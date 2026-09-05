import SwiftUI

@MainActor
struct SettingsActions {
    var onOverlayVisibilityChanged: (Bool) -> Void
    var onOverlayRegionChanged: (OverlayRegionPreference) -> Void
    var onShowOfflineMembersChanged: (Bool) -> Void
    var onRequiresRightClickToThrowChanged: (Bool) -> Void
    var onQuietModeChanged: (Bool) -> Void
    var onLaunchAtLoginChanged: (Bool) -> Void
    var onCheckForUpdates: () -> Void
    var canCheckForUpdates: () -> Bool
    var onPurchase: (String) -> Void
    var onRefreshCommerceState: (String?) -> Void
    var onSetEquippedCosmetic: (CommerceProductKind, String?) -> Void
    var onRestorePurchases: () -> Void
    var onSignInWithApple: (AppleAuthorizationPayload) -> Void
    var onDeleteAccount: (AppleAuthorizationPayload) -> Void
    var onSaveProfile: @MainActor @Sendable () -> Void
    var onCreateRoom: () -> Void
    var onJoinRoom: () -> Void
    var onSelectRoom: (UUID) -> Void
    var onCopyInviteCode: (UUID) async -> Bool
    var onRotateInviteCode: (UUID) -> Void
    var onRenameRoom: (UUID, String) -> Void
    var onRemoveRoomMember: (UUID, UUID) -> Void
    var onDeleteRoom: (UUID) -> Void

    static let empty = SettingsActions(
        onOverlayVisibilityChanged: { _ in },
        onOverlayRegionChanged: { _ in },
        onShowOfflineMembersChanged: { _ in },
        onRequiresRightClickToThrowChanged: { _ in },
        onQuietModeChanged: { _ in },
        onLaunchAtLoginChanged: { _ in },
        onCheckForUpdates: {},
        canCheckForUpdates: { false },
        onPurchase: { _ in },
        onRefreshCommerceState: { _ in },
        onSetEquippedCosmetic: { _, _ in },
        onRestorePurchases: {},
        onSignInWithApple: { _ in },
        onDeleteAccount: { _ in },
        onSaveProfile: {},
        onCreateRoom: {},
        onJoinRoom: {},
        onSelectRoom: { _ in },
        onCopyInviteCode: { _ in false },
        onRotateInviteCode: { _ in },
        onRenameRoom: { _, _ in },
        onRemoveRoomMember: { _, _ in },
        onDeleteRoom: { _ in }
    )
}

struct SettingsRootView: View {
    @Bindable var model: AppModel
    let actions: SettingsActions
    let storeAvailability: StoreAvailability

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
        Group {
            if model.authenticationRequired {
                AppleSignInView(model: model, onSignIn: actions.onSignInWithApple)
            } else if model.preferences.onboardingComplete {
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
                    case .store:
                        StoreView(
                            model: model,
                            actions: actions,
                            availability: storeAvailability
                        )
                    case .app:
                        AppSettingsView(
                            model: model,
                            actions: actions,
                            storeAvailability: storeAvailability
                        )
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
