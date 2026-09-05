import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var preferences: AppPreferences
    var overlayVisibility: OverlayVisibility
    var overlayVisible: Bool { overlayVisibility.isVisible }
    var presence: PresenceState = .online
    var nickname: String
    private(set) var confirmedNickname: String?
    var selectedCharacterID: String
    private(set) var pendingCharacterID: String?
    private(set) var equippedBubbleStyleID: String?
    private(set) var equippedThrowableID: String?
    private(set) var activeEntitlementKeys: Set<String> = []
    private(set) var snapshotActiveEntitlementKeys: Set<String> = []
    private(set) var cosmeticEquipmentRequests: [CommerceProductKind: CosmeticEquipmentRequest] = [:]
    private(set) var commerceProducts: [CommerceProductState]
    var draft = ""
    private(set) var messageLedger = MessageLedger()
    private(set) var messageOutbox = MessageOutbox()
    private(set) var bubbleLedger = ActiveBubbleLedger()
    var availableScreens: [OverlayScreenOption] = []
    var activeSettingsPage: SettingsPage = .profile
    var connectionState: BackendConnectionState = .idle
    var authenticationRequired = false
    var accountOperationInProgress = false
    private(set) var activeRoomTransportConnected = false
    var rooms: [Room] = []
    var hasProfile = false
    var currentUserID: UUID?
    var errorMessage: String?
    private var successFeedback = SuccessFeedbackState()
    var successMessage: String? { successFeedback.message }
    var successMessageGeneration: Int { successFeedback.generation }
    var isWorking = false
    var groupOperation: GroupOperation = .idle
    var newRoomName = ""
    var inviteCode = ""
    var lastCreatedInviteCode: String?
    var launchAtLogin: Bool
    private(set) var unreadCounts: [UUID: Int] = [:]
    private var basePresence: [MemberPresenceKey: PresenceState] = [:]
    private var typingMembers: Set<MemberPresenceKey> = []

    init(
        preferences: AppPreferences,
        commerceProducts: [CommerceProduct] = CommerceCatalog.products
    ) {
        self.preferences = preferences
        self.overlayVisibility = OverlayVisibility(isVisible: preferences.overlayVisible)
        self.nickname = preferences.nickname
        self.confirmedNickname = preferences.onboardingComplete
            ? ProfileValidator.normalizedNickname(preferences.nickname)
            : nil
        self.selectedCharacterID = PixelCharacterCatalog.canonicalID(for: preferences.selectedCharacterID)
        self.pendingCharacterID = nil
        self.equippedBubbleStyleID = nil
        self.equippedThrowableID = nil
        self.launchAtLogin = preferences.launchAtLogin
        self.commerceProducts = commerceProducts.map {
            CommerceProductState(
                product: $0,
                purchaseState: .confirming,
                isWorking: false
            )
        }
    }

    func setOverlayVisibility(_ visibility: OverlayVisibility) {
        overlayVisibility = visibility
        preferences.overlayVisible = visibility.isVisible
    }

    func acceptDraft() -> String? {
        let normalized = MessageValidator.normalized(draft)
        guard MessageValidator.isValid(normalized) else { return nil }
        draft = ""
        return normalized
    }

    var activeRoom: Room? {
        if let activeRoomID = preferences.activeRoomID,
           let match = rooms.first(where: { $0.id == activeRoomID }) {
            return match
        }
        return rooms.first
    }

    var realtimeActiveRoomID: UUID? {
        if case .switching(let roomID) = groupOperation { return roomID }
        return resolvedActiveRoomID(in: rooms)
    }

    func resolvedActiveRoomID(in availableRooms: [Room]) -> UUID? {
        if let preferredRoomID = preferences.activeRoomID,
           availableRooms.contains(where: { $0.id == preferredRoomID }) {
            return preferredRoomID
        }
        return availableRooms.first?.id
    }

    var groupMutationsDisabled: Bool {
        isWorking || groupOperation.blocksMutations
    }

    var normalizedNicknameDraft: String {
        ProfileValidator.normalizedNickname(nickname)
    }

    var nicknameDraftIsValid: Bool {
        ProfileValidator.isValidNickname(nickname)
    }

    var hasNicknameChanges: Bool {
        guard let confirmedNickname else { return false }
        return normalizedNicknameDraft != confirmedNickname
    }

    func presentSuccess(_ message: String) {
        successFeedback.present(message)
    }

    func dismissSuccess(generation: Int? = nil) {
        successFeedback.dismiss(generation: generation)
    }

    func apply(snapshot: BackendSnapshot, currentUserID: UUID?) {
        self.currentUserID = currentUserID
        authenticationRequired = false
        activeEntitlementKeys = snapshot.activeEntitlementKeys
        snapshotActiveEntitlementKeys = snapshot.activeEntitlementKeys
        hasProfile = snapshot.profile != nil
        var updatedRooms = snapshot.rooms
        let previousBasePresence = basePresence
        let previousTypingMembers = typingMembers
        for roomIndex in updatedRooms.indices {
            for memberIndex in updatedRooms[roomIndex].members.indices {
                let member = updatedRooms[roomIndex].members[memberIndex]
                let key = MemberPresenceKey(roomID: updatedRooms[roomIndex].id, userID: member.userID)
                if let state = previousBasePresence[key] {
                    updatedRooms[roomIndex].members[memberIndex].presence = previousTypingMembers.contains(key)
                        ? .typing
                        : state
                }
            }
        }
        rooms = updatedRooms
        let retainedRoomIDs = Set(updatedRooms.map(\.id))
        messageLedger.retain(roomIDs: retainedRoomIDs)
        messageOutbox.retain(roomIDs: retainedRoomIDs)
        unreadCounts = unreadCounts.filter { roomID, _ in
            updatedRooms.contains(where: { $0.id == roomID })
        }
        let validKeys = Set(updatedRooms.flatMap { room in
            room.members.map { member in
                MemberPresenceKey(roomID: room.id, userID: member.userID)
            }
        })
        basePresence = Dictionary(uniqueKeysWithValues: updatedRooms.flatMap { room in
            room.members.map { member in
                let key = MemberPresenceKey(roomID: room.id, userID: member.userID)
                return (key, previousBasePresence[key] ?? member.presence)
            }
        })
        typingMembers = previousTypingMembers.intersection(validKeys)
        if let profile = snapshot.profile {
            let shouldAdoptNickname = confirmedNickname.map {
                normalizedNicknameDraft == $0
            } ?? true
            confirmedNickname = ProfileValidator.normalizedNickname(profile.nickname)
            if shouldAdoptNickname { nickname = profile.nickname }
            preferences.nickname = profile.nickname
            selectedCharacterID = PixelCharacterCatalog.canonicalID(for: profile.characterID)
            preferences.selectedCharacterID = selectedCharacterID
            equippedBubbleStyleID = profile.equippedBubbleStyleID
            equippedThrowableID = profile.equippedThrowableID
        } else {
            confirmedNickname = nil
            equippedBubbleStyleID = nil
            equippedThrowableID = nil
        }
        enforceSelectableCurrentCharacter()
        enforceOwnedCosmetics()
        preferences.activeRoomID = resolvedActiveRoomID(in: rooms)
        preferences.onboardingComplete = snapshot.profile != nil && !rooms.isEmpty
    }

    func apply(profile: Profile) {
        guard currentUserID == profile.id else { return }
        hasProfile = true
        let shouldAdoptNickname = confirmedNickname.map {
            normalizedNicknameDraft == $0
        } ?? true
        confirmedNickname = ProfileValidator.normalizedNickname(profile.nickname)
        if shouldAdoptNickname { nickname = profile.nickname }
        preferences.nickname = profile.nickname
        selectedCharacterID = PixelCharacterCatalog.canonicalID(for: profile.characterID)
        preferences.selectedCharacterID = selectedCharacterID
        equippedBubbleStyleID = profile.equippedBubbleStyleID
        equippedThrowableID = profile.equippedThrowableID
        for roomIndex in rooms.indices {
            guard let memberIndex = rooms[roomIndex].members.firstIndex(where: {
                $0.userID == profile.id
            }) else { continue }
            rooms[roomIndex].members[memberIndex].nickname = profile.nickname
            rooms[roomIndex].members[memberIndex].characterID = selectedCharacterID
            rooms[roomIndex].members[memberIndex].equippedBubbleStyleID = equippedBubbleStyleID
        }
        enforceSelectableCurrentCharacter()
        enforceOwnedCosmetics()
    }

    var selectableCharacters: [PixelCharacterDefinition] {
        PixelCharacterCatalog.selectableDefinitions(entitlementKeys: activeEntitlementKeys)
    }

    func isCharacterSelectable(_ characterID: String) -> Bool {
        PixelCharacterCatalog.canSelect(characterID, entitlementKeys: activeEntitlementKeys)
    }

    func apply(commerceState: CommerceState) {
        guard let index = commerceProducts.firstIndex(where: {
            $0.id == commerceState.product.id
        }) else { return }
        commerceProducts[index].product = commerceState.product
        commerceProducts[index].purchaseState = commerceState.purchaseState
        commerceProducts[index].isEquipped = commerceState.isEquipped
        if commerceState.entitlementStatus == "active" {
            activeEntitlementKeys.insert(commerceState.product.entitlementKey)
            if commerceState.isEquipped {
                switch commerceState.product.kind {
                case .bubble:
                    equippedBubbleStyleID = commerceState.product.catalogItemID
                case .throwable:
                    equippedThrowableID = commerceState.product.catalogItemID
                case .character:
                    break
                }
            }
        } else {
            activeEntitlementKeys.remove(commerceState.product.entitlementKey)
            enforceSelectableCurrentCharacter()
            enforceOwnedCosmetics()
        }
    }

    func apply(commerceStates: [CommerceState]) {
        for state in commerceStates { apply(commerceState: state) }
        if commerceStates.contains(where: { $0.product.kind == .bubble }) {
            equippedBubbleStyleID = commerceStates.first(where: {
                $0.product.kind == .bubble
                    && $0.entitlementStatus == "active"
                    && $0.isEquipped
            })?.product.catalogItemID
        }
        if commerceStates.contains(where: { $0.product.kind == .throwable }) {
            equippedThrowableID = commerceStates.first(where: {
                $0.product.kind == .throwable
                    && $0.entitlementStatus == "active"
                    && $0.isEquipped
            })?.product.catalogItemID
        }
        enforceOwnedCosmetics()
    }

    func commerceProduct(id: String) -> CommerceProductState? {
        commerceProducts.first { $0.id == id }
    }

    func ownedProfileCosmeticProducts(for kind: CommerceProductKind) -> [CommerceProduct] {
        guard kind == .bubble || kind == .throwable else { return [] }
        return CommerceCatalog.cosmeticProducts
            .filter {
                $0.kind == kind && snapshotActiveEntitlementKeys.contains($0.entitlementKey)
            }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func equippedCosmeticID(for kind: CommerceProductKind) -> String? {
        switch kind {
        case .bubble: equippedBubbleStyleID
        case .throwable: equippedThrowableID
        case .character: nil
        }
    }

    @discardableResult
    func beginCosmeticEquipmentRequest(
        kind: CommerceProductKind,
        catalogItemID: String?
    ) -> Bool {
        guard kind != .character, cosmeticEquipmentRequests[kind] == nil else { return false }
        cosmeticEquipmentRequests[kind] = CosmeticEquipmentRequest(
            kind: kind,
            catalogItemID: catalogItemID
        )
        return true
    }

    func endCosmeticEquipmentRequest(kind: CommerceProductKind) {
        cosmeticEquipmentRequests.removeValue(forKey: kind)
    }

    func cosmeticEquipmentRequest(for kind: CommerceProductKind) -> CosmeticEquipmentRequest? {
        cosmeticEquipmentRequests[kind]
    }

    @discardableResult
    func beginCharacterEquipmentRequest(characterID: String) -> Bool {
        let canonicalID = PixelCharacterCatalog.canonicalID(for: characterID)
        guard pendingCharacterID == nil,
              selectedCharacterID != canonicalID,
              isCharacterSelectable(canonicalID)
        else { return false }
        pendingCharacterID = canonicalID
        return true
    }

    func endCharacterEquipmentRequest() {
        pendingCharacterID = nil
    }

    var snapshotActiveEntitlements: Set<String> {
        snapshotActiveEntitlementKeys
    }

    func setCommerceWorking(_ isWorking: Bool, productID: String) {
        guard let index = commerceProducts.firstIndex(where: { $0.id == productID }) else { return }
        commerceProducts[index].isWorking = isWorking
    }

    func setCommercePurchaseState(_ state: CommercePurchaseState, productID: String) {
        guard let index = commerceProducts.firstIndex(where: { $0.id == productID }) else { return }
        commerceProducts[index].purchaseState = state
    }

    func setCommerceLocalizedPrices(_ prices: [String: String]) {
        for index in commerceProducts.indices {
            commerceProducts[index].localizedPrice = prices[commerceProducts[index].id]
        }
    }

    private func enforceSelectableCurrentCharacter() {
        guard !isCharacterSelectable(selectedCharacterID) else { return }
        selectedCharacterID = PixelCharacterCatalog.pixelHamsterID
        preferences.selectedCharacterID = selectedCharacterID
        guard let currentUserID else { return }
        for roomIndex in rooms.indices {
            guard let memberIndex = rooms[roomIndex].members.firstIndex(where: {
                $0.userID == currentUserID
            }) else { continue }
            rooms[roomIndex].members[memberIndex].characterID = PixelCharacterCatalog.pixelHamsterID
        }
    }

    private func enforceOwnedCosmetics() {
        if let equippedBubbleStyleID,
           !CommerceCatalog.products.contains(where: {
               $0.kind == .bubble
                   && $0.catalogItemID == equippedBubbleStyleID
                   && activeEntitlementKeys.contains($0.entitlementKey)
           }) {
            self.equippedBubbleStyleID = nil
        }
        if let equippedThrowableID,
           !CommerceCatalog.products.contains(where: {
               $0.kind == .throwable
                   && $0.catalogItemID == equippedThrowableID
                   && activeEntitlementKeys.contains($0.entitlementKey)
           }) {
            self.equippedThrowableID = nil
        }
        guard let currentUserID else { return }
        for roomIndex in rooms.indices {
            guard let memberIndex = rooms[roomIndex].members.firstIndex(where: {
                $0.userID == currentUserID
            }) else { continue }
            rooms[roomIndex].members[memberIndex].equippedBubbleStyleID = equippedBubbleStyleID
        }
        for index in commerceProducts.indices {
            let product = commerceProducts[index].product
            commerceProducts[index].isEquipped = switch product.kind {
            case .character: product.characterID == selectedCharacterID
            case .bubble: product.catalogItemID == equippedBubbleStyleID
            case .throwable: product.catalogItemID == equippedThrowableID
            }
        }
    }

    var effectiveLocalPresence: PresenceState {
        // Snapshot/message reconciliation may still be running after the
        // Realtime transport has already recovered. Presence is published on
        // that transport, so do not leave only the local character gray while
        // peers can already see it online.
        if activeRoomRealtimeAvailable {
            return presence
        }
        return switch connectionState {
        case .connecting:
            .reconnecting
        case .idle, .failed, .online:
            .offline
        }
    }

    var activeRoomRealtimeAvailable: Bool {
        activeRoomTransportConnected || connectionState == .online
    }

    var pixelWorldMembers: [PixelWorldMember] {
        guard let activeRoom else { return [] }
        return activeRoom.members.compactMap { member in
            let key = MemberPresenceKey(roomID: activeRoom.id, userID: member.userID)
            let isCurrentUser = member.userID == currentUserID
            let isTyping = typingMembers.contains(key)
            let baseState = isCurrentUser
                ? effectiveLocalPresence
                : (basePresence[key] ?? (member.presence == .typing ? .online : member.presence))
            guard isCurrentUser || preferences.showOfflineMembers || baseState != .offline else { return nil }
            return PixelWorldMember(
                id: member.userID,
                nickname: ProfileValidator.displayNickname(member.nickname),
                characterID: PixelCharacterCatalog.canonicalID(for: member.characterID),
                presence: baseState,
                isTyping: isTyping,
                isCurrentUser: isCurrentUser,
                equippedBubbleStyleID: member.equippedBubbleStyleID
            )
        }
    }

    var activeBubbles: [ActiveBubble] { bubbleLedger.bubbles }

    var totalUnreadCount: Int {
        unreadCounts.values.reduce(0, +)
    }

    var activeRoomUnreadCount: Int {
        activeRoom.map { unreadCounts[$0.id, default: 0] } ?? 0
    }

    func unreadCount(in roomID: UUID) -> Int {
        unreadCounts[roomID, default: 0]
    }

    func markRoomRead(_ roomID: UUID) {
        unreadCounts.removeValue(forKey: roomID)
    }

    func incrementUnread(in roomID: UUID) {
        unreadCounts[roomID, default: 0] += 1
    }

    func updatePresence(roomID: UUID, userID: UUID, state: PresenceState) {
        let key = MemberPresenceKey(roomID: roomID, userID: userID)
        basePresence[key] = state
        if state == .offline {
            typingMembers.remove(key)
        }
        guard let roomIndex = rooms.firstIndex(where: { $0.id == roomID }),
              let memberIndex = rooms[roomIndex].members.firstIndex(where: { $0.userID == userID })
        else { return }
        rooms[roomIndex].members[memberIndex].presence = typingMembers.contains(key) ? .typing : state
    }

    func updateTyping(roomID: UUID, userID: UUID, active: Bool) {
        let key = MemberPresenceKey(roomID: roomID, userID: userID)
        if active {
            typingMembers.insert(key)
        } else {
            typingMembers.remove(key)
        }
        guard let roomIndex = rooms.firstIndex(where: { $0.id == roomID }),
              let memberIndex = rooms[roomIndex].members.firstIndex(where: { $0.userID == userID })
        else { return }
        if active {
            rooms[roomIndex].members[memberIndex].presence = .typing
        } else {
            rooms[roomIndex].members[memberIndex].presence = basePresence[key] ?? .online
        }
    }

    func setActiveRoomRealtimeConnected(_ connected: Bool) {
        activeRoomTransportConnected = connected
        // Typing is a transient Broadcast lease. A disconnect can lose the
        // matching typing_stop event, so never carry typing across reconnect.
        guard let activeRoomID = activeRoom?.id,
              let roomIndex = rooms.firstIndex(where: { $0.id == activeRoomID })
        else { return }
        if !connected {
            typingMembers = typingMembers.filter { $0.roomID != activeRoomID }
        }
        for memberIndex in rooms[roomIndex].members.indices {
            let member = rooms[roomIndex].members[memberIndex]
            let key = MemberPresenceKey(roomID: activeRoomID, userID: member.userID)
            if connected {
                rooms[roomIndex].members[memberIndex].presence = typingMembers.contains(key)
                    ? .typing
                    : (basePresence[key] ?? .offline)
            } else if member.presence != .offline {
                rooms[roomIndex].members[memberIndex].presence = .reconnecting
                if member.userID != currentUserID {
                    // Presence state is a lease on this active room's channel.
                    // Do not invalidate unrelated rooms during a selective swap.
                    basePresence[key] = .offline
                }
            }
        }
    }

    func stageMessage(
        id: UUID,
        roomID: UUID,
        senderID: UUID,
        body: String,
        revealBubble: Bool = true,
        now: Date = .now
    ) {
        messageOutbox.stage(id: id, roomID: roomID, senderID: senderID, body: body, createdAt: now)
        if revealBubble, roomID == activeRoom?.id {
            bubbleLedger.show(
                senderID: senderID,
                messageID: id,
                body: body,
                bubbleStyleID: equippedBubbleStyleID,
                expiresAt: now.addingTimeInterval(ActiveBubbleLedger.defaultLifetime)
            )
        }
    }

    @discardableResult
    func confirmMessage(_ message: ChatMessage, revealBubble: Bool = true) -> Bool {
        let wasOutgoing = messageOutbox.confirm(id: message.id, roomID: message.roomID)
        let wasNewToLedger = messageLedger.confirm(message)
        let isNew = wasNewToLedger && !wasOutgoing
        if (isNew || wasOutgoing), revealBubble, message.roomID == activeRoom?.id {
            bubbleLedger.show(
                senderID: message.senderID,
                messageID: message.id,
                body: message.body,
                bubbleStyleID: message.bubbleStyleID,
                expiresAt: message.createdAt.addingTimeInterval(ActiveBubbleLedger.defaultLifetime)
            )
            bubbleLedger.prune()
        }
        return isNew
    }

    func failMessage(id: UUID, roomID: UUID) -> OutgoingMessage? {
        let message = messageOutbox.fail(id: id, roomID: roomID)
        bubbleLedger.remove(messageID: id)
        return message
    }

    func replaceMessages(roomID: UUID, with messages: [ChatMessage]) {
        messageLedger.replaceConfirmed(roomID: roomID, with: messages)
        for message in messages {
            _ = messageOutbox.confirm(id: message.id, roomID: roomID)
        }
    }

    func removeMessage(id: UUID, roomID: UUID) {
        messageLedger.remove(id: id, roomID: roomID)
        bubbleLedger.remove(messageID: id)
    }

    func clearBubbles() {
        bubbleLedger.removeAll()
    }

    func dismissExpiredBubbles(at date: Date = .now) {
        bubbleLedger.prune(at: date)
        messageLedger.prune(now: date)
    }
}

private struct MemberPresenceKey: Hashable {
    let roomID: UUID
    let userID: UUID
}
