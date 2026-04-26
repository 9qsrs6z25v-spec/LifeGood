import Foundation

/// 兩邊都存在但內容/時間戳不一致的支出衝突
struct ExpenseConflict: Identifiable {
    let id = UUID()
    /// 被覆蓋（採用較舊版本）的那一筆 — 可供使用者選擇還原
    let loser: Expense
    /// 勝出（採用較新版本）的那一筆
    let winner: Expense
}

/// 一次 cloud → local 合併的結果摘要
struct ExpenseMergeResult {
    let merged: [Expense]
    let added: [Expense]
    let conflicts: [ExpenseConflict]
    let unchanged: Int

    var hasUserVisibleChange: Bool { !added.isEmpty || !conflicts.isEmpty }
}
