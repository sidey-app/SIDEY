import AppKit

private final class ScreenObserverToken: @unchecked Sendable {
    let value: NSObjectProtocol

    init(_ value: NSObjectProtocol) { self.value = value }

    deinit { NotificationCenter.default.removeObserver(value) }
}

struct OverlayScreenGeometry: Equatable, Sendable {
    let identifier: String
    let legacySignature: String
    let name: String
    let visibleFrame: CGRect
}

enum OverlayRegionLayout {
    static let preferredDepth: CGFloat = 180

    static func screen(
        for preference: OverlayRegionPreference,
        screens: [OverlayScreenGeometry]
    ) -> OverlayScreenGeometry? {
        guard !screens.isEmpty else { return nil }
        guard let identifier = preference.screenIdentifier else { return screens.first }
        return screens.first(where: {
            $0.identifier == identifier || $0.legacySignature == identifier
        }) ?? screens.first
    }

    static func frame(
        for preference: OverlayRegionPreference,
        on screen: OverlayScreenGeometry
    ) -> CGRect {
        let visible = screen.visibleFrame
        let depth = min(preferredDepth, visible.height / 3)
        if preference.edge.isHorizontal {
            let length = visible.width * preference.span.fraction
            return CGRect(
                x: visible.midX - length / 2,
                y: preference.edge == .bottom ? visible.minY : visible.maxY - depth,
                width: length,
                height: depth
            )
        }

        let length = visible.height * preference.span.fraction
        return CGRect(
            x: preference.edge == .left ? visible.minX : visible.maxX - depth,
            y: visible.midY - length / 2,
            width: depth,
            height: length
        )
    }
}

@MainActor
final class OverlayWindowGroup {
    private let worldWindow: PixelWorldWindowController
    private let interactionWindow: OverlayInteractionWindowController
    private let model: AppModel
    private let onRegionChanged: () -> Void
    private var screenObserver: ScreenObserverToken?
    private(set) var currentFrame: CGRect = .zero
    private(set) var currentScreenIdentifier: String?
    private var overlayVisible = false

    init(
        model: AppModel,
        onSend: @escaping (String) -> Void = { _ in },
        onTypingChanged: @escaping (Bool) -> Void = { _ in },
        onRegionChanged: @escaping () -> Void = {}
    ) {
        self.model = model
        self.onRegionChanged = onRegionChanged
        worldWindow = PixelWorldWindowController(model: model, frame: .zero)
        interactionWindow = OverlayInteractionWindowController(
            model: model,
            onSend: onSend,
            onTypingChanged: onTypingChanged
        )
        screenObserver = ScreenObserverToken(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensDidChange() }
        })
        refreshAvailableScreens()
    }

    func restore(preference: OverlayRegionPreference) {
        apply(preference: preference, persistFallback: true)
    }

    func setRegionPreference(_ preference: OverlayRegionPreference) {
        model.preferences.overlayRegion = preference
        apply(preference: preference, persistFallback: true)
    }

    func setVisible(_ visible: Bool) {
        overlayVisible = visible
        if visible {
            apply(preference: model.preferences.overlayRegion, persistFallback: true)
            worldWindow.orderFront()
            interactionWindow.setVisible(true)
        } else {
            worldWindow.orderOut()
            interactionWindow.setVisible(false)
        }
    }

    func focusMessageField() {
        guard overlayVisible else { return }
        interactionWindow.focusMessageField()
    }

    var worldLevel: NSWindow.Level { worldWindow.level }
    var interactionLevel: NSWindow.Level { interactionWindow.level }
    var worldIsVisible: Bool { worldWindow.isVisible }
    var interactionIsVisible: Bool { interactionWindow.isVisible }
    var interactionSize: CGSize { interactionWindow.size }
    var worldSize: CGSize { worldWindow.size }
    var worldCanHide: Bool { worldWindow.canHide }
    var worldIgnoresMouseEvents: Bool { worldWindow.ignoresMouseEvents }
    var interactionIgnoresMouseEvents: Bool { interactionWindow.ignoresMouseEvents }
    var interactionIsKeyWindow: Bool { interactionWindow.isKeyWindow }
    var worldIsRendering: Bool { worldWindow.isRendering }
    var worldCollectionBehavior: NSWindow.CollectionBehavior { worldWindow.collectionBehavior }
    var interactionCollectionBehavior: NSWindow.CollectionBehavior { interactionWindow.collectionBehavior }

    private func apply(preference: OverlayRegionPreference, persistFallback: Bool) {
        let screens = screenGeometries
        guard let screen = OverlayRegionLayout.screen(for: preference, screens: screens) else { return }
        var resolved = preference
        let requestedScreenExists = preference.screenIdentifier == nil || screens.contains(where: {
            $0.identifier == preference.screenIdentifier || $0.legacySignature == preference.screenIdentifier
        })
        resolved.screenIdentifier = screen.identifier
        currentScreenIdentifier = screen.identifier
        currentFrame = OverlayRegionLayout.frame(for: resolved, on: screen)
        worldWindow.setFrame(currentFrame)
        interactionWindow.setScreenFrame(screen.visibleFrame)

        if persistFallback,
           (!requestedScreenExists || model.preferences.overlayRegion != resolved) {
            model.preferences.overlayRegion = resolved
            onRegionChanged()
        }
    }

    private func screensDidChange() {
        refreshAvailableScreens()
        apply(preference: model.preferences.overlayRegion, persistFallback: true)
    }

    private func refreshAvailableScreens() {
        model.availableScreens = screenGeometries.map {
            OverlayScreenOption(id: $0.identifier, name: $0.name)
        }
    }

    private var screenGeometries: [OverlayScreenGeometry] {
        let screens = NSScreen.screens
        guard let main = NSScreen.main else { return screens.map(\.sideyOverlayGeometry) }
        return ([main] + screens.filter { $0 !== main }).map(\.sideyOverlayGeometry)
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
            name: localizedName,
            visibleFrame: visibleFrame
        )
    }
}
