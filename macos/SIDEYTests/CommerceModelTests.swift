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
                "bubble_bunny_pink",
                "bubble_butter_chick",
                "bubble_starry_cat",
                "throwable_bouncy_heart",
                "throwable_toy_cannon",
                "throwable_squeaky_duck",
            ]
        )
        for product in CommerceCatalog.characterProducts {
            let characterID = try XCTUnwrap(product.characterID)
            XCTAssertEqual(PixelCharacterCatalog.definition(for: characterID).id, characterID)
            XCTAssertEqual(
                PixelCharacterCatalog.definition(for: characterID).entitlementKey,
                product.entitlementKey
            )
        }
    }

    func testCosmeticCatalogKeepsApprovedKindsPricesAndOrdering() throws {
        XCTAssertEqual(CommerceCatalog.cosmeticProducts.map(\.kind), [
            .bubble, .bubble, .bubble, .throwable, .throwable, .throwable,
        ])
        XCTAssertEqual(CommerceCatalog.cosmeticProducts.map(\.catalogItemID), [
            "bubble_bunny_pink",
            "bubble_butter_chick",
            "bubble_starry_cat",
            "throwable_bouncy_heart",
            "throwable_toy_cannon",
            "throwable_squeaky_duck",
        ])
        XCTAssertEqual(CommerceProduct.bunnyPinkBubble.amountKRW, 1_900)
        XCTAssertEqual(CommerceProduct.butterChickBubble.amountKRW, 1_900)
        XCTAssertEqual(CommerceProduct.starryCatBubble.amountKRW, 1_900)
        XCTAssertEqual(CommerceProduct.bouncyHeart.amountKRW, 990)
        XCTAssertEqual(CommerceProduct.toyCannon.amountKRW, 3_900)
        XCTAssertEqual(CommerceProduct.squeakyDuck.amountKRW, 990)
        XCTAssertTrue(CommerceCatalog.products.map(\.sortOrder).elementsEqual(
            CommerceCatalog.products.map(\.sortOrder).sorted()
        ))
        XCTAssertTrue(CommerceCatalog.cosmeticProducts.allSatisfy { $0.characterID == nil })
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

    func testCosmeticGridFitsSixFiveAndFourColumnsAtResponsiveBodyWidths() {
        func columnCount(_ width: CGFloat) -> Int {
            Int((width + StoreCardLayout.spacing)
                / (StoreCardLayout.minimumWidth + StoreCardLayout.spacing))
        }

        XCTAssertEqual(columnCount(760), 6)
        XCTAssertEqual(columnCount(620), 5)
        XCTAssertEqual(columnCount(500), 4)
        XCTAssertEqual(StoreCardLayout.maximumWidth, 118)
        XCTAssertEqual(StoreCardLayout.cornerRadius, 18)
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

    func testRevokedOrServerUnequippedCosmeticsImmediatelyFallBackToDefaults() {
        let userID = UUID()
        let model = AppModel(preferences: .defaults)
        model.apply(
            snapshot: BackendSnapshot(
                profile: Profile(
                    id: userID,
                    nickname: "꾸미기친구",
                    characterID: PixelCharacterCatalog.pixelHamsterID,
                    equippedBubbleStyleID: CommerceProduct.bunnyPinkBubble.catalogItemID,
                    equippedThrowableID: CommerceProduct.toyCannon.catalogItemID
                ),
                rooms: [],
                activeEntitlementKeys: [
                    CommerceProduct.bunnyPinkBubble.entitlementKey,
                    CommerceProduct.toyCannon.entitlementKey,
                ]
            ),
            currentUserID: userID
        )
        XCTAssertEqual(model.equippedBubbleStyleID, "bubble_bunny_pink")
        XCTAssertEqual(model.equippedThrowableID, "throwable_toy_cannon")

        model.apply(commerceState: CommerceState(
            product: .toyCannon,
            googleConnected: true,
            entitlementStatus: "refunded",
            latestOrderStatus: "refunded",
            isEquipped: false
        ))
        XCTAssertNil(model.equippedThrowableID)

        model.apply(commerceStates: [
            CommerceState(
                product: .bunnyPinkBubble,
                googleConnected: true,
                entitlementStatus: "active",
                latestOrderStatus: "approved",
                isEquipped: false
            ),
            CommerceState(
                product: .butterChickBubble,
                googleConnected: true,
                entitlementStatus: nil,
                latestOrderStatus: nil,
                isEquipped: false
            ),
            CommerceState(
                product: .starryCatBubble,
                googleConnected: true,
                entitlementStatus: nil,
                latestOrderStatus: nil,
                isEquipped: false
            ),
        ])
        XCTAssertNil(model.equippedBubbleStyleID)
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
