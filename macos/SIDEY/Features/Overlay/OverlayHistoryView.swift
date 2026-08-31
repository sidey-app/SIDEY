import SwiftUI

struct OverlayHistoryView: View {
    @Bindable var model: AppModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label("최근 메시지", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                    Text("메시지는 서버에서 \(ProductLimits.messageRetentionDays)일 후 자동 삭제됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("최근 메시지 닫기")
            }

            if entries.isEmpty {
                ContentUnavailableView(
                    "아직 메시지 없음",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("이 그룹의 최근 메시지가 여기에 표시됩니다.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                HStack(spacing: 6) {
                                    Text(entry.createdAt, style: .time)
                                    if entry.state == .pending {
                                        Label("전송 중", systemImage: "clock")
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            }
                            .padding(10)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 390, height: 270)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .glassEffect(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var entries: [MessageLedgerEntry] {
        guard let roomID = model.activeRoom?.id else { return [] }
        return Self.recentEntries(in: model.messageLedger, roomID: roomID)
    }

    static func recentEntries(in ledger: MessageLedger, roomID: UUID) -> [MessageLedgerEntry] {
        Array(ledger.entries.filter { $0.roomID == roomID }.suffix(20).reversed())
    }
}
