import Foundation
import Supabase

actor SideyBackend {
    nonisolated let events: AsyncStream<BackendEvent>

    private let client: SupabaseClient
    private let keychain: KeychainStore
    private let legacyRefreshAccount: String
    private let inviteAccountPrefix: String
    private let eventContinuation: AsyncStream<BackendEvent>.Continuation
    private var channels: [UUID: RealtimeChannelV2] = [:]
    private var channelTasks: [UUID: [Task<Void, Never>]] = [:]
    private var channelRecoveryTasks: [UUID: Task<Void, Never>] = [:]
    private var channelRecoveryAttempts: [UUID: Int] = [:]
    private var channelsBeingAdded: Set<UUID> = []
    private var realtimeWatchdogTask: Task<Void, Never>?
    private var recoveryReconciliationTask: Task<Void, Never>?
    private var typingExpiryTasks: [String: Task<Void, Never>] = [:]
    private var activeRoomID: UUID?
    private var localPresence: PresenceState = .online
    private var connectionTracker = RealtimeConnectionTracker()
    private var lastEmittedConnectionState: Bool?
    private var isShuttingDown = false

    init(configuration: RuntimeConfiguration, keychain: KeychainStore = KeychainStore()) {
        let eventPair = AsyncStream<BackendEvent>.makeStream()
        self.events = eventPair.stream
        self.eventContinuation = eventPair.continuation
        let fingerprint = configuration.backendFingerprint
        let legacyRefreshAccount = "supabase-refresh:\(fingerprint):default"
        self.keychain = keychain
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

    func syncRealtime(roomIDs: [UUID], activeRoomID: UUID?) async throws {
        guard !isShuttingDown else { return }
        let plan = RealtimeRoomPlan.make(
            existing: Set(channels.keys),
            requested: roomIDs,
            activeRoomID: activeRoomID
        )
        self.activeRoomID = plan.activeRoomID
        connectionTracker.replaceDesiredRoomIDs(plan.desired)

        for roomID in plan.removals {
            await removeChannel(roomID)
        }
        for roomID in plan.additions {
            try await addChannel(roomID)
        }
        try await publishPresence()
        emitConnectionState()
        startRealtimeWatchdogIfNeeded()
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
        guard roomID == activeRoomID,
              ["typing_start", "typing_keepalive", "typing_stop"].contains(event),
              let channel = subscribedChannel(roomID: roomID),
              let userID = client.auth.currentUser?.id
        else { return }
        try await channel.broadcast(event: event, message: TypingPayload(userID: userID))
    }

    func broadcastCharacterPulse(roomID: UUID, eventID: UUID) async throws {
        guard roomID == activeRoomID,
              let channel = subscribedChannel(roomID: roomID),
              let userID = client.auth.currentUser?.id
        else { return }
        try await channel.broadcast(
            event: "character_pulse",
            message: CharacterPulsePayload(userID: userID, eventID: eventID)
        )
    }

    func shutdown() async {
        isShuttingDown = true
        connectionTracker.replaceDesiredRoomIDs([])
        realtimeWatchdogTask?.cancel()
        realtimeWatchdogTask = nil
        recoveryReconciliationTask?.cancel()
        recoveryReconciliationTask = nil
        for task in channelRecoveryTasks.values { task.cancel() }
        channelRecoveryTasks.removeAll()
        channelRecoveryAttempts.removeAll()
        for roomID in Array(channels.keys) { await removeChannel(roomID) }
        for task in typingExpiryTasks.values { task.cancel() }
        typingExpiryTasks.removeAll()
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

        let (profiles, rooms, memberships, peers) = try await (
            profileRows, roomRows, membershipRows, visibleProfiles
        )
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
                inviteVersion: room.inviteVersion
            )
        }
        return BackendSnapshot(profile: profiles.first?.domain, rooms: mappedRooms)
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
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 20,
              normalized.rangeOfCharacter(from: .newlines) == nil
        else { throw SideyBackendError.invalidRoomName }
        let rows: [CreateRoomRow] = try await client.rpc(
            "create_room",
            params: CreateRoomParameters(name: normalized)
        ).execute().value
        guard let row = rows.first else { throw SideyBackendError.malformedResponse }
        try keychain.writeString(row.inviteCode, account: inviteAccount(roomID: row.roomID))
        return CreatedRoom(roomID: row.roomID, inviteCode: row.inviteCode)
    }

    func joinRoom(inviteCode: String) async throws -> UUID {
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
        try? keychain.writeString(normalized, account: inviteAccount(roomID: roomID))
        return roomID
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

    func sendMessage(roomID: UUID, body: String, id: UUID = UUID()) async throws -> ChatMessage {
        let normalized = MessageValidator.normalized(body)
        guard MessageValidator.isValid(normalized) else { throw SideyBackendError.remote("메시지는 200자·3줄 이하여야 함") }
        let value: DatabaseMessage = try await client.rpc(
            "send_message",
            params: SendMessageParameters(id: id, roomID: roomID, body: normalized)
        ).execute().value
        return value.domain
    }

    func recentMessages(roomID: UUID, limit: Int = 50) async throws -> [ChatMessage] {
        let rows: [DatabaseMessage] = try await client.from("messages")
            .select()
            .eq("room_id", value: roomID.uuidString)
            .order("created_at", ascending: false)
            .limit(min(max(limit, 1), 50))
            .execute().value
        return rows.reversed().map(\.domain)
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

    private func addChannel(_ roomID: UUID) async throws {
        guard let userID = client.auth.currentUser?.id else { throw SideyBackendError.remote("인증 세션이 없음") }
        channelsBeingAdded.insert(roomID)
        defer { channelsBeingAdded.remove(roomID) }
        let channel = client.channel("room:\(roomID.uuidString.lowercased())") { config in
            config.isPrivate = true
            config.broadcast.receiveOwnBroadcasts = false
            config.presence = PresenceJoinConfig(key: userID.uuidString.lowercased())
        }
        let inserted = channel.broadcastStream(event: "INSERT")
        let updated = channel.broadcastStream(event: "UPDATE")
        let deleted = channel.broadcastStream(event: "DELETE")
        let typingStart = channel.broadcastStream(event: "typing_start")
        let typingKeepalive = channel.broadcastStream(event: "typing_keepalive")
        let typingStop = channel.broadcastStream(event: "typing_stop")
        let characterPulse = channel.broadcastStream(event: "character_pulse")
        let presenceChanges = channel.presenceChange()
        let statusChanges = channel.statusChange

        // Start consuming status changes before subscribing. Starting this task
        // afterwards can replay an older `.subscribing` event after
        // `subscribeWithError()` has already succeeded, leaving the app stuck in
        // the gray reconnecting state until another status event arrives.
        channels[roomID] = channel
        channelTasks[roomID] = [
            Task { [weak self] in
                for await payload in inserted { await self?.handleDatabaseBroadcast(roomID: roomID, payload: payload, event: "INSERT") }
            },
            Task { [weak self] in
                for await payload in updated { await self?.handleDatabaseBroadcast(roomID: roomID, payload: payload, event: "UPDATE") }
            },
            Task { [weak self] in
                for await payload in deleted { await self?.handleDatabaseBroadcast(roomID: roomID, payload: payload, event: "DELETE") }
            },
            Task { [weak self] in
                for await payload in typingStart { await self?.handleTyping(roomID: roomID, payload: payload, active: true) }
            },
            Task { [weak self] in
                for await payload in typingKeepalive { await self?.handleTyping(roomID: roomID, payload: payload, active: true) }
            },
            Task { [weak self] in
                for await payload in typingStop { await self?.handleTyping(roomID: roomID, payload: payload, active: false) }
            },
            Task { [weak self] in
                for await payload in characterPulse { await self?.handleCharacterPulse(roomID: roomID, payload: payload) }
            },
            Task { [weak self] in
                for await action in presenceChanges { await self?.handlePresence(roomID: roomID, action: action) }
            },
            Task { [weak self] in
                for await status in statusChanges {
                    await self?.handleChannelStatus(roomID: roomID, status: status)
                }
            }
        ]
        do {
            try await channel.subscribeWithError()
            try Task.checkCancellation()
            connectionTracker.setSubscribed(channel.status == .subscribed, roomID: roomID)
        } catch {
            channelTasks.removeValue(forKey: roomID)?.forEach { $0.cancel() }
            channels.removeValue(forKey: roomID)
            connectionTracker.setSubscribed(false, roomID: roomID)
            await client.removeChannel(channel)
            throw error
        }
    }

    private func removeChannel(_ roomID: UUID) async {
        channelRecoveryTasks.removeValue(forKey: roomID)?.cancel()
        channelRecoveryAttempts.removeValue(forKey: roomID)
        channelTasks.removeValue(forKey: roomID)?.forEach { $0.cancel() }
        connectionTracker.setSubscribed(false, roomID: roomID)
        guard let channel = channels.removeValue(forKey: roomID) else { return }
        await client.removeChannel(channel)
    }

    private func handleChannelStatus(roomID: UUID, status: RealtimeChannelStatus) async {
        switch status {
        case .subscribed:
            channelRecoveryTasks.removeValue(forKey: roomID)?.cancel()
            channelRecoveryAttempts.removeValue(forKey: roomID)
            connectionTracker.setSubscribed(true, roomID: roomID)
            if channels[roomID]?.status == .subscribed {
                try? await publishPresence()
            }
            emitConnectionState()
        case .unsubscribed:
            connectionTracker.setSubscribed(false, roomID: roomID)
            emitConnectionState()
            if !channelsBeingAdded.contains(roomID) {
                scheduleChannelRecovery(roomID: roomID)
            }
        case .subscribing, .unsubscribing:
            connectionTracker.setSubscribed(false, roomID: roomID)
            emitConnectionState()
        }
    }

    private func publishPresence() async throws {
        guard let userID = client.auth.currentUser?.id else { return }
        for (roomID, channel) in channels {
            guard client.realtimeV2.status == .connected,
                  channel.status == .subscribed
            else { continue }
            let state = PresencePublicationPlan.state(
                for: roomID,
                activeRoomID: activeRoomID,
                localPresence: localPresence
            )
            try await channel.track(PresencePayload(
                userID: userID,
                state: state,
                onlineAt: ISO8601DateFormatter().string(from: .now)
            ))
        }
    }

    private func subscribedChannel(roomID: UUID) -> RealtimeChannelV2? {
        guard client.realtimeV2.status == .connected,
              let channel = channels[roomID],
              channel.status == .subscribed
        else {
            scheduleChannelRecovery(roomID: roomID)
            return nil
        }
        return channel
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
            let subscribed = socketConnected && channels[roomID]?.status == .subscribed
            connectionTracker.setSubscribed(subscribed, roomID: roomID)
            if !subscribed, !channelsBeingAdded.contains(roomID) {
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

        if let channel = channels[roomID] {
            channelTasks.removeValue(forKey: roomID)?.forEach { $0.cancel() }
            channels.removeValue(forKey: roomID)
            connectionTracker.setSubscribed(false, roomID: roomID)
            await client.removeChannel(channel)
        }

        guard !isShuttingDown,
              connectionTracker.desiredRoomIDs.contains(roomID)
        else { return }

        do {
            try await addChannel(roomID)
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
            scheduleChannelRecovery(roomID: roomID)
        }
    }

    private func scheduleRecoveryReconciliation() {
        guard !isShuttingDown, recoveryReconciliationTask == nil else { return }
        recoveryReconciliationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.reconcileAfterRealtimeRecovery()
        }
    }

    private func reconcileAfterRealtimeRecovery() async {
        recoveryReconciliationTask = nil
        guard !isShuttingDown,
              let snapshot = try? await loadSnapshot()
        else { return }
        eventContinuation.yield(.snapshot(snapshot))
    }

    private func emitConnectionState() {
        let connected = connectionTracker.isConnected
        guard lastEmittedConnectionState != connected else { return }
        lastEmittedConnectionState = connected
        eventContinuation.yield(.connection(connected))
    }

    private func handleDatabaseBroadcast(roomID: UUID, payload: JSONObject, event: String) async {
        let change = payload["payload"]?.objectValue ?? payload
        let table = change["table"]?.stringValue ?? ""
        if event == "INSERT", table == "messages",
           let record = change["record"]?.objectValue,
           let message = try? record.decode(as: DatabaseMessage.self) {
            eventContinuation.yield(.message(message.domain))
        } else if ["profiles", "rooms", "room_members"].contains(table),
                  let snapshot = try? await loadSnapshot() {
            eventContinuation.yield(.snapshot(snapshot))
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
            eventContinuation.yield(.presence(
                roomID: roomID,
                userID: update.userID,
                state: update.state
            ))
        }
    }

    private func handleTyping(roomID: UUID, payload: JSONObject, active: Bool) {
        let inner = payload["payload"]?.objectValue ?? payload
        guard let typing = try? inner.decode(as: TypingPayload.self),
              typing.userID != client.auth.currentUser?.id
        else { return }
        let key = "\(roomID.uuidString)|\(typing.userID.uuidString)"
        typingExpiryTasks.removeValue(forKey: key)?.cancel()
        eventContinuation.yield(.typing(roomID: roomID, userID: typing.userID, active: active))
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
              pulse.userID != client.auth.currentUser?.id
        else { return }
        eventContinuation.yield(.characterPulse(CharacterPulseEvent(
            id: pulse.eventID,
            roomID: roomID,
            userID: pulse.userID
        )))
    }

    private func expireTyping(roomID: UUID, userID: UUID, key: String) {
        typingExpiryTasks.removeValue(forKey: key)
        eventContinuation.yield(.typing(roomID: roomID, userID: userID, active: false))
    }

    private func inviteAccount(roomID: UUID) -> String {
        inviteAccountPrefix + roomID.uuidString.lowercased()
    }
}
