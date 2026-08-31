import SwiftUI

struct OverlayComposerView: View {
    @Bindable var model: AppModel
    let onMoveBegan: () -> Void
    let onDrag: (CGSize) -> Void
    let onMoveEnded: () -> Void
    let onScaleChanged: (Double) -> Void
    let onSend: (String) -> Void
    let onTypingChanged: (Bool) -> Void
    let onToggleHistory: () -> Void
    let onOpenSettings: () -> Void
    let onOverlayModeChanged: (OverlayMode) -> Void
    @State private var isDragging = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                onOverlayModeChanged(model.overlayMode == .locked ? .editing : .locked)
            } label: {
                Image(systemName: model.overlayMode == .locked ? "lock.fill" : "lock.open.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.overlayMode == .locked ? "오버레이 잠금 해제" : "오버레이 잠금")

            if model.overlayMode == .editing {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                    onMoveBegan()
                                }
                                onDrag(value.translation)
                            }
                            .onEnded { value in
                                onDrag(value.translation)
                                isDragging = false
                                onMoveEnded()
                            }
                    )
                    .accessibilityLabel("아바타 이동")
            }

            ZStack(alignment: .leading) {
                if model.draft.isEmpty {
                    Text("짧은 메시지").foregroundStyle(.tertiary)
                }
                NativeMessageField(text: $model.draft, onSubmit: send)
            }
                .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 40)
                .onChange(of: model.draft) { _, value in
                    onTypingChanged(!MessageValidator.normalized(value).isEmpty)
                }

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(!MessageValidator.isValid(MessageValidator.normalized(model.draft)))

            if model.overlayMode == .editing {
                HStack(spacing: 5) {
                    Image(systemName: "textformat.size")
                        .foregroundStyle(.secondary)
                    Slider(value: $model.preferences.overlayScale, in: 1.5...2.0, step: 0.05)
                    .frame(width: 82)
                    .onChange(of: model.preferences.overlayScale) { _, value in
                        onScaleChanged(value)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("아바타 크기")

                Button(action: onToggleHistory) {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("최근 메시지")

                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("설정 열기")
            }
        }
        .font(.system(size: 16, weight: .medium))
        .padding(.horizontal, 14)
        .frame(width: model.overlayMode == .editing ? 570 : 390, height: 46)
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
