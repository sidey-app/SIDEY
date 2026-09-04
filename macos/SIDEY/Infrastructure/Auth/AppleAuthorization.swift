import AuthenticationServices
import CryptoKit
import Foundation
import Security

struct AppleAuthorizationPayload: Sendable {
    let identityToken: String
    let authorizationCode: String?
    let nonce: String
}

enum AppleAuthorization {
    static func prepare(_ request: ASAuthorizationAppleIDRequest, nonce: String) {
        request.requestedScopes = [.fullName, .email]
        request.nonce = SHA256.hash(data: Data(nonce.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func payload(
        from result: Result<ASAuthorization, any Error>,
        nonce: String
    ) throws -> AppleAuthorizationPayload {
        let authorization = try result.get()
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8)
        else { throw AppleAuthorizationError.missingIdentityToken }
        let authorizationCode = credential.authorizationCode
            .flatMap { String(data: $0, encoding: .utf8) }
        return AppleAuthorizationPayload(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            nonce: nonce
        )
    }

    static func makeNonce(length: Int = 32) -> String {
        precondition(length > 0)
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        result.reserveCapacity(length)
        while result.count < length {
            var byte: UInt8 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, 1, &byte) == errSecSuccess else {
                return UUID().uuidString.replacingOccurrences(of: "-", with: "")
            }
            if byte < alphabet.count { result.append(alphabet[Int(byte)]) }
        }
        return result
    }
}

enum AppleAuthorizationError: LocalizedError {
    case missingIdentityToken
    case missingAuthorizationCode

    var errorDescription: String? {
        switch self {
        case .missingIdentityToken: "Apple 로그인 응답에 identity token이 없습니다."
        case .missingAuthorizationCode: "계정 탈퇴에는 새로운 Apple 인증 코드가 필요합니다."
        }
    }
}
