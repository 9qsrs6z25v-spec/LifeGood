import SwiftUI
import WidgetKit

// MARK: - 今天（v25.545，只屬於 LifeGoodWidgets）
//
// systemSmall、systemMedium；StandBy 用小的。只讀 life_v1.json（WidgetLifeSnapshot）。
// 「25 分後」由 timeline provider 每分鐘一筆 entry 算好字（WidgetDateText.countdown），
// 不用系統的相對時間字樣。點了 → WidgetLink.today(那一場)。
//
// 規格見 scratchpad/widgets/v1/brief.md 的 G2。
//
// 為什麼每分鐘一筆 entry（brief §6）：
//   • Text(date, style: .relative／.timer) 會帶秒、每秒跳（「25 分鐘 10 秒」「25:10」），不是「25 分後」。
//   • iOS 18 新的 SystemFormatStyle 寫法沒把握，不用。
//   • timeline 裡的 entry 不算每天的重新整理額度（額度算 getTimeline 被叫幾次）；
//     只有「90 分鐘內有倒數」時才每分鐘一筆（軸上「現在」那道線另外每 10 分鐘一筆），
//     視窗 2 小時，到了再要一次新的。
//
// 換日：快照裡有今天、明天兩份；timeline 在 00:00 放一筆，day(at:) 自己換到明天那一份。
// 過了 validUntil（後天 00:00）整份不能用，請使用者打開 App。
//
// [v2] StandBy（privacy）的行程標題改寫主題（WidgetStop.lockedSurfaceTitle，使用者決定 2）；
//      部屬姓名（stop.owner）照舊不寫，全天的事照舊 lockTitle（生日只寫「家人生日」）。
//      TodayWidgetTimeline 也給鎖定畫面「下一場」（LockScreenWidgets.swift）共用。
//
// 旅遊期間（使用者過幾天出國）：景點是 kind == .trip 的 stop（App 的 TodayAgenda 挑的，
// 跟靈動島同一段），這裡照一般行程畫：小飛機記號、站名、點了開那一趟。
//
// 型別（internal 的都帶 TodayWidget 前綴；畫面零件 private）：
//   TodayWidget、TodayWidgetEntry、TodayWidgetProvider、TodayWidgetTimeline、
//   TodayWidgetModel、TodayWidgetRow、TodayWidgetChip、TodayWidgetAxis、TodayWidgetAxisDot、
//   TodayWidgetSample、TodayWidgetEntryView

// MARK: - Widget

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.today, provider: TodayWidgetProvider()) { entry in
            TodayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("今天")
        .description("下一場幾點、今天幾場、今天誰生日")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Timeline

struct TodayWidgetEntry: TimelineEntry {
    /// 畫面一律拿這個當「現在」（不在 View 裡呼叫 Date()）
    let date: Date
    /// nil＝還沒打開過新版 App（或檔案讀不到）
    let snapshot: WidgetLifeSnapshot?
}

struct TodayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayWidgetEntry {
        TodayWidgetSample.entry(now: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayWidgetEntry) -> Void) {
        if context.isPreview {
            // 小工具庫裡的預覽：寫死的樣本（10:05、下一場 10:30）
            completion(TodayWidgetSample.entry(now: Date()))
            return
        }
        let snapshot = WidgetSnapshotStore.read(WidgetLifeSnapshot.self)
        completion(TodayWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayWidgetEntry>) -> Void) {
        let now = Date()
        guard let snapshot = WidgetSnapshotStore.read(WidgetLifeSnapshot.self) else {
            // App 第一次寫完快照會叫重畫，這裡不用定時
            let only = TodayWidgetEntry(date: now, snapshot: nil)
            completion(Timeline(entries: [only], policy: .never))
            return
        }
        let plan = TodayWidgetTimeline.plan(snapshot: snapshot, now: now)
        let entries: [TodayWidgetEntry] = plan.dates.map { TodayWidgetEntry(date: $0, snapshot: snapshot) }
        let policy: TimelineReloadPolicy
        if let reloadAt = plan.reloadAt {
            policy = .after(reloadAt)
        } else {
            policy = .never
        }
        completion(Timeline(entries: entries, policy: policy))
    }
}

/// 「今天」哪些時間點要換畫面（brief §6）
enum TodayWidgetTimeline {
    /// 每分鐘一筆 entry 的視窗長度（2 小時）；到了就跟系統要一次新的 timeline
    static let tickWindow: TimeInterval = 120 * 60

    struct Plan {
        /// 依時間排好、不重複；至少一筆
        var dates: [Date]
        /// 什麼時候跟系統要新的 timeline；nil＝.never（整份快照都排完了）
        var reloadAt: Date?
    }

    static func plan(snapshot: WidgetLifeSnapshot, now: Date) -> Plan {
        let start = floorToMinute(now)
        let validUntil = snapshot.validUntil
        let windowEnd = min(start.addingTimeInterval(tickWindow), validUntil)

        var times = Set<Date>()
        times.insert(start)
        // 視窗內：有倒數字的那幾分鐘，每分鐘一筆；軸上「現在」那道線每 10 分鐘挪一次
        var tick = start.addingTimeInterval(60)
        while tick < windowEnd {
            if needsTick(snapshot: snapshot, at: tick) || needsAxisTick(snapshot: snapshot, at: tick) {
                times.insert(tick)
            }
            tick = tick.addingTimeInterval(60)
        }
        insertMilestones(into: &times, snapshot: snapshot)

        var dates: [Date] = times.filter { $0 >= start && $0 <= validUntil }.sorted()
        if dates.isEmpty {
            dates = [start]
        }
        let reloadAt: Date? = windowEnd < validUntil ? windowEnd : nil
        return Plan(dates: dates, reloadAt: reloadAt)
    }

    /// 這一分鐘畫面上有沒有倒數字（進行中那場的結束、下一場的開始在 90 分鐘內）
    static func needsTick(snapshot: WidgetLifeSnapshot, at time: Date) -> Bool {
        guard let day = snapshot.day(at: time) else { return false }
        if let cur = day.currentStop(at: time),
           WidgetDateText.countdown(to: cur.stop.end, from: time) != nil {
            return true
        }
        if let next = day.nextStop(at: time),
           WidgetDateText.countdown(to: next.stop.start, from: time) != nil {
            return true
        }
        return false
    }

    /// 軸上「現在」那道直線多久挪一次（分鐘）
    static let axisTickMinutes = 10

    /// [審查補] 軸上「現在」那道直線：在軸的範圍內（第一場開始～最後一場結束）每 10 分鐘一筆。
    /// brief §6 只排倒數與場次邊界；離下一場還很久（超過 90 分）時，沒有這條直線最久 2 小時才動
    ///（小型的軸一天 8 小時畫在約 138pt 上，2 小時≈32pt，看得出來）。一個視窗最多多 12 筆。
    static func needsAxisTick(snapshot: WidgetLifeSnapshot, at time: Date) -> Bool {
        let minuteIndex = Int((time.timeIntervalSinceReferenceDate / 60).rounded(.down))
        guard minuteIndex % axisTickMinutes == 0 else { return false }
        guard let day = snapshot.day(at: time), !day.stops.isEmpty else { return false }
        let state = DayTimelineAttributes.ContentState(stops: day.stops.map(\.stop))
        return state.nowPosition(time) != nil
    }

    /// 換日、每場開始／結束、倒數開始出現、快照過期、「10:02 更新」出現的那一刻
    private static func insertMilestones(into times: inout Set<Date>, snapshot: WidgetLifeSnapshot) {
        let lead = TimeInterval(WidgetFreshness.countdownMaxMinutes * 60)
        for day in snapshot.days {
            times.insert(day.dayStart)
            times.insert(day.dayEnd)
            for item in day.stops {
                let stop = item.stop
                times.insert(stop.start)
                times.insert(stop.end)
                times.insert(stop.start.addingTimeInterval(-lead))
                times.insert(stop.end.addingTimeInterval(-lead))
            }
        }
        times.insert(snapshot.validUntil)
        // showsUpdatedAt 是「超過」三小時（>），多 1 秒才會翻過去
        times.insert(snapshot.generatedAt.addingTimeInterval(WidgetFreshness.lifeShowUpdatedAfter + 1))
    }

    /// 往下取整到分鐘（倒數字的分鐘是無條件進位，從整分算起才不會差一分）
    static func floorToMinute(_ date: Date) -> Date {
        let seconds = (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60
        return Date(timeIntervalSinceReferenceDate: seconds)
    }
}

// MARK: - 畫面要的字（全部在這裡組好，body 只讀）

/// 中型的一列：一場行程，或一句話（「今天的行程結束了」）
struct TodayWidgetRow: Identifiable {
    let id: String
    /// nil＝一句話，不畫點、不畫時間
    let kind: TimelineStopKind?
    /// 「10:30」「明天 08:30」；一句話時是空字串
    let time: String
    let title: String
    /// 灰字（部屬姓名、地點…）；StandBy／隱私時是空字串
    let owner: String
    /// 最右邊：「進行中」「25 分後」或空字串
    let trailing: String
    let url: URL

    var isMessage: Bool { kind == nil }
}

/// 中型的全天的事膠囊
struct TodayWidgetChip: Identifiable {
    let id: String
    let icon: String
    let text: String
}

/// 軸上的一個點
struct TodayWidgetAxisDot: Identifiable {
    let id: String
    let kind: TimelineStopKind
    /// 0…1
    let position: Double
    /// 已經結束（淡色）
    let isDone: Bool
}

/// 今天的軸（位置用靈動島的 ContentState.position／nowPosition 算，同一條軸）
struct TodayWidgetAxis {
    let dots: [TodayWidgetAxisDot]
    /// 現在那一道直線；還沒開始或已經結束是 nil
    let now: Double?
    /// 中型兩端的時間：第一場開始、最後一場結束
    let startText: String
    let endText: String
}

struct TodayWidgetModel {
    enum Kind {
        /// 一句話（沒快照、過期）
        case message
        /// 有一場進行中
        case live
        /// 下一場還沒開始
        case upcoming
        /// 今天的都跑完了
        case finished
        /// 今天沒有排行程
        case free
    }

    var kind: Kind = .message
    var message = ""

    // 小型
    var dateText = ""
    /// 右上「4 場」
    var countText = ""
    /// 小標「下一場・25 分後」
    var label = ""
    /// 大字前面的小字「到」「明天」
    var heroPrefix = ""
    /// 大字「10:30」
    var hero = ""
    /// 第二行（標題）
    var line = ""
    var lineLimit = 1
    /// 最下面：第一件全天的事
    var footIcon = ""
    var footText = ""
    var axis: TodayWidgetAxis? = nil

    // StandBy（大字＋一行類別＋一行倒數）
    var standByLine = ""
    var standBySub = ""
    var standBySubIsCountdown = false

    // 中型
    /// 「今天 4 場・還剩 3 場」
    var summary = ""
    var greeting: [String] = []
    var chips: [TodayWidgetChip] = []
    /// 「＋2 件」
    var moreChips = ""
    var rows: [TodayWidgetRow] = []
    /// 「10:02 更新」（快照超過 3 小時才有）
    var updatedText = ""

    /// 小型整塊點下去
    var tapURL: URL = WidgetLink.today(nil)

    /// privacy＝StandBy（背景被拿掉）：標題換成 lockedSurfaceTitle（[v2] 主題，不含人名）、不寫 owner、
    /// 全天的事用 lockTitle（J:177）
    static func make(snapshot: WidgetLifeSnapshot?, now: Date, privacy: Bool) -> TodayWidgetModel {
        var model = TodayWidgetModel()
        guard let snap = snapshot else {
            model.message = "打開 LifeGood 一次，這裡就會出現今天的行程"
            return model
        }
        guard let day = snap.day(at: now) else {
            model.message = "打開 LifeGood 更新今天的行程"
            return model
        }
        model.dateText = day.dateText
        model.greeting = day.greeting
        model.axis = TodayWidgetText.axis(day: day, now: now)
        if snap.showsUpdatedAt(at: now) {
            model.updatedText = WidgetDateText.updatedAt(snap.generatedAt, now: now)
        }
        TodayWidgetText.fillAllDay(&model, day: day, privacy: privacy)
        let rowLimit = model.updatedText.isEmpty ? 3 : 2
        model.rows = TodayWidgetText.rows(day: day, now: now, privacy: privacy, limit: rowLimit)

        if day.stops.isEmpty {
            TodayWidgetText.fillFree(&model, day: day, privacy: privacy)
        } else if let cur = day.currentStop(at: now) {
            TodayWidgetText.fillLive(&model, day: day, stop: cur, now: now, privacy: privacy)
        } else if let next = day.nextStop(at: now) {
            TodayWidgetText.fillUpcoming(&model, day: day, stop: next, now: now, privacy: privacy)
        } else {
            TodayWidgetText.fillFinished(&model, day: day, privacy: privacy)
        }
        return model
    }
}

/// 組字的小函式（只拼日期、時間、標題，不碰金額）
private enum TodayWidgetText {
    static func title(_ item: WidgetStop, privacy: Bool) -> String {
        if privacy {
            // [v2] 決定 2：StandBy 寫會議主題（旅遊寫站名／住宿），部屬姓名不寫
            let locked = item.lockedSurfaceTitle
            return locked.isEmpty ? item.stop.kind.label : locked
        }
        return item.stop.title.isEmpty ? "未命名行程" : item.stop.title
    }

    static func countSummary(_ day: WidgetLifeDay, now: Date) -> String {
        let total = day.stops.count
        let left = day.remainingStops(at: now).count
        if left == 0 { return "今天 \(total) 場・都結束了" }
        return "今天 \(total) 場・還剩 \(left) 場"
    }

    static func fillAllDay(_ model: inout TodayWidgetModel, day: WidgetLifeDay, privacy: Bool) {
        let items = day.allDay
        let chips: [TodayWidgetChip] = items.prefix(2).map { item in
            TodayWidgetChip(id: item.id, icon: item.icon, text: privacy ? item.lockTitle : item.title)
        }
        model.chips = chips
        model.moreChips = items.count > 2 ? "＋\(items.count - 2) 件" : ""
        if let first = items.first {
            model.footIcon = first.icon
            model.footText = privacy ? first.lockTitle : first.shortTitle
        }
    }

    /// 進行中：「進行中・40 分後結束」「到 11:30」
    static func fillLive(_ model: inout TodayWidgetModel, day: WidgetLifeDay, stop: WidgetStop,
                         now: Date, privacy: Bool) {
        let countdown = WidgetDateText.countdown(to: stop.stop.end, from: now)
        model.kind = .live
        model.countText = "\(day.stops.count) 場"
        model.summary = countSummary(day, now: now)
        model.label = countdown.map { "進行中・" + $0 + "結束" } ?? "進行中"
        model.heroPrefix = "到"
        model.hero = DayTimelineFormat.time(stop.stop.end)
        model.line = title(stop, privacy: privacy)
        model.standByLine = title(stop, privacy: true)
        model.standBySub = countdown.map { $0 + "結束" } ?? "進行中"
        model.standBySubIsCountdown = countdown != nil
        model.tapURL = WidgetLink.today(stop.stop)
    }

    /// 下一場：「今天第一場・50 分後」「下一場・25 分後」「10:30」
    static func fillUpcoming(_ model: inout TodayWidgetModel, day: WidgetLifeDay, stop: WidgetStop,
                             now: Date, privacy: Bool) {
        let countdown = WidgetDateText.countdown(to: stop.stop.start, from: now)
        let isFirst = stop.id == day.stops.first?.id
        let head = isFirst ? "今天第一場" : "下一場"
        model.kind = .upcoming
        model.countText = "\(day.stops.count) 場"
        model.summary = countSummary(day, now: now)
        model.label = countdown.map { head + "・" + $0 } ?? head
        model.hero = DayTimelineFormat.time(stop.stop.start)
        model.line = title(stop, privacy: privacy)
        model.standByLine = title(stop, privacy: true)
        model.standBySub = countdown ?? head
        model.standBySubIsCountdown = countdown != nil
        model.tapURL = WidgetLink.today(stop.stop)
    }

    /// 都跑完了：「今天的行程結束了」「明天 08:30」「早會」
    static func fillFinished(_ model: inout TodayWidgetModel, day: WidgetLifeDay, privacy: Bool) {
        model.kind = .finished
        model.countText = "\(day.stops.count) 場"
        model.summary = "今天 \(day.stops.count) 場・都結束了"
        model.label = "今天的行程結束了"
        model.standBySub = "今天的行程結束了"
        if let next = day.nextDayFirstStop {
            model.heroPrefix = "明天"
            model.hero = DayTimelineFormat.time(next.stop.start)
            model.line = title(next, privacy: privacy)
            model.standByLine = title(next, privacy: true)
        } else {
            // 大字已經是「明天」，下面不再重複「明天」兩個字（StandBy 也一樣）
            model.hero = "明天"
            model.line = "還沒有排行程"
            model.standByLine = "還沒有排行程"
        }
        model.tapURL = WidgetLink.today(nil)
    }

    /// 今天沒有排行程：大字寫日期，第二行寫第一件全天的事或「好好過一天」
    static func fillFree(_ model: inout TodayWidgetModel, day: WidgetLifeDay, privacy: Bool) {
        let first = day.allDay.first
        let lockText = first?.lockTitle ?? "好好過一天"
        model.kind = .free
        model.summary = "今天沒有排行程"
        model.label = "今天沒有排行程"
        model.hero = day.shortDateText
        model.line = privacy ? lockText : (first?.title ?? "好好過一天")
        model.lineLimit = 2
        // 第二行已經寫了全天的事，最下面不重複
        model.footIcon = ""
        model.footText = ""
        model.standByLine = lockText
        model.standBySub = "今天沒有排行程"
        model.tapURL = WidgetLink.today(nil)
    }

    /// 中型下面那幾列
    static func rows(day: WidgetLifeDay, now: Date, privacy: Bool, limit: Int) -> [TodayWidgetRow] {
        let remaining = day.remainingStops(at: now)
        if !remaining.isEmpty {
            return remaining.prefix(limit).map { stopRow($0, now: now, privacy: privacy) }
        }
        var out: [TodayWidgetRow] = []
        if !day.stops.isEmpty {
            out.append(messageRow(id: "lg-row-done", text: "今天的行程結束了"))
        }
        if let next = day.nextDayFirstStop {
            out.append(tomorrowRow(next, privacy: privacy))
        } else if day.stops.isEmpty {
            out.append(messageRow(id: "lg-row-free", text: "好好過一天"))
        } else {
            out.append(messageRow(id: "lg-row-none", text: "明天還沒有排行程"))
        }
        return out
    }

    static func stopRow(_ item: WidgetStop, now: Date, privacy: Bool) -> TodayWidgetRow {
        let trailing: String
        if item.stop.start <= now {
            trailing = "進行中"
        } else {
            trailing = WidgetDateText.countdown(to: item.stop.start, from: now) ?? ""
        }
        return TodayWidgetRow(id: item.id,
                              kind: item.stop.kind,
                              time: DayTimelineFormat.time(item.stop.start),
                              title: title(item, privacy: privacy),
                              owner: privacy ? "" : item.stop.owner,
                              trailing: trailing,
                              url: WidgetLink.today(item.stop))
    }

    static func tomorrowRow(_ item: WidgetStop, privacy: Bool) -> TodayWidgetRow {
        TodayWidgetRow(id: "lg-row-tomorrow-" + item.id,
                       kind: item.stop.kind,
                       time: "明天 " + DayTimelineFormat.time(item.stop.start),
                       title: title(item, privacy: privacy),
                       owner: privacy ? "" : item.stop.owner,
                       trailing: "",
                       url: WidgetLink.today(item.stop))
    }

    static func messageRow(id: String, text: String) -> TodayWidgetRow {
        TodayWidgetRow(id: id, kind: nil, time: "", title: text, owner: "", trailing: "",
                       url: WidgetLink.today(nil))
    }

    /// 軸：用靈動島 ContentState 的同一套位置算法（共用檔 DayTimelineAttributes.swift）
    static func axis(day: WidgetLifeDay, now: Date) -> TodayWidgetAxis? {
        guard !day.stops.isEmpty else { return nil }
        let state = DayTimelineAttributes.ContentState(stops: day.stops.map(\.stop))
        let dots: [TodayWidgetAxisDot] = day.stops.map { item in
            TodayWidgetAxisDot(id: item.id,
                               kind: item.stop.kind,
                               position: state.position(of: item.stop),
                               isDone: item.stop.end <= now)
        }
        return TodayWidgetAxis(dots: dots,
                               now: state.nowPosition(now),
                               startText: DayTimelineFormat.time(state.axisStart),
                               endText: DayTimelineFormat.time(state.axisEnd))
    }
}

/// 小工具庫預覽與 placeholder 的樣本。**寫死的展示字**（J:127-134）：
/// 10/13 週二 10:05、4 場、下一場 10:30 CDA 異常檢討、媽媽 62 歲生日。
enum TodayWidgetSample {
    static func entry(now: Date) -> TodayWidgetEntry {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: now)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 3600)
        let validUntil = cal.date(byAdding: .day, value: 2, to: dayStart) ?? dayEnd.addingTimeInterval(24 * 3600)
        let sampleNow = at(dayStart, 10, 5)
        let day = WidgetLifeDay(dayKey: WidgetDateText.dayKey(dayStart),
                                dayStart: dayStart,
                                dayEnd: dayEnd,
                                dateText: "10/13 週二",
                                shortDateText: "10/13",
                                stops: stops(dayStart),
                                allDay: allDay,
                                greeting: ["Have a nice", "Tuesday!"],
                                hidesMeetings: false,
                                nextDayFirstStop: nil)
        let snapshot = WidgetLifeSnapshot(generatedAt: sampleNow,
                                          dataDay: WidgetDateText.dayKey(dayStart),
                                          validUntil: validUntil,
                                          days: [day])
        return TodayWidgetEntry(date: sampleNow, snapshot: snapshot)
    }

    private static func at(_ dayStart: Date, _ hour: Int, _ minute: Int) -> Date {
        dayStart.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
    }

    private static func stops(_ dayStart: Date) -> [WidgetStop] {
        let s1 = TimelineStop(id: "sample-1", title: "早會", start: at(dayStart, 8, 30),
                              durationMinutes: 30, owner: "會議室", detail: "", kind: .personal)
        let s2 = TimelineStop(id: "sample-2", title: "CDA 異常檢討", start: at(dayStart, 10, 30),
                              durationMinutes: 60, owner: "王小明", detail: "", kind: .meeting)
        let s3 = TimelineStop(id: "sample-3", title: "機台 PM 排程", start: at(dayStart, 14, 0),
                              durationMinutes: 60, owner: "工作", detail: "", kind: .appleCalendar)
        let s4 = TimelineStop(id: "sample-4", title: "接女兒", start: at(dayStart, 16, 30),
                              durationMinutes: 30, owner: "幼兒園", detail: "", kind: .personal)
        return [
            WidgetStop(stop: s1, location: "", lockTitle: "會議"),
            WidgetStop(stop: s2, location: "", lockTitle: "部屬會議"),
            WidgetStop(stop: s3, location: "", lockTitle: "系統行事曆"),
            WidgetStop(stop: s4, location: "", lockTitle: "事務")
        ]
    }

    private static var allDay: [WidgetAllDayItem] {
        [
            WidgetAllDayItem(id: "sample-bd", kind: .birthday, title: "媽媽 62 歲生日",
                             shortTitle: "媽媽生日", lockTitle: "家人生日", icon: "birthday.cake.fill"),
            WidgetAllDayItem(id: "sample-sr", kind: .sideRole, title: "尾牙：場勘日",
                             shortTitle: "尾牙：場勘日", lockTitle: "兼任職務", icon: "flag.fill")
        ]
    }
}

// MARK: - 畫面

struct TodayWidgetEntryView: View {
    let entry: TodayWidgetEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    private var surface: WidgetPalette.Surface {
        WidgetPalette.Surface(renderingMode: renderingMode, showsBackground: showsBackground)
    }

    private var palette: WidgetPalette {
        WidgetPalette(colorScheme, mono: surface.isMono)
    }

    private var model: TodayWidgetModel {
        TodayWidgetModel.make(snapshot: entry.snapshot, now: entry.date, privacy: surface.isStandBy)
    }

    private var isMedium: Bool { family == .systemMedium }

    /// 小型整塊開那一場；中型每一列各自是 Link，其他地方開我的行事曆（J:167）
    private var tapURL: URL {
        isMedium ? WidgetLink.today(nil) : model.tapURL
    }

    /// 中型右上角有手寫問候，月牙／雲不放右上（J:56）；小型右上有「4 場」，放大字那一列旁
    private var skyMoon: WidgetSkyMoon {
        isMedium ? WidgetSkyMoon.topLeading : WidgetSkyMoon.middleTrailing
    }

    var body: some View {
        TodayWidgetContent(model: model, palette: palette,
                           standBy: surface.isStandBy, isMedium: isMedium)
            .containerBackground(for: .widget) {
                backgroundView
            }
            .widgetURL(tapURL)
    }

    @ViewBuilder
    private var backgroundView: some View {
        if surface.drawsSky {
            WidgetSky(palette: palette, moon: skyMoon)
        } else {
            Color.clear
        }
    }
}

/// 依尺寸、狀態挑版面
private struct TodayWidgetContent: View {
    let model: TodayWidgetModel
    let palette: WidgetPalette
    let standBy: Bool
    let isMedium: Bool

    var body: some View {
        if model.kind == .message {
            TodayMessageView(text: model.message, palette: palette)
        } else if isMedium {
            TodayMediumView(model: model, palette: palette)
        } else if standBy {
            TodayStandByView(model: model, palette: palette)
        } else {
            TodaySmallView(model: model, palette: palette)
        }
    }
}

/// 大字：「10:30」「到 11:30」「明天 08:30」（著色模式染重點色）
private struct TodayHero: View {
    let prefix: String
    let text: String
    let palette: WidgetPalette
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            if !prefix.isEmpty {
                // 不准被擠成兩行（StandBy 40pt「明天 08:30」超過 138pt 寬時，縮的是後面的時間）
                Text(prefix)
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .fixedSize()
            }
            Text(text)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
        }
    }
}

// MARK: 小型

/// 第一列日期＋場數、小標、大字、標題、軸、第一件全天的事。
/// 放不下時先拿掉軸，全天的事那一行保留（ViewThatFits 由上往下挑第一個放得下的）。
private struct TodaySmallView: View {
    let model: TodayWidgetModel
    let palette: WidgetPalette

    var body: some View {
        ViewThatFits(in: .vertical) {
            column(showsAxis: true)
            column(showsAxis: false)
        }
    }

    private func column(showsAxis: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            // 最長「進行中・1 小時 30 分後結束」約 150pt，比小型內容寬（約 138pt）長：縮字不截斷
            Text(model.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.label)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.top, 2)
            TodayHero(prefix: model.heroPrefix, text: model.hero, palette: palette, size: 32)
            lineText
            Spacer(minLength: 4)
            axisRow(showsAxis: showsAxis)
            footRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text(model.dateText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.inkDate)
            Spacer(minLength: 2)
            // mock_spec today-small：「10/13 週二　　4 場」整列同一色（inkDate）
            Text(model.countText)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(palette.inkDate)
        }
        .lineLimit(1)
    }

    private var lineText: some View {
        Text(model.line)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(palette.ink)
            .lineLimit(model.lineLimit)
            .minimumScaleFactor(0.85)
    }

    @ViewBuilder
    private func axisRow(showsAxis: Bool) -> some View {
        if showsAxis, let axis = model.axis {
            TodayAxisView(axis: axis, palette: palette, showsTimes: false)
        }
    }

    @ViewBuilder
    private var footRow: some View {
        if !model.footText.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: model.footIcon)
                    .font(.system(size: 10, weight: .semibold))
                Text(model.footText)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(palette.label)
            .padding(.top, 5)
        }
    }
}

/// StandBy：大字時間、一行標題（[v2] lockedSurfaceTitle：主題，不寫人名）、一行倒數（樣稿 today-standby）
private struct TodayStandByView: View {
    let model: TodayWidgetModel
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TodayHero(prefix: model.heroPrefix, text: model.hero, palette: palette, size: 40)
            Text(model.standByLine)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(model.standBySub)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(subColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var subColor: Color {
        model.standBySubIsCountdown ? palette.countdown : palette.label
    }
}

// MARK: 中型

/// 日期＋手寫問候、「今天 4 場・還剩 3 場」、全天的事膠囊（或軸）、最多 3 列。
/// 矮的中型（SE 一類，約 148pt 高）三列加膠囊放不下時，退成兩列（ViewThatFits 由上往下挑）。
private struct TodayMediumView: View {
    let model: TodayWidgetModel
    let palette: WidgetPalette

    var body: some View {
        ViewThatFits(in: .vertical) {
            column(rows: model.rows)
            column(rows: Array(model.rows.prefix(2)))
        }
    }

    private func column(rows: [TodayWidgetRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TodayMediumHeader(model: model, palette: palette)
            middleRow
                .padding(.top, 6)
            Spacer(minLength: 4)
            TodayRowsList(rows: rows, updatedText: model.updatedText, palette: palette)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 有全天的事畫膠囊；沒有就畫今天的軸，兩端寫第一場開始與最後一場結束（J:163）
    @ViewBuilder
    private var middleRow: some View {
        if !model.chips.isEmpty {
            TodayChipsRow(chips: model.chips, more: model.moreChips, palette: palette)
        } else if let axis = model.axis {
            TodayAxisView(axis: axis, palette: palette, showsTimes: true)
        }
    }
}

/// 左邊日期＋場數，右上手寫問候；放不下就不寫問候（J:164）
private struct TodayMediumHeader: View {
    let model: TodayWidgetModel
    let palette: WidgetPalette

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 8) {
                titles
                Spacer(minLength: 8)
                greetingView
            }
            titles
        }
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.dateText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.inkDate)
            Text(model.summary)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
        }
    }

    /// App 的手寫字（TripScriptFont.greeting，同一個字型），往左上斜 8°
    @ViewBuilder
    private var greetingView: some View {
        if !model.greeting.isEmpty {
            Text(model.greeting.joined(separator: "\n"))
                .font(Font.custom("BradleyHandITCTT-Bold", fixedSize: 15))
                .foregroundStyle(palette.ink.opacity(0.85))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .rotationEffect(.degrees(-8))
                .padding(.trailing, 2)
        }
    }
}

/// 全天的事：最多 2 顆膠囊，多的寫「＋N 件」
private struct TodayChipsRow: View {
    let chips: [TodayWidgetChip]
    let more: String
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 6) {
            ForEach(chips, id: \.id) { chip in
                chipView(chip)
            }
            if !more.isEmpty {
                // 膠囊太長時縮的是膠囊裡的字，「＋2 件」不准被截成「…」
                Text(more)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.label)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    private func chipView(_ chip: TodayWidgetChip) -> some View {
        HStack(spacing: 3) {
            Image(systemName: chip.icon)
                .font(.system(size: 9, weight: .bold))
            Text(chip.text)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(palette.capsuleText)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(palette.capsuleFill, in: Capsule())
    }
}

/// 中型下面幾列；每一列是一個 Link（點了開那一場，J:162、167）
private struct TodayRowsList: View {
    let rows: [TodayWidgetRow]
    let updatedText: String
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(rows, id: \.id) { row in
                Link(destination: row.url) {
                    TodayRowView(row: row, palette: palette)
                }
            }
            if !updatedText.isEmpty {
                updatedLine
            }
        }
    }

    /// 快照超過 3 小時：右下角小字「10:02 更新」（J:165）
    private var updatedLine: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(updatedText)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(palette.label)
                .lineLimit(1)
        }
    }
}

/// 一列：記號、時間、標題、owner（灰）、最右邊「進行中」或倒數
private struct TodayRowView: View {
    let row: TodayWidgetRow
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 6) {
            markView
            timeText
            Text(row.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(titleColor)
                .lineLimit(1)
            Spacer(minLength: 4)
            sideColumns
        }
    }

    private var titleColor: Color {
        row.isMessage ? palette.label : palette.ink
    }

    @ViewBuilder
    private var markView: some View {
        if let kind = row.kind {
            WidgetStopMark(kind: kind, color: palette.dot(kind), size: 8)
                .frame(width: 10, height: 10)
        }
    }

    @ViewBuilder
    private var timeText: some View {
        if !row.time.isEmpty {
            Text(row.time)
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// owner 與倒數各佔固定寬度，三列才對得齊
    @ViewBuilder
    private var sideColumns: some View {
        if !row.isMessage {
            Text(row.owner)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(palette.label)
                .lineLimit(1)
                .frame(width: 52, alignment: .leading)
            Text(row.trailing)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(palette.countdown)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 70, alignment: .trailing)
        }
    }
}

// MARK: 軸

/// 今天的軸：每站一個記號（已結束淡色），現在一道直線。showsTimes＝兩端寫時間（中型）
private struct TodayAxisView: View {
    let axis: TodayWidgetAxis
    let palette: WidgetPalette
    let showsTimes: Bool

    var body: some View {
        if showsTimes {
            HStack(spacing: 6) {
                timeLabel(axis.startText)
                track
                timeLabel(axis.endText)
            }
        } else {
            track
        }
    }

    private var track: some View {
        GeometryReader { geo in
            TodayAxisTrack(axis: axis, palette: palette, width: geo.size.width)
        }
        .frame(height: 12)
    }

    private func timeLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(palette.label)
            .fixedSize()
    }
}

private struct TodayAxisTrack: View {
    let axis: TodayWidgetAxis
    let palette: WidgetPalette
    let width: CGFloat

    private let inset: CGFloat = 6
    private let markSize: CGFloat = 8

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(palette.axisTrack)
                .frame(width: usable, height: 1.5)
                .offset(x: inset)
            nowMarker
            ForEach(axis.dots, id: \.id) { dot in
                markView(dot)
            }
        }
        .frame(width: width, height: 12, alignment: .leading)
    }

    private var usable: CGFloat { max(0, width - inset * 2) }

    private var markBox: CGFloat { markSize + 2 }

    private func x(_ position: Double) -> CGFloat {
        inset + usable * CGFloat(position)
    }

    @ViewBuilder
    private var nowMarker: some View {
        if let position = axis.now {
            Capsule()
                .fill(palette.ink)
                .frame(width: 2, height: 12)
                .offset(x: x(position) - 1)
        }
    }

    private func markView(_ dot: TodayWidgetAxisDot) -> some View {
        WidgetStopMark(kind: dot.kind, color: palette.dot(dot.kind), size: markSize)
            .frame(width: markBox, height: markBox)
            .opacity(dot.isDone ? 0.4 : 1)
            .offset(x: x(dot.position) - markBox / 2)
    }
}

// MARK: 一句話

/// 沒快照／過期：只寫一句話
private struct TodayMessageView: View {
    let text: String
    let palette: WidgetPalette

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.label)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
