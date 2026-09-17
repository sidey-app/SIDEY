import Foundation

enum SideySessionError: LocalizedError, Equatable {
    case authenticationRequired
    case legacyClaimRequired
    case googleNotConfigured
    case rejected(String)
    var errorDescription: String? {
        switch self {
        case .authenticationRequired: "Google 또는 Apple로 로그인해 주세요."
        case .legacyClaimRequired: "기존 계정을 유지하려면 Google 또는 Apple로 로그인해 주세요."
        case .googleNotConfigured: "Google 데스크톱 로그인 설정이 없습니다."
        case .rejected(let code): SideyBackendError.business(code: code).localizedDescription
        }
    }
}

/// Owns only SIDEY sessions. Legacy credentials are an isolated ownership proof
/// for the one-time claim and can never authorize ordinary service requests.
actor SideySessionClient {
    struct Session: Codable, Sendable {
        let accessToken: String
        let refreshToken: String
        let userId: UUID
        let sessionId: UUID
        let accessExpiresAt: Date
    }
    private struct LegacySession: Sendable {
        let userID: UUID?
        let accessToken: String?
        let refreshToken: String
        let expiresAt: Date
        let anonymous: Bool
    }
    private let configuration: RuntimeConfiguration
    private let keychain: KeychainStore
    private let network: URLSession
    private let now: @Sendable () -> Date
    private var session: Session?
    private var legacy: LegacySession?
    private var didRestore = false
    private var refreshFlight: Task<Session, Error>?
    private var authenticationInFlight = false
    private var googleInFlight = false

    init(configuration: RuntimeConfiguration, keychain: KeychainStore,
         network: URLSession = .shared, now: @escaping @Sendable () -> Date = Date.init) {
        self.configuration = configuration
        self.keychain = keychain
        self.network = network
        self.now = now
    }
    private var sessionAccount: String { "sidey-session:\(configuration.backendFingerprint):default" }
    private var legacySessionAccount: String { "supabase-session:\(configuration.legacyBackendFingerprint):default" }
    private var legacyRefreshAccount: String { "supabase-refresh:\(configuration.legacyBackendFingerprint):default" }
    private var claimMarker: String { "sidey-legacy-migrated:\(configuration.legacyBackendFingerprint)" }

    func restore() async throws {
        try loadStoredState()
        guard session != nil else {
            throw legacy == nil ? SideySessionError.authenticationRequired : SideySessionError.legacyClaimRequired
        }
        _ = try await accessToken()
    }
    func userID() -> UUID? { session?.userId }
    func hasLegacyCredential() throws -> Bool { try loadStoredState(); return legacy != nil }

    func accessToken() async throws -> String {
        try loadStoredState()
        guard let session else {
            throw legacy == nil ? SideySessionError.authenticationRequired : SideySessionError.legacyClaimRequired
        }
        if session.accessExpiresAt.timeIntervalSince(now()) > 30 { return session.accessToken }
        return try await refresh().accessToken
    }

    func challenge() async throws -> String {
        let data = try await publicRequest(path: "auth/challenge", body: Data("{}".utf8))
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: String],
              let nonce = result["nonce"], !nonce.isEmpty else { throw SideyBackendError.malformedResponse }
        return nonce
    }

    func authenticate(provider: String, credential: String, nonce: String) async throws {
        guard !authenticationInFlight else { throw SideySessionError.rejected("authentication_in_progress") }
        authenticationInFlight = true
        defer { authenticationInFlight = false }
        try loadStoredState()
        var proof = ["provider": provider, "credential": credential, "nonce": nonce, "platform": "MACOS"]
        if session != nil {
            _ = try await request(method: "POST", path: "auth/link", body: JSONSerialization.data(withJSONObject: proof))
            return
        }
        var expectedLegacyID: UUID?
        var path = "auth/login"
        if legacy != nil {
            let verifiedLegacy = try await legacyOwnershipCredential()
            expectedLegacyID = verifiedLegacy.userID
            // Previously linked accounts already retain the same provider subject
            // in the imported identity table and use normal provider login.
            if verifiedLegacy.anonymous {
                guard let id = verifiedLegacy.userID, let token = verifiedLegacy.accessToken else {
                    throw SideyBackendError.sessionRecoveryFailed
                }
                expectedLegacyID = id
                proof["legacyCredential"] = token
                path = "auth/legacy-claim"
            }
        }
        let data = try await publicRequest(path: path, body: JSONSerialization.data(withJSONObject: proof))
        let next = try Self.decode(data)
        if let expectedLegacyID, next.userId != expectedLegacyID { throw SideyBackendError.sessionRecoveryFailed }
        try persist(next)
        if legacy != nil {
            // Persist the new rotating credentials first. A crash during cleanup
            // then restores SIDEY directly and never repeats a successful claim.
            try keychain.writeString(next.userId.uuidString, account: claimMarker)
            try keychain.delete(account: legacySessionAccount)
            try keychain.delete(account: legacyRefreshAccount)
            legacy = nil
        }
    }

    func signInWithGoogle() async throws {
        try await authenticateWithGoogle(unlink: false)
    }

    func unlinkGoogleIdentity() async throws {
        try await authenticateWithGoogle(unlink: true)
    }

    private func authenticateWithGoogle(unlink: Bool) async throws {
        guard !configuration.googleClientID.isEmpty else { throw SideySessionError.googleNotConfigured }
        guard !googleInFlight else { throw SideySessionError.rejected("authentication_in_progress") }
        googleInFlight = true
        defer { googleInFlight = false }
        let nonce = try await challenge()
        let credential = try await GoogleDesktopOAuth.authenticate(configuration: configuration, nonce: nonce, network: network)
        if unlink {
            try await self.unlink(provider: "GOOGLE", credential: credential, nonce: nonce)
        } else {
            try await authenticate(provider: "GOOGLE", credential: credential, nonce: nonce)
        }
    }

    func unlink(provider: String, credential: String, nonce: String) async throws {
        guard !authenticationInFlight else { throw SideySessionError.rejected("authentication_in_progress") }
        authenticationInFlight = true
        defer { authenticationInFlight = false }
        let proof = ["provider": provider, "credential": credential, "nonce": nonce, "platform": "MACOS"]
        _ = try await request(method: "POST", path: "auth/unlink", body: JSONSerialization.data(withJSONObject: proof))
    }

    func signOut(allSessions: Bool = false) async throws {
        guard !authenticationInFlight, !googleInFlight else { throw SideySessionError.rejected("authentication_in_progress") }
        authenticationInFlight = true
        defer { authenticationInFlight = false }
        try loadStoredState()
        if let flight = refreshFlight { _ = try await flight.value }
        if session != nil {
            _ = try await request(method: "POST", path: allSessions ? "auth/logout-all" : "auth/logout", body: Data("{}".utf8))
        }
        try keychain.delete(account: sessionAccount)
        session = nil
    }

    /// Only a rejected access token is retried, once, after single-flight refresh.
    /// Transport failures and arbitrary mutations are never blindly replayed.
    func request(method: String, path: String, body: Data? = nil) async throws -> Data {
        let token = try await accessToken()
        guard let expectedSession = session?.sessionId else { throw SideySessionError.authenticationRequired }
        do {
            let result = try await perform(method: method, path: path, body: body, token: token)
            try requireSession(expectedSession)
            return result
        }
        catch SideySessionError.rejected("http_401") {
            try requireSession(expectedSession)
            let replacement: String
            if let current = session, current.accessToken != token { replacement = current.accessToken }
            else { replacement = try await refresh().accessToken }
            try requireSession(expectedSession)
            let result = try await perform(method: method, path: path, body: body, token: replacement)
            try requireSession(expectedSession)
            return result
        }
    }

    private func requireSession(_ expected: UUID) throws {
        guard session?.sessionId == expected else { throw SideySessionError.rejected("session_changed") }
    }

    private func loadStoredState() throws {
        guard !didRestore else { return }
        if let data = try keychain.read(account: sessionAccount) { session = try Self.decode(data) }
        if session == nil, try keychain.readString(account: claimMarker) == nil {
            if let data = try keychain.read(account: legacySessionAccount) {
                legacy = try Self.parseLegacy(data)
            } else if let refresh = try keychain.readString(account: legacyRefreshAccount), !refresh.isEmpty {
                legacy = LegacySession(userID: nil, accessToken: nil, refreshToken: refresh, expiresAt: .distantPast, anonymous: true)
            }
        }
        didRestore = true
    }

    private func refresh() async throws -> Session {
        if let flight = refreshFlight { return try await flight.value }
        guard let current = session else { throw SideySessionError.authenticationRequired }
        let flight = Task<Session, Error> { try await self.rotate(current) }
        refreshFlight = flight
        defer { refreshFlight = nil }
        return try await flight.value
    }
    private func rotate(_ current: Session) async throws -> Session {
        let body = try JSONSerialization.data(withJSONObject: ["refreshToken": current.refreshToken])
        let data: Data
        do { data = try await publicRequest(path: "auth/refresh", body: body) }
        catch {
            // A response lost after rotation cannot safely replay the consumed
            // token. Require fresh identity proof instead of revoking by reuse.
            session = nil
            try keychain.delete(account: sessionAccount)
            throw error
        }
        let next: Session
        do { next = try Self.decode(data) }
        catch {
            session = nil
            try keychain.delete(account: sessionAccount)
            throw error
        }
        guard next.userId == current.userId, next.sessionId == current.sessionId else {
            session = nil
            try keychain.delete(account: sessionAccount)
            throw SideyBackendError.sessionRecoveryFailed
        }
        // Keep the newly rotated token in memory even when Keychain is denied;
        // never send the consumed old token again in this process.
        session = next
        try persist(next)
        return next
    }
    private func persist(_ value: Session) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try keychain.write(encoder.encode(value), account: sessionAccount)
        session = value
    }

    private func legacyOwnershipCredential() async throws -> LegacySession {
        guard let current = legacy else { throw SideyBackendError.sessionRecoveryFailed }
        if current.accessToken != nil, current.userID != nil, current.expiresAt.timeIntervalSince(now()) > 60 { return current }
        let url = configuration.legacySupabaseURL.appendingPathComponent("auth/v1/token")
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        var request = URLRequest(url: parts.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.legacySupabasePublishableKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": current.refreshToken])
        let (data, response) = try await network.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw SideyBackendError.sessionRecoveryFailed
        }
        let restored = try Self.parseLegacy(data)
        if let priorID = current.userID, restored.userID != priorID { throw SideyBackendError.sessionRecoveryFailed }
        try SideyAuthStorage(keychain: keychain, legacyRefreshAccount: legacyRefreshAccount)
            .store(key: legacySessionAccount, value: data)
        legacy = restored
        return restored
    }
    private static func parseLegacy(_ data: Data) throws -> LegacySession {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let refresh = object["refresh_token"] as? String, !refresh.isEmpty else {
            throw SideyBackendError.sessionRecoveryFailed
        }
        let user = object["user"] as? [String: Any]
        return LegacySession(userID: (user?["id"] as? String).flatMap(UUID.init(uuidString:)),
            accessToken: object["access_token"] as? String, refreshToken: refresh,
            expiresAt: Date(timeIntervalSince1970: object["expires_at"] as? Double ?? 0),
            anonymous: user?["is_anonymous"] as? Bool ?? true)
    }
    private func publicRequest(path: String, body: Data) async throws -> Data {
        try await perform(method: "POST", path: path, body: body, token: nil)
    }
    private func perform(method: String, path: String, body: Data?, token: String?) async throws -> Data {
        // Keep caller-supplied query strings, but never allow an origin escape.
        let base = configuration.apiBaseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/"
        guard !path.hasPrefix("//"), !path.contains("://"), !path.split(separator: "/").contains("..") else {
            throw SideyBackendError.malformedResponse
        }
        let relativePath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let url = URL(string: base + relativePath), url.host == configuration.apiBaseURL.host else {
            throw SideyBackendError.malformedResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await network.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw SideyBackendError.malformedResponse }
        let errorBody = (200..<300).contains(response.statusCode) ? nil : try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let errorCode = errorBody?["code"] as? String
        if response.statusCode == 401, token != nil,
           errorCode == nil || errorCode == "session_rejected" {
            throw SideySessionError.rejected("http_401")
        }
        guard (200..<300).contains(response.statusCode) else {
            // A provider/challenge rejection is not an expired SIDEY JWT.
            // Replaying it would reuse an already consumed authentication nonce.
            throw SideySessionError.rejected(errorCode ?? "http_\(response.statusCode)")
        }
        return data
    }
    private static func decode(_ data: Data) throws -> Session {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let value = formatter.date(from: raw) { return value }
            formatter.formatOptions = [.withInternetDateTime]
            guard let value = formatter.date(from: raw) else { throw SideyBackendError.invalidTimestamp }
            return value
        }
        let session = try decoder.decode(Session.self, from: data)
        guard !session.accessToken.isEmpty, !session.refreshToken.isEmpty else { throw SideyBackendError.malformedResponse }
        return session
    }
}
