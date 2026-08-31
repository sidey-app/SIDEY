import AppKit
import CoreGraphics
import Foundation

/// Publishes only the derived online/away state. It never reads event contents or mouse coordinates.
@MainActor
final class SystemActivityMonitor {
    nonisolated static let anyInputEventType = CGEventType(rawValue: UInt32.max)!

    private let awayThreshold: TimeInterval
    private let idleSecondsProvider: () -> TimeInterval
    private let screenLockedProvider: () -> Bool
    private let onChange: (PresenceState) -> Void
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastState: PresenceState?

    init(
        awayThreshold: TimeInterval = 5 * 60,
        idleSecondsProvider: @escaping () -> TimeInterval = {
            CGEventSource.secondsSinceLastEventType(
                .combinedSessionState,
                eventType: SystemActivityMonitor.anyInputEventType
            )
        },
        screenLockedProvider: @escaping () -> Bool = SystemActivityMonitor.currentScreenLocked,
        onChange: @escaping (PresenceState) -> Void
    ) {
        self.awayThreshold = awayThreshold
        self.idleSecondsProvider = idleSecondsProvider
        self.screenLockedProvider = screenLockedProvider
        self.onChange = onChange
    }

    func start() {
        guard timer == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.publish(screenLockedOverride: true)
                }
            },
            center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.publish(screenLockedOverride: false)
                }
            }
        ]
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.publish() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        publish()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }

    func refresh() {
        publish()
    }

    nonisolated static func state(
        screenLocked: Bool,
        idleSeconds: TimeInterval,
        awayThreshold: TimeInterval
    ) -> PresenceState {
        (screenLocked || idleSeconds >= awayThreshold) ? .away : .online
    }

    nonisolated static func currentScreenLocked() -> Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    private func publish(screenLockedOverride: Bool? = nil) {
        let state = Self.state(
            screenLocked: screenLockedOverride ?? screenLockedProvider(),
            idleSeconds: idleSecondsProvider(),
            awayThreshold: awayThreshold
        )
        guard state != lastState else { return }
        lastState = state
        onChange(state)
    }
}
