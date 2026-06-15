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

    /// 遠端「全功能免費」總開關（由 RemoteAdminManager 套用，預設 true）
    @Published private(set) var remoteAllFree: Bool

    private static let devOverrideKey = "subscription_dev_override"
    private static let remoteAllFreeKey = "ra_all_free"
    private static let founderKey = "subscription_founder_unlocked"
    private static let expirationDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()

    /// 是否享有完整功能：開發旗標 / 早鳥永久解鎖 / 遠端全免費 / 有效訂閱
    var isPremium: Bool {
        if devOverride { return true }
        if isFounderUnlocked { return true }
        if remoteAllFree { return true }
        guard let exp = entitlementExpiresAt else { return false }
        return exp > Date()
    }

    /// 早鳥永久解鎖標記（本機 + iCloud KV，重裝 / 換機保留）
    var isFounderUnlocked: Bool {
        UserDefaults.standard.bool(forKey: Self.founderKey)
            || NSUbiquitousKeyValueStore.default.bool(forKey: Self.founderKey)
    }

    /// 由 RemoteAdminManager 在「伺服器確認」免費狀態後呼叫。
    /// 免費中 → 蓋早鳥章（日後收回時這些早期使用者永久保留解鎖）。
    func applyRemoteFreeAccess(_ free: Bool) {
        UserDefaults.standard.set(free, forKey: Self.remoteAllFreeKey)
        remoteAllFree = free
        if free, !isFounderUnlocked {
            UserDefaults.standard.set(true, forKey: Self.founderKey)
            NSUbiquitousKeyValueStore.default.set(true, forKey: Self.founderKey)
            NSUbiquitousKeyValueStore.default.synchronize()
        }
        // 移除多餘的 objectWillChange.send()：
        // @Published var remoteAllFree 的 willSet 已自動發送 objectWillChange，
        // 重複手動呼叫會觸發第二次 SwiftUI 更新週期，造成不必要的重繪。
    }

    private var transactionListener: Task<Void, Never>?

    private init() {
        self.devOverride = UserDefaults.standard.bool(forKey: Self.devOverrideKey)
        // 預設全功能免費（在伺服器回覆前先採樂觀值，避免免費期間短暫被鎖）
        self.remoteAllFree = UserDefaults.standard.object(forKey: Self.remoteAllFreeKey) as? Bool ?? true
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
                // 保留到期日最晚的訂閱，避免升級後舊方案覆蓋新方案的 expirationDate
                if let existingExp = foundExp, let newExp = transaction.expirationDate {
                    if newExp > existingExp {
                        foundID = transaction.productID
                        foundExp = newExp
                    }
                } else {
                    foundID = transaction.productID
                    foundExp = transaction.expirationDate
                }
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
        return "下次續訂：\(Self.expirationDateFormatter.string(from: date))"
    }
}
