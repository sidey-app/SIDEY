import Foundation
import ServiceManagement

@MainActor
struct LaunchAtLoginController {
    let helperIdentifier: String

    init(helperIdentifier: String = AppReleaseChannel.resolve().loginItemIdentifier) {
        self.helperIdentifier = helperIdentifier
    }

    private var service: SMAppService {
        SMAppService.loginItem(identifier: helperIdentifier)
    }

    var isEnabled: Bool {
        service.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status != .notRegistered else { return }
            try service.unregister()
        }
    }
}
