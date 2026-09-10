#if !APP_STORE
import AppKit
import SpriteKit

/// Approved V2 pixel geometry, in the same local coordinates as the 48pt body.
@MainActor
final class PixelCharacterStunEffect: SKNode {
    private static let starTexture = texture(named: "character-stun-star")
    private static let ringTexture = texture(named: "character-stun-ring")
    private let stars: [SKSpriteNode]

    override init() {
        stars = (0..<3).map { _ in SKSpriteNode(texture: Self.starTexture, size: CGSize(width: 14, height: 14)) }
        super.init()
        // Texture rects use a bottom-left origin. Split the ring to pass behind the body.
        for (rect, position, depth) in [
            (CGRect(x: 0, y: 6.0/11, width: 1, height: 5.0/11), CGPoint(x: 1, y: 21), CGFloat(-1)),
            (CGRect(x: 0, y: 0, width: 1, height: 6.0/11), CGPoint(x: 1, y: 10), CGFloat(1))
        ] {
            let texture = SKTexture(rect: rect, in: Self.ringTexture)
            texture.filteringMode = .nearest
            let ring = SKSpriteNode(texture: texture, size: CGSize(width: 46, height: rect.height * 22))
            ring.position = position
            ring.zPosition = depth
            addChild(ring)
        }
        stars.forEach { addChild($0) }
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(elapsed: TimeInterval, reduceMotion: Bool) {
        for (index, star) in stars.enumerated() {
            let angle = (reduceMotion ? 0 : elapsed) / 1.2 * 2 * Double.pi + Double(index) * 2 * Double.pi / 3
            let depth = sin(angle)
            let x = round(32 + 11 * cos(angle) - 3.5)
            let y = round(19 + 5 * depth - 3.5)
            star.position = CGPoint(x: (x + 3.5 - 32) * 2, y: (y + 3.5 - 12) * 2)
            star.zPosition = y + 3.5 >= 19 ? -0.5 : 1.5
        }
    }

    private static func texture(named name: String) -> SKTexture {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else { preconditionFailure("Missing direct-distribution stun asset: \(name)") }
        let result = SKTexture(image: image)
        result.filteringMode = .nearest
        return result
    }
}
#endif
