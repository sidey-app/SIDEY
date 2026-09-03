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
    case store
    case app

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile: "내 프로필"
        case .groups: "그룹"
        case .store: "꾸미기·상점"
        case .app: "앱 설정"
        }
    }

    var systemImage: String {
        switch self {
        case .profile: "person.crop.circle"
        case .groups: "person.2"
        case .store: "sparkles"
        case .app: "gearshape"
        }
    }
}

enum CommerceCatalog {
    static let starlightUpalupaProductID = "character_starlight_upalupa"
    static let starlightUpalupaCharacterID = "pixel_starlight_upalupa"
    static let starlightUpalupaEntitlementKey = "character:pixel_starlight_upalupa"
    static let starlightUpalupaDescription = "진주빛 몸과 별빛 아가미를 가진 우파루파예요. 온라인일 때 별이 은은하게 따라다니고, 더블클릭하면 별무리가 두 겹으로 팡 터져요."

    static let guineaPigProductID = "character_guinea_pig"
    static let guineaPigEntitlementKey = "character:pixel_guinea_pig"
    static let monkeyProductID = "character_monkey"
    static let monkeyEntitlementKey = "character:pixel_monkey"
    static let chinchillaProductID = "character_chinchilla"
    static let chinchillaEntitlementKey = "character:pixel_chinchilla"

    /// Product order is a presentation contract. Registering a future product
    /// here is enough for the existing store grid to render it.
    static let products: [CommerceProduct] = [
        .starlightUpalupa,
        .guineaPig,
        .monkey,
        .chinchilla,
    ]

    static func product(id: String) -> CommerceProduct? {
        products.first { $0.id == id }
    }
}

struct CommerceProduct: Equatable, Sendable {
    let id: String
    let displayName: String
    let description: String
    let characterID: String
    let entitlementKey: String
    let amountKRW: Int
    let currency: String
    let taxInclusive: Bool

    static let starlightUpalupa = CommerceProduct(
        id: CommerceCatalog.starlightUpalupaProductID,
        displayName: "별빛 우파루파",
        description: CommerceCatalog.starlightUpalupaDescription,
        characterID: CommerceCatalog.starlightUpalupaCharacterID,
        entitlementKey: CommerceCatalog.starlightUpalupaEntitlementKey,
        amountKRW: 1_900,
        currency: "KRW",
        taxInclusive: true
    )

    static let guineaPig = CommerceProduct(
        id: CommerceCatalog.guineaPigProductID,
        displayName: "아기 기니피그",
        description: "낮고 동글동글한 몸에 비대칭 삼색 무늬가 매력인 작은 친구예요.",
        characterID: PixelCharacterCatalog.pixelGuineaPigID,
        entitlementKey: CommerceCatalog.guineaPigEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let monkey = CommerceProduct(
        id: CommerceCatalog.monkeyProductID,
        displayName: "아기 원숭이",
        description: "세 갈래 머리털과 시안 목도리로 씩씩하게 산책하는 친구예요.",
        characterID: PixelCharacterCatalog.pixelMonkeyID,
        entitlementKey: CommerceCatalog.monkeyEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let chinchilla = CommerceProduct(
        id: CommerceCatalog.chinchillaProductID,
        displayName: "아기 친칠라",
        description: "크고 둥근 귀와 포근한 회색 털, 파란 목도리를 가진 친구예요.",
        characterID: PixelCharacterCatalog.pixelChinchillaID,
        entitlementKey: CommerceCatalog.chinchillaEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    var formattedPrice: String {
        amountKRW.formatted(.number.grouping(.automatic)) + "원"
    }
}

struct CommerceProductState: Equatable, Identifiable, Sendable {
    var product: CommerceProduct
    var purchaseState: CommercePurchaseState
    var isWorking: Bool

    var id: String { product.id }
}

enum CommercePurchaseState: Equatable, Sendable {
    case available
    case googleConnectionRequired
    case openingCheckout
    case confirming
    case owned
    case error(String)
    case refunded

    var label: String {
        switch self {
        case .available: "구매 가능"
        case .googleConnectionRequired: "Google 연결 필요"
        case .openingCheckout: "결제창 여는 중"
        case .confirming: "확인 중"
        case .owned: "보유 중"
        case .error: "오류"
        case .refunded: "환불됨"
        }
    }
}

struct CommerceState: Equatable, Sendable {
    let product: CommerceProduct
    let googleConnected: Bool
    let entitlementStatus: String?
    let latestOrderStatus: String?

    var purchaseState: CommercePurchaseState {
        if entitlementStatus == "active" { return .owned }
        if entitlementStatus == "refunded" || latestOrderStatus == "refunded" { return .refunded }
        return googleConnected ? .available : .googleConnectionRequired
    }
}

struct CommerceCheckout: Equatable, Sendable {
    let orderID: UUID
    let checkoutURL: URL
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
    var inviteVersion: Int = 0
    var inviteCodeReady: Bool = true
    var realtimeEpoch: Int = 1
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
    case failed
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
    static let maximumConfirmedPerRoom = 50
    static let retentionInterval = TimeInterval(ProductLimits.messageRetentionDays * 24 * 60 * 60)

    private(set) var entries: [MessageLedgerEntry] = []

    @discardableResult
    mutating func confirm(_ message: ChatMessage, now: Date = .now) -> Bool {
        let wasKnown = entries.contains(where: { $0.id == message.id })
        if let index = entries.firstIndex(where: { $0.id == message.id }) {
            entries[index].body = message.body
            entries[index].createdAt = message.createdAt
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
        sortAndPrune(now: now)
        return !wasKnown
    }

    mutating func replaceConfirmed(roomID: UUID, with messages: [ChatMessage], now: Date = .now) {
        entries.removeAll { $0.roomID == roomID }
        for message in messages where message.roomID == roomID {
            confirm(message, now: now)
        }
        sortAndPrune(now: now)
    }

    mutating func remove(id: UUID, roomID: UUID) {
        entries.removeAll { $0.id == id && $0.roomID == roomID }
    }

    mutating func retain(roomIDs: Set<UUID>) {
        entries.removeAll { !roomIDs.contains($0.roomID) }
    }

    mutating func prune(now: Date = .now) {
        sortAndPrune(now: now)
    }

    var latest: MessageLedgerEntry? { entries.last }

    func latest(in roomID: UUID) -> MessageLedgerEntry? {
        entries.last(where: { $0.roomID == roomID })
    }

    private mutating func sortAndPrune(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.retentionInterval)
        entries.removeAll { $0.createdAt < cutoff }
        entries.sort { lhs, rhs in
            lhs.createdAt == rhs.createdAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.createdAt < rhs.createdAt
        }

        let roomIDs = Set(entries.map(\.roomID))
        for roomID in roomIDs {
            let roomIndices = entries.indices.filter { entries[$0].roomID == roomID }
            let overflow = roomIndices.count - Self.maximumConfirmedPerRoom
            guard overflow > 0 else { continue }
            let removedIDs = Set(roomIndices.prefix(overflow).map { entries[$0].id })
            entries.removeAll { removedIDs.contains($0.id) }
        }
    }
}

enum OutgoingMessageState: Equatable, Sendable {
    case pending
    case failed
}

struct OutgoingMessage: Equatable, Identifiable, Sendable {
    let id: UUID
    let roomID: UUID
    let senderID: UUID
    let body: String
    let createdAt: Date
    var state: OutgoingMessageState
}

struct MessageOutbox: Equatable, Sendable {
    static let maximumFailedPerRoom = 50

    private(set) var entries: [OutgoingMessage] = []

    mutating func stage(
        id: UUID,
        roomID: UUID,
        senderID: UUID,
        body: String,
        createdAt: Date = .now
    ) {
        guard !entries.contains(where: { $0.id == id }) else { return }
        entries.append(OutgoingMessage(
            id: id,
            roomID: roomID,
            senderID: senderID,
            body: body,
            createdAt: createdAt,
            state: .pending
        ))
    }

    @discardableResult
    mutating func confirm(id: UUID, roomID: UUID) -> Bool {
        let previousCount = entries.count
        entries.removeAll { $0.id == id && $0.roomID == roomID }
        return entries.count != previousCount
    }

    mutating func retain(roomIDs: Set<UUID>) {
        entries.removeAll { !roomIDs.contains($0.roomID) }
    }

    @discardableResult
    mutating func fail(id: UUID, roomID: UUID) -> OutgoingMessage? {
        guard let index = entries.firstIndex(where: {
            $0.id == id && $0.roomID == roomID && $0.state == .pending
        }) else { return nil }
        entries[index].state = .failed
        pruneFailed(roomID: roomID)
        return entries.first(where: { $0.id == id && $0.roomID == roomID })
    }

    private mutating func pruneFailed(roomID: UUID) {
        let failed = entries
            .filter { $0.roomID == roomID && $0.state == .failed }
            .sorted { $0.createdAt < $1.createdAt }
        let overflow = failed.count - Self.maximumFailedPerRoom
        guard overflow > 0 else { return }
        let removedIDs = Set(failed.prefix(overflow).map(\.id))
        entries.removeAll { removedIDs.contains($0.id) }
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

struct RealtimeTopology: Equatable, Sendable {
    let roomEpochs: [UUID: Int]

    init(rooms: some Sequence<Room>) {
        roomEpochs = Dictionary(uniqueKeysWithValues: rooms.prefix(5).map {
            ($0.id, $0.realtimeEpoch)
        })
    }

    init(channelEpochs: [UUID: Int]) {
        roomEpochs = channelEpochs
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

struct CharacterThrowEvent: Equatable, Identifiable, Sendable {
    let id: UUID
    let roomID: UUID
    let actorUserID: UUID
    let targetUserID: UUID
    let sourceCharacterID: String
}

enum CharacterThrowTargetPolicy {
    static func canTarget(_ member: PixelWorldMember) -> Bool {
        !member.isCurrentUser
    }
}

struct CharacterThrowCooldown: Equatable, Sendable {
    static let duration: TimeInterval = 0.5
    private var lastAcceptedUptimeByActor: [UUID: TimeInterval] = [:]

    mutating func accept(actorUserID: UUID, uptime: TimeInterval) -> Bool {
        guard uptime.isFinite else { return false }
        if let last = lastAcceptedUptimeByActor[actorUserID], uptime - last < Self.duration {
            return false
        }
        lastAcceptedUptimeByActor[actorUserID] = uptime
        return true
    }
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
