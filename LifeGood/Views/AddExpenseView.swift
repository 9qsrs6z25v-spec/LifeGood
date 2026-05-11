import SwiftUI
import MapKit

struct AddExpenseView: View {
    @EnvironmentObject var store: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let expenseType: ExpenseType
    var editingExpense: Expense?
    var preset: AddExpensePreset?

    // MARK: - 基本欄位

    @State private var title = ""
    @State private var amountText = ""
    @State private var date = Date()
    @State private var selectedVariableCategory: VariableCategory = .food
    @State private var selectedTaxSavingSubCategory: TaxSavingSubCategory = .donation
    /// 社交子分類：禮金 / 紅包 / 白包 等
    @State private var selectedSocialSubCategory: SocialSubCategory = .birthdayGift
    /// 社交禮金收受人（家人 + 人際關係多選）
    @State private var selectedSocialRecipients: Set<String> = []
    @State private var showSocialRecipientPopover: Bool = false
    /// 固定支出：列入節稅追蹤；nil 採自動推斷
    @State private var taxDeductibleOverride: Bool? = nil
    @State private var selectedDiningMembers: Set<String> = []
    @State private var showDiningMemberPopover: Bool = false

    /// 支援「人員多選」的變動支出分類
    private static let memberCategories: Set<VariableCategory> = [
        .food, .entertainment, .shopping, .dailyNecessities,
        .medical, .education, .social, .other
    ]
    @State private var selectedFixedCategory: FixedCategory = .rent
    @State private var selectedRecurrence: Recurrence = .monthly
    @State private var note = ""
    @State private var showValidationError = false

    // MARK: - 保險子分類

    @State private var selectedInsuranceSubCategory: InsuranceSubCategory = .savings

    // MARK: - 貸款子分類

    @State private var selectedLoanSubCategory: LoanSubCategory = .mortgage
    @State private var loanTotalAmountText = ""
    @State private var loanYearsText = ""
    @State private var selectedBankMilestoneId: UUID?
    @State private var selectedBankCurrency: String = "NT$"
    @State private var selectedCreditCardMilestoneId: UUID?

    // MARK: - 儲蓄險欄位

    @State private var insCompany = ""
    @State private var insCurrencyCode: String = "NT$"
    @State private var insRateText = ""

    // MARK: - 自訂幣別（左側 NT$ 選擇）

    @State private var selectedCurrencyCode: String = "NT$"
    @State private var insStartDate = Date()
    @State private var insMaturityDate = Calendar.current.date(byAdding: .year, value: 6, to: Date()) ?? Date()

    // MARK: - 房貸欄位（連動房地產）

    @State private var reName = ""
    @State private var reCity = ""
    @State private var reAddress = ""
    @State private var rePurchaseDate = Date()
    @State private var reIsSold = false
    @State private var reSoldDate = Date()
    @State private var rePurchasePriceText = ""   // 萬元
    @State private var reCurrentValueText = ""    // 萬元
    @State private var reMonthlyRentalText = ""   // NT$
    @State private var mortgageLinkExisting = false
    @State private var selectedMortgageRealEstateId: UUID?

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

    /// 變動支出進階模式：關閉時隱藏關聯資產 / 扣款目標 / 名稱欄位（首次預設關閉）
    @AppStorage("addExpense_advanced_mode") private var advancedMode: Bool = false

    /// Sheet 的尺寸：基本模式僅佔半屏左右；進階模式佔滿
    @State private var sheetDetent: PresentationDetent = .large

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
    @State private var selectedRealEstateExpenseCategory: RealEstateExpenseCategory = .renovation
    @State private var realEstateLinkExisting: Bool = true

    // MARK: - 固定支出關聯資產

    enum FixedAssetLinkType: String, CaseIterable, Identifiable {
        case none = "無"
        case vehicle = "汽車"
        case realEstate = "房地產"
        case insurance = "儲蓄險"

        var id: String { rawValue }
    }

    @State private var selectedFixedAssetLink: FixedAssetLinkType = .none
    @State private var fixedLinkVehicleId: UUID?
    @State private var fixedLinkRealEstateId: UUID?
    @State private var fixedLinkInsuranceId: UUID?

    // MARK: - 多張照片
    @State private var photoFileNames: [String] = []

    // MARK: - 飲食店家自動完成

    @StateObject private var restaurantCompleter = RestaurantSearchCompleter()
    @ObservedObject private var locationProvider = LocationProvider.shared
    @State private var placeAddress: String?
    @State private var placeLatitude: Double?
    @State private var placeLongitude: Double?
    @FocusState private var titleFieldFocused: Bool
    @State private var suppressNextCompleterUpdate = false
    /// 是否展開所有候選地點（預設僅顯示 20 個）
    @State private var expandedSuggestions: Bool = false

    // MARK: - 條件判斷

    private var isEditing: Bool { editingExpense != nil }
    private var isInsurance: Bool { expenseType == .fixed && selectedFixedCategory == .insurance }
    private var isSavingsInsurance: Bool { isInsurance && selectedInsuranceSubCategory == .savings }
    private var isLoan: Bool { expenseType == .fixed && selectedFixedCategory == .loan }
    private var isMortgage: Bool { isLoan && selectedLoanSubCategory == .mortgage }
    private var isCarLoan: Bool { isLoan && selectedLoanSubCategory == .car }
    private var showLoanCalcFields: Bool { isCarLoan || isMortgage }
    private var showFixedAssetLink: Bool { expenseType == .fixed && !isInsurance && !isLoan }
    /// 是否為飲食類變動支出（決定要不要顯示餐廳自動完成）
    private var isFoodVariable: Bool {
        expenseType == .variable && selectedVariableCategory == .food
    }

    /// 是否為「需要選地點」的變動支出分類：飲食 / 娛樂 / 購物 / 日用品 / 醫療
    private var supportsPlacePicker: Bool {
        guard expenseType == .variable else { return false }
        return [.food, .entertainment, .shopping, .dailyNecessities, .medical]
            .contains(selectedVariableCategory)
    }

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

    private var insCurrencySymbol: String { isSavingsInsurance ? insCurrencyCode : "NT$" }
    private var insIsUSD: Bool { insCurrencyCode == "US$" || insCurrencyCode == "USD" || insCurrencyCode.lowercased() == "美金" }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                basicInfoSection

                // 變動支出：先選關聯資產，再選分類（基本模式隱藏關聯資產選擇）
                if expenseType == .variable {
                    if advancedMode {
                        assetLinkSection
                        if selectedAssetLink == .vehicle { vehicleLinkSection }
                        if selectedAssetLink == .stock { stockLinkSection }
                        if selectedAssetLink == .insurance { insuranceLinkSection }
                        if selectedAssetLink == .realEstate { realEstateLinkSection }
                    }
                    // 基本模式一律顯示分類；進階模式時若連結汽車/股票/房地產則隱藏分類
                    let suppressCategory = advancedMode && (
                        selectedAssetLink == .vehicle
                        || selectedAssetLink == .stock
                        || selectedAssetLink == .realEstate
                    )
                    if !suppressCategory {
                        categorySection
                    }
                    // 進階模式：分類區塊下方加照片廊
                    if advancedMode {
                        photoGallerySection
                    }
                } else {
                    // 固定支出：先選關聯資產（若適用），再選分類
                    if showFixedAssetLink {
                        fixedAssetLinkSection
                        if selectedFixedAssetLink == .vehicle { fixedVehicleLinkSection }
                        if selectedFixedAssetLink == .realEstate { fixedRealEstateLinkSection }
                        if selectedFixedAssetLink == .insurance { fixedInsuranceLinkSection }
                    }
                    categorySection
                }

                // 固定支出：保險/貸款子分類
                if isInsurance { insuranceSubCategorySection }
                if isLoan { loanSubCategorySection }

                // 固定支出：節稅追蹤 toggle（保險 / 房貸 / 房租 才出現）
                if showTaxDeductibleToggle {
                    taxDeductibleToggleSection
                }

                if isSavingsInsurance {
                    savingsInsuranceSection
                    savingsCalcSection
                } else if isMortgage {
                    mortgageRealEstateSection
                } else if isCarLoan {
                    carLoanVehicleSection
                }

                if showValidationError {
                    Section {
                        Text("請輸入名稱和有效金額").foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle(isEditing ? "編輯\(expenseType.rawValue)" : "新增\(expenseType.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents(
                expenseType == .variable ? [.height(440), .large] : [.large],
                selection: $sheetDetent
            )
            .presentationDragIndicator(.visible)
            .onChange(of: advancedMode) { _, newValue in
                if expenseType == .variable {
                    sheetDetent = newValue ? .large : .height(440)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "儲存" : "新增") { saveExpense() }
                        .bold().foregroundStyle(.green)
                }
            }
            .onAppear {
                loadEditing()
                applyPreset()
                // 依進階開關決定初始 sheet 高度（須在 loadEditing 後再算，因為它可能會打開進階模式）
                if expenseType == .variable {
                    sheetDetent = advancedMode ? .large : .height(440)
                }
            }
            .onChange(of: selectedAssetLink) { _, newValue in
                if newValue == .vehicle {
                    selectedVariableCategory = .vehicle
                } else if newValue == .stock {
                    selectedVariableCategory = .stock
                } else if newValue == .realEstate {
                    selectedVariableCategory = .realEstate
                }
                applyAutoTitleIfLinked()
            }
            .onChange(of: selectedVehicleId) { _, _ in applyAutoTitleIfLinked() }
            .onChange(of: selectedVehicleExpenseCategory) { _, _ in applyAutoTitleIfLinked() }
            .onChange(of: selectedRealEstateLinkId) { _, _ in applyAutoTitleIfLinked() }
            .onChange(of: realEstateLinkExisting) { _, _ in applyAutoTitleIfLinked() }
            .onChange(of: selectedRealEstateExpenseCategory) { _, _ in
                applyAutoTitleIfLinked()
            }
            .onChange(of: selectedMortgageRealEstateId) { _, _ in applyAutoTitleIfLinked() }
            .onChange(of: mortgageLinkExisting) { _, _ in applyAutoTitleIfLinked() }
            .onChange(of: note) { _, _ in
                if isMortgage { applyAutoTitleIfLinked() }
            }
            .onChange(of: selectedFixedAssetLink) { _, _ in applyAutoTitleIfLinked() }
            .onChange(of: fixedLinkVehicleId) { _, _ in applyAutoTitleIfLinked() }
            .onChange(of: selectedFixedCategory) { _, _ in applyAutoTitleIfLinked() }
            .onChange(of: selectedLoanSubCategory) { _, _ in applyAutoTitleIfLinked() }
        }
    }

    // MARK: - 連結資產名稱自動生成

    /// 若此筆支出連結到理財模式中的具體項目（車輛/房地產），回傳自動生成的名稱「項目 N：型號-類別」。
    private var linkedAssetTitle: String? {
        // 變動支出 - 汽車
        if expenseType == .variable, selectedAssetLink == .vehicle,
           let id = selectedVehicleId,
           let vehicle = financeStore.vehicles.first(where: { $0.id == id }) {
            let n = itemNumber(in: vehicle.variableExpenses) { $0.linkedExpenseId }
            return "項目 \(n)：\(vehicle.name)-\(selectedVehicleExpenseCategory.rawValue)"
        }
        // 變動支出 - 房地產
        if expenseType == .variable, selectedAssetLink == .realEstate,
           let id = selectedRealEstateLinkId,
           let re = financeStore.realEstates.first(where: { $0.id == id }) {
            let n = itemNumber(in: re.variableExpenses) { $0.linkedExpenseId }
            return "項目 \(n)：\(re.name)-\(selectedRealEstateExpenseCategory.rawValue)"
        }
        // 固定支出 - 車貸
        if isCarLoan,
           let id = selectedVehicleId,
           let vehicle = financeStore.vehicles.first(where: { $0.id == id }) {
            let n = itemNumber(in: vehicle.fixedExpenses) { $0.linkedExpenseId }
            return "項目 \(n)：\(vehicle.name)-車貸"
        }
        // 固定支出 - 房貸（連動既有物件）
        if isMortgage, mortgageLinkExisting,
           let id = selectedMortgageRealEstateId,
           let re = financeStore.realEstates.first(where: { $0.id == id }) {
            let n = itemNumber(in: re.mortgageItems) { $0.linkedExpenseId }
            let trimmedNote = note.trimmingCharacters(in: .whitespaces)
            let mortgageName: String
            if !trimmedNote.isEmpty {
                mortgageName = trimmedNote
            } else if let expenseId = editingExpense?.id,
                      let item = re.mortgageItems.first(where: { $0.linkedExpenseId == expenseId }),
                      !item.title.trimmingCharacters(in: .whitespaces).isEmpty {
                mortgageName = item.title.trimmingCharacters(in: .whitespaces)
            } else {
                mortgageName = "房貸"
            }
            return "【\(re.name)】貸款\(n)-\(mortgageName)"
        }
        // 固定支出 - 一般類別連結汽車
        if expenseType == .fixed, showFixedAssetLink, selectedFixedAssetLink == .vehicle,
           let id = fixedLinkVehicleId,
           let vehicle = financeStore.vehicles.first(where: { $0.id == id }) {
            let n = itemNumber(in: vehicle.fixedExpenses) { $0.linkedExpenseId }
            return "項目 \(n)：\(vehicle.name)-\(selectedFixedCategory.rawValue)"
        }
        return nil
    }

    private func itemNumber<T>(in items: [T], idExtractor: (T) -> UUID?) -> Int {
        if let id = editingExpense?.id,
           let idx = items.firstIndex(where: { idExtractor($0) == id }) {
            return idx + 1
        }
        return items.count + 1
    }

    private func applyAutoTitleIfLinked() {
        if let auto = linkedAssetTitle {
            title = auto
        }
    }

    // MARK: - 基本資訊

    private var basicInfoSection: some View {
        Section {
            // 金額（永遠顯示）
            HStack {
                if isSavingsInsurance {
                    Text(insCurrencySymbol).foregroundStyle(.secondary)
                } else {
                    Menu {
                        Button {
                            selectedCurrencyCode = "NT$"
                        } label: {
                            if selectedCurrencyCode == "NT$" {
                                Label("NT$", systemImage: "checkmark")
                            } else {
                                Text("NT$")
                            }
                        }
                        ForEach(store.currencyRates) { rate in
                            Button {
                                selectedCurrencyCode = rate.code
                            } label: {
                                if selectedCurrencyCode == rate.code {
                                    Label("\(rate.code)（1=\(rateDisplay(rate.rate)) 元）", systemImage: "checkmark")
                                } else {
                                    Text("\(rate.code)（1=\(rateDisplay(rate.rate)) 元）")
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Text(selectedCurrencyCode)
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                TextField(isMortgage ? "每月房貸金額" : (isCarLoan ? "每月車貸金額" : (isSavingsInsurance ? "保費金額" : "金額")), text: $amountText)
                    .keyboardType(.decimalPad)
            }

            if showLoanCalcFields {
                HStack {
                    Text("NT$").foregroundStyle(.secondary)
                    TextField("總貸款金額", text: $loanTotalAmountText)
                        .keyboardType(.decimalPad)
                }
            }

            // 日期（永遠顯示，儲蓄險除外）
            if !isSavingsInsurance {
                DatePicker(showLoanCalcFields ? "開始日期" : "日期", selection: $date, displayedComponents: .date)
            }

            // 名稱（進階模式或固定支出或飲食類才顯示，移到日期下方）
            if showNameField {
                if linkedAssetTitle != nil {
                    HStack {
                        Text("名稱")
                        Spacer()
                        Text(title)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                    }
                } else if supportsPlacePicker {
                    placeNameAutocomplete
                } else {
                    TextField(expenseType == .variable ? "名稱（留空自動以分類為名）" : "名稱", text: $title)
                }
            }

            // 扣款目標（進階模式或固定支出才顯示）
            if showBankPicker && !isSavingsInsurance {
                bankPicker
            }

            if showLoanCalcFields {
                HStack {
                    TextField("貸款年限", text: $loanYearsText)
                        .keyboardType(.decimalPad)
                    Text("年").foregroundStyle(.secondary)
                }
                loanCalcRow
            }

            // 備註（移到基本資訊最下方；變動支出基本模式時隱藏）
            if expenseType == .fixed || advancedMode {
                TextField("備註", text: $note, axis: .vertical).lineLimit(3)
            }
        } header: {
            HStack {
                Text("基本資訊")
                Spacer()
                if expenseType == .variable {
                    Toggle("進階", isOn: $advancedMode.animation())
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(.caption2)
                }
            }
            .textCase(.none)
        }
    }

    /// 是否顯示名稱欄位：進階模式 / 固定支出 / 已連結資產 / 飲食類別（要選店家）都顯示
    private var showNameField: Bool {
        expenseType == .fixed || advancedMode || linkedAssetTitle != nil || supportsPlacePicker
    }

    /// 是否顯示扣款目標選單
    private var showBankPicker: Bool {
        let hasAccounts = !bankMilestones.isEmpty || !creditCardMilestones.isEmpty
        guard hasAccounts else { return false }
        return expenseType == .fixed || advancedMode
    }

    private func computedLoanRate() -> Double? {
        let monthly = Double(amountText) ?? 0
        let total = Double(loanTotalAmountText) ?? 0
        let years = Double(loanYearsText) ?? 0
        guard monthly > 0, total > 0, years > 0 else { return nil }
        let totalPaid = monthly * 12 * years
        let totalInterest = totalPaid - total
        return (totalInterest / total / years) * 100
    }

    @ViewBuilder
    private var loanCalcRow: some View {
        let monthly = Double(amountText) ?? 0
        let total = Double(loanTotalAmountText) ?? 0
        let years = Double(loanYearsText) ?? 0
        if monthly > 0 && total > 0 && years > 0 {
            let totalPaid = monthly * 12 * years
            let totalInterest = totalPaid - total
            let avgAnnualRate = (totalInterest / total / years) * 100
            VStack(spacing: 6) {
                HStack {
                    Text("貸款總繳").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(fmtCurrency(totalPaid)).font(.caption.bold())
                }
                HStack {
                    Text("利息總額").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(fmtCurrency(totalInterest)).font(.caption.bold()).foregroundStyle(.orange)
                }
                HStack {
                    Text("實際年利率（估算）").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.2f%%", avgAnnualRate)).font(.caption.bold()).foregroundStyle(.blue)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func fmtCurrency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "NT$0"
    }

    // MARK: - 多張照片 Section

    /// 在進階模式分類下方顯示照片廊：拍照 / 相簿多選 / 看大圖 / 刪除
    private var photoGallerySection: some View {
        let expenseId = editingExpense?.id ?? generatedNewExpenseId
        return Section {
            MultiPhotoGallery(
                fileNames: $photoFileNames,
                urlFor: { Expense.photoURL(for: $0) },
                onSaveImage: { data in
                    Expense.savePhoto(data, expenseId: expenseId, photoId: UUID())
                },
                onDeleteFile: { name in
                    Expense.deletePhoto(name)
                },
                title: "照片"
            )
            .padding(.vertical, 4)
        } header: {
            Text("照片")
        } footer: {
            Text("可拍照或從相簿一次選多張，會跟著本筆支出儲存。儲存後會在美食地圖等頁面顯示。")
        }
    }

    /// 為新增模式提供穩定的 expenseId（避免每次 body 重建時產生新 UUID）
    @State private var generatedNewExpenseId: UUID = UUID()

    // MARK: - 地點欄位（飲食 / 娛樂 / 購物 / 日用品 / 醫療）

    /// 名稱欄位列：輸入店名同時跑出歷史地點 + Apple Maps 候選清單
    @ViewBuilder
    private var placeNameAutocomplete: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: placeIcon)
                    .foregroundStyle(placeIconColor)
                    .frame(width: 22)
                TextField(placeNamePrompt, text: $title)
                    .focused($titleFieldFocused)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                if placeLatitude != nil {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
                if !title.isEmpty {
                    Button {
                        title = ""
                        clearPlace()
                        expandedSuggestions = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let addr = placeAddress, !addr.isEmpty, placeLatitude != nil {
                Text(addr)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.leading, 32)
            }
            if titleFieldFocused {
                placeSuggestionsList
            }
        }
        .padding(.vertical, 2)
        .onAppear {
            LocationProvider.shared.requestIfNeeded()
            restaurantCompleter.setRegion(LocationProvider.shared.searchRegion)
            if !title.isEmpty { restaurantCompleter.queryFragment = title }
        }
        .onChange(of: title) { _, newValue in
            if suppressNextCompleterUpdate {
                suppressNextCompleterUpdate = false
                return
            }
            restaurantCompleter.queryFragment = newValue
            expandedSuggestions = false
            // 重新輸入時清掉之前選定的座標 / 地址
            if placeLatitude != nil || placeLongitude != nil || placeAddress != nil {
                clearPlace()
            }
        }
        .onChange(of: locationProvider.lastLocation) { _, _ in
            restaurantCompleter.setRegion(LocationProvider.shared.searchRegion)
            if !title.isEmpty { restaurantCompleter.queryFragment = title }
        }
    }

    private var placeNamePrompt: String {
        switch selectedVariableCategory {
        case .food: return "店名 / 餐廳"
        case .entertainment: return "電影院 / KTV / 場館"
        case .shopping: return "百貨 / 商家"
        case .dailyNecessities: return "賣場 / 超市"
        case .medical: return "醫院 / 診所 / 藥局"
        default: return "名稱"
        }
    }

    /// 候選清單：預設顯示 20 個項目，21 格為「顯示更多」按鈕；展開後顯示全部，並換成「收合」
    @ViewBuilder
    private var placeSuggestionsList: some View {
        let all = allPlaceSuggestions
        if !all.isEmpty {
            let limit = 20
            let visible: [PlaceSuggestion] = expandedSuggestions ? all : Array(all.prefix(limit))
            let hiddenCount = max(0, all.count - limit)
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { item in
                            Button {
                                applySuggestion(item)
                            } label: {
                                placeSuggestionRow(item)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 52)
                        }
                        if !expandedSuggestions && hiddenCount > 0 {
                            Button {
                                expandedSuggestions = true
                            } label: {
                                HStack {
                                    Image(systemName: "chevron.down.circle.fill")
                                        .foregroundStyle(.blue)
                                    Text("顯示更多 (\(hiddenCount))")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.blue)
                                    Spacer()
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        } else if expandedSuggestions && all.count > limit {
                            Button {
                                expandedSuggestions = false
                            } label: {
                                HStack {
                                    Image(systemName: "chevron.up.circle.fill")
                                        .foregroundStyle(.secondary)
                                    Text("收合")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
            )
        } else if !title.trimmingCharacters(in: .whitespaces).isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                Text("找不到符合的地點，將以「\(title)」儲存。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private func placeSuggestionRow(_ item: PlaceSuggestion) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(item.iconColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: item.iconName)
                    .foregroundStyle(item.iconColor)
                    .font(.callout)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "arrow.up.left")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    /// 合併「之前去過」（依名稱含查詢字串）與 Apple Maps POI 結果，去重後產生候選清單
    private var allPlaceSuggestions: [PlaceSuggestion] {
        let q = title.trimmingCharacters(in: .whitespaces).lowercased()
        var seenKeys: Set<String> = []
        var output: [PlaceSuggestion] = []

        // 1) 之前去過：同類別、含座標、名稱含查詢字串（空字串時也顯示所有歷史）
        for exp in store.expenses
            where exp.expenseType == .variable
                && exp.variableCategory == selectedVariableCategory
                && exp.placeLatitude != nil
                && exp.placeLongitude != nil
                && !exp.title.trimmingCharacters(in: .whitespaces).isEmpty {
            if !q.isEmpty && !exp.title.lowercased().contains(q) { continue }
            let key = "past|\(exp.title.lowercased())|\(exp.placeAddress?.lowercased() ?? "")"
            if seenKeys.contains(key) { continue }
            seenKeys.insert(key)
            output.append(PlaceSuggestion(
                id: key,
                source: .past,
                title: exp.title,
                subtitle: exp.placeAddress ?? "",
                completion: nil,
                latitude: exp.placeLatitude,
                longitude: exp.placeLongitude,
                address: exp.placeAddress
            ))
        }

        // 2) Apple Maps：搜尋字串非空才會有結果
        for c in restaurantCompleter.results {
            let key = "apple|\(c.title.lowercased())|\(c.subtitle.lowercased())"
            if seenKeys.contains(key) { continue }
            // 名稱完全相同且同地址的 past 已存在時略過
            let pastKey = "past|\(c.title.lowercased())|\(c.subtitle.lowercased())"
            if seenKeys.contains(pastKey) { continue }
            seenKeys.insert(key)
            output.append(PlaceSuggestion(
                id: key,
                source: .apple,
                title: c.title,
                subtitle: c.subtitle,
                completion: c,
                latitude: nil,
                longitude: nil,
                address: c.subtitle.isEmpty ? nil : c.subtitle
            ))
        }

        return output
    }

    /// 套用使用者選擇的候選
    private func applySuggestion(_ item: PlaceSuggestion) {
        suppressNextCompleterUpdate = true
        title = item.title
        expandedSuggestions = false
        switch item.source {
        case .past:
            placeAddress = item.address
            placeLatitude = item.latitude
            placeLongitude = item.longitude
            titleFieldFocused = false
        case .apple:
            // 先帶 fallback，再呼叫 resolve 補完整地址 / 座標
            placeAddress = item.address
            placeLatitude = nil
            placeLongitude = nil
            if let c = item.completion {
                restaurantCompleter.resolve(c) { mapItem in
                    if let mapItem {
                        let resolved = mapItem.formattedAddress
                        placeAddress = resolved.isEmpty ? item.address : resolved
                        placeLatitude = mapItem.placemark.coordinate.latitude
                        placeLongitude = mapItem.placemark.coordinate.longitude
                    }
                }
            }
            titleFieldFocused = false
        }
    }

    /// 清掉先前綁定的地點資料
    private func clearPlace() {
        placeAddress = nil
        placeLatitude = nil
        placeLongitude = nil
    }

    private var placeIcon: String {
        switch selectedVariableCategory {
        case .food: return "fork.knife.circle.fill"
        case .entertainment: return "gamecontroller.fill"
        case .shopping: return "bag.fill"
        case .dailyNecessities: return "house.fill"
        case .medical: return "cross.case.fill"
        default: return "mappin.circle.fill"
        }
    }

    private var placeIconColor: Color {
        switch selectedVariableCategory {
        case .food: return .orange
        case .entertainment: return .pink
        case .shopping: return .cyan
        case .dailyNecessities: return .green
        case .medical: return .red
        default: return .secondary
        }
    }

    // MARK: - 分類

    private var bankMilestones: [LifeMilestone] {
        lifeStore.milestones.filter {
            $0.category == .achievement && $0.financeSubCategory == .bank
        }
    }

    private var creditCardMilestones: [LifeMilestone] {
        lifeStore.milestones.filter {
            $0.category == .achievement && $0.financeSubCategory == .creditCard
        }
    }

    private func bankCurrencies(for ms: LifeMilestone) -> [String] {
        let codes = (ms.bankDeposits ?? [])
            .filter { !$0.isWithdrawal }
            .map(\.currencyCode)
        var unique: [String] = []
        for c in codes where !unique.contains(c) { unique.append(c) }
        return unique.isEmpty ? ["NT$"] : unique
    }

    /// 計算銀行的目前總額（含信用卡彙總扣款）
    private func bankBalance(for ms: LifeMilestone) -> Double {
        let now = Date()
        var total: Double = 0
        for dep in ms.bankDeposits ?? [] {
            guard dep.date <= now else { continue }
            if let expId = dep.linkedExpenseId,
               let exp = store.expenses.first(where: { $0.id == expId }),
               exp.linkedCreditCardMilestoneId != nil {
                continue
            }
            total += dep.isWithdrawal ? -dep.amount : dep.amount
        }
        let cards = lifeStore.milestones.filter {
            $0.financeSubCategory == .creditCard && $0.linkedBankMilestoneId == ms.id
        }
        for card in cards {
            let exps = store.expenses.filter {
                $0.linkedCreditCardMilestoneId == card.id && $0.date <= now
            }
            for exp in exps { total -= exp.amount }
        }
        return total
    }

    private func formatBankBalance(_ value: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        if abs(value) >= 10000 {
            let wan = value / 10000
            let str = f.string(from: NSNumber(value: wan)) ?? "0"
            return "NT$ \(str)萬"
        } else {
            let str = f.string(from: NSNumber(value: value)) ?? "0"
            return "NT$ \(str)"
        }
    }

    private var bankPickerLabel: String {
        if let id = selectedCreditCardMilestoneId,
           let card = creditCardMilestones.first(where: { $0.id == id }) {
            let cardName = card.cardName ?? card.title
            if let bankId = card.linkedBankMilestoneId,
               let bank = bankMilestones.first(where: { $0.id == bankId }) {
                return "\(cardName) → \(bank.bankName ?? bank.title)"
            }
            return cardName
        }
        if let id = selectedBankMilestoneId,
           let ms = bankMilestones.first(where: { $0.id == id }) {
            let name = ms.bankName ?? ms.title
            return "\(name) · \(selectedBankCurrency)"
        }
        return "未選擇"
    }

    private var bankPicker: some View {
        HStack {
            Text("扣款目標").foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("不指定") {
                    selectedBankMilestoneId = nil
                    selectedBankCurrency = "NT$"
                    selectedCreditCardMilestoneId = nil
                }
                if !bankMilestones.isEmpty {
                    Section("銀行") {
                        ForEach(bankMilestones) { ms in
                            let currencies = bankCurrencies(for: ms)
                            let name = ms.bankName ?? ms.title
                            let balanceLabel = "\(name)（\(formatBankBalance(bankBalance(for: ms)))）"
                            if currencies.count > 1 {
                                Menu(balanceLabel) {
                                    ForEach(currencies, id: \.self) { code in
                                        Button(code) {
                                            selectedBankMilestoneId = ms.id
                                            selectedBankCurrency = code
                                            selectedCreditCardMilestoneId = nil
                                        }
                                    }
                                }
                            } else {
                                Button(balanceLabel) {
                                    selectedBankMilestoneId = ms.id
                                    selectedBankCurrency = currencies.first ?? "NT$"
                                    selectedCreditCardMilestoneId = nil
                                }
                            }
                        }
                    }
                }
                if !creditCardMilestones.isEmpty {
                    Section("信用卡") {
                        ForEach(creditCardMilestones) { card in
                            let cardName = card.cardName ?? card.title
                            let bankInfo: String? = {
                                guard let bankId = card.linkedBankMilestoneId,
                                      let bank = bankMilestones.first(where: { $0.id == bankId }) else { return nil }
                                let bankName = bank.bankName ?? bank.title
                                return "\(bankName)（\(formatBankBalance(bankBalance(for: bank)))）"
                            }()
                            Button(bankInfo.map { "\(cardName) → \($0)" } ?? cardName) {
                                selectedCreditCardMilestoneId = card.id
                                selectedBankMilestoneId = card.linkedBankMilestoneId
                                selectedBankCurrency = "NT$"
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(bankPickerLabel)
                        .foregroundStyle((selectedBankMilestoneId == nil && selectedCreditCardMilestoneId == nil) ? .secondary : .primary)
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 飲食人員多選清單（popover 內容，可連續勾選不會關閉）
    private var diningMemberSelectorList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("選擇人員")
                    .font(.headline)
                Spacer()
                Button("完成") { showDiningMemberPopover = false }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))

            ScrollView {
                VStack(spacing: 0) {
                    diningMemberRow(name: nil, label: "不指定")
                    Divider()
                    ForEach(familyNames, id: \.self) { name in
                        diningMemberRow(name: name, label: name)
                        if name != familyNames.last { Divider() }
                    }
                }
            }
        }
    }

    private func diningMemberRow(name: String?, label: String) -> some View {
        // name == nil 代表「不指定」
        let isSelected: Bool = {
            if let n = name { return selectedDiningMembers.contains(n) }
            return selectedDiningMembers.isEmpty
        }()
        return Button {
            if let n = name {
                if selectedDiningMembers.contains(n) {
                    selectedDiningMembers.remove(n)
                } else {
                    selectedDiningMembers.insert(n)
                }
            } else {
                selectedDiningMembers.removeAll()
            }
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .green : .secondary)
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 多選人員的顯示文字：未選 / 1 人 / N 人
    private var diningMembersLabel: String {
        if selectedDiningMembers.isEmpty { return "不指定" }
        let ordered = familyNames.filter { selectedDiningMembers.contains($0) }
        if ordered.count == 1 { return ordered[0] }
        return "\(ordered.count) 人"
    }

    /// 將多選人員 Set 序列化為 `、` 分隔字串（向下相容單名格式）
    private var diningMembersString: String {
        guard !selectedDiningMembers.isEmpty else { return "" }
        return familyNames.filter { selectedDiningMembers.contains($0) }
            .joined(separator: "、")
    }

    private var familyNames: [String] {
        var names: [String] = []
        let myName = lifeStore.profile.chineseName
        if !myName.isEmpty { names.append(myName) }
        for m in lifeStore.familyMembers where !m.chineseName.isEmpty {
            names.append(m.chineseName)
        }
        return names
    }

    // MARK: - 社交禮金收受人選單

    /// 候選人來源：家人 + 人際關係（朋友 / 同事 / 客戶）
    private var socialRecipientCandidates: [(group: String, names: [String])] {
        var groups: [(String, [String])] = []
        let famNames = lifeStore.familyMembers
            .map { $0.chineseName }
            .filter { !$0.isEmpty }
        if !famNames.isEmpty { groups.append(("家人", famNames)) }
        let relGroups = Dictionary(grouping: lifeStore.relationships) { $0.group.rawValue }
        for key in ["朋友", "同事", "客戶", "家人", "其他"] {
            let names = (relGroups[key] ?? [])
                .map { $0.name }
                .filter { !$0.isEmpty }
            if !names.isEmpty { groups.append((key, names)) }
        }
        // 去重（保留首次出現順序）
        return groups.map { (g, list) in
            var seen = Set<String>(); var unique: [String] = []
            for n in list where !seen.contains(n) { seen.insert(n); unique.append(n) }
            return (g, unique)
        }
    }

    private var socialRecipientLabel: String {
        if selectedSocialRecipients.isEmpty { return "選擇收受人" }
        return selectedSocialRecipients.sorted().joined(separator: "、")
    }

    private var socialRecipientString: String {
        guard !selectedSocialRecipients.isEmpty else { return "" }
        return selectedSocialRecipients.sorted().joined(separator: "、")
    }

    private var socialRecipientSelectorList: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selectedSocialRecipients.removeAll()
                    } label: {
                        HStack {
                            Image(systemName: selectedSocialRecipients.isEmpty
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedSocialRecipients.isEmpty ? Color.green : Color.secondary)
                            Text("不指定")
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                ForEach(socialRecipientCandidates, id: \.group) { group in
                    Section(group.group) {
                        ForEach(group.names, id: \.self) { name in
                            Button {
                                if selectedSocialRecipients.contains(name) {
                                    selectedSocialRecipients.remove(name)
                                } else {
                                    selectedSocialRecipients.insert(name)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: selectedSocialRecipients.contains(name)
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedSocialRecipients.contains(name) ? Color.green : Color.secondary)
                                    Text(name)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("收受人")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { showSocialRecipientPopover = false }
                        .bold().foregroundStyle(.green)
                }
            }
        }
    }

    private var categorySection: some View {
        Section("分類") {
            if expenseType == .variable {
                HStack {
                    Picker("類別", selection: $selectedVariableCategory) {
                        ForEach(VariableCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // 人員選擇（飲食 / 娛樂 / 購物 / 日用 / 醫療 / 教育 / 社交 / 其他）只在進階模式才顯示，支援多選 + 點外部才關閉
                    if advancedMode && Self.memberCategories.contains(selectedVariableCategory) && !familyNames.isEmpty {
                        Divider()
                        Button {
                            showDiningMemberPopover = true
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "person.2.fill").font(.caption)
                                Text(diningMembersLabel).lineLimit(1)
                                Image(systemName: "chevron.down").font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showDiningMemberPopover) {
                            diningMemberSelectorList
                                .presentationDetents([.height(380), .medium])
                                .presentationDragIndicator(.visible)
                        }
                    }
                }

                // 節稅子分類（連動到稅務頁）
                if selectedVariableCategory == .taxSaving {
                    Picker("節稅項目", selection: $selectedTaxSavingSubCategory) {
                        ForEach(TaxSavingSubCategory.allCases) { sub in
                            Label(sub.rawValue, systemImage: sub.icon).tag(sub)
                        }
                    }
                    Text(selectedTaxSavingSubCategory.limitNote)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // 社交子分類 + 收受人（連動家人履歷）
                if selectedVariableCategory == .social && advancedMode {
                    HStack {
                        Picker("禮金種類", selection: $selectedSocialSubCategory) {
                            ForEach(SocialSubCategory.allCases) { sub in
                                Label(sub.rawValue, systemImage: sub.icon).tag(sub)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        if !socialRecipientCandidates.isEmpty {
                            Divider()
                            Button {
                                showSocialRecipientPopover = true
                            } label: {
                                HStack(spacing: 2) {
                                    Image(systemName: "gift.fill").font(.caption)
                                    Text(socialRecipientLabel).lineLimit(1)
                                    Image(systemName: "chevron.down").font(.caption2)
                                }
                                .foregroundStyle(.pink)
                            }
                            .buttonStyle(.plain)
                            .sheet(isPresented: $showSocialRecipientPopover) {
                                socialRecipientSelectorList
                                    .presentationDetents([.height(420), .medium])
                                    .presentationDragIndicator(.visible)
                            }
                        }
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
            Picker("連動方式", selection: $realEstateLinkExisting) {
                Text("新增物件").tag(false)
                Text("選擇既有").tag(true)
            }
            .pickerStyle(.segmented)

            if realEstateLinkExisting {
                if financeStore.realEstates.isEmpty {
                    Text("尚無房地產，請切換至「新增物件」")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Picker("選擇物件", selection: $selectedRealEstateLinkId) {
                        Text("請選擇").tag(nil as UUID?)
                        ForEach(financeStore.realEstates) { re in
                            Text("\(re.name)\(!re.address.isEmpty ? " (\(re.address))" : "")").tag(re.id as UUID?)
                        }
                    }
                }
            } else {
                TextField("物件名稱", text: $reName)
                Picker("縣市", selection: $reCity) {
                    Text("請選擇").tag("")
                    ForEach(AddRealEstateView.taiwanCities, id: \.self) { c in
                        Text(c).tag(c)
                    }
                }
                TextField("地址（可多行）", text: $reAddress, axis: .vertical)
                    .lineLimit(2...5)
                DatePicker("購入日期", selection: $rePurchaseDate, displayedComponents: .date)
                Toggle("已售出", isOn: $reIsSold)
                if reIsSold {
                    DatePicker("售出日期", selection: $reSoldDate, in: rePurchaseDate..., displayedComponents: .date)
                }
                HStack {
                    TextField("購入價格", text: $rePurchasePriceText).keyboardType(.decimalPad)
                    Text("萬元").foregroundStyle(.secondary)
                }
                HStack {
                    TextField("目前估值", text: $reCurrentValueText).keyboardType(.decimalPad)
                    Text("萬元").foregroundStyle(.secondary)
                }
                HStack {
                    Text("NT$").foregroundStyle(.secondary)
                    TextField("月租金收入（選填）", text: $reMonthlyRentalText).keyboardType(.decimalPad)
                }
            }

            Picker("支出類別", selection: $selectedRealEstateExpenseCategory) {
                ForEach(RealEstateExpenseCategory.allCases) { cat in
                    Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                }
            }
        } header: {
            Text("房地產（連動理財模式）")
        } footer: {
            Text(realEstateLinkExisting
                 ? "房屋價金將同步至已支出房屋金額章節，其餘類別同步至變動支出章節。"
                 : "儲存後將自動在理財模式建立房地產物件，並將本筆支出同步至對應章節。")
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
            Text("選擇後分類自動設為「汽車」並隱藏分類區塊，名稱自動生成為「項目 N：型號-支出類別」並轉為唯讀。支出類別會依照車輛動力類型自動篩選。")
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

    // MARK: - 節稅追蹤（固定支出 toggle）

    /// 此筆固定支出是否會顯示節稅 toggle
    private var showTaxDeductibleToggle: Bool {
        guard expenseType == .fixed else { return false }
        if selectedFixedCategory == .insurance { return true }
        if selectedFixedCategory == .loan && selectedLoanSubCategory == .mortgage { return true }
        if selectedFixedCategory == .rent { return true }
        return false
    }

    /// 自動推斷預設值（與 Expense.autoTaxDeductible 同邏輯）
    private var autoTaxDeductibleDefault: Bool {
        if selectedFixedCategory == .insurance { return selectedInsuranceSubCategory != .savings }
        if selectedFixedCategory == .loan && selectedLoanSubCategory == .mortgage { return true }
        if selectedFixedCategory == .rent { return true }
        return false
    }

    private var inferredTaxSavingSubLabel: String {
        if selectedFixedCategory == .insurance { return TaxSavingSubCategory.insurance.rawValue }
        if selectedFixedCategory == .loan && selectedLoanSubCategory == .mortgage { return TaxSavingSubCategory.mortgage.rawValue }
        if selectedFixedCategory == .rent { return TaxSavingSubCategory.rent.rawValue }
        return ""
    }

    private var inferredTaxSavingLimitNote: String {
        if selectedFixedCategory == .insurance { return TaxSavingSubCategory.insurance.limitNote }
        if selectedFixedCategory == .loan && selectedLoanSubCategory == .mortgage { return TaxSavingSubCategory.mortgage.limitNote }
        if selectedFixedCategory == .rent { return TaxSavingSubCategory.rent.limitNote }
        return ""
    }

    private var taxDeductibleToggleSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { taxDeductibleOverride ?? autoTaxDeductibleDefault },
                set: { taxDeductibleOverride = $0 }
            )) {
                Label("列入節稅追蹤", systemImage: "lightbulb.fill")
                    .foregroundStyle(.green)
            }
        } header: {
            Text("稅務")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("開啟後本筆固定支出會以「\(inferredTaxSavingSubLabel)」計入稅務頁節稅累積。")
                if !inferredTaxSavingLimitNote.isEmpty {
                    Text(inferredTaxSavingLimitNote)
                        .foregroundStyle(.tertiary)
                }
                if isSavingsInsurance {
                    Text("注意：儲蓄險預設不列入扣除額；若你的方案含人身保險成分，可手動開啟。")
                        .foregroundStyle(.orange)
                }
            }
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

    // MARK: - 房貸連動房地產

    private var mortgageRealEstateSection: some View {
        Section {
            Picker("連動方式", selection: $mortgageLinkExisting) {
                Text("新增物件").tag(false)
                Text("選擇既有").tag(true)
            }
            .pickerStyle(.segmented)

            if mortgageLinkExisting {
                if financeStore.realEstates.isEmpty {
                    Text("尚無房地產，請先在理財模式新增物件")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Picker("選擇物件", selection: $selectedMortgageRealEstateId) {
                        Text("請選擇").tag(nil as UUID?)
                        ForEach(financeStore.realEstates) { re in
                            Text("\(re.name)\(!re.address.isEmpty ? " (\(re.address))" : "")")
                                .tag(re.id as UUID?)
                        }
                    }
                }
            } else {
                TextField("物件名稱", text: $reName)
                Picker("縣市", selection: $reCity) {
                    Text("請選擇").tag("")
                    ForEach(AddRealEstateView.taiwanCities, id: \.self) { c in
                        Text(c).tag(c)
                    }
                }
                TextField("地址（可多行）", text: $reAddress, axis: .vertical)
                    .lineLimit(2...5)
                DatePicker("購入日期", selection: $rePurchaseDate, displayedComponents: .date)
                Toggle("已售出", isOn: $reIsSold)
                if reIsSold {
                    DatePicker("售出日期", selection: $reSoldDate, in: rePurchaseDate..., displayedComponents: .date)
                }
                HStack {
                    TextField("購入價格", text: $rePurchasePriceText).keyboardType(.decimalPad)
                    Text("萬元").foregroundStyle(.secondary)
                }
                HStack {
                    TextField("目前估值", text: $reCurrentValueText).keyboardType(.decimalPad)
                    Text("萬元").foregroundStyle(.secondary)
                }
                HStack {
                    Text("NT$").foregroundStyle(.secondary)
                    TextField("月租金收入（選填）", text: $reMonthlyRentalText).keyboardType(.decimalPad)
                }
            }
        } header: {
            Text("房地產資訊（連動理財模式）")
        } footer: {
            Text(mortgageLinkExisting
                 ? "儲存後將自動在選擇的房地產物件中新增對應的房貸紀錄。"
                 : "儲存後將自動在理財模式的房地產中建立或更新對應物件（價格以萬元為單位，例如 1500 代表 NT$15,000,000）。")
        }
    }

    // MARK: - 儲蓄險詳細欄位

    private var savingsInsuranceSection: some View {
        Group {
            Section("繳費設定") {
                HStack {
                    Text("幣別")
                    Spacer()
                    Menu {
                        Button {
                            insCurrencyCode = "NT$"
                        } label: {
                            if insCurrencyCode == "NT$" {
                                Label("NT$", systemImage: "checkmark")
                            } else {
                                Text("NT$")
                            }
                        }
                        ForEach(store.currencyRates) { rate in
                            Button {
                                insCurrencyCode = rate.code
                            } label: {
                                if insCurrencyCode == rate.code {
                                    Label("\(rate.code)（1=\(rateDisplay(rate.rate)) 元）", systemImage: "checkmark")
                                } else {
                                    Text("\(rate.code)（1=\(rateDisplay(rate.rate)) 元）")
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Text(insCurrencyCode)
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                        .foregroundStyle(.secondary)
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

    // MARK: - 固定支出關聯資產

    private var fixedAssetLinkSection: some View {
        Section {
            Picker("關聯資產", selection: $selectedFixedAssetLink) {
                ForEach(FixedAssetLinkType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("關聯理財資產（選填）")
        } footer: {
            Text("選擇後可將此筆固定支出連結到理財模式的對應項目。")
        }
    }

    private var fixedVehicleLinkSection: some View {
        Section("汽車（連動理財模式）") {
            if financeStore.vehicles.isEmpty {
                Text("尚無車輛，請先在理財模式新增汽車")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Picker("選擇車輛", selection: $fixedLinkVehicleId) {
                    Text("請選擇").tag(nil as UUID?)
                    ForEach(financeStore.vehicles) { v in
                        Text("\(v.name)\(!v.brand.isEmpty ? " (\(v.brand))" : "")").tag(v.id as UUID?)
                    }
                }
            }
        }
    }

    private var fixedRealEstateLinkSection: some View {
        Section("房地產（連動理財模式）") {
            if financeStore.realEstates.isEmpty {
                Text("尚無房地產，請先在理財模式新增")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Picker("選擇物件", selection: $fixedLinkRealEstateId) {
                    Text("請選擇").tag(nil as UUID?)
                    ForEach(financeStore.realEstates) { re in
                        Text("\(re.name)\(!re.address.isEmpty ? " (\(re.address))" : "")").tag(re.id as UUID?)
                    }
                }
            }
        }
    }

    private var fixedInsuranceLinkSection: some View {
        Section("儲蓄險（連動理財模式）") {
            if financeStore.insurances.isEmpty {
                Text("尚無儲蓄險，請先在理財模式新增")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Picker("選擇保單", selection: $fixedLinkInsuranceId) {
                    Text("請選擇").tag(nil as UUID?)
                    ForEach(financeStore.insurances) { ins in
                        Text("\(ins.name)\(!ins.company.isEmpty ? " (\(ins.company))" : "")").tag(ins.id as UUID?)
                    }
                }
            }
        }
    }

    // MARK: - 儲存

    private func saveExpense() {
        var trimmedTitle = title.trimmingCharacters(in: .whitespaces)

        // 變動支出：名稱留空時以分類名稱當預設（讓基本模式更省事）
        if expenseType == .variable && trimmedTitle.isEmpty {
            trimmedTitle = selectedVariableCategory.rawValue
            title = trimmedTitle
        }

        // 股票連動時自動計算金額
        var finalAmountText = amountText
        if expenseType == .variable && selectedAssetLink == .stock {
            if let shares = Double(stockSharesText), let price = Double(stockPriceText), shares > 0, price > 0 {
                finalAmountText = String(format: "%.0f", shares * price)
            }
        }

        guard !trimmedTitle.isEmpty,
              let rawAmount = Double(finalAmountText), rawAmount > 0 else {
            showValidationError = true
            return
        }

        // 自訂幣別換算為 NT$（儲蓄險不適用，使用其自身幣別欄位）
        let amount = isSavingsInsurance ? rawAmount : rawAmount * currencyMultiplier

        let expenseId = editingExpense?.id ?? generatedNewExpenseId
        var linkedInsId = editingExpense?.linkedInsuranceId
        var linkedStkId = editingExpense?.linkedStockId
        var linkedREId = editingExpense?.linkedRealEstateId
        var linkedVehId = editingExpense?.linkedVehicleId

        // 固定支出連動
        if isSavingsInsurance {
            linkedInsId = syncSavingsInsurance(amount: amount, existingId: linkedInsId, expenseId: expenseId)
        }
        if isMortgage {
            if mortgageLinkExisting, let reId = selectedMortgageRealEstateId {
                linkedREId = reId
                syncMortgageToExistingRealEstate(realEstateId: reId, expenseId: expenseId, amount: amount)
                if let re = financeStore.realEstates.first(where: { $0.id == reId }) {
                    let idx = re.mortgageItems.firstIndex(where: { $0.linkedExpenseId == expenseId }).map { $0 + 1 } ?? re.mortgageItems.count
                    let mTitle = re.mortgageItems.first(where: { $0.linkedExpenseId == expenseId })?.title ?? "房貸"
                    trimmedTitle = "【\(re.name)】貸款\(idx)-\(mTitle)"
                }
            } else {
                linkedREId = syncRealEstate(mortgageAmount: amount, existingId: linkedREId, expenseId: expenseId)
                if let re = financeStore.realEstates.first(where: { $0.id == linkedREId }) {
                    let idx = re.mortgageItems.firstIndex(where: { $0.linkedExpenseId == expenseId }).map { $0 + 1 } ?? re.mortgageItems.count
                    let mTitle = re.mortgageItems.first(where: { $0.linkedExpenseId == expenseId })?.title ?? "房貸"
                    trimmedTitle = "【\(re.name)】貸款\(idx)-\(mTitle)"
                }
            }
        }
        if isCarLoan, let vehicleId = selectedVehicleId {
            linkedVehId = vehicleId
            syncCarLoanToVehicle(vehicleId: vehicleId, expenseId: expenseId, amount: amount)
        }

        // 固定支出一般類別關聯資產
        if showFixedAssetLink {
            switch selectedFixedAssetLink {
            case .vehicle:
                if let vehicleId = fixedLinkVehicleId {
                    linkedVehId = vehicleId
                    syncFixedToVehicle(vehicleId: vehicleId, expenseId: expenseId, amount: amount)
                }
            case .realEstate:
                linkedREId = fixedLinkRealEstateId
            case .insurance:
                linkedInsId = fixedLinkInsuranceId
            case .none:
                break
            }
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
                if realEstateLinkExisting {
                    if let reId = selectedRealEstateLinkId {
                        linkedREId = reId
                        syncRealEstateVariableExpense(realEstateId: reId, expenseId: expenseId, amount: amount)
                    }
                } else {
                    let reId = syncNewRealEstateForVariable(existingId: linkedREId)
                    linkedREId = reId
                    syncRealEstateVariableExpense(realEstateId: reId, expenseId: expenseId, amount: amount)
                    selectedRealEstateLinkId = reId
                }
            case .none:
                break
            }
        }

        let savedCurrencyCode = isSavingsInsurance ? insCurrencyCode : selectedCurrencyCode
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
            realEstateExpenseCategory: (expenseType == .variable && selectedAssetLink == .realEstate) ? selectedRealEstateExpenseCategory : nil,
            taxSavingSubCategory: (expenseType == .variable && selectedVariableCategory == .taxSaving) ? selectedTaxSavingSubCategory : nil,
            socialSubCategory: (expenseType == .variable && selectedVariableCategory == .social) ? selectedSocialSubCategory : nil,
            socialRecipient: (expenseType == .variable && selectedVariableCategory == .social && !selectedSocialRecipients.isEmpty) ? socialRecipientString : nil,
            taxDeductibleOverride: (expenseType == .fixed && showTaxDeductibleToggle) ? taxDeductibleOverride : nil,
            note: note.trimmingCharacters(in: .whitespaces),
            currencyCode: savedCurrencyCode,
            diningMember: (expenseType == .variable && Self.memberCategories.contains(selectedVariableCategory) && !selectedDiningMembers.isEmpty) ? diningMembersString : nil,
            loanTotalAmount: showLoanCalcFields ? Double(loanTotalAmountText) : nil,
            loanYears: showLoanCalcFields ? Double(loanYearsText) : nil,
            loanRate: showLoanCalcFields ? computedLoanRate() : nil,
            linkedBankMilestoneId: selectedBankMilestoneId,
            linkedBankCurrency: selectedBankMilestoneId != nil ? selectedBankCurrency : nil,
            linkedCreditCardMilestoneId: selectedCreditCardMilestoneId,
            placeAddress: supportsPlacePicker ? placeAddress : nil,
            placeLatitude: supportsPlacePicker ? placeLatitude : nil,
            placeLongitude: supportsPlacePicker ? placeLongitude : nil,
            photoFileNames: photoFileNames
        )

        if isEditing { store.update(expense) } else { store.add(expense) }
        syncBankWithdrawal(for: expense, previous: editingExpense)
        dismiss()
    }

    private func syncBankWithdrawal(for expense: Expense, previous: Expense?) {
        // 移除舊的連結記錄（若有）
        if let prevId = previous?.linkedBankMilestoneId,
           var oldMs = lifeStore.milestones.first(where: { $0.id == prevId }) {
            oldMs.bankDeposits?.removeAll { $0.linkedExpenseId == expense.id }
            lifeStore.update(oldMs)
        }
        // 信用卡扣款不寫入 BankDeposit；改在顯示時依月份彙總
        guard expense.linkedCreditCardMilestoneId == nil else { return }
        // 週期性固定支出也不寫入單筆 BankDeposit；顯示時依 recurrence 從建立日展開到今天
        if expense.expenseType == .fixed, expense.recurrence != nil {
            // 同時清掉同一帳戶下舊版本可能殘留的單筆紀錄
            if let bankId = expense.linkedBankMilestoneId,
               var ms = lifeStore.milestones.first(where: { $0.id == bankId }) {
                ms.bankDeposits?.removeAll { $0.linkedExpenseId == expense.id }
                lifeStore.update(ms)
            }
            return
        }
        // 寫入新的連結記錄（直接扣款的銀行）
        guard let bankId = expense.linkedBankMilestoneId,
              var ms = lifeStore.milestones.first(where: { $0.id == bankId }) else { return }
        var list = ms.bankDeposits ?? []
        list.removeAll { $0.linkedExpenseId == expense.id }
        list.append(BankDeposit(
            id: UUID(), date: expense.date, amount: expense.amount,
            currencyCode: expense.linkedBankCurrency ?? "NT$",
            isWithdrawal: true, linkedExpenseId: expense.id
        ))
        ms.bankDeposits = list
        lifeStore.update(ms)
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

    /// 同步房地產支出（房屋價金→已支出章節，其餘→變動支出章節）
    private func syncRealEstateVariableExpense(realEstateId: UUID, expenseId: UUID, amount: Double) {
        guard var re = financeStore.realEstates.first(where: { $0.id == realEstateId }) else { return }

        if selectedRealEstateExpenseCategory == .housePayment {
            // 房屋價金 → paidItems（已支出房屋金額）
            let newPaid = RealEstatePaidItem(
                id: UUID(),
                title: title.trimmingCharacters(in: .whitespaces),
                amount: amount,
                date: date,
                linkedExpenseId: expenseId
            )
            // 編輯時先從 variableExpenses 移除（修正舊資料歸錯章節）
            re.variableExpenses.removeAll { $0.linkedExpenseId == expenseId }

            if let idx = re.paidItems.firstIndex(where: { $0.linkedExpenseId == expenseId }) {
                re.paidItems[idx] = RealEstatePaidItem(
                    id: re.paidItems[idx].id,
                    title: title.trimmingCharacters(in: .whitespaces),
                    amount: amount,
                    date: date,
                    linkedExpenseId: expenseId
                )
            } else {
                re.paidItems.append(newPaid)
            }
        } else if selectedRealEstateExpenseCategory == .utility {
            // 水電瓦斯 → utilityPayments（與房地產卡片水電瓦斯章節雙向同步）
            re.paidItems.removeAll { $0.linkedExpenseId == expenseId }
            re.variableExpenses.removeAll { $0.linkedExpenseId == expenseId }

            let inferredType: UtilityType = {
                let lower = title.lowercased()
                if title.contains("水") { return .water }
                if title.contains("電") || lower.contains("electric") { return .electricity }
                if title.contains("瓦斯") || lower.contains("gas") { return .gas }
                return .electricity
            }()

            if let idx = re.utilityPayments.firstIndex(where: { $0.linkedExpenseId == expenseId }) {
                let old = re.utilityPayments[idx]
                re.utilityPayments[idx] = UtilityPayment(
                    id: old.id, type: old.type, date: date, amount: amount,
                    photoFileName: old.photoFileName,
                    note: note.trimmingCharacters(in: .whitespaces),
                    linkedExpenseId: expenseId
                )
            } else {
                re.utilityPayments.append(UtilityPayment(
                    type: inferredType, date: date, amount: amount,
                    note: note.trimmingCharacters(in: .whitespaces),
                    linkedExpenseId: expenseId
                ))
            }
        } else {
            // 其餘類別 → variableExpenses（變動支出）
            let trimmedNote = note.trimmingCharacters(in: .whitespaces)
            let newEntry = RealEstateVariableExpense(
                id: UUID(),
                category: selectedRealEstateExpenseCategory,
                name: trimmedNote,
                amount: amount,
                date: date,
                linkedExpenseId: expenseId
            )
            // 編輯時先從 paidItems / utilityPayments 移除（修正類別切換時的歸屬）
            re.paidItems.removeAll { $0.linkedExpenseId == expenseId }
            re.utilityPayments.removeAll { $0.linkedExpenseId == expenseId }

            if let idx = re.variableExpenses.firstIndex(where: { $0.linkedExpenseId == expenseId }) {
                re.variableExpenses[idx] = RealEstateVariableExpense(
                    id: re.variableExpenses[idx].id,
                    category: selectedRealEstateExpenseCategory,
                    name: trimmedNote,
                    amount: amount,
                    date: date,
                    linkedExpenseId: expenseId
                )
            } else {
                re.variableExpenses.append(newEntry)
            }
        }

        financeStore.update(re)
    }

    /// 變動支出連動「新增物件」模式：建立或更新房地產主檔（不含貸款），回傳物件 ID
    private func syncNewRealEstateForVariable(existingId: UUID?) -> UUID {
        let existingRE = existingId.flatMap { id in financeStore.realEstates.first(where: { $0.id == id }) }
        let reId = existingRE?.id ?? UUID()
        let trimmedName = reName.trimmingCharacters(in: .whitespaces)
        let resolvedName = trimmedName.isEmpty ? title.trimmingCharacters(in: .whitespaces) : trimmedName
        let purchasePrice = (Double(rePurchasePriceText) ?? 0) * 10000
        let currentValue = (Double(reCurrentValueText) ?? 0) * 10000

        if var re = existingRE {
            re.name = resolvedName
            re.city = reCity
            re.address = reAddress.trimmingCharacters(in: .whitespaces)
            re.purchaseDate = rePurchaseDate
            re.soldDate = reIsSold ? reSoldDate : nil
            re.purchasePrice = purchasePrice
            re.currentValue = currentValue
            re.monthlyRental = Double(reMonthlyRentalText) ?? 0
            financeStore.update(re)
        } else {
            let realEstate = RealEstate(
                id: reId,
                name: resolvedName,
                city: reCity,
                address: reAddress.trimmingCharacters(in: .whitespaces),
                purchaseDate: rePurchaseDate,
                soldDate: reIsSold ? reSoldDate : nil,
                purchasePrice: purchasePrice,
                currentValue: currentValue,
                monthlyRental: Double(reMonthlyRentalText) ?? 0,
                note: ""
            )
            financeStore.add(realEstate)
        }
        return reId
    }

    /// 同步建立或更新理財模式的儲蓄險
    private func syncSavingsInsurance(amount: Double, existingId: UUID?, expenseId: UUID) -> UUID {
        let insuranceId = existingId ?? UUID()
        let insurance = SavingsInsurance(
            id: insuranceId,
            name: title.trimmingCharacters(in: .whitespaces),
            company: insCompany.trimmingCharacters(in: .whitespaces),
            currencyCode: insCurrencyCode,
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
        let existingRE = existingId.flatMap { id in financeStore.realEstates.first(where: { $0.id == id }) }
        let reId = existingRE?.id ?? UUID()
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        let mortgageTitle = trimmedNote.isEmpty ? "房貸" : trimmedNote
        let years = Double(loanYearsText) ?? 0
        let computedPeriods = years > 0 ? Int(years * 12) : 240
        let mortgageItem = RealEstateMortgageItem(
            title: mortgageTitle,
            amount: mortgageAmount,
            totalPeriods: computedPeriods,
            startDate: date,
            linkedExpenseId: expenseId
        )
        let trimmedName = reName.trimmingCharacters(in: .whitespaces)
        let resolvedName = trimmedName.isEmpty ? title.trimmingCharacters(in: .whitespaces) : trimmedName
        let purchasePrice = (Double(rePurchasePriceText) ?? 0) * 10000
        let currentValue = (Double(reCurrentValueText) ?? 0) * 10000

        if var re = existingRE {
            re.name = resolvedName
            re.city = reCity
            re.address = reAddress.trimmingCharacters(in: .whitespaces)
            re.purchaseDate = rePurchaseDate
            re.soldDate = reIsSold ? reSoldDate : nil
            re.purchasePrice = purchasePrice
            re.currentValue = currentValue
            re.monthlyRental = Double(reMonthlyRentalText) ?? 0
            if let idx = re.mortgageItems.firstIndex(where: { $0.linkedExpenseId == expenseId }) {
                let prev = re.mortgageItems[idx]
                re.mortgageItems[idx] = RealEstateMortgageItem(
                    id: prev.id,
                    title: mortgageTitle,
                    amount: mortgageAmount,
                    totalPeriods: years > 0 ? computedPeriods : prev.totalPeriods,
                    startDate: years > 0 ? date : prev.startDate,
                    linkedExpenseId: expenseId
                )
            } else {
                re.mortgageItems.append(mortgageItem)
            }
            financeStore.update(re)
        } else {
            let realEstate = RealEstate(
                id: reId,
                name: resolvedName,
                city: reCity,
                address: reAddress.trimmingCharacters(in: .whitespaces),
                purchaseDate: rePurchaseDate,
                soldDate: reIsSold ? reSoldDate : nil,
                purchasePrice: purchasePrice,
                currentValue: currentValue,
                monthlyRental: Double(reMonthlyRentalText) ?? 0,
                mortgageItems: [mortgageItem],
                note: ""
            )
            financeStore.add(realEstate)
        }
        return reId
    }

    /// 同步房貸到既有房地產物件
    private func syncMortgageToExistingRealEstate(realEstateId: UUID, expenseId: UUID, amount: Double) {
        guard var re = financeStore.realEstates.first(where: { $0.id == realEstateId }) else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        let mortgageTitle = trimmedNote.isEmpty ? "房貸" : trimmedNote
        let years = Double(loanYearsText) ?? 0
        let computedPeriods = years > 0 ? Int(years * 12) : 240

        if let idx = re.mortgageItems.firstIndex(where: { $0.linkedExpenseId == expenseId }) {
            let prev = re.mortgageItems[idx]
            re.mortgageItems[idx] = RealEstateMortgageItem(
                id: prev.id,
                title: mortgageTitle,
                amount: amount,
                totalPeriods: years > 0 ? computedPeriods : prev.totalPeriods,
                startDate: years > 0 ? date : prev.startDate,
                linkedExpenseId: expenseId
            )
        } else {
            let mortgageItem = RealEstateMortgageItem(
                title: mortgageTitle,
                amount: amount,
                totalPeriods: computedPeriods,
                startDate: date,
                linkedExpenseId: expenseId
            )
            re.mortgageItems.append(mortgageItem)
        }
        financeStore.update(re)
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

    /// 同步固定支出到汽車定期支出（一般類別關聯用，category 依 fixedCategory 決定）
    private func syncFixedToVehicle(vehicleId: UUID, expenseId: UUID, amount: Double) {
        guard var vehicle = financeStore.vehicles.first(where: { $0.id == vehicleId }) else { return }

        let category: VehicleFixedCategory
        switch selectedFixedCategory {
        case .subscription: category = .subscription
        default: category = .tax  // 房租/水電/管理費等歸為稅費雜支
        }

        let period: VehicleExpensePeriod = selectedRecurrence == .yearly ? .yearly : .monthly

        if let idx = vehicle.fixedExpenses.firstIndex(where: { $0.linkedExpenseId == expenseId }) {
            vehicle.fixedExpenses[idx] = VehicleFixedExpense(
                id: vehicle.fixedExpenses[idx].id,
                category: category, amount: amount, period: period, linkedExpenseId: expenseId
            )
        } else {
            vehicle.fixedExpenses.append(VehicleFixedExpense(
                id: UUID(), category: category, amount: amount, period: period, linkedExpenseId: expenseId
            ))
        }
        financeStore.update(vehicle)
    }

    // MARK: - 載入編輯資料

    private func loadEditing() {
        guard let expense = editingExpense else { return }

        // 編輯既有的變動支出且包含進階欄位時，自動展開進階模式讓使用者看到完整資訊
        if expense.expenseType == .variable {
            let hasAdvancedFields = expense.linkedRealEstateId != nil
                || expense.linkedVehicleId != nil
                || expense.linkedStockId != nil
                || expense.linkedInsuranceId != nil
                || expense.linkedBankMilestoneId != nil
                || expense.linkedCreditCardMilestoneId != nil
            if hasAdvancedFields { advancedMode = true }
        }

        title = expense.title
        // 編輯飲食支出時，還原店家位置資訊但不要觸發完成器
        if let addr = expense.placeAddress { placeAddress = addr }
        if let lat = expense.placeLatitude { placeLatitude = lat }
        if let lon = expense.placeLongitude { placeLongitude = lon }
        suppressNextCompleterUpdate = true
        photoFileNames = expense.photoFileNames
        selectedCurrencyCode = expense.currencyCode
        // 還原為原始幣別金額顯示
        if expense.currencyCode != "NT$",
           let rate = store.currencyRates.first(where: { $0.code == expense.currencyCode }),
           rate.rate > 0 {
            amountText = String(format: "%.0f", expense.amount / rate.rate)
        } else {
            amountText = String(format: "%.0f", expense.amount)
        }
        date = expense.date
        if let vc = expense.variableCategory { selectedVariableCategory = vc }
        if let ts = expense.taxSavingSubCategory { selectedTaxSavingSubCategory = ts }
        if let ss = expense.socialSubCategory { selectedSocialSubCategory = ss }
        if let raw = expense.socialRecipient, !raw.isEmpty {
            let names = raw.components(separatedBy: CharacterSet(charactersIn: ",、，"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            selectedSocialRecipients = Set(names)
        }
        taxDeductibleOverride = expense.taxDeductibleOverride
        if let fc = expense.fixedCategory { selectedFixedCategory = fc }
        if let rec = expense.recurrence { selectedRecurrence = rec }
        if let sub = expense.insuranceSubCategory { selectedInsuranceSubCategory = sub }
        if let sub = expense.loanSubCategory { selectedLoanSubCategory = sub }
        // 多選人員：以「、」分隔；向下相容單名格式（split 仍會回傳一個元素）
        if let raw = expense.diningMember, !raw.isEmpty {
            let parts = raw.split(separator: "、").map { $0.trimmingCharacters(in: .whitespaces) }
            selectedDiningMembers = Set(parts.filter { !$0.isEmpty })
        } else {
            selectedDiningMembers = []
        }
        if let lt = expense.loanTotalAmount, lt > 0 { loanTotalAmountText = String(format: "%.0f", lt) }
        if let ly = expense.loanYears, ly > 0 { loanYearsText = String(format: "%g", ly) }
        selectedBankMilestoneId = expense.linkedBankMilestoneId
        selectedBankCurrency = expense.linkedBankCurrency ?? "NT$"
        selectedCreditCardMilestoneId = expense.linkedCreditCardMilestoneId
        note = expense.note

        // 載入連結的儲蓄險
        if let linkedId = expense.linkedInsuranceId,
           let linked = financeStore.insurances.first(where: { $0.id == linkedId }) {
            insCompany = linked.company
            insCurrencyCode = linked.currencyCode
            insRateText = linked.annualRate > 0 ? String(format: "%.2f", linked.annualRate) : ""
            insStartDate = linked.startDate
            insMaturityDate = linked.maturityDate
        }

        // 載入連結的房地產
        if let linkedId = expense.linkedRealEstateId,
           let linked = financeStore.realEstates.first(where: { $0.id == linkedId }) {
            if expense.loanSubCategory == .mortgage {
                mortgageLinkExisting = true
                selectedMortgageRealEstateId = linkedId
                // 備註自動讀取對應貸款項目的名稱（若目前備註為空或與原先相同）
                if let item = linked.mortgageItems.first(where: { $0.linkedExpenseId == expense.id }) {
                    let mortgageTitle = item.title.trimmingCharacters(in: .whitespaces)
                    if !mortgageTitle.isEmpty {
                        note = mortgageTitle
                    }
                    // 還原貸款年限（從 totalPeriods 換算）
                    if loanYearsText.isEmpty && item.totalPeriods > 0 {
                        let years = Double(item.totalPeriods) / 12.0
                        loanYearsText = String(format: "%g", years)
                    }
                    // 開始日期從 mortgageItem.startDate 同步
                    date = item.startDate
                }
            }
            reName = linked.name
            reCity = linked.city
            reAddress = linked.address
            rePurchaseDate = linked.purchaseDate
            reIsSold = linked.soldDate != nil
            reSoldDate = linked.soldDate ?? Date()
            let purchaseWan = linked.purchasePrice / 10000
            let currentWan = linked.currentValue / 10000
            rePurchasePriceText = purchaseWan > 0 ? formatWan(purchaseWan) : ""
            reCurrentValueText = currentWan > 0 ? formatWan(currentWan) : ""
            reMonthlyRentalText = linked.monthlyRental > 0 ? String(format: "%.0f", linked.monthlyRental) : ""
        } else if expense.linkedRealEstateId != nil && expense.loanSubCategory == .mortgage {
            // 連結的房地產已被刪除，切回「新增物件」模式讓使用者可重新建立
            mortgageLinkExisting = false
            selectedMortgageRealEstateId = nil
        }

        // 載入車貸連結的車輛
        if expense.expenseType == .fixed && expense.fixedCategory == .loan
           && expense.loanSubCategory == .car && expense.linkedVehicleId != nil {
            selectedVehicleId = expense.linkedVehicleId
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
            } else if let reId = expense.linkedRealEstateId {
                selectedAssetLink = .realEstate
                if financeStore.realEstates.contains(where: { $0.id == reId }) {
                    realEstateLinkExisting = true
                    selectedRealEstateLinkId = reId
                } else {
                    realEstateLinkExisting = false
                    selectedRealEstateLinkId = nil
                }
                if let reCat = expense.realEstateExpenseCategory {
                    selectedRealEstateExpenseCategory = reCat
                }
            }
        }

        // 載入固定支出（非保險/貸款）的資產連結
        if expense.expenseType == .fixed && expense.fixedCategory != .insurance && expense.fixedCategory != .loan {
            if expense.linkedVehicleId != nil {
                selectedFixedAssetLink = .vehicle
                fixedLinkVehicleId = expense.linkedVehicleId
            } else if expense.linkedRealEstateId != nil {
                selectedFixedAssetLink = .realEstate
                fixedLinkRealEstateId = expense.linkedRealEstateId
            } else if expense.linkedInsuranceId != nil {
                selectedFixedAssetLink = .insurance
                fixedLinkInsuranceId = expense.linkedInsuranceId
            }
        }

        // 編輯時若已連動理財項目，依目前清單重新計算「項目 N：型號-類別」
        applyAutoTitleIfLinked()
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
        f.maximumFractionDigits = isSavingsInsurance && insIsUSD ? 2 : 0
        return f.string(from: NSNumber(value: value)) ?? "NT$0"
    }

    private func rateDisplay(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%g", value)
    }

    private func formatWan(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%g", value)
    }

    private var currencyMultiplier: Double {
        if selectedCurrencyCode == "NT$" { return 1 }
        if let rate = store.currencyRates.first(where: { $0.code == selectedCurrencyCode }), rate.rate > 0 {
            return rate.rate
        }
        return 1
    }

    private func applyPreset() {
        guard editingExpense == nil, let preset else { return }
        if let fc = preset.fixedCategory { selectedFixedCategory = fc }
        if let lsc = preset.loanSubCategory { selectedLoanSubCategory = lsc }
        if let vc = preset.variableCategory { selectedVariableCategory = vc }
        if let vec = preset.vehicleExpenseCategory { selectedVehicleExpenseCategory = vec }
        if let rec = preset.recurrence { selectedRecurrence = rec }
        if let reCat = preset.realEstateExpenseCategory { selectedRealEstateExpenseCategory = reCat }
        if let vid = preset.linkedVehicleId {
            selectedVehicleId = vid
            fixedLinkVehicleId = vid
        }
        if let reId = preset.linkedRealEstateId {
            selectedRealEstateLinkId = reId
            selectedMortgageRealEstateId = reId
            fixedLinkRealEstateId = reId
        }
        if let al = preset.assetLink { selectedAssetLink = al }
        if let fal = preset.fixedAssetLink { selectedFixedAssetLink = fal }
        if let rle = preset.realEstateLinkExisting { realEstateLinkExisting = rle }
        if let mle = preset.mortgageLinkExisting { mortgageLinkExisting = mle }
    }
}

// MARK: - 預設值（用於從理財模式建立支出時帶入分類/連結）

struct AddExpensePreset {
    var fixedCategory: FixedCategory?
    var loanSubCategory: LoanSubCategory?
    var variableCategory: VariableCategory?
    var vehicleExpenseCategory: VehicleVariableCategory?
    var realEstateExpenseCategory: RealEstateExpenseCategory?
    var recurrence: Recurrence?
    var linkedVehicleId: UUID?
    var linkedRealEstateId: UUID?
    var assetLink: AddExpenseView.AssetLinkType?
    var fixedAssetLink: AddExpenseView.FixedAssetLinkType?
    var realEstateLinkExisting: Bool?
    var mortgageLinkExisting: Bool?
}

// MARK: - 地點候選資料型別

/// 變動支出名稱自動完成的候選項目（合併歷史紀錄 + Apple Maps）
fileprivate struct PlaceSuggestion: Identifiable {
    enum Source { case past, apple }
    let id: String
    let source: Source
    let title: String
    let subtitle: String
    let completion: MKLocalSearchCompletion?
    let latitude: Double?
    let longitude: Double?
    let address: String?

    var iconName: String {
        switch source {
        case .past: return "clock.arrow.circlepath"
        case .apple: return "mappin"
        }
    }
    var iconColor: Color {
        switch source {
        case .past: return .green
        case .apple: return .orange
        }
    }
}

#Preview {
    AddExpenseView(expenseType: .fixed)
        .environmentObject(ExpenseStore())
        .environmentObject(FinanceStore())
}
