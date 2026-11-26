// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.646 mac6 G2] 誰還欠我的小元件（judge_mac.md §T3-5、§T3-8、§T3-9）：側欄那一列、人卡片、字首圓、詳情欄分帳區。
//
// • 主控骨架：`MacSidebarOwedRow(count:)` 最簡 Label（骨架時側欄不會畫它：sidebarShows 回 false）、
//   `MacOwedFactsSection(expenseID:)` 回 EmptyView()（G3a 在 MacInspector 呼叫）；G2 換內容。
// • 名字不准進 .help(、accessibilityIdentifier、log、⌘C；不加寫入按鈕。

import SwiftUI

/// 側欄「變動支出」下面縮排一列「誰還欠我」＋人數膠囊（G2：不用 .badge(、不改 MacSidebarRow）
struct MacSidebarOwedRow: View {
    let count: Int

    var body: some View {
        Label("誰還欠我", systemImage: "person.2")
    }
}

/// 詳情欄分帳區（唯讀＋〔看誰還欠我〕；只在變動支出那一路）
struct MacOwedFactsSection: View {
    let expenseID: UUID

    var body: some View {
        EmptyView()
    }
}
