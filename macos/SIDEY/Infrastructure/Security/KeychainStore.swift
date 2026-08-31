import Foundation
import Security
import Supabase

struct KeychainStore: Sendable {
    let service: String

    init(service: String = "com.sidey.desktop") {
        self.service = service
    }

    func read(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainStoreError(status: status)
        }
        return data
    }

    func write(_ data: Data, account: String) throws {
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw KeychainStoreError(status: updateStatus) }

        var insertion = query
        insertion.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(insertion as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainStoreError(status: addStatus) }
    }

    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError(status: status)
        }
    }

    func deleteAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError(status: status)
        }
    }

    func readString(account: String) throws -> String? {
        guard let data = try read(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func writeString(_ value: String, account: String) throws {
        try write(Data(value.utf8), account: account)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct KeychainStoreError: LocalizedError, Equatable {
    let status: OSStatus

    var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? "Keychain 오류 \(status)"
    }
}

/// Supabase의 전체 세션과 기존 Godot 클라이언트의 refresh token을 함께 갱신한다.
/// 네이티브 알파를 롤백해도 익명 계정이 끊기지 않게 하는 호환 계층이다.
struct SideyAuthStorage: AuthLocalStorage, Sendable {
    let keychain: KeychainStore
    let legacyRefreshAccount: String

    func store(key: String, value: Data) throws {
        try keychain.write(value, account: key)
        if let object = try? JSONSerialization.jsonObject(with: value) as? [String: Any],
           let refreshToken = object["refresh_token"] as? String,
           !refreshToken.isEmpty {
            try keychain.writeString(refreshToken, account: legacyRefreshAccount)
        }
    }

    func retrieve(key: String) throws -> Data? {
        try keychain.read(account: key)
    }

    func remove(key: String) throws {
        try keychain.delete(account: key)
    }
}
