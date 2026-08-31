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

@MainActor
protocol ComposerAutoDismissScheduling: AnyObject {
    func schedule(after delay: Duration, action: @escaping @MainActor () -> Void)
    func cancel()
}

@MainActor
private final class TaskComposerAutoDismissScheduler: ComposerAutoDismissScheduling {
    private var task: Task<Void, Never>?

    func schedule(after delay: Duration, action: @escaping @MainActor () -> Void) {
        cancel()
        task = Task { @MainActor in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

enum OverlayRegionLayout {
    static let preferredDepth: CGFloat = 240

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
    static let defaultComposerAutoDismissDelay: Duration = .seconds(5)

    private let model: AppModel
    private let onSend: (String) -> Void
    private let onTypingChanged: (Bool) -> Void
    private let onCharacterDoubleClick: () -> Void
    private let onRegionChanged: () -> Void
    private lazy var worldWindow = PixelWorldWindowController(
        model: model,
        frame: .zero,
        onCurrentUserFrameChanged: { [weak self] frame in self?.currentUserFrameChanged(frame) }
    )
    private lazy var interactionWindow = OverlayInteractionWindowController(
        model: model,
        onSend: { [weak self] body in self?.submitComposerMessage(body) },
        onTypingChanged: { [weak self] active in self?.onTypingChanged(active) },
        onCancel: { [weak self] in self?.dismissComposer() }
    )
    private lazy var hotspotWindow = CharacterHotspotWindowController(
        onClick: { [weak self] clickCount in self?.handleCharacterClick(clickCount: clickCount) }
    )
    private var screenObserver: ScreenObserverToken?
    private(set) var currentFrame: CGRect = .zero
    private(set) var currentScreenIdentifier: String?
    private var overlayVisible = false
    private(set) var composerVisible = false
    private var currentUserLocalFrame: CGRect?
    private let composerAutoDismissDelay: Duration
    private let composerAutoDismissScheduler: any ComposerAutoDismissScheduling

    init(
        model: AppModel,
        onSend: @escaping (String) -> Void = { _ in },
        onTypingChanged: @escaping (Bool) -> Void = { _ in },
        onCharacterDoubleClick: @escaping () -> Void = {},
        onRegionChanged: @escaping () -> Void = {},
        composerAutoDismissDelay: Duration = OverlayWindowGroup.defaultComposerAutoDismissDelay,
        composerAutoDismissScheduler: (any ComposerAutoDismissScheduling)? = nil
    ) {
        self.model = model
        self.onSend = onSend
        self.onTypingChanged = onTypingChanged
        self.onCharacterDoubleClick = onCharacterDoubleClick
        self.onRegionChanged = onRegionChanged
        self.composerAutoDismissDelay = composerAutoDismissDelay
        self.composerAutoDismissScheduler = composerAutoDismissScheduler ?? TaskComposerAutoDismissScheduler()
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
            hotspotWindow.setVisible(true)
        } else {
            dismissComposer()
            hotspotWindow.setVisible(false)
            worldWindow.orderOut()
        }
    }

    func focusMessageField() {
        presentComposer()
    }

    func presentComposer() {
        guard overlayVisible, model.activeRoom != nil else { return }
        cancelComposerAutoDismiss()
        composerVisible = true
        worldWindow.setComposerVisible(true)
        interactionWindow.setVisible(true)
        interactionWindow.focusMessageField()
        if !MessageValidator.normalized(model.draft).isEmpty {
            onTypingChanged(true)
        }
    }

    func dismissComposer() {
        dismissComposer(sendTypingStop: true)
    }

    func toggleComposer() {
        composerVisible ? dismissComposer() : presentComposer()
    }

    func handleCharacterClick(clickCount: Int) {
        switch clickCount {
        case 1:
            toggleComposer()
        case 2:
            // The first click in the sequence already performed the existing
            // single-click behavior. Keep the composer open after the second.
            presentComposer()
            onCharacterDoubleClick()
        default:
            break
        }
    }

    func playCharacterPulse(_ event: CharacterPulseEvent) {
        worldWindow.playCharacterPulse(event)
    }

    func submitComposerMessage(_ body: String) {
        guard composerVisible else { return }
        scheduleComposerAutoDismiss()
        onSend(body)
    }

    var worldLevel: NSWindow.Level { worldWindow.level }
    var interactionLevel: NSWindow.Level { interactionWindow.level }
    var worldIsVisible: Bool { worldWindow.isVisible }
    var interactionIsVisible: Bool { interactionWindow.isVisible }
    var hotspotIsVisible: Bool { hotspotWindow.isVisible }
    var hotspotIgnoresMouseEvents: Bool { hotspotWindow.ignoresMouseEvents }
    var hotspotSize: CGSize { hotspotWindow.size }
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
        positionHotspot()

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

    private func dismissComposer(sendTypingStop: Bool) {
        cancelComposerAutoDismiss()
        guard composerVisible || interactionWindow.isVisible else { return }
        composerVisible = false
        interactionWindow.setVisible(false)
        worldWindow.setComposerVisible(false)
        if sendTypingStop { onTypingChanged(false) }
    }

    private func scheduleComposerAutoDismiss() {
        composerAutoDismissScheduler.schedule(after: composerAutoDismissDelay) { [weak self] in
            self?.dismissComposer(sendTypingStop: true)
        }
    }

    private func cancelComposerAutoDismiss() {
        composerAutoDismissScheduler.cancel()
    }

    private func currentUserFrameChanged(_ localFrame: CGRect?) {
        currentUserLocalFrame = localFrame
        guard localFrame != nil else {
            hotspotWindow.setFrame(nil)
            dismissComposer()
            return
        }
        positionHotspot()
    }

    private func positionHotspot() {
        guard let localFrame = currentUserLocalFrame else { return }
        hotspotWindow.setFrame(CGRect(
            x: currentFrame.minX + localFrame.minX,
            y: currentFrame.minY + localFrame.minY,
            width: localFrame.width,
            height: localFrame.height
        ))
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
