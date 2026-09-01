import SwiftUI

struct OnboardingView: View {
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
                         ? "그룹을 만들거나 받은 초대 코드로 참여하면 픽셀 월드가 나타납니다."
                         : "나중에 설정에서 언제든 바꿀 수 있습니다.")
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
                maximumColumns: 4,
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
                Text("같은 그룹에서 캐릭터와 닉네임이 겹쳐도 괜찮습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("다음") {
                    PendingTextInputCommitter.commitThen(actions.onSaveProfile)
                }
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
                    Text("새 비공개 그룹을 직접 만들 수 있습니다.").foregroundStyle(.secondary)
                    Spacer()
                    Button(action: actions.onCreateRoom) {
                        OperationButtonLabel(
                            title: model.groupOperation.createButtonTitle,
                            showsProgress: model.groupOperation == .creating
                        )
                    }
                        .buttonStyle(.glassProminent)
                        .disabled(model.groupMutationsDisabled || !validRoomName)
                }
            } else {
                TextField("친구에게 받은 초대 코드", text: $model.inviteCode)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: model.inviteCode) { _, value in
                        let uppercased = value.uppercased()
                        if value != uppercased { model.inviteCode = uppercased }
                    }
                HStack {
                    Text("그룹에는 최대 \(ProductLimits.maximumRoomMembers)명까지 참여할 수 있습니다.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: actions.onJoinRoom) {
                        OperationButtonLabel(
                            title: model.groupOperation.joinButtonTitle,
                            showsProgress: model.groupOperation == .joining
                        )
                    }
                        .buttonStyle(.glassProminent)
                        .disabled(model.groupMutationsDisabled || model.inviteCode.trimmingCharacters(in: .whitespaces).isEmpty)
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
