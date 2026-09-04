import Foundation
import StoreKit

@MainActor
final class AppStorePurchaseController {
    private let verifierURL: URL?
    private var productsByID: [String: Product] = [:]
    private var updatesTask: Task<Void, Never>?

    init(verifierURL: URL? = AppStoreServiceEndpoint.resolve()) {
        self.verifierURL = verifierURL
    }

    deinit { updatesTask?.cancel() }

    func loadProducts() async throws -> [String: String] {
        let products = try await Product.products(for: CommerceCatalog.products.map(\.id))
        productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        return Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0.displayPrice) })
    }

    func purchase(productID: String, userID: UUID, accessToken: String) async throws -> Bool {
        if productsByID[productID] == nil { _ = try await loadProducts() }
        guard let product = productsByID[productID] else {
            throw AppStorePurchaseError.productUnavailable
        }
        let result = try await product.purchase(options: [.appAccountToken(userID)])
        switch result {
        case .success(let verification):
            try await submit(verification, accessToken: accessToken)
            return true
        case .pending:
            throw AppStorePurchaseError.pending
        case .userCancelled:
            return false
        @unknown default:
            throw AppStorePurchaseError.unknownResult
        }
    }

    func restore(accessToken: String) async throws {
        try await AppStore.sync()
        try await reconcileCurrentEntitlements(accessToken: accessToken)
    }

    func reconcileCurrentEntitlements(accessToken: String) async throws {
        for await verification in Transaction.currentEntitlements {
            try await submit(verification, accessToken: accessToken)
        }
    }

    func startObserving(
        accessToken: @escaping @Sendable () async throws -> String,
        didChange: @escaping @MainActor () -> Void,
        didFail: @escaping @MainActor (String) -> Void
    ) {
        updatesTask?.cancel()
        updatesTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await verification in Transaction.updates {
                guard !Task.isCancelled else { return }
                do {
                    try await submit(
                        verification,
                        accessToken: try await accessToken()
                    )
                    didChange()
                } catch {
                    didFail(error.localizedDescription)
                }
            }
        }
    }

    func stopObserving() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    private func submit(
        _ verification: VerificationResult<Transaction>,
        accessToken: String
    ) async throws {
        guard case .verified(let transaction) = verification else {
            throw AppStorePurchaseError.unverifiedTransaction
        }
        guard transaction.productID.isEmpty == false,
              CommerceCatalog.product(id: transaction.productID) != nil
        else { throw AppStorePurchaseError.productUnavailable }
        guard let verifierURL else { throw AppStorePurchaseError.verifierNotConfigured }

        var request = URLRequest(
            url: verifierURL.appending(path: "v1/app-store/transactions")
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            SignedTransactionRequest(signedTransactionInfo: verification.jwsRepresentation)
        )
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppStorePurchaseError.serverRejected
        }
        await transaction.finish()
    }
}

enum AppStoreServiceEndpoint {
    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) -> URL? {
#if DEBUG
        let raw = environment["SIDEY_APP_STORE_VERIFIER_URL"]
            ?? bundle.object(forInfoDictionaryKey: "SIDEYAppStoreVerifierURL") as? String
#else
        let raw = bundle.object(forInfoDictionaryKey: "SIDEYAppStoreVerifierURL") as? String
#endif
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              let url = URL(string: value),
              url.host != nil,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil,
              Self.isAllowed(url)
        else { return nil }
        return url
    }

    private static func isAllowed(_ url: URL) -> Bool {
        if url.scheme == "https" { return true }
#if DEBUG
        return url.scheme == "http"
            && ["localhost", "127.0.0.1", "::1"].contains(url.host?.lowercased())
#else
        return false
#endif
    }
}

private struct SignedTransactionRequest: Encodable {
    let signedTransactionInfo: String
}

enum AppStorePurchaseError: LocalizedError {
    case productUnavailable
    case pending
    case unknownResult
    case unverifiedTransaction
    case verifierNotConfigured
    case serverRejected

    var errorDescription: String? {
        switch self {
        case .productUnavailable: "App Store에서 이 상품을 찾지 못했습니다."
        case .pending: "구매 승인이 대기 중입니다. 승인 후 자동으로 반영됩니다."
        case .unknownResult: "알 수 없는 App Store 구매 결과입니다."
        case .unverifiedTransaction: "Apple이 검증하지 못한 거래라 반영하지 않았습니다."
        case .verifierNotConfigured: "App Store 거래 검증 서버가 설정되지 않았습니다."
        case .serverRejected: "서버가 App Store 거래를 승인하지 않았습니다."
        }
    }
}
