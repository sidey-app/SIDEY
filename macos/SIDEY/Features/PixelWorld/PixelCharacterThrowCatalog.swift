import AppKit
import SpriteKit

enum PixelCharacterThrowCatalog {
    static let fallbackCharacterID = PixelCharacterCatalog.pixelHamsterID
    static let fallbackObjectID = "patch_soft_ball"
    static let actionFrameCount = 8
    static let objectFrameCount = 12
    static let throwFrames = 0..<4
    static let hitFrames = 4..<8
    static let rotationFrames = 0..<8
    static let impactFrames = 8..<12

    static let paidObjectID = "heart_cushion"

    static func objectID(for characterID: String) -> String {
        let id = PixelCharacterCatalog.canonicalID(for: characterID)
        return switch id {
        case PixelCharacterCatalog.pixelGuineaPigID: "mini_paprika"
        case PixelCharacterCatalog.pixelMonkeyID: "banana"
        case PixelCharacterCatalog.pixelChinchillaID: "dust_bath_pouch"
        case PixelCharacterCatalog.pixelStarlightUpalupaID: "starlight_orb"
        // The asset licence keeps paid characters off the free patch ball, so every
        // other paid character throws the licensed cushion.
        // 정지유 carries the licensed cup; every other paid character throws the cushion.
        case PixelCharacterCatalog.pixelJungjiyuID: "ice_americano"
        default: PixelCharacterCatalog.definition(for: id).entitlementKey == nil
            ? fallbackObjectID
            : paidObjectID
        }
    }

    static func actionAssetURL(for characterID: String, bundle: Bundle = .main) -> URL? {
        let id = PixelCharacterCatalog.canonicalID(for: characterID)
        let name = "\(id)_throw_hit"
        return bundle.url(forResource: name, withExtension: "png", subdirectory: "CharacterThrow/ActionSheets")
            ?? bundle.url(forResource: name, withExtension: "png")
    }

    static func objectAssetURL(for objectID: String, bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: objectID, withExtension: "png", subdirectory: "CharacterThrow/ObjectSheets")
            ?? bundle.url(forResource: objectID, withExtension: "png")
    }
}

struct PixelCharacterThrowTextures {
    let throwFrames: [SKTexture]
    let hitFrames: [SKTexture]
    let rotationFrames: [SKTexture]
    let impactFrames: [SKTexture]
}

@MainActor
final class PixelCharacterThrowTextureStore {
    static let shared = PixelCharacterThrowTextureStore()
    private var cache: [String: PixelCharacterThrowTextures] = [:]

    func textures(for sourceCharacterID: String, bundle: Bundle = .main) -> PixelCharacterThrowTextures {
        let characterID = PixelCharacterCatalog.canonicalID(for: sourceCharacterID)
        if let cached = cache[characterID] { return cached }
        let actions = frames(
            url: PixelCharacterThrowCatalog.actionAssetURL(for: characterID, bundle: bundle),
            count: PixelCharacterThrowCatalog.actionFrameCount,
            cellSize: CGSize(width: 24, height: 24),
            fallbackColor: .systemOrange
        )
        let objectID = PixelCharacterThrowCatalog.objectID(for: characterID)
        let objects = frames(
            url: PixelCharacterThrowCatalog.objectAssetURL(for: objectID, bundle: bundle),
            count: PixelCharacterThrowCatalog.objectFrameCount,
            cellSize: CGSize(width: 16, height: 16),
            fallbackColor: .systemTeal
        )
        let result = PixelCharacterThrowTextures(
            throwFrames: Array(actions[PixelCharacterThrowCatalog.throwFrames]),
            hitFrames: Array(actions[PixelCharacterThrowCatalog.hitFrames]),
            rotationFrames: Array(objects[PixelCharacterThrowCatalog.rotationFrames]),
            impactFrames: Array(objects[PixelCharacterThrowCatalog.impactFrames])
        )
        cache[characterID] = result
        return result
    }

    private func frames(
        url: URL?,
        count: Int,
        cellSize: CGSize,
        fallbackColor: NSColor
    ) -> [SKTexture] {
        let image: NSImage
        if let url, let loaded = NSImage(contentsOf: url) {
            image = loaded
        } else {
            image = NSImage(size: CGSize(width: cellSize.width * CGFloat(count), height: cellSize.height))
            image.lockFocus()
            fallbackColor.setFill()
            for index in 0..<count {
                NSBezierPath(ovalIn: CGRect(
                    x: CGFloat(index) * cellSize.width + 3,
                    y: 3,
                    width: cellSize.width - 6,
                    height: cellSize.height - 6
                )).fill()
            }
            image.unlockFocus()
        }
        let sheet = SKTexture(image: image)
        sheet.filteringMode = .nearest
        return (0..<count).map { index in
            let texture = SKTexture(
                rect: CGRect(
                    x: CGFloat(index) / CGFloat(count),
                    y: 0,
                    width: 1 / CGFloat(count),
                    height: 1
                ),
                in: sheet
            )
            texture.filteringMode = .nearest
            return texture
        }
    }
}

enum PixelCharacterThrowStyle {
    static let throwDuration: TimeInterval = 0.4
    static let releaseDelay: TimeInterval = 0.2
    static let hitDuration: TimeInterval = 0.44
    static let impactDuration: TimeInterval = 0.24
    static let impactPointSize: CGFloat = 48
    static let rotationFrameInterval: TimeInterval = 0.083
    static let maximumActiveProjectiles = 32

    static func arcHeight(for distance: CGFloat) -> CGFloat {
        min(96, max(24, distance * 0.18))
    }

    static func flightDuration(for distance: CGFloat) -> TimeInterval {
        min(0.95, max(0.35, 0.35 + TimeInterval(distance / 1_600)))
    }
}
