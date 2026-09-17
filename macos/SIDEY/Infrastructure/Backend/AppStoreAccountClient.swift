import Foundation

enum AccountDeletionResult: Sendable, Equatable {
    case deleted
    case appleAuthenticationRequired
}

struct AppStoreAccountClient: Sendable {
    let apiBaseURL: URL?
    let session: URLSession

    init(apiBaseURL: URL? = AppStoreServiceEndpoint.resolve(), session: URLSession = .shared) {
        self.apiBaseURL = apiBaseURL
        self.session = session
    }

    func deleteAccount(payload: AppleAuthorizationPayload, accessToken: String) async throws {
        guard let authorizationCode = payload.authorizationCode else {
            throw AppleAuthorizationError.missingAuthorizationCode
        }
        guard let apiBaseURL else { throw AppStorePurchaseError.verifierNotConfigured }
        var request = URLRequest(url: apiBaseURL.appending(path: "account/apple"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(DeleteAccountRequest(
            identityToken: payload.identityToken,
            authorizationCode: authorizationCode,
            nonce: payload.nonce
        ))
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppStoreAccountError.deletionRejected
        }
        if http.statusCode == 401 { throw SideyBackendError.sessionRecoveryFailed }
        guard (200..<300).contains(http.statusCode) else {
            throw AppStoreAccountError.deletionRejected
        }
        let result = try JSONDecoder().decode(DeleteAccountResponse.self, from: data)
        guard result.deleted else { throw AppStoreAccountError.deletionRejected }
    }
}

private struct DeleteAccountResponse: Decodable {
    let deleted: Bool
    let appleCredentialRevoked: Bool
}

private struct DeleteAccountRequest: Encodable {
    let identityToken: String
    let authorizationCode: String
    let nonce: String
}

enum AppStoreAccountError: LocalizedError {
    case deletionRejected
    var errorDescription: String? { "계정 삭제 요청을 완료하지 못했습니다." }
}
