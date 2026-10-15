import SwiftUI
import Charts
import Combine

// MARK: - 健康（v25.351 建立，v25.352 加入 Apple 健康聯動與跑步路徑）
//
// 訓練量＝總次數（每組次數 × 組數）× 等效負荷。負荷是「自身體重」時帶入健康檔案
// 最近一次的體重；沒有體重紀錄就不灌進總量（見 WorkoutExercise.volume）。
//
// HealthKit 沒有組數／次數／負荷的欄位，所以重訓明細只留在本 App，寫回去的只有
// 時間、距離與熱量——Apple 健康設定小頁有明講，不要讓使用者以為明細會同步。
//
// [v25.551] 即時紀錄橫幅寫運動名；訓練紀錄的爬升 10 公尺以上才顯示；舊版記錄的那幾筆多一行灰字說明。
// [v25.552] 健康 v2：數字和字全部讀一套（WorkoutFacts／WorkoutFormat）；刪除先問；「＋」先選運動；
// 上次跑到一半被關掉的那一趟有救回卡（RunRecoveryCenter）；寫進 Apple 健康走共用的 WorkoutHealthWriter。
//
// [v25.553] 健康 v3：新骨架，跟記帳、理財、車子同一套零件（health/judge.md §3、build/v3/brief.md §G4）。
//   • 捲動頁（同收支總覽）：由上到下 ⓪ 記錄中條（釘在最上面）→ ① 看板（天空、河堤、這週跑了 14.6 公里）→
//     ② 開始列 → ③ 要確認（救回）→ ④ 最近運動（一趟一張 MoneyItemCard，卡面是路線形狀、不開地圖）→
//     ⑤ 每週公里 → ⑥ 重訓（綜效曲線＋動作統計）→ ⑦ Apple 健康一列（點了打開設定小頁）→ ⑧ 健康里程碑。
//   • 整頁的字和數字在 .task(id:) 裡用 HealthPageData.build 算一次存成 @State（id＝workoutsRevision＋今天＋上次用的運動）；
//     body 只畫。
//   • 頁面不盯記錄器：以前 @StateObject tracker 讓跑步時整頁每秒重算（U1 D1、v2 留下的）。現在只有 ⓪ 記錄中條
//     （HealthLiveStrip）自己看 RunTracker；這頁只用 .onReceive(RunTracker.shared.$phase) 記一個 runActive
//     （phase 只在開始、暫停、繼續、結束時才變）。body 裡不讀 RunTracker 任何會每秒變的值。
//   • 彈出頁只有一個 enum HealthSheet＋一個 .sheet(item:)，內容最外層 .appStores()（Mac 上 sheet 拿不到環境物件會閃退）。
//     開始運動 v3 仍是 RunTrackingView（v5 換全螢幕）。提示框分掛在不同的子 view：刪除掛在最近運動、丟掉掛在要確認。
//   • 訂閱（待決定 8）：看得到全部；開始新的一趟、「＋」、編輯、複製到現在、刪除、新增／改健康里程碑要訂閱；
//     不擋：記錄中條「回到跑步」、救回〔存下來〕〔丟掉〕、每週目標、看板主角、Apple 健康開關與同步、點卡片看成果頁。
//   • 右上：綠色「＋」（補記四種有氧、記一次重訓）、「⋯」（每週目標、看板主角、Apple 健康）。跑者小圖示拿掉，
//     開始跑步改由頁面裡的大綠鈕負責。
//   • 人生分頁一開始就有「健康」（MainTabView 的 LifeFeatureGate，待決定 7）。

// MARK: - 彈出頁

/// 健康頁的彈出頁：一個 enum、一個 .sheet(item:)。每次打開帶新的 UUID（坑 #8：先改值再打開會帶到舊值）
private enum HealthSheet: Identifiable {
    /// 開始運動／回到跑步（RunTrackingView）
    case run(UUID)
    /// 補記（session nil、sport 是「＋」選的那一種）或編輯（session 有值）
    case editor(UUID, WorkoutSession?, WorkoutSport?)
    /// 成果頁：第二個 UUID 是那一趟的 id
    case detail(UUID, UUID)
    /// 每週目標小表單
    case goal(UUID)
    /// Apple 健康設定小頁
    case appleHealth(UUID)
    /// 健康里程碑：nil＝新增
    case milestone(UUID, LifeMilestone?)

    var id: UUID {
        switch self {
        case .run(let id): return id
        case .editor(let id, _, _): return id
        case .detail(let id, _): return id
        case .goal(let id): return id
        case .appleHealth(let id): return id
        case .milestone(let id, _): return id
        }
    }
}

/// 最近運動的一列：一趟＋它的卡（page.recent[i] 對 page.recentItems[i]，item.id == session.id）
private struct HealthRecentRow: Identifiable {
    let session: WorkoutSession
    let item: MoneyItem
    var id: UUID { item.id }
}

/// 要確認的一列（救回）：第一列上面不畫分隔線
private struct HealthCheckEntry: Identifiable {
    let checkpoint: RunCheckpoint
    let first: Bool
    var id: UUID { checkpoint.id }
}

// MARK: - 健康頁

struct HealthView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme

    /// [v25.552] 上次跑到一半被關掉、還沒存的那幾趟（App 一打開就 scan；③ 要確認）
    @ObservedObject private var recovery = RunRecoveryCenter.shared
    /// 上次用的運動（開始列的大鈕寫「開始」＋這一種；RunTrackingView 讀同一個鍵）
    @AppStorage(RunSport.lastSportKey) private var lastSport: RunSport = .run
    /// Apple 健康一列的字（設定小頁讀寫同兩個鍵）
    @AppStorage("health_hk_enabled") private var hkEnabled = false
    @AppStorage("health_hk_last_sync") private var lastSyncEpoch: Double = 0

    /// 整頁的字和數字（.task(id:) 算一次；nil＝還沒算好）
    @State private var page: HealthPageData?
    /// 記錄中（含暫停）：只在開始、暫停、繼續、結束時變（不盯每秒的數字）
    @State private var runActive = false
    /// 今天（過了午夜回到前景，看板換新的一天）
    @State private var dayKey = WorkoutFormat.date(Date())
    @State private var sheet: HealthSheet?
    /// 按了「刪除」、等確認的那一趟
    @State private var deleteTarget: WorkoutSession?
    /// 要確認區按了「丟掉」、等確認的那一趟
    @State private var discardTarget: RunCheckpoint?
    @State private var showPremiumAlert = false
    /// [v25.388] 複製到現在之後的短暫提示（新的一筆排到最上面，不講一聲會以為沒反應）
    @State private var copiedNote: String?
    @State private var copiedNoteTask: Task<Void, Never>?

    /// 「＋」選單裡補記的四種有氧（重訓另外一顆）
    private static let logSports: [WorkoutSport] = HealthPageData.cardioSports
    /// 健康里程碑的醫療紅（跟 MilestoneCategory.health 的 cross.fill 同一組，U1 E4）
    private static let medicalRed = Color(tb: 0xD93545)

    private var pal: TripBoardPalette { TripBoardPalette(scheme) }

    /// 運動、健康頁設定、體重一改 workoutsRevision 就加一；跨過午夜、換了上次用的運動也重算
    private var taskKey: String {
        "\(lifeStore.workoutsRevision)-\(dayKey)-\(lastSport.rawValue)"
    }

    // MARK: 主體

    // 修飾器鏈拆兩段（捲動頁一段、彈出頁與生命週期一段），閉包裡只呼叫具名函式：body 一個運算式不要太大（坑 #7）
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                scrollPage(proxy)
            }
            .sheet(item: $sheet) { s in
                sheetView(s).appStores()
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .task(id: taskKey) { rebuild() }
            // [v25.552] 保險：App 一打開已經 scan 過（LifeGoodApp），這裡重複呼叫什麼都不做
            .task { await RunRecoveryCenter.shared.scan() }
            // Published 一訂閱就送目前的值；之後只在開始、暫停、繼續、結束時送
            .onReceive(RunTracker.shared.$phase) { p in phaseChanged(p) }
            .onAppear { refreshDay() }
            .onChange(of: scenePhase) { _, phase in sceneChanged(phase) }
            // 離開頁面時把還在倒數的提示收掉，不要留一個醒著的 Task
            .onDisappear { clearCopiedNote() }
        }
    }

    /// 捲動頁本身：大標「健康」、底色、⓪ 記錄中條、右上兩顆
    private func scrollPage(_ proxy: ScrollViewProxy) -> some View {
        ScrollView {
            pageContent(proxy)
                .padding(.top, 8)
                .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        // ⓪ 記錄中條：沒在記錄時什麼都不畫（高度 0）；回到跑步不擋訂閱、不改上次用的運動
        .safeAreaInset(edge: .top, spacing: 0) {
            HealthLiveStrip { openRun() }
        }
        .navigationTitle("健康")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarContent }
    }

    /// 整頁一次算好（HealthPageData.build 在主執行緒：MoneyItem.workout 用到共用的 formatter）
    private func rebuild() {
        page = HealthPageData.build(workouts: lifeStore.workouts,
                                    prefs: lifeStore.workoutPrefs,
                                    bodyWeightKg: lifeStore.latestBodyWeightKg,
                                    lastSport: lastSport)
    }

    /// 記錄器開始、暫停、繼續、結束：只記「在不在記錄」（一樣就不寫，免得多重畫一次）
    private func phaseChanged(_ p: RunTracker.Phase) {
        let active = p != .idle
        if active != runActive { runActive = active }
    }

    private func sceneChanged(_ phase: ScenePhase) {
        if phase == .active { refreshDay() }
    }

    /// 回到前景、切回這頁：日期變了才改（改了 taskKey 就變，看板重算）
    private func refreshDay() {
        let k = WorkoutFormat.date(Date())
        if k != dayKey { dayKey = k }
    }

    private func clearCopiedNote() {
        copiedNoteTask?.cancel()
        copiedNoteTask = nil
        copiedNote = nil
    }

    @ViewBuilder
    private func pageContent(_ proxy: ScrollViewProxy) -> some View {
        if let p = page {
            sections(p, proxy: proxy)
        } else {
            Color.clear.frame(height: 420)
        }
    }

    /// 由上到下 ①～⑧（⓪ 在 safeAreaInset）
    private func sections(_ p: HealthPageData, proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 20) {
            HealthBoard(data: p, onGoalTap: { openGoal() })
                .padding(.horizontal, 16)
            if !runActive {
                HealthStartRow(data: p.start) { s in start(s) }
                    .padding(.horizontal, 16)
            }
            if !recovery.pending.isEmpty {
                recoverySection
            }
            recentSection(p)
            weeklySection(p)
            if p.hasStrength {
                HealthStrengthSection(scrollToCurve: {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(HealthStrengthSection.curveAnchor, anchor: .top)
                    }
                })
            }
            appleHealthRow
            milestoneSection
        }
    }

    // MARK: 動作（訂閱照待決定 8）

    /// 開始列：大鈕或小膠囊。運動先寫進上次用的那一種（RunTrackingView 一打開就讀這個鍵）；記錄中不改
    private func start(_ s: WorkoutSport) {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        if !RunTracker.shared.isActive, let rs = s.runSport, rs != lastSport {
            lastSport = rs
        }
        sheet = .run(UUID())
    }

    /// 記錄中條「回到跑步」：不擋訂閱（在跑的那一趟一定讓你存完）
    private func openRun() {
        sheet = .run(UUID())
    }

    /// 目標格、「⋯ › 每週目標」：不擋訂閱。page 還沒算好（剛打開那一瞬間）就不開，免得彈出一張空白表單
    private func openGoal() {
        guard page != nil else { return }
        sheet = .goal(UUID())
    }

    private func openAppleHealth() {
        sheet = .appleHealth(UUID())
    }

    /// 「＋」選單：補記一趟／記一次重訓（選單本身沒訂閱時就換成跳付費說明的按鈕）
    private func openEditor(sport: WorkoutSport) {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        sheet = .editor(UUID(), nil, sport)
    }

    /// 長按「編輯」：拿 store 裡最新的那一筆（page 是上一次算的）
    private func edit(_ s: WorkoutSession) {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        let latest = lifeStore.workouts.first(where: { $0.id == s.id }) ?? s
        sheet = .editor(UUID(), latest, nil)
    }

    /// 長按「複製到現在」（只有重訓、手動補記才有）：store 下一輪才寫，這裡先講一聲
    private func duplicate(_ s: WorkoutSession) {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        let saved = WorkoutActions.duplicate(s, store: lifeStore)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showCopiedNote("已複製「" + WorkoutFacts.title(saved) + "」到現在，新的一筆排在最上面。")
    }

    /// 長按「刪除」：先問（確認框在最近運動區）
    private func askDelete(_ s: WorkoutSession) {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        deleteTarget = s
    }

    /// 健康里程碑：新增、改都要訂閱
    private func addMilestone() {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        sheet = .milestone(UUID(), nil)
    }

    private func editMilestone(_ m: LifeMilestone) {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        sheet = .milestone(UUID(), m)
    }

    private func showCopiedNote(_ text: String) {
        copiedNoteTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { copiedNote = text }
        copiedNoteTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { copiedNote = nil }
        }
    }

    // MARK: 右上（綠色「＋」、「⋯」）

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                addButton
                moreMenu
            }
        }
    }

    /// 綠色「＋」：有訂閱是選單；沒訂閱是一顆只跳付費說明的按鈕（照 FinanceAddMenuPill，付費在選單打開前就擋）
    @ViewBuilder
    private var addButton: some View {
        if subscription.isPremium {
            Menu {
                addMenuItems
            } label: {
                addIcon
            }
            .accessibilityLabel("補記一趟運動")
        } else {
            Button {
                showPremiumAlert = true
            } label: {
                addIcon
            }
            .accessibilityLabel("補記一趟運動")
        }
    }

    private var addIcon: some View {
        Image(systemName: "plus.circle.fill")
            .font(.title3)
            .foregroundStyle(.green)
    }

    @ViewBuilder
    private var addMenuItems: some View {
        ForEach(Self.logSports) { s in
            Button {
                openEditor(sport: s)
            } label: {
                Label("補記一趟" + s.displayName, systemImage: s.icon)
            }
        }
        Divider()
        Button {
            openEditor(sport: .strength)
        } label: {
            Label("記一次重訓", systemImage: "dumbbell.fill")
        }
    }

    /// 「⋯」：每週目標、看板主角、Apple 健康（都不擋訂閱）
    private var moreMenu: some View {
        Menu {
            Button {
                openGoal()
            } label: {
                Label("每週目標", systemImage: "target")
            }
            Picker(selection: heroBinding) {
                ForEach(WorkoutHeroChoice.allCases) { c in
                    Text(c.title).tag(c)
                }
            } label: {
                Label("看板主角", systemImage: "star.circle")
            }
            .pickerStyle(.menu)
            Button {
                openAppleHealth()
            } label: {
                Label("Apple 健康", systemImage: "heart.text.square")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
        }
        .accessibilityLabel("更多")
    }

    /// 看板主角（存在 lifeStore.workoutPrefs，跟 iCloud 同步）
    private var heroBinding: Binding<WorkoutHeroChoice> {
        let store = lifeStore
        return Binding(get: { store.workoutPrefs.heroChoice },
                       set: { store.setHeroChoice($0) })
    }

    // MARK: 彈出頁

    @ViewBuilder
    private func sheetView(_ s: HealthSheet) -> some View {
        switch s {
        case .run:
            runSheet
        case .editor(_, let session, let sport):
            editorSheet(session, sport: sport)
        case .detail(_, let sessionId):
            WorkoutDetailView(sessionId: sessionId)
        case .goal:
            goalSheet
        case .appleHealth:
            HealthAppleHealthSheet()
        case .milestone(_, let m):
            milestoneSheet(m)
        }
    }

    /// 開始運動（v3 仍是舊面板）：RunTrackingView 已經關畫面後下一輪才交出那一趟
    private var runSheet: some View {
        let store = lifeStore
        return RunTrackingView { session in
            WorkoutActions.save(session, store: store)
        }
    }

    /// 補記／編輯：WorkoutEditorView 的 onSave 已經在關掉之後下一輪才呼叫
    private func editorSheet(_ session: WorkoutSession?, sport: WorkoutSport?) -> some View {
        let store = lifeStore
        return WorkoutEditorView(session: session, initialSport: sport) { saved in
            WorkoutActions.save(saved, store: store)
        }
    }

    /// 每週目標：運動跟著看板主角；表單自己先關掉、下一輪才交出公里
    @ViewBuilder
    private var goalSheet: some View {
        if let p = page {
            let store = lifeStore
            let suggestion = p.suggestion
            HealthGoalSheet(suggestion: suggestion) { km in
                store.setWeeklyGoal(km, for: suggestion.sport)
            }
        }
    }

    @ViewBuilder
    private func milestoneSheet(_ m: LifeMilestone?) -> some View {
        if let m {
            AddMilestoneView(editing: m)
        } else {
            AddMilestoneView(initialCategory: .health)
        }
    }

    // MARK: ③ 要確認（救回；0 件整區不出現）

    private var checkEntries: [HealthCheckEntry] {
        let shown = recovery.pending.prefix(3)
        var out: [HealthCheckEntry] = []
        for cp in shown {
            out.append(HealthCheckEntry(checkpoint: cp, first: out.isEmpty))
        }
        return out
    }

    /// 多出 3 件以外的：「還有 2 件」
    private var checkMoreText: String? {
        let more = recovery.pending.count - 3
        return more > 0 ? "還有 \(more) 件" : nil
    }

    /// 〔存下來〕〔丟掉〕都不擋訂閱；丟掉先問（提示框掛在這一區）
    private var recoverySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "要確認")
            VStack(spacing: 0) {
                ForEach(checkEntries) { entry in
                    recoveryRow(entry)
                }
                if let more = checkMoreText {
                    Divider().padding(.leading, 14)
                    Text(more)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }
            .modifier(FinanceCardChrome())
        }
        .padding(.horizontal, 16)
        .alert("丟掉這一趟？", isPresented: discardBinding, presenting: discardTarget) { c in
            Button("丟掉", role: .destructive) { RunRecoveryCenter.shared.discard(c) }
            Button("取消", role: .cancel) { }
        } message: { _ in
            Text("丟掉就找不回來了。")
        }
    }

    private func recoveryRow(_ entry: HealthCheckEntry) -> some View {
        let cp = entry.checkpoint
        let message = cp.prompt()
        let store = lifeStore
        let buttons: [FinanceCheckButton] = [
            FinanceCheckButton(title: "存下來") { RunRecoveryCenter.shared.save(cp, store: store) },
            FinanceCheckButton(title: "丟掉") { discardTarget = cp }
        ]
        return VStack(spacing: 0) {
            if !entry.first {
                Divider().padding(.leading, 44)
            }
            FinanceCheckRow(icon: "exclamationmark.arrow.circlepath",
                            message: message,
                            buttons: buttons,
                            accessibilityLabel: "存下來：" + message,
                            pal: pal)
        }
    }

    private var discardBinding: Binding<Bool> {
        Binding(get: { discardTarget != nil }, set: { if !$0 { discardTarget = nil } })
    }

    // MARK: ④ 最近運動

    private func recentRows(_ p: HealthPageData) -> [HealthRecentRow] {
        let n = min(p.recent.count, p.recentItems.count)
        var out: [HealthRecentRow] = []
        for i in 0..<n {
            out.append(HealthRecentRow(session: p.recent[i], item: p.recentItems[i]))
        }
        return out
    }

    private func recentTrailing(_ p: HealthPageData) -> String? {
        p.isEmpty ? nil : "這週 \(p.weekTripCount) 趟"
    }

    /// 刪除確認框掛在這一區（不跟丟掉的提示框掛在同一個 view）
    private func recentSection(_ p: HealthPageData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MoneySectionHeader(title: "最近運動", trailing: recentTrailing(p))
            if let note = copiedNote {
                copiedBanner(note)
            }
            if p.isEmpty {
                emptyCard(p)
            } else {
                VStack(spacing: 10) {
                    ForEach(recentRows(p)) { row in
                        recentCard(row)
                    }
                }
                if p.totalCount > 0 {
                    allRecordsLink(p.totalCount)
                }
            }
        }
        .padding(.horizontal, 16)
        .alert(deleteTitle, isPresented: deleteBinding, presenting: deleteTarget) { s in
            Button("刪除", role: .destructive) { deleteNow(s) }
            Button("取消", role: .cancel) { }
        } message: { s in
            Text(WorkoutActions.deleteMessage(s))
        }
    }

    /// 一趟一張卡：點了打開成果頁（不擋訂閱）；長按編輯／複製到現在／刪除
    private func recentCard(_ row: HealthRecentRow) -> some View {
        let s = row.session
        return Button {
            sheet = .detail(UUID(), s.id)
        } label: {
            MoneyItemCard(item: row.item)
        }
        .buttonStyle(MoneyPressStyle())
        // 長按浮起來的預覽照卡片的圓角（MoneyItemCard 一般版 18），不要露出方角（同全部紀錄頁）
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityHint("點兩下看這一趟的成果；長按可以編輯或刪除")
        .contextMenu {
            recentMenu(s)
        }
    }

    @ViewBuilder
    private func recentMenu(_ s: WorkoutSession) -> some View {
        Button {
            edit(s)
        } label: {
            Label("編輯", systemImage: "pencil")
        }
        if WorkoutActions.canDuplicate(s) {
            Button {
                duplicate(s)
            } label: {
                Label("複製到現在", systemImage: "plus.square.on.square")
            }
        }
        Divider()
        Button(role: .destructive) {
            askDelete(s)
        } label: {
            Label("刪除", systemImage: "trash")
        }
    }

    /// 「看全部紀錄（148 趟）›」：推進全部紀錄頁（依週分組、篩選、緊湊）
    private func allRecordsLink(_ total: Int) -> some View {
        NavigationLink {
            WorkoutListView()
        } label: {
            Text("看全部紀錄（\(total) 趟）›")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(pal.hint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .modifier(FinanceCardChrome())
                .contentShape(Rectangle())
        }
        .buttonStyle(MoneyPressStyle())
    }

    private func copiedBanner(_ note: String) -> some View {
        let green = MoneyTone.good.color(pal)
        return HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(green)
            Text(note)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(green)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(green.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .transition(.opacity)
    }

    /// 空狀態（一筆都沒有；judge §3.5）
    private func emptyCard(_ p: HealthPageData) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "figure.run")
                .font(.title2.weight(.semibold))
                .foregroundStyle(WorkoutPalette.sport(.run, dark: pal.dark))
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("還沒有運動紀錄")
                    .font(.subheadline.weight(.bold))
                Text(emptyText(p))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .modifier(FinanceCardChrome())
        .accessibilityElement(children: .combine)
    }

    private func emptyText(_ p: HealthPageData) -> String {
        let startWord: String = "「開始" + p.start.sport.displayName + "」"
        var text: String
        if ProcessInfo.processInfo.isiOSAppOnMac {
            text = "在 iPhone 上按" + startWord + "記錄"
        } else {
            text = "按上面" + startWord
        }
        text += "；之前跑過的可以按右上「＋」補記，例如河濱 5.2 公里・32 分；"
        text += "有戴 Apple Watch 的話，打開下面的「Apple 健康」，手錶記的會自己出現。"
        return text
    }

    /// 「刪除 10/15 晨跑 5.2 公里？」
    private var deleteTitle: String {
        guard let s = deleteTarget else { return "" }
        return WorkoutActions.deleteTitle(s)
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }

    /// 提示框關掉那一次畫面更新先過，下一輪主執行緒才寫 store（WorkoutActions.delete 已經排到下一輪）
    private func deleteNow(_ s: WorkoutSession) {
        WorkoutActions.delete(s.id, store: lifeStore)
    }

    // MARK: ⑤ 每週公里

    /// 有氧不到 2 週：一行「再記一週，就會出現每週公里」；完全沒有有氧整區不出現
    @ViewBuilder
    private func weeklySection(_ p: HealthPageData) -> some View {
        if let w = p.weekly {
            // MoneyChartCard 自帶 .padding(.horizontal)，外面不要再加
            WorkoutWeeklyCard(series: w)
        } else if let t = p.weeklyPrompt {
            weeklyPromptCard(t)
        }
    }

    private func weeklyPromptCard(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .modifier(FinanceCardChrome())
        .padding(.horizontal, 16)
    }

    // MARK: ⑦ Apple 健康（一列）

    /// 「已連線・今天 06:40 同步」「已連線」「沒有打開」「這台裝置不支援」
    private var appleHealthStatus: String {
        guard HealthKitManager.shared.isAvailable else { return "這台裝置不支援" }
        guard hkEnabled else { return "沒有打開" }
        guard lastSyncEpoch > 0 else { return "已連線" }
        let when = HealthPageData.whenText(Date(timeIntervalSince1970: lastSyncEpoch), now: Date())
        return "已連線・" + when + " 同步"
    }

    /// 白卡一列；點了打開設定小頁（不擋訂閱）
    private var appleHealthRow: some View {
        let status = appleHealthStatus
        return Button {
            openAppleHealth()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "heart.text.square.fill")
                    .font(.title3)
                    .foregroundStyle(.pink)
                Text("Apple 健康")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .modifier(FinanceCardChrome())
            .contentShape(Rectangle())
        }
        .buttonStyle(MoneyPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Apple 健康，" + status)
        .accessibilityHint("點兩下打開 Apple 健康設定")
        .accessibilityAddTraits(.isButton)
        .padding(.horizontal, 16)
    }

    // MARK: ⑧ 健康里程碑

    private var healthMilestones: [LifeMilestone] {
        lifeStore.milestones.filter { $0.category == .health }.sorted { $0.date > $1.date }
    }

    /// 標頭右邊綠色「＋」＋白卡：每列「[cross.fill] 年度健檢　2026/3/2・抽血正常 ›」，最下面一列「＋ 記一筆健康里程碑」
    private var milestoneSection: some View {
        let list = healthMilestones
        let firstId = list.first?.id
        return VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "健康里程碑", addLabel: "記一筆健康里程碑", onAdd: { addMilestone() })
            VStack(spacing: 0) {
                ForEach(list) { m in
                    milestoneRow(m, divider: m.id != firstId)
                }
                if !list.isEmpty {
                    Divider().padding(.leading, 14)
                }
                addMilestoneRow
            }
            .modifier(FinanceCardChrome())
        }
        .padding(.horizontal, 16)
    }

    private func milestoneRow(_ m: LifeMilestone, divider: Bool) -> some View {
        let title = m.title.isEmpty ? "未命名" : m.title
        let meta = milestoneMeta(m)
        return VStack(spacing: 0) {
            if divider {
                Divider().padding(.leading, 52)
            }
            Button {
                editMilestone(m)
            } label: {
                HStack(spacing: 12) {
                    milestoneIcon
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    Text(meta)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title + "，" + meta)
            .accessibilityHint("點兩下修改")
            .accessibilityAddTraits(.isButton)
        }
    }

    /// 醫療紅的圓＋白色十字（跟 MilestoneCategory.health 同一個圖示）
    private var milestoneIcon: some View {
        Image(systemName: "cross.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: 26, height: 26)
            .background(Self.medicalRed, in: Circle())
            .accessibilityHidden(true)
    }

    private var addMilestoneRow: some View {
        Button {
            addMilestone()
        } label: {
            Label("記一筆健康里程碑", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MoneyTone.good.color(pal))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(MoneyPressStyle())
    }

    /// 「2026/3/2・抽血正常」
    private func milestoneMeta(_ m: LifeMilestone) -> String {
        var parts: [String] = [WorkoutFormat.date(m.date)]
        let note = m.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { parts.append(note) }
        return parts.joined(separator: "・")
    }
}

// MARK: - ⑥ 重訓（綜效曲線＋動作統計；有重訓紀錄才出現）

/// 綜效曲線的模式（照舊三段）
private enum HealthCurveMode: String, CaseIterable, Identifiable {
    case volume = "總訓練量"
    case reps = "總次數"
    case exercise = "單一動作"
    var id: String { rawValue }
}

/// 綜效曲線的期間（照舊）
private enum HealthCurveRange: String, CaseIterable, Identifiable {
    case quarter = "近 3 月"
    case halfYear = "近半年"
    case year = "近一年"
    case all = "全部"
    var id: String { rawValue }

    var from: Date? {
        let cal = Calendar.current, now = Date()
        switch self {
        case .quarter: return cal.date(byAdding: .month, value: -3, to: now)
        case .halfYear: return cal.date(byAdding: .month, value: -6, to: now)
        case .year: return cal.date(byAdding: .year, value: -1, to: now)
        case .all: return nil
        }
    }
}

/// 曲線上的一點（id 用序號：同一天兩個動作也不會撞）
private struct HealthCurvePoint: Identifiable {
    let id: Int
    let date: Date
    let value: Double
    let label: String
}

/// 動作統計的一列
private struct HealthExerciseStat: Identifiable {
    let name: String
    let times: Int
    let sets: Int
    let reps: Int
    let volume: Double
    let best: String
    var id: String { name }
}

/// ⑥ 重訓：段落標頭「重訓」＋綜效曲線（MoneyChartCard 主題 65）＋白卡「動作統計」前 5 名。
/// 原本健康頁的曲線、動作統計搬過來（自己的 @State）；綠色換重訓紫。動作統計按一列：曲線換到那個動作、畫面捲到曲線（U1 B10）。
/// [v25.553] 只算重量訓練的動作：有氧（跑、走、騎、登山）在 ⑤ 每週公里，不再混進「重訓」這一區。
/// 統計在 .task(id: workoutsRevision) 算一次存起來（按住曲線拖動時不重算整份統計）。
private struct HealthStrengthSection: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.colorScheme) private var scheme

    /// 動作統計按一列：曲線換好之後捲到曲線（健康頁的 ScrollViewReader）
    let scrollToCurve: () -> Void

    /// 有重訓動作的那幾趟（新到舊）
    @State private var sessions: [WorkoutSession] = []
    @State private var stats: [HealthExerciseStat] = []
    @State private var bodyWeight: Double?
    @State private var loaded = false
    @State private var curveMode: HealthCurveMode = .volume
    @State private var selectedExercise = ""
    @State private var range: HealthCurveRange = .halfYear
    @State private var rawSelectedDate: Date?
    @State private var showAllStats = false

    /// 曲線那張卡的 id（scrollTo 用）
    static let curveAnchor = "health.strength.curve"

    init(scrollToCurve: @escaping () -> Void) {
        self.scrollToCurve = scrollToCurve
    }

    private var pal: TripBoardPalette { TripBoardPalette(scheme) }
    /// 重訓紫（取代原本手寫的綠 Color(0.20, 0.78, 0.45)）
    private var liftColor: Color { WorkoutPalette.sport(.strength, dark: scheme == .dark) }

    var body: some View {
        let points = curvePoints
        return VStack(alignment: .leading, spacing: 10) {
            MoneySectionHeader(title: "重訓")
                .padding(.horizontal, 16)
            // MoneyChartCard 自帶 .padding(.horizontal)
            MoneyChartCard(theme: .workoutStrength, title: "綜效曲線",
                           trailing: loaded ? "\(points.count) 筆" : nil,
                           content: AnyView(curveContent(points)))
                .id(Self.curveAnchor)
            if !stats.isEmpty {
                statsCard
                    .padding(.horizontal, 16)
            }
        }
        .task(id: lifeStore.workoutsRevision) { rebuild() }
    }

    // MARK: 資料

    private func rebuild() {
        let bw = lifeStore.latestBodyWeightKg
        let all = lifeStore.workoutsByDateDesc.filter { !$0.strengthExercises.isEmpty }
        let made = Self.makeStats(all, bodyWeight: bw)
        sessions = all
        bodyWeight = bw
        stats = made
        // 單一動作：沒選過、或選的那個動作已經沒有了 → 次數最多的那一個
        if selectedExercise.isEmpty || !made.contains(where: { $0.name == selectedExercise }) {
            selectedExercise = made.first?.name ?? ""
        }
        loaded = true
    }

    /// 動作統計、單一動作用的名字：只算重量訓練、照動作名稱；沒名字的不列
    private static func statName(_ e: WorkoutExercise) -> String? {
        guard e.kind == .strength else { return nil }
        let n = e.name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? nil : n
    }

    private static func makeStats(_ sessions: [WorkoutSession], bodyWeight: Double?) -> [HealthExerciseStat] {
        var grouped: [String: [WorkoutExercise]] = [:]
        for s in sessions {
            for e in s.exercises {
                if let n = statName(e) { grouped[n, default: []].append(e) }
            }
        }
        var list: [HealthExerciseStat] = []
        for (name, items) in grouped {
            let vol = items.compactMap { $0.volume(bodyWeightKg: bodyWeight) }.reduce(0, +)
            let bestLoad = items.compactMap { $0.loadType == .weight ? $0.loadKg : nil }.max()
            let bestReps = items.map { $0.reps }.max() ?? 0
            var best = ""
            if let bl = bestLoad, bl > 0 {
                best = "最重 " + WorkoutExercise.kgText(bl)
            } else if bestReps > 0 {
                best = "單組最多 \(bestReps) 下"
            }
            let sets = items.reduce(0) { $0 + max(0, $1.sets) }
            let reps = items.reduce(0) { $0 + $1.totalReps }
            list.append(HealthExerciseStat(name: name, times: items.count, sets: sets, reps: reps,
                                           volume: vol, best: best))
        }
        return list.sorted { a, b in
            if a.times != b.times { return a.times > b.times }
            return a.name < b.name
        }
    }

    private var inRange: [WorkoutSession] {
        guard let from = range.from else { return sessions }
        return sessions.filter { $0.date >= from }
    }

    private var curvePoints: [HealthCurvePoint] {
        let asc = inRange.sorted { $0.date < $1.date }
        let bw = bodyWeight
        var out: [HealthCurvePoint] = []
        switch curveMode {
        case .volume:
            for s in asc {
                if let v = s.totalVolume(bodyWeightKg: bw), v > 0 {
                    out.append(HealthCurvePoint(id: out.count, date: s.date, value: v, label: WorkoutFacts.title(s)))
                }
            }
        case .reps:
            for s in asc where s.totalReps > 0 {
                out.append(HealthCurvePoint(id: out.count, date: s.date, value: Double(s.totalReps),
                                            label: WorkoutFacts.title(s)))
            }
        case .exercise:
            guard !selectedExercise.isEmpty else { return [] }
            for s in asc {
                for e in s.exercises where Self.statName(e) == selectedExercise {
                    if let v = e.volume(bodyWeightKg: bw), v > 0 {
                        out.append(HealthCurvePoint(id: out.count, date: s.date, value: v,
                                                    label: e.summary(bodyWeightKg: bw)))
                    } else if e.totalReps > 0 {
                        out.append(HealthCurvePoint(id: out.count, date: s.date, value: Double(e.totalReps),
                                                    label: e.summary(bodyWeightKg: bw)))
                    }
                }
            }
        }
        return out
    }

    /// 最近一次叫這個名字的動作（sessions 是新到舊）
    private func latestExercise(named name: String) -> WorkoutExercise? {
        guard !name.isEmpty else { return nil }
        for s in sessions {
            if let e = s.exercises.first(where: { Self.statName($0) == name }) { return e }
        }
        return nil
    }

    private var curveUnit: String {
        switch curveMode {
        case .volume: return "公斤"
        case .reps: return "下"
        case .exercise:
            guard let e = latestExercise(named: selectedExercise) else { return "" }
            return e.volume(bodyWeightKg: bodyWeight) != nil ? "公斤" : "下"
        }
    }

    private func selectedPoint(_ points: [HealthCurvePoint]) -> HealthCurvePoint? {
        guard let raw = rawSelectedDate else { return nil }
        return points.min { a, b in
            abs(a.date.timeIntervalSince(raw)) < abs(b.date.timeIntervalSince(raw))
        }
    }

    // MARK: 綜效曲線

    private func curveContent(_ points: [HealthCurvePoint]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("模式", selection: $curveMode) {
                ForEach(HealthCurveMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            if curveMode == .exercise {
                exerciseChips
            }
            rangeChips
            curveArea(points)
        }
        .padding(.horizontal, 16)
    }

    private var exerciseChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(stats) { st in
                    FinanceFilterChip(text: st.name, on: selectedExercise == st.name, pal: pal) {
                        animate { selectedExercise = st.name }
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var rangeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(HealthCurveRange.allCases) { r in
                    FinanceFilterChip(text: r.rawValue, on: range == r, pal: pal) {
                        animate { range = r }
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func animate(_ change: () -> Void) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { change() }
    }

    @ViewBuilder
    private func curveArea(_ points: [HealthCurvePoint]) -> some View {
        if !loaded {
            Color.clear.frame(height: 210)
        } else if points.count >= 2 {
            chartBody(points)
                .frame(height: 210)
            Text(curveNote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(emptyCurveText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 30)
        }
    }

    private var emptyCurveText: String {
        if curveMode == .exercise && selectedExercise.isEmpty { return "選一個動作看它的進步曲線" }
        return "這個條件下不足兩筆，換個期間或模式試試"
    }

    private var curveNote: String {
        switch curveMode {
        case .volume:
            if bodyWeight == nil {
                return "訓練量＝總次數 × 負荷。目前健康檔案還沒有體重紀錄，「自身體重」的動作不計入總量——到醫療地圖補一筆體重就會納入。"
            }
            return "訓練量＝總次數 × 負荷；自身體重的動作以健康檔案最近體重 \(WorkoutExercise.kgText(bodyWeight ?? 0)) 計算。"
        case .reps:
            return "只算重量訓練的總次數（每組次數 × 組數），不受負荷影響。"
        case .exercise:
            return "同一個動作的每次表現：有負荷算訓練量、其餘算總次數。"
        }
    }

    private func chartBody(_ points: [HealthCurvePoint]) -> some View {
        let color = liftColor
        let unit = curveUnit
        let sel = selectedPoint(points)
        return Chart {
            ForEach(points) { p in
                AreaMark(x: .value("日期", p.date, unit: .day), y: .value(unit, p.value))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.20), color.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("日期", p.date, unit: .day), y: .value(unit, p.value))
                    .foregroundStyle(color)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                PointMark(x: .value("日期", p.date, unit: .day), y: .value(unit, p.value))
                    .foregroundStyle(color)
                    .symbolSize(26)
            }
            if let s = sel {
                RuleMark(x: .value("選取", s.date, unit: .day))
                    .foregroundStyle(color.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        selectionCard(s)
                    }
                PointMark(x: .value("選取", s.date, unit: .day), y: .value(unit, s.value))
                    .foregroundStyle(color)
                    .symbolSize(80)
            }
        }
        .chartXSelection(value: $rawSelectedDate)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(axisText(v)) }
                }
            }
        }
    }

    private func selectionCard(_ p: HealthCurvePoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(WorkoutFormat.date(p.date))
                .font(.caption2.weight(.bold))
            Text(axisText(p.value) + " " + curveUnit)
                .font(.caption.weight(.bold))
                .foregroundStyle(liftColor)
            Text(p.label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(liftColor.opacity(0.25), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
        .frame(maxWidth: 180)
    }

    // MARK: 動作統計

    /// 白卡：小標「動作統計」、前 5 名（多的「看全部 12 個動作 ›」展開）
    private var statsCard: some View {
        let shown = showAllStats ? stats : Array(stats.prefix(5))
        return VStack(spacing: 0) {
            statsTitle
            ForEach(shown) { st in
                Divider().padding(.leading, 14)
                statRow(st)
            }
            if stats.count > 5 {
                Divider().padding(.leading, 14)
                moreStatsButton
            }
        }
        .modifier(FinanceCardChrome())
    }

    private var statsTitle: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("動作統計")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.primary)
            Spacer(minLength: 8)
            Text("\(stats.count) 個動作")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func statRow(_ st: HealthExerciseStat) -> some View {
        let meta = statMeta(st)
        return Button {
            pick(st.name)
        } label: {
            HStack(spacing: 12) {
                timesBadge(st.times)
                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(st.name)
                        .font(.subheadline.weight(.bold))
                    if !meta.isEmpty {
                        Text(meta)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if st.volume > 0 {
                    Text(Self.volumeText(st.volume))
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(liftColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(MoneyPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statSpoken(st, meta: meta))
        .accessibilityHint("點兩下看這個動作的曲線")
        .accessibilityAddTraits(.isButton)
    }

    private func timesBadge(_ times: Int) -> some View {
        Text("\(times)")
            .font(.system(size: 13, weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(liftColor)
            .frame(width: 34, height: 34)
            .background(liftColor.opacity(0.14), in: Circle())
            .accessibilityHidden(true)
    }

    private var moreStatsText: String {
        showAllStats ? "收起" : "看全部 \(stats.count) 個動作 ›"
    }

    private var moreStatsButton: some View {
        Button {
            animate { showAllStats.toggle() }
        } label: {
            Text(moreStatsText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(pal.hint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 按一列：曲線換到那個動作，再把畫面捲到曲線
    private func pick(_ name: String) {
        animate {
            curveMode = .exercise
            selectedExercise = name
        }
        scrollToCurve()
    }

    // 副標都先在一般函式裡組好字串再交給 Text（ViewBuilder 內串字串容易讓型別檢查逾時，v25.350）
    private func statMeta(_ st: HealthExerciseStat) -> String {
        var parts: [String] = []
        if st.sets > 0 { parts.append("\(st.sets) 組") }
        if st.reps > 0 { parts.append("\(st.reps) 下") }
        if !st.best.isEmpty { parts.append(st.best) }
        return parts.joined(separator: "・")
    }

    private func statSpoken(_ st: HealthExerciseStat, meta: String) -> String {
        var parts: [String] = [st.name, "\(st.times) 次"]
        if !meta.isEmpty { parts.append(meta.replacingOccurrences(of: "・", with: "，")) }
        if st.volume > 0 { parts.append("訓練量 " + Self.volumeText(st.volume)) }
        return parts.joined(separator: "，")
    }

    private static func volumeText(_ v: Double) -> String {
        if v >= 10000 { return String(format: "%.1f 噸", v / 1000) }
        return String(format: "%.0f kg", v)
    }

    private func axisText(_ v: Double) -> String {
        if curveUnit == "公斤" && v >= 10000 { return String(format: "%.1f 噸", v / 1000) }
        return v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }
}

// MARK: - ⑦ Apple 健康設定小頁

/// 健康頁「Apple 健康」那一列打開的小頁：原本健康頁上那張卡的內容（開關、說明、立即同步）＋同步原封搬過來。
/// 開關、同步都不擋訂閱。
private struct HealthAppleHealthSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var health = HealthKitManager.shared
    /// 上次同步時間，決定要往回抓多久（第一次抓 90 天）
    @AppStorage("health_hk_last_sync") private var lastSyncEpoch: Double = 0
    @AppStorage("health_hk_enabled") private var hkEnabled = false
    @State private var syncing = false
    @State private var syncMessage: String?

    init() {}

    var body: some View {
        NavigationStack {
            Form {
                switchSection
                if health.isAvailable && hkEnabled {
                    syncSection
                }
            }
            .navigationTitle("Apple 健康")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var hkBinding: Binding<Bool> {
        Binding(get: { hkEnabled },
                set: { on in
                    hkEnabled = on
                    if on { Task { await health.requestAuthorization(); await syncFromHealthKit() } }
                })
    }

    private var footerText: String {
        if !health.isAvailable { return "這台裝置不支援「健康」App。" }
        if hkEnabled {
            return "體重、血壓、心率與訓練會與 Apple 健康互通。HealthKit 沒有「組數／次數／負荷」的欄位，所以重訓明細只留在這個 App，寫回去的只有時間、距離與熱量。"
        }
        return "打開後可以把 Apple 健康的體重、血壓與 Apple Watch 的訓練帶進來，這裡記的訓練也會寫回去計入體能訓練圓環。"
    }

    private var switchSection: some View {
        Section {
            if health.isAvailable {
                Toggle(isOn: hkBinding) {
                    Label("與 Apple 健康互通", systemImage: "heart.text.square.fill")
                }
                .tint(WorkoutPalette.go)
            } else {
                Label("這台裝置不支援", systemImage: "heart.slash")
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text(footerText)
        }
    }

    private var lastSyncText: String {
        HealthPageData.whenText(Date(timeIntervalSince1970: lastSyncEpoch), now: Date())
    }

    private var syncSection: some View {
        Section {
            Button {
                Task { await syncFromHealthKit() }
            } label: {
                Label(syncing ? "同步中…" : "立即同步", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(syncing)
            if lastSyncEpoch > 0 {
                LabeledContent("上次同步", value: lastSyncText)
            }
            if let msg = syncMessage {
                Text(msg)
                    .font(.footnote)
                    .foregroundStyle(WorkoutPalette.go)
            }
            if let err = health.lastError {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    /// 從 Apple 健康抓體重、血壓與訓練回來（原本在健康頁，原封搬過來；v4 再改同步起點與自動同步）
    private func syncFromHealthKit() async {
        guard hkEnabled, health.isAvailable, !syncing else { return }
        syncing = true
        syncMessage = nil
        defer { syncing = false }

        let since = lastSyncEpoch > 0
            ? Date(timeIntervalSince1970: lastSyncEpoch)
            : Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date.distantPast

        var addedWeights = 0
        var addedVitals = 0
        var addedWorkouts = 0

        var profile = lifeStore.healthProfile
        let cal = Calendar.current

        // 體重：同一天已經有體重紀錄就不重複加
        let weights = await health.fetchBodyMass(since: since)
        for w in weights {
            let hasSameDay = profile.measurements.contains {
                $0.weightKg != nil && cal.isDate($0.date, inSameDayAs: w.date)
            }
            guard !hasSameDay else { continue }
            profile.measurements.append(HealthMeasurement(date: w.date, weightKg: w.kg,
                                                          note: "來自 Apple 健康"))
            addedWeights += 1
        }
        // 血壓／心率：同一分鐘已經有就跳過
        let vitals = await health.fetchVitals(since: since)
        for v in vitals {
            let exists = profile.measurements.contains {
                abs($0.date.timeIntervalSince(v.date)) < 60 && $0.hasBloodPressure
            }
            guard !exists else { continue }
            profile.measurements.append(HealthMeasurement(date: v.date, weightKg: nil,
                                                          systolic: v.systolic, diastolic: v.diastolic,
                                                          heartRate: v.heartRate, note: "來自 Apple 健康"))
            addedVitals += 1
        }
        if profile.heightCm == 0, let h = await health.fetchLatestHeightCm(), h > 0 {
            profile.heightCm = h
        }
        if addedWeights > 0 || addedVitals > 0 || profile.heightCm != lifeStore.healthProfile.heightCm {
            profile.measurements.sort { $0.date > $1.date }
            lifeStore.updateHealthProfile(profile)
        }

        // 訓練：已經匯入過的 UUID 不再重複
        let known = Set(lifeStore.workouts.compactMap(\.healthKitUUID))
        let imported = await health.fetchWorkouts(since: since, excluding: known)
        for w in imported {
            let minutes = w.end.timeIntervalSince(w.start) / 60
            guard minutes >= 1 else { continue }
            let ex = WorkoutExercise(
                name: w.activityName,
                kind: w.isCardio ? .cardio : .strength,
                reps: 0, sets: 0, loadType: .none, loadKg: 0,
                distanceKm: w.distanceKm, durationMinutes: minutes,
                route: w.route, elevationGainM: 0,
                note: w.isCardio ? "" : "來自 Apple 健康，組數次數請自行補上",
                sport: w.sport)                       // [v25.552] 手錶的運動種類（走路＝健走、健行＝登山）
            let session = WorkoutSession(
                date: w.start, title: w.activityName, exercises: [ex],
                durationMinutes: minutes, place: "", note: "",
                healthKitUUID: w.uuid, activeEnergyKcal: w.energyKcal,
                source: .watch)                       // [v25.552] 從 Apple 健康帶進來的
            lifeStore.upsertWorkout(session)
            addedWorkouts += 1
        }

        lastSyncEpoch = Date().timeIntervalSince1970
        syncMessage = syncSummary(weights: addedWeights, vitals: addedVitals, workouts: addedWorkouts)
    }

    private func syncSummary(weights: Int, vitals: Int, workouts: Int) -> String {
        var parts: [String] = []
        if weights > 0 { parts.append("體重 \(weights) 筆") }
        if vitals > 0 { parts.append("血壓 \(vitals) 筆") }
        if workouts > 0 { parts.append("訓練 \(workouts) 筆") }
        return parts.isEmpty ? "已是最新，沒有新資料" : "已帶入 " + parts.joined(separator: "、")
    }
}
