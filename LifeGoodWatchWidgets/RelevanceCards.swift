import SwiftUI
import WidgetKit
import AppIntents

// MARK: - 智慧型堆疊：自己浮上來的五張卡、「下一場」「已花」「這週跑步」自己往上排（手錶 v7b，v25.584；
//         watch/judge.md §3.2、§2.17、§6.1、§7.8-3；watch/build/v7b/brief.md §1、§2、G2）
//
// 只屬於 LifeGoodWatchWidgets。**主控寫好（不准改）：WatchRelevanceClues、三個 provider 的 relevance()、RelevanceCardSource、
// RelevanceCardIntent、RelevanceCardEntry、RelevanceCardProvider、五個 *CardWidget。RelevanceCardView 以下 G2 填。**
//
// 為什麼手錶小格這個檔要 import AppIntents（pbxwatch_check S 段准許清單）：
//   • RelevanceEntriesProvider 的 Configuration 規定要是 WidgetConfigurationIntent（App Intents 的型別；build/v7b/doc/）
//   • RelevantContext（「這段時間浮上來」）現在定義在 RelevanceKit；Apple：「import App Intents 就會帶進 RelevanceKit，
//     不用自己 import RelevanceKit」。RelevanceKit 這個框架 watchOS 26 才有，**這個專案一律不准直接 import RelevanceKit**
//     （最低 watchOS 11，直接連會在舊錶上找不到框架），RelevantContext 從 App Intents 拿（它在 App Intents 裡從 watchOS 10 就有）
//
// 1. 「下一場」「已花」「這週跑步」（你自己加進堆疊、錶面的那幾種）：TimelineProvider 的 relevance()（watchOS 11 起；
//    回 WidgetRelevance＋RelevantContext.date(from:to:)，watchOS 10 起、watchOS 26 起標舊寫法——最低 watchOS 11 照用）。
//    手錶的堆疊排序**不看** TimelineEntryRelevance（那是 iPhone、iPad 的，Apple〈Increasing the visibility of widgets in
//    Smart Stacks〉對照表），只看這個。時段在 WatchRelevancePlan（Shared/WatchRelevance.swift）：
//      下一場＝每場開始前 60 分鐘到結束；已花＝平日 11:30–13:30、17:30–19:30；這週跑步＝平常跑步的時段（同那張卡）
//    只用時間當線索：不用位置、不用運動、睡眠權限（不加任何 Info.plist 鍵、entitlement）。
// 2. 五張卡（watchOS 26 才有：RelevanceConfiguration＋RelevanceEntriesProvider，**只在智慧型堆疊出現、不能手動加**）：
//    早安、快開會了、卡費快到了、平常跑步的時間、旅途下一站。字是 iPhone 寫好的（包裡 relevanceCards；平常跑步的公里手錶算），
//    這裡只排版。手腕放下、沒解鎖：會議名、站名、旅行名換 privateLines（WatchPrivacyRule.hidesPersonal）；部屬名字一律不上卡；
//    卡費只有「卡費」與日期（包裡根本沒有卡名、金額）。底色同一片夜空（WatchWidgetStyle.sky），狀態只上在字（不整片紅綠）。
//    「快開會了」「旅途下一站」可以替掉你自己放的「下一場」、「平常跑步的時間」替掉「這週跑步」（associatedKind，watchOS 26）。
//    堆疊卡沒有時間軸（系統拿一次字就畫），所以不寫會跑的倒數「5 分後」（brief §1-3）。
// 每一張卡最外層 .containerBackground(for: .widget)（少了整格變成系統的英文提示，judge §7.8-10）。

// MARK: - 1. 你自己加的三種：relevance()（watchOS 11 起）

/// 「這幾段時間該浮上來」→ 系統要的那一包（照開始時間，近的先：Apple 說系統可能只用前面幾個）
enum WatchRelevanceClues {
    static func relevance(_ windows: [WatchRelevanceWindow]) -> WidgetRelevance<Void> {
        let attributes: [WidgetRelevanceAttribute<Void>] = windows.map { w in
            WidgetRelevanceAttribute(context: RelevantContext.date(from: w.start, to: w.end))
        }
        return WidgetRelevance(attributes)
    }
}

extension NextUpProvider {
    /// 下一場：每場開始前 60 分鐘到結束（iPhone 關掉「智慧型堆疊卡」＝不排）
    func relevance() async -> WidgetRelevance<Void> {
        let package = WidgetSnapshotStore.read(WatchPackage.self)
        return WatchRelevanceClues.relevance(WatchRelevancePlan.nextUpWindows(package: package, now: Date()))
    }
}

extension SpentProvider {
    /// 已花：平日 11:30–13:30、17:30–19:30（「錢」沒送、「智慧型堆疊卡」關掉＝不排）
    func relevance() async -> WidgetRelevance<Void> {
        let package = WidgetSnapshotStore.read(WatchPackage.self)
        return WatchRelevanceClues.relevance(WatchRelevancePlan.spentWindows(package: package, now: Date()))
    }
}

extension RunWeekProvider {
    /// 這週跑步：平常跑步的時段（同「平常跑步的時間」卡：週日離目標 3 公里以內才排、今天那個時段跑過不排）
    func relevance() async -> WidgetRelevance<Void> {
        let now = Date()
        let source = RelevanceCardSource.read(now: now)
        return WatchRelevanceClues.relevance(source.runWindows(now: now))
    }
}

/// 堆疊卡、「這週跑步」要的東西讀一次（手錶 App Group：包、手錶自己記的那幾趟、上一次用的運動、按過〔到了〕的站）。
/// 手錶才有的型別（WatchRunText、WatchRunLog、WatchCheckInLog、WatchSport）在這裡換成 WatchRelevancePlan 吃的數字與編號
struct RelevanceCardSource {
    var package: WatchPackage?
    /// 「平常跑步的時間」卡的數字（③ 跑步同一套 WatchRunText.home）；包裡沒有這週跑步是 nil（不浮）
    var numbers: WatchRunNumbers?
    /// 主角運動這週每一趟的開始時間（手錶自己記的＋iPhone 帶進來的；「今天這個時段跑過了沒」）
    var runStarts: [Date]
    /// 手錶上按過〔到了〕、iPhone 還沒寫回包裡的站（旅途下一站不再浮）
    var arrived: Set<UUID>

    static func read(now: Date) -> RelevanceCardSource {
        let package = WidgetSnapshotStore.read(WatchPackage.self)
        let own = WatchRunLog.all()
        let home = WatchRunText.home(package: package, own: own, now: now, lastSport: WatchRunPrefs.lastSport)
        var numbers: WatchRunNumbers? = nil
        if package?.runWeek != nil {
            numbers = WatchRunNumbers(icon: home.sport.icon, tint: home.sport.tint, km: home.km, goalKm: home.goalKm,
                                      runs: home.runs, streakWeeks: home.streakWeeks, daysLeft: home.daysLeft)
        }
        let hero = home.sport.rawValue
        var starts: [Date] = own.filter { $0.sport == hero }.map { $0.start }
        for r in package?.runWeek?.recent ?? [] where r.sport == hero {
            starts.append(r.start)
        }
        var arrived = Set<UUID>()
        for item in WatchCheckInLog.all() where item.checkIn.arrival != nil {
            arrived.insert(item.checkIn.stopId)
        }
        return RelevanceCardSource(package: package, numbers: numbers, runStarts: starts, arrived: arrived)
    }

    /// 這一種卡現在該請系統排的那幾張
    func cards(_ kind: WatchRelevanceKind, now: Date) -> [WatchRelevanceCard] {
        WatchRelevancePlan.liveCards(kind: kind, package: package, run: numbers, runStarts: runStarts,
                                     arrivedStopIds: arrived, now: now, forLookup: false)
    }

    /// 拿 id 找回那一張；找不到（包換了、那一場被刪了）畫「打開 iPhone 上的 LifeGood 一次」
    func card(_ kind: WatchRelevanceKind, id: String, now: Date) -> WatchRelevanceCard {
        WatchRelevancePlan.card(kind: kind, id: id, package: package, run: numbers, now: now)
            ?? WatchRelevancePlan.fallbackCard(kind)
    }

    /// 「這週跑步」自己往上排的時段（＝「平常跑步的時間」那幾張卡的時間）
    func runWindows(now: Date) -> [WatchRelevanceWindow] {
        WatchRelevancePlan.runWeekWindows(package: package, run: numbers, runStarts: runStarts, now: now)
    }
}

// MARK: - 2. 五張卡（watchOS 26）

/// 系統拿這個認「是哪一張卡」：只有卡的 id（WatchRelevanceCard.id）。不是給人設定的，不寫 perform
///（照 iPhone WidgetConfigs.swift 的寫法：static title／description＋@Parameter）
struct RelevanceCardIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "LifeGood 堆疊卡"
    static var description = IntentDescription("智慧型堆疊自己浮上來的 LifeGood 卡")

    @Parameter(title: "卡")
    var cardId: String?

    init() {}

    init(cardId: String) {
        self.cardId = cardId
    }
}

/// 一張卡要畫的東西（provider 算好；View 不讀檔）
@available(watchOS 26, *)
struct RelevanceCardEntry: RelevanceEntry {
    let card: WatchRelevanceCard
}

/// 五種卡共用一個 provider（kind 決定是哪一種）
@available(watchOS 26, *)
struct RelevanceCardProvider: RelevanceEntriesProvider {
    let kind: WatchRelevanceKind

    /// 這一種卡現在該浮的那幾段：一張卡一段（RelevantContext.date(interval:kind:)；會議、卡費、旅途下一站 .scheduled，
    /// 早安、平常跑步 .informational）
    func relevance() async -> WidgetRelevance<RelevanceCardIntent> {
        let now = Date()
        let cards = RelevanceCardSource.read(now: now).cards(kind, now: now)
        let hint: RelevantContext.DateKind = kind.isScheduled ? .scheduled : .informational
        let attributes: [WidgetRelevanceAttribute<RelevanceCardIntent>] = cards.map { c in
            WidgetRelevanceAttribute(configuration: RelevanceCardIntent(cardId: c.id),
                                     context: RelevantContext.date(interval: DateInterval(start: c.start, end: c.end),
                                                                   kind: hint))
        }
        return WidgetRelevance(attributes)
    }

    func entry(configuration: RelevanceCardIntent, context: Context) async throws -> RelevanceCardEntry {
        if context.isPreview {
            return RelevanceCardEntry(card: WatchRelevancePlan.fallbackCard(kind))
        }
        let now = Date()
        let id = configuration.cardId ?? ""
        return RelevanceCardEntry(card: RelevanceCardSource.read(now: now).card(kind, id: id, now: now))
    }

    func placeholder(context: Context) -> RelevanceCardEntry {
        RelevanceCardEntry(card: WatchRelevancePlan.fallbackCard(kind))
    }
}

/// 早安：06:30 到今天第一件開始（最晚 09:00）
@available(watchOS 26, *)
struct MorningCardWidget: Widget {
    var body: some WidgetConfiguration {
        RelevanceConfiguration(kind: WatchWidgetKind.cardMorning,
                               provider: RelevanceCardProvider(kind: .morning)) { entry in
            RelevanceCardView(card: entry.card)
        }
        .configurationDisplayName("早安")
        .description("早上浮上來：今天幾件、家人生日、卡費")
    }
}

/// 快開會了：每一場開始前 20 分鐘到開始後 10 分鐘（可以替掉你自己放的「下一場」）
@available(watchOS 26, *)
struct MeetingCardWidget: Widget {
    var body: some WidgetConfiguration {
        RelevanceConfiguration(kind: WatchWidgetKind.cardMeeting,
                               provider: RelevanceCardProvider(kind: .meeting)) { entry in
            RelevanceCardView(card: entry.card)
        }
        .configurationDisplayName("快開會了")
        .description("開會前浮上來；不寫部屬名字")
        .associatedKind(WatchWidgetKind.nextUp)
    }
}

/// 卡費快到了：自己繳的卡費截止前 3 天起，每天 09:00–21:00
@available(watchOS 26, *)
struct CardBillCardWidget: Widget {
    var body: some WidgetConfiguration {
        RelevanceConfiguration(kind: WatchWidgetKind.cardBill,
                               provider: RelevanceCardProvider(kind: .cardBill)) { entry in
            RelevanceCardView(card: entry.card)
        }
        .configurationDisplayName("卡費快到了")
        .description("自己繳的卡費截止前浮上來；只寫「卡費」和日期")
    }
}

/// 平常跑步的時間：近 4 週同一時段跑過 3 次以上（可以替掉你自己放的「這週跑步」）
@available(watchOS 26, *)
struct UsualRunCardWidget: Widget {
    var body: some WidgetConfiguration {
        RelevanceConfiguration(kind: WatchWidgetKind.cardRun,
                               provider: RelevanceCardProvider(kind: .usualRun)) { entry in
            RelevanceCardView(card: entry.card)
        }
        .configurationDisplayName("平常跑步的時間")
        .description("平常跑步的時段浮上來：這週幾公里、還差多少")
        .associatedKind(WatchWidgetKind.runWeek)
    }
}

/// 旅途下一站：每一站前 30 分鐘到抵達（可以替掉你自己放的「下一場」）；不放天氣
@available(watchOS 26, *)
struct TripStopCardWidget: Widget {
    var body: some WidgetConfiguration {
        RelevanceConfiguration(kind: WatchWidgetKind.cardTrip,
                               provider: RelevanceCardProvider(kind: .tripStop)) { entry in
            RelevanceCardView(card: entry.card)
        }
        .configurationDisplayName("旅途下一站")
        .description("旅途中每一站快到時浮上來")
        .associatedKind(WatchWidgetKind.nextUp)
    }
}

// MARK: - G2 填（下面這個 View 的名字與參數不准改；不准加 @available、不准讀檔、不准 import 別的）

//
// [G2] 卡的三行：字全部是 card.lines／card.privateLines（iPhone 或 WatchRelevancePlan 組好的），這裡只排版、不拼字。
//   • 遮不遮：WatchPrivacyRule.hidesPersonal(dimmed: isLuminanceReduced, redacted: redactionReasons.contains(.privacy))
//     → WatchRelevancePlan.shownLines(card, hidesNames:)（會議名、站名、旅行名抬手才寫）
//   • 一行：圖示（icon、tint；沒有 tint 跟字同色）＋ lead（tone 的顏色）＋ text；沒有 lead 時 tone 上在整行
//     tone："amber"＝WatchPalette.amber、"blue"＝WatchPalette.countdown、"dim"＝.secondary、nil＝第一行 primary／其他 primary 0.9
//   • 第一行 16 semibold rounded、其他 15 medium rounded；每行 1 行、可縮到 0.7；三行左對齊、spacing 1
//   • 點了開 card.link（widgetURL）；最外層 .containerBackground(for: .widget) { WatchWidgetStyle.sky }（不整片紅綠）
//   • 41mm（堆疊卡約 162 點寬）也要放得下：字不夠寬靠 minimumScaleFactor，不換行

/// 一張堆疊卡（G2）：三行左對齊。字只拿 lines（WatchRelevancePlan.shownLines 選好的那一份）：不讀包、不讀設定、不拼字。
/// 最外層只有點了開哪裡（widgetURL）與夜空底（containerBackground）；手腕放下不另外換字、不另外調暗（系統會），版面不跳
struct RelevanceCardView: View {
    let card: WatchRelevanceCard

    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.redactionReasons) private var reasons

    private var lines: [WatchCardLine] {
        WatchRelevancePlan.shownLines(card, hidesNames: WatchPrivacyRule.hidesPersonal(dimmed: dimmed,
                                                                                       redacted: reasons.contains(.privacy)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(lines.enumerated()), id: \.offset) { pair in
                RelevanceCardLineView(line: pair.element, isFirst: pair.offset == 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: card.link))
        .containerBackground(for: .widget) {
            WatchWidgetStyle.sky
        }
    }
}

/// 卡的一行：圖示（有 tint 用 tint，沒有跟字同色）＋開頭上色那一段（lead，tone 的顏色）＋其餘的字。
/// 第一行 16 semibold rounded、其他 15 medium rounded；一行、放不下縮到 0.7（41mm 約 162 點寬也不換行）
private struct RelevanceCardLineView: View {
    let line: WatchCardLine
    let isFirst: Bool

    var body: some View {
        HStack(spacing: 4) {
            iconView
            textView
        }
    }

    /// 「☀︎」「💳」「🏃」…；沒有 icon 不畫（HStack 不留空位）
    @ViewBuilder
    private var iconView: some View {
        if let symbol = line.icon {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(iconColor)
                .widgetAccentable()
        }
    }

    private var textView: some View {
        lineText
            .font(lineFont)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// 有 lead：「3 天後」（tone 色）＋「・要自己繳」（一般色）；沒有 lead：tone 上在整行（tone 是 nil＝一般色）
    private var lineText: Text {
        guard let lead = line.lead else {
            let whole: Text = Text(line.text).foregroundStyle(toneColor)
            return whole
        }
        let head: Text = Text(lead).foregroundStyle(toneColor)
        let rest: Text = Text(line.text).foregroundStyle(baseColor)
        return head + rest
    }

    private var lineFont: Font {
        if isFirst {
            return Font.system(size: 16, weight: .semibold, design: .rounded)
        }
        return Font.system(size: 15, weight: .medium, design: .rounded)
    }

    private var iconSize: CGFloat {
        isFirst ? 12 : 11
    }

    private var iconColor: Color {
        if let hex = line.tint {
            return WatchWidgetStyle.color(hex)
        }
        return toneColor
    }

    /// tone："amber" 琥珀、"blue" 倒數藍、"dim" 灰；nil 或其他＝一般色
    private var toneColor: Color {
        switch line.tone ?? "" {
        case WatchRelevancePlan.toneAmber:
            return WatchWidgetStyle.color(WatchPalette.amber)
        case WatchRelevancePlan.toneBlue:
            return WatchWidgetStyle.countdown
        case WatchRelevancePlan.toneDim:
            return Color.secondary
        default:
            return baseColor
        }
    }

    /// 第一行 primary、其他 primary 0.9
    private var baseColor: Color {
        isFirst ? Color.primary : Color.primary.opacity(0.9)
    }
}
