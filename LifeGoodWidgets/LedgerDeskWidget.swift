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
            LedgerDeskEntryView(entry: entry)
        }
        .configurationDisplayName("記帳台")
        .description("看還能花，一按就記帳")
        .supportedFamilies([.systemMedium])
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
