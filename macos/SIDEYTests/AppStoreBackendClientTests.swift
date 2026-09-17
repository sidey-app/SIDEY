import Foundation
import XCTest
#if APP_STORE
@testable import SIDEYAppStore
#else
@testable import SIDEY
#endif

final class AppStoreBackendClientTests: XCTestCase {
    func testDeletionUsesSideySessionAndFreshAppleProof() async throws {
        let fixture = CommerceHTTPFixture(
            response: #"{"deleted":true,"appleCredentialRevoked":true}"#
        ) { request in
            XCTAssertEqual(request.url?.path, "/api/account/apple")
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sidey-access")
            XCTAssertNil(request.value(forHTTPHeaderField: "apikey"))
            XCTAssertEqual(CommerceHTTPFixture.body(request), [
                "identityToken": "apple-proof", "authorizationCode": "fresh-code", "nonce": "server-challenge"
            ])
        }
        defer { fixture.close() }
        try await AppStoreAccountClient(apiBaseURL: fixture.url, session: fixture.session).deleteAccount(
            payload: AppleAuthorizationPayload(identityToken: "apple-proof", authorizationCode: "fresh-code", nonce: "server-challenge"),
            accessToken: "sidey-access"
        )
    }

    func testDeletionDoesNotTreatUndeletedResponseAsSuccess() async {
        let fixture = CommerceHTTPFixture(response: #"{"deleted":false,"appleCredentialRevoked":false}"#)
        defer { fixture.close() }
        do {
            try await AppStoreAccountClient(apiBaseURL: fixture.url, session: fixture.session).deleteAccount(
                payload: AppleAuthorizationPayload(identityToken: "proof", authorizationCode: "code", nonce: "challenge"),
                accessToken: "sidey-access"
            )
            XCTFail("An undeleted account must not clear local credentials")
        } catch {
            XCTAssertTrue(error is AppStoreAccountError)
        }
    }

    func testRejectedAppleIdentityCannotCompleteDeletion() async {
        let fixture = CommerceHTTPFixture(status: 403, response: #"{"code":"apple_identity_mismatch"}"#)
        defer { fixture.close() }
        do {
            try await AppStoreAccountClient(apiBaseURL: fixture.url, session: fixture.session).deleteAccount(
                payload: AppleAuthorizationPayload(identityToken: "unlinked-identity", authorizationCode: "fresh-code", nonce: "challenge"),
                accessToken: "sidey-access"
            )
            XCTFail("An unlinked Apple identity must not complete account deletion")
        } catch {
            XCTAssertTrue(error is AppStoreAccountError)
        }
    }

    func testExpiredSideySessionReturnsToAuthenticationInsteadOfCompletingDeletion() async {
        let fixture = CommerceHTTPFixture(status: 401, response: #"{"code":"unauthorized"}"#)
        defer { fixture.close() }
        do {
            try await AppStoreAccountClient(apiBaseURL: fixture.url, session: fixture.session).deleteAccount(
                payload: AppleAuthorizationPayload(identityToken: "apple-proof", authorizationCode: "fresh-code", nonce: "challenge"),
                accessToken: "revoked-sidey-access"
            )
            XCTFail("A rejected SIDEY session must not complete account deletion")
        } catch {
            XCTAssertEqual(error as? SideyBackendError, .sessionRecoveryFailed)
        }
    }

    func testTransactionUsesSideyEndpointAndDecodesCanonicalRefund() async throws {
        let fixture = CommerceHTTPFixture(
            response: #"{"transactionId":"1234","entitlementKey":"character:cat","entitlementStatus":"refunded","bindingState":"bound"}"#
        ) { request in
            XCTAssertEqual(request.url?.path, "/api/app-store/transactions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sidey-access")
            XCTAssertEqual(CommerceHTTPFixture.body(request), ["signedTransactionInfo": "apple-signed-data"])
        }
        defer { fixture.close() }
        let result = try await AppStoreTransactionClient(apiBaseURL: fixture.url, session: fixture.session)
            .submit(signedTransactionInfo: "apple-signed-data", accessToken: { "sidey-access" })
        XCTAssertEqual(result.transactionId, "1234")
        XCTAssertEqual(result.entitlementKey, "character:cat")
        XCTAssertEqual(result.entitlementStatus, "refunded")
        XCTAssertEqual(result.bindingState, "bound")
    }

    func testRejectedTransactionCannotGrantOwnership() async {
        let fixture = CommerceHTTPFixture(status: 403, response: #"{"code":"app_account_token_mismatch"}"#)
        defer { fixture.close() }
        do {
            _ = try await AppStoreTransactionClient(apiBaseURL: fixture.url, session: fixture.session)
                .submit(signedTransactionInfo: "signed", accessToken: { "sidey-access" })
            XCTFail("Provider rejection must fail the purchase")
        } catch {
            XCTAssertTrue(error is AppStorePurchaseError)
        }
    }

    func testUnknownEntitlementStateCannotBeAccepted() async {
        let fixture = CommerceHTTPFixture(
            response: #"{"transactionId":"1234","entitlementKey":"character:cat","entitlementStatus":"client-approved","bindingState":"bound"}"#
        )
        defer { fixture.close() }
        do {
            _ = try await AppStoreTransactionClient(apiBaseURL: fixture.url, session: fixture.session)
                .submit(signedTransactionInfo: "signed", accessToken: { "sidey-access" })
            XCTFail("Unknown server state must fail closed")
        } catch {
            XCTAssertTrue(error is AppStorePurchaseError)
        }
    }

    func testEachTransactionSubmissionObtainsCurrentToken() async throws {
        let tokens = CommerceTokenSource()
        let observed = CommerceTokenObservation()
        let fixture = CommerceHTTPFixture(
            response: #"{"transactionId":"1234","entitlementKey":"character:cat","entitlementStatus":"active","bindingState":"bound"}"#
        ) { request in observed.append(request.value(forHTTPHeaderField: "Authorization") ?? "") }
        defer { fixture.close() }
        let client = AppStoreTransactionClient(apiBaseURL: fixture.url, session: fixture.session)
        _ = try await client.submit(signedTransactionInfo: "first", accessToken: { await tokens.next() })
        _ = try await client.submit(signedTransactionInfo: "restored", accessToken: { await tokens.next() })
        XCTAssertEqual(observed.values, ["Bearer sidey-1", "Bearer sidey-2"])
    }
}

private actor CommerceTokenSource {
    private var generation = 0
    func next() -> String { generation += 1; return "sidey-\(generation)" }
}

private final class CommerceTokenObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    func append(_ token: String) { lock.withLock { stored.append(token) } }
    var values: [String] { lock.withLock { stored } }
}

private final class CommerceHTTPFixture: @unchecked Sendable {
    let url = URL(string: "https://\(UUID().uuidString.lowercased()).invalid/api")!
    let session: URLSession
    let status: Int
    let response: Data
    let observe: @Sendable (URLRequest) -> Void

    init(status: Int = 200, response: String, observe: @escaping @Sendable (URLRequest) -> Void = { _ in }) {
        self.status = status
        self.response = Data(response.utf8)
        self.observe = observe
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CommerceURLProtocol.self]
        session = URLSession(configuration: configuration)
        CommerceURLProtocol.registry.add(self)
    }

    func close() {
        session.invalidateAndCancel()
        CommerceURLProtocol.registry.remove(url.host!)
    }

    static func body(_ request: URLRequest) -> [String: String]? {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: String]
    }
}

private final class CommerceFixtureRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var fixtures: [String: CommerceHTTPFixture] = [:]
    func add(_ fixture: CommerceHTTPFixture) { lock.withLock { fixtures[fixture.url.host!] = fixture } }
    func remove(_ host: String) { _ = lock.withLock { fixtures.removeValue(forKey: host) } }
    func get(_ host: String) -> CommerceHTTPFixture? { lock.withLock { fixtures[host] } }
}

private final class CommerceURLProtocol: URLProtocol, @unchecked Sendable {
    static let registry = CommerceFixtureRegistry()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix(".invalid") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let fixture = Self.registry.get(request.url!.host!) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        fixture.observe(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: fixture.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: fixture.response)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
