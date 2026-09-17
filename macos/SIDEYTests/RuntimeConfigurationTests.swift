import CryptoKit
import Foundation
import XCTest
#if APP_STORE
@testable import SIDEYAppStore
#else
@testable import SIDEY
#endif

final class RuntimeConfigurationTests: XCTestCase {
    func testAuthCallbackSeparatesOldProductionAndDevelopmentSchemes() {
        XCTAssertTrue(SideyAuthCallback.matches(SideyAuthCallback.callbackURL(scheme: "sidey-dev"), scheme: "sidey-dev"))
        XCTAssertFalse(SideyAuthCallback.matches(SideyAuthCallback.callbackURL(scheme: "sidey"), scheme: "sidey-dev"))
    }
    func testDevelopmentAcceptsAPIWithoutSupabaseConfiguration() throws {
        let value = try RuntimeConfiguration.resolve(releaseChannel: .development,
            environment: ["SIDEY_API_BASE_URL": "https://staging.sidey.app/api"], bundleInfo: [:])
        XCTAssertEqual(value.apiBaseURL.absoluteString, "https://staging.sidey.app/api")
        XCTAssertNotEqual(value.backendFingerprint, value.legacyBackendFingerprint)
    }
    func testLegacyFingerprintPreservesExactExistingKeychainAccount() throws {
        let value = RuntimeConfiguration(apiBaseURL: URL(string: "https://staging.sidey.app/api")!)
        let oldURL = "https://whtejsviizgejauasqqt.supabase.co"
        let oldFingerprint = SHA256.hash(data: Data(oldURL.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(value.legacyBackendFingerprint, oldFingerprint)
    }
    func testAPIBaseRequiresContractPathButLegacyOriginRemainsValid() throws {
        for raw in ["https://staging.sidey.app", "https://staging.sidey.app/other", "https://staging.sidey.app/api/nested"] {
            XCTAssertThrowsError(try RuntimeConfiguration.resolve(releaseChannel: .development,
                environment: ["SIDEY_API_BASE_URL": raw], bundleInfo: [:]))
        }
        let configuration = try RuntimeConfiguration.resolve(releaseChannel: .development,
            environment: ["SIDEY_API_BASE_URL": "http://localhost:8080/api/",
                          "SIDEY_LEGACY_SUPABASE_URL": "https://legacy.example",
                          "SIDEY_LEGACY_SUPABASE_PUBLISHABLE_KEY": "public-key"], bundleInfo: [:])
        XCTAssertEqual(configuration.legacySupabaseURL.host, "legacy.example")
    }

    func testDevelopmentRejectsMissingProductionAndUntrustedURLs() {
        for raw in ["", "http://staging.sidey.app/api", "https://api.sidey.app/api",
                    "https://user:password@staging.sidey.app/api", "https://staging.sidey.app/api?query=1",
                    "https://staging.sidey.app/api#fragment"] {
            XCTAssertThrowsError(try RuntimeConfiguration.resolve(releaseChannel: .development,
                environment: ["SIDEY_API_BASE_URL": raw], bundleInfo: [:]))
        }
    }
    func testDevelopmentLoopbackAndExplicitLegacyConfiguration() throws {
        for host in ["localhost", "127.0.0.1", "[::1]"] {
            let value = try RuntimeConfiguration.resolve(releaseChannel: .development,
                environment: ["SIDEY_API_BASE_URL": "http://\(host):8080/api"], bundleInfo: [:])
            XCTAssertEqual(value.apiBaseURL.scheme, "http")
        }
        XCTAssertThrowsError(try RuntimeConfiguration.resolve(releaseChannel: .development,
            environment: ["SIDEY_API_BASE_URL": "http://localhost:8080/api",
                          "SIDEY_LEGACY_SUPABASE_URL": "https://legacy.example",
                          "SIDEY_LEGACY_SUPABASE_PUBLISHABLE_KEY": "sb_secret_do-not-ship"], bundleInfo: [:]))
    }
    func testProductionIgnoresEnvironmentForBothDistributions() throws {
        for channel in [AppReleaseChannel.production, .appStore] {
            let value = try RuntimeConfiguration.resolve(releaseChannel: channel,
                environment: ["SIDEY_API_BASE_URL": "https://attacker.example/api", "SIDEY_GOOGLE_CLIENT_ID": "attacker"], bundleInfo: [:])
            XCTAssertTrue(value.isProductionBackend)
            XCTAssertEqual(value.apiBaseURL.absoluteString, "https://api.sidey.app/api")
            XCTAssertTrue(value.googleClientID.isEmpty)
        }
    }
    func testBundledGoogleAndProductionEndpointConfiguration() throws {
        let value = try RuntimeConfiguration.resolve(releaseChannel: .production, environment: [:],
            bundleInfo: ["SIDEYAPIBaseURL": "https://api.sidey.app/api", "SIDEYGoogleClientID": "public-desktop-client"])
        XCTAssertEqual(value.googleClientID, "public-desktop-client")
    }
}
