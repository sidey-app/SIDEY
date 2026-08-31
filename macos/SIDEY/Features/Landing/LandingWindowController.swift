import AppKit
import SwiftUI

@MainActor
final class LandingWindowController: NSWindowController {
    private let onSkip: () -> Void
    private let onFirstFrame: () -> Void
    private var didReportFirstFrame = false
    private var isRestoringSession = false

    init(onSkip: @escaping () -> Void, onFirstFrame: @escaping () -> Void = {}) {
        self.onSkip = onSkip
        self.onFirstFrame = onFirstFrame
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 680, height: 440),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = "SIDEY"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.center()
        window.contentView = NSHostingView(rootView: LandingView(
            isRestoringSession: false,
            onSkip: onSkip
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show() {
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.displayIfNeeded()
        guard !didReportFirstFrame else { return }
        didReportFirstFrame = true
        DispatchQueue.main.async { [onFirstFrame] in
            onFirstFrame()
        }
    }

    func setRestoringSession(_ restoring: Bool) {
        guard isRestoringSession != restoring else { return }
        isRestoringSession = restoring
        window?.contentView = NSHostingView(rootView: LandingView(
            isRestoringSession: restoring,
            onSkip: onSkip
        ))
    }
}
