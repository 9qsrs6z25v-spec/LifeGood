import Foundation
import SwiftUI

/// 管理 Apple Watch 端透過 iCloud 推送進來的支出，以便 iPhone App 內顯示通知並讓使用者選擇處理。
final class WatchSyncCoordinator: ObservableObject {
    static let shared = WatchSyncCoordinator()

    /// 來自手錶的新增支出 — 待使用者確認
    @Published var pendingAdditions: [Expense] = []
    /// 與本機衝突、已自動以較新時間戳取代的紀錄 — 提供「還原本機版本」選項
    @Published var pendingConflicts: [ExpenseConflict] = []

    /// 是否有任何項目需要 UI 提示
    var hasPending: Bool { !pendingAdditions.isEmpty || !pendingConflicts.isEmpty }

    private init() {}

    /// CloudSyncManager 在合併後呼叫，把新增 / 衝突項記入待處理清單。
    /// 只記錄「來自其他裝置」的項目（sourceDevice != iphone）以避免自我提示。
    func record(result: ExpenseMergeResult) {
        let watchAdds = result.added.filter { $0.sourceDevice != "iphone" }
        if !watchAdds.isEmpty {
            DispatchQueue.main.async {
                self.pendingAdditions.append(contentsOf: watchAdds)
            }
        }
        if !result.conflicts.isEmpty {
            DispatchQueue.main.async {
                self.pendingConflicts.append(contentsOf: result.conflicts)
            }
        }
    }

    func dismissAddition(_ expense: Expense) {
        pendingAdditions.removeAll { $0.id == expense.id }
    }

    func dismissAllAdditions() {
        pendingAdditions.removeAll()
    }

    func dismissConflict(_ conflict: ExpenseConflict) {
        pendingConflicts.removeAll { $0.id == conflict.id }
    }

    func dismissAllConflicts() {
        pendingConflicts.removeAll()
    }
}
