import SwiftUI

// MARK: - 美化紀錄（AddVehicleView）
// [2026-06] 本次美化方向：
//   1. Section header 統一升級：4pt Capsule 漸層色條 + 彩色圖示 + .subheadline.semibold + 計數膠囊，
//      對齊全 App section header 設計語言（OverviewView / IncomeView / FixedExpenseView）。
//   2. fixedExpenseSection 列行：加入 36pt 藍色漸層圓形圖示 + 類別標籤從 RoundedRectangle 升級
//      為 Capsule 週期徽章，對齊 FixedExpenseRow / ExpenseRow 視覺規格。
//   3. variableExpenseSection 列行：加入 36pt 橘色漸層圓形圖示 + 類別標籤改 Capsule + 日期膠囊，
//      對齊 ExpenseRow 視覺規格。
//   4. calcSection 升級：每列加入彩色 32pt 圖示圓，數值以彩色 Capsule 徽章呈現，
//      對齊 AddExpenseView.calcPreviewRows 設計語言。
//   5. noteSection：加入 Capsule 色條標題，提升視覺一致性。
//   6. 輔助函式 vehicleSectionHeader / calcRow 集中維護，方便日後均值對齊。
// [2026-06 v2] 本次美化方向：
//   7. vehiclePreviewCard（英雄預覽卡）：Form 頂部新增翠綠漸層英雄預覽卡，
//      即時顯示車名 + 購入價大字 + 目前估值 / 折舊金額 / 月固定支出 KPI 橫列，
//      動力類型白色膠囊 + 折舊率膠囊；三顆散景裝飾圓 + 頂部玻璃光澤，
//      cardAppeared spring 進場動畫，對齊 AddStockView.amountPreviewCard /
//      AddSavingsInsuranceView.calcPreviewCard 規格。
//   8. errorBanner：從純紅字 Text 升級為帶圖示的橘色警告橫幅卡
//      （exclamationmark.triangle.fill + 說明文字），對齊 AddExpenseView errorBanner 規格。
//   9. .tint(.teal)：青藍主題色統一套用，Toggle / DatePicker 等系統元件配色與車輛主題一致，
//      對齊 AddStockView(.orange) / AddRealEstateView(.purple) 主題色規格。
//  10. vehicleSectionHeader 計數膠囊：補入 .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.6))
//      細邊框，對齊全 App 計數膠囊細邊框規格（OverviewView / StockView sectionHeader）。
//  11. variableExpenseSection 日期膠囊：背景從 .systemGray5 改為 .tertiarySystemFill，
//      深色模式相容，對齊 OverviewView.recentRow / CareerView 日期膠囊規格；
//      shortDateFormatter 改為靜態共用實例，避免每次 render 重新分配。
//  12. calcSection 進場動畫：加入 calcSectionAppeared spring 旗標 + opacity+Y offset 進場，
//      對齊 AddSavingsInsuranceView.cardAppeared / AddStockView 進場規格。
// [2026-08 v3] 本次美化方向（定期／變動支出列表補齊進場動畫）：
//  13. fixedExpenseSection／variableExpenseSection 的 ForEach 列先前完全沒有進場動畫，
//      是全檔案唯一還沒對齊的角落——同一支 Form 裡 vehiclePreviewCard（cardAppeared）與
//      calcSection（calcSectionAppeared）都已有 spring 進場，這兩個「最常滑動瀏覽」的
//      清單區塊卻是裸出現。新增 fixedExpensesAppeared／variableExpensesAppeared 旗標，
//      比照 SpouseResumeView.expenseRow / ResumeGiftSection.giftRow 規格：ForEach 改用
//      enumerated 索引，每列 opacity(0→1) + offset(12→0)，spring(0.44, 0.82) 依索引
//      × 0.04s 交錯延遲（上限 14 列，避免長清單延遲過久）；觸發點掛在各自 Section 的
//      onAppear（而非 ForEach 內每列），避免 Form 捲動時 lazy-load 重複觸發。
//      （下次美化本檔案時：主要欄位、英雄卡、兩大支出清單、試算區皆已對齊進場動畫規格，
//      可轉往其他仍留有待辦的畫面）
// [2026-08 v4] 本次美化方向（儲存按鈕載入狀態，延續 v25.81/25.82/25.83 待辦清單）：
//  14. 工具列「儲存／新增」按鈕：save() 自帶 isSaving 忙碌守衛（disabled(isSaving)）避免
//      快速連點造成重複車輛紀錄，但按鈕本身在存檔期間毫無視覺變化。補上
//      ProgressView().scaleEffect(0.7).tint(.green)，isSaving 為 true 時顯示於按鈕左側，
//      對齊 AddIncomeView／AddExpenseView／AddSavingsInsuranceView 儲存按鈕載入狀態規格。
//      純視覺層補強，save() 內部守衛判斷與車輛寫入邏輯完全未變動。同型 isSaving 守衛仍
//      存在於 AddStockView／AddRealEstateView，可作為下次美化比照補齊的清單。
//
// [v25.538] 先修資料（畫面不變）：
//   - 新增流程按取消改走共用的 VehicleDeletion：連銀行扣款紀錄、只靠 linkedVehicleId 連過來的支出一起清。
//   - 左滑刪單筆支出先確認；確認後連記帳那筆、收據照片、銀行扣款紀錄一起刪。
//   - 編輯頁不再弄壞資料：估值 0 的車再存不會變成購入價；金額帶回不丟位數；編輯時自動存進去的
//     表頭按取消會還原；有改過不能往下滑關掉、按取消先問；只載入一次；購入日、售出日不能選未來；
//     錯誤橫幅放最上面。
//   - 家充地點提示不再建議填「家」；估值欄下多一顆「照每年 15% 估（帶入）」，取代列表的折舊開關。

struct AddVehicleView: View {
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let editing: Vehicle?
    /// [v25.538] 用 @State 存：sheet 的內容會因為上一頁重畫而重新 init，
    /// 用 let 的話新增流程每次 init 都會換一個新的 UUID，自動存檔和「取消」回滾就找不到那台車
    @State private var stableVehicleId: UUID

    init(editing: Vehicle? = nil) {
        self.editing = editing
        _stableVehicleId = State(initialValue: editing?.id ?? UUID())
    }

    // MARK: - 基本欄位

    @State private var name = ""
    @State private var brand = ""
    @State private var ownerName = ""
    @State private var powerType: VehiclePowerType = .gasoline
    /// [v25.397] 原廠標稱電池容量（kWh）與家充地點關鍵字。只有有電池的車型才問。
    @State private var batteryCapacityText = ""
    @State private var homeChargePlace = ""
    @State private var purchaseDate = Date()
    @State private var isSold = false
    @State private var soldDate = Date()
    @State private var purchasePriceText = ""
    @State private var currentValueText = ""
    @State private var note = ""
    @State private var showError = false
    @State private var hasAutoSaved: Bool = false
    // 儲存為同步寫回 store 後立即 dismiss()，sheet 收合動畫期間按鈕仍可觸發，
    // 快速連點會建立兩筆重複車輛紀錄；補上忙碌守衛比照 AddRealEstateView 既有修法。
    @State private var isSaving = false
    // v2 進場動畫旗標
    @State private var cardAppeared = false
    @State private var calcSectionAppeared = false
    // v3 進場動畫旗標：定期／變動支出列表交錯進場
    @State private var fixedExpensesAppeared = false
    @State private var variableExpensesAppeared = false
    // [v25.538] loadEditing 只跑一次；initialFields 是載入完的欄位，拿來判斷有沒有改過
    @State private var didLoad = false
    @State private var initialFields: VehicleFormFields?
    // [v25.538] 編輯既有車子時「新增項目」已經把表頭自動存進去了，取消要還原
    @State private var headerAutoSaved = false
    // [v25.538] 最後一次自動存進去的欄位：之後把欄位改回原樣，車子裡存的還是改過的，往下滑關掉也要擋
    @State private var autoSavedFields: VehicleFormFields?
    // [v25.538] 打開時的車子（取消時還原表頭用），第一次載入時存起來。不能直接用 editing：
    // 卡片頁傳進來的是每次重畫都從 store 重抓的車子，自動存檔後卡片頁一重畫，editing 就變成存過的樣子
    @State private var openedSnapshot: Vehicle?
    // [v25.538] 有改過時按取消先問；說明文字在打開確認框的那一刻算好
    @State private var showDiscardConfirm = false
    @State private var discardMessage = ""
    // [v25.538] 左滑刪支出：先記下來跳確認，確認後才刪
    @State private var pendingExpenseDeletion: ExpenseSwipeDeletion?
    // [v25.538] 驗證沒過時加一，表單捲到最上面的錯誤橫幅
    @State private var errorScrollTick = 0

    // MARK: - 編輯/新增項目

    @State private var editingFixedExpense: Expense?
    @State private var editingVariableExpense: Expense?
    @State private var addingFixedCategory: VehicleFixedCategory?
    @State private var addingVariableCategory: VehicleVariableCategory?
    @State private var showFixedCategoryPicker = false
    @State private var showVariableCategoryPicker = false

    // MARK: - 從 store 取得目前車輛 / 項目列表

    private var currentVehicle: Vehicle? {
        financeStore.vehicles.first(where: { $0.id == stableVehicleId })
    }

    private var fixedExpenses: [VehicleFixedExpense] {
        currentVehicle?.fixedExpenses ?? []
    }

    private var variableExpenses: [VehicleVariableExpense] {
        currentVehicle?.variableExpenses ?? []
    }

    /// [v25.538] 表單上「車子本身」的欄位，用來判斷有沒有改過（要不要問放棄、能不能往下滑關掉）。
    /// 沒勾「已售出」時售出日只是預設值，不算。
    struct VehicleFormFields: Equatable {
        var name: String
        var brand: String
        var ownerName: String
        var powerType: VehiclePowerType
        var batteryCapacityText: String
        var homeChargePlace: String
        var purchaseDate: Date
        var soldDate: Date?
        var purchasePriceText: String
        var currentValueText: String
        var note: String
    }

    /// [v25.538] 左滑要刪的列（車子上的項目 id）和它們連到的記帳支出 id
    struct ExpenseSwipeDeletion {
        let itemIds: Set<UUID>
        let expenseIds: Set<UUID>
        /// 記帳裡真的還找得到的筆數（滑的當下算好）：記帳那筆早被刪掉的孤兒列，不能說「會一起刪除」
        let foundExpenseCount: Int
    }

    /// [v25.538] 左滑的當下就把要刪的東西和確認框要講的筆數算好
    private func makeSwipeDeletion(linkedExpenseIds: [UUID?], itemIds: [UUID]) -> ExpenseSwipeDeletion {
        let expenseIds = Set(linkedExpenseIds.compactMap { $0 })
        let found = expenseStore.expenses.filter { expenseIds.contains($0.id) }.count
        return ExpenseSwipeDeletion(itemIds: Set(itemIds), expenseIds: expenseIds, foundExpenseCount: found)
    }

    private var currentFields: VehicleFormFields {
        VehicleFormFields(
            name: name, brand: brand, ownerName: ownerName, powerType: powerType,
            batteryCapacityText: batteryCapacityText, homeChargePlace: homeChargePlace,
            purchaseDate: purchaseDate, soldDate: isSold ? soldDate : nil,
            purchasePriceText: purchasePriceText, currentValueText: currentValueText, note: note
        )
    }

    /// [v25.538] 有沒有東西會被放棄：新增流程已經自動存過（車子和這次記的支出都在 store 裡）、
    /// 編輯時自動存進車子的欄位跟打開時不一樣（欄位後來改回原樣也算，車子裡存的還是改過的），
    /// 或欄位跟打開時不一樣
    private var hasChanges: Bool {
        if editing == nil && hasAutoSaved { return true }
        guard let initial = initialFields else { return false }
        if let saved = autoSavedFields, saved != initial { return true }
        return currentFields != initial
    }

    /// [v25.538] 錯誤橫幅那一列的 id，驗證沒過時捲過去
    private static let errorBannerId = "vehicleErrorBanner"

    // [v25.538] body 拆成「表單本體」和三段「彈出視窗」（同 AddRealEstateView v25.530）：這版多了刪支出確認、
    // 放棄修改確認和捲到錯誤橫幅，十幾個修飾器擠在同一個運算式裡容易型別檢查逾時
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                withConfirmations(withCategoryPickers(withExpenseSheets(editorForm)))
                    .onAppear { loadEditingOnce() }
                    .onChange(of: errorScrollTick) { _, _ in
                        // 橫幅這一列剛加進表單，等它畫好再捲過去
                        DispatchQueue.main.async {
                            withAnimation { proxy.scrollTo(Self.errorBannerId, anchor: .top) }
                        }
                    }
            }
        }
        // [v25.538] 有改過就不能往下滑關掉：滑掉不會經過「取消」，新增流程會留下自動存檔的半台車，
        // 編輯時自動存進去的欄位也不會還原
        .interactiveDismissDisabled(hasChanges)
    }

    private var editorForm: some View {
        Form {
            // [v25.538] 錯誤橫幅移到最上面：以前在最底下，支出列一多，按「新增」看起來像沒反應
            if showError {
                Section {
                    errorBanner
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .id(Self.errorBannerId)
                }
            }
            // v2：翠綠英雄預覽卡（常態顯示，即時反映填入數值）
            Section {
                vehiclePreviewCard
                    .opacity(cardAppeared ? 1 : 0)
                    .offset(y: cardAppeared ? 0 : 18)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .onAppear {
                        withAnimation(.spring(response: 0.50, dampingFraction: 0.78)) {
                            cardAppeared = true
                        }
                    }
            }
            vehicleInfoSection
            valueSection
            fixedExpenseSection
            variableExpenseSection
            calcSection
            noteSection
        }
        .tint(.teal) // v2: 青藍主題色
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("取消") { cancelTapped() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 6) {
                    // [美化] 存檔中顯示同色 ProgressView，對齊 AddIncomeView／AddExpenseView／
                    // AddSavingsInsuranceView 儲存按鈕載入狀態規格
                    if isSaving {
                        ProgressView().scaleEffect(0.7).tint(.green)
                    }
                    Button(editing != nil || hasAutoSaved ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green).disabled(isSaving)
                }
            }
        }
    }

    private func withExpenseSheets<Content: View>(_ content: Content) -> some View {
        content
            .sheet(item: $editingFixedExpense) { exp in
                AddExpenseView(expenseType: .fixed, editingExpense: exp)
                    .appStores()
            }
            .sheet(item: $editingVariableExpense) { exp in
                AddExpenseView(expenseType: .variable, editingExpense: exp)
                    .appStores()
            }
            .sheet(item: $addingFixedCategory) { cat in
                AddExpenseView(
                    expenseType: .fixed,
                    preset: makeFixedPreset(for: cat)
                )
                .appStores()
            }
            .sheet(item: $addingVariableCategory) { cat in
                AddExpenseView(
                    expenseType: .variable,
                    preset: makeVariablePreset(for: cat)
                )
                .appStores()
            }
    }

    private func withCategoryPickers<Content: View>(_ content: Content) -> some View {
        content
            .confirmationDialog("選擇定期支出類別", isPresented: $showFixedCategoryPicker, titleVisibility: .visible) {
                ForEach(VehicleFixedCategory.allCases) { cat in
                    Button(cat.rawValue) {
                        guard ensureVehicleSavedInStore() else { return }
                        addingFixedCategory = cat
                    }
                }
                Button("取消", role: .cancel) {}
            }
            .confirmationDialog("選擇變動支出類別", isPresented: $showVariableCategoryPicker, titleVisibility: .visible) {
                ForEach(VehicleVariableCategory.categories(for: powerType)) { cat in
                    Button(cat.rawValue) {
                        guard ensureVehicleSavedInStore() else { return }
                        addingVariableCategory = cat
                    }
                }
                Button("取消", role: .cancel) {}
            }
    }

    // [v25.538] 左滑刪支出的確認、按取消時「要放棄這次的修改嗎？」
    private func withConfirmations<Content: View>(_ content: Content) -> some View {
        content
            .alert("刪除這筆支出？", isPresented: expenseDeletionPresented, presenting: pendingExpenseDeletion) { request in
                Button("刪除", role: .destructive) { confirmExpenseDeletion(request) }
                Button("取消", role: .cancel) {}
            } message: { request in
                Text(expenseDeletionMessage(request))
            }
            .confirmationDialog("要放棄這次的修改嗎？", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
                Button("放棄修改", role: .destructive) { cancelAndRollback() }
                Button("繼續編輯", role: .cancel) {}
            } message: {
                Text(discardMessage)
            }
    }

    private var expenseDeletionPresented: Binding<Bool> {
        Binding(
            get: { pendingExpenseDeletion != nil },
            set: { if !$0 { pendingExpenseDeletion = nil } }
        )
    }

    private var navTitle: String {
        let isMotorcycle = powerType == .motorcycle || powerType == .electricMotorcycle
        let typeLabel = isMotorcycle ? "🛵機車" : "🚗汽車"
        let action = (editing != nil || hasAutoSaved) ? "編輯" : "新增"
        return "\(action) \(typeLabel)"
    }

    // MARK: - 車輛資訊

    private var ownerOptions: [String] {
        var names: [String] = []
        let profileName = lifeStore.profile.chineseName
        if !profileName.isEmpty { names.append(profileName) }
        for m in lifeStore.familyMembers {
            let n = m.chineseName.isEmpty ? m.englishName : m.chineseName
            if !n.isEmpty { names.append(n) }
        }
        return names
    }

    private var vehicleInfoSection: some View {
        Section {
            TextField("車名（如 Model Y）", text: $name)
            TextField("品牌（如 Tesla）", text: $brand)

            if !ownerOptions.isEmpty {
                Picker("車輛所有人", selection: $ownerName) {
                    Text("未指定").tag("")
                    ForEach(ownerOptions, id: \.self) { n in
                        Text(n).tag(n)
                    }
                }
            }

            Picker("動力類型", selection: $powerType) {
                ForEach(VehiclePowerType.allCases) { type in
                    Label(type.rawValue, systemImage: type.icon).tag(type)
                }
            }

            // [v25.397] 電池相關欄位。填了才算得出充電損耗、續航與家充佔比；
            // 不填不影響既有功能，所以維持選填。
            if hasBatteryType {
                HStack {
                    Text("原廠電池容量")
                    Spacer()
                    TextField("選填", text: $batteryCapacityText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                    Text("kWh").font(.caption).foregroundStyle(.secondary)
                }
                // [v25.538] 提示不再建議填「家」：地點「包含」關鍵字就算家充，「全家」「家樂福」的充電站都會被算進去
                TextField("家充地點關鍵字（例：社區 B2 充電位）", text: $homeChargePlace)
            }

            // [v25.538] 購入日、售出日不能選未來：未來的售出日會讓車馬上蓋「售出」章，淨資產卻還算它
            DatePicker("購入日期", selection: $purchaseDate, in: ...Date(), displayedComponents: .date)
                .onChange(of: purchaseDate) { _, newValue in
                    // 售出日期 DatePicker 用 in: purchaseDate... 限制往後可選範圍，只擋新選取、
                    // 不會回頭修正已選定的舊值；購入日期後調若晚於既有售出日期，會存出售出早於
                    // 購入的無效資料（同型修復見 AddIncomeView 起薪/結束日 v24.63 已知問題）。
                    if soldDate < newValue { soldDate = newValue }
                }

            Toggle("已售出", isOn: $isSold)
            if isSold {
                // [v25.538] 舊資料的購入日可能在未來，上限取兩者較晚的，範圍才不會倒過來（倒過來會閃退）
                DatePicker("售出日期", selection: $soldDate, in: purchaseDate...max(purchaseDate, Date()), displayedComponents: .date)
            }
        } header: {
            vehicleSectionHeader("車輛資訊", icon: "car.fill", color: .teal)
        }
    }

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
            // [v25.538] 取代列表底部的「折舊開關」（它一按就永久蓋掉所有車的估值）：
            // 這裡只把估計值填進欄位，你按儲存才算數
            if let estimate = fifteenPercentEstimate {
                Button {
                    currentValueText = Self.editableAmountText(estimate / 10000, decimals: 4)
                } label: {
                    Label(fifteenPercentLabel(estimate), systemImage: "wand.and.stars")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        } header: {
            vehicleSectionHeader("價值", icon: "yensign.circle.fill", color: .green)
        } footer: {
            Text("以萬元為單位輸入，例如輸入 80 代表 NT$800,000。")
        }
    }

    /// [v25.538] 照每年 15% 估：購入價 × 0.85^(持有年數)，持有年數＝天數 ÷ 365.25（最少 0），算到售出日或今天。
    /// 1 萬以上進位到千元（跟按鈕上「約 NT$X萬」寫的一樣），未滿 1 萬進位到元。購入價沒填或 ≤ 0 時沒有這顆。
    private var fifteenPercentEstimate: Double? {
        guard let priceWan = Double(purchasePriceText.trimmingCharacters(in: .whitespaces)), priceWan > 0 else { return nil }
        let price = priceWan * 10000
        guard price.isFinite else { return nil }
        let end = isSold ? soldDate : Date()
        let years = max(0, end.timeIntervalSince(purchaseDate) / 86400 / 365.25)
        let raw = price * pow(0.85, years)
        return raw >= 10000 ? (raw / 1000).rounded() * 1000 : raw.rounded()
    }

    /// [v25.538] 先組成 String 再給 Label：直接寫字面值會被當成 LocalizedStringKey，「15%」的 % 可能被當成格式符號
    private func fifteenPercentLabel(_ estimate: Double) -> String {
        "照每年 15% 估：約 " + estimate.ntdWanString + "（帶入）"
    }

    // MARK: - 定期支出

    private var fixedExpenseSection: some View {
        Section {
            ForEach(Array(fixedExpenses.enumerated()), id: \.element.id) { idx, fe in
                Button {
                    if let expId = fe.linkedExpenseId,
                       let exp = expenseStore.expenses.first(where: { $0.id == expId }) {
                        editingFixedExpense = exp
                    }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color.blue.opacity(0.22), Color.blue.opacity(0.09)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                                .frame(width: 36, height: 36)
                            Circle()
                                .stroke(Color.blue.opacity(0.18), lineWidth: 1)
                                .frame(width: 36, height: 36)
                            Image(systemName: "calendar.badge.checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.blue)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(fe.category.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(fe.period == .monthly ? "每月" : "每年")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.blue.opacity(0.10))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.blue.opacity(0.18), lineWidth: 0.5))
                        }
                        Spacer()
                        Text(fe.amount > 0 ? formatCurrency(fe.amount) : "未填")
                            .font(.subheadline.bold())
                            .foregroundStyle(fe.amount > 0 ? .primary : .secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // [v3] 交錯淡入 + 向上進場動畫，對齊 SpouseResumeView.expenseRow /
                // ResumeGiftSection.giftRow 清單列規格
                .opacity(fixedExpensesAppeared ? 1 : 0)
                .offset(y: fixedExpensesAppeared ? 0 : 12)
                .animation(
                    .spring(response: 0.44, dampingFraction: 0.82)
                        .delay(0.04 * Double(min(idx, 14))),
                    value: fixedExpensesAppeared
                )
            }
            .onDelete(perform: deleteFixedExpenses)

            Button {
                showFixedCategoryPicker = true
            } label: {
                Label("新增項目", systemImage: "plus.circle")
                    .foregroundStyle(.green)
            }
        } header: {
            vehicleSectionHeader("定期支出", icon: "calendar.badge.checkmark", color: .blue, count: fixedExpenses.count)
        } footer: {
            if !fixedExpenses.isEmpty {
                let monthlyTotal = fixedExpenses.reduce(0.0) { $0 + $1.period.toMonthly($1.amount) }
                Text("定期支出合計每月 \(formatCurrency(monthlyTotal))，與記帳模式的固定支出連動。")
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05)) {
                fixedExpensesAppeared = true
            }
        }
    }

    // MARK: - 變動支出

    private var variableExpenseSection: some View {
        Section {
            ForEach(Array(variableExpenses.enumerated()), id: \.element.id) { idx, ve in
                Button {
                    if let expId = ve.linkedExpenseId,
                       let exp = expenseStore.expenses.first(where: { $0.id == expId }) {
                        editingVariableExpense = exp
                    }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color.orange.opacity(0.22), Color.orange.opacity(0.09)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                                .frame(width: 36, height: 36)
                            Circle()
                                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
                                .frame(width: 36, height: 36)
                            Image(systemName: ve.category.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.orange)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ve.category.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            HStack(spacing: 3) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 9, weight: .medium))
                                Text(formatShortDate(ve.date))
                                    .font(.caption2.weight(.medium))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                        }
                        Spacer()
                        Text(ve.amount > 0 ? formatCurrency(ve.amount) : "未填")
                            .font(.subheadline.bold())
                            .foregroundStyle(ve.amount > 0 ? .primary : .secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // [v3] 交錯淡入 + 向上進場動畫，對齊 SpouseResumeView.expenseRow /
                // ResumeGiftSection.giftRow 清單列規格
                .opacity(variableExpensesAppeared ? 1 : 0)
                .offset(y: variableExpensesAppeared ? 0 : 12)
                .animation(
                    .spring(response: 0.44, dampingFraction: 0.82)
                        .delay(0.04 * Double(min(idx, 14))),
                    value: variableExpensesAppeared
                )
            }
            .onDelete(perform: deleteVariableExpenses)

            Button {
                showVariableCategoryPicker = true
            } label: {
                Label("新增項目", systemImage: "plus.circle")
                    .foregroundStyle(.green)
            }
        } header: {
            vehicleSectionHeader("變動支出", icon: "arrow.triangle.2.circlepath", color: .orange, count: variableExpenses.count)
        } footer: {
            if !variableExpenses.isEmpty {
                let total = variableExpenses.reduce(0.0) { $0 + $1.amount }
                Text("變動支出合計 \(formatCurrency(total))，與記帳模式的變動支出連動。")
            } else {
                Text("油錢、停車、洗車、臨時維修等支出，每筆單獨記錄。")
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.08)) {
                variableExpensesAppeared = true
            }
        }
    }

    // MARK: - 試算

    @ViewBuilder
    private var calcSection: some View {
        let purchase = (Double(purchasePriceText) ?? 0) * 10000
        let current = (Double(currentValueText) ?? 0) * 10000
        let fixedMonthly = fixedExpenses.reduce(0.0) { $0 + $1.period.toMonthly($1.amount) }
        let variableTotal = variableExpenses.reduce(0.0) { $0 + $1.amount }

        if purchase > 0 || fixedMonthly > 0 {
            Section {
                if purchase > 0, current > 0, purchase > current {
                    calcRow(icon: "arrow.down.circle.fill", label: "折舊金額",
                            value: formatCurrency(purchase - current), color: .red)
                    calcRow(icon: "percent", label: "折舊率",
                            value: String(format: "%.1f%%", (purchase - current) / purchase * 100), color: .red)
                }
                if fixedMonthly > 0 {
                    calcRow(icon: "calendar.circle.fill", label: "每月定期支出",
                            value: formatCurrency(fixedMonthly), color: .orange)
                }
                if variableTotal > 0 {
                    calcRow(icon: "arrow.triangle.2.circlepath.circle.fill", label: "變動支出累計",
                            value: formatCurrency(variableTotal), color: .orange)
                }
            } header: {
                vehicleSectionHeader("試算", icon: "chart.bar.fill", color: .purple)
            }
            // v2：試算區塊進場動畫
            .opacity(calcSectionAppeared ? 1 : 0)
            .offset(y: calcSectionAppeared ? 0 : 12)
            .onAppear {
                withAnimation(.spring(response: 0.48, dampingFraction: 0.80).delay(0.20)) {
                    calcSectionAppeared = true
                }
            }
        }
    }

    private var noteSection: some View {
        Section {
            TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
        } header: {
            vehicleSectionHeader("備註", icon: "text.bubble.fill", color: .secondary)
        }
    }

    // MARK: - 自動存檔（在新增項目之前確保車輛已存在於 store）

    @discardableResult
    private func ensureVehicleSavedInStore() -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty,
              let priceWan = Double(purchasePriceText), priceWan > 0 else {
            showError = true
            errorScrollTick += 1
            return false
        }
        showError = false

        let price = priceWan * 10000
        let currentVal = currentValueToSave(priceWan: priceWan)
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)

        if var vehicle = currentVehicle {
            // [v25.538] 編輯既有車子時這裡就把表頭寫進去了，記下來，取消時才知道要還原
            headerAutoSaved = true
            autoSavedFields = currentFields
            vehicle.name = trimmedName
            vehicle.brand = brand.trimmingCharacters(in: .whitespaces)
            vehicle.ownerName = ownerName
            vehicle.powerType = powerType
            vehicle.purchaseDate = purchaseDate
            vehicle.soldDate = isSold ? soldDate : nil
            vehicle.purchasePrice = price
            vehicle.currentValue = currentVal
            vehicle.note = trimmedNote
            vehicle.batteryCapacityKWh = batteryValue
            vehicle.homeChargePlace = homeKeywordValue
            financeStore.update(vehicle)
        } else {
            let vehicle = Vehicle(
                id: stableVehicleId,
                name: trimmedName,
                brand: brand.trimmingCharacters(in: .whitespaces),
                ownerName: ownerName,
                powerType: powerType,
                purchaseDate: purchaseDate,
                soldDate: isSold ? soldDate : nil,
                purchasePrice: price,
                currentValue: currentVal,
                fixedExpenses: [],
                variableExpenses: [],
                note: trimmedNote,
                batteryCapacityKWh: batteryValue,
                homeChargePlace: homeKeywordValue
            )
            financeStore.add(vehicle)
            hasAutoSaved = true
        }
        return true
    }

    /// [v25.538] 工具列「取消」：有改過先問「要放棄這次的修改嗎？」，沒改過直接關
    private func cancelTapped() {
        guard hasChanges else { cancelAndRollback(); return }
        discardMessage = discardConfirmMessage()
        showDiscardConfirm = true
    }

    /// [v25.538] 放棄確認框的說明：講清楚按下去會刪什麼、留什麼
    private func discardConfirmMessage() -> String {
        if editing == nil {
            guard hasAutoSaved, let v = currentVehicle else { return "剛剛填的資料不會存。" }
            let s = VehicleDeletion.summary(of: v, expenseStore: expenseStore)
            guard s.expenseCount > 0 else { return "剛剛填的資料不會存，這台車不會加進理財。" }
            return "這台車和這次記的 \(s.expenseCount) 筆支出（連同收據照片和銀行扣款紀錄）都會刪除，不能復原。"
        }
        if headerAutoSaved {
            return "車子的資料會回到打開這頁之前的樣子；這次在記帳新增或修改的支出已經存好，會留著。"
        }
        return "剛剛改的資料不會存。"
    }

    /// 「取消」真正做的事（有改過時是確認框按「放棄修改」之後）。
    /// 新增流程：「新增項目」會先把車子自動存進 store（ensureVehicleSavedInStore），取消時要整台拿掉，
    /// 連這次記的支出一起刪。[v25.538] 改走共用的 VehicleDeletion（.withExpenses）：以前只刪鏡像連到的支出，
    /// 銀行扣款紀錄和只靠 linkedVehicleId 連過來的支出都留下來。
    /// 編輯既有車子：「新增項目」一樣先把表頭存進去，以前按取消不還原。[v25.538] 把車子本身的欄位還原成
    /// 打開時的樣子；支出不動（那些在記帳裡是真的花費），照片紀錄也照 store 現在的。
    /// 先關掉這頁、下一個 runloop 才寫 store：確認框、sheet 正在收的那個交易裡改 store 容易閃退。
    private func cancelAndRollback() {
        let finance = financeStore
        let expenses = expenseStore
        let life = lifeStore
        let vehicleId = stableVehicleId
        let original = openedSnapshot ?? editing
        let rollbackNew = editing == nil && hasAutoSaved
        let needsHeaderRestore = editing != nil && headerAutoSaved
        dismiss()
        guard rollbackNew || needsHeaderRestore else { return }
        DispatchQueue.main.async {
            guard var v = finance.vehicles.first(where: { $0.id == vehicleId }) else { return }
            // 刪整台只走新增流程（editing == nil）；編輯既有車子不管怎樣都只還原表頭
            if needsHeaderRestore {
                guard let original else { return }
                Self.restoreHeader(&v, from: original)
                finance.update(v)
            } else if rollbackNew {
                VehicleDeletion.delete(v, mode: .withExpenses, financeStore: finance,
                                       expenseStore: expenses, lifeStore: life)
            }
        }
    }

    /// [v25.538] 車子本身的欄位還原成打開編輯頁時的快照；定期／變動支出鏡像、照片紀錄留著 store 現在的
    private static func restoreHeader(_ v: inout Vehicle, from original: Vehicle) {
        v.name = original.name
        v.brand = original.brand
        v.ownerName = original.ownerName
        v.powerType = original.powerType
        v.purchaseDate = original.purchaseDate
        v.soldDate = original.soldDate
        v.purchasePrice = original.purchasePrice
        v.currentValue = original.currentValue
        v.note = original.note
        v.batteryCapacityKWh = original.batteryCapacityKWh
        v.homeChargePlace = original.homeChargePlace
    }

    // MARK: - 預設值（給 AddExpenseView）

    private func makeFixedPreset(for cat: VehicleFixedCategory) -> AddExpensePreset {
        switch cat {
        case .carLoan:
            return AddExpensePreset(
                fixedCategory: .loan,
                loanSubCategory: .car,
                recurrence: .monthly,
                linkedVehicleId: stableVehicleId
            )
        case .subscription:
            return AddExpensePreset(
                fixedCategory: .subscription,
                recurrence: .monthly,
                linkedVehicleId: stableVehicleId,
                fixedAssetLink: .vehicle
            )
        case .tax:
            return AddExpensePreset(
                fixedCategory: .other,
                recurrence: .yearly,
                linkedVehicleId: stableVehicleId,
                fixedAssetLink: .vehicle
            )
        }
    }

    /// [v25.538] 這幾種從車子打開記帳時，直接顯示車輛區（度數、電量、里程），不用再切進階模式
    private static let vehicleSectionCategories: Set<VehicleVariableCategory> = [.electricity, .fuel, .maintenance, .repair]

    private func makeVariablePreset(for cat: VehicleVariableCategory) -> AddExpensePreset {
        AddExpensePreset(
            variableCategory: .vehicle,
            vehicleExpenseCategory: cat,
            linkedVehicleId: stableVehicleId,
            assetLink: .vehicle,
            showVehicleSection: Self.vehicleSectionCategories.contains(cat)
        )
    }

    // MARK: - 刪除

    // [v25.538] 左滑刪除不再直接刪：先記下要刪哪幾列、連到哪些記帳支出，跳確認框，
    // 確認後才連記帳支出、收據照片、銀行扣款紀錄一起刪（confirmExpenseDeletion）。

    private func deleteFixedExpenses(at offsets: IndexSet) {
        let items = fixedExpenses
        let picked = offsets.filter { $0 < items.count }.map { items[$0] }
        guard !picked.isEmpty else { return }
        pendingExpenseDeletion = makeSwipeDeletion(
            linkedExpenseIds: picked.map { $0.linkedExpenseId },
            itemIds: picked.map { $0.id }
        )
    }

    private func deleteVariableExpenses(at offsets: IndexSet) {
        let items = variableExpenses
        let picked = offsets.filter { $0 < items.count }.map { items[$0] }
        guard !picked.isEmpty else { return }
        pendingExpenseDeletion = makeSwipeDeletion(
            linkedExpenseIds: picked.map { $0.linkedExpenseId },
            itemIds: picked.map { $0.id }
        )
    }

    /// [v25.538] 確認框的說明：沒連到記帳（或記帳那筆已經不在）的項目只會從車子拿掉
    private func expenseDeletionMessage(_ request: ExpenseSwipeDeletion) -> String {
        let count = request.foundExpenseCount
        if count == 1 { return "記帳裡的這筆和銀行扣款紀錄會一起刪除，不能復原。" }
        if count > 1 { return "記帳裡的這 \(count) 筆和銀行扣款紀錄會一起刪除，不能復原。" }
        return "這個項目沒有連到記帳，只會從這台車拿掉，不能復原。"
    }

    /// [v25.538] 確認後才刪；延後一個 runloop，因為確認框正在收的那個交易裡改 store 容易閃退
    private func confirmExpenseDeletion(_ request: ExpenseSwipeDeletion) {
        let finance = financeStore
        let expenses = expenseStore
        let life = lifeStore
        let vehicleId = stableVehicleId
        DispatchQueue.main.async {
            // 記帳支出（含收據照片）＋所有銀行帳戶裡對得上的扣款紀錄；每台車上指到它們的鏡像也一起清
            RealEstateDeletion.removeExpenses(request.expenseIds, expenseStore: expenses, lifeStore: life)
            // 沒連到記帳的舊項目（linkedExpenseId 是 nil）上面清不到，照列的 id 從這台車拿掉
            guard var v = finance.vehicles.first(where: { $0.id == vehicleId }) else { return }
            let before = v.fixedExpenses.count + v.variableExpenses.count
            v.fixedExpenses.removeAll { request.itemIds.contains($0.id) }
            v.variableExpenses.removeAll { request.itemIds.contains($0.id) }
            if v.fixedExpenses.count + v.variableExpenses.count != before { finance.update(v) }
        }
    }

    // MARK: - 儲存

    private func save() {
        guard !isSaving else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty,
              let priceWan = Double(purchasePriceText), priceWan > 0 else {
            showError = true; errorScrollTick += 1; return
        }
        isSaving = true

        let price = priceWan * 10000
        let currentVal = currentValueToSave(priceWan: priceWan)
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)

        if var vehicle = currentVehicle {
            vehicle.name = trimmedName
            vehicle.brand = brand.trimmingCharacters(in: .whitespaces)
            vehicle.ownerName = ownerName
            vehicle.powerType = powerType
            vehicle.purchaseDate = purchaseDate
            vehicle.soldDate = isSold ? soldDate : nil
            vehicle.purchasePrice = price
            vehicle.currentValue = currentVal
            vehicle.note = trimmedNote
            vehicle.batteryCapacityKWh = batteryValue
            vehicle.homeChargePlace = homeKeywordValue
            financeStore.update(vehicle)
        } else {
            let vehicle = Vehicle(
                id: stableVehicleId,
                name: trimmedName,
                brand: brand.trimmingCharacters(in: .whitespaces),
                ownerName: ownerName,
                powerType: powerType,
                purchaseDate: purchaseDate,
                soldDate: isSold ? soldDate : nil,
                purchasePrice: price,
                currentValue: currentVal,
                fixedExpenses: [],
                variableExpenses: [],
                note: trimmedNote,
                batteryCapacityKWh: batteryValue,
                homeChargePlace: homeKeywordValue
            )
            financeStore.add(vehicle)
        }
        dismiss()
    }

    /// 這個動力類型有沒有電池
    private var hasBatteryType: Bool {
        powerType == .electric || powerType == .hybrid || powerType == .electricMotorcycle
    }

    /// 只有有電池的車型才存電池欄位；換成油車就存 nil，
    /// 不要留著上一個車型填到一半的值（同 careerFields 的既有規矩）
    private var batteryValue: Double? {
        guard hasBatteryType, let v = Double(batteryCapacityText), v > 0 else { return nil }
        return v
    }

    private var homeKeywordValue: String? {
        let t = homeChargePlace.trimmingCharacters(in: .whitespaces)
        return (hasBatteryType && !t.isEmpty) ? t : nil
    }

    /// [v25.538] 估值欄換成台幣。看得懂的數字（含 0）照填的存；空白或看不懂＝沒改：
    /// 編輯時維持原本的估值（原本 0 就還是 0，loadEditing 把 0 帶成空白），新增時才用購入價。
    /// 以前空白一律變購入價，估值 0（報廢、全損）的車打開再按一次儲存，估值就被悄悄改成購入價。
    private func currentValueToSave(priceWan: Double) -> Double {
        let text = currentValueText.trimmingCharacters(in: .whitespaces)
        if let wan = Double(text), wan >= 0, (wan * 10000).isFinite { return wan * 10000 }
        if let e = openedSnapshot ?? editing { return e.currentValue }
        return priceWan * 10000
    }

    /// [v25.538] 金額帶回輸入框：四捨五入到指定小數位後去掉多餘的 0（照抄 AddRealEstateView v25.530）。
    /// 「萬」用 4 位＝1 元精度。只給可編輯的文字用，顯示用的格式不走這裡。
    private static func editableAmountText(_ value: Double, decimals: Int) -> String {
        var text = String(format: "%.\(decimals)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }

    // MARK: - 載入編輯

    /// [v25.538] 只在第一次出現時載入：onAppear 可能重跑（例如上面蓋的記帳 sheet 收起來），
    /// 會拿開頁時的舊快照蓋掉正在改的欄位。載入完記下欄位的樣子，之後拿來比對有沒有改過。
    private func loadEditingOnce() {
        guard !didLoad else { return }
        didLoad = true
        openedSnapshot = editing
        loadEditing()
        initialFields = currentFields
    }

    private func loadEditing() {
        guard let e = editing else { return }
        name = e.name; brand = e.brand; ownerName = e.ownerName
        powerType = e.powerType
        if let cap = e.batteryCapacityKWh { batteryCapacityText = String(format: "%g", cap) }
        homeChargePlace = e.homeChargePlace ?? ""
        purchaseDate = e.purchaseDate
        if let sd = e.soldDate {
            isSold = true
            soldDate = sd
        } else {
            isSold = false
            soldDate = Date()
        }
        // [v25.538] 金額帶回輸入框不能丟位數：%g 只有 6 位有效數字，12,345,678 存一次就變 12,345,700。
        // 估值 0 照舊帶成空白；存檔時空白＝維持原值（currentValueToSave），不會變成購入價
        purchasePriceText = e.purchasePrice > 0 ? Self.editableAmountText(e.purchasePrice / 10000, decimals: 4) : ""
        currentValueText = e.currentValue > 0 ? Self.editableAmountText(e.currentValue / 10000, decimals: 4) : ""
        note = e.note
    }

    // MARK: - 美化輔助元件

    // MARK: - v2 新增：英雄預覽卡 & 錯誤橫幅

    // v2：翠綠漸層英雄預覽卡（即時反映購入價 / 估值 / 折舊 / 月固定支出）
    private var vehiclePreviewCard: some View {
        let purchaseWan = Double(purchasePriceText) ?? 0
        let currentWan  = Double(currentValueText) ?? 0
        let purchase    = purchaseWan * 10000
        let current     = currentWan  * 10000
        let depAmt      = purchase > 0 && current > 0 && purchase > current ? purchase - current : 0.0
        let depRate     = purchase > 0 && current > 0 ? (purchase - current) / purchase * 100 : 0.0
        let monthlyFix  = fixedExpenses.reduce(0.0) { $0 + $1.period.toMonthly($1.amount) }
        let accentA     = Color(red: 0.15, green: 0.72, blue: 0.65)
        let accentB     = Color(red: 0.05, green: 0.55, blue: 0.60)
        return ZStack(alignment: .topLeading) {
            // 漸層背景
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(
                    colors: [accentA, accentB],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            // 散景裝飾圓
            Circle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 90, height: 90)
                .offset(x: -20, y: -30)
                .blur(radius: 6)
            Circle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 70, height: 70)
                .offset(x: 250, y: 4)
                .blur(radius: 5)
            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 55, height: 55)
                .offset(x: 190, y: 52)
                .blur(radius: 8)
            // 玻璃光澤高光
            LinearGradient(
                colors: [.white.opacity(0.18), .clear],
                startPoint: .top, endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            // 卡片內容
            VStack(alignment: .leading, spacing: 12) {
                // 頂列：動力類型 + 折舊率
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: powerType.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(powerType.rawValue)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white.opacity(0.90))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.white.opacity(0.22))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 0.6))
                    Spacer()
                    if purchaseWan > 0 && currentWan > 0 {
                        Text(String(format: "%.1f%% 折舊", max(0, depRate)))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(depAmt > 0
                                ? Color(red: 1.0, green: 0.82, blue: 0.50)
                                : .white.opacity(0.80))
                            .padding(.horizontal, 7).padding(.vertical, 2.5)
                            .background(.white.opacity(0.18))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.5))
                    }
                }
                // 車名（[v25.520] 過長改跑馬燈，原本 minimumScaleFactor 縮字）
                MarqueeText(name.isEmpty ? "車輛名稱" : name)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(name.isEmpty ? .white.opacity(0.45) : .white)
                // 購入價大字
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(purchaseWan > 0 ? purchase.ntdWanString : "NT$ —")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(purchaseWan > 0 ? .white : .white.opacity(0.45))
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.72)
                    Text("購入價")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
                // KPI 橫列（三格）
                if purchaseWan > 0 {
                    Rectangle()
                        .fill(.white.opacity(0.20))
                        .frame(height: 0.5)
                    HStack(spacing: 0) {
                        HeroKpiCell(label: "目前估值",
                                    value: currentWan > 0 ? current.ntdWanString : "—",
                                    icon: "speedometer")
                        HeroKpiDivider()
                        // 折舊金額：>0 時用金色標示，維持與車輛卡片一致的語意色
                        HeroKpiCell(label: "折舊金額",
                                    value: depAmt > 0 ? depAmt.ntdWanString : "—",
                                    icon: "arrow.down.right",
                                    valueColor: depAmt > 0
                                        ? Color(red: 1.0, green: 0.82, blue: 0.50)
                                        : .white.opacity(0.45))
                        HeroKpiDivider()
                        HeroKpiCell(label: "月固定支出",
                                    value: monthlyFix > 0 ? monthlyFix.ntdWanString : "—",
                                    icon: "calendar")
                    }
                    .padding(.top, 2)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.18), lineWidth: 0.75)
        )
        .shadow(color: accentB.opacity(0.28), radius: 12, x: 0, y: 6)
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }

    // v2：橘色警告橫幅（取代純紅字）
    private var errorBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)
            Text("請輸入車名和購入價格")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.25), lineWidth: 0.75))
    }

    @ViewBuilder
    private func vehicleSectionHeader(_ title: String, icon: String, color: Color, count: Int? = nil) -> some View {
        HStack(spacing: 7) {
            Capsule()
                .fill(LinearGradient(
                    colors: [color, color.opacity(0.70)],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 4, height: 18)
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            if let n = count, n > 0 {
                Text("\(n)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(color.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.6)) // v2
            }
            Spacer()
        }
        .textCase(nil)
    }

    private func calcRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [color.opacity(0.18), color.opacity(0.08)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(color.opacity(0.10))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(color.opacity(0.20), lineWidth: 0.5))
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        value.ntdWanString
    }

    // v2：靜態共用實例，避免每次 render 重新分配
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()

    private func formatShortDate(_ date: Date) -> String {
        Self.shortDateFormatter.string(from: date)
    }
}
