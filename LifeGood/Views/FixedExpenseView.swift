import SwiftUI

struct FixedExpenseView: View {
    @EnvironmentObject var store: ExpenseStore
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
        let grouped = Dictionary(grouping: store.fixedExpenses) { expense in
            expense.fixedCategory ?? .other
        }
        return grouped.sorted { $0.value.reduce(0) { $0 + $1.amount } > $1.value.reduce(0) { $0 + $1.amount } }
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

            // 年度預估
            let yearlyEstimate = store.fixedExpenses.reduce(0.0) { total, expense in
                switch expense.recurrence {
                case .monthly: return total + expense.amount * 12
                case .quarterly: return total + expense.amount * 4
                case .yearly: return total + expense.amount
                case .none: return total + expense.amount
                }
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
                        store.delete(at: offsets, from: expenses)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func categoryHeader(category: FixedCategory, expenses: [Expense]) -> some View {
        HStack {
            Image(systemName: category.icon)
            Text(category.rawValue)
            Spacer()
            Text(formatCurrency(expenses.reduce(0) { $0 + $1.amount }))
                .font(.caption.bold())
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: value)) ?? "NT$0"
    }
}

// MARK: - 固定支出列

struct FixedExpenseRow: View {
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
    FixedExpenseView()
        .environmentObject(ExpenseStore())
}
