#if !APP_STORE
import AppKit
import AVFoundation
import CoreAudio

struct CharacterImpactAdmission {
    private var lastStart: TimeInterval = -.infinity
    mutating func accept(at time: TimeInterval, activeVoices: Int, enabled: Bool) -> Bool {
        guard enabled, time.isFinite, activeVoices < 4, time - lastStart >= 0.080 else { return false }
        lastStart = time
        return true
    }
    mutating func reset() { lastStart = -.infinity }
}

@MainActor
final class CharacterImpactAudio {
    static let objectIDs = ["patch_soft_ball", "mini_paprika", "banana", "dust_bath_pouch",
                            "starlight_orb", "throwable_bouncy_heart", "throwable_squeaky_duck", "throwable_toy_cannon"]
    var isEnabled = true { didSet { if !isEnabled { stopAll() } } }
    private var players: [String: [AVAudioPlayer]] = [:]
    private var admission = CharacterImpactAdmission()
    private(set) var resourceErrors: [String] = []
    private(set) var playCount = 0
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var outputListener: AudioObjectPropertyListenerBlock?
    private var outputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    init(bundle: Bundle = .main) {
        for id in Self.objectIDs {
            do {
                guard let url = bundle.url(forResource: "impact-\(id)", withExtension: "wav") else {
                    throw CocoaError(.fileNoSuchFile)
                }
                players[id] = try (0..<4).map { _ in
                    let player = try AVAudioPlayer(contentsOf: url)
                    player.prepareToPlay()
                    return player
                }
            } catch { resourceErrors.append(id) }
        }
        let events: [(NotificationCenter, Notification.Name)] = [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidSleepNotification),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.sessionDidResignActiveNotification),
            (DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked"))
        ]
        for (center, name) in events {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stopAll() }
            }
            observers.append((center, token))
        }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.stopAll() }
        }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &outputAddress, .main, listener) == noErr {
            outputListener = listener
        }
    }

    isolated deinit {
        for (center, token) in observers { center.removeObserver(token) }
        if let outputListener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &outputAddress, .main, outputListener)
        }
        for player in players.values.flatMap({ $0 }) { player.stop() }
    }

    var activeVoiceCount: Int { players.values.flatMap { $0 }.filter(\.isPlaying).count }

    @discardableResult
    func play(objectID: String, at time: TimeInterval) -> Bool {
        guard !SystemActivityMonitor.currentScreenLocked(), let player = players[objectID]?.first(where: { !$0.isPlaying }),
              admission.accept(at: time, activeVoices: activeVoiceCount, enabled: isEnabled)
        else { return false }
        player.currentTime = 0
        guard player.play() else { return false }
        playCount += 1
        return true
    }

    func stopAll() {
        for player in players.values.flatMap({ $0 }) {
            player.stop()
            player.currentTime = 0
        }
        admission.reset()
    }
}
#endif
