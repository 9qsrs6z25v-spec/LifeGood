import SwiftUI

struct AddRealEstateView: View {
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @Environment(\.dismiss) private var dismiss

    var editing: RealEstate?

    @State private var name = ""
    @State private var address = ""
    @State private var purchaseDate = Date()
    @State private var purchasePriceText = ""
    @State private var currentValueText = ""
    @State private var monthlyRentalText = ""
    @State private var monthlyMortgageText = ""
    @State private var note = ""
    @State private var showError = false

    private var mortgageAmount: Double { Double(monthlyMortgageText) ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("物件資訊") {
                    TextField("物件名稱", text: $name)
                    TextField("地址", text: $address)
                    DatePicker("購入日期", selection: $purchaseDate, displayedComponents: .date)
                }

                Section {
                    HStack {
                        TextField("購入價格", text: $purchasePriceText).keyboardType(.decimalPad)
                        Text("萬元").foregroundStyle(.secondary)
                    }
                    HStack {
                        TextField("目前估值", text: $currentValueText).keyboardType(.decimalPad)
                        Text("萬元").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("價值")
                } footer: {
                    Text("以萬元為單位輸入，例如輸入 1500 代表 NT$15,000,000。")
                }

                Section {
                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("月租金收入", text: $monthlyRentalText).keyboardType(.decimalPad)
                    }
                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("月房貸支出", text: $monthlyMortgageText).keyboardType(.decimalPad)
                    }
                } header: {
                    Text("每月收支")
                } footer: {
                    if mortgageAmount > 0 {
                        Text("儲存後將自動在記帳模式的固定支出中建立或更新對應的房貸紀錄。")
                    }
                }

                if let rental = Double(monthlyRentalText),
                   let mortgage = Double(monthlyMortgageText) {
                    Section("試算") {
                        HStack {
                            Text("每月淨現金流")
                            Spacer()
                            let flow = rental - mortgage
                            Text(formatCurrency(flow))
                                .foregroundStyle(flow >= 0 ? .green : .red)
                        }
                    }
                }

                Section("備註") {
                    TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
                }

                if showError {
                    Section {
                        Text("請輸入物件名稱和購入價格")
                            .foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle(editing != nil ? "編輯房地產" : "新增房地產")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing != nil ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green)
                }
            }
            .onAppear {
                if let e = editing {
                    name = e.name; address = e.address
                    purchaseDate = e.purchaseDate
                    purchasePriceText = e.purchasePrice > 0 ? String(format: "%g", e.purchasePrice / 10000) : ""
                    currentValueText = e.currentValue > 0 ? String(format: "%g", e.currentValue / 10000) : ""
                    monthlyRentalText = e.monthlyRental > 0 ? String(format: "%.0f", e.monthlyRental) : ""
                    monthlyMortgageText = e.monthlyMortgage > 0 ? String(format: "%.0f", e.monthlyMortgage) : ""
                    note = e.note
                }
            }
        }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              let priceWan = Double(purchasePriceText), priceWan > 0 else {
            showError = true; return
        }

        let price = priceWan * 10000
        let currentVal = (Double(currentValueText) ?? priceWan) * 10000
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        let reId = editing?.id ?? UUID()
        let existingExpenseId = editing?.linkedExpenseId

        // 房貸 > 0 時同步建立/更新固定支出
        var expenseId = existingExpenseId
        if mortgageAmount > 0 {
            expenseId = syncMortgageExpense(
                realEstateId: reId,
                existingExpenseId: existingExpenseId,
                name: trimmedName,
                note: trimmedNote
            )
        }

        let item = RealEstate(
            id: reId,
            name: trimmedName,
            address: address.trimmingCharacters(in: .whitespaces),
            purchaseDate: purchaseDate,
            purchasePrice: price,
            currentValue: currentVal,
            monthlyRental: Double(monthlyRentalText) ?? 0,
            monthlyMortgage: mortgageAmount,
            linkedExpenseId: mortgageAmount > 0 ? expenseId : nil,
            note: trimmedNote
        )
        if editing != nil { financeStore.update(item) } else { financeStore.add(item) }
        dismiss()
    }

    /// 同步建立或更新記帳模式的固定支出（貸款-房貸）
    private func syncMortgageExpense(realEstateId: UUID, existingExpenseId: UUID?, name: String, note: String) -> UUID {
        let expenseId = existingExpenseId ?? UUID()

        let expense = Expense(
            id: expenseId,
            title: name,
            amount: mortgageAmount,
            date: purchaseDate,
            expenseType: .fixed,
            fixedCategory: .loan,
            recurrence: .monthly,
            loanSubCategory: .mortgage,
            linkedRealEstateId: realEstateId,
            note: note
        )

        if existingExpenseId != nil {
            expenseStore.update(expense)
        } else {
            expenseStore.add(expense)
        }

        return expenseId
    }

    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "NT$0"
    }
}
