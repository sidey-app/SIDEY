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
    static let starlightUpalupaEntitlementKey = "character:pixel_starlight_upalupa"
    static let guineaPigEntitlementKey = "character:pixel_guinea_pig"
    static let monkeyEntitlementKey = "character:pixel_monkey"
    static let chinchillaEntitlementKey = "character:pixel_chinchilla"
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
