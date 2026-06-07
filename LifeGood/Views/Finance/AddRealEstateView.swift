import SwiftUI
import PhotosUI

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
                infoSection

                Picker("", selection: $editTab) {
                    ForEach(EditTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if editTab == .finance {
                    valueSection
                    if showRental { rentalSection }
                    if showMortgage { mortgageSection }
                    if showPaid { paidSection }
                    if showVariable { variableExpenseSection }
                    calcSection

                    Section("備註") {
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
                        Text("請輸入物件名稱和購入價格").foregroundStyle(.red).font(.caption)
                    }
                }
            }
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
            .onAppear { loadEditing() }
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
        Section("物件資訊") {
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
            ForEach(storeMortgageItems) { m in
                Button {
                    if let expId = m.linkedExpenseId,
                       let exp = expenseStore.expenses.first(where: { $0.id == expId }) {
                        editingExpense = exp
                    }
                } label: {
                    HStack {
                        Image(systemName: "building.columns.fill")
                            .font(.caption).foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.title.isEmpty ? "房貸" : m.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            HStack(spacing: 6) {
                                if m.totalPeriods > 0 {
                                    Text("\(m.elapsedPeriods)/\(m.totalPeriods) 期")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Text(formatCurrency(m.paidAmount))
                                    .font(.caption2).foregroundStyle(.blue)
                            }
                        }
                        Spacer()
                        Text(formatCurrency(m.amount))
                            .font(.subheadline.bold())
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
                Label("新增貸款項目", systemImage: "plus.circle").foregroundStyle(.green)
            }
        } header: {
            Text("貸款項目")
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
                    HStack {
                        Image(systemName: "banknote.fill")
                            .font(.caption).foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.title.isEmpty ? "房屋價金" : p.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(fmtDate(p.date))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(formatCurrency(p.amount))
                            .font(.subheadline.bold())
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
            Text("已支出房屋金額")
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
                    HStack {
                        Label(ve.category.rawValue, systemImage: ve.category.icon)
                            .font(.subheadline.weight(.medium))
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.orange.opacity(0.12))
                            .foregroundStyle(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 2) {
                            if !ve.name.isEmpty {
                                Text(ve.name).font(.caption).foregroundStyle(.primary)
                            }
                            Text(fmtDate(ve.date))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(formatCurrency(ve.amount))
                            .font(.subheadline.bold())
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
                Label("新增變動支出", systemImage: "plus.circle").foregroundStyle(.green)
            }
        } header: {
            Text("變動支出")
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
        ForEach(Array(landDeedItems.enumerated()), id: \.element.id) { index, _ in
            Section {
                TextField("坐落", text: $landDeedItems[index].situation)
                TextField("地號", text: $landDeedItems[index].number)
                HStack {
                    TextField("面積", text: $landDeedItems[index].areaText).keyboardType(.decimalPad)
                    Text("㎡").foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Text("土地權狀 \(index + 1)")
                    Spacer()
                    Button { landDeedItems.remove(at: index) } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                    }.buttonStyle(.plain)
                }
            }
        }

        ForEach(Array(bldgDeedItems.enumerated()), id: \.element.id) { index, _ in
            Section {
                TextField("坐落", text: $bldgDeedItems[index].situation)
                TextField("建號", text: $bldgDeedItems[index].number)
                TextField("門牌", text: $bldgDeedItems[index].address)
                Toggle("填入完工日", isOn: $bldgDeedItems[index].hasCompletionDate)
                if bldgDeedItems[index].hasCompletionDate {
                    DatePicker("完工日", selection: $bldgDeedItems[index].completionDate, displayedComponents: .date)
                }
                TextField("用途", text: $bldgDeedItems[index].usage)
                TextField("附屬建物", text: $bldgDeedItems[index].annex)
                HStack {
                    TextField("面積", text: $bldgDeedItems[index].areaText).keyboardType(.decimalPad)
                    Text("㎡").foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Text("建物權狀 \(index + 1)")
                    Spacer()
                    Button { bldgDeedItems.remove(at: index) } label: {
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
            ForEach(Array(elevatorItems.enumerated()), id: \.element.id) { index, item in
                HStack {
                    Text("保養 \(index + 1)").font(.subheadline.weight(.medium))
                        .frame(width: 56, alignment: .leading)

                    DatePicker("", selection: $elevatorItems[index].date, displayedComponents: .date)
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
                            Task {
                                if let data = try? await newItem.loadTransferable(type: Data.self) {
                                    let fileName = ElevatorMaintenance.savePhoto(data, id: item.id)
                                    elevatorItems[index].photoFileName = fileName
                                }
                            }
                        }
                    ), matching: .images) {
                        Image(systemName: item.photoFileName == nil ? "photo.badge.plus" : "arrow.triangle.2.circlepath.camera")
                            .font(.title3).foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        if let fn = elevatorItems[index].photoFileName {
                            ElevatorMaintenance.deletePhoto(fn)
                        }
                        elevatorItems.remove(at: index)
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

            ForEach(Array(floorItems.enumerated()), id: \.element.id) { index, _ in
                VStack(spacing: 8) {
                    HStack {
                        TextField("樓層（如 B1、1F）", text: $floorItems[index].floorNumber)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                        Divider()
                        HStack {
                            TextField("面積", text: $floorItems[index].areaText)
                                .keyboardType(.decimalPad)
                                .frame(width: 60)
                            Text("㎡").foregroundStyle(.secondary).font(.caption)
                        }
                        Button(role: .destructive) {
                            floorItems.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }.buttonStyle(.plain)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                        ForEach(FloorFunction.allCases) { fn in
                            let isOn = floorItems[index].functions.contains(fn)
                            Button {
                                if isOn { floorItems[index].functions.remove(fn) }
                                else { floorItems[index].functions.insert(fn) }
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
            ForEach(Array(insuranceItems.enumerated()), id: \.element.id) { index, _ in
                VStack(spacing: 10) {
                    if index > 0 { Divider() }

                    HStack {
                        Text("保險 \(index + 1)").font(.subheadline.weight(.medium))
                        Spacer()
                        Button(role: .destructive) {
                            let item = insuranceItems[index]
                            if let linkedId = item.linkedExpenseId {
                                expenseStore.expenses.removeAll { $0.id == linkedId }
                            }
                            insuranceItems.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }.buttonStyle(.plain)
                    }

                    TextField("火災地震險號", text: $insuranceItems[index].policyNumber)

                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("價格", text: $insuranceItems[index].amountText)
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
            ForEach(Array(assetItems.enumerated()), id: \.element.id) { index, _ in
                VStack(spacing: 10) {
                    if index > 0 { Divider() }

                    HStack {
                        Text("資產 \(index + 1)").font(.subheadline.weight(.medium))
                        Spacer()
                        Button(role: .destructive) {
                            let item = assetItems[index]
                            if let linkedId = item.linkedExpenseId {
                                expenseStore.expenses.removeAll { $0.id == linkedId }
                            }
                            assetItems.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }.buttonStyle(.plain)
                    }

                    Picker("類別", selection: $assetItems[index].category) {
                        ForEach(RealEstateExpenseCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }

                    TextField("名稱", text: $assetItems[index].name)
                    TextField("廠牌", text: $assetItems[index].brand)
                    TextField("位置樓層", text: $assetItems[index].floorLocation)

                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("價格", text: $assetItems[index].amountText)
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
                if let eid = saleExpId { expenseStore.expenses.removeAll { $0.id == eid }; saleExpId = nil }
            } else {
                saleExpId = syncSaleExpense(reId: reId, name: trimmedName, loss: abs(pl), date: soldDate, existingId: saleExpId)
                if let iid = saleIncId { expenseStore.incomes.removeAll { $0.id == iid }; saleIncId = nil }
            }
        } else {
            if let eid = saleExpId { expenseStore.expenses.removeAll { $0.id == eid }; saleExpId = nil }
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
        for index in offsets {
            let item = items[index]
            if let expId = item.linkedExpenseId {
                expenseStore.expenses.removeAll { $0.id == expId }
            }
            re.mortgageItems.removeAll { $0.id == item.id }
        }
        financeStore.update(re)
    }

    private func deletePaidItems(at offsets: IndexSet) {
        guard var re = currentEstate else { return }
        let items = re.paidItems
        for index in offsets {
            let item = items[index]
            if let expId = item.linkedExpenseId {
                expenseStore.expenses.removeAll { $0.id == expId }
            }
            re.paidItems.removeAll { $0.id == item.id }
        }
        financeStore.update(re)
    }

    private func deleteVariableItems(at offsets: IndexSet) {
        guard var re = currentEstate else { return }
        let items = re.variableExpenses
        for index in offsets {
            let item = items[index]
            if let expId = item.linkedExpenseId {
                expenseStore.expenses.removeAll { $0.id == expId }
            }
            re.variableExpenses.removeAll { $0.id == item.id }
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
        let waterParts = e.waterMeterNumber.split(separator: "-").map(String.init)
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
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct PhotoViewerSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            Group {
                if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
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
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.slash").font(.largeTitle).foregroundStyle(.secondary)
                        Text("無法載入照片").foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .navigationTitle("照片瀏覽")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if scale > 1 {
                        Button {
                            withAnimation(.spring(duration: 0.3)) { resetView() }
                        } label: {
                            Image(systemName: "arrow.counterclockwise.circle")
                                .foregroundStyle(.white)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("關閉") { dismiss() }
                }
            }
        }
    }

    private func resetView() {
        scale = 1; lastScale = 1
        offset = .zero; lastOffset = .zero
    }
}
