import Foundation

/// Serializes complete Presence publications while retaining only the newest
/// state that has not started yet. Callers whose intermediate state is
/// coalesced complete with the newer full publication.
actor PresencePublicationQueue<State: Sendable> {
    typealias Publish = @Sendable (State) async throws -> Void

    private struct Pending: Sendable {
        let revision: UInt64
        let state: State
    }

    private let publish: Publish
    private var nextRevision: UInt64 = 0
    private var latest: Pending?
    private var waiters: [UInt64: CheckedContinuation<Void, any Error>] = [:]
    private var worker: Task<Void, Never>?

    init(publish: @escaping Publish) {
        self.publish = publish
    }

    func submit(_ state: State) async throws {
        nextRevision &+= 1
        let revision = nextRevision
        latest = Pending(revision: revision, state: state)

        try await withCheckedThrowingContinuation { continuation in
            waiters[revision] = continuation
            startWorkerIfNeeded()
        }
    }

    func cancel() {
        worker?.cancel()
        worker = nil
        latest = nil
        let pendingWaiters = waiters.values
        waiters.removeAll()
        for waiter in pendingWaiters {
            waiter.resume(throwing: CancellationError())
        }
    }

    private func startWorkerIfNeeded() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        while !Task.isCancelled, let pending = latest {
            latest = nil
            do {
                try await publish(pending.state)
                resumeWaiters(through: pending.revision, result: .success(()))
            } catch {
                // A newer full state can still repair a failed partial batch.
                // Keep older callers waiting for that state instead of making
                // a transient superseded failure observable.
                if latest != nil { continue }
                resumeWaiters(through: pending.revision, result: .failure(error))
            }
        }
        worker = nil
        if latest != nil { startWorkerIfNeeded() }
    }

    private func resumeWaiters(
        through revision: UInt64,
        result: Result<Void, any Error>
    ) {
        let completed = waiters.keys.filter { $0 <= revision }
        for key in completed {
            guard let waiter = waiters.removeValue(forKey: key) else { continue }
            waiter.resume(with: result)
        }
    }
}
