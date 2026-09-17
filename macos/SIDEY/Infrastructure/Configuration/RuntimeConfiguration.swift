import CryptoKit
import Foundation

// Dispatch old application URLs only. New Google login uses a loopback redirect.
enum SideyAuthCallback {
    static let productionScheme = "sidey"
    static var configuredScheme: String {
        normalized(Bundle.main.object(forInfoDictionaryKey: "SIDEYAuthURLScheme") as? String) ?? productionScheme
    }
    static func callbackURL(scheme: String? = nil) -> URL {
        URL(string: "\(normalized(scheme) ?? configuredScheme)://auth/google")!
    }
    static func matches(_ url: URL, scheme: String? = nil) -> Bool {
        url.scheme?.lowercased() == (normalized(scheme) ?? configuredScheme)
            && url.host == "auth" && url.path == "/google"
    }
    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty, value.first?.isLetter == true,
              value.allSatisfy({ $0.isLetter || $0.isNumber || "+-.".contains($0) }) else { return nil }
        return value
    }
}

struct RuntimeConfiguration: Equatable, Sendable {
    static let productionHost = "api.sidey.app"
    static let legacyProductionURL = URL(string: "https://whtejsviizgejauasqqt.supabase.co")!
    static let legacyProductionKey = "sb_publishable_kkASOI4rRTX8Drob21hkCw_VwUex63Y"
    let apiBaseURL: URL
    var googleClientID: String = ""
    // Google installed-desktop OAuth client configuration is public application data.
    var googleClientSecret: String = ""
    var legacySupabaseURL: URL = Self.legacyProductionURL
    var legacySupabasePublishableKey: String = Self.legacyProductionKey

    var backendFingerprint: String { Self.fingerprint(apiBaseURL) }
    var legacyBackendFingerprint: String { Self.fingerprint(legacySupabaseURL) }
    var isProductionBackend: Bool { apiBaseURL.host?.lowercased() == Self.productionHost }

    static func resolve(
        releaseChannel: AppReleaseChannel = .resolve(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleInfo: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) throws -> Self {
        let production = releaseChannel == .production || releaseChannel == .appStore
        func configured(_ environmentKey: String, _ bundleKey: String) -> String? {
            let raw = production ? bundleInfo[bundleKey] as? String
                : environment[environmentKey] ?? bundleInfo[bundleKey] as? String
            guard let result = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !result.isEmpty, !result.contains("$(") else { return nil }
            return result
        }
        let rawURL = configured("SIDEY_API_BASE_URL", "SIDEYAPIBaseURL")
            ?? (production ? "https://\(productionHost)/api" : nil)
        guard let rawURL, let url = URL(string: rawURL), isAllowedBackendURL(url), ["/api", "/api/"].contains(url.path),
              !production || url.scheme == "https" else {
            throw RuntimeConfigurationError.missingDevelopmentConfiguration
        }
        if !production && url.host?.lowercased() == productionHost {
            throw RuntimeConfigurationError.productionBackendNotAllowedInDevelopment
        }
        var result = Self(apiBaseURL: url,
            googleClientID: configured("SIDEY_GOOGLE_CLIENT_ID", "SIDEYGoogleClientID") ?? "",
            googleClientSecret: configured("SIDEY_GOOGLE_CLIENT_SECRET", "SIDEYGoogleClientSecret") ?? "")
        if !production {
            let legacyURL = configured("SIDEY_LEGACY_SUPABASE_URL", "SIDEYLegacySupabaseURL")
            let legacyKey = configured("SIDEY_LEGACY_SUPABASE_PUBLISHABLE_KEY", "SIDEYLegacySupabasePublishableKey")
            if legacyURL != nil || legacyKey != nil {
                guard let legacyURL, let parsed = URL(string: legacyURL), isAllowedBackendURL(parsed),
                      let legacyKey else { throw RuntimeConfigurationError.incompleteEnvironment }
                guard !looksLikeSecretKey(legacyKey) else { throw RuntimeConfigurationError.secretKeyNotAllowed }
                result.legacySupabaseURL = parsed
                result.legacySupabasePublishableKey = legacyKey
            }
        }
        return result
    }
    private static func fingerprint(_ url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
    private static func isAllowedBackendURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return false }
        return scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host))
    }
    private static func looksLikeSecretKey(_ value: String) -> Bool {
        if value.hasPrefix("sb_secret_") || value.hasPrefix("service_role") { return true }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return false }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["role"] as? String == "service_role"
    }
}

enum RuntimeConfigurationError: LocalizedError, Equatable {
    case incompleteEnvironment
    case secretKeyNotAllowed
    case missingDevelopmentConfiguration
    case productionBackendNotAllowedInDevelopment
    var errorDescription: String? {
        switch self {
        case .incompleteEnvironment: "기존 계정 복구용 URL과 public key를 모두 설정해야 합니다."
        case .secretKeyNotAllowed: "클라이언트에 서버 secret/service-role 키를 사용할 수 없습니다."
        case .missingDevelopmentConfiguration: "SIDEY_API_BASE_URL에 유효한 backend URL을 설정해 주세요."
        case .productionBackendNotAllowedInDevelopment: "Sidey-dev는 production backend에 연결할 수 없습니다."
        }
    }
}
