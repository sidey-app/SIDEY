import AppKit

@MainActor
final class LoginItemDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let helperURL = Bundle.main.bundleURL
        let mainAppURL = (0..<4).reduce(helperURL) { url, _ in
            url.deletingLastPathComponent()
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--sidey-login-item"]
        configuration.activates = false
        NSWorkspace.shared.openApplication(
            at: mainAppURL,
            configuration: configuration
        ) { _, _ in
            Task { @MainActor in
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

let application = NSApplication.shared
let delegate = LoginItemDelegate()
application.delegate = delegate
application.setActivationPolicy(.prohibited)
application.run()
