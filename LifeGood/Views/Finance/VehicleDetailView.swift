import SwiftUI

// [v25.540] 載具卡片（換新卡片）的外殼：跟房屋卡、股票卡同一個樣子（換車列、看板、一欄捲到底、分享）。
// - 卡片上的字和數字全在 VehicleCardData.build 一次算好（只在 .task 裡算；換車時在 jump 裡同步算好新的那台）；
//   各區畫面在 VehicleCardViews.swift，這裡只管排列順序、彈出頁、確認框、付費和分享。
// - 看資料免費；新增、編輯、刪除、修正都先過 requirePremium，「＋」選單在打開前就擋。
// - 彈出頁收成一個 VehicleSheet＋一個 .sheet(item:)，確認框一個 VehicleConfirm、選單一個 VehicleChoice。
// - 「照片與單據」綁著照片紀錄的編輯、刪除，留在這個檔案畫；照片紀錄編輯器搬到 VehicleEditors.swift。
// - 刪整台車不在卡片上（列表左滑、編輯頁最下面「刪除這台車」）。
// - 分享不輸出車主、地點、家充、里程、照片、備註、車輛資料、自己取的名稱；車名像車牌改寫「品牌 動力」（決定 20）。

struct VehicleDetailView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    /// @State 而不是 let：換車列點一下就換一台（同一張卡換內容，不重開 sheet）
    @State private var vehicleId: UUID
    /// 列表傳進來的順序（同一組：持有中／已售出）；空的時候用 store 的順序
    private let order: [UUID]
    /// 打開時要捲到哪一區；捲過一次就清掉
    @State private var startAnchor: VehicleAnchor?
    /// 換車的方向（+1 往右邊那台、-1 往左邊），決定滑入的方向
    @State private var slideDirection: Int = 1

    /// 卡片上全部的字與數字：只在 .task(id: cardTaskKey) 和換車時算
    @State private var card: VehicleCardData?
    /// 上一次算 card 用的 key：換車時已經同步算好，.task 看到同一個 key 就不再算一次
    @State private var lastBuiltKey = ""
    @State private var ledgerFilter: VehicleLedgerFilter = .all

    @State private var sheet: VehicleSheet?
    @State private var pendingConfirm: VehicleConfirm?
    @State private var pendingChoice: VehicleChoice?
    @State private var showPremiumAlert = false
    @State private var askExportPageSize = false
    /// 補建舊定期：打開記帳頁前記下來，記帳頁關掉時比對有沒有新存一筆（定案 18）
    @State private var pendingBackfill: VehicleBackfill?

    init(vehicleId: UUID, order: [UUID] = [], startAt: VehicleAnchor? = nil) {
        _vehicleId = State(initialValue: vehicleId)
        self.order = order
        _startAnchor = State(initialValue: startAt)
    }

    private static let placeholder = Vehicle(name: "")
    fileprivate static let gregorian = Calendar(identifier: .gregorian)

    /// 目前這台（store 裡最新的那一份；被刪掉時是空的佔位，.task 會把卡片關掉）
    fileprivate var vehicle: Vehicle {
        store.vehicles.first(where: { $0.id == vehicleId }) ?? Self.placeholder
    }

    /// 換車列：列表傳進來的順序，只留跟目前這台同一組的（isSold(asOf:)：售出日還沒到照持有中算，跟列表分組一樣）
    private var siblings: [Vehicle] {
        let current = vehicle
        let all = store.vehicles
        var list: [Vehicle]
        if order.isEmpty {
            list = all
        } else {
            let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            list = order.compactMap { byId[$0] }
            if !list.contains(where: { $0.id == current.id }), byId[current.id] != nil {
                list.append(current)
            }
        }
        let now = Date()
        let sold = current.isSold(asOf: now)
        return list.filter { $0.isSold(asOf: now) == sold }
    }

    private var titleText: String {
        if let card { return card.name }
        let name = vehicle.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "未命名車輛" : name
    }

    /// 換車、記帳改了、車子改了都要重算
    private var cardTaskKey: String {
        taskKey(for: vehicleId)
    }

    private func taskKey(for id: UUID) -> String {
        "\(id.uuidString)-\(store.modifyID)-\(expenseStore.modifyID)"
    }

    var body: some View {
        NavigationStack {
            withPresentations(scroller)
        }
    }

    private var scroller: some View {
        ScrollViewReader { proxy in
            ScrollView {
                cardContent(proxy)
            }
            .background(Color(.systemGroupedBackground))
            .task(id: cardTaskKey) { rebuildCard(proxy) }
        }
        // 換車列釘在導覽列下面：同一組不只一台才出現。不做整頁左右滑（會跟照片橫捲、長按、點圖打架）
        .safeAreaInset(edge: .top, spacing: 0) { switcherBar }
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
    }

    // MARK: - 算卡片、換車

    /// 在主執行緒算（MoneyFormat 共用一個 NumberFormatter）
    private func buildCard(for id: UUID) -> VehicleCardData? {
        guard let v = store.vehicles.first(where: { $0.id == id }) else { return nil }
        return VehicleCardData.build(v, vehicles: store.vehicles, expense: expenseStore)
    }

    private func rebuildCard(_ proxy: ScrollViewProxy) {
        guard store.vehicles.contains(where: { $0.id == vehicleId }) else {
            // 車子被刪掉了（編輯頁最下面刪的、或別台裝置同步過來的）：卡片沒有東西可看了。
            // 晚一點才關：編輯頁可能還在往下收，一邊收一邊關卡片會被 UIKit 擋掉
            card = nil
            lastBuiltKey = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismiss() }
            return
        }
        let key = cardTaskKey
        if card == nil || key != lastBuiltKey {
            card = buildCard(for: vehicleId)
            lastBuiltKey = key
        }
        scrollToStartIfNeeded(proxy)
    }

    /// 打開時要捲到的那一區：等各區真的畫出來再捲（排到下一個 main.async 可能比畫面更新還早）
    private func scrollToStartIfNeeded(_ proxy: ScrollViewProxy) {
        guard let anchor = startAnchor else { return }
        startAnchor = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    private func select(_ id: UUID, in list: [Vehicle]) {
        let from = list.firstIndex { $0.id == vehicleId } ?? 0
        let to = list.firstIndex { $0.id == id } ?? 0
        jump(to: id, direction: to >= from ? 1 : -1)
    }

    /// 換到另一台（J39）：新的那台在這裡同步算好再換，不先清成 nil，滑進來的不會是一塊空白。
    /// 帳本篩選、還沒按的確認框一起重設；各區自己的展開、「再看 N 筆」跟著 .id(vehicleId) 歸零
    private func jump(to id: UUID, direction: Int) {
        guard id != vehicleId else { return }
        let next = buildCard(for: id)
        slideDirection = direction
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            vehicleId = id
            card = next
            ledgerFilter = .all
            pendingConfirm = nil
            pendingChoice = nil
        }
        lastBuiltKey = next == nil ? "" : taskKey(for: id)
    }

    @ViewBuilder
    private var switcherBar: some View {
        let list = siblings
        if list.count > 1 {
            FinanceSwitcherStrip(items: switcherItems(list), selected: vehicleId) { id in
                select(id, in: list)
            }
            .padding(.vertical, 4)
            .background(.bar)
        }
    }

    /// 一台一顆：車名（最多 6 字）＋估值（已售出「賣 110萬」），一律中性色（定案 9）
    private func switcherItems(_ list: [Vehicle]) -> [FinanceSwitcherItem] {
        list.map { v -> FinanceSwitcherItem in
            let trailing = VehicleCardData.switcherTrailing(v)
            let name = v.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = MoneyBoardText.short(name.isEmpty ? "未命名車輛" : name, max: 6)
            return FinanceSwitcherItem(id: v.id, title: title,
                                       trailing: trailing?.text ?? "", tone: trailing?.tone ?? .neutral)
        }
    }

    // MARK: - 工具列

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("關閉") { dismiss() }
        }
        // 標題就是車名，太長跑馬燈（不再寫「車輛卡片」）
        ToolbarItem(placement: .principal) {
            MarqueeText(titleText)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 16) {
                Button {
                    shareTapped()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("分享")
                .disabled(card == nil)
                Button {
                    requirePremium { sheet = .edit(VehicleEditFocus.none) }
                } label: {
                    Text("編輯").foregroundStyle(.green)
                }
                // 刪除整台只在列表左滑、編輯頁最下面（都會先確認）
            }
        }
    }

    // MARK: - 內容

    private var slideTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: slideDirection > 0 ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: slideDirection > 0 ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private func cardContent(_ proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 22) {
            if let card {
                let actions = makeActions(proxy)
                upperSections(card, actions: actions, proxy: proxy)
                lowerSections(card, actions: actions)
            } else {
                Color.clear.frame(height: 360)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 28)
        // 換車時整包內容依方向滑入（id 變了就觸發轉場）
        .id(vehicleId)
        .transition(slideTransition)
    }

    /// 看板、要確認、每月養車、接下來、車貸（各區自己決定整區要不要出現）
    @ViewBuilder
    private func upperSections(_ card: VehicleCardData, actions: VehicleCardActions,
                               proxy: ScrollViewProxy) -> some View {
        VehicleCardBoard(data: card, scrollTo: { anchor in scroll(proxy, to: anchor) })
            .id(VehicleAnchor.top)
        VehicleChecksSection(data: card, actions: actions)
            .id(VehicleAnchor.checks)
        VehicleMonthlySection(data: card, actions: actions)
            .id(VehicleAnchor.monthly)
        VehicleUpcomingSection(data: card, actions: actions)
            .id(VehicleAnchor.upcoming)
        VehicleLoanSection(data: card, actions: actions)
            .id(VehicleAnchor.loan)
    }

    /// 充電／加油／油電、我的帳本、車輛資料、照片與單據
    @ViewBuilder
    private func lowerSections(_ card: VehicleCardData, actions: VehicleCardActions) -> some View {
        VehicleEnergySection(data: card, actions: actions)
            .id(VehicleAnchor.energy)
        VehicleLedgerSection(data: card, filter: $ledgerFilter, actions: actions)
            .id(VehicleAnchor.ledger)
        VehicleInfoSection(data: card, actions: actions)
            .id(VehicleAnchor.info)
        photosSection(card)
            .id(VehicleAnchor.photos)
    }

    fileprivate func scroll(_ proxy: ScrollViewProxy, to anchor: VehicleAnchor) {
        withAnimation(.easeInOut(duration: 0.35)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    // MARK: - 彈出頁、確認框

    private func withPresentations<Content: View>(_ content: Content) -> some View {
        withAlerts(withSheets(content))
    }

    private func withSheets<Content: View>(_ content: Content) -> some View {
        content
            .sheet(item: $sheet, onDismiss: { sheetDismissed() }) { s in sheetView(s).appStores() }
            .exportPageSizeDialog(isPresented: $askExportPageSize,
                                  itemCount: card?.ledger.events.count ?? 0) { per in
                exportPaged(perPage: per)
            }
    }

    private func withAlerts<Content: View>(_ content: Content) -> some View {
        content
            .alert(pendingConfirm?.title ?? "", isPresented: confirmPresented, presenting: pendingConfirm) { c in
                confirmButtons(c)
            } message: { c in
                Text(c.message)
            }
            .confirmationDialog(pendingChoice?.title ?? "", isPresented: choicePresented,
                                titleVisibility: .visible, presenting: pendingChoice) { c in
                choiceButtons(c)
            } message: { c in
                Text(c.message)
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
    }

    private var confirmPresented: Binding<Bool> {
        Binding(get: { pendingConfirm != nil }, set: { if !$0 { pendingConfirm = nil } })
    }

    private var choicePresented: Binding<Bool> {
        Binding(get: { pendingChoice != nil }, set: { if !$0 { pendingChoice = nil } })
    }

    @ViewBuilder
    private func confirmButtons(_ c: VehicleConfirm) -> some View {
        if let label = c.button {
            Button(label, role: c.destructive ? .destructive : nil) { Self.runAfterClose(c.action) }
            Button("取消", role: .cancel) {}
        } else {
            Button("好", role: .cancel) {}
        }
    }

    /// 確認框按下去要寫 store 的（刪記帳、停止扣款、移除鏡像、刪照片…）排到下一個 runloop 才做：
    /// 確認框正在收的那個交易裡同步改 @Published store 容易閃退（同 AddVehicleView、VehiclePhotoEditor 的寫法）
    private static func runAfterClose(_ action: @escaping () -> Void) {
        DispatchQueue.main.async { action() }
    }

    @ViewBuilder
    private func choiceButtons(_ c: VehicleChoice) -> some View {
        ForEach(c.options) { o in
            Button(o.label, role: o.destructive ? .destructive : nil) { o.action() }
        }
        Button("取消", role: .cancel) {}
    }

    /// 兩個 switch 分開（記帳類／照片類）：一個 switch 放全部 case 容易型別檢查逾時
    @ViewBuilder
    private func sheetView(_ s: VehicleSheet) -> some View {
        switch s {
        case .edit, .editExpense, .newExpense, .share:
            recordSheet(s)
        default:
            mediaSheet(s)
        }
    }

    /// 編輯頁、記帳、分享
    @ViewBuilder
    private func recordSheet(_ s: VehicleSheet) -> some View {
        switch s {
        case .edit(let focus):
            AddVehicleView(editing: vehicle, focus: focus)
        case .editExpense(let ex, let showVehicleSection):
            AddExpenseView(expenseType: ex.expenseType, editingExpense: ex,
                           preset: Self.editPreset(showVehicleSection))
        case .newExpense(let request):
            AddExpenseView(expenseType: request.expenseType, preset: request.preset)
        case .share(let payload):
            ShareSheet(items: payload.items)
        default:
            EmptyView()
        }
    }

    /// 照片紀錄編輯、看照片、充電與里程分析
    @ViewBuilder
    private func mediaSheet(_ s: VehicleSheet) -> some View {
        switch s {
        case .photoEditor(_, let record, let category):
            VehiclePhotoEditor(vehicleId: vehicleId, editing: record, category: category)
        case .photos(let draft):
            CutePhotoViewer(draft: draft)
        case .chargeAnalytics:
            VehicleChargeAnalyticsView(vehicleId: vehicleId)
        default:
            EmptyView()
        }
    }

    /// 定案 19：油錢、電費、保養、維修那幾筆打開時帶 showVehicleSection，度數、公升、里程欄直接看得到
    private static func editPreset(_ showVehicleSection: Bool) -> AddExpensePreset? {
        showVehicleSection ? AddExpensePreset(showVehicleSection: true) : nil
    }
}

// MARK: - 動作（VehicleCardActions 的每一個 closure）

extension VehicleDetailView {
    /// 新增、編輯、刪除、修正的唯一一道門：看資料免費，改資料付費
    fileprivate func requirePremium(_ action: () -> Void) {
        if subscription.isPremium {
            action()
        } else {
            showPremiumAlert = true
        }
    }

    fileprivate func makeActions(_ proxy: ScrollViewProxy) -> VehicleCardActions {
        var a = VehicleCardActions()
        a.scrollTo = { anchor in scroll(proxy, to: anchor) }
        // 篩選只改變顯示：跟篩選膠囊同一個動畫（easeOut 0.25）
        a.setLedgerFilter = { filter in
            withAnimation(.easeOut(duration: 0.25)) { ledgerFilter = filter }
        }
        a.edit = { focus in requirePremium { sheet = .edit(focus) } }
        a.fixCheck = { check, action in fixCheck(check, action) }
        a.openExpense = { id in requirePremium { openExpenseRecord(id) } }
        a.stopExpense = { id in requirePremium { confirmStop(id) } }
        a.deleteLoan = { row in requirePremium { confirmDeleteLoan(row) } }
        a.addLedger = { kind in requirePremium { presentAdd(kind) } }
        a.openLedger = { event in openLedger(event, proxy: proxy) }
        a.deleteLedger = { event in deleteLedger(event) }
        // 充電與里程分析、看照片都不用付費
        a.openAnalytics = { sheet = .chargeAnalytics }
        a.showPhotos = { draft in sheet = .photos(draft) }
        // 「＋ 記一筆」選單在打開前就擋：沒付費時畫面換成普通按鈕，按了跳付費說明
        a.canEdit = subscription.isPremium
        a.askPremium = { showPremiumAlert = true }
        return a
    }

    /// 只是告訴你一件事（只有「好」）
    fileprivate func presentNotice(_ title: String, _ message: String) {
        pendingConfirm = VehicleConfirm(title: title, message: message)
    }

    /// 從選單（confirmationDialog）選了之後再跳確認框：等選單收完再出來，不然確認框會被吃掉
    fileprivate func presentConfirmLater(_ c: VehicleConfirm) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            pendingConfirm = c
        }
    }

    /// 確認框按下去之後要開彈出頁：一樣等確認框收完
    fileprivate func presentSheetLater(_ s: VehicleSheet) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            sheet = s
        }
    }

    // MARK: 打開記帳那一筆

    /// 打開記帳裡那一筆（帳本列、接下來、車貸列、要確認的「去填／去看」）
    fileprivate func openExpenseRecord(_ id: UUID) {
        guard let ex = expenseStore.expenses.first(where: { $0.id == id }) else {
            presentNotice("找不到這筆記帳", "記帳裡已經沒有這一筆了（可能在記帳那邊刪掉了）。")
            return
        }
        sheet = .editExpense(ex, showVehicleSection: Self.showsVehicleSection(ex))
    }

    /// 油錢、電費、保養、維修：記帳頁的車輛區（度數、電量、公升、里程錶）直接打開
    fileprivate static func showsVehicleSection(_ ex: Expense) -> Bool {
        guard ex.expenseType == .variable, let cat = ex.vehicleExpenseCategory else { return false }
        switch cat {
        case .fuel, .electricity, .maintenance, .repair: return true
        default: return false
        }
    }

    // MARK: 記一筆

    /// 「＋ 記一筆」「＋ 記保險」「＋ 記稅費」「＋ 加一筆車貸」「＋ 記第一次充電」：分類先帶好、連到這台。
    /// 已售出的車，變動支出的日期預設賣出日（照房屋）
    fileprivate func presentAdd(_ kind: VehicleLedgerAddKind) {
        if kind == .photo {
            sheet = .photoEditor(UUID(), nil, .maintenance)
            return
        }
        if let cat = kind.variableCategory {
            var preset = AddVehicleView.makeVariablePreset(for: cat, vehicleId: vehicleId)
            let v = vehicle
            if v.isSold(asOf: Date()), let sold = v.soldDate { preset.date = sold }
            sheet = .newExpense(VehicleExpenseRequest(expenseType: .variable, preset: preset))
        } else if let fixed = kind.fixedKind {
            let preset = AddVehicleView.makeFixedPreset(for: fixed, vehicleId: vehicleId)
            sheet = .newExpense(VehicleExpenseRequest(expenseType: .fixed, preset: preset))
        }
    }

    // MARK: 帳本列

    /// 車貸年列捲到車貸區（不用付費）；其他都是去改資料（付費）
    fileprivate func openLedger(_ e: VehicleLedgerEvent, proxy: ScrollViewProxy) {
        switch e.source {
        case .loanYear:
            scroll(proxy, to: .loan)
        case .expense(let id):
            requirePremium { openExpenseRecord(id) }
        case .purchase:
            requirePremium { sheet = .edit(.purchase) }
        case .fixedYear(let id, _):
            requirePremium { openExpenseRecord(id) }
        case .legacy(let mirrorId):
            requirePremium { offerLegacyChoices(e, mirrorId: mirrorId) }
        }
    }

    /// 長按刪除：只有真的記帳列能刪（買車列、年列、沒連到記帳的不能）
    fileprivate func deleteLedger(_ e: VehicleLedgerEvent) {
        guard e.canDelete, let id = e.expenseId else { return }
        requirePremium { confirmDeleteLedger(e, expenseId: id) }
    }

    fileprivate func confirmDeleteLedger(_ e: VehicleLedgerEvent, expenseId id: UUID) {
        guard expenseStore.expenses.contains(where: { $0.id == id }) else {
            presentNotice("找不到這筆記帳", "記帳裡已經沒有這一筆了（可能在記帳那邊刪掉了）。")
            return
        }
        let title = "刪除「\(e.title) \(e.amountText)」？"
        let message: String
        if let bank = bankName(forExpense: id) {
            let account = bank.hasSuffix("帳戶") ? bank : "\(bank)帳戶"
            message = "記帳裡這筆和\(account)的扣款紀錄會一起刪除，不能復原。"
        } else {
            message = "記帳裡這筆支出會一起刪除，不能復原。"
        }
        pendingConfirm = VehicleConfirm(title: title, message: message, button: "刪除",
                                        action: { deleteExpenses([id]) })
    }

    /// 銀行帳戶裡真的有這筆扣款才提銀行名（信用卡、週期性固定支出不會有單筆扣款）。照抄 RealEstateDetailView
    fileprivate func bankName(forExpense id: UUID) -> String? {
        for ms in lifeStore.milestones {
            let deposits = ms.bankDeposits ?? []
            guard deposits.contains(where: { $0.linkedExpenseId == id }) else { continue }
            let bank = (ms.bankName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return bank.isEmpty ? ms.title : bank
        }
        return nil
    }

    /// 刪記帳支出：收據照片、所有銀行帳戶裡的扣款紀錄、每台車身上指到它的鏡像一起清
    fileprivate func deleteExpenses(_ ids: Set<UUID>) {
        RealEstateDeletion.removeExpenses(ids, expenseStore: expenseStore, lifeStore: lifeStore)
    }

    /// 沒連到記帳的舊變動鏡像：補建一筆記帳支出（直接建，不開表單），或只從車子拿掉
    fileprivate func offerLegacyChoices(_ e: VehicleLedgerEvent, mirrorId: UUID) {
        let message = "這筆 \(e.amountText) 只記在車子這邊，記帳裡沒有：不會算進記帳的支出，也沒有地方改。補建一筆記帳支出之後，點這一列就能編輯。"
        let day = FinanceFormat.ymd(e.date)
        let backfill = VehicleChoice.Option(label: "補建記帳支出", action: {
            presentConfirmLater(VehicleConfirm(
                title: "補建記帳支出？",
                message: "在記帳新增一筆 \(e.amountText)（\(day)），連到這台車。不會動銀行帳戶。",
                button: "補建", destructive: false,
                action: { backfillLegacy(mirrorId) }))
        })
        let remove = VehicleChoice.Option(label: "從車子移除", destructive: true, action: {
            presentConfirmLater(VehicleConfirm(
                title: "移除「\(e.title) \(e.amountText)」？",
                message: "這一筆只記在車子這邊（沒連到記帳），會從車子拿掉，不能復原。",
                button: "移除",
                action: { removeMirrors([mirrorId]) }))
        })
        pendingChoice = VehicleChoice(title: "「\(e.title)」沒連到記帳", message: message, options: [backfill, remove])
    }

    /// 補建：照鏡像的分類、金額、日期建一筆汽車變動支出，鏡像改連過去（不寫銀行扣款）
    fileprivate func backfillLegacy(_ mirrorId: UUID) {
        guard var v = store.vehicles.first(where: { $0.id == vehicleId }) else { return }
        guard let made = VehicleFixes.backfillVariable(mirrorId, of: &v) else { return }
        expenseStore.add(made)
        store.update(v)
    }

    /// 只從這台車移掉這些鏡像（記帳不動）
    fileprivate func removeMirrors(_ ids: [UUID]) {
        guard var v = store.vehicles.first(where: { $0.id == vehicleId }) else { return }
        VehicleFixes.removeMirrors(Set(ids), from: &v)
        store.update(v)
    }

    // MARK: 停止扣款、刪車貸

    /// 停止扣款（接下來、車貸列長按）：最後扣款日設成今天（確認文字照 J253）
    fileprivate func confirmStop(_ id: UUID) {
        guard expenseStore.expenses.contains(where: { $0.id == id }) else {
            presentNotice("找不到這筆記帳", "記帳裡已經沒有這一筆了（可能在記帳那邊刪掉了）。")
            return
        }
        let today = FinanceFormat.ymd(Self.gregorian.startOfDay(for: Date()))
        let message = "記帳那筆的最後扣款日設成今天（\(today)），之後不再扣，也不會再從銀行扣。"
        pendingConfirm = VehicleConfirm(title: "停止扣款？", message: message, button: "停止扣款",
                                        destructive: false, action: { stopExpense(id) })
    }

    fileprivate func stopExpense(_ id: UUID) {
        var list = expenseStore.expenses
        if VehicleFixes.stop(id, on: Date(), in: &list) {
            expenseStore.expenses = list
        }
    }

    /// 刪一筆車貸會改寫過去（已繳的期數也從帳本和淨資產走勢消失），確認文字由 VehicleCardData 寫好
    fileprivate func confirmDeleteLoan(_ row: VehicleLoanSectionData.Row) {
        let title = "刪除「\(row.title)」？"
        switch row.source {
        case .expense(let id):
            let fallback = "會刪掉記帳裡這筆車貸和銀行的扣款紀錄，不能復原。"
            let message = row.deleteMessage.isEmpty ? fallback : row.deleteMessage
            pendingConfirm = VehicleConfirm(title: title, message: message, button: "刪除",
                                            action: { deleteExpenses([id]) })
        case .legacy(let mirrorId):
            let message = "這筆車貸只記在車子這邊（沒連到記帳），會從車子拿掉，不能復原。"
            pendingConfirm = VehicleConfirm(title: title, message: message, button: "刪除",
                                            action: { removeMirrors([mirrorId]) })
        }
    }

    // MARK: 要確認

    /// 每顆修正鈕：先付費；有確認文字的先確認，「去填／去改／去看」直接打開
    fileprivate func fixCheck(_ check: VehicleCheck, _ action: VehicleCheck.Action) {
        requirePremium {
            let fix = action.fix
            guard let confirm = action.confirm else {
                performFix(fix)
                return
            }
            let title = action.confirmTitle.isEmpty ? "確定要修正嗎？" : action.confirmTitle
            pendingConfirm = VehicleConfirm(title: title, message: confirm, button: action.title,
                                            destructive: action.destructive, action: { performFix(fix) })
        }
    }

    fileprivate func performFix(_ fix: VehicleCheck.Fix) {
        switch fix {
        case .stopAtSale(let ids, let soldDate):
            stopAtSale(ids, soldDate: soldDate)
        case .convertToInsurance(let ids):
            convertToInsurance(ids)
        case .openExpense(let id):
            openExpenseRecord(id)
        case .removeMirrors(let ids):
            removeMirrors(ids)
        case .backfillFixed(let mirrorId):
            startBackfill(mirrorId)
        case .assign(let ids):
            assignExpenses(ids)
        case .markValueZero:
            markValueZero()
        case .edit(let focus):
            sheet = .edit(focus)
        }
    }

    /// 賣了還在扣：車貸、保險、稅費照賣車的規則停，月租、訂閱停在賣出日；記帳只寫一次
    fileprivate func stopAtSale(_ ids: [UUID], soldDate: Date) {
        guard let v = store.vehicles.first(where: { $0.id == vehicleId }) else { return }
        var list = expenseStore.expenses
        if VehicleFixes.stopAtSale(ids, soldDate: soldDate, vehicle: v, in: &list, calendar: Self.gregorian) {
            expenseStore.expenses = list
        }
    }

    /// [v25.541] 記成「其他」的車險改成保險（強制險／綜合險）。車險只認 linkedVehicleId、不留鏡像（同記帳頁存車險）：
    /// 先寫記帳（連同 linkedVehicleId）再拿鏡像。順序反過來，只靠鏡像連過來的那筆會先跟這台斷開、從卡片消失
    fileprivate func convertToInsurance(_ ids: [UUID]) {
        var list = expenseStore.expenses
        guard VehicleFixes.convertToInsurance(ids, vehicleId: vehicleId, in: &list) else { return }
        expenseStore.expenses = list
        VehicleMirrors.removeMirrors(of: Set(ids), financeStore: store)
    }

    /// 都算這台：沒指定車的「汽車」支出連到這台（不寫鏡像）
    fileprivate func assignExpenses(_ ids: [UUID]) {
        var list = expenseStore.expenses
        if VehicleFixes.assign(ids, to: vehicleId, in: &list) {
            expenseStore.expenses = list
        }
    }

    /// 就是 0（報廢）：估值 0 並寫更新日，之後照 0 算（決定 10）
    fileprivate func markValueZero() {
        guard var v = store.vehicles.first(where: { $0.id == vehicleId }) else { return }
        VehicleFixes.markValueZero(&v, today: Date())
        store.update(v)
    }

    /// 補建舊定期（定案 18）：AddExpensePreset 沒有金額，打開記帳頁讓你照確認框寫的金額打；
    /// 先記下打開前所有支出的 id，記帳頁關掉時（sheetDismissed）比對
    fileprivate func startBackfill(_ mirrorId: UUID) {
        guard let mirror = vehicle.fixedExpenses.first(where: { $0.id == mirrorId }) else {
            presentConfirmLater(VehicleConfirm(title: "找不到這筆", message: "車子這邊已經沒有這筆舊的定期支出了。"))
            return
        }
        let preset = VehicleFixes.backfillPreset(for: mirror, vehicleId: vehicleId)
        pendingBackfill = VehicleBackfill(mirrorId: mirrorId, vehicleId: vehicleId,
                                          existingIds: Set(expenseStore.expenses.map(\.id)))
        presentSheetLater(.newExpense(VehicleExpenseRequest(expenseType: .fixed, preset: preset)))
    }

    /// 彈出頁關掉時：補建的那一次，記帳多了一筆連到這台的固定支出，就把舊鏡像從車子拿掉
    ///（新鏡像記帳頁存檔時已經建好）；按取消沒存就什麼都不動，「要確認」那一件會留著
    fileprivate func sheetDismissed() {
        guard let pending = pendingBackfill else { return }
        pendingBackfill = nil
        // 記帳頁存檔是先寫 store 再關，所以這裡看得到新的那筆；拿掉舊鏡像一樣排到下一個 runloop、讀最新的車子
        let finance = store
        let expenses = expenseStore
        DispatchQueue.main.async {
            let added = expenses.expenses.contains { ex in
                !pending.existingIds.contains(ex.id) && ex.expenseType == .fixed
                    && ex.linkedVehicleId == pending.vehicleId
            }
            guard added, var v = finance.vehicles.first(where: { $0.id == pending.vehicleId }) else { return }
            VehicleFixes.removeMirrors([pending.mirrorId], from: &v)
            finance.update(v)
        }
    }
}

// MARK: - 照片與單據

extension VehicleDetailView {
    /// 照片紀錄＋帳本那批支出的收據（張數、封面、排序都在 VehicleCardData 算好）；沒有任何一項時縮成一行
    fileprivate func photosSection(_ card: VehicleCardData) -> some View {
        let media = card.media
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                MoneySectionHeader(title: "照片與單據", trailing: media.trailing)
                    .accessibilityAddTraits(.isHeader)
                if !media.isEmpty {
                    photoAddMenu
                }
            }
            if media.isEmpty {
                photosEmptyRow
            } else {
                photoStrip(media.items)
            }
        }
    }

    /// 區塊標題右邊的綠色小「＋」（跟房屋卡同一個樣子）
    fileprivate var photoAddIcon: some View {
        Image(systemName: "plus")
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(Color.white)
            .frame(width: 24, height: 24)
            .background(Color(tb: 0x1F9D57), in: Circle())
            .frame(width: 34, height: 30)
            .contentShape(Rectangle())
    }

    /// 付費才打開的「＋」選單：沒付費時換成普通按鈕，按了跳付費說明（選單打開前就擋）
    @ViewBuilder
    fileprivate var photoAddMenu: some View {
        if subscription.isPremium {
            Menu {
                photoAddItems
            } label: {
                photoAddIcon
            }
            .accessibilityLabel("加照片或單據")
        } else {
            Button {
                showPremiumAlert = true
            } label: {
                photoAddIcon
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityLabel("加照片或單據")
        }
    }

    /// 四項（J475）：打開照片紀錄編輯器，類別先帶好
    fileprivate var photoAddItems: some View {
        ForEach(VehiclePhotoAddOption.all) { option in
            Button {
                requirePremium { sheet = .photoEditor(UUID(), nil, option.category) }
            } label: {
                Label(option.title, systemImage: option.category.icon)
            }
        }
    }

    /// 沒有任何照片：整區縮成一行「＋ 加照片（…）」（付費才打開選單）
    fileprivate var photosEmptyRow: some View {
        let label = HStack(spacing: 8) {
            Text("＋ 加照片（車子的樣子、保養單、行照、保險卡）")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TripBoardPalette(scheme).hint)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(14)
        .contentShape(Rectangle())
        return Group {
            if subscription.isPremium {
                Menu {
                    photoAddItems
                } label: {
                    label
                }
            } else {
                Button {
                    showPremiumAlert = true
                } label: {
                    label
                }
                .buttonStyle(MoneyPressStyle())
            }
        }
        .modifier(FinanceCardChrome())
    }

    fileprivate func photoStrip(_ items: [VehicleMediaData.Item]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(items) { item in
                    photoButton(item)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .modifier(FinanceCardChrome())
    }

    fileprivate func photoButton(_ item: VehicleMediaData.Item) -> some View {
        Button {
            handlePhotoTap(item)
        } label: {
            VehiclePhotoCard(item: item)
        }
        .buttonStyle(.plain)
        .contextMenu { photoMenu(item) }
        .accessibilityLabel(Self.photoSpoken(item))
    }

    /// VoiceOver：「封面，車輛照片，新車交車，2024/9/5，3 張照片」
    fileprivate static func photoSpoken(_ item: VehicleMediaData.Item) -> String {
        let kind = item.category?.rawValue ?? "支出"
        let cover = item.isCover ? "封面，" : ""
        let count = item.fileNames.isEmpty ? "沒有照片" : "\(item.fileNames.count) 張照片"
        return "\(cover)\(kind)，\(item.title)，\(item.dateText)，\(count)"
    }

    /// 長按：照片紀錄「編輯資訊」「刪除」；支出「打開那筆記帳」（都要付費；刪除先確認）
    @ViewBuilder
    fileprivate func photoMenu(_ item: VehicleMediaData.Item) -> some View {
        switch item.source {
        case .record(let id):
            Button {
                requirePremium { editPhotoRecord(id) }
            } label: {
                Label("編輯資訊", systemImage: "pencil")
            }
            Button(role: .destructive) {
                requirePremium { confirmDeletePhotoRecord(id) }
            } label: {
                Label("刪除", systemImage: "trash")
            }
        case .expense(let id):
            Button {
                requirePremium { openExpenseRecord(id) }
            } label: {
                Label("打開那筆記帳", systemImage: "list.bullet.rectangle")
            }
        }
    }

    /// 點照片一律用 CutePhotoViewer 看全部（看不用付費）；沒照片的紀錄點了是去編輯（付費）
    fileprivate func handlePhotoTap(_ item: VehicleMediaData.Item) {
        switch item.source {
        case .record(let id):
            guard !item.fileNames.isEmpty else {
                requirePremium { editPhotoRecord(id) }
                return
            }
            let urls = item.fileNames.map { VehiclePhotoRecord.photoURL(for: $0) }
            let kind = CutePhotoDraft.Kind.vehicle(item.category ?? .other)
            sheet = .photos(CutePhotoDraft(urls: urls, title: item.title, note: item.note, date: item.date, kind: kind))
        case .expense:
            let urls = item.fileNames.map { Expense.photoURL(for: $0) }
            guard !urls.isEmpty else { return }
            let note = item.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let shown = note == item.title ? "" : note
            sheet = .photos(CutePhotoDraft(urls: urls, title: item.title, note: shown, date: item.date, kind: .expense))
        }
    }

    fileprivate func editPhotoRecord(_ id: UUID) {
        guard let rec = vehicle.photoRecords.first(where: { $0.id == id }) else {
            presentNotice("找不到這筆照片紀錄", "它可能已經被刪掉了。")
            return
        }
        sheet = .photoEditor(UUID(), rec, rec.category)
    }

    /// 刪除照片紀錄（J473）：「刪除「五萬公里保養」和 3 張照片？」
    fileprivate func confirmDeletePhotoRecord(_ id: UUID) {
        guard let rec = vehicle.photoRecords.first(where: { $0.id == id }) else { return }
        let trimmed = rec.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? rec.category.rawValue : trimmed
        let n = rec.photoFileNames.count
        let title = n > 0 ? "刪除「\(name)」和 \(n) 張照片？" : "刪除「\(name)」？"
        let message = n > 0 ? "iCloud 上的備份也會一起刪掉。" : "這筆照片紀錄會刪掉，不能復原。"
        pendingConfirm = VehicleConfirm(title: title, message: message, button: "刪除",
                                        action: { deletePhotoRecord(id) })
    }

    /// 照片檔（連 iCloud 備份）和紀錄一起刪（同 VehiclePhotoEditor.deleteRecord）
    fileprivate func deletePhotoRecord(_ id: UUID) {
        guard var v = store.vehicles.first(where: { $0.id == vehicleId }),
              let rec = v.photoRecords.first(where: { $0.id == id }) else { return }
        for name in rec.photoFileNames {
            VehiclePhotoRecord.deletePhoto(name)
        }
        v.photoRecords.removeAll { $0.id == id }
        store.update(v)
    }
}

// MARK: - 分享圖片

extension VehicleDetailView {
    fileprivate static let shareStampFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyyMMdd_HHmm"
        return f
    }()

    /// 帳本除了買車列沒有任何紀錄：直接出一張（看板＋每月養車）；有紀錄：先問每頁幾筆
    fileprivate func shareTapped() {
        guard let card else { return }
        if card.ledger.isEmpty {
            exportCardImage(card)
        } else {
            askExportPageSize = true
        }
    }

    /// 算圖一律淺色；各區讀的環境物件用 .appStores() 補上（缺了 ImageRenderer 會當掉）
    fileprivate static func exportDecorate(_ view: AnyView) -> AnyView {
        AnyView(view.appStores().environment(\.colorScheme, .light))
    }

    /// 每頁頁首「🚗 載具｜Taycan」（車名像車牌時是「品牌 動力」）
    fileprivate static func exportPageHeader(_ card: VehicleCardData) -> AnyView {
        AnyView(
            HStack {
                Text(card.shareHeader)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
        )
    }

    /// 分享用的那一份（J494）：車貸列的名稱可能是自己取的（地址、人名），改寫「車貸」「第 N 筆」。
    /// 其他會外流的（車主、地點、家充、里程、照片、備註、車輛資料）所在的區根本不放進分享圖
    fileprivate static func shareCard(_ card: VehicleCardData) -> VehicleCardData {
        guard var loan = card.loan else { return card }
        let many = loan.rows.count > 1
        loan.rows = loan.rows.map { shareLoanRow($0, many: many) }
        var copy = card
        copy.loan = loan
        return copy
    }

    fileprivate static func shareLoanRow(_ r: VehicleLoanSectionData.Row, many: Bool) -> VehicleLoanSectionData.Row {
        let title = many ? "第 \(r.index) 筆" : "車貸"
        return VehicleLoanSectionData.Row(id: r.id, source: r.source, index: r.index, status: r.status,
                                          badge: r.badge, title: title, range: r.range, amount: r.amount,
                                          statusText: r.statusText, progress: r.progress, nextText: r.nextText,
                                          isUnlinked: r.isUnlinked, termMissing: r.termMissing, canStop: r.canStop,
                                          deleteMessage: r.deleteMessage, accessibilityText: r.accessibilityText)
    }

    fileprivate static func exportSingleContent(_ card: VehicleCardData) -> some View {
        VStack(spacing: 16) {
            VehicleCardBoard(data: card, scrollTo: nil)
            if card.monthly != nil {
                VehicleMonthlySection(data: card, actions: VehicleCardActions(), forExport: true)
            }
        }
        .padding(.horizontal, 16)
        .frame(width: 430)
        .padding(.vertical, 20)
        .background(Color(.systemGroupedBackground))
    }

    /// 單張 JPG（寬 430、scale 照 ImageExportLimits、品質 0.95），檔名「車輛卡片_<名>_yyyyMMdd_HHmm.jpg」（西曆）
    @MainActor
    fileprivate func exportCardImage(_ card: VehicleCardData) {
        let safe = Self.shareCard(card)
        let content = Self.exportDecorate(AnyView(Self.exportSingleContent(safe)))
        let renderer = ImageRenderer(content: content)
        var measured = CGSize.zero
        renderer.render { size, _ in measured = size }
        renderer.scale = ImageExportLimits.safeScale(for: measured)
        guard let ui = renderer.uiImage, !ImageExportLimits.isBlank(ui),
              let data = ui.jpegData(compressionQuality: 0.95) else { return }
        let base = PagedImageExporter.sanitizeFileName(safe.shareFileBase)
        let name = "\(base)_\(Self.shareStampFmt.string(from: Date())).jpg"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            sheet = .share(StockCardSharePayload(items: [url]))
        } catch { }
    }

    /// 分頁：看板、每月養車、車貸、帳本總表當第一頁的開頭區塊，接著「紀錄 N 筆」和逐筆（分享版的標題、細字）
    @MainActor
    fileprivate func exportPaged(perPage: Int) {
        guard let current = card else { return }
        let safe = Self.shareCard(current)
        let urls = PagedImageExporter.exportSections(
            baseName: safe.shareFileBase,
            itemsPerPage: perPage,
            header: Self.exportPageHeader(safe),
            items: Self.exportItems(safe),
            decorate: { Self.exportDecorate($0) }
        )
        guard !urls.isEmpty else { return }
        sheet = .share(StockCardSharePayload(items: urls))
    }

    /// 區塊標題左右留 20，往外推 4 跟逐筆的卡對齊（同房屋）
    fileprivate static func exportItems(_ card: VehicleCardData) -> [PagedExportItem] {
        let actions = VehicleCardActions()
        var items: [PagedExportItem] = []
        let board = VehicleCardBoard(data: card, scrollTo: nil)
        items.append(.sectionHeader(AnyView(board.padding(.horizontal, -4))))
        if card.monthly != nil {
            let monthly = VehicleMonthlySection(data: card, actions: actions, forExport: true)
            items.append(.sectionHeader(AnyView(monthly.padding(.horizontal, -4))))
        }
        if card.loan != nil {
            let loan = VehicleLoanSection(data: card, actions: actions, forExport: true)
            items.append(.sectionHeader(AnyView(loan.padding(.horizontal, -4))))
        }
        let summary = exportLedgerSummary(card, actions: actions)
        items.append(.sectionHeader(AnyView(summary.padding(.horizontal, -4))))
        let count = card.ledger.recordCount
        let trailing: String? = count > 0 ? "\(count) 筆" : nil
        items.append(.sectionHeader(AnyView(MoneySectionHeader(title: "紀錄", trailing: trailing))))
        items += card.ledger.events.map { e -> PagedExportItem in
            .row(AnyView(VehicleLedgerRowView(event: e, forShare: true)))
        }
        return items
    }

    fileprivate static func exportLedgerSummary(_ card: VehicleCardData, actions: VehicleCardActions) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MoneySectionHeader(title: "我的帳本", trailing: card.ledger.headerTrailing)
            VehicleLedgerSummaryCard(data: card, actions: actions, forExport: true)
        }
    }
}

// MARK: - 照片卡

/// 照片與單據的一張卡（寬 120，沿用舊相簿卡的樣子）：縮圖（多張疊三層、右上張數）、封面小標、
/// 類別徽章（支出寫「支出」）、標題跑馬燈、日期
private struct VehiclePhotoCard: View {
    let item: VehicleMediaData.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            thumb
            badge
            MarqueeText(item.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Text(item.dateText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 120)
    }

    private var thumb: some View {
        ZStack(alignment: .topTrailing) {
            thumbImages
            if item.fileNames.count >= 2 {
                Text("\(item.fileNames.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.black.opacity(0.55))
                    .clipShape(Capsule())
                    .padding(5)
            }
        }
        .overlay(alignment: .topLeading) { coverTag }
    }

    @ViewBuilder
    private var thumbImages: some View {
        if item.fileNames.count >= 2 {
            // 多張：後兩張斜角堆疊在底、首張在上。id 用檔名（不用 offset），增刪照片時縮圖不會閃成別張
            ZStack {
                ForEach(Array(item.fileNames.prefix(3).enumerated()).reversed(), id: \.element) { idx, name in
                    ThumbnailImageView(url: url(name))
                        .frame(width: 108, height: 108)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .rotationEffect(.degrees(Double(idx) * 3.5))
                        .offset(x: CGFloat(idx) * 3, y: CGFloat(idx) * -3)
                }
            }
            .frame(width: 116, height: 116)
        } else if let first = item.fileNames.first {
            ThumbnailImageView(url: url(first))
                .frame(width: 116, height: 116)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            emptyThumb
        }
    }

    /// 沒有照片的紀錄（點了去編輯）：淡色底＋類別圖示
    private var emptyThumb: some View {
        let tint = item.category?.color ?? Color.orange
        let icon = item.category?.icon ?? "photo"
        return RoundedRectangle(cornerRadius: 12)
            .fill(tint.opacity(0.12))
            .frame(width: 116, height: 116)
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(tint.opacity(0.7))
            }
    }

    @ViewBuilder
    private var coverTag: some View {
        if item.isCover {
            Text("封面")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color(tb: 0x1F9D57), in: Capsule())
                .padding(5)
        }
    }

    private var badge: some View {
        let color = item.category?.color ?? Color.orange
        let icon = item.category?.icon ?? "tag.fill"
        let text = item.category?.rawValue ?? "支出"
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
    }

    private func url(_ name: String) -> URL {
        switch item.source {
        case .record: return VehiclePhotoRecord.photoURL(for: name)
        case .expense: return Expense.photoURL(for: name)
        }
    }
}

/// 「＋」選單的四項（J475）
private struct VehiclePhotoAddOption: Identifiable {
    let title: String
    let category: VehiclePhotoCategory
    var id: String { title }

    static let all: [VehiclePhotoAddOption] = [
        VehiclePhotoAddOption(title: "加車輛照片", category: .appearance),
        VehiclePhotoAddOption(title: "加保養單", category: .maintenance),
        VehiclePhotoAddOption(title: "加保險・稅費文件", category: .insurance),
        VehiclePhotoAddOption(title: "加事故照片", category: .accident)
    ]
}

// MARK: - 彈出頁與確認框的型別

/// 卡片上所有彈出頁（一個 .sheet(item:)）。每次「新增」都帶一個新的 UUID：
/// 跟「打開」綁在一起，不會帶到上一次的內容（v25.532 教訓：不要先設值再 set Bool）
private enum VehicleSheet: Identifiable {
    case edit(VehicleEditFocus)
    case editExpense(Expense, showVehicleSection: Bool)
    case newExpense(VehicleExpenseRequest)
    case photoEditor(UUID, VehiclePhotoRecord?, VehiclePhotoCategory)
    case photos(CutePhotoDraft)
    case chargeAnalytics
    case share(StockCardSharePayload)

    var id: String {
        switch self {
        case .edit(let focus): return "edit-\(focus)"
        case .editExpense(let ex, _): return "expense-" + ex.id.uuidString
        case .newExpense(let request): return "newExpense-" + request.id.uuidString
        case .photoEditor(let token, _, _): return "photoEditor-" + token.uuidString
        case .photos(let draft): return "photos-" + draft.id.uuidString
        case .chargeAnalytics: return "chargeAnalytics"
        case .share(let payload): return "share-" + payload.id.uuidString
        }
    }
}

/// 新增一筆記帳：種類和預設值跟「打開」綁在一起（不叫 NewExpenseRequest：房屋那個是 private 同名）
private struct VehicleExpenseRequest {
    let id = UUID()
    let expenseType: ExpenseType
    let preset: AddExpensePreset
}

/// 一個確認框（button 是 nil 時只是告訴你一件事，只有「好」）
private struct VehicleConfirm: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var button: String? = nil
    var destructive = true
    var action: () -> Void = {}
}

/// 一個選單（沒連到記帳的舊鏡像：補建或移除）
private struct VehicleChoice: Identifiable {
    struct Option: Identifiable {
        let id = UUID()
        let label: String
        var destructive = false
        let action: () -> Void
    }
    let id = UUID()
    let title: String
    let message: String
    let options: [Option]
}

/// 補建舊定期：打開記帳頁那一刻的鏡像、車子和所有支出 id（關掉時比對有沒有多一筆）
private struct VehicleBackfill {
    let mirrorId: UUID
    let vehicleId: UUID
    let existingIds: Set<UUID>
}
