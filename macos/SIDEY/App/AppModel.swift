import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var preferences: AppPreferences
    var overlayVisibility: OverlayVisibility
    var overlayVisible: Bool { overlayVisibility.isVisible }
    var presence: PresenceState = .online
    var nickname: String
    var selectedCharacterID: String
    var draft = ""
    private(set) var messageLedger = MessageLedger()
    private(set) var messageOutbox = MessageOutbox()
    private(set) var bubbleLedger = ActiveBubbleLedger()
    var availableScreens: [OverlayScreenOption] = []
    var activeSettingsPage: SettingsPage = .profile
    var connectionState: BackendConnectionState = .idle
    var rooms: [Room] = []
    var hasProfile = false
    var currentUserID: UUID?
    var errorMessage: String?
    var successMessage: String?
    var isWorking = false
    var groupOperation: GroupOperation = .idle
    var newRoomName = ""
    var inviteCode = ""
    var lastCreatedInviteCode: String?
    var launchAtLogin: Bool
    private(set) var unreadCounts: [UUID: Int] = [:]
    private var basePresence: [MemberPresenceKey: PresenceState] = [:]
    private var typingMembers: Set<MemberPresenceKey> = []

    init(preferences: AppPreferences) {
        self.preferences = preferences
        self.overlayVisibility = OverlayVisibility(isVisible: preferences.overlayVisible)
        self.nickname = preferences.nickname
        self.selectedCharacterID = PixelCharacterCatalog.canonicalID(for: preferences.selectedCharacterID)
        self.launchAtLogin = preferences.launchAtLogin
    }

    func setOverlayVisibility(_ visibility: OverlayVisibility) {
        overlayVisibility = visibility
        preferences.overlayVisible = visibility.isVisible
    }

    func acceptDraft() -> String? {
        let normalized = MessageValidator.normalized(draft)
        guard MessageValidator.isValid(normalized) else { return nil }
        draft = ""
        return normalized
    }

    var activeRoom: Room? {
        if let activeRoomID = preferences.activeRoomID,
           let match = rooms.first(where: { $0.id == activeRoomID }) {
            return match
        }
        return rooms.first
    }

    var realtimeActiveRoomID: UUID? {
        if case .switching(let roomID) = groupOperation { return roomID }
        return resolvedActiveRoomID(in: rooms)
    }

    func resolvedActiveRoomID(in availableRooms: [Room]) -> UUID? {
        if let preferredRoomID = preferences.activeRoomID,
           availableRooms.contains(where: { $0.id == preferredRoomID }) {
            return preferredRoomID
        }
        return availableRooms.first?.id
    }

    var groupMutationsDisabled: Bool {
        isWorking || groupOperation.blocksMutations
    }

    func apply(snapshot: BackendSnapshot, currentUserID: UUID?) {
        self.currentUserID = currentUserID
        hasProfile = snapshot.profile != nil
        var updatedRooms = snapshot.rooms
        let previousBasePresence = basePresence
        let previousTypingMembers = typingMembers
        for roomIndex in updatedRooms.indices {
            for memberIndex in updatedRooms[roomIndex].members.indices {
                let member = updatedRooms[roomIndex].members[memberIndex]
                let key = MemberPresenceKey(roomID: updatedRooms[roomIndex].id, userID: member.userID)
                if let state = previousBasePresence[key] {
                    updatedRooms[roomIndex].members[memberIndex].presence = previousTypingMembers.contains(key)
                        ? .typing
                        : state
                }
            }
        }
        rooms = updatedRooms
        let retainedRoomIDs = Set(updatedRooms.map(\.id))
        messageLedger.retain(roomIDs: retainedRoomIDs)
        messageOutbox.retain(roomIDs: retainedRoomIDs)
        unreadCounts = unreadCounts.filter { roomID, _ in
            updatedRooms.contains(where: { $0.id == roomID })
        }
        let validKeys = Set(updatedRooms.flatMap { room in
            room.members.map { member in
                MemberPresenceKey(roomID: room.id, userID: member.userID)
            }
        })
        basePresence = Dictionary(uniqueKeysWithValues: updatedRooms.flatMap { room in
            room.members.map { member in
                let key = MemberPresenceKey(roomID: room.id, userID: member.userID)
                return (key, previousBasePresence[key] ?? member.presence)
            }
        })
        typingMembers = previousTypingMembers.intersection(validKeys)
        if let profile = snapshot.profile {
            nickname = profile.nickname
            preferences.nickname = profile.nickname
            selectedCharacterID = PixelCharacterCatalog.canonicalID(for: profile.characterID)
            preferences.selectedCharacterID = selectedCharacterID
        }
        preferences.activeRoomID = resolvedActiveRoomID(in: rooms)
        preferences.onboardingComplete = snapshot.profile != nil && !rooms.isEmpty
    }

    var effectiveLocalPresence: PresenceState {
        switch connectionState {
        case .online:
            presence
        case .connecting:
            .reconnecting
        case .idle, .failed:
            .offline
        }
    }

    var pixelWorldMembers: [PixelWorldMember] {
        guard let activeRoom else { return [] }
        return activeRoom.members.compactMap { member in
            let key = MemberPresenceKey(roomID: activeRoom.id, userID: member.userID)
            let isCurrentUser = member.userID == currentUserID
            let isTyping = typingMembers.contains(key)
            let baseState = isCurrentUser
                ? effectiveLocalPresence
                : (basePresence[key] ?? (member.presence == .typing ? .online : member.presence))
            guard isCurrentUser || preferences.showOfflineMembers || baseState != .offline else { return nil }
            return PixelWorldMember(
                id: member.userID,
                nickname: ProfileValidator.displayNickname(member.nickname),
                characterID: PixelCharacterCatalog.canonicalID(for: member.characterID),
                presence: baseState,
                isTyping: isTyping,
                isCurrentUser: isCurrentUser
            )
        }
    }

    var activeBubbles: [ActiveBubble] { bubbleLedger.bubbles }

    var totalUnreadCount: Int {
        unreadCounts.values.reduce(0, +)
    }

    var activeRoomUnreadCount: Int {
        activeRoom.map { unreadCounts[$0.id, default: 0] } ?? 0
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

    func updatePresence(roomID: UUID, userID: UUID, state: PresenceState) {
        let key = MemberPresenceKey(roomID: roomID, userID: userID)
        basePresence[key] = state
        if state == .offline {
            typingMembers.remove(key)
        }
        guard let roomIndex = rooms.firstIndex(where: { $0.id == roomID }),
              let memberIndex = rooms[roomIndex].members.firstIndex(where: { $0.userID == userID })
        else { return }
        rooms[roomIndex].members[memberIndex].presence = typingMembers.contains(key) ? .typing : state
    }

    func updateTyping(roomID: UUID, userID: UUID, active: Bool) {
        let key = MemberPresenceKey(roomID: roomID, userID: userID)
        if active {
            typingMembers.insert(key)
        } else {
            typingMembers.remove(key)
        }
        guard let roomIndex = rooms.firstIndex(where: { $0.id == roomID }),
              let memberIndex = rooms[roomIndex].members.firstIndex(where: { $0.userID == userID })
        else { return }
        if active {
            rooms[roomIndex].members[memberIndex].presence = .typing
        } else {
            rooms[roomIndex].members[memberIndex].presence = basePresence[key] ?? .online
        }
    }

    func setRealtimeConnected(_ connected: Bool) {
        // Typing is a transient Broadcast lease. A disconnect can lose the
        // matching typing_stop event, so never carry typing across reconnect.
        if !connected { typingMembers.removeAll() }
        for roomIndex in rooms.indices {
            for memberIndex in rooms[roomIndex].members.indices {
                let member = rooms[roomIndex].members[memberIndex]
                let key = MemberPresenceKey(roomID: rooms[roomIndex].id, userID: member.userID)
                if connected {
                    rooms[roomIndex].members[memberIndex].presence = typingMembers.contains(key)
                        ? .typing
                        : (basePresence[key] ?? .offline)
                } else if member.presence != .offline {
                    rooms[roomIndex].members[memberIndex].presence = .reconnecting
                    if member.userID != currentUserID {
                        // Presence state is a lease on a specific socket. Never
                        // resurrect a remote user's old online/away state after
                        // reconnect; wait for a fresh join/sync instead.
                        basePresence[key] = .offline
                    }
                }
            }
        }
    }

    func stageMessage(
        id: UUID,
        roomID: UUID,
        senderID: UUID,
        body: String,
        revealBubble: Bool = true,
        now: Date = .now
    ) {
        messageOutbox.stage(id: id, roomID: roomID, senderID: senderID, body: body, createdAt: now)
        if revealBubble, roomID == activeRoom?.id {
            bubbleLedger.show(
                senderID: senderID,
                messageID: id,
                body: body,
                expiresAt: now.addingTimeInterval(ActiveBubbleLedger.defaultLifetime)
            )
        }
    }

    @discardableResult
    func confirmMessage(_ message: ChatMessage, revealBubble: Bool = true) -> Bool {
        let wasOutgoing = messageOutbox.confirm(id: message.id, roomID: message.roomID)
        let wasNewToLedger = messageLedger.confirm(message)
        let isNew = wasNewToLedger && !wasOutgoing
        if isNew, revealBubble, message.roomID == activeRoom?.id {
            bubbleLedger.show(
                senderID: message.senderID,
                messageID: message.id,
                body: message.body,
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
    }
}

private struct MemberPresenceKey: Hashable {
    let roomID: UUID
    let userID: UUID
}
