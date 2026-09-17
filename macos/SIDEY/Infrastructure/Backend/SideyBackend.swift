import Foundation

/// REST owns durable snapshots; the authenticated socket owns commands and live delivery.
actor SideyBackend {
    nonisolated let events: AsyncStream<BackendEvent>
    private let continuation: AsyncStream<BackendEvent>.Continuation
    private let configuration: RuntimeConfiguration
    private let keychain: KeychainStore
    private let session: SideySessionClient
    private let transport: SpringRealtimeTransport
    private let networkPathMonitor: any NetworkPathMonitoring
    private var reader: Task<Void, Never>?
    private var networkReader: Task<Void, Never>?
    private var membershipPoll: Task<Void, Never>?
    private let membershipPollInterval: Duration
    private var lifecycle = UUID()
    private var authorizedRooms: Set<UUID> = []
    private var latestSnapshot: BackendSnapshot?
    private var retry: Task<Void, Never>?
    private var recovery: Task<BackendReconciliation, Error>?
    private var recoveryID = UUID()
    private var stateRevision = 0
    private var connected = false
    private var stopping = false
    private var pathAvailable = true
    private var userID: UUID?
    private var activeRoomID: UUID?
    private var localPresence: PresenceState = .online
    private var subscribed: Set<UUID> = []
    private var ledgers: [UUID: SpringMessageLedger] = [:]
    private var typingExpiry: [String: Task<Void, Never>] = [:]

    init(configuration: RuntimeConfiguration, keychain: KeychainStore = KeychainStore(),
         authCallbackURL: URL = SideyAuthCallback.callbackURL(),
         networkPathMonitor: any NetworkPathMonitoring = SystemNetworkPathMonitor(),
         session: SideySessionClient? = nil, transport: SpringRealtimeTransport = SpringRealtimeTransport(),
         membershipPollInterval: Duration = .seconds(30)) {
        self.configuration = configuration
        self.keychain = keychain
        self.session = session ?? SideySessionClient(configuration: configuration, keychain: keychain)
        self.transport = transport
        self.networkPathMonitor = networkPathMonitor
        self.membershipPollInterval = membershipPollInterval
        let pair = AsyncStream<BackendEvent>.makeStream(bufferingPolicy: .bufferingNewest(256))
        events = pair.stream
        continuation = pair.continuation
    }

    func boot(requireExistingSession: Bool = true) async throws -> BackendSnapshot {
        lifecycle = UUID()
        stopping = false
        do { try await session.restore() }
        catch SideySessionError.authenticationRequired { throw SideyBackendError.sessionRecoveryFailed }
        catch SideySessionError.legacyClaimRequired { throw SideyBackendError.sessionRecoveryFailed }
        catch {
            if await session.userID() == nil { throw SideyBackendError.sessionRecoveryFailed }
            throw error
        }
        userID = await session.userID()
        return try await loadSnapshot()
    }

    func authenticationNonce() async throws -> String { try await session.challenge() }
    func signInWithApple(identityToken: String, nonce: String) async throws {
        try await session.authenticate(provider: "APPLE", credential: identityToken, nonce: nonce)
        userID = await session.userID()
    }
    func signInWithGoogle() async throws {
        try await session.signInWithGoogle()
        userID = await session.userID()
    }
    func currentAccessToken() async throws -> String { try await session.accessToken() }
    func currentUserID() -> UUID? { userID }
    func signOut(allSessions: Bool = false) async throws {
        try await session.signOut(allSessions: allSessions)
        await shutdown()
        userID = nil
        ledgers.removeAll()
    }
    func authenticationRequired() async -> Bool { await session.userID() == nil }
    func unlinkGoogleIdentity() async throws { try await session.unlinkGoogleIdentity() }
    func unlinkAppleIdentity(identityToken: String, nonce: String) async throws {
        try await session.unlink(provider: "APPLE", credential: identityToken, nonce: nonce)
    }

    func loadSnapshot() async throws -> BackendSnapshot {
        let profile: Profile?
        do { profile = try await profileRequest(method: "GET", path: "/profile") }
        catch SideyBackendError.remote("profile_missing") { profile = nil }
        catch SideyBackendError.remote("profile_required") { profile = nil }
        let rooms: [SpringRoom] = try await request("GET", "/rooms")
        let entitlements: [DatabaseCommerceEntitlement] = try await request("GET", "/commerce/entitlements")
        return BackendSnapshot(profile: profile, rooms: rooms.map(\.domain),
            activeEntitlementKeys: Set(entitlements.filter { $0.status == "active" }.map(\.entitlementKey)))
    }

    func upsertProfile(nickname: String, characterID: String = "pixel_hamster") async throws -> Profile {
        try await profileRequest(method: "PUT", path: "/profile", body: ["nickname": nickname, "characterId": characterID])
    }
    func setEquippedCosmetic(kind: CommerceProductKind, catalogItemID: String?) async throws -> Profile {
        try await profileRequest(method: "PUT", path: "/profile/equipment",
            body: ["kind": kind.rawValue, "catalogItemId": catalogItemID as Any? ?? NSNull()])
    }
    func deleteAccount() async throws { try await mutation("DELETE", "/account") }
    func setTreeMovementPaused(_ paused: Bool, expectedRevision: Int64, expectedUserID: UUID) async throws -> Profile {
        guard userID == expectedUserID else { throw SideyBackendError.sessionRecoveryFailed }
        return try await profileRequest(method: "PUT", path: "/profile/tree", body: ["paused": paused, "expectedRevision": expectedRevision])
    }

    func createRoom(name: String) async throws -> CreatedRoom {
        let value: SpringCreatedRoom = try await request("POST", "/rooms", body: ["name": name])
        return created(value)
    }
    func rotateInviteCode(roomID: UUID) async throws -> CreatedRoom {
        let value: SpringCreatedRoom = try await request("POST", "/rooms/\(roomID)/invite/rotate")
        return created(value)
    }
    func joinRoom(inviteCode: String) async throws -> JoinedRoom {
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let room: SpringRoom = try await request("POST", "/rooms/join", body: ["inviteCode": code])
        return JoinedRoom(roomID: room.id, storedInKeychain: storeInvite(code, roomID: room.id))
    }
    func leaveRoom(_ roomID: UUID) async throws {
        try await mutation("POST", "/rooms/\(roomID)/leave")
        try? keychain.delete(account: inviteAccount(roomID))
    }
    func renameRoom(_ roomID: UUID, name: String) async throws { try await mutation("PUT", "/rooms/\(roomID)", body: ["name": name]) }
    func removeRoomMember(_ roomID: UUID, userID: UUID) async throws { try await mutation("DELETE", "/rooms/\(roomID)/members/\(userID)") }
    func deleteRoom(_ roomID: UUID) async throws {
        try await mutation("DELETE", "/rooms/\(roomID)")
        try? keychain.delete(account: inviteAccount(roomID))
    }
    func storedInviteCode(roomID: UUID) throws -> String? {
        // Preserve locally held invitation secrets across the backend cutover.
        try keychain.readString(account: inviteAccount(roomID))
            ?? keychain.readString(account: "room-invite:\(configuration.legacyBackendFingerprint):default:\(roomID.uuidString.lowercased())")
    }

    func storeState() async throws -> [CommerceState] {
        let remoteProducts: [SpringProduct] = try await request("GET", "/commerce/catalog")
        let products = try SpringCatalog.validatedProducts(remoteProducts)
        let entitlements: [DatabaseCommerceEntitlement] = try await request("GET", "/commerce/entitlements")
        let profile = try await profileRequest(method: "GET", path: "/profile")
        return products.map { product in
            let equipped = switch product.productKind {
            case .character: profile.characterID == product.catalogItemId
            case .bubble: profile.equippedBubbleStyleID == product.catalogItemId
            case .throwable: profile.equippedThrowableID == product.catalogItemId
            }
            return CommerceState(product: product.domain, googleConnected: true,
                entitlementStatus: entitlements.first { $0.entitlementKey == product.entitlementKey }?.status,
                latestOrderStatus: nil, isEquipped: equipped)
        }
    }
    func commerceState(productID: String = CommerceCatalog.starlightUpalupaProductID) async throws -> CommerceState {
        guard let state = try await storeState().first(where: { $0.product.id == productID }) else { throw SideyBackendError.malformedResponse }
        return state
    }
    func createCommerceOrder(productID: String = CommerceCatalog.starlightUpalupaProductID) async throws -> CommerceCheckout {
        let value: SpringCheckout = try await request("POST", "/commerce/orders", body: ["productId": productID])
        return CommerceCheckout(orderID: value.orderId, checkoutURL: value.checkoutUrl)
    }
    func commerceOrderStatus(orderID: UUID) async throws -> String {
        let order: SpringOrder = try await request("GET", "/commerce/orders/\(orderID)")
        guard order.id == orderID else { throw SideyBackendError.malformedResponse }
        return order.status
    }

    func syncRealtime(rooms: [Room], activeRoomID: UUID?) async throws -> BackendReconciliation {
        self.activeRoomID = activeRoomID
        stateRevision += 1
        startReaders()
        do { return try await reconcile() }
        catch { scheduleRecovery(); throw error }
    }
    private func reconcile() async throws -> BackendReconciliation {
        if let recovery { return try await recovery.value }
        let id = UUID()
        recoveryID = id
        let task = Task { try await self.performRecovery() }
        recovery = task
        defer { if recoveryID == id { recovery = nil } }
        return try await task.value
    }
    private func performRecovery() async throws -> BackendReconciliation {
        let current = lifecycle
        while true {
            let revision = stateRevision
            let value = try await recoverRooms(lifecycle: current)
            try ensureCurrent(current)
            if revision == stateRevision {
                emit(.connection(BackendConnectionStatus(transportConnected: true, recoveryReconciled: true)))
                return value
            }
            try Task.checkCancellation()
        }
    }
    private func recoverRooms(lifecycle current: UUID) async throws -> BackendReconciliation {
        guard !stopping, pathAvailable else { throw SideyBackendError.realtimeUnavailable }
        emit(.connection(BackendConnectionStatus(transportConnected: connected, recoveryReconciled: false)))
        // REST first observes explicit revocation immediately, even while a cached
        // access JWT remains unexpired and a rejected WS handshake has no JSON body.
        let snapshot = try await loadSnapshot()
        try ensureCurrent(current)
        adoptAuthorization(snapshot)
        if !connected {
            try await transport.connect(baseURL: configuration.apiBaseURL, accessToken: session.accessToken())
            try ensureCurrent(current)
            connected = true
            subscribed.removeAll()
        }
        let roomIDs = Set(snapshot.rooms.map(\.id))
        for removed in subscribed.subtracting(roomIDs) {
            _ = try await command(["type": "unsubscribe", "roomId": removed.uuidString])
            try ensureCurrent(current)
            subscribed.remove(removed)
        }
        ledgers = ledgers.filter { roomIDs.contains($0.key) }
        if let activeRoomID, !roomIDs.contains(activeRoomID) { self.activeRoomID = snapshot.rooms.first?.id }
        for room in snapshot.rooms {
            // The ACK checkpoint is created AFTER live registration. Live frames may
            // arrive during every await below, and merge into the same UUID ledger.
            let data = try await command(["type": "subscribe", "roomId": room.id.uuidString])
            try ensureCurrent(current)
            subscribed.insert(room.id)
            let ack = try JSONDecoder().decode(SpringSubscribeAck.self, from: data)
            if ledgers[room.id] == nil { ledgers[room.id] = SpringMessageLedger() }
            ledgers[room.id]?.prune()
            if let through = ack.recoveryThrough {
                var cursor = ledgers[room.id]?.confirmedCursor
                repeat {
                    try Task.checkCancellation()
                    let page = try await messagePage(roomID: room.id, after: cursor, through: through, limit: 200)
                    try ensureCurrent(current)
                    guard page.messages.allSatisfy({ $0.roomId == room.id }) else { throw SideyBackendError.malformedResponse }
                    for message in page.messages { try merge(message, emitLive: false) }
                    if let next = page.nextCursor, next == cursor { throw SideyBackendError.malformedResponse }
                    cursor = page.nextCursor
                } while cursor != nil
                ledgers[room.id]?.confirmRecovery(through: through)
            }
            emit(.messagesReplaced(roomID: room.id, messages: ledgers[room.id]?.messages ?? []))
            try await transport.send(Self.json(["type": "presence.snapshot", "roomId": room.id.uuidString]))
            try ensureCurrent(current)
        }
        try await publishPresence()
        try ensureCurrent(current)
        guard connected, !stopping else { throw SideyBackendError.realtimeUnavailable }
        return BackendReconciliation(snapshot: snapshot, activeRoomID: activeRoomID,
            activeMessages: activeRoomID.flatMap { ledgers[$0]?.messages } ?? [])
    }

    private func ensureCurrent(_ current: UUID) throws {
        try Task.checkCancellation()
        guard current == lifecycle, !stopping else { throw CancellationError() }
    }

    private func adoptAuthorization(_ snapshot: BackendSnapshot) {
        authorizedRooms = Set(snapshot.rooms.map(\.id))
        ledgers = ledgers.filter { authorizedRooms.contains($0.key) }
        let allowedPrefixes = Set(authorizedRooms.map(\.uuidString))
        for (key, task) in typingExpiry where !allowedPrefixes.contains(String(key.prefix(36))) {
            task.cancel(); typingExpiry.removeValue(forKey: key)
        }
        latestSnapshot = snapshot
    }

    private func checkMembership() async {
        guard !stopping, pathAvailable, recovery == nil else { return }
        let current = lifecycle
        do {
            let snapshot = try await loadSnapshot()
            try ensureCurrent(current)
            guard snapshot != latestSnapshot else { return }
            adoptAuthorization(snapshot)
            stateRevision += 1
            emit(.snapshot(snapshot))
            scheduleRecovery()
        } catch { _ = await authenticationLost() }
    }

    func setActiveRoom(_ roomID: UUID?) async throws {
        activeRoomID = roomID
        try await publishPresence()
    }
    func setLocalPresence(_ state: PresenceState) async throws {
        localPresence = state
        if connected { try await publishPresence() }
    }
    private func publishPresence() async throws {
        try await transport.send(Self.json(["type": "presence.update", "activeRoomId": activeRoomID?.uuidString as Any? ?? NSNull(),
            "activity": localPresence == .online ? "ONLINE" : "AWAY"]))
    }
    func broadcastTyping(roomID: UUID, event: String) async throws {
        try await transport.send(Self.json(["type": "typing", "roomId": roomID.uuidString, "active": event != "typing_stop"]))
    }
    func broadcastCharacterPulse(roomID: UUID, eventID: UUID) async throws {
        try await transport.send(Self.json(["type": "character.pulse", "roomId": roomID.uuidString, "eventId": eventID.uuidString]))
    }
    func broadcastCharacterThrow(roomID: UUID, eventID: UUID, targetUserID: UUID) async throws {
        try await transport.send(Self.json(["type": "character.throw", "roomId": roomID.uuidString,
            "eventId": eventID.uuidString, "targetUserId": targetUserID.uuidString]))
    }
    func sendMessage(roomID: UUID, body: String, id: UUID = UUID()) async throws -> ChatMessage {
        let current = lifecycle
        let normalized = MessageValidator.normalized(body)
        guard MessageValidator.isValid(normalized) else { throw SideyBackendError.remote("메시지는 200자·3줄 이하로 입력해 주세요.") }
        let payload: [String: Any] = ["type": "message.send", "id": id.uuidString, "roomId": roomID.uuidString, "body": normalized]
        do {
            let data = try await command(payload)
            try ensureCurrent(current)
            let ack = try JSONDecoder().decode(SpringMessageAck.self, from: data)
            try merge(ack.message, emitLive: true)
            return try ack.message.domain
        } catch {
            try ensureCurrent(current)
            if error as? SideyBackendError == .remote("message_id_conflict") { throw error }
            // An ACK may have been lost after COMMIT. The UUID is kept by the
            // caller; a lookup can confirm this attempt without a second insert.
            if let canonical = try? await message(id: id, roomID: roomID) {
                try ensureCurrent(current)
                guard canonical.senderID == userID, canonical.body == normalized else { throw SideyBackendError.remote("message_id_conflict") }
                return canonical
            }
            throw error
        }
    }
    func message(id: UUID, roomID: UUID) async throws -> ChatMessage? {
        do {
            let value: SpringMessage = try await request("GET", "/rooms/\(roomID)/messages/\(id)")
            return try value.domain
        } catch SideyBackendError.remote("message_missing") { return nil }
    }
    func recentMessages(roomID: UUID, limit: Int = 50) async throws -> [ChatMessage] {
        // Room switching uses the recovered room ledger. Older history remains
        // cursor-paged in REST; a recent-window query is never used for recovery.
        if let ledger = ledgers[roomID] { return Array(ledger.messages.suffix(max(1, limit))) }
        return try await historyPage(roomID: roomID, before: nil, pageSize: limit).messages.reversed()
    }
    func historyPage(roomID: UUID, before: MessageHistoryCursor?, pageSize: Int) async throws -> MessageHistoryPage {
        let before = before.map { SpringCursor(createdAt: $0.rawCreatedAt, id: $0.id) }
            ?? SpringCursor(createdAt: PostgresTimestampEncoder.encode(Date().addingTimeInterval(86_400)), id: UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!)
        let page = try await messagePage(roomID: roomID, before: before, limit: min(max(1, pageSize), 200))
        return try page.domain
    }
    private func messagePage(roomID: UUID, after: SpringCursor? = nil, before: SpringCursor? = nil,
                             through: SpringCursor? = nil, limit: Int) async throws -> SpringMessagePage {
        var query = URLComponents()
        query.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        for (prefix, cursor) in [("after", after), ("before", before), ("through", through)] {
            if let cursor {
                query.queryItems?.append(URLQueryItem(name: prefix + "CreatedAt", value: cursor.createdAt))
                query.queryItems?.append(URLQueryItem(name: prefix + "Id", value: cursor.id.uuidString))
            }
        }
        // Spring decodes query parameters using form semantics: a literal '+'
        // in PostgreSQL timezone offsets would otherwise become a space.
        let encoded = (query.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
        return try await request("GET", "/rooms/\(roomID)/messages?\(encoded)")
    }

    private func startReaders() {
        if membershipPoll == nil {
            membershipPoll = Task { [weak self, membershipPollInterval] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: membershipPollInterval) } catch { return }
                    await self?.checkMembership()
                }
            }
        }
        if reader == nil {
            reader = Task { [weak self, transport] in
                for await event in transport.events {
                    guard !Task.isCancelled else { return }
                    await self?.receive(event)
                }
            }
        }
        if networkReader == nil {
            networkPathMonitor.start()
            networkReader = Task { [weak self, networkPathMonitor] in
                for await availability in networkPathMonitor.updates {
                    guard !Task.isCancelled else { return }
                    await self?.networkChanged(availability)
                }
            }
        }
    }
    private func receive(_ event: SpringRealtimeTransport.Event) async {
        guard !stopping, await transport.isCurrent(event) else { return }
        switch event {
        case .closed:
            stateRevision += 1
            connected = false
            emit(.connection(BackendConnectionStatus(transportConnected: false, recoveryReconciled: false)))
            scheduleRecovery()
        case .frame(let data, _):
            do {
                let event = try JSONDecoder().decode(SpringEvent.self, from: data)
                if event.type == "error", let code = event.code {
                    if ["membership_required", "room_missing"].contains(code) { await checkMembership() }
                    emit(.technicalError(SideyBackendError.business(code: code).localizedDescription))
                    return
                }
                if event.type == "message.created", let message = event.message {
                    guard authorizedRooms.contains(message.roomId) else { return }
                    try merge(message, emitLive: true); return
                }
                if event.type == "room.changed" { stateRevision += 1; scheduleRecovery(); return }
                guard let room = event.roomId, authorizedRooms.contains(room) else { return }
                switch event.type {
                case "messages.pruned":
                    ledgers[room]?.prune()
                    emit(.messagesReplaced(roomID: room, messages: ledgers[room]?.messages ?? []))
                case "presence":
                    for (id, value) in event.members ?? [:] {
                        guard let user = UUID(uuidString: id) else { continue }
                        let state: PresenceState = value == "ONLINE" ? .online : value == "AWAY" ? .away : .offline
                        emit(.presence(roomID: room, userID: user, state: state))
                    }
                case "typing":
                    guard let user = event.userId, user != userID else { return }
                    let key = "\(room):\(user)"
                    typingExpiry.removeValue(forKey: key)?.cancel()
                    let active = event.active == true
                    emit(.typing(roomID: room, userID: user, active: active))
                    if active {
                        typingExpiry[key] = Task { [weak self] in
                            do { try await Task.sleep(for: .seconds(4)) } catch { return }
                            await self?.expireTyping(key: key, room: room, user: user)
                        }
                    }
                case "character.pulse":
                    if let user = event.userId, user != userID, let id = event.eventId {
                        emit(.characterPulse(CharacterPulseEvent(id: id, roomID: room, userID: user)))
                    }
                case "character.throw":
                    if let user = event.userId, user != userID, let id = event.eventId,
                       let target = event.targetUserId, let source = event.sourceCharacterId {
                        emit(.characterThrow(CharacterThrowEvent(id: id, roomID: room, actorUserID: user,
                            targetUserID: target, sourceCharacterID: source, throwableID: event.throwableId)))
                    }
                default: break
                }
            } catch { await transport.disconnect(); connected = false; scheduleRecovery() }
        }
    }
    private func expireTyping(key: String, room: UUID, user: UUID) {
        typingExpiry.removeValue(forKey: key)
        emit(.typing(roomID: room, userID: user, active: false))
    }
    private func merge(_ value: SpringMessage, emitLive: Bool) throws {
        if ledgers[value.roomId] == nil { ledgers[value.roomId] = SpringMessageLedger() }
        let isNew = try ledgers[value.roomId]!.merge(value)
        if emitLive, isNew { emit(.message(try value.domain)) }
    }
    private func scheduleRecovery() {
        guard !stopping, retry == nil else { return }
        retry = Task { [weak self] in
            var delay = 1
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard let self else { return }
                do {
                    let value = try await self.reconcile()
                    await self.recovered(value)
                    return
                } catch {
                    if await self.authenticationLost() { return }
                    delay = min(delay * 2, 30)
                }
            }
        }
    }
    private func recovered(_ value: BackendReconciliation) {
        guard !stopping, !Task.isCancelled else { return }
        retry = nil
        emit(.reconciliation(value))
    }
    private func authenticationLost() async -> Bool {
        guard await session.userID() == nil else { return false }
        await shutdown()
        userID = nil
        ledgers.removeAll()
        emit(.authenticationRequired)
        return true
    }
    private func networkChanged(_ availability: NetworkAvailability) async {
        let wasAvailable = pathAvailable
        pathAvailable = availability == .available
        if !pathAvailable { await transport.disconnect(); connected = false }
        if wasAvailable != pathAvailable { scheduleRecovery() }
    }
    func shutdown() async {
        lifecycle = UUID()
        stopping = true
        retry?.cancel(); retry = nil
        recovery?.cancel(); recovery = nil; recoveryID = UUID()
        typingExpiry.values.forEach { $0.cancel() }; typingExpiry.removeAll()
        membershipPoll?.cancel(); membershipPoll = nil
        authorizedRooms.removeAll(); latestSnapshot = nil
        await transport.disconnect()
        connected = false
        subscribed.removeAll()
        // Readers remain attached across logout/login. Cancelling an AsyncStream
        // iterator terminates the shared stream; shutdown is also used on sign-in.
    }

    private func command(_ payload: [String: Any]) async throws -> Data {
        var body = payload
        let id = UUID().uuidString
        body["requestId"] = id
        do { return try await transport.command(Self.json(body), requestID: id) }
        catch SpringRealtimeTransport.Failure.server(let code) {
            if ["membership_required", "room_missing"].contains(code),
               let value = payload["roomId"] as? String, let room = UUID(uuidString: value) { revokeLocalRoom(room) }
            throw SideyBackendError.business(code: code)
        }
    }
    private func request<T: Decodable>(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> T {
        let data = try await requestData(method, path, body: body)
        return try JSONDecoder().decode(T.self, from: data)
    }
    private func profileRequest(method: String, path: String, body: [String: Any]? = nil) async throws -> Profile {
        let value: SpringProfile = try await request(method, path, body: body)
        return value.domain
    }
    private func mutation(_ method: String, _ path: String, body: [String: Any]? = nil) async throws {
        _ = try await requestData(method, path, body: body)
    }
    private func requestData(_ method: String, _ path: String, body: [String: Any]?) async throws -> Data {
        let current = lifecycle
        do {
            let data = try await session.request(method: method, path: path, body: body.map(Self.json))
            try ensureCurrent(current)
            return data
        }
        catch SideySessionError.rejected(let code) {
            if ["membership_required", "room_missing"].contains(code) {
                let parts = path.split(separator: "/")
                if parts.count >= 2, parts[0] == "rooms", let room = UUID(uuidString: String(parts[1])) { revokeLocalRoom(room) }
            }
            throw SideyBackendError.business(code: code)
        }
        catch SideySessionError.authenticationRequired {
            _ = await authenticationLost()
            throw SideyBackendError.sessionRecoveryFailed
        }
        catch SideySessionError.legacyClaimRequired {
            _ = await authenticationLost()
            throw SideyBackendError.sessionRecoveryFailed
        }
    }
    private func revokeLocalRoom(_ room: UUID) {
        authorizedRooms.remove(room)
        ledgers.removeValue(forKey: room)
        if activeRoomID == room { activeRoomID = nil }
        if var snapshot = latestSnapshot {
            snapshot.rooms.removeAll { $0.id == room }
            adoptAuthorization(snapshot)
            emit(.snapshot(snapshot))
        }
        emit(.messagesReplaced(roomID: room, messages: []))
        stateRevision += 1
        scheduleRecovery()
    }
    private static func json(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    private func inviteAccount(_ roomID: UUID) -> String { "room-invite:\(configuration.backendFingerprint):default:\(roomID.uuidString.lowercased())" }
    private func storeInvite(_ code: String, roomID: UUID) -> Bool {
        do { try keychain.writeString(code, account: inviteAccount(roomID)); return true } catch { return false }
    }
    private func created(_ value: SpringCreatedRoom) -> CreatedRoom {
        CreatedRoom(roomID: value.room.id, inviteCode: value.inviteCode, storedInKeychain: storeInvite(value.inviteCode, roomID: value.room.id))
    }
    private func emit(_ event: BackendEvent) {
        switch continuation.yield(event) {
        case .dropped: stateRevision += 1; scheduleRecovery()
        case .terminated: stopping = true
        default: break
        }
    }
#if DEBUG
    func interruptRealtimeConnectionForTesting() async { await transport.disconnect(); connected = false; scheduleRecovery() }
    func simulateNetworkAvailabilityForTesting(_ value: NetworkAvailability) async { await networkChanged(value) }
    func deleteOwnAccountForTesting() async throws { try await mutation("DELETE", "/account") }
#endif
}
