import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var preferences: AppPreferences
    var overlayVisibility: OverlayVisibility
    var overlayVisible: Bool { overlayVisibility.isVisible }
    var overlayMode: OverlayMode
    var presence: PresenceState = .online
    var nickname: String
    var draft = ""
    var latestMessage: String?
    private(set) var messageLedger = MessageLedger()
    var activeSettingsPage: SettingsPage = .profile
    var connectionState: BackendConnectionState = .idle
    var rooms: [Room] = []
    var hasProfile = false
    var currentUserID: UUID?
    var errorMessage: String?
    var successMessage: String?
    var isWorking = false
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
        self.overlayMode = preferences.overlayLocked ? .locked : .editing
        self.nickname = preferences.nickname
        self.launchAtLogin = preferences.launchAtLogin
    }

    func setOverlayVisibility(_ visibility: OverlayVisibility) {
        overlayVisibility = visibility
        preferences.overlayVisible = visibility.isVisible
    }

    func setOverlayMode(_ mode: OverlayMode) {
        overlayMode = mode
        preferences.overlayLocked = mode == .locked
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
        }
        if activeRoom == nil || !rooms.contains(where: { $0.id == preferences.activeRoomID }) {
            preferences.activeRoomID = rooms.first?.id
        }
        preferences.onboardingComplete = snapshot.profile != nil && !rooms.isEmpty
    }

    var displayedMember: RoomMember? {
        guard let activeRoom else { return nil }
        return activeRoom.members.first(where: { $0.userID != currentUserID }) ?? activeRoom.members.first
    }

    var avatarPresence: PresenceState {
        guard let displayedMember else { return effectiveLocalPresence }
        return displayedMember.userID == currentUserID
            ? effectiveLocalPresence
            : displayedMember.presence
    }

    private var effectiveLocalPresence: PresenceState {
        switch connectionState {
        case .online:
            presence
        case .connecting:
            .reconnecting
        case .idle, .failed:
            .offline
        }
    }

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
        guard let roomIndex = rooms.firstIndex(where: { $0.id == roomID }),
              let memberIndex = rooms[roomIndex].members.firstIndex(where: { $0.userID == userID })
        else { return }
        let key = MemberPresenceKey(roomID: roomID, userID: userID)
        basePresence[key] = state
        if state == .offline {
            typingMembers.remove(key)
        }
        rooms[roomIndex].members[memberIndex].presence = typingMembers.contains(key) ? .typing : state
    }

    func updateTyping(roomID: UUID, userID: UUID, active: Bool) {
        guard let roomIndex = rooms.firstIndex(where: { $0.id == roomID }),
              let memberIndex = rooms[roomIndex].members.firstIndex(where: { $0.userID == userID })
        else { return }
        let key = MemberPresenceKey(roomID: roomID, userID: userID)
        if active {
            typingMembers.insert(key)
            rooms[roomIndex].members[memberIndex].presence = .typing
        } else {
            typingMembers.remove(key)
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
                }
            }
        }
    }

    func stageMessage(id: UUID, roomID: UUID, body: String, revealLatest: Bool = true) {
        messageLedger.stage(id: id, roomID: roomID, body: body)
        if revealLatest { refreshLatestMessage() }
    }

    @discardableResult
    func confirmMessage(_ message: ChatMessage, revealLatest: Bool = true) -> Bool {
        let isNew = messageLedger.confirm(message)
        if revealLatest { refreshLatestMessage() }
        return isNew
    }

    func failMessage(id: UUID, revealLatest: Bool = true) -> String? {
        let body = messageLedger.fail(id: id)
        if revealLatest { refreshLatestMessage() }
        return body
    }

    func replaceMessages(roomID: UUID, with messages: [ChatMessage], revealLatest: Bool = true) {
        messageLedger.replaceConfirmed(roomID: roomID, with: messages)
        if revealLatest { refreshLatestMessage() }
    }

    func refreshLatestMessage() {
        latestMessage = activeRoom.map { messageLedger.latest(in: $0.id)?.body } ?? nil
    }
}

private struct MemberPresenceKey: Hashable {
    let roomID: UUID
    let userID: UUID
}
