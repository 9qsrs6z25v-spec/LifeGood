import SwiftUI
import PhotosUI

// MARK: - 美化紀錄（AddRealEstateView）
// [2026-06] 本次美化方向：
//   1. reSectionHeader：統一升級所有 Section header 為「4pt Capsule 漸層側條 + 彩色圖示
//      + .subheadline.bold 標題」，對齊全 App section header 設計語言（AddVehicleView / AddStockView）。
//      各 section 配色：物件資訊(purple) / 價值(indigo) / 租金(green) / 貸款(blue) /
//      已支出(green) / 變動支出(orange) / 試算(teal) / 備註(secondary)。
//   2. reIconCircle：貸款/已支出列的圖示從 caption 小圖示升級為 32pt 漸層圓形底圖，
//      對齊 FixedExpenseRow / StockDetailView transactionRow 的圖示圓規格。
//   3. 變動支出列：類別標籤從 RoundedRectangle(cornerRadius:6) 改為 Capsule，
//      圖示同步升級為 32pt 漸層圓，對齊 ExpenseRow / variableExpenseSection 設計語言。
//   4. 錯誤驗證：從裸紅字 Text 升級為帶圖示的橘色警告橫幅卡，
//      對齊 AddExpenseView / AddStockView 的錯誤卡片規格；listRowBackground 透明。
//   5. calcSection 數值列：加入彩色 Capsule 背景標籤，使正負值（綠/紅）更一目了然，
//      對齊 RealEstateDetailView cashFlow 的正負色彩規格。
//   6. Form 整體套用 .tint(.purple)，DatePicker / Toggle 等系統元件統一房地產主題色。
// [2026-06 v2] 本次美化方向：
//   7. estatePreviewCard（英雄預覽卡）：Form 頂部新增紫色→靛藍漸層英雄預覽卡，
//      即時顯示物件名稱大字 + 購入價 + 估值/增值/月租 KPI 橫列；
//      三顆散景裝飾圓 + 頂部玻璃光澤（white.opacity(0.18)→clear）；
//      cardAppeared spring 進場動畫（opacity + Y 位移 20pt），
//      對齊 AddVehicleView.vehiclePreviewCard / AddStockView.amountPreviewCard 規格。
//   8. Tab 切換器升級：Picker(.segmented) → @Namespace + matchedGeometryEffect 自訂彩色 Capsule Pill，
//      理財→紫色（chart.bar.fill）/ 房屋資料→青藍（house.fill），
//      spring(response:0.30, dampingFraction:0.72) 平滑滑動，
//      對齊 RealEstateDetailView.tabPicker / SubordinateDetailView.detailTab 設計規格。
//   9. reIconCircle：補入 Circle().stroke(color.opacity(0.22), lineWidth:0.75) overlay，
//      對齊 CareerView v2 / FamilyView v2 / ChildDetailView v2 圖示圓邊框規格。
//  10. 各 Capsule 膠囊補細邊框：
//      貸款期數膠囊 → Capsule().stroke(blue.opacity(0.22), 0.6pt)；
//      已支出日期膠囊 → Capsule().stroke(separator.opacity(0.25), 0.6pt)；
//      變動支出類別膠囊 → Capsule().stroke(orange.opacity(0.22), 0.6pt)，
//      對齊全 App 膠囊統一描邊規格（FinanceChartView v5 / EInvoiceSetupView v2）。
// [2026-07 v3] 金額單位一致性補強：
//  11. estatePreviewCard 月租收入 KPI 格：原本直接顯示 "NT$\(Int(rentalAmt).formatted())"
//      裸台幣整數，與同排「目前估值 / 增值」兩格已採用的萬/億智慧量級格式不一致，
//      月租偏高時字串明顯較長；改為 rentalAmt ≥1萬 顯示「X.X萬」、≥1億 顯示「X.X億」，
//      對齊同卡其餘 KPI 格與 RealEstateDetailView.fmt(_:) 的顯示規格。
// [2026-08 v4] 補齊「房屋資料」分頁 Section header 補齊（雖然本檔案 v1 註記已統一升級
//   所有 Section header，但「房屋資料」分頁的 propertyDetailSection／土地權狀／建物權狀／
//   詳細（新增權狀）共 4 處當時被漏掉，仍是系統預設純文字標頭，與「理財」分頁物件資訊／
//   價值／租金收入等早已升級的 Capsule 側條規格不一致）：
//  12. propertyDetailSection 改用 reSectionHeader("房屋資料", house.fill, .cyan)，色彩對齊
//      Tab 切換器「房屋資料」分頁既有的青藍主題色。
//  13. 新增 reSectionHeader(_:icon:color:trailing:) 多載，讓動態編號 Section（土地/建物
//      權狀，筆數可能為 0～N 筆）也能沿用同一份色條＋圖示＋標題排版，右側原本裸紅色
//      「－」刪除鈕原樣保留、位置與觸發邏輯完全未變動，僅改用共用 helper 排版。
//      土地權狀＝brown（doc.text.fill）／建物權狀＝indigo（building.2.fill）。
//  14. 「詳細」（新增權狀選單所在 Section）改用 reSectionHeader("詳細",
//      plus.rectangle.on.rectangle, .teal)。
//      純視覺層調整，Section 內欄位綁定、新增/刪除權狀、儲存等既有商業邏輯完全未變動；
//      featureToggleList 小型 popover（300×460）的 Section("理財")／Section("房屋資料")
//      維持系統原生列表樣式不變（純開關清單、非主要內容 Section，套用漸層標頭反而過重）。
// [2026-08 v5] 工具列「儲存／新增」按鈕補齊載入狀態：
//  15. save() 自帶 isSaving 忙碌守衛（disabled(isSaving)）避免快速連點造成重複房地產紀錄，
//      但按鈕本身在存檔期間毫無視覺提示。補上 ProgressView().scaleEffect(0.7).tint(.green)，
//      isSaving 為 true 時顯示於按鈕左側，對齊 AddIncomeView／AddExpenseView／
//      AddSavingsInsuranceView／AddVehicleView／AddStockView 儲存按鈕載入狀態規格
//      （tint 依各檔案儲存按鈕自身 foregroundStyle 配色，本檔案按鈕為綠色）。
//      至此全 App 帶 isSaving 忙碌守衛的 Add*View 儲存按鈕載入狀態已全數補齊。
//      純視覺層調整，save() 內部守衛判斷與房地產/貸款/已支出/變動支出/保險同步寫入
//      邏輯完全未變動。
//      （下次美化本檔案時，可轉往其他仍留有待辦的畫面）
// [v25.532] 上面 5、7、11 的試算區和英雄預覽卡已拿掉：用的是另一套房貸算法，跟卡片、看板對不起來。

struct AddRealEstateView: View {
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let editing: RealEstate?
    private let stableEstateId: UUID
    @State private var hasAutoSaved: Bool

    init(editing: RealEstate? = nil) {
        self.editing = editing
        self.stableEstateId = editing?.id ?? UUID()
        _hasAutoSaved = State(initialValue: editing != nil)
    }

    enum EditTab: String, CaseIterable {
        case finance = "理財"
        case house = "房屋資料"
    }
    @State private var editTab: EditTab = .finance

    // 編輯/新增項目 sheet 狀態
    @State private var editingExpense: Expense?
    @State private var addingMortgage = false
    @State private var addingPaid = false
    @State private var addingVariableCategory: RealEstateExpenseCategory?
    @State private var showVariableCategoryPicker = false
    /// [v25.530] 「＋變動支出 → 水電瓦斯」直接開水電繳費（同卡片頁），不再繞去記帳、存完跑到別區
    @State private var addingUtilityPayment = false

    private var currentEstate: RealEstate? {
        financeStore.realEstates.first(where: { $0.id == stableEstateId })
    }
    private var storeMortgageItems: [RealEstateMortgageItem] { currentEstate?.mortgageItems ?? [] }
    private var storePaidItems: [RealEstatePaidItem] { currentEstate?.paidItems ?? [] }
    private var storeVariableItems: [RealEstateVariableExpense] { currentEstate?.variableExpenses ?? [] }

    @State private var name = ""
    @State private var city = ""
    @State private var address = ""
    @State private var purchaseDate = Date()

    // 台灣縣市（6 直轄市 + 3 省轄市 + 13 縣）
    static let taiwanCities: [String] = [
        "臺北市", "新北市", "桃園市", "臺中市", "臺南市", "高雄市",
        "基隆市", "新竹市", "嘉義市",
        "新竹縣", "苗栗縣", "彰化縣", "南投縣", "雲林縣", "嘉義縣",
        "屏東縣", "宜蘭縣", "花蓮縣", "臺東縣",
        "澎湖縣", "金門縣", "連江縣"
    ]
    @State private var isSold = false
    @State private var soldDate = Date()
    @State private var purchasePriceText = ""
    @State private var currentValueText = ""
    @State private var monthlyRentalText = ""
    @State private var note = ""
    @State private var showError = false
    @State private var isSaving = false
    // [v25.532] 當初跟銀行借了多少（萬）；空的＝沒填，HouseFacts 用推算的。不預先填，填進去就變成「你填的」
    @State private var loanPrincipalText = ""
    // [v25.532] 成交價（萬）；空的＝沒填，售出損益和賣掉後的價值退回目前估值
    @State private var soldPriceText = ""
    // matchedGeometryEffect：Tab 切換器平滑滑動（對齊 RealEstateDetailView.tabPicker 規格）
    @Namespace private var tabNamespace

    // MARK: - 功能選別
    @State private var showRental = false
    @State private var showMortgage = false
    @State private var showPaid = false
    @State private var showVariable = false
    @State private var showLandDetail = false
    @State private var showFloor = false
    @State private var showUtilities = false
    @State private var showInsurance = false
    @State private var showAsset = false
    @State private var showFeaturePicker = false

    // MARK: - 人生模式欄位
    @State private var buildingType: BuildingType = .townhouse
    @State private var hasElevator = false
    @State private var elevatorItems: [ElevatorItemState] = []
    @State private var viewingPhotoURL: URL?
    // 防止同一筆保養記錄連續選兩張照片時新舊 Task 並行：後選的較快完成先把
    // photoFileName 指向它自己，先選的隨後完成又讀到已更新的值當「舊檔」誤刪，
    // 兩個 Task 互相刪對方剛存好的檔案（同型修復見 RealEstateDetailView.
    // ElevatorMaintenanceEditor.photoLoadTask）。依 item.id 分別記錄、取消前一個。
    @State private var elevatorPhotoLoadTasks: [UUID: Task<Void, Never>] = [:]
    // 上面的 Task 完成時只能靠這個世代編號判斷自己是否仍是「目前這一次選取」，
    // 不能靠清空 elevatorPhotoLoadTasks[itemId] 本身來判斷（Task 非 Equatable，
    // 且若無條件清空，會把後續、仍在執行中的新選取 Task 的登記一併清掉，
    // 導致下一次選取時 cancel() 變成 no-op、新舊 Task 並行互刪對方檔案）。
    @State private var elevatorPhotoLoadGeneration: [UUID: Int] = [:]
    // [v25.530] 換掉、刪掉的保養照片先不刪檔，按儲存才刪：按取消時房子資料還指著舊檔，先刪就救不回來。
    // 這次新選進來的照片也記著，按取消時刪掉，免得變成沒人用的孤兒檔。
    @State private var elevatorPhotosDropped: Set<String> = []
    @State private var elevatorPhotosAdded: Set<String> = []

    struct ElevatorItemState: Identifiable {
        let id: UUID
        var date: Date
        // [v25.530] 存整個照片陣列：以前只留第一張，存一次其餘照片就從資料裡掉了
        var photoFileNames: [String] = []
    }
    @State private var pingCountText = ""
    @State private var landOwner = ""
    @State private var ownerPickerSelection = ""
    @State private var landSituation = ""
    @State private var landNumber = ""
    @State private var landAreaText = ""
    @State private var landDeedItems: [LandDeedState] = []
    @State private var bldgDeedItems: [BuildingDeedState] = []

    struct LandDeedState: Identifiable {
        let id: UUID
        var situation: String
        var number: String
        var areaText: String
    }
    struct BuildingDeedState: Identifiable {
        let id: UUID
        var situation: String
        var number: String
        var address: String
        var hasCompletionDate: Bool
        var completionDate: Date
        var usage: String
        var annex: String
        var areaText: String
    }
    @State private var floorItems: [FloorItemState] = []

    struct FloorItemState: Identifiable {
        let id: UUID
        var floorNumber: String
        var functions: Set<FloorFunction>
        var areaText: String
    }
    @State private var waterMeterNumber = ""
    @State private var waterStation = ""
    @State private var waterCode = ""
    @State private var waterCheck = ""
    @State private var waterMeterOwner = ""
    @State private var electricityMeterNumber = ""
    @State private var electricityMeterOwner = ""
    @State private var gasMeterNumber = ""
    @State private var gasMeterOwner = ""
    @State private var gasUserNumber = ""
    @State private var extraMeters: [UtilityMeter] = []
    // [v25.530] 水電瓦斯「所有權人」目前是「從家人選」的那幾個（water／electricity／gas，額外的表用它的 id）。
    // 以前用「文字是不是某位家人」決定顯示選單還是輸入框，手動輸入打第一個字輸入框就不見了。
    @State private var ownerPickedFromList: Set<String> = []
    @State private var insuranceItems: [InsuranceItemState] = []
    @State private var assetItems: [AssetItemState] = []
    // [v25.530] 保險／附屬資產按減號時，連到的記帳支出先記在這裡，按儲存才刪；按取消就什麼都不刪
    @State private var pendingRemovedExpenseIds: Set<UUID> = []
    // [v25.530] 左滑刪貸款／房屋價金／變動支出：先記下來跳確認，確認後才刪
    @State private var pendingSwipeDeletion: SwipeDeletionRequest?

    struct SwipeDeletionRequest {
        enum Kind { case mortgage, paid, variable }
        let kind: Kind
        let itemIds: Set<UUID>
        let expenseIds: Set<UUID>
    }

    /// [v25.530] save() 同步保險／附屬資產的連結支出時先改副本，最後 expenses 只寫一次
    struct LinkedExpenseBatch {
        var expenses: [Expense]
        var changed = false
        /// 金額或日期變了、要重寫銀行扣款紀錄的支出
        var bankSyncIds = Set<UUID>()
    }

    struct InsuranceItemState: Identifiable {
        let id: UUID
        var policyNumber: String
        var amountText: String
        var linkedExpenseId: UUID?
        var amount: Double { Double(amountText) ?? 0 }
    }

    struct AssetItemState: Identifiable {
        let id: UUID
        var category: RealEstateExpenseCategory
        var name: String
        var brand: String
        var floorLocation: String
        var amountText: String
        var linkedExpenseId: UUID?
        var amount: Double { Double(amountText) ?? 0 }
    }

    // 貸款/已支出/變動支出項目改由 financeStore.realEstates[stableEstateId] 持有，
    // 透過 AddExpenseView 新增/編輯，不再使用本地 @State。

    var body: some View {
        NavigationStack {
            withEditorPresentations(editorForm)
        }
    }

    // [v25.530] body 拆成「表單本體」和「彈出視窗」兩段：v25.530 多了一個 sheet 和刪除確認框之後，
    // 整串十幾個修飾器擠在同一個運算式裡，Xcode Cloud 編譯時型別檢查逾時（AddRealEstateView.swift:337）。
    private var editorForm: some View {
        Form {
            // [v25.532] 拿掉頂端的英雄預覽卡和下面的試算區：它們用的是另一套房貸算法，跟卡片、看板對不起來
            infoSection

            // ── 自訂 Tab 切換器（matchedGeometryEffect Capsule Pill）──
            // 理財(紫) / 房屋資料(青藍)，Tab 切換 spring 平滑滑動
            Section {
                HStack(spacing: 0) {
                    ForEach(EditTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                                editTab = tab
                            }
                        } label: {
                            let isActive = editTab == tab
                            ZStack {
                                if isActive {
                                    Capsule()
                                        .fill(reTabGradient(tab))
                                        .matchedGeometryEffect(id: "reTabIndicator", in: tabNamespace)
                                }
                                HStack(spacing: 5) {
                                    Image(systemName: tab == .finance ? "chart.bar.fill" : "house.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(tab.rawValue)
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundStyle(isActive ? .white : Color.secondary)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color(.separator).opacity(0.20), lineWidth: 0.75))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if editTab == .finance {
                valueSection
                if showRental { rentalSection }
                if showMortgage { mortgageSection }
                if showPaid { paidSection }
                if showVariable { variableExpenseSection }

                Section(header: reSectionHeader("備註", icon: "text.bubble.fill", color: Color.secondary)) {
                    TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
                }
            } else {
                propertyDetailSection
                if hasElevator && buildingType == .townhouse { elevatorSection }
                if showLandDetail { landDetailSection }
                if showFloor { floorSection }
                if showUtilities { utilitiesSection }
                if showInsurance { insuranceSection }
                if showAsset { propertyAssetSection }
            }

            if showError {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text("請輸入物件名稱和購入價格")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.orange.opacity(0.25), lineWidth: 0.75)
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
        }
        .tint(.purple)
        .navigationTitle((editing != nil || hasAutoSaved) ? "編輯房地產" : "新增房地產")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("取消") { cancelAndRollback() } }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button { showFeaturePicker.toggle() } label: {
                        Image(systemName: "checklist")
                            .foregroundStyle(.blue)
                    }
                    .popover(isPresented: $showFeaturePicker, arrowEdge: .top) {
                        featureToggleList
                    }
                    // [美化] 存檔中顯示同色 ProgressView，對齊 AddIncomeView／AddExpenseView／
                    // AddSavingsInsuranceView／AddVehicleView／AddStockView 儲存按鈕載入狀態規格
                    if isSaving {
                        ProgressView().scaleEffect(0.7).tint(.green)
                    }
                    Button((editing != nil || hasAutoSaved) ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(isSaving)
                }
            }
        }
        .onAppear {
            loadEditing()
        }
    }

    // 再拆一次：每個 sheet 的 closure 都是單一運算式，會跟外面整串一起推型別，一串放太多一樣會逾時
    private func withEditorPresentations<Content: View>(_ content: Content) -> some View {
        withCategoryPresentations(withExpenseSheets(content))
    }

    private func withExpenseSheets<Content: View>(_ content: Content) -> some View {
        content
            .sheet(item: $viewingPhotoURL) { url in
                PhotoViewerSheet(url: url)
            }
            .sheet(item: $editingExpense) { exp in
                AddExpenseView(expenseType: exp.expenseType, editingExpense: exp)
            }
            .sheet(isPresented: $addingMortgage) {
                AddExpenseView(
                    expenseType: .fixed,
                    preset: AddExpensePreset(
                        fixedCategory: .loan,
                        loanSubCategory: .mortgage,
                        recurrence: .monthly,
                        linkedRealEstateId: stableEstateId,
                        mortgageLinkExisting: true
                    )
                )
            }
            .sheet(isPresented: $addingPaid) {
                AddExpenseView(
                    expenseType: .variable,
                    preset: AddExpensePreset(
                        variableCategory: .realEstate,
                        realEstateExpenseCategory: .housePayment,
                        linkedRealEstateId: stableEstateId,
                        assetLink: .realEstate,
                        realEstateLinkExisting: true
                    )
                )
            }
    }

    private func withCategoryPresentations<Content: View>(_ content: Content) -> some View {
        content
            .sheet(item: $addingVariableCategory) { cat in
                AddExpenseView(
                    expenseType: .variable,
                    preset: AddExpensePreset(
                        variableCategory: .realEstate,
                        realEstateExpenseCategory: cat,
                        linkedRealEstateId: stableEstateId,
                        assetLink: .realEstate,
                        realEstateLinkExisting: true
                    )
                )
            }
            .sheet(isPresented: $addingUtilityPayment) {
                UtilityPaymentEditor(estateId: stableEstateId, editing: nil)
            }
            .confirmationDialog("選擇變動支出類別", isPresented: $showVariableCategoryPicker, titleVisibility: .visible) {
                ForEach(RealEstateExpenseCategory.allCases.filter { $0 != .housePayment }) { cat in
                    Button(cat.rawValue) {
                        if cat == .utility { addingUtilityPayment = true } else { addingVariableCategory = cat }
                    }
                }
                Button("取消", role: .cancel) {}
            }
            .alert("刪除項目？", isPresented: swipeDeletionPresented, presenting: pendingSwipeDeletion) { request in
                Button("刪除", role: .destructive) { confirmSwipeDeletion(request) }
                Button("取消", role: .cancel) {}
            } message: { request in
                Text(swipeDeletionMessage(request))
            }
    }

    private var swipeDeletionPresented: Binding<Bool> {
        Binding(
            get: { pendingSwipeDeletion != nil },
            set: { if !$0 { pendingSwipeDeletion = nil } }
        )
    }

    // MARK: - 功能選別選單

    private var featureToggleList: some View {
        List {
            Section("理財") {
                Toggle(isOn: $showRental) { Label("租金收入", systemImage: "dollarsign.circle") }
                    .onChange(of: showRental) { _, v in saveStoredToggle("showRental", v) }
                Toggle(isOn: $showMortgage) { Label("貸款項目", systemImage: "building.columns") }
                    .onChange(of: showMortgage) { _, v in saveStoredToggle("showMortgage", v) }
                Toggle(isOn: $showPaid) { Label("已支出房屋金額", systemImage: "banknote") }
                    .onChange(of: showPaid) { _, v in saveStoredToggle("showPaid", v) }
                Toggle(isOn: $showVariable) { Label("變動支出", systemImage: "cart") }
                    .onChange(of: showVariable) { _, v in saveStoredToggle("showVariable", v) }
            }
            Section("房屋資料") {
                Toggle(isOn: $showLandDetail) { Label("詳細", systemImage: "map") }
                    .onChange(of: showLandDetail) { _, v in saveStoredToggle("showLandDetail", v) }
                Toggle(isOn: $showFloor) { Label("樓層資訊", systemImage: "building.2") }
                    .onChange(of: showFloor) { _, v in saveStoredToggle("showFloor", v) }
                Toggle(isOn: $showUtilities) { Label("水電瓦斯", systemImage: "bolt.fill") }
                    .onChange(of: showUtilities) { _, v in saveStoredToggle("showUtilities", v) }
                Toggle(isOn: $showInsurance) { Label("保險項目", systemImage: "shield.fill") }
                    .onChange(of: showInsurance) { _, v in saveStoredToggle("showInsurance", v) }
                Toggle(isOn: $showAsset) { Label("房屋附屬資產", systemImage: "sofa.fill") }
                    .onChange(of: showAsset) { _, v in saveStoredToggle("showAsset", v) }
            }
        }
        .listStyle(.insetGrouped)
        .frame(width: 300, height: 460)
        .presentationCompactAdaptation(.popover)
    }

    // MARK: - 功能切換持久化

    /// UserDefaults key prefix（依本筆房地產的 stableEstateId 區分）
    private func featureToggleKey(_ name: String) -> String {
        "realEstate.\(stableEstateId.uuidString).feature.\(name)"
    }

    /// 讀已儲存的切換值；無資料時回 nil（讓呼叫端 fallback 到資料推導）
    private func loadStoredToggle(_ name: String) -> Bool? {
        let key = featureToggleKey(name)
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return UserDefaults.standard.bool(forKey: key)
    }

    private func saveStoredToggle(_ name: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: featureToggleKey(name))
    }

    // MARK: - 物件資訊

    private var infoSection: some View {
        Section(header: reSectionHeader("物件資訊", icon: "house.fill", color: .purple)) {
            TextField("物件名稱", text: $name)

            Picker("縣市", selection: $city) {
                Text("請選擇").tag("")
                ForEach(Self.taiwanCities, id: \.self) { c in
                    Text(c).tag(c)
                }
            }

            TextField("地址（可多行）", text: $address, axis: .vertical)
                .lineLimit(2...5)

            DatePicker("購入日期", selection: $purchaseDate, displayedComponents: .date)
                .onChange(of: purchaseDate) { _, v in
                    // [v25.532] 售出日期的 in: purchaseDate... 只擋新選的，不會修正已選好的舊值；
                    // 購入日往後調晚過售出日，會存出「還沒買就賣掉」（同 AddVehicleView）
                    if soldDate < v { soldDate = v }
                }

            Toggle("已售出", isOn: $isSold)
            if isSold {
                DatePicker("售出日期", selection: $soldDate, in: purchaseDate..., displayedComponents: .date)
                soldPriceRow
            }
        }
    }

    /// [v25.532] 成交價：售出損益、賣掉之後的房子價值都看它，沒填才用目前估值
    private var soldPriceRow: some View {
        HStack {
            TextField("成交價（沒填用目前估值）", text: $soldPriceText)
                .keyboardType(.decimalPad)
            Text("萬元").foregroundStyle(.secondary)
        }
    }

    // MARK: - 價值

    private var pingCount: Double { Double(pingCountText) ?? 0 }

    private func perPingText(_ wanText: String) -> String {
        guard pingCount > 0, let wan = Double(wanText), wan > 0 else { return "" }
        let perPing = wan / pingCount
        return String(format: "%.1f 萬/坪", perPing)
    }

    private var valueSection: some View {
        Section {
            HStack {
                HStack {
                    TextField("購入價格", text: $purchasePriceText).keyboardType(.decimalPad)
                    Text("萬元").foregroundStyle(.secondary)
                }
                if pingCount > 0, let pp = perPingText(purchasePriceText) as String?, !pp.isEmpty {
                    Divider()
                    Text(pp).font(.caption).foregroundStyle(.tertiary)
                        .frame(minWidth: 80, alignment: .trailing)
                }
            }
            HStack {
                HStack {
                    TextField("目前估值", text: $currentValueText).keyboardType(.decimalPad)
                    Text("萬元").foregroundStyle(.secondary)
                }
                if pingCount > 0, let pp = perPingText(currentValueText) as String?, !pp.isEmpty {
                    Divider()
                    Text(pp).font(.caption).foregroundStyle(.tertiary)
                        .frame(minWidth: 80, alignment: .trailing)
                }
            }
        } header: {
            reSectionHeader("價值", icon: "tag.fill", color: .indigo)
        } footer: {
            valueFooter
        }
    }

    /// [v25.532] 估值多久沒更新一眼看得到（日期是進這頁之前那次存的）
    private var valueFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("以萬元為單位輸入，例如輸入 1500 代表 NT$15,000,000。")
            if let updated = editing?.valueUpdatedAt {
                Text("估值更新於 \(fmtDate(updated))")
            }
        }
    }

    // MARK: - 租金收入

    private var rentalSection: some View {
        Section(header: reSectionHeader("租金收入", icon: "dollarsign.circle.fill", color: .green)) {
            HStack {
                Text("NT$").foregroundStyle(.secondary)
                TextField("月租金收入", text: $monthlyRentalText).keyboardType(.decimalPad)
            }
        }
    }

    // MARK: - 貸款項目

    /// [v25.532] 期數、已繳、這個月房貸全讀 HouseFacts（跟卡片、看板同一套），這頁不再自己算
    private var houseFacts: HouseFacts? {
        currentEstate.map { HouseFacts.build($0, expense: expenseStore) }
    }

    private var mortgageSection: some View {
        let facts = houseFacts
        return Section {
            ForEach(storeMortgageItems) { m in
                mortgageRow(m, segment: facts?.segments.first(where: { $0.id == m.id }))
            }
            .onDelete(perform: deleteMortgageItems)

            loanPrincipalRow(facts)

            Button {
                guard ensureRealEstateSavedInStore() else { return }
                addingMortgage = true
            } label: {
                Label("新增貸款項目", systemImage: "plus.circle").foregroundStyle(.blue)
            }
        } header: {
            reSectionHeader("貸款項目", icon: "building.columns.fill", color: .blue)
        } footer: {
            Text(mortgageFooterText(facts))
        }
    }

    private func mortgageRow(_ m: RealEstateMortgageItem, segment seg: HouseFacts.Segment?) -> some View {
        // 每期金額以連到的記帳那筆為準（seg.perPeriod），沒對到段才用房貸項目自己的
        let perPeriod: Double = seg?.perPeriod ?? m.amount
        return Button {
            if let expId = m.linkedExpenseId,
               let exp = expenseStore.expenses.first(where: { $0.id == expId }) {
                editingExpense = exp
            }
        } label: {
            HStack(spacing: 12) {
                reIconCircle(icon: "building.columns.fill", color: .blue)
                VStack(alignment: .leading, spacing: 3) {
                    // [v25.520] 名稱放不下改跑馬燈（原本 lineLimit(1) 切成「…」）
                    MarqueeText(m.title.isEmpty ? "房貸" : m.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    if let seg = seg {
                        mortgageProgress(seg)
                    }
                }
                Spacer()
                Text(formatCurrency(perPeriod))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.22, green: 0.53, blue: 0.98))
                Image(systemName: "chevron.right")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 「已繳 x／y 期」膠囊＋已繳金額（已繳期數 × 每期金額）
    private func mortgageProgress(_ seg: HouseFacts.Segment) -> some View {
        let periodText: String = "\(seg.paidPeriods)/\(seg.countedPeriods) 期"
        let paidText: String = "已繳 " + formatCurrency(Double(seg.paidPeriods) * seg.perPeriod)
        return HStack(spacing: 5) {
            if seg.countedPeriods > 0 {
                Text(periodText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.blue.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.blue.opacity(0.22), lineWidth: 0.6))
            }
            Text(paidText)
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// [v25.532] 當初跟銀行借了多少：還欠多少本金從這個數算起
    private func loanPrincipalRow(_ facts: HouseFacts?) -> some View {
        let placeholder: String = loanPrincipalPlaceholder(facts)
        return HStack {
            Text("當初跟銀行借了多少")
            TextField(placeholder, text: $loanPrincipalText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            Text("萬元").foregroundStyle(.secondary)
        }
    }

    /// 沒填時 HouseFacts 會用哪個數，只寫在提示字裡（同一套順序：記帳的總貸款金額 → 購入價 − 自備款）。
    /// 用「假裝沒填」的同一間房子算一次，提示的數字就是存檔後真的會用的那個。
    /// 這頁每打一個字就重畫一次，build 不便宜：輸入框有字時看不到提示字就不算；
    /// 存著的本來就是沒填、購入價也沒改時，上面那份 facts 就是同一個結果，直接用。
    private func loanPrincipalPlaceholder(_ facts: HouseFacts?) -> String {
        let example = "例如 1944"
        guard loanPrincipalText.isEmpty, var re = currentEstate else { return example }
        let typedPrice: Double = (Double(purchasePriceText) ?? 0) * 10000
        let samePrice: Bool = typedPrice <= 0 || abs(typedPrice - re.purchasePrice) < 1
        let f: HouseFacts
        if let stored = facts, (re.loanPrincipal ?? 0) <= 0, samePrice {
            f = stored
        } else {
            re.loanPrincipal = nil
            if typedPrice > 0 { re.purchasePrice = typedPrice }
            f = HouseFacts.build(re, expense: expenseStore)
        }
        guard let p = f.principal, p > 0 else { return example }
        let wanText: String = Self.editableAmountText(p / 10000, decimals: 0)
        switch f.principalSource {
        case .ledger: return wanText + "（記帳的總貸款金額）"
        case .estimated: return wanText + "（購入價 − 自備款）"
        case .entered, .unknown: return example
        }
    }

    private func mortgageFooterText(_ facts: HouseFacts?) -> String {
        let principalNote = "沒填就用推算的；有填就照你填的算還欠多少本金。"
        guard !storeMortgageItems.isEmpty else {
            return "點擊「新增貸款項目」可建立多筆不同期數的貸款。" + principalNote
        }
        // 賣掉的房子 HouseFacts 停在賣出那天，monthlyMortgage 是賣出那個月的；不是這個月賣的，「這個月」就沒有房貸
        let monthly: Double
        if let f = facts, Calendar.current.isDate(f.asOf, equalTo: Date(), toGranularity: .month) {
            monthly = f.monthlyMortgage
        } else {
            monthly = 0
        }
        let monthText: String
        if monthly > 0 {
            let monthlyText: String = formatCurrency(monthly)
            monthText = "這個月房貸 \(monthlyText)，與記帳模式的固定支出連動。"
        } else {
            monthText = "這個月沒有要繳的房貸，與記帳模式的固定支出連動。"
        }
        return monthText + principalNote
    }

    // MARK: - 已支出房屋金額

    private var paidSection: some View {
        Section {
            ForEach(storePaidItems) { p in
                Button {
                    if let expId = p.linkedExpenseId,
                       let exp = expenseStore.expenses.first(where: { $0.id == expId }) {
                        editingExpense = exp
                    }
                } label: {
                    HStack(spacing: 12) {
                        reIconCircle(icon: "banknote.fill", color: .green)
                        VStack(alignment: .leading, spacing: 3) {
                            MarqueeText(p.title.isEmpty ? "房屋價金" : p.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(fmtDate(p.date))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color(.separator).opacity(0.25), lineWidth: 0.6))
                        }
                        Spacer()
                        Text(formatCurrency(p.amount))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: deletePaidItems)

            Button {
                guard ensureRealEstateSavedInStore() else { return }
                addingPaid = true
            } label: {
                Label("新增已支出項目", systemImage: "plus.circle").foregroundStyle(.green)
            }
        } header: {
            reSectionHeader("已支出房屋金額", icon: "banknote.fill", color: .green)
        } footer: {
            if !storePaidItems.isEmpty {
                let total = storePaidItems.reduce(0.0) { $0 + $1.amount }
                Text("已支出合計 \(formatCurrency(total))，與記帳模式的變動支出連動。")
            } else {
                Text("記錄頭期款、簽約金、工程款等已支付的房屋相關金額。")
            }
        }
    }

    private static let fmtDateFormatter: DateFormatter = {
        // [v25.530] 固定西元曆：手機設成民國曆時才不會印出「0115/10/10」
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "yyyy/M/d"
        return f
    }()

    private func fmtDate(_ d: Date) -> String {
        Self.fmtDateFormatter.string(from: d)
    }

    // MARK: - 變動支出

    private var variableExpenseSection: some View {
        Section {
            ForEach(storeVariableItems) { ve in
                Button {
                    if let expId = ve.linkedExpenseId,
                       let exp = expenseStore.expenses.first(where: { $0.id == expId }) {
                        editingExpense = exp
                    }
                } label: {
                    HStack(spacing: 12) {
                        reIconCircle(icon: ve.category.icon, color: .orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ve.category.rawValue)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 7).padding(.vertical, 2.5)
                                .background(Color.orange.opacity(0.12))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.orange.opacity(0.22), lineWidth: 0.6))
                            HStack(spacing: 5) {
                                if !ve.name.isEmpty {
                                    MarqueeText(ve.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                }
                                Text(fmtDate(ve.date))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(formatCurrency(ve.amount))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.86, green: 0.36, blue: 0.06))
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: deleteVariableItems)

            Button {
                guard ensureRealEstateSavedInStore() else { return }
                showVariableCategoryPicker = true
            } label: {
                Label("新增變動支出", systemImage: "plus.circle").foregroundStyle(.orange)
            }
        } header: {
            reSectionHeader("變動支出", icon: "cart.fill", color: .orange)
        } footer: {
            if !storeVariableItems.isEmpty {
                let total = storeVariableItems.reduce(0.0) { $0 + $1.amount }
                Text("變動支出合計 \(formatCurrency(total))，與記帳模式的變動支出連動。")
            } else {
                Text("裝修、維修、家具、清潔等一次性支出。")
            }
        }
    }

    // MARK: - 房屋資料（人生）

    private var ownerCandidates: [String] {
        var names: [String] = []
        let myName = lifeStore.profile.chineseName
        if !myName.isEmpty { names.append(myName) }
        for member in lifeStore.familyMembers where !member.chineseName.isEmpty {
            names.append(member.chineseName)
        }
        return names
    }

    private var propertyDetailSection: some View {
        Section(header: reSectionHeader("房屋資料", icon: "house.fill", color: .cyan)) {
            Picker("建物類型", selection: $buildingType) {
                ForEach(BuildingType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }

            if buildingType == .townhouse {
                Toggle("有電梯", isOn: $hasElevator)
            }

            HStack {
                TextField("坪數", text: $pingCountText).keyboardType(.decimalPad)
                Text("坪").foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("所有權人").font(.caption).foregroundStyle(.secondary)
                if !ownerCandidates.isEmpty {
                    Picker("選擇人員", selection: $ownerPickerSelection) {
                        Text("手動輸入").tag("")
                        ForEach(ownerCandidates, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .onChange(of: ownerPickerSelection) { _, newValue in
                        if !newValue.isEmpty { landOwner = newValue }
                    }
                }
                if ownerPickerSelection.isEmpty {
                    TextField("手動輸入所有權人", text: $landOwner)
                }
            }
        }
    }

    @ViewBuilder
    private var landDetailSection: some View {
        ForEach($landDeedItems) { $item in
            Section {
                TextField("坐落", text: $item.situation)
                TextField("地號", text: $item.number)
                HStack {
                    TextField("面積", text: $item.areaText).keyboardType(.decimalPad)
                    Text("㎡").foregroundStyle(.secondary)
                }
            } header: {
                reSectionHeader(
                    "土地權狀 \((landDeedItems.firstIndex(where: { $0.id == item.id }) ?? 0) + 1)",
                    icon: "doc.text.fill", color: .brown
                ) {
                    Button { landDeedItems.removeAll { $0.id == item.id } } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                    }.buttonStyle(.plain)
                }
            }
        }

        ForEach($bldgDeedItems) { $item in
            Section {
                TextField("坐落", text: $item.situation)
                TextField("建號", text: $item.number)
                TextField("門牌", text: $item.address)
                Toggle("填入完工日", isOn: $item.hasCompletionDate)
                if item.hasCompletionDate {
                    DatePicker("完工日", selection: $item.completionDate, displayedComponents: .date)
                }
                TextField("用途", text: $item.usage)
                TextField("附屬建物", text: $item.annex)
                HStack {
                    TextField("面積", text: $item.areaText).keyboardType(.decimalPad)
                    Text("㎡").foregroundStyle(.secondary)
                }
            } header: {
                reSectionHeader(
                    "建物權狀 \((bldgDeedItems.firstIndex(where: { $0.id == item.id }) ?? 0) + 1)",
                    icon: "building.2.fill", color: .indigo
                ) {
                    Button { bldgDeedItems.removeAll { $0.id == item.id } } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                    }.buttonStyle(.plain)
                }
            }
        }

        Section(header: reSectionHeader("詳細", icon: "plus.rectangle.on.rectangle", color: .teal)) {
            Menu {
                Button {
                    landDeedItems.append(LandDeedState(id: UUID(), situation: "", number: "", areaText: ""))
                } label: { Label("土地權狀", systemImage: "doc.text") }
                Button {
                    bldgDeedItems.append(BuildingDeedState(
                        id: UUID(), situation: "", number: "", address: "",
                        hasCompletionDate: false, completionDate: Date(),
                        usage: "", annex: "", areaText: ""
                    ))
                } label: { Label("建物權狀", systemImage: "building.2") }
            } label: {
                Label("新增權狀", systemImage: "plus.circle").foregroundStyle(.green)
            }
        }
    }

    // MARK: - 電梯資料

    private var elevatorSection: some View {
        Section {
            ForEach($elevatorItems) { $item in
                HStack {
                    Text("保養 \((elevatorItems.firstIndex(where: { $0.id == item.id }) ?? 0) + 1)")
                        .font(.subheadline.weight(.medium))
                        .frame(width: 56, alignment: .leading)

                    DatePicker("", selection: $item.date, displayedComponents: .date)
                        .labelsHidden()

                    Spacer()

                    if let photoFileName = item.photoFileNames.first {
                        Button {
                            let url = ElevatorMaintenance.photosDirectory
                                .appendingPathComponent(photoFileName)
                            viewingPhotoURL = url
                        } label: {
                            Image(systemName: "photo.fill")
                                .font(.title3).foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }

                    PhotosPicker(selection: Binding(
                        get: { nil },
                        set: { newItem in
                            guard let newItem else { return }
                            let itemId = item.id
                            elevatorPhotoLoadTasks[itemId]?.cancel()
                            let generation = (elevatorPhotoLoadGeneration[itemId] ?? 0) + 1
                            elevatorPhotoLoadGeneration[itemId] = generation
                            elevatorPhotoLoadTasks[itemId] = Task {
                                if let data = try? await newItem.loadTransferable(type: Data.self) {
                                    guard !Task.isCancelled else { return }
                                    // 檔名用全新 UUID（而非沿用編輯中記錄不變的 item.id），避免同路徑覆寫
                                    // 造成 ThumbnailCache（全域 NSCache，依 url.path 為 key）換照片後
                                    // 跨畫面持續顯示舊縮圖，對齊 RealEstateDetailView.ElevatorMaintenanceEditor
                                    // 同型修復。
                                    // 必須先寫入新照片、確認成功後才刪舊照片：若先刪舊檔、寫入新檔又因
                                    // 空間不足等原因失敗（savePhoto 回傳 nil），會在使用者毫無提示下
                                    // 永久遺失原本的照片。
                                    let fileName = ElevatorMaintenance.savePhoto(data, id: UUID())
                                    guard let fileName else { return }
                                    if let idx = elevatorItems.firstIndex(where: { $0.id == itemId }) {
                                        // [v25.530] 這裡只能換一張：只換第一張，其餘照片原樣留著。
                                        // 舊檔先不刪，記進 elevatorPhotosDropped，按儲存才刪（取消時房子還指著它）。
                                        elevatorPhotosAdded.insert(fileName)
                                        if let oldName = elevatorItems[idx].photoFileNames.first {
                                            elevatorPhotosDropped.insert(oldName)
                                            elevatorItems[idx].photoFileNames[0] = fileName
                                        } else {
                                            elevatorItems[idx].photoFileNames = [fileName]
                                        }
                                    } else {
                                        // item 已在等待期間被刪除，剛存好的新檔案要一併清掉，避免孤兒檔案
                                        ElevatorMaintenance.deletePhoto(fileName)
                                    }
                                }
                                // 只有仍是目前這一代（沒被更新的選取取代）才清空登記，避免清掉
                                // 後續、仍在執行中的新選取 Task 的登記，導致下一次選取時
                                // cancel() 變成 no-op、新舊 Task 並行互刪對方剛存好的檔案。
                                if elevatorPhotoLoadGeneration[itemId] == generation {
                                    elevatorPhotoLoadTasks[itemId] = nil
                                }
                            }
                        }
                    ), matching: .images) {
                        Image(systemName: item.photoFileNames.isEmpty ? "photo.badge.plus" : "arrow.triangle.2.circlepath.camera")
                            .font(.title3).foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        // 刪除這筆記錄前先取消尚未完成的照片載入 Task，避免它稍後才完成、
                        // 把照片存進磁碟卻已找不到對應的 item，變成永久孤兒檔案。
                        elevatorPhotoLoadTasks[item.id]?.cancel()
                        elevatorPhotoLoadTasks[item.id] = nil
                        // [v25.530] 照片檔等按儲存才刪（按取消時房子資料還指著它）
                        elevatorPhotosDropped.formUnion(item.photoFileNames)
                        elevatorItems.removeAll { $0.id == item.id }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                elevatorItems.append(ElevatorItemState(id: UUID(), date: Date()))
            } label: {
                Label("新增保養記錄", systemImage: "plus.circle").foregroundStyle(.green)
            }
        } header: {
            Text("電梯資料")
        }
    }

    private var floorSection: some View {
        Section {
            HStack {
                Text("樓層數")
                Spacer()
                Text("\(floorItems.count) 層").foregroundStyle(.secondary)
            }

            ForEach($floorItems) { $item in
                VStack(spacing: 8) {
                    HStack {
                        TextField("樓層（如 B1、1F）", text: $item.floorNumber)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                        Divider()
                        HStack {
                            TextField("面積", text: $item.areaText)
                                .keyboardType(.decimalPad)
                                .frame(width: 60)
                            Text("㎡").foregroundStyle(.secondary).font(.caption)
                        }
                        Button(role: .destructive) {
                            floorItems.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }.buttonStyle(.plain)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                        ForEach(FloorFunction.allCases) { fn in
                            let isOn = item.functions.contains(fn)
                            Button {
                                if isOn { $item.wrappedValue.functions.remove(fn) }
                                else { $item.wrappedValue.functions.insert(fn) }
                            } label: {
                                Text(fn.rawValue)
                                    .font(.caption)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .frame(maxWidth: .infinity)
                                    .background(isOn ? Color.green.opacity(0.2) : Color(.tertiarySystemFill))
                                    .foregroundStyle(isOn ? .green : .secondary)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Button {
                floorItems.append(FloorItemState(id: UUID(), floorNumber: "", functions: [], areaText: ""))
            } label: {
                Label("新增樓層", systemImage: "plus.circle").foregroundStyle(.green)
            }
        } header: {
            Text("樓層資訊")
        }
    }

    // MARK: - 水電瓦斯（人生）

    @ViewBuilder
    private var utilitiesSection: some View {
        Section {
            HStack {
                Image(systemName: "drop.fill").foregroundStyle(.blue).frame(width: 24)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        VStack(spacing: 2) {
                            TextField("站所", text: $waterStation)
                                .multilineTextAlignment(.center)
                            Text("站所").font(.system(size: 9)).foregroundStyle(.tertiary)
                        }
                        .frame(width: 44)
                        Text("-").foregroundStyle(.secondary)
                        VStack(spacing: 2) {
                            TextField("編號", text: $waterCode)
                                .multilineTextAlignment(.center)
                            Text("編號").font(.system(size: 9)).foregroundStyle(.tertiary)
                        }
                        Text("-").foregroundStyle(.secondary)
                        VStack(spacing: 2) {
                            TextField("檢", text: $waterCheck)
                                .multilineTextAlignment(.center)
                            Text("檢號").font(.system(size: 9)).foregroundStyle(.tertiary)
                        }
                        .frame(width: 32)
                    }
                    ownerPicker(selection: $waterMeterOwner, placeholder: "所有權人", key: "water")
                }
            }
            HStack {
                Image(systemName: "bolt.fill").foregroundStyle(.yellow).frame(width: 24)
                VStack(alignment: .leading, spacing: 6) {
                    TextField("電號", text: $electricityMeterNumber)
                    ownerPicker(selection: $electricityMeterOwner, placeholder: "所有權人", key: "electricity")
                }
            }
            HStack {
                Image(systemName: "flame.fill").foregroundStyle(.orange).frame(width: 24)
                VStack(alignment: .leading, spacing: 6) {
                    TextField("用戶編號", text: $gasUserNumber)
                    TextField("表號", text: $gasMeterNumber)
                    ownerPicker(selection: $gasMeterOwner, placeholder: "所有權人", key: "gas")
                }
            }
        } header: {
            Text("水電瓦斯（主表）")
        } footer: {
            Text("以上為主表。如有第二、第三個水/電/瓦斯表（例如客廳一個電表、廚房一個電表），請在下方「額外的表」新增。")
        }

        Section {
            ForEach($extraMeters) { $meter in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Picker("類型", selection: $meter.type) {
                            ForEach(UtilityType.allCases) { t in
                                Label(t.rawValue, systemImage: t.icon).tag(t)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        Spacer()
                        Button(role: .destructive) {
                            extraMeters.removeAll { $0.id == meter.id }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    TextField("名稱（例：客廳、廚房、二樓）", text: $meter.label)
                    if meter.type == .gas {
                        TextField("用戶編號", text: $meter.userNumber)
                    }
                    TextField(meterNumberLabel(for: meter.type), text: $meter.meterNumber)
                    ownerPicker(selection: $meter.owner, placeholder: "所有權人", key: meter.id.uuidString)
                }
                .padding(.vertical, 4)
            }
            Button {
                extraMeters.append(UtilityMeter(type: .electricity))
            } label: {
                Label("新增表（多個水／電／瓦斯）", systemImage: "plus.circle")
                    .foregroundStyle(.green)
            }
        } header: {
            Text("額外的表")
        }
    }

    private func meterNumberLabel(for type: UtilityType) -> String {
        switch type {
        case .water: return "水號"
        case .electricity: return "電號"
        case .gas: return "表號"
        }
    }

    private var combinedWaterNumber: String {
        let parts = [waterStation, waterCode, waterCheck]
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.allSatisfy({ $0.isEmpty }) { return "" }
        return parts.joined(separator: "-")
    }

    private func ownerPicker(selection: Binding<String>, placeholder: String, key: String) -> some View {
        // [v25.530] 選單只管「選家人／手動輸入」這個模式（ownerPickedFromList），不再直接綁文字，
        // 手動輸入打字時不會因為文字變了就切回選單。
        let pickedFromList = ownerPickedFromList.contains(key)
        let pickerSelection = Binding<String>(
            get: { ownerPickedFromList.contains(key) ? selection.wrappedValue : "" },
            set: { newValue in
                if newValue.isEmpty {
                    // 從某位家人切回手動輸入：照舊清空，讓你重新打
                    if ownerPickedFromList.contains(key) {
                        ownerPickedFromList.remove(key)
                        selection.wrappedValue = ""
                    }
                } else {
                    ownerPickedFromList.insert(key)
                    selection.wrappedValue = newValue
                }
            }
        )
        return Group {
            if ownerCandidates.isEmpty {
                TextField(placeholder, text: selection)
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Picker(placeholder, selection: pickerSelection) {
                    Text("手動輸入").tag("")
                    ForEach(ownerCandidates, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .font(.subheadline)
                if !pickedFromList {
                    TextField(placeholder, text: selection)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 保險項目（人生）

    private var insuranceSection: some View {
        Section {
            ForEach($insuranceItems) { $item in
                VStack(spacing: 10) {
                    if insuranceItems.first?.id != item.id { Divider() }

                    HStack {
                        Text("保險 \((insuranceItems.firstIndex(where: { $0.id == item.id }) ?? 0) + 1)")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Button(role: .destructive) {
                            // [v25.530] 先只從表單拿掉；連到的記帳支出記進待刪，按儲存才刪（按取消就救得回來）
                            if let linkedId = item.linkedExpenseId {
                                pendingRemovedExpenseIds.insert(linkedId)
                            }
                            insuranceItems.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }.buttonStyle(.plain)
                    }

                    TextField("火災地震險號", text: $item.policyNumber)

                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("價格", text: $item.amountText)
                            .keyboardType(.decimalPad)
                    }
                }
            }

            Button {
                insuranceItems.append(InsuranceItemState(
                    id: UUID(), policyNumber: "", amountText: ""
                ))
            } label: {
                Label("新增保險項目", systemImage: "plus.circle").foregroundStyle(.green)
            }
        } header: {
            Text("保險項目")
        } footer: {
            Text("有填入價格的保險項目將自動列入變動支出。")
        }
    }

    // MARK: - 房屋附屬資產（人生）

    private var propertyAssetSection: some View {
        Section {
            ForEach($assetItems) { $item in
                VStack(spacing: 10) {
                    if assetItems.first?.id != item.id { Divider() }

                    HStack {
                        Text("資產 \((assetItems.firstIndex(where: { $0.id == item.id }) ?? 0) + 1)")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Button(role: .destructive) {
                            // [v25.530] 同保險：先只從表單拿掉，連到的記帳支出按儲存才刪
                            if let linkedId = item.linkedExpenseId {
                                pendingRemovedExpenseIds.insert(linkedId)
                            }
                            assetItems.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }.buttonStyle(.plain)
                    }

                    Picker("類別", selection: $item.category) {
                        ForEach(RealEstateExpenseCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }

                    TextField("名稱", text: $item.name)
                    TextField("廠牌", text: $item.brand)
                    TextField("位置樓層", text: $item.floorLocation)

                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("價格", text: $item.amountText)
                            .keyboardType(.decimalPad)
                    }
                }
            }

            Button {
                assetItems.append(AssetItemState(
                    id: UUID(), category: .furniture, name: "", brand: "",
                    floorLocation: "", amountText: ""
                ))
            } label: {
                Label("新增附屬資產", systemImage: "plus.circle").foregroundStyle(.green)
            }
        } header: {
            Text("房屋附屬資產")
        } footer: {
            Text("有填入價格的附屬資產將自動列入變動支出。")
        }
    }

    // MARK: - 儲存

    private func save() {
        guard !isSaving else { return }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              let priceWan = Double(purchasePriceText), priceWan > 0 else {
            showError = true; return
        }
        isSaving = true

        let price = priceWan * 10000
        let currentVal = (Double(currentValueText) ?? priceWan) * 10000
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        let reId = stableEstateId
        // [v25.532] 借款本金、成交價：空的或 ≤ 0 存 nil（＝沒填，用推算的／目前估值）
        let enteredPrincipal: Double? = Self.positiveWan(loanPrincipalText)
        let enteredSoldPrice: Double? = isSold ? Self.positiveWan(soldPriceText) : nil
        // [v25.532] 估值有改才蓋今天。跟進這頁時的原始資料（editing）比，不跟 currentEstate 比：
        // 新增流程按「新增貸款項目」會先自動存一次，跟它比就永遠是「沒改」。
        // 原本就沒估值、輸入框也還是空的，存檔時退回購入價不算改。
        let valueStamp: Date?
        if let before = editing {
            let stillBlank = before.currentValue <= 0 && Double(currentValueText) == nil
            let valueChanged = !stillBlank && abs(currentVal - before.currentValue) >= 1
            valueStamp = valueChanged ? Date() : currentEstate?.valueUpdatedAt
        } else {
            valueStamp = Double(currentValueText) != nil ? Date() : currentEstate?.valueUpdatedAt
        }

        // [v25.530] 減號拿掉的、價格清空的保險／附屬資產，連到的記帳支出（含銀行扣款）到按儲存這裡才一起刪。
        // 還有項目連著的 id 不刪。
        var keptLinkedIds = Set<UUID>()
        var expenseIdsToRemove = pendingRemovedExpenseIds
        for item in insuranceItems {
            guard let id = item.linkedExpenseId else { continue }
            if item.amount > 0 { keptLinkedIds.insert(id) } else { expenseIdsToRemove.insert(id) }
        }
        for item in assetItems {
            guard let id = item.linkedExpenseId else { continue }
            if item.amount > 0 { keptLinkedIds.insert(id) } else { expenseIdsToRemove.insert(id) }
        }
        expenseIdsToRemove.subtract(keptLinkedIds)
        RealEstateDeletion.removeExpenses(expenseIdsToRemove, expenseStore: expenseStore, lifeStore: lifeStore)

        // 貸款/已支出/變動支出由 AddExpenseView 直接寫入 financeStore，這裡保留 store 內既有資料
        let syncedMortgages: [RealEstateMortgageItem] = currentEstate?.mortgageItems ?? []
        // [v25.530] 剛刪掉的支出若也被舊版記帳重複記在房屋價金／變動支出裡，一併拿掉，免得留下指向不存在支出的項目（金額還照算進合計）
        let syncedPaids: [RealEstatePaidItem] = (currentEstate?.paidItems ?? []).filter { p in
            guard let id = p.linkedExpenseId else { return true }
            return !expenseIdsToRemove.contains(id)
        }
        let syncedVariable: [RealEstateVariableExpense] = (currentEstate?.variableExpenses ?? []).filter { ve in
            guard let id = ve.linkedExpenseId else { return true }
            return !expenseIdsToRemove.contains(id)
        }
        // [v25.530] 水電繳費有自己的收據照片，不刪，只解除指向已刪支出的連結
        let existingUtilityPayments: [UtilityPayment] = (currentEstate?.utilityPayments ?? []).map { (payment: UtilityPayment) -> UtilityPayment in
            var up = payment
            if let id = up.linkedExpenseId, expenseIdsToRemove.contains(id) { up.linkedExpenseId = nil }
            return up
        }
        // 房屋資料集錦由詳細頁 RenovationPhotoEditor 直接寫入，這裡保留既有資料避免被清空
        let existingRenovationPhotos: [RenovationPhoto] = currentEstate?.renovationPhotos ?? []
        let existingDocuments: [RealEstateDocument] = currentEstate?.documents ?? []

        // [v25.530] 保險、附屬資產連到的記帳支出：還在就只改跟著項目變的欄位，不再整筆重建
        // （以前每存一次就把日期蓋成購入日、標題重產、備註清空）；找不到了才新建一筆。
        // 「名稱／日期改了沒」跟進編輯頁時的原始項目（editing）比。
        var batch = LinkedExpenseBatch(expenses: expenseStore.expenses)
        let originalName = editing?.name ?? trimmedName
        let purchaseDayChanged = editing.map { !Calendar.current.isDate($0.purchaseDate, inSameDayAs: purchaseDate) } ?? false

        var syncedInsurance: [RealEstateInsuranceItem] = []
        for item in insuranceItems {
            if item.amount > 0 {
                let before = editing?.insuranceItems.first(where: { $0.id == item.id })
                let expId = syncLinkedExpense(
                    linkedId: item.linkedExpenseId,
                    amount: item.amount,
                    title: Self.insuranceExpenseTitle(trimmedName, item.policyNumber),
                    oldAutoTitle: before.map { Self.insuranceExpenseTitle(originalName, $0.policyNumber) },
                    nameChanged: before.map { $0.policyNumber != item.policyNumber } ?? false,
                    category: .insurance,
                    categoryChanged: false,
                    reId: reId,
                    purchaseDayChanged: purchaseDayChanged,
                    batch: &batch
                )
                syncedInsurance.append(RealEstateInsuranceItem(
                    id: item.id, policyNumber: item.policyNumber,
                    amount: item.amount, linkedExpenseId: expId
                ))
            } else {
                // 價格清空：連到的支出已在上面一起刪掉
                syncedInsurance.append(RealEstateInsuranceItem(
                    id: item.id, policyNumber: item.policyNumber,
                    amount: 0, linkedExpenseId: nil
                ))
            }
        }

        var syncedAssets: [RealEstatePropertyAsset] = []
        for item in assetItems {
            if item.amount > 0 {
                let before = editing?.propertyAssets.first(where: { $0.id == item.id })
                let label = Self.assetExpenseLabel(item.name, item.category)
                let oldLabel: String? = before.map { Self.assetExpenseLabel($0.name, $0.category) }
                let expId = syncLinkedExpense(
                    linkedId: item.linkedExpenseId,
                    amount: item.amount,
                    title: "\(trimmedName) - \(label)",
                    oldAutoTitle: oldLabel.map { "\(originalName) - \($0)" },
                    nameChanged: oldLabel.map { $0 != label } ?? false,
                    category: item.category,
                    categoryChanged: before.map { $0.category != item.category } ?? false,
                    reId: reId,
                    purchaseDayChanged: purchaseDayChanged,
                    batch: &batch
                )
                syncedAssets.append(RealEstatePropertyAsset(
                    id: item.id, category: item.category, name: item.name,
                    brand: item.brand, floorLocation: item.floorLocation,
                    amount: item.amount, linkedExpenseId: expId
                ))
            } else {
                syncedAssets.append(RealEstatePropertyAsset(
                    id: item.id, category: item.category, name: item.name,
                    brand: item.brand, floorLocation: item.floorLocation,
                    amount: 0, linkedExpenseId: nil
                ))
            }
        }
        // [v25.532] 標成已售出：連到的房貸固定支出停在成交日，記帳才不會賣掉之後還每月扣；
        // 取消已售出：把「因為賣房停的」還原（只有原本是已售出、這次取消才還原，免得動到你在記帳自己停的）。
        // 跟上面一起改在 batch 上，下面一次寫回。
        let wasSold = editing?.soldDate != nil
        if let estate = currentEstate, isSold || wasSold,
           RealEstateSale.syncMortgageStops(of: estate, soldDate: isSold ? soldDate : nil, in: &batch.expenses) {
            batch.changed = true
        }
        if batch.changed { expenseStore.expenses = batch.expenses }
        syncBankWithdrawals(for: batch.bankSyncIds, in: batch.expenses)

        // 售出損益同步
        var saleExpId = editing?.saleLinkedExpenseId
        var saleIncId = editing?.saleLinkedIncomeId
        if isSold {
            // [v25.532] 有填成交價就用成交價算賺賠，沒填才用目前估值
            let salePrice: Double = enteredSoldPrice ?? currentVal
            let pl = salePrice - price
            if pl >= 0 {
                saleIncId = syncSaleIncome(reId: reId, name: trimmedName, profit: pl, date: soldDate, existingId: saleIncId)
                // 改用 expenseStore.delete(_:) 清除連結支出，確保附加照片一併移除，避免孤兒照片
                if let eid = saleExpId, let exp = expenseStore.expenses.first(where: { $0.id == eid }) {
                    expenseStore.delete(exp)
                }
                saleExpId = nil
            } else {
                saleExpId = syncSaleExpense(reId: reId, name: trimmedName, loss: abs(pl), date: soldDate, existingId: saleExpId)
                if let iid = saleIncId { expenseStore.incomes.removeAll { $0.id == iid }; saleIncId = nil }
            }
        } else {
            if let eid = saleExpId, let exp = expenseStore.expenses.first(where: { $0.id == eid }) {
                expenseStore.delete(exp)
            }
            saleExpId = nil
            if let iid = saleIncId { expenseStore.incomes.removeAll { $0.id == iid }; saleIncId = nil }
        }

        // 建物類型改為非透天厝、或關閉「有電梯」開關時，電梯保養記錄會整批不再寫入，
        // 比照上方逐筆刪除鈕（elevatorPhotoLoadTasks 刪除按鈕）做法，一併刪除磁碟上的
        // 保養照片，避免存檔後這些照片變成沒有任何欄位引用得到的孤兒檔案。
        // [v25.530] 換掉／刪掉的保養照片也是到這裡才刪；最後還存在房子裡的照片一張都不刪。
        let elevatorSectionKept = buildingType == .townhouse && hasElevator
        let keptElevatorPhotos: Set<String> = elevatorSectionKept
            ? Set(elevatorItems.flatMap { $0.photoFileNames })
            : []
        let elevatorPhotoCandidates = elevatorPhotosDropped.union(elevatorItems.flatMap { $0.photoFileNames })
        for fn in elevatorPhotoCandidates.subtracting(keptElevatorPhotos) {
            ElevatorMaintenance.deletePhoto(fn)
        }

        // [v25.530] 樓層要從 store 裡這間房子的最新資料改起：物品樹（items）只在卡片頁編輯、這頁沒有，
        // 以前直接 new 一個 FloorInfo，存一次整棵物品樹就不見了。新加的樓層才是空的。
        let storeFloors: [FloorInfo] = currentEstate?.floors ?? []
        let syncedFloors: [FloorInfo] = floorItems.map { item -> FloorInfo in
            var info = storeFloors.first(where: { $0.id == item.id }) ?? FloorInfo(id: item.id)
            // [v25.532] 去掉前後空白：「 3F」排序、街景解析才認得
            info.floorNumber = item.floorNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            // 功能沒動就保留原本順序（Set 轉陣列順序不固定）
            if Set(info.functions) != item.functions {
                info.functions = FloorFunction.allCases.filter { item.functions.contains($0) }
            }
            info.area = Double(item.areaText) ?? 0
            return info
        }

        // [v25.530] 水號三格都沒動就原樣存回（不論原本幾段），動了才用「站所-編號-檢號」重組
        let loadedWaterParts: [String] = Self.splitWaterNumber(waterMeterNumber)
        let waterUntouched: Bool = loadedWaterParts == [waterStation, waterCode, waterCheck]
        let savedWaterNumber: String = waterUntouched ? waterMeterNumber : combinedWaterNumber

        var re = RealEstate(
            id: reId, name: trimmedName,
            city: city,
            address: address.trimmingCharacters(in: .whitespacesAndNewlines),
            purchaseDate: purchaseDate,
            soldDate: isSold ? soldDate : nil,
            purchasePrice: price, currentValue: currentVal,
            monthlyRental: Double(monthlyRentalText) ?? 0,
            mortgageItems: syncedMortgages,
            paidItems: syncedPaids,
            variableExpenses: syncedVariable,
            saleLinkedExpenseId: saleExpId,
            saleLinkedIncomeId: saleIncId,
            note: trimmedNote,
            buildingType: buildingType,
            hasElevator: elevatorSectionKept,
            elevatorMaintenances: elevatorSectionKept
                ? elevatorItems.map { ElevatorMaintenance(id: $0.id, date: $0.date, photoFileNames: $0.photoFileNames) }
                : [],
            pingCount: Double(pingCountText) ?? 0,
            landOwner: landOwner.trimmingCharacters(in: .whitespaces),
            landSituation: landSituation.trimmingCharacters(in: .whitespaces),
            landNumber: landNumber.trimmingCharacters(in: .whitespaces),
            landArea: Double(landAreaText) ?? 0,
            landDeeds: landDeedItems.map { LandDeed(id: $0.id, situation: $0.situation.trimmingCharacters(in: .whitespaces), number: $0.number.trimmingCharacters(in: .whitespaces), area: Double($0.areaText) ?? 0) },
            buildingDeeds: bldgDeedItems.map { BuildingDeed(id: $0.id, situation: $0.situation.trimmingCharacters(in: .whitespaces), number: $0.number.trimmingCharacters(in: .whitespaces), address: $0.address.trimmingCharacters(in: .whitespaces), completionDate: $0.hasCompletionDate ? $0.completionDate : nil, usage: $0.usage.trimmingCharacters(in: .whitespaces), annex: $0.annex.trimmingCharacters(in: .whitespaces), area: Double($0.areaText) ?? 0) },
            totalFloors: floorItems.count,
            fromFloor: 0,
            toFloor: 0,
            floors: syncedFloors,
            waterMeterNumber: savedWaterNumber,
            waterMeterOwner: waterMeterOwner.trimmingCharacters(in: .whitespaces),
            electricityMeterNumber: electricityMeterNumber.trimmingCharacters(in: .whitespaces),
            electricityMeterOwner: electricityMeterOwner.trimmingCharacters(in: .whitespaces),
            gasMeterNumber: gasMeterNumber.trimmingCharacters(in: .whitespaces),
            gasMeterOwner: gasMeterOwner.trimmingCharacters(in: .whitespaces),
            gasUserNumber: gasUserNumber.trimmingCharacters(in: .whitespaces),
            insuranceItems: syncedInsurance,
            propertyAssets: syncedAssets,
            utilityPayments: existingUtilityPayments,
            extraMeters: extraMeters.map { m in
                UtilityMeter(id: m.id, type: m.type,
                             label: m.label.trimmingCharacters(in: .whitespaces),
                             meterNumber: m.meterNumber.trimmingCharacters(in: .whitespaces),
                             owner: m.owner.trimmingCharacters(in: .whitespaces),
                             userNumber: m.userNumber.trimmingCharacters(in: .whitespaces))
            }.filter { !$0.meterNumber.isEmpty || !$0.label.isEmpty },
            renovationPhotos: existingRenovationPhotos,
            documents: existingDocuments
        )
        // [v25.530] 這頁沒有編輯、init 也沒帶的欄位要從原本那間帶回來：舊版單筆房貸連結
        // （linkedExpenseId）以前存一次就被清掉，那筆房貸支出從此跟房子斷線；
        // 大樓的起訖樓層也不要歸零（樓層解析在下一版換掉）。
        if let old = currentEstate {
            re.linkedExpenseId = old.linkedExpenseId
            re.fromFloor = old.fromFloor
            re.toFloor = old.toFloor
        }
        // [v25.532] 這三個是這頁的欄位，照這頁的輸入寫，不從舊資料帶回（清空就是改回沒填）
        re.loanPrincipal = enteredPrincipal
        re.soldPrice = enteredSoldPrice
        re.valueUpdatedAt = valueStamp
        if currentEstate != nil { financeStore.update(re) } else { financeStore.add(re) }
        dismiss()
    }

    /// 自動存檔：在新增項目前確保 estate 已存在於 store
    @discardableResult
    private func ensureRealEstateSavedInStore() -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty,
              let priceWan = Double(purchasePriceText), priceWan > 0 else {
            showError = true
            return false
        }
        showError = false

        let price = priceWan * 10000
        let currentVal = (Double(currentValueText) ?? priceWan) * 10000

        if currentEstate == nil {
            let re = RealEstate(
                id: stableEstateId,
                name: trimmedName,
                city: city,
                address: address.trimmingCharacters(in: .whitespacesAndNewlines),
                purchaseDate: purchaseDate,
                purchasePrice: price,
                currentValue: currentVal,
                note: note.trimmingCharacters(in: .whitespaces),
                buildingType: buildingType
            )
            financeStore.add(re)
            hasAutoSaved = true
        }
        return true
    }

    /// 「取消」按鈕：新增流程中若已因新增貸款/已支出/變動支出等子項目觸發過
    /// ensureRealEstateSavedInStore() 自動建檔，「取消」原本只單純 dismiss、完全不檢查
    /// hasAutoSaved，導致這筆使用者明確想放棄的房地產連同已建立的支出/照片永久留在 store
    /// 並同步上 CloudKit。這裡補上回滾：
    /// 僅在「新增流程」（editing == nil）且已自動存檔時才移除，編輯既有房地產時
    /// 「取消」維持原樣不動任何資料。
    private func cancelAndRollback() {
        // [v25.530] 這次新選、還沒存進房子的保養照片刪掉；換掉的舊照片沒刪過，房子還指著它
        for task in elevatorPhotoLoadTasks.values { task.cancel() }
        for name in elevatorPhotosAdded { ElevatorMaintenance.deletePhoto(name) }
        if editing == nil, hasAutoSaved, let re = currentEstate {
            // [v25.530] 改走共用的刪整間：以前只刪記帳支出，銀行帳戶裡的扣款紀錄會留下來
            RealEstateDeletion.deleteEstate(re, financeStore: financeStore,
                                            expenseStore: expenseStore, lifeStore: lifeStore)
        }
        dismiss()
    }

    // MARK: - 刪除項目

    // [v25.530] 左滑刪除不再直接刪：先記下要刪哪幾筆、連到哪些記帳支出，跳確認框，
    // 確認後才連記帳支出＋銀行扣款紀錄一起刪（confirmSwipeDeletion）。

    private func deleteMortgageItems(at offsets: IndexSet) {
        let items = storeMortgageItems
        let picked = offsets.filter { $0 < items.count }.map { items[$0] }
        pendingSwipeDeletion = SwipeDeletionRequest(
            kind: .mortgage,
            itemIds: Set(picked.map { $0.id }),
            expenseIds: Set(picked.compactMap { $0.linkedExpenseId })
        )
    }

    private func deletePaidItems(at offsets: IndexSet) {
        let items = storePaidItems
        let picked = offsets.filter { $0 < items.count }.map { items[$0] }
        pendingSwipeDeletion = SwipeDeletionRequest(
            kind: .paid,
            itemIds: Set(picked.map { $0.id }),
            expenseIds: Set(picked.compactMap { $0.linkedExpenseId }).subtracting(expenseIdsOwnedByItems)
        )
    }

    private func deleteVariableItems(at offsets: IndexSet) {
        let items = storeVariableItems
        let picked = offsets.filter { $0 < items.count }.map { items[$0] }
        pendingSwipeDeletion = SwipeDeletionRequest(
            kind: .variable,
            itemIds: Set(picked.map { $0.id }),
            expenseIds: Set(picked.compactMap { $0.linkedExpenseId }).subtracting(expenseIdsOwnedByItems)
        )
    }

    /// [v25.530] 保險／附屬資產還連著的記帳支出 id（表單裡的＋store 裡的）。
    /// 舊版記帳再存一次這類支出，會把它重複加進變動支出（類別是房屋價金的加進房屋價金）；
    /// 左滑刪那種重複列時只拿掉那一列，支出還被保險／附屬資產連著，不能刪。
    /// 水電繳費連著的也算（跟卡片頁 isExpenseShared 同一套），不然刪重複列會讓繳費紀錄連到不存在的支出。
    private var expenseIdsOwnedByItems: Set<UUID> {
        var ids = Set(insuranceItems.compactMap { $0.linkedExpenseId })
        ids.formUnion(assetItems.compactMap { $0.linkedExpenseId })
        ids.formUnion((currentEstate?.insuranceItems ?? []).compactMap { $0.linkedExpenseId })
        ids.formUnion((currentEstate?.propertyAssets ?? []).compactMap { $0.linkedExpenseId })
        ids.formUnion((currentEstate?.utilityPayments ?? []).compactMap { $0.linkedExpenseId })
        return ids
    }

    private func swipeDeletionMessage(_ request: SwipeDeletionRequest) -> String {
        let expenseCount = request.expenseIds.count
        if expenseCount == 1 {
            return "會一起刪掉記帳裡這筆支出，以及銀行的扣款紀錄，不能復原。"
        }
        if expenseCount > 1 {
            return "會一起刪掉記帳裡這 \(expenseCount) 筆支出，以及銀行的扣款紀錄，不能復原。"
        }
        return "這個項目會刪除，不能復原。"
    }

    private func confirmSwipeDeletion(_ request: SwipeDeletionRequest) {
        guard var re = currentEstate else { return }
        // 記帳支出（含照片）＋所有銀行帳戶裡對得上的扣款紀錄
        RealEstateDeletion.removeExpenses(request.expenseIds, expenseStore: expenseStore, lifeStore: lifeStore)
        switch request.kind {
        case .mortgage:
            re.mortgageItems.removeAll { request.itemIds.contains($0.id) }
        case .paid:
            re.paidItems.removeAll { request.itemIds.contains($0.id) }
        case .variable:
            re.variableExpenses.removeAll { request.itemIds.contains($0.id) }
        }
        financeStore.update(re)
    }

    // MARK: - 同步函式

    private static func insuranceExpenseTitle(_ estateName: String, _ policyNumber: String) -> String {
        policyNumber.isEmpty ? "\(estateName) - 保險" : "\(estateName) - \(policyNumber)"
    }

    private static func assetExpenseLabel(_ name: String, _ category: RealEstateExpenseCategory) -> String {
        name.isEmpty ? category.rawValue : name
    }

    /// [v25.530] 保險／附屬資產連到的記帳支出（save() 用，改在 batch 副本上）。
    /// 支出還在：只改跟著項目變的欄位——金額；項目名稱改了（或標題還是舊的自動標題，例如只改了房子名稱）才改標題；
    /// 購入日改了、而且支出日期還停在原本的購入日才改日期；附屬資產類別改了才改子分類。
    /// 備註、照片、地點、付款方式、銀行等其他欄位原樣保留，id 不變（以前每存一次就整筆重建）。
    /// 支出已經不在（在記帳那邊被刪了）：才新建一筆，回傳新的 id 讓項目改連過去。
    private func syncLinkedExpense(
        linkedId: UUID?, amount: Double, title: String, oldAutoTitle: String?, nameChanged: Bool,
        category: RealEstateExpenseCategory, categoryChanged: Bool,
        reId: UUID, purchaseDayChanged: Bool, batch: inout LinkedExpenseBatch
    ) -> UUID {
        if let id = linkedId, let idx = batch.expenses.firstIndex(where: { $0.id == id }) {
            var exp = batch.expenses[idx]
            let oldAmount = exp.amount
            let oldDate = exp.date
            let oldTitle = exp.title
            let oldCategory = exp.realEstateExpenseCategory
            exp.amount = amount
            if nameChanged || exp.title == oldAutoTitle {
                exp.title = title
            }
            if purchaseDayChanged, let oldPurchaseDate = editing?.purchaseDate,
               Calendar.current.isDate(exp.date, inSameDayAs: oldPurchaseDate) {
                exp.date = purchaseDate
            }
            if categoryChanged {
                exp.realEstateExpenseCategory = category
            }
            let moneyChanged = exp.amount != oldAmount || exp.date != oldDate
            if moneyChanged || exp.title != oldTitle || exp.realEstateExpenseCategory != oldCategory {
                batch.expenses[idx] = exp
                batch.changed = true
            }
            if moneyChanged { batch.bankSyncIds.insert(id) }
            return id
        }
        let newExpense = Expense(
            id: UUID(), title: title, amount: amount, date: purchaseDate,
            expenseType: .variable, variableCategory: .realEstate,
            linkedRealEstateId: reId,
            realEstateExpenseCategory: category, note: ""
        )
        batch.expenses.append(newExpense)
        batch.changed = true
        return newExpense.id
    }

    /// [v25.530] 金額或日期改了的連結支出，照 AddExpenseView.syncBankWithdrawal 重寫它的銀行扣款紀錄：
    /// 移掉舊的、寫入新的；信用卡扣款、週期性固定支出不寫單筆。milestones 只寫一次。
    private func syncBankWithdrawals(for ids: Set<UUID>, in expenses: [Expense]) {
        guard !ids.isEmpty else { return }
        var milestones = lifeStore.milestones
        var changed = false
        for exp in expenses where ids.contains(exp.id) {
            guard exp.linkedCreditCardMilestoneId == nil else { continue }
            if exp.expenseType == .fixed && exp.recurrence != nil { continue }
            guard let bankId = exp.linkedBankMilestoneId,
                  let mi = milestones.firstIndex(where: { $0.id == bankId }) else { continue }
            var list = milestones[mi].bankDeposits ?? []
            list.removeAll { $0.linkedExpenseId == exp.id }
            // 台幣支出扣外幣子帳戶時照匯率換算（同水電瓦斯編輯器）；支出本身就是那個幣別才原樣記
            let isNTD = exp.currencyCode == "NT$" || exp.currencyCode == "TWD"
            let value: (amount: Double, code: String) = isNTD
                ? realEstateBankWithdrawalValue(ntd: exp.amount, currency: exp.linkedBankCurrency, rates: expenseStore.currencyRates)
                : (amount: exp.amount, code: exp.linkedBankCurrency ?? exp.currencyCode)
            list.append(BankDeposit(
                id: UUID(), date: exp.date, amount: value.amount,
                currencyCode: value.code,
                isWithdrawal: true, linkedExpenseId: exp.id
            ))
            milestones[mi].bankDeposits = list
            changed = true
        }
        if changed { lifeStore.milestones = milestones }
    }

    // MARK: - 載入編輯

    private func loadEditing() {
        guard let e = editing else { return }

        // 優先使用 UserDefaults 中持久化的切換值；若未儲存過則依資料推導預設值
        showRental = loadStoredToggle("showRental") ?? (e.monthlyRental > 0)
        showMortgage = loadStoredToggle("showMortgage") ?? !e.mortgageItems.isEmpty
        showPaid = loadStoredToggle("showPaid") ?? !e.paidItems.isEmpty
        showVariable = loadStoredToggle("showVariable") ?? !e.variableExpenses.isEmpty
        showLandDetail = loadStoredToggle("showLandDetail") ?? (!e.landDeeds.isEmpty || !e.buildingDeeds.isEmpty)
        showFloor = loadStoredToggle("showFloor") ?? !e.floors.isEmpty
        showUtilities = loadStoredToggle("showUtilities") ?? (!e.waterMeterNumber.isEmpty || !e.electricityMeterNumber.isEmpty || !e.gasMeterNumber.isEmpty || !e.gasUserNumber.isEmpty)
        showInsurance = loadStoredToggle("showInsurance") ?? !e.insuranceItems.isEmpty
        showAsset = loadStoredToggle("showAsset") ?? !e.propertyAssets.isEmpty

        name = e.name; city = e.city; address = e.address
        purchaseDate = e.purchaseDate
        if let sd = e.soldDate {
            isSold = true; soldDate = sd
        } else {
            isSold = false; soldDate = Date()
        }
        // [v25.530] 金額帶回輸入框不能丟精度：%g 只有 6 位有效數字，每存一次「萬」就漂一點
        purchasePriceText = e.purchasePrice > 0 ? Self.editableAmountText(e.purchasePrice / 10000, decimals: 4) : ""
        currentValueText = e.currentValue > 0 ? Self.editableAmountText(e.currentValue / 10000, decimals: 4) : ""
        monthlyRentalText = e.monthlyRental > 0 ? Self.editableAmountText(e.monthlyRental, decimals: 2) : ""
        // [v25.532] 只帶回你填過的；推算的數字只當提示字，不放進輸入框
        if let principal = e.loanPrincipal, principal > 0 {
            loanPrincipalText = Self.editableAmountText(principal / 10000, decimals: 4)
        } else {
            loanPrincipalText = ""
        }
        if let sold = e.soldPrice, sold > 0 {
            soldPriceText = Self.editableAmountText(sold / 10000, decimals: 4)
        } else {
            soldPriceText = ""
        }
        note = e.note

        // mortgageItems / paidItems / variableExpenses 已從 store 直接讀取，無須載入到本地 state

        // 人生模式欄位
        buildingType = e.buildingType
        hasElevator = e.hasElevator
        elevatorItems = e.elevatorMaintenances.map {
            ElevatorItemState(id: $0.id, date: $0.date, photoFileNames: $0.photoFileNames)
        }
        pingCountText = e.pingCount > 0 ? String(format: "%g", e.pingCount) : ""
        landOwner = e.landOwner
        if ownerCandidates.contains(e.landOwner) {
            ownerPickerSelection = e.landOwner
        }
        landSituation = e.landSituation
        landNumber = e.landNumber
        landAreaText = e.landArea > 0 ? String(format: "%g", e.landArea) : ""
        landDeedItems = e.landDeeds.map { d in
            LandDeedState(id: d.id, situation: d.situation, number: d.number, areaText: d.area > 0 ? String(format: "%g", d.area) : "")
        }
        bldgDeedItems = e.buildingDeeds.map { d in
            BuildingDeedState(id: d.id, situation: d.situation, number: d.number, address: d.address,
                              hasCompletionDate: d.completionDate != nil, completionDate: d.completionDate ?? Date(),
                              usage: d.usage, annex: d.annex, areaText: d.area > 0 ? String(format: "%g", d.area) : "")
        }
        floorItems = e.floors.map { f in
            FloorItemState(id: f.id, floorNumber: f.floorNumber, functions: Set(f.functions), areaText: f.area > 0 ? String(format: "%g", f.area) : "")
        }
        // waterMeterNumber 留著原值：save() 用它判斷三格有沒有被改過
        waterMeterNumber = e.waterMeterNumber
        // [v25.530] 任何段數都拆得回三格（以前剛好兩段時三格全空，再存就被清掉）
        let waterParts = Self.splitWaterNumber(e.waterMeterNumber)
        waterStation = waterParts[0]; waterCode = waterParts[1]; waterCheck = waterParts[2]
        waterMeterOwner = e.waterMeterOwner
        electricityMeterNumber = e.electricityMeterNumber
        electricityMeterOwner = e.electricityMeterOwner
        gasMeterNumber = e.gasMeterNumber
        gasMeterOwner = e.gasMeterOwner
        gasUserNumber = e.gasUserNumber
        extraMeters = e.extraMeters
        // [v25.530] 讀回時剛好是某位家人的，才用「從家人選」模式；其餘（含空白）是手動輸入
        var picked = Set<String>()
        if ownerCandidates.contains(e.waterMeterOwner) { picked.insert("water") }
        if ownerCandidates.contains(e.electricityMeterOwner) { picked.insert("electricity") }
        if ownerCandidates.contains(e.gasMeterOwner) { picked.insert("gas") }
        for m in e.extraMeters where ownerCandidates.contains(m.owner) {
            picked.insert(m.id.uuidString)
        }
        ownerPickedFromList = picked

        insuranceItems = e.insuranceItems.map { ins in
            InsuranceItemState(
                id: ins.id, policyNumber: ins.policyNumber,
                amountText: ins.amount > 0 ? Self.editableAmountText(ins.amount, decimals: 2) : "",
                linkedExpenseId: ins.linkedExpenseId
            )
        }

        assetItems = e.propertyAssets.map { a in
            AssetItemState(
                id: a.id, category: a.category, name: a.name,
                brand: a.brand, floorLocation: a.floorLocation,
                amountText: a.amount > 0 ? Self.editableAmountText(a.amount, decimals: 2) : "",
                linkedExpenseId: a.linkedExpenseId
            )
        }
    }

    /// [v25.530] 金額帶回輸入框：四捨五入到指定小數位後去掉多餘的 0。
    /// 「萬」用 4 位（＝1 元精度），元用 2 位。只給可編輯的文字用，顯示用的格式不走這裡。
    private static func editableAmountText(_ value: Double, decimals: Int) -> String {
        var text = String(format: "%.\(decimals)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }

    /// [v25.532] 「萬」輸入框換成台幣；空的、看不懂的、≤ 0 都回 nil（＝沒填）。
    /// 貼上「inf」「1e400」會變成無限大，存進去整份房地產 JSON 編碼失敗、默默存不了檔，也當沒填。
    private static func positiveWan(_ text: String) -> Double? {
        guard let wan = Double(text.trimmingCharacters(in: .whitespaces)), wan > 0 else { return nil }
        let value = wan * 10000
        return value.isFinite ? value : nil
    }

    /// [v25.530] 水號拆成「站所、編號、檢號」三格，一定回傳 3 個元素：
    /// 1 段放編號；2 段末段只有 1 個字當「編號-檢號」，否則當「站所-編號」；
    /// 3 段以上頭尾是站所、檢號，中間全部（含 -）放編號。
    private static func splitWaterNumber(_ raw: String) -> [String] {
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        switch parts.count {
        case 0:
            return ["", "", ""]
        case 1:
            return ["", parts[0], ""]
        case 2:
            return parts[1].count <= 1 ? ["", parts[0], parts[1]] : [parts[0], parts[1], ""]
        default:
            let middle = parts[1..<(parts.count - 1)].joined(separator: "-")
            return [parts[0], middle, parts[parts.count - 1]]
        }
    }

    // MARK: - 售出損益同步

    private func syncSaleIncome(reId: UUID, name: String, profit: Double, date: Date, existingId: UUID?) -> UUID {
        let incId = existingId ?? UUID()
        let income = Income(
            id: incId, title: "售出 \(name)（獲利）",
            amount: profit, date: date,
            category: .investment, period: .once,
            linkedStockId: nil
        )
        if existingId != nil { expenseStore.update(income) }
        else { expenseStore.add(income) }
        return incId
    }

    private func syncSaleExpense(reId: UUID, name: String, loss: Double, date: Date, existingId: UUID?) -> UUID {
        let expId = existingId ?? UUID()
        // 帶回既有 photoFileNames：連結的支出可能在記帳那邊附加過照片，整筆重建時不帶回會被清空、檔案變孤兒。
        let existingPhotos = existingId.flatMap { id in expenseStore.expenses.first(where: { $0.id == id })?.photoFileNames } ?? []
        let expense = Expense(
            id: expId, title: "售出 \(name)（虧損）",
            amount: loss, date: date,
            expenseType: .variable, variableCategory: .realEstate,
            linkedRealEstateId: reId, note: "",
            photoFileNames: existingPhotos
        )
        if existingId != nil { expenseStore.update(expense) }
        else { expenseStore.add(expense) }
        return expId
    }

    private func formatCurrency(_ value: Double) -> String {
        value.ntdWanString
    }

    // MARK: - 美化輔助：Section Header（Capsule 側條 + 彩色圖示 + 粗體標題）

    private func reSectionHeader(_ title: String, icon: String, color: Color) -> some View {
        reSectionHeader(title, icon: icon, color: color) { EmptyView() }
    }

    /// 動態編號 Section（土地/建物權狀）專用：補上可選的右側操作按鈕（如刪除），
    /// 與無 trailing 版本共用同一份色條＋圖示＋標題排版，避免另立一套樣式。
    private func reSectionHeader<Trailing: View>(
        _ title: String, icon: String, color: Color, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 9) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 18)
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
            Spacer()
            trailing()
        }
        .textCase(nil)
    }

    // MARK: - 美化輔助：漸層圖示圓（32pt + stroke 邊框，對齊 CareerView v2 / FamilyView v2 規格）

    private func reIconCircle(icon: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.22), color.opacity(0.09)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
        }
        .overlay(Circle().stroke(color.opacity(0.22), lineWidth: 0.75))
    }

    // MARK: - 美化輔助：Tab 切換器漸層（對齊 RealEstateDetailView.tabPicker 規格）

    private func reTabGradient(_ tab: EditTab) -> LinearGradient {
        switch tab {
        case .finance:
            return LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing)
        case .house:
            return LinearGradient(colors: [.teal, Color(red: 0.12, green: 0.50, blue: 0.88)], startPoint: .leading, endPoint: .trailing)
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - 美化紀錄（PhotoViewerSheet）
// [2026-07] 本次美化方向：
//   本元件為全 App 共用的縮放照片檢視器（AddRealEstateView 內物件照片 / RealEstateDetailView
//   房屋資料照片 / FamilyMembersResumeView 家人照片皆呼叫此同一個 struct），
//   1. 「關閉」按鈕：topBarTrailing → topBarLeading，修正與全 App「關閉／取消統一置左」
//      慣例不符的殘留個案（MultiPhotoGallery.PhotoLightbox v2 當時誤判為「唯一例外」，
//      實際上此處也是同一慣例的漏網之魚，一併補上）。
//   2. 「重設縮放」圖示鈕：原本佔用左側，改移至 topBarTrailing，避免與關閉鈕位置衝突。
// [2026-07 v2] 載入狀態 / 失敗狀態補上黑底對比與進場動畫，聚焦這一個元件：
//   3. ProgressView() 原本沒有 tint，在純黑背景上呈現系統預設灰色、辨識度低；
//      補上 .tint(.white)，對齊 MultiPhotoGallery.PhotoLightbox／RealEstateDetailView／
//      RenovationPhotoEditor 等黑底載入圈的既有規格。
//   4. 失敗狀態原本用 .secondary（跟隨系統配色，在黑底上淺色模式會偏深灰、對比不足），
//      改為 .white.opacity 分層 + 圖示加淡白色圓底錨點，確保深淺色模式在黑背景上都清楚可辨。
//   5. 圖片載入完成加入淡入動畫（imageAppeared），取代原本讀檔完成瞬間硬切出現的生硬感，
//      對齊 MultiPhotoGallery.PhotoLightbox 的淡入規格。
//   本次僅調整載入中／失敗兩種狀態與進場過場的視覺呈現，縮放/拖曳手勢、關閉／重設鈕邏輯、
//   讀檔流程完全未變動。
struct PhotoViewerSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    // 只在進場時從磁碟讀取一次並解碼，避免 pinch/pan 手勢每次改 scale/offset 都觸發 body
    // 重新評估、連帶在主執行緒重複讀檔＋解碼造成縮放時明顯卡頓。
    @State private var loadedImage: UIImage?
    @State private var loadFailed = false
    @State private var imageAppeared = false

    var body: some View {
        NavigationStack {
            Group {
                if let img = loadedImage {
                    GeometryReader { geo in
                        Image(uiImage: img)
                            .resizable().scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .scaleEffect(scale)
                            .offset(offset)
                            .opacity(imageAppeared ? 1 : 0)
                            .onAppear {
                                withAnimation(.easeOut(duration: 0.25)) { imageAppeared = true }
                            }
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        scale = max(1, min(lastScale * value, 5))
                                    }
                                    .onEnded { _ in
                                        lastScale = scale
                                        if scale <= 1 { resetView() }
                                    }
                            )
                            .simultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        guard scale > 1 else { return }
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                            )
                            .onTapGesture(count: 2) {
                                withAnimation(.spring(duration: 0.3)) {
                                    if scale > 1 {
                                        resetView()
                                    } else {
                                        scale = 2.5
                                        lastScale = 2.5
                                    }
                                }
                            }
                    }
                } else if loadFailed {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 64, height: 64)
                            Image(systemName: "photo.slash")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        Text("無法載入照片")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            // 照片資訊列：檔名 / 解析度 / 檔案大小（與 PhotoLightbox 共用 PhotoInfoBar）
            .overlay(alignment: .bottom) {
                if loadedImage != nil {
                    PhotoInfoBar(url: url, image: loadedImage)
                        .padding(.bottom, 14)
                }
            }
            .task {
                let url = url
                let img = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    return UIImage(data: data)
                }.value
                loadedImage = img
                loadFailed = (img == nil)
            }
            .navigationTitle("照片瀏覽")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 關閉按鈕：統一移至左側，對齊全 App「關閉／取消置左」慣例
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
                // 重設縮放：讓出左側給關閉鈕，改置右側
                ToolbarItem(placement: .topBarTrailing) {
                    if scale > 1 {
                        Button {
                            withAnimation(.spring(duration: 0.3)) { resetView() }
                        } label: {
                            Image(systemName: "arrow.counterclockwise.circle")
                                .foregroundStyle(.white)
                        }
                    }
                }
                // [v25.471] 存到相簿／分享（與其餘圖片預覽共用同一組按鈕）。
                // 這個檢視器有導覽列，兩顆就掛在右上角的工具列上——位置與其他
                // 預覽一致，只是外框由工具列提供，不再套深色圓底。
                ToolbarItem(placement: .topBarTrailing) {
                    PhotoActionButtons(url: url, chromeless: true)
                }
            }
        }
    }

    private func resetView() {
        scale = 1; lastScale = 1
        offset = .zero; lastOffset = .zero
    }
}
