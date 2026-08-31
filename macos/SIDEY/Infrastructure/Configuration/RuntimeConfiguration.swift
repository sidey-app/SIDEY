import CryptoKit
import Foundation

struct RuntimeConfiguration: Equatable, Sendable {
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
                  let url = URL(string: rawURL), url.scheme == "https", url.host != nil
            else { throw RuntimeConfigurationError.incompleteEnvironment }
            guard !Self.looksLikeSecretKey(key) else { throw RuntimeConfigurationError.secretKeyNotAllowed }
            return Self(supabaseURL: url, supabasePublishableKey: key)
        }

        // Supabase publishable keys are client identifiers, not server secrets. These values
        // match the existing alpha client so a native migration keeps the same backend contract.
        return Self(
            supabaseURL: URL(string: "https://whtejsviizgejauasqqt.supabase.co")!,
            supabasePublishableKey: "sb_publishable_kkASOI4rRTX8Drob21hkCw_VwUex63Y"
        )
    }

    private static func looksLikeSecretKey(_ value: String) -> Bool {
        value.hasPrefix("sb_secret_") || value.hasPrefix("service_role")
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
