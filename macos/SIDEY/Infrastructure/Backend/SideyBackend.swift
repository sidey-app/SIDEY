import Foundation
import Supabase

actor SideyBackend {
    nonisolated let events: AsyncStream<BackendEvent>

    private let client: SupabaseClient
    private let keychain: KeychainStore
    private let authCallbackURL: URL
    private let legacyRefreshAccount: String
    private let inviteAccountPrefix: String
    private let eventContinuation: AsyncStream<BackendEvent>.Continuation
    private var channels: [UUID: RoomRealtimeChannels] = [:]
    private var channelRecoveryTasks: [UUID: Task<Void, Never>] = [:]
    private var channelRecoveryAttempts: [UUID: Int] = [:]
    private var channelsBeingAdded: Set<UUID> = []
    private var realtimeWatchdogTask: Task<Void, Never>?
    private var recoveryReconciliationTask: Task<Void, Never>?
    private var recoveryReconciliationGeneration = 0
    private var recoveryReconciliationAttempt = 0
    private var structuralSnapshotTask: Task<Void, Never>?
    private var structuralSnapshotAttempt = 0
    private var typingExpiryTasks: [String: Task<Void, Never>] = [:]
    private var activeRoomID: UUID?
    private var localPresence: PresenceState = .online
    private lazy var presencePublicationQueue = PresencePublicationQueue<PresencePublicationIntent> {
        [weak self] intent in
        guard let self else { return }
        try await self.performPresencePublication(intent)
    }
    private var connectionTracker = RealtimeConnectionTracker()
    private var lastEmittedConnectionStatus: BackendConnectionStatus?
    private var recoveryReconciled = false
    private var isShuttingDown = false

    init(
        configuration: RuntimeConfiguration,
        keychain: KeychainStore = KeychainStore(),
        authCallbackURL: URL = SideyAuthCallback.callbackURL()
    ) {
        let eventPair = AsyncStream<BackendEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(256)
        )
        self.events = eventPair.stream
        self.eventContinuation = eventPair.continuation
        let fingerprint = configuration.backendFingerprint
        let legacyRefreshAccount = "supabase-refresh:\(fingerprint):default"
        self.keychain = keychain
        self.authCallbackURL = authCallbackURL
        self.legacyRefreshAccount = legacyRefreshAccount
        self.inviteAccountPrefix = "room-invite:\(fingerprint):default:"

        let storage = SideyAuthStorage(
            keychain: keychain,
            legacyRefreshAccount: legacyRefreshAccount
        )
        let authOptions = SupabaseClientOptions.AuthOptions(
            storage: storage,
            storageKey: "supabase-session:\(fingerprint):default",
            autoRefreshToken: true,
            emitLocalSessionAsInitialSession: true
        )
        let options = SupabaseClientOptions(auth: authOptions)
        self.client = SupabaseClient(
            supabaseURL: configuration.supabaseURL,
            supabaseKey: configuration.supabasePublishableKey,
            options: options
        )
    }

    func boot(requireExistingSession: Bool = false) async throws -> BackendSnapshot {
        _ = try await restoreOrCreateSession(requireExistingSession: requireExistingSession)
        return try await loadSnapshot()
    }

    func syncRealtime(rooms: [Room], activeRoomID: UUID?) async throws -> BackendReconciliation {
        guard !isShuttingDown else { throw CancellationError() }
        try await configureChannels(rooms: rooms, activeRoomID: activeRoomID)
        return try await reconcileCurrentState(emitEvents: false)
    }

    func setActiveRoom(_ roomID: UUID?) async throws {
        activeRoomID = roomID
        try await publishPresence()
    }

    func setLocalPresence(_ state: PresenceState) async throws {
        localPresence = state == .away ? .away : .online
        try await publishPresence()
    }

    func broadcastTyping(roomID: UUID, event: String) async throws {
        guard ["typing_start", "typing_keepalive", "typing_stop"].contains(event),
              let roomChannels = subscribedChannels(roomID: roomID)
        else { return }
        _ = try await client.rpc(
            "broadcast_room_event",
            params: BroadcastRoomEventParameters(
                roomID: roomID,
                realtimeEpoch: roomChannels.epoch,
                event: event == "typing_keepalive" ? "typing_start" : event,
                eventID: nil
            )
        ).execute()
    }

    func broadcastCharacterPulse(roomID: UUID, eventID: UUID) async throws {
        guard roomID == activeRoomID,
              let roomChannels = subscribedChannels(roomID: roomID)
        else { return }
        _ = try await client.rpc(
            "broadcast_room_event",
            params: BroadcastRoomEventParameters(
                roomID: roomID,
                realtimeEpoch: roomChannels.epoch,
                event: "character_pulse",
                eventID: eventID
            )
        ).execute()
    }

    func broadcastCharacterThrow(roomID: UUID, eventID: UUID, targetUserID: UUID) async throws {
        guard roomID == activeRoomID,
              let roomChannels = subscribedChannels(roomID: roomID)
        else { return }
        _ = try await client.rpc(
            "broadcast_character_throw",
            params: BroadcastCharacterThrowParameters(
                roomID: roomID,
                realtimeEpoch: roomChannels.epoch,
                eventID: eventID,
                targetUserID: targetUserID
            )
        ).execute()
    }

    func shutdown() async {
        isShuttingDown = true
        connectionTracker.replaceDesiredRoomIDs([])
        realtimeWatchdogTask?.cancel()
        realtimeWatchdogTask = nil
        recoveryReconciliationTask?.cancel()
        recoveryReconciliationTask = nil
        structuralSnapshotTask?.cancel()
        structuralSnapshotTask = nil
        for task in channelRecoveryTasks.values { task.cancel() }
        channelRecoveryTasks.removeAll()
        channelRecoveryAttempts.removeAll()
        for roomID in Array(channels.keys) { await removeChannel(roomID) }
        for task in typingExpiryTasks.values { task.cancel() }
        typingExpiryTasks.removeAll()
        await presencePublicationQueue.cancel()
        eventContinuation.finish()
    }

    func loadSnapshot() async throws -> BackendSnapshot {
        let session = try await client.auth.session
        async let profileRows: [DatabaseProfile] = client.from("profiles")
            .select()
            .eq("id", value: session.user.id.uuidString)
            .execute().value
        async let roomRows: [DatabaseRoom] = client.from("rooms")
            .select()
            .order("created_at", ascending: true)
            .execute().value
        async let membershipRows: [DatabaseMembership] = client.from("room_members")
            .select()
            .order("joined_at", ascending: true)
            .execute().value
        async let visibleProfiles: [DatabaseProfile] = client.from("profiles")
            .select()
            .execute().value
        async let entitlementKeys = loadActiveEntitlementKeysIfAvailable()

        let (profiles, rooms, memberships, peers, remoteEntitlementKeys) = try await (
            profileRows, roomRows, membershipRows, visibleProfiles, entitlementKeys
        )
        let profile = profiles.first
        let profileByID = Dictionary(uniqueKeysWithValues: peers.map { ($0.id, $0) })
        let membershipsByRoom = Dictionary(grouping: memberships, by: \.roomID)
        let mappedRooms = rooms.map { room in
            let members = (membershipsByRoom[room.id] ?? []).map { membership in
                let peer = profileByID[membership.userID]
                return RoomMember(
                    userID: membership.userID,
                    nickname: peer?.nickname ?? "친구",
                    characterID: PixelCharacterCatalog.canonicalID(for: peer?.characterID ?? "pixel_hamster"),
                    presence: .offline
                )
            }
            return Room(
                id: room.id,
                name: room.name,
                ownerID: room.ownerID,
                members: members,
                inviteCodeHint: room.inviteCodeHint,
                inviteVersion: 0,
                inviteCodeReady: room.inviteCodeReady,
                realtimeEpoch: room.realtimeEpoch
            )
        }
        return BackendSnapshot(
            profile: profile?.domain,
            rooms: mappedRooms,
            activeEntitlementKeys: CommerceEntitlementSnapshotPolicy.resolvedKeys(
                remoteKeys: remoteEntitlementKeys,
                profileCharacterID: profile?.characterID
            )
        )
    }

    /// Commerce is an optional feature boundary. A missing or temporarily
    /// unavailable commerce schema must not turn the core messenger snapshot
    /// into a connection failure.
    private func loadActiveEntitlementKeysIfAvailable() async -> Set<String>? {
        do {
            let rows: [DatabaseCommerceEntitlement] = try await client
                .from("commerce_entitlements")
                .select("entitlement_key,status")
                .eq("status", value: "active")
                .execute().value
            return Set(rows.map(\.entitlementKey))
        } catch {
            return nil
        }
    }

    func commerceState(
        productID: String = CommerceCatalog.starlightUpalupaProductID
    ) async throws -> CommerceState {
        let rows: [DatabaseCommerceState] = try await client.rpc(
            "get_commerce_state",
            params: CommerceStateParameters(productID: productID)
        ).execute().value
        guard let state = rows.first,
              let registeredProduct = CommerceCatalog.product(id: productID),
              state.productID == productID,
              state.characterID == registeredProduct.characterID,
              state.entitlementKey == registeredProduct.entitlementKey,
              PixelCharacterCatalog.definition(for: state.characterID).id == state.characterID
        else { throw SideyBackendError.malformedResponse }
        return state.domain
    }

    func googleIdentityLinkURL() async throws -> URL {
        let response = try await client.auth.getLinkIdentityURL(
            provider: .google,
            redirectTo: authCallbackURL
        )
        return response.url
    }

    func handleAuthCallback(_ url: URL) async throws {
        guard SideyAuthCallback.matches(url, scheme: authCallbackURL.scheme) else {
            throw SideyBackendError.remote("지원하지 않는 인증 응답입니다.")
        }
        let previousUserID = client.auth.currentUser?.id
        let session = try await client.auth.session(from: url)
        guard previousUserID == nil || session.user.id == previousUserID else {
            throw SideyBackendError.remote("Google 연결 중 SIDEY 계정이 바뀌었습니다.")
        }
    }

    func createCommerceOrder(
        productID: String = CommerceCatalog.starlightUpalupaProductID
    ) async throws -> CommerceCheckout {
        let response: CommerceOrderResponse = try await client.functions.invoke(
            "commerce-order",
            options: FunctionInvokeOptions(body: CommerceOrderRequest(productID: productID))
        )
        return CommerceCheckout(orderID: response.orderID, checkoutURL: response.checkoutURL)
    }

    @discardableResult
    func upsertProfile(nickname: String, characterID: String = "pixel_hamster") async throws -> Profile {
        guard ProfileValidator.isValidNickname(nickname) else { throw SideyBackendError.invalidProfile }
        let normalized = ProfileValidator.normalizedNickname(nickname)
        let value: DatabaseProfile = try await client.rpc(
            "upsert_profile",
            params: UpsertProfileParameters(nickname: normalized, characterID: characterID)
        ).execute().value
        return value.domain
    }

    func createRoom(name: String) async throws -> CreatedRoom {
        guard RoomNameValidator.isValid(name) else { throw SideyBackendError.invalidRoomName }
        let normalized = RoomNameValidator.normalized(name)
        let rows: [CreateRoomRow] = try await client.rpc(
            "create_room",
            params: CreateRoomParameters(name: normalized)
        ).execute().value
        guard let row = rows.first else { throw SideyBackendError.malformedResponse }
        let storedInKeychain: Bool
        do {
            try keychain.writeString(row.inviteCode, account: inviteAccount(roomID: row.roomID))
            storedInKeychain = true
        } catch {
            storedInKeychain = false
        }
        return CreatedRoom(
            roomID: row.roomID,
            inviteCode: row.inviteCode,
            storedInKeychain: storedInKeychain
        )
    }

    func joinRoom(inviteCode: String) async throws -> JoinedRoom {
        let normalized = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { throw SideyBackendError.invalidInviteCode }
        let rows: [JoinRoomRow] = try await client.rpc(
            "join_room",
            params: JoinRoomParameters(inviteCode: normalized)
        ).execute().value
        guard let row = rows.first else { throw SideyBackendError.malformedResponse }
        if let code = row.errorCode, !code.isEmpty { throw SideyBackendError.business(code: code) }
        guard let roomID = row.roomID else { throw SideyBackendError.malformedResponse }
        // The database intentionally stores only a hash. Preserve the plaintext
        // code the user already supplied so this device can offer a copy action.
        let storedInKeychain: Bool
        do {
            try keychain.writeString(normalized, account: inviteAccount(roomID: roomID))
            storedInKeychain = true
        } catch {
            storedInKeychain = false
        }
        return JoinedRoom(roomID: roomID, storedInKeychain: storedInKeychain)
    }

    func rotateInviteCode(roomID: UUID) async throws -> CreatedRoom {
        let code: String = try await client.rpc(
            "rotate_invite_code",
            params: RotateInviteCodeParameters(roomID: roomID)
        ).execute().value
        let storedInKeychain: Bool
        do {
            try keychain.writeString(code, account: inviteAccount(roomID: roomID))
            storedInKeychain = true
        } catch {
            storedInKeychain = false
        }
        return CreatedRoom(roomID: roomID, inviteCode: code, storedInKeychain: storedInKeychain)
    }

    func leaveRoom(_ roomID: UUID) async throws {
        let _: UUID? = try await client.rpc(
            "leave_room",
            params: LeaveRoomParameters(roomID: roomID)
        ).execute().value
        try? keychain.delete(account: inviteAccount(roomID: roomID))
        if activeRoomID == roomID { activeRoomID = nil }
        await removeChannel(roomID)
    }

    func renameRoom(_ roomID: UUID, name: String) async throws {
        guard RoomNameValidator.isValid(name) else { throw SideyBackendError.invalidRoomName }
        do {
            _ = try await client.rpc(
                "rename_room",
                params: RenameRoomParameters(
                    roomID: roomID,
                    name: RoomNameValidator.normalized(name)
                )
            ).execute()
        } catch {
            throw SideyBackendError.normalized(error)
        }
    }

    func removeRoomMember(_ roomID: UUID, userID: UUID) async throws {
        do {
            _ = try await client.rpc(
                "remove_room_member",
                params: RemoveRoomMemberParameters(roomID: roomID, userID: userID)
            ).execute()
        } catch {
            throw SideyBackendError.normalized(error)
        }
    }

    func deleteRoom(_ roomID: UUID) async throws {
        do {
            _ = try await client.rpc(
                "delete_room",
                params: DeleteRoomParameters(roomID: roomID)
            ).execute()
        } catch {
            throw SideyBackendError.normalized(error)
        }
        try? keychain.delete(account: inviteAccount(roomID: roomID))
        if activeRoomID == roomID { activeRoomID = nil }
        await removeChannel(roomID)
    }

    func sendMessage(roomID: UUID, body: String, id: UUID = UUID()) async throws -> ChatMessage {
        let normalized = MessageValidator.normalized(body)
        guard MessageValidator.isValid(normalized) else { throw SideyBackendError.remote("메시지는 200자·3줄 이하로 입력해 주세요.") }
        let parameters = SendMessageParameters(id: id, roomID: roomID, body: normalized)
        do {
            let value: DatabaseMessage = try await client.rpc(
                "send_message",
                params: parameters
            ).execute().value
            return try value.domain
        } catch {
            // An HTTP failure can happen after Postgres committed. Resolve the
            // client UUID through RLS first, then retry exactly once with the
            // same UUID. Never mint a replacement ID for an ambiguous result.
            if let committed = try? await message(id: id, roomID: roomID),
               committed.body == normalized,
               committed.senderID == client.auth.currentUser?.id {
                return committed
            }
            do {
                let value: DatabaseMessage = try await client.rpc(
                    "send_message",
                    params: parameters
                ).execute().value
                return try value.domain
            } catch {
                if let committed = try? await message(id: id, roomID: roomID),
                   committed.body == normalized,
                   committed.senderID == client.auth.currentUser?.id {
                    return committed
                }
                throw SideyBackendError.normalized(error)
            }
        }
    }

    func message(id: UUID, roomID: UUID) async throws -> ChatMessage? {
        let rows: [DatabaseMessage] = try await client.from("messages")
            .select()
            .eq("id", value: id.uuidString)
            .eq("room_id", value: roomID.uuidString)
            .limit(1)
            .execute().value
        return try rows.first.map { try $0.domain }
    }

    func recentMessages(roomID: UUID, limit: Int = 50) async throws -> [ChatMessage] {
        let rows: [DatabaseMessage] = try await client.from("messages")
            .select()
            .eq("room_id", value: roomID.uuidString)
            .order("created_at", ascending: false)
            .limit(min(max(limit, 1), 50))
            .execute().value
        return try rows.reversed().map { try $0.domain }
    }

    func historyPage(
        roomID: UUID,
        before cursor: MessageHistoryCursor?,
        pageSize: Int
    ) async throws -> MessageHistoryPage {
        let boundedPageSize = min(max(pageSize, 1), 50)
        let cutoff = PostgresTimestampEncoder.encode(
            Date().addingTimeInterval(-MessageLedger.retentionInterval)
        )
        let query = client.from("messages")
            .select()
            .eq("room_id", value: roomID.uuidString)
            .gte("created_at", value: cutoff)

        if let cursor {
            _ = try PostgresTimestampDecoder.decode(cursor.rawCreatedAt)
            _ = query.or(
                "created_at.lt.\(cursor.rawCreatedAt),and(created_at.eq.\(cursor.rawCreatedAt),id.lt.\(cursor.id.uuidString))"
            )
        }

        let rows: [DatabaseMessage] = try await query
            .order("created_at", ascending: false)
            .order("id", ascending: false)
            .limit(boundedPageSize + 1)
            .execute().value
        return try MessageHistoryPageMapper.page(from: rows, pageSize: boundedPageSize)
    }

    func currentUserID() -> UUID? {
        client.auth.currentUser?.id
    }

    func storedInviteCode(roomID: UUID) throws -> String? {
        try keychain.readString(account: inviteAccount(roomID: roomID))
    }

#if DEBUG
    func interruptRealtimeConnectionForTesting() {
        client.realtimeV2.disconnect(reason: "SIDEY integration recovery test")
    }

    func deleteOwnAccountForTesting() async throws {
        _ = try await client.rpc("delete_own_account").execute()
    }
#endif

    private func restoreOrCreateSession(requireExistingSession: Bool) async throws -> Session {
        if client.auth.currentSession != nil {
            return try await client.auth.session
        }
        if let refreshToken = try keychain.readString(account: legacyRefreshAccount), !refreshToken.isEmpty {
            do {
                return try await client.auth.refreshSession(refreshToken: refreshToken)
            } catch {
                throw SideyBackendError.sessionRecoveryFailed
            }
        }
        if requireExistingSession {
            throw SideyBackendError.sessionRecoveryFailed
        }
        return try await client.auth.signInAnonymously()
    }

    private func configureChannels(rooms: [Room], activeRoomID: UUID?) async throws {
        let requestedRooms = Array(rooms.prefix(5))
        let requestedByID = Dictionary(uniqueKeysWithValues: requestedRooms.map { ($0.id, $0) })
        let desiredRoomIDs = Set(requestedByID.keys)
        let requestedTopology = RealtimeTopology(rooms: requestedRooms)
        let currentTopology = RealtimeTopology(channelEpochs: Dictionary(
            uniqueKeysWithValues: channels.map { ($0.key, $0.value.epoch) }
        ))
        let resolvedActiveRoomID = activeRoomID.flatMap {
            desiredRoomIDs.contains($0) ? $0 : nil
        }
        let topologyChanged = requestedTopology != currentTopology
        let activeRoomChanged = self.activeRoomID != resolvedActiveRoomID

        self.activeRoomID = resolvedActiveRoomID
        connectionTracker.replaceDesiredRoomIDs(desiredRoomIDs)
        if topologyChanged {
            recoveryReconciled = false
        }
        emitConnectionState()

        for roomID in Set(channels.keys).subtracting(desiredRoomIDs) {
            await removeChannel(roomID)
            try? keychain.delete(account: inviteAccount(roomID: roomID))
        }
        for room in requestedRooms {
            if let existing = channels[room.id], existing.epoch != room.realtimeEpoch {
                await removeChannel(room.id)
            }
            if channels[room.id] == nil {
                try await addChannel(roomID: room.id, epoch: room.realtimeEpoch)
            }
        }
        if topologyChanged || activeRoomChanged {
            try await publishPresence()
        }
        startRealtimeWatchdogIfNeeded()
    }

    private func addChannel(roomID: UUID, epoch: Int) async throws {
        guard let userID = client.auth.currentUser?.id else {
            throw SideyBackendError.remote("인증 세션이 없습니다.")
        }
        channelsBeingAdded.insert(roomID)
        defer { channelsBeingAdded.remove(roomID) }

        let topicPrefix = "room:\(roomID.uuidString.lowercased()):\(epoch)"
        let databaseChannel = client.channel("\(topicPrefix):db") { config in
            config.isPrivate = true
            config.broadcast.receiveOwnBroadcasts = false
        }
        let ephemeralChannel = client.channel("\(topicPrefix):ephemeral") { config in
            config.isPrivate = true
            config.broadcast.receiveOwnBroadcasts = false
            config.presence = PresenceJoinConfig(key: userID.uuidString.lowercased())
        }

        let messageChanges = databaseChannel.broadcastStream(event: "message_changed")
        let structureChanges = databaseChannel.broadcastStream(event: "structure_changed")
        let messagesPruned = databaseChannel.broadcastStream(event: "messages_pruned")
        let databaseStatuses = databaseChannel.statusChange
        let typingStart = ephemeralChannel.broadcastStream(event: "typing_start")
        let typingStop = ephemeralChannel.broadcastStream(event: "typing_stop")
        let characterPulse = ephemeralChannel.broadcastStream(event: "character_pulse")
        let characterThrow = ephemeralChannel.broadcastStream(event: "character_throw")
        let presenceChanges = ephemeralChannel.presenceChange()
        let ephemeralStatuses = ephemeralChannel.statusChange

        let tasks = [
            Task { [weak self] in
                for await payload in messageChanges {
                    await self?.handleDatabaseBroadcast(
                        roomID: roomID,
                        payload: payload,
                        event: "message_changed"
                    )
                }
            },
            Task { [weak self] in
                for await payload in structureChanges {
                    await self?.handleDatabaseBroadcast(
                        roomID: roomID,
                        payload: payload,
                        event: "structure_changed"
                    )
                }
            },
            Task { [weak self] in
                for await payload in messagesPruned {
                    await self?.handleDatabaseBroadcast(
                        roomID: roomID,
                        payload: payload,
                        event: "messages_pruned"
                    )
                }
            },
            Task { [weak self] in
                for await payload in typingStart {
                    await self?.handleTyping(roomID: roomID, payload: payload, active: true)
                }
            },
            Task { [weak self] in
                for await payload in typingStop {
                    await self?.handleTyping(roomID: roomID, payload: payload, active: false)
                }
            },
            Task { [weak self] in
                for await payload in characterPulse {
                    await self?.handleCharacterPulse(roomID: roomID, payload: payload)
                }
            },
            Task { [weak self] in
                for await payload in characterThrow {
                    await self?.handleCharacterThrow(roomID: roomID, payload: payload)
                }
            },
            Task { [weak self] in
                for await action in presenceChanges {
                    await self?.handlePresence(roomID: roomID, action: action)
                }
            },
            Task { [weak self] in
                for await status in databaseStatuses {
                    await self?.handleChannelStatus(roomID: roomID, kind: .database, status: status)
                }
            },
            Task { [weak self] in
                for await status in ephemeralStatuses {
                    await self?.handleChannelStatus(roomID: roomID, kind: .ephemeral, status: status)
                }
            }
        ]
        channels[roomID] = RoomRealtimeChannels(
            epoch: epoch,
            database: databaseChannel,
            ephemeral: ephemeralChannel,
            tasks: tasks
        )

        do {
            try await databaseChannel.subscribeWithError()
            try Task.checkCancellation()
            try await ephemeralChannel.subscribeWithError()
            try Task.checkCancellation()
            updateRoomSubscription(roomID: roomID)
        } catch {
            await removeChannel(roomID, resetRecovery: false)
            throw error
        }
    }

    private func removeChannel(_ roomID: UUID, resetRecovery: Bool = true) async {
        if resetRecovery {
            channelRecoveryTasks.removeValue(forKey: roomID)?.cancel()
            channelRecoveryAttempts.removeValue(forKey: roomID)
        }
        connectionTracker.setSubscribed(false, roomID: roomID)
        guard let roomChannels = channels.removeValue(forKey: roomID) else { return }
        roomChannels.tasks.forEach { $0.cancel() }
        await client.removeChannel(roomChannels.database)
        await client.removeChannel(roomChannels.ephemeral)
    }

    private func handleChannelStatus(
        roomID: UUID,
        kind: RealtimeChannelKind,
        status: RealtimeChannelStatus
    ) async {
        switch status {
        case .subscribed:
            channelRecoveryTasks.removeValue(forKey: roomID)?.cancel()
            channelRecoveryAttempts.removeValue(forKey: roomID)
            updateRoomSubscription(roomID: roomID)
            if kind == .ephemeral,
               channels[roomID]?.ephemeral.status == .subscribed {
                try? await publishPresence()
            }
            emitConnectionState()
        case .unsubscribed:
            connectionTracker.setSubscribed(false, roomID: roomID)
            recoveryReconciled = false
            emitConnectionState()
            if !channelsBeingAdded.contains(roomID) {
                scheduleChannelRecovery(roomID: roomID)
            }
        case .subscribing, .unsubscribing:
            connectionTracker.setSubscribed(false, roomID: roomID)
            recoveryReconciled = false
            emitConnectionState()
        }
    }

    private func updateRoomSubscription(roomID: UUID) {
        guard let roomChannels = channels[roomID] else {
            connectionTracker.setSubscribed(false, roomID: roomID)
            return
        }
        connectionTracker.setSubscribed(
            roomChannels.database.status == .subscribed
                && roomChannels.ephemeral.status == .subscribed,
            roomID: roomID
        )
    }

    private func publishPresence() async throws {
        try await presencePublicationQueue.submit(PresencePublicationIntent(
            activeRoomID: activeRoomID,
            localPresence: localPresence
        ))
    }

    private func performPresencePublication(_ intent: PresencePublicationIntent) async throws {
        guard !connectionTracker.desiredRoomIDs.isEmpty else { return }
        guard let userID = client.auth.currentUser?.id else {
            throw SideyBackendError.realtimeUnavailable
        }
        guard client.realtimeV2.status == .connected else {
            throw SideyBackendError.realtimeUnavailable
        }

        // A publication is a complete desired-room batch. Missing or
        // unsubscribed channels are errors instead of silently producing a
        // partial Presence state that can make two rooms look active.
        for roomID in connectionTracker.desiredRoomIDs.sorted(by: {
            $0.uuidString < $1.uuidString
        }) {
            guard let roomChannels = channels[roomID],
                  roomChannels.ephemeral.status == .subscribed
            else {
                throw SideyBackendError.realtimeUnavailable
            }
            let state = PresencePublicationPlan.state(
                for: roomID,
                activeRoomID: intent.activeRoomID,
                localPresence: intent.localPresence
            )
            try await roomChannels.ephemeral.track(PresencePayload(
                userID: userID,
                state: state,
                onlineAt: ISO8601DateFormatter().string(from: .now)
            ))
        }
    }

    private func subscribedChannels(roomID: UUID) -> RoomRealtimeChannels? {
        guard client.realtimeV2.status == .connected,
              let roomChannels = channels[roomID],
              roomChannels.database.status == .subscribed,
              roomChannels.ephemeral.status == .subscribed
        else {
            scheduleChannelRecovery(roomID: roomID)
            return nil
        }
        return roomChannels
    }

    private func startRealtimeWatchdogIfNeeded() {
        guard realtimeWatchdogTask == nil else { return }
        realtimeWatchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(RealtimeRecoveryPolicy.watchdogInterval))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self?.inspectRealtimeHealth()
            }
        }
    }

    private func inspectRealtimeHealth() {
        guard !isShuttingDown else { return }
        let socketConnected = client.realtimeV2.status == .connected
        for roomID in connectionTracker.desiredRoomIDs {
            let subscribed = socketConnected
                && channels[roomID]?.database.status == .subscribed
                && channels[roomID]?.ephemeral.status == .subscribed
            connectionTracker.setSubscribed(subscribed, roomID: roomID)
            if !subscribed, !channelsBeingAdded.contains(roomID) {
                recoveryReconciled = false
                scheduleChannelRecovery(roomID: roomID)
            }
        }
        emitConnectionState()
    }

    private func scheduleChannelRecovery(roomID: UUID) {
        guard !isShuttingDown,
              connectionTracker.desiredRoomIDs.contains(roomID),
              channelRecoveryTasks[roomID] == nil
        else { return }

        let attempt = channelRecoveryAttempts[roomID, default: 0] + 1
        channelRecoveryAttempts[roomID] = attempt
        let delay = RealtimeRecoveryPolicy.delay(forAttempt: attempt)
        channelRecoveryTasks[roomID] = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.recoverChannel(roomID: roomID)
        }
    }

    private func recoverChannel(roomID: UUID) async {
        channelRecoveryTasks.removeValue(forKey: roomID)
        guard !isShuttingDown,
              connectionTracker.desiredRoomIDs.contains(roomID),
              !channelsBeingAdded.contains(roomID)
        else { return }

        let epoch = channels[roomID]?.epoch
        if channels[roomID] != nil { await removeChannel(roomID, resetRecovery: false) }

        guard !isShuttingDown,
              connectionTracker.desiredRoomIDs.contains(roomID)
        else { return }

        do {
            guard let epoch else { return }
            try await addChannel(roomID: roomID, epoch: epoch)
            guard !isShuttingDown,
                  connectionTracker.desiredRoomIDs.contains(roomID)
            else {
                await removeChannel(roomID)
                return
            }
            try await publishPresence()
            emitConnectionState()
            scheduleRecoveryReconciliation()
        } catch {
            connectionTracker.setSubscribed(false, roomID: roomID)
            emitConnectionState()
            scheduleRecoveryReconciliation()
            scheduleChannelRecovery(roomID: roomID)
        }
    }

    private func scheduleRecoveryReconciliation() {
        guard !isShuttingDown else { return }
        recoveryReconciled = false
        emitConnectionState()
        recoveryReconciliationGeneration += 1
        recoveryReconciliationAttempt = 1
        let generation = recoveryReconciliationGeneration
        recoveryReconciliationTask?.cancel()
        recoveryReconciliationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(RealtimeRecoveryPolicy.delay(forAttempt: 1)))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.reconcileAfterRealtimeRecovery(generation: generation)
        }
    }

    private func reconcileAfterRealtimeRecovery(generation: Int) async {
        recoveryReconciliationTask = nil
        guard !isShuttingDown, generation == recoveryReconciliationGeneration else { return }
        do {
            _ = try await reconcileCurrentState(emitEvents: true)
            recoveryReconciliationAttempt = 0
        } catch {
            recoveryReconciliationAttempt += 1
            let attempt = recoveryReconciliationAttempt
            emit(.technicalError("실시간 상태 재동기화 실패: \(error.localizedDescription)"))
            recoveryReconciliationTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(
                        RealtimeRecoveryPolicy.delay(forAttempt: attempt)
                    ))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self?.reconcileAfterRealtimeRecovery(generation: generation)
            }
        }
    }

    private func reconcileCurrentState(emitEvents: Bool) async throws -> BackendReconciliation {
        var snapshot = try await loadSnapshot()
        let snapshotEpochs = Dictionary(uniqueKeysWithValues: snapshot.rooms.prefix(5).map {
            ($0.id, $0.realtimeEpoch)
        })
        let channelEpochs = Dictionary(uniqueKeysWithValues: channels.map { ($0.key, $0.value.epoch) })
        if snapshotEpochs != channelEpochs {
            try await configureChannels(rooms: snapshot.rooms, activeRoomID: activeRoomID)
            snapshot = try await loadSnapshot()
        }

        let reconciledActiveRoomID = activeRoomID.flatMap { requestedID in
            snapshot.rooms.contains(where: { $0.id == requestedID }) ? requestedID : snapshot.rooms.first?.id
        } ?? snapshot.rooms.first?.id
        let messages: [ChatMessage]
        if let reconciledActiveRoomID {
            messages = try await recentMessages(roomID: reconciledActiveRoomID)
        } else {
            messages = []
        }
        let reconciliation = BackendReconciliation(
            snapshot: snapshot,
            activeRoomID: reconciledActiveRoomID,
            activeMessages: messages
        )
        if emitEvents {
            emit(.reconciliation(reconciliation))
        }
        recoveryReconciled = true
        emitConnectionState()
        return reconciliation
    }

    private func emitConnectionState() {
        let status = BackendConnectionStatus(
            transportConnected: connectionTracker.isConnected,
            recoveryReconciled: recoveryReconciled,
            activeRoomTransportConnected: activeRoomID.map {
                connectionTracker.isSubscribed(roomID: $0)
            } ?? connectionTracker.isConnected
        )
        guard lastEmittedConnectionStatus != status else { return }
        lastEmittedConnectionStatus = status
        emit(.connection(status))
    }

    private func handleDatabaseBroadcast(roomID: UUID, payload: JSONObject, event: String) async {
        let inner = payload["payload"]?.objectValue ?? payload
        guard let change = try? inner.decode(as: DatabaseChangePayload.self),
              change.roomID == roomID
        else { return }

        switch event {
        case "message_changed":
            guard let operation = change.operation,
                  ["INSERT", "UPDATE", "DELETE"].contains(operation),
                  let messageID = change.messageID
            else { return }
            if operation == "DELETE" {
                emit(.messageDeleted(roomID: roomID, messageID: messageID))
                return
            }
            do {
                guard let verified = try await message(id: messageID, roomID: roomID) else {
                    throw SideyBackendError.malformedResponse
                }
                emit(.message(verified))
            } catch {
                emit(.technicalError(
                    "메시지 수신 실패: \(error.localizedDescription)"
                ))
            }
        case "structure_changed":
            guard let entity = change.entity,
                  ["profiles", "rooms", "room_members"].contains(entity),
                  let operation = change.operation,
                  ["INSERT", "UPDATE", "DELETE"].contains(operation)
            else { return }
            scheduleStructuralSnapshot()
        case "messages_pruned":
            emit(.messagesInvalidated(roomID: roomID))
        default:
            return
        }
    }

    private func scheduleStructuralSnapshot() {
        guard structuralSnapshotTask == nil, !isShuttingDown else { return }
        let attempt = structuralSnapshotAttempt
        let delay: Duration = attempt == 0
            ? .milliseconds(150)
            : .seconds(RealtimeRecoveryPolicy.delay(forAttempt: attempt))
        structuralSnapshotTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.emitStructuralSnapshot()
        }
    }

    private func emitStructuralSnapshot() async {
        structuralSnapshotTask = nil
        guard !isShuttingDown else { return }
        do {
            let snapshot = try await loadSnapshot()
            let snapshotTopology = RealtimeTopology(rooms: snapshot.rooms)
            let channelTopology = RealtimeTopology(channelEpochs: Dictionary(
                uniqueKeysWithValues: channels.map { ($0.key, $0.value.epoch) }
            ))
            structuralSnapshotAttempt = 0
            if snapshotTopology == channelTopology {
                emit(.snapshot(snapshot))
            } else {
                try await configureChannels(
                    rooms: snapshot.rooms,
                    activeRoomID: activeRoomID
                )
                _ = try await reconcileCurrentState(emitEvents: true)
            }
        } catch {
            emit(.technicalError("그룹 상태 재동기화 실패: \(error.localizedDescription)"))
            structuralSnapshotAttempt += 1
            scheduleStructuralSnapshot()
            if !recoveryReconciled {
                scheduleRecoveryReconciliation()
            }
        }
    }

    private func handlePresence(roomID: UUID, action: any PresenceAction) {
        var joined: [UUID: PresenceState] = [:]
        for (userIDString, presence) in action.joins {
            guard let userID = UUID(uuidString: userIDString),
                  let payload = try? presence.decodeState(as: PresencePayload.self)
            else { continue }
            joined[userID] = payload.state
        }
        let left = Set(action.leaves.keys.compactMap(UUID.init(uuidString:)))
        for update in PresenceChangePlan.updates(joined: joined, left: left) {
            emit(.presence(
                roomID: roomID,
                userID: update.userID,
                state: update.state
            ))
        }
    }

    private func handleTyping(roomID: UUID, payload: JSONObject, active: Bool) {
        let inner = payload["payload"]?.objectValue ?? payload
        guard let typing = try? inner.decode(as: TypingPayload.self),
              typing.roomID == roomID,
              typing.userID != client.auth.currentUser?.id
        else { return }
        let key = "\(roomID.uuidString)|\(typing.userID.uuidString)"
        typingExpiryTasks.removeValue(forKey: key)?.cancel()
        guard !active || typingExpiryTasks.count < 60 else {
            scheduleStructuralSnapshot()
            return
        }
        emit(.typing(roomID: roomID, userID: typing.userID, active: active))
        guard active else { return }
        typingExpiryTasks[key] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await self?.expireTyping(roomID: roomID, userID: typing.userID, key: key)
        }
    }

    private func handleCharacterPulse(roomID: UUID, payload: JSONObject) {
        let inner = payload["payload"]?.objectValue ?? payload
        guard let pulse = try? inner.decode(as: CharacterPulsePayload.self),
              pulse.roomID == roomID,
              pulse.userID != client.auth.currentUser?.id
        else { return }
        emit(.characterPulse(CharacterPulseEvent(
            id: pulse.eventID,
            roomID: roomID,
            userID: pulse.userID
        )))
    }

    private func handleCharacterThrow(roomID: UUID, payload: JSONObject) {
        let inner = payload["payload"]?.objectValue ?? payload
        guard let value = try? inner.decode(as: CharacterThrowPayload.self),
              value.schemaVersion == 1,
              value.roomID == roomID,
              value.actorUserID != value.targetUserID,
              value.actorUserID != client.auth.currentUser?.id
        else { return }
        emit(.characterThrow(CharacterThrowEvent(
            id: value.eventID,
            roomID: roomID,
            actorUserID: value.actorUserID,
            targetUserID: value.targetUserID,
            sourceCharacterID: value.sourceCharacterID
        )))
    }

    private func expireTyping(roomID: UUID, userID: UUID, key: String) {
        typingExpiryTasks.removeValue(forKey: key)
        emit(.typing(roomID: roomID, userID: userID, active: false))
    }

    private func emit(_ event: BackendEvent) {
        switch eventContinuation.yield(event) {
        case .enqueued:
            break
        case .dropped:
            scheduleStructuralSnapshot()
        case .terminated:
            isShuttingDown = true
        @unknown default:
            scheduleStructuralSnapshot()
        }
    }

    private func inviteAccount(roomID: UUID) -> String {
        inviteAccountPrefix + roomID.uuidString.lowercased()
    }
}

private enum RealtimeChannelKind: Sendable {
    case database
    case ephemeral
}

private struct RoomRealtimeChannels: Sendable {
    let epoch: Int
    let database: RealtimeChannelV2
    let ephemeral: RealtimeChannelV2
    let tasks: [Task<Void, Never>]
}
