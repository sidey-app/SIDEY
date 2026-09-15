import Foundation
import Observation

/// Profile revisions are global to a user, including snapshots from other rooms.
@MainActor
@Observable
final class TreeMovementState {
    struct Value: Equatable {
        let paused: Bool
        let revision: Int64?
    }
    struct Request: Equatable {
        let id = UUID()
        let userID: UUID
        let paused: Bool
        let expectedRevision: Int64
    }
    private(set) var confirmed: [UUID: Value] = [:]
    private(set) var pending: Request?
    private var migrationAttempted: Set<UUID> = []

    @discardableResult
    func accept(userID: UUID, paused: Bool, revision: Int64?) -> Value {
        let candidate = Value(paused: paused, revision: revision.map { max(0, $0) })
        if let previous = confirmed[userID],
           (previous.revision ?? -1) >= (candidate.revision ?? -1) {
            return previous
        }
        confirmed[userID] = candidate
        return candidate
    }

    /// The legacy preference remains visible until migration is confirmed, including a failed attempt.
    func effectivePaused(userID: UUID, currentUserID: UUID?, legacyPaused: Bool) -> Bool {
        let value = confirmed[userID]
        if let revision = value?.revision, revision >= 1 { return value?.paused ?? false }
        return userID == currentUserID && legacyPaused
    }

    func begin(userID: UUID, paused: Bool, migrating: Bool = false) -> Request? {
        guard pending == nil, let current = confirmed[userID],
              let revision = current.revision else { return nil }
        if migrating {
            guard current.revision == 0, migrationAttempted.insert(userID).inserted else { return nil }
        }
        let request = Request(userID: userID, paused: paused, expectedRevision: revision)
        pending = request
        return request
    }

    /// Request identity prevents a stale completion from clearing a new account's request.
    @discardableResult
    func finish(_ request: Request) -> Bool {
        guard pending == request else { return false }
        pending = nil
        return true
    }

    func cancelPending() { pending = nil }

    func reset() {
        confirmed.removeAll()
        pending = nil
        migrationAttempted.removeAll()
    }
}
