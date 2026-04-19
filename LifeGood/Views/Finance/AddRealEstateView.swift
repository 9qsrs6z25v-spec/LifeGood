import SwiftUI

struct AddRealEstateView: View {
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    var editing: RealEstate?

    enum EditTab: String, CaseIterable {
        case finance = "理財"
        case house = "房屋資料"
    }
    @State private var editTab: EditTab = .finance

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

    // MARK: - 人生模式欄位
    @State private var buildingType: BuildingType = .townhouse
    @State private var pingCountText = ""
    @State private var landOwner = ""
    @State private var ownerPickerSelection = ""
    @State private var landSituation = ""
    @State private var landNumber = ""
    @State private var landAreaText = ""
    @State private var floorItems: [FloorItemState] = []

    struct FloorItemState: Identifiable {
        let id: UUID
        var floorNumber: String
        var functions: Set<FloorFunction>
    }
    @State private var waterMeterNumber = ""
    @State private var waterMeterOwner = ""
    @State private var electricityMeterNumber = ""
    @State private var electricityMeterOwner = ""
    @State private var gasMeterNumber = ""
    @State private var gasMeterOwner = ""
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

    // MARK: - 貸款項目列表

    @State private var mortgageItems: [MortgageItemState] = []

    struct MortgageItemState: Identifiable {
        let id: UUID
        var title: String
        var amountText: String
        var periodsText: String
        var startDate: Date
        var linkedExpenseId: UUID?

        var amount: Double { Double(amountText) ?? 0 }
        var periods: Int { Int(periodsText) ?? 0 }

        var elapsedPeriods: Int {
            let months = Calendar.current.dateComponents([.month], from: startDate, to: Date()).month ?? 0
            return min(max(0, months), periods)
        }
        var paidAmount: Double { amount * Double(elapsedPeriods) }
    }

    // MARK: - 已支出房屋金額列表

    @State private var paidItems: [PaidItemState] = []

    struct PaidItemState: Identifiable {
        let id: UUID
        var title: String
        var amountText: String
        var date: Date
        var linkedExpenseId: UUID?

        var amount: Double { Double(amountText) ?? 0 }
    }

    // MARK: - 變動支出列表

    @State private var variableItems: [VariableItemState] = []

    struct VariableItemState: Identifiable {
        let id: UUID
        var category: RealEstateExpenseCategory
        var amountText: String
        var date: Date
        var linkedExpenseId: UUID?

        var amount: Double { Double(amountText) ?? 0 }
    }

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
                    rentalSection
                    mortgageSection
                    paidSection
                    variableExpenseSection
                    calcSection

                    Section("備註") {
                        TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
                    }
                } else {
                    propertyDetailSection
                    landDetailSection
                    floorSection
                    utilitiesSection
                    insuranceSection
                    propertyAssetSection
                }

                if showError {
                    Section {
                        Text("請輸入物件名稱和購入價格").foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle(editing != nil ? "編輯房地產" : "新增房地產")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing != nil ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green)
                }
            }
            .onAppear { loadEditing() }
        }
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
            ForEach(Array(mortgageItems.enumerated()), id: \.element.id) { index, _ in
                VStack(spacing: 10) {
                    if index > 0 { Divider() }

                    HStack {
                        Text("貸款 \(index + 1)")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Button(role: .destructive) {
                            let item = mortgageItems[index]
                            if let linkedId = item.linkedExpenseId {
                                expenseStore.expenses.removeAll { $0.id == linkedId }
                            }
                            mortgageItems.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }

                    TextField("名稱（如 第一順位房貸）", text: $mortgageItems[index].title)

                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("每期金額", text: $mortgageItems[index].amountText)
                            .keyboardType(.decimalPad)
                    }

                    HStack {
                        TextField("總期數", text: $mortgageItems[index].periodsText)
                            .keyboardType(.numberPad)
                        Text("期").foregroundStyle(.secondary)

                        if mortgageItems[index].periods > 0 {
                            Text("(\(mortgageItems[index].periods / 12)年\(mortgageItems[index].periods % 12)月)")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }

                    DatePicker("起始日", selection: $mortgageItems[index].startDate, displayedComponents: .date)

                    if mortgageItems[index].amount > 0, mortgageItems[index].periods > 0 {
                        HStack {
                            Text("貸款總額")
                            Spacer()
                            Text(formatCurrency(mortgageItems[index].amount * Double(mortgageItems[index].periods)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("已繳")
                            Text("\(mortgageItems[index].elapsedPeriods)/\(mortgageItems[index].periods) 期")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(formatCurrency(mortgageItems[index].paidAmount))
                                .font(.caption.bold()).foregroundStyle(.blue)
                        }
                    }
                }
            }

            Button {
                mortgageItems.append(MortgageItemState(
                    id: UUID(), title: "", amountText: "", periodsText: "240", startDate: purchaseDate
                ))
            } label: {
                Label("新增貸款項目", systemImage: "plus.circle").foregroundStyle(.green)
            }
        } header: {
            Text("貸款項目")
        } footer: {
            if !mortgageItems.isEmpty {
                let monthlyTotal = mortgageItems.reduce(0.0) { $0 + $1.amount }
                Text("每月房貸合計 \(formatCurrency(monthlyTotal))，儲存後將自動連動記帳模式的固定支出。")
            } else {
                Text("可新增多筆不同利率或期數的貸款項目。")
            }
        }
    }

    // MARK: - 已支出房屋金額

    private var paidSection: some View {
        Section {
            ForEach(Array(paidItems.enumerated()), id: \.element.id) { index, _ in
                VStack(spacing: 10) {
                    if index > 0 { Divider() }

                    HStack {
                        Text("項目 \(index + 1)")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Button(role: .destructive) {
                            let item = paidItems[index]
                            if let linkedId = item.linkedExpenseId {
                                expenseStore.expenses.removeAll { $0.id == linkedId }
                            }
                            paidItems.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }

                    TextField("名稱（如 頭期款、簽約金）", text: $paidItems[index].title)

                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("金額", text: $paidItems[index].amountText)
                            .keyboardType(.decimalPad)
                    }

                    DatePicker("日期", selection: $paidItems[index].date, displayedComponents: .date)
                }
            }

            Button {
                paidItems.append(PaidItemState(
                    id: UUID(), title: "", amountText: "", date: Date()
                ))
            } label: {
                Label("新增已支出項目", systemImage: "plus.circle").foregroundStyle(.green)
            }
        } header: {
            Text("已支出房屋金額")
        } footer: {
            if !paidItems.isEmpty {
                let total = paidItems.reduce(0.0) { $0 + $1.amount }
                Text("已支出合計 \(formatCurrency(total))，儲存後將自動連動記帳模式的變動支出。")
            } else {
                Text("記錄頭期款、簽約金、工程款等已支付的房屋相關金額。")
            }
        }
    }

    // MARK: - 變動支出

    private var variableExpenseSection: some View {
        Section {
            ForEach(Array(variableItems.enumerated()), id: \.element.id) { index, _ in
                VStack(spacing: 10) {
                    if index > 0 { Divider() }

                    HStack {
                        Text("項目 \(index + 1)").font(.subheadline.weight(.medium))
                        Spacer()
                        Button(role: .destructive) {
                            let item = variableItems[index]
                            if let linkedId = item.linkedExpenseId {
                                expenseStore.expenses.removeAll { $0.id == linkedId }
                            }
                            variableItems.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }.buttonStyle(.plain)
                    }

                    Picker("類別", selection: $variableItems[index].category) {
                        ForEach(RealEstateExpenseCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }
                    DatePicker("日期", selection: $variableItems[index].date, displayedComponents: .date)
                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("金額", text: $variableItems[index].amountText).keyboardType(.decimalPad)
                    }
                }
            }

            Button {
                variableItems.append(VariableItemState(
                    id: UUID(), category: .renovation, amountText: "", date: Date()
                ))
            } label: {
                Label("新增變動支出", systemImage: "plus.circle").foregroundStyle(.green)
            }
        } header: {
            Text("變動支出")
        } footer: {
            Text("裝修、維修、家具、清潔等一次性支出。")
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

    private var landDetailSection: some View {
        Section("詳細") {
            TextField("座落", text: $landSituation)
            TextField("地號", text: $landNumber)
            HStack {
                TextField("面積", text: $landAreaText).keyboardType(.decimalPad)
                Text("㎡").foregroundStyle(.secondary)
            }
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
                        TextField("樓層編號（如 B1、1F）", text: $floorItems[index].floorNumber)
                            .font(.subheadline.weight(.medium))
                        Spacer()
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
                floorItems.append(FloorItemState(id: UUID(), floorNumber: "", functions: []))
            } label: {
                Label("新增樓層", systemImage: "plus.circle").foregroundStyle(.green)
            }
        } header: {
            Text("樓層資訊")
        }
    }

    // MARK: - 水電瓦斯（人生）

    private var utilitiesSection: some View {
        Section("水電瓦斯") {
            HStack {
                Image(systemName: "drop.fill").foregroundStyle(.blue).frame(width: 24)
                VStack(alignment: .leading, spacing: 6) {
                    TextField("水號", text: $waterMeterNumber)
                    TextField("所有權人", text: $waterMeterOwner)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            HStack {
                Image(systemName: "bolt.fill").foregroundStyle(.yellow).frame(width: 24)
                VStack(alignment: .leading, spacing: 6) {
                    TextField("電號", text: $electricityMeterNumber)
                    TextField("所有權人", text: $electricityMeterOwner)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            HStack {
                Image(systemName: "flame.fill").foregroundStyle(.orange).frame(width: 24)
                VStack(alignment: .leading, spacing: 6) {
                    TextField("瓦斯表號", text: $gasMeterNumber)
                    TextField("所有權人", text: $gasMeterOwner)
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
        let mortgageMonthly = mortgageItems.reduce(0.0) { $0 + $1.amount }
        let mortgagePaidTotal = mortgageItems.reduce(0.0) { $0 + $1.paidAmount }
        let paidTotal = paidItems.reduce(0.0) { $0 + $1.amount }
        let varTotal = variableItems.reduce(0.0) { $0 + $1.amount }
        let mortgageTotal = mortgageItems.reduce(0.0) { $0 + $1.amount * Double($1.periods) }
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
        let reId = editing?.id ?? UUID()

        // 同步貸款項目到固定支出
        var syncedMortgages: [RealEstateMortgageItem] = []
        for item in mortgageItems where item.amount > 0 {
            let expId = syncMortgageItemExpense(reId: reId, reName: trimmedName, item: item, note: trimmedNote)
            syncedMortgages.append(RealEstateMortgageItem(
                id: item.id, title: item.title.trimmingCharacters(in: .whitespaces),
                amount: item.amount, totalPeriods: item.periods,
                startDate: item.startDate, linkedExpenseId: expId
            ))
        }

        // 同步已支出金額到變動支出
        var syncedPaids: [RealEstatePaidItem] = []
        for item in paidItems where item.amount > 0 {
            let expId = syncPaidItemExpense(reId: reId, reName: trimmedName, item: item)
            syncedPaids.append(RealEstatePaidItem(
                id: item.id, title: item.title.trimmingCharacters(in: .whitespaces),
                amount: item.amount, date: item.date, linkedExpenseId: expId
            ))
        }

        // 同步變動支出
        var syncedVariable: [RealEstateVariableExpense] = []
        for item in variableItems where item.amount > 0 {
            let expId = syncVariableExpense(reId: reId, reName: trimmedName, item: item)
            syncedVariable.append(RealEstateVariableExpense(
                id: item.id, category: item.category,
                amount: item.amount, date: item.date, linkedExpenseId: expId
            ))
        }

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
            note: trimmedNote,
            buildingType: buildingType,
            pingCount: Double(pingCountText) ?? 0,
            landOwner: landOwner.trimmingCharacters(in: .whitespaces),
            landSituation: landSituation.trimmingCharacters(in: .whitespaces),
            landNumber: landNumber.trimmingCharacters(in: .whitespaces),
            landArea: Double(landAreaText) ?? 0,
            totalFloors: floorItems.count,
            fromFloor: 0,
            toFloor: 0,
            floors: floorItems.map { FloorInfo(id: $0.id, floorNumber: $0.floorNumber, functions: Array($0.functions)) },
            waterMeterNumber: waterMeterNumber.trimmingCharacters(in: .whitespaces),
            waterMeterOwner: waterMeterOwner.trimmingCharacters(in: .whitespaces),
            electricityMeterNumber: electricityMeterNumber.trimmingCharacters(in: .whitespaces),
            electricityMeterOwner: electricityMeterOwner.trimmingCharacters(in: .whitespaces),
            gasMeterNumber: gasMeterNumber.trimmingCharacters(in: .whitespaces),
            gasMeterOwner: gasMeterOwner.trimmingCharacters(in: .whitespaces),
            insuranceItems: syncedInsurance,
            propertyAssets: syncedAssets
        )
        if editing != nil { financeStore.update(re) } else { financeStore.add(re) }
        dismiss()
    }

    // MARK: - 同步函式

    private func syncMortgageItemExpense(reId: UUID, reName: String, item: MortgageItemState, note: String) -> UUID {
        let expenseId = item.linkedExpenseId ?? UUID()
        let title = item.title.isEmpty ? "\(reName) - 房貸" : "\(reName) - \(item.title)"
        let expense = Expense(
            id: expenseId, title: title, amount: item.amount, date: purchaseDate,
            expenseType: .fixed, fixedCategory: .loan, recurrence: .monthly,
            loanSubCategory: .mortgage, linkedRealEstateId: reId, note: note
        )
        if item.linkedExpenseId != nil { expenseStore.update(expense) }
        else { expenseStore.add(expense) }
        return expenseId
    }

    private func syncPaidItemExpense(reId: UUID, reName: String, item: PaidItemState) -> UUID {
        let expenseId = item.linkedExpenseId ?? UUID()
        let title = item.title.isEmpty ? "\(reName) - 已付款" : "\(reName) - \(item.title)"
        let expense = Expense(
            id: expenseId, title: title, amount: item.amount, date: item.date,
            expenseType: .variable, variableCategory: .realEstate,
            linkedRealEstateId: reId,
            realEstateExpenseCategory: .housePayment, note: ""
        )
        if item.linkedExpenseId != nil { expenseStore.update(expense) }
        else { expenseStore.add(expense) }
        return expenseId
    }

    private func syncVariableExpense(reId: UUID, reName: String, item: VariableItemState) -> UUID {
        let expenseId = item.linkedExpenseId ?? UUID()
        let expense = Expense(
            id: expenseId, title: "\(reName) - \(item.category.rawValue)",
            amount: item.amount, date: item.date,
            expenseType: .variable, variableCategory: .realEstate,
            linkedRealEstateId: reId,
            realEstateExpenseCategory: item.category, note: ""
        )
        if item.linkedExpenseId != nil { expenseStore.update(expense) }
        else { expenseStore.add(expense) }
        return expenseId
    }

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

        mortgageItems = e.mortgageItems.map { m in
            MortgageItemState(
                id: m.id, title: m.title,
                amountText: m.amount > 0 ? String(format: "%.0f", m.amount) : "",
                periodsText: m.totalPeriods > 0 ? "\(m.totalPeriods)" : "",
                startDate: m.startDate,
                linkedExpenseId: m.linkedExpenseId
            )
        }

        paidItems = e.paidItems.map { p in
            PaidItemState(
                id: p.id, title: p.title,
                amountText: p.amount > 0 ? String(format: "%.0f", p.amount) : "",
                date: p.date, linkedExpenseId: p.linkedExpenseId
            )
        }

        variableItems = e.variableExpenses.map { ve in
            VariableItemState(
                id: ve.id, category: ve.category,
                amountText: ve.amount > 0 ? String(format: "%.0f", ve.amount) : "",
                date: ve.date, linkedExpenseId: ve.linkedExpenseId
            )
        }

        // 人生模式欄位
        buildingType = e.buildingType
        pingCountText = e.pingCount > 0 ? String(format: "%g", e.pingCount) : ""
        landOwner = e.landOwner
        if ownerCandidates.contains(e.landOwner) {
            ownerPickerSelection = e.landOwner
        }
        landSituation = e.landSituation
        landNumber = e.landNumber
        landAreaText = e.landArea > 0 ? String(format: "%g", e.landArea) : ""
        floorItems = e.floors.map { f in
            FloorItemState(id: f.id, floorNumber: f.floorNumber, functions: Set(f.functions))
        }
        waterMeterNumber = e.waterMeterNumber
        waterMeterOwner = e.waterMeterOwner
        electricityMeterNumber = e.electricityMeterNumber
        electricityMeterOwner = e.electricityMeterOwner
        gasMeterNumber = e.gasMeterNumber
        gasMeterOwner = e.gasMeterOwner

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

    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "NT$0"
    }
}
