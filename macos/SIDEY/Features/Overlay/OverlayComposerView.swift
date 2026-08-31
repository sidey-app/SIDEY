import SwiftUI

struct OverlayComposerView: View {
    @Bindable var model: AppModel
    let onSend: (String) -> Void
    let onInputActivity: () -> Void
    let onTypingChanged: (Bool) -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                if model.draft.isEmpty {
                    Text("짧은 메시지").foregroundStyle(.tertiary)
                }
                NativeMessageField(
                    text: $model.draft,
                    onInputActivity: onInputActivity,
                    onSubmit: send,
                    onCancel: onCancel
                )
            }
            .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 40)
            .onChange(of: model.draft) { _, value in
                onTypingChanged(!MessageValidator.normalized(value).isEmpty)
            }

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(!MessageValidator.isValid(MessageValidator.normalized(model.draft)))
            .accessibilityLabel("메시지 전송")
        }
        .font(.system(size: 16, weight: .medium))
        .padding(.horizontal, 14)
        .frame(width: 390, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .glassEffect(in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .padding(5)
    }

    private func send() {
        guard let body = model.acceptDraft() else { return }
        onTypingChanged(false)
        onSend(body)
    }
}
