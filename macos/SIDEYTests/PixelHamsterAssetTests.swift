import ImageIO
import XCTest
@testable import SIDEY

final class PixelHamsterAssetTests: XCTestCase {
    func testRuntimeSheetIsEight24PixelFramesWithAlpha() throws {
        let url = try XCTUnwrap(PixelHamsterAsset.url())
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )

        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 192)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 24)
        XCTAssertEqual(PixelHamsterAsset.frameCount, 8)
        XCTAssertEqual(PixelHamsterAsset.framePixelSize, CGSize(width: 24, height: 24))
        let hasAlpha = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            .alphaInfo != .none
        XCTAssertTrue(hasAlpha)
    }

    func testLegacyMintyProfileUsesPixelHamsterAlias() {
        XCTAssertEqual(PixelCharacterCatalog.canonicalID(for: "minty_pup"), "pixel_hamster")
        XCTAssertEqual(PixelCharacterCatalog.canonicalID(for: "pixel_hamster"), "pixel_hamster")
    }
}
