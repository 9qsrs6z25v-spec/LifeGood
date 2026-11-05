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
//
// [v25.604 職能雷達 v4a] 使用者原話：「部屬的匯出功能選項太複雜，不如分block予以匯出及時間選別就好」。
// 兩個選項頁只剩〔圖片｜文字〕、期間（部屬總覽＝日子＋〔只看○○〕）、區塊清單；清單的字一律照
// SubExportComposer.pickRows／TeamExportComposer.pickRows（勾一列＝setPicked；〔全選〕〔全不選〕〔預設〕＝pickAll／pickNone／pickDefault），
// 模型一律 resolveExport（拿掉的細項在 forExport 接成固定值）。拿掉：四大格、細項卡、會議範圍頁、看板的〔分數〕〔生日〕膠囊、
// 圖片分頁卡（每頁幾項、全部一張）、「還沒做完的不管期間都列」開關、部屬總覽的任務種類／會議種類／完成項目三種／報告卡。
// 每頁幾項照 @AppStorage("export_items_per_page") 自動分頁（這頁不能改）。規格 radar/build/v4a/brief.md §3。

// MARK: - 部屬卡片的選項頁

/// 部屬卡片的選項頁。SubordinateDetailView：
///     .sheet(item: $exportRequest) { req in
///         SubordinateExportSheet(subordinateId: subordinateId, initialFormat: req.format,
///                                mentioned: mentionedItemsCache).appStores()
///     }
/// [v25.604 v4a] 只剩〔圖片｜文字〕、期間、區塊清單（SubExportComposer.pickRows）；模型一律 resolveExport。
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
    /// 每頁幾項：跟部屬總覽、別的分頁匯出共用同一個數字（[v25.604 v4a] 這頁不能改，照這個自動分頁）
    @AppStorage("export_items_per_page") private var perPage: Int = 15
    @State private var options = SubExportOptions()
    /// 〔圖片｜文字〕不記（選單決定）
    @State private var format: SubExportFormat
    @State private var snapshot: SubExportSnapshot? = nil
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
            content(m)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(m) }
        .disabled(busy != nil)
        .overlay { busyLayer }
    }

    /// [v25.604 v4a] 一頁三段：〔圖片｜文字〕、期間、區塊清單（字一律照 pickRows）；最後「不會匯出」
    private func content(_ m: SubExportModel) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            XSheetFormatPicker(format: $format)
            XSheetPeriodSection(options: $options,
                                rangeText: SubExportComposer.periodCore(m),
                                fallbackStart: m.rangeStart,
                                showsWhileMine: showsWhileMine(m))
            XSheetPickList(sections: SubExportComposer.pickRows(options, m),
                           onAll: { options.pickAll() },
                           onNone: { options.pickNone() },
                           onDefault: { options.pickDefault() },
                           onToggle: { p in toggle(p) })
            XSheetNeverCard()
        }
    }

    /// [v25.593 轉組織 v2]〔在我這裡的時候〕：已轉出的人才多這一顆（export design §1.3、§5.4）；
    /// 記住的是這一顆、這次開的人還在（入職～今天，斷言 27）時也畫出來，免得五顆都沒亮。要退回這一件：刪這一支與上面那個參數
    private func showsWhileMine(_ m: SubExportModel) -> Bool {
        m.snapshot.isArchived || options.period == .whileMine
    }

    /// [v25.604 v4a] 勾／取消一列（依賴沒滿足照樣可以勾，不自動幫忙勾別的）
    private func toggle(_ p: SubExportPick) {
        options.setPicked(p, !options.isPicked(p))
    }

    @ViewBuilder
    private var busyLayer: some View {
        if let b = busy {
            XSheetBusyOverlay(text: b)
        }
    }

    // MARK: 底下那條

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

    /// 底下那條第二行（藍字或橘字）與第三行（橘字）。[v25.604 v4a] 圖片一律照每頁幾項自動分頁（沒有〔全部一張〕）
    private func footLines(_ m: SubExportModel) -> (text: String, warn: Bool, extra: String) {
        switch format {
        case .image:
            let p = XSheetFoot.pages(rows: m.pageRowCount, perPage: perPageValue, hint: "縮短期間")
            return (p.text, p.warn, "")
        case .text:
            let t = XSheetFoot.text(SubExportComposer.text(m), hint: "縮短期間")
            return (t.text, false, t.extra)
        }
    }

    // MARK: 小工具

    /// [v25.604 v4a] 一律 resolveExport（固定值、依賴、一對一會議照〔一對一會議〕那一列）
    private func currentModel() -> SubExportModel? {
        guard let s = snapshot else { return nil }
        return SubExportComposer.resolveExport(s, options, now: Date())
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

    /// 抽一次快照（主執行緒）。回傳這一次的快照，按〔匯出…〕時直接用這一份（不等 @State 下一拍）。
    /// [v25.604 v4a] 會議範圍不再在這頁記（resolveExport 照〔一對一會議〕那一列算）
    @discardableResult
    private func refresh() -> SubExportSnapshot {
        let snap = SubExportSnapshot.make(store: lifeStore, subordinateId: subordinateId, mentioned: mentioned)
        if snap.isGone {
            if !closing { gone = true }
            return snap
        }
        snapshot = snap
        return snap
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
        let snap = refresh()
        guard !snap.isGone else { return }
        let m = SubExportComposer.resolveExport(snap, options, now: Date())
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
        let n = SubExportComposer.pageEstimate(rows: p.model.pageRowCount, perPage: perPageValue)
        Task { @MainActor in
            busy = "正在產生圖片…（約 \(n) 張）"
            // 讓「正在產生」那一層先畫出來（模組一次同步出完所有頁，中間插不進去，brief §1-7）
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
            let r = SubExportImage.render(p.model, perPage: perPageValue)
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
/// [v25.604 v4a] 只剩〔圖片｜文字〕、日子（一直看得到）＋〔只看○○〕、區塊清單（TeamExportComposer.pickRows）；
/// 「完成項目」那一列下面切〔當天｜這一週｜這個月｜全部〕。模型一律 resolveExport。
struct TeamExportSheet: View {
    let initialFormat: SubExportFormat
    /// 畫面上選的那一天（這頁可以改，不回寫畫面、不記）
    let day: Date
    /// 畫面上「只看：王小明」的那一位（nil＝沒有篩選）
    let onlyPersonId: UUID?
    /// 出圖：(這一份, 每頁幾項〔nil＝全部一張；v25.604 v4a 起這頁一律傳每頁幾項〕) → 結果
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
    @State private var loaded = false
    @State private var ask: Pending? = nil
    @State private var busy: String? = nil
    @State private var share: SubExportSharePayload? = nil
    @State private var failure: XSheetNote? = nil
    @State private var noteAfterShare: XSheetNote? = nil
    @State private var sharedOnce = false

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
            XSheetTitle(title: "匯出部屬總覽", subtitle: subtitle)
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
            content(m)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(m) }
        .disabled(busy != nil)
        .overlay { busyLayer }
    }

    /// [v25.604 v4a] 日子（一直看得到）、〔只看○○〕、〔圖片｜文字〕、區塊清單（字一律照 pickRows）
    private func content(_ m: TeamExportModel) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            dayCard
            if onlyPersonId != nil {
                onlyCard
            }
            XSheetFormatPicker(format: $format)
            XSheetTeamPickList(sections: TeamExportComposer.pickRows(options, m),
                               range: $options.completedRange,
                               onAll: { options.pickAll() },
                               onNone: { options.pickNone() },
                               onDefault: { options.pickDefault() },
                               onToggle: { p in toggle(p) })
        }
    }

    /// [v25.604 v4a] 勾／取消一列（依賴沒滿足照樣可以勾，不自動幫忙勾別的）
    private func toggle(_ p: TeamExportPick) {
        options.setPicked(p, !options.isPicked(p))
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

    @ViewBuilder
    private var busyLayer: some View {
        if let b = busy {
            XSheetBusyOverlay(text: b)
        }
    }

    // MARK: 底下那條

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

    /// [v25.604 v4a] 圖片一律照每頁幾項自動分頁（沒有〔全部一張〕）
    private func footLines(_ m: TeamExportModel) -> (text: String, warn: Bool, extra: String) {
        switch format {
        case .image:
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
    /// [v25.604 v4a] 一律 resolveExport（任務種類、會議種類、完成項目三種固定全帶；依賴沒滿足當沒勾）
    private func currentModel() -> TeamExportModel {
        TeamExportComposer.resolveExport(subordinates: lifeStore.activeSubordinates,
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

    /// 「10/28（三）・3 位」
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
        let n = SubExportComposer.pageEstimate(rows: p.model.pageRowCount, perPage: perPageValue)
        Task { @MainActor in
            busy = "正在產生圖片…（約 \(n) 張）"
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
            let r = makeImage(p.model, perPageValue)
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
/// [v25.604 v4a 裁定] 這頁不能再改每頁幾項：三句提示改成「到別的分頁的匯出把每頁項目數改…」（同一個 @AppStorage）
private enum XSheetFoot {
    static func pages(rows: Int, perPage: Int, hint: String) -> (text: String, warn: Bool) {
        if rows == 0 { return ("1 張（只有看板）", false) }
        let n = SubExportComposer.pageEstimate(rows: rows, perPage: perPage)
        if n > SubExportComposer.manyPages {
            return ("約 \(n) 張，很多；可以\(hint)，或到別的分頁的匯出把每頁項目數改大", true)
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
            let msg = "出圖失敗，可能是內容太長。可以\(hint)再試一次，或到別的分頁的匯出把每頁項目數改小。"
            return ([], XSheetNote(title: "圖片出不來", message: msg), nil)
        }
        var later: XSheetNote? = nil
        if r.urls.count < r.expected {
            let miss = r.expected - r.urls.count
            later = XSheetNote(title: "有 \(miss) 張出不來",
                               message: "有 \(miss) 張出不來，已略過；到別的分頁的匯出把每頁項目數改小可以補")
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

/// 導覽列中間兩行：「匯出部屬卡片」＋小字。
/// [v25.604 v4a] 部屬總覽的日子改成頁面上一直看得到（dayCard），小字不再能點、不再有展開箭頭
private struct XSheetTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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

// MARK: [v25.604 v4a] 區塊清單
//
// 每一列的字（名字、灰字、要先勾…、件數）都照 SubExportComposer.pickRows／TeamExportComposer.pickRows，這裡只畫。
// 依賴沒滿足、職能雷達還沒有評分（row.blockedText）：整列淡、小字換成橘字，照樣可以勾（不自動幫忙勾）。
// 不畫圖示圓（二十幾列太擠）。

/// 「要匯出哪些」＋〔全選〕〔全不選〕〔預設〕
private struct XSheetPickQuickRow: View {
    let onAll: () -> Void
    let onNone: () -> Void
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
        XSheetLinkChip(title: "全不選", action: onNone)
        XSheetLinkChip(title: "預設", action: onDefault)
    }
}

/// 一列的長相：方框勾＋名字＋小字一行（blockedText 橘、不然 caption 灰）＋右邊件數（「沒有」或淡掉的列灰）
private struct XSheetPickFace: View {
    let title: String
    let caption: String?
    let blockedText: String?
    let countText: String?
    let isOn: Bool

    private var isBlocked: Bool { blockedText != nil }

    private var smallText: String? { blockedText ?? caption }

    private var titleColor: Color { isBlocked ? Color.secondary : Color.primary }

    private var smallColor: Color { isBlocked ? Color.orange : Color.secondary }

    private var countColor: Color {
        (isBlocked || countText == "沒有") ? Color.secondary : Color.primary
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            XSheetCheckBox(isOn: isOn)
            texts
            Spacer(minLength: 6)
            countLabel
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(titleColor)
                .fixedSize(horizontal: false, vertical: true)
            smallLine
        }
    }

    @ViewBuilder
    private var smallLine: some View {
        if let s = smallText {
            Text(s)
                .font(.caption)
                .foregroundStyle(smallColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var countLabel: some View {
        if let c = countText {
            Text(c)
                .font(.headline)
                .foregroundStyle(countColor)
                .lineLimit(1)
        }
    }
}

/// 一列（整列一顆按鈕；VoiceOver：「名字，件數，已勾選／沒勾，小字」）
private struct XSheetPickRowView: View {
    let title: String
    let caption: String?
    let blockedText: String?
    let countText: String?
    let isOn: Bool
    let action: () -> Void

    private var spoken: String {
        var parts: [String] = [title]
        if let c = countText { parts.append(c) }
        parts.append(isOn ? "已勾選" : "沒勾")
        if let s = blockedText ?? caption { parts.append(s) }
        return parts.joined(separator: "，")
    }

    var body: some View {
        Button(action: action) {
            XSheetPickFace(title: title, caption: caption, blockedText: blockedText,
                           countText: countText, isOn: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isOn ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}

/// 部屬卡片的區塊清單：快捷一排＋每段小標＋白卡（看板／主動性／潛力性／執掌／職能／敏感）
private struct XSheetPickList: View {
    let sections: [SubExportPickSectionRows]
    let onAll: () -> Void
    let onNone: () -> Void
    let onDefault: () -> Void
    let onToggle: (SubExportPick) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            XSheetPickQuickRow(onAll: onAll, onNone: onNone, onDefault: onDefault)
            ForEach(sections) { sec in
                XSheetPickSectionView(section: sec, onToggle: onToggle)
            }
        }
    }
}

/// 部屬卡片清單的一段（敏感那段小標右邊橘字「分享前會提醒」）
private struct XSheetPickSectionView: View {
    let section: SubExportPickSectionRows
    let onToggle: (SubExportPick) -> Void

    private var trailing: String {
        section.rows.contains { $0.pick.isSensitive } ? "分享前會提醒" : ""
    }

    private var lastId: String? { section.rows.last?.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            XSheetSectionLabel(title: section.title, trailing: trailing, trailingColor: .orange)
            XSheetCard {
                ForEach(section.rows) { row in
                    rowView(row)
                    if row.id != lastId {
                        Divider()
                    }
                }
            }
        }
    }

    private func rowView(_ row: SubExportPickRow) -> XSheetPickRowView {
        let p: SubExportPick = row.pick
        return XSheetPickRowView(title: row.title, caption: row.caption, blockedText: row.blockedText,
                                 countText: row.countText, isOn: row.isOn, action: { onToggle(p) })
    }
}

/// 部屬總覽的區塊清單（看板／區塊／敏感）；「完成項目」那一列下面多〔當天｜這一週｜這個月｜全部〕
private struct XSheetTeamPickList: View {
    let sections: [TeamExportPickSectionRows]
    @Binding var range: TeamCompletedRange
    let onAll: () -> Void
    let onNone: () -> Void
    let onDefault: () -> Void
    let onToggle: (TeamExportPick) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            XSheetPickQuickRow(onAll: onAll, onNone: onNone, onDefault: onDefault)
            ForEach(sections) { sec in
                XSheetTeamPickSectionView(section: sec, range: $range, onToggle: onToggle)
            }
        }
    }
}

/// 部屬總覽清單的一段
private struct XSheetTeamPickSectionView: View {
    let section: TeamExportPickSectionRows
    @Binding var range: TeamCompletedRange
    let onToggle: (TeamExportPick) -> Void

    private var trailing: String {
        section.rows.contains { $0.pick.isSensitive } ? "分享前會提醒" : ""
    }

    private var lastId: String? { section.rows.last?.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            XSheetSectionLabel(title: section.title, trailing: trailing, trailingColor: .orange)
            XSheetCard {
                ForEach(section.rows) { row in
                    rowView(row)
                    if row.isCompleted {
                        XSheetRangePicker(range: $range, enabled: row.isOn)
                    }
                    if row.id != lastId {
                        Divider()
                    }
                }
            }
        }
    }

    private func rowView(_ row: TeamExportPickRow) -> XSheetPickRowView {
        let p: TeamExportPick = row.pick
        return XSheetPickRowView(title: row.title, caption: row.caption, blockedText: row.blockedText,
                                 countText: row.countText, isOn: row.isOn, action: { onToggle(p) })
    }
}

/// 完成項目範圍〔當天｜這一週｜這個月｜全部〕（照舊記住；沒勾完成項目時淡掉、不能切）。跟那一列的按鈕分開，不包在 Button 裡
private struct XSheetRangePicker: View {
    @Binding var range: TeamCompletedRange
    let enabled: Bool

    var body: some View {
        Picker("完成項目範圍", selection: $range) {
            ForEach(TeamCompletedRange.allCases) { r in
                Text(r.label).tag(r)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel("完成項目範圍")
    }
}

// MARK: 期間

/// 期間：小標右邊藍字「2026/10/1～10/31」、五顆等寬膠囊、〔自訂…〕兩個日子
/// [v25.604 v4a]「還沒做完、還沒到的不管期間都列」開關拿掉（固定＝是，forExport）；「期間只切做完的、發生過的」那行留著
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

// MARK: 底下那條、產圖中

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
