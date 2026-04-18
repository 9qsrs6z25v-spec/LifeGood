import SwiftUI

struct AddRealEstateView: View {
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @Environment(\.dismiss) private var dismiss

    var editing: RealEstate?

    @State private var name = ""
    @State private var address = ""
    @State private var purchaseDate = Date()
    @State private var isSold = false
    @State private var soldDate = Date()
    @State private var purchasePriceText = ""
    @State private var currentValueText = ""
    @State private var monthlyRentalText = ""
    @State private var note = ""
    @State private var showError = false

    // MARK: - 貸款項目列表

    @State private var mortgageItems: [MortgageItemState] = []

    struct MortgageItemState: Identifiable {
        let id: UUID
        var title: String
        var amountText: String
        var periodsText: String
        var startDate: Date
        var linkedExpenseId: UUID?

        var amount: Double { Double(amountText) ?? 0 }
        var periods: Int { Int(periodsText) ?? 0 }

        var elapsedPeriods: Int {
            let months = Calendar.current.dateComponents([.month], from: startDate, to: Date()).month ?? 0
            return min(max(0, months), periods)
        }
        var paidAmount: Double { amount * Double(elapsedPeriods) }
    }

    // MARK: - 已支出房屋金額列表

    @State private var paidItems: [PaidItemState] = []

    struct PaidItemState: Identifiable {
        let id: UUID
        var title: String
        var amountText: String
        var date: Date
        var linkedExpenseId: UUID?

        var amount: Double { Double(amountText) ?? 0 }
    }

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

    var body: some View {
        NavigationStack {
            Form {
                infoSection
                valueSection
                rentalSection
                mortgageSection
                paidSection
                variableExpenseSection
                calcSection

                Section("備註") {
                    TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
                }

                if showError {
                    Section {
                        Text("請輸入物件名稱和購入價格").foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle(editing != nil ? "編輯房地產" : "新增房地產")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing != nil ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green)
                }
            }
            .onAppear { loadEditing() }
        }
    }

    // MARK: - 物件資訊

    private var infoSection: some View {
        Section("物件資訊") {
            TextField("物件名稱", text: $name)
            TextField("地址", text: $address)
            DatePicker("購入日期", selection: $purchaseDate, displayedComponents: .date)

            Toggle("已售出", isOn: $isSold)
            if isSold {
                DatePicker("售出日期", selection: $soldDate, in: purchaseDate..., displayedComponents: .date)
            }
        }
    }

    // MARK: - 價值

    private var valueSection: some View {
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
    }

    // MARK: - 租金收入

    private var rentalSection: some View {
        Section("租金收入") {
            HStack {
                Text("NT$").foregroundStyle(.secondary)
                TextField("月租金收入", text: $monthlyRentalText).keyboardType(.decimalPad)
            }
        }
    }

    // MARK: - 貸款項目

    private var mortgageSection: some View {
        Section {
            ForEach(Array(mortgageItems.enumerated()), id: \.element.id) { index, _ in
                VStack(spacing: 10) {
                    if index > 0 { Divider() }

                    HStack {
                        Text("貸款 \(index + 1)")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Button(role: .destructive) {
                            let item = mortgageItems[index]
                            if let linkedId = item.linkedExpenseId {
                                expenseStore.expenses.removeAll { $0.id == linkedId }
                            }
                            mortgageItems.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }

                    TextField("名稱（如 第一順位房貸）", text: $mortgageItems[index].title)

                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("每期金額", text: $mortgageItems[index].amountText)
                            .keyboardType(.decimalPad)
                    }

                    HStack {
                        TextField("總期數", text: $mortgageItems[index].periodsText)
                            .keyboardType(.numberPad)
                        Text("期").foregroundStyle(.secondary)

                        if mortgageItems[index].periods > 0 {
                            Text("(\(mortgageItems[index].periods / 12)年\(mortgageItems[index].periods % 12)月)")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }

                    DatePicker("起始日", selection: $mortgageItems[index].startDate, displayedComponents: .date)

                    if mortgageItems[index].amount > 0, mortgageItems[index].periods > 0 {
                        HStack {
                            Text("貸款總額")
                            Spacer()
                            Text(formatCurrency(mortgageItems[index].amount * Double(mortgageItems[index].periods)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("已繳")
                            Text("\(mortgageItems[index].elapsedPeriods)/\(mortgageItems[index].periods) 期")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(formatCurrency(mortgageItems[index].paidAmount))
                                .font(.caption.bold()).foregroundStyle(.blue)
                        }
                    }
                }
            }

            Button {
                mortgageItems.append(MortgageItemState(
                    id: UUID(), title: "", amountText: "", periodsText: "240", startDate: purchaseDate
                ))
            } label: {
                Label("新增貸款項目", systemImage: "plus.circle").foregroundStyle(.green)
            }
        } header: {
            Text("貸款項目")
        } footer: {
            if !mortgageItems.isEmpty {
                let monthlyTotal = mortgageItems.reduce(0.0) { $0 + $1.amount }
                Text("每月房貸合計 \(formatCurrency(monthlyTotal))，儲存後將自動連動記帳模式的固定支出。")
            } else {
                Text("可新增多筆不同利率或期數的貸款項目。")
            }
        }
    }

    // MARK: - 已支出房屋金額

    private var paidSection: some View {
        Section {
            ForEach(Array(paidItems.enumerated()), id: \.element.id) { index, _ in
                VStack(spacing: 10) {
                    if index > 0 { Divider() }

                    HStack {
                        Text("項目 \(index + 1)")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Button(role: .destructive) {
                            let item = paidItems[index]
                            if let linkedId = item.linkedExpenseId {
                                expenseStore.expenses.removeAll { $0.id == linkedId }
                            }
                            paidItems.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }

                    TextField("名稱（如 頭期款、簽約金）", text: $paidItems[index].title)

                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("金額", text: $paidItems[index].amountText)
                            .keyboardType(.decimalPad)
                    }

                    DatePicker("日期", selection: $paidItems[index].date, displayedComponents: .date)
                }
            }

            Button {
                paidItems.append(PaidItemState(
                    id: UUID(), title: "", amountText: "", date: Date()
                ))
            } label: {
                Label("新增已支出項目", systemImage: "plus.circle").foregroundStyle(.green)
            }
        } header: {
            Text("已支出房屋金額")
        } footer: {
            if !paidItems.isEmpty {
                let total = paidItems.reduce(0.0) { $0 + $1.amount }
                Text("已支出合計 \(formatCurrency(total))，儲存後將自動連動記帳模式的變動支出。")
            } else {
                Text("記錄頭期款、簽約金、工程款等已支付的房屋相關金額。")
            }
        }
    }

    // MARK: - 變動支出

    private var variableExpenseSection: some View {
        Section {
            ForEach(Array(variableItems.enumerated()), id: \.element.id) { index, _ in
                VStack(spacing: 10) {
                    if index > 0 { Divider() }

                    HStack {
                        Text("項目 \(index + 1)").font(.subheadline.weight(.medium))
                        Spacer()
                        Button(role: .destructive) {
                            let item = variableItems[index]
                            if let linkedId = item.linkedExpenseId {
                                expenseStore.expenses.removeAll { $0.id == linkedId }
                            }
                            variableItems.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }.buttonStyle(.plain)
                    }

                    Picker("類別", selection: $variableItems[index].category) {
                        ForEach(RealEstateExpenseCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }
                    DatePicker("日期", selection: $variableItems[index].date, displayedComponents: .date)
                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("金額", text: $variableItems[index].amountText).keyboardType(.decimalPad)
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
            Text("裝修、維修、家具、清潔等一次性支出。")
        }
    }

    // MARK: - 試算

    @ViewBuilder
    private var calcSection: some View {
        let rental = Double(monthlyRentalText) ?? 0
        let mortgageMonthly = mortgageItems.reduce(0.0) { $0 + $1.amount }
        let mortgagePaidTotal = mortgageItems.reduce(0.0) { $0 + $1.paidAmount }
        let paidTotal = paidItems.reduce(0.0) { $0 + $1.amount }
        let varTotal = variableItems.reduce(0.0) { $0 + $1.amount }
        let mortgageTotal = mortgageItems.reduce(0.0) { $0 + $1.amount * Double($1.periods) }
        let allPaid = paidTotal + mortgagePaidTotal + varTotal

        if rental > 0 || mortgageMonthly > 0 || paidTotal > 0 || varTotal > 0 {
            Section("試算") {
                if rental > 0 || mortgageMonthly > 0 {
                    HStack {
                        Text("每月淨現金流"); Spacer()
                        Text(formatCurrency(rental - mortgageMonthly))
                            .foregroundStyle(rental - mortgageMonthly >= 0 ? .green : .red)
                    }
                }
                if mortgageTotal > 0 {
                    HStack {
                        Text("貸款總額"); Spacer()
                        Text(formatCurrency(mortgageTotal)).foregroundStyle(.secondary)
                    }
                }
                if mortgagePaidTotal > 0 {
                    HStack {
                        Text("已繳貸款金額"); Spacer()
                        Text(formatCurrency(mortgagePaidTotal)).foregroundStyle(.blue)
                    }
                }
                if paidTotal > 0 {
                    HStack {
                        Text("已支出房屋金額"); Spacer()
                        Text(formatCurrency(paidTotal)).foregroundStyle(.purple)
                    }
                }
                if varTotal > 0 {
                    HStack {
                        Text("變動支出累計"); Spacer()
                        Text(formatCurrency(varTotal)).foregroundStyle(.orange)
                    }
                }
                HStack {
                    Text("房屋總已支出"); Spacer()
                    Text(formatCurrency(allPaid))
                        .font(.body.bold()).foregroundStyle(.red)
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

        // 同步貸款項目到固定支出
        var syncedMortgages: [RealEstateMortgageItem] = []
        for item in mortgageItems where item.amount > 0 {
            let expId = syncMortgageItemExpense(reId: reId, reName: trimmedName, item: item, note: trimmedNote)
            syncedMortgages.append(RealEstateMortgageItem(
                id: item.id, title: item.title.trimmingCharacters(in: .whitespaces),
                amount: item.amount, totalPeriods: item.periods,
                startDate: item.startDate, linkedExpenseId: expId
            ))
        }

        // 同步已支出金額到變動支出
        var syncedPaids: [RealEstatePaidItem] = []
        for item in paidItems where item.amount > 0 {
            let expId = syncPaidItemExpense(reId: reId, reName: trimmedName, item: item)
            syncedPaids.append(RealEstatePaidItem(
                id: item.id, title: item.title.trimmingCharacters(in: .whitespaces),
                amount: item.amount, date: item.date, linkedExpenseId: expId
            ))
        }

        // 同步變動支出
        var syncedVariable: [RealEstateVariableExpense] = []
        for item in variableItems where item.amount > 0 {
            let expId = syncVariableExpense(reId: reId, reName: trimmedName, item: item)
            syncedVariable.append(RealEstateVariableExpense(
                id: item.id, category: item.category,
                amount: item.amount, date: item.date, linkedExpenseId: expId
            ))
        }

        let re = RealEstate(
            id: reId, name: trimmedName,
            address: address.trimmingCharacters(in: .whitespaces),
            purchaseDate: purchaseDate,
            soldDate: isSold ? soldDate : nil,
            purchasePrice: price, currentValue: currentVal,
            monthlyRental: Double(monthlyRentalText) ?? 0,
            mortgageItems: syncedMortgages,
            paidItems: syncedPaids,
            variableExpenses: syncedVariable,
            note: trimmedNote
        )
        if editing != nil { financeStore.update(re) } else { financeStore.add(re) }
        dismiss()
    }

    // MARK: - 同步函式

    private func syncMortgageItemExpense(reId: UUID, reName: String, item: MortgageItemState, note: String) -> UUID {
        let expenseId = item.linkedExpenseId ?? UUID()
        let title = item.title.isEmpty ? "\(reName) - 房貸" : "\(reName) - \(item.title)"
        let expense = Expense(
            id: expenseId, title: title, amount: item.amount, date: purchaseDate,
            expenseType: .fixed, fixedCategory: .loan, recurrence: .monthly,
            loanSubCategory: .mortgage, linkedRealEstateId: reId, note: note
        )
        if item.linkedExpenseId != nil { expenseStore.update(expense) }
        else { expenseStore.add(expense) }
        return expenseId
    }

    private func syncPaidItemExpense(reId: UUID, reName: String, item: PaidItemState) -> UUID {
        let expenseId = item.linkedExpenseId ?? UUID()
        let title = item.title.isEmpty ? "\(reName) - 已付款" : "\(reName) - \(item.title)"
        let expense = Expense(
            id: expenseId, title: title, amount: item.amount, date: item.date,
            expenseType: .variable, variableCategory: .dailyNecessities,
            linkedRealEstateId: reId,
            realEstateExpenseCategory: .housePayment, note: ""
        )
        if item.linkedExpenseId != nil { expenseStore.update(expense) }
        else { expenseStore.add(expense) }
        return expenseId
    }

    private func syncVariableExpense(reId: UUID, reName: String, item: VariableItemState) -> UUID {
        let expenseId = item.linkedExpenseId ?? UUID()
        let expense = Expense(
            id: expenseId, title: "\(reName) - \(item.category.rawValue)",
            amount: item.amount, date: item.date,
            expenseType: .variable, variableCategory: .dailyNecessities,
            linkedRealEstateId: reId,
            realEstateExpenseCategory: item.category, note: ""
        )
        if item.linkedExpenseId != nil { expenseStore.update(expense) }
        else { expenseStore.add(expense) }
        return expenseId
    }

    // MARK: - 載入編輯

    private func loadEditing() {
        guard let e = editing else { return }
        name = e.name; address = e.address
        purchaseDate = e.purchaseDate
        if let sd = e.soldDate {
            isSold = true; soldDate = sd
        } else {
            isSold = false; soldDate = Date()
        }
        purchasePriceText = e.purchasePrice > 0 ? String(format: "%g", e.purchasePrice / 10000) : ""
        currentValueText = e.currentValue > 0 ? String(format: "%g", e.currentValue / 10000) : ""
        monthlyRentalText = e.monthlyRental > 0 ? String(format: "%.0f", e.monthlyRental) : ""
        note = e.note

        mortgageItems = e.mortgageItems.map { m in
            MortgageItemState(
                id: m.id, title: m.title,
                amountText: m.amount > 0 ? String(format: "%.0f", m.amount) : "",
                periodsText: m.totalPeriods > 0 ? "\(m.totalPeriods)" : "",
                startDate: m.startDate,
                linkedExpenseId: m.linkedExpenseId
            )
        }

        paidItems = e.paidItems.map { p in
            PaidItemState(
                id: p.id, title: p.title,
                amountText: p.amount > 0 ? String(format: "%.0f", p.amount) : "",
                date: p.date, linkedExpenseId: p.linkedExpenseId
            )
        }

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
