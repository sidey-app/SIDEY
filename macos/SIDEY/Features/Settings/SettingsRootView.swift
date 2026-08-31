import SwiftUI

@MainActor
struct SettingsActions {
    var onOverlayVisibilityChanged: (Bool) -> Void
    var onOverlayRegionChanged: (OverlayRegionPreference) -> Void
    var onShowOfflineMembersChanged: (Bool) -> Void
    var onQuietModeChanged: (Bool) -> Void
    var onLaunchAtLoginChanged: (Bool) -> Void
    var onSaveProfile: () -> Void
    var onCreateRoom: () -> Void
    var onJoinRoom: () -> Void
    var onSelectRoom: (UUID) -> Void
    var onCopyInviteCode: (UUID) -> Void

    static let empty = SettingsActions(
        onOverlayVisibilityChanged: { _ in },
        onOverlayRegionChanged: { _ in },
        onShowOfflineMembersChanged: { _ in },
        onQuietModeChanged: { _ in },
        onLaunchAtLoginChanged: { _ in },
        onSaveProfile: {},
        onCreateRoom: {},
        onJoinRoom: {},
        onSelectRoom: { _ in },
        onCopyInviteCode: { _ in }
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
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(36)
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
            TextField("닉네임 2~12자", text: $model.nickname)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
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
        let value = model.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.count >= 2 && value.count <= 12 && value.rangeOfCharacter(from: .newlines) == nil
    }

    private var validRoomName: Bool {
        let value = model.newRoomName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && value.count <= 20 && value.rangeOfCharacter(from: .newlines) == nil
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
        SettingsSection(title: "내 프로필", subtitle: "친구들에게 보이는 이름과 캐릭터") {
            LabeledContent("닉네임") {
                TextField("2~12자", text: $model.nickname)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 320)
            }
            Text("캐릭터")
                .font(.headline)
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
        let value = model.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.count >= 2 && value.count <= 12 && value.rangeOfCharacter(from: .newlines) == nil
    }
}

private struct GroupsSettingsView: View {
    @Bindable var model: AppModel
    let actions: SettingsActions

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            SettingsSection(title: "그룹", subtitle: "그룹당 최대 5명 · 사용자당 최대 5개") {
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
                            isActive: room.id == model.activeRoom?.id,
                            onSelect: { actions.onSelectRoom(room.id) },
                            onCopyInviteCode: { actions.onCopyInviteCode(room.id) }
                        )
                        if room.id != model.rooms.last?.id { Divider() }
                    }
                }
            }

            SettingsSection(title: "그룹 추가", subtitle: "서버에서 멤버십과 인원 제한을 다시 검증함") {
                HStack {
                    TextField("새 그룹 이름", text: $model.newRoomName)
                        .textFieldStyle(.roundedBorder)
                    Button("만들기", action: actions.onCreateRoom)
                        .buttonStyle(.glassProminent)
                        .disabled(model.isWorking || !validRoomName || !validNickname)
                }
                HStack {
                    TextField("초대 코드", text: $model.inviteCode)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: model.inviteCode) { _, value in
                            let uppercased = value.uppercased()
                            if value != uppercased { model.inviteCode = uppercased }
                        }
                    Button("참여", action: actions.onJoinRoom)
                        .disabled(model.isWorking || model.inviteCode.trimmingCharacters(in: .whitespaces).isEmpty || !validNickname)
                }
                if let invite = model.lastCreatedInviteCode {
                    LabeledContent("방금 만든 그룹의 초대 코드") {
                        Text(invite)
                            .font(.system(.body, design: .monospaced).bold())
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var validNickname: Bool {
        model.nickname.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    private var validRoomName: Bool {
        let value = model.newRoomName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && value.count <= 20 && value.rangeOfCharacter(from: .newlines) == nil
    }
}

private struct RoomRow: View {
    let room: Room
    let isActive: Bool
    let onSelect: () -> Void
    let onCopyInviteCode: () -> Void

    var body: some View {
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
            } else {
                Button("이 그룹 보기", action: onSelect)
            }
            Button(action: onCopyInviteCode) {
                Label("초대 코드 복사", systemImage: "doc.on.doc")
            }
            .help("이 기기의 Keychain에 보관된 초대 코드 복사")
        }
        .padding(.vertical, 4)
    }
}

private struct AppSettingsView: View {
    @Bindable var model: AppModel
    let actions: SettingsActions

    var body: some View {
        SettingsSection(title: "앱 설정", subtitle: "픽셀 월드 영역과 시작 동작") {
            Toggle("픽셀 월드 표시", isOn: Binding(
                get: { model.overlayVisible },
                set: { actions.onOverlayVisibilityChanged($0) }
            ))
            Toggle("로그인 시 자동 실행", isOn: Binding(
                get: { model.launchAtLogin },
                set: { actions.onLaunchAtLoginChanged($0) }
            ))
            Toggle("조용히 모드", isOn: Binding(
                get: { model.preferences.quietModeEnabled },
                set: { actions.onQuietModeChanged($0) }
            ))
            Toggle("오프라인 멤버 표시", isOn: Binding(
                get: { model.preferences.showOfflineMembers },
                set: { actions.onShowOfflineMembersChanged($0) }
            ))
            LabeledContent("가장자리") {
                Picker("가장자리", selection: regionEdgeBinding) {
                    ForEach(OverlayEdge.allCases) { edge in
                        Text(edge.title).tag(edge)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }
            LabeledContent("길이") {
                Picker("길이", selection: regionSpanBinding) {
                    ForEach(OverlaySpan.allCases) { span in
                        Text(span.title).tag(span)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }
            LabeledContent("모니터") {
                Picker("모니터", selection: regionScreenBinding) {
                    ForEach(model.availableScreens) { screen in
                        Text(screen.name).tag(Optional(screen.id))
                    }
                }
                .labelsHidden()
                .frame(width: 240)
            }
            LabeledContent("설정 창 동작") {
                Text("일반 macOS 창").foregroundStyle(.secondary)
            }
            LabeledContent("월드 동작") {
                Text("항상 위 · 클릭 통과 · 30 FPS").foregroundStyle(.secondary)
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
    @ViewBuilder let content: Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 18) { content }
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title2.bold())
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .groupBoxStyle(.automatic)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
