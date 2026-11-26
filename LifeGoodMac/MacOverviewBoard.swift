// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.648 mac7 G2] 總覽看板的資料與字（judge_mac.md §U3-2 ①～⑮；只 import Foundation，不碰 Color、不寫任何東西）。
//
// • 每支照抄 iOS（d070244）：OverviewBoard.swift（OB）、OverviewView.swift（OV）、MoneyBoardKit.swift（MBK）、MoneyBoards.swift（MBS）；
//   上一行寫「照抄 檔:行（d070244）」；一律照 iOS、不修 iPhone 的怪規則（§U3-2 最後一段）；sim 編號 ov7#N。
// • 全部收 now:、calendar:；頁面一次算完傳同一個 now、Calendar.current。金額字一律 MacText.short、百分比 WidgetMoneyFormat.percent。
// • 主控骨架（C0）：型別、欄位、推導（② 已照抄 OB:38-99）與簽名定案（§U7-6，組內不准改）；build 回空的、categoryStats 回 []、
//   字回 ""／nil。G2 換內容。

import Foundation

// MARK: - ① 未來幾天要扣的一筆固定支出

// 照抄 OverviewBoard.swift:28-36（d070244）OverviewUpcomingBill（名字）— sim7: ov7#1
struct MacOverviewBill: Identifiable, Equatable {
    let id: UUID
    let title: String
    let icon: String
    let amount: Double
    let date: Date
    /// 0＝今天、1＝明天…
    let daysAway: Int
}

// MARK: - ② 看板的資料

// 照抄 OverviewBoard.swift:38-99（d070244）OverviewBoardData（dues: [MoneyFixedDue] → [MacFixedDue]、upcoming → [MacOverviewBill]）— sim7: ov7#2
struct MacOverviewBoardData: Equatable {
    var month = 1
    var day = 1
    var daysInMonth = 30
    /// 本月已入帳
    var income: Double = 0
    /// 近 6 個月收入中位數（MacMoneyStore.estimatedMonthlyIncome）
    var incomeMedian: Double = 0
    /// 拿來算「還能花」的收入：本月已入帳與近 6 個月中位數取大
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
    /// 本月 1 號到今天，每天的變動支出
    var daily: [Double] = []
    /// 這個月從哪一天開始有記帳
    var firstDay = 1
    /// 這個月每一筆固定支出的扣款日
    var dues: [MacFixedDue] = []
    var upcoming: [MacOverviewBill] = []

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

    /// 剩下的日子每天大概花多少：有前 3 個月的紀錄就用那個（「平常的花法」），沒有才用這個月到目前的日均
    var typicalDaily: Double { prev3DailyAvg ?? variableDailyAvg }
    var usesTypicalDaily: Bool { prev3DailyAvg != nil }
    /// 月底預估的總支出＝已經花的＋剩下的日子照平常的花法
    var projectedSpending: Double { spending + typicalDaily * Double(max(0, daysInMonth - day)) }

    /// 日預算：收入扣掉固定支出，平均到這個月的每一天；固定支出就超過收入、或沒有收入紀錄時不畫
    var dailyBudget: Double? {
        guard hasBase, base > fixed else { return nil }
        return (base - fixed) / Double(max(daysInMonth, 1))
    }
}

// MARK: - ③ 一次算完

extension MacOverviewBoardData {
    // 照抄 OverviewBoard.swift:101-186（d070244）OverviewBoardData.build（替換表見 judge_mac.md §U3-2 ③）— sim7: ov7#3
    // （刪 let cal = Calendar.current；store. → money.、三個 computed 換成收 now:、calendar: 的同名函式；
    //   MoneyFixedSchedule.thisMonth → MacFixedSchedule.thisMonth；Mac 補：upcoming 同時間照 amount 大到小、再照 id，L7-4）
    // body 裡叫（MacOverviewPage 一次算完傳同一個 now、cal）：只讀 money，不寫任何東西。
    @MainActor
    static func build(money: MacMoneyStore, now: Date, calendar cal: Calendar) -> MacOverviewBoardData {
        var d = MacOverviewBoardData()
        d.month = cal.component(.month, from: now)
        d.day = cal.component(.day, from: now)
        d.daysInMonth = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        d.income = money.currentMonthIncomeTotal(now: now, calendar: cal)
        d.incomeMedian = money.estimatedMonthlyIncome(now: now, calendar: cal)
        d.base = max(d.income, d.incomeMedian)
        d.baseIsEstimate = d.incomeMedian > d.income
        d.fixed = money.currentMonthFixedTotal(now: now, calendar: cal)

        let today = cal.startOfDay(for: now)
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) else {
            return d
        }
        let variables = money.expenses.filter { $0.expenseType == .variable }

        // 本月每天的變動支出（iOS 原樣：本月以後日期的也算進 variable，daily 只留到今天；L7-13）
        var daily = Array(repeating: 0.0, count: d.daysInMonth)
        for e in variables where cal.isDate(e.date, equalTo: now, toGranularity: .month) {
            d.variable += money.ownAmount(e)
            if cal.isDate(e.date, inSameDayAs: now) { d.todayCount += 1 }
            let i = cal.component(.day, from: e.date) - 1
            if daily.indices.contains(i) { daily[i] += money.ownAmount(e) }
        }
        if daily.indices.contains(d.day - 1) { d.todayVariable = daily[d.day - 1] }
        d.daily = Array(daily.prefix(d.day))

        // 從哪一天開始記帳：最早一筆變動支出在這個月就從那天起；更早就從 1 號；一筆都沒有＝今天＋1
        if let first = variables.map(\.date).min() {
            d.firstDay = first < monthStart ? 1 : cal.component(.day, from: first)
        } else {
            d.firstDay = d.day + 1
        }

        d.dues = MacFixedSchedule.thisMonth(money: money, now: now, calendar: cal)

        // 上個月到同一天為止：變動支出照實算，固定支出用上個月那時候的月等值
        if let lastStart = cal.date(byAdding: .month, value: -1, to: monthStart) {
            let lastDays = cal.range(of: .day, in: .month, for: lastStart)?.count ?? 30
            let cutDay = min(d.day, lastDays)
            if let cutoff = cal.date(byAdding: .day, value: cutDay, to: lastStart) {
                let lv = variables.filter { $0.date >= lastStart && $0.date < cutoff }
                    .reduce(0) { $0 + money.ownAmount($1) }
                let sameDayLastMonth = cal.date(byAdding: .month, value: -1, to: now) ?? lastStart
                let lf = money.fixedMonthlyTotal(for: sameDayLastMonth, calendar: cal)
                let total = lv + lf
                d.lastMonthSameDay = total > 0 ? total : nil
            }
        }

        // 近 3 個月的變動日均（那個月有花錢才算進來）
        var prevSum = 0.0
        var prevDays = 0
        for back in 1...3 {
            guard let m = cal.date(byAdding: .month, value: -back, to: monthStart),
                  let next = cal.date(byAdding: .month, value: 1, to: m) else { continue }
            let t = variables.filter { $0.date >= m && $0.date < next }.reduce(0) { $0 + money.ownAmount($1) }
            if t > 0 {
                prevSum += t
                prevDays += cal.range(of: .day, in: .month, for: m)?.count ?? 30
            }
        }
        d.prev3DailyAvg = prevDays > 0 ? prevSum / Double(prevDays) : nil

        // 未來 7 天要扣的固定支出（今天要扣的也算、第 7 天不算）
        let horizon = cal.date(byAdding: .day, value: 7, to: today) ?? today
        var bills: [MacOverviewBill] = []
        for e in money.expenses where e.isRecurringFixed {
            guard let due = e.nextFixedDueDate(onOrAfter: today, calendar: cal), due < horizon else {
                continue
            }
            let away = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: due)).day ?? 0
            bills.append(MacOverviewBill(id: e.id,
                                         title: e.stopRowLabel(suppressing: []).primary,
                                         icon: e.categoryIcon,
                                         amount: money.ntdValue(of: e),
                                         date: due,
                                         daysAway: max(0, away)))
        }
        // Mac 補（L7-4）：iOS 的 sorted 不穩定，同一個時間照 amount 大到小、再照 id 字串
        d.upcoming = bills.sorted { a, b in
            if a.date != b.date { return a.date < b.date }
            if a.amount != b.amount { return a.amount > b.amount }
            return a.id.uuidString < b.id.uuidString
        }
        return d
    }
}

// MARK: - ④ 本月花在哪裡

// 照抄 OverviewView.swift:179-186（d070244）CategoryStat
struct MacOverviewCategoryStat: Identifiable, Equatable {
    let category: VariableCategory
    let amount: Double
    let count: Int
    /// 上個月到同一天為止
    let lastMonth: Double
    var id: String { category.rawValue }
}

enum MacOverviewStats {
    // 照抄 OverviewView.swift:188-212（d070244）buildCategoryStats（store → money、Calendar.current → 參數）— sim7: ov7#4
    // 沒分類的算 .other（case，不寫字面值）；本月 vs 上月到同一天；0 不列；金額大到小、同額照 rawValue
    @MainActor
    static func categoryStats(money: MacMoneyStore, now: Date, calendar cal: Calendar) -> [MacOverviewCategoryStat] {
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)),
              let lastStart = cal.date(byAdding: .month, value: -1, to: monthStart) else { return [] }
        let day = cal.component(.day, from: now)
        let lastDays = cal.range(of: .day, in: .month, for: lastStart)?.count ?? 30
        let lastCut = cal.date(byAdding: .day, value: min(day, lastDays), to: lastStart) ?? monthStart
        var amount: [VariableCategory: Double] = [:]
        var count: [VariableCategory: Int] = [:]
        var last: [VariableCategory: Double] = [:]
        for e in money.expenses where e.expenseType == .variable {
            let c = e.variableCategory ?? .other
            if cal.isDate(e.date, equalTo: now, toGranularity: .month) {
                amount[c, default: 0] += money.ownAmount(e)
                count[c, default: 0] += 1
            } else if e.date >= lastStart && e.date < lastCut {
                last[c, default: 0] += money.ownAmount(e)
            }
        }
        return amount
            .map { MacOverviewCategoryStat(category: $0.key, amount: $0.value, count: count[$0.key] ?? 0,
                                lastMonth: last[$0.key] ?? 0) }
            .filter { $0.amount > 0 }
            .sorted { a, b in a.amount != b.amount ? a.amount > b.amount : a.id < b.id }
    }
}

// MARK: - ⑤ 語氣（畫面那邊對到 MacTone；這檔不碰 Color）

// 照抄 MoneyBoardKit.swift:48（d070244）MoneyTone 的前四種（Mac 新名字）— sim7: ov7#5
enum MacOverviewTone: Equatable {
    case good, warn, bad, neutral
}

// MARK: - ⑨ ⑫ ⑭ 畫面要的字與格子

/// ⑨ 看板頭部（OB:210-240）
struct MacOverviewHead: Equatable {
    /// 「11 月・第 26 天／共 30 天」
    let date: String
    /// 「已花 79%」（沒有收入＝nil）
    let capsule: String?
    /// 「本月支出」「本月還能花」「本月已超支」
    let label: String
    let big: String
    /// 超支＝.bad；其餘 nil（ink）
    let bigTone: MacOverviewTone?
    /// 「Have a nice November!」
    let greeting: String
}

/// ⑫ 四格的一格（OB:347-419）
struct MacOverviewTileText: Identifiable, Equatable {
    let label: String
    let icon: String
    let value: String
    let valueTone: MacOverviewTone?
    let detail: String?
    let accent: String?
    let accentTone: MacOverviewTone
    /// 點了切到哪一頁（收入 .income、支出與今天 .variable、每天還能花 nil）
    let target: MacPage?

    var id: String { label }
}

/// ⑭ 每日長條那天的站牌（stations 對到那天；沒有扣款＝.none）
enum MacOverviewStation: Equatable {
    case none, past, next, later
}

/// ⑭ 每日長條的一天（Mac 自己的；1…daysInMonth 每天一根）
struct MacOverviewDay: Identifiable, Equatable {
    let day: Int
    /// "\(day)"
    let label: String
    /// d.daily[day − 1]（今天以後 0）
    let amount: Double
    /// dailyBudget.map { min(amount, $0) } ?? amount
    let under: Double
    /// max(0, amount − (dailyBudget ?? amount))
    let over: Double
    let station: MacOverviewStation
    let isToday: Bool

    var id: Int { day }
}

// MARK: - ⑥ ⑦ ⑧ ⑨～⑮ 字

enum MacOverviewBoardText {
    // ⑥ 照抄 MoneyBoardKit.swift:36-41（d070244）MoneyFormat.change（percent → WidgetMoneyFormat.percent）— sim7: ov7#6
    /// 「↑12%」「↓8%」；差不到 1% 就說「持平」
    static func change(_ now: Double, vs before: Double) -> String? {
        guard before > 0 else { return nil }
        let r = now / before - 1
        if abs(r) < 0.01 { return "持平" }
        return (r > 0 ? "↑" : "↓") + WidgetMoneyFormat.percent(abs(r))
    }

    // ⑥ 照抄 MoneyBoardKit.swift:72-77（d070244）MoneyTone.spendingChange（MoneyTone → MacOverviewTone）— sim7: ov7#6
    /// 花得比較多是「注意」、比較少是「好」；差不到 5% 不上色（沒有 .bad：比較不用紅）
    static func spendingTone(_ now: Double, vs before: Double) -> MacOverviewTone {
        guard before > 0 else { return .neutral }
        if now > before * 1.05 { return .warn }
        if now < before * 0.95 { return .good }
        return .neutral
    }

    // ⑦ 照抄 MoneyBoards.swift:100-101（d070244）MoneyBoardText.months（逐字）— sim7: ov7#7
    private static let months = ["January", "February", "March", "April", "May", "June", "July",
                                 "August", "September", "October", "November", "December"]

    // ⑦ 照抄 MoneyBoards.swift:104-106（d070244）MoneyBoardText.month — sim7: ov7#7
    /// 手寫問候用的英文月份（「Have a nice November!」）
    static func month(_ m: Int) -> String {
        months[min(12, max(1, m)) - 1]
    }

    // ⑦ 照抄 MoneyBoards.swift:109-111（d070244）MoneyBoardText.short — sim7: ov7#7
    /// 膠囊、牌子上的名字：太長就截掉
    static func short(_ s: String, max n: Int = 8) -> String {
        s.count > n ? String(s.prefix(n - 1)) + "…" : s
    }

    // ⑧ 照抄 MoneyBoards.swift:165-170（d070244）MoneyFixedSchedule.label(next(dues, today:), today:, month:)
    //   （next／when 叫 MacFixedSchedule :75、:82；MoneyBoardText.short → short）— sim7: ov7#8
    /// 「明天扣 壽險」「11/28 扣 3 筆」；這個月沒有下一站＝nil
    static func nextLabel(_ d: MacOverviewBoardData) -> String? {
        let next = MacFixedSchedule.next(d.dues, today: d.day)
        guard let first = next.first else { return nil }
        let w = MacFixedSchedule.when(day: first.day, today: d.day, month: d.month)
        let what = next.count == 1 ? short(first.title) : "\(next.count) 筆"
        return w + (w.contains("/") ? " 扣 " : "扣 ") + what
    }

    // ⑨ 照抄 OverviewBoard.swift:229（d070244）header 的 capsule 值（MoneyFormat.percent → WidgetMoneyFormat.percent）— sim7: ov7#9
    /// 膠囊的「79%」（沒有收入＝nil；畫面寫 MacPill(label: "已花", value:)）
    static func spentShare(_ d: MacOverviewBoardData) -> String? {
        d.hasBase ? WidgetMoneyFormat.percent(d.spending / d.base) : nil
    }

    // ⑨ 照抄 OverviewBoard.swift:210-240（d070244）header（MoneyFormat.short → MacText.short）— sim7: ov7#9
    static func header(_ d: MacOverviewBoardData) -> MacOverviewHead {
        let title: String
        let big: String
        let bigTone: MacOverviewTone?
        if !d.hasBase {
            title = "本月支出"
            big = MacText.short(d.spending)
            bigTone = nil
        } else if d.left >= 0 {
            title = "本月還能花"
            big = MacText.short(d.left)
            bigTone = nil
        } else {
            title = "本月已超支"
            big = MacText.short(-d.left)
            bigTone = .bad
        }
        return MacOverviewHead(date: "\(d.month) 月・第 \(d.day) 天／共 \(d.daysInMonth) 天",
                               capsule: spentShare(d).map { "已花 " + $0 },
                               label: title,
                               big: big,
                               bigTone: bigTone,
                               greeting: "Have a nice " + month(d.month) + "!")
    }

    // ⑩ 照抄 OverviewBoard.swift:242-266（d070244）verdict（Text → 三段字；neutral 時畫面用 ink）— sim7: ov7#10
    /// 頭部那一句：照平常的花法，月底可以存多少／會超出多少
    static func verdict(_ d: MacOverviewBoardData) -> (lead: String, amount: String, tone: MacOverviewTone) {
        let projected = d.projectedSpending
        let how = d.usesTypicalDaily ? "照平常的花法" : "照這個月的速度"
        if !d.hasBase {
            return (how + "，月底大約花", MacText.short(projected), .neutral)
        } else if d.left < 0 {
            return ("已經超出收入", MacText.short(-d.left), .bad)
        } else if projected > d.base {
            return (how + "，月底會超出", MacText.short(projected - d.base), .warn)
        }
        return (how + "，月底可以存", MacText.short(d.base - projected), .good)
    }

    // ⑪ 照抄 OverviewBoard.swift:290-292（d070244）moneyCell 的 trailing 字 — sim7: ov7#11
    static func moneyTrailing(_ d: MacOverviewBoardData) -> String {
        d.hasBase
            ? "收入 " + MacText.short(d.base) + (d.baseIsEstimate ? "・預估" : "")
            : "還沒有收入紀錄"
    }

    // ⑪ 照抄 OverviewBoard.swift:288-289、:319-327（d070244）legend 的字與 over 判斷 — sim7: ov7#11
    /// over＝照這樣花月底會超出收入（圖例「月底約」那格換 warn 色）
    static func legend(_ d: MacOverviewBoardData) -> (fixed: String, variable: String, month: String, over: Bool) {
        let projected = d.projectedSpending
        let over = d.hasBase && projected > d.base
        return ("固定 " + MacText.short(d.fixed), "變動 " + MacText.short(d.variable), "月底約 " + MacText.short(projected), over)
    }

    // ⑫ 照抄 OverviewBoard.swift:347-419（d070244）四格（action → target；tint 由畫面照 icon 對主題色）— sim7: ov7#12
    static func tiles(_ d: MacOverviewBoardData) -> [MacOverviewTileText] {
        // 本月收入（OB:347-364）
        let incomeDetail: String
        if d.baseIsEstimate {
            incomeDetail = "預期 " + MacText.short(d.base)
        } else if d.incomeMedian > 0 {
            incomeDetail = "近 6 月中位數 " + MacText.short(d.incomeMedian)
        } else {
            incomeDetail = d.income > 0 ? "本月已入帳" : "還沒有紀錄"
        }
        let income = MacOverviewTileText(label: "本月收入", icon: "banknote.fill", value: MacText.short(d.income),
                                         valueTone: nil, detail: incomeDetail, accent: nil, accentTone: .neutral,
                                         target: .income)
        // 本月支出（OB:366-381）
        var spendDetail = "固定＋變動"
        var spendAccent: String? = nil
        var spendTone: MacOverviewTone = .neutral
        if let last = d.lastMonthSameDay, let ch = change(d.spending, vs: last) {
            spendDetail = "比上月同期"
            spendAccent = ch
            spendTone = spendingTone(d.spending, vs: last)
        }
        let spending = MacOverviewTileText(label: "本月支出", icon: "cart.fill", value: MacText.short(d.spending),
                                           valueTone: nil, detail: spendDetail, accent: spendAccent, accentTone: spendTone,
                                           target: .variable)
        // 每天還能花（OB:383-404）
        let allowValue: String
        let allowTone: MacOverviewTone?
        let allowDetail: String
        if !d.hasBase {
            allowValue = "—"
            allowTone = nil
            allowDetail = "需要收入紀錄"
        } else if d.allowancePerDay >= 0 {
            allowValue = MacText.short(d.allowancePerDay)
            allowTone = nil
            allowDetail = "還有 \(d.remainingDays) 天"
        } else {
            allowValue = "已超支"
            allowTone = .bad
            allowDetail = "還有 \(d.remainingDays) 天"
        }
        let allowance = MacOverviewTileText(label: "每天還能花", icon: "wallet.pass.fill", value: allowValue,
                                            valueTone: allowTone, detail: allowDetail, accent: nil, accentTone: .neutral,
                                            target: nil)
        // 今天花了（OB:406-418；只算今天的變動支出，L7-2）
        let today = MacOverviewTileText(label: "今天花了", icon: "calendar", value: MacText.short(d.todayVariable),
                                        valueTone: nil, detail: d.todayCount > 0 ? "\(d.todayCount) 筆" : nil,
                                        accent: d.todayCount > 0 ? nil : "還沒花錢", accentTone: .good,
                                        target: .variable)
        return [income, spending, allowance, today]
    }

    // ⑬ 照抄 OverviewBoard.swift:580-585（d070244）row 的 when — sim7: ov7#13
    /// 「今天扣款」「明天扣款」「11/28 (週五)・2 天後」
    static func when(_ b: MacOverviewBill) -> String {
        switch b.daysAway {
        case 0: return "今天扣款"
        case 1: return "明天扣款"
        default: return dueFormatter.string(from: b.date) + "・\(b.daysAway) 天後"
        }
    }

    // ⑬ 照抄 OverviewBoard.swift:586（d070244）soon — sim7: ov7#13
    static func soon(_ b: MacOverviewBill) -> Bool {
        b.daysAway <= 1
    }

    // ⑬ 照抄 OverviewBoard.swift:515-520（d070244）dueFmt — sim7: ov7#13
    static let dueFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d (E)"
        return f
    }()

    // ⑬ 照抄 OverviewBoard.swift:540（d070244）未來 7 天標頭右邊的字（MoneyFormat.short → MacText.short）— sim7: ov7#13
    /// 「3 筆・NT$2,960」
    static func upcomingCount(_ bills: [MacOverviewBill]) -> String {
        let total: Double = bills.reduce(0) { $0 + $1.amount }
        return "\(bills.count) 筆・" + MacText.short(total)
    }

    // ⑭ Mac 新：每日長條（1…daysInMonth 每天一根；amount＝d.daily[day − 1]、今天以後 0；
    //   under＋over＝amount、有日預算時 under ≤ 日預算；站牌照 MacFixedSchedule.stations 對到那天，沒有扣款＝.none）— sim7: ov7#14
    static func daily(_ d: MacOverviewBoardData) -> [MacOverviewDay] {
        let stations = MacFixedSchedule.stations(d.dues, today: d.day)
        var out: [MacOverviewDay] = []
        for day in 1...max(d.daysInMonth, 1) {
            let amount: Double = d.daily.indices.contains(day - 1) ? d.daily[day - 1] : 0
            let under: Double = d.dailyBudget.map { min(amount, $0) } ?? amount
            let over: Double = max(0, amount - (d.dailyBudget ?? amount))
            var station: MacOverviewStation = .none
            if let s = stations.first(where: { $0.day == day }) {
                station = s.past ? .past : (s.isNext ? .next : .later)
            }
            out.append(MacOverviewDay(day: day, label: "\(day)", amount: amount, under: under, over: over,
                                      station: station, isToday: day == d.day))
        }
        return out
    }

    // ⑭ Mac 新：X 軸要標的日子（1、5、10、15、20、25、最後一天、今天；照 MacChartGraph.swift:63-67 的 visible）— sim7: ov7#14
    static func axisDays(_ d: MacOverviewBoardData) -> [String] {
        let n = max(d.daysInMonth, 1)
        let picks = Set([1, 5, 10, 15, 20, 25, n, d.day].filter { $0 >= 1 && $0 <= n })
        return picks.sorted().map { "\($0)" }
    }

    // ⑭ Mac 新：每日長條整張一個 VoiceOver 元素的字 — sim7: ov7#14
    /// 「每天花多少：今天 NT$500，日預算 NT$1,087」
    static func dailySummary(_ d: MacOverviewBoardData) -> String {
        "每天花多少：今天 " + MacText.short(d.todayVariable) + (budgetText(d).map { "，" + $0 } ?? "")
    }

    // ⑮ 照抄 OverviewBoard.swift:278（d070244）budgetLabel（MoneyFormat.short → MacText.short）— sim7: ov7#15
    /// 「日預算 NT$1,087」（固定支出就超過收入、或沒有收入紀錄＝nil）
    static func budgetText(_ d: MacOverviewBoardData) -> String? {
        d.dailyBudget.map { "日預算 " + MacText.short($0) }
    }

    // ④ 照抄 OverviewView.swift:218（d070244）分類區標頭右邊的字（ntdWanString → MacText.short）— sim7: ov7#16
    /// 「6 類・NT$2.2萬」；沒有分類＝nil
    static func categoryCount(_ stats: [MacOverviewCategoryStat]) -> String? {
        let total: Double = stats.reduce(0) { $0 + $1.amount }
        return stats.isEmpty ? nil : "\(stats.count) 類・" + MacText.short(total)
    }

    // ④ 照抄 OverviewView.swift:246-249（d070244）明信片的占比（total > 0 才算）＋MoneyItemCard.swift:705-708 的筆數 — sim7: ov7#16
    /// 「40%・32 筆」
    static func categoryShare(_ s: MacOverviewCategoryStat, total: Double) -> String {
        WidgetMoneyFormat.percent(total > 0 ? s.amount / total : 0) + "・\(s.count) 筆"
    }

    // ④ 照抄 OverviewView.swift:250-251（d070244）change：lastMonth > 0 才有（色＝spendingTone：warn 橘、good 綠、neutral label，不用紅）— sim7: ov7#16
    /// 「↑8%」「持平」
    static func categoryChange(_ s: MacOverviewCategoryStat) -> String? {
        s.lastMonth > 0 ? change(s.amount, vs: s.lastMonth) : nil
    }
}
