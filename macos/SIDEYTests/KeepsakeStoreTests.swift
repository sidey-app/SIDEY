import AppKit
import SpriteKit
import SwiftUI
import XCTest
@testable import SIDEY

@MainActor
final class KeepsakeStoreTests: XCTestCase {
    func testIndependentOwnershipAndLegacyOfferIdentity() throws {
        XCTAssertEqual(CommerceCatalog.products.count, 24)
        let keepsakes = CommerceCatalog.products.filter(\.isKeepsake)
        XCTAssertEqual(keepsakes.count, 7)
        for product in CommerceCatalog.characterProducts {
            let item = try XCTUnwrap(CommerceCatalog.keepsake(for: product.id))
            XCTAssertNotEqual(product.entitlementKey, item.entitlementKey)
            XCTAssertEqual(item.amountKRW, 990)
            XCTAssertEqual(PixelCharacterThrowCatalog.objectID(for: try XCTUnwrap(product.characterID)), "patch_soft_ball")
            // A free hamster can render any independently equipped keepsake.
            XCTAssertEqual(PixelCharacterThrowCatalog.resolvedObjectID(for: "pixel_hamster", equippedObjectID: item.catalogItemID), item.renderAssetID)
            XCTAssertNotNil(PixelCharacterThrowCatalog.objectAssetURL(for: item.catalogItemID))
        }
        XCTAssertEqual(CommerceCatalog.product(appStoreID: "character_monkey_solo")?.id, CommerceProduct.monkey.id)
        XCTAssertEqual(CommerceCatalog.product(appStoreID: "character_monkey")?.id, CommerceProduct.monkey.id)
        XCTAssertEqual(CommerceProduct.monkey.appStoreProductID, "character_monkey_solo")
        XCTAssertNil(CommerceCatalog.product(appStoreID: "haracter_pig"))
    }
    func testTrialDoesNotRepeatOnViewUpdateAndStopsOnClose() throws {
        let scenario = StorePreviewScenario.make(product: .pig)
        let scene = PixelWorldScene(size: StorePreviewStageLayout.size, renderingConfiguration: .storePreview(
            initialTrackFractions: scenario.initialTrackFractions, fixedTrackFractions: scenario.fixedTrackFractions))
        let view = StorePreviewSKView(frame: CGRect(origin: .zero, size: StorePreviewStageLayout.size))
        view.presentScene(scene)
        let coordinator = StorePreviewPlaybackCoordinator()
        let request = UUID()
        coordinator.configure(view: view, scene: scene, scenario: scenario, isPlaying: true,
            trialRequestID: request, trialObjectID: "pork")
        XCTAssertEqual(scene.activeProjectileCount, 1)
        XCTAssertFalse(coordinator.hasActiveThrowTask)
        XCTAssertEqual(view.characterThrowInteraction?.throwableID, "patch_soft_ball")
        coordinator.configure(view: view, scene: scene, scenario: scenario, isPlaying: true,
            trialRequestID: request, trialObjectID: "pork")
        XCTAssertEqual(scene.activeProjectileCount, 1)
        coordinator.stop(detachingScene: true)
        XCTAssertEqual(scene.activeProjectileCount, 0)
        XCTAssertNil(view.scene)
    }
    func testReducedMotionSuppressesTrialAndDoesNotReplayItOnResume() {
        let scenario = StorePreviewScenario.make(product: .pig)
        let scene = PixelWorldScene(size: StorePreviewStageLayout.size, renderingConfiguration: .storePreview(
            initialTrackFractions: scenario.initialTrackFractions, fixedTrackFractions: scenario.fixedTrackFractions))
        let view = StorePreviewSKView(frame: CGRect(origin: .zero, size: StorePreviewStageLayout.size))
        let coordinator = StorePreviewPlaybackCoordinator()
        let request = UUID()
        coordinator.configure(view: view, scene: scene, scenario: scenario, isPlaying: false,
            trialRequestID: request, trialObjectID: "pork")
        coordinator.configure(view: view, scene: scene, scenario: scenario, isPlaying: true,
            trialRequestID: request, trialObjectID: "pork")
        XCTAssertEqual(scene.activeProjectileCount, 0)
        coordinator.stop(detachingScene: true)
    }
    func testPairSheetFitsBothPurchaseCardsForAllOwnershipStates() throws {
        let product = CommerceProduct.pig
        let item = try XCTUnwrap(CommerceCatalog.keepsake(for: product.id))
        for ownsCharacter in [false,true] {
            for ownsItem in [false,true] {
                let view = NSHostingView(rootView: StoreProductDetailSheet(
                    productState: .init(product: product, purchaseState: ownsCharacter ? .owned : .available, isWorking: false),
                    relatedProductState: .init(product: item, purchaseState: ownsItem ? .owned : .available, isWorking: false),
                    actions: .empty, onClose: {}))
                XCTAssertEqual(view.fittingSize.width,600,accuracy:0.01)
                XCTAssertEqual(view.fittingSize.height,720,accuracy:0.01)
            }
        }
    }
}
