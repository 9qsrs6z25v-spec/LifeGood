// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.646 mac6 G2] 誰還欠我的看板數字、分頁、側欄條件（judge_mac.md §T3-3、§T3-8、§T5-3）。
//
// • 頁面 body 裡 `let now = Date()` 算一次傳下去（照 MacVariablePage:23）；這裡只收值、不寫任何 store。
// • `MacPageTheme.coral` 主控已填最終值（照抄出處）；MT 只加 `case .owed: return .coral` 一行。
// • 主控骨架：`MacOwedScreen.make` 回空、`sidebarShows` 回 false、`sidebarPeople` 回 0（側欄那一列不出現＝畫面跟 25.645 一樣）；G2 換內容。

import SwiftUI

// MARK: - 頁色

extension MacPageTheme {
    // 照抄 HeroStyleKit.swift:377-380（258fea0）；tint 取 bottom：top 跟變動支出的橘太像
    static let coral = MacPageTheme(top: Color(red: 1.00, green: 0.58, blue: 0.28),
                                    bottom: Color(red: 0.90, green: 0.28, blue: 0.55),
                                    tint: Color(red: 0.90, green: 0.28, blue: 0.55))
}

// MARK: - 分頁

/// 〔還沒還｜還清了（最近 90 天）〕
enum MacOwedTab: Hashable {
    case unpaid, settled
}

// MARK: - 一頁要畫的東西（一次算好；名字只在畫面）

struct MacOwedScreen {
    let tab: MacOwedTab
    /// 看板（兩個分頁都顯示還沒還的總數，照 iPhone OLV:80）
    let summary: MacOwedSummary
    /// 這個分頁的人（卡片、組的順序）
    let people: [MacOwedPerson]
    /// 還清了分頁第三顆膠囊「最近 90 天還清 N 筆」
    let settledCount: Int

    static let empty = MacOwedScreen(tab: .unpaid, summary: MacOwedSummary(), people: [], settledCount: 0)

    /// §T3-3（sim6: owed6#…）。主控骨架：空
    static func make(book: MacOwedBook, expenses: [Expense], tab: MacOwedTab, person: String?, now: Date,
                     calendar: Calendar) -> MacOwedScreen {
        MacOwedScreen(tab: tab, summary: MacOwedSummary(), people: [], settledCount: 0)
    }

    /// 側欄「誰還欠我」那一列出不出現：還沒還總額 ≥ 0.5 或目前就在這頁（G2：sidebarCount(expenses:).shows || page == .owed）。
    /// 主控骨架：false（不出現）
    static func sidebarShows(book: MacOwedBook, expenses: [Expense], page: MacPage) -> Bool {
        false
    }

    /// 側欄膠囊的人數（名字去重）。主控骨架：0
    static func sidebarPeople(book: MacOwedBook, expenses: [Expense]) -> Int {
        0
    }
}
