import SwiftUI

struct VariableExpenseView: View {
    @EnvironmentObject var store: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var lifeStore: LifeStore
    @State private var showingAddSheet = false
    @State private var selectedCategory: VariableCategory?
    @State private var expenseToEdit: Expense?
    @State private var visibleWeeks = 1
    @State private var searchText: String = ""

    private static let groupDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M月d日 EEEE"
        f.locale = Locale(identifier: "zh_TW")
        return f
    }()

    private let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "TWD"
        f.currencySymbol = "NT$"
        f.maximumFractionDigits = 0
        return f
    }()

    var filteredExpenses: [Expense] {
        var list = store.variableExpenses
        if let category = selectedCategory {
            list = list.filter { $0.variableCategory == category }
        }
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter { exp in
                exp.title.lowercased().contains(q)
                    || exp.note.lowercased().contains(q)
                    || exp.categoryName.lowercased().contains(q)
                    || (exp.placeAddress?.lowercased().contains(q) ?? false)
                    || (exp.diningMember?.lowercased().contains(q) ?? false)
                    || (exp.socialRecipient?.lowercased().contains(q) ?? false)
                    || (exp.taxSavingSubCategory?.rawValue.lowercased().contains(q) ?? false)
                    || (exp.socialSubCategory?.rawValue.lowercased().contains(q) ?? false)
            }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    monthSummaryHeader
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                Section {
                    categoryFilter
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if filteredExpenses.isEmpty {
                    Section {
                        emptyStateView
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    expenseListSections
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("變動支出")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddExpenseView(expenseType: .variable)
            }
            .sheet(item: $expenseToEdit) { expense in
                AddExpenseView(expenseType: .variable, editingExpense: expense)
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜尋名稱 / 備註 / 分類 / 地點"
            )
        }
    }

    // MARK: - 月摘要

    private var monthProgress: Double {
        let cal = Calendar.current
        let now = Date()
        let day = Double(cal.component(.day, from: now))
        let total = Double(cal.range(of: .day, in: .month, for: now)?.count ?? 30)
        return min(day / total, 1.0)
    }

    private var monthSummaryHeader: some View {
        let count = store.currentMonthExpenses.filter { $0.expenseType == .variable }.count
        let total = store.currentMonthVariableTotal
        let dayOfMonth = Calendar.current.component(.day, from: Date())
        let dailyAvg = total / Double(max(dayOfMonth, 1))

        return VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("本月變動支出")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.80))
                    Text(formatCurrency(total))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    if total > 0 {
                        Text("日均 " + formatCurrency(dailyAvg))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.top, 1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(count) 筆")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.22))
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                }
            }

            // 月進度條
            VStack(spacing: 5) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.18))
                            .frame(height: 5)
                        Capsule()
                            .fill(.white.opacity(0.80))
                            .frame(width: geo.size.width * monthProgress, height: 5)
                            .animation(.spring(response: 0.7, dampingFraction: 0.8), value: monthProgress)
                    }
                }
                .frame(height: 5)
                HStack {
                    Text("本月進度 \(Int(monthProgress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.60))
                    Spacer()
                    Text("剩 \(Int((1 - monthProgress) * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.60))
                }
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.62, blue: 0.22),
                        Color(red: 0.86, green: 0.36, blue: 0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // 裝飾性散景圓
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 120, height: 120)
                    .offset(x: 80, y: -45)
                    .blur(radius: 12)
                Circle()
                    .fill(.white.opacity(0.07))
                    .frame(width: 70, height: 70)
                    .offset(x: -60, y: 40)
                    .blur(radius: 8)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.86, green: 0.36, blue: 0.06).opacity(0.38), radius: 14, x: 0, y: 7)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    // MARK: - 分類篩選

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "全部", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }

                ForEach(VariableCategory.allCases) { category in
                    FilterChip(
                        title: category.rawValue,
                        icon: category.icon,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - 空狀態

    private var emptyStateView: some View {
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
                Image(systemName: isSearching ? "magnifyingglass" : "bag")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 7) {
                Text(isSearching ? "找不到符合的支出" : "尚無變動支出紀錄")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(isSearching ? "換個關鍵字試試" : "點擊右上角 + 新增第一筆支出")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52)
    }

    // MARK: - 支出列表（List sections，包在外層的 List 內）

    @ViewBuilder
    private var expenseListSections: some View {
        let allGroups = groupedByDate()
        let isSearching = !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        let cutoff = Calendar.current.date(byAdding: .day, value: -7 * visibleWeeks, to: Date()) ?? Date()
        // 搜尋時不限制週數，顯示所有符合的結果
        let visibleGroups = isSearching ? allGroups : allGroups.filter { group in
            guard let d = group.value.first?.date else { return false }
            return d >= cutoff
        }
        let hiddenGroups: [(key: String, value: [Expense])] = isSearching ? [] : allGroups.filter { group in
            guard let d = group.value.first?.date else { return true }
            return d < cutoff
        }
        let hiddenCount = hiddenGroups.reduce(0) { $0 + $1.value.count }

        ForEach(visibleGroups, id: \.key) { dateString, expenses in
            Section(header: Text(dateString)) {
                ForEach(expenses) { expense in
                    ExpenseRow(expense: expense)
                        .contentShape(Rectangle())
                        .onTapGesture { expenseToEdit = expense }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                if let idx = expenses.firstIndex(where: { $0.id == expense.id }) {
                                    deleteWithSync(offsets: IndexSet(integer: idx), from: expenses)
                                }
                            } label: { Label("刪除", systemImage: "trash") }

                            Button {
                                duplicateExpense(expense)
                            } label: { Label("複製", systemImage: "doc.on.doc") }
                            .tint(.blue)
                        }
                }
            }
        }

        if hiddenCount > 0 {
            Section {
                Button {
                    withAnimation { visibleWeeks += 1 }
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "chevron.down").font(.caption2)
                        Text("展開更早一週（剩 \(hiddenCount) 筆）")
                            .font(.caption.weight(.medium))
                        Spacer()
                    }
                    .foregroundStyle(.green)
                }
            }
        }
    }

    /// 刪除變動支出時同步刪除理財連結項目
    private func deleteWithSync(offsets: IndexSet, from list: [Expense]) {
        for index in offsets {
            let expense = list[index]
            // 同步刪除汽車變動支出
            if let vehicleId = expense.linkedVehicleId,
               var vehicle = financeStore.vehicles.first(where: { $0.id == vehicleId }) {
                vehicle.variableExpenses.removeAll { $0.linkedExpenseId == expense.id }
                financeStore.update(vehicle)
            }
            // 同步刪除房地產變動支出與水電瓦斯繳費紀錄
            if let reId = expense.linkedRealEstateId,
               var re = financeStore.realEstates.first(where: { $0.id == reId }) {
                re.variableExpenses.removeAll { $0.linkedExpenseId == expense.id }
                re.utilityPayments.removeAll { $0.linkedExpenseId == expense.id }
                financeStore.update(re)
            }
            // 同步解除股票連結
            if let stockId = expense.linkedStockId,
               var stock = financeStore.stocks.first(where: { $0.id == stockId }) {
                stock.linkedExpenseId = nil
                financeStore.update(stock)
            }
            // 同步刪除銀行扣款記錄
            if let bankId = expense.linkedBankMilestoneId,
               var ms = lifeStore.milestones.first(where: { $0.id == bankId }) {
                ms.bankDeposits?.removeAll { $0.linkedExpenseId == expense.id }
                lifeStore.update(ms)
            }
        }
        store.delete(at: offsets, from: list)
    }

    /// 複製支出：全部欄位複製，日期改為現在
    private func duplicateExpense(_ expense: Expense) {
        let copy = Expense(
            id: UUID(),
            title: expense.title,
            amount: expense.amount,
            date: Date(),
            expenseType: expense.expenseType,
            variableCategory: expense.variableCategory,
            fixedCategory: expense.fixedCategory,
            recurrence: expense.recurrence,
            insuranceSubCategory: expense.insuranceSubCategory,
            loanSubCategory: expense.loanSubCategory,
            linkedInsuranceId: expense.linkedInsuranceId,
            linkedStockId: expense.linkedStockId,
            linkedRealEstateId: expense.linkedRealEstateId,
            linkedVehicleId: expense.linkedVehicleId,
            vehicleExpenseCategory: expense.vehicleExpenseCategory,
            realEstateExpenseCategory: expense.realEstateExpenseCategory,
            taxSavingSubCategory: expense.taxSavingSubCategory,
            socialSubCategory: expense.socialSubCategory,
            socialRecipient: expense.socialRecipient,
            taxDeductibleOverride: expense.taxDeductibleOverride,
            note: expense.note,
            currencyCode: expense.currencyCode,
            diningMember: expense.diningMember,
            linkedBankMilestoneId: expense.linkedBankMilestoneId,
            linkedBankCurrency: expense.linkedBankCurrency,
            linkedCreditCardMilestoneId: expense.linkedCreditCardMilestoneId,
            placeAddress: expense.placeAddress,
            placeLatitude: expense.placeLatitude,
            placeLongitude: expense.placeLongitude
        )
        store.add(copy)
    }

    // MARK: - 依日期分組

    private func groupedByDate() -> [(key: String, value: [Expense])] {
        let grouped = Dictionary(grouping: filteredExpenses) { expense in
            Self.groupDateFormatter.string(from: expense.date)
        }

        return grouped.sorted { pair1, pair2 in
            guard let date1 = pair1.value.first?.date,
                  let date2 = pair2.value.first?.date else { return false }
            return date1 > date2
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: value)) ?? "NT$0"
    }
}

// MARK: - 篩選標籤

struct FilterChip: View {
    let title: String
    var icon: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(isSelected ? Color.green : Color(.secondarySystemFill))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
            .shadow(
                color: isSelected ? Color.green.opacity(0.30) : .clear,
                radius: 6, x: 0, y: 3
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.04 : 1.0)
        .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isSelected)
    }
}

// MARK: - 支出列

struct ExpenseRow: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var store: ExpenseStore
    let expense: Expense

    private let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "TWD"
        f.currencySymbol = "NT$"
        f.maximumFractionDigits = 0
        return f
    }()

    private var categoryAccent: Color {
        expense.variableCategory?.accentColor ?? .secondary
    }

    var body: some View {
        HStack(spacing: 12) {
            // 分類圖示圓
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [categoryAccent.opacity(0.18), categoryAccent.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                Image(systemName: expense.categoryIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(categoryAccent)
            }

            // 標題 + 副資訊
            VStack(alignment: .leading, spacing: 3) {
                Text(expense.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                // 分類 + 備註
                HStack(spacing: 0) {
                    Text(expense.categoryName)
                        .foregroundStyle(.secondary)
                    if !expense.note.isEmpty {
                        Text(" · ")
                            .foregroundStyle(Color(.tertiaryLabel))
                        Text(expense.note)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .lineLimit(1)

                // 扣款帳戶標籤（信用卡 / 銀行）
                if let label = deductionTargetLabel {
                    HStack(spacing: 3) {
                        Image(systemName: deductionIcon)
                        Text(label)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(categoryAccent.opacity(0.85))
                    .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            // 金額 + 同行者
            VStack(alignment: .trailing, spacing: 3) {
                Text(formattedAmount)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.92, green: 0.28, blue: 0.28))
                    .contentTransition(.numericText())

                if let member = expense.diningMember, !member.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 9))
                        Text(member)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.orange.opacity(0.85))
                    .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var deductionIcon: String {
        expense.linkedCreditCardMilestoneId != nil ? "creditcard.fill" : "building.columns.fill"
    }

    private var deductionTargetLabel: String? {
        if let cardId = expense.linkedCreditCardMilestoneId,
           let card = lifeStore.milestones.first(where: { $0.id == cardId }) {
            return card.cardName ?? card.title
        }
        if let bankId = expense.linkedBankMilestoneId,
           let ms = lifeStore.milestones.first(where: { $0.id == bankId }) {
            let name = ms.bankName ?? ms.title
            let currency = expense.linkedBankCurrency ?? "NT$"
            return currency == "NT$" ? name : "\(name) · \(currency)"
        }
        return nil
    }

    private func formatCurrency(_ value: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: value)) ?? "NT$0"
    }

    /// 顯示用金額：外幣時將儲存的台幣等值除以匯率還原原幣金額
    private var formattedAmount: String {
        let code = expense.currencyCode
        if code != "NT$" && code != "TWD" && !code.isEmpty {
            let displayAmount: Double
            if let rate = store.currencyRates.first(where: { $0.code == code }), rate.rate > 0 {
                displayAmount = expense.amount / rate.rate
            } else {
                displayAmount = expense.amount
            }
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.maximumFractionDigits = 0
            let str = f.string(from: NSNumber(value: displayAmount)) ?? "0"
            return "\(code) \(str)"
        }
        return formatCurrency(expense.amount)
    }
}

#Preview {
    VariableExpenseView()
        .environmentObject(ExpenseStore())
}
