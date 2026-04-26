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

    private let saveKey = "lifegood_expenses"
    private let incomeKey = "lifegood_incomes"
    private let currencyRatesKey = "lifegood_currency_rates"
    private var isLoading = false

    init() {
        load()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadFromCloud),
            name: .cloudSyncDidPullChanges,
            object: nil
        )
    }

    @objc private func reloadFromCloud() {
        load()
        objectWillChange.send()
    }

    // MARK: - 支出 CRUD

    func add(_ expense: Expense) {
        var stamped = expense
        stamped.updatedAt = Date()
        if stamped.sourceDevice == nil { stamped.sourceDevice = "iphone" }
        expenses.append(stamped)
    }

    func update(_ expense: Expense) {
        if let index = expenses.firstIndex(where: { $0.id == expense.id }) {
            var stamped = expense
            stamped.updatedAt = Date()
            if stamped.sourceDevice == nil { stamped.sourceDevice = "iphone" }
            expenses[index] = stamped
        }
    }

    func delete(_ expense: Expense) {
        expenses.removeAll { $0.id == expense.id }
    }

    func delete(at offsets: IndexSet, from list: [Expense]) {
        let idsToDelete = offsets.map { list[$0].id }
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
        let ids = offsets.map { list[$0].id }
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
        let activeFixed = expenses.filter { expense in
            expense.expenseType == .fixed &&
            expense.recurrence != nil &&
            calendar.startOfDay(for: expense.date) <= calendar.startOfDay(for: periodDate)
        }
        return activeFixed.reduce(0) { $0 + projectedAmount(for: $1, in: period) }
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

    private func dailyData(calendar: Calendar, now: Date) -> [ChartDataPoint] {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"

        var results: [ChartDataPoint] = []
        for dayOffset in (0..<30).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            let startOfDay = calendar.startOfDay(for: date)

            // 變動支出：按實際日期加總
            let variableTotal = expenses
                .filter { $0.expenseType == .variable && calendar.isDate($0.date, inSameDayAs: startOfDay) }
                .reduce(0) { $0 + $1.amount }

            // 固定支出：依週期投射每日金額
            let fixedTotal = projectedFixedTotal(for: startOfDay, period: .daily, calendar: calendar)

            results.append(ChartDataPoint(
                label: formatter.string(from: date),
                amount: variableTotal + fixedTotal,
                date: startOfDay
            ))
        }
        return results
    }

    private func weeklyData(calendar: Calendar, now: Date) -> [ChartDataPoint] {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"

        var results: [ChartDataPoint] = []
        for weekOffset in (0..<12).reversed() {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: now),
                  let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { continue }
            let startOfWeek = calendar.startOfDay(for: weekStart)

            let variableTotal = expenses
                .filter { $0.expenseType == .variable && $0.date >= startOfWeek && $0.date < weekEnd }
                .reduce(0) { $0 + $1.amount }

            let fixedTotal = projectedFixedTotal(for: startOfWeek, period: .weekly, calendar: calendar)

            results.append(ChartDataPoint(
                label: formatter.string(from: startOfWeek),
                amount: variableTotal + fixedTotal,
                date: startOfWeek
            ))
        }
        return results
    }

    private func monthlyData(calendar: Calendar, now: Date) -> [ChartDataPoint] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/M"

        var results: [ChartDataPoint] = []
        for monthOffset in (0..<12).reversed() {
            guard let date = calendar.date(byAdding: .month, value: -monthOffset, to: now) else { continue }

            let variableTotal = expenses
                .filter { $0.expenseType == .variable && calendar.isDate($0.date, equalTo: date, toGranularity: .month) }
                .reduce(0) { $0 + $1.amount }

            let fixedTotal = projectedFixedTotal(for: date, period: .monthly, calendar: calendar)

            results.append(ChartDataPoint(
                label: formatter.string(from: date),
                amount: variableTotal + fixedTotal,
                date: date
            ))
        }
        return results
    }

    private func quarterlyData(calendar: Calendar, now: Date) -> [ChartDataPoint] {
        var results: [ChartDataPoint] = []
        for quarterOffset in (0..<8).reversed() {
            guard let date = calendar.date(byAdding: .month, value: -quarterOffset * 3, to: now) else { continue }
            let quarter = (calendar.component(.month, from: date) - 1) / 3 + 1
            let year = calendar.component(.year, from: date)

            let variableTotal = expenses.filter { expense in
                expense.expenseType == .variable &&
                (calendar.component(.month, from: expense.date) - 1) / 3 + 1 == quarter &&
                calendar.component(.year, from: expense.date) == year
            }.reduce(0) { $0 + $1.amount }

            let fixedTotal = projectedFixedTotal(for: date, period: .quarterly, calendar: calendar)

            results.append(ChartDataPoint(
                label: "\(year)Q\(quarter)",
                amount: variableTotal + fixedTotal,
                date: date
            ))
        }
        return results
    }

    private func yearlyData(calendar: Calendar, now: Date) -> [ChartDataPoint] {
        var results: [ChartDataPoint] = []
        for yearOffset in (0..<5).reversed() {
            guard let date = calendar.date(byAdding: .year, value: -yearOffset, to: now) else { continue }

            let variableTotal = expenses
                .filter { $0.expenseType == .variable && calendar.isDate($0.date, equalTo: date, toGranularity: .year) }
                .reduce(0) { $0 + $1.amount }

            // 固定支出：依週期換算成年度金額（每月×12、每季×4、每年×1）
            let fixedTotal = projectedFixedTotal(for: date, period: .yearly, calendar: calendar)

            let year = calendar.component(.year, from: date)
            results.append(ChartDataPoint(
                label: "\(year)",
                amount: variableTotal + fixedTotal,
                date: date
            ))
        }
        return results
    }

    // MARK: - 同步合併

    /// 將外部（iCloud）傳來的 expense 陣列與本地合併，依 `updatedAt` 取較新者。
    /// 回傳值為「衝突 / 變動報告」，供 UI 提示用。
    /// - Note: 不觸發 push（避免循環），會直接寫入 UserDefaults 並通知本 store reload。
    @discardableResult
    static func mergeExpenses(local: [Expense], remote: [Expense]) -> ExpenseMergeResult {
        var indexed: [UUID: Expense] = [:]
        for e in local { indexed[e.id] = e }

        var added: [Expense] = []        // 遠端新增（本機未有）
        var conflicts: [ExpenseConflict] = []  // 兩邊都有但內容/時間不同
        var unchanged = 0

        for r in remote {
            if let l = indexed[r.id] {
                if r.updatedAt > l.updatedAt {
                    indexed[r.id] = r
                    if !areEquivalent(l, r) {
                        conflicts.append(ExpenseConflict(loser: l, winner: r))
                    }
                } else if l.updatedAt > r.updatedAt {
                    // 本機較新，保留本機
                } else {
                    unchanged += 1
                }
            } else {
                indexed[r.id] = r
                added.append(r)
            }
        }

        let merged = Array(indexed.values)
        return ExpenseMergeResult(merged: merged, added: added, conflicts: conflicts, unchanged: unchanged)
    }

    private static func areEquivalent(_ a: Expense, _ b: Expense) -> Bool {
        a.title == b.title && a.amount == b.amount && a.date == b.date &&
        a.variableCategory == b.variableCategory && a.fixedCategory == b.fixedCategory &&
        a.note == b.note && a.currencyCode == b.currencyCode
    }

    /// 由 CloudSyncManager 在收到外部變更後呼叫：將 cloud array 與 in-memory expenses 合併。
    /// 不會觸發 save()（避免再次 push 造成循環）。
    func applyRemoteMerge(_ remote: [Expense]) -> ExpenseMergeResult {
        let result = Self.mergeExpenses(local: expenses, remote: remote)
        isLoading = true
        expenses = result.merged.sorted { $0.date > $1.date }
        // 直接寫入 UserDefaults 但不 push 到 cloud
        if let data = try? JSONEncoder().encode(expenses) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
        isLoading = false
        return result
    }

    /// 移除指定 id 的支出（用於使用者在衝突 UI 撤銷手錶端新增）
    func removeById(_ id: UUID) {
        expenses.removeAll { $0.id == id }
    }

    /// 用指定的 Expense 取代目前的版本（用於使用者在衝突 UI 還原本機版本）
    func revertTo(_ expense: Expense) {
        var reverted = expense
        reverted.updatedAt = Date()
        reverted.sourceDevice = "iphone"
        if let i = expenses.firstIndex(where: { $0.id == reverted.id }) {
            expenses[i] = reverted
        } else {
            expenses.append(reverted)
        }
    }

    // MARK: - 持久化

    private func save() {
        if let data = try? JSONEncoder().encode(expenses) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
        if let data = try? JSONEncoder().encode(incomes) {
            UserDefaults.standard.set(data, forKey: incomeKey)
        }
        CloudSyncManager.shared.pushAll()
    }

    private func saveCurrencyRates() {
        if let data = try? JSONEncoder().encode(currencyRates) {
            UserDefaults.standard.set(data, forKey: currencyRatesKey)
        }
        CloudSyncManager.shared.push(key: currencyRatesKey)
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
        expenses.removeAll()
    }
}
