import SwiftUI
import WidgetKit
import AppIntents

// MARK: - 淨資產（小、中＋鎖定畫面圓形、長方形）（小工具 v4）
//
// 只屬於「LifeGoodWidgets」target。由 G3 實作，規格見 scratchpad/widgets/v4/brief.md 的 G3-2；
// judge.md §2.8（J:330）、design_wealth.md W1（D:89-163）；主控定案 3、4、11。
// （主控建好的空檔，已登記 pbxproj：A01A000002000087／A01B000002000087）
//
// 只讀 finance_v1.json 的 netWorth（WidgetNetWorth）：App 用理財總覽頭部同一套（FinanceSnapshot.current＋
// FinanceHistory.series(months: 2)，**不寫每月紀錄**）算好、組好的字——「NT$1720萬」「比上月 ↑2%」
// 「總資產 NT$3795萬・貸款還欠 約 NT$2075萬」、各類金額與占幾成。**這個檔不算錢、不拼「NT$」**，也**不上網**。
//
// • 小：「淨資產　10 月／NT$1720萬／比上月 ↑2%」＋資產、貸款兩條（各類照占比分段、各自的主題色）。
// • 中：「淨資產 NT$1720萬　　比上月 ↑2%」／「總資產 …・貸款還欠 約 …」／兩條／左欄資產（最多 4 類）、
//   右欄貸款（最多 3 類，沒有寫「沒有貸款」），每列 圖示＋名稱＋金額；右下「股價 10/13 13:30」（淨資產裡股票是幾點的價）。
// • 鎖定畫面（系統單色）：圓形「淨資產」＋「↑2%」；長方形「淨資產」／「NT$1720萬」／「比上月 ↑2%」（沒有就「資產 4 類・10 月」）。
//   使用者決定（沿用 v2）：鎖定畫面可以放金額，照「隱藏金額」。
// • 跨月（D:158）：快照是 10 月的、現在已經 11/1（App 還沒開）→ 不寫「比上月」，改寫「10/31 的數字」（橘）：
//   不能拿 10 月的數字去比 9 月還當成 11 月。快照不是今天寫的（同一個月）也寫「10/11 的數字」。
// • 隱藏金額：大字、那一句、各類金額換成 mask／App 寫好的遮罩版（lineMasked），各類改寫占幾成（shareText）；
//   比上月 %、月份照常。遮起來時大字不標紅（不洩漏是負的）。
// • 顏色：比上月照理財圖表「紅漲綠跌」（palette.change，著色模式靠 ↑↓）；淨資產是負的大字紅（同理財總覽 bigTone .bad）。
// • 時間軸：now＋之後 7 個 00:00（跨月那天 00:00 一定在裡面），.atEnd；App 寫快照時會叫重畫。
// • 點了：整塊 → 理財總覽（lifegood://finance/overview）。
//
// 型別（internal 的都帶 NetWorthWidget 前綴或是 brief 指定的名字；畫面零件 private，也帶 NetWorthWidget 前綴）：
//   NetWorthWidget、NetWorthConfigIntent、NetWorthWidgetEntry、NetWorthWidgetProvider、NetWorthWidgetRow、
//   NetWorthWidgetModel、NetWorthWidgetSample、NetWorthWidgetEntryView

// MARK: - Widget

struct NetWorthWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.netWorth, intent: NetWorthConfigIntent.self,
                               provider: NetWorthWidgetProvider()) { entry in
            NetWorthWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("淨資產")
        .description("身家比上個月多還是少")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - 長按設定

/// 「淨資產」：金額要不要一律隱藏
struct NetWorthConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "淨資產"
    static var description = IntentDescription("金額要不要一律隱藏")

    @Parameter(title: "金額", default: .followMaster)
    var amount: WidgetAmountOption

    init() {}
}

// MARK: - Timeline

struct NetWorthWidgetEntry: TimelineEntry {
    /// 畫面一律拿這個當「現在」（不在 View 裡呼叫 Date()）
    let date: Date
    /// 有沒有 finance 快照（沒有＝還沒打開過新版 App）
    let hasSnapshot: Bool
    /// 沒有任何資產、也沒有貸款是 nil
    let netWorth: WidgetNetWorth?
    /// 長按設定的「金額」.hides(master: 總開關)（provider 讀一次）
    let hidesAmounts: Bool
    /// 快照的月份就是這一筆的月份（不是就不寫「比上月」）
    let isCurrentMonth: Bool
    /// 快照是不是今天寫的
    let isFromToday: Bool
    /// 跨月、或快照不是今天寫的：「10/31 的數字」（橘字）；不然空字串
    let staleText: String

    /// 時間軸排幾個 00:00
    static let midnightCount = 7

    /// 用那一筆的時間挑：同一個月嗎、今天的快照嗎
    static func make(date: Date, snapshot: WidgetFinanceSnapshot?, hidden: Bool) -> NetWorthWidgetEntry {
        guard let snap = snapshot else {
            return NetWorthWidgetEntry(date: date, hasSnapshot: false, netWorth: nil, hidesAmounts: hidden,
                                       isCurrentMonth: true, isFromToday: true, staleText: "")
        }
        let worth: WidgetNetWorth? = snap.netWorth
        let current: Bool = worth?.isCurrentMonth(at: date) ?? true
        let today: Bool = snap.isFromToday(at: date)
        let stale: String = (current && today) ? "" : WidgetDateText.figuresOf(snap.generatedAt)
        return NetWorthWidgetEntry(date: date, hasSnapshot: true, netWorth: worth, hidesAmounts: hidden,
                                   isCurrentMonth: current, isFromToday: today, staleText: stale)
    }
}

/// 不上網：只讀 finance 快照。每天 00:00 換一次（跨月不寫比上月、「10/11 的數字」）
struct NetWorthWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NetWorthWidgetEntry {
        NetWorthWidgetSample.entry(at: Date())
    }

    func snapshot(for configuration: NetWorthConfigIntent, in context: Context) async -> NetWorthWidgetEntry {
        let now = Date()
        if context.isPreview {
            return NetWorthWidgetSample.entry(at: now)
        }
        let hidden: Bool = configuration.amount.hides(master: WidgetHideAmounts.isOn)
        let snapshot = WidgetSnapshotStore.read(WidgetFinanceSnapshot.self)
        return NetWorthWidgetEntry.make(date: now, snapshot: snapshot, hidden: hidden)
    }

    func timeline(for configuration: NetWorthConfigIntent, in context: Context) async -> Timeline<NetWorthWidgetEntry> {
        let now = Date()
        let hidden: Bool = configuration.amount.hides(master: WidgetHideAmounts.isOn)
        let snapshot = WidgetSnapshotStore.read(WidgetFinanceSnapshot.self)
        let dates: [Date] = [now] + WidgetDateText.midnights(after: now, count: NetWorthWidgetEntry.midnightCount)
        let entries: [NetWorthWidgetEntry] = dates.map { date in
            NetWorthWidgetEntry.make(date: date, snapshot: snapshot, hidden: hidden)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

// MARK: - 畫面要的字（全部在這裡組好，body 只讀）

/// 中型的一列（一類資產或貸款）
struct NetWorthWidgetRow: Identifiable {
    let id: String
    let title: String
    let icon: String
    /// 「NT$3178萬」「約 NT$1800萬」；隱藏金額時「84%」
    let value: String
    let top: UInt32
    let bottom: UInt32
}

/// 淨資產要畫的字。金額字只有 App 寫好的（netWorthText、line、amountText）或 mask；這裡不算錢、不拼「NT$」
struct NetWorthWidgetModel {
    /// 中型左欄最多幾類資產、右欄最多幾類貸款
    static let maxAssets = 4
    static let maxDebts = 3

    /// 沒快照、沒有資產也沒有貸款：只寫一句話
    var isMessage = true
    var message = ""
    /// 「10 月」（這份數字是哪個月的）
    var monthText = ""
    /// 大字「NT$1720萬」；隱藏 mask
    var hero = ""
    /// 淨資產是負的（大字紅；隱藏時不標）
    var heroIsNegative = false
    /// 大字旁邊：「比上月 ↑2%」；跨月或沒有上個月、快照又舊了改寫「10/31 的數字」；都沒有空字串
    var headTrail = ""
    /// headTrail 是「10/31 的數字」（橘）不是比上月
    var headTrailIsStale = false
    /// 比上月的方向（1 漲、-1 跌、0 持平）：紅漲綠跌
    var direction = 0
    /// 大字旁邊已經寫了比上月、快照又不是今天的（同一個月）：右下另寫「10/11 的數字」
    var footStale = ""
    /// 「總資產 NT$3795萬・貸款還欠 約 NT$2075萬」；隱藏用 App 寫好的 lineMasked
    var line = ""
    /// 兩條的分段（各類的 share 與顏色）與長度
    var assetParts: [WidgetNetWorthPart] = []
    var debtParts: [WidgetNetWorthPart] = []
    var assetsBar: Double = 0
    var debtsBar: Double = 0
    /// 中型兩欄
    var assetRows: [NetWorthWidgetRow] = []
    var debtRows: [NetWorthWidgetRow] = []
    /// 中型右下：「股價 10/13 13:30」（淨資產裡股票用的是幾點的價）；不知道空字串
    var stockPriceText = ""
    /// 鎖定畫面圓形中間：「↑2%」「持平」；沒有（跨月、沒有上個月）「—」
    var circleText = "—"
    /// 鎖定畫面長方形第二、三行
    var rectLine2 = ""
    var rectLine3 = ""

    static func make(entry: NetWorthWidgetEntry) -> NetWorthWidgetModel {
        var m = NetWorthWidgetModel()
        guard entry.hasSnapshot else {
            m.message = "打開 LifeGood 一次，這裡就會出現淨資產"
            m.rectLine2 = m.message
            return m
        }
        guard let w = entry.netWorth else {
            m.message = "新增房地產、股票、保單或車子之後，這裡會算出淨資產"
            m.rectLine2 = m.message
            return m
        }
        let hidden: Bool = entry.hidesAmounts
        m.isMessage = false
        m.monthText = w.monthText
        m.hero = hidden ? WidgetHideAmounts.mask : w.netWorthText
        m.heroIsNegative = w.isNegative && !hidden
        m.line = hidden ? w.lineMasked : w.line
        m.assetParts = w.assets
        m.debtParts = w.debts
        m.assetsBar = w.assetsBar
        m.debtsBar = w.debtsBar
        m.assetRows = w.assets.prefix(maxAssets).map { row($0, hidden: hidden) }
        m.debtRows = w.debts.prefix(maxDebts).map { row($0, hidden: hidden) }
        if let at = w.stockPriceAt {
            m.stockPriceText = "股價 " + WidgetDateText.shortDate(at) + " " + DayTimelineFormat.time(at)
        }
        fillChange(&m, worth: w, entry: entry)
        m.rectLine2 = m.hero
        return m
    }

    /// 一類：隱藏金額時金額換成占幾成（「84%」）
    private static func row(_ part: WidgetNetWorthPart, hidden: Bool) -> NetWorthWidgetRow {
        NetWorthWidgetRow(id: part.key, title: part.title, icon: part.icon,
                          value: hidden ? part.shareText : part.amountText,
                          top: part.top, bottom: part.bottom)
    }

    /// 比上月：只在快照的月份＝這一筆的月份時寫（跨月不能比錯月份）；不寫的時候改寫「10/31 的數字」
    private static func fillChange(_ m: inout NetWorthWidgetModel, worth w: WidgetNetWorth,
                                   entry: NetWorthWidgetEntry) {
        let change: String = entry.isCurrentMonth ? (w.changeText ?? "") : ""
        let short: String = entry.isCurrentMonth ? (w.changeShort ?? "") : ""
        if !change.isEmpty {
            m.headTrail = change
            m.direction = w.changeDirection
            m.footStale = entry.staleText
        } else if !entry.staleText.isEmpty {
            m.headTrail = entry.staleText
            m.headTrailIsStale = true
        }
        m.circleText = short.isEmpty ? "—" : short
        if !change.isEmpty {
            m.rectLine3 = change
        } else if !entry.staleText.isEmpty {
            m.rectLine3 = entry.staleText
        } else {
            m.rectLine3 = w.summaryText
        }
    }
}

/// 小工具庫預覽與 placeholder 的樣本。**寫死的展示字**（D:97-122 的例子；% 照 App 的寫法是整數）
enum NetWorthWidgetSample {
    static func entry(at now: Date) -> NetWorthWidgetEntry {
        NetWorthWidgetEntry(date: now, hasSnapshot: true, netWorth: netWorth(at: now), hidesAmounts: false,
                            isCurrentMonth: true, isFromToday: true, staleText: "")
    }

    static func netWorth(at now: Date) -> WidgetNetWorth {
        let month: Int = Calendar.current.component(.month, from: now)
        return WidgetNetWorth(monthKey: WidgetDateText.monthKey(now),
                              monthText: "\(month) 月",
                              netWorthText: "NT$1720萬",
                              isNegative: false,
                              changeText: "比上月 ↑2%",
                              changeShort: "↑2%",
                              changeDirection: 1,
                              line: "總資產 NT$3795萬・貸款還欠 約 NT$2075萬",
                              lineMasked: "總資產 NT$ ••••・貸款還欠 約 NT$ ••••",
                              assets: assets,
                              debts: debts,
                              assetsBar: 1,
                              debtsBar: 0.547,
                              summaryText: "資產 4 類・\(month) 月",
                              stockPriceAt: nil)
    }

    private static let assets: [WidgetNetWorthPart] = [
        WidgetNetWorthPart(key: "realEstate", title: "房地產", icon: "house.fill", amountText: "NT$3178萬",
                           shareText: "84%", share: 0.837, top: 0xB79CFF, bottom: 0x6B4BE0),
        WidgetNetWorthPart(key: "stock", title: "股票", icon: "chart.line.uptrend.xyaxis", amountText: "NT$262萬",
                           shareText: "7%", share: 0.069, top: 0xFFB45E, bottom: 0xF07A2A),
        WidgetNetWorthPart(key: "vehicle", title: "載具", icon: "car.fill", amountText: "NT$260萬",
                           shareText: "7%", share: 0.069, top: 0x7FE3D0, bottom: 0x1A9C8C),
        WidgetNetWorthPart(key: "savings", title: "儲蓄險", icon: "shield.lefthalf.filled", amountText: "NT$95萬",
                           shareText: "3%", share: 0.025, top: 0x8EC5FF, bottom: 0x3A6FE0)
    ]

    private static let debts: [WidgetNetWorthPart] = [
        WidgetNetWorthPart(key: "mortgage", title: "房貸", icon: "house", amountText: "約 NT$1800萬",
                           shareText: "87%", share: 0.867, top: 0xB79CFF, bottom: 0x6B4BE0),
        WidgetNetWorthPart(key: "carLoan", title: "車貸", icon: "car", amountText: "約 NT$275萬",
                           shareText: "13%", share: 0.133, top: 0x7FE3D0, bottom: 0x1A9C8C)
    ]
}

// MARK: - 畫面

struct NetWorthWidgetEntryView: View {
    let entry: NetWorthWidgetEntry

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
        family == .accessoryCircular || family == .accessoryRectangular
    }

    var body: some View {
        let model = NetWorthWidgetModel.make(entry: entry)
        NetWorthWidgetContent(model: model, palette: palette, family: family)
            .containerBackground(for: .widget) {
                background
            }
            .widgetURL(WidgetLink.financeOverview)
    }

    /// 主畫面全彩畫天空（不放月牙／雲：右上是月份、比上月）；著色、StandBy、鎖定畫面透明
    @ViewBuilder
    private var background: some View {
        if surface.drawsSky && !isAccessory {
            WidgetSky(palette: palette, moon: WidgetSkyMoon.none)
        } else {
            Color.clear
        }
    }
}

/// 依尺寸、狀態挑版面（ViewBuilder 裡只比對 Bool 與 WidgetFamily）
private struct NetWorthWidgetContent: View {
    let model: NetWorthWidgetModel
    let palette: WidgetPalette
    let family: WidgetFamily

    var body: some View {
        if family == .accessoryCircular {
            NetWorthWidgetCircular(model: model)
        } else if family == .accessoryRectangular {
            NetWorthWidgetRect(model: model)
        } else if model.isMessage {
            NetWorthWidgetMessage(text: model.message, palette: palette)
        } else if family == .systemMedium {
            NetWorthWidgetMedium(model: model, palette: palette)
        } else {
            NetWorthWidgetSmall(model: model, palette: palette)
        }
    }
}

// MARK: 小

/// 「淨資產　10 月」／（空）／大字／比上月／兩條／「10/11 的數字」。放不下時先拿掉兩條
private struct NetWorthWidgetSmall: View {
    let model: NetWorthWidgetModel
    let palette: WidgetPalette

    var body: some View {
        ViewThatFits(in: .vertical) {
            column(showsBars: true)
            column(showsBars: false)
        }
    }

    private func column(showsBars: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            NetWorthWidgetTitleRow(month: model.monthText, palette: palette)
            Spacer(minLength: 2)
            NetWorthWidgetHero(text: model.hero, negative: model.heroIsNegative, palette: palette, size: 26)
            NetWorthWidgetTrail(model: model, palette: palette, size: 12)
            NetWorthWidgetSmallBars(model: model, palette: palette, shows: showsBars)
            NetWorthWidgetFootStale(text: model.footStale, palette: palette)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 「淨資產　　10 月」
private struct NetWorthWidgetTitleRow: View {
    let month: String
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 4) {
            Text("淨資產")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.ink)
            Spacer(minLength: 4)
            Text(month)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(palette.label)
        }
        .lineLimit(1)
    }
}

private struct NetWorthWidgetSmallBars: View {
    let model: NetWorthWidgetModel
    let palette: WidgetPalette
    let shows: Bool

    var body: some View {
        if shows {
            NetWorthWidgetBars(model: model, palette: palette, labelWidth: 22, height: 5)
                .padding(.top, 4)
        }
    }
}

/// 右下「10/11 的數字」（橘；大字旁邊已經寫了比上月、快照又不是今天的才有）
private struct NetWorthWidgetFootStale: View {
    let text: String
    let palette: WidgetPalette

    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.warn)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

// MARK: 中

/// 「淨資產 NT$1720萬　比上月 ↑2%」／那一句／兩條／左欄資產、右欄貸款。
/// 矮的中型放不下時依序：資產剩 3 類 → 拿掉那一句（ViewThatFits 由上往下挑）
private struct NetWorthWidgetMedium: View {
    let model: NetWorthWidgetModel
    let palette: WidgetPalette

    var body: some View {
        ViewThatFits(in: .vertical) {
            column(assetLimit: NetWorthWidgetModel.maxAssets, showsLine: true)
            column(assetLimit: 3, showsLine: true)
            column(assetLimit: 3, showsLine: false)
        }
    }

    private func column(assetLimit: Int, showsLine: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            NetWorthWidgetMediumHeader(model: model, palette: palette)
            NetWorthWidgetLine(text: showsLine ? model.line : "", palette: palette)
            NetWorthWidgetBars(model: model, palette: palette, labelWidth: 24, height: 6)
            NetWorthWidgetColumns(model: model, palette: palette, assetLimit: assetLimit)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct NetWorthWidgetMediumHeader: View {
    let model: NetWorthWidgetModel
    let palette: WidgetPalette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("淨資產")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.label)
                .fixedSize()
            NetWorthWidgetHero(text: model.hero, negative: model.heroIsNegative, palette: palette, size: 20)
                .layoutPriority(1)
            Spacer(minLength: 4)
            NetWorthWidgetTrail(model: model, palette: palette, size: 12)
        }
    }
}

/// 「總資產 NT$3795萬・貸款還欠 約 NT$2075萬」（空字串不畫）
private struct NetWorthWidgetLine: View {
    let text: String
    let palette: WidgetPalette

    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.label)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

/// 左欄資產（最多 assetLimit 類）、右欄貸款（最多 3 類，沒有寫「沒有貸款」）＋右下股價時間、舊數字
private struct NetWorthWidgetColumns: View {
    let model: NetWorthWidgetModel
    let palette: WidgetPalette
    let assetLimit: Int

    private var assets: [NetWorthWidgetRow] { Array(model.assetRows.prefix(assetLimit)) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(assets, id: \.id) { row in
                    NetWorthWidgetRowView(row: row, palette: palette)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            NetWorthWidgetDebtColumn(model: model, palette: palette)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct NetWorthWidgetDebtColumn: View {
    let model: NetWorthWidgetModel
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            debts
            Spacer(minLength: 0)
            NetWorthWidgetFoot(stock: model.stockPriceText, stale: model.footStale, palette: palette)
        }
    }

    @ViewBuilder
    private var debts: some View {
        if model.debtRows.isEmpty {
            Text("沒有貸款")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.label)
                .lineLimit(1)
        } else {
            ForEach(model.debtRows, id: \.id) { row in
                NetWorthWidgetRowView(row: row, palette: palette)
            }
        }
    }
}

/// 一類：圖示（各類主題色；著色模式靠圖示分）＋名稱＋金額（隱藏時占幾成）
private struct NetWorthWidgetRowView: View {
    let row: NetWorthWidgetRow
    let palette: WidgetPalette

    private var iconColor: Color {
        if palette.isMono { return palette.ink }
        return palette.isDark ? Color(widgetHex: row.top) : Color(widgetHex: row.bottom)
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: row.icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(iconColor)
                .frame(width: 14)
            Text(row.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.label)
                .lineLimit(1)
                .fixedSize()
            Text(row.value)
                .font(.system(size: 11.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// 右下小字：「股價 10/13 13:30」（灰）＋「10/11 的數字」（橘）；兩個都沒有不畫
private struct NetWorthWidgetFoot: View {
    let stock: String
    let stale: String
    let palette: WidgetPalette

    var body: some View {
        if !stock.isEmpty || !stale.isEmpty {
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                part(stock, color: palette.label)
                part(stale, color: palette.warn)
            }
            .font(.system(size: 9.5, weight: .semibold))
            .lineLimit(1)
        }
    }

    @ViewBuilder
    private func part(_ text: String, color: Color) -> some View {
        if !text.isEmpty {
            Text(text)
                .foregroundStyle(color)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: 小、中共用

/// 大字（著色模式染重點色）；淨資產是負的紅字（同理財總覽 bigTone .bad）
private struct NetWorthWidgetHero: View {
    let text: String
    let negative: Bool
    let palette: WidgetPalette
    let size: CGFloat

    private var color: Color { negative ? palette.bad : palette.ink }

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .widgetAccentable()
    }
}

/// 「比上月 ↑2%」或「10/31 的數字」（橘）；都沒有不畫。
/// [v25.549] 「比上月」跟理財總覽頭部的膠囊一樣不上紅綠（總覽沒上色，兩邊要一致），方向靠 ↑↓
private struct NetWorthWidgetTrail: View {
    let model: NetWorthWidgetModel
    let palette: WidgetPalette
    let size: CGFloat

    private var color: Color {
        model.headTrailIsStale ? palette.warn : palette.label
    }

    var body: some View {
        if !model.headTrail.isEmpty {
            Text(model.headTrail)
                .font(.system(size: size, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

/// 資產、貸款兩條（貸款沒有就只有資產那一條）
private struct NetWorthWidgetBars: View {
    let model: NetWorthWidgetModel
    let palette: WidgetPalette
    let labelWidth: CGFloat
    let height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            NetWorthWidgetBarRow(label: "資產", parts: model.assetParts, fraction: model.assetsBar,
                                 palette: palette, labelWidth: labelWidth, height: height)
            debtRow
        }
    }

    @ViewBuilder
    private var debtRow: some View {
        if !model.debtParts.isEmpty {
            NetWorthWidgetBarRow(label: "貸款", parts: model.debtParts, fraction: model.debtsBar,
                                 palette: palette, labelWidth: labelWidth, height: height)
        }
    }
}

private struct NetWorthWidgetBarRow: View {
    let label: String
    let parts: [WidgetNetWorthPart]
    let fraction: Double
    let palette: WidgetPalette
    let labelWidth: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.label)
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)
            NetWorthWidgetBar(parts: parts, fraction: fraction, palette: palette, height: height)
        }
    }
}

/// 一條：淡底＋塗 fraction 那麼長，裡面照各類的 share 分段（各類主題色；著色模式同一色、靠縫分開）
private struct NetWorthWidgetBar: View {
    let parts: [WidgetNetWorthPart]
    let fraction: Double
    let palette: WidgetPalette
    let height: CGFloat

    private let gap: CGFloat = 1.5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.barTrack)
                segments(total: geo.size.width)
            }
        }
        .frame(height: height)
    }

    private func segments(total: CGFloat) -> some View {
        HStack(spacing: gap) {
            ForEach(parts, id: \.id) { part in
                NetWorthWidgetSegment(part: part, palette: palette)
                    .frame(width: segmentWidth(part, total: total))
            }
        }
        .frame(width: filledWidth(total), alignment: .leading)
        .clipShape(Capsule())
    }

    /// 這一條塗多長（0…整條）
    private func filledWidth(_ total: CGFloat) -> CGFloat {
        let f: Double = fraction.isFinite ? min(1, max(0, fraction)) : 0
        return total * CGFloat(f)
    }

    /// 一段多長：塗的長度扣掉段與段之間的縫，照 share 分
    private func segmentWidth(_ part: WidgetNetWorthPart, total: CGFloat) -> CGFloat {
        let gaps: CGFloat = gap * CGFloat(max(0, parts.count - 1))
        let usable: CGFloat = max(0, filledWidth(total) - gaps)
        let share: Double = part.share.isFinite ? min(1, max(0, part.share)) : 0
        return usable * CGFloat(share)
    }
}

private struct NetWorthWidgetSegment: View {
    let part: WidgetNetWorthPart
    let palette: WidgetPalette

    private var gradient: LinearGradient {
        LinearGradient(colors: [Color(widgetHex: part.top), Color(widgetHex: part.bottom)],
                       startPoint: .leading, endPoint: .trailing)
    }

    var body: some View {
        if palette.isMono {
            Rectangle()
                .fill(palette.ink.opacity(0.8))
        } else {
            Rectangle()
                .fill(gradient)
        }
    }
}

/// 沒快照、沒有資產也沒有貸款：只寫一句話（小、中共用）
private struct NetWorthWidgetMessage: View {
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

// MARK: 鎖定畫面（系統單色，不指定顏色，只用 .secondary 分深淺）

/// 圓形：上小字「淨資產」、中間「↑2%」（跨月、沒有上個月「—」）
private struct NetWorthWidgetCircular: View {
    let model: NetWorthWidgetModel

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Text("淨資產")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(model.circleText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
            }
            .padding(.horizontal, 5)
        }
    }
}

/// 長方形三行：「淨資產」／「NT$1720萬」（重點色；一句話時是那句話）／「比上月 ↑2%」或「資產 4 類・10 月」
private struct NetWorthWidgetRect: View {
    let model: NetWorthWidgetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("淨資產")
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
            Text(model.rectLine2)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(2)
                .minimumScaleFactor(0.65)
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
