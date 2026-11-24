// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.640 mac1] 右邊的詳情（brief.md §G2-8、judge_mac.md §F1、§O6）：選到的那一筆。
// 金額、分類（categoryName）、日期、備註、付款（只寫「信用卡／銀行／不指定」，不顯示卡號、帳號）；
// 下面放 G3 的 MacInspectorEditSection(ref:)（每欄能不能改＋原因、〔編輯〕〔刪除〕）。

import SwiftUI

struct MacInspector: View {
    @EnvironmentObject private var ui: MacUIState

    var body: some View {
        Group {
            if let ref = ui.selection {
                MacInspectorBody(ref: ref)
            } else {
                ContentUnavailableView("選一筆看詳情", systemImage: "sidebar.right",
                                       description: Text("在列表點一筆"))
            }
        }
        .inspectorColumnWidth(min: 240, ideal: 290, max: 400)
    }
}

fileprivate struct MacInspectorBody: View {
    let ref: MacEntryRef
    @EnvironmentObject private var money: MacMoneyStore

    var body: some View {
        Form {
            MacInspectorFacts(ref: ref, money: money)
            MacInspectorEditSection(ref: ref)
        }
        .formStyle(.grouped)
    }
}

/// 這筆的內容（找不到＝在別台刪掉了，或還沒讀到）
fileprivate struct MacInspectorFacts: View {
    let ref: MacEntryRef
    @ObservedObject var money: MacMoneyStore

    var body: some View {
        switch ref {
        case .expense(let id):
            if let e = money.expense(id) {
                MacExpenseFacts(rows: MacInspectorRows.expense(e, money: money), title: e.title)
            } else {
                MacMissingFacts()
            }
        case .income(let id):
            if let i = money.income(id) {
                MacExpenseFacts(rows: MacInspectorRows.income(i), title: i.title)
            } else {
                MacMissingFacts()
            }
        }
    }
}

fileprivate struct MacExpenseFacts: View {
    let rows: [MacInspectorRow]
    let title: String

    var body: some View {
        Section {
            ForEach(rows) { row in
                LabeledContent(row.label, value: row.value)
            }
        } header: {
            Text(title.isEmpty ? "（沒有名稱）" : title)
                .font(.headline)
        }
    }
}

fileprivate struct MacMissingFacts: View {
    var body: some View {
        Section {
            Text("這筆已經不在了（可能在 iPhone 刪掉了）。按 ⌘R 重新讀取。")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 一列一列的字

fileprivate struct MacInspectorRow: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

fileprivate enum MacInspectorRows {
    @MainActor
    static func expense(_ e: Expense, money: MacMoneyStore) -> [MacInspectorRow] {
        var rows: [MacInspectorRow] = []
        rows.append(MacInspectorRow(label: "金額", value: MacText.exactMoney(money.ntdValue(of: e))))
        if e.expenseType == .variable, money.splitIndex.liveShares(for: e) != nil {
            rows.append(MacInspectorRow(label: "你自己那份", value: MacText.exactMoney(money.ownAmount(e))))
        }
        if !isNTD(e.currencyCode) {
            rows.append(MacInspectorRow(label: "記的幣別", value: e.currencyCode))
        }
        rows.append(MacInspectorRow(label: "類型", value: typeText(e)))
        rows.append(MacInspectorRow(label: "分類", value: e.categoryName))
        rows.append(MacInspectorRow(label: e.expenseType == .fixed ? "起始日" : "日期", value: dateText(e)))
        if e.expenseType == .fixed, let end = e.endDate {
            rows.append(MacInspectorRow(label: "結束日", value: MacText.fullDay(end)))
        }
        rows.append(MacInspectorRow(label: "付款", value: paymentText(e)))
        rows.append(MacInspectorRow(label: "備註", value: e.note.isEmpty ? "—" : e.note))
        return rows
    }

    static func income(_ i: Income) -> [MacInspectorRow] {
        var rows: [MacInspectorRow] = []
        rows.append(MacInspectorRow(label: "金額", value: MacText.exactMoney(i.amount)))
        rows.append(MacInspectorRow(label: "分類", value: i.category.rawValue))
        rows.append(MacInspectorRow(label: "週期", value: periodText(i)))
        rows.append(MacInspectorRow(label: i.period == .once ? "日期" : "起始日", value: MacText.fullDay(i.date)))
        // [v25.641 mac2] 有結束日就列（不限週期）：「2026/12/31（離職）」
        if let end = i.endDate {
            rows.append(MacInspectorRow(label: "結束", value: endText(end, reason: i.endReason)))
        }
        // [v25.641 mac2] 入帳跟收入頁表格同一支字（「連著銀行」「連結股票」「—」）
        rows.append(MacInspectorRow(label: "入帳", value: MacIncomeTable.bankText(i)))
        rows.append(MacInspectorRow(label: "備註", value: i.note.isEmpty ? "—" : i.note))
        return rows
    }

    private static func isNTD(_ code: String) -> Bool {
        code == "NT$" || code == "TWD" || code.isEmpty
    }

    private static func typeText(_ e: Expense) -> String {
        guard e.expenseType == .fixed else { return "變動支出" }
        guard let r = e.recurrence else { return "固定支出" }
        return "固定支出（" + r.rawValue + "）"
    }

    private static func dateText(_ e: Expense) -> String {
        e.expenseType == .variable ? MacText.fullDayTime(e.date) : MacText.fullDay(e.date)
    }

    /// 只寫哪一種，不顯示卡號、帳號（judge_mac.md §O7）
    private static func paymentText(_ e: Expense) -> String {
        if e.linkedCreditCardMilestoneId != nil { return "信用卡" }
        if e.linkedBankMilestoneId != nil { return "銀行" }
        return "不指定"
    }

    /// 「2026/12/31（離職）」；沒有原因只寫日期
    private static func endText(_ end: Date, reason: SalaryEndReason?) -> String {
        guard let reason else { return MacText.fullDay(end) }
        return MacText.fullDay(end) + "（" + reason.rawValue + "）"
    }

    private static func periodText(_ i: Income) -> String {
        if i.period == .once { return "單次" }
        return i.isFixedSalary ? i.period.rawValue + "（固定薪水）" : i.period.rawValue
    }
}
