import AppKit
import SpriteKit
import XCTest
#if APP_STORE
@testable import SIDEYAppStore
#else
@testable import SIDEY
#endif

@MainActor
final class NewCharacterIntegrationTests: XCTestCase {
    func testPaidCharactersDefaultToBallAndKeepItemsIndependent() {
        for (character, item) in [("pixel_otter", "clam"), ("pixel_pig", "pork"), ("pixel_tree", "timber")] {
            XCTAssertEqual(PixelCharacterThrowCatalog.objectID(for: character), "patch_soft_ball")
            XCTAssertEqual(PixelCharacterThrowCatalog.resolvedObjectID(for: character, equippedObjectID: "throwable_" + item), item)
            XCTAssertFalse(PixelCharacterCatalog.canSelect(character, entitlementKeys: []))
            XCTAssertTrue(PixelCharacterCatalog.canSelect(character, entitlementKeys: ["character:\(character)"]))
            XCTAssertTrue(PixelCharacterThrowCatalog.supports(objectID: item))
        }
        XCTAssertEqual(CommerceProduct.otter.amountKRW, 1_100)
        XCTAssertEqual(CommerceProduct.pig.amountKRW, 1_100)
        XCTAssertEqual(CommerceProduct.tree.amountKRW, 1_100)
        for product in [CommerceProduct.snowflake, .baseball, .wakkuball, .dujjonku] {
            XCTAssertTrue(PixelCharacterThrowCatalog.purchasableObjectIDs.contains(product.catalogItemID))
            XCTAssertNotNil(product.automaticEquipmentAfterFreshPurchase)
        }
    }

    func testAllCatalogPricesUseApprovedKoreanTiers() {
        let premium: Set<String> = ["bubble_bunny_pink", "bubble_butter_chick", "bubble_starry_cat",
                                    "throwable_dujjonku", "throwable_wakkuball"]
        for product in CommerceCatalog.products {
            let expected = product.id == "throwable_toy_cannon" ? 3_300
                : premium.contains(product.id) ? 2_200 : 1_100
            XCTAssertEqual(product.amountKRW, expected, product.id)
        }
    }

    func testTreeStaysPutThroughMovementAvoidanceAndResumesOnEveryEdge() {
        for edge in [OverlayEdge.bottom, .top, .left, .right] {
            let tree = UUID(), friend = UUID(), room = UUID()
            let scene = PixelWorldScene(size: CGSize(width: 600, height: 600), renderingConfiguration: .storePreview(initialTrackFractions: [tree: 0.3, friend: 0.31], fixedTrackFractions: [:]))
            scene.apply(roomID: room, members: [
                PixelWorldMember(id: tree, nickname: "나무", characterID: "pixel_tree", presence: .online, isTyping: false, isCurrentUser: true),
                PixelWorldMember(id: friend, nickname: "친구", characterID: "pixel_hamster", presence: .online, isTyping: false, isCurrentUser: false)
            ], bubbles: [], edge: edge, activityFrame: CGRect(x: 0, y: 0, width: 600, height: 600), installationSeed: 42, composerVisible: true)
            XCTAssertFalse(scene.toggleTreeMovement(for: friend))
            XCTAssertTrue(scene.toggleTreeMovement(for: tree))
            let initial = scene.agentStates.first { $0.id == tree }!.trackPosition
            for frame in 1...90 { scene.update(Double(frame) / 30) }
            XCTAssertEqual(scene.agentStates.first { $0.id == tree }!.trackPosition, initial, accuracy: 0.001)
            XCTAssertEqual(scene.agentStates.first { $0.id == tree }!.velocity, 0)
            XCTAssertTrue(scene.isTreeMovementPaused(for: tree))
            XCTAssertTrue(scene.toggleTreeMovement(for: tree))
            var moved = false
            for frame in 91...240 {
                scene.update(Double(frame) / 30)
                moved = moved || abs(scene.agentStates.first { $0.id == tree }!.trackPosition - initial) > 1
            }
            XCTAssertTrue(moved, "Tree must resume on \(edge)")
            XCTAssertFalse(PixelCharacterCatalog.definition(for: "pixel_tree").mirrorsToMovementDirection)
        }
    }

    func testTreePauseAndSoundPreferencesSurviveRelaunch() throws {
        var value = AppPreferences()
        value.treeMovementPaused = true
        value.characterSoundEffectsEnabled = false
        let restored = try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(value))
        XCTAssertTrue(restored.treeMovementPaused)
        XCTAssertFalse(restored.characterSoundEffectsEnabled)
        let old = try JSONDecoder().decode(AppPreferences.self, from: Data(#"{"schemaVersion":8}"#.utf8))
        XCTAssertFalse(old.treeMovementPaused)
        XCTAssertTrue(old.characterSoundEffectsEnabled)
    }
}
