import SwiftUI
import Combine

// MARK: - [v25.588] 部屬匯出可選：選項頁（部屬卡片、部屬總覽）
//
// 規格：scratchpad/orgmove/export/design.md §2（選項頁）、§4（分享前提醒）、§6.4-7／8／16／17／18、§8.3（部屬總覽）；
// 工作清單：scratchpad/orgmove/build/export/brief.md 的 G1。樣稿 ②③④⑨。
//
// 主控只寫了兩個 init 的簽名（G3、G4 照這個呼叫，不准改）；body 與其餘全部 G1 寫。
// 組字、件數、提醒、能不能按一律呼叫 SubExportComposer／TeamExportComposer（SubordinateExport.swift，凍結）；
// 出圖呼叫 SubExportImage.render（卡片）或建構時給的 makeImage（部屬總覽）。
//
// [v25.588 部屬匯出] 寫法守則（沒有編譯環境）：
// • 每個 body 拆成小 View／computed var，字串在 ViewBuilder 外面組好；修飾器分層寫在不同的 computed var。
// • 畫面上每一個數字都吃同一份 resolve() 的結果（卡片：currentModel()；總覽：currentModel()），子 View 不自己篩。
// • 顏色全部用系統色（深色模式照系統）；勾選框用 Color.accentColor。出圖的淺色由 SubExportImage.decorate 管。
// • 資料變了：卡片 0.3 秒後重抽快照（onReceive objectWillChange＋可取消的 Task；不用 Combine 的 debounce，
//   因為 body 每次重算都會換一個新的 debounce publisher、重新訂閱，等著的那一拍會被丟掉）；總覽直接吃 lifeStore。
// • 分享前一定跳提醒（每次都問）；提醒和內容是按〔匯出…〕那一刻重抽的同一份。
// • 這頁沒有任何「關掉之後寫 store」；記住上次只寫這台的 @AppStorage（JSON 字串，不跟 iCloud）。

// MARK: - 部屬卡片的選項頁

/// 部屬卡片的選項頁。SubordinateDetailView：
///     .sheet(item: $exportRequest) { req in
///         SubordinateExportSheet(subordinateId: subordinateId, initialFormat: req.format,
///                                mentioned: mentionedItemsCache).appStores()
///     }
struct SubordinateExportSheet: View {
    let subordinateId: UUID
    /// 從哪個按鈕進來就先選哪一種（不記）
    let initialFormat: SubExportFormat
    /// 卡片算好的被標註清單（很貴，不在這裡重掃）
    let mentioned: [SubordinateItemRef]

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    /// 記住上次：存這台的 JSON 字串（SubExportOptions.load／json；選項型別不准 RawRepresentable，design §6.4-12）
    @AppStorage("sub_export_options_v1") private var optionsJSON: String = ""
    /// 每頁幾項：跟部屬總覽、別的分頁匯出共用同一個數字
    @AppStorage("export_items_per_page") private var perPage: Int = 15
    @State private var options = SubExportOptions()
    /// 〔圖片｜文字〕不記（選單決定）
    @State private var format: SubExportFormat
    @State private var snapshot: SubExportSnapshot? = nil
    /// 會議範圍沒選的（每次打開照名稱重算、不記）
    @State private var excludedMeetings: Set<UUID> = []
    /// 已經照名稱判斷過的會議（同步進來的新會議也照「一對一預設不選」判斷一次）
    @State private var seenMeetingIds: Set<UUID> = []
    /// 〔全部一張〕不記
    @State private var allInOnePage = false
    @State private var loaded = false
    /// 分享前提醒（含按下去那一刻抓的 model、text）
    @State private var ask: Pending? = nil
    /// 「正在產生圖片…（約 2 張）」
    @State private var busy: String? = nil
    @State private var share: SubExportSharePayload? = nil
    @State private var failure: XSheetNote? = nil
    /// 部分張數出不來：分享面板關掉之後再說
    @State private var noteAfterShare: XSheetNote? = nil
    /// 分享過一次 → 左上〔取消〕變〔完成〕
    @State private var sharedOnce = false
    /// 這位同仁不在名單上了（iCloud 從別台刪掉）
    @State private var gone = false
    /// [v25.588 部屬匯出] 按了〔好〕、正在關頁：不再重抽、不再跳一次「不在名單上」（關頁動畫中同步又來一波時）
    @State private var closing = false
    @State private var editingPerPage = false
    /// 資料變了 0.3 秒後重抽：Task 放在 class 裡，排程本身不觸發重畫
    @State private var debouncer = XSheetDebouncer()

    private struct Pending: Identifiable {
        let id = UUID()
        let model: SubExportModel
        let text: String
        let title: String
        let message: String
        let format: SubExportFormat
    }

    /// 明確寫出 init：G1 會加 private @State，合成的 memberwise init 會跟著變 private，卡片就叫不到
    init(subordinateId: UUID, initialFormat: SubExportFormat, mentioned: [SubordinateItemRef]) {
        self.subordinateId = subordinateId
        self.initialFormat = initialFormat
        self.mentioned = mentioned
        _format = State(initialValue: initialFormat)
    }

    // MARK: 外層（修飾器分三層，每層各自型別檢查）

    var body: some View {
        shareLayer
    }

    private var shareLayer: some View {
        askLayer
            .sheet(item: $share, onDismiss: { shareDismissed() }) { p in
                ShareSheet(items: p.items).appStores()
            }
    }

    private var askLayer: some View {
        lifecycleLayer
            .alert(ask?.title ?? "", isPresented: askShown, presenting: ask) { p in
                Button("取消", role: .cancel) { }
                Button("分享") { DispatchQueue.main.async { run(p) } }
            } message: { p in
                Text(p.message)
            }
    }

    private var lifecycleLayer: some View {
        stack
            .presentationDetents([.fraction(0.7), .large])
            .presentationDragIndicator(.visible)
            .presentationSizing(.form)
            .interactiveDismissDisabled(busy != nil)
            .onAppear { firstLoad() }
            .onDisappear { debouncer.cancel() }
            .onChange(of: options) { _, new in optionsJSON = new.json() }
            .onReceive(lifeStore.objectWillChange) { _ in scheduleRefresh() }
    }

    private var stack: some View {
        NavigationStack {
            pageBody
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarItems }
                .alert(failure?.title ?? "", isPresented: failureShown, presenting: failure) { _ in
                    Button("好", role: .cancel) { }
                } message: { note in
                    Text(note.message)
                }
        }
        .alert("這位同仁已經不在名單上了", isPresented: $gone) {
            Button("好") { closeLater() }
        } message: {
            Text("可能是從別台裝置刪掉了；這份不會匯出。")
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(cancelTitle) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(busy != nil)
        }
        ToolbarItem(placement: .principal) {
            XSheetTitle(title: "匯出部屬卡片", subtitle: subtitle)
        }
    }

    @ViewBuilder
    private var pageBody: some View {
        if let m = currentModel() {
            page(m)
        } else {
            XSheetLoading()
        }
    }

    // MARK: 頁面

    private func page(_ m: SubExportModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                upper(m)
                lower(m)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(m) }
        .disabled(busy != nil)
        .overlay { busyLayer }
        .onChange(of: tooTall(m)) { _, tall in
            if tall { allInOnePage = false }   // 太長了，一張出不來：已勾著就自動取消
        }
    }

    /// 一打開（7 成高）看得到的：〔圖片｜文字〕、看板卡、要匯出哪些、四大格、期間
    private func upper(_ m: SubExportModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            XSheetFormatPicker(format: $format)
            boardCard
            XSheetQuickRow(onAll: { options.selectAllBlocks() },
                           onBoardOnly: { options.boardOnly() },
                           onDefault: { options = SubExportOptions() })
            XSheetTileGrid(tiles: tileSpecs(m))
            XSheetPeriodSection(options: $options,
                                rangeText: SubExportComposer.periodCore(m),
                                fallbackStart: m.rangeStart,
                                showsWhileMine: showsWhileMine(m))
        }
    }

    /// [v25.593 轉組織 v2]〔在我這裡的時候〕：已轉出的人才多這一顆（export design §1.3、§5.4）；
    /// 記住的是這一顆、這次開的人還在（入職～今天，斷言 27）時也畫出來，免得五顆都沒亮。要退回這一件：刪這一支與上面那個參數
    private func showsWhileMine(_ m: SubExportModel) -> Bool {
        m.snapshot.isArchived || options.period == .whileMine
    }

    /// 往上拉之後：細項、另外三區、潛力性、執掌、排班、細節與敏感、圖片分頁、不會匯出
    private func lower(_ m: SubExportModel) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            XSheetDetailsCard(options: $options, excluded: $excludedMeetings, model: m, name: personName(m))
            XSheetActiveCard(options: $options, model: m, name: personName(m))
            XSheetPotentialCard(options: $options, model: m)
            XSheetDutyCard(options: $options, model: m)
            XSheetSensitiveCard(options: $options)
            if format == .image {
                pagingCard(m)
                    .modifier(XSheetPerPageEditor(isPresented: $editingPerPage))
            }
            XSheetNeverCard()
        }
    }

    private var boardCard: some View {
        XSheetCard {
            XSheetToggleRow(title: "上方看板（摘要卡）",
                            caption: "名字、職稱、部門、廠區、入職年資、件數小格",
                            titleFont: .headline,
                            isOn: $options.includeBoard)
            XSheetBoardExtras(options: $options)
        }
    }

    @ViewBuilder
    private var busyLayer: some View {
        if let b = busy {
            XSheetBusyOverlay(text: b)
        }
    }

    // MARK: 四大格

    private func tileSpecs(_ m: SubExportModel) -> [XSheetTileSpec] {
        [
            XSheetTileSpec(id: "tasks", title: "任務", icon: "checklist", color: .cyan,
                           count: m.rowCount(.tasks), caption: taskCaption, isOn: blockOn(.tasks)),
            XSheetTileSpec(id: "meetings", title: "會議", icon: "person.3.fill", color: .indigo,
                           count: m.rowCount(.meetings), caption: meetingCaption(m), isOn: blockOn(.meetings)),
            XSheetTileSpec(id: "completed", title: "完成項目", icon: "checkmark.circle.fill", color: .green,
                           count: m.rowCount(.completed), caption: completedCaption, isOn: blockOn(.completed)),
            XSheetTileSpec(id: "leaves", title: "請假", icon: "calendar.badge.minus", color: .teal,
                           count: m.rowCount(.leaves), caption: leaveCaption(m), isOn: blockOn(.leaves))
        ]
    }

    private var taskCaption: String {
        options.taskAlarm ? "未完成・含機台警報" : "未完成"
    }

    /// 「1on1 沒選・未完成議程 3」（有排除才寫前半）
    private func meetingCaption(_ m: SubExportModel) -> String {
        let open = "未完成議程 \(m.openAgendaCount)"
        let off = m.snapshot.meetings.filter { excludedMeetings.contains($0.id) }
        guard !off.isEmpty else { return open }
        let allOneOnOne = off.allSatisfy { SubExportComposer.isOneOnOneName($0.topic) }
        let head = allOneOnOne ? "1on1 沒選" : "\(off.count) 個沒選"
        return head + "・" + open
    }

    private var completedCaption: String {
        SubExportCompletedKind.allCases
            .filter { options.completedKinds.contains($0) }
            .map { $0.label }
            .joined(separator: "・")
    }

    /// 「36 小時・不含事由」
    private func leaveCaption(_ m: SubExportModel) -> String {
        let reason = options.leaveReason ? "含事由" : "不含事由"
        let h = m.leaveHours
        return h > 0 ? SubExportComposer.hoursText(h) + "・" + reason : reason
    }

    private func blockOn(_ b: SubExportBlock) -> Binding<Bool> {
        Binding(get: { options.blocks.contains(b) },
                set: { on in
                    if on { _ = options.blocks.insert(b) } else { _ = options.blocks.remove(b) }
                })
    }

    // MARK: 圖片分頁、底下那條

    private func pagingCard(_ m: SubExportModel) -> XSheetPagingCard {
        let rows = m.pageRowCount
        let pages = SubExportComposer.pageEstimate(rows: rows, perPage: perPageValue)
        let tall = tooTall(m)
        let h = Int(m.estimatedHeight).formatted()
        let blur = Int(SubExportComposer.blurHeight).formatted()
        let caption = tall ? "太長了，一張出不來" : "約 \(h)pt；超過 \(blur) 會先說字會變小變糊"
        return XSheetPagingCard(perPage: perPageValue,
                                pageCaption: "上次的數字；共 \(rows) 項 → \(pages) 張",
                                allInOne: $allInOnePage,
                                allInOneCaption: caption,
                                allInOneDisabled: tall,
                                onEdit: { editingPerPage = true })
    }

    private func bottomBar(_ m: SubExportModel) -> XSheetBottomBar {
        let can = SubExportComposer.canExport(m)
        let count = SubExportComposer.countLine(m)
        let foot = footLines(m)
        let first = can.ok ? (count.isEmpty ? "只有看板" : count) : can.reason
        return XSheetBottomBar(line1: first,
                               line1Muted: !can.ok,
                               line2: can.ok ? foot.text : "",
                               line2Warn: foot.warn,
                               line3: can.ok ? foot.extra : "",
                               buttonTitle: format == .image ? "匯出圖片" : "匯出文字",
                               enabled: can.ok && busy == nil,
                               action: { startExport() })
    }

    /// 底下那條第二行（藍字或橘字）與第三行（橘字）
    private func footLines(_ m: SubExportModel) -> (text: String, warn: Bool, extra: String) {
        switch format {
        case .image:
            if allInOnePage && !tooTall(m) {
                let h = Int(m.estimatedHeight).formatted()
                if m.estimatedHeight > SubExportComposer.blurHeight {
                    return ("一張約 \(h)pt，字會變小變糊，建議分頁", true, "")
                }
                return ("一張約 \(h)pt", false, "")
            }
            let p = XSheetFoot.pages(rows: m.pageRowCount, perPage: perPageValue, hint: "縮短期間")
            return (p.text, p.warn, "")
        case .text:
            let t = XSheetFoot.text(SubExportComposer.text(m), hint: "縮短期間")
            return (t.text, false, t.extra)
        }
    }

    // MARK: 小工具

    private func currentModel() -> SubExportModel? {
        guard let s = snapshot else { return nil }
        return SubExportComposer.resolve(s, options, excludedMeetings: excludedMeetings, now: Date())
    }

    private func tooTall(_ m: SubExportModel) -> Bool {
        m.estimatedHeight > SubExportComposer.maxSingleHeight
    }

    private var perPageValue: Int { min(200, max(1, perPage)) }

    private var cancelTitle: String { sharedOnce ? "完成" : "取消" }

    /// 「王小明・工程師・製造一課」（空的不寫）
    private var subtitle: String {
        guard let s = snapshot else { return "" }
        return [s.name, s.gradeTitle, s.department]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "・")
    }

    private func personName(_ m: SubExportModel) -> String {
        m.snapshot.name.isEmpty ? "這位同仁" : m.snapshot.name
    }

    private var askShown: Binding<Bool> {
        Binding(get: { ask != nil }, set: { if !$0 { ask = nil } })
    }

    private var failureShown: Binding<Bool> {
        Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    }

    // MARK: 載入、重抽

    private func firstLoad() {
        guard !loaded else { return }
        loaded = true
        options = SubExportOptions.load(optionsJSON)
        refresh()
    }

    /// 抽一次快照（主執行緒）。新出現的會議照名稱判斷一次「一對一預設不選」。
    /// 回傳這一次的快照與會議範圍，按〔匯出…〕時直接用這一份（不等 @State 下一拍）。
    @discardableResult
    private func refresh() -> (snap: SubExportSnapshot, excluded: Set<UUID>) {
        let snap = SubExportSnapshot.make(store: lifeStore, subordinateId: subordinateId, mentioned: mentioned)
        if snap.isGone {
            if !closing { gone = true }
            return (snap, excludedMeetings)
        }
        var excluded = excludedMeetings
        let fresh = snap.meetings.filter { !seenMeetingIds.contains($0.id) }
        if !fresh.isEmpty {
            excluded.formUnion(SubExportComposer.defaultExcludedMeetings(fresh))
            seenMeetingIds.formUnion(fresh.map { $0.id })
            excludedMeetings = excluded
        }
        snapshot = snap
        return (snap, excluded)
    }

    /// 選項頁開著時資料變了（iCloud 同步）：0.3 秒內沒有再變才重抽（design §6.4-18）
    private func scheduleRefresh() {
        guard loaded, !closing else { return }
        debouncer.schedule { _ = refresh() }
    }

    // MARK: 匯出

    /// 按〔匯出…〕：再抽一次快照 → 組字 → 提醒（提醒和內容同一份）
    private func startExport() {
        guard busy == nil, !gone, !closing else { return }
        let fresh = refresh()
        guard !fresh.snap.isGone else { return }
        let m = SubExportComposer.resolve(fresh.snap, options, excludedMeetings: fresh.excluded, now: Date())
        guard SubExportComposer.canExport(m).ok else { return }
        let text = SubExportComposer.text(m)
        let w = SubExportComposer.warning(m, text: text)
        ask = Pending(model: m, text: text, title: w.title, message: w.message, format: format)
    }

    private func run(_ p: Pending) {
        guard p.format == .image else {
            presentShare([p.text])
            return
        }
        let per: Int? = (allInOnePage && !tooTall(p.model)) ? nil : perPageValue
        let n = SubExportComposer.pageEstimate(rows: p.model.pageRowCount, perPage: per)
        Task { @MainActor in
            busy = "正在產生圖片…（約 \(n) 張）"
            // 讓「正在產生」那一層先畫出來（模組一次同步出完所有頁，中間插不進去，brief §1-7）
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
            let r = SubExportImage.render(p.model, perPage: per)
            busy = nil
            finish(r)
        }
    }

    private func finish(_ r: SubExportRenderResult) {
        let out = XSheetFoot.outcome(r, hint: "縮短期間")
        if let f = out.failure {
            failure = f
            return
        }
        noteAfterShare = out.later
        presentShare(out.items)
    }

    private func presentShare(_ items: [Any]) {
        sharedOnce = true
        share = SubExportSharePayload(items: items)
    }

    private func shareDismissed() {
        guard let n = noteAfterShare else { return }
        noteAfterShare = nil
        DispatchQueue.main.async { failure = n }
    }

    private func closeLater() {
        closing = true
        debouncer.cancel()
        DispatchQueue.main.async { dismiss() }
    }
}

// MARK: - 部屬總覽的選項頁

/// 部屬總覽的選項頁。SubordinateOverviewView：
///     .sheet(item: $teamExportRequest) { req in
///         TeamExportSheet(initialFormat: req.format, day: selectedDate, onlyPersonId: filterPersonId,
///                         makeImage: { model, perPage in teamExportImage(model, perPage: perPage) }).appStores()
///     }
/// makeImage 由部屬總覽用自己的列組圖（G4），這頁只負責選、提醒、叫它、開分享面板。
struct TeamExportSheet: View {
    let initialFormat: SubExportFormat
    /// 畫面上選的那一天（這頁可以改，不回寫畫面、不記）
    let day: Date
    /// 畫面上「只看：王小明」的那一位（nil＝沒有篩選）
    let onlyPersonId: UUID?
    /// 出圖：(這一份, 每頁幾項〔nil＝全部一張〕) → 結果
    let makeImage: @MainActor (TeamExportModel, Int?) -> SubExportRenderResult

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    /// 記住上次：存這台（跟卡片那包互不影響）
    @AppStorage("team_export_options_v1") private var optionsJSON: String = ""
    @AppStorage("export_items_per_page") private var perPage: Int = 15
    @State private var options = TeamExportOptions()
    @State private var format: SubExportFormat
    /// 這份匯出的日子（初值＝畫面上那一天；不回寫畫面、不記）
    @State private var pickedDay: Date
    /// 〔只看○○〕：預設照畫面（不記）
    @State private var onlyOn = true
    @State private var showDay = false
    @State private var allInOnePage = false
    @State private var loaded = false
    @State private var ask: Pending? = nil
    @State private var busy: String? = nil
    @State private var share: SubExportSharePayload? = nil
    @State private var failure: XSheetNote? = nil
    @State private var noteAfterShare: XSheetNote? = nil
    @State private var sharedOnce = false
    @State private var editingPerPage = false

    private struct Pending: Identifiable {
        let id = UUID()
        let model: TeamExportModel
        let text: String
        let title: String
        let message: String
        let format: SubExportFormat
    }

    init(initialFormat: SubExportFormat, day: Date, onlyPersonId: UUID?,
         makeImage: @escaping @MainActor (TeamExportModel, Int?) -> SubExportRenderResult) {
        self.initialFormat = initialFormat
        self.day = day
        self.onlyPersonId = onlyPersonId
        self.makeImage = makeImage
        _format = State(initialValue: initialFormat)
        _pickedDay = State(initialValue: day)
    }

    // MARK: 外層

    var body: some View {
        shareLayer
    }

    private var shareLayer: some View {
        askLayer
            .sheet(item: $share, onDismiss: { shareDismissed() }) { p in
                ShareSheet(items: p.items).appStores()
            }
    }

    private var askLayer: some View {
        lifecycleLayer
            .alert(ask?.title ?? "", isPresented: askShown, presenting: ask) { p in
                Button("取消", role: .cancel) { }
                Button("分享") { DispatchQueue.main.async { run(p) } }
            } message: { p in
                Text(p.message)
            }
    }

    private var lifecycleLayer: some View {
        stack
            .presentationDetents([.fraction(0.7), .large])
            .presentationDragIndicator(.visible)
            .presentationSizing(.form)
            .interactiveDismissDisabled(busy != nil)
            .onAppear { firstLoad() }
            .onChange(of: options) { _, new in optionsJSON = new.json() }
    }

    private var stack: some View {
        NavigationStack {
            pageBody
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarItems }
                .alert(failure?.title ?? "", isPresented: failureShown, presenting: failure) { _ in
                    Button("好", role: .cancel) { }
                } message: { note in
                    Text(note.message)
                }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(cancelTitle) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(busy != nil)
        }
        ToolbarItem(placement: .principal) {
            XSheetTitle(title: "匯出部屬總覽", subtitle: subtitle,
                        onTap: { showDay.toggle() }, expanded: showDay)
        }
    }

    @ViewBuilder
    private var pageBody: some View {
        if loaded {
            page(currentModel())
        } else {
            XSheetLoading()
        }
    }

    // MARK: 頁面

    private func page(_ m: TeamExportModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                upper(m)
                lower(m)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(m) }
        .disabled(busy != nil)
        .overlay { busyLayer }
    }

    private func upper(_ m: TeamExportModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if showDay {
                dayCard
            }
            if onlyPersonId != nil {
                onlyCard
            }
            XSheetFormatPicker(format: $format)
            boardCard
            XSheetQuickRow(onAll: { options.selectAllBlocks() },
                           onBoardOnly: { options.boardOnly() },
                           onDefault: { options = TeamExportOptions() })
            XSheetTileGrid(tiles: tileSpecs(m))
            reportCard(m)
        }
    }

    private func lower(_ m: TeamExportModel) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            XSheetTeamDetailsCard(options: $options)
            if format == .image {
                pagingCard(m)
                    .modifier(XSheetPerPageEditor(isPresented: $editingPerPage))
            }
        }
    }

    private var dayCard: some View {
        XSheetCard {
            DatePicker("日期", selection: $pickedDay, displayedComponents: .date)
                .datePickerStyle(.compact)
            Text("只改這份匯出的日子，部屬總覽畫面上的日期不會跟著變。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var onlyCard: some View {
        XSheetCard {
            XSheetToggleRow(title: "只看" + onlyName,
                            caption: "照部屬總覽畫面上的篩選；關掉＝全部部屬",
                            isOn: $onlyOn)
        }
    }

    private var boardCard: some View {
        XSheetCard {
            XSheetToggleRow(title: "上方看板（部屬總覽）",
                            caption: "共幾人、當日請假、當日會議、待辦任務",
                            titleFont: .headline,
                            isOn: $options.includeBoard)
        }
    }

    private func reportCard(_ m: TeamExportModel) -> some View {
        XSheetCard {
            XSheetCheckRow(title: "報告", icon: "doc.text.fill", color: .purple,
                           caption: "本週＋待交；交過的在完成項目",
                           count: m.rowCount(.reports), isOn: blockOn(.reports))
        }
    }

    @ViewBuilder
    private var busyLayer: some View {
        if let b = busy {
            XSheetBusyOverlay(text: b)
        }
    }

    // MARK: 四大格

    private func tileSpecs(_ m: TeamExportModel) -> [XSheetTileSpec] {
        [
            XSheetTileSpec(id: "tasks", title: "任務", icon: "checklist", color: .cyan,
                           count: m.rowCount(.tasks),
                           caption: "當日 \(m.dayTasks.count)・未完成 \(m.openTasks.count)",
                           isOn: blockOn(.tasks)),
            XSheetTileSpec(id: "meetings", title: "會議", icon: "person.3.fill", color: .indigo,
                           count: m.rowCount(.meetings),
                           caption: "當日 \(m.dayMeetings.count)・未完成條目 \(m.meetingItems.count)",
                           isOn: blockOn(.meetings)),
            XSheetTileSpec(id: "completed", title: "完成項目", icon: "checkmark.circle.fill", color: .green,
                           count: m.rowCount(.completed), caption: completedCaption,
                           isOn: blockOn(.completed)),
            XSheetTileSpec(id: "leaves", title: "請假", icon: "calendar.badge.minus", color: .teal,
                           count: m.rowCount(.leaves), caption: leaveCaption(m),
                           isOn: blockOn(.leaves))
        ]
    }

    /// 「這一週・任務議程報告」
    private var completedCaption: String {
        let kinds = SubExportCompletedKind.allCases
            .filter { options.completedKinds.contains($0) }
            .map { $0.label }
            .joined()
        return options.completedRange.label + "・" + kinds
    }

    /// 「8 小時・不含事由」
    private func leaveCaption(_ m: TeamExportModel) -> String {
        let reason = options.leaveReason ? "含事由" : "不含事由"
        let h = m.leaves.reduce(0.0) { $0 + ($1.rec.leaveHours ?? 0) }
        return h > 0 ? SubExportComposer.hoursText(h) + "・" + reason : reason
    }

    private func blockOn(_ b: TeamExportBlock) -> Binding<Bool> {
        Binding(get: { options.blocks.contains(b) },
                set: { on in
                    if on { _ = options.blocks.insert(b) } else { _ = options.blocks.remove(b) }
                })
    }

    // MARK: 圖片分頁、底下那條

    private func pagingCard(_ m: TeamExportModel) -> XSheetPagingCard {
        let rows = m.pageRowCount
        let pages = SubExportComposer.pageEstimate(rows: rows, perPage: perPageValue)
        return XSheetPagingCard(perPage: perPageValue,
                                pageCaption: "上次的數字；共 \(rows) 項 → \(pages) 張",
                                allInOne: $allInOnePage,
                                allInOneCaption: "\(rows) 項放進一張；項目多時字會變小變糊",
                                allInOneDisabled: false,
                                onEdit: { editingPerPage = true })
    }

    private func bottomBar(_ m: TeamExportModel) -> XSheetBottomBar {
        let can = TeamExportComposer.canExport(m)
        let count = TeamExportComposer.countLine(m)
        let foot = footLines(m)
        let first = can.ok ? (count.isEmpty ? "只有看板" : count) : can.reason
        return XSheetBottomBar(line1: first,
                               line1Muted: !can.ok,
                               line2: can.ok ? foot.text : "",
                               line2Warn: foot.warn,
                               line3: can.ok ? foot.extra : "",
                               buttonTitle: format == .image ? "匯出圖片" : "匯出文字",
                               enabled: can.ok && busy == nil,
                               action: { startExport() })
    }

    private func footLines(_ m: TeamExportModel) -> (text: String, warn: Bool, extra: String) {
        switch format {
        case .image:
            if allInOnePage {
                return ("全部一張（\(m.pageRowCount) 項）", false, "")
            }
            let p = XSheetFoot.pages(rows: m.pageRowCount, perPage: perPageValue, hint: "少勾幾區")
            return (p.text, p.warn, "")
        case .text:
            let t = XSheetFoot.text(TeamExportComposer.text(m), hint: "少勾幾區")
            return (t.text, false, t.extra)
        }
    }

    // MARK: 小工具

    /// [v25.593 轉組織 v2] 部屬總覽的匯出只匯在職的（同總覽畫面；judge §3.6）。knownNames、onlyName 照舊全部（提醒點名、查名字）。
    /// 要退回這一件：activeSubordinates 改回 subordinates（這裡與 subtitle 兩處）
    private func currentModel() -> TeamExportModel {
        TeamExportComposer.resolve(subordinates: lifeStore.activeSubordinates,
                                   onlyPersonId: onlyOn ? onlyPersonId : nil,
                                   options: options, day: pickedDay, now: Date(),
                                   cal: Calendar.current, knownNames: knownNames())
    }

    /// 提醒點名用：部屬＋組織人員＋名片的名字（trim、2 字以上、去重；同 SubExportSnapshot.make 那段）
    private func knownNames() -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        let all = lifeStore.subordinates.map { $0.name }
            + lifeStore.orgPeople.map { $0.name }
            + lifeStore.businessCards.map { $0.name }
        for raw in all {
            let n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard n.count >= 2, !seen.contains(n) else { continue }
            seen.insert(n)
            out.append(n)
        }
        return out
    }

    private var onlyName: String {
        guard let pid = onlyPersonId,
              let s = lifeStore.subordinates.first(where: { $0.id == pid }) else { return "這位同仁" }
        let n = s.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "這位同仁" : n
    }

    /// 「10/28（三）・3 位」（點了展開日期）
    private var subtitle: String {
        let g = SubExportComposer.gregorian
        let date = SubExportComposer.md(pickedDay, wd: true, now: Date(), cal: g)
        let people: Int
        if onlyOn, let pid = onlyPersonId {
            people = lifeStore.activeSubordinates.filter { $0.id == pid }.count
        } else {
            people = lifeStore.activeSubordinates.count
        }
        return date + "・\(people) 位"
    }

    private var perPageValue: Int { min(200, max(1, perPage)) }

    private var cancelTitle: String { sharedOnce ? "完成" : "取消" }

    private var askShown: Binding<Bool> {
        Binding(get: { ask != nil }, set: { if !$0 { ask = nil } })
    }

    private var failureShown: Binding<Bool> {
        Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    }

    private func firstLoad() {
        guard !loaded else { return }
        options = TeamExportOptions.load(optionsJSON)
        loaded = true
    }

    // MARK: 匯出

    private func startExport() {
        guard busy == nil else { return }
        let m = currentModel()
        guard TeamExportComposer.canExport(m).ok else { return }
        let text = TeamExportComposer.text(m)
        let w = TeamExportComposer.warning(m, text: text)
        ask = Pending(model: m, text: text, title: w.title, message: w.message, format: format)
    }

    private func run(_ p: Pending) {
        guard p.format == .image else {
            presentShare([p.text])
            return
        }
        let per: Int? = allInOnePage ? nil : perPageValue
        let n = SubExportComposer.pageEstimate(rows: p.model.pageRowCount, perPage: per)
        Task { @MainActor in
            busy = "正在產生圖片…（約 \(n) 張）"
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
            let r = makeImage(p.model, per)
            busy = nil
            finish(r)
        }
    }

    private func finish(_ r: SubExportRenderResult) {
        let out = XSheetFoot.outcome(r, hint: "少勾幾區")
        if let f = out.failure {
            failure = f
            return
        }
        noteAfterShare = out.later
        presentShare(out.items)
    }

    private func presentShare(_ items: [Any]) {
        sharedOnce = true
        share = SubExportSharePayload(items: items)
    }

    private func shareDismissed() {
        guard let n = noteAfterShare else { return }
        noteAfterShare = nil
        DispatchQueue.main.async { failure = n }
    }
}

// MARK: - 共用：小型別與組字（只在這支用）

/// 出圖失敗、部分張數出不來的說明
private struct XSheetNote: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// 底下那條第二、三行的字＋出圖結果的處理（卡片、總覽共用；hint＝「縮短期間」或「少勾幾區」）
private enum XSheetFoot {
    static func pages(rows: Int, perPage: Int, hint: String) -> (text: String, warn: Bool) {
        if rows == 0 { return ("1 張（只有看板）", false) }
        let n = SubExportComposer.pageEstimate(rows: rows, perPage: perPage)
        if n > SubExportComposer.manyPages {
            return ("約 \(n) 張，很多；可以\(hint)或把每頁項目數改大", true)
        }
        return ("約 \(n) 張（每頁 \(perPage) 項）", false)
    }

    static func text(_ s: String, hint: String) -> (text: String, extra: String) {
        let st = SubExportComposer.textStats(s)
        let base = "約 \(st.lines.formatted()) 行・\(st.chars.formatted()) 字"
        let long = st.chars > SubExportComposer.longTextChars
        return (base, long ? "很長，貼到 LINE 可能被截斷；可以\(hint)或改用圖片" : "")
    }

    /// urls 空的＝全部失敗（說原因，不再安靜結束，修 B3）；比預期少＝照樣分享出得來的，分享面板關掉後說
    static func outcome(_ r: SubExportRenderResult, hint: String) -> (items: [Any], failure: XSheetNote?, later: XSheetNote?) {
        if r.urls.isEmpty {
            let msg = "出圖失敗，可能是內容太長。把每頁項目數改小，或\(hint)再試一次。"
            return ([], XSheetNote(title: "圖片出不來", message: msg), nil)
        }
        var later: XSheetNote? = nil
        if r.urls.count < r.expected {
            let miss = r.expected - r.urls.count
            later = XSheetNote(title: "有 \(miss) 張出不來",
                               message: "有 \(miss) 張出不來，已略過；把每頁項目數改小可以補")
        }
        let items: [Any] = r.urls.map { $0 as Any }
        return (items, nil, later)
    }
}

/// 選項頁開著時資料變了：0.3 秒內沒有再變才做（design §6.4-18）。
/// 不用 Combine 的 .debounce 直接掛 onReceive：body 每次重算都會換一個新的 publisher、重新訂閱，等著的那一拍會被丟掉。
private final class XSheetDebouncer {
    private var task: Task<Void, Never>?

    func schedule(_ work: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            work()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

/// 細項「最後一個勾不能取消」：只剩一個時按了不動
private func xsheetToggled<T: Hashable>(_ set: Set<T>, _ k: T) -> Set<T> {
    var s = set
    if s.contains(k) {
        if s.count > 1 {
            s.remove(k)
        }
    } else {
        s.insert(k)
    }
    return s
}

/// 細項膠囊：是不是「最後一個勾」（灰掉、不能取消）
private func xsheetIsLast<T: Hashable>(_ set: Set<T>, _ k: T) -> Bool {
    set.count == 1 && set.contains(k)
}

// MARK: - 共用零件（全部系統色）

/// 白卡（深色模式照系統）
private struct XSheetCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// 小標＋右邊一句（藍字或橘字）
private struct XSheetSectionLabel: View {
    let title: String
    var trailing: String = ""
    var trailingColor: Color = .accentColor

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if !trailing.isEmpty {
                Text(trailing)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(trailingColor)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// 導覽列中間兩行：「匯出部屬卡片」＋小字（部屬總覽的小字可以點，展開日期）
private struct XSheetTitle: View {
    let title: String
    let subtitle: String
    var onTap: (() -> Void)? = nil
    var expanded = false

    private var hintText: String { expanded ? "收起日期" : "可以改日期" }

    var body: some View {
        if let onTap = onTap {
            Button(action: onTap) {
                lines(chevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint(hintText)
        } else {
            lines(chevron: false)
        }
    }

    private func lines(chevron: Bool) -> some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.headline)
            HStack(spacing: 3) {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if chevron {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// 〔圖片｜文字〕（不記）
private struct XSheetFormatPicker: View {
    @Binding var format: SubExportFormat

    var body: some View {
        Picker("匯出成", selection: $format) {
            ForEach(SubExportFormat.allCases) { f in
                Text(f.label).tag(f)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

/// 「要匯出哪些」＋〔全選〕〔只要看板〕〔預設〕
private struct XSheetQuickRow: View {
    let onAll: () -> Void
    let onBoardOnly: () -> Void
    let onDefault: () -> Void

    /// [v25.588 部屬匯出] 一列放得下就一列；字放大放不下時，小標在上、三顆膠囊在下（會換行）
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                label
                Spacer(minLength: 6)
                chips
            }
            VStack(alignment: .leading, spacing: 6) {
                label
                ChipFlowLayout(spacing: 6) {
                    chips
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var label: some View {
        Text("要匯出哪些")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var chips: some View {
        XSheetLinkChip(title: "全選", action: onAll)
        XSheetLinkChip(title: "只要看板", action: onBoardOnly)
        XSheetLinkChip(title: "預設", action: onDefault)
    }
}

/// 藍字小膠囊（快捷）
private struct XSheetLinkChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 方框勾
private struct XSheetCheckBox: View {
    let isOn: Bool

    var body: some View {
        Image(systemName: isOn ? "checkmark.square.fill" : "square")
            .font(.title3)
            .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            .accessibilityHidden(true)
    }
}

/// 圖示圓
private struct XSheetIconDisc: View {
    let icon: String
    let color: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 32, height: 32)
            .background(color.opacity(0.14), in: Circle())
            .accessibilityHidden(true)
    }
}

/// 細項膠囊：勾了藍底（敏感的橘底）；沒勾灰底「＋」（敏感的橘字）；最後一個勾灰掉、不能取消
private struct XSheetChip: View {
    let title: String
    let isOn: Bool
    var sensitive = false
    var locked = false
    var spoken: String? = nil
    let action: () -> Void

    private var fg: Color {
        if isOn { return .white }
        return sensitive ? .orange : .primary
    }

    private var bg: Color {
        if isOn { return sensitive ? .orange : .accentColor }
        return sensitive ? Color.orange.opacity(0.15) : Color(.tertiarySystemFill)
    }

    private var stateText: String { isOn ? "已勾選" : "沒勾" }

    private var hintText: String { locked ? "最後一個，不能取消；整區不要就取消上面的大格" : "" }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isOn ? "checkmark" : "plus")
                    .font(.caption2.weight(.bold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(fg)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(bg, in: Capsule())
            .opacity(locked ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .accessibilityLabel(spoken ?? title)
        .accessibilityValue(stateText)
        .accessibilityHint(hintText)
        .accessibilityAddTraits(isOn ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}

/// 開關列：粗字＋灰字（可以折行）
private struct XSheetToggleRow: View {
    let title: String
    let caption: String
    var titleFont: Font = .body.weight(.semibold)
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(titleFont)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 看板卡下面那排〔分數〕（橘＝敏感）〔生日〕；看板關了整排灰掉
private struct XSheetBoardExtras: View {
    @Binding var options: SubExportOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ChipFlowLayout(spacing: 8) {
                XSheetChip(title: "分數", isOn: options.boardScores, sensitive: true,
                           spoken: "看板分數，至今累計") {
                    options.boardScores.toggle()
                }
                XSheetChip(title: "生日", isOn: options.boardBirthday, spoken: "看板生日，只有月日") {
                    options.boardBirthday.toggle()
                }
            }
            Text("分數＝至今累計，預設不帶；生日只有月日")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(!options.includeBoard)
        .opacity(options.includeBoard ? 1 : 0.4)
    }
}

// MARK: 四大格

/// 一格的內容（數字不管勾沒勾都顯示）
private struct XSheetTileSpec: Identifiable {
    let id: String
    let title: String
    let icon: String
    let color: Color
    let count: Int
    let caption: String
    let isOn: Binding<Bool>

    /// VoiceOver：「任務，6 筆，已勾選，未完成・含機台警報」
    var spoken: String {
        let state = isOn.wrappedValue ? "已勾選" : "沒勾"
        return "\(title)，\(count) 筆，\(state)，\(caption)"
    }
}

private struct XSheetTileRow: Identifiable {
    let id: Int
    let items: [XSheetTileSpec]
}

/// 寬度 ≥ 600pt 一列四格、不然 2×2；字放大到 accessibility 級改一欄（design §6.4-16、17）
private struct XSheetTileGrid: View {
    let tiles: [XSheetTileSpec]
    @Environment(\.dynamicTypeSize) var typeSize
    @State var width: CGFloat = 0

    private var pairs: [XSheetTileRow] {
        stride(from: 0, to: tiles.count, by: 2).map { i in
            XSheetTileRow(id: i, items: Array(tiles[i..<min(i + 2, tiles.count)]))
        }
    }

    var body: some View {
        grid
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { w in
                width = w
            }
    }

    @ViewBuilder
    private var grid: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                ForEach(tiles) { XSheetTile(spec: $0) }
            }
        } else if width >= 600 {
            HStack(spacing: 10) {
                ForEach(tiles) { XSheetTile(spec: $0) }
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: 10) {
                ForEach(pairs) { row in
                    XSheetTilePair(row: row)
                }
            }
        }
    }
}

private struct XSheetTilePair: View {
    let row: XSheetTileRow

    var body: some View {
        HStack(spacing: 10) {
            ForEach(row.items) { XSheetTile(spec: $0) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 大格：左上方框勾、右上大數字（0 灰）、底下小字；勾了有 accentColor 框
private struct XSheetTile: View {
    let spec: XSheetTileSpec

    private var isOn: Bool { spec.isOn.wrappedValue }

    var body: some View {
        Button {
            spec.isOn.wrappedValue.toggle()
        } label: {
            face
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spec.spoken)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isOn ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    private var face: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Text(spec.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { border }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(isOn ? Color.accentColor : Color.clear, lineWidth: 2)
    }

    private var header: some View {
        HStack(spacing: 6) {
            XSheetCheckBox(isOn: isOn)
            Image(systemName: spec.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(spec.color)
            Text(spec.title)
                .font(.headline)
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text(String(spec.count))
                .font(.title3.weight(.bold))
                .foregroundStyle(spec.count == 0 ? Color.secondary : Color.primary)
        }
    }
}

// MARK: 期間

/// 期間：小標右邊藍字「2026/10/1～10/31」、五顆等寬膠囊、〔自訂…〕兩個日子、「不管期間都列」開關
/// [v25.593 轉組織 v2] 已轉出的人多第六顆〔在我這裡的時候〕（入職～轉出生效日）：字長，五顆那一排放不下，
/// 自己一排放在五顆下面（不藏進 ScrollView）。要退回這一件：刪 showsWhileMine 與 whileMineRow
private struct XSheetPeriodSection: View {
    @Binding var options: SubExportOptions
    let rangeText: String
    /// 切到〔自訂…〕而且還沒有起日時，先帶入原本那段期間的起日（沒有就一個月前）
    let fallbackStart: Date?
    /// [v25.593 轉組織 v2] 多畫〔在我這裡的時候〕那一顆
    var showsWhileMine: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            XSheetSectionLabel(title: "期間", trailing: rangeText)
            HStack(spacing: 6) {
                ForEach(SubExportPeriod.pickerCases) { p in
                    XSheetSegmentChip(title: p.label, isOn: options.period == p) { pick(p) }
                }
            }
            if showsWhileMine {
                whileMineRow
            }
            if options.period == .custom {
                XSheetCustomRange(options: $options)
            }
            Text("期間只切做完的、發生過的")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            Toggle(isOn: $options.openItemsIgnorePeriod) {
                Text("還沒做完、還沒到的不管期間都列")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
        }
    }

    /// [v25.593 轉組織 v2]〔在我這裡的時候〕（一整排寬）
    private var whileMineRow: some View {
        XSheetSegmentChip(title: SubExportPeriod.whileMine.label, isOn: options.period == .whileMine) {
            pick(.whileMine)
        }
    }

    private func pick(_ p: SubExportPeriod) {
        if p == .custom && options.customStart == nil {
            let monthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            options.customStart = fallbackStart ?? monthAgo
        }
        options.period = p
    }
}

/// 等寬膠囊（期間、部屬總覽完成項目範圍）
private struct XSheetSegmentChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(isOn ? Color.accentColor : Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}

/// 〔自訂…〕：起、迄（迄 in: 起...；迄可清空＝到今天）
private struct XSheetCustomRange: View {
    @Binding var options: SubExportOptions

    private var startBinding: Binding<Date> {
        Binding(get: { options.customStart ?? Date() }, set: { options.customStart = $0 })
    }

    private var endBinding: Binding<Date> {
        Binding(get: { options.customEnd ?? Date() }, set: { options.customEnd = $0 })
    }

    private var endFloor: Date { options.customStart ?? Date.distantPast }

    /// [v25.588 部屬匯出] 起最晚＝迄（迄空著＝到今天）：兩個日子互相限制（design §2.5）
    private var startCeil: Date { options.customEnd ?? Date() }

    var body: some View {
        XSheetCard {
            DatePicker("起", selection: startBinding, in: ...startCeil, displayedComponents: .date)
                .datePickerStyle(.compact)
            Divider()
            endRow
        }
    }

    @ViewBuilder
    private var endRow: some View {
        if options.customEnd == nil {
            HStack(spacing: 8) {
                Text("迄")
                Spacer(minLength: 8)
                Text("到今天")
                    .foregroundStyle(.secondary)
                Button("選日子") { options.customEnd = max(Date(), endFloor) }
                    .buttonStyle(.bordered)
            }
        } else {
            HStack(spacing: 8) {
                DatePicker("迄", selection: endBinding, in: endFloor..., displayedComponents: .date)
                    .datePickerStyle(.compact)
                Button("清掉") { options.customEnd = nil }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("清掉迄日，改成到今天")
            }
        }
    }
}

// MARK: 細項（部屬卡片）

/// 細項一列：左邊區名、右邊膠囊；那一區沒勾整列灰掉、不能按
private struct XSheetDetailRow<Content: View>: View {
    let label: String
    let enabled: Bool
    @ViewBuilder let content: () -> Content
    @Environment(\.dynamicTypeSize) var typeSize

    var body: some View {
        rows
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.4)
    }

    /// [v25.588 部屬匯出] 字放大到 accessibility 級：區名在上、膠囊在下（72pt 寬放不下「完成項目」）
    @ViewBuilder
    private var rows: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                title
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top, spacing: 10) {
                title
                    .frame(width: 72, alignment: .leading)
                    .padding(.top, 7)
                VStack(alignment: .leading, spacing: 8) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var title: some View {
        Text(label)
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
    }
}

/// 細項：任務〔機台警報〕〔缺失任務〕〔內容與處理〕；會議「會議範圍 2/3 ›」＋〔別人會議交給王小明的〕；
/// 完成項目〔任務〕〔議程〕〔報告〕（最後一個不能取消）；請假〔事由〕
private struct XSheetDetailsCard: View {
    @Binding var options: SubExportOptions
    @Binding var excluded: Set<UUID>
    let model: SubExportModel
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            XSheetSectionLabel(title: "細項", trailing: "只影響勾了的那一區")
            XSheetCard {
                taskRow
                Divider()
                meetingRow
                Divider()
                completedRow
                Divider()
                leaveRow
            }
        }
    }

    private var taskRow: some View {
        XSheetDetailRow(label: "任務", enabled: options.blocks.contains(.tasks)) {
            ChipFlowLayout(spacing: 6) {
                XSheetChip(title: "機台警報", isOn: options.taskAlarm) { options.taskAlarm.toggle() }
                XSheetChip(title: "缺失任務", isOn: options.taskDereliction, sensitive: true) {
                    options.taskDereliction.toggle()
                }
                XSheetChip(title: "內容與處理", isOn: options.taskDetails) { options.taskDetails.toggle() }
            }
        }
    }

    private var meetingRow: some View {
        XSheetDetailRow(label: "會議", enabled: options.blocks.contains(.meetings)) {
            NavigationLink {
                scopePage
            } label: {
                XSheetScopeLinkLabel(title: scopeTitle, note: scopeNote)
            }
            .buttonStyle(.plain)
            XSheetChip(title: "別人會議交給\(name)的", isOn: options.othersAgenda) {
                options.othersAgenda.toggle()
            }
        }
    }

    private var completedRow: some View {
        XSheetDetailRow(label: "完成項目", enabled: options.blocks.contains(.completed)) {
            ChipFlowLayout(spacing: 6) {
                ForEach(SubExportCompletedKind.allCases) { k in
                    XSheetChip(title: k.label, isOn: options.completedKinds.contains(k),
                               locked: xsheetIsLast(options.completedKinds, k)) {
                        options.completedKinds = xsheetToggled(options.completedKinds, k)
                    }
                }
            }
        }
    }

    private var leaveRow: some View {
        XSheetDetailRow(label: "請假", enabled: options.blocks.contains(.leaves)) {
            XSheetChip(title: "事由", isOn: options.leaveReason, sensitive: true, spoken: "請假事由") {
                options.leaveReason.toggle()
            }
            Text("事由常是看病、家人的事")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scopePage: XSheetMeetingScopePage {
        XSheetMeetingScopePage(snapshot: model.snapshot, start: model.rangeStart, end: model.rangeEnd,
                               excluded: $excluded)
    }

    /// 「會議範圍 2/3」
    private var scopeTitle: String {
        let all = model.snapshot.meetings
        let off = all.filter { excluded.contains($0.id) }.count
        return "會議範圍 \(all.count - off)/\(all.count)"
    }

    /// 「王小明 1on1 沒選」「王小明 1on1 等 2 個沒選」
    private var scopeNote: String {
        let all = model.snapshot.meetings
        if all.isEmpty { return "名下沒有會議" }
        let off = all.filter { excluded.contains($0.id) }
        guard let first = off.first else { return "全部都選" }
        let topic = first.topic.isEmpty ? "未命名會議" : first.topic
        return off.count == 1 ? topic + " 沒選" : topic + " 等 \(off.count) 個沒選"
    }
}

private struct XSheetScopeLinkLabel: View {
    let title: String
    let note: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// 會議範圍頁：一列一個會議（主題、時間、期間內有沒有開、未完成議程幾條、勾）；名稱像一對一的預設不選、不記
private struct XSheetMeetingScopePage: View {
    let snapshot: SubExportSnapshot
    let start: Date?
    let end: Date?
    @Binding var excluded: Set<UUID>

    var body: some View {
        list(SubExportComposer.meetingScopeRows(snapshot, start: start, end: end, now: Date()))
            .navigationTitle("會議範圍")
            .navigationBarTitleDisplayMode(.inline)
    }

    private func list(_ rows: [SubExportComposer.MeetingScopeRow]) -> some View {
        List {
            Section {
                ForEach(rows) { row in
                    XSheetScopeRow(row: row, isOn: isOn(row.id))
                }
            } footer: {
                Text(footerText(empty: rows.isEmpty))
            }
        }
    }

    private func footerText(empty: Bool) -> String {
        if empty { return "這位同仁名下沒有會議。" }
        return "名稱像一對一（1on1、一對一、面談、個談…）的會議預設不選。每次打開匯出都照名稱重新判斷，不會記住。"
    }

    private func isOn(_ id: UUID) -> Binding<Bool> {
        Binding(get: { !excluded.contains(id) },
                set: { on in
                    if on { _ = excluded.remove(id) } else { _ = excluded.insert(id) }
                })
    }
}

private struct XSheetScopeRow: View {
    let row: SubExportComposer.MeetingScopeRow
    @Binding var isOn: Bool

    /// 「期間內有開・未完成議程 2」
    private var detail: String {
        var parts: [String] = [row.hadSession ? "期間內有開" : "期間內沒開"]
        if row.openCount > 0 { parts.append("未完成議程 \(row.openCount)") }
        return parts.joined(separator: "・")
    }

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                texts
                Spacer(minLength: 8)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.topic)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.primary)
            Text(row.whenText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            if row.isOneOnOne {
                Text("一對一，預設不選")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: 另外三區、潛力性、執掌、排班（部屬卡片）

/// 方框勾一列：勾、圖示圓、名字（＋橘色小標）、灰字、右邊件數（0 灰）
private struct XSheetCheckRow: View {
    let title: String
    let icon: String
    let color: Color
    let caption: String
    let count: Int
    var unit: String = ""
    var tag: String? = nil
    @Binding var isOn: Bool

    private var countText: String { unit.isEmpty ? String(count) : "\(count) \(unit)" }

    private var spoken: String {
        let state = isOn ? "已勾選" : "沒勾"
        return "\(title)，\(countText)，\(state)，\(caption)"
    }

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            face
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isOn ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    private var face: some View {
        HStack(spacing: 12) {
            XSheetCheckBox(isOn: isOn)
            XSheetIconDisc(icon: icon, color: color)
            VStack(alignment: .leading, spacing: 2) {
                titleLine
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Text(countText)
                .font(.headline)
                .foregroundStyle(count == 0 ? Color.secondary : Color.primary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var titleLine: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.primary)
            if let tag = tag {
                Text(tag)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15), in: Capsule())
            }
        }
    }
}

/// 主動性的另外三區：報告、兼任職務、被標註的項目（橘色小標「別人的事」）
private struct XSheetActiveCard: View {
    @Binding var options: SubExportOptions
    let model: SubExportModel
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            XSheetSectionLabel(title: "主動性的另外三區")
            XSheetCard {
                XSheetCheckRow(title: "報告", icon: "doc.text.fill", color: .purple,
                               caption: "未交的；交過的在完成項目",
                               count: model.rowCount(.reports), isOn: blockOn(.reports))
                Divider()
                XSheetCheckRow(title: "兼任職務", icon: "person.badge.plus", color: .indigo,
                               caption: "在任的都列",
                               count: model.rowCount(.sideRoles), isOn: blockOn(.sideRoles))
                Divider()
                XSheetCheckRow(title: "被標註的項目", icon: "at", color: .pink,
                               caption: "別的同仁的任務、會議 @ 到\(name)",
                               count: model.rowCount(.mentioned), tag: "別人的事", isOn: blockOn(.mentioned))
            }
        }
    }

    private func blockOn(_ b: SubExportBlock) -> Binding<Bool> {
        Binding(get: { options.blocks.contains(b) },
                set: { on in
                    if on { _ = options.blocks.insert(b) } else { _ = options.blocks.remove(b) }
                })
    }
}

/// 潛力性（考評）：3×2 小格（歷程、優缺點、成就、改善、缺失紀錄、Miss Operation），右邊期間內筆數，0 筆灰
///（[v25.590 轉組織 v1a-1]「升職歷程」改「歷程」：格子的字吃 SubExportBlock.label；歷程＝升職＋轉組織）
private struct XSheetPotentialCard: View {
    @Binding var options: SubExportOptions
    let model: SubExportModel
    @Environment(\.dynamicTypeSize) var typeSize

    private static let blocks: [SubExportBlock] = [.history, .proCon, .achievements, .improvements, .faults, .missOps]

    private var columns: [GridItem] {
        let n = typeSize.isAccessibilitySize ? 1 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: n)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            XSheetSectionLabel(title: "潛力性（考評）", trailing: "勾了會寫進分享提醒", trailingColor: .orange)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Self.blocks) { b in
                    XSheetMiniCell(title: b.label, count: model.rowCount(b), isOn: blockOn(b))
                }
            }
        }
    }

    private func blockOn(_ b: SubExportBlock) -> Binding<Bool> {
        Binding(get: { options.blocks.contains(b) },
                set: { on in
                    if on { _ = options.blocks.insert(b) } else { _ = options.blocks.remove(b) }
                })
    }
}

private struct XSheetMiniCell: View {
    let title: String
    let count: Int
    @Binding var isOn: Bool

    private var spoken: String {
        let state = isOn ? "已勾選" : "沒勾"
        return "\(title)，\(count) 筆，\(state)"
    }

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                XSheetCheckBox(isOn: isOn)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                Text(String(count))
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(count == 0 ? Color.secondary : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isOn ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}

/// 執掌（執掌設備、PM／警報時間軸）＋卡片上沒有的（排班；[v25.591 轉組織 v1a-2] 有交接過來的班，caption 多說一句）
/// [v25.590 轉組織 v1a-1] 這位同仁有從交接單收到的機台，時間軸底下多一列〔只列接手之後〕（預設開；
/// 執掌設備的件數也跟著切）。要退回這一件：刪掉 `if hasReceivedEquipment { … }` 那一段、hasReceivedEquipment／
/// handoverCaption／handoverEnabled 三個 computed var 與底下的 XSheetHandoverRow，timelineCaption 改回原句。
private struct XSheetDutyCard: View {
    @Binding var options: SubExportOptions
    let model: SubExportModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                XSheetSectionLabel(title: "執掌")
                XSheetCard {
                    XSheetCheckRow(title: "執掌設備", icon: "wrench.and.screwdriver.fill", color: .teal,
                                   caption: "現在負責的機台＋期間內 PM、警報件數",
                                   count: model.rowCount(.equipment), unit: "台", isOn: blockOn(.equipment))
                    Divider()
                    XSheetCheckRow(title: "PM／警報時間軸", icon: "clock.arrow.circlepath", color: .orange,
                                   caption: timelineCaption,
                                   count: model.rowCount(.timeline), isOn: blockOn(.timeline))
                    if hasReceivedEquipment {
                        Divider()
                        XSheetHandoverRow(options: $options, caption: handoverCaption, enabled: handoverEnabled)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                XSheetSectionLabel(title: "卡片上沒有的")
                XSheetCard {
                    XSheetCheckRow(title: "排班", icon: "calendar", color: .indigo,
                                   caption: shiftCaption,
                                   count: model.shiftDays, unit: "天", isOn: blockOn(.shifts))
                }
            }
        }
    }

    /// [v25.591 轉組織 v1a-2] 期間內有交接過來的班：說一句「交接過來的那幾天另成一段」（匯出那一段後面寫「｜交接自 王小明」）。
    /// 要退回這一件：刪掉這個 computed var，排班那一列的 caption 改回原句
    private var shiftCaption: String {
        if model.shiftRuns.contains(where: { $0.handoverFrom != nil }) {
            return "班表頁沒有匯出；連續同一班併成一段，交接過來的那幾天另成一段"
        }
        return "班表頁沒有匯出；連續同一班併成一段"
    }

    /// 這位同仁現在負責的機台裡，有從交接單收到的
    private var hasReceivedEquipment: Bool {
        !model.snapshot.equipmentSince.isEmpty
    }

    /// 〔只列接手之後〕開著：前一位負責人的時期不列
    private var timelineCaption: String {
        if hasReceivedEquipment && options.timelineAfterHandover {
            return "機台的一生；從交接單收到的只列接手之後"
        }
        return "機台的一生，會含前一位負責人的時期"
    }

    /// 「蝕刻機 E-03 從 11/2 接手：PM、警報、件數都從那一刻起算」
    private var handoverCaption: String {
        SubExportComposer.handoverTimelineCaption(model.snapshot, now: model.now)
    }

    /// 執掌設備、時間軸都沒勾：這一列灰掉
    private var handoverEnabled: Bool {
        options.blocks.contains(.timeline) || options.blocks.contains(.equipment)
    }

    private func blockOn(_ b: SubExportBlock) -> Binding<Bool> {
        Binding(get: { options.blocks.contains(b) },
                set: { on in
                    if on { _ = options.blocks.insert(b) } else { _ = options.blocks.remove(b) }
                })
    }
}

/// [v25.590 轉組織 v1a-1] 時間軸底下的〔只列接手之後〕（只有這位同仁有從交接單收到的機台才出現）
private struct XSheetHandoverRow: View {
    @Binding var options: SubExportOptions
    let caption: String
    let enabled: Bool

    var body: some View {
        XSheetDetailRow(label: "時間軸", enabled: enabled) {
            XSheetChip(title: "只列接手之後", isOn: options.timelineAfterHandover,
                       spoken: "時間軸只列接手之後") {
                options.timelineAfterHandover.toggle()
            }
            captionText
        }
    }

    @ViewBuilder
    private var captionText: some View {
        if !caption.isEmpty {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 細節與敏感：〔逾期、準時與自訂分〕〔備註〕
/// [v25.590 轉組織 v1a-1]「交接時已逾期」跟〔逾期、準時與自訂分〕同一個開關（caption 多寫一句）
private struct XSheetSensitiveCard: View {
    @Binding var options: SubExportOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            XSheetSectionLabel(title: "細節與敏感")
            XSheetCard {
                XSheetToggleRow(title: "逾期、準時與自訂分",
                                caption: "任務逾期幾天、交接時已逾期、完成章（準時／超前／逾期）、自訂分；看板分數在看板那張卡",
                                isOn: $options.includeMarks)
                Divider()
                XSheetToggleRow(title: "備註",
                                caption: "任務、議程、會議、報告、紀錄的備註，可能 @ 到別的同仁",
                                isOn: $options.includeNotes)
            }
        }
    }
}

/// 不會匯出。[v25.590 轉組織 v1a-1] 多「交接單（在交接單頁分享）」：交接單只從交接單頁右上分享（文字、分享前提醒）；
/// 轉組織提示列、「從王小明接手」那一區是操作提示，也不進匯出（design §5.2，這裡不另外寫）。
private struct XSheetNeverCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("不會匯出")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("你寫的部屬備註、生日的年份、被別人排第幾名、這位同仁填的排名票（在「…」▸ 匯出圖片）、交接單（在交接單頁分享）")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: 細項（部屬總覽）

/// 任務〔當日任務〕〔未完成任務〕〔缺失任務〕；會議〔當日會議〕〔未完成條目〕〔一對一〕；
/// 完成項目〔當天〕〔這一週〕〔這個月〕〔全部〕＋〔任務〕〔議程〕〔報告〕；請假〔事由〕。各組最後一個勾不能取消
private struct XSheetTeamDetailsCard: View {
    @Binding var options: TeamExportOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            XSheetSectionLabel(title: "細項", trailing: "只影響勾了的那一區")
            XSheetCard {
                taskRow
                Divider()
                meetingRow
                Divider()
                completedRow
                Divider()
                leaveRow
            }
        }
    }

    private var taskRow: some View {
        XSheetDetailRow(label: "任務", enabled: options.blocks.contains(.tasks)) {
            ChipFlowLayout(spacing: 6) {
                ForEach(TeamTaskKind.allCases) { k in
                    XSheetChip(title: k.label, isOn: options.taskKinds.contains(k),
                               locked: xsheetIsLast(options.taskKinds, k)) {
                        options.taskKinds = xsheetToggled(options.taskKinds, k)
                    }
                }
                XSheetChip(title: "缺失任務", isOn: options.includeDereliction, sensitive: true) {
                    options.includeDereliction.toggle()
                }
            }
        }
    }

    private var meetingRow: some View {
        XSheetDetailRow(label: "會議", enabled: options.blocks.contains(.meetings)) {
            ChipFlowLayout(spacing: 6) {
                ForEach(TeamMeetingKind.allCases) { k in
                    XSheetChip(title: k.label, isOn: options.meetingKinds.contains(k),
                               locked: xsheetIsLast(options.meetingKinds, k)) {
                        options.meetingKinds = xsheetToggled(options.meetingKinds, k)
                    }
                }
                XSheetChip(title: "一對一", isOn: options.includeOneOnOne, sensitive: true,
                           spoken: "一對一會議") {
                    options.includeOneOnOne.toggle()
                }
            }
        }
    }

    private var completedRow: some View {
        XSheetDetailRow(label: "完成項目", enabled: options.blocks.contains(.completed)) {
            HStack(spacing: 6) {
                ForEach(TeamCompletedRange.allCases) { r in
                    XSheetSegmentChip(title: r.label, isOn: options.completedRange == r) {
                        options.completedRange = r
                    }
                }
            }
            ChipFlowLayout(spacing: 6) {
                ForEach(SubExportCompletedKind.allCases) { k in
                    XSheetChip(title: k.label, isOn: options.completedKinds.contains(k),
                               locked: xsheetIsLast(options.completedKinds, k)) {
                        options.completedKinds = xsheetToggled(options.completedKinds, k)
                    }
                }
            }
        }
    }

    private var leaveRow: some View {
        XSheetDetailRow(label: "請假", enabled: options.blocks.contains(.leaves)) {
            XSheetChip(title: "事由", isOn: options.leaveReason, sensitive: true, spoken: "請假事由") {
                options.leaveReason.toggle()
            }
            Text("事由常是看病、家人的事")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: 圖片分頁、底下那條、產圖中、每頁幾項

/// 圖片分頁（只在〔圖片〕）：「每頁 15 項 改 ›」＋「全部一張」方框
private struct XSheetPagingCard: View {
    let perPage: Int
    let pageCaption: String
    @Binding var allInOne: Bool
    let allInOneCaption: String
    let allInOneDisabled: Bool
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            XSheetSectionLabel(title: "圖片分頁")
            XSheetCard {
                perPageRow
                Divider()
                allInOneRow
            }
        }
    }

    private var perPageRow: some View {
        Button(action: onEdit) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("每頁 \(perPage) 項")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    Text(pageCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HStack(spacing: 2) {
                    Text("改")
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(allInOne)
        .opacity(allInOne ? 0.45 : 1)
    }

    private var allInOneRow: some View {
        Button {
            allInOne.toggle()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("全部一張")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    Text(allInOneCaption)
                        .font(.caption)
                        .foregroundStyle(allInOneDisabled ? Color.orange : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                XSheetCheckBox(isOn: allInOne)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(allInOneDisabled)
        .accessibilityAddTraits(allInOne ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}

/// 底下那條（.bar 背景）：左兩行（件數；藍字約幾張／幾行幾字，或橘字）＋右邊大按鈕
private struct XSheetBottomBar: View {
    let line1: String
    let line1Muted: Bool
    let line2: String
    let line2Warn: Bool
    let line3: String
    let buttonTitle: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            texts
            Button(action: action) {
                Text(buttonTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!enabled)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(line1)
                .font(.footnote)
                .foregroundStyle(line1Muted ? Color.secondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            if !line2.isEmpty {
                Text(line2)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(line2Warn ? Color.orange : Color.accentColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !line3.isEmpty {
                Text(line3)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 產圖中：整頁蓋一層半透明＋ProgressView＋「正在產生圖片…（約 2 張）」（不能中途停止，brief §1-7）
private struct XSheetBusyOverlay: View {
    let text: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .accessibilityElement(children: .combine)
    }
}

/// 快照還沒抽好（一打開那一拍）
private struct XSheetLoading: View {
    var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
    }
}

/// 「每頁 15 項 改 ›」：輸入 1～200，寫回共用的 export_items_per_page（照 ExportPageSizeDialog 的寫法）
private struct XSheetPerPageEditor: ViewModifier {
    @Binding var isPresented: Bool
    @AppStorage("export_items_per_page") var perPage: Int = 15
    @State var text = ""

    func body(content: Content) -> some View {
        content
            .alert("每頁幾項", isPresented: $isPresented) {
                TextField("每頁項目數", text: $text)
                    .keyboardType(.numberPad)
                Button("好") { apply() }
                Button("取消", role: .cancel) { }
            } message: {
                Text("輸入 1～200。部屬卡片、部屬總覽和別的分頁匯出共用這個數字。")
            }
            .onChange(of: isPresented) { _, showing in
                if showing { text = String(perPage) }   // 開框預填上次的數字
            }
    }

    private func apply() {
        let entered = Int(text.trimmingCharacters(in: .whitespaces)) ?? perPage
        perPage = min(200, max(1, entered))
    }
}
