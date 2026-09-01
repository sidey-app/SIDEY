import CryptoKit
import ImageIO
import XCTest
@testable import SIDEY

final class PixelHamsterAssetTests: XCTestCase {
    private let expectedHashes = [
        "pixel_hamster": "43171c1dd614629058b6d593c57ca0e5841b0be03a04a05181dfda67c53a7f45",
        "pixel_cat": "d8b370c03b5cf0ede6aa0d9fa6210030e164b015a920622e89ae86f835e018b2",
        "pixel_puppy": "8f56a5fda51a224802f41d6d1c359a138c83036b7da3e0a35777f9f4ed38d5f7",
        "pixel_rabbit": "f8e53749200a284f7729ea9baac3237a9fac0caf8efedf9102dcee065e521342",
        "pixel_penguin": "f171503f8ffb938732583a4b6f42443e7a69120bb17496f6e8d34372da2ea886",
        "pixel_starlight_upalupa": "d180810a8796280077f3f70f6da681888c583c2f8d74776d0f5d300e943a079a"
    ]

    func testAllRuntimeSheetsAreTen24PixelFramesWithAlphaAndStableHashes() throws {
        XCTAssertEqual(PixelCharacterCatalog.all.count, 6)
        for character in PixelCharacterCatalog.all {
            let url = try XCTUnwrap(character.assetURL(), character.id)
            let data = try Data(contentsOf: url)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let properties = try XCTUnwrap(
                CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            )
            XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 240, character.id)
            XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 24, character.id)
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertNotEqual(image.alphaInfo, .none, character.id)
            XCTAssertEqual(SHA256.hash(data: data).hex, expectedHashes[character.id], character.id)
        }
        XCTAssertEqual(PixelCharacterAsset.frameCount, 10)
        XCTAssertEqual(PixelCharacterAsset.framePixelSize, CGSize(width: 24, height: 24))
    }

    func testEveryFrameSharesTheSameLowestOpaquePixelBaseline() throws {
        for character in PixelCharacterCatalog.all {
            let url = try XCTUnwrap(character.assetURL())
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let width = image.width
            let height = image.height
            var rgba = [UInt8](repeating: 0, count: width * height * 4)
            try rgba.withUnsafeMutableBytes { bytes in
                let context = try XCTUnwrap(CGContext(
                    data: bytes.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue
                ))
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }

            let baselines = (0..<PixelCharacterCatalog.frameCount).map { frame -> Int in
                var lowestMemoryRow = Int.min
                for y in 0..<height {
                    for x in (frame * 24)..<((frame + 1) * 24) {
                        if rgba[(y * width + x) * 4 + 3] > 0 {
                            lowestMemoryRow = max(lowestMemoryRow, y)
                        }
                    }
                }
                return height - 1 - lowestMemoryRow
            }
            XCTAssertEqual(Set(baselines).count, 1, "\(character.id): \(baselines)")
            XCTAssertEqual(baselines.first, PixelCharacterCatalog.footBaselinePixel, character.id)
        }
    }

    func testCatalogAndFallbackContracts() {
        XCTAssertEqual(PixelCharacterCatalog.all.map(\.id), [
            "pixel_hamster", "pixel_cat", "pixel_puppy", "pixel_rabbit", "pixel_penguin",
            "pixel_starlight_upalupa"
        ])
        XCTAssertEqual(PixelCharacterCatalog.free.count, 5)
        XCTAssertFalse(PixelCharacterCatalog.canSelect(
            PixelCharacterCatalog.pixelStarlightUpalupaID,
            entitlementKeys: []
        ))
        XCTAssertTrue(PixelCharacterCatalog.canSelect(
            PixelCharacterCatalog.pixelStarlightUpalupaID,
            entitlementKeys: [PixelCharacterCatalog.starlightUpalupaEntitlementKey]
        ))
        XCTAssertEqual(PixelCharacterCatalog.definition(
            for: PixelCharacterCatalog.pixelStarlightUpalupaID
        ).sparkleEffect, .starlight)
        XCTAssertTrue(PixelCharacterCatalog.definition(
            for: PixelCharacterCatalog.pixelStarlightUpalupaID
        ).mirrorsToMovementDirection)
        XCTAssertTrue(PixelCharacterCatalog.free.allSatisfy {
            !$0.mirrorsToMovementDirection
        })
        XCTAssertEqual(PixelSparkleEffect.starlight.ambientDelay, 1.0...1.4)
        XCTAssertEqual(PixelSparkleEffect.starlight.ambientDuration, 1.05)
        XCTAssertEqual(PixelSparkleEffect.starlight.ambientCount, 4...6)
        XCTAssertEqual(PixelSparkleEffect.starlight.ambientRadius, 2.6...4.0)
        XCTAssertEqual(PixelSparkleEffect.starlight.centralFlashDuration, 0.32)
        XCTAssertEqual(PixelSparkleEffect.starlight.centralFlashRadius, 34)
        XCTAssertEqual(PixelSparkleEffect.starlight.pulseWaves.map(\.count), [18, 24])
        XCTAssertEqual(PixelSparkleEffect.starlight.pulseWaves.map(\.distance), [126...168, 82...132])
        XCTAssertEqual(PixelSparkleEffect.starlight.pulseWaves.map(\.radius), [8...13, 4.5...8])
        XCTAssertEqual(PixelSparkleEffect.starlight.pulseCount, 42)
        XCTAssertEqual(PixelSparkleEffect.starlight.pulseDuration, 0.84, accuracy: 0.001)
        XCTAssertEqual(PixelCharacterCatalog.canonicalID(for: "minty_pup"), "pixel_hamster")
        XCTAssertEqual(PixelCharacterCatalog.canonicalID(for: "pixel_cat"), "pixel_cat")
        XCTAssertEqual(PixelCharacterCatalog.canonicalID(for: "unknown"), "pixel_hamster")
        XCTAssertEqual(PixelCharacterCatalog.definition(for: "unknown").displayName, "아기 햄스터")
        for character in PixelCharacterCatalog.all {
            XCTAssertEqual(character.frames, .standard)
        }
    }
}

private extension Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
