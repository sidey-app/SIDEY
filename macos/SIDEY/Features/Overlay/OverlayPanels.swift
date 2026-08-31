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

    init(onClick: @escaping (Int) -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) { onClick(event.clickCount) }
}

@MainActor
final class PixelWorldWindowController {
    private let panel: NSPanel
    private let model: AppModel
    private var hostingView: NSHostingView<PixelWorldView>?
    private var composerVisible = false
    private var characterPulse: CharacterPulseEvent?
    private let onCurrentUserFrameChanged: (CGRect?) -> Void

    init(
        model: AppModel,
        frame: CGRect,
        onCurrentUserFrameChanged: @escaping (CGRect?) -> Void = { _ in }
    ) {
        self.model = model
        self.onCurrentUserFrameChanged = onCurrentUserFrameChanged
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

    func setFrame(_ frame: CGRect) { panel.setFrame(frame, display: true) }

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

    func orderOut() {
        panel.orderOut(nil)
        panel.contentView = nil
        hostingView = nil
        characterPulse = nil
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
            composerVisible: composerVisible,
            characterPulse: characterPulse,
            onCurrentUserFrameChanged: onCurrentUserFrameChanged
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
final class OverlayInteractionWindowController {
    static let panelSize = OverlayComposerLayout.panelSize
    private let panel: NSPanel
    private var focusRequestID = 0

    init(
        model: AppModel,
        onSend: @escaping (String) -> Void,
        onInputActivity: @escaping () -> Void,
        onTypingChanged: @escaping (Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        panel = InteractiveOverlayPanel(
            contentRect: CGRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless],
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
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(
            rootView: OverlayComposerView(
                model: model,
                onSend: onSend,
                onInputActivity: onInputActivity,
                onTypingChanged: onTypingChanged,
                onCancel: onCancel
            )
        )
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
            panel.orderOut(nil)
        }
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

    init(onClick: @escaping (Int) -> Void) {
        panel = CharacterHotspotPanel(
            contentRect: CGRect(origin: .zero, size: Self.panelSize),
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
        panel.ignoresMouseEvents = false
        panel.isReleasedWhenClosed = false
        panel.contentView = CharacterHotspotView(onClick: onClick)
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
    private let onClose: () -> Void

    init(model: AppModel, onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
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
            rootView: OverlayHistoryView(model: model, onClose: { window.orderOut(nil) })
        )
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() { window?.makeKeyAndOrderFront(nil) }

    func windowWillClose(_ notification: Notification) { onClose() }
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
