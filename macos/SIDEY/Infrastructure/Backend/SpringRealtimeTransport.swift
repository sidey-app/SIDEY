import Foundation

/// Socket-only boundary. Room recovery and durable UUID merging belong to the backend client.
actor SpringRealtimeTransport {
    enum Event: Sendable {
        case frame(Data, generation: UUID)
        case closed(generation: UUID)
    }

    enum Failure: Error, Equatable, Sendable {
        case disconnected
        case timeout
        case invalidFrame
        case frameTooLarge
        case tooManyCommands
        case duplicateRequestID
        case outboundBackpressure
        case server(String)
    }

    nonisolated let events: AsyncStream<Event>
    private let eventContinuation: AsyncStream<Event>.Continuation
    private let socketFactory: @Sendable (URLRequest) -> any SpringRealtimeSocket
    private let heartbeatInterval: Duration
    private let handshakeTimeout: Duration
    private let inboundTimeout: Duration
    private let watchdogInterval: Duration
    private let sendTimeout: Duration
    private let pendingLimit: Int
    private var generation = UUID()
    private var socket: (any SpringRealtimeSocket)?
    private var reader: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var lastInbound: ContinuousClock.Instant?
    private var handshakeTimer: Task<Void, Never>?
    private var handshake: CheckedContinuation<Void, Error>?
    private var ready = false

    private struct Pending {
        let token: UUID
        let continuation: CheckedContinuation<Data, Error>
        let timer: Task<Void, Never>
    }
    private var pending: [String: Pending] = [:]
    private struct Sending {
        let continuation: CheckedContinuation<Void, Error>
        let timer: Task<Void, Never>
        let task: Task<Void, Never>
    }
    private var outgoing: [UUID: Sending] = [:]
    private static let maximumFrameSize = 16_384

    init(
        eventBufferLimit: Int = 256,
        pendingLimit: Int = 64,
        heartbeatInterval: Duration = .seconds(20),
        handshakeTimeout: Duration = .seconds(15),
        inboundTimeout: Duration = .seconds(60),
        watchdogInterval: Duration = .seconds(5),
        sendTimeout: Duration = .seconds(15),
        socketFactory: @escaping @Sendable (URLRequest) -> any SpringRealtimeSocket = {
            URLSessionSpringSocket(request: $0)
        }
    ) {
        let stream = AsyncStream<Event>.makeStream(bufferingPolicy: .bufferingNewest(max(1, eventBufferLimit)))
        events = stream.stream
        eventContinuation = stream.continuation
        self.socketFactory = socketFactory
        self.pendingLimit = max(1, pendingLimit)
        self.heartbeatInterval = heartbeatInterval
        self.handshakeTimeout = handshakeTimeout
        self.inboundTimeout = inboundTimeout
        self.watchdogInterval = watchdogInterval
        self.sendTimeout = sendTimeout
    }

    deinit {
        reader?.cancel()
        heartbeat?.cancel()
        watchdog?.cancel()
        handshakeTimer?.cancel()
        socket?.cancel()
        eventContinuation.finish()
    }

    /// Returns only after the server has accepted the SIDEY session. Token expiry does
    /// not affect this connection; explicit server revocation still closes it.
    func connect(baseURL: URL, accessToken: String) async throws {
        terminate(error: Failure.disconnected, notify: false)
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              components.scheme == "https" || components.scheme == "http",
              components.host != nil, components.user == nil, components.password == nil,
              !accessToken.isEmpty, !accessToken.contains("\r"), !accessToken.contains("\n") else {
            throw Failure.invalidFrame
        }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/api/realtime"
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw Failure.invalidFrame }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let connection = socketFactory(request)
        let current = generation
        socket = connection
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                handshake = continuation
                handshakeTimer = Task { [weak self, handshakeTimeout] in
                    do { try await Task.sleep(for: handshakeTimeout) } catch { return }
                    await self?.failed(Failure.timeout, generation: current)
                }
                connection.resume()
                reader = Task { [weak self] in
                    do {
                        while !Task.isCancelled {
                            let frame = try await connection.receive()
                            guard await self?.received(frame, generation: current) == true else { return }
                        }
                    } catch {
                        await self?.failed(error, generation: current)
                    }
                }
            }
        } onCancel: {
            Task { await self.failed(CancellationError(), generation: current) }
        }
    }

    /// Use for commands which return an ACK (subscribe, unsubscribe, message.send,
    /// ping). Presence and transient updates use send instead.
    func command(_ payload: Data, requestID: String, timeout: Duration = .seconds(15)) async throws -> Data {
        guard ready, socket != nil else { throw Failure.disconnected }
        guard pending.count < pendingLimit else { throw Failure.tooManyCommands }
        guard pending[requestID] == nil else { throw Failure.duplicateRequestID }
        guard !requestID.isEmpty, requestID.utf16.count <= 128,
              requestID.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }),
              var object = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw Failure.invalidFrame
        }
        object["requestId"] = requestID
        let data = try JSONSerialization.data(withJSONObject: object)
        let text = try validatedText(data)
        guard outgoing.count < pendingLimit else { throw Failure.outboundBackpressure }
        let current = generation
        let token = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let timer = Task { [weak self] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    await self?.expire(requestID: requestID, token: token, generation: current)
                }
                pending[requestID] = Pending(token: token, continuation: continuation, timer: timer)
                Task { [weak self] in
                    do { try await self?.write(text, generation: current) }
                    catch { await self?.reject(requestID: requestID, token: token, generation: current, error: error) }
                }
            }
        } onCancel: {
            Task { await self.cancel(requestID: requestID, token: token, generation: current) }
        }
    }

    func send(_ payload: Data) async throws {
        let text = try validatedText(payload)
        try await write(text, generation: generation)
    }

    /// A separate timer owns completion even if the platform write never returns.
    /// Closing a partly written socket is safer than reusing an ambiguous stream.
    private func write(_ text: String, generation current: UUID) async throws {
        guard current == generation, ready, let socket else { throw Failure.disconnected }
        guard outgoing.count < pendingLimit else { throw Failure.outboundBackpressure }
        let token = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                let timer = Task { [weak self, sendTimeout] in
                    do { try await Task.sleep(for: sendTimeout) } catch { return }
                    await self?.writeTimedOut(token, generation: current)
                }
                let task = Task { [weak self] in
                    do {
                        try await socket.send(text)
                        await self?.writeFinished(token, generation: current)
                    } catch {
                        await self?.failed(error, generation: current)
                    }
                }
                outgoing[token] = Sending(continuation: continuation, timer: timer, task: task)
            }
        } onCancel: {
            Task { await self.writeCancelled(token, generation: current) }
        }
    }

    func disconnect() {
        terminate(error: Failure.disconnected, notify: true)
    }

    func isCurrent(_ event: Event) -> Bool {
        switch event {
        case .frame(_, let value), .closed(let value): return value == generation
        }
    }

    private func validatedText(_ data: Data) throws -> String {
        guard data.count <= Self.maximumFrameSize else { throw Failure.frameTooLarge }
        guard let text = String(data: data, encoding: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String, !type.isEmpty else { throw Failure.invalidFrame }
        return text
    }

    private func received(_ data: Data, generation current: UUID) -> Bool {
        guard current == generation, socket != nil else { return false }
        guard data.count <= Self.maximumFrameSize else {
            failed(Failure.frameTooLarge, generation: current)
            return false
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            failed(Failure.invalidFrame, generation: current)
            return false
        }
        lastInbound = ContinuousClock.now
        if !ready {
            guard type == "connected" else {
                failed(Failure.invalidFrame, generation: current)
                return false
            }
            ready = true
            handshakeTimer?.cancel()
            handshakeTimer = nil
            handshake?.resume()
            handshake = nil
            heartbeat = Task { [weak self, heartbeatInterval] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: heartbeatInterval) } catch { return }
                    guard await self?.sendHeartbeat(generation: current) == true else { return }
                }
            }
            watchdog = Task { [weak self, watchdogInterval] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: watchdogInterval) } catch { return }
                    guard await self?.checkInbound(generation: current) == true else { return }
                }
            }
        }
        if let requestID = object["requestId"] as? String,
           ["ack", "message.ack", "pong", "error"].contains(type),
           let waiting = pending.removeValue(forKey: requestID) {
            waiting.timer.cancel()
            if type == "error" {
                waiting.continuation.resume(throwing: Failure.server(object["code"] as? String ?? "unknown_error"))
            } else {
                waiting.continuation.resume(returning: data)
            }
            return true
        }
        if type == "heartbeat.ack" { return true }
        // If any durable frame is evicted, close and let the consumer run REST
        // catch-up. The final closed event replaces a buffered frame and remains
        // observable even when the consumer was temporarily stalled.
        switch eventContinuation.yield(.frame(data, generation: current)) {
        case .dropped(let displaced):
            if isDurable(displaced) {
                failed(Failure.disconnected, generation: current)
                return false
            }
        case .terminated:
            failed(Failure.disconnected, generation: current)
            return false
        case .enqueued: break
        @unknown default:
            failed(Failure.disconnected, generation: current)
            return false
        }
        return true
    }

    private func isDurable(_ event: Event) -> Bool {
        guard case .frame(let data, _) = event,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return true }
        return !["presence", "typing", "character.pulse", "character.throw", "heartbeat.ack", "pong", "connected"].contains(type)
    }

    private func sendHeartbeat(generation current: UUID) async -> Bool {
        guard current == generation, ready else { return false }
        do { try await send(Data(#"{"type":"heartbeat"}"#.utf8)); return true }
        catch { return false }
    }

    private func expire(requestID: String, token: UUID, generation current: UUID) {
        guard current == generation, pending[requestID]?.token == token,
              let waiting = pending.removeValue(forKey: requestID) else { return }
        waiting.continuation.resume(throwing: Failure.timeout)
    }

    private func checkInbound(generation current: UUID) -> Bool {
        guard current == generation, ready, let lastInbound else { return false }
        guard lastInbound.duration(to: .now) < inboundTimeout else {
            failed(Failure.timeout, generation: current)
            return false
        }
        return true
    }

    private func writeFinished(_ token: UUID, generation current: UUID) {
        guard current == generation, let writing = outgoing.removeValue(forKey: token) else { return }
        writing.timer.cancel()
        writing.continuation.resume()
    }

    private func writeTimedOut(_ token: UUID, generation current: UUID) {
        guard current == generation, outgoing[token] != nil else { return }
        failed(Failure.timeout, generation: current)
    }

    private func writeCancelled(_ token: UUID, generation current: UUID) {
        guard current == generation, outgoing[token] != nil else { return }
        failed(CancellationError(), generation: current)
    }

    private func reject(requestID: String, token: UUID, generation current: UUID, error: Error) {
        guard current == generation, pending[requestID]?.token == token,
              let waiting = pending.removeValue(forKey: requestID) else { return }
        waiting.timer.cancel()
        waiting.continuation.resume(throwing: error)
    }

    private func cancel(requestID: String, token: UUID, generation current: UUID) {
        guard current == generation, pending[requestID]?.token == token,
              let waiting = pending.removeValue(forKey: requestID) else { return }
        waiting.timer.cancel()
        waiting.continuation.resume(throwing: CancellationError())
    }

    private func failed(_ error: Error, generation current: UUID) {
        guard current == generation else { return }
        terminate(error: error, notify: true)
    }

    private func terminate(error: Error, notify: Bool) {
        let hadConnection = socket != nil
        generation = UUID()
        ready = false
        reader?.cancel()
        reader = nil
        heartbeat?.cancel()
        heartbeat = nil
        watchdog?.cancel()
        watchdog = nil
        lastInbound = nil
        handshakeTimer?.cancel()
        handshakeTimer = nil
        socket?.cancel()
        socket = nil
        let writing = outgoing.values
        outgoing.removeAll()
        for write in writing {
            write.timer.cancel()
            write.task.cancel()
            write.continuation.resume(throwing: error)
        }
        handshake?.resume(throwing: error)
        handshake = nil
        let waiting = pending.values
        pending.removeAll()
        for command in waiting {
            command.timer.cancel()
            command.continuation.resume(throwing: error)
        }
        if hadConnection && notify { eventContinuation.yield(.closed(generation: generation)) }
    }
}

/// Narrow injectable socket boundary: deterministic tests can control incoming
/// ACKs, failed reads and delayed old-connection reads without network access.
protocol SpringRealtimeSocket: Sendable {
    func resume()
    func receive() async throws -> Data
    func send(_ text: String) async throws
    func cancel()
}

private struct URLSessionSpringSocket: SpringRealtimeSocket {
    private let task: URLSessionWebSocketTask

    init(request: URLRequest) {
        task = URLSession.shared.webSocketTask(with: request)
        task.maximumMessageSize = 16_384
    }

    func resume() { task.resume() }
    func cancel() { task.cancel(with: .goingAway, reason: nil) }
    func send(_ text: String) async throws { try await task.send(.string(text)) }
    func receive() async throws -> Data {
        switch try await task.receive() {
        case .data(let data): return data
        case .string(let text): return Data(text.utf8)
        @unknown default: throw SpringRealtimeTransport.Failure.invalidFrame
        }
    }
}
