import Foundation
import HealthKit
import WatchKit

// MARK: - 手錶自己記跑步（手錶 v4，v25.580；watch/judge.md §2.10～§2.12、§5.7、§7.8-8／16／17；watch/build/v4/brief.md §2、G2）
//
// 只屬於 LifeGoodWatch。**骨架（主控寫）：對外的名字、型別、參數一個都不准改（畫面 G3、G4 照這些寫）；G2 填內容。**
// HKWorkoutSession＋HKLiveWorkoutBuilder（距離、心率、大卡由 HKLiveWorkoutDataSource 自己收），路線交給 RouteRecorder
// （seriesBuilder(for: .workoutRoute())），每公里震一下＋講一句交給 WatchRunVoice，存檔交給 RunStash。照 Apple 範例
// samples/mw/Shared/WorkoutManager.swift、WorkoutManager+watchOS.swift 的寫法（@MainActor 類別、delegate nonisolated、
// 回呼一律 Task { @MainActor in … }）。
//
// 一趟怎麼走（phase）：
//   idle ──③〔▶ 開始跑步〕openPrep──▶ preparing（session.prepare() 感應器暖機、GPS 暖機、看權限）
//        ◀──✕ cancelPrep──
//   preparing ──〔開始〕beginCountdown──▶ countdown（3、2、1 每下震一次；點一下 skipCountdown）
//   countdown ──數到 0──▶ running（startActivity＋beginCollection 同一刻＝出門那一刻；RunStash 先寫一次）
//   running ⇄ paused（你按的：pause()／resume()；手錶的自動暫停不換 phase，autoPaused＝true）
//   running／paused ──按住 1 秒 end()──▶ ending（stopActivity → .stopped → endCollection）
//        移動不到 60 秒 ──▶ askShort（〔存下來〕saveShort／〔丟掉〕discardShort → idle）
//        ──▶ 存進 Apple 健康（附註、finishWorkout、路線收尾）──▶ summary（saved＝true；存不進去 saved＝false、unsaved 有值）
//   summary ──〔完成〕finishSummary──▶ idle（跑完 15 分鐘內打開 App 還是摘要；超過 appBecameActive 收起來）
//
// ⚠️ 不准設 CLLocationManager.allowsBackgroundLocationUpdates（watchOS 沒有 location 背景模式＝一開定位就閃退；
//    運動 session 本來就讓 App 整段在背景活著，judge §5.7、§7.8-16）。
// ⚠️ 不准碰 iPhone 的東西：這裡只寫手錶自己的 Apple 健康；「第幾次」「新紀錄」只在 iPhone 算（v5 送回來）。
//
// [G2 填好]（brief §1-11～18、G2-1）
// • session 的回呼（狀態、自動暫停、出錯）照 Apple 範例用 AsyncStream 排隊、一個一個在主執行緒處理（Task 不保證先來先做；
//   收尾要 await，下一個等它做完）；每一個帶 session 的 ObjectIdentifier：換運動時 end() 掉的那個、存好之後放掉的那個晚到的
//   「已結束」不會算到這一趟。builder 的「收到資料」順序沒關係（主執行緒當下再讀 statistics），照範例 Task { @MainActor in }。
// • 你按的暫停走 didChangeTo（.paused／.running）；手錶的自動暫停走 didGenerate（.motionPaused／.motionResumed），phase 不換。
//   兩種疊在一起（自動暫停中又按暫停）算同一段、算自動（同 iPhone WatchRunImport.pauses 的配對）；你按繼續時那一段關掉。
// • 結束：end() → stopActivity → .stopped → endCollection → 不到 60 秒問 → addMetadata（失敗不擋）→ finishWorkout → session.end()
//   → 路線收尾 → 摘要。10 秒等不到 .stopped（session 壞了）自己收尾；session 沒經過 .stopped 就 .ended 也收尾（存不進去就留在手錶）。
// • 當機接回：系統叫 handleActiveWorkoutRecovery → recoverActiveWorkoutSession；RunStash 那一份（或沒存成那一趟）開始時間差 5 秒內
//   才接回每公里、暫停、點；接回後第一次拿到距離只補每公里、不震不講；路線一律收尾時用獨立的 builder 插全部的點。
//   系統沒叫：App 啟動 6 秒後（或 5 秒後回前景、接回問不到）那一份變成「沒存成」（不到 1 分鐘的直接丟；準備頁、倒數中也收；
//   啟動 5 秒內就開跑的話，開跑那一刻先收，免得新的存檔蓋掉它）。
// [裁定] 手錶的自動暫停兩條路都聽：session 的 didGenerate，加上 builder 收到的事件（workoutBuilderDidCollectEvent 讀
//   workoutEvents；研究 u3 §6.3 寫的是這一條，Apple 沒寫清楚 watchOS 26 走哪一條）。兩條都走 motionEvent：同一個事件來兩次、
//   晚到的舊事件（時間不比上一個處理過的新）都不再處理，不會講兩次「自動暫停。」、不會多記一段暫停。當機接回時舊的事件不重播。

/// 跑步這一趟在哪一步（RootView 看它：不是 idle 就整個畫面換成跑步）
enum RunPhase: Equatable {
    /// 沒在跑（③ 跑步與其他頁照常）
    case idle
    /// 準備頁（session 已 prepare、GPS 暖機）
    case preparing
    /// 3、2、1
    case countdown
    /// 跑步中（含手錶的自動暫停：autoPaused）
    case running
    /// 你按的暫停
    case paused
    /// 按住結束之後：收尾、存進 Apple 健康中（畫面「存進 Apple 健康中…」）
    case ending
    /// 移動不到 1 分鐘：問要不要存
    case askShort
    /// 跑完摘要（saved＝true 存好了；false＝存不進去、unsaved 有值、〔再存一次〕）
    case summary
}

/// [G2] HealthKit session 的回呼（背景佇列）→ 主執行緒照順序處理（Apple 範例 WorkoutManager.swift 的 AsyncStream 寫法；
/// 範例只留最新一個，這裡全部留：暫停、繼續、停止一個都不能掉）。session＝那個 HKWorkoutSession 的 ObjectIdentifier
private enum WorkoutSessionEvent: Sendable {
    case state(HKWorkoutSessionState, from: HKWorkoutSessionState, date: Date, session: ObjectIdentifier)
    case motion(paused: Bool, date: Date, session: ObjectIdentifier)
    case failed(String, session: ObjectIdentifier)
}

/// 檔案層的常數：nonisolated 的 delegate 方法直接 yield（不放在 @MainActor 類別裡，Swift 5／6 模式都不用跨隔離）
private let workoutSessionEvents = AsyncStream.makeStream(of: WorkoutSessionEvent.self, bufferingPolicy: .unbounded)

@MainActor
final class WorkoutManager: NSObject, ObservableObject {
    static let shared = WorkoutManager()

    // MARK: 畫面讀的（只准這個類別改）

    @Published private(set) var phase: RunPhase = .idle
    /// 這一趟（或準備頁轉錶冠選到）的運動
    @Published private(set) var sport: WatchSport = .run
    /// 健康「存運動」的權限（authorizationStatus(for: .workoutType())；準備頁那一行，WatchRunText.prepLine）
    @Published private(set) var health: WatchRunHealthAccess = .unknown
    /// 低電量模式（ProcessInfo.isLowPowerModeEnabled；進準備頁、換運動時重讀）
    @Published private(set) var lowPower = false
    /// 倒數到幾（3、2、1）
    @Published private(set) var countdown = 3
    /// 這一趟開始的時間（3、2、1 數到 0 那一刻；頁首時段名「晨跑」用它）
    @Published private(set) var startDate: Date?
    /// 距離（公尺；builder 的步行＋跑步距離，騎車用騎車距離）
    @Published private(set) var meters: Double = 0
    /// 每跑滿一整公里那一刻的移動秒數
    @Published private(set) var kmTimes: [Double] = []
    /// 手錶的自動暫停中（motionPaused 到 motionResumed）
    @Published private(set) var autoPaused = false
    /// 你按暫停的那一刻（paused 時才有；頁首「已暫停 0:42」）
    @Published private(set) var pausedSince: Date?
    /// 心率（最近一筆，次／分）；還沒量到 nil
    @Published private(set) var heartRate: Double?
    /// 「這一公里」（分鐘／公里，最近 30 秒；WatchRunMath.recentPace）；算不出來 nil
    @Published private(set) var recentPace: Double?
    /// 騎車「時速」（公里／時，最近 10 秒；WatchRunMath.recentSpeedKmh）
    @Published private(set) var recentSpeed: Double?
    /// 每跑滿一公里那 3 秒（全螢幕「第 3 公里」）；平常 nil
    @Published private(set) var kmFlash: WatchRunKmFlash?
    /// 當機重開接回來：這個時間以前頁首寫「已接回」
    @Published private(set) var recoveredUntil: Date?
    /// 跑完那一趟（摘要讀它；ending 時已經有 end、移動時間、距離）
    @Published private(set) var result: WatchRunRecord?
    /// 摘要的路線小圖（result 定下來時算一次：WatchRunMath.routeShape）
    @Published private(set) var resultShape: [WatchRunShapePoint] = []
    /// 摘要：存進 Apple 健康了
    @Published private(set) var saved = false
    /// 存不進 Apple 健康、留在手錶上的那一趟（RunStash.unsaved；③ 那一行「有 1 趟還沒存進 Apple 健康」）
    @Published private(set) var unsaved: WatchRunRecord?
    /// 〔再存一次〕、〔不存這一趟〕正在做
    @Published private(set) var busy = false
    /// 上一個動作失敗的一句話（摘要最下面小字；成功的動作清掉）
    @Published private(set) var problem: String?
    /// 每公里講一句（WatchRunPrefs；控制頁小開關、手錶設定同一個）
    @Published private(set) var voiceOn: Bool
    /// 每公里震一下
    @Published private(set) var hapticOn: Bool

    /// 不是 idle＝RootView 整個畫面換成跑步（準備、倒數、跑步中、存檔中、問不到 1 分鐘、摘要）
    var showsRunFlow: Bool { phase != .idle }

    // MARK: 內部（G2）

    let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    /// session 是照哪一種運動建的（準備頁轉錶冠換了運動：那個 session 收掉，按〔開始〕時再建）
    private var sessionSport: WatchSport?
    /// 這一趟手錶自己的編號（WatchRunRecord.id）
    private var runId = UUID()
    /// 「這一公里」的距離樣本（WatchRunMath.pruned 只留 60 秒）
    private var samples: [WatchRunSample] = []
    /// 這一趟的暫停（你按的、自動的）
    private var pauses: [WatchRunPause] = []
    /// 動態大卡、心率平均最高（builder 的 statistics）
    private var kcal: Double = 0
    private var heartAvg: Double?
    private var heartMax: Double?
    /// 上一筆距離（公尺、移動秒數）：kmCrossings 從這一筆內插到新的那一筆
    private var prevMeters: Double = 0
    private var prevSeconds: Double = 0
    /// 當機接回後第一次拿到距離：只補每公里時間，不震不講（中間漏掉的那幾公里配速不準）
    private var quietNextDistance = false
    /// [裁定] 最後處理過的自動暫停／繼續的時間（session、builder 兩條路同一個事件只算一次；比它舊的不理）
    private var lastMotionAt: Date?
    /// 存好的那一筆（〔不存這一趟〕要刪它）
    private var savedWorkout: HKWorkout?
    /// 存好的那一條路線（〔不存這一趟〕一起刪）
    private var savedRoute: HKWorkoutRoute?
    /// 每秒一次（重算「這一公里」、GPS 弱、每 30 秒寫一次 RunStash）
    private var ticker: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    /// 每公里那一頁 3 秒後收起來
    private var flashTask: Task<Void, Never>?
    /// 上次寫 RunStash 的時間
    private var lastCheckpoint: Date?
    /// App 啟動時讀到的跑步中存檔（當機那一趟）：系統接回就用它補；沒接回（appBecameActive 5 秒後）變成 unsaved
    private var pendingCheckpoint: WatchRunRecord?
    private let launchedAt = Date()
    /// 結束收尾已經開始（.stopped、.ended、10 秒保險那一次只做一次）
    private var finishing = false
    /// recoverActiveWorkoutSession 正在問
    private var recovering = false
    /// 摘要出現的那一刻（15 分鐘收起來：跑完的時間跟打開摘要的時間取晚的）
    private var summarySince: Date?
    /// 低電量模式切換的通知
    private var powerObserver: NSObjectProtocol?

    /// 打包出來的 Info.plist 有健康兩句說明字（少了 requestAuthorization 會閃退；同 iPhone HealthKitManager.hasUsageDescriptions）
    private static let hasHealthUsageDescriptions: Bool =
        Bundle.main.object(forInfoDictionaryKey: "NSHealthShareUsageDescription") != nil
            && Bundle.main.object(forInfoDictionaryKey: "NSHealthUpdateUsageDescription") != nil

    /// 開始以前要的權限（judge §5.7；Apple「Creating a workout route」：路線要讀寫 workoutType 與 workoutRoute）。
    /// 寫：運動、路線、距離、大卡（後兩種是〔再存一次〕用 HKWorkoutBuilder 補存時要的）；
    /// 讀：心率、大卡、步行＋跑步距離、騎車距離、運動、路線
    var typesToShare: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKSeriesType.workoutRoute(),
         HKQuantityType(.activeEnergyBurned), HKQuantityType(.distanceWalkingRunning),
         HKQuantityType(.distanceCycling)]
    }

    var typesToRead: Set<HKObjectType> {
        [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned),
         HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling),
         HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
    }

    private override init() {
        // 沒有預設值的先設（同 WatchModel.init 的規矩）
        voiceOn = WatchRunPrefs.voiceOn
        hapticOn = WatchRunPrefs.hapticOn
        super.init()
        unsaved = RunStash.loadUnsaved()
        pendingCheckpoint = RunStash.loadCurrent()
        health = healthAccess()
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        // session 的回呼一個一個照順序處理（收尾要 await：下一個等它做完）
        Task { @MainActor in
            for await event in workoutSessionEvents.stream {
                await self.handle(event)
            }
        }
        // 低電量模式在準備頁中途打開、關掉：那一行跟著換
        powerObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange,
                                                               object: nil, queue: .main) { _ in
            Task { @MainActor in
                WorkoutManager.shared.refreshLowPower()
            }
        }
        // 當機那一趟：系統通常在啟動時就叫 handleActiveWorkoutRecovery；6 秒後還沒接回就變成「沒存成」
        if pendingCheckpoint != nil {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                self.settleStaleCheckpoint(now: Date())
            }
        }
    }

    // MARK: ③、準備頁（G3 叫）

    /// ③〔▶ 開始跑步〕：phase＝preparing、sport＝傳進來的、讀權限與低電量、GPS 暖機、
    /// 健康有給就 prepare 一個 session（感應器先暖機）。只有大約位置：問一次「這一次給精確位置」
    func openPrep(sport: WatchSport) {
        if phase == .summary { finishSummary() }
        guard phase == .idle else { return }
        self.sport = sport
        problem = nil
        phase = .preparing
        refreshReadiness()
        let route = RouteRecorder.shared
        route.refreshAccess()
        route.warmUp()                    // 有權限才真的開始；還沒給的話記著，給了馬上開始
        route.askPreciseOnce()
        if health == .allowed {
            prepareSession()
        }
    }

    /// 準備頁 ✕：prepare 過的 session end()、GPS 停、回 idle
    func cancelPrep() {
        guard phase == .preparing || phase == .countdown else { return }
        countdownTask?.cancel()
        countdownTask = nil
        endPreparedSession()
        RouteRecorder.shared.cool()
        phase = .idle
    }

    /// 準備頁轉錶冠換運動：prepare 過的 session 運動不一樣就收掉（不馬上再 prepare：兩個 session 疊在一起會失敗，
    /// brief §1-14）；按〔開始〕時再建一個、3 秒倒數當暖機
    func setSport(_ sport: WatchSport) {
        guard phase == .idle || phase == .preparing else { return }
        refreshLowPower()
        guard sport != self.sport else { return }
        self.sport = sport
        if phase == .preparing, let prepared = sessionSport, prepared != sport {
            endPreparedSession()
        }
    }

    /// 重讀健康權限、低電量、位置權限（準備頁 onAppear、回前景）
    func refreshReadiness() {
        let h = healthAccess()
        if h != health { health = h }
        refreshLowPower()
        RouteRecorder.shared.refreshAccess()
    }

    /// 說明卡〔好〕：在手錶上跳健康權限框、再跳位置權限框；問完重讀、健康有給就 prepare
    func requestPermissions() async {
        if HKHealthStore.isHealthDataAvailable() && Self.hasHealthUsageDescriptions {
            do {
                try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            } catch {
                // 問不成（系統出錯）：下面重讀，準備頁照實寫
            }
        }
        RouteRecorder.shared.requestAccess()
        refreshReadiness()
        guard phase == .preparing else { return }
        if health == .allowed && session == nil {
            prepareSession()
        }
        RouteRecorder.shared.warmUp()
    }

    /// 〔開始〕：健康沒給（denied）不動；phase＝countdown、3、2、1 每下震一次，數到 0 開始
    func beginCountdown() {
        guard phase == .preparing, health != .denied else { return }
        if session == nil || sessionSport != sport {
            endPreparedSession()
            prepareSession()
        }
        problem = nil
        phase = .countdown
        countdown = 3
        countdownTask?.cancel()
        countdownTask = Task { @MainActor in
            for n in [3, 2, 1] {
                guard self.phase == .countdown, !Task.isCancelled else { return }
                self.countdown = n
                self.play(.click)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard self.phase == .countdown, !Task.isCancelled else { return }
            self.startRun(at: Date())
        }
    }

    /// 倒數時點一下：馬上開始
    func skipCountdown() {
        guard phase == .countdown else { return }
        countdownTask?.cancel()
        countdownTask = nil
        startRun(at: Date())
    }

    // MARK: 跑步中（G4 叫）

    /// 這一刻的移動秒數（扣掉暫停；TimelineView 每秒叫）：跑步中 builder.elapsedTime(at:)；跑完 result 的移動秒數；沒在跑 0
    func movingSeconds(at date: Date) -> Double {
        switch phase {
        case .running, .paused, .ending:
            guard let builder else { return result?.movingSeconds ?? prevSeconds }
            let s = builder.elapsedTime(at: date)
            return s.isFinite && s > 0 ? s : 0
        case .summary, .askShort:
            return result?.movingSeconds ?? 0
        default:
            return 0
        }
    }

    /// 〔⏸ 暫停〕
    func pause() {
        guard phase == .running else { return }
        session?.pause()
    }

    /// 〔▶ 繼續〕
    func resume() {
        guard phase == .paused else { return }
        session?.resume()
    }

    /// 按住 1 秒結束（只點一下不會到這裡：G4 的按住 1 秒才叫）
    func end() {
        guard phase == .running || phase == .paused else { return }
        phase = .ending
        flashTask?.cancel()
        kmFlash = nil
        WatchRunVoice.shared.stopAll()
        let now = Date()
        guard let s = session else {
            Task { @MainActor in await self.finishCollection(at: now) }
            return
        }
        s.stopActivity(with: now)
        // 保險：10 秒還沒收到「已停止」（session 壞了），自己收尾
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard self.phase == .ending, !self.finishing else { return }
            await self.finishCollection(at: now)
        }
    }

    /// 控制頁「🔊 語音」：這一趟有效、也記成下次的預設（WatchRunPrefs）
    func setVoiceOn(_ on: Bool) {
        voiceOn = on
        WatchRunPrefs.setVoiceOn(on)
        if !on { WatchRunVoice.shared.stopAll() }
    }

    /// 控制頁「震動」
    func setHapticOn(_ on: Bool) {
        hapticOn = on
        WatchRunPrefs.setHapticOn(on)
    }

    // MARK: 跑完（G4 叫）

    /// 不到 1 分鐘〔存下來〕
    func saveShort() {
        guard phase == .askShort else { return }
        phase = .ending
        Task { @MainActor in
            await self.saveLive()
        }
    }

    /// 不到 1 分鐘〔丟掉〕：builder.discardWorkout()、session.end()、RunStash 刪掉、回 idle
    func discardShort() {
        guard phase == .askShort else { return }
        builder?.discardWorkout()
        session?.end()
        session = nil
        builder = nil
        sessionSport = nil
        RouteRecorder.shared.reset()
        RunStash.clearCurrent()
        result = nil
        resultShape = []
        saved = false
        kmFlash = nil
        finishing = false
        phase = .idle
    }

    /// 〔再存一次〕：用 HKWorkoutBuilder（不是 live 的）照 unsaved 那一份補存（開始、結束、距離、大卡、暫停事件、附註、路線）
    func retrySave() {
        guard let r = unsaved, !busy else { return }
        busy = true
        problem = nil
        Task { @MainActor in
            await self.saveAgain(r)
            self.busy = false
        }
    }

    /// 〔不存這一趟〕確認之後：刪掉 Apple 健康裡剛存的那一筆（＋路線）、WatchRunLog 拿掉、回 idle
    func discardSaved() {
        guard let w = savedWorkout, !busy else { return }
        busy = true
        var objects: [HKObject] = []
        if let route = savedRoute {
            objects.append(route)
        }
        objects.append(w)
        // Task 裡只抓 let（抓 var 編不過：concurrently-executing code）
        let toDelete = objects
        let id = result?.id ?? runId
        Task { @MainActor in
            do {
                try await self.healthStore.delete(toDelete)
                WatchRunLog.remove(id)
                self.busy = false
                self.problem = nil
                self.finishSummary()
            } catch {
                self.busy = false
                self.problem = "沒刪成功：" + error.localizedDescription
            }
        }
    }

    /// 〔完成〕：回 idle（沒存成的那一趟留在 unsaved，③ 有一行）
    func finishSummary() {
        guard phase == .summary else { return }
        phase = .idle
        result = nil
        resultShape = []
        saved = false
        kmFlash = nil
        savedWorkout = nil
        savedRoute = nil
        summarySince = nil
        problem = nil
        session = nil
        builder = nil
        sessionSport = nil
        finishing = false
        RouteRecorder.shared.reset()
    }

    /// ③「有 1 趟還沒存進 Apple 健康」：打開那一趟的摘要（saved＝false，〔再存一次〕）
    func showUnsaved() {
        guard phase == .idle, let u = unsaved else { return }
        result = u
        resultShape = WatchRunMath.routeShape(u.points, kmTimes: u.kmTimes, sport: u.sport,
                                              movingSeconds: u.movingSeconds, meters: u.meters)
        saved = false
        savedWorkout = nil
        savedRoute = nil
        problem = nil
        summarySince = Date()
        phase = .summary
    }

    // MARK: 系統（G2：WatchAppDelegate、WatchModel 叫）

    /// 當機重開（WatchAppDelegate.handleActiveWorkoutRecovery）：recoverActiveWorkoutSession → 接回 session、builder、
    /// 從 RunStash.current 補每公里時間、暫停、路線點 → phase＝running／paused、頁首「已接回」3 秒
    func recoverActiveWorkout() {
        guard !recovering else { return }
        recovering = true
        Task { @MainActor in
            let recovered = try? await self.healthStore.recoverActiveWorkoutSession()
            self.recovering = false
            guard let s = recovered else {
                // 拿不到（session 已經沒了）：那一份 current 變成沒存成（問的時候 6 秒那一次被擋掉了，這裡補一次）
                self.settleStaleCheckpoint(now: Date())
                return
            }
            self.attach(s)
        }
    }

    /// 手錶 App 回前景（WatchModel.scenePhaseChanged(.active)）：摘要超過 15 分鐘收起來；
    /// 啟動 5 秒後還沒接回的跑步中存檔 → 變成 unsaved（〔再存一次〕）；重讀權限、低電量
    func appBecameActive(now: Date) {
        refreshReadiness()
        if phase == .summary {
            let anchor = max(result?.end ?? .distantPast, summarySince ?? .distantPast)
            if now.timeIntervalSince(anchor) > WatchRunText.summaryKeepSeconds {
                finishSummary()
            }
        }
        settleStaleCheckpoint(now: now)
    }

    // MARK: - 內部：準備

    /// 健康「存運動」的權限：只有寫的狀態查得到（讀的 Apple 刻意查不到）
    private func healthAccess() -> WatchRunHealthAccess {
        guard HKHealthStore.isHealthDataAvailable(), Self.hasHealthUsageDescriptions else { return .denied }
        switch healthStore.authorizationStatus(for: HKObjectType.workoutType()) {
        case .sharingAuthorized:
            return .allowed
        case .sharingDenied:
            return .denied
        default:
            return .unknown
        }
    }

    private func refreshLowPower() {
        let lp = ProcessInfo.processInfo.isLowPowerModeEnabled
        if lp != lowPower { lowPower = lp }
    }

    /// 這種運動的設定（室外）
    private static func configuration(for sport: WatchSport) -> HKWorkoutConfiguration {
        let c = HKWorkoutConfiguration()
        switch sport {
        case .run:
            c.activityType = .running
        case .walk:
            c.activityType = .walking
        case .bike:
            c.activityType = .cycling
        case .hike:
            c.activityType = .hiking
        }
        c.locationType = .outdoor
        return c
    }

    /// 接回的 session 是哪一種運動（不是這四種的當跑步）
    private static func watchSport(for type: HKWorkoutActivityType) -> WatchSport {
        switch type {
        case .walking:
            return .walk
        case .cycling:
            return .bike
        case .hiking:
            return .hike
        default:
            return .run
        }
    }

    /// 建一個 session＋live builder、prepare（感應器暖機）。建不起來就算了（按開始時再試，還是不行就說一句）
    private func prepareSession() {
        guard session == nil else { return }
        let config = Self.configuration(for: sport)
        let s: HKWorkoutSession
        do {
            s = try HKWorkoutSession(healthStore: healthStore, configuration: config)
        } catch {
            return
        }
        let b = s.associatedWorkoutBuilder()
        b.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
        s.delegate = self
        b.delegate = self
        session = s
        builder = b
        sessionSport = sport
        s.prepare()
    }

    /// 準備頁、倒數時收掉 prepare 過的 session（還沒開始的）
    private func endPreparedSession() {
        guard let s = session else { return }
        s.end()
        session = nil
        builder = nil
        sessionSport = nil
    }

    // MARK: - 內部：跑步中

    /// 3、2、1 數完（或點一下跳過）：startActivity＋beginCollection 同一刻
    private func startRun(at date: Date) {
        countdownTask = nil
        if session == nil || sessionSport != sport {
            endPreparedSession()
            prepareSession()
        }
        guard let s = session, let b = builder else {
            phase = .preparing
            problem = "沒開始成功：Apple 健康的運動開不起來"
            play(.failure)
            return
        }
        // 當機那一趟還沒收（啟動 5 秒內就開跑）：先變成沒存成，這一趟的存檔才不會把它蓋掉
        settleStaleCheckpoint(now: date, force: true)
        resetLiveNumbers()
        RouteRecorder.shared.restore(points: [])           // 上一趟的點一定不帶進這一趟
        runId = UUID()
        startDate = date
        finishing = false
        recoveredUntil = nil
        result = nil
        resultShape = []
        saved = false
        savedWorkout = nil
        savedRoute = nil
        problem = nil
        WatchRunPrefs.setLastSport(sport)
        play(.start)
        s.startActivity(with: date)
        Task { @MainActor in
            do {
                _ = try await b.beginCollection(at: date)
            } catch {
                self.startFailed(error)
            }
        }
        phase = .running
        RouteRecorder.shared.begin(routeBuilder: routeBuilder(of: b),
                                   moving: { [weak self] d in self?.movingSeconds(at: d) ?? 0 }, seg: 0)
        checkpoint(now: date)
        startTicker()
    }

    /// 這一趟 builder 的路線 builder：有給路線寫入才拿（同 iPhone saveWorkout：沒給就不碰 series builder，收尾時用獨立的試）
    private func routeBuilder(of b: HKLiveWorkoutBuilder) -> HKWorkoutRouteBuilder? {
        guard canShare(HKSeriesType.workoutRoute()) else { return nil }
        return b.seriesBuilder(for: HKSeriesType.workoutRoute()) as? HKWorkoutRouteBuilder
    }

    /// beginCollection 失敗：收掉、回準備頁、說一句
    private func startFailed(_ error: Error) {
        guard phase == .running || phase == .paused else { return }
        ticker?.cancel()
        ticker = nil
        session?.end()
        session = nil
        builder = nil
        sessionSport = nil
        RunStash.clearCurrent()
        RouteRecorder.shared.reset()
        RouteRecorder.shared.warmUp()
        startDate = nil
        phase = .preparing
        problem = "沒開始成功：" + error.localizedDescription
        play(.failure)
    }

    /// 新的一趟、接回之前：跑步中的數字歸零
    private func resetLiveNumbers() {
        meters = 0
        kmTimes = []
        samples = []
        pauses = []
        kcal = 0
        heartRate = nil
        heartAvg = nil
        heartMax = nil
        recentPace = nil
        recentSpeed = nil
        autoPaused = false
        pausedSince = nil
        kmFlash = nil
        prevMeters = 0
        prevSeconds = 0
        quietNextDistance = false
        lastCheckpoint = nil
        lastMotionAt = nil
    }

    /// 每秒一次：「這一公里」、GPS 弱、每 30 秒存檔；跑完自己停
    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard self.phase == .running || self.phase == .paused else { break }
                self.tick(now: Date())
            }
        }
    }

    private func tick(now: Date) {
        let secs = movingSeconds(at: now)
        let pace = WatchRunMath.recentPace(samples, nowSeconds: secs)
        if pace != recentPace { recentPace = pace }
        if sport == .bike {
            let speed = WatchRunMath.recentSpeedKmh(samples, nowSeconds: secs)
            if speed != recentSpeed { recentSpeed = speed }
        }
        RouteRecorder.shared.tick(now: now)
        if let until = recoveredUntil, now >= until { recoveredUntil = nil }
        let last = lastCheckpoint ?? .distantPast
        if now.timeIntervalSince(last) >= 30 { checkpoint(now: now) }
    }

    /// 跑步中這一趟寫進 RunStash（當機接回、沒接回變成沒存成都靠它）
    private func checkpoint(now: Date = Date()) {
        guard let start = startDate, phase == .running || phase == .paused else { return }
        let r = WatchRunRecord(id: runId, sport: sport, start: start, end: nil,
                               movingSeconds: movingSeconds(at: now), meters: meters, kcal: kcal,
                               heartAvg: heartAvg, heartMax: heartMax, kmTimes: kmTimes, pauses: pauses,
                               points: RouteRecorder.shared.points, workoutId: nil, savedAt: nil, updatedAt: now)
        RunStash.saveCurrent(r)
        lastCheckpoint = now
    }

    /// builder 收到資料（在主執行緒當下讀 statistics；不是這一趟的 builder 不理）
    private func collected(from id: ObjectIdentifier) {
        guard let b = builder, ObjectIdentifier(b) == id,
              phase == .running || phase == .paused else { return }
        updateStats(from: b, seconds: b.elapsedTime, announce: true)
    }

    /// 心率、大卡、距離（騎車用騎車距離）；距離變多才往下算每公里
    private func updateStats(from b: HKLiveWorkoutBuilder, seconds: Double, announce: Bool) {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        if let hr = b.statistics(for: HKQuantityType(.heartRate)) {
            if let v = hr.mostRecentQuantity()?.doubleValue(for: bpm), v.isFinite, v > 0, v != heartRate {
                heartRate = v
            }
            if let a = hr.averageQuantity()?.doubleValue(for: bpm), a.isFinite, a > 0 {
                heartAvg = a
            }
            if let m = hr.maximumQuantity()?.doubleValue(for: bpm), m.isFinite, m > 0 {
                heartMax = m
            }
        }
        let energy = b.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()
        if let k = energy?.doubleValue(for: .kilocalorie()), k.isFinite, k >= 0 {
            kcal = k
        }
        let distanceType = sport == .bike ? HKQuantityType(.distanceCycling) : HKQuantityType(.distanceWalkingRunning)
        guard let m = b.statistics(for: distanceType)?.sumQuantity()?.doubleValue(for: .meter()),
              m.isFinite, m > meters else { return }
        let secs = seconds.isFinite ? max(seconds, prevSeconds) : prevSeconds
        distanceArrived(meters: m, seconds: secs, announce: announce)
    }

    /// 新的累計距離：走滿整公里那一刻（內插）記進 kmTimes、「這一公里」的樣本、每公里震一下講一句
    private func distanceArrived(meters m: Double, seconds: Double, announce: Bool) {
        let quiet = quietNextDistance
        quietNextDistance = false
        let crossed = WatchRunMath.kmCrossings(prevMeters: prevMeters, prevSeconds: prevSeconds,
                                               meters: m, seconds: seconds, done: kmTimes.count)
        samples = WatchRunMath.pruned(samples + [WatchRunSample(seconds: seconds, meters: m)], nowSeconds: seconds)
        prevMeters = m
        prevSeconds = seconds
        meters = m
        guard !crossed.isEmpty else { return }
        kmTimes += crossed
        if announce && !quiet {
            announceKm()
        }
        checkpoint()
    }

    /// 每公里那 3 秒：只講最後那一公里（騎車不是 5 的倍數 nil：不震不講不換頁）
    private func announceKm() {
        guard let f = WatchRunText.kmFlash(sport: sport, kmTimes: kmTimes) else { return }
        kmFlash = f
        if hapticOn { play(.notification) }
        if voiceOn { WatchRunVoice.shared.say(f.voice) }
        flashTask?.cancel()
        let nanos = UInt64(min(max(WatchRunText.flashSeconds, 0), 60) * 1_000_000_000)
        flashTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled, self.kmFlash == f else { return }
            self.kmFlash = nil
        }
    }

    // MARK: - 內部：暫停（你按的走 session 狀態、手錶的自動暫停走事件）

    /// 最後一段暫停還沒結束
    private var hasOpenPause: Bool {
        guard let last = pauses.last else { return false }
        return last.end == nil
    }

    private func closeOpenPause(at date: Date) {
        guard let last = pauses.last, last.end == nil else { return }
        pauses[pauses.count - 1].end = max(date, last.start)
    }

    /// 路線：你按的暫停、自動暫停任一個在就不收點
    private func syncRoutePause() {
        RouteRecorder.shared.setPaused(phase == .paused || autoPaused)
    }

    /// session → .paused（你按的）。自動暫停中又按暫停：同一段（算自動），不另開一段
    private func manualPaused(at date: Date) {
        guard phase == .running else { return }
        phase = .paused
        pausedSince = date
        if !hasOpenPause {
            pauses.append(WatchRunPause(start: date, auto: false))
        }
        syncRoutePause()
        play(.stop)
        checkpoint()
    }

    /// session → .running（從你按的暫停繼續）：那一段關掉（含自動暫停中按的那一段）
    private func manualResumed(at date: Date) {
        guard phase == .paused else { return }
        closeOpenPause(at: date)
        autoPaused = false
        pausedSince = nil
        phase = .running
        syncRoutePause()
        play(.start)
        checkpoint()
    }

    /// 手錶的自動暫停（motionPaused）：phase 不換、頁首「已自動暫停」、講「自動暫停。」
    private func motionPaused(at date: Date) {
        guard phase == .running, !autoPaused else { return }
        autoPaused = true
        if !hasOpenPause {
            pauses.append(WatchRunPause(start: date, auto: true))
        }
        syncRoutePause()
        if hapticOn { play(.stop) }
        if voiceOn { WatchRunVoice.shared.say(WatchRunFacts.voiceAutoPause) }
        checkpoint()
    }

    /// 手錶的自動繼續（motionResumed）：講「繼續。」。你按的暫停還在的話那一段留著（等你按繼續）
    private func motionResumed(at date: Date) {
        guard autoPaused else { return }
        autoPaused = false
        if phase == .running {
            closeOpenPause(at: date)
        }
        syncRoutePause()
        guard phase == .running else { return }
        if hapticOn { play(.start) }
        if voiceOn { WatchRunVoice.shared.say(WatchRunFacts.voiceAutoResume) }
        checkpoint()
    }

    /// [裁定] 自動暫停／繼續的入口（session 的 didGenerate、builder 收到的事件都走這裡）：
    /// 同一個事件從兩條路來、或晚到的舊事件（時間不比上一個處理過的新）都不再處理
    private func motionEvent(paused: Bool, at date: Date) {
        if let last = lastMotionAt, date <= last { return }
        lastMotionAt = date
        if paused {
            motionPaused(at: date)
        } else {
            motionResumed(at: date)
        }
    }

    /// [裁定] builder 收到事件（主執行緒當下讀 workoutEvents；不是這一趟的 builder 不理）：
    /// 比上一個處理過的新的自動暫停／繼續照時間順序走 motionEvent。你按的暫停、繼續照舊只看 session 的狀態（didChangeTo）
    private func collectedEvents(from id: ObjectIdentifier) {
        guard let b = builder, ObjectIdentifier(b) == id,
              phase == .running || phase == .paused else { return }
        let after = lastMotionAt ?? .distantPast
        var motions: [(paused: Bool, at: Date)] = []
        for e in b.workoutEvents {
            let at = e.dateInterval.start
            guard at > after else { continue }
            switch e.type {
            case .motionPaused:
                motions.append((paused: true, at: at))
            case .motionResumed:
                motions.append((paused: false, at: at))
            default:
                break
            }
        }
        motions.sort { $0.at < $1.at }
        for m in motions {
            motionEvent(paused: m.paused, at: m.at)
        }
    }

    // MARK: - 內部：session 的回呼（照順序）

    private func handle(_ event: WorkoutSessionEvent) async {
        switch event {
        case .state(let state, from: let prior, date: let date, session: let id):
            guard isCurrent(id) else { return }
            await sessionChanged(to: state, from: prior, at: date)
        case .motion(paused: let paused, date: let date, session: let id):
            guard isCurrent(id) else { return }
            motionEvent(paused: paused, at: date)
        case .failed(let message, session: let id):
            guard isCurrent(id) else { return }
            sessionFailed(message)
        }
    }

    /// 是現在這一趟的 session（換運動收掉的、存好放掉的不算）
    private func isCurrent(_ id: ObjectIdentifier) -> Bool {
        guard let s = session else { return false }
        return ObjectIdentifier(s) == id
    }

    private func sessionChanged(to state: HKWorkoutSessionState, from prior: HKWorkoutSessionState,
                                at date: Date) async {
        switch state {
        case .paused:
            manualPaused(at: date)
        case .running:
            manualResumed(at: date)
        case .stopped:
            guard phase == .running || phase == .paused || phase == .ending else { return }
            if phase != .ending {
                // 不是你按的結束（系統停的）：一樣收尾
                phase = .ending
                kmFlash = nil
                WatchRunVoice.shared.stopAll()
            }
            await finishCollection(at: date)
        case .ended:
            if phase == .preparing || phase == .countdown {
                // prepare 過的 session 被系統收掉（放太久）：按〔開始〕時再建一個
                session = nil
                builder = nil
                sessionSport = nil
            } else if phase == .running || phase == .paused || phase == .ending {
                // 沒經過「已停止」就結束了：照樣收尾（存不進去就留在手錶上〔再存一次〕）
                if phase != .ending { phase = .ending }
                await finishCollection(at: date)
            }
        default:
            break
        }
    }

    private func sessionFailed(_ message: String) {
        problem = "運動紀錄出錯：" + message
        if phase == .preparing || phase == .countdown {
            // prepare 過的那個壞了（例：換運動剛收掉的那個還沒結束完）：收掉，數完 startRun 會建新的
            endPreparedSession()
        }
    }

    // MARK: - 內部：收尾、存進 Apple 健康

    /// .stopped 之後：路線停、endCollection、組好這一趟 → 不到 60 秒問；不然存
    private func finishCollection(at date: Date) async {
        guard !finishing else { return }
        finishing = true
        ticker?.cancel()
        ticker = nil
        flashTask?.cancel()
        kmFlash = nil
        RouteRecorder.shared.stop()
        let end = max(date, startDate ?? date)
        var moving = prevSeconds
        if let b = builder {
            do {
                _ = try await b.endCollection(at: end)
            } catch {
                // 收不起來照樣往下（finishWorkout 會再說一次為什麼）
            }
            let s = b.elapsedTime(at: end)
            if s.isFinite && s > 0 { moving = s }
            updateStats(from: b, seconds: moving, announce: false)
        }
        let r = WatchRunRecord(id: runId, sport: sport, start: startDate ?? end, end: end,
                               movingSeconds: moving, meters: meters, kcal: kcal,
                               heartAvg: heartAvg, heartMax: heartMax, kmTimes: kmTimes, pauses: pauses,
                               points: RouteRecorder.shared.points, workoutId: nil, savedAt: nil, updatedAt: Date())
        result = r
        RunStash.saveCurrent(r)
        if WatchRunText.isShort(r) {
            phase = .askShort
            return
        }
        await saveLive()
    }

    /// 附註 → finishWorkout → session.end() → 路線收尾 → 摘要；丟錯：留在手錶（unsaved）〔再存一次〕
    private func saveLive() async {
        phase = .ending
        guard var r = result else {
            finishing = false
            phase = .idle
            return
        }
        guard let b = builder else {
            session?.end()
            keepUnsaved(&r, reason: "這一趟的運動紀錄不見了")
            showSummary(r)
            return
        }
        do {
            _ = try await b.addMetadata(runMetadata(kmTimes: r.kmTimes, pauses: r.pauses))
        } catch {
            // 附註寫不進去不擋：運動照存（iPhone 帶進來時用路線推算分段）
        }
        do {
            let w = try await b.finishWorkout()
            session?.end()
            let now = Date()
            r.savedAt = now
            r.updatedAt = now
            saved = true
            if let w {
                savedWorkout = w
                r.workoutId = w.uuid.uuidString
                savedRoute = await RouteRecorder.shared.finishRoute(for: w, healthStore: healthStore)
            }
            // w 是 nil（文件：存好了但讀不到那一筆）：saved 照樣 true，③ 不自己加（等 iPhone 帶進來）
            WatchRunLog.upsert(logEntry(r, saved: w != nil), now: now)
            RunStash.clearCurrent()
            play(.success)
        } catch {
            session?.end()
            keepUnsaved(&r, reason: error.localizedDescription)
        }
        showSummary(r)
    }

    /// 存不進去：那一趟留在手錶（RunStash.unsaved），③ 一行、摘要〔再存一次〕
    private func keepUnsaved(_ r: inout WatchRunRecord, reason: String) {
        let now = Date()
        r.savedAt = nil
        r.workoutId = nil
        r.updatedAt = now
        unsaved = r
        RunStash.saveUnsaved(r)
        RunStash.clearCurrent()
        saved = false
        problem = "Apple 健康：" + reason
        WatchRunLog.upsert(logEntry(r, saved: false), now: now)
        play(.failure)
    }

    /// 摘要：小圖算一次、放掉 session 與 builder
    private func showSummary(_ r: WatchRunRecord) {
        result = r
        resultShape = WatchRunMath.routeShape(r.points, kmTimes: r.kmTimes, sport: r.sport,
                                              movingSeconds: r.movingSeconds, meters: r.meters)
        summarySince = Date()
        session = nil
        builder = nil
        sessionSport = nil
        finishing = false
        phase = .summary
    }

    /// LifeGood 附註（iPhone 帶進來時讀）：recorder「watch 25.580」、kmTimes（空的不放）、每次暫停是不是自動的（沒暫停不放）
    private func runMetadata(kmTimes: [Double], pauses: [WatchRunPause]) -> [String: Any] {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        var meta: [String: Any] = [WatchRunMeta.recorderKey: WatchRunMeta.recorder(version: version)]
        if !kmTimes.isEmpty {
            meta[WatchRunMeta.kmTimesKey] = WatchRunMeta.encodeTimes(kmTimes)
        }
        if !pauses.isEmpty {
            meta[WatchRunMeta.autoPausesKey] = WatchRunMeta.encodeFlags(pauses.map { $0.auto })
        }
        return meta
    }

    private func logEntry(_ r: WatchRunRecord, saved: Bool) -> WatchRunLogEntry {
        WatchRunLogEntry(id: r.id, workoutId: r.workoutId, sport: r.sport.rawValue, start: r.start,
                         end: r.end ?? r.updatedAt, movingSeconds: r.movingSeconds, meters: r.meters, saved: saved)
    }

    private func canShare(_ type: HKObjectType) -> Bool {
        healthStore.authorizationStatus(for: type) == .sharingAuthorized
    }

    /// 〔再存一次〕：非 live 的 HKWorkoutBuilder 照存檔補（同 iPhone HealthKitManager.saveWorkout 的寫法）
    private func saveAgain(_ original: WatchRunRecord) async {
        var r = original
        let end = max(r.end ?? r.updatedAt, r.start)
        let b = HKWorkoutBuilder(healthStore: healthStore, configuration: Self.configuration(for: r.sport), device: .local())
        do {
            _ = try await b.beginCollection(at: r.start)
            let samples = retrySamples(r, end: end)
            if !samples.isEmpty {
                _ = try await b.addSamples(samples)
            }
            let events = pauseEvents(r.pauses, start: r.start, end: end)
            if !events.isEmpty {
                do {
                    _ = try await b.addWorkoutEvents(events)
                } catch {
                    // 暫停寫不進去頂多「健身」App 的時間含暫停，不連累整筆
                }
            }
            do {
                _ = try await b.addMetadata(runMetadata(kmTimes: r.kmTimes, pauses: r.pauses))
            } catch {
                // 附註寫不進去不擋
            }
            _ = try await b.endCollection(at: end)
            let w = try await b.finishWorkout()
            let now = Date()
            r.end = end
            r.savedAt = now
            r.updatedAt = now
            var route: HKWorkoutRoute?
            if let w {
                r.workoutId = w.uuid.uuidString
                route = await RouteRecorder.shared.saveRoute(r.points, for: w, healthStore: healthStore)
            }
            unsaved = nil
            RunStash.clearUnsaved()
            WatchRunLog.upsert(logEntry(r, saved: w != nil), now: now)
            problem = nil
            if phase == .summary, result?.id == r.id {
                result = r
                saved = true
                savedWorkout = w
                savedRoute = route
            }
            play(.success)
        } catch {
            problem = "Apple 健康：" + error.localizedDescription
            play(.failure)
        }
    }

    /// 補存的距離、大卡：只放有給寫入的那幾種（addSamples 只要有一種沒權限整筆都存不進去；同 iPhone canShare）
    private func retrySamples(_ r: WatchRunRecord, end: Date) -> [HKSample] {
        var out: [HKSample] = []
        let distanceType = r.sport == .bike ? HKQuantityType(.distanceCycling) : HKQuantityType(.distanceWalkingRunning)
        if r.meters.isFinite, r.meters > 0, canShare(distanceType) {
            let q = HKQuantity(unit: .meter(), doubleValue: r.meters)
            out.append(HKQuantitySample(type: distanceType, quantity: q, start: r.start, end: end))
        }
        let energyType = HKQuantityType(.activeEnergyBurned)
        if r.kcal.isFinite, r.kcal > 0, canShare(energyType) {
            let q = HKQuantity(unit: .kilocalorie(), doubleValue: r.kcal)
            out.append(HKQuantitySample(type: energyType, quantity: q, start: r.start, end: end))
        }
        return out
    }

    /// 結束了的暫停一組「暫停」＋「繼續」（零長度的時間點；夾在開始～結束之間）
    private func pauseEvents(_ pauses: [WatchRunPause], start: Date, end: Date) -> [HKWorkoutEvent] {
        var out: [HKWorkoutEvent] = []
        for p in pauses {
            guard let pauseEnd = p.end else { continue }
            let from = min(max(p.start, start), end)
            let to = min(max(pauseEnd, from), end)
            guard to > from else { continue }
            out.append(HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: from, duration: 0), metadata: nil))
            out.append(HKWorkoutEvent(type: .resume, dateInterval: DateInterval(start: to, duration: 0), metadata: nil))
        }
        return out
    }

    // MARK: - 內部：當機接回

    /// 接回系統還留著的那個 session
    private func attach(_ s: HKWorkoutSession) {
        if let current = session, current === s, phase == .running || phase == .paused { return }
        guard phase == .idle || phase == .preparing || phase == .countdown else { return }
        let state = s.state
        guard state == .running || state == .paused || state == .stopped else {
            if state == .prepared || state == .notStarted { s.end() }
            return
        }
        countdownTask?.cancel()
        countdownTask = nil
        if let old = session, old !== s { old.end() }
        RouteRecorder.shared.cool()
        let b = s.associatedWorkoutBuilder()
        s.delegate = self
        b.delegate = self
        b.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: s.workoutConfiguration)
        session = s
        builder = b
        let sp = Self.watchSport(for: s.workoutConfiguration.activityType)
        sport = sp
        sessionSport = sp
        let begun = s.startDate ?? b.startDate
        let stash = takeRecord(for: begun)
        resetLiveNumbers()
        runId = stash?.id ?? UUID()
        if let cp = stash {
            kmTimes = cp.kmTimes
            pauses = cp.pauses
            meters = cp.meters
            kcal = cp.kcal
            heartAvg = cp.heartAvg
            heartMax = cp.heartMax
            prevMeters = cp.meters
            prevSeconds = cp.movingSeconds
        }
        startDate = begun ?? stash?.start ?? Date()
        let points = stash?.points ?? []
        RouteRecorder.shared.restore(points: points)
        let nextSeg = (points.last?.seg ?? -1) + 1
        // 接回的那一趟：路線一律收尾時用獨立的 builder 插全部的點（接回後的 seriesBuilder 只有後半段）
        RouteRecorder.shared.begin(routeBuilder: nil,
                                   moving: { [weak self] d in self?.movingSeconds(at: d) ?? 0 }, seg: nextSeg)
        let now = Date()
        autoPaused = false
        // [裁定] 接回的 builder 裡當機前的自動暫停事件不重播（暫停已經從存檔接回；只聽這一刻以後的）
        lastMotionAt = now
        if state == .paused {
            if !hasOpenPause {
                pauses.append(WatchRunPause(start: now, auto: false))
            }
            pausedSince = pauses.last?.start ?? now
            phase = .paused
        } else {
            closeOpenPause(at: now)
            pausedSince = nil
            phase = .running
        }
        syncRoutePause()
        quietNextDistance = true
        finishing = false
        pendingCheckpoint = nil
        result = nil
        resultShape = []
        saved = false
        savedWorkout = nil
        savedRoute = nil
        problem = nil
        recoveredUntil = now.addingTimeInterval(WatchRunText.flashSeconds)
        if state == .stopped {
            // 當機時已經按了結束：直接收尾、存
            phase = .ending
            Task { @MainActor in
                await self.finishCollection(at: now)
            }
            return
        }
        checkpoint(now: now)
        startTicker()
    }

    /// 接回時拿回同一趟的存檔：跑步中那一份、或已經變成「沒存成」的那一份（開始時間差 5 秒內；系統沒給開始時間就只認跑步中那一份）
    private func takeRecord(for begun: Date?) -> WatchRunRecord? {
        if let cp = pendingCheckpoint, Self.sameRun(cp, begun) {
            return cp
        }
        if let u = unsaved, u.savedAt == nil, begun != nil, Self.sameRun(u, begun) {
            unsaved = nil
            RunStash.clearUnsaved()
            return u
        }
        return nil
    }

    private static func sameRun(_ r: WatchRunRecord, _ begun: Date?) -> Bool {
        guard let begun else { return true }
        return abs(r.start.timeIntervalSince(begun)) <= 5
    }

    /// 系統沒接回（session 已經沒了）：那一份跑步中存檔變成「沒存成」（結束＝最後一次存檔；不到 1 分鐘的直接丟）。
    /// 準備頁、倒數中也收（這一趟還沒寫存檔）；force＝這一趟要開始了（startRun：不等 5 秒，免得這一趟的存檔蓋掉當機那一份）
    private func settleStaleCheckpoint(now: Date, force: Bool = false) {
        guard var r = pendingCheckpoint, !recovering else { return }
        if !force {
            guard phase == .idle || phase == .preparing || phase == .countdown,
                  now.timeIntervalSince(launchedAt) > 5 else { return }
        }
        pendingCheckpoint = nil
        let end = max(r.end ?? r.updatedAt, r.start)
        r.end = end
        if !(r.movingSeconds.isFinite && r.movingSeconds > 0) {
            let paused = r.pauses.reduce(0.0) { $0 + $1.seconds }
            r.movingSeconds = max(0, r.wallSeconds(now: end) - paused)
        }
        RunStash.clearCurrent()
        guard !WatchRunText.isShort(r) else { return }
        r.savedAt = nil
        r.workoutId = nil
        r.updatedAt = now
        unsaved = r
        RunStash.saveUnsaved(r)
        WatchRunLog.upsert(logEntry(r, saved: false), now: now)
    }

    // MARK: - 震動

    /// 倒數 .click、開始／繼續 .start、暫停（手動、自動）.stop、每公里 .notification、存好 .success、存不進去 .failure
    private func play(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }
}

// MARK: - HealthKit 的 delegate（在背景佇列叫：一律 nonisolated＋Task { @MainActor in }／排進 workoutSessionEvents；照 Apple 範例）

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {
        workoutSessionEvents.continuation.yield(
            .state(toState, from: fromState, date: date, session: ObjectIdentifier(workoutSession)))
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        workoutSessionEvents.continuation.yield(
            .failed(error.localizedDescription, session: ObjectIdentifier(workoutSession)))
    }

    /// 手錶的自動暫停：motionPaused／motionResumed（你按的暫停走 didChangeTo，這裡不理 pause／resume）
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didGenerate event: HKWorkoutEvent) {
        let id = ObjectIdentifier(workoutSession)
        let at = event.dateInterval.start
        switch event.type {
        case .motionPaused:
            workoutSessionEvents.continuation.yield(.motion(paused: true, date: at, session: id))
        case .motionResumed:
            workoutSessionEvents.continuation.yield(.motion(paused: false, date: at, session: id))
        default:
            break
        }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        // 只交編號過去：主執行緒當下再讀 statistics（不把 HealthKit 物件帶過隔離）
        let id = ObjectIdentifier(workoutBuilder)
        Task { @MainActor in
            self.collected(from: id)
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // [裁定] 手錶的自動暫停也從這裡聽（session 的 didGenerate 沒來時的保險；同一個事件只算一次，見 motionEvent）。
        // 你按的暫停、繼續照舊只看 session 的 didChangeTo。只交編號過去，主執行緒當下再讀 workoutEvents
        let id = ObjectIdentifier(workoutBuilder)
        Task { @MainActor in
            self.collectedEvents(from: id)
        }
    }
}
