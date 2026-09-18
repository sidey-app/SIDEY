import AppKit
import SwiftUI

private final class StatusNoticePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

enum StatusNoticeLayout {
    static let panelSize = CGSize(width: 400, height: 64)
    static let stackGap: CGFloat = 8

    /// Uses the composer's top-center spot, or stacks below the composer while it is open.
    static func frame(in visibleFrame: CGRect, belowComposer: Bool) -> CGRect {
        let top = belowComposer
            ? OverlayComposerLayout.frame(in: visibleFrame).minY - stackGap
            : visibleFrame.maxY - OverlayComposerLayout.topInset
        return CGRect(
            x: visibleFrame.midX - panelSize.width / 2,
            y: top - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )
    }
}

/// Briefly confirms the result of a global shortcut. The shortcut was pressed while another
/// app was in use, so the notice never activates SIDEY, never becomes key and ignores the mouse.
@MainActor
final class StatusNoticeWindowController {
    static let displayDuration: Duration = .milliseconds(1600)
    private let panel: NSPanel
    private var hideTask: Task<Void, Never>?

    init() {
        panel = StatusNoticePanel(
            contentRect: CGRect(origin: .zero, size: StatusNoticeLayout.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
    }

    func show(_ notice: GlobalShortcutNotice, in visibleFrame: CGRect, belowComposer: Bool) {
        hideTask?.cancel()
        let hostingView = NSHostingView(rootView: StatusNoticeView(notice: notice))
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        panel.setFrame(
            StatusNoticeLayout.frame(in: visibleFrame, belowComposer: belowComposer),
            display: true
        )
        panel.orderFrontRegardless()
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: notice.accessibilityAnnouncement,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: StatusNoticeWindowController.displayDuration)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        panel.orderOut(nil)
        panel.contentView = nil
    }

    var isVisible: Bool { panel.isVisible }
    var level: NSWindow.Level { panel.level }
    var ignoresMouseEvents: Bool { panel.ignoresMouseEvents }
    var canBecomeKey: Bool { panel.canBecomeKey }
}

private struct StatusNoticeView: View {
    let notice: GlobalShortcutNotice

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: notice.symbolName)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(notice.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(width: 390, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .glassEffect(in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .padding(5)
        .background(Color.clear)
        .accessibilityElement(children: .combine)
    }
}
