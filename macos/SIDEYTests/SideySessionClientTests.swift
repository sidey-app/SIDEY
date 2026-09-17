import Foundation
import Security
import XCTest
#if APP_STORE
@testable import SIDEYAppStore
#else
@testable import SIDEY
#endif

@MainActor
final class SideySessionClientTests: XCTestCase {
    private let user = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    private let sid = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    private let configuration = RuntimeConfiguration(apiBaseURL: URL(string: "https://session.test/api")!)

    private func fixture() -> (SideySessionClient, KeychainStore, SessionNetwork) {
        let security = SessionKeychainSecurity()
        let store = KeychainStore(service: UUID().uuidString, session: KeychainAccessSession(security: security))
        let transport = SessionNetwork()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionURLProtocol.self]
        config.httpAdditionalHeaders = ["X-Test-ID": transport.id]
        let network = URLSession(configuration: config)
        let client = SideySessionClient(configuration: configuration, keychain: store, network: network,
            now: { Date(timeIntervalSince1970: 1_735_689_600) })
        return (client, store, transport)
    }
    private func session(_ access: String = "new-access", refresh: String = "new-refresh", expired: Bool = false, sessionID: UUID? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["userId": user.uuidString, "sessionId": (sessionID ?? sid).uuidString,
            "accessToken": access, "refreshToken": refresh,
            "accessExpiresAt": expired ? "2024-01-01T00:00:00Z" : "2025-01-01T00:15:00.000000Z"])
    }
    private func legacy(anonymous: Bool = true) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["user": ["id": user.uuidString, "is_anonymous": anonymous],
            "access_token": "old-supabase-proof", "refresh_token": "old-refresh", "expires_at": 1_735_690_500])
    }
    func testNewInstallRequiresProviderAndNeverCreatesAnonymousAccount() async throws {
        let (client, _, transport) = fixture()
        do { try await client.restore(); XCTFail("must require identity") }
        catch { XCTAssertEqual(error as? SideySessionError, .authenticationRequired) }
        XCTAssertTrue(transport.requests.isEmpty)
        let id = await client.userID()
        XCTAssertNil(id)
    }
    func testConcurrentRefreshRotatesExactlyOnceAndPersistsOpaqueToken() async throws {
        let (client, store, transport) = fixture()
        try store.write(session("expired", refresh: "old", expired: true), account: "sidey-session:\(configuration.backendFingerprint):default")
        transport.respond(200, try session())
        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<20 { group.addTask { try await client.accessToken() } }
            var values = [String]()
            for try await value in group { values.append(value) }
            return values
        }
        XCTAssertEqual(Set(tokens), ["new-access"])
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.url?.path, "/api/auth/refresh")
        let saved = try XCTUnwrap(store.read(account: "sidey-session:\(configuration.backendFingerprint):default"))
        XCTAssertTrue(String(decoding: saved, as: UTF8.self).contains("new-refresh"))
    }
    func testUnauthorizedRequestRefreshesOnceAndReplaysWithNewAccess() async throws {
        let (client, store, transport) = fixture()
        try store.write(session("first-access"), account: "sidey-session:\(configuration.backendFingerprint):default")
        transport.respond(401, Data("{}".utf8))
        transport.respond(200, try session())
        transport.respond(200, Data("{\"ok\":true}".utf8))
        _ = try await client.request(method: "GET", path: "rooms")
        XCTAssertEqual(transport.requests.map { $0.url!.path }, ["/api/rooms", "/api/auth/refresh", "/api/rooms"])
        XCTAssertEqual(transport.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer new-access")
    }
    func testRefreshFailureDoesNotReuseConsumedOldToken() async throws {
        let (client, store, transport) = fixture()
        try store.write(session(expired: true), account: "sidey-session:\(configuration.backendFingerprint):default")
        transport.respond(503, Data("{}".utf8))
        do { _ = try await client.accessToken(); XCTFail() } catch {}
        do { _ = try await client.accessToken(); XCTFail() }
        catch { XCTAssertEqual(error as? SideySessionError, .authenticationRequired) }
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertNil(try store.read(account: "sidey-session:\(configuration.backendFingerprint):default"))
    }
    func testLegacyClaimPreservesUUIDAndOnlyClearsProofAfterSIDEYSessionSaved() async throws {
        let (client, store, transport) = fixture()
        let legacyAccount = "supabase-session:\(configuration.legacyBackendFingerprint):default"
        try store.write(legacy(), account: legacyAccount)
        do { try await client.restore(); XCTFail() }
        catch { XCTAssertEqual(error as? SideySessionError, .legacyClaimRequired) }
        transport.respond(200, try session())
        try await client.authenticate(provider: "GOOGLE", credential: "provider-proof", nonce: "fresh-nonce")
        XCTAssertEqual(transport.requests.first?.url?.path, "/api/auth/legacy-claim")
        XCTAssertTrue(transport.bodies.first.map { String(decoding: $0, as: UTF8.self).contains("old-supabase-proof") } ?? false)
        let restoredID = await client.userID()
        XCTAssertEqual(restoredID, user)
        XCTAssertNil(try store.read(account: legacyAccount))
        XCTAssertNotNil(try store.read(account: "sidey-session:\(configuration.backendFingerprint):default"))
        XCTAssertEqual(try store.readString(account: "sidey-legacy-migrated:\(configuration.legacyBackendFingerprint)"), user.uuidString)
    }
    func testFailedClaimRetainsLegacyCredentialAndBlocksOrdinaryRequests() async throws {
        let (client, store, transport) = fixture()
        let account = "supabase-session:\(configuration.legacyBackendFingerprint):default"
        try store.write(legacy(), account: account)
        transport.respond(409, Data("{\"code\":\"identity_conflict\"}".utf8))
        do { try await client.authenticate(provider: "APPLE", credential: "taken", nonce: "nonce"); XCTFail() } catch {}
        do { _ = try await client.request(method: "GET", path: "rooms"); XCTFail() } catch {}
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertNotNil(try store.read(account: account))
    }
    func testAuthenticatedAdditionalProviderUsesLinkAndLogoutRevokesBeforeClear() async throws {
        let (client, store, transport) = fixture()
        let account = "sidey-session:\(configuration.backendFingerprint):default"
        try store.write(session(), account: account)
        transport.respond(204, Data())
        transport.respond(204, Data())
        try await client.authenticate(provider: "APPLE", credential: "fresh-proof", nonce: "fresh-nonce")
        try await client.signOut()
        XCTAssertEqual(transport.requests.map { $0.url!.path }, ["/api/auth/link", "/api/auth/logout"])
        XCTAssertNil(try store.read(account: account))
    }
    func testGooglePKCEAndCallbackRejectMismatchedOrDuplicateState() throws {
        let redirect = URL(string: "http://127.0.0.1:32123/")!
        let url = GoogleDesktopOAuth.authorizationURL(clientID: "desktop-client", nonce: "backend-nonce",
            verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", state: "expected", redirect: redirect)
        let query = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
        XCTAssertEqual(query["code_challenge"], "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertEqual(query["nonce"], "backend-nonce")
        XCTAssertEqual(query["redirect_uri"], redirect.absoluteString)
        XCTAssertEqual(try GoogleLoopbackCallback.parseRequest(Data("GET /?code=valid&state=expected HTTP/1.1\r\n\r\n".utf8), state: "expected")?.get(), "valid")
        for params in ["code=valid&state=wrong", "code=valid&state=expected&state=expected"] {
            XCTAssertThrowsError(try GoogleLoopbackCallback.parseRequest(Data("GET /?\(params) HTTP/1.1\r\n\r\n".utf8), state: "expected")?.get())
        }
    }

    func testProviderAndConsumedChallengeErrorsNeverRefreshOrReplayProof() async throws {
        for code in ["invalid_identity_credential", "auth_challenge_invalid", "identity_provider_unavailable"] {
            let (client, store, transport) = fixture()
            let account = "sidey-session:\(configuration.backendFingerprint):default"
            let original = try session()
            try store.write(original, account: account)
            transport.respond(401, try JSONSerialization.data(withJSONObject: ["code": code]))
            do {
                try await client.authenticate(provider: "APPLE", credential: "fresh-proof", nonce: "one-use-nonce")
                XCTFail("Provider rejection must reach the caller")
            } catch { XCTAssertEqual(error as? SideySessionError, .rejected(code)) }
            XCTAssertEqual(transport.requests.map { $0.url!.path }, ["/api/auth/link"])
            XCTAssertEqual(try store.read(account: account), original)
            let currentUser = await client.userID()
            XCTAssertEqual(currentUser, user)
        }
    }

    func testServerSessionRejectionStillRefreshesBeforeReplayingRequest() async throws {
        let (client, store, transport) = fixture()
        try store.write(session("old-access"), account: "sidey-session:\(configuration.backendFingerprint):default")
        transport.respond(401, Data(#"{"code":"session_rejected"}"#.utf8))
        transport.respond(200, try session())
        transport.respond(200, Data("[]".utf8))
        _ = try await client.request(method: "GET", path: "rooms")
        XCTAssertEqual(transport.requests.map { $0.url!.path }, ["/api/rooms", "/api/auth/refresh", "/api/rooms"])
    }

    func testFreshProviderUnlinkUsesSideyCredentialWithoutReplacingSession() async throws {
        let (client, store, transport) = fixture()
        let account = "sidey-session:\(configuration.backendFingerprint):default"
        let original = try session()
        try store.write(original, account: account)
        transport.respond(204, Data())
        try await client.unlink(provider: "APPLE", credential: "fresh-id-token", nonce: "fresh-server-challenge")
        XCTAssertEqual(transport.requests.first?.url?.path, "/api/auth/unlink")
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer new-access")
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(transport.bodies.first)) as? [String: String]
        XCTAssertEqual(body, ["provider": "APPLE", "credential": "fresh-id-token", "nonce": "fresh-server-challenge", "platform": "MACOS"])
        XCTAssertEqual(try store.read(account: account), original)
    }

    func testLastIdentityAndMismatchedUnlinkRejectionsKeepExistingSession() async throws {
        for (status, code) in [(409, "last_identity_unlink_forbidden"), (403, "identity_proof_mismatch")] {
            let (client, store, transport) = fixture()
            let account = "sidey-session:\(configuration.backendFingerprint):default"
            let original = try session()
            try store.write(original, account: account)
            transport.respond(status, try JSONSerialization.data(withJSONObject: ["code": code]))
            do {
                try await client.unlink(provider: "GOOGLE", credential: "fresh-proof", nonce: "fresh-nonce")
                XCTFail("Server identity protection must be preserved")
            } catch { XCTAssertEqual(error as? SideySessionError, .rejected(code)) }
            XCTAssertEqual(try store.read(account: account), original)
            XCTAssertEqual(transport.requests.count, 1)
        }
    }

    func testLogoutAllRestoresStoredSessionAndClearsOnlyAfterRevocationACK() async throws {
        let (client, store, transport) = fixture()
        let account = "sidey-session:\(configuration.backendFingerprint):default"
        try store.write(session(), account: account)
        transport.respond(204, Data())
        try await client.signOut(allSessions: true)
        XCTAssertEqual(transport.requests.map { $0.url!.path }, ["/api/auth/logout-all"])
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer new-access")
        XCTAssertNil(try store.read(account: account))
        let currentUser = await client.userID()
        XCTAssertNil(currentUser)
    }

    func testFailedLogoutDoesNotPretendServerSessionWasRevoked() async throws {
        let (client, store, transport) = fixture()
        let account = "sidey-session:\(configuration.backendFingerprint):default"
        let original = try session()
        try store.write(original, account: account)
        transport.respond(503, Data(#"{"code":"temporarily_unavailable"}"#.utf8))
        do { try await client.signOut(allSessions: true); XCTFail("Must report revocation failure") }
        catch { XCTAssertEqual(error as? SideySessionError, .rejected("temporarily_unavailable")) }
        XCTAssertEqual(try store.read(account: account), original)
        let currentUser = await client.userID()
        XCTAssertEqual(currentUser, user)
    }

    func testExistingLegacyProviderUsesLoginAndPreservesOriginalUUID() async throws {
        let (client, store, transport) = fixture()
        let legacyAccount = "supabase-session:\(configuration.legacyBackendFingerprint):default"
        try store.write(legacy(anonymous: false), account: legacyAccount)
        transport.respond(200, try session())
        try await client.authenticate(provider: "GOOGLE", credential: "provider-id-token", nonce: "server-nonce")
        XCTAssertEqual(transport.requests.map { $0.url!.path }, ["/api/auth/login"])
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(transport.bodies.first)) as? [String: String]
        XCTAssertNil(body?["legacyCredential"])
        let currentUser = await client.userID()
        XCTAssertEqual(currentUser, user)
        XCTAssertNil(try store.read(account: legacyAccount))
    }

    func testChallengeIsFetchedBeforeLoginAndRawProviderProofIsSent() async throws {
        let (client, _, transport) = fixture()
        transport.respond(200, Data(#"{"nonce":"server-generated-challenge"}"#.utf8))
        transport.respond(200, try session())
        let nonce = try await client.challenge()
        try await client.authenticate(provider: "GOOGLE", credential: "provider-id-token", nonce: nonce)
        XCTAssertEqual(transport.requests.map { $0.url!.path }, ["/api/auth/challenge", "/api/auth/login"])
        XCTAssertTrue(transport.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(transport.bodies.last)) as? [String: String]
        XCTAssertEqual(body?["nonce"], "server-generated-challenge")
        XCTAssertEqual(body?["credential"], "provider-id-token")
        XCTAssertEqual(body?["provider"], "GOOGLE")
    }

    func testOldSessionResponsesCannotReplayOrApplyAfterLogoutAndNewLogin() async throws {
        for status in [200, 401] {
            let (client, store, transport) = fixture()
            try store.write(session("original-access"), account: "sidey-session:\(configuration.backendFingerprint):default")
            let gate = SessionResponseGate()
            transport.respond(status, Data("{}".utf8), gate: gate)
            let pending = Task { try await client.request(method: "PUT", path: "profile", body: Data("{}".utf8)) }
            await gate.waitUntilSuspended()
            transport.respond(204, Data())
            try await client.signOut()
            transport.respond(200, try session("replacement-access", sessionID: UUID()))
            try await client.authenticate(provider: "GOOGLE", credential: "fresh-proof", nonce: "fresh-nonce")
            gate.release()
            do { _ = try await pending.value; XCTFail("Old account response must not complete against a new session") }
            catch { XCTAssertEqual(error as? SideySessionError, .rejected("session_changed")) }
            XCTAssertEqual(transport.requests.map { $0.url!.path }, ["/api/profile", "/api/auth/logout", "/api/auth/login"])
            let token = try await client.accessToken()
            XCTAssertEqual(token, "replacement-access")
        }
    }
}

private final class SessionResponseGate: @unchecked Sendable {
    private let lock = NSLock()
    private var delivery: (@Sendable () -> Void)?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func suspend(_ action: @escaping @Sendable () -> Void) {
        let ready = lock.withLock {
            delivery = action
            let ready = waiters
            waiters.removeAll()
            return ready
        }
        ready.forEach { $0.resume() }
    }
    func waitUntilSuspended() async {
        await withCheckedContinuation { continuation in
            let ready = lock.withLock {
                if delivery != nil { return true }
                waiters.append(continuation)
                return false
            }
            if ready { continuation.resume() }
        }
    }
    func release() {
        let action = lock.withLock { let action = delivery; delivery = nil; return action }
        action?()
    }
}

private final class SessionKeychainSecurity: KeychainSecurityPerforming, @unchecked Sendable {
    private let lock = NSLock()
    private var data = [String: Data]()
    func copyMatching(_ query: CFDictionary) -> (status: OSStatus, data: Data?) {
        lock.withLock {
            let value = data[(query as NSDictionary)[kSecAttrAccount] as! String]
            return (value == nil ? errSecItemNotFound : errSecSuccess, value)
        }
    }
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        lock.withLock {
            let key = (query as NSDictionary)[kSecAttrAccount] as! String
            guard data[key] != nil else { return errSecItemNotFound }
            data[key] = (attributes as NSDictionary)[kSecValueData] as? Data
            return errSecSuccess
        }
    }
    func add(_ attributes: CFDictionary) -> OSStatus {
        lock.withLock {
            data[(attributes as NSDictionary)[kSecAttrAccount] as! String] = (attributes as NSDictionary)[kSecValueData] as? Data
            return errSecSuccess
        }
    }
    func delete(_ query: CFDictionary) -> OSStatus {
        lock.withLock { data.removeValue(forKey: (query as NSDictionary)[kSecAttrAccount] as! String); return errSecSuccess }
    }
}

private final class SessionNetwork: @unchecked Sendable {
    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var registry = [String: SessionNetwork]()
    let id = UUID().uuidString
    private let lock = NSLock()
    private var replies = [(Int, Data, SessionResponseGate?)]()
    private var recorded = [URLRequest]()
    private var recordedBodies = [Data]()
    init() { Self.registryLock.withLock { Self.registry[id] = self } }
    var requests: [URLRequest] { lock.withLock { recorded } }
    var bodies: [Data] { lock.withLock { recordedBodies } }
    func respond(_ status: Int, _ data: Data, gate: SessionResponseGate? = nil) { lock.withLock { replies.append((status, data, gate)) } }
    static func take(_ request: URLRequest) -> (Int, Data, SessionResponseGate?) {
        guard let id = request.value(forHTTPHeaderField: "X-Test-ID"),
              let instance = registryLock.withLock({ registry[id] }) else { return (500, Data(), nil) }
        return instance.lock.withLock {
            instance.recorded.append(request)
            var body = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                var bytes = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    if count <= 0 { break }
                    body.append(contentsOf: bytes.prefix(count))
                }
                stream.close()
            }
            instance.recordedBodies.append(body)
            return instance.replies.isEmpty ? (500, Data(), nil) : instance.replies.removeFirst()
        }
    }
}
private final class SessionURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data, gate) = SessionNetwork.take(request)
        let deliver: @Sendable () -> Void = { [self] in
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        if let gate { gate.suspend(deliver) } else { deliver() }
    }
    override func stopLoading() {}
}
