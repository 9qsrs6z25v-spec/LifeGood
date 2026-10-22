import Foundation

// MARK: - 手錶上的字（手錶 v1，v25.574；watch/judge.md §2.1–§2.5、§2.17、§3.1、§5.6、§6.2；watch/build/v1/brief.md §2）
//
// 這個檔只屬於手錶兩個 target（LifeGoodWatch、LifeGoodWatchWidgets），iPhone 兩個 target 都不編。
// 只准用 Foundation 與 WatchPackage.swift／WidgetSnapshot.swift／DayTimelineAttributes.swift 的純資料型別。
//
// 手錶「只排版、不算錢」：金額字全部是 iPhone 寫好的（WidgetMoneyDay.lines(hidden:)、lock、bill.amountText），
// 這裡只挑那一份、把幾段字用「・」接起來。每一頁、每一格要畫的字都在這裡組好，View 只讀結果。
// scratchpad/watch/build/v1/sim_v1.py 跟這個檔一模一樣（同名函式），改了兩邊一起改、重跑 sim。
//
// 隱私（judge §6.1、§2.17）：
//   • 錶面、智慧型堆疊（WatchText.nextUp／spent）＝鎖定畫面：不寫人名（stop.owner）、財富只有類別字、
//     家人生日寫 lockTitle（「家人生日」）；金額照遮住規則（WatchPrivacyRule.masksAmounts）。
//   • 手錶 App 抬手＝解鎖的 iPhone App；手腕放下（isLuminanceReduced）或系統要求遮（redactionReasons.privacy）：
//     金額一律遮、人名／議程／備註／家人名字換字（WatchPrivacyRule.hidesPersonal）。

// MARK: - 遮的規則（judge §6.2-2、§6.2-3；兩個手錶 target 都經過這裡）

enum WatchPrivacyRule {
    /// 金額要不要遮：手腕放下、系統要求遮（手錶沒解鎖）、手錶的「遮住金額」、iPhone 的「隱藏金額」——任一個成立
    static func masksAmounts(dimmed: Bool, redacted: Bool, watchHides: Bool, phoneHides: Bool) -> Bool {
        dimmed || redacted || watchHides || phoneHides
    }

    /// 人名、議程、備註、家人名字要不要換字：手腕放下、系統要求遮（「遮住金額」開關只管錢，不管這個）
    static func hidesPersonal(dimmed: Bool, redacted: Bool) -> Bool {
        dimmed || redacted
    }
}

/// 手錶自己的「遮住金額」：存在**手錶**的 App Group UserDefaults（手錶 App 與手錶小格都讀得到；不跟 iPhone 同步）
enum WatchHideAmounts {
    static let key = "watch_hide_amounts"

    static var isOn: Bool { WidgetShared.defaults?.bool(forKey: key) ?? false }

    static func set(_ on: Bool) {
        WidgetShared.defaults?.set(on, forKey: key)
    }
}

/// 手錶上次收到 iPhone 的包是什麼時候（內容沒變也算；手錶設定「iPhone 14:02 更新」）
enum WatchReceiveLog {
    static let key = "watch_pkg_received_at"

    static var lastReceivedAt: Date? {
        guard let t = WidgetShared.defaults?.object(forKey: key) as? Double, t > 0 else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    static func note(_ date: Date) {
        WidgetShared.defaults?.set(date.timeIntervalSince1970, forKey: key)
    }
}

// MARK: - 色碼（judge §2.1、U4 §4.3；0xRRGGBB，兩個手錶 target 各自轉成 Color）

enum WatchPalette {
    static let skyTop: UInt32 = 0x121B38
    static let skyMid: UInt32 = 0x0E1428
    static let dateText: UInt32 = 0xB9C7EE
    static let small: UInt32 = 0xA3B2D9
    static let primary: UInt32 = 0xF3F6FF
    static let countdown: UInt32 = 0x8DB7FF
    static let amber: UInt32 = 0xFFC14D
    static let red: UInt32 = 0xFF7A8A
    static let fixedBar: UInt32 = 0xA98BFF
    static let variableBar: UInt32 = 0x5B9BFF
    static let green: UInt32 = 0x5ACC70
    static let meeting: UInt32 = 0xFF9F0A
    static let personal: UInt32 = 0x64D2FF
    static let appleCalendar: UInt32 = 0x30D158
    static let trip: UInt32 = 0xBF5AF2

    static func kind(_ kind: TimelineStopKind) -> UInt32 {
        switch kind {
        case .meeting:       return meeting
        case .personal:      return personal
        case .appleCalendar: return appleCalendar
        case .trip:          return trip
        }
    }
}

// MARK: - 共用小字

enum WatchText {
    /// 星期的一個字（Calendar 的 weekday：1＝星期日）。不靠語系的「narrow」寫法，sim 才算得一樣
    static let weekdayChars = ["日", "一", "二", "三", "四", "五", "六"]

    /// 錶面與手錶設定都寫的那一句（judge §3.2、§2.15）
    static let faceNote = "錶面上至少放一格 LifeGood，數字才會自己跟上；只放在智慧型堆疊的話，打開這個 App 一次才會更新。"

    /// 「30 分鐘」「1 小時」「1 小時 30 分」（跟會議通知「30 分鐘」同一種寫法）
    static func duration(_ minutes: Int) -> String {
        let m = max(0, minutes)
        if m < 60 { return "\(m) 分鐘" }
        let h = m / 60
        let r = m % 60
        return r == 0 ? "\(h) 小時" : "\(h) 小時 \(r) 分"
    }

    /// 「10/27（二）」；withWeekday false（41mm 放不下）＝「10/27」
    static func billDate(_ date: Date, withWeekday: Bool) -> String {
        let cal = Calendar.current
        let c = cal.dateComponents([.month, .day, .weekday], from: date)
        let base = "\(c.month ?? 0)/\(c.day ?? 0)"
        guard withWeekday else { return base }
        let i = min(max((c.weekday ?? 1) - 1, 0), weekdayChars.count - 1)
        return base + "（" + weekdayChars[i] + "）"
    }

    /// 自己繳的卡費還有幾天：「今天截止」「明天截止」「5 天後」（n＝WidgetDateText.daysFrom）
    static func cardDueText(_ n: Int) -> String {
        if n <= 0 { return "今天截止" }
        if n == 1 { return "明天截止" }
        return "\(n) 天後"
    }

    /// 部屬會議的議程：iPhone 把議程項目用「、」接起來、裁到 90 字（TodayAgenda.detailText）；拆回一項一項
    static func agendaItems(_ detail: String) -> [String] {
        detail.components(separatedBy: "、")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 行程種類的記號（SF Symbol；著色模式、手腕放下靠形狀分）：● 部屬會議、○ 我的行事曆、■ 系統行事曆、✈︎ 旅遊景點
    static func markSymbol(_ kind: TimelineStopKind) -> String {
        switch kind {
        case .meeting:       return "circle.fill"
        case .personal:      return "circle"
        case .appleCalendar: return "square.fill"
        case .trip:          return "airplane"
        }
    }

    /// 行程的標題（手錶 App 抬手）：主題；空的退回 lockTitle（「部屬會議」）
    static func stopTitle(_ s: WidgetStop) -> String {
        let t = s.stop.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? s.lockTitle : t
    }

    /// 「09:30 部門會議」（錶面、通知等鎖定畫面用：lockedSurfaceTitle，不寫人名）
    static func lockedLine(_ s: WidgetStop) -> String {
        DayTimelineFormat.time(s.stop.start) + " " + s.lockedSurfaceTitle
    }

    /// 進行中：「進行中・10:00 結束」；還沒開始：倒數（90 分鐘內）「5 分後」；更遠、已經結束：nil
    static func timeState(_ s: WidgetStop, now: Date) -> String? {
        if s.stop.start <= now && now < s.stop.end {
            return "進行中・" + DayTimelineFormat.time(s.stop.end) + " 結束"
        }
        return WidgetDateText.countdown(to: s.stop.start, from: now)
    }

    /// 部屬會議的「議程 3 項」；沒有議程 nil
    static func agendaCountText(_ s: WidgetStop) -> String? {
        guard s.stop.kind == .meeting else { return nil }
        let n = agendaItems(s.stop.detail).count
        return n > 0 ? "議程 \(n) 項" : nil
    }

    /// ① 今天「現在或下一件」的第二行：
    /// 部屬會議「5 分後・30 分鐘・議程 3 項」；其他「5 分後・12F 大會議室」（沒地點寫時長）；進行中「進行中・10:00 結束」
    static func focusDetail(_ s: WidgetStop, now: Date) -> String {
        var parts: [String] = []
        if let t = timeState(s, now: now) { parts.append(t) }
        if s.stop.start <= now && now < s.stop.end { return parts.joined(separator: "・") }
        if s.stop.kind == .meeting {
            parts.append(duration(s.stop.durationMinutes))
            if let a = agendaCountText(s) { parts.append(a) }
        } else {
            let place = s.location.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append(place.isEmpty ? duration(s.stop.durationMinutes) : place)
        }
        return parts.joined(separator: "・")
    }

    /// 今天全部（第二層清單）的第二行：「5 分後・12F 大會議室・30 分鐘」「30 分鐘・議程 3 項」「國小側門・15 分鐘」
    static func listDetail(_ s: WidgetStop, now: Date) -> String {
        var parts: [String] = []
        if let t = timeState(s, now: now) { parts.append(t) }
        if s.stop.kind != .meeting {
            let place = s.location.trimmingCharacters(in: .whitespacesAndNewlines)
            if !place.isEmpty { parts.append(place) }
        }
        parts.append(duration(s.stop.durationMinutes))
        if let a = agendaCountText(s) { parts.append(a) }
        return parts.joined(separator: "・")
    }
}

// MARK: - ① 今天（judge §2.1）

struct WatchTodayRow: Equatable, Identifiable {
    enum State: Equatable {
        /// 最近過去的那一件（灰）
        case past
        /// 現在或下一件（亮、多一行 detail）
        case focus
        /// 接下來的
        case upcoming
    }

    /// 場次 id（點了開那一件：WatchRoute.stop(id)）
    var id: String
    var kind: TimelineStopKind
    var state: State
    /// 「09:30」
    var time: String
    /// 「部門會議」（抬手；手錶 App 裡會議主題、行程名照顯示，judge §2.17）
    var title: String
    /// focus 那一列的第二行（WatchText.focusDetail）；其他 nil
    var detail: String?
}

/// 「今天要留意」一行（最多 2 行，judge §2.1）
struct WatchAttention: Equatable, Identifiable {
    enum Kind: Equatable {
        /// ① 自己繳的卡費今天截止（琥珀）
        case cardDueToday
        /// ② 今天的家人生日、紀念日
        case birthday
        /// ③ 自己繳的卡費 7 天內截止
        case cardDueSoon
        /// ④ 家庭待辦今天到期（只有件數）
        case family
        /// ⑤ 旅行 7 天內出發
        case trip
    }

    var id: String
    var kind: Kind
    /// SF Symbol
    var icon: String
    /// 抬手的字：「媽媽 62 歲生日」「卡費 10/27（二）・5 天後」
    var text: String
    /// 手腕放下的字：「家人生日」（其他種類本來就沒有人名，跟 text 一樣）
    var lockText: String
    var isAmber: Bool

    /// 點了去哪：卡費 → 接下來要繳；生日 → 今天全部；其他不動
    var route: WatchTextRoute? {
        switch kind {
        case .cardDueToday, .cardDueSoon: return .bills
        case .birthday: return .dayList
        case .family, .trip: return nil
        }
    }
}

/// WatchText 給的「點了去哪」（手錶 App 的 WatchRoute 照這個開；Foundation 這邊不認得 SwiftUI 的路徑）
enum WatchTextRoute: Equatable {
    case dayList
    case bills
}

struct WatchToday: Equatable {
    enum Mode: Equatable {
        /// 手上沒有包（「還沒收到 iPhone 的資料」〔再試一次〕）
        case noPackage
        /// 包裡沒有行程（iPhone 從來沒寫過 life 快照）
        case noLife
        /// 過了後天 00:00
        case expired
        /// 平常：有還沒結束的事
        case today
        /// 今天的都結束了（20:00 以前；或 20:00 以後但明天沒排）
        case allDone
        /// 20:00 以後、今天沒有還沒結束的事：換明天
        case tomorrow
        /// 今天沒排
        case empty
    }

    var mode: Mode
    /// 最上面那一行：「今天 10/22 週四・還有 4 件」「明天 10/23 週五・3 件」「今天 10/22 週四」「10/22 週四」
    var header: String
    var rows: [WatchTodayRow]
    /// 「還有 N 件 ›」（0＝不寫）
    var moreCount: Int
    /// 一句話：「今天的行程都結束了」「今天沒排行程」「還沒收到 iPhone 的資料・打開 iPhone 上的 LifeGood 一次」…
    var message: String?
    /// 都結束了的第二句：「明天 08:30 早會」「明天沒排行程」
    var nextLine: String?
    var attention: [WatchAttention]
}

extension WatchText {
    /// 「今天要留意」最多幾行
    static let maxAttention = 2
    /// 「接下來」的卡費、旅行看幾天內
    static let soonDays = 7
    /// 20:00 以後今天都結束了就換明天
    static let tomorrowHour = 20

    static func today(package: WatchPackage?, now: Date, compact: Bool) -> WatchToday {
        guard let package else {
            return WatchToday(mode: .noPackage, header: WidgetDateText.dayLabel(now), rows: [], moreCount: 0,
                              message: "還沒收到 iPhone 的資料・打開 iPhone 上的 LifeGood 一次",
                              nextLine: nil, attention: [])
        }
        guard let life = package.life else {
            return WatchToday(mode: .noLife, header: WidgetDateText.dayLabel(now), rows: [], moreCount: 0,
                              message: "打開 iPhone 上的 LifeGood 一次",
                              nextLine: nil, attention: attention(package: package, day: nil, now: now, compact: compact))
        }
        guard let day = life.day(at: now) else {
            return WatchToday(mode: .expired, header: WidgetDateText.dayLabel(now), rows: [], moreCount: 0,
                              message: "打開 iPhone 上的 LifeGood，更新今天的行程",
                              nextLine: nil, attention: attention(package: package, day: nil, now: now, compact: compact))
        }
        let notes = attention(package: package, day: day, now: now, compact: compact)
        if day.stops.isEmpty {
            return WatchToday(mode: .empty, header: day.dateText, rows: [], moreCount: 0,
                              message: "今天沒排行程", nextLine: nil, attention: notes)
        }
        let remaining = day.remainingStops(at: now)
        if remaining.isEmpty {
            let hour = Calendar.current.component(.hour, from: now)
            if hour >= tomorrowHour, let next = life.day(after: day), !next.stops.isEmpty {
                let shown = Array(next.stops.prefix(3))
                let rows: [WatchTodayRow] = shown.map { row($0, state: .upcoming, now: now) }
                return WatchToday(mode: .tomorrow,
                                  header: "明天 " + next.dateText + "・\(next.stops.count) 件",
                                  rows: rows, moreCount: next.stops.count - shown.count,
                                  message: nil, nextLine: nil, attention: notes)
            }
            return WatchToday(mode: .allDone, header: "今天 " + day.dateText, rows: [], moreCount: 0,
                              message: "今天的行程都結束了", nextLine: tomorrowLine(day), attention: notes)
        }
        var rows: [WatchTodayRow] = []
        if let past = day.stops.last(where: { $0.stop.end <= now }) {
            rows.append(row(past, state: .past, now: now))
        }
        rows.append(row(remaining[0], state: .focus, now: now))
        let after = Array(remaining.dropFirst().prefix(2))
        for s in after {
            rows.append(row(s, state: .upcoming, now: now))
        }
        let more = remaining.count - 1 - after.count
        return WatchToday(mode: .today,
                          header: "今天 " + day.dateText + "・還有 \(remaining.count) 件",
                          rows: rows, moreCount: max(0, more),
                          message: nil, nextLine: nil, attention: notes)
    }

    static func row(_ s: WidgetStop, state: WatchTodayRow.State, now: Date) -> WatchTodayRow {
        WatchTodayRow(id: s.stop.id, kind: s.stop.kind, state: state,
                      time: DayTimelineFormat.time(s.stop.start), title: stopTitle(s),
                      detail: state == .focus ? focusDetail(s, now: now) : nil)
    }

    /// 「明天 08:30 早會」；明天沒排「明天沒排行程」
    static func tomorrowLine(_ day: WidgetLifeDay) -> String {
        guard let first = day.nextDayFirstStop else { return "明天沒排行程" }
        return "明天 " + DayTimelineFormat.time(first.stop.start) + " " + stopTitle(first)
    }

    /// 今天要留意（最多 2 行，依序挑）：① 自己繳的卡費今天截止 ② 今天的家人生日、紀念日 ③ 自己繳的卡費 7 天內截止（最近一筆）
    /// ④ 家庭待辦今天到期 ⑤ 旅行 7 天內出發。day＝nil（過期、沒有行程）時只看要繳
    static func attention(package: WatchPackage, day: WidgetLifeDay?, now: Date, compact: Bool) -> [WatchAttention] {
        var out: [WatchAttention] = []
        let cards: [WatchBill] = (package.bills ?? []).filter { $0.bill.kind == .cardBill && $0.needsAction }
        // ① 今天截止
        if let b = cards.first(where: { WidgetDateText.daysFrom(now, to: $0.bill.dueDate) == 0 }) {
            out.append(WatchAttention(id: "card-today-" + b.id, kind: .cardDueToday, icon: "creditcard.fill",
                                      text: "卡費今天截止", lockText: "卡費今天截止", isAmber: true))
        }
        // ② 今天的家人生日、紀念日
        if let day {
            for item in day.allDay where item.kind == .birthday || item.kind == .anniversary {
                out.append(WatchAttention(id: "ad-" + item.id, kind: .birthday, icon: item.icon,
                                          text: item.title, lockText: item.lockTitle, isAmber: false))
            }
        }
        // ③ 7 天內（明天起）截止的最近一筆
        if let b = cards.first(where: { (1...soonDays).contains(WidgetDateText.daysFrom(now, to: $0.bill.dueDate)) }) {
            let n = WidgetDateText.daysFrom(now, to: b.bill.dueDate)
            let text = "卡費 " + billDate(b.bill.dueDate, withWeekday: !compact) + "・" + cardDueText(n)
            out.append(WatchAttention(id: "card-soon-" + b.id, kind: .cardDueSoon, icon: "creditcard.fill",
                                      text: text, lockText: text, isAmber: false))
        }
        // ④ 家庭待辦今天到期（只有件數）
        if let day, let life = package.life {
            let n = life.familyDueCount(day.dayKey)
            if n > 0 {
                let text = "家庭待辦 今天到期 \(n)"
                out.append(WatchAttention(id: "family-" + day.dayKey, kind: .family, icon: "house.fill",
                                          text: text, lockText: text, isAmber: false))
            }
        }
        // ⑤ 旅行 7 天內出發（出發那天起算旅途中，v6 才有旅行頁）
        if let trips = package.life?.trips,
           let t = trips.first(where: { (1...soonDays).contains(WidgetDateText.daysFrom(now, to: $0.firstDay)) }) {
            let n = WidgetDateText.daysFrom(now, to: t.firstDay)
            let text = t.title + "・還有 \(n) 天"
            out.append(WatchAttention(id: "trip-" + t.id.uuidString, kind: .trip, icon: "airplane",
                                      text: text, lockText: text, isAmber: false))
        }
        return Array(out.prefix(maxAttention))
    }
}

// MARK: - 今天全部（第二層清單，judge §2.2）

struct WatchListRow: Equatable, Identifiable {
    var id: String
    var kind: TimelineStopKind
    /// 「09:30 部門會議」
    var title: String
    /// 「5 分後・12F 大會議室・30 分鐘」（WatchText.listDetail）
    var detail: String
    var isCurrent: Bool
}

struct WatchAllDayRow: Equatable, Identifiable {
    var id: String
    var icon: String
    /// 抬手「媽媽 62 歲生日」
    var text: String
    /// 手腕放下「家人生日」
    var lockText: String
}

struct WatchDayList: Equatable {
    /// 現在・接下來（還沒結束的，依開始時間）
    var rows: [WatchListRow]
    var allDay: [WatchAllDayRow]
    /// 「明天 10/23 週五・3 件」；包裡沒有明天、明天沒排是 nil
    var tomorrowHeader: String?
    /// 「08:30 早會 起」
    var tomorrowFirst: String?
    /// 已經過了（舊到新）
    var past: [WatchListRow]
}

extension WatchText {
    static func dayList(package: WatchPackage?, now: Date) -> WatchDayList {
        guard let life = package?.life, let day = life.day(at: now) else {
            return WatchDayList(rows: [], allDay: [], tomorrowHeader: nil, tomorrowFirst: nil, past: [])
        }
        let rows: [WatchListRow] = day.remainingStops(at: now).map { listRow($0, now: now) }
        let past: [WatchListRow] = day.stops.filter { $0.stop.end <= now }.map { listRow($0, now: now) }
        let allDay: [WatchAllDayRow] = day.allDay.map {
            WatchAllDayRow(id: $0.id, icon: $0.icon, text: $0.title, lockText: $0.lockTitle)
        }
        var header: String? = nil
        var first: String? = nil
        if let next = life.day(after: day) {
            if let s = next.stops.first {
                header = "明天 " + next.dateText + "・\(next.stops.count) 件"
                first = DayTimelineFormat.time(s.stop.start) + " " + stopTitle(s) + " 起"
            }
        } else if let s = day.nextDayFirstStop {
            header = "明天"
            first = DayTimelineFormat.time(s.stop.start) + " " + stopTitle(s) + " 起"
        }
        return WatchDayList(rows: rows, allDay: allDay, tomorrowHeader: header, tomorrowFirst: first, past: past)
    }

    static func listRow(_ s: WidgetStop, now: Date) -> WatchListRow {
        WatchListRow(id: s.stop.id, kind: s.stop.kind,
                     title: DayTimelineFormat.time(s.stop.start) + " " + stopTitle(s),
                     detail: listDetail(s, now: now),
                     isCurrent: s.stop.start <= now && now < s.stop.end)
    }
}

// MARK: - 一件事的細節（judge §2.3）

struct WatchStopDetail: Equatable {
    var kind: TimelineStopKind
    /// 「1 對 1」
    var title: String
    /// 「11:00–11:30・30 分鐘」
    var timeLine: String
    /// 「20 分後開始」「進行中・11:30 結束」「已經結束」；更遠 nil
    var status: String?
    /// 部屬會議：抬手「和 王小明」；手腕放下、沒送名字「部屬會議」。其他種類 nil
    var who: String?
    /// 地點（部屬會議沒有）
    var place: String?
    /// 「議程 3 項」（部屬會議才有）
    var agendaTitle: String?
    /// 議程一項一項（手腕放下＝空）
    var agendaItems: [String]
    /// 其他種類的備註摘要：抬手原文；手腕放下「備註 1 則」；沒有 nil
    var note: String?
}

extension WatchText {
    static func stopDetail(_ s: WidgetStop, now: Date, hidesPersonal: Bool) -> WatchStopDetail {
        let stop = s.stop
        let timeLine = DayTimelineFormat.range(stop) + "・" + duration(stop.durationMinutes)
        var status: String? = nil
        if stop.start <= now && now < stop.end {
            status = "進行中・" + DayTimelineFormat.time(stop.end) + " 結束"
        } else if now >= stop.end {
            status = "已經結束"
        } else if let c = WidgetDateText.countdown(to: stop.start, from: now) {
            status = c + "開始"
        }
        if stop.kind == .meeting {
            let owner = stop.owner.trimmingCharacters(in: .whitespacesAndNewlines)
            let who = (hidesPersonal || owner.isEmpty) ? "部屬會議" : "和 " + owner
            let items = agendaItems(stop.detail)
            return WatchStopDetail(kind: stop.kind, title: stopTitle(s), timeLine: timeLine, status: status,
                                   who: who, place: nil,
                                   agendaTitle: items.isEmpty ? nil : "議程 \(items.count) 項",
                                   agendaItems: hidesPersonal ? [] : items, note: nil)
        }
        let place = s.location.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = stop.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        var note: String? = nil
        if !raw.isEmpty && raw != place {
            note = hidesPersonal ? "備註 1 則" : raw
        }
        return WatchStopDetail(kind: stop.kind, title: stopTitle(s), timeLine: timeLine, status: status,
                               who: nil, place: place.isEmpty ? nil : place,
                               agendaTitle: nil, agendaItems: [], note: note)
    }

    /// 包裡找那一件（今天、明天的行程，再找明天的第一場）；找不到 nil
    static func findStop(id: String, in package: WatchPackage?) -> WidgetStop? {
        guard let life = package?.life else { return nil }
        for day in life.days {
            if let hit = day.stops.first(where: { $0.stop.id == id }) { return hit }
        }
        for day in life.days {
            if let s = day.nextDayFirstStop, s.stop.id == id { return s }
        }
        return nil
    }

    /// 部屬會議通知〔看議程〕：userInfo 的會議 UUID → 包裡那一場的 id。
    /// 場次 id＝「m」＋UUID 前 8 碼＋開始時間（TodayAgenda.stopId；DeepLinkRouter.stopIdForMeeting 同一個開頭）；
    /// 比對只看開頭。同一天好幾場：挑還沒結束的第一場，都結束了挑最後一場
    static func meetingStopId(meetingId: String, in package: WatchPackage?, now: Date) -> String? {
        guard let life = package?.life else { return nil }
        let prefix = "m" + String(meetingId.prefix(8))
        var hits: [WidgetStop] = []
        for day in life.days {
            hits.append(contentsOf: day.stops.filter { $0.stop.kind == .meeting && $0.stop.id.hasPrefix(prefix) })
        }
        if let live = hits.first(where: { $0.stop.end > now }) { return live.stop.id }
        return hits.last?.stop.id
    }
}

// MARK: - ② 錢（judge §2.4）

struct WatchMoneyView: Equatable {
    enum Mode: Equatable {
        /// 手上沒有包（大字「—」）
        case noPackage
        /// 過了快照最後一天（下個月 7 號以後）
        case ended
        case normal
    }

    var mode: Mode
    /// 「本月還能花・10/22 週四」；遮住「本月已花・10/22 週四」
    var title: String
    /// 「NT$2.4萬」；遮住「72%」
    var hero: String
    /// 超支（沒遮時大字紅）
    var heroIsRed: Bool
    /// 「每天 NT$2,400・還有 10 天」（41mm「每天 NT$2,400」）；遮住「還有 10 天」
    var line: String
    /// 細條（遮住也畫：只透露比例）
    var bar: WidgetMoneyBar?
    /// 「今天 NT$120・2 筆」；遮住「今天 2 筆」
    var today: String?
    /// 30 天內最近一筆要繳：「10/27（二）卡費・5 天後」（沒有金額）
    var bill: String?
    var billIcon: String?
    /// 「上次更新 10/20」
    var footer: String?
}

extension WatchText {
    /// 「錢」那一列看幾天內
    static let billDays = 30

    static func money(package: WatchPackage?, now: Date, masked: Bool, compact: Bool) -> WatchMoneyView {
        guard let package else {
            return WatchMoneyView(mode: .noPackage, title: "本月還能花", hero: "—", heroIsRed: false,
                                  line: "還沒收到 iPhone 的資料", bar: nil, today: nil, bill: nil, billIcon: nil, footer: nil)
        }
        let next = nextBill(package: package, now: now)
        let billText: String? = next.map { billLine($0, now: now, compact: compact) }
        guard let money = package.money, !money.hasEnded(at: now), let d = money.day(at: now) else {
            return WatchMoneyView(mode: .ended, title: "本月還能花", hero: "—", heroIsRed: false,
                                  line: "打開 iPhone 上的 LifeGood 一次", bar: nil, today: nil,
                                  bill: billText, billIcon: next?.bill.icon, footer: nil)
        }
        let l = d.lines(hidden: masked)
        var line = l.line
        if !masked && d.state == .normal && !compact {
            line += "・還有 \(d.remainingDays) 天"
        }
        let todayText = l.todayText.isEmpty ? nil : l.todayText
        let footer: String? = money.isStale(at: now) ? WidgetDateText.lastUpdated(money.generatedAt) : nil
        return WatchMoneyView(mode: .normal, title: l.title + "・" + d.dateText, hero: l.hero,
                              heroIsRed: d.isOver && !masked, line: line, bar: d.bar, today: todayText,
                              bill: billText, billIcon: next?.bill.icon, footer: footer)
    }

    /// 30 天內最近一筆要繳（今天的也算；bills 已經依日期排好）
    static func nextBill(package: WatchPackage, now: Date) -> WatchBill? {
        (package.bills ?? []).first { b in
            let n = WidgetDateText.daysFrom(now, to: b.bill.dueDate)
            return n >= 0 && n < billDays
        }
    }

    /// 「10/27（二）卡費・5 天後」「11/6（五）Netflix・15 天後」（不寫金額）；41mm「10/27 卡費・5 天後」
    static func billLine(_ b: WatchBill, now: Date, compact: Bool) -> String {
        billTitle(b, compact: compact) + "・" + dueSuffix(b, now: now)
    }

    /// 「10/27（二）卡費」；41mm 不寫星期、日期和名字中間空一格「10/27 卡費」
    static func billTitle(_ b: WatchBill, compact: Bool) -> String {
        if compact { return billDate(b.bill.dueDate, withWeekday: false) + " " + b.bill.title }
        return billDate(b.bill.dueDate, withWeekday: true) + b.bill.title
    }

    /// 自己繳的卡費「5 天後」「今天截止」；其他照 iPhone 小工具「今天扣款」「明天扣款」「14 天後」
    static func dueSuffix(_ b: WatchBill, now: Date) -> String {
        let n = WidgetDateText.daysFrom(now, to: b.bill.dueDate)
        if b.bill.kind.isWealth && b.needsAction { return cardDueText(n) }
        return WidgetDateText.dueText(b.bill.dueDate, from: now) ?? ""
    }
}

// MARK: - 接下來要繳（第二層清單，judge §2.5）

struct WatchBillRow: Equatable, Identifiable {
    var id: String
    /// 「10/27（二）卡費」「11/5（四）苗栗的家 房貸」
    var title: String
    /// 「5 天後・要自己繳」「NT$32,000・14 天後」（遮住「NT$ ••••・14 天後」）
    var detail: String
    var icon: String
}

struct WatchBillList: Equatable {
    /// 30 天內的，最多 5 列（畫面先列 3 列，「再看 N 筆 ›」才列到 5）
    var rows: [WatchBillRow]
    /// 30 天內總共幾筆
    var total: Int
}

extension WatchText {
    /// 接下來要繳最多列幾筆
    static let maxBillRows = 5

    static func bills(package: WatchPackage?, now: Date, masked: Bool, compact: Bool) -> WatchBillList {
        let all: [WatchBill] = (package?.bills ?? []).filter { b in
            let n = WidgetDateText.daysFrom(now, to: b.bill.dueDate)
            return n >= 0 && n < billDays
        }
        let rows: [WatchBillRow] = all.prefix(maxBillRows).map { b in
            WatchBillRow(id: b.id,
                         title: billTitle(b, compact: compact),
                         detail: billDetail(b, now: now, masked: masked),
                         icon: b.bill.icon)
        }
        return WatchBillList(rows: rows, total: all.count)
    }

    static func billDetail(_ b: WatchBill, now: Date, masked: Bool) -> String {
        let suffix = dueSuffix(b, now: now)
        if b.bill.kind.isWealth {
            return b.needsAction ? suffix + "・要自己繳" : suffix
        }
        let amount = b.bill.amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        if amount.isEmpty { return suffix }
        return (masked ? WidgetHideAmounts.mask : amount) + "・" + suffix
    }
}

// MARK: - 資料多舊（judge §5.6）

struct WatchFreshness: Equatable {
    var text: String
    /// 超過 2 天、過期：琥珀色
    var isAmber: Bool
}

extension WatchText {
    /// 今天的行程：3 小時內 nil；3 小時～2 天「09:24 更新」／「10/21 22:10 更新」；超過 2 天琥珀；過期請打開 iPhone
    static func lifeFreshness(package: WatchPackage?, now: Date) -> WatchFreshness? {
        guard let life = package?.life else { return nil }
        if life.isExpired(at: now) {
            return WatchFreshness(text: "打開 iPhone 上的 LifeGood，更新今天的行程", isAmber: true)
        }
        guard life.showsUpdatedAt(at: now) else { return nil }
        let old = now.timeIntervalSince(life.generatedAt) > WidgetFreshness.moneyStaleAfter
        return WatchFreshness(text: WidgetDateText.updatedAt(life.generatedAt, now: now), isAmber: old)
    }

    /// 錢：2 天內 nil；超過「上次更新 10/20」；過了下個月 7 號請打開 iPhone
    static func moneyFreshness(package: WatchPackage?, now: Date) -> WatchFreshness? {
        guard let money = package?.money else { return nil }
        if money.hasEnded(at: now) {
            return WatchFreshness(text: "打開 iPhone 上的 LifeGood 一次", isAmber: true)
        }
        guard money.isStale(at: now) else { return nil }
        return WatchFreshness(text: WidgetDateText.lastUpdated(money.generatedAt), isAmber: false)
    }
}

// MARK: - 錶面「下一場」（judge §3.1；圓形、角落、一行字、長方形共用；鎖定畫面規則：不寫人名）

struct WatchNextUp: Equatable {
    /// 第一行前面的記號；nil＝不畫
    var mark: TimelineStopKind?
    var line1: String
    var line2: String
    var line3: String
    /// 第三行前面的圖示（「卡費今天截止」creditcard.fill、「家人生日」那一格的圖示）；nil＝不畫
    var line3Icon: String?
    /// 圓形中間的時間：下一場的開始「09:30」、進行中的結束「10:00」；沒有 nil
    var time: String?
    /// 圓形外圈 0…1：下一場開始前 60 分鐘從 0 填到 1；進行中＝已經過了多少；沒有 nil（不畫環）
    var ring: Double?
    /// 一行字、角落沿邊的字：「09:30 部門會議」
    var inline: String
    /// 點了開哪一件（nil＝只開 App 第一頁）
    var stopId: String?
}

extension WatchText {
    /// 圓形外圈：開始前幾分鐘開始填
    static let ringLeadMinutes = 60

    static func nextUp(package: WatchPackage?, now: Date) -> WatchNextUp {
        guard let package, let life = package.life else {
            return WatchNextUp(mark: nil, line1: "LifeGood", line2: "打開 iPhone 上的 App 一次", line3: "",
                               line3Icon: nil, time: nil, ring: nil, inline: "打開 iPhone 上的 LifeGood", stopId: nil)
        }
        guard let day = life.day(at: now) else {
            return WatchNextUp(mark: nil, line1: "打開 LifeGood", line2: "更新今天的行程", line3: "",
                               line3Icon: nil, time: nil, ring: nil, inline: "打開 LifeGood 更新今天的行程", stopId: nil)
        }
        var out: WatchNextUp
        let remaining = day.remainingStops(at: now)
        if let cur = day.currentStop(at: now) {
            let next = day.nextStop(at: now)
            out = WatchNextUp(mark: cur.stop.kind, line1: cur.lockedSurfaceTitle,
                              line2: "進行中・" + DayTimelineFormat.time(cur.stop.end) + " 結束",
                              line3: next.map { "接著 " + lockedLine($0) } ?? "今天最後一件",
                              line3Icon: nil, time: DayTimelineFormat.time(cur.stop.end),
                              ring: elapsed(cur, now: now),
                              inline: cur.lockedSurfaceTitle + "・" + DayTimelineFormat.time(cur.stop.end) + " 結束",
                              stopId: cur.stop.id)
        } else if let next = day.nextStop(at: now) {
            let after = remaining.count - 1
            var third: [String] = []
            if let c = WidgetDateText.countdown(to: next.stop.start, from: now) { third.append(c) }
            if after > 0 { third.append("之後 \(after) 件") }
            out = WatchNextUp(mark: next.stop.kind, line1: lockedLine(next),
                              line2: faceDetail(next), line3: third.joined(separator: "・"),
                              line3Icon: nil, time: DayTimelineFormat.time(next.stop.start),
                              ring: lead(next, now: now), inline: lockedLine(next), stopId: next.stop.id)
        } else if !day.stops.isEmpty {
            var second = "明天沒排行程"
            var third = ""
            if let first = day.nextDayFirstStop {
                second = "明天 " + lockedLine(first)
            }
            if let tomorrow = life.day(after: day), !tomorrow.stops.isEmpty {
                third = "明天 \(tomorrow.stops.count) 件"
            }
            out = WatchNextUp(mark: nil, line1: "今天的行程結束了", line2: second, line3: third,
                              line3Icon: nil, time: nil, ring: nil, inline: "今天的行程結束了", stopId: nil)
        } else {
            let first = day.allDay.first
            out = WatchNextUp(mark: nil, line1: day.dateText, line2: "今天沒排行程",
                              line3: first?.lockTitle ?? "", line3Icon: first?.icon,
                              time: nil, ring: nil, inline: "今天沒排行程", stopId: nil)
        }
        // 第三行換字：自己繳的卡費今天截止 ＞ 資料超過 3 小時（judge §3.1 表的後三列）
        let cardToday = (package.bills ?? []).contains { b in
            b.bill.kind == .cardBill && b.needsAction && WidgetDateText.daysFrom(now, to: b.bill.dueDate) == 0
        }
        if cardToday {
            out.line3 = "卡費今天截止"
            out.line3Icon = "creditcard.fill"
        } else if life.showsUpdatedAt(at: now) {
            out.line3 = WidgetDateText.updatedAt(life.generatedAt, now: now)
            out.line3Icon = nil
        }
        return out
    }

    /// 錶面第二行（不寫人名）：部屬會議「30 分鐘・議程 3 項」；其他「12F 大會議室・30 分鐘」（沒地點只寫時長）
    static func faceDetail(_ s: WidgetStop) -> String {
        var parts: [String] = []
        if s.stop.kind == .meeting {
            parts.append(duration(s.stop.durationMinutes))
            if let a = agendaCountText(s) { parts.append(a) }
        } else {
            let place = s.location.trimmingCharacters(in: .whitespacesAndNewlines)
            if !place.isEmpty { parts.append(place) }
            parts.append(duration(s.stop.durationMinutes))
        }
        return parts.joined(separator: "・")
    }

    /// 開始前 60 分鐘從 0 填到 1（更早＝0）
    static func lead(_ s: WidgetStop, now: Date) -> Double {
        let lead = Double(ringLeadMinutes * 60)
        let left = s.stop.start.timeIntervalSince(now)
        if left >= lead { return 0 }
        if left <= 0 { return 1 }
        return 1 - left / lead
    }

    /// 進行中那一場已經過了多少（0…1）
    static func elapsed(_ s: WidgetStop, now: Date) -> Double {
        let total = s.stop.end.timeIntervalSince(s.stop.start)
        guard total > 0 else { return 1 }
        return min(max(now.timeIntervalSince(s.stop.start) / total, 0), 1)
    }
}

// MARK: - 錶面「已花」（judge §3.1；§13-9：長方形抬手寫還能花金額、手腕放下 72%）

struct WatchSpent: Equatable {
    /// 圓形、角落的環 0…1（iPhone 寫好的 lock.ringValue）
    var ringValue: Double
    /// 「72%」「超支」「2 筆」
    var ringText: String
    /// 「已花」「今天」
    var ringCaption: String
    /// 沒有收入紀錄：圓形上面畫購物車
    var showsCart: Bool
    /// 一行字、角落沿邊：「今天 2 筆・已花 72%」
    var inline: String
    /// 長方形三行：抬手「本月還能花／NT$2.4萬／每天 NT$2,400・10 天」；遮住「本月已花／72%／還有 10 天・今天 2 筆」
    var title: String
    var hero: String
    var line3: String
    var heroIsRed: Bool
}

extension WatchText {
    static func spent(package: WatchPackage?, now: Date, masked: Bool) -> WatchSpent {
        guard let package else {
            return WatchSpent(ringValue: 0, ringText: "—", ringCaption: "已花", showsCart: false,
                              inline: "打開 iPhone 上的 LifeGood", title: "LifeGood", hero: "—",
                              line3: "打開 iPhone 上的 App 一次", heroIsRed: false)
        }
        guard let money = package.money else {
            return WatchSpent(ringValue: 0, ringText: "—", ringCaption: "已花", showsCart: false,
                              inline: "錢沒有送到手錶", title: "LifeGood", hero: "—",
                              line3: "iPhone 設定 › Apple Watch", heroIsRed: false)
        }
        guard !money.hasEnded(at: now), let d = money.day(at: now) else {
            return WatchSpent(ringValue: 0, ringText: "—", ringCaption: "已花", showsCart: false,
                              inline: "打開 iPhone 上的 LifeGood", title: "LifeGood", hero: "—",
                              line3: "打開 iPhone 上的 LifeGood 一次", heroIsRed: false)
        }
        let l = d.lines(hidden: masked)
        var parts: [String] = []
        if money.isStale(at: now) {
            parts = [WidgetDateText.lastUpdated(money.generatedAt)]
        } else if masked {
            parts = [l.line]
            if d.state != .noIncome { parts.append(l.footer) }
        } else {
            parts = [l.line]
            if d.state == .normal { parts.append("\(d.remainingDays) 天") }
        }
        let line3 = parts.filter { !$0.isEmpty }.joined(separator: "・")
        let ratio = min(max(d.spentRatio.isFinite ? d.spentRatio : 0, 0), 1)
        return WatchSpent(ringValue: d.lock?.ringValue ?? ratio,
                          ringText: d.lock?.ringText ?? "—",
                          ringCaption: d.lock?.ringCaption ?? "已花",
                          showsCart: d.state == .noIncome,
                          inline: d.lock?.inlineText ?? l.title,
                          title: l.title, hero: l.hero, line3: line3,
                          heroIsRed: d.isOver && !masked)
    }
}

// MARK: - 錶面小格的時間軸（照 iPhone TodayWidgetTimeline 的規則；judge §3.1「時間軸」）

struct WatchTimelineDates: Equatable {
    /// 依時間排好、不重複；至少一筆
    var dates: [Date]
    /// 什麼時候跟系統要新的 timeline；nil＝.never（等下一包送來時重畫）
    var reloadAt: Date?
}

enum WatchTimelinePlan {
    /// 每分鐘一筆的視窗長度（2 小時；同 iPhone TodayWidgetTimeline.tickWindow）
    static let tickWindow: TimeInterval = 120 * 60
    /// 一份 timeline 最多幾筆（保險）
    static let maxEntries = 200

    /// 下一場：視窗內倒數字出現的那幾分鐘每分鐘一筆；每場開始、結束、開始前 90 分鐘、結束前 90 分鐘；
    /// 換日、過期、「09:24 更新」出現的那一刻
    static func nextUp(package: WatchPackage?, now: Date) -> WatchTimelineDates {
        let start = floorToMinute(now)
        guard let life = package?.life else { return WatchTimelineDates(dates: [start], reloadAt: nil) }
        let validUntil = life.validUntil
        let windowEnd = min(start.addingTimeInterval(tickWindow), validUntil)
        var times = Set<Date>()
        times.insert(start)
        var tick = start.addingTimeInterval(60)
        while tick < windowEnd {
            if needsTick(life: life, at: tick) { times.insert(tick) }
            tick = tick.addingTimeInterval(60)
        }
        let lead = TimeInterval(WidgetFreshness.countdownMaxMinutes * 60)
        for day in life.days {
            times.insert(day.dayStart)
            times.insert(day.dayEnd)
            for item in day.stops {
                times.insert(item.stop.start)
                times.insert(item.stop.end)
                times.insert(item.stop.start.addingTimeInterval(-lead))
                times.insert(item.stop.end.addingTimeInterval(-lead))
            }
        }
        times.insert(validUntil)
        times.insert(life.generatedAt.addingTimeInterval(WidgetFreshness.lifeShowUpdatedAfter + 1))
        var dates: [Date] = times.filter { $0 >= start && $0 <= validUntil }.sorted()
        if dates.isEmpty { dates = [start] }
        if dates.count > maxEntries { dates = Array(dates.prefix(maxEntries)) }
        let reloadAt: Date? = windowEnd < validUntil ? windowEnd : nil
        return WatchTimelineDates(dates: dates, reloadAt: reloadAt)
    }

    /// 這一分鐘畫面上有沒有倒數字或外圈要動（進行中那場、90 分鐘內的下一場）
    static func needsTick(life: WatchLife, at time: Date) -> Bool {
        guard let day = life.day(at: time) else { return false }
        if day.currentStop(at: time) != nil { return true }
        if let next = day.nextStop(at: time),
           WidgetDateText.countdown(to: next.stop.start, from: time) != nil {
            return true
        }
        return false
    }

    /// 已花：現在、往後每一天 00:00、「上次更新」出現的那一刻、最後一天結束（「打開 iPhone…」）
    static func spent(package: WatchPackage?, now: Date) -> WatchTimelineDates {
        let start = floorToMinute(now)
        guard let money = package?.money else { return WatchTimelineDates(dates: [start], reloadAt: nil) }
        var times = Set<Date>()
        times.insert(start)
        for day in money.days where day.dayStart > start {
            times.insert(day.dayStart)
        }
        times.insert(money.generatedAt.addingTimeInterval(WidgetFreshness.moneyStaleAfter + 1))
        if let last = money.days.last { times.insert(last.dayEnd) }
        var dates: [Date] = times.filter { $0 >= start }.sorted()
        if dates.count > maxEntries { dates = Array(dates.prefix(maxEntries)) }
        return WatchTimelineDates(dates: dates, reloadAt: nil)
    }

    /// 往下取整到分鐘（倒數字的分鐘是無條件進位，從整分算起才不會差一分）
    static func floorToMinute(_ date: Date) -> Date {
        let seconds = (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60
        return Date(timeIntervalSinceReferenceDate: seconds)
    }
}
