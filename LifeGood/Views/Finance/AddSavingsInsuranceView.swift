import SwiftUI

// MARK: - 美化紀錄（AddSavingsInsuranceView）
// [2026-06] 本次美化方向：
//   1. sectionHeader：統一升級為「4pt Capsule 漸層色條 + 彩色圖示 + .subheadline.bold 標題」，
//      對齊 AddVehicleView / AddExpenseView section header 設計語言。
//   2. calcPreviewCard：在表單頂部加入綠色漸層試算預覽卡，即時顯示「目前帳戶價值 / 期滿預估領回 /
//      預估總報酬率」三欄 KPI；大數字套用 ntdWanString 萬/億格式；
//      加入 spring 進場動畫（cardAppeared），對齊 AddExpenseView.loanCalcRow 設計語言。
//   3. errorBanner：從純紅文字升級為帶圖示的橘色警告膠囊卡，對齊 AddExpenseView 驗證錯誤規格。
//   4. Form tint 套用 .tint(.green)，與儲蓄險整體綠色主題一致。

struct AddSavingsInsuranceView: View {
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @Environment(\.dismiss) private var dismiss

    var editing: SavingsInsurance?

    @State private var name = ""
    @State private var company = ""
    @State private var currencyCode: String = "NT$"
    @State private var premiumText = ""
    @State private var paymentPeriod: Recurrence = .yearly
    @State private var annualRateText = ""
    @State private var startDate = Date()
    @State private var maturityDate = Calendar.current.date(byAdding: .year, value: 6, to: Date()) ?? Date()
    @State private var note = ""
    @State private var showError = false
    @State private var cardAppeared = false

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

    private var currencySymbol: String { currencyCode }
    private var isUSD: Bool { currencyCode == "US$" || currencyCode == "USD" || currencyCode.lowercased() == "美金" }

    var body: some View {
        NavigationStack {
            Form {
                // 試算預覽卡（有保費金額時顯示）
                if premium > 0 {
                    Section {
                        calcPreviewCard
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }

                Section {
                    TextField("保單名稱", text: $name)
                    TextField("保險公司", text: $company)
                } header: {
                    sectionHeader("基本資訊", icon: "shield.fill",
                                  gradient: [Color(red: 0.18, green: 0.62, blue: 0.40),
                                             Color(red: 0.12, green: 0.82, blue: 0.52)])
                }

                Section {
                    HStack {
                        Text("幣別")
                        Spacer()
                        Menu {
                            Button {
                                currencyCode = "NT$"
                            } label: {
                                if currencyCode == "NT$" {
                                    Label("NT$", systemImage: "checkmark")
                                } else {
                                    Text("NT$")
                                }
                            }
                            ForEach(expenseStore.currencyRates) { rate in
                                Button {
                                    currencyCode = rate.code
                                } label: {
                                    if currencyCode == rate.code {
                                        Label("\(rate.code)（1=\(rateDisplay(rate.rate)) 元）", systemImage: "checkmark")
                                    } else {
                                        Text("\(rate.code)（1=\(rateDisplay(rate.rate)) 元）")
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Text(currencyCode)
                                Image(systemName: "chevron.down").font(.caption2)
                            }
                            .foregroundStyle(.secondary)
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
                } header: {
                    sectionHeader("繳費設定", icon: "creditcard.fill",
                                  gradient: [Color(red: 0.22, green: 0.42, blue: 0.88),
                                             Color(red: 0.32, green: 0.62, blue: 1.00)])
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
                    sectionHeader("繳費資訊", icon: "chart.bar.fill",
                                  gradient: [Color(red: 0.42, green: 0.22, blue: 0.82),
                                             Color(red: 0.62, green: 0.42, blue: 1.00)])
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
                    sectionHeader("自動計算結果", icon: "sparkles",
                                  gradient: [Color(red: 0.10, green: 0.68, blue: 0.48),
                                             Color(red: 0.18, green: 0.88, blue: 0.38)])
                } footer: {
                    if annualRate > 0 {
                        Text("以年利率 \(String(format: "%.2f%%", annualRate)) 複利計算，\(paymentPeriod.rawValue)繳 \(formatCurrency(premium))，共 \(totalPeriods) 期。")
                    }
                }

                Section {
                    TextField("選填備註", text: $note, axis: .vertical)
                        .lineLimit(3)
                } header: {
                    sectionHeader("備註", icon: "pencil",
                                  gradient: [Color.gray, Color.gray.opacity(0.65)])
                }

                if showError {
                    Section {
                        errorBanner
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .tint(.green)
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
                    currencyCode = e.currencyCode
                    premiumText = String(format: "%.0f", e.premiumAmount)
                    paymentPeriod = e.paymentPeriod
                    annualRateText = e.annualRate > 0 ? String(format: "%.2f", e.annualRate) : ""
                    startDate = e.startDate
                    maturityDate = e.maturityDate
                    note = e.note
                }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.12)) {
                    cardAppeared = true
                }
            }
        }
    }

    // MARK: - 子視圖

    /// 統一 section header：4pt 漸層 Capsule 色條 + 彩色圖示 + 粗體標題
    private func sectionHeader(_ title: String, icon: String, gradient: [Color]) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(LinearGradient(colors: gradient, startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 16)
            Image(systemName: icon)
                .font(.caption.bold())
                .foregroundStyle(gradient.first ?? .primary)
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.vertical, 2)
        .textCase(nil)
    }

    /// 即時試算預覽卡（綠色漸層英雄卡）
    private var calcPreviewCard: some View {
        ZStack(alignment: .topTrailing) {
            // 散景裝飾圓
            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 90, height: 90)
                .offset(x: 12, y: -24)
            Circle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 55, height: 55)
                .offset(x: -18, y: 14)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "leaf.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.90))
                    Text("保單試算預覽")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.90))
                    Spacer()
                    if annualRate > 0 {
                        Text("年利率 \(String(format: "%.2f%%", annualRate))")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.22))
                            .clipShape(Capsule())
                            .foregroundStyle(.white)
                    }
                }

                HStack(spacing: 0) {
                    previewKpiCell(label: "目前帳戶", value: formatCurrency(calculatedCurrentValue))
                    Rectangle()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 0.5, height: 36)
                    previewKpiCell(label: "期滿預估", value: formatCurrency(calculatedExpectedReturn))
                    if totalPaid > 0 {
                        Rectangle()
                            .fill(Color.white.opacity(0.28))
                            .frame(width: 0.5, height: 36)
                        let roi = (calculatedExpectedReturn - premium * Double(totalPeriods)) / (premium * Double(totalPeriods)) * 100
                        previewKpiCell(
                            label: "預估報酬率",
                            value: String(format: "%.1f%%", roi),
                            tint: roi >= 0 ? Color(red: 0.78, green: 1.00, blue: 0.60) : Color(red: 1.00, green: 0.68, blue: 0.68)
                        )
                    }
                }
            }
            .padding(16)
        }
        .background(
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.64, blue: 0.44),
                         Color(red: 0.16, green: 0.82, blue: 0.34)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color(red: 0.10, green: 0.64, blue: 0.44).opacity(0.32), radius: 10, y: 4)
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .opacity(cardAppeared ? 1 : 0)
        .offset(y: cardAppeared ? 0 : 14)
        .animation(.spring(response: 0.50, dampingFraction: 0.80), value: cardAppeared)
    }

    private func previewKpiCell(label: String, value: String, tint: Color = .white) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .minimumScaleFactor(0.70)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.80))
        }
        .frame(maxWidth: .infinity)
    }

    /// 驗證失敗橘色錯誤卡
    private var errorBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
                .font(.subheadline.bold())
            Text("請輸入保單名稱和有效保費金額")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [Color.orange, Color(red: 1.0, green: 0.60, blue: 0.15)],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    // MARK: - 商業邏輯（不變動）

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
            currencyCode: currencyCode,
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
        // 台幣套用「萬」規則；外幣維持原幣別與小數位
        if !isUSD && (currencySymbol == "NT$" || currencySymbol == "TWD") {
            return value.ntdWanString
        }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencySymbol = currencySymbol
        f.maximumFractionDigits = isUSD ? 2 : 0
        return f.string(from: NSNumber(value: value)) ?? "\(currencySymbol)0"
    }

    private func rateDisplay(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%g", value)
    }
}
