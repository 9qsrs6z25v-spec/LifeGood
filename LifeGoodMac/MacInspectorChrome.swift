// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.646 mac6 G3a] 詳情欄的新標頭與空狀態（judge_mac.md §T5-1）：分類色圖示圓＋名稱＋一行小字；沒選東西時跟著頁面顏色的提示。
//
// • 三種共用 `MacInspectorHeader(info:)`（變動支出、收入：MacInspector；固定支出：MacFixedPage 的 MacFixedFactsSection，G3c）。
// • 不讀 colorScheme、不加動畫、修飾器 ≤ 3；不加 .macCard、.macBoard、.macAppear、.textSelection。
// • 主控骨架：三個 struct 最簡 body、`MacInspectorHeaderInfo` 三支 static 簡單值（還沒有人呼叫：MI 這版 G3a 才改）；G3a 換內容。

import SwiftUI

/// 標頭要畫的東西
struct MacInspectorHeaderInfo {
    /// 空＝「（沒有名稱）」
    let title: String
    /// 「變動支出・飲食」「收入・薪水」「固定支出・房租」
    let detail: String
    let icon: String
    let tint: Color

    /// 變動支出（G3a：variableCategory → icon、accentColor；nil → "cart.fill"、MacPageTheme.orange.top；
    /// detail「變動支出・」＋macDisplayCategoryName(kinds: money.kindIndex)）。主控骨架：簡單值
    @MainActor
    static func expense(_ e: Expense, money: MacMoneyStore) -> MacInspectorHeaderInfo {
        MacInspectorHeaderInfo(title: e.title.isEmpty ? "（沒有名稱）" : e.title, detail: "", icon: "cart.fill",
                               tint: MacPageTheme.orange.top)
    }

    /// 收入（G3a：category.icon、category.macTint、「收入・」＋rawValue）。主控骨架：簡單值
    static func income(_ i: Income) -> MacInspectorHeaderInfo {
        MacInspectorHeaderInfo(title: i.title.isEmpty ? "（沒有名稱）" : i.title, detail: "", icon: "cart.fill",
                               tint: MacPageTheme.green.top)
    }

    /// 固定支出（G3a／G3c：MacFixedGroupKey.of(e, kinds:) → macIcon、macTint、「固定支出・」＋title）。主控骨架：簡單值
    @MainActor
    static func fixed(_ e: Expense, money: MacMoneyStore) -> MacInspectorHeaderInfo {
        MacInspectorHeaderInfo(title: e.title.isEmpty ? "（沒有名稱）" : e.title, detail: "", icon: "cart.fill",
                               tint: MacPageTheme.blue.top)
    }
}

/// 詳情欄最上面（Section header 用）
struct MacInspectorHeader: View {
    let info: MacInspectorHeaderInfo

    var body: some View {
        Text(info.title)
            .font(.headline)
    }
}

/// 沒選東西（G3a：MacEmptyHint，跟著 page.theme.tint）
struct MacInspectorEmpty: View {
    let page: MacPage

    var body: some View {
        Text("選一筆看詳情")
    }
}
