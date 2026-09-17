import Foundation
import Security
import XCTest
#if APP_STORE
@testable import SIDEYAppStore
#else
@testable import SIDEY
#endif

@MainActor
final class SpringMessageRecoveryTests: XCTestCase {
    func testLiveMaximumNeverAdvancesCompletedRecoveryCheckpoint() throws {
        let fixture = RecoveryFixtureData()
        var ledger = SpringMessageLedger()
        let completed = fixture.cursor(10)
        ledger.confirmRecovery(through: completed)
        _ = try ledger.merge(fixture.message(100))
        _ = try ledger.merge(fixture.message(50)) // Earlier transaction committed later.
        XCTAssertEqual(ledger.confirmedCursor, completed)
        XCTAssertEqual(ledger.messages.map(\.id), [fixture.id(50), fixture.id(100)])
        ledger.confirmRecovery(through: fixture.cursor(100))
        XCTAssertEqual(ledger.confirmedCursor, fixture.cursor(100))
    }

    func testHistoryAndLiveOverlapMergeByUUIDAndRetainCanonicalBubbleSnapshot() throws {
        let fixture = RecoveryFixtureData()
        var ledger = SpringMessageLedger()
        let canonical = fixture.message(20)
        XCTAssertTrue(try ledger.merge(canonical))
        for index in 0...40 { _ = try ledger.merge(fixture.message(index)) }
        XCTAssertFalse(try ledger.merge(canonical))
        XCTAssertEqual(ledger.messages.count, 41)
        XCTAssertEqual(ledger.messages.first(where: { $0.id == canonical.id })?.bubbleStyleID, "bubble_bunny_pink")
        XCTAssertNil(ledger.confirmedCursor, "Partial page merging must never implicitly complete recovery")
    }

    func testBoundedViewEvictsOldestRowsWithoutChangingCheckpoint() throws {
        let fixture = RecoveryFixtureData()
        var ledger = SpringMessageLedger(capacity: 3)
        let completed = fixture.cursor(1)
        ledger.confirmRecovery(through: completed)
        for index in (0..<8).reversed() { _ = try ledger.merge(fixture.message(index)) }
        XCTAssertEqual(ledger.messages.map(\.id), [fixture.id(5), fixture.id(6), fixture.id(7)])
        XCTAssertEqual(ledger.confirmedCursor, completed)
    }

    func testFailedRetryRetainsUUIDOnlyForSameRoomSenderBodyWithinRetention() {
        let fixture = RecoveryFixtureData()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let id = fixture.id(1)
        var outbox = MessageOutbox()
        outbox.stage(id: id, roomID: fixture.room, senderID: fixture.user, body: "original", createdAt: now)
        XCTAssertNil(outbox.retryID(roomID: fixture.room, senderID: fixture.user, body: "original", now: now))
        _ = outbox.fail(id: id, roomID: fixture.room)
        XCTAssertEqual(outbox.retryID(roomID: fixture.room, senderID: fixture.user, body: "original", now: now.addingTimeInterval(60)), id)
        XCTAssertNil(outbox.retryID(roomID: fixture.room, senderID: fixture.user, body: "edited", now: now))
        XCTAssertNil(outbox.retryID(roomID: fixture.id(2), senderID: fixture.user, body: "original", now: now))
        XCTAssertNil(outbox.retryID(roomID: fixture.room, senderID: fixture.id(2), body: "original", now: now))
        XCTAssertNil(outbox.retryID(roomID: fixture.room, senderID: fixture.user, body: "original", now: now.addingTimeInterval(3 * 86_400)))
        outbox.stage(id: id, roomID: fixture.room, senderID: fixture.user, body: "original", createdAt: now.addingTimeInterval(60))
        XCTAssertEqual(outbox.entries.count, 1)
        XCTAssertEqual(outbox.entries.first?.state, .pending)
        XCTAssertEqual(outbox.entries.first?.createdAt, now, "Restaging cannot extend the original retention guarantee")
        XCTAssertNil(outbox.retryID(roomID: fixture.room, senderID: fixture.user, body: "original", now: now))
    }

    func testGatewaySubscribesBeforeReadingAllPagesAndMergesLiveBeyondCheckpoint() async throws {
        let fixture = try RecoveryGatewayFixture()
        let snapshot = try await fixture.backend.boot()
        let result = try await fixture.backend.syncRealtime(rooms: snapshot.rooms, activeRoomID: fixture.data.room)
        XCTAssertEqual(result.activeMessages.count, 231)
        XCTAssertEqual(Set(result.activeMessages.map(\.id)).count, 231)
        XCTAssertEqual(result.activeMessages.map(\.id), (0...230).map(fixture.data.id))
        let queries = fixture.server.historyQueries
        XCTAssertEqual(queries.count, 2, "Recovery must continue beyond the old recent-50 window and the first 200 rows")
        XCTAssertNil(queries.first?["afterId"])
        XCTAssertEqual(queries.last?["afterId"]?.lowercased(), fixture.data.id(199).uuidString.lowercased())
        XCTAssertTrue(queries.allSatisfy { $0["throughCreatedAt"] == fixture.data.timestamp(229) })
        XCTAssertTrue(fixture.server.everyHistoryRequestWasSubscribed)
        _ = try await fixture.backend.syncRealtime(rooms: snapshot.rooms, activeRoomID: fixture.data.room)
        XCTAssertEqual(fixture.server.historyQueries.last?["afterId"]?.lowercased(), fixture.data.id(229).uuidString.lowercased(),
            "The live row beyond the completed checkpoint cannot advance the next REST recovery cursor")
        await fixture.backend.shutdown()
        fixture.close()
    }

    func testFailedSecondRecoveryPageDoesNotConfirmPartialCheckpoint() async throws {
        let fixture = try RecoveryGatewayFixture(failSecondPageOnce: true)
        let snapshot = try await fixture.backend.boot()
        do {
            _ = try await fixture.backend.syncRealtime(rooms: snapshot.rooms, activeRoomID: fixture.data.room)
            XCTFail("Synthetic second page failure must abort recovery")
        } catch { /* Partial rows may merge, but the checkpoint must remain unconfirmed. */ }
        let result = try await fixture.backend.syncRealtime(rooms: snapshot.rooms, activeRoomID: fixture.data.room)
        XCTAssertEqual(result.activeMessages.count, 231)
        let queries = fixture.server.historyQueries
        XCTAssertEqual(queries.count, 4)
        XCTAssertNil(queries[2]["afterId"], "Retry must restart from the last completed checkpoint, not the partial first page")
        XCTAssertEqual(Set(result.activeMessages.map(\.id)).count, 231)
        await fixture.backend.shutdown()
        fixture.close()
    }

    func testEquipmentClearSendsExplicitNullThroughAuthenticatedREST() async throws {
        let fixture = try RecoveryGatewayFixture()
        _ = try await fixture.backend.boot()
        _ = try await fixture.backend.setEquippedCosmetic(kind: .throwable, catalogItemID: nil)
        XCTAssertTrue(fixture.server.receivedEquipmentClear)
        await fixture.backend.shutdown()
        fixture.close()
    }

    func testSilentMembershipRemovalRefreshesSnapshotAndClearsRoomWithoutSocketEvent() async throws {
        let fixture = try RecoveryGatewayFixture(membershipPollInterval: .milliseconds(20))
        let snapshot = try await fixture.backend.boot()
        _ = try await fixture.backend.syncRealtime(rooms: snapshot.rooms, activeRoomID: fixture.data.room)
        var removed = false
        let reader = Task { @MainActor in
            for await event in fixture.backend.events {
                if case .snapshot(let snapshot) = event, snapshot.rooms.isEmpty { removed = true; return }
            }
        }
        defer { reader.cancel() }
        fixture.server.removeMembership()
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !removed {
            guard ContinuousClock.now < deadline else { return XCTFail("Membership poll never observed removal") }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(fixture.server.returnedRemovedSnapshot)
        do { _ = try await fixture.backend.recentMessages(roomID: fixture.data.room); XCTFail("Removed room cache must not remain readable") }
        catch { XCTAssertEqual(error as? SideyBackendError, .membershipRequired) }
        await fixture.backend.shutdown()
        fixture.close()
    }

    func testCheckoutPollingReadsExactServerOrder() async throws {
        let fixture = try RecoveryGatewayFixture()
        _ = try await fixture.backend.boot()
        let status = try await fixture.backend.commerceOrderStatus(orderID: fixture.data.id(800))
        XCTAssertEqual(status, "failed")
        await fixture.backend.shutdown()
        fixture.close()
    }

    func testGenericAccountDeletionUsesAuthenticatedEmptyResponseContract() async throws {
        let fixture = try RecoveryGatewayFixture()
        _ = try await fixture.backend.boot()
        try await fixture.backend.deleteAccount()
        XCTAssertTrue(fixture.server.receivedAuthenticatedDelete)
        await fixture.backend.shutdown()
        fixture.close()
    }

    func testAccountDeletionReauthenticationAndOtherErrorsPreserveLocalIdentity() async throws {
        for (status, code) in [(400, "apple_reauthentication_required"), (403, "account_delete_forbidden")] {
            let fixture = try RecoveryGatewayFixture(accountStatus: status, accountCode: code)
            _ = try await fixture.backend.boot()
            do { try await fixture.backend.deleteAccount(); XCTFail("Deletion rejection must propagate") }
            catch { XCTAssertEqual(error as? SideyBackendError, .remote(code)) }
            let retainedUser = await fixture.backend.currentUserID()
            XCTAssertEqual(retainedUser, fixture.data.user)
            XCTAssertTrue(fixture.server.receivedAuthenticatedDelete)
            await fixture.backend.shutdown()
            fixture.close()
        }
    }

    func testGatewayRetryKeepsLogicalUUIDRoomBodyAndAcceptsCanonicalAck() async throws {
        let fixture = try RecoveryGatewayFixture()
        let snapshot = try await fixture.backend.boot()
        _ = try await fixture.backend.syncRealtime(rooms: snapshot.rooms, activeRoomID: fixture.data.room)
        let id = fixture.data.id(999)
        let body = "재시도해도 같은 메시지"
        do {
            _ = try await fixture.backend.sendMessage(roomID: fixture.data.room, body: body, id: id)
            XCTFail("First synthetic server rejection must fail")
        } catch { /* The same logical attempt is retried below. */ }
        let canonical = try await fixture.backend.sendMessage(roomID: fixture.data.room, body: body, id: id)
        let attempts = fixture.server.messageAttempts
        XCTAssertEqual(attempts.count, 2)
        for attempt in attempts {
            XCTAssertEqual(attempt["id"]?.lowercased(), id.uuidString.lowercased())
            XCTAssertEqual(attempt["roomId"]?.lowercased(), fixture.data.room.uuidString.lowercased())
            XCTAssertEqual(attempt["body"], body)
        }
        XCTAssertNotEqual(attempts[0]["requestId"], attempts[1]["requestId"], "Command correlation is separate from durable message identity")
        XCTAssertEqual(canonical.id, id)
        XCTAssertEqual(canonical.body, body)
        XCTAssertEqual(canonical.bubbleStyleID, "bubble_bunny_pink")
        await fixture.backend.shutdown()
        fixture.close()
    }
}

private struct RecoveryFixtureData: Sendable {
    let room = UUID(uuidString: "00000000-0000-0000-0001-000000000001")!
    let user = UUID(uuidString: "00000000-0000-0000-0002-000000000001")!
    func id(_ index: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", index + 1))! }
    func timestamp(_ index: Int) -> String { String(format: "2099-01-01T09:00:00.%06d+09:00", index) }
    func cursor(_ index: Int) -> SpringCursor { SpringCursor(createdAt: timestamp(index), id: id(index)) }
    func message(_ index: Int) -> SpringMessage {
        SpringMessage(id: id(index), roomId: room, senderId: user, body: "message \(index)",
            bubbleStyleId: "bubble_bunny_pink", createdAt: timestamp(index))
    }
    func messageJSON(_ index: Int) -> [String: Any] {
        ["id": id(index).uuidString, "roomId": room.uuidString, "senderId": user.uuidString,
         "body": "message \(index)", "bubbleStyleId": "bubble_bunny_pink", "createdAt": timestamp(index)]
    }
    var profileJSON: [String: Any] {
        ["id": user.uuidString, "nickname": "테스트", "characterId": "pixel_hamster", "treeMovementPaused": false,
         "treeMovementRevision": 0]
    }
    var roomJSON: [String: Any] {
        ["id": room.uuidString, "name": "테스트 방", "ownerId": user.uuidString, "inviteCodeHint": "ABCD",
         "inviteVersion": 1, "members": [["userId": user.uuidString, "profile": profileJSON]]]
    }
}

private final class RecoveryGatewayFixture {
    let data = RecoveryFixtureData()
    let backend: SideyBackend
    let server: RecoveryProtocolServer
    private let network: URLSession
    private let host: String
    init(failSecondPageOnce: Bool = false, accountStatus: Int = 204, accountCode: String = "",
         membershipPollInterval: Duration = .seconds(30)) throws {
        host = "recovery-\(UUID().uuidString.lowercased()).invalid"
        let config = RuntimeConfiguration(apiBaseURL: URL(string: "https://\(host)/api")!)
        server = RecoveryProtocolServer(data: data, failSecondPageOnce: failSecondPageOnce,
            accountStatus: accountStatus, accountCode: accountCode)
        RecoveryURLProtocol.servers.register(server, host: host)
        let networkConfig = URLSessionConfiguration.ephemeral
        networkConfig.protocolClasses = [RecoveryURLProtocol.self]
        network = URLSession(configuration: networkConfig)
        let stored = try JSONSerialization.data(withJSONObject: [
            "accessToken": "test-access", "refreshToken": "test-refresh", "userId": data.user.uuidString,
            "sessionId": UUID().uuidString, "accessExpiresAt": "2099-01-01T00:00:00Z"
        ])
        let keychain = KeychainStore(service: host, session: KeychainAccessSession(security: RecoveryStoredSession(stored)))
        let session = SideySessionClient(configuration: config, keychain: keychain, network: network)
        let socket = RecoveryProtocolSocket(server: server)
        let transport = SpringRealtimeTransport(heartbeatInterval: .seconds(3_600), socketFactory: { _ in socket })
        backend = SideyBackend(configuration: config, keychain: keychain, networkPathMonitor: RecoveryNetworkMonitor(),
            session: session, transport: transport, membershipPollInterval: membershipPollInterval)
    }
    func close() {
        network.invalidateAndCancel()
        RecoveryURLProtocol.servers.remove(host: host)
    }
}

private final class RecoveryProtocolServer: @unchecked Sendable {
    let data: RecoveryFixtureData
    private let lock = NSLock()
    private var subscribed = false
    private var queries: [[String: String]] = []
    private var attempts: [[String: String]] = []
    private var ordered = true
    private var equipmentClear = false
    private var authenticatedDelete = false
    private var membershipRemoved = false
    private var removedSnapshot = false
    private let accountStatus: Int
    private let accountCode: String
    private let failSecondPageOnce: Bool
    init(data: RecoveryFixtureData, failSecondPageOnce: Bool, accountStatus: Int, accountCode: String) {
        self.data = data
        self.failSecondPageOnce = failSecondPageOnce
        self.accountStatus = accountStatus
        self.accountCode = accountCode
    }
    var historyQueries: [[String: String]] { lock.withLock { queries } }
    var messageAttempts: [[String: String]] { lock.withLock { attempts } }
    var everyHistoryRequestWasSubscribed: Bool { lock.withLock { ordered } }
    var receivedEquipmentClear: Bool { lock.withLock { equipmentClear } }
    var receivedAuthenticatedDelete: Bool { lock.withLock { authenticatedDelete } }
    var returnedRemovedSnapshot: Bool { lock.withLock { removedSnapshot } }
    func removeMembership() { lock.withLock { membershipRemoved = true } }

    func reply(_ request: URLRequest) throws -> (Int, Data) {
        let result: (Int, Any) = lock.withLock {
            guard let url = request.url else { return (400, ["code": "invalid_url"]) }
            if url.path == "/api/account" {
                authenticatedDelete = request.httpMethod == "DELETE"
                    && request.value(forHTTPHeaderField: "Authorization") == "Bearer test-access"
                return (accountStatus, ["code": accountCode])
            }
            if url.path == "/api/profile" { return (200, data.profileJSON) }
            if url.path == "/api/profile/equipment" {
                var bytes = request.httpBody
                if bytes == nil, let stream = request.httpBodyStream {
                    stream.open()
                    defer { stream.close() }
                    var content = Data()
                    var buffer = [UInt8](repeating: 0, count: 1_024)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        if count <= 0 { break }
                        content.append(contentsOf: buffer.prefix(count))
                    }
                    bytes = content
                }
                let body = bytes.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                equipmentClear = request.httpMethod == "PUT"
                    && request.value(forHTTPHeaderField: "Authorization") == "Bearer test-access"
                    && body?["kind"] as? String == "throwable" && body?["catalogItemId"] is NSNull
                return (200, data.profileJSON)
            }
            if url.path == "/api/rooms" {
                if membershipRemoved { removedSnapshot = true; return (200, []) }
                return (200, [data.roomJSON])
            }
            if url.path == "/api/commerce/orders/\(data.id(800))" {
                return (200, ["id": data.id(800).uuidString, "status": "failed"])
            }
            if url.path == "/api/commerce/entitlements" { return (200, []) }
            if url.path.hasSuffix("/messages") {
                if membershipRemoved { return (403, ["code": "membership_required"]) }
                ordered = ordered && subscribed
                // Real Spring request parameters use form decoding. A literal '+'
                // loses the timezone offset; URLComponents alone would hide this.
                if URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery?.contains("+") == true {
                    return (400, ["code": "invalid_request"])
                }
                let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
                queries.append(query)
                if failSecondPageOnce && queries.count == 2 { return (503, ["code": "recovery_page_unavailable"]) }
                let after = query["afterId"].flatMap(UUID.init(uuidString:))
                let start = after.flatMap { value in (0..<230).firstIndex(where: { data.id($0) == value }).map { $0 + 1 } } ?? 0
                let end = min(230, start + (Int(query["limit"] ?? "50") ?? 50))
                let next: Any = end < 230 ? ["createdAt": data.timestamp(end - 1), "id": data.id(end - 1).uuidString] : NSNull()
                return (200, ["messages": (start..<end).map(data.messageJSON), "nextCursor": next])
            }
            return (404, ["code": "message_missing"])
        }
        return (result.0, result.0 == 204 ? Data() : try JSONSerialization.data(withJSONObject: result.1))
    }

    func command(_ text: String) throws -> [Data] {
        guard let body = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: String],
              let type = body["type"] else { return [] }
        return try lock.withLock {
            if type == "subscribe" {
                subscribed = true
                return try [
                    ["type": "message.created", "message": data.messageJSON(230)],
                    ["type": "ack", "requestId": body["requestId"]!, "recoveryThrough": ["createdAt": data.timestamp(229), "id": data.id(229).uuidString]]
                ].map { try JSONSerialization.data(withJSONObject: $0) }
            }
            if type == "message.send" {
                attempts.append(body)
                if attempts.count == 1 {
                    return [try JSONSerialization.data(withJSONObject: ["type": "error", "requestId": body["requestId"]!, "code": "internal_error"])]
                }
                var message = data.messageJSON(999)
                message["id"] = body["id"]
                message["body"] = body["body"]
                return [try JSONSerialization.data(withJSONObject: ["type": "message.ack", "requestId": body["requestId"]!, "message": message])]
            }
            return []
        }
    }
}

private final class RecoveryServerRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: RecoveryProtocolServer] = [:]
    func register(_ server: RecoveryProtocolServer, host: String) { lock.withLock { values[host] = server } }
    func remove(host: String) { _ = lock.withLock { values.removeValue(forKey: host) } }
    func server(host: String) -> RecoveryProtocolServer? { lock.withLock { values[host] } }
}
private final class RecoveryURLProtocol: URLProtocol, @unchecked Sendable {
    static let servers = RecoveryServerRegistry()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix(".invalid") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let url = request.url, let server = Self.servers.server(host: url.host ?? "") else { throw URLError(.badURL) }
            let (status, data) = try server.reply(request)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private final class RecoveryProtocolSocket: SpringRealtimeSocket, @unchecked Sendable {
    private let server: RecoveryProtocolServer
    private let stream = AsyncThrowingStream<Data, Error>.makeStream()
    init(server: RecoveryProtocolServer) { self.server = server }
    func resume() { stream.continuation.yield(Data(#"{"type":"connected","connectionId":"test"}"#.utf8)) }
    func cancel() { stream.continuation.finish(throwing: CancellationError()) }
    func receive() async throws -> Data {
        var iterator = stream.stream.makeAsyncIterator()
        guard let next = try await iterator.next() else { throw CancellationError() }
        return next
    }
    func send(_ text: String) async throws {
        for frame in try server.command(text) { stream.continuation.yield(frame) }
    }
}
private struct RecoveryNetworkMonitor: NetworkPathMonitoring {
    let updates = AsyncStream<NetworkAvailability> { $0.finish() }
    func start() {}
    func cancel() {}
}
private struct RecoveryStoredSession: KeychainSecurityPerforming {
    let stored: Data
    init(_ stored: Data) { self.stored = stored }
    func copyMatching(_ query: CFDictionary) -> (status: OSStatus, data: Data?) {
        let account = (query as NSDictionary)[kSecAttrAccount] as? String ?? ""
        return account.hasPrefix("sidey-session:") ? (errSecSuccess, stored) : (errSecItemNotFound, nil)
    }
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus { errSecSuccess }
    func add(_ attributes: CFDictionary) -> OSStatus { errSecSuccess }
    func delete(_ query: CFDictionary) -> OSStatus { errSecSuccess }
}
