// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.642 mac3] 細項 Lite（只顯示）：照抄 ExpenseKinds.swift 讀的那幾支（judge_mac §Q7 ⑭）。
// 總設計先放骨架（§Q9 名稱表）：G3 整檔改寫；簽名不准改（G2 叫 MacKindIndex.empty、init(data:)、kind(of:)、
// Expense.macDisplayCategoryName(kinds:)）。骨架行為＝沒有細項（分類照 categoryName），G3 拿掉也編得過。
import Foundation

struct MacKindIndex {
    static let empty = MacKindIndex(data: nil)

    init(data: Data?) {}

    /// 這筆的細項字（沒有＝nil）
    func kind(of e: Expense) -> String? { nil }
}

extension Expense {
    /// 「汽車 - 罰款」「稅費・地價稅」；沒有細項照 categoryName
    func macDisplayCategoryName(kinds: MacKindIndex) -> String { categoryName }
}
