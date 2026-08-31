import XCTest
@testable import SIDEY

@MainActor
final class AppUpdateControllerTests: XCTestCase {
    func testHostBundleRequiresSignedSparkleUpdates() throws {
        let info = Bundle.main.infoDictionary

        XCTAssertEqual(
            info?["SUFeedURL"] as? String,
            "https://raw.githubusercontent.com/sidey-app/SIDEY/main/updates/appcast.xml"
        )
        XCTAssertEqual(
            info?["SUPublicEDKey"] as? String,
            "n1AfFmJpRxNkuGIAJsBAV029uvzF7t3ejRD+OY246C0="
        )
        XCTAssertEqual(info?["SURequireSignedFeed"] as? Bool, true)
        XCTAssertEqual(info?["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
        XCTAssertEqual(info?["SIDEYReleaseChannel"] as? String, "development")
        XCTAssertEqual(info?["CFBundleDisplayName"] as? String, "Sidey-dev")
    }

    func testProductionSparkleControllerCanBeCreatedWithoutStartingNetworkChecks() {
        let controller = SparkleUpdateController(
            releaseChannel: .production,
            startingUpdater: false
        )

        XCTAssertFalse(controller.canCheckForUpdates)
    }

    func testDevelopmentChannelDoesNotStartOrExposeSparkleUpdater() {
        let controller = SparkleUpdateController(
            releaseChannel: .development,
            startingUpdater: true
        )

        XCTAssertFalse(controller.canCheckForUpdates)
        controller.checkForUpdates()
    }

    func testUnknownReleaseChannelIsRejected() {
        XCTAssertNil(AppReleaseChannel(rawValue: "preview"))
    }
}
