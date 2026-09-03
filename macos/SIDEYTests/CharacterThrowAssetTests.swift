import CryptoKit
import ImageIO
import XCTest
@testable import SIDEY

final class CharacterThrowAssetTests: XCTestCase {
    private let actionHashes = [
        "pixel_hamster": "b9915afdbb5476b17ea7b7f0a06eea09cc20b96dd1995328bdae2f806c3285c8",
        "pixel_cat": "128e020aab718d8d45e81f599c221467b46f27aa809c45b1d873580cdaffcc62",
        "pixel_puppy": "38d2858c97b456be17f34fd6b93df862e9c0d3b72e5592bb0e625e64110c5744",
        "pixel_rabbit": "f641ebbba64e8c23d33173ff04d4907d3e15955024dd72e3f6e7d9b3e20fec84",
        "pixel_penguin": "7ee5ea2b90994400a1b4dd252ed2affb095416597422a8ef4cb0ae54b3fb7f77",
        "pixel_guinea_pig": "384157773baa55bd4a5f8586d179ab7eb43f42fb4204c306490784551e38ae1d",
        "pixel_monkey": "059a288dde75695febec8a42303dc63f126636b094e3896b795b6a4ac1cce39a",
        "pixel_chinchilla": "a6dd2b4f1837812bc9fd0d979fe379c4362ed8018b9d5e6991e5c28d53265b02",
        "pixel_starlight_upalupa": "7a9bae8b1359f432857e026c972e3bc99777539ce7cfff89bc01e95d1938de75"
    ]
    private let objectHashes = [
        "patch_soft_ball": "cdde7f417c5d8d82d0f4df6b03fa8e7d494d98a37d75aa66699505d7c87c53fe",
        "mini_paprika": "85b8d0525a865e531882a736561e9b7c4fbb6a2c3f80d91b456c4c4a7425724d",
        "banana": "9cfca454ff6305fdd374c08f64c3c21e3af278166ffe15f7f81a183bb214f138",
        "dust_bath_pouch": "b68022f5fe1a1a6a57fe56a01f73bae3d14b27d76f2dcbf10c6686b979634a65",
        "starlight_orb": "08cf8ec8dc680ae07dcd83de9d56948873445470c6b15b5ad22e770f4277984c"
    ]

    func testApprovedActionSheetsAreBundledAtExactSizeAndHash() throws {
        for (id, hash) in actionHashes {
            try assertAsset(
                url: PixelCharacterThrowCatalog.actionAssetURL(for: id),
                size: CGSize(width: 192, height: 24),
                hash: hash,
                label: id
            )
        }
    }

    func testApprovedObjectSheetsAreBundledAtExactSizeAndHash() throws {
        for (id, hash) in objectHashes {
            try assertAsset(
                url: PixelCharacterThrowCatalog.objectAssetURL(for: id),
                size: CGSize(width: 192, height: 16),
                hash: hash,
                label: id
            )
        }
    }

    private func assertAsset(url: URL?, size: CGSize, hash: String, label: String) throws {
        let url = try XCTUnwrap(url, label)
        let data = try Data(contentsOf: url)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, Int(size.width), label)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, Int(size.height), label)
        XCTAssertEqual(SHA256.hash(data: data).hex, hash, label)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertNotEqual(image.alphaInfo, .none, label)
    }
}

private extension Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
