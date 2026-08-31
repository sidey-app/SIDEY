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

    func assetURL(bundle: Bundle = .main) -> URL? {
        bundle.url(
            forResource: resourceName,
            withExtension: "png",
            subdirectory: resourceDirectory
        ) ?? bundle.url(forResource: resourceName, withExtension: "png")
    }
}

enum PixelCharacterCatalog {
    static let pixelHamsterID = "pixel_hamster"
    static let legacyMintyPupID = "minty_pup"

    static let all: [PixelCharacterDefinition] = [
        PixelCharacterDefinition(
            id: pixelHamsterID,
            displayName: "아기 햄스터",
            resourceName: "pixel_hamster",
            resourceDirectory: "Characters/PixelHamster",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "골든 · 크림 · 페리윙클"
        ),
        PixelCharacterDefinition(
            id: "pixel_cat",
            displayName: "아기 고양이",
            resourceName: "pixel_cat",
            resourceDirectory: "Characters/PixelCat",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "스모크 그레이 · 크림 · 라일락"
        ),
        PixelCharacterDefinition(
            id: "pixel_puppy",
            displayName: "아기 강아지",
            resourceName: "pixel_puppy",
            resourceDirectory: "Characters/PixelPuppy",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "캐러멜 · 크림 · 스카이 블루"
        ),
        PixelCharacterDefinition(
            id: "pixel_rabbit",
            displayName: "아기 토끼",
            resourceName: "pixel_rabbit",
            resourceDirectory: "Characters/PixelRabbit",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "아이보리 · 피치 · 라벤더"
        ),
        PixelCharacterDefinition(
            id: "pixel_penguin",
            displayName: "아기 펭귄",
            resourceName: "pixel_penguin",
            resourceDirectory: "Characters/PixelPenguin",
            previewFrame: 0,
            frames: .standard,
            paletteDescription: "네이비 · 크림 · 민트"
        )
    ]

    static let frameCount = 10
    static let framePixelSize = CGSize(width: 24, height: 24)
    static let sheetPixelSize = CGSize(width: 240, height: 24)
    static let footBaselinePixel = 3

    static func canonicalID(for storedID: String) -> String {
        let candidate = storedID == legacyMintyPupID ? pixelHamsterID : storedID
        return all.contains(where: { $0.id == candidate }) ? candidate : pixelHamsterID
    }

    static func definition(for storedID: String) -> PixelCharacterDefinition {
        let canonical = canonicalID(for: storedID)
        return all.first(where: { $0.id == canonical }) ?? all[0]
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
