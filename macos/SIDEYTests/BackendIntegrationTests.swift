import Foundation
import XCTest
@testable import SIDEY

final class BackendIntegrationTests: XCTestCase {
    func testTwoNativeClientsMessageTypingPresenceAndCleanup() async throws {
        var environment = ProcessInfo.processInfo.environment
        let testBundle = Bundle(for: Self.self)
        let integrationFlag = configuredValue(
            environment: environment,
            environmentKey: "SIDEY_RUN_BACKEND_INTEGRATION",
            bundle: testBundle,
            bundleKey: "SIDEYRunBackendIntegration"
        )
        guard integrationFlag == "1" else {
            throw XCTSkip("명시적인 로컬·staging 환경에서만 통합 테스트 실행")
        }
        environment["SIDEY_SUPABASE_URL"] = configuredValue(
            environment: environment,
            environmentKey: "SIDEY_SUPABASE_URL",
            bundle: testBundle,
            bundleKey: "SIDEYSupabaseURL"
        )
        environment["SIDEY_SUPABASE_PUBLISHABLE_KEY"] = configuredValue(
            environment: environment,
            environmentKey: "SIDEY_SUPABASE_PUBLISHABLE_KEY",
            bundle: testBundle,
            bundleKey: "SIDEYSupabasePublishableKey"
        )
        guard environment["SIDEY_SUPABASE_URL"]?.isEmpty == false,
              environment["SIDEY_SUPABASE_PUBLISHABLE_KEY"]?.isEmpty == false
        else {
            XCTFail("통합 테스트에는 SIDEY_SUPABASE_URL과 SIDEY_SUPABASE_PUBLISHABLE_KEY가 필요합니다.")
            return
        }
        let configuration = try RuntimeConfiguration.resolve(environment: environment)
        guard !configuration.isProductionBackend else {
            XCTFail("통합 테스트는 SIDEY production backend에서 실행할 수 없습니다.")
            return
        }
        let firstStore = KeychainStore(service: "app.sidey.desktop.integration.\(UUID().uuidString)")
        let secondStore = KeychainStore(service: "app.sidey.desktop.integration.\(UUID().uuidString)")
        let first = SideyBackend(configuration: configuration, keychain: firstStore)
        let second = SideyBackend(configuration: configuration, keychain: secondStore)
        let firstProbe = BackendEventProbe()
        let secondProbe = BackendEventProbe()
        let firstEvents = Task { await firstProbe.consume(first.events) }
        let secondEvents = Task { await secondProbe.consume(second.events) }
        var createdRoomIDs: Set<UUID> = []

        do {
            _ = try await first.boot()
            _ = try await second.boot()
            _ = try await first.upsertProfile(nickname: "통합첫째")
            _ = try await second.upsertProfile(nickname: "통합둘째")
            let created = try await first.createRoom(name: "네이티브 통합 \(Int.random(in: 1000...9999))")
            createdRoomIDs.insert(created.roomID)
            let joinedRoom = try await second.joinRoom(inviteCode: created.inviteCode)
            XCTAssertEqual(joinedRoom.roomID, created.roomID)
            XCTAssertTrue(joinedRoom.storedInKeychain)
            let creatorStoredCode = try await first.storedInviteCode(roomID: created.roomID)
            let joinerStoredCode = try await second.storedInviteCode(roomID: created.roomID)
            XCTAssertEqual(creatorStoredCode, created.inviteCode)
            XCTAssertEqual(joinerStoredCode, created.inviteCode)

            let firstSnapshot = try await first.loadSnapshot()
            let secondSnapshot = try await second.loadSnapshot()
            _ = try await first.syncRealtime(rooms: firstSnapshot.rooms, activeRoomID: created.roomID)
            _ = try await second.syncRealtime(rooms: secondSnapshot.rooms, activeRoomID: created.roomID)
            try await waitUntil("두 클라이언트 Realtime 구독") {
                let firstConnected = await firstProbe.isConnected
                let secondConnected = await secondProbe.isConnected
                return firstConnected && secondConnected
            }

            let snapshotsBeforeRename = await secondProbe.snapshotCount
            let renamedRoom = "이름 변경 \(Int.random(in: 1000...9999))"
            try await first.renameRoom(created.roomID, name: renamedRoom)
            try await waitUntil("두 번째 클라이언트 그룹 이름 변경 수신") {
                await secondProbe.hasSnapshot(
                    after: snapshotsBeforeRename,
                    roomID: created.roomID,
                    expectedName: renamedRoom
                )
            }

            let body = "Swift 네이티브 통합 \(UUID().uuidString.prefix(8))"
            let sent = try await first.sendMessage(roomID: created.roomID, body: body)
            try await waitUntil("두 번째 클라이언트 메시지 수신") {
                await secondProbe.messageIDs.contains(sent.id)
            }
            let receivedMessages = try await second.recentMessages(roomID: created.roomID)
            XCTAssertEqual(receivedMessages.last?.body, body)

            try await first.broadcastTyping(roomID: created.roomID, event: "typing_start")
            try await waitUntil("typing_start Broadcast 수신") { await secondProbe.typingStarted }
            try await first.broadcastTyping(roomID: created.roomID, event: "typing_stop")
            try await waitUntil("typing_stop Broadcast 수신") { await secondProbe.typingStopped }

            let pulseEventID = UUID()
            try await first.broadcastCharacterPulse(roomID: created.roomID, eventID: pulseEventID)
            try await waitUntil("character_pulse Broadcast 수신") {
                await secondProbe.characterPulseEventIDs.contains(pulseEventID)
            }

            try await first.setLocalPresence(.away)
            let optionalFirstUserID = await first.currentUserID()
            let firstUserID = try XCTUnwrap(optionalFirstUserID)
            try await waitUntil("away Presence 수신") {
                await secondProbe.presence[firstUserID] == .away
            }

            let optionalSecondUserID = await second.currentUserID()
            let secondUserID = try XCTUnwrap(optionalSecondUserID)
            let presenceUpdatesBeforeInterruption = await firstProbe.presenceUpdateCounts[secondUserID, default: 0]
            let disconnectionsBeforeInterruption = await secondProbe.disconnectedAfterConnectCount
            await second.interruptRealtimeConnectionForTesting()
            try await waitUntil("강제 단절 감지", timeout: .seconds(15)) {
                await secondProbe.disconnectedAfterConnectCount > disconnectionsBeforeInterruption
            }
            try await waitUntil("Realtime 자동 재구독", timeout: .seconds(30)) {
                await secondProbe.isConnected
            }
            try await waitUntil("재구독 뒤 Presence 재발행") {
                await firstProbe.hasPresenceUpdate(
                    userID: secondUserID,
                    state: .online,
                    after: presenceUpdatesBeforeInterruption
                )
            }

            let recoveredBody = "재구독 메시지 \(UUID().uuidString.prefix(8))"
            let recoveredMessage = try await first.sendMessage(roomID: created.roomID, body: recoveredBody)
            try await waitUntil("재구독 뒤 메시지 수신") {
                await secondProbe.messageIDs.contains(recoveredMessage.id)
            }

            let recoveredPulseEventID = UUID()
            try await first.broadcastCharacterPulse(roomID: created.roomID, eventID: recoveredPulseEventID)
            try await waitUntil("재구독 뒤 character_pulse 수신") {
                await secondProbe.characterPulseEventIDs.contains(recoveredPulseEventID)
            }

            let deletionRoom = try await first.createRoom(name: "삭제 통합 \(Int.random(in: 1000...9999))")
            createdRoomIDs.insert(deletionRoom.roomID)
            _ = try await second.joinRoom(inviteCode: deletionRoom.inviteCode)
            let firstDeletionSnapshot = try await first.loadSnapshot()
            let secondDeletionSnapshot = try await second.loadSnapshot()
            _ = try await first.syncRealtime(
                rooms: firstDeletionSnapshot.rooms,
                activeRoomID: created.roomID
            )
            _ = try await second.syncRealtime(
                rooms: secondDeletionSnapshot.rooms,
                activeRoomID: created.roomID
            )

            let snapshotsBeforeDeletion = await secondProbe.snapshotCount
            try await first.deleteRoom(deletionRoom.roomID)
            createdRoomIDs.remove(deletionRoom.roomID)
            try await waitUntil("참가 클라이언트 그룹 삭제 수신") {
                await secondProbe.hasSnapshot(
                    after: snapshotsBeforeDeletion,
                    roomID: deletionRoom.roomID,
                    expectedName: nil
                )
            }
            let afterDeletionSnapshot = try await second.loadSnapshot()
            _ = try await second.syncRealtime(rooms: afterDeletionSnapshot.rooms, activeRoomID: created.roomID)
            let deletedRoomStoredCode = try await second.storedInviteCode(roomID: deletionRoom.roomID)
            XCTAssertNil(deletedRoomStoredCode)

            let snapshotsBeforeRemoval = await secondProbe.snapshotCount
            try await first.removeRoomMember(created.roomID, userID: secondUserID)
            try await waitUntil("추방된 클라이언트 그룹 제거 수신") {
                await secondProbe.hasSnapshot(
                    after: snapshotsBeforeRemoval,
                    roomID: created.roomID,
                    expectedName: nil
                )
            }
            _ = try await second.syncRealtime(rooms: [], activeRoomID: nil)
            let removedRoomStoredCode = try await second.storedInviteCode(roomID: created.roomID)
            XCTAssertNil(removedRoomStoredCode)

            try await first.deleteRoom(created.roomID)
            createdRoomIDs.remove(created.roomID)
        } catch {
            for roomID in createdRoomIDs {
                try? await second.leaveRoom(roomID)
                try? await first.deleteRoom(roomID)
            }
            try? await first.deleteOwnAccountForTesting()
            try? await second.deleteOwnAccountForTesting()
            firstEvents.cancel()
            secondEvents.cancel()
            await first.shutdown()
            await second.shutdown()
            try? firstStore.deleteAll()
            try? secondStore.deleteAll()
            throw error
        }

        try await first.deleteOwnAccountForTesting()
        try await second.deleteOwnAccountForTesting()
        firstEvents.cancel()
        secondEvents.cancel()
        await first.shutdown()
        await second.shutdown()
        try firstStore.deleteAll()
        try secondStore.deleteAll()
    }

    private func waitUntil(
        _ label: String,
        timeout: Duration = .seconds(15),
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("\(label): 통합 이벤트가 \(timeout) 안에 도착하지 않음")
        throw IntegrationTimeout()
    }

    private func configuredValue(
        environment: [String: String],
        environmentKey: String,
        bundle: Bundle,
        bundleKey: String
    ) -> String? {
        if let value = environment[environmentKey], !value.isEmpty {
            return value
        }
        if let value = bundle.object(forInfoDictionaryKey: bundleKey) as? String,
           !value.isEmpty
        {
            return value
        }
        if let value = bundle.object(forInfoDictionaryKey: bundleKey) as? NSNumber {
            return value.stringValue
        }
        return nil
    }
}

private actor BackendEventProbe {
    private(set) var isConnected = false
    private(set) var messageIDs: Set<UUID> = []
    private(set) var typingStarted = false
    private(set) var typingStopped = false
    private(set) var characterPulseEventIDs: Set<UUID> = []
    private(set) var presence: [UUID: PresenceState] = [:]
    private(set) var presenceUpdateCounts: [UUID: Int] = [:]
    private(set) var disconnectedAfterConnectCount = 0
    private(set) var snapshotCount = 0
    private(set) var roomNames: [UUID: String] = [:]
    private var hasConnected = false

    func hasPresenceUpdate(userID: UUID, state: PresenceState, after count: Int) -> Bool {
        presence[userID] == state && presenceUpdateCounts[userID, default: 0] > count
    }

    func hasSnapshot(after count: Int, roomID: UUID, expectedName: String?) -> Bool {
        snapshotCount > count && roomNames[roomID] == expectedName
    }

    func consume(_ events: AsyncStream<BackendEvent>) async {
        for await event in events {
            switch event {
            case .connection(let connected):
                if connected {
                    hasConnected = true
                } else if hasConnected {
                    disconnectedAfterConnectCount += 1
                }
                isConnected = connected
            case .message(let message):
                messageIDs.insert(message.id)
            case .messageDeleted:
                break
            case .messagesInvalidated:
                break
            case .messagesReplaced(_, let messages):
                messageIDs.formUnion(messages.map(\.id))
            case .typing(_, _, let active):
                if active { typingStarted = true } else { typingStopped = true }
            case .characterPulse(let event):
                characterPulseEventIDs.insert(event.id)
            case .presence(_, let userID, let state):
                presence[userID] = state
                presenceUpdateCounts[userID, default: 0] += 1
            case .snapshot(let snapshot):
                snapshotCount += 1
                roomNames = Dictionary(uniqueKeysWithValues: snapshot.rooms.map { ($0.id, $0.name) })
            case .technicalError:
                break
            }
        }
    }
}

private struct IntegrationTimeout: Error {}
