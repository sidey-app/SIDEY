import AppKit
import SwiftUI

private final class InteractiveOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AvatarOverlayWindowController {
    private let panel: NSPanel
    private let model: AppModel
    private var hostingView: NSHostingView<AvatarOverlayView>?

    init(model: AppModel, frame: CGRect) {
        self.model = model
        let avatarFrame = Self.extendedFrame(from: frame)
        panel = NSPanel(
            contentRect: avatarFrame,
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

    func setFrame(_ frame: CGRect) { panel.setFrame(Self.extendedFrame(from: frame), display: true) }
    func orderFront() {
        if hostingView == nil {
            let view = NSHostingView(rootView: AvatarOverlayView(model: model))
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

    private static func extendedFrame(from anchorFrame: CGRect) -> CGRect {
        CGRect(
            x: anchorFrame.minX,
            y: anchorFrame.minY,
            width: anchorFrame.width,
            height: anchorFrame.height + AvatarOverlayLayout.topWindowExtension
        )
    }
}

@MainActor
final class OverlayInteractionWindowController {
    private static let lockedPanelSize = CGSize(width: 400, height: 56)
    private static let editingPanelSize = CGSize(width: 580, height: 56)
    private let panel: NSPanel

    init(
        model: AppModel,
        onMoveBegan: @escaping () -> Void,
        onDrag: @escaping (CGSize) -> Void,
        onMoveEnded: @escaping () -> Void,
        onScaleChanged: @escaping (Double) -> Void,
        onSend: @escaping (String) -> Void,
        onTypingChanged: @escaping (Bool) -> Void,
        onToggleHistory: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOverlayModeChanged: @escaping (OverlayMode) -> Void
    ) {
        panel = InteractiveOverlayPanel(
            contentRect: CGRect(origin: .zero, size: Self.panelSize(for: model.overlayMode)),
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
                onMoveBegan: onMoveBegan,
                onDrag: onDrag,
                onMoveEnded: onMoveEnded,
                onScaleChanged: onScaleChanged,
                onSend: onSend,
                onTypingChanged: onTypingChanged,
                onToggleHistory: onToggleHistory,
                onOpenSettings: onOpenSettings,
                onOverlayModeChanged: onOverlayModeChanged
            )
        )
    }

    func setAnchorFrame(_ overlayFrame: CGRect) {
        panel.setFrameOrigin(NSPoint(
            x: overlayFrame.midX - panel.frame.width / 2,
            y: overlayFrame.minY + 8
        ))
    }

    func setMode(_ mode: OverlayMode) {
        let size = Self.panelSize(for: mode)
        guard panel.frame.size != size else { return }
        let oldFrame = panel.frame
        panel.setFrame(
            CGRect(
                x: oldFrame.midX - size.width / 2,
                y: oldFrame.minY,
                width: size.width,
                height: size.height
            ),
            display: true
        )
    }

    func setVisible(_ visible: Bool) {
        if visible {
            // The always-present composer must not steal keyboard focus from
            // whichever app the user is currently working in.
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

    private static func panelSize(for mode: OverlayMode) -> CGSize {
        mode == .editing ? editingPanelSize : lockedPanelSize
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

@MainActor
final class OverlayHistoryWindowController {
    private static let panelSize = CGSize(width: 400, height: 280)
    private let panel: NSPanel

    init(model: AppModel, onClose: @escaping () -> Void) {
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
            rootView: OverlayHistoryView(model: model, onClose: onClose)
        )
    }

    func setAnchorFrame(_ overlayFrame: CGRect) {
        panel.setFrameOrigin(NSPoint(
            x: overlayFrame.midX - Self.panelSize.width / 2,
            y: overlayFrame.minY + 78
        ))
    }

    func setVisible(_ visible: Bool) {
        if visible {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderOut(nil)
        }
    }

    var isVisible: Bool { panel.isVisible }
    var ignoresMouseEvents: Bool { panel.ignoresMouseEvents }
    var collectionBehavior: NSWindow.CollectionBehavior { panel.collectionBehavior }
}
