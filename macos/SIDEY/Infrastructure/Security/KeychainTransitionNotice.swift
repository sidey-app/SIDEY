import AppKit

enum KeychainTransitionNotice {
    static let message =
        "SIDEY는 로그인 상태와 그룹 초대 코드를 안전하게 보관하고 불러오기 위해 macOS 키체인을 사용합니다."

    static let migrationExplanation =
        "이전 버전에서 저장한 정보를 처음 불러올 때 Mac 로그인 암호를 요청할 수 있습니다. 다음부터 묻지 않도록 하려면 이어서 표시되는 macOS 창에서 ‘항상 허용’을 선택해 주세요. ‘허용’을 선택하면 저장된 정보에 따라 창이 몇 차례 더 나타나거나 다음 실행 때 다시 표시될 수 있습니다."

    static let privacyExplanation =
        "SIDEY는 입력한 암호를 확인하거나 저장하지 않습니다."

    @MainActor
    static func present() -> Bool {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = message
        alert.informativeText = "\(migrationExplanation)\n\n\(privacyExplanation)"
        alert.addButton(withTitle: "계속")
        alert.addButton(withTitle: "SIDEY 종료")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
