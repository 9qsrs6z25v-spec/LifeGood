import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var store: ExpenseStore
    @State private var showAddVariable = false
    @State private var showAddFixed = false
    @State private var showAddStock = false
    @State private var showAddRealEstate = false

    private let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "TWD"
        f.currencySymbol = "NT$"
        f.maximumFractionDigits = 0
        return f
    }()

    private var displayedIncome: Double {
        store.hasCurrentMonthIncome ? store.currentMonthIncomeTotal : store.estimatedMonthlyIncome
    }

    private var isEstimated: Bool {
        !store.hasCurrentMonthIncome && store.estimatedMonthlyIncome > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 本月收支摘要
                    monthlyBalanceCard

                    // 收支分類摘要
                    HStack(alignment: .top, spacing: 12) {
                        summaryCard(
                            title: isEstimated ? "收入 (預估)" : "收入",
                            amount: displayedIncome,
                            icon: "banknote.fill",
                            color: .green
                        )
                        summaryCard(
                            title: "變動支出",
                            amount: store.currentMonthVariableTotal,
                            icon: "arrow.up.arrow.down.circle.fill",
                            color: .orange
                        )
                        summaryCard(
                            title: "固定支出",
                            amount: store.currentMonthFixedTotal,
                            icon: "pin.circle.fill",
                            color: .blue
                        )
                    }
                    .padding(.horizontal)

                    // 今日花費
                    todayCard

                    // 本月分類支出
                    categoryBreakdownSection

                    // 最近交易
                    recentTransactionsSection
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("總覽")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    quickAddMenu
                }
            }
            .sheet(isPresented: $showAddVariable) { AddExpenseView(expenseType: .variable) }
            .sheet(isPresented: $showAddFixed) { AddExpenseView(expenseType: .fixed) }
            .sheet(isPresented: $showAddStock) { AddStockView() }
            .sheet(isPresented: $showAddRealEstate) { AddRealEstateView() }
        }
    }

    private var quickAddMenu: some View {
        Menu {
            Button { showAddVariable = true } label: { Label("變動支出", systemImage: "arrow.up.arrow.down.circle.fill") }
            Button { showAddFixed = true } label: { Label("固定支出", systemImage: "pin.circle.fill") }
            Button { showAddStock = true } label: { Label("股票", systemImage: "chart.line.uptrend.xyaxis") }
            Button { showAddRealEstate = true } label: { Label("房地產", systemImage: "building.2.fill") }
        } label: {
            Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
        }
    }

    // MARK: - 本月收支摘要

    private var monthlyBalanceCard: some View {
        VStack(spacing: 12) {
            let income = displayedIncome
            let balance = income - store.currentMonthTotal
            let isPositive = balance >= 0

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("本月收入").font(.caption).foregroundStyle(.white.opacity(0.7))
                        if isEstimated {
                            Text("預估")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color.white.opacity(0.25))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .foregroundStyle(.white)
                        }
                    }
                    Text(smartCurrency(income))
                        .font(.title3.bold()).foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("本月支出").font(.caption).foregroundStyle(.white.opacity(0.7))
                    Text(smartCurrency(store.currentMonthTotal))
                        .font(.title3.bold()).foregroundStyle(.white)
                }
            }

            Divider().background(.white.opacity(0.3))

            HStack {
                HStack(spacing: 4) {
                    Text("收支餘額").font(.subheadline).foregroundStyle(.white.opacity(0.8))
                    if isEstimated {
                        Text("預估")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.white.opacity(0.25))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(.white)
                    }
                }
                Spacer()
                Text((isPositive ? "+" : "") + smartCurrency(balance))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            Text(currentMonthString())
                .font(.caption).foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.green, Color.green.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 摘要卡片

    private func summaryCard(title: String, amount: Double, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text(smartCurrency(amount))
                .font(.title3.bold())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }

    // MARK: - 今日花費

    private var todayCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("今日花費")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(smartCurrency(store.todayTotal))
                    .font(.title2.bold())
            }
            Spacer()
            Image(systemName: "calendar")
                .font(.title2)
                .foregroundStyle(.green)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        .padding(.horizontal)
    }

    // MARK: - 分類支出

    private var categoryBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本月變動支出分類")
                .font(.headline)
                .padding(.horizontal)

            let categoryTotals = store.variableCategoryTotals()

            if categoryTotals.isEmpty {
                Text("尚無資料")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(categoryTotals.enumerated()), id: \.offset) { _, item in
                        HStack {
                            Image(systemName: item.category.icon)
                                .frame(width: 30)
                                .foregroundStyle(.green)
                            Text(item.category.rawValue)
                                .font(.subheadline)
                            Spacer()
                            Text(smartCurrency(item.amount))
                                .font(.subheadline.bold())
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)

                        if item.category != categoryTotals.last?.category {
                            Divider().padding(.leading, 50)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
                .padding(.horizontal)
            }
        }
    }

    // MARK: - 最近交易

    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近交易")
                .font(.headline)
                .padding(.horizontal)

            let recent = Array(store.expenses.sorted { $0.date > $1.date }.prefix(5))

            if recent.isEmpty {
                Text("尚無交易紀錄")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(recent) { expense in
                        HStack {
                            Image(systemName: expense.categoryIcon)
                                .frame(width: 30)
                                .foregroundStyle(.green)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(expense.title)
                                    .font(.subheadline)
                                Text(expense.categoryName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(smartCurrency(expense.amount))
                                    .font(.subheadline.bold())
                                Text(formatDate(expense.date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)

                        if expense.id != recent.last?.id {
                            Divider().padding(.leading, 50)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: value)) ?? "NT$0"
    }

    private func smartCurrency(_ value: Double) -> String {
        if abs(value) >= 10000 {
            let wan = value / 10000
            if abs(wan) >= 10 {
                return String(format: "%.1f 萬", wan)
            } else {
                return String(format: "%.2f 萬", wan)
            }
        }
        return formatCurrency(value)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    private func currentMonthString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: Date())
    }
}

#Preview {
    OverviewView()
        .environmentObject(ExpenseStore())
}
