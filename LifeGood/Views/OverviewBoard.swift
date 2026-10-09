import SwiftUI

// MARK: - 總覽看板（v25.522）
//
// 使用者：「你幫我規劃完整的 KPI 對於使用者會想看的」。打開總覽的人想知道的是
// 「這個月到目前為止怎麼樣、接下來還能花多少」，所以看板回答的依序是：
//
// 1. 這個月會剩多少（結餘、儲蓄率）
// 2. 收入進來多少、支出花了多少（跟上個月同一天比）
// 3. 今天起每天還能花多少（扣掉這個月還要付的固定支出之後）
// 4. 花的速度：月過了幾成 vs 可以自由花的錢用了幾成，照這個速度月底會怎樣
// 5. 日均、固定支出占收入幾成、今天花了多少
// 6. 這個月的小事：最大一筆、最常去的店、無消費天數、記了幾筆
// 7. 未來 7 天要扣哪些固定支出
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
    /// 預算基準：本月已入帳與近 6 個月中位數取大（ExpenseStore.budgetBaseIncome）
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
    /// 近 7 天每天的變動支出（最後一個是今天）
    var last7: [Double] = []
    /// 本月 1 號到今天，每天累計的變動支出
    var cumulative: [Double] = []
    /// 近 6 個月每月收入（最後一個是本月）
    var incomeMonths: [Double] = []
    var largestTitle: String? = nil
    var largestAmount: Double = 0
    var topPlace: String? = nil
    var topPlaceCount = 0
    /// 本月 1 號到昨天，沒有任何變動支出的天數（今天還沒過完不算）
    var noSpendDays = 0
    /// 本月記帳筆數（變動支出＋收入）
    var entryCount = 0
    var upcoming: [OverviewUpcomingBill] = []

    // MARK: 推導

    var spending: Double { variable + fixed }
    var hasBase: Bool { base > 0 }
    var monthProgress: Double { Double(day) / Double(max(daysInMonth, 1)) }
    /// 今天起還剩幾天（含今天）
    var remainingDays: Int { max(1, daysInMonth - day + 1) }
    var balance: Double { base - spending }
    var savingRate: Double? { hasBase ? balance / base : nil }

    /// 扣掉固定支出之後可以自由花的錢。
    ///
    /// 「燒錢進度」比的是這個，不是「總支出 ÷ 收入」：固定支出在月初就整筆算進來，
    /// 用總支出比的話，月初第 9 天就會顯示「錢花了 50%、月過了 29%」而跳警告，
    /// 其實一點事都沒有。
    var free: Double { base - fixed }
    var freeRatio: Double {
        if free > 0 { return variable / free }
        return variable > 0 ? 1.01 : 0
    }

    /// 今天起每天還能花多少（負的＝已經超支）
    var allowancePerDay: Double { (base - spending) / Double(remainingDays) }
    var variableDailyAvg: Double { variable / Double(max(day, 1)) }
    /// 照目前的速度，月底的總支出
    var projectedSpending: Double { fixed + variableDailyAvg * Double(daysInMonth) }

    var paceTone: MoneyTone {
        if freeRatio > 1 { return .bad }
        if freeRatio > monthProgress + HeroOverspendHint.warnLead { return .warn }
        return .good
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
        let estimate = store.estimatedMonthlyIncome
        d.base = max(d.income, estimate)
        d.baseIsEstimate = estimate > d.income
        d.fixed = store.currentMonthFixedTotal

        let today = cal.startOfDay(for: now)
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) else {
            return d
        }
        let variables = store.expenses.filter { $0.expenseType == .variable }

        // 本月每天的變動支出
        var daily = Array(repeating: 0.0, count: d.daysInMonth)
        var thisMonth: [Expense] = []
        for e in variables where cal.isDate(e.date, equalTo: now, toGranularity: .month) {
            thisMonth.append(e)
            let i = cal.component(.day, from: e.date) - 1
            if daily.indices.contains(i) { daily[i] += e.amount }
        }
        d.variable = thisMonth.reduce(0) { $0 + $1.amount }
        if daily.indices.contains(d.day - 1) { d.todayVariable = daily[d.day - 1] }
        d.todayCount = thisMonth.filter { cal.isDate($0.date, inSameDayAs: now) }.count

        var running = 0.0
        var cumulative: [Double] = []
        for i in 0..<min(d.day, daily.count) {
            running += daily[i]
            cumulative.append(running)
        }
        d.cumulative = cumulative

        // 從「開始記帳的那一天」算起：這個月中才開始用的人，前面那些天不是沒花錢，是還沒記
        // 一筆變動支出都沒記過的人不顯示（不是「無消費 N 天」）
        let lastIndex = min(d.day - 1, daily.count)
        var firstIndex = lastIndex
        if let first = variables.map(\.date).min() {
            firstIndex = first >= monthStart ? cal.component(.day, from: first) - 1 : 0
        }
        var quiet = 0
        if firstIndex < lastIndex {
            for i in firstIndex..<lastIndex where daily[i] == 0 {
                quiet += 1
            }
        }
        d.noSpendDays = quiet

        // 近 7 天（含今天，可能跨月）
        var last7: [Double] = []
        for back in stride(from: 6, through: 0, by: -1) {
            guard let start = cal.date(byAdding: .day, value: -back, to: today),
                  let end = cal.date(byAdding: .day, value: 1, to: start) else { continue }
            let sum = variables.filter { $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.amount }
            last7.append(sum)
        }
        d.last7 = last7

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

        d.incomeMonths = Array(store.heroIncomeSeries().suffix(6).map { $0.value })

        if let big = thisMonth.max(by: { $0.amount < $1.amount }), big.amount > 0 {
            d.largestTitle = big.stopRowLabel(suppressing: []).primary
            d.largestAmount = big.amount
        }

        // 最常去：只算有地點座標的（真的是一個地方），去兩次以上才算「常去」
        var counts: [String: Int] = [:]
        for e in thisMonth where e.hasPlaceCoordinate {
            if let name = e.placeDisplayName { counts[name, default: 0] += 1 }
        }
        let ranked = counts.sorted { a, b in
            a.value != b.value ? a.value > b.value : a.key < b.key
        }
        if let top = ranked.first, top.value >= 2 {
            d.topPlace = top.key
            d.topPlaceCount = top.value
        }

        d.entryCount = thisMonth.count + store.currentMonthIncomes.count

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
    let openFixed: () -> Void
    let editFixed: (UUID) -> Void

    @Environment(\.colorScheme) private var scheme
    /// 只讀「圓角」（看板不吃英雄卡的漸層與 KPI 樣式，同行程看板）
    @ObservedObject private var heroStyle = HeroStyleStore.shared
    @State private var showAllUpcoming = false

    private static let dueFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d (E)"
        return f
    }()

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let chips = chipList()
        return VStack(alignment: .leading, spacing: 10) {
            header(pal)
            tileGrid(pal)
            if data.hasBase {
                paceCard(pal)
            }
            if !chips.isEmpty {
                ChipFlowLayout(spacing: 6) {
                    ForEach(chips) { chip in
                        MoneyChipView(chip: chip, pal: pal)
                    }
                }
            }
            if !data.upcoming.isEmpty {
                upcomingCard(pal)
            }
        }
        .padding(14)
        .modifier(MoneyBoardChrome(pal: pal, corner: CGFloat(heroStyle.value(.corner, .overview))))
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    // MARK: 標頭

    private func header(_ pal: TripBoardPalette) -> some View {
        let d = data
        let title = d.hasBase ? "本月結餘" : "本月支出"
        let big = d.hasBase ? MoneyFormat.signed(d.balance) : MoneyFormat.short(d.spending)
        let bigTone: MoneyTone? = (d.hasBase && d.balance < 0) ? .bad : nil
        let dayLine = "\(d.month) 月・第 \(d.day) 天／共 \(d.daysInMonth) 天"
        let rateText: String? = d.savingRate.map { "儲蓄率 " + MoneyFormat.percent($0) }
        let note: String?
        if !d.hasBase {
            note = "記下收入之後，這裡會算出結餘、儲蓄率和每天還能花多少。"
        } else if d.baseIsEstimate {
            note = "收入還沒全部入帳，先用近 6 個月的中位數 " + MoneyFormat.short(d.base) + " 估。"
        } else {
            note = nil
        }
        return VStack(alignment: .leading, spacing: 4) {
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
                    .frame(width: 118, height: 40)
                    .accessibilityHidden(true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(big)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(bigTone?.color(pal) ?? pal.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                if let rateText {
                    tag(rateText, pal: pal)
                }
                if d.baseIsEstimate {
                    tag("預估", pal: pal)
                }
            }
            if let note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(pal.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func tag(_ text: String, pal: TripBoardPalette) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(pal.capsuleText)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(pal.capsuleFill, in: Capsule())
            .overlay(Capsule().stroke(pal.capsuleStroke, lineWidth: 0.75))
    }

    // MARK: 格子

    private func tileGrid(_ pal: TripBoardPalette) -> some View {
        VStack(spacing: 8) {
            MoneyTileRow(tiles: [incomeTile(pal), spendingTile(pal), allowanceTile(pal)])
            MoneyTileRow(tiles: [dailyTile(pal), fixedTile(pal), todayTile(pal)])
        }
    }

    private func artColor(_ tint: TripBoardTint, _ pal: TripBoardPalette) -> Color {
        pal.badge(tint).last ?? pal.label
    }

    private func incomeTile(_ pal: TripBoardPalette) -> AnyView {
        let d = data
        let detail = d.baseIsEstimate ? "預期 " + MoneyFormat.short(d.base) : "已入帳"
        return AnyView(MoneyTile(
            icon: "banknote.fill", tint: .green, label: "本月收入",
            value: MoneyFormat.short(d.income),
            detail: detail,
            art: d.incomeMonths.count >= 2
                ? AnyView(MoneyBars(values: d.incomeMonths, color: artColor(.green, pal)).equatable())
                : nil,
            action: openIncome, pal: pal))
    }

    private func spendingTile(_ pal: TripBoardPalette) -> AnyView {
        let d = data
        var detail = "變動＋固定"
        var tone: MoneyTone = .neutral
        if let last = d.lastMonthSameDay, let change = MoneyFormat.change(d.spending, vs: last) {
            detail = "比上月同期 " + change
            if d.spending > last * 1.05 { tone = .warn } else if d.spending < last * 0.95 { tone = .good }
        }
        return AnyView(MoneyTile(
            icon: "cart.fill", tint: .pink, label: "本月支出",
            value: MoneyFormat.short(d.spending),
            detail: detail, detailTone: tone,
            art: d.cumulative.count >= 2
                ? AnyView(MoneySparkline(values: d.cumulative, color: artColor(.pink, pal)).equatable())
                : nil,
            action: openVariable, pal: pal))
    }

    private func allowanceTile(_ pal: TripBoardPalette) -> AnyView {
        let d = data
        let value: String
        let valueTone: MoneyTone?
        let detail: String
        let detailTone: MoneyTone
        if !d.hasBase {
            value = "—"
            valueTone = nil
            detail = "還沒有收入紀錄"
            detailTone = .neutral
        } else if d.allowancePerDay >= 0 {
            value = MoneyFormat.short(d.allowancePerDay)
            valueTone = nil
            detail = "還有 \(d.remainingDays) 天"
            detailTone = .neutral
        } else {
            value = "已超支"
            valueTone = .bad
            detail = "超出 " + MoneyFormat.short(d.spending - d.base)
            detailTone = .bad
        }
        return AnyView(MoneyTile(
            icon: "wallet.pass.fill", tint: .blue, label: "每天還能花",
            value: value, valueTone: valueTone,
            detail: detail, detailTone: detailTone,
            art: d.hasBase
                ? AnyView(MoneyRing(fraction: max(0, 1 - d.freeRatio),
                                    color: artColor(.blue, pal), track: pal.progressTrack).equatable())
                : nil,
            pal: pal))
    }

    private func dailyTile(_ pal: TripBoardPalette) -> AnyView {
        let d = data
        var detail = "近 7 天"
        var tone: MoneyTone = .neutral
        if let prev = d.prev3DailyAvg, let change = MoneyFormat.change(d.variableDailyAvg, vs: prev) {
            detail = "比近 3 月 " + change
            if d.variableDailyAvg > prev * 1.05 { tone = .warn } else if d.variableDailyAvg < prev * 0.95 { tone = .good }
        }
        return AnyView(MoneyTile(
            icon: "chart.bar.fill", tint: .orange, label: "日均花費",
            value: MoneyFormat.short(d.variableDailyAvg),
            detail: detail, detailTone: tone,
            art: d.last7.count >= 2
                ? AnyView(MoneyBars(values: d.last7, color: artColor(.orange, pal)).equatable())
                : nil,
            action: openVariable, pal: pal))
    }

    private func fixedTile(_ pal: TripBoardPalette) -> AnyView {
        let d = data
        let share = d.hasBase ? d.fixed / d.base : 0
        let detail = d.hasBase ? "占收入 " + MoneyFormat.percent(share) : "每月等值"
        let tone: MoneyTone = d.hasBase && share > 0.5 ? .warn : .neutral
        return AnyView(MoneyTile(
            icon: "pin.fill", tint: .purple, label: "固定支出",
            value: MoneyFormat.short(d.fixed),
            detail: detail, detailTone: tone,
            art: d.hasBase
                ? AnyView(MoneyRing(fraction: share, color: artColor(.purple, pal),
                                    track: pal.progressTrack).equatable())
                : nil,
            action: openFixed, pal: pal))
    }

    private func todayTile(_ pal: TripBoardPalette) -> AnyView {
        let d = data
        let detail = d.todayCount > 0 ? "\(d.todayCount) 筆" : "零支出 ✓"
        return AnyView(MoneyTile(
            icon: "calendar", tint: .mint, label: "今天花了",
            value: MoneyFormat.short(d.todayVariable),
            detail: detail, detailTone: d.todayCount > 0 ? .neutral : .good,
            pal: pal))
    }

    // MARK: 燒錢進度

    private func paceCard(_ pal: TripBoardPalette) -> some View {
        let d = data
        let status: String
        if d.free <= 0 {
            status = "固定支出（" + MoneyFormat.short(d.fixed) + "）已經吃掉整個收入（"
                + MoneyFormat.short(d.base) + "），每一筆變動支出都是超支。"
        } else if d.freeRatio > 1 {
            status = "扣掉固定支出可以花的 " + MoneyFormat.short(d.free) + " 已經用完，超出 "
                + MoneyFormat.short(d.variable - d.free) + "。"
        } else if d.projectedSpending > d.base {
            status = "照這個速度，月底大約花 " + MoneyFormat.short(d.projectedSpending) + "，會超出 "
                + MoneyFormat.short(d.projectedSpending - d.base) + "。"
        } else {
            status = "照這個速度，月底大約花 " + MoneyFormat.short(d.projectedSpending) + "，可以剩 "
                + MoneyFormat.short(d.base - d.projectedSpending) + "。"
        }
        return MoneyPaceCard(title: "燒錢進度", icon: "flame.fill",
                             monthProgress: d.monthProgress,
                             spentLabel: "可花的錢用了", spentRatio: d.freeRatio,
                             tone: d.paceTone, status: status,
                             tag: d.baseIsEstimate ? "預估" : nil, pal: pal)
    }

    // MARK: 膠囊

    private func chipList() -> [MoneyChip] {
        let d = data
        var out: [MoneyChip] = []
        if let t = d.largestTitle, d.largestAmount > 0 {
            out.append(MoneyChip(id: "big", icon: "crown.fill",
                                 text: "最大一筆 " + Self.clip(t) + " " + MoneyFormat.short(d.largestAmount)))
        }
        if let p = d.topPlace {
            out.append(MoneyChip(id: "place", icon: "mappin.and.ellipse",
                                 text: "最常去 " + Self.clip(p) + " ×\(d.topPlaceCount)"))
        }
        if d.noSpendDays > 0 {
            out.append(MoneyChip(id: "quiet", icon: "leaf.fill", text: "無消費 \(d.noSpendDays) 天"))
        }
        if d.entryCount > 0 {
            out.append(MoneyChip(id: "count", icon: "square.and.pencil", text: "本月記了 \(d.entryCount) 筆"))
        }
        return out
    }

    /// 膠囊不換行、不捲動，太長的名字截到 10 個字
    private static func clip(_ s: String) -> String {
        s.count > 10 ? String(s.prefix(10)) + "…" : s
    }

    // MARK: 未來 7 天要扣

    private func upcomingCard(_ pal: TripBoardPalette) -> some View {
        let all = data.upcoming
        let shown = showAllUpcoming ? all : Array(all.prefix(3))
        let total = all.reduce(0) { $0 + $1.amount }
        let summary = "\(all.count) 筆・" + MoneyFormat.short(total)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(artColor(.blue, pal))
                Text("未來 7 天要扣")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(pal.ink)
                Spacer(minLength: 4)
                Text(summary)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(pal.label)
            }
            .padding(.bottom, 4)
            ForEach(shown) { bill in
                Button {
                    editFixed(bill.id)
                } label: {
                    upcomingRow(bill, pal: pal)
                }
                .buttonStyle(.plain)
            }
            if all.count > 3 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showAllUpcoming.toggle() }
                } label: {
                    Text(showAllUpcoming ? "收起" : "還有 \(all.count - 3) 筆")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(pal.hint)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .modifier(TripBoardCellChrome(pal: pal))
    }

    private func upcomingRow(_ bill: OverviewUpcomingBill, pal: TripBoardPalette) -> some View {
        let when: String
        switch bill.daysAway {
        case 0: when = "今天扣款"
        case 1: when = "明天扣款"
        default: when = Self.dueFmt.string(from: bill.date) + "・\(bill.daysAway) 天後"
        }
        let soon = bill.daysAway <= 1
        return HStack(spacing: 10) {
            TripBoardIconBadge(icon: bill.icon, colors: pal.badge(.blue), diameter: 26, dark: pal.dark)
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
        .padding(.vertical, 6)
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
            let c = CGPoint(x: w / 2, y: -h + 6)

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
            let r: CGFloat = 7
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
                ctx.fill(Path(ellipseIn: CGRect(x: sun.x - r * 2.2, y: sun.y - r * 2.2,
                                                width: r * 4.4, height: r * 4.4)),
                         with: .radialGradient(Gradient(colors: [glow.opacity(0.28), glow.opacity(0)]),
                                               center: sun, startRadius: r * 0.6, endRadius: r * 2.2))
                ctx.fill(Path(ellipseIn: CGRect(x: sun.x - r, y: sun.y - r, width: r * 2, height: r * 2)),
                         with: .color(glow))
                // 挖掉一塊變月牙
                ctx.fill(Path(ellipseIn: CGRect(x: sun.x - r + 4, y: sun.y - r - 2, width: r * 2, height: r * 2)),
                         with: .color(sky))
            } else {
                let glow = Color(tb: 0xFFC94D)
                ctx.fill(Path(ellipseIn: CGRect(x: sun.x - r * 2.4, y: sun.y - r * 2.4,
                                                width: r * 4.8, height: r * 4.8)),
                         with: .radialGradient(Gradient(colors: [glow.opacity(0.45), glow.opacity(0)]),
                                               center: sun, startRadius: r * 0.6, endRadius: r * 2.4))
                ctx.fill(Path(ellipseIn: CGRect(x: sun.x - r, y: sun.y - r, width: r * 2, height: r * 2)),
                         with: .color(Color(tb: 0xFFB020)))
            }
        }
    }
}
