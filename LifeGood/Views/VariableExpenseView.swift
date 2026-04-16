import SwiftUI

struct VariableExpenseView: View {
    @EnvironmentObject var store: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @State private var showingAddSheet = false
    @State private var selectedCategory: VariableCategory?
    @State private var expenseToEdit: Expense?

    private let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "TWD"
        f.currencySymbol = "NT$"
        f.maximumFractionDigits = 0
        return f
    }()

    var filteredExpenses: [Expense] {
        if let category = selectedCategory {
            return store.variableExpenses.filter { $0.variableCategory == category }
        }
        return store.variableExpenses
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 本月變動支出摘要
                monthSummaryHeader

                // 分類篩選
                categoryFilter

                // 支出列表
                if filteredExpenses.isEmpty {
                    emptyStateView
                } else {
                    expenseList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("變動支出")
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
        }
    }

    // MARK: - 月摘要

    private var monthSummaryHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("本月變動支出")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(formatCurrency(store.currentMonthVariableTotal))
                    .font(.title2.bold())
            }
            Spacer()
            Text("\(store.currentMonthExpenses.filter { $0.expenseType == .variable }.count) 筆")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
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
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("尚無變動支出紀錄")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("點擊右上角 + 新增支出")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 支出列表

    private var expenseList: some View {
        List {
            ForEach(groupedByDate(), id: \.key) { dateString, expenses in
                Section(header: Text(dateString)) {
                    ForEach(expenses) { expense in
                        ExpenseRow(expense: expense)
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

    /// 刪除變動支出時同步刪除理財連結項目
    private func deleteWithSync(offsets: IndexSet, from list: [Expense]) {
        for index in offsets {
            let expense = list[index]
            if let vehicleId = expense.linkedVehicleId,
               var vehicle = financeStore.vehicles.first(where: { $0.id == vehicleId }) {
                vehicle.variableExpenses.removeAll { $0.linkedExpenseId == expense.id }
                financeStore.update(vehicle)
            }
        }
        store.delete(at: offsets, from: list)
    }

    // MARK: - 依日期分組

    private func groupedByDate() -> [(key: String, value: [Expense])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 EEEE"
        formatter.locale = Locale(identifier: "zh_TW")

        let grouped = Dictionary(grouping: filteredExpenses) { expense in
            formatter.string(from: expense.date)
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
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.green : Color(.systemGray5))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
    }
}

// MARK: - 支出列

struct ExpenseRow: View {
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
            Image(systemName: expense.categoryIcon)
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 36, height: 36)
                .background(Color.green.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 4) {
                    Text(expense.categoryName)
                    if !expense.note.isEmpty {
                        Text("· \(expense.note)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            Text(formatCurrency(expense.amount))
                .font(.subheadline.bold())
                .foregroundStyle(.red)
        }
        .padding(.vertical, 2)
    }

    private func formatCurrency(_ value: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: value)) ?? "NT$0"
    }
}

#Preview {
    VariableExpenseView()
        .environmentObject(ExpenseStore())
}
