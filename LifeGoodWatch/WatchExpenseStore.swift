import Foundation
import SwiftUI

/// 手錶端的精簡 Store：直接讀寫 iCloud Key-Value Store 的 `lifegood_expenses`。
///
/// 寫入流程（read-modify-write）：
/// 1. `synchronize()` 拉最新雲端狀態
/// 2. 解碼現有 expense 陣列
/// 3. append 本次新增
/// 4. encode 後寫回 KVS
///
/// 衝突處理：手錶只新增（每筆都有獨立 UUID），不會與其他裝置產生 id 衝突；
/// iPhone 端會在收到通知時依 `updatedAt` 處理任何邊界情況。
final class WatchExpenseStore: ObservableObject {
    private let kvStore = NSUbiquitousKeyValueStore.default
    private let key = "lifegood_expenses"

    @Published var lastSavedAt: Date?
    @Published var saveError: String?

    init() {
        kvStore.synchronize()
    }

    /// 啟動時把 KVS 的最新狀態拉一次（不會用到，但確保第一次 read-modify-write 不會基於空資料）
    func refreshFromCloud() {
        kvStore.synchronize()
    }

    @discardableResult
    func add(_ expense: WatchExpense) -> Bool {
        kvStore.synchronize()

        var current = decodeCurrent()
        current.append(expense)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        guard let data = try? encoder.encode(current) else {
            saveError = "編碼失敗"
            return false
        }
        kvStore.set(data, forKey: key)
        let ok = kvStore.synchronize()
        if ok {
            lastSavedAt = Date()
            saveError = nil
        } else {
            saveError = "iCloud 同步失敗"
        }
        return ok
    }

    private func decodeCurrent() -> [WatchExpense] {
        guard let data = kvStore.data(forKey: key) else { return [] }
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([WatchExpense].self, from: data) {
            return list
        }
        return []
    }
}
