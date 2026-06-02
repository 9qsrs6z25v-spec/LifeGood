import Foundation
import StoreKit
import Combine

// MARK: - Product Identifiers

enum LifeGoodProduct: String, CaseIterable {
    case monthly = "com.lifegood.premium.monthly"
    case yearly  = "com.lifegood.premium.yearly"

    var displayTitle: String {
        switch self {
        case .monthly: return "月訂閱"
        case .yearly:  return "年訂閱"
        }
    }

    var fallbackPriceText: String {
        switch self {
        case .monthly: return "NT$60 / 月"
        case .yearly:  return "NT$600 / 年"
        }
    }
}

// MARK: - Subscription Manager

final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchaseInProgress: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var entitlementExpiresAt: Date?
    @Published private(set) var entitledProductID: String?

    /// 開發 / 測試用：可在設定中強制視為已訂閱，方便沒有 sandbox 帳號時驗證
    @Published var devOverride: Bool {
        didSet {
            UserDefaults.standard.set(devOverride, forKey: Self.devOverrideKey)
        }
    }

    private static let devOverrideKey = "subscription_dev_override"

    /// 是否享有完整功能。包含：StoreKit 解鎖、開發旗標。
    var isPremium: Bool {
        if devOverride { return true }
        guard let exp = entitlementExpiresAt else { return false }
        return exp > Date()
    }

    private var transactionListener: Task<Void, Never>?

    private init() {
        self.devOverride = UserDefaults.standard.bool(forKey: Self.devOverrideKey)
        transactionListener = listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Loading

    @MainActor
    func loadProducts() async {
        do {
            let ids = LifeGoodProduct.allCases.map(\.rawValue)
            let fetched = try await Product.products(for: ids)
            self.products = fetched.sorted { lhs, rhs in
                guard let li = LifeGoodProduct.allCases.firstIndex(where: { $0.rawValue == lhs.id }),
                      let ri = LifeGoodProduct.allCases.firstIndex(where: { $0.rawValue == rhs.id })
                else { return false }
                return li < ri
            }
        } catch {
            self.lastError = "讀取商品失敗：\(error.localizedDescription)"
        }
    }

    // MARK: - Purchase

    @MainActor
    func purchase(_ product: Product) async {
        purchaseInProgress = true
        defer { purchaseInProgress = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await refreshStatus()
                await transaction.finish()
            case .userCancelled:
                break
            case .pending:
                lastError = "購買處理中，請稍候。"
            @unknown default:
                break
            }
        } catch {
            lastError = "購買失敗：\(error.localizedDescription)"
        }
    }

    @MainActor
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshStatus()
        } catch {
            lastError = "還原購買失敗：\(error.localizedDescription)"
        }
    }

    // MARK: - Entitlement

    @MainActor
    func refreshStatus() async {
        var foundID: String?
        var foundExp: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productType == .autoRenewable,
                  LifeGoodProduct.allCases.contains(where: { $0.rawValue == transaction.productID })
            else { continue }
            if transaction.revocationDate == nil {
                foundID = transaction.productID
                foundExp = transaction.expirationDate
            }
        }
        self.entitledProductID = foundID
        self.entitlementExpiresAt = foundExp
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    await self.refreshStatus()
                    await transaction.finish()
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): return value
        case .unverified(_, let error): throw error
        }
    }

    // MARK: - Convenience

    var currentPlanText: String {
        if devOverride { return "開發者模式（已解鎖）" }
        guard let id = entitledProductID,
              let p = LifeGoodProduct(rawValue: id) else { return "尚未訂閱" }
        return p.displayTitle
    }

    var expirationText: String? {
        guard let date = entitlementExpiresAt else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy/M/d"
        return "下次續訂：\(f.string(from: date))"
    }
}
