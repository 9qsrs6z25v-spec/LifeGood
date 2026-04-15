import SwiftUI

struct AddSavingsInsuranceView: View {
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @Environment(\.dismiss) private var dismiss

    var editing: SavingsInsurance?

    @State private var name = ""
    @State private var company = ""
    @State private var currency: Currency = .twd
    @State private var premiumText = ""
    @State private var paymentPeriod: Recurrence = .yearly
    @State private var annualRateText = ""
    @State private var startDate = Date()
    @State private var maturityDate = Calendar.current.date(byAdding: .year, value: 6, to: Date()) ?? Date()
    @State private var note = ""
    @State private var showError = false

    // MARK: - 自動計算

    private var premium: Double { Double(premiumText) ?? 0 }
    private var annualRate: Double { Double(annualRateText) ?? 0 }

    private var periodsPerYear: Double {
        switch paymentPeriod {
        case .monthly: return 12
        case .quarterly: return 4
        case .yearly: return 1
        }
    }

    private var totalPeriods: Int {
        let months = Calendar.current.dateComponents([.month], from: startDate, to: maturityDate).month ?? 0
        let monthsPerPeriod = paymentPeriod == .monthly ? 1 : (paymentPeriod == .quarterly ? 3 : 12)
        return max(0, months / monthsPerPeriod)
    }

    /// 已繳期數：起始日即繳第一期，故 +1，且不超過總期數
    private var elapsedPeriods: Int {
        guard Date() >= startDate else { return 0 }
        let months = Calendar.current.dateComponents([.month], from: startDate, to: min(Date(), maturityDate)).month ?? 0
        let monthsPerPeriod = paymentPeriod == .monthly ? 1 : (paymentPeriod == .quarterly ? 3 : 12)
        return min(months / monthsPerPeriod + 1, totalPeriods)
    }

    private var calculatedExpectedReturn: Double {
        guard premium > 0 else { return 0 }
        let r = annualRate / 100.0 / periodsPerYear
        return SavingsInsurance.futureValue(payment: premium, ratePerPeriod: r, periods: totalPeriods)
    }

    private var calculatedCurrentValue: Double {
        guard premium > 0 else { return 0 }
        let r = annualRate / 100.0 / periodsPerYear
        return SavingsInsurance.futureValue(payment: premium, ratePerPeriod: r, periods: elapsedPeriods)
    }

    private var totalPaid: Double {
        premium * Double(elapsedPeriods)
    }

    private var currencySymbol: String { currency.symbol }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    TextField("保單名稱", text: $name)
                    TextField("保險公司", text: $company)
                }

                Section("繳費設定") {
                    Picker("幣別", selection: $currency) {
                        ForEach(Currency.allCases, id: \.self) { c in
                            Text("\(c.symbol) (\(c.rawValue))").tag(c)
                        }
                    }

                    HStack {
                        Text(currencySymbol)
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .leading)
                        TextField("保費金額", text: $premiumText)
                            .keyboardType(.decimalPad)
                    }

                    Picker("繳費週期", selection: $paymentPeriod) {
                        ForEach(Recurrence.allCases, id: \.self) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }

                    HStack {
                        Text("複利年利率")
                        Spacer()
                        TextField("0.00", text: $annualRateText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("%")
                            .foregroundStyle(.secondary)
                    }

                    DatePicker("起始日", selection: $startDate, displayedComponents: .date)
                    DatePicker("到期日", selection: $maturityDate, displayedComponents: .date)
                }

                Section {
                    HStack {
                        Text("繳費期數")
                        Spacer()
                        Text("\(totalPeriods) 期")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("已繳期數")
                        Spacer()
                        Text("\(elapsedPeriods) 期")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("已繳總額")
                        Spacer()
                        Text(formatCurrency(totalPaid))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("繳費資訊")
                }

                Section {
                    HStack {
                        Text("目前帳戶價值")
                        Spacer()
                        Text(formatCurrency(calculatedCurrentValue))
                            .font(.body.bold())
                            .foregroundStyle(.blue)
                    }
                    HStack {
                        Text("期滿預估領回")
                        Spacer()
                        Text(formatCurrency(calculatedExpectedReturn))
                            .font(.body.bold())
                            .foregroundStyle(.green)
                    }
                    if totalPaid > 0 {
                        HStack {
                            Text("預估總報酬率")
                            Spacer()
                            let roi = (calculatedExpectedReturn - premium * Double(totalPeriods)) / (premium * Double(totalPeriods)) * 100
                            Text(String(format: "%.2f%%", roi))
                                .font(.body.bold())
                                .foregroundStyle(roi >= 0 ? .green : .red)
                        }
                        HStack {
                            Text("複利增值")
                            Spacer()
                            let gain = calculatedExpectedReturn - premium * Double(totalPeriods)
                            Text((gain >= 0 ? "+" : "") + formatCurrency(gain))
                                .foregroundStyle(gain >= 0 ? .green : .red)
                        }
                    }
                } header: {
                    Text("自動計算結果")
                } footer: {
                    if annualRate > 0 {
                        Text("以年利率 \(String(format: "%.2f%%", annualRate)) 複利計算，\(paymentPeriod.rawValue)繳 \(formatCurrency(premium))，共 \(totalPeriods) 期。")
                    }
                }

                Section("備註") {
                    TextField("選填備註", text: $note, axis: .vertical)
                        .lineLimit(3)
                }

                if showError {
                    Section {
                        Text("請輸入保單名稱和有效保費金額")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(editing != nil ? "編輯儲蓄險" : "新增儲蓄險")
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
                    name = e.name
                    company = e.company
                    currency = e.currency
                    premiumText = String(format: "%.0f", e.premiumAmount)
                    paymentPeriod = e.paymentPeriod
                    annualRateText = e.annualRate > 0 ? String(format: "%.2f", e.annualRate) : ""
                    startDate = e.startDate
                    maturityDate = e.maturityDate
                    note = e.note
                }
            }
        }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              premium > 0 else {
            showError = true; return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedCompany = company.trimmingCharacters(in: .whitespaces)
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)

        let insuranceId = editing?.id ?? UUID()
        let existingExpenseId = editing?.linkedExpenseId

        // 同步建立或更新固定支出紀錄
        let expenseId = syncFixedExpense(
            insuranceId: insuranceId,
            existingExpenseId: existingExpenseId,
            name: trimmedName,
            note: trimmedNote
        )

        // 儲存儲蓄險紀錄
        let item = SavingsInsurance(
            id: insuranceId,
            name: trimmedName,
            company: trimmedCompany,
            currency: currency,
            premiumAmount: premium,
            paymentPeriod: paymentPeriod,
            annualRate: annualRate,
            startDate: startDate,
            maturityDate: maturityDate,
            expectedReturn: calculatedExpectedReturn,
            currentValue: calculatedCurrentValue,
            linkedExpenseId: expenseId,
            note: trimmedNote
        )
        if editing != nil { financeStore.update(item) } else { financeStore.add(item) }
        dismiss()
    }

    /// 同步建立或更新記帳模式的固定支出紀錄
    private func syncFixedExpense(insuranceId: UUID, existingExpenseId: UUID?, name: String, note: String) -> UUID {
        let expenseId = existingExpenseId ?? UUID()

        let expense = Expense(
            id: expenseId,
            title: name,
            amount: premium,
            date: startDate,
            expenseType: .fixed,
            fixedCategory: .insurance,
            recurrence: paymentPeriod,
            insuranceSubCategory: .savings,
            linkedInsuranceId: insuranceId,
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
        f.numberStyle = .currency
        f.currencySymbol = currencySymbol
        f.maximumFractionDigits = currency == .usd ? 2 : 0
        return f.string(from: NSNumber(value: value)) ?? "\(currencySymbol)0"
    }
}
