import Foundation
import Observation

@MainActor
@Observable
final class AppMessageState {
    var draft = ""
    private(set) var messageLedger = MessageLedger()
    private(set) var messageOutbox = MessageOutbox()
    private(set) var bubbleLedger = ActiveBubbleLedger()
    private(set) var unreadCounts: [UUID: Int] = [:]

    func reset() {
        draft = ""
        messageLedger = MessageLedger()
        messageOutbox = MessageOutbox()
        bubbleLedger = ActiveBubbleLedger()
        unreadCounts.removeAll()
    }

    func retain(roomIDs: Set<UUID>) {
        let removed = messageLedger.entries.filter { !roomIDs.contains($0.roomID) }.map(\.id)
            + messageOutbox.entries.filter { !roomIDs.contains($0.roomID) }.map(\.id)
        for id in removed { bubbleLedger.remove(messageID: id) }
        messageLedger.retain(roomIDs: roomIDs)
        messageOutbox.retain(roomIDs: roomIDs)
        unreadCounts = unreadCounts.filter { roomIDs.contains($0.key) }
    }

    var totalUnreadCount: Int {
        unreadCounts.values.reduce(0, +)
    }

    func unreadCount(in roomID: UUID) -> Int {
        unreadCounts[roomID, default: 0]
    }

    func markRoomRead(_ roomID: UUID) {
        unreadCounts.removeValue(forKey: roomID)
    }

    func incrementUnread(in roomID: UUID) {
        unreadCounts[roomID, default: 0] += 1
    }

    func stageNewMessage(roomID: UUID, senderID: UUID, body: String, revealBubble: Bool = true,
                         now: Date = .now, activeRoomID: UUID?, equippedBubbleStyleID: String?) -> OutgoingMessage {
        messageOutbox.pruneFailed(now: now)
        let value = OutgoingMessage(id: UUID(), roomID: roomID, senderID: senderID, body: body, createdAt: now, state: .pending)
        stageMessage(id: value.id, roomID: roomID, senderID: senderID, body: body, revealBubble: revealBubble,
                     now: now, activeRoomID: activeRoomID, equippedBubbleStyleID: equippedBubbleStyleID)
        return value
    }

    func retryMessage(id: UUID, roomID: UUID, senderID: UUID, revealBubble: Bool = true,
                      now: Date = .now, activeRoomID: UUID?, equippedBubbleStyleID: String?) -> OutgoingMessage? {
        messageOutbox.pruneFailed(now: now)
        guard let value = messageOutbox.retryCandidate(id: id, roomID: roomID, senderID: senderID, now: now) else { return nil }
        stageMessage(id: value.id, roomID: value.roomID, senderID: value.senderID, body: value.body,
                     revealBubble: revealBubble, now: value.createdAt, activeRoomID: activeRoomID,
                     equippedBubbleStyleID: equippedBubbleStyleID)
        return value
    }

    func stageMessage(
        id: UUID,
        roomID: UUID,
        senderID: UUID,
        body: String,
        revealBubble: Bool = true,
        now: Date = .now,
        activeRoomID: UUID?,
        equippedBubbleStyleID: String?
    ) {
        messageOutbox.stage(id: id, roomID: roomID, senderID: senderID, body: body, createdAt: now)
        if revealBubble, roomID == activeRoomID {
            bubbleLedger.show(
                senderID: senderID,
                messageID: id,
                body: body,
                bubbleStyleID: equippedBubbleStyleID,
                expiresAt: now.addingTimeInterval(ActiveBubbleLedger.defaultLifetime)
            )
        }
    }

    @discardableResult
    func confirmMessage(_ message: ChatMessage, revealBubble: Bool = true, activeRoomID: UUID?) -> Bool {
        let wasOutgoing = messageOutbox.confirm(id: message.id, roomID: message.roomID)
        let wasNewToLedger = messageLedger.confirm(message)
        let isNew = wasNewToLedger && !wasOutgoing
        if (isNew || wasOutgoing), revealBubble, message.roomID == activeRoomID {
            bubbleLedger.show(
                senderID: message.senderID,
                messageID: message.id,
                body: message.body,
                bubbleStyleID: message.bubbleStyleID,
                expiresAt: message.createdAt.addingTimeInterval(ActiveBubbleLedger.defaultLifetime)
            )
            bubbleLedger.prune()
        }
        return isNew
    }

    func failMessage(id: UUID, roomID: UUID) -> OutgoingMessage? {
        let message = messageOutbox.fail(id: id, roomID: roomID)
        bubbleLedger.remove(messageID: id)
        return message
    }

    func replaceMessages(roomID: UUID, with messages: [ChatMessage]) {
        messageLedger.replaceConfirmed(roomID: roomID, with: messages)
        for message in messages {
            _ = messageOutbox.confirm(id: message.id, roomID: roomID)
        }
    }

    func removeMessage(id: UUID, roomID: UUID) {
        messageLedger.remove(id: id, roomID: roomID)
        bubbleLedger.remove(messageID: id)
    }

    func clearBubbles() {
        bubbleLedger.removeAll()
    }

    func dismissExpiredBubbles(at date: Date = .now) {
        bubbleLedger.prune(at: date)
        messageLedger.prune(now: date)
        messageOutbox.pruneFailed(now: date)
    }
}
