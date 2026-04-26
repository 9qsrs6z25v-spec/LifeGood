import SwiftUI

struct FixedExpenseView: View {
    @EnvironmentObject var store: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var lifeStore: LifeStore
    @State private var showingAddSheet = false
    @State private var expenseToEdit: Expense?

    private let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "TWD"
        f.currencySymbol = "NT$"
        f.maximumFractionDigits = 0
        return f
    }()

    var groupedByCategory: [(key: FixedCategory, value: [Expense])] {
        let now = Date()
        let grouped = Dictionary(grouping: store.fixedExpenses) { expense in
            expense.fixedCategory ?? .other
        }
        return grouped.sorted {
            $0.value.filter { $0.date <= now }.reduce(0) { $0 + $1.amount }
            > $1.value.filter { $0.date <= now }.reduce(0) { $0 + $1.amount }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 月固定支出摘要
                fixedSummaryHeader

                if store.fixedExpenses.isEmpty {
                    emptyStateView
                } else {
                    fixedExpenseList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("固定支出")
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
                AddExpenseView(expenseType: .fixed)
            }
            .sheet(item: $expenseToEdit) { expense in
                AddExpenseView(expenseType: .fixed, editingExpense: expense)
            }
        }
    }

    // MARK: - 摘要

    private var fixedSummaryHeader: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("本月固定支出")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(formatCurrency(store.currentMonthFixedTotal))
                        .font(.title2.bold())
                }
                Spacer()
                Text("\(store.fixedExpenses.count) 筆")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // 年度預估（依開始日期計算今年度剩餘期數）
            let yearlyEstimate = store.fixedExpenses.reduce(0.0) { total, expense in
                total + expense.amount * Double(occurrencesThisYear(for: expense))
            }

            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
                Text("年度預估固定支出：\(formatCurrency(yearlyEstimate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)
            .background(Color.blue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding()
        .background(Color(.systemBackground))
    }

    // MARK: - 空狀態

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "pin.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("尚無固定支出紀錄")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("點擊右上角 + 新增固定支出")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 列表

    private var fixedExpenseList: some View {
        List {
            ForEach(groupedByCategory, id: \.key) { category, expenses in
                Section(header: categoryHeader(category: category, expenses: expenses)) {
                    ForEach(expenses) { expense in
                        FixedExpenseRow(expense: expense)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                expenseToEdit = expense
                            }
                    }
                    .onDelete { offsets in
                        deleteWithSync(offsets: offsets, from: expenses)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func categoryHeader(category: FixedCategory, expenses: [Expense]) -> some View {
        let now = Date()
        let activeExpenses = expenses.filter { $0.date <= now }

        return HStack {
            Image(systemName: category.icon)
            Text(category.rawValue)
            Spacer()
            if category == .insurance {
                insuranceHeaderAmount(activeExpenses)
            } else {
                Text(formatCurrency(activeExpenses.reduce(0) { $0 + monthlyEquivalent($1) }))
                    .font(.caption.bold())
            }
        }
    }

    @ViewBuilder
    private func insuranceHeaderAmount(_ expenses: [Expense]) -> some View {
        let byCurrency = Dictionary(grouping: expenses) { $0.currencyCode }
        let parts = byCurrency.sorted(by: { $0.key < $1.key }).map { (code, exps) -> String in
            let total = exps.reduce(0.0) { $0 + monthlyEquivalent($1) }
            return formatCurrencyWithCode(total, code: code)
        }
        Text(parts.joined(separator: " + "))
            .font(.caption.bold())
    }

    private func monthlyEquivalent(_ expense: Expense) -> Double {
        switch expense.recurrence {
        case .monthly: return expense.amount
        case .quarterly: return expense.amount / 3
        case .yearly: return expense.amount / 12
        case .none: return expense.amount
        }
    }

    private func formatCurrencyWithCode(_ value: Double, code: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        if code == "NT$" || code == "TWD" {
            f.currencySymbol = "NT$"
        } else {
            f.currencySymbol = "\(code) "
        }
        return f.string(from: NSNumber(value: value)) ?? "\(code) 0"
    }

    /// 刪除固定支出時同步刪除理財連結項目
    private func deleteWithSync(offsets: IndexSet, from list: [Expense]) {
        for index in offsets {
            let expense = list[index]
            // 解除連結的儲蓄險（僅清除連結，不刪除整筆儲蓄險）
            if let linkedId = expense.linkedInsuranceId,
               var ins = financeStore.insurances.first(where: { $0.id == linkedId }) {
                if ins.linkedExpenseId == expense.id {
                    ins.linkedExpenseId = nil
                    financeStore.update(ins)
                }
            }
            // 刪除房地產中對應的貸款/已支出/變動支出項目（不刪除整筆房地產）
            if let linkedId = expense.linkedRealEstateId,
               var re = financeStore.realEstates.first(where: { $0.id == linkedId }) {
                re.mortgageItems.removeAll { $0.linkedExpenseId == expense.id }
                re.paidItems.removeAll { $0.linkedExpenseId == expense.id }
                re.variableExpenses.removeAll { $0.linkedExpenseId == expense.id }
                re.insuranceItems.removeAll { $0.linkedExpenseId == expense.id }
                re.propertyAssets.removeAll { $0.linkedExpenseId == expense.id }
                financeStore.update(re)
            }
            // 刪除連結的汽車定期支出項目
            if let linkedId = expense.linkedVehicleId,
               var vehicle = financeStore.vehicles.first(where: { $0.id == linkedId }) {
                vehicle.fixedExpenses.removeAll { $0.linkedExpenseId == expense.id }
                financeStore.update(vehicle)
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

    private func formatCurrency(_ value: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: value)) ?? "NT$0"
    }

    /// 依開始日期與週期，估算該筆固定支出在當年度內發生的次數
    private func occurrencesThisYear(for expense: Expense) -> Int {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        guard let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let yearEnd = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) else {
            return 0
        }
        let effectiveStart = max(expense.date, yearStart)
        if effectiveStart > yearEnd { return 0 }

        switch expense.recurrence {
        case .monthly:
            let months = calendar.dateComponents([.month], from: effectiveStart, to: yearEnd).month ?? 0
            return max(0, months + 1)
        case .quarterly:
            let months = calendar.dateComponents([.month], from: effectiveStart, to: yearEnd).month ?? 0
            return max(0, months / 3 + 1)
        case .yearly:
            return expense.date <= yearEnd ? 1 : 0
        case .none:
            return expense.date <= yearEnd ? 1 : 0
        }
    }
}

// MARK: - 固定支出列

struct FixedExpenseRow: View {
    @EnvironmentObject var lifeStore: LifeStore
    let expense: Expense

    private let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "TWD"
        f.currencySymbol = "NT$"
        f.maximumFractionDigits = 0
        return f
    }()

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 4) {
                    if let recurrence = expense.recurrence {
                        Text(recurrence.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                    if !expense.note.isEmpty {
                        Text(expense.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formattedAmount)
                    .font(.subheadline.bold())
                    .foregroundStyle(.red)
                if let label = deductionTargetLabel {
                    HStack(spacing: 3) {
                        Image(systemName: deductionIcon)
                            .font(.caption2)
                        Text(label).font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var formattedAmount: String {
        let code = expense.currencyCode
        if code != "NT$" && code != "TWD" && !code.isEmpty {
            let f = NumberFormatter()
            f.numberStyle = .currency
            f.currencySymbol = "\(code) "
            f.maximumFractionDigits = 0
            return f.string(from: NSNumber(value: expense.amount)) ?? "\(code) 0"
        }
        return formatCurrency(expense.amount)
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
}

#Preview {
    FixedExpenseView()
        .environmentObject(ExpenseStore())
}
