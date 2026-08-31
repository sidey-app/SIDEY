import AppKit

@MainActor
enum PendingTextInputCommitter {
    /// macOS 한글 IME의 마지막 조합 문자를 확정한 뒤 저장 액션을 실행한다.
    ///
    /// 버튼 클릭 시 SwiftUI 바인딩 갱신보다 액션이 먼저 실행될 수 있으므로,
    /// 필드 에디터를 끝내고 다음 메인 런루프까지 기다린다.
    static func commitThen(
        in window: NSWindow? = NSApp.keyWindow ?? NSApp.mainWindow,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) {
        if let textInput = window?.firstResponder as? any NSTextInputClient,
           textInput.hasMarkedText() {
            textInput.unmarkText()
        }
        window?.makeFirstResponder(nil)

        Task { @MainActor in
            await Task.yield()
            action()
        }
    }
}
