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
        edge: OverlayEdge,
        bodyMinY: CGFloat = 52,
        includesTail: Bool = true,
        leadingDecorationWidth: CGFloat = 0
    ) -> Self {
        let maximumWidth = min(220, max(24, tangentLength - 16))
        let size: CGSize
        if isTyping {
            size = CGSize(width: min(42, maximumWidth), height: 30)
        } else {
            size = PixelBubbleMeasurementCache.shared.size(
                text: text,
                maximumWidth: maximumWidth,
                leadingDecorationWidth: leadingDecorationWidth
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
            y: bodyMinY,
            width: size.width,
            height: size.height
        )
        let total: CGRect
        if includesTail {
            let tailPoint = CGPoint(x: 0, y: 44)
            total = bodyFrame.union(CGRect(origin: tailPoint, size: CGSize(width: 0.001, height: 0.001)))
        } else {
            total = bodyFrame
        }
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

struct PixelBubbleStackEntry: Equatable, Sendable {
    let bubble: ActiveBubble
    let layout: PixelBubbleLayout
    let includesTail: Bool
}

enum PixelBubbleStackLayout {
    static let bodySpacing: CGFloat = 6

    static func make(
        bubbles: [ActiveBubble],
        tangentPosition: CGFloat,
        tangentLength: CGFloat,
        edge: OverlayEdge
    ) -> [PixelBubbleStackEntry] {
        let ordered = bubbles.sorted(by: ActiveBubble.presentationOrder)
        var nextBodyMinY: CGFloat = 52
        var reversedEntries: [PixelBubbleStackEntry] = []

        for bubble in ordered.suffix(ActiveBubbleLedger.maximumVisiblePerSender).reversed() {
            let isLatest = bubble.messageID == ordered.last?.messageID
            let layout = PixelBubbleLayout.make(
                text: bubble.body,
                isTyping: false,
                tangentPosition: tangentPosition,
                tangentLength: tangentLength,
                edge: edge,
                bodyMinY: nextBodyMinY,
                includesTail: isLatest,
                leadingDecorationWidth: PixelBubbleTheme.resolve(bubble.bubbleStyleID)
                    .decorationAssetName == nil ? 0 : PixelBubbleStyle.decorationLeadingWidth
            )
            reversedEntries.append(PixelBubbleStackEntry(
                bubble: bubble,
                layout: layout,
                includesTail: isLatest
            ))
            nextBodyMinY = layout.bodyFrame.maxY + bodySpacing
        }

        return Array(reversedEntries.reversed())
    }

    static func bodyTangentRange(
        for entries: [PixelBubbleStackEntry],
        at tangentPosition: CGFloat,
        edge: OverlayEdge
    ) -> ClosedRange<CGFloat>? {
        let ranges = entries.map { $0.layout.bodyTangentRange(at: tangentPosition, edge: edge) }
        guard let first = ranges.first else { return nil }
        return ranges.dropFirst().reduce(first) { partial, range in
            min(partial.lowerBound, range.lowerBound)...max(partial.upperBound, range.upperBound)
        }
    }
}

private extension ActiveBubble {
    static func presentationOrder(_ lhs: ActiveBubble, _ rhs: ActiveBubble) -> Bool {
        lhs.expiresAt == rhs.expiresAt
            ? lhs.messageID.uuidString < rhs.messageID.uuidString
            : lhs.expiresAt < rhs.expiresAt
    }
}

private final class PixelBubbleMeasurementCache: @unchecked Sendable {
    static let shared = PixelBubbleMeasurementCache()

    private let cache = NSCache<NSString, PixelBubbleMeasuredSize>()

    private init() {
        cache.countLimit = 128
    }

    func size(
        text: String,
        maximumWidth: CGFloat,
        leadingDecorationWidth: CGFloat
    ) -> CGSize {
        let key = [
            "10.5",
            String(Int((maximumWidth * 10).rounded())),
            String(Int(leadingDecorationWidth)),
            text
        ].joined(separator: "|") as NSString
        if let cached = cache.object(forKey: key) { return cached.value }

        let font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        paragraph.alignment = .center
        let measured = (text as NSString).boundingRect(
            with: CGSize(
                width: max(8, maximumWidth - 16 - leadingDecorationWidth),
                height: .greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraph]
        ).integral.size
        let result = CGSize(
            width: min(
                maximumWidth,
                max(28 + leadingDecorationWidth, ceil(measured.width) + 16 + leadingDecorationWidth)
            ),
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
