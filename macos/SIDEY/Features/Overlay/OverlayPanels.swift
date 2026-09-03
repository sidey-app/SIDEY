import AppKit
import SwiftUI

private final class InteractiveOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class CharacterHotspotPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class CharacterHotspotView: NSView {
    let onClick: (Int) -> Void
    let onRightClick: () -> Void

    init(onClick: @escaping (Int) -> Void, onRightClick: @escaping () -> Void) {
        self.onClick = onClick
        self.onRightClick = onRightClick
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) { onClick(event.clickCount) }
    override func rightMouseDown(with event: NSEvent) { onRightClick() }
}

enum OverlayWindowIdentifier {
    static let composer = NSUserInterfaceItemIdentifier("sidey.overlay.composer")
    static let characterHotspot = NSUserInterfaceItemIdentifier("sidey.overlay.character-hotspot")

    static func isInteractionSource(_ identifier: NSUserInterfaceItemIdentifier?) -> Bool {
        identifier == composer || identifier == characterHotspot
    }
}

@MainActor
final class PixelWorldWindowController {
    private let panel: NSPanel
    private let model: AppModel
    private var hostingView: NSHostingView<PixelWorldView>?
    private var composerVisible = false
    private var characterPulse: CharacterPulseEvent?
    private var characterThrow: CharacterThrowEvent?
    private var localActivityFrame: CGRect = .zero
    private let onCharacterFramesChanged: ([UUID: CGRect]) -> Void

    init(
        model: AppModel,
        frame: CGRect,
        onCharacterFramesChanged: @escaping ([UUID: CGRect]) -> Void = { _ in }
    ) {
        self.model = model
        self.onCharacterFramesChanged = onCharacterFramesChanged
        panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
    }

    func setLayout(renderFrame: CGRect, localActivityFrame: CGRect) {
        self.localActivityFrame = localActivityFrame
        panel.setFrame(renderFrame, display: true)
        hostingView?.rootView = makeRootView()
    }

    func orderFront() {
        if hostingView == nil {
            let view = NSHostingView(rootView: makeRootView())
            hostingView = view
            panel.contentView = view
        }
        panel.orderFrontRegardless()
    }

    func setComposerVisible(_ visible: Bool) {
        guard composerVisible != visible else { return }
        composerVisible = visible
        hostingView?.rootView = makeRootView()
    }

    func playCharacterPulse(_ event: CharacterPulseEvent) {
        guard event.roomID == model.activeRoom?.id, let hostingView else { return }
        characterPulse = event
        hostingView.rootView = makeRootView()
    }

    func playCharacterThrow(_ event: CharacterThrowEvent) {
        guard event.roomID == model.activeRoom?.id, let hostingView else { return }
        characterThrow = event
        hostingView.rootView = makeRootView()
    }

    func orderOut() {
        panel.orderOut(nil)
        panel.contentView = nil
        hostingView = nil
        characterPulse = nil
        characterThrow = nil
    }

    var level: NSWindow.Level { panel.level }
    var isVisible: Bool { panel.isVisible }
    var canHide: Bool { panel.canHide }
    var ignoresMouseEvents: Bool { panel.ignoresMouseEvents }
    var isRendering: Bool { hostingView != nil }
    var size: CGSize { panel.frame.size }
    var collectionBehavior: NSWindow.CollectionBehavior { panel.collectionBehavior }

    private func makeRootView() -> PixelWorldView {
        PixelWorldView(
            model: model,
            activityFrame: localActivityFrame,
            composerVisible: composerVisible,
            characterPulse: characterPulse,
            characterThrow: characterThrow,
            onCharacterFramesChanged: onCharacterFramesChanged
        )
    }
}

enum OverlayComposerLayout {
    static let panelSize = CGSize(width: 400, height: 56)
    static let topInset: CGFloat = 10

    static func frame(in visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.maxY - panelSize.height - topInset,
            width: panelSize.width,
            height: panelSize.height
        )
    }
}

@MainActor
final class OverlayInteractionWindowController: NSObject, NSWindowDelegate {
    static let panelSize = OverlayComposerLayout.panelSize
    private let panel: NSPanel
    private let onDismissRequested: () -> Void
    private var focusRequestID = 0
    private var isProgrammaticallyHiding = false

    init(
        model: AppModel,
        onSend: @escaping (String) -> Void,
        onInputActivity: @escaping () -> Void,
        onTypingChanged: @escaping (Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        onDismissRequested = onCancel
        panel = InteractiveOverlayPanel(
            contentRect: CGRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.identifier = OverlayWindowIdentifier.composer
        panel.delegate = self
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.isReleasedWhenClosed = false
        let hostingView = NSHostingView(
            rootView: OverlayComposerView(
                model: model,
                onSend: onSend,
                onInputActivity: onInputActivity,
                onTypingChanged: onTypingChanged,
                onCancel: onCancel
            )
        )
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
    }

    func setScreenFrame(_ visibleFrame: CGRect) {
        panel.setFrame(OverlayComposerLayout.frame(in: visibleFrame), display: panel.isVisible)
    }

    func setVisible(_ visible: Bool) {
        if visible {
            // Showing the composer must not steal focus from the current app.
            panel.orderFrontRegardless()
        } else {
            focusRequestID &+= 1
            isProgrammaticallyHiding = true
            panel.orderOut(nil)
            isProgrammaticallyHiding = false
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isProgrammaticallyHiding, panel.isVisible else { return }
        onDismissRequested()
    }

    func focusMessageField() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        focusRequestID &+= 1
        let requestID = focusRequestID

        // Character clicks arrive from a non-activating hotspot panel. Defer
        // first-responder assignment until that mouse event has completed and
        // SwiftUI has attached the representable NSTextView to the view tree.
        DispatchQueue.main.async { [weak self] in
            self?.completeMessageFieldFocus(requestID: requestID, attemptsRemaining: 2)
        }
    }

    private func completeMessageFieldFocus(requestID: Int, attemptsRemaining: Int) {
        guard requestID == focusRequestID, panel.isVisible else { return }
        panel.contentView?.layoutSubtreeIfNeeded()
        if let field = panel.contentView?.firstDescendant(
            withIdentifier: NSUserInterfaceItemIdentifier("sidey.message-field")
        ) {
            panel.makeKeyAndOrderFront(nil)
            if panel.makeFirstResponder(field) { return }
        }

        guard attemptsRemaining > 0 else { return }
        DispatchQueue.main.async { [weak self] in
            self?.completeMessageFieldFocus(
                requestID: requestID,
                attemptsRemaining: attemptsRemaining - 1
            )
        }
    }

    var level: NSWindow.Level { panel.level }
    var isVisible: Bool { panel.isVisible }
    var size: CGSize { panel.frame.size }
    var ignoresMouseEvents: Bool { panel.ignoresMouseEvents }
    var isKeyWindow: Bool { panel.isKeyWindow }
    var usesTransparentSurface: Bool {
        guard
            let layer = panel.contentView?.layer,
            let layerBackground = layer.backgroundColor,
            let layerColor = NSColor(cgColor: layerBackground)
        else { return false }

        return !panel.isOpaque
            && panel.backgroundColor.alphaComponent < 0.001
            && !layer.isOpaque
            && layerColor.alphaComponent < 0.001
    }
    var messageFieldIsFirstResponder: Bool {
        (panel.firstResponder as? NSView)?.identifier
            == NSUserInterfaceItemIdentifier("sidey.message-field")
    }
    var collectionBehavior: NSWindow.CollectionBehavior { panel.collectionBehavior }
}

@MainActor
final class CharacterHotspotWindowController {
    static let panelSize = CGSize(width: 52, height: 52)
    private let panel: NSPanel
    private var requestedVisible = false
    private var hasFrame = false

    init(
        onClick: @escaping (Int) -> Void,
        onRightClick: @escaping () -> Void = {}
    ) {
        panel = CharacterHotspotPanel(
            contentRect: CGRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.identifier = OverlayWindowIdentifier.characterHotspot
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.ignoresMouseEvents = false
        panel.isReleasedWhenClosed = false
        panel.contentView = CharacterHotspotView(onClick: onClick, onRightClick: onRightClick)
    }

    func setFrame(_ frame: CGRect?) {
        guard let frame else {
            hasFrame = false
            panel.orderOut(nil)
            return
        }
        hasFrame = true
        panel.setFrame(frame, display: false)
        if requestedVisible { panel.orderFrontRegardless() }
    }

    func setVisible(_ visible: Bool) {
        requestedVisible = visible
        if visible, hasFrame {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    var isVisible: Bool { panel.isVisible }
    var ignoresMouseEvents: Bool { panel.ignoresMouseEvents }
    var size: CGSize { panel.frame.size }
}

@MainActor
final class HistoryWindowController: NSWindowController, NSWindowDelegate {
    static let contentSize = CGSize(width: 560, height: 420)
    private let model: AppModel
    private(set) var historyStore: MessageHistoryStore

    convenience init(model: AppModel) {
        self.init(
            model: model,
            loadPage: { _, _, _ in
                MessageHistoryPage(messages: [], nextCursor: nil)
            }
        )
    }

    init(
        model: AppModel,
        loadPage: @escaping MessageHistoryPageLoader
    ) {
        self.model = model
        let historyStore = MessageHistoryStore(loadPage: loadPage)
        self.historyStore = historyStore
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SIDEY 최근 기록"
        window.level = .normal
        window.collectionBehavior = [.managed]
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 440, height: 300)
        window.center()
        window.contentView = NSHostingView(
            rootView: OverlayHistoryView(
                model: model,
                history: historyStore,
                onClose: { [weak window] in
                    historyStore.deactivate()
                    window?.orderOut(nil)
                }
            )
        )
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        historyStore.activate(roomID: model.realtimeActiveRoomID)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        historyStore.deactivate()
    }
}

private extension NSView {
    func firstDescendant(withIdentifier identifier: NSUserInterfaceItemIdentifier) -> NSView? {
        if self.identifier == identifier { return self }
        for subview in subviews {
            if let match = subview.firstDescendant(withIdentifier: identifier) { return match }
        }
        return nil
    }
}
