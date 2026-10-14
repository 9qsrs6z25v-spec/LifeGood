import SwiftUI
import WidgetKit

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
// 型別（internal 的都帶 Bills 前綴；畫面零件 private）：
//   BillsWidget、BillsWidgetEntry、BillsWidgetProvider、BillsTimeline（鎖定畫面「下一筆要繳」共用）、
//   BillsSample（同）、BillsWidgetEntryView

// MARK: - Widget

struct BillsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.bills, provider: BillsWidgetProvider()) { entry in
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
    /// 「隱藏金額」開著（provider 讀一次）
    let hidesAmounts: Bool
}

struct BillsWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BillsWidgetEntry {
        let now = Date()
        return BillsWidgetEntry(date: now, snapshot: BillsSample.snapshot(at: now), hidesAmounts: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (BillsWidgetEntry) -> Void) {
        let now = Date()
        if context.isPreview {
            completion(BillsWidgetEntry(date: now, snapshot: BillsSample.snapshot(at: now), hidesAmounts: false))
            return
        }
        let snapshot = WidgetSnapshotStore.read(WidgetBillsSnapshot.self)
        completion(BillsWidgetEntry(date: now, snapshot: snapshot, hidesAmounts: WidgetHideAmounts.isOn))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BillsWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshotStore.read(WidgetBillsSnapshot.self)
        let hidden = WidgetHideAmounts.isOn
        let dates = BillsTimeline.entryDates(snapshot: snapshot, now: now)
        let entries: [BillsWidgetEntry] = dates.map {
            BillsWidgetEntry(date: $0, snapshot: snapshot, hidesAmounts: hidden)
        }
        let policy = BillsTimeline.policy(snapshot: snapshot, dates: dates, now: now)
        completion(Timeline(entries: entries, policy: policy))
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

    /// 只挑字、不算錢：日期字與日差由 WidgetDateText 組，金額字是 App 寫好的
    static func make(snapshot: WidgetBillsSnapshot?, now: Date, hidden: Bool) -> BillsWidgetModel {
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
        let list = snap.upcoming(at: now)
        model.header = "接下來 \(WidgetBillsSnapshot.listDays) 天"
        guard !list.isEmpty else {
            model.kind = .empty
            model.emptyTitle = "\(WidgetBillsSnapshot.listDays) 天內沒有要扣的"
            if let next = snap.next(at: now) {
                model.emptyNext = nextText(next, hidden: hidden)
            }
            return model
        }
        model.kind = .list
        model.countText = "\(list.count) 件"
        model.rows = list.prefix(3).map { row($0, now: now, hidden: hidden) }
        model.moreAfterThree = moreText(Array(list.dropFirst(3)))
        model.moreAfterTwo = moreText(Array(list.dropFirst(2)))
        return model
    }

    /// 「下一筆 11/15 (週日) Netflix NT$390」
    private static func nextText(_ bill: WidgetBill, hidden: Bool) -> String {
        let date: String = WidgetDateText.billDate(bill.dueDate)
        let amount: String = amountText(bill, hidden: hidden)
        return "下一筆 \(date) \(bill.title) \(amount)"
    }

    private static func amountText(_ bill: WidgetBill, hidden: Bool) -> String {
        let text: String = hidden ? WidgetHideAmounts.mask : bill.amountText
        return bill.isIncome ? "★ " + text : text
    }

    private static func row(_ bill: WidgetBill, now: Date, hidden: Bool) -> BillsWidgetRow {
        let due: String = WidgetDateText.dueText(bill.dueDate, from: now, isIncome: bill.isIncome) ?? ""
        let detailText: String = bill.detail ?? ""
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
        return BillsWidgetRow(id: bill.id, title: bill.title, lead: lead, rest: rest,
                              amount: amountText(bill, hidden: hidden), isIncome: bill.isIncome,
                              tint: bill.tint, tintDark: bill.tintDark, url: bill.url)
    }

    /// 「再來 10/28 美元保單、11/5 Taycan 車貸 等 3 件」：只列剩下的前兩個名字；剩 1 件就只寫那一件
    private static func moreText(_ rest: [WidgetBill]) -> String {
        guard !rest.isEmpty else { return "" }
        let names: [String] = rest.prefix(2).map { WidgetDateText.shortDate($0.dueDate) + " " + $0.title }
        let joined = names.joined(separator: "、")
        if rest.count == 1 { return "再來 " + joined }
        return "再來 " + joined + " 等 \(rest.count) 件"
    }
}

/// 小工具庫預覽與 placeholder 的樣本。**寫死的展示字**（J:240-247 的那 6 件，今天起算的日子）。
/// 網址一律只開固定支出頁（展示用的不連到任何一筆）。
enum BillsSample {
    static func snapshot(at now: Date) -> WidgetBillsSnapshot {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let link = WidgetLink.fixedExpenses.absoluteString
        let items: [WidgetBill] = [
            WidgetBill(id: "sample-1", kind: .fixed, title: "Netflix", detail: "每月",
                       dueDate: day(2, from: today), amountText: "NT$390", isIncome: false,
                       icon: "play.tv.fill", tint: 0x6B44E0, tintDark: 0xA88BFF, link: link),
            WidgetBill(id: "sample-2", kind: .fixed, title: "中華電信", detail: "每月",
                       dueDate: day(5, from: today), amountText: "NT$999", isIncome: false,
                       icon: "phone.fill", tint: 0x1A86A6, tintDark: 0x7FE3F0, link: link),
            WidgetBill(id: "sample-3", kind: .mortgage, title: "苗栗的家 房貸", detail: "第 8／480 期",
                       dueDate: day(7, from: today), amountText: "NT$6.2萬", isIncome: false,
                       icon: "house.fill", tint: 0x6B4BE0, tintDark: 0xB79CFF, link: link),
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

    private var model: BillsWidgetModel {
        BillsWidgetModel.make(snapshot: entry.snapshot, now: entry.date, hidden: entry.hidesAmounts)
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

    private var amountText: some View {
        Text(row.amount)
            .font(.system(size: 12.5, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(amountColor)
            .lineLimit(1)
            .fixedSize()
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
