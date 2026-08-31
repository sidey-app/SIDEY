import XCTest
@testable import SIDEY

final class MessageLedgerTests: XCTestCase {
    func testOptimisticMessageIsConfirmedWithoutDuplicate() {
        let id = UUID()
        let roomID = UUID()
        let message = ChatMessage(id: id, roomID: roomID, senderID: UUID(), body: "안녕", createdAt: .now)
        var ledger = MessageLedger()

        ledger.stage(id: id, roomID: roomID, body: "안녕")
        XCTAssertFalse(ledger.confirm(message), "낙관적 항목 확인은 새 수신으로 세면 안 됨")
        XCTAssertFalse(ledger.confirm(message), "Realtime 재수신은 중복 수신으로 세면 안 됨")

        XCTAssertEqual(ledger.entries.count, 1)
        XCTAssertEqual(ledger.entries.first?.state, .confirmed)
    }

    @MainActor
    func testHistoryOrdersNewestMessageFirstAndCapsAtTwenty() {
        let roomID = UUID()
        var ledger = MessageLedger()
        for index in 0..<24 {
            _ = ledger.confirm(ChatMessage(
                id: UUID(),
                roomID: roomID,
                senderID: UUID(),
                body: "메시지 \(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            ))
        }

        let entries = OverlayHistoryView.recentEntries(in: ledger, roomID: roomID)

        XCTAssertEqual(entries.count, 20)
        XCTAssertEqual(entries.first?.body, "메시지 23")
        XCTAssertEqual(entries.last?.body, "메시지 4")
    }

    @MainActor
    func testInactiveRoomMessageDoesNotReplaceVisibleBubbleAndUnreadDeduplicates() {
        let activeRoomID = UUID()
        let inactiveRoomID = UUID()
        var preferences = AppPreferences.defaults
        preferences.activeRoomID = activeRoomID
        let model = AppModel(preferences: preferences)
        model.rooms = [
            Self.room(id: activeRoomID, name: "활성"),
            Self.room(id: inactiveRoomID, name: "다른 그룹")
        ]
        let activeMessage = ChatMessage(
            id: UUID(), roomID: activeRoomID, senderID: UUID(), body: "보이는 메시지", createdAt: .now
        )
        let inactiveMessage = ChatMessage(
            id: UUID(), roomID: inactiveRoomID, senderID: UUID(), body: "조용한 수신", createdAt: .now
        )

        XCTAssertTrue(model.confirmMessage(activeMessage))
        XCTAssertTrue(model.confirmMessage(inactiveMessage, revealLatest: false))
        model.incrementUnread(in: inactiveRoomID)
        XCTAssertFalse(model.confirmMessage(inactiveMessage, revealLatest: false))

        XCTAssertEqual(model.latestMessage, "보이는 메시지")
        XCTAssertEqual(model.unreadCount(in: inactiveRoomID), 1)
        model.markRoomRead(inactiveRoomID)
        XCTAssertEqual(model.unreadCount(in: inactiveRoomID), 0)
    }

    private static func room(id: UUID, name: String) -> Room {
        Room(
            id: id,
            name: name,
            ownerID: UUID(),
            members: [],
            inviteCodeHint: "ABCD",
            inviteVersion: 1
        )
    }

    func testFailedOptimisticMessageReturnsBodyAndIsRemoved() {
        let id = UUID()
        var ledger = MessageLedger()
        ledger.stage(id: id, roomID: UUID(), body: "복구할 메시지")

        XCTAssertEqual(ledger.fail(id: id), "복구할 메시지")
        XCTAssertTrue(ledger.entries.isEmpty)
    }

    @MainActor
    func testQuietHistoryReplacementDoesNotRevealBubble() {
        let roomID = UUID()
        var preferences = AppPreferences.defaults
        preferences.activeRoomID = roomID
        let model = AppModel(preferences: preferences)
        model.rooms = [Self.room(id: roomID, name: "조용한 방")]
        let message = ChatMessage(
            id: UUID(), roomID: roomID, senderID: UUID(), body: "표시하지 않음", createdAt: .now
        )

        model.replaceMessages(roomID: roomID, with: [message], revealLatest: false)

        XCTAssertNil(model.latestMessage)
        XCTAssertEqual(model.messageLedger.entries.count, 1)
    }

    func testReplacingServerHistoryKeepsPendingMessageAndDeduplicatesRows() {
        let roomID = UUID()
        let confirmedID = UUID()
        let pendingID = UUID()
        let confirmed = ChatMessage(
            id: confirmedID,
            roomID: roomID,
            senderID: UUID(),
            body: "서버 원본",
            createdAt: .now
        )
        var ledger = MessageLedger()
        ledger.stage(id: pendingID, roomID: roomID, body: "전송 중")

        ledger.replaceConfirmed(roomID: roomID, with: [confirmed, confirmed])

        XCTAssertEqual(ledger.entries.count, 2)
        XCTAssertEqual(ledger.entries.filter { $0.state == .pending }.map(\.id), [pendingID])
        XCTAssertEqual(ledger.entries.filter { $0.state == .confirmed }.map(\.id), [confirmedID])
    }
}
