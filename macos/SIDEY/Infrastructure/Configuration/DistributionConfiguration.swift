import Foundation

enum AppReleaseChannel: String, Equatable {
    case production
    case development
    case appStore = "app-store"

    static func resolve(from bundle: Bundle = .main) -> AppReleaseChannel {
        guard let value = bundle.object(forInfoDictionaryKey: "SIDEYReleaseChannel") as? String else {
            return .production
        }
        return AppReleaseChannel(rawValue: value) ?? .production
    }

    var storeAvailability: StoreAvailability {
        switch self {
        case .production: .comingSoon
        case .development: .direct
        case .appStore: .appStore
        }
    }

    var keychainService: String {
        switch self {
        case .production: "com.sidey.desktop"
        case .development: "com.sidey.desktop.dev"
        case .appStore: "com.sidey.desktop.appstore"
        }
    }

    var preferencesSuiteName: String? {
        switch self {
        case .production: nil
        case .development: "app.sidey.desktop.dev"
        case .appStore: "app.sidey.desktop.appstore"
        }
    }

    var loginItemMode: LaunchAtLoginController.Mode {
        switch self {
        case .production:
            .helper(identifier: "app.sidey.desktop.login-item")
        case .development:
            .helper(identifier: "app.sidey.desktop.dev.login-item")
        case .appStore:
            .mainApp
        }
    }

    var requiresAppleAuthentication: Bool { self == .appStore }
}

enum StoreAvailability: Equatable {
    case comingSoon
    case direct
    case appStore

    var allowsCommerceActions: Bool { self != .comingSoon }
    var usesAppStore: Bool { self == .appStore }
}
