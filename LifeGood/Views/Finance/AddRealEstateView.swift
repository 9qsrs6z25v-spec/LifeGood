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
    // v2 進場動畫旗標
    @State private var cardAppeared = false
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

    struct ElevatorItemState: Identifiable {
        let id: UUID
        var date: Date
        var photoFileName: String?
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
    @State private var insuranceItems: [InsuranceItemState] = []
    @State private var assetItems: [AssetItemState] = []

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
            Form {
                // ── 英雄預覽卡（物件名稱 / 購入價 / KPI）──
                Section {
                    estatePreviewCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .opacity(cardAppeared ? 1 : 0)
                        .offset(y: cardAppeared ? 0 : 20)
                }

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
                    calcSection

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
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button { showFeaturePicker.toggle() } label: {
                            Image(systemName: "checklist")
                                .foregroundStyle(.blue)
                        }
                        .popover(isPresented: $showFeaturePicker, arrowEdge: .top) {
                            featureToggleList
                        }
                        Button((editing != nil || hasAutoSaved) ? "儲存" : "新增") { save() }
                            .bold().foregroundStyle(.green)
                    }
                }
            }
            .onAppear {
                loadEditing()
                withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                    cardAppeared = true
                }
            }
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
            .confirmationDialog("選擇變動支出類別", isPresented: $showVariableCategoryPicker, titleVisibility: .visible) {
                ForEach(RealEstateExpenseCategory.allCases.filter { $0 != .housePayment }) { cat in
                    Button(cat.rawValue) {
                        addingVariableCategory = cat
                    }
                }
                Button("取消", role: .cancel) {}
            }
        }
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

            Toggle("已售出", isOn: $isSold)
            if isSold {
                DatePicker("售出日期", selection: $soldDate, in: purchaseDate..., displayedComponents: .date)
            }
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
            Text("以萬元為單位輸入，例如輸入 1500 代表 NT$15,000,000。")
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

    private var mortgageSection: some View {
        Section {
            ForEach(storeMortgageItems) { m in
                Button {
                    if let expId = m.linkedExpenseId,
                       let exp = expenseStore.expenses.first(where: { $0.id == expId }) {
                        editingExpense = exp
                    }
                } label: {
                    HStack(spacing: 12) {
                        reIconCircle(icon: "building.columns.fill", color: .blue)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(m.title.isEmpty ? "房貸" : m.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            HStack(spacing: 5) {
                                if m.totalPeriods > 0 {
                                    Text("\(m.elapsedPeriods)/\(m.totalPeriods) 期")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.blue)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.10))
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(Color.blue.opacity(0.22), lineWidth: 0.6))
                                }
                                Text("已繳 \(formatCurrency(m.paidAmount))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(formatCurrency(m.amount))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.22, green: 0.53, blue: 0.98))
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: deleteMortgageItems)

            Button {
                guard ensureRealEstateSavedInStore() else { return }
                addingMortgage = true
            } label: {
                Label("新增貸款項目", systemImage: "plus.circle").foregroundStyle(.blue)
            }
        } header: {
            reSectionHeader("貸款項目", icon: "building.columns.fill", color: .blue)
        } footer: {
            if !storeMortgageItems.isEmpty {
                let monthlyTotal = storeMortgageItems.reduce(0.0) { $0 + $1.amount }
                Text("每月房貸合計 \(formatCurrency(monthlyTotal))，與記帳模式的固定支出連動。")
            } else {
                Text("點擊「新增貸款項目」可建立多筆不同期數的貸款。")
            }
        }
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
                            Text(p.title.isEmpty ? "房屋價金" : p.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
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
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
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
                                    Text(ve.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
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
        Section("房屋資料") {
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
                HStack {
                    Text("土地權狀 \((landDeedItems.firstIndex(where: { $0.id == item.id }) ?? 0) + 1)")
                    Spacer()
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
                HStack {
                    Text("建物權狀 \((bldgDeedItems.firstIndex(where: { $0.id == item.id }) ?? 0) + 1)")
                    Spacer()
                    Button { bldgDeedItems.removeAll { $0.id == item.id } } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                    }.buttonStyle(.plain)
                }
            }
        }

        Section("詳細") {
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

                    if let photoFileName = item.photoFileName {
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
                                    if let oldName = elevatorItems.first(where: { $0.id == itemId })?.photoFileName {
                                        ElevatorMaintenance.deletePhoto(oldName)
                                    }
                                    let fileName = ElevatorMaintenance.savePhoto(data, id: UUID())
                                    if let idx = elevatorItems.firstIndex(where: { $0.id == itemId }) {
                                        elevatorItems[idx].photoFileName = fileName
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
                        Image(systemName: item.photoFileName == nil ? "photo.badge.plus" : "arrow.triangle.2.circlepath.camera")
                            .font(.title3).foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        // 刪除這筆記錄前先取消尚未完成的照片載入 Task，避免它稍後才完成、
                        // 把照片存進磁碟卻已找不到對應的 item，變成永久孤兒檔案。
                        elevatorPhotoLoadTasks[item.id]?.cancel()
                        elevatorPhotoLoadTasks[item.id] = nil
                        if let fn = item.photoFileName {
                            ElevatorMaintenance.deletePhoto(fn)
                        }
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
                    ownerPicker(selection: $waterMeterOwner, placeholder: "所有權人")
                }
            }
            HStack {
                Image(systemName: "bolt.fill").foregroundStyle(.yellow).frame(width: 24)
                VStack(alignment: .leading, spacing: 6) {
                    TextField("電號", text: $electricityMeterNumber)
                    ownerPicker(selection: $electricityMeterOwner, placeholder: "所有權人")
                }
            }
            HStack {
                Image(systemName: "flame.fill").foregroundStyle(.orange).frame(width: 24)
                VStack(alignment: .leading, spacing: 6) {
                    TextField("用戶編號", text: $gasUserNumber)
                    TextField("表號", text: $gasMeterNumber)
                    ownerPicker(selection: $gasMeterOwner, placeholder: "所有權人")
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
                    ownerPicker(selection: $meter.owner, placeholder: "所有權人")
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

    private func ownerPicker(selection: Binding<String>, placeholder: String) -> some View {
        Group {
            if ownerCandidates.isEmpty {
                TextField(placeholder, text: selection)
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Picker(placeholder, selection: selection) {
                    Text("手動輸入").tag("")
                    ForEach(ownerCandidates, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .font(.subheadline)
                if selection.wrappedValue.isEmpty {
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
                            // 改用 expenseStore.delete(_:)（對齊本檔案售出損益同步等處既有規格），
                            // 確保連結支出附加的照片一併從磁碟移除，避免直接 removeAll 留下孤兒照片檔。
                            if let linkedId = item.linkedExpenseId,
                               let exp = expenseStore.expenses.first(where: { $0.id == linkedId }) {
                                expenseStore.delete(exp)
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
                            // 改用 expenseStore.delete(_:)（對齊本檔案售出損益同步等處既有規格），
                            // 確保連結支出附加的照片一併從磁碟移除，避免直接 removeAll 留下孤兒照片檔。
                            if let linkedId = item.linkedExpenseId,
                               let exp = expenseStore.expenses.first(where: { $0.id == linkedId }) {
                                expenseStore.delete(exp)
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

    // MARK: - 試算

    @ViewBuilder
    private var calcSection: some View {
        let rental = Double(monthlyRentalText) ?? 0
        let mortgageMonthly = storeMortgageItems.reduce(0.0) { $0 + $1.amount }
        let mortgagePaidTotal = storeMortgageItems.reduce(0.0) { $0 + $1.paidAmount }
        let paidTotal = storePaidItems.reduce(0.0) { $0 + $1.amount }
        let varTotal = storeVariableItems.reduce(0.0) { $0 + $1.amount }
        let mortgageTotal = storeMortgageItems.reduce(0.0) { $0 + $1.totalAmount }
        let allPaid = paidTotal + mortgagePaidTotal + varTotal

        if rental > 0 || mortgageMonthly > 0 || paidTotal > 0 || varTotal > 0 {
            Section(header: reSectionHeader("試算", icon: "function", color: .teal)) {
                if rental > 0 || mortgageMonthly > 0 {
                    let netFlow = rental - mortgageMonthly
                    let flowColor: Color = netFlow >= 0 ? .green : .red
                    HStack {
                        Text("每月淨現金流")
                            .font(.subheadline)
                        Spacer()
                        Text(formatCurrency(netFlow))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(flowColor)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(flowColor.opacity(0.10))
                            .clipShape(Capsule())
                    }
                }
                if mortgageTotal > 0 {
                    HStack {
                        Text("貸款總額").font(.subheadline)
                        Spacer()
                        Text(formatCurrency(mortgageTotal))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                if mortgagePaidTotal > 0 {
                    HStack {
                        Text("已繳貸款金額").font(.subheadline)
                        Spacer()
                        Text(formatCurrency(mortgagePaidTotal))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.22, green: 0.53, blue: 0.98))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.blue.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
                if paidTotal > 0 {
                    HStack {
                        Text("已支出房屋金額").font(.subheadline)
                        Spacer()
                        Text(formatCurrency(paidTotal))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.purple.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
                if varTotal > 0 {
                    HStack {
                        Text("變動支出累計").font(.subheadline)
                        Spacer()
                        Text(formatCurrency(varTotal))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.orange.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
                HStack {
                    Text("房屋總已支出")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(formatCurrency(allPaid))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.25))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Color.red.opacity(0.10))
                        .clipShape(Capsule())
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
        let reId = stableEstateId

        // 貸款/已支出/變動支出由 AddExpenseView 直接寫入 financeStore，這裡保留 store 內既有資料
        let syncedMortgages: [RealEstateMortgageItem] = currentEstate?.mortgageItems ?? []
        let syncedPaids: [RealEstatePaidItem] = currentEstate?.paidItems ?? []
        let syncedVariable: [RealEstateVariableExpense] = currentEstate?.variableExpenses ?? []
        let existingUtilityPayments: [UtilityPayment] = currentEstate?.utilityPayments ?? []
        // 房屋資料集錦由詳細頁 RenovationPhotoEditor 直接寫入，這裡保留既有資料避免被清空
        let existingRenovationPhotos: [RenovationPhoto] = currentEstate?.renovationPhotos ?? []
        let existingDocuments: [RealEstateDocument] = currentEstate?.documents ?? []

        // 同步保險項目到變動支出（有價格才連動）
        var syncedInsurance: [RealEstateInsuranceItem] = []
        for item in insuranceItems {
            if item.amount > 0 {
                let expId = syncInsuranceExpense(reId: reId, reName: trimmedName, item: item)
                syncedInsurance.append(RealEstateInsuranceItem(
                    id: item.id, policyNumber: item.policyNumber,
                    amount: item.amount, linkedExpenseId: expId
                ))
            } else {
                // 金額被清空前若已連動過一筆變動支出，這裡只是把 linkedExpenseId 設為 nil，
                // 不會刪掉舊的 Expense；該筆孤兒紀錄會繼續留在變動支出總額裡且從此無從察覺，
                // 需比照上面「有價格」分支一併清掉。
                if let oldExpId = item.linkedExpenseId,
                   let oldExp = expenseStore.expenses.first(where: { $0.id == oldExpId }) {
                    expenseStore.delete(oldExp)
                }
                syncedInsurance.append(RealEstateInsuranceItem(
                    id: item.id, policyNumber: item.policyNumber,
                    amount: 0, linkedExpenseId: nil
                ))
            }
        }

        // 同步附屬資產到變動支出（有價格才連動）
        var syncedAssets: [RealEstatePropertyAsset] = []
        for item in assetItems {
            if item.amount > 0 {
                let expId = syncAssetExpense(reId: reId, reName: trimmedName, item: item)
                syncedAssets.append(RealEstatePropertyAsset(
                    id: item.id, category: item.category, name: item.name,
                    brand: item.brand, floorLocation: item.floorLocation,
                    amount: item.amount, linkedExpenseId: expId
                ))
            } else {
                // 同上：金額清空前若已連動過變動支出，須一併刪除，避免孤兒 Expense 繼續計入總額。
                if let oldExpId = item.linkedExpenseId,
                   let oldExp = expenseStore.expenses.first(where: { $0.id == oldExpId }) {
                    expenseStore.delete(oldExp)
                }
                syncedAssets.append(RealEstatePropertyAsset(
                    id: item.id, category: item.category, name: item.name,
                    brand: item.brand, floorLocation: item.floorLocation,
                    amount: 0, linkedExpenseId: nil
                ))
            }
        }

        // 售出損益同步
        var saleExpId = editing?.saleLinkedExpenseId
        var saleIncId = editing?.saleLinkedIncomeId
        if isSold {
            let pl = currentVal - price
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

        let re = RealEstate(
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
            hasElevator: buildingType == .townhouse && hasElevator,
            elevatorMaintenances: (buildingType == .townhouse && hasElevator)
                ? elevatorItems.map { ElevatorMaintenance(id: $0.id, date: $0.date, photoFileName: $0.photoFileName) }
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
            floors: floorItems.map { FloorInfo(id: $0.id, floorNumber: $0.floorNumber, functions: Array($0.functions), area: Double($0.areaText) ?? 0) },
            waterMeterNumber: combinedWaterNumber,
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

    // MARK: - 刪除項目

    private func deleteMortgageItems(at offsets: IndexSet) {
        guard var re = currentEstate else { return }
        let items = re.mortgageItems
        // 這些項目可透過「已支出項目」點擊進入 AddExpenseView 附加照片，
        // 刪除前先清除照片檔案避免孤兒檔（對齊 VehicleView/VehicleDetailView.deleteVehicle 既有修復規格）
        var linkedIds = Set<UUID>()
        for index in offsets {
            let item = items[index]
            if let expId = item.linkedExpenseId { linkedIds.insert(expId) }
            re.mortgageItems.removeAll { $0.id == item.id }
        }
        if !linkedIds.isEmpty {
            for exp in expenseStore.expenses where linkedIds.contains(exp.id) {
                for name in exp.photoFileNames { Expense.deletePhoto(name) }
            }
            expenseStore.expenses.removeAll { linkedIds.contains($0.id) }
        }
        financeStore.update(re)
    }

    private func deletePaidItems(at offsets: IndexSet) {
        guard var re = currentEstate else { return }
        let items = re.paidItems
        var linkedIds = Set<UUID>()
        for index in offsets {
            let item = items[index]
            if let expId = item.linkedExpenseId { linkedIds.insert(expId) }
            re.paidItems.removeAll { $0.id == item.id }
        }
        if !linkedIds.isEmpty {
            for exp in expenseStore.expenses where linkedIds.contains(exp.id) {
                for name in exp.photoFileNames { Expense.deletePhoto(name) }
            }
            expenseStore.expenses.removeAll { linkedIds.contains($0.id) }
        }
        financeStore.update(re)
    }

    private func deleteVariableItems(at offsets: IndexSet) {
        guard var re = currentEstate else { return }
        let items = re.variableExpenses
        var linkedIds = Set<UUID>()
        for index in offsets {
            let item = items[index]
            if let expId = item.linkedExpenseId { linkedIds.insert(expId) }
            re.variableExpenses.removeAll { $0.id == item.id }
        }
        if !linkedIds.isEmpty {
            for exp in expenseStore.expenses where linkedIds.contains(exp.id) {
                for name in exp.photoFileNames { Expense.deletePhoto(name) }
            }
            expenseStore.expenses.removeAll { linkedIds.contains($0.id) }
        }
        financeStore.update(re)
    }

    // MARK: - 同步函式

    private func syncInsuranceExpense(reId: UUID, reName: String, item: InsuranceItemState) -> UUID {
        let expenseId = item.linkedExpenseId ?? UUID()
        let title = item.policyNumber.isEmpty ? "\(reName) - 保險" : "\(reName) - \(item.policyNumber)"
        let expense = Expense(
            id: expenseId, title: title, amount: item.amount, date: purchaseDate,
            expenseType: .variable, variableCategory: .realEstate,
            linkedRealEstateId: reId,
            realEstateExpenseCategory: .insurance, note: ""
        )
        if item.linkedExpenseId != nil { expenseStore.update(expense) }
        else { expenseStore.add(expense) }
        return expenseId
    }

    private func syncAssetExpense(reId: UUID, reName: String, item: AssetItemState) -> UUID {
        let expenseId = item.linkedExpenseId ?? UUID()
        let label = item.name.isEmpty ? item.category.rawValue : item.name
        let expense = Expense(
            id: expenseId, title: "\(reName) - \(label)",
            amount: item.amount, date: purchaseDate,
            expenseType: .variable, variableCategory: .realEstate,
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
        purchasePriceText = e.purchasePrice > 0 ? String(format: "%g", e.purchasePrice / 10000) : ""
        currentValueText = e.currentValue > 0 ? String(format: "%g", e.currentValue / 10000) : ""
        monthlyRentalText = e.monthlyRental > 0 ? String(format: "%.0f", e.monthlyRental) : ""
        note = e.note

        // mortgageItems / paidItems / variableExpenses 已從 store 直接讀取，無須載入到本地 state

        // 人生模式欄位
        buildingType = e.buildingType
        hasElevator = e.hasElevator
        elevatorItems = e.elevatorMaintenances.map {
            ElevatorItemState(id: $0.id, date: $0.date, photoFileName: $0.photoFileName)
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
        waterMeterNumber = e.waterMeterNumber
        let waterParts = e.waterMeterNumber.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        if waterParts.count >= 3 {
            waterStation = waterParts[0]; waterCode = waterParts[1]; waterCheck = waterParts[2]
        } else if waterParts.count == 1 && !waterParts[0].isEmpty {
            waterCode = waterParts[0]
        }
        waterMeterOwner = e.waterMeterOwner
        electricityMeterNumber = e.electricityMeterNumber
        electricityMeterOwner = e.electricityMeterOwner
        gasMeterNumber = e.gasMeterNumber
        gasMeterOwner = e.gasMeterOwner
        gasUserNumber = e.gasUserNumber
        extraMeters = e.extraMeters

        insuranceItems = e.insuranceItems.map { ins in
            InsuranceItemState(
                id: ins.id, policyNumber: ins.policyNumber,
                amountText: ins.amount > 0 ? String(format: "%.0f", ins.amount) : "",
                linkedExpenseId: ins.linkedExpenseId
            )
        }

        assetItems = e.propertyAssets.map { a in
            AssetItemState(
                id: a.id, category: a.category, name: a.name,
                brand: a.brand, floorLocation: a.floorLocation,
                amountText: a.amount > 0 ? String(format: "%.0f", a.amount) : "",
                linkedExpenseId: a.linkedExpenseId
            )
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
        let expense = Expense(
            id: expId, title: "售出 \(name)（虧損）",
            amount: loss, date: date,
            expenseType: .variable, variableCategory: .realEstate,
            linkedRealEstateId: reId, note: ""
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

    // MARK: - 美化輔助：英雄預覽卡（紫藍漸層 + 三顆散景圓 + 玻璃光澤）

    private var estatePreviewCard: some View {
        let purchaseWan = Double(purchasePriceText) ?? 0
        let currentWan  = Double(currentValueText)  ?? 0
        let apprecWan   = (purchaseWan > 0 && currentWan > 0) ? currentWan - purchaseWan : 0
        let rentalAmt   = Double(monthlyRentalText) ?? 0
        let isUp        = apprecWan >= 0
        let accentTop   = Color(red: 0.52, green: 0.20, blue: 0.88)
        let accentBot   = Color(red: 0.28, green: 0.10, blue: 0.68)

        return ZStack(alignment: .topLeading) {
            // 背景漸層
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [accentTop, accentBot],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            // 散景裝飾圓 ①（右上大圓）
            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 110, height: 110)
                .offset(x: 240, y: -30)
                .blur(radius: 12)
            // 散景裝飾圓 ②（左下中圓）
            Circle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 70, height: 70)
                .offset(x: 18, y: 100)
                .blur(radius: 8)
            // 散景裝飾圓 ③（中右小圓）
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 55, height: 55)
                .offset(x: 175, y: 72)
                .blur(radius: 8)
            // 頂部玻璃光澤（white.opacity(0.18)→clear，top→center）
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.18), .clear],
                                     startPoint: .top, endPoint: .center))

            VStack(alignment: .leading, spacing: 14) {
                // ── 標題列 ──
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name.isEmpty ? "新增房地產" : name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.80)
                        if !city.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.circle.fill").font(.system(size: 10))
                                Text(city).font(.caption)
                            }
                            .foregroundStyle(.white.opacity(0.80))
                        }
                    }
                    Spacer()
                    if isSold {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 9))
                            Text("已售出")
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.white.opacity(0.20))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.30), lineWidth: 0.6))
                    }
                }

                // ── 購入價大字 ──
                if purchaseWan > 0 {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(purchaseWan >= 10000
                             ? String(format: "%.1f億", purchaseWan / 10000)
                             : String(format: "%.0f萬", purchaseWan))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.65)
                            .contentTransition(.numericText())
                        Text("NT$").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.70))
                    }
                } else {
                    Text("請輸入購入價格")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                }

                // ── KPI 橫列（估值 / 增值 / 月租）──
                HStack(spacing: 0) {
                    reHeroKpiCell(
                        icon: "building.2.fill",
                        label: "目前估值",
                        value: currentWan > 0
                            ? (currentWan >= 10000
                               ? String(format: "%.1f億", currentWan / 10000)
                               : String(format: "%.0f萬", currentWan))
                            : "—"
                    )
                    Divider().frame(height: 32).opacity(0.35)
                    reHeroKpiCell(
                        icon: isUp ? "arrow.up.right" : "arrow.down.right",
                        label: "增值",
                        value: (purchaseWan > 0 && currentWan > 0)
                            ? (isUp
                               ? "+\(String(format: "%.0f", apprecWan))萬"
                               : "\(String(format: "%.0f", apprecWan))萬")
                            : "—",
                        tint: (purchaseWan > 0 && currentWan > 0)
                            ? (isUp ? Color.green.opacity(0.90) : Color.red.opacity(0.90))
                            : Color.white.opacity(0.80)
                    )
                    Divider().frame(height: 32).opacity(0.35)
                    reHeroKpiCell(
                        icon: "dollarsign.circle.fill",
                        label: "月租收入",
                        // [2026-07 v3] 月租金額改用萬/億智慧量級，對齊同卡購入價/估值/增值三格已用的
                        // wan 顯示規格；monthlyRentalText 本身以「原始台幣」輸入（非萬），需自行換算，
                        // 不直接呼叫共用 ntdWanString（該函式會多帶「NT$」前綴，與同排其他三格純數字
                        // + 量級字的簡潔風格不符）。
                        value: rentalAmt > 0
                            ? (rentalAmt >= 100_000_000
                               ? String(format: "%.1f億", rentalAmt / 100_000_000)
                               : rentalAmt >= 10_000
                                 ? String(format: "%.1f萬", rentalAmt / 10_000)
                                 : "NT$\(Int(rentalAmt).formatted())")
                            : "—"
                    )
                }
                .padding(.vertical, 8)
                .background(.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.75)
        )
        .shadow(color: accentTop.opacity(0.30), radius: 16, x: 0, y: 6)
        .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
    }

    private func reHeroKpiCell(icon: String, label: String, value: String,
                                tint: Color = .white) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.08)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28)
                Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            }
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.70))
        }
        .frame(maxWidth: .infinity)
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
                        Image(systemName: "photo.slash").font(.largeTitle).foregroundStyle(.secondary)
                        Text("無法載入照片").foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
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
            }
        }
    }

    private func resetView() {
        scale = 1; lastScale = 1
        offset = .zero; lastOffset = .zero
    }
}
