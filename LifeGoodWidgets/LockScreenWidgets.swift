import SwiftUI
import WidgetKit
import AppIntents

// MARK: - 鎖定畫面：已花（圓形＋一行字）、下一場（長方形＋一行字）、下一筆要繳（長方形）（小工具 v2）
//
// 只屬於「LifeGoodWidgets」target。規格見 scratchpad/widgets/v2/brief.md 的 G3-6；
// 樣稿 mock_spec lock-spent-circular、lock-next-event-rect、lock-next-bill-rect、lock-money-inline、
// lock-today-inline（J:285-298）。
//
// 共通：
// • 鎖定畫面一律系統單色，不指定顏色（只用 .secondary 分深淺）；.containerBackground 用 Color.clear，
//   圓形自己墊 AccessoryWidgetBackground()。
// • 使用者決定 2：要放金額、項目名稱與會議主題也可以放（「10/15 Netflix NT$390」「10:30 CDA 異常檢討」），
//   所以**不加** .privacySensitive()。**人名一律不寫**：部屬姓名（stop.owner）不碰，
//   行程標題用 WidgetStop.lockedSurfaceTitle、生日只寫 lockTitle（「家人生日」）。
// • 「已花」三種字（WidgetMoneyLock）App 寫好、不含金額，隱藏金額開關不影響；
//   「下一筆要繳」的金額跟著隱藏開關換成 mask。
//
// [v3] 長按可設定（AppIntentConfiguration，kind 不變；設定在 WidgetConfigs.swift）：
// • 下一場（LockNextStopConfigIntent）「顯示主題」：開（預設＝v2，lockedSurfaceTitle）；關＝類別字
//  （WidgetStop.lockTitle：「部屬會議」「會議」「系統行事曆」；旅遊景點兩種都是站名，景點算低隱私 J:298）。
// • 下一筆要繳（LockNextBillConfigIntent）「顯示名稱」：開（預設＝v2，「10/15 Netflix」）；
//   關＝類別字（WidgetBill.lockedTitle：「10/15 訂閱服務」）。金額照「隱藏金額」總開關，不另設。
// • 已花沒有設定，照舊 StaticConfiguration。
//
// [財富 v4] v25.565（wealth/judge.md §7.1；build/v4/brief.md G2-12）：「下一筆要繳」碰到卡費、交割
// （WidgetBillKind.isWealth）——不管「顯示名稱」開不開，一律只寫類別字（WidgetBill.lockedTitle「卡費」「交割」）、
// 不寫金額（連 mask 也不放）：「10/27 卡費」／「8 天後・之後還有 4 件」。卡名、金額、號碼都不上鎖定畫面。
//
// 型別（internal 的帶 LockSpent／LockNextStop／LockNextBill 前綴；畫面零件 private）：
//   LockSpentWidget、LockSpentEntry、LockSpentProvider、LockSpentEntryView
//   LockNextStopWidget、LockNextStopEntry、LockNextStopProvider、LockNextStopEntryView
//   LockNextBillWidget、LockNextBillEntry、LockNextBillProvider、LockNextBillEntryView

// MARK: - 已花（accessoryCircular、accessoryInline）

struct LockSpentWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.lockSpent, provider: LockSpentProvider()) { entry in
            LockSpentEntryView(entry: entry)
        }
        .configurationDisplayName("已花")
        .description("這個月已經花了幾成")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

struct LockSpentEntry: TimelineEntry {
    let date: Date
    /// nil＝還沒打開過新版 App
    let snapshot: WidgetMoneySnapshot?
}

struct LockSpentProvider: TimelineProvider {
    func placeholder(in context: Context) -> LockSpentEntry {
        let now = Date()
        return LockSpentEntry(date: now, snapshot: LedgerDeskSample.snapshot(at: now))
    }

    func getSnapshot(in context: Context, completion: @escaping (LockSpentEntry) -> Void) {
        let now = Date()
        if context.isPreview {
            completion(LockSpentEntry(date: now, snapshot: LedgerDeskSample.snapshot(at: now)))
            return
        }
        completion(LockSpentEntry(date: now, snapshot: WidgetSnapshotStore.read(WidgetMoneySnapshot.self)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LockSpentEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshotStore.read(WidgetMoneySnapshot.self)
        let dates = MoneyLeftTimeline.entryDates(snapshot: snapshot, now: now)
        let entries: [LockSpentEntry] = dates.map { LockSpentEntry(date: $0, snapshot: snapshot) }
        let policy = MoneyLeftTimeline.policy(snapshot: snapshot, dates: dates, now: now)
        completion(Timeline(entries: entries, policy: policy))
    }
}

/// 圓形與一行字要的字（全部是 App 寫在 WidgetMoneyDay.lock 裡的）
private struct LockSpentModel {
    enum Ring {
        /// 沒快照、v1 舊檔、跨月：只放 creditcard 圖示
        case iconOnly
        /// 有收入基準：進度環＋「62%」／「超支」＋「已花」
        case progress
        /// 沒有收入紀錄：購物車圖示＋「3 筆」＋「今天」，不畫進度
        case noIncome
    }

    var ring: Ring = .iconOnly
    var ringValue: Double = 0
    var ringText = ""
    var ringCaption = ""
    var inlineText = ""

    static func make(snapshot: WidgetMoneySnapshot?, now: Date) -> LockSpentModel {
        var model = LockSpentModel()
        guard let snap = snapshot else {
            model.inlineText = "打開 LifeGood 看本月已花"
            return model
        }
        if snap.hasEnded(at: now) {
            model.inlineText = WidgetDateText.monthStarted(now)
            return model
        }
        guard let day = snap.day(at: now), let lock = day.lock else {
            model.inlineText = "打開 LifeGood 看本月已花"
            return model
        }
        model.ring = day.state == .noIncome ? Ring.noIncome : Ring.progress
        model.ringValue = clamp(lock.ringValue)
        model.ringText = lock.ringText
        model.ringCaption = lock.ringCaption
        model.inlineText = lock.inlineText
        return model
    }

    /// App 已經夾好 0…1；這裡只防 NaN（環的長度，不是金額）
    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

struct LockSpentEntryView: View {
    let entry: LockSpentEntry

    @Environment(\.widgetFamily) private var family

    private var model: LockSpentModel {
        LockSpentModel.make(snapshot: entry.snapshot, now: entry.date)
    }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                Color.clear
            }
            .widgetURL(WidgetLink.expenseOverview)
    }

    @ViewBuilder
    private var content: some View {
        if family == .accessoryInline {
            Label(model.inlineText, systemImage: "creditcard")
        } else {
            LockSpentCircular(model: model)
        }
    }
}

/// 圓形：系統半透明圓底＋自己畫的環（不用 Gauge）＋中間的字
private struct LockSpentCircular: View {
    let model: LockSpentModel

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            ringLayer
            center
        }
    }

    @ViewBuilder
    private var ringLayer: some View {
        if model.ring == .progress {
            LockSpentRing(value: model.ringValue)
        }
    }

    @ViewBuilder
    private var center: some View {
        switch model.ring {
        case .iconOnly:
            Image(systemName: "creditcard")
                .font(.system(size: 20, weight: .semibold))
        case .progress:
            LockSpentRingLabel(text: model.ringText, caption: model.ringCaption, icon: "")
        case .noIncome:
            LockSpentRingLabel(text: model.ringText, caption: model.ringCaption, icon: "cart")
        }
    }
}

/// 底環（淡）＋進度（圓頭線，從 12 點鐘方向順時針）
private struct LockSpentRing: View {
    let value: Double

    private let lineWidth: CGFloat = 4

    private var progress: CGFloat { CGFloat(value) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: lineWidth)
                .opacity(0.3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
        .padding(lineWidth / 2 + 1)
    }
}

/// 中間：（購物車）「62%」「已花」
private struct LockSpentRingLabel: View {
    let text: String
    let caption: String
    /// 空字串＝不放圖示
    let icon: String

    var body: some View {
        VStack(spacing: 0) {
            iconView
            Text(text)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
    }

    @ViewBuilder
    private var iconView: some View {
        if !icon.isEmpty {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
        }
    }
}

// MARK: - 下一場（accessoryRectangular、accessoryInline）

struct LockNextStopWidget: Widget {
    var body: some WidgetConfiguration {
        // [v3] StaticConfiguration → AppIntentConfiguration（kind 不變：已經放好的升級後用預設值、外觀一樣）
        AppIntentConfiguration(kind: WidgetKind.lockNextStop, intent: LockNextStopConfigIntent.self,
                               provider: LockNextStopProvider()) { entry in
            LockNextStopEntryView(entry: entry)
        }
        .configurationDisplayName("下一場")
        .description("下一場幾點、今天還有幾場")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

struct LockNextStopEntry: TimelineEntry {
    let date: Date
    /// nil＝還沒打開過新版 App
    let snapshot: WidgetLifeSnapshot?
    /// [v3] 長按設定「顯示主題」（預設 true＝v2）；false 寫類別字。placeholder／預覽是 true
    var showsTitle: Bool = true
}

/// [v3] TimelineProvider → AppIntentTimelineProvider（多讀長按設定；排程照舊）
struct LockNextStopProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LockNextStopEntry {
        let sample = TodayWidgetSample.entry(now: Date())
        return LockNextStopEntry(date: sample.date, snapshot: sample.snapshot, showsTitle: true)
    }

    func snapshot(for configuration: LockNextStopConfigIntent, in context: Context) async -> LockNextStopEntry {
        if context.isPreview {
            let sample = TodayWidgetSample.entry(now: Date())
            return LockNextStopEntry(date: sample.date, snapshot: sample.snapshot, showsTitle: true)
        }
        let snapshot = WidgetSnapshotStore.read(WidgetLifeSnapshot.self)
        return LockNextStopEntry(date: Date(), snapshot: snapshot, showsTitle: configuration.showTitle)
    }

    /// 跟「今天」同一份排程（有倒數的那幾分鐘每分鐘一筆，TodayWidgetTimeline）
    func timeline(for configuration: LockNextStopConfigIntent, in context: Context) async -> Timeline<LockNextStopEntry> {
        let now = Date()
        let showsTitle: Bool = configuration.showTitle
        guard let snapshot = WidgetSnapshotStore.read(WidgetLifeSnapshot.self) else {
            let only = LockNextStopEntry(date: now, snapshot: nil, showsTitle: showsTitle)
            return Timeline(entries: [only], policy: .never)
        }
        let plan = TodayWidgetTimeline.plan(snapshot: snapshot, now: now)
        let entries: [LockNextStopEntry] = plan.dates.map {
            LockNextStopEntry(date: $0, snapshot: snapshot, showsTitle: showsTitle)
        }
        let policy: TimelineReloadPolicy
        if let reloadAt = plan.reloadAt {
            policy = .after(reloadAt)
        } else {
            policy = .never
        }
        return Timeline(entries: entries, policy: policy)
    }
}

/// 長方形三行與一行字（只拼時間、標題、場數；標題一律 lockedSurfaceTitle，不寫人名）。
/// [v3] showsTitle＝false（長按設定關掉「顯示主題」）：標題改寫類別字（WidgetStop.lockTitle）
private struct LockNextStopModel {
    /// 第一行前面的圖示（會議 person.2.fill、我的行事曆 calendar、系統行事曆 calendar.badge.clock、旅遊 airplane）；
    /// 一句話時是空字串
    var icon = ""
    /// 第一行（粗）：「10:30 CDA 異常檢討」——標題太長時縮的是這一段
    var line1 = ""
    /// 第一行後面不縮的那一段：「・進行中」「・下一站」
    var line1Suffix = ""
    /// 第二行：「25 分後・今天還有 3 場」「明天 08:30 早會」
    var line2 = ""
    /// 第三行（淡）：「🎂 1 位家人生日」或第一件全天的事
    var line3Icon = ""
    var line3 = ""
    var inlineIcon = "calendar"
    var inlineText = ""
    var url: URL = WidgetLink.today(nil)

    static func make(snapshot: WidgetLifeSnapshot?, now: Date, showsTitle: Bool = true) -> LockNextStopModel {
        var model = LockNextStopModel()
        guard let snap = snapshot, let day = snap.day(at: now) else {
            // 長方形一行約 160pt：整句 15pt 粗體放不下會被截成「…」，拆兩行
            model.line1 = "打開 LifeGood"
            model.line2 = "更新今天的行程"
            model.inlineText = "打開 LifeGood 更新今天的行程"
            return model
        }
        if day.stops.isEmpty {
            fillFree(&model, day: day)
        } else if let cur = day.currentStop(at: now) {
            fillLive(&model, day: day, stop: cur, now: now, showsTitle: showsTitle)
        } else if let next = day.nextStop(at: now) {
            fillUpcoming(&model, day: day, stop: next, now: now, showsTitle: showsTitle)
        } else {
            fillFinished(&model, day: day, showsTitle: showsTitle)
        }
        return model
    }

    static func symbol(for kind: TimelineStopKind) -> String {
        switch kind {
        case .meeting:       return "person.2.fill"
        case .personal:      return "calendar"
        case .appleCalendar: return "calendar.badge.clock"
        case .trip:          return "airplane"
        }
    }

    /// 鎖定畫面的標題：主題（旅遊站名／住宿），空的退回類別字（靈動島那一組）。
    /// [v3] showsTitle 關掉：類別字（lockTitle：「部屬會議」「會議」「系統行事曆」；旅遊照樣站名／住宿），空的退回類別字
    static func title(_ item: WidgetStop, showsTitle: Bool) -> String {
        let text: String = showsTitle ? item.lockedSurfaceTitle : item.lockTitle
        return text.isEmpty ? item.stop.kind.label : text
    }

    /// 「10:30 CDA 異常檢討」（[v3] 關掉主題：「10:30 部屬會議」）
    static func timeAndTitle(_ item: WidgetStop, showsTitle: Bool) -> String {
        DayTimelineFormat.time(item.stop.start) + " " + title(item, showsTitle: showsTitle)
    }

    /// 「今天還有 3 場」（旅遊「站」）；前面有倒數就接成「25 分後・今天還有 3 場」
    static func remainingLine(_ day: WidgetLifeDay, now: Date, kind: TimelineStopKind, lead: String?) -> String {
        let count = day.remainingStops(at: now).count
        let unit = kind == .trip ? "站" : "場"
        let base = "今天還有 \(count) \(unit)"
        guard let lead, !lead.isEmpty else { return base }
        return lead + "・" + base
    }

    /// 第三行：有生日寫「n 位家人生日」（不寫是誰）；沒有就第一件全天的事的 lockTitle
    static func fillAllDay(_ model: inout LockNextStopModel, day: WidgetLifeDay) {
        let birthdays: Int = day.allDay.filter { $0.kind == .birthday }.count
        if birthdays > 0 {
            model.line3Icon = "birthday.cake.fill"
            model.line3 = "\(birthdays) 位家人生日"
        } else if let first = day.allDay.first {
            model.line3Icon = first.icon
            model.line3 = first.lockTitle
        }
    }

    /// 進行中：「👥 10:30 CDA 異常檢討・進行中」「40 分後結束・今天還有 3 場」
    static func fillLive(_ model: inout LockNextStopModel, day: WidgetLifeDay, stop: WidgetStop, now: Date,
                         showsTitle: Bool) {
        let countdown = WidgetDateText.countdown(to: stop.stop.end, from: now)
        let lead: String? = countdown.map { $0 + "結束" }
        let line: String = timeAndTitle(stop, showsTitle: showsTitle)
        model.icon = symbol(for: stop.stop.kind)
        model.line1 = line
        model.line1Suffix = "・進行中"
        model.line2 = remainingLine(day, now: now, kind: stop.stop.kind, lead: lead)
        fillAllDay(&model, day: day)
        model.inlineIcon = model.icon
        model.inlineText = line + "・進行中"
        model.url = WidgetLink.today(stop.stop)
    }

    /// 下一場：「👥 10:30 CDA 異常檢討」「25 分後・今天還有 3 場」；旅遊「✈ 16:20 天神地下街・下一站」
    static func fillUpcoming(_ model: inout LockNextStopModel, day: WidgetLifeDay, stop: WidgetStop, now: Date,
                             showsTitle: Bool) {
        let isTrip = stop.stop.kind == .trip
        let countdown: String? = isTrip ? nil : WidgetDateText.countdown(to: stop.stop.start, from: now)
        let line: String = timeAndTitle(stop, showsTitle: showsTitle)
        model.icon = symbol(for: stop.stop.kind)
        model.line1 = line
        model.line1Suffix = isTrip ? "・下一站" : ""
        model.line2 = remainingLine(day, now: now, kind: stop.stop.kind, lead: countdown)
        fillAllDay(&model, day: day)
        model.inlineIcon = model.icon
        model.inlineText = line
        model.url = WidgetLink.today(stop.stop)
    }

    /// 都跑完了：「今天的行程結束了」「明天 08:30 早會」
    static func fillFinished(_ model: inout LockNextStopModel, day: WidgetLifeDay, showsTitle: Bool) {
        model.line1 = "今天的行程結束了"
        if let next = day.nextDayFirstStop {
            model.line2 = "明天 " + timeAndTitle(next, showsTitle: showsTitle)
            model.inlineIcon = symbol(for: next.stop.kind)
            model.inlineText = model.line2
        } else {
            model.line2 = "明天還沒有排行程"
            model.inlineIcon = "calendar"
            model.inlineText = "今天的行程結束了"
        }
        model.url = WidgetLink.today(nil)
    }

    /// 今天沒行程：「今天沒有排行程」「家人生日」；一行字有生日寫「🎂 今天 家人生日」
    static func fillFree(_ model: inout LockNextStopModel, day: WidgetLifeDay) {
        model.line1 = "今天沒有排行程"
        model.line2 = day.allDay.first?.lockTitle ?? "好好過一天"
        if let birthday = day.allDay.first(where: { $0.kind == .birthday }) {
            model.inlineIcon = "birthday.cake.fill"
            model.inlineText = "今天 " + birthday.lockTitle
        } else {
            model.inlineIcon = "calendar"
            model.inlineText = "今天沒有排行程"
        }
        model.url = WidgetLink.today(nil)
    }
}

struct LockNextStopEntryView: View {
    let entry: LockNextStopEntry

    @Environment(\.widgetFamily) private var family

    private var model: LockNextStopModel {
        LockNextStopModel.make(snapshot: entry.snapshot, now: entry.date, showsTitle: entry.showsTitle)
    }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                Color.clear
            }
            .widgetURL(model.url)
    }

    @ViewBuilder
    private var content: some View {
        if family == .accessoryInline {
            Label(model.inlineText, systemImage: model.inlineIcon)
        } else {
            LockNextStopRect(model: model)
        }
    }
}

/// 長方形三行：粗、一般、淡
private struct LockNextStopRect: View {
    let model: LockNextStopModel

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            LockScreenWidgetLine(icon: model.icon, text: model.line1, suffix: model.line1Suffix,
                                 size: 15, weight: .bold)
            secondLine
            thirdLine
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var secondLine: some View {
        if !model.line2.isEmpty {
            Text(model.line2)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    @ViewBuilder
    private var thirdLine: some View {
        if !model.line3.isEmpty {
            LockScreenWidgetLine(icon: model.line3Icon, text: model.line3, suffix: "",
                                 size: 13, weight: .medium)
                .foregroundStyle(.secondary)
        }
    }
}

/// 一行：（圖示）字（不縮的尾巴）。字太長時縮的是中間那一段，尾巴（「・進行中」、金額）一定看得到
private struct LockScreenWidgetLine: View {
    let icon: String
    let text: String
    let suffix: String
    let size: CGFloat
    let weight: Font.Weight

    var body: some View {
        HStack(spacing: 3) {
            iconView
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            suffixView
        }
        .font(.system(size: size, weight: weight))
    }

    @ViewBuilder
    private var iconView: some View {
        if !icon.isEmpty {
            Image(systemName: icon)
                .font(.system(size: size - 2, weight: .semibold))
        }
    }

    @ViewBuilder
    private var suffixView: some View {
        if !suffix.isEmpty {
            Text(suffix)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

// MARK: - 下一筆要繳（accessoryRectangular）

struct LockNextBillWidget: Widget {
    var body: some WidgetConfiguration {
        // [v3] StaticConfiguration → AppIntentConfiguration（kind 不變：已經放好的升級後用預設值、外觀一樣）
        AppIntentConfiguration(kind: WidgetKind.lockNextBill, intent: LockNextBillConfigIntent.self,
                               provider: LockNextBillProvider()) { entry in
            LockNextBillEntryView(entry: entry)
        }
        .configurationDisplayName("下一筆要繳")
        .description("下一筆要扣的錢是哪天、多少")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct LockNextBillEntry: TimelineEntry {
    let date: Date
    /// nil＝還沒打開過新版 App
    let snapshot: WidgetBillsSnapshot?
    /// 「隱藏金額」開著（provider 讀一次）
    let hidesAmounts: Bool
    /// [v3] 長按設定「顯示名稱」（預設 true＝v2）；false 寫類別字。placeholder／預覽是 true
    var showsName: Bool = true
}

/// [v3] TimelineProvider → AppIntentTimelineProvider（多讀長按設定；排程照舊）
struct LockNextBillProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LockNextBillEntry {
        let now = Date()
        return LockNextBillEntry(date: now, snapshot: BillsSample.snapshot(at: now), hidesAmounts: false,
                                 showsName: true)
    }

    func snapshot(for configuration: LockNextBillConfigIntent, in context: Context) async -> LockNextBillEntry {
        let now = Date()
        if context.isPreview {
            return LockNextBillEntry(date: now, snapshot: BillsSample.snapshot(at: now), hidesAmounts: false,
                                     showsName: true)
        }
        let snapshot = WidgetSnapshotStore.read(WidgetBillsSnapshot.self)
        return LockNextBillEntry(date: now, snapshot: snapshot, hidesAmounts: WidgetHideAmounts.isOn,
                                 showsName: configuration.showName)
    }

    /// 跟「接下來要繳」同一份排程（每天 00:00 自己把「2 天後」改成「明天扣款」）
    func timeline(for configuration: LockNextBillConfigIntent, in context: Context) async -> Timeline<LockNextBillEntry> {
        let now = Date()
        let snapshot = WidgetSnapshotStore.read(WidgetBillsSnapshot.self)
        let hidden = WidgetHideAmounts.isOn
        let showsName: Bool = configuration.showName
        let dates = BillsTimeline.entryDates(snapshot: snapshot, now: now)
        let entries: [LockNextBillEntry] = dates.map {
            LockNextBillEntry(date: $0, snapshot: snapshot, hidesAmounts: hidden, showsName: showsName)
        }
        let policy = BillsTimeline.policy(snapshot: snapshot, dates: dates, now: now)
        return Timeline(entries: entries, policy: policy)
    }
}

/// 「下一筆要繳」／「10/15 Netflix NT$390」／「2 天後・之後還有 5 件」
/// [財富 v4] 卡費、交割：「10/27 卡費」（不寫卡名、金額）／「8 天後・之後還有 4 件」
private struct LockNextBillModel {
    var header = "下一筆要繳"
    /// 「10/15 Netflix」（太長時縮這一段）
    var main = ""
    /// 「NT$390」；隱藏金額時 mask；沒有下一筆是空字串。[財富 v4] 卡費、交割也是空字串（不畫）
    var amount = ""
    var foot = ""
    var url: URL = WidgetLink.fixedExpenses

    /// [v3] showsName＝false（長按設定關掉「顯示名稱」）：「10/15 訂閱服務」（WidgetBill.lockedTitle）
    static func make(snapshot: WidgetBillsSnapshot?, now: Date, hidden: Bool,
                     showsName: Bool = true) -> LockNextBillModel {
        var model = LockNextBillModel()
        guard let snap = snapshot else {
            model.main = "打開 LifeGood 一次"
            return model
        }
        if snap.hasEnded(at: now) {
            model.main = "打開 LifeGood 更新"
            return model
        }
        guard let bill = snap.next(at: now) else {
            model.main = "接下來沒有要扣的"
            return model
        }
        let list = snap.upcoming(at: now)
        let due: String = WidgetDateText.dueText(bill.dueDate, from: now, isIncome: bill.isIncome) ?? ""
        // [財富 v4] 卡費、交割：只寫類別字、不寫金額（不管「顯示名稱」、「隱藏金額」開不開）
        let wealth: Bool = bill.kind.isWealth
        let name: String = (showsName && !wealth) ? bill.title : bill.lockedTitle
        model.main = WidgetDateText.shortDate(bill.dueDate) + " " + name
        model.amount = wealth ? "" : (hidden ? WidgetHideAmounts.mask : bill.amountText)
        // 30 天內還有別的才寫「之後還有 N 件」；30 天外才有下一筆時只寫幾天後
        if list.count > 1 {
            model.foot = due + "・之後還有 \(list.count - 1) 件"
        } else {
            model.foot = due
        }
        model.url = bill.url
        return model
    }
}

struct LockNextBillEntryView: View {
    let entry: LockNextBillEntry

    private var model: LockNextBillModel {
        LockNextBillModel.make(snapshot: entry.snapshot, now: entry.date, hidden: entry.hidesAmounts,
                               showsName: entry.showsName)
    }

    var body: some View {
        LockNextBillRect(model: model)
            .containerBackground(for: .widget) {
                Color.clear
            }
            .widgetURL(model.url)
    }
}

private struct LockNextBillRect: View {
    let model: LockNextBillModel

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(model.header)
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
            LockScreenWidgetLine(icon: "", text: model.main, suffix: model.amount,
                                 size: 14, weight: .medium)
            footLine
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var footLine: some View {
        if !model.foot.isEmpty {
            Text(model.foot)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
