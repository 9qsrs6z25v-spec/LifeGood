import SwiftUI
import UniformTypeIdentifiers

// [v25.534] 房屋卡片（換新卡片）的外殼：跟股票卡片同一個樣子（換房列、看板、一欄捲到底、分享）。
// - 卡片上的字和數字全在 HouseCardData.build 一次算好（只在 .task 裡算，換房、記帳或房子改了才重算）；
//   各區畫面在 HouseCardViews.swift，這裡只管排列順序、彈出頁、確認框、付費和分享。
// - 看資料免費；新增、編輯、刪除、修正都先過 requirePremium，選單在打開前就擋。
// - 彈出頁收成一個 HouseSheet＋一個 .sheet(item:)，確認框一個 HouseConfirm；fileImporter 單獨掛在穩定的容器上。
// - 「樓層與物品」「照片與文件」綁著物品樹和照片匯入，留在這個檔案畫（物品樹攤平＋單一 ForEach、
//   寫回 store 延後一個 runloop，兩個都是真機閃退的修正，不能拿掉）。
// - 編輯頁、照片檢視器、縮圖都搬到 RealEstateEditors.swift。
// - [v25.567] 房貸下面一段「從哪扣」（WealthLoanPayFromSection；改的是記帳那一筆固定支出、從下一期起；judge §6.3）。分享不放。

struct RealEstateDetailView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    /// @State 而不是 let：換房列點一下就換一間（同一張卡換內容，不重開 sheet）
    @State private var estateId: UUID
    /// 列表傳進來的順序（同一組：持有中／已售出）；空的時候用 store 的順序
    private let order: [UUID]
    /// 打開時要捲到哪一區（人生模式打開捲到「房屋資料」）；捲過一次就清掉
    @State private var startAnchor: HouseAnchor?
    /// 換房的方向（+1 往右邊那間、-1 往左邊），決定滑入的方向
    @State private var slideDirection: Int = 1

    /// 卡片上全部的字與數字：只在 .task(id: cardTaskKey) 裡算
    @State private var card: HouseCardData?
    @State private var ledgerFilter: HouseLedgerFilter = .all
    /// 「樓層與物品」展開的那一層（一次只開一層）
    @State private var expandedFloorId: UUID?

    @State private var sheet: HouseSheet?
    @State private var pendingConfirm: HouseConfirm?
    @State private var pendingChoice: HouseChoice?
    @State private var showPremiumAlert = false
    @State private var showDocumentPicker = false
    @State private var askExportPageSize = false

    init(estate: RealEstate, order: [UUID] = [], startAt: HouseAnchor? = nil) {
        _estateId = State(initialValue: estate.id)
        self.order = order
        _startAnchor = State(initialValue: startAt)
    }

    private static let placeholder = RealEstate(name: "")

    /// 目前這間（store 裡最新的那一份；被刪掉時是空的佔位，.task 會把卡片關掉）
    fileprivate var estate: RealEstate {
        store.realEstates.first(where: { $0.id == estateId }) ?? Self.placeholder
    }

    /// 換房列：列表傳進來的順序，只留跟目前這間同一組（持有中／已售出）的
    private var siblings: [RealEstate] {
        let current = estate
        let all = store.realEstates
        var list: [RealEstate]
        if order.isEmpty {
            list = all
        } else {
            let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            list = order.compactMap { byId[$0] }
            if !list.contains(where: { $0.id == current.id }), byId[current.id] != nil {
                list.append(current)
            }
        }
        return list.filter { $0.isSold == current.isSold }
    }

    private var titleText: String {
        if let card { return card.name }
        let name = estate.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "未命名房屋" : name
    }

    /// 換房、記帳改了、房子改了都要重算
    private var cardTaskKey: String {
        "\(estateId.uuidString)-\(store.modifyID)-\(expenseStore.modifyID)"
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
        // 換房列釘在導覽列下面：同一組不只一間才出現。不做整頁左右滑（會跟照片橫捲、長按、階梯圖打架）
        .safeAreaInset(edge: .top, spacing: 0) { switcherBar }
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
    }

    // MARK: - 算卡片、換房

    /// 只有這裡會算 HouseCardData（在主執行緒：MoneyFormat 共用一個 NumberFormatter）
    private func rebuildCard(_ proxy: ScrollViewProxy) {
        guard let re = store.realEstates.first(where: { $0.id == estateId }) else {
            // 房子被刪掉了（編輯頁最下面刪的、或別台裝置同步過來的）：卡片沒有東西可看了。
            // 晚一點才關：編輯頁可能還在往下收，一邊收一邊關卡片會被 UIKit 擋掉
            card = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismiss() }
            return
        }
        card = HouseCardData.build(re, expense: expenseStore)
        guard let anchor = startAnchor else { return }
        startAnchor = nil
        // 等各區真的畫出來再捲：只排到下一個 main.async 的話，可能比這次畫面更新還早跑，
        // 那時候還是空的佔位，找不到「房屋資料」就不會捲
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    private func select(_ id: UUID, in list: [RealEstate]) {
        let from = list.firstIndex { $0.id == estateId } ?? 0
        let to = list.firstIndex { $0.id == id } ?? 0
        jump(to: id, direction: to >= from ? 1 : -1)
    }

    /// 換到另一間：卡片、帳本篩選、展開的樓層、還沒按的確認框一起清掉，.task 會用新的 id 重算
    private func jump(to id: UUID, direction: Int) {
        guard id != estateId else { return }
        slideDirection = direction
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            estateId = id
            card = nil
            ledgerFilter = .all
            expandedFloorId = nil
            pendingConfirm = nil
            pendingChoice = nil
        }
    }

    @ViewBuilder
    private var switcherBar: some View {
        let list = siblings
        if list.count > 1 {
            FinanceSwitcherStrip(items: switcherItems(list), selected: estateId) { id in
                select(id, in: list)
            }
            .padding(.vertical, 4)
            .background(.bar)
        }
    }

    private func switcherItems(_ list: [RealEstate]) -> [FinanceSwitcherItem] {
        list.map { re -> FinanceSwitcherItem in
            let trailing = HouseCardData.switcherTrailing(re)
            let name = re.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = MoneyBoardText.short(name.isEmpty ? "未命名房屋" : name, max: 6)
            return FinanceSwitcherItem(id: re.id, title: title,
                                       trailing: trailing?.text ?? "", tone: trailing?.tone ?? .neutral)
        }
    }

    // MARK: - 工具列

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("關閉") { dismiss() }
        }
        // 標題就是房名，太長跑馬燈
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
                    requirePremium { sheet = .edit(HouseEditFocus.none) }
                } label: {
                    Text("編輯").foregroundStyle(.green)
                }
                // 刪除整間只在列表左滑、編輯頁最下面（都會先確認）
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
        // 換房時整包內容依方向滑入（id 變了就觸發轉場）
        .id(estateId)
        .transition(slideTransition)
    }

    /// 看板、要確認、房貸、每個月住這裡、出租、帳本（各區自己決定整區要不要出現）
    @ViewBuilder
    private func upperSections(_ card: HouseCardData, actions: HouseCardActions, proxy: ScrollViewProxy) -> some View {
        HouseCardBoard(data: card, onTapProgress: { scroll(proxy, to: .mortgage) })
            .id(HouseAnchor.top)
        HouseChecksSection(data: card, actions: actions)
            .id(HouseAnchor.checks)
        HouseMortgageSection(data: card, actions: actions)
            .id(HouseAnchor.mortgage)
        WealthLoanPayFromSection(expenseIds: loanPayIds)
        HouseLivingSection(data: card, actions: actions)
            .id(HouseAnchor.living)
        HouseRentalSection(data: card)
            .id(HouseAnchor.rental)
        HouseLedgerSection(data: card, filter: $ledgerFilter, actions: actions)
            .id(HouseAnchor.ledger)
    }

    /// [v25.567] 這間房的貸款固定支出（房貸「從哪扣」那一段）：記帳連到這間房、或房子的貸款項目連著的；還在扣的、有週期的
    private var loanPayIds: [UUID] {
        let itemIds = Set(estate.mortgageItems.compactMap { $0.linkedExpenseId })
        return expenseStore.expenses.filter { e in
            guard e.expenseType == .fixed, e.fixedCategory == .loan, e.recurrence != nil, !e.isFixedEnded else { return false }
            return e.linkedRealEstateId == estateId || itemIds.contains(e.id)
        }.map(\.id)
    }

    /// 房屋資料、樓層與物品、照片與文件、水電瓦斯、電梯保養
    @ViewBuilder
    private func lowerSections(_ card: HouseCardData, actions: HouseCardActions) -> some View {
        HouseInfoSection(estate: card.estate, data: card, actions: actions)
            .id(HouseAnchor.info)
        floorsSection(card)
            .id(HouseAnchor.floors)
        photosSection(card)
            .id(HouseAnchor.photos)
        HouseUtilitiesSection(estate: card.estate, data: card, actions: actions)
            .id(HouseAnchor.utilities)
        HouseElevatorSection(estate: card.estate, data: card, actions: actions)
            .id(HouseAnchor.elevator)
    }

    fileprivate func scroll(_ proxy: ScrollViewProxy, to anchor: HouseAnchor) {
        withAnimation(.easeInOut(duration: 0.35)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    // MARK: - 彈出頁、確認框

    private func withPresentations<Content: View>(_ content: Content) -> some View {
        withAlerts(withSheets(content))
    }

    private static let documentTypes: [UTType] = [
        .pdf, .presentation, .spreadsheet, .text, .commaSeparatedText,
        .plainText, .rtf, .image, .data
    ]

    private func withSheets<Content: View>(_ content: Content) -> some View {
        content
            .sheet(item: $sheet) { s in sheetView(s).appStores() }
            // fileImporter 掛在穩定的 NavigationStack 上（不要掛在「＋」選單的 label：
            // 那是暫態 view，關閉檔案選單時回寫 binding 會閃退）
            .fileImporter(isPresented: $showDocumentPicker,
                          allowedContentTypes: Self.documentTypes,
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { importDocuments(urls) }
            }
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
    private func confirmButtons(_ c: HouseConfirm) -> some View {
        if let label = c.button {
            Button(label, role: c.destructive ? .destructive : nil) { c.action() }
            Button("取消", role: .cancel) {}
        } else {
            Button("好", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func choiceButtons(_ c: HouseChoice) -> some View {
        ForEach(c.options) { o in
            Button(o.label, role: o.destructive ? .destructive : nil) { o.action() }
        }
        Button("取消", role: .cancel) {}
    }

    @ViewBuilder
    private func sheetView(_ s: HouseSheet) -> some View {
        switch s {
        case .edit, .share, .newExpense, .editExpense, .floorItem:
            recordSheet(s)
        default:
            mediaSheet(s)
        }
    }

    /// 編輯頁、分享、記帳、樓層物品
    @ViewBuilder
    private func recordSheet(_ s: HouseSheet) -> some View {
        switch s {
        case .edit(let focus):
            AddRealEstateView(editing: estate, focus: focus)
        case .share(let payload):
            ShareSheet(items: payload.items)
        case .newExpense(let request):
            AddExpenseView(expenseType: request.expenseType, preset: request.preset)
        case .editExpense(let ex):
            AddExpenseView(expenseType: ex.expenseType, editingExpense: ex)
        case .floorItem(let target):
            floorItemEditor(target)
        default:
            EmptyView()
        }
    }

    /// 水電、電梯、裝潢照片、看照片、看文件
    @ViewBuilder
    private func mediaSheet(_ s: HouseSheet) -> some View {
        switch s {
        case .newUtility:
            UtilityPaymentEditor(estateId: estateId, editing: nil)
        case .editUtility(let payment):
            UtilityPaymentEditor(estateId: estateId, editing: payment)
        case .newElevator:
            ElevatorMaintenanceEditor(estateId: estateId, editing: nil)
        case .editElevator(let record):
            ElevatorMaintenanceEditor(estateId: estateId, editing: record)
        case .newRenovation:
            RenovationPhotoEditor(estateId: estateId, editing: nil)
        case .editRenovation(let photo):
            RenovationPhotoEditor(estateId: estateId, editing: photo)
        case .photos(let draft):
            CutePhotoViewer(draft: draft)
        case .document(let wrapper):
            DocumentQuickLookView(url: wrapper.url)
        default:
            EmptyView()
        }
    }

    private func floorItemEditor(_ target: FloorItemEditTarget) -> some View {
        FloorItemEditor(initialName: target.currentName, isEditing: target.itemId != nil) { newName in
            if let itemId = target.itemId {
                renameFloorItem(floorId: target.floorId, itemId: itemId, newName: newName)
            } else {
                addFloorItem(floorId: target.floorId, parentItemId: target.parentItemId, name: newName)
            }
        }
    }
}

// MARK: - 動作（HouseCardActions 的每一個 closure）

extension RealEstateDetailView {
    /// 新增、編輯、刪除、修正的唯一一道門：看資料免費，改資料付費
    fileprivate func requirePremium(_ action: () -> Void) {
        if subscription.isPremium {
            action()
        } else {
            showPremiumAlert = true
        }
    }

    fileprivate func makeActions(_ proxy: ScrollViewProxy) -> HouseCardActions {
        var a = HouseCardActions()
        a.scrollTo = { anchor in scroll(proxy, to: anchor) }
        // 篩選只改變顯示：跟篩選膠囊同一個動畫（easeOut 0.25）
        a.setLedgerFilter = { filter in
            withAnimation(.easeOut(duration: 0.25)) { ledgerFilter = filter }
        }
        a.edit = { focus in requirePremium { sheet = .edit(focus) } }
        a.fixCheck = { check in fixCheck(check) }
        a.openSegment = { seg in requirePremium { openSegmentRecord(seg) } }
        a.deleteSegment = { seg in requirePremium { confirmDeleteSegment(seg) } }
        a.addSegment = { requirePremium { presentNewMortgage() } }
        a.addLedger = { kind in requirePremium { presentAdd(kind) } }
        a.openLedger = { event in openLedger(event, proxy: proxy) }
        a.deleteLedger = { event in deleteLedger(event) }
        a.openExpense = { id in requirePremium { openExpenseRecord(id) } }
        a.openUtility = { payment in requirePremium { presentUtility(payment) } }
        a.openElevator = { record in requirePremium { presentElevator(record) } }
        a.showPhotos = { draft in sheet = .photos(draft) }
        // 「＋ 記一筆」選單在打開前就擋：沒付費時畫面換成普通按鈕，按了跳付費說明
        a.canEdit = subscription.isPremium
        a.askPremium = { showPremiumAlert = true }
        return a
    }

    /// 只是告訴你一件事（只有「好」）
    fileprivate func presentNotice(_ title: String, _ message: String) {
        pendingConfirm = HouseConfirm(title: title, message: message)
    }

    /// 從選單（confirmationDialog）選了之後再跳確認框：等選單收完再出來，不然確認框會被吃掉
    fileprivate func presentConfirmLater(_ c: HouseConfirm) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            pendingConfirm = c
        }
    }

    fileprivate func presentUtility(_ payment: UtilityPayment?) {
        if let payment {
            sheet = .editUtility(payment)
        } else {
            sheet = .newUtility(UUID())
        }
    }

    fileprivate func presentElevator(_ record: ElevatorMaintenance?) {
        if let record {
            sheet = .editElevator(record)
        } else {
            sheet = .newElevator(UUID())
        }
    }

    /// 打開記帳裡那一筆（保險列、家電、帳本列）。賣出虧損那筆是跟著成交價自動算的，不給改
    fileprivate func openExpenseRecord(_ id: UUID) {
        if id == estate.saleLinkedExpenseId {
            presentNotice("這一筆是賣房的虧損",
                          "它跟著購入價和成交價自動算，要改請到「編輯」改成交價。")
            return
        }
        guard let ex = expenseStore.expenses.first(where: { $0.id == id }) else {
            presentNotice("找不到這筆記帳", "記帳裡已經沒有這一筆了（可能在記帳那邊刪掉了）。")
            return
        }
        sheet = .editExpense(ex)
    }

    // MARK: 記一筆、加一段

    /// 「＋ 加一段」、記一筆的「房貸一段」：起始日接在最後一段的最後一期（貸款第一期是起始日的下一期，剛好接上）
    fileprivate func presentNewMortgage() {
        let start = card?.mortgage?.newSegmentStart ?? Date()
        let preset = AddExpensePreset(
            fixedCategory: .loan,
            loanSubCategory: .mortgage,
            recurrence: .monthly,
            linkedRealEstateId: estateId,
            mortgageLinkExisting: true,
            date: start
        )
        sheet = .newExpense(NewExpenseRequest(expenseType: .fixed, preset: preset))
    }

    /// 「＋ 記一筆」：水電瓦斯直接開繳費編輯器；其他開記帳（分類先帶好）。賣掉的房子日期預設賣出日
    fileprivate func presentAdd(_ kind: HouseLedgerAddKind) {
        switch kind {
        case .mortgageSegment:
            presentNewMortgage()
        case .utility:
            sheet = .newUtility(UUID())
        default:
            guard let category = kind.category else { return }
            var preset = AddExpensePreset(
                variableCategory: .realEstate,
                realEstateExpenseCategory: category,
                linkedRealEstateId: estateId,
                assetLink: .realEstate,
                realEstateLinkExisting: true
            )
            if estate.isSold, let sold = estate.soldDate { preset.date = sold }
            sheet = .newExpense(NewExpenseRequest(expenseType: .variable, preset: preset))
        }
    }

    // MARK: 帳本列

    /// 房貸年列捲到房貸區（不用付費）；其他都是去改資料（付費）
    fileprivate func openLedger(_ e: HouseLedgerEvent, proxy: ScrollViewProxy) {
        if case .mortgageYear = e.source {
            scroll(proxy, to: .mortgage)
            return
        }
        requirePremium { openLedgerRecord(e) }
    }

    fileprivate func openLedgerRecord(_ e: HouseLedgerEvent) {
        switch e.source {
        case .expense(let id):
            openExpenseRecord(id)
        case .utility(let paymentId):
            if let payment = estate.utilityPayments.first(where: { $0.id == paymentId }) {
                sheet = .editUtility(payment)
            } else if let id = e.expenseId {
                openExpenseRecord(id)
            }
        case .mortgageYear:
            break
        case .fixedYear(let id, _):
            openExpenseRecord(id)
        case .legacy(let kind, let itemId):
            offerLegacyChoices(e, kind: kind, itemId: itemId)
        }
    }

    /// 長按刪除：房貸年列、固定支出年列不是一筆真的記帳，不能刪
    fileprivate func deleteLedger(_ e: HouseLedgerEvent) {
        guard e.canDelete, !e.isYearRow else { return }
        requirePremium { confirmDeleteLedger(e) }
    }

    fileprivate func confirmDeleteLedger(_ e: HouseLedgerEvent) {
        let title = "刪除「\(e.title) \(e.amountText)」？"
        if let expId = e.expenseId, expenseStore.expenses.contains(where: { $0.id == expId }) {
            var message = "記帳裡這筆支出"
            if let bank = bankName(forExpense: expId) {
                message += "和\(bank)的扣款紀錄會一起刪除，不能復原。"
            } else {
                message += "會一起刪除，不能復原。"
            }
            message += ledgerDeleteExtra(expId)
            pendingConfirm = HouseConfirm(title: title, message: message, button: "刪除",
                                          action: { deleteLedgerExpense(expId) })
        } else if case .legacy(let kind, let itemId) = e.source {
            pendingConfirm = HouseConfirm(title: title, message: legacyDeleteMessage(kind), button: "刪除",
                                          action: { deleteLegacyItem(kind, itemId: itemId) })
        }
    }

    /// 銀行帳戶裡真的有這筆扣款才提銀行名（信用卡、週期性固定支出不會有單筆扣款）
    fileprivate func bankName(forExpense id: UUID) -> String? {
        for ms in lifeStore.milestones {
            let deposits = ms.bankDeposits ?? []
            guard deposits.contains(where: { $0.linkedExpenseId == id }) else { continue }
            let bank = (ms.bankName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return bank.isEmpty ? ms.title : bank
        }
        return nil
    }

    /// 刪的是保險或家電那筆支出時，房子那邊的那一項也會拿掉：先講清楚
    fileprivate func ledgerDeleteExtra(_ expId: UUID) -> String {
        let re = estate
        if re.insuranceItems.contains(where: { $0.linkedExpenseId == expId }) {
            return "「房屋資料」裡的這張保單也會一起拿掉。"
        }
        if re.propertyAssets.contains(where: { $0.linkedExpenseId == expId }) {
            return "「樓層與物品」裡的這件家電家具也會一起拿掉。"
        }
        if re.utilityPayments.contains(where: { $0.linkedExpenseId == expId }) {
            return "水電的這筆繳費紀錄和收據照片也會一起刪掉。"
        }
        return ""
    }

    /// 刪記帳支出（含照片、所有銀行帳戶裡的扣款），再把房子所有陣列裡連到它的項目拿掉。
    /// 新帳本已經用支出 id 去重：一筆只會出現一列，所以這裡不用再分「共用支出的重複列」
    fileprivate func deleteLedgerExpense(_ expId: UUID) {
        guard var re = store.realEstates.first(where: { $0.id == estateId }) else { return }
        RealEstateDeletion.removeExpenses([expId], expenseStore: expenseStore, lifeStore: lifeStore)
        for p in re.utilityPayments where p.linkedExpenseId == expId {
            p.photoFileNames.forEach { UtilityPayment.deletePhoto($0) }
        }
        re.utilityPayments.removeAll { $0.linkedExpenseId == expId }
        re.paidItems.removeAll { $0.linkedExpenseId == expId }
        re.variableExpenses.removeAll { $0.linkedExpenseId == expId }
        re.insuranceItems.removeAll { $0.linkedExpenseId == expId }
        re.propertyAssets.removeAll { $0.linkedExpenseId == expId }
        re.mortgageItems.removeAll { $0.linkedExpenseId == expId }
        if re.linkedExpenseId == expId { re.linkedExpenseId = nil }
        store.update(re)
    }

    // MARK: 沒連到記帳的舊資料

    fileprivate func offerLegacyChoices(_ e: HouseLedgerEvent, kind: HouseLedgerEvent.LegacyKind, itemId: UUID) {
        let message = "這筆 \(e.amountText) 只記在房子這邊，記帳裡沒有：不會算進記帳的支出，也沒有地方改。補建一筆記帳支出之後，點這一列就能編輯。"
        let backfill = HouseChoice.Option(label: "補建記帳支出", action: {
            presentConfirmLater(HouseConfirm(
                title: "補建記帳支出？",
                message: "在記帳新增一筆 \(e.amountText)（\(HouseCardFormat.ymd(e.date))），連到這間房子。不會動銀行帳戶。",
                button: "補建", destructive: false,
                action: { backfillLegacy(kind, itemId: itemId) }))
        })
        let remove = HouseChoice.Option(label: "刪除這一筆", destructive: true, action: {
            presentConfirmLater(HouseConfirm(
                title: "刪除「\(e.title) \(e.amountText)」？",
                message: legacyDeleteMessage(kind), button: "刪除",
                action: { deleteLegacyItem(kind, itemId: itemId) }))
        })
        pendingChoice = HouseChoice(title: "「\(e.title)」沒連到記帳", message: message, options: [backfill, remove])
    }

    fileprivate func legacyDeleteMessage(_ kind: HouseLedgerEvent.LegacyKind) -> String {
        switch kind {
        case .utility: return "這筆繳費紀錄只記在房子這邊（沒連到記帳），會連收據照片一起刪除，不能復原。"
        case .asset: return "這件家電家具只記在房子這邊（沒連到記帳），會從「樓層與物品」一起拿掉，不能復原。"
        case .insurance: return "這張保單只記在房子這邊（沒連到記帳），會從「房屋資料」一起拿掉，不能復原。"
        case .paid, .variable: return "這一筆只記在房子這邊（沒連到記帳），會從房子裡刪除，不能復原。"
        }
    }

    fileprivate func deleteLegacyItem(_ kind: HouseLedgerEvent.LegacyKind, itemId: UUID) {
        guard var re = store.realEstates.first(where: { $0.id == estateId }) else { return }
        switch kind {
        case .paid:
            re.paidItems.removeAll { $0.id == itemId }
        case .variable:
            re.variableExpenses.removeAll { $0.id == itemId }
        case .utility:
            for p in re.utilityPayments where p.id == itemId {
                p.photoFileNames.forEach { UtilityPayment.deletePhoto($0) }
            }
            re.utilityPayments.removeAll { $0.id == itemId }
        case .insurance:
            re.insuranceItems.removeAll { $0.id == itemId }
        case .asset:
            re.propertyAssets.removeAll { $0.id == itemId }
        }
        store.update(re)
    }

    /// 補建：照編輯頁建保險／附屬資產支出的欄位建一筆房地產變動支出，再把那一項改連過去（不寫銀行扣款）
    fileprivate func backfillLegacy(_ kind: HouseLedgerEvent.LegacyKind, itemId: UUID) {
        guard var re = store.realEstates.first(where: { $0.id == estateId }) else { return }
        guard let made = Self.legacyExpense(kind, itemId: itemId, in: re) else { return }
        let old = Self.legacyLink(kind, itemId: itemId, in: re)
        Self.setLegacyLink(kind, itemId: itemId, to: made.id, in: &re)
        // 同一個找不到的舊連結如果還掛在別的陣列，它們本來就是同一筆：一起改連到新的這筆
        if let old { Self.relink(&re, from: old, to: made.id) }
        expenseStore.add(made)
        store.update(re)
    }

    fileprivate static func legacyExpense(_ kind: HouseLedgerEvent.LegacyKind, itemId: UUID,
                                          in re: RealEstate) -> Expense? {
        let name = re.name.trimmingCharacters(in: .whitespacesAndNewlines)
        func make(_ title: String, _ amount: Double, _ date: Date,
                  _ category: RealEstateExpenseCategory, note: String = "") -> Expense {
            Expense(title: title, amount: amount, date: date, expenseType: .variable,
                    variableCategory: .realEstate, linkedRealEstateId: re.id,
                    realEstateExpenseCategory: category, note: note)
        }
        switch kind {
        case .paid:
            guard let it = re.paidItems.first(where: { $0.id == itemId }) else { return nil }
            let title = it.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return make(title.isEmpty ? "\(name) - 房屋價金" : title, it.amount, it.date, .housePayment)
        case .variable:
            guard let v = re.variableExpenses.first(where: { $0.id == itemId }) else { return nil }
            return make("\(name) - \(v.category.rawValue)", v.amount, v.date, v.category, note: v.name)
        case .utility:
            guard let p = re.utilityPayments.first(where: { $0.id == itemId }) else { return nil }
            return make("\(name) - \(p.type.rawValue)", p.amount, p.date, .utility, note: p.note)
        case .insurance:
            guard let it = re.insuranceItems.first(where: { $0.id == itemId }) else { return nil }
            let policy = it.policyNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            return make(policy.isEmpty ? "\(name) - 保險" : "\(name) - \(policy)", it.amount, re.purchaseDate, .insurance)
        case .asset:
            guard let a = re.propertyAssets.first(where: { $0.id == itemId }) else { return nil }
            let label = a.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return make("\(name) - \(label.isEmpty ? a.category.rawValue : label)", a.amount, re.purchaseDate, a.category)
        }
    }

    fileprivate static func legacyLink(_ kind: HouseLedgerEvent.LegacyKind, itemId: UUID, in re: RealEstate) -> UUID? {
        switch kind {
        case .paid: return re.paidItems.first(where: { $0.id == itemId })?.linkedExpenseId
        case .variable: return re.variableExpenses.first(where: { $0.id == itemId })?.linkedExpenseId
        case .utility: return re.utilityPayments.first(where: { $0.id == itemId })?.linkedExpenseId
        case .insurance: return re.insuranceItems.first(where: { $0.id == itemId })?.linkedExpenseId
        case .asset: return re.propertyAssets.first(where: { $0.id == itemId })?.linkedExpenseId
        }
    }

    fileprivate static func setLegacyLink(_ kind: HouseLedgerEvent.LegacyKind, itemId: UUID, to id: UUID,
                                          in re: inout RealEstate) {
        switch kind {
        case .paid:
            for i in re.paidItems.indices where re.paidItems[i].id == itemId { re.paidItems[i].linkedExpenseId = id }
        case .variable:
            for i in re.variableExpenses.indices where re.variableExpenses[i].id == itemId {
                re.variableExpenses[i].linkedExpenseId = id
            }
        case .utility:
            for i in re.utilityPayments.indices where re.utilityPayments[i].id == itemId {
                re.utilityPayments[i].linkedExpenseId = id
            }
        case .insurance:
            for i in re.insuranceItems.indices where re.insuranceItems[i].id == itemId {
                re.insuranceItems[i].linkedExpenseId = id
            }
        case .asset:
            for i in re.propertyAssets.indices where re.propertyAssets[i].id == itemId {
                re.propertyAssets[i].linkedExpenseId = id
            }
        }
    }

    fileprivate static func relink(_ re: inout RealEstate, from old: UUID, to new: UUID) {
        for i in re.paidItems.indices where re.paidItems[i].linkedExpenseId == old { re.paidItems[i].linkedExpenseId = new }
        for i in re.variableExpenses.indices where re.variableExpenses[i].linkedExpenseId == old {
            re.variableExpenses[i].linkedExpenseId = new
        }
        for i in re.utilityPayments.indices where re.utilityPayments[i].linkedExpenseId == old {
            re.utilityPayments[i].linkedExpenseId = new
        }
        for i in re.insuranceItems.indices where re.insuranceItems[i].linkedExpenseId == old {
            re.insuranceItems[i].linkedExpenseId = new
        }
        for i in re.propertyAssets.indices where re.propertyAssets[i].linkedExpenseId == old {
            re.propertyAssets[i].linkedExpenseId = new
        }
    }

    // MARK: 房貸段

    /// 點一段：連到記帳的開那筆固定支出；沒連到記帳的舊段說明一下，可以補建
    fileprivate func openSegmentRecord(_ seg: HouseFacts.Segment) {
        // 只在記帳裡、沒有房貸項目的段：seg.id 是支出 id，linkedExpenseId 也是它
        if let expId = seg.linkedExpenseId, let ex = expenseStore.expenses.first(where: { $0.id == expId }) {
            sheet = .editExpense(ex)
            return
        }
        guard let item = estate.mortgageItems.first(where: { $0.id == seg.id }) else {
            presentNotice("找不到這一段", "記帳和房子裡都已經沒有這段房貸了。")
            return
        }
        let message = "這段房貸（每期 \(MoneyFormat.short(item.amount))、\(HouseCardFormat.ym(item.startDate)) 起 \(item.totalPeriods) 期）只記在房子這邊，記帳的固定支出裡沒有，所以沒有地方改金額和年限。補建一筆記帳固定支出之後，點這一段就能編輯。"
        pendingConfirm = HouseConfirm(title: "「\(seg.displayTitle)」沒連到記帳", message: message,
                                      button: "補建記帳固定支出", destructive: false,
                                      action: { backfillSegment(itemId: item.id) })
    }

    /// 照 AddExpenseView 建房貸固定支出的欄位補一筆：固定、貸款、房貸、每月、起始日、每期金額、年限、連到這間
    fileprivate func backfillSegment(itemId: UUID) {
        guard var re = store.realEstates.first(where: { $0.id == estateId }),
              let i = re.mortgageItems.firstIndex(where: { $0.id == itemId }) else { return }
        let item = re.mortgageItems[i]
        let segName = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let years: Double? = item.totalPeriods > 0 ? Double(item.totalPeriods) / 12 : nil
        var ex = Expense(title: "【\(re.name)】" + (segName.isEmpty ? "房貸" : segName),
                         amount: item.amount, date: item.startDate, expenseType: .fixed,
                         fixedCategory: .loan, recurrence: .monthly, loanSubCategory: .mortgage,
                         linkedRealEstateId: re.id, loanYears: years)
        // 已經賣掉的房子：照賣房的規則停在賣出日，不然「要確認」又會說賣掉還在扣
        if let sold = re.soldDate {
            ex.endDate = sold
            ex.endReason = .assetSold
        }
        re.mortgageItems[i].linkedExpenseId = ex.id
        expenseStore.add(ex)
        store.update(re)
    }

    fileprivate func confirmDeleteSegment(_ seg: HouseFacts.Segment) {
        let hasExpense = seg.linkedExpenseId.map { id in expenseStore.expenses.contains { $0.id == id } } ?? false
        let message = hasExpense
            ? "會一起刪掉記帳裡這筆每月房貸，以及銀行的扣款紀錄，不能復原。"
            : "這一段會從房子裡刪除，不能復原。"
        pendingConfirm = HouseConfirm(title: "刪除「\(seg.displayTitle)」？", message: message, button: "刪除",
                                      action: { deleteSegment(seg) })
    }

    fileprivate func deleteSegment(_ seg: HouseFacts.Segment) {
        if estate.mortgageItems.contains(where: { $0.id == seg.id }) {
            deleteEstateItem(itemId: seg.id, linkedExpenseId: seg.linkedExpenseId)
            return
        }
        // 只在記帳裡的段（seg.id 是支出 id）：刪那筆支出；房子這邊還指著它的連結一起清
        guard let expId = seg.linkedExpenseId else { return }
        RealEstateDeletion.removeExpenses([expId], expenseStore: expenseStore, lifeStore: lifeStore)
        guard var re = store.realEstates.first(where: { $0.id == estateId }) else { return }
        re.mortgageItems.removeAll { $0.linkedExpenseId == expId }
        if re.linkedExpenseId == expId { re.linkedExpenseId = nil }
        store.update(re)
    }

    /// 刪房子底下一筆連到記帳的項目（v25.530）：跟保險／附屬資產／水電共用同一筆支出的重複列只拿掉列、不刪支出
    fileprivate func deleteEstateItem(itemId: UUID, linkedExpenseId: UUID?) {
        guard var re = store.realEstates.first(where: { $0.id == estateId }) else { return }
        let shared: Bool = linkedExpenseId.map { isExpenseShared($0, in: re) } ?? false
        if let expId = linkedExpenseId, !shared {
            RealEstateDeletion.removeExpenses([expId], expenseStore: expenseStore, lifeStore: lifeStore)
        }
        func shouldRemove(_ id: UUID, _ linked: UUID?) -> Bool {
            if id == itemId { return true }
            guard !shared, let expId = linkedExpenseId else { return false }
            return linked == expId
        }
        re.mortgageItems.removeAll { shouldRemove($0.id, $0.linkedExpenseId) }
        re.paidItems.removeAll { shouldRemove($0.id, $0.linkedExpenseId) }
        re.variableExpenses.removeAll { shouldRemove($0.id, $0.linkedExpenseId) }
        store.update(re)
    }

    fileprivate func isExpenseShared(_ expId: UUID, in re: RealEstate) -> Bool {
        if re.insuranceItems.contains(where: { $0.linkedExpenseId == expId }) { return true }
        if re.propertyAssets.contains(where: { $0.linkedExpenseId == expId }) { return true }
        return re.utilityPayments.contains(where: { $0.linkedExpenseId == expId })
    }

    // MARK: 要確認

    /// 每顆修正鈕：先付費，有確認文字的先確認；「去填／去改／去看」直接開編輯頁
    fileprivate func fixCheck(_ check: HouseCheck) {
        requirePremium {
            guard let confirm = check.confirm else {
                performFix(check.fix)
                return
            }
            let fix = check.fix
            pendingConfirm = HouseConfirm(title: fixTitle(check.kind), message: confirm, button: check.button,
                                          destructive: check.kind == .orphans,
                                          action: { performFix(fix) })
        }
    }

    fileprivate func fixTitle(_ kind: HouseCheck.Kind) -> String {
        switch kind {
        case .soldStillCharging: return "停掉賣出後的房貸扣款？"
        case .orphans: return "拿掉房子這邊留下的項目？"
        case .duplicates: return "整理重複的項目？"
        default: return "確定要修正嗎？"
        }
    }

    fileprivate func performFix(_ fix: HouseCheck.Fix) {
        switch fix {
        case .stopMortgagesAtSale:
            stopMortgagesAtSale()
        case .openSegment(let seg):
            openSegmentRecord(seg)
        case .removeOrphans(let links):
            removeOrphans(links)
        case .mergeDuplicates(let dups):
            mergeDuplicates(dups)
        case .edit(let focus):
            sheet = .edit(focus)
        }
    }

    /// 賣掉還在扣：連到這間的房貸固定支出停在賣出日（跟編輯頁存檔時同一個函式），記帳只寫一次
    fileprivate func stopMortgagesAtSale() {
        guard let re = store.realEstates.first(where: { $0.id == estateId }), let sold = re.soldDate else { return }
        var list = expenseStore.expenses
        if RealEstateSale.syncMortgageStops(of: re, soldDate: sold, in: &list) {
            expenseStore.expenses = list
        }
    }

    /// 記帳那邊已經刪掉的：房子這邊的項目拿掉；水電只解除連結（收據照片留著）；房子身上的連結清掉
    fileprivate func removeOrphans(_ links: [HouseItemLink]) {
        guard var re = store.realEstates.first(where: { $0.id == estateId }) else { return }
        let alive = Set(expenseStore.expenses.map(\.id))
        for link in links where !alive.contains(link.expenseId) {
            switch link.place {
            case .mortgage: re.mortgageItems.removeAll { $0.id == link.itemId }
            case .paid: re.paidItems.removeAll { $0.id == link.itemId }
            case .variable: re.variableExpenses.removeAll { $0.id == link.itemId }
            case .insurance: re.insuranceItems.removeAll { $0.id == link.itemId }
            case .asset: re.propertyAssets.removeAll { $0.id == link.itemId }
            case .utility:
                for i in re.utilityPayments.indices where re.utilityPayments[i].id == link.itemId {
                    re.utilityPayments[i].linkedExpenseId = nil
                }
            case .estateMortgage:
                if re.linkedExpenseId == link.expenseId { re.linkedExpenseId = nil }
            case .estateSale:
                if re.saleLinkedExpenseId == link.expenseId { re.saleLinkedExpenseId = nil }
            }
        }
        store.update(re)
    }

    /// 同一筆支出掛在好幾處：只留在 keep 那個陣列（同陣列重複留第一列），其餘拿掉；記帳的支出不刪
    fileprivate func mergeDuplicates(_ dups: [HouseDuplicate]) {
        guard var re = store.realEstates.first(where: { $0.id == estateId }) else { return }
        let paymentsBefore = re.utilityPayments
        for d in dups {
            let id = d.expenseId
            re.insuranceItems = Self.keepOne(re.insuranceItems, expenseId: id, keep: d.keep == .insurance) { $0.linkedExpenseId }
            re.propertyAssets = Self.keepOne(re.propertyAssets, expenseId: id, keep: d.keep == .asset) { $0.linkedExpenseId }
            re.utilityPayments = Self.keepOne(re.utilityPayments, expenseId: id, keep: d.keep == .utility) { $0.linkedExpenseId }
            re.paidItems = Self.keepOne(re.paidItems, expenseId: id, keep: d.keep == .paid) { $0.linkedExpenseId }
            re.variableExpenses = Self.keepOne(re.variableExpenses, expenseId: id, keep: d.keep == .variable) { $0.linkedExpenseId }
        }
        // 拿掉的水電列：收據照片沒有別的列在用才刪檔
        let keptIds = Set(re.utilityPayments.map(\.id))
        let stillUsed = Set(re.utilityPayments.flatMap(\.photoFileNames))
        for p in paymentsBefore where !keptIds.contains(p.id) {
            for name in p.photoFileNames where !stillUsed.contains(name) { UtilityPayment.deletePhoto(name) }
        }
        store.update(re)
    }

    /// 連到 expenseId 的列：keep 是 true 時留第一列，其餘（或全部）拿掉
    fileprivate static func keepOne<T>(_ list: [T], expenseId: UUID, keep: Bool, link: (T) -> UUID?) -> [T] {
        var kept = false
        return list.filter { item in
            guard link(item) == expenseId else { return true }
            if keep && !kept {
                kept = true
                return true
            }
            return false
        }
    }
}

// MARK: - 樓層與物品（物品樹 CRUD 留在這裡）

extension RealEstateDetailView {
    fileprivate static let treeIndent: CGFloat = 16

    fileprivate func floorsSection(_ card: HouseCardData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("樓層與物品", trailing: card.floors.trailing) {
                premiumAddMenu("新增樓層或物品") { floorsAddItems(card) }
            }
            floorsCard(card)
        }
    }

    /// 右上綠色「＋」：新增物品（選哪一層）、新增家電家具、新增樓層（後兩個到編輯頁）
    @ViewBuilder
    fileprivate func floorsAddItems(_ card: HouseCardData) -> some View {
        let floors = card.floors.floors
        if floors.count == 1, let only = floors.first {
            Button { newFloorItem(floorId: only.id, parent: nil) } label: {
                Label("新增物品", systemImage: "shippingbox")
            }
        } else if floors.count > 1 {
            Menu {
                ForEach(floors) { f in
                    Button(f.label) { newFloorItem(floorId: f.id, parent: nil) }
                }
            } label: {
                Label("新增物品", systemImage: "shippingbox")
            }
        }
        Button { sheet = .edit(.floors) } label: {
            Label("新增家電家具", systemImage: "sofa")
        }
        Button { sheet = .edit(.floors) } label: {
            Label("新增樓層", systemImage: "square.stack.3d.up")
        }
    }

    @ViewBuilder
    fileprivate func floorsCard(_ card: HouseCardData) -> some View {
        let data = card.floors
        if data.isEmpty {
            floorsEmptyRow
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(data.floors) { floor in
                    floorBlock(floor)
                    if floor.id != data.floors.last?.id { Divider() }
                }
                if !data.otherAssets.isEmpty {
                    if !data.floors.isEmpty { Divider() }
                    assetGroup("其他位置", data.otherAssets)
                        .padding(.vertical, 10)
                }
                if let summary = data.assetSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                }
            }
            .padding(14)
            .modifier(FinanceCardChrome())
        }
    }

    fileprivate var floorsEmptyRow: some View {
        HStack(spacing: 12) {
            Text("到「編輯」新增樓層（例如 B1、1F、2F），這裡就會一層一層列出來")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                requirePremium { sheet = .edit(.floors) }
            } label: {
                Text("去加樓層")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TripBoardPalette(scheme).hint)
                    .fixedSize()
            }
            .buttonStyle(MoneyPressStyle())
        }
        .padding(14)
        .modifier(FinanceCardChrome())
    }

    /// 一層：一列＋點了在原地展開（展開、收起不用付費）
    fileprivate func floorBlock(_ floor: HouseFloorsData.Floor) -> some View {
        let open = expandedFloorId == floor.id
        return VStack(alignment: .leading, spacing: 6) {
            floorRow(floor, open: open)
            if open {
                floorDetail(floor)
            }
        }
    }

    fileprivate func floorRow(_ floor: HouseFloorsData.Floor, open: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedFloorId = open ? nil : floor.id
            }
        } label: {
            HStack(spacing: 12) {
                floorBadge(floor)
                floorMiddle(floor)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    if !floor.countText.isEmpty {
                        Text(floor.countText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(floor.accessibilityText)
        .accessibilityHint(open ? "點兩下收起" : "點兩下展開")
        .accessibilityAddTraits(.isButton)
    }

    /// 中間：房間小膠囊，下面一行灰字面積
    fileprivate func floorMiddle(_ floor: HouseFloorsData.Floor) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if floor.rooms.isEmpty {
                Text("沒填用途")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            } else {
                roomChips(floor.rooms)
            }
            if let area = floor.areaText {
                Text(area)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 左邊 40pt 方塊「3F」；地下室深灰，其他用房子的紫
    fileprivate func floorBadge(_ floor: HouseFloorsData.Floor) -> some View {
        let dark = scheme == .dark
        let purpleHex: UInt32 = dark ? 0xB79CFF : 0x6B4BE0
        let basementHex: UInt32 = dark ? 0x4A5263 : 0x4A5568
        let purple = Color(tb: purpleHex)
        let tintAlpha: Double = dark ? 0.22 : 0.12
        let fill: Color = floor.isBasement ? Color(tb: basementHex) : purple.opacity(tintAlpha)
        let ink: Color = floor.isBasement ? Color.white : purple
        return Text(floor.label)
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(ink)
            .padding(.horizontal, 2)
            .frame(width: 40, height: 40)
            .background(fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    fileprivate func roomChips(_ rooms: [String]) -> some View {
        ChipFlowLayout(spacing: 5) {
            ForEach(rooms, id: \.self) { room in
                Text(room)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
    }

    /// 展開後：「家電家具」（附屬資產）＋「收納」（物品樹）
    fileprivate func floorDetail(_ floor: HouseFloorsData.Floor) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !floor.assets.isEmpty {
                assetGroup("家電家具", floor.assets)
            }
            storageGroup(floorId: floor.id)
        }
        .padding(.leading, 52)
        .padding(.bottom, 10)
    }

    fileprivate func groupTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
    }

    fileprivate func assetGroup(_ title: String, _ assets: [HouseFloorsData.Asset]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            groupTitle(title)
            ForEach(assets) { asset in
                assetRow(asset)
            }
        }
    }

    /// 點家電：打開它連結的記帳支出（付費）；沒連到記帳的不能點
    fileprivate func assetRow(_ asset: HouseFloorsData.Asset) -> some View {
        Button {
            guard let id = asset.expenseId else { return }
            requirePremium { openExpenseRecord(id) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sofa.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                MarqueeText(asset.text)
                    .font(.subheadline)
                Spacer(minLength: 4)
                if asset.expenseId != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(minHeight: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(asset.expenseId == nil)
    }

    /// 這一層的物品樹（讀 store 最新的一份，新增、改名之後馬上看得到）
    fileprivate func floorItems(_ floorId: UUID) -> [FloorItem] {
        estate.floors.first(where: { $0.id == floorId })?.items ?? []
    }

    fileprivate func storageGroup(floorId: UUID) -> some View {
        let rows = flattenedFloorItems(floorItems(floorId))
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                groupTitle("收納")
                Spacer(minLength: 8)
                Button {
                    requirePremium { newFloorItem(floorId: floorId, parent: nil) }
                } label: {
                    Label("新增物品", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 4)
            if rows.isEmpty {
                Text("還沒有物品，點「新增物品」開始建立")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                // 先把樹攤平成一維再用單一 ForEach：遞迴回傳 AnyView 在新增／刪除時會讓 AttributeGraph 崩潰
                ForEach(rows) { row in
                    floorItemRow(floorId: floorId, row: row)
                }
            }
        }
    }

    /// 一件物品：縮排＋細線（不再用 │├└ 字元）。點一下改名、長按新增子項目／改名／刪除（都要付費）
    fileprivate func floorItemRow(floorId: UUID, row: FlatFloorItem) -> some View {
        let item = row.item
        let name = item.name.isEmpty ? "未命名" : item.name
        let indent = CGFloat(row.depth) * Self.treeIndent
        let count = descendantCount(of: item)
        return HStack(spacing: 6) {
            Image(systemName: item.children.isEmpty ? "cube" : "cube.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
            MarqueeText(name)
                .font(.subheadline)
            if count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
        }
        .padding(.leading, indent)
        .frame(minHeight: 34)
        .background(alignment: .leading) {
            FloorTreeGuide(depth: row.depth, isLast: row.isLast, ancestorIsLast: row.ancestorIsLast,
                           indent: Self.treeIndent)
                .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                .frame(width: indent)
        }
        .contentShape(Rectangle())
        .onTapGesture { requirePremium { renameFloorItemSheet(floorId: floorId, item: item) } }
        .contextMenu { floorItemMenu(floorId: floorId, item: item) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("點兩下重新命名")
        .accessibilityAction(named: "新增子項目") { requirePremium { newFloorItem(floorId: floorId, parent: item.id) } }
        .accessibilityAction(named: "重新命名") { requirePremium { renameFloorItemSheet(floorId: floorId, item: item) } }
        .accessibilityAction(named: "刪除") { requirePremium { confirmDeleteFloorItem(floorId: floorId, item: item) } }
    }

    @ViewBuilder
    fileprivate func floorItemMenu(floorId: UUID, item: FloorItem) -> some View {
        Button {
            requirePremium { newFloorItem(floorId: floorId, parent: item.id) }
        } label: {
            Label("新增子項目", systemImage: "plus")
        }
        Button {
            requirePremium { renameFloorItemSheet(floorId: floorId, item: item) }
        } label: {
            Label("重新命名", systemImage: "pencil")
        }
        Button(role: .destructive) {
            requirePremium { confirmDeleteFloorItem(floorId: floorId, item: item) }
        } label: {
            Label("刪除", systemImage: "trash")
        }
    }

    fileprivate func newFloorItem(floorId: UUID, parent: UUID?) {
        sheet = .floorItem(FloorItemEditTarget(floorId: floorId, parentItemId: parent, itemId: nil, currentName: ""))
    }

    fileprivate func renameFloorItemSheet(floorId: UUID, item: FloorItem) {
        sheet = .floorItem(FloorItemEditTarget(floorId: floorId, parentItemId: nil, itemId: item.id, currentName: item.name))
    }

    /// 刪一個會連整棵子樹一起刪：先確認，寫出底下有幾件
    fileprivate func confirmDeleteFloorItem(floorId: UUID, item: FloorItem) {
        let name = item.name.isEmpty ? "未命名" : item.name
        let count = descendantCount(of: item)
        let message = count > 0 ? "底下 \(count) 件也會一起刪掉。" : "刪除後不能復原。"
        let itemId = item.id
        pendingConfirm = HouseConfirm(title: "刪除「\(name)」？", message: message, button: "刪除",
                                      action: { deleteFloorItem(floorId: floorId, itemId: itemId) })
    }

    fileprivate func descendantCount(of item: FloorItem) -> Int {
        item.children.reduce(0) { $0 + 1 + descendantCount(of: $1) }
    }

    /// 樹深度優先攤平成一維（每列帶畫細線要的 depth／isLast／祖先資訊）
    fileprivate func flattenedFloorItems(_ items: [FloorItem], depth: Int = 0,
                                         ancestorIsLast: [Bool] = []) -> [FlatFloorItem] {
        var result: [FlatFloorItem] = []
        for (idx, item) in items.enumerated() {
            let isLast = idx == items.count - 1
            result.append(FlatFloorItem(id: item.id, item: item, depth: depth,
                                        isLast: isLast, ancestorIsLast: ancestorIsLast))
            if !item.children.isEmpty {
                result.append(contentsOf: flattenedFloorItems(item.children, depth: depth + 1,
                                                              ancestorIsLast: ancestorIsLast + [isLast]))
            }
        }
        return result
    }

    /// 新增物品：parentItemId 是 nil 加在這一層的最上層，否則加在那一件底下
    fileprivate func addFloorItem(floorId: UUID, parentItemId: UUID?, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              var re = store.realEstates.first(where: { $0.id == estateId }),
              let fIdx = re.floors.firstIndex(where: { $0.id == floorId }) else { return }
        let newItem = FloorItem(name: trimmed)
        if let parentId = parentItemId {
            re.floors[fIdx].items = insertChild(into: re.floors[fIdx].items, parentId: parentId, child: newItem)
        } else {
            re.floors[fIdx].items.append(newItem)
        }
        commitFloorEstate(re)
    }

    fileprivate func renameFloorItem(floorId: UUID, itemId: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              var re = store.realEstates.first(where: { $0.id == estateId }),
              let fIdx = re.floors.firstIndex(where: { $0.id == floorId }) else { return }
        re.floors[fIdx].items = renameInTree(re.floors[fIdx].items, targetId: itemId, newName: trimmed)
        commitFloorEstate(re)
    }

    fileprivate func deleteFloorItem(floorId: UUID, itemId: UUID) {
        guard var re = store.realEstates.first(where: { $0.id == estateId }),
              let fIdx = re.floors.firstIndex(where: { $0.id == floorId }) else { return }
        re.floors[fIdx].items = removeFromTree(re.floors[fIdx].items, targetId: itemId)
        commitFloorEstate(re)
    }

    /// 樓層物品寫回 store 刻意延後一個 runloop：新增／改名是在 FloorItemEditor「儲存」裡觸發、
    /// 緊接著 sheet 關閉，在這個 view-update 交易裡同步改 observed state 會閃退。
    fileprivate func commitFloorEstate(_ re: RealEstate) {
        DispatchQueue.main.async {
            store.update(re)
        }
    }

    fileprivate func insertChild(into items: [FloorItem], parentId: UUID, child: FloorItem) -> [FloorItem] {
        items.map { node in
            var node = node
            if node.id == parentId {
                node.children.append(child)
            } else {
                node.children = insertChild(into: node.children, parentId: parentId, child: child)
            }
            return node
        }
    }

    fileprivate func renameInTree(_ items: [FloorItem], targetId: UUID, newName: String) -> [FloorItem] {
        items.map { node in
            var node = node
            if node.id == targetId {
                node.name = newName
            } else {
                node.children = renameInTree(node.children, targetId: targetId, newName: newName)
            }
            return node
        }
    }

    fileprivate func removeFromTree(_ items: [FloorItem], targetId: UUID) -> [FloorItem] {
        var result: [FloorItem] = []
        for node in items where node.id != targetId {
            var copy = node
            copy.children = removeFromTree(node.children, targetId: targetId)
            result.append(copy)
        }
        return result
    }

    // MARK: 區塊標題＋「＋」選單

    fileprivate func sectionHeader<Add: View>(_ title: String, trailing: String?,
                                              @ViewBuilder add: () -> Add) -> some View {
        let addView = add()
        return HStack(alignment: .center, spacing: 10) {
            MoneySectionHeader(title: title, trailing: trailing)
                .accessibilityAddTraits(.isHeader)
            addView
        }
    }

    /// 區塊標題右邊的綠色小「＋」（跟其他各區同一個樣子）
    fileprivate var addIcon: some View {
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
    fileprivate func premiumAddMenu<Items: View>(_ label: String, @ViewBuilder items: () -> Items) -> some View {
        let content = items()
        if subscription.isPremium {
            Menu {
                content
            } label: {
                addIcon
            }
            .accessibilityLabel(label)
        } else {
            Button {
                showPremiumAlert = true
            } label: {
                addIcon
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityLabel(label)
        }
    }
}

// MARK: - 照片與文件

extension RealEstateDetailView {
    fileprivate func photosSection(_ card: HouseCardData) -> some View {
        let items = photoItems(card)
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("照片與文件", trailing: card.media.trailing) {
                if !items.isEmpty {
                    premiumAddMenu("新增照片或文件") { photoAddItems }
                }
            }
            if items.isEmpty {
                photosEmptyRow
            } else {
                photoStrip(items)
            }
        }
    }

    /// 集錦要列的：裝潢照片、有圖片的關聯支出（跟張數同一批）、文件、有收據的水電、有照片的電梯保養
    fileprivate func photoItems(_ card: HouseCardData) -> [HousePhotoItem] {
        let re = card.estate
        let ids = Set(card.media.photoExpenseIds)
        var items: [HousePhotoItem] = re.renovationPhotos.map { HousePhotoItem.renovation($0) }
        items += expenseStore.expenses.filter { ids.contains($0.id) }.map { HousePhotoItem.expense($0) }
        items += re.documents.map { HousePhotoItem.document($0) }
        items += re.utilityPayments.filter { !$0.photoFileNames.isEmpty }.map { HousePhotoItem.utility($0) }
        items += re.elevatorMaintenances.filter { !$0.photoFileNames.isEmpty }.map { HousePhotoItem.elevator($0) }
        return items.sorted { $0.date > $1.date }
    }

    @ViewBuilder
    fileprivate var photoAddItems: some View {
        Button {
            sheet = .newRenovation(UUID())
        } label: {
            Label("新增照片及描述", systemImage: "photo")
        }
        Button {
            showDocumentPicker = true
        } label: {
            Label("上傳文件（PDF、PPT、Excel…）", systemImage: "doc.badge.plus")
        }
    }

    /// 沒有任何照片和文件：整區縮成一行「＋ 加照片或文件」（付費才打開選單）
    fileprivate var photosEmptyRow: some View {
        let label = HStack(spacing: 8) {
            Text("＋ 加照片或文件")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TripBoardPalette(scheme).hint)
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

    fileprivate func photoStrip(_ items: [HousePhotoItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(items) { item in
                    Button {
                        handleHousePhotoTap(item)
                    } label: {
                        housePhotoCard(item)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { photoMenu(item) }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .modifier(FinanceCardChrome())
    }

    /// 長按：編輯資訊、打開那筆記帳、刪除文件（都要付費；刪文件先確認）
    @ViewBuilder
    fileprivate func photoMenu(_ item: HousePhotoItem) -> some View {
        switch item {
        case .renovation(let p):
            Button {
                requirePremium { sheet = .editRenovation(p) }
            } label: {
                Label("編輯資訊", systemImage: "pencil")
            }
        case .expense(let e):
            Button {
                requirePremium { openExpenseRecord(e.id) }
            } label: {
                Label("打開那筆記帳", systemImage: "list.bullet.rectangle")
            }
        case .document(let d):
            Button(role: .destructive) {
                requirePremium { confirmDeleteDocument(d) }
            } label: {
                Label("刪除文件", systemImage: "trash")
            }
        case .utility(let u):
            Button {
                requirePremium { sheet = .editUtility(u) }
            } label: {
                Label("編輯繳費紀錄", systemImage: "pencil")
            }
        case .elevator(let m):
            Button {
                requirePremium { sheet = .editElevator(m) }
            } label: {
                Label("編輯保養紀錄", systemImage: "pencil")
            }
        }
    }

    /// 點照片一律用 CutePhotoViewer 看全部（看不用付費）；沒照片的裝潢紀錄點了是去編輯（付費）
    fileprivate func handleHousePhotoTap(_ item: HousePhotoItem) {
        switch item {
        case .renovation(let p):
            guard !p.photoFileNames.isEmpty else {
                requirePremium { sheet = .editRenovation(p) }
                return
            }
            let urls = p.photoFileNames.map { RenovationPhoto.photoURL(for: $0) }
            let title = p.title.isEmpty ? "裝潢紀錄" : p.title
            sheet = .photos(CutePhotoDraft(urls: urls, title: title, note: p.note, date: p.date, kind: .renovation))
        case .expense(let e):
            let urls = item.fileNames.map { Expense.photoURL(for: $0) }
            guard !urls.isEmpty else { return }
            let trimmedNote = e.note.trimmingCharacters(in: .whitespaces)
            let fallback: String = e.title.isEmpty ? "支出照片" : e.title
            let title: String = trimmedNote.isEmpty ? fallback : trimmedNote
            let note: String = (trimmedNote.isEmpty || trimmedNote == title) ? "" : trimmedNote
            sheet = .photos(CutePhotoDraft(urls: urls, title: title, note: note, date: e.date, kind: .expense))
        case .document(let d):
            sheet = .document(IdentifiableURL(url: d.fileURL))
        case .utility(let u):
            let urls = u.photoFileNames.map { UtilityPayment.photosDirectory.appendingPathComponent($0) }
            let amountText: String = u.amount > 0 ? MoneyFormat.short(u.amount) : ""
            let noteParts = [amountText, u.note.trimmingCharacters(in: .whitespaces)].filter { !$0.isEmpty }
            sheet = .photos(CutePhotoDraft(urls: urls, title: "\(u.type.rawValue) 繳費",
                                           note: noteParts.joined(separator: "・"), date: u.date, kind: .utility(u.type)))
        case .elevator(let m):
            let urls = m.photoFileNames.map { ElevatorMaintenance.photoURL(for: $0) }
            sheet = .photos(CutePhotoDraft(urls: urls, title: "電梯保養", note: "", date: m.date, kind: .elevator))
        }
    }

    fileprivate func housePhotoCard(_ item: HousePhotoItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            housePhotoThumb(item)
            HStack(spacing: 4) {
                Image(systemName: item.badgeIcon)
                    .font(.system(size: 9))
                    .foregroundStyle(item.badgeColor)
                MarqueeText(item.displayTitle)
                    .font(.caption.weight(.medium))
            }
            .frame(width: 140, alignment: .leading)
            Text(HouseCardFormat.ymd(item.date))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(8)
    }

    @ViewBuilder
    fileprivate func housePhotoThumb(_ item: HousePhotoItem) -> some View {
        if case .document(let d) = item {
            documentThumbnail(for: d)
        } else if item.fileNames.count >= 2 {
            stackedHousePhotos(fileNames: item.fileNames, urlFor: item.urlForFileName)
        } else {
            singlePhoto(url: item.primaryURL)
        }
    }

    /// 文件縮圖：大張彩色圖示＋副檔名，跟照片卡同尺寸
    fileprivate func documentThumbnail(for doc: RealEstateDocument) -> some View {
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
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(doc.iconColor.opacity(0.18))
                        .clipShape(Capsule())
                }
            }
            .frame(width: 130, height: 100)
        }
        .frame(width: 130, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
        .frame(width: 140, height: 110)
    }

    /// 多張照片疊起來：往後三張遞減旋轉位移，右上角寫總張數
    fileprivate func stackedHousePhotos(fileNames: [String], urlFor: (String) -> URL) -> some View {
        let visible = Array(fileNames.prefix(3))
        let urls = visible.map { urlFor($0) }
        return ZStack {
            if urls.count >= 3 {
                stackedPhotoLayer(url: urls[2])
                    .rotationEffect(.degrees(7))
                    .offset(x: 7, y: 4)
                    .opacity(0.85)
            }
            if urls.count >= 2 {
                stackedPhotoLayer(url: urls[1])
                    .rotationEffect(.degrees(-5))
                    .offset(x: -4, y: 2)
                    .opacity(0.92)
            }
            if let first = urls.first {
                stackedPhotoLayer(url: first)
            }
            photoCountBadge(fileNames.count)
        }
        .frame(width: 140, height: 110)
    }

    fileprivate func photoCountBadge(_ count: Int) -> some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 10))
                    Text("\(count)")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.65))
                .clipShape(Capsule())
                .padding(6)
            }
            Spacer()
        }
        .frame(width: 130, height: 100)
    }

    fileprivate func stackedPhotoLayer(url: URL) -> some View {
        ThumbnailImageView(url: url)
            .frame(width: 130, height: 100)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
    }

    /// 單張照片卡：跟疊起來的卡同一個大小（140×110，內容 130×100）
    fileprivate func singlePhoto(url: URL?) -> some View {
        ThumbnailImageView(url: url, placeholderIcon: "photo")
            .frame(width: 130, height: 100)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
            .frame(width: 140, height: 110)
    }

    // MARK: 文件匯入／刪除

    /// 讀檔、複製搬到背景執行緒（以前在主執行緒同步讀整個檔，大檔會卡住）；寫回 store 回主執行緒，
    /// 而且寫回「選檔那時候」那一間，不會寫到換過去的那間。讀不到的檔案跳提示（以前默默略過）
    fileprivate func importDocuments(_ urls: [URL]) {
        let requestedId = estateId
        Task {
            let results: [RealEstateDocument?] = await Task.detached(priority: .userInitiated) {
                urls.map { RealEstateDocument.importDocument(from: $0) }
            }.value
            let docs = results.compactMap { $0 }
            let failed = results.count - docs.count
            if var re = store.realEstates.first(where: { $0.id == requestedId }) {
                if !docs.isEmpty {
                    re.documents.append(contentsOf: docs)
                    store.update(re)
                }
            } else {
                // 匯入途中房子被刪掉了：剛複製進來的檔案沒人用，刪掉
                docs.forEach { RealEstateDocument.deleteDocument($0.fileName) }
            }
            guard failed > 0 else { return }
            let message = failed == results.count
                ? "選的檔案讀不到，沒有匯入。可以先存到「檔案」App 再選一次。"
                : "有 \(failed) 個檔案讀不到，沒有匯入；其他的已經加進「照片與文件」。"
            presentNotice("有檔案沒匯入", message)
        }
    }

    fileprivate func confirmDeleteDocument(_ doc: RealEstateDocument) {
        let name = doc.displayName.isEmpty ? doc.fileName : doc.displayName
        pendingConfirm = HouseConfirm(title: "刪除「\(name)」？", message: "iCloud 上的也會刪掉，不能復原。",
                                      button: "刪除", action: { deleteDocument(doc) })
    }

    fileprivate func deleteDocument(_ doc: RealEstateDocument) {
        guard var re = store.realEstates.first(where: { $0.id == estateId }) else { return }
        RealEstateDocument.deleteDocument(doc.fileName)
        re.documents.removeAll { $0.id == doc.id }
        store.update(re)
    }
}

// MARK: - 分享圖片

extension RealEstateDetailView {
    fileprivate static let shareStampFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyyMMdd_HHmm"
        return f
    }()

    /// 帳本沒有任何一列：直接出一張（看板＋房貸）；有紀錄：先問每頁幾筆
    fileprivate func shareTapped() {
        guard let card else { return }
        if card.ledger.events.isEmpty {
            exportCardImage(card)
        } else {
            askExportPageSize = true
        }
    }

    /// 算圖一律淺色；看板、各區讀的環境物件都補上（缺了 ImageRenderer 會當掉）。
    /// 不輸出房屋資料、水電、照片：門牌、權狀、表號、所有權人、衛星圖都在那幾區
    fileprivate func exportDecorate(_ view: AnyView) -> AnyView {
        AnyView(
            view
                .environmentObject(store)
                .environmentObject(expenseStore)
                .environmentObject(lifeStore)
                .environmentObject(subscription)
                .environment(\.colorScheme, .light)
        )
    }

    fileprivate func exportPageHeader(_ card: HouseCardData) -> AnyView {
        AnyView(
            HStack {
                Text("🏠 房地產｜\(card.name)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
        )
    }

    fileprivate func exportSingleContent(_ card: HouseCardData) -> some View {
        VStack(spacing: 16) {
            HouseCardBoard(data: card, onTapProgress: nil)
            if card.mortgage != nil {
                HouseMortgageSection(data: card, actions: HouseCardActions(), forExport: true)
            }
        }
        .padding(.horizontal, 16)
        .frame(width: 430)
        .padding(.vertical, 20)
        .background(Color(.systemGroupedBackground))
    }

    /// 單張 JPG（寬 430、scale 照 ImageExportLimits、品質 0.95），檔名「房屋卡片_<房名>_yyyyMMdd_HHmm.jpg」
    @MainActor
    fileprivate func exportCardImage(_ card: HouseCardData) {
        let content = exportDecorate(AnyView(exportSingleContent(card)))
        let renderer = ImageRenderer(content: content)
        var measured = CGSize.zero
        renderer.render { size, _ in measured = size }
        renderer.scale = ImageExportLimits.safeScale(for: measured)
        guard let ui = renderer.uiImage, !ImageExportLimits.isBlank(ui),
              let data = ui.jpegData(compressionQuality: 0.95) else { return }
        let safeName = PagedImageExporter.sanitizeFileName(card.name)
        let name = "房屋卡片_\(safeName)_\(Self.shareStampFmt.string(from: Date())).jpg"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            sheet = .share(StockCardSharePayload(items: [url]))
        } catch { }
    }

    /// 分頁：看板、房貸、每個月住這裡、帳本總表當第一頁的開頭區塊，接著帳本逐筆（含房貸、固定支出年列）
    @MainActor
    fileprivate func exportPaged(perPage: Int) {
        guard let card else { return }
        let actions = HouseCardActions()
        var items: [PagedExportItem] = []
        // 區塊標題左右留 20，往外推 4 跟逐筆的卡對齊
        items.append(.sectionHeader(AnyView(HouseCardBoard(data: card, onTapProgress: nil).padding(.horizontal, -4))))
        if card.mortgage != nil {
            let mortgage = HouseMortgageSection(data: card, actions: actions, forExport: true)
            items.append(.sectionHeader(AnyView(mortgage.padding(.horizontal, -4))))
        }
        if card.living != nil {
            let living = HouseLivingSection(data: card, actions: actions)
            items.append(.sectionHeader(AnyView(living.padding(.horizontal, -4))))
        }
        items.append(.sectionHeader(AnyView(exportLedgerSummary(card, actions: actions).padding(.horizontal, -4))))
        if !card.ledger.events.isEmpty {
            let trailing: String? = card.ledger.recordCount > 0 ? "\(card.ledger.recordCount) 筆" : nil
            items.append(.sectionHeader(AnyView(MoneySectionHeader(title: "紀錄", trailing: trailing))))
            items += card.ledger.events.map { e -> PagedExportItem in
                .row(AnyView(HouseLedgerRowView(event: e)))
            }
        }
        let urls = PagedImageExporter.exportSections(
            baseName: "房屋卡片_\(card.name)",
            itemsPerPage: perPage,
            header: exportPageHeader(card),
            items: items,
            decorate: { exportDecorate($0) }
        )
        guard !urls.isEmpty else { return }
        sheet = .share(StockCardSharePayload(items: urls))
    }

    fileprivate func exportLedgerSummary(_ card: HouseCardData, actions: HouseCardActions) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MoneySectionHeader(title: "我的帳本", trailing: card.ledger.headerTrailing)
            HouseLedgerSummaryCard(data: card, actions: actions)
        }
    }
}

// MARK: - 彈出頁與確認框的型別

/// 卡片上所有彈出頁（一個 .sheet(item:)）。每次「新增」都帶一個新的 UUID：
/// 跟「打開」綁在一起，不會帶到上一次的內容（v25.532 教訓：不要先設值再 set Bool）
private enum HouseSheet: Identifiable {
    case edit(HouseEditFocus)
    case share(StockCardSharePayload)
    case newExpense(NewExpenseRequest)
    case editExpense(Expense)
    case floorItem(FloorItemEditTarget)
    case newUtility(UUID)
    case editUtility(UtilityPayment)
    case newElevator(UUID)
    case editElevator(ElevatorMaintenance)
    case newRenovation(UUID)
    case editRenovation(RenovationPhoto)
    case photos(CutePhotoDraft)
    case document(IdentifiableURL)

    var id: String {
        switch self {
        case .edit(let focus): return "edit-\(focus)"
        case .share(let payload): return "share-" + payload.id.uuidString
        case .newExpense(let request): return "newExpense-" + request.id.uuidString
        case .editExpense(let ex): return "expense-" + ex.id.uuidString
        case .floorItem(let target): return "floorItem-" + target.id.uuidString
        case .newUtility(let token): return "newUtility-" + token.uuidString
        case .editUtility(let payment): return "utility-" + payment.id.uuidString
        case .newElevator(let token): return "newElevator-" + token.uuidString
        case .editElevator(let record): return "elevator-" + record.id.uuidString
        case .newRenovation(let token): return "newRenovation-" + token.uuidString
        case .editRenovation(let photo): return "renovation-" + photo.id.uuidString
        case .photos(let draft): return "photos-" + draft.id.uuidString
        case .document(let wrapper): return "document-" + wrapper.id.uuidString
        }
    }
}

/// 新增一筆記帳：種類和預設值跟「打開」綁在一起
private struct NewExpenseRequest {
    let id = UUID()
    let expenseType: ExpenseType
    let preset: AddExpensePreset
}

/// 一個確認框（button 是 nil 時只是告訴你一件事，只有「好」）
private struct HouseConfirm: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var button: String? = nil
    var destructive = true
    var action: () -> Void = {}
}

/// 一個選單（沒連到記帳的舊資料：補建或刪除）
private struct HouseChoice: Identifiable {
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

// MARK: - 物品樹的一列、縮排細線

/// 攤平後的一件物品：先算好畫細線要的 depth／isLast／祖先資訊，畫面用單一 ForEach、不遞迴
private struct FlatFloorItem: Identifiable {
    let id: UUID
    let item: FloorItem
    let depth: Int
    let isLast: Bool
    let ancestorIsLast: [Bool]
}

/// 物品樹的縮排細線（取代 │├└ 字元）：一個 Shape 畫完整列，不用 ForEach 一段一段畫
/// （動態範圍的 ForEach 在新增／刪除時會閃退）
private struct FloorTreeGuide: Shape {
    let depth: Int
    let isLast: Bool
    let ancestorIsLast: [Bool]
    let indent: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard depth > 0 else { return p }
        // 祖先那一層後面還有兄弟：那一欄整列畫直線接下去
        for level in 1..<depth where level < ancestorIsLast.count && !ancestorIsLast[level] {
            let x = indent * (CGFloat(level - 1) + 0.5)
            p.move(to: CGPoint(x: x, y: rect.minY))
            p.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        // 自己這一層：直線到中間（後面還有兄弟就畫到底）＋往右一小段橫線
        let x = indent * (CGFloat(depth - 1) + 0.5)
        p.move(to: CGPoint(x: x, y: rect.minY))
        p.addLine(to: CGPoint(x: x, y: isLast ? rect.midY : rect.maxY))
        p.move(to: CGPoint(x: x, y: rect.midY))
        p.addLine(to: CGPoint(x: indent * CGFloat(depth) - 3, y: rect.midY))
        return p
    }
}

// MARK: - 照片與文件的一張卡

private enum HousePhotoItem: Identifiable {
    case renovation(RenovationPhoto)
    case expense(Expense)
    case document(RealEstateDocument)
    case utility(UtilityPayment)
    case elevator(ElevatorMaintenance)

    var id: String {
        switch self {
        case .renovation(let p): return "r-\(p.id.uuidString)"
        case .expense(let e): return "e-\(e.id.uuidString)"
        case .document(let d): return "d-\(d.id.uuidString)"
        case .utility(let u): return "u-\(u.id.uuidString)"
        case .elevator(let m): return "ev-\(m.id.uuidString)"
        }
    }

    var date: Date {
        switch self {
        case .renovation(let p): return p.date
        case .expense(let e): return e.date
        case .document(let d): return d.date
        case .utility(let u): return u.date
        case .elevator(let m): return m.date
        }
    }

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
            return d.displayName.isEmpty ? "文件" : d.displayName
        case .utility(let u):
            return "\(u.type.rawValue) 收據"
        case .elevator:
            return "電梯保養"
        }
    }

    /// 照片檔名；記帳存的 PDF 帳單不算照片（跟張數同一套）
    var fileNames: [String] {
        switch self {
        case .renovation(let p): return p.photoFileNames
        case .expense(let e): return e.photoFileNames.filter { HouseCardFormat.isImage($0) }
        case .document: return []
        case .utility(let u): return u.photoFileNames
        case .elevator(let m): return m.photoFileNames
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
        case .utility: return UtilityPayment.photosDirectory.appendingPathComponent(name)
        case .elevator: return ElevatorMaintenance.photosDirectory.appendingPathComponent(name)
        }
    }

    /// 卡片標題前的小圖示：分辨來源
    var badgeIcon: String {
        switch self {
        case .renovation: return "paintbrush.fill"
        case .expense: return "tag.fill"
        case .document(let d): return d.icon
        case .utility(let u): return u.type.icon
        case .elevator: return "arrow.up.arrow.down.square.fill"
        }
    }

    var badgeColor: Color {
        switch self {
        case .renovation: return .blue
        case .expense: return .orange
        case .document(let d): return d.iconColor
        case .utility(let u):
            switch u.type {
            case .water: return .blue
            case .electricity: return Color(tb: 0xC27400)
            case .gas: return .orange
            }
        case .elevator: return .teal
        }
    }
}
