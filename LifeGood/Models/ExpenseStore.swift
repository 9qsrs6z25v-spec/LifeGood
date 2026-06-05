import Foundation
import SwiftUI

class ExpenseStore: ObservableObject {
    @Published var expenses: [Expense] = [] {
        didSet { if !isLoading { save() } }
    }
    @Published var incomes: [Income] = [] {
        didSet { if !isLoading { save() } }
    }
    @Published var currencyRates: [CurrencyRate] = [] {
        didSet { if !isLoading { saveCurrencyRates() } }
    }
    /// 每次 save() 或 cloud reload 後都更新，供 ChartView 偵測內容異動（含支出金額/分類/日期編輯）
    @Published private(set) var modifyID: UUID = UUID()

    private let saveKey = "lifegood_expenses"
    private let incomeKey = "lifegood_incomes"
    private let currencyRatesKey = "lifegood_currency_rates"
    private var isLoading = false
    private let saveQueue = DispatchQueue(label: "com.lifegood.expensestore.save", qos: .utility)

    init() {
        load()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadFromCloud),
            name: .cloudSyncDidPullChanges,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func reloadFromCloud() {
        load()
        modifyID = UUID()
    }

    // MARK: - 支出 CRUD

    func add(_ expense: Expense) {
        expenses.append(expense)
    }

    func update(_ expense: Expense) {
        if let index = expenses.firstIndex(where: { $0.id == expense.id }) {
            expenses[index] = expense
        }
    }

    func delete(_ expense: Expense) {
        for name in expense.photoFileNames { Expense.deletePhoto(name) }
        expenses.removeAll { $0.id == expense.id }
    }

    func delete(at offsets: IndexSet, from list: [Expense]) {
        let validOffsets = offsets.filter { $0 < list.count }
        let idsToDelete = Set(validOffsets.map { list[$0].id })
        for exp in expenses where idsToDelete.contains(exp.id) {
            for name in exp.photoFileNames { Expense.deletePhoto(name) }
        }
        expenses.removeAll { idsToDelete.contains($0.id) }
    }

    // MARK: - 收入 CRUD

    func add(_ income: Income) { incomes.append(income) }

    func update(_ income: Income) {
        if let i = incomes.firstIndex(where: { $0.id == income.id }) { incomes[i] = income }
    }

    func deleteIncome(_ income: Income) {
        incomes.removeAll { $0.id == income.id }
    }

    func deleteIncome(at offsets: IndexSet, from list: [Income]) {
        let validOffsets = offsets.filter { $0 < list.count }
        let ids = Set(validOffsets.map { list[$0].id })
        incomes.removeAll { ids.contains($0.id) }
    }

    // MARK: - 收入統計

    var currentMonthIncomes: [Income] {
        let calendar = Calendar.current
        let now = Date()
        return incomes.filter {
            calendar.isDate($0.date, equalTo: now, toGranularity: .month)
        }
    }

    /// 本月收入合計（單次收入 + 週期收入的月等效金額）
    var currentMonthIncomeTotal: Double {
        let calendar = Calendar.current
        let now = Date()

        // 單次收入：只計本月實際紀錄的
        let onceTotal = incomes
            .filter { $0.period == .once && calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }

        // 週期性收入：建立日期 <= 本月的，換算為月金額
        let recurringTotal = incomes
            .filter { $0.period != .once && calendar.startOfDay(for: $0.date) <= calendar.startOfDay(for: now) }
            .reduce(0) { $0 + $1.monthlyAmount }

        return onceTotal + recurringTotal
    }

    /// 本月收支餘額
    var currentMonthBalance: Double {
        currentMonthIncomeTotal - currentMonthTotal
    }

    /// 當月是否有實際收入紀錄
    var hasCurrentMonthIncome: Bool { currentMonthIncomeTotal > 0 }

    /// 過去月份收入中位數（用於當月無收入時預估）
    var estimatedMonthlyIncome: Double {
        let calendar = Calendar.current
        let now = Date()

        var monthlyTotals: [Double] = []
        for i in 1...6 {
            guard let monthDate = calendar.date(byAdding: .month, value: -i, to: now) else { continue }
            let total = incomeTotal(for: monthDate)
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

    /// 計算指定月份的收入合計
    private func incomeTotal(for date: Date) -> Double {
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return 0 }

        let onceTotal = incomes
            .filter { $0.period == .once && calendar.isDate($0.date, equalTo: date, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }

        let recurringTotal = incomes
            .filter { $0.period != .once && $0.date < monthEnd }
            .reduce(0) { $0 + $1.monthlyAmount }

        return onceTotal + recurringTotal
    }

    // MARK: - 篩選

    var variableExpenses: [Expense] {
        expenses
            .filter { $0.expenseType == .variable }
            .sorted { $0.date > $1.date }
    }

    var fixedExpenses: [Expense] {
        expenses
            .filter { $0.expenseType == .fixed }
            .sorted { $0.date > $1.date }
    }

    // MARK: - 本月統計

    var currentMonthExpenses: [Expense] {
        let calendar = Calendar.current
        let now = Date()
        return expenses.filter {
            calendar.isDate($0.date, equalTo: now, toGranularity: .month)
        }
    }

    var currentMonthVariableTotal: Double {
        currentMonthExpenses
            .filter { $0.expenseType == .variable }
            .reduce(0) { $0 + $1.amount }
    }

    /// 本月固定支出：所有建立日期 <= 本月的固定支出，依週期換算為月金額
    var currentMonthFixedTotal: Double {
        let calendar = Calendar.current
        let now = Date()
        return projectedFixedTotal(for: now, period: .monthly, calendar: calendar)
    }

    var currentMonthTotal: Double {
        currentMonthVariableTotal + currentMonthFixedTotal
    }

    // MARK: - 今日統計

    var todayTotal: Double {
        let calendar = Calendar.current
        let today = Date()

        // 變動支出：只計今天實際紀錄的
        let variableToday = expenses
            .filter { $0.expenseType == .variable && calendar.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.amount }

        // 固定支出：依週期換算每日金額
        let fixedDaily = projectedFixedTotal(for: today, period: .daily, calendar: calendar)

        return variableToday + fixedDaily
    }

    // MARK: - 分類統計

    func variableCategoryTotals(for month: Date? = nil) -> [(category: VariableCategory, amount: Double)] {
        let target = month ?? Date()
        let calendar = Calendar.current
        let filtered = expenses.filter {
            $0.expenseType == .variable &&
            calendar.isDate($0.date, equalTo: target, toGranularity: .month)
        }

        var totals: [VariableCategory: Double] = [:]
        for expense in filtered {
            if let cat = expense.variableCategory {
                totals[cat, default: 0] += expense.amount
            }
        }

        return totals.map { (category: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    // MARK: - 固定支出週期換算

    /// 將固定支出金額依據週期換算為指定時間區間的等效金額
    /// - Parameters:
    ///   - expense: 固定支出
    ///   - period: 目標時間區間
    /// - Returns: 換算後的金額
    private func projectedAmount(for expense: Expense, in period: TimePeriod) -> Double {
        guard expense.expenseType == .fixed, let recurrence = expense.recurrence else {
            return expense.amount
        }

        switch (recurrence, period) {
        // 每月 → 各區間
        case (.monthly, .daily):    return expense.amount / 30.0
        case (.monthly, .weekly):   return expense.amount / 4.33
        case (.monthly, .monthly):  return expense.amount
        case (.monthly, .quarterly): return expense.amount * 3.0
        case (.monthly, .yearly):   return expense.amount * 12.0
        // 每季 → 各區間
        case (.quarterly, .daily):    return expense.amount / 91.0
        case (.quarterly, .weekly):   return expense.amount / 13.0
        case (.quarterly, .monthly):  return expense.amount / 3.0
        case (.quarterly, .quarterly): return expense.amount
        case (.quarterly, .yearly):   return expense.amount * 4.0
        // 每年 → 各區間
        case (.yearly, .daily):    return expense.amount / 365.0
        case (.yearly, .weekly):   return expense.amount / 52.0
        case (.yearly, .monthly):  return expense.amount / 12.0
        case (.yearly, .quarterly): return expense.amount / 4.0
        case (.yearly, .yearly):   return expense.amount
        }
    }

    /// 計算某個時間點的固定支出投射總額（只計入建立日期 <= periodDate 的固定支出）
    private func projectedFixedTotal(for periodDate: Date, period: TimePeriod, calendar: Calendar) -> Double {
        // 只計入「固定且有週期」的支出；過去這裡誤傳整個 expenses，導致每筆變動支出的
        // 全額被當成固定支出累加（projectedAmount 對非固定項目會直接回傳 amount），
        // 使「本月固定支出」看板灌入全部變動消費而暴增。
        let allFixed = expenses.filter { $0.expenseType == .fixed && $0.recurrence != nil }
        return projectedFixedTotal(from: allFixed, for: periodDate, period: period, calendar: calendar)
    }

    /// 同上，但接受已預先篩選（expenseType == .fixed && recurrence != nil）的子集合，
    /// 避免在迴圈中重複掃描整份支出陣列。
    private func projectedFixedTotal(from fixedExpenses: [Expense], for periodDate: Date,
                                     period: TimePeriod, calendar: Calendar) -> Double {
        let dayOfPeriod = calendar.startOfDay(for: periodDate)
        let active = fixedExpenses.filter {
            calendar.startOfDay(for: $0.date) <= dayOfPeriod
        }
        return active.reduce(0) { $0 + projectedAmount(for: $1, in: period) }
    }

    // MARK: - 圖表資料

    func chartData(for period: TimePeriod) -> [ChartDataPoint] {
        let calendar = Calendar.current
        let now = Date()

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

    /// 取得指定時間區間的起始日期（與 chartData 視窗一致）
    func periodStart(for period: TimePeriod, now: Date = Date(), calendar: Calendar = .current) -> Date {
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

    /// 變動支出依分類加總（時間範圍與趨勢圖一致）
    func variableBreakdown(for period: TimePeriod) -> [(category: VariableCategory, amount: Double)] {
        let calendar = Calendar.current
        let now = Date()
        let start = periodStart(for: period, now: now, calendar: calendar)
        var dict: [VariableCategory: Double] = [:]
        for e in expenses where e.expenseType == .variable && e.date >= start && e.date <= now {
            guard let cat = e.variableCategory else { continue }
            dict[cat, default: 0] += e.amount
        }
        return dict.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    /// 固定支出依分類加總（用 projectedAmount 投射至所選時間單位，所以比例不受區間影響）
    func fixedBreakdown(for period: TimePeriod) -> [(category: FixedCategory, amount: Double)] {
        let calendar = Calendar.current
        let now = Date()
        var dict: [FixedCategory: Double] = [:]
        for e in expenses where e.expenseType == .fixed && e.recurrence != nil
            && calendar.startOfDay(for: e.date) <= calendar.startOfDay(for: now) {
            guard let cat = e.fixedCategory else { continue }
            dict[cat, default: 0] += projectedAmount(for: e, in: period)
        }
        return dict.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    private static let chartDayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()
    private static let chartMonthFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M"; return f
    }()

    private func dailyData(calendar: Calendar, now: Date) -> [ChartDataPoint] {
        let formatter = Self.chartDayFormatter
        let allFixed = expenses.filter { $0.expenseType == .fixed && $0.recurrence != nil }

        // 預先將 30 天內的變動支出依「當日 startOfDay」分組（O(n) 一次掃描），
        // 避免原本 O(30×n) 的逐日 filter
        let cutoff = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -29, to: now) ?? now)
        var variableByDay: [Date: Double] = [:]
        for e in expenses where e.expenseType == .variable {
            let day = calendar.startOfDay(for: e.date)
            if day >= cutoff { variableByDay[day, default: 0] += e.amount }
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

    private func weeklyData(calendar: Calendar, now: Date) -> [ChartDataPoint] {
        let formatter = Self.chartDayFormatter
        let allFixed = expenses.filter { $0.expenseType == .fixed && $0.recurrence != nil }

        // 預先計算每週的起訖時間（O(12)），再 O(n) 掃描所有支出指派到對應的週
        var weekRanges: [(start: Date, end: Date)] = []
        for weekOffset in (0..<12).reversed() {
            guard let ws = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: now) else { continue }
            let startOfWs = calendar.startOfDay(for: ws)
            guard let we = calendar.date(byAdding: .day, value: 7, to: startOfWs) else { continue }
            weekRanges.append((startOfWs, we))
        }
        var variableByWeek: [Date: Double] = [:]
        for e in expenses where e.expenseType == .variable {
            for range in weekRanges where e.date >= range.start && e.date < range.end {
                variableByWeek[range.start, default: 0] += e.amount
                break
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

    private func monthlyData(calendar: Calendar, now: Date) -> [ChartDataPoint] {
        let formatter = Self.chartMonthFormatter
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
            if validKeys.contains(k) { variableByMonth[k, default: 0] += e.amount }
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
            if validKeys.contains(k) { variableByQuarter[k, default: 0] += e.amount }
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
            if validYears.contains(y) { variableByYear[y, default: 0] += e.amount }
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

    // MARK: - 持久化

    private func save() {
        modifyID = UUID()
        let expSnap = expenses
        let incSnap = incomes
        let expKey = saveKey
        let incKey = incomeKey
        saveQueue.async {
            if let data = try? JSONEncoder().encode(expSnap) {
                UserDefaults.standard.set(data, forKey: expKey)
            }
            if let data = try? JSONEncoder().encode(incSnap) {
                UserDefaults.standard.set(data, forKey: incKey)
            }
            CloudSyncManager.shared.pushAll()
        }
    }

    private func saveCurrencyRates() {
        let snap = currencyRates
        let key = currencyRatesKey
        // 使用 pushAll() 而非 push(key:)，統一走 2 秒防抖，
        // 避免匯率連續更新時繞過節流直接打 CloudKit
        saveQueue.async {
            if let data = try? JSONEncoder().encode(snap) {
                UserDefaults.standard.set(data, forKey: key)
            }
            CloudSyncManager.shared.pushAll()
        }
    }

    private func load() {
        isLoading = true
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([Expense].self, from: data) {
            expenses = decoded
        }
        if let data = UserDefaults.standard.data(forKey: incomeKey),
           let decoded = try? JSONDecoder().decode([Income].self, from: data) {
            incomes = decoded
        }
        if let data = UserDefaults.standard.data(forKey: currencyRatesKey),
           let decoded = try? JSONDecoder().decode([CurrencyRate].self, from: data) {
            currencyRates = decoded
        }
        isLoading = false
    }

    // MARK: - 匯出

    func exportJSON() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(expenses)) ?? Data()
    }

    func exportCSV() -> String {
        var csv = "id,title,amount,date,type,category,recurrence,note\n"
        let formatter = ISO8601DateFormatter()
        for e in expenses.sorted(by: { $0.date < $1.date }) {
            let fields: [String] = [
                e.id.uuidString,
                csvEscape(e.title),
                String(format: "%.2f", e.amount),
                formatter.string(from: e.date),
                e.expenseType.rawValue,
                e.categoryName,
                e.recurrence?.rawValue ?? "",
                csvEscape(e.note)
            ]
            csv += fields.joined(separator: ",") + "\n"
        }
        return csv
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    // MARK: - 匯入

    enum ImportMode {
        case merge    // 合併（跳過重複 ID）
        case replace  // 取代全部
    }

    func importJSON(data: Data, mode: ImportMode = .merge) -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let imported = try? decoder.decode([Expense].self, from: data) else {
            return 0
        }
        switch mode {
        case .merge:
            let existingIDs = Set(expenses.map(\.id))
            let newExpenses = imported.filter { !existingIDs.contains($0.id) }
            expenses.append(contentsOf: newExpenses)
            return newExpenses.count
        case .replace:
            let count = imported.count
            expenses = imported
            return count
        }
    }

    // MARK: - 清除

    func clearAll() {
        // 清除支出附帶的照片
        for exp in expenses {
            for name in exp.photoFileNames { Expense.deletePhoto(name) }
        }
        isLoading = true
        expenses.removeAll()
        incomes.removeAll()
        currencyRates.removeAll()
        isLoading = false
        save()
        saveCurrencyRates()
    }
}
