// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.646 mac6 G3a] 詳情欄的新標頭與空狀態（judge_mac.md §T5-1）：分類色圖示圓＋名稱＋一行小字；沒選東西時跟著頁面顏色的提示。
//
// • 三種共用 `MacInspectorHeader(info:)`（變動支出、收入：MacInspector；固定支出：MacFixedPage 的 MacFixedFactsSection，G3c）。
// • 不讀 colorScheme、不加動畫、修飾器 ≤ 3；不加 .macCard、.macBoard、.macAppear、.textSelection。
// • 只看、不寫：這檔不碰任何 store 的寫入、不碰分帳（分帳區是 MacOwedCells 的 MacOwedFactsSection，MI 只放位置）。
// • 參考答案：build/mac6/sim6_inspector.py（sim_mac6 的 inspector6；圖示、色、detail 對照表）。

import SwiftUI

/// 標頭要畫的東西
struct MacInspectorHeaderInfo {
    /// 空＝「（沒有名稱）」
    let title: String
    /// 「變動支出・飲食」「收入・薪水」「固定支出・房租」
    let detail: String
    let icon: String
    let tint: Color

    /// 變動支出：variableCategory → icon、accentColor；nil → "cart.fill"、MacPageTheme.orange.top；
    /// detail「變動支出・」＋macDisplayCategoryName(kinds: money.kindIndex)（跟下面「分類」那列同一支字）
    @MainActor
    static func expense(_ e: Expense, money: MacMoneyStore) -> MacInspectorHeaderInfo {
        // sim6: inspector6#3 detail＝「變動支出・」＋細項說法（「汽車 - 罰款」「稅費・…」；沒有細項＝categoryName）
        let detail: String = "變動支出・" + e.macDisplayCategoryName(kinds: money.kindIndex)
        let title: String = titleText(e.title)
        // sim6: inspector6#1 有分類：圖示＝VariableCategory.icon、色＝VariableCategory.accentColor（14 類，Expense.swift 共用）
        if let c = e.variableCategory {
            return MacInspectorHeaderInfo(title: title, detail: detail, icon: c.icon, tint: c.accentColor)
        }
        // sim6: inspector6#2 沒有分類：購物車＋變動支出頁的橘
        return MacInspectorHeaderInfo(title: title, detail: detail, icon: "cart.fill", tint: MacPageTheme.orange.top)
    }

    /// 收入：category.icon、category.macTint、「收入・」＋rawValue
    static func income(_ i: Income) -> MacInspectorHeaderInfo {
        // sim6: inspector6#4 圖示＝IncomeCategory.icon、色＝IncomeCategory.macTint（MacTheme，5 類）、detail「收入・」＋rawValue
        let c: IncomeCategory = i.category
        return MacInspectorHeaderInfo(title: titleText(i.title), detail: "收入・" + c.rawValue, icon: c.icon, tint: c.macTint)
    }

    /// 固定支出（G3c 在 MacFixedPage 呼叫）：MacFixedGroupKey.of(e, kinds:) → macIcon、macTint、「固定支出・」＋title
    @MainActor
    static func fixed(_ e: Expense, money: MacMoneyStore) -> MacInspectorHeaderInfo {
        // sim6: inspector6#5 跟固定支出頁表格同一個分組（8 類＋稅費）：圖示＝macIcon、色＝macTint、detail「固定支出・」＋組名
        let key: MacFixedGroupKey = MacFixedGroupKey.of(e, kinds: money.kindIndex)
        return MacInspectorHeaderInfo(title: titleText(e.title), detail: "固定支出・" + key.title, icon: key.macIcon,
                                      tint: key.macTint)
    }

    /// sim6: inspector6#6 名稱是空字串＝「（沒有名稱）」（跟 Mac 5 詳情欄 header 同一個判斷、同一句）
    private static func titleText(_ raw: String) -> String {
        raw.isEmpty ? "（沒有名稱）" : raw
    }
}

/// 詳情欄最上面（Section header 用）：28pt 實心分類色圓＋名稱（headline，最多兩行）＋一行小字（caption 灰）
/// sim6: inspector6#7 樣子固定：圓 top＝tint、bottom＝tint@0.75、size 28、solid；不讀 colorScheme、不動畫
struct MacInspectorHeader: View {
    let info: MacInspectorHeaderInfo

    var body: some View {
        HStack(spacing: 10) {
            MacIconBadge(icon: info.icon, top: info.tint, bottom: info.tint.opacity(0.75), size: 28, solid: true)
            MacInspectorHeaderText(title: info.title, detail: info.detail)
        }
        .padding(.bottom, 2)
    }
}

/// 標頭右邊兩行字（拆出來：body 短、修飾器 ≤ 3）
private struct MacInspectorHeaderText: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .lineLimit(2)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// 沒選東西：MacEmptyHint，跟著 page.theme.tint（誰還欠我頁粉珊瑚、圖表頁夜空藍）；字跟 Mac 5 一樣
/// sim6: inspector6#8 圖示 hand.point.up.left、標題「選一筆看詳情」、說明「在列表點一筆」、色＝那一頁的 theme.tint
struct MacInspectorEmpty: View {
    let page: MacPage

    var body: some View {
        MacEmptyHint(icon: "hand.point.up.left", tint: page.theme.tint, title: "選一筆看詳情", detail: "在列表點一筆")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
