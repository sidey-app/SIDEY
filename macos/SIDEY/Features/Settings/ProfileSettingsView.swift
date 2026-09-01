import SwiftUI

struct ProfileSettingsView: View {
    @Bindable var model: AppModel
    let onSave: @MainActor @Sendable () -> Void

    var body: some View {
        SettingsSection(
            title: "내 프로필",
            subtitle: "친구들에게 보이는 이름과 캐릭터를 설정할 수 있습니다.",
            systemImage: "person.crop.circle"
        ) {
            SettingsControlRow(
                title: "닉네임",
                description: "친구들의 픽셀 월드와 메시지에 표시되는 이름 · 2~8자"
            ) {
                TextField("2~8자", text: $model.nickname)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .onChange(of: model.nickname) { _, value in
                        let limited = ProfileValidator.limitedNicknameDraft(value)
                        if limited != value { model.nickname = limited }
                    }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("캐릭터")
                    .font(.headline)
                Text("친구 화면에서 나를 나타낼 픽셀 동물을 선택할 수 있습니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            CharacterSelectionGrid(
                maximumColumns: 5,
                selection: $model.selectedCharacterID
            )
            Text("캐릭터와 닉네임은 그룹 안에서 중복해서 선택할 수 있습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("프로필 저장") {
                    PendingTextInputCommitter.commitThen(onSave)
                }
                    .buttonStyle(.glassProminent)
                    .disabled(model.groupMutationsDisabled || !validNickname)
            }
        }

        if !model.preferences.onboardingComplete {
            Label("프로필을 저장한 뒤 그룹을 만들거나 초대 코드로 참여해 주세요.", systemImage: "sparkles")
                .foregroundStyle(.secondary)
                .padding(.top, 18)
        }
    }

    private var validNickname: Bool {
        ProfileValidator.isValidNickname(model.nickname)
    }
}
