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

    var currentMonthTotal: Double {
        currentMonthExpenses.reduce(0) { $0 + $1.amount }
    }

    var currentMonthVariableTotal: Double {
        currentMonthExpenses
            .filter { $0.expenseType == .variable }
            .reduce(0) { $0 + $1.amount }
    }

    var currentMonthFixedTotal: Double {
        currentMonthExpenses
            .filter { $0.expenseType == .fixed }
            .reduce(0) { $0 + $1.amount }
    }

    // MARK: - 今日統計

    var todayTotal: Double {
        let calendar = Calendar.current
        let today = Date()
        return expenses
            .filter { calendar.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.amount }
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
            let total = expenses
                .filter { calendar.isDate($0.date, inSameDayAs: startOfDay) }
                .reduce(0) { $0 + $1.amount }
            results.append(ChartDataPoint(
                label: formatter.string(from: date),
                amount: total,
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
            let total = expenses
                .filter { $0.date >= startOfWeek && $0.date < weekEnd }
                .reduce(0) { $0 + $1.amount }
            results.append(ChartDataPoint(
                label: formatter.string(from: startOfWeek),
                amount: total,
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
            let total = expenses
                .filter { calendar.isDate($0.date, equalTo: date, toGranularity: .month) }
                .reduce(0) { $0 + $1.amount }
            results.append(ChartDataPoint(
                label: formatter.string(from: date),
                amount: total,
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

            let total = expenses.filter { expense in
                let expQuarter = (calendar.component(.month, from: expense.date) - 1) / 3 + 1
                let expYear = calendar.component(.year, from: expense.date)
                return expQuarter == quarter && expYear == year
            }.reduce(0) { $0 + $1.amount }

            results.append(ChartDataPoint(
                label: "\(year)Q\(quarter)",
                amount: total,
                date: date
            ))
        }
        return results
    }

    private func yearlyData(calendar: Calendar, now: Date) -> [ChartDataPoint] {
        var results: [ChartDataPoint] = []
        for yearOffset in (0..<5).reversed() {
            guard let date = calendar.date(byAdding: .year, value: -yearOffset, to: now) else { continue }
            let total = expenses
                .filter { calendar.isDate($0.date, equalTo: date, toGranularity: .year) }
                .reduce(0) { $0 + $1.amount }
            let year = calendar.component(.year, from: date)
            results.append(ChartDataPoint(
                label: "\(year)",
                amount: total,
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
