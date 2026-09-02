import Foundation
import Sparkle

enum AppReleaseChannel: String, Equatable {
    case production
    case development

    static func resolve(from bundle: Bundle = .main) -> AppReleaseChannel {
        guard let value = bundle.object(forInfoDictionaryKey: "SIDEYReleaseChannel") as? String else {
            return .production
        }
        return AppReleaseChannel(rawValue: value) ?? .production
    }

    var storeAvailability: StoreAvailability {
        switch self {
        case .production: .comingSoon
        case .development: .enabled
        }
    }

    var keychainService: String {
        switch self {
        case .production: "com.sidey.desktop"
        case .development: "com.sidey.desktop.dev"
        }
    }

    var preferencesSuiteName: String? {
        switch self {
        case .production: nil
        case .development: "app.sidey.desktop.dev"
        }
    }

    var loginItemIdentifier: String {
        switch self {
        case .production: "app.sidey.desktop.login-item"
        case .development: "app.sidey.desktop.dev.login-item"
        }
    }
}

enum StoreAvailability: Equatable {
    case comingSoon
    case enabled

    var allowsCommerceActions: Bool { self == .enabled }
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
