import SwiftUI

struct GroupsSettingsView: View {
    @Bindable var model: AppModel
    let actions: SettingsActions

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            SettingsSection(
                title: "현재 그룹",
                subtitle: "함께 표시할 친구와 활성 그룹을 관리할 수 있습니다. 그룹당 최대 \(ProductLimits.maximumRoomMembers)명까지 참여할 수 있습니다.",
                systemImage: "person.2"
            ) {
                if model.rooms.isEmpty {
                    ContentUnavailableView(
                        "아직 연결된 그룹 없음",
                        systemImage: "person.2",
                        description: Text("새 그룹을 만들거나 친구에게 받은 초대 코드를 입력해 주세요.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    ForEach(model.rooms) { room in
                        RoomRow(
                            room: room,
                            currentUserID: model.currentUserID,
                            isActive: room.id == model.activeRoom?.id,
                            mutationsDisabled: model.groupMutationsDisabled,
                            selectionDisabled: model.isWorking || !model.groupOperation.allowsRoomSelection,
                            isSwitchingTarget: model.groupOperation.isSwitching(to: room.id),
                            onSelect: { actions.onSelectRoom(room.id) },
                            onCopyInviteCode: { await actions.onCopyInviteCode(room.id) },
                            onRotateInviteCode: { actions.onRotateInviteCode(room.id) },
                            onRename: { name in actions.onRenameRoom(room.id, name) },
                            onRemoveMember: { userID in
                                actions.onRemoveRoomMember(room.id, userID)
                            },
                            onLeave: { actions.onLeaveRoom(room.id) },
                            onDelete: { actions.onDeleteRoom(room.id) }
                        )
                        if room.id != model.rooms.last?.id { Divider() }
                    }
                }
            }

            SettingsSection(
                title: "새 그룹 만들기",
                subtitle: "새 공간을 만들고 생성된 초대 코드를 친구에게 공유할 수 있습니다.",
                systemImage: "plus.circle"
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("그룹 이름")
                        .font(.headline)
                    Text("1~20자의 이름을 입력해 새로운 비공개 그룹을 만들 수 있습니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    TextField("새 그룹 이름", text: $model.newRoomName)
                        .textFieldStyle(.roundedBorder)
                    Button(action: actions.onCreateRoom) {
                        OperationButtonLabel(
                            title: model.groupOperation.createButtonTitle,
                            showsProgress: model.groupOperation == .creating
                        )
                    }
                        .buttonStyle(.glassProminent)
                        .disabled(model.groupMutationsDisabled || !validRoomName || !validNickname)
                }

                if let invite = model.lastCreatedInviteCode {
                    Divider()
                    SettingsControlRow(
                        title: "방금 발급한 초대 코드",
                        description: "이 코드를 전달받은 친구만 그룹에 참여할 수 있습니다."
                    ) {
                        Text(invite)
                            .font(.system(.body, design: .monospaced).bold())
                            .textSelection(.enabled)
                    }
                }
            }

            SettingsSection(
                title: "초대 코드로 참여",
                subtitle: "친구에게 받은 코드를 입력해 기존 비공개 그룹에 참여할 수 있습니다.",
                systemImage: "ticket"
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("초대 코드")
                        .font(.headline)
                    Text("초대 코드를 입력하면 서버에서 멤버십과 인원 제한을 확인합니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    TextField("초대 코드", text: $model.inviteCode)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: model.inviteCode) { _, value in
                            let uppercased = value.uppercased()
                            if value != uppercased { model.inviteCode = uppercased }
                        }
                    Button(action: actions.onJoinRoom) {
                        OperationButtonLabel(
                            title: model.groupOperation.joinButtonTitle,
                            showsProgress: model.groupOperation == .joining
                        )
                    }
                        .buttonStyle(.glassProminent)
                        .disabled(model.groupMutationsDisabled || model.inviteCode.trimmingCharacters(in: .whitespaces).isEmpty || !validNickname)
                }
            }
        }
    }

    private var validNickname: Bool {
        model.confirmedNickname.map(ProfileValidator.isValidNickname)
            ?? ProfileValidator.isValidNickname(model.nickname)
    }

    private var validRoomName: Bool {
        RoomNameValidator.isValid(model.newRoomName)
    }
}
struct RoomRow: View {
    let room: Room
    let currentUserID: UUID?
    let isActive: Bool
    let mutationsDisabled: Bool
    let selectionDisabled: Bool
    let isSwitchingTarget: Bool
    let onSelect: () -> Void
    let onCopyInviteCode: () async -> Bool
    let onRotateInviteCode: () -> Void
    let onRename: (String) -> Void
    let onRemoveMember: (UUID) -> Void
    let onLeave: () -> Void
    let onDelete: () -> Void

    @State private var isExpanded = false
    @State private var isRenaming = false
    @State private var renameDraft = ""
    @State private var removalCandidate: RoomMember?
    @State private var showsDeleteConfirmation = false
    @State private var showsLeaveConfirmation = false
    @State private var inviteCopyFeedback = InviteCopyFeedbackState()
    @State private var inviteCopyTask: Task<Void, Never>?
    @State private var inviteCopyResetTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            roomHeader
            VStack(alignment: .leading, spacing: 0) {
                if isExpanded {
                    expandedContent
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .clipped()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            isSwitchingTarget ? Color.accentColor.opacity(0.10) : .clear,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isSwitchingTarget ? Color.accentColor.opacity(0.55) : .clear,
                    lineWidth: 1
                )
        }
        .onChange(of: room.name) { _, newName in
            if !isRenaming { renameDraft = newName }
        }
        .onDisappear {
            inviteCopyTask?.cancel()
            inviteCopyResetTask?.cancel()
            inviteCopyFeedback.cancel()
        }
        .alert(
            removalCandidate.map { "‘\($0.nickname)’님을 내보낼까요?" } ?? "멤버 내보내기",
            isPresented: Binding(
                get: { removalCandidate != nil },
                set: { if !$0 { removalCandidate = nil } }
            )
        ) {
            Button("취소", role: .cancel) { removalCandidate = nil }
            Button("내보내기", role: .destructive) {
                guard let candidate = removalCandidate else { return }
                removalCandidate = nil
                onRemoveMember(candidate.userID)
            }
        } message: {
            Text("이 멤버는 그룹과 기존 메시지에 접근할 수 없게 됩니다.")
        }
        .alert("‘\(room.name)’ 그룹을 삭제할까요?", isPresented: $showsDeleteConfirmation) {
            Button("취소", role: .cancel) {}
            Button("그룹 삭제", role: .destructive, action: onDelete)
        } message: {
            Text("멤버와 모든 메시지가 영구 삭제되며 복구할 수 없습니다.")
        }
        .alert("‘\(room.name)’ 그룹에서 나갈까요?", isPresented: $showsLeaveConfirmation) {
            Button("취소", role: .cancel) {}
            Button("그룹 나가기", role: .destructive, action: onLeave)
        } message: {
            Text(RoomLeaveConfirmation.resolve(
                room: room,
                currentUserID: currentUserID
            ).message)
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if room.members.isEmpty {
                Text("표시할 멤버가 없습니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 48)
            } else {
                ForEach(room.members) { member in
                    memberRow(member)
                }
            }

            if RoomManagementPolicy.canManage(room, currentUserID: currentUserID) {
                Divider()
                    .padding(.leading, 48)
                if isRenaming {
                    renameEditor
                } else {
                    managementButtons
                }
            }
            Divider()
                .padding(.leading, 48)
            Button("그룹 나가기", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                showsLeaveConfirmation = true
            }
            .disabled(mutationsDisabled)
            .padding(.leading, 48)
        }
        .padding(.top, 12)
        .padding(.leading, 8)
    }

    private var roomHeader: some View {
        HStack(spacing: 10) {
            Button(action: toggleExpansion) {
                HStack(spacing: 14) {
                    Image(systemName: isActive ? "person.2.fill" : "person.2")
                        .font(.title2)
                        .foregroundStyle(isActive ? .mint : .secondary)
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(room.name).font(.headline)
                        Text(room.inviteCodeReady
                             ? "\(room.members.count)/\(ProductLimits.maximumRoomMembers)명 · 초대 코드 \(room.inviteCodeHint)"
                             : "\(room.members.count)/\(ProductLimits.maximumRoomMembers)명 · 초대 코드 재발급 필요")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isActive {
                        Label("활성", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.mint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isActive || isSwitchingTarget {
                Button(action: onSelect) {
                    OperationButtonLabel(
                        title: isSwitchingTarget ? "연결 중…" : "그룹 참가",
                        showsProgress: isSwitchingTarget
                    )
                }
                .disabled(selectionDisabled || isSwitchingTarget)
            }
            if !room.inviteCodeReady,
               RoomManagementPolicy.canManage(room, currentUserID: currentUserID) {
                Button("초대 코드 재발급", systemImage: "arrow.clockwise", action: onRotateInviteCode)
                    .disabled(mutationsDisabled)
                    .help("노출 위험이 있던 이전 코드를 폐기하고 새 128-bit 코드를 한 번 발급합니다.")
            } else {
                Button(action: copyInviteCode) {
                    Label(
                        inviteCopyFeedback.showsConfirmation ? "복사 완료" : "초대 코드 복사",
                        systemImage: inviteCopyFeedback.showsConfirmation
                            ? "checkmark.circle.fill"
                            : "doc.on.doc"
                    )
                    .foregroundStyle(inviteCopyFeedback.showsConfirmation ? .green : .primary)
                }
                .disabled(mutationsDisabled || !room.inviteCodeReady)
                .help("이 기기의 키체인에 보관된 초대 코드를 복사합니다.")
            }

            Button(action: toggleExpansion) {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "그룹 접기" : "그룹 펼치기")
            .accessibilityLabel(isExpanded ? "그룹 접기" : "그룹 펼치기")
        }
    }

    private var managementButtons: some View {
        HStack(spacing: 8) {
            Button("이름 변경", systemImage: "pencil") {
                renameDraft = room.name
                isRenaming = true
            }
            .disabled(mutationsDisabled)
            Button("그룹 삭제", systemImage: "trash", role: .destructive) {
                showsDeleteConfirmation = true
            }
            .disabled(mutationsDisabled)
        }
        .padding(.leading, 48)
    }

    private func toggleExpansion() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isExpanded.toggle()
        }
    }

    private func copyInviteCode() {
        inviteCopyTask?.cancel()
        inviteCopyTask = Task {
            let succeeded = await onCopyInviteCode()
            guard !Task.isCancelled,
                  let generation = inviteCopyFeedback.recordResult(succeeded)
            else { return }

            inviteCopyResetTask?.cancel()
            inviteCopyResetTask = Task {
                do {
                    try await Task.sleep(for: InviteCopyFeedbackState.confirmationDuration)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                inviteCopyFeedback.clear(generation: generation)
            }
        }
    }

    private var renameEditor: some View {
        HStack(spacing: 8) {
            TextField("그룹 이름 1~20자", text: $renameDraft)
                .textFieldStyle(.roundedBorder)
                .onChange(of: renameDraft) { _, value in
                    let limited = RoomNameValidator.limitedDraft(value)
                    if value != limited { renameDraft = limited }
                }
            Button("저장") {
                let value = renameDraft
                isRenaming = false
                onRename(value)
            }
            .buttonStyle(.borderedProminent)
            .disabled(mutationsDisabled || !RoomNameValidator.isValid(renameDraft))
            Button("취소") {
                renameDraft = room.name
                isRenaming = false
            }
            .disabled(mutationsDisabled)
        }
        .padding(.leading, 48)
    }

    @ViewBuilder
    private func memberRow(_ member: RoomMember) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: PixelCharacterPreviewImage.image(
                for: PixelCharacterCatalog.definition(for: member.characterID)
            ))
            .interpolation(.none)
            .resizable()
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            HStack(spacing: 6) {
                if RoomManagementPolicy.isOwner(member, in: room) {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(Color(red: 0.95, green: 0.68, blue: 0.12))
                        .accessibilityLabel("방장")
                }
                Text(member.nickname)
                if member.userID == currentUserID {
                    Text("나")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            Spacer()
            if RoomManagementPolicy.canRemove(
                member,
                from: room,
                currentUserID: currentUserID
            ) {
                Button("내보내기", role: .destructive) {
                    removalCandidate = member
                }
                .disabled(mutationsDisabled)
            }
        }
        .padding(.leading, 48)
    }
}

struct OperationButtonLabel: View {
    let title: String
    let showsProgress: Bool

    var body: some View {
        HStack(spacing: 7) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            }
            Text(title)
        }
    }
}
