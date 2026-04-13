import Foundation
import SwiftUI

class ExpenseStore: ObservableObject {
    @Published var expenses: [Expense] = [] {
        didSet {
            save()
        }
    }

    private let saveKey = "lifegood_expenses"

    init() {
        load()
    }

    // MARK: - CRUD

    func add(_ expense: Expense) {
        expenses.append(expense)
    }

    func update(_ expense: Expense) {
        if let index = expenses.firstIndex(where: { $0.id == expense.id }) {
            expenses[index] = expense
        }
    }

    func delete(_ expense: Expense) {
        expenses.removeAll { $0.id == expense.id }
    }

    func delete(at offsets: IndexSet, from list: [Expense]) {
        let idsToDelete = offsets.map { list[$0].id }
        expenses.removeAll { idsToDelete.contains($0.id) }
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

    // MARK: - 持久化

    private func save() {
        if let data = try? JSONEncoder().encode(expenses) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([Expense].self, from: data) {
            expenses = decoded
        }
    }
}
