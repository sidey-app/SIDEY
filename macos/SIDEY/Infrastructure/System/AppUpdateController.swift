import Foundation
import Sparkle

enum AppReleaseChannel: String, Equatable {
    case production
    case development

    static func resolve(from bundle: Bundle = .main) -> AppReleaseChannel {
        guard let value = bundle.object(forInfoDictionaryKey: "SIDEYReleaseChannel") as? String else {
            return .development
        }
        return AppReleaseChannel(rawValue: value) ?? .development
    }
}

@MainActor
protocol AppUpdateChecking: AnyObject {
    var canCheckForUpdates: Bool { get }
    func checkForUpdates()
}

@MainActor
final class SparkleUpdateController: AppUpdateChecking {
    private let controller: SPUStandardUpdaterController?

    init(
        releaseChannel: AppReleaseChannel = .resolve(),
        startingUpdater: Bool = true
    ) {
        if releaseChannel == .production {
            controller = SPUStandardUpdaterController(
                startingUpdater: startingUpdater,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        } else {
            controller = nil
        }
    }

    var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
