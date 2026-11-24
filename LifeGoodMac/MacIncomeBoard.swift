// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.641 mac2 G2] 收入頁的數字與表格列（只 import Foundation；brief.md §2 G2 第 1～4 條、judge_mac.md §P7、§P8）。
//
// • ④⑤⑥⑧ 一支一支照抄 iOS（88bb518），只准 Date()→now、Calendar.current→calendar、store.→money.、
//   HeroTrendPoint→MacIncomePoint、private 增減、多傳 now:／calendar:；看板一次算完傳同一個 now。
// • 表格列（MacIncomeRow）全 let，顯示字建列時算好；排序自己寫（不用 Foundation 的排序 API），同值照 id。
// • 這個檔不寫 store、不碰 records、不讀帳本／存摺。

import Foundation

// MARK: - 型別

/// ⑤ 的一個點（iOS 的 HeroTrendPoint 是 iOS 檔，Mac 不編）
struct MacIncomePoint {
    let month: Date
    let value: Double
}

/// 長條一根（label「11月」；最後一根＝這個月）
struct MacIncomeBar: Identifiable, Equatable {
    let id: Int
    let label: String
    let amount: Double
    let isCurrent: Bool
}

/// ⑧ IncomeBoardData（欄位名照 iOS；peaks 換成 bars）
struct MacIncomeBoardData: Equatable {
    var year = 2026
    var month = 1
    /// 本月已入帳（①）
    var income: Double = 0
    /// 近 6 個月中位數（④）
    var median: Double = 0
    /// 今年累計（③）
    var yearToDate: Double = 0
    /// 固定月收（還在領的週期收入換成每月）
    var recurringMonthly: Double = 0
    /// 近 6 個月，一個月一根（最後一根是這個月）
    var bars: [MacIncomeBar] = []
    /// 下一次固定收入入帳的日子
    var nextPay: Date? = nil
    /// 上個月存下收入的幾成（負的＝花得比收入多）；上個月沒有收入是 nil
    var lastMonthSaving: Double? = nil
    var lastMonthShort: Double = 0
}

extension MacMoneyStore {
    // 照抄 ExpenseStore.swift:290-308（88bb518）estimatedMonthlyIncome — sim2: stats#4
    func estimatedMonthlyIncome(now: Date, calendar: Calendar) -> Double {
        var monthlyTotals: [Double] = []
        for i in 1...6 {
            guard let monthDate = calendar.date(byAdding: .month, value: -i, to: now) else { continue }
            let total = incomeTotal(for: monthDate, now: now, calendar: calendar)
            if total > 0 { monthlyTotals.append(total) }
        }

        guard !monthlyTotals.isEmpty else { return 0 }
        let sorted = monthlyTotals.sorted()
        let count = sorted.count
        if count % 2 == 0 {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2
        }
        return sorted[count / 2]
    }

    // 照抄 ExpenseStore.swift:369-371（88bb518）fixedMonthlyTotal(for:) — sim2: stats#6
    func fixedMonthlyTotal(for date: Date, calendar: Calendar) -> Double {
        projectedFixedTotal(for: date, period: .monthly, calendar: calendar)
    }

    // 照抄 ExpenseStore.swift:658-662（88bb518）heroIncomeSeries — sim2: stats#5
    func incomeSeries(now: Date, calendar: Calendar) -> [MacIncomePoint] {
        monthlyHeroSeries(firstDate: incomes.map(\.date).min(), now: now, calendar: calendar) { monthStart, _ in
            incomeTotal(for: monthStart, now: now, calendar: calendar)
        }
    }

    // 照抄 ExpenseStore.swift:688-708（88bb518）monthlyHeroSeries
    private func monthlyHeroSeries(firstDate: Date?, now: Date, calendar: Calendar,
                                   valueFor: (Date, Date) -> Double) -> [MacIncomePoint] {
        guard let firstDate else { return [] }
        let cal = calendar
        guard let currentMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)),
              let firstMonth = cal.date(from: cal.dateComponents([.year, .month], from: firstDate)) else {
            return []
        }
        let monthsBetween = cal.dateComponents([.month], from: firstMonth, to: currentMonth).month ?? 0
        let count = min(monthsBetween + 1, 480)
        guard count >= 1 else { return [] }
        var out: [MacIncomePoint] = []
        for back in stride(from: count - 1, through: 0, by: -1) {
            guard let monthStart = cal.date(byAdding: .month, value: -back, to: currentMonth) else { continue }
            let nextMonth = cal.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
            let monthEnd = min(nextMonth.addingTimeInterval(-1), now)
            out.append(MacIncomePoint(month: monthStart, value: valueFor(monthStart, monthEnd)))
        }
        return out
    }
}

enum MacIncomeBoard {
    // 照抄 MoneyBoards.swift:373-439（88bb518）IncomeBoardData.build — sim2: stats#8
    @MainActor
    static func build(money: MacMoneyStore, now: Date, calendar: Calendar) -> MacIncomeBoardData {
        let cal = calendar
        var d = MacIncomeBoardData()
        d.year = cal.component(.year, from: now)
        d.month = cal.component(.month, from: now)
        d.income = money.currentMonthIncomeTotal(now: now, calendar: calendar)
        d.median = money.estimatedMonthlyIncome(now: now, calendar: calendar)
        d.yearToDate = money.yearToDateIncomeTotal(now: now, calendar: calendar)
        d.recurringMonthly = money.incomes
            .filter { $0.period != .once && $0.isActive(in: now, calendar: calendar) }
            .reduce(0) { $0 + $1.monthlyAmount }

        let series = money.incomeSeries(now: now, calendar: calendar)
        d.bars = MacIncomeBoard.bars(Array(series.suffix(6)), calendar: calendar)

        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) else { return d }
        let today = cal.startOfDay(for: now)

        // 下次入帳：還在領的固定收入，照起始日的「幾號」（年領的是「幾月幾號」）往後找最近的一天
        for i in money.incomes where i.period != .once && i.monthlyAmount > 0 && i.isActive(in: now, calendar: calendar) {
            let payDay = cal.component(.day, from: i.date)
            let payMonth = cal.component(.month, from: i.date)
            var candidates: [Date] = []
            for add in 0...1 {
                var comps = DateComponents()
                switch i.period {
                case .monthly:
                    guard let m = cal.date(byAdding: .month, value: add, to: monthStart) else { continue }
                    comps = cal.dateComponents([.year, .month], from: m)
                case .yearly:
                    comps.year = d.year + add
                    comps.month = payMonth
                case .once:
                    continue
                }
                comps.day = 1
                guard let first = cal.date(from: comps) else { continue }
                let days = cal.range(of: .day, in: .month, for: first)?.count ?? 28
                comps.day = min(payDay, days)
                if let date = cal.date(from: comps) { candidates.append(date) }
            }
            let start = cal.startOfDay(for: i.date)
            let end = i.endDate.map { cal.startOfDay(for: $0) }
            guard let next = candidates.filter({ c in
                c >= today && c >= start && (end.map { c <= $0 } ?? true)
            }).min() else { continue }
            if d.nextPay.map({ next < $0 }) ?? true { d.nextPay = next }
        }

        // 上個月存下幾成：上個月的收入 −（變動支出＋固定支出月等值）
        if series.count >= 2, let lastStart = cal.date(byAdding: .month, value: -1, to: monthStart) {
            let lastIncome = series[series.count - 2].value
            if lastIncome > 0 {
                let lastVariable = money.expenses
                    .filter { $0.expenseType == .variable && $0.date >= lastStart && $0.date < monthStart }
                    .reduce(0) { $0 + money.ownAmount($1) }
                let lastFixed = money.fixedMonthlyTotal(for: monthStart.addingTimeInterval(-1), calendar: calendar)
                let saved = lastIncome - lastVariable - lastFixed
                d.lastMonthSaving = saved / lastIncome
                d.lastMonthShort = max(0, -saved)
            }
        }
        return d
    }
}

extension MacIncomeBoard {
    /// ⑤ 後 6 點 → 長條（標籤「N月」，照 MoneyBoards.swift:385-388；最後一根＝這個月）
    static func bars(_ points: [MacIncomePoint], calendar: Calendar) -> [MacIncomeBar] {
        var out: [MacIncomeBar] = []
        for (k, p) in points.enumerated() {
            let label = "\(calendar.component(.month, from: p.month))月"
            out.append(MacIncomeBar(id: k, label: label, amount: p.value, isCurrent: k == points.count - 1))
        }
        return out
    }
}

// MARK: - ⑨ 看板的字（MoneyBoards.swift:441-513；英文招呼不抄）

/// 膠囊一顆（good：true＝綠、false＝紅、nil＝一般）
struct MacIncomeChip: Identifiable {
    let icon: String
    let label: String
    let value: String
    let good: Bool?
    var id: String { label }
}

enum MacIncomeHeadline {
    private static let payFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d"
        return f
    }()

    /// 「2026 年 11 月」
    static func monthTitle(_ d: MacIncomeBoardData) -> String {
        "\(d.year) 年 \(d.month) 月"
    }

    /// ahead（中位數 > 本月已入帳）時的預期（長條的半透明那段、虛線）
    static func expected(_ d: MacIncomeBoardData) -> Double? {
        d.median > d.income ? d.median : nil
    }

    /// 一句話（MoneyBoards.swift:475-487；「一個月畫一座山」改「一個月一根」）— sim2: stats#9
    static func line(_ d: MacIncomeBoardData) -> String {
        if d.median > d.income {
            return "預期 " + WidgetMoneyFormat.short(d.median) + "（近 6 個月中位數）"
        }
        if d.median > 0 {
            let r = d.income / d.median - 1
            if abs(r) < 0.01 { return "跟近 6 個月中位數差不多" }
            return "比近 6 個月中位數多 " + WidgetMoneyFormat.percent(r)
        }
        return d.income > 0 ? "這是第一個有收入紀錄的月份" : "記下收入之後，這裡會一個月一根"
    }

    /// 膠囊（順序、出現條件照 MoneyBoards.swift:489-512）— sim2: stats#9
    static func chips(_ d: MacIncomeBoardData, now: Date, calendar: Calendar) -> [MacIncomeChip] {
        var out: [MacIncomeChip] = []
        if d.median > 0 {
            out.append(MacIncomeChip(icon: "chart.bar.fill", label: "近 6 月中位數",
                                     value: WidgetMoneyFormat.short(d.median), good: nil))
        }
        if d.recurringMonthly > 0 {
            out.append(MacIncomeChip(icon: "repeat", label: "固定月收",
                                     value: WidgetMoneyFormat.short(d.recurringMonthly), good: nil))
        }
        if let next = d.nextPay {
            let value = calendar.isDate(next, inSameDayAs: now) ? "今天" : payFmt.string(from: next)
            out.append(MacIncomeChip(icon: "calendar.badge.clock", label: "下次入帳", value: value, good: nil))
        }
        if let rate = d.lastMonthSaving {
            if rate >= 0 {
                out.append(MacIncomeChip(icon: "leaf.fill", label: "上月存下",
                                         value: WidgetMoneyFormat.percent(rate), good: true))
            } else {
                out.append(MacIncomeChip(icon: "exclamationmark.triangle.fill", label: "上月透支",
                                         value: WidgetMoneyFormat.short(d.lastMonthShort), good: false))
            }
        }
        return out
    }

    /// 長條的 VoiceOver 摘要：「近 6 個月收入：6月 NT$8.5萬、…」
    static func chartSummary(_ d: MacIncomeBoardData) -> String {
        let parts = d.bars.map { b in b.label + " " + WidgetMoneyFormat.short(b.amount) }
        var text = "近 6 個月收入：" + parts.joined(separator: "、")
        if let e = expected(d) { text += "；本月預期 " + WidgetMoneyFormat.short(e) }
        return text
    }
}

// MARK: - 表格（MacIncomeTable：範圍、搜尋、篩選、排序、列的字）

/// 表格一列（全 let；顯示字建列時算好，Cell 裡不再 format）
struct MacIncomeRow: Identifiable {
    let id: MacEntryRef
    /// 單次＝日期；週期＝起始日
    let date: Date
    let title: String
    /// 分類 rawValue（中文）
    let category: String
    /// 0 單次、1 每月、2 每年
    let periodRank: Int
    /// 「單次」「每月」「每月・離職 2026/12」
    let periodText: String
    let amount: Double
    /// 「+NT$50,000」「+NT$1,234.5」
    let amountText: String
    /// 「連著銀行」「連著銀行・USD」「連結股票」「—」
    let bankText: String
    /// 跟名稱一樣就空的
    let note: String
    /// 固定薪水已結束：整列淡一點
    let dimmed: Bool
    /// 這筆算進本月已入帳多少（單次＝amount、週期＝monthlyAmount）
    let monthly: Double
}

typealias MacIncomeSort = KeyPathComparator<MacIncomeRow>

enum MacIncomeRange: String, CaseIterable, Identifiable {
    case month, year, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: return "本月"
        case .year: return "今年"
        case .all: return "全部"
        }
    }

    /// 有收入但這個範圍、搜尋、分類篩完是空的
    var emptyText: String {
        switch self {
        case .month: return "本月沒有符合的"
        case .year: return "今年沒有符合的"
        case .all: return "沒有符合的"
        }
    }
}

enum MacIncomeTable {
    /// 範圍＋分類＋搜尋 → 列（照 order 排好）
    static func rows(incomes: [Income], range: MacIncomeRange, query: String, category: IncomeCategory?,
                     now: Date, calendar: Calendar, order: [MacIncomeSort]) -> [MacIncomeRow] {
        var out: [MacIncomeRow] = []
        for i in incomes {
            guard inRange(i, range: range, now: now, calendar: calendar) else { continue }
            if let category, i.category != category { continue }
            guard matches(i, query: query) else { continue }
            out.append(row(i, now: now, calendar: calendar))
        }
        return sort(out, by: order)
    }

    /// sim2: table#range
    /// 本月＝① 算進去的那幾筆；今年＝單次同年而且月份 ≤ 這個月，週期開始那天 ≤ 今天而且
    /// isActive(in: max(今年 1/1, 開始那個月 1 號))；全部＝全部含未來
    static func inRange(_ i: Income, range: MacIncomeRange, now: Date, calendar: Calendar) -> Bool {
        switch range {
        case .all:
            return true
        case .month:
            if i.period == .once {
                return calendar.isDate(i.date, equalTo: now, toGranularity: .month)
            }
            return calendar.startOfDay(for: i.date) <= calendar.startOfDay(for: now)
                && i.isActive(in: now, calendar: calendar)
        case .year:
            let year = calendar.component(.year, from: now)
            if i.period == .once {
                return calendar.component(.year, from: i.date) == year
                    && calendar.component(.month, from: i.date) <= calendar.component(.month, from: now)
            }
            guard calendar.startOfDay(for: i.date) <= calendar.startOfDay(for: now) else { return false }
            var comps = DateComponents()
            comps.year = year
            comps.month = 1
            comps.day = 1
            guard let jan1 = calendar.date(from: comps),
                  let startMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: i.date)) else {
                return false
            }
            return i.isActive(in: max(jan1, startMonth), calendar: calendar)
        }
    }

    /// sim2: table#search　照 IncomeView.swift:95-103：.whitespaces 去頭尾、lowercased、名稱／備註／分類 contains
    static func matches(_ i: Income, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return true }
        return i.title.lowercased().contains(q)
            || i.note.lowercased().contains(q)
            || i.category.rawValue.lowercased().contains(q)
    }

    /// sim2: table#sort　照 sortOrder 一個一個比（compare 已照正反），同值照 id 字串
    static func sort(_ rows: [MacIncomeRow], by order: [MacIncomeSort]) -> [MacIncomeRow] {
        rows.sorted { a, b in
            for c in order {
                let r = c.compare(a, b)
                if r == .orderedAscending { return true }
                if r == .orderedDescending { return false }
            }
            return a.id.id < b.id.id
        }
    }

    /// ⑪ 列的字（MoneyItemCard.swift:1006-1035）
    static func row(_ i: Income, now: Date, calendar: Calendar) -> MacIncomeRow {
        let t = i.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var periodText: String
        let rank: Int
        switch i.period {
        case .once:
            periodText = "單次"
            rank = 0
        case .monthly:
            periodText = i.period.rawValue
            rank = 1
        case .yearly:
            periodText = i.period.rawValue
            rank = 2
        }
        var dimmed = false
        if i.isFixedSalary, let end = i.endDate {
            dimmed = !i.isActive(in: now, calendar: calendar)
            let ym = "\(calendar.component(.year, from: end))/\(calendar.component(.month, from: end))"
            periodText += "・" + (i.endReason?.rawValue ?? "結束") + " " + ym
        }
        let memo = i.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = (memo.isEmpty || memo == t) ? "" : memo
        let monthly = i.period == .once ? i.amount : i.monthlyAmount
        return MacIncomeRow(id: .income(i.id), date: i.date, title: t.isEmpty ? i.category.rawValue : t,
                            category: i.category.rawValue, periodRank: rank, periodText: periodText,
                            amount: i.amount, amountText: "+" + MacText.exactMoney(i.amount),
                            bankText: bankText(i), note: note, dimmed: dimmed, monthly: monthly)
    }

    /// 入帳（表格、詳情同一支）：「連著銀行」（外幣加「・幣別」）、「連結股票」，兩個用「・」接；都沒有「—」
    static func bankText(_ i: Income) -> String {
        var parts: [String] = []
        if i.linkedBankMilestoneId != nil {
            var text = "連著銀行"
            if let code = i.linkedBankCurrency, !code.isEmpty, code != "NT$", code != "TWD" {
                text += "・" + code
            }
            parts.append(text)
        }
        if i.linkedStockId != nil {
            parts.append("連結股票")
        }
        return parts.isEmpty ? "—" : parts.joined(separator: "・")
    }

    /// 列裡有每年的收入 → 表格下面小字「每年的收入，大字照每月 1/12 算」
    static func hasYearly(_ rows: [MacIncomeRow]) -> Bool {
        rows.contains { r in r.periodRank == 2 }
    }

    /// 表格下面那行：本月＝「本月合計 NT$85,000」（monthly 加總＝本月已入帳）；今年、全部＝「12 筆」
    static func footer(_ rows: [MacIncomeRow], range: MacIncomeRange) -> String {
        if range == .month {
            let total = rows.reduce(0.0) { s, r in s + r.monthly }
            return "本月合計 " + MacText.money(total)
        }
        return "\(rows.count) 筆"
    }
}
