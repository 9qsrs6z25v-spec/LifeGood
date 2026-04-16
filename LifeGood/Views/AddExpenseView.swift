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

    // MARK: - 貸款子分類

    @State private var selectedLoanSubCategory: LoanSubCategory = .mortgage

    // MARK: - 儲蓄險欄位

    @State private var insCompany = ""
    @State private var insCurrency: Currency = .twd
    @State private var insRateText = ""
    @State private var insStartDate = Date()
    @State private var insMaturityDate = Calendar.current.date(byAdding: .year, value: 6, to: Date()) ?? Date()

    // MARK: - 房貸欄位（連動房地產）

    @State private var reAddress = ""
    @State private var rePurchaseDate = Date()
    @State private var rePurchasePriceText = ""
    @State private var reCurrentValueText = ""
    @State private var reMonthlyRentalText = ""

    // MARK: - 變動支出關聯資產

    enum AssetLinkType: String, CaseIterable, Identifiable {
        case none = "無"
        case vehicle = "汽車"
        case stock = "股票"
        case insurance = "儲蓄險"
        case realEstate = "房地產"

        var id: String { rawValue }
    }

    @State private var selectedAssetLink: AssetLinkType = .none

    // 汽車
    @State private var selectedVehicleId: UUID?
    @State private var selectedVehicleExpenseCategory: VehicleVariableCategory = .fuel

    // 股票（新增投資）
    @State private var stockName = ""
    @State private var stockSymbol = ""
    @State private var stockSharesText = ""
    @State private var stockPriceText = ""
    @State private var stockCurrentPriceText = ""

    // 儲蓄險/房地產選擇器
    @State private var selectedInsuranceLinkId: UUID?
    @State private var selectedRealEstateLinkId: UUID?

    // MARK: - 條件判斷

    private var isEditing: Bool { editingExpense != nil }
    private var isInsurance: Bool { expenseType == .fixed && selectedFixedCategory == .insurance }
    private var isSavingsInsurance: Bool { isInsurance && selectedInsuranceSubCategory == .savings }
    private var isLoan: Bool { expenseType == .fixed && selectedFixedCategory == .loan }
    private var isMortgage: Bool { isLoan && selectedLoanSubCategory == .mortgage }
    private var isCarLoan: Bool { isLoan && selectedLoanSubCategory == .car }

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

                // 變動支出：關聯資產選擇
                if expenseType == .variable {
                    assetLinkSection
                    if selectedAssetLink == .vehicle { vehicleLinkSection }
                    if selectedAssetLink == .stock { stockLinkSection }
                    if selectedAssetLink == .insurance { insuranceLinkSection }
                    if selectedAssetLink == .realEstate { realEstateLinkSection }
                }

                // 固定支出：保險/貸款子分類
                if isInsurance { insuranceSubCategorySection }
                if isLoan { loanSubCategorySection }

                if isSavingsInsurance {
                    savingsInsuranceSection
                    savingsCalcSection
                } else if isMortgage {
                    mortgageRealEstateSection
                } else if isCarLoan {
                    carLoanVehicleSection
                }

                Section("備註") {
                    TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
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

            HStack {
                Text(isSavingsInsurance ? insCurrencySymbol : "NT$").foregroundStyle(.secondary)
                TextField(isMortgage ? "每月房貸金額" : (isSavingsInsurance ? "保費金額" : "金額"), text: $amountText)
                    .keyboardType(.decimalPad)
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

    // MARK: - 關聯資產選擇

    private var assetLinkSection: some View {
        Section {
            Picker("關聯資產", selection: $selectedAssetLink) {
                ForEach(AssetLinkType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("關聯理財資產（選填）")
        } footer: {
            Text("選擇後可將此筆支出連結到理財模式的對應項目。")
        }
    }

    // MARK: - 股票連動

    private var stockLinkSection: some View {
        Section {
            TextField("股票名稱", text: $stockName)
            TextField("股票代號（選填）", text: $stockSymbol)
            TextField("股數", text: $stockSharesText).keyboardType(.decimalPad)
            HStack {
                Text("NT$").foregroundStyle(.secondary)
                TextField("買入價格（每股）", text: $stockPriceText).keyboardType(.decimalPad)
            }
            HStack {
                Text("NT$").foregroundStyle(.secondary)
                TextField("目前價格（每股，選填）", text: $stockCurrentPriceText).keyboardType(.decimalPad)
            }

            if let shares = Double(stockSharesText), shares > 0,
               let price = Double(stockPriceText), price > 0 {
                HStack {
                    Text("投入金額")
                    Spacer()
                    Text(formatCurrency(shares * price)).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("股票投資（連動理財模式）")
        } footer: {
            Text("儲存後將自動在理財模式的股票頁面建立對應的持股紀錄。金額欄位將自動填入投入金額。")
        }
    }

    // MARK: - 儲蓄險連動（變動支出）

    private var insuranceLinkSection: some View {
        Section {
            if financeStore.insurances.isEmpty {
                Text("尚無儲蓄險，請先在理財模式新增")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Picker("選擇保單", selection: $selectedInsuranceLinkId) {
                    Text("請選擇").tag(nil as UUID?)
                    ForEach(financeStore.insurances) { ins in
                        Text("\(ins.name)\(!ins.company.isEmpty ? " (\(ins.company))" : "")").tag(ins.id as UUID?)
                    }
                }
            }
        } header: {
            Text("儲蓄險（連動理財模式）")
        } footer: {
            Text("將此筆支出關聯到已有的儲蓄險保單。")
        }
    }

    // MARK: - 房地產連動（變動支出）

    private var realEstateLinkSection: some View {
        Section {
            if financeStore.realEstates.isEmpty {
                Text("尚無房地產，請先在理財模式新增")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Picker("選擇物件", selection: $selectedRealEstateLinkId) {
                    Text("請選擇").tag(nil as UUID?)
                    ForEach(financeStore.realEstates) { re in
                        Text("\(re.name)\(!re.address.isEmpty ? " (\(re.address))" : "")").tag(re.id as UUID?)
                    }
                }
            }
        } header: {
            Text("房地產（連動理財模式）")
        } footer: {
            Text("將此筆支出關聯到已有的房地產物件（如裝修、管理費等）。")
        }
    }

    // MARK: - 汽車連動

    private var vehicleLinkSection: some View {
        Section {
            if financeStore.vehicles.isEmpty {
                Text("尚無車輛，請先在理財模式新增汽車")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Picker("選擇車輛", selection: $selectedVehicleId) {
                    Text("請選擇").tag(nil as UUID?)
                    ForEach(financeStore.vehicles) { v in
                        Text("\(v.name)\(!v.brand.isEmpty ? " (\(v.brand))" : "")").tag(v.id as UUID?)
                    }
                }

                let selectedVehicle = financeStore.vehicles.first { $0.id == selectedVehicleId }
                let availableCategories = VehicleVariableCategory.categories(
                    for: selectedVehicle?.powerType ?? .gasoline
                )

                Picker("支出類別", selection: $selectedVehicleExpenseCategory) {
                    ForEach(availableCategories) { cat in
                        Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                    }
                }
            }
        } header: {
            Text("汽車資訊（連動理財模式）")
        } footer: {
            Text("支出類別會依照車輛動力類型自動篩選（油車→油錢、電車→電費、混合→兩者皆有）。")
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

    // MARK: - 貸款子分類

    private var loanSubCategorySection: some View {
        Section("貸款類別") {
            Picker("貸款類別", selection: $selectedLoanSubCategory) {
                ForEach(LoanSubCategory.allCases) { sub in
                    Text(sub.rawValue).tag(sub)
                }
            }
            .pickerStyle(.menu)
        }
    }

    // MARK: - 車貸連動汽車

    private var carLoanVehicleSection: some View {
        Section {
            if financeStore.vehicles.isEmpty {
                Text("尚無車輛，請先在理財模式新增汽車")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Picker("選擇車輛", selection: $selectedVehicleId) {
                    Text("請選擇").tag(nil as UUID?)
                    ForEach(financeStore.vehicles) { v in
                        Text("\(v.name)\(!v.brand.isEmpty ? " (\(v.brand))" : "")").tag(v.id as UUID?)
                    }
                }
            }
        } header: {
            Text("車輛資訊（連動理財模式）")
        } footer: {
            Text("儲存後將自動在理財模式的汽車定期支出中新增對應的車貸紀錄。")
        }
    }

    // MARK: - 房貸連動房地產欄位

    private var mortgageRealEstateSection: some View {
        Section {
            TextField("地址", text: $reAddress)
            DatePicker("購入日期", selection: $rePurchaseDate, displayedComponents: .date)
            HStack {
                Text("NT$").foregroundStyle(.secondary)
                TextField("購入價格", text: $rePurchasePriceText).keyboardType(.decimalPad)
            }
            HStack {
                Text("NT$").foregroundStyle(.secondary)
                TextField("目前估值", text: $reCurrentValueText).keyboardType(.decimalPad)
            }
            HStack {
                Text("NT$").foregroundStyle(.secondary)
                TextField("月租金收入（選填）", text: $reMonthlyRentalText).keyboardType(.decimalPad)
            }
        } header: {
            Text("房地產資訊（連動理財模式）")
        } footer: {
            Text("儲存後將自動在理財模式的房地產中建立或更新對應物件。")
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
                    Text("目前帳戶價值"); Spacer()
                    Text(formatCurrency(insCurrentValue)).font(.body.bold()).foregroundStyle(.blue)
                }
                HStack {
                    Text("期滿預估領回"); Spacer()
                    Text(formatCurrency(insExpectedReturn)).font(.body.bold()).foregroundStyle(.green)
                }
                if insTotalPeriods > 0 {
                    let totalPremium = insPremium * Double(insTotalPeriods)
                    let gain = insExpectedReturn - totalPremium
                    HStack {
                        Text("複利增值"); Spacer()
                        Text((gain >= 0 ? "+" : "") + formatCurrency(gain))
                            .foregroundStyle(gain >= 0 ? .green : .red)
                    }
                    if totalPremium > 0 {
                        HStack {
                            Text("預估總報酬率"); Spacer()
                            Text(String(format: "%.2f%%", gain / totalPremium * 100))
                                .font(.body.bold()).foregroundStyle(gain >= 0 ? .green : .red)
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

    // MARK: - 儲存

    private func saveExpense() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)

        // 股票連動時自動計算金額
        var finalAmountText = amountText
        if expenseType == .variable && selectedAssetLink == .stock {
            if let shares = Double(stockSharesText), let price = Double(stockPriceText), shares > 0, price > 0 {
                finalAmountText = String(format: "%.0f", shares * price)
            }
        }

        guard !trimmedTitle.isEmpty,
              let amount = Double(finalAmountText), amount > 0 else {
            showValidationError = true
            return
        }

        let expenseId = editingExpense?.id ?? UUID()
        var linkedInsId = editingExpense?.linkedInsuranceId
        var linkedStkId = editingExpense?.linkedStockId
        var linkedREId = editingExpense?.linkedRealEstateId
        var linkedVehId = editingExpense?.linkedVehicleId

        // 固定支出連動
        if isSavingsInsurance {
            linkedInsId = syncSavingsInsurance(amount: amount, existingId: linkedInsId, expenseId: expenseId)
        }
        if isMortgage {
            linkedREId = syncRealEstate(mortgageAmount: amount, existingId: linkedREId, expenseId: expenseId)
        }
        if isCarLoan, let vehicleId = selectedVehicleId {
            linkedVehId = vehicleId
            syncCarLoanToVehicle(vehicleId: vehicleId, expenseId: expenseId, amount: amount)
        }

        // 變動支出關聯資產連動
        if expenseType == .variable {
            switch selectedAssetLink {
            case .vehicle:
                if let vehicleId = selectedVehicleId {
                    linkedVehId = vehicleId
                    syncVehicleVariableExpense(vehicleId: vehicleId, expenseId: expenseId, amount: amount)
                }
            case .stock:
                linkedStkId = syncStockInvestment(existingId: linkedStkId)
            case .insurance:
                linkedInsId = selectedInsuranceLinkId
            case .realEstate:
                linkedREId = selectedRealEstateLinkId
            case .none:
                break
            }
        }

        let expense = Expense(
            id: expenseId,
            title: trimmedTitle,
            amount: amount,
            date: isSavingsInsurance ? insStartDate : date,
            expenseType: expenseType,
            variableCategory: expenseType == .variable ? selectedVariableCategory : nil,
            fixedCategory: expenseType == .fixed ? selectedFixedCategory : nil,
            recurrence: expenseType == .fixed ? selectedRecurrence : nil,
            insuranceSubCategory: isInsurance ? selectedInsuranceSubCategory : nil,
            loanSubCategory: isLoan ? selectedLoanSubCategory : nil,
            linkedInsuranceId: linkedInsId,
            linkedStockId: linkedStkId,
            linkedRealEstateId: linkedREId,
            linkedVehicleId: linkedVehId,
            vehicleExpenseCategory: (expenseType == .variable && selectedAssetLink == .vehicle) ? selectedVehicleExpenseCategory : nil,
            note: note.trimmingCharacters(in: .whitespaces)
        )

        if isEditing { store.update(expense) } else { store.add(expense) }
        dismiss()
    }

    /// 同步建立股票投資紀錄
    private func syncStockInvestment(existingId: UUID?) -> UUID {
        let stockId = existingId ?? UUID()
        let shares = Double(stockSharesText) ?? 0
        let price = Double(stockPriceText) ?? 0
        let currentPrice = Double(stockCurrentPriceText) ?? price

        let stock = Stock(
            id: stockId,
            name: stockName.trimmingCharacters(in: .whitespaces).isEmpty ? title.trimmingCharacters(in: .whitespaces) : stockName.trimmingCharacters(in: .whitespaces),
            symbol: stockSymbol.trimmingCharacters(in: .whitespaces).uppercased(),
            purchaseDate: date,
            shares: shares,
            purchasePrice: price,
            currentPrice: currentPrice,
            note: note.trimmingCharacters(in: .whitespaces)
        )

        if existingId != nil { financeStore.update(stock) } else { financeStore.add(stock) }
        return stockId
    }

    /// 同步建立或更新理財模式的儲蓄險
    private func syncSavingsInsurance(amount: Double, existingId: UUID?, expenseId: UUID) -> UUID {
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
            linkedExpenseId: expenseId,
            note: note.trimmingCharacters(in: .whitespaces)
        )
        if existingId != nil { financeStore.update(insurance) } else { financeStore.add(insurance) }
        return insuranceId
    }

    /// 同步建立或更新理財模式的房地產
    private func syncRealEstate(mortgageAmount: Double, existingId: UUID?, expenseId: UUID) -> UUID {
        let reId = existingId ?? UUID()
        let realEstate = RealEstate(
            id: reId,
            name: title.trimmingCharacters(in: .whitespaces),
            address: reAddress.trimmingCharacters(in: .whitespaces),
            purchaseDate: rePurchaseDate,
            purchasePrice: Double(rePurchasePriceText) ?? 0,
            currentValue: Double(reCurrentValueText) ?? 0,
            monthlyRental: Double(reMonthlyRentalText) ?? 0,
            monthlyMortgage: mortgageAmount,
            linkedExpenseId: expenseId,
            note: note.trimmingCharacters(in: .whitespaces)
        )
        if existingId != nil { financeStore.update(realEstate) } else { financeStore.add(realEstate) }
        return reId
    }

    /// 同步車貸到理財模式的汽車定期支出
    private func syncCarLoanToVehicle(vehicleId: UUID, expenseId: UUID, amount: Double) {
        guard var vehicle = financeStore.vehicles.first(where: { $0.id == vehicleId }) else { return }

        let newEntry = VehicleFixedExpense(
            id: UUID(),
            category: .carLoan,
            amount: amount,
            period: selectedRecurrence == .yearly ? .yearly : .monthly,
            linkedExpenseId: expenseId
        )

        if let existingIdx = vehicle.fixedExpenses.firstIndex(where: { $0.linkedExpenseId == expenseId }) {
            vehicle.fixedExpenses[existingIdx] = VehicleFixedExpense(
                id: vehicle.fixedExpenses[existingIdx].id,
                category: .carLoan,
                amount: amount,
                period: selectedRecurrence == .yearly ? .yearly : .monthly,
                linkedExpenseId: expenseId
            )
        } else {
            vehicle.fixedExpenses.append(newEntry)
        }

        financeStore.update(vehicle)
    }

    // MARK: - 載入編輯資料

    private func loadEditing() {
        guard let expense = editingExpense else { return }
        title = expense.title
        amountText = String(format: "%.0f", expense.amount)
        date = expense.date
        if let vc = expense.variableCategory { selectedVariableCategory = vc }
        if let fc = expense.fixedCategory { selectedFixedCategory = fc }
        if let rec = expense.recurrence { selectedRecurrence = rec }
        if let sub = expense.insuranceSubCategory { selectedInsuranceSubCategory = sub }
        if let sub = expense.loanSubCategory { selectedLoanSubCategory = sub }
        note = expense.note

        // 載入連結的儲蓄險
        if let linkedId = expense.linkedInsuranceId,
           let linked = financeStore.insurances.first(where: { $0.id == linkedId }) {
            insCompany = linked.company
            insCurrency = linked.currency
            insRateText = linked.annualRate > 0 ? String(format: "%.2f", linked.annualRate) : ""
            insStartDate = linked.startDate
            insMaturityDate = linked.maturityDate
        }

        // 載入連結的房地產
        if let linkedId = expense.linkedRealEstateId,
           let linked = financeStore.realEstates.first(where: { $0.id == linkedId }) {
            reAddress = linked.address
            rePurchaseDate = linked.purchaseDate
            rePurchasePriceText = linked.purchasePrice > 0 ? String(format: "%.0f", linked.purchasePrice) : ""
            reCurrentValueText = linked.currentValue > 0 ? String(format: "%.0f", linked.currentValue) : ""
            reMonthlyRentalText = linked.monthlyRental > 0 ? String(format: "%.0f", linked.monthlyRental) : ""
        }

        // 載入變動支出的資產連結
        if expense.expenseType == .variable {
            if expense.linkedVehicleId != nil {
                selectedAssetLink = .vehicle
                selectedVehicleId = expense.linkedVehicleId
                if let veCat = expense.vehicleExpenseCategory {
                    selectedVehicleExpenseCategory = veCat
                }
            } else if let linkedId = expense.linkedStockId,
                      let linked = financeStore.stocks.first(where: { $0.id == linkedId }) {
                selectedAssetLink = .stock
                stockName = linked.name
                stockSymbol = linked.symbol
                stockSharesText = String(format: "%.0f", linked.shares)
                stockPriceText = String(format: "%.2f", linked.purchasePrice)
                stockCurrentPriceText = linked.currentPrice > 0 ? String(format: "%.2f", linked.currentPrice) : ""
            } else if expense.linkedInsuranceId != nil {
                selectedAssetLink = .insurance
                selectedInsuranceLinkId = expense.linkedInsuranceId
            } else if expense.linkedRealEstateId != nil {
                selectedAssetLink = .realEstate
                selectedRealEstateLinkId = expense.linkedRealEstateId
            }
        }
    }

    /// 同步汽車變動支出到理財模式的汽車
    private func syncVehicleVariableExpense(vehicleId: UUID, expenseId: UUID, amount: Double) {
        guard var vehicle = financeStore.vehicles.first(where: { $0.id == vehicleId }) else { return }

        let newEntry = VehicleVariableExpense(
            id: UUID(),
            category: selectedVehicleExpenseCategory,
            amount: amount,
            date: date,
            linkedExpenseId: expenseId
        )

        // 檢查是否已有連結的項目（編輯情境）
        if let existingIdx = vehicle.variableExpenses.firstIndex(where: { $0.linkedExpenseId == expenseId }) {
            vehicle.variableExpenses[existingIdx] = VehicleVariableExpense(
                id: vehicle.variableExpenses[existingIdx].id,
                category: selectedVehicleExpenseCategory,
                amount: amount,
                date: date,
                linkedExpenseId: expenseId
            )
        } else {
            vehicle.variableExpenses.append(newEntry)
        }

        financeStore.update(vehicle)
    }

    // MARK: - 輔助

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label); Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencySymbol = isSavingsInsurance ? insCurrencySymbol : "NT$"
        f.maximumFractionDigits = isSavingsInsurance && insCurrency == .usd ? 2 : 0
        return f.string(from: NSNumber(value: value)) ?? "NT$0"
    }
}

#Preview {
    AddExpenseView(expenseType: .fixed)
        .environmentObject(ExpenseStore())
        .environmentObject(FinanceStore())
}
