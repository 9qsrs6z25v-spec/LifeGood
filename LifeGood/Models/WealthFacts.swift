import Foundation
import CryptoKit

// MARK: - [v25.563] 一套數字：財富（wealth/judge.md §3.13；build/v2/brief.md）
//
// 全 App 跟「錢在哪個帳戶」有關的數字只算這一套：財富頁列表、英雄卡、卡片頁明細、信用卡的要繳／還沒出帳／還能刷、
// 記帳／收入／股票／房屋水電／AI 記帳的扣款選單、轉帳、對存摺（v4 起理財淨資產、小工具；v7 網頁版）。
// 取代以前四份餘額（財富頁 bankBalances、記帳 allBankBalances、股票 allAccountBalances、網頁版）、
// 五份「這個帳戶有哪些幣別」、兩套信用卡期別（U1 C1、C2、C7）。照 HouseFacts／VehicleFacts：純值、build 一次。
//
// 規則（一條一行；sim_v2.py 照這裡一行一行寫過、跑過）：
// • 日子一律以「天」為單位（西曆、手機時區）：某一天的數字＝那天結束時。
// • 存摺上＝（最近一次對存摺的數字）＋（那天之後、今天以前的每一筆）；從沒對過就從 0 全部加起來；以前的沖正照舊當加減。
//   同一天：先算那天的每一筆，對存摺最後（記的是那天結束時）。
// • 每一筆：手動存提款、轉帳兩邊、利息、手續費；記帳一次性支出、一次性收入寫在 bankDeposits 的那筆；
//   直接扣這個帳戶的週期性固定支出、入這個帳戶的月薪（第 k 期＝第一期＋k 個週期一次加，D8；金額照那一期當時，D9）；
//   股票交割與股利（股票自己寫的，日期是 T+2，還沒到的不算）；
//   **信用卡帳單**：每張卡每一期，在繳款截止日從「那一期的扣款帳戶」扣一次帳單金額（v2 一律當自動扣全額；
//   刷卡當天不再扣銀行，D5）。
// • 跳過（被別的算法取代）：連到刷卡支出的、連到週期性固定支出／收入的、連到股票而那檔股票自己有交割帳戶的（v1 W8）。
// • 信用卡一期＝(上次結帳日, 這次結帳日]，結帳日當天刷的算這一期；結帳日 29–31 遇小月取月底；
//   沒填結帳日當 25 日、沒填繳款截止日當 15 日（跟以前的扣款日同一個預設）。截止日：繳款日 ≤ 結帳日 → 下個月；不然同月。
//   要繳＝已經結帳、截止日還沒到的；還沒出帳＝還沒結帳的這一期（刷到今天）；還能刷＝額度 − 要繳 − 還沒出帳（不小於 0）。
// • 換算只有一支：FinanceRates.accountAmount（v1）；查不到匯率的那一格不算進台幣合計（不當 1:1，D14），標「沒有匯率」。
// • 證券戶身上的 bankDeposits 不算進任何合計（D16）；待交割只算銀行帳戶裡、日期還沒到的股票款（同一天買賣相抵）。
//
// （工程）build 很重（展開每一期），全 App 只透過 LifeStore.wealthFacts(expense:finance:) 拿快取的那一份
// （key＝里程碑／財富帳本的 revision＋記帳、理財的 modifyID＋匯率＋日期），打字時不重算（U1 P1、P5）。
// 不標 @MainActor（AI 記帳、LifeStore 都會叫）；但字串用到 ntdWanString（NumberFormatter），請在主執行緒叫。

// MARK: - 日曆（西曆、zh_TW、跟著手機的時區；坑 #11）

enum WealthCal {
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

    static func addMonths(_ n: Int, to d: Date) -> Date {
        calendar.date(byAdding: .month, value: n, to: d) ?? d
    }

    /// d 那個月的第 dayOfMonth 天 00:00（超過月底取月底）
    static func date(inMonthOf d: Date, day dayOfMonth: Int) -> Date {
        var comps = calendar.dateComponents([.year, .month], from: d)
        comps.day = 1
        let first = calendar.date(from: comps) ?? calendar.startOfDay(for: d)
        let maxDay = calendar.range(of: .day, in: .month, for: first)?.count ?? 28
        comps.day = min(max(dayOfMonth, 1), maxDay)
        return calendar.date(from: comps) ?? first
    }

    /// 那個月 1 號 00:00
    static func startOfMonth(_ d: Date) -> Date { date(inMonthOf: d, day: 1) }

    /// 「2026-10」：帳單 key（結帳日那個月）
    static func monthKey(_ d: Date) -> String {
        let c = calendar.dateComponents([.year, .month], from: d)
        return String(format: "%04ld-%02ld", c.year ?? 0, c.month ?? 0)
    }

    /// 「2026-10-19」：快取 key
    static func dayKey(_ d: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04ld-%02ld-%02ld", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 幾月（1–12）
    static func month(_ d: Date) -> Int { calendar.component(.month, from: d) }

    /// 那天之後幾天（day 對 day）
    static func days(from a: Date, to b: Date) -> Int {
        calendar.dateComponents([.day], from: day(a), to: day(b)).day ?? 0
    }
}

// MARK: - 固定 id（D21）

enum WealthIDs {
    /// 虛擬紀錄要 UUID 時用：SHA256 前 16 位元組，每次開 App 都一樣（以前用 Hasher，每次開 App 種子不同）
    static func stable(_ seed: String) -> UUID {
        let digest = SHA256.hash(data: Data(seed.utf8))
        var b = [UInt8](repeating: 0, count: 16)
        var i = 0
        for byte in digest {
            if i >= 16 { break }
            b[i] = byte
            i += 1
        }
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    /// 股票卡寫的「現金股利入帳」那一筆 BankDeposit 的 id。
    /// ⚠️ 照 v25.316 以來 StockDetailView.stableDepositId 的 FNV-1a 一個位元都不能改：舊資料的股利入帳就是這個 id，
    ///    換算法就認不得以前的股利（刪那次配息時刪不到、重寫交割時會被當成交割紀錄清掉）。
    static func dividendDeposit(_ dividendId: UUID) -> UUID {
        let seed = "dividend-\(dividendId.uuidString)"
        var h: UInt64 = 14_695_981_039_346_656_037
        for byte in seed.utf8 { h = (h ^ UInt64(byte)) &* 1_099_511_628_211 }
        let lo = h
        let hi = (h >> 32) ^ (h << 17) ^ 0xB3B3_B3B3_B3B3_B3B3
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 { bytes[i]     = UInt8((lo >> (i * 8)) & 0xff) }
        for i in 0..<8 { bytes[i + 8] = UInt8((hi >> (i * 8)) & 0xff) }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// 這檔股票每一次現金股利的入帳 id。股票卡加交易、新增股票頁存檔重寫交割紀錄時，
    /// 用它把股利那幾筆留下來（以前 removeAll { linkedStockId == 股票 } 連股利一起清掉）
    static func dividendDepositIds(of stock: Stock) -> Set<UUID> {
        var out = Set<UUID>()
        for d in stock.dividends where d.kind == .cash {
            out.insert(dividendDeposit(d.id))
        }
        return out
    }
}

// MARK: - 金額的字（不用 NumberFormatter：哪個執行緒叫都可以）

enum WealthFormat {
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

    /// 「NT$128,400」「-NT$3,200」（寫到元，對存摺、對帳單用）
    static func ntd(_ v: Double) -> String {
        let r = v.rounded()
        let body = "NT$" + grouped(Swift.abs(r), decimals: 0)
        return r < 0 ? "-" + body : body
    }

    /// 台幣「NT$128,400」；外幣「美金 3,200.00」（外幣照實寫兩位小數）
    static func money(_ v: Double, code: String) -> String {
        if FinanceRates.isNTD(code) { return ntd(v) }
        let body = "\(code) " + grouped(Swift.abs(v), decimals: 2)
        return v < 0 && (Swift.abs(v) * 100).rounded() != 0 ? "-" + body : body
    }

    /// 「10/27」
    static func monthDay(_ d: Date) -> String {
        let c = WealthCal.calendar.dateComponents([.month, .day], from: d)
        return "\(c.month ?? 0)/\(c.day ?? 0)"
    }

    /// 0.083 →「8.3%」
    static func percent(_ ratio: Double) -> String {
        String(format: "%.1f%%", ratio * 100)
    }
}

// MARK: - 期數一次算、金額照當時（D8、D9）

enum WealthSchedule {
    /// 固定支出第 k 期（從 0 起）的扣款日：第一期＋k 個週期，一次加（月底取月底；同 Expense.nextFixedDueDate）。
    /// 貸款的第一期是起始日的下一個週期（撥款日 3/5 → 第一期 4/5）。
    static func fixedDue(_ exp: Expense, _ k: Int) -> Date? {
        guard let rec = exp.recurrence else { return nil }
        let (component, step) = rec.componentValue
        let cal = WealthCal.calendar
        let first: Date = exp.fixedCategory == .loan
            ? (cal.date(byAdding: component, value: step, to: exp.date) ?? exp.date)
            : exp.date
        return cal.date(byAdding: component, value: step * k, to: first)
    }

    /// 固定支出到 until 那天（含）為止的每一期；結束日當期照算（同 Expense.fixedPeriodCount）。最多 1200 期
    static func fixedPeriods(_ exp: Expense, through until: Date) -> [(index: Int, date: Date)] {
        guard exp.expenseType == .fixed, exp.recurrence != nil else { return [] }
        let limit = WealthCal.day(until)
        let end: Date? = exp.endDate.map { WealthCal.day($0) }
        var out: [(index: Int, date: Date)] = []
        var k = 0
        while k < 1200 {
            guard let due = fixedDue(exp, k) else { break }
            let d = WealthCal.day(due)
            if d > limit { break }
            if let e = end, d > e { break }
            out.append((index: k, date: due))
            k += 1
        }
        return out
    }

    /// 週期性收入（每月／每年）到 until 那天（含）為止的每一期：第 k 期＝起始日＋k 個週期一次加；
    /// 有結束日的照 Income.isActive(in:)（結束那個月含）。單次收入回空的。最多 1200 期
    static func incomePeriods(_ inc: Income, through until: Date) -> [(index: Int, date: Date)] {
        let component: Calendar.Component
        switch inc.period {
        case .once: return []
        case .monthly: component = .month
        case .yearly: component = .year
        }
        let cal = WealthCal.calendar
        let limit = WealthCal.day(until)
        var out: [(index: Int, date: Date)] = []
        var k = 0
        while k < 1200 {
            guard let due = cal.date(byAdding: component, value: k, to: inc.date) else { break }
            if WealthCal.day(due) > limit { break }
            if !inc.isActive(in: due, calendar: cal) { break }
            out.append((index: k, date: due))
            k += 1
        }
        return out
    }

    /// 那一期的金額（D9）：history（已照日期排好）裡「那一期那天（含）以前最後一筆」；
    /// 找到的是最新一筆就用現在的金額（記帳表單直接改金額、沒補紀錄的，最新那一段跟著現在）；
    /// 那一期比第一筆還早用第一筆；沒有紀錄＝現在的金額
    static func amount(at date: Date, current: Double, sortedHistory h: [AmountSnapshot]) -> Double {
        guard !h.isEmpty else { return current }
        let d = WealthCal.day(date)
        var found: Int? = nil
        for (i, s) in h.enumerated() where WealthCal.day(s.date) <= d { found = i }
        guard let i = found else { return h[0].amount }
        return i == h.count - 1 ? current : h[i].amount
    }

    /// 支出一筆（或一期）的台幣值：只有外幣儲蓄險是原幣存的（同 ExpenseStore.ntdValue(of:)）
    static func ntd(of exp: Expense, raw: Double, rates: FinanceRates) -> Double {
        guard let o = exp.originalCurrencyAmount else { return raw }
        return raw * rates.rate(o.code)
    }
}

// MARK: - 信用卡的期別（全 App 只有這一份；v1 的 CreditCardCycle 搬過來）

enum WealthCardCycle {
    static let defaultBillingDay = 25
    static let defaultPaymentDay = 15

    /// 實際拿來算的結帳日（沒填 25；舊資料打錯的 0、45 夾到 1–31）
    static func billingDay(_ raw: Int?) -> Int { min(max(raw ?? defaultBillingDay, 1), 31) }
    /// 實際拿來算的繳款截止日（沒填 15）
    static func paymentDay(_ raw: Int?) -> Int { min(max(raw ?? defaultPaymentDay, 1), 31) }

    /// d 那個月的結帳日（00:00；超過月底取月底）
    static func closeDate(inMonthOf d: Date, billingDay b: Int) -> Date {
        WealthCal.date(inMonthOf: d, day: b)
    }

    /// 這天刷的算哪一期：那一期的結帳日。一期＝(上次結帳日, 這次結帳日]，結帳日當天刷的算這一期
    static func statementClose(for d: Date, billingDay b: Int) -> Date {
        let dd = WealthCal.day(d)
        let thisMonth = closeDate(inMonthOf: dd, billingDay: b)
        if dd <= thisMonth { return thisMonth }
        return closeDate(inMonthOf: WealthCal.addMonths(1, to: WealthCal.startOfMonth(dd)), billingDay: b)
    }

    /// close 的前一次結帳日
    static func previousClose(_ close: Date, billingDay b: Int) -> Date {
        closeDate(inMonthOf: WealthCal.addMonths(-1, to: WealthCal.startOfMonth(close)), billingDay: b)
    }

    /// 結帳日 close 那一期的繳款截止日：繳款日 ≤ 結帳日 → 下個月；不然同一個月（同 LifeMilestone.creditCardWithdrawalDate）
    static func dueDate(close: Date, billingDay b: Int, paymentDay p: Int) -> Date {
        let monthStart = WealthCal.startOfMonth(close)
        let month = p <= b ? WealthCal.addMonths(1, to: monthStart) : monthStart
        return WealthCal.date(inMonthOf: month, day: p)
    }

    /// 「10 月帳單」（結帳日那個月）
    static func label(close: Date) -> String { "\(WealthCal.month(close)) 月帳單" }

    /// 改扣款帳戶時的「下一期」：明天起刷的那一期（結帳日當天改，今天這期照舊從原本的帳戶扣）
    static func nextStatement(billingDay raw: Int?, now: Date) -> (key: String, label: String) {
        let close = statementClose(for: WealthCal.addDays(1, to: WealthCal.day(now)), billingDay: billingDay(raw))
        return (WealthCal.monthKey(close), label(close: close))
    }

    /// 這一期（帳單 key）從哪個帳戶扣（D10）：沒有歷史＝卡現在的扣款帳戶；
    /// 有歷史找「fromKey ≤ 這一期」的最後一段，那一段是最新的一段就用卡現在的 linkedBankMilestoneId
    /// （還沒更新的 iPad 改了扣款帳戶，新的那一段也跟得上）；比第一段還早用第一段的帳戶
    static func payer(statementKey key: String, linked: UUID?, history: [WealthPayFrom]?) -> UUID? {
        let h = (history ?? []).sorted { $0.fromKey < $1.fromKey }
        guard !h.isEmpty else { return linked }
        var found: Int? = nil
        for (i, e) in h.enumerated() where e.fromKey <= key { found = i }
        guard let idx = found else { return h[0].accountId }
        return idx == h.count - 1 ? linked : h[idx].accountId
    }
}

/// 一筆刷卡（定期扣款每一期一筆），金額台幣
struct WealthCardEntry: Identifiable {
    let id: String
    let date: Date
    let amount: Double
    let expenseId: UUID
    /// 定期扣款展開出來的那一期（不是第一期）
    let isRecurring: Bool
}

/// 一期帳單
struct WealthStatement: Identifiable {
    /// 「2026-10」（結帳日那個月；西曆）
    let key: String
    /// 這一期第一天（上次結帳日隔天）
    let start: Date
    /// 結帳日
    let close: Date
    /// 繳款截止日（v2：自動扣全額，這天從扣款帳戶扣）
    let due: Date
    /// 帳單金額（台幣）
    let amount: Double
    /// 幾筆
    let count: Int
    /// 這一期從哪個帳戶扣（D10；帳戶不在了是 nil）
    let payerId: UUID?
    /// 結帳日已經過了（結帳日當天還沒出帳）
    let isClosed: Bool
    /// 截止日到了（v2 一律當自動扣全額：這天就扣了）
    let isPaid: Bool

    var id: String { key }
    /// 「10 月帳單」
    var label: String { WealthCardCycle.label(close: close) }
}

// MARK: - 明細一列（今天以前的、接下來 35 天的）

struct WealthLedgerRow: Identifiable {
    enum Kind {
        case deposit, withdrawal, interest, fee
        case transferOut, transferIn
        /// 對存摺（存摺上的數字）
        case anchor
        /// 以前的沖正（照舊當加減）
        case legacyAdjust
        /// 記帳一次性支出／收入寫在帳戶裡的那筆
        case expense, income
        /// 直接扣這個帳戶的週期性固定支出、入這個帳戶的月薪（展開的每一期）
        case fixedExpense, recurringIncome
        /// 信用卡一期帳單
        case cardBill
        /// 股票交割、股利（股票自己寫的）
        case stockBuy, stockSell, dividend

        /// 徽章（D16：證券寫「買入」「賣出」，不再寫「賣出獲利」）
        var badge: String {
            switch self {
            case .deposit: return "存款"
            case .withdrawal: return "提款"
            case .interest: return "利息"
            case .fee: return "手續費"
            case .transferOut: return "轉出"
            case .transferIn: return "轉入"
            case .anchor: return "對存摺"
            case .legacyAdjust: return "沖正"
            case .expense: return "扣款"
            case .income: return "收入"
            case .fixedExpense: return "固定扣款"
            case .recurringIncome: return "入帳"
            case .cardBill: return "卡費"
            case .stockBuy: return "買入"
            case .stockSell: return "賣出"
            case .dividend: return "股利"
            }
        }
    }

    /// 真的紀錄＝BankDeposit.id.uuidString；固定支出「fx-<支出>-<k>」；月薪「in-<收入>-<k>」；卡費「bill-<卡>-<2026-10>」
    let id: String
    let date: Date
    /// 幣別（台幣一律 "NT$"）
    let code: String
    /// 金額（正的）；對存摺＝存摺上的數字
    let amount: Double
    /// 錢出去（對存摺看 anchorDiff）
    let isOutflow: Bool
    let kind: Kind
    /// 「@GoGo 9 月帳單」「中華電信」「轉給 國泰世華」「買 0050」「對存摺」
    let title: String
    let note: String?
    /// 這一列之後、這個幣別的存摺上
    var balanceAfter: Double
    /// 對存摺：跟 App 算的差多少（存摺上 − App 算的）
    var anchorDiff: Double?
    /// 真的紀錄（點了可以編輯／刪除）
    let depositId: UUID?
    let expenseId: UUID?
    let incomeId: UUID?
    let stockId: UUID?
    let cardId: UUID?
    let statementKey: String?
    let transferPairId: UUID?
    /// 還沒結帳的那一期卡費（接下來 35 天裡、金額會再變）
    let isEstimate: Bool

    init(id: String, date: Date, code: String, amount: Double, isOutflow: Bool, kind: Kind,
         title: String, note: String? = nil, balanceAfter: Double = 0, anchorDiff: Double? = nil,
         depositId: UUID? = nil, expenseId: UUID? = nil, incomeId: UUID? = nil, stockId: UUID? = nil,
         cardId: UUID? = nil, statementKey: String? = nil, transferPairId: UUID? = nil,
         isEstimate: Bool = false) {
        self.id = id
        self.date = date
        self.code = code
        self.amount = amount
        self.isOutflow = isOutflow
        self.kind = kind
        self.title = title
        self.note = note
        self.balanceAfter = balanceAfter
        self.anchorDiff = anchorDiff
        self.depositId = depositId
        self.expenseId = expenseId
        self.incomeId = incomeId
        self.stockId = stockId
        self.cardId = cardId
        self.statementKey = statementKey
        self.transferPairId = transferPairId
        self.isEstimate = isEstimate
    }

    /// 「+NT$80,000」「-美金 10.00」；對存摺「NT$74,199」
    var amountText: String {
        if kind == .anchor { return WealthFormat.money(amount, code: code) }
        return (isOutflow ? "-" : "+") + WealthFormat.money(amount, code: code)
    }

    /// 「餘額 128,400」（底下小字；跟存摺一樣一列一列對得上）
    var balanceText: String { "餘額 " + WealthFormat.money(balanceAfter, code: code) }
}

/// 要確認的一條（v2 只偵測 #6 沒填結帳日、#9 沒有匯率；畫面 v3）
struct WealthCheck: Identifiable {
    enum Kind: String {
        case cardDaysMissing
        case unknownRate
    }
    let id: String
    let kind: Kind
    let text: String
    let accountIds: [UUID]
}

// MARK: - 一套數字

struct WealthFacts {
    /// 接下來幾天（每個帳戶的 upcoming）
    static let upcomingDays = 35

    let now: Date
    /// 今天 00:00
    let today: Date
    /// 銀行帳戶（照里程碑的順序）＋證券戶（isSecurities）
    let accounts: [Account]
    let cards: [Card]
    /// 存款合計（存摺上；算進存款合計、沒收起來的銀行帳戶，每個幣別換台幣；查不到匯率的不算）
    let cash: Double
    /// 有幣別查不到匯率（大字前加「約」）
    let cashIsApprox: Bool
    /// 台幣活存（定存帳戶、外幣不算）
    let live: Double
    /// 定存（帳戶種類是定存的）
    let fixedDeposit: Double
    /// 外幣（活存帳戶裡不是台幣的那幾格，換台幣）
    let foreign: Double
    /// 卡費還沒扣：每張卡「要繳＋還沒出帳」
    let owedCards: Double
    /// 待交割：銀行帳戶裡日期還沒到的股票款
    let pendingSettlement: Double
    /// 查不到匯率的幣別
    let unknownCodes: [String]
    let checks: [WealthCheck]

    /// 還沒扣＝卡費＋待交割
    var notYetDebited: Double { owedCards + pendingSettlement }
    /// 扣完活存能用＝台幣活存 − 還沒扣（judge §3.1）
    var usable: Double { live - notYetDebited }

    var banks: [Account] { accounts.filter { !$0.isSecurities } }
    var securities: [Account] { accounts.filter { $0.isSecurities } }
    /// 記帳、收入、房屋水電選單列的銀行：沒收起來、不是定存（judge §6.2）
    var pickerBanks: [Account] { accounts.filter { !$0.isSecurities && !$0.hidden && !$0.isFixedDeposit } }
    /// 記帳選單列的卡：沒停用的
    var pickerCards: [Card] { cards.filter { !$0.isDisabled } }

    func account(_ id: UUID?) -> Account? {
        guard let id else { return nil }
        return accounts.first { $0.id == id }
    }

    func card(_ id: UUID?) -> Card? {
        guard let id else { return nil }
        return cards.first { $0.id == id }
    }

    /// 英雄卡大字：「NT$81.7萬」；有幣別查不到匯率「約 NT$71.4萬」
    var cashText: String { (cashIsApprox ? "約 " : "") + cash.ntdWanString }

    /// 英雄卡大字下面那一句：「卡費還沒扣 NT$4.8萬」（有待交割「卡費還沒扣 NT$4.8萬、交割 NT$5.2萬」）；都沒有＝nil
    var notYetDebitedText: String? {
        var parts: [String] = []
        if owedCards > 0.5 { parts.append("卡費還沒扣 " + owedCards.ntdWanString) }
        if pendingSettlement > 0.5 {
            parts.append(parts.isEmpty ? "交割還沒扣 " + pendingSettlement.ntdWanString
                                       : "交割 " + pendingSettlement.ntdWanString)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "、")
    }

    /// 「為什麼數字變了」：v2 第一次打開財富頁說明一次（judge §9-1：寫你自己的數字）。
    /// 沒有卡費還沒扣的帳戶、也沒有「以前沖正過、之後還沒對過存摺」的帳戶＝nil
    var passbookNotice: (title: String, message: String)? {
        let visible = banks.filter { !$0.hidden }
        let changed = visible.filter { $0.cardOwed > 0.5 }.sorted { $0.cardOwed > $1.cardOwed }
        // [v25.563 最後裁定] 以前的沖正（v1 刷卡當天扣時補到跟存摺一樣的差額）v2 照舊當加減（§1-8），
        // 卡費改在截止日才扣後，這種帳戶會多出「沖正那天還沒扣的卡費」：點名請他對一次存摺
        let adjusted = visible.filter { WealthFacts.hasLegacyAdjustSinceAnchor($0) }
        guard !changed.isEmpty || !adjusted.isEmpty else { return nil }
        var parts: [String] = []
        if !changed.isEmpty {
            var lines: [String] = []
            for a in changed.prefix(3) {
                let before = WealthFormat.ntd(a.ntdTotal - a.cardOwed)
                let after = WealthFormat.ntd(a.ntdTotal)
                lines.append("\(a.name)：\(before) → \(after)（卡費 \(WealthFormat.ntd(a.cardOwed)) 還沒扣）")
            }
            if changed.count > 3 { lines.append("另外 \(changed.count - 3) 個帳戶也一樣") }
            parts.append(lines.joined(separator: "\n"))
            parts.append("以前刷卡當天就從銀行扣；現在跟存摺一樣，卡費在繳款截止日才扣，所以數字比以前多。"
                         + "還沒扣的卡費寫在每一列下面的「扣完能用」。")
        } else {
            parts.append("以前刷卡當天就從銀行扣；現在跟存摺一樣，卡費在繳款截止日才扣。")
        }
        if !adjusted.isEmpty {
            var names: String = adjusted.prefix(3).map { $0.name }.joined(separator: "、")
            if adjusted.count > 3 { names += " 等 \(adjusted.count) 個帳戶" }
            parts.append(names + "以前沖正過：那是照以前的算法（刷卡當天就扣）補的差額，現在照樣加減，"
                         + "數字可能多了沖正那天還沒扣的卡費，請對一次存摺。")
        }
        parts.append("跟存摺對不上時，打開帳戶，按「銀行存款」右邊的＋、選幣別，再切到「對存摺」，打存摺上的數字，以後就從那裡往後算。")
        return ("銀行的數字改成跟存摺一樣", parts.joined(separator: "\n\n"))
    }

    /// 最近一次對存摺之後（從沒對過＝全部）還有以前記的沖正（isAdjust、沒有 kind）。
    /// 對存摺那天同一天的沖正已經被對存摺吸收（同一天對存摺最後算），所以只看「之後」的
    private static func hasLegacyAdjustSinceAnchor(_ a: Account) -> Bool {
        let last: Date? = a.lastAnchorDate
        return a.ledger.contains(where: { (row: WealthLedgerRow) -> Bool in
            guard row.kind == .legacyAdjust else { return false }
            guard let anchorDay = last else { return true }
            return WealthCal.day(row.date) > anchorDay
        })
    }

    // MARK: 一個帳戶

    struct Account: Identifiable {
        let id: UUID
        /// 暱稱 → 銀行名 → 標題
        let name: String
        /// 銀行名 → 標題
        let bankName: String
        let nickname: String?
        let isSecurities: Bool
        /// 帳戶種類是定存
        let isFixedDeposit: Bool
        /// 收起來了（帳本 hidden）
        let hidden: Bool
        /// 算進存款合計（帳本 countInCash，沒設＝算）
        let countsInCash: Bool
        /// 這個帳戶有的幣別（台幣在前，其他照出現的順序；D20：月薪入帳、記帳扣款的幣別也算）
        let currencies: [String]
        /// 每個幣別的存摺上（今天結束時）
        let balances: [String: Double]
        /// 換台幣的合計（查不到匯率的不算）
        let ntdTotal: Double
        /// 有數字、但查不到匯率的幣別
        let unknownCodes: [String]
        /// 從這裡扣的卡「要繳＋還沒出帳」（台幣）
        let cardOwed: Double
        /// 從這裡交割、還沒到交割日的股票款（台幣）
        let pendingSettlement: Double
        /// 最近一次對存摺（那天）
        let lastAnchorDate: Date?
        /// 明細：今天以前的，新到舊（judge §8 v2：明細不放未來的列）
        let ledger: [WealthLedgerRow]
        /// 接下來 35 天（明天起），舊到新，每一列有扣完剩多少
        let upcoming: [WealthLedgerRow]
        /// 接下來 35 天最低（台幣；含今天的數字）；沒有接下來的事＝nil
        let lowestNTD: Double?
        let lowestDate: Date?

        /// 還沒扣＝卡費＋待交割
        var notYetDebited: Double { cardOwed + pendingSettlement }
        /// 扣完能用＝存摺上 − 還沒扣
        var usable: Double { ntdTotal - notYetDebited }
        var hasUnknownRate: Bool { !unknownCodes.isEmpty }

        /// 這個幣別的存摺上（台幣的 "TWD"／空白都算台幣）
        func balance(_ code: String) -> Double {
            balances[WealthFacts.norm(code)] ?? 0
        }

        /// 只有一個幣別有數字（或都是 0）時是那個幣別；好幾個幣別都有數字是 nil
        var singleCode: String? {
            let nonZero = balances.filter { Swift.abs($0.value) > 0.004 }.map(\.key)
            if nonZero.count > 1 { return nil }
            return nonZero.first ?? currencies.first ?? "NT$"
        }

        /// 列表那一列的金額：「NT$128,400」「美金 3,200.00」；好幾個幣別「約 NT$23.4萬」
        var balanceText: String {
            if let c = singleCode { return WealthFormat.money(balance(c), code: c) }
            return "約 " + ntdTotal.ntdWanString
        }

        /// 底下小字：查不到匯率「沒有匯率」；有還沒扣的「扣完能用 NT$5.3萬」；都沒有＝nil
        var footnoteText: String? {
            if hasUnknownRate { return "沒有匯率" }
            if notYetDebited > 0.5 { return "扣完能用 " + usable.ntdWanString }
            return nil
        }

        /// 選單括號裡的數字：「存摺 NT$12.8萬」「存摺 美金 3,200」；好幾個幣別「存摺 約 NT$23.4萬」；查不到匯率加「・沒有匯率」
        var pickerBalanceText: String {
            let body: String
            if let c = singleCode {
                body = FinanceRates.isNTD(c) ? balance(c).ntdWanString : balance(c).wanString(symbolPrefix: c)
            } else {
                body = "約 " + ntdTotal.ntdWanString
            }
            return "存摺 " + body + (hasUnknownRate ? "・沒有匯率" : "")
        }

        /// 選單一列：「台新銀行（存摺 NT$12.8萬）」；有暱稱「薪轉（台新銀行・存摺 NT$12.8萬）」
        var pickerLabel: String {
            if let n = nickname { return "\(n)（\(bankName)・\(pickerBalanceText)）" }
            return "\(bankName)（\(pickerBalanceText)）"
        }

        /// 好幾個幣別時子選單那一列：「美金（存摺 美金 3,200）」「NT$（存摺 NT$13.2萬）」
        func pickerLabel(code: String) -> String {
            let c = WealthFacts.norm(code)
            let v = balance(c)
            let text = FinanceRates.isNTD(c) ? v.ntdWanString : v.wanString(symbolPrefix: c)
            return "\(c)（存摺 \(text)）"
        }
    }

    // MARK: 一張信用卡

    struct Card: Identifiable {
        let id: UUID
        /// 卡名 → 標題
        let name: String
        let isDisabled: Bool
        /// 額度（沒填或 0＝nil）
        let limit: Double?
        /// 實際拿來算的結帳日、繳款截止日
        let billingDay: Int
        let paymentDay: Int
        let billingDayMissing: Bool
        let paymentDayMissing: Bool
        /// 這一期（還沒結帳的）從哪個帳戶扣；沒設或帳戶不在了是 nil
        let payerId: UUID?
        let payerName: String?
        /// 每一期帳單，舊到新（含還沒結帳的這一期）
        let statements: [WealthStatement]
        /// 每一筆刷卡，舊到新（台幣）
        let entries: [WealthCardEntry]
        /// 要繳：已經結帳、截止日還沒到
        let due: Double
        /// 最早一期還沒繳的帳單
        let dueStatement: WealthStatement?
        /// 還沒出帳：還沒結帳的這一期，刷到今天
        let unbilled: Double
        let unbilledCount: Int
        /// 這一期的結帳日、截止日
        let nextClose: Date
        let nextDue: Date
        /// 最近一期已經扣的帳單
        let lastPaid: WealthStatement?

        /// 卡費還沒扣＝要繳＋還沒出帳
        var owed: Double { due + unbilled }
        /// 還能刷＝額度 − 要繳 − 還沒出帳（不小於 0）；沒填額度＝nil
        var available: Double? {
            guard let l = limit else { return nil }
            return Swift.max(0, l - owed)
        }
        /// 使用率＝(要繳＋還沒出帳)÷額度；沒填額度＝nil
        var usage: Double? {
            guard let l = limit, l > 0 else { return nil }
            return owed / l
        }
        /// 0 很寬鬆（< 30%）、1 正常（< 50%）、2 偏高（< 90%）、3 快刷滿了
        var usageTier: Int {
            let u = usage ?? 0
            if u < 0.3 { return 0 }
            if u < 0.5 { return 1 }
            if u < 0.9 { return 2 }
            return 3
        }
        var usageTierName: String {
            switch usageTier {
            case 0: return "很寬鬆"
            case 1: return "正常"
            case 2: return "偏高"
            default: return "快刷滿了"
            }
        }
        /// 「額度用了 8.3%・很寬鬆」；沒填額度＝nil
        var usageText: String? {
            guard let u = usage else { return nil }
            return "額度用了 \(WealthFormat.percent(u))・\(usageTierName)"
        }
    }

    // MARK: - 工具

    /// 台幣一律寫 "NT$"（"TWD"、空白都算台幣，FinanceRates.isNTD）
    static func norm(_ code: String) -> String { FinanceRates.isNTD(code) ? "NT$" : code }

    /// 帳戶、卡的名字：暱稱 → 銀行名（卡：卡名）→ 標題
    static func displayName(of m: LifeMilestone, book: WealthBook) -> String {
        if let n = book.account(m.id).trimmedNickname { return n }
        if m.financeSubCategory == .creditCard {
            if let c = m.cardName?.trimmingCharacters(in: .whitespaces), !c.isEmpty { return c }
            return m.title
        }
        return bankName(of: m)
    }

    /// 銀行名 → 標題
    static func bankName(of m: LifeMilestone) -> String {
        if let b = m.bankName?.trimmingCharacters(in: .whitespaces), !b.isEmpty { return b }
        return m.title
    }

    /// 這筆真的存提款紀錄算存摺上時要不要跳過（被別的算法取代；v1 bankDepositIsReplaced 搬過來）：
    /// 連到刷卡支出（卡費帳單取代）、連到週期性固定支出／收入（逐期展開取代）、
    /// 連到跟股票有關的收入／支出而那檔股票自己有交割帳戶（銀行的錢只看股票自己寫的交割、股利；v1 W8）
    static func isReplaced(_ dep: BankDeposit, expensesById: [UUID: Expense], incomesById: [UUID: Income],
                           stocksById: [UUID: Stock]) -> Bool {
        guard let linkedId = dep.linkedExpenseId else { return false }
        if let exp = expensesById[linkedId] {
            if exp.linkedCreditCardMilestoneId != nil { return true }
            if exp.expenseType == .fixed, exp.recurrence != nil { return true }
            if let sid = exp.linkedStockId, stocksById[sid]?.hasOwnSettlementAccount == true { return true }
            return false
        }
        if let inc = incomesById[linkedId] {
            if inc.period != .once { return true }
            if let sid = inc.linkedStockId, stocksById[sid]?.hasOwnSettlementAccount == true { return true }
        }
        return false
    }

    /// 這個帳戶有哪些幣別（D20；記帳、收入、股票、房屋水電、AI 記帳的選單都用這一支）：
    /// 存提款紀錄（兩個方向都算）、入這裡的收入、扣這裡的記帳、交割在這裡的股票用過的幣別；台幣在前；都沒有＝["NT$"]
    static func currencies(forAccount account: LifeMilestone, expenses: [Expense], incomes: [Income],
                           stocks: [Stock]) -> [String] {
        var seen: [String] = []
        func add(_ raw: String?) {
            guard let raw else { return }
            let c = norm(raw)
            if !seen.contains(c) { seen.append(c) }
        }
        for d in account.bankDeposits ?? [] { add(d.currencyCode) }
        for i in incomes where i.linkedBankMilestoneId == account.id { add(i.linkedBankCurrency ?? "NT$") }
        for e in expenses where e.linkedBankMilestoneId == account.id && e.linkedCreditCardMilestoneId == nil {
            add(e.linkedBankCurrency ?? "NT$")
        }
        for s in stocks where s.linkedBankMilestoneId == account.id || s.linkedSecuritiesMilestoneId == account.id {
            add(s.linkedBankCurrency ?? "NT$")
        }
        if seen.isEmpty { return ["NT$"] }
        if let i = seen.firstIndex(of: "NT$"), i > 0 {
            seen.remove(at: i)
            seen.insert("NT$", at: 0)
        }
        return seen
    }

    /// 一張卡到 until 那天（含）的每一筆刷卡（台幣；定期扣款每一期一筆，期數一次算、金額照當時），舊到新
    static func cardEntries(forCard cardId: UUID, expenses: [Expense], through until: Date,
                            rates: FinanceRates) -> [WealthCardEntry] {
        let limit = WealthCal.day(until)
        var out: [WealthCardEntry] = []
        for exp in expenses where exp.linkedCreditCardMilestoneId == cardId {
            if exp.expenseType == .fixed, exp.recurrence != nil {
                let hist = exp.amountHistory.sorted { $0.date < $1.date }
                for p in WealthSchedule.fixedPeriods(exp, through: until) {
                    let raw = WealthSchedule.amount(at: p.date, current: exp.amount, sortedHistory: hist)
                    out.append(WealthCardEntry(
                        id: "cc-\(exp.id.uuidString)-\(p.index)", date: p.date,
                        amount: WealthSchedule.ntd(of: exp, raw: raw, rates: rates),
                        expenseId: exp.id, isRecurring: p.index > 0))
                }
            } else if WealthCal.day(exp.date) <= limit {
                out.append(WealthCardEntry(
                    id: "cc-\(exp.id.uuidString)", date: exp.date,
                    amount: WealthSchedule.ntd(of: exp, raw: exp.amount, rates: rates),
                    expenseId: exp.id, isRecurring: false))
            }
        }
        return out.sorted { $0.date < $1.date }
    }

    /// 把刷卡分成一期一期的帳單（舊到新）。payer：這一期從哪個帳戶扣（只認還在的銀行帳戶）
    static func statements(of card: LifeMilestone, entries: [WealthCardEntry], history: [WealthPayFrom]?,
                           bankIds: Set<UUID>, today: Date) -> [WealthStatement] {
        let b = WealthCardCycle.billingDay(card.billingDay)
        let p = WealthCardCycle.paymentDay(card.paymentDay)
        var sums: [Date: Double] = [:]
        var counts: [Date: Int] = [:]
        for e in entries {
            let close = WealthCardCycle.statementClose(for: e.date, billingDay: b)
            sums[close, default: 0] += e.amount
            counts[close, default: 0] += 1
        }
        let t = WealthCal.day(today)
        var out: [WealthStatement] = []
        for close in sums.keys.sorted() {
            let key = WealthCal.monthKey(close)
            let due = WealthCardCycle.dueDate(close: close, billingDay: b, paymentDay: p)
            let start = WealthCal.addDays(1, to: WealthCardCycle.previousClose(close, billingDay: b))
            let raw = WealthCardCycle.payer(statementKey: key, linked: card.linkedBankMilestoneId, history: history)
            let payer: UUID? = raw.flatMap { bankIds.contains($0) ? $0 : nil }
            out.append(WealthStatement(
                key: key, start: start, close: close, due: due,
                amount: sums[close] ?? 0, count: counts[close] ?? 0, payerId: payer,
                isClosed: close < t, isPaid: WealthCal.day(due) <= t))
        }
        return out
    }

    /// 一張卡的每一期帳單（刪卡時用：每一期照它的扣款帳戶寫回一筆，存摺上的數字不變）
    static func cardStatements(for card: LifeMilestone, milestones: [LifeMilestone], book: WealthBook,
                               expenses: [Expense], rates: FinanceRates, now: Date) -> [WealthStatement] {
        let bankIds = Set(milestones.filter {
            $0.category == .achievement && $0.financeSubCategory == .bank
        }.map(\.id))
        let today = WealthCal.day(now)
        let entries = cardEntries(forCard: card.id, expenses: expenses, through: today, rates: rates)
        return statements(of: card, entries: entries, history: book.card(card.id).payFrom,
                          bankIds: bankIds, today: today)
    }

    // MARK: - 換匯（轉帳）

    /// 轉帳預設的匯率（1 外幣＝幾台幣）：剛好一邊是台幣、另一邊設定裡查得到匯率才有；其他＝nil
    static func defaultTransferRate(from fromCode: String, to toCode: String, rates: FinanceRates) -> Double? {
        let f = norm(fromCode), t = norm(toCode)
        if f == t { return nil }
        if f == "NT$" { return rates.known(t) }
        if t == "NT$" { return rates.known(f) }
        return nil
    }

    /// 轉出 amount（fromCode）對方收到多少（toCode）。rate：1 外幣＝幾台幣（只在一邊是台幣時用，可以是你改過的）；
    /// 兩邊都是外幣用設定裡的匯率。台幣四捨五入到元、外幣到 0.01。換不了（查不到匯率）＝nil
    /// 例：台幣 50,000 → 美金、匯率 32.05 → 1,560.06
    static func transferAmount(_ amount: Double, from fromCode: String, to toCode: String, rate: Double?,
                               rates: FinanceRates) -> Double? {
        let f = norm(fromCode), t = norm(toCode)
        if f == t { return amount }
        let ntd: Double
        if f == "NT$" {
            ntd = amount
        } else if t == "NT$", let r = rate, r > 0 {
            ntd = amount * r
        } else if let r = rates.known(f), r > 0 {
            ntd = amount * r
        } else {
            return nil
        }
        if t == "NT$" { return ntd.rounded() }
        let toRate: Double?
        if f == "NT$", let r = rate, r > 0 { toRate = r } else { toRate = rates.known(t) }
        guard let r = toRate, r > 0 else { return nil }
        return (ntd / r * 100).rounded() / 100
    }

    // MARK: - 快取 key

    /// LifeStore.wealthFacts 的快取 key：里程碑／財富帳本的 revision＋記帳、理財的 modifyID＋匯率＋日期
    static func cacheKey(revision: Int, expense: ExpenseStore, finance: FinanceStore, now: Date) -> String {
        let rateSig = expense.currencyRates.map { "\($0.code)=\($0.rate)" }.joined(separator: ",")
        return "\(revision)|\(expense.modifyID.uuidString)|\(finance.modifyID.uuidString)|\(rateSig)|\(WealthCal.dayKey(now))"
    }

    // MARK: - build

    /// 一次建好全部（很重：展開每一期）。全 App 請用 LifeStore.wealthFacts(expense:finance:) 拿快取的
    static func build(milestones: [LifeMilestone], book: WealthBook, expenses: [Expense], incomes: [Income],
                      stocks: [Stock], rates: FinanceRates, now: Date) -> WealthFacts {
        let today = WealthCal.day(now)
        let horizon = WealthCal.addDays(upcomingDays, to: today)
        let finance = milestones.filter { $0.category == .achievement && $0.financeSubCategory != nil }
        let bankMs = finance.filter { $0.financeSubCategory == .bank }
        let securityMs = finance.filter { $0.financeSubCategory == .securities }
        let cardMs = finance.filter { $0.financeSubCategory == .creditCard }
        let bankIds = Set(bankMs.map(\.id))

        var nameById: [UUID: String] = [:]
        for m in finance { nameById[m.id] = displayName(of: m, book: book) }
        let expensesById = Dictionary(expenses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let incomesById = Dictionary(incomes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let stocksById = Dictionary(stocks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var dividendIds = Set<UUID>()
        for s in stocks { dividendIds.formUnion(WealthIDs.dividendDepositIds(of: s)) }

        // 卡：每一期帳單，記到「那一期的扣款帳戶」
        var cards: [Card] = []
        var billsByAccount: [UUID: [BillRef]] = [:]
        var owedByAccount: [UUID: Double] = [:]
        // 接下來 35 天的卡費也要：還沒結帳的那一期刷到今天的先當帳單（寫「約」）
        for c in cardMs {
            let entries = cardEntries(forCard: c.id, expenses: expenses, through: today, rates: rates)
            let stmts = statements(of: c, entries: entries, history: book.card(c.id).payFrom,
                                   bankIds: bankIds, today: today)
            let card = makeCard(c, name: nameById[c.id] ?? c.title, entries: entries, statements: stmts,
                                today: today, book: book, bankIds: bankIds, nameById: nameById)
            cards.append(card)
            for s in stmts {
                guard let payer = s.payerId, Swift.abs(s.amount) > 0.004 else { continue }
                billsByAccount[payer, default: []].append(BillRef(cardId: c.id, cardName: card.name, statement: s))
                if !s.isPaid { owedByAccount[payer, default: 0] += s.amount }
            }
        }

        // 直接扣銀行的週期性固定支出、入銀行的週期性收入，照帳戶分好（一次掃）
        var fixedByBank: [UUID: [Expense]] = [:]
        for e in expenses where e.expenseType == .fixed && e.recurrence != nil && e.linkedCreditCardMilestoneId == nil {
            if let bid = e.linkedBankMilestoneId { fixedByBank[bid, default: []].append(e) }
        }
        var incomesByBank: [UUID: [Income]] = [:]
        for i in incomes where i.period != .once {
            if let bid = i.linkedBankMilestoneId { incomesByBank[bid, default: []].append(i) }
        }

        let ctx = BuildContext(today: today, horizon: horizon, rates: rates, book: book,
                               expensesById: expensesById, incomesById: incomesById, stocksById: stocksById,
                               dividendIds: dividendIds, nameById: nameById,
                               expenses: expenses, incomes: incomes, stocks: stocks)
        var accounts: [Account] = []
        for m in bankMs {
            accounts.append(makeAccount(m, isSecurities: false, ctx: ctx,
                                        fixed: fixedByBank[m.id] ?? [], incomes: incomesByBank[m.id] ?? [],
                                        bills: billsByAccount[m.id] ?? [], cardOwed: owedByAccount[m.id] ?? 0))
        }
        for m in securityMs {
            accounts.append(makeAccount(m, isSecurities: true, ctx: ctx, fixed: [], incomes: [], bills: [], cardOwed: 0))
        }

        // 整頁
        var cash: Double = 0, live: Double = 0, fixedDeposit: Double = 0, foreign: Double = 0
        var pending: Double = 0
        var unknown: [String] = []
        for a in accounts where !a.isSecurities && !a.hidden && a.countsInCash {
            for (code, value) in a.balances {
                guard let r = rates.known(code) else { continue }
                let v = value * r
                cash += v
                if a.isFixedDeposit { fixedDeposit += v }
                else if code == "NT$" { live += v }
                else { foreign += v }
            }
            for c in a.unknownCodes where !unknown.contains(c) { unknown.append(c) }
            pending += a.pendingSettlement
        }
        let owed = cards.reduce(0.0) { $0 + $1.owed }

        // 要確認（v2 只偵測）：#6 卡沒填結帳日／繳款截止日、#9 查不到匯率
        var checks: [WealthCheck] = []
        for c in cards where !c.isDisabled && (c.billingDayMissing || c.paymentDayMissing) {
            checks.append(WealthCheck(id: "card-days-\(c.id.uuidString)", kind: .cardDaysMissing,
                                      text: missingDaysText(c), accountIds: [c.id]))
        }
        for code in unknown {
            let owners = accounts.filter { !$0.isSecurities && $0.unknownCodes.contains(code) }
            let names = owners.map(\.name).joined(separator: "、")
            let amounts = owners.map { WealthFormat.money($0.balance(code), code: code) }.joined(separator: "、")
            checks.append(WealthCheck(id: "rate-\(code)", kind: .unknownRate,
                                      text: "設定裡找不到「\(code)」的匯率，\(names)的 \(amounts) 先不算進合計",
                                      accountIds: owners.map(\.id)))
        }

        return WealthFacts(now: now, today: today, accounts: accounts, cards: cards,
                           cash: cash, cashIsApprox: !unknown.isEmpty, live: live, fixedDeposit: fixedDeposit,
                           foreign: foreign, owedCards: owed, pendingSettlement: pending,
                           unknownCodes: unknown, checks: checks)
    }

    // MARK: - build 的零件

    /// 一期帳單記到哪個帳戶
    private struct BillRef {
        let cardId: UUID
        let cardName: String
        let statement: WealthStatement
    }

    private struct BuildContext {
        let today: Date
        let horizon: Date
        let rates: FinanceRates
        let book: WealthBook
        let expensesById: [UUID: Expense]
        let incomesById: [UUID: Income]
        let stocksById: [UUID: Stock]
        let dividendIds: Set<UUID>
        let nameById: [UUID: String]
        let expenses: [Expense]
        let incomes: [Income]
        let stocks: [Stock]
    }

    /// 存摺上的一筆（排好照日期累加）
    private struct Event {
        let day: Date
        let code: String
        /// 加減（對存摺不用）
        let delta: Double
        /// 對存摺：存摺上的數字
        let anchor: Double?
        /// 同一天的先後（真的紀錄照存的順序在前，展開的在後；對存摺一律最後）
        let seq: Int
        let row: WealthLedgerRow
    }

    private static func makeCard(_ c: LifeMilestone, name: String, entries: [WealthCardEntry],
                                 statements stmts: [WealthStatement], today: Date, book: WealthBook,
                                 bankIds: Set<UUID>, nameById: [UUID: String]) -> Card {
        let b = WealthCardCycle.billingDay(c.billingDay)
        let p = WealthCardCycle.paymentDay(c.paymentDay)
        let nextClose = WealthCardCycle.statementClose(for: today, billingDay: b)
        let nextDue = WealthCardCycle.dueDate(close: nextClose, billingDay: b, paymentDay: p)
        var due: Double = 0
        var dueStatement: WealthStatement? = nil
        var unbilled: Double = 0
        var unbilledCount = 0
        var lastPaid: WealthStatement? = nil
        for s in stmts {
            if !s.isClosed {
                unbilled += s.amount
                unbilledCount += s.count
            } else if !s.isPaid {
                due += s.amount
                if dueStatement == nil { dueStatement = s }
            } else {
                lastPaid = s
            }
        }
        let rawPayer = WealthCardCycle.payer(statementKey: WealthCal.monthKey(nextClose),
                                             linked: c.linkedBankMilestoneId, history: book.card(c.id).payFrom)
        let payer: UUID? = rawPayer.flatMap { bankIds.contains($0) ? $0 : nil }
        let limit: Double? = (c.creditLimit ?? 0) > 0 ? c.creditLimit : nil
        return Card(id: c.id, name: name, isDisabled: c.isDisabled == true, limit: limit,
                    billingDay: b, paymentDay: p,
                    billingDayMissing: c.billingDay == nil, paymentDayMissing: c.paymentDay == nil,
                    payerId: payer, payerName: payer.flatMap { nameById[$0] },
                    statements: stmts, entries: entries, due: due, dueStatement: dueStatement,
                    unbilled: unbilled, unbilledCount: unbilledCount,
                    nextClose: nextClose, nextDue: nextDue, lastPaid: lastPaid)
    }

    /// 「@GoGo 沒填結帳日，先當每月 25 日結帳、隔月 15 日繳」
    private static func missingDaysText(_ c: Card) -> String {
        let payWhen = c.paymentDay <= c.billingDay ? "隔月" : "當月"
        if c.billingDayMissing && c.paymentDayMissing {
            return "\(c.name) 沒填結帳日和繳款截止日，先當每月 \(c.billingDay) 日結帳、\(payWhen) \(c.paymentDay) 日繳"
        }
        if c.billingDayMissing {
            return "\(c.name) 沒填結帳日，先當每月 \(c.billingDay) 日結帳"
        }
        return "\(c.name) 沒填繳款截止日，先當\(payWhen) \(c.paymentDay) 日繳"
    }

    /// 真的紀錄是哪一種、標題寫什麼
    private static func classify(_ dep: BankDeposit, ctx: BuildContext) -> (kind: WealthLedgerRow.Kind, title: String) {
        if dep.isAnchor { return (.anchor, "對存摺") }
        if dep.isAdjust { return (.legacyAdjust, "沖正") }
        if dep.isTransfer {
            let other = dep.counterpartyId.flatMap { ctx.nameById[$0] } ?? "別的帳戶"
            if dep.isWithdrawal { return (.transferOut, "轉給 \(other)") }
            return (.transferIn, "來自 \(other)")
        }
        if dep.kind == BankDeposit.kindInterest { return (.interest, "利息") }
        if dep.kind == BankDeposit.kindFee { return (.fee, "手續費") }
        if let sid = dep.linkedStockId {
            let name = ctx.stocksById[sid]?.name ?? "股票"
            if ctx.dividendIds.contains(dep.id) { return (.dividend, "\(name) 股利") }
            if dep.isWithdrawal { return (.stockBuy, "買 \(name)") }
            return (.stockSell, "賣 \(name)")
        }
        if let lid = dep.linkedExpenseId {
            if let e = ctx.expensesById[lid] { return (.expense, e.title) }
            if let i = ctx.incomesById[lid] { return (.income, i.title) }
        }
        if dep.isWithdrawal { return (.withdrawal, "提款") }
        return (.deposit, "存款")
    }

    private static func makeAccount(_ m: LifeMilestone, isSecurities: Bool, ctx: BuildContext,
                                    fixed: [Expense], incomes: [Income], bills: [BillRef],
                                    cardOwed: Double) -> Account {
        let rates = ctx.rates
        let prefs = ctx.book.account(m.id)
        var events: [Event] = []

        // ① 真的紀錄（存提款、對存摺、轉帳、記帳一次性、股票交割與股利）
        let deposits = m.bankDeposits ?? []
        var pendingByDay: [Date: [String: Double]] = [:]
        for (i, dep) in deposits.enumerated() {
            if isReplaced(dep, expensesById: ctx.expensesById, incomesById: ctx.incomesById,
                          stocksById: ctx.stocksById) { continue }
            let day = WealthCal.day(dep.date)
            let code = norm(dep.currencyCode)
            // 待交割：日期還沒到的股票款（同一天買賣相抵；股利不算）
            if !isSecurities, dep.linkedStockId != nil, !ctx.dividendIds.contains(dep.id), !dep.isTransfer,
               day > ctx.today {
                pendingByDay[day, default: [:]][code, default: 0] += dep.isWithdrawal ? dep.amount : -dep.amount
            }
            guard day <= ctx.horizon else { continue }
            let c = classify(dep, ctx: ctx)
            let anchorValue: Double? = dep.isAnchor ? dep.anchorAmount : nil
            let row = WealthLedgerRow(
                id: dep.id.uuidString, date: dep.date, code: code,
                amount: anchorValue ?? dep.amount, isOutflow: dep.isWithdrawal, kind: c.kind, title: c.title,
                note: dep.note, depositId: dep.id,
                expenseId: dep.linkedExpenseId.flatMap { lid -> UUID? in ctx.expensesById[lid] == nil ? nil : lid },
                incomeId: dep.linkedExpenseId.flatMap { lid -> UUID? in ctx.incomesById[lid] == nil ? nil : lid },
                stockId: dep.linkedStockId, transferPairId: dep.transferPairId)
            events.append(Event(day: day, code: code, delta: dep.isWithdrawal ? -dep.amount : dep.amount,
                                anchor: anchorValue, seq: i, row: row))
        }

        // ② 直接扣這裡的週期性固定支出（期數一次算、金額照那一期當時）
        var seq = 100_000
        for exp in fixed {
            let hist = exp.amountHistory.sorted { $0.date < $1.date }
            for p in WealthSchedule.fixedPeriods(exp, through: ctx.horizon) {
                let raw = WealthSchedule.amount(at: p.date, current: exp.amount, sortedHistory: hist)
                let ntd = WealthSchedule.ntd(of: exp, raw: raw, rates: rates)
                let original: (amount: Double, code: String)? = exp.originalCurrencyAmount.map { (amount: raw, code: $0.code) }
                let w = rates.accountAmount(ntd: ntd, original: original, into: exp.linkedBankCurrency ?? "NT$")
                let code = norm(w.code)
                let row = WealthLedgerRow(
                    id: "fx-\(exp.id.uuidString)-\(p.index)", date: p.date, code: code, amount: w.amount,
                    isOutflow: true, kind: .fixedExpense, title: exp.title, expenseId: exp.id)
                events.append(Event(day: WealthCal.day(p.date), code: code, delta: -w.amount, anchor: nil,
                                    seq: seq, row: row))
                seq += 1
            }
        }

        // ③ 入這裡的月薪、年薪（期數一次算、金額照那一期當時）
        for inc in incomes {
            let hist = (inc.amountHistory ?? []).sorted { $0.date < $1.date }
            for p in WealthSchedule.incomePeriods(inc, through: ctx.horizon) {
                let raw = WealthSchedule.amount(at: p.date, current: inc.amount, sortedHistory: hist)
                let w = rates.accountAmount(ntd: raw, into: inc.linkedBankCurrency ?? "NT$")
                let code = norm(w.code)
                let row = WealthLedgerRow(
                    id: "in-\(inc.id.uuidString)-\(p.index)", date: p.date, code: code, amount: w.amount,
                    isOutflow: false, kind: .recurringIncome, title: inc.title, incomeId: inc.id)
                events.append(Event(day: WealthCal.day(p.date), code: code, delta: w.amount, anchor: nil,
                                    seq: seq, row: row))
                seq += 1
            }
        }

        // ④ 信用卡帳單：在繳款截止日從這裡扣（v2 一律當自動扣全額）
        for bill in bills {
            let s = bill.statement
            let day = WealthCal.day(s.due)
            guard day <= ctx.horizon else { continue }
            let row = WealthLedgerRow(
                id: "bill-\(bill.cardId.uuidString)-\(s.key)", date: s.due, code: "NT$", amount: s.amount,
                isOutflow: true, kind: .cardBill, title: "\(bill.cardName) \(s.label)",
                cardId: bill.cardId, statementKey: s.key, isEstimate: !s.isClosed)
            events.append(Event(day: day, code: "NT$", delta: -s.amount, anchor: nil, seq: seq, row: row))
            seq += 1
        }

        // 照日期累加：同一天先算每一筆，對存摺最後（記的是那天結束時）
        events.sort { a, b in
            if a.day != b.day { return a.day < b.day }
            let aa = a.anchor != nil, bb = b.anchor != nil
            if aa != bb { return !aa }
            return a.seq < b.seq
        }
        var running: [String: Double] = [:]
        var todayBalances: [String: Double] = [:]
        var crossedToday = false
        var past: [WealthLedgerRow] = []
        var future: [WealthLedgerRow] = []
        var lastAnchor: Date? = nil
        for e in events {
            if !crossedToday && e.day > ctx.today {
                todayBalances = running
                crossedToday = true
            }
            var row = e.row
            let before = running[e.code] ?? 0
            if let a = e.anchor {
                running[e.code] = a
                row.anchorDiff = ((a - before) * 100).rounded() / 100
                if e.day <= ctx.today { lastAnchor = e.day }
            } else {
                running[e.code] = before + e.delta
            }
            row.balanceAfter = running[e.code] ?? 0
            if e.day <= ctx.today { past.append(row) } else { future.append(row) }
        }
        if !crossedToday { todayBalances = running }

        // 台幣合計（查不到匯率的不算）
        var ntdTotal: Double = 0
        var unknown: [String] = []
        for (code, value) in todayBalances {
            if let r = rates.known(code) { ntdTotal += value * r }
            else if Swift.abs(value) > 0.004 { unknown.append(code) }
        }
        unknown.sort()

        // 接下來 35 天最低（台幣；從今天的數字開始）
        var lowest: Double? = nil
        var lowestDate: Date? = nil
        if !future.isEmpty {
            var run = todayBalances
            func ntdOf(_ b: [String: Double]) -> Double {
                var t: Double = 0
                for (code, value) in b { if let r = rates.known(code) { t += value * r } }
                return t
            }
            var low = ntdOf(run)
            var lowDay = ctx.today
            for e in events where e.day > ctx.today {
                if let a = e.anchor { run[e.code] = a } else { run[e.code, default: 0] += e.delta }
                let v = ntdOf(run)
                if v < low { low = v; lowDay = e.day }
            }
            lowest = low
            lowestDate = lowDay
        }

        // 待交割（台幣）
        var pendingNTD: Double = 0
        for (_, byCode) in pendingByDay {
            for (code, net) in byCode where net > 0 {
                if let r = rates.known(code) { pendingNTD += net * r }
            }
        }

        let codes = WealthFacts.currencies(forAccount: m, expenses: ctx.expenses, incomes: ctx.incomes,
                                           stocks: ctx.stocks)
        var balances = todayBalances
        for c in codes where balances[c] == nil { balances[c] = 0 }

        return Account(
            id: m.id, name: ctx.nameById[m.id] ?? bankName(of: m), bankName: bankName(of: m),
            nickname: prefs.trimmedNickname, isSecurities: isSecurities,
            isFixedDeposit: m.bankAccountType == .fixed,
            hidden: prefs.hidden == true, countsInCash: prefs.countInCash ?? true,
            currencies: codes, balances: balances, ntdTotal: ntdTotal, unknownCodes: unknown,
            cardOwed: cardOwed, pendingSettlement: isSecurities ? 0 : pendingNTD,
            lastAnchorDate: lastAnchor, ledger: Array(past.reversed()), upcoming: future,
            lowestNTD: lowest, lowestDate: lowestDate)
    }
}

// MARK: - [v25.563] 對存摺要的「App 算的數字」

extension WealthFacts {
    /// 這個帳戶這個幣別在 day 那天結束時，App 算的存摺上；excluding：不算那一筆（編輯以前的對存摺時，不算它自己）。
    /// 用同一套算法、把「今天」當成 day 重算一次（只在選日期、打開表單時算，打字時不算）
    static func passbookBalance(accountId: UUID, code: String, endOf day: Date, excluding: UUID?,
                                milestones: [LifeMilestone], book: WealthBook, expenses: [Expense],
                                incomes: [Income], stocks: [Stock], rates: FinanceRates) -> Double {
        var list = milestones
        if let ex = excluding, let i = list.firstIndex(where: { $0.id == accountId }) {
            list[i].bankDeposits = (list[i].bankDeposits ?? []).filter { $0.id != ex }
        }
        let f = build(milestones: list, book: book, expenses: expenses, incomes: incomes, stocks: stocks,
                      rates: rates, now: day)
        return f.account(accountId)?.balance(code) ?? 0
    }
}
