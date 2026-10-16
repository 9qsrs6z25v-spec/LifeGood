import SwiftUI
import MapKit
import Charts
import HealthKit

// MARK: - 一趟運動的成果頁（v25.553，健康 v3；health/judge.md §5.2，分享是 v5）
//
// 點一張運動卡打開（健康頁、全部紀錄都用 .sheet(item:) 打開、最外層 .appStores()）。卡片頁骨架同股票、房屋、車子（U3 §4.3、
// VehicleDetailView）：NavigationStack > ScrollViewReader > ScrollView > VStack(spacing 22，左右 16、上 10、下 28)，
// 換一趟列釘在導覽列下面（.safeAreaInset(.top)、.bar 底；同一週只有一趟不出現）。
//
// 由上到下（樣稿②-5）：① 成果看板（MoneyBoardHeader band 132＋風景「這一趟的路」＋FinanceTileGrid 六格，HeroCard.health 的圓角）
// → ② 這趟的收穫 → ③ 要確認 → ④ 路線（整頁唯一一張真地圖，快慢上色；點一下開全螢幕可拖可縮）→ ⑤ 每公里 → ⑥ 高度
// →（重訓、多個動作）動作 → ⑧ Apple 健康 → ⑨ 資料。字與數字全在 WorkoutCardData.build 算好（.task(id:) 裡算一次；換一趟時同步算好再換）。
//
// • 不盯記錄器、不每秒重畫：只讀 lifeStore（workoutsRevision 變了才重算）。
// • 彈出頁一個 WorkoutDetailSheet＋一個 .sheet(item:)（最外層 .appStores()）；刪除確認一個 .alert(presenting:)，
//   付費說明 .premiumLockAlert 掛在外層（同一個 view 不掛兩個 alert）。
// • 訂閱（待決定 8）：看全部免費；編輯、刪除要訂閱。放大地圖、換一趟不擋。
// • 刪除：確認後等提示框收完（0.35 秒）先關成果頁，再 WorkoutActions.delete（它自己再排到下一輪才寫 store）。
//   這一趟被別的地方刪掉（別台裝置同步過來）：0.6 秒後自己關掉。
// • 編輯過距離或時間（validSplits 是 nil）：每公里整區不出現、最快一公里「—」、要確認多一行說明；地圖照樣快慢上色。
//
// [v25.554] 健康 v4（build/v4/brief.md §6 G4；judge §5.2 ③⑧、§5.3）：
// • ③ 要確認有按鈕（全部交給 HealthSyncCenter，都不擋訂閱）：同一趟〔合成一筆〕（舊版記的〔接回來〕）〔兩筆都留〕；
//   舊版沒路線〔去 Apple 健康找〕→ 找的時候「正在 Apple 健康找…」、找到換〔接回來〕〔先不要〕、找不到寫一句。
//   看的是手錶那一趟時按〔合成一筆〕：手錶那一趟被拿掉了，直接換到合成好的那一趟（不關頁面）。
// • ⑧ Apple 健康一列：幾點存進去的、存入中（HealthSyncCenter.writing，子 view 自己看）、改過〔更新〕、手錶「10/8 匯入」、
//   合成過、沒開〔打開〕（同一個 .sheet(item:) 開 Apple 健康設定小頁）、沒寫入權限〔怎麼打開〕（說明框掛在這一列自己的 view）、
//   沒存〔存進去〕。寫入權限（canWriteWorkout）不會通知畫面：打開時、回到前景、彈出頁收起時重讀，變了才重算。
// • 刪除照 WorkoutActions.deleteAsk 三種：LifeGood 寫進 Apple 健康的〔連 Apple 健康那筆一起刪〕〔只刪 LifeGood 這筆〕〔取消〕；
//   手錶記的、合成過的、沒碰過 Apple 健康的〔刪除〕〔取消〕。
// • ⑨ 合成過的「記錄方式 LifeGood（iPhone）＋Apple Watch」、大卡「Apple Watch 量的」（字在 WorkoutCardData）。

struct WorkoutDetailView: View {
    /// 打開哪一趟；換一趟（同一週的換一趟列）在頁面裡面換，不重開 sheet
    let sessionId: UUID
    /// [v25.555] 剛跑完：跑步畫面按住結束、存好之後，同一個全螢幕直接換成這一頁（judge §4.3「先存再看」）。
    /// 左上「完成」（關掉整個全螢幕回健康頁）、導覽列下面「已存好・名稱 ✎・地點 ✎」那一條、沒有換一趟列。// G3：照 build/v5/brief.md §G3 實作
    let justFinished: Bool

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// 健康頁 Apple 健康開關（同 HealthView、WorkoutHealthWriter.enabledKey）
    @AppStorage("health_hk_enabled") private var hkEnabled = false
    /// [v25.554] Apple 健康有沒有給寫入（HealthKitManager.canWriteWorkout 不會通知畫面）：只拿來當重算的 key，
    /// 打開時、回到前景、彈出頁收起時重讀（去「健康」App 打開權限回來，〔怎麼打開〕換成〔存進去〕）
    @State private var hkCanWrite = false

    /// 現在看的是哪一趟（換一趟列點了就換）
    @State private var currentId: UUID
    /// 頁面上全部的字與數字：只在 .task(id:) 和換一趟時算
    @State private var card: WorkoutCardData?
    /// 上一次算 card 用的 key：換一趟時已經同步算好，.task 看到同一個 key 就不再算一次
    @State private var lastBuiltKey = ""
    /// 換一趟的方向（+1 往右邊那趟、-1 往左邊），決定滑入的方向
    @State private var slideDirection = 1
    @State private var sheet: WorkoutDetailSheet?
    /// [v25.554] 刪除確認框：字和三種按鈕先算好（WorkoutActions.deleteAsk）
    @State private var deleteAsk: WorkoutDeleteAsk?
    @State private var showPremiumAlert = false
    /// 正在關（刪掉了）：資料沒了也不再清空畫面、不再排第二次關
    @State private var closing = false

    init(sessionId: UUID, justFinished: Bool = false) {
        self.sessionId = sessionId
        self.justFinished = justFinished
        _currentId = State(initialValue: sessionId)
    }

    var body: some View {
        NavigationStack {
            scroller
                .alert(deleteAsk?.title ?? "", isPresented: deletePresented, presenting: deleteAsk) { a in
                    deleteButtons(a)
                } message: { a in
                    Text(a.message)
                }
        }
        // 收起時重讀寫入權限（Apple 健康設定小頁打開開關、同意之後回來）
        .sheet(item: $sheet, onDismiss: { refreshWriteAccess() }) { s in sheetView(s).appStores() }
        .premiumLockAlert(isPresented: $showPremiumAlert)
    }

    private var scroller: some View {
        ScrollViewReader { proxy in
            ScrollView {
                pageContent(proxy)
            }
            .background(Color(.systemGroupedBackground))
            .task(id: cardTaskKey) { rebuild() }
        }
        // 從「健康」App 改完權限回來
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshWriteAccess() }
        }
        // 換一趟列釘在導覽列下面：同一週不只一趟才出現
        .safeAreaInset(edge: .top, spacing: 0) { switcherBar }
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
    }

    // MARK: - 資料

    /// store 裡最新的這一趟（被刪掉是 nil）
    private var currentSession: WorkoutSession? {
        lifeStore.workouts.first { $0.id == currentId }
    }

    private var titleText: String {
        if let card { return card.title }
        if let s = currentSession { return WorkoutFacts.title(s) }
        return "運動"
    }

    /// 換一趟、運動改了（workoutsRevision：運動、每週目標、體重、[v25.554] Apple 健康的帳）、Apple 健康開關改了、
    /// [v25.554] 寫入權限改了都重算
    private var cardTaskKey: String {
        taskKey(for: currentId)
    }

    private func taskKey(for id: UUID) -> String {
        "\(id.uuidString)-\(lifeStore.workoutsRevision)-\(hkEnabled)-\(hkCanWrite)"
    }

    /// 在主執行緒算（WorkoutFormat 的 DateFormatter 共用）。
    /// [v25.554] 能不能用「健康」看 HealthKitManager.isAvailable（打包出來的 Info.plist 少了健康說明字也是 false：
    /// 那時按鈕按了也不會動，整列不出現）；寫入權限每次現讀
    private func buildCard(_ s: WorkoutSession) -> WorkoutCardData {
        let hk = HealthKitManager.shared
        return WorkoutCardData.build(session: s, sessions: lifeStore.workouts, prefs: lifeStore.workoutPrefs,
                                     bodyWeightKg: lifeStore.latestBodyWeightKg, hkEnabled: hkEnabled,
                                     hkAvailable: hk.isAvailable, hkCanWrite: hk.canWriteWorkout,
                                     ledger: lifeStore.workoutHealthLedger)
    }

    /// [v25.554] 重讀寫入權限；變了才寫（key 跟著變 → .task(id:) 重算一次）
    private func refreshWriteAccess() {
        let can = HealthKitManager.shared.canWriteWorkout
        if can != hkCanWrite { hkCanWrite = can }
    }

    private func rebuild() {
        refreshWriteAccess()
        guard let s = currentSession else {
            // 這一趟沒了（別台裝置刪的、同步過來）：沒有東西可看了。晚一點才關：
            // 編輯頁、提示框可能還在收，一邊收一邊關會被 UIKit 擋掉（同 VehicleDetailView）
            guard !closing else { return }
            closing = true
            card = nil
            lastBuiltKey = ""
            closeLater(seconds: 0.6)
            return
        }
        let key = cardTaskKey
        if card == nil || key != lastBuiltKey {
            card = buildCard(s)
            lastBuiltKey = key
        }
    }

    private func closeLater(seconds: Double) {
        let close = dismiss
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            close()
        }
    }

    /// 換到同一週的另一趟：新的那趟在這裡同步算好再換（不先清成 nil，滑進來的不會是一塊空白）
    private func jump(to id: UUID) {
        guard id != currentId, let s = lifeStore.workouts.first(where: { $0.id == id }) else { return }
        let list = card?.switcher ?? []
        let from = list.firstIndex { $0.id == currentId } ?? 0
        let to = list.firstIndex { $0.id == id } ?? 0
        let next = buildCard(s)
        slideDirection = to >= from ? 1 : -1
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            currentId = id
            card = next
        }
        lastBuiltKey = taskKey(for: id)
    }

    @ViewBuilder
    private var switcherBar: some View {
        if let items = card?.switcher, items.count > 1 {
            FinanceSwitcherStrip(items: items, selected: currentId) { id in
                jump(to: id)
            }
            .padding(.vertical, 4)
            .background(.bar)
        }
    }

    // MARK: - 工具列

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("關閉") { dismiss() }
        }
        // 標題是這一趟的名字（「河濱晨跑」「晨跑」），太長跑馬燈
        ToolbarItem(placement: .principal) {
            MarqueeText(titleText)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 16) {
                moreMenu
                Button {
                    edit()
                } label: {
                    Text("編輯").foregroundStyle(.green)
                }
                .disabled(card == nil)
            }
        }
    }

    /// 「⋯」：刪除這一趟（v5 在同一個選單加「分享」）
    private var moreMenu: some View {
        Menu {
            Button(role: .destructive) {
                askDelete()
            } label: {
                Label("刪除這一趟", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("更多")
        .disabled(card == nil)
    }

    // MARK: - 內容

    private var slideTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: slideDirection > 0 ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: slideDirection > 0 ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private func pageContent(_ proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 22) {
            if let card {
                upperSections(card, proxy: proxy)
                lowerSections(card)
            } else {
                Color.clear.frame(height: 360)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 28)
        // 換一趟時整包內容依方向滑入（id 變了就觸發轉場）
        .id(currentId)
        .transition(slideTransition)
    }

    /// 看板、收穫、要確認、路線、每公里（各區自己決定整區要不要出現）
    @ViewBuilder
    private func upperSections(_ c: WorkoutCardData, proxy: ScrollViewProxy) -> some View {
        WorkoutDetailBoard(data: c, onTap: { tap in scroll(proxy, to: tap) })
            .id(WorkoutDetailAnchor.top)
        WorkoutDetailGains(gains: c.gains)
        WorkoutDetailChecks(checks: c.checks, sessionId: c.sessionId, onMerged: { id in showMerged(id) })
        WorkoutDetailRoute(route: c.route, note: c.routeNote, onOpen: { openMap() })
        WorkoutDetailSplits(data: c.splits)
            .id(WorkoutDetailAnchor.splits)
    }

    /// 高度、動作、Apple 健康、資料
    @ViewBuilder
    private func lowerSections(_ c: WorkoutCardData) -> some View {
        WorkoutDetailElevationSection(data: c.elevation, sport: c.sport)
            .id(WorkoutDetailAnchor.elevation)
        WorkoutDetailMoves(moves: c.moves)
        WorkoutDetailAppleHealth(line: c.health, sessionId: c.sessionId, onOpen: { openAppleHealth() })
        WorkoutDetailInfo(items: c.info)
    }

    /// 六格點了：最快一公里 → 每公里；爬升 → 高度
    private func scroll(_ proxy: ScrollViewProxy, to tap: WorkoutCardData.TileTap) {
        let target: WorkoutDetailAnchor
        switch tap {
        case .none: return
        case .splits: target = .splits
        case .elevation: target = .elevation
        }
        withAnimation(.easeInOut(duration: 0.35)) {
            proxy.scrollTo(target, anchor: .top)
        }
    }

    // MARK: - 動作（編輯、刪除擋訂閱；放大地圖不擋）

    private func requirePremium(_ action: () -> Void) {
        guard subscription.isPremium else {
            showPremiumAlert = true
            return
        }
        action()
    }

    private func edit() {
        guard let s = currentSession else { return }
        requirePremium {
            sheet = .edit(UUID(), s)
        }
    }

    private func openMap() {
        guard card?.route != nil else { return }
        sheet = .map(UUID())
    }

    /// [v25.554] Apple 健康那一列〔打開〕：開 Apple 健康設定小頁（不擋訂閱：同 v3 開關與同步不擋）
    private func openAppleHealth() {
        sheet = .appleHealth(UUID())
    }

    /// [v25.554] 看手錶那一趟時按了〔合成一筆〕：手錶那一趟被拿掉了，換到合成好的那一趟（不然 0.6 秒後整頁關掉）。
    /// 已經在關（這一趟沒了、刪除中）就照關
    private func showMerged(_ id: UUID) {
        guard !closing else { return }
        jump(to: id)
    }

    private func askDelete() {
        guard let s = currentSession else { return }
        requirePremium {
            deleteAsk = WorkoutActions.deleteAsk(s)
        }
    }

    private var deletePresented: Binding<Bool> {
        Binding(get: { deleteAsk != nil }, set: { if !$0 { deleteAsk = nil } })
    }

    /// [v25.554] 刪除確認框的按鈕（WorkoutActions.deleteKind）：LifeGood 寫進 Apple 健康的三顆；手錶的、合成過的、沒碰過的〔刪除〕〔取消〕
    @ViewBuilder
    private func deleteButtons(_ a: WorkoutDeleteAsk) -> some View {
        if a.kind == .withHealth {
            Button("連 Apple 健康那筆一起刪", role: .destructive) { confirmDelete(a, alsoFromHealth: true) }
            Button("只刪 LifeGood 這筆", role: .destructive) { confirmDelete(a, alsoFromHealth: false) }
        } else {
            Button("刪除", role: .destructive) { confirmDelete(a, alsoFromHealth: false) }
        }
        Button("取消", role: .cancel) {}
    }

    /// 〔刪除〕：等提示框收完先關成果頁，再刪（WorkoutActions.delete 自己再排到下一輪才寫 store）。
    /// [v25.554] alsoFromHealth：〔連 Apple 健康那筆一起刪〕；Apple 健康那筆留著的，HealthSyncCenter 記進「不再帶進來」
    private func confirmDelete(_ a: WorkoutDeleteAsk, alsoFromHealth: Bool) {
        closing = true
        let id = a.id
        let store = lifeStore
        let close = dismiss
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            close()
            WorkoutActions.delete(id, alsoFromHealth: alsoFromHealth, store: store)
        }
    }

    // MARK: - 彈出頁

    @ViewBuilder
    private func sheetView(_ s: WorkoutDetailSheet) -> some View {
        switch s {
        case .edit(_, let session):
            editor(session)
        case .map:
            fullMap
        case .appleHealth:
            HealthAppleHealthSheet()
        }
    }

    /// 編輯：WorkoutEditorView 已經在關掉之後下一輪才呼叫 onSave
    private func editor(_ session: WorkoutSession) -> some View {
        let store = lifeStore
        return WorkoutEditorView(session: session) { saved in
            let edited = saved
            Task { @MainActor in WorkoutActions.save(edited, store: store) }
        }
    }

    @ViewBuilder
    private var fullMap: some View {
        if let r = card?.route {
            WorkoutDetailFullMap(route: r, title: card?.title ?? "路線")
        } else {
            Text("這一趟沒有路線")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding()
        }
    }
}

// MARK: - 小型別（只在這個檔裡）

/// 成果頁的彈出頁（一個 .sheet(item:)；request 帶新 UUID，同一趟再開一次也是新的表單）
private enum WorkoutDetailSheet: Identifiable {
    case edit(UUID, WorkoutSession)
    case map(UUID)
    /// [v25.554] Apple 健康那一列〔打開〕：Apple 健康設定小頁（HealthView.swift 的 HealthAppleHealthSheet）
    case appleHealth(UUID)

    var id: UUID {
        switch self {
        case .edit(let id, _): return id
        case .map(let id): return id
        case .appleHealth(let id): return id
        }
    }
}

/// [v25.554] 〔去 Apple 健康找〕舊版沒存到的路線：還沒按／找的時候／找不到（找到了看 HealthSyncCenter.routeFinds）
private enum WorkoutDetailFindState: Equatable {
    case idle, searching, notFound
}

/// [v25.554] 要確認一列畫面要的東西（字和按鈕先組好，body 只畫）
private struct WorkoutDetailCheckRow: Identifiable {
    let id: String
    let icon: String
    let message: String
    let buttons: [FinanceCheckButton]

    /// 第一顆按鈕的 VoiceOver：「按鈕字：句子」（同健康頁）；沒有按鈕唸句子
    var spoken: String {
        guard let first = buttons.first else { return message }
        return first.title + "：" + message
    }
}

/// 六格捲過去的位置
private enum WorkoutDetailAnchor: Hashable {
    case top, splits, elevation
}

/// 地圖上線的粗細：先畫 7pt 的邊（淺色白、深色深藍），再畫 4pt 的快慢色（灰色那段才看得到）
private enum WorkoutDetailMapStroke {
    static let casing = StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
    static let line = StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
}

// MARK: - ① 成果看板

/// 天空（這一趟的路，從側面看）＋六格。外框照 VehicleCardBoard 自己組（頭部要蓋 VoiceOver 那一句），
/// 圓角吃 HeroCard.health（跟健康頁看板同一個設定）
private struct WorkoutDetailBoard: View {
    let data: WorkoutCardData
    let onTap: (WorkoutCardData.TileTap) -> Void

    @Environment(\.colorScheme) private var scheme
    /// 只讀「圓角」（同 MoneyBoardCard：看板不吃英雄卡的漸層與 KPI 樣式）
    @ObservedObject private var heroStyle = HeroStyleStore.shared

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let corner = CGFloat(heroStyle.value(.corner, .health))
        VStack(alignment: .leading, spacing: 0) {
            header(pal)
            tiles(pal)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 14)
        }
        .modifier(MoneyBoardChrome(pal: pal, corner: corner))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func header(_ pal: TripBoardPalette) -> some View {
        let b = data.board
        let line: Text? = b.line.runs.isEmpty ? nil : FinanceLineText.text(b.line, pal: pal)
        return MoneyBoardHeader(
            date: b.date,
            dateIcon: b.dateIcon,
            capsule: b.capsule,
            capsuleIcon: b.capsuleIcon,
            capsuleTint: nil,
            label: b.label,
            big: b.big,
            bigTone: nil,
            line: line,
            greeting: b.greeting,
            scene: .runTrail(data.scene),
            band: 132,
            seed: b.seed)
            // 整個頭部一個 VoiceOver 元素（風景本來就 accessibilityHidden）
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(b.accessibilityText)
    }

    private func tiles(_ pal: TripBoardPalette) -> some View {
        let tap = onTap
        return FinanceTileGrid(tiles: data.tiles, pal: pal, onTap: { (t: WorkoutCardData.Tile) in
            tap(t.tap)
        })
    }
}

// MARK: - ② 這趟的收穫

private struct WorkoutDetailGains: View {
    let gains: [WorkoutCardData.Gain]

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if !gains.isEmpty {
            content(TripBoardPalette(scheme))
        }
    }

    private func content(_ pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "這趟的收穫")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(gains.enumerated()), id: \.element.id) { i, g in
                    if i > 0 {
                        Divider().padding(.leading, 58)
                    }
                    row(g, pal: pal)
                }
            }
            .modifier(FinanceCardChrome())
        }
    }

    private func row(_ g: WorkoutCardData.Gain, pal: TripBoardPalette) -> some View {
        HStack(spacing: 12) {
            TripBoardIconBadge(icon: g.icon, colors: badgeColors(g), diameter: 32, dark: pal.dark)
            FinanceSentence(line: g.line, pal: pal)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(g.accessibilityText)
    }

    /// 目標那列：這種運動的主題色（跑步橘）；連續週數：綠
    private func badgeColors(_ g: WorkoutCardData.Gain) -> [Color] {
        guard let sport = g.sport else { return [Color(tb: 0x5BD99A), Color(tb: 0x1F9D57)] }
        let t = MoneyArtTheme.of(sport)
        return [t.topColor, t.bottomColor]
    }
}

// MARK: - ③ 要確認（[v25.554] 有按鈕：〔合成一筆〕〔接回來〕〔兩筆都留〕〔去 Apple 健康找〕〔先不要〕；都不擋訂閱）

/// 按鈕全部交給 HealthSyncCenter（它自己在 await 之後才寫 store、重新拿最新的那一筆）。
/// 換一趟時整包內容 .id(currentId) 重建，找路線的狀態跟著回到還沒按
private struct WorkoutDetailChecks: View {
    let checks: [WorkoutCardData.Check]
    /// 這一趟（找路線、接回來用）
    let sessionId: UUID
    /// 看手錶那一趟時合成好了：換到合成好的那一趟（App 那一趟的 id）
    let onMerged: (UUID) -> Void

    @EnvironmentObject var lifeStore: LifeStore
    @ObservedObject private var sync = HealthSyncCenter.shared
    @Environment(\.colorScheme) private var scheme
    @State private var findState: WorkoutDetailFindState = .idle

    var body: some View {
        if !checks.isEmpty {
            content(TripBoardPalette(scheme))
        }
    }

    private func content(_ pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "要確認")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                    if i > 0 {
                        Divider().padding(.leading, 44)
                    }
                    FinanceCheckRow(icon: r.icon, message: r.message, buttons: r.buttons,
                                    accessibilityLabel: r.spoken, pal: pal)
                }
            }
            .modifier(FinanceCardChrome())
        }
    }

    // MARK: 字與按鈕

    private var rows: [WorkoutDetailCheckRow] {
        checks.map { row(for: $0) }
    }

    /// 這一趟在 Apple 健康找到的手錶路線（健康頁自動同步找到的、這頁〔去 Apple 健康找〕找到的）
    private var find: WorkoutRouteFind? {
        sync.routeFinds.first { $0.sessionId == sessionId }
    }

    private func row(for c: WorkoutCardData.Check) -> WorkoutDetailCheckRow {
        // 舊版沒路線那一列：找到了換〔接回來〕〔先不要〕；找的時候、找不到換一句（沒按鈕）
        if c.actions.contains(.findRoute) {
            if let f = find {
                return WorkoutDetailCheckRow(id: c.id, icon: c.icon, message: WorkoutCardData.routeFoundMessage,
                                             buttons: findButtons(f))
            }
            switch findState {
            case .searching:
                return WorkoutDetailCheckRow(id: c.id, icon: c.icon,
                                             message: WorkoutCardData.routeSearchingMessage, buttons: [])
            case .notFound:
                return WorkoutDetailCheckRow(id: c.id, icon: c.icon,
                                             message: WorkoutCardData.routeNotFoundMessage, buttons: [])
            case .idle:
                break
            }
        }
        let buttons: [FinanceCheckButton] = c.actions.map { a in
            FinanceCheckButton(title: a.title, action: { perform(a) })
        }
        return WorkoutDetailCheckRow(id: c.id, icon: c.icon, message: c.message, buttons: buttons)
    }

    private func findButtons(_ f: WorkoutRouteFind) -> [FinanceCheckButton] {
        let store = lifeStore
        let center = sync
        return [
            FinanceCheckButton(title: "接回來") {
                Task { @MainActor in await center.attachRoute(f, store: store) }
            },
            FinanceCheckButton(title: "先不要") {
                Task { @MainActor in center.skipRoute(f, store: store) }
            }
        ]
    }

    // MARK: 動作

    private func perform(_ a: WorkoutCardData.CheckAction) {
        let store = lifeStore
        let center = sync
        switch a {
        case .merge(let d):
            let viewingWatch = d.watchId == sessionId
            let done = onMerged
            Task { @MainActor in
                await center.merge(d, store: store)
                // 看的是手錶那一趟：合成好了它就被拿掉了，換到合成好的那一趟
                let ids = Set(store.workouts.map(\.id))
                if viewingWatch, ids.contains(d.appId), !ids.contains(d.watchId) {
                    done(d.appId)
                }
            }
        case .keepBoth(let d):
            // 寫帳排到下一輪（按鈕按下去那一次畫面更新先過；這一列會跟著消失）
            Task { @MainActor in center.keepBoth(d, store: store) }
        case .findRoute:
            findState = .searching
            let id = sessionId
            Task { @MainActor in
                let f = await center.findRoute(for: id, store: store)
                findState = f == nil ? .notFound : .idle
            }
        }
    }
}

// MARK: - ④ 路線

/// 白卡：200pt 的地圖（平常不能拖，點一下開全螢幕）＋圖例；沒有路線換一行灰字（重訓整區不出現）
private struct WorkoutDetailRoute: View {
    let route: WorkoutCardData.RouteMap?
    let note: String?
    let onOpen: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let route {
            mapSection(route)
        } else if let note {
            noteSection(note)
        }
    }

    private func mapSection(_ r: WorkoutCardData.RouteMap) -> some View {
        let dark = scheme == .dark
        return VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "路線", trailing: "點一下放大")
            VStack(alignment: .leading, spacing: 10) {
                mapButton(r, dark: dark)
                if r.paced {
                    WorkoutDetailLegend(note: r.legendNote, dark: dark)
                }
            }
            .padding(12)
            .modifier(FinanceCardChrome())
        }
    }

    /// 地圖本身不吃手勢（捲頁面不會被地圖攔住），上面蓋一個透明按鈕
    private func mapButton(_ r: WorkoutCardData.RouteMap, dark: Bool) -> some View {
        WorkoutDetailMap(route: r, interactive: false, dark: dark)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .overlay {
                Button(action: onOpen) {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("放大路線地圖")
                .accessibilityHint(r.accessibilityText)
            }
    }

    private func noteSection(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "路線")
            Text(note)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .modifier(FinanceCardChrome())
        }
    }
}

/// 路線地圖（卡片裡那張、全螢幕那張共用）：每一小段先畫邊再畫快慢色、暫停斷開不連線；
/// 每整公里白底小牌、暫停小牌、起點白圈（運動色邊）、終點方格旗
private struct WorkoutDetailMap: View {
    let route: WorkoutCardData.RouteMap
    let interactive: Bool
    let dark: Bool

    var body: some View {
        Map(initialPosition: camera, interactionModes: modes) {
            ForEach(route.pieces) { p in
                MapPolyline(coordinates: p.coordinates)
                    .stroke(casingColor, style: WorkoutDetailMapStroke.casing)
            }
            ForEach(route.pieces) { p in
                MapPolyline(coordinates: p.coordinates)
                    .stroke(lineColor(p), style: WorkoutDetailMapStroke.line)
            }
            ForEach(route.pauses) { m in
                Annotation("", coordinate: m.coordinate, anchor: .bottom) {
                    WorkoutDetailPauseTag(text: m.text)
                }
            }
            ForEach(route.marks) { m in
                Annotation("", coordinate: m.coordinate) {
                    WorkoutDetailKmPill(text: m.text)
                }
            }
            Annotation("", coordinate: route.start) {
                WorkoutDetailStartDot(color: sportColor)
            }
            Annotation("", coordinate: route.end, anchor: .bottomLeading) {
                WorkoutDetailFinishFlag(dark: dark)
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))   // 淡色、不顯示店家，線最清楚
    }

    /// 鏡頭：中心照 RouteMath.bounds，範圍照路線自己的南北、東西（WorkoutCardData.cameraSpan；長條的路放滿長條的地圖）
    private var camera: MapCameraPosition {
        let span = MKCoordinateSpan(latitudeDelta: route.latitudeDelta, longitudeDelta: route.longitudeDelta)
        return .region(MKCoordinateRegion(center: route.center, span: span))
    }

    /// 卡片裡那張不能動；全螢幕可拖可縮（不給轉、不給傾斜：北方朝上）
    private var modes: MapInteractionModes {
        interactive ? [.pan, .zoom] : []
    }

    private var casingColor: Color { WorkoutPalette.casing(dark: dark) }

    private var sportColor: Color { WorkoutPalette.sport(route.sport, dark: dark) }

    /// 快慢五級；算不出快慢（點上沒有時間）整條運動色
    private func lineColor(_ p: WorkoutCardData.RouteMap.Piece) -> Color {
        guard let level = p.level else { return sportColor }
        return WorkoutPalette.pace(level, dark: dark)
    }
}

/// 每整公里的白底小牌「1」「2」…
private struct WorkoutDetailKmPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color(tb: 0x0B1B45))
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Color.white, in: Capsule())
            .overlay(Capsule().stroke(Color(tb: 0x0B1B45, 0.25), lineWidth: 0.75))
            .shadow(color: Color.black.opacity(0.18), radius: 1.5, x: 0, y: 1)
    }
}

/// 暫停的地方「暫停 2:30」
private struct WorkoutDetailPauseTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(Color(tb: 0x4A5B8C))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.92), in: Capsule())
    }
}

/// 起點：白圈、運動色邊
private struct WorkoutDetailStartDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(color, lineWidth: 3))
    }
}

/// 終點：方格旗（旗竿底對著終點）
private struct WorkoutDetailFinishFlag: View {
    let dark: Bool

    var body: some View {
        Image(systemName: "flag.checkered")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(dark ? Color.white : Color(tb: 0x0B1B45))
            .shadow(color: dark ? Color.black.opacity(0.6) : Color.white, radius: 1.5)
    }
}

/// 圖例：五個小色條＋「快很多 快 差不多 慢 慢很多」＋灰字「（跟這趟平均 6'11" 比）」
private struct WorkoutDetailLegend: View {
    let note: String
    let dark: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ChipFlowLayout(spacing: 10) {
                ForEach(WorkoutPaceLevel.allCases, id: \.self) { level in
                    item(level)
                }
            }
            if !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("路線顏色：藍色比較快、灰色差不多、琥珀色比較慢" + note)
    }

    private func item(_ level: WorkoutPaceLevel) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(WorkoutPalette.pace(level, dark: dark))
                .frame(width: 16, height: 5)
            Text(level.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.primary)
        }
    }
}

/// 全螢幕地圖（同一張地圖、可以拖、可以縮；左上「完成」）
private struct WorkoutDetailFullMap: View {
    let route: WorkoutCardData.RouteMap
    let title: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            WorkoutDetailMap(route: route, interactive: true, dark: scheme == .dark)
                .ignoresSafeArea(edges: .bottom)
                .safeAreaInset(edge: .bottom, spacing: 0) { legendBar }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("完成") { dismiss() }
                    }
                }
        }
    }

    @ViewBuilder
    private var legendBar: some View {
        if route.paced {
            WorkoutDetailLegend(note: route.legendNote, dark: scheme == .dark)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
        }
    }
}

// MARK: - ⑤ 每公里

/// 一行一公里（騎車滿 5 公里每 5 公里一行、寫時速）：「1　6'02"　███▌ 快　+4 m　★」；
/// 最後不滿一段「0.2　1'14"（換算每公里 6'10"，跟平均差不多）」
private struct WorkoutDetailSplits: View {
    let data: WorkoutCardData.Splits?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let d = data, !d.rows.isEmpty {
            content(d)
        }
    }

    private func content(_ d: WorkoutCardData.Splits) -> some View {
        let dark = scheme == .dark
        return VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: d.title, trailing: d.trailing)
            VStack(alignment: .leading, spacing: 0) {
                if let cap = d.caption {
                    Text(cap)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                }
                ForEach(Array(d.rows.enumerated()), id: \.element.id) { i, row in
                    if i > 0 {
                        Divider().padding(.leading, 14)
                    }
                    WorkoutDetailSplitRow(row: row, dark: dark)
                }
            }
            .padding(.vertical, 2)
            .modifier(FinanceCardChrome())
        }
        // 一行固定欄寬（@ScaledMetric）加起來：xxxLarge 約 328pt，SE 卡片 343pt 還放得下長條；
        // 再大（輔助字級）會超出卡片，跟看板一樣封頂
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

private struct WorkoutDetailSplitRow: View {
    let row: WorkoutCardData.SplitRow
    let dark: Bool

    // 欄寬跟著字級放大（字放大時數字不會被切掉）
    @ScaledMetric(relativeTo: .subheadline) private var labelWidth: CGFloat = 30
    @ScaledMetric(relativeTo: .subheadline) private var valueWidth: CGFloat = 56
    @ScaledMetric(relativeTo: .caption) private var wordWidth: CGFloat = 40
    @ScaledMetric(relativeTo: .caption) private var climbWidth: CGFloat = 44

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(row.label)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .trailing)
            Text(row.value)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(Color.primary)
                .frame(width: valueWidth, alignment: .leading)
            if let note = row.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                barPart
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityText)
    }

    /// 長條（越快越長、五級色）＋級別字（字一律一般字色）＋爬升＋最快那一段的星星
    private var barPart: some View {
        HStack(alignment: .center, spacing: 8) {
            WorkoutDetailSplitBar(fraction: row.fraction, color: WorkoutPalette.pace(row.level, dark: dark))
            Text(row.levelWord)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.primary)
                .frame(width: wordWidth, alignment: .leading)
            Text(row.climb)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: climbWidth, alignment: .trailing)
            Image(systemName: "star.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(tb: 0xFFC93C))
                .opacity(row.star ? 1 : 0)
                .frame(width: 14)
        }
    }
}

private struct WorkoutDetailSplitBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(color)
                .frame(width: max(6, geo.size.width * CGFloat(fraction)), height: 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

// MARK: - ⑥ 高度

private struct WorkoutDetailElevationSection: View {
    let data: WorkoutCardData.Elevation?
    let sport: WorkoutSport

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let d = data {
            content(d)
        }
    }

    private func content(_ d: WorkoutCardData.Elevation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "高度")
            VStack(alignment: .leading, spacing: 10) {
                // 「爬升 18 m・下降 17 m・最高比起點高 9 m」：數字粗體（同這趟的收穫那一句）
                FinanceSentence(line: d.summary, pal: TripBoardPalette(scheme))
                WorkoutDetailElevationChart(data: d, color: lineColor)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(FinanceCardChrome())
        }
    }

    /// 高度不是快慢：用運動色（不用配速五級色）
    private var lineColor: Color {
        WorkoutPalette.sport(sport, dark: scheme == .dark)
    }
}

/// 高度對距離的面積小圖（同股票融資那張的寫法：AreaMark 從底畫到值、上面一條 LineMark），高 110
private struct WorkoutDetailElevationChart: View {
    let data: WorkoutCardData.Elevation
    let color: Color

    var body: some View {
        chart
            .chartYScale(domain: data.floor...data.ceiling)
            .chartXScale(domain: 0...data.totalKm)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5))
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
            }
            .frame(height: 110)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(data.accessibilityText)
    }

    private var areaFill: LinearGradient {
        LinearGradient(colors: [color.opacity(0.28), color.opacity(0.04)], startPoint: .top, endPoint: .bottom)
    }

    private var chart: some View {
        Chart {
            ForEach(data.points) { p in
                AreaMark(x: .value("公里", p.km), yStart: .value("底", data.floor),
                         yEnd: .value("高度", p.meters))
                    .foregroundStyle(areaFill)
                LineMark(x: .value("公里", p.km), y: .value("高度", p.meters))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            if let peak = data.peak {
                PointMark(x: .value("公里", peak.km), y: .value("高度", peak.meters))
                    .foregroundStyle(color)
                    .symbolSize(30)
                    .annotation(position: .top, spacing: 2) {
                        Text(data.peakLabel)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
            }
        }
    }
}

// MARK: - 動作（重訓、或一趟裡不只一個動作）

private struct WorkoutDetailMoves: View {
    let moves: [WorkoutCardData.Move]

    var body: some View {
        if !moves.isEmpty {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "動作", trailing: "\(moves.count) 個")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(moves.enumerated()), id: \.element.id) { i, m in
                    if i > 0 {
                        Divider().padding(.leading, 14)
                    }
                    row(m)
                }
            }
            .modifier(FinanceCardChrome())
        }
    }

    private func row(_ m: WorkoutCardData.Move) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(m.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
            Text(m.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - ⑧ Apple 健康（一列；裝置不支援不出現）

/// [v25.554] 字與按鈕在 WorkoutCardData.makeHealth 算好；這裡只多看 HealthSyncCenter.writing（存入中即時換字，
/// 不放進 .task(id:) 算的 card）。〔怎麼打開〕的說明框掛在這個 view（成果頁的刪除框掛在外層，同一個 view 不掛兩個 alert）
private struct WorkoutDetailAppleHealth: View {
    let line: WorkoutCardData.HealthLine?
    let sessionId: UUID
    /// 〔打開〕：開 Apple 健康設定小頁（成果頁的 .sheet(item:)）
    let onOpen: () -> Void

    @EnvironmentObject var lifeStore: LifeStore
    @ObservedObject private var sync = HealthSyncCenter.shared
    @Environment(\.colorScheme) private var scheme
    @State private var showHowTo = false
    /// 這一列按了〔存進去〕〔更新〕沒成功的那一句（HealthSyncCenter.lastProblem）；再按一次清掉
    @State private var problem: String? = nil

    var body: some View {
        if let line {
            row(line, pal: TripBoardPalette(scheme))
                .alert(WorkoutCardData.howToTitle, isPresented: $showHowTo) {
                    Button("好", role: .cancel) {}
                } message: {
                    Text(WorkoutCardData.howToMessage)
                }
        }
    }

    /// 正在寫進 Apple 健康（新的一趟剛存、〔存進去〕、〔更新〕）
    private var isWriting: Bool {
        sync.writing.contains(sessionId)
    }

    private func row(_ l: WorkoutCardData.HealthLine, pal: TripBoardPalette) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 30, height: 30)
                .background(heartFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            texts(l, pal: pal)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            trailingButton(l, pal: pal)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .modifier(FinanceCardChrome())
    }

    /// 一行粗體（已存進、合成過綠字；其他一般灰字，不染紅）＋小字；存入中整列換「存進 Apple 健康中…」
    @ViewBuilder
    private func texts(_ l: WorkoutCardData.HealthLine, pal: TripBoardPalette) -> some View {
        if isWriting {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(WorkoutCardData.healthWritingText)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(l.text)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(l.good ? MoneyTone.good.color(pal) : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let sub = subText(l) {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// 小字：剛剛按了沒成功的那一句優先（還有按鈕可以再按時才寫），不然 card 算好的那一句
    private func subText(_ l: WorkoutCardData.HealthLine) -> String? {
        if l.button != .none, let p = problem, !p.isEmpty { return p }
        return l.note
    }

    /// 右邊的膠囊按鈕（樣子同 FinanceCheckRow）；存入中不出現
    @ViewBuilder
    private func trailingButton(_ l: WorkoutCardData.HealthLine, pal: TripBoardPalette) -> some View {
        if !isWriting, l.button != .none {
            Button {
                tap(l.button)
            } label: {
                Text(l.button.title)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(pal.hint)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 11)
                    .frame(minHeight: 30)
                    .background(pal.hint.opacity(0.12), in: Capsule())
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityLabel(l.button.title + "：" + l.text)
        }
    }

    /// 〔更新〕〔存進去〕交給 HealthSyncCenter（它自己在 await 之後拿 store 最新的那一筆）；〔打開〕回呼開設定小頁；
    /// 〔怎麼打開〕自己的說明框。都不擋訂閱
    private func tap(_ b: WorkoutCardData.HealthButton) {
        problem = nil
        let id = sessionId
        let store = lifeStore
        let center = sync
        switch b {
        case .none:
            return
        case .open:
            onOpen()
        case .howTo:
            showHowTo = true
        case .update:
            Task { @MainActor in
                await center.update(id, store: store)
                // 有編號而且不再是「改過」＝更新好了（不拿別的動作留下的 lastProblem 來寫）；
                // 還是改過、或舊的刪了新的沒寫進去，才寫為什麼
                let latest = store.workouts.first(where: { $0.id == id })
                let done = latest.map { $0.healthKitUUID != nil && WorkoutFacts.healthStale($0) == nil } ?? true
                problem = done ? nil : (center.lastProblem ?? "沒更新成功")
            }
        case .push:
            Task { @MainActor in
                // 下一輪才拿 store 裡最新的那一筆（按下去到這裡之間可能被編輯、刪掉）
                guard let s = store.workouts.first(where: { $0.id == id }) else { return }
                await center.push(s, store: store)
                // 還是沒有編號＝沒寫進去：寫一句為什麼（有編號＝成功，這一列會換成「已存進」）
                let saved = store.workouts.first(where: { $0.id == id })?.healthKitUUID != nil
                problem = saved ? nil : (center.lastProblem ?? "沒存進 Apple 健康")
            }
        }
    }

    private var heartFill: LinearGradient {
        LinearGradient(colors: [Color(tb: 0xFF6B8A), Color(tb: 0xF2355B)], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - ⑨ 資料（永遠出現）

private struct WorkoutDetailInfo: View {
    let items: [WorkoutCardData.InfoItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "資料")
            FinanceInfoRows(rows: rows)
                .modifier(FinanceCardChrome())
        }
    }

    private var rows: [FinanceInfoRows.Row] {
        items.map { item in
            FinanceInfoRows.Row(id: item.id,
                                content: AnyView(FinanceInfoRow(label: item.label, value: valueText(item))))
        }
    }

    /// 值；有 note 時下面多一行灰色小字（大卡「估的，依體重 72.4 kg」）。用插值接，不串 +
    private func valueText(_ item: WorkoutCardData.InfoItem) -> Text {
        guard let note = item.note, !note.isEmpty else { return Text(item.value) }
        let main = Text(item.value)
        let sub: Text = Text(note).font(.caption).foregroundStyle(.secondary)
        return Text("\(main)\n\(sub)")
    }
}
