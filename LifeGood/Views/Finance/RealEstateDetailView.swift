import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import QuickLook

struct RealEstateDetailView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    let estateId: UUID
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var viewingPhotoURL: URL?
    @State private var addingElevatorMaintenance = false
    @State private var editingElevatorMaintenance: ElevatorMaintenance?
    @State private var addingUtilityPayment = false
    @State private var editingUtilityPayment: UtilityPayment?
    @State private var utilityExpanded = false
    @State private var addingRenovationPhoto = false
    @State private var editingRenovationPhoto: RenovationPhoto?
    @State private var bulkRenovationPickerItems: [PhotosPickerItem] = []
    @State private var showBulkRenovationPicker = false
    /// 批次匯入後等待輸入日期/標題的暫存檔名（傳給 RenovationPhotoEditor）
    @State private var pendingBulkPhotoNames: [String]? = nil
    /// 房屋資料集錦中點任何一張照片，都用這個 cute viewer 呈現
    @State private var cutePhotoDraft: CutePhotoDraft?
    /// 文件上傳 picker
    @State private var showDocumentPicker = false
    /// 點擊文件後 QuickLook 預覽
    @State private var previewingDocumentURL: IdentifiableURL?
    @State private var showPremiumAlert = false
    /// 已展開備註的變動支出項目 IDs
    @State private var expandedVariableExpenseIds: Set<UUID> = []
    /// 用於在子 sheet 關閉後強制刷新水電瓦斯區塊（解決 SwiftUI 巢狀 sheet 偶爾不更新的問題）
    @State private var dataRefreshID = UUID()

    // MARK: - 收合狀態（理財分頁）
    /// 試算章節預設展開
    @State private var calcSectionExpanded = true
    @State private var mortgageSectionExpanded = false
    @State private var paidSectionExpanded = false
    @State private var variableSectionExpanded = false
    @State private var incomeSectionExpanded = false

    // MARK: - 直接從卡片新增支出項目
    @State private var addingMortgageItem = false
    @State private var addingPaidItem = false
    @State private var addingVariableCategory: RealEstateExpenseCategory?
    /// 點章節項目時開啟編輯該筆 Expense
    @State private var editingLinkedExpense: Expense?

    enum DetailTab: String, CaseIterable {
        case finance = "理財"
        case house = "房屋資料"
    }
    @State private var detailTab: DetailTab = .finance

    private var estate: RealEstate {
        store.realEstates.first(where: { $0.id == estateId }) ?? placeholder
    }

    private let placeholder = RealEstate(name: "")

    init(estate: RealEstate) {
        self.estateId = estate.id
    }

    private var rarity: CardRarity { CardRarity.realEstate(price: estate.purchasePrice) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    flashCard
                    tabPicker
                    if detailTab == .finance {
                        infoSection
                    } else {
                        houseInfoSection
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("房地產卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            if subscription.isPremium { showEdit = true }
                            else { showPremiumAlert = true }
                        } label: {
                            Text("編輯").foregroundStyle(.green)
                        }
                        Button {
                            if subscription.isPremium { showDeleteConfirm = true }
                            else { showPremiumAlert = true }
                        } label: {
                            Text("刪除").foregroundStyle(.red)
                        }
                    }
                }
            }
            .sheet(isPresented: $showEdit) {
                AddRealEstateView(editing: estate)
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .sheet(item: $viewingPhotoURL) { url in
                PhotoViewerSheet(url: url)
            }
            .sheet(isPresented: $addingElevatorMaintenance,
                   onDismiss: { dataRefreshID = UUID() }) {
                ElevatorMaintenanceEditor(estateId: estateId, editing: nil)
            }
            .sheet(item: $editingElevatorMaintenance,
                   onDismiss: { dataRefreshID = UUID() }) { m in
                ElevatorMaintenanceEditor(estateId: estateId, editing: m)
            }
            .sheet(isPresented: $addingUtilityPayment,
                   onDismiss: { dataRefreshID = UUID() }) {
                UtilityPaymentEditor(estateId: estateId, editing: nil)
            }
            .sheet(item: $editingUtilityPayment,
                   onDismiss: { dataRefreshID = UUID() }) { p in
                UtilityPaymentEditor(estateId: estateId, editing: p)
            }
            .sheet(isPresented: $addingRenovationPhoto,
                   onDismiss: { dataRefreshID = UUID() }) {
                RenovationPhotoEditor(estateId: estateId, editing: nil)
            }
            .sheet(item: $editingRenovationPhoto,
                   onDismiss: { dataRefreshID = UUID() }) { p in
                RenovationPhotoEditor(estateId: estateId, editing: p)
            }
            .sheet(isPresented: Binding(
                get: { pendingBulkPhotoNames != nil },
                set: { if !$0 { pendingBulkPhotoNames = nil } }
            ), onDismiss: { dataRefreshID = UUID() }) {
                if let names = pendingBulkPhotoNames {
                    RenovationPhotoEditor(estateId: estateId, editing: nil, preloadedFileNames: names)
                }
            }
            .sheet(item: $cutePhotoDraft) { draft in
                CutePhotoViewer(draft: draft)
            }
            .sheet(item: $previewingDocumentURL) { wrapper in
                DocumentQuickLookView(url: wrapper.url)
            }
            .sheet(isPresented: $addingMortgageItem, onDismiss: { dataRefreshID = UUID() }) {
                AddExpenseView(
                    expenseType: .fixed,
                    preset: AddExpensePreset(
                        fixedCategory: .loan,
                        loanSubCategory: .mortgage,
                        recurrence: .monthly,
                        linkedRealEstateId: estateId,
                        mortgageLinkExisting: true
                    )
                )
            }
            .sheet(isPresented: $addingPaidItem, onDismiss: { dataRefreshID = UUID() }) {
                AddExpenseView(
                    expenseType: .variable,
                    preset: AddExpensePreset(
                        variableCategory: .realEstate,
                        realEstateExpenseCategory: .housePayment,
                        linkedRealEstateId: estateId,
                        assetLink: .realEstate,
                        realEstateLinkExisting: true
                    )
                )
            }
            .sheet(item: $addingVariableCategory, onDismiss: { dataRefreshID = UUID() }) { cat in
                AddExpenseView(
                    expenseType: .variable,
                    preset: AddExpensePreset(
                        variableCategory: .realEstate,
                        realEstateExpenseCategory: cat,
                        linkedRealEstateId: estateId,
                        assetLink: .realEstate,
                        realEstateLinkExisting: true
                    )
                )
            }
            .sheet(item: $editingLinkedExpense, onDismiss: { dataRefreshID = UUID() }) { exp in
                AddExpenseView(expenseType: exp.expenseType, editingExpense: exp)
            }
            .alert("確定要刪除這筆房地產嗎？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) {
                    deleteEstate()
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("刪除後所有連結的記帳支出也會一併移除，此操作無法復原。")
            }
        }
    }

    // MARK: - 閃卡主體

    private var flashCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text(rarity.label)
                    .font(.caption2.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(rarity.textColor)
                Spacer()
                Label("房地產", systemImage: "building.2.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(rarity == .legendary ? .yellow : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            VStack(spacing: 6) {
                Text(estate.name)
                    .font(.title.weight(.bold))
                    .foregroundStyle(rarity == .legendary ? .white : .primary)
                    .multilineTextAlignment(.center)

                if !estate.fullAddress.isEmpty {
                    Text(estate.fullAddress)
                        .font(.subheadline)
                        .foregroundStyle(rarity == .legendary ? .white.opacity(0.7) : .secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
            }
            .padding(.top, 16)
            .padding(.horizontal, 24)

            VStack(spacing: 4) {
                Text("\(fmtWan(estate.currentValue))")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(rarity.textColor)
                Text("萬元")
                    .font(.subheadline)
                    .foregroundStyle(rarity == .legendary ? .white.opacity(0.6) : .secondary)
            }
            .padding(.vertical, 20)

            HStack {
                VStack(spacing: 2) {
                    Text("購入")
                        .font(.caption2).foregroundStyle(rarity == .legendary ? Color.white.opacity(0.5) : Color(UIColor.tertiaryLabel))
                    Text("\(fmtWan(estate.purchasePrice)) 萬")
                        .font(.caption.bold()).foregroundStyle(rarity == .legendary ? Color.white.opacity(0.8) : Color.primary)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("增值率")
                        .font(.caption2).foregroundStyle(rarity == .legendary ? Color.white.opacity(0.5) : Color(UIColor.tertiaryLabel))
                    Text(String(format: "%@%.1f%%", estate.appreciationRate >= 0 ? "+" : "", estate.appreciationRate))
                        .font(.caption.bold()).foregroundStyle(estate.appreciationRate >= 0 ? .green : .red)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("月租")
                        .font(.caption2).foregroundStyle(rarity == .legendary ? Color.white.opacity(0.5) : Color(UIColor.tertiaryLabel))
                    Text(estate.monthlyRental > 0 ? fmt(estate.monthlyRental) : "—")
                        .font(.caption.bold()).foregroundStyle(rarity == .legendary ? Color.white.opacity(0.8) : Color.primary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(
            LinearGradient(colors: rarity.bgGradient,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    AngularGradient(colors: rarity.borderGradient, center: .center),
                    lineWidth: rarity.borderWidth
                )
        )
        .shadow(color: rarity.shadowColor, radius: rarity == .legendary ? 15 : 8, y: 4)
        .overlay(alignment: .topLeading) {
            if estate.isSold {
                SoldStamp(size: 32)
                    .offset(x: -10, y: -14)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    // MARK: - 詳細資訊

    @ViewBuilder
    private var calcSummary: some View {
        let rental = estate.monthlyRental
        let mortgageMonthly = estate.monthlyMortgage
        let mortgageTotal = estate.totalMortgageAmount
        let mortgagePaidTotal = estate.totalMortgagePaid
        let paidTotal = estate.totalPaid
        let varTotal = estate.variableTotal
        let allPaid = paidTotal + mortgagePaidTotal + varTotal

        if rental > 0 || mortgageMonthly > 0 || paidTotal > 0 || varTotal > 0 {
            collapsibleSection(
                title: "試算",
                summary: fmt(allPaid),
                summaryColor: .red,
                isExpanded: $calcSectionExpanded
            ) {
                VStack(spacing: 0) {
                    if rental > 0 || mortgageMonthly > 0 {
                        calcRow("每月淨現金流", fmt(rental - mortgageMonthly),
                                color: rental - mortgageMonthly >= 0 ? .green : .red)
                    }
                    if mortgageTotal > 0 {
                        calcRow("貸款總額", fmt(mortgageTotal), color: .secondary)
                    }
                    if mortgagePaidTotal > 0 {
                        calcRow("已繳貸款金額", fmt(mortgagePaidTotal), color: .blue)
                    }
                    if paidTotal > 0 {
                        calcRow("已支出房屋金額", fmt(paidTotal), color: .purple)
                    }
                    if varTotal > 0 {
                        calcRow("變動支出累計", fmt(varTotal), color: .orange)
                    }
                    HStack {
                        Text("房屋總已支出").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(fmt(allPaid)).font(.subheadline.bold()).foregroundStyle(.red)
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                }
            }
        }
    }

    private func calcRow(_ label: String, _ value: String, color: Color) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.bold()).foregroundStyle(color)
        }
        .padding(.horizontal).padding(.vertical, 6)
    }

    private var infoSection: some View {
        VStack(spacing: 0) {
            calcSummary

            collapsibleSection(
                title: "貸款明細 (\(estate.mortgageItems.count) 筆)",
                summary: estate.mortgageItems.isEmpty ? nil : "已繳 " + fmt(estate.totalMortgagePaid),
                summaryColor: .blue,
                isExpanded: $mortgageSectionExpanded,
                trailing: {
                    Button {
                        if subscription.isPremium { addingMortgageItem = true }
                        else { showPremiumAlert = true }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.subheadline).foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                }
            ) {
                if estate.mortgageItems.isEmpty {
                    emptySectionRow("尚無貸款項目")
                } else {
                    ForEach(estate.mortgageItems.sorted { $0.startDate > $1.startDate }) { m in
                        SwipeableRow(
                            onCopy: { duplicateMortgageItem(m) },
                            onDelete: { deleteMortgageItem(m) }
                        ) {
                            HStack {
                                Text(m.title.isEmpty ? "房貸" : m.title)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundStyle(.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                Text("\(m.elapsedPeriods)/\(m.totalPeriods) 期")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text(fmt(m.amount) + "/月").font(.subheadline.bold())
                            }
                            .padding(.horizontal).padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .onTapGesture { openLinkedExpense(id: m.linkedExpenseId) }
                        }
                    }
                    HStack {
                        Text("已繳貸款").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(fmt(estate.totalMortgagePaid))
                            .font(.subheadline.bold()).foregroundStyle(.blue)
                    }
                    .padding(.horizontal).padding(.vertical, 6)
                }
            }

            let paidTotal = estate.paidItems.reduce(0.0) { $0 + $1.amount }
            collapsibleSection(
                title: "已支出 (\(estate.paidItems.count) 筆)",
                summary: estate.paidItems.isEmpty ? nil : fmt(paidTotal),
                summaryColor: .purple,
                isExpanded: $paidSectionExpanded,
                trailing: {
                    Button {
                        if subscription.isPremium { addingPaidItem = true }
                        else { showPremiumAlert = true }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.subheadline).foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                }
            ) {
                if estate.paidItems.isEmpty {
                    emptySectionRow("尚無已支出項目")
                } else {
                    ForEach(estate.paidItems.sorted { $0.date > $1.date }) { p in
                        SwipeableRow(
                            onCopy: { duplicatePaidItem(p) },
                            onDelete: { deletePaidItem(p) }
                        ) {
                            HStack(alignment: .top) {
                                Text(p.title.isEmpty ? "已付款" : p.title)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.1))
                                    .foregroundStyle(.purple)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(fmt(p.amount)).font(.subheadline.bold())
                                    Text(fmtDate(p.date))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal).padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .onTapGesture { openLinkedExpense(id: p.linkedExpenseId) }
                        }
                    }
                }
            }

            variableExpensesContent

            if estate.monthlyRental > 0 {
                let flow = estate.monthlyCashFlow
                collapsibleSection(
                    title: "收益",
                    summary: fmt(flow) + "/月",
                    summaryColor: flow >= 0 ? .green : .red,
                    isExpanded: $incomeSectionExpanded
                ) {
                    HStack {
                        Text("月淨現金流").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(fmt(flow))
                            .font(.subheadline.bold())
                            .foregroundStyle(flow >= 0 ? .green : .red)
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                    HStack {
                        Text("年租金報酬率").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2f%%", estate.rentalYield))
                            .font(.subheadline.bold()).foregroundStyle(.blue)
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                }
            }
        }
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    @ViewBuilder
    private var variableExpensesContent: some View {
        collapsibleSection(
            title: "變動支出 (\(estate.variableExpenses.count) 筆)",
            summary: estate.variableExpenses.isEmpty ? nil : fmt(estate.variableTotal),
            summaryColor: .orange,
            isExpanded: $variableSectionExpanded,
            trailing: {
                Menu {
                    ForEach(RealEstateExpenseCategory.allCases.filter { $0 != .housePayment }) { cat in
                        Button {
                            if subscription.isPremium { addingVariableCategory = cat }
                            else { showPremiumAlert = true }
                        } label: {
                            Label(cat.rawValue, systemImage: cat.icon)
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.subheadline).foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            }
        ) {
            if estate.variableExpenses.isEmpty {
                emptySectionRow("尚無變動支出")
            } else {
                ForEach(estate.variableExpenses.sorted { $0.date > $1.date }) { ve in
                    SwipeableRow(
                        onCopy: { duplicateVariableExpenseItem(ve) },
                        onDelete: { deleteVariableExpenseItem(ve) }
                    ) {
                        HStack(alignment: .top) {
                            Text(ve.category.rawValue)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.1))
                                .foregroundStyle(.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            if !ve.name.isEmpty {
                                Text(ve.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Spacer()
                            }
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(fmt(ve.amount)).font(.subheadline.bold())
                                Text(fmtDate(ve.date))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal).padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .onTapGesture { openLinkedExpense(id: ve.linkedExpenseId) }
                    }
                }
            }
        }
    }

    private func emptySectionRow(_ text: String) -> some View {
        HStack {
            Text(text).font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal).padding(.vertical, 6)
    }

    // MARK: - 分頁選擇器

    private var tabPicker: some View {
        Picker("", selection: $detailTab) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    // MARK: - 房屋資料（人生）

    private var houseInfoSection: some View {
        VStack(spacing: 0) {
            let hasProperty = estate.pingCount > 0 || !estate.landOwner.isEmpty

            if hasProperty {
                sectionHeader("房屋資料")
                if estate.pingCount > 0 { infoRow("坪數", String(format: "%g 坪", estate.pingCount)) }
                if !estate.landOwner.isEmpty { infoRow("所有權人", estate.landOwner) }
            }

            if !estate.landDeeds.isEmpty || !estate.buildingDeeds.isEmpty {
                ForEach(Array(estate.landDeeds.enumerated()), id: \.element.id) { i, d in
                    sectionHeader("土地權狀\(estate.landDeeds.count > 1 ? " \(i + 1)" : "")")
                    if !d.situation.isEmpty { infoRow("坐落", d.situation) }
                    if !d.number.isEmpty { infoRow("地號", d.number) }
                    if d.area > 0 { infoRow("面積", String(format: "%g ㎡", d.area)) }
                }
                ForEach(Array(estate.buildingDeeds.enumerated()), id: \.element.id) { i, d in
                    sectionHeader("建物權狀\(estate.buildingDeeds.count > 1 ? " \(i + 1)" : "")")
                    if !d.situation.isEmpty { infoRow("坐落", d.situation) }
                    if !d.number.isEmpty { infoRow("建號", d.number) }
                    if !d.address.isEmpty { infoRow("門牌", d.address) }
                    if let cd = d.completionDate {
                        infoRow("完工日", fmtDate(cd))
                    }
                    if !d.usage.isEmpty { infoRow("用途", d.usage) }
                    if !d.annex.isEmpty { infoRow("附屬建物", d.annex) }
                    if d.area > 0 { infoRow("面積", String(format: "%g ㎡", d.area)) }
                }
            }

            if !estate.floors.isEmpty {
                buildingVisualization
            }

            // 樓層下方：裝潢照片
            renovationPhotosContent

            if estate.hasElevator {
                sectionHeaderWithAdd("電梯資料") { addingElevatorMaintenance = true }
                if estate.elevatorMaintenances.isEmpty {
                    HStack {
                        Text("尚無保養記錄").font(.caption).foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.horizontal).padding(.vertical, 6)
                } else {
                    ForEach(estate.elevatorMaintenances) { m in
                        Button { editingElevatorMaintenance = m } label: {
                            HStack {
                                Image(systemName: "wrench.and.screwdriver")
                                    .font(.caption).foregroundStyle(.blue)
                                Text(fmtDate(m.date))
                                    .font(.subheadline).foregroundStyle(.primary)
                                Spacer()
                                if m.photoFileName != nil {
                                    Button {
                                        if let url = m.photoURL {
                                            viewingPhotoURL = url
                                        }
                                    } label: {
                                        Image(systemName: "photo.fill")
                                            .font(.caption).foregroundStyle(.blue)
                                    }
                                    .buttonStyle(.plain)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal).padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            let hasUtilities = !estate.waterMeterNumber.isEmpty || !estate.waterMeterOwner.isEmpty
                || !estate.electricityMeterNumber.isEmpty || !estate.electricityMeterOwner.isEmpty
                || !estate.gasMeterNumber.isEmpty || !estate.gasMeterOwner.isEmpty || !estate.gasUserNumber.isEmpty
                || !estate.utilityPayments.isEmpty
                || !estate.extraMeters.isEmpty

            if hasUtilities {
                utilitiesContent
                    .id(dataRefreshID)
            }

            if !estate.insuranceItems.isEmpty {
                sectionHeader("保險項目")
                ForEach(estate.insuranceItems) { ins in
                    HStack {
                        Image(systemName: "shield.fill").foregroundStyle(.indigo)
                        Text(ins.policyNumber.isEmpty ? "未填險號" : ins.policyNumber)
                            .font(.subheadline)
                            .foregroundStyle(ins.policyNumber.isEmpty ? .tertiary : .primary)
                        Spacer()
                        if ins.amount > 0 {
                            Text(fmt(ins.amount)).font(.subheadline.bold()).foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                }
            }

            if !estate.propertyAssets.isEmpty {
                sectionHeader("房屋附屬資產")
                ForEach(estate.propertyAssets) { asset in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(asset.category.rawValue)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.1))
                                .foregroundStyle(.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text(asset.name.isEmpty ? "—" : asset.name)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if asset.amount > 0 {
                                Text(fmt(asset.amount)).font(.subheadline.bold()).foregroundStyle(.orange)
                            }
                        }
                        HStack(spacing: 10) {
                            if !asset.brand.isEmpty {
                                Text("廠牌 \(asset.brand)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            if !asset.floorLocation.isEmpty {
                                Text("位置 \(asset.floorLocation)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                }
            }

            let hasDeeds = !estate.landDeeds.isEmpty || !estate.buildingDeeds.isEmpty
            if !hasProperty && !hasDeeds && estate.floors.isEmpty && !hasUtilities && estate.insuranceItems.isEmpty && estate.propertyAssets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36)).foregroundStyle(.tertiary)
                    Text("尚未填寫房屋資料").font(.subheadline).foregroundStyle(.secondary)
                    Text("點擊下方編輯按鈕填寫").font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            }
        }
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - 建物立體圖

    private static let cyanColor = Color(red: 0, green: 0.85, blue: 1.0)

    private var sortedFloors: [FloorInfo] {
        estate.floors.sorted { floorOrder($0) < floorOrder($1) }
    }

    private func floorOrder(_ f: FloorInfo) -> Int {
        let s = f.floorNumber.uppercased()
            .replacingOccurrences(of: "F", with: "")
            .replacingOccurrences(of: "樓", with: "")
            .trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("B") { return -(Int(s.dropFirst()) ?? 0) }
        return Int(s) ?? 0
    }

    private var buildingVisualization: some View {
        HolographicBuildingView(
            floors: sortedFloors,
            isApartment: estate.buildingType != .townhouse
        )
        .shadow(color: Self.cyanColor.opacity(0.25), radius: 10)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.medium))
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    // MARK: - 房屋資料集錦（裝潢照片 + 關聯支出照片 + PDF / PPT / Excel 等文件）

    /// 集錦區塊的 header：含「+」Menu（拍照 / 批次多選 / 上傳文件）
    private var renovationSectionHeader: some View {
        HStack {
            Text("房屋資料集錦").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button {
                    if subscription.isPremium { addingRenovationPhoto = true }
                    else { showPremiumAlert = true }
                } label: {
                    Label("新增單張照片（含描述）", systemImage: "photo")
                }
                Button {
                    if subscription.isPremium { showBulkRenovationPicker = true }
                    else { showPremiumAlert = true }
                } label: {
                    Label("批次匯入多張照片", systemImage: "photo.on.rectangle.angled")
                }
                Divider()
                Button {
                    if subscription.isPremium { showDocumentPicker = true }
                    else { showPremiumAlert = true }
                } label: {
                    Label("上傳文件 (PDF / PPT / Excel…)", systemImage: "doc.badge.plus")
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.subheadline).foregroundStyle(.green)
            }
        }
        .padding(.horizontal).padding(.top, 12).padding(.bottom, 4)
        .photosPicker(isPresented: $showBulkRenovationPicker,
                      selection: $bulkRenovationPickerItems,
                      maxSelectionCount: 0,
                      matching: .images)
        .onChange(of: bulkRenovationPickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importBulkRenovationPhotos(items) }
        }
        .fileImporter(
            isPresented: $showDocumentPicker,
            allowedContentTypes: [
                .pdf, .presentation, .spreadsheet, .text, .commaSeparatedText,
                .plainText, .rtf, .image, .data
            ],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                importDocuments(urls)
            }
        }
    }

    /// 把多選相片寫入磁碟後，開 RenovationPhotoEditor 讓使用者輸入日期/標題/備註，
    /// 一次匯入成「一筆」RenovationPhoto，這些照片會以堆疊方式顯示。
    @MainActor
    private func importBulkRenovationPhotos(_ items: [PhotosPickerItem]) async {
        var fileNames: [String] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            fileNames.append(RenovationPhoto.savePhoto(data, id: UUID()))
        }
        bulkRenovationPickerItems = []
        guard !fileNames.isEmpty else { return }
        pendingBulkPhotoNames = fileNames
    }

    /// 該房地產關聯的、有附照片的支出（變動 + 固定皆含）
    private var linkedExpensePhotos: [Expense] {
        expenseStore.expenses
            .filter { $0.linkedRealEstateId == estateId && !$0.photoFileNames.isEmpty }
    }

    @ViewBuilder
    private var renovationPhotosContent: some View {
        renovationSectionHeader

        let renovationItems = estate.renovationPhotos.map { HousePhotoItem.renovation($0) }
        let expenseItems = linkedExpensePhotos.map { HousePhotoItem.expense($0) }
        let documentItems = estate.documents.map { HousePhotoItem.document($0) }
        let allItems = (renovationItems + expenseItems + documentItems).sorted { $0.date > $1.date }

        if allItems.isEmpty {
            HStack {
                Text("尚無房屋資料").font(.caption).foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal).padding(.vertical, 6)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(allItems) { item in
                        Button {
                            handleHousePhotoTap(item)
                        } label: {
                            housePhotoCard(item)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if case .renovation(let p) = item.kind {
                                Button {
                                    editingRenovationPhoto = p
                                } label: {
                                    Label("編輯資訊", systemImage: "pencil")
                                }
                            }
                            if case .document(let d) = item.kind {
                                Button(role: .destructive) {
                                    deleteDocument(d)
                                } label: {
                                    Label("刪除文件", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
    }

    private func handleHousePhotoTap(_ item: HousePhotoItem) {
        switch item.kind {
        case .renovation(let p):
            guard !p.photoFileNames.isEmpty else {
                editingRenovationPhoto = p
                return
            }
            let urls = p.photoFileNames.map { RenovationPhoto.photoURL(for: $0) }
            let title = p.title.isEmpty ? "裝潢紀錄" : p.title
            cutePhotoDraft = CutePhotoDraft(
                urls: urls,
                title: title,
                note: p.note,
                date: p.date,
                kind: .renovation
            )
        case .expense(let e):
            guard !e.photoFileNames.isEmpty else { return }
            let urls = e.photoFileNames.map { Expense.photoURL(for: $0) }
            let trimmedNote = e.note.trimmingCharacters(in: .whitespaces)
            let title: String = {
                if !trimmedNote.isEmpty { return trimmedNote }
                return e.title.isEmpty ? "支出照片" : e.title
            }()
            cutePhotoDraft = CutePhotoDraft(
                urls: urls,
                title: title,
                note: (trimmedNote.isEmpty || trimmedNote == title) ? "" : trimmedNote,
                date: e.date,
                kind: .expense
            )
        case .document(let d):
            previewingDocumentURL = IdentifiableURL(url: d.fileURL)
        }
    }

    private func housePhotoCard(_ item: HousePhotoItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if case .document(let d) = item.kind {
                documentThumbnail(for: d)
            } else if item.fileNames.count >= 2 {
                stackedHousePhotos(fileNames: item.fileNames, urlFor: item.urlForFileName)
            } else if let url = item.primaryURL {
                renovationSinglePhoto(url: url)
            } else {
                renovationSinglePhoto(url: nil)
            }
            HStack(spacing: 4) {
                Image(systemName: item.badgeIcon)
                    .font(.system(size: 9))
                    .foregroundStyle(item.badgeColor)
                Text(item.displayTitle)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .frame(width: 130, alignment: .leading)
            Text(fmtDate(item.date))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(8)
    }

    /// 文件縮圖卡片：大張的彩色 icon + 副檔名標籤，與照片卡片同尺寸
    private func documentThumbnail(for doc: RealEstateDocument) -> some View {
        let ext = (doc.fileName as NSString).pathExtension.uppercased()
        return ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 10)
                .fill(doc.iconColor.opacity(0.12))
                .frame(width: 130, height: 100)
            VStack(spacing: 6) {
                Image(systemName: doc.icon)
                    .font(.system(size: 38))
                    .foregroundStyle(doc.iconColor)
                if !ext.isEmpty {
                    Text(ext)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(doc.iconColor)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(doc.iconColor.opacity(0.18))
                        .clipShape(Capsule())
                }
            }
            .frame(width: 130, height: 100)
        }
        .frame(width: 130, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 文件匯入 / 刪除

    private func importDocuments(_ urls: [URL]) {
        guard var estate = store.realEstates.first(where: { $0.id == estateId }) else { return }
        for url in urls {
            if let doc = RealEstateDocument.importDocument(from: url) {
                estate.documents.append(doc)
            }
        }
        store.update(estate)
        dataRefreshID = UUID()
    }

    private func deleteDocument(_ doc: RealEstateDocument) {
        guard var estate = store.realEstates.first(where: { $0.id == estateId }) else { return }
        RealEstateDocument.deleteDocument(doc.fileName)
        estate.documents.removeAll { $0.id == doc.id }
        store.update(estate)
        dataRefreshID = UUID()
    }

    /// 通用堆疊照片視圖：用一個 urlFor 閉包來支援 RenovationPhoto / Expense 兩種來源
    private func stackedHousePhotos(fileNames: [String], urlFor: (String) -> URL) -> some View {
        let visible = Array(fileNames.prefix(3))
        return ZStack {
            if visible.count >= 3 {
                stackedHousePhotoLayer(url: urlFor(visible[2]))
                    .rotationEffect(.degrees(7))
                    .offset(x: 7, y: 4)
                    .opacity(0.85)
            }
            if visible.count >= 2 {
                stackedHousePhotoLayer(url: urlFor(visible[1]))
                    .rotationEffect(.degrees(-5))
                    .offset(x: -4, y: 2)
                    .opacity(0.92)
            }
            stackedHousePhotoLayer(url: urlFor(visible[0]))

            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 3) {
                        Image(systemName: "square.stack.3d.up.fill").font(.system(size: 10))
                        Text("\(fileNames.count)").font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Capsule())
                    .padding(6)
                }
                Spacer()
            }
            .frame(width: 130, height: 100)
        }
        .frame(width: 140, height: 110)
    }

    @ViewBuilder
    private func stackedHousePhotoLayer(url: URL) -> some View {
        Group {
            if let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill))
            }
        }
        .frame(width: 130, height: 100)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
    }

    private func renovationPhotoCard(_ p: RenovationPhoto) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if p.photoFileNames.count >= 2 {
                renovationStackedPhotos(for: p.photoFileNames)
            } else {
                renovationSinglePhoto(url: p.photoURL)
            }
            Text(displayTitle(for: p))
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(width: 130, alignment: .leading)
            Text(fmtDate(p.date))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(8)
    }

    /// 顯示用標題：使用者填的 title 優先；多張時 fallback 到「N 張照片」
    private func displayTitle(for p: RenovationPhoto) -> String {
        if !p.title.isEmpty { return p.title }
        if p.photoFileNames.count >= 2 { return "\(p.photoFileNames.count) 張照片" }
        return "未命名"
    }

    /// 單張照片卡片（同舊版）
    @ViewBuilder
    private func renovationSinglePhoto(url: URL?) -> some View {
        if let url = url, let img = UIImage(contentsOfFile: url.path) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 130, height: 100)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onTapGesture { viewingPhotoURL = url }
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 130, height: 100)
                .overlay(
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                )
        }
    }

    /// 多張照片堆疊卡片：3 張往後遞減旋轉位移，最上層放第一張，右上角徽章顯示總張數
    private func renovationStackedPhotos(for fileNames: [String]) -> some View {
        let visible = Array(fileNames.prefix(3))
        return ZStack {
            // 最後一張（背景）
            if visible.count >= 3 {
                stackedPhotoLayer(visible[2])
                    .rotationEffect(.degrees(7))
                    .offset(x: 7, y: 4)
                    .opacity(0.85)
            }
            // 中間
            if visible.count >= 2 {
                stackedPhotoLayer(visible[1])
                    .rotationEffect(.degrees(-5))
                    .offset(x: -4, y: 2)
                    .opacity(0.92)
            }
            // 最上層封面
            stackedPhotoLayer(visible[0])

            // 數量徽章
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 3) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 10))
                        Text("\(fileNames.count)")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Capsule())
                    .padding(6)
                }
                Spacer()
            }
            .frame(width: 130, height: 100)
        }
        .frame(width: 140, height: 110)
    }

    @ViewBuilder
    private func stackedPhotoLayer(_ name: String) -> some View {
        let url = RenovationPhoto.photoURL(for: name)
        Group {
            if let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill))
            }
        }
        .frame(width: 130, height: 100)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
    }

    @ViewBuilder
    private var utilitiesContent: some View {
        sectionHeaderWithAdd("水電瓦斯") { addingUtilityPayment = true }

        // 水（主表）
        if !estate.waterMeterNumber.isEmpty || !estate.waterMeterOwner.isEmpty {
            utilityRow(icon: "drop.fill", color: .blue,
                       number: estate.waterMeterNumber, owner: estate.waterMeterOwner,
                       numberLabel: "水號")
        }
        // 額外的水表
        ForEach(estate.extraMeters.filter { $0.type == .water }) { m in
            extraMeterRow(m)
        }
        latestPaymentRow(type: .water)

        // 電（主表）
        if !estate.electricityMeterNumber.isEmpty || !estate.electricityMeterOwner.isEmpty {
            utilityRow(icon: "bolt.fill", color: .yellow,
                       number: estate.electricityMeterNumber, owner: estate.electricityMeterOwner,
                       numberLabel: "電號")
        }
        ForEach(estate.extraMeters.filter { $0.type == .electricity }) { m in
            extraMeterRow(m)
        }
        latestPaymentRow(type: .electricity)

        // 瓦斯（主表）
        if !estate.gasUserNumber.isEmpty || !estate.gasMeterNumber.isEmpty || !estate.gasMeterOwner.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill").foregroundStyle(.orange).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        if !estate.gasUserNumber.isEmpty {
                            Text("用戶編號 \(estate.gasUserNumber)").font(.caption2).foregroundStyle(.secondary)
                        }
                        if !estate.gasMeterNumber.isEmpty {
                            Text("表號 \(estate.gasMeterNumber)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !estate.gasMeterOwner.isEmpty {
                        Text(estate.gasMeterOwner).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
        ForEach(estate.extraMeters.filter { $0.type == .gas }) { m in
            extraMeterRow(m)
        }
        latestPaymentRow(type: .gas)

        // 展開：顯示所有歷史繳費紀錄
        let allPayments = estate.utilityPayments.sorted { $0.date > $1.date }
        let olderPayments = allPayments.filter { p in
            !isLatestPayment(p)
        }
        if utilityExpanded {
            if !olderPayments.isEmpty {
                Divider().padding(.horizontal)
                ForEach(olderPayments) { p in
                    paymentRow(p)
                }
            }
        }
        if !olderPayments.isEmpty {
            Button {
                withAnimation { utilityExpanded.toggle() }
            } label: {
                HStack {
                    Spacer()
                    Image(systemName: utilityExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                    Text(utilityExpanded ? "收起歷史紀錄" : "展開歷史紀錄（\(olderPayments.count) 筆）")
                        .font(.caption.weight(.medium))
                    Spacer()
                }
                .foregroundStyle(.green)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func extraMeterRow(_ m: UtilityMeter) -> some View {
        let color: Color = {
            switch m.type {
            case .water: return .blue
            case .electricity: return .yellow
            case .gas: return .orange
            }
        }()
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: m.type.icon).foregroundStyle(color).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if !m.label.isEmpty {
                        Text(m.label)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(color.opacity(0.12))
                            .foregroundStyle(color)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    if !m.userNumber.isEmpty {
                        Text("用戶編號 \(m.userNumber)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if !m.meterNumber.isEmpty {
                    let label: String = {
                        switch m.type {
                        case .water: return "水號"
                        case .electricity: return "電號"
                        case .gas: return "表號"
                        }
                    }()
                    Text("\(label) \(m.meterNumber)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !m.owner.isEmpty {
                Text(m.owner).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal).padding(.vertical, 6)
    }

    private func utilityRow(icon: String, color: Color, number: String, owner: String, numberLabel: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(numberLabel).font(.caption2).foregroundStyle(.secondary)
                    Text(number.isEmpty ? "—" : number).font(.subheadline.weight(.medium))
                }
                if !owner.isEmpty {
                    Text("所有權人：\(owner)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    // MARK: - 輔助

    /// 該類型最新一筆繳費
    private func latestPayment(for type: UtilityType) -> UtilityPayment? {
        estate.utilityPayments
            .filter { $0.type == type }
            .sorted { $0.date > $1.date }
            .first
    }

    private func isLatestPayment(_ p: UtilityPayment) -> Bool {
        for t in UtilityType.allCases {
            if let latest = latestPayment(for: t), latest.id == p.id { return true }
        }
        return false
    }

    @ViewBuilder
    private func latestPaymentRow(type: UtilityType) -> some View {
        if let p = latestPayment(for: type) {
            Button { editingUtilityPayment = p } label: {
                HStack(spacing: 8) {
                    Rectangle().fill(Color.clear).frame(width: 20)
                    Text(fmtDate(p.date)).font(.caption2).foregroundStyle(.tertiary)
                    if p.photoFileName != nil {
                        Button {
                            if let url = p.photoURL { viewingPhotoURL = url }
                        } label: {
                            Image(systemName: "photo.fill").font(.caption2).foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Text(fmt(p.amount))
                        .font(.caption.bold()).foregroundStyle(.red)
                    Image(systemName: "chevron.right")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.horizontal).padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func paymentRow(_ p: UtilityPayment) -> some View {
        Button { editingUtilityPayment = p } label: {
            HStack {
                Image(systemName: p.type.icon)
                    .font(.caption).foregroundStyle(utilityColor(p.type)).frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.type.rawValue).font(.caption.weight(.medium)).foregroundStyle(.primary)
                    Text(fmtDate(p.date)).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                if p.photoFileName != nil {
                    Button {
                        if let url = p.photoURL { viewingPhotoURL = url }
                    } label: {
                        Image(systemName: "photo.fill").font(.caption).foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
                Text(fmt(p.amount))
                    .font(.subheadline.bold()).foregroundStyle(.red)
                Image(systemName: "chevron.right")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func utilityColor(_ type: UtilityType) -> Color {
        switch type {
        case .water: return .blue
        case .electricity: return .yellow
        case .gas: return .orange
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal).padding(.top, 12).padding(.bottom, 4)
    }

    /// 可收合區塊：未展開時顯示摘要金額；點 header 切換展開
    @ViewBuilder
    private func collapsibleSection<Content: View>(
        title: String,
        summary: String?,
        summaryColor: Color = .secondary,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        collapsibleSection(
            title: title, summary: summary, summaryColor: summaryColor,
            isExpanded: isExpanded,
            trailing: { EmptyView() },
            content: content
        )
    }

    /// 可收合區塊（含右側自訂按鈕，例：「+」新增鈕、Menu 等）
    @ViewBuilder
    private func collapsibleSection<Content: View, Trailing: View>(
        title: String,
        summary: String?,
        summaryColor: Color = .secondary,
        isExpanded: Binding<Bool>,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack {
                    Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if let summary, !isExpanded.wrappedValue {
                        Text(summary)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(summaryColor)
                    }
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            trailing()
        }
        .padding(.horizontal).padding(.top, 12).padding(.bottom, 4)

        if isExpanded.wrappedValue {
            content()
        }
    }

    private func sectionHeaderWithAdd(_ title: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            Button {
                if subscription.isPremium { action() }
                else { showPremiumAlert = true }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.subheadline).foregroundStyle(.green)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal).padding(.top, 12).padding(.bottom, 4)
    }

    private func deleteEstate() {
        for m in estate.mortgageItems {
            if let linkedId = m.linkedExpenseId {
                expenseStore.expenses.removeAll { $0.id == linkedId }
            }
        }
        for p in estate.paidItems {
            if let linkedId = p.linkedExpenseId {
                expenseStore.expenses.removeAll { $0.id == linkedId }
            }
        }
        for ve in estate.variableExpenses {
            if let linkedId = ve.linkedExpenseId {
                expenseStore.expenses.removeAll { $0.id == linkedId }
            }
        }
        for ins in estate.insuranceItems {
            if let linkedId = ins.linkedExpenseId {
                expenseStore.expenses.removeAll { $0.id == linkedId }
            }
        }
        for asset in estate.propertyAssets {
            if let linkedId = asset.linkedExpenseId {
                expenseStore.expenses.removeAll { $0.id == linkedId }
            }
        }
        for up in estate.utilityPayments {
            if let linkedId = up.linkedExpenseId {
                expenseStore.expenses.removeAll { $0.id == linkedId }
            }
            if let name = up.photoFileName { UtilityPayment.deletePhoto(name) }
        }
        // 清除裝潢照片檔案（多張）
        for rp in estate.renovationPhotos {
            for name in rp.photoFileNames { RenovationPhoto.deletePhoto(name) }
        }
        if let linkedId = estate.linkedExpenseId {
            expenseStore.expenses.removeAll { $0.id == linkedId }
        }
        if let saleExpId = estate.saleLinkedExpenseId {
            expenseStore.expenses.removeAll { $0.id == saleExpId }
        }
        if let saleIncId = estate.saleLinkedIncomeId {
            expenseStore.incomes.removeAll { $0.id == saleIncId }
        }
        store.deleteRealEstate(estate)
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "NT$0"
    }

    private func fmtWan(_ v: Double) -> String {
        String(format: "%g", v / 10000)
    }

    private func fmtDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: d)
    }

    // MARK: - 章節項目：點擊編輯 / 複製 / 刪除

    /// 依 linkedExpenseId 查找對應的 Expense（找不到時 sheet 不會開啟）
    private func openLinkedExpense(id: UUID?) {
        guard let id, let exp = expenseStore.expenses.first(where: { $0.id == id }) else { return }
        editingLinkedExpense = exp
    }

    /// 移除指定 Expense 與其所有 side-effects（房地產項目、銀行扣款、信用卡連結等）
    private func deleteLinkedExpense(_ expense: Expense) {
        if var re = store.realEstates.first(where: { $0.id == estateId }) {
            re.mortgageItems.removeAll { $0.linkedExpenseId == expense.id }
            re.paidItems.removeAll { $0.linkedExpenseId == expense.id }
            re.variableExpenses.removeAll { $0.linkedExpenseId == expense.id }
            store.update(re)
        }
        if let bankId = expense.linkedBankMilestoneId,
           var ms = lifeStore.milestones.first(where: { $0.id == bankId }) {
            ms.bankDeposits?.removeAll { $0.linkedExpenseId == expense.id }
            lifeStore.update(ms)
        }
        expenseStore.expenses.removeAll { $0.id == expense.id }
    }

    /// 複製一個 Expense（新 id、日期改為今天）並重新觸發房地產 / 銀行同步
    private func duplicateLinkedExpense(_ source: Expense) {
        let newId = UUID()
        let copy = Expense(
            id: newId,
            title: source.title,
            amount: source.amount,
            date: Date(),
            expenseType: source.expenseType,
            variableCategory: source.variableCategory,
            fixedCategory: source.fixedCategory,
            recurrence: source.recurrence,
            insuranceSubCategory: source.insuranceSubCategory,
            loanSubCategory: source.loanSubCategory,
            linkedInsuranceId: source.linkedInsuranceId,
            linkedStockId: source.linkedStockId,
            linkedRealEstateId: source.linkedRealEstateId,
            linkedVehicleId: source.linkedVehicleId,
            vehicleExpenseCategory: source.vehicleExpenseCategory,
            realEstateExpenseCategory: source.realEstateExpenseCategory,
            taxSavingSubCategory: source.taxSavingSubCategory,
            socialSubCategory: source.socialSubCategory,
            socialRecipient: source.socialRecipient,
            taxDeductibleOverride: source.taxDeductibleOverride,
            note: source.note,
            currencyCode: source.currencyCode,
            diningMember: source.diningMember,
            linkedBankMilestoneId: source.linkedBankMilestoneId,
            linkedBankCurrency: source.linkedBankCurrency,
            linkedCreditCardMilestoneId: source.linkedCreditCardMilestoneId,
            placeAddress: source.placeAddress,
            placeLatitude: source.placeLatitude,
            placeLongitude: source.placeLongitude,
            photoFileNames: source.photoFileNames
        )
        expenseStore.expenses.append(copy)
        // 房地產項目層級同步：依原本 source 出現在哪個陣列，clone 一份新項目
        if var re = store.realEstates.first(where: { $0.id == estateId }) {
            if let m = re.mortgageItems.first(where: { $0.linkedExpenseId == source.id }) {
                re.mortgageItems.append(RealEstateMortgageItem(
                    id: UUID(), title: m.title, amount: m.amount,
                    totalPeriods: m.totalPeriods, startDate: Date(),
                    linkedExpenseId: newId
                ))
            }
            if let p = re.paidItems.first(where: { $0.linkedExpenseId == source.id }) {
                re.paidItems.append(RealEstatePaidItem(
                    id: UUID(), title: p.title, amount: p.amount,
                    date: Date(), linkedExpenseId: newId
                ))
            }
            if let v = re.variableExpenses.first(where: { $0.linkedExpenseId == source.id }) {
                re.variableExpenses.append(RealEstateVariableExpense(
                    id: UUID(), category: v.category, name: v.name,
                    amount: v.amount, date: Date(), linkedExpenseId: newId
                ))
            }
            store.update(re)
        }
        // 銀行扣款由 syncBankWithdrawal 模式自動接管（週期性會虛擬展開，
        // 一次性會由原 Expense 流程處理；這裡未走 AddExpenseView 故手動處理一次性）
        if copy.linkedCreditCardMilestoneId == nil,
           !(copy.expenseType == .fixed && copy.recurrence != nil),
           let bankId = copy.linkedBankMilestoneId,
           var ms = lifeStore.milestones.first(where: { $0.id == bankId }) {
            var list = ms.bankDeposits ?? []
            list.append(BankDeposit(
                id: UUID(), date: copy.date, amount: copy.amount,
                currencyCode: copy.linkedBankCurrency ?? "NT$",
                isWithdrawal: true, linkedExpenseId: copy.id
            ))
            ms.bankDeposits = list
            lifeStore.update(ms)
        }
    }

    // 三個分頁各自的入口

    private func deleteMortgageItem(_ m: RealEstateMortgageItem) {
        if let expId = m.linkedExpenseId,
           let exp = expenseStore.expenses.first(where: { $0.id == expId }) {
            deleteLinkedExpense(exp)
        } else if var re = store.realEstates.first(where: { $0.id == estateId }) {
            re.mortgageItems.removeAll { $0.id == m.id }
            store.update(re)
        }
    }

    private func duplicateMortgageItem(_ m: RealEstateMortgageItem) {
        if let expId = m.linkedExpenseId,
           let exp = expenseStore.expenses.first(where: { $0.id == expId }) {
            duplicateLinkedExpense(exp)
        }
    }

    private func deletePaidItem(_ p: RealEstatePaidItem) {
        if let expId = p.linkedExpenseId,
           let exp = expenseStore.expenses.first(where: { $0.id == expId }) {
            deleteLinkedExpense(exp)
        } else if var re = store.realEstates.first(where: { $0.id == estateId }) {
            re.paidItems.removeAll { $0.id == p.id }
            store.update(re)
        }
    }

    private func duplicatePaidItem(_ p: RealEstatePaidItem) {
        if let expId = p.linkedExpenseId,
           let exp = expenseStore.expenses.first(where: { $0.id == expId }) {
            duplicateLinkedExpense(exp)
        }
    }

    private func deleteVariableExpenseItem(_ v: RealEstateVariableExpense) {
        if let expId = v.linkedExpenseId,
           let exp = expenseStore.expenses.first(where: { $0.id == expId }) {
            deleteLinkedExpense(exp)
        } else if var re = store.realEstates.first(where: { $0.id == estateId }) {
            re.variableExpenses.removeAll { $0.id == v.id }
            store.update(re)
        }
    }

    private func duplicateVariableExpenseItem(_ v: RealEstateVariableExpense) {
        if let expId = v.linkedExpenseId,
           let exp = expenseStore.expenses.first(where: { $0.id == expId }) {
            duplicateLinkedExpense(exp)
        }
    }
}

// MARK: - 章節項目向左滑動顯示複製 / 刪除

/// 房地產卡片章節項目用的可滑動 row：向左拖曳露出複製 / 刪除按鈕。
/// content 內可放 .onTapGesture 來開啟編輯頁面。
fileprivate struct SwipeableRow<Content: View>: View {
    let content: Content
    let onCopy: () -> Void
    let onDelete: () -> Void

    init(
        onCopy: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.onCopy = onCopy
        self.onDelete = onDelete
        self.content = content()
    }

    private let actionWidth: CGFloat = 64
    private var revealOffset: CGFloat { -(actionWidth * 2) }

    @State private var offset: CGFloat = 0
    @State private var settledOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            // 滑開後露出的按鈕
            HStack(spacing: 0) {
                Spacer()
                Button {
                    close()
                    onCopy()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "doc.on.doc.fill").font(.system(size: 16))
                        Text("複製").font(.caption2.bold())
                    }
                    .foregroundStyle(.white)
                    .frame(width: actionWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.blue)
                }
                .buttonStyle(.plain)
                Button {
                    close()
                    onDelete()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "trash.fill").font(.system(size: 16))
                        Text("刪除").font(.caption2.bold())
                    }
                    .foregroundStyle(.white)
                    .frame(width: actionWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.red)
                }
                .buttonStyle(.plain)
            }

            // 前景內容
            content
                .background(Color(.systemBackground))
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            let proposed = settledOffset + value.translation.width
                            if proposed > 0 {
                                // 不允許向右拉超過 0（過 0 加阻尼）
                                offset = proposed / 4
                            } else if proposed < revealOffset {
                                // 過頭加阻尼
                                offset = revealOffset + (proposed - revealOffset) / 3
                            } else {
                                offset = proposed
                            }
                        }
                        .onEnded { value in
                            let predicted = settledOffset + value.predictedEndTranslation.width
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                offset = predicted < revealOffset / 2 ? revealOffset : 0
                                settledOffset = offset
                            }
                        }
                )
        }
        .clipped()
    }

    private func close() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            offset = 0
            settledOffset = 0
        }
    }
}

// MARK: - 電梯保養編輯

struct ElevatorMaintenanceEditor: View {
    @EnvironmentObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss

    let estateId: UUID
    let editing: ElevatorMaintenance?

    @State private var date = Date()
    @State private var photoFileName: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("保養記錄") {
                    DatePicker("保養日期", selection: $date, displayedComponents: .date)

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        HStack {
                            Image(systemName: "photo")
                            Text(photoFileName == nil ? "選擇照片" : "更換照片")
                            Spacer()
                            if photoFileName != nil {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }
                    if photoFileName != nil {
                        Button(role: .destructive) {
                            if let name = photoFileName { ElevatorMaintenance.deletePhoto(name) }
                            photoFileName = nil
                        } label: {
                            Label("移除照片", systemImage: "xmark.circle")
                        }
                    }
                }

                if editing != nil {
                    Section {
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("刪除此記錄", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "新增保養記錄" : "編輯保養記錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") { save() }.bold().foregroundStyle(.green)
                }
            }
            .onAppear {
                if let e = editing {
                    date = e.date
                    photoFileName = e.photoFileName
                }
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    if let item, let data = try? await item.loadTransferable(type: Data.self) {
                        let id = editing?.id ?? UUID()
                        photoFileName = ElevatorMaintenance.savePhoto(data, id: id)
                    }
                }
            }
            .alert("確定刪除？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) { deleteRecord() }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private func save() {
        guard var estate = store.realEstates.first(where: { $0.id == estateId }) else { return }
        let recordId = editing?.id ?? UUID()
        let record = ElevatorMaintenance(id: recordId, date: date, photoFileName: photoFileName)
        if let idx = estate.elevatorMaintenances.firstIndex(where: { $0.id == recordId }) {
            estate.elevatorMaintenances[idx] = record
        } else {
            estate.elevatorMaintenances.append(record)
        }
        store.update(estate)
        dismiss()
    }

    private func deleteRecord() {
        guard var estate = store.realEstates.first(where: { $0.id == estateId }),
              let e = editing else { return }
        if let name = e.photoFileName { ElevatorMaintenance.deletePhoto(name) }
        estate.elevatorMaintenances.removeAll { $0.id == e.id }
        store.update(estate)
        dismiss()
    }
}

// MARK: - 水電瓦斯繳費編輯

struct UtilityPaymentEditor: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let estateId: UUID
    let editing: UtilityPayment?

    @State private var type: UtilityType = .water
    @State private var date = Date()
    @State private var amountText = ""
    @State private var note = ""
    @State private var photoFileName: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var showDeleteConfirm = false
    @State private var showError = false
    @State private var selectedBankMilestoneId: UUID?
    @State private var selectedBankCurrency: String = "NT$"
    @State private var selectedCreditCardMilestoneId: UUID?

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

    private var hasPaymentTargets: Bool {
        !bankMilestones.isEmpty || !creditCardMilestones.isEmpty
    }

    private var bankPickerLabel: String {
        if let id = selectedCreditCardMilestoneId,
           let card = creditCardMilestones.first(where: { $0.id == id }) {
            return card.cardName ?? card.title
        }
        if let id = selectedBankMilestoneId,
           let ms = bankMilestones.first(where: { $0.id == id }) {
            let name = ms.bankName ?? ms.title
            return "\(name) · \(selectedBankCurrency)"
        }
        return "未選擇"
    }

    private func bankCurrencies(for ms: LifeMilestone) -> [String] {
        let codes = (ms.bankDeposits ?? [])
            .filter { !$0.isWithdrawal }
            .map(\.currencyCode)
        var unique: [String] = []
        for c in codes where !unique.contains(c) { unique.append(c) }
        return unique.isEmpty ? ["NT$"] : unique
    }

    @ViewBuilder
    private func bankSubMenu(for ms: LifeMilestone) -> some View {
        let name = ms.bankName ?? ms.title
        let currencies = bankCurrencies(for: ms)
        if currencies.count > 1 {
            Menu(name) {
                ForEach(currencies, id: \.self) { code in
                    Button(code) {
                        selectedBankMilestoneId = ms.id
                        selectedBankCurrency = code
                        selectedCreditCardMilestoneId = nil
                    }
                }
            }
        } else {
            Button(name) {
                selectedBankMilestoneId = ms.id
                selectedBankCurrency = currencies.first ?? "NT$"
                selectedCreditCardMilestoneId = nil
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    Picker("類型", selection: $type) {
                        ForEach(UtilityType.allCases) { t in
                            Label(t.rawValue, systemImage: t.icon).tag(t)
                        }
                    }
                    DatePicker("繳費日期", selection: $date, displayedComponents: .date)
                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("金額", text: $amountText).keyboardType(.decimalPad)
                    }
                }

                if hasPaymentTargets {
                    Section {
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
                                            bankSubMenu(for: ms)
                                        }
                                    }
                                }
                                if !creditCardMilestones.isEmpty {
                                    Section("信用卡") {
                                        ForEach(creditCardMilestones) { card in
                                            Button(card.cardName ?? card.title) {
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
                    } footer: {
                        Text("選擇扣款銀行或信用卡，繳費會自動連動該帳戶圖表。")
                    }
                }

                Section("收據照片") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        HStack {
                            Image(systemName: "photo")
                            Text(photoFileName == nil ? "選擇照片" : "更換照片")
                            Spacer()
                            if photoFileName != nil {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }
                    if photoFileName != nil {
                        Button(role: .destructive) {
                            if let name = photoFileName { UtilityPayment.deletePhoto(name) }
                            photoFileName = nil
                        } label: {
                            Label("移除照片", systemImage: "xmark.circle")
                        }
                    }
                }

                Section("備註") {
                    TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
                }

                if editing != nil {
                    Section {
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("刪除此記錄", systemImage: "trash")
                        }
                    }
                }

                if showError {
                    Section {
                        Text("請輸入有效金額").foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle(editing == nil ? "新增繳費紀錄" : "編輯繳費紀錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") { save() }.bold().foregroundStyle(.green)
                }
            }
            .onAppear {
                if let e = editing {
                    type = e.type
                    date = e.date
                    amountText = e.amount > 0 ? String(format: "%.0f", e.amount) : ""
                    note = e.note
                    photoFileName = e.photoFileName
                    // 載入既有的扣款目標（從連結的 Expense 讀回）
                    if let expId = e.linkedExpenseId,
                       let exp = expenseStore.expenses.first(where: { $0.id == expId }) {
                        selectedBankMilestoneId = exp.linkedBankMilestoneId
                        selectedBankCurrency = exp.linkedBankCurrency ?? "NT$"
                        selectedCreditCardMilestoneId = exp.linkedCreditCardMilestoneId
                    }
                }
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    if let item, let data = try? await item.loadTransferable(type: Data.self) {
                        let id = editing?.id ?? UUID()
                        photoFileName = UtilityPayment.savePhoto(data, id: id)
                    }
                }
            }
            .alert("確定刪除？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) { deleteRecord() }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private func save() {
        guard let amount = Double(amountText), amount > 0 else {
            showError = true; return
        }
        guard var estate = store.realEstates.first(where: { $0.id == estateId }) else { return }
        let recordId = editing?.id ?? UUID()

        // 取得舊的支出（用於同步銀行扣款時還原舊紀錄）
        let previousExpense: Expense? = {
            guard let id = editing?.linkedExpenseId else { return nil }
            return expenseStore.expenses.first(where: { $0.id == id })
        }()

        // 同步建立 / 更新對應的變動支出（含扣款目標）
        let expenseId = editing?.linkedExpenseId ?? UUID()
        let expenseTitle = "\(estate.name) - \(type.rawValue)"
        let expense = Expense(
            id: expenseId,
            title: expenseTitle,
            amount: amount,
            date: date,
            expenseType: .variable,
            variableCategory: .realEstate,
            linkedRealEstateId: estate.id,
            realEstateExpenseCategory: .utility,
            note: note.trimmingCharacters(in: .whitespaces),
            linkedBankMilestoneId: selectedBankMilestoneId,
            linkedBankCurrency: selectedBankMilestoneId != nil ? selectedBankCurrency : nil,
            linkedCreditCardMilestoneId: selectedCreditCardMilestoneId
        )
        if editing?.linkedExpenseId != nil {
            expenseStore.update(expense)
        } else {
            expenseStore.add(expense)
        }
        syncBankWithdrawal(for: expense, previous: previousExpense)

        let record = UtilityPayment(
            id: recordId, type: type, date: date, amount: amount,
            photoFileName: photoFileName,
            note: note.trimmingCharacters(in: .whitespaces),
            linkedExpenseId: expenseId
        )
        if let idx = estate.utilityPayments.firstIndex(where: { $0.id == recordId }) {
            estate.utilityPayments[idx] = record
        } else {
            estate.utilityPayments.append(record)
        }
        store.update(estate)
        dismiss()
    }

    private func deleteRecord() {
        guard var estate = store.realEstates.first(where: { $0.id == estateId }),
              let e = editing else { return }
        if let name = e.photoFileName { UtilityPayment.deletePhoto(name) }
        // 同步移除對應的變動支出與銀行扣款紀錄
        if let linkedId = e.linkedExpenseId {
            if let exp = expenseStore.expenses.first(where: { $0.id == linkedId }),
               let bankId = exp.linkedBankMilestoneId,
               var ms = lifeStore.milestones.first(where: { $0.id == bankId }) {
                ms.bankDeposits?.removeAll { $0.linkedExpenseId == linkedId }
                lifeStore.update(ms)
            }
            expenseStore.expenses.removeAll { $0.id == linkedId }
        }
        estate.utilityPayments.removeAll { $0.id == e.id }
        store.update(estate)
        dismiss()
    }

    /// 同步銀行扣款紀錄（與 AddExpenseView 同邏輯）
    private func syncBankWithdrawal(for expense: Expense, previous: Expense?) {
        // 移除舊的銀行扣款紀錄
        if let prevBankId = previous?.linkedBankMilestoneId,
           var oldMs = lifeStore.milestones.first(where: { $0.id == prevBankId }) {
            oldMs.bankDeposits?.removeAll { $0.linkedExpenseId == expense.id }
            lifeStore.update(oldMs)
        }
        // 信用卡扣款不寫入 BankDeposit；改在顯示時依月份彙總
        guard expense.linkedCreditCardMilestoneId == nil else { return }
        // 寫入新的銀行扣款紀錄
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
}

// MARK: - 房屋照片集錦：彙整裝潢 + 關聯支出照片

fileprivate enum HousePhotoItem: Identifiable {
    case renovation(RenovationPhoto)
    case expense(Expense)
    case document(RealEstateDocument)

    var id: String {
        switch self {
        case .renovation(let p): return "r-\(p.id.uuidString)"
        case .expense(let e): return "e-\(e.id.uuidString)"
        case .document(let d): return "d-\(d.id.uuidString)"
        }
    }

    var kind: HousePhotoItem { self }

    var date: Date {
        switch self {
        case .renovation(let p): return p.date
        case .expense(let e): return e.date
        case .document(let d): return d.date
        }
    }

    /// 顯示用標題
    var displayTitle: String {
        switch self {
        case .renovation(let p):
            if !p.title.isEmpty { return p.title }
            if p.photoFileNames.count >= 2 { return "\(p.photoFileNames.count) 張照片" }
            return "未命名"
        case .expense(let e):
            let trimmedNote = e.note.trimmingCharacters(in: .whitespaces)
            if !trimmedNote.isEmpty { return trimmedNote }
            return e.title.isEmpty ? "支出照片" : e.title
        case .document(let d):
            if !d.displayName.isEmpty { return d.displayName }
            return "文件"
        }
    }

    var fileNames: [String] {
        switch self {
        case .renovation(let p): return p.photoFileNames
        case .expense(let e): return e.photoFileNames
        case .document: return []   // 文件不是圖片堆疊
        }
    }

    var primaryURL: URL? {
        guard let name = fileNames.first else { return nil }
        return urlForFileName(name)
    }

    func urlForFileName(_ name: String) -> URL {
        switch self {
        case .renovation: return RenovationPhoto.photoURL(for: name)
        case .expense: return Expense.photoURL(for: name)
        case .document(let d): return d.fileURL
        }
    }

    /// 卡片標題前的徽章圖示：分辨來源
    var badgeIcon: String {
        switch self {
        case .renovation: return "paintbrush.fill"
        case .expense: return "tag.fill"
        case .document(let d): return d.icon
        }
    }

    var badgeColor: Color {
        switch self {
        case .renovation: return .blue
        case .expense: return .orange
        case .document(let d): return d.iconColor
        }
    }
}

// MARK: - 支出多張照片展開瀏覽器

/// 把一筆 Expense 的所有照片以左右滑動方式逐張展開（與 RenovationStackViewer 對等）。
struct ExpensePhotoStackViewer: View {
    let expense: Expense
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if expense.photoFileNames.isEmpty {
                    Text("沒有照片").foregroundStyle(.white.opacity(0.7))
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(expense.photoFileNames.enumerated()), id: \.offset) { idx, name in
                            let url = Expense.photoURL(for: name)
                            ZStack {
                                if let img = UIImage(contentsOfFile: url.path) {
                                    ZoomableImageView(image: img)
                                } else {
                                    ProgressView().tint(.white)
                                }
                            }
                            .tag(idx)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                }

                VStack {
                    Spacer()
                    panelContent
                }
            }
            .navigationTitle(displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
            }
        }
    }

    private var displayTitle: String {
        let trimmedNote = expense.note.trimmingCharacters(in: .whitespaces)
        if !trimmedNote.isEmpty { return trimmedNote }
        return expense.title.isEmpty ? "支出照片" : expense.title
    }

    @ViewBuilder
    private var panelContent: some View {
        let trimmedNote = expense.note.trimmingCharacters(in: .whitespaces)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(currentIndex + 1) / \(expense.photoFileNames.count)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            if !expense.title.isEmpty && !trimmedNote.isEmpty {
                Text(expense.title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
            Text(fmtDate(expense.date))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .padding(.bottom, 32)
    }

    private func fmtDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: date)
    }
}

// MARK: - 房屋資料集錦：可愛風照片瀏覽器

struct CutePhotoDraft: Identifiable {
    enum Kind {
        case renovation, expense
        var label: String {
            switch self {
            case .renovation: return "裝潢紀錄"
            case .expense: return "支出照片"
            }
        }
        var icon: String {
            switch self {
            case .renovation: return "paintbrush.fill"
            case .expense: return "tag.fill"
            }
        }
        var accent: Color {
            switch self {
            case .renovation: return Color(red: 0.82, green: 0.55, blue: 0.92)   // 粉紫
            case .expense:    return Color(red: 0.98, green: 0.62, blue: 0.45)   // 蜜桃
            }
        }
    }

    let id = UUID()
    let urls: [URL]
    let title: String
    let note: String
    let date: Date
    let kind: Kind
}

/// 可愛風照片瀏覽器：粉色漸層背景 + 圓角描邊照片 + 自訂頁碼點 + 友善資訊卡。
/// 支援雙指縮放（內含 ZoomableImageView）+ 多張左右滑動切換。
struct CutePhotoViewer: View {
    let draft: CutePhotoDraft
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int = 0

    var body: some View {
        ZStack {
            backgroundGradient
            decorativeOrbs

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 4)
                photoArea
                Spacer(minLength: 4)
                if draft.urls.count > 1 {
                    pageDots
                        .padding(.bottom, 4)
                }
                infoCard
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: 背景

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 1.00, green: 0.94, blue: 0.93),    // 淡桃
                Color(red: 1.00, green: 0.90, blue: 0.94),    // 淡粉
                Color(red: 0.94, green: 0.90, blue: 1.00)     // 淡紫
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    /// 角落漂浮的兩顆柔光圓球，讓畫面更活潑
    private var decorativeOrbs: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(draft.kind.accent.opacity(0.18))
                    .frame(width: 220, height: 220)
                    .blur(radius: 50)
                    .offset(x: -geo.size.width * 0.35, y: -geo.size.height * 0.32)
                Circle()
                    .fill(Color.pink.opacity(0.12))
                    .frame(width: 280, height: 280)
                    .blur(radius: 60)
                    .offset(x: geo.size.width * 0.32, y: geo.size.height * 0.18)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: 上方 chrome

    private var topBar: some View {
        HStack {
            // 來源膠囊
            HStack(spacing: 6) {
                Image(systemName: draft.kind.icon)
                    .font(.caption.weight(.bold))
                Text(draft.kind.label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(LinearGradient(
                        colors: [draft.kind.accent, draft.kind.accent.opacity(0.75)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            )
            .shadow(color: draft.kind.accent.opacity(0.35), radius: 6, y: 3)

            Spacer()

            // 關閉按鈕
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(draft.kind.accent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(Circle().stroke(draft.kind.accent.opacity(0.25), lineWidth: 1))
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    // MARK: 主照片區

    private var photoArea: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(draft.urls.enumerated()), id: \.offset) { idx, url in
                photoCard(url: url)
                    .tag(idx)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func photoCard(url: URL) -> some View {
        Group {
            if let img = UIImage(contentsOfFile: url.path) {
                ZoomableImageView(image: img)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white, lineWidth: 4)
                    )
                    .shadow(color: Color.black.opacity(0.15), radius: 14, y: 6)
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        VStack(spacing: 10) {
                            Image(systemName: "photo.fill.on.rectangle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(draft.kind.accent.opacity(0.6))
                            Text("找不到照片")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white, lineWidth: 4)
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 10, y: 4)
            }
        }
    }

    // MARK: 自訂頁碼點

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<draft.urls.count, id: \.self) { idx in
                Capsule()
                    .fill(idx == currentIndex
                          ? draft.kind.accent
                          : Color.gray.opacity(0.3))
                    .frame(
                        width: idx == currentIndex ? 18 : 6,
                        height: 6
                    )
                    .animation(.spring(response: 0.32, dampingFraction: 0.7),
                               value: currentIndex)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(Color.white.opacity(0.6), lineWidth: 0.5))
    }

    // MARK: 底部資訊卡

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("📸")
                    .font(.title3)
                Text(draft.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.25, green: 0.18, blue: 0.35))
                    .lineLimit(2)
                Spacer()
                if draft.urls.count > 1 {
                    Text("\(currentIndex + 1) / \(draft.urls.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(draft.kind.accent)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(
                            Capsule().fill(draft.kind.accent.opacity(0.15))
                        )
                }
            }
            if !draft.note.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Text("💬")
                    Text(draft.note)
                        .font(.subheadline)
                        .foregroundStyle(Color(red: 0.35, green: 0.3, blue: 0.45))
                        .lineLimit(4)
                }
            }
            HStack(spacing: 6) {
                Text("📅")
                Text(fmtDate(draft.date))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.85))
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(colors: [
                            Color.white.opacity(0.6),
                            draft.kind.accent.opacity(0.08)
                        ], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 14, y: -2)
        .padding(.horizontal, 14)
        .padding(.bottom, 18)
    }

    private func fmtDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy 年 M 月 d 日"
        f.locale = Locale(identifier: "zh_TW")
        return f.string(from: d)
    }
}

// MARK: - 文件預覽（QuickLook 包裝）

/// 用 QLPreviewController 預覽 PDF / PPT / Excel / Word 等，支援 Apple 內建的縮放與分享。
/// 以 sheet 包裹呈現，使用者下拉即可關閉。
struct DocumentQuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        return preview
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}
