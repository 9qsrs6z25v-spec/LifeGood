import Foundation

// MARK: - 大方塊第三版要的快照欄位（v25.637 large3；只屬於主 App）
//
// 規格：scratchpad/radar/judge_largewidgets.md §C 第三版、scratchpad/radar/build/large3/brief.md §1。
// sim：scratchpad/radar/build/large3/sim_large3.py（一個函式一個函式對照）。
//
// 只在既有的寫入時機裡算（不另外加監聽、不另外加寫入時機）：
//   • money（WidgetSnapshotWriter.moneySnapshot，記帳＋理財那條防抖 3 秒）：
//       monthCategories（還能花・大「花在哪」）、recentDays（還能花・大「近 7 天」）、todayEntries（記帳台・大「今天記的」）
//   • finance（WidgetFinanceBuilder.netWorth）：WidgetNetWorth.history（淨資產・大「近 12 個月」）
//
// 規矩：
//   • 只讀不寫：不改任何 store。**不呼叫 FinanceChartBoardData.build**（它會 FinanceHistory.record 寫每月紀錄）、
//     不呼叫 FinanceHistory.record；走勢只用 FinanceHistory.series(months: 12)（只讀），而且只在換日、財富的 revision
//     或過去月份回推讀得到的東西（historyKey）變了才重算過去那 11 個月（historyCache）；這個月那一點每次都用剛算好的 FinanceSnapshot.current。
//   • 統計數字跟 App 同一個來源：變動支出一律 expense.ownAmount（25.634 起分帳那頓只算自己那份；同 OverviewBoardData.build、
//     VariableBoardData.build）。「今天記的」金額照 App 列表卡片的大字（MoneyItem.amountText：刷卡金額，外幣照原幣）。
//   • 字要穩定：金額只用 MoneyFormat.short／MoneyFormat.percent／ntdWanString；比例一律夾 0…1、四捨五入到小數三位；
//     排序同值一律再比固定的東西（分類照 VariableCategory.allCases、支出照 id），同樣的帳寫出同樣的字。
//   • 隱私：「今天記的」只有時間、分類、金額——**不放名稱、備註、店名、地點、同行人員、分帳的人**。走勢不放金額。
//
// @MainActor：MoneyFormat 的 NumberFormatter 只在主執行緒用（跟寫手一樣）。

@MainActor
enum WidgetLargeExtras {

    /// 「花在哪」最多幾列（同變動支出看板市集：有「其他」時前 4 類＋其他）
    static let maxCategoryRows = 5
    static let namedRowsWithOther = 4
    /// 「近 7 天」幾根
    static let recentDayCount = 7
    /// 「近 7 天」今天之後再寫幾天（明天、後天；快照超過兩天沒更新就算舊的，WidgetFreshness.moneyStaleAfter）
    static let recentDaysAhead = 2
    /// 「今天記的」最多幾筆
    static let maxTodayEntries = 4
    /// 走勢幾個月
    static let historyMonths = 12

    /// Calendar 的 weekday：1＝星期日
    private static let weekdayChars: [String] = ["日", "一", "二", "三", "四", "五", "六"]

    // MARK: - 純函式（sim 對照）

    /// 夾 0…1、四捨五入到小數三位（字要穩定）；不是有限數 0
    static func unit3(_ v: Double) -> Double {
        guard v.isFinite else { return 0 }
        let c: Double = min(max(v, 0), 1)
        return (c * 1000).rounded() / 1000
    }

    /// 寫進快照的數字一律有限
    private static func finite(_ v: Double) -> Double {
        v.isFinite ? v : 0
    }

    /// 柱高：除以 7 天裡最大的那一天；都沒花（最大 ≤ 0）全部 0。負的、不是有限數當 0
    static func barHeights(_ values: [Double]) -> [Double] {
        let clean: [Double] = values.map { ($0.isFinite && $0 > 0) ? $0 : 0 }
        let top: Double = clean.max() ?? 0
        guard top > 0 else { return clean.map { _ in 0 } }
        return clean.map { unit3($0 / top) }
    }

    /// 走勢高度：(v − 最低) ÷ (最高 − 最低)；只有 1 點、或全部差不到 1 塊錢＝0.5（畫成一條平的線）。負的淨資產照算
    static func trendHeights(_ values: [Double]) -> [Double] {
        let clean: [Double] = values.map { $0.isFinite ? $0 : 0 }
        guard let lo = clean.min(), let hi = clean.max() else { return [] }
        let span: Double = hi - lo
        guard span >= 1 else { return clean.map { _ in 0.5 } }
        return clean.map { unit3(($0 - lo) / span) }
    }

    /// 走勢的月份字：今年「11 月」、去年「去年 12 月」、更早「2024/12」
    static func monthLabel(year: Int, month: Int, currentYear: Int) -> String {
        if year == currentYear { return "\(month) 月" }
        if year == currentYear - 1 { return "去年 \(month) 月" }
        return "\(year)/\(month)"
    }

    /// 一個分類這個月花了多少、幾筆
    struct CategoryTotal: Equatable {
        let category: VariableCategory
        let amount: Double
        let count: Int
    }

    /// 照變動支出看板「市集」（VariableBoardData.build）的分法：有名字的分類大到小（同值照 VariableCategory.allCases），
    /// 「其他」固定最後；有「其他」時最多 4 類、沒有時最多 5 類，放不下的併進「其他」。
    /// 放不放得下照看板算（0 元的分類也算一類，看板的 byCategory 有它）；**畫的時候** 0 元的分類不列，
    /// 這樣每一列的金額、占比跟看板一樣（例：5 類有錢＋社交整類分帳到 0、沒有「其他」→ 看板 6 類 > 5，第 5 類併進「其他」，這裡也是）。
    /// total ≤ 0（這個月還沒花錢）回空陣列
    static func categoryRows(_ totals: [CategoryTotal], total: Double) -> [WidgetMoneyCategoryShare] {
        guard total.isFinite, total > 0 else { return [] }
        let order: [VariableCategory] = VariableCategory.allCases
        let named: [CategoryTotal] = totals
            .filter { $0.category != .other }
            .sorted { a, b in
                if a.amount != b.amount { return a.amount > b.amount }
                let ia: Int = order.firstIndex(of: a.category) ?? order.count
                let ib: Int = order.firstIndex(of: b.category) ?? order.count
                return ia < ib
            }
        var otherAmount: Double = 0
        var otherCount: Int = 0
        for t in totals where t.category == .other {
            otherAmount += t.amount
            otherCount += t.count
        }
        let room: Int = otherAmount > 0 ? namedRowsWithOther : maxCategoryRows
        var kept: [CategoryTotal] = named
        if named.count > room {
            kept = Array(named.prefix(namedRowsWithOther))
            for t in named.dropFirst(namedRowsWithOther) {
                otherAmount += t.amount
                otherCount += t.count
            }
        }
        let shown: [CategoryTotal] = kept.filter { $0.amount > 0 }
        var out: [WidgetMoneyCategoryShare] = shown.map { share($0.category.rawValue, $0.amount, $0.count, total: total) }
        if otherAmount > 0 {
            out.append(share(VariableCategory.other.rawValue, otherAmount, otherCount, total: total))
        }
        return out
    }

    private static func share(_ key: String, _ amount: Double, _ count: Int, total: Double) -> WidgetMoneyCategoryShare {
        let v: Double = finite(amount)
        let r: Double = finite(v / total)
        return WidgetMoneyCategoryShare(key: key, amountText: MoneyFormat.short(v), share: unit3(r),
                                        shareText: MoneyFormat.percent(min(max(r, 0), 1)), count: count)
    }

    // MARK: - money：還能花（大）、記帳台（大）

    /// 這個月（now 那個月）的變動支出照分類分。同 VariableBoardData.build：expenseType == .variable、
    /// cal.isDate(e.date, equalTo: now, toGranularity: .month)、沒有分類算「其他」、金額 ownAmount
    static func monthCategories(expense: ExpenseStore, now: Date,
                                calendar cal: Calendar = .current) -> [WidgetMoneyCategoryShare] {
        var amounts: [VariableCategory: Double] = [:]
        var counts: [VariableCategory: Int] = [:]
        var total: Double = 0
        for e in expense.expenses where e.expenseType == .variable {
            guard cal.isDate(e.date, equalTo: now, toGranularity: .month) else { continue }
            let c: VariableCategory = e.variableCategory ?? .other
            let v: Double = finite(expense.ownAmount(e))
            amounts[c, default: 0] += v
            counts[c, default: 0] += 1
            total += v
        }
        var totals: [CategoryTotal] = []
        for c in VariableCategory.allCases {
            if let a = amounts[c] {
                totals.append(CategoryTotal(category: c, amount: a, count: counts[c] ?? 0))
            }
        }
        return categoryRows(totals, total: total)
    }

    /// 今天、明天、後天各一份「近 7 天」（最後一根＝那一天）。每天的變動支出同 OverviewBoardData.build 的 daily（ownAmount）；
    /// 只算到今天為止（明天以後還不知道，是 0——同 money 的 days 往後推的規則）。日子用 WidgetDateText.dayKey 對
    static func recentDays(expense: ExpenseStore, now: Date,
                           calendar cal: Calendar = .current) -> [WidgetMoneyRecentWeek] {
        let today: Date = cal.startOfDay(for: now)
        guard let first = cal.date(byAdding: .day, value: -(recentDayCount - 1), to: today),
              let end = cal.date(byAdding: .day, value: 1, to: today) else { return [] }
        var byDay: [String: Double] = [:]
        for e in expense.expenses where e.expenseType == .variable {
            guard e.date >= first, e.date < end else { continue }
            byDay[WidgetDateText.dayKey(e.date), default: 0] += finite(expense.ownAmount(e))
        }
        var out: [WidgetMoneyRecentWeek] = []
        for ahead in 0...recentDaysAhead {
            guard let asOf = cal.date(byAdding: .day, value: ahead, to: today) else { continue }
            var days: [Date] = []
            for back in stride(from: recentDayCount - 1, through: 0, by: -1) {
                if let d = cal.date(byAdding: .day, value: -back, to: asOf) {
                    days.append(d)
                }
            }
            let values: [Double] = days.map { byDay[WidgetDateText.dayKey($0)] ?? 0 }
            let heights: [Double] = barHeights(values)
            var bars: [WidgetMoneyRecentBar] = []
            for (d, h) in zip(days, heights) {
                let w: Int = cal.component(.weekday, from: d)
                let i: Int = min(max(w - 1, 0), weekdayChars.count - 1)
                bars.append(WidgetMoneyRecentBar(dayKey: WidgetDateText.dayKey(d), weekday: weekdayChars[i], height: h))
            }
            let sum: Double = values.reduce(0) { $0 + max(0, $1) }
            out.append(WidgetMoneyRecentWeek(dayKey: WidgetDateText.dayKey(asOf), bars: bars,
                                             totalText: "\(recentDayCount) 天 " + MoneyFormat.short(finite(sum)),
                                             totalTextMasked: "\(recentDayCount) 天 " + WidgetHideAmounts.mask))
        }
        return out
    }

    /// 今天記的變動支出（同 OverviewBoardData.build 的 todayCount：expenseType == .variable、跟 now 同一天），
    /// 最新的在前（同時間照 id），最多 4 筆。只有時間、分類、金額
    static func todayEntries(expense: ExpenseStore, now: Date,
                             calendar cal: Calendar = .current) -> [WidgetMoneyTodayEntry] {
        let today: [Expense] = expense.expenses.filter {
            $0.expenseType == .variable && cal.isDate($0.date, inSameDayAs: now)
        }
        let sorted: [Expense] = today.sorted { a, b in
            if a.date != b.date { return a.date > b.date }
            return a.id.uuidString < b.id.uuidString
        }
        let rates: [String: Double] = listRates(expense)
        return sorted.prefix(maxTodayEntries).map { (e: Expense) -> WidgetMoneyTodayEntry in
            WidgetMoneyTodayEntry(id: e.id.uuidString,
                                  timeText: DayTimelineFormat.time(e.date),
                                  categoryKey: (e.variableCategory ?? .other).rawValue,
                                  amountText: listAmountText(e, rates: rates),
                                  amountTextMasked: WidgetHideAmounts.mask)
        }
    }

    /// 同 MoneyItemContext.init 的 rates：store.currencyRates 同一個代碼取第一個
    static func listRates(_ store: ExpenseStore) -> [String: Double] {
        var r: [String: Double] = [:]
        for rate in store.currencyRates where r[rate.code] == nil {
            r[rate.code] = rate.rate
        }
        return r
    }

    private static let listDecimal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    /// 跟 App 列表卡片的大字同一個規則（MoneyItem.amountText，MoneyItemCard.swift；變動支出沒有儲蓄險那條）：
    /// 台幣 ntdWanString；外幣照原幣（存的是台幣等值，除回匯率；查不到匯率照存的數字）。改那邊要一起改（keycheck 比對）
    static func listAmountText(_ e: Expense, rates: [String: Double]) -> String {
        let code = e.currencyCode
        guard code != "NT$", code != "TWD", !code.isEmpty else { return e.amount.ntdWanString }
        let value: Double
        if let rate = rates[code], rate > 0 {
            value = e.amount / rate
        } else {
            value = e.amount
        }
        return code + " " + (listDecimal.string(from: NSNumber(value: value)) ?? "0")
    }

    // MARK: - finance：淨資產（大）走勢

    /// 過去 11 個月（不含這個月）的快取：換日、財富 revision、過去月份回推會讀到的東西變了才重算
    ///（FinanceHistory.series 要回推好幾個月，很重）
    private struct HistoryCache {
        let key: String
        let past: [FinanceMonthPoint]
    }

    private static var historyCache: HistoryCache? = nil

    /// 快取的鑰匙：哪一天｜財富 revision｜記帳的 modifyID（支出、收入、分帳、細項、iCloud 重載；貸款、存款與卡費的回推）｜
    /// 匯率｜房子、車、保單、股票的內容指紋｜每月紀錄、每週股票市值的指紋。
    /// [審查 fix] 原本只看筆數：改估價、買價、日期、貸款、補記舊帳、匯率、iCloud 拉來的每月紀錄都不會重算，
    /// 過去 11 個月停在舊的、只有這個月跳。股票不含 currentPrice（股價更新只動這個月那一點，不重算）
    static func historyKey(finance f: FinanceStore, expense ex: ExpenseStore, now: Date, wealthRevision: Int) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let stocks: [Stock] = f.stocks.map { (stock: Stock) -> Stock in
            var copy = stock
            copy.currentPrice = 0
            return copy
        }
        let blobs: [Data?] = [try? encoder.encode(f.realEstates), try? encoder.encode(f.vehicles),
                              try? encoder.encode(f.insurances), try? encoder.encode(stocks),
                              UserDefaults.standard.data(forKey: FinanceHistory.key)]
        var hasher = Hasher()
        for blob in blobs {
            guard let blob else {
                hasher.combine(-1)
                continue
            }
            hasher.combine(blob.count)
            blob.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in hasher.combine(bytes: raw) }
        }
        for week in StockValueHistory.load() {
            hasher.combine(week.weekStart.timeIntervalSinceReferenceDate)
            hasher.combine(week.value)
        }
        let rateSig: String = ex.currencyRates.map { (rate: CurrencyRate) -> String in "\(rate.code)=\(rate.rate)" }
            .joined(separator: ",")
        let parts: [String] = [WidgetDateText.dayKey(now), String(wealthRevision), ex.modifyID.uuidString, rateSig,
                               String(hasher.finalize())]
        return parts.joined(separator: "|")
    }

    /// 近 12 個月：過去 11 個月照 FinanceHistory.series(months: 12)（有存的用存的、沒有的回推；只讀），
    /// 這個月用 current（剛算好的 FinanceSnapshot.current，跟大字同一個數）。前面資產、貸款都是 0 的月份不畫
    ///（同 FinanceChartBoardData.build）；不到 2 點 nil
    static func netWorthHistory(finance f: FinanceStore, expense e: ExpenseStore, rates: FinanceRates,
                                index: FinanceLoanIndex, current: FinanceSnapshot, now: Date, wealthRevision: Int,
                                calendar cal: Calendar = .current) -> [WidgetNetWorthPoint]? {
        guard let thisMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) else { return nil }
        let key: String = historyKey(finance: f, expense: e, now: now, wealthRevision: wealthRevision)
        let past: [FinanceMonthPoint]
        if let cached = historyCache, cached.key == key {
            past = cached.past
        } else {
            let all: [FinanceMonthPoint] = FinanceHistory.series(months: historyMonths, finance: f, expense: e,
                                                                 rates: rates, now: now, index: index)
            past = Array(all.filter { $0.month < thisMonth }.suffix(historyMonths - 1))
            historyCache = HistoryCache(key: key, past: past)
        }
        let latest = FinanceMonthPoint(month: thisMonth, assets: current.assets, debt: current.debt, recorded: true)
        let points: [FinanceMonthPoint] = Array((past + [latest]).drop { $0.assets <= 0 && $0.debt <= 0 })
        guard points.count >= 2 else { return nil }
        let heights: [Double] = trendHeights(points.map { $0.netWorth })
        let currentYear: Int = cal.component(.year, from: now)
        var out: [WidgetNetWorthPoint] = []
        for (p, h) in zip(points, heights) {
            let y: Int = cal.component(.year, from: p.month)
            let m: Int = cal.component(.month, from: p.month)
            out.append(WidgetNetWorthPoint(monthKey: WidgetDateText.monthKey(p.month),
                                           monthText: monthLabel(year: y, month: m, currentYear: currentYear),
                                           height: h))
        }
        return out
    }
}
