import AppKit

extension AppCoordinator {
    func startBackend() {
        if let configurationError {
            model.connectionState = .failed(configurationError.localizedDescription)
            model.errorMessage = configurationError.localizedDescription
            backendBootstrapState = .failed
            applyRequestedOverlayVisibility()
            refreshStatusItem()
            if launchReason == .loginItem { showSettings() }
            advanceFirstRunTransition()
            return
        }
        guard let backend else {
            backendBootstrapState = .failed
            applyRequestedOverlayVisibility()
            refreshStatusItem()
            if launchReason == .loginItem { showSettings() }
            advanceFirstRunTransition()
            return
        }
        let requireExistingSession = model.preferences.onboardingComplete
        backendConnectionStatus = nil
        model.setActiveRoomRealtimeConnected(false)
        model.connectionState = .connecting
        backendEventTask?.cancel()
        backendEventTask = Task { [weak self] in
            for await event in backend.events {
                guard !Task.isCancelled else { return }
                self?.handleBackendEvent(event)
            }
        }
        backendTask?.cancel()
        backendTask = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await backend.boot(requireExistingSession: requireExistingSession)
                let userID = await backend.currentUserID()
                guard !Task.isCancelled else { return }
                model.apply(snapshot: snapshot, currentUserID: userID)
                refreshCommerceState()
                let reconciliation = try await backend.syncRealtime(
                    rooms: snapshot.rooms,
                    activeRoomID: model.activeRoom?.id
                )
                applyBackendReconciliation(reconciliation)
                model.setActiveRoomRealtimeConnected(true)
                model.connectionState = .online
                model.errorMessage = nil
                backendBootstrapState = .ready
                model.preferences.keychainTransitionComplete = true
                applyRequestedOverlayVisibility()
                overlayWindows.refreshThrowHotspots()
                refreshStatusItem()
                persistPreferences()
                advanceFirstRunTransition()
            } catch {
                guard !Task.isCancelled else { return }
                model.connectionState = .failed(error.localizedDescription)
                model.errorMessage = "서버 연결 실패: \(error.localizedDescription)"
                backendBootstrapState = .failed
                applyRequestedOverlayVisibility()
                overlayWindows.refreshThrowHotspots()
                refreshStatusItem()
                if launchReason == .loginItem { showSettings() }
                advanceFirstRunTransition()
            }
        }
    }

    func saveProfile() {
        guard let backend else { return }
        let characterID = PixelCharacterCatalog.canonicalID(for: model.selectedCharacterID)
        guard model.isCharacterSelectable(characterID) else {
            model.errorMessage = "보유한 캐릭터만 프로필에 선택할 수 있습니다."
            model.selectedCharacterID = PixelCharacterCatalog.pixelHamsterID
            return
        }
        guard !model.isWorking, model.groupOperation == .idle else { return }
        model.isWorking = true
        model.errorMessage = nil
        model.successMessage = nil
        Task { [weak self] in
            guard let self else { return }
            defer { model.isWorking = false }
            do {
                let profile = try await backend.upsertProfile(
                    nickname: model.nickname,
                    characterID: characterID
                )
                model.apply(profile: profile)
                model.successMessage = "프로필을 저장했습니다."
                applyRequestedOverlayVisibility()
                refreshStatusItem()
                persistPreferences()
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
    }

    func createRoom() {
        guard let backend else { return }
        let roomName = model.newRoomName
        let characterID = PixelCharacterCatalog.canonicalID(for: model.selectedCharacterID)
        guard model.isCharacterSelectable(characterID) else {
            model.errorMessage = "보유한 캐릭터만 프로필에 선택할 수 있습니다."
            return
        }
        runMutation(groupOperation: .creating) {
            _ = try await backend.upsertProfile(
                nickname: self.model.nickname,
                characterID: characterID
            )
            let created = try await backend.createRoom(name: roomName)
            self.model.lastCreatedInviteCode = created.inviteCode
            if !created.storedInKeychain {
                self.model.errorMessage = "그룹은 생성됐지만 초대 코드를 키체인에 저장하지 못했습니다. 지금 표시된 코드를 따로 보관해 주세요."
            }
            self.model.newRoomName = ""
            self.model.preferences.activeRoomID = created.roomID
        }
    }

    func joinRoom() {
        guard let backend else { return }
        let inviteCode = model.inviteCode
        let characterID = PixelCharacterCatalog.canonicalID(for: model.selectedCharacterID)
        guard model.isCharacterSelectable(characterID) else {
            model.errorMessage = "보유한 캐릭터만 프로필에 선택할 수 있습니다."
            return
        }
        runMutation(groupOperation: .joining) {
            _ = try await backend.upsertProfile(
                nickname: self.model.nickname,
                characterID: characterID
            )
            let joined = try await backend.joinRoom(inviteCode: inviteCode)
            if !joined.storedInKeychain {
                self.model.errorMessage = "그룹에는 참여했지만 초대 코드를 키체인에 저장하지 못했습니다. 받은 코드를 따로 보관해 주세요."
            }
            self.model.inviteCode = ""
            self.model.preferences.activeRoomID = joined.roomID
        }
    }

    func renameRoom(_ roomID: UUID, name: String) {
        guard let backend else { return }
        runMutation(successMessage: "그룹 이름을 변경했습니다.") {
            try await backend.renameRoom(roomID, name: name)
        }
    }

    func removeRoomMember(_ roomID: UUID, userID: UUID) {
        guard let backend else { return }
        let nickname = model.rooms
            .first(where: { $0.id == roomID })?
            .members.first(where: { $0.userID == userID })?
            .nickname ?? "멤버"
        runMutation(successMessage: "\(nickname)님을 그룹에서 내보냈습니다.") {
            try await backend.removeRoomMember(roomID, userID: userID)
        }
    }

    func deleteRoom(_ roomID: UUID) {
        guard let backend else { return }
        let roomName = model.rooms.first(where: { $0.id == roomID })?.name ?? "그룹"
        runMutation(successMessage: "‘\(roomName)’ 그룹을 삭제했습니다.") {
            try await backend.deleteRoom(roomID)
        }
    }

    func selectRoom(_ roomID: UUID) {
        guard model.rooms.contains(where: { $0.id == roomID }), !model.isWorking else { return }
        switch model.groupOperation {
        case .creating, .joining:
            return
        case .switching(let targetRoomID) where targetRoomID == roomID:
            return
        case .idle, .switching:
            break
        }
        if model.activeRoom?.id == roomID, model.groupOperation == .idle { return }
        overlayWindows.dismissComposer()
        overlayWindows.invalidateThrowInteraction()
        typingChanged(false)
        model.errorMessage = nil
        roomSwitchPipeline.request(roomID)
    }

    func loadMessages(from backend: SideyBackend, roomID: UUID?) async throws {
        guard let roomID else {
            model.clearBubbles()
            return
        }
        let messages = try await backend.recentMessages(roomID: roomID)
        model.replaceMessages(roomID: roomID, with: messages)
    }

    func commitRoomSwitch(roomID: UUID, messages: [ChatMessage]) {
        guard model.rooms.contains(where: { $0.id == roomID }) else { return }
        model.replaceMessages(roomID: roomID, with: messages)
        model.preferences.activeRoomID = roomID
        model.markRoomRead(roomID)
        model.clearBubbles()
        model.connectionState = .online
        model.errorMessage = nil
        overlayWindows.invalidateThrowInteraction()
        refreshStatusItem()
        persistPreferences()
    }

    func handleRoomSwitchFailure(_ error: any Error, restoreError: (any Error)?) {
        if let restoreError {
            model.connectionState = .failed(restoreError.localizedDescription)
            model.setActiveRoomRealtimeConnected(false)
            model.errorMessage = "실시간 연결 복구 실패: \(restoreError.localizedDescription)"
        } else {
            model.errorMessage = "그룹 전환 실패: \(error.localizedDescription)"
        }
        refreshStatusItem()
    }

    func sendMessage(_ body: String) {
        guard let backend, let roomID = model.activeRoom?.id else {
            model.errorMessage = SideyBackendError.noActiveRoom.localizedDescription
            model.draft = body
            overlayWindows.presentComposer()
            return
        }
        guard let senderID = model.currentUserID else {
            model.errorMessage = "현재 사용자 정보를 확인하지 못했습니다."
            model.draft = body
            overlayWindows.presentComposer()
            return
        }
        let messageID = UUID()
        let revealMessage = !model.preferences.quietModeEnabled
        model.stageMessage(
            id: messageID,
            roomID: roomID,
            senderID: senderID,
            body: body,
            revealBubble: revealMessage
        )
        if revealMessage { scheduleBubbleExpiry() }
        Task { [weak self] in
            guard let self else { return }
            do {
                let message = try await backend.sendMessage(roomID: roomID, body: body, id: messageID)
                model.confirmMessage(message, revealBubble: revealMessage)
                model.errorMessage = nil
            } catch {
                model.errorMessage = "전송 실패: \(error.localizedDescription)"
                _ = model.failMessage(id: messageID, roomID: roomID)
                if model.activeRoom?.id == roomID {
                    overlayWindows.presentComposer()
                }
            }
        }
    }

    func runMutation(
        successMessage: String? = nil,
        groupOperation: GroupOperation? = nil,
        _ operation: @escaping @MainActor () async throws -> Void
    ) {
        guard let backend, !model.isWorking, model.groupOperation == .idle else { return }
        model.isWorking = true
        if let groupOperation { model.groupOperation = groupOperation }
        model.errorMessage = nil
        model.successMessage = nil
        Task { [weak self] in
            guard let self else { return }
            defer {
                model.isWorking = false
                if let groupOperation, model.groupOperation == groupOperation {
                    model.groupOperation = .idle
                }
            }
            var serverMutationCommitted = false
            do {
                let wasOnboardingComplete = model.preferences.onboardingComplete
                try await operation()
                serverMutationCommitted = true
                let postCommitWarning = model.errorMessage
                let snapshot = try await backend.loadSnapshot()
                let reconciliation = try await backend.syncRealtime(
                    rooms: snapshot.rooms,
                    activeRoomID: model.resolvedActiveRoomID(in: snapshot.rooms)
                )
                applyBackendReconciliation(reconciliation)
                model.connectionState = .online
                model.errorMessage = postCommitWarning
                model.successMessage = successMessage
                if !wasOnboardingComplete && model.preferences.onboardingComplete {
                    model.activeSettingsPage = .groups
                    settingsWindow.transitionFromOnboardingToSettings()
                }
                applyRequestedOverlayVisibility()
                refreshStatusItem()
                persistPreferences()
            } catch {
                model.successMessage = nil
                model.errorMessage = serverMutationCommitted
                    ? "서버 작업은 완료됐지만 상태 동기화에 실패했습니다: \(error.localizedDescription)"
                    : error.localizedDescription
            }
        }
    }

    func applyBackendSnapshot(_ snapshot: BackendSnapshot, currentUserID: UUID?) {
        if let activeRoomID = model.activeRoom?.id,
           !snapshot.rooms.contains(where: { $0.id == activeRoomID }) {
            overlayWindows.dismissComposer()
            typingChanged(false)
            model.clearBubbles()
        }
        model.apply(snapshot: snapshot, currentUserID: currentUserID)
    }

    func handleBackendEvent(_ event: BackendEvent) {
        switch event {
        case .snapshot(let snapshot):
            applyBackendSnapshot(snapshot, currentUserID: model.currentUserID)
            applyRequestedOverlayVisibility()
            refreshStatusItem()
            persistPreferences()
        case .reconciliation(let reconciliation):
            applyBackendReconciliation(reconciliation)
            applyRequestedOverlayVisibility()
            refreshStatusItem()
            persistPreferences()
        case .message(let message):
            let isActiveRoom = message.roomID == model.activeRoom?.id
            let revealMessage = isActiveRoom && !model.preferences.quietModeEnabled
            let isNew = model.confirmMessage(message, revealBubble: revealMessage)
            guard isNew else { return }
            if message.senderID != model.currentUserID && (!isActiveRoom || model.preferences.quietModeEnabled) {
                model.incrementUnread(in: message.roomID)
            }
            if revealMessage { scheduleBubbleExpiry() }
            refreshStatusItem()
        case .messageDeleted(let roomID, let messageID):
            model.removeMessage(id: messageID, roomID: roomID)
        case .messagesInvalidated(let roomID):
            guard let backend else { return }
            Task { [weak self] in
                guard let self else { return }
                do {
                    let messages = try await backend.recentMessages(roomID: roomID)
                    model.replaceMessages(roomID: roomID, with: messages)
                } catch {
                    model.errorMessage = "메시지 보관 상태 동기화 실패: \(error.localizedDescription)"
                }
            }
        case .messagesReplaced(let roomID, let messages):
            model.replaceMessages(roomID: roomID, with: messages)
        case .presence(let roomID, let userID, let state):
            model.updatePresence(roomID: roomID, userID: userID, state: state)
            overlayWindows.refreshThrowHotspots()
        case .typing(let roomID, let userID, let active):
            model.updateTyping(roomID: roomID, userID: userID, active: active)
        case .characterPulse(let event):
            guard event.roomID == model.activeRoom?.id,
                  model.activeRoom?.members.contains(where: { $0.userID == event.userID }) == true,
                  characterPulseCooldown.accept(
                    roomID: event.roomID,
                    userID: event.userID,
                    uptime: ProcessInfo.processInfo.systemUptime
                  )
            else { return }
            overlayWindows.playCharacterPulse(event)
        case .characterThrow(let event):
            guard event.roomID == model.activeRoom?.id,
                  event.actorUserID != event.targetUserID,
                  model.activeRoom?.members.contains(where: { $0.userID == event.actorUserID }) == true,
                  model.activeRoom?.members.contains(where: { $0.userID == event.targetUserID }) == true,
                  characterThrowCooldown.accept(
                    actorUserID: event.actorUserID,
                    uptime: ProcessInfo.processInfo.systemUptime
                  )
            else { return }
            overlayWindows.playCharacterThrow(event)
        case .connection(let status):
            let previousStatus = backendConnectionStatus
            backendConnectionStatus = status
            model.connectionState = status.isReady ? .online : .connecting
            model.setActiveRoomRealtimeConnected(status.activeRoomTransportConnected)
            if previousStatus?.activeRoomTransportConnected == true,
               !status.activeRoomTransportConnected {
                overlayWindows.invalidateThrowInteraction()
            }
            overlayWindows.refreshThrowHotspots()
        case .technicalError(let message):
            model.errorMessage = message
        }
    }

    func applyBackendReconciliation(_ reconciliation: BackendReconciliation) {
        applyBackendSnapshot(reconciliation.snapshot, currentUserID: model.currentUserID)
        if let activeRoomID = reconciliation.activeRoomID {
            model.preferences.activeRoomID = activeRoomID
            model.replaceMessages(roomID: activeRoomID, with: reconciliation.activeMessages)
        }
    }

    func scheduleBubbleExpiry() {
        bubbleExpiryTask?.cancel()
        bubbleExpiryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }
                model.dismissExpiredBubbles()
                if model.activeBubbles.isEmpty { return }
            }
        }
    }

    func localPresenceChanged(_ state: PresenceState) {
        model.presence = state
        guard let backend else { return }
        Task {
            do { try await backend.setLocalPresence(state) }
            catch { model.connectionState = .failed(error.localizedDescription) }
        }
    }

    func typingChanged(_ active: Bool) {
        if let roomID = model.activeRoom?.id, let userID = model.currentUserID {
            model.updateTyping(roomID: roomID, userID: userID, active: active)
        }
        guard let backend else { return }
        let actions = typingLease.update(active: active, roomID: model.activeRoom?.id)
        for action in actions {
            switch action {
            case .stop(let stoppedRoomID):
                typingTask?.cancel()
                typingTask = nil
                Task { try? await backend.broadcastTyping(roomID: stoppedRoomID, event: "typing_stop") }
            case .start(let startedRoomID):
                typingTask?.cancel()
                typingTask = Task {
                    try? await backend.broadcastTyping(roomID: startedRoomID, event: "typing_start")
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else { return }
                        try? await backend.broadcastTyping(roomID: startedRoomID, event: "typing_keepalive")
                    }
                }
            }
        }
    }

    func characterDoubleClicked() {
        guard let room = model.activeRoom,
              let userID = model.currentUserID,
              room.members.contains(where: { $0.userID == userID }),
              characterPulseCooldown.accept(
                roomID: room.id,
                userID: userID,
                uptime: ProcessInfo.processInfo.systemUptime
              )
        else { return }

        let event = CharacterPulseEvent(id: UUID(), roomID: room.id, userID: userID)
        overlayWindows.playCharacterPulse(event)
        guard let backend else { return }
        Task { try? await backend.broadcastCharacterPulse(roomID: room.id, eventID: event.id) }
    }

    func characterThrowRequested(targetUserID: UUID) {
        guard model.activeRoomRealtimeAvailable,
              let room = model.activeRoom,
              let actorUserID = model.currentUserID,
              actorUserID != targetUserID,
              let actor = room.members.first(where: { $0.userID == actorUserID }),
              model.pixelWorldMembers.contains(where: {
                  $0.id == targetUserID && CharacterThrowTargetPolicy.canTarget($0)
              }),
              characterThrowCooldown.accept(
                  actorUserID: actorUserID,
                  uptime: ProcessInfo.processInfo.systemUptime
              )
        else { return }

        let event = CharacterThrowEvent(
            id: UUID(),
            roomID: room.id,
            actorUserID: actorUserID,
            targetUserID: targetUserID,
            sourceCharacterID: PixelCharacterCatalog.canonicalID(for: actor.characterID)
        )
        overlayWindows.playCharacterThrow(event)
        guard let backend else { return }
        Task {
            try? await backend.broadcastCharacterThrow(
                roomID: room.id,
                eventID: event.id,
                targetUserID: targetUserID
            )
        }
    }

    func refreshCommerceState(productID: String? = nil) {
        guard releaseChannel.storeAvailability.allowsCommerceActions,
              let backend
        else { return }
        let productIDs = productID.map { [$0] } ?? model.commerceProducts.map(\.id)

        for productID in productIDs {
            guard model.commerceProduct(id: productID) != nil,
                  commerceProductTasks[productID] == nil
            else { continue }

            model.setCommerceWorking(true, productID: productID)
            commerceProductTasks[productID] = Task { [weak self] in
                guard let self else { return }
                defer {
                    model.setCommerceWorking(false, productID: productID)
                    commerceProductTasks[productID] = nil
                }
                do {
                    let state = try await backend.commerceState(productID: productID)
                    model.apply(commerceState: state)
                } catch is CancellationError {
                    return
                } catch {
                    model.setCommercePurchaseState(
                        .error("상점 상태를 불러오지 못했습니다."),
                        productID: productID
                    )
                }
            }
        }
    }

    private func connectGoogleForCommerce(productID: String) {
        guard releaseChannel.storeAvailability.allowsCommerceActions,
              let backend,
              model.commerceProduct(id: productID) != nil,
              commerceProductTasks[productID] == nil,
              googleConnectionProductID == nil || googleConnectionProductID == productID
        else { return }

        googleConnectionProductID = productID
        model.setCommerceWorking(true, productID: productID)
        model.errorMessage = nil
        commerceProductTasks[productID] = Task { [weak self] in
            guard let self else { return }
            var didOpenBrowser = false
            defer {
                if !didOpenBrowser {
                    googleConnectionProductID = nil
                }
                model.setCommerceWorking(false, productID: productID)
                commerceProductTasks[productID] = nil
            }
            do {
                let url = try await backend.googleIdentityLinkURL()
                guard NSWorkspace.shared.open(url) else {
                    throw SideyBackendError.remote("기본 브라우저를 열지 못했습니다.")
                }
                didOpenBrowser = true
                model.successMessage = "브라우저에서 Google 계정 연결을 완료해 주세요."
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

    func purchase(productID: String) {
        guard releaseChannel.storeAvailability.allowsCommerceActions,
              let backend,
              let productState = model.commerceProduct(id: productID),
              commerceProductTasks[productID] == nil,
              productState.purchaseState != .owned
        else { return }

        if productState.purchaseState == .googleConnectionRequired {
            connectGoogleForCommerce(productID: productID)
            return
        }
        guard productState.purchaseState == .available
                || productState.purchaseState == .refunded
        else { return }

        let product = productState.product
        model.setCommerceWorking(true, productID: productID)
        model.setCommercePurchaseState(.openingCheckout, productID: productID)
        model.errorMessage = nil
        commerceProductTasks[productID] = Task { [weak self] in
            guard let self else { return }
            defer {
                model.setCommerceWorking(false, productID: productID)
                commerceProductTasks[productID] = nil
            }
            do {
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
                        model.successMessage = "\(product.displayName) 구매가 완료되었습니다."
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
}
