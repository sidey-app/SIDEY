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

    static let characterProducts: [CommerceProduct] = [
        .starlightUpalupa,
        .guineaPig,
        .monkey,
        .chinchilla,
    ]

    static let cosmeticProducts: [CommerceProduct] = [
        .bunnyPinkBubble,
        .butterChickBubble,
        .starryCatBubble,
        .bouncyHeart,
        .toyCannon,
        .squeakyDuck,
    ]

    /// App Store intentionally keeps the existing four character IAPs. The
    /// direct build receives the broader server catalog.
    static var products: [CommerceProduct] {
#if APP_STORE
        characterProducts
#else
        characterProducts + cosmeticProducts
#endif
    }

    static func product(id: String) -> CommerceProduct? {
        products.first { $0.id == id }
    }
}

enum CommerceProductKind: String, Codable, CaseIterable, Sendable {
    case character
    case bubble
    case throwable

    var title: String {
        switch self {
        case .character: "캐릭터"
        case .bubble: "말풍선"
        case .throwable: "투척물"
        }
    }
}

struct CommerceProduct: Equatable, Sendable {
    let id: String
    let displayName: String
    let description: String
    let kind: CommerceProductKind
    let catalogItemID: String
    let characterID: String?
    let entitlementKey: String
    let sortOrder: Int
    let amountKRW: Int
    let currency: String
    let taxInclusive: Bool

    init(
        id: String,
        displayName: String,
        description: String,
        kind: CommerceProductKind = .character,
        catalogItemID: String? = nil,
        characterID: String?,
        entitlementKey: String,
        sortOrder: Int = 0,
        amountKRW: Int,
        currency: String,
        taxInclusive: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.kind = kind
        self.catalogItemID = catalogItemID ?? characterID ?? id
        self.characterID = characterID
        self.entitlementKey = entitlementKey
        self.sortOrder = sortOrder
        self.amountKRW = amountKRW
        self.currency = currency
        self.taxInclusive = taxInclusive
    }

    static let starlightUpalupa = CommerceProduct(
        id: CommerceCatalog.starlightUpalupaProductID,
        displayName: "별빛 우파루파",
        description: CommerceCatalog.starlightUpalupaDescription,
        characterID: CommerceCatalog.starlightUpalupaCharacterID,
        entitlementKey: CommerceCatalog.starlightUpalupaEntitlementKey,
        sortOrder: 10,
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
        sortOrder: 20,
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
        sortOrder: 30,
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
        sortOrder: 40,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let bunnyPinkBubble = CommerceProduct(
        id: "bubble_bunny_pink", displayName: "핑크 토끼 말풍선",
        description: "토끼 장식과 또렷한 진한 글자가 있는 분홍 말풍선이에요.",
        kind: .bubble, catalogItemID: "bubble_bunny_pink", characterID: nil,
        entitlementKey: "bubble:bubble_bunny_pink", sortOrder: 110,
        amountKRW: 1_900, currency: "KRW", taxInclusive: true
    )

    static let butterChickBubble = CommerceProduct(
        id: "bubble_butter_chick", displayName: "버터 병아리 말풍선",
        description: "병아리 장식과 또렷한 진한 글자가 있는 버터색 말풍선이에요.",
        kind: .bubble, catalogItemID: "bubble_butter_chick", characterID: nil,
        entitlementKey: "bubble:bubble_butter_chick", sortOrder: 120,
        amountKRW: 1_900, currency: "KRW", taxInclusive: true
    )

    static let starryCatBubble = CommerceProduct(
        id: "bubble_starry_cat", displayName: "별밤 고양이 말풍선",
        description: "별고양이 장식과 밝은 글자가 있는 남보라 말풍선이에요.",
        kind: .bubble, catalogItemID: "bubble_starry_cat", characterID: nil,
        entitlementKey: "bubble:bubble_starry_cat", sortOrder: 130,
        amountKRW: 1_900, currency: "KRW", taxInclusive: true
    )

    static let bouncyHeart = CommerceProduct(
        id: "throwable_bouncy_heart", displayName: "통통 하트",
        description: "통통 튀며 날아가 마음을 전하는 하트예요.",
        kind: .throwable, catalogItemID: "throwable_bouncy_heart", characterID: nil,
        entitlementKey: "throwable:throwable_bouncy_heart", sortOrder: 210,
        amountKRW: 990, currency: "KRW", taxInclusive: true
    )

    static let toyCannon = CommerceProduct(
        id: "throwable_toy_cannon", displayName: "미니 대포",
        description: "캐릭터 앞 몸통에 대포가 나타나 심지탄을 쏘고 상대 몸통에서 펑 터져요.",
        kind: .throwable, catalogItemID: "throwable_toy_cannon", characterID: nil,
        entitlementKey: "throwable:throwable_toy_cannon", sortOrder: 220,
        amountKRW: 3_900, currency: "KRW", taxInclusive: true
    )

    static let squeakyDuck = CommerceProduct(
        id: "throwable_squeaky_duck", displayName: "삑삑 오리",
        description: "노란 오리가 빙글빙글 날아가는 장난스러운 투척물이에요.",
        kind: .throwable, catalogItemID: "throwable_squeaky_duck", characterID: nil,
        entitlementKey: "throwable:throwable_squeaky_duck", sortOrder: 230,
        amountKRW: 990, currency: "KRW", taxInclusive: true
    )

    var formattedPrice: String {
        amountKRW.formatted(.number.grouping(.automatic)) + "원"
    }
}

struct CommerceProductState: Equatable, Identifiable, Sendable {
    var product: CommerceProduct
    var purchaseState: CommercePurchaseState
    var isWorking: Bool
    var localizedPrice: String?
    var isEquipped: Bool

    init(
        product: CommerceProduct,
        purchaseState: CommercePurchaseState,
        isWorking: Bool,
        localizedPrice: String? = nil,
        isEquipped: Bool = false
    ) {
        self.product = product
        self.purchaseState = purchaseState
        self.isWorking = isWorking
        self.localizedPrice = localizedPrice
        self.isEquipped = isEquipped
    }

    var id: String { product.id }
    var formattedPrice: String { localizedPrice ?? product.formattedPrice }
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
    let isEquipped: Bool

    init(
        product: CommerceProduct,
        googleConnected: Bool,
        entitlementStatus: String?,
        latestOrderStatus: String?,
        isEquipped: Bool = false
    ) {
        self.product = product
        self.googleConnected = googleConnected
        self.entitlementStatus = entitlementStatus
        self.latestOrderStatus = latestOrderStatus
        self.isEquipped = isEquipped
    }

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
    var equippedBubbleStyleID: String?
    var equippedThrowableID: String?

    init(
        id: UUID,
        nickname: String,
        characterID: String,
        equippedBubbleStyleID: String? = nil,
        equippedThrowableID: String? = nil
    ) {
        self.id = id
        self.nickname = nickname
        self.characterID = characterID
        self.equippedBubbleStyleID = equippedBubbleStyleID
        self.equippedThrowableID = equippedThrowableID
    }
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
    var equippedBubbleStyleID: String? = nil
}

struct ChatMessage: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let roomID: UUID
    let senderID: UUID
    let body: String
    let createdAt: Date
    let bubbleStyleID: String?

    init(
        id: UUID,
        roomID: UUID,
        senderID: UUID,
        body: String,
        createdAt: Date,
        bubbleStyleID: String? = nil
    ) {
        self.id = id
        self.roomID = roomID
        self.senderID = senderID
        self.body = body
        self.createdAt = createdAt
        self.bubbleStyleID = bubbleStyleID
    }
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
    var bubbleStyleID: String? = nil
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
            entries[index].bubbleStyleID = message.bubbleStyleID
        } else {
            entries.append(MessageLedgerEntry(
                id: message.id,
                roomID: message.roomID,
                senderID: message.senderID,
                body: message.body,
                createdAt: message.createdAt,
                state: .confirmed,
                bubbleStyleID: message.bubbleStyleID
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
    let bubbleStyleID: String?

    init(
        senderID: UUID,
        messageID: UUID,
        body: String,
        expiresAt: Date,
        bubbleStyleID: String? = nil
    ) {
        self.senderID = senderID
        self.messageID = messageID
        self.body = body
        self.expiresAt = expiresAt
        self.bubbleStyleID = bubbleStyleID
    }
}

struct ActiveBubbleLedger: Equatable, Sendable {
    static let maximumVisiblePerSender = 2
    static let defaultLifetime: TimeInterval = 10

    private(set) var bubbles: [ActiveBubble] = []

    mutating func show(
        senderID: UUID,
        messageID: UUID,
        body: String,
        bubbleStyleID: String? = nil,
        expiresAt: Date = .now.addingTimeInterval(Self.defaultLifetime)
    ) {
        bubbles.removeAll { $0.messageID == messageID }
        bubbles.append(ActiveBubble(
            senderID: senderID,
            messageID: messageID,
            body: body,
            expiresAt: expiresAt,
            bubbleStyleID: bubbleStyleID
        ))
        bubbles.sort { lhs, rhs in
            lhs.expiresAt == rhs.expiresAt
                ? lhs.messageID.uuidString < rhs.messageID.uuidString
                : lhs.expiresAt < rhs.expiresAt
        }
        let senderBubbles = bubbles.filter { $0.senderID == senderID }
        if senderBubbles.count > Self.maximumVisiblePerSender {
            let removedIDs = Set(
                senderBubbles
                    .prefix(senderBubbles.count - Self.maximumVisiblePerSender)
                    .map(\.messageID)
            )
            bubbles.removeAll { removedIDs.contains($0.messageID) }
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
    let equippedBubbleStyleID: String?

    init(
        id: UUID,
        nickname: String,
        characterID: String,
        presence: PresenceState,
        isTyping: Bool,
        isCurrentUser: Bool,
        equippedBubbleStyleID: String? = nil
    ) {
        self.id = id
        self.nickname = nickname
        self.characterID = characterID
        self.presence = presence
        self.isTyping = isTyping
        self.isCurrentUser = isCurrentUser
        self.equippedBubbleStyleID = equippedBubbleStyleID
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

    func isSubscribed(roomID: UUID) -> Bool {
        subscribedRoomIDs.contains(roomID)
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

struct RealtimeTopologyUpdatePlan: Equatable, Sendable {
    let additions: Set<UUID>
    let removals: Set<UUID>

    static func make(live: RealtimeTopology, requestedRooms: [Room]) -> Self {
        let desired = RealtimeTopology(rooms: requestedRooms)
        let additions = Set(desired.roomEpochs.compactMap { roomID, desiredEpoch in
            live.roomEpochs[roomID] == desiredEpoch ? nil : roomID
        })
        let removals = Set(live.roomEpochs.compactMap { roomID, liveEpoch in
            desired.roomEpochs[roomID] == liveEpoch ? nil : roomID
        })
        return Self(additions: additions, removals: removals)
    }
}

struct RealtimeDesiredTopology: Equatable, Sendable {
    private(set) var roomEpochs: [UUID: Int] = [:]

    mutating func replace(rooms: some Sequence<Room>) {
        roomEpochs = Dictionary(uniqueKeysWithValues: rooms.prefix(5).map {
            ($0.id, $0.realtimeEpoch)
        })
    }

    var roomIDs: Set<UUID> {
        Set(roomEpochs.keys)
    }

    func epoch(for roomID: UUID) -> Int? {
        roomEpochs[roomID]
    }
}

enum RealtimeChannelPairPolicy {
    static func isSubscribed(database: Bool, ephemeral: Bool) -> Bool {
        database && ephemeral
    }
}

enum RealtimeChannelGenerationPolicy {
    static func accepts(
        candidateGeneration: Int,
        currentGeneration: Int,
        desiredEpoch: Int?,
        channelEpoch: Int?
    ) -> Bool {
        candidateGeneration == currentGeneration
            && desiredEpoch != nil
            && desiredEpoch == channelEpoch
    }
}

enum RealtimeRecoveryPolicy {
    static let watchdogInterval: TimeInterval = 5
    static let pathRecoveryDebounce: TimeInterval = 0.35
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
    let throwableID: String?

    init(
        id: UUID,
        roomID: UUID,
        actorUserID: UUID,
        targetUserID: UUID,
        sourceCharacterID: String,
        throwableID: String? = nil
    ) {
        self.id = id
        self.roomID = roomID
        self.actorUserID = actorUserID
        self.targetUserID = targetUserID
        self.sourceCharacterID = sourceCharacterID
        self.throwableID = throwableID
    }
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
