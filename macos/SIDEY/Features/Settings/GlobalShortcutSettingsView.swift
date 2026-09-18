import AppKit
import SwiftUI

extension GlobalShortcutModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var modifiers: GlobalShortcutModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        self = modifiers
    }
}

struct GlobalShortcutSettingsRow: View {
    let action: GlobalShortcutAction
    let shortcut: GlobalShortcut?
    let status: GlobalShortcutStatus?
    let isRecording: Bool
    let onBeginRecording: () -> Void
    let onRecord: (GlobalShortcut) -> Void
    let onCancelRecording: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                SettingsRowLabel(title: action.title, description: action.summary)
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(statusIsWarning ? Color.orange : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 16)
            HStack(spacing: 8) {
                recorderField
                Button("지우기", action: onClear)
                    .disabled(shortcut == nil)
            }
            .frame(width: 240, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }

    private var recorderField: some View {
        Text(fieldTitle)
            .font(.callout)
            .foregroundStyle(shortcut == nil || isRecording ? Color.secondary : Color.primary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(
                Color.primary.opacity(isRecording ? 0.08 : 0.04),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isRecording ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: 1)
            }
            .overlay {
                GlobalShortcutKeyCapture(
                    isRecording: isRecording,
                    onBegin: onBeginRecording,
                    onRecord: onRecord,
                    onCancel: onCancelRecording
                )
            }
    }

    private var fieldTitle: String {
        if isRecording { return "조합 입력 대기 중…" }
        return shortcut?.displayString ?? "클릭해서 지정"
    }

    private var statusMessage: String? {
        if isRecording { return "지정할 조합을 눌러 주세요. Esc를 누르면 취소돼요." }
        guard let status else { return shortcut == nil ? "지정된 조합이 없어요." : nil }
        switch status {
        case .active: return "다른 앱을 쓰는 중에도 이 조합으로 실행돼요."
        case .unavailable: return "다른 앱이 사용 중이라 지금은 작동하지 않아요."
        case .rejected(let rejection): return rejection.message
        }
    }

    private var statusIsWarning: Bool {
        guard !isRecording, let status else { return false }
        switch status {
        case .active: return false
        case .unavailable, .rejected: return true
        }
    }
}

private struct GlobalShortcutKeyCapture: NSViewRepresentable {
    let isRecording: Bool
    let onBegin: () -> Void
    let onRecord: (GlobalShortcut) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> GlobalShortcutCaptureView {
        let view = GlobalShortcutCaptureView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: GlobalShortcutCaptureView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: GlobalShortcutCaptureView) {
        view.onBegin = onBegin
        view.onRecord = onRecord
        view.onCancel = onCancel
        view.isRecording = isRecording
    }
}

/// Captures one combination only while recording in the focused settings window.
/// It never installs an app-wide or system-wide key monitor.
final class GlobalShortcutCaptureView: NSView {
    var isRecording = false
    var onBegin: () -> Void = {}
    var onRecord: (GlobalShortcut) -> Void = { _ in }
    var onCancel: () -> Void = {}

    override var acceptsFirstResponder: Bool { true }

    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
    }

    override func mouseDown(with event: NSEvent) {
        guard window?.makeFirstResponder(self) == true else { return }
        beginRecording()
    }

    override func keyDown(with event: NSEvent) {
        if isRecording {
            capture(event)
        } else if !event.isARepeat,
                  event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                  event.charactersIgnoringModifiers == " " || event.charactersIgnoringModifiers == "\r" {
            beginRecording()
        } else {
            super.keyDown(with: event)
        }
    }

    // Command and Control combinations arrive here before keyDown and before the menu.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown, window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        capture(event)
        return true
    }

    override func resignFirstResponder() -> Bool {
        cancelRecording()
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if let window {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didResignKeyNotification,
                object: window
            )
        }
        if newWindow == nil {
            cancelRecording()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        cancelRecording()
    }

    private func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        onBegin()
    }

    private func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        onCancel()
    }

    private func capture(_ event: NSEvent) {
        isRecording = false
        guard UInt32(event.keyCode) != GlobalShortcut.escapeKeyCode else {
            onCancel()
            return
        }
        onRecord(GlobalShortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: GlobalShortcutModifiers(event.modifierFlags)
        ))
    }
}
