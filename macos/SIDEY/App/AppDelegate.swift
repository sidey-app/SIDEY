import AppKit
import QuartzCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private let launchProbe = LaunchPerformanceProbe()
    private lazy var updateController = SparkleUpdateController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = ProcessInfo.processInfo.environment
        if environment["SIDEY_TESTING"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
            || NSClassFromString("XCTest.XCTestCase") != nil {
            return
        }
        let coordinator: AppCoordinator
        if let suiteName = environment["SIDEY_PREFERENCES_SUITE"],
           let defaults = UserDefaults(suiteName: suiteName) {
            coordinator = AppCoordinator(
                updateController: updateController,
                preferencesStore: .userDefaults(defaults),
                legacyMigrator: .none,
                onLandingFirstFrame: { [weak launchProbe] in
                    launchProbe?.markFirstFrame()
                }
            )
        } else {
            coordinator = AppCoordinator(
                updateController: updateController,
                onLandingFirstFrame: { [weak launchProbe] in
                    launchProbe?.markFirstFrame()
                }
            )
        }
        self.coordinator = coordinator
        coordinator.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator?.handleManualReopen(
            originatesFromOverlayInteraction: OverlayWindowIdentifier.isInteractionSource(
                sender.currentEvent?.window?.identifier
            )
        )
        // AppCoordinator exclusively owns SIDEY's custom settings window.
        // Prevent AppKit/SwiftUI from restoring the empty Settings scene too.
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where coordinator?.handleOpenURL(url) == true {
            return
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.shutdown()
    }
}

@MainActor
private final class LaunchPerformanceProbe {
    private let startedAt = CACurrentMediaTime()
    private let outputURL = ProcessInfo.processInfo.environment["SIDEY_LAUNCH_METRICS_PATH"]
        .map { URL(fileURLWithPath: $0) }
    private var didReport = false

    func markFirstFrame() {
        guard !didReport, let outputURL else { return }
        didReport = true
        let snapshot = LaunchMetricsSnapshot(
            firstLandingFrameMS: (CACurrentMediaTime() - startedAt) * 1_000
        )
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: outputURL, options: .atomic)
        }
    }
}

private struct LaunchMetricsSnapshot: Codable, Sendable {
    let firstLandingFrameMS: Double
}
