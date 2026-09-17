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

    func testFreshSameBodySendIsNewWhileExplicitRetryKeepsOriginalSnapshot() throws {
        let state = AppMessageState(), room = UUID(), sender = UUID(), now = Date(timeIntervalSince1970: 1_000_000)
        let first = state.stageNewMessage(roomID: room, senderID: sender, body: "same", now: now, activeRoomID: room, equippedBubbleStyleID: nil)
        _ = state.failMessage(id: first.id, roomID: room)
        let second = state.stageNewMessage(roomID: room, senderID: sender, body: "same", now: now.addingTimeInterval(1), activeRoomID: room, equippedBubbleStyleID: nil)
        XCTAssertNotEqual(first.id, second.id)
        let retried = try XCTUnwrap(state.retryMessage(id: first.id, roomID: room, senderID: sender,
            now: now.addingTimeInterval(2), activeRoomID: room, equippedBubbleStyleID: nil))
        XCTAssertEqual(retried.id, first.id)
        XCTAssertEqual(retried.body, first.body)
        XCTAssertEqual(retried.createdAt, first.createdAt)
        XCTAssertEqual(state.messageOutbox.entries.first(where: { $0.id == first.id })?.state, .pending)
        XCTAssertNil(state.retryMessage(id: first.id, roomID: room, senderID: sender, now: now, activeRoomID: room, equippedBubbleStyleID: nil))
    }

    func testFailedRetryCandidatesRejectWrongOwnerRoomExpiredAndOverCapacity() {
        let data = RecoveryFixtureData(), now = Date(timeIntervalSince1970: 1_000_000)
        var outbox = MessageOutbox()
        for index in 0...50 {
            outbox.stage(id: data.id(index), roomID: data.room, senderID: data.user, body: "same", createdAt: now.addingTimeInterval(Double(index)))
            _ = outbox.fail(id: data.id(index), roomID: data.room)
        }
        XCTAssertEqual(outbox.entries.count, 50)
        XCTAssertNil(outbox.retryCandidate(id: data.id(0), roomID: data.room, senderID: data.user, now: now))
        XCTAssertNil(outbox.retryCandidate(id: data.id(1), roomID: UUID(), senderID: data.user, now: now))
        XCTAssertNil(outbox.retryCandidate(id: data.id(1), roomID: data.room, senderID: UUID(), now: now))
        XCTAssertNil(outbox.retryCandidate(id: data.id(1), roomID: data.room, senderID: data.user, now: now.addingTimeInterval(1 + MessageLedger.retentionInterval)))
        outbox.pruneFailed(now: now.addingTimeInterval(50 + MessageLedger.retentionInterval))
        XCTAssertTrue(outbox.entries.isEmpty)
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

    func testDirectRoomRevocationClearsCachedMessagesWithoutSnapshotPoll() async throws {
        let fixture = try RecoveryGatewayFixture()
        let snapshot = try await fixture.backend.boot()
        _ = try await fixture.backend.syncRealtime(rooms: snapshot.rooms, activeRoomID: fixture.data.room)
        let revoked = expectation(description: "Direct revocation received")
        let observed = Task { @MainActor in
            for await event in fixture.backend.events {
                if case .roomRevoked(let room, _) = event, room == fixture.data.room { revoked.fulfill(); return }
            }
        }
        defer { observed.cancel() }
        fixture.server.removeMembership()
        await fulfillment(of: [revoked], timeout: 2)
        XCTAssertFalse(fixture.server.returnedRemovedSnapshot, "Revocation must act immediately without a REST poll")
        do { _ = try await fixture.backend.recentMessages(roomID: fixture.data.room); XCTFail("Removed cache remained readable") }
        catch { XCTAssertEqual(error as? SideyBackendError, .membershipRequired) }
        do { try await fixture.backend.setActiveRoom(fixture.data.room); XCTFail("A late focus callback restored revoked active room") }
        catch { XCTAssertEqual(error as? SideyBackendError, .membershipRequired) }
        let attempts = fixture.server.messageAttempts.count
        do { _ = try await fixture.backend.sendMessage(roomID: fixture.data.room, body: "blocked"); XCTFail("Revoked room allowed send") }
        catch { XCTAssertEqual(error as? SideyBackendError, .membershipRequired) }
        XCTAssertEqual(fixture.server.messageAttempts.count, attempts)
        fixture.server.restoreMembership()
        let rejoined = try await fixture.backend.syncRealtime(rooms: snapshot.rooms, activeRoomID: fixture.data.room)
        XCTAssertEqual(rejoined.snapshot.rooms.map(\.id), [fixture.data.room], "A fresh authoritative rejoin must be allowed after revocation")
        XCTAssertEqual(rejoined.activeMessages.count, 231)
        await fixture.backend.shutdown(); fixture.close()
    }

    func testDirectRoomRevocationIsHandledWithoutRoomSubscription() async throws {
        let fixture = try RecoveryGatewayFixture(emptyRooms: true)
        let snapshot = try await fixture.backend.boot()
        _ = try await fixture.backend.syncRealtime(rooms: snapshot.rooms, activeRoomID: nil)
        let revoked = expectation(description: "Direct revocation received")
        let observed = Task { @MainActor in
            for await event in fixture.backend.events {
                if case .roomRevoked(let room, _) = event, room == fixture.data.room { revoked.fulfill(); return }
            }
        }
        defer { observed.cancel() }
        fixture.server.removeMembership()
        await fulfillment(of: [revoked], timeout: 2)
        XCTAssertTrue(fixture.server.historyQueries.isEmpty)
        await fixture.backend.shutdown(); fixture.close()
    }

    func testRevocationCancelsInFlightRecoveryAndRejectsLateHistoryOrSnapshot() async throws {
        for holdSnapshot in [false, true] {
            let fixture = try RecoveryGatewayFixture(holdHistory: !holdSnapshot)
            let snapshot = try await fixture.backend.boot()
            if holdSnapshot {
                _ = try await fixture.backend.syncRealtime(rooms: snapshot.rooms, activeRoomID: fixture.data.room)
                fixture.server.holdNextSnapshot()
            }
            let recovering = Task { try await fixture.backend.syncRealtime(rooms: snapshot.rooms, activeRoomID: fixture.data.room) }
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while !fixture.server.historyResponseHeld {
                guard ContinuousClock.now < deadline else { return XCTFail("Recovery request did not reach gate") }
                try await Task.sleep(for: .milliseconds(2))
            }
            let revoked = expectation(description: "Recovery interrupted by revocation")
            let observed = Task { @MainActor in
                for await event in fixture.backend.events {
                    if case .roomRevoked = event { revoked.fulfill(); return }
                }
            }
            defer { observed.cancel() }
            fixture.server.removeMembership()
            await fulfillment(of: [revoked], timeout: 2)
            fixture.server.releaseHistory()
            do { _ = try await recovering.value; XCTFail("Revoked recovery returned stale messages") }
            catch { /* Cancellation or membership denial both reject stale recovery. */ }
            let current = try await fixture.backend.syncRealtime(rooms: [], activeRoomID: nil)
            XCTAssertTrue(current.snapshot.rooms.isEmpty)
            XCTAssertTrue(current.activeMessages.isEmpty)
            XCTAssertNil(current.activeRoomID)
            await fixture.backend.shutdown(); fixture.close()
        }
    }

    func testRoomRevocationPurgesFailedMessagesPresenceTypingAndActiveRoom() throws {
        let data = RecoveryFixtureData()
        let room = try JSONDecoder().decode(SpringRoom.self, from: JSONSerialization.data(withJSONObject: data.roomJSON)).domain
        let model = AppModel(preferences: .defaults)
        model.rooms = [room]; model.currentUserID = data.user; model.preferences.activeRoomID = room.id
        model.draft = "removed room draft"
        model.updatePresence(roomID: room.id, userID: data.user, state: .away)
        model.updateTyping(roomID: room.id, userID: data.user, active: true)
        let pending = model.stageNewMessage(roomID: room.id, senderID: data.user, body: "failed")
        _ = model.failMessage(id: pending.id, roomID: room.id)
        _ = model.confirmMessage(try data.message(1).domain)
        model.incrementUnread(in: room.id)
        model.revokeRoom(room.id)
        XCTAssertTrue(model.rooms.isEmpty)
        XCTAssertNil(model.activeRoom)
        XCTAssertTrue(model.draft.isEmpty)
        XCTAssertTrue(model.messageOutbox.entries.isEmpty)
        XCTAssertTrue(model.messageLedger.entries.isEmpty)
        XCTAssertTrue(model.unreadCounts.isEmpty)
        XCTAssertTrue(model.activeBubbles.isEmpty)
        model.apply(snapshot: BackendSnapshot(profile: nil, rooms: [room]), currentUserID: data.user)
        XCTAssertEqual(model.rooms.first?.members.first?.presence, .offline, "Rejoin cannot inherit revoked presence or typing")
    }

    func testRevokingInactiveRoomPreservesOtherRoomDraftAndMessages() throws {
        let data = RecoveryFixtureData()
        let room = try JSONDecoder().decode(SpringRoom.self, from: JSONSerialization.data(withJSONObject: data.roomJSON)).domain
        let other = Room(id: UUID(), name: "other", ownerID: data.user, members: room.members, inviteCodeHint: "TEST")
        let model = AppModel(preferences: .defaults)
        model.rooms = [room, other]; model.currentUserID = data.user; model.preferences.activeRoomID = other.id
        model.draft = "active room draft"
        let active = model.stageNewMessage(roomID: other.id, senderID: data.user, body: "keep")
        _ = model.stageNewMessage(roomID: room.id, senderID: data.user, body: "remove")
        model.revokeRoom(room.id)
        XCTAssertEqual(model.activeRoom?.id, other.id)
        XCTAssertEqual(model.draft, "active room draft")
        XCTAssertEqual(model.messageOutbox.entries.map(\.id), [active.id])
    }

    func testQueuedOldReconciliationCannotRestoreRevokedRoomButFreshRejoinCan() throws {
        let data = RecoveryFixtureData()
        let room = try JSONDecoder().decode(SpringRoom.self, from: JSONSerialization.data(withJSONObject: data.roomJSON)).domain
        let coordinator = AppCoordinator(updateController: NoUpdateController(),
            preferencesStore: PreferencesStore(load: { .defaults }, save: { _ in }),
            legacyMigrator: .none, keychainAccessSession: KeychainAccessSession(),
            releaseChannel: .development, arguments: [])
        coordinator.model.currentUserID = data.user
        let old = BackendSnapshot(profile: nil, rooms: [room])
        coordinator.applyBackendSnapshot(old, currentUserID: data.user)
        coordinator.handleBackendEvent(.roomRevoked(roomID: room.id, revision: 1))
        coordinator.applyBackendReconciliation(BackendReconciliation(snapshot: old, activeRoomID: room.id, activeMessages: [try data.message(1).domain]))
        XCTAssertTrue(coordinator.model.rooms.isEmpty)
        XCTAssertTrue(coordinator.model.messageLedger.entries.isEmpty)
        var fresh = old; fresh.membershipRevision = 1
        coordinator.applyBackendReconciliation(BackendReconciliation(snapshot: fresh, activeRoomID: room.id, activeMessages: []))
        XCTAssertEqual(coordinator.model.rooms.map(\.id), [room.id])
    }

    func testReplacementBackendStartsANewLocalMembershipRevision() throws {
        let fixture = try RecoveryGatewayFixture()
        defer { fixture.close() }
        let coordinator = AppCoordinator(updateController: NoUpdateController(),
            preferencesStore: PreferencesStore(load: { .defaults }, save: { _ in }),
            legacyMigrator: .none, keychainAccessSession: KeychainAccessSession(),
            releaseChannel: .development, arguments: [])
        coordinator.latestMembershipRevision = 5
        coordinator.backend = fixture.backend
        XCTAssertEqual(coordinator.latestMembershipRevision, 0)
        let room = try JSONDecoder().decode(SpringRoom.self, from: JSONSerialization.data(withJSONObject: fixture.data.roomJSON)).domain
        XCTAssertTrue(coordinator.applyBackendSnapshot(BackendSnapshot(profile: nil, rooms: [room]), currentUserID: fixture.data.user))
        XCTAssertEqual(coordinator.model.rooms.map(\.id), [room.id])
    }

    func testRevocationSurvivesBoundedEventOverflowWhileRecoveryIsBlocked() async throws {
        let fixture = try RecoveryGatewayFixture()
        let snapshot = try await fixture.backend.boot()
        _ = try await fixture.backend.syncRealtime(rooms: snapshot.rooms, activeRoomID: fixture.data.room)
        // Do not consume events yet: the UI is a slow consumer. Hold the next
        // REST snapshot so a dropped control cannot be repaired by recovery.
        fixture.server.holdNextSnapshot()
        fixture.server.removeMembership()
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !fixture.server.historyResponseHeld {
            guard ContinuousClock.now < deadline else { return XCTFail("Recovery snapshot was not blocked") }
            try await Task.sleep(for: .milliseconds(2))
        }
        for _ in 0..<600 {
            fixture.server.publishTransientError()
            // Allow the socket reader to advance while the UI remains blocked.
            try await Task.sleep(for: .milliseconds(1))
        }
        let coordinator = AppCoordinator(updateController: NoUpdateController(),
            preferencesStore: PreferencesStore(load: { .defaults }, save: { _ in }),
            legacyMigrator: .none, keychainAccessSession: KeychainAccessSession(),
            releaseChannel: .development, arguments: [])
        coordinator.applyBackendSnapshot(snapshot, currentUserID: fixture.data.user)
        let cleared = expectation(description: "Revocation retained despite UI stream overflow")
        let reader = Task { @MainActor in
            for await event in fixture.backend.events {
                if case .roomStateInvalidated = event {
                    coordinator.handleBackendEvent(event)
                    cleared.fulfill(); return
                }
            }
        }
        defer { reader.cancel() }
        await fulfillment(of: [cleared], timeout: 2)
        XCTAssertTrue(coordinator.model.rooms.isEmpty)
        XCTAssertTrue(coordinator.model.messageLedger.entries.isEmpty)
        XCTAssertTrue(fixture.server.historyResponseHeld, "UI must clear without waiting for the blocked REST response")
        await fixture.backend.shutdown()
        fixture.server.releaseHistory()
        fixture.close()
    }

    func testLostAckRetrievesCommittedCanonicalUUIDAndConflictNeverFallsBack() async throws {
        for mode in [RecoveryMessageMode.loseAck, .canonical] {
            let fixture = try RecoveryGatewayFixture(messageMode: mode)
            let snapshot = try await fixture.backend.boot()
            _ = try await fixture.backend.syncRealtime(rooms: snapshot.rooms, activeRoomID: fixture.data.room)
            let id = UUID()
            let first = try await fixture.backend.sendMessage(roomID: fixture.data.room, body: "original", id: id)
            XCTAssertEqual(first.id, id)
            let before = fixture.server.lookupCount
            do { _ = try await fixture.backend.sendMessage(roomID: fixture.data.room, body: "edited", id: id); XCTFail("Changed payload accepted") }
            catch { XCTAssertEqual(error as? SideyBackendError, .remote("message_id_conflict")) }
            if mode == .canonical { XCTAssertEqual(fixture.server.lookupCount, before, "Explicit conflict must not be hidden by lookup") }
            let same = try await fixture.backend.sendMessage(roomID: fixture.data.room, body: "original", id: id)
            XCTAssertEqual(same.id, first.id)
            XCTAssertEqual(same.createdAt, first.createdAt)
            XCTAssertEqual(fixture.server.committedMessageCount, 1)
            await fixture.backend.shutdown(); fixture.close()
        }
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
         emptyRooms: Bool = false, holdHistory: Bool = false, messageMode: RecoveryMessageMode = .rejectFirst) throws {
        host = "recovery-\(UUID().uuidString.lowercased()).invalid"
        let config = RuntimeConfiguration(apiBaseURL: URL(string: "https://\(host)/api")!)
        server = RecoveryProtocolServer(data: data, failSecondPageOnce: failSecondPageOnce,
            accountStatus: accountStatus, accountCode: accountCode, emptyRooms: emptyRooms, holdHistory: holdHistory, messageMode: messageMode)
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
            session: session, transport: transport)
    }
    func close() {
        network.invalidateAndCancel()
        RecoveryURLProtocol.servers.remove(host: host)
    }
}

private enum RecoveryMessageMode { case rejectFirst, loseAck, canonical }

private final class RecoveryProtocolServer: @unchecked Sendable {
    let data: RecoveryFixtureData
    private let lock = NSLock()
    private var subscribed = false
    private var publish: (@Sendable (Data) -> Void)?
    private var heldHistory: (@Sendable () -> Void)?
    private var shouldHoldSnapshot = false
    private var shouldHoldHistory: Bool
    private let emptyRooms: Bool
    private let messageMode: RecoveryMessageMode
    private var committed: [String: [String: Any]] = [:]
    private var lookups = 0
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
    init(data: RecoveryFixtureData, failSecondPageOnce: Bool, accountStatus: Int, accountCode: String, emptyRooms: Bool, holdHistory: Bool, messageMode: RecoveryMessageMode) {
        self.emptyRooms = emptyRooms
        self.shouldHoldHistory = holdHistory
        self.messageMode = messageMode
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
    var lookupCount: Int { lock.withLock { lookups } }
    var committedMessageCount: Int { lock.withLock { committed.count } }
    var shouldLoseAck: Bool { lock.withLock { messageMode == .loseAck && attempts.count == 1 } }
    var historyResponseHeld: Bool { lock.withLock { heldHistory != nil } }
    func attach(_ publish: @escaping @Sendable (Data) -> Void) { lock.withLock { self.publish = publish } }
    func holdNextSnapshot() { lock.withLock { shouldHoldSnapshot = true } }
    func holdHistoryResponse(path: String, _ callback: @escaping @Sendable () -> Void) -> Bool {
        lock.withLock {
            if path.hasSuffix("/messages"), shouldHoldHistory { shouldHoldHistory = false }
            else if path == "/api/rooms", shouldHoldSnapshot { shouldHoldSnapshot = false }
            else { return false }
            heldHistory = callback; return true
        }
    }
    func releaseHistory() { let callback = lock.withLock { let value = heldHistory; heldHistory = nil; return value }; callback?() }
    func publishTransientError() {
        let sink = lock.withLock { publish }
        sink?(Data(#"{"type":"error","code":"transient_rate_limited"}"#.utf8))
    }
    func restoreMembership() { lock.withLock { membershipRemoved = false } }
    func removeMembership() {
        let sink = lock.withLock { membershipRemoved = true; return publish }
        sink?(try! JSONSerialization.data(withJSONObject: ["type": "room.revoked", "roomId": data.room.uuidString]))
    }

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
                return (200, emptyRooms ? [] : [data.roomJSON])
            }
            if url.path == "/api/commerce/orders/\(data.id(800))" {
                return (200, ["id": data.id(800).uuidString, "status": "failed"])
            }
            if url.path == "/api/commerce/entitlements" { return (200, []) }
            if url.path.contains("/messages/") {
                lookups += 1
                if membershipRemoved { return (403, ["code": "membership_required"]) }
                if let message = committed[url.lastPathComponent.lowercased()] { return (200, message) }
            }
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
                if messageMode == .rejectFirst && attempts.count == 1 {
                    return [try JSONSerialization.data(withJSONObject: ["type": "error", "requestId": body["requestId"]!, "code": "internal_error"])]
                }
                let key = body["id"]!.lowercased()
                if let message = committed[key] {
                    if message["body"] as? String != body["body"] {
                        return [try JSONSerialization.data(withJSONObject: ["type": "error", "requestId": body["requestId"]!, "code": "message_id_conflict"])]
                    }
                    return [try JSONSerialization.data(withJSONObject: ["type": "message.ack", "requestId": body["requestId"]!, "message": message])]
                }
                var message = data.messageJSON(999)
                message["id"] = body["id"]
                message["body"] = body["body"]
                committed[key] = message
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
    private let deliveryLock = NSLock()
    private var stopped = false
    override func startLoading() {
        do {
            guard let url = request.url, let server = Self.servers.server(host: url.host ?? "") else { throw URLError(.badURL) }
            let (status, data) = try server.reply(request)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            let deliver: @Sendable () -> Void = { [self] in
                deliveryLock.withLock {
                    guard !stopped else { return }
                    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocol(self, didLoad: data)
                    client?.urlProtocolDidFinishLoading(self)
                }
            }
            if server.holdHistoryResponse(path: url.path, deliver) { return }
            deliver()
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { deliveryLock.withLock { stopped = true } }
}

private final class RecoveryProtocolSocket: SpringRealtimeSocket, @unchecked Sendable {
    private let server: RecoveryProtocolServer
    private let stream = AsyncThrowingStream<Data, Error>.makeStream()
    init(server: RecoveryProtocolServer) {
        self.server = server
        let continuation = stream.continuation
        server.attach { continuation.yield($0) }
    }
    func resume() { stream.continuation.yield(Data(#"{"type":"connected","connectionId":"test"}"#.utf8)) }
    func cancel() { stream.continuation.finish(throwing: CancellationError()) }
    func receive() async throws -> Data {
        var iterator = stream.stream.makeAsyncIterator()
        guard let next = try await iterator.next() else { throw CancellationError() }
        return next
    }
    func send(_ text: String) async throws {
        let frames = try server.command(text)
        if text.contains("message.send"), server.shouldLoseAck { throw URLError(.networkConnectionLost) }
        for frame in frames { stream.continuation.yield(frame) }
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
