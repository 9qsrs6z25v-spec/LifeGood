import SwiftUI

// MARK: - 收支看板：外框、膠囊、三頁的資料與看板（v25.526）
//
// 頭部（天空＋風景＋手寫問候）在 MoneyBoardScenes.swift；這個檔案是：
// - MoneyBoardCard：看板的外框（頭部＋下面的內容），圓角讀英雄卡設定的「圓角」
// - MoneyBoardChip：看板下面那幾顆白色膠囊（灰色的標籤＋深色的數字）
// - MoneyFixedSchedule：這個月每一筆固定支出哪一天扣（總覽的城市、固定支出的列車共用）
// - 變動支出（市集）、收入（山）、固定支出（列車）三塊看板與它們的資料
// 總覽在 OverviewBoard.swift；圖表的星空寫在 ChartView 裡（期間切換在那裡）。
//
// 原本這幾頁最上面是英雄卡（漸層＋三格 KPI＋雙軌進度條＋超支小字提示），
// 這一版跟總覽同一套：一個大數字、一句話、一幅用資料畫的風景、幾顆膠囊。
// 原本 KPI 裡的數字都還在：搬到膠囊或頭部右上角的那一顆。

/// 看板的外框：頭部貼齊上緣（天空畫滿），下面的內容留邊。
struct MoneyBoardCard: View {
    let card: HeroCard
    let header: MoneyBoardHeader
    var content: AnyView? = nil

    @Environment(\.colorScheme) private var scheme
    /// 只讀「圓角」（看板不吃英雄卡的漸層與 KPI 樣式，同行程看板）
    @ObservedObject private var heroStyle = HeroStyleStore.shared

    var body: some View {
        let pal = TripBoardPalette(scheme)
        VStack(alignment: .leading, spacing: 0) {
            header
            if let content {
                content
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
            }
        }
        .modifier(MoneyBoardChrome(pal: pal, corner: CGFloat(heroStyle.value(.corner, card))))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

// MARK: - 膠囊

struct MoneyBoardChip: Identifiable, Equatable {
    let icon: String
    let label: String
    let value: String
    var tone: MoneyTone = .neutral

    var id: String { icon + label + value }
}

/// 一顆膠囊：圖示、灰色的標籤、深色的數字（好／注意／超過才上色）
struct MoneyBoardChipView: View {
    let chip: MoneyBoardChip
    let pal: TripBoardPalette

    var body: some View {
        let valueColor = chip.tone == .neutral ? pal.ink : chip.tone.color(pal)
        let iconColor = chip.tone == .neutral ? pal.hint : chip.tone.color(pal)
        HStack(spacing: 5) {
            Image(systemName: chip.icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(iconColor)
            if chip.label.isEmpty {
                Text(chip.value)
                    .foregroundStyle(valueColor)
            } else {
                Text("\(Text(chip.label).foregroundStyle(pal.label)) \(Text(chip.value).foregroundStyle(valueColor))")
            }
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 11)
        .frame(minHeight: 28)
        .background(pal.cellFill, in: Capsule())
        .overlay(Capsule().stroke(pal.cellStroke, lineWidth: pal.dark ? 0.5 : 0.75))
        .shadow(color: pal.cellShadow, radius: 4, x: 0, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chip.label.isEmpty ? chip.value : chip.label + " " + chip.value)
    }
}

/// 會自動換行的一排膠囊（擠不下時換行，不切字）
struct MoneyBoardChips: View {
    let chips: [MoneyBoardChip]
    let pal: TripBoardPalette

    var body: some View {
        ChipFlowLayout(spacing: 6) {
            ForEach(chips) { chip in
                MoneyBoardChipView(chip: chip, pal: pal)
            }
        }
    }
}

enum MoneyBoardText {
    private static let months = ["January", "February", "March", "April", "May", "June", "July",
                                 "August", "September", "October", "November", "December"]

    /// 手寫問候用的英文月份（「Have a nice October!」）
    static func month(_ m: Int) -> String {
        months[min(12, max(1, m)) - 1]
    }

    /// 膠囊、牌子上的名字：太長就截掉（膠囊不換行，太長會把整排撐開）
    static func short(_ s: String, max n: Int = 8) -> String {
        s.count > n ? String(s.prefix(n - 1)) + "…" : s
    }
}

// MARK: - 這個月的扣款日

/// 這個月的一筆固定支出：哪一天扣、扣什麼、多少
struct MoneyFixedDue: Equatable {
    let day: Int
    let title: String
    let amount: Double
}

enum MoneyFixedSchedule {
    /// 這個月每一筆週期性固定支出的扣款日。規則跟固定支出卡上的「明天扣款」同一支
    /// （Expense.nextFixedDueDate）：還沒開始的、已經停止的不算；季繳、年繳只有扣款的那個月才有。
    static func thisMonth(store: ExpenseStore, now: Date = Date(),
                          calendar cal: Calendar = .current) -> [MoneyFixedDue] {
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)),
              let nextMonth = cal.date(byAdding: .month, value: 1, to: monthStart) else { return [] }
        var out: [MoneyFixedDue] = []
        for e in store.expenses where e.isRecurringFixed {
            guard let due = e.nextFixedDueDate(onOrAfter: monthStart, calendar: cal), due < nextMonth else {
                continue
            }
            out.append(MoneyFixedDue(day: cal.component(.day, from: due),
                                     title: MoneyItem.title(e),
                                     amount: store.ntdValue(of: e)))
        }
        return out.sorted { $0.day == $1.day ? $0.amount > $1.amount : $0.day < $1.day }
    }

    /// 一天一站（同一天扣好幾筆也是一站）；今天以前的是扣過的，今天或之後最近的那一站是下一站
    static func stations(_ dues: [MoneyFixedDue], today: Int) -> [MoneyRailStation] {
        let days = Set(dues.map(\.day)).sorted()
        let next = days.first { $0 >= today }
        return days.map { MoneyRailStation(day: $0, past: $0 < today, isNext: $0 == next) }
    }

    /// 下一站要扣的那幾筆
    static func next(_ dues: [MoneyFixedDue], today: Int) -> [MoneyFixedDue] {
        guard let day = dues.map(\.day).filter({ $0 >= today }).min() else { return [] }
        return dues.filter { $0.day == day }
    }

    /// 「今天」「明天」「10/12」
    static func when(day: Int, today: Int, month: Int) -> String {
        switch day - today {
        case 0: return "今天"
        case 1: return "明天"
        default: return "\(month)/\(day)"
        }
    }

    /// 「明天扣 Netflix」「10/12 扣 3 筆」
    static func label(_ next: [MoneyFixedDue], today: Int, month: Int) -> String? {
        guard let first = next.first else { return nil }
        let w = when(day: first.day, today: today, month: month)
        let what = next.count == 1 ? MoneyBoardText.short(first.title) : "\(next.count) 筆"
        return w + (w.contains("/") ? " 扣 " : "扣 ") + what
    }

    /// 月均（NT$ 等值）：季繳 ÷ 3、年繳 ÷ 12；外幣儲蓄險先換成 NT$
    static func monthlyNTD(_ e: Expense, store: ExpenseStore) -> Double {
        let ntd = store.ntdValue(of: e)
        switch e.recurrence {
        case .monthly, .none: return ntd
        case .quarterly: return ntd / 3
        case .yearly: return ntd / 12
        }
    }
}

// MARK: - 變動支出：市集

struct VariableBoardData: Equatable {
    var month = 1
    var day = 1
    var total: Double = 0
    var count = 0
    var today: Double = 0
    var todayCount = 0
    /// 近 3 個月「1 號到同一天」的平均。只算整個月都有在記帳的月份（從月中才開始記的那個月，
    /// 前半個月是 0，拿來比會說這個月多花了好幾倍）；沒有可以比的月份是 nil
    var samePeriodAvg: Double? = nil
    /// 一個分類一家店，最多五家（第五家以後併成「其他」）
    var shops: [MoneyMarketScene.Shop] = []
    var largestTitle: String? = nil
    var largestAmount: Double = 0
    var topPlace: String? = nil
    var topPlaceCount = 0
    /// 這個月一毛都沒花的天數（從開始記帳那天起算到昨天；今天還沒過完不算）
    var noSpendDays = 0

    var dailyAvg: Double { total / Double(max(day, 1)) }

    /// 放在 .task(id: store.modifyID) 裡跑，不要在 body 裡算（會掃好幾遍全部的支出）
    static func build(store: ExpenseStore, now: Date = Date()) -> VariableBoardData {
        let cal = Calendar.current
        var d = VariableBoardData()
        d.month = cal.component(.month, from: now)
        d.day = cal.component(.day, from: now)
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) else { return d }
        let variables = store.expenses.filter { $0.expenseType == .variable }
        let firstEver = variables.map(\.date).min().map { cal.startOfDay(for: $0) }

        var spentDays = Set<Int>()
        var byCategory: [VariableCategory: Double] = [:]
        var places: [String: Int] = [:]
        var largest: Expense? = nil
        for e in variables where cal.isDate(e.date, equalTo: now, toGranularity: .month) {
            d.total += e.amount
            d.count += 1
            if cal.isDate(e.date, inSameDayAs: now) {
                d.today += e.amount
                d.todayCount += 1
            }
            spentDays.insert(cal.component(.day, from: e.date))
            byCategory[e.variableCategory ?? .other, default: 0] += e.amount
            if let p = e.placeName?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
                places[p, default: 0] += 1
            }
            if e.amount > (largest?.amount ?? 0) { largest = e }
        }
        if let largest {
            d.largestTitle = MoneyBoardText.short(MoneyItem.title(largest), max: 10)
            d.largestAmount = largest.amount
        }
        if let top = places.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }),
           top.value >= 2 {
            d.topPlace = MoneyBoardText.short(top.key)
            d.topPlaceCount = top.value
        }

        // 店：「其他」固定排最後；有名字的分類超過四類（有「其他」時）或五類，後面的併進「其他」
        if d.total > 0 {
            let named = byCategory.filter { $0.key != .other }.sorted { $0.value > $1.value }
            var otherSum = byCategory[.other] ?? 0
            let room = otherSum > 0 ? 4 : 5
            var kept = named
            if named.count > room {
                kept = Array(named.prefix(4))
                otherSum += named.dropFirst(4).reduce(0) { $0 + $1.value }
            }
            var shops = kept.map {
                MoneyMarketScene.Shop(theme: MoneyArtTheme.of($0.key), amount: $0.value, share: $0.value / d.total)
            }
            if otherSum > 0 {
                shops.append(MoneyMarketScene.Shop(theme: .misc, amount: otherSum, share: otherSum / d.total))
            }
            d.shops = shops
        }

        // 無消費：從這個月開始記帳的那一天起，到昨天
        if let firstEver {
            let firstDay = firstEver < monthStart ? 1 : cal.component(.day, from: firstEver)
            if firstDay < d.day {
                d.noSpendDays = (firstDay..<d.day).filter { !spentDays.contains($0) }.count
            }
        }

        // 近 3 個月同期
        var sums: [Double] = []
        for back in 1...3 {
            guard let m = cal.date(byAdding: .month, value: -back, to: monthStart),
                  let firstEver, firstEver <= m else { continue }
            let mDays = cal.range(of: .day, in: .month, for: m)?.count ?? 30
            guard let cut = cal.date(byAdding: .day, value: min(d.day, mDays), to: m) else { continue }
            sums.append(variables.filter { $0.date >= m && $0.date < cut }.reduce(0) { $0 + $1.amount })
        }
        d.samePeriodAvg = sums.isEmpty ? nil : sums.reduce(0, +) / Double(sums.count)
        return d
    }
}

struct VariableBoard: View {
    let data: VariableBoardData

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let d = data
        MoneyBoardCard(
            card: .variableExpense,
            header: MoneyBoardHeader(
                date: "\(d.month) 月・第 \(d.day) 天",
                capsule: "本月 \(d.count) 筆", capsuleIcon: "list.bullet",
                label: "本月變動支出",
                big: MoneyFormat.short(d.total),
                line: line(pal),
                greeting: ["Spend", "wisely!"],
                scene: .market(MoneyMarketScene(shops: d.shops)),
                seed: d.month * 29 + 3),
            content: AnyView(MoneyBoardChips(chips: chips, pal: pal)))
    }

    private func line(_ pal: TripBoardPalette) -> Text {
        let d = data
        guard let avg = d.samePeriodAvg else {
            return Text(d.total > 0 ? "前幾個月還沒有完整的紀錄可以比" : "這個月還沒有變動支出")
        }
        guard avg > 0 else { return Text("近 3 個月的同一段時間都沒有花費") }
        let r = d.total / avg - 1
        if abs(r) < 0.01 { return Text("跟近 3 個月同期差不多") }
        let pct = MoneyFormat.percent(abs(r))
        if r > 0 {
            return Text("比近 3 個月同期多 \(Text(pct).fontWeight(.heavy).foregroundStyle(MoneyTone.warn.color(pal)))")
        }
        return Text("比近 3 個月同期少 \(Text(pct).fontWeight(.heavy).foregroundStyle(MoneyTone.good.color(pal)))")
    }

    private var chips: [MoneyBoardChip] {
        let d = data
        var out: [MoneyBoardChip] = []
        if d.todayCount > 0 {
            out.append(MoneyBoardChip(icon: "sun.max.fill", label: "今天", value: MoneyFormat.short(d.today)))
        } else {
            out.append(MoneyBoardChip(icon: "sun.max.fill", label: "今天", value: "還沒花錢", tone: .good))
        }
        if d.total > 0 {
            out.append(MoneyBoardChip(icon: "chart.line.uptrend.xyaxis", label: "日均",
                                      value: MoneyFormat.short(d.dailyAvg)))
        }
        if let t = d.largestTitle {
            out.append(MoneyBoardChip(icon: "crown.fill", label: "最大一筆",
                                      value: t + " " + MoneyFormat.short(d.largestAmount)))
        }
        if let p = d.topPlace {
            out.append(MoneyBoardChip(icon: "mappin.and.ellipse", label: "最常去", value: "\(p) ×\(d.topPlaceCount)"))
        }
        if d.noSpendDays > 0 {
            out.append(MoneyBoardChip(icon: "leaf.fill", label: "無消費", value: "\(d.noSpendDays) 天", tone: .good))
        }
        return out
    }
}

// MARK: - 收入：山

struct IncomeBoardData: Equatable {
    var year = 2026
    var month = 1
    /// 本月已入帳（ExpenseStore.currentMonthIncomeTotal）
    var income: Double = 0
    /// 近 6 個月中位數（ExpenseStore.estimatedMonthlyIncome）
    var median: Double = 0
    var yearToDate: Double = 0
    /// 固定月收（還在領的週期收入換成每月）
    var recurringMonthly: Double = 0
    /// 近 6 個月，一個月一座山（最後一座是這個月）
    var peaks: [MoneyMountainScene.Peak] = []
    /// 下一次固定收入入帳的日子
    var nextPay: Date? = nil
    /// 上個月存下收入的幾成（負的＝花得比收入多）；上個月沒有收入是 nil
    var lastMonthSaving: Double? = nil
    var lastMonthShort: Double = 0

    static func build(store: ExpenseStore, now: Date = Date()) -> IncomeBoardData {
        let cal = Calendar.current
        var d = IncomeBoardData()
        d.year = cal.component(.year, from: now)
        d.month = cal.component(.month, from: now)
        d.income = store.currentMonthIncomeTotal
        d.median = store.estimatedMonthlyIncome
        d.yearToDate = store.yearToDateIncomeTotal
        d.recurringMonthly = store.incomes
            .filter { $0.period != .once && $0.isActive(in: now) }
            .reduce(0) { $0 + $1.monthlyAmount }

        let series = store.heroIncomeSeries()
        d.peaks = series.suffix(6).map {
            MoneyMountainScene.Peak(label: "\(cal.component(.month, from: $0.date))月", value: $0.value)
        }

        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) else { return d }
        let today = cal.startOfDay(for: now)

        // 下次入帳：還在領的固定收入，照起始日的「幾號」（年領的是「幾月幾號」）往後找最近的一天
        for i in store.incomes where i.period != .once && i.monthlyAmount > 0 && i.isActive(in: now) {
            let payDay = cal.component(.day, from: i.date)
            let payMonth = cal.component(.month, from: i.date)
            var candidates: [Date] = []
            for add in 0...1 {
                var comps = DateComponents()
                switch i.period {
                case .monthly:
                    guard let m = cal.date(byAdding: .month, value: add, to: monthStart) else { continue }
                    comps = cal.dateComponents([.year, .month], from: m)
                case .yearly:
                    comps.year = d.year + add
                    comps.month = payMonth
                case .once:
                    continue
                }
                comps.day = 1
                guard let first = cal.date(from: comps) else { continue }
                let days = cal.range(of: .day, in: .month, for: first)?.count ?? 28
                comps.day = min(payDay, days)
                if let date = cal.date(from: comps) { candidates.append(date) }
            }
            let start = cal.startOfDay(for: i.date)
            let end = i.endDate.map { cal.startOfDay(for: $0) }
            guard let next = candidates.filter({ c in
                c >= today && c >= start && (end.map { c <= $0 } ?? true)
            }).min() else { continue }
            if d.nextPay.map({ next < $0 }) ?? true { d.nextPay = next }
        }

        // 上個月存下幾成：上個月的收入 −（變動支出＋固定支出月等值）
        if series.count >= 2, let lastStart = cal.date(byAdding: .month, value: -1, to: monthStart) {
            let lastIncome = series[series.count - 2].value
            if lastIncome > 0 {
                let lastVariable = store.expenses
                    .filter { $0.expenseType == .variable && $0.date >= lastStart && $0.date < monthStart }
                    .reduce(0) { $0 + $1.amount }
                let lastFixed = store.fixedMonthlyTotal(for: monthStart.addingTimeInterval(-1))
                let saved = lastIncome - lastVariable - lastFixed
                d.lastMonthSaving = saved / lastIncome
                d.lastMonthShort = max(0, -saved)
            }
        }
        return d
    }
}

struct IncomeBoard: View {
    let data: IncomeBoardData

    @Environment(\.colorScheme) private var scheme

    private static let payFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d"
        return f
    }()

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let d = data
        let ahead = d.median > d.income
        MoneyBoardCard(
            card: .income,
            header: MoneyBoardHeader(
                date: "\(d.year) 年 \(d.month) 月",
                capsule: d.yearToDate > 0 ? "今年累計 " + MoneyFormat.short(d.yearToDate) : nil,
                capsuleIcon: "sum",
                label: "本月已入帳",
                big: MoneyFormat.short(d.income),
                line: line(pal),
                greeting: ahead || d.income <= 0 ? ["Payday", "ahead!"] : ["Well", "done!"],
                scene: .mountains(MoneyMountainScene(
                    peaks: d.peaks,
                    expected: ahead ? d.median : nil,
                    expectedLabel: ahead ? "預期 " + MoneyFormat.short(d.median) : nil)),
                seed: d.month * 23 + 5),
            content: chips.isEmpty ? nil : AnyView(MoneyBoardChips(chips: chips, pal: pal)))
    }

    private func line(_ pal: TripBoardPalette) -> Text {
        let d = data
        if d.median > d.income {
            return Text("預期 \(MoneyFormat.short(d.median))（近 6 個月中位數）")
        }
        if d.median > 0 {
            let r = d.income / d.median - 1
            if abs(r) < 0.01 { return Text("跟近 6 個月中位數差不多") }
            let pct = MoneyFormat.percent(r)
            return Text("比近 6 個月中位數多 \(Text(pct).fontWeight(.heavy).foregroundStyle(MoneyTone.good.color(pal)))")
        }
        return Text(d.income > 0 ? "這是第一個有收入紀錄的月份" : "記下收入之後，這裡會一個月畫一座山")
    }

    private var chips: [MoneyBoardChip] {
        let d = data
        var out: [MoneyBoardChip] = []
        if d.median > 0 {
            out.append(MoneyBoardChip(icon: "chart.bar.fill", label: "近 6 月中位數", value: MoneyFormat.short(d.median)))
        }
        if d.recurringMonthly > 0 {
            out.append(MoneyBoardChip(icon: "repeat", label: "固定月收", value: MoneyFormat.short(d.recurringMonthly)))
        }
        if let next = d.nextPay {
            let value = Calendar.current.isDateInToday(next) ? "今天" : Self.payFmt.string(from: next)
            out.append(MoneyBoardChip(icon: "calendar.badge.clock", label: "下次入帳", value: value))
        }
        if let rate = d.lastMonthSaving {
            if rate >= 0 {
                out.append(MoneyBoardChip(icon: "leaf.fill", label: "上月存下", value: MoneyFormat.percent(rate),
                                          tone: .good))
            } else {
                out.append(MoneyBoardChip(icon: "exclamationmark.triangle.fill", label: "上月透支",
                                          value: MoneyFormat.short(d.lastMonthShort), tone: .bad))
            }
        }
        return out
    }
}

// MARK: - 固定支出：列車

struct FixedBoardData: Equatable {
    var month = 1
    var day = 1
    var daysInMonth = 30
    /// 本月固定支出（月等值，ExpenseStore.currentMonthFixedTotal）
    var monthly: Double = 0
    /// 拿來算「占收入幾成」的收入（ExpenseStore.budgetBaseIncome）
    var incomeBase: Double = 0
    var dues: [MoneyFixedDue] = []
    var yearly: Double = 0
    var taxMonthly: Double = 0
    var subscriptionCount = 0
    var subscriptionMonthly: Double = 0
    /// 還在繳的貸款，剩下幾期加起來
    var loanLeft: Double = 0
    var hasFixed = false

    var paidCount: Int { dues.filter { $0.day < day }.count }
    var leftCount: Int { dues.count - paidCount }
    var next: [MoneyFixedDue] { MoneyFixedSchedule.next(dues, today: day) }

    static func build(store: ExpenseStore, now: Date = Date()) -> FixedBoardData {
        let cal = Calendar.current
        var d = FixedBoardData()
        d.month = cal.component(.month, from: now)
        d.day = cal.component(.day, from: now)
        d.daysInMonth = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        d.monthly = store.currentMonthFixedTotal
        d.incomeBase = store.budgetBaseIncome
        d.dues = MoneyFixedSchedule.thisMonth(store: store, now: now, calendar: cal)
        d.yearly = yearlyEstimate(store: store, now: now, calendar: cal)
        for e in store.expenses where e.expenseType == .fixed {
            d.hasFixed = true
            guard e.isRecurringFixed, e.isFixedActive(on: now, calendar: cal) else { continue }
            if e.fixedCategory == .subscription {
                d.subscriptionCount += 1
                d.subscriptionMonthly += MoneyFixedSchedule.monthlyNTD(e, store: store)
            }
            if e.effectivelyTaxDeductible {
                d.taxMonthly += MoneyFixedSchedule.monthlyNTD(e, store: store)
            }
            if let s = e.moneyLoanSchedule(now: now, calendar: cal), !s.isDone {
                d.loanLeft += s.left
            }
        }
        return d
    }

    /// 今年一共會扣多少：每一筆照實際的扣款日（Expense.nextFixedDueDate）數今年有幾期。
    ///
    /// 原本的算法（FixedExpenseView.occurrencesThisYear）只看起始日與週期：已經停止的項目
    /// （繳清的貸款、取消的訂閱）照樣算滿一整年，去年那一筆單次的固定支出也會算進今年。
    /// 這裡照扣款日一期一期數：結束日之後的不算、單次的只算日期在今年的。
    static func yearlyEstimate(store: ExpenseStore, now: Date = Date(),
                               calendar cal: Calendar = .current) -> Double {
        let year = cal.component(.year, from: now)
        guard let yearStart = cal.date(from: DateComponents(year: year, month: 1, day: 1)),
              let nextYear = cal.date(byAdding: .year, value: 1, to: yearStart) else { return 0 }
        var total = 0.0
        for e in store.expenses where e.expenseType == .fixed {
            let ntd = store.ntdValue(of: e)
            guard e.isRecurringFixed else {
                if e.date >= yearStart && e.date < nextYear { total += ntd }
                continue
            }
            var from = yearStart
            var n = 0
            while n < 60, let due = e.nextFixedDueDate(onOrAfter: from, calendar: cal), due < nextYear {
                n += 1
                guard let after = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: due)) else { break }
                from = after
            }
            total += ntd * Double(n)
        }
        return total
    }
}

struct FixedBoard: View {
    let data: FixedBoardData

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let d = data
        let next = d.next
        var nextTitle: String? = nil
        var nextDetail: String? = nil
        if let first = next.first {
            nextTitle = "下一站・" + MoneyFixedSchedule.when(day: first.day, today: d.day, month: d.month)
            let sum = next.reduce(0) { $0 + $1.amount }
            nextDetail = (next.count == 1 ? MoneyBoardText.short(first.title) : "\(next.count) 筆") + " "
                + MoneyFormat.short(sum)
        }
        return MoneyBoardCard(
            card: .fixedExpense,
            header: MoneyBoardHeader(
                date: d.dues.isEmpty ? "\(d.month) 月" : "\(d.month) 月・\(d.dues.count) 筆扣款",
                capsule: d.incomeBase > 0 && d.monthly > 0
                    ? "占收入 " + MoneyFormat.percent(d.monthly / d.incomeBase) : nil,
                capsuleIcon: "chart.pie.fill",
                label: "每月固定支出",
                big: MoneyFormat.short(d.monthly),
                line: line(pal),
                greeting: ["All", "aboard!"],
                scene: .railway(MoneyRailScene(
                    month: d.month, daysInMonth: d.daysInMonth, today: d.day,
                    stations: MoneyFixedSchedule.stations(d.dues, today: d.day),
                    nextTitle: nextTitle, nextDetail: nextDetail)),
                seed: d.month * 17 + 9),
            content: chips.isEmpty ? nil : AnyView(MoneyBoardChips(chips: chips, pal: pal)))
    }

    private func line(_ pal: TripBoardPalette) -> Text {
        let d = data
        if d.dues.isEmpty {
            return Text(d.hasFixed ? "這個月沒有要扣款的項目" : "新增房租、訂閱、保險之後，這裡會排出每一筆扣款的車站")
        }
        if d.leftCount == 0 {
            return Text("這個月的 \(d.dues.count) 筆都扣完了")
        }
        if d.paidCount == 0 {
            return Text("這個月還有 \(d.leftCount) 筆要扣")
        }
        return Text("已扣 \(d.paidCount) 筆、還有 \(d.leftCount) 筆")
    }

    private var chips: [MoneyBoardChip] {
        let d = data
        var out: [MoneyBoardChip] = []
        let next = d.next
        if let first = next.first {
            let when = MoneyFixedSchedule.when(day: first.day, today: d.day, month: d.month)
            let what = next.count == 1 ? MoneyBoardText.short(first.title) : "\(next.count) 筆"
            let sum = next.reduce(0) { $0 + $1.amount }
            out.append(MoneyBoardChip(icon: "tram.fill", label: "下一站",
                                      value: when + " " + what + " " + MoneyFormat.short(sum),
                                      tone: first.day - d.day <= 1 ? .warn : .neutral))
        }
        if d.yearly > 0 {
            out.append(MoneyBoardChip(icon: "calendar", label: "年度預估", value: MoneyFormat.short(d.yearly)))
        }
        if d.subscriptionCount > 0 {
            out.append(MoneyBoardChip(icon: "play.rectangle.fill", label: "訂閱 \(d.subscriptionCount) 個",
                                      value: "每月 " + MoneyFormat.short(d.subscriptionMonthly)))
        }
        if d.loanLeft > 0 {
            out.append(MoneyBoardChip(icon: "building.columns.fill", label: "貸款還要繳",
                                      value: MoneyFormat.short(d.loanLeft)))
        }
        if d.taxMonthly > 0 {
            out.append(MoneyBoardChip(icon: "leaf.fill", label: "節稅", value: "每月 " + MoneyFormat.short(d.taxMonthly),
                                      tone: .good))
        }
        return out
    }
}
