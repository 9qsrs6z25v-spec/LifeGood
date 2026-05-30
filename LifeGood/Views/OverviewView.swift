import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var store: ExpenseStore
    @State private var showAddVariable = false
    @State private var showAddFixed = false
    @State private var showAddStock = false
    @State private var showAddRealEstate = false
    @State private var appearedCards: Set<String> = []

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

    // 本月過了幾天 / 共幾天
    private var monthProgress: Double {
        let cal = Calendar.current
        let now = Date()
        let day = Double(cal.component(.day, from: now))
        let range = cal.range(of: .day, in: .month, for: now)
        let total = Double(range?.count ?? 30)
        return min(day / total, 1.0)
    }

    // 支出占收入比例（用於進度條）
    private var spendingRatio: Double {
        guard displayedIncome > 0 else { return 0 }
        return min(store.currentMonthTotal / displayedIncome, 1.0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    monthlyBalanceCard
                        .padding(.horizontal)

                    HStack(alignment: .top, spacing: 12) {
                        summaryCard(
                            title: isEstimated ? "收入 (預估)" : "收入",
                            amount: displayedIncome,
                            icon: "banknote.fill",
                            color: .green,
                            key: "income"
                        )
                        summaryCard(
                            title: "變動支出",
                            amount: store.currentMonthVariableTotal,
                            icon: "arrow.up.arrow.down.circle.fill",
                            color: .orange,
                            key: "variable"
                        )
                        summaryCard(
                            title: "固定支出",
                            amount: store.currentMonthFixedTotal,
                            icon: "pin.circle.fill",
                            color: .blue,
                            key: "fixed"
                        )
                    }
                    .padding(.horizontal)

                    todayCard
                        .padding(.horizontal)

                    categoryBreakdownSection

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

    // MARK: - 本月收支摘要卡片

    private var monthlyBalanceCard: some View {
        let income = displayedIncome
        let balance = income - store.currentMonthTotal
        let isPositive = balance >= 0

        return VStack(spacing: 0) {
            // 頂部：收入 vs 支出
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(isEstimated ? "本月收入（預估）" : "本月收入")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                        if isEstimated {
                            Text("預估")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.white.opacity(0.22))
                                .clipShape(Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    Text(smartCurrency(income))
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("本月支出")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                    Text(smartCurrency(store.currentMonthTotal))
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                }
            }

            // 分隔線
            Rectangle()
                .fill(.white.opacity(0.2))
                .frame(height: 0.5)
                .padding(.vertical, 14)

            // 收支餘額
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("收支餘額")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                        if isEstimated {
                            Text("預估")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.white.opacity(0.22))
                                .clipShape(Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    Text(currentMonthString())
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                Text((isPositive ? "+" : "") + smartCurrency(balance))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }

            // 支出進度條
            if income > 0 {
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.18))
                                .frame(height: 6)
                            Capsule()
                                .fill(spendingRatio > 0.9 ? Color.red.opacity(0.85) : .white.opacity(0.85))
                                .frame(width: geo.size.width * spendingRatio, height: 6)
                                .animation(.spring(response: 0.7, dampingFraction: 0.8), value: spendingRatio)
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        Text("支出 \(Int(spendingRatio * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Text("月進度 \(Int(monthProgress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.top, 12)
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.74, blue: 0.50),
                    Color(red: 0.07, green: 0.50, blue: 0.38)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.07, green: 0.50, blue: 0.38).opacity(0.40), radius: 16, x: 0, y: 8)
    }

    // MARK: - 摘要小卡

    private func summaryCard(title: String, amount: Double, icon: String, color: Color, key: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 彩色頂端條
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(height: 3)
                .padding(.bottom, 10)

            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            Text(smartCurrency(amount))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
    }

    // MARK: - 今日花費

    private var todayCard: some View {
        let cal = Calendar.current
        let day = cal.component(.day, from: Date())
        let weekday = cal.component(.weekday, from: Date())
        let weekdayStr = ["日", "一", "二", "三", "四", "五", "六"][weekday - 1]

        return HStack(spacing: 14) {
            // 日期圓形徽章
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.green.opacity(0.15), .green.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                VStack(spacing: 0) {
                    Text("\(day)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                    Text("週\(weekdayStr)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.green.opacity(0.7))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("今日花費")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(smartCurrency(store.todayTotal))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(store.todayTotal > 0 ? .primary : .secondary)
                    .contentTransition(.numericText())
            }

            Spacer()

            if store.todayTotal == 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(.green.opacity(0.6))
                    Text("今日無支出")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
    }

    // MARK: - 分類支出（帶比例條）

    private var categoryBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("本月變動支出分類")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)

            let categoryTotals = store.variableCategoryTotals()
            let maxAmount = categoryTotals.map(\.amount).max() ?? 1

            if categoryTotals.isEmpty {
                emptyPlaceholder(
                    icon: "chart.bar.xaxis",
                    title: "尚無分類紀錄",
                    subtitle: "新增變動支出後顯示分類統計"
                )
                .padding(.horizontal)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(categoryTotals.enumerated()), id: \.offset) { idx, item in
                        categoryRow(item: item, maxAmount: maxAmount)

                        if idx < categoryTotals.count - 1 {
                            Divider().padding(.leading, 46)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
                .padding(.horizontal)
            }
        }
    }

    private func categoryRow(item: (category: VariableCategory, amount: Double), maxAmount: Double) -> some View {
        let ratio = maxAmount > 0 ? item.amount / maxAmount : 0
        let totalVar = store.currentMonthVariableTotal
        let pct = totalVar > 0 ? Int(item.amount / totalVar * 100) : 0

        return VStack(spacing: 6) {
            HStack {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.10))
                        .frame(width: 30, height: 30)
                    Image(systemName: item.category.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                }
                Text(item.category.rawValue)
                    .font(.subheadline)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(smartCurrency(item.amount))
                        .font(.subheadline.bold())
                    Text("\(pct)%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // 比例進度條
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemFill))
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.green.opacity(0.7))
                        .frame(width: geo.size.width * ratio, height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - 最近交易

    private struct RecentItem: Identifiable {
        let id: UUID
        let title: String
        let icon: String
        let category: String
        let amount: Double
        let date: Date
        let isIncome: Bool
    }

    private var recentItems: [RecentItem] {
        let recentExp = store.expenses.suffix(5).map { e in
            RecentItem(id: e.id, title: e.title, icon: e.categoryIcon,
                       category: e.categoryName, amount: e.amount, date: e.date, isIncome: false)
        }
        let recentInc = store.incomes.suffix(5).map { i in
            RecentItem(id: i.id, title: i.title, icon: i.category.icon,
                       category: i.category.rawValue, amount: i.amount, date: i.date, isIncome: true)
        }
        return Array((recentExp + recentInc).sorted { $0.date > $1.date }.prefix(5))
    }

    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("最近交易")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)

            if recentItems.isEmpty {
                emptyPlaceholder(
                    icon: "list.bullet.rectangle",
                    title: "尚無交易紀錄",
                    subtitle: "新增收入或支出後顯示於此"
                )
                .padding(.horizontal)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentItems.enumerated()), id: \.element.id) { idx, item in
                        recentRow(item)

                        if idx < recentItems.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
                .padding(.horizontal)
            }
        }
    }

    private func recentRow(_ item: RecentItem) -> some View {
        let accentColor: Color = item.isIncome ? .green : .red

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: item.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(item.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(item.isIncome ? "+" : "-")\(smartCurrency(item.amount))")
                    .font(.subheadline.bold())
                    .foregroundStyle(accentColor)
                Text(formatDate(item.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - 空狀態元件

    private func emptyPlaceholder(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(.systemFill))
                    .frame(width: 64, height: 64)
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
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
