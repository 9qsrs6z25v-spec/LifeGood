import SwiftUI

struct AddExpenseView: View {
    @EnvironmentObject var store: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @Environment(\.dismiss) private var dismiss

    let expenseType: ExpenseType
    var editingExpense: Expense?

    // MARK: - 基本欄位

    @State private var title = ""
    @State private var amountText = ""
    @State private var date = Date()
    @State private var selectedVariableCategory: VariableCategory = .food
    @State private var selectedFixedCategory: FixedCategory = .rent
    @State private var selectedRecurrence: Recurrence = .monthly
    @State private var note = ""
    @State private var showValidationError = false

    // MARK: - 保險子分類

    @State private var selectedInsuranceSubCategory: InsuranceSubCategory = .savings

    // MARK: - 儲蓄險欄位（保險-儲蓄險時顯示）

    @State private var insCompany = ""
    @State private var insCurrency: Currency = .twd
    @State private var insRateText = ""
    @State private var insStartDate = Date()
    @State private var insMaturityDate = Calendar.current.date(byAdding: .year, value: 6, to: Date()) ?? Date()

    private var isEditing: Bool { editingExpense != nil }
    private var isInsurance: Bool { expenseType == .fixed && selectedFixedCategory == .insurance }
    private var isSavingsInsurance: Bool { isInsurance && selectedInsuranceSubCategory == .savings }

    // MARK: - 儲蓄險自動計算

    private var insPremium: Double { Double(amountText) ?? 0 }
    private var insRate: Double { Double(insRateText) ?? 0 }

    private var insPeriodsPerYear: Double {
        switch selectedRecurrence {
        case .monthly: return 12
        case .quarterly: return 4
        case .yearly: return 1
        }
    }

    private var insTotalPeriods: Int {
        let months = Calendar.current.dateComponents([.month], from: insStartDate, to: insMaturityDate).month ?? 0
        let mpp = selectedRecurrence == .monthly ? 1 : (selectedRecurrence == .quarterly ? 3 : 12)
        return max(0, months / mpp)
    }

    private var insElapsedPeriods: Int {
        guard Date() >= insStartDate else { return 0 }
        let months = Calendar.current.dateComponents([.month], from: insStartDate, to: min(Date(), insMaturityDate)).month ?? 0
        let mpp = selectedRecurrence == .monthly ? 1 : (selectedRecurrence == .quarterly ? 3 : 12)
        return min(months / mpp + 1, insTotalPeriods)
    }

    private var insExpectedReturn: Double {
        guard insPremium > 0 else { return 0 }
        let r = insRate / 100.0 / insPeriodsPerYear
        return SavingsInsurance.futureValue(payment: insPremium, ratePerPeriod: r, periods: insTotalPeriods)
    }

    private var insCurrentValue: Double {
        guard insPremium > 0 else { return 0 }
        let r = insRate / 100.0 / insPeriodsPerYear
        return SavingsInsurance.futureValue(payment: insPremium, ratePerPeriod: r, periods: insElapsedPeriods)
    }

    private var insCurrencySymbol: String { isSavingsInsurance ? insCurrency.symbol : "NT$" }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                basicInfoSection
                categorySection

                if isInsurance {
                    insuranceSubCategorySection
                }

                if isSavingsInsurance {
                    savingsInsuranceSection
                    savingsCalcSection
                } else if expenseType == .fixed {
                    // 非儲蓄險的固定支出：一般備註
                    Section("備註") {
                        TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
                    }
                } else {
                    Section("備註") {
                        TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
                    }
                }

                if showValidationError {
                    Section {
                        Text("請輸入名稱和有效金額").foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle(isEditing ? "編輯\(expenseType.rawValue)" : "新增\(expenseType.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "儲存" : "新增") { saveExpense() }
                        .bold().foregroundStyle(.green)
                }
            }
            .onAppear { loadEditing() }
        }
    }

    // MARK: - 基本資訊

    private var basicInfoSection: some View {
        Section("基本資訊") {
            TextField("名稱", text: $title)

            if isSavingsInsurance {
                // 儲蓄險金額在下方繳費設定中填寫，這裡顯示幣別+金額
                HStack {
                    Text(insCurrencySymbol).foregroundStyle(.secondary)
                    TextField("保費金額", text: $amountText).keyboardType(.decimalPad)
                }
            } else {
                HStack {
                    Text("NT$").foregroundStyle(.secondary)
                    TextField("金額", text: $amountText).keyboardType(.decimalPad)
                }
            }

            if !isSavingsInsurance {
                DatePicker("日期", selection: $date, displayedComponents: .date)
            }
        }
    }

    // MARK: - 分類

    private var categorySection: some View {
        Section("分類") {
            if expenseType == .variable {
                Picker("類別", selection: $selectedVariableCategory) {
                    ForEach(VariableCategory.allCases) { cat in
                        Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                    }
                }
            } else {
                Picker("類別", selection: $selectedFixedCategory) {
                    ForEach(FixedCategory.allCases) { cat in
                        Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                    }
                }

                if !isSavingsInsurance {
                    Picker("週期", selection: $selectedRecurrence) {
                        ForEach(Recurrence.allCases, id: \.self) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 保險子分類

    private var insuranceSubCategorySection: some View {
        Section("保險類別") {
            Picker("保險類別", selection: $selectedInsuranceSubCategory) {
                ForEach(InsuranceSubCategory.allCases) { sub in
                    Text(sub.rawValue).tag(sub)
                }
            }
            .pickerStyle(.menu)
        }
    }

    // MARK: - 儲蓄險詳細欄位

    private var savingsInsuranceSection: some View {
        Group {
            Section("繳費設定") {
                Picker("幣別", selection: $insCurrency) {
                    ForEach(Currency.allCases, id: \.self) { c in
                        Text("\(c.symbol) (\(c.rawValue))").tag(c)
                    }
                }

                Picker("繳費週期", selection: $selectedRecurrence) {
                    ForEach(Recurrence.allCases, id: \.self) { r in
                        Text(r.rawValue).tag(r)
                    }
                }

                HStack {
                    Text("複利年利率")
                    Spacer()
                    TextField("0.00", text: $insRateText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("%").foregroundStyle(.secondary)
                }

                TextField("保險公司", text: $insCompany)

                DatePicker("起始日", selection: $insStartDate, displayedComponents: .date)
                DatePicker("到期日", selection: $insMaturityDate, displayedComponents: .date)
            }

            Section("備註") {
                TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
            }
        }
    }

    // MARK: - 儲蓄險自動計算

    private var savingsCalcSection: some View {
        Group {
            Section("繳費資訊") {
                row("繳費期數", "\(insTotalPeriods) 期")
                row("已繳期數", "\(insElapsedPeriods) 期")
                row("已繳總額", formatCurrency(insPremium * Double(insElapsedPeriods)))
            }

            Section {
                HStack {
                    Text("目前帳戶價值")
                    Spacer()
                    Text(formatCurrency(insCurrentValue)).font(.body.bold()).foregroundStyle(.blue)
                }
                HStack {
                    Text("期滿預估領回")
                    Spacer()
                    Text(formatCurrency(insExpectedReturn)).font(.body.bold()).foregroundStyle(.green)
                }
                if insTotalPeriods > 0 {
                    let totalPremium = insPremium * Double(insTotalPeriods)
                    let gain = insExpectedReturn - totalPremium
                    HStack {
                        Text("複利增值")
                        Spacer()
                        Text((gain >= 0 ? "+" : "") + formatCurrency(gain))
                            .foregroundStyle(gain >= 0 ? .green : .red)
                    }
                    if totalPremium > 0 {
                        HStack {
                            Text("預估總報酬率")
                            Spacer()
                            Text(String(format: "%.2f%%", gain / totalPremium * 100))
                                .font(.body.bold())
                                .foregroundStyle(gain >= 0 ? .green : .red)
                        }
                    }
                }
            } header: {
                Text("自動計算結果")
            } footer: {
                if insRate > 0, insPremium > 0 {
                    Text("以年利率 \(String(format: "%.2f%%", insRate)) 複利計算，\(selectedRecurrence.rawValue)繳 \(formatCurrency(insPremium))，共 \(insTotalPeriods) 期。")
                }
            }
        }
    }

    // MARK: - Save

    private func saveExpense() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty,
              let amount = Double(amountText), amount > 0 else {
            showValidationError = true
            return
        }

        // 決定連結的儲蓄險 ID
        var linkedId = editingExpense?.linkedInsuranceId

        if isSavingsInsurance {
            // 同步建立/更新理財模式的儲蓄險
            linkedId = syncSavingsInsurance(amount: amount, existingId: linkedId)
            // 儲蓄險用起始日作為支出日期
            date = insStartDate
        }

        let expense = Expense(
            id: editingExpense?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespaces),
            amount: amount,
            date: isSavingsInsurance ? insStartDate : date,
            expenseType: expenseType,
            variableCategory: expenseType == .variable ? selectedVariableCategory : nil,
            fixedCategory: expenseType == .fixed ? selectedFixedCategory : nil,
            recurrence: expenseType == .fixed ? selectedRecurrence : nil,
            insuranceSubCategory: isInsurance ? selectedInsuranceSubCategory : nil,
            linkedInsuranceId: isSavingsInsurance ? linkedId : nil,
            note: note.trimmingCharacters(in: .whitespaces)
        )

        if isEditing {
            store.update(expense)
        } else {
            store.add(expense)
        }

        dismiss()
    }

    /// 同步建立或更新理財模式的儲蓄險紀錄
    private func syncSavingsInsurance(amount: Double, existingId: UUID?) -> UUID {
        let insuranceId = existingId ?? UUID()

        let insurance = SavingsInsurance(
            id: insuranceId,
            name: title.trimmingCharacters(in: .whitespaces),
            company: insCompany.trimmingCharacters(in: .whitespaces),
            currency: insCurrency,
            premiumAmount: amount,
            paymentPeriod: selectedRecurrence,
            annualRate: insRate,
            startDate: insStartDate,
            maturityDate: insMaturityDate,
            expectedReturn: insExpectedReturn,
            currentValue: insCurrentValue,
            note: note.trimmingCharacters(in: .whitespaces)
        )

        if existingId != nil {
            financeStore.update(insurance)
        } else {
            financeStore.add(insurance)
        }

        return insuranceId
    }

    // MARK: - Load Editing

    private func loadEditing() {
        guard let expense = editingExpense else { return }
        title = expense.title
        amountText = String(format: "%.0f", expense.amount)
        date = expense.date
        if let vc = expense.variableCategory { selectedVariableCategory = vc }
        if let fc = expense.fixedCategory { selectedFixedCategory = fc }
        if let rec = expense.recurrence { selectedRecurrence = rec }
        if let sub = expense.insuranceSubCategory { selectedInsuranceSubCategory = sub }
        note = expense.note

        // 載入連結的儲蓄險資料
        if let linkedId = expense.linkedInsuranceId,
           let linked = financeStore.insurances.first(where: { $0.id == linkedId }) {
            insCompany = linked.company
            insCurrency = linked.currency
            insRateText = linked.annualRate > 0 ? String(format: "%.2f", linked.annualRate) : ""
            insStartDate = linked.startDate
            insMaturityDate = linked.maturityDate
        }
    }

    // MARK: - Helpers

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencySymbol = insCurrencySymbol
        f.maximumFractionDigits = isSavingsInsurance && insCurrency == .usd ? 2 : 0
        return f.string(from: NSNumber(value: value)) ?? "\(insCurrencySymbol)0"
    }
}

#Preview {
    AddExpenseView(expenseType: .fixed)
        .environmentObject(ExpenseStore())
        .environmentObject(FinanceStore())
}
