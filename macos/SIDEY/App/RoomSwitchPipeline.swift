import Foundation

@MainActor
final class RoomSwitchPipeline {
    typealias Switch = @MainActor (UUID) async throws -> [ChatMessage]
    typealias Restore = @MainActor () async throws -> Void

    private struct Request {
        let generation: UInt64
        let roomID: UUID
        let notBefore: ContinuousClock.Instant
    }

    private let debounce: Duration
    private let performSwitch: Switch
    private let restoreCommittedRoom: Restore
    private let operationChanged: @MainActor (GroupOperation) -> Void
    private let committed: @MainActor (UUID, [ChatMessage]) -> Void
    private let failed: @MainActor (UUID, any Error, (any Error)?) -> Void
    private var generation: UInt64 = 0
    private var pending: Request?
    private var worker: Task<Void, Never>?

    init(
        debounce: Duration,
        performSwitch: @escaping Switch,
        restoreCommittedRoom: @escaping Restore,
        operationChanged: @escaping @MainActor (GroupOperation) -> Void,
        committed: @escaping @MainActor (UUID, [ChatMessage]) -> Void,
        failed: @escaping @MainActor (UUID, any Error, (any Error)?) -> Void
    ) {
        self.debounce = debounce
        self.performSwitch = performSwitch
        self.restoreCommittedRoom = restoreCommittedRoom
        self.operationChanged = operationChanged
        self.committed = committed
        self.failed = failed
    }

    func request(_ roomID: UUID) {
        generation &+= 1
        pending = Request(
            generation: generation,
            roomID: roomID,
            notBefore: ContinuousClock.now.advanced(by: debounce)
        )
        operationChanged(.switching(roomID))
        startWorkerIfNeeded()
    }

    func cancel() {
        generation &+= 1
        pending = nil
        worker?.cancel()
        worker = nil
        operationChanged(.idle)
    }

    private func startWorkerIfNeeded() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        while !Task.isCancelled, let request = pending {
            do {
                try await ContinuousClock().sleep(until: request.notBefore)
            } catch {
                break
            }
            guard !Task.isCancelled else { break }
            guard pending?.generation == request.generation else { continue }
            pending = nil

            do {
                let messages = try await performSwitch(request.roomID)
                guard isCurrent(request) else { continue }
                committed(request.roomID, messages)
                operationChanged(.idle)
            } catch {
                guard isCurrent(request) else { continue }
                let restoreError: (any Error)?
                do {
                    try await restoreCommittedRoom()
                    restoreError = nil
                } catch {
                    restoreError = error
                }
                guard isCurrent(request) else { continue }
                failed(request.roomID, error, restoreError)
                operationChanged(.idle)
            }
        }
        worker = nil
        if pending != nil { startWorkerIfNeeded() }
    }

    private func isCurrent(_ request: Request) -> Bool {
        generation == request.generation && pending == nil
    }
}
