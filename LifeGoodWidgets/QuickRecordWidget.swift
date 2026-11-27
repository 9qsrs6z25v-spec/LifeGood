import SwiftUI
import WidgetKit
import AppIntents

// MARK: - 一按就記（systemSmall、systemMedium）：常記範本的互動按鈕、✓ 已記・復原、待入帳 N 筆（小工具 v2）
//
// 只屬於「LifeGoodWidgets」target。規格見 scratchpad/widgets/v2/brief.md 的 G3-4；
// 設計 scratchpad/widgets/design_money.md W7（M:370-410）；主控定案 B。
//
// • 範本：money 快照的 templates（App 從近 60 天挑「同名稱＋同金額＋同分類（＋同車）」≥3 次的，最多 4 個）。
//   每個範本一顆 Button(intent: QuickRecordIntent(template:))，按下去**不開 App**：在小工具的行程裡
//   寫一筆「待入帳」進 App Group 的收件匣（QuickRecordInbox），App 下次打開／回前景時收進帳本。
// • 「✓ 已記 7-11 咖啡 NT$65・復原」：最新一筆待入帳在 bannerDuration（10 分鐘）內才有；同一顆按了
//   兩次以上寫「✓ 已記 2 次 7-11 咖啡」。復原＝Button(intent: UndoQuickRecordIntent)，App 還沒收走才有效。
// • 「待入帳 N 筆・打開 LifeGood 就會記進帳本」（小型寫「待入帳 N 筆」）。
// • **小工具裡不算錢**：待入帳不加進「今天」「還能花」（App 收進帳本、重寫快照之後才會變）。
// • 隱藏金額：按鈕上的價目、橫幅裡的金額一起換成 WidgetHideAmounts.mask（主控定案 5）；中型左半同記帳台。
// • 小工具庫預覽／placeholder 的按鈕畫成不能按的樣子（isSample），不會把展示用的範本寫進收件匣。
// • StandBy 不能按（系統行為），版面照常；著色模式按鈕改外框。
// • 整塊 .widgetURL → 收支總覽（按鈕以外的地方開 App）。
//
// 型別（internal 的都帶 QuickRecordWidget 前綴；畫面零件 private）：
//   QuickRecordWidget、QuickRecordWidgetEntry、QuickRecordWidgetProvider、QuickRecordWidgetTimeline、
//   QuickRecordWidgetSample、QuickRecordWidgetEntryView

// MARK: - Widget

struct QuickRecordWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.quickRecord, provider: QuickRecordWidgetProvider()) { entry in
            QuickRecordRootView(entry: entry)
        }
        .configurationDisplayName("一按就記")
        .description("常記的東西按一下就記好，不用開 App；大的一次放 8 個")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Timeline

struct QuickRecordWidgetEntry: TimelineEntry {
    /// 畫面一律拿這個當「現在」
    let date: Date
    /// nil＝還沒打開過新版 App（或檔案讀不到）
    let snapshot: WidgetMoneySnapshot?
    /// 還沒被 App 收走的待入帳，依按下的時間由舊到新（QuickRecordInbox.pending()）
    let pending: [QuickRecordEntry]
    /// 「隱藏金額」開著（provider 讀一次）
    let hidesAmounts: Bool
    /// 小工具庫預覽／placeholder：按鈕不能按
    let isSample: Bool
}

struct QuickRecordWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickRecordWidgetEntry {
        if context.family == .systemLarge {
            return QuickRecordLargeSample.entry(now: Date())
        }
        return QuickRecordWidgetSample.entry(now: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickRecordWidgetEntry) -> Void) {
        if context.isPreview {
            if context.family == .systemLarge {
                completion(QuickRecordLargeSample.entry(now: Date()))
            } else {
                completion(QuickRecordWidgetSample.entry(now: Date()))
            }
            return
        }
        let entry = QuickRecordWidgetEntry(date: Date(),
                                           snapshot: WidgetSnapshotStore.read(WidgetMoneySnapshot.self),
                                           pending: QuickRecordInbox.pending(),
                                           hidesAmounts: WidgetHideAmounts.isOn,
                                           isSample: false)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickRecordWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshotStore.read(WidgetMoneySnapshot.self)
        let pending = QuickRecordInbox.pending()
        let hidden = WidgetHideAmounts.isOn
        let dates = QuickRecordWidgetTimeline.entryDates(snapshot: snapshot, pending: pending, now: now)
        let entries: [QuickRecordWidgetEntry] = dates.map {
            QuickRecordWidgetEntry(date: $0, snapshot: snapshot, pending: pending,
                                   hidesAmounts: hidden, isSample: false)
        }
        // 按鈕、復原之後系統會自己重畫（intent 也叫了 reload）；App 收走時 QuickRecordImporter 叫 reload
        let policy = MoneyLeftTimeline.policy(snapshot: snapshot, dates: dates, now: now)
        completion(Timeline(entries: entries, policy: policy))
    }
}

/// 一按就記哪些時間點要換畫面
enum QuickRecordWidgetTimeline {
    /// 左半還能花的那些時間（MoneyLeftTimeline）＋「✓ 已記…」橫幅消失的那一刻（比 now 晚才放）
    static func entryDates(snapshot: WidgetMoneySnapshot?, pending: [QuickRecordEntry], now: Date) -> [Date] {
        var dates = Set(MoneyLeftTimeline.entryDates(snapshot: snapshot, now: now))
        if let latest = pending.last {
            let bannerEnd = latest.createdAt.addingTimeInterval(QuickRecordInbox.bannerDuration)
            if bannerEnd > now {
                dates.insert(bannerEnd)
            }
        }
        return dates.sorted()
    }
}

// MARK: - 畫面要的字（全部在這裡組好，body 只讀）

/// 一顆範本按鈕要畫的東西
private struct QuickRecordWidgetItem: Identifiable {
    let id: String
    /// 按下去原樣交給 QuickRecordIntent
    let template: WidgetQuickTemplate
    let title: String
    /// 「NT$65」；隱藏金額時是 mask
    let amountText: String
    let icon: String
    let top: UInt32
    let bottom: UInt32
}

private struct QuickRecordWidgetModel {
    enum Kind {
        /// 有範本：2×2 按鈕
        case buttons
        /// 沒快照、或 v1 舊檔（templates 是 nil）
        case noSnapshot
        /// 有快照但還沒有記滿 3 次的東西
        case noTemplates
    }

    var kind: Kind = .noSnapshot
    var items: [QuickRecordWidgetItem] = []
    var message = ""
    var messageSub = ""
    /// 「✓ 已記 7-11 咖啡 NT$65」「✓ 已記 2 次 7-11 咖啡」；沒有橫幅是空字串
    var bannerText = ""
    /// 復原哪一筆；nil＝沒有橫幅
    var undoId: UUID? = nil
    var pendingCount = 0
    /// 「待入帳 2 筆・打開 LifeGood 就會記進帳本」
    var pendingLong = ""
    /// 「待入帳 2 筆」
    var pendingShort = ""
    var isSample = false

    /// 只挑字、不算錢：金額字是 App 寫在範本／收件匣裡的，隱藏時整個換成 mask
    static func make(entry: QuickRecordWidgetEntry) -> QuickRecordWidgetModel {
        var model = QuickRecordWidgetModel()
        model.isSample = entry.isSample
        if let templates = entry.snapshot?.templates {
            if templates.isEmpty {
                model.kind = .noTemplates
                model.message = "常記的東西記滿 3 次就會出現在這裡"
                model.messageSub = "同名稱、同金額，近 60 天"
            } else {
                model.kind = .buttons
                model.items = buttonItems(templates, hidden: entry.hidesAmounts)
            }
        } else {
            model.kind = .noSnapshot
            model.message = "打開 LifeGood 一次，這裡就會出現常記的東西"
        }
        fillBanner(&model, pending: entry.pending, now: entry.date, hidden: entry.hidesAmounts)
        let count = entry.pending.count
        model.pendingCount = count
        if count > 0 {
            model.pendingLong = "待入帳 \(count) 筆・打開 LifeGood 就會記進帳本"
            model.pendingShort = "待入帳 \(count) 筆"
        }
        return model
    }

    /// 最多 4 顆、id 不重複（App 已經排好：次數多到少）
    private static func buttonItems(_ templates: [WidgetQuickTemplate], hidden: Bool) -> [QuickRecordWidgetItem] {
        var seen = Set<String>()
        var out: [QuickRecordWidgetItem] = []
        for t in templates where !seen.contains(t.id) {
            seen.insert(t.id)
            let amount: String = hidden ? WidgetHideAmounts.mask : t.amountText
            out.append(QuickRecordWidgetItem(id: t.id, template: t, title: t.title, amountText: amount,
                                             icon: t.icon, top: t.top, bottom: t.bottom))
            if out.count == 4 { break }
        }
        return out
    }

    /// 「✓ 已記…」：最新一筆在 bannerDuration 內才有；同一顆在這段時間內按了 n 次（n ≥ 2）寫「已記 n 次」
    private static func fillBanner(_ model: inout QuickRecordWidgetModel, pending: [QuickRecordEntry],
                                   now: Date, hidden: Bool) {
        guard let latest = pending.last else { return }
        let window = QuickRecordInbox.bannerDuration
        guard now.timeIntervalSince(latest.createdAt) < window else { return }
        let same: [QuickRecordEntry] = pending.filter { item in
            item.templateId == latest.templateId && now.timeIntervalSince(item.createdAt) < window
        }
        if same.count >= 2 {
            model.bannerText = "✓ 已記 \(same.count) 次 \(latest.title)"
        } else {
            let amount: String = hidden ? WidgetHideAmounts.mask : latest.amountText
            model.bannerText = "✓ 已記 \(latest.title) \(amount)"
        }
        model.undoId = latest.id
    }
}

/// 小工具庫預覽與 placeholder 的樣本。**寫死的展示字**（M:376-387）；按鈕畫成不能按的樣子。
enum QuickRecordWidgetSample {
    static func entry(now: Date) -> QuickRecordWidgetEntry {
        var snap = LedgerDeskSample.snapshot(at: now)
        snap.templates = templates
        return QuickRecordWidgetEntry(date: now, snapshot: snap, pending: [],
                                      hidesAmounts: false, isSample: true)
    }

    private static var templates: [WidgetQuickTemplate] {
        [
            WidgetQuickTemplate(id: "sample-1", title: "7-11 咖啡", amount: 65, amountText: "NT$65",
                                categoryKey: "sample-food", icon: "cup.and.saucer.fill",
                                top: 0xFFB45E, bottom: 0xEE5E3B, tint: 0xEE5E3B, count: 14),
            WidgetQuickTemplate(id: "sample-2", title: "早餐", amount: 85, amountText: "NT$85",
                                categoryKey: "sample-food", icon: "fork.knife",
                                top: 0xFFB45E, bottom: 0xEE5E3B, tint: 0xEE5E3B, count: 9),
            WidgetQuickTemplate(id: "sample-3", title: "停車", amount: 60, amountText: "NT$60",
                                categoryKey: "sample-car", icon: "parkingsign",
                                top: 0x7FE3D0, bottom: 0x1A9C8C, tint: 0x138A7E, count: 6),
            WidgetQuickTemplate(id: "sample-4", title: "全家", amount: 39, amountText: "NT$39",
                                categoryKey: "sample-shopping", icon: "cart.fill",
                                top: 0xFF9CBB, bottom: 0xE0457A, tint: 0xE0457A, count: 4)
        ]
    }
}

// MARK: - 畫面

struct QuickRecordWidgetEntryView: View {
    let entry: QuickRecordWidgetEntry

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

    private var model: QuickRecordWidgetModel {
        QuickRecordWidgetModel.make(entry: entry)
    }

    private var isMedium: Bool { family == .systemMedium }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                backgroundView
            }
            .widgetURL(WidgetLink.expenseOverview)
    }

    @ViewBuilder
    private var content: some View {
        if isMedium {
            QuickRecordWidgetMedium(model: model, entry: entry, palette: palette)
        } else {
            QuickRecordWidgetSmall(model: model, palette: palette)
        }
    }

    /// 小型右上有「復原」，不放雲／月牙；中型放左上日期旁
    @ViewBuilder
    private var backgroundView: some View {
        if surface.drawsSky {
            WidgetSky(palette: palette, moon: isMedium ? WidgetSkyMoon.topLeading : WidgetSkyMoon.none)
        } else {
            Color.clear
        }
    }
}

/// 小型：上面一行（橫幅／待入帳 N 筆／一按就記），下面 2×2 範本按鈕
private struct QuickRecordWidgetSmall: View {
    let model: QuickRecordWidgetModel
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            QuickRecordWidgetHeader(model: model, palette: palette, showsPending: true)
            QuickRecordWidgetMain(model: model, palette: palette)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 中型：左半還能花（點了開收支總覽）；右半上面橫幅、中間 2×2、下面「待入帳 N 筆・…」
private struct QuickRecordWidgetMedium: View {
    let model: QuickRecordWidgetModel
    let entry: QuickRecordWidgetEntry
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 12) {
            Link(destination: WidgetLink.expenseOverview) {
                WidgetMoneyPanel(snapshot: entry.snapshot, now: entry.date,
                                 hidden: entry.hidesAmounts, palette: palette)
            }
            rightHalf
        }
    }

    private var rightHalf: some View {
        VStack(alignment: .leading, spacing: 5) {
            QuickRecordWidgetHeader(model: model, palette: palette, showsPending: false)
            QuickRecordWidgetMain(model: model, palette: palette)
            pendingFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var pendingFooter: some View {
        if model.pendingCount > 0 {
            QuickRecordWidgetPendingLine(long: model.pendingLong, short: model.pendingShort, palette: palette)
        }
    }
}

/// 最上面一行：有橫幅寫「✓ 已記…・復原」；否則（小型）「待入帳 N 筆」或「一按就記」
private struct QuickRecordWidgetHeader: View {
    let model: QuickRecordWidgetModel
    let palette: WidgetPalette
    /// 小型沒有下面那一行，待入帳寫在這裡
    let showsPending: Bool

    private var showsPendingText: Bool { showsPending && model.pendingCount > 0 }

    private var text: String {
        showsPendingText ? model.pendingShort : "一按就記"
    }

    private var color: Color {
        showsPendingText ? palette.inkDate : palette.ink
    }

    var body: some View {
        if let undoId = model.undoId {
            QuickRecordWidgetBanner(text: model.bannerText, undoId: undoId,
                                    interactive: !model.isSample, palette: palette)
        } else {
            Text(text)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// 「✓ 已記 7-11 咖啡 NT$65」＋「復原」
private struct QuickRecordWidgetBanner: View {
    let text: String
    let undoId: UUID
    let interactive: Bool
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(palette.good)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            undoButton
        }
    }

    @ViewBuilder
    private var undoButton: some View {
        if interactive {
            Button(intent: UndoQuickRecordIntent(entryId: undoId)) {
                QuickRecordWidgetUndoLabel(palette: palette)
            }
            .buttonStyle(.plain)
        } else {
            QuickRecordWidgetUndoLabel(palette: palette)
        }
    }
}

private struct QuickRecordWidgetUndoLabel: View {
    let palette: WidgetPalette

    var body: some View {
        Text("復原")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(palette.deskAddIcon)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(palette.deskAddFill, in: Capsule())
            .fixedSize()
    }
}

/// 中間：有範本畫 2×2 按鈕，否則一句說明
private struct QuickRecordWidgetMain: View {
    let model: QuickRecordWidgetModel
    let palette: WidgetPalette

    var body: some View {
        switch model.kind {
        case .buttons:
            QuickRecordWidgetGrid(items: model.items, interactive: !model.isSample, palette: palette)
        case .noSnapshot, .noTemplates:
            QuickRecordWidgetEmpty(message: model.message, sub: model.messageSub, palette: palette)
        }
    }
}

/// 2×2 固定四格（範本不滿 4 個時空格留白，按鈕大小不變）
private struct QuickRecordWidgetGrid: View {
    let items: [QuickRecordWidgetItem]
    let interactive: Bool
    let palette: WidgetPalette

    var body: some View {
        VStack(spacing: 6) {
            row(first: 0)
            row(first: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(first: Int) -> some View {
        HStack(spacing: 6) {
            cell(first)
            cell(first + 1)
        }
    }

    @ViewBuilder
    private func cell(_ index: Int) -> some View {
        if index < items.count {
            QuickRecordWidgetButton(item: items[index], interactive: interactive, palette: palette)
        } else {
            Color.clear
        }
    }
}

/// 一顆範本按鈕（不開 App；預覽時只畫樣子）
private struct QuickRecordWidgetButton: View {
    let item: QuickRecordWidgetItem
    let interactive: Bool
    let palette: WidgetPalette

    var body: some View {
        if interactive {
            Button(intent: QuickRecordIntent(template: item.template)) {
                QuickRecordWidgetFace(item: item, palette: palette)
            }
            .buttonStyle(.plain)
        } else {
            QuickRecordWidgetFace(item: item, palette: palette)
        }
    }
}

/// 按鈕的樣子：範本的兩色漸層、第一行「☕ 7-11 咖啡」、第二行價目（M:378-385；同記帳台的卡；著色模式外框）。
/// 兩行字、垂直置中：小螢幕的小型（一格約 47pt 高）也放得下
private struct QuickRecordWidgetFace: View {
    let item: QuickRecordWidgetItem
    let palette: WidgetPalette

    private var ink: Color { palette.isMono ? palette.ink : palette.tileInk }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            titleRow
            amountText
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            LedgerDeskCardBackground(top: item.top, bottom: item.bottom, plain: false,
                                     palette: palette, cornerRadius: 12)
        }
    }

    private var titleRow: some View {
        HStack(spacing: 3) {
            Image(systemName: item.icon)
                .font(.system(size: 10.5, weight: .bold))
                .widgetAccentable()
            Text(item.title)
                .font(.system(size: 11.5, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }

    private var amountText: some View {
        Text(item.amountText)
            .font(.system(size: 10.5, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// 沒有範本時的一句說明
private struct QuickRecordWidgetEmpty: View {
    let message: String
    let sub: String
    let palette: WidgetPalette

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "hand.tap")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.label)
            Text(message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            subText
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var subText: some View {
        if !sub.isEmpty {
            Text(sub)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// 中型右下「待入帳 N 筆・打開 LifeGood 就會記進帳本」；放不下改「待入帳 N 筆」
private struct QuickRecordWidgetPendingLine: View {
    let long: String
    let short: String
    let palette: WidgetPalette

    var body: some View {
        ViewThatFits(in: .horizontal) {
            line(long)
            line(short)
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(palette.inkDate)
            .lineLimit(1)
    }
}

// MARK: - 大型（v25.638 large4）
//
// judge_largewidgets.md §C 第四版 C1、brief §2 G1。同一個 kind、同一個 timeline（getTimeline 一字不動），
// QuickRecordRootView 依尺寸分：大型 → QuickRecordLargeEntryView，其他（小型、中型）→ 既有 QuickRecordWidgetEntryView（一字不動）。
// • ① 表頭：「一按就記」＋右邊「待入帳 2 筆」；剛記完（最新一筆 10 分鐘內）整行換成既有的 QuickRecordWidgetBanner
//   （「✓ 已記 早餐 NT$65」＋〔復原〕＝既有 UndoQuickRecordIntent）。
// • ② 2×4 範本按鈕（一排 2 格、間距 8）：每顆 Button(intent: QuickRecordIntent(template:))，按了直接記、不開 App；
//   範本 1–7 個時最後一格「＋ 記一筆」（Link → 新增支出），其餘格子不畫；8 個以上只畫前 8 個。
// • ③ 頁腳「打開 LifeGood 就會記進帳本」（剛記完、表頭被橫幅佔走時改寫「待入帳 N 筆・打開 LifeGood 就會記進帳本」）。
// • 沒有範本／舊快照／沒快照：表頭＋既有 QuickRecordWidgetEmpty（字跟中型一樣），不畫格子。
// • 放不下只砍按鈕高（60 → 52 → 46）、再拿掉頁腳，字級不變（QuickRecordLargeLayout.candidates，ViewThatFits 4 個候選）。
// • 隱藏金額只用 entry.hidesAmounts（provider 既有那一次）：價目換 mask、範本名稱照常。不放還能花（左半面板）。
// • 整塊 widgetURL＝收支總覽（按鈕以外的地方）。
//
// 型別：QuickRecordRootView、QuickRecordLargeSample（internal）；model 與畫面零件 private。

/// 依尺寸分：大型 → QuickRecordLargeEntryView；其他 → 既有 QuickRecordWidgetEntryView（小型、中型原封不動）
struct QuickRecordRootView: View {
    let entry: QuickRecordWidgetEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .systemLarge {
            QuickRecordLargeEntryView(entry: entry)
        } else {
            QuickRecordWidgetEntryView(entry: entry)
        }
    }
}

/// 一格：範本按鈕，或「＋ 記一筆」（item 是 nil）
private struct QuickRecordLargeCell: Identifiable {
    let id: String
    let item: QuickRecordWidgetItem?
}

/// 一排（最多 2 格；id＝第幾排）
private struct QuickRecordLargeRow: Identifiable {
    let id: Int
    let cells: [QuickRecordLargeCell]
}

/// 一個候選（id 0…3，大到小）
private struct QuickRecordLargeCandidate: Identifiable {
    let id: Int
    let plan: QuickRecordLargeLayout.Plan
}

/// 大型要的東西：只挑字、不算錢（sim qr_large_make）。表頭、橫幅、待入帳用既有 QuickRecordWidgetModel（同小型中型）
private struct QuickRecordLargeModel {
    let base: QuickRecordWidgetModel
    let rows: [QuickRecordLargeRow]
    /// 表頭右邊：沒有橫幅時「待入帳 N 筆」（沒有待入帳是空字串）；有橫幅時空字串
    let trailing: String
    /// 頁腳：有橫幅而且有待入帳時「待入帳 N 筆・打開 LifeGood 就會記進帳本」，否則「打開 LifeGood 就會記進帳本」
    let footer: String
    /// 固定 4 個（大到小）
    let candidates: [QuickRecordLargeCandidate]

    var interactive: Bool { !base.isSample }

    /// 安全取值：index 夾在 0...count-1；沒有候選回最矮、不帶頁腳
    func candidate(at index: Int) -> QuickRecordLargeCandidate {
        let i: Int = max(index, 0)
        if let picked = candidates.dropFirst(i).first {
            return picked
        }
        if let last = candidates.last {
            return last
        }
        let plan = QuickRecordLargeLayout.Plan(tileHeight: QuickRecordLargeLayout.compactTileHeight,
                                               showsFooter: false)
        return QuickRecordLargeCandidate(id: 0, plan: plan)
    }

    static func make(entry: QuickRecordWidgetEntry) -> QuickRecordLargeModel {
        let base: QuickRecordWidgetModel = QuickRecordWidgetModel.make(entry: entry)
        var items: [QuickRecordWidgetItem] = []
        if base.kind == .buttons {
            let templates: [WidgetQuickTemplate] = entry.snapshot?.templates ?? []
            items = largeItems(templates, hidden: entry.hidesAmounts)
        }
        var cells: [QuickRecordLargeCell] = items.map { (it: QuickRecordWidgetItem) -> QuickRecordLargeCell in
            QuickRecordLargeCell(id: it.id, item: it)
        }
        if QuickRecordLargeLayout.showsAddTile(templateCount: items.count) {
            cells.append(QuickRecordLargeCell(id: "+add", item: nil))
        }
        let chunks: [[QuickRecordLargeCell]] = QuickRecordLargeLayout.chunked(cells)
        var rows: [QuickRecordLargeRow] = []
        for (i, chunk) in chunks.enumerated() {
            rows.append(QuickRecordLargeRow(id: i, cells: chunk))
        }
        let plans: [QuickRecordLargeLayout.Plan] = QuickRecordLargeLayout.candidates(rows: rows.count)
        var candidates: [QuickRecordLargeCandidate] = []
        for (i, plan) in plans.enumerated() {
            candidates.append(QuickRecordLargeCandidate(id: i, plan: plan))
        }
        let trailing: String = base.undoId == nil ? base.pendingShort : ""
        let showsPendingFooter: Bool = base.undoId != nil && base.pendingCount > 0
        let footer: String = showsPendingFooter ? base.pendingLong : "打開 LifeGood 就會記進帳本"
        return QuickRecordLargeModel(base: base, rows: rows, trailing: trailing, footer: footer,
                                     candidates: candidates)
    }

    /// 最多 maxTiles 顆、id 不重複（同 buttonItems 的寫法；App 已經排好：次數多到少）
    private static func largeItems(_ templates: [WidgetQuickTemplate], hidden: Bool) -> [QuickRecordWidgetItem] {
        var seen = Set<String>()
        var out: [QuickRecordWidgetItem] = []
        for t in templates where !seen.contains(t.id) {
            seen.insert(t.id)
            let amount: String = hidden ? WidgetHideAmounts.mask : t.amountText
            out.append(QuickRecordWidgetItem(id: t.id, template: t, title: t.title, amountText: amount,
                                             icon: t.icon, top: t.top, bottom: t.bottom))
            if out.count >= QuickRecordLargeLayout.maxTiles { break }
        }
        return out
    }
}

/// 大型：palette／surface 同 QuickRecordWidgetEntryView；右上有字，天空不放月牙
private struct QuickRecordLargeEntryView: View {
    let entry: QuickRecordWidgetEntry

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    private var surface: WidgetPalette.Surface {
        WidgetPalette.Surface(renderingMode: renderingMode, showsBackground: showsBackground)
    }

    private var palette: WidgetPalette {
        WidgetPalette(colorScheme, mono: surface.isMono)
    }

    private var model: QuickRecordLargeModel {
        QuickRecordLargeModel.make(entry: entry)
    }

    var body: some View {
        QuickRecordLargeContent(model: model, palette: palette)
            .containerBackground(for: .widget) {
                backgroundView
            }
            .widgetURL(WidgetLink.expenseOverview)
    }

    /// 著色不畫天空
    @ViewBuilder
    private var backgroundView: some View {
        if surface.drawsSky {
            WidgetSky(palette: palette, moon: WidgetSkyMoon.none)
        } else {
            Color.clear
        }
    }
}

/// 有範本 → 格子；沒有（0 個、舊快照、沒快照）→ 表頭＋一句說明（同中型的字）
private struct QuickRecordLargeContent: View {
    let model: QuickRecordLargeModel
    let palette: WidgetPalette

    var body: some View {
        if model.base.kind == .buttons {
            QuickRecordLargeBoard(model: model, palette: palette)
        } else {
            emptyColumn
        }
    }

    private var emptyColumn: some View {
        VStack(spacing: 0) {
            QuickRecordLargeHeader(model: model, palette: palette)
                .frame(height: QuickRecordLargeLayout.headerHeight)
            QuickRecordWidgetEmpty(message: model.base.message, sub: model.base.messageSub, palette: palette)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 4 個候選由上往下挑（字級不變、只砍按鈕高與頁腳；不巢狀 ViewThatFits）
private struct QuickRecordLargeBoard: View {
    let model: QuickRecordLargeModel
    let palette: WidgetPalette

    var body: some View {
        ViewThatFits(in: .vertical) {
            QuickRecordLargeColumn(model: model, candidate: model.candidate(at: 0), palette: palette)
            QuickRecordLargeColumn(model: model, candidate: model.candidate(at: 1), palette: palette)
            QuickRecordLargeColumn(model: model, candidate: model.candidate(at: 2), palette: palette)
            QuickRecordLargeColumn(model: model, candidate: model.candidate(at: 3), palette: palette)
        }
    }
}

/// 表頭（固定高）→ 格子（上面空 gridTopGap）→ Spacer →（候選帶的話）頁腳。QuickRecordLargeLayout.height 算的就是這一欄
private struct QuickRecordLargeColumn: View {
    let model: QuickRecordLargeModel
    let candidate: QuickRecordLargeCandidate
    let palette: WidgetPalette

    private var plan: QuickRecordLargeLayout.Plan { candidate.plan }

    var body: some View {
        VStack(spacing: 0) {
            QuickRecordLargeHeader(model: model, palette: palette)
                .frame(height: QuickRecordLargeLayout.headerHeight)
            QuickRecordLargeGrid(rows: model.rows, tileHeight: plan.tileHeight,
                                 interactive: model.interactive, palette: palette)
                .padding(.top, QuickRecordLargeLayout.gridTopGap)
            Spacer(minLength: 0)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var footer: some View {
        if plan.showsFooter {
            LargeWidgetFooterLine(text: model.footer, palette: palette, height: QuickRecordLargeLayout.footerHeight)
        }
    }
}

/// 表頭一行：剛記完 → 既有「✓ 已記…・復原」；否則「一按就記」＋右邊待入帳筆數
private struct QuickRecordLargeHeader: View {
    let model: QuickRecordLargeModel
    let palette: WidgetPalette

    var body: some View {
        if let undoId = model.base.undoId {
            QuickRecordWidgetBanner(text: model.base.bannerText, undoId: undoId,
                                    interactive: !model.base.isSample, palette: palette)
        } else {
            titleRow
        }
    }

    private var titleRow: some View {
        HStack(spacing: 6) {
            Text("一按就記")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .widgetAccentable()
            Spacer(minLength: 4)
            trailingText
        }
    }

    @ViewBuilder
    private var trailingText: some View {
        if !model.trailing.isEmpty {
            Text(model.trailing)
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(palette.inkDate)
                .lineLimit(1)
        }
    }
}

/// 最多 4 排、一排 2 格；最後一排只有 1 格時右半空白（按鈕寬不變）。每排高＝候選的按鈕高
private struct QuickRecordLargeGrid: View {
    let rows: [QuickRecordLargeRow]
    let tileHeight: CGFloat
    let interactive: Bool
    let palette: WidgetPalette

    var body: some View {
        VStack(spacing: QuickRecordLargeLayout.tileSpacing) {
            ForEach(rows) { (row: QuickRecordLargeRow) in
                rowView(row)
            }
        }
    }

    private func rowView(_ row: QuickRecordLargeRow) -> some View {
        HStack(spacing: QuickRecordLargeLayout.tileSpacing) {
            ForEach(row.cells) { (cell: QuickRecordLargeCell) in
                QuickRecordLargeTile(cell: cell, interactive: interactive, palette: palette)
            }
            if row.cells.count < QuickRecordLargeLayout.columns {
                Color.clear
            }
        }
        .frame(height: tileHeight)
    }
}

/// 一格：範本 → 按了就記（不開 App；預覽只畫樣子）；「＋ 記一筆」→ 開新增支出
private struct QuickRecordLargeTile: View {
    let cell: QuickRecordLargeCell
    let interactive: Bool
    let palette: WidgetPalette

    var body: some View {
        if let item = cell.item {
            templateTile(item)
        } else {
            Link(destination: WidgetDeskTile.addExpense.url) {
                QuickRecordLargeAddFace(palette: palette)
            }
        }
    }

    @ViewBuilder
    private func templateTile(_ item: QuickRecordWidgetItem) -> some View {
        if interactive {
            Button(intent: QuickRecordIntent(template: item.template)) {
                QuickRecordLargeFace(item: item, palette: palette)
            }
            .buttonStyle(.plain)
        } else {
            QuickRecordLargeFace(item: item, palette: palette)
        }
    }
}

/// 範本按鈕的樣子：範本的兩色漸層、第一行「☕ 7-11 咖啡」、第二行價目（著色模式外框）
private struct QuickRecordLargeFace: View {
    let item: QuickRecordWidgetItem
    let palette: WidgetPalette

    private var ink: Color { palette.isMono ? palette.ink : palette.tileInk }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            titleRow
            amountText
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            LedgerDeskCardBackground(top: item.top, bottom: item.bottom, plain: false,
                                     palette: palette, cornerRadius: 14)
        }
    }

    private var titleRow: some View {
        HStack(spacing: 4) {
            Image(systemName: item.icon)
                .font(.system(size: 13, weight: .bold))
                .widgetAccentable()
            Text(item.title)
                .font(.system(size: 13.5, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var amountText: some View {
        Text(item.amountText)
            .font(.system(size: 12.5, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// 「＋ 記一筆」的樣子：淺底、App 藍圖示（著色模式外框＋重點色圖示）
private struct QuickRecordLargeAddFace: View {
    let palette: WidgetPalette

    private var iconColor: Color { palette.isMono ? palette.ink : palette.deskAddIcon }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: WidgetDeskTile.addExpense.icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(iconColor)
                .widgetAccentable()
            Text(WidgetDeskTile.addExpense.title)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            LedgerDeskCardBackground(top: WidgetDeskTile.addExpense.top, bottom: WidgetDeskTile.addExpense.bottom,
                                     plain: true, palette: palette, cornerRadius: 14)
        }
    }
}

/// 大型的小工具庫預覽與 placeholder：7 個寫死的展示範本（看得到最後一格「＋ 記一筆」）；按鈕畫成不能按的樣子
enum QuickRecordLargeSample {
    static func entry(now: Date) -> QuickRecordWidgetEntry {
        var snap = LedgerDeskSample.snapshot(at: now)
        snap.templates = templates
        return QuickRecordWidgetEntry(date: now, snapshot: snap, pending: [],
                                      hidesAmounts: false, isSample: true)
    }

    private static var templates: [WidgetQuickTemplate] {
        [
            WidgetQuickTemplate(id: "sample-1", title: "7-11 咖啡", amount: 65, amountText: "NT$65",
                                categoryKey: "sample-food", icon: "cup.and.saucer.fill",
                                top: 0xFFB45E, bottom: 0xEE5E3B, tint: 0xEE5E3B, count: 14),
            WidgetQuickTemplate(id: "sample-2", title: "早餐", amount: 85, amountText: "NT$85",
                                categoryKey: "sample-food", icon: "fork.knife",
                                top: 0xFFB45E, bottom: 0xEE5E3B, tint: 0xEE5E3B, count: 9),
            WidgetQuickTemplate(id: "sample-3", title: "停車", amount: 60, amountText: "NT$60",
                                categoryKey: "sample-car", icon: "parkingsign",
                                top: 0x7FE3D0, bottom: 0x1A9C8C, tint: 0x138A7E, count: 6),
            WidgetQuickTemplate(id: "sample-4", title: "全家", amount: 39, amountText: "NT$39",
                                categoryKey: "sample-shopping", icon: "cart.fill",
                                top: 0xFF9CBB, bottom: 0xE0457A, tint: 0xE0457A, count: 4),
            WidgetQuickTemplate(id: "sample-5", title: "午餐", amount: 150, amountText: "NT$150",
                                categoryKey: "sample-food", icon: "fork.knife",
                                top: 0xFFB45E, bottom: 0xEE5E3B, tint: 0xEE5E3B, count: 4),
            WidgetQuickTemplate(id: "sample-6", title: "捷運", amount: 35, amountText: "NT$35",
                                categoryKey: "sample-transport", icon: "tram.fill",
                                top: 0x7FE3D0, bottom: 0x1A9C8C, tint: 0x138A7E, count: 3),
            WidgetQuickTemplate(id: "sample-7", title: "加油", amount: 1200, amountText: "NT$1,200",
                                categoryKey: "sample-car", icon: "fuelpump.fill",
                                top: 0x7FE3D0, bottom: 0x1A9C8C, tint: 0x138A7E, count: 3)
        ]
    }
}
