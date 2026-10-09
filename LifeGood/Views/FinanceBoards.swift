import SwiftUI
import Charts

// MARK: - 理財六頁的看板（v25.527）
//
// 頭部跟收支看板同一套（MoneyBoardHeader：天空、雲、月牙、手寫問候、一幅資料畫的風景），
// 外框是 MoneyBoardCard。數字的算法在 FinanceInsights.swift，風景的畫法在 FinanceBoardScenes.swift。
// 這個檔案是每一頁「要寫什麼字、畫什麼景」：
//   總覽：資產小鎮＋錢放在哪裡（四張明信片）＋每個月的現金流＋接下來 30 天
//   股票、儲蓄險、載具、房地產、圖表：在下面各自的段落

extension MoneyFormat {
    /// 風景裡的小牌子：不寫 NT$（「1880萬」）
    static func compact(_ v: Double) -> String {
        short(v).replacingOccurrences(of: "NT$", with: "")
    }
}

/// 看板內容裡的小標題（「錢放在哪裡」　　4 類・NT$2,520萬）
struct FinanceSectionTitle: View {
    let title: String
    var trailing: Text? = nil
    let pal: TripBoardPalette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(pal.ink)
            Spacer(minLength: 6)
            if let trailing {
                trailing
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(pal.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - 總覽

struct FinanceOverviewData: Equatable {
    var month = 1
    var snapshot = FinanceSnapshot()
    /// 上個月底的淨資產（有存的用存的，沒有就回推）；沒有任何資產是 nil
    var lastMonthNetWorth: Double? = nil
    var cashFlow = FinanceCashFlow()
    var upcoming: [FinanceUpcoming] = []
    var counts: [FinanceAssetKind: Int] = [:]
    /// 保單到期可以領回的（台幣）
    var savingsExpected: Double = 0
    /// 股票還持有的那些賺賠了幾成；沒有持股是 nil
    var stockUnrealizedRate: Double? = nil
    var vehicleMonthly: Double = 0

    var assetCount: Int { counts.values.reduce(0, +) }

    /// 放在 .task(id:) 裡跑（會掃全部的支出找貸款）
    static func build(finance f: FinanceStore, expense e: ExpenseStore, now: Date = Date()) -> FinanceOverviewData {
        let cal = Calendar.current
        let rates = FinanceRates(e)
        var d = FinanceOverviewData()
        d.month = cal.component(.month, from: now)
        d.snapshot = FinanceSnapshot.current(finance: f, expense: e, rates: rates, now: now)
        FinanceHistory.record(d.snapshot, now: now)
        if d.snapshot.assets > 0 || d.snapshot.debt > 0 {
            let two = FinanceHistory.series(months: 2, finance: f, expense: e, rates: rates, now: now)
            if two.count == 2, two[0].assets > 0 { d.lastMonthNetWorth = two[0].netWorth }
        }
        d.cashFlow = FinanceCashFlow.build(finance: f, rates: rates, now: now)
        d.upcoming = FinanceUpcoming.build(finance: f, expense: e, now: now)
        let activeStocks = f.stocks.filter { !$0.isSold }
        let livePolicies = f.insurances.filter { now < $0.maturityDate }
        d.counts = [.realEstate: f.realEstates.filter { !$0.isSold }.count,
                    .savings: livePolicies.count,
                    .stock: activeStocks.count,
                    .vehicle: f.vehicles.filter { !$0.isSold }.count]
        d.savingsExpected = livePolicies.reduce(0) { $0 + rates.ntd($1.calculatedExpectedReturn, code: $1.currencyCode) }
        let cost = activeStocks.reduce(0) { $0 + $1.totalCost }
        if cost > 0 {
            d.stockUnrealizedRate = (activeStocks.reduce(0) { $0 + $1.marketValue } - cost) / cost
        }
        d.vehicleMonthly = d.cashFlow.vehicle
        return d
    }
}

struct FinanceOverviewBoard: View {
    let data: FinanceOverviewData
    let open: (FinanceFeature) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let d = data
        let s = d.snapshot
        MoneyBoardCard(
            card: .financeOverview,
            header: MoneyBoardHeader(
                date: d.assetCount > 0 ? "\(d.month) 月・資產 \(d.assetCount) 項" : "\(d.month) 月",
                capsule: changeCapsule,
                capsuleIcon: "chart.line.uptrend.xyaxis",
                label: "淨資產",
                big: MoneyFormat.short(s.netWorth),
                bigTone: s.netWorth < 0 ? .bad : nil,
                line: line(pal),
                greeting: ["Keep", "growing!"],
                scene: .town(town),
                band: 118,
                seed: d.month * 37 + 11),
            content: AnyView(
                VStack(alignment: .leading, spacing: 14) {
                    allocation(pal)
                    cashFlowSection(pal)
                    if !d.upcoming.isEmpty {
                        upcomingSection(pal)
                    }
                }))
    }

    /// 「比上月 ↑1.8%」（上個月是負的也照「變了多少」算：−100 萬 → −50 萬是 ↑50%）
    private var changeCapsule: String? {
        guard let last = data.lastMonthNetWorth, abs(last) >= 1 else { return nil }
        let r = (data.snapshot.netWorth - last) / abs(last)
        if abs(r) < 0.01 { return "比上月 持平" }
        return "比上月 " + (r > 0 ? "↑" : "↓") + MoneyFormat.percent(abs(r))
    }

    private func line(_ pal: TripBoardPalette) -> Text {
        let s = data.snapshot
        if s.assets <= 0 && s.debt <= 0 {
            return Text("新增房地產、股票、保單或車子之後，這裡會蓋出你的資產小鎮")
        }
        let assets = "總資產 " + MoneyFormat.short(s.assets)
        if s.debt <= 0 {
            return Text("\(assets)・沒有貸款")
        }
        return Text("\(assets)・貸款還要繳 \(Text(MoneyFormat.short(s.debt)).fontWeight(.heavy).foregroundStyle(MoneyTone.bad.color(pal)))")
    }

    private var town: FinTownScene {
        let d = data
        let s = d.snapshot
        var b: [FinTownScene.Building] = []
        for kind in FinanceAssetKind.allCases where s.value(kind) > 0 {
            switch kind {
            case .realEstate:
                b.append(.init(kind: kind, value: s.realEstate, owed: s.mortgage, count: d.counts[kind] ?? 1,
                               label: MoneyFormat.compact(s.realEstate),
                               owedLabel: s.mortgage > 0 ? "房貸 " + MoneyFormat.compact(s.mortgage) : nil))
            case .stock:
                b.append(.init(kind: kind, value: s.stock, label: MoneyFormat.compact(s.stock),
                               rising: (d.stockUnrealizedRate ?? 0) >= 0))
            case .savings:
                b.append(.init(kind: kind, value: s.savings, label: MoneyFormat.compact(s.savings)))
            case .vehicle:
                b.append(.init(kind: kind, value: s.vehicle, owed: s.carLoan, label: MoneyFormat.compact(s.vehicle)))
            }
        }
        return FinTownScene(buildings: b.sorted { $0.value > $1.value })
    }

    // MARK: 錢放在哪裡

    @ViewBuilder
    private func allocation(_ pal: TripBoardPalette) -> some View {
        let d = data
        let s = d.snapshot
        let kinds = FinanceAssetKind.allCases.filter { s.value($0) > 0 }.sorted { s.value($0) > s.value($1) }
        VStack(alignment: .leading, spacing: 8) {
            FinanceSectionTitle(
                title: "錢放在哪裡",
                trailing: kinds.isEmpty ? nil : Text("\(kinds.count) 類・" + MoneyFormat.short(s.assets)),
                pal: pal)
            if kinds.isEmpty {
                Text("還沒有理財資產。右上角＋可以新增股票或房地產；儲蓄險、載具在各自的分頁新增。")
                    .font(.footnote)
                    .foregroundStyle(pal.label)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            } else {
                MoneyShareRibbon(segments: kinds.map { .init(theme: $0.theme, value: s.value($0)) })
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(kinds) { kind in
                        Button {
                            open(kind.feature)
                        } label: {
                            postcard(kind, pal: pal)
                        }
                        .buttonStyle(MoneyPressStyle())
                        .accessibilityHint("切到" + kind.name + "頁")
                    }
                }
            }
        }
    }

    private func postcard(_ kind: FinanceAssetKind, pal: TripBoardPalette) -> some View {
        let d = data
        let s = d.snapshot
        let value = s.value(kind)
        let footer: Text
        let footerA11y: String
        switch kind {
        case .realEstate:
            if s.mortgage > 0 {
                footer = Text("房貸還要繳 \(Text(MoneyFormat.compact(s.mortgage)).foregroundStyle(MoneyTone.bad.color(pal)))")
                footerA11y = "房貸還要繳 " + MoneyFormat.short(s.mortgage)
            } else {
                footer = Text("\(d.counts[kind] ?? 0) 筆・沒有房貸")
                footerA11y = "\(d.counts[kind] ?? 0) 筆，沒有房貸"
            }
        case .savings:
            footer = Text("到期可領 \(Text(MoneyFormat.compact(d.savingsExpected)).foregroundStyle(MoneyTone.good.color(pal)))")
            footerA11y = "到期可領 " + MoneyFormat.short(d.savingsExpected)
        case .stock:
            if let r = d.stockUnrealizedRate {
                let tone = MoneyTone.change(r)
                let text = (r >= 0 ? "+" : "") + MoneyFormat.percent(r)
                footer = Text("未實現 \(Text(text).foregroundStyle(tone.color(pal)))")
                footerA11y = "未實現 " + text
            } else {
                footer = Text("\(d.counts[kind] ?? 0) 檔")
                footerA11y = "\(d.counts[kind] ?? 0) 檔"
            }
        case .vehicle:
            footer = Text("每月養車 " + MoneyFormat.compact(d.vehicleMonthly))
            footerA11y = "每月養車 " + MoneyFormat.short(d.vehicleMonthly)
        }
        return MoneyCategoryPostcard(theme: kind.theme, name: kind.name, amount: MoneyFormat.short(value),
                                     share: s.assets > 0 ? value / s.assets : 0, count: d.counts[kind] ?? 0,
                                     change: nil, changeTone: .neutral,
                                     customFooter: footer, customFooterA11y: footerA11y)
    }

    // MARK: 每個月的現金流

    private func cashFlowSection(_ pal: TripBoardPalette) -> some View {
        let c = data.cashFlow
        let trailing: Text? = c.isEmpty ? nil
            : Text("\(c.net >= 0 ? "淨流入" : "淨流出") \(Text(MoneyFormat.short(abs(c.net))).fontWeight(.heavy).foregroundStyle((c.net >= 0 ? MoneyTone.good : MoneyTone.bad).color(pal)))")
        let green = MoneyTone.good.color(pal)
        let inSegs: [(Double, Color, String)] = [(c.rent, green, "租金"), (c.dividends, green.opacity(0.55), "股利")]
        let outSegs: [(Double, Color, String)] = [(c.mortgage, MoneyArtTheme.finHome.midColor, "房貸"),
                                                  (c.premiums, MoneyArtTheme.finSavings.midColor, "保費"),
                                                  (c.vehicle, MoneyArtTheme.finDrive.midColor, "養車")]
        let scale = max(c.inflow, c.outflow, 1)
        return VStack(alignment: .leading, spacing: 8) {
            FinanceSectionTitle(title: "每個月的現金流", trailing: trailing, pal: pal)
            VStack(alignment: .leading, spacing: 8) {
                if c.isEmpty {
                    Text("有租金、股利、房貸、保費或養車的紀錄之後，這裡會算出理財每個月進出多少。")
                        .font(.footnote)
                        .foregroundStyle(pal.label)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    FinanceFlowRow(label: "進來", segments: inSegs, scale: scale, total: c.inflow,
                                   totalColor: MoneyTone.good.color(pal), pal: pal)
                    FinanceFlowRow(label: "出去", segments: outSegs, scale: scale, total: c.outflow,
                                   totalColor: MoneyTone.bad.color(pal), pal: pal)
                    ChipFlowLayout(spacing: 10) {
                        ForEach(Array((inSegs + outSegs).enumerated()), id: \.offset) { _, seg in
                            if seg.0 > 0 {
                                MoneyLegendItem(mark: .swatch, color: seg.1,
                                                text: seg.2 + " " + MoneyFormat.compact(seg.0), pal: pal)
                            }
                        }
                    }
                    Text("股利、養車的變動支出用近 12 個月的平均；保費換成每月。")
                        .font(.caption2)
                        .foregroundStyle(pal.label.opacity(0.85))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .modifier(TripBoardCellChrome(pal: pal))
        }
    }

    // MARK: 接下來 30 天

    private static let dueFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d"
        return f
    }()

    private func upcomingSection(_ pal: TripBoardPalette) -> some View {
        let list = Array(data.upcoming.prefix(6))
        return VStack(alignment: .leading, spacing: 8) {
            FinanceSectionTitle(title: "接下來 30 天", trailing: Text("\(data.upcoming.count) 件"), pal: pal)
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, ev in
                    if i > 0 {
                        Rectangle()
                            .fill(pal.label.opacity(0.15))
                            .frame(height: 0.5)
                            .padding(.leading, 38)
                    }
                    Button {
                        switch ev.kind {
                        case .premium, .maturity: open(.insurance)
                        case .mortgage: open(.realEstate)
                        case .vehicle: open(.vehicle)
                        }
                    } label: {
                        upcomingRow(ev, pal: pal)
                    }
                    .buttonStyle(MoneyPressStyle())
                }
            }
            .padding(.horizontal, 12)
            .modifier(TripBoardCellChrome(pal: pal))
        }
    }

    private func upcomingRow(_ ev: FinanceUpcoming, pal: TripBoardPalette) -> some View {
        let when: String
        switch ev.daysAway {
        case 0: when = "今天"
        case 1: when = "明天"
        default: when = Self.dueFmt.string(from: ev.date) + "・\(ev.daysAway) 天後"
        }
        let line = [when, ev.detail].compactMap { $0 }.joined(separator: "・")
        let soon = ev.daysAway <= 1 && !ev.isIncome
        return HStack(spacing: 10) {
            TripBoardIconBadge(icon: ev.icon, colors: pal.badge(ev.tint), diameter: 28, dark: pal.dark)
            VStack(alignment: .leading, spacing: 1) {
                MarqueeText(ev.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(pal.ink)
                Text(line)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ev.isIncome ? MoneyTone.good.color(pal) : (soon ? MoneyTone.warn.color(pal) : pal.label))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(ev.amount)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(ev.isIncome ? MoneyTone.good.color(pal) : pal.ink)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ev.title + "，" + line + "，" + ev.amount)
    }
}

/// 現金流的一列：「進來　▇▇▇▇▇▇▇░░　3.4萬」
struct FinanceFlowRow: View {
    let label: String
    let segments: [(Double, Color, String)]
    let scale: Double
    let total: Double
    let totalColor: Color
    let pal: TripBoardPalette

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(pal.label)
                .frame(width: 30, alignment: .leading)
            GeometryReader { geo in
                HStack(spacing: 1.5) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                        if seg.0 > 0 {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(seg.1)
                                .frame(width: max(3, geo.size.width * CGFloat(seg.0 / max(scale, 1))))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 16)
            Text(MoneyFormat.compact(total))
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(totalColor)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label + " " + MoneyFormat.short(total) + "："
                            + segments.filter { $0.0 > 0 }.map { $0.2 + " " + MoneyFormat.short($0.0) }.joined(separator: "、"))
    }
}

// MARK: - 股票：熱氣球

struct StockBoardData: Equatable {
    var dateText = ""
    var activeCount = 0
    var soldCount = 0
    /// 持有中的市值、成本（台幣）
    var value: Double = 0
    var cost: Double = 0
    /// 今天漲跌（台幣）與幾成；不知道前一天收盤的那幾檔不算，全部都不知道是 nil
    var dayChange: Double? = nil
    var dayRate: Double? = nil
    /// 每一檔今天漲跌幾成（0.012＝漲 1.2%）：卡片的「今日」膠囊用（在這裡算一次，不在 body 裡讀快取）
    var dayRates: [UUID: Double] = [:]
    /// 已實現（賣掉的那些：賣出金額 − 成本），全部的股票、全部的時間
    var realized: Double = 0
    var dividendsThisYear: Double = 0
    var topLabel: String? = nil
    var topShare: Double = 0
    var balloons: [FinBalloonScene.Balloon] = []
    var month = 1

    var unrealized: Double { value - cost }

    /// 氣球、牌子上的名字：有代號寫代號，沒有寫名字
    static func label(_ s: Stock) -> String {
        s.symbol.isEmpty ? MoneyBoardText.short(s.name, max: 5) : s.symbol
    }

    static func build(stocks: [Stock], now: Date = Date()) -> StockBoardData {
        let cal = Calendar.current
        var d = StockBoardData()
        d.month = cal.component(.month, from: now)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_Hant_TW")
        fmt.dateFormat = "M/d"
        d.dateText = fmt.string(from: now)
        let active = stocks.filter { !$0.isSold && $0.shares > 0 }
        d.activeCount = active.count
        d.soldCount = stocks.filter(\.isSold).count
        d.value = active.reduce(0) { $0 + $1.marketValue }
        d.cost = active.reduce(0) { $0 + $1.totalCost }

        var change: Double = 0
        var base: Double = 0
        var known = false
        for s in active where s.currentPrice > 0 {
            guard let prev = s.moneyPreviousClose(now: now), prev > 0 else { continue }
            known = true
            change += s.shares * (s.currentPrice - prev) * s.currencyFactor
            base += s.shares * prev * s.currencyFactor
            d.dayRates[s.id] = s.currentPrice / prev - 1
        }
        if known {
            d.dayChange = change
            d.dayRate = base > 0 ? change / base : nil
        }
        d.realized = stocks.reduce(0) { $0 + $1.moneyRealizedProfit }
        let yearStart = cal.date(from: cal.dateComponents([.year], from: now)) ?? now
        d.dividendsThisYear = stocks.reduce(0) { $0 + $1.moneyCashDividends(from: yearStart, to: now) }
        if let top = active.max(by: { $0.marketValue < $1.marketValue }), d.value > 0 {
            d.topLabel = label(top)
            d.topShare = top.marketValue / d.value
        }

        // 氣球：市值最大的 7 檔，照清單的順序排；賺最多的那一顆掛牌子
        let biggest = Set(active.sorted { $0.marketValue > $1.marketValue }.prefix(7).map(\.id))
        let shown = active.filter { biggest.contains($0.id) }
        let best = shown.filter { $0.totalCost > 0 }.max { $0.returnRate < $1.returnRate }
        d.balloons = shown.map { s in
            var b = FinBalloonScene.Balloon(label: label(s), value: s.marketValue, returnRate: s.returnRate)
            if s.id == best?.id, s.returnRate >= 1, shown.count > 1 {
                b.callout = label(s) + " +" + "\(Int(s.returnRate.rounded()))%"
            }
            return b
        }
        return d
    }
}

struct StockBoard: View {
    let data: StockBoardData

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let d = data
        let dayTone = d.dayChange.map { MoneyTone.change($0, base: max(d.value, 1)) } ?? .neutral
        MoneyBoardCard(
            card: .stock,
            header: MoneyBoardHeader(
                date: d.activeCount > 0 ? "\(d.dateText)・持有 \(d.activeCount) 檔" : d.dateText,
                capsule: dayCapsule,
                capsuleIcon: dayTone == .down ? "chart.line.downtrend.xyaxis" : "chart.line.uptrend.xyaxis",
                capsuleTint: dayTone == .neutral ? nil : dayTone.color(pal),
                label: "股票市值",
                big: MoneyFormat.short(d.value),
                line: line(pal),
                greeting: ["Rise", "high!"],
                scene: .balloons(FinBalloonScene(balloons: d.balloons)),
                band: 118,
                seed: d.month * 41 + 7),
            content: chips.isEmpty ? nil : AnyView(MoneyBoardChips(chips: chips, pal: pal)))
    }

    /// 「今日 ▲1.2%」
    private var dayCapsule: String? {
        guard let r = data.dayRate else { return nil }
        if abs(r) < 0.0005 { return "今日 平盤" }
        return "今日 " + (r > 0 ? "▲" : "▼") + FinanceText.percent1(abs(r))
    }

    private func line(_ pal: TripBoardPalette) -> Text {
        let d = data
        guard d.activeCount > 0 else {
            return Text(d.soldCount > 0 ? "持有中的都賣掉了，賣掉的在最下面" : "新增股票之後，這裡會飛起一顆顆熱氣球")
        }
        guard d.cost > 0 else { return Text("成本沒有填，算不出賺賠") }
        let pl = d.unrealized
        let tone = MoneyTone.change(pl, base: d.cost)
        let amount = FinanceText.signed(pl)
        let rate = FinanceText.signedPercent(pl / d.cost)
        return Text("未實現 \(Text(amount + "（" + rate + "）").fontWeight(.heavy).foregroundStyle(tone.color(pal)))・成本 \(MoneyFormat.short(d.cost))")
    }

    private var chips: [MoneyBoardChip] {
        let d = data
        var out: [MoneyBoardChip] = []
        if let c = d.dayChange {
            out.append(MoneyBoardChip(icon: "sun.max.fill", label: "今日", value: FinanceText.signed(c),
                                      tone: MoneyTone.change(c, base: max(d.value, 1))))
        }
        if abs(d.realized) >= 1 {
            out.append(MoneyBoardChip(icon: "checkmark.seal.fill", label: "已實現", value: FinanceText.signed(d.realized),
                                      tone: MoneyTone.change(d.realized, base: max(d.cost, 1))))
        }
        if d.dividendsThisYear > 0 {
            out.append(MoneyBoardChip(icon: "gift.fill", label: "今年股利", value: MoneyFormat.short(d.dividendsThisYear)))
        }
        if let t = d.topLabel, d.activeCount > 1 {
            out.append(MoneyBoardChip(icon: "crown.fill", label: "最大持股",
                                      value: t + "・" + MoneyFormat.percent(d.topShare)))
        }
        return out
    }
}

/// 理財頁的數字寫法（帶正負號的金額、百分比）
enum FinanceText {
    /// 「+NT$41.2萬」「-NT$3,200」
    static func signed(_ v: Double) -> String {
        (v > 0 ? "+" : "") + v.ntdWanString
    }

    /// 「1.2%」（一位小數；10% 以上不寫小數）
    static func percent1(_ r: Double) -> String {
        let p = r * 100
        return abs(p) >= 10 ? "\(Int(p.rounded()))%" : String(format: "%.1f%%", p)
    }

    /// 「+21%」「-3.5%」
    static func signedPercent(_ r: Double) -> String {
        (r > 0 ? "+" : (r < 0 ? "-" : "")) + percent1(abs(r))
    }

    /// 原幣別的金額：台幣「NT$3.2萬」，外幣「美金 3,000」（跟多幣別帳戶同一套寫法）
    static func money(_ v: Double, code: String) -> String {
        FinanceRates.isNTD(code) ? v.ntdWanString : v.wanString(symbolPrefix: code)
    }
}

// MARK: - 儲蓄險：果園

struct SavingsBoardData: Equatable {
    var month = 1
    var liveCount = 0
    var maturedCount = 0
    /// 還沒滿期的保單（全部換成台幣）：今天的價值、已繳、到期可領、整張的保費總額
    var value: Double = 0
    var paid: Double = 0
    var expected: Double = 0
    var fullPremium: Double = 0
    /// 「美金 2 張」「外幣 3 張」
    var foreignLabel: String? = nil
    /// 「10/15 美金 3,000」
    var nextDue: String? = nil
    var allPaid = false
    /// 「2026/11・58.2萬」
    var soonestMaturity: String? = nil
    /// 保費加權的平均年利率（%）
    var avgRate: Double? = nil
    /// 外幣的匯率（「美金匯率 32.1」）；設定裡沒填的列在 missingRates
    var rateChips: [String] = []
    var missingRates: [String] = []
    var trees: [FinOrchardScene.Tree] = []

    var gainRate: Double? { fullPremium > 0 ? expected / fullPremium - 1 : nil }

    static func build(insurances: [SavingsInsurance], rates: FinanceRates, now: Date = Date()) -> SavingsBoardData {
        let cal = Calendar.current
        var d = SavingsBoardData()
        d.month = cal.component(.month, from: now)
        let live = insurances.filter { $0.moneyIsLive(now: now) }
        d.liveCount = live.count
        d.maturedCount = insurances.count - live.count
        for ins in live {
            let code = ins.currencyCode
            d.value += rates.ntd(ins.value(at: now), code: code)
            d.paid += rates.ntd(ins.premiumAmount * Double(ins.elapsedPeriods(at: now)), code: code)
            d.expected += rates.ntd(ins.calculatedExpectedReturn, code: code)
            d.fullPremium += rates.ntd(ins.moneyFullPremium, code: code)
        }

        let foreign = live.filter { !FinanceRates.isNTD($0.currencyCode) }
        let codes = Array(Set(foreign.map(\.currencyCode))).sorted()
        if codes.count == 1 {
            d.foreignLabel = "\(codes[0]) \(foreign.count) 張"
        } else if codes.count > 1 {
            d.foreignLabel = "外幣 \(foreign.count) 張"
        }
        for code in codes {
            if let r = rates.known(code) {
                d.rateChips.append(code + "匯率 " + FinanceItemText.number(r))
            } else {
                d.missingRates.append(code)
            }
        }

        let md = DateFormatter()
        md.locale = Locale(identifier: "zh_Hant_TW")
        md.dateFormat = "M/d"
        let ym = DateFormatter()
        ym.locale = Locale(identifier: "zh_Hant_TW")
        ym.dateFormat = "yyyy/M"
        let dues = live.compactMap { ins in ins.moneyNextDue(now: now).map { (ins, $0) } }
        if let next = dues.min(by: { $0.1 < $1.1 }) {
            d.nextDue = md.string(from: next.1) + " " + FinanceText.money(next.0.premiumAmount, code: next.0.currencyCode)
        } else {
            d.allPaid = !live.isEmpty
        }
        if let soon = live.min(by: { $0.maturityDate < $1.maturityDate }) {
            let amount = FinanceRates.isNTD(soon.currencyCode)
                ? MoneyFormat.compact(soon.calculatedExpectedReturn)
                : FinanceText.money(soon.calculatedExpectedReturn, code: soon.currencyCode)
            d.soonestMaturity = ym.string(from: soon.maturityDate) + "・" + amount
        }
        let weights = live.map { rates.ntd($0.annualPremium, code: $0.currencyCode) }
        let wSum = weights.reduce(0, +)
        if wSum > 0 {
            d.avgRate = zip(live, weights).reduce(0) { $0 + $1.0.annualRate * $1.1 } / wSum
        }

        // 樹：最快滿期的在左邊，最多 6 棵
        let year = DateFormatter()
        year.dateFormat = "yyyy"
        d.trees = live.sorted { $0.maturityDate < $1.maturityDate }.prefix(6).map { ins in
            let total = max(ins.totalPeriods, 1)
            return FinOrchardScene.Tree(progress: Double(ins.elapsedPeriods(at: now)) / Double(total),
                                        label: year.string(from: ins.maturityDate),
                                        gain: (ins.moneyGainRate ?? 0) * 100,
                                        foreign: !FinanceRates.isNTD(ins.currencyCode))
        }
        return d
    }
}

struct SavingsBoard: View {
    let data: SavingsBoardData

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let d = data
        var date = "\(d.liveCount) 張保單"
        if d.maturedCount > 0 { date += "・已滿期 \(d.maturedCount) 張" }
        return MoneyBoardCard(
            card: .savings,
            header: MoneyBoardHeader(
                date: date,
                dateIcon: "doc.text.fill",
                capsule: d.foreignLabel,
                capsuleIcon: "dollarsign.circle.fill",
                label: "保單現值",
                big: MoneyFormat.short(d.value),
                line: line(pal),
                greeting: ["Grow", "steady!"],
                scene: .orchard(FinOrchardScene(trees: d.trees)),
                band: 112,
                seed: d.month * 23 + 5),
            content: chips.isEmpty ? nil : AnyView(MoneyBoardChips(chips: chips, pal: pal)))
    }

    private func line(_ pal: TripBoardPalette) -> Text {
        let d = data
        guard d.liveCount > 0 else {
            return Text(d.maturedCount > 0 ? "保單都滿期了，錢已經領回來" : "新增保單之後，這裡會長出一片果園")
        }
        let expected = Text(MoneyFormat.short(d.expected)).fontWeight(.heavy).foregroundStyle(MoneyTone.good.color(pal))
        guard let g = d.gainRate, abs(g) >= 0.005 else {
            return Text("已繳 \(MoneyFormat.short(d.paid))・到期可領 \(expected)")
        }
        let more = g > 0 ? "多 " + FinanceText.percent1(g) : "少 " + FinanceText.percent1(abs(g))
        return Text("已繳 \(MoneyFormat.short(d.paid))・到期可領 \(expected)（\(more)）")
    }

    private var chips: [MoneyBoardChip] {
        let d = data
        var out: [MoneyBoardChip] = []
        if let n = d.nextDue {
            out.append(MoneyBoardChip(icon: "calendar", label: "下次繳費", value: n))
        } else if d.allPaid {
            out.append(MoneyBoardChip(icon: "checkmark.seal.fill", label: "", value: "保費都繳完了", tone: .good))
        }
        if let m = d.soonestMaturity {
            out.append(MoneyBoardChip(icon: "star.fill", label: "最快滿期", value: m))
        }
        if let r = d.avgRate, r > 0 {
            out.append(MoneyBoardChip(icon: "percent", label: "平均年利率", value: String(format: "%.2f%%", r)))
        }
        for c in d.rateChips {
            out.append(MoneyBoardChip(icon: "arrow.left.arrow.right", label: "", value: c))
        }
        for code in d.missingRates {
            out.append(MoneyBoardChip(icon: "exclamationmark.triangle.fill", label: "",
                                      value: code + "沒有設匯率（當 1 算）", tone: .warn))
        }
        return out
    }
}

// MARK: - 載具：今年這條路

/// 一台車要寫在卡片與看板上的幾個數字（掃記帳的支出算，放在 .task 裡算一次）
struct VehicleFacts: Equatable {
    /// 充電：平均每度、每公里（電車有填度數、里程才有）
    var perKwh: Double? = nil
    var perKm: Double? = nil
    /// 近 12 個月的平均每月油錢（油車）
    var fuelPerMonth: Double? = nil
    /// 每月養車：定期支出的月均＋近 12 個月的變動支出 ÷ 12
    var monthly: Double = 0
    /// 車貸繳到第幾期（連結的記帳固定支出有年期或總額才有）
    var loan: MoneyLoanSchedule? = nil
    /// 車貸還要繳（台幣）
    var loanLeft: Double = 0

    /// 充電紀錄（有度數的電費）
    static func chargeExpenses(_ v: Vehicle, expenses: [Expense]) -> [Expense] {
        expenses.filter { $0.linkedVehicleId == v.id && $0.vehicleExpenseCategory == .electricity && ($0.evKwh ?? 0) > 0 }
    }

    static func build(_ v: Vehicle, expense e: ExpenseStore, now: Date = Date()) -> VehicleFacts {
        let cal = Calendar.current
        let yearAgo = cal.date(byAdding: .year, value: -1, to: now) ?? now
        var f = VehicleFacts()
        let recent = v.variableExpenses.filter { $0.date >= yearAgo && $0.date <= now }
        f.monthly = v.monthlyFixedTotal + recent.reduce(0) { $0 + $1.amount } / 12
        if v.powerType == .gasoline || v.powerType == .motorcycle || v.powerType == .hybrid {
            let fuel = recent.filter { $0.category == .fuel }.reduce(0) { $0 + $1.amount }
            if fuel > 0 { f.fuelPerMonth = fuel / 12 }
        }
        if v.hasBattery {
            let a = VehicleChargeAnalytics(expenses: chargeExpenses(v, expenses: e.expenses),
                                           capacityKWh: v.batteryCapacityKWh, homeKeyword: v.homeChargePlace)
            f.perKwh = a.avgPricePerKwh
            f.perKm = a.avgCostPerKm
        }
        let byId = Dictionary(e.expenses.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for id in FinanceLoans.carLoanIds(v, expenses: e.expenses) {
            guard let ex = byId[id] else { continue }
            if f.loan == nil, let s = ex.moneyLoanSchedule(now: now, calendar: cal) { f.loan = s }
            if let left = FinanceLoans.remaining(ex, at: now, store: e, calendar: cal) { f.loanLeft += left }
        }
        return f
    }
}

struct VehicleBoardData: Equatable {
    var year = 2026
    var month = 1
    var activeCount = 0
    var soldCount = 0
    var value: Double = 0
    /// 有填買入價的那幾台：買入價合計、現在的估值合計（折舊只比這幾台）
    var purchase: Double = 0
    var pricedValue: Double = 0
    var monthly: Double = 0
    var yearSpent: Double = 0
    /// 全部同一種動力就寫那一種（「電車」）
    var powerLabel: String? = nil
    var powerIcon = "car.fill"
    /// 只有一台車：持有幾年（折舊那顆膠囊寫）
    var yearsOwned: Double? = nil
    var perKwh: Double? = nil
    var perKm: Double? = nil
    var loanLeft: Double = 0
    var scene = FinRoadScene(today: 0, marks: [], signs: [])

    var depreciationRate: Double? { purchase > 0 ? pricedValue / purchase - 1 : nil }

    static func build(vehicles: [Vehicle], facts: [UUID: VehicleFacts], expense e: ExpenseStore,
                      now: Date = Date()) -> VehicleBoardData {
        let cal = Calendar.current
        var d = VehicleBoardData()
        d.year = cal.component(.year, from: now)
        d.month = cal.component(.month, from: now)
        let active = vehicles.filter { !$0.isSold }
        d.activeCount = active.count
        d.soldCount = vehicles.count - active.count
        d.value = active.reduce(0) { $0 + $1.currentValue }
        let priced = active.filter { $0.purchasePrice > 0 }
        d.purchase = priced.reduce(0) { $0 + $1.purchasePrice }
        d.pricedValue = priced.reduce(0) { $0 + $1.currentValue }
        let types = Set(active.map(\.powerType))
        if types.count == 1, let t = types.first {
            d.powerLabel = t.rawValue
            d.powerIcon = t.icon
        }
        if active.count == 1 { d.yearsOwned = active[0].yearsOwned }

        guard let yearStart = cal.date(from: cal.dateComponents([.year], from: now)),
              let nextYear = cal.date(byAdding: .year, value: 1, to: yearStart) else { return d }
        let yearSpan = nextYear.timeIntervalSince(yearStart)
        func t(_ date: Date) -> Double { min(1, max(0, date.timeIntervalSince(yearStart) / yearSpan)) }

        var kwhCost: Double = 0
        var kwh: Double = 0
        var kmCost: Double = 0
        var km: Double = 0
        var monthTotals = [Double](repeating: 0, count: 12)
        var monthKinds = [[FinRoadScene.Kind: Double]](repeating: [:], count: 12)
        for v in active {
            d.monthly += facts[v.id]?.monthly ?? 0
            d.loanLeft += facts[v.id]?.loanLeft ?? 0
            // 今年已花：今年的變動支出＋定期支出的月均 × 今年持有的月數
            let from = max(yearStart, v.purchaseDate)
            let months = from > now ? 0 : (cal.dateComponents([.month], from: from, to: now).month ?? 0) + 1
            d.yearSpent += v.monthlyFixedTotal * Double(min(12, months))
            for ve in v.variableExpenses where ve.date >= yearStart && ve.date <= now {
                d.yearSpent += ve.amount
                let m = cal.component(.month, from: ve.date) - 1
                monthTotals[m] += ve.amount
                monthKinds[m][FinRoadScene.Kind.of(ve.category), default: 0] += ve.amount
            }
            if v.hasBattery {
                let a = VehicleChargeAnalytics(expenses: VehicleFacts.chargeExpenses(v, expenses: e.expenses),
                                               capacityKWh: v.batteryCapacityKWh, homeKeyword: v.homeChargePlace)
                kwhCost += a.totalCost
                kwh += a.totalKwh
                for iv in a.intervals {
                    kmCost += iv.cost
                    km += iv.km
                }
            }
        }
        if kwh > 0 { d.perKwh = kwhCost / kwh }
        if km > 0 { d.perKm = kmCost / km }

        var marks: [FinRoadScene.Mark] = []
        for m in 0..<12 where monthTotals[m] > 0 {
            let kind = monthKinds[m].max { $0.value < $1.value }?.key ?? .other
            marks.append(FinRoadScene.Mark(t: (Double(m) + 0.5) / 12, kind: kind, amount: monthTotals[m]))
        }

        // 路牌：連結了記帳固定支出的車貸、稅費、訂閱，今年接下來的那一次
        let byId = Dictionary(e.expenses.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let today = cal.startOfDay(for: now)
        let md = DateFormatter()
        md.locale = Locale(identifier: "zh_Hant_TW")
        md.dateFormat = "M/d"
        var upcoming: [(Date, String)] = []
        for v in active {
            for fe in v.fixedExpenses {
                guard let id = fe.linkedExpenseId, let ex = byId[id],
                      let due = ex.nextFixedDueDate(onOrAfter: today, calendar: cal), due < nextYear else { continue }
                let label = md.string(from: due) + " " + fe.category.rawValue
                if !upcoming.contains(where: { $0.1 == label }) { upcoming.append((due, label)) }
            }
        }
        let signs = upcoming.sorted { $0.0 < $1.0 }.prefix(3).map { FinRoadScene.Sign(t: t($0.0), label: $0.1) }
        d.scene = FinRoadScene(today: t(now), marks: marks, signs: Array(signs))
        return d
    }
}

extension FinRoadScene.Kind {
    static func of(_ c: VehicleVariableCategory) -> FinRoadScene.Kind {
        switch c {
        case .fuel: return .fuel
        case .electricity: return .charge
        case .maintenance, .repair, .wash: return .care
        case .parking: return .park
        case .other: return .other
        }
    }
}

struct VehicleBoard: View {
    let data: VehicleBoardData

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let d = data
        var date = "\(d.activeCount) 輛・\(String(d.year)) 年"
        if d.soldCount > 0 { date += "・已售出 \(d.soldCount)" }
        return MoneyBoardCard(
            card: .vehicle,
            header: MoneyBoardHeader(
                date: date,
                dateIcon: "car.fill",
                capsule: d.powerLabel,
                capsuleIcon: d.powerIcon,
                label: "車輛估值",
                big: MoneyFormat.short(d.value),
                line: line,
                greeting: ["Drive", "safe!"],
                scene: .road(d.scene),
                band: 112,
                seed: d.month * 31 + 9),
            content: chips.isEmpty ? nil : AnyView(MoneyBoardChips(chips: chips, pal: pal)))
    }

    private var line: Text {
        let d = data
        guard d.activeCount > 0 else {
            return Text(d.soldCount > 0 ? "車子都賣掉了，賣掉的還留在下面" : "新增車子之後，這裡會畫出你今年這條路")
        }
        var parts: [String] = []
        if d.monthly > 0 { parts.append("每月養車 " + MoneyFormat.short(d.monthly)) }
        if d.yearSpent > 0 { parts.append("今年已花 " + MoneyFormat.short(d.yearSpent)) }
        return Text(parts.isEmpty ? "還沒有養車的紀錄" : parts.joined(separator: "・"))
    }

    private var chips: [MoneyBoardChip] {
        let d = data
        var out: [MoneyBoardChip] = []
        if let p = d.perKwh {
            out.append(MoneyBoardChip(icon: "bolt.fill", label: "每度電", value: "NT$" + FinanceItemText.number(p, digits: 1)))
        }
        if let p = d.perKm {
            out.append(MoneyBoardChip(icon: "road.lanes", label: "每公里", value: "NT$" + FinanceItemText.number(p, digits: 1)))
        }
        if let r = d.depreciationRate, abs(r) >= 0.005 {
            var v = (r < 0 ? "-" : "+") + FinanceText.percent1(abs(r))
            if let y = d.yearsOwned, y >= 0.1 { v += "・" + FinanceItemText.number(y, digits: 1) + " 年" }
            out.append(MoneyBoardChip(icon: r < 0 ? "arrow.down.right" : "arrow.up.right",
                                      label: r < 0 ? "折舊" : "增值", value: v))
        }
        if d.loanLeft >= 1 {
            out.append(MoneyBoardChip(icon: "banknote.fill", label: "車貸還要繳", value: MoneyFormat.short(d.loanLeft)))
        }
        return out
    }
}

// MARK: - 房地產：街景

extension RealEstate {
    /// 房貸在 date 那天還要繳多少（每個貸款項目：剩下的期數 × 每期金額）
    func moneyMortgageLeft(at date: Date = Date()) -> Double {
        mortgageItems.reduce(0) { $0 + Double(FinanceLoans.mortgagePeriodsLeft($1, at: date)) * $1.amount }
    }

    /// 房貸最後一期在哪一年；沒有房貸是 nil
    var moneyMortgageEndYear: Int? {
        let cal = Calendar.current
        let ends = mortgageItems.compactMap { cal.date(byAdding: .month, value: max(0, $0.totalPeriods - 1), to: $0.startDate) }
        return ends.max().map { cal.component(.year, from: $0) }
    }
}

struct RealEstateBoardData: Equatable {
    var month = 1
    var activeCount = 0
    var soldCount = 0
    var value: Double = 0
    var owed: Double = 0
    var rentedCount = 0
    var monthlyRent: Double = 0
    var monthlyMortgage: Double = 0
    /// 有填買入價的那幾間：買入價合計、現在的估值合計
    var purchase: Double = 0
    var pricedValue: Double = 0
    var mortgageEndYear: Int? = nil
    var homes: [FinStreetScene.Home] = []

    var equity: Double { value - owed }
    var appreciationRate: Double? { purchase > 0 ? pricedValue / purchase - 1 : nil }

    static func build(estates: [RealEstate], now: Date = Date()) -> RealEstateBoardData {
        var d = RealEstateBoardData()
        d.month = Calendar.current.component(.month, from: now)
        let active = estates.filter { !$0.isSold }
        d.activeCount = active.count
        d.soldCount = estates.count - active.count
        d.value = active.reduce(0) { $0 + $1.currentValue }
        d.owed = active.reduce(0) { $0 + $1.moneyMortgageLeft(at: now) }
        d.rentedCount = active.filter { $0.monthlyRental > 0 }.count
        d.monthlyRent = active.reduce(0) { $0 + $1.monthlyRental }
        d.monthlyMortgage = active.reduce(0) { $0 + $1.monthlyMortgage }
        let priced = active.filter { $0.purchasePrice > 0 }
        d.purchase = priced.reduce(0) { $0 + $1.purchasePrice }
        d.pricedValue = priced.reduce(0) { $0 + $1.currentValue }
        d.mortgageEndYear = active.filter { $0.moneyMortgageLeft(at: now) > 0 }.compactMap(\.moneyMortgageEndYear).max()

        // 街景：最多 4 間，值最多的在前面
        d.homes = active.sorted { $0.currentValue > $1.currentValue }.prefix(4).map { re in
            let left = re.moneyMortgageLeft(at: now)
            let fraction = re.currentValue > 0 ? min(1, left / re.currentValue) : 0
            let tower = re.buildingType == .apartment
            let floors = tower ? 0 : (re.floors.isEmpty ? max(1, re.totalFloors) : re.floors.count)
            return FinStreetScene.Home(tower: tower, floors: floors,
                                       fromFloor: tower ? max(1, re.fromFloor) : 0,
                                       toFloor: tower ? max(1, re.fromFloor, re.toFloor) : 0,
                                       owedFraction: fraction,
                                       owedLabel: left > 0 ? "房貸 " + MoneyFormat.percent(fraction) : nil,
                                       rented: re.monthlyRental > 0, sold: false,
                                       label: MoneyBoardText.short(re.name.isEmpty ? re.city : re.name, max: 6))
        }
        return d
    }
}

struct RealEstateBoard: View {
    let data: RealEstateBoardData

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let d = data
        var date = "\(d.activeCount) 筆房產"
        if d.soldCount > 0 { date += "・已售出 \(d.soldCount)" }
        return MoneyBoardCard(
            card: .realEstate,
            header: MoneyBoardHeader(
                date: date,
                dateIcon: "house.fill",
                capsule: d.rentedCount > 0 ? "出租 \(d.rentedCount) 筆" : nil,
                capsuleIcon: "key.fill",
                label: "房產估值",
                big: MoneyFormat.short(d.value),
                line: line(pal),
                greeting: ["Home", "sweet home!"],
                scene: .street(FinStreetScene(homes: d.homes)),
                band: 118,
                seed: d.month * 19 + 13),
            content: chips(pal).isEmpty ? nil : AnyView(MoneyBoardChips(chips: chips(pal), pal: pal)))
    }

    private func line(_ pal: TripBoardPalette) -> Text {
        let d = data
        guard d.activeCount > 0 else {
            return Text(d.soldCount > 0 ? "房子都賣掉了，賣掉的還留在下面" : "新增房子之後，這裡會蓋出一條街")
        }
        guard d.owed > 0, d.value > 0 else { return Text("沒有房貸，全部都是你的") }
        let mine = Text(MoneyFormat.short(d.equity)).fontWeight(.heavy)
            .foregroundStyle((d.equity >= 0 ? MoneyTone.good : MoneyTone.bad).color(pal))
        return Text("扣掉貸款，真正是你的 \(mine)（\(MoneyFormat.percent(max(0, d.equity) / d.value))）")
    }

    private func chips(_ pal: TripBoardPalette) -> [MoneyBoardChip] {
        let d = data
        var out: [MoneyBoardChip] = []
        if d.monthlyRent > 0 {
            var v = MoneyFormat.short(d.monthlyRent)
            if d.value > 0 { v += "・報酬 " + FinanceText.percent1(d.monthlyRent * 12 / d.value) }
            out.append(MoneyBoardChip(icon: "tag.fill", label: "月租", value: v, tone: .good))
        }
        if d.monthlyMortgage > 0 {
            out.append(MoneyBoardChip(icon: "building.columns.fill", label: "月貸", value: MoneyFormat.short(d.monthlyMortgage)))
        }
        if let r = d.appreciationRate, abs(r) >= 0.005 {
            out.append(MoneyBoardChip(icon: r > 0 ? "arrow.up.right" : "arrow.down.right", label: r > 0 ? "增值" : "跌價",
                                      value: FinanceText.signedPercent(r), tone: MoneyTone.change(r)))
        }
        if let y = d.mortgageEndYear {
            out.append(MoneyBoardChip(icon: "flag.checkered", label: "房貸繳完", value: "\(String(y)) 年"))
        }
        return out
    }
}

// MARK: - 圖表：極光

enum FinanceChartPeriod: Int, CaseIterable, Identifiable {
    case year = 12
    case threeYears = 36
    case all = 0

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .year: return "近 1 年"
        case .threeYears: return "近 3 年"
        case .all: return "全部"
        }
    }
}

struct FinanceChartBoardData: Equatable {
    var period: FinanceChartPeriod = .year
    var points: [FinanceMonthPoint] = []
    var snapshot = FinanceSnapshot()

    var netWorth: Double { points.last?.netWorth ?? snapshot.netWorth }
    var firstNetWorth: Double? { points.count >= 2 ? points.first?.netWorth : nil }
    var hasEstimate: Bool { points.dropLast().contains { !$0.recorded } }

    static func build(finance f: FinanceStore, expense e: ExpenseStore, period: FinanceChartPeriod,
                      now: Date = Date()) -> FinanceChartBoardData {
        let cal = Calendar.current
        let rates = FinanceRates(e)
        var d = FinanceChartBoardData()
        d.period = period
        d.snapshot = FinanceSnapshot.current(finance: f, expense: e, rates: rates, now: now)
        FinanceHistory.record(d.snapshot, now: now)
        var months = period.rawValue
        if period == .all {
            let first = FinanceHistory.firstMonth(finance: f, now: now)
            months = (cal.dateComponents([.month], from: first, to: now).month ?? 0) + 1
        }
        months = min(120, max(2, months))
        let points = FinanceHistory.series(months: months, finance: f, expense: e, rates: rates, now: now)
        // 最前面那幾個月什麼都還沒有（資產、貸款都是 0）就不畫
        d.points = Array(points.drop { $0.assets <= 0 && $0.debt <= 0 })
        return d
    }

    /// 「一年前」「三年前」「2019/3」
    var startWord: String {
        guard let first = points.first else { return "" }
        switch period {
        case .year where points.count >= 12: return "一年前"
        case .threeYears where points.count >= 36: return "三年前"
        default:
            let f = DateFormatter()
            f.dateFormat = "yyyy/M"
            return f.string(from: first.month)
        }
    }

    var scene: FinAuroraScene {
        let values = points.map(\.netWorth)
        guard values.count >= 2 else { return FinAuroraScene(values: values) }
        let cal = Calendar.current
        var ticks: [FinAuroraScene.Tick] = []
        let n = points.count
        if n <= 14 {
            // 一年：頭、中間、尾寫月份
            for i in Set([0, n / 2, n - 1]).sorted() {
                ticks.append(.init(index: i, label: "\(cal.component(.month, from: points[i].month))月"))
            }
        } else {
            // 好幾年：每年 1 月寫年份（太擠就隔一年）
            let januaries = points.indices.filter { cal.component(.month, from: points[$0].month) == 1 }
            let every = januaries.count > 6 ? 2 : 1
            for (k, i) in januaries.enumerated() where k % every == 0 {
                ticks.append(.init(index: i, label: String(cal.component(.year, from: points[i].month))))
            }
        }
        return FinAuroraScene(values: values,
                              startLabel: startWord + " " + MoneyFormat.compact(values[0]),
                              endLabel: "現在 " + MoneyFormat.compact(values[values.count - 1]),
                              ticks: ticks)
    }
}

/// 圖表頁的極光看板：夜空、極光的上緣是每個月的淨資產；底下切換近 1 年／近 3 年／全部
struct FinanceChartBoard: View {
    let data: FinanceChartBoardData
    @Binding var period: FinanceChartPeriod

    var body: some View {
        FinanceChartBoardBody(data: data, period: $period)
            // 極光一定是晚上：不管系統深淺色，這張看板都是夜空
            .environment(\.colorScheme, .dark)
    }
}

private struct FinanceChartBoardBody: View {
    let data: FinanceChartBoardData
    @Binding var period: FinanceChartPeriod

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let d = data
        MoneyBoardCard(
            card: .financeChart,
            header: MoneyBoardHeader(
                date: d.points.count >= 2 ? "近 \(d.points.count) 個月" : "這個月",
                dateIcon: "sparkles",
                capsule: d.hasEstimate ? "含估算" : nil,
                capsuleIcon: "wand.and.stars",
                label: "淨資產",
                big: MoneyFormat.short(d.netWorth),
                bigTone: d.netWorth < 0 ? .bad : nil,
                line: line(pal),
                greeting: ["Bright", "future!"],
                scene: .aurora(d.scene),
                band: 120,
                seed: 29),
            content: AnyView(periodChips(pal)))
    }

    private func line(_ pal: TripBoardPalette) -> Text {
        let d = data
        guard let first = d.firstNetWorth else {
            return Text("每個月打開理財頁會記一筆，記滿兩個月就畫得出走勢")
        }
        let change = d.netWorth - first
        let tone: MoneyTone = change >= 0 ? .good : .bad
        var delta = FinanceText.signed(change)
        if abs(first) >= 1 { delta += "（" + FinanceText.signedPercent(change / abs(first)) + "）" }
        return Text("\(d.startWord) \(MoneyFormat.short(first)) → 現在 \(Text(delta).fontWeight(.heavy).foregroundStyle(tone.color(pal)))")
    }

    private func periodChips(_ pal: TripBoardPalette) -> some View {
        HStack(spacing: 8) {
            ForEach(FinanceChartPeriod.allCases) { p in
                let on = p == period
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { period = p }
                } label: {
                    Text(p.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(on ? pal.ink : pal.label)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 34)
                        .background(on ? pal.cellFill : Color.clear, in: Capsule())
                        .overlay(Capsule().stroke(pal.cellStroke, lineWidth: on ? 1 : 0.75))
                }
                .buttonStyle(MoneyPressStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }
}

/// 淨資產走勢：資產（紫）、貸款（紅）、淨資產（綠，下面一片），圓點是當月存下來的紀錄
struct FinanceNetWorthCard: View {
    let points: [FinanceMonthPoint]

    @Environment(\.colorScheme) private var scheme

    private static let ym: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/M"
        return f
    }()

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let assetColor = MoneyArtTheme.finHome.tintColor
        let debtColor = MoneyTone.bad.color(pal)
        let netColor = MoneyTone.good.color(pal)
        VStack(alignment: .leading, spacing: 10) {
            MoneySectionHeader(title: "淨資產走勢", trailing: points.count >= 2 ? "每月一點" : nil)
            VStack(alignment: .leading, spacing: 8) {
                if points.count < 2 {
                    Text("每個月打開理財頁會記一筆，記滿兩個月就畫得出走勢。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Chart {
                        ForEach(points) { pt in
                            AreaMark(x: .value("月份", pt.month), y: .value("淨資產", pt.netWorth))
                                .foregroundStyle(LinearGradient(colors: [netColor.opacity(0.28), netColor.opacity(0.02)],
                                                                startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.monotone)
                        }
                        ForEach(points) { pt in
                            LineMark(x: .value("月份", pt.month), y: .value("金額", pt.assets),
                                     series: .value("項目", "資產"))
                                .foregroundStyle(assetColor.opacity(0.75))
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                                .interpolationMethod(.monotone)
                            LineMark(x: .value("月份", pt.month), y: .value("金額", pt.debt),
                                     series: .value("項目", "貸款"))
                                .foregroundStyle(debtColor.opacity(0.75))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                .interpolationMethod(.monotone)
                            LineMark(x: .value("月份", pt.month), y: .value("金額", pt.netWorth),
                                     series: .value("項目", "淨資產"))
                                .foregroundStyle(netColor)
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                .interpolationMethod(.monotone)
                        }
                        ForEach(points.filter(\.recorded)) { pt in
                            PointMark(x: .value("月份", pt.month), y: .value("金額", pt.netWorth))
                                .foregroundStyle(netColor)
                                .symbolSize(18)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text(MoneyFormat.compact(v)).font(.caption2)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisValueLabel {
                                if let d = value.as(Date.self) {
                                    Text(Self.ym.string(from: d)).font(.caption2)
                                }
                            }
                        }
                    }
                    .frame(height: 190)
                    .accessibilityLabel("淨資產走勢")
                    ChipFlowLayout(spacing: 12) {
                        MoneyLegendItem(mark: .swatch, color: netColor, text: "淨資產", pal: pal)
                        MoneyLegendItem(mark: .swatch, color: assetColor, text: "資產", pal: pal)
                        MoneyLegendItem(mark: .dash, color: debtColor, text: "貸款還要繳", pal: pal)
                    }
                    Text("圓點是那個月打開理財頁時存下來的；其他月份是回推的估算（房子、車子在買入價與現在的估值之間平均變化，股票沒有市值紀錄就用成本）。貸款算的是還要繳的期數 × 每期金額，含利息，所以淨資產會偏保守一點。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
