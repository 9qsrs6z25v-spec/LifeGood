// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.648 mac7 G2] 總覽看板、這個月的錢橫條、未來 7 天要扣、分類卡（judge_mac.md §U3-3、§U3-5、§U3-6）。
//
// • 只畫：數字與字一律由 MacOverviewBoard.swift 算好（MacOverviewBoardText）；body 不寫 store、不寫 UserDefaults、不寫 log。
// • edit 只准 requestEdit（未來 7 天要扣點一筆）；ui 只准寫 page、variableMonth、variableCategoryRequest（分類卡跳頁、四格切頁）。
// • MacMoneyBar 照抄 OverviewBoard.swift:422-503（d070244）MoneySplitBar：全 LifeGoodMac 第二個 Canvas，不畫字（不准 ctx.resolve(、ctx.draw(）。
// • 修飾器鏈 ≤ 8（超過拆小 struct）；不准 AnyView、LazyVGrid、GeometryReader、withAnimation、.transition(、.macAppear(。
// • 主控骨架（C0）：五個 View 的名字與參數定案（§U7-6）。G2 填內容；另加 MacOverviewCategoryHeader（MOP 的 Section 標頭）與 fileprivate 小 struct。

import SwiftUI

// MARK: - 語氣 → 色

fileprivate extension MacOverviewTone {
    /// MacOverviewTone（Foundation 那邊算好）對到 MacTone 同名 case
    var macTone: MacTone {
        switch self {
        case .good: return .good
        case .warn: return .warn
        case .bad: return .bad
        case .neutral: return .neutral
        }
    }
}

// MARK: - §U3-3 總覽看板

/// §U3-3 總覽看板（.macBoard(.green)）— sim7: ov7#9 ov7#10 ov7#11 ov7#12
struct MacOverviewHeroBoard: View {
    let data: MacOverviewBoardData

    var body: some View {
        let head = MacOverviewBoardText.header(data)
        VStack(alignment: .leading, spacing: 12) {
            MacOverviewHeroTop(data: data, head: head)
            HStack(alignment: .top, spacing: 16) {
                MacOverviewHeroLead(data: data, head: head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                MacOverviewMoneyCell(data: data)
                    .frame(minWidth: 360, idealWidth: 400, maxWidth: 440)
            }
            MacOverviewTileRow(tiles: MacOverviewBoardText.tiles(data))
        }
        .macBoard(.green)
        .padding(.vertical, 6)
    }
}

/// 第一行：日期（callout semibold、inkDate）＋已花膠囊（有收入才有）……右上手寫招呼
fileprivate struct MacOverviewHeroTop: View {
    let data: MacOverviewBoardData
    let head: MacOverviewHead
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = MacPalette(scheme)
        HStack(alignment: .center, spacing: 10) {
            Text(head.date)
                .font(.callout.weight(.semibold))
                .foregroundStyle(p.inkDate)
                .lineLimit(1)
            if let share = MacOverviewBoardText.spentShare(data) {
                MacPill(icon: "chart.pie.fill", label: "已花", value: share, tone: .neutral)
            }
            Spacer(minLength: 8)
            MacGreeting(text: head.greeting)
        }
    }
}

/// 左欄：小標、大字、結論句（照 OB:266-267 寫法：Text 裡插 Text）
fileprivate struct MacOverviewHeroLead: View {
    let data: MacOverviewBoardData
    let head: MacOverviewHead
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = MacPalette(scheme)
        let v = MacOverviewBoardText.verdict(data)
        let color: Color = v.tone == .neutral ? p.ink : v.tone.macTone.color(p)
        VStack(alignment: .leading, spacing: 6) {
            MacHeroLabel(text: head.label)
            MacOverviewBigNumber(text: head.big, value: data.hasBase ? data.left : data.spending, tone: head.bigTone)
            Text("\(v.lead) \(Text(v.amount).fontWeight(.heavy).foregroundStyle(color))")
                .font(.callout)
                .foregroundStyle(p.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 右欄：這個月的錢（標題＋右邊收入字、橫條、圖例）
fileprivate struct MacOverviewMoneyCell: View {
    let data: MacOverviewBoardData
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = MacPalette(scheme)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("這個月的錢")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(p.ink)
                Spacer(minLength: 6)
                Text(MacOverviewBoardText.moneyTrailing(data))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(p.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            MacMoneyBar(fixed: data.fixed, variable: data.variable,
                        projected: data.daily.isEmpty ? data.spending : data.projectedSpending,
                        income: data.hasBase ? data.base : nil, dark: p.dark)
                .equatable()
                .frame(height: 18)
                .accessibilityHidden(true)
            MacOverviewLegend(legend: MacOverviewBoardText.legend(data), dark: p.dark)
        }
        .macCard()
        .accessibilityElement(children: .combine)
    }
}

/// 圖例：放得下排一列，放不下換兩列（照 OB:332-343）
fileprivate struct MacOverviewLegend: View {
    let legend: (fixed: String, variable: String, month: String, over: Bool)
    let dark: Bool

    var body: some View {
        let p = MacPalette(dark ? .dark : .light)
        let monthInk: Color = legend.over ? MacTone.warn.color(p) : MacMoneyBar.variableInk(dark: dark)
        let fixed = MacOverviewLegendItem(dash: false, color: MacMoneyBar.fixedInk(dark: dark), text: legend.fixed)
        let variable = MacOverviewLegendItem(dash: false, color: MacMoneyBar.variableInk(dark: dark), text: legend.variable)
        let month = MacOverviewLegendItem(dash: true, color: monthInk, text: legend.month)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                fixed
                variable
                month
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    fixed
                    variable
                }
                month
            }
        }
    }
}

/// 圖例一格：色塊（或虛線）＋字（照 MoneyBoardKit.swift:209-239）
fileprivate struct MacOverviewLegendItem: View {
    let dash: Bool
    let color: Color
    let text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 5) {
            if dash {
                Path { path in
                    path.move(to: CGPoint(x: 1, y: 1))
                    path.addLine(to: CGPoint(x: 11, y: 1))
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 3]))
                .frame(width: 12, height: 2)
            } else {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(MacPalette(scheme).label)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// 下排四格（Grid 一列 4 個）
fileprivate struct MacOverviewTileRow: View {
    let tiles: [MacOverviewTileText]

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                ForEach(tiles) { t in
                    MacOverviewTile(tile: t)
                }
            }
        }
    }
}

/// 一格：target 有值整張是按鈕（切頁；ui 只寫 page）
fileprivate struct MacOverviewTile: View {
    let tile: MacOverviewTileText
    @EnvironmentObject private var ui: MacUIState

    var body: some View {
        if let t = tile.target {
            Button {
                ui.page = t
            } label: {
                MacOverviewTileFace(tile: tile)
            }
            .buttonStyle(.plain)
            .help("切到" + t.title + "頁")
        } else {
            MacOverviewTileFace(tile: tile)
        }
    }
}

/// 一格的樣子：白卡＋24pt 實心圖示圓＋小標＋22pt 數字＋小字（accent 照 accentTone 上色）
fileprivate struct MacOverviewTileFace: View {
    let tile: MacOverviewTileText
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = MacPalette(scheme)
        let theme = Self.theme(tile.icon)
        let valueInk: Color = tile.valueTone.map { $0.macTone.color(p) } ?? p.ink
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                MacIconBadge(icon: tile.icon, top: theme.top, bottom: theme.bottom, size: 24, solid: true)
                Text(tile.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(p.label)
                    .lineLimit(1)
            }
            MacStatNumber(text: tile.value)
                .foregroundStyle(valueInk)
            detailText(p)
                .font(.caption)
                .foregroundStyle(p.label)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .macCard()
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
    }

    /// 主題：收入綠、支出 MacChartTheme.variable（對到 iPhone .pink）、每天還能花藍、今天橘
    private static func theme(_ icon: String) -> MacPageTheme {
        switch icon {
        case "banknote.fill": return MacPageTheme.green
        case "cart.fill": return MacChartTheme.variable
        case "wallet.pass.fill": return MacPageTheme.blue
        default: return MacPageTheme.orange
        }
    }

    /// 照 MoneyBoardKit.swift:130-135 detailText：detail＋空一格＋accent（上色）
    private func detailText(_ p: MacPalette) -> Text {
        let base = tile.detail ?? ""
        guard let accent = tile.accent else { return Text(base.isEmpty ? " " : base) }
        let colored = Text(accent).fontWeight(.semibold).foregroundStyle(tile.accentTone.macTone.color(p))
        return base.isEmpty ? colored : Text("\(base) \(colored)")
    }

    /// 照 MoneyBoardKit.swift:123-128 a11y
    private var a11y: String {
        var s = tile.label + "，" + tile.value
        if let detail = tile.detail { s += "，" + detail }
        if let accent = tile.accent { s += " " + accent }
        return s
    }
}

/// 「本月還能花」大字（＝MacHeroNumber 同字型；tone 有值時 MacTone 色、沒有時 ink）
struct MacOverviewBigNumber: View {
    let text: String
    let value: Double
    let tone: MacOverviewTone?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let p = MacPalette(scheme)
        let ink: Color = tone.map { $0.macTone.color(p) } ?? p.ink
        Text(text)
            .font(.system(size: 36, weight: .heavy, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(ink)
            .contentTransition(.numericText())
            .transaction { t in
                if reduceMotion { t.animation = nil }
            }
            .animation(.snappy, value: value)
    }
}

// 照抄 OverviewBoard.swift:422-503（d070244）MoneySplitBar（Color(tb:) → MacTheme.hex）— sim7: ov7#11
/// 這個月的錢：固定（紫）＋變動（藍）＋照平常的花法到月底還會花的那一段（斜線），收入是一道刻度
/// 刻度以後的斜線換成橘色（照這樣花，月底會超出收入的那一段）。看得到、不給讀：金額寫在下面的圖例裡（Canvas 不畫字）。
struct MacMoneyBar: View, Equatable {
    let fixed: Double
    let variable: Double
    /// 月底預估的總支出（已經花的也算在裡面）
    let projected: Double
    let income: Double?
    let dark: Bool

    static func fixedInk(dark: Bool) -> Color { dark ? MacTheme.hex(0xA98BFF) : MacTheme.hex(0x8B5CF6) }
    static func variableInk(dark: Bool) -> Color { dark ? MacTheme.hex(0x5B9BFF) : MacTheme.hex(0x2F6FE0) }

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let barH: CGFloat = 10
            let y = (size.height - barH) / 2
            let spent = fixed + variable
            let scale = max(income ?? 0, projected, spent, 1)
            func x(_ v: Double) -> CGFloat { CGFloat(max(0, v) / scale) * w }

            let bar = Path(roundedRect: CGRect(x: 0, y: y, width: w, height: barH), cornerRadius: barH / 2)
            ctx.fill(bar, with: .color(dark ? Color.white.opacity(0.10) : MacTheme.hex(0xE3ECF8)))
            var g = ctx
            g.clip(to: bar)

            let fixedEnd = x(fixed)
            if fixed > 0 {
                g.fill(Path(CGRect(x: 0, y: y, width: fixedEnd, height: barH)),
                       with: .linearGradient(Gradient(colors: dark
                                                          ? [MacTheme.hex(0x8B5CF6), MacTheme.hex(0xA98BFF)]
                                                          : [MacTheme.hex(0xB38BFF), MacTheme.hex(0x8B5CF6)]),
                                             startPoint: CGPoint(x: 0, y: y),
                                             endPoint: CGPoint(x: max(fixedEnd, 1), y: y)))
            }
            let spentEnd = x(spent)
            if variable > 0 {
                g.fill(Path(CGRect(x: fixedEnd, y: y, width: spentEnd - fixedEnd, height: barH)),
                       with: .linearGradient(Gradient(colors: dark
                                                          ? [MacTheme.hex(0x3D86FF), MacTheme.hex(0x5B9BFF)]
                                                          : [MacTheme.hex(0x5B9BFF), MacTheme.hex(0x2459D6)]),
                                             startPoint: CGPoint(x: fixedEnd, y: y),
                                             endPoint: CGPoint(x: max(spentEnd, fixedEnd + 1), y: y)))
            }
            // 照平常的花法，到月底還會花的那一段：斜線（超過收入的那一截換成橘色）
            if projected > spent {
                let end = x(projected)
                let cut = income.map { min(max(x($0), spentEnd), end) } ?? end
                hatch(&g, from: spentEnd, to: cut, y: y, h: barH, color: Self.variableInk(dark: dark))
                if cut < end {
                    hatch(&g, from: cut, to: end, y: y, h: barH,
                          color: dark ? MacTheme.hex(0xFFC14D) : MacTheme.hex(0xE07800))
                }
            }
            // 收入的刻度
            if let income, income > 0 {
                let ix = min(w - 1, max(1, x(income)))
                ctx.fill(Path(roundedRect: CGRect(x: ix - 1, y: 0, width: 2, height: size.height), cornerRadius: 1),
                         with: .color(dark ? MacTheme.hex(0xF3F6FF) : MacTheme.hex(0x0B1B45)))
            }
        }
    }

    private func hatch(_ ctx: inout GraphicsContext, from x0: CGFloat, to x1: CGFloat,
                       y: CGFloat, h: CGFloat, color: Color) {
        guard x1 - x0 > 0.5 else { return }
        let rect = CGRect(x: x0, y: y, width: x1 - x0, height: h)
        var g = ctx
        g.clip(to: Path(rect))
        g.fill(Path(rect), with: .color(color.opacity(0.14)))
        var stripes = Path()
        var sx = x0 - h
        while sx < x1 {
            stripes.move(to: CGPoint(x: sx, y: y + h))
            stripes.addLine(to: CGPoint(x: sx + h, y: y))
            sx += 4
        }
        g.stroke(stripes, with: .color(color.opacity(0.6)), lineWidth: 1.2)
    }
}

// MARK: - §U3-5 未來 7 天要扣

/// §U3-5 未來 7 天要扣（.macBoard(.blue)；bills 空的不畫，照 OV:95-99）— sim7: ov7#13
/// 預設 3 列；多的〔還有 N 筆〕／〔收起〕（照 OB:554-566 的字；不包 withAnimation）。點一筆＝edit.requestEdit（這卡不寫任何東西）。
struct MacOverviewUpcomingCard: View {
    let bills: [MacOverviewBill]
    @State private var showAll = false

    private static let shownByDefault = 3

    var body: some View {
        let shown = showAll ? bills : Array(bills.prefix(Self.shownByDefault))
        if !bills.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                MacSectionHeader(title: "未來 7 天要扣", icon: "calendar.badge.clock", tint: MacPageTheme.blue.top,
                                 count: MacOverviewBoardText.upcomingCount(bills))
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, bill in
                        if i > 0 {
                            Divider()
                                .padding(.leading, 38)
                        }
                        MacOverviewBillButton(bill: bill)
                    }
                    if bills.count > Self.shownByDefault {
                        Divider()
                        MacOverviewMoreButton(text: showAll ? "收起" : "還有 \(bills.count - Self.shownByDefault) 筆") {
                            showAll.toggle()
                        }
                    }
                }
                .macCard()
            }
            .macBoard(.blue)
        }
    }
}

/// 〔還有 N 筆〕〔收起〕
fileprivate struct MacOverviewMoreButton: View {
    let text: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MacPalette(scheme).hint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 一筆：點了開同一張固定支出表單（policy／gate／postCheck 照舊；edit 只准 requestEdit）— sim7: ov7#13
fileprivate struct MacOverviewBillButton: View {
    let bill: MacOverviewBill
    @EnvironmentObject private var edit: MacEditCenter

    var body: some View {
        Button {
            edit.requestEdit(.expense(bill.id))
        } label: {
            MacOverviewBillRow(bill: bill)
        }
        .buttonStyle(.plain)
        .help("編輯這筆固定支出")
    }
}

/// 一列：28pt 淡紫圖示圓＋名稱（一行）＋哪天扣（快到了 warn）＋金額
fileprivate struct MacOverviewBillRow: View {
    let bill: MacOverviewBill
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = MacPalette(scheme)
        let purple = MacRailTint(scheme).station
        let when = MacOverviewBoardText.when(bill)
        let amount = MacText.short(bill.amount)
        HStack(spacing: 10) {
            MacIconBadge(icon: bill.icon, top: purple, bottom: purple, size: 28, solid: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(bill.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(p.ink)
                    .lineLimit(1)
                Text(when)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MacOverviewBoardText.soon(bill) ? MacTone.warn.color(p) : p.label)
            }
            Spacer(minLength: 8)
            Text(amount)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(p.ink)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bill.title + "，" + when + "，" + amount)
    }
}

// MARK: - §U3-6 本月花在哪裡

/// MOP 那段 Section 的標頭：「本月花在哪裡」＋「6 類・NT$2.2萬」（OV:217-218）— sim7: ov7#16
struct MacOverviewCategoryHeader: View {
    let stats: [MacOverviewCategoryStat]

    var body: some View {
        MacSectionHeader(title: "本月花在哪裡", icon: "chart.pie.fill", tint: MacPageTheme.orange.top,
                         count: MacOverviewBoardText.categoryCount(stats))
    }
}

/// §U3-6 本月花在哪裡的分類卡（3 欄 Grid；點一張跳變動支出只看那一類）— sim7: ov7#4 ov7#16 ov7#17
struct MacOverviewCategoryCards: View {
    let stats: [MacOverviewCategoryStat]

    /// 每一列第一張的 index（3 欄；同 MacGameViews.swift MacGameMonthGrid 的 pairs 寫法）
    private var rows: [Int] { Array(stride(from: 0, to: stats.count, by: 3)) }

    var body: some View {
        let total: Double = stats.reduce(0) { $0 + $1.amount }
        VStack(alignment: .leading, spacing: 0) {
            if stats.isEmpty {
                MacEmptyHint(icon: "chart.bar.xaxis", tint: MacPageTheme.orange.top, title: "尚無分類紀錄",
                             detail: "新增變動支出後顯示分類統計")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    ForEach(rows, id: \.self) { i in
                        GridRow {
                            MacOverviewCategoryCard(stat: stats[i], total: total)
                            if i + 1 < stats.count {
                                MacOverviewCategoryCard(stat: stats[i + 1], total: total)
                            }
                            if i + 2 < stats.count {
                                MacOverviewCategoryCard(stat: stats[i + 2], total: total)
                            }
                        }
                    }
                }
            }
        }
        .macBoard(.orange)
        .padding(.vertical, 6)
    }
}

/// 一張分類卡＝按鈕：跳到變動支出頁、本月、只看這一類（ui 只寫 variableMonth、variableCategoryRequest、page）
fileprivate struct MacOverviewCategoryCard: View {
    let stat: MacOverviewCategoryStat
    let total: Double
    @EnvironmentObject private var ui: MacUIState

    var body: some View {
        Button {
            jump(stat.category)
        } label: {
            MacOverviewCategoryFace(stat: stat, total: total)
        }
        .buttonStyle(.plain)
        .help("切到變動支出，只看這一類")
    }

    /// sim7: ov7#17 順序固定：page 的 didSet 會清選取、清搜全部月份，不清 request（變動支出頁 onAppear 讀到就清）
    private func jump(_ c: VariableCategory) {
        ui.variableMonth = nil
        ui.variableCategoryRequest = c
        ui.page = .variable
    }
}

/// 一張的樣子：白卡＋28pt 淡色分類圖示圓＋名稱＋金額＋「40%・32 筆」＋比上月同期（不用紅）＋比例條
fileprivate struct MacOverviewCategoryFace: View {
    let stat: MacOverviewCategoryStat
    let total: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = MacPalette(scheme)
        let c = stat.category
        let share: Double = total > 0 ? stat.amount / total : 0
        let line = MacOverviewBoardText.categoryShare(stat, total: total)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                MacIconBadge(icon: c.icon, top: c.accentColor, bottom: c.accentColor.opacity(0.7), size: 28, solid: false)
                Text(c.rawValue)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(p.ink)
                    .lineLimit(1)
            }
            MacStatNumber(text: MacText.short(stat.amount))
                .foregroundStyle(p.ink)
            Text(line)
                .font(.caption)
                .foregroundStyle(p.label)
                .lineLimit(1)
            MacOverviewCategoryChange(stat: stat)
            MacMeterBar(fraction: share, tint: c.accentColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .macCard()
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(c.rawValue + "，" + MacText.short(stat.amount) + "，" + line)
    }
}

/// 「比上月同期 ↑8%」（lastMonth > 0 才有；色照 spendingTone：warn 橘、good 綠、neutral label；沒有就留一行空白，卡片一樣高）
fileprivate struct MacOverviewCategoryChange: View {
    let stat: MacOverviewCategoryStat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = MacPalette(scheme)
        let tone = MacOverviewBoardText.spendingTone(stat.amount, vs: stat.lastMonth)
        let ink: Color = tone == .neutral ? p.label : tone.macTone.color(p)
        HStack(spacing: 4) {
            if let ch = MacOverviewBoardText.categoryChange(stat) {
                Text("比上月同期")
                    .foregroundStyle(p.label)
                Text(ch)
                    .fontWeight(.semibold)
                    .foregroundStyle(ink)
            } else {
                Text(" ")
            }
        }
        .font(.caption2)
        .lineLimit(1)
    }
}
