import SwiftUI

@MainActor
struct SettingsActions {
    var onOverlayVisibilityChanged: (Bool) -> Void
    var onOverlayRegionChanged: (OverlayRegionPreference) -> Void
    var onShowOfflineMembersChanged: (Bool) -> Void
    var onQuietModeChanged: (Bool) -> Void
    var onLaunchAtLoginChanged: (Bool) -> Void
    var onCheckForUpdates: () -> Void
    var canCheckForUpdates: () -> Bool
    var onSaveProfile: () -> Void
    var onCreateRoom: () -> Void
    var onJoinRoom: () -> Void
    var onSelectRoom: (UUID) -> Void
    var onCopyInviteCode: (UUID) -> Void
    var onRenameRoom: (UUID, String) -> Void
    var onRemoveRoomMember: (UUID, UUID) -> Void
    var onDeleteRoom: (UUID) -> Void

    static let empty = SettingsActions(
        onOverlayVisibilityChanged: { _ in },
        onOverlayRegionChanged: { _ in },
        onShowOfflineMembersChanged: { _ in },
        onQuietModeChanged: { _ in },
        onLaunchAtLoginChanged: { _ in },
        onCheckForUpdates: {},
        canCheckForUpdates: { false },
        onSaveProfile: {},
        onCreateRoom: {},
        onJoinRoom: {},
        onSelectRoom: { _ in },
        onCopyInviteCode: { _ in },
        onRenameRoom: { _, _ in },
        onRemoveRoomMember: { _, _ in },
        onDeleteRoom: { _ in }
    )
}

struct SettingsRootView: View {
    @Bindable var model: AppModel
    let actions: SettingsActions

    var body: some View {
        Group {
            if model.preferences.onboardingComplete {
                settingsNavigation
            } else {
                OnboardingView(model: model, actions: actions)
            }
        }
        .animation(.snappy, value: model.preferences.onboardingComplete)
    }

    private var settingsNavigation: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $model.activeSettingsPage) { page in
                Label(page.title, systemImage: page.systemImage)
                    .tag(page)
                    .font(.body.weight(.medium))
                    .padding(.vertical, 8)
            }
            .navigationTitle("SIDEY")
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 280)
            .safeAreaInset(edge: .bottom) {
                ConnectionBadge(state: model.connectionState)
                    .padding(16)
            }
        } detail: {
            ScrollView {
                Group {
                    switch model.activeSettingsPage {
                    case .profile:
                        ProfileSettingsView(model: model, onSave: actions.onSaveProfile)
                    case .groups:
                        GroupsSettingsView(model: model, actions: actions)
                    case .app:
                        AppSettingsView(model: model, actions: actions)
                    }
                }
                .frame(maxWidth: 760, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 44)
                .padding(.vertical, 40)
            }
            .overlay(alignment: .bottom) {
                if let error = model.errorMessage {
                    ErrorBanner(message: error) { model.errorMessage = nil }
                        .padding(20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let success = model.successMessage {
                    SuccessBanner(message: success) { model.successMessage = nil }
                        .padding(20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(.background)
        .animation(.snappy, value: model.errorMessage)
    }
}

private struct OnboardingView: View {
    @Bindable var model: AppModel
    let actions: SettingsActions
    @State private var groupPath: GroupPath = .create

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.mint.opacity(0.16), Color.cyan.opacity(0.08), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                HStack(spacing: 8) {
                    stepBadge(number: 1, title: "프로필", complete: model.hasProfile)
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    stepBadge(number: 2, title: "그룹", complete: model.preferences.onboardingComplete)
                }

                VStack(spacing: 8) {
                    Text(model.hasProfile ? "친구와 연결하기" : "SIDEY에서 쓸 이름 정하기")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(model.hasProfile
                         ? "그룹을 만들거나 받은 초대 코드로 참여하면 픽셀 월드가 나타남"
                         : "나중에 설정에서 언제든 바꿀 수 있음")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Group {
                    if model.hasProfile {
                        groupStep
                    } else {
                        profileStep
                    }
                }
                .padding(26)
                .frame(width: 620, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .glassEffect(in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                ConnectionBadge(state: model.connectionState)
                    .frame(width: 260)
            }
            .padding(48)

            if let error = model.errorMessage {
                ErrorBanner(message: error) { model.errorMessage = nil }
                    .padding(20)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            } else if let success = model.successMessage {
                SuccessBanner(message: success) { model.successMessage = nil }
                    .padding(20)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    private var profileStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("내 캐릭터")
                .font(.title2.bold())
            CharacterSelectionGrid(
                maximumColumns: 3,
                selection: $model.selectedCharacterID
            )
            TextField("닉네임 2~8자", text: $model.nickname)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .onChange(of: model.nickname) { _, value in
                    let limited = ProfileValidator.limitedNicknameDraft(value)
                    if limited != value { model.nickname = limited }
                }
            HStack {
                Text("같은 그룹에서 캐릭터와 닉네임이 겹쳐도 괜찮음")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("다음", action: actions.onSaveProfile)
                    .buttonStyle(.glassProminent)
                    .disabled(model.isWorking || !validNickname)
            }
        }
    }

    private var groupStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Picker("그룹 연결 방식", selection: $groupPath) {
                ForEach(GroupPath.allCases) { path in
                    Text(path.title).tag(path)
                }
            }
            .pickerStyle(.segmented)

            if groupPath == .create {
                TextField("새 그룹 이름", text: $model.newRoomName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Text("직접 그룹 만들기").foregroundStyle(.secondary)
                    Spacer()
                    Button("그룹 만들기", action: actions.onCreateRoom)
                        .buttonStyle(.glassProminent)
                        .disabled(model.isWorking || !validRoomName)
                }
            } else {
                TextField("친구에게 받은 초대 코드", text: $model.inviteCode)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: model.inviteCode) { _, value in
                        let uppercased = value.uppercased()
                        if value != uppercased { model.inviteCode = uppercased }
                    }
                HStack {
                    Text("그룹당 최대 5명").foregroundStyle(.secondary)
                    Spacer()
                    Button("코드로 참여", action: actions.onJoinRoom)
                        .buttonStyle(.glassProminent)
                        .disabled(model.isWorking || model.inviteCode.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func stepBadge(number: Int, title: String, complete: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: complete ? "checkmark.circle.fill" : "\(number).circle.fill")
            Text(title)
        }
        .font(.headline)
        .foregroundStyle(complete ? .mint : .primary)
    }

    private var validNickname: Bool {
        ProfileValidator.isValidNickname(model.nickname)
    }

    private var validRoomName: Bool {
        RoomNameValidator.isValid(model.newRoomName)
    }

    private enum GroupPath: String, CaseIterable, Identifiable {
        case create
        case join

        var id: String { rawValue }
        var title: String { self == .create ? "새 그룹 만들기" : "초대 코드 참여" }
    }
}

private struct ProfileSettingsView: View {
    @Bindable var model: AppModel
    let onSave: () -> Void

    var body: some View {
        SettingsSection(
            title: "내 프로필",
            subtitle: "친구들에게 보이는 이름과 캐릭터를 설정함",
            systemImage: "person.crop.circle"
        ) {
            SettingsControlRow(
                title: "닉네임",
                description: "친구들의 픽셀 월드와 메시지에 표시되는 이름 · 2~8자"
            ) {
                TextField("2~8자", text: $model.nickname)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .onChange(of: model.nickname) { _, value in
                        let limited = ProfileValidator.limitedNicknameDraft(value)
                        if limited != value { model.nickname = limited }
                    }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("캐릭터")
                    .font(.headline)
                Text("친구 화면에서 나를 나타낼 픽셀 동물을 선택함")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            CharacterSelectionGrid(
                maximumColumns: 5,
                selection: $model.selectedCharacterID
            )
            Text("캐릭터와 닉네임은 그룹 안에서 중복 선택 가능")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("프로필 저장", action: onSave)
                    .buttonStyle(.glassProminent)
                    .disabled(model.isWorking || !validNickname)
            }
        }

        if !model.preferences.onboardingComplete {
            Label("프로필 저장 후 그룹을 만들거나 초대 코드로 참여하면 준비 완료", systemImage: "sparkles")
                .foregroundStyle(.secondary)
                .padding(.top, 18)
        }
    }

    private var validNickname: Bool {
        ProfileValidator.isValidNickname(model.nickname)
    }
}

private struct GroupsSettingsView: View {
    @Bindable var model: AppModel
    let actions: SettingsActions

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            SettingsSection(
                title: "현재 그룹",
                subtitle: "함께 표시할 친구와 활성 그룹을 관리함 · 그룹당 최대 5명",
                systemImage: "person.3"
            ) {
                if model.rooms.isEmpty {
                    ContentUnavailableView(
                        "아직 연결된 그룹 없음",
                        systemImage: "person.3",
                        description: Text("새 그룹을 만들거나 친구의 초대 코드를 입력해줘")
                    )
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    ForEach(model.rooms) { room in
                        RoomRow(
                            room: room,
                            currentUserID: model.currentUserID,
                            isActive: room.id == model.activeRoom?.id,
                            isWorking: model.isWorking,
                            onSelect: { actions.onSelectRoom(room.id) },
                            onCopyInviteCode: { actions.onCopyInviteCode(room.id) },
                            onRename: { name in actions.onRenameRoom(room.id, name) },
                            onRemoveMember: { userID in
                                actions.onRemoveRoomMember(room.id, userID)
                            },
                            onDelete: { actions.onDeleteRoom(room.id) }
                        )
                        if room.id != model.rooms.last?.id { Divider() }
                    }
                }
            }

            SettingsSection(
                title: "새 그룹 만들기",
                subtitle: "새 공간을 만들고 생성된 초대 코드를 친구에게 공유함",
                systemImage: "plus.circle"
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("그룹 이름")
                        .font(.headline)
                    Text("1~20자의 이름을 입력해 새로운 비공개 그룹을 만듦")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    TextField("새 그룹 이름", text: $model.newRoomName)
                        .textFieldStyle(.roundedBorder)
                    Button("그룹 만들기", action: actions.onCreateRoom)
                        .buttonStyle(.glassProminent)
                        .disabled(model.isWorking || !validRoomName || !validNickname)
                }

                if let invite = model.lastCreatedInviteCode {
                    Divider()
                    SettingsControlRow(
                        title: "방금 만든 그룹의 초대 코드",
                        description: "이 코드를 전달받은 친구만 그룹에 참여할 수 있음"
                    ) {
                        Text(invite)
                            .font(.system(.body, design: .monospaced).bold())
                            .textSelection(.enabled)
                    }
                }
            }

            SettingsSection(
                title: "초대 코드로 참여",
                subtitle: "친구에게 받은 코드를 입력해 기존 비공개 그룹에 들어감",
                systemImage: "ticket"
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("초대 코드")
                        .font(.headline)
                    Text("공백을 제외한 초대 코드를 입력하면 서버에서 멤버십과 인원 제한을 확인함")
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
                    Button("코드로 참여", action: actions.onJoinRoom)
                        .buttonStyle(.glassProminent)
                        .disabled(model.isWorking || model.inviteCode.trimmingCharacters(in: .whitespaces).isEmpty || !validNickname)
                }
            }
        }
    }

    private var validNickname: Bool {
        model.nickname.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    private var validRoomName: Bool {
        RoomNameValidator.isValid(model.newRoomName)
    }
}

private struct RoomRow: View {
    let room: Room
    let currentUserID: UUID?
    let isActive: Bool
    let isWorking: Bool
    let onSelect: () -> Void
    let onCopyInviteCode: () -> Void
    let onRename: (String) -> Void
    let onRemoveMember: (UUID) -> Void
    let onDelete: () -> Void

    @State private var isExpanded = false
    @State private var isRenaming = false
    @State private var renameDraft = ""
    @State private var removalCandidate: RoomMember?
    @State private var showsDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            roomHeader
            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
        .onChange(of: room.name) { _, newName in
            if !isRenaming { renameDraft = newName }
        }
        .alert(
            removalCandidate.map { "‘\($0.nickname)’님을 내보낼까?" } ?? "멤버 내보내기",
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
            Text("이 멤버는 그룹과 기존 메시지에 접근할 수 없게 됨.")
        }
        .alert("‘\(room.name)’ 그룹을 삭제할까?", isPresented: $showsDeleteConfirmation) {
            Button("취소", role: .cancel) {}
            Button("그룹 삭제", role: .destructive, action: onDelete)
        } message: {
            Text("멤버와 모든 메시지가 영구 삭제되며 복구할 수 없음.")
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if room.members.isEmpty {
                Text("표시할 멤버 없음")
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
        }
        .padding(.top, 12)
        .padding(.leading, 8)
    }

    private var roomHeader: some View {
        HStack(spacing: 10) {
            Button(action: toggleExpansion) {
                HStack(spacing: 14) {
                    Image(systemName: isActive ? "person.3.fill" : "person.3")
                        .font(.title2)
                        .foregroundStyle(isActive ? .mint : .secondary)
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(room.name).font(.headline)
                        Text("\(room.members.count)/5명 · 초대 코드 \(room.inviteCodeHint)")
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

            if !isActive {
                Button("그룹 참가", action: onSelect)
                    .disabled(isWorking)
            }
            Button(action: onCopyInviteCode) {
                Label("초대 코드 복사", systemImage: "doc.on.doc")
            }
            .disabled(isWorking)
            .help("이 기기의 Keychain에 보관된 초대 코드 복사")

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
            .disabled(isWorking)
            Button("그룹 삭제", systemImage: "trash", role: .destructive) {
                showsDeleteConfirmation = true
            }
            .disabled(isWorking)
        }
        .padding(.leading, 48)
    }

    private func toggleExpansion() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isExpanded.toggle()
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
            .disabled(isWorking || !RoomNameValidator.isValid(renameDraft))
            Button("취소") {
                renameDraft = room.name
                isRenaming = false
            }
            .disabled(isWorking)
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
                .disabled(isWorking)
            }
        }
        .padding(.leading, 48)
    }
}

private struct AppSettingsView: View {
    @Bindable var model: AppModel
    let actions: SettingsActions

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            SettingsSection(
                title: "일반",
                subtitle: "SIDEY의 기본 표시와 실행 방식을 설정함",
                systemImage: "gearshape"
            ) {
                SettingsToggleRow(
                    title: "픽셀 월드 표시",
                    description: "선택한 화면 가장자리에 친구들의 픽셀 월드를 표시함",
                    isOn: Binding(
                        get: { model.overlayVisible },
                        set: { actions.onOverlayVisibilityChanged($0) }
                    )
                )
                Divider()
                SettingsToggleRow(
                    title: "로그인 시 자동 실행",
                    description: "Mac에 로그인하면 SIDEY를 자동으로 시작함",
                    isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { actions.onLaunchAtLoginChanged($0) }
                    )
                )
            }

            SettingsSection(
                title: "표시",
                subtitle: "친구 상태와 메시지가 화면에 나타나는 방식을 조절함",
                systemImage: "eye"
            ) {
                SettingsToggleRow(
                    title: "조용히 모드",
                    description: "메시지 본문 말풍선은 숨기고 타이핑 상태와 미확인 수는 유지함",
                    isOn: Binding(
                        get: { model.preferences.quietModeEnabled },
                        set: { actions.onQuietModeChanged($0) }
                    )
                )
                Divider()
                SettingsToggleRow(
                    title: "오프라인 멤버 표시",
                    description: "접속하지 않은 친구도 잠든 캐릭터와 빨간 상태 점으로 남겨둠",
                    isOn: Binding(
                        get: { model.preferences.showOfflineMembers },
                        set: { actions.onShowOfflineMembersChanged($0) }
                    )
                )
            }

            SettingsSection(
                title: "업데이트",
                subtitle: "서명된 공식 배포 채널에서 새로운 SIDEY 버전을 확인함",
                systemImage: "arrow.triangle.2.circlepath"
            ) {
                SettingsControlRow(
                    title: "업데이트 확인",
                    description: "Sparkle이 현재 버전보다 새로운 공증 업데이트가 있는지 확인함"
                ) {
                    Button("지금 확인", action: actions.onCheckForUpdates)
                        .buttonStyle(.glassProminent)
                        .disabled(!actions.canCheckForUpdates())
                }
            }

            SettingsSection(
                title: "월드 배치",
                subtitle: "픽셀 월드를 표시할 모니터와 화면 가장자리 영역을 선택함",
                systemImage: "rectangle.inset.filled"
            ) {
                SettingsControlRow(
                    title: "가장자리",
                    description: "캐릭터가 걸어 다닐 화면 방향"
                ) {
                    Picker("가장자리", selection: regionEdgeBinding) {
                        ForEach(OverlayEdge.allCases) { edge in
                            Text(edge.title).tag(edge)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
                Divider()
                SettingsControlRow(
                    title: "영역 길이",
                    description: "선택한 가장자리에서 월드가 차지할 범위"
                ) {
                    Picker("길이", selection: regionSpanBinding) {
                        ForEach(OverlaySpan.allCases) { span in
                            Text(span.title).tag(span)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
                Divider()
                SettingsControlRow(
                    title: "모니터",
                    description: "픽셀 월드와 메시지 입력창을 표시할 화면"
                ) {
                    Picker("모니터", selection: regionScreenBinding) {
                        ForEach(model.availableScreens) { screen in
                            Text(screen.name).tag(Optional(screen.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 240)
                }
            }

            SettingsSection(
                title: "동작 정보",
                subtitle: "현재 적용되는 창과 렌더링 정책",
                systemImage: "info.circle"
            ) {
                SettingsControlRow(
                    title: "설정 창",
                    description: "다른 일반 앱 창과 동일한 레벨에서 열림"
                ) {
                    Text("일반 macOS 창")
                        .foregroundStyle(.secondary)
                }
                Divider()
                SettingsControlRow(
                    title: "픽셀 월드",
                    description: "기본 모드에서 뒤 앱의 포인터 입력을 방해하지 않음"
                ) {
                    Text("항상 위 · 클릭 통과 · 30 FPS")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var regionEdgeBinding: Binding<OverlayEdge> {
        Binding(
            get: { model.preferences.overlayRegion.edge },
            set: { edge in
                var preference = model.preferences.overlayRegion
                preference.edge = edge
                actions.onOverlayRegionChanged(preference)
            }
        )
    }

    private var regionSpanBinding: Binding<OverlaySpan> {
        Binding(
            get: { model.preferences.overlayRegion.span },
            set: { span in
                var preference = model.preferences.overlayRegion
                preference.span = span
                actions.onOverlayRegionChanged(preference)
            }
        )
    }

    private var regionScreenBinding: Binding<String?> {
        Binding(
            get: { model.preferences.overlayRegion.screenIdentifier },
            set: { screenIdentifier in
                var preference = model.preferences.overlayRegion
                preference.screenIdentifier = screenIdentifier
                actions.onOverlayRegionChanged(preference)
            }
        )
    }
}

private struct ConnectionBadge: View {
    let state: BackendConnectionState

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(state.label).font(.caption.weight(.medium))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .clipShape(Capsule())
        .glassEffect(in: Capsule())
    }

    private var color: Color {
        switch state {
        case .online: .green
        case .connecting: .orange
        case .idle: .gray
        case .failed: .red
        }
    }
}

private struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).lineLimit(3)
            Spacer()
            Button(action: onDismiss) { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: 620)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SuccessBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(message).lineLimit(2)
            Spacer()
            Button(action: onDismiss) { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: 620)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String?
    let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.title2.bold())
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 18) { content }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    .thinMaterial,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.primary.opacity(0.06), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.035), radius: 12, y: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            SettingsRowLabel(title: title, description: description)
            Spacer(minLength: 16)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.large)
                .tint(.accentColor)
        }
        .contentShape(Rectangle())
    }
}

private struct SettingsControlRow<Control: View>: View {
    let title: String
    let description: String
    let control: Control

    init(
        title: String,
        description: String,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.description = description
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            SettingsRowLabel(title: title, description: description)
            Spacer(minLength: 16)
            control
        }
    }
}

private struct SettingsRowLabel: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
