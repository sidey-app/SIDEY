import AppKit

struct PixelBubbleLayout: Equatable, Sendable {
    let size: CGSize
    let localCenterX: CGFloat
    let tailTipX: CGFloat
    let bodyFrame: CGRect
    let totalFrame: CGRect

    static func make(
        text: String,
        isTyping: Bool,
        tangentPosition: CGFloat,
        tangentLength: CGFloat,
        edge: OverlayEdge
    ) -> Self {
        let maximumWidth = min(220, max(24, tangentLength - 16))
        let size: CGSize
        if isTyping {
            size = CGSize(width: min(42, maximumWidth), height: 30)
        } else {
            size = PixelBubbleMeasurementCache.shared.size(
                text: text,
                maximumWidth: maximumWidth
            )
        }

        let halfWidth = size.width / 2
        let worldCenter = min(
            max(tangentPosition, halfWidth + 4),
            max(halfWidth + 4, tangentLength - halfWidth - 4)
        )
        let tangentSign: CGFloat = switch edge {
        case .bottom, .right: 1
        case .top, .left: -1
        }
        let localCenterX = (worldCenter - tangentPosition) * tangentSign
        let tailTipX = -localCenterX
        let bodyFrame = CGRect(
            x: localCenterX - halfWidth,
            y: 52,
            width: size.width,
            height: size.height
        )
        let tailPoint = CGPoint(x: 0, y: 44)
        let total = bodyFrame.union(CGRect(origin: tailPoint, size: CGSize(width: 0.001, height: 0.001)))
        return Self(
            size: size,
            localCenterX: localCenterX,
            tailTipX: tailTipX,
            bodyFrame: bodyFrame,
            totalFrame: total
        )
    }

    func bodyTangentRange(at tangentPosition: CGFloat, edge: OverlayEdge) -> ClosedRange<CGFloat> {
        let tangentSign: CGFloat = switch edge {
        case .bottom, .right: 1
        case .top, .left: -1
        }
        let first = tangentPosition + bodyFrame.minX * tangentSign
        let second = tangentPosition + bodyFrame.maxX * tangentSign
        return min(first, second)...max(first, second)
    }
}

private final class PixelBubbleMeasurementCache: @unchecked Sendable {
    static let shared = PixelBubbleMeasurementCache()

    private let cache = NSCache<NSString, PixelBubbleMeasuredSize>()

    private init() {
        cache.countLimit = 128
    }

    func size(text: String, maximumWidth: CGFloat) -> CGSize {
        let key = "10.5|\(Int((maximumWidth * 10).rounded()))|\(text)" as NSString
        if let cached = cache.object(forKey: key) { return cached.value }

        let font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        paragraph.alignment = .center
        let measured = (text as NSString).boundingRect(
            with: CGSize(width: max(8, maximumWidth - 16), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraph]
        ).integral.size
        let result = CGSize(
            width: min(maximumWidth, max(28, ceil(measured.width) + 16)),
            height: max(28, ceil(measured.height) + 14)
        )
        cache.setObject(PixelBubbleMeasuredSize(result), forKey: key)
        return result
    }
}

private final class PixelBubbleMeasuredSize: NSObject {
    let value: CGSize

    init(_ value: CGSize) {
        self.value = value
    }
}
