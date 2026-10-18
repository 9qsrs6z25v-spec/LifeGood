import SwiftUI
import WidgetKit
import AppIntents

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
// [v3] 長按可設定（AppIntentConfiguration＋TodayConfigIntent，WidgetConfigs.swift；kind 不變）：
//   • 顯示哪幾種：部屬會議／我的行事曆／系統行事曆／旅遊（預設全開＝v2）。provider 讀快照後**先篩再排 timeline**
//    （WidgetLifeSnapshot.filtered(kinds:)：全天的事的我的行事曆／系統行事曆跟著藏，生日、紀念日照常；
//     「明天 08:30 …」從留下的種類挑）。四種全關＝「今天沒有排行程」。
//   • 鎖著時（StandBy）顯示主題：預設開（主控定案 1＝v2 的 lockedSurfaceTitle）；關掉回到 v1 的類別字
//    （WidgetStop.lockTitle：「部屬會議」「會議」「系統行事曆」；旅遊照樣寫站名）。部屬姓名不管開關都不寫。
//
// [v5] 規格見 scratchpad/widgets/v5/brief.md 的 G3-1～G3-3（design_life.md L1「大的」:169-194、中型「上靈動島」:208-212）。
//   • 大型（.systemLarge；kind、TodayConfigIntent 不變）：表頭同中型（日期、場數、手寫問候），下面只回答四件事——
//     ① 幾點要去哪（還沒結束的最多 5 列；不滿時最上面補最近結束的一場，淡色「已結束」）、
//     ② 今天誰特別（WidgetLifeSnapshot.todaySpecials／todayTeamLine）、③ 要處理（todayTodos）、
//     ④ 接下來（upcomingLines：下一趟旅行＋最多 2 件倒數）。字全部是契約組好的，這裡只挑列數；整區空的不畫標題。
//     小 iPhone 放不下時砍列數、字級不變（TodayLargeView 的 ViewThatFits，列數算在 TodayLargeLayout）。
//     「今天」設定關掉「部屬會議」（showsTeam＝false）時 ②③ 的部屬那幾行也藏。「25 分後」沿用 v1 每分鐘一筆 entry。
//   • 中型「上靈動島」：今天還沒結束的 ≥ 2 場、靈動島沒在跑才出現，Button(intent: StartDayTimelineIntent())
//    （共用檔 DayTimelineToggleIntent.swift，LiveActivityIntent，在 App 的行程裡跑）；跑起來換成小字「靈動島顯示中」。
//     「跑到幾點」provider 讀一次（DayTimelineToggleState.runningUntil，放進 entry.liveUntil），
//     timeline 在那一刻多排一筆，靈動島過期時按鈕自己回來。View 不讀 UserDefaults。
//
// [v25.558] 健康 v7b（build/v7b/brief.md §6 G1-3、G1-4；design_life.md L1 大的、widgets/v5/brief.md）：
//   • 大型最下面、跟「10:02 更新」同一列（左邊運動、右邊更新，TodayLargeFooter）多一行運動：
//     今天有運動「今天 河濱晨跑 5.2 公里」（點了開那一趟的成果頁）；沒有就是這週的進度「這週跑了 14.6 公里・目標 20」
//    （點了開健康頁）；什麼都沒有（新手、很久沒動又沒目標）那一行不畫。字、圖示、網址都是 App 組好放在 life 快照
//     （WidgetLifeSnapshot.workout，WorkoutFacts.widgetWorkoutDays），這裡只呼叫 workoutLine(at:privacy:) 畫字。
//   • 為什麼放頁腳：L1 定「一個區塊一件事、只回答四件事」，運動不另開第五區、不加區標；頁腳只多一列約 17.5pt
//     （沒有運動也沒有「更新」時整列不畫，跟 v5 一樣 0pt）。小 iPhone 放不下時 ViewThatFits 先砍列數（v5 的候選照舊、
//     都帶運動那一行），最後一個候選 (2,0) 才拿掉運動那一行。
//   • 隱私：背景被拿掉、當成 StandBy（mode.privacy）時用 privateText「今天 跑步 5.2 公里」（名字可能是地點），點了只開健康頁。
//   • 長按設定（顯示哪幾種行程）不影響這一行：filtered(kinds:) 只篩 days，workout 原樣帶過來。小、中型、StandBy、鎖定畫面不讀。
//
// 型別（internal 的都帶 TodayWidget 前綴；畫面零件 private）：
//   TodayWidget、TodayWidgetEntry、TodayWidgetProvider、TodayWidgetTimeline、
//   TodayWidgetModel、TodayWidgetRow、TodayWidgetChip、TodayWidgetAxis、TodayWidgetAxisDot、
//   TodayWidgetSample、TodayWidgetEntryView
//   [v3] 設定在 WidgetConfigs.swift 的 TodayConfigIntent
//   [v5] TodayLargeLayout、TodayLargeSegment；畫面零件 TodayLarge…、TodayWidgetLive…（private）

// MARK: - Widget

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        // [v3] StaticConfiguration → AppIntentConfiguration（kind 不變：已經放好的升級後用預設值、外觀一樣）
        AppIntentConfiguration(kind: WidgetKind.today, intent: TodayConfigIntent.self,
                               provider: TodayWidgetProvider()) { entry in
            TodayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("今天")
        .description("下一場幾點、今天幾場、今天誰生日；大的再加要處理的事與接下來")
        // [v5] 加大型（kind 不變，已經放好的小、中不受影響）
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Timeline

struct TodayWidgetEntry: TimelineEntry {
    /// 畫面一律拿這個當「現在」（不在 View 裡呼叫 Date()）
    let date: Date
    /// nil＝還沒打開過新版 App（或檔案讀不到）。
    /// [v3] 已經照長按設定篩過種類（provider 篩，View 不再篩）
    let snapshot: WidgetLifeSnapshot?
    /// [v3] StandBy 寫主題（true，預設＝v2）或類別字（false）。placeholder／預覽是 true
    var showsSubjectWhenLocked: Bool = true
    /// [v5] 大型 ②③ 要不要寫部屬那幾行（＝長按設定「部屬會議」；週末關掉公司的事，部屬也一起藏）
    var showsTeam: Bool = true
    /// [v5] 靈動島跑到幾點（provider 讀一次 DayTimelineToggleState.runningUntil）；沒在跑是 nil。
    /// 中型「上靈動島」按鈕：> date 時換成「靈動島顯示中」
    var liveUntil: Date? = nil
}

/// [v3] TimelineProvider → AppIntentTimelineProvider（多讀長按設定；排程照舊，拿篩過的快照排）
struct TodayWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TodayWidgetEntry {
        TodayWidgetSample.entry(now: Date())
    }

    func snapshot(for configuration: TodayConfigIntent, in context: Context) async -> TodayWidgetEntry {
        if context.isPreview {
            // 小工具庫裡的預覽：寫死的樣本（10:05、下一場 10:30）
            return TodayWidgetSample.entry(now: Date())
        }
        let snapshot = Self.readFiltered(configuration)
        return TodayWidgetEntry(date: Date(), snapshot: snapshot,
                                showsSubjectWhenLocked: configuration.standBySubject,
                                showsTeam: configuration.showMeetings,
                                liveUntil: DayTimelineToggleState.runningUntil)
    }

    func timeline(for configuration: TodayConfigIntent, in context: Context) async -> Timeline<TodayWidgetEntry> {
        let now = Date()
        let subject: Bool = configuration.standBySubject
        // [v5] 關掉「部屬會議」時大型的部屬那幾行也藏；靈動島「跑到幾點」讀一次
        let showsTeam: Bool = configuration.showMeetings
        let liveUntil: Date? = DayTimelineToggleState.runningUntil
        guard let snapshot = Self.readFiltered(configuration) else {
            // App 第一次寫完快照會叫重畫，這裡不用定時
            let only = TodayWidgetEntry(date: now, snapshot: nil, showsSubjectWhenLocked: subject,
                                        showsTeam: showsTeam, liveUntil: liveUntil)
            return Timeline(entries: [only], policy: .never)
        }
        let plan = TodayWidgetTimeline.plan(snapshot: snapshot, now: now)
        let dates: [Date] = TodayWidgetTimeline.adding(liveUntil: liveUntil, to: plan.dates, now: now,
                                                       validUntil: snapshot.validUntil)
        let entries: [TodayWidgetEntry] = dates.map {
            TodayWidgetEntry(date: $0, snapshot: snapshot, showsSubjectWhenLocked: subject,
                             showsTeam: showsTeam, liveUntil: liveUntil)
        }
        let policy: TimelineReloadPolicy
        if let reloadAt = plan.reloadAt {
            policy = .after(reloadAt)
        } else {
            policy = .never
        }
        return Timeline(entries: entries, policy: policy)
    }

    /// [v3] 讀 life 快照、照設定只留開著的那幾種（四種都開＝原樣）
    private static func readFiltered(_ configuration: TodayConfigIntent) -> WidgetLifeSnapshot? {
        let kinds: Set<TimelineStopKind> = configuration.kinds
        return WidgetSnapshotStore.read(WidgetLifeSnapshot.self)?.filtered(kinds: kinds)
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

    /// [v5] 靈動島「跑到幾點」在 (now, validUntil] 之間就多排一筆：過了那一刻，中型的「上靈動島」自己回來。
    /// plan(snapshot:now:) 的簽名不動（鎖定畫面「下一場」也在用），所以另外插
    static func adding(liveUntil: Date?, to dates: [Date], now: Date, validUntil: Date) -> [Date] {
        guard let until = liveUntil, until > now, until <= validUntil else { return dates }
        var times = Set<Date>(dates)
        times.insert(until)
        return times.sorted()
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
    /// 最右邊：「進行中」「25 分後」「已結束」或空字串
    let trailing: String
    let url: URL
    /// [v5] 大型 ① 最上面補的「最近結束的一場」（淡色、「已結束」）。中型不會有
    var isDone: Bool = false

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

    // [v5] 中型「上靈動島」
    /// 今天還沒結束的（篩過的）≥ 2 場、靈動島沒在跑
    var showsLiveButton = false
    /// 靈動島正在跑（liveUntil > now）：按鈕換成小字「靈動島顯示中」
    var showsLiveRunning = false

    // [v5] 大型（includesLarge 時才填）
    /// ① 還沒結束的每一場（最多 TodayLargeLayout.maxStopRows），一場都不剩時是中型的訊息列
    var largeRows: [TodayWidgetRow] = []
    /// ① 最近結束的一場（淡色）；一場都不剩（largeRows 是訊息列）或還沒有結束的是 nil
    var largeDone: TodayWidgetRow? = nil
    /// ② 第一行：全天的事、今天／明天生日（todaySpecials；最多 3 段）
    var specials: [WidgetLineItem] = []
    /// ② 第二行：「部屬 請假 2・大夜 3・小夜 2」（todayTeamLine）
    var teamLine: WidgetLineItem? = nil
    /// ③ 要處理（todayTodos）
    var todos: [WidgetLineItem] = []
    /// ④ 接下來（upcomingLines：旅行＋最多 2 件倒數）；畫幾列由 TodayLargeLayout.upcoming 挑
    var upcoming: [WidgetLineItem] = []
    /// [健康 v7b] 最下面那一行運動（WidgetLifeSnapshot.workoutLine）；nil＝不畫
    var workoutLine: WidgetLineItem? = nil

    /// 小型整塊點下去
    var tapURL: URL = WidgetLink.today(nil)

    /// privacy＝StandBy（背景被拿掉）：標題換成 lockedSurfaceTitle（[v2] 主題，不含人名）、不寫 owner、
    /// 全天的事用 lockTitle（J:177）。
    /// [v3] showsSubject＝長按設定「鎖著時顯示主題」：false 時 privacy 的標題回到 v1 的類別字（WidgetStop.lockTitle）。
    /// 非 privacy（主畫面）不受影響
    /// [v5] showsTeam＝長按設定「部屬會議」（大型 ②③ 的部屬那幾行）；liveUntil＝靈動島跑到幾點（中型按鈕）；
    /// includesLarge＝大型才組 ②③④（小、中不用）
    static func make(snapshot: WidgetLifeSnapshot?, now: Date, privacy: Bool,
                     showsSubject: Bool = true, showsTeam: Bool = true,
                     liveUntil: Date? = nil, includesLarge: Bool = false) -> TodayWidgetModel {
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
        let mode = TodayWidgetTitleMode(privacy: privacy, showsSubject: showsSubject)
        model.rows = TodayWidgetText.rows(day: day, now: now, mode: mode, limit: rowLimit)
        TodayWidgetText.fillIsland(&model, day: day, now: now, liveUntil: liveUntil)
        if includesLarge {
            TodayWidgetText.fillLarge(&model, snapshot: snap, day: day, now: now, mode: mode,
                                      showsTeam: showsTeam)
        }

        if day.stops.isEmpty {
            TodayWidgetText.fillFree(&model, day: day, privacy: privacy)
        } else if let cur = day.currentStop(at: now) {
            TodayWidgetText.fillLive(&model, day: day, stop: cur, now: now, mode: mode)
        } else if let next = day.nextStop(at: now) {
            TodayWidgetText.fillUpcoming(&model, day: day, stop: next, now: now, mode: mode)
        } else {
            TodayWidgetText.fillFinished(&model, day: day, mode: mode)
        }
        return model
    }
}

/// [v3] 行程標題怎麼寫：privacy＝StandBy；showsSubject＝長按設定「鎖著時顯示主題」
private struct TodayWidgetTitleMode {
    let privacy: Bool
    let showsSubject: Bool

    /// StandBy 那一行（standByLine）一律用鎖著的寫法，主題開關照設定
    var locked: TodayWidgetTitleMode {
        TodayWidgetTitleMode(privacy: true, showsSubject: showsSubject)
    }
}

/// 組字的小函式（只拼日期、時間、標題，不碰金額）
private enum TodayWidgetText {
    static func title(_ item: WidgetStop, mode: TodayWidgetTitleMode) -> String {
        if mode.privacy && mode.showsSubject {
            // [v2] 決定 2：StandBy 寫會議主題（旅遊寫站名／住宿），部屬姓名不寫
            let locked = item.lockedSurfaceTitle
            return locked.isEmpty ? item.stop.kind.label : locked
        }
        if mode.privacy {
            // [v3] 設定關掉「鎖著時顯示主題」：回到 v1 的類別字（旅遊的 lockTitle 本來就是站名／住宿）
            return item.lockTitle.isEmpty ? item.stop.kind.label : item.lockTitle
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
                         now: Date, mode: TodayWidgetTitleMode) {
        let countdown = WidgetDateText.countdown(to: stop.stop.end, from: now)
        model.kind = .live
        model.countText = "\(day.stops.count) 場"
        model.summary = countSummary(day, now: now)
        model.label = countdown.map { "進行中・" + $0 + "結束" } ?? "進行中"
        model.heroPrefix = "到"
        model.hero = DayTimelineFormat.time(stop.stop.end)
        model.line = title(stop, mode: mode)
        model.standByLine = title(stop, mode: mode.locked)
        model.standBySub = countdown.map { $0 + "結束" } ?? "進行中"
        model.standBySubIsCountdown = countdown != nil
        model.tapURL = WidgetLink.today(stop.stop)
    }

    /// 下一場：「今天第一場・50 分後」「下一場・25 分後」「10:30」
    static func fillUpcoming(_ model: inout TodayWidgetModel, day: WidgetLifeDay, stop: WidgetStop,
                             now: Date, mode: TodayWidgetTitleMode) {
        let countdown = WidgetDateText.countdown(to: stop.stop.start, from: now)
        let isFirst = stop.id == day.stops.first?.id
        let head = isFirst ? "今天第一場" : "下一場"
        model.kind = .upcoming
        model.countText = "\(day.stops.count) 場"
        model.summary = countSummary(day, now: now)
        model.label = countdown.map { head + "・" + $0 } ?? head
        model.hero = DayTimelineFormat.time(stop.stop.start)
        model.line = title(stop, mode: mode)
        model.standByLine = title(stop, mode: mode.locked)
        model.standBySub = countdown ?? head
        model.standBySubIsCountdown = countdown != nil
        model.tapURL = WidgetLink.today(stop.stop)
    }

    /// 都跑完了：「今天的行程結束了」「明天 08:30」「早會」
    static func fillFinished(_ model: inout TodayWidgetModel, day: WidgetLifeDay, mode: TodayWidgetTitleMode) {
        model.kind = .finished
        model.countText = "\(day.stops.count) 場"
        model.summary = "今天 \(day.stops.count) 場・都結束了"
        model.label = "今天的行程結束了"
        model.standBySub = "今天的行程結束了"
        if let next = day.nextDayFirstStop {
            model.heroPrefix = "明天"
            model.hero = DayTimelineFormat.time(next.stop.start)
            model.line = title(next, mode: mode)
            model.standByLine = title(next, mode: mode.locked)
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
    static func rows(day: WidgetLifeDay, now: Date, mode: TodayWidgetTitleMode, limit: Int) -> [TodayWidgetRow] {
        let remaining = day.remainingStops(at: now)
        if !remaining.isEmpty {
            return remaining.prefix(limit).map { stopRow($0, now: now, mode: mode) }
        }
        var out: [TodayWidgetRow] = []
        if !day.stops.isEmpty {
            out.append(messageRow(id: "lg-row-done", text: "今天的行程結束了"))
        }
        if let next = day.nextDayFirstStop {
            out.append(tomorrowRow(next, mode: mode))
        } else if day.stops.isEmpty {
            out.append(messageRow(id: "lg-row-free", text: "好好過一天"))
        } else {
            out.append(messageRow(id: "lg-row-none", text: "明天還沒有排行程"))
        }
        return out
    }

    static func stopRow(_ item: WidgetStop, now: Date, mode: TodayWidgetTitleMode) -> TodayWidgetRow {
        let trailing: String
        if item.stop.start <= now {
            trailing = "進行中"
        } else {
            trailing = WidgetDateText.countdown(to: item.stop.start, from: now) ?? ""
        }
        return TodayWidgetRow(id: item.id,
                              kind: item.stop.kind,
                              time: DayTimelineFormat.time(item.stop.start),
                              title: title(item, mode: mode),
                              owner: mode.privacy ? "" : item.stop.owner,
                              trailing: trailing,
                              url: WidgetLink.today(item.stop))
    }

    static func tomorrowRow(_ item: WidgetStop, mode: TodayWidgetTitleMode) -> TodayWidgetRow {
        TodayWidgetRow(id: "lg-row-tomorrow-" + item.id,
                       kind: item.stop.kind,
                       time: "明天 " + DayTimelineFormat.time(item.stop.start),
                       title: title(item, mode: mode),
                       owner: mode.privacy ? "" : item.stop.owner,
                       trailing: "",
                       url: WidgetLink.today(item.stop))
    }

    static func messageRow(id: String, text: String) -> TodayWidgetRow {
        TodayWidgetRow(id: id, kind: nil, time: "", title: text, owner: "", trailing: "",
                       url: WidgetLink.today(nil))
    }

    // MARK: [v5]

    /// 中型「上靈動島」：靈動島在跑（liveUntil > now）寫「靈動島顯示中」；沒在跑、還剩 2 場以上才出現按鈕
    static func fillIsland(_ model: inout TodayWidgetModel, day: WidgetLifeDay, now: Date, liveUntil: Date?) {
        let running: Bool = liveUntil.map { $0 > now } ?? false
        let left: Int = day.remainingStops(at: now).count
        model.showsLiveRunning = running
        model.showsLiveButton = !running && left >= 2
    }

    /// 大型 ①～④。字全部是契約組好的（WidgetLifeSnapshot.todaySpecials／todayTeamLine／todayTodos／upcomingLines），
    /// 這裡只放進 model。privacy（StandBy 沒有大型；萬一背景被拿掉被當成 StandBy）：不寫任何人名——
    /// ② 生日那一行不畫、④ 只留旅行；部屬、待辦本來就只有數字。
    /// [健康 v7b] 多放最下面那一行運動（privacy 時是不寫名字的 privateText）
    static func fillLarge(_ model: inout TodayWidgetModel, snapshot snap: WidgetLifeSnapshot, day: WidgetLifeDay,
                          now: Date, mode: TodayWidgetTitleMode, showsTeam: Bool) {
        model.largeRows = rows(day: day, now: now, mode: mode, limit: TodayLargeLayout.maxStopRows)
        let hasRemaining: Bool = !day.remainingStops(at: now).isEmpty
        model.largeDone = hasRemaining ? doneRow(day: day, now: now, mode: mode) : nil
        model.specials = mode.privacy ? [] : snap.todaySpecials(at: now, includeTeam: showsTeam)
        model.teamLine = snap.todayTeamLine(at: now, includeTeam: showsTeam)
        model.todos = snap.todayTodos(at: now, includeTeam: showsTeam)
        let countdownLimit: Int = mode.privacy ? 0 : TodayLargeLayout.maxCountdowns
        model.upcoming = snap.upcomingLines(at: now, countdownLimit: countdownLimit)
        // [健康 v7b] 最下面那一行運動。privacy＝背景被拿掉：不寫這一趟的名字、點了只開健康頁
        model.workoutLine = snap.workoutLine(at: now, privacy: mode.privacy)
    }

    /// 大型 ① 最近結束的一場：淡色、最右邊「已結束」，點了一樣開那一場。還沒有結束的是 nil
    static func doneRow(day: WidgetLifeDay, now: Date, mode: TodayWidgetTitleMode) -> TodayWidgetRow? {
        let ended: [WidgetStop] = day.stops.filter { $0.stop.end <= now }
        let latest: WidgetStop? = ended.max(by: { (a: WidgetStop, b: WidgetStop) -> Bool in
            a.stop.end < b.stop.end
        })
        guard let item = latest else { return nil }
        return TodayWidgetRow(id: "lg-row-ended-" + item.id,
                              kind: item.stop.kind,
                              time: DayTimelineFormat.time(item.stop.start),
                              title: title(item, mode: mode),
                              owner: mode.privacy ? "" : item.stop.owner,
                              trailing: "已結束",
                              url: WidgetLink.today(item.stop),
                              isDone: true)
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

/// [v5] 大型 ② 第一行的一段（第二段起前面有「・」）
struct TodayLargeSegment: Identifiable {
    let id: String
    let item: WidgetLineItem
    let leadingDot: Bool
}

/// [v5] 大型的列數（純函式；View 只呼叫這些，不自己切陣列）。
/// 小 iPhone（大型約 292×311，內容約 260×279）放不下時，TodayLargeView 由上往下試
/// （① 幾場, ④ 幾列）＝(5,3)(4,3)(4,2)(3,2)(3,1)(2,1)，[審查補] 最後 (2,0)；字級不變
enum TodayLargeLayout {
    /// ① 最多幾列
    static let maxStopRows = 5
    /// ④ 旅行之外最多幾件倒數
    static let maxCountdowns = 2

    /// ① 前 limit 列；不滿 limit 列時最上面補最近結束的一場（一場都不剩時是訊息列，不補）
    static func stopRows(model: TodayWidgetModel, limit: Int) -> [TodayWidgetRow] {
        let base: [TodayWidgetRow] = Array(model.largeRows.prefix(max(0, limit)))
        guard let done = model.largeDone, base.count < limit else { return base }
        return [done] + base
    }

    /// ④ 前 limit 列（旅行在最前面）
    static func upcoming(model: TodayWidgetModel, limit: Int) -> [WidgetLineItem] {
        Array(model.upcoming.prefix(max(0, limit)))
    }

    /// ② 第一行前 count 段，第二段起前面加「・」
    static func segments(_ items: [WidgetLineItem], count: Int) -> [TodayLargeSegment] {
        let shown: [WidgetLineItem] = Array(items.prefix(max(0, count)))
        var out: [TodayLargeSegment] = []
        for (index, item) in shown.enumerated() {
            out.append(TodayLargeSegment(id: item.id, item: item, leadingDot: index > 0))
        }
        return out
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
        var snapshot = WidgetLifeSnapshot(generatedAt: sampleNow,
                                          dataDay: WidgetDateText.dayKey(dayStart),
                                          validUntil: validUntil,
                                          days: [day])
        // [v5] 大型預覽的 ②③④（契約的樣本：請假 2・大夜 3・小夜 2、明天 王小明生日、部屬任務逾期 2・今天到期 3、
        // 家庭待辦今天到期 1、勇闖福岡親子行還有 38 天、結婚紀念日還有 23 天、女兒 3 歲生日還有 40 天）。
        // 小、中、鎖定畫面不讀這幾欄，看不到差別
        snapshot.trips = [WidgetLifeSample.trip(dayStart: dayStart)]
        snapshot.hasTeam = true
        snapshot.team = [WidgetLifeSample.teamDay(dayStart: dayStart)]
        snapshot.familyTasks = [WidgetLifeSample.familyTasksDay(dayStart: dayStart)]
        snapshot.countdowns = WidgetLifeSample.countdowns(dayStart: dayStart)
        // [健康 v7b] 大型最下面那一行運動：這週跑了 14.6 公里・目標 20（契約的樣本；小、中、鎖定畫面不讀）
        snapshot.workout = [WidgetLifeSample.workoutDay(dayStart: dayStart)]
        return TodayWidgetEntry(date: sampleNow, snapshot: snapshot, showsSubjectWhenLocked: true)
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
        TodayWidgetModel.make(snapshot: entry.snapshot, now: entry.date, privacy: surface.isStandBy,
                              showsSubject: entry.showsSubjectWhenLocked, showsTeam: entry.showsTeam,
                              liveUntil: entry.liveUntil, includesLarge: isLarge)
    }

    private var isMedium: Bool { family == .systemMedium }

    /// [v5]
    private var isLarge: Bool { family == .systemLarge }

    /// [v5] 中、大型：每一列各自是 Link、右上角有手寫問候
    private var hasRowLinks: Bool { isMedium || isLarge }

    /// 小型整塊開那一場；中、大型每一列各自是 Link，其他地方開我的行事曆（J:167）
    private var tapURL: URL {
        hasRowLinks ? WidgetLink.today(nil) : model.tapURL
    }

    /// 中、大型右上角有手寫問候，月牙／雲不放右上（J:56）；小型右上有「4 場」，放大字那一列旁
    private var skyMoon: WidgetSkyMoon {
        hasRowLinks ? WidgetSkyMoon.topLeading : WidgetSkyMoon.middleTrailing
    }

    var body: some View {
        TodayWidgetContent(model: model, palette: palette,
                           standBy: surface.isStandBy, isMedium: isMedium, isLarge: isLarge)
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
    /// [v5]
    var isLarge: Bool = false

    var body: some View {
        if model.kind == .message {
            TodayMessageView(text: model.message, palette: palette)
        } else if isLarge {
            TodayLargeView(model: model, palette: palette)
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
            TodayMediumHeader(model: model, palette: palette, showsLiveControl: true)
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

/// 左邊日期＋場數，右上手寫問候；放不下就不寫問候（J:164）。
/// [v5] 中型（showsLiveControl）：場數那一行右邊放「上靈動島」或「靈動島顯示中」——比手寫問候重要，
/// 放不下時 ViewThatFits 先丟的是問候。大型也用這個表頭，但不放按鈕（false）
private struct TodayMediumHeader: View {
    let model: TodayWidgetModel
    let palette: WidgetPalette
    var showsLiveControl: Bool = false

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
            HStack(spacing: 6) {
                Text(model.summary)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                liveControl
            }
        }
    }

    /// [v5] 還剩 2 場以上、靈動島沒在跑：按鈕；正在跑：小字。其他時候什麼都不放
    @ViewBuilder
    private var liveControl: some View {
        if showsLiveControl && model.showsLiveButton {
            TodayWidgetLiveButton(palette: palette)
        } else if showsLiveControl && model.showsLiveRunning {
            TodayWidgetLiveRunningText(palette: palette)
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

/// 一列：記號、時間、標題、owner（灰）、最右邊「進行中」或倒數。
/// [v5] 大型最上面補的「最近結束的一場」（isDone）：整列淡色（0.45）、「已結束」灰字
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
        .opacity(rowOpacity)
    }

    private var titleColor: Color {
        row.isMessage ? palette.label : palette.ink
    }

    private var trailingColor: Color {
        row.isDone ? palette.label : palette.countdown
    }

    private var rowOpacity: Double {
        row.isDone ? 0.45 : 1
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
                .foregroundStyle(trailingColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 70, alignment: .trailing)
        }
    }
}

// MARK: 中型「上靈動島」（[v5]）

/// 「上靈動島」：StartDayTimelineIntent（共用檔，LiveActivityIntent：在 App 的行程裡背景跑、不開 App 畫面；
/// 沒交到 App 時存成待套用，App 下次回前景套用）。膠囊同全天的事（capsuleFill／capsuleText）
private struct TodayWidgetLiveButton: View {
    let palette: WidgetPalette

    var body: some View {
        Button(intent: StartDayTimelineIntent()) {
            TodayWidgetLiveButtonLabel(palette: palette)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("把今天的行程放上靈動島")
    }
}

private struct TodayWidgetLiveButtonLabel: View {
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "calendar.day.timeline.left")
                .font(.system(size: 9.5, weight: .bold))
            Text("上靈動島")
                .font(.system(size: 10.5, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(palette.capsuleText)
        .padding(.horizontal, 7)
        // [審查] 上下 2（不是膠囊的 3）：10.5pt 中文行高約 14.8＋4 ≈ 18.8，不比旁邊 13.5pt 的場數（約 19）高，
        // 中型表頭不會因為多了按鈕變高（矮的中型才不會因此從三列退成兩列）
        .padding(.vertical, 2)
        .background(palette.capsuleFill, in: Capsule())
        .fixedSize()
    }
}

/// 靈動島正在跑：小字「靈動島顯示中」（不是按鈕；要收掉去控制中心或設定頁）
private struct TodayWidgetLiveRunningText: View {
    let palette: WidgetPalette

    var body: some View {
        Text("靈動島顯示中")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(palette.label)
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: 大型（[v5]）

/// 表頭（同中型：日期、場數、手寫問候；不放「上靈動島」）＋四區。
/// 小 iPhone 放不下時砍列數、字級不變：ViewThatFits 由上往下挑第一個放得下的（① 幾場, ④ 幾列）。
/// 估高（[審查] 中文字的行高約字級 ×1.4，比英文高；區塊全滿＝樣本那一天）：表頭 38、
/// ① 標 23＋每場 18.2（列距 3）、② 60（兩行）、③ 59（兩行）、④ 標 23＋每列 17.5（列距 1）、「10:02 更新」13 →
/// (5,3) 約 360、(4,3) 約 339（Pro Max 內容約 350）、(4,2) 約 320（6.1 吋內容約 322）、(3,2) 約 299、
/// (3,1) 約 281（SE 內容約 292）、(2,1) 約 259（292×311 內容約 279，加「更新」那行約 272 也放得下）。
/// [審查補] 最後再一個 (2,0)：④ 整區不畫（連標題），中文字行高比估的再高一點時也不會被截
/// [健康 v7b] 頁腳（TodayLargeFooter）有運動那一行時約 17.5＋上距 4（原本只有「更新」13、沒有上距）：
/// 上面七個候選都帶運動那一行（放不下先砍列數），最後再一個 (2,0) 不帶運動那一行
private struct TodayLargeView: View {
    let model: TodayWidgetModel
    let palette: WidgetPalette

    var body: some View {
        ViewThatFits(in: .vertical) {
            column(stopLimit: 5, nextLimit: 3, showsWorkout: true)
            column(stopLimit: 4, nextLimit: 3, showsWorkout: true)
            column(stopLimit: 4, nextLimit: 2, showsWorkout: true)
            column(stopLimit: 3, nextLimit: 2, showsWorkout: true)
            column(stopLimit: 3, nextLimit: 1, showsWorkout: true)
            column(stopLimit: 2, nextLimit: 1, showsWorkout: true)
            column(stopLimit: 2, nextLimit: 0, showsWorkout: true)
            column(stopLimit: 2, nextLimit: 0, showsWorkout: false)
        }
    }

    /// [健康 v7b] showsWorkout＝頁腳要不要畫運動那一行（false 時只剩「10:02 更新」，同 v5）
    private func column(stopLimit: Int, nextLimit: Int, showsWorkout: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TodayMediumHeader(model: model, palette: palette)
            TodayLargeStopsSection(rows: TodayLargeLayout.stopRows(model: model, limit: stopLimit),
                                   palette: palette)
            TodayLargeSpecialsSection(specials: model.specials, teamLine: model.teamLine, palette: palette)
            TodayLargeLinesSection(heading: "要處理", items: model.todos, palette: palette)
            TodayLargeLinesSection(heading: "接下來",
                                   items: TodayLargeLayout.upcoming(model: model, limit: nextLimit),
                                   palette: palette)
            Spacer(minLength: 0)
            TodayLargeFooter(workout: footerWorkout(showsWorkout),
                             updatedText: model.updatedText,
                             palette: palette)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// [健康 v7b] 頁腳的運動那一行：候選不帶（showsWorkout＝false）或快照沒有就是 nil
    private func footerWorkout(_ showsWorkout: Bool) -> WidgetLineItem? {
        guard showsWorkout else { return nil }
        return model.workoutLine
    }
}

/// 區標：「幾點要去哪」「今天誰特別」「要處理」「接下來」
private struct TodayLargeSectionTitle: View {
    let text: String
    let palette: WidgetPalette

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(palette.label)
            .lineLimit(1)
    }
}

/// ① 幾點要去哪：一列一場（同中型的列，每列 Link 開那一場）；一場都不剩時是訊息列
private struct TodayLargeStopsSection: View {
    let rows: [TodayWidgetRow]
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TodayLargeSectionTitle(text: "幾點要去哪", palette: palette)
            TodayRowsList(rows: rows, updatedText: "", palette: palette)
        }
        .padding(.top, 6)
    }
}

/// ②③④ 的一列：圖示 10pt＋字 12.5pt，一行
private struct TodayLargeLineView: View {
    let item: WidgetLineItem
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: item.icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.label)
                .frame(width: 13)
            Text(item.text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
    }
}

/// 一串列，每列一個 Link（點了去契約給的網址）
private struct TodayLargeLinks: View {
    let items: [WidgetLineItem]
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(items, id: \.id) { item in
                Link(destination: item.url) {
                    TodayLargeLineView(item: item, palette: palette)
                }
            }
        }
    }
}

/// ③ 要處理、④ 接下來：沒有東西整區不畫（連標題）
private struct TodayLargeLinesSection: View {
    let heading: String
    let items: [WidgetLineItem]
    let palette: WidgetPalette

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                TodayLargeSectionTitle(text: heading, palette: palette)
                TodayLargeLinks(items: items, palette: palette)
            }
            .padding(.top, 6)
        }
    }
}

/// ② 今天誰特別：第一行全天的事與生日（每段一個 Link；放不下 3 段→2 段→1 段），第二行部屬人數
private struct TodayLargeSpecialsSection: View {
    let specials: [WidgetLineItem]
    let teamLine: WidgetLineItem?
    let palette: WidgetPalette

    private var hasContent: Bool { !specials.isEmpty || teamLine != nil }

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: 2) {
                TodayLargeSectionTitle(text: "今天誰特別", palette: palette)
                specialsRow
                teamRow
            }
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private var specialsRow: some View {
        if !specials.isEmpty {
            ViewThatFits(in: .horizontal) {
                segmentsRow(3)
                segmentsRow(2)
                segmentsRow(1)
            }
        }
    }

    @ViewBuilder
    private var teamRow: some View {
        if let line = teamLine {
            Link(destination: line.url) {
                TodayLargeLineView(item: line, palette: palette)
            }
        }
    }

    private func segmentsRow(_ count: Int) -> some View {
        TodayLargeSegmentsRow(segments: TodayLargeLayout.segments(specials, count: count), palette: palette)
    }
}

private struct TodayLargeSegmentsRow: View {
    let segments: [TodayLargeSegment]
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 4) {
            ForEach(segments, id: \.id) { segment in
                TodayLargeSegmentView(segment: segment, palette: palette)
            }
        }
    }
}

/// 一段：「・」（第二段起）＋圖示＋字；點了去那一段的網址（我的行事曆／生日名單）
private struct TodayLargeSegmentView: View {
    let segment: TodayLargeSegment
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 4) {
            if segment.leadingDot {
                Text("・")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(palette.label)
            }
            Link(destination: segment.item.url) {
                TodayLargeLineView(item: segment.item, palette: palette)
            }
        }
    }
}

/// [健康 v7b] 最下面那一列（取代 v5 的 TodayLargeUpdatedLine）：左邊運動那一行（Link，點了開那一趟／健康頁；
/// 圖示、字級照 TodayLargeLineView，不加區標）、右邊快照超過 3 小時的小字「10:02 更新」（同中型）。
/// 兩個都沒有：整列不畫（0pt）；只有「更新」：跟 v5 一模一樣（靠右、沒有上距）
private struct TodayLargeFooter: View {
    let workout: WidgetLineItem?
    let updatedText: String
    let palette: WidgetPalette

    private var hasContent: Bool { workout != nil || !updatedText.isEmpty }

    /// 有運動那一行才跟上面隔 4pt
    private var topGap: CGFloat { workout == nil ? 0 : 4 }

    var body: some View {
        if hasContent {
            HStack(spacing: 6) {
                workoutLink
                Spacer(minLength: 4)
                updatedLabel
            }
            .padding(.top, topGap)
        }
    }

    @ViewBuilder
    private var workoutLink: some View {
        if let line = workout {
            Link(destination: line.url) {
                TodayLargeLineView(item: line, palette: palette)
            }
        }
    }

    /// 「10:02 更新」不讓運動那一行擠掉（固定自己的寬度，字長的是運動那一行縮）
    @ViewBuilder
    private var updatedLabel: some View {
        if !updatedText.isEmpty {
            Text(updatedText)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(palette.label)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
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
