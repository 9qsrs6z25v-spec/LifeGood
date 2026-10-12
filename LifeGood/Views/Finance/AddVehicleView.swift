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
//
// [v25.539] 同一套數字：
//   - 上面 4、7、12 的試算區和英雄預覽卡拿掉：預覽卡的大字是購入價、月固定只算鏡像，跟卡片、列表的數字對不起來，
//     月固定同一頁還出現三次。車子的數字一律在卡片看（VehicleFacts）。
//   - 加成交價（已售出才有）、估值更新日（改估值、新增車子時寫今天；清空估值欄＝不改估值、不寫日子）。
//   - 卡片的「去改」「更新估值」會帶 focus 進來：打開後捲到那一欄、游標放進去（同 AddRealEstateView）。
//   - 最下面「刪除這台車」（編輯時才有、要付費），走跟列表左滑同一個確認框（只刪車子／連記帳一起刪）。
//   - 標成已售出、取消已售出、改售出日時，連到這台車的車貸、保險、稅費停在售出日（或還原），記帳一次寫回。
//   - 「新增項目」前的自動存檔和按「儲存」合成一份寫入（writeVehicle）。
//   - 定期支出的種類加「保險」「車位月租」，做成 static，卡片之後的「＋ 記一筆」也用同一份。
//     這頁的選單只加「車位月租」：車險不寫鏡像，這頁的清單看不到（見 FixedPresetKind.editorMenu）。
//   - 定期支出列的名稱改照記帳那筆的分類寫（車位月租不再顯示成鏡像的「稅費」）。

/// [v25.539] 從卡片打開編輯頁時要捲到哪一欄（同 HouseEditFocus）
enum VehicleEditFocus: Hashable { case none, purchase, value, sold, soldPrice, battery, homeCharge, owner, brand, note }

struct AddVehicleView: View {
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    let editing: Vehicle?
    /// [v25.539] 打開後要捲到哪一欄（.none＝不捲）
    let focus: VehicleEditFocus
    /// [v25.538] 用 @State 存：sheet 的內容會因為上一頁重畫而重新 init，
    /// 用 let 的話新增流程每次 init 都會換一個新的 UUID，自動存檔和「取消」回滾就找不到那台車
    @State private var stableVehicleId: UUID
    /// [v25.539] 捲到 focus 那一欄只做一次（記帳 sheet 收起來 onAppear 會再跑）
    @State private var didApplyFocus = false
    @FocusState private var focusedField: VehicleEditFocus?
    /// [v25.539] 最下面「刪除這台車」：要刪的車和筆數在按的那一刻算好；付費提示
    @State private var deleteVehicleRequest: VehicleDeleteRequest?
    @State private var showDeleteVehicleConfirm = false
    @State private var showPremiumAlert = false

    init(editing: Vehicle? = nil, focus: VehicleEditFocus = .none) {
        self.editing = editing
        self.focus = focus
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
    /// [v25.539] 成交價（萬元）；空白＝沒填，卡片用估值當賣價
    @State private var soldPriceText = ""
    @State private var note = ""
    @State private var showError = false
    @State private var hasAutoSaved: Bool = false
    // 儲存為同步寫回 store 後立即 dismiss()，sheet 收合動畫期間按鈕仍可觸發，
    // 快速連點會建立兩筆重複車輛紀錄；補上忙碌守衛比照 AddRealEstateView 既有修法。
    @State private var isSaving = false
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
    /// [v25.539] 改用 FixedPresetKind：多了保險、車位月租（VehicleFixedCategory 不能加 case）
    @State private var addingFixedPreset: FixedPresetKind?
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
        /// [v25.539] 沒勾「已售出」時是空的（同售出日）
        var soldPriceText: String
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
            soldPriceText: isSold ? soldPriceText : "",
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
                withDeletePresentations(withConfirmations(withCategoryPickers(withExpenseSheets(editorForm))))
                    .onAppear {
                        loadEditingOnce()
                        applyFocus(proxy)
                    }
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
            // [v25.539] 頂端的英雄預覽卡、下面的試算區拿掉：大字是購入價、月固定只算鏡像，跟卡片對不起來
            vehicleInfoSection
            valueSection
            fixedExpenseSection
            variableExpenseSection
            noteSection
            if editing != nil {
                deleteVehicleSection
            }
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
            .sheet(item: $addingFixedPreset) { kind in
                AddExpenseView(
                    expenseType: .fixed,
                    preset: Self.makeFixedPreset(for: kind, vehicleId: stableVehicleId)
                )
                .appStores()
            }
            .sheet(item: $addingVariableCategory) { cat in
                AddExpenseView(
                    expenseType: .variable,
                    preset: Self.makeVariablePreset(for: cat, vehicleId: stableVehicleId)
                )
                .appStores()
            }
    }

    private func withCategoryPickers<Content: View>(_ content: Content) -> some View {
        content
            .confirmationDialog("選擇定期支出類別", isPresented: $showFixedCategoryPicker, titleVisibility: .visible) {
                ForEach(FixedPresetKind.editorMenu) { kind in
                    Button(kind.rawValue) {
                        guard writeVehicle(finishing: false) else { return }
                        addingFixedPreset = kind
                    }
                }
                Button("取消", role: .cancel) {}
            }
            .confirmationDialog("選擇變動支出類別", isPresented: $showVariableCategoryPicker, titleVisibility: .visible) {
                ForEach(VehicleVariableCategory.categories(for: powerType)) { cat in
                    Button(cat.rawValue) {
                        guard writeVehicle(finishing: false) else { return }
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
                .focused($focusedField, equals: .brand)
                .id(VehicleEditFocus.brand)

            if !ownerOptions.isEmpty {
                Picker("車輛所有人", selection: $ownerName) {
                    Text("未指定").tag("")
                    ForEach(ownerOptions, id: \.self) { n in
                        Text(n).tag(n)
                    }
                }
                .id(VehicleEditFocus.owner)
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
                        .focused($focusedField, equals: .battery)
                    Text("kWh").font(.caption).foregroundStyle(.secondary)
                }
                .id(VehicleEditFocus.battery)
                // [v25.538] 提示不再建議填「家」：地點「包含」關鍵字就算家充，「全家」「家樂福」的充電站都會被算進去
                TextField("家充地點關鍵字（例：社區 B2 充電位）", text: $homeChargePlace)
                    .focused($focusedField, equals: .homeCharge)
                    .id(VehicleEditFocus.homeCharge)
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
                .id(VehicleEditFocus.sold)
            if isSold {
                // [v25.538] 舊資料的購入日可能在未來，上限取兩者較晚的，範圍才不會倒過來（倒過來會閃退）
                DatePicker("售出日期", selection: $soldDate, in: purchaseDate...max(purchaseDate, Date()), displayedComponents: .date)
                soldPriceRow
            }
        } header: {
            vehicleSectionHeader("車輛資訊", icon: "car.fill", color: .teal)
        } footer: {
            // [v25.539] 存檔時 VehicleSale.syncStops 會照這句做（決定 6）
            if isSold {
                Text("標成已售出後，連到這台車的車貸、保險、稅費會停在售出日；停車月租、訂閱請自己確認。")
            }
        }
    }

    /// [v25.539] 成交價（同房屋）：賣出價差、帳本的「拿回」、理財總覽回推賣出前的價值都看它，沒填才用目前估值
    private var soldPriceRow: some View {
        HStack {
            TextField("成交價（沒填用目前估值）", text: $soldPriceText)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .soldPrice)
            Text("萬元").foregroundStyle(.secondary)
        }
        .id(VehicleEditFocus.soldPrice)
    }

    private var valueSection: some View {
        Section {
            HStack {
                TextField("購入價格", text: $purchasePriceText).keyboardType(.decimalPad)
                    .focused($focusedField, equals: .purchase)
                Text("萬元").foregroundStyle(.secondary)
            }
            .id(VehicleEditFocus.purchase)
            HStack {
                TextField("目前估值", text: $currentValueText).keyboardType(.decimalPad)
                    .focused($focusedField, equals: .value)
                Text("萬元").foregroundStyle(.secondary)
            }
            .id(VehicleEditFocus.value)
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
            valueFooter
        }
    }

    /// [v25.539] 估值多久沒更新一眼看得到（日期是打開這頁之前那次存的；改了估值按儲存才換成今天）
    private var valueFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("以萬元為單位輸入，例如輸入 80 代表 NT$800,000。")
            if let updated = (openedSnapshot ?? editing)?.valueUpdatedAt {
                Text("估值更新於 " + HouseCardFormat.ymd(updated))
            }
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
                            Text(fixedRowTitle(fe))
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

    /// [v25.539] 列的名稱照記帳那筆的分類寫（跟卡片同一個 VehicleFacts.categoryLabel）：
    /// 「車位月租」存進鏡像的分類是「稅費」，照鏡像寫會跟你剛選的對不上。記帳找不到那筆才用鏡像的分類
    private func fixedRowTitle(_ fe: VehicleFixedExpense) -> String {
        guard let expId = fe.linkedExpenseId,
              let exp = expenseStore.expenses.first(where: { $0.id == expId }) else { return fe.category.rawValue }
        return VehicleFacts.categoryLabel(exp)
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

    private var noteSection: some View {
        Section {
            TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
                .focused($focusedField, equals: .note)
                .id(VehicleEditFocus.note)
        } header: {
            vehicleSectionHeader("備註", icon: "text.bubble.fill", color: .secondary)
        }
    }

    // MARK: - [v25.539] 從卡片打開：捲到那一欄

    /// 等表單畫好再捲過去；金額、文字欄位順便把游標放進去（照 AddRealEstateView.applyFocus）
    private func applyFocus(_ proxy: ScrollViewProxy) {
        guard focus != VehicleEditFocus.none, !didApplyFocus else { return }
        didApplyFocus = true
        // 成交價只有勾了「已售出」才有那一列，沒有就捲到「已售出」
        let target: VehicleEditFocus = (focus == .soldPrice && !isSold) ? .sold : focus
        // loadEditingOnce 剛把欄位填好（含「已售出」那幾列），排到下一輪、等它畫好才捲
        DispatchQueue.main.async {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(target, anchor: .center)
                }
                if Self.focusesTextField(target) { focusedField = target }
            }
        }
    }

    /// 「已售出」開關、車主選單只捲過去；其他是文字欄位，直接把游標放進去
    private static func focusesTextField(_ target: VehicleEditFocus) -> Bool {
        switch target {
        case .purchase, .value, .soldPrice, .battery, .homeCharge, .brand, .note: return true
        case .sold, .owner, .none: return false
        }
    }

    // MARK: - [v25.539] 刪除這台車

    /// 卡片上的「刪除」之後會拿掉（v25.540）：刪整台只在列表左滑和這裡。要付費，走跟列表同一個確認框，
    /// 確認框寫出照片紀錄、記帳支出各幾筆，可以選「只刪車子，記帳留著」
    private var deleteVehicleSection: some View {
        Section {
            Button(role: .destructive) {
                requestVehicleDeletion()
            } label: {
                Label("刪除這台車", systemImage: "trash")
                    .foregroundStyle(.red)
            }
        } footer: {
            Text("照片紀錄會一起刪掉；連到這台車的記帳支出可以選留著或一起刪。")
        }
    }

    /// 要刪的車和筆數在按的這一刻算好（確認框的 message 每次重畫都會跑，不在裡面掃全部記帳）
    private func requestVehicleDeletion() {
        guard subscription.isPremium else {
            showPremiumAlert = true
            return
        }
        guard let v = currentVehicle ?? editing else { return }
        deleteVehicleRequest = VehicleDeleteRequest(
            vehicle: v,
            summary: VehicleDeletion.summary(of: v, expenseStore: expenseStore)
        )
        showDeleteVehicleConfirm = true
    }

    private func withDeletePresentations<Content: View>(_ content: Content) -> some View {
        content
            .vehicleDeleteDialog(isPresented: $showDeleteVehicleConfirm, request: deleteVehicleRequest) { _, mode in
                deleteWholeVehicle(mode: mode)
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
    }

    /// 先關掉這頁、下一個 runloop 才刪（卡片還開在下面，確認框、sheet 正在收的那個交易裡改 store 容易閃退）。
    /// 用 store 裡最新的那一份（自動存過表頭、或確認框開著時被同步改過）
    private func deleteWholeVehicle(mode: VehicleDeletion.Mode) {
        let finance = financeStore
        let expenses = expenseStore
        let life = lifeStore
        let vehicleId = stableVehicleId
        dismiss()
        DispatchQueue.main.async {
            guard let v = finance.vehicles.first(where: { $0.id == vehicleId }) else { return }
            VehicleDeletion.delete(v, mode: mode, financeStore: finance, expenseStore: expenses, lifeStore: life)
        }
    }

    // MARK: - 寫進 store（[v25.539] 自動存檔和儲存合成一份）

    /// 表單寫進 store 只有這一份：「新增項目」前的自動存檔（finishing＝false）和按「儲存」（true）都走這裡。
    /// 以前兩邊各寫一份，欄位一多就會漏一邊（這版多了成交價、估值更新日）。
    /// 自動存檔只寫車子本身，取消時還原得回來；按「儲存」才同步賣車停扣、才關掉這頁。
    @discardableResult
    private func writeVehicle(finishing: Bool) -> Bool {
        if finishing && isSaving { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, let price = Self.positiveWan(purchasePriceText) else {
            showError = true
            errorScrollTick += 1
            return false
        }
        showError = false
        if finishing { isSaving = true }

        // 打開這頁時的樣子（新增流程是 nil）：估值有沒有改、售出日有沒有動都跟它比，
        // 不跟 store 比——自動存檔之後 store 裡已經是改過的
        let original: Vehicle? = openedSnapshot ?? editing
        let currentVal = currentValueToSave(price: price)
        let existing = currentVehicle
        if existing != nil && !finishing {
            // [v25.538] 編輯既有車子時這裡就把表頭寫進去了，記下來，取消時才知道要還原
            headerAutoSaved = true
            autoSavedFields = currentFields
        }
        // 既有的車從 store 那份改（定期／變動鏡像、照片紀錄照留）；新的才建一台空的
        var vehicle = existing ?? Vehicle(id: stableVehicleId, name: trimmedName)
        vehicle.name = trimmedName
        vehicle.brand = brand.trimmingCharacters(in: .whitespaces)
        vehicle.ownerName = ownerName
        vehicle.powerType = powerType
        vehicle.purchaseDate = purchaseDate
        vehicle.soldDate = isSold ? soldDate : nil
        vehicle.purchasePrice = price
        vehicle.currentValue = currentVal
        vehicle.note = note.trimmingCharacters(in: .whitespaces)
        vehicle.batteryCapacityKWh = batteryValue
        vehicle.homeChargePlace = homeKeywordValue
        // [v25.539] 這兩個照這頁的輸入寫：成交價清空＝改回沒填；沒勾已售出就沒有成交價
        vehicle.soldPrice = isSold ? Self.positiveWan(soldPriceText) : nil
        vehicle.valueUpdatedAt = valueStamp(saving: currentVal, original: original)

        if existing != nil {
            financeStore.update(vehicle)
        } else {
            financeStore.add(vehicle)
            if !finishing { hasAutoSaved = true }
        }
        if finishing {
            syncSaleStops(vehicle, original: original)
            dismiss()
        }
        return true
    }

    /// [v25.539] 標成已售出、取消已售出、改了售出日時：連到這台車的車貸、保險、稅費停在售出日（或還原），
    /// 在記帳的副本上改，有改到才一次寫回（決定 6）。售出日沒動就不碰記帳：
    /// 之後在記帳自己改過的結束日，不會因為按一次這頁的儲存就被蓋掉。
    /// 自動存檔不做：取消時只還原車子本身，記帳的結束日還原不了
    private func syncSaleStops(_ vehicle: Vehicle, original: Vehicle?) {
        let cal = Calendar(identifier: .gregorian)
        let newSold: Date? = vehicle.soldDate
        let changed: Bool
        switch (original?.soldDate, newSold) {
        case (nil, nil):
            changed = false
        case let (before?, after?):
            changed = !cal.isDate(before, inSameDayAs: after)
        default:
            changed = true
        }
        guard changed else { return }
        var list = expenseStore.expenses
        if VehicleSale.syncStops(of: vehicle, soldDate: newSold, in: &list, now: Date(), calendar: cal) {
            expenseStore.expenses = list
        }
    }

    /// [v25.539] 估值更新日：新增車子一律寫今天（估值空白就用購入價，也算今天估的）；
    /// 編輯時估值欄填了數字、而且跟打開時不一樣才寫今天（原本是沒填過的 0，填了就算，含填 0）；
    /// 清空、看不懂＝不改估值，日子也照舊
    private func valueStamp(saving value: Double, original: Vehicle?) -> Date? {
        guard let original else { return Date() }
        guard enteredCurrentValue != nil else { return original.valueUpdatedAt }
        let wasUnfilled = original.currentValue <= 0 && original.valueUpdatedAt == nil
        let changed = wasUnfilled || abs(value - original.currentValue) >= 1
        return changed ? Date() : original.valueUpdatedAt
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
    /// 新增流程：「新增項目」會先把車子自動存進 store（writeVehicle(finishing: false)），取消時要整台拿掉，
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
        // [v25.539] 自動存檔也會寫這兩個，一起還原
        v.soldPrice = original.soldPrice
        v.valueUpdatedAt = original.valueUpdatedAt
    }

    // MARK: - 預設值（給 AddExpenseView）

    /// [v25.539] 從車子新增定期支出的種類（這頁的「新增項目」選單；之後卡片的「＋ 記一筆」也用同一份）。
    /// 不用 VehicleFixedCategory：那是存進車子鏡像的分類，加新 case 舊版 App 讀不懂；
    /// 保險、車位月租只看記帳那筆的分類（卡片寫「保險」「車位租金」），不需要鏡像分類
    enum FixedPresetKind: String, CaseIterable, Identifiable {
        case insurance = "保險"
        case tax = "稅費"
        case parkingRent = "車位月租"
        case subscription = "訂閱"
        case carLoan = "車貸"

        var id: String { rawValue }

        /// 這頁「新增項目」選單列的種類。保險不放：車險不寫鏡像（決定 8），這頁的清單讀的是鏡像，
        /// 從這裡記好了清單也看不到，會以為沒存到。這頁的清單 v25.540 拿掉（決定 9），
        /// 保險改從新卡片的「＋ 記保險」進來（makeFixedPreset(.insurance) 已經帶強制險，可以直接用）
        static let editorMenu: [FixedPresetKind] = [.tax, .parkingRent, .subscription, .carLoan]
    }

    /// [v25.539] 改成 static、車子 id 從外面傳：卡片的「＋ 記一筆」、每月養車的「＋ 記保險」不用打開這頁也能用
    static func makeFixedPreset(for kind: FixedPresetKind, vehicleId: UUID) -> AddExpensePreset {
        switch kind {
        case .carLoan:
            return AddExpensePreset(
                fixedCategory: .loan,
                loanSubCategory: .car,
                recurrence: .monthly,
                linkedVehicleId: vehicleId
            )
        case .insurance:
            // 決定 8：車險只寫 linkedVehicleId、不寫鏡像（AddExpenseView 存保險時不寫鏡像，免得舊畫面標成「稅費」）。
            // 保險類別要是強制險或綜合險，記帳才會連到車，所以帶強制險（AddExpenseView 不帶的話預設是儲蓄險）
            return AddExpensePreset(
                fixedCategory: .insurance,
                recurrence: .yearly,
                linkedVehicleId: vehicleId,
                fixedAssetLink: .vehicle,
                insuranceSubCategory: .compulsory
            )
        case .parkingRent:
            // 車位月租：記帳那筆是「房租＋每月」，卡片從記帳讀分類寫「車位租金」，不再從「稅費」繞進去
            return AddExpensePreset(
                fixedCategory: .rent,
                recurrence: .monthly,
                linkedVehicleId: vehicleId,
                fixedAssetLink: .vehicle
            )
        case .subscription:
            return AddExpensePreset(
                fixedCategory: .subscription,
                recurrence: .monthly,
                linkedVehicleId: vehicleId,
                fixedAssetLink: .vehicle
            )
        case .tax:
            return AddExpensePreset(
                fixedCategory: .other,
                recurrence: .yearly,
                linkedVehicleId: vehicleId,
                fixedAssetLink: .vehicle
            )
        }
    }

    /// [v25.538] 這幾種從車子打開記帳時，直接顯示車輛區（度數、電量、里程），不用再切進階模式
    private static let vehicleSectionCategories: Set<VehicleVariableCategory> = [.electricity, .fuel, .maintenance, .repair]

    /// [v25.539] 同 makeFixedPreset 改成 static
    static func makeVariablePreset(for cat: VehicleVariableCategory, vehicleId: UUID) -> AddExpensePreset {
        AddExpensePreset(
            variableCategory: .vehicle,
            vehicleExpenseCategory: cat,
            linkedVehicleId: vehicleId,
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

    /// 工具列「儲存／新增」。[v25.539] 跟自動存檔走同一份 writeVehicle
    private func save() {
        writeVehicle(finishing: true)
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
    /// 編輯時維持原本的估值（原本 0 就還是 0），新增時才用購入價。
    /// 以前空白一律變購入價，估值 0（報廢、全損）的車打開再按一次儲存，估值就被悄悄改成購入價。
    private func currentValueToSave(price: Double) -> Double {
        if let v = enteredCurrentValue { return v }
        if let e = openedSnapshot ?? editing { return e.currentValue }
        return price
    }

    /// [v25.539] 估值欄填的數字（台幣）；空白、看不懂、負的、無限大都回 nil（＝沒改，也不寫估值更新日）
    private var enteredCurrentValue: Double? {
        guard let wan = Double(currentValueText.trimmingCharacters(in: .whitespaces)), wan >= 0 else { return nil }
        let value = wan * 10000
        return value.isFinite ? value : nil
    }

    /// [v25.539] 「萬」輸入框換成台幣（購入價、成交價）；空的、看不懂的、≤ 0 都回 nil（＝沒填）。
    /// 貼上「inf」「1e400」會變成無限大，存進去整份車子 JSON 編碼失敗、默默存不了檔，也當沒填（同 AddRealEstateView）
    private static func positiveWan(_ text: String) -> Double? {
        guard let wan = Double(text.trimmingCharacters(in: .whitespaces)), wan > 0 else { return nil }
        let value = wan * 10000
        return value.isFinite ? value : nil
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
        // [v25.539] 確認過的 0（有估值更新日：「就是 0（報廢）」或你在這頁填過 0）帶成「0」；沒填過的 0 照舊空白
        let valueKnown = e.currentValue > 0 || e.valueUpdatedAt != nil
        currentValueText = valueKnown ? Self.editableAmountText(max(0, e.currentValue) / 10000, decimals: 4) : ""
        // [v25.539] 成交價只帶回你填過的；沒填是空白（卡片用估值當賣價）
        if let sold = e.soldPrice, sold > 0 {
            soldPriceText = Self.editableAmountText(sold / 10000, decimals: 4)
        } else {
            soldPriceText = ""
        }
        note = e.note
    }

    // MARK: - 美化輔助元件（[v25.539] 英雄預覽卡、試算列 calcRow 拿掉了）

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
