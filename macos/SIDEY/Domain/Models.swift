import CoreGraphics
import Foundation

enum LaunchReason: String, Codable, Sendable {
    case firstRun
    case manual
    case loginItem
}

enum LaunchRouter {
    static let loginItemArgument = "--sidey-login-item"

    static func reason(hasShownNativeLanding: Bool, arguments: [String]) -> LaunchReason {
        guard hasShownNativeLanding else { return .firstRun }
        return arguments.contains(loginItemArgument) ? .loginItem : .manual
    }
}

enum OverlayMode: String, Codable, Sendable {
    case locked
    case editing
}

enum OverlayVisibility: String, Codable, Sendable {
    case hidden
    case visible

    init(isVisible: Bool) {
        self = isVisible ? .visible : .hidden
    }

    var isVisible: Bool { self == .visible }
}

enum BackendBootstrapState: Equatable, Sendable {
    case pending
    case ready
    case failed
}

enum FirstRunDestination: Equatable, Sendable {
    case waiting
    case onboarding
    case overlay
    case recovery
}

enum FirstRunTransition {
    static func destination(
        landingCompleted: Bool,
        onboardingComplete: Bool,
        backendState: BackendBootstrapState
    ) -> FirstRunDestination {
        guard landingCompleted else { return .waiting }
        guard onboardingComplete else { return .onboarding }
        return switch backendState {
        case .pending: .waiting
        case .ready: .overlay
        case .failed: .recovery
        }
    }
}

enum OverlayRevealPolicy {
    static func isVisible(
        requested: Bool,
        onboardingComplete: Bool,
        backendState: BackendBootstrapState
    ) -> Bool {
        requested && onboardingComplete && backendState == .ready
    }
}

enum PresenceState: String, Codable, CaseIterable, Sendable {
    case online
    case typing
    case away
    case offline
    case reconnecting
}

enum SettingsPage: String, CaseIterable, Identifiable, Sendable {
    case profile
    case groups
    case app

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile: "내 프로필"
        case .groups: "그룹"
        case .app: "앱 설정"
        }
    }

    var systemImage: String {
        switch self {
        case .profile: "person.crop.circle"
        case .groups: "person.3"
        case .app: "gearshape"
        }
    }
}

struct Profile: Codable, Equatable, Sendable {
    let id: UUID
    var nickname: String
    var characterID: String
}

struct Room: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var ownerID: UUID
    var members: [RoomMember]
    var inviteCodeHint: String
    var inviteVersion: Int
}

struct RoomMember: Codable, Equatable, Identifiable, Sendable {
    var id: UUID { userID }
    let userID: UUID
    var nickname: String
    var characterID: String
    var presence: PresenceState
}

struct ChatMessage: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let roomID: UUID
    let senderID: UUID
    let body: String
    let createdAt: Date
}

enum MessageDeliveryState: Equatable, Sendable {
    case pending
    case confirmed
}

struct MessageLedgerEntry: Equatable, Identifiable, Sendable {
    let id: UUID
    let roomID: UUID
    var body: String
    var createdAt: Date
    var state: MessageDeliveryState
}

struct MessageLedger: Equatable, Sendable {
    private(set) var entries: [MessageLedgerEntry] = []

    mutating func stage(id: UUID, roomID: UUID, body: String, createdAt: Date = .now) {
        guard !entries.contains(where: { $0.id == id }) else { return }
        entries.append(MessageLedgerEntry(
            id: id,
            roomID: roomID,
            body: body,
            createdAt: createdAt,
            state: .pending
        ))
    }

    @discardableResult
    mutating func confirm(_ message: ChatMessage) -> Bool {
        let wasKnown = entries.contains(where: { $0.id == message.id })
        if let index = entries.firstIndex(where: { $0.id == message.id }) {
            entries[index].body = message.body
            entries[index].createdAt = message.createdAt
            entries[index].state = .confirmed
        } else {
            entries.append(MessageLedgerEntry(
                id: message.id,
                roomID: message.roomID,
                body: message.body,
                createdAt: message.createdAt,
                state: .confirmed
            ))
        }
        entries.sort { lhs, rhs in
            lhs.createdAt == rhs.createdAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.createdAt < rhs.createdAt
        }
        return !wasKnown
    }

    mutating func replaceConfirmed(roomID: UUID, with messages: [ChatMessage]) {
        entries.removeAll { $0.roomID == roomID && $0.state == .confirmed }
        for message in messages where message.roomID == roomID {
            confirm(message)
        }
    }

    @discardableResult
    mutating func fail(id: UUID) -> String? {
        guard let index = entries.firstIndex(where: { $0.id == id && $0.state == .pending }) else { return nil }
        return entries.remove(at: index).body
    }

    var latest: MessageLedgerEntry? { entries.last }

    func latest(in roomID: UUID) -> MessageLedgerEntry? {
        entries.last(where: { $0.roomID == roomID })
    }
}

struct RealtimeRoomPlan: Equatable, Sendable {
    let desired: Set<UUID>
    let additions: Set<UUID>
    let removals: Set<UUID>
    let activeRoomID: UUID?

    static func make(existing: Set<UUID>, requested: [UUID], activeRoomID: UUID?) -> Self {
        let desired = Set(requested.prefix(5))
        return Self(
            desired: desired,
            additions: desired.subtracting(existing),
            removals: existing.subtracting(desired),
            activeRoomID: activeRoomID.flatMap { desired.contains($0) ? $0 : nil }
        )
    }
}

struct RealtimeConnectionTracker: Equatable, Sendable {
    private(set) var desiredRoomIDs: Set<UUID> = []
    private(set) var subscribedRoomIDs: Set<UUID> = []

    mutating func replaceDesiredRoomIDs(_ roomIDs: Set<UUID>) {
        desiredRoomIDs = roomIDs
        subscribedRoomIDs.formIntersection(roomIDs)
    }

    mutating func setSubscribed(_ subscribed: Bool, roomID: UUID) {
        guard desiredRoomIDs.contains(roomID) else {
            subscribedRoomIDs.remove(roomID)
            return
        }
        if subscribed {
            subscribedRoomIDs.insert(roomID)
        } else {
            subscribedRoomIDs.remove(roomID)
        }
    }

    var isConnected: Bool {
        subscribedRoomIDs == desiredRoomIDs
    }
}

enum PresencePublicationPlan {
    static func state(
        for roomID: UUID,
        activeRoomID: UUID?,
        localPresence: PresenceState
    ) -> PresenceState {
        guard roomID == activeRoomID else { return .offline }
        return localPresence == .away ? .away : .online
    }
}

struct PresenceUpdate: Equatable, Sendable {
    let userID: UUID
    let state: PresenceState
}

enum TypingLeaseAction: Equatable, Sendable {
    case start(UUID)
    case stop(UUID)
}

struct TypingLease: Equatable, Sendable {
    private(set) var roomID: UUID?

    mutating func update(active: Bool, roomID requestedRoomID: UUID?) -> [TypingLeaseAction] {
        guard active, let requestedRoomID else {
            guard let roomID else { return [] }
            self.roomID = nil
            return [.stop(roomID)]
        }

        guard roomID != requestedRoomID else { return [] }
        var actions: [TypingLeaseAction] = []
        if let roomID { actions.append(.stop(roomID)) }
        roomID = requestedRoomID
        actions.append(.start(requestedRoomID))
        return actions
    }
}

enum PresenceChangePlan {
    /// Supabase Presence can report a state replacement as leave(old) and
    /// join(new) for the same key in one delta. The join must win without an
    /// intermediate/final offline overwrite.
    static func updates(
        joined: [UUID: PresenceState],
        left: Set<UUID>
    ) -> [PresenceUpdate] {
        let offline = left.subtracting(joined.keys).map {
            PresenceUpdate(userID: $0, state: .offline)
        }
        let current = joined.map {
            PresenceUpdate(userID: $0.key, state: $0.value)
        }
        return (offline + current).sorted { lhs, rhs in
            lhs.userID.uuidString < rhs.userID.uuidString
        }
    }
}

enum MessageValidator {
    static let maximumCharacters = 200
    static let maximumLines = 3

    static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValid(_ value: String) -> Bool {
        !value.isEmpty
            && value.count <= maximumCharacters
            && value.split(separator: "\n", omittingEmptySubsequences: false).count <= maximumLines
    }

    static func isValidDraft(_ value: String) -> Bool {
        value.count <= maximumCharacters
            && value.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .split(separator: "\n", omittingEmptySubsequences: false).count <= maximumLines
    }
}
