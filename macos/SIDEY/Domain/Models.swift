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
    static let poopProductID = "character_poop"
    static let poopEntitlementKey = "character:pixel_poop"
    static let capybaraProductID = "character_capybara"
    static let capybaraEntitlementKey = "character:pixel_capybara"
    static let hedgehogProductID = "character_hedgehog"
    static let hedgehogEntitlementKey = "character:pixel_hedgehog"
    static let unicornProductID = "character_unicorn"
    static let unicornEntitlementKey = "character:pixel_unicorn"
    static let shibaProductID = "character_shiba"
    static let shibaEntitlementKey = "character:pixel_shiba"
    static let salmonSushiProductID = "character_salmon_sushi"
    static let salmonSushiEntitlementKey = "character:pixel_salmon_sushi"
    static let grandpaProductID = "character_grandpa"
    static let grandpaEntitlementKey = "character:pixel_grandpa"
    static let spiderHeroProductID = "character_spider_hero"
    static let spiderHeroEntitlementKey = "character:pixel_spider_hero"
    static let crowProductID = "character_crow"
    static let crowEntitlementKey = "character:pixel_crow"
    static let kimchiProductID = "character_kimchi"
    static let kimchiEntitlementKey = "character:pixel_kimchi"
    static let quokkaProductID = "character_quokka"
    static let quokkaEntitlementKey = "character:pixel_quokka"
    static let redPandaProductID = "character_red_panda"
    static let redPandaEntitlementKey = "character:pixel_red_panda"
    static let otterProductID = "character_otter"
    static let otterEntitlementKey = "character:pixel_otter"
    static let duckProductID = "character_duck"
    static let duckEntitlementKey = "character:pixel_duck"
    static let pandaProductID = "character_panda"
    static let pandaEntitlementKey = "character:pixel_panda"
    static let frogProductID = "character_frog"
    static let frogEntitlementKey = "character:pixel_frog"
    static let octopusProductID = "character_octopus"
    static let octopusEntitlementKey = "character:pixel_octopus"
    static let bungeoppangProductID = "character_bungeoppang"
    static let bungeoppangEntitlementKey = "character:pixel_bungeoppang"
    static let friedEggProductID = "character_fried_egg"
    static let friedEggEntitlementKey = "character:pixel_fried_egg"
    static let samgakGimbapProductID = "character_samgak_gimbap"
    static let samgakGimbapEntitlementKey = "character:pixel_samgak_gimbap"
    static let tteokbokkiProductID = "character_tteokbokki"
    static let tteokbokkiEntitlementKey = "character:pixel_tteokbokki"
    static let avocadoProductID = "character_avocado"
    static let avocadoEntitlementKey = "character:pixel_avocado"
    static let slimeProductID = "character_slime"
    static let slimeEntitlementKey = "character:pixel_slime"
    static let cactusPotProductID = "character_cactus_pot"
    static let cactusPotEntitlementKey = "character:pixel_cactus_pot"
    static let tofuProductID = "character_tofu"
    static let tofuEntitlementKey = "character:pixel_tofu"
    static let cupRamenProductID = "character_cup_ramen"
    static let cupRamenEntitlementKey = "character:pixel_cup_ramen"
    static let grandmaProductID = "character_grandma"
    static let grandmaEntitlementKey = "character:pixel_grandma"
    static let babyProductID = "character_baby"
    static let babyEntitlementKey = "character:pixel_baby"
    static let santaProductID = "character_santa"
    static let santaEntitlementKey = "character:pixel_santa"
    static let jungjiyuProductID = "character_jungjiyu"
    static let jungjiyuEntitlementKey = "character:pixel_jungjiyu"

    /// Product order is a presentation contract. Registering a future product
    /// here is enough for the existing store grid to render it.
    static let products: [CommerceProduct] = [
        .starlightUpalupa,
        .guineaPig,
        .monkey,
        .chinchilla,
        .poop,
        .capybara,
        .hedgehog,
        .unicorn,
        .shiba,
        .salmonSushi,
        .grandpa,
        .spiderHero,
        .crow,
        .kimchi,
        .quokka,
        .redPanda,
        .otter,
        .duck,
        .panda,
        .frog,
        .octopus,
        .bungeoppang,
        .friedEgg,
        .samgakGimbap,
        .tteokbokki,
        .avocado,
        .slime,
        .cactusPot,
        .tofu,
        .cupRamen,
        .grandma,
        .baby,
        .santa,
        .jungjiyu,
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


    static let poop = CommerceProduct(
        id: CommerceCatalog.poopProductID,
        displayName: "똥",
        description: "부드러운 코코아색 소용돌이에 반짝이는 눈이 달린 장난꾸러기 친구예요.",
        characterID: PixelCharacterCatalog.pixelPoopID,
        entitlementKey: CommerceCatalog.poopEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let capybara = CommerceProduct(
        id: CommerceCatalog.capybaraProductID,
        displayName: "아기 카피바라",
        description: "머리에 귤 하나를 얹고 느긋하게 산책하는 세상 편한 친구예요.",
        characterID: PixelCharacterCatalog.pixelCapybaraID,
        entitlementKey: CommerceCatalog.capybaraEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let hedgehog = CommerceProduct(
        id: CommerceCatalog.hedgehogProductID,
        displayName: "아기 고슴도치",
        description: "뾰족한 가시 아래 크림색 얼굴이 숨어 있는 수줍은 친구예요.",
        characterID: PixelCharacterCatalog.pixelHedgehogID,
        entitlementKey: CommerceCatalog.hedgehogEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let unicorn = CommerceProduct(
        id: CommerceCatalog.unicornProductID,
        displayName: "아기 유니콘",
        description: "금빛 뿔과 세 가지 색 갈기를 가진 반짝이는 친구예요.",
        characterID: PixelCharacterCatalog.pixelUnicornID,
        entitlementKey: CommerceCatalog.unicornEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let shiba = CommerceProduct(
        id: CommerceCatalog.shibaProductID,
        displayName: "아기 시바견",
        description: "동그란 눈썹 무늬와 말린 꼬리로 씩씩하게 걷는 친구예요.",
        characterID: PixelCharacterCatalog.pixelShibaID,
        entitlementKey: CommerceCatalog.shibaEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let salmonSushi = CommerceProduct(
        id: CommerceCatalog.salmonSushiProductID,
        displayName: "연어초밥",
        description: "밥 위에 연어 한 점을 얹고 김 띠를 두른 든든한 친구예요.",
        characterID: PixelCharacterCatalog.pixelSalmonSushiID,
        entitlementKey: CommerceCatalog.salmonSushiEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let grandpa = CommerceProduct(
        id: CommerceCatalog.grandpaProductID,
        displayName: "할아버지",
        description: "흰 수염과 동그란 안경, 파란 가디건이 포근한 친구예요.",
        characterID: PixelCharacterCatalog.pixelGrandpaID,
        entitlementKey: CommerceCatalog.grandpaEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let spiderHero = CommerceProduct(
        id: CommerceCatalog.spiderHeroProductID,
        displayName: "거미맨",
        description: "빨간 마스크와 큰 흰 눈, 파란 슈트로 화면 가장자리를 지키는 친구예요.",
        characterID: PixelCharacterCatalog.pixelSpiderHeroID,
        entitlementKey: CommerceCatalog.spiderHeroEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let crow = CommerceProduct(
        id: CommerceCatalog.crowProductID,
        displayName: "아기 까마귀",
        description: "까만 깃털에 노란 부리, 머리 위 작은 깃 두 개가 귀여운 친구예요.",
        characterID: PixelCharacterCatalog.pixelCrowID,
        entitlementKey: CommerceCatalog.crowEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let kimchi = CommerceProduct(
        id: CommerceCatalog.kimchiProductID,
        displayName: "김치",
        description: "새빨간 양념 옷을 입고 초록 배춧잎을 머리에 얹은 매콤한 친구예요.",
        characterID: PixelCharacterCatalog.pixelKimchiID,
        entitlementKey: CommerceCatalog.kimchiEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let quokka = CommerceProduct(
        id: CommerceCatalog.quokkaProductID,
        displayName: "아기 쿼카",
        description: "세상에서 가장 행복한 미소로 화면 가장자리를 밝히는 친구예요.",
        characterID: PixelCharacterCatalog.pixelQuokkaID,
        entitlementKey: CommerceCatalog.quokkaEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let redPanda = CommerceProduct(
        id: CommerceCatalog.redPandaProductID,
        displayName: "아기 레서판다",
        description: "주황 털에 흰 눈썹 무늬, 줄무늬 꼬리를 살랑이는 친구예요.",
        characterID: PixelCharacterCatalog.pixelRedPandaID,
        entitlementKey: CommerceCatalog.redPandaEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let otter = CommerceProduct(
        id: CommerceCatalog.otterProductID,
        displayName: "아기 수달",
        description: "두 손으로 노란 조개를 꼭 안고 다니는 친구예요.",
        characterID: PixelCharacterCatalog.pixelOtterID,
        entitlementKey: CommerceCatalog.otterEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let duck = CommerceProduct(
        id: CommerceCatalog.duckProductID,
        displayName: "아기 오리",
        description: "노란 솜털에 주황 부리, 머리 위 작은 깃이 귀여운 친구예요.",
        characterID: PixelCharacterCatalog.pixelDuckID,
        entitlementKey: CommerceCatalog.duckEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let panda = CommerceProduct(
        id: CommerceCatalog.pandaProductID,
        displayName: "아기 판다",
        description: "까만 귀와 눈 무늬, 대나무색 목도리를 두른 친구예요.",
        characterID: PixelCharacterCatalog.pixelPandaID,
        entitlementKey: CommerceCatalog.pandaEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let frog = CommerceProduct(
        id: CommerceCatalog.frogProductID,
        displayName: "아기 개구리",
        description: "머리 위로 볼록 솟은 눈과 넓은 미소가 사랑스러운 친구예요.",
        characterID: PixelCharacterCatalog.pixelFrogID,
        entitlementKey: CommerceCatalog.frogEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let octopus = CommerceProduct(
        id: CommerceCatalog.octopusProductID,
        displayName: "아기 문어",
        description: "동글동글한 머리 아래 여덟 다리를 꼬물거리는 친구예요.",
        characterID: PixelCharacterCatalog.pixelOctopusID,
        entitlementKey: CommerceCatalog.octopusEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let bungeoppang = CommerceProduct(
        id: CommerceCatalog.bungeoppangProductID,
        displayName: "붕어빵",
        description: "노릇한 격자 무늬와 양쪽 지느러미가 살아 있는 겨울 간식 친구예요.",
        characterID: PixelCharacterCatalog.pixelBungeoppangID,
        entitlementKey: CommerceCatalog.bungeoppangEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let friedEgg = CommerceProduct(
        id: CommerceCatalog.friedEggProductID,
        displayName: "계란후라이",
        description: "하얀 흰자 위에 노른자 얼굴이 톡 올라간 아침 친구예요.",
        characterID: PixelCharacterCatalog.pixelFriedEggID,
        entitlementKey: CommerceCatalog.friedEggEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let samgakGimbap = CommerceProduct(
        id: CommerceCatalog.samgakGimbapProductID,
        displayName: "삼각김밥",
        description: "까만 김에 하얀 밥과 빨간 라벨을 두른 삼각형 친구예요.",
        characterID: PixelCharacterCatalog.pixelSamgakGimbapID,
        entitlementKey: CommerceCatalog.samgakGimbapEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let tteokbokki = CommerceProduct(
        id: CommerceCatalog.tteokbokkiProductID,
        displayName: "떡볶이",
        description: "빨간 양념 위로 떡 세 개가 봉긋 올라온 컵 친구예요.",
        characterID: PixelCharacterCatalog.pixelTteokbokkiID,
        entitlementKey: CommerceCatalog.tteokbokkiEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let avocado = CommerceProduct(
        id: CommerceCatalog.avocadoProductID,
        displayName: "아보카도",
        description: "연둣빛 과육 가운데 갈색 씨앗 얼굴이 웃고 있는 친구예요.",
        characterID: PixelCharacterCatalog.pixelAvocadoID,
        entitlementKey: CommerceCatalog.avocadoEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let slime = CommerceProduct(
        id: CommerceCatalog.slimeProductID,
        displayName: "슬라임",
        description: "반짝이는 물방울 하이라이트를 품은 말랑한 민트 친구예요.",
        characterID: PixelCharacterCatalog.pixelSlimeID,
        entitlementKey: CommerceCatalog.slimeEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let cactusPot = CommerceProduct(
        id: CommerceCatalog.cactusPotProductID,
        displayName: "화분",
        description: "테라코타 화분 위에서 두 팔 벌린 선인장 친구예요.",
        characterID: PixelCharacterCatalog.pixelCactusPotID,
        entitlementKey: CommerceCatalog.cactusPotEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let tofu = CommerceProduct(
        id: CommerceCatalog.tofuProductID,
        displayName: "두부",
        description: "파 조각을 얹은 새하얀 네모 두부 친구예요.",
        characterID: PixelCharacterCatalog.pixelTofuID,
        entitlementKey: CommerceCatalog.tofuEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let cupRamen = CommerceProduct(
        id: CommerceCatalog.cupRamenProductID,
        displayName: "라면",
        description: "김이 모락모락 나는 국물 위에 면과 파를 얹은 야근 친구예요.",
        characterID: PixelCharacterCatalog.pixelCupRamenID,
        entitlementKey: CommerceCatalog.cupRamenEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let grandma = CommerceProduct(
        id: CommerceCatalog.grandmaProductID,
        displayName: "할머니",
        description: "뽀글 파마와 분홍 가디건, 다정한 미소의 친구예요.",
        characterID: PixelCharacterCatalog.pixelGrandmaID,
        entitlementKey: CommerceCatalog.grandmaEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let baby = CommerceProduct(
        id: CommerceCatalog.babyProductID,
        displayName: "아기",
        description: "머리에 곱슬 한 가닥, 쪽쪽이를 문 파란 턱받이 친구예요.",
        characterID: PixelCharacterCatalog.pixelBabyID,
        entitlementKey: CommerceCatalog.babyEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let santa = CommerceProduct(
        id: CommerceCatalog.santaProductID,
        displayName: "산타",
        description: "빨간 모자와 하얀 수염, 검은 벨트를 맨 선물 배달 친구예요.",
        characterID: PixelCharacterCatalog.pixelSantaID,
        entitlementKey: CommerceCatalog.santaEntitlementKey,
        amountKRW: 990,
        currency: "KRW",
        taxInclusive: true
    )

    static let jungjiyu = CommerceProduct(
        id: CommerceCatalog.jungjiyuProductID,
        displayName: "정지유",
        description: "앞머리를 내린 긴 갈색 생머리에 흰 이너와 연핑크 가디건, 청바지를 입은 친구예요.",
        characterID: PixelCharacterCatalog.pixelJungjiyuID,
        entitlementKey: CommerceCatalog.jungjiyuEntitlementKey,
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
