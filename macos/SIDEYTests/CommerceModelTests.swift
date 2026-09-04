import XCTest
@testable import SIDEY

@MainActor
final class CommerceModelTests: XCTestCase {
    func testCatalogProvidesRenderableProductsInDisplayOrder() throws {
        XCTAssertEqual(
            CommerceCatalog.products.map(\.id),
            [
                CommerceCatalog.starlightUpalupaProductID,
                CommerceCatalog.guineaPigProductID,
                CommerceCatalog.monkeyProductID,
                CommerceCatalog.chinchillaProductID,
            ]
        )
        for product in CommerceCatalog.products {
            XCTAssertEqual(PixelCharacterCatalog.definition(for: product.characterID).id, product.characterID)
            XCTAssertEqual(
                PixelCharacterCatalog.definition(for: product.characterID).entitlementKey,
                product.entitlementKey
            )
        }
    }

    func testReleaseChannelHardCodesStoreAvailabilityAndIsolationIdentifiers() {
        XCTAssertFalse(AppReleaseChannel.production.storeAvailability.allowsCommerceActions)
        XCTAssertTrue(AppReleaseChannel.development.storeAvailability.allowsCommerceActions)
        XCTAssertTrue(AppReleaseChannel.appStore.storeAvailability.usesAppStore)
        XCTAssertNotEqual(AppReleaseChannel.production.keychainService, AppReleaseChannel.development.keychainService)
        XCTAssertNotEqual(AppReleaseChannel.production.loginItemMode, AppReleaseChannel.development.loginItemMode)
        XCTAssertEqual(AppReleaseChannel.appStore.loginItemMode, .mainApp)
        XCTAssertTrue(AppReleaseChannel.appStore.requiresAppleAuthentication)
        XCTAssertNil(AppReleaseChannel.production.preferencesSuiteName)
        XCTAssertEqual(AppReleaseChannel.development.preferencesSuiteName, "app.sidey.desktop.dev")
        XCTAssertEqual(AppReleaseChannel.appStore.preferencesSuiteName, "app.sidey.desktop.appstore")
    }

    func testTwoProductsKeepOrderAndUpdateStateIndependently() throws {
        let first = Self.fixtureProduct(id: "fixture_first", characterID: "pixel_hamster")
        let second = Self.fixtureProduct(id: "fixture_second", characterID: "pixel_cat")
        let model = AppModel(preferences: .defaults, commerceProducts: [second, first])

        XCTAssertEqual(model.commerceProducts.map(\.id), [second.id, first.id])

        model.apply(commerceState: CommerceState(
            product: first,
            googleConnected: true,
            entitlementStatus: "active",
            latestOrderStatus: "approved"
        ))
        model.setCommerceWorking(true, productID: second.id)
        model.setCommercePurchaseState(.error("두 번째 상품만 실패"), productID: second.id)

        XCTAssertEqual(model.commerceProducts.map(\.id), [second.id, first.id])
        XCTAssertEqual(model.commerceProduct(id: first.id)?.purchaseState, .owned)
        XCTAssertFalse(try XCTUnwrap(model.commerceProduct(id: first.id)).isWorking)
        XCTAssertEqual(
            model.commerceProduct(id: second.id)?.purchaseState,
            .error("두 번째 상품만 실패")
        )
        XCTAssertTrue(try XCTUnwrap(model.commerceProduct(id: second.id)).isWorking)
    }

    func testStoreProductCardForwardsItsOwnProductIDForPurchase() {
        let product = Self.fixtureProduct(id: "fixture_selected", characterID: "pixel_rabbit")
        let state = CommerceProductState(product: product, purchaseState: .available, isWorking: false)
        var purchasedProductID: String?
        var actions = SettingsActions.empty
        actions.onPurchase = { purchasedProductID = $0 }

        StoreProductCard(productState: state, actions: actions).requestPurchase()

        XCTAssertEqual(purchasedProductID, product.id)
    }

    func testStoreKitLocalizedPriceOverridesDirectPrice() {
        let product = Self.fixtureProduct(id: "fixture_localized", characterID: "pixel_rabbit")
        let state = CommerceProductState(
            product: product,
            purchaseState: .available,
            isWorking: false,
            localizedPrice: "$0.99"
        )

        XCTAssertEqual(state.formattedPrice, "$0.99")
    }

    func testStoreReactionPreviewFitsInsideItsCardWithoutUsingWorldScale() {
        XCTAssertEqual(StoreReactionPreviewStyle.peakScale, 1.45, accuracy: 0.001)
        XCTAssertEqual(StoreReactionPreviewStyle.maximumRenderedCharacterSize, 139.2, accuracy: 0.001)
        XCTAssertLessThan(
            StoreReactionPreviewStyle.maximumRenderedCharacterSize,
            StoreCardLayout.minimumPreviewHeight
        )
        XCTAssertEqual(StoreCardLayout.aspectRatio, 1)
        XCTAssertGreaterThan(StoreCardLayout.footerMinimumSpacing, 0)
        XCTAssertNotEqual(StoreReactionPreviewStyle.peakScale, PixelCharacterPulseStyle.peakScale)
    }

    func testPurchaseStateRequiresGoogleAndReflectsOwnershipAndRefund() {
        let product = CommerceProduct.starlightUpalupa

        XCTAssertEqual(CommerceState(
            product: product,
            googleConnected: false,
            entitlementStatus: nil,
            latestOrderStatus: nil
        ).purchaseState, .googleConnectionRequired)
        XCTAssertEqual(CommerceState(
            product: product,
            googleConnected: true,
            entitlementStatus: nil,
            latestOrderStatus: nil
        ).purchaseState, .available)
        XCTAssertEqual(CommerceState(
            product: product,
            googleConnected: true,
            entitlementStatus: "active",
            latestOrderStatus: "approved"
        ).purchaseState, .owned)
        XCTAssertEqual(CommerceState(
            product: product,
            googleConnected: true,
            entitlementStatus: "refunded",
            latestOrderStatus: "refunded"
        ).purchaseState, .refunded)
    }

    func testCoreSnapshotDoesNotDependOnCommerceSchemaAvailability() {
        let ownedKey = CommerceCatalog.starlightUpalupaEntitlementKey

        XCTAssertEqual(
            CommerceEntitlementSnapshotPolicy.resolvedKeys(
                remoteKeys: [ownedKey],
                profileCharacterID: PixelCharacterCatalog.pixelHamsterID
            ),
            [ownedKey]
        )
        XCTAssertEqual(
            CommerceEntitlementSnapshotPolicy.resolvedKeys(
                remoteKeys: nil,
                profileCharacterID: PixelCharacterCatalog.pixelStarlightUpalupaID
            ),
            [ownedKey]
        )
        XCTAssertEqual(
            CommerceEntitlementSnapshotPolicy.resolvedKeys(
                remoteKeys: nil,
                profileCharacterID: PixelCharacterCatalog.pixelHamsterID
            ),
            []
        )
    }

    func testPaidCharacterAppearsOnlyWithActiveEntitlementAndRefundFallsBack() {
        let userID = UUID()
        let roomID = UUID()
        var preferences = AppPreferences.defaults
        preferences.activeRoomID = roomID
        let model = AppModel(preferences: preferences)
        XCTAssertEqual(model.selectableCharacters.map(\.id), PixelCharacterCatalog.free.map(\.id))

        model.apply(
            snapshot: BackendSnapshot(
                profile: Profile(
                    id: userID,
                    nickname: "별빛친구",
                    characterID: PixelCharacterCatalog.pixelStarlightUpalupaID
                ),
                rooms: [Room(
                    id: roomID,
                    name: "별빛방",
                    ownerID: userID,
                    members: [RoomMember(
                        userID: userID,
                        nickname: "별빛친구",
                        characterID: PixelCharacterCatalog.pixelStarlightUpalupaID,
                        presence: .online
                    )],
                    inviteCodeHint: "ST••••"
                )],
                activeEntitlementKeys: [CommerceCatalog.starlightUpalupaEntitlementKey]
            ),
            currentUserID: userID
        )
        XCTAssertTrue(model.selectableCharacters.contains {
            $0.id == PixelCharacterCatalog.pixelStarlightUpalupaID
        })
        XCTAssertEqual(
            model.pixelWorldMembers.first?.characterID,
            PixelCharacterCatalog.pixelStarlightUpalupaID
        )

        model.apply(commerceState: CommerceState(
            product: .starlightUpalupa,
            googleConnected: true,
            entitlementStatus: "refunded",
            latestOrderStatus: "refunded"
        ))
        XCTAssertEqual(model.selectedCharacterID, PixelCharacterCatalog.pixelHamsterID)
        XCTAssertEqual(model.pixelWorldMembers.first?.characterID, PixelCharacterCatalog.pixelHamsterID)
        XCTAssertEqual(model.selectableCharacters.map(\.id), PixelCharacterCatalog.free.map(\.id))
    }

    private static func fixtureProduct(id: String, characterID: String) -> CommerceProduct {
        CommerceProduct(
            id: id,
            displayName: "테스트 캐릭터 \(id)",
            description: "카드 순서와 독립 상태를 확인하는 테스트 상품입니다.",
            characterID: characterID,
            entitlementKey: "character:\(characterID):\(id)",
            amountKRW: 1_200,
            currency: "KRW",
            taxInclusive: true
        )
    }
}
