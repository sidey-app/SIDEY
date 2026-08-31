import Foundation
import XCTest
@testable import SIDEY

final class BackendIntegrationTests: XCTestCase {
    func testTwoNativeClientsMessageTypingPresenceAndCleanup() async throws {
        let sentinel = "/private/tmp/sidey-run-backend-integration"
        guard ProcessInfo.processInfo.environment["SIDEY_RUN_BACKEND_INTEGRATION"] == "1"
                || FileManager.default.fileExists(atPath: sentinel) else {
            throw XCTSkip("SIDEY_RUN_BACKEND_INTEGRATION=1일 때만 실서버 통합 테스트 실행")
        }

        let configuration = try RuntimeConfiguration.resolve(environment: [:])
        let firstStore = KeychainStore(service: "app.sidey.desktop.integration.\(UUID().uuidString)")
        let secondStore = KeychainStore(service: "app.sidey.desktop.integration.\(UUID().uuidString)")
        let first = SideyBackend(configuration: configuration, keychain: firstStore)
        let second = SideyBackend(configuration: configuration, keychain: secondStore)
        let firstProbe = BackendEventProbe()
        let secondProbe = BackendEventProbe()
        let firstEvents = Task { await firstProbe.consume(first.events) }
        let secondEvents = Task { await secondProbe.consume(second.events) }
        var createdRoomID: UUID?

        do {
            _ = try await first.boot()
            _ = try await second.boot()
            _ = try await first.upsertProfile(nickname: "통합첫째")
            _ = try await second.upsertProfile(nickname: "통합둘째")
            let created = try await first.createRoom(name: "네이티브 통합 \(Int.random(in: 1000...9999))")
            createdRoomID = created.roomID
            let joinedRoomID = try await second.joinRoom(inviteCode: created.inviteCode)
            XCTAssertEqual(joinedRoomID, created.roomID)
            let creatorStoredCode = try await first.storedInviteCode(roomID: created.roomID)
            let joinerStoredCode = try await second.storedInviteCode(roomID: created.roomID)
            XCTAssertEqual(creatorStoredCode, created.inviteCode)
            XCTAssertEqual(joinerStoredCode, created.inviteCode)

            try await first.syncRealtime(roomIDs: [created.roomID], activeRoomID: created.roomID)
            try await second.syncRealtime(roomIDs: [created.roomID], activeRoomID: created.roomID)
            try await waitUntil("두 클라이언트 Realtime 구독") {
                let firstConnected = await firstProbe.isConnected
                let secondConnected = await secondProbe.isConnected
                return firstConnected && secondConnected
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

            try await first.setLocalPresence(.away)
            let optionalFirstUserID = await first.currentUserID()
            let firstUserID = try XCTUnwrap(optionalFirstUserID)
            try await waitUntil("away Presence 수신") {
                await secondProbe.presence[firstUserID] == .away
            }

            try await second.leaveRoom(created.roomID)
            try await first.leaveRoom(created.roomID)
            createdRoomID = nil
        } catch {
            if let roomID = createdRoomID {
                try? await second.leaveRoom(roomID)
                try? await first.leaveRoom(roomID)
            }
            firstEvents.cancel()
            secondEvents.cancel()
            await first.shutdown()
            await second.shutdown()
            try? firstStore.deleteAll()
            try? secondStore.deleteAll()
            throw error
        }

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
}

private actor BackendEventProbe {
    private(set) var isConnected = false
    private(set) var messageIDs: Set<UUID> = []
    private(set) var typingStarted = false
    private(set) var typingStopped = false
    private(set) var presence: [UUID: PresenceState] = [:]

    func consume(_ events: AsyncStream<BackendEvent>) async {
        for await event in events {
            switch event {
            case .connection(let connected):
                isConnected = connected
            case .message(let message):
                messageIDs.insert(message.id)
            case .typing(_, _, let active):
                if active { typingStarted = true } else { typingStopped = true }
            case .presence(_, let userID, let state):
                presence[userID] = state
            case .snapshot:
                break
            }
        }
    }
}

private struct IntegrationTimeout: Error {}
