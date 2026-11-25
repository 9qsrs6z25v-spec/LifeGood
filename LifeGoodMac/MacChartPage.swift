// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.645 mac5 G2] 電腦版第 5 頁：圖表（judge_mac.md §S5-2、§S5-4）：夜空看板＋趨勢卡＋圓餅卡＋本月比例與分帳＋明細表。
//
// • 整頁 VStack(spacing: 12)，不用 ScrollView（Table 不能放進 ScrollView）。
// • 重活（點、兩個圓餅）放 MacChartCache（class，不是 store）；明細列照 focus 每次重算；不在 body 寫任何 store。
// • 明細表照 MacIncomeTableView（MacIncomePage.swift:363-433）：Table(rows, selection:, sortOrder:)、每欄一支寫死型別的 TableColumn 函式、
//   Cell 只有 let 與 body；右鍵、連按兩下、⌫ 一律叫 MacEditCenter 現成的 8 支（requestEdit／requestDuplicate／requestStop／requestDelete／
//   canEdit／canDuplicate／canStop／canDelete）。
// • 主控骨架：struct MacChartPage: View 無參數（MacShell 的 case .chart 用）；G2 換內容。

import SwiftUI

/// 圓餅卡看哪一種（不存）
enum MacChartPieKind: String, CaseIterable, Hashable {
    case variable = "變動"
    case fixed = "固定"
}

struct MacChartPage: View {
    @EnvironmentObject private var money: MacMoneyStore
    @EnvironmentObject private var ui: MacUIState
    @EnvironmentObject private var edit: MacEditCenter
    /// 照 iPhone 預設「日」；不記住（L6）
    @State private var period: TimePeriod = .daily
    @State private var pie: MacChartPieKind = .variable
    /// nil＝最後一期
    @State private var focus: MacChartFocus? = nil
    /// chartXSelection 選到的 label（放開滑鼠會變回 nil；focus 留著；focus 被別的地方改掉時清成 nil）
    @State private var picked: String? = nil
    /// 空＝照 chartRows 建好的順序（T6）
    @State private var sortOrder: [MacChartSort] = []
    @State private var cache = MacChartCache()

    var body: some View {
        let now = Date()
        let calendar = Calendar.current
        let screen: MacChartScreen = MacChartScreen.make(money: money, period: period, pie: pie, focus: focus, order: sortOrder,
                                                         cache: cache, now: now, calendar: calendar)
        let key = MacChartGuardKey(selection: ui.selection, period: period, pie: pie, focus: focus,
                                   alive: MacChartGuardKey.isAlive(ui.selection, money: money))
        MacChartLayout(screen: screen, period: $period, pie: $pie, focus: $focus, picked: pickBinding(screen.selectedLabel),
                       sortOrder: $sortOrder, ui: ui, edit: edit, money: money)
            .navigationSubtitle(screen.boardTitle)
            .onChange(of: period) { _, _ in
                // 換期間：明細回到最後一期、選取的長條清掉（選取守門另外清 ui.selection）
                focus = nil
                picked = nil
            }
            .onChange(of: picked) { _, v in
                if let v { focus = .period(v) }
            }
            .onChange(of: focus) { _, f in
                // 圖例、〔換一期〕、〔回到最近一期〕改了 focus：長條的選取放掉（虛線改照 focus 畫；
                // macOS 放開後 picked 若沒變回 nil，再點同一根也會換回那一期）
                if let p = picked, f != MacChartFocus.period(p) { picked = nil }
            }
            .modifier(MacChartSelectionGuard(key: key, ui: ui))
    }

    /// 長條的選取：拖曳中＝picked；放開後虛線與金額留在 focus 那一期（沒點過＝不畫）
    private func pickBinding(_ fallback: String?) -> Binding<String?> {
        Binding<String?>(get: { picked ?? fallback }, set: { v in picked = v })
    }
}

// MARK: - 重活的快取（class，不是 store；鍵換了才重算）

/// 鍵：期間＋每個讀的鍵的 changeTag＋那一天（跨午夜鍵換新）＋那一分鐘（今天稍晚的帳到點才算，跟 iPhone 同一分鐘一樣）
/// ＋顯示快照的狀態（快照不進 records）＋筆數
struct MacChartCacheKey: Equatable {
    let period: TimePeriod
    let tags: String
    let day: Date
    let minute: Int
    let showingCache: Bool
    let savedAt: Date?
    let account: String?
    let count: Int

    @MainActor
    static func make(money: MacMoneyStore, period: TimePeriod, now: Date, calendar: Calendar) -> MacChartCacheKey {
        var tags = ""
        for k in money.records.keys.sorted() {
            let tag: String = money.records[k]?.changeTag ?? "-"
            tags += k + "=" + tag + "|"
        }
        let minute = Int(now.timeIntervalSinceReferenceDate / 60)
        return MacChartCacheKey(period: period, tags: tags, day: calendar.startOfDay(for: now), minute: minute,
                                showingCache: money.showingCache, savedAt: money.cacheSavedAt, account: money.accountHash,
                                count: money.expenses.count)
    }
}

@MainActor
final class MacChartCache {
    private var key: MacChartCacheKey? = nil
    private(set) var points: [ChartDataPoint] = []
    private(set) var variable: [(category: VariableCategory, amount: Double)] = []
    private(set) var fixed: [(group: MacFixedGroupKey, amount: Double)] = []
    private(set) var mix: MacChartMix = .zero
    private(set) var splitNote: String? = nil

    /// 鍵一樣就不重算（拖長條時 body 一直重畫）
    func load(money: MacMoneyStore, period: TimePeriod, now: Date, calendar: Calendar) {
        let k = MacChartCacheKey.make(money: money, period: period, now: now, calendar: calendar)
        if let old = key, old == k { return }
        key = k
        points = money.chartData(for: period, now: now, calendar: calendar)
        variable = money.variableBreakdown(for: period, now: now, calendar: calendar)
        fixed = money.fixedBreakdown(for: period, now: now, calendar: calendar)
        // ⑬ 本月支出類型比例（照抄 ChartView.swift:939-941（9f25bf5）：只看本月）
        let v = money.currentMonthVariableTotal(now: now, calendar: calendar)
        let f = money.currentMonthFixedTotal(now: now, calendar: calendar)
        mix = MacChartMix.make(variable: v, fixed: f)
        // ⑭ 分帳說明（照 ChartView.swift:335（9f25bf5）：本月、≥ 0.5 才有字）
        splitNote = MacVariableText.statsNote(money.splitDeducted(now: now, calendar: calendar))
    }
}

// MARK: - 這一頁要的東西（一次算完）

struct MacChartScreen {
    let boardTitle: String
    let chipIcon: String
    let numbers: MacChartBoardNumbers
    let line: String
    let maxText: String?
    /// 星座的值（總計 ≤ 0＝空：只畫山影）
    let skyValues: [Double]
    let hasData: Bool
    let periodTitle: String
    let pointCount: String
    let bars: [MacChartBar]
    let visible: Set<String>
    /// 使用者點過的那一期（focus＝.period 而且還在這段期間裡）
    let selectedLabel: String?
    let pie: MacChartPieData
    let mix: MacChartMix
    let splitNote: String?
    let focusTitle: String
    let rows: [MacChartRow]
    let rowCountText: String
    let rowsTotalText: String
    /// 〔換一期 ▾〕：新到舊
    let labelsNewFirst: [String]
    /// 明細正在看最後一期（不出現〔回到最近一期〕）
    let isLatest: Bool

    @MainActor
    static func make(money: MacMoneyStore, period: TimePeriod, pie: MacChartPieKind, focus: MacChartFocus?,
                     order: [MacChartSort], cache: MacChartCache, now: Date, calendar: Calendar) -> MacChartScreen {
        cache.load(money: money, period: period, now: now, calendar: calendar)
        let points: [ChartDataPoint] = cache.points
        let numbers = MacChartBoardNumbers.make(points)
        let labels: [String] = points.map { p in p.label }
        let lastLabel: String = labels.last ?? ""
        let resolved: MacChartFocus = resolve(focus, labels: labels)
        let selected: String? = pickedLabel(focus, labels: labels)
        let built: [MacChartRow] = money.chartRows(resolved, period: period, points: points, now: now, calendar: calendar)
        let rows: [MacChartRow] = order.isEmpty ? built : sort(built, by: order)
        let sum: Double = rows.reduce(0) { s, r in s + r.amount }
        let bars: [MacChartBar] = points.map { p in
            MacChartBar(label: p.label, amount: p.amount, fill: fill(p.label, selected: selected), valueText: MacText.short(p.amount))
        }
        let pieData: MacChartPieData = pie == .variable
            ? MacChartPieData.variable(cache.variable, period: period)
            : MacChartPieData.fixed(cache.fixed, period: period)
        let maxText: String? = numbers.topLabel.map { l in MacChartText.boardMaxLabel(l, period: period) }
        let skyValues: [Double] = numbers.total > 0 ? points.map { p in p.amount } : []
        return MacChartScreen(
            boardTitle: MacChartText.boardTitle(period),
            chipIcon: MacChartText.chipIcon(period),
            numbers: numbers,
            line: MacChartText.line(total: numbers.total, average: numbers.average, top: numbers.top),
            maxText: maxText,
            skyValues: skyValues,
            hasData: numbers.total > 0,
            periodTitle: MacChartText.periodTitle(period),
            pointCount: "\(points.count) 點",
            bars: bars,
            visible: MacChartText.visibleLabels(labels, period: period),
            selectedLabel: selected,
            pie: pieData,
            mix: cache.mix,
            splitNote: cache.splitNote,
            focusTitle: MacChartText.focusTitle(resolved, period: period),
            rows: rows,
            rowCountText: "\(rows.count) 筆",
            rowsTotalText: "合計 " + MacText.short(sum),
            labelsNewFirst: Array(labels.reversed()),
            isLatest: resolved == .period(lastLabel))
    }

    /// nil 或那一期已不在這段期間 → 最後一期
    static func resolve(_ focus: MacChartFocus?, labels: [String]) -> MacChartFocus {
        let last: MacChartFocus = .period(labels.last ?? "")
        guard let f = focus else { return last }
        if case .period(let l) = f, !labels.contains(l) { return last }
        return f
    }

    static func pickedLabel(_ focus: MacChartFocus?, labels: [String]) -> String? {
        guard let f = focus, case .period(let l) = f, labels.contains(l) else { return nil }
        return l
    }

    /// 長條色（§S3-4）：沒選＝trend.top；選到那根＝trend.bottom；其餘＝trend.top 0.45
    static func fill(_ label: String, selected: String?) -> Color {
        guard let s = selected else { return MacChartTheme.trend.top }
        return label == s ? MacChartTheme.trend.bottom : MacChartTheme.trend.top.opacity(0.45)
    }

    /// T6：點過欄名才排（同 MacIncomeTable.sort：同值照 id 字串）
    static func sort(_ rows: [MacChartRow], by order: [MacChartSort]) -> [MacChartRow] {
        rows.sorted { a, b in
            for c in order {
                let r = c.compare(a, b)
                if r == .orderedAscending { return true }
                if r == .orderedDescending { return false }
            }
            return a.id.id < b.id.id
        }
    }
}

/// ⑬ 本月支出類型比例一行（比例條寬 260：兩段各最少 10pt、中間空 4pt）
struct MacChartMix {
    let total: Double
    let variableWidth: CGFloat
    let fixedWidth: CGFloat
    /// 「變動 64.2%・固定 35.8%」
    let text: String

    static let zero = MacChartMix(total: 0, variableWidth: 0, fixedWidth: 0, text: "")

    static func make(variable v: Double, fixed f: Double) -> MacChartMix {
        let total = v + f
        guard total > 0 else { return zero }
        let text = "變動 " + MacChartText.percent(v / total) + "・固定 " + MacChartText.percent(f / total)
        let full: CGFloat = 260
        if v <= 0 { return MacChartMix(total: total, variableWidth: 0, fixedWidth: full, text: text) }
        if f <= 0 { return MacChartMix(total: total, variableWidth: full, fixedWidth: 0, text: text) }
        let room: CGFloat = full - 4
        let share: CGFloat = room * CGFloat(v / total)
        let wv: CGFloat = min(max(share, 10), room - 10)
        return MacChartMix(total: total, variableWidth: wv, fixedWidth: room - wv, text: text)
    }
}

// MARK: - 圓餅卡的資料（逐筆給色；圖例前 6 列）

struct MacChartLegendRow: Identifiable {
    let id: String
    let icon: String
    let tint: Color
    let name: String
    let amountText: String
    let percentText: String
    /// 比例條（已夾在 0…1）
    let fraction: Double
    let focus: MacChartFocus
}

struct MacChartPieItem {
    let id: String
    let icon: String
    let tint: Color
    let amount: Double
    let focus: MacChartFocus
}

struct MacChartPieData {
    let slices: [MacChartSlice]
    let legend: [MacChartLegendRow]
    /// 第 7 類起（照 ChartView.swift:909「還有 N 個分類」）
    let more: Int
    let center: String
    let detail: String
    let title: String
    /// 固定多一行「換算成每一天」
    let unitLine: String?
    let tint: Color

    static func variable(_ items: [(category: VariableCategory, amount: Double)], period: TimePeriod) -> MacChartPieData {
        let list: [MacChartPieItem] = items.map { it in
            MacChartPieItem(id: it.category.rawValue, icon: it.category.icon, tint: it.category.accentColor, amount: it.amount,
                            focus: .variable(it.category))
        }
        return make(list, title: MacChartText.pieTitle(prefix: "變動支出", period: period), unitLine: nil,
                    tint: MacChartTheme.variable.tint)
    }

    static func fixed(_ items: [(group: MacFixedGroupKey, amount: Double)], period: TimePeriod) -> MacChartPieData {
        let list: [MacChartPieItem] = items.map { it in
            MacChartPieItem(id: it.group.title, icon: it.group.macIcon, tint: it.group.macTint, amount: it.amount,
                            focus: .fixed(it.group))
        }
        return make(list, title: MacChartText.pieTitle(prefix: "固定支出", period: period),
                    unitLine: "換算成" + MacChartText.fixedUnit(period), tint: MacChartTheme.fixed.tint)
    }

    static func make(_ list: [MacChartPieItem], title: String, unitLine: String?, tint: Color) -> MacChartPieData {
        let total: Double = list.reduce(0) { s, it in s + it.amount }
        let slices: [MacChartSlice] = list.map { it in MacChartSlice(id: it.id, amount: it.amount, color: it.tint) }
        var legend: [MacChartLegendRow] = []
        for it in list.prefix(6) {
            let pct: Double = total > 0 ? it.amount / total : 0
            legend.append(MacChartLegendRow(id: it.id, icon: it.icon, tint: it.tint, name: it.id,
                                            amountText: MacText.short(it.amount), percentText: MacChartText.percent(pct),
                                            fraction: min(max(pct, 0), 1), focus: it.focus))
        }
        return MacChartPieData(slices: slices, legend: legend, more: max(list.count - 6, 0), center: MacText.short(total),
                               detail: "\(list.count) 類", title: title, unitLine: unitLine, tint: tint)
    }
}

// MARK: - 選取守門（一個 key、一個 .onChange）

struct MacChartGuardKey: Equatable {
    let selection: MacEntryRef?
    let period: TimePeriod
    let pie: MacChartPieKind
    let focus: MacChartFocus?
    /// 選到的那筆支出還在 money.expenses 裡（沒選＝true）
    let alive: Bool

    @MainActor
    static func isAlive(_ sel: MacEntryRef?, money: MacMoneyStore) -> Bool {
        guard let s = sel, s.isExpense else { return true }
        return money.expenses.contains { e in e.id == s.uuid }
    }
}

struct MacChartSelectionGuard: ViewModifier {
    /// 這次畫出來的選取、期間、圓餅種類、focus、那筆在不在（onChange 拿到新舊兩份）
    let key: MacChartGuardKey
    @ObservedObject var ui: MacUIState

    func body(content: Content) -> some View {
        content
            .onChange(of: key) { old, new in
                adjudicate(old: old, new: new)
            }
    }

    // sim5: guard5#1 只在三種情況清選取：① 選到收入 ② 那筆已不在 money.expenses ③ 換了期間、圓餅種類或 focus。
    // 不做「不在目前表裡就清」（看門狗〔看一下〕在圖表頁直接選、存完自動選取留著）
    private func adjudicate(old: MacChartGuardKey, new: MacChartGuardKey) {
        guard let sel = new.selection else { return }
        let changed = old.period != new.period || old.pie != new.pie || old.focus != new.focus
        if !sel.isExpense || !new.alive || changed {
            ui.selection = nil
        }
    }
}

// MARK: - 整頁版面（不用捲動容器：Table 不能放進去）

struct MacChartLayout: View {
    let screen: MacChartScreen
    @Binding var period: TimePeriod
    @Binding var pie: MacChartPieKind
    @Binding var focus: MacChartFocus?
    @Binding var picked: String?
    @Binding var sortOrder: [MacChartSort]
    @ObservedObject var ui: MacUIState
    let edit: MacEditCenter
    let money: MacMoneyStore

    var body: some View {
        VStack(spacing: 0) {
            MacChartTop(screen: screen, period: $period, pie: $pie, focus: $focus, picked: $picked)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            Divider()
            MacChartTableView(rows: screen.rows, sortOrder: $sortOrder, ui: ui, edit: edit, money: money)
        }
    }
}

/// 看板（高 128）→ 圖卡列（高 230）→ 比例＋分帳一行 → 明細表頭
struct MacChartTop: View {
    let screen: MacChartScreen
    @Binding var period: TimePeriod
    @Binding var pie: MacChartPieKind
    @Binding var focus: MacChartFocus?
    @Binding var picked: String?

    var body: some View {
        VStack(spacing: 12) {
            MacChartStarBoard(screen: screen, period: $period)
                .frame(height: 128)
                .macAppear(0)
            MacChartCardRow(screen: screen, pie: $pie, focus: $focus, picked: $picked)
                .frame(height: 230)
            MacChartMixLine(mix: screen.mix, note: screen.splitNote)
            MacChartTableHead(screen: screen, focus: $focus)
        }
    }
}

// MARK: - 夜空看板（整塊深色調色盤；淺色模式也是夜空，L5）

struct MacChartStarBoard: View {
    let screen: MacChartScreen
    @Binding var period: TimePeriod

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MacTheme.boardCorner, style: .continuous)
        HStack(alignment: .top, spacing: 12) {
            MacChartBoardText(screen: screen)
                .frame(minWidth: 280, maxHeight: .infinity, alignment: .topLeading)
            MacChartBoardSky(values: screen.skyValues, period: $period)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(MacSky.fill, in: shape)
        .shadow(color: Color.black.opacity(0.40), radius: 12, x: 0, y: 5)
        .environment(\.colorScheme, .dark)
    }
}

/// 左欄：期間、支出總計、大字、一句話、最多那期（金色，有才出現）
struct MacChartBoardText: View {
    let screen: MacChartScreen

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(screen.boardTitle, systemImage: screen.chipIcon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(MacSky.ink.inkDate)
            MacHeroLabel(text: "支出總計")
            MacHeroNumber(text: MacText.short(screen.numbers.total), value: screen.numbers.total)
            Text(screen.line)
                .font(.callout.weight(.semibold))
                .foregroundStyle(MacSky.ink.inkDate)
                .lineLimit(1)
            MacChartBoardMax(text: screen.maxText)
        }
    }
}

struct MacChartBoardMax: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text)
                .font(.caption.weight(.heavy))
                .foregroundStyle(MacSky.gold)
                .lineLimit(1)
        }
    }
}

/// 右欄：星座（只畫不收滑鼠）＋右上期間切換＋右下手寫招呼
struct MacChartBoardSky: View {
    let values: [Double]
    @Binding var period: TimePeriod

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MacChartSkyView(values: values)
                .equatable()
            VStack(alignment: .trailing, spacing: 0) {
                MacChartPeriodPicker(period: $period)
                Spacer(minLength: 0)
                MacGreeting(text: "Starry trends")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MacChartPeriodPicker: View {
    @Binding var period: TimePeriod

    var body: some View {
        Picker("", selection: $period) {
            ForEach(TimePeriod.allCases, id: \.self) { p in
                Text(p.rawValue).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 200)
    }
}

// MARK: - 圖卡列：趨勢卡（寬撐滿 ≥ 320）＋圓餅卡（寬 320）；沒資料換一張空白提示

struct MacChartCardRow: View {
    let screen: MacChartScreen
    @Binding var pie: MacChartPieKind
    @Binding var focus: MacChartFocus?
    @Binding var picked: String?

    var body: some View {
        if screen.hasData {
            HStack(alignment: .top, spacing: 12) {
                MacChartTrendCard(screen: screen, picked: $picked)
                    .macAppear(1)
                MacChartPieCard(data: screen.pie, pie: $pie, focus: $focus)
                    .frame(width: 320)
                    .macAppear(2)
            }
        } else {
            MacChartEmptyCard()
                .macAppear(1)
        }
    }
}

struct MacChartEmptyCard: View {
    var body: some View {
        MacEmptyHint(icon: "chart.bar", tint: MacChartTheme.trend.tint, title: "這段期間還沒有支出",
                     detail: "記下支出之後，這裡每一期會亮一顆星")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .macCard()
    }
}

struct MacChartTrendCard: View {
    let screen: MacChartScreen
    @Binding var picked: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MacSectionHeader(title: screen.periodTitle, icon: "chart.bar.fill", tint: MacChartTheme.trend.tint,
                             count: screen.pointCount)
            MacChartTrend(bars: screen.bars, visible: screen.visible, picked: $picked, title: screen.periodTitle,
                          count: screen.pointCount)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .macCard()
    }
}

struct MacChartPieCard: View {
    let data: MacChartPieData
    @Binding var pie: MacChartPieKind
    @Binding var focus: MacChartFocus?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MacChartPieHead(data: data, pie: $pie)
            HStack(alignment: .top, spacing: 10) {
                MacChartPieArea(data: data)
                MacChartLegend(data: data, focus: $focus)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .macCard()
    }
}

/// 一行〔變動｜固定〕＋色條＋副標；固定多一行「換算成每一天」
struct MacChartPieHead: View {
    let data: MacChartPieData
    @Binding var pie: MacChartPieKind

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                MacChartPieKindPicker(pie: $pie)
                Capsule()
                    .fill(data.tint)
                    .frame(width: 4, height: 14)
                Text(data.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            MacChartPieUnit(text: data.unitLine)
        }
    }
}

struct MacChartPieKindPicker: View {
    @Binding var pie: MacChartPieKind

    var body: some View {
        Picker("", selection: $pie) {
            ForEach(MacChartPieKind.allCases, id: \.self) { k in
                Text(k.rawValue).tag(k)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 104)
    }
}

struct MacChartPieUnit: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// 甜甜圈 132×132；這段期間沒有這一種＝照 iPhone 的「尚無資料」
struct MacChartPieArea: View {
    let data: MacChartPieData

    var body: some View {
        if data.slices.isEmpty {
            VStack(spacing: 4) {
                Text("尚無資料")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("新增支出後將顯示圖表")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 132, height: 132)
        } else {
            MacChartPie(slices: data.slices, center: data.center, detail: data.detail)
        }
    }
}

/// 圖例前 6 列（點一列＝明細換那一類）；第 7 類起「還有 N 個分類」
struct MacChartLegend: View {
    let data: MacChartPieData
    @Binding var focus: MacChartFocus?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(data.legend) { row in
                MacChartLegendButton(row: row, selected: focus == row.focus, focus: $focus)
            }
            MacChartLegendMore(count: data.more)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct MacChartLegendButton: View {
    let row: MacChartLegendRow
    let selected: Bool
    @Binding var focus: MacChartFocus?

    var body: some View {
        Button {
            focus = row.focus
        } label: {
            MacChartLegendLabel(row: row, selected: selected)
        }
        .buttonStyle(.plain)
        .help(row.name + " " + row.amountText + "（" + row.percentText + "）")
    }
}

struct MacChartLegendLabel: View {
    let row: MacChartLegendRow
    let selected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        let fill: Color = selected ? row.tint.opacity(0.08) : Color.clear
        HStack(spacing: 6) {
            MacIconBadge(icon: row.icon, top: row.tint, bottom: row.tint.opacity(0.7), size: 20, solid: false)
            MacChartLegendLines(row: row, selected: selected)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(fill, in: shape)
        .contentShape(shape)
    }
}

/// 第一行名稱＋金額＋百分比；第二行比例條（寬 60）
struct MacChartLegendLines: View {
    let row: MacChartLegendRow
    let selected: Bool

    var body: some View {
        let font: Font = selected ? Font.caption.weight(.semibold) : Font.caption
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(row.name)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(row.amountText)
                    .monospacedDigit()
                    .lineLimit(1)
                Text(row.percentText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(font)
            MacMeterBar(fraction: row.fraction, tint: row.tint)
                .frame(width: 60)
        }
    }
}

struct MacChartLegendMore: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text("還有 \(count) 個分類")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.leading, 4)
        }
    }
}

// MARK: - 本月比例＋分帳一行

struct MacChartMixLine: View {
    let mix: MacChartMix
    let note: String?

    var body: some View {
        HStack(spacing: 10) {
            Text("本月")
                .font(.callout.weight(.semibold))
            MacChartMixBody(mix: mix)
            Spacer(minLength: 8)
            MacChartSplitNote(note: note)
        }
        .frame(height: 28)
    }
}

struct MacChartMixBody: View {
    let mix: MacChartMix

    var body: some View {
        if mix.total > 0 {
            HStack(spacing: 8) {
                MacChartMixBar(variableWidth: mix.variableWidth, fixedWidth: mix.fixedWidth)
                Text(mix.text)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("這個月還沒有支出")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct MacChartMixBar: View {
    let variableWidth: CGFloat
    let fixedWidth: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            MacChartMixSegment(width: variableWidth, color: MacChartTheme.mixVariable)
            MacChartMixSegment(width: fixedWidth, color: MacChartTheme.mixFixed)
        }
        .frame(width: 260, alignment: .leading)
    }
}

struct MacChartMixSegment: View {
    let width: CGFloat
    let color: Color

    var body: some View {
        if width > 0 {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
                .frame(width: width, height: 8)
        }
    }
}

struct MacChartSplitNote: View {
    let note: String?

    var body: some View {
        if let note {
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - 明細表頭：那一期（或那一類）＋筆數＋合計＋〔換一期 ▾〕〔回到最近一期〕

struct MacChartTableHead: View {
    let screen: MacChartScreen
    @Binding var focus: MacChartFocus?

    var body: some View {
        HStack(spacing: 10) {
            MacSectionHeader(title: screen.focusTitle, icon: "list.bullet", tint: MacChartTheme.trend.tint,
                             count: screen.rowCountText)
                .fixedSize(horizontal: true, vertical: false)
            Text(screen.rowsTotalText)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            MacChartPeriodMenu(labels: screen.labelsNewFirst, focus: $focus)
            MacChartLatestButton(show: !screen.isLatest, focus: $focus)
        }
    }
}

/// 〔換一期 ▾〕：列全部 label 新到舊（chartXSelection 手勢不順時的保底，鍵盤也能用）
struct MacChartPeriodMenu: View {
    let labels: [String]
    @Binding var focus: MacChartFocus?

    var body: some View {
        Menu("換一期") {
            ForEach(labels, id: \.self) { l in
                Button(l) { focus = .period(l) }
            }
        }
        .fixedSize()
    }
}

struct MacChartLatestButton: View {
    let show: Bool
    @Binding var focus: MacChartFocus?

    var body: some View {
        if show {
            Button("回到最近一期") { focus = nil }
        }
    }
}

// MARK: - 5 欄表格（照 MacIncomeTableView：每欄一支 private func、回傳型別寫死；內容閉包只放一個 Cell）

struct MacChartTableView: View {
    let rows: [MacChartRow]
    @Binding var sortOrder: [MacChartSort]
    @ObservedObject var ui: MacUIState
    let edit: MacEditCenter
    let money: MacMoneyStore

    var body: some View {
        Table(rows, selection: $ui.selection, sortOrder: $sortOrder) {
            dateColumn()
            titleColumn()
            categoryColumn()
            kindColumn()
            amountColumn()
        }
        .modifier(MacChartTableActions(ui: ui, edit: edit, money: money))
        .overlay {
            MacChartTableEmpty(show: rows.isEmpty)
        }
    }

    private func dateColumn() -> TableColumn<MacChartRow, MacChartSort, MacChartDateCell, Text> {
        TableColumn(Text("日期"), value: \MacChartRow.sortDate) { row in
            MacChartDateCell(row: row)
        }
        .width(min: 84, ideal: 104, max: 140)
    }

    private func titleColumn() -> TableColumn<MacChartRow, MacChartSort, MacChartTitleCell, Text> {
        TableColumn(Text("項目"), value: \MacChartRow.title) { row in
            MacChartTitleCell(row: row)
        }
        .width(min: 100, ideal: 200, max: 360)
    }

    private func categoryColumn() -> TableColumn<MacChartRow, MacChartSort, MacChartCategoryCell, Text> {
        TableColumn(Text("分類"), value: \MacChartRow.category) { row in
            MacChartCategoryCell(row: row)
        }
        .width(min: 60, ideal: 110, max: 200)
    }

    private func kindColumn() -> TableColumn<MacChartRow, MacChartSort, MacChartKindCell, Text> {
        TableColumn(Text("類型"), value: \MacChartRow.kindText) { row in
            MacChartKindCell(row: row)
        }
        .width(min: 48, ideal: 150, max: 220)
    }

    private func amountColumn() -> TableColumn<MacChartRow, MacChartSort, MacChartAmountCell, Text> {
        TableColumn(Text("金額"), value: \MacChartRow.amount) { row in
            MacChartAmountCell(row: row)
        }
        .width(min: 80, ideal: 110, max: 160)
    }
}

// MARK: - Cell（每格一個小 View；字在建列時就算好）

struct MacChartDateCell: View {
    let row: MacChartRow

    var body: some View {
        Text(row.dateText)
            .monospacedDigit()
            .lineLimit(1)
    }
}

struct MacChartTitleCell: View {
    let row: MacChartRow

    var body: some View {
        Text(row.title)
            .lineLimit(1)
    }
}

struct MacChartCategoryCell: View {
    let row: MacChartRow

    var body: some View {
        Text(row.category)
            .lineLimit(1)
    }
}

struct MacChartKindCell: View {
    let row: MacChartRow

    var body: some View {
        Text(row.kindText)
            .lineLimit(1)
            .foregroundStyle(row.isFixed ? Color.secondary : Color.primary)
    }
}

struct MacChartAmountCell: View {
    let row: MacChartRow

    var body: some View {
        Text(row.amountText)
            .monospacedDigit()
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// 這一期（這一類）沒有帳
struct MacChartTableEmpty: View {
    let show: Bool

    var body: some View {
        if show {
            Text("這一段沒有帳")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 表格的右鍵、連按兩下、⌫、Return／Space（照 MacFixedTableActions）

struct MacChartTableActions: ViewModifier {
    @ObservedObject var ui: MacUIState
    let edit: MacEditCenter
    let money: MacMoneyStore

    func body(content: Content) -> some View {
        content
            .contextMenu(forSelectionType: MacEntryRef.self) { refs in
                MacChartMenu(refs: refs, edit: edit, money: money)
            } primaryAction: { refs in
                if let r = refs.first { edit.requestEdit(r) }
            }
            .onDeleteCommand {
                if let r = ui.selection, !ui.searchFieldFocused { edit.requestDelete(r) }
            }
            .onKeyPress(.return) {
                ui.showInspector = true
                return .handled
            }
            .onKeyPress(.space) {
                ui.showInspector = true
                return .handled
            }
    }
}

/// 右鍵選單：固定支出〔編輯〕〔停止扣款…〕〔刪除…〕；變動〔編輯〕〔複製成新的一筆〕〔刪除…〕（反灰一律照 MacEditCenter）
struct MacChartMenu: View {
    let refs: Set<MacEntryRef>
    let edit: MacEditCenter
    let money: MacMoneyStore

    var body: some View {
        if let r = refs.first {
            Button("編輯") { edit.requestEdit(r) }
                .disabled(!edit.canEdit(r))
            if isFixed(r) {
                Button("停止扣款…") { edit.requestStop(r) }
                    .disabled(!edit.canStop(r))
            } else {
                Button("複製成新的一筆") { edit.requestDuplicate(r) }
                    .disabled(!edit.canDuplicate(r))
            }
            Button("刪除…", role: .destructive) { edit.requestDelete(r) }
                .disabled(!edit.canDelete(r))
        }
    }

    private func isFixed(_ r: MacEntryRef) -> Bool {
        let e: Expense? = money.expenses.first(where: { x in x.id == r.uuid })
        return e?.expenseType == .fixed
    }
}
