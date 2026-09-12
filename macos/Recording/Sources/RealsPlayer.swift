#if (DEBUG && !APP_STORE) || SIDEY_REALS
import AppKit
import Combine
import SpriteKit

@MainActor
final class RealsPlayer: ObservableObject {
    enum State { case ready, playing, paused, finished }
    @Published private(set) var state: State = .ready
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var delivered = 0
    @Published private(set) var performed = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var overlayVisible = false
    private(set) var scene: PixelWorldScene?
    private var view: SKView?
    private var panel: NSPanel?
    private var timeline: RealsTimeline?
    private var timer: Timer?
    private var lastTick = 0.0
    private var nextAction = 0
    private var lastPresentation: RealsTimeline.Presentation?
    private let audio = CharacterImpactAudio()

    var isEditingLocked: Bool { state == .playing || state == .paused }
    var status: String {
        if state == .playing && elapsed < 0 { return "\(Int(ceil(-elapsed)))초 뒤 시작" }
        switch state {
        case .ready: return "촬영 준비"
        case .playing: return "재생 중"
        case .paused: return "일시정지"
        case .finished: return "재생 완료"
        }
    }

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(pauseForSleep),
                                                          name: NSWorkspace.willSleepNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    isolated deinit {
        timer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    func preview(_ project: RealsProject) throws {
        _ = try project.validated()
        stop()
        timeline = RealsTimeline(project: project)
        elapsed = -project.countdown
        duration = timeline?.duration ?? 0
        createOverlay(project)
        applyPresentation(at: -100)
    }

    func start(_ project: RealsProject) throws {
        guard !project.lines.isEmpty || !project.actions.isEmpty else {
            throw RealsProject.InvalidProject(message: "채팅이나 액션을 하나 이상 추가하세요.")
        }
        try preview(project)
        state = .playing
        audio.isEnabled = project.soundEnabled
        lastTick = ProcessInfo.processInfo.systemUptime
        view?.isPaused = false
        advance(by: 0)
        let ticker = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer = ticker
        RunLoop.main.add(ticker, forMode: .common)
    }

    func pauseOrResume() {
        switch state {
        case .playing:
            state = .paused
            view?.isPaused = true
            audio.stopAll()
        case .paused:
            lastTick = ProcessInfo.processInfo.systemUptime
            state = .playing
            view?.isPaused = false
        default: break
        }
    }

    private func tick() {
        guard state == .playing else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let delta = max(0, now - lastTick)
        lastTick = now
        // Never dump a backlog of actions after sleep or a long app stall.
        guard delta < 0.5 else { pauseOrResume(); return }
        advance(by: delta)
    }

    func advance(by delta: Double) {
        guard state == .playing, let timeline, delta.isFinite, delta >= 0 else { return }
        elapsed = min(duration, elapsed + delta)
        applyPresentation(at: elapsed)
        while nextAction < timeline.actionEvents.count, timeline.actionEvents[nextAction].second <= elapsed {
            let event = timeline.actionEvents[nextAction]
            let action = event.action
            if action.kind == .pulse {
                scene?.playLocalPreviewPulse(memberID: action.actorID, at: max(0, elapsed))
            } else if let target = action.targetID,
                      let actor = timeline.project.participants.first(where: { $0.id == action.actorID }) {
                scene?.playLocalPreviewThrow(CharacterThrowEvent(id: event.id, roomID: timeline.roomID,
                    actorUserID: actor.id, targetUserID: target, sourceCharacterID: actor.characterID,
                    throwableID: action.throwableID))
            }
            nextAction += 1
            performed = nextAction
        }
        if elapsed >= duration {
            state = .finished
            timer?.invalidate()
            timer = nil
            view?.isPaused = true
            audio.stopAll()
        }
    }

    private func createOverlay(_ project: RealsProject) {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let size = CGSize(width: min(project.overlayWidth, screen.width), height: min(420, screen.height))
        let panel = NSPanel(contentRect: CGRect(x: screen.midX - size.width / 2, y: screen.minY,
                                               width: size.width, height: size.height),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        PixelWorldRendererPolicy.apply(to: view)
        let fractions = Dictionary(uniqueKeysWithValues: project.participants.enumerated().map {
            ($0.element.id, CGFloat($0.offset + 1) / CGFloat(project.participants.count + 1))
        })
        let config = PixelWorldRenderingConfiguration(pulsePeakScale: PixelCharacterPulseStyle.peakScale,
            initialTrackFractions: fractions, fixedTrackFractions: project.fixedPositions ? fractions : [:],
            minimumTrackInset: 40, allowsLocalPreviewEvents: true)
        let scene = PixelWorldScene(size: size, renderingConfiguration: config,
                                   clock: { [weak self] in max(0, self?.elapsed ?? 0) }, usesPlaybackClock: true)
        scene.onCharacterImpact = { [weak self] id, _ in
            self?.audio.play(objectID: id, at: ProcessInfo.processInfo.systemUptime)
        }
        scene.onStopCharacterSounds = { [weak self] in self?.audio.stopAll() }
        view.presentScene(scene)
        panel.contentView = view
        self.scene = scene
        self.view = view
        self.panel = panel
        panel.orderFrontRegardless()
        overlayVisible = true
    }

    private func applyPresentation(at time: Double) {
        guard let timeline else { return }
        let presentation = timeline.presentation(at: time)
        delivered = presentation.delivered
        guard presentation != lastPresentation else { return }
        lastPresentation = presentation
        scene?.apply(roomID: timeline.roomID, members: presentation.members, bubbles: presentation.bubbles,
                     edge: .bottom, installationSeed: 77)
    }

    @objc private func pauseForSleep() {
        if state == .playing { pauseOrResume() }
    }

    @objc private func screenChanged() {
        // A changed recording region needs a fresh take; do not silently crop an active take.
        stop()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        audio.stopAll()
        scene?.cancelLocalPreviewPlayback()
        view?.isPaused = true
        view?.presentScene(nil)
        panel?.close()
        panel = nil
        view = nil
        scene = nil
        timeline = nil
        lastPresentation = nil
        nextAction = 0
        elapsed = 0
        delivered = 0
        performed = 0
        duration = 0
        state = .ready
        overlayVisible = false
    }
}
#endif
