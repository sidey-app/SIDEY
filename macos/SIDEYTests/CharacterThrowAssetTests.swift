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
        "pixel_starlight_upalupa": "7a9bae8b1359f432857e026c972e3bc99777539ce7cfff89bc01e95d1938de75",
        "pixel_poop": "c12e2c24a39a5218d0d86a8b5b028fe77fe1c34f332c031635f6abe1e1a5d3d3",
        "pixel_capybara": "1a28fb610a5ed4f3597abe7c93934a8ebba63cc1149efb829e29262814814ead",
        "pixel_hedgehog": "6ee2f4e351a2f9776c1c2b4b8996bc9efec760b31c70816472175138cd6fbe8f",
        "pixel_unicorn": "6520e4a7b3e3daf6b9386b0b8767747f0a2bca8601877654ad3849016f30acb6",
        "pixel_shiba": "b5c8623ba9f4e2b5fd0a83e29d7ac8aff7a9f6bc4b60981bd6e2423bdcb4a9b1",
        "pixel_salmon_sushi": "0256b526b15dd28e5c7d99449a8dfcad96c129aba75bf445788e10c3829e48a8",
        "pixel_grandpa": "4750f05abdcf2aa35b3ee67c61bb15a3e19e5740f97184fb48cd3d62f2890fa2",
        "pixel_spider_hero": "f88240cc985cc9007288cd2a17d5da3d35759160793ab572da29304f92f8acf3",
        "pixel_crow": "18c071da87650d54a8b8f081c4e1ba63048f5174ee8e23398e990282ac63c5c8",
        "pixel_kimchi": "01465eab41387ea7092606e311a3d84cf8504886ab949c734b45fe061ef35098",
        "pixel_quokka": "c9fcbcc9baf8be73dc6e950edabf73198d57ec2edc63502a5b315fe6274777d4",
        "pixel_red_panda": "d1014a9d2b57311148afbbb0a899fd9acbf8fdd2d82549c3ef0265d7110e8f80",
        "pixel_otter": "f5a25ab6c649f680ab53726ea44f007de9487ca1e8de9892f7688506bfd26486",
        "pixel_duck": "a5174ecf98c8249d569f0fb8230bd8414decf5e6f7713c42e968331be6076907",
        "pixel_panda": "231b610fecbbf10dc76843eddd02e031304a2493f5c186a0b835a3ed502f277a",
        "pixel_frog": "3ba862134c2513b407c0ae2c3d87ad5fef7a175110a1bb94b655fda48dbfed72",
        "pixel_octopus": "450c146f071a286fd3c491aba208c68c757ad7ccb765548de879e15b123c3b79",
        "pixel_bungeoppang": "a4cb9e9cd23599baaf65bde6c1a0ec4e622934176ced6439c0585080d38fd758",
        "pixel_fried_egg": "a5e651f2aecfd231cb736309a5cdd0f178698b9b77fdeeb8d28c7d4b9c4b8cac",
        "pixel_samgak_gimbap": "4af5e28183a035e6992ab898f8cc347d7ec41746ece4256a6613a17852d0c670",
        "pixel_tteokbokki": "9c7e7736bd51b089e9891bbff2fde39c62c7626ff303e5b5bb4ab25f854cd9ef",
        "pixel_avocado": "3b7685c56aab5dffb64482a0d217cb91818b77cf9a9fdcd96933c4308c8b4ed9",
        "pixel_slime": "d8b04e9803d2059f91d723138235a6865832d0cb7dfe1c0fe9f8ffa34ba419e6",
        "pixel_cactus_pot": "a9b9a7c4d7e4aae26f7cd2a18c5fb42dfcdaf18fa72231cc70d27bab12760655",
        "pixel_tofu": "91ef6cb841b2684559cda346b677cdb55046e76b13f52e9ae8d3ac871a9a4f92",
        "pixel_cup_ramen": "3a0ae66c8744b85983f6d20d8e9ed09e466cf47da1d4a47a58c00505ba001471",
        "pixel_grandma": "9de37131633d697928208c69e24f86d0312aaf68af867029eda064698b4a0c10",
        "pixel_baby": "dd44e8e20d17547dfed1d9c1aa42858b182eb25228a73d5f0b324fe196eeab54",
        "pixel_santa": "8a8392cb8baba464fa550b1e5b8d89f070e55bcb26c57dec0164c03f6f2df63a",
        "pixel_jungjiyu": "9f72a2fecdf334b30f92520cd120b0cba008ba8df57ddae8eb63c52e1eaa420b"
    ]
    private let objectHashes = [
        "patch_soft_ball": "cdde7f417c5d8d82d0f4df6b03fa8e7d494d98a37d75aa66699505d7c87c53fe",
        "mini_paprika": "85b8d0525a865e531882a736561e9b7c4fbb6a2c3f80d91b456c4c4a7425724d",
        "banana": "9cfca454ff6305fdd374c08f64c3c21e3af278166ffe15f7f81a183bb214f138",
        "dust_bath_pouch": "b68022f5fe1a1a6a57fe56a01f73bae3d14b27d76f2dcbf10c6686b979634a65",
        "starlight_orb": "08cf8ec8dc680ae07dcd83de9d56948873445470c6b15b5ad22e770f4277984c",
        "heart_cushion": "988ce26889b74ce6fbd6ba16366160361092bf8194e8aed8a2e90231ddd53dab",
        "ice_americano": "7491386e36f5d23a6dbf74c0bf3c19652a390a87adf03e284cdfbee8944784db"
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
