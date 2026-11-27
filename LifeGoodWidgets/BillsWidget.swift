import SwiftUI
import WidgetKit
import AppIntents

// MARK: - 接下來要繳（systemMedium）（小工具 v2）
//
// 只屬於「LifeGoodWidgets」target。規格見 scratchpad/widgets/v2/brief.md 的 G3-5；
// 樣稿 mock_spec bills-medium（J:234-281）。
//
// 只讀 bills_v1.json（WidgetBillsSnapshot）：App 已經把記帳的固定支出與理財的房貸、車貸、保費、滿期
// 合成一份今天＋45 天的清單、去重、排好、金額字組好。這裡只挑「接下來 30 天」（upcoming(at:)）來畫：
//   標題列「接下來 30 天　6 件」（整列 → 固定支出頁）、最多 3 列（每列 → 那一筆）、「再來 …… 等 3 件」。
// **只寫件數、不寫合計**（J:256）；金額欄隱藏時整個換成 WidgetHideAmounts.mask。
//
// 換日：timeline 從明天起每天 00:00 一筆，到 horizonEnd 為止；「2 天後 → 明天扣款 → 今天扣款 → 拿掉」
// 由 entry.date 跟扣款日的日曆天差算（WidgetDateText.dueText／isDueSoon，日差不是金額），不用開 App。
//
// [v3] 長按可設定（AppIntentConfiguration＋BillsConfigIntent，WidgetConfigs.swift；kind 不變）：
//   範圍 全部（預設）／只看記帳固定支出／只看理財；天數 30（預設）／7；金額 跟著總開關（預設）／一律隱藏。
//   清單＝upcoming(at:days:scope:)、空的時候「下一筆」＝next(at:scope:)；標題「接下來 7 天」、空的「7 天內沒有要扣的」。
//   預設值＝v2 一模一樣。標題列的連結照舊開固定支出頁（「只看理財」也一樣，v4 才有理財總覽網址）。
//
// [財富 v4] v25.565（build/v4/brief.md G2-13；judge §6.5、§7.1）：清單多兩種，App 寫好的（WidgetBillsBuilder）——
//   卡費（.cardBill：「CUBE 卡費」「自己繳・含 Netflix」「NT$18,600」；刷卡的定期扣款併在裡面，Netflix 不再另外一列）、
//   交割（.settlement：「元大證券 交割」「從薪轉扣」）。點那一列開那張卡／那個帳戶（WidgetLink.wealth）。
//   這裡的邏輯不用改：主畫面寫卡名＋金額（照「隱藏金額」，judge §7.1 允許）；只有 systemMedium，不會上 StandBy。
//   範圍「只看記帳」也列卡費（WidgetBillScope.ledger：記帳的定期扣款併在卡費裡）。
//   鎖定畫面「下一筆要繳」碰到這兩種只寫「卡費」「交割」、不寫金額（LockScreenWidgets.swift）。
//   [財富 v4 審查] 保險：放在 iPad 鎖定畫面（vibrant；Mac 桌面沒聚焦時也是 vibrant）時，卡費、交割那幾列照鎖定畫面的規矩
//   ——名稱換類別字（lockedTitle「卡費」「交割」）、不寫小字（扣款帳戶暱稱）、不寫金額（judge §7.1：鎖定畫面不放卡名、金額）。
//   全彩（主畫面、今天視圖）照舊。記帳、理財那幾件不受影響（跟 v3 一樣）。
//
// 型別（internal 的都帶 Bills 前綴；畫面零件 private）：
//   BillsWidget、BillsWidgetEntry、BillsWidgetProvider、BillsTimeline（鎖定畫面「下一筆要繳」共用）、
//   BillsSample（同）、BillsWidgetEntryView

// MARK: - Widget

struct BillsWidget: Widget {
    var body: some WidgetConfiguration {
        // [v3] StaticConfiguration → AppIntentConfiguration（kind 不變：已經放好的升級後用預設值、外觀一樣）
        AppIntentConfiguration(kind: WidgetKind.bills, intent: BillsConfigIntent.self,
                               provider: BillsWidgetProvider()) { entry in
            BillsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("接下來要繳")
        .description("30 天內哪天要扣什麼錢；大的照這週、下週分開列")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Timeline

struct BillsWidgetEntry: TimelineEntry {
    /// 畫面一律拿這個當「現在」
    let date: Date
    /// nil＝還沒打開過新版 App（或檔案讀不到）
    let snapshot: WidgetBillsSnapshot?
    /// 「隱藏金額」開著（provider 讀一次）。
    /// [v3] ＝長按設定的「金額」.hides(master: 總開關)：一律隱藏、或總開關開著
    let hidesAmounts: Bool
    /// [v3] 長按設定的範圍（預設全部＝v2）
    var scope: WidgetBillScope = .all
    /// [v3] 長按設定的天數（預設 30＝v2）
    var days: Int = WidgetBillsSnapshot.listDays
}

/// [v3] TimelineProvider → AppIntentTimelineProvider（多讀長按設定；排程照舊 BillsTimeline）
struct BillsWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BillsWidgetEntry {
        let now = Date()
        return BillsWidgetEntry(date: now, snapshot: BillsSample.snapshot(at: now), hidesAmounts: false)
    }

    func snapshot(for configuration: BillsConfigIntent, in context: Context) async -> BillsWidgetEntry {
        let now = Date()
        if context.isPreview {
            return BillsWidgetEntry(date: now, snapshot: BillsSample.snapshot(at: now), hidesAmounts: false)
        }
        let snapshot = WidgetSnapshotStore.read(WidgetBillsSnapshot.self)
        let hidden: Bool = configuration.amount.hides(master: WidgetHideAmounts.isOn)
        return BillsWidgetEntry(date: now, snapshot: snapshot, hidesAmounts: hidden,
                                scope: configuration.scope.scope, days: configuration.days.days)
    }

    func timeline(for configuration: BillsConfigIntent, in context: Context) async -> Timeline<BillsWidgetEntry> {
        let now = Date()
        let snapshot = WidgetSnapshotStore.read(WidgetBillsSnapshot.self)
        let hidden: Bool = configuration.amount.hides(master: WidgetHideAmounts.isOn)
        let scope: WidgetBillScope = configuration.scope.scope
        let days: Int = configuration.days.days
        let dates = BillsTimeline.entryDates(snapshot: snapshot, now: now)
        let entries: [BillsWidgetEntry] = dates.map {
            BillsWidgetEntry(date: $0, snapshot: snapshot, hidesAmounts: hidden, scope: scope, days: days)
        }
        let policy = BillsTimeline.policy(snapshot: snapshot, dates: dates, now: now)
        return Timeline(entries: entries, policy: policy)
    }
}

/// 接下來要繳（中）與鎖定畫面「下一筆要繳」哪些時間點要換畫面
enum BillsTimeline {
    /// 最多排幾個 00:00（horizonEnd 是今天＋45 天，留一點餘裕）
    static let maxMidnights = 60

    /// now；明天起每天 00:00 到 horizonEnd（含）；快照變舊的那一刻（比 now 晚才放）。沒快照只有 now。
    static func entryDates(snapshot: WidgetBillsSnapshot?, now: Date) -> [Date] {
        guard let snap = snapshot else { return [now] }
        var dates: Set<Date> = [now]
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var midnight: Date? = cal.date(byAdding: .day, value: 1, to: today)
        var count = 0
        while let m = midnight, m <= snap.horizonEnd, count < maxMidnights {
            dates.insert(m)
            midnight = cal.date(byAdding: .day, value: 1, to: m)
            count += 1
        }
        // isStale 是「超過」兩天（>），多 1 秒才會翻過去
        let stale = snap.generatedAt.addingTimeInterval(WidgetFreshness.moneyStaleAfter + 1)
        if stale > now {
            dates.insert(stale)
        }
        return dates.sorted()
    }

    /// 沒快照：.never（App 第一次寫完會叫重畫）。有快照：最後一筆（horizonEnd）過了再要一次
    static func policy(snapshot: WidgetBillsSnapshot?, dates: [Date], now: Date) -> TimelineReloadPolicy {
        guard snapshot != nil, let last = dates.last, last > now else { return .never }
        return .after(last)
    }
}

// MARK: - 畫面要的字（全部在這裡組好，body 只讀）

/// 一列（一筆要扣的錢）
private struct BillsWidgetRow: Identifiable {
    let id: String
    let title: String
    /// 今天／明天要扣的「今天扣款」「明天扣款」（橘）；其他是空字串
    let lead: String
    /// 「10/15 (週四)・2 天後・每月」；lead 有字時只剩「・第 8／480 期」
    let rest: String
    /// 「NT$390」；隱藏金額時 mask；會領回的前面加「★ 」
    let amount: String
    let isIncome: Bool
    let tint: UInt32
    let tintDark: UInt32
    let url: URL
}

private struct BillsWidgetModel {
    enum Kind {
        /// 一句話（沒快照、超過 horizonEnd）
        case message
        /// 30 天內沒有要扣的
        case empty
        /// 清單
        case list
    }

    var kind: Kind = .message
    var message = ""
    /// 「接下來 30 天」
    var header = ""
    /// 「6 件」（清單才有；30 天內沒有時空字串）
    var countText = ""
    var rows: [BillsWidgetRow] = []
    /// 列了 3 列時的最下面一行「再來 10/28 美元保單、11/5 Taycan 車貸 等 3 件」
    var moreAfterThree = ""
    /// 放不下只列 2 列時的那一行
    var moreAfterTwo = ""
    var emptyTitle = ""
    /// 「下一筆 11/15 (週日) Netflix NT$390」
    var emptyNext = ""
    /// 超過兩天沒更新：「上次更新 10/11」
    var staleText = ""

    /// 只挑字、不算錢：日期字與日差由 WidgetDateText 組，金額字是 App 寫好的。
    /// [v3] scope／days：長按設定的範圍、天數（預設全部／30＝v2）
    /// [財富 v4 審查] lockScreen：放在鎖定畫面（vibrant）——卡費、交割只寫類別字、不寫小字與金額
    static func make(snapshot: WidgetBillsSnapshot?, now: Date, hidden: Bool,
                     scope: WidgetBillScope = .all,
                     days: Int = WidgetBillsSnapshot.listDays,
                     lockScreen: Bool = false) -> BillsWidgetModel {
        var model = BillsWidgetModel()
        guard let snap = snapshot else {
            model.message = "打開 LifeGood 一次，這裡就會出現接下來要扣的錢"
            return model
        }
        guard !snap.hasEnded(at: now) else {
            model.message = "打開 LifeGood 更新接下來要繳"
            return model
        }
        if snap.isStale(at: now) {
            model.staleText = WidgetDateText.lastUpdated(snap.generatedAt)
        }
        let list = snap.upcoming(at: now, days: days, scope: scope)
        model.header = "接下來 \(days) 天"
        guard !list.isEmpty else {
            model.kind = .empty
            model.emptyTitle = "\(days) 天內沒有要扣的"
            if let next = snap.next(at: now, scope: scope) {
                model.emptyNext = nextText(next, hidden: hidden, lockScreen: lockScreen)
            }
            return model
        }
        model.kind = .list
        model.countText = "\(list.count) 件"
        model.rows = list.prefix(3).map { row($0, now: now, hidden: hidden, lockScreen: lockScreen) }
        model.moreAfterThree = moreText(Array(list.dropFirst(3)), lockScreen: lockScreen)
        model.moreAfterTwo = moreText(Array(list.dropFirst(2)), lockScreen: lockScreen)
        return model
    }

    /// [財富 v4 審查] 這一筆在鎖定畫面上要不要收起來：卡費、交割（WidgetBillKind.isWealth）放在鎖定畫面時
    private static func isLocked(_ bill: WidgetBill, lockScreen: Bool) -> Bool {
        lockScreen && bill.kind.isWealth
    }

    /// [財富 v4 審查] 名稱：收起來的寫類別字（「卡費」「交割」），其他照 App 寫的
    private static func shownTitle(_ bill: WidgetBill, lockScreen: Bool) -> String {
        isLocked(bill, lockScreen: lockScreen) ? bill.lockedTitle : bill.title
    }

    /// 「下一筆 11/15 (週日) Netflix NT$390」。[財富 v4 審查] 鎖定畫面的卡費、交割：「下一筆 10/27 (週二) 卡費」
    private static func nextText(_ bill: WidgetBill, hidden: Bool, lockScreen: Bool) -> String {
        let date: String = WidgetDateText.billDate(bill.dueDate)
        let name: String = shownTitle(bill, lockScreen: lockScreen)
        if isLocked(bill, lockScreen: lockScreen) {
            return "下一筆 \(date) \(name)"
        }
        let amount: String = amountText(bill, hidden: hidden)
        return "下一筆 \(date) \(name) \(amount)"
    }

    private static func amountText(_ bill: WidgetBill, hidden: Bool) -> String {
        let text: String = hidden ? WidgetHideAmounts.mask : bill.amountText
        return bill.isIncome ? "★ " + text : text
    }

    /// [財富 v4 審查] lockScreen：卡費、交割那一列名稱換類別字、不寫小字（「自己繳・含 Netflix」「從薪轉扣」）與金額
    private static func row(_ bill: WidgetBill, now: Date, hidden: Bool, lockScreen: Bool) -> BillsWidgetRow {
        let locked: Bool = isLocked(bill, lockScreen: lockScreen)
        let due: String = WidgetDateText.dueText(bill.dueDate, from: now, isIncome: bill.isIncome) ?? ""
        let detailText: String = locked ? "" : (bill.detail ?? "")
        let detail: String = detailText.isEmpty ? "" : "・" + detailText
        let lead: String
        let rest: String
        if WidgetDateText.isDueSoon(bill.dueDate, from: now) {
            lead = due
            rest = detail
        } else {
            lead = ""
            rest = WidgetDateText.billDate(bill.dueDate) + "・" + due + detail
        }
        let amount: String = locked ? "" : amountText(bill, hidden: hidden)
        return BillsWidgetRow(id: bill.id, title: shownTitle(bill, lockScreen: lockScreen), lead: lead, rest: rest,
                              amount: amount, isIncome: bill.isIncome,
                              tint: bill.tint, tintDark: bill.tintDark, url: bill.url)
    }

    /// 「再來 10/28 美元保單、11/5 Taycan 車貸 等 3 件」：只列剩下的前兩個名字；剩 1 件就只寫那一件。
    /// [財富 v4 審查] 鎖定畫面的卡費、交割寫類別字（「11/27 卡費」）
    private static func moreText(_ rest: [WidgetBill], lockScreen: Bool) -> String {
        guard !rest.isEmpty else { return "" }
        let names: [String] = rest.prefix(2).map { (bill: WidgetBill) -> String in
            WidgetDateText.shortDate(bill.dueDate) + " " + shownTitle(bill, lockScreen: lockScreen)
        }
        let joined = names.joined(separator: "、")
        if rest.count == 1 { return "再來 " + joined }
        return "再來 " + joined + " 等 \(rest.count) 件"
    }
}

/// 小工具庫預覽與 placeholder 的樣本。**寫死的展示字**（J:240-247 的那 6 件，今天起算的日子）。
/// 網址一律只開固定支出頁（展示用的不連到任何一筆）。
/// [財富 v4] Netflix 那一列換成「CUBE 卡費」（.cardBill，「自己繳・含 Netflix」：刷卡的 Netflix 併進卡費，不再另外一列），
/// 排在第 3 列（8 天後）：中型預覽看得到新的一種；鎖定畫面預覽的第一筆仍是有金額的中華電信
enum BillsSample {
    static func snapshot(at now: Date) -> WidgetBillsSnapshot {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let link = WidgetLink.fixedExpenses.absoluteString
        let items: [WidgetBill] = [
            WidgetBill(id: "sample-2", kind: .fixed, title: "中華電信", detail: "每月",
                       dueDate: day(5, from: today), amountText: "NT$999", isIncome: false,
                       icon: "phone.fill", tint: 0x1A86A6, tintDark: 0x7FE3F0, link: link),
            WidgetBill(id: "sample-3", kind: .mortgage, title: "苗栗的家 房貸", detail: "第 8／480 期",
                       dueDate: day(7, from: today), amountText: "NT$6.2萬", isIncome: false,
                       icon: "house.fill", tint: 0x6B4BE0, tintDark: 0xB79CFF, link: link),
            WidgetBill(id: "sample-1", kind: .cardBill, title: "CUBE 卡費", detail: "自己繳・含 Netflix",
                       dueDate: day(8, from: today), amountText: "NT$18,600", isIncome: false,
                       icon: "creditcard.fill", tint: 0xD9601F, tintDark: 0xFFB86B, link: link,
                       lockTitle: "卡費"),
            WidgetBill(id: "sample-4", kind: .premium, title: "美元保單", detail: "第 4／6 期",
                       dueDate: day(15, from: today), amountText: "美金 3,000", isIncome: false,
                       icon: "umbrella.fill", tint: 0x2F5BD8, tintDark: 0x8DB7FF, link: link),
            // 車貸金額不舉例（J:247）：樣本裡它排第 5，只會出現在「再來 …」那一行（不寫金額）
            WidgetBill(id: "sample-5", kind: .vehicle, title: "Taycan 車貸", detail: "第 26／60 期",
                       dueDate: day(23, from: today), amountText: WidgetHideAmounts.mask, isIncome: false,
                       icon: "car.fill", tint: 0x138A7E, tintDark: 0x7FE3D0, link: link),
            WidgetBill(id: "sample-6", kind: .vehicle, title: "Taycan 停車月租", detail: "每月",
                       dueDate: day(23, from: today), amountText: "NT$4,999", isIncome: false,
                       icon: "parkingsign", tint: 0x138A7E, tintDark: 0x7FE3D0, link: link)
        ]
        return WidgetBillsSnapshot(generatedAt: now,
                                   dataDay: WidgetDateText.dayKey(today),
                                   horizonEnd: day(45, from: today),
                                   items: items)
    }

    private static func day(_ offset: Int, from today: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: today)
            ?? today.addingTimeInterval(TimeInterval(offset) * 24 * 3600)
    }
}

// MARK: - 畫面

struct BillsWidgetEntryView: View {
    let entry: BillsWidgetEntry

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    /// [v25.631 large1] 大型另外畫（BillsLargeView）；中型照舊
    @Environment(\.widgetFamily) private var family

    private var surface: WidgetPalette.Surface {
        WidgetPalette.Surface(renderingMode: renderingMode, showsBackground: showsBackground)
    }

    private var palette: WidgetPalette {
        WidgetPalette(colorScheme, mono: surface.isMono)
    }

    /// [財富 v4 審查] 鎖定畫面（iPad 鎖定畫面是 vibrant；Mac 桌面沒聚焦時也是）：卡費、交割照鎖定畫面的規矩收起來
    private var onLockScreen: Bool { renderingMode == .vibrant }

    private var model: BillsWidgetModel {
        BillsWidgetModel.make(snapshot: entry.snapshot, now: entry.date, hidden: entry.hidesAmounts,
                              scope: entry.scope, days: entry.days, lockScreen: onLockScreen)
    }

    /// [v25.631 large1] 大型：同一個 entry（同一個 timeline），字在 BillsLargeModel.make 組好
    private var largeModel: BillsLargeModel {
        BillsLargeModel.make(snapshot: entry.snapshot, now: entry.date, hidden: entry.hidesAmounts,
                             scope: entry.scope, days: entry.days, lockScreen: onLockScreen)
    }

    /// [v25.631 large1] 大型 → BillsLargeView；其他（中型）→ 既有 BillsWidgetContent
    @ViewBuilder
    private var content: some View {
        if family == .systemLarge {
            BillsLargeView(model: largeModel, palette: palette)
        } else {
            BillsWidgetContent(model: model, palette: palette)
        }
    }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                backgroundView
            }
            .widgetURL(WidgetLink.fixedExpenses)
    }

    /// 右上有「6 件」，不放雲／月牙；著色不畫天空
    @ViewBuilder
    private var backgroundView: some View {
        if surface.drawsSky {
            WidgetSky(palette: palette, moon: WidgetSkyMoon.none)
        } else {
            Color.clear
        }
    }
}

private struct BillsWidgetContent: View {
    let model: BillsWidgetModel
    let palette: WidgetPalette

    var body: some View {
        switch model.kind {
        case .message:
            BillsWidgetMessage(text: model.message, palette: palette)
        case .empty:
            BillsWidgetEmpty(model: model, palette: palette)
        case .list:
            BillsWidgetList(model: model, palette: palette)
        }
    }
}

/// 標題列、最多 3 列、最下面「再來 …」。矮的中型（SE、mini）放不下 3 列時退成 2 列（ViewThatFits 由上往下挑）
private struct BillsWidgetList: View {
    let model: BillsWidgetModel
    let palette: WidgetPalette

    var body: some View {
        ViewThatFits(in: .vertical) {
            column(rows: model.rows, more: model.moreAfterThree)
            column(rows: Array(model.rows.prefix(2)), more: model.moreAfterTwo)
        }
    }

    /// 間距 3：一行一列約 23pt，標題＋3 列＋「再來…」約 115pt，6.1 吋以上的中型（內容約 126pt 起）放得下 3 列
    private func column(rows: [BillsWidgetRow], more: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            BillsWidgetHeader(title: model.header, count: model.countText, palette: palette)
            ForEach(rows, id: \.id) { row in
                Link(destination: row.url) {
                    BillsWidgetRowView(row: row, palette: palette)
                }
            }
            Spacer(minLength: 0)
            footer(more: more)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func footer(more: String) -> some View {
        if !more.isEmpty || !model.staleText.isEmpty {
            BillsWidgetFooter(more: more, stale: model.staleText, palette: palette)
        }
    }
}

/// 「接下來 30 天　　6 件」（整列 → 固定支出頁，J:269）
private struct BillsWidgetHeader: View {
    let title: String
    let count: String
    let palette: WidgetPalette

    var body: some View {
        Link(destination: WidgetLink.fixedExpenses) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.ink)
                    .widgetAccentable()
                Spacer(minLength: 4)
                Text(count)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.label)
            }
            .lineLimit(1)
        }
    }
}

/// 一列（一行，照樣稿「▍Netflix　10/15 (週四)・2 天後　NT$390」）：左邊色條、名稱、
/// 「日期・幾天後・期數」（今天／明天扣款橘字）、右邊金額（粗）。
/// [審查] 原本名稱與日期分兩行，一列約 36pt，3 列＋標題＋「再來…」約 150pt，手機中型（內容約 126–138pt）
/// 永遠只放得下 2 列；改成一行（約 23pt）3 列才放得下。擠的時候先縮中間的日期字，名稱、金額留著。
private struct BillsWidgetRowView: View {
    let row: BillsWidgetRow
    let palette: WidgetPalette

    private var barColor: Color { palette.billBar(tint: row.tint, tintDark: row.tintDark) }
    private var amountColor: Color { row.isIncome ? palette.good : palette.ink }

    var body: some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(barColor)
                .frame(width: 3, height: 14)
            titleText
            BillsWidgetDueLine(lead: row.lead, rest: row.rest, palette: palette)
            Spacer(minLength: 4)
            amountText
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(palette.rowFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    /// 名稱比日期字優先拿寬度（日期字先縮成「…」）
    private var titleText: some View {
        Text(row.title)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(palette.ink)
            .lineLimit(1)
            .layoutPriority(1)
    }

    /// [財富 v4 審查] 空字串（鎖定畫面的卡費、交割）不畫，右邊不留空
    @ViewBuilder
    private var amountText: some View {
        if !row.amount.isEmpty {
            Text(row.amount)
                .font(.system(size: 12.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(amountColor)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// 名稱後面那一段：「明天扣款」（橘）＋「・第 8／480 期」，或「10/15 (週四)・2 天後・每月」
private struct BillsWidgetDueLine: View {
    let lead: String
    let rest: String
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 0) {
            if !lead.isEmpty {
                Text(lead)
                    .foregroundStyle(palette.warn)
                    .fixedSize()
            }
            Text(rest)
                .foregroundStyle(palette.label)
        }
        .font(.system(size: 10, weight: .semibold))
        .lineLimit(1)
    }
}

/// 最下面：「再來 …」（左）＋「上次更新 10/11」（右，快照太舊才有）
private struct BillsWidgetFooter: View {
    let more: String
    let stale: String
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 4) {
            Text(more)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 2)
            if !stale.isEmpty {
                Text(stale)
                    .fixedSize()
            }
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(palette.label)
    }
}

/// 30 天內沒有要扣的：大字＋「下一筆 11/15 (週日) Netflix NT$390」
private struct BillsWidgetEmpty: View {
    let model: BillsWidgetModel
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BillsWidgetHeader(title: model.header, count: model.countText, palette: palette)
            Spacer(minLength: 0)
            Text(model.emptyTitle)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .widgetAccentable()
            nextLine
            Spacer(minLength: 0)
            staleLine
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var nextLine: some View {
        if !model.emptyNext.isEmpty {
            Text(model.emptyNext)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.label)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
    }

    @ViewBuilder
    private var staleLine: some View {
        if !model.staleText.isEmpty {
            BillsWidgetFooter(more: "", stale: model.staleText, palette: palette)
        }
    }
}

/// 沒快照、過了 horizonEnd：只寫一句話
private struct BillsWidgetMessage: View {
    let text: String
    let palette: WidgetPalette

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.label)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 大型（v25.631 large1）
//
// 規格：scratchpad/radar/build/large1/brief.md §0 C1、§2 G1；示意圖 scratchpad/largewidgets/bills.html（版面以示意圖為準）。
// 參考答案：sim_large1.py 的 bills_large_make／bills_large_row／bills_large_more（一個字一個字對照）。
//
//   表頭「接下來 30 天」＋大字「9」＋「件」、右上「10:02 更新」（超過兩天「上次更新 11/17」橘字）→
//   「這週／下週／之後」（LargeWeekBucket.of，週的第一天照 Calendar.current）→ 每列兩行：
//   名稱（會領回的前面一顆星）／「今天扣款」（橘）＋「・每月」或「11/25 (週三)・第 26／60 期」；右邊金額 →
//   頁腳「再來 12/15 Spotify 等 4 件」（剩下的第一個名字＋剩下件數）。只寫件數、不寫合計；大型的小字不寫「N 天後」。
//   沒快照、過了 horizonEnd、30 天內沒有要扣的：直接畫中型的畫面（BillsWidgetContent，同一個 BillsWidgetModel）。
//   放不下只砍列數不縮字：每一塊用 BillsLargeLayout 的常數固定高度，候選 4 個（BillsLargeLayout.candidates）。
//   隱藏金額＝entry.hidesAmounts（provider 讀一次）；vibrant（Mac 桌面沒聚焦）卡費、交割寫類別字、不寫小字與金額。

/// 大型一列：兩行（名稱／小字）＋右邊金額
private struct BillsLargeRow: Identifiable {
    let id: String
    /// 「Netflix」；vibrant 的卡費、交割寫類別字「卡費」「交割」
    let title: String
    /// 會領回的（保單滿期）：名稱前面畫 star.fill（色條同色）
    let showsStar: Bool
    /// 今天／明天的「今天扣款」「明天扣款」「今天到期」（橘）；其他是空字串
    let lead: String
    /// lead 有字時「・每月」（沒有小字就空）；其他「11/25 (週三)・第 26／60 期」
    let rest: String
    /// 「NT$390」「+美金 3.6萬」；隱藏金額時 mask；vibrant 的卡費、交割是空字串（不畫）
    let amount: String
    /// 綠字：會領回、沒隱藏、沒收起來
    let incomeStyle: Bool
    let tint: UInt32
    let tintDark: UInt32
    let url: URL
    let bucket: LargeWeekBucket
}

/// 一區（「這週」那幾列）；不畫區標時整個候選只有一區（id -1、title 空字串）
private struct BillsLargeSection: Identifiable {
    /// LargeWeekBucket.rawValue；不畫區標 -1
    let id: Int
    let title: String
    let rows: [BillsLargeRow]
}

/// ViewThatFits 的一個候選：畫幾列、分不分區、頁腳
private struct BillsLargeCandidate: Identifiable {
    let id: Int
    let plan: BillsLargeLayout.Plan
    let sections: [BillsLargeSection]
    /// 「再來 12/15 Spotify 等 4 件」；全部列完了是空字串（不畫）
    let footer: String
}

private struct BillsLargeModel {
    /// 中型的 model：kind 不是 .list（一句話、30 天內沒有要扣的）時大型直接畫中型的畫面
    var base = BillsWidgetModel()
    /// 「接下來 30 天」
    var header = ""
    /// 「9」（表頭另外畫「件」）
    var countNumber = ""
    /// 「10:02 更新」「11/19 22:00 更新」；超過兩天「上次更新 11/17」
    var updatedText = ""
    var updatedIsStale = false
    /// 固定 4 個（大到小）
    var candidates: [BillsLargeCandidate] = []

    /// 安全取值：超出範圍回最後一個；沒有候選回一個 0 列的
    func candidate(at index: Int) -> BillsLargeCandidate {
        guard let last = candidates.last else {
            let plan = BillsLargeLayout.Plan(rows: 0, showsSections: false)
            return BillsLargeCandidate(id: 0, plan: plan, sections: [], footer: "")
        }
        guard index >= 0, index < candidates.count else { return last }
        return candidates[index]
    }

    /// 只挑字、不算錢（sim bills_large_make）。參數跟 BillsWidgetModel.make 一樣
    static func make(snapshot: WidgetBillsSnapshot?, now: Date, hidden: Bool,
                     scope: WidgetBillScope, days: Int, lockScreen: Bool) -> BillsLargeModel {
        var model = BillsLargeModel()
        model.base = BillsWidgetModel.make(snapshot: snapshot, now: now, hidden: hidden,
                                           scope: scope, days: days, lockScreen: lockScreen)
        guard model.base.kind == .list, let snap = snapshot else { return model }
        let list: [WidgetBill] = snap.upcoming(at: now, days: days, scope: scope)
        model.header = model.base.header
        model.countNumber = "\(list.count)"
        let stale: Bool = snap.isStale(at: now)
        model.updatedIsStale = stale
        model.updatedText = stale
            ? WidgetDateText.lastUpdated(snap.generatedAt)
            : WidgetDateText.updatedAt(snap.generatedAt, now: now)
        // 全部（不是只有前 maxRows 筆）：BillsLargeLayout 要知道後面還有沒有、跨了幾區
        let buckets: [LargeWeekBucket] = list.map { (bill: WidgetBill) -> LargeWeekBucket in
            LargeWeekBucket.of(bill.dueDate, now: now)
        }
        var rows: [BillsLargeRow] = []
        for (i, bill) in list.prefix(BillsLargeLayout.maxRows).enumerated() {
            rows.append(row(bill, bucket: buckets[i], now: now, hidden: hidden, lockScreen: lockScreen))
        }
        let raw: [Int] = buckets.map { (b: LargeWeekBucket) -> Int in b.rawValue }
        let plans: [BillsLargeLayout.Plan] = BillsLargeLayout.candidates(buckets: raw)
        var candidates: [BillsLargeCandidate] = []
        for (i, plan) in plans.enumerated() {
            let n: Int = max(0, plan.rows)
            let shown: [BillsLargeRow] = Array(rows.prefix(n))
            let rest: [WidgetBill] = Array(list.dropFirst(n))
            let item = BillsLargeCandidate(id: i, plan: plan,
                                           sections: sections(shown, labeled: plan.showsSections),
                                           footer: moreText(rest, lockScreen: lockScreen))
            candidates.append(item)
        }
        model.candidates = candidates
        return model
    }

    /// 照 bucket 連續分段（清單照日期排好，同一區連在一起）；不分區時一段
    private static func sections(_ rows: [BillsLargeRow], labeled: Bool) -> [BillsLargeSection] {
        guard labeled else {
            return [BillsLargeSection(id: -1, title: "", rows: rows)]
        }
        var out: [BillsLargeSection] = []
        for row in rows {
            if let last = out.last, last.id == row.bucket.rawValue {
                out[out.count - 1] = BillsLargeSection(id: last.id, title: last.title, rows: last.rows + [row])
            } else {
                out.append(BillsLargeSection(id: row.bucket.rawValue, title: row.bucket.title, rows: [row]))
            }
        }
        return out
    }

    /// 一列（sim bills_large_row）。lockScreen：vibrant 的卡費、交割寫類別字、不寫小字與金額
    private static func row(_ bill: WidgetBill, bucket: LargeWeekBucket, now: Date, hidden: Bool,
                            lockScreen: Bool) -> BillsLargeRow {
        let locked: Bool = lockScreen && bill.kind.isWealth
        let title: String = locked ? bill.lockedTitle : bill.title
        let detailText: String = locked ? "" : (bill.detail ?? "")
        let detail: String = detailText.isEmpty ? "" : "・" + detailText
        let lead: String
        let rest: String
        if WidgetDateText.isDueSoon(bill.dueDate, from: now) {
            lead = WidgetDateText.dueText(bill.dueDate, from: now, isIncome: bill.isIncome) ?? ""
            rest = detail
        } else {
            lead = ""
            rest = WidgetDateText.billDate(bill.dueDate) + detail
        }
        let amount: String = locked ? "" : (hidden ? WidgetHideAmounts.mask : bill.amountText)
        let income: Bool = bill.isIncome && !hidden && !locked
        return BillsLargeRow(id: bill.id, title: title, showsStar: bill.isIncome && !locked, lead: lead, rest: rest,
                             amount: amount, incomeStyle: income,
                             tint: bill.tint, tintDark: bill.tintDark, url: bill.url, bucket: bucket)
    }

    /// 「再來 12/15 Spotify 等 4 件」：只寫剩下的第一個名字＋剩下件數；剩 1 件只寫那一件（sim bills_large_more）。
    /// vibrant 的卡費、交割寫類別字（「12/16 交割」）
    private static func moreText(_ rest: [WidgetBill], lockScreen: Bool) -> String {
        guard let first = rest.first else { return "" }
        let locked: Bool = lockScreen && first.kind.isWealth
        let name: String = locked ? first.lockedTitle : first.title
        let head: String = WidgetDateText.shortDate(first.dueDate) + " " + name
        if rest.count == 1 { return "再來 " + head }
        return "再來 " + head + " 等 \(rest.count) 件"
    }
}

/// 大型：清單 → BillsLargeList；一句話、30 天內沒有要扣的 → 中型的畫面
private struct BillsLargeView: View {
    let model: BillsLargeModel
    let palette: WidgetPalette

    var body: some View {
        if model.base.kind == .list {
            BillsLargeList(model: model, palette: palette)
        } else {
            BillsWidgetContent(model: model.base, palette: palette)
        }
    }
}

/// 4 個候選由上往下挑（字級不變、只砍列數；不巢狀 ViewThatFits）
private struct BillsLargeList: View {
    let model: BillsLargeModel
    let palette: WidgetPalette

    var body: some View {
        ViewThatFits(in: .vertical) {
            BillsLargeColumn(model: model, candidate: model.candidate(at: 0), palette: palette)
            BillsLargeColumn(model: model, candidate: model.candidate(at: 1), palette: palette)
            BillsLargeColumn(model: model, candidate: model.candidate(at: 2), palette: palette)
            BillsLargeColumn(model: model, candidate: model.candidate(at: 3), palette: palette)
        }
    }
}

/// 表頭 → 各區 → Spacer → 頁腳。每一塊固定高度（BillsLargeLayout.height 算的就是這一欄）
private struct BillsLargeColumn: View {
    let model: BillsLargeModel
    let candidate: BillsLargeCandidate
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BillsLargeHeader(model: model, palette: palette)
            ForEach(candidate.sections) { section in
                BillsLargeSectionView(section: section, palette: palette)
            }
            Spacer(minLength: 0)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var footer: some View {
        if !candidate.footer.isEmpty {
            LargeWidgetFooterLine(text: candidate.footer, palette: palette, height: BillsLargeLayout.footerHeight)
        }
    }
}

/// 「接下來 30 天」＋大字「9」「件」、右上「10:02 更新」（整塊 → 固定支出頁）
private struct BillsLargeHeader: View {
    let model: BillsLargeModel
    let palette: WidgetPalette

    var body: some View {
        Link(destination: WidgetLink.fixedExpenses) {
            HStack(alignment: .top, spacing: 0) {
                titleBlock
                Spacer(minLength: 6)
                updatedLine
            }
            .frame(height: BillsLargeLayout.headerHeight, alignment: .top)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.header)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.inkDate)
                .lineLimit(1)
            countLine
        }
    }

    private var countLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(model.countNumber)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.ink)
                .widgetAccentable()
            Text("件")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(palette.ink)
        }
        .lineLimit(1)
    }

    private var updatedColor: Color { model.updatedIsStale ? palette.warn : palette.label }

    private var updatedLine: some View {
        Text(model.updatedText)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(updatedColor)
            .lineLimit(1)
            .fixedSize()
            .padding(.top, 2)
    }
}

/// 區標（不分區時只空 compactTopGap）＋這一區的列（每列 → 那一筆）
private struct BillsLargeSectionView: View {
    let section: BillsLargeSection
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            label
            VStack(spacing: BillsLargeLayout.rowSpacing) {
                ForEach(section.rows) { row in
                    Link(destination: row.url) {
                        BillsLargeRowView(row: row, palette: palette)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var label: some View {
        if section.title.isEmpty {
            Color.clear
                .frame(height: BillsLargeLayout.compactTopGap)
        } else {
            LargeWidgetSectionLabel(title: section.title, height: BillsLargeLayout.sectionHeaderHeight,
                                    palette: palette, bottomGap: BillsLargeLayout.sectionLabelBottomGap)
        }
    }
}

/// 一列：色條、（星）名稱／小字、右邊金額。固定高 rowHeight
private struct BillsLargeRowView: View {
    let row: BillsLargeRow
    let palette: WidgetPalette

    private var barColor: Color { palette.billBar(tint: row.tint, tintDark: row.tintDark) }

    var body: some View {
        HStack(spacing: 8) {
            LargeWidgetTintBar(color: barColor, height: BillsLargeLayout.tintBarHeight)
            texts
            Spacer(minLength: 4)
            BillsLargeAmount(text: row.amount, incomeStyle: row.incomeStyle, palette: palette)
        }
        .padding(.leading, 8)
        .padding(.trailing, 9)
        .frame(height: BillsLargeLayout.rowHeight)
        .background { LargeWidgetCardBackground(palette: palette) }
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 1) {
            titleLine
            BillsLargeSubline(lead: row.lead, rest: row.rest, palette: palette)
        }
    }

    private var titleLine: some View {
        HStack(spacing: 3) {
            star
            Text(row.title)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var star: some View {
        if row.showsStar {
            Image(systemName: "star.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(barColor)
        }
    }
}

/// 「今天扣款」（橘）＋「・每月」，或「11/25 (週三)・第 26／60 期」；兩個都空不畫
private struct BillsLargeSubline: View {
    let lead: String
    let rest: String
    let palette: WidgetPalette

    var body: some View {
        if !lead.isEmpty || !rest.isEmpty {
            HStack(spacing: 0) {
                leadText
                Text(rest)
                    .foregroundStyle(palette.label)
            }
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
        }
    }

    @ViewBuilder
    private var leadText: some View {
        if !lead.isEmpty {
            Text(lead)
                .foregroundStyle(palette.warn)
                .fixedSize()
        }
    }
}

/// 右邊金額：空字串（vibrant 的卡費、交割）不畫；會領回的綠字
private struct BillsLargeAmount: View {
    let text: String
    let incomeStyle: Bool
    let palette: WidgetPalette

    private var color: Color { incomeStyle ? palette.good : palette.ink }

    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
        }
    }
}
