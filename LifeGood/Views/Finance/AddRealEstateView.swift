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

    // MARK: - 變動支出列表

    @State private var variableItems: [VariableItemState] = []

    struct VariableItemState: Identifiable {
        let id: UUID
        var category: RealEstateExpenseCategory
        var amountText: String
        var date: Date
        var linkedExpenseId: UUID?

        var amount: Double { Double(amountText) ?? 0 }
    }

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

                // 變動支出
                variableExpenseSection

                // 試算
                calcSection

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
            .onAppear { loadEditing() }
        }
    }

    // MARK: - 變動支出

    private var variableExpenseSection: some View {
        Section {
            ForEach(Array(variableItems.enumerated()), id: \.element.id) { index, _ in
                VStack(spacing: 10) {
                    if index > 0 { Divider() }

                    HStack {
                        Text("項目 \(index + 1)")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Button(role: .destructive) {
                            let item = variableItems[index]
                            if let linkedId = item.linkedExpenseId {
                                expenseStore.expenses.removeAll { $0.id == linkedId }
                            }
                            variableItems.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }

                    Picker("類別", selection: $variableItems[index].category) {
                        ForEach(RealEstateExpenseCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }

                    DatePicker("日期", selection: $variableItems[index].date, displayedComponents: .date)

                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("金額", text: $variableItems[index].amountText)
                            .keyboardType(.decimalPad)
                    }
                }
            }

            Button {
                variableItems.append(VariableItemState(
                    id: UUID(), category: .renovation, amountText: "", date: Date()
                ))
            } label: {
                Label("新增變動支出", systemImage: "plus.circle").foregroundStyle(.green)
            }
        } header: {
            Text("變動支出")
        } footer: {
            if !variableItems.isEmpty {
                let total = variableItems.reduce(0.0) { $0 + $1.amount }
                Text("變動支出合計 \(formatCurrency(total))，儲存後將自動連動記帳模式的變動支出。")
            } else {
                Text("裝修、維修、家具、清潔等一次性支出。")
            }
        }
    }

    // MARK: - 試算

    @ViewBuilder
    private var calcSection: some View {
        let rental = Double(monthlyRentalText) ?? 0
        let mortgage = Double(monthlyMortgageText) ?? 0
        let varTotal = variableItems.reduce(0.0) { $0 + $1.amount }

        if rental > 0 || mortgage > 0 || varTotal > 0 {
            Section("試算") {
                if rental > 0 || mortgage > 0 {
                    HStack {
                        Text("每月淨現金流"); Spacer()
                        Text(formatCurrency(rental - mortgage))
                            .foregroundStyle(rental - mortgage >= 0 ? .green : .red)
                    }
                }
                if varTotal > 0 {
                    HStack {
                        Text("變動支出累計"); Spacer()
                        Text(formatCurrency(varTotal)).foregroundStyle(.orange)
                    }
                }
                if mortgage > 0 || varTotal > 0 {
                    HStack {
                        Text("總支出"); Spacer()
                        Text(formatCurrency(mortgage + varTotal)).font(.body.bold()).foregroundStyle(.red)
                    }
                }
            }
        }
    }

    // MARK: - 儲存

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

        // 房貸連動固定支出
        var expenseId = existingExpenseId
        if mortgageAmount > 0 {
            expenseId = syncMortgageExpense(
                realEstateId: reId, existingExpenseId: existingExpenseId,
                name: trimmedName, note: trimmedNote
            )
        }

        // 變動支出連動
        var syncedVariableExpenses: [RealEstateVariableExpense] = []
        for item in variableItems where item.amount > 0 {
            let linkedId = syncVariableExpense(
                realEstateId: reId, realEstateName: trimmedName, item: item
            )
            syncedVariableExpenses.append(RealEstateVariableExpense(
                id: item.id, category: item.category,
                amount: item.amount, date: item.date, linkedExpenseId: linkedId
            ))
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
            variableExpenses: syncedVariableExpenses,
            linkedExpenseId: mortgageAmount > 0 ? expenseId : nil,
            note: trimmedNote
        )
        if editing != nil { financeStore.update(item) } else { financeStore.add(item) }
        dismiss()
    }

    /// 同步單筆變動支出到記帳模式
    private func syncVariableExpense(realEstateId: UUID, realEstateName: String, item: VariableItemState) -> UUID {
        let expenseId = item.linkedExpenseId ?? UUID()

        let expense = Expense(
            id: expenseId,
            title: "\(realEstateName) - \(item.category.rawValue)",
            amount: item.amount,
            date: item.date,
            expenseType: .variable,
            variableCategory: .dailyNecessities,
            linkedRealEstateId: realEstateId,
            note: ""
        )

        if item.linkedExpenseId != nil {
            expenseStore.update(expense)
        } else {
            expenseStore.add(expense)
        }

        return expenseId
    }

    /// 同步房貸到記帳固定支出
    private func syncMortgageExpense(realEstateId: UUID, existingExpenseId: UUID?, name: String, note: String) -> UUID {
        let expenseId = existingExpenseId ?? UUID()

        let expense = Expense(
            id: expenseId, title: name, amount: mortgageAmount, date: purchaseDate,
            expenseType: .fixed, fixedCategory: .loan, recurrence: .monthly,
            loanSubCategory: .mortgage, linkedRealEstateId: realEstateId, note: note
        )

        if existingExpenseId != nil { expenseStore.update(expense) }
        else { expenseStore.add(expense) }

        return expenseId
    }

    // MARK: - 載入編輯

    private func loadEditing() {
        guard let e = editing else { return }
        name = e.name; address = e.address
        purchaseDate = e.purchaseDate
        purchasePriceText = e.purchasePrice > 0 ? String(format: "%g", e.purchasePrice / 10000) : ""
        currentValueText = e.currentValue > 0 ? String(format: "%g", e.currentValue / 10000) : ""
        monthlyRentalText = e.monthlyRental > 0 ? String(format: "%.0f", e.monthlyRental) : ""
        monthlyMortgageText = e.monthlyMortgage > 0 ? String(format: "%.0f", e.monthlyMortgage) : ""
        note = e.note

        variableItems = e.variableExpenses.map { ve in
            VariableItemState(
                id: ve.id, category: ve.category,
                amountText: ve.amount > 0 ? String(format: "%.0f", ve.amount) : "",
                date: ve.date, linkedExpenseId: ve.linkedExpenseId
            )
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "NT$0"
    }
}
