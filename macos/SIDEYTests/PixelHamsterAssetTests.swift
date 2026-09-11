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
        "pixel_guinea_pig": "1a0bf85dae86f2e6bb460e8b0b852c2bd010d5ff6f7efd1477cbd6986da64f5b",
        "pixel_monkey": "515fe377f5344dd4cbaa2b0faf58de3ce72fdc62be5aff6a9d9de683983c783b",
        "pixel_chinchilla": "c0009e007a7a63029fb58ad6f94d2b9a8c9ae7a55f139dd4892050f11614c5d4",
        "pixel_starlight_upalupa": "d180810a8796280077f3f70f6da681888c583c2f8d74776d0f5d300e943a079a",
        "pixel_poop": "4ad6f2f5e7f21530d442cdc8c2576fb3e346fa7c169c1bf2eef0a76a1dcd260a",
        "pixel_capybara": "619ff8a14df04676741d9e0a9e1fa360e0fbd70ab11486b16164052f6f6f2623",
        "pixel_hedgehog": "1425bc90448ca4d072a8002b154373bd4130f307ae960e6734f94f8d2d26ac0a",
        "pixel_unicorn": "3e059ccaf26840e06dfcca4ab2f5b3cce862476223e67c91b9e67644f0e02abc",
        "pixel_shiba": "298650cf84e4958a372f8e406d92365b66f2c9b185f1fc69b904ac2cd1dc5832",
        "pixel_salmon_sushi": "5a86a6babc1539dd9326635a79979c5f7105a2ae6497dbe8d7bd706bdecebe33",
        "pixel_grandpa": "49dbeec5c93856edc41f995e259db58837a0957cc445f28b380886fc2bfd11d9",
        "pixel_spider_hero": "9a00de9db8322671940c5457ad240acfbcc6c526d320071f402529262052390e",
        "pixel_crow": "ba7332e06a98ba9e72e184f07632d63c4d4d70666311b253dc45093b7fe1eb55",
        "pixel_kimchi": "f32635953218c5dbb5e556743b6d5827a07a40d2e6aff3d094b3c0999be95af9",
        "pixel_quokka": "ab2778d8d2f49cfccecebfdab629507a77c5b9515c85c0884cc82233358168f6",
        "pixel_red_panda": "0ea3f9a705b400448c091fb131417b1c525e08c5ab97a3eef577aa3dd4dc68a7",
        "pixel_otter": "8444567968f26b1940dad2148a386e5247db73162dbf7b84fca58e907ca4ff01",
        "pixel_duck": "117b9929cf75edcbf39c904a3b471944b00af48faae55e73a3986b82ed35092f",
        "pixel_panda": "7242d5d61e424382b8c8fe2f0c14fe5a96c06b55524025f2dfcf65a7c534286b",
        "pixel_frog": "9a0a3c779b65d4854702d27b864f8d439e2f566128360d5396d7481f8efebf30",
        "pixel_octopus": "525fdd8204da571d4d4c4bf9ce4171ee7ca49c9bcf8bde6d40f137f3b16c0f46",
        "pixel_bungeoppang": "01c351f7da5ac6262a10785accf789afbe873e37e85d22ff537a2af8c0246175",
        "pixel_fried_egg": "dd24d5960f3bdf1018a60af0c2ffcdd882890a99c1bd75201565e0772fba0bbb",
        "pixel_samgak_gimbap": "73de18fab969f390ad42beb0f4e958fca735dd5e2444b5371129fc898236b888",
        "pixel_tteokbokki": "dd302f7eeaed14ae33a970a37672a98458537f5c41920f644d6e6a0cfb04f26c",
        "pixel_avocado": "0dda7f52a818c154a6ec5e7e8dff0bc0f4353da52c39bf803a182dbb758823c5",
        "pixel_slime": "b617507db147821f92d54fd6c9327b4e942b87081cdbd716b4c44fd11e8ec7a8",
        "pixel_cactus_pot": "ca073da73856b4564f1059b79bef0977c31e79d498dd5bd8abdd67e6d176ed48",
        "pixel_tofu": "d7acd5a24ac008043c5fcd9a5b6b8058c5363000ee071a62912aff1c32a33ff9",
        "pixel_cup_ramen": "8c80b1d32a9bd9fecc19af4004af24cb6b9800069e0d46914379a7083e98c675",
        "pixel_grandma": "1fb62d27514270292af5f9cdc7b26ae1a7294160ee4c7948e914d563fbd5f1fe",
        "pixel_baby": "2977c30ec0ffe1d1b54ce985f3b6345a583ab09895c8fa5d9c4c9f4f48e65e35",
        "pixel_santa": "396a05bd704fae4720993dda6be0df2046de8d5364de62fee612398824b98856",
        "pixel_jungjiyu": "1739b168fa32e16559804bcad92703f5f22df7df567d5546413116cd965c649b"
    ]

    func testAllRuntimeSheetsAreTen24PixelFramesWithAlphaAndStableHashes() throws {
        XCTAssertEqual(PixelCharacterCatalog.all.count, 39)
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

    func testGuineaPigWalkFramesBobWithTwoFeetAndSafeEarMargin() throws {
        let character = PixelCharacterCatalog.definition(for: PixelCharacterCatalog.pixelGuineaPigID)
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

        var topOpaqueRows: [Int] = []
        var baselineRunCounts: [Int] = []
        for frame in character.frames.walk {
            for y in 0..<2 {
                for x in (frame * 24)..<((frame + 1) * 24) {
                    XCTAssertEqual(rgba[(y * width + x) * 4 + 3], 0, "walk frame \(frame), x=\(x), y=\(y)")
                }
            }

            let frameX = frame * 24
            let topRow = try XCTUnwrap((0..<height).first { y in
                (0..<24).contains { x in rgba[(y * width + frameX + x) * 4 + 3] > 0 }
            })
            topOpaqueRows.append(topRow)

            let baselineMemoryRow = height - 1 - PixelCharacterCatalog.footBaselinePixel
            var runCount = 0
            var wasOpaque = false
            for x in 0..<24 {
                let isOpaque = rgba[(baselineMemoryRow * width + frameX + x) * 4 + 3] > 0
                if isOpaque && !wasOpaque { runCount += 1 }
                wasOpaque = isOpaque
            }
            baselineRunCounts.append(runCount)
        }
        XCTAssertEqual(topOpaqueRows, [5, 4, 5, 4])
        XCTAssertEqual(baselineRunCounts, [2, 1, 2, 1])
    }

    func testCatalogAndFallbackContracts() {
        XCTAssertEqual(PixelCharacterCatalog.all.map(\.id), [
            "pixel_hamster", "pixel_cat", "pixel_puppy", "pixel_rabbit",
            "pixel_penguin", "pixel_guinea_pig", "pixel_monkey", "pixel_chinchilla",
            "pixel_starlight_upalupa", "pixel_poop", "pixel_capybara", "pixel_hedgehog",
            "pixel_unicorn", "pixel_shiba", "pixel_salmon_sushi", "pixel_grandpa",
            "pixel_spider_hero", "pixel_crow", "pixel_kimchi", "pixel_quokka",
            "pixel_red_panda", "pixel_otter", "pixel_duck", "pixel_panda",
            "pixel_frog", "pixel_octopus", "pixel_bungeoppang", "pixel_fried_egg",
            "pixel_samgak_gimbap", "pixel_tteokbokki", "pixel_avocado", "pixel_slime",
            "pixel_cactus_pot", "pixel_tofu", "pixel_cup_ramen", "pixel_grandma",
            "pixel_baby", "pixel_santa", "pixel_jungjiyu"
        ])
        XCTAssertEqual(PixelCharacterCatalog.free.count, 5)
        for character in PixelCharacterCatalog.all where character.entitlementKey != nil {
            XCTAssertFalse(PixelCharacterCatalog.canSelect(character.id, entitlementKeys: []))
            XCTAssertTrue(PixelCharacterCatalog.canSelect(
                character.id,
                entitlementKeys: [try! XCTUnwrap(character.entitlementKey)]
            ))
        }
        XCTAssertEqual(PixelCharacterCatalog.definition(
            for: PixelCharacterCatalog.pixelStarlightUpalupaID
        ).sparkleEffect, .starlight)
        XCTAssertTrue(PixelCharacterCatalog.definition(
            for: PixelCharacterCatalog.pixelStarlightUpalupaID
        ).mirrorsToMovementDirection)
        XCTAssertTrue(PixelCharacterCatalog.definition(
            for: PixelCharacterCatalog.pixelGuineaPigID
        ).mirrorsToMovementDirection)
        XCTAssertEqual(
            PixelCharacterCatalog.canonicalID(for: PixelCharacterCatalog.legacyPixelKoalaID),
            PixelCharacterCatalog.pixelChinchillaID
        )
        XCTAssertEqual(
            PixelCharacterCatalog.definition(for: PixelCharacterCatalog.legacyPixelKoalaID).displayName,
            "아기 친칠라"
        )
        XCTAssertTrue(PixelCharacterCatalog.free.allSatisfy { !$0.mirrorsToMovementDirection })
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

    func testBlinkingCharactersFlashASecondIdleFrameThatIsMoreThanABodyLift() throws {
        let blinking = PixelCharacterCatalog.all
            .filter { $0.idleTiming == .blinking }
            .map(\.id)
        XCTAssertEqual(blinking, [
            "pixel_poop", "pixel_capybara", "pixel_hedgehog", "pixel_unicorn",
            "pixel_shiba", "pixel_salmon_sushi", "pixel_grandpa", "pixel_spider_hero",
            "pixel_crow", "pixel_kimchi", "pixel_quokka", "pixel_red_panda",
            "pixel_otter", "pixel_duck", "pixel_panda", "pixel_frog",
            "pixel_octopus", "pixel_bungeoppang", "pixel_fried_egg", "pixel_samgak_gimbap",
            "pixel_tteokbokki", "pixel_avocado", "pixel_slime", "pixel_cactus_pot",
            "pixel_tofu", "pixel_cup_ramen", "pixel_grandma", "pixel_baby",
            "pixel_santa", "pixel_jungjiyu"
        ])
        XCTAssertEqual(PixelCharacterIdleTiming.breathing.restDuration, 0.55)
        XCTAssertEqual(PixelCharacterIdleTiming.breathing.accentDuration, 0.55)
        XCTAssertEqual(PixelCharacterIdleTiming.blinking.restDuration, 2.4)
        XCTAssertEqual(PixelCharacterIdleTiming.blinking.accentDuration, 0.3)
        XCTAssertEqual(
            PixelCharacterIdleTiming.blinking.frameDurations(frameCount: 2),
            [2.4, 0.3]
        )
        XCTAssertEqual(PixelCharacterIdleTiming.breathing.frameDurations(frameCount: 0), [])

        for character in PixelCharacterCatalog.all where character.idleTiming == .blinking {
            let (rgba, width, height) = try sheetPixels(character)
            let rest = character.frames.idle.lowerBound
            let accent = rest + 1
            // A breathing sheet repeats the rest frame one pixel higher. A blink has to
            // change something else, so the two frames must not line up under that shift.
            var isOnlyABodyLift = true
            // Rows above the body's lowest line only; the feet do not move with the lift.
            for row in 0..<(height - 2 - PixelCharacterCatalog.footBaselinePixel) {
                for x in 0..<24 {
                    let accentOffset = ((row * width) + accent * 24 + x) * 4
                    let restOffset = (((row + 1) * width) + rest * 24 + x) * 4
                    if Array(rgba[accentOffset..<(accentOffset + 4)])
                        != Array(rgba[restOffset..<(restOffset + 4)]) {
                        isOnlyABodyLift = false
                    }
                }
            }
            XCTAssertFalse(isOnlyABodyLift, character.id)
        }
    }

    private func sheetPixels(
        _ character: PixelCharacterDefinition
    ) throws -> (rgba: [UInt8], width: Int, height: Int) {
        let url = try XCTUnwrap(character.assetURL(), character.id)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var rgba = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return (rgba, image.width, image.height)
    }
}

private extension Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
