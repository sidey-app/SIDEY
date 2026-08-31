import XCTest
@testable import SIDEY

final class KeychainStoreTests: XCTestCase {
    func testDefaultOperationReasonExplainsWhySIDEYUsesKeychain() {
        XCTAssertEqual(
            KeychainStore.defaultOperationReason,
            "SIDEY는 로그인 세션과 그룹 초대 코드를 안전하게 불러오기 위해 macOS 키체인 접근이 필요합니다."
        )
    }

    func testKeychainRoundTripAndDeletion() throws {
        let store = KeychainStore(service: "app.sidey.desktop.tests.\(UUID().uuidString)")
        let account = "round-trip"
        defer { try? store.delete(account: account) }

        try store.writeString("SIDEY-비밀값", account: account)
        XCTAssertEqual(try store.readString(account: account), "SIDEY-비밀값")
        try store.delete(account: account)
        XCTAssertNil(try store.read(account: account))
    }

    func testSupabaseStorageMirrorsRefreshTokenForRollback() throws {
        let store = KeychainStore(service: "app.sidey.desktop.tests.\(UUID().uuidString)")
        let sessionAccount = "native-session"
        let legacyAccount = "legacy-refresh"
        defer {
            try? store.delete(account: sessionAccount)
            try? store.delete(account: legacyAccount)
        }
        let storage = SideyAuthStorage(keychain: store, legacyRefreshAccount: legacyAccount)
        let session = Data(#"{"access_token":"access","refresh_token":"keep-this-account"}"#.utf8)

        try storage.store(key: sessionAccount, value: session)

        XCTAssertEqual(try storage.retrieve(key: sessionAccount), session)
        XCTAssertEqual(try store.readString(account: legacyAccount), "keep-this-account")
    }

    func testNativeBackendReadsGodotInviteCodeAccount() async throws {
        let store = KeychainStore(service: "app.sidey.desktop.tests.\(UUID().uuidString)")
        let configuration = try RuntimeConfiguration.resolve(environment: [:])
        let roomID = try XCTUnwrap(UUID(uuidString: "A33009C1-B56D-4DEB-9CF2-ECEB778B658F"))
        let godotAccount = "room-invite:\(configuration.backendFingerprint):default:\(roomID.uuidString.lowercased())"
        defer { try? store.delete(account: godotAccount) }
        try store.writeString("SIDEY-LEGACY-CODE", account: godotAccount)
        let backend = SideyBackend(configuration: configuration, keychain: store)

        let migrated = try await backend.storedInviteCode(roomID: roomID)

        XCTAssertEqual(migrated, "SIDEY-LEGACY-CODE")
        await backend.shutdown()
    }

    func testExistingLocalIdentityNeverCreatesReplacementAnonymousSession() async throws {
        let store = KeychainStore(service: "app.sidey.desktop.tests.\(UUID().uuidString)")
        let configuration = try RuntimeConfiguration.resolve(environment: [:])
        let backend = SideyBackend(configuration: configuration, keychain: store)

        do {
            _ = try await backend.boot(requireExistingSession: true)
            XCTFail("기존 로컬 계정은 세션 복구 실패 시 새 익명 계정을 만들면 안 됨")
        } catch let error as SideyBackendError {
            XCTAssertEqual(error, .sessionRecoveryFailed)
        } catch {
            XCTFail("예상하지 못한 오류: \(error)")
        }
        await backend.shutdown()
    }
}
