import XCTest
@testable import SIDEY

final class RuntimeConfigurationTests: XCTestCase {
    func testAcceptsCompleteHTTPSPublishableConfiguration() throws {
        let configuration = try RuntimeConfiguration.resolve(environment: [
            "SIDEY_SUPABASE_URL": "https://example.supabase.co",
            "SIDEY_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_public"
        ])

        XCTAssertEqual(configuration.supabaseURL.absoluteString, "https://example.supabase.co")
        XCTAssertEqual(configuration.supabasePublishableKey, "sb_publishable_public")
        XCTAssertFalse(configuration.backendFingerprint.isEmpty)
    }

    func testRejectsPartialInsecureAndSecretConfiguration() {
        XCTAssertThrowsError(try RuntimeConfiguration.resolve(environment: [
            "SIDEY_SUPABASE_URL": "https://example.supabase.co"
        ]))
        XCTAssertThrowsError(try RuntimeConfiguration.resolve(environment: [
            "SIDEY_SUPABASE_URL": "http://example.supabase.co",
            "SIDEY_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_public"
        ]))
        XCTAssertThrowsError(try RuntimeConfiguration.resolve(environment: [
            "SIDEY_SUPABASE_URL": "https://example.supabase.co",
            "SIDEY_SUPABASE_PUBLISHABLE_KEY": "sb_secret_do-not-ship"
        ]))
    }
}
