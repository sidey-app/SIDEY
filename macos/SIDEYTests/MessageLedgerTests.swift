import XCTest
@testable import SIDEY

final class MessageLedgerTests: XCTestCase {
    func testOptimisticMessagePreservesSenderAndConfirmsWithoutDuplicate() {
        let id = UUID()
        let roomID = UUID()
        let senderID = UUID()
        let message = ChatMessage(
            id: id,
            roomID: roomID,
            senderID: senderID,
            body: "안녕",
            createdAt: .now
        )
        var ledger = MessageLedger()

        ledger.stage(id: id, roomID: roomID, senderID: senderID, body: "안녕")
        XCTAssertFalse(ledger.confirm(message), "optimistic confirmation is not a new receive")
        XCTAssertFalse(ledger.confirm(message), "Realtime echo must remain deduplicated")

        XCTAssertEqual(ledger.entries.count, 1)
        XCTAssertEqual(ledger.entries.first?.senderID, senderID)
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

    func testActiveBubblesReplacePerSenderEvictOldestAndExpireIndependently() {
        var bubbles = ActiveBubbleLedger()
        let start = Date(timeIntervalSince1970: 1_000)
        let senders = (0..<5).map { _ in UUID() }

        for index in 0..<4 {
            bubbles.show(
                senderID: senders[index],
                messageID: UUID(),
                body: "메시지 \(index)",
                expiresAt: start.addingTimeInterval(TimeInterval(index + 1))
            )
        }
        let replacementID = UUID()
        bubbles.show(
            senderID: senders[0],
            messageID: replacementID,
            body: "교체",
            expiresAt: start.addingTimeInterval(20)
        )
        XCTAssertEqual(bubbles.bubbles.count, 4)
        XCTAssertEqual(bubbles.bubbles.first(where: { $0.senderID == senders[0] })?.messageID, replacementID)

        bubbles.show(
            senderID: senders[4],
            messageID: UUID(),
            body: "다섯 번째 발신자",
            expiresAt: start.addingTimeInterval(21)
        )
        XCTAssertEqual(bubbles.bubbles.count, 4)
        XCTAssertFalse(bubbles.bubbles.contains(where: { $0.senderID == senders[1] }))

        bubbles.prune(at: start.addingTimeInterval(20.5))
        XCTAssertEqual(bubbles.bubbles.count, 1)
        XCTAssertEqual(bubbles.bubbles.first?.senderID, senders[4])
    }

    @MainActor
    func testInactiveRoomMessageDoesNotCreateVisibleBubbleAndUnreadDeduplicates() {
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
        XCTAssertTrue(model.confirmMessage(inactiveMessage, revealBubble: false))
        model.incrementUnread(in: inactiveRoomID)
        XCTAssertFalse(model.confirmMessage(inactiveMessage, revealBubble: false))

        XCTAssertEqual(model.activeBubbles.map(\.body), ["보이는 메시지"])
        XCTAssertEqual(model.unreadCount(in: inactiveRoomID), 1)
    }

    @MainActor
    func testFailedOptimisticMessageRestoresBodyAndRemovesBubble() {
        let id = UUID()
        let roomID = UUID()
        let senderID = UUID()
        var preferences = AppPreferences.defaults
        preferences.activeRoomID = roomID
        let model = AppModel(preferences: preferences)
        model.rooms = [Self.room(id: roomID, name: "활성")]
        model.stageMessage(id: id, roomID: roomID, senderID: senderID, body: "복구할 메시지")

        XCTAssertEqual(model.failMessage(id: id), "복구할 메시지")
        XCTAssertTrue(model.messageLedger.entries.isEmpty)
        XCTAssertTrue(model.activeBubbles.isEmpty)
    }

    @MainActor
    func testHistoryReplacementNeverReplaysOldMessagesAsBubbles() {
        let roomID = UUID()
        var preferences = AppPreferences.defaults
        preferences.activeRoomID = roomID
        let model = AppModel(preferences: preferences)
        model.rooms = [Self.room(id: roomID, name: "조용한 방")]
        let message = ChatMessage(
            id: UUID(), roomID: roomID, senderID: UUID(), body: "기록 원본", createdAt: .now
        )

        model.replaceMessages(roomID: roomID, with: [message])

        XCTAssertTrue(model.activeBubbles.isEmpty)
        XCTAssertEqual(model.messageLedger.entries.count, 1)
    }

    func testReplacingServerHistoryKeepsPendingMessageAndDeduplicatesRows() {
        let roomID = UUID()
        let pendingID = UUID()
        let confirmed = ChatMessage(
            id: UUID(), roomID: roomID, senderID: UUID(), body: "서버 원본", createdAt: .now
        )
        var ledger = MessageLedger()
        ledger.stage(id: pendingID, roomID: roomID, senderID: UUID(), body: "전송 중")

        ledger.replaceConfirmed(roomID: roomID, with: [confirmed, confirmed])

        XCTAssertEqual(ledger.entries.count, 2)
        XCTAssertEqual(ledger.entries.filter { $0.state == .pending }.map(\.id), [pendingID])
        XCTAssertEqual(ledger.entries.filter { $0.state == .confirmed }.map(\.id), [confirmed.id])
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
}
