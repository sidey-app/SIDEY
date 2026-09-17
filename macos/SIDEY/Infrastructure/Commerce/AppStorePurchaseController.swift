import Foundation
import StoreKit
import OSLog

@MainActor
final class AppStorePurchaseController {
    private let logger = Logger(subsystem: "app.sidey.desktop", category: "AppStoreProducts")
    private let transactions: AppStoreTransactionClient
    private var productsByID: [String: Product] = [:]
    private var updatesTask: Task<Void, Never>?

    init(apiBaseURL: URL? = AppStoreServiceEndpoint.resolve(), session: URLSession = .shared) {
        self.transactions = AppStoreTransactionClient(apiBaseURL: apiBaseURL, session: session)
    }

    deinit { updatesTask?.cancel() }

    func loadProducts() async throws -> [String: String] {
        let products = try await Product.products(for: CommerceCatalog.products.map(\.appStoreProductID))
        let missingIDs = Set(CommerceCatalog.products.map(\.appStoreProductID))
            .subtracting(products.map(\.id)).sorted().joined(separator: ",")
        logger.notice("StoreKit returned \(products.count) products; unavailable IDs: \(missingIDs, privacy: .public)")
        productsByID = Dictionary(uniqueKeysWithValues: products.compactMap { product in
            CommerceCatalog.product(appStoreID: product.id).map { ($0.id, product) }
        })
        return Dictionary(uniqueKeysWithValues: productsByID.map { ($0.key, $0.value.displayPrice) })
    }

    func purchase(productID: String, userID: UUID, accessToken: @escaping @Sendable () async throws -> String) async throws -> Bool {
        if productsByID[productID] == nil { _ = try await loadProducts() }
        guard let product = productsByID[productID] else {
            throw AppStorePurchaseError.productUnavailable
        }
        let result = try await product.purchase(options: [.appAccountToken(userID)])
        switch result {
        case .success(let verification):
            let result = try await submit(verification, accessToken: accessToken)
            guard result.entitlementStatus == "active", result.bindingState == "bound" else {
                throw AppStorePurchaseError.serverRejected
            }
            return true
        case .pending:
            throw AppStorePurchaseError.pending
        case .userCancelled:
            return false
        @unknown default:
            throw AppStorePurchaseError.unknownResult
        }
    }

    func restore(accessToken: @escaping @Sendable () async throws -> String) async throws {
        try await AppStore.sync()
        try await reconcileCurrentEntitlements(accessToken: accessToken)
    }

    func reconcileCurrentEntitlements(accessToken: @escaping @Sendable () async throws -> String) async throws {
        for await verification in Transaction.currentEntitlements {
            _ = try await submit(verification, accessToken: accessToken)
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
                    _ = try await submit(
                        verification,
                        accessToken: accessToken
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
        accessToken: @Sendable () async throws -> String
    ) async throws -> AppStoreTransactionResult {
        guard case .verified(let transaction) = verification else {
            throw AppStorePurchaseError.unverifiedTransaction
        }
        guard transaction.productID.isEmpty == false,
              CommerceCatalog.product(appStoreID: transaction.productID) != nil
        else { throw AppStorePurchaseError.productUnavailable }
        let result = try await transactions.submit(
            signedTransactionInfo: verification.jwsRepresentation,
            accessToken: accessToken
        )
        guard result.transactionId == String(transaction.id),
              result.entitlementKey == CommerceCatalog.product(appStoreID: transaction.productID)?.entitlementKey
        else {
            throw AppStorePurchaseError.serverRejected
        }
        await transaction.finish()
        return result
    }
}

enum AppStoreServiceEndpoint {
    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) -> URL? {
        try? RuntimeConfiguration.resolve(
            environment: environment,
            bundleInfo: bundle.infoDictionary ?? [:]
        ).apiBaseURL
    }
}

struct AppStoreTransactionResult: Decodable, Sendable {
    let transactionId: String
    let entitlementKey: String
    let entitlementStatus: String
    let bindingState: String
}

struct AppStoreTransactionClient: Sendable {
    let apiBaseURL: URL?
    var session: URLSession = .shared

    func submit(signedTransactionInfo: String, accessToken: @Sendable () async throws -> String) async throws -> AppStoreTransactionResult {
        guard let apiBaseURL else { throw AppStorePurchaseError.verifierNotConfigured }
        // StoreKit's purchase sheet and restore can outlive a 15-minute JWT.
        // Obtain the current SIDEY credential at each actual server submission.
        let currentToken = try await accessToken()
        var request = URLRequest(url: apiBaseURL.appending(path: "app-store/transactions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(currentToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SignedTransactionRequest(signedTransactionInfo: signedTransactionInfo))
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppStorePurchaseError.serverRejected
        }
        let result = try JSONDecoder().decode(AppStoreTransactionResult.self, from: data)
        guard ["active", "refunded", "revoked"].contains(result.entitlementStatus),
              ["bound", "unbound"].contains(result.bindingState) else {
            throw AppStorePurchaseError.serverRejected
        }
        return result
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
