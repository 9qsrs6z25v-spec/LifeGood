import Foundation
import ActivityKit
import UIKit
import UserNotifications

// MARK: - 跑步即時動態 · App 這一側（健康 v6，v25.556）
//
// 規格：scratchpad/health/judge.md §4.4、§6 v6；health/build/v6/brief.md §G3（推送節流照 build/v6/sim_v6.py §6 的 ActivityPusher 逐行寫）。
// 只屬於 App target（A01C000001000002）。小工具那一側是 LifeGoodWidgets/RunLiveActivity.swift，資料是共用檔 RunActivityAttributes.swift。
//
// 誰叫這裡（主控契約，簽章不准改）：
// • RunTracker（G1）：start(sport:) 最後 began(self)；ticker 跑步中每秒 tick(self)；pause() 最後 paused(self)；
//   resume() 最後 resumed(self)；finish() 交出成果之前 finished(result)；cancel() 最後 cancelled()。
// • LifeGoodApp（G3）：init 登記 RunPauseBridge → handlePauseButton(pause:runId:)；.task 一開始 endLeftovers(keeping:)；
//   scenePhase 變 .active 時 appBecameActive()。
//
//
// 怎麼做（brief §G3-1～G3-10）：
// • 開：按開始那一刻先記下還在的（上一趟的「完成」、App 被關掉後的殘留），開新的之後一個一個馬上收；
//   打包出來的 Info.plist 有 NSSupportsLiveActivities、系統的即時動態開著才開，開不起來（try?）默默略過。
// • 推：時間不推（小工具 Text(timerInterval:) 自己走）；距離、第三格照 ActivityPusher.tick 節流；暫停、繼續馬上推。
//   每一次 update／end 都排在上一次後面（pending 串），不會後推的先到。staleDate 每次推都往後延 5 分鐘。
// • 收：完成換「完成」那張、15 分鐘後自己收（.after）；放棄馬上收。自己收之前先停掉 stateWatch（不要被當成使用者滑掉）。
// • 使用者在鎖定畫面滑掉（.dismissed）：這一趟不再開；系統 8 小時收掉（.ended）：回前景再開；快 8 小時（前景）收舊開新。
// • 暫停 30 分鐘：鎖定畫面那一行靠 staleDate（共用檔）；本機通知只在已經有權限時排（不新問），世代守門。

@MainActor
final class RunActivityCenter {

    static let shared = RunActivityCenter()

    // MARK: 主控定的數字（sim_v6.py §6 照這幾個數驗過；不准改）

    /// 跑步的即時動態優先序（今日行程 DayTimelineController 是 50）：同時開著時靈動島放跑步
    static let relevanceScore: Double = 100
    /// 距離、第三格：內容有變、離上次推滿 10 秒就推
    static let pushEverySeconds: TimeInterval = 10
    /// 或走了 50 公尺、而且離上次推至少 5 秒
    static let pushMinSeconds: TimeInterval = 5
    static let pushEveryMeters: Double = 50
    /// 內容沒變（紅燈站著）也每 60 秒推一次：staleDate 往後延，鎖定畫面不會誤寫「好一陣子沒更新了」
    static let heartbeatSeconds: TimeInterval = 60
    /// 完成之後鎖定畫面留多久（ActivityUIDismissalPolicy.after；系統上限 4 小時）
    static let finishedLingerSeconds: TimeInterval = 15 * 60
    /// 一個即時動態最長 8 小時：7 小時 50 分時（App 在前景）收掉舊的、開新的
    static let renewAfterSeconds: TimeInterval = 7 * 3600 + 50 * 60
    /// 暫停 30 分鐘提醒那一則本機通知的 id（RunActivityAttributes.pauseRemindSeconds 後響）
    static let pauseReminderId = "run_pause_reminder"

    /// [G3] 開不起來、被系統收掉（沒有 activity）時，App 在前景每隔多久再試一次（keepAlive）
    private static let retryRequestSeconds: TimeInterval = 60

    /// [G3] 打包出來的 Info.plist 真的有 NSSupportsLiveActivities 才為 true（照 RunTracker.hasLocationBackgroundMode 的寫法）：
    /// 沒有就整個略過，不呼叫 Activity.request
    private static let hasLiveActivitiesKey: Bool = {
        Bundle.main.object(forInfoDictionaryKey: "NSSupportsLiveActivities") as? Bool ?? false
    }()

    // MARK: 狀態（brief §G3-1）

    /// 正在記錄的那一趟的即時動態；沒開、開不起來、被滑掉、被系統收掉、已經結束是 nil
    private var activity: Activity<RunActivityAttributes>?
    /// 這一個即時動態是什麼時候開的（8 小時上限前重開用）
    private var activityStartedAt: Date?
    /// 上一次真的推出去的時間、距離、整公里、內容（節流：sim_v6.py ActivityPusher 的 last_at／last_m／last_km／last_state）
    private var lastPushAt = Date.distantPast
    private var lastPushMeters: Double = 0
    private var lastPushKm = 0
    private var lastState: RunActivityAttributes.ContentState?
    /// 最近一次 update／end：一個接一個照順序送（後推的不會先到）
    private var pending: Task<Void, Never>?
    /// 看著現在這一個：使用者在鎖定畫面滑掉（.dismissed）、系統 8 小時收掉（.ended）
    private var stateWatch: Task<Void, Never>?
    /// 這一趟被使用者在鎖定畫面滑掉了：這一趟不再開（下一趟 began 重設）
    private var userDismissed = false
    /// 上一次叫 request 的時間（開不起來時 App 在前景每 60 秒才再試一次）
    private var lastRequestAt = Date.distantPast
    /// 暫停 30 分鐘提醒的世代：排之前、排的時候剛好按了繼續／結束，舊的那一次就不排（或排好再拿掉）
    private var reminderGen = 0
    /// 現在要的那一則提醒是第幾代（暫停中）；不要了（繼續、完成、放棄、清殘留）是 nil。
    /// 排好之後只在「已經不要了」時才拿掉：同一個 id，剛好又按了暫停的那一則不會被舊的那一次順手拿掉
    private var reminderWantedGen: Int?

    private init() {}

    // MARK: RunTracker 叫的

    /// 按開始那一刻（App 一定在前景）：先收掉殘留的跑步即時動態，再開一個新的（relevanceScore 100）。
    /// 系統的「即時動態」關著、打包出來的 Info.plist 沒有 NSSupportsLiveActivities、開不起來：默默略過，不擋跑步
    func began(_ tracker: RunTracker) {
        let now = Date()
        userDismissed = false
        cancelReminder()                                   // 保險：上一趟留下來的 30 分鐘提醒
        stateWatch?.cancel()
        stateWatch = nil
        activity = nil
        activityStartedAt = nil
        lastState = nil
        lastPushAt = .distantPast
        lastPushMeters = 0
        lastPushKm = 0
        // 現在還在的（上一趟留著的「完成」、App 被關掉後留下來的那一張）先記下來，新的開好之後一個一個馬上收掉
        let olds = Activity<RunActivityAttributes>.activities
        request(tracker, now: now)
        let keepId = activity?.id
        let previous = pending
        pending = Task {
            await previous?.value
            for old in olds where old.id != keepId {
                await old.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// 跑步中每秒（RunTracker 的 ticker）：照 sim_v6.py ActivityPusher.tick 的規則決定要不要真的推
    /// （內容有變而且滿 10 秒、或走了 50 公尺而且滿 5 秒；過整公里那一秒；內容沒變也每 60 秒一次）
    func tick(_ tracker: RunTracker) {
        guard tracker.phase == .running else { return }
        let now = Date()
        if UIApplication.shared.applicationState == .active { keepAlive(tracker, now: now) }   // 8 小時重開、開不起來的再試（只在前景）
        guard activity != nil else { return }
        let state = makeState(tracker)
        let since = now.timeIntervalSince(lastPushAt)
        let km = Self.wholeKm(tracker.distanceMeters)
        let moved = tracker.distanceMeters - lastPushMeters
        let changed = state != lastState
        let byTime = changed && since >= Self.pushEverySeconds
        let byDistance = changed && moved >= Self.pushEveryMeters && since >= Self.pushMinSeconds
        guard km != lastPushKm || since >= Self.heartbeatSeconds || byTime || byDistance else { return }
        push(state, now: now, distance: tracker.distanceMeters)
    }

    /// 按暫停那一刻（畫面上的鈕、鎖定畫面的鈕、「太短要存嗎？」前的暫停都會到這裡）：馬上推「已暫停」、排 30 分鐘提醒
    func paused(_ tracker: RunTracker) {
        push(makeState(tracker), now: Date(), distance: tracker.distanceMeters)
        let sport = WorkoutSport(tracker.sport)
        let title = WorkoutFacts.timeOfDayName(sport, start: tracker.activeStartedAt ?? Date())
        scheduleReminder(title: title)
    }

    /// 按繼續那一刻：馬上推、取消 30 分鐘提醒
    func resumed(_ tracker: RunTracker) {
        cancelReminder()
        push(makeState(tracker), now: Date(), distance: tracker.distanceMeters)
    }

    /// 按完成（RunTracker.finish 算好成果之後）：換成「完成　5.20 公里・32:10・6'11"」，15 分鐘後自己收；取消 30 分鐘提醒。
    /// 結束那一刻系統就把它從靈動島拿掉，今日行程（50）自己回來
    func finished(_ result: RunResult) {
        cancelReminder()
        let content = ActivityContent(state: finishedState(result),
                                      staleDate: nil,
                                      relevanceScore: Self.relevanceScore)
        let until = Date().addingTimeInterval(Self.finishedLingerSeconds)
        endCurrent(content, policy: .after(until))
    }

    /// 放棄這一趟、太短不存：馬上收掉；取消 30 分鐘提醒
    func cancelled() {
        cancelReminder()
        endCurrent(nil, policy: .immediate)
    }

    // MARK: App、intent 叫的

    /// App 啟動（LifeGoodApp .task）、鎖定畫面按到不是正在記錄的那一趟：收掉 runId 不是 keeping 的跑步即時動態（馬上收）；
    /// keeping 是 nil（沒在記錄）時也取消 30 分鐘提醒。「完成」那張已經結束（.ended），留著讓它 15 分鐘後自己收
    func endLeftovers(keeping runId: UUID?) async {
        let keep = runId?.uuidString
        if runId == nil { cancelReminder() }
        // 剛按完成的那一張先換成「完成」（變成 .ended），下面才不會被當成殘留收掉
        await pending?.value
        for a in Activity<RunActivityAttributes>.activities where a.attributes.runId != keep {
            let s = a.activityState
            guard s == .active || s == .stale else { continue }
            await a.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// 鎖定畫面／靈動島的暫停鈕（RunPauseBridge 的處理者）：是正在記錄的那一趟才暫停／繼續，等推送送出才回；
    /// 不是（App 被關掉後留下來的殘留）就收掉殘留。不擋訂閱（已經在跑的那一趟一定讓你存完）
    func handlePauseButton(pause: Bool, runId: String) async {
        let tracker = RunTracker.shared
        guard let id = tracker.activeRunId, id.uuidString == runId else {
            // App 被關掉後留下的那一張：只收掉；救回交給下次打開 App 的「有一趟運動還沒存」
            await endLeftovers(keeping: tracker.activeRunId)
            return
        }
        reconcile()                                        // [審查] intent 剛把 App 叫醒：看著它的那一條可能還沒處理到 .ended／.dismissed
        if pause && tracker.phase == .running {
            tracker.pause()                                // → paused(_:)：馬上推「已暫停」、排提醒
        } else if !pause && tracker.phase == .paused {
            tracker.resume()                               // → resumed(_:)：馬上推「跑步中」、取消提醒
        } else {
            // 按到舊畫面的鈕（已經暫停了又按暫停）：推一次現在的樣子，鈕換回對的
            push(makeState(tracker), now: Date(), distance: tracker.distanceMeters)
        }
        // [審查] 這一趟的那一張已經被系統收掉（8 小時，App 在背景，.ended 還掛在鎖定畫面、鈕還按得到）：
        // 上面推不出去，鎖定畫面會一直寫「跑步中」。LiveActivityIntent 的 perform 裡系統准開新的（Apple 文件），
        // 就在這裡開一張現在的樣子（request 會把同一趟的舊卡收掉）；開不起來 try? 默默略過。使用者滑掉的不開
        if activity == nil && !userDismissed {
            request(tracker, now: Date())
        }
        await flush()                                      // 推上去了 intent 才回，系統才重畫
    }

    /// 等最近一次推送（update／end）送出
    func flush() async {
        await pending?.value
    }

    /// App 回到前景（LifeGoodApp 的 scenePhase .active）：正在記錄、即時動態不見了（一開始系統關著後來打開、
    /// 8 小時被系統收掉、開的時候失敗）而且不是使用者自己滑掉的 → 重開；快 8 小時了 → 收掉舊的開新的
    func appBecameActive() {
        let tracker = RunTracker.shared
        guard tracker.isActive else { return }
        reconcile()                                        // 保險：看著它的那一條還沒來得及處理（App 剛醒），先照它現在的狀態對一次
        let now = Date()
        if activity == nil && !userDismissed {
            request(tracker, now: now)                     // 回前景就開（不等 60 秒）
        } else {
            keepAlive(tracker, now: now)
        }
    }

    // MARK: - 內部：開、推、收

    /// 開一個新的（brief §G3-2）。只在前景叫（began、keepAlive、appBecameActive）：Activity.request 在背景會被系統擋；
    /// 例外是 handlePauseButton（在 LiveActivityIntent 的 perform 裡，系統准開，Apple 文件 LiveActivityIntent）
    private func request(_ tracker: RunTracker, now: Date) {
        lastRequestAt = now
        guard Self.hasLiveActivitiesKey,
              ActivityAuthorizationInfo().areActivitiesEnabled,
              let id = tracker.activeRunId,
              let start = tracker.activeStartedAt else { return }
        // 名字只用時段名（「晨跑」），不用沿用來的名字（常常就是地名）；不放路線、不放地點
        let title = WorkoutFacts.timeOfDayName(WorkoutSport(tracker.sport), start: start)
        let attributes = RunActivityAttributes(runId: id.uuidString,
                                               sport: RunActivitySport(tracker.sport),
                                               title: title,
                                               startedAt: start)
        let state = makeState(tracker)
        let content = ActivityContent(state: state,
                                      staleDate: RunActivityAttributes.staleDate(state, now: now),
                                      relevanceScore: Self.relevanceScore)
        // 開不起來（系統關著、超過同時幾個的上限、iPad）：默默略過，跑步照常
        guard let a = try? Activity<RunActivityAttributes>.request(attributes: attributes,
                                                                    content: content,
                                                                    pushType: nil) else { return }
        activity = a
        activityStartedAt = now
        remember(state, now: now, distance: tracker.distanceMeters)
        watch(a)
        // 同一趟之前那一張（系統 8 小時收掉、還掛在鎖定畫面上的；重開時剛收的）：新的開好了就馬上拿掉，鎖定畫面不會有兩張
        let runKey = id.uuidString
        let sameRun = Activity<RunActivityAttributes>.activities.filter { old in
            old.id != a.id && old.attributes.runId == runKey
        }
        guard !sameRun.isEmpty else { return }
        let previous = pending
        pending = Task {
            await previous?.value
            for old in sameRun {
                await old.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// 真的推一次（brief §G3-5）：記下這一次（節流用），排在上一次 update／end 後面送
    private func push(_ state: RunActivityAttributes.ContentState, now: Date, distance: Double) {
        guard let a = activity else { return }
        let content = ActivityContent(state: state,
                                      staleDate: RunActivityAttributes.staleDate(state, now: now),
                                      relevanceScore: Self.relevanceScore)
        remember(state, now: now, distance: distance)
        let previous = pending
        pending = Task {
            await previous?.value
            await a.update(content)
        }
    }

    /// sim_v6.py ActivityPusher.push 的那四行
    private func remember(_ state: RunActivityAttributes.ContentState, now: Date, distance: Double) {
        lastPushAt = now
        lastPushMeters = distance
        lastPushKm = Self.wholeKm(distance)
        lastState = state
    }

    /// 收掉現在這一個（brief §G3-6）：先不看它（自己收掉的不要被當成使用者滑掉），再排在上一次後面 end
    private func endCurrent(_ content: ActivityContent<RunActivityAttributes.ContentState>?,
                            policy: ActivityUIDismissalPolicy) {
        stateWatch?.cancel()
        stateWatch = nil
        guard let a = activity else { return }
        activity = nil
        activityStartedAt = nil
        lastState = nil
        let previous = pending
        pending = Task {
            await previous?.value
            await a.end(content, dismissalPolicy: policy)
        }
    }

    /// 看著它（照 DayTimelineController.watch(_:)）：使用者在鎖定畫面滑掉 → 這一趟不再開；系統 8 小時收掉 → 回前景再開
    private func watch(_ a: Activity<RunActivityAttributes>) {
        stateWatch?.cancel()
        let id = a.id
        stateWatch = Task { [weak self] in
            for await s in a.activityStateUpdates {
                if s == .dismissed {
                    self?.activityGone(id, byUser: true)
                    return
                }
                if s == .ended {
                    self?.activityGone(id, byUser: false)
                    return
                }
            }
        }
    }

    /// 看著它的那一條還沒來得及處理（App 剛醒、intent 剛把 App 叫起來）：照現在這一張的狀態先對一次
    /// （.dismissed＝使用者滑掉、.ended＝系統收掉；appBecameActive、handlePauseButton 用）
    private func reconcile() {
        guard let a = activity else { return }
        let s = a.activityState
        if s == .dismissed {
            activityGone(a.id, byUser: true)
        } else if s == .ended {
            activityGone(a.id, byUser: false)
        }
    }

    /// 是現在這一個才清（重開時舊的那一個結束不算）
    private func activityGone(_ id: String, byUser: Bool) {
        guard let a = activity, a.id == id else { return }
        activity = nil
        activityStartedAt = nil
        lastState = nil
        stateWatch?.cancel()                               // [審查] appBecameActive 對帳時叫到的：還在等的那一條也停掉（從 watch 裡叫到的，停掉自己也沒事，下一行就 return）
        stateWatch = nil
        if byUser { userDismissed = true }
    }

    /// 8 小時重開、開不起來的再試（brief §G3-8）。只在 App 在前景時叫（tick 裡、appBecameActive 裡）
    private func keepAlive(_ tracker: RunTracker, now: Date) {
        if activity != nil {
            guard let started = activityStartedAt,
                  now.timeIntervalSince(started) >= Self.renewAfterSeconds else { return }
            endCurrent(nil, policy: .immediate)            // 快 8 小時：收掉舊的、開新的
            request(tracker, now: now)
            return
        }
        guard !userDismissed,
              now.timeIntervalSince(lastRequestAt) >= Self.retryRequestSeconds else { return }
        request(tracker, now: now)
    }

    // MARK: - 內部：字（sim_v6.py make_state、finished_line）

    /// 鎖定畫面、靈動島的內容（brief §G3-3）：記錄中第三格是「這一公里」（騎車「時速」），暫停中改成平均。
    /// [v25.557] 自動暫停中多帶 autoPaused（標題「晨跑・自動暫停」；第三格照暫停寫平均）
    private func makeState(_ tracker: RunTracker) -> RunActivityAttributes.ContentState {
        let sport = WorkoutSport(tracker.sport)
        let meters = tracker.distanceMeters
        let distanceText = WorkoutFormat.preciseKmNumber(meters / 1000, sport: sport)
        let clockStart = tracker.movingClockStart ?? Date()
        if tracker.phase == .paused {
            let third: String
            let label: String
            if sport == .bike {
                let kmh = WorkoutFormat.speedKmh(km: meters / 1000, minutes: tracker.elapsed / 60)
                third = kmh.map { WorkoutFormat.speedNumber($0) } ?? "—"
                label = "平均時速"
            } else {
                third = WorkoutFormat.pace(tracker.paceMinPerKm)
                label = "平均配速"
            }
            return RunActivityAttributes.ContentState(phase: .paused,
                                                      distanceText: distanceText,
                                                      clockStart: clockStart,
                                                      pausedAt: tracker.pausedAt,
                                                      thirdText: third,
                                                      thirdLabel: label,
                                                      autoPaused: tracker.autoPaused ? true : nil)
        }
        let third: String
        let label: String
        if sport == .bike {
            third = tracker.recentSpeedKmh.map { WorkoutFormat.speedNumber($0) } ?? "—"
            label = "時速"
        } else {
            third = WorkoutFormat.pace(tracker.recentPaceMinPerKm)
            label = "這一公里"
        }
        return RunActivityAttributes.ContentState(phase: .running,
                                                  distanceText: distanceText,
                                                  clockStart: clockStart,
                                                  pausedAt: nil,
                                                  thirdText: third,
                                                  thirdLabel: label)
    }

    /// 完成那一張（brief §G3-4）：「5.20 公里・32:10・6'11"」（騎車「23.4 公里・1:05:12・時速 21.5」）；
    /// 時間停在移動時間（clockStart＝結束時間往前推移動時間、pausedAt＝結束時間），第三格同暫停（平均）
    private func finishedState(_ r: RunResult) -> RunActivityAttributes.ContentState {
        let sport = WorkoutSport(r.sport)
        let km = r.distanceKm
        let minutes = r.movingMinutes
        let kmText = WorkoutFormat.preciseKmNumber(km, sport: sport)
        let clockText = WorkoutFormat.clock(minutes: minutes)
        let head = kmText + " 公里・" + clockText + "・"
        let third: String
        let label: String
        let line: String
        if sport == .bike {
            let kmh = WorkoutFormat.speedKmh(km: km, minutes: minutes)
            third = kmh.map { WorkoutFormat.speedNumber($0) } ?? "—"
            label = "平均時速"
            line = head + "時速 " + third
        } else {
            third = WorkoutFormat.pace(km: km, minutes: minutes)
            label = "平均配速"
            line = head + third
        }
        let clockStart = r.endedAt.addingTimeInterval(-minutes * 60)
        return RunActivityAttributes.ContentState(phase: .finished,
                                                  distanceText: kmText,
                                                  clockStart: clockStart,
                                                  pausedAt: r.endedAt,
                                                  thirdText: third,
                                                  thirdLabel: label,
                                                  finishedLine: line)
    }

    /// 第幾個整公里（sim 的 int(distance // 1000)）；NaN、無限大、負的當 0（Int(Double) 碰到會閃退）
    private static func wholeKm(_ meters: Double) -> Int {
        guard meters.isFinite, meters > 0 else { return 0 }
        return Int(min(meters, 1_000_000_000) / 1000)
    }

    // MARK: - 內部：暫停 30 分鐘提醒（brief §G3-9）

    /// 有通知權限才排（不新問：跑到一半跳權限框比不提醒更糟），沒有就只靠鎖定畫面那一行（staleDate）。
    /// 世代守門：排之前、排的時候剛好按了繼續／結束／放棄，就不排（或排好再拿掉）
    private func scheduleReminder(title: String) {
        reminderGen &+= 1
        let gen = reminderGen
        reminderWantedGen = gen
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: break
            default: return                                // 沒權限：不問，只靠鎖定畫面那一行
            }
            guard gen == self.reminderGen else { return }  // 排之前已經繼續／結束了
            let content = UNMutableNotificationContent()
            content.title = title + "已暫停 30 分鐘"
            content.body = "還要繼續嗎？不跑了就打開 LifeGood 按「結束」，這一趟會存下來。"
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: RunActivityAttributes.pauseRemindSeconds,
                                                            repeats: false)
            let req = UNNotificationRequest(identifier: Self.pauseReminderId, content: content, trigger: trigger)
            try? await center.add(req)
            if gen != self.reminderGen && self.reminderWantedGen == nil {   // 排的時候剛好按了繼續／結束：排好再拿掉
                center.removePendingNotificationRequests(withIdentifiers: [Self.pauseReminderId])
            }
        }
    }

    /// 繼續、完成、放棄、開始新的一趟、清殘留（沒在記錄）時：還沒響的拿掉、響過的也從通知中心拿掉
    private func cancelReminder() {
        reminderGen &+= 1
        reminderWantedGen = nil
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.pauseReminderId])
        center.removeDeliveredNotifications(withIdentifiers: [Self.pauseReminderId])
    }
}

// MARK: - RunSport → 共用檔的 RunActivitySport（主控寫好）

extension RunActivitySport {
    init(_ s: RunSport) {
        switch s {
        case .run: self = .run
        case .walk: self = .walk
        case .bike: self = .bike
        case .hike: self = .hike
        }
    }
}
