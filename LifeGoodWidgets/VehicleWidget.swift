import SwiftUI
import WidgetKit
import AppIntents

// MARK: - 我的車（小、中＋鎖定畫面圓形、長方形）（小工具 v4）
//
// 只屬於「LifeGoodWidgets」target。由 G3 實作，規格見 scratchpad/widgets/v4/brief.md 的 G3-1；
// judge.md §2.8（J:329）、design_wealth.md W4（D:317-370）；主控定案 10、11、14。
// （主控建好的空檔，已登記 pbxproj：A01A000002000086／A01B000002000086）
//
// 只讀 finance_v1.json 的 vehicles（WidgetFinanceVehicle）：每月養車、每度電、估值、車貸、接下來要扣的，
// 全部是 App 用 VehicleFacts 算好、組好的字。**這個檔不算錢、不拼「NT$」**，也**不上網**。
// 會隨日子變的只有三樣，都用契約的函式拿（日子、期數是整數，不是金額）：
//   • 車貸已繳幾期：WidgetVehicleLoan.paid(at:)／progressText(at:)／fraction(at:)（扣款日 00:00 起自己加一期）
//   • 「下一筆 11/5 車貸 第 26 期、停車月租」：WidgetFinanceVehicle.nextText(at:)（扣過的自己換下一筆）；
//     45 天內的都扣過了（App 太久沒開）改寫車貸下一期「12/5 車貸 第 27 期」（WidgetVehicleLoan.dues）
//   • 鎖定畫面圓形沒車貸時的「11/5」：nextShortDate(at:)
//
// • 小：「Taycan［車］／每月養車／約 NT$5,200／車貸 已繳 25／60 期 ▓▓░░／下一筆 11/5 車貸 第 26 期、停車月租」；
//   快照不是今天的右下橘字「10/11 的數字」。放不下時依序：下一筆縮一行 → 拿掉進度條 → 拿掉下一筆。
// • 中：左邊插畫（主題色漸層方塊＋車＋一條路）＋名字＋「電車」；右邊估值、每月養車、每度電、車貸進度（＋「2029/9 繳完」）、
//   下一筆、最下面兩顆按鈕（⚡ 記電費／🅿 記停車；油車、油電、機車 ⛽ 記加油）。按鈕＝共用檔的 LifeGoodOpenIntent
//  （openAppWhenRun，App 打開到新增支出、車子與分類帶好，你按儲存才算）。已售出沒有按鈕，大字的小標寫「已售出」。
// • 鎖定畫面（系統單色）：圓形有車貸＝進度環＋車＋「25／60」，沒車貸＝車＋「11/5」；
//   長方形「Taycan」／「每月養車 約 NT$5,200」／「下一筆 11/5 車貸 第 26 期」（沒有下一筆改寫車貸進度）。
//   使用者決定（沿用 v2）：鎖定畫面可以放金額與車名，照「隱藏金額」。
// • **插畫不用照片**（照片可能拍到車牌）：SF Symbol（快照的 symbol：car.fill／scooter）＋車子主題色
//  （電車 finElectric 綠、油車油電 finGas 藍、機車藍灰；色碼是 App 寫進快照的 top／bottom／tint）。著色模式改外框＋重點色。
// • 隱藏金額：每月養車、估值／成交換成 mask；每度電（單價）、期數、日期照常。估值的字是「估值 NT$260萬」整句，
//   換成 mask 會看不出是什麼，中型隱藏時那一行就不寫。
// • 時間軸：now＋之後 7 個 00:00，.atEnd；App 改了車子、記了帳會寫快照叫重畫。
// • 點了：整塊 → 那一台車的卡片（lifegood://finance/vehicle?id=）；沒車 → 載具頁；按鈕 → 新增支出。
//
// 型別（internal 的都帶 VehicleWidget 前綴或是 brief 指定的名字；畫面零件 private，也帶 VehicleWidget 前綴）：
//   VehicleWidget、VehicleConfigIntent、VehicleWidgetEntry、VehicleWidgetProvider、VehicleWidgetModel、
//   VehicleWidgetSample、VehicleWidgetEntryView

// MARK: - Widget

struct VehicleWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.vehicle, intent: VehicleConfigIntent.self,
                               provider: VehicleWidgetProvider()) { entry in
            VehicleWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("我的車")
        .description("每月養車、車貸繳到第幾期、下一筆扣什麼")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - 長按設定

/// 「我的車」：選哪一台、金額。車子 nil＝第一台沒賣掉的（選的車賣掉又扣完了、刪掉了也是，WidgetFinanceSnapshot.vehicle(id:)）
struct VehicleConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "我的車"
    static var description = IntentDescription("選哪一台車、金額要不要隱藏")

    @Parameter(title: "車子")
    var vehicle: WidgetVehicleEntity?

    @Parameter(title: "金額", default: .followMaster)
    var amount: WidgetAmountOption

    init() {}
}

// MARK: - Timeline

struct VehicleWidgetEntry: TimelineEntry {
    /// 畫面一律拿這個當「現在」（不在 View 裡呼叫 Date()）
    let date: Date
    /// 有沒有 finance 快照（沒有＝還沒打開過新版 App）
    let hasSnapshot: Bool
    /// 設定選的那一台（找不到用第一台沒賣掉的）；沒車 nil
    let vehicle: WidgetFinanceVehicle?
    /// 長按設定的「金額」.hides(master: 總開關)（provider 讀一次）
    let hidesAmounts: Bool
    /// 快照是不是今天寫的
    let isFromToday: Bool
    /// 快照不是今天寫的：「10/11 的數字」（橘字）；是今天的空字串
    let staleText: String

    /// 時間軸排幾個 00:00
    static let midnightCount = 7

    /// 用那一筆的時間挑：今天的快照嗎、要不要寫「10/11 的數字」
    static func make(date: Date, snapshot: WidgetFinanceSnapshot?, vehicleID: String?,
                     hidden: Bool) -> VehicleWidgetEntry {
        guard let snap = snapshot else {
            return VehicleWidgetEntry(date: date, hasSnapshot: false, vehicle: nil, hidesAmounts: hidden,
                                      isFromToday: true, staleText: "")
        }
        let today: Bool = snap.isFromToday(at: date)
        let stale: String = today ? "" : WidgetDateText.figuresOf(snap.generatedAt)
        return VehicleWidgetEntry(date: date, hasSnapshot: true, vehicle: snap.vehicle(id: vehicleID),
                                  hidesAmounts: hidden, isFromToday: today, staleText: stale)
    }
}

/// 不上網：只讀 finance 快照。每天 00:00 換一次（已繳幾期、下一筆）
struct VehicleWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> VehicleWidgetEntry {
        VehicleWidgetSample.entry(at: Date())
    }

    func snapshot(for configuration: VehicleConfigIntent, in context: Context) async -> VehicleWidgetEntry {
        let now = Date()
        if context.isPreview {
            return VehicleWidgetSample.entry(at: now)
        }
        let hidden: Bool = configuration.amount.hides(master: WidgetHideAmounts.isOn)
        let snapshot = WidgetSnapshotStore.read(WidgetFinanceSnapshot.self)
        return VehicleWidgetEntry.make(date: now, snapshot: snapshot, vehicleID: configuration.vehicle?.id,
                                       hidden: hidden)
    }

    func timeline(for configuration: VehicleConfigIntent, in context: Context) async -> Timeline<VehicleWidgetEntry> {
        let now = Date()
        let hidden: Bool = configuration.amount.hides(master: WidgetHideAmounts.isOn)
        let snapshot = WidgetSnapshotStore.read(WidgetFinanceSnapshot.self)
        let vehicleID: String? = configuration.vehicle?.id
        let dates: [Date] = [now] + WidgetDateText.midnights(after: now, count: VehicleWidgetEntry.midnightCount)
        let entries: [VehicleWidgetEntry] = dates.map { date in
            VehicleWidgetEntry.make(date: date, snapshot: snapshot, vehicleID: vehicleID, hidden: hidden)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

// MARK: - 畫面要的字（全部在這裡組好，body 只讀）

/// 一台車要畫的字。金額字只有 App 寫好的（monthlyText、valueText）或 mask；這裡不算錢、不拼「NT$」
struct VehicleWidgetModel {
    /// 沒快照、沒車：只寫一句話
    var isMessage = true
    var message = ""
    /// 整塊點了去哪：那一台；一句話時載具頁
    var url: URL = WidgetLink.financeVehicles
    /// 「Taycan」（一句話時「我的車」，鎖定畫面長方形第一行用）
    var name = "我的車"
    /// 中型名字下面：「電車」；快照不是今天的換成「10/11 的數字」（橘）
    var subText = ""
    var subIsStale = false
    /// 插畫：SF Symbol＋主題色（App 寫進快照的色碼）
    var symbol = "car.fill"
    var top: UInt32 = 0x7FE3D0
    var bottom: UInt32 = 0x1A9C8C
    var tint: UInt32 = 0x138A7E
    /// 大字上面的小標：「每月養車」；已售出「已售出」
    var heroLabel = ""
    /// 大字：「約 NT$5,200」；已售出「成交 NT$200萬」；隱藏 mask；沒有「—」
    var heroText = ""
    /// 中型：「估值 NT$260萬」；隱藏金額、已售出（已經在大字）是空字串
    var valueText = ""
    /// 中型：「每度電 NT$7.9」（單價，隱藏金額照常）；沒有空字串
    var energyText = ""
    /// 有車貸（有填年限的）
    var hasLoan = false
    /// 「車貸 已繳 25／60 期」「車貸繳清」「車貸 2026/11 開始」
    var loanText = ""
    /// 中型：「車貸 已繳 25／60 期・2029/9 繳完」（放不下退回 loanText）
    var loanDetail = ""
    /// 進度條、進度環 0…1
    var loanFraction: Double = 0
    /// 鎖定畫面圓形：「25／60」「繳清」
    var ringText = ""
    /// 「下一筆 11/5 車貸 第 26 期、停車月租」；沒有空字串
    var nextText = ""
    /// 下一筆是今天、明天（橘字）
    var nextIsSoon = false
    /// 鎖定畫面圓形沒車貸時：「11/5」
    var nextShortDate = ""
    /// 中型的兩顆按鈕（已售出沒有）
    var buttons: [WidgetVehicleButton] = []
    /// 快照不是今天的：「10/11 的數字」
    var staleText = ""
    /// 鎖定畫面長方形第二、三行
    var rectLine2 = ""
    var rectLine3 = ""

    static func make(entry: VehicleWidgetEntry) -> VehicleWidgetModel {
        var m = VehicleWidgetModel()
        guard entry.hasSnapshot else {
            m.message = "打開 LifeGood 一次，這裡就會出現你的車"
            m.rectLine2 = m.message
            return m
        }
        guard let v = entry.vehicle else {
            m.message = "還沒有車子"
            m.rectLine2 = m.message
            return m
        }
        m.isMessage = false
        m.url = v.url
        m.name = v.name
        m.symbol = v.symbol
        m.top = v.top
        m.bottom = v.bottom
        m.tint = v.tint
        m.staleText = entry.staleText
        m.subIsStale = !entry.staleText.isEmpty
        m.subText = m.subIsStale ? entry.staleText : v.powerText
        fillMoney(&m, vehicle: v, hidden: entry.hidesAmounts)
        fillLoan(&m, loan: v.loan, now: entry.date)
        fillNext(&m, vehicle: v, now: entry.date)
        m.buttons = v.isSold ? [] : v.buttons
        fillRect(&m, vehicle: v)
        return m
    }

    /// 金額欄：App 寫好的字原樣放；隱藏時整個換 mask
    private static func shown(_ text: String?, hidden: Bool) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return hidden ? WidgetHideAmounts.mask : text
    }

    private static func fillMoney(_ m: inout VehicleWidgetModel, vehicle v: WidgetFinanceVehicle, hidden: Bool) {
        if v.isSold {
            m.heroLabel = "已售出"
            m.heroText = shown(v.valueText, hidden: hidden) ?? "—"
            m.valueText = ""
        } else {
            m.heroLabel = "每月養車"
            m.heroText = shown(v.monthlyText, hidden: hidden) ?? "—"
            // 「估值 NT$260萬」整句換成 mask 會看不出是什麼，隱藏時不寫
            m.valueText = hidden ? "" : (v.valueText ?? "")
        }
        m.energyText = v.energyText ?? ""
    }

    private static func fillLoan(_ m: inout VehicleWidgetModel, loan: WidgetVehicleLoan?, now: Date) {
        guard let loan, loan.total > 0 else { return }
        m.hasLoan = true
        m.loanText = loan.progressText(at: now)
        m.loanFraction = loan.fraction(at: now)
        let paid: Int = loan.paid(at: now)
        let done: Bool = loan.isDone(at: now)
        m.ringText = done ? "繳清" : "\(paid)／\(loan.total)"
        if !done, paid > 0, let payoff = loan.payoffText {
            m.loanDetail = m.loanText + "・" + payoff
        } else {
            m.loanDetail = m.loanText
        }
    }

    private static func fillNext(_ m: inout VehicleWidgetModel, vehicle v: WidgetFinanceVehicle, now: Date) {
        if let next = v.nextText(at: now), let first = v.remainingDues(at: now).first {
            m.nextText = "下一筆 " + next
            m.nextIsSoon = WidgetDateText.isDueSoon(first.date, from: now)
            m.nextShortDate = v.nextShortDate(at: now) ?? ""
            return
        }
        // 45 天內要扣的都扣過了（App 太久沒開）：車貸接下來的扣款日快照裡還有（WidgetVehicleLoan.dues，最多 6 期），
        // 寫車貸那一期——11/5 過了 App 沒開也會換成「12/5 車貸 第 27 期」（brief §9.5）。日子、期數是整數，不是金額
        guard let due = nextLoanDue(v.loan, now: now) else { return }
        let day: String = WidgetDateText.shortDate(due.date)
        m.nextText = "下一筆 " + day + " 車貸 第 \(due.index) 期"
        m.nextIsSoon = WidgetDateText.isDueSoon(due.date, from: now)
        m.nextShortDate = day
    }

    /// 車貸今天（含）以後的第一期；沒有車貸、都扣完了 nil
    private static func nextLoanDue(_ loan: WidgetVehicleLoan?, now: Date) -> WidgetLoanDue? {
        guard let loan else { return nil }
        let today: Date = Calendar.current.startOfDay(for: now)
        return loan.dues.first { $0.date >= today }
    }

    /// 長方形：第二行每月養車（已售出「已售出」；沒有每月養車改寫車貸進度）；第三行下一筆（沒有就車貸進度）
    private static func fillRect(_ m: inout VehicleWidgetModel, vehicle v: WidgetFinanceVehicle) {
        if v.isSold {
            m.rectLine2 = "已售出"
        } else if shown(v.monthlyText, hidden: false) != nil {
            m.rectLine2 = "每月養車 " + m.heroText
        } else if m.hasLoan {
            m.rectLine2 = m.loanText
        } else {
            m.rectLine2 = v.powerText
        }
        if !m.nextText.isEmpty {
            m.rectLine3 = m.nextText
        } else if m.hasLoan && m.rectLine2 != m.loanText {
            m.rectLine3 = m.loanText
        }
    }
}

/// 小工具庫預覽與 placeholder 的樣本。**寫死的展示字**（D:325-349 的 Taycan，日子從今天起算）。
/// 網址只開載具頁、按鈕只開空白的新增支出（展示用的不連到任何一台車）
enum VehicleWidgetSample {
    static let sampleID = UUID(uuidString: "00000000-0000-0000-0000-00000000CA12") ?? UUID()

    static func entry(at now: Date) -> VehicleWidgetEntry {
        VehicleWidgetEntry(date: now, hasSnapshot: true, vehicle: vehicle(at: now), hidesAmounts: false,
                           isFromToday: true, staleText: "")
    }

    static func vehicle(at now: Date) -> WidgetFinanceVehicle {
        let today = Calendar.current.startOfDay(for: now)
        let due: Date = day(22, from: today)
        let loan = WidgetVehicleLoan(paid: 25, total: 60,
                                     dues: [WidgetLoanDue(date: due, index: 26)],
                                     payoffText: "2029/9 繳完", startText: nil)
        let dues: [WidgetVehicleDue] = [
            WidgetVehicleDue(id: "sample-parking", date: due, title: "停車月租", periodText: nil,
                             amountText: "NT$4,999"),
            WidgetVehicleDue(id: "sample-loan", date: due, title: "車貸", periodText: "第 26 期",
                             amountText: "NT$3.2萬")
        ]
        let add: String = WidgetLink.addExpense().absoluteString
        let buttons: [WidgetVehicleButton] = [
            WidgetVehicleButton(categoryKey: "sample-energy", title: "記電費", icon: "bolt.fill", link: add),
            WidgetVehicleButton(categoryKey: "sample-parking", title: "記停車", icon: "parkingsign.circle", link: add)
        ]
        return WidgetFinanceVehicle(id: sampleID, name: "Taycan", power: .electric, powerText: "電車",
                                    isSold: false, top: 0x7FE3D0, bottom: 0x1A9C8C, tint: 0x138A7E,
                                    symbol: "car.fill", monthlyText: "約 NT$5,200", energyText: "每度電 NT$7.9",
                                    valueText: "估值 NT$260萬", loan: loan, upcoming: dues, buttons: buttons,
                                    link: WidgetLink.financeVehicles.absoluteString)
    }

    private static func day(_ offset: Int, from today: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: today)
            ?? today.addingTimeInterval(TimeInterval(offset) * 24 * 3600)
    }
}

// MARK: - 畫面

struct VehicleWidgetEntryView: View {
    let entry: VehicleWidgetEntry

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
        let model = VehicleWidgetModel.make(entry: entry)
        VehicleWidgetContent(model: model, palette: palette, family: family)
            .containerBackground(for: .widget) {
                background
            }
            .widgetURL(model.url)
    }

    /// 主畫面全彩畫天空（不放月牙／雲：右上是插畫、右半全是字）；著色、StandBy、鎖定畫面透明
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
private struct VehicleWidgetContent: View {
    let model: VehicleWidgetModel
    let palette: WidgetPalette
    let family: WidgetFamily

    var body: some View {
        if family == .accessoryCircular {
            VehicleWidgetCircular(model: model)
        } else if family == .accessoryRectangular {
            VehicleWidgetRect(model: model)
        } else if model.isMessage {
            VehicleWidgetMessage(text: model.message, palette: palette)
        } else if family == .systemMedium {
            VehicleWidgetMedium(model: model, palette: palette)
        } else {
            VehicleWidgetSmall(model: model, palette: palette)
        }
    }
}

/// 車子主題色的重點（進度條）：淺色用 tint、深色用 top（深底上 tint 太暗）；著色模式、StandBy 用 ink
private enum VehicleWidgetInk {
    static func accent(_ model: VehicleWidgetModel, palette: WidgetPalette) -> Color {
        if palette.isMono { return palette.ink }
        return palette.isDark ? Color(widgetHex: model.top) : Color(widgetHex: model.tint)
    }
}

// MARK: 小

/// 名字＋插畫／（空）／每月養車＋大字／車貸進度＋條／下一筆／「10/11 的數字」。
/// 小螢幕放不下時依序：下一筆縮一行 → 拿掉進度條 → 拿掉下一筆（ViewThatFits 由上往下挑）
private struct VehicleWidgetSmall: View {
    let model: VehicleWidgetModel
    let palette: WidgetPalette

    var body: some View {
        ViewThatFits(in: .vertical) {
            column(nextLines: 2, showsBar: true)
            column(nextLines: 1, showsBar: true)
            column(nextLines: 1, showsBar: false)
            column(nextLines: 0, showsBar: false)
        }
    }

    private func column(nextLines: Int, showsBar: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            VehicleWidgetTitleRow(model: model, palette: palette)
            Spacer(minLength: 2)
            VehicleWidgetHero(label: model.heroLabel, text: model.heroText, palette: palette, size: 22)
            VehicleWidgetLoanLine(model: model, palette: palette, showsBar: showsBar, detail: false)
            VehicleWidgetNextLine(model: model, palette: palette, lines: nextLines)
            VehicleWidgetStaleLine(text: model.staleText, palette: palette)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 小型第一列：左名字、右小插畫
private struct VehicleWidgetTitleRow: View {
    let model: VehicleWidgetModel
    let palette: WidgetPalette

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(model.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            VehicleWidgetArt(model: model, palette: palette, width: 36, height: 26, iconSize: 13)
        }
    }
}

// MARK: 中

/// 左：插畫＋名字＋「電車」；右：估值、每月養車、每度電、車貸、下一筆、兩顆按鈕
private struct VehicleWidgetMedium: View {
    let model: VehicleWidgetModel
    let palette: WidgetPalette

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VehicleWidgetMediumSide(model: model, palette: palette)
                .frame(width: 100)
            VehicleWidgetMediumMain(model: model, palette: palette)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct VehicleWidgetMediumSide: View {
    let model: VehicleWidgetModel
    let palette: WidgetPalette

    private var subColor: Color { model.subIsStale ? palette.warn : palette.label }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            VehicleWidgetArt(model: model, palette: palette, width: 100, height: 66, iconSize: 28)
            Spacer(minLength: 2)
            Text(model.name)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(model.subText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(subColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 右半。矮的中型放不下時依序拿掉：估值 → 每度電 → 進度條（ViewThatFits 由上往下挑）
private struct VehicleWidgetMediumMain: View {
    let model: VehicleWidgetModel
    let palette: WidgetPalette

    var body: some View {
        ViewThatFits(in: .vertical) {
            column(showsValue: true, showsEnergy: true, showsBar: true)
            column(showsValue: false, showsEnergy: true, showsBar: true)
            column(showsValue: false, showsEnergy: false, showsBar: true)
            column(showsValue: false, showsEnergy: false, showsBar: false)
        }
    }

    private func column(showsValue: Bool, showsEnergy: Bool, showsBar: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            VehicleWidgetPlainLine(text: showsValue ? model.valueText : "", color: palette.label)
            VehicleWidgetMoneyRow(model: model, palette: palette)
            VehicleWidgetPlainLine(text: showsEnergy ? model.energyText : "", color: palette.inkSoft)
            VehicleWidgetLoanLine(model: model, palette: palette, showsBar: showsBar, detail: true)
            VehicleWidgetNextLine(model: model, palette: palette, lines: 1)
            Spacer(minLength: 0)
            VehicleWidgetButtonRow(model: model, palette: palette)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 中型「每月養車 約 NT$5,200」（小標＋粗字同一行）；已售出「已售出 成交 NT$200萬」
private struct VehicleWidgetMoneyRow: View {
    let model: VehicleWidgetModel
    let palette: WidgetPalette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(model.heroLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.label)
                .lineLimit(1)
                .fixedSize()
            Text(model.heroText)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
        }
    }
}

/// 一行小字（空字串不畫）
private struct VehicleWidgetPlainLine: View {
    let text: String
    let color: Color

    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// 最下面兩顆按鈕（已售出沒有）
private struct VehicleWidgetButtonRow: View {
    let model: VehicleWidgetModel
    let palette: WidgetPalette

    var body: some View {
        if !model.buttons.isEmpty {
            HStack(spacing: 6) {
                ForEach(model.buttons, id: \.id) { button in
                    VehicleWidgetActionButton(button: button, model: model, palette: palette)
                }
            }
        }
    }
}

/// 「⚡ 記電費」：打開 App 的新增支出、車子與分類帶好（共用檔的 LifeGoodOpenIntent，openAppWhenRun）。
/// 底是車子主題色的漸層（同記帳台的卡）；著色模式只畫外框
private struct VehicleWidgetActionButton: View {
    let button: WidgetVehicleButton
    let model: VehicleWidgetModel
    let palette: WidgetPalette

    private var ink: Color { palette.isMono ? palette.ink : palette.tileInk }

    var body: some View {
        Button(intent: LifeGoodOpenIntent(url: button.url)) {
            VehicleWidgetActionLabel(title: button.title, icon: button.icon, ink: ink)
                .background {
                    LedgerDeskCardBackground(top: model.top, bottom: model.bottom, plain: false,
                                             palette: palette, cornerRadius: 11)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct VehicleWidgetActionLabel: View {
    let title: String
    let icon: String
    let ink: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
    }
}

// MARK: 小、中共用

/// 插畫：車子主題色的漸層圓角方塊＋白色的車＋一條路（不用照片）。著色模式只畫外框、車染重點色
private struct VehicleWidgetArt: View {
    let model: VehicleWidgetModel
    let palette: WidgetPalette
    let width: CGFloat
    let height: CGFloat
    let iconSize: CGFloat

    private var iconColor: Color { palette.isMono ? palette.ink : palette.tileInk }

    var body: some View {
        ZStack {
            LedgerDeskCardBackground(top: model.top, bottom: model.bottom, plain: false,
                                     palette: palette, cornerRadius: height * 0.28)
            VehicleWidgetCarMark(symbol: model.symbol, size: iconSize, color: iconColor)
        }
        .frame(width: width, height: height)
    }
}

/// 車（快照的 SF Symbol：car.fill／scooter）＋車底下一條淡淡的路
private struct VehicleWidgetCarMark: View {
    let symbol: String
    let size: CGFloat
    let color: Color

    private var roadWidth: CGFloat { size * 1.7 }
    private var roadHeight: CGFloat { max(1.5, size * 0.09) }

    var body: some View {
        VStack(spacing: size * 0.12) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(color)
                .widgetAccentable()
            Capsule()
                .fill(color.opacity(0.55))
                .frame(width: roadWidth, height: roadHeight)
        }
    }
}

/// 大字（小型）：上面小標「每月養車」，下面「約 NT$5,200」（著色模式染重點色）
private struct VehicleWidgetHero: View {
    let label: String
    let text: String
    let palette: WidgetPalette
    let size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.label)
                .lineLimit(1)
            Text(text)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .widgetAccentable()
        }
    }
}

/// 車貸進度：「車貸 已繳 25／60 期」＋進度條（沒有車貸不畫）。
/// detail（中型）先試「・2029/9 繳完」，放不下退回只寫進度
private struct VehicleWidgetLoanLine: View {
    let model: VehicleWidgetModel
    let palette: WidgetPalette
    let showsBar: Bool
    let detail: Bool

    var body: some View {
        if model.hasLoan {
            VStack(alignment: .leading, spacing: 2) {
                loanText
                bar
            }
        }
    }

    @ViewBuilder
    private var loanText: some View {
        if detail {
            ViewThatFits(in: .horizontal) {
                line(model.loanDetail)
                line(model.loanText)
            }
        } else {
            line(model.loanText)
        }
    }

    @ViewBuilder
    private var bar: some View {
        if showsBar {
            VehicleWidgetBar(fraction: model.loanFraction,
                             fill: VehicleWidgetInk.accent(model, palette: palette),
                             track: palette.barTrack)
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(palette.inkSoft)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// 進度條：淡底＋主題色（著色模式染重點色）
private struct VehicleWidgetBar: View {
    let fraction: Double
    let fill: Color
    let track: Color
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(track)
                Capsule()
                    .fill(fill)
                    .frame(width: filledWidth(geo.size.width))
                    .widgetAccentable()
            }
        }
        .frame(height: height)
    }

    /// 塗多長：有繳就至少一個圓頭那麼長，0 期不塗
    private func filledWidth(_ total: CGFloat) -> CGFloat {
        let f: Double = fraction.isFinite ? min(1, max(0, fraction)) : 0
        guard f > 0 else { return 0 }
        return max(height, total * CGFloat(f))
    }
}

/// 「下一筆 11/5 車貸 第 26 期、停車月租」：今天、明天要扣的橘字（D §1.4），其他灰字
private struct VehicleWidgetNextLine: View {
    let model: VehicleWidgetModel
    let palette: WidgetPalette
    let lines: Int

    private var color: Color { model.nextIsSoon ? palette.warn : palette.label }

    var body: some View {
        if lines > 0 && !model.nextText.isEmpty {
            Text(model.nextText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(lines)
                .minimumScaleFactor(0.8)
        }
    }
}

/// 右下「10/11 的數字」（橘；快照是今天的不畫）
private struct VehicleWidgetStaleLine: View {
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

/// 沒快照、沒車：只寫一句話（小、中共用）
private struct VehicleWidgetMessage: View {
    let text: String
    let palette: WidgetPalette

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "car.fill")
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

/// 圓形：有車貸＝進度環＋車＋「25／60」；沒車貸＝車＋下一筆的日子「11/5」
private struct VehicleWidgetCircular: View {
    let model: VehicleWidgetModel

    private var iconSize: CGFloat { model.hasLoan ? 14 : 18 }
    private var caption: String { model.hasLoan ? model.ringText : model.nextShortDate }

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            ring
            VStack(spacing: 1) {
                Image(systemName: model.symbol)
                    .font(.system(size: iconSize, weight: .semibold))
                captionText
            }
            .padding(.horizontal, 7)
        }
    }

    @ViewBuilder
    private var ring: some View {
        if model.hasLoan {
            VehicleWidgetRing(value: model.loanFraction)
        }
    }

    @ViewBuilder
    private var captionText: some View {
        if !caption.isEmpty {
            Text(caption)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

/// 底環（淡）＋車貸進度（圓頭線，從 12 點鐘方向順時針；同「已花」圓形的畫法，不用 Gauge）
private struct VehicleWidgetRing: View {
    let value: Double

    private let lineWidth: CGFloat = 4

    private var progress: CGFloat {
        CGFloat(value.isFinite ? min(1, max(0, value)) : 0)
    }

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

/// 長方形三行：「Taycan」（快照舊了右邊「10/11 的數字」）／「每月養車 約 NT$5,200」（重點色）／「下一筆 11/5 車貸 第 26 期」
private struct VehicleWidgetRect: View {
    let model: VehicleWidgetModel

    /// 一句話（還沒打開 App、沒車）才准折兩行；平常三行各一行，第二行折行會把第三行擠出長方形
    private var line2Limit: Int { model.isMessage ? 2 : 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            VehicleWidgetRectTitle(name: model.name, stale: model.staleText)
            Text(model.rectLine2)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .lineLimit(line2Limit)
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
                .minimumScaleFactor(0.75)
        }
    }
}

private struct VehicleWidgetRectTitle: View {
    let name: String
    let stale: String

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 2)
            staleText
        }
    }

    @ViewBuilder
    private var staleText: some View {
        if !stale.isEmpty {
            Text(stale)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}
