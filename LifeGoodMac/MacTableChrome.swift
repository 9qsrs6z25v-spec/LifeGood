// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.648 mac7 G1a] 三頁表格的小元件（judge_mac.md §U4-1）：計數／合計膠囊、今天昨天標籤、組頭圖示圓、空狀態、表尾。
//
// • 只 import SwiftUI；每個 body 修飾器 ≤ 6、不讀 Environment（MacTableInk.init 除外，由 TableView 讀一次 colorScheme 傳進來）、
//   不加動畫、不收滑鼠（沒有 .onHover、.help(）。Cell 只收 ink、不讀。
// • 總覽不准用這些（總覽有自己的元件）。
// • 主控骨架（C0）：名字與參數定案（§U7-6）；MacTableInk 值已填；其餘 body 最簡（這版 C0 沒人用）。G1a 換內容。

import SwiftUI

/// 表格的語氣色：TableView 讀一次 colorScheme 建好、傳給欄函式；Cell 只收不讀
struct MacTableInk {
    let good: Color
    let warn: Color
    let hint: Color

    init(_ scheme: ColorScheme) {
        let p = MacPalette(scheme)
        good = MacTone.good.color(p)
        warn = MacTone.warn.color(p)
        hint = p.hint
    }
}

/// 組頭的筆數膠囊（＝MacSectionCount 的樣子；那支是 private）
struct MacTableCountPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
    }
}

/// 合計小膠囊（表尾、篩選列、變動每天組頭）
struct MacTableSumPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
    }
}

/// 「今天」「昨天」標籤
struct MacTableDayTag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
    }
}

/// 固定組頭的分類色圖示圓（18pt 實心）
struct MacTableGroupIcon: View {
    let icon: String
    let tint: Color

    var body: some View {
        Image(systemName: icon)
    }
}

/// 空狀態（大圖示圓＋原字；撐滿表格那一塊）
struct MacTableEmpty: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String?

    var body: some View {
        Text(title)
    }
}

/// 空狀態的按鈕（〔在全部裡找〕〔搜全部月份〕〔顯示已停止〕…；跟著頁面顏色）
struct MacTableEmptyButton: View {
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
    }
}

/// 表尾：上一條線＋合計膠囊＋說明（有才有）
struct MacTableFooterStrip: View {
    let text: String
    let note: String?
    let tint: Color

    var body: some View {
        Text(text)
    }
}
