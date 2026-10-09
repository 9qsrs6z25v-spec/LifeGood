import SwiftUI

// MARK: - 總覽看板（v25.522，v25.523 重做，v25.526 換成城市）
//
// 使用者：「你幫我規劃完整的 KPI 對於使用者會想看的」。打開總覽的人想知道的是
// 「這個月到目前為止怎麼樣、接下來還能花多少」。
//
// [v25.523] 第一版使用者說「質感差很多，這個好亂」：只回答四件事，一件一個位置。
//
// [v25.526] 使用者：「上方看板差強人意，你再好好規劃」。字與數字沒有問題，問題是畫面上
// 看不到自己這個月的錢——只有字和角落一個小太陽。改成跟行程看板同一套頭部（天空、雲、
// 手寫的 Have a nice October!），最下面畫一座「這個月的城市」（MoneyBoardScenes.swift）：
// - 每天一棟樓，樓高＝那天的變動支出；沒花錢的日子種一棵樹；還沒到的日子是虛線框的空地
// - 一條虛線是日預算（扣掉固定支出後平均每天可以花多少），超過的那一截樓頂是橘色
// - 今天那棟插一面小旗
// - 地上一條鐵道：固定支出的扣款日是車站，電車停在今天，下一站寫「明天扣 Netflix」
//
// 版面：
// 1. 頭部：日期／已花幾成（膠囊）、本月還能花（大字）、一句結論（月底可以存多少或會超出多少）
// 2. 「這個月的錢」：一條橫條（固定紫、變動藍、照平常的花法到月底的那一段畫斜線、收入一道刻度）
// 3. 四格：本月收入、本月支出（跟上個月同一天比）、每天還能花、今天花了（右下角淡淡的圖案）
// 4. 未來 7 天要扣的固定支出（看板下面另外一塊）
//
// 原本那張走勢圖（MoneySpendChart）跟右上角的太陽（OverviewSunArc）拿掉：
// 城市就是每天花多少的圖，橫條就是累計到月底的樣子。

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
    /// 本月 1 號到今天，每天的變動支出（城市裡一天一棟樓）
    var daily: [Double] = []
    /// 這個月從哪一天開始有記帳：之前的日子不種樹（那不是沒花錢，是還沒開始記）
    var firstDay = 1
    /// 這個月每一筆固定支出的扣款日（鐵道上的車站）
    var dues: [MoneyFixedDue] = []
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

    /// 日預算：收入扣掉固定支出，平均到這個月的每一天（城市裡那一條虛線）。
    /// 固定支出就超過收入、或沒有收入紀錄時不畫。
    var dailyBudget: Double? {
        guard hasBase, base > fixed else { return nil }
        return (base - fixed) / Double(max(daysInMonth, 1))
    }
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
        d.daily = Array(daily.prefix(d.day))

        // 從哪一天開始記帳：最早一筆變動支出在這個月就從那天起；更早就從 1 號；一筆都沒有就不種樹
        if let first = variables.map(\.date).min() {
            d.firstDay = first < monthStart ? 1 : cal.component(.day, from: first)
        } else {
            d.firstDay = d.day + 1
        }

        d.dues = MoneyFixedSchedule.thisMonth(store: store, now: now, calendar: cal)

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

    var body: some View {
        let pal = TripBoardPalette(scheme)
        MoneyBoardCard(
            card: .overview,
            header: header(pal),
            content: AnyView(
                VStack(alignment: .leading, spacing: 8) {
                    moneyCell(pal)
                    MoneyTileGrid(tiles: [incomeTile(pal), spendingTile(pal), allowanceTile(pal), todayTile(pal)])
                }))
    }

    // MARK: 頭部

    private func header(_ pal: TripBoardPalette) -> MoneyBoardHeader {
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
        return MoneyBoardHeader(
            date: "\(d.month) 月・第 \(d.day) 天／共 \(d.daysInMonth) 天",
            capsule: d.hasBase ? "已花 " + MoneyFormat.percent(d.spending / d.base) : nil,
            capsuleIcon: "chart.pie.fill",
            label: title,
            big: big,
            bigTone: bigTone,
            line: verdict(pal),
            greeting: ["Have a nice", MoneyBoardText.month(d.month) + "!"],
            scene: .city(cityScene),
            seed: d.month * 31 + 7)
    }

    /// 頭部那一句：照平常的花法，月底可以存多少／會超出多少
    private func verdict(_ pal: TripBoardPalette) -> Text {
        let d = data
        let projected = d.projectedSpending
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
        return Text("\(lead) \(Text(amount).fontWeight(.heavy).foregroundStyle(color))")
    }

    private var cityScene: MoneyCityScene {
        let d = data
        return MoneyCityScene(
            daysInMonth: d.daysInMonth,
            today: d.day,
            daily: d.daily,
            firstDay: d.firstDay,
            dailyBudget: d.dailyBudget,
            budgetLabel: d.dailyBudget.map { "日預算 " + MoneyFormat.short($0) },
            stations: MoneyFixedSchedule.stations(d.dues, today: d.day),
            nextLabel: MoneyFixedSchedule.label(MoneyFixedSchedule.next(d.dues, today: d.day),
                                                today: d.day, month: d.month))
    }

    // MARK: 這個月的錢

    private func moneyCell(_ pal: TripBoardPalette) -> some View {
        let d = data
        let projected = d.projectedSpending
        let over = d.hasBase && projected > d.base
        let trailing = d.hasBase
            ? "收入 " + MoneyFormat.short(d.base) + (d.baseIsEstimate ? "・預估" : "")
            : "還沒有收入紀錄"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("這個月的錢")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(pal.ink)
                Spacer(minLength: 6)
                Text(trailing)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(pal.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            MoneySplitBar(fixed: d.fixed, variable: d.variable,
                          projected: d.daily.isEmpty ? d.spending : projected,
                          income: d.hasBase ? d.base : nil, dark: pal.dark)
                .equatable()
                .frame(height: 18)
                .accessibilityHidden(true)
            legend(pal, projected: projected, over: over)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .modifier(TripBoardCellChrome(pal: pal))
        .accessibilityElement(children: .combine)
    }

    private func legend(_ pal: TripBoardPalette, projected: Double, over: Bool) -> some View {
        let d = data
        let fixed = MoneyLegendItem(mark: .swatch, color: MoneySplitBar.fixedInk(dark: pal.dark),
                                    text: "固定 " + MoneyFormat.short(d.fixed), pal: pal)
        let variable = MoneyLegendItem(mark: .swatch, color: MoneySplitBar.variableInk(dark: pal.dark),
                                       text: "變動 " + MoneyFormat.short(d.variable), pal: pal)
        let month = MoneyLegendItem(mark: .dash,
                                    color: over ? MoneyTone.warn.color(pal) : MoneySplitBar.variableInk(dark: pal.dark),
                                    text: "月底約 " + MoneyFormat.short(projected), pal: pal)
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
            action: openIncome, actionHint: "切到收入頁", watermark: "banknote", pal: pal))
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
            action: openVariable, actionHint: "切到變動支出頁", watermark: "bag", pal: pal))
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
            detail: detail, watermark: "calendar", pal: pal))
    }

    private func todayTile(_ pal: TripBoardPalette) -> AnyView {
        let d = data
        return AnyView(MoneyTile(
            icon: "calendar", tint: .orange, label: "今天花了",
            value: MoneyFormat.short(d.todayVariable),
            detail: d.todayCount > 0 ? "\(d.todayCount) 筆" : nil,
            accent: d.todayCount > 0 ? nil : "還沒花錢",
            accentTone: .good,
            action: openVariable, actionHint: "切到變動支出頁", watermark: "sun.max", pal: pal))
    }
}

// MARK: - 這個月的錢：一條橫條

/// 固定（紫）＋變動（藍）＋照平常的花法到月底還會花的那一段（斜線），收入是一道刻度。
/// 刻度以後的斜線換成橘色（照這樣花，月底會超出收入的那一段）。
/// 看得到、不給讀：金額寫在下面的圖例裡。
struct MoneySplitBar: View, Equatable {
    let fixed: Double
    let variable: Double
    /// 月底預估的總支出（已經花的也算在裡面）
    let projected: Double
    let income: Double?
    let dark: Bool

    static func fixedInk(dark: Bool) -> Color { dark ? Color(tb: 0xA98BFF) : Color(tb: 0x8B5CF6) }
    static func variableInk(dark: Bool) -> Color { dark ? Color(tb: 0x5B9BFF) : Color(tb: 0x2F6FE0) }

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let barH: CGFloat = 10
            let y = (size.height - barH) / 2
            let spent = fixed + variable
            let scale = max(income ?? 0, projected, spent, 1)
            func x(_ v: Double) -> CGFloat { CGFloat(max(0, v) / scale) * w }

            let bar = Path(roundedRect: CGRect(x: 0, y: y, width: w, height: barH), cornerRadius: barH / 2)
            ctx.fill(bar, with: .color(dark ? Color.white.opacity(0.10) : Color(tb: 0xE3ECF8)))
            var g = ctx
            g.clip(to: bar)

            let fixedEnd = x(fixed)
            if fixed > 0 {
                g.fill(Path(CGRect(x: 0, y: y, width: fixedEnd, height: barH)),
                       with: .linearGradient(Gradient(colors: dark
                                                          ? [Color(tb: 0x8B5CF6), Color(tb: 0xA98BFF)]
                                                          : [Color(tb: 0xB38BFF), Color(tb: 0x8B5CF6)]),
                                             startPoint: CGPoint(x: 0, y: y),
                                             endPoint: CGPoint(x: max(fixedEnd, 1), y: y)))
            }
            let spentEnd = x(spent)
            if variable > 0 {
                g.fill(Path(CGRect(x: fixedEnd, y: y, width: spentEnd - fixedEnd, height: barH)),
                       with: .linearGradient(Gradient(colors: dark
                                                          ? [Color(tb: 0x3D86FF), Color(tb: 0x5B9BFF)]
                                                          : [Color(tb: 0x5B9BFF), Color(tb: 0x2459D6)]),
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
                          color: dark ? Color(tb: 0xFFC14D) : Color(tb: 0xE07800))
                }
            }
            // 收入的刻度
            if let income, income > 0 {
                let ix = min(w - 1, max(1, x(income)))
                ctx.fill(Path(roundedRect: CGRect(x: ix - 1, y: 0, width: 2, height: size.height), cornerRadius: 1),
                         with: .color(dark ? Color(tb: 0xF3F6FF) : Color(tb: 0x0B1B45)))
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
