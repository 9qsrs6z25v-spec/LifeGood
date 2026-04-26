import SwiftUI

struct IncomeView: View {
    @EnvironmentObject var store: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var lifeStore: LifeStore
    @State private var showAdd = false
    @State private var editingItem: Income?
    @State private var selectedCategory: IncomeCategory?

    private let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f
    }()

    var filteredIncomes: [Income] {
        let sorted = store.incomes.sorted { $0.date > $1.date }
        if let cat = selectedCategory {
            return sorted.filter { $0.category == cat }
        }
        return sorted
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryHeader
                categoryFilter

                if filteredIncomes.isEmpty {
                    emptyState
                } else {
                    incomeList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("收入")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("總收入")
                                .font(.caption2).foregroundStyle(.secondary)
                            Text("\(fmtWan(totalIncomeAll)) 萬")
                                .font(.subheadline.bold()).foregroundStyle(.green)
                        }
                        Button { showAdd = true } label: {
                            Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                        }
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddIncomeView() }
            .sheet(item: $editingItem) { item in AddIncomeView(editing: item) }
        }
    }

    /// 所有收入加總（含已繳的固定薪水展開到每一個已發生月份）
    private var totalIncomeAll: Double {
        let calendar = Calendar.current
        let now = Date()
        return store.incomes.reduce(0.0) { sum, income in
            switch income.period {
            case .once:
                return sum + income.amount
            case .monthly:
                let months = calendar.dateComponents([.month], from: income.date, to: now).month ?? 0
                return sum + income.amount * Double(max(1, months + 1))
            case .yearly:
                let years = calendar.dateComponents([.year], from: income.date, to: now).year ?? 0
                return sum + income.amount * Double(max(1, years + 1))
            }
        }
    }

    private func fmtWan(_ v: Double) -> String {
        String(format: "%.0f", v / 10000)
    }

    // MARK: - 摘要

    private var summaryHeader: some View {
        let useEstimate = !store.hasCurrentMonthIncome && store.estimatedMonthlyIncome > 0
        let displayedIncome = useEstimate ? store.estimatedMonthlyIncome : store.currentMonthIncomeTotal
        let displayedBalance = displayedIncome - store.currentMonthTotal

        return VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(useEstimate ? "本月收入（預估）" : "本月收入")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if useEstimate {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.caption2).foregroundStyle(.orange)
                        }
                    }
                    Text(fmt(displayedIncome))
                        .font(.title2.bold())
                        .foregroundStyle(useEstimate ? .orange : .green)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("收支餘額")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(fmt(displayedBalance))
                        .font(.title3.bold())
                        .foregroundStyle(displayedBalance >= 0 ? .green : .red)
                }
            }

            if useEstimate {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.orange)
                    Text("本月尚無收入紀錄，顯示近 6 個月中位數預估")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(10)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // 週期收入摘要
            let recurringMonthly = store.incomes
                .filter { $0.period != .once }
                .reduce(0.0) { $0 + $1.monthlyAmount }
            if recurringMonthly > 0 {
                HStack {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.blue)
                    Text("固定月收入：\(fmt(recurringMonthly))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(10)
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }

    // MARK: - 篩選

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "全部", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(IncomeCategory.allCases) { cat in
                    FilterChip(title: cat.rawValue, icon: cat.icon, isSelected: selectedCategory == cat) {
                        selectedCategory = cat
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - 空狀態

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "banknote").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("尚無收入紀錄").font(.headline).foregroundStyle(.secondary)
            Text("點擊右上角 + 新增收入").font(.subheadline).foregroundStyle(.tertiary)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    // MARK: - 列表

    private var incomeList: some View {
        List {
            ForEach(groupedByDate(), id: \.key) { dateString, incomes in
                Section(header: Text(dateString)) {
                    ForEach(incomes) { income in
                        incomeRow(income)
                            .contentShape(Rectangle())
                            .onTapGesture { editingItem = income }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            let income = incomes[index]
                            if let stockId = income.linkedStockId,
                               var stock = financeStore.stocks.first(where: { $0.id == stockId }) {
                                stock.linkedIncomeId = nil
                                financeStore.update(stock)
                            }
                            if let bankId = income.linkedBankMilestoneId,
                               var ms = lifeStore.milestones.first(where: { $0.id == bankId }) {
                                ms.bankDeposits?.removeAll { $0.linkedExpenseId == income.id }
                                lifeStore.update(ms)
                            }
                        }
                        store.deleteIncome(at: offsets, from: incomes)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func incomeRow(_ income: Income) -> some View {
        HStack {
            Image(systemName: income.category.icon)
                .font(.title3).foregroundStyle(.green)
                .frame(width: 36, height: 36)
                .background(Color.green.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(income.title).font(.subheadline.weight(.medium))
                HStack(spacing: 4) {
                    Text(income.category.rawValue)
                    if income.period != .once {
                        Text(income.period.rawValue)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    if !income.note.isEmpty {
                        Text("- \(income.note)")
                    }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(fmt(income.amount))
                    .font(.subheadline.bold()).foregroundStyle(.green)
                if let label = depositBankLabel(for: income) {
                    HStack(spacing: 3) {
                        Image(systemName: "building.columns.fill")
                            .font(.caption2)
                        Text(label).font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func depositBankLabel(for income: Income) -> String? {
        guard let bankId = income.linkedBankMilestoneId,
              let ms = lifeStore.milestones.first(where: { $0.id == bankId }) else { return nil }
        let name = ms.bankName ?? ms.title
        let currency = income.linkedBankCurrency ?? "NT$"
        return currency == "NT$" ? name : "\(name) · \(currency)"
    }

    // MARK: - 分組

    private func groupedByDate() -> [(key: String, value: [Income])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 EEEE"
        formatter.locale = Locale(identifier: "zh_TW")

        let grouped = Dictionary(grouping: filteredIncomes) { income in
            formatter.string(from: income.date)
        }

        return grouped.sorted { pair1, pair2 in
            guard let d1 = pair1.value.first?.date, let d2 = pair2.value.first?.date else { return false }
            return d1 > d2
        }
    }

    private func fmt(_ v: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: v)) ?? "NT$0"
    }
}
