// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.644 mac4 G2] 固定支出頁的資料（judge_mac §R7 ①～⑬；只 import Foundation）。
//
// • ②④⑤ 照抄 iOS（f2c8892）一個 token 都不改（keycheck 照抄比對；只准 store.→money.、MoneyFixedSchedule.→MacFixedSchedule.）；
//   ①③⑥⑦⑧⑨⑩⑪⑫⑬ iOS 回的是 View 或 Mac 有補的規則：照字面值＋sim_mac4.py 行為寫（board4#、head4#、table4#、rail4#、trend4#）。
// • 全部收 now:、calendar:；看板一次算完（同一個 now、Calendar.current），body 只排版、不寫 store。
// • 列（MacFixedRow）全 let，顯示字建列時算好；排序自己寫（KeyPathComparator.compare 一個一個比），同值照 id。
// • 停止一律叫 macIsFixedEnded(now:calendar:)（共用那支寫死 Date()，不叫）。這個檔不寫 store、不碰 records。
import Foundation

// MARK: - 這個月的扣款日

/// 這個月的一筆週期性固定支出：哪一天扣、扣什麼、多少（Mac 多帶 id：同天同額照 id 排）
struct MacFixedDue: Equatable {
    let id: UUID
    let day: Int
    let title: String
    let amount: Double
}

/// 時間軸的一站（一天一站；同一天扣好幾筆也是一站）
struct MacFixedRailStation: Identifiable, Equatable {
    let day: Int
    let past: Bool
    let isNext: Bool

    var id: Int { day }
}

/// 時間軸 1 號到月底的一格（沒扣款的那天 station＝nil、help＝""）
struct MacFixedRailDay: Identifiable {
    let day: Int
    let station: MacFixedRailStation?
    let isToday: Bool
    /// 滑鼠停在格子上的字：那天每筆一行「11/25 測試房貸 NT$28,000」
    let help: String

    var id: Int { day }
}

enum MacFixedSchedule {
    // 照抄 MoneyBoards.swift:125-140（f2c8892）MoneyFixedSchedule.thisMonth — sim4: board4#3
    // （store → money、MoneyItem.title → MacVariableText.title；同一天金額大的先，Mac 補：同額照 id）
    @MainActor
    static func thisMonth(money: MacMoneyStore, now: Date, calendar cal: Calendar) -> [MacFixedDue] {
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)),
              let nextMonth = cal.date(byAdding: .month, value: 1, to: monthStart) else { return [] }
        var out: [MacFixedDue] = []
        for e in money.expenses where e.isRecurringFixed {
            guard let due = e.nextFixedDueDate(onOrAfter: monthStart, calendar: cal), due < nextMonth else {
                continue
            }
            out.append(MacFixedDue(id: e.id,
                                   day: cal.component(.day, from: due),
                                   title: MacVariableText.title(e),
                                   amount: money.ntdValue(of: e)))
        }
        return out.sorted { a, b in
            if a.day != b.day { return a.day < b.day }
            if a.amount != b.amount { return a.amount > b.amount }
            return a.id.uuidString < b.id.uuidString
        }
    }

    // 照抄 MoneyBoards.swift:142-147（f2c8892）stations — sim4: board4#4
    /// 一天一站；今天以前的是扣過的，今天或之後最近的那一站是下一站
    static func stations(_ dues: [MacFixedDue], today: Int) -> [MacFixedRailStation] {
        let days = Set(dues.map(\.day)).sorted()
        let next = days.first { $0 >= today }
        return days.map { MacFixedRailStation(day: $0, past: $0 < today, isNext: $0 == next) }
    }

    // 照抄 MoneyBoards.swift:149-153（f2c8892）next
    /// 下一站要扣的那幾筆
    static func next(_ dues: [MacFixedDue], today: Int) -> [MacFixedDue] {
        guard let day = dues.map(\.day).filter({ $0 >= today }).min() else { return [] }
        return dues.filter { $0.day == day }
    }

    // 照抄 MoneyBoards.swift:155-162（f2c8892）when
    /// 「今天」「明天」「10/12」
    static func when(day: Int, today: Int, month: Int) -> String {
        switch day - today {
        case 0: return "今天"
        case 1: return "明天"
        default: return "\(month)/\(day)"
        }
    }

    // 照抄 MoneyBoards.swift:173-181（f2c8892）monthlyNTD — sim4: board4#5
    /// 月均（NT$ 等值）：季繳 ÷ 3、年繳 ÷ 12；外幣儲蓄險先換成 NT$
    @MainActor
    static func monthlyNTD(_ e: Expense, money: MacMoneyStore) -> Double {
        let ntd = money.ntdValue(of: e)
        switch e.recurrence {
        case .monthly, .none: return ntd
        case .quarterly: return ntd / 3
        case .yearly: return ntd / 12
        }
    }

    // sim4: rail4#1　有扣款那格的字：那天每筆一行「11/25 測試房貸 NT$28,000」（沒扣款＝""）
    static func railHelp(_ dues: [MacFixedDue], day: Int, month: Int) -> String {
        var lines: [String] = []
        for u in dues where u.day == day {
            lines.append("\(month)/\(day) " + u.title + " " + MacText.money(u.amount))
        }
        return lines.joined(separator: "\n")
    }

    /// 時間軸 1 號到月底每天一格（今天沒扣款也有一格，畫旗）
    static func railDays(_ d: MacFixedBoardData) -> [MacFixedRailDay] {
        var byDay: [Int: MacFixedRailStation] = [:]
        for s in stations(d.dues, today: d.day) {
            byDay[s.day] = s
        }
        let last = max(1, d.daysInMonth)
        return (1...last).map { (n: Int) -> MacFixedRailDay in
            MacFixedRailDay(day: n, station: byDay[n], isToday: n == d.day,
                            help: railHelp(d.dues, day: n, month: d.month))
        }
    }

    /// 時間軸整條一個 VoiceOver 元素：「扣款時間軸：這個月 3 筆扣款，下一站 11/26」
    static func railLabel(_ d: MacFixedBoardData) -> String {
        var text = "扣款時間軸：這個月 \(d.dues.count) 筆扣款"
        if let first = d.next.first {
            text += "，下一站 \(d.month)/\(first.day)"
        }
        return text
    }
}

// MARK: - 看板的數字

// 照抄 MoneyBoards.swift:517-566（f2c8892）FixedBoardData — sim4: board4#1
// （monthly＝currentMonthFixedTotal、incomeBase＝budgetBaseIncome 都傳同一個 now；moneyLoanSchedule → macLoanSchedule）
struct MacFixedBoardData {
    var month = 1
    var day = 1
    var daysInMonth = 30
    /// 本月固定支出（月等值，MacMoneyStore.currentMonthFixedTotal）
    var monthly: Double = 0
    /// 拿來算「占收入幾成」的收入（MacMoneyStore.budgetBaseIncome）
    var incomeBase: Double = 0
    var dues: [MacFixedDue] = []
    var yearly: Double = 0
    var taxMonthly: Double = 0
    var subscriptionCount = 0
    var subscriptionMonthly: Double = 0
    /// 還在繳的貸款，剩下幾期加起來
    var loanLeft: Double = 0
    var hasFixed = false

    var paidCount: Int { dues.filter { $0.day < day }.count }
    var leftCount: Int { dues.count - paidCount }
    var next: [MacFixedDue] { MacFixedSchedule.next(dues, today: day) }

    @MainActor
    static func build(money: MacMoneyStore, now: Date, calendar cal: Calendar) -> MacFixedBoardData {
        var d = MacFixedBoardData()
        d.month = cal.component(.month, from: now)
        d.day = cal.component(.day, from: now)
        d.daysInMonth = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        d.monthly = money.currentMonthFixedTotal(now: now, calendar: cal)
        d.incomeBase = money.budgetBaseIncome(now: now, calendar: cal)
        d.dues = MacFixedSchedule.thisMonth(money: money, now: now, calendar: cal)
        d.yearly = yearlyEstimate(money: money, now: now, calendar: cal)
        for e in money.expenses where e.expenseType == .fixed {
            d.hasFixed = true
            guard e.isRecurringFixed, e.isFixedActive(on: now, calendar: cal) else { continue }
            if e.fixedCategory == .subscription {
                d.subscriptionCount += 1
                d.subscriptionMonthly += MacFixedSchedule.monthlyNTD(e, money: money)
            }
            if e.effectivelyTaxDeductible {
                d.taxMonthly += MacFixedSchedule.monthlyNTD(e, money: money)
            }
            if let s = e.macLoanSchedule(now: now, calendar: cal), !s.isDone {
                d.loanLeft += s.left
            }
        }
        return d
    }

    // 照抄 MoneyBoards.swift:570-592（f2c8892）yearlyEstimate — sim4: board4#2（store → money）
    /// 今年一共會扣多少：每一筆照實際的扣款日數今年有幾期（最多 60）；單次的只算日期在今年的
    @MainActor
    static func yearlyEstimate(money: MacMoneyStore, now: Date, calendar cal: Calendar) -> Double {
        let year = cal.component(.year, from: now)
        guard let yearStart = cal.date(from: DateComponents(year: year, month: 1, day: 1)),
              let nextYear = cal.date(byAdding: .year, value: 1, to: yearStart) else { return 0 }
        var total = 0.0
        for e in money.expenses where e.expenseType == .fixed {
            let ntd = money.ntdValue(of: e)
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

// MARK: - 頭的字、膠囊

/// 頭左：「11 月・3 筆扣款」［占收入 49%］、「每月固定支出」、大字、一句話
struct MacFixedHeader {
    let date: String
    let capsule: String?
    let label: String
    let big: String
    let line: String
}

enum MacFixedChipTone {
    case neutral, warn, good
}

/// 頭右膠囊（直排最多 5 顆）
struct MacFixedChip: Identifiable {
    let icon: String
    let label: String
    let value: String
    let tone: MacFixedChipTone

    var id: String { label }
}

enum MacFixedHeadline {
    // 照抄 MoneyBoards.swift:595-643（f2c8892）FixedBoard 頭與一句話 — sim4: head4#1（英文招呼不抄）
    static func header(_ d: MacFixedBoardData) -> MacFixedHeader {
        let date = d.dues.isEmpty ? "\(d.month) 月" : "\(d.month) 月・\(d.dues.count) 筆扣款"
        var capsule: String? = nil
        if d.incomeBase > 0 && d.monthly > 0 {
            capsule = "占收入 " + WidgetMoneyFormat.percent(d.monthly / d.incomeBase)
        }
        return MacFixedHeader(date: date, capsule: capsule, label: "每月固定支出",
                              big: WidgetMoneyFormat.short(d.monthly), line: line(d))
    }

    /// 一句話四種（照 FixedBoard.line）
    static func line(_ d: MacFixedBoardData) -> String {
        if d.dues.isEmpty {
            return d.hasFixed ? "這個月沒有要扣款的項目" : "新增房租、訂閱、保險之後，這裡會排出每一筆扣款的車站"
        }
        if d.leftCount == 0 {
            return "這個月的 \(d.dues.count) 筆都扣完了"
        }
        if d.paidCount == 0 {
            return "這個月還有 \(d.leftCount) 筆要扣"
        }
        return "已扣 \(d.paidCount) 筆、還有 \(d.leftCount) 筆"
    }

    // 照抄 MoneyBoards.swift:645-674（f2c8892）FixedBoard.chips — sim4: head4#2（順序與條件逐字；下一站 ≤1 天 warn、節稅 good）
    static func chips(_ d: MacFixedBoardData) -> [MacFixedChip] {
        var out: [MacFixedChip] = []
        let next = d.next
        if let first = next.first {
            let when = MacFixedSchedule.when(day: first.day, today: d.day, month: d.month)
            let what = next.count == 1 ? MacVariableText.short(first.title) : "\(next.count) 筆"
            let sum = next.reduce(0) { $0 + $1.amount }
            out.append(MacFixedChip(icon: "tram.fill", label: "下一站",
                                    value: when + " " + what + " " + WidgetMoneyFormat.short(sum),
                                    tone: first.day - d.day <= 1 ? .warn : .neutral))
        }
        if d.yearly > 0 {
            out.append(MacFixedChip(icon: "calendar", label: "年度預估", value: WidgetMoneyFormat.short(d.yearly),
                                    tone: .neutral))
        }
        if d.subscriptionCount > 0 {
            out.append(MacFixedChip(icon: "play.rectangle.fill", label: "訂閱 \(d.subscriptionCount) 個",
                                    value: "每月 " + WidgetMoneyFormat.short(d.subscriptionMonthly), tone: .neutral))
        }
        if d.loanLeft > 0 {
            out.append(MacFixedChip(icon: "building.columns.fill", label: "貸款還要繳",
                                    value: WidgetMoneyFormat.short(d.loanLeft), tone: .neutral))
        }
        if d.taxMonthly > 0 {
            out.append(MacFixedChip(icon: "leaf.fill", label: "節稅", value: "每月 " + WidgetMoneyFormat.short(d.taxMonthly),
                                    tone: .good))
        }
        return out
    }
}

// MARK: - 表格的列

/// 表格一列（全 let；顯示字建列時算好，Cell 裡不再 format）
struct MacFixedRow: Identifiable {
    let id: MacEntryRef
    /// 名稱（空的退到地點名、備註或分類名）
    let title: String
    /// 細項說法（「稅費・地價稅」「牌照稅」「貸款 - 房貸」）
    let category: String
    /// 「每月」「每季」「每年」「—」
    let period: String
    /// 週期排序：每月 1、每季 2、每年 3、單次 0
    let periodRank: Int
    /// NT$ 等值（排序用；外幣儲蓄險換算）
    let amount: Double
    /// ⑩「NT$28,000」「USD 1,440」「USD 4（≈ NT$128）」
    let amountText: String
    /// 月均 NT$ 等值（排序用）
    let monthly: Double
    /// 季、年才有字；每月那筆「—」
    let monthlyText: String
    /// 下次扣款（沒有＝.distantFuture）
    let nextDue: Date
    /// 「今天扣款」「明天扣款」「12/1・6 天後」「3/1 扣款」；已停止或沒有下一期＝""
    let nextDueText: String
    /// 下次扣款 ≤ 1 天（上色）
    let warn: Bool
    /// 「信用卡」「銀行」「銀行・USD」「—」
    let payText: String
    /// 「進行中」「已繳 36／240 期」「已繳清」「12/1 開始」「取消訂閱 2026/3/31」
    let status: String
    /// 0 進行中（含貸款）、1 還沒開始、2 已停止
    let statusRank: Int
    /// 已停止整列變淡
    let dimmed: Bool
}

typealias MacFixedSort = KeyPathComparator<MacFixedRow>

/// 一組（iPhone 一個 FixedGroup；點過欄名＝整串一組，key＝nil）
struct MacFixedGroupSection: Identifiable {
    let id: String
    let key: MacFixedGroupKey?
    /// 「貸款」「稅費」；整串一組「依金額排序」
    let title: String
    /// 「3 筆」
    let countText: String
    /// 「每月 NT$2.8萬」那種的完整位數「每月 NT$28,000」；整串一組＝""
    let headerText: String
    let rows: [MacFixedRow]
}

enum MacFixedTable {
    // 照抄 FixedExpenseView.swift:76-98（f2c8892）buildGroupedByCategory — sim4: table4#1
    // 組權重＝已開始、沒停止的 NT$ 等值加總，大的先；Mac 補：同權重照組名字串。組裡進行中在前、NT$ 等值大到小，Mac 補：同額照 id。
    // 「顯示已停止」關掉：已停止的列拿掉（權重本來就不算它們），整組空了就不列。
    // 點過欄名（order 不空）→ 整串一組「依X排序」，照 order 一個一個比、同值照 id。
    @MainActor
    static func groups(money: MacMoneyStore, showEnded: Bool, order: [MacFixedSort], now: Date,
                       calendar cal: Calendar) -> [MacFixedGroupSection] {
        let kinds = money.kindIndex
        var keys: [MacFixedGroupKey] = []
        var buckets: [MacFixedGroupKey: [Expense]] = [:]
        for e in money.fixedExpenses {
            let k = MacFixedGroupKey.of(e, kinds: kinds)
            if buckets[k] == nil { keys.append(k) }
            buckets[k, default: []].append(e)
        }
        var weights: [MacFixedGroupKey: Double] = [:]
        for k in keys {
            var sum = 0.0
            for e in buckets[k] ?? [] where e.date <= now && !e.macIsFixedEnded(now: now, calendar: cal) {
                sum += money.ntdValue(of: e)
            }
            weights[k] = sum
        }
        let orderedKeys: [MacFixedGroupKey] = keys.sorted { a, b in
            let wa = weights[a] ?? 0
            let wb = weights[b] ?? 0
            if wa != wb { return wa > wb }
            return a.title < b.title
        }
        if !order.isEmpty {
            var all: [MacFixedRow] = []
            for k in orderedKeys {
                for e in buckets[k] ?? [] {
                    let r = row(e, money: money, kinds: kinds, now: now, calendar: cal)
                    if showEnded || !r.dimmed { all.append(r) }
                }
            }
            guard !all.isEmpty else { return [] }
            let sorted = sort(all, by: order)
            let name = order.first.map { c in columnName(c) } ?? "點的欄"
            return [MacFixedGroupSection(id: "sorted", key: nil, title: "依" + name + "排序",
                                         countText: "\(sorted.count) 筆", headerText: "", rows: sorted)]
        }
        var out: [MacFixedGroupSection] = []
        for k in orderedKeys {
            let exps = buckets[k] ?? []
            let rows = exps.map { (e: Expense) -> MacFixedRow in
                row(e, money: money, kinds: kinds, now: now, calendar: cal)
            }
            let shown = rows.filter { r in showEnded || !r.dimmed }.sorted { a, b in groupOrder(a, b) }
            guard !shown.isEmpty else { continue }
            out.append(MacFixedGroupSection(id: k.title, key: k, title: k.title, countText: "\(shown.count) 筆",
                                            headerText: "每月 " + headerTotal(k, exps, now: now, calendar: cal),
                                            rows: shown))
        }
        return out
    }

    /// 組裡：進行中在前、NT$ 等值大到小、同額照 id
    static func groupOrder(_ a: MacFixedRow, _ b: MacFixedRow) -> Bool {
        if a.dimmed != b.dimmed { return !a.dimmed }
        if a.amount != b.amount { return a.amount > b.amount }
        return a.id.id < b.id.id
    }

    /// 照 sortOrder 一個一個比（compare 已照正反），同值照 id 字串（同 Mac 3 MacVariableTable.sort）
    static func sort(_ rows: [MacFixedRow], by order: [MacFixedSort]) -> [MacFixedRow] {
        rows.sorted { a, b in
            for c in order {
                let r = c.compare(a, b)
                if r == .orderedAscending { return true }
                if r == .orderedDescending { return false }
            }
            return a.id.id < b.id.id
        }
    }

    /// 欄名（整串一組的標題「依金額排序」；同 Mac 3 MacVariableTable.columnName 的比法）
    static func columnName(_ c: MacFixedSort) -> String {
        if c.keyPath == \MacFixedRow.title { return "項目" }
        if c.keyPath == \MacFixedRow.category { return "分類" }
        if c.keyPath == \MacFixedRow.periodRank { return "週期" }
        if c.keyPath == \MacFixedRow.amount { return "金額" }
        if c.keyPath == \MacFixedRow.monthly { return "月均" }
        if c.keyPath == \MacFixedRow.nextDue { return "下次扣款" }
        if c.keyPath == \MacFixedRow.payText { return "扣款方式" }
        if c.keyPath == \MacFixedRow.statusRank { return "狀態" }
        return "點的欄"
    }

    /// 這幾組加起來幾筆（篩選列右邊）
    static func countText(_ groups: [MacFixedGroupSection]) -> String {
        let n = groups.reduce(0) { s, g in s + g.rows.count }
        return "\(n) 筆"
    }

    // 照抄 FixedExpenseView.swift:341-383（f2c8892）headerTotalText／headerCurrencyCode／monthlyEquivalent／formatCurrencyWithCode
    // — sim4: table4#2　用 amount（不是 NT$ 等值）；單次＝全額（iPhone 怪規則照抄）；保險分幣別、只有儲蓄險用原幣、
    // 幣別排序後「 + 」接；0 位小數 halfEven（WidgetMoneyFormat.number(v, digits: 0)）
    static func headerTotal(_ key: MacFixedGroupKey, _ exps: [Expense], now: Date, calendar cal: Calendar) -> String {
        let active = exps.filter { e in e.date <= now && !e.macIsFixedEnded(now: now, calendar: cal) }
        guard key == .category(.insurance) else {
            return codeMoney(active.reduce(0.0) { s, e in s + headerMonthly(e) }, code: "NT$")
        }
        var byCurrency: [String: [Expense]] = [:]
        for e in active {
            byCurrency[headerCode(e), default: []].append(e)
        }
        guard !byCurrency.isEmpty else { return codeMoney(0, code: "NT$") }
        let codes: [String] = byCurrency.keys.sorted()
        let parts: [String] = codes.map { (code: String) -> String in
            let total = (byCurrency[code] ?? []).reduce(0.0) { s, e in s + headerMonthly(e) }
            return codeMoney(total, code: code)
        }
        return parts.joined(separator: " + ")
    }

    /// 只有儲蓄險的 amount 是原幣；其他保險（含外幣保費）存的是 NT$
    static func headerCode(_ e: Expense) -> String {
        let isSavingsIns = e.fixedCategory == .insurance && e.insuranceSubCategory == .savings
        return isSavingsIns ? e.currencyCode : "NT$"
    }

    /// 組頭的每月等值（單次＝全額；跟詳情的月均換算不同，別合併）
    static func headerMonthly(_ e: Expense) -> Double {
        switch e.recurrence {
        case .monthly: return e.amount
        case .quarterly: return e.amount / 3
        case .yearly: return e.amount / 12
        case .none: return e.amount
        }
    }

    /// 「NT$2,300」「USD 120」
    static func codeMoney(_ v: Double, code: String) -> String {
        let head = (code == "NT$" || code == "TWD") ? "NT$" : code + " "
        return head + WidgetMoneyFormat.number(v, digits: 0)
    }

    static func isNTD(_ code: String) -> Bool {
        code == "NT$" || code == "TWD" || code.isEmpty
    }

    // 照抄 MoneyItemCard.swift:825-838（f2c8892）amountText — sim4: table4#3
    // Mac：台幣完整位數（同 Mac 3 那支詳情用的字：NT$＋兩位以內小數）；儲蓄險原幣 0 位；其他外幣＝原幣 0 位＋「（≈ NT$128）」
    static func amountText(_ e: Expense, rates: [CurrencyRate]) -> String {
        let code = e.currencyCode
        guard !isNTD(code) else { return "NT$" + WidgetMoneyFormat.number(e.amount, digits: 2) }
        if e.fixedCategory == .insurance && e.insuranceSubCategory == .savings {
            return code + " " + WidgetMoneyFormat.number(e.amount, digits: 0)
        }
        let value: Double
        if let rate = rates.first(where: { r in r.code == code })?.rate, rate > 0 {
            value = e.amount / rate
        } else {
            value = e.amount
        }
        return code + " " + WidgetMoneyFormat.number(value, digits: 0) + "（≈ " + MacText.money(e.amount) + "）"
    }

    // 照抄 MoneyItemCard.swift:931-942（f2c8892）下次扣款 chip — sim4: table4#3（≤ 1 天才上色）
    /// 已停止、沒有下一期 → (nil, "", false)
    static func due(_ e: Expense, now: Date, calendar cal: Calendar) -> (date: Date?, text: String, warn: Bool) {
        guard !e.macIsFixedEnded(now: now, calendar: cal),
              let due = e.nextFixedDueDate(onOrAfter: now, calendar: cal) else { return (nil, "", false) }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: due)).day ?? 0
        let md = "\(cal.component(.month, from: due))/\(cal.component(.day, from: due))"
        let text: String
        switch days {
        case ...0: text = "今天扣款"
        case 1: text = "明天扣款"
        case 2...31: text = md + "・\(days) 天後"
        default: text = md + " 扣款"
        }
        return (due, text, days <= 1)
    }

    /// 「2026/3/31」（照 calendar 的年月日）
    static func ymd(_ d: Date, calendar cal: Calendar) -> String {
        "\(cal.component(.year, from: d))/\(cal.component(.month, from: d))/\(cal.component(.day, from: d))"
    }

    /// 狀態欄：已停止「原因（沒有＝已停止） yyyy/M/d」＞還沒開始「M/d 開始」＞貸款「已繳清」／「已繳 a／b 期」＞「進行中」
    static func status(_ e: Expense, now: Date, calendar cal: Calendar) -> (text: String, rank: Int) {
        if e.macIsFixedEnded(now: now, calendar: cal), let end = e.endDate {
            return ((e.endReason?.rawValue ?? "已停止") + " " + ymd(end, calendar: cal), 2)
        }
        if cal.startOfDay(for: e.date) > cal.startOfDay(for: now) {
            let md = "\(cal.component(.month, from: e.date))/\(cal.component(.day, from: e.date))"
            return (md + " 開始", 1)
        }
        if e.fixedCategory == .loan, let s = e.macLoanSchedule(now: now, calendar: cal) {
            return (s.isDone ? "已繳清" : "已繳 \(s.elapsed)／\(s.total) 期", 0)
        }
        return ("進行中", 0)
    }

    // 照抄 MoneyItemCard.swift:909-1003（f2c8892）MoneyItem.fixed 的列字 — sim4: table4#3
    // 月均：季、年才有（外幣儲蓄險原幣 0 位，其餘 MacText.money）；每月、單次「—」
    @MainActor
    static func row(_ e: Expense, money: MacMoneyStore, kinds: MacKindIndex, now: Date, calendar cal: Calendar) -> MacFixedRow {
        let savingsForeign = e.fixedCategory == .insurance && e.insuranceSubCategory == .savings && !isNTD(e.currencyCode)
        var monthlyText = "—"
        if let rec = e.recurrence, rec != .monthly {
            let m: Double = rec == .quarterly ? e.amount / 3 : e.amount / 12
            monthlyText = savingsForeign ? e.currencyCode + " " + WidgetMoneyFormat.number(m, digits: 0) : MacText.money(m)
        }
        let d = due(e, now: now, calendar: cal)
        let st = status(e, now: now, calendar: cal)
        let rank: Int
        switch e.recurrence {
        case .monthly: rank = 1
        case .quarterly: rank = 2
        case .yearly: rank = 3
        case .none: rank = 0
        }
        return MacFixedRow(id: .expense(e.id), title: MacVariableText.title(e),
                           category: e.macDisplayCategoryName(kinds: kinds),
                           period: e.recurrence?.rawValue ?? "—", periodRank: rank,
                           amount: money.ntdValue(of: e), amountText: amountText(e, rates: money.rates),
                           monthly: MacFixedSchedule.monthlyNTD(e, money: money), monthlyText: monthlyText,
                           nextDue: d.date ?? .distantFuture, nextDueText: d.text, warn: d.warn,
                           payText: MacVariableTable.payText(e, empty: "—"),
                           status: st.text, statusRank: st.rank, dimmed: e.macIsFixedEnded(now: now, calendar: cal))
    }

    // 照抄 FixedExpenseView.swift:1177-1184（f2c8892）卡片 monthlyEquivalent — sim4: table4#4
    /// 詳情的月均換算：單次＝0（跟組頭的 headerMonthly 不同，別合併）
    static func inspectorMonthly(_ e: Expense) -> Double {
        switch e.recurrence {
        case .monthly: return e.amount
        case .quarterly: return e.amount / 3
        case .yearly: return e.amount / 12
        case .none: return 0
        }
    }
}

// MARK: - 金額走勢

/// 走勢的一點（Mac 補 id：Int）
struct MacFixedTrendPoint: Identifiable {
    let id: Int
    let date: Date
    let amount: Double
}

// 照抄 FixedExpenseView.swift:744-772（f2c8892）actualPoints／forecastPoints — sim4: trend4#1
// 實際點照日期排（同日期照原本順序）；最小平方法往後 3 年（每年一點、下限 0）；首點接最後實際點；2 筆以上才有預測
struct MacFixedTrend {
    let actual: [MacFixedTrendPoint]
    let forecast: [MacFixedTrendPoint]

    static func make(_ e: Expense, calendar cal: Calendar) -> MacFixedTrend {
        let sorted = e.amountHistory.enumerated().sorted { a, b in
            a.element.date != b.element.date ? a.element.date < b.element.date : a.offset < b.offset
        }
        var actual: [MacFixedTrendPoint] = []
        for (i, pair) in sorted.enumerated() {
            actual.append(MacFixedTrendPoint(id: i, date: pair.element.date, amount: pair.element.amount))
        }
        return MacFixedTrend(actual: actual, forecast: forecastPoints(actual, calendar: cal))
    }

    static func forecastPoints(_ pts: [MacFixedTrendPoint], calendar cal: Calendar) -> [MacFixedTrendPoint] {
        guard pts.count >= 2, let last = pts.last else { return [] }
        let base = pts[0].date.timeIntervalSince1970
        let xs: [Double] = pts.map { p in (p.date.timeIntervalSince1970 - base) / 86400 }
        let ys: [Double] = pts.map { p in p.amount }
        let n = Double(pts.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        var sumXY = 0.0
        var sumXX = 0.0
        for i in 0..<xs.count {
            sumXY += xs[i] * ys[i]
            sumXX += xs[i] * xs[i]
        }
        let denom = n * sumXX - sumX * sumX
        guard abs(denom) > 0.0001 else { return [] }
        let slope = (n * sumXY - sumX * sumY) / denom
        let intercept = (sumY - slope * sumX) / n
        var out: [MacFixedTrendPoint] = [MacFixedTrendPoint(id: 0, date: last.date, amount: last.amount)]
        for yr in 1...3 {
            guard let d = cal.date(byAdding: .year, value: yr, to: last.date) else { continue }
            let x = (d.timeIntervalSince1970 - base) / 86400
            out.append(MacFixedTrendPoint(id: yr, date: d, amount: max(0, slope * x + intercept)))
        }
        return out
    }
}

// MARK: - 詳情欄的字

/// 詳情一列（label 在同一區裡不重複）
struct MacFixedInfoRow: Identifiable {
    let label: String
    let value: String

    var id: String { label }
}

/// 金額紀錄一列（同一天可能好幾筆：id 用序號）
struct MacFixedHistoryRow: Identifiable {
    let id: Int
    let date: String
    let amount: String
}

/// 貸款進度（照抄 FixedExpenseView.swift:1042-1119（f2c8892）loanCardInfo／LoanCardInfo／loanRows）
struct MacFixedLoanInfo {
    let progressValue: Double
    let progressTotal: Double
    /// 「起 ─ 37% ─ 訖」三段
    let startText: String
    let percentText: String
    let endText: String
    let rows: [MacFixedInfoRow]
}

/// 詳情欄一次算完的字（基本資料 → 貸款進度 → 儲蓄險 → 金額走勢＋金額紀錄 → 備註）
struct MacFixedInspectorInfo {
    let title: String
    let facts: [MacFixedInfoRow]
    let loan: MacFixedLoanInfo?
    /// 儲蓄險（只列支出上有的；空＝不是儲蓄險）
    let savings: [MacFixedInfoRow]
    let trend: MacFixedTrend
    /// 新到舊最多 12 筆
    let history: [MacFixedHistoryRow]
    /// 「還有 N 筆」
    let historyMore: String?
    let note: String

    /// 詳情只列最近幾筆金額紀錄
    static let historyLimit = 12

    // 照抄 FixedExpenseView.swift:689-720（f2c8892）infoCard（月均換算 ⑪、起始日、最後扣款、實際期數、節稅）
    @MainActor
    static func make(_ e: Expense, money: MacMoneyStore, now: Date, calendar cal: Calendar) -> MacFixedInspectorInfo {
        let trend = MacFixedTrend.make(e, calendar: cal)
        let newestFirst = Array(trend.actual.reversed())
        let shown = Array(newestFirst.prefix(historyLimit))
        let history: [MacFixedHistoryRow] = shown.map { p in
            MacFixedHistoryRow(id: p.id, date: MacText.fullDay(p.date), amount: historyAmount(p.amount, e: e))
        }
        let more: String? = newestFirst.count > historyLimit ? "還有 \(newestFirst.count - historyLimit) 筆" : nil
        let memo = e.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return MacFixedInspectorInfo(title: MacVariableText.title(e), facts: makeFacts(e, money: money, now: now, calendar: cal),
                                     loan: makeLoan(e, now: now, calendar: cal), savings: makeSavings(e),
                                     trend: trend, history: history, historyMore: more, note: memo.isEmpty ? "—" : memo)
    }

    @MainActor
    static func makeFacts(_ e: Expense, money: MacMoneyStore, now: Date, calendar cal: Calendar) -> [MacFixedInfoRow] {
        var rows: [MacFixedInfoRow] = []
        rows.append(MacFixedInfoRow(label: "金額", value: MacFixedTable.amountText(e, rates: money.rates)))
        let type = e.recurrence.map { r in "固定支出（" + r.rawValue + "）" } ?? "固定支出"
        rows.append(MacFixedInfoRow(label: "類型", value: type))
        rows.append(MacFixedInfoRow(label: "分類", value: e.macDisplayCategoryName(kinds: money.kindIndex)))
        // sim4: table4#4 月均換算：季、年才列（單次＝0 不列）
        let monthly = MacFixedTable.inspectorMonthly(e)
        if let rec = e.recurrence, rec != .monthly, monthly > 0 {
            rows.append(MacFixedInfoRow(label: "月均換算", value: monthlyText(monthly, e: e, rates: money.rates)))
        }
        rows.append(MacFixedInfoRow(label: "起始日", value: MacText.fullDay(e.date)))
        let due = MacFixedTable.due(e, now: now, calendar: cal)
        if let d = due.date {
            rows.append(MacFixedInfoRow(label: "下次扣款", value: MacText.fullDay(d) + "（" + due.text + "）"))
        }
        if let end = e.endDate {
            rows.append(MacFixedInfoRow(label: "最後扣款",
                                        value: MacText.fullDay(end) + (e.endReason.map { r in "（" + r.rawValue + "）" } ?? "")))
        }
        if e.isRecurringFixed {
            rows.append(MacFixedInfoRow(label: "實際期數", value: "\(e.fixedPeriodCount(until: now, calendar: cal)) 期"))
        }
        if e.effectivelyTaxDeductible {
            rows.append(MacFixedInfoRow(label: "節稅", value: "列入節稅追蹤"))
        }
        rows.append(MacFixedInfoRow(label: "付款", value: MacVariableTable.payText(e, empty: "不指定")))
        if !e.photoFileNames.isEmpty {
            rows.append(MacFixedInfoRow(label: "照片", value: "\(e.photoFileNames.count) 張（請在 iPhone 看）"))
        }
        return rows
    }

    // 照抄 FixedExpenseView.swift:1199-1212（f2c8892）monthlyEquivalentDisplay：外幣儲蓄險以原幣寫，有匯率附 NT$ 等值
    static func monthlyText(_ monthly: Double, e: Expense, rates: [CurrencyRate]) -> String {
        let code = e.currencyCode
        let isSavingsIns = e.fixedCategory == .insurance && e.insuranceSubCategory == .savings
        guard isSavingsIns, !MacFixedTable.isNTD(code) else { return MacText.money(monthly) }
        let text = code + " " + WidgetMoneyFormat.number(monthly, digits: 0)
        if let rate = rates.first(where: { r in r.code == code })?.rate, rate > 0 {
            return text + " ≈ " + MacText.money(monthly * rate)
        }
        return text
    }

    /// 金額紀錄的金額：外幣儲蓄險原幣 0 位；其餘 NT$（兩位以內小數）
    static func historyAmount(_ v: Double, e: Expense) -> String {
        let isSavingsIns = e.fixedCategory == .insurance && e.insuranceSubCategory == .savings
        if isSavingsIns && !MacFixedTable.isNTD(e.currencyCode) {
            return e.currencyCode + " " + WidgetMoneyFormat.number(v, digits: 0)
        }
        return "NT$" + WidgetMoneyFormat.number(v, digits: 2)
    }

    // 照抄 FixedExpenseView.swift:1042-1119（f2c8892）貸款區塊：期數讀 macLoanPeriods；金額一律每期 × 期數（含利息）
    static func makeLoan(_ e: Expense, now: Date, calendar cal: Calendar) -> MacFixedLoanInfo? {
        guard e.fixedCategory == .loan, let rec = e.recurrence,
              let p = e.macLoanPeriods(asOf: now, calendar: cal) else { return nil }
        let (component, step) = rec.componentValue
        let end = MacLoanMath.dueDate(p.total, start: e.date, component: component, step: step, calendar: cal)
        let isDone = p.paid >= p.total
        let ratio: Double = p.total > 0 ? min(1, Double(p.paid) / Double(p.total)) : 0
        let per = e.amount
        var rows: [MacFixedInfoRow] = []
        if let rate = e.loanRate, rate > 0 {
            rows.append(MacFixedInfoRow(label: "貸款利率", value: String(format: "%.2f%%", rate)))
        }
        rows.append(MacFixedInfoRow(label: "已繳／總期數",
                                    value: isDone ? "已繳清（共 \(p.total) 期）" : "\(p.paid)／\(p.total) 期"))
        rows.append(MacFixedInfoRow(label: "已繳金額", value: WidgetMoneyFormat.short(per * Double(p.paid))))
        if let principal = e.loanTotalAmount, principal > 0 {
            rows.append(MacFixedInfoRow(label: "借款本金", value: WidgetMoneyFormat.short(principal)))
        }
        rows.append(MacFixedInfoRow(label: "全部要繳（含利息）", value: WidgetMoneyFormat.short(per * Double(p.total))))
        rows.append(MacFixedInfoRow(label: "還要繳", value: WidgetMoneyFormat.short(per * Double(max(0, p.total - p.paid)))))
        rows.append(MacFixedInfoRow(label: "預計繳清", value: end.map { d in MacText.fullDay(d) } ?? "—"))
        let total = Double(max(p.total, 1))
        return MacFixedLoanInfo(progressValue: min(Double(max(p.paid, 0)), total), progressTotal: total,
                                startText: MacText.fullDay(e.date), percentText: WidgetMoneyFormat.percent(ratio),
                                endText: end.map { d in MacText.fullDay(d) } ?? "—", rows: rows)
    }

    /// 儲蓄險：只列支出上有的（種類、幣別、年利率）；期數、到期日、預估領回在保單那包，這版不讀
    static func makeSavings(_ e: Expense) -> [MacFixedInfoRow] {
        guard e.fixedCategory == .insurance, e.insuranceSubCategory == .savings else { return [] }
        var rows: [MacFixedInfoRow] = []
        rows.append(MacFixedInfoRow(label: "種類", value: InsuranceSubCategory.savings.rawValue))
        rows.append(MacFixedInfoRow(label: "幣別", value: MacFixedTable.isNTD(e.currencyCode) ? "NT$" : e.currencyCode))
        if let rate = e.insuranceRate, rate > 0 {
            rows.append(MacFixedInfoRow(label: "年利率", value: String(format: "%.2f%%", rate)))
        }
        return rows
    }
}
