// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.644 mac4 G1] 固定支出的期數、金額歷史、詢問框金額字（judge_mac §R5、§R7 ⑲；brief §2 G1）。
// 照抄 WealthFacts.swift:138-150、:240-266、:383-409、:437-444、AddExpenseView.swift:5449-5470（f2c8892）；
// 只 import Foundation；不准 Calendar.current（WealthCal 是西曆、zh_TW、跟著 Mac 的時區）。純函式，只准在
// MacEditor／MacEntryRules／MacEditPolicy 叫（不准進 MacCloudWriter.swift；G2 不准叫）。sim_mac4.py cal4#、ask4#。
import Foundation

enum MacFixedCal {
    // 照抄 WealthFacts.swift:138-150（f2c8892）WealthCal.calendar／day／addDays — sim4: cal4#1
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "zh_TW")
        c.timeZone = TimeZone.autoupdatingCurrent
        return c
    }()

    /// 那天 00:00
    static func day(_ d: Date) -> Date { calendar.startOfDay(for: d) }

    static func addDays(_ n: Int, to d: Date) -> Date {
        calendar.date(byAdding: .day, value: n, to: d) ?? d
    }

    // 照抄 WealthFacts.swift:243-262（f2c8892）WealthFormat.grouped — sim4: ask4#1
    /// 128400 →「128,400」；decimals 2 →「3,200.00」；負數前面一個「-」
    static func grouped(_ v: Double, decimals: Int) -> String {
        let scale: Double = decimals >= 2 ? 100 : 1
        let r = (Swift.abs(v) * scale).rounded()
        guard r.isFinite, r < 9e17 else { return String(format: "%.0f", v) }
        let n = Int64(r)
        let unit = Int64(scale)
        let whole = n / unit
        let frac = n % unit
        let digits = String(whole)
        var rev = ""
        for (i, ch) in digits.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { rev.append(",") }
            rev.append(ch)
        }
        var s = String(rev.reversed())
        if decimals >= 2 {
            s += frac < 10 ? ".0\(frac)" : ".\(frac)"
        }
        return (v < 0 && n != 0) ? "-" + s : s
    }

    // 照抄 WealthFacts.swift:265-269（f2c8892）WealthFormat.ntd — sim4: ask4#1
    /// 「NT$128,400」「-NT$3,200」（寫到元）
    static func ntd(_ v: Double) -> String {
        let r = v.rounded()
        let body = "NT$" + grouped(Swift.abs(r), decimals: 0)
        return r < 0 ? "-" + body : body
    }

    // 照抄 WealthFacts.swift:386-394（f2c8892）WealthSchedule.fixedDue — sim4: cal4#3
    /// 第 k 期（從 0 起）的扣款日：第一期＋k 個週期，一次加；貸款第一期＝起始日＋1 個週期
    static func fixedDue(_ exp: Expense, _ k: Int) -> Date? {
        guard let rec = exp.recurrence else { return nil }
        let (component, step) = rec.componentValue
        let cal = MacFixedCal.calendar
        let first: Date = exp.fixedCategory == .loan
            ? (cal.date(byAdding: component, value: step, to: exp.date) ?? exp.date)
            : exp.date
        return cal.date(byAdding: component, value: step * k, to: first)
    }

    // 照抄 WealthFacts.swift:397-409（f2c8892）WealthSchedule.fixedPeriods — sim4: cal4#4
    /// 到 until 那天（含）為止的每一期；結束日當期照算。最多 1200 期
    static func fixedPeriods(_ exp: Expense, through until: Date) -> [(index: Int, date: Date)] {
        guard exp.expenseType == .fixed, exp.recurrence != nil else { return [] }
        let limit = MacFixedCal.day(until)
        let end: Date? = exp.endDate.map { MacFixedCal.day($0) }
        var out: [(index: Int, date: Date)] = []
        var k = 0
        while k < 1200 {
            guard let due = fixedDue(exp, k) else { break }
            let d = MacFixedCal.day(due)
            if d > limit { break }
            if let e = end, d > e { break }
            out.append((index: k, date: due))
            k += 1
        }
        return out
    }

    // 照抄 WealthFacts.swift:437-444（f2c8892）WealthSchedule.amount — sim4: cal4#2
    /// 那一期的金額：history（已照日期排好）裡那天（含）以前最後一筆；找到的是最新一筆就用現在的金額；
    /// 比第一筆早用第一筆；沒有紀錄＝現在的金額
    static func amount(at date: Date, current: Double, sortedHistory h: [AmountSnapshot]) -> Double {
        guard !h.isEmpty else { return current }
        let d = MacFixedCal.day(date)
        var found: Int? = nil
        for (i, s) in h.enumerated() where MacFixedCal.day(s.date) <= d { found = i }
        guard let i = found else { return h[0].amount }
        return i == h.count - 1 ? current : h[i].amount
    }

    // 照抄 AddExpenseView.swift:5453-5470（f2c8892）AmountHistoryChange.from（新的兩筆帶 firstID、newID：重試一模一樣）— sim4: cal4#5
    /// cutoff 那天（含）起是 newAmount；cutoff 以前每一期照原本算出來的金額不變
    static func historyFrom(_ cutoff: Date, history: [AmountSnapshot], current: Double, firstDate: Date,
                            newAmount: Double, firstID: UUID, newID: UUID) -> [AmountSnapshot] {
        let start = MacFixedCal.day(cutoff)
        let sorted = history.sorted { $0.date < $1.date }
        // cutoff 前一天那一期原本算的金額（跟 MacFixedCal.amount 同一條）
        let before = MacFixedCal.amount(at: MacFixedCal.addDays(-1, to: start), current: current, sortedHistory: sorted)
        var kept = sorted.filter { MacFixedCal.day($0.date) < start }
        if let last = kept.last {
            if Swift.abs(last.amount - before) > 0.004 {
                kept[kept.count - 1] = AmountSnapshot(id: last.id, date: last.date, amount: before)
            }
        } else {
            kept = [AmountSnapshot(id: firstID, date: firstDate, amount: before)]
        }
        kept.append(AmountSnapshot(id: newID, date: cutoff, amount: newAmount))
        return kept
    }

    // MARK: - Mac 4 新加（P8、表單規則；sim4: cal4#6～#9）

    /// 今天以前每一期的（那天, 金額）— sim4: cal4#6
    static func pastPeriods(_ e: Expense, now: Date) -> [(day: Date, amount: Double)] {
        let sortedHistory = e.amountHistory.sorted { $0.date < $1.date }
        let yesterday = addDays(-1, to: day(now))
        var out: [(day: Date, amount: Double)] = []
        for p in fixedPeriods(e, through: yesterday) {
            out.append((day: day(p.date), amount: amount(at: p.date, current: e.amount, sortedHistory: sortedHistory)))
        }
        return out
    }

    /// 兩份「以前的期數」一模一樣：筆數一樣、每期那天一樣、金額差 ≤ 0.004 — sim4: cal4#7
    static func samePast(_ a: [(day: Date, amount: Double)], _ b: [(day: Date, amount: Double)]) -> Bool {
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) where x.day != y.day || Swift.abs(x.amount - y.amount) > 0.004 {
            return false
        }
        return true
    }

    /// 最近一期已扣過的那天（沒有＝nil）— sim4: cal4#8
    static func lastPastDue(_ e: Expense, now: Date) -> Date? {
        pastPeriods(e, now: now).last?.day
    }

    /// 已開始＝第一期那天（e.date）在今天以前（照 iPhone 問不問那條，貸款也看 e.date）
    static func isStarted(_ e: Expense, now: Date) -> Bool {
        day(e.date) < day(now)
    }

    /// 金額紀錄有明天或之後的點（今天的點不算：iPhone〔從今天起〕本來就換掉）
    static func historyHasFuture(_ e: Expense, now: Date) -> Bool {
        let today = day(now)
        return e.amountHistory.contains { s in day(s.date) > today }
    }

    private static let zeroID = UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID()

    /// ★1〔從今天起〕改完今天以前每一期一模一樣（新金額不影響以前，帶 e.amount）— sim4: cal4#9
    static func fromTodayKeepsPast(_ e: Expense, now: Date) -> Bool {
        var after = e
        after.amountHistory = historyFrom(now, history: e.amountHistory, current: e.amount, firstDate: e.date,
                                          newAmount: e.amount, firstID: zeroID, newID: zeroID)
        return samePast(pastPeriods(e, now: now), pastPeriods(after, now: now))
    }

    /// 停止區下限（打開開關、〔停止扣款…〕的預設那天）：max(今天, 第一期, 最近已扣過的那期) — sim4: entry4#3
    static func stopLowerBound(_ e: Expense, now: Date) -> Date {
        var d = max(day(now), day(e.date))
        if let last = lastPastDue(e, now: now), last > d { d = last }
        return d
    }

    // 照抄 AddExpenseView.swift:3995-4005（f2c8892）amountChangeAsk 的字（只拿掉〔全部都改〕；台幣＝WealthFormat.ntd）— sim4: ask4#1
    static func amountAskTitle(name: String, old: Double, new: Double) -> String {
        "\(name)從 \(ntd(old)) 改成 \(ntd(new))"
    }

    static func amountAskMessage(hasPayment: Bool, iPhoneLine: String) -> String {
        let why = hasPayment ? "財富頁銀行的數字照這個算。" : "固定支出頁的金額走勢照這個記。"
        return "以前扣過的那幾期要不要跟著改？" + why + "\n" + iPhoneLine
    }
}
