import Foundation
import ActivityKit
import SwiftUI
import UIKit
import EventKit

// MARK: - 今日行程時間軸 · 主 App 側控制器（v25.377）
//
// 負責：把今天的會議整理成精簡快照 → 啟動／更新 Live Activity → 到期前自動續期。
//
// ⚠️ Live Activity 的現實限制（不是可以繞過的實作細節）：
//   • ContentState 上限 4KB，所以場次數與文字長度都要先裁切
//   • 一個 Activity 最長活 8 小時，之後系統會自己結束它。
//     從早到晚的行程超過 8 小時，所以到期前要重啟一次（見 scheduleRenewal）
//   • 使用者可以在系統設定裡關閉即時動態，areActivitiesEnabled 會是 false
//
// [v5] 控制中心「今日行程」、中型「今天」的「上靈動島」（DayTimelineToggleIntent／StartDayTimelineIntent，
//      LiveActivityIntent，在 App 的行程裡背景跑）經 DayTimelineToggleBridge 叫 setEnabled(_:store:)，
//      設定頁的開關也是同一個 isEnabled。靈動島開始、續期、收掉、被使用者滑掉、系統 8 小時收掉時，
//      把「跑到幾點」寫進 App Group（DayTimelineToggleState.setRunningUntil，沒在跑寫 nil），
//      值真的變了才重畫控制項與「今天」（publishRunState）。控制項的開＝「跑到幾點」> 現在，不是 isEnabled。
//      規格見 scratchpad/widgets/v5/brief.md 的 G1-7。
//
// [健康 v6] 即時動態的優先序 relevanceScore 50（開始、更新都帶）：跑步（RunActivityCenter）是 100，跑步時靈動島放跑步，
//      跑完那一刻跑步的結束、從靈動島拿掉，今日行程自己回來。點軸上的點（SelectTimelineStopIntent）也保留這個分數。

@MainActor
final class DayTimelineController: ObservableObject {

    static let shared = DayTimelineController()

    /// [健康 v6] 即時動態的優先序：跑步 100（RunActivityCenter.relevanceScore）比較高，跑步時靈動島放跑步、跑完今日行程自己回來
    static let relevanceScore: Double = 50

    /// 使用者是否開啟這個功能（設定頁的開關）
    @AppStorage("day_timeline_enabled") var isEnabled = false {
        didSet { if !isEnabled { Task { await stop() } } }
    }

    /// 最近一次的失敗原因，設定頁會顯示
    @Published private(set) var lastError: String?
    /// 目前有沒有在跑
    @Published private(set) var isRunning = false

    /// 展開區的寬度放得下幾顆點。這是版面上限，不是容量上限。
    private let maxStops = 8
    /// ContentState 的硬上限是 4KB（超過 Activity.request 直接丟錯）。
    /// 留 500 bytes 給 ActivityKit 自己的封裝開銷。
    private let maxPayloadBytes = 3_500

    private var renewalTask: Task<Void, Never>?
    /// [v5] 看著目前那一個即時動態：使用者在鎖定畫面滑掉、系統 8 小時收掉時寫「沒在跑」
    private var stateWatch: Task<Void, Never>?

    private init() {}

    // MARK: - 對外

    /// [v5] 設定頁、控制中心「今日行程」、中型「上靈動島」共用：開＝打開並 refresh；關＝關掉並 stop。
    /// 今天沒有行程時開也不會上島（refresh 照舊：沒有站就 stop），「跑到幾點」維持沒在跑
    func setEnabled(_ on: Bool, store: LifeStore) async {
        isEnabled = on
        if on {
            await refresh(store: store)
        } else {
            await stop()
        }
    }

    /// 依目前的資料重新整理。資料有變（新增會議、改時間）或 App 回到前景時呼叫。
    func refresh(store: LifeStore) async {
        guard isEnabled else {
            // [v5] 沒開：App 被殺掉時被滑掉、收掉的來不及寫，這裡補一次「沒在跑」（值沒變就什麼都不做）
            if liveActivity() == nil { publishRunState(until: nil) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = "系統的「即時動態」已關閉。請到「設定 → LifeGood → 即時動態」打開。"
            await stop()
            return
        }
        // 先挑出今天的行程，再按實際編碼大小裁到 4KB 以內
        let stops = fitted(todayStops(store: store))
        guard !stops.isEmpty else {
            // 今天沒有行程就不要占著靈動島
            await stop()
            lastError = nil
            return
        }
        let state = DayTimelineAttributes.ContentState(
            stops: stops,
            selectedIndex: defaultIndex(for: stops),
            generatedAt: Date())

        if let activity = liveActivity() {
            await activity.update(ActivityContent(state: state, staleDate: staleDate(stops),
                                                  relevanceScore: Self.relevanceScore))
            isRunning = true
            lastError = nil
            // [v5] App 重開後不知道是幾點開始的：沒記著「跑到幾點」就保守當現在開始
            if !DayTimelineToggleState.isRunning(at: Date()) {
                publishRunState(until: Date().addingTimeInterval(DayTimelineToggleState.maxRun))
            }
            if stateWatch == nil { watch(activity) }
        } else {
            // [v5] 剩下的都是已經結束、還掛在鎖定畫面上的（系統 8 小時收掉的）：先拿掉，再開新的
            for leftover in Activity<DayTimelineAttributes>.activities {
                await leftover.end(nil, dismissalPolicy: .immediate)
            }
            await start(state: state, stops: stops)
        }
        scheduleRenewal()
    }

    /// 結束（關閉開關、今天沒行程、或使用者手動停止）
    func stop() async {
        // [v5] 自己收掉的不用再看（收掉之後的 dismissed 不要再進 activityDidEnd）
        stateWatch?.cancel()
        stateWatch = nil
        renewalTask?.cancel()
        renewalTask = nil
        for activity in Activity<DayTimelineAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        isRunning = false
        // [v5] 控制項回到「未顯示」、中型「今天」的「上靈動島」回來（續期的 stop 也會寫 nil，下一次 refresh 再寫回來）
        publishRunState(until: nil)
    }

    // MARK: - 啟動

    private func start(state: DayTimelineAttributes.ContentState,
                       stops: [TimelineStop]) async {
        let attributes = DayTimelineAttributes(dayLabel: Self.dayLabel(Date()))
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: staleDate(stops),
                                         relevanceScore: Self.relevanceScore),
                pushType: nil)
            isRunning = true
            lastError = nil
            // [v5] 看著它（被滑掉、被系統收掉時寫「沒在跑」），寫「跑到幾點」（最長 8 小時）
            watch(activity)
            publishRunState(until: Date().addingTimeInterval(DayTimelineToggleState.maxRun))
        } catch {
            // 常見原因：使用者關掉了即時動態、或 ContentState 超過 4KB
            lastError = "無法開啟靈動島：\(error.localizedDescription)"
            isRunning = false
            publishRunState(until: nil)
        }
    }

    // MARK: - [v5] 「跑到幾點」（控制中心「今日行程」、中型「上靈動島」看這個）

    /// 現在還活著的那一個（進行中或內容過期但還在）；已經結束、被滑掉的不算
    private func liveActivity() -> Activity<DayTimelineAttributes>? {
        Activity<DayTimelineAttributes>.activities.first { a in
            a.activityState != .ended && a.activityState != .dismissed
        }
    }

    /// 「跑到幾點」變了才重畫控制項與「今天」（App 在背景叫重畫會吃小工具每天的額度）
    private func publishRunState(until: Date?) {
        if DayTimelineToggleState.setRunningUntil(until) {
            WidgetRefresh.reloadControls(WidgetKind.dayTimelineControlKinds)
            WidgetRefresh.reload([WidgetKind.today])
        }
    }

    /// 使用者在鎖定畫面把它滑掉、系統 8 小時收掉：activityStateUpdates 會送 dismissed／ended
    private func watch(_ activity: Activity<DayTimelineAttributes>) {
        stateWatch?.cancel()
        let id = activity.id
        stateWatch = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                if state == .dismissed || state == .ended {
                    self?.activityDidEnd(id)
                    return
                }
            }
        }
    }

    /// 續期時舊的結束、新的已經在跑：不要清掉
    private func activityDidEnd(_ id: String) {
        let others = Activity<DayTimelineAttributes>.activities.contains { a in
            a.id != id && a.activityState == .active
        }
        guard !others else { return }
        stateWatch = nil
        isRunning = false
        publishRunState(until: nil)
    }

    /// 內容過期時間：最後一場結束後就不用再顯示了
    private func staleDate(_ stops: [TimelineStop]) -> Date? {
        stops.last?.end
    }

    /// 8 小時到期前重啟一次。系統時間到就會把 Activity 收掉，
    /// 不自己續期的話下午就看不到時間軸了。
    private func scheduleRenewal() {
        renewalTask?.cancel()
        renewalTask = Task { [weak self] in
            // 7 小時 50 分後動作，留 10 分鐘餘裕
            try? await Task.sleep(nanoseconds: UInt64(7 * 3600 + 50 * 60) * 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.stop()
            self.isRunning = false
            // [v5] App 在前景時馬上接上（以前要等下一次回前景，中間島會空著、控制項寫「未顯示」）；
            // 不在前景時照舊交給下一次回前景的 refresh
            if UIApplication.shared.applicationState == .active {
                await self.refresh(store: AppStores.life)
            }
        }
    }

    // MARK: - 快照

    /// 今天的行程：挑行程交給 TodayAgenda（跟「今天」小工具同一段程式，v25.545 抽出去），
    /// 這裡只做靈動島版面的事——超過 8 站時裁掉。
    ///
    /// 只收「有時間的」項目：時間軸是一條從早到晚的時間線，
    /// 全日事件（durationMinutes == 0）沒有落點，硬放上去只會讓軸失真。
    private func todayStops(store: LifeStore) -> [TimelineStop] {
        var out = TodayAgenda.stops(on: Date(), store: store)
        // 超過上限時保留「從現在起最近的幾場」——早上八點看整天、下午三點看下半天
        if out.count > maxStops {
            let now = Date()
            if let firstUpcoming = out.firstIndex(where: { $0.end > now }) {
                let start = min(firstUpcoming, max(0, out.count - maxStops))
                out = Array(out[start..<min(start + maxStops, out.count)])
            } else {
                out = Array(out.suffix(maxStops))
            }
        }
        return out
    }

    /// [v25.382] 依實際編碼大小裁到 4KB 以內。
    ///
    /// 以前是用「8 站 × 估計每站 300 bytes」這種心算來抓，很容易錯得離譜——
    /// 中文一個字 3 bytes、JSON 還要算欄位名，一場議程滿檔的會議就可能逼近上限。
    /// 直接編碼來量最準；超過就從最晚的那一站開始砍。
    private func fitted(_ stops: [TimelineStop]) -> [TimelineStop] {
        var out = stops
        while out.count > 1, encodedSize(out) > maxPayloadBytes {
            out.removeLast()
        }
        return out
    }

    private func encodedSize(_ stops: [TimelineStop]) -> Int {
        let probe = DayTimelineAttributes.ContentState(stops: stops, selectedIndex: 0)
        return (try? JSONEncoder().encode(probe))?.count ?? 0
    }

    /// 預設選中的那一站：進行中 > 下一場 > 第一場
    private func defaultIndex(for stops: [TimelineStop]) -> Int {
        let now = Date()
        if let i = stops.firstIndex(where: { $0.start <= now && now < $0.end }) { return i }
        if let i = stops.firstIndex(where: { $0.start > now }) { return i }
        return 0
    }

    // MARK: - 文字

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d（E）"
        return f
    }()

    static func dayLabel(_ date: Date) -> String { dayFmt.string(from: date) }
}
