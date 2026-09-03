import CoreGraphics
import Foundation

struct PixelCharacterFrameContract: Equatable, Sendable {
    let idle: Range<Int>
    let walk: Range<Int>
    let doze: Range<Int>
    let offline: Range<Int>

    static let standard = PixelCharacterFrameContract(
        idle: 0..<2,
        walk: 2..<6,
        doze: 6..<8,
        offline: 8..<10
    )
}

/// How long the overlay holds each idle frame. `breathing` see-saws between the two idle
/// frames at an even pace; `blinking` holds the open-eyed frame and flashes the closed-eyed
/// one, which needs a sheet whose second idle frame closes the eyes.
struct PixelCharacterIdleTiming: Equatable, Sendable {
    let restDuration: TimeInterval
    let accentDuration: TimeInterval

    static let breathing = PixelCharacterIdleTiming(restDuration: 0.55, accentDuration: 0.55)
    static let blinking = PixelCharacterIdleTiming(restDuration: 2.4, accentDuration: 0.3)

    /// Per-frame hold times in sheet order: the first idle frame rests, the others accent.
    func frameDurations(frameCount: Int) -> [TimeInterval] {
        guard frameCount > 0 else { return [] }
        return (0..<frameCount).map { $0 == 0 ? restDuration : accentDuration }
    }
}

struct PixelCharacterDefinition: Equatable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let resourceName: String
    let resourceDirectory: String
    let previewFrame: Int
    let frames: PixelCharacterFrameContract
    let paletteDescription: String
    let entitlementKey: String?
    let mirrorsToMovementDirection: Bool
    let sparkleEffect: PixelSparkleEffect?
    /// Defaults to even breathing; characters whose second idle frame closes the eyes
    /// pass `.blinking` so the overlay holds the open frame and flashes the blink.
    var idleTiming: PixelCharacterIdleTiming = .breathing

    func assetURL(bundle: Bundle = .main) -> URL? {
        bundle.url(
            forResource: resourceName,
            withExtension: "png",
            subdirectory: resourceDirectory
        ) ?? bundle.url(forResource: resourceName, withExtension: "png")
    }
}

struct PixelSparkleColor: Equatable, Sendable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: 1)
    }
}

struct PixelSparkleEffect: Equatable, Sendable {
    let ambientDelay: ClosedRange<TimeInterval>
    let ambientDuration: TimeInterval
    let ambientCount: ClosedRange<Int>
    let ambientRadius: ClosedRange<CGFloat>
    let ambientHorizontalPosition: ClosedRange<CGFloat>
    let ambientVerticalPosition: ClosedRange<CGFloat>
    let ambientRise: CGFloat
    let centralFlashDuration: TimeInterval
    let centralFlashRadius: CGFloat
    let pulseWaves: [PixelSparklePulseWave]
    let colors: [PixelSparkleColor]

    var pulseDuration: TimeInterval {
        pulseWaves.map { $0.delay + $0.duration }.max() ?? centralFlashDuration
    }

    var pulseCount: Int {
        pulseWaves.reduce(0) { $0 + $1.count }
    }

    static let starlight = PixelSparkleEffect(
        ambientDelay: 1.0...1.4,
        ambientDuration: 1.05,
        ambientCount: 4...6,
        ambientRadius: 2.6...4.0,
        ambientHorizontalPosition: -25...25,
        ambientVerticalPosition: 5...37,
        ambientRise: 4,
        centralFlashDuration: 0.32,
        centralFlashRadius: 34,
        pulseWaves: [
            PixelSparklePulseWave(
                delay: 0,
                duration: 0.72,
                count: 18,
                distance: 126...168,
                radius: 8...13
            ),
            PixelSparklePulseWave(
                delay: 0.06,
                duration: 0.78,
                count: 24,
                distance: 82...132,
                radius: 4.5...8
            )
        ],
        colors: [
            PixelSparkleColor(red: 0.47, green: 0.76, blue: 0.68),
            PixelSparkleColor(red: 0.66, green: 0.53, blue: 0.84),
            PixelSparkleColor(red: 0.96, green: 0.73, blue: 0.22)
        ]
    )
}

struct PixelSparklePulseWave: Equatable, Sendable {
    let delay: TimeInterval
    let duration: TimeInterval
    let count: Int
    let distance: ClosedRange<CGFloat>
    let radius: ClosedRange<CGFloat>
}

enum PixelCharacterCatalog {
    static let pixelHamsterID = "pixel_hamster"
    static let pixelGuineaPigID = "pixel_guinea_pig"
    static let pixelMonkeyID = "pixel_monkey"
    static let pixelChinchillaID = "pixel_chinchilla"
    static let pixelStarlightUpalupaID = "pixel_starlight_upalupa"
    static let pixelPoopID = "pixel_poop"
    static let pixelCapybaraID = "pixel_capybara"
    static let pixelHedgehogID = "pixel_hedgehog"
    static let pixelUnicornID = "pixel_unicorn"
    static let pixelShibaID = "pixel_shiba"
    static let pixelSalmonSushiID = "pixel_salmon_sushi"
    static let pixelGrandpaID = "pixel_grandpa"
    static let pixelSpiderHeroID = "pixel_spider_hero"
    static let pixelCrowID = "pixel_crow"
    static let pixelKimchiID = "pixel_kimchi"
    static let pixelQuokkaID = "pixel_quokka"
    static let pixelRedPandaID = "pixel_red_panda"
    static let pixelOtterID = "pixel_otter"
    static let pixelDuckID = "pixel_duck"
    static let pixelPandaID = "pixel_panda"
    static let pixelFrogID = "pixel_frog"
    static let pixelOctopusID = "pixel_octopus"
    static let pixelBungeoppangID = "pixel_bungeoppang"
    static let pixelFriedEggID = "pixel_fried_egg"
    static let pixelSamgakGimbapID = "pixel_samgak_gimbap"
    static let pixelTteokbokkiID = "pixel_tteokbokki"
    static let pixelAvocadoID = "pixel_avocado"
    static let pixelSlimeID = "pixel_slime"
    static let pixelCactusPotID = "pixel_cactus_pot"
    static let pixelTofuID = "pixel_tofu"
    static let pixelCupRamenID = "pixel_cup_ramen"
    static let pixelGrandmaID = "pixel_grandma"
    static let pixelBabyID = "pixel_baby"
    static let pixelSantaID = "pixel_santa"
    static let pixelJungjiyuID = "pixel_jungjiyu"
    static let starlightUpalupaEntitlementKey = "character:pixel_starlight_upalupa"
    static let guineaPigEntitlementKey = "character:pixel_guinea_pig"
    static let monkeyEntitlementKey = "character:pixel_monkey"
    static let chinchillaEntitlementKey = "character:pixel_chinchilla"
    static let poopEntitlementKey = "character:pixel_poop"
    static let capybaraEntitlementKey = "character:pixel_capybara"
    static let hedgehogEntitlementKey = "character:pixel_hedgehog"
    static let unicornEntitlementKey = "character:pixel_unicorn"
    static let shibaEntitlementKey = "character:pixel_shiba"
    static let salmonSushiEntitlementKey = "character:pixel_salmon_sushi"
    static let grandpaEntitlementKey = "character:pixel_grandpa"
    static let spiderHeroEntitlementKey = "character:pixel_spider_hero"
    static let crowEntitlementKey = "character:pixel_crow"
    static let kimchiEntitlementKey = "character:pixel_kimchi"
    static let quokkaEntitlementKey = "character:pixel_quokka"
    static let redPandaEntitlementKey = "character:pixel_red_panda"
    static let otterEntitlementKey = "character:pixel_otter"
    static let duckEntitlementKey = "character:pixel_duck"
    static let pandaEntitlementKey = "character:pixel_panda"
    static let frogEntitlementKey = "character:pixel_frog"
    static let octopusEntitlementKey = "character:pixel_octopus"
    static let bungeoppangEntitlementKey = "character:pixel_bungeoppang"
    static let friedEggEntitlementKey = "character:pixel_fried_egg"
    static let samgakGimbapEntitlementKey = "character:pixel_samgak_gimbap"
    static let tteokbokkiEntitlementKey = "character:pixel_tteokbokki"
    static let avocadoEntitlementKey = "character:pixel_avocado"
    static let slimeEntitlementKey = "character:pixel_slime"
    static let cactusPotEntitlementKey = "character:pixel_cactus_pot"
    static let tofuEntitlementKey = "character:pixel_tofu"
    static let cupRamenEntitlementKey = "character:pixel_cup_ramen"
    static let grandmaEntitlementKey = "character:pixel_grandma"
    static let babyEntitlementKey = "character:pixel_baby"
    static let santaEntitlementKey = "character:pixel_santa"
    static let jungjiyuEntitlementKey = "character:pixel_jungjiyu"
    static let legacyMintyPupID = "minty_pup"
    static let legacyPixelKoalaID = "pixel_koala"

    static let all: [PixelCharacterDefinition] = [
        PixelCharacterDefinition(
            id: pixelHamsterID,
            displayName: "아기 햄스터",
            resourceName: "pixel_hamster",
            resourceDirectory: "Characters/PixelHamster",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "골든 · 크림 · 페리윙클",
            entitlementKey: nil,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil
        ),
        PixelCharacterDefinition(
            id: "pixel_cat",
            displayName: "아기 고양이",
            resourceName: "pixel_cat",
            resourceDirectory: "Characters/PixelCat",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "스모크 그레이 · 크림 · 라일락",
            entitlementKey: nil,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil
        ),
        PixelCharacterDefinition(
            id: "pixel_puppy",
            displayName: "아기 강아지",
            resourceName: "pixel_puppy",
            resourceDirectory: "Characters/PixelPuppy",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "캐러멜 · 크림 · 스카이 블루",
            entitlementKey: nil,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil
        ),
        PixelCharacterDefinition(
            id: "pixel_rabbit",
            displayName: "아기 토끼",
            resourceName: "pixel_rabbit",
            resourceDirectory: "Characters/PixelRabbit",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "아이보리 · 피치 · 라벤더",
            entitlementKey: nil,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil
        ),
        PixelCharacterDefinition(
            id: "pixel_penguin",
            displayName: "아기 펭귄",
            resourceName: "pixel_penguin",
            resourceDirectory: "Characters/PixelPenguin",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "네이비 · 크림 · 민트",
            entitlementKey: nil,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil
        ),
        PixelCharacterDefinition(
            id: pixelGuineaPigID,
            displayName: "아기 기니피그",
            resourceName: "pixel_guinea_pig",
            resourceDirectory: "Characters/PixelGuineaPig",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "브라운 · 캐러멜 · 크림",
            entitlementKey: guineaPigEntitlementKey,
            mirrorsToMovementDirection: true,
            sparkleEffect: nil
        ),
        PixelCharacterDefinition(
            id: pixelMonkeyID,
            displayName: "아기 원숭이",
            resourceName: "pixel_monkey",
            resourceDirectory: "Characters/PixelMonkey",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "웜 브라운 · 피치 · 시안",
            entitlementKey: monkeyEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil
        ),
        PixelCharacterDefinition(
            id: pixelChinchillaID,
            displayName: "아기 친칠라",
            resourceName: "pixel_chinchilla",
            resourceDirectory: "Characters/PixelChinchilla",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "쿨 그레이 · 크림 · 스카이 블루",
            entitlementKey: chinchillaEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil
        ),
        PixelCharacterDefinition(
            id: pixelStarlightUpalupaID,
            displayName: "별빛 우파루파",
            resourceName: "pixel_starlight_upalupa",
            resourceDirectory: "Characters/PixelStarlightUpalupa",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "진주빛 핑크 · 라벤더 · 민트",
            entitlementKey: starlightUpalupaEntitlementKey,
            mirrorsToMovementDirection: true,
            sparkleEffect: .starlight
        ),
        PixelCharacterDefinition(
            id: pixelPoopID,
            displayName: "똥",
            resourceName: "pixel_poop",
            resourceDirectory: "Characters/PixelPoop",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "코코아 브라운 · 모카 · 코랄 볼",
            entitlementKey: poopEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelCapybaraID,
            displayName: "아기 카피바라",
            resourceName: "pixel_capybara",
            resourceDirectory: "Characters/PixelCapybara",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "탠 브라운 · 크림 · 세이지 그린",
            entitlementKey: capybaraEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelHedgehogID,
            displayName: "아기 고슴도치",
            resourceName: "pixel_hedgehog",
            resourceDirectory: "Characters/PixelHedgehog",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "체스트넛 · 크림 · 코랄",
            entitlementKey: hedgehogEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelUnicornID,
            displayName: "아기 유니콘",
            resourceName: "pixel_unicorn",
            resourceDirectory: "Characters/PixelUnicorn",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "펄 화이트 · 라벤더 · 핑크",
            entitlementKey: unicornEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelShibaID,
            displayName: "아기 시바견",
            resourceName: "pixel_shiba",
            resourceDirectory: "Characters/PixelShiba",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "세서미 오렌지 · 크림 · 레드",
            entitlementKey: shibaEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelSalmonSushiID,
            displayName: "연어초밥",
            resourceName: "pixel_salmon_sushi",
            resourceDirectory: "Characters/PixelSalmonSushi",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "밥알 화이트 · 연어 오렌지 · 김 그린",
            entitlementKey: salmonSushiEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelGrandpaID,
            displayName: "할아버지",
            resourceName: "pixel_grandpa",
            resourceDirectory: "Characters/PixelGrandpa",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "피치 스킨 · 실버 · 네이비 가디건",
            entitlementKey: grandpaEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelSpiderHeroID,
            displayName: "거미맨",
            resourceName: "pixel_spider_hero",
            resourceDirectory: "Characters/PixelSpiderHero",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "히어로 레드 · 화이트 · 로열 블루",
            entitlementKey: spiderHeroEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelCrowID,
            displayName: "아기 까마귀",
            resourceName: "pixel_crow",
            resourceDirectory: "Characters/PixelCrow",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "잉크 블랙 · 슬레이트 · 골든 옐로",
            entitlementKey: crowEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelKimchiID,
            displayName: "김치",
            resourceName: "pixel_kimchi",
            resourceDirectory: "Characters/PixelKimchi",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "고춧가루 레드 · 배추 아이보리 · 잎 그린",
            entitlementKey: kimchiEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelQuokkaID,
            displayName: "아기 쿼카",
            resourceName: "pixel_quokka",
            resourceDirectory: "Characters/PixelQuokka",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "모카 브라운 · 크림 · 스카이 블루",
            entitlementKey: quokkaEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelRedPandaID,
            displayName: "아기 레서판다",
            resourceName: "pixel_red_panda",
            resourceDirectory: "Characters/PixelRedPanda",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "러스트 오렌지 · 크림 · 스카이 블루",
            entitlementKey: redPandaEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelOtterID,
            displayName: "아기 수달",
            resourceName: "pixel_otter",
            resourceDirectory: "Characters/PixelOtter",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "월넛 브라운 · 크림 · 세이지 그린",
            entitlementKey: otterEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelDuckID,
            displayName: "아기 오리",
            resourceName: "pixel_duck",
            resourceDirectory: "Characters/PixelDuck",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "레몬 옐로 · 크림 · 스카이 블루",
            entitlementKey: duckEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelPandaID,
            displayName: "아기 판다",
            resourceName: "pixel_panda",
            resourceDirectory: "Characters/PixelPanda",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "화이트 · 차콜 · 뱀부 그린",
            entitlementKey: pandaEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelFrogID,
            displayName: "아기 개구리",
            resourceName: "pixel_frog",
            resourceDirectory: "Characters/PixelFrog",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "리프 그린 · 페일 옐로 · 골든",
            entitlementKey: frogEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelOctopusID,
            displayName: "아기 문어",
            resourceName: "pixel_octopus",
            resourceDirectory: "Characters/PixelOctopus",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "코랄 핑크 · 로즈 · 스카이 블루",
            entitlementKey: octopusEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelBungeoppangID,
            displayName: "붕어빵",
            resourceName: "pixel_bungeoppang",
            resourceDirectory: "Characters/PixelBungeoppang",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "골든 브라운 · 버터 크림 · 코랄 볼",
            entitlementKey: bungeoppangEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelFriedEggID,
            displayName: "계란후라이",
            resourceName: "pixel_fried_egg",
            resourceDirectory: "Characters/PixelFriedEgg",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "에그 화이트 · 요크 옐로 · 버터",
            entitlementKey: friedEggEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelSamgakGimbapID,
            displayName: "삼각김밥",
            resourceName: "pixel_samgak_gimbap",
            resourceDirectory: "Characters/PixelSamgakGimbap",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "김 그린 · 밥알 화이트 · 라벨 레드",
            entitlementKey: samgakGimbapEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelTteokbokkiID,
            displayName: "떡볶이",
            resourceName: "pixel_tteokbokki",
            resourceDirectory: "Characters/PixelTteokbokki",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "고추장 레드 · 떡 아이보리 · 파 그린",
            entitlementKey: tteokbokkiEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelAvocadoID,
            displayName: "아보카도",
            resourceName: "pixel_avocado",
            resourceDirectory: "Characters/PixelAvocado",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "아보카도 그린 · 페일 라임 · 씨앗 브라운",
            entitlementKey: avocadoEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelSlimeID,
            displayName: "슬라임",
            resourceName: "pixel_slime",
            resourceDirectory: "Characters/PixelSlime",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "민트 틸 · 아쿠아 · 골든",
            entitlementKey: slimeEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelCactusPotID,
            displayName: "화분",
            resourceName: "pixel_cactus_pot",
            resourceDirectory: "Characters/PixelCactusPot",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "선인장 그린 · 테라코타 · 핑크 꽃",
            entitlementKey: cactusPotEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelTofuID,
            displayName: "두부",
            resourceName: "pixel_tofu",
            resourceDirectory: "Characters/PixelTofu",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "두부 화이트 · 소프트 그레이 · 파 그린",
            entitlementKey: tofuEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelCupRamenID,
            displayName: "라면",
            resourceName: "pixel_cup_ramen",
            resourceDirectory: "Characters/PixelCupRamen",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "컵 화이트 · 국물 오렌지 · 레드 라벨",
            entitlementKey: cupRamenEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelGrandmaID,
            displayName: "할머니",
            resourceName: "pixel_grandma",
            resourceDirectory: "Characters/PixelGrandma",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "피치 스킨 · 실버 펌 · 핑크 가디건",
            entitlementKey: grandmaEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelBabyID,
            displayName: "아기",
            resourceName: "pixel_baby",
            resourceDirectory: "Characters/PixelBaby",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "피치 스킨 · 화이트 · 베이비 블루",
            entitlementKey: babyEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelSantaID,
            displayName: "산타",
            resourceName: "pixel_santa",
            resourceDirectory: "Characters/PixelSanta",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "산타 레드 · 스노 화이트 · 피치 스킨",
            entitlementKey: santaEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        ),
        PixelCharacterDefinition(
            id: pixelJungjiyuID,
            displayName: "정지유",
            resourceName: "pixel_jungjiyu",
            resourceDirectory: "Characters/PixelJungjiyu",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "브라운 헤어 · 연핑크 가디건 · 연청 데님",
            entitlementKey: jungjiyuEntitlementKey,
            mirrorsToMovementDirection: false,
            sparkleEffect: nil,
            idleTiming: .blinking
        )
    ]

    static let free = all.filter { $0.entitlementKey == nil }

    static let frameCount = 10
    static let framePixelSize = CGSize(width: 24, height: 24)
    static let sheetPixelSize = CGSize(width: 240, height: 24)
    static let footBaselinePixel = 3

    static func canonicalID(for storedID: String) -> String {
        let candidate = switch storedID {
        case legacyMintyPupID: pixelHamsterID
        case legacyPixelKoalaID: pixelChinchillaID
        default: storedID
        }
        return all.contains(where: { $0.id == candidate }) ? candidate : pixelHamsterID
    }

    static func definition(for storedID: String) -> PixelCharacterDefinition {
        let canonical = canonicalID(for: storedID)
        return all.first(where: { $0.id == canonical }) ?? all[0]
    }

    static func selectableDefinitions(entitlementKeys: Set<String>) -> [PixelCharacterDefinition] {
        all.filter { definition in
            guard let entitlementKey = definition.entitlementKey else { return true }
            return entitlementKeys.contains(entitlementKey)
        }
    }

    static func canSelect(_ characterID: String, entitlementKeys: Set<String>) -> Bool {
        let definition = definition(for: characterID)
        guard let entitlementKey = definition.entitlementKey else { return true }
        return entitlementKeys.contains(entitlementKey)
    }
}

enum PixelCharacterAsset {
    static let frameCount = PixelCharacterCatalog.frameCount
    static let framePixelSize = PixelCharacterCatalog.framePixelSize

    static func url(for characterID: String, bundle: Bundle = .main) -> URL? {
        PixelCharacterCatalog.definition(for: characterID).assetURL(bundle: bundle)
    }
}

/// Compatibility surface for existing callers and old asset tests.
enum PixelHamsterAsset {
    static let frameCount = PixelCharacterAsset.frameCount
    static let framePixelSize = PixelCharacterAsset.framePixelSize

    static func url(bundle: Bundle = .main) -> URL? {
        PixelCharacterAsset.url(for: PixelCharacterCatalog.pixelHamsterID, bundle: bundle)
    }
}
