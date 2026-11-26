// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.648 mac7 G2] 總覽看板、這個月的錢橫條、未來 7 天要扣、分類卡（judge_mac.md §U3-3、§U3-5、§U3-6）。
//
// • 只畫：數字與字一律由 MacOverviewBoard.swift 算好（MacOverviewBoardText）；body 不寫 store、不寫 UserDefaults、不寫 log。
// • edit 只准 requestEdit（未來 7 天要扣點一筆）；ui 只准寫 page、variableMonth、variableCategoryRequest（分類卡跳頁、四格切頁）。
// • MacMoneyBar 照抄 OverviewBoard.swift:422-503（d070244）MoneySplitBar：全 LifeGoodMac 第二個 Canvas，不畫字（不准 ctx.resolve(、ctx.draw(）。
// • 修飾器鏈 ≤ 8（超過拆小 struct）；不准 AnyView、LazyVGrid、GeometryReader、withAnimation、.transition(、.macAppear(。
// • 主控骨架（C0）：五個 View 的名字與參數定案（§U7-6）；body 最簡（這版 C0 沒人用）。G2 換內容。

import SwiftUI

/// §U3-3 總覽看板（.macBoard(.green)）
struct MacOverviewHeroBoard: View {
    let data: MacOverviewBoardData

    var body: some View {
        EmptyView()
    }
}

/// §U3-5 未來 7 天要扣（.macBoard(.blue)；bills 空的不畫）
struct MacOverviewUpcomingCard: View {
    let bills: [MacOverviewBill]

    var body: some View {
        EmptyView()
    }
}

/// §U3-6 本月花在哪裡的分類卡（3 欄 Grid；點一張跳變動支出只看那一類）
struct MacOverviewCategoryCards: View {
    let stats: [MacOverviewCategoryStat]

    var body: some View {
        EmptyView()
    }
}

/// 「本月還能花」大字（＝MacHeroNumber 同字型；tone 有值時 MacTone 色、沒有時 ink）
struct MacOverviewBigNumber: View {
    let text: String
    let value: Double
    let tone: MacOverviewTone?

    var body: some View {
        Text(text)
    }
}

// 照抄 OverviewBoard.swift:422-503（d070244）MoneySplitBar（Color(tb:) → MacTheme.hex）— G2 換 body
/// 這個月的錢：固定（紫）＋變動（藍）＋照平常的花法到月底還會花的那一段（斜線），收入是一道刻度
struct MacMoneyBar: View, Equatable {
    let fixed: Double
    let variable: Double
    /// 月底預估的總支出（已經花的也算在裡面）
    let projected: Double
    let income: Double?
    let dark: Bool

    static func fixedInk(dark: Bool) -> Color { dark ? MacTheme.hex(0xA98BFF) : MacTheme.hex(0x8B5CF6) }
    static func variableInk(dark: Bool) -> Color { dark ? MacTheme.hex(0x5B9BFF) : MacTheme.hex(0x2F6FE0) }

    var body: some View {
        Color.clear
    }
}
