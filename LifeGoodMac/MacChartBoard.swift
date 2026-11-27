// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.645 mac5 G2] 圖表頁的數字與字（judge_mac.md §S5-1、§S5-3）：只 import Foundation，不碰 UI、不寫任何 store。
//
// • extension MacMoneyStore：chartData／periodStart／variableBreakdown／fixedBreakdown 照抄 ExpenseStore.swift:712-939（9f25bf5），
//   一律照 iOS（不修 iPhone 的怪規則），Mac 只多 now:、calendar: 參數；頁面一次算完、傳同一個 now 與 Calendar.current。
// • chartRows：明細列（分桶規則＝ExpenseStore 的 xxxData 那一桶；列合計＝那根長條、＝那一片）。
// • MacChartBoardNumbers／MacChartText：照抄 ChartView.swift:829-832、:927-935、:1142-1192、:1232-1312（9f25bf5），MoneyFormat.short → MacText.short。
// • 主控骨架：簽名定案（不准改）；G2 換內容，每支上一行「照抄 檔:行（9f25bf5）」、Swift 每段 // sim5: xxx#n。

import Foundation

// MARK: - 明細表的焦點、列、排序（§S5-3）

/// 明細表看哪一段：一期（長條的 label）、一類變動、一組固定
enum MacChartFocus: Hashable {
    case period(String)
    case variable(VariableCategory)
    case fixed(MacFixedGroupKey)
}

/// 明細表一列（字在建列時算好，Cell 只排版）
struct MacChartRow: Identifiable {
    let ref: MacEntryRef
    var id: MacEntryRef { ref }
    let sortDate: Date
    let dateText: String
    let title: String
    let category: String
    let kindText: String
    let amount: Double
    let amountText: String
    let isFixed: Bool
}

typealias MacChartSort = KeyPathComparator<MacChartRow>

// MARK: - 看板的數字（照抄 ChartView.swift:1232-1236（9f25bf5））

struct MacChartBoardNumbers: Equatable {
    /// 這段期間每一期加起來
    let total: Double
    /// 期均：分母＝金額 > 0 的期數（沒有就 0）
    let average: Double
    /// 最高那一期的金額（沒有點＝0）
    let top: Double
    /// 最高那一期的 label（同額留第一個；top ≤ 0 時 nil）
    let topLabel: String?

    static let zero = MacChartBoardNumbers(total: 0, average: 0, top: 0, topLabel: nil)

    // 照抄 ChartView.swift:1232-1236（9f25bf5）ChartStarBoard.body 的 total／spent／average／top／topLabel — sim5: board5#1
    static func make(_ points: [ChartDataPoint]) -> MacChartBoardNumbers {
        let total = points.reduce(0) { $0 + $1.amount }
        let spent = points.filter { $0.amount > 0 }
        let average = spent.isEmpty ? 0 : total / Double(spent.count)
        // points.max { $0.amount < $1.amount }：同額留第一個
        let top = points.max { $0.amount < $1.amount }
        let topLabel: String? = top.flatMap { $0.amount > 0 ? $0.label : nil }
        let topAmount: Double = top?.amount ?? 0
        return MacChartBoardNumbers(total: total, average: average, top: topAmount, topLabel: topLabel)
    }
}

// MARK: - 字（照抄 ChartView.swift（9f25bf5）；Text → String）

enum MacChartText {
    // 照抄 ChartView.swift:1260-1268（9f25bf5）TimePeriod.boardTitle — sim5: board5#2
    /// 看板左上：「近 30 天」「近 12 週」「近 12 個月」「近 8 季」「近 5 年」
    static func boardTitle(_ period: TimePeriod) -> String {
        switch period {
        case .daily:     return "近 30 天"
        case .weekly:    return "近 12 週"
        case .monthly:   return "近 12 個月"
        case .quarterly: return "近 8 季"
        case .yearly:    return "近 5 年"
        }
    }

    // 照抄 ChartView.swift:1271-1279（9f25bf5）TimePeriod.boardMaxLabel — sim5: board5#2
    /// 最多那期：「最多的一天 11/18」「最多的一週 11/16 起」…
    static func boardMaxLabel(_ label: String, period: TimePeriod) -> String {
        switch period {
        case .daily:     return "最多的一天 " + label
        case .weekly:    return "最多的一週 " + label + " 起"
        case .monthly:   return "最多的月份 " + label
        case .quarterly: return "最多的一季 " + label
        case .yearly:    return "最多的一年 " + label
        }
    }

    // 照抄 ChartView.swift:1292-1300（9f25bf5）TimePeriod.chipIcon — sim5: board5#2
    /// 期間圖示：sun.max.fill／7.square／calendar／chart.bar.fill／sparkles
    static func chipIcon(_ period: TimePeriod) -> String {
        switch period {
        case .daily:     return "sun.max.fill"
        case .weekly:    return "7.square"
        case .monthly:   return "calendar"
        case .quarterly: return "chart.bar.fill"
        case .yearly:    return "sparkles"
        }
    }

    // 照抄 ChartView.swift:1251-1255（9f25bf5）ChartStarBoard.line（MoneyFormat.short → MacText.short；Mac 沒有載入中那一句）— sim5: board5#2
    /// 看板一句話：「這段期間還沒有支出」／「期均 X・最高 Y」
    static func line(total: Double, average: Double, top: Double) -> String {
        if total <= 0 { return "這段期間還沒有支出" }
        return "期均 " + MacText.short(average) + "・最高 " + MacText.short(top)
    }

    // 照抄 ChartView.swift:1174-1182（9f25bf5）periodTitle — sim5: board5#3
    /// 趨勢卡標頭：「每日支出趨勢（近30天）」…
    static func periodTitle(_ period: TimePeriod) -> String {
        switch period {
        case .daily: return "每日支出趨勢（近30天）"
        case .weekly: return "每週支出趨勢（近12週）"
        case .monthly: return "每月支出趨勢（近12個月）"
        case .quarterly: return "每季支出趨勢（近8季）"
        case .yearly: return "每年支出趨勢（近5年）"
        }
    }

    // 照抄 ChartView.swift:927-935（9f25bf5）periodPieTitle(prefix:) — sim5: board5#3
    /// 圓餅副標：prefix＋「分類比例（近30天）」…
    static func pieTitle(prefix: String, period: TimePeriod) -> String {
        switch period {
        case .daily:     return prefix + "分類比例（近30天）"
        case .weekly:    return prefix + "分類比例（近12週）"
        case .monthly:   return prefix + "分類比例（近12個月）"
        case .quarterly: return prefix + "分類比例（近8季）"
        case .yearly:    return prefix + "分類比例（近5年）"
        }
    }

    // Mac 自訂（sim_mac5 FIXED_UNIT）— sim5: board5#3
    /// 固定支出換算單位：「每一天」「每一週」「每個月」「每一季」「每一年」（圓餅副標第二行、明細類型欄）
    static func fixedUnit(_ period: TimePeriod) -> String {
        switch period {
        case .daily:     return "每一天"
        case .weekly:    return "每一週"
        case .monthly:   return "每個月"
        case .quarterly: return "每一季"
        case .yearly:    return "每一年"
        }
    }

    // 照抄 ChartView.swift:1142-1161（9f25bf5）visibleXLabels — sim5: board5#4
    /// X 軸要顯示的 label：日每 5、週 2、月 2、季 1、年 1，最後一筆一定顯示
    static func visibleLabels(_ labels: [String], period: TimePeriod) -> Set<String> {
        let stride: Int
        switch period {
        case .daily:     stride = 5   // 30 天 → 顯示 6 個
        case .weekly:    stride = 2   // 12 週 → 顯示 6 個
        case .monthly:   stride = 2   // 12 月 → 顯示 6 個
        case .quarterly: stride = 1   // 8 季 → 全部顯示
        case .yearly:    stride = 1   // 5 年 → 全部顯示
        }
        var visible = Set<String>()
        for i in Swift.stride(from: 0, to: labels.count, by: stride) {
            visible.insert(labels[i])
        }
        // 確保最後一筆一定顯示
        if let last = labels.last {
            visible.insert(last)
        }
        return visible
    }

    // 照抄 ChartView.swift:1188-1192（9f25bf5）abbreviateCurrency — sim5: board5#5
    /// Y 軸：「%.1f億」「%.0f萬」「%.0f」
    static func axis(_ v: Double) -> String {
        if v >= 100_000_000 { return String(format: "%.1f億", v / 100_000_000) }
        if v >= 10_000 { return String(format: "%.0f萬", v / 10_000) }
        return String(format: "%.0f", v)
    }

    // 照抄 ChartView.swift:829、:851（9f25bf5）圖例百分比 — sim5: board5#6
    /// 圓餅百分比「%.1f%%」（分母＝那個圓餅的合計）
    static func percent(_ r: Double) -> String {
        String(format: "%.1f%%", r * 100)
    }

    // Mac 自訂（sim_mac5 focus_title）— sim5: board5#7
    /// 明細表頭：「11/25 這一天」「11/23 起這一週」「2026/11 這個月」「2026Q4 這一季」「2026 這一年」「飲食 · 近 30 天」
    static func focusTitle(_ focus: MacChartFocus, period: TimePeriod) -> String {
        switch focus {
        case .period(let label):
            switch period {
            case .daily:     return label + " 這一天"
            case .weekly:    return label + " 起這一週"
            case .monthly:   return label + " 這個月"
            case .quarterly: return label + " 這一季"
            case .yearly:    return label + " 這一年"
            }
        case .variable(let c):
            return c.rawValue + " · " + boardTitle(period)
        case .fixed(let g):
            return g.title + " · " + boardTitle(period)
        }
    }

    // Mac 補（iOS 字典順序不固定）— sim5: board5#3
    /// 圓餅同額的順序：VariableCategory.allCases
    static func orderVariable(_ c: VariableCategory) -> Int {
        VariableCategory.allCases.firstIndex(of: c) ?? VariableCategory.allCases.count
    }

    // Mac 補（iOS 字典順序不固定）— sim5: board5#3
    /// 圓餅同額的順序：FixedCategory.allCases，稅費最後
    static func orderFixed(_ g: MacFixedGroupKey) -> Int {
        switch g {
        case .tax:
            return FixedCategory.allCases.count
        case .category(let c):
            return FixedCategory.allCases.firstIndex(of: c) ?? FixedCategory.allCases.count
        }
    }
}

// MARK: - 圖表數字（照抄 ExpenseStore.swift:712-939（9f25bf5）；Mac 多 now:、calendar:）

extension MacMoneyStore {
    // 照抄 ExpenseStore.swift:712-728（9f25bf5）chartData(for:)（刪 let calendar／let now，改收參數）— sim5: chart5#1
    /// ① 趨勢長條的每一期（日 30、週 12、月 12、季 8、年 5）
    func chartData(for period: TimePeriod, now: Date, calendar: Calendar) -> [ChartDataPoint] {
        switch period {
        case .daily:
            return dailyData(calendar: calendar, now: now)
        case .weekly:
            return weeklyData(calendar: calendar, now: now)
        case .monthly:
            return monthlyData(calendar: calendar, now: now)
        case .quarterly:
            return quarterlyData(calendar: calendar, now: now)
        case .yearly:
            return yearlyData(calendar: calendar, now: now)
        }
    }

    // 照抄 ExpenseStore.swift:731-745（9f25bf5）periodStart(for:now:calendar:)（拿掉兩個預設值）— sim5: chart5#2
    /// ② 這段期間的起點（圓餅、明細 .variable 用）
    func periodStart(for period: TimePeriod, now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        switch period {
        case .daily:
            return calendar.date(byAdding: .day, value: -29, to: today) ?? today
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: -11, to: today) ?? today
        case .monthly:
            return calendar.date(byAdding: .month, value: -11, to: today) ?? today
        case .quarterly:
            return calendar.date(byAdding: .month, value: -7 * 3, to: today) ?? today
        case .yearly:
            return calendar.date(byAdding: .year, value: -4, to: today) ?? today
        }
    }

    // 照抄 ExpenseStore.swift:748-758（9f25bf5）variableBreakdown(for:)（同額照 VariableCategory.allCases）— sim5: chart5#3
    /// ③ 變動支出依分類（ownAmount；跳過沒分類；同額照 VariableCategory.allCases）
    func variableBreakdown(for period: TimePeriod, now: Date, calendar: Calendar) -> [(category: VariableCategory, amount: Double)] {
        let start = periodStart(for: period, now: now, calendar: calendar)
        var dict: [VariableCategory: Double] = [:]
        for e in expenses where e.expenseType == .variable && e.date >= start && e.date <= now {
            guard let cat = e.variableCategory else { continue }
            dict[cat, default: 0] += ownAmount(e)
        }
        let pairs: [(VariableCategory, Double)] = dict.map { ($0.key, $0.value) }
        let ordered: [(VariableCategory, Double)] = pairs.sorted { a, b in
            a.1 != b.1 ? a.1 > b.1 : MacChartText.orderVariable(a.0) < MacChartText.orderVariable(b.0)
        }
        return ordered.map { p in (category: p.0, amount: p.1) }
    }

    // 照抄 ExpenseStore.swift:762-772（9f25bf5）fixedBreakdown(for:)（ExpenseKindStore.shared.index → kindIndex、FixedGroup → MacFixedGroupKey；
    // isFixedActive 照傳 now；同額照 FixedCategory.allCases、稅費最後）— sim5: chart5#4
    /// ④ 固定支出依組（projectedAmount 換算到這個期間單位；跳過沒分類）
    func fixedBreakdown(for period: TimePeriod, now: Date, calendar: Calendar) -> [(group: MacFixedGroupKey, amount: Double)] {
        var dict: [MacFixedGroupKey: Double] = [:]
        for e in expenses where e.expenseType == .fixed && e.recurrence != nil
            && e.isFixedActive(on: now, calendar: calendar) {
            guard e.fixedCategory != nil else { continue }
            dict[MacFixedGroupKey.of(e, kinds: kindIndex), default: 0] += projectedAmount(for: e, in: period)
        }
        let pairs: [(MacFixedGroupKey, Double)] = dict.map { ($0.key, $0.value) }
        let ordered: [(MacFixedGroupKey, Double)] = pairs.sorted { a, b in
            a.1 != b.1 ? a.1 > b.1 : MacChartText.orderFixed(a.0) < MacChartText.orderFixed(b.0)
        }
        return ordered.map { p in (group: p.0, amount: p.1) }
    }

    // 照抄 ExpenseStore.swift:775-780（9f25bf5）chartDayFormatter／chartMonthFormatter（只設 dateFormat；名字加 mac）— sim5: chart5#5
    private static let macChartDayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()
    private static let macChartMonthFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M"; return f
    }()

    // 照抄 ExpenseStore.swift:782-807（9f25bf5）dailyData（body 逐字；只換 formatter 名字）— sim5: chart5#6
    private func dailyData(calendar: Calendar, now: Date) -> [ChartDataPoint] {
        let formatter = Self.macChartDayFormatter
        let allFixed = expenses.filter { $0.expenseType == .fixed && $0.recurrence != nil }

        // 預先將 30 天內的變動支出依「當日 startOfDay」分組（O(n) 一次掃描），
        // 避免原本 O(30×n) 的逐日 filter
        let cutoff = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -29, to: now) ?? now)
        var variableByDay: [Date: Double] = [:]
        for e in expenses where e.expenseType == .variable {
            let day = calendar.startOfDay(for: e.date)
            if day >= cutoff { variableByDay[day, default: 0] += ownAmount(e) }
        }

        var results: [ChartDataPoint] = []
        for dayOffset in (0..<30).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            let startOfDay = calendar.startOfDay(for: date)
            let variableTotal = variableByDay[startOfDay] ?? 0
            let fixedTotal = projectedFixedTotal(from: allFixed, for: startOfDay, period: .daily, calendar: calendar)
            results.append(ChartDataPoint(
                label: formatter.string(from: date),
                amount: variableTotal + fixedTotal,
                date: startOfDay
            ))
        }
        return results
    }

    // 照抄 ExpenseStore.swift:810-845（9f25bf5）weeklyData（body 逐字；只換 formatter 名字）— sim5: chart5#7
    private func weeklyData(calendar: Calendar, now: Date) -> [ChartDataPoint] {
        let formatter = Self.macChartDayFormatter
        let allFixed = expenses.filter { $0.expenseType == .fixed && $0.recurrence != nil }

        // 預先計算每週的起訖時間（O(12)），再以「日期偏移量 ÷ 7」直接計算週索引（真正 O(n)），
        // 修正原本 O(n×12) 內層迴圈與注釋不符的問題。
        var weekRanges: [(start: Date, end: Date)] = []
        for weekOffset in (0..<12).reversed() {
            guard let ws = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: now) else { continue }
            let startOfWs = calendar.startOfDay(for: ws)
            guard let we = calendar.date(byAdding: .day, value: 7, to: startOfWs) else { continue }
            weekRanges.append((startOfWs, we))
        }
        var variableByWeek: [Date: Double] = [:]
        if let cutoff = weekRanges.first?.start {
            for e in expenses where e.expenseType == .variable {
                let eDay = calendar.startOfDay(for: e.date)
                guard eDay >= cutoff,
                      let dayOffset = calendar.dateComponents([.day], from: cutoff, to: eDay).day else { continue }
                let weekIndex = dayOffset / 7
                guard weekIndex < weekRanges.count else { continue }
                variableByWeek[weekRanges[weekIndex].start, default: 0] += ownAmount(e)
            }
        }

        var results: [ChartDataPoint] = []
        for range in weekRanges {
            let variableTotal = variableByWeek[range.start] ?? 0
            let fixedTotal = projectedFixedTotal(from: allFixed, for: range.start, period: .weekly, calendar: calendar)
            results.append(ChartDataPoint(
                label: formatter.string(from: range.start),
                amount: variableTotal + fixedTotal,
                date: range.start
            ))
        }
        return results
    }

    // 照抄 ExpenseStore.swift:848-876（9f25bf5）monthlyData（body 逐字；只換 formatter 名字）— sim5: chart5#8
    private func monthlyData(calendar: Calendar, now: Date) -> [ChartDataPoint] {
        let formatter = Self.macChartMonthFormatter
        let allFixed = expenses.filter { $0.expenseType == .fixed && $0.recurrence != nil }

        // 預先建立月份對照（year*100+month → representative Date），O(n) 分組
        var monthDates: [(key: Int, date: Date)] = []
        for monthOffset in (0..<12).reversed() {
            guard let d = calendar.date(byAdding: .month, value: -monthOffset, to: now) else { continue }
            let key = calendar.component(.year, from: d) * 100 + calendar.component(.month, from: d)
            monthDates.append((key, d))
        }
        let validKeys = Set(monthDates.map(\.key))
        var variableByMonth: [Int: Double] = [:]
        for e in expenses where e.expenseType == .variable {
            let k = calendar.component(.year, from: e.date) * 100 + calendar.component(.month, from: e.date)
            if validKeys.contains(k) { variableByMonth[k, default: 0] += ownAmount(e) }
        }

        var results: [ChartDataPoint] = []
        for (key, date) in monthDates {
            let variableTotal = variableByMonth[key] ?? 0
            let fixedTotal = projectedFixedTotal(from: allFixed, for: date, period: .monthly, calendar: calendar)
            results.append(ChartDataPoint(
                label: formatter.string(from: date),
                amount: variableTotal + fixedTotal,
                date: date
            ))
        }
        return results
    }

    // 照抄 ExpenseStore.swift:879-909（9f25bf5）quarterlyData（body 逐字；只換 formatter 名字）— sim5: chart5#9
    private func quarterlyData(calendar: Calendar, now: Date) -> [ChartDataPoint] {
        let allFixed = expenses.filter { $0.expenseType == .fixed && $0.recurrence != nil }

        // 預先建立季度對照（year*10+quarter），O(n) 分組
        var quarterInfo: [(key: Int, year: Int, quarter: Int, date: Date)] = []
        for quarterOffset in (0..<8).reversed() {
            guard let d = calendar.date(byAdding: .month, value: -quarterOffset * 3, to: now) else { continue }
            let y = calendar.component(.year, from: d)
            let q = (calendar.component(.month, from: d) - 1) / 3 + 1
            quarterInfo.append((y * 10 + q, y, q, d))
        }
        let validKeys = Set(quarterInfo.map(\.key))
        var variableByQuarter: [Int: Double] = [:]
        for e in expenses where e.expenseType == .variable {
            let y = calendar.component(.year, from: e.date)
            let q = (calendar.component(.month, from: e.date) - 1) / 3 + 1
            let k = y * 10 + q
            if validKeys.contains(k) { variableByQuarter[k, default: 0] += ownAmount(e) }
        }

        var results: [ChartDataPoint] = []
        for info in quarterInfo {
            let variableTotal = variableByQuarter[info.key] ?? 0
            let fixedTotal = projectedFixedTotal(from: allFixed, for: info.date, period: .quarterly, calendar: calendar)
            results.append(ChartDataPoint(
                label: "\(info.year)Q\(info.quarter)",
                amount: variableTotal + fixedTotal,
                date: info.date
            ))
        }
        return results
    }

    // 照抄 ExpenseStore.swift:912-939（9f25bf5）yearlyData（body 逐字；只換 formatter 名字）— sim5: chart5#10
    private func yearlyData(calendar: Calendar, now: Date) -> [ChartDataPoint] {
        let allFixed = expenses.filter { $0.expenseType == .fixed && $0.recurrence != nil }

        // 預先建立年份清單，O(n) 分組後直接查字典
        var yearDates: [(year: Int, date: Date)] = []
        for yearOffset in (0..<5).reversed() {
            guard let d = calendar.date(byAdding: .year, value: -yearOffset, to: now) else { continue }
            yearDates.append((calendar.component(.year, from: d), d))
        }
        let validYears = Set(yearDates.map(\.year))
        var variableByYear: [Int: Double] = [:]
        for e in expenses where e.expenseType == .variable {
            let y = calendar.component(.year, from: e.date)
            if validYears.contains(y) { variableByYear[y, default: 0] += ownAmount(e) }
        }

        var results: [ChartDataPoint] = []
        for (year, date) in yearDates {
            let variableTotal = variableByYear[year] ?? 0
            // 固定支出：依週期換算成年度金額（每月×12、每季×4、每年×1）
            let fixedTotal = projectedFixedTotal(from: allFixed, for: date, period: .yearly, calendar: calendar)
            results.append(ChartDataPoint(
                label: "\(year)",
                amount: variableTotal + fixedTotal,
                date: date
            ))
        }
        return results
    }

    // MARK: 明細列（§S5-3；分桶＝上面 xxxData 那一桶，列合計＝那根長條、＝那一片）

    /// 明細列：.period＝那一桶（含桶裡的未來日期）；.variable／.fixed＝那一片
    func chartRows(_ focus: MacChartFocus, period: TimePeriod, points: [ChartDataPoint],
                   now: Date, calendar: Calendar) -> [MacChartRow] {
        var variable: [Expense] = []
        var fixed: [Expense] = []
        switch focus {
        case .period(let label):
            // sim5: rows5#1 那一期：變動＝跟 xxxData 同一桶（含桶裡的未來日期）；固定＝那一期 startOfDay 還在扣的（同 projectedFixedTotal）
            guard let point = points.first(where: { p in p.label == label }) else { return [] }
            let bucket = MacChartBucket(period: period, point: point, now: now, calendar: calendar)
            let day = calendar.startOfDay(for: point.date)
            for e in expenses {
                if e.expenseType == .variable {
                    if bucket.contains(e.date) { variable.append(e) }
                } else if e.expenseType == .fixed && e.recurrence != nil && e.isFixedActive(on: day, calendar: calendar) {
                    fixed.append(e)
                }
            }
        case .variable(let c):
            // sim5: rows5#2 那一類（同 variableBreakdown：periodStart ≤ date ≤ now）
            let start = periodStart(for: period, now: now, calendar: calendar)
            variable = expenses.filter { e in
                e.expenseType == .variable && e.variableCategory == c && e.date >= start && e.date <= now
            }
        case .fixed(let g):
            // sim5: rows5#3 那一組（同 fixedBreakdown：isFixedActive(on: now)、跳過沒分類）
            let kinds = kindIndex
            fixed = expenses.filter { e in
                e.expenseType == .fixed && e.recurrence != nil && e.isFixedActive(on: now, calendar: calendar)
                    && e.fixedCategory != nil && MacFixedGroupKey.of(e, kinds: kinds) == g
            }
        }
        return chartRowsText(variable: variable, fixed: fixed, period: period)
    }

    // sim5: rows5#4 字與預設順序：變動日期新到舊在前、固定金額大到小在後，同值照 id 字串（MacEntryRef.id）
    private func chartRowsText(variable: [Expense], fixed: [Expense], period: TimePeriod) -> [MacChartRow] {
        let kinds = kindIndex
        let unit = "固定（換算成" + MacChartText.fixedUnit(period) + "）"
        let varSorted: [Expense] = variable.sorted { a, b in
            if a.date != b.date { return a.date > b.date }
            return MacEntryRef.expense(a.id).id < MacEntryRef.expense(b.id).id
        }
        let fixedPairs: [(Expense, Double)] = fixed.map { e in (e, projectedAmount(for: e, in: period)) }
        let fixedSorted: [(Expense, Double)] = fixedPairs.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            return MacEntryRef.expense(a.0.id).id < MacEntryRef.expense(b.0.id).id
        }
        var rows: [MacChartRow] = []
        for e in varSorted {
            let amount = ownAmount(e)
            rows.append(MacChartRow(ref: .expense(e.id), sortDate: e.date, dateText: MacText.dayTime(e.date), title: e.title,
                                    category: e.macDisplayCategoryName(kinds: kinds), kindText: "變動", amount: amount,
                                    amountText: MacText.money(amount), isFixed: false))
        }
        for (e, amount) in fixedSorted {
            let cycle: String = e.recurrence?.rawValue ?? ""
            rows.append(MacChartRow(ref: .expense(e.id), sortDate: e.date, dateText: cycle, title: e.title,
                                    category: MacFixedGroupKey.of(e, kinds: kinds).title, kindText: unit, amount: amount,
                                    amountText: MacText.money(amount), isFixed: true))
        }
        return rows
    }
}

// MARK: - 一期的桶（照抄上面 xxxData 的分桶：日 startOfDay、週 weekRanges＋(eDay − cutoff).day / 7、月 年×100＋月、季 年×10＋季、年）

/// sim5: rows5#1 一筆變動支出落不落在這一期（跟長條同一條規則，所以列合計＝那根長條）
private struct MacChartBucket {
    let period: TimePeriod
    let point: ChartDataPoint
    let calendar: Calendar
    /// 週：跟 weeklyData 一樣的 12 格起點（舊到新）
    let weekStarts: [Date]

    init(period: TimePeriod, point: ChartDataPoint, now: Date, calendar: Calendar) {
        self.period = period
        self.point = point
        self.calendar = calendar
        var starts: [Date] = []
        if period == .weekly {
            // 照抄 ExpenseStore.swift:816-822（9f25bf5）weekRanges
            for weekOffset in (0..<12).reversed() {
                guard let ws = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: now) else { continue }
                let startOfWs = calendar.startOfDay(for: ws)
                guard calendar.date(byAdding: .day, value: 7, to: startOfWs) != nil else { continue }
                starts.append(startOfWs)
            }
        }
        self.weekStarts = starts
    }

    func contains(_ t: Date) -> Bool {
        switch period {
        case .daily:
            return calendar.startOfDay(for: t) == point.date
        case .weekly:
            // 照抄 ExpenseStore.swift:824-833（9f25bf5）
            guard let cutoff = weekStarts.first else { return false }
            let eDay = calendar.startOfDay(for: t)
            guard eDay >= cutoff,
                  let dayOffset = calendar.dateComponents([.day], from: cutoff, to: eDay).day else { return false }
            let weekIndex = dayOffset / 7
            guard weekIndex < weekStarts.count else { return false }
            return weekStarts[weekIndex] == point.date
        case .monthly:
            return monthKey(t) == monthKey(point.date)
        case .quarterly:
            return quarterKey(t) == quarterKey(point.date)
        case .yearly:
            return calendar.component(.year, from: t) == calendar.component(.year, from: point.date)
        }
    }

    private func monthKey(_ d: Date) -> Int {
        calendar.component(.year, from: d) * 100 + calendar.component(.month, from: d)
    }

    private func quarterKey(_ d: Date) -> Int {
        let y = calendar.component(.year, from: d)
        let q = (calendar.component(.month, from: d) - 1) / 3 + 1
        return y * 10 + q
    }
}
