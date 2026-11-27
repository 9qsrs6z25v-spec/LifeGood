import SwiftUI
import WidgetKit
import AppIntents

// MARK: - 記帳台（systemMedium）：左半還能花、右半四張卡（連結）（小工具 v2）
//
// 只屬於「LifeGoodWidgets」target。規格見 scratchpad/widgets/v2/brief.md 的 G3-3；
// 樣稿 mock_spec ledger-desk-medium（J:183-231）。
//
// • 左半：WidgetMoneyPanel（還能花、今天、收入），點了 → 收支總覽。
// • 右半 2×2：WidgetMoneySnapshot.deskTiles()（App 已經挑好四張、網址組好）：最常記的兩個分類、
//   車子卡（「⚡ Taycan 電費」；沒車＝第三多的分類）、「＋ 記一筆」。每張各自一個 Link →
//   新增支出、分類／車子帶好、數字鍵盤跳出（App 的快速通道）。**都是使用者按儲存才算**，小工具不寫資料。
//   四張卡沒有金額（J:226），隱藏金額只影響左半。
// • v1 舊檔（沒有分類，hasDeskData 是 false）：右半只放「＋ 記一筆」一張。
// • 不設整塊 .widgetURL：每一塊各自 Link。
//
// 換日、跨月：timeline 直接用 v1 的 MoneyLeftTimeline（每天 00:00、快照變舊那一刻）。
//
// [v3] 長按可設定（AppIntentConfiguration＋LedgerDeskConfigIntent，WidgetConfigs.swift；kind 不變）：
//   • 按鈕 1／2／3：自動（預設，照 v2 的挑法）、🎤 說一句（紫）、新增收入（綠）、14 個變動分類、每台車的車子分類。
//     卡由 WidgetMoneySnapshot.deskTiles(choiceIDs:) 挑（契約）；三格都自動＝跟 v2 一模一樣。第 4 格固定「＋ 記一筆」。
//     說一句、新增收入的卡畫法同分類卡（漸層＋白字）；只有「＋ 記一筆」是淺底。
//   • 金額：跟著總開關（預設）／一律隱藏（左半改 App 寫好的隱藏版「本月已花／62%／還有 19 天／今天 3 筆」）。
//   • relevance（LedgerDeskRelevance）：中午 11:00–13:30、晚上 17:30–20:00 的 entry 掛 score 1，
//     其他 score 0，讓智慧型堆疊吃飯時間比較常把記帳台轉上來（系統決定，不保證）。只用 iOS 14 就有的
//     TimelineEntryRelevance(score:duration:)，不用 iOS 18 的 relevances()。
//
// 型別（internal 的都帶 LedgerDesk 前綴；畫面零件 private）：
//   LedgerDeskWidget、LedgerDeskEntry、LedgerDeskProvider、LedgerDeskSample、LedgerDeskEntryView、
//   LedgerDeskCardBackground（一按就記的按鈕也用這個底）
//   [v3] private：LedgerDeskRelevance、LedgerDeskRelevanceWindow、LedgerDeskRelevanceSpan

// MARK: - Widget

struct LedgerDeskWidget: Widget {
    var body: some WidgetConfiguration {
        // [v3] StaticConfiguration → AppIntentConfiguration（kind 不變：已經放好的升級後用預設值、外觀一樣）
        AppIntentConfiguration(kind: WidgetKind.ledgerDesk, intent: LedgerDeskConfigIntent.self,
                               provider: LedgerDeskProvider()) { entry in
            LedgerDeskRootView(entry: entry)
        }
        .configurationDisplayName("記帳台")
        .description("看還能花，一按就記帳；大的上面整排還能花、中間四張大卡、下面今天記的")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Timeline

struct LedgerDeskEntry: TimelineEntry {
    /// 畫面一律拿這個當「現在」
    let date: Date
    /// nil＝還沒打開過新版 App（或檔案讀不到）
    let snapshot: WidgetMoneySnapshot?
    /// 「隱藏金額」開著（provider 讀一次）。
    /// [v3] ＝長按設定的「金額」.hides(master: 總開關)：一律隱藏、或總開關開著
    let hidesAmounts: Bool
    /// [v3] 長按設定的按鈕 1／2／3（WidgetDeskButtonEntity.id；nil＝自動）。預覽、placeholder 全自動
    var choiceIDs: [String?] = [nil, nil, nil]
    /// [v3] 智慧型堆疊用：吃飯時段 score 1、其他 score 0（LedgerDeskRelevance）；預覽、placeholder 是 nil
    var relevance: TimelineEntryRelevance? = nil
}

/// [v3] TimelineProvider → AppIntentTimelineProvider（多讀長按設定；排程＝MoneyLeftTimeline ∪ 吃飯時段的頭尾）
struct LedgerDeskProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LedgerDeskEntry {
        let now = Date()
        return LedgerDeskEntry(date: now, snapshot: LedgerDeskSample.snapshot(at: now), hidesAmounts: false)
    }

    func snapshot(for configuration: LedgerDeskConfigIntent, in context: Context) async -> LedgerDeskEntry {
        let now = Date()
        if context.isPreview {
            // 小工具庫裡的預覽：寫死的展示字（三格自動，跟 v2 一樣）
            return LedgerDeskEntry(date: now, snapshot: LedgerDeskSample.snapshot(at: now), hidesAmounts: false)
        }
        let snapshot = WidgetSnapshotStore.read(WidgetMoneySnapshot.self)
        let hidden: Bool = configuration.amount.hides(master: WidgetHideAmounts.isOn)
        return LedgerDeskEntry(date: now, snapshot: snapshot, hidesAmounts: hidden,
                               choiceIDs: configuration.choiceIDs)
    }

    func timeline(for configuration: LedgerDeskConfigIntent, in context: Context) async -> Timeline<LedgerDeskEntry> {
        let now = Date()
        let snapshot = WidgetSnapshotStore.read(WidgetMoneySnapshot.self)
        let hidden: Bool = configuration.amount.hides(master: WidgetHideAmounts.isOn)
        let choices: [String?] = configuration.choiceIDs
        let spans: [LedgerDeskRelevanceSpan] = LedgerDeskRelevance.spans(now: now)
        let dates: [Date] = LedgerDeskRelevance.entryDates(snapshot: snapshot, now: now, spans: spans)
        let entries: [LedgerDeskEntry] = dates.map {
            LedgerDeskEntry(date: $0, snapshot: snapshot, hidesAmounts: hidden, choiceIDs: choices,
                            relevance: LedgerDeskRelevance.relevance(at: $0, spans: spans))
        }
        let policy = MoneyLeftTimeline.policy(snapshot: snapshot, dates: dates, now: now)
        return Timeline(entries: entries, policy: policy)
    }
}

// MARK: - [v3] 智慧型堆疊：吃飯時段往前排（J:619）

/// 一天裡的一個吃飯時段（本地時間，Calendar.current）
private struct LedgerDeskRelevanceWindow {
    let startHour: Int
    let startMinute: Int
    let endHour: Int
    let endMinute: Int
}

/// 某一天的那一段（含開始、不含結束）
private struct LedgerDeskRelevanceSpan {
    let start: Date
    let end: Date

    func contains(_ date: Date) -> Bool {
        start <= date && date < end
    }
}

/// 只排時間、打分數，不碰金額。timeline 已經排到月底後一個多月，吃飯時段只排今天起 7 天
///（每段頭尾各一筆，最多 28 筆；App 一週內總會再寫快照、叫重畫，再往後排）
private enum LedgerDeskRelevance {
    /// 中午 11:00–13:30、晚上 17:30–20:00
    static let windows: [LedgerDeskRelevanceWindow] = [
        LedgerDeskRelevanceWindow(startHour: 11, startMinute: 0, endHour: 13, endMinute: 30),
        LedgerDeskRelevanceWindow(startHour: 17, startMinute: 30, endHour: 20, endMinute: 0)
    ]
    /// 今天起排幾天
    static let dayCount = 7

    /// 今天起 dayCount 天的每一段（依時間排好）
    static func spans(now: Date) -> [LedgerDeskRelevanceSpan] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var out: [LedgerDeskRelevanceSpan] = []
        for offset in 0..<dayCount {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            for window in windows {
                if let piece = makeSpan(window, on: day, calendar: cal) {
                    out.append(piece)
                }
            }
        }
        return out
    }

    private static func makeSpan(_ window: LedgerDeskRelevanceWindow, on day: Date,
                                 calendar cal: Calendar) -> LedgerDeskRelevanceSpan? {
        guard let start = cal.date(bySettingHour: window.startHour, minute: window.startMinute, second: 0, of: day),
              let end = cal.date(bySettingHour: window.endHour, minute: window.endMinute, second: 0, of: day),
              end > start else { return nil }
        return LedgerDeskRelevanceSpan(start: start, end: end)
    }

    /// MoneyLeftTimeline 的時間點 ∪ 每一段的開始、結束（比 now 晚才放）。沒快照只有 now（不加）
    static func entryDates(snapshot: WidgetMoneySnapshot?, now: Date,
                           spans: [LedgerDeskRelevanceSpan]) -> [Date] {
        let base: [Date] = MoneyLeftTimeline.entryDates(snapshot: snapshot, now: now)
        guard snapshot != nil else { return base }
        var all = Set<Date>(base)
        for span in spans {
            if span.start > now { all.insert(span.start) }
            if span.end > now { all.insert(span.end) }
        }
        return all.sorted()
    }

    /// 落在某一段裡：score 1、有效到那一段結束；其他：score 0（有效到下一筆 entry）
    static func relevance(at date: Date, spans: [LedgerDeskRelevanceSpan]) -> TimelineEntryRelevance {
        guard let hit = spans.first(where: { $0.contains(date) }) else {
            return TimelineEntryRelevance(score: 0, duration: 0)
        }
        let left: TimeInterval = hit.end.timeIntervalSince(date)
        return TimelineEntryRelevance(score: 1, duration: left)
    }
}

// MARK: - 挑卡（只挑、不算）

private enum LedgerDeskModel {
    /// 右半要畫的卡：照長按設定挑（WidgetMoneySnapshot.deskTiles(choiceIDs:)，id 已帶格子編號、不重複），
    /// 沒快照只有「＋ 記一筆」。
    /// [v3] 不再先看 hasDeskData：v1 舊檔（沒有分類）三格自動時 deskTiles(choiceIDs:) 本來就只回「＋ 記一筆」
    ///（跟 v2 一樣），但指定了「說一句」「新增收入」的格子照樣畫得出來
    static func tiles(snapshot: WidgetMoneySnapshot?, choiceIDs: [String?]) -> [WidgetDeskTile] {
        guard let snap = snapshot else { return [WidgetDeskTile.addExpense] }
        var seen = Set<String>()
        var out: [WidgetDeskTile] = []
        for tile in snap.deskTiles(choiceIDs: choiceIDs) where !seen.contains(tile.id) {
            seen.insert(tile.id)
            out.append(tile)
        }
        if out.count > 4 {
            // deskTiles(choiceIDs:) 最多 4 張；保險起見留前三張＋最後的「記一筆」
            let add = out[out.count - 1]
            out = Array(out.prefix(3)) + [add]
        }
        return out
    }
}

/// 小工具庫預覽與 placeholder 的樣本。**寫死的展示字，不是計算**（J:192-199 的字）。
/// 分類 key 刻意用 App 認不得的「sample-…」：萬一被點到，App 解不開就開空白的新增支出，
/// 不會把展示用的字當成真的分類（v25.454 的教訓）。
enum LedgerDeskSample {
    static func snapshot(at now: Date) -> WidgetMoneySnapshot {
        var snap = MoneyLeftSample.snapshot(at: now)
        if !snap.days.isEmpty {
            snap.days[0].todayText = "今天 NT$1,240・3 筆"
            snap.days[0].todayCount = 3
            snap.days[0].incomeText = "收入 NT$12萬・預估"
            snap.days[0].masked = WidgetMoneyMasked(title: "本月已花", hero: "62%",
                                                    line: "還有 19 天", footer: "今天 3 筆")
            snap.days[0].lock = WidgetMoneyLock(ringValue: 0.62, ringText: "62%",
                                                ringCaption: "已花", inlineText: "今天 3 筆・已花 62%")
        }
        let food = WidgetCategory(key: "sample-food", title: "飲食", icon: "fork.knife",
                                  top: 0xFFB45E, bottom: 0xEE5E3B, tint: 0xEE5E3B)
        let shopping = WidgetCategory(key: "sample-shopping", title: "購物", icon: "cart.fill",
                                      top: 0xFF9CBB, bottom: 0xE0457A, tint: 0xE0457A)
        snap.categories = [food, shopping]
        snap.topCategoryKeys = [food.key, shopping.key]
        snap.vehicleCard = WidgetVehicleCard(vehicleId: sampleVehicleId, vehicleName: "Taycan",
                                             categoryKey: "sample-electricity", title: "Taycan 電費",
                                             icon: "bolt.fill", top: 0x7FE3D0, bottom: 0x1A9C8C, tint: 0x138A7E)
        snap.templates = []
        snap.todayEntries = LedgerDeskLargeSample.todayEntries
        return snap
    }

    /// 固定的假 UUID（每次預覽卡片 id 都一樣）
    private static let sampleVehicleId = UUID(uuidString: "00000000-0000-0000-0000-00000000CA45") ?? UUID()
}

// MARK: - 畫面

struct LedgerDeskEntryView: View {
    let entry: LedgerDeskEntry

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    private var surface: WidgetPalette.Surface {
        WidgetPalette.Surface(renderingMode: renderingMode, showsBackground: showsBackground)
    }

    private var palette: WidgetPalette {
        WidgetPalette(colorScheme, mono: surface.isMono)
    }

    private var tiles: [WidgetDeskTile] {
        LedgerDeskModel.tiles(snapshot: entry.snapshot, choiceIDs: entry.choiceIDs)
    }

    var body: some View {
        HStack(spacing: 12) {
            Link(destination: WidgetLink.expenseOverview) {
                WidgetMoneyPanel(snapshot: entry.snapshot, now: entry.date,
                                 hidden: entry.hidesAmounts, palette: palette)
            }
            LedgerDeskGrid(tiles: tiles, palette: palette)
        }
        .containerBackground(for: .widget) {
            backgroundView
        }
    }

    /// 著色不畫天空；雲／月牙放左上日期旁（右半有卡）
    @ViewBuilder
    private var backgroundView: some View {
        if surface.drawsSky {
            WidgetSky(palette: palette, moon: .topLeading)
        } else {
            Color.clear
        }
    }
}

/// 右半 2×2（每兩張一列；只有一張時那一張佔滿右半）
private struct LedgerDeskGrid: View {
    let tiles: [WidgetDeskTile]
    let palette: WidgetPalette

    private var topRow: [WidgetDeskTile] { Array(tiles.prefix(2)) }
    private var bottomRow: [WidgetDeskTile] { Array(tiles.dropFirst(2).prefix(2)) }

    var body: some View {
        VStack(spacing: 8) {
            row(topRow)
            if !bottomRow.isEmpty {
                row(bottomRow)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ items: [WidgetDeskTile]) -> some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.id) { tile in
                Link(destination: tile.url) {
                    LedgerDeskTileView(tile: tile, palette: palette)
                }
            }
        }
    }
}

/// 一張卡：左上白色圖示、左下白字（「＋ 記一筆」是淺底藍圖示）；著色模式外框＋重點色圖示。
/// [v3] 🎤 說一句（紫）、新增收入（綠）跟分類卡同一個畫法（漸層＋白字）：只有 .add 是淺底，isAdd 判斷不變
private struct LedgerDeskTileView: View {
    let tile: WidgetDeskTile
    let palette: WidgetPalette

    private var isAdd: Bool { tile.style == .add }

    private var iconColor: Color {
        if palette.isMono { return palette.ink }
        return isAdd ? palette.deskAddIcon : palette.tileInk
    }

    private var textColor: Color {
        if palette.isMono { return palette.ink }
        return isAdd ? palette.ink : palette.tileInk
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: tile.icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(iconColor)
                .widgetAccentable()
            Spacer(minLength: 2)
            Text(tile.title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            LedgerDeskCardBackground(top: tile.top, bottom: tile.bottom, plain: isAdd, palette: palette)
        }
    }
}

/// 卡片底（記帳台的卡、一按就記的按鈕共用）：
/// 分類／車子／範本＝App 分類卡的兩色漸層（深色再壓 15% 黑）；plain＝「＋ 記一筆」的淺底；
/// 著色模式（含 StandBy）＝只畫外框。
struct LedgerDeskCardBackground: View {
    let top: UInt32
    let bottom: UInt32
    /// 「＋ 記一筆」那種淺底（不用 top／bottom）
    let plain: Bool
    let palette: WidgetPalette
    var cornerRadius: CGFloat = 14

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var gradient: LinearGradient {
        LinearGradient(colors: [Color(widgetHex: top), Color(widgetHex: bottom)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 深色：同淺色漸層壓 15% 黑（mock_spec）
    private var shade: Double { palette.isDark ? 0.15 : 0 }

    var body: some View {
        if palette.isMono {
            shape.strokeBorder(palette.tileOutline, lineWidth: 1.2)
        } else if plain {
            shape.fill(palette.deskAddFill)
        } else {
            ZStack {
                shape.fill(gradient)
                shape.fill(Color.black.opacity(shade))
            }
        }
    }
}

// MARK: - 大型（v25.632 large2）
//
// judge_largewidgets.md §C 第二版 C3、brief §2 G3。同一個 kind、同一個 timeline（LedgerDeskProvider 一字不動），
// LedgerDeskRootView 依尺寸分：大型 → LedgerDeskLargeEntryView，其他（中型）→ 既有 LedgerDeskEntryView（一字不動）。
// • 上半整寬：WidgetMoneyPanelWide（WidgetMoneyPanel.swift 檔尾；跟中型左半同一組字），點了 → 收支總覽。
// • 下半 2×2 大卡片：跟中型同一組卡（LedgerDeskModel.tiles(snapshot:choiceIDs:)，長按設定照用），卡上沒有金額；
//   每張各自一個 Link → 新增支出、分類／車子帶好（使用者按儲存才算）。一排只有 1 張時那張佔滿整排。
// • 放不下只砍卡片高（76 → 68 → 60）、再拿掉頁腳，字級不變（LedgerDeskLargeLayout.candidates，ViewThatFits 4 個候選）。
// • 上半與卡片之間 Spacer(minLength: 12)：卡片貼底、手指好按（第三版「今天記的」放那裡）。
// • 整塊 widgetURL＝收支總覽（空白處的後備）。
//
// 型別：LedgerDeskRootView（internal）；LedgerDeskLargeModel 與畫面零件 private。

/// 依尺寸分：大型 → LedgerDeskLargeEntryView；其他 → 既有 LedgerDeskEntryView（中型原封不動）
struct LedgerDeskRootView: View {
    let entry: LedgerDeskEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .systemLarge {
            LedgerDeskLargeEntryView(entry: entry)
        } else {
            LedgerDeskEntryView(entry: entry)
        }
    }
}

/// 大型要的東西：上半的字、卡、今天記的、4 個候選（只挑、不算；sim ld3_large_make）
/// [v25.637 large3] 候選改用 LedgerDeskTodayLayout（今天記的 0 筆＝第二版的候選逐一相同）；
/// 每個候選先切好今天記的幾筆、右邊「共 N 筆」（View 不切陣列）。
private struct LedgerDeskLargeModel {
    let panel: WidgetMoneyPanelWideModel
    let tiles: [WidgetDeskTile]
    /// 今天記的（最多 4 筆，最新的在前；過了午夜、舊快照、不是 .day 時空的）
    let today: [LedgerDeskTodayRow]
    /// 固定 4 個（大到小）
    let candidates: [LedgerDeskLargeCandidate]

    /// 安全取值：index 夾在 0...count-1；沒有候選回最矮、不帶頁腳、沒有今天記的
    func candidate(at index: Int) -> LedgerDeskLargeCandidate {
        guard !candidates.isEmpty else {
            let plan = LedgerDeskTodayLayout.Plan(tileHeight: LedgerDeskLargeLayout.compactTileHeight,
                                                  showsFooter: false, todayRows: 0)
            return LedgerDeskLargeCandidate(id: 0, plan: plan, today: [], trailing: "")
        }
        let i: Int = min(max(index, 0), candidates.count - 1)
        return candidates[i]
    }

    static func make(entry: LedgerDeskEntry) -> LedgerDeskLargeModel {
        let panel = WidgetMoneyPanelWideModel.make(snapshot: entry.snapshot, now: entry.date, hidden: entry.hidesAmounts)
        let tiles: [WidgetDeskTile] = LedgerDeskModel.tiles(snapshot: entry.snapshot, choiceIDs: entry.choiceIDs)
        var rows: [LedgerDeskTodayRow] = []
        var total: Int = 0
        if panel.kind == .day, let snap = entry.snapshot, let day = snap.day(at: entry.date) {
            let entries: [WidgetMoneyTodayEntry] = snap.todayEntryRows(dayKey: day.dayKey) ?? []
            rows = entries.prefix(LedgerDeskTodayLayout.maxRows).map { (e: WidgetMoneyTodayEntry) -> LedgerDeskTodayRow in
                row(e, snap: snap, hidden: entry.hidesAmounts)
            }
            total = day.todayCount ?? rows.count
        }
        let plans: [LedgerDeskTodayLayout.Plan] = LedgerDeskTodayLayout.candidates(tileCount: tiles.count,
                                                                                   hasFooter: !panel.footer.isEmpty,
                                                                                   entryCount: rows.count)
        var out: [LedgerDeskLargeCandidate] = []
        for (i, plan) in plans.enumerated() {
            out.append(makeCandidate(id: i, plan: plan, rows: rows, total: total))
        }
        return LedgerDeskLargeModel(panel: panel, tiles: tiles, today: rows, candidates: out)
    }

    /// 一個候選：今天記的先切好；放得下的比今天記的少時右邊寫「共 N 筆」
    private static func makeCandidate(id: Int, plan: LedgerDeskTodayLayout.Plan, rows: [LedgerDeskTodayRow],
                                      total: Int) -> LedgerDeskLargeCandidate {
        let shown: [LedgerDeskTodayRow] = Array(rows.prefix(max(0, plan.todayRows)))
        let trailing: String = plan.todayRows > 0 && total > shown.count ? "共 \(total) 筆" : ""
        return LedgerDeskLargeCandidate(id: id, plan: plan, today: shown, trailing: trailing)
    }

    /// 一筆：時間、分類（圖示、名稱、色）、金額（隱藏時用 App 寫好的遮罩版）。不算錢、不拼 NT$
    private static func row(_ e: WidgetMoneyTodayEntry, snap: WidgetMoneySnapshot, hidden: Bool) -> LedgerDeskTodayRow {
        let c: WidgetCategory? = snap.category(forKey: e.categoryKey)
        return LedgerDeskTodayRow(id: e.id, time: e.timeText, icon: c?.icon ?? "", tint: c?.tint,
                                  title: c?.title ?? e.categoryKey,
                                  amount: hidden ? e.amountTextMasked : e.amountText)
    }
}

/// 大型：palette／surface 同中型；天空月牙放右上（上半右邊比較空）
private struct LedgerDeskLargeEntryView: View {
    let entry: LedgerDeskEntry

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    private var surface: WidgetPalette.Surface {
        WidgetPalette.Surface(renderingMode: renderingMode, showsBackground: showsBackground)
    }

    private var palette: WidgetPalette {
        WidgetPalette(colorScheme, mono: surface.isMono)
    }

    private var model: LedgerDeskLargeModel {
        LedgerDeskLargeModel.make(entry: entry)
    }

    var body: some View {
        LedgerDeskLargeBoard(model: model, palette: palette)
            .containerBackground(for: .widget) {
                backgroundView
            }
            .widgetURL(WidgetLink.expenseOverview)
    }

    /// 著色不畫天空
    @ViewBuilder
    private var backgroundView: some View {
        if surface.drawsSky {
            WidgetSky(palette: palette, moon: .topTrailing)
        } else {
            Color.clear
        }
    }
}

/// 4 個候選由上往下挑（字級不變、只砍卡片高與頁腳；不巢狀 ViewThatFits）
private struct LedgerDeskLargeBoard: View {
    let model: LedgerDeskLargeModel
    let palette: WidgetPalette

    var body: some View {
        ViewThatFits(in: .vertical) {
            LedgerDeskLargeColumn(model: model, candidate: model.candidate(at: 0), palette: palette)
            LedgerDeskLargeColumn(model: model, candidate: model.candidate(at: 1), palette: palette)
            LedgerDeskLargeColumn(model: model, candidate: model.candidate(at: 2), palette: palette)
            LedgerDeskLargeColumn(model: model, candidate: model.candidate(at: 3), palette: palette)
        }
    }
}

/// 上半（固定高）→ Spacer（至少 12）→ 卡片 →（有的話）今天記的。LedgerDeskTodayLayout.height 算的就是這一欄；
/// 今天記的 0 筆時跟第二版一模一樣（卡片貼底）
private struct LedgerDeskLargeColumn: View {
    let model: LedgerDeskLargeModel
    let candidate: LedgerDeskLargeCandidate
    let palette: WidgetPalette

    private var plan: LedgerDeskTodayLayout.Plan { candidate.plan }

    private var gap: CGFloat {
        model.tiles.isEmpty ? 0 : LedgerDeskLargeLayout.gridTopGap
    }

    var body: some View {
        VStack(spacing: 0) {
            Link(destination: WidgetLink.expenseOverview) {
                WidgetMoneyPanelWide(model: model.panel, showsFooter: plan.showsFooter, palette: palette)
            }
            Spacer(minLength: gap)
            LedgerDeskLargeGrid(tiles: model.tiles, tileHeight: plan.tileHeight, palette: palette)
            today
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 今天記的（候選已經切好幾筆；空的不畫，連區標）。點了 → 收支總覽
    @ViewBuilder
    private var today: some View {
        if !candidate.today.isEmpty {
            Link(destination: WidgetLink.expenseOverview) {
                LedgerDeskLargeToday(rows: candidate.today, trailing: candidate.trailing, palette: palette)
            }
        }
    }
}

/// 2×2（前 2 張一排、第 3–4 張一排；沒有就不畫）。每排高度＝候選的卡片高
private struct LedgerDeskLargeGrid: View {
    let tiles: [WidgetDeskTile]
    let tileHeight: CGFloat
    let palette: WidgetPalette

    private var topRow: [WidgetDeskTile] { Array(tiles.prefix(2)) }
    private var bottomRow: [WidgetDeskTile] { Array(tiles.dropFirst(2).prefix(2)) }

    var body: some View {
        VStack(spacing: LedgerDeskLargeLayout.tileSpacing) {
            if !topRow.isEmpty {
                row(topRow)
            }
            if !bottomRow.isEmpty {
                row(bottomRow)
            }
        }
    }

    private func row(_ items: [WidgetDeskTile]) -> some View {
        HStack(spacing: LedgerDeskLargeLayout.tileSpacing) {
            ForEach(items, id: \.id) { (tile: WidgetDeskTile) in
                Link(destination: tile.url) {
                    LedgerDeskLargeTileView(tile: tile, palette: palette)
                }
            }
        }
        .frame(height: tileHeight)
    }
}

/// 一張大卡：左上圖示、左下字（同中型卡的畫法，字大一點）；「＋ 記一筆」淺底；著色模式外框＋重點色圖示
private struct LedgerDeskLargeTileView: View {
    let tile: WidgetDeskTile
    let palette: WidgetPalette

    private var isAdd: Bool { tile.style == .add }

    private var iconColor: Color {
        if palette.isMono { return palette.ink }
        return isAdd ? palette.deskAddIcon : palette.tileInk
    }

    private var textColor: Color {
        if palette.isMono { return palette.ink }
        return isAdd ? palette.ink : palette.tileInk
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: tile.icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(iconColor)
                .widgetAccentable()
            Spacer(minLength: 2)
            Text(tile.title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            LedgerDeskCardBackground(top: tile.top, bottom: tile.bottom, plain: isAdd, palette: palette)
        }
    }
}

// MARK: - 大型「今天記的」（v25.637 large3）
//
// judge_largewidgets.md §C 第三版 C3、brief §2 G3。money 快照頂層 todayEntries（App 在 3 秒防抖裡寫好，最多 4 筆、
// 最新的在前），只在畫的那一天＝快照的 dataDay 才畫（snap.todayEntryRows(dayKey:)）。一筆只有時間、分類、金額：
// 「12:10 🍴 飲食 ｜ NT$180」；不放名稱、備註、店名、地點、同行人員。隱藏金額時用 App 寫好的遮罩版。
// 放不下照順序砍（LedgerDeskTodayLayout.candidates）：筆數 4→3→2→1、先帶頁腳再不帶、卡片 76→68→60；都不行＝第二版。
//
// 型別：LedgerDeskLargeSample（internal）；LedgerDeskTodayRow、LedgerDeskLargeCandidate 與畫面零件 private。

/// 今天記的一筆（畫面要的字；只挑、不算）
private struct LedgerDeskTodayRow: Identifiable {
    let id: String
    /// 「12:10」
    let time: String
    /// SF Symbol（快照沒有這個分類時空字串，不畫）
    let icon: String
    /// 分類色（0xRRGGBB）；nil＝用 label 色
    let tint: UInt32?
    /// 分類名稱「飲食」
    let title: String
    /// 「NT$180」／「JPY 15,238」；隱藏時「NT$ ••••」
    let amount: String
}

/// 一個候選：版面（卡片高、頁腳、今天記的幾筆）＋今天記的先切好＋右邊「共 N 筆」（沒有＝空字串）
private struct LedgerDeskLargeCandidate: Identifiable {
    let id: Int
    let plan: LedgerDeskTodayLayout.Plan
    let today: [LedgerDeskTodayRow]
    let trailing: String
}

/// 區標＋每筆一列（固定高：LedgerDeskTodayLayout.todayHeight）
private struct LedgerDeskLargeToday: View {
    let rows: [LedgerDeskTodayRow]
    let trailing: String
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LedgerDeskLargeTodayLabel(trailing: trailing, palette: palette)
            ForEach(rows, id: \.id) { (row: LedgerDeskTodayRow) in
                LedgerDeskLargeTodayRow(row: row, palette: palette)
                    .frame(height: LedgerDeskTodayLayout.rowHeight)
            }
        }
    }
}

/// 「今天記的」＋右邊「共 5 筆」（空的不畫）；上面空、字貼底
private struct LedgerDeskLargeTodayLabel: View {
    let trailing: String
    let palette: WidgetPalette

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text("今天記的")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(palette.label)
            Spacer(minLength: 6)
            if !trailing.isEmpty {
                Text(trailing)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.label)
            }
        }
        .padding(.bottom, 3)
        .frame(maxWidth: .infinity, minHeight: LedgerDeskTodayLayout.sectionHeight,
               maxHeight: LedgerDeskTodayLayout.sectionHeight, alignment: .bottom)
    }
}

/// 「12:10 🍴 飲食 ……… NT$180」
private struct LedgerDeskLargeTodayRow: View {
    let row: LedgerDeskTodayRow
    let palette: WidgetPalette

    private var iconColor: Color {
        if palette.isMono { return palette.ink }
        return row.tint.map { Color(widgetHex: $0) } ?? palette.label
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(row.time)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(palette.label)
                .fixedSize()
            icon
            Text(row.title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(row.amount)
                .font(.system(size: 11.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    @ViewBuilder
    private var icon: some View {
        if !row.icon.isEmpty {
            Image(systemName: row.icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(iconColor)
                .frame(width: 14)
        }
    }
}

/// 小工具庫預覽的今天記的（寫死的展示字；key 用 sample-…，跟 LedgerDeskSample 的分類對得上）。
/// 樣本的 todayCount 是 3，不寫「共 N 筆」
enum LedgerDeskLargeSample {
    static let todayEntries: [WidgetMoneyTodayEntry] = [
        WidgetMoneyTodayEntry(id: "sample-t1", timeText: "12:10", categoryKey: "sample-food",
                              amountText: "NT$180", amountTextMasked: WidgetHideAmounts.mask),
        WidgetMoneyTodayEntry(id: "sample-t2", timeText: "08:40", categoryKey: "sample-shopping",
                              amountText: "NT$65", amountTextMasked: WidgetHideAmounts.mask),
        WidgetMoneyTodayEntry(id: "sample-t3", timeText: "08:05", categoryKey: "sample-food",
                              amountText: "NT$35", amountTextMasked: WidgetHideAmounts.mask),
    ]
}
