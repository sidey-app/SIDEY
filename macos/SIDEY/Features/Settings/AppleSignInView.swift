import AuthenticationServices
import SwiftUI

struct AppleSignInView: View {
    @Bindable var model: AppModel
    let onSignIn: (AppleAuthorizationPayload) -> Void
    @State private var nonce = AppleAuthorization.makeNonce()

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 54))
                .foregroundStyle(.mint)
            VStack(spacing: 8) {
                Text("Apple로 SIDEY 시작하기")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("구매 복원과 계정 보호를 위해 App Store 버전은 Apple 로그인이 필요합니다.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            SignInWithAppleButton(.continue) { request in
                nonce = AppleAuthorization.makeNonce()
                AppleAuthorization.prepare(request, nonce: nonce)
            } onCompletion: { result in
                do {
                    onSignIn(try AppleAuthorization.payload(from: result, nonce: nonce))
                } catch {
                    model.errorMessage = error.localizedDescription
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(width: 280, height: 44)
            .disabled(model.accountOperationInProgress)

            if model.accountOperationInProgress { ProgressView("로그인 확인 중") }
            if let error = model.errorMessage {
                Text(error).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center)
            }
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
