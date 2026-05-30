import SwiftUI

struct IncomeView: View {
    @EnvironmentObject var store: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var lifeStore: LifeStore
    @State private var showAdd = false
    @State private var editingItem: Income?
    @State private var selectedCategory: IncomeCategory?
    @State private var searchText: String = ""
    @State private var headerAppeared = false

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f
    }()

    private static let groupDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M月d日 EEEE"
        f.locale = Locale(identifier: "zh_TW")
        return f
    }()

    var filteredIncomes: [Income] {
        var list = store.incomes.sorted { $0.date > $1.date }
        if let cat = selectedCategory {
            list = list.filter { $0.category == cat }
        }
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter { inc in
                inc.title.lowercased().contains(q)
                    || inc.note.lowercased().contains(q)
                    || inc.category.rawValue.lowercased().contains(q)
            }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summaryHeader
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .opacity(headerAppeared ? 1 : 0)
                        .offset(y: headerAppeared ? 0 : 22)
                        .onAppear {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                                headerAppeared = true
                            }
                        }
                }
                Section {
                    categoryFilter
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if filteredIncomes.isEmpty {
                    Section {
                        emptyState
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    incomeListSections
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
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
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜尋名稱 / 備註 / 分類"
            )
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
        let isPositive = displayedBalance >= 0
        let recurringMonthly = store.incomes
            .filter { $0.period != .once }
            .reduce(0.0) { $0 + $1.monthlyAmount }

        return VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(useEstimate ? "本月收入（預估）" : "本月收入")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.78))
                        if useEstimate {
                            HStack(spacing: 3) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.system(size: 8))
                                Text("預估")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.white.opacity(0.22))
                            .clipShape(Capsule())
                            .foregroundStyle(.white)
                        }
                    }
                    Text(fmt(displayedIncome))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("收支餘額")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                    Text((isPositive ? "+" : "") + fmt(displayedBalance))
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
            }

            if useEstimate {
                HStack(spacing: 5) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                    Text("顯示近 6 個月收入中位數預估值")
                        .font(.caption2)
                    Spacer()
                }
                .foregroundStyle(.white.opacity(0.70))
                .padding(.top, 10)
            }

            if recurringMonthly > 0 {
                Rectangle()
                    .fill(.white.opacity(0.20))
                    .frame(height: 0.5)
                    .padding(.vertical, 12)

                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                    Text("固定月收入")
                        .font(.caption)
                    Spacer()
                    Text(fmt(recurringMonthly))
                        .font(.caption.bold())
                }
                .foregroundStyle(.white.opacity(0.88))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.74, blue: 0.50),
                        Color(red: 0.07, green: 0.50, blue: 0.38)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(.white.opacity(0.13))
                    .frame(width: 140, height: 140)
                    .offset(x: 90, y: -55)
                    .blur(radius: 14)
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 90, height: 90)
                    .offset(x: -70, y: 55)
                    .blur(radius: 10)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.07, green: 0.50, blue: 0.38).opacity(0.40), radius: 16, x: 0, y: 8)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
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
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color(.separator).opacity(0.22), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 1)
        }
    }

    // MARK: - 日期 Section Header（含日計合計）

    private func daySectionHeader(dateString: String, incomes: [Income]) -> some View {
        let dayTotal = incomes.reduce(0.0) { $0 + $1.amount }
        return HStack(spacing: 6) {
            Text(dateString)
            Spacer(minLength: 8)
            HStack(spacing: 3) {
                Text(fmt(dayTotal))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(red: 0.16, green: 0.74, blue: 0.50).opacity(0.9))
                Text("・\(incomes.count) 筆")
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - 空狀態

    private var emptyState: some View {
        let isSearching = !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        return VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(.systemFill), Color(.secondarySystemFill)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 84, height: 84)
                Image(systemName: isSearching ? "magnifyingglass" : "banknote")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 7) {
                Text(isSearching ? "找不到符合的收入" : "尚無收入紀錄")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(isSearching ? "換個關鍵字試試" : "點擊右上角 + 新增收入")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52)
    }

    // MARK: - 列表（List sections，包在外層的 List 內）

    @ViewBuilder
    private var incomeListSections: some View {
        ForEach(groupedByDate(), id: \.key) { dateString, incomes in
            Section(header: daySectionHeader(dateString: dateString, incomes: incomes)) {
                ForEach(incomes) { income in
                    incomeRow(income)
                        .contentShape(Rectangle())
                        .onTapGesture { editingItem = income }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                if let idx = incomes.firstIndex(where: { $0.id == income.id }) {
                                    deleteIncomes(at: IndexSet(integer: idx), from: incomes)
                                }
                            } label: { Label("刪除", systemImage: "trash") }

                            Button {
                                duplicateIncome(income)
                            } label: { Label("複製", systemImage: "doc.on.doc") }
                            .tint(.blue)
                        }
                }
            }
        }
    }

    /// 刪除收入時同步清掉股票連結與銀行存款紀錄
    private func deleteIncomes(at offsets: IndexSet, from incomes: [Income]) {
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

    /// 複製收入：欄位沿用、日期改為現在、不沿用股票配息連結（避免 1:1 配息重複連結）。
    /// 若是一次性且連結銀行帳戶，補一筆對應的入帳紀錄維持餘額正確。
    private func duplicateIncome(_ income: Income) {
        let copy = Income(
            id: UUID(),
            title: income.title,
            amount: income.amount,
            date: Date(),
            category: income.category,
            period: income.period,
            isFixedSalary: income.isFixedSalary,
            note: income.note,
            linkedStockId: nil,
            linkedBankMilestoneId: income.linkedBankMilestoneId,
            linkedBankCurrency: income.linkedBankCurrency
        )
        store.add(copy)
        // 一次性收入 + 有連結銀行 → 補一筆入帳，週期性收入靠展開不需單筆
        if copy.period == .once,
           let bankId = copy.linkedBankMilestoneId,
           var ms = lifeStore.milestones.first(where: { $0.id == bankId }) {
            var list = ms.bankDeposits ?? []
            list.append(BankDeposit(
                id: UUID(), date: copy.date, amount: copy.amount,
                currencyCode: copy.linkedBankCurrency ?? "NT$",
                isWithdrawal: false, linkedExpenseId: copy.id
            ))
            ms.bankDeposits = list
            lifeStore.update(ms)
        }
    }

    private func incomeCategoryColor(_ category: IncomeCategory) -> Color {
        switch category {
        case .salary:     return Color(red: 0.16, green: 0.74, blue: 0.50)
        case .bonus:      return Color(red: 1.00, green: 0.72, blue: 0.18)
        case .gift:       return Color(red: 1.00, green: 0.35, blue: 0.55)
        case .luck:       return Color(red: 0.68, green: 0.40, blue: 1.00)
        case .investment: return Color(red: 0.27, green: 0.67, blue: 0.99)
        }
    }

    private func incomeRow(_ income: Income) -> some View {
        let accent = incomeCategoryColor(income.category)
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.20), accent.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 42, height: 42)
                Image(systemName: income.category.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(income.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(income.category.rawValue)
                        .foregroundStyle(.secondary)
                    if income.period != .once {
                        Text(income.period.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(accent.opacity(0.12))
                            .foregroundStyle(accent)
                            .clipShape(Capsule())
                    }
                    if !income.note.isEmpty {
                        Text("· \(income.note)")
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                }
                .font(.caption)
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 3) {
                Text(fmt(income.amount))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .contentTransition(.numericText())
                if let label = depositBankLabel(for: income) {
                    HStack(spacing: 3) {
                        Image(systemName: "building.columns.fill")
                            .font(.system(size: 9))
                        Text(label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
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
        let grouped = Dictionary(grouping: filteredIncomes) { income in
            Self.groupDateFormatter.string(from: income.date)
        }

        return grouped.sorted { pair1, pair2 in
            guard let d1 = pair1.value.first?.date, let d2 = pair2.value.first?.date else { return false }
            return d1 > d2
        }
    }

    private func fmt(_ v: Double) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: v)) ?? "NT$0"
    }
}
