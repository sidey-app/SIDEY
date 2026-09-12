import AppKit

extension AppCoordinator {
    func refreshCommerceState(productID: String? = nil) {
        guard releaseChannel.storeAvailability.allowsCommerceActions,
              let backend
        else { return }
        let requestedIDs = productID.map { [$0] } ?? model.commerceProducts.map(\.id)
        let productIDs = requestedIDs.filter {
            model.commerceProduct(id: $0) != nil && commerceSession.productTasks[$0] == nil
        }
        guard !productIDs.isEmpty else { return }
        productIDs.forEach { model.setCommerceWorking(true, productID: $0) }
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                for id in productIDs {
                    model.setCommerceWorking(false, productID: id)
                    commerceSession.productTasks[id] = nil
                }
            }
            if releaseChannel.storeAvailability.usesAppStore {
                await refreshAppStorePrices()
            }
            do {
                let states = try await backend.storeState()
                model.apply(commerceStates: states)
                if releaseChannel.storeAvailability.usesAppStore {
                    for state in states where state.entitlementStatus != "active" {
                        model.setCommercePurchaseState(.available, productID: state.product.id)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                for id in productIDs {
                    model.setCommercePurchaseState(
                        .error("상점 상태를 불러오지 못했습니다."),
                        productID: id
                    )
                }
            }
        }
        productIDs.forEach { commerceSession.productTasks[$0] = task }
    }

    func setEquippedCosmetic(kind: CommerceProductKind, catalogItemID: String?) {
        let product = catalogItemID.flatMap { requestedID in
            model.ownedProfileCosmeticProducts(for: kind).first {
                $0.catalogItemID == requestedID
            }
        }
        guard releaseChannel.storeAvailability.allowsCosmeticEquipment,
              kind != .character,
              let backend,
              catalogItemID == nil || product != nil,
              model.equippedCosmeticID(for: kind) != catalogItemID,
              commerceSession.equipmentTasks[kind] == nil,
              model.beginCosmeticEquipmentRequest(kind: kind, catalogItemID: catalogItemID)
        else { return }

        model.errorMessage = nil
        model.dismissSuccess()
        commerceSession.equipmentTasks[kind] = Task { [weak self] in
            guard let self else { return }
            defer {
                model.endCosmeticEquipmentRequest(kind: kind)
                commerceSession.equipmentTasks[kind] = nil
            }
            do {
                let profile = try await backend.setEquippedCosmetic(
                    kind: kind,
                    catalogItemID: catalogItemID
                )
                guard profile.id == model.currentUserID else {
                    throw SideyBackendError.malformedResponse
                }
                model.apply(profile: profile)
                model.presentSuccess(CosmeticEquipmentFeedback.successMessage(
                    kind: kind,
                    product: product
                ))
                model.errorMessage = nil
                persistPreferences()
            } catch is CancellationError {
                return
            } catch {
                model.errorMessage = "장착 상태를 바꾸지 못했습니다: \(error.localizedDescription)"
            }
        }
    }

#if !APP_STORE
    private func connectGoogleForCommerce(productID: String) {
        guard releaseChannel.storeAvailability.allowsCommerceActions,
              let backend,
              model.commerceProduct(id: productID) != nil,
              commerceSession.productTasks[productID] == nil,
              commerceSession.googleConnectionProductID == nil || commerceSession.googleConnectionProductID == productID
        else { return }

        commerceSession.googleConnectionProductID = productID
        model.setCommerceWorking(true, productID: productID)
        model.errorMessage = nil
        commerceSession.productTasks[productID] = Task { [weak self] in
            guard let self else { return }
            var didOpenBrowser = false
            defer {
                if !didOpenBrowser {
                    commerceSession.googleConnectionProductID = nil
                }
                model.setCommerceWorking(false, productID: productID)
                commerceSession.productTasks[productID] = nil
            }
            do {
                let url = try await backend.googleIdentityLinkURL()
                guard NSWorkspace.shared.open(url) else {
                    throw SideyBackendError.remote("기본 브라우저를 열지 못했습니다.")
                }
                didOpenBrowser = true
                model.presentSuccess("브라우저에서 Google 계정 연결을 완료해 주세요.")
            } catch is CancellationError {
                return
            } catch {
                model.setCommercePurchaseState(
                    .error("Google 연결을 시작하지 못했습니다."),
                    productID: productID
                )
                model.errorMessage = "Google 계정 연결 실패: \(error.localizedDescription)"
            }
        }
    }
#endif

    func purchase(productID: String) {
        guard releaseChannel.storeAvailability.allowsCommerceActions,
              let backend,
              let productState = model.commerceProduct(id: productID),
              commerceSession.productTasks[productID] == nil,
              productState.purchaseState != .owned
        else { return }

#if !APP_STORE
        if !releaseChannel.storeAvailability.usesAppStore,
           productState.purchaseState == .googleConnectionRequired {
            connectGoogleForCommerce(productID: productID)
            return
        }
#endif
        guard productState.purchaseState == .available
                || productState.purchaseState == .refunded
        else { return }

        let product = productState.product
        model.setCommerceWorking(true, productID: productID)
        model.setCommercePurchaseState(.openingCheckout, productID: productID)
        model.errorMessage = nil
        commerceSession.productTasks[productID] = Task { [weak self] in
            guard let self else { return }
            defer {
                model.setCommerceWorking(false, productID: productID)
                commerceSession.productTasks[productID] = nil
            }
            do {
                if releaseChannel.storeAvailability.usesAppStore {
                    guard let userID = model.currentUserID else {
                        throw SideyBackendError.sessionRecoveryFailed
                    }
                    let purchased = try await commerceSession.purchaseController.purchase(
                        productID: productID,
                        userID: userID,
                        accessToken: try await backend.currentAccessToken()
                    )
                    if purchased {
                        let snapshot = try await backend.loadSnapshot()
                        applyBackendSnapshot(snapshot, currentUserID: userID)
                        model.setCommercePurchaseState(.owned, productID: productID)
                        if let equipment = product.automaticEquipmentAfterFreshPurchase {
                            do {
                                let profile = try await backend.setEquippedCosmetic(
                                    kind: equipment.kind,
                                    catalogItemID: equipment.catalogItemID
                                )
                                guard profile.id == userID else {
                                    throw SideyBackendError.malformedResponse
                                }
                                model.apply(profile: profile)
                                persistPreferences()
                                model.presentSuccess("\(product.displayName) 구매 및 장착이 완료되었습니다.")
                            } catch is CancellationError {
                                return
                            } catch {
                                model.presentSuccess("\(product.displayName) 구매가 완료되었습니다.")
                                model.errorMessage = "구매는 반영됐지만 자동 장착하지 못했습니다: \(error.localizedDescription)"
                            }
                        } else {
                            model.presentSuccess("\(product.displayName) 구매가 완료되었습니다.")
                        }
                    } else {
                        model.setCommercePurchaseState(.available, productID: productID)
                    }
                    return
                }
#if APP_STORE
                throw SideyBackendError.remote("App Store 배포 구성이 올바르지 않습니다.")
#else
                let checkout = try await backend.createCommerceOrder(productID: productID)
                guard NSWorkspace.shared.open(checkout.checkoutURL) else {
                    throw SideyBackendError.remote("기본 브라우저를 열지 못했습니다.")
                }
                model.setCommercePurchaseState(.confirming, productID: productID)

                for _ in 0..<90 {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .seconds(2))
                    let state = try await backend.commerceState(productID: productID)
                    if state.purchaseState == .owned {
                        model.apply(commerceState: state)
                        let snapshot = try await backend.loadSnapshot()
                        applyBackendSnapshot(snapshot, currentUserID: model.currentUserID)
                        model.presentSuccess("\(product.displayName) 구매가 완료되었습니다.")
                        model.errorMessage = nil
                        persistPreferences()
                        return
                    }
                    if state.latestOrderStatus == "failed" || state.latestOrderStatus == "canceled" {
                        model.apply(commerceState: state)
                        model.setCommercePurchaseState(
                            .error("결제가 완료되지 않았습니다. 다시 시도해 주세요."),
                            productID: productID
                        )
                        return
                    }
                }
                model.setCommercePurchaseState(
                    .error("결제 승인 확인 시간이 초과되었습니다. 상점 상태를 다시 확인해 주세요."),
                    productID: productID
                )
#endif
            } catch is CancellationError {
                return
            } catch {
                model.setCommercePurchaseState(
                    .error("결제 상태를 확인하지 못했습니다."),
                    productID: productID
                )
                model.errorMessage = "\(product.displayName) 구매 처리 실패: \(error.localizedDescription)"
            }
        }
    }

    func signInWithApple(_ payload: AppleAuthorizationPayload) {
        guard releaseChannel.requiresAppleAuthentication, let backend,
              !model.accountOperationInProgress else { return }
        model.accountOperationInProgress = true
        model.errorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            defer { model.accountOperationInProgress = false }
            do {
                try await backend.signInWithApple(
                    identityToken: payload.identityToken,
                    nonce: payload.nonce
                )
                model.authenticationRequired = false
                startBackend()
            } catch {
                model.authenticationRequired = true
                model.errorMessage = "Apple 로그인 실패: \(error.localizedDescription)"
            }
        }
    }

    func restoreAppStorePurchases() {
        guard releaseChannel == .appStore, let backend, let userID = model.currentUserID,
              !model.accountOperationInProgress else { return }
        model.accountOperationInProgress = true
        model.errorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            defer { model.accountOperationInProgress = false }
            do {
                try await commerceSession.purchaseController.restore(
                    accessToken: try await backend.currentAccessToken()
                )
                let snapshot = try await backend.loadSnapshot()
                applyBackendSnapshot(snapshot, currentUserID: userID)
                refreshCommerceState()
                model.presentSuccess("App Store 구매 내역을 복원했습니다.")
            } catch {
                model.errorMessage = "구매 복원 실패: \(error.localizedDescription)"
            }
        }
    }

    func deleteAccount(_ payload: AppleAuthorizationPayload) {
        guard releaseChannel == .appStore, let backend,
              !model.accountOperationInProgress else { return }
        model.accountOperationInProgress = true
        model.errorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            defer { model.accountOperationInProgress = false }
            do {
                try await commerceSession.accountClient.deleteAccount(
                    payload: payload,
                    accessToken: try await backend.currentAccessToken()
                )
                try? await backend.signOut()
                try? KeychainStore(
                    service: releaseChannel.keychainService,
                    session: keychainAccessSession
                ).deleteAll()
                preferencesStore.save(.defaults)
                NSApplication.shared.terminate(nil)
            } catch {
                model.errorMessage = "계정 탈퇴 실패: \(error.localizedDescription)"
            }
        }
    }

    func refreshAppStorePrices() async {
        model.beginCommercePriceLoading()
        do {
            model.setCommerceLocalizedPrices(try await commerceSession.purchaseController.loadProducts())
        } catch {
            model.failCommercePriceLoading()
            model.errorMessage = "App Store 상품 정보를 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    func configureAppStoreCommerce(backend: SideyBackend) async {
        await refreshAppStorePrices()
        do {
            try await commerceSession.purchaseController.reconcileCurrentEntitlements(
                accessToken: try await backend.currentAccessToken()
            )
        } catch {
            model.errorMessage = "App Store 구매 내역을 반영하지 못했습니다: \(error.localizedDescription)"
        }
        commerceSession.purchaseController.startObserving(
            accessToken: { try await backend.currentAccessToken() },
            didChange: { [weak self] in self?.refreshCommerceState() },
            didFail: { [weak self] message in
                self?.model.errorMessage = "App Store 거래 반영 실패: \(message)"
            }
        )
    }
}
