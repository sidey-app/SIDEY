import SwiftUI

struct OverlayHistoryView: View {
    @Bindable var model: AppModel
    @Bindable var history: MessageHistoryStore
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Group {
                switch history.initialState {
                case .idle, .loading:
                    loadingView
                case .failed(let message):
                    initialFailureView(message: message)
                case .loaded where entries.isEmpty:
                    emptyView
                case .loaded:
                    messageList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.72))
        .onChange(of: model.realtimeActiveRoomID, initial: true) { _, roomID in
            history.roomDidChange(to: roomID)
        }
    }

    private var header: some View {
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
    }

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.large)
            Text("최근 메시지를 불러오는 중…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func initialFailureView(message: String) -> some View {
        ContentUnavailableView {
            Label("기록을 불러오지 못했어요", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
        } description: {
            Text(message)
        } actions: {
            Button("다시 시도") { history.retryInitial() }
        }
    }

    private var emptyView: some View {
        ContentUnavailableView(
            "아직 메시지 없음",
            systemImage: "bubble.left.and.bubble.right",
            description: Text("이 그룹의 최근 메시지가 여기에 표시됩니다.")
        )
    }

    private var messageList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(entries) { entry in
                    HistoryMessageCard(
                        entry: entry,
                        participant: participant(for: entry.senderID)
                    )
                }
                paginationFooter
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.visible)
    }

    @ViewBuilder
    private var paginationFooter: some View {
        switch history.olderState {
        case .idle:
            Color.clear
                .frame(height: 2)
                .onAppear { history.loadNextPage() }
                .accessibilityHidden(true)
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("이전 메시지를 불러오는 중…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        case .failed(let message):
            VStack(spacing: 6) {
                Text("이전 메시지를 불러오지 못했어요")
                    .font(.caption.weight(.semibold))
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button("다시 시도") { history.retryNextPage() }
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        case .exhausted:
            Text("최근 \(ProductLimits.messageRetentionDays)일 기록을 모두 봤어요")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
    }

    private var entries: [MessageLedgerEntry] {
        guard let roomID = history.roomID else { return [] }
        return MessageHistoryMerge.entries(
            pagedMessages: history.messages,
            ledger: model.messageLedger,
            outbox: model.messageOutbox,
            roomID: roomID
        )
    }

    private func participant(for senderID: UUID) -> MessageHistoryParticipant {
        let room = history.roomID.flatMap { roomID in
            model.rooms.first(where: { $0.id == roomID })
        }
        return MessageHistoryParticipantResolver.resolve(
            senderID: senderID,
            in: room,
            currentUserID: model.currentUserID
        )
    }
}

private struct HistoryMessageCard: View {
    let entry: MessageLedgerEntry
    let participant: MessageHistoryParticipant

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: PixelCharacterPreviewImage.image(
                for: PixelCharacterCatalog.definition(for: participant.characterID)
            ))
            .interpolation(.none)
            .resizable()
            .frame(width: 24, height: 24)
            .frame(width: 40, height: 40)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(participant.nickname)
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .lineLimit(1)
                    if participant.isCurrentUser {
                        Text("나")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                    Spacer(minLength: 8)
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(entry.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                deliveryStatus
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.14))
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var deliveryStatus: some View {
        switch entry.state {
        case .pending:
            Label("전송 중", systemImage: "clock")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .failed:
            Label("전송 실패", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        case .confirmed:
            EmptyView()
        }
    }
}
