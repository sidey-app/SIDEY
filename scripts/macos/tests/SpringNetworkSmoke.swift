import Foundation
import Security

private func report(_ value: String) { FileHandle.standardError.write(Data((value + "\n").utf8)) }
private enum SmokeFailure: Error { case failed(String) }
private func require(_ value: Bool, _ message: String) throws {
    if !value { throw SmokeFailure.failed(message) }
}
private final class MemoryCredentialStore: KeychainSecurityPerforming, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data]
    init(account: String, data: Data) { values = [account: data] }
    func copyMatching(_ query: CFDictionary) -> (status: OSStatus, data: Data?) {
        lock.withLock {
            let value = values[(query as NSDictionary)[kSecAttrAccount] as? String ?? ""]
            return (value == nil ? errSecItemNotFound : errSecSuccess, value)
        }
    }
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        lock.withLock {
            let key = (query as NSDictionary)[kSecAttrAccount] as? String ?? ""
            guard values[key] != nil else { return errSecItemNotFound }
            values[key] = (attributes as NSDictionary)[kSecValueData] as? Data
            return errSecSuccess
        }
    }
    func add(_ attributes: CFDictionary) -> OSStatus {
        lock.withLock {
            values[(attributes as NSDictionary)[kSecAttrAccount] as? String ?? ""] = (attributes as NSDictionary)[kSecValueData] as? Data
            return errSecSuccess
        }
    }
    func delete(_ query: CFDictionary) -> OSStatus {
        lock.withLock { values.removeValue(forKey: (query as NSDictionary)[kSecAttrAccount] as? String ?? ""); return errSecSuccess }
    }
}
private struct LocalNetworkMonitor: NetworkPathMonitoring {
    let updates = AsyncStream<NetworkAvailability> { $0.finish() }
    func start() {}
    func cancel() {}
}
private actor Probe {
    var messages: Set<UUID> = []
    var rooms: Set<UUID> = []
    var typing: Set<UUID> = []
    var online: Set<UUID> = []
    func accept(_ event: BackendEvent) {
        switch event {
        case .message(let message): messages.insert(message.id)
        case .snapshot(let snapshot): rooms = Set(snapshot.rooms.map(\.id))
        case .reconciliation(let value): rooms = Set(value.snapshot.rooms.map(\.id))
        case .typing(_, let user, let active): if active { typing.insert(user) }
        case .presence(_, let user, let state): if state == .online { online.insert(user) }
        default: break
        }
    }
    func saw(_ id: UUID) -> Bool { messages.contains(id) }
    func hasRoom(_ id: UUID) -> Bool { rooms.contains(id) }
    func sawTyping(_ id: UUID) -> Bool { typing.contains(id) }
    func sawOnline(_ id: UUID) -> Bool { online.contains(id) }
}
private func wait(_ message: String, _ condition: @escaping @Sendable () async -> Bool) async throws {
    let until = ContinuousClock.now.advanced(by: .seconds(8))
    while !(await condition()) {
        guard ContinuousClock.now < until else { throw SmokeFailure.failed(message) }
        try await Task.sleep(for: .milliseconds(10))
    }
}
@main private struct SpringNetworkSmoke {
    static func main() async throws {
        guard CommandLine.arguments.count == 2,
              let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as? [String: Any],
              let raw = fixture["apiBase"] as? String, let url = URL(string: raw),
              ["127.0.0.1", "localhost", "::1"].contains(url.host ?? ""), url.scheme == "http",
              let sessions = fixture["sessions"] as? [[String: Any]], sessions.count == 2,
              let firstID = sessions[0]["userId"] as? String, let firstUser = UUID(uuidString: firstID),
              let secondID = sessions[1]["userId"] as? String, let secondUser = UUID(uuidString: secondID), firstUser != secondUser else {
            throw SmokeFailure.failed("Two disposable loopback sessions are required")
        }
        let configuration = RuntimeConfiguration(apiBaseURL: url)
        var clients: [SideyBackend] = []
        var sockets: [SpringRealtimeTransport] = []
        for var value in sessions {
            // Force real refresh rotation rather than trusting the fixture's access JWT.
            value["accessExpiresAt"] = "2000-01-01T00:00:00Z"
            let account = "sidey-session:\(configuration.backendFingerprint):default"
            let storage = MemoryCredentialStore(account: account, data: try JSONSerialization.data(withJSONObject: value))
            let keychain = KeychainStore(service: UUID().uuidString, session: KeychainAccessSession(security: storage))
            let socket = SpringRealtimeTransport()
            clients.append(SideyBackend(configuration: configuration, keychain: keychain,
                networkPathMonitor: LocalNetworkMonitor(), transport: socket, membershipPollInterval: .milliseconds(250)))
            sockets.append(socket)
        }
        let first = clients[0], second = clients[1]
        let probe = Probe()
        let reader = Task { for await event in second.events { await probe.accept(event) } }
        defer { reader.cancel() }
        FileHandle.standardError.write(Data("STEP boot first\n".utf8))
        _ = try await first.boot()
        FileHandle.standardError.write(Data("STEP boot second\n".utf8))
        _ = try await second.boot()
        FileHandle.standardError.write(Data("STEP profiles\n".utf8))
        _ = try await first.upsertProfile(nickname: "맥첫째")
        _ = try await second.upsertProfile(nickname: "맥둘째")
        report("PASS real SIDEY session refresh and profile REST")
        let room = try await first.createRoom(name: "맥통합검증")
        _ = try await second.joinRoom(inviteCode: room.inviteCode)
        let one = try await first.loadSnapshot(), two = try await second.loadSnapshot()
        await probe.accept(.snapshot(two))
        _ = try await first.syncRealtime(rooms: one.rooms, activeRoomID: room.roomID)
        _ = try await second.syncRealtime(rooms: two.rooms, activeRoomID: room.roomID)
        let id = UUID()
        let canonical = try await first.sendMessage(roomID: room.roomID, body: "안전한 재시도", id: id)
        let duplicate = try await first.sendMessage(roomID: room.roomID, body: "안전한 재시도", id: id)
        try require(canonical.id == duplicate.id && canonical.createdAt == duplicate.createdAt, "Canonical UUID retry changed")
        do {
            _ = try await first.sendMessage(roomID: room.roomID, body: "다른 내용", id: id)
            throw SmokeFailure.failed("Different payload accepted")
        } catch SideyBackendError.remote("message_id_conflict") {}
        try await wait("Committed live message missing") { await probe.saw(id) }
        let history = try await first.historyPage(roomID: room.roomID, before: nil, pageSize: 200)
        try require(history.messages.filter { $0.id == id }.count == 1, "Duplicate persistent message")
        report("PASS real raw WS send, UUID retry/conflict, peer fanout and REST history")
        try await first.broadcastTyping(roomID: room.roomID, event: "typing_start")
        try await first.setLocalPresence(.online)
        try await wait("Typing missing") { await probe.sawTyping(firstUser) }
        try await wait("Presence missing") { await probe.sawOnline(firstUser) }
        report("PASS server typing and focused presence")
        await sockets[1].disconnect()
        let missing = try await first.sendMessage(roomID: room.roomID, body: "연결 복구", id: UUID())
        let recovered = try await second.syncRealtime(rooms: two.rooms, activeRoomID: room.roomID)
        try require(recovered.activeMessages.contains { $0.id == missing.id }, "Recovery lost committed message")
        report("PASS disconnect and subscribe-first REST recovery")
        try await first.removeRoomMember(room.roomID, userID: secondUser)
        // The server may silently remove subscriptions; real REST reconciliation must notice.
        try await wait("Silent kick retained local room") { !(await probe.hasRoom(room.roomID)) }
        do {
            _ = try await second.sendMessage(roomID: room.roomID, body: "차단 확인", id: UUID())
            throw SmokeFailure.failed("Removed member sent message")
        } catch SideyBackendError.membershipRequired {}
        report("PASS silent kick reconciliation and server authorization")
        try await first.deleteAccount()
        try await second.deleteAccount()
        await first.shutdown(); await second.shutdown()
        report("PASS disposable account deletion and owner-room cleanup")
    }
}
