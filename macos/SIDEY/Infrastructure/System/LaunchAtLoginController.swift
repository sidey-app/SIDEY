import Foundation
import ServiceManagement

@MainActor
struct LaunchAtLoginController {
    static let helperIdentifier = "app.sidey.desktop.login-item"

    private var service: SMAppService {
        SMAppService.loginItem(identifier: Self.helperIdentifier)
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
