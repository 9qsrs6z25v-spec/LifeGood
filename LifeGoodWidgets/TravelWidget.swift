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
        .description("下一趟還有幾天、旅途中第幾天、下一站")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
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
        TravelWidgetContent(model: current, palette: palette, family: family)
            .containerBackground(for: .widget) {
                background(for: current)
            }
            .widgetURL(current.url)
    }

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

    var body: some View {
        if family == .accessoryRectangular {
            TravelWidgetRect(model: model)
        } else if showsMessage {
            TravelWidgetMessage(text: model.message, hint: hint, palette: palette)
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
    private var hint: String {
        family == .systemMedium ? model.hint : ""
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
