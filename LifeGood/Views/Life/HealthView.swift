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
//     開始運動（RunTrackingView）[v25.555] 起改全螢幕（.fullScreenCover(item:)，見下面 v5 那段）。提示框分掛在不同的子 view：刪除掛在最近運動、丟掉掛在要確認。
//   • 訂閱（待決定 8）：看得到全部；開始新的一趟、「＋」、編輯、複製到現在、刪除、新增／改健康里程碑要訂閱；
//     不擋：記錄中條「回到跑步」、救回〔存下來〕〔丟掉〕、每週目標、看板主角、Apple 健康開關與同步、點卡片看成果頁。
//   • 右上：綠色「＋」（補記四種有氧、記一次重訓）、「⋯」（每週目標、看板主角、Apple 健康）。跑者小圖示拿掉，
//     開始跑步改由頁面裡的大綠鈕負責。
//   • 人生分頁一開始就有「健康」（MainTabView 的 LifeFeatureGate，待決定 7）。
//
// [v25.554] 健康 v4（build/v4/brief.md §G3）：
//   • 打開健康頁、回到前景、關掉彈出頁時自動同步 Apple 健康（HealthSyncCenter.syncIfDue：離上次 15 分鐘以上才同步、不跳權限框）；
//     上面蓋著彈出頁（跑步中、成果頁、設定小頁）時回到前景不同步，關掉彈出頁再看。
//   • .task(id:) 記住上次算的 key（lastBuiltKey，同 WorkoutDetailView）：從全部紀錄返回、切分頁回來不再整頁重算。
//   • ③ 要確認多四種：同一趟〔合成一筆〕〔兩筆都留〕、舊紀錄〔接回來〕（手錶那筆已在 LifeGood 走合成；還沒帶進來的〔先不要〕）、
//     Apple 健康多一項〔去同意〕、寫進去以後又改過〔更新〕。順序：救回→同一趟→接回路線→去同意→更新，最多 3 列。都不擋訂閱。
//   • 刪除確認框照 WorkoutActions.deleteAsk 三種：LifeGood 寫進 Apple 健康的〔連 Apple 健康那筆一起刪〕〔只刪 LifeGood 這筆〕〔取消〕。
//   • ⑦ Apple 健康一列同步中寫「同步中…」；設定小頁的同步搬進 HealthSyncCenter，字改成「會帶進來／會存回去」。
//
// [v25.555] 健康 v5（build/v5/brief.md §G1-6）：
//   • 「開始跑步」「回到跑步」改全螢幕：.fullScreenCover(item: $runCover)（HealthRunCover，每次新的 UUID），往下滑不會收掉；
//     HealthSheet 沒有 .run 了（全檔一個 .sheet(item:)＋一個 .fullScreenCover(item:)，內容最外層都 .appStores()）。
//   • RunTrackingView(onFinish:) 的意思改了：按住結束後它在下一個 runloop 才交出那一趟，這裡同步寫好 store＋排 Apple 健康
//     （WorkoutActions.save），它自己把同一個全螢幕換成成果頁（剛跑完）、不關全螢幕；左上「完成」才關。
//   • 全螢幕關掉時，剛跑完那一趟在「最近運動」那張卡亮 1.6 秒（綠色外框淡出）；看板、卡片在全螢幕開著時 store 一改就會重算。
//   • 全螢幕開著時回到前景不同步 Apple 健康（跑步中解鎖手機不在背後讀寫），關掉時再看一次（同關掉彈出頁）。
//
// [v25.557] 健康 v7（build/v7/brief.md §G3-2～G3-4）：
//   • ⑤ 每週公里下面多「月曆」（HealthCalendarCard：熱圖、打勾／葉子、長按一週請假），再下面「個人紀錄」
//     （HealthRecordsCard，插在每週公里和重訓中間；judge §3.10），點一天／點一列打開那一趟的成果頁（不擋訂閱）。
//   • 「⋯」多兩顆：「這週請假／取消這週請假」「下週請假／取消下週請假」（不擋訂閱；選單收起來那一輪先過，下一輪才寫 store）。
//     看板連續週數照請假算（HealthPageData.build 收 leave）。
//   • 鎖定畫面／靈動島的跑步卡點進來（lifegood://life/health/run → DeepLinkRouter.requestHealthRun）：.onDeepLinkHealthRun 收，
//     在跑 → 跑步全螢幕（回到那一趟；彈出頁開著先收掉，0.45 秒後再開）；剛跑完 20 分鐘內 → 那一趟的成果頁；
//     都不是 → 照「開始」（要訂閱）。在跑、剛跑完都不擋訂閱（待決定 8）。
//
// [v25.558] 健康 v7b（build/v7b/brief.md §6 G3-3～G3-5）：
//   • 看板：膠囊多「[mountain.2.fill] 今年 357.9 公里」、河堤遠景照今年累積公里換（黃昏河濱＋橋、山路＋遠山、海岸＋燈塔）——
//     資料在 HealthPageData.build、畫法在 HealthBoardScenes（這個檔不用改看板）。
//   • ⑧ 健康里程碑：白卡最上面多「還沒記」的運動里程碑最多 3 列（page.milestones 近 90 天、新到舊，畫面上用 WorkoutFacts.isRecorded
//     對 lifeStore.milestones 篩：在成果頁記了，回來這一列馬上不見、出現在下面的健康里程碑）。
//     一列「[flag.checkered 運動色圓] 第一次跑完 10 公里　8/23・還沒記 ›」，點了打開那一趟的成果頁（不擋訂閱；〔記成人生里程碑〕在成果頁、那裡擋）；
//     列跟健康里程碑之間一條分隔線；沒有就跟 v7 一模一樣。
//   • 收 lifegood://life/health?id=<UUID>（「今天（大）」小工具運動那一行；DeepLinkRouter.requestHealthSession）：.onDeepLinkHealthSession，
//     跑步全螢幕開著不動、那一趟已經刪掉停在健康頁、已經在看那一趟不動；彈出頁開著先收掉，0.45 秒後（同 presentRunCover）再開成果頁。
//     不擋訂閱（看成果頁免費）。還是一個 .sheet(item:)＋一個 .fullScreenCover(item:)。
//
// [手錶 v5，v25.582]（watch/build/v5/brief.md G2-1～G2-3；judge §2.12、§5.7 最後一段、§8 v5 做好標準 5、6）：
//   • 手錶跑完送「我跑完了」（WatchBridge 寫 WatchRunFlags）：打開頁面、回到前景、關掉彈出頁、收到 WatchRunFlags.changed
//     （這頁在畫面上、App 在前景、沒蓋著彈出頁）時先叫 HealthSyncCenter.syncForWatchRun（找到那一筆就同步，不等 15 分鐘），
//     再照舊 syncIfDue（剛同步過 lastSync 是新的，它自己不再跑）。
//   • 手錶說有一趟存不進 Apple 健康：最上面一行「手錶上有 1 趟沒存進 Apple 健康，打開手錶上的 LifeGood 再存一次」
//     （HealthWatchUnsavedRow，不能按；WatchRunFlags.hasUnsaved，出現、回前景、旗子一變都重看）。
//   • 「▶ 開始跑步」照 WatchRunStarter.route（sim_v5 §8）：戴著手錶先問（HealthSheet.runChoice → WatchRunChoiceSheet）、
//     記住手錶就直接叫手錶（startOnWatch：HKHealthStore.startWatchApp(toHandle:)，手錶打開準備頁、不自己開跑）、
//     其他照舊開 iPhone 跑步全螢幕。**選手錶那條路不碰 RunTracker、不開 runCover：iPhone 不會多記一筆。**
//     叫的時候開始列下面一行灰字「正在叫醒手錶…」→「已經在手錶上打開準備頁，在手錶上按〔開始〕」；叫不醒跳
//     「沒叫醒手錶（…），可以改用 iPhone 記」〔改用 iPhone 記〕〔好〕（掛在開始列那一區，這一區只有這一個提示框）。
//     選 iPhone、〔改用 iPhone 記〕都記下時間（WatchRunStarter.notePhoneChosen：跑步畫面〔開始〕10 分鐘內不再問、不再叫手錶）。
//   • 開始列大鈕：記住用手錶記時多一個 applewatch（HealthStartRow.watchMark）。
//   • 跑步畫面〔開始〕交給手錶時（RunTrackingView 自己關掉全螢幕）：回到這頁開始列下面那一行講一聲（onWatchStarted）。
//   • 生命週期那幾個修飾器收進 lifecycle(_:)，body 不再加長。還是一個 .sheet(item:)＋一個 .fullScreenCover(item:)。

// MARK: - 彈出頁

/// 健康頁的彈出頁：一個 enum、一個 .sheet(item:)。每次打開帶新的 UUID（坑 #8：先改值再打開會帶到舊值）
private enum HealthSheet: Identifiable {
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
    /// [手錶 v5] 「這一趟用哪個記？」（戴著手錶按「▶ 開始跑步」；要開始的運動）
    case runChoice(UUID, WorkoutSport)

    var id: UUID {
        switch self {
        case .editor(let id, _, _): return id
        case .detail(let id, _): return id
        case .goal(let id): return id
        case .appleHealth(let id): return id
        case .milestone(let id, _): return id
        case .runChoice(let id, _): return id
        }
    }
}

/// [v25.555] 跑步畫面（全螢幕）：每次打開都是新的 id（.fullScreenCover(item:)，同 HealthSheet 每次帶新的 UUID）
private struct HealthRunCover: Identifiable {
    let id = UUID()
}

/// [手錶 v5] 叫不醒手錶（WatchRunStarter.startOnWatch 回的那一句）：提示框〔改用 iPhone 記〕〔好〕
private struct HealthWatchFailure: Identifiable {
    let id = UUID()
    /// 「沒叫醒手錶（…），可以改用 iPhone 記」（WatchRunStarter.failedText 組好的）
    let message: String
}

/// [手錶 v5] 健康頁最上面那一行（judge §2.12）：手錶上有一趟存不進 Apple 健康、留在手錶上。只是說明，不能按；
/// 手錶〔再存一次〕存好（ranWorkout）或 7 天沒消息就不出現（WatchRunFlags.hasUnsaved）
private struct HealthWatchUnsavedRow: View {
    let pal: TripBoardPalette

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    var body: some View {
        let c = pal.notice(.late)
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(c.icon)
                .accessibilityHidden(true)
            Text(WatchRunFlags.unsavedBanner)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(c.text)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(c.fill, in: shape)
        .overlay { shape.stroke(c.stroke, lineWidth: 0.75) }
        .accessibilityElement(children: .combine)
    }
}

/// 最近運動的一列：一趟＋它的卡（page.recent[i] 對 page.recentItems[i]，item.id == session.id）
private struct HealthRecentRow: Identifiable {
    let session: WorkoutSession
    let item: MoneyItem
    var id: UUID { item.id }
}

/// [v25.554] 要確認的五種（build/v4/brief.md §G3-5）
private enum HealthCheckKind {
    /// 上次跑到一半被關掉、還沒存的那一趟：〔存下來〕〔丟掉〕
    case recovery(RunCheckpoint)
    /// 手錶和 App 同一趟〔合成一筆〕〔兩筆都留〕；legacy（舊版記的、手錶那筆已在 LifeGood）〔接回來〕〔兩筆都留〕
    case duplicate(WorkoutDuplicate)
    /// 舊版記的、手錶那筆還沒帶進 LifeGood：〔接回來〕〔先不要〕
    case routeFind(WorkoutRouteFind)
    /// Apple 健康多一項要同意（騎車距離）：〔去同意〕
    case moreAccess
    /// 寫進 Apple 健康以後又改過：〔更新〕
    case stale(WorkoutHealthStale)

    /// ForEach 用（五種各自加前綴，不會撞）
    var key: String {
        switch self {
        case .recovery(let cp): return "recovery-" + cp.id.uuidString
        case .duplicate(let d): return "duplicate-" + d.id
        case .routeFind(let f): return "route-" + f.sessionId.uuidString
        case .moreAccess: return "access"
        case .stale(let st): return "stale-" + st.id.uuidString
        }
    }
}

/// 要確認的一列：第一列上面不畫分隔線
private struct HealthCheckEntry: Identifiable {
    let kind: HealthCheckKind
    let first: Bool
    var id: String { kind.key }
}

/// 要確認一列要畫的東西（圖示、一句話、按鈕）：在函式裡組好，body 只畫
private struct HealthCheckSpec {
    let icon: String
    let message: String
    let buttons: [FinanceCheckButton]
}

// MARK: - 健康頁

struct HealthView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme

    /// [v25.552] 上次跑到一半被關掉、還沒存的那幾趟（App 一打開就 scan；③ 要確認）
    @ObservedObject private var recovery = RunRecoveryCenter.shared
    /// [v25.554] Apple 健康同步（要確認的接回路線、去同意；Apple 健康一列「同步中…」）。
    /// body 只讀它的屬性（不每秒變），不在 body 裡叫它的動作
    @ObservedObject private var sync = HealthSyncCenter.shared
    /// 上次用的運動（開始列的大鈕寫「開始」＋這一種；RunTrackingView 讀同一個鍵）
    @AppStorage(RunSport.lastSportKey) private var lastSport: RunSport = .run
    /// Apple 健康一列的字（設定小頁讀寫同兩個鍵）
    @AppStorage("health_hk_enabled") private var hkEnabled = false
    @AppStorage("health_hk_last_sync") private var lastSyncEpoch: Double = 0

    /// 整頁的字和數字（.task(id:) 算一次；nil＝還沒算好）
    @State private var page: HealthPageData?
    /// [v25.554] 上次算 page 用的 taskKey：畫面重新出現（全部紀錄返回、切分頁回來）.task(id:) 會再跑一次，key 一樣就不重算
    @State private var lastBuiltKey = ""
    /// [v25.554] 這頁在畫面上（回到前景時只有在畫面上才自動同步；推進全部紀錄、切到別的分頁時是 false）
    @State private var onScreen = false
    /// 記錄中（含暫停）：只在開始、暫停、繼續、結束時變（不盯每秒的數字）
    @State private var runActive = false
    /// 今天（過了午夜回到前景，看板換新的一天）
    @State private var dayKey = WorkoutFormat.date(Date())
    @State private var sheet: HealthSheet?
    /// [v25.555] 跑步畫面（全螢幕；開始跑步、回到跑步）
    @State private var runCover: HealthRunCover?
    /// [v25.555] 全螢幕開著時跑完存好的那一趟（關掉全螢幕時那張卡亮一下）
    @State private var finishedRunId: UUID?
    /// [v25.555] 正在亮的那張卡（最近運動；1.6 秒後淡掉）
    @State private var flashId: UUID?
    @State private var flashTask: Task<Void, Never>?
    /// [v25.554] 按了「刪除」、等確認的那一趟（字和三種按鈕先算好：WorkoutActions.deleteAsk）
    @State private var deleteAsk: WorkoutDeleteAsk?
    /// 要確認區按了「丟掉」、等確認的那一趟
    @State private var discardTarget: RunCheckpoint?
    @State private var showPremiumAlert = false
    /// [v25.388] 複製到現在之後的短暫提示（新的一筆排到最上面，不講一聲會以為沒反應）
    @State private var copiedNote: String?
    @State private var copiedNoteTask: Task<Void, Never>?
    /// [手錶 v5] 最上面「手錶上有 1 趟沒存進 Apple 健康…」那一行（WatchRunFlags.hasUnsaved；出現、回前景、旗子一變才重看）
    @State private var watchUnsaved = false
    /// [手錶 v5] 開始列下面那一行灰字（「正在叫醒手錶…」「已經在手錶上打開準備頁…」）；nil＝不顯示
    @State private var watchNote: String?
    @State private var watchNoteTask: Task<Void, Never>?
    /// [手錶 v5] 正在叫手錶（再按一次不再叫）
    @State private var watchStarting = false
    /// [手錶 v5] 叫不醒手錶：「沒叫醒手錶（…），可以改用 iPhone 記」〔改用 iPhone 記〕〔好〕
    @State private var watchFailure: HealthWatchFailure?

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

    // 修飾器鏈拆三段（捲動頁一段、彈出頁一段、生命週期一段），閉包裡只呼叫具名函式：body 一個運算式不要太大（坑 #7）
    var body: some View {
        NavigationStack {
            lifecycle(presentedPage)
        }
    }

    /// 捲動頁＋彈出頁（一個 .sheet(item:)＋一個 .fullScreenCover(item:)）＋整頁重算、打開頁面
    private var presentedPage: some View {
        ScrollViewReader { proxy in
            scrollPage(proxy)
        }
        // [v25.554] 彈出頁關掉、回到這頁：Apple 健康 15 分鐘沒同步就同步（開著彈出頁時回到前景不同步，見 sceneChanged）
        .sheet(item: $sheet, onDismiss: { sheetDismissed() }) { s in
            sheetView(s).appStores()
        }
        // [v25.555] 跑步畫面全螢幕（往下滑不會收掉）；關掉時剛跑完那張卡亮一下、看要不要同步 Apple 健康
        .fullScreenCover(item: $runCover, onDismiss: { runCoverDismissed() }) { _ in
            runScreen.appStores()
        }
        .premiumLockAlert(isPresented: $showPremiumAlert)
        .task(id: taskKey) { rebuild() }
        // 打開頁面（每次出現）：救回 scan＋[手錶 v5] 手錶跑完那一筆＋Apple 健康 15 分鐘沒同步就同步
        .task { await pageOpened() }
    }

    /// [手錶 v5] 生命週期那幾個收在這裡（body 不再加長）
    private func lifecycle<V: View>(_ v: V) -> some View {
        v
            // Published 一訂閱就送目前的值；之後只在開始、暫停、繼續、結束時送
            .onReceive(RunTracker.shared.$phase) { p in phaseChanged(p) }
            // [v25.557] 鎖定畫面／靈動島的跑步卡點進來（冷啟動 onAppear、已經在這頁 onChange 都收）
            .onDeepLinkHealthRun { openRunFromLink() }
            // [健康 v7b] 「今天（大）」小工具運動那一行點進來（lifegood://life/health?id=…）：打開那一趟的成果頁
            .onDeepLinkHealthSession { openSessionFromLink() }
            // [手錶 v5] 手錶送來「我跑完了」「沒存成」（WatchBridge 寫好旗子、主執行緒發）
            .onReceive(NotificationCenter.default.publisher(for: WatchRunFlags.changed)) { _ in watchFlagsChanged() }
            .onAppear { pageAppeared() }
            .onChange(of: scenePhase) { _, phase in sceneChanged(phase) }
            // 離開頁面時把還在倒數的提示收掉，不要留一個醒著的 Task
            .onDisappear { pageDisappeared() }
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

    /// 整頁一次算好（HealthPageData.build 在主執行緒：MoneyItem.workout 用到共用的 formatter）。
    /// [v25.554] key 跟上次算的一樣（畫面重新出現）就不重算；ledger 一改 workoutsRevision 就加一，key 跟著變
    private func rebuild() {
        let key = taskKey
        guard page == nil || key != lastBuiltKey else { return }
        page = HealthPageData.build(workouts: lifeStore.workouts,
                                    prefs: lifeStore.workoutPrefs,
                                    bodyWeightKg: lifeStore.latestBodyWeightKg,
                                    lastSport: lastSport,
                                    ledger: lifeStore.workoutHealthLedger,
                                    leave: lifeStore.workoutLeave)      // [v25.557] 請假：改了 workoutsRevision 會加一
        lastBuiltKey = key
    }

    /// [v25.552] 救回：App 一打開已經 scan 過（LifeGoodApp），這裡重複呼叫什麼都不做。
    /// [v25.554] 接著 Apple 健康：開著、離上次同步 15 分鐘以上才同步（syncIfDue 自己判斷；不跳權限框）
    /// [手錶 v5] syncIfDue 之前先 syncForWatchRun：手錶說「我跑完了」（24 小時內）就不等 15 分鐘，找到那一筆就同步
    private func pageOpened() async {
        await RunRecoveryCenter.shared.scan()
        await HealthSyncCenter.shared.syncForWatchRun(store: lifeStore)
        await HealthSyncCenter.shared.syncIfDue(store: lifeStore)
    }

    private func pageAppeared() {
        onScreen = true
        refreshDay()
        refreshWatchUnsaved()
    }

    private func pageDisappeared() {
        onScreen = false
        clearCopiedNote()
        clearFlash()
        clearWatchNote()
    }

    /// 記錄器開始、暫停、繼續、結束：只記「在不在記錄」（一樣就不寫，免得多重畫一次）
    private func phaseChanged(_ p: RunTracker.Phase) {
        let active = p != .idle
        if active != runActive { runActive = active }
    }

    /// 回到前景：日期變了換新的一天；[v25.554] 這頁在畫面上就看要不要同步 Apple 健康（15 分鐘一次）。
    /// 上面蓋著彈出頁時不同步（跑步中解鎖手機不在背後讀寫 Apple 健康、不重算整頁；設定小頁正在跳權限框也不搶），
    /// 關掉彈出頁時再看一次（sheetDismissed）。[v25.555] 跑步全螢幕開著時也一樣不同步（關掉時 runCoverDismissed 再看）
    private func sceneChanged(_ phase: ScenePhase) {
        guard phase == .active else { return }
        refreshDay()
        refreshWatchUnsaved()
        guard onScreen, sheet == nil, runCover == nil else { return }
        autoSync()
    }

    /// [手錶 v5] 手錶送來「我跑完了」「沒存成」（WatchRunFlags.changed）：最上面那一行跟著變；
    /// 這頁在畫面上、App 在前景、沒蓋著彈出頁／全螢幕就馬上看要不要同步（同回到前景）。
    /// 背景被手錶叫醒時不讀 Apple 健康（鎖著讀不到），回到前景 sceneChanged 再看
    private func watchFlagsChanged() {
        refreshWatchUnsaved()
        guard scenePhase == .active, onScreen, sheet == nil, runCover == nil else { return }
        autoSync()
    }

    /// [手錶 v5] 「手錶上有 1 趟沒存進 Apple 健康…」要不要出現（一樣就不寫，免得多重畫一次）
    private func refreshWatchUnsaved() {
        let on = WatchRunFlags.hasUnsaved(now: Date())
        if on != watchUnsaved { watchUnsaved = on }
    }

    /// [v25.554] 彈出頁關掉（成果頁、設定小頁、跑完…）：這頁還在畫面上就看要不要同步（syncIfDue 自己判斷 15 分鐘、正在同步就不動）
    private func sheetDismissed() {
        guard onScreen else { return }
        autoSync()
    }

    /// [v25.555] 跑步全螢幕關掉（收起、關閉、成果頁「完成」）：剛跑完那一趟的卡亮一下，再照關掉彈出頁看要不要同步
    private func runCoverDismissed() {
        if let id = finishedRunId {
            finishedRunId = nil
            flash(id)
        }
        sheetDismissed()
    }

    /// [v25.555] 全螢幕裡跑完、store 已經寫好那一趟（RunTrackingView 已經在下一個 runloop 才叫 onFinish）：只記 id，關掉全螢幕時亮。
    /// 萬一全螢幕已經關了（runCover 是 nil）才交出來，就直接亮，不留一個舊 id 等到下一次關全螢幕才亮錯
    private func justFinished(_ id: UUID) {
        if runCover == nil {
            flash(id)
        } else {
            finishedRunId = id
        }
    }

    /// [v25.555] 最近運動那張卡亮 1.6 秒（綠色外框）再淡掉；看板、卡片已經重算好（workoutsRevision 變了 .task(id:) 照樣跑）
    private func flash(_ id: UUID) {
        flashTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { flashId = id }
        flashTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.6)) { flashId = nil }
        }
    }

    private func clearFlash() {
        flashTask?.cancel()
        flashTask = nil
        flashId = nil
    }

    /// 排到下一輪主執行緒才同步（不跟關彈出頁、回到前景那一次畫面更新搶同一輪；syncIfDue 的 store 寫入都在 await 之後）。
    /// [手錶 v5] 先 syncForWatchRun（手錶說跑完了：找到那一筆就同步、不等 15 分鐘），同步過的話 syncIfDue 自己不再跑
    private func autoSync() {
        let store = lifeStore
        Task {
            await HealthSyncCenter.shared.syncForWatchRun(store: store)
            await HealthSyncCenter.shared.syncIfDue(store: store)
        }
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
        let checks = checkKinds(p)
        return VStack(spacing: 20) {
            // [手錶 v5] 最上面那一行跟看板包一個 Group（VStack 直接的子 view 維持 10 個以內；Group 裡的照樣各自排、間距不變）
            Group {
                if watchUnsaved {
                    HealthWatchUnsavedRow(pal: pal)             // [手錶 v5] 手錶上有一趟沒存進 Apple 健康
                        .padding(.horizontal, 16)
                }
                HealthBoard(data: p, onGoalTap: { openGoal() })
                    .padding(.horizontal, 16)
            }
            if !runActive {
                startSection(p)
            }
            if !checks.isEmpty {
                checkSection(checks)
            }
            recentSection(p)
            weeklySection(p)
            // [v25.557] 月曆（每週公里下面）、個人紀錄（插在每週公里和重訓中間）
            if !p.isEmpty {
                calendarSection
            }
            if !p.records.isEmpty {
                recordsSection(p)
            }
            if p.hasStrength {
                HealthStrengthSection(scrollToCurve: {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(HealthStrengthSection.curveAnchor, anchor: .top)
                    }
                })
            }
            appleHealthRow
            milestoneSection(p)
        }
    }

    // MARK: 動作（訂閱照待決定 8）

    /// 開始列：大鈕或小膠囊。運動先寫進上次用的那一種（RunTrackingView 一打開就讀這個鍵）；記錄中不改。
    /// [手錶 v5] 接著照 WatchRunStarter.route（sim_v5 §8）：戴著手錶先問、記住手錶直接叫手錶、其他照舊開 iPhone 跑步全螢幕
    /// （沒手錶、iPad、Mac、重訓、其他有氧、記住 iPhone 都是 .phone，跟以前一模一樣）
    private func start(_ s: WorkoutSport) {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        if !RunTracker.shared.isActive, let rs = s.runSport, rs != lastSport {
            lastSport = rs
        }
        switch WatchRunStarter.route(sport: s, now: Date(), fromRunScreen: false) {
        case .ask: sheet = .runChoice(UUID(), s)
        case .watch: startOnWatch(s)
        case .phone: runCover = HealthRunCover()
        }
    }

    // MARK: [手錶 v5] 用手錶記／用 iPhone 記

    /// 開始列大鈕標 applewatch：戴著手錶、記住「用手錶記」
    private var startWatchMark: Bool {
        WatchRunStarter.watchReady && WatchRunStarter.choice == .watch
    }

    /// 「這一趟用哪個記？」選了（WatchRunChoiceSheet 已經先收起來、下一個 runloop 才叫這裡）：
    /// 勾了記住就存（只這支 iPhone）；手錶 → 叫手錶；iPhone → 記下時間（跑步畫面〔開始〕不再問）、開跑步全螢幕
    private func choicePicked(_ c: WatchRunStarter.Choice, remember: Bool, sport: WorkoutSport) {
        if remember { WatchRunStarter.setChoice(c) }
        switch c {
        case .watch:
            startOnWatch(sport)
        case .phone, .ask:
            WatchRunStarter.notePhoneChosen(now: Date())
            presentRunCoverAfterChoice()
        }
    }

    /// 選了 iPhone：那一頁 dismiss() 時 sheet 已經回到 nil、收的動畫還在跑——跟 presentRunCover 一樣等 0.45 秒再開全螢幕
    /// （同一個 view 上 sheet 還在收時開 fullScreenCover 會開不起來）
    private func presentRunCoverAfterChoice() {
        guard sheet == nil else {
            presentRunCover()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            reopenRunCoverAfterSheet()
        }
    }

    /// 用手錶記：叫醒手錶 LifeGood 打開準備頁（WatchRunStarter.startOnWatch → HKHealthStore.startWatchApp(toHandle:)；
    /// 手錶不自己開跑）。**iPhone 這邊不碰 RunTracker、不開 runCover：不會多記一筆。**
    /// 正在叫的時候再按不再叫一次。成功：開始列下面「已經在手錶上打開準備頁…」；叫不醒：提示框〔改用 iPhone 記〕〔好〕
    private func startOnWatch(_ s: WorkoutSport) {
        guard !watchStarting else { return }
        watchStarting = true
        showWatchNote(WatchRunStarter.startingText, hideAfter: nil)
        let began = Date()
        Task { @MainActor in
            let failure = await WatchRunStarter.startOnWatch(sport: s)
            watchStarting = false
            guard let failure else {
                showWatchNote(WatchRunStarter.startedMessage(syncOn: HealthSyncCenter.shared.isEnabled),
                              hideAfter: watchNoteSeconds)
                return
            }
            await Self.settle(since: began)
            clearWatchNote()
            guard runCover == nil else { return }               // 等的時候改用 iPhone 開了跑步畫面：不再跳
            guard sheet == nil else {                           // 等的時候又開了別的彈出頁：提示框跳不出來，改寫在開始列下面
                showWatchNote(failure, hideAfter: 6)
                return
            }
            watchFailure = HealthWatchFailure(message: failure)
        }
    }

    /// 剛收掉「用哪個記」那一頁就失敗（手錶不在身邊時很快就回來）：等收的動畫跑完（同 presentRunCover 的 0.45 秒）再跳提示框
    private static func settle(since began: Date) async {
        let wait = min(0.5, 0.5 - Date().timeIntervalSince(began))
        guard wait > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
    }

    /// 成功那一句留多久（Apple 健康同步沒開那一句比較長，多留一下）
    private var watchNoteSeconds: Double {
        HealthSyncCenter.shared.isEnabled ? 3.5 : 6
    }

    /// 跑步畫面〔開始〕交給手錶了（RunTrackingView 自己關掉全螢幕、iPhone 什麼都沒記）：開始列下面那一行講一聲
    private func watchStartedFromRunScreen() {
        showWatchNote(WatchRunStarter.startedMessage(syncOn: HealthSyncCenter.shared.isEnabled),
                      hideAfter: watchNoteSeconds)
    }

    /// 開始列下面那一行灰字（hideAfter nil＝一直留著，等叫手錶的結果）；VoiceOver 唸出來
    private func showWatchNote(_ text: String, hideAfter seconds: Double?) {
        watchNoteTask?.cancel()
        watchNoteTask = nil
        withAnimation(.easeOut(duration: 0.2)) { watchNote = text }
        UIAccessibility.post(notification: .announcement, argument: text)
        guard let seconds else { return }
        let nanos = UInt64(min(max(seconds, 0), 30) * 1_000_000_000)
        watchNoteTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { watchNote = nil }
        }
    }

    private func clearWatchNote() {
        watchNoteTask?.cancel()
        watchNoteTask = nil
        watchNote = nil
    }

    /// 〔改用 iPhone 記〕：記下剛選了 iPhone（跑步畫面〔開始〕10 分鐘內不再問、不再叫手錶）；
    /// 提示框收掉那一下先過，再開跑步全螢幕（訂閱、上次用的運動在 start 已經擋過、寫好）
    private func usePhoneAfterWatchFailed() {
        WatchRunStarter.notePhoneChosen(now: Date())
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            reopenRunCoverAfterSheet()
        }
    }

    private var watchFailureBinding: Binding<Bool> {
        Binding(get: { watchFailure != nil }, set: { if !$0 { watchFailure = nil } })
    }

    /// 「沒叫醒手錶（…），可以改用 iPhone 記」
    private var watchFailureTitle: String {
        watchFailure?.message ?? ""
    }

    @ViewBuilder
    private var watchFailureButtons: some View {
        Button(WatchRunStarter.usePhoneTitle) { usePhoneAfterWatchFailed() }
        Button(WatchRunStarter.okTitle, role: .cancel) { }
    }

    /// ② 開始列＋叫手錶那一行灰字。「沒叫醒手錶…」提示框掛在這一區（這一區只有這一個提示框；刪除掛在最近運動、丟掉掛在要確認）
    private func startSection(_ p: HealthPageData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HealthStartRow(data: p.start, watchMark: startWatchMark) { s in start(s) }
            if let note = watchNote {
                watchNoteLine(note)
            }
        }
        .padding(.horizontal, 16)
        .alert(watchFailureTitle, isPresented: watchFailureBinding, presenting: watchFailure) { _ in
            watchFailureButtons
        }
    }

    /// 「正在叫醒手錶…」「已經在手錶上打開準備頁，在手錶上按〔開始〕」：灰字、手錶圖示（不能按）
    private func watchNoteLine(_ note: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "applewatch")
                .font(.footnote.weight(.semibold))
                .accessibilityHidden(true)
            Text(note)
                .font(.footnote.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .transition(.opacity)
    }

    /// 記錄中條「回到跑步」：不擋訂閱（在跑的那一趟一定讓你存完）。[v25.555] 全螢幕
    private func openRun() {
        runCover = HealthRunCover()
    }

    /// [v25.557] 鎖定畫面／靈動島的跑步卡點進來（lifegood://life/health/run；DeepLinkRouter 已經切到人生 › 健康）。
    /// 在跑 → 跑步全螢幕（回到那一趟；已經開著就不動）；沒在跑、全螢幕開著（剛跑完的成果頁）→ 不動；
    /// 剛跑完 20 分鐘內（鎖定畫面「完成」那張留 15 分鐘）→ 那一趟的成果頁；有一趟沒存（App 跑到一半被關掉）→ 留在健康頁（③ 要確認）；
    /// 都不是 → 照「開始」（要訂閱，同開始列）。在跑、剛跑完都不擋訂閱（待決定 8）
    private func openRunFromLink() {
        guard DeepLinkRouter.shared.takeHealthRun() else { return }
        guard runCover == nil else { return }
        if RunTracker.shared.isActive {
            presentRunCover()
            return
        }
        if let id = recentAppRunId(now: Date()) {
            if case .detail(_, let shown)? = sheet, shown == id { return }   // 已經在看那一趟
            sheet = .detail(UUID(), id)
            return
        }
        // 跑到一半 App 被關掉、點了還留著的那張卡：有一趟還沒存（③ 要確認「存下來／丟掉」）就留在健康頁，
        // 不蓋一個開始畫面在它上面（在跑的那一趟一定讓你存完；救回 scan 還沒跑完時照下面開開始畫面）
        if !recovery.pending.isEmpty { return }
        guard subscription.isPremium else { showPremiumAlert = true; return }
        presentRunCover()
    }

    /// [v25.557] 打開跑步全螢幕；上面開著彈出頁（成果頁、設定小頁…）先收掉，0.45 秒後（收的動畫跑完）再開
    /// （同一個 view 上 sheet 還在時開 fullScreenCover 會開不起來）
    private func presentRunCover() {
        guard sheet != nil else {
            runCover = HealthRunCover()
            return
        }
        sheet = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            reopenRunCoverAfterSheet()
        }
    }

    /// [v25.557] 彈出頁收掉之後：那 0.45 秒裡又開了別的（或全螢幕已經開了）就不動
    private func reopenRunCoverAfterSheet() {
        guard runCover == nil, sheet == nil else { return }
        runCover = HealthRunCover()
    }

    /// [v25.557] 剛跑完（App 記的、endedAt 在 20 分鐘內）的那一趟；有好幾趟拿最晚結束的
    private func recentAppRunId(now: Date) -> UUID? {
        let window: TimeInterval = 20 * 60
        var best: (id: UUID, end: Date)?
        for s in lifeStore.workouts {
            guard let end = s.endedAt, WorkoutFacts.source(of: s) == .app else { continue }
            let ago = now.timeIntervalSince(end)
            guard ago >= -60, ago <= window else { continue }
            if let b = best, b.end >= end { continue }
            best = (id: s.id, end: end)
        }
        return best?.id
    }

    /// [v25.557] 月曆點一天、個人紀錄點一列：打開那一趟的成果頁（不擋訂閱，同點卡片）
    /// [健康 v7b] ⑧ 上面「還沒記」的運動里程碑點一列也走這裡
    private func openDetail(_ id: UUID) {
        sheet = .detail(UUID(), id)
    }

    /// [健康 v7b] 「今天（大）」小工具運動那一行點進來（lifegood://life/health?id=…；DeepLinkRouter 已經切到人生 › 健康）：
    /// 打開那一趟的成果頁（不擋訂閱）。跑步全螢幕開著 → 不動（在跑、剛跑完的成果頁都在全螢幕裡，不蓋掉）；
    /// 那一趟已經刪掉（或還沒同步到這台）→ 停在健康頁；已經在看那一趟 → 不動；
    /// 彈出頁開著別的（成果頁、設定小頁…）→ 先收掉，0.45 秒後（收的動畫跑完，同 presentRunCover）再開
    private func openSessionFromLink() {
        guard let id = DeepLinkRouter.shared.takeHealthSession() else { return }
        guard runCover == nil else { return }
        guard lifeStore.workouts.contains(where: { $0.id == id }) else { return }
        if case .detail(_, let shown)? = sheet, shown == id { return }
        guard sheet != nil else {
            sheet = .detail(UUID(), id)
            return
        }
        sheet = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            reopenDetailAfterSheet(id)
        }
    }

    /// [健康 v7b] 彈出頁收掉之後才開那一趟的成果頁：那 0.45 秒裡又開了別的（或跑步全螢幕開了）就不動
    private func reopenDetailAfterSheet(_ id: UUID) {
        guard sheet == nil, runCover == nil else { return }
        sheet = .detail(UUID(), id)
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

    /// 長按「刪除」：先問（確認框在最近運動區）。[v25.554] 拿 store 裡最新的那一筆算要問哪一種（page 是上一次算的）
    private func askDelete(_ s: WorkoutSession) {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        let latest = lifeStore.workouts.first(where: { $0.id == s.id }) ?? s
        deleteAsk = WorkoutActions.deleteAsk(latest)
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

    /// 綠圓白「＋」（樣稿①：深色也是白色的＋；綠用開始鈕、標頭小「＋」同一個 1F9D57，不用系統綠）
    private var addIcon: some View {
        Image(systemName: "plus.circle.fill")
            .font(.title3)
            .symbolRenderingMode(.palette)
            .foregroundStyle(Color.white, WorkoutPalette.go)
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
            leaveMenuItems
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
        }
        .accessibilityLabel("更多")
    }

    /// [v25.557] 「⋯」的請假兩顆（page 還沒算好不出現）：這週請假／取消這週請假、下週請假／取消下週請假
    @ViewBuilder
    private var leaveMenuItems: some View {
        if let p = page {
            Divider()
            Button {
                setLeave(!p.thisWeekLeave, nextWeek: false)
            } label: {
                Label(p.thisWeekLeave ? "取消這週請假" : "這週請假", systemImage: "leaf")
            }
            Button {
                setLeave(!p.nextWeekLeave, nextWeek: true)
            } label: {
                Label(p.nextWeekLeave ? "取消下週請假" : "下週請假", systemImage: "leaf")
            }
        }
    }

    /// [v25.557] 「⋯」請假：不擋訂閱（把資料弄對，不是新增內容）。選單收起來那一次畫面更新先過，下一輪主執行緒才寫 store
    private func setLeave(_ on: Bool, nextWeek: Bool) {
        let store = lifeStore
        let now = Date()
        let day = nextWeek ? HealthPageData.nextWeekDay(now) : now
        DispatchQueue.main.async { store.setLeave(on, weekOf: day) }
    }

    /// 看板主角（存在 lifeStore.workoutPrefs，跟 iCloud 同步）。
    /// 選單收起來那一次畫面更新先過，下一輪主執行緒才寫 store（寫了整頁會重算，不跟收選單搶同一輪）
    private var heroBinding: Binding<WorkoutHeroChoice> {
        let store = lifeStore
        return Binding(get: { store.workoutPrefs.heroChoice },
                       set: { choice in
                           DispatchQueue.main.async { store.setHeroChoice(choice) }
                       })
    }

    // MARK: 彈出頁

    @ViewBuilder
    private func sheetView(_ s: HealthSheet) -> some View {
        switch s {
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
        case .runChoice(_, let sport):
            runChoiceSheet(sport)
        }
    }

    /// [手錶 v5] 「這一趟用哪個記？」（半頁）：WatchRunChoiceSheet 已經先收起來、下一個 runloop 才交出選的
    private func runChoiceSheet(_ sport: WorkoutSport) -> some View {
        WatchRunChoiceSheet(sport: sport) { c, remember in
            choicePicked(c, remember: remember, sport: sport)
        }
    }

    /// [v25.555] 跑步畫面（全螢幕的內容）：按住結束後 RunTrackingView 在下一個 runloop 才交出那一趟，
    /// 這裡同步寫好 store＋排 Apple 健康（WorkoutActions.save）；它接著把同一個全螢幕換成成果頁（剛跑完），不關全螢幕
    /// [手錶 v5] 跑步畫面〔開始〕交給手錶時（它自己關掉全螢幕）：onWatchStarted 在開始列下面講一聲
    private var runScreen: some View {
        let store = lifeStore
        return RunTrackingView(onFinish: { session in
            WorkoutActions.save(session, store: store)
            justFinished(session.id)
        }, onWatchStarted: {
            watchStartedFromRunScreen()
        })
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

    // MARK: ③ 要確認（0 件整區不出現；最多 3 列，多的「還有 N 件」）

    /// Apple 健康開著、裝置支援（〔去同意〕〔更新〕只在這時候出現：關著按了也寫不進 Apple 健康）
    private var healthLinked: Bool {
        hkEnabled && HealthKitManager.shared.isAvailable
    }

    /// 全部要確認的（還沒截 3 列）。順序：救回 → 同一趟 → 接回路線 → 去同意 → 更新（build/v4/brief.md §G3-5）。
    /// 接回路線：同一趟裡 legacy 的（手錶那筆已在 LifeGood，走合成）在前，再來 sync.routeFinds（手錶那筆還沒帶進來）；
    /// 同一趟已經有那一趟的就不再列 routeFind
    private func checkKinds(_ p: HealthPageData) -> [HealthCheckKind] {
        var out: [HealthCheckKind] = []
        for cp in recovery.pending {
            out.append(.recovery(cp))
        }
        for d in p.duplicates where !d.legacy {
            out.append(.duplicate(d))
        }
        for d in p.duplicates where d.legacy {
            out.append(.duplicate(d))
        }
        let pairedApps = Set(p.duplicates.map { $0.appId })
        for f in sync.routeFinds where !pairedApps.contains(f.sessionId) {
            out.append(.routeFind(f))
        }
        if healthLinked && sync.needsMoreAccess {
            out.append(.moreAccess)
        }
        if healthLinked {
            for st in p.staleWrites {
                out.append(.stale(st))
            }
        }
        return out
    }

    /// 前 3 件（第一列上面不畫線）
    private func checkEntries(_ kinds: [HealthCheckKind]) -> [HealthCheckEntry] {
        var out: [HealthCheckEntry] = []
        for k in kinds.prefix(3) {
            out.append(HealthCheckEntry(kind: k, first: out.isEmpty))
        }
        return out
    }

    /// 多出 3 件以外的：「還有 2 件」
    private func checkMoreText(_ count: Int) -> String? {
        let more = count - 3
        return more > 0 ? "還有 \(more) 件" : nil
    }

    /// 都不擋訂閱（把資料弄對，不是新增內容）；丟掉先問（提示框掛在這一區，這一區只有這一個提示框）
    private func checkSection(_ kinds: [HealthCheckKind]) -> some View {
        let entries = checkEntries(kinds)
        let moreText = checkMoreText(kinds.count)
        return VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "要確認")
            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    checkRow(entry)
                }
                if let more = moreText {
                    checkMoreRow(more)
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

    @ViewBuilder
    private func checkMoreRow(_ text: String) -> some View {
        Divider().padding(.leading, 14)
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
    }

    /// 一列：VoiceOver 照舊「第一顆按鈕字：句子」
    private func checkRow(_ entry: HealthCheckEntry) -> some View {
        let spec = checkSpec(entry.kind)
        let spoken = (spec.buttons.first?.title ?? "") + "：" + spec.message
        return VStack(spacing: 0) {
            if !entry.first {
                Divider().padding(.leading, 44)
            }
            FinanceCheckRow(icon: spec.icon,
                            message: spec.message,
                            buttons: spec.buttons,
                            accessibilityLabel: spoken,
                            pal: pal)
        }
    }

    private func checkSpec(_ kind: HealthCheckKind) -> HealthCheckSpec {
        switch kind {
        case .recovery(let cp): return recoverySpec(cp)
        case .duplicate(let d): return duplicateSpec(d)
        case .routeFind(let f): return routeFindSpec(f)
        case .moreAccess: return moreAccessSpec()
        case .stale(let st): return staleSpec(st)
        }
    }

    /// 救回：「上次的跑步 3.4 公里・21:05 還沒存。」〔存下來〕〔丟掉〕（照舊；丟掉先問）
    private func recoverySpec(_ cp: RunCheckpoint) -> HealthCheckSpec {
        let store = lifeStore
        let buttons: [FinanceCheckButton] = [
            FinanceCheckButton(title: "存下來") { RunRecoveryCenter.shared.save(cp, store: store) },
            FinanceCheckButton(title: "丟掉") { discardTarget = cp }
        ]
        return HealthCheckSpec(icon: "exclamationmark.arrow.circlepath", message: cp.prompt(), buttons: buttons)
    }

    /// 同一趟：「Apple Watch 也記了 10/8 06:04–06:41 這一趟（6.0 公里），要合成一筆嗎？」〔合成一筆〕〔兩筆都留〕；
    /// 舊紀錄（手錶那筆已在 LifeGood）：「9/20 的跑步是舊版記的，路線沒存到；Apple Watch 同一時間有路線。」〔接回來〕〔兩筆都留〕
    private func duplicateSpec(_ d: WorkoutDuplicate) -> HealthCheckSpec {
        let store = lifeStore
        let center = sync
        let buttons: [FinanceCheckButton] = [
            FinanceCheckButton(title: d.legacy ? "接回來" : "合成一筆") {
                Task { await center.merge(d, store: store) }
            },
            FinanceCheckButton(title: "兩筆都留") { center.keepBoth(d, store: store) }
        ]
        return HealthCheckSpec(icon: d.legacy ? "map" : "applewatch",
                               message: WorkoutFacts.duplicatePrompt(d),
                               buttons: buttons)
    }

    /// 舊紀錄（手錶那筆還沒帶進 LifeGood）：〔接回來〕〔先不要〕
    private func routeFindSpec(_ f: WorkoutRouteFind) -> HealthCheckSpec {
        let store = lifeStore
        let center = sync
        let buttons: [FinanceCheckButton] = [
            FinanceCheckButton(title: "接回來") { Task { await center.attachRoute(f, store: store) } },
            FinanceCheckButton(title: "先不要") { center.skipRoute(f, store: store) }
        ]
        return HealthCheckSpec(icon: "map", message: f.prompt, buttons: buttons)
    }

    /// 「Apple 健康多了一項要你同意：騎車距離。」〔去同意〕（跳系統的同意畫面）
    private func moreAccessSpec() -> HealthCheckSpec {
        let store = lifeStore
        let center = sync
        let buttons: [FinanceCheckButton] = [
            FinanceCheckButton(title: "去同意") { Task { await center.requestAccess(store: store) } }
        ]
        return HealthCheckSpec(icon: "heart.text.square", message: WorkoutFacts.moreAccessPrompt, buttons: buttons)
    }

    /// 「10/12 晨跑改過了，Apple 健康裡還是 5.0 公里。」〔更新〕（刪掉 Apple 健康裡舊的那筆、照現在的寫一筆新的）
    private func staleSpec(_ st: WorkoutHealthStale) -> HealthCheckSpec {
        let store = lifeStore
        let center = sync
        let id = st.id
        let buttons: [FinanceCheckButton] = [
            FinanceCheckButton(title: "更新") { Task { await center.update(id, store: store) } }
        ]
        return HealthCheckSpec(icon: "arrow.triangle.2.circlepath",
                               message: WorkoutFacts.stalePrompt(st),
                               buttons: buttons)
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
        .alert(deleteTitle, isPresented: deleteBinding, presenting: deleteAsk) { a in
            deleteButtons(a)
        } message: { a in
            Text(a.message)
        }
    }

    /// [v25.554] 刪除確認框的按鈕（WorkoutActions.deleteKind）：LifeGood 寫進 Apple 健康的三顆；手錶的、沒碰過的〔刪除〕〔取消〕
    @ViewBuilder
    private func deleteButtons(_ a: WorkoutDeleteAsk) -> some View {
        if a.kind == .withHealth {
            Button("連 Apple 健康那筆一起刪", role: .destructive) { deleteNow(a, alsoFromHealth: true) }
            Button("只刪 LifeGood 這筆", role: .destructive) { deleteNow(a, alsoFromHealth: false) }
        } else {
            Button("刪除", role: .destructive) { deleteNow(a, alsoFromHealth: false) }
        }
        Button("取消", role: .cancel) { }
    }

    /// 一趟一張卡：點了打開成果頁（不擋訂閱）；長按編輯／複製到現在／刪除
    private func recentCard(_ row: HealthRecentRow) -> some View {
        let s = row.session
        return Button {
            sheet = .detail(UUID(), s.id)
        } label: {
            MoneyItemCard(item: row.item)
                .overlay { flashRing(row.id) }                 // [v25.555] 剛跑完回來亮一下
        }
        .buttonStyle(MoneyPressStyle())
        // 長按浮起來的預覽照卡片的圓角（MoneyItemCard 一般版 18），不要露出方角（同全部紀錄頁）
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityHint("點兩下看這一趟的成果；長按可以編輯或刪除")
        .contextMenu {
            recentMenu(s)
        }
    }

    /// [v25.555] 剛跑完那一趟的綠色外框（跟卡片同一個圓角 18）；不擋點按、VoiceOver 不讀
    @ViewBuilder
    private func flashRing(_ id: UUID) -> some View {
        if flashId == id {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(WorkoutPalette.go, lineWidth: 2.5)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            EmptyView()
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
        deleteAsk?.title ?? ""
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleteAsk != nil }, set: { if !$0 { deleteAsk = nil } })
    }

    /// 提示框關掉那一次畫面更新先過，下一輪主執行緒才寫 store（WorkoutActions.delete 已經排到下一輪）；
    /// [v25.554] alsoFromHealth：〔連 Apple 健康那筆一起刪〕。Apple 健康那筆留著的，HealthSyncCenter 記進「不再帶進來」
    private func deleteNow(_ a: WorkoutDeleteAsk, alsoFromHealth: Bool) {
        WorkoutActions.delete(a.id, alsoFromHealth: alsoFromHealth, store: lifeStore)
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

    // MARK: ⑤-1 月曆、⑤-2 個人紀錄（v25.557）

    /// 月曆：資料在卡片自己的 .task(id:) 算（refreshKey＝workoutsRevision＋今天；請假一改 workoutsRevision 就加一）。
    /// 長按一週請假：長按選單收起來那一輪先過，下一輪主執行緒才寫 store
    private var calendarSection: some View {
        let store = lifeStore
        return HealthCalendarCard(sessions: lifeStore.workouts,
                                  leave: lifeStore.workoutLeave,
                                  refreshKey: "\(lifeStore.workoutsRevision)-\(dayKey)",
                                  onOpen: { id in openDetail(id) },
                                  onLeave: { on, start in
                                      DispatchQueue.main.async { store.setLeave(on, weekOf: start) }
                                  })
            .padding(.horizontal, 16)
    }

    /// 個人紀錄（page.records 在 .task 裡算好）；點一列打開那一趟
    private func recordsSection(_ p: HealthPageData) -> some View {
        HealthRecordsCard(records: p.records) { id in openDetail(id) }
            .padding(.horizontal, 16)
    }

    // MARK: ⑦ Apple 健康（一列）

    /// 「已連線・今天 06:40 同步」「已連線」「沒有打開」「這台裝置不支援」；[v25.554] 同步中「同步中…」
    private var appleHealthStatus: String {
        guard HealthKitManager.shared.isAvailable else { return "這台裝置不支援" }
        guard hkEnabled else { return "沒有打開" }
        if sync.syncing { return "同步中…" }
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

    /// 標頭右邊綠色「＋」＋白卡：每列「[cross.fill] 年度健檢　2026/3/2・抽血正常 ›」，最下面一列「＋ 記一筆健康里程碑」。
    /// [健康 v7b] 白卡最上面先列「還沒記」的運動里程碑（最多 3 列，pendingSportMilestones），再一條分隔線接健康里程碑
    private func milestoneSection(_ p: HealthPageData) -> some View {
        let list = healthMilestones
        let firstId = list.first?.id
        let pending = pendingSportMilestones(p)
        let firstPending = pending.first?.key
        return VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "健康里程碑", addLabel: "記一筆健康里程碑", onAdd: { addMilestone() })
            VStack(spacing: 0) {
                ForEach(pending, id: \.key) { m in
                    sportMilestoneRow(m, divider: m.key != firstPending)
                }
                if !pending.isEmpty {
                    Divider().padding(.leading, 14)
                }
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

    // MARK: ⑧ 上面：還沒記的運動里程碑（[健康 v7b]）

    /// 近 90 天達成、還沒記成人生里程碑的（page.milestones 已經新到舊），最多 3 個。
    /// 記過沒每次畫都對 lifeStore.milestones 看一次（最多 5 × 人生里程碑筆數，很輕）：在成果頁記了，這裡馬上不見
    private func pendingSportMilestones(_ p: HealthPageData) -> [WorkoutMilestone] {
        let life = lifeStore.milestones
        let open = p.milestones.filter { !WorkoutFacts.isRecorded($0, in: life) }
        return Array(open.prefix(3))
    }

    /// 一列「[flag.checkered 運動色圓] 第一次跑完 10 公里　8/23・還沒記 ›」；點了打開那一趟的成果頁（不擋訂閱：記的按鈕在成果頁、那裡擋）
    private func sportMilestoneRow(_ m: WorkoutMilestone, divider: Bool) -> some View {
        let meta = WorkoutFormat.monthDay(m.date) + "・還沒記"
        let spoken = m.title + "，" + Self.spokenMonthDay(m.date) + "，還沒記成人生里程碑"
        return VStack(spacing: 0) {
            if divider {
                Divider().padding(.leading, 52)
            }
            Button {
                openDetail(m.sessionId)
            } label: {
                sportMilestoneLabel(m, meta: meta)
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .accessibilityHint("點兩下打開那一趟")
            .accessibilityAddTraits(.isButton)
        }
    }

    private func sportMilestoneLabel(_ m: WorkoutMilestone, meta: String) -> some View {
        HStack(spacing: 12) {
            sportMilestoneIcon(m)
            Text(m.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(meta)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    /// 運動色的圓＋白色終點方格旗（連續週數、次數這種不分運動的用綠）
    private func sportMilestoneIcon(_ m: WorkoutMilestone) -> some View {
        let fill = sportMilestoneColor(m)
        return Image(systemName: m.icon)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: 26, height: 26)
            .background(fill, in: Circle())
            .accessibilityHidden(true)
    }

    private func sportMilestoneColor(_ m: WorkoutMilestone) -> Color {
        guard let sport = m.sport else { return MoneyTone.good.color(pal) }
        return WorkoutPalette.sport(sport, dark: pal.dark)
    }

    /// VoiceOver 的日期字「8 月 23 日」（西曆、手機時區，同 WorkoutFacts.calendar）
    private static func spokenMonthDay(_ date: Date) -> String {
        let c = WorkoutFacts.calendar.dateComponents([.month, .day], from: date)
        return "\(c.month ?? 0) 月 \(c.day ?? 0) 日"
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

/// 健康頁「Apple 健康」那一列打開的小頁：開關、會帶進來／會存回去、立即同步。開關、同步都不擋訂閱。
/// [v25.554] 不再 private：成果頁 Apple 健康那一列〔打開〕也開這一頁（WorkoutDetailView，.sheet(item:)＋.appStores()）。
/// 同步搬進 HealthSyncCenter（健康頁自動同步、成果頁〔存進去〕〔更新〕共用同一套）：這頁只畫它的狀態、按了叫它。
/// 同步到一半關掉小頁再打開、又按一次：HealthSyncCenter.syncing 還是 true（單例，跨小頁），按鈕是「同步中…」不能按。
/// 字照 judge §3.8「會帶進來／會存回去」：以前寫「體重…與 Apple 健康互通」，其實體重從來沒寫回去（U1 C7）。
struct HealthAppleHealthSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var health = HealthKitManager.shared
    /// [v25.554] 同步、去同意、上一次的結果（同步中、已帶入幾筆、沒成功的一句話）
    @ObservedObject private var center = HealthSyncCenter.shared
    /// 上次同步時間（HealthSyncCenter 寫同一個鍵；這裡只讀來顯示）
    @AppStorage("health_hk_last_sync") private var lastSyncEpoch: Double = 0
    @AppStorage("health_hk_enabled") private var hkEnabled = false

    init() {}

    var body: some View {
        NavigationStack {
            Form {
                switchSection
                if health.isAvailable && hkEnabled {
                    bringInSection
                    sendBackSection
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

    // MARK: 動作

    /// 打開：跳系統的同意畫面（只問還沒問過的種類），問完同步一次（HealthSyncCenter.requestAccess）。
    /// @AppStorage 先寫進 UserDefaults，HealthSyncCenter.isEnabled 讀得到「開著」
    private var hkBinding: Binding<Bool> {
        Binding(get: { hkEnabled },
                set: { on in
                    hkEnabled = on
                    if on { requestAccess() }
                })
    }

    private func requestAccess() {
        let store = lifeStore
        let sync = center
        Task { await sync.requestAccess(store: store) }
    }

    private func syncNow() {
        let store = lifeStore
        let sync = center
        Task { await sync.sync(store: store) }
    }

    // MARK: 開關

    /// 關著時只留開關和這段說明；開著時下面多三段（會帶進來、會存回去、同步）
    private var footerText: String {
        if !health.isAvailable { return "這台裝置不支援「健康」App。" }
        if hkEnabled {
            return "開著時，Apple Watch 記的運動會自己出現在健康頁，在 LifeGood 記的運動也會存進 Apple 健康。"
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

    // MARK: 會帶進來／會存回去

    private var bringInSection: some View {
        Section {
            infoLine("Apple Watch 記的運動（路線、距離、爬升、大卡）", icon: "applewatch")
            infoLine("體重、身高、血壓", icon: "heart.text.square")
        } header: {
            Text("會帶進來")
        }
    }

    private var sendBackSection: some View {
        Section {
            infoLine("在 LifeGood 記的運動：時間、距離（騎車寫騎車距離）、路線、暫停、大卡", icon: "figure.run")
            infoLine("重訓只有時間和大卡（Apple 健康沒有組數、次數的欄位）", icon: "dumbbell.fill")
            infoLine("體重不會寫回去", icon: "scalemass")
        } header: {
            Text("會存回去")
        } footer: {
            Text("打開健康頁時，離上次同步超過 15 分鐘會自己同步。在 LifeGood 刪掉手錶記的那一趟，以後不會再帶進來。")
        }
    }

    /// 一列一行字（不能按）
    private func infoLine(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: 同步

    private var lastSyncText: String {
        HealthPageData.whenText(Date(timeIntervalSince1970: lastSyncEpoch), now: Date())
    }

    private var syncTitle: String {
        center.syncing ? "同步中…" : "立即同步"
    }

    /// 沒成功的一句話：HealthSyncCenter 的（沒刪成功、沒更新成功…）＋HealthKitManager 的（同一句不寫兩次）
    private var problemText: String? {
        var parts: [String] = []
        if let p = center.lastProblem, !p.isEmpty { parts.append(p) }
        if let e = health.lastError, !e.isEmpty, !parts.contains(e) { parts.append(e) }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private var syncSection: some View {
        Section {
            Button {
                syncNow()
            } label: {
                Label(syncTitle, systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(center.syncing)
            if center.needsMoreAccess {
                Button {
                    requestAccess()
                } label: {
                    Label("同意 Apple 健康新的一項（騎車距離）", systemImage: "checkmark.shield")
                }
                .disabled(center.syncing)
            }
            if lastSyncEpoch > 0 {
                LabeledContent("上次同步", value: lastSyncText)
            }
            if let msg = center.lastMessage {
                Text(msg)
                    .font(.footnote)
                    .foregroundStyle(WorkoutPalette.go)
            }
            if let problem = problemText {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }
}
