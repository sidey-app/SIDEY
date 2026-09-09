#if !APP_STORE
import Foundation

/// Scene-owned transient state, shared with the local input gate. Never persisted or broadcast.
@MainActor
final class CharacterStunState {
    static let window: TimeInterval = 10
    static let threshold = 10
    static let duration: TimeInterval = 6
    private var hits: [UUID: [TimeInterval]] = [:]
    private(set) var startedAt: [UUID: TimeInterval] = [:]
    private let now: () -> TimeInterval

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
    }

    func isStunned(_ id: UUID) -> Bool { isStunned(id, at: now()) }

    func isStunned(_ id: UUID, at time: TimeInterval) -> Bool {
        startedAt[id].map { time < $0 + Self.duration } ?? false
    }

    /// The scene deduplicates throw event IDs before creating a projectile.
    @discardableResult
    func recordHit(_ id: UUID, at time: TimeInterval) -> Bool {
        guard !isStunned(id, at: time) else { return false }
        startedAt.removeValue(forKey: id)
        var recent = (hits[id] ?? []).filter { $0 >= time - Self.window }
        recent.append(time)
        if recent.count >= Self.threshold {
            hits.removeValue(forKey: id)
            startedAt[id] = time
            return true
        }
        hits[id] = recent
        return false
    }

    func advance(to time: TimeInterval) {
        startedAt = startedAt.filter { time < $0.value + Self.duration }
        for id in Array(hits.keys) {
            hits[id]?.removeAll { $0 < time - Self.window }
            if hits[id]?.isEmpty == true { hits.removeValue(forKey: id) }
        }
    }

    func remove(_ id: UUID) {
        hits.removeValue(forKey: id)
        startedAt.removeValue(forKey: id)
    }

    func reset() {
        hits.removeAll()
        startedAt.removeAll()
    }
}
#endif
