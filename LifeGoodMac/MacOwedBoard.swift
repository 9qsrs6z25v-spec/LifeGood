// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.646 mac6 G2] 誰還欠我的看板數字、分頁、側欄條件（judge_mac.md §T3-3、§T3-8、§T5-3）。
//
// • 頁面 body 裡 `let now = Date()` 算一次傳下去（照 MacVariablePage:23）；這裡只收值、不寫任何 store。
// • `MacPageTheme.coral` 主控已填最終值（照抄出處）；MT 只加 `case .owed: return .coral` 一行。
// • G2：`make` 一次算看板、人卡片、組、每一列（字在建列時算好；Cell 只排版）；`sidebarShows`＝還沒還總額 ≥ 0.5 或停在這頁。

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
    /// [G2] 表格的組（點了人卡片＝只留那一組；組內照 people 的順序：日期新到舊）
    let groups: [MacOwedGroup]
    /// [G2] 點到的人（不在 people 裡＝nil＝全部）
    let person: String?
    /// [G2]「全部」卡的金額（這個分頁每個人的 total 加總）
    let allTotal: Double

    static let empty = MacOwedScreen(tab: .unpaid, summary: MacOwedSummary(), people: [], settledCount: 0, groups: [],
                                     person: nil, allTotal: 0)

    /// §T3-3（sim6: owed6#11）：看板數字、人卡片、組、還清了第三顆膠囊
    static func make(book: MacOwedBook, expenses: [Expense], tab: MacOwedTab, person: String?, now: Date,
                     calendar: Calendar) -> MacOwedScreen {
        let summary = book.summary(expenses: expenses, now: now, calendar: calendar)
        let settled: [MacOwedMeal] = book.settledMeals(expenses: expenses, now: now, calendar: calendar)
        let meals: [MacOwedMeal] = tab == .unpaid ? book.owedMeals(expenses: expenses, now: now, calendar: calendar) : settled
        let people = MacOwedBook.people(meals)
        let picked: String? = people.contains(where: { p in p.name == person }) ? person : nil
        var byID: [UUID: Expense] = [:]
        for e in expenses where byID[e.id] == nil { byID[e.id] = e }
        var groups: [MacOwedGroup] = []
        for p in people where picked == nil || p.name == picked {
            groups.append(group(p, tab: tab, expenses: byID, now: now, calendar: calendar))
        }
        let allTotal: Double = people.reduce(0) { $0 + $1.total }
        return MacOwedScreen(tab: tab, summary: summary, people: people, settledCount: settled.count, groups: groups,
                             person: picked, allTotal: allTotal)
    }

    /// 一個人一組（sim6: owed6#12 組頭＝owedPersonValue；找不到支出的那頓不出）
    static func group(_ p: MacOwedPerson, tab: MacOwedTab, expenses: [UUID: Expense], now: Date,
                      calendar: Calendar) -> MacOwedGroup {
        var rows: [MacOwedRow] = []
        for m in p.meals {
            guard let e = expenses[m.expenseID] else { continue }
            rows.append(row(m, expense: e, tab: tab, now: now, calendar: calendar))
        }
        return MacOwedGroup(id: p.name, name: p.name, headerText: MacOwedText.owedPersonValue(p),
                            avatarIndex: avatarIndex(p.name), rows: rows)
    }

    /// 字首圓的色號 0～5（sim6: owed6#18 unicodeScalars 穩定算，不用 hashValue：每次開 App 同一個人同一個色）
    static func avatarIndex(_ name: String) -> Int {
        let h: Int = name.unicodeScalars.reduce(0) { acc, u in (acc &* 31 &+ Int(u.value)) & 0xFFFF }
        return h % 6
    }

    /// 一頓一列（sim6: owed6#13 日期今年 md、不是今年 ymd；總額＝刷卡金額；狀態字；預判原因）
    static func row(_ m: MacOwedMeal, expense e: Expense, tab: MacOwedTab, now: Date, calendar: Calendar) -> MacOwedRow {
        let sameYear = calendar.component(.year, from: m.date) == calendar.component(.year, from: now)
        let dateText = sameYear ? MacOwedText.md(m.date, calendar) : MacOwedText.ymd(m.date, calendar)
        let settled = tab == .settled
        let ref = MacOwedMealRef(expenseID: m.expenseID, shareID: m.shareID,
                                 repaymentID: settled ? m.lastRepaymentID : nil, expected: m.amount)
        return MacOwedRow(id: m.id, expenseID: m.expenseID, shareID: m.shareID, date: m.date, dateText: dateText,
                          title: m.title, dot: e.variableCategory?.accentColor ?? MacPageTheme.orange.top,
                          total: e.amount, totalText: MacOwedText.ntd(e.amount), amount: m.amount,
                          amountText: MacOwedText.ntd(m.amount), days: m.days,
                          statusText: statusText(m, settled: settled, calendar: calendar),
                          late: !settled && m.days > MacOwedText.lateDays, settled: settled, ref: ref,
                          repayReason: repayReason(m, settled: settled), undoReason: undoReason(m, settled: settled))
    }

    /// 狀態欄：還沒還「今天」／「等了 N 天」；還清了 paidLine（帳戶名一律「帳戶」，不讀存摺包）
    static func statusText(_ m: MacOwedMeal, settled: Bool, calendar: Calendar) -> String {
        if settled {
            return MacOwedText.paidLine(date: m.repaidDate ?? m.date, accountName: m.account ? "帳戶" : nil, calendar: calendar)
        }
        return m.days == 0 ? "今天" : "等了 \(m.days) 天"
    }

    /// 〔已還…〕頁面預判（sim6: owed6#14；只能比寫入層的 gate 嚴或一樣：§T4-3 r1～r3）
    static func repayReason(_ m: MacOwedMeal, settled: Bool) -> String? {
        if settled { return MacSplitPatch.reasonText("already_settled") }
        if m.partial { return MacSplitPatch.reasonText("partial") }
        return nil
    }

    /// 〔改成還沒還〕頁面預判（sim6: owed6#15；§T4-3 u1、u4、u5；還沒還分頁一律不給）
    static func undoReason(_ m: MacOwedMeal, settled: Bool) -> String? {
        guard settled else { return MacSplitPatch.reasonText(m.partial ? "partial" : "already_undone") }
        if m.lastRepaymentID == nil { return MacSplitPatch.reasonText("already_undone") }
        if m.lastTouchesBank { return MacSplitPatch.reasonText("deposit") }
        if m.shareRemoved { return MacSplitPatch.reasonText("share_removed") }
        return nil
    }

    /// 組內照表頭排序（組照 people 順序不動；同值照 id 字串）（sim6: owed6#16）
    static func sorted(_ groups: [MacOwedGroup], by order: [MacOwedSort]) -> [MacOwedGroup] {
        groups.map { (g: MacOwedGroup) -> MacOwedGroup in
            let rows: [MacOwedRow] = g.rows.sorted { a, b in
                for c in order {
                    let r = c.compare(a, b)
                    if r == .orderedAscending { return true }
                    if r == .orderedDescending { return false }
                }
                return a.id < b.id
            }
            return MacOwedGroup(id: g.id, name: g.name, headerText: g.headerText, avatarIndex: g.avatarIndex, rows: rows)
        }
    }

    /// 選到的那一列與它那組的名字（名字只給表單標題、組頭；列本身沒有名字）
    static func pick(_ groups: [MacOwedGroup], id: String?) -> MacOwedPicked? {
        guard let id else { return nil }
        for g in groups {
            if let r = g.rows.first(where: { r in r.id == id }) { return MacOwedPicked(row: r, name: g.name) }
        }
        return nil
    }

    /// 側欄「誰還欠我」那一列出不出現：還沒還總額 ≥ 0.5 或目前就在這頁（停在這頁時標完最後一筆，列不會突然消失）
    static func sidebarShows(book: MacOwedBook, expenses: [Expense], page: MacPage) -> Bool {
        // sim6: owed6#17
        book.sidebarCount(expenses: expenses).shows || page == .owed
    }

    /// 側欄膠囊的人數（名字去重）
    static func sidebarPeople(book: MacOwedBook, expenses: [Expense]) -> Int {
        book.sidebarCount(expenses: expenses).people
    }
}

/// 選到的那一列＋那組的名字（只在記憶體；表單標題「王小明 還了 NT$375」用）
struct MacOwedPicked {
    let row: MacOwedRow
    let name: String
}
