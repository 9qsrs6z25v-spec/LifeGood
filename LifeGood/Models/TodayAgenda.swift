import Foundation
import EventKit

// MARK: - 某一天的行程（v25.545，只屬於主 App）
//
// 從 DayTimelineController.todayStops 抽出來、加上「哪一天」參數：
// 靈動島（只取今天、再裁 8 站）與「今天」小工具（今天、明天，不裁）用同一段程式挑行程，
// 場次 id 也是同一套（lifegood://today?stop=<id> 才開得到同一張卡）。
//
// ⚠️ 場次 id、title、owner、detail、durationMinutes、kind、排序都不能改：
//    靈動島的 ContentState、DeepLinkRouter 的 DayTimelineLink.resolve（id 的第一個字母＋UUID 前 8 碼）
//    都靠它們。「裁成 8 站」是靈動島版面的事，留在 DayTimelineController。
//
// 規格見 scratchpad/widgets/v1/brief.md 的 G1。

/// @MainActor：AppleCalendarBridge 是 @MainActor（AppleCalendarBridge.swift:8）
@MainActor
enum TodayAgenda {

    /// 一場行程＋小工具多要的兩樣東西
    struct Item {
        /// 靈動島那一份，原樣
        var stop: TimelineStop
        /// 地點：個人事件、系統行事曆的地點，旅遊景點的地址；部屬會議沒有地點欄位，是空字串
        var location: String
        /// StandBy 用、不含人名：「部屬會議」「會議／事務」「系統行事曆」、景點名（過夜那站「住宿」）
        var lockTitle: String
    }

    /// 內容摘要的字數上限。[v25.382] 展開區給摘要 3 行（原本是 DayTimelineController.maxDetailLength）
    private static let maxDetailLength = 90

    /// 某一天全部有時間的行程：部屬會議（含週期展開）＋我的行事曆的個人事件（含重複）
    /// ＋系統行事曆＋[v25.469] 旅遊行程那一天的景點，依開始時間排序，**不裁站數**。
    ///
    /// 只收「有時間的」項目：時間軸是一條從早到晚的時間線，
    /// 全日事件（durationMinutes == 0）沒有落點，硬放上去只會讓軸失真（全日的事見 CalendarDayItems）。
    static func items(on day: Date, store: LifeStore, calendar cal: Calendar = .current) -> [Item] {
        let dayStart = cal.startOfDay(for: day)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        // expandedOccurrences 需要一個起點與展開上限，給當天就好——
        // 範圍越窄，週期會議的逐步推進越快
        let from = cal.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart

        var out: [Item] = []

        // 1) 部屬會議
        // [v25.470] 旅遊期間不收部屬會議（使用者：代理人會處理）。
        // 只擋部屬會議——個人事件與系統行事曆是自己的事，旅行中照樣要看得到。
        if !store.hidesMeetings(on: day) {
            for sub in store.subordinates {
                for meeting in sub.meetings {
                    for occ in meeting.expandedOccurrences(from: from, horizon: dayEnd) {
                        guard !occ.isCancelled else { continue }
                        guard occ.date >= dayStart, occ.date < dayEnd else { continue }
                        let stop = TimelineStop(
                            id: stopId("m", meeting.id, occ.date),
                            title: meeting.topic,
                            start: occ.date,
                            durationMinutes: max(5, meeting.durationMinutes),
                            owner: sub.name,
                            detail: detailText(meeting: meeting, occurrence: occ),
                            kind: .meeting)
                        // SubordinateMeeting 沒有地點欄位；StandBy 不寫部屬名字、也不寫主題
                        out.append(Item(stop: stop,
                                        location: "",
                                        lockTitle: TimelineStopKind.meeting.label))
                    }
                }
            }
        }

        // 2) 我的行事曆：個人事件。occurs(on:) 已經處理好重複規則，
        //    occurrenceDate(on:) 再把原始時分套到那一天（與 MyCalendarView 同一組工具）。
        for event in store.personalEvents where event.occurs(on: day, calendar: cal) {
            guard event.durationMinutes > 0 else { continue }   // 全日事件沒有軸上落點
            let start = event.occurrenceDate(on: day, calendar: cal)
            let stop = TimelineStop(
                id: stopId("p", event.id, start),
                title: event.title,
                start: start,
                durationMinutes: max(5, event.durationMinutes),
                owner: eventOwnerText(event),
                detail: truncated(event.note),
                kind: .personal)
            out.append(Item(stop: stop,
                            location: event.location.trimmingCharacters(in: .whitespacesAndNewlines),
                            lockTitle: event.kind.rawValue))
        }

        // 3) [v25.383] iOS 系統行事曆。比照 MyCalendarView：
        //    已經從 LifeGood 同步出去的事件要排掉，不然同一件事會出現兩次
        //    （一次是上面的個人事件、一次是它在系統行事曆裡的分身）。
        let appleCal = AppleCalendarBridge.shared
        if appleCal.hasAccess {
            let syncedIds = Set(store.personalEvents.compactMap { $0.ekEventIdentifier })
            for ev in appleCal.events(forDay: day, calendar: cal)
            where !syncedIds.contains(ev.eventIdentifier) {
                guard !ev.isAllDay else { continue }            // 全日事件沒有軸上落點
                let start = ev.startDate ?? day
                guard start >= dayStart, start < dayEnd else { continue }
                let minutes = Int(((ev.endDate ?? start).timeIntervalSince(start)) / 60)
                let stop = TimelineStop(
                    id: "e" + String(ev.calendarItemIdentifier.prefix(8))
                        + String(Int(start.timeIntervalSince1970)),
                    title: ev.title ?? "",
                    start: start,
                    durationMinutes: max(5, minutes),
                    owner: appleOwnerText(ev),
                    detail: truncated(ev.notes ?? ""),
                    kind: .appleCalendar)
                let place = (ev.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                out.append(Item(stop: stop,
                                location: place,
                                lockTitle: TimelineStopKind.appleCalendar.label))
            }
        }

        // 4) [v25.469] 旅遊行程的景點。使用者要求：每個站點的時間也要進時間軸。
        //
        //    走 plan.timeline 而不是 stops 的原始欄位——抵達時間是推算出來的
        //    （出發時間 ＋ 各段交通 ＋ 停留），而且打過卡的站會用實際時間。
        //    那份推算只有 TripPlan.timeline 知道，自己重算一定會跟畫面對不起來。
        for plan in store.tripPlans {
            for slot in plan.timeline {
                guard slot.arrival >= dayStart, slot.arrival < dayEnd else { continue }
                // 已經離開的站不用再占位置——旅遊那一天站數多，軸上只有 8 個位子
                if slot.stop.checkInState == .departed { continue }
                let stop = TimelineStop(
                    id: stopId("t", plan.id, slot.arrival),
                    title: slot.stop.displayName,
                    start: slot.arrival,
                    // 停留時間可能是 0（純經過），給個下限才有落點
                    durationMinutes: max(5, slot.stop.dwellMinutes),
                    owner: plan.displayTitle,
                    detail: truncated(tripDetail(slot.stop)),
                    kind: .trip)
                // 景點算低隱私，StandBy 照樣寫站名；過夜那一站寫「住宿」（不露飯店名）
                out.append(Item(stop: stop,
                                location: slot.stop.address.trimmingCharacters(in: .whitespacesAndNewlines),
                                lockTitle: slot.stop.isOvernight ? "住宿" : slot.stop.displayName))
            }
        }

        out.sort { $0.stop.start < $1.stop.start }
        return out
    }

    /// 只要 TimelineStop（靈動島用）
    static func stops(on day: Date, store: LifeStore, calendar cal: Calendar = .current) -> [TimelineStop] {
        items(on: day, store: store, calendar: cal).map { $0.stop }
    }

    // MARK: - 字（從 DayTimelineController 原樣搬來）

    /// [v25.382] 場次 id。只需要在同一份快照裡唯一（ForEach 用），
    /// 以前塞整個 UUID 加上完整時間戳要 57 個字元，白白吃掉 4KB 預算的一大塊。
    /// 格式「來源字母＋UUID 前 8 碼＋開始時間 epoch」：DayTimelineLink.resolve／stopIdForMeeting 靠它。
    private static func stopId(_ prefix: String, _ id: UUID, _ start: Date) -> String {
        // prefix(8) 回的是 Substring，String + Substring 不能直接相加
        prefix + String(id.uuidString.prefix(8)) + String(Int(start.timeIntervalSince1970))
    }

    /// 內容摘要：優先用議程項目，沒有才用備註；一律裁到上限
    private static func detailText(meeting: SubordinateMeeting,
                                   occurrence: ResolvedMeetingOccurrence) -> String {
        // 區域變數不叫 items：同一個 enum 裡有 static func items(on:)，名字分開比較好讀
        let agendaItems = occurrence.items.isEmpty ? meeting.items : occurrence.items
        let titles = agendaItems.map(\.content).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let raw = titles.isEmpty
            ? meeting.note
            : titles.joined(separator: "、")
        return truncated(raw)
    }

    /// 個人事件的第二行標籤：有地點就顯示地點，沒有就顯示事件分類
    private static func eventOwnerText(_ event: PersonalEvent) -> String {
        let place = event.location.trimmingCharacters(in: .whitespacesAndNewlines)
        return place.isEmpty ? event.kind.rawValue : place
    }

    /// [v25.469] 景點的內容摘要：地址優先，沒填就用備註。
    /// 旅遊那一天在外面跑，地址比備註有用——要導航的時候看的是它。
    private static func tripDetail(_ stop: TripStop) -> String {
        let addr = stop.address.trimmingCharacters(in: .whitespacesAndNewlines)
        return addr.isEmpty ? stop.note : addr
    }

    /// [v25.383] 系統行事曆事件的第二行標籤：有地點顯示地點，
    /// 沒有就顯示它屬於哪一本行事曆（工作／家庭／訂閱的節日…）
    private static func appleOwnerText(_ event: EKEvent) -> String {
        let place = (event.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !place.isEmpty { return place }
        return event.calendar?.title ?? "行事曆"
    }

    /// 壓成單行並裁到上限。ContentState 有 4KB 硬上限，長備註必須先砍。
    private static func truncated(_ raw: String) -> String {
        let flat = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard flat.count > maxDetailLength else { return flat }
        return String(flat.prefix(maxDetailLength)) + "…"
    }
}
