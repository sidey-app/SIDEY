import AppKit
import SwiftUI

@main
struct RealsApp: App {
    @NSApplicationDelegateAdaptor(RealsAppDelegate.self) private var delegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class RealsAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let editor = RealsEditor()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !ProcessInfo.processInfo.arguments.contains("-XCTest") && NSClassFromString("XCTestCase") == nil else { return }
        guard BuildReview.shared.validateLaunch() else { NSApp.terminate(nil); return }
        NSApplication.shared.setActivationPolicy(.regular)
        showEditor()
        BuildReview.shared.observeReadyWindow()
    }

    private func showEditor() {
        if let window {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1180, height: 800),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "sidey-reals"
            window.minSize = CGSize(width: 1000, height: 700)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: RealsEditorView(editor: editor))
            window.center()
            window.makeKeyAndOrderFront(nil)
            self.window = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showEditor()
        return false
    }

    func windowWillClose(_ notification: Notification) { editor.shutdown() }
    func applicationWillTerminate(_ notification: Notification) { editor.shutdown() }
}
