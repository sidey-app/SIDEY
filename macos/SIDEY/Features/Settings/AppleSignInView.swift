import AuthenticationServices
import SwiftUI

struct AppleSignInView: View {
    @Bindable var model: AppModel
    let actions: SettingsActions
    let usesApple: Bool

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 54))
                .foregroundStyle(.mint)
            VStack(spacing: 8) {
                Text("SIDEY 시작하기")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("계정을 보호하고 기존 프로필과 그룹을 계속 사용하려면 로그인해 주세요.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Google로 계속", action: actions.onSignInWithGoogle)
                .buttonStyle(.glassProminent)
                .frame(width: 280, height: 44)
                .disabled(model.accountOperationInProgress)
            ServerAppleSignInButton(
                isDisabled: model.accountOperationInProgress,
                fetchNonce: actions.onAuthenticationNonce,
                onAuthorization: actions.onSignInWithApple,
                onError: { model.errorMessage = $0.localizedDescription }
            )

            if model.accountOperationInProgress { ProgressView("로그인 확인 중") }
            if let error = model.errorMessage {
                Text(error).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center)
            }
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Apple requires a synchronous request callback. Prepare the server's one-use
/// challenge before enabling it, then replace that challenge after every attempt.
struct ServerAppleSignInButton: View {
    let isDisabled: Bool
    let fetchNonce: @MainActor () async throws -> String
    let onAuthorization: (AppleAuthorizationPayload) -> Void
    let onError: (any Error) -> Void
    @State private var nonce: String?
    @State private var requestedNonce: String?
    @State private var requestedAuthorization: ((AppleAuthorizationPayload) -> Void)?
    @State private var generation = 0
    @State private var preparationFailed = false

    var body: some View {
        VStack(spacing: 8) {
            SignInWithAppleButton(.continue) { request in
                guard let nonce else { return }
                requestedNonce = nonce
                requestedAuthorization = onAuthorization
                self.nonce = nil
                AppleAuthorization.prepare(request, nonce: nonce)
            } onCompletion: { result in
                defer {
                    requestedNonce = nil
                    requestedAuthorization = nil
                    nonce = nil
                    generation += 1
                }
                do {
                    let payload = try AppleAuthorization.payload(from: result)
                    guard payload.nonce == requestedNonce, let requestedAuthorization else {
                        throw AppleAuthorizationError.missingRequestNonce
                    }
                    requestedAuthorization(payload)
                } catch {
                    onError(error)
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(width: 280, height: 44)
            .disabled(isDisabled || nonce == nil || requestedNonce != nil)

            if preparationFailed {
                Button("로그인 준비 다시 시도") { generation += 1 }
                    .disabled(isDisabled)
            }
        }
        .task(id: generation) {
            preparationFailed = false
            do {
                while !Task.isCancelled {
                    if requestedNonce == nil {
                        let prepared = try await fetchNonce()
                        try Task.checkCancellation()
                        nonce = prepared
                    }
                    // Server challenges expire after five minutes.
                    try await Task.sleep(for: .seconds(240))
                }
            } catch is CancellationError {
                return
            } catch {
                nonce = nil
                preparationFailed = true
                onError(error)
            }
        }
    }
}
