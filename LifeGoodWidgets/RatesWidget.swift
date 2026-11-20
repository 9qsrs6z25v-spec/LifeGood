import SwiftUI
import WidgetKit
import AppIntents

// MARK: - 金價匯率（小＋鎖定畫面三型）（小工具 v4）
//
// 只屬於「LifeGoodWidgets」target。由 G2 實作，規格見 scratchpad/widgets/v4/brief.md 的 G2-4。
// （主控建好的空檔，已登記 pbxproj：A01A000002000085／A01B000002000085）
//
// 讀 finance_v1.json 的 rates（設定「自訂幣別匯率」裡 App 認得的幣別、App 上次自動更新的時間；沒快照也照樣有兩種黃金），
// 自己上網抓（WidgetQuoteStore.refreshRates → 契約的 WidgetQuoteService.fetchRates → FXRateService.fetchDayQuotes：
// 黃金＝GC=F × TWD=X ÷ 31.1034768 × 克數，跟 App 的自動更新同一個算式），寫 quotes_v1.json。
// 字一律拿 WidgetRateChoice.figures(quote:appUpdatedAt:now:)（契約：選價、漲跌、「幾點的價」、「期貨換算」），
// **這個檔不算錢、不拼「NT$」**。抓不到用 App 自訂幣別匯率裡的值、寫「10/13 08:12 的價」，不寫漲跌。
//
// • 小：「黃金 每克／NT$4,243／▼72（-1.7%）比昨天／美金 32.13／期貨換算・10:42 ↻」。紅漲綠跌、▲▼ 在字裡。
//   ↻＝RefreshQuotesIntent（在小工具裡跑，不開 App）；StandBy 不放。
// • 鎖定畫面（同一個 kind；公開牌價，可以放數字）：圓「金/克／4,243」、長方形「黃金 每克 NT$4,243 ▼1.7%／美金 32.13／10:42」、
//   一行「黃金 每克 4,243・美金 32.13」。系統單色、不放 ↻。
// • 公開牌價不是你的錢：**不受「隱藏金額」影響、沒有金額設定**（主控定案 5）。
// • 設定：大字（黃金每克〔預設〕／每台錢／自訂幣別裡的）、下面那一行（美金〔預設，有填才有〕／不顯示／其他）。
//   跟大字同一個就不寫第二次。
// • 點了開設定 › 自訂幣別匯率（lifegood://settings/currency，App 會把那一區展開）。
// • 時間軸：now＋（下一個 00:00，比 policy 早才放：「10:42」過了午夜變「10/13 10:42」）；
//   policy＝WidgetQuoteSchedule.nextRatesRefresh（07:00–24:00 每 60 分，半夜跳到 07:00）。
//   上網只在 timeline 與 ↻；placeholder、預覽用寫死的樣本字，snapshot 只讀檔。
//
// 型別（internal 的都帶 RatesWidget 前綴或是 brief 指定的名字；畫面零件 private）：
//   RatesWidget、RatesConfigIntent、RatesWidgetEntry、RatesWidgetProvider、RatesWidgetPick、RatesWidgetModel、
//   RatesWidgetSample、RatesWidgetEntryView

// MARK: - Widget

struct RatesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.rates, intent: RatesConfigIntent.self,
                               provider: RatesWidgetProvider()) { entry in
            RatesWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("金價匯率")
        .description("黃金每克、美金現在多少")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - 長按設定

/// 「金價匯率」：大字、下面那一行。沒有金額設定（公開牌價）。
/// 大字 nil＝黃金每克；下面那一行 nil＝美金（自訂幣別匯率裡有填才有），選「不顯示」＝不寫
struct RatesConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "金價匯率"
    static var description = IntentDescription("選大字與下面那一行")

    @Parameter(title: "大字")
    var main: WidgetRateEntity?

    @Parameter(title: "下面那一行")
    var second: WidgetRateLineEntity?

    init() {}
}

// MARK: - Timeline

struct RatesWidgetEntry: TimelineEntry {
    /// 畫面一律拿這個當「現在」（字已經用它組好放在 model）
    let date: Date
    let model: RatesWidgetModel
}

struct RatesWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> RatesWidgetEntry {
        RatesWidgetEntry(date: Date(), model: RatesWidgetSample.model)
    }

    /// 預覽用樣本；其他時候只讀檔（不上網，要快）
    func snapshot(for configuration: RatesConfigIntent, in context: Context) async -> RatesWidgetEntry {
        let now = Date()
        if context.isPreview {
            return RatesWidgetEntry(date: now, model: RatesWidgetSample.model)
        }
        let pick = RatesWidgetPick.make(configuration: configuration)
        let model = RatesWidgetModel.make(pick: pick, cache: WidgetQuoteStore.read(), now: now)
        return RatesWidgetEntry(date: now, model: model)
    }

    /// 沒快照也照樣抓得到兩種黃金
    func timeline(for configuration: RatesConfigIntent, in context: Context) async -> Timeline<RatesWidgetEntry> {
        let now = Date()
        let pick = RatesWidgetPick.make(configuration: configuration)
        let cache = await WidgetQuoteStore.refreshRates(codes: pick.codes, now: now, force: false)
        let reloadAt: Date = WidgetQuoteSchedule.nextRatesRefresh(after: now)
        let dates: [Date] = WidgetQuoteStore.entryDates(now: now, reloadAt: reloadAt)
        let entries: [RatesWidgetEntry] = dates.map { date in
            RatesWidgetEntry(date: date, model: RatesWidgetModel.make(pick: pick, cache: cache, now: date))
        }
        return Timeline(entries: entries, policy: .after(reloadAt))
    }
}

// MARK: - 選了哪兩個

/// 設定＋finance 快照 → 大字與下面那一行要顯示的（WidgetRateChoice：代碼、名字、App 的值）
struct RatesWidgetPick {
    let main: WidgetRateChoice
    /// nil＝不寫下面那一行
    let second: WidgetRateChoice?
    /// App 最後一次自動更新匯率成功的時間（WidgetRatesBlock.appUpdatedAt）
    let appUpdatedAt: Date?

    /// 要抓的代碼（大字、下面那一行）
    var codes: [String] {
        guard let second else { return [main.code] }
        return [main.code, second.code]
    }

    static func make(configuration: RatesConfigIntent) -> RatesWidgetPick {
        let block: WidgetRatesBlock = WidgetSnapshotStore.read(WidgetFinanceSnapshot.self)?.rates
            ?? WidgetRatesBlock(items: [], appUpdatedAt: nil)
        return make(block: block, mainID: configuration.main?.id, secondID: configuration.second?.id)
    }

    /// 大字：選的（找不到＝黃金每克）；下面那一行：選「不顯示」nil、選了別的照選的（找不到也 nil）、
    /// 沒選＝美金（有填才有）；跟大字同一個就不寫第二次
    static func make(block: WidgetRatesBlock, mainID: String?, secondID: String?) -> RatesWidgetPick {
        let main: WidgetRateChoice = block.choice(code: mainID ?? WidgetRatesBlock.goldGramCode) ?? block.defaultMain
        var second: WidgetRateChoice? = nil
        if let id = secondID {
            if id != WidgetRateLineEntity.offID {
                second = block.choice(code: id)
            }
        } else {
            second = block.defaultSecond
        }
        if second?.code == main.code {
            second = nil
        }
        return RatesWidgetPick(main: main, second: second, appUpdatedAt: block.appUpdatedAt)
    }
}

// MARK: - 畫面要的字

/// 金價匯率要的全部字。provider 用那一筆 entry 的時間組好（WidgetRateChoice.figures），body 只放 Text
struct RatesWidgetModel {
    /// 大字有值（小工具抓到的或 App 的）
    var hasValue = false
    /// 「黃金 每克」「美金」
    var title = ""
    /// 鎖定畫面圓形的小字「金/克」
    var shortTitle = ""
    /// 大字「NT$4,243」「32.13」；沒有「—」
    var valueText = "—"
    /// 圓形、一行字的數字「4,243」；沒有「—」
    var shortValue = "—"
    /// 「▼72（-1.7%）比昨天」「跟昨天差不多」；App 的價 ""；沒有值「還沒抓到黃金 每克」
    var changeText = ""
    /// 1 漲（紅）、-1 跌（綠）、0 平或不知道（灰）
    var direction = 0
    /// 下面那一行「美金 32.13」；沒選 ""；選了但沒有值「日圓 —」。
    /// 跟大字不是同一個來源（一個小工具剛抓、一個用 App 的價；或大字沒有值；或不是同一輪抓的）時後面接它自己的時間：
    ///「日圓 0.21・10/13 08:12 的價」（任何時候都寫是幾點的價）
    var secondLine = ""
    /// 同上不接時間（小型放不下時、一行字用）
    var secondLineShort = ""
    /// 最下面「期貨換算・10:42」（幣別只有時間）
    var footer = ""
    /// 「10:42」「10/13 10:42」「10/13 08:12 的價」「App 的價」
    var timeText = ""
    /// ↻ 要重抓的代碼
    var codes: [String] = []

    // 鎖定畫面

    /// 長方形第一行「黃金 每克 NT$4,243 ▼1.7%」
    var rectLine1 = ""
    /// 長方形第三行：時間；沒有值「還沒抓到」
    var rectLine3 = ""
    /// 一行字「黃金 每克 4,243・美金 32.13」
    var inlineText = ""

    static func make(pick: RatesWidgetPick, cache: WidgetQuoteCache?, now: Date) -> RatesWidgetModel {
        var model = RatesWidgetModel()
        let main: WidgetRateChoice = pick.main
        model.title = main.title
        model.shortTitle = main.shortTitle
        model.codes = pick.codes
        let mainFigures: WidgetRateFigures? = figuresOf(main, pick: pick, cache: cache, now: now)
        let secondFigures: WidgetRateFigures? = pick.second.flatMap { choice in
            figuresOf(choice, pick: pick, cache: cache, now: now)
        }
        let secondShort: String = shortLine(pick.second, figures: secondFigures)
        model.secondLineShort = secondShort
        let apart: Bool = fetchedApart(pick, cache: cache)
        model.secondLine = secondShort + timeSuffix(secondFigures, main: mainFigures, apart: apart)
        guard let f = mainFigures else {
            model.changeText = "還沒抓到" + main.title
            model.rectLine1 = main.title + " —"
            model.rectLine3 = "還沒抓到"
            model.inlineText = joined(main.title + " —", secondShort)
            return model
        }
        model.hasValue = true
        model.valueText = f.valueText
        model.shortValue = f.shortValue
        model.changeText = f.changeText ?? ""
        model.direction = f.direction
        model.timeText = f.timeText
        model.footer = f.sourceText.map { $0 + "・" + f.timeText } ?? f.timeText
        var line1: String = f.title + " " + f.valueText
        if let rate = f.rateText {
            line1 += " " + rate
        }
        model.rectLine1 = line1
        model.rectLine3 = f.timeText
        model.inlineText = joined(f.title + " " + f.shortValue, secondShort)
        return model
    }

    /// 契約的選價＋組字（小工具抓的比 App 新就用小工具的；都沒有 nil）
    private static func figuresOf(_ choice: WidgetRateChoice, pick: RatesWidgetPick, cache: WidgetQuoteCache?,
                                  now: Date) -> WidgetRateFigures? {
        let quote: WidgetRateQuote? = cache?.rates[choice.code]
        return choice.figures(quote: quote, appUpdatedAt: pick.appUpdatedAt, now: now)
    }

    /// 「美金 32.13」「黃金 每克 4,243」（title＋shortValue）；沒選 ""；選了但沒有值「日圓 —」
    private static func shortLine(_ choice: WidgetRateChoice?, figures: WidgetRateFigures?) -> String {
        guard let choice else { return "" }
        guard let f = figures else { return choice.title + " —" }
        return f.title + " " + f.shortValue
    }

    /// 下面那一行跟大字不是同一個來源（大字沒有值、或一個是小工具剛抓的一個是 App 的價）時接「・」＋它自己的時間；
    /// 同一個來源（一起抓到的、或都是 App 那一次）不接（時間只差幾分，最下面一行已經寫了）。
    /// [審查] 兩個都是小工具抓的、可是不是同一輪（apart：這一輪美金沒抓到，留著上一輪的）也接——
    /// 不然「美金 32.13」看起來像最下面那個「10:42」的價
    private static func timeSuffix(_ second: WidgetRateFigures?, main: WidgetRateFigures?, apart: Bool) -> String {
        guard let second, !second.timeText.isEmpty else { return "" }
        guard let main else { return "・" + second.timeText }
        let sameRound: Bool = main.fromApp || !apart
        if main.fromApp == second.fromApp && sameRound { return "" }
        return "・" + second.timeText
    }

    /// [審查] 快取裡大字與下面那一行抓的時間差超過 WidgetQuoteSchedule.freshFor（不是同一輪抓到的）。
    /// 同一輪抓的 fetchedAt 一模一樣；別的金價匯率小工具剛抓過其中一個，也只差幾分鐘
    private static func fetchedApart(_ pick: RatesWidgetPick, cache: WidgetQuoteCache?) -> Bool {
        guard let second = pick.second,
              let mainAt = cache?.rates[pick.main.code]?.fetchedAt,
              let secondAt = cache?.rates[second.code]?.fetchedAt else { return false }
        return abs(mainAt.timeIntervalSince(secondAt)) > WidgetQuoteSchedule.freshFor
    }

    /// 一行字：「黃金 每克 4,243」＋「・美金 32.13」（第二段空的不接）
    private static func joined(_ first: String, _ second: String) -> String {
        second.isEmpty ? first : first + "・" + second
    }
}

/// 小工具庫預覽與 placeholder 的樣本。**這些是寫死的展示字，不是計算**（同 MoneyLeftSample；數字取自
/// scratchpad/widgets/v4/fetch_check.out 2026/10/14 實際打 Yahoo 的結果）
enum RatesWidgetSample {
    static var model: RatesWidgetModel {
        var model = RatesWidgetModel()
        model.hasValue = true
        model.title = "黃金 每克"
        model.shortTitle = "金/克"
        model.valueText = "NT$4,243"
        model.shortValue = "4,243"
        model.changeText = "▼72（-1.7%）比昨天"
        model.direction = -1
        model.secondLine = "美金 32.13"
        model.secondLineShort = "美金 32.13"
        model.footer = "期貨換算・10:42"
        model.timeText = "10:42"
        model.codes = [WidgetRatesBlock.goldGramCode, WidgetRatesBlock.usdCode]
        model.rectLine1 = "黃金 每克 NT$4,243 ▼1.7%"
        model.rectLine3 = "10:42"
        model.inlineText = "黃金 每克 4,243・美金 32.13"
        return model
    }
}

// MARK: - 畫面

struct RatesWidgetEntryView: View {
    let entry: RatesWidgetEntry

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

    private var isAccessory: Bool {
        family == .accessoryCircular || family == .accessoryRectangular || family == .accessoryInline
    }

    /// ↻：StandBy 不放（按不到）
    private var refreshIntent: RefreshQuotesIntent? {
        guard !surface.isStandBy, !entry.model.codes.isEmpty else { return nil }
        return RefreshQuotesIntent(stockIds: [], rateCodes: entry.model.codes)
    }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                background
            }
            .widgetURL(WidgetLink.settingsCurrency)
    }

    @ViewBuilder
    private var content: some View {
        if family == .accessoryInline {
            Text(entry.model.inlineText)
        } else if family == .accessoryCircular {
            RatesWidgetCircular(model: entry.model)
        } else if family == .accessoryRectangular {
            RatesWidgetRect(model: entry.model)
        } else {
            RatesWidgetSmall(model: entry.model, palette: palette, refresh: refreshIntent)
        }
    }

    /// 主畫面全彩畫天空（不放月牙／雲：大字會撐滿整寬）；著色、StandBy、鎖定畫面透明
    @ViewBuilder
    private var background: some View {
        if surface.drawsSky && !isAccessory {
            WidgetSky(palette: palette, moon: .none)
        } else {
            Color.clear
        }
    }
}

/// 小型：名字／大字／比昨天／下面那一行／期貨換算・時間＋↻
private struct RatesWidgetSmall: View {
    let model: RatesWidgetModel
    let palette: WidgetPalette
    let refresh: RefreshQuotesIntent?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.label)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            RatesWidgetHero(text: model.valueText, color: palette.ink, size: 30)
            changeView
            secondView
            Spacer(minLength: 2)
            RatesWidgetFooter(full: model.footer, short: model.timeText, refresh: refresh, palette: palette)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 「▼72（-1.7%）比昨天」紅漲綠跌；「還沒抓到…」「跟昨天差不多」灰（direction 0）。
    /// [審查] 一行縮字：每台錢「▼284（-1.8%）比昨天」約 128pt 寬，給兩行會折行，五列加起來超過 158pt 小型的 126pt
    @ViewBuilder
    private var changeView: some View {
        if !model.changeText.isEmpty {
            Text(model.changeText)
                .font(.system(size: 12.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(palette.change(model.direction))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    /// 「美金 32.13」；來源跟大字不同時「美金 32.13・10/13 08:12 的價」，放不下就不接時間
    @ViewBuilder
    private var secondView: some View {
        if !model.secondLine.isEmpty {
            ViewThatFits(in: .horizontal) {
                secondText(model.secondLine)
                secondText(model.secondLineShort)
            }
        }
    }

    private func secondText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(palette.inkSoft)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}

/// 大字（著色模式染重點色）
private struct RatesWidgetHero: View {
    let text: String
    let color: Color
    let size: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .widgetAccentable()
    }
}

/// 最下面：「期貨換算・10:42」放不下只寫「10:42」＋右下 ↻（StandBy 沒有）
private struct RatesWidgetFooter: View {
    let full: String
    let short: String
    let refresh: RefreshQuotesIntent?
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 4) {
            ViewThatFits(in: .horizontal) {
                footText(full)
                footText(short)
            }
            Spacer(minLength: 2)
            refreshButton
        }
    }

    private func footText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(palette.label)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    @ViewBuilder
    private var refreshButton: some View {
        if let intent = refresh {
            RatesWidgetRefreshButton(intent: intent, palette: palette)
        }
    }
}

/// ↻：RefreshQuotesIntent 在小工具裡跑（不開 App），抓完寫快取、重畫
private struct RatesWidgetRefreshButton: View {
    let intent: RefreshQuotesIntent
    let palette: WidgetPalette

    var body: some View {
        Button(intent: intent) {
            RatesWidgetRefreshIcon(palette: palette)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("重抓報價")
    }
}

/// ↻ 的圖示（外面多留一點按得到的範圍，靠右對齊）
private struct RatesWidgetRefreshIcon: View {
    let palette: WidgetPalette

    var body: some View {
        Image(systemName: "arrow.clockwise")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(palette.label)
            .frame(width: 26, height: 20, alignment: .trailing)
            .contentShape(Rectangle())
    }
}

/// 鎖定畫面圓形：系統半透明圓底＋上小字「金/克」＋中間「4,243」（系統單色）
private struct RatesWidgetCircular: View {
    let model: RatesWidgetModel

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text(model.shortTitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                RatesWidgetHero(text: model.shortValue, color: .primary, size: 15)
            }
            .padding(.horizontal, 5)
        }
    }
}

/// 鎖定畫面長方形：「黃金 每克 NT$4,243 ▼1.7%」（重點色）／「美金 32.13」／「10:42」（淡）
private struct RatesWidgetRect: View {
    let model: RatesWidgetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(model.rectLine1)
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .widgetAccentable()
            secondLine
            thirdLine
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var secondLine: some View {
        if !model.secondLine.isEmpty {
            Text(model.secondLine)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
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
