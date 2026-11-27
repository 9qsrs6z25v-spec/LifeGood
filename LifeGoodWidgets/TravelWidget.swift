import SwiftUI
import WidgetKit

// MARK: - 旅行（systemSmall、systemMedium、accessoryRectangular）（小工具 v3）
//
// 只屬於「LifeGoodWidgets」target。由 G3 實作，規格見 scratchpad/widgets/v3/brief.md 的 G3-2；judge.md §2.8（J:331）；
// 字照 design_life.md L4 的出發前／旅途中（封面、天氣、打卡按鈕這版不做）。
//
// 只讀 life_v1.json：trips（WidgetLifeSnapshot.tripPhase(at:)）＋今天的旅遊景點（WidgetLifeDay.nextTripStop(at:)／
// remainingTripStops(at:)）。**不篩種類**（旅遊景點本來就是 kind == .trip）。
// 出發前「✈ <行程名>／<N> 天／<M/d (週)> 出發」；旅途中「第 2 天／共 7 天・下一站 <景點> <16:20>」；
// 回來後換下一趟（快照最多帶 3 趟還沒回來的），沒有就「還沒有排下一趟旅行」。
// 第幾天、共幾天、還有幾天只用 tripPhase 給的整數（日差不是金額，小工具可以算）；日期字只用
// WidgetDateText.billDate、時間只用 DayTimelineFormat.time。
//
// 隱私：鎖定畫面長方形、StandBy 的景點名用 WidgetStop.lockedSurfaceTitle（旅遊景點＝站名，過夜那一站「住宿」，J:298）；
// 行程名照寫（使用者決定：鎖定畫面放項目名稱、不放人名）。主畫面寫站名（stop.title）。
//
// 點了去哪：整塊 → 那一趟（WidgetTrip.url＝lifegood://life/trip?id=…&src=widget）；沒有下一趟／沒快照 → 旅遊地圖（WidgetLink.trip(nil)）。
//
// 型別（internal 的都帶 TravelWidget 前綴；畫面零件 private，也帶 TravelWidget 前綴）：
//   TravelWidget、TravelWidgetEntry、TravelWidgetProvider、TravelWidgetTimeline、
//   TravelWidgetRow、TravelWidgetModel、TravelWidgetSample、TravelWidgetEntryView

// MARK: - Widget

struct TravelWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.travel, provider: TravelWidgetProvider()) { entry in
            TravelWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("旅行")
        .description("下一趟還有幾天、旅途中第幾天、下一站；大的列出今天每一站")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

// MARK: - Timeline

struct TravelWidgetEntry: TimelineEntry {
    /// 畫面一律拿這個當「現在」（不在 View 裡呼叫 Date()）
    let date: Date
    /// nil＝還沒打開過新版 App（或檔案讀不到）
    let snapshot: WidgetLifeSnapshot?
}

struct TravelWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TravelWidgetEntry {
        TravelWidgetSample.entry()
    }

    func getSnapshot(in context: Context, completion: @escaping (TravelWidgetEntry) -> Void) {
        if context.isPreview {
            // 小工具庫裡的預覽：寫死的樣本（勇闖福岡親子行、38 天、11/20 (週五) 出發、行李 8/15）
            completion(TravelWidgetSample.entry())
            return
        }
        let snapshot = WidgetSnapshotStore.read(WidgetLifeSnapshot.self)
        completion(TravelWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TravelWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshotStore.read(WidgetLifeSnapshot.self)
        let dates = TravelWidgetTimeline.entryDates(snapshot: snapshot, now: now)
        let entries: [TravelWidgetEntry] = dates.map { TravelWidgetEntry(date: $0, snapshot: snapshot) }
        let policy = TravelWidgetTimeline.policy(dates: dates, now: now)
        completion(Timeline(entries: entries, policy: policy))
    }
}

/// 旅行哪些時間點要換畫面（brief G3-2 第 3 點）
enum TravelWidgetTimeline {
    /// 每天 00:00 一筆，最多排這麼多天；排不到回程那一刻的，排到第 60 個 00:00 就跟系統要新的
    static let maxMidnights = 60

    /// now ∪ 明天起每天 00:00（到那一趟的 afterLastDay 為止）∪ 那一趟的 firstDay、afterLastDay
    ///（出國換了時區，這兩個不一定落在本地的 00:00）∪ 快照裡每一天的開始／結束、旅遊景點的開始／結束
    /// ∪ 快照過期那一刻（validUntil）。全部要比 now 晚、不超過這份 timeline 排到的地方。
    /// 沒快照、舊檔沒有 trips、沒有下一趟：只有 now（App 改了行程會叫重畫：WidgetKind.lifeKinds 已含旅行）。
    static func entryDates(snapshot: WidgetLifeSnapshot?, now: Date) -> [Date] {
        guard let snap = snapshot, let trip = activeTrip(in: snap, now: now) else { return [now] }
        let midnights = upcomingMidnights(after: now, through: trip.afterLastDay)
        let horizon = scheduleEnd(midnights: midnights, trip: trip)
        var times = Set<Date>(midnights)
        times.insert(trip.firstDay)
        times.insert(trip.afterLastDay)
        times.insert(snap.validUntil)
        insertStopTimes(into: &times, snapshot: snap)
        let later: [Date] = times.filter { $0 > now && $0 <= horizon }.sorted()
        return [now] + later
    }

    /// 排完最後一筆就跟系統要新的（回程那一刻換下一趟）；只有 now 就 .never
    static func policy(dates: [Date], now: Date) -> TimelineReloadPolicy {
        guard let last = dates.last, last > now else { return .never }
        return .after(last)
    }

    /// tripPhase 挑到的那一趟（出發前或旅途中）；沒有下一趟回 nil
    static func activeTrip(in snapshot: WidgetLifeSnapshot, now: Date) -> WidgetTrip? {
        switch snapshot.tripPhase(at: now) {
        case .noTrip:
            return nil
        case .upcoming(let trip, daysUntil: _):
            return trip
        case .during(let trip, day: _):
            return trip
        }
    }

    /// 明天起每天 00:00（本地時間），到 end 為止（含），最多 maxMidnights 個
    private static func upcomingMidnights(after now: Date, through end: Date) -> [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var out: [Date] = []
        var offset = 1
        while out.count < maxMidnights {
            guard let next = cal.date(byAdding: .day, value: offset, to: today), next <= end else { break }
            out.append(next)
            offset += 1
        }
        return out
    }

    /// 這份 timeline 排到哪：排滿 maxMidnights 天還沒到回程，就只排到最後一個 00:00
    private static func scheduleEnd(midnights: [Date], trip: WidgetTrip) -> Date {
        guard midnights.count >= maxMidnights, let last = midnights.last else { return trip.afterLastDay }
        return min(last, trip.afterLastDay)
    }

    /// 快照裡每一天的開始／結束、旅遊景點的開始／結束（下一站、進行中跟著換）
    private static func insertStopTimes(into times: inout Set<Date>, snapshot: WidgetLifeSnapshot) {
        for day in snapshot.days {
            times.insert(day.dayStart)
            times.insert(day.dayEnd)
            for item in day.stops where item.stop.kind == .trip {
                times.insert(item.stop.start)
                times.insert(item.stop.end)
            }
        }
    }
}

// MARK: - 畫面要的字（全部在這裡組好，body 只讀）

/// 中型旅途中的一列：一個景點，或一句話（「今天的行程走完了」）
struct TravelWidgetRow: Identifiable {
    let id: String
    /// 「16:20」「明天 09:00」；一句話時是空字串
    let time: String
    let title: String
    /// 最右邊：「下一站」「進行中」或空字串
    let trailing: String
    /// 一句話：不畫小飛機、字用灰色
    let isMessage: Bool
}

struct TravelWidgetModel {
    enum Kind {
        /// 沒快照、舊檔沒有 trips：「打開 LifeGood 一次，這裡就會出現下一趟旅行」
        case message
        /// 沒有下一趟：「還沒有排下一趟旅行」
        case noTrip
        /// 還沒出發
        case upcoming
        /// 旅途中（出發那天 00:00 起）
        case during
    }

    var kind: Kind = .message
    /// 一句話（message、noTrip）
    var message = ""
    /// 中型一句話下面的小字（noTrip：「在 LifeGood 的旅遊地圖排一趟」）
    var hint = ""
    /// 行程名「勇闖福岡親子行」
    var tripTitle = ""

    // 大字：「38」＋小字「天」、「明天」、小字「第」＋「2」＋小字「天」
    var heroPrefix = ""
    var hero = ""
    var heroSuffix = ""

    // 小型（主畫面、StandBy）大字下面兩行
    /// 「11/20 (週五) 出發」「共 7 天」
    var smallLine1 = ""
    /// 「行李 8/15」「下一站 天神地下街 16:20」「今天的行程走完了」；旅途中快照過期是空字串
    var smallLine2 = ""

    // 中型・出發前
    /// 左上「下一趟旅行」
    var upcomingLabel = ""
    /// 大字下面「後出發」「出發」
    var heroCaption = ""
    /// 「11/20 (週五) 出發・共 7 天」
    var dateLine = ""
    /// 「行李 8/15」；沒有行李清單是空字串
    var packingLine = ""

    // 中型・旅途中
    /// 右上「第 2 天／共 7 天」
    var dayText = ""
    var rows: [TravelWidgetRow] = []

    // 鎖定畫面長方形（三行：粗、一般、淡）
    var rectLine1 = ""
    var rectLine2 = ""
    var rectLine3 = ""

    /// 整塊點下去：那一趟；沒有下一趟、沒快照開旅遊地圖
    var url: URL = WidgetLink.trip(nil)

    /// privacy＝鎖定畫面、StandBy：景點名換 lockedSurfaceTitle（站名；過夜那一站「住宿」）
    static func make(snapshot: WidgetLifeSnapshot?, now: Date, privacy: Bool) -> TravelWidgetModel {
        var model = TravelWidgetModel()
        guard let snap = snapshot, snap.trips != nil else {
            TravelWidgetText.fillMessage(&model)
            return model
        }
        switch snap.tripPhase(at: now) {
        case .noTrip:
            TravelWidgetText.fillNoTrip(&model)
        case .upcoming(let trip, daysUntil: let days):
            TravelWidgetText.fillUpcoming(&model, trip: trip, daysUntil: days)
        case .during(let trip, day: let dayNumber):
            TravelWidgetText.fillDuring(&model, trip: trip, dayNumber: dayNumber,
                                        today: snap.day(at: now), now: now, privacy: privacy)
        }
        return model
    }
}

/// 組字的小函式（只拼行程名、日期、時間、站名、天數，不碰金額）
private enum TravelWidgetText {
    /// 沒快照（舊檔沒有 trips 也算）
    static func fillMessage(_ model: inout TravelWidgetModel) {
        model.kind = .message
        model.message = "打開 LifeGood 一次，這裡就會出現下一趟旅行"
        // 長方形一行約 160pt：整句放不下，拆兩行
        model.rectLine1 = "打開 LifeGood 一次"
        model.rectLine2 = "就會出現下一趟旅行"
    }

    /// 沒有下一趟（都回來了、沒排）
    static func fillNoTrip(_ model: inout TravelWidgetModel) {
        model.kind = .noTrip
        model.message = "還沒有排下一趟旅行"
        model.hint = "在 LifeGood 的旅遊地圖排一趟"
        model.rectLine1 = "還沒有排下一趟旅行"
    }

    /// 出發前：「38 天」（明天出發寫「明天」）、「11/20 (週五) 出發」、「行李 8/15」（沒清單寫「共 7 天」）
    static func fillUpcoming(_ model: inout TravelWidgetModel, trip: WidgetTrip, daysUntil: Int) {
        let date = WidgetDateText.billDate(trip.startDate)
        let total = "共 \(max(trip.dayCount, 1)) 天"
        let packing = packingText(trip)
        let isTomorrow = daysUntil <= 1
        model.kind = .upcoming
        model.tripTitle = trip.title
        model.url = trip.url
        model.hero = isTomorrow ? "明天" : "\(daysUntil)"
        model.heroSuffix = isTomorrow ? "" : "天"
        model.smallLine1 = date + " 出發"
        model.smallLine2 = packing.isEmpty ? total : packing
        model.upcomingLabel = "下一趟旅行"
        model.heroCaption = isTomorrow ? "出發" : "後出發"
        model.dateLine = date + " 出發・" + total
        model.packingLine = packing
        model.rectLine1 = trip.title
        model.rectLine2 = isTomorrow ? "明天出發" : "\(daysUntil) 天後出發"
        model.rectLine3 = date
    }

    /// 旅途中：「第 2 天」「共 7 天」「下一站 天神地下街 16:20」；中型列出今天還沒走完的景點。
    /// today＝snap.day(at: now)；nil＝快照過期（App 兩天沒開）：第幾天照算，下一站不寫
    static func fillDuring(_ model: inout TravelWidgetModel, trip: WidgetTrip, dayNumber: Int,
                           today: WidgetLifeDay?, now: Date, privacy: Bool) {
        let total = max(trip.dayCount, 1)
        model.kind = .during
        model.tripTitle = trip.title
        model.url = trip.url
        model.heroPrefix = "第"
        model.hero = "\(dayNumber)"
        model.heroSuffix = "天"
        model.smallLine1 = "共 \(total) 天"
        model.dayText = "第 \(dayNumber) 天／共 \(total) 天"
        model.rectLine1 = model.dayText
        model.rectLine3 = trip.title
        guard let day = today else {
            model.rows = [messageRow(id: "lg-travel-stale", text: "打開 LifeGood 更新今天的行程")]
            return
        }
        fillStops(&model, day: day, now: now, privacy: privacy)
    }

    /// 下一站那一行（小型、長方形）與中型的列
    static func fillStops(_ model: inout TravelWidgetModel, day: WidgetLifeDay, now: Date, privacy: Bool) {
        let remaining = day.remainingTripStops(at: now)
        let next = day.nextTripStop(at: now)
        if let next {
            let name = stopName(next, privacy: privacy)
            let time = DayTimelineFormat.time(next.stop.start)
            model.smallLine2 = "下一站 " + name + " " + time
            model.rectLine2 = "下一站 " + time + " " + name
        } else if let current = remaining.first {
            // 今天最後一站進行中（後面沒有下一站了）
            model.smallLine2 = "現在 " + stopName(current, privacy: privacy)
            model.rectLine2 = model.smallLine2
        } else {
            model.smallLine2 = "今天的行程走完了"
            model.rectLine2 = "今天的行程走完了"
        }
        model.rows = rows(day: day, remaining: remaining, nextId: next?.id, now: now, privacy: privacy)
    }

    /// 中型的列：今天還沒走完的景點最多 3 列；都走完了寫一句話，隔天有旅遊景點再加「明天 09:00 太宰府」
    static func rows(day: WidgetLifeDay, remaining: [WidgetStop], nextId: String?,
                     now: Date, privacy: Bool) -> [TravelWidgetRow] {
        if !remaining.isEmpty {
            return remaining.prefix(3).map { stopRow($0, nextId: nextId, now: now, privacy: privacy) }
        }
        var out: [TravelWidgetRow] = [messageRow(id: "lg-travel-done", text: "今天的行程走完了")]
        if let first = tomorrowFirstTripStop(day) {
            out.append(TravelWidgetRow(id: "lg-travel-tomorrow-" + first.id,
                                       time: "明天 " + DayTimelineFormat.time(first.stop.start),
                                       title: stopName(first, privacy: privacy),
                                       trailing: "",
                                       isMessage: false))
        }
        return out
    }

    /// 一個景點：「16:20 天神地下街　下一站」；已經開始的寫「進行中」
    static func stopRow(_ item: WidgetStop, nextId: String?, now: Date, privacy: Bool) -> TravelWidgetRow {
        let trailing: String
        if item.stop.start <= now {
            trailing = "進行中"
        } else if item.id == nextId {
            trailing = "下一站"
        } else {
            trailing = ""
        }
        return TravelWidgetRow(id: item.id,
                               time: DayTimelineFormat.time(item.stop.start),
                               title: stopName(item, privacy: privacy),
                               trailing: trailing,
                               isMessage: false)
    }

    static func messageRow(id: String, text: String) -> TravelWidgetRow {
        TravelWidgetRow(id: id, time: "", title: text, trailing: "", isMessage: true)
    }

    /// 隔天第一個旅遊景點：v3 的 nextDayFirstStops 裡挑 kind == .trip；舊檔（nil）看 nextDayFirstStop
    static func tomorrowFirstTripStop(_ day: WidgetLifeDay) -> WidgetStop? {
        if let firsts = day.nextDayFirstStops {
            return firsts.first { $0.stop.kind == .trip }
        }
        guard let first = day.nextDayFirstStop, first.stop.kind == .trip else { return nil }
        return first
    }

    /// 景點名：主畫面寫站名（stop.title）；鎖定畫面、StandBy 寫 lockedSurfaceTitle（旅遊景點＝lockTitle）
    static func stopName(_ item: WidgetStop, privacy: Bool) -> String {
        let raw = privacy ? item.lockedSurfaceTitle : item.stop.title
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "景點" : name
    }

    /// 「行李 8/15」；沒有行李清單（共 0 條）是空字串
    static func packingText(_ trip: WidgetTrip) -> String {
        guard trip.packingTotal > 0 else { return "" }
        return "行李 \(trip.packingDone)/\(trip.packingTotal)"
    }
}

/// 小工具庫預覽與 placeholder 的樣本。**寫死的展示字**（J:331）：
/// 10/13 10:05 看 11/20 (週五) 08:30 出發的「勇闖福岡親子行」：38 天、共 7 天、行李 8/15。
enum TravelWidgetSample {
    /// 固定的假 id（預覽點不到真的行程）
    static let tripId = UUID(uuidString: "6F1C2A10-3B5D-4E2A-9C7E-0A1B2C3D4E5F") ?? UUID()

    static func entry() -> TravelWidgetEntry {
        let now = moment(2026, 10, 13, 10, 5) ?? Date()
        let start = moment(2026, 11, 20, 8, 30) ?? now.addingTimeInterval(38 * 86_400)
        let snapshot = WidgetLifeSnapshot(generatedAt: now,
                                          dataDay: WidgetDateText.dayKey(now),
                                          validUntil: now.addingTimeInterval(2 * 86_400),
                                          days: [],
                                          trips: [sampleTrip(start: start)])
        return TravelWidgetEntry(date: now, snapshot: snapshot)
    }

    private static func sampleTrip(start: Date) -> WidgetTrip {
        let cal = Calendar.current
        let firstDay = cal.startOfDay(for: start)
        let after = cal.date(byAdding: .day, value: 7, to: firstDay) ?? firstDay.addingTimeInterval(7 * 86_400)
        return WidgetTrip(id: tripId,
                          title: "勇闖福岡親子行",
                          startDate: start,
                          endDate: after.addingTimeInterval(-6 * 3600),
                          firstDay: firstDay,
                          dayCount: 7,
                          afterLastDay: after,
                          packingDone: 8,
                          packingTotal: 15,
                          link: WidgetLink.trip(tripId).absoluteString)
    }

    private static func moment(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date? {
        let comps = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return Calendar.current.date(from: comps)
    }
}

// MARK: - 畫面

struct TravelWidgetEntryView: View {
    let entry: TravelWidgetEntry

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

    private var isRect: Bool { family == .accessoryRectangular }

    /// 鎖定畫面、StandBy：景點名換 lockedSurfaceTitle
    private var model: TravelWidgetModel {
        TravelWidgetModel.make(snapshot: entry.snapshot, now: entry.date, privacy: isRect || surface.isStandBy)
    }

    var body: some View {
        let current = model
        let large: TravelLargeModel? = family == .systemLarge
            ? TravelLargeModel.make(snapshot: entry.snapshot, now: entry.date, privacy: largePrivacy) : nil
        TravelWidgetContent(model: current, palette: palette, family: family, large: large)
            .containerBackground(for: .widget) {
                background(for: current)
            }
            .widgetURL(current.url)
    }

    /// [v25.631] 大型：Mac 桌面沒聚焦（vibrant）、StandBy 的景點名換 lockedSurfaceTitle
    private var largePrivacy: Bool { renderingMode == .vibrant || surface.isStandBy }

    /// 主畫面全彩畫天空；著色、StandBy、鎖定畫面透明
    @ViewBuilder
    private func background(for current: TravelWidgetModel) -> some View {
        if surface.drawsSky && !isRect {
            WidgetSky(palette: palette, moon: skyMoon(for: current))
        } else {
            Color.clear
        }
    }

    /// 月牙／雲不壓字（J:56）：
    /// • 小型：第一列是「✈ 行程名」整列，放大字那一列右邊；一句話（置中好幾行）放右上
    /// • 中型：出發前、一句話放左上（左欄「下一趟旅行」與右欄之間的空檔，見 TravelWidgetUpcomingMedium）；
    ///   旅途中整條標題列都是字（行程名＋「第 2 天／共 7 天」），不放
    private func skyMoon(for current: TravelWidgetModel) -> WidgetSkyMoon {
        // [v25.631] 大型整面是字（表頭、天數條、每一站），不放月牙／雲
        if family == .systemLarge { return WidgetSkyMoon.none }
        let isMessage = current.kind == .message || current.kind == .noTrip
        if family != .systemMedium {
            return isMessage ? WidgetSkyMoon.topTrailing : WidgetSkyMoon.middleTrailing
        }
        return current.kind == .during ? WidgetSkyMoon.none : WidgetSkyMoon.topLeading
    }
}

/// 依尺寸、狀態挑版面（ViewBuilder 裡只比對 Bool 與沒有關聯值的列舉，不用 if case）
private struct TravelWidgetContent: View {
    let model: TravelWidgetModel
    let palette: WidgetPalette
    let family: WidgetFamily
    /// [v25.631] 大型才有（EntryView 只在 .systemLarge 時算）
    var large: TravelLargeModel? = nil

    var body: some View {
        if family == .accessoryRectangular {
            TravelWidgetRect(model: model)
        } else if showsMessage {
            TravelWidgetMessage(text: model.message, hint: hint, palette: palette)
        } else if family == .systemLarge {
            TravelLargeView(model: large ?? TravelLargeModel(), palette: palette)
        } else if family != .systemMedium {
            TravelWidgetSmall(model: model, palette: palette)
        } else if model.kind == .during {
            TravelWidgetDuringMedium(model: model, palette: palette)
        } else {
            TravelWidgetUpcomingMedium(model: model, palette: palette)
        }
    }

    private var showsMessage: Bool {
        model.kind == .message || model.kind == .noTrip
    }

    /// 小字只在中型寫（小型放不下）
    /// [v25.631] 大型也寫（「在 LifeGood 的旅遊地圖排一趟」）
    private var hint: String {
        family == .systemSmall ? "" : model.hint
    }
}

/// 「✈ 勇闖福岡親子行」：小飛機（旅遊紫；著色模式染重點色）＋字
private struct TravelWidgetTitleLine: View {
    let text: String
    let palette: WidgetPalette
    let size: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "airplane")
                .font(.system(size: size - 1, weight: .bold))
                .foregroundStyle(palette.dot(.trip))
                .widgetAccentable()
            Text(text)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

/// 大字：「38」＋小字「天」、「明天」、小字「第」＋「2」＋小字「天」（數字染重點色）
private struct TravelWidgetHero: View {
    let model: TravelWidgetModel
    let palette: WidgetPalette
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            TravelWidgetHeroUnit(text: model.heroPrefix, size: unitSize, palette: palette)
            Text(model.hero)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
            TravelWidgetHeroUnit(text: model.heroSuffix, size: unitSize, palette: palette)
        }
    }

    private var unitSize: CGFloat { size * 0.45 }
}

/// 大字前後的小字（「第」「天」）；空字串不畫
private struct TravelWidgetHeroUnit: View {
    let text: String
    let size: CGFloat
    let palette: WidgetPalette

    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// 小字一行（空字串不畫）
private struct TravelWidgetLine: View {
    let text: String
    let size: CGFloat
    let color: Color
    let lines: Int

    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(lines)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: 小型

/// 小型（主畫面、StandBy）：「✈ 行程名」、大字、兩行小字。拿掉天空也成立（J:61）
private struct TravelWidgetSmall: View {
    let model: TravelWidgetModel
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TravelWidgetTitleLine(text: model.tripTitle, palette: palette, size: 13)
            TravelWidgetHero(model: model, palette: palette, size: 36)
                .padding(.top, 2)
            Spacer(minLength: 2)
            VStack(alignment: .leading, spacing: 2) {
                TravelWidgetLine(text: model.smallLine1, size: 12.5, color: palette.inkDate, lines: 1)
                TravelWidgetLine(text: model.smallLine2, size: 12, color: palette.ink, lines: 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: 中型

/// 中型・出發前：左「✈ 下一趟旅行／38 天／後出發」，右「行程名（2 行）／11/20 (週五) 出發・共 7 天／行李 8/15」
private struct TravelWidgetUpcomingMedium: View {
    let model: TravelWidgetModel
    let palette: WidgetPalette

    /// 左欄寬：右欄從整塊的約 150pt 起（內容邊距 16＋118＋16），左上的月牙／雲（x 104–148、y 6–32）
    /// 落在左欄小標的右邊、右欄的左邊，壓不到字
    private static let leftWidth: CGFloat = 118

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            leftColumn
                .frame(width: Self.leftWidth, alignment: .leading)
            rightColumn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            TravelWidgetTitleLine(text: model.upcomingLabel, palette: palette, size: 12.5)
            TravelWidgetHero(model: model, palette: palette, size: 40)
            TravelWidgetLine(text: model.heroCaption, size: 13, color: palette.label, lines: 1)
        }
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.tripTitle)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(palette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            TravelWidgetLine(text: model.dateLine, size: 12, color: palette.inkDate, lines: 2)
            TravelWidgetLine(text: model.packingLine, size: 12, color: palette.label, lines: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 中型・旅途中：「✈ 行程名」＋右上「第 2 天／共 7 天」，下面最多 3 列今天還沒走完的景點。
/// 矮的中型放不下三列時退成兩列（ViewThatFits 由上往下挑）
private struct TravelWidgetDuringMedium: View {
    let model: TravelWidgetModel
    let palette: WidgetPalette

    var body: some View {
        ViewThatFits(in: .vertical) {
            column(rows: model.rows)
            column(rows: Array(model.rows.prefix(2)))
        }
    }

    private func column(rows: [TravelWidgetRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            TravelWidgetRowsList(rows: rows, palette: palette)
                .padding(.top, 10)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            TravelWidgetTitleLine(text: model.tripTitle, palette: palette, size: 15)
            Spacer(minLength: 6)
            Text(model.dayText)
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .fixedSize()
                .widgetAccentable()
        }
    }
}

/// 中型旅途中的幾列（整塊一個網址，列不另設 Link）
private struct TravelWidgetRowsList: View {
    let rows: [TravelWidgetRow]
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(rows, id: \.id) { row in
                TravelWidgetRowView(row: row, palette: palette)
            }
        }
    }
}

/// 一列：小飛機、時間、站名、最右邊「下一站」「進行中」
private struct TravelWidgetRowView: View {
    let row: TravelWidgetRow
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
            trailingText
        }
    }

    private var titleColor: Color {
        row.isMessage ? palette.label : palette.ink
    }

    @ViewBuilder
    private var markView: some View {
        if !row.isMessage {
            WidgetStopMark(kind: .trip, color: palette.dot(.trip), size: 8)
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

    @ViewBuilder
    private var trailingText: some View {
        if !row.trailing.isEmpty {
            Text(row.trailing)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(palette.countdown)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

// MARK: 一句話

/// 沒快照「打開 LifeGood 一次…」、沒有下一趟「還沒有排下一趟旅行」（中型多一行小字）
private struct TravelWidgetMessage: View {
    let text: String
    let hint: String
    let palette: WidgetPalette

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "airplane")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.dot(.trip))
                .widgetAccentable()
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(4)
            hintText
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var hintText: some View {
        if !hint.isEmpty {
            Text(hint)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(palette.label)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }
}

// MARK: 鎖定畫面長方形

/// 三行：粗（✈＋字）、一般、淡。鎖定畫面一律系統單色，不指定顏色（只用 .secondary 分深淺）
private struct TravelWidgetRect: View {
    let model: TravelWidgetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            firstLine
            secondLine
            thirdLine
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var firstLine: some View {
        HStack(spacing: 3) {
            Image(systemName: "airplane")
                .font(.system(size: 13, weight: .semibold))
            Text(model.rectLine1)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.system(size: 15, weight: .bold))
        .widgetAccentable()
    }

    @ViewBuilder
    private var secondLine: some View {
        if !model.rectLine2.isEmpty {
            Text(model.rectLine2)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    @ViewBuilder
    private var thirdLine: some View {
        if !model.rectLine3.isEmpty {
            Text(model.rectLine3)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

// MARK: - 大型（v25.631 large1）
//
// 規格：scratchpad/radar/build/large1/brief.md 的 G3；示意圖 scratchpad/largewidgets/travel.html（旅途中）。
// 旅途中：「✈ 福岡｜第 2 天／共 5 天」→ 天數條（7 天以內一天一個膠囊，超過改進度條＋頭尾日期）→「今天」
// 最多 5 站（還沒走完的旅遊景點；進行中那站框起來、下一站標出來；過夜那一站寫「住宿」，不寫飯店名）
// →「明天第一站 10:00 柳川遊船」→ 最下面「行李 15／15」＋進度條（全勾打勾）。
// 出發前：「✈ 下一趟旅行」→ 行程名 → 大字「12」＋「天後出發」（明天出發「明天」＋「出發」）→
//「11/19 (週四) 出發・共 5 天」→ 行李 →「之後的旅行」最多 2 趟（「1/18 沖繩・3 天」）。
// 沒有旅行、沒快照：TravelWidgetContent 先走 TravelWidgetMessage（大型也寫小字）。
// 放不下只砍列數不縮字：每一塊用 TravelLargeLayout 的常數固定高度，候選由 TravelLargeLayout 算好放在 model，
// View 只用 ViewThatFits(in: .vertical) 由上往下挑（旅途中、出發前各一個，不巢狀）。
// 隱私：vibrant（Mac 桌面沒聚焦）、StandBy 寫 lockedSurfaceTitle；部屬會議不是旅遊景點，本來就不列。
// 字全部在 TravelLargeModel.make 組好（照 sim_large1.py 的 travel_large_make／large_stop_name），body 只讀。

/// 天數條一格：過去、今天、之後
private enum TravelLargeDayState {
    case past
    case today
    case future
}

/// 天數條的一格（7 天以內）：「11/19」
private struct TravelLargeDayCap: Identifiable {
    /// 第幾天（0 起算）
    let id: Int
    let label: String
    let state: TravelLargeDayState
}

/// 今天的一站：「09:30 太宰府天滿宮　進行中」
private struct TravelLargeStop: Identifiable {
    let id: String
    /// 「09:30」
    let time: String
    let title: String
    /// 「進行中」「下一站」或空字串
    let trailing: String
    /// 進行中那一站畫外框
    let isCurrent: Bool
    /// 點了開今天的行程那一站
    let url: URL
}

/// 「之後的旅行」一列：「1/18 沖繩・3 天」
private struct TravelLargeLaterTrip: Identifiable {
    let id: UUID
    let text: String
    let url: URL
}

/// 大型組字的小函式（只拼行程名、日期、時間、站名、天數，不碰金額）
private enum TravelLargeText {
    /// App 寫給過夜那一站的 lockTitle（LifeGood/Models/TodayAgenda.swift：slot.stop.isOvernight ? "住宿" : …）。
    /// App 改這個字要一起改這裡
    static let overnightTitle = "住宿"

    /// 站名：vibrant、StandBy 寫 lockedSurfaceTitle；主畫面過夜那一站也寫「住宿」（不寫飯店名）；其他寫站名
    static func stopName(_ item: WidgetStop, privacy: Bool) -> String {
        let raw: String
        if privacy {
            raw = item.lockedSurfaceTitle
        } else if item.lockTitle == TravelLargeText.overnightTitle {
            raw = TravelLargeText.overnightTitle
        } else {
            raw = item.stop.title
        }
        let name: String = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "景點" : name
    }

    /// 「行李 15／15」（全形斜線）；沒有行李清單（共 0 條）是空字串
    static func packingText(_ trip: WidgetTrip) -> String {
        guard trip.packingTotal > 0 else { return "" }
        return "行李 \(trip.packingDone)／\(trip.packingTotal)"
    }

    /// 行李打勾的比例（0…1）；沒有清單是 0
    static func packingFraction(_ trip: WidgetTrip) -> Double {
        guard trip.packingTotal > 0 else { return 0 }
        let done: Double = Double(trip.packingDone)
        let total: Double = Double(trip.packingTotal)
        return min(1, max(0, done / total))
    }

    /// 第 index 格（0 起算）跟今天（第 dayNumber 天，1 起算）比
    static func dayState(index: Int, dayNumber: Int) -> TravelLargeDayState {
        if index + 1 < dayNumber { return .past }
        if index + 1 == dayNumber { return .today }
        return .future
    }

    /// 今天的一站；已經開始的寫「進行中」，還沒開始的第一站寫「下一站」
    static func makeStop(_ item: WidgetStop, nextId: String?, now: Date, privacy: Bool) -> TravelLargeStop {
        let isCurrent: Bool = item.stop.start <= now
        let trailing: String
        if isCurrent {
            trailing = "進行中"
        } else if item.id == nextId {
            trailing = "下一站"
        } else {
            trailing = ""
        }
        return TravelLargeStop(id: item.id,
                               time: DayTimelineFormat.time(item.stop.start),
                               title: stopName(item, privacy: privacy),
                               trailing: trailing,
                               isCurrent: isCurrent,
                               url: WidgetLink.today(item.stop))
    }

    /// 「1/18 沖繩・3 天」
    static func laterTrip(_ trip: WidgetTrip) -> TravelLargeLaterTrip {
        let days: Int = max(trip.dayCount, 1)
        let date: String = WidgetDateText.shortDate(trip.startDate)
        let text: String = date + " " + trip.title + "・\(days) 天"
        return TravelLargeLaterTrip(id: trip.id, text: text, url: trip.url)
    }
}

/// 大型要的字（每個欄位都有預設值：TravelLargeModel() 是一句話狀態）
private struct TravelLargeModel {
    /// message／noTrip 由 TravelWidgetContent 先畫 TravelWidgetMessage；這裡只是保底
    var kind: TravelWidgetModel.Kind = .message
    var message = ""
    var hint = ""
    /// 行程名「福岡」
    var tripTitle = ""

    // 旅途中
    /// 右上「第 2 天／共 5 天」
    var dayText = ""
    /// 7 天以內一天一格；超過是空陣列（改畫進度條）
    var dayCaps: [TravelLargeDayCap] = []
    /// 超過 7 天：第幾天／共幾天
    var dayFraction: Double = 0
    /// 超過 7 天：進度條下面頭尾的日期「11/19」「11/30」
    var dayStartLabel = ""
    var dayEndLabel = ""
    /// 今天還沒走完的旅遊景點（最多 maxStops 站）
    var stops: [TravelLargeStop] = []
    /// 沒有站時那一列：「今天的行程走完了」「打開 LifeGood 更新今天的行程」
    var stopsMessage = ""
    /// 「明天第一站 10:00 柳川遊船」；沒有是空字串
    var tomorrowTime = ""
    var tomorrowTitle = ""
    /// 「行李 15／15」；沒有行李清單是空字串（整行不畫）
    var packingText = ""
    var packingFraction: Double = 0
    var packingDone = false
    var duringCandidates: [TravelLargeLayout.DuringPlan] = []

    // 出發前
    /// 「下一趟旅行」
    var upcomingLabel = ""
    /// 大字「12」「明天」
    var hero = ""
    /// 「天後出發」「出發」
    var heroCaption = ""
    /// 「11/19 (週四) 出發・共 5 天」
    var dateLine = ""
    /// 之後的旅行（最多 maxLaterTrips 趟）
    var laterTrips: [TravelLargeLaterTrip] = []
    /// ViewThatFits 4 個候選：「之後的旅行」放幾列
    var upcomingCandidates: [Int] = []

    /// 旅途中第 index 個候選；超出範圍回最後一個，空的回 0 列不帶明天
    func duringCandidate(at index: Int) -> TravelLargeLayout.DuringPlan {
        guard let last = duringCandidates.last else {
            return TravelLargeLayout.DuringPlan(rows: 0, showsTomorrow: false)
        }
        guard index >= 0, index < duringCandidates.count else { return last }
        return duringCandidates[index]
    }

    /// 出發前第 index 個候選；超出範圍回最後一個，空的回 0 列
    func upcomingCandidate(at index: Int) -> Int {
        guard let last = upcomingCandidates.last else { return 0 }
        guard index >= 0, index < upcomingCandidates.count else { return last }
        return upcomingCandidates[index]
    }

    /// 這個候選畫哪幾站（前 plan.rows 站）
    func stops(for plan: TravelLargeLayout.DuringPlan) -> [TravelLargeStop] {
        Array(stops.prefix(max(0, plan.rows)))
    }

    /// 這個候選畫哪幾趟之後的旅行（前 rows 趟）
    func laterTrips(rows: Int) -> [TravelLargeLaterTrip] {
        Array(laterTrips.prefix(max(0, rows)))
    }

    /// privacy＝vibrant、StandBy：景點名換 lockedSurfaceTitle
    static func make(snapshot: WidgetLifeSnapshot?, now: Date, privacy: Bool) -> TravelLargeModel {
        var model = TravelLargeModel()
        guard let snap = snapshot, snap.trips != nil else {
            model.message = "打開 LifeGood 一次，這裡就會出現下一趟旅行"
            return model
        }
        switch snap.tripPhase(at: now) {
        case .noTrip:
            model.kind = .noTrip
            model.message = "還沒有排下一趟旅行"
            model.hint = "在 LifeGood 的旅遊地圖排一趟"
        case .upcoming(let trip, daysUntil: let days):
            model.fillTrip(trip)
            model.fillUpcoming(trip: trip, daysUntil: days, snapshot: snap, now: now)
        case .during(let trip, day: let dayNumber):
            model.fillTrip(trip)
            model.fillDuring(trip: trip, dayNumber: dayNumber, today: snap.day(at: now), now: now, privacy: privacy)
        }
        return model
    }

    /// 出發前、旅途中都有的：行程名、行李
    private mutating func fillTrip(_ trip: WidgetTrip) {
        tripTitle = trip.title
        packingText = TravelLargeText.packingText(trip)
        packingFraction = TravelLargeText.packingFraction(trip)
        packingDone = trip.packingTotal > 0 && trip.packingDone >= trip.packingTotal
    }

    /// 出發前：「12 天後出發」（明天出發「明天／出發」）、日期、之後的旅行（不是這一趟、還沒回來的前 2 趟）
    private mutating func fillUpcoming(trip: WidgetTrip, daysUntil: Int, snapshot: WidgetLifeSnapshot, now: Date) {
        let total: Int = max(trip.dayCount, 1)
        let isTomorrow: Bool = daysUntil <= 1
        kind = .upcoming
        upcomingLabel = "下一趟旅行"
        hero = isTomorrow ? "明天" : "\(daysUntil)"
        heroCaption = isTomorrow ? "出發" : "天後出發"
        dateLine = WidgetDateText.billDate(trip.startDate) + " 出發・共 \(total) 天"
        let all: [WidgetTrip] = snapshot.trips ?? []
        let others: [WidgetTrip] = all.filter { $0.afterLastDay > now && $0.id != trip.id }
        laterTrips = others.prefix(TravelLargeLayout.maxLaterTrips).map { (t: WidgetTrip) -> TravelLargeLaterTrip in
            TravelLargeText.laterTrip(t)
        }
        upcomingCandidates = TravelLargeLayout.upcomingCandidates(laterCount: laterTrips.count,
                                                                  hasPacking: !packingText.isEmpty)
    }

    /// 旅途中：第幾天、天數條、今天每一站、明天第一站。today＝snap.day(at: now)；nil＝快照過期：第幾天照算，站不寫
    private mutating func fillDuring(trip: WidgetTrip, dayNumber: Int, today: WidgetLifeDay?,
                                     now: Date, privacy: Bool) {
        let total: Int = max(trip.dayCount, 1)
        kind = .during
        dayText = "第 \(dayNumber) 天／共 \(total) 天"
        fillDays(trip: trip, dayNumber: dayNumber, total: total)
        var hasTomorrow = false
        if let day = today {
            fillStops(day: day, now: now, privacy: privacy)
            if let first = TravelWidgetText.tomorrowFirstTripStop(day) {
                hasTomorrow = true
                tomorrowTime = DayTimelineFormat.time(first.stop.start)
                tomorrowTitle = TravelLargeText.stopName(first, privacy: privacy)
            }
        } else {
            stopsMessage = "打開 LifeGood 更新今天的行程"
        }
        duringCandidates = TravelLargeLayout.duringCandidates(stopCount: stops.count, hasTomorrow: hasTomorrow,
                                                              hasPacking: !packingText.isEmpty)
    }

    /// 天數條：7 天以內一天一格（出發那天起每天 00:00 的日期），超過改進度條＋頭尾日期
    private mutating func fillDays(trip: WidgetTrip, dayNumber: Int, total: Int) {
        let cal = Calendar.current
        if total <= TravelLargeLayout.maxDayCapsules {
            var caps: [TravelLargeDayCap] = []
            for i in 0..<total {
                let date: Date = cal.date(byAdding: .day, value: i, to: trip.firstDay) ?? trip.firstDay
                let state: TravelLargeDayState = TravelLargeText.dayState(index: i, dayNumber: dayNumber)
                caps.append(TravelLargeDayCap(id: i, label: WidgetDateText.shortDate(date), state: state))
            }
            dayCaps = caps
            return
        }
        dayFraction = Double(dayNumber) / Double(total)
        dayStartLabel = WidgetDateText.shortDate(trip.firstDay)
        let last: Date = cal.date(byAdding: .day, value: total - 1, to: trip.firstDay) ?? trip.firstDay
        dayEndLabel = WidgetDateText.shortDate(last)
    }

    /// 今天還沒走完的旅遊景點前 maxStops 站（部屬會議等其他種類不列）；一站都沒有寫「今天的行程走完了」
    private mutating func fillStops(day: WidgetLifeDay, now: Date, privacy: Bool) {
        let remaining: [WidgetStop] = day.remainingTripStops(at: now)
        let nextId: String? = day.nextTripStop(at: now)?.id
        stops = remaining.prefix(TravelLargeLayout.maxStops).map { (item: WidgetStop) -> TravelLargeStop in
            TravelLargeText.makeStop(item, nextId: nextId, now: now, privacy: privacy)
        }
        if remaining.isEmpty {
            stopsMessage = "今天的行程走完了"
        }
    }
}

// MARK: 大型的畫面

/// 旅途中、出發前各一種版面（message／noTrip 通常在 TravelWidgetContent 就先畫掉了，這裡保底）
private struct TravelLargeView: View {
    let model: TravelLargeModel
    let palette: WidgetPalette

    var body: some View {
        if model.kind == .during {
            TravelLargeDuring(model: model, palette: palette)
        } else if model.kind == .upcoming {
            TravelLargeUpcoming(model: model, palette: palette)
        } else {
            TravelWidgetMessage(text: model.message, hint: model.hint, palette: palette)
        }
    }
}

/// 旅途中：4 個候選（站數、要不要明天第一站）由上往下挑第一個放得下的
private struct TravelLargeDuring: View {
    let model: TravelLargeModel
    let palette: WidgetPalette

    var body: some View {
        ViewThatFits(in: .vertical) {
            TravelLargeDuringColumn(model: model, plan: model.duringCandidate(at: 0), palette: palette)
            TravelLargeDuringColumn(model: model, plan: model.duringCandidate(at: 1), palette: palette)
            TravelLargeDuringColumn(model: model, plan: model.duringCandidate(at: 2), palette: palette)
            TravelLargeDuringColumn(model: model, plan: model.duringCandidate(at: 3), palette: palette)
        }
    }
}

/// 旅途中一欄：表頭 → 天數條 →「今天」→ 每一站 →（明天第一站）→ 行李。每一塊固定高度（TravelLargeLayout）
private struct TravelLargeDuringColumn: View {
    let model: TravelLargeModel
    let plan: TravelLargeLayout.DuringPlan
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LargeWidgetTitleLine(icon: "airplane", iconColor: palette.dot(.trip), title: model.tripTitle,
                                 trailing: model.dayText, trailingColor: palette.ink, palette: palette,
                                 height: TravelLargeLayout.headerHeight)
            TravelLargeDayStrip(model: model, palette: palette)
            LargeWidgetSectionLabel(title: "今天", height: TravelLargeLayout.sectionHeaderHeight,
                                    palette: palette, bottomGap: 4)
            stopList
            tomorrowLine
            Spacer(minLength: 0)
            packingLine
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 每一站（各自一個 Link）；沒有站時一列一句話
    @ViewBuilder
    private var stopList: some View {
        if model.stops.isEmpty {
            messageRow
        } else {
            VStack(alignment: .leading, spacing: TravelLargeLayout.rowSpacing) {
                ForEach(model.stops(for: plan)) { stop in
                    Link(destination: stop.url) {
                        TravelLargeStopRow(stop: stop, palette: palette)
                    }
                }
            }
        }
    }

    private var messageRow: some View {
        Text(model.stopsMessage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.label)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: TravelLargeLayout.rowHeight,
                   maxHeight: TravelLargeLayout.rowHeight, alignment: .leading)
            .background { LargeWidgetCardBackground(palette: palette, cornerRadius: 10) }
    }

    @ViewBuilder
    private var tomorrowLine: some View {
        if plan.showsTomorrow {
            TravelLargeTomorrow(time: model.tomorrowTime, title: model.tomorrowTitle, palette: palette)
        }
    }

    @ViewBuilder
    private var packingLine: some View {
        if !model.packingText.isEmpty {
            TravelLargePacking(text: model.packingText, fraction: model.packingFraction, done: model.packingDone,
                               palette: palette, height: TravelLargeLayout.packingHeight, topGap: 8)
        }
    }
}

/// 天數條：7 天以內一天一個膠囊（過去實心、今天粗框半透明、之後細框），超過改進度條＋頭尾日期
private struct TravelLargeDayStrip: View {
    let model: TravelLargeModel
    let palette: WidgetPalette

    var body: some View {
        strip
            .frame(maxWidth: .infinity, minHeight: TravelLargeLayout.dayStripHeight,
                   maxHeight: TravelLargeLayout.dayStripHeight, alignment: .bottom)
    }

    @ViewBuilder
    private var strip: some View {
        if model.dayCaps.isEmpty {
            TravelLargeDayBar(fraction: model.dayFraction, startLabel: model.dayStartLabel,
                              endLabel: model.dayEndLabel, palette: palette)
        } else {
            HStack(spacing: 5) {
                ForEach(model.dayCaps) { cap in
                    TravelLargeDayCapView(cap: cap, palette: palette)
                }
            }
        }
    }
}

/// 一天一個膠囊＋日期（今天的日期粗、深色）
private struct TravelLargeDayCapView: View {
    let cap: TravelLargeDayCap
    let palette: WidgetPalette

    private var isToday: Bool { cap.state == .today }

    private var labelWeight: Font.Weight { isToday ? .bold : .semibold }

    private var labelColor: Color { isToday ? palette.ink : palette.label }

    private var trip: Color { palette.dot(.trip) }

    var body: some View {
        VStack(spacing: 4) {
            capsule
                .frame(height: TravelLargeLayout.dayCapsuleHeight)
            Text(cap.label)
                .font(.system(size: 9.5, weight: labelWeight))
                .monospacedDigit()
                .foregroundStyle(labelColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var capsule: some View {
        if cap.state == .past {
            Capsule()
                .fill(trip)
                .widgetAccentable()
        } else if cap.state == .today {
            ZStack {
                Capsule().fill(trip.opacity(0.35))
                Capsule().strokeBorder(trip, lineWidth: 2.5)
            }
        } else {
            Capsule()
                .strokeBorder(trip.opacity(0.55), lineWidth: 1.5)
        }
    }
}

/// 超過 7 天的天數條：進度條＋頭尾日期
private struct TravelLargeDayBar: View {
    let fraction: Double
    let startLabel: String
    let endLabel: String
    let palette: WidgetPalette

    var body: some View {
        VStack(spacing: 4) {
            LargeWidgetBar(fraction: fraction, fill: palette.dot(.trip), track: palette.barTrack,
                           height: TravelLargeLayout.dayCapsuleHeight)
            HStack(spacing: 4) {
                dateText(startLabel)
                Spacer(minLength: 4)
                dateText(endLabel)
            }
        }
    }

    private func dateText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(palette.label)
            .lineLimit(1)
    }
}

/// 一站：小飛機、時間、站名、最右邊「進行中／下一站」；進行中那站紫框
private struct TravelLargeStopRow: View {
    let stop: TravelLargeStop
    let palette: WidgetPalette

    private var highlight: Color? {
        stop.isCurrent ? palette.dot(.trip).opacity(0.7) : nil
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "airplane")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.dot(.trip))
                .widgetAccentable()
            timeText
            Text(stop.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            trailingText
        }
        .padding(.horizontal, 10)
        .frame(height: TravelLargeLayout.rowHeight)
        .background { LargeWidgetCardBackground(palette: palette, cornerRadius: 10, highlight: highlight) }
    }

    private var timeText: some View {
        Text(stop.time)
            .font(.system(size: 14, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(palette.ink)
            .lineLimit(1)
            .fixedSize()
    }

    @ViewBuilder
    private var trailingText: some View {
        if !stop.trailing.isEmpty {
            Text(stop.trailing)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(palette.countdown)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// 「🌅 明天第一站 10:00 柳川遊船」：固定高度，字貼底
private struct TravelLargeTomorrow: View {
    let time: String
    let title: String
    let palette: WidgetPalette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "sunrise")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.label)
            Text("明天第一站")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(palette.inkSoft)
                .lineLimit(1)
                .fixedSize()
            timeText
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: TravelLargeLayout.tomorrowHeight,
               maxHeight: TravelLargeLayout.tomorrowHeight, alignment: .bottomLeading)
    }

    private var timeText: some View {
        Text(time)
            .font(.system(size: 12.5, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(palette.ink)
            .lineLimit(1)
            .fixedSize()
    }
}

/// 「🧳 行李 15／15 ▓▓▓ ✓」：固定高度 height（含上面空 topGap），字貼底；全勾打勾
private struct TravelLargePacking: View {
    let text: String
    let fraction: Double
    let done: Bool
    let palette: WidgetPalette
    let height: CGFloat
    let topGap: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "suitcase")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.label)
            label
            LargeWidgetBar(fraction: fraction, fill: palette.good, track: palette.barTrack)
            doneMark
        }
        .padding(.top, topGap)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .bottomLeading)
    }

    private var label: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(palette.ink)
            .lineLimit(1)
            .fixedSize()
    }

    @ViewBuilder
    private var doneMark: some View {
        if done {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.good)
                .widgetAccentable()
        }
    }
}

/// 出發前：4 個候選（「之後的旅行」放幾列）由上往下挑第一個放得下的
private struct TravelLargeUpcoming: View {
    let model: TravelLargeModel
    let palette: WidgetPalette

    var body: some View {
        ViewThatFits(in: .vertical) {
            TravelLargeUpcomingColumn(model: model, laterRows: model.upcomingCandidate(at: 0), palette: palette)
            TravelLargeUpcomingColumn(model: model, laterRows: model.upcomingCandidate(at: 1), palette: palette)
            TravelLargeUpcomingColumn(model: model, laterRows: model.upcomingCandidate(at: 2), palette: palette)
            TravelLargeUpcomingColumn(model: model, laterRows: model.upcomingCandidate(at: 3), palette: palette)
        }
    }
}

/// 出發前一欄：「✈ 下一趟旅行」→ 行程名 → 大字 → 日期 → 行李 →（之後的旅行）。每一塊固定高度（TravelLargeLayout）
private struct TravelLargeUpcomingColumn: View {
    let model: TravelLargeModel
    let laterRows: Int
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LargeWidgetTitleLine(icon: "airplane", iconColor: palette.dot(.trip), title: model.upcomingLabel,
                                 trailing: "", trailingColor: palette.ink, palette: palette,
                                 titleSize: 12.5, height: TravelLargeLayout.upLabelHeight)
            titleText
            heroLine
            dateText
            packingLine
            Spacer(minLength: 0)
            laterSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var titleText: some View {
        Text(model.tripTitle)
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(palette.ink)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: TravelLargeLayout.upTitleHeight,
                   maxHeight: TravelLargeLayout.upTitleHeight, alignment: .leading)
    }

    /// 大字「12」＋「天後出發」（明天出發「明天」＋「出發」）
    private var heroLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(model.hero)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .widgetAccentable()
            Text(model.heroCaption)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, minHeight: TravelLargeLayout.upHeroHeight,
               maxHeight: TravelLargeLayout.upHeroHeight, alignment: .bottomLeading)
    }

    private var dateText: some View {
        Text(model.dateLine)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.inkDate)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: TravelLargeLayout.upDateHeight,
                   maxHeight: TravelLargeLayout.upDateHeight, alignment: .leading)
    }

    @ViewBuilder
    private var packingLine: some View {
        if !model.packingText.isEmpty {
            TravelLargePacking(text: model.packingText, fraction: model.packingFraction, done: model.packingDone,
                               palette: palette, height: TravelLargeLayout.upPackingHeight, topGap: 12)
        }
    }

    /// 「之後的旅行」區標＋每一趟（各自一個 Link）；這個候選 0 列就整塊不畫
    @ViewBuilder
    private var laterSection: some View {
        if laterRows > 0 {
            VStack(alignment: .leading, spacing: 0) {
                LargeWidgetSectionLabel(title: "之後的旅行", height: TravelLargeLayout.laterHeaderHeight,
                                        palette: palette, bottomGap: 4)
                VStack(alignment: .leading, spacing: TravelLargeLayout.laterRowSpacing) {
                    ForEach(model.laterTrips(rows: laterRows)) { trip in
                        Link(destination: trip.url) {
                            TravelLargeLaterRow(trip: trip, palette: palette)
                        }
                    }
                }
            }
        }
    }
}

/// 「✈ 1/18 沖繩・3 天 ›」
private struct TravelLargeLaterRow: View {
    let trip: TravelLargeLaterTrip
    let palette: WidgetPalette

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "airplane")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.dot(.trip))
                .widgetAccentable()
            Text(trip.text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.label)
        }
        .padding(.horizontal, 10)
        .frame(height: TravelLargeLayout.laterRowHeight)
        .background { LargeWidgetCardBackground(palette: palette, cornerRadius: 9) }
    }
}
