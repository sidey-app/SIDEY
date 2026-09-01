import CryptoKit
import Foundation

struct RuntimeConfiguration: Equatable, Sendable {
    static let productionHost = "whtejsviizgejauasqqt.supabase.co"
    let supabaseURL: URL
    let supabasePublishableKey: String

    var backendFingerprint: String {
        let digest = SHA256.hash(data: Data(supabaseURL.absoluteString.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Self {
        let environmentURL = environment["SIDEY_SUPABASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let environmentKey = environment["SIDEY_SUPABASE_PUBLISHABLE_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)

        if environmentURL != nil || environmentKey != nil {
            guard let rawURL = environmentURL, !rawURL.isEmpty,
                  let key = environmentKey, !key.isEmpty,
                  let url = URL(string: rawURL), Self.isAllowedBackendURL(url)
            else { throw RuntimeConfigurationError.incompleteEnvironment }
            guard !Self.looksLikeSecretKey(key) else { throw RuntimeConfigurationError.secretKeyNotAllowed }
            return Self(supabaseURL: url, supabasePublishableKey: key)
        }

        // Supabase publishable keys are client identifiers, not server secrets. These values
        // match the existing alpha client so a native migration keeps the same backend contract.
        return Self(
            supabaseURL: URL(string: "https://\(productionHost)")!,
            supabasePublishableKey: "sb_publishable_kkASOI4rRTX8Drob21hkCw_VwUex63Y"
        )
    }

    var isProductionBackend: Bool {
        supabaseURL.host?.lowercased() == Self.productionHost
    }

    private static func isAllowedBackendURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
            return false
        }
        if scheme == "https" { return true }
        return scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)
    }

    private static func looksLikeSecretKey(_ value: String) -> Bool {
        if value.hasPrefix("sb_secret_") || value.hasPrefix("service_role") {
            return true
        }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return false }
        var encodedPayload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encodedPayload += String(repeating: "=", count: (4 - encodedPayload.count % 4) % 4)
        guard let data = Data(base64Encoded: encodedPayload),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return payload["role"] as? String == "service_role"
    }
}

enum RuntimeConfigurationError: LocalizedError, Equatable {
    case incompleteEnvironment
    case secretKeyNotAllowed

    var errorDescription: String? {
        switch self {
        case .incompleteEnvironment:
            "SIDEY_SUPABASE_URL과 SIDEY_SUPABASE_PUBLISHABLE_KEY를 모두 설정해야 합니다."
        case .secretKeyNotAllowed:
            "클라이언트에 Supabase secret/service-role 키를 사용할 수 없습니다."
        }
    }
}
