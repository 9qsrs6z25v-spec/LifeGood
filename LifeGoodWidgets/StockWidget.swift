import SwiftUI
import WidgetKit
import AppIntents

// MARK: - 股票今天（小＝一檔＋鎖定畫面三型；中＝三檔）（小工具 v4）
//
// 只屬於「LifeGoodWidgets」target。由 G2 實作，規格見 scratchpad/widgets/v4/brief.md 的 G2-2、G2-3。
// （主控建好的空檔，已登記 pbxproj：A01A000002000084／A01B000002000084）
//
// 讀 finance_v1.json（App 寫：持有中的股票、代號、要試的 Yahoo 代號、股數、均價、App 的價與時間、股利那一行），
// 自己上網抓新價（WidgetQuoteStore.refreshStocks → 契約的 WidgetQuoteService，寫 quotes_v1.json），
// 字一律拿 WidgetFinanceStock.figures(quote:now:)（契約：選價、市值、比均價、漲跌、「幾點的價」都在那裡組好），
// **這個檔不算錢、不拼「NT$」**。抓不到就用 App 的價並寫「10/13 13:30 的價」；任何時候都寫是幾點的價。
//
// • 小（一檔）：「TSMC（手寫）2330／1,085／▲13（+1.2%）／比均價 +21%／2 張・NT$217萬／13:30 收盤 ↻」。
//   不是今天的價，漲跌前面加「10/13 」（WidgetStockFigures.datePrefix）。紅漲綠跌（palette.change），▲▼ 在字裡（著色模式靠它）。
//   ↻＝RefreshQuotesIntent（在小工具裡跑，不開 App）；StandBy 不放（按不到）。整塊點了開那一檔（lifegood://finance/stock?id=）。
// • 鎖定畫面（同一個 kind）：圓「2330／▲1.2%」、長方形「2330 台積電／1,085 ▲1.2%／13:30 收盤」、一行「2330 1,085 ▲1.2%」。
//   系統單色、不放 ↻；金額只有小型的「2 張・NT$217萬」，鎖定畫面只放價與 %。
// • 中（三檔，另一個 kind）：「股票 … 10:42 ↻」／三列「2330 台積電｜1,085｜▲1.2%」（每列點了開那一檔）／
//   最下面「今年股利 NT$3.9萬・最近 10/5 配息 NT$530」（App 寫好的字；隱藏金額時用 App 寫好的遮罩版；
//   [審查] 快照是去年寫的就不寫這行，不把去年的股利當今年）。
//   某一列的時間跟第一行不一樣（美股、App 的價）就在名字後面接「・23:55」。不寫今日合計（主控定案 2）、不寫下次配息日。
// • 隱藏金額：provider 讀一次「隱藏金額」總開關，算 configuration.amount.hides(master:) 放進 model；股價、%、日期照常。
// • 時間軸：now＋（下一個 00:00，比 policy 早才放）；policy＝WidgetQuoteSchedule.nextStockRefresh
//  （台股盤中 15 分、13:35 收盤那一次、美股盤中 60 分、其他 3 小時或開盤那一刻）。每一筆 entry 的字用那一筆的時間組。
//   [審查] 收盤後 1 小時內快取還是盤中那一筆（Yahoo 慢、13:35 抓失敗）就 15 分後再抓（WidgetQuoteStore.stockReloadAt）。
//   上網只在 timeline 與 ↻；placeholder、預覽用寫死的樣本字，snapshot 只讀檔。
//
// 型別（internal 的都帶 StockWidget／StocksWidget 前綴或是 brief 指定的名字；畫面零件 private）：
//   StockWidget、StockConfigIntent、StockWidgetEntry、StockWidgetProvider、StockWidgetModel、StockWidgetSample、StockWidgetEntryView
//   StocksWidget、StocksConfigIntent、StocksWidgetEntry、StocksWidgetProvider、StocksWidgetRow、StocksWidgetModel、
//   StocksWidgetSample、StocksWidgetEntryView

// MARK: - Widget（小＋鎖定畫面三型）

struct StockWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.stock, intent: StockConfigIntent.self,
                               provider: StockWidgetProvider()) { entry in
            StockWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("股票今天")
        .description("一檔股票現在多少、今天漲跌、比均價")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Widget（中，三檔）

struct StocksWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.stocks, intent: StocksConfigIntent.self,
                               provider: StocksWidgetProvider()) { entry in
            StocksWidgetRootView(entry: entry)
        }
        .configurationDisplayName("股票今天")
        .description("三檔股票的價與漲跌、今年股利；大的放 6 檔")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - 長按設定

/// 「股票今天」（小、鎖定畫面）：選哪一檔、金額。股票 nil＝市值最大那一檔（選的賣掉、刪掉了也是）
struct StockConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "股票今天"
    static var description = IntentDescription("選哪一檔、金額要不要隱藏")

    @Parameter(title: "股票")
    var stock: WidgetStockEntity?

    @Parameter(title: "金額", default: .followMaster)
    var amount: WidgetAmountOption

    init() {}
}

/// 「股票今天」（中）：第 1／2／3 檔、金額。沒選的用市值大到小補滿三檔（WidgetFinanceSnapshot.threeStocks）
struct StocksConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "股票今天"
    static var description = IntentDescription("選第 1～3 檔、金額要不要隱藏")

    @Parameter(title: "第 1 檔")
    var stock1: WidgetStockEntity?

    @Parameter(title: "第 2 檔")
    var stock2: WidgetStockEntity?

    @Parameter(title: "第 3 檔")
    var stock3: WidgetStockEntity?

    @Parameter(title: "金額", default: .followMaster)
    var amount: WidgetAmountOption

    init() {}

    /// 三格存的股票 id（nil＝沒選）
    var stockIDs: [String?] {
        [stock1?.id, stock2?.id, stock3?.id]
    }
}

// MARK: - Timeline（小）

struct StockWidgetEntry: TimelineEntry {
    /// 畫面一律拿這個當「現在」（字已經用它組好放在 model）
    let date: Date
    let model: StockWidgetModel
}

struct StockWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StockWidgetEntry {
        StockWidgetEntry(date: Date(), model: StockWidgetSample.model)
    }

    /// 預覽用樣本；其他時候只讀檔（不上網，要快）
    func snapshot(for configuration: StockConfigIntent, in context: Context) async -> StockWidgetEntry {
        let now = Date()
        if context.isPreview {
            return StockWidgetEntry(date: now, model: StockWidgetSample.model)
        }
        let hidden: Bool = configuration.amount.hides(master: WidgetHideAmounts.isOn)
        let snapshot = WidgetSnapshotStore.read(WidgetFinanceSnapshot.self)
        let model = StockWidgetModel.make(snapshot: snapshot, stockID: configuration.stock?.id,
                                          cache: WidgetQuoteStore.read(), now: now, hidden: hidden)
        return StockWidgetEntry(date: now, model: model)
    }

    func timeline(for configuration: StockConfigIntent, in context: Context) async -> Timeline<StockWidgetEntry> {
        let now = Date()
        let hidden: Bool = configuration.amount.hides(master: WidgetHideAmounts.isOn)
        let snapshot = WidgetSnapshotStore.read(WidgetFinanceSnapshot.self)
        guard let stock = snapshot?.stock(id: configuration.stock?.id) else {
            // 沒快照、沒持股：一句話；App 寫快照時會叫重畫，這裡只是保險
            let model = StockWidgetModel.make(snapshot: snapshot, stockID: nil, cache: nil, now: now, hidden: hidden)
            let retry: Date = now.addingTimeInterval(WidgetQuoteStore.idleRetry)
            return Timeline(entries: [StockWidgetEntry(date: now, model: model)], policy: .after(retry))
        }
        let cache = await WidgetQuoteStore.refreshStocks([stock], now: now, force: false)
        let quote: WidgetQuote? = cache?.stocks[stock.symbol]
        let reloadAt: Date = WidgetQuoteStore.stockReloadAt([stock], cache: cache, now: now)
        let dates: [Date] = WidgetQuoteStore.entryDates(now: now, reloadAt: reloadAt)
        let entries: [StockWidgetEntry] = dates.map { date in
            StockWidgetEntry(date: date, model: StockWidgetModel.make(stock: stock, quote: quote, now: date, hidden: hidden))
        }
        return Timeline(entries: entries, policy: .after(reloadAt))
    }
}

// MARK: - 畫面要的字（小、鎖定畫面）

/// 一檔要的全部字。provider 用那一筆 entry 的時間組好（WidgetFinanceStock.figures），body 只放 Text。
/// 金額字只有 holding（figures 組好的「2 張・NT$217萬」或遮罩版），這裡不算錢、不拼「NT$」
struct StockWidgetModel {
    /// 沒快照、沒持股：只寫一句話
    var isMessage = true
    var message = ""
    /// 整塊點了去哪：那一檔；一句話時股票頁
    var url: URL = WidgetLink.financeStocks
    /// ↻ 要重抓的那一檔；一句話時 nil
    var stockId: UUID? = nil

    /// 左上手寫英文名「TSMC」
    var script = ""
    /// 右上代號「2330」
    var symbol = ""
    /// 大字「1,085」「US$708.8」；沒有任何報價「—」
    var priceText = "—"
    /// 「▲13（+1.2%）」，不是今天的價「10/13 ▲13（+1.2%）」；沒有報價「還沒有報價」；不知道昨收 ""
    var changeLine = ""
    /// 1 漲（紅）、-1 跌（綠）、0 平盤或不知道（灰）
    var direction = 0
    /// 「比均價 +21%」；均價沒填 ""
    var vsAverage = ""
    /// 「2 張・NT$217萬」；隱藏金額「2 張・NT$ ••••」；沒有報價只寫「2 張」
    var holding = ""
    /// 「10:42」「13:30 收盤」「10/13 收盤」「10/13 13:30 的價」「App 的價」
    var timeText = ""

    // 鎖定畫面

    /// 圓形上面的小字「2330」
    var circleTop = ""
    /// 圓形中間「▲1.2%」（不知道昨收寫價）；一句話時 ""（只放圖示）
    var circleCenter = "—"
    /// 長方形三行：「2330 台積電」／「1,085 ▲1.2%」（不是今天的價前面加「10/13」）／「13:30 收盤」
    var rectLine1 = ""
    var rectLine2 = ""
    var rectLine3 = ""
    /// 一行字「2330 1,085 ▲1.2%」
    var inlineText = ""

    /// provider（snapshot）用：沒快照、沒持股是一句話；不然挑設定選的那一檔（找不到＝市值最大）
    static func make(snapshot: WidgetFinanceSnapshot?, stockID: String?, cache: WidgetQuoteCache?,
                     now: Date, hidden: Bool) -> StockWidgetModel {
        guard let snap = snapshot else { return notice("打開 LifeGood 一次，這裡就會出現股票") }
        guard let stock = snap.stock(id: stockID) else { return notice("還沒有持股") }
        return make(stock: stock, quote: cache?.stocks[stock.symbol], now: now, hidden: hidden)
    }

    /// 一檔的字（now＝這一筆 entry 的時間：「今天」「收盤」「10/13」都照它判斷）
    static func make(stock: WidgetFinanceStock, quote: WidgetQuote?, now: Date, hidden: Bool) -> StockWidgetModel {
        var model = StockWidgetModel()
        model.isMessage = false
        model.url = stock.url
        model.stockId = stock.id
        model.script = stock.script
        model.symbol = stock.symbol
        model.circleTop = stock.symbol
        model.rectLine1 = stock.menuTitle
        guard let figures = stock.figures(quote: quote, now: now) else {
            // App 也還沒報過價、小工具也沒抓到：不寫 NT$0
            model.changeLine = "還沒有報價"
            model.holding = stock.qtyText
            model.rectLine2 = "還沒有報價"
            model.inlineText = stock.symbol + " 還沒有報價"
            return model
        }
        fill(&model, figures: figures, symbol: stock.symbol, hidden: hidden)
        return model
    }

    /// 一句話（沒快照、沒持股）
    static func notice(_ text: String) -> StockWidgetModel {
        var model = StockWidgetModel()
        model.message = text
        model.circleCenter = ""
        model.rectLine1 = "股票今天"
        model.rectLine2 = text
        model.inlineText = text
        return model
    }

    /// 用空白接起來，nil、空字串跳過（「10/13」「1,085」「▲1.2%」→「10/13 1,085 ▲1.2%」）
    static func joined(_ parts: [String?]) -> String {
        let texts: [String] = parts.compactMap { $0 }.filter { !$0.isEmpty }
        return texts.joined(separator: " ")
    }

    private static func fill(_ model: inout StockWidgetModel, figures f: WidgetStockFigures, symbol: String,
                             hidden: Bool) {
        model.priceText = f.priceText
        if let change = f.changeText {
            model.changeLine = joined([f.datePrefix, change])
        }
        model.direction = f.direction
        model.vsAverage = f.vsAverageText ?? ""
        model.holding = hidden ? f.holdingTextMasked : f.holdingText
        model.timeText = f.timeText
        model.circleCenter = f.rateText ?? f.priceText
        model.rectLine2 = joined([f.datePrefix, f.priceText, f.rateText])
        model.rectLine3 = f.timeText
        model.inlineText = joined([symbol, f.datePrefix, f.priceText, f.rateText])
    }
}

/// 小工具庫預覽與 placeholder 的樣本。**這些是寫死的展示字，不是計算**（同 MoneyLeftSample）
enum StockWidgetSample {
    /// ↻ 在預覽裡也畫出來（預覽按不到；真的按了也只是找不到這一檔、什麼都不抓）
    static let sampleID = UUID(uuidString: "00000000-0000-0000-0000-000000002330")

    static var model: StockWidgetModel {
        var model = StockWidgetModel()
        model.isMessage = false
        model.stockId = sampleID
        model.script = "TSMC"
        model.symbol = "2330"
        model.priceText = "1,085"
        model.changeLine = "▲13（+1.2%）"
        model.direction = 1
        model.vsAverage = "比均價 +21%"
        model.holding = "2 張・NT$217萬"
        model.timeText = "13:30 收盤"
        model.circleTop = "2330"
        model.circleCenter = "▲1.2%"
        model.rectLine1 = "2330 台積電"
        model.rectLine2 = "1,085 ▲1.2%"
        model.rectLine3 = "13:30 收盤"
        model.inlineText = "2330 1,085 ▲1.2%"
        return model
    }
}

// MARK: - 畫面（小、鎖定畫面）

struct StockWidgetEntryView: View {
    let entry: StockWidgetEntry

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

    /// ↻：StandBy 不放（按不到）、一句話時不放
    private var refreshIntent: RefreshQuotesIntent? {
        guard !surface.isStandBy, let id = entry.model.stockId else { return nil }
        return RefreshQuotesIntent(stockIds: [id], rateCodes: [])
    }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                background
            }
            .widgetURL(entry.model.url)
    }

    @ViewBuilder
    private var content: some View {
        if family == .accessoryInline {
            Text(entry.model.inlineText)
        } else if family == .accessoryCircular {
            StockWidgetCircular(model: entry.model)
        } else if family == .accessoryRectangular {
            StockWidgetRect(model: entry.model)
        } else if entry.model.isMessage {
            StockWidgetMessage(text: entry.model.message, palette: palette)
        } else {
            StockWidgetSmall(model: entry.model, palette: palette, plainScript: surface.isTinted,
                             refresh: refreshIntent)
        }
    }

    /// 主畫面全彩畫天空（不放月牙／雲：右上是代號、大字會撐滿整寬）；著色、StandBy、鎖定畫面透明
    @ViewBuilder
    private var background: some View {
        if surface.drawsSky && !isAccessory {
            WidgetSky(palette: palette, moon: .none)
        } else {
            Color.clear
        }
    }
}

/// 小型：手寫名＋代號／大字價／漲跌／比均價／張數・市值／時間＋↻。
/// 放不下（小螢幕）時先拿掉「比均價」那一行，價、漲跌、時間一定在。
/// [審查] 列距 0（同還能花）：列距 1 時七列加起來約 127pt，158pt 的小型（內容 126pt）會一直退成沒有「比均價」的版本
private struct StockWidgetSmall: View {
    let model: StockWidgetModel
    let palette: WidgetPalette
    /// 著色模式：手寫字換一般字
    let plainScript: Bool
    let refresh: RefreshQuotesIntent?

    var body: some View {
        ViewThatFits(in: .vertical) {
            column(showsAverage: true)
            column(showsAverage: false)
        }
    }

    private func column(showsAverage: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            StockWidgetTitleRow(script: model.script, symbol: model.symbol, palette: palette,
                                plainScript: plainScript)
            StockWidgetHero(text: model.priceText, color: palette.ink, size: 30)
            changeView
            detailLine(showsAverage ? model.vsAverage : "")
            detailLine(model.holding)
            Spacer(minLength: 2)
            StockWidgetFooter(time: model.timeText, refresh: refresh, palette: palette)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 「▲13（+1.2%）」紅漲綠跌；「還沒有報價」灰（direction 0）
    @ViewBuilder
    private var changeView: some View {
        if !model.changeLine.isEmpty {
            Text(model.changeLine)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(palette.change(model.direction))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    @ViewBuilder
    private func detailLine(_ text: String) -> some View {
        if !text.isEmpty {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(palette.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

/// 第一列：左手寫英文名（App 股票卡同一個字型），右代號
private struct StockWidgetTitleRow: View {
    let script: String
    let symbol: String
    let palette: WidgetPalette
    let plainScript: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(script)
                .font(scriptFont)
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Text(symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.label)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var scriptFont: Font {
        plainScript ? Font.system(size: 13, weight: .semibold) : Font.custom("BradleyHandITCTT-Bold", fixedSize: 15)
    }
}

/// 大字（著色模式染重點色）
private struct StockWidgetHero: View {
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

/// 最下面：幾點的價＋右下 ↻（StandBy、一句話時沒有 ↻）
private struct StockWidgetFooter: View {
    let time: String
    let refresh: RefreshQuotesIntent?
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 4) {
            Text(time)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            refreshButton
        }
    }

    @ViewBuilder
    private var refreshButton: some View {
        if let intent = refresh {
            StockWidgetRefreshButton(intent: intent, palette: palette)
        }
    }
}

/// ↻：RefreshQuotesIntent 在小工具裡跑（不開 App），抓完寫快取、重畫
private struct StockWidgetRefreshButton: View {
    let intent: RefreshQuotesIntent
    let palette: WidgetPalette

    var body: some View {
        Button(intent: intent) {
            StockWidgetRefreshIcon(palette: palette)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("重抓報價")
    }
}

/// ↻ 的圖示（外面多留一點按得到的範圍，靠右對齊不往內佔版面）
private struct StockWidgetRefreshIcon: View {
    let palette: WidgetPalette

    var body: some View {
        Image(systemName: "arrow.clockwise")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(palette.label)
            .frame(width: 26, height: 20, alignment: .trailing)
            .contentShape(Rectangle())
    }
}

/// 沒快照、沒持股：只寫一句話（小、中共用）
private struct StockWidgetMessage: View {
    let text: String
    let palette: WidgetPalette

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
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

/// 鎖定畫面圓形：系統半透明圓底＋上小字代號＋中間 ▲1.2%（系統單色，不指定顏色）
private struct StockWidgetCircular: View {
    let model: StockWidgetModel

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            center
        }
    }

    @ViewBuilder
    private var center: some View {
        if model.isMessage {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 20, weight: .semibold))
        } else {
            VStack(spacing: 0) {
                Text(model.circleTop)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                StockWidgetHero(text: model.circleCenter, color: .primary, size: 14)
            }
            .padding(.horizontal, 5)
        }
    }
}

/// 鎖定畫面長方形三行：名字（粗）／價與 %（重點色）／幾點的價（淡）
private struct StockWidgetRect: View {
    let model: StockWidgetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(model.rectLine1)
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(model.rectLine2)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .widgetAccentable()
            thirdLine
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var thirdLine: some View {
        if !model.rectLine3.isEmpty {
            Text(model.rectLine3)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Timeline（中）

struct StocksWidgetEntry: TimelineEntry {
    let date: Date
    let model: StocksWidgetModel
    /// 大型（6 檔）才有；中型 nil（既有 StocksWidgetEntry(date:model:) 照用）
    var large: StocksLargeModel? = nil
}

struct StocksWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StocksWidgetEntry {
        if context.family == .systemLarge {
            return StocksWidgetEntry(date: Date(), model: StocksWidgetSample.model, large: StocksLargeSample.model)
        }
        return StocksWidgetEntry(date: Date(), model: StocksWidgetSample.model)
    }

    func snapshot(for configuration: StocksConfigIntent, in context: Context) async -> StocksWidgetEntry {
        if context.family == .systemLarge {
            return largeSnapshot(for: configuration, in: context)
        }
        let now = Date()
        if context.isPreview {
            return StocksWidgetEntry(date: now, model: StocksWidgetSample.model)
        }
        let hidden: Bool = configuration.amount.hides(master: WidgetHideAmounts.isOn)
        let snapshot = WidgetSnapshotStore.read(WidgetFinanceSnapshot.self)
        let model = StocksWidgetModel.make(snapshot: snapshot, ids: configuration.stockIDs,
                                           cache: WidgetQuoteStore.read(), now: now, hidden: hidden)
        return StocksWidgetEntry(date: now, model: model)
    }

    func timeline(for configuration: StocksConfigIntent, in context: Context) async -> Timeline<StocksWidgetEntry> {
        if context.family == .systemLarge {
            return await largeTimeline(for: configuration)
        }
        let now = Date()
        let hidden: Bool = configuration.amount.hides(master: WidgetHideAmounts.isOn)
        let snapshot = WidgetSnapshotStore.read(WidgetFinanceSnapshot.self)
        let rows: [WidgetFinanceStock] = snapshot?.threeStocks(ids: configuration.stockIDs) ?? []
        guard let snap = snapshot, !rows.isEmpty else {
            let model = StocksWidgetModel.make(snapshot: snapshot, ids: configuration.stockIDs, cache: nil,
                                               now: now, hidden: hidden)
            let retry: Date = now.addingTimeInterval(WidgetQuoteStore.idleRetry)
            return Timeline(entries: [StocksWidgetEntry(date: now, model: model)], policy: .after(retry))
        }
        let cache = await WidgetQuoteStore.refreshStocks(rows, now: now, force: false)
        let reloadAt: Date = WidgetQuoteStore.stockReloadAt(rows, cache: cache, now: now)
        let dates: [Date] = WidgetQuoteStore.entryDates(now: now, reloadAt: reloadAt)
        let block: WidgetStocksBlock = snap.stocks
        let writtenAt: Date = snap.generatedAt
        let entries: [StocksWidgetEntry] = dates.map { date in
            StocksWidgetEntry(date: date, model: StocksWidgetModel.make(stocks: rows, block: block, writtenAt: writtenAt,
                                                                         cache: cache, now: date, hidden: hidden))
        }
        return Timeline(entries: entries, policy: .after(reloadAt))
    }
}

// MARK: - 畫面要的字（中）

/// 中型的一列：「2330 台積電｜1,085｜▲1.2%」
struct StocksWidgetRow: Identifiable {
    let id: UUID
    /// 「2330 台積電」「VOO」
    let name: String
    /// 這一列的時間跟第一行不一樣時「・23:55」「・10/13 13:30 的價」；一樣 ""
    let timeSuffix: String
    /// 「1,085」「US$708.8」；沒有報價「—」
    let priceText: String
    /// 「▲1.2%」，不是今天的價「10/13 ▲1.2%」；不知道昨收 ""；沒有報價「還沒有報價」
    let rateText: String
    let direction: Int
    let url: URL
}

struct StocksWidgetModel {
    var isMessage = true
    var message = ""
    /// 整塊（列與第一行以外的地方）點了去股票頁
    var url: URL = WidgetLink.financeStocks
    /// 第一行右邊的時間＝第一列（有報價的第一列）的 timeText
    var timeText = ""
    var rows: [StocksWidgetRow] = []
    /// 「今年股利 NT$3.9萬・最近 10/5 配息 NT$530」（App 寫好的字；隱藏金額用 App 的遮罩版）；沒有 ""
    var dividendLine = ""
    /// ↻ 要重抓的三檔
    var stockIds: [UUID] = []

    /// provider（snapshot、沒資料）用：沒快照、沒持股是一句話
    static func make(snapshot: WidgetFinanceSnapshot?, ids: [String?], cache: WidgetQuoteCache?,
                     now: Date, hidden: Bool) -> StocksWidgetModel {
        guard let snap = snapshot else { return notice("打開 LifeGood 一次，這裡就會出現股票") }
        let stocks: [WidgetFinanceStock] = snap.threeStocks(ids: ids)
        guard !stocks.isEmpty else { return notice("還沒有持股") }
        return make(stocks: stocks, block: snap.stocks, writtenAt: snap.generatedAt, cache: cache, now: now,
                    hidden: hidden)
    }

    /// 三檔的字（now＝這一筆 entry 的時間；writtenAt＝finance 快照寫的時間，股利那一行的「今年」是那一年）
    static func make(stocks: [WidgetFinanceStock], block: WidgetStocksBlock, writtenAt: Date,
                     cache: WidgetQuoteCache?, now: Date, hidden: Bool) -> StocksWidgetModel {
        var model = StocksWidgetModel()
        model.isMessage = false
        let figures: [WidgetStockFigures?] = stocks.map { $0.figures(quote: cache?.stocks[$0.symbol], now: now) }
        let header: String = headerTime(figures)
        model.timeText = header
        var rows: [StocksWidgetRow] = []
        for (stock, f) in zip(stocks, figures) {
            rows.append(row(stock, figures: f, headerTime: header))
        }
        model.rows = rows
        model.stockIds = stocks.map { $0.id }
        let line: String? = hidden ? block.dividendLineMasked : block.dividendLine
        // [審查] 「今年股利」是快照那一年的：跨年了（App 從去年底到現在都沒開）就不寫，不把去年的當今年
        model.dividendLine = isSameYear(writtenAt, now) ? (line ?? "") : ""
        return model
    }

    /// 同一個西曆年（手機現在的時區）
    private static func isSameYear(_ a: Date, _ b: Date) -> Bool {
        let cal = Calendar.current
        return cal.component(.year, from: a) == cal.component(.year, from: b)
    }

    static func notice(_ text: String) -> StocksWidgetModel {
        var model = StocksWidgetModel()
        model.message = text
        return model
    }

    /// 第一列的時間；第一列沒有報價就往下找
    private static func headerTime(_ figures: [WidgetStockFigures?]) -> String {
        for f in figures {
            if let t = f?.timeText, !t.isEmpty { return t }
        }
        return ""
    }

    private static func row(_ stock: WidgetFinanceStock, figures f: WidgetStockFigures?,
                            headerTime: String) -> StocksWidgetRow {
        var suffix = ""
        if let t = f?.timeText, !t.isEmpty, t != headerTime {
            suffix = "・" + t
        }
        var rate = "還沒有報價"
        if let f {
            rate = f.rateText.map { StockWidgetModel.joined([f.datePrefix, $0]) } ?? ""
        }
        return StocksWidgetRow(id: stock.id, name: stock.menuTitle, timeSuffix: suffix,
                               priceText: f?.priceText ?? "—", rateText: rate,
                               direction: f?.direction ?? 0, url: stock.url)
    }
}

/// 小工具庫預覽與 placeholder 的樣本（寫死的展示字，不是計算）
enum StocksWidgetSample {
    static var model: StocksWidgetModel {
        var model = StocksWidgetModel()
        model.isMessage = false
        model.timeText = "10:42"
        model.rows = rows
        model.dividendLine = "今年股利 NT$3.9萬・最近 10/5 配息 NT$530"
        model.stockIds = rows.map { $0.id }
        return model
    }

    private static let rows: [StocksWidgetRow] = [
        sampleRow("00000000-0000-0000-0000-000000002330", name: "2330 台積電", suffix: "",
                  price: "1,085", rate: "▲1.2%", direction: 1),
        sampleRow("00000000-0000-0000-0000-000000000099", name: "VOO", suffix: "・23:55",
                  price: "US$708.8", rate: "▼0.9%", direction: -1),
        sampleRow("00000000-0000-0000-0000-000000000050", name: "0050 元大台灣50", suffix: "",
                  price: "113", rate: "▲0.5%", direction: 1)
    ]

    private static func sampleRow(_ id: String, name: String, suffix: String, price: String, rate: String,
                                  direction: Int) -> StocksWidgetRow {
        StocksWidgetRow(id: UUID(uuidString: id) ?? UUID(), name: name, timeSuffix: suffix, priceText: price,
                        rateText: rate, direction: direction, url: WidgetLink.financeStocks)
    }
}

// MARK: - 畫面（中）

struct StocksWidgetEntryView: View {
    let entry: StocksWidgetEntry

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    private var surface: WidgetPalette.Surface {
        WidgetPalette.Surface(renderingMode: renderingMode, showsBackground: showsBackground)
    }

    private var palette: WidgetPalette {
        WidgetPalette(colorScheme, mono: surface.isMono)
    }

    /// ↻：三檔一起重抓（StandBy 不放）
    private var refreshIntent: RefreshQuotesIntent? {
        guard !surface.isStandBy, !entry.model.stockIds.isEmpty else { return nil }
        return RefreshQuotesIntent(stockIds: entry.model.stockIds, rateCodes: [])
    }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                background
            }
            .widgetURL(entry.model.url)
    }

    @ViewBuilder
    private var content: some View {
        if entry.model.isMessage {
            StockWidgetMessage(text: entry.model.message, palette: palette)
        } else {
            StocksWidgetBoard(model: entry.model, palette: palette, refresh: refreshIntent)
        }
    }

    /// 全彩畫天空（第一行右邊是時間＋↻，不放月牙／雲）；著色、StandBy 透明
    @ViewBuilder
    private var background: some View {
        if surface.drawsSky {
            WidgetSky(palette: palette, moon: .none)
        } else {
            Color.clear
        }
    }
}

/// 第一行／三列／股利那一行
private struct StocksWidgetBoard: View {
    let model: StocksWidgetModel
    let palette: WidgetPalette
    let refresh: RefreshQuotesIntent?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            StocksWidgetHeader(time: model.timeText, refresh: refresh, palette: palette)
            ForEach(model.rows, id: \.id) { row in
                StocksWidgetRowView(row: row, palette: palette)
            }
            Spacer(minLength: 0)
            dividendView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var dividendView: some View {
        if !model.dividendLine.isEmpty {
            Text(model.dividendLine)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(palette.label)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

/// 第一行：「股票」（點了開股票頁）……時間＋↻
private struct StocksWidgetHeader: View {
    let time: String
    let refresh: RefreshQuotesIntent?
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 6) {
            Link(destination: WidgetLink.financeStocks) {
                titleLine
            }
            refreshButton
        }
    }

    private var titleLine: some View {
        HStack(spacing: 5) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.label)
            Text("股票")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(palette.ink)
            Spacer(minLength: 6)
            Text(time)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    @ViewBuilder
    private var refreshButton: some View {
        if let intent = refresh {
            StockWidgetRefreshButton(intent: intent, palette: palette)
        }
    }
}

/// 一列（點了開那一檔）：名字（太長縮的是名字）｜價｜漲跌（紅漲綠跌、▲▼）
private struct StocksWidgetRowView: View {
    let row: StocksWidgetRow
    let palette: WidgetPalette

    var body: some View {
        Link(destination: row.url) {
            HStack(spacing: 8) {
                nameView
                Spacer(minLength: 4)
                priceView
                rateView
            }
        }
    }

    private var nameView: some View {
        HStack(spacing: 0) {
            Text(row.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
            suffixView
        }
    }

    @ViewBuilder
    private var suffixView: some View {
        if !row.timeSuffix.isEmpty {
            Text(row.timeSuffix)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.label)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var priceView: some View {
        Text(row.priceText)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(palette.ink)
            .lineLimit(1)
            .fixedSize()
            .widgetAccentable()
    }

    private var rateView: some View {
        Text(row.rateText)
            .font(.system(size: 12.5, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(palette.change(row.direction))
            .lineLimit(1)
            .fixedSize()
            .frame(minWidth: 52, alignment: .trailing)
    }
}

// MARK: - 大型（v25.632 large2）
//
// 規格：scratchpad/radar/build/large2/brief.md §0 C1、§2 G1；示意圖 scratchpad/largewidgets/stocks.html（版面以示意圖為準）。
// 參考答案：sim_large2.py 的 stocks_large_make_snap／stocks_large_make／stocks_large_row（一個字一個字對照）。
//
//   表頭「股票　台股盤中・10:42」＋右上 36pt 圓〔↻〕（RefreshQuotesIntent，6 檔一起重抓）→
//   6 列，每列兩行「2330 台積電｜1,085」／「比均價 +18%・2 張・NT$217萬｜▲13（+1.2%）」→ 頁腳「今年股利 …」。
//   放不下改一行「2330 台積電｜1,085｜▲1.2%」（6 檔都在），再放不下才少列；字級不變（StocksLargeLayout.candidates）。
//   挑哪 6 檔：前 3 檔照長按設定的第 1／2／3 檔，其他照 App 的市值補（StocksLargePick.pick；設定不加參數）。
//   上網只多抓 3 檔：同一個 WidgetQuoteStore.refreshStocks（只抓快取不夠新的）、重畫時間同中型。
//   這個檔不算錢、不拼「NT$」：字一律拿 WidgetFinanceStock.figures(quote:now:)。
//   隱藏金額＝provider 讀一次放進 model；vibrant（Mac 桌面沒聚焦）第二行只寫比均價、股利不畫。

extension StocksWidgetProvider {
    /// 預覽用樣本；其他時候只讀檔（不上網，要快）
    func largeSnapshot(for configuration: StocksConfigIntent,
                       in context: TimelineProviderContext) -> StocksWidgetEntry {
        let now = Date()
        if context.isPreview {
            return StocksWidgetEntry(date: now, model: StocksWidgetSample.model, large: StocksLargeSample.model)
        }
        let hidden: Bool = configuration.amount.hides(master: WidgetHideAmounts.isOn)
        let snapshot = WidgetSnapshotStore.read(WidgetFinanceSnapshot.self)
        let large = StocksLargeModel.make(snapshot: snapshot, ids: configuration.stockIDs,
                                          cache: WidgetQuoteStore.read(), now: now, hidden: hidden)
        return StocksWidgetEntry(date: now, model: StocksWidgetModel(), large: large)
    }

    /// 6 檔：同一個快取、同一個重畫時間（stockReloadAt／entryDates）；每一筆 entry 的字用那一筆的時間組
    func largeTimeline(for configuration: StocksConfigIntent) async -> Timeline<StocksWidgetEntry> {
        let now = Date()
        let hidden: Bool = configuration.amount.hides(master: WidgetHideAmounts.isOn)
        let snapshot = WidgetSnapshotStore.read(WidgetFinanceSnapshot.self)
        let items: [WidgetFinanceStock] = snapshot?.stocks.items ?? []
        let rows: [WidgetFinanceStock] = StocksLargePick.pick(items, ids: configuration.stockIDs,
                                                              count: StocksLargeLayout.maxRows)
        guard let snap = snapshot, !rows.isEmpty else {
            // 沒快照、沒持股：一句話；App 寫快照時會叫重畫，這裡只是保險
            let large = StocksLargeModel.make(snapshot: snapshot, ids: configuration.stockIDs, cache: nil,
                                              now: now, hidden: hidden)
            let retry: Date = now.addingTimeInterval(WidgetQuoteStore.idleRetry)
            let entry = StocksWidgetEntry(date: now, model: StocksWidgetModel(), large: large)
            return Timeline(entries: [entry], policy: .after(retry))
        }
        let cache = await WidgetQuoteStore.refreshStocks(rows, now: now, force: false)
        let reloadAt: Date = WidgetQuoteStore.stockReloadAt(rows, cache: cache, now: now)
        let dates: [Date] = WidgetQuoteStore.entryDates(now: now, reloadAt: reloadAt)
        let block: WidgetStocksBlock = snap.stocks
        let writtenAt: Date = snap.generatedAt
        let entries: [StocksWidgetEntry] = dates.map { (date: Date) -> StocksWidgetEntry in
            let large = StocksLargeModel.make(stocks: rows, block: block, writtenAt: writtenAt, cache: cache,
                                              now: date, hidden: hidden)
            return StocksWidgetEntry(date: date, model: StocksWidgetModel(), large: large)
        }
        return Timeline(entries: entries, policy: .after(reloadAt))
    }
}

/// 大型的一列（sim stocks_large_row）：兩行版用 changeText＋detail，一行版用 rateText
struct StocksLargeRow: Identifiable {
    let id: UUID
    /// 「2330」「AAPL」
    let code: String
    /// 「台積電」；名字就是代號 ""（不畫）
    let name: String
    /// 這一列的時間跟表頭那一檔不一樣時「・05:00 收盤」「・10/13 13:30 的價」；一樣 ""
    let timeSuffix: String
    /// 「1,085」「US$228.4」；沒有報價「—」
    let priceText: String
    /// 兩行版右下「▲13（+1.2%）」「平盤」，不是今天的價「10/13 ▲13（+1.2%）」；不知道昨收 ""；沒有報價「還沒有報價」
    let changeText: String
    /// 一行版「▲1.2%」（同中型）；不知道昨收 ""；沒有報價「還沒有報價」
    let rateText: String
    /// 1 漲（紅）、-1 跌（綠）、0 平盤或不知道（灰）
    let direction: Int
    /// 兩行版左下「比均價 +18%・2 張・NT$217萬」（隱藏金額用遮罩版）；沒有報價「2 張」
    let detail: String
    /// vibrant 只寫「比均價 +18%」；沒有報價 ""
    let detailLocked: String
    let url: URL
}

/// ViewThatFits 的一個候選：畫前幾檔、兩行還是一行（列由 model 先切好）
struct StocksLargeCandidate: Identifiable {
    let id: Int
    let plan: StocksLargeLayout.Plan
    let rows: [StocksLargeRow]
}

struct StocksLargeModel {
    /// 沒快照、沒持股：只寫一句話
    var isMessage = true
    var message = ""
    /// 表頭右邊「台股盤中・10:42」「13:30 收盤」；都沒有時間 ""
    var headerText = ""
    /// 最多 6 檔（全部；候選再切）
    var rows: [StocksLargeRow] = []
    /// 「今年股利 NT$3.9萬・最近 10/5 配息 NT$530」（App 寫好的字；隱藏金額用遮罩版）；沒有、跨年 ""
    var dividendLine = ""
    /// ↻ 要重抓的那幾檔
    var stockIds: [UUID] = []
    /// 固定 4 個（大到小）
    var candidates: [StocksLargeCandidate] = []

    /// 安全取值：超出範圍夾在頭尾；沒有候選回一個 0 列的
    func candidate(at index: Int) -> StocksLargeCandidate {
        guard !candidates.isEmpty else {
            let plan = StocksLargeLayout.Plan(rows: 0, twoLine: false)
            return StocksLargeCandidate(id: 0, plan: plan, rows: [])
        }
        let i: Int = min(max(0, index), candidates.count - 1)
        return candidates[i]
    }

    /// provider（snapshot、沒資料）用：沒快照、沒持股是一句話（sim stocks_large_make_snap）
    static func make(snapshot: WidgetFinanceSnapshot?, ids: [String?], cache: WidgetQuoteCache?,
                     now: Date, hidden: Bool) -> StocksLargeModel {
        guard let snap = snapshot else { return notice("打開 LifeGood 一次，這裡就會出現股票") }
        let stocks: [WidgetFinanceStock] = StocksLargePick.pick(snap.stocks.items, ids: ids,
                                                                count: StocksLargeLayout.maxRows)
        guard !stocks.isEmpty else { return notice("還沒有持股") }
        return make(stocks: stocks, block: snap.stocks, writtenAt: snap.generatedAt, cache: cache, now: now,
                    hidden: hidden)
    }

    /// 6 檔的字（sim stocks_large_make；now＝這一筆 entry 的時間；writtenAt＝finance 快照寫的時間）
    static func make(stocks: [WidgetFinanceStock], block: WidgetStocksBlock, writtenAt: Date,
                     cache: WidgetQuoteCache?, now: Date, hidden: Bool) -> StocksLargeModel {
        var model = StocksLargeModel()
        model.isMessage = false
        let figures: [WidgetStockFigures?] = stocks.map { (stock: WidgetFinanceStock) -> WidgetStockFigures? in
            stock.figures(quote: cache?.stocks[stock.symbol], now: now)
        }
        // 表頭用的那一檔＝第一個有時間的
        var headerTime = ""
        var headerLive = false
        var headerUS = false
        for (stock, f) in zip(stocks, figures) {
            if let fig = f, !fig.timeText.isEmpty {
                headerTime = fig.timeText
                headerLive = StocksLargeText.isLive(fig)
                headerUS = stock.isUS
                break
            }
        }
        var rows: [StocksLargeRow] = []
        for (stock, f) in zip(stocks, figures) {
            rows.append(row(stock, figures: f, headerTime: headerTime, hidden: hidden))
        }
        model.headerText = StocksLargeText.header(time: headerTime, isLive: headerLive, isUS: headerUS, now: now)
        model.rows = rows
        model.stockIds = stocks.map { (stock: WidgetFinanceStock) -> UUID in stock.id }
        let line: String? = hidden ? block.dividendLineMasked : block.dividendLine
        // 「今年股利」是快照那一年的：跨年了就不寫（同中型）
        model.dividendLine = isSameYear(writtenAt, now) ? (line ?? "") : ""
        model.candidates = makeCandidates(rows, hasFooter: !model.dividendLine.isEmpty)
        return model
    }

    /// 一句話（沒快照、沒持股）
    static func notice(_ text: String) -> StocksLargeModel {
        var model = StocksLargeModel()
        model.message = text
        return model
    }

    /// 4 個候選，列先切好（樣本也用這個）
    static func makeCandidates(_ rows: [StocksLargeRow], hasFooter: Bool) -> [StocksLargeCandidate] {
        let plans: [StocksLargeLayout.Plan] = StocksLargeLayout.candidates(count: rows.count, hasFooter: hasFooter)
        var out: [StocksLargeCandidate] = []
        for (i, plan) in plans.enumerated() {
            let shown: [StocksLargeRow] = Array(rows.prefix(max(0, plan.rows)))
            out.append(StocksLargeCandidate(id: i, plan: plan, rows: shown))
        }
        return out
    }

    /// 同一個西曆年（手機現在的時區；中型的 isSameYear 是 private，這裡另寫一個一樣的）
    private static func isSameYear(_ a: Date, _ b: Date) -> Bool {
        let cal = Calendar.current
        return cal.component(.year, from: a) == cal.component(.year, from: b)
    }

    /// 一列（sim stocks_large_row）：時間跟表頭那一檔不一樣就在名字後面接「・時間」
    private static func row(_ stock: WidgetFinanceStock, figures: WidgetStockFigures?, headerTime: String,
                            hidden: Bool) -> StocksLargeRow {
        let name: String = stock.name == stock.symbol ? "" : stock.name
        guard let f = figures else {
            // App 也還沒報過價、小工具也沒抓到：不寫 NT$0
            return StocksLargeRow(id: stock.id, code: stock.symbol, name: name, timeSuffix: "", priceText: "—",
                                  changeText: "還沒有報價", rateText: "還沒有報價", direction: 0,
                                  detail: stock.qtyText, detailLocked: "", url: stock.url)
        }
        var suffix = ""
        if !f.timeText.isEmpty, f.timeText != headerTime {
            suffix = "・" + f.timeText
        }
        let change: String = f.changeText.map { (text: String) -> String in
            StockWidgetModel.joined([f.datePrefix, text])
        } ?? ""
        let rate: String = f.rateText.map { (text: String) -> String in
            StockWidgetModel.joined([f.datePrefix, text])
        } ?? ""
        let vs: String = f.vsAverageText ?? ""
        let holding: String = hidden ? f.holdingTextMasked : f.holdingText
        let detail: String = StocksLargeText.dotJoined([vs, holding])
        return StocksLargeRow(id: stock.id, code: stock.symbol, name: name, timeSuffix: suffix,
                              priceText: f.priceText, changeText: change, rateText: rate, direction: f.direction,
                              detail: detail, detailLocked: vs, url: stock.url)
    }
}

/// 小工具庫預覽與 placeholder 的樣本（示意圖那 6 檔）。**這些是寫死的展示字，不是計算**
enum StocksLargeSample {
    static var model: StocksLargeModel {
        var model = StocksLargeModel()
        model.isMessage = false
        model.headerText = "台股盤中・10:42"
        model.rows = rows
        model.dividendLine = "今年股利 NT$3.9萬・最近 10/5 配息 NT$530"
        model.stockIds = rows.map { (row: StocksLargeRow) -> UUID in row.id }
        model.candidates = StocksLargeModel.makeCandidates(rows, hasFooter: true)
        return model
    }

    private static let rows: [StocksLargeRow] = [
        sampleRow("00000000-0000-0000-0000-000000002330", code: "2330", name: "台積電", suffix: "",
                  price: "1,085", change: "▲13（+1.2%）", rate: "▲1.2%", direction: 1,
                  average: "比均價 +18%", holding: "2 張・NT$217萬"),
        sampleRow("00000000-0000-0000-0000-000000000050", code: "0050", name: "元大台灣50", suffix: "",
                  price: "198.5", change: "▼0.8（-0.4%）", rate: "▼0.4%", direction: -1,
                  average: "比均價 +9.1%", holding: "3 張・NT$59.6萬"),
        sampleRow("00000000-0000-0000-0000-000000002454", code: "2454", name: "聯發科", suffix: "",
                  price: "1,320", change: "▼10（-0.8%）", rate: "▼0.8%", direction: -1,
                  average: "比均價 -4.0%", holding: "1 張・NT$132萬"),
        sampleRow("00000000-0000-0000-0000-00000000AA91", code: "AAPL", name: "Apple", suffix: "・05:00 收盤",
                  price: "US$228.4", change: "▲1.6（+0.7%）", rate: "▲0.7%", direction: 1,
                  average: "比均價 +22%", holding: "10 股・NT$7.4萬"),
        sampleRow("00000000-0000-0000-0000-000000000878", code: "00878", name: "國泰永續高股息", suffix: "",
                  price: "22.84", change: "平盤", rate: "平盤", direction: 0,
                  average: "比均價 +3.0%", holding: "10 張・NT$22.8萬"),
        sampleRow("00000000-0000-0000-0000-000000002317", code: "2317", name: "鴻海", suffix: "",
                  price: "212.5", change: "▼3.2（-1.5%）", rate: "▼1.5%", direction: -1,
                  average: "比均價 +31%", holding: "2 張・NT$42.5萬")
    ]

    private static func sampleRow(_ id: String, code: String, name: String, suffix: String, price: String,
                                  change: String, rate: String, direction: Int, average: String,
                                  holding: String) -> StocksLargeRow {
        StocksLargeRow(id: UUID(uuidString: id) ?? UUID(), code: code, name: name, timeSuffix: suffix,
                       priceText: price, changeText: change, rateText: rate, direction: direction,
                       detail: average + "・" + holding, detailLocked: average, url: WidgetLink.financeStocks)
    }
}

// MARK: 畫面（大）

/// Widget 的 closure 用這個分尺寸：大型 → StocksLargeEntryView；其他原封不動交給既有的 StocksWidgetEntryView
struct StocksWidgetRootView: View {
    let entry: StocksWidgetEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .systemLarge, let large = entry.large {
            StocksLargeEntryView(entry: entry, model: large)
        } else {
            StocksWidgetEntryView(entry: entry)
        }
    }
}

/// 大型：一句話 → StockWidgetMessage；其他 → StocksLargeBoard。整塊點了開股票頁
private struct StocksLargeEntryView: View {
    let entry: StocksWidgetEntry
    let model: StocksLargeModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    private var surface: WidgetPalette.Surface {
        WidgetPalette.Surface(renderingMode: renderingMode, showsBackground: showsBackground)
    }

    private var palette: WidgetPalette {
        WidgetPalette(colorScheme, mono: surface.isMono)
    }

    /// Mac 桌面沒聚焦：第二行只寫比均價、股利不畫
    private var vibrant: Bool {
        renderingMode == .vibrant
    }

    /// ↻：6 檔一起重抓（StandBy、一句話時不放）
    private var refreshIntent: RefreshQuotesIntent? {
        guard !surface.isStandBy, !model.stockIds.isEmpty else { return nil }
        return RefreshQuotesIntent(stockIds: model.stockIds, rateCodes: [])
    }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                background
            }
            .widgetURL(WidgetLink.financeStocks)
    }

    @ViewBuilder
    private var content: some View {
        if model.isMessage {
            StockWidgetMessage(text: model.message, palette: palette)
        } else {
            StocksLargeBoard(model: model, palette: palette, refresh: refreshIntent, vibrant: vibrant)
        }
    }

    /// 全彩畫天空（右上是 ↻，不放月牙／雲）；著色、StandBy 透明
    @ViewBuilder
    private var background: some View {
        if surface.drawsSky {
            WidgetSky(palette: palette, moon: WidgetSkyMoon.none)
        } else {
            Color.clear
        }
    }
}

/// 4 個候選由上往下挑（字級不變、只改兩行／一行與列數；不巢狀 ViewThatFits）
private struct StocksLargeBoard: View {
    let model: StocksLargeModel
    let palette: WidgetPalette
    let refresh: RefreshQuotesIntent?
    let vibrant: Bool

    var body: some View {
        ViewThatFits(in: .vertical) {
            StocksLargeColumn(model: model, candidate: model.candidate(at: 0), palette: palette, refresh: refresh,
                              vibrant: vibrant)
            StocksLargeColumn(model: model, candidate: model.candidate(at: 1), palette: palette, refresh: refresh,
                              vibrant: vibrant)
            StocksLargeColumn(model: model, candidate: model.candidate(at: 2), palette: palette, refresh: refresh,
                              vibrant: vibrant)
            StocksLargeColumn(model: model, candidate: model.candidate(at: 3), palette: palette, refresh: refresh,
                              vibrant: vibrant)
        }
    }
}

/// 表頭 → 列 → Spacer → 頁腳。每一塊固定高度（StocksLargeLayout.height 算的就是這一欄）
private struct StocksLargeColumn: View {
    let model: StocksLargeModel
    let candidate: StocksLargeCandidate
    let palette: WidgetPalette
    let refresh: RefreshQuotesIntent?
    let vibrant: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StocksLargeHeader(text: model.headerText, palette: palette, refresh: refresh)
                .frame(height: StocksLargeLayout.headerHeight)
            list
            Spacer(minLength: 0)
            StocksLargeFooter(text: vibrant ? "" : model.dividendLine, palette: palette)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var list: some View {
        VStack(spacing: StocksLargeLayout.rowSpacing) {
            ForEach(candidate.rows, id: \.id) { (row: StocksLargeRow) in
                StocksLargeRowView(row: row, palette: palette, twoLine: candidate.plan.twoLine, vibrant: vibrant)
            }
        }
        .padding(.top, StocksLargeLayout.listTopGap)
    }
}

/// 「股票　台股盤中・10:42」（點了開股票頁）＋右上 ↻
private struct StocksLargeHeader: View {
    let text: String
    let palette: WidgetPalette
    let refresh: RefreshQuotesIntent?

    var body: some View {
        HStack(spacing: 8) {
            Link(destination: WidgetLink.financeStocks) {
                titleLine
            }
            refreshButton
        }
    }

    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("股票")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(palette.ink)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.label)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var refreshButton: some View {
        if let intent = refresh {
            StocksLargeRefreshButton(palette: palette, intent: intent)
        }
    }
}

/// ↻：RefreshQuotesIntent 在小工具裡跑（不開 App），6 檔抓完寫快取、重畫
private struct StocksLargeRefreshButton: View {
    let palette: WidgetPalette
    let intent: RefreshQuotesIntent

    var body: some View {
        Button(intent: intent) {
            StocksLargeRefreshIcon(palette: palette)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("重抓報價")
    }
}

/// 36pt 的圓（膠囊底色；著色模式也看得到）
private struct StocksLargeRefreshIcon: View {
    let palette: WidgetPalette

    var body: some View {
        Image(systemName: "arrow.clockwise")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(palette.capsuleText)
            .frame(width: StocksLargeLayout.refreshSize, height: StocksLargeLayout.refreshSize)
            .background(Circle().fill(palette.capsuleFill))
            .contentShape(Circle())
    }
}

/// 一列（點了開那一檔）：卡片底＋兩行或一行
private struct StocksLargeRowView: View {
    let row: StocksLargeRow
    let palette: WidgetPalette
    let twoLine: Bool
    let vibrant: Bool

    private var height: CGFloat {
        twoLine ? StocksLargeLayout.twoLineRowHeight : StocksLargeLayout.oneLineRowHeight
    }

    var body: some View {
        Link(destination: row.url) {
            content
                .padding(.horizontal, 10)
                .frame(height: height)
                .background {
                    LargeWidgetCardBackground(palette: palette, cornerRadius: 10)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if twoLine {
            StocksLargeTwoLine(row: row, palette: palette, vibrant: vibrant)
        } else {
            StocksLargeOneLine(row: row, palette: palette)
        }
    }
}

/// 「2330」＋「台積電」＋「・05:00 收盤」（太長縮的是名字）
private struct StocksLargeName: View {
    let row: StocksLargeRow
    let palette: WidgetPalette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(row.code)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(palette.label)
                .fixedSize()
            nameText
            suffixText
        }
    }

    @ViewBuilder
    private var nameText: some View {
        if !row.name.isEmpty {
            Text(row.name)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var suffixText: some View {
        if !row.timeSuffix.isEmpty {
            Text(row.timeSuffix)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.label)
                .fixedSize()
        }
    }
}

/// 兩行：左「2330 台積電」／「比均價 +18%・2 張・NT$217萬」，右「1,085」／「▲13（+1.2%）」
private struct StocksLargeTwoLine: View {
    let row: StocksLargeRow
    let palette: WidgetPalette
    let vibrant: Bool

    var body: some View {
        HStack(spacing: 0) {
            left
            Spacer(minLength: 4)
            right
        }
    }

    private var left: some View {
        VStack(alignment: .leading, spacing: 1) {
            StocksLargeName(row: row, palette: palette)
            Text(vibrant ? row.detailLocked : row.detail)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var right: some View {
        VStack(alignment: .trailing, spacing: 1) {
            price
            Text(row.changeText)
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(palette.change(row.direction))
                .fixedSize()
        }
    }

    private var price: some View {
        Text(row.priceText)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(palette.ink)
            .fixedSize()
            .widgetAccentable()
    }
}

/// 一行：「2330 台積電｜1,085｜▲1.2%」（6 檔都在；放不下時用）
private struct StocksLargeOneLine: View {
    let row: StocksLargeRow
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 8) {
            StocksLargeName(row: row, palette: palette)
            Spacer(minLength: 4)
            price
            rate
        }
    }

    private var price: some View {
        Text(row.priceText)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(palette.ink)
            .fixedSize()
            .widgetAccentable()
    }

    private var rate: some View {
        Text(row.rateText)
            .font(.system(size: 11.5, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(palette.change(row.direction))
            .lineLimit(1)
            .fixedSize()
            .frame(minWidth: 52, alignment: .trailing)
    }
}

/// 頁腳「今年股利 NT$3.9萬・最近 10/5 配息 NT$530」；字空的（沒有、跨年、vibrant）不畫
private struct StocksLargeFooter: View {
    let text: String
    let palette: WidgetPalette

    var body: some View {
        if !text.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.label)
                Text(text)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: StocksLargeLayout.footerHeight,
                   maxHeight: StocksLargeLayout.footerHeight, alignment: .bottomLeading)
        }
    }
}
