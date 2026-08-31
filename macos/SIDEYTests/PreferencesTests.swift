import XCTest
@testable import SIDEY

final class PreferencesTests: XCTestCase {
    func testPreferencesRoundTrip() throws {
        var value = AppPreferences.defaults
        value.hasShownNativeLanding = true
        value.overlayVisible = false
        value.quietModeEnabled = true
        value.showOfflineMembers = false
        value.selectedCharacterID = "pixel_penguin"
        value.overlayRegion = OverlayRegionPreference(
            edge: .right,
            span: .half,
            screenIdentifier: "display:42"
        )
        value.overlayFrame = CodableRect(CGRect(x: 120, y: 80, width: 720, height: 360))
        value.overlayScreenIdentifier = "display:42"

        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(AppPreferences.self, from: data), value)
    }

    func testVersionOnePreferencesDecodeWithoutDroppingExistingValues() throws {
        let json = #"{"schemaVersion":1,"hasShownNativeLanding":true,"onboardingComplete":true,"overlayVisible":false,"overlayLocked":false,"overlayScale":1.8,"nickname":"민지"}"#
        let value = try JSONDecoder().decode(AppPreferences.self, from: Data(json.utf8))

        XCTAssertTrue(value.hasShownNativeLanding)
        XCTAssertTrue(value.onboardingComplete)
        XCTAssertFalse(value.overlayVisible)
        XCTAssertFalse(value.overlayLocked)
        XCTAssertEqual(value.overlayScale, 1.8)
        XCTAssertFalse(value.launchAtLogin)
        XCTAssertFalse(value.quietModeEnabled)
        XCTAssertNil(value.overlayScreenIdentifier)
        XCTAssertEqual(value.schemaVersion, AppPreferences.currentSchemaVersion)
        XCTAssertEqual(value.overlayRegion.edge, .bottom)
        XCTAssertEqual(value.overlayRegion.span, .full)
        XCTAssertTrue(value.showOfflineMembers)
        XCTAssertEqual(value.nickname, "민지")
        XCTAssertEqual(value.selectedCharacterID, "pixel_hamster")
    }

    func testLegacyScreenIdentifierMigratesIntoBottomFullRegion() throws {
        let json = #"{"schemaVersion":4,"overlayScreenIdentifier":"2560x1440@2.000"}"#
        let value = try JSONDecoder().decode(AppPreferences.self, from: Data(json.utf8))

        XCTAssertEqual(value.overlayRegion.edge, .bottom)
        XCTAssertEqual(value.overlayRegion.span, .full)
        XCTAssertEqual(value.overlayRegion.screenIdentifier, "2560x1440@2.000")
    }
}
