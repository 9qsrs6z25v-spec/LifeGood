// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.648 mac7 G3] 記帳小鎮第三批：年度星路（judge_mac.md §U5-3、§U5-5）。只算不寫：road 是純函式，翻到哪一年只在記憶體。
//
// • 規則只用 Foundation 型別；月界一律 MacGameRules.calendar（台北、洛杉磯各跑；sim 編號 game#55～#64）。
// • 沒有金額、名字；不比較（不寫「比去年」）；以前沒開始的月份寫「還沒開始記帳」（灰），以後的月份是空框。
// • 主控骨架（C0）：型別、簽名、字（extension MacGameText）定案（§U7-6）；road 回 12 個 .future、popover EmptyView()。G3 換內容。

import SwiftUI

/// 星路要的量（MacGameModel.recompute 填；只在記憶體）
struct MacGameYearInput: Equatable {
    /// 結算月（舊到新；最多往回 120 個）
    let months: [MacGameMonth]
    let current: MacGameMonth?
    /// 開始記帳那天
    let start: Date?
    /// 記帳週（週一 00:00）
    let weeks: Set<Date>
    /// 點亮的徽章 id → 點亮時間（timeIntervalSinceReferenceDate；0＝第一次打開補上的）
    let earned: [String: Double]

    static let empty = MacGameYearInput(months: [], current: nil, start: nil, weeks: [], earned: [:])
}

enum MacGameYearNodeKind: Equatable {
    case settled, current, future, notStarted
}

/// 星路上的一個月
struct MacGameYearNode: Identifiable, Equatable {
    /// 1～12
    let month: Int
    /// 那年那月 1 號 00:00
    let start: Date
    let kind: MacGameYearNodeKind
    /// settled、current 才有
    let stars: MacGameMonth?
    /// 那個月點亮的徽章數（t > 0 的才算）
    let badges: Int

    var id: Int { month }
}

/// 一年的星路
struct MacGameYearRoad: Equatable {
    let year: Int
    let title: String
    let nodes: [MacGameYearNode]
    let starsTotal: Int
    let weeks: Int
    let canBack: Bool
    let canForward: Bool
    let footer: String
}

enum MacGameYearRules {
    // sim7: game#55（年界：hi＝now 的年、lo＝start 的年（沒有＝hi）；不會比 hi 大）
    static func bounds(start: Date?, now: Date, calendar: Calendar) -> (lo: Int, hi: Int) {
        let hi = calendar.component(.year, from: now)
        guard let s = start else { return (hi, hi) }
        return (min(calendar.component(.year, from: s), hi), hi)
    }

    // sim7: game#55（翻年夾在 [lo, hi]：不翻到未來、不翻到開始記帳以前）
    static func step(_ year: Int, by n: Int, start: Date?, now: Date, calendar: Calendar) -> Int {
        let b = bounds(start: start, now: now, calendar: calendar)
        return min(max(year + n, b.lo), b.hi)
    }

    // sim7: game#56～#60（純函式：只讀 input，不寫任何東西）
    // sim7: game#62（月界一律用呼叫端給的 calendar（＝MacGameRules.calendar，跟著這台 Mac 的時區）；年、月用整數比，不比 Date）
    static func road(year: Int, input: MacGameYearInput, now: Date, calendar: Calendar) -> MacGameYearRoad {
        let cal = calendar
        let cur = MacGameYearRules.yearMonth(now, calendar: cal)
        let first: (y: Int, m: Int)? = input.start.map { s in MacGameYearRules.yearMonth(s, calendar: cal) }
        var nodes: [MacGameYearNode] = []
        var stars = 0
        for m in 1...12 {
            let start = cal.date(from: DateComponents(year: year, month: m, day: 1)) ?? now
            let end = cal.date(byAdding: .month, value: 1, to: start) ?? start
            // sim7: game#56（以後＝future；這個月＝current（星＝input.current）；開始記帳那個月以前＝notStarted；
            //               其餘找結算月（找不到＝往回超過 120 個月＝notStarted））
            let kind: MacGameYearNodeKind
            var got: MacGameMonth? = nil
            if year > cur.y || (year == cur.y && m > cur.m) {
                kind = .future
            } else if year == cur.y && m == cur.m {
                kind = .current
                got = input.current
            } else if let f = first, !(year < f.y || (year == f.y && m < f.m)),
                      let hit = input.months.first(where: { x in MacGameYearRules.isMonth(x.start, year: year, month: m, calendar: cal) }) {
                kind = .settled
                got = hit
                // sim7: game#57（那年結算月的星數合計；本月不算）
                stars += hit.settledStars
            } else {
                kind = .notStarted
            }
            // sim7: game#59（那個月點亮的徽章：t > 0 而且 那月 1 號 ≤ 點亮時間 < 下月 1 號；t＝0 是第一次打開補上的，不畫）
            var badges = 0
            for t in input.earned.values where t > 0 {
                let d = Date(timeIntervalSinceReferenceDate: t)
                if start <= d && d < end {
                    badges += 1
                }
            }
            nodes.append(MacGameYearNode(month: m, start: start, kind: kind, stars: got, badges: badges))
        }
        // sim7: game#58（記帳週：週一落在那一年的才算（跨年那週算週一那年））
        let weeks = input.weeks.filter { w in cal.component(.year, from: w) == year }.count
        let b = bounds(start: input.start, now: now, calendar: cal)
        return MacGameYearRoad(year: year, title: MacGameText.yearTitle(year), nodes: nodes, starsTotal: stars, weeks: weeks,
                               canBack: year > b.lo, canForward: year < b.hi,
                               footer: MacGameText.yearFooter(year: year, stars: stars, weeks: weeks, isThisYear: year == b.hi))
    }

    /// 那天的（年, 月）
    private static func yearMonth(_ d: Date, calendar: Calendar) -> (y: Int, m: Int) {
        (calendar.component(.year, from: d), calendar.component(.month, from: d))
    }

    /// 是不是那年那月
    private static func isMonth(_ d: Date, year: Int, month: Int, calendar: Calendar) -> Bool {
        calendar.component(.year, from: d) == year && calendar.component(.month, from: d) == month
    }
}

/// 年度星路 popover（寬 520；遊戲列〔☆〕開）
// sim7: game#61（只畫：星路由 MacGameModel.openYear／stepYear／recompute 算好（yearRoad）；裡面的 Button 只有〔‹〕〔›〕；不放 ScrollView）
struct MacGameYearPopover: View {
    @EnvironmentObject private var game: MacGameModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let road = game.yearRoad {
                MacGameYearHeader(road: road, onStep: { n in game.stepYear(n) })
                MacGameYearGrid(nodes: road.nodes)
                Divider()
                MacGameYearFooter(text: road.footer)
            }
        }
        .padding(16)
        .frame(width: 520)
    }
}

/// 〔‹〕「2026 年的星路」〔›〕（不能翻到未來、不能翻到開始記帳那年以前）
private struct MacGameYearHeader: View {
    let road: MacGameYearRoad
    let onStep: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                onStep(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(!road.canBack)
            Spacer(minLength: 4)
            Text(road.title)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                onStep(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .disabled(!road.canForward)
        }
    }
}

/// 兩排各 6 個月（1～6 月、7～12 月）；節點之間墊一條路
private struct MacGameYearGrid: View {
    let nodes: [MacGameYearNode]

    private func row(_ r: Int) -> [MacGameYearNode] {
        Array(nodes.dropFirst(r * 6).prefix(6))
    }

    var body: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 12) {
            ForEach(0..<2, id: \.self) { r in
                GridRow {
                    ForEach(row(r)) { node in
                        MacGameYearNodeView(node: node)
                    }
                }
            }
        }
    }
}

/// 一個月：圓（月份）＋三顆小星或一句灰字＋點亮的徽章
private struct MacGameYearNodeView: View {
    let node: MacGameYearNode
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = MacPalette(scheme)
        VStack(spacing: 4) {
            ZStack {
                // 路：每排第一個月只畫右半、最後一個月只畫左半（兩端藏在圓底下）
                MacGameYearPath(left: node.month % 6 != 1, right: node.month % 6 != 0, track: p.track)
                MacGameYearDot(node: node, p: p)
            }
            .frame(height: 44)
            MacGameYearNodeDetail(node: node)
        }
        .frame(width: 80, height: 104, alignment: .top)
    }
}

/// 6pt 的路（左半、右半各自畫或不畫）
private struct MacGameYearPath: View {
    let left: Bool
    let right: Bool
    let track: Color

    var body: some View {
        HStack(spacing: 0) {
            left ? track : Color.clear
            right ? track : Color.clear
        }
        .frame(height: 6)
    }
}

/// 44pt 的圓：結算月＝白底細框（三顆星＝金框）、這個月＝虛線框、以後與開始以前＝灰細框
// sim7: game#63（三顆星的月份金框；沒有收入的月份 ★2、★3 是灰橫線（MacGameYearStar））
private struct MacGameYearDot: View {
    let node: MacGameYearNode
    let p: MacPalette

    private var isGold: Bool {
        node.kind == .settled && (node.stars?.settledStars ?? 0) == 3
    }

    private var ink: Color {
        node.kind == .settled || node.kind == .current ? p.ink : p.label
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(p.cellFill)
            ring
            Text(MacGameText.monthLabel(node.start, calendar: MacGameRules.calendar))
                .font(.caption.weight(.semibold))
                .foregroundStyle(ink)
                .lineLimit(1)
        }
        .frame(width: 44, height: 44)
    }

    @ViewBuilder
    private var ring: some View {
        switch node.kind {
        case .settled:
            Circle()
                .stroke(isGold ? MacGameTint.gold.top : p.cellStroke, lineWidth: isGold ? 1.5 : 0.75)
        case .current:
            Circle()
                .stroke(MacGameTint.dimStroke, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        case .future, .notStarted:
            Circle()
                .stroke(MacGameTint.dimStroke, lineWidth: 0.75)
        }
    }
}

/// 圓下面：結算月、這個月＝三顆小星；這個月、以後、開始以前＝一句灰字；有點亮徽章＝小徽章（×N）
private struct MacGameYearNodeDetail: View {
    let node: MacGameYearNode

    private var note: String? {
        switch node.kind {
        case .settled: return nil
        case .current: return MacGameText.pending
        case .future: return MacGameText.yearLater
        case .notStarted: return MacGameText.yearBefore
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            if let m = node.stars {
                HStack(spacing: 2) {
                    MacGameYearStar(star: m.record, help: MacGameText.starHelp(m, which: 0))
                    MacGameYearStar(star: m.hold, help: MacGameText.starHelp(m, which: 1))
                    MacGameYearStar(star: m.save, help: MacGameText.starHelp(m, which: 2))
                }
            }
            if let t = note {
                Text(t)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            if node.badges > 0 {
                MacGameYearBadge(count: node.badges)
            }
        }
    }
}

/// 一顆小星：拿到＝實心金星；還沒／月底結算＝灰空心；不算＝灰橫線（同 MGV 的對照，那邊是 private）
private struct MacGameYearStar: View {
    let star: MacGameStar
    let help: String
    @Environment(\.colorScheme) private var scheme

    private var icon: String {
        switch star {
        case .got: return "star.fill"
        case .notYet, .pending: return "star"
        case .notCounted: return "minus"
        }
    }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(star == .got ? MacGameTint(scheme).star : MacGameTint.dimIcon)
            .frame(width: 12, height: 12)
            .help(help)
    }
}

/// 那個月點亮的徽章：一枚小徽章，2 枚以上旁邊寫 ×N
private struct MacGameYearBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "rosette")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MacGameTint.medal.top)
            if count > 1 {
                Text("×" + String(count))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 底部：今年拿到 N 顆星・有記帳 N 週＋說明
private struct MacGameYearFooter: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.caption.weight(.semibold))
            Text(MacGameText.yearNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 字（§U5-5；沒有金額、名字、比較）
// sim7: game#64（字照 §S4-0＋keycheck 遊戲禁字表；沒有比較字）

extension MacGameText {
    static let yearHelp = "年度星路"
    static let yearEmpty = "這一年還沒有記帳"
    static let yearBefore = "還沒開始記帳"
    static let yearLater = "還沒到"
    static let yearNote = "照每筆帳的日期即時算，補記以前的也算；這個月要到月底才結算。"
    static let townHelp = "小鎮照等級蓋；這週有記帳的日子會亮一扇窗，沒花錢的日子種一棵樹"

    // sim7: game#60
    static func yearTitle(_ year: Int) -> String {
        "\(year) 年的星路"
    }

    // sim7: game#60（星數、週數都 0＝「這一年還沒有記帳」；不是今年寫「2025 年拿到…」）
    static func yearFooter(year: Int, stars: Int, weeks: Int, isThisYear: Bool) -> String {
        if stars == 0 && weeks == 0 {
            return yearEmpty
        }
        return (isThisYear ? "今年" : "\(year) 年") + "拿到 \(stars) 顆星・有記帳 \(weeks) 週"
    }
}
