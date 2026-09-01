import SwiftUI

struct AppSettingsView: View {
    @Bindable var model: AppModel
    let actions: SettingsActions

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
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
            }

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
