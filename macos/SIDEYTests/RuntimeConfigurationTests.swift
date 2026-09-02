import XCTest
@testable import SIDEY

final class RuntimeConfigurationTests: XCTestCase {
    func testAuthCallbackSeparatesProductionAndDevelopmentSchemes() {
        let productionURL = SideyAuthCallback.callbackURL(scheme: "sidey")
        let developmentURL = SideyAuthCallback.callbackURL(scheme: "sidey-dev")

        XCTAssertEqual(productionURL.absoluteString, "sidey://auth/google")
        XCTAssertEqual(developmentURL.absoluteString, "sidey-dev://auth/google")
        XCTAssertTrue(SideyAuthCallback.matches(developmentURL, scheme: "sidey-dev"))
        XCTAssertFalse(SideyAuthCallback.matches(productionURL, scheme: "sidey-dev"))
    }

    func testAcceptsCompleteHTTPSPublishableConfiguration() throws {
        let configuration = try RuntimeConfiguration.resolve(releaseChannel: .development, environment: [
            "SIDEY_SUPABASE_URL": "https://example.supabase.co",
            "SIDEY_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_public"
        ])

        XCTAssertEqual(configuration.supabaseURL.absoluteString, "https://example.supabase.co")
        XCTAssertEqual(configuration.supabasePublishableKey, "sb_publishable_public")
        XCTAssertFalse(configuration.backendFingerprint.isEmpty)
    }

    func testRejectsPartialInsecureAndSecretConfiguration() {
        XCTAssertThrowsError(try RuntimeConfiguration.resolve(releaseChannel: .development, environment: [
            "SIDEY_SUPABASE_URL": "https://example.supabase.co"
        ]))
        XCTAssertThrowsError(try RuntimeConfiguration.resolve(releaseChannel: .development, environment: [
            "SIDEY_SUPABASE_URL": "http://example.supabase.co",
            "SIDEY_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_public"
        ]))
        XCTAssertThrowsError(try RuntimeConfiguration.resolve(releaseChannel: .development, environment: [
            "SIDEY_SUPABASE_URL": "https://example.supabase.co",
            "SIDEY_SUPABASE_PUBLISHABLE_KEY": "sb_secret_do-not-ship"
        ]))
        XCTAssertThrowsError(try RuntimeConfiguration.resolve(releaseChannel: .development, environment: [
            "SIDEY_SUPABASE_URL": "https://example.supabase.co",
            "SIDEY_SUPABASE_PUBLISHABLE_KEY": "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.signature"
        ]))
    }

    func testAllowsHTTPOnlyForLoopbackDevelopment() throws {
        for host in ["localhost", "127.0.0.1", "[::1]"] {
            let configuration = try RuntimeConfiguration.resolve(releaseChannel: .development, environment: [
                "SIDEY_SUPABASE_URL": "http://\(host):54321",
                "SIDEY_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_local"
            ])
            XCTAssertEqual(configuration.supabaseURL.scheme, "http")
        }
        XCTAssertThrowsError(try RuntimeConfiguration.resolve(releaseChannel: .development, environment: [
            "SIDEY_SUPABASE_URL": "http://192.168.0.10:54321",
            "SIDEY_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_local"
        ]))
    }

    func testDevelopmentRejectsProductionAndMissingConfiguration() {
        XCTAssertThrowsError(try RuntimeConfiguration.resolve(
            releaseChannel: .development,
            environment: [:],
            bundleInfo: [:]
        ))
        XCTAssertThrowsError(try RuntimeConfiguration.resolve(
            releaseChannel: .development,
            environment: [
                "SIDEY_SUPABASE_URL": "https://whtejsviizgejauasqqt.supabase.co",
                "SIDEY_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_public"
            ],
            bundleInfo: [:]
        ))
    }

    func testProductionIgnoresInjectedBackendConfiguration() throws {
        let configuration = try RuntimeConfiguration.resolve(
            releaseChannel: .production,
            environment: [
                "SIDEY_SUPABASE_URL": "https://attacker.example",
                "SIDEY_SUPABASE_PUBLISHABLE_KEY": "sb_secret_do-not-ship"
            ],
            bundleInfo: [:]
        )

        XCTAssertTrue(configuration.isProductionBackend)
    }
}
