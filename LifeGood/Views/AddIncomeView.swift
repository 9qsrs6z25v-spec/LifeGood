import SwiftUI

struct AddIncomeView: View {
    @EnvironmentObject var store: ExpenseStore
    @Environment(\.dismiss) private var dismiss

    var editing: Income?

    @State private var title = ""
    @State private var amountText = ""
    @State private var date = Date()
    @State private var category: IncomeCategory = .salary
    @State private var period: IncomePeriod = .monthly
    @State private var note = ""
    @State private var showError = false

    private var isEditing: Bool { editing != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    TextField("名稱", text: $title)
                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("金額", text: $amountText).keyboardType(.decimalPad)
                    }
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                }

                Section("分類") {
                    Picker("類別", selection: $category) {
                        ForEach(IncomeCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }

                    Picker("週期", selection: $period) {
                        ForEach(IncomePeriod.allCases) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                }

                if period != .once {
                    Section("試算") {
                        if let amount = Double(amountText), amount > 0 {
                            let monthly = period == .monthly ? amount : amount / 12
                            HStack {
                                Text("月等效收入"); Spacer()
                                Text(formatCurrency(monthly)).foregroundStyle(.green)
                            }
                            HStack {
                                Text("年等效收入"); Spacer()
                                Text(formatCurrency(monthly * 12)).foregroundStyle(.green)
                            }
                        }
                    }
                }

                Section("備註") {
                    TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
                }

                if showError {
                    Section {
                        Text("請輸入名稱和有效金額").foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle(isEditing ? "編輯收入" : "新增收入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green)
                }
            }
            .onAppear {
                if let e = editing {
                    title = e.title
                    amountText = String(format: "%.0f", e.amount)
                    date = e.date
                    category = e.category
                    period = e.period
                    note = e.note
                }
            }
        }
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty,
              let amount = Double(amountText), amount > 0 else {
            showError = true; return
        }
        let income = Income(
            id: editing?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespaces),
            amount: amount,
            date: date,
            category: category,
            period: period,
            note: note.trimmingCharacters(in: .whitespaces)
        )
        if isEditing { store.update(income) } else { store.add(income) }
        dismiss()
    }

    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "NT$0"
    }
}
