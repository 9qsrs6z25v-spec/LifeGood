import SwiftUI
import WidgetKit
import AppIntents

// MARK: - 還能花（v25.545，只屬於 LifeGoodWidgets）
//
// systemSmall；StandBy 用同一個。只讀 money_v1.json（WidgetMoneySnapshot），
// 照快照裡 App 組好的字畫，不做任何金額計算與格式化。
// 點整塊 → WidgetLink.expenseOverview（收支總覽）。
//
// 規格見 scratchpad/widgets/v1/brief.md 的 G2。
//
// 換日：App 寫快照時已經把「今天到月底每一天」的字各準備一份，這裡只依 entry.date 挑那一天
//（WidgetMoneySnapshot.day(at:)）。timeline 在每一天的 00:00 各放一筆 entry，所以沒開 App
// 也會自己換到下一天那一份；過了快照最後一天（跨月）改顯示「11 月開始了」。
//
// StandBy 照樣顯示金額（使用者第 2 題），所以這裡**不加** .privacySensitive()。
//
// [v2] 隱藏金額：provider 讀一次 WidgetHideAmounts.isOn 放進 entry（hidesAmounts），
//      字一律經過 WidgetMoneyDay.lines(hidden:) 拿（開著時「本月已花／62%／還有 19 天／今天 3 筆」）。
//      MoneyLeftTimeline 給記帳台、一按就記、鎖定畫面「已花」共用；MoneyLeftBar 給 WidgetMoneyPanel 共用。
//
// [v3] 長按可設定（AppIntentConfiguration＋MoneyLeftConfigIntent，WidgetConfigs.swift；kind 不變）：
//      金額「跟著總開關（預設）／這個小工具一律隱藏」→ provider 算 hidesAmounts＝config.amount.hides(master:)。
//      右上加一顆「⊕」（MoneyLeftAddButton）：Button(intent: LifeGoodOpenIntent(新增支出網址))，
//      打開 App 到新增支出、數字鍵盤跳出（跟控制項「記一筆」同一條路）。StandBy 不放（不能按）。
//      ⊕ 以外的地方照舊整塊 → 收支總覽。月牙／雲從右上改到大字那一列旁（右上被 ⊕ 佔了，J:56）。
//
// 型別（全部 internal 的都帶 MoneyLeft 前綴；畫面零件 private）：
//   MoneyLeftWidget、MoneyLeftEntry、MoneyLeftProvider、MoneyLeftTimeline、
//   MoneyLeftModel、MoneyLeftSample、MoneyLeftEntryView、MoneyLeftBar
//   [v3] 設定在 WidgetConfigs.swift 的 MoneyLeftConfigIntent；⊕ 是本檔 private 的 MoneyLeftAddButton

// MARK: - Widget

struct MoneyLeftWidget: Widget {
    var body: some WidgetConfiguration {
        // [v3] StaticConfiguration → AppIntentConfiguration（kind 不變：已經放好的升級後用預設值、外觀一樣）
        AppIntentConfiguration(kind: WidgetKind.moneyLeft, intent: MoneyLeftConfigIntent.self,
                               provider: MoneyLeftProvider()) { entry in
            MoneyLeftEntryView(entry: entry)
        }
        .configurationDisplayName("還能花")
        .description("這個月還能花多少、每天還能花多少")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Timeline

struct MoneyLeftEntry: TimelineEntry {
    /// 畫面一律拿這個當「現在」（不在 View 裡呼叫 Date()）
    let date: Date
    /// nil＝還沒打開過新版 App（或檔案讀不到）
    let snapshot: WidgetMoneySnapshot?
    /// [v2] 「隱藏金額」開著（provider 讀一次；View 裡不讀 UserDefaults）。
    /// [v3] ＝長按設定的「金額」.hides(master: 總開關)：一律隱藏、或總開關開著
    let hidesAmounts: Bool
}

/// [v3] TimelineProvider → AppIntentTimelineProvider（多讀長按設定；排程照舊）
struct MoneyLeftProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MoneyLeftEntry {
        let now = Date()
        return MoneyLeftEntry(date: now, snapshot: MoneyLeftSample.snapshot(at: now), hidesAmounts: false)
    }

    func snapshot(for configuration: MoneyLeftConfigIntent, in context: Context) async -> MoneyLeftEntry {
        let now = Date()
        if context.isPreview {
            // 小工具庫裡的預覽：寫死的展示字
            return MoneyLeftEntry(date: now, snapshot: MoneyLeftSample.snapshot(at: now), hidesAmounts: false)
        }
        let snapshot = WidgetSnapshotStore.read(WidgetMoneySnapshot.self)
        let hidden: Bool = configuration.amount.hides(master: WidgetHideAmounts.isOn)
        return MoneyLeftEntry(date: now, snapshot: snapshot, hidesAmounts: hidden)
    }

    func timeline(for configuration: MoneyLeftConfigIntent, in context: Context) async -> Timeline<MoneyLeftEntry> {
        let now = Date()
        let snapshot = WidgetSnapshotStore.read(WidgetMoneySnapshot.self)
        let hidden: Bool = configuration.amount.hides(master: WidgetHideAmounts.isOn)
        let dates = MoneyLeftTimeline.entryDates(snapshot: snapshot, now: now)
        let entries: [MoneyLeftEntry] = dates.map {
            MoneyLeftEntry(date: $0, snapshot: snapshot, hidesAmounts: hidden)
        }
        // 平常不用定時要：App 存檔／iCloud 同步後寫了新快照才叫重畫（WidgetSnapshotWriter）。
        // 只在排到的最後一個 00:00（跨月後 daysAfterEnd 天）過了以後再要一次，日期那一行才不會停住
        let policy = MoneyLeftTimeline.policy(snapshot: snapshot, dates: dates, now: now)
        return Timeline(entries: entries, policy: policy)
    }
}

/// 「還能花」哪些時間點要換畫面（brief §6）
enum MoneyLeftTimeline {
    /// [情境驗證補] 跨月以後 App 還沒打開時，往後再排幾個 00:00。
    /// 「11 月開始了」上面那一行日期是 entry.date 組的：不排的話 timeline 停在跨月那一刻，
    /// 11/3 還寫「11/1 週日」（12 月了也還寫「11 月開始了」）。
    static let daysAfterEnd = 31

    /// now；每一天的 00:00；最後一天結束（跨月那一刻）與之後每天的 00:00；快照變舊的那一刻。
    /// 沒快照只有 now。
    static func entryDates(snapshot: WidgetMoneySnapshot?, now: Date) -> [Date] {
        guard let snap = snapshot else { return [now] }
        var dates: Set<Date> = [now]
        for day in snap.days where day.dayStart > now {
            dates.insert(day.dayStart)
        }
        for midnight in midnightsAfterEnd(snapshot: snap, now: now) {
            dates.insert(midnight)
        }
        // isStale 是「超過」兩天（>），多 1 秒才會翻過去
        let stale = snap.generatedAt.addingTimeInterval(WidgetFreshness.moneyStaleAfter + 1)
        if stale > now {
            dates.insert(stale)
        }
        return dates.sorted()
    }

    /// 快照最後一天結束（跨月那一刻）起、之後每天的 00:00，都比 now 晚，共 daysAfterEnd 個。
    /// 已經跨月了（now 比最後一天還晚）就從明天 00:00 排起。只排日期，不算錢。
    static func midnightsAfterEnd(snapshot snap: WidgetMoneySnapshot, now: Date) -> [Date] {
        guard let last = snap.days.last else { return [] }
        let cal = Calendar.current
        var midnight: Date = last.dayEnd
        if midnight <= now {
            let today = cal.startOfDay(for: now)
            guard let tomorrow = cal.date(byAdding: .day, value: 1, to: today) else { return [] }
            midnight = tomorrow
        }
        var out: [Date] = []
        for _ in 0..<daysAfterEnd {
            out.append(midnight)
            guard let next = cal.date(byAdding: .day, value: 1, to: midnight) else { break }
            midnight = next
        }
        return out
    }

    /// 沒快照：.never（App 第一次寫完會叫重畫）。有快照：最後一筆 entry 過了再要一次
    ///（最後一筆是跨月後第 daysAfterEnd 個 00:00，一個多月才一次，額度可以忽略）。
    static func policy(snapshot: WidgetMoneySnapshot?, dates: [Date], now: Date) -> TimelineReloadPolicy {
        guard snapshot != nil, let last = dates.last, last > now else { return .never }
        return .after(last)
    }
}

// MARK: - 畫面要的字（全部在這裡挑好，body 只讀）

struct MoneyLeftModel {
    enum Kind {
        /// 一句話（沒快照）
        case message
        /// 某一天（正常／超支／沒收入）
        case day
        /// 跨月了、App 還沒打開
        case monthStarted
    }

    var kind: Kind = .message
    var message = ""
    var dateText = ""
    var title = ""
    var hero = ""
    var line = ""
    var footer = ""
    var isOver = false
    var bar: WidgetMoneyBar? = nil

    /// 只挑字、不算錢：每個字都是快照裡 App 組好的，或 WidgetDateText 的日期字。
    /// [v2] hidden＝隱藏金額開著：四行改用 App 寫好的隱藏版（WidgetMoneyDay.lines(hidden:)）
    static func make(snapshot: WidgetMoneySnapshot?, now: Date, hidden: Bool) -> MoneyLeftModel {
        var model = MoneyLeftModel()
        guard let snap = snapshot else {
            // 不顯示 NT$0（會以為這個月一毛都沒花，J:62）
            model.message = "打開 LifeGood 一次，這裡就會出現本月還能花"
            return model
        }
        guard !snap.hasEnded(at: now), let day = snap.day(at: now) else {
            model.kind = .monthStarted
            model.dateText = WidgetDateText.dayLabel(now)
            model.title = WidgetDateText.monthStarted(now)
            model.line = "打開 LifeGood 算這個月還能花"
            model.footer = WidgetDateText.lastUpdated(snap.generatedAt)
            return model
        }
        let lines = day.lines(hidden: hidden)
        model.kind = .day
        model.dateText = day.dateText
        model.title = lines.title
        model.hero = lines.hero
        model.line = lines.line
        model.isOver = day.isOver
        model.bar = day.bar
        // 超過兩天沒更新：最下面一行老實說是舊的（J:63）
        model.footer = snap.isStale(at: now) ? WidgetDateText.lastUpdated(snap.generatedAt) : lines.footer
        return model
    }
}

/// 小工具庫預覽與 placeholder 用的樣本。**這些是寫死的展示字，不是計算**（J:92 那一列）。
enum MoneyLeftSample {
    static func snapshot(at now: Date) -> WidgetMoneySnapshot {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 3600)
        let bar = WidgetMoneyBar(fixed: 0.47, variable: 0.15, income: 1.0)
        let day = WidgetMoneyDay(dayKey: WidgetDateText.dayKey(start),
                                 dayStart: start,
                                 dayEnd: end,
                                 dateText: "10/13 週二",
                                 state: .normal,
                                 title: "本月還能花",
                                 hero: "NT$4.6萬",
                                 line: "每天 NT$2,402",
                                 footer: "已花 62%・還有 19 天",
                                 spentRatio: 0.62,
                                 remainingDays: 19,
                                 bar: bar)
        return WidgetMoneySnapshot(generatedAt: now,
                                   dataDay: WidgetDateText.dayKey(start),
                                   month: cal.component(.month, from: start),
                                   days: [day])
    }
}

// MARK: - 畫面

struct MoneyLeftEntryView: View {
    let entry: MoneyLeftEntry

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    private var surface: WidgetPalette.Surface {
        WidgetPalette.Surface(renderingMode: renderingMode, showsBackground: showsBackground)
    }

    private var palette: WidgetPalette {
        WidgetPalette(colorScheme, mono: surface.isMono)
    }

    private var model: MoneyLeftModel {
        MoneyLeftModel.make(snapshot: entry.snapshot, now: entry.date, hidden: entry.hidesAmounts)
    }

    var body: some View {
        MoneyLeftContent(model: model, palette: palette, standBy: surface.isStandBy)
            .overlay(alignment: .topTrailing) {
                addButton
            }
            .containerBackground(for: .widget) {
                backgroundView
            }
            .widgetURL(WidgetLink.expenseOverview)
    }

    /// [v3] 右上「⊕」：StandBy 不放（不能按）；主畫面全彩、著色都放
    @ViewBuilder
    private var addButton: some View {
        if !surface.isStandBy {
            MoneyLeftAddButton(palette: palette)
        }
    }

    /// 著色、StandBy 不畫天空（J:59、114）。
    /// [v3] 右上是「⊕」；放大字旁會壓到「NT$4.6萬」的最後一個字（大字會撐滿整寬），
    /// 四個角又分別是日期、⊕、橫條與最下面那行——這格不放月牙／雲，只留漸層與星星
    @ViewBuilder
    private var backgroundView: some View {
        if surface.drawsSky {
            WidgetSky(palette: palette, moon: .none)
        } else {
            Color.clear
        }
    }
}

/// [v3] 右上「⊕」：打開 App 到新增支出、數字鍵盤跳出（J:106）。
/// 小型只能整塊一個網址，所以用「打開 App 的按鈕動作」：共用檔的 LifeGoodOpenIntent（openAppWhenRun，
/// 兩個 target 都有）把網址交給 App 的總入口（WidgetOpenAppHandoff → WidgetLink.apply），跟控制項「記一筆」同一條路。
/// 全彩 App 藍（palette.deskAddIcon，深色 #5B9BFF）；著色模式白色＋重點色。
private struct MoneyLeftAddButton: View {
    let palette: WidgetPalette

    var body: some View {
        Button(intent: LifeGoodOpenIntent(url: WidgetLink.addExpense())) {
            MoneyLeftAddIcon(palette: palette)
        }
        .buttonStyle(.plain)
    }
}

/// ⊕ 的圖示（約 22pt；外面多留一點點按得到的範圍，靠右上對齊不往內佔版面）
private struct MoneyLeftAddIcon: View {
    let palette: WidgetPalette

    var body: some View {
        Image(systemName: "plus.circle.fill")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(palette.deskAddIcon)
            .widgetAccentable()
            .frame(width: 30, height: 30, alignment: .topTrailing)
            .contentShape(Rectangle())
    }
}

/// 依狀態挑版面
private struct MoneyLeftContent: View {
    let model: MoneyLeftModel
    let palette: WidgetPalette
    let standBy: Bool

    var body: some View {
        switch model.kind {
        case .message:
            MoneyLeftMessage(text: model.message, palette: palette)
        case .monthStarted:
            MoneyLeftMonthStarted(model: model, palette: palette)
        case .day:
            if standBy {
                MoneyLeftStandBy(model: model, palette: palette)
            } else {
                MoneyLeftDay(model: model, palette: palette)
            }
        }
    }
}

/// 超支時小標、大字、第二行用紅色（J:93）；著色模式靠「已超支」三個字
private struct MoneyLeftTone {
    let model: MoneyLeftModel
    let palette: WidgetPalette

    var title: Color { model.isOver ? palette.bad : palette.label }
    var hero: Color { model.isOver ? palette.bad : palette.ink }
    var line: Color { model.isOver ? palette.bad : palette.inkSoft }
}

/// 最大的字（著色模式染重點色）
private struct MoneyLeftHero: View {
    let text: String
    let color: Color
    let size: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .widgetAccentable()
    }
}

/// 正常／超支／沒收入：日期、小標、大字、第二行、橫條、最下面一行。
/// 放不下（小螢幕＋「記一筆收入，才算得出還能花」兩行）時先拿掉橫條，字都保留。
private struct MoneyLeftDay: View {
    let model: MoneyLeftModel
    let palette: WidgetPalette

    private var tone: MoneyLeftTone { MoneyLeftTone(model: model, palette: palette) }

    var body: some View {
        ViewThatFits(in: .vertical) {
            column(showsBar: true)
            column(showsBar: false)
        }
    }

    private func column(showsBar: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.dateText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.inkDate)
            Text(model.title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(tone.title)
                .padding(.top, 1)
            MoneyLeftHero(text: model.hero, color: tone.hero, size: 32)
            lineText
            Spacer(minLength: 4)
            barView(showsBar: showsBar)
            footerText
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 「每天 NT$2,402」；沒收入時「記一筆收入，才算得出還能花」比較長，給兩行
    private var lineText: some View {
        Text(model.line)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tone.line)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
    }

    @ViewBuilder
    private func barView(showsBar: Bool) -> some View {
        if showsBar, let bar = model.bar {
            MoneyLeftBar(bar: bar, palette: palette)
                .frame(height: 10)
        }
    }

    private var footerText: some View {
        Text(model.footer)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(palette.label)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.top, 5)
    }
}

/// StandBy：只留小標、大字、第二行，字放大；照樣顯示金額（使用者第 2 題）
private struct MoneyLeftStandBy: View {
    let model: MoneyLeftModel
    let palette: WidgetPalette

    private var tone: MoneyLeftTone { MoneyLeftTone(model: model, palette: palette) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tone.title)
                .lineLimit(1)
            MoneyLeftHero(text: model.hero, color: tone.hero, size: 40)
            Text(model.line)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tone.line)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// 跨月了、App 還沒打開（v1 老實請使用者打開 App，J:96）
private struct MoneyLeftMonthStarted: View {
    let model: MoneyLeftModel
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.dateText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.inkDate)
            Text(model.title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(palette.ink)
                .padding(.top, 4)
                .widgetAccentable()
            Text(model.line)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.inkSoft)
                .lineLimit(3)
                .padding(.top, 6)
            Spacer(minLength: 4)
            Text(model.footer)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.label)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 還沒打開過新版 App：只寫一句話，不顯示 NT$0
private struct MoneyLeftMessage: View {
    let text: String
    let palette: WidgetPalette

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "creditcard")
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

// MARK: - 這個月的錢（橫條）

/// 跟總覽「這個月的錢」同一條縮短：紫＝固定（0 → fixed）、藍＝變動（接在後面）、
/// 一道直線＝收入基準；超過收入的那一截疊紅。不畫斜線預估（J:99）。
/// 比例 App 已經夾好（0…1），這裡只把比例換成寬度，不算錢。
/// [v2] internal：記帳台、一按就記（中）左半的 WidgetMoneyPanel 也畫這一條
struct MoneyLeftBar: View {
    let bar: WidgetMoneyBar
    let palette: WidgetPalette

    private let trackHeight: CGFloat = 6

    /// [v2] 明寫 internal init：別的檔（WidgetMoneyPanel）要建它，不靠合成的 memberwise init
    ///（有 private 存儲屬性時，合成 init 的可見度不想去賭）
    init(bar: WidgetMoneyBar, palette: WidgetPalette) {
        self.bar = bar
        self.palette = palette
    }

    var body: some View {
        GeometryReader { geo in
            layers(width: geo.size.width, height: geo.size.height)
        }
    }

    private func layers(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            fills(width: width)
                .frame(width: width, height: trackHeight)
                .clipShape(Capsule())
            incomeTick(width: width, height: height)
        }
        .frame(width: width, height: height, alignment: .leading)
    }

    private func fills(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(palette.barTrack)
            Rectangle()
                .fill(fixedGradient)
                .frame(width: fixedWidth(width))
                .widgetAccentable()
            Rectangle()
                .fill(variableGradient)
                .frame(width: variableWidth(width))
                .offset(x: fixedWidth(width))
                .widgetAccentable()
            overSegment(width: width)
        }
    }

    private var fixedGradient: LinearGradient {
        LinearGradient(colors: [palette.fixedTop, palette.fixedBottom],
                       startPoint: .leading, endPoint: .trailing)
    }

    private var variableGradient: LinearGradient {
        LinearGradient(colors: [palette.variableTop, palette.variableBottom],
                       startPoint: .leading, endPoint: .trailing)
    }

    /// 超過收入基準的那一截（紅）
    @ViewBuilder
    private func overSegment(width: CGFloat) -> some View {
        if let span = overSpan() {
            Rectangle()
                .fill(palette.bad)
                .frame(width: width * span.length)
                .offset(x: width * span.start)
        }
    }

    /// 收入基準那一道直線（比橫條高一點）
    @ViewBuilder
    private func incomeTick(width: CGFloat, height: CGFloat) -> some View {
        if let income = bar.income {
            Capsule()
                .fill(palette.incomeTick)
                .frame(width: 2, height: height)
                .offset(x: tickX(income: income, width: width))
        }
    }

    // 比例 → 寬度

    private func clamp(_ value: Double) -> CGFloat {
        guard value.isFinite else { return 0 }
        return CGFloat(min(max(value, 0), 1))
    }

    private func fixedWidth(_ width: CGFloat) -> CGFloat {
        width * clamp(bar.fixed)
    }

    private func variableWidth(_ width: CGFloat) -> CGFloat {
        let room: CGFloat = 1 - clamp(bar.fixed)
        let part: CGFloat = min(clamp(bar.variable), room)
        return width * part
    }

    /// (起點, 長度)，都是 0…1；沒超過收入是 nil
    private func overSpan() -> (start: CGFloat, length: CGFloat)? {
        guard let income = bar.income else { return nil }
        let line: CGFloat = clamp(income)
        let fixed: CGFloat = clamp(bar.fixed)
        let used: CGFloat = min(fixed + min(clamp(bar.variable), 1 - fixed), 1)
        guard used > line else { return nil }
        return (start: line, length: used - line)
    }

    private func tickX(income: Double, width: CGFloat) -> CGFloat {
        let x: CGFloat = width * clamp(income) - 1
        let maxX: CGFloat = max(width - 2, 0)
        return min(max(x, 0), maxX)
    }
}
