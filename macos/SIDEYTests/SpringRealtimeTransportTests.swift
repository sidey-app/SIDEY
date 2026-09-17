import Foundation
import XCTest
#if APP_STORE
@testable import SIDEYAppStore
#else
@testable import SIDEY
#endif

@MainActor
final class SpringRealtimeTransportTests: XCTestCase {
    private let origin = URL(string: "https://sidey.example/ignored?secret=discarded")!

    func testHandshakeUsesAuthorizationHeaderAndCommandsCorrelateWithoutConsumingLiveMessages() async throws {
        let socket = ControlledSpringSocket()
        let transport = makeTransport(socket)
        try await transport.connect(baseURL: origin, accessToken: "access-token")
        XCTAssertEqual(socket.request?.url?.absoluteString, "wss://sidey.example/api/realtime")
        XCTAssertEqual(socket.request?.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        let command = Task {
            try await transport.command(json(#"{"type":"subscribe","roomId":"room"}"#), requestID: "subscribe-1")
        }
        let sent = await socket.nextSent()
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(sent.utf8)) as? [String: String])
        XCTAssertEqual(object["requestId"], "subscribe-1")
        socket.push(#"{"type":"message.created","message":{"id":"committed"}}"#)
        socket.push(#"{"type":"ack","requestId":"subscribe-1","recoveryThrough":null}"#)
        let response = try await command.value
        XCTAssertTrue(String(decoding: response, as: UTF8.self).contains("recoveryThrough"))
        var events = transport.events.makeAsyncIterator()
        _ = await events.next() // connected
        guard case .frame(let live, _) = await events.next() else { return XCTFail("Missing live frame") }
        XCTAssertTrue(String(decoding: live, as: UTF8.self).contains("committed"))
        await transport.disconnect()
        guard case .closed = await events.next() else { return XCTFail("Missing close event") }
    }

    func testTimeoutReleasesCorrelationAndServerErrorFailsOnlyItsCommand() async throws {
        let socket = ControlledSpringSocket()
        let transport = makeTransport(socket)
        try await transport.connect(baseURL: origin, accessToken: "access-token")
        do {
            _ = try await transport.command(json(#"{"type":"ping"}"#), requestID: "retry", timeout: .milliseconds(25))
            XCTFail("Expected timeout")
        } catch { XCTAssertEqual(error as? SpringRealtimeTransport.Failure, .timeout) }
        _ = await socket.nextSent()
        let retry = Task { try await transport.command(json(#"{"type":"ping"}"#), requestID: "retry") }
        _ = await socket.nextSent()
        socket.push(#"{"type":"error","requestId":"retry","code":"membership_required"}"#)
        do { _ = try await retry.value; XCTFail("Expected server error") }
        catch { XCTAssertEqual(error as? SpringRealtimeTransport.Failure, .server("membership_required")) }
        let next = Task { try await transport.command(json(#"{"type":"ping"}"#), requestID: "next") }
        _ = await socket.nextSent()
        socket.push(#"{"type":"pong","requestId":"next"}"#)
        _ = try await next.value
        await transport.disconnect()
    }

    func testBoundedPendingCommandsAndDisconnectRejectAllWaiters() async throws {
        let socket = ControlledSpringSocket()
        let transport = makeTransport(socket, pendingLimit: 1)
        try await transport.connect(baseURL: origin, accessToken: "access-token")
        let waiting = Task { try await transport.command(json(#"{"type":"ping"}"#), requestID: "first") }
        _ = await socket.nextSent()
        do {
            _ = try await transport.command(json(#"{"type":"ping"}"#), requestID: "second")
            XCTFail("Expected bounded pending map")
        } catch { XCTAssertEqual(error as? SpringRealtimeTransport.Failure, .tooManyCommands) }
        await transport.disconnect()
        do { _ = try await waiting.value; XCTFail("Expected disconnect") }
        catch { XCTAssertEqual(error as? SpringRealtimeTransport.Failure, .disconnected) }
        XCTAssertEqual(socket.cancelCount, 1)
    }

    func testOldReaderCannotCloseOrPublishIntoReplacementConnection() async throws {
        let old = ControlledSpringSocket(holdReadAfterCancel: true)
        let new = ControlledSpringSocket()
        let sockets = ControlledSpringSocketFactory([old, new])
        let transport = SpringRealtimeTransport(heartbeatInterval: .seconds(3_600), socketFactory: { sockets.next($0) })
        try await transport.connect(baseURL: origin, accessToken: "old-token")
        try await transport.connect(baseURL: origin, accessToken: "new-token")
        old.push(#"{"type":"message.created","message":{"id":"stale"}}"#)
        let ping = Task { try await transport.command(json(#"{"type":"ping"}"#), requestID: "new") }
        _ = await new.nextSent()
        new.push(#"{"type":"pong","requestId":"new"}"#)
        _ = try await ping.value
        await transport.disconnect()
        var events = transport.events.makeAsyncIterator()
        var frames: [String] = []
        while let event = await events.next() {
            if case .closed = event { break }
            if case .frame(let data, _) = event { frames.append(String(decoding: data, as: UTF8.self)) }
        }
        XCTAssertEqual(frames.count, 2) // The two accepted handshakes only.
        XCTAssertFalse(frames.contains(where: { $0.contains("stale") }))
    }

    func testDurableEventOverflowClosesInsteadOfSilentlyLosingCommittedMessage() async throws {
        let socket = ControlledSpringSocket()
        let transport = makeTransport(socket, eventBufferLimit: 1)
        try await transport.connect(baseURL: origin, accessToken: "access-token")
        socket.push(#"{"type":"message.created","message":{"id":"one"}}"#)
        socket.push(#"{"type":"message.created","message":{"id":"two"}}"#)
        await socket.waitForCancel()
        var events = transport.events.makeAsyncIterator()
        guard case .closed = await events.next() else { return XCTFail("Overflow must remain observable for REST recovery") }
        XCTAssertEqual(socket.cancelCount, 1)
    }

    func testOversizedOutgoingFrameFailsBeforeSendingAndHandshakeTimeoutCancelsSocket() async throws {
        let socket = ControlledSpringSocket()
        let transport = makeTransport(socket)
        try await transport.connect(baseURL: origin, accessToken: "access-token")
        do {
            try await transport.send(json("{\"type\":\"typing\",\"value\":\"\(String(repeating: "a", count: 16_384))\"}"))
            XCTFail("Expected size limit")
        } catch { XCTAssertEqual(error as? SpringRealtimeTransport.Failure, .frameTooLarge) }
        await transport.disconnect()
        let stalled = ControlledSpringSocket(autoConnect: false)
        let waiting = SpringRealtimeTransport(handshakeTimeout: .milliseconds(25), socketFactory: { _ in stalled })
        do {
            try await waiting.connect(baseURL: origin, accessToken: "access-token")
            XCTFail("Expected handshake timeout")
        } catch { XCTAssertEqual(error as? SpringRealtimeTransport.Failure, .timeout) }
        XCTAssertEqual(stalled.cancelCount, 1)
    }

    func testHeartbeatUsesServerCommandWithoutRequestCorrelation() async throws {
        let socket = ControlledSpringSocket()
        let transport = SpringRealtimeTransport(heartbeatInterval: .milliseconds(25), socketFactory: { _ in socket })
        try await transport.connect(baseURL: origin, accessToken: "access-token")
        let heartbeat = await socket.nextSent()
        XCTAssertEqual(heartbeat, #"{"type":"heartbeat"}"#)
        await transport.disconnect()
    }

    func testQueuedFramesAndCloseFromPreviousConnectionAreRejectedAfterReconnect() async throws {
        let sockets = ControlledSpringSocketFactory([ControlledSpringSocket(), ControlledSpringSocket()])
        let transport = SpringRealtimeTransport(heartbeatInterval: .seconds(3_600), socketFactory: { sockets.next($0) })
        try await transport.connect(baseURL: origin, accessToken: "old")
        await transport.disconnect()
        try await transport.connect(baseURL: origin, accessToken: "new")
        var events = transport.events.makeAsyncIterator()
        let first = await events.next(), second = await events.next(), third = await events.next()
        let oldFrame = try XCTUnwrap(first)
        let oldClose = try XCTUnwrap(second)
        let newFrame = try XCTUnwrap(third)
        let oldFrameAccepted = await transport.isCurrent(oldFrame)
        let oldCloseAccepted = await transport.isCurrent(oldClose)
        let newFrameAccepted = await transport.isCurrent(newFrame)
        XCTAssertFalse(oldFrameAccepted)
        XCTAssertFalse(oldCloseAccepted)
        XCTAssertTrue(newFrameAccepted)
        await transport.disconnect()
    }

    func testCancelledCommandFreesPendingCapacityWithoutClosingConnection() async throws {
        let socket = ControlledSpringSocket()
        let transport = makeTransport(socket, pendingLimit: 1)
        try await transport.connect(baseURL: origin, accessToken: "access-token")
        let cancelled = Task { try await transport.command(json(#"{"type":"ping"}"#), requestID: "cancelled") }
        _ = await socket.nextSent()
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        let replacement = Task { try await transport.command(json(#"{"type":"ping"}"#), requestID: "replacement") }
        _ = await socket.nextSent()
        socket.push(#"{"type":"pong","requestId":"replacement"}"#)
        _ = try await replacement.value
        XCTAssertEqual(socket.cancelCount, 0)
        await transport.disconnect()
    }

    func testOversizedIncomingFrameClosesAndRequiresRecovery() async throws {
        let socket = ControlledSpringSocket()
        let transport = makeTransport(socket)
        try await transport.connect(baseURL: origin, accessToken: "access-token")
        socket.push(String(repeating: "a", count: 16_385))
        await socket.waitForCancel()
        var events = transport.events.makeAsyncIterator()
        _ = await events.next() // connected
        guard case .closed = await events.next() else { return XCTFail("Oversized incoming data must close") }
    }

    func testSilentSocketClosesEvenWhenHeartbeatWritesSucceed() async throws {
        let socket = ControlledSpringSocket()
        let transport = SpringRealtimeTransport(heartbeatInterval: .milliseconds(10),
            inboundTimeout: .milliseconds(80), watchdogInterval: .milliseconds(10), socketFactory: { _ in socket })
        try await transport.connect(baseURL: origin, accessToken: "token")
        let heartbeat = await socket.nextSent()
        XCTAssertEqual(heartbeat, #"{"type":"heartbeat"}"#)
        await socket.waitForCancel()
        var events = transport.events.makeAsyncIterator()
        _ = await events.next()
        guard case .closed = await events.next() else { return XCTFail("Silent socket must trigger recovery") }
        XCTAssertEqual(socket.cancelCount, 1)
    }

    func testHungWriteDeadlineFailsCallerAndPendingCommands() async throws {
        let socket = ControlledSpringSocket(blockSends: true)
        let transport = SpringRealtimeTransport(heartbeatInterval: .seconds(3_600),
            sendTimeout: .milliseconds(80), socketFactory: { _ in socket })
        try await transport.connect(baseURL: origin, accessToken: "token")
        let waiting = Task { try await transport.command(json(#"{"type":"ping"}"#), requestID: "pending") }
        _ = await socket.nextSent()
        do {
            try await transport.send(json(#"{"type":"typing","active":true}"#))
            XCTFail("Hung write must not wait forever")
        } catch { XCTAssertEqual(error as? SpringRealtimeTransport.Failure, .timeout) }
        do { _ = try await waiting.value; XCTFail("Pending command must fail with transport") }
        catch { XCTAssertEqual(error as? SpringRealtimeTransport.Failure, .timeout) }
        XCTAssertEqual(socket.cancelCount, 1)
    }

    func testInboundWatchdogIsIndependentOfHungHeartbeatWrite() async throws {
        let socket = ControlledSpringSocket(blockSends: true)
        let transport = SpringRealtimeTransport(heartbeatInterval: .milliseconds(10),
            inboundTimeout: .milliseconds(80), watchdogInterval: .milliseconds(10),
            sendTimeout: .seconds(3_600), socketFactory: { _ in socket })
        try await transport.connect(baseURL: origin, accessToken: "token")
        _ = await socket.nextSent()
        await socket.waitForCancel()
        XCTAssertEqual(socket.cancelCount, 1)
    }

    func testCancelledHungWriteClosesOnlyItsConnection() async throws {
        let old = ControlledSpringSocket(blockSends: true)
        let new = ControlledSpringSocket()
        let sockets = ControlledSpringSocketFactory([old, new])
        let transport = SpringRealtimeTransport(heartbeatInterval: .seconds(3_600),
            socketFactory: { sockets.next($0) })
        try await transport.connect(baseURL: origin, accessToken: "old")
        let sending = Task { try await transport.send(json(#"{"type":"heartbeat"}"#)) }
        _ = await old.nextSent()
        sending.cancel()
        do { try await sending.value; XCTFail("Expected write cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        try await transport.connect(baseURL: origin, accessToken: "new")
        try await transport.send(json(#"{"type":"heartbeat"}"#))
        XCTAssertEqual(new.cancelCount, 0)
        await transport.disconnect()
    }

    func testHeartbeatAcknowledgementsKeepReplacementConnectionAlive() async throws {
        let old = ControlledSpringSocket()
        let new = ControlledSpringSocket()
        let sockets = ControlledSpringSocketFactory([old, new])
        let transport = SpringRealtimeTransport(heartbeatInterval: .milliseconds(20),
            inboundTimeout: .milliseconds(200), watchdogInterval: .milliseconds(10),
            socketFactory: { sockets.next($0) })
        try await transport.connect(baseURL: origin, accessToken: "old")
        try await transport.connect(baseURL: origin, accessToken: "new")
        for _ in 0..<15 {
            _ = await new.nextSent()
            new.push(#"{"type":"heartbeat.ack"}"#)
        }
        XCTAssertEqual(old.cancelCount, 1)
        XCTAssertEqual(new.cancelCount, 0)
        await transport.disconnect()
    }

    private func makeTransport(_ socket: ControlledSpringSocket, eventBufferLimit: Int = 256, pendingLimit: Int = 64) -> SpringRealtimeTransport {
        SpringRealtimeTransport(eventBufferLimit: eventBufferLimit, pendingLimit: pendingLimit, heartbeatInterval: .seconds(3_600)) {
            socket.setRequest($0)
            return socket
        }
    }
}

private func json(_ text: String) -> Data { Data(text.utf8) }

private final class ControlledSpringSocket: SpringRealtimeSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var incoming: [Data] = []
    private var receivers: [CheckedContinuation<Data, Error>] = []
    private var cancellations: [CheckedContinuation<Void, Never>] = []
    private var cancelled = 0
    private var capturedRequest: URLRequest?
    private let outgoing = AsyncStream<String>.makeStream()
    private let holdReadAfterCancel: Bool
    private let autoConnect: Bool
    private let blockSends: Bool
    private var blockedSends: [CheckedContinuation<Void, Error>] = []

    init(holdReadAfterCancel: Bool = false, autoConnect: Bool = true, blockSends: Bool = false) {
        self.holdReadAfterCancel = holdReadAfterCancel
        self.autoConnect = autoConnect
        self.blockSends = blockSends
    }

    var request: URLRequest? { lock.withLock { capturedRequest } }
    var cancelCount: Int { lock.withLock { cancelled } }
    func setRequest(_ request: URLRequest) { lock.withLock { capturedRequest = request } }
    func resume() { if autoConnect { push(#"{"type":"connected","connectionId":"test"}"#) } }
    func send(_ text: String) async throws {
        outgoing.continuation.yield(text)
        if blockSends {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.withLock {
                    if cancelled > 0 { continuation.resume(throwing: CancellationError()) }
                    else { blockedSends.append(continuation) }
                }
            }
        }
    }
    func nextSent() async -> String {
        var iterator = outgoing.stream.makeAsyncIterator()
        return await iterator.next() ?? ""
    }
    func receive() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                if !incoming.isEmpty { continuation.resume(returning: incoming.removeFirst()) }
                else if cancelled > 0 && !holdReadAfterCancel { continuation.resume(throwing: CancellationError()) }
                else { receivers.append(continuation) }
            }
        }
    }
    func push(_ frame: String) {
        lock.withLock {
            if receivers.isEmpty { incoming.append(json(frame)) }
            else { receivers.removeFirst().resume(returning: json(frame)) }
        }
    }
    func cancel() {
        lock.withLock {
            cancelled += 1
            for sender in blockedSends { sender.resume(throwing: CancellationError()) }
            blockedSends.removeAll()
            if !holdReadAfterCancel {
                for receiver in receivers { receiver.resume(throwing: CancellationError()) }
                receivers.removeAll()
            }
            for waiter in cancellations { waiter.resume() }
            cancellations.removeAll()
        }
    }
    func waitForCancel() async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if cancelled > 0 { continuation.resume() }
                else { cancellations.append(continuation) }
            }
        }
    }
}

private final class ControlledSpringSocketFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var sockets: [ControlledSpringSocket]
    init(_ sockets: [ControlledSpringSocket]) { self.sockets = sockets }
    func next(_ request: URLRequest) -> ControlledSpringSocket {
        lock.withLock {
            let socket = sockets.removeFirst()
            socket.setRequest(request)
            return socket
        }
    }
}
