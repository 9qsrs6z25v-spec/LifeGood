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
        .description("30 天內哪天要扣什麼錢")
        .supportedFamilies([.systemMedium])
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

    var body: some View {
        BillsWidgetContent(model: model, palette: palette)
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
