import SwiftUI

// MARK: - 總覽看板（v25.522，v25.523 重做）
//
// 使用者：「你幫我規劃完整的 KPI 對於使用者會想看的」。打開總覽的人想知道的是
// 「這個月到目前為止怎麼樣、接下來還能花多少」。
//
// [v25.523] 第一版使用者說「質感差很多，這個好亂」：六格擠成兩列三格、迷你圖壓在數字上、
// 大字寫「結餘 +32.7萬」底下又說「會超出 23.4萬」兩句打架、膠囊列同一家店名出現兩次。
// 這一版只回答四件事，一件一個位置：
//
// 1. 大字：本月還能花多少（收入 − 已花），底下一行「收入 X・已花 N%」
// 2. 一張圖：這個月的支出一路累計上去的線、收入那條線、照平常的花法到月底會到哪
//    （圖下面一行圖例寫固定／變動／月底預估的金額，再一行結論：月底可以存多少或會超出多少）
// 3. 四格：本月收入、本月支出（跟上個月同一天比）、每天還能花、今天花了
// 4. 未來 7 天要扣的固定支出（看板下面另外一塊）
//
// 日均、最大一筆、最常去的店、無消費天數這些是「變動支出」的事，搬到變動支出頁的看板。
//
// 插畫：右上角一道「太陽的軌跡」，太陽的位置就是月進度（月初在東邊剛升起、
// 月底在西邊落下）；深色模式是月亮。跟資料有關，不是貼圖。

/// 未來幾天要扣的一筆固定支出
struct OverviewUpcomingBill: Identifiable, Equatable {
    let id: UUID
    let title: String
    let icon: String
    let amount: Double
    let date: Date
    /// 0＝今天、1＝明天…
    let daysAway: Int
}

struct OverviewBoardData: Equatable {
    var month = 1
    var day = 1
    var daysInMonth = 30
    /// 本月已入帳
    var income: Double = 0
    /// 近 6 個月收入中位數（ExpenseStore.estimatedMonthlyIncome）
    var incomeMedian: Double = 0
    /// 拿來算「還能花」的收入：本月已入帳與近 6 個月中位數取大（ExpenseStore.budgetBaseIncome）
    var base: Double = 0
    var baseIsEstimate = false
    /// 本月變動支出
    var variable: Double = 0
    /// 本月固定支出（月等值）
    var fixed: Double = 0
    /// 上個月到同一天為止的支出（變動＋固定月等值）；沒有資料是 nil
    var lastMonthSameDay: Double? = nil
    var todayVariable: Double = 0
    var todayCount = 0
    /// 近 3 個月的變動支出日均（有花錢的月份才算）
    var prev3DailyAvg: Double? = nil
    /// 本月 1 號到今天，每天累計的變動支出
    var cumulative: [Double] = []
    var upcoming: [OverviewUpcomingBill] = []

    // MARK: 推導

    var spending: Double { variable + fixed }
    var hasBase: Bool { base > 0 }
    var monthProgress: Double { Double(day) / Double(max(daysInMonth, 1)) }
    /// 今天起還剩幾天（含今天）
    var remainingDays: Int { max(1, daysInMonth - day + 1) }
    /// 本月還能花（負的＝已經超支）
    var left: Double { base - spending }
    /// 今天起每天還能花多少（負的＝已經超支）
    var allowancePerDay: Double { left / Double(remainingDays) }
    var variableDailyAvg: Double { variable / Double(max(day, 1)) }

    /// 剩下的日子每天大概花多少：有前 3 個月的紀錄就用那個（「平常的花法」），
    /// 沒有才用這個月到目前的日均。
    ///
    /// 不直接拿這個月的日均乘到月底：月初出去玩一趟，日均就被那幾天撐到平常的三倍，
    /// 再乘 31 天會預估出一個不可能的數字（第一版就是這樣，說月底會花 90 萬）。
    var typicalDaily: Double { prev3DailyAvg ?? variableDailyAvg }
    var usesTypicalDaily: Bool { prev3DailyAvg != nil }
    /// 月底預估的總支出＝已經花的＋剩下的日子照平常的花法
    var projectedSpending: Double { spending + typicalDaily * Double(max(0, daysInMonth - day)) }
}

extension OverviewBoardData {
    /// 一次算完。放在 .task(id: store.modifyID) 裡跑，不要在 body 裡算——
    /// 這裡會掃好幾遍全部的支出。
    static func build(store: ExpenseStore, now: Date = Date()) -> OverviewBoardData {
        let cal = Calendar.current
        var d = OverviewBoardData()
        d.month = cal.component(.month, from: now)
        d.day = cal.component(.day, from: now)
        d.daysInMonth = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        d.income = store.currentMonthIncomeTotal
        d.incomeMedian = store.estimatedMonthlyIncome
        d.base = max(d.income, d.incomeMedian)
        d.baseIsEstimate = d.incomeMedian > d.income
        d.fixed = store.currentMonthFixedTotal

        let today = cal.startOfDay(for: now)
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) else {
            return d
        }
        let variables = store.expenses.filter { $0.expenseType == .variable }

        // 本月每天的變動支出
        var daily = Array(repeating: 0.0, count: d.daysInMonth)
        for e in variables where cal.isDate(e.date, equalTo: now, toGranularity: .month) {
            d.variable += e.amount
            if cal.isDate(e.date, inSameDayAs: now) { d.todayCount += 1 }
            let i = cal.component(.day, from: e.date) - 1
            if daily.indices.contains(i) { daily[i] += e.amount }
        }
        if daily.indices.contains(d.day - 1) { d.todayVariable = daily[d.day - 1] }

        var running = 0.0
        var cumulative: [Double] = []
        for i in 0..<min(d.day, daily.count) {
            running += daily[i]
            cumulative.append(running)
        }
        d.cumulative = cumulative

        // 上個月到同一天為止：變動支出照實算，固定支出用上個月那時候的月等值
        if let lastStart = cal.date(byAdding: .month, value: -1, to: monthStart) {
            let lastDays = cal.range(of: .day, in: .month, for: lastStart)?.count ?? 30
            let cutDay = min(d.day, lastDays)
            if let cutoff = cal.date(byAdding: .day, value: cutDay, to: lastStart) {
                let lv = variables.filter { $0.date >= lastStart && $0.date < cutoff }
                    .reduce(0) { $0 + $1.amount }
                let sameDayLastMonth = cal.date(byAdding: .month, value: -1, to: now) ?? lastStart
                let lf = store.fixedMonthlyTotal(for: sameDayLastMonth)
                let total = lv + lf
                d.lastMonthSameDay = total > 0 ? total : nil
            }
        }

        // 近 3 個月的變動日均（那個月有花錢才算進來，沒記帳的月份不該把平均拉低）
        var prevSum = 0.0
        var prevDays = 0
        for back in 1...3 {
            guard let m = cal.date(byAdding: .month, value: -back, to: monthStart),
                  let next = cal.date(byAdding: .month, value: 1, to: m) else { continue }
            let t = variables.filter { $0.date >= m && $0.date < next }.reduce(0) { $0 + $1.amount }
            if t > 0 {
                prevSum += t
                prevDays += cal.range(of: .day, in: .month, for: m)?.count ?? 30
            }
        }
        d.prev3DailyAvg = prevDays > 0 ? prevSum / Double(prevDays) : nil

        // 未來 7 天要扣的固定支出（今天要扣的也算）
        let horizon = cal.date(byAdding: .day, value: 7, to: today) ?? today
        var bills: [OverviewUpcomingBill] = []
        for e in store.expenses where e.isRecurringFixed {
            guard let due = e.nextFixedDueDate(onOrAfter: today, calendar: cal), due < horizon else {
                continue
            }
            let away = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: due)).day ?? 0
            bills.append(OverviewUpcomingBill(id: e.id,
                                              title: e.stopRowLabel(suppressing: []).primary,
                                              icon: e.categoryIcon,
                                              amount: store.ntdValue(of: e),
                                              date: due,
                                              daysAway: max(0, away)))
        }
        d.upcoming = bills.sorted { $0.date < $1.date }
        return d
    }
}

// MARK: - 看板

struct OverviewBoard: View {
    let data: OverviewBoardData
    let openIncome: () -> Void
    let openVariable: () -> Void

    @Environment(\.colorScheme) private var scheme
    /// 只讀「圓角」（看板不吃英雄卡的漸層與 KPI 樣式，同行程看板）
    @ObservedObject private var heroStyle = HeroStyleStore.shared

    var body: some View {
        let pal = TripBoardPalette(scheme)
        return VStack(alignment: .leading, spacing: 0) {
            header(pal)
            chartCard(pal)
                .padding(.top, 12)
            MoneyTileGrid(tiles: [incomeTile(pal), spendingTile(pal), allowanceTile(pal), todayTile(pal)])
                .padding(.top, 8)
        }
        .padding(14)
        .modifier(MoneyBoardChrome(pal: pal, corner: CGFloat(heroStyle.value(.corner, .overview))))
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    // MARK: 標頭

    private func header(_ pal: TripBoardPalette) -> some View {
        let d = data
        let title: String
        let big: String
        let bigTone: MoneyTone?
        if !d.hasBase {
            title = "本月支出"
            big = MoneyFormat.short(d.spending)
            bigTone = nil
        } else if d.left >= 0 {
            title = "本月還能花"
            big = MoneyFormat.short(d.left)
            bigTone = nil
        } else {
            title = "本月已超支"
            big = MoneyFormat.short(-d.left)
            bigTone = .bad
        }
        let dayLine = "\(d.month) 月・第 \(d.day) 天／共 \(d.daysInMonth) 天"
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(dayLine)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(pal.inkDate)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(pal.label)
                }
                Spacer(minLength: 8)
                OverviewSunArc(progress: d.monthProgress, dark: pal.dark, sky: pal.boardTop)
                    .equatable()
                    .frame(width: 104, height: 36)
                    .accessibilityHidden(true)
            }
            Text(big)
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(bigTone?.color(pal) ?? pal.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .padding(.top, 2)
            subLine(pal)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func subLine(_ pal: TripBoardPalette) -> some View {
        let d = data
        if d.hasBase {
            HStack(spacing: 6) {
                Text("收入 " + MoneyFormat.short(d.base))
                if d.baseIsEstimate {
                    Text("預估")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(pal.capsuleText)
                        .padding(.horizontal, 6).padding(.vertical, 1.5)
                        .background(pal.capsuleFill, in: Capsule())
                        .overlay(Capsule().stroke(pal.capsuleStroke, lineWidth: 0.75))
                }
                Text("・已花 " + MoneyFormat.percent(d.spending / d.base))
            }
            .font(.caption)
            .foregroundStyle(pal.label)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        } else {
            Text("記下收入之後，這裡會算出這個月還能花多少。")
                .font(.caption)
                .foregroundStyle(pal.label)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 走勢圖

    private func chartCard(_ pal: TripBoardPalette) -> some View {
        let d = data
        let projected = d.projectedSpending
        let overProjected = d.hasBase && projected > d.base
        let lineColor = d.hasBase && d.left < 0 ? MoneyTone.bad.color(pal) : pal.progressInk
        return VStack(alignment: .leading, spacing: 0) {
            MoneySpendChart(month: d.month, daysInMonth: d.daysInMonth, day: d.day,
                            fixed: d.fixed, cumulative: d.cumulative,
                            projected: d.cumulative.isEmpty ? nil : projected,
                            ceiling: d.hasBase ? d.base : nil,
                            ceilingLabel: d.hasBase
                                ? (d.baseIsEstimate ? "預估收入 " : "收入 ") + MoneyFormat.short(d.base)
                                : nil,
                            line: lineColor,
                            projection: overProjected ? MoneyTone.warn.color(pal) : lineColor,
                            band: MoneyInk.fixedBand(pal),
                            rule: pal.label.opacity(0.35),
                            label: pal.label,
                            halo: pal.cellFill)
                .equatable()
                .frame(height: 118)
                .accessibilityHidden(true)

            legend(pal, projected: projected, lineColor: lineColor)
                .padding(.top, 6)

            Rectangle()
                .fill(pal.label.opacity(0.18))
                .frame(height: 0.5)
                .padding(.top, 8)

            verdict(pal, projected: projected)
                .padding(.top, 8)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .modifier(TripBoardCellChrome(pal: pal))
    }

    private func legend(_ pal: TripBoardPalette, projected: Double, lineColor: Color) -> some View {
        let d = data
        let fixed = MoneyLegendItem(mark: .swatch, color: MoneyInk.fixed(pal),
                                    text: "固定 " + MoneyFormat.short(d.fixed), pal: pal)
        let variable = MoneyLegendItem(mark: .swatch, color: lineColor,
                                       text: "變動 " + MoneyFormat.short(d.variable), pal: pal)
        let month = MoneyLegendItem(mark: .dash, color: lineColor,
                                    text: "月底 " + MoneyFormat.short(projected), pal: pal)
        // 放得下排一列，放不下（字放大、窄螢幕）換成兩列
        return ViewThatFits(in: .horizontal) {
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

    private func verdict(_ pal: TripBoardPalette, projected: Double) -> some View {
        let d = data
        let how = d.usesTypicalDaily ? "照平常的花法" : "照這個月的速度"
        let lead: String
        let amount: String
        let tone: MoneyTone
        if !d.hasBase {
            lead = how + "，月底大約花"
            amount = MoneyFormat.short(projected)
            tone = .neutral
        } else if d.left < 0 {
            lead = "已經超出收入"
            amount = MoneyFormat.short(-d.left)
            tone = .bad
        } else if projected > d.base {
            lead = how + "，月底會超出"
            amount = MoneyFormat.short(projected - d.base)
            tone = .warn
        } else {
            lead = how + "，月底可以存"
            amount = MoneyFormat.short(d.base - projected)
            tone = .good
        }
        let color = tone == .neutral ? pal.ink : tone.color(pal)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            Text("\(lead) \(Text(amount).fontWeight(.bold).foregroundStyle(color))")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(pal.label)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 四格

    private func incomeTile(_ pal: TripBoardPalette) -> AnyView {
        let d = data
        let detail: String
        if d.baseIsEstimate {
            detail = "預期 " + MoneyFormat.short(d.base)
        } else if d.incomeMedian > 0 {
            detail = "近 6 月中位數 " + MoneyFormat.short(d.incomeMedian)
        } else {
            detail = d.income > 0 ? "本月已入帳" : "還沒有紀錄"
        }
        return AnyView(MoneyTile(
            icon: "banknote.fill", tint: .green, label: "本月收入",
            value: MoneyFormat.short(d.income),
            detail: detail,
            action: openIncome, actionHint: "切到收入頁", pal: pal))
    }

    private func spendingTile(_ pal: TripBoardPalette) -> AnyView {
        let d = data
        var detail = "固定＋變動"
        var accent: String? = nil
        var tone: MoneyTone = .neutral
        if let last = d.lastMonthSameDay, let change = MoneyFormat.change(d.spending, vs: last) {
            detail = "比上月同期"
            accent = change
            tone = MoneyTone.spendingChange(d.spending, vs: last)
        }
        return AnyView(MoneyTile(
            icon: "cart.fill", tint: .pink, label: "本月支出",
            value: MoneyFormat.short(d.spending),
            detail: detail, accent: accent, accentTone: tone,
            action: openVariable, actionHint: "切到變動支出頁", pal: pal))
    }

    private func allowanceTile(_ pal: TripBoardPalette) -> AnyView {
        let d = data
        let value: String
        let valueTone: MoneyTone?
        let detail: String
        if !d.hasBase {
            value = "—"
            valueTone = nil
            detail = "需要收入紀錄"
        } else if d.allowancePerDay >= 0 {
            value = MoneyFormat.short(d.allowancePerDay)
            valueTone = nil
            detail = "還有 \(d.remainingDays) 天"
        } else {
            value = "已超支"
            valueTone = .bad
            detail = "還有 \(d.remainingDays) 天"
        }
        return AnyView(MoneyTile(
            icon: "wallet.pass.fill", tint: .blue, label: "每天還能花",
            value: value, valueTone: valueTone,
            detail: detail, pal: pal))
    }

    private func todayTile(_ pal: TripBoardPalette) -> AnyView {
        let d = data
        return AnyView(MoneyTile(
            icon: "calendar", tint: .orange, label: "今天花了",
            value: MoneyFormat.short(d.todayVariable),
            detail: d.todayCount > 0 ? "\(d.todayCount) 筆" : nil,
            accent: d.todayCount > 0 ? nil : "還沒花錢",
            accentTone: .good,
            action: openVariable, actionHint: "切到變動支出頁", pal: pal))
    }
}

// MARK: - 未來 7 天要扣

/// 總覽看板下面另外一塊：接下來一週會扣款的固定支出。點一筆直接編輯。
struct OverviewUpcomingCard: View {
    let bills: [OverviewUpcomingBill]
    let editFixed: (UUID) -> Void

    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var heroStyle = HeroStyleStore.shared
    @State private var showAll = false

    private static let shownByDefault = 3

    private static let dueFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d (E)"
        return f
    }()

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let shown = showAll ? bills : Array(bills.prefix(Self.shownByDefault))
        let total = bills.reduce(0) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("未來 7 天要扣")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(pal.ink)
                Spacer(minLength: 4)
                Text("\(bills.count) 筆・" + MoneyFormat.short(total))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(pal.label)
            }
            .padding(.horizontal, 2)
            .accessibilityElement(children: .combine)

            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, bill in
                    if i > 0 {
                        Rectangle()
                            .fill(pal.label.opacity(0.15))
                            .frame(height: 0.5)
                            .padding(.leading, 38)
                    }
                    Button {
                        editFixed(bill.id)
                    } label: {
                        row(bill, pal: pal)
                    }
                    .buttonStyle(MoneyPressStyle())
                }
                if bills.count > Self.shownByDefault {
                    Rectangle()
                        .fill(pal.label.opacity(0.15))
                        .frame(height: 0.5)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showAll.toggle() }
                    } label: {
                        Text(showAll ? "收起" : "還有 \(bills.count - Self.shownByDefault) 筆")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(pal.hint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .modifier(TripBoardCellChrome(pal: pal))
        }
        .padding(14)
        .modifier(MoneyBoardChrome(pal: pal, corner: CGFloat(heroStyle.value(.corner, .overview))))
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private func row(_ bill: OverviewUpcomingBill, pal: TripBoardPalette) -> some View {
        let when: String
        switch bill.daysAway {
        case 0: when = "今天扣款"
        case 1: when = "明天扣款"
        default: when = Self.dueFmt.string(from: bill.date) + "・\(bill.daysAway) 天後"
        }
        let soon = bill.daysAway <= 1
        return HStack(spacing: 10) {
            TripBoardIconBadge(icon: bill.icon, colors: pal.badge(.purple), diameter: 28, dark: pal.dark)
            VStack(alignment: .leading, spacing: 1) {
                MarqueeText(bill.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(pal.ink)
                Text(when)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(soon ? MoneyTone.warn.color(pal) : pal.label)
            }
            Spacer(minLength: 8)
            Text(MoneyFormat.short(bill.amount))
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(pal.ink)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bill.title + "，" + when + "，" + MoneyFormat.short(bill.amount))
        .accessibilityHint("點兩下編輯這筆固定支出")
    }
}

// MARK: - 插畫：太陽的軌跡

/// 一道從東（左下）升起、往西（右下）落下的弧，太陽的位置＝月進度。
/// 走過的那一段是實線、還沒走的是虛線。深色模式是月亮（一彎月牙）加幾顆星。
/// 看得到、不給讀：日期與天數寫在左邊的 Text 裡。
struct OverviewSunArc: View, Equatable {
    let progress: Double
    let dark: Bool
    /// 天空的顏色（畫月牙時用來挖掉一塊）
    let sky: Color

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let p0 = CGPoint(x: 6, y: h - 3)
            let p2 = CGPoint(x: w - 6, y: h - 3)
            // 弧頂（月中）留出太陽加光暈的高度，不然月中那幾天太陽會被切掉一截
            let r: CGFloat = 7
            let halo = r * 1.9
            let apex = halo + 1
            let c = CGPoint(x: w / 2, y: 2 * apex - p0.y)

            func point(_ t: CGFloat) -> CGPoint {
                let a = (1 - t) * (1 - t)
                let b = 2 * (1 - t) * t
                let e = t * t
                return CGPoint(x: a * p0.x + b * c.x + e * p2.x,
                               y: a * p0.y + b * c.y + e * p2.y)
            }

            // 地平線
            var horizon = Path()
            horizon.move(to: CGPoint(x: 0, y: h - 3))
            horizon.addLine(to: CGPoint(x: w, y: h - 3))
            let lineColor = dark ? Color.white : Color(tb: 0xC98A2E)
            ctx.stroke(horizon, with: .color(lineColor.opacity(dark ? 0.18 : 0.25)),
                       style: StrokeStyle(lineWidth: 0.75))

            let t = CGFloat(max(0, min(1, progress)))
            var walked = Path()
            var ahead = Path()
            let steps = 40
            for i in 0...steps {
                let tt = CGFloat(i) / CGFloat(steps)
                let pt = point(tt)
                if tt <= t {
                    if walked.isEmpty { walked.move(to: pt) } else { walked.addLine(to: pt) }
                }
                if tt >= t {
                    if ahead.isEmpty { ahead.move(to: pt) } else { ahead.addLine(to: pt) }
                }
            }
            ctx.stroke(walked, with: .color(lineColor.opacity(dark ? 0.40 : 0.55)),
                       style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            ctx.stroke(ahead, with: .color(lineColor.opacity(dark ? 0.22 : 0.32)),
                       style: StrokeStyle(lineWidth: 1.1, lineCap: .round, dash: [2, 3.5]))

            let sun = point(t)
            if dark {
                // 幾顆固定位置的星（每次重畫都一樣，不會閃）
                let stars: [CGPoint] = [CGPoint(x: w * 0.18, y: h * 0.30), CGPoint(x: w * 0.34, y: h * 0.12),
                                        CGPoint(x: w * 0.62, y: h * 0.18), CGPoint(x: w * 0.82, y: h * 0.36),
                                        CGPoint(x: w * 0.50, y: h * 0.42)]
                for s in stars where hypot(s.x - sun.x, s.y - sun.y) > r * 2 {
                    ctx.fill(Path(ellipseIn: CGRect(x: s.x - 0.9, y: s.y - 0.9, width: 1.8, height: 1.8)),
                             with: .color(.white.opacity(0.7)))
                }
                let glow = Color(tb: 0xF4F1DE)
                ctx.fill(Path(ellipseIn: CGRect(x: sun.x - halo, y: sun.y - halo,
                                                width: halo * 2, height: halo * 2)),
                         with: .radialGradient(Gradient(colors: [glow.opacity(0.28), glow.opacity(0)]),
                                               center: sun, startRadius: r * 0.6, endRadius: halo))
                ctx.fill(Path(ellipseIn: CGRect(x: sun.x - r, y: sun.y - r, width: r * 2, height: r * 2)),
                         with: .color(glow))
                // 挖掉一塊變月牙
                ctx.fill(Path(ellipseIn: CGRect(x: sun.x - r + 4, y: sun.y - r - 2, width: r * 2, height: r * 2)),
                         with: .color(sky))
            } else {
                let glow = Color(tb: 0xFFC94D)
                ctx.fill(Path(ellipseIn: CGRect(x: sun.x - halo, y: sun.y - halo,
                                                width: halo * 2, height: halo * 2)),
                         with: .radialGradient(Gradient(colors: [glow.opacity(0.45), glow.opacity(0)]),
                                               center: sun, startRadius: r * 0.6, endRadius: halo))
                ctx.fill(Path(ellipseIn: CGRect(x: sun.x - r, y: sun.y - r, width: r * 2, height: r * 2)),
                         with: .color(Color(tb: 0xFFB020)))
            }
        }
    }
}
