import AppKit

struct OverlayScreenGeometry: Equatable {
    let identifier: String
    let legacySignature: String
    let visibleFrame: CGRect
}

enum OverlayPlacement {
    static func target(
        for frame: CGRect,
        screens: [OverlayScreenGeometry],
        preferredIdentifier: String? = nil
    ) -> OverlayScreenGeometry? {
        guard !screens.isEmpty else { return nil }
        if let preferredIdentifier,
           let preferred = screens.first(where: {
               $0.identifier == preferredIdentifier || $0.legacySignature == preferredIdentifier
           }) {
            return preferred
        }

        let intersections = screens.map { screen in
            (screen, intersectionArea(frame, screen.visibleFrame))
        }
        if let largest = intersections.max(by: { $0.1 < $1.1 }), largest.1 > 0 {
            return largest.0
        }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        return screens.min { lhs, rhs in
            squaredDistance(from: center, to: lhs.visibleFrame)
                < squaredDistance(from: center, to: rhs.visibleFrame)
        }
    }

    static func clamped(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        let x = min(
            max(frame.minX, visibleFrame.minX),
            max(visibleFrame.minX, visibleFrame.maxX - frame.width)
        )
        let y = min(
            max(frame.minY, visibleFrame.minY),
            max(visibleFrame.minY, visibleFrame.maxY - frame.height)
        )
        return CGRect(origin: CGPoint(x: x, y: y), size: frame.size)
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return max(0, intersection.width) * max(0, intersection.height)
    }

    private static func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(max(rect.minX - point.x, 0), point.x - rect.maxX)
        let dy = max(max(rect.minY - point.y, 0), point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}

@MainActor
final class OverlayWindowGroup {
    static let defaultSize = CGSize(width: 720, height: 360)

    private let avatarWindow: AvatarOverlayWindowController
    private let model: AppModel
    private var interactionWindow: OverlayInteractionWindowController!
    private var historyWindow: OverlayHistoryWindowController!
    private(set) var currentFrame: CGRect
    private var overlayVisible = false
    private var historyRequested = false
    private var currentMode: OverlayMode
    private var interactiveMoveStartFrame: CGRect?
    private let onMoveEnded: () -> Void
    private let onHistoryOpened: () -> Void

    init(
        model: AppModel,
        onSend: @escaping (String) -> Void = { _ in },
        onTypingChanged: @escaping (Bool) -> Void = { _ in },
        onOpenSettings: @escaping () -> Void,
        onOverlayModeChanged: @escaping (OverlayMode) -> Void = { _ in },
        onScaleChanged: @escaping (Double) -> Void = { _ in },
        onMoveEnded: @escaping () -> Void = {},
        onHistoryOpened: @escaping () -> Void = {}
    ) {
        let initialFrame = CGRect(origin: .zero, size: Self.defaultSize)
        currentFrame = initialFrame
        self.model = model
        currentMode = model.overlayMode
        self.onMoveEnded = onMoveEnded
        self.onHistoryOpened = onHistoryOpened
        avatarWindow = AvatarOverlayWindowController(model: model, frame: initialFrame)
        historyWindow = OverlayHistoryWindowController(
            model: model,
            onClose: { [weak self] in self?.setHistoryVisible(false) }
        )
        interactionWindow = OverlayInteractionWindowController(
            model: model,
            onMoveBegan: { [weak self] in self?.beginInteractiveMove() },
            onDrag: { [weak self] translation in self?.updateInteractiveMove(translation: translation) },
            onMoveEnded: { [weak self] in self?.endInteractiveMove() },
            onScaleChanged: onScaleChanged,
            onSend: onSend,
            onTypingChanged: onTypingChanged,
            onToggleHistory: { [weak self] in self?.toggleHistory() },
            onOpenSettings: onOpenSettings,
            onOverlayModeChanged: onOverlayModeChanged
        )
    }

    func restore(frame: CodableRect?, screenIdentifier: String? = nil) {
        let desired = frame?.cgRect ?? defaultFrame()
        let screens = screenGeometries
        let target: OverlayScreenGeometry?
        if let screenIdentifier {
            // A saved display that disappeared must fall back to the primary display,
            // not whichever display happens to intersect stale global coordinates.
            target = screens.first(where: {
                $0.identifier == screenIdentifier || $0.legacySignature == screenIdentifier
            }) ?? screens.first
        } else {
            target = OverlayPlacement.target(for: desired, screens: screens)
        }
        currentFrame = target.map { OverlayPlacement.clamped(desired, to: $0.visibleFrame) } ?? desired
        applyFrames()
    }

    func setVisible(_ visible: Bool) {
        overlayVisible = visible
        if visible {
            interactionWindow.setMode(currentMode)
            applyFrames()
            avatarWindow.orderFront()
            interactionWindow.setVisible(true)
        } else {
            historyRequested = false
            avatarWindow.orderOut()
            interactionWindow.setVisible(false)
            historyWindow.setVisible(false)
        }
    }

    func setMode(_ mode: OverlayMode) {
        currentMode = mode
        interactionWindow.setMode(mode)
        interactionWindow.setVisible(overlayVisible)
        applyFrames()
        if mode == .locked {
            historyRequested = false
            historyWindow.setVisible(false)
        }
    }

    func toggleHistory() {
        let shouldShow = !historyRequested
        setHistoryVisible(shouldShow)
        if shouldShow, overlayVisible, currentMode == .editing {
            onHistoryOpened()
        }
    }

    func move(by translation: CGSize) {
        currentFrame.origin.x += translation.width
        currentFrame.origin.y -= translation.height
        currentFrame = clamped(currentFrame)
        applyFrames()
    }

    func resetPosition() {
        interactiveMoveStartFrame = nil
        currentFrame = clamped(defaultFrame())
        applyFrames()
    }

    func focusMessageField() {
        guard overlayVisible else { return }
        interactionWindow.focusMessageField()
    }

    func beginInteractiveMove() {
        interactiveMoveStartFrame = currentFrame
    }

    func updateInteractiveMove(translation: CGSize) {
        guard var frame = interactiveMoveStartFrame else { return }
        frame.origin.x += translation.width
        frame.origin.y -= translation.height
        // Do not clamp on every drag event. Clamping to the current display here
        // traps the window at that display's edge and creates visible jitter while
        // the pointer is trying to cross onto an adjacent display.
        currentFrame = frame
        applyFrames()
    }

    func endInteractiveMove() {
        guard interactiveMoveStartFrame != nil else { return }
        interactiveMoveStartFrame = nil
        currentFrame = clamped(currentFrame)
        applyFrames()
        onMoveEnded()
    }

    var avatarLevel: NSWindow.Level { avatarWindow.level }
    var interactionLevel: NSWindow.Level { interactionWindow.level }
    var avatarIsVisible: Bool { avatarWindow.isVisible }
    var interactionIsVisible: Bool { interactionWindow.isVisible }
    var interactionSize: CGSize { interactionWindow.size }
    var avatarSize: CGSize { avatarWindow.size }
    var avatarCanHide: Bool { avatarWindow.canHide }
    var avatarIgnoresMouseEvents: Bool { avatarWindow.ignoresMouseEvents }
    var interactionIgnoresMouseEvents: Bool { interactionWindow.ignoresMouseEvents }
    var interactionIsKeyWindow: Bool { interactionWindow.isKeyWindow }
    var avatarIsRendering: Bool { avatarWindow.isRendering }
    var historyIsVisible: Bool { historyWindow.isVisible }
    var historyIgnoresMouseEvents: Bool { historyWindow.ignoresMouseEvents }
    var avatarCollectionBehavior: NSWindow.CollectionBehavior { avatarWindow.collectionBehavior }
    var interactionCollectionBehavior: NSWindow.CollectionBehavior { interactionWindow.collectionBehavior }
    var currentScreenIdentifier: String? {
        OverlayPlacement.target(for: currentFrame, screens: screenGeometries)?.identifier
    }

    private func applyFrames() {
        avatarWindow.setFrame(currentFrame)
        interactionWindow.setAnchorFrame(currentFrame)
        historyWindow.setAnchorFrame(currentFrame)
    }

    private func setHistoryVisible(_ visible: Bool) {
        historyRequested = visible
        historyWindow.setVisible(overlayVisible && currentMode == .editing && visible)
    }

    private func defaultFrame() -> CGRect {
        let visibleFrame = NSScreen.screens.first?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CGRect(
            x: visibleFrame.maxX - Self.defaultSize.width - 24,
            y: visibleFrame.minY + 24,
            width: Self.defaultSize.width,
            height: Self.defaultSize.height
        )
    }

    private func clamped(_ frame: CGRect) -> CGRect {
        guard let target = OverlayPlacement.target(for: frame, screens: screenGeometries) else {
            return frame
        }
        return OverlayPlacement.clamped(frame, to: target.visibleFrame)
    }

    private var screenGeometries: [OverlayScreenGeometry] {
        NSScreen.screens.map(\.sideyOverlayGeometry)
    }
}

private extension NSScreen {
    var sideyOverlayGeometry: OverlayScreenGeometry {
        let screenNumber = (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { $0.uint32Value }
        let identifier = screenNumber.map { "display:\($0)" }
            ?? "display:\(localizedName):\(Int(frame.width))x\(Int(frame.height))"
        let pixelWidth = Int((frame.width * backingScaleFactor).rounded())
        let pixelHeight = Int((frame.height * backingScaleFactor).rounded())
        let legacySignature = String(
            format: "%dx%d@%.3f",
            pixelWidth,
            pixelHeight,
            backingScaleFactor
        )
        return OverlayScreenGeometry(
            identifier: identifier,
            legacySignature: legacySignature,
            visibleFrame: visibleFrame
        )
    }
}
