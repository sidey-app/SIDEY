import AppKit
import SwiftUI

private final class InteractiveOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PixelWorldWindowController {
    private let panel: NSPanel
    private let model: AppModel
    private var hostingView: NSHostingView<PixelWorldView>?

    init(model: AppModel, frame: CGRect) {
        self.model = model
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
            let view = NSHostingView(rootView: PixelWorldView(model: model))
            hostingView = view
            panel.contentView = view
        }
        panel.orderFrontRegardless()
    }

    func orderOut() {
        panel.orderOut(nil)
        panel.contentView = nil
        hostingView = nil
    }

    var level: NSWindow.Level { panel.level }
    var isVisible: Bool { panel.isVisible }
    var canHide: Bool { panel.canHide }
    var ignoresMouseEvents: Bool { panel.ignoresMouseEvents }
    var isRendering: Bool { hostingView != nil }
    var size: CGSize { panel.frame.size }
    var collectionBehavior: NSWindow.CollectionBehavior { panel.collectionBehavior }
}

@MainActor
final class OverlayInteractionWindowController {
    static let panelSize = CGSize(width: 400, height: 56)
    private let panel: NSPanel

    init(
        model: AppModel,
        onSend: @escaping (String) -> Void,
        onTypingChanged: @escaping (Bool) -> Void
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
                onTypingChanged: onTypingChanged
            )
        )
    }

    func setScreenFrame(_ visibleFrame: CGRect) {
        panel.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - Self.panelSize.width / 2,
            y: visibleFrame.minY + 10
        ))
    }

    func setVisible(_ visible: Bool) {
        if visible {
            // Showing the composer must not steal focus from the current app.
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    func focusMessageField() {
        panel.makeKeyAndOrderFront(nil)
        guard let field = panel.contentView?.firstDescendant(
            withIdentifier: NSUserInterfaceItemIdentifier("sidey.message-field")
        ) else { return }
        panel.makeFirstResponder(field)
    }

    var level: NSWindow.Level { panel.level }
    var isVisible: Bool { panel.isVisible }
    var size: CGSize { panel.frame.size }
    var ignoresMouseEvents: Bool { panel.ignoresMouseEvents }
    var isKeyWindow: Bool { panel.isKeyWindow }
    var collectionBehavior: NSWindow.CollectionBehavior { panel.collectionBehavior }
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
