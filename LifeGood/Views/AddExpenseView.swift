import SwiftUI

struct AddExpenseView: View {
    @EnvironmentObject var store: ExpenseStore
    @Environment(\.dismiss) private var dismiss

    let expenseType: ExpenseType
    var editingExpense: Expense?

    @State private var title = ""
    @State private var amountText = ""
    @State private var date = Date()
    @State private var selectedVariableCategory: VariableCategory = .food
    @State private var selectedFixedCategory: FixedCategory = .rent
    @State private var selectedRecurrence: Recurrence = .monthly
    @State private var note = ""
    @State private var showValidationError = false

    private var isEditing: Bool { editingExpense != nil }

    var body: some View {
        NavigationStack {
            Form {
                // 基本資訊
                Section("基本資訊") {
                    TextField("名稱", text: $title)

                    HStack {
                        Text("NT$")
                            .foregroundStyle(.secondary)
                        TextField("金額", text: $amountText)
                            .keyboardType(.decimalPad)
                    }

                    DatePicker("日期", selection: $date, displayedComponents: .date)
                }

                // 分類
                Section("分類") {
                    if expenseType == .variable {
                        Picker("類別", selection: $selectedVariableCategory) {
                            ForEach(VariableCategory.allCases) { category in
                                Label(category.rawValue, systemImage: category.icon)
                                    .tag(category)
                            }
                        }
                    } else {
                        Picker("類別", selection: $selectedFixedCategory) {
                            ForEach(FixedCategory.allCases) { category in
                                Label(category.rawValue, systemImage: category.icon)
                                    .tag(category)
                            }
                        }

                        Picker("週期", selection: $selectedRecurrence) {
                            ForEach(Recurrence.allCases, id: \.self) { recurrence in
                                Text(recurrence.rawValue).tag(recurrence)
                            }
                        }
                    }
                }

                // 備註
                Section("備註") {
                    TextField("選填備註", text: $note, axis: .vertical)
                        .lineLimit(3)
                }

                // 驗證錯誤
                if showValidationError {
                    Section {
                        Text("請輸入名稱和有效金額")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(isEditing ? "編輯\(expenseType.rawValue)" : "新增\(expenseType.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "儲存" : "新增") {
                        saveExpense()
                    }
                    .bold()
                    .foregroundStyle(.green)
                }
            }
            .onAppear {
                if let expense = editingExpense {
                    title = expense.title
                    amountText = String(format: "%.0f", expense.amount)
                    date = expense.date
                    if let vc = expense.variableCategory {
                        selectedVariableCategory = vc
                    }
                    if let fc = expense.fixedCategory {
                        selectedFixedCategory = fc
                    }
                    if let rec = expense.recurrence {
                        selectedRecurrence = rec
                    }
                    note = expense.note
                }
            }
        }
    }

    private func saveExpense() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty,
              let amount = Double(amountText), amount > 0 else {
            showValidationError = true
            return
        }

        let expense = Expense(
            id: editingExpense?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespaces),
            amount: amount,
            date: date,
            expenseType: expenseType,
            variableCategory: expenseType == .variable ? selectedVariableCategory : nil,
            fixedCategory: expenseType == .fixed ? selectedFixedCategory : nil,
            recurrence: expenseType == .fixed ? selectedRecurrence : nil,
            note: note.trimmingCharacters(in: .whitespaces)
        )

        if isEditing {
            store.update(expense)
        } else {
            store.add(expense)
        }

        dismiss()
    }
}

#Preview {
    AddExpenseView(expenseType: .variable)
        .environmentObject(ExpenseStore())
}
