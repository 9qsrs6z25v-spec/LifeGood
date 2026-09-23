import Foundation
import ActivityKit
import SwiftUI
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

@MainActor
final class DayTimelineController: ObservableObject {

    static let shared = DayTimelineController()

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
    /// 內容摘要的字數上限。[v25.382] 展開區現在給摘要 3 行，跟著放寬。
    private let maxDetailLength = 90
    /// ContentState 的硬上限是 4KB（超過 Activity.request 直接丟錯）。
    /// 留 500 bytes 給 ActivityKit 自己的封裝開銷。
    private let maxPayloadBytes = 3_500

    private var renewalTask: Task<Void, Never>?

    private init() {}

    // MARK: - 對外

    /// 依目前的資料重新整理。資料有變（新增會議、改時間）或 App 回到前景時呼叫。
    func refresh(store: LifeStore) async {
        guard isEnabled else { return }
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

        if let activity = DayTimelineLiveActivity.running {
            await activity.update(ActivityContent(state: state, staleDate: staleDate(stops)))
            isRunning = true
            lastError = nil
        } else {
            await start(state: state, stops: stops)
        }
        scheduleRenewal()
    }

    /// 結束（關閉開關、今天沒行程、或使用者手動停止）
    func stop() async {
        renewalTask?.cancel()
        renewalTask = nil
        for activity in Activity<DayTimelineAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        isRunning = false
    }

    // MARK: - 啟動

    private func start(state: DayTimelineAttributes.ContentState,
                       stops: [TimelineStop]) async {
        let attributes = DayTimelineAttributes(dayLabel: Self.dayLabel(Date()))
        do {
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: staleDate(stops)),
                pushType: nil)
            isRunning = true
            lastError = nil
        } catch {
            // 常見原因：使用者關掉了即時動態、或 ContentState 超過 4KB
            lastError = "無法開啟靈動島：\(error.localizedDescription)"
            isRunning = false
        }
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
            // 重新啟動由下一次 refresh 負責；App 在前景時會馬上接上
            self.isRunning = false
        }
    }

    // MARK: - 快照

    /// 今天的行程：部屬會議（含週期展開）＋我的行事曆的個人事件（含重複），
    /// 依開始時間排序後裁切。
    ///
    /// 只收「有時間的」項目：時間軸是一條從早到晚的時間線，
    /// 全日事件（durationMinutes == 0）沒有落點，硬放上去只會讓軸失真。
    private func todayStops(store: LifeStore) -> [TimelineStop] {
        let cal = Calendar.current
        let today = Date()
        let dayStart = cal.startOfDay(for: today)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        // expandedOccurrences 需要一個起點與展開上限，給當天就好——
        // 範圍越窄，週期會議的逐步推進越快
        let from = cal.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart

        var out: [TimelineStop] = []

        // 1) 部屬會議
        for sub in store.subordinates {
            for meeting in sub.meetings {
                for occ in meeting.expandedOccurrences(from: from, horizon: dayEnd) {
                    guard !occ.isCancelled else { continue }
                    guard occ.date >= dayStart, occ.date < dayEnd else { continue }
                    out.append(TimelineStop(
                        id: Self.stopId("m", meeting.id, occ.date),
                        title: meeting.topic,
                        start: occ.date,
                        durationMinutes: max(5, meeting.durationMinutes),
                        owner: sub.name,
                        detail: detailText(meeting: meeting, occurrence: occ),
                        kind: .meeting))
                }
            }
        }

        // 2) 我的行事曆：個人事件。occurs(on:) 已經處理好重複規則，
        //    occurrenceDate(on:) 再把原始時分套到今天（與 MyCalendarView 同一組工具）。
        for event in store.personalEvents where event.occurs(on: today, calendar: cal) {
            guard event.durationMinutes > 0 else { continue }   // 全日事件沒有軸上落點
            let start = event.occurrenceDate(on: today, calendar: cal)
            out.append(TimelineStop(
                id: Self.stopId("p", event.id, start),
                title: event.title,
                start: start,
                durationMinutes: max(5, event.durationMinutes),
                owner: eventOwnerText(event),
                detail: truncated(event.note),
                kind: .personal))
        }

        // 3) [v25.383] iOS 系統行事曆。比照 MyCalendarView：
        //    已經從 LifeGood 同步出去的事件要排掉，不然同一件事會出現兩次
        //    （一次是上面的個人事件、一次是它在系統行事曆裡的分身）。
        let appleCal = AppleCalendarBridge.shared
        if appleCal.hasAccess {
            let syncedIds = Set(store.personalEvents.compactMap { $0.ekEventIdentifier })
            for ev in appleCal.events(forDay: today, calendar: cal)
            where !syncedIds.contains(ev.eventIdentifier) {
                guard !ev.isAllDay else { continue }            // 全日事件沒有軸上落點
                let start = ev.startDate ?? today
                guard start >= dayStart, start < dayEnd else { continue }
                let minutes = Int(((ev.endDate ?? start).timeIntervalSince(start)) / 60)
                out.append(TimelineStop(
                    id: "e" + String(ev.calendarItemIdentifier.prefix(8))
                        + String(Int(start.timeIntervalSince1970)),
                    title: ev.title ?? "",
                    start: start,
                    durationMinutes: max(5, minutes),
                    owner: appleOwnerText(ev),
                    detail: truncated(ev.notes ?? ""),
                    kind: .appleCalendar))
            }
        }

        out.sort { $0.start < $1.start }
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

    /// [v25.382] 場次 id。只需要在同一份快照裡唯一（ForEach 用），
    /// 以前塞整個 UUID 加上完整時間戳要 57 個字元，白白吃掉 4KB 預算的一大塊。
    private static func stopId(_ prefix: String, _ id: UUID, _ start: Date) -> String {
        // prefix(8) 回的是 Substring，String + Substring 不能直接相加
        prefix + String(id.uuidString.prefix(8)) + String(Int(start.timeIntervalSince1970))
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

    /// 內容摘要：優先用議程項目，沒有才用備註；一律裁到上限
    private func detailText(meeting: SubordinateMeeting,
                            occurrence: ResolvedMeetingOccurrence) -> String {
        let items = occurrence.items.isEmpty ? meeting.items : occurrence.items
        let titles = items.map(\.content).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let raw = titles.isEmpty
            ? meeting.note
            : titles.joined(separator: "、")
        return truncated(raw)
    }

    /// 個人事件的第二行標籤：有地點就顯示地點，沒有就顯示事件分類
    private func eventOwnerText(_ event: PersonalEvent) -> String {
        let place = event.location.trimmingCharacters(in: .whitespacesAndNewlines)
        return place.isEmpty ? event.kind.rawValue : place
    }

    /// [v25.383] 系統行事曆事件的第二行標籤：有地點顯示地點，
    /// 沒有就顯示它屬於哪一本行事曆（工作／家庭／訂閱的節日…）
    private func appleOwnerText(_ event: EKEvent) -> String {
        let place = (event.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !place.isEmpty { return place }
        return event.calendar?.title ?? "行事曆"
    }

    /// 壓成單行並裁到上限。ContentState 有 4KB 硬上限，長備註必須先砍。
    private func truncated(_ raw: String) -> String {
        let flat = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard flat.count > maxDetailLength else { return flat }
        return String(flat.prefix(maxDetailLength)) + "…"
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
