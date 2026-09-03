import Foundation
import Network

enum NetworkAvailability: Equatable, Sendable {
    case available
    case unavailable

    init(pathStatus: NWPath.Status) {
        switch pathStatus {
        case .satisfied:
            self = .available
        case .unsatisfied, .requiresConnection:
            self = .unavailable
        @unknown default:
            self = .unavailable
        }
    }
}

enum NetworkAvailabilityTransition: Equatable, Sendable {
    case unchanged
    case initialAvailable
    case becameUnavailable
    case becameAvailable
}

struct NetworkAvailabilityState: Equatable, Sendable {
    private(set) var current: NetworkAvailability?

    mutating func update(_ next: NetworkAvailability) -> NetworkAvailabilityTransition {
        guard current != next else { return .unchanged }
        let previous = current
        current = next

        switch (previous, next) {
        case (nil, .available):
            return .initialAvailable
        case (_, .unavailable):
            return .becameUnavailable
        case (.unavailable, .available):
            return .becameAvailable
        case (.available, .available):
            return .unchanged
        }
    }
}

protocol NetworkPathMonitoring: Sendable {
    var updates: AsyncStream<NetworkAvailability> { get }

    func start()
    func cancel()
}

final class SystemNetworkPathMonitor: NetworkPathMonitoring, @unchecked Sendable {
    let updates: AsyncStream<NetworkAvailability>

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "app.sidey.desktop.network-path")
    private let continuation: AsyncStream<NetworkAvailability>.Continuation
    private let lock = NSLock()
    private var started = false

    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
        let pair = AsyncStream<NetworkAvailability>.makeStream(bufferingPolicy: .bufferingNewest(1))
        updates = pair.stream
        continuation = pair.continuation
        monitor.pathUpdateHandler = { [continuation] path in
            continuation.yield(NetworkAvailability(pathStatus: path.status))
        }
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        started = true
        monitor.start(queue: queue)
    }

    func cancel() {
        lock.lock()
        let shouldCancel = started
        started = false
        lock.unlock()
        guard shouldCancel else { return }
        monitor.cancel()
        continuation.finish()
    }
}
