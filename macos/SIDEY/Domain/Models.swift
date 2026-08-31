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

enum ManualReopenPolicy {
    static func shouldOpenSettings(
        hasShownNativeLanding: Bool,
        composerVisible: Bool,
        originatesFromOverlayInteraction: Bool = false
    ) -> Bool {
        hasShownNativeLanding && !composerVisible && !originatesFromOverlayInteraction
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

enum OverlayEdge: String, Codable, CaseIterable, Identifiable, Sendable {
    case bottom
    case left
    case right
    case top

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bottom: "하단"
        case .left: "좌측"
        case .right: "우측"
        case .top: "상단"
        }
    }

    var isHorizontal: Bool { self == .bottom || self == .top }

    /// Pixel art is authored feet-down. Rotate the complete presentation so
    /// the feet point toward the selected screen edge.
    var presentationRotation: CGFloat {
        switch self {
        case .bottom: 0
        case .left: -.pi / 2
        case .right: .pi / 2
        case .top: .pi
        }
    }
}

enum OverlaySpan: String, Codable, CaseIterable, Identifiable, Sendable {
    case third
    case half
    case full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .third: "1/3"
        case .half: "1/2"
        case .full: "전체"
        }
    }

    var fraction: CGFloat {
        switch self {
        case .third: 1.0 / 3.0
        case .half: 1.0 / 2.0
        case .full: 1
        }
    }
}

struct OverlayRegionPreference: Codable, Equatable, Sendable {
    var edge: OverlayEdge
    var span: OverlaySpan
    var screenIdentifier: String?

    static let defaultValue = OverlayRegionPreference(
        edge: .bottom,
        span: .full,
        screenIdentifier: nil
    )
}

struct OverlayScreenOption: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
}

enum BackendBootstrapState: Equatable, Sendable {
    case pending
    case ready
    case failed
}

enum GroupOperation: Equatable, Sendable {
    case idle
    case creating
    case joining
    case switching(UUID)

    var blocksMutations: Bool { self != .idle }

    var allowsRoomSelection: Bool {
        switch self {
        case .idle, .switching: true
        case .creating, .joining: false
        }
    }

    func isSwitching(to roomID: UUID) -> Bool {
        self == .switching(roomID)
    }

    var createButtonTitle: String {
        self == .creating ? "만드는 중…" : "그룹 만들기"
    }

    var joinButtonTitle: String {
        self == .joining ? "참여 중…" : "코드로 참여"
    }
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
        case .groups: "person.2"
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
    let senderID: UUID
    var body: String
    var createdAt: Date
    var state: MessageDeliveryState
}

struct MessageLedger: Equatable, Sendable {
    private(set) var entries: [MessageLedgerEntry] = []

    mutating func stage(
        id: UUID,
        roomID: UUID,
        senderID: UUID,
        body: String,
        createdAt: Date = .now
    ) {
        guard !entries.contains(where: { $0.id == id }) else { return }
        entries.append(MessageLedgerEntry(
            id: id,
            roomID: roomID,
            senderID: senderID,
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
                senderID: message.senderID,
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

struct ActiveBubble: Equatable, Identifiable, Sendable {
    var id: UUID { messageID }
    let senderID: UUID
    let messageID: UUID
    let body: String
    let expiresAt: Date
}

struct ActiveBubbleLedger: Equatable, Sendable {
    static let maximumVisible = 4
    static let defaultLifetime: TimeInterval = 10

    private(set) var bubbles: [ActiveBubble] = []

    mutating func show(
        senderID: UUID,
        messageID: UUID,
        body: String,
        expiresAt: Date = .now.addingTimeInterval(Self.defaultLifetime)
    ) {
        bubbles.removeAll { $0.senderID == senderID || $0.messageID == messageID }
        bubbles.append(ActiveBubble(
            senderID: senderID,
            messageID: messageID,
            body: body,
            expiresAt: expiresAt
        ))
        bubbles.sort { lhs, rhs in
            lhs.expiresAt == rhs.expiresAt
                ? lhs.messageID.uuidString < rhs.messageID.uuidString
                : lhs.expiresAt < rhs.expiresAt
        }
        if bubbles.count > Self.maximumVisible {
            bubbles.removeFirst(bubbles.count - Self.maximumVisible)
        }
    }

    mutating func remove(messageID: UUID) {
        bubbles.removeAll { $0.messageID == messageID }
    }

    mutating func removeAll() {
        bubbles.removeAll()
    }

    mutating func prune(at date: Date = .now) {
        bubbles.removeAll { $0.expiresAt <= date }
    }
}

struct PixelWorldMember: Equatable, Identifiable, Sendable {
    let id: UUID
    let nickname: String
    let characterID: String
    let presence: PresenceState
    let isTyping: Bool
    let isCurrentUser: Bool
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

enum RealtimeRecoveryPolicy {
    static let watchdogInterval: TimeInterval = 5
    static let maximumDelay: TimeInterval = 30

    static func delay(forAttempt attempt: Int) -> TimeInterval {
        let exponent = Double(max(0, min(attempt - 1, 5)))
        return min(8 * pow(2, exponent), maximumDelay)
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

struct CharacterPulseEvent: Equatable, Identifiable, Sendable {
    let id: UUID
    let roomID: UUID
    let userID: UUID
}

struct CharacterPulseCooldown: Equatable, Sendable {
    static let duration: TimeInterval = 1

    private struct Key: Hashable, Sendable {
        let roomID: UUID
        let userID: UUID
    }

    private var lastAcceptedUptime: [Key: TimeInterval] = [:]

    mutating func accept(roomID: UUID, userID: UUID, uptime: TimeInterval) -> Bool {
        guard uptime.isFinite else { return false }
        let key = Key(roomID: roomID, userID: userID)
        if let last = lastAcceptedUptime[key], uptime - last < Self.duration {
            return false
        }
        lastAcceptedUptime[key] = uptime
        return true
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

enum ProfileValidator {
    static let minimumNicknameCharacters = 2
    static let maximumNicknameCharacters = 8

    static func normalizedNickname(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValidNickname(_ value: String) -> Bool {
        let normalized = normalizedNickname(value)
        return normalized.count >= minimumNicknameCharacters
            && normalized.count <= maximumNicknameCharacters
            && value.rangeOfCharacter(from: .newlines) == nil
            && !value.contains("\t")
    }

    static func limitedNicknameDraft(_ value: String) -> String {
        let singleLine = value.filter { !$0.isNewline && $0 != "\t" }
        return String(singleLine.prefix(maximumNicknameCharacters))
    }

    static func displayNickname(_ value: String) -> String {
        String(normalizedNickname(value).prefix(maximumNicknameCharacters))
    }
}

enum RoomNameValidator {
    static let minimumCharacters = 1
    static let maximumCharacters = 20

    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValid(_ value: String) -> Bool {
        let normalized = normalized(value)
        return normalized.count >= minimumCharacters
            && normalized.count <= maximumCharacters
            && value.rangeOfCharacter(from: .newlines) == nil
            && !value.contains("\t")
    }

    static func limitedDraft(_ value: String) -> String {
        let singleLine = value.filter { !$0.isNewline && $0 != "\t" }
        let normalized = normalized(singleLine)
        guard normalized.count > maximumCharacters else { return singleLine }
        return String(normalized.prefix(maximumCharacters))
    }
}

enum RoomManagementPolicy {
    static func isOwner(_ member: RoomMember, in room: Room) -> Bool {
        room.ownerID == member.userID
    }

    static func canManage(_ room: Room, currentUserID: UUID?) -> Bool {
        room.ownerID == currentUserID
    }

    static func canRemove(
        _ member: RoomMember,
        from room: Room,
        currentUserID: UUID?
    ) -> Bool {
        canManage(room, currentUserID: currentUserID)
            && member.userID != currentUserID
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
