import SwiftUI
import AuthenticationServices

struct AppSettingsView: View {
    @Bindable var model: AppModel
    let actions: SettingsActions
    let storeAvailability: StoreAvailability
    @State private var showsDeletionControls = false
    @State private var deletionPhrase = ""
    @State private var requiresAppleDeletionAuthentication = false
    @State private var unlinksAppleIdentity = false

    init(
        model: AppModel,
        actions: SettingsActions,
        storeAvailability: StoreAvailability = AppReleaseChannel.resolve().storeAvailability
    ) {
        self.model = model
        self.actions = actions
        self.storeAvailability = storeAvailability
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            #if DEBUG
            Text("\(SideyBuildStamp.target) · \(SideyBuildStamp.commit.prefix(8))\(SideyBuildStamp.dirty ? " · 미커밋 변경" : "")")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            #endif
            SettingsSection(
                title: "일반",
                subtitle: "SIDEY의 기본 표시와 실행 방식을 설정할 수 있습니다.",
                systemImage: "gearshape"
            ) {
                SettingsToggleRow(
                    title: "픽셀 월드 표시",
                    description: "선택한 화면 가장자리에 친구들의 픽셀 월드를 표시합니다.",
                    isOn: Binding(
                        get: { model.overlayVisible },
                        set: { actions.onOverlayVisibilityChanged($0) }
                    )
                )
                Divider()
                SettingsToggleRow(
                    title: "로그인 시 자동 실행",
                    description: "Mac에 로그인하면 SIDEY를 자동으로 시작합니다.",
                    isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { actions.onLaunchAtLoginChanged($0) }
                    )
                )
            }

            SettingsSection(
                title: "표시",
                subtitle: "친구 상태와 메시지가 화면에 나타나는 방식을 조절할 수 있습니다.",
                systemImage: "eye"
            ) {
                SettingsToggleRow(
                    title: "조용히 모드",
                    description: "메시지 본문 말풍선은 숨기고 타이핑 상태와 미확인 수는 유지합니다.",
                    isOn: Binding(
                        get: { model.preferences.quietModeEnabled },
                        set: { actions.onQuietModeChanged($0) }
                    )
                )
                Divider()
                SettingsToggleRow(
                    title: "오프라인 멤버 표시",
                    description: "접속하지 않은 친구도 잠든 캐릭터와 빨간 상태 점으로 표시합니다.",
                    isOn: Binding(
                        get: { model.preferences.showOfflineMembers },
                        set: { actions.onShowOfflineMembersChanged($0) }
                    )
                )
                Divider()
                SettingsToggleRow(
                    title: "더블 우클릭 후 던지기",
                    description: "끄면 친구 캐릭터를 바로 클릭할 수 있고, 켜면 내 캐릭터를 더블 우클릭한 뒤 10초 동안만 클릭할 수 있습니다.",
                    isOn: Binding(
                        get: { model.preferences.requiresRightClickToThrow },
                        set: { actions.onRequiresRightClickToThrowChanged($0) }
                    )
                )
            }

            SettingsSection(title: "소리", subtitle: "캐릭터 효과음 재생을 설정합니다.", systemImage: "speaker.wave.2") {
                SettingsToggleRow(
                    title: "캐릭터 효과음",
                    description: "현재 그룹에서 캐릭터가 맞을 때 효과음을 재생합니다.",
                    isOn: Binding(get: { model.preferences.characterSoundEffectsEnabled },
                                  set: { actions.onCharacterSoundEffectsChanged($0) })
                )
            }

            if !storeAvailability.usesAppStore {
                SettingsSection(
                    title: "업데이트",
                    subtitle: "새로운 SIDEY 버전이 있는지 확인할 수 있습니다.",
                    systemImage: "arrow.triangle.2.circlepath"
                ) {
                    SettingsControlRow(
                        title: "업데이트 확인",
                        description: "새 버전이 있으면 안전하게 내려받아 설치할 수 있습니다."
                    ) {
                        Button("지금 확인", action: actions.onCheckForUpdates)
                            .buttonStyle(.glassProminent)
                            .disabled(!actions.canCheckForUpdates())
                    }
                }
            }

            SettingsSection(
                title: "월드 배치",
                subtitle: "픽셀 캐릭터를 표시할 화면과 위치를 선택할 수 있습니다.",
                systemImage: "rectangle.inset.filled"
            ) {
                SettingsControlRow(
                    title: "가장자리",
                    description: "캐릭터가 걸어 다닐 화면 방향을 선택합니다."
                ) {
                    Picker("가장자리", selection: regionEdgeBinding) {
                        ForEach(OverlayEdge.allCases) { edge in
                            Text(edge.title).tag(edge)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180, alignment: .trailing)
                }
                Divider()
                SettingsControlRow(
                    title: "영역 길이",
                    description: "선택한 가장자리에서 월드가 차지할 범위를 선택합니다."
                ) {
                    Picker("길이", selection: regionSpanBinding) {
                        ForEach(OverlaySpan.allCases) { span in
                            Text(span.title).tag(span)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180, alignment: .trailing)
                }
                Divider()
                SettingsControlRow(
                    title: "모니터",
                    description: "픽셀 월드와 메시지 입력창을 표시할 화면을 선택합니다."
                ) {
                    Picker("모니터", selection: regionScreenBinding) {
                        ForEach(model.availableScreens) { screen in
                            Text(screen.name).tag(Optional(screen.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 240, alignment: .trailing)
                }
            }

            accountSection

        }
    }

    private var accountSection: some View {
        SettingsSection(
            title: "계정 및 개인정보",
            subtitle: "계정 데이터와 개인정보를 관리합니다.",
            systemImage: "person.crop.circle"
        ) {
            HStack(spacing: 18) {
                Link(
                    "개인정보 처리방침",
                    destination: URL(string: "https://sidey-app.github.io/SIDEY/privacy.html")!
                )
                Link(
                    "이용약관",
                    destination: URL(string: "https://sidey-app.github.io/SIDEY/terms.html")!
                )
                Spacer()
                if storeAvailability.usesAppStore {
                    Button("구매 복원", action: actions.onRestorePurchases)
                        .disabled(model.accountOperationInProgress)
                }
            }
            Divider()
            DisclosureGroup("로그인 계정 관리") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Google 또는 Apple 계정을 연결할 수 있습니다. 마지막 로그인 계정은 연결을 해제할 수 없습니다.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Google 계정 연결", action: actions.onSignInWithGoogle)
                        Button("Google 연결 해제", role: .destructive, action: actions.onUnlinkGoogleIdentity)
                    }
                    Picker("Apple 계정", selection: $unlinksAppleIdentity) {
                        Text("연결").tag(false)
                        Text("연결 해제").tag(true)
                    }
                    .frame(maxWidth: 280)
                    ServerAppleSignInButton(
                        isDisabled: model.accountOperationInProgress,
                        fetchNonce: actions.onAuthenticationNonce,
                        onAuthorization: unlinksAppleIdentity ? actions.onUnlinkAppleIdentity : actions.onSignInWithApple,
                        onError: { model.errorMessage = $0.localizedDescription }
                    )
                    Text("연결하거나 해제할 계정으로 다시 인증해 주세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(model.accountOperationInProgress)
            }
            HStack {
                Button("로그아웃") { actions.onSignOut(false) }
                Button("모든 기기에서 로그아웃") { actions.onSignOut(true) }
            }
            .disabled(model.accountOperationInProgress)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("계정 탈퇴")
                    .font(.body.weight(.semibold))
                Text("프로필, 메시지, 그룹 멤버십을 삭제합니다. 구매 기록은 회계·부정 사용 방지에 필요한 범위에서 계정과 분리해 보관될 수 있습니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if showsDeletionControls {
                    TextField("확인을 위해 ‘탈퇴’ 입력", text: $deletionPhrase)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                    if requiresAppleDeletionAuthentication {
                        ServerAppleSignInButton(
                            isDisabled: deletionPhrase != "탈퇴" || model.accountOperationInProgress,
                            fetchNonce: actions.onAuthenticationNonce,
                            onAuthorization: actions.onDeleteAccount,
                            onError: { model.errorMessage = $0.localizedDescription }
                        )
                        Text("연결된 Apple 계정으로 다시 인증하면 즉시 삭제됩니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button("계정 영구 삭제", role: .destructive) {
                            Task {
                                do {
                                    requiresAppleDeletionAuthentication = try await actions.onRequestAccountDeletion() == .appleAuthenticationRequired
                                } catch {
                                    model.errorMessage = "계정 탈퇴 실패: \(error.localizedDescription)"
                                }
                            }
                        }
                        .disabled(deletionPhrase != "탈퇴" || model.accountOperationInProgress)
                    }
                } else {
                    Button("계정 탈퇴…", role: .destructive) {
                        showsDeletionControls = true
                    }
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
