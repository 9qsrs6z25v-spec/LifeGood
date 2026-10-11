import Foundation

// [v25.532] 房貸／房地產的數字全 App 只算這一套。
//
// 以前同一間房子有三套期數規則（房貸項目自己用月份差、記帳固定支出卡用「起始那個月算第一期」、
// 接下來 30 天又是另一種），淨資產用的是「含利息還要繳」，還沒開始的段算 0，季繳年繳一律當月繳。
// 現在：
// - 期數照記帳 Expense.nextFixedDueDate：貸款第一期＝起始日＋1 個週期，第 k 期＝第一期＋(k−1) 個週期
//   （一次加，不一期一期累加），用 startOfDay 比，結束日當天那期算數。
// - 每一段的資料以連結的記帳固定支出為準（起始日、每期金額、週期、年限、結束日）；
//   房子身上的 mortgageItems 只當索引，沒有連結的舊段才讀它自己的欄位。
// - 還欠看本金：借款本金 P 依序取 你填的 → 記帳裡各段一樣的「總貸款金額」→ 購入價 − 房屋價金（推算）；
//   月利率用二分法從 P 和每個月的扣款反推（等於一個平均利率），之後每個月 B = B×(1+r) − 當月扣款。
//   算不出本金或利率時，才退回「含利息還要繳」。
// - 第一段開始之後，還沒開始的段也算欠；賣掉的房子一切停在賣出那天。

// MARK: - 房貸的數學（純函式，不碰 store）

enum HouseLoanMath {
    /// 一個週期幾個月（季繳 3、年繳 12）：月付換算用
    static func periodMonths(_ r: Recurrence) -> Int {
        switch r {
        case .monthly: return 1
        case .quarterly: return 3
        case .yearly: return 12
        }
    }

    /// 合約期數：取整跟 Expense.suggestedEndDate 一樣，期數 × 週期才會剛好落在記帳補上的結束日
    static func contractPeriods(years: Double, recurrence r: Recurrence) -> Int {
        // [v25.532] 年限最多算 100 年：輸入框打了一長串數字時 Int(...) 會直接閃退，期數迴圈也會跑不完
        let y: Double = years.isFinite ? min(max(years, 0), 100) : 0
        switch r {
        case .monthly:   return max(1, Int((y * 12).rounded()))
        case .quarterly: return max(1, Int((y * 12).rounded() / 3))
        case .yearly:    return max(1, Int(y.rounded()))
        }
    }

    /// 第一期扣款日＝起始日＋1 個週期（貸款規則，同 nextFixedDueDate）
    static func firstDue(start: Date, component: Calendar.Component, step: Int, calendar cal: Calendar) -> Date {
        cal.date(byAdding: component, value: step, to: start) ?? start
    }

    /// 第 k 期（從 1 起算）扣款日＝第一期＋(k−1) 個週期，一次加
    static func dueDate(_ k: Int, start: Date, component: Calendar.Component, step: Int, calendar cal: Calendar) -> Date {
        let first = firstDue(start: start, component: component, step: step, calendar: cal)
        return cal.date(byAdding: component, value: step * max(0, k - 1), to: first) ?? first
    }

    /// 扣款日 ≤ day 的期數（最多 limit 期）。先用月份差估，再前後微調，不用一期一期數。
    static func duesOnOrBefore(_ day: Date, start: Date, component: Calendar.Component, step: Int,
                               limit: Int, calendar cal: Calendar) -> Int {
        guard limit > 0, step > 0 else { return 0 }
        let target = cal.startOfDay(for: day)
        let first = cal.startOfDay(for: firstDue(start: start, component: component, step: step, calendar: cal))
        guard first <= target else { return 0 }
        func due(_ j: Int) -> Date {   // j 從 0 起算
            cal.startOfDay(for: cal.date(byAdding: component, value: step * j, to: first) ?? first)
        }
        let diff = cal.dateComponents([component], from: first, to: target).value(for: component) ?? 0
        var j = max(0, diff / step)
        var guardSteps = 0
        while j > 0 && due(j) > target && guardSteps < 8 { j -= 1; guardSteps += 1 }
        guardSteps = 0
        while due(j + 1) <= target && guardSteps < 8 { j += 1; guardSteps += 1 }
        return min(limit, j + 1)
    }

    /// 月利率 r：解 Σ CF_t ÷ (1+r)^t ＝ P（t＝從第一段起始那個月往後第幾個月）。
    /// 扣款總和 ≤ P、或要超過每月 2% 才湊得出來時回 nil（資料對不上，不硬算）。
    static func monthlyRate(principal p: Double, flows: [Double]) -> Double? {
        guard p > 0, !flows.isEmpty else { return nil }
        func pv(_ r: Double) -> Double {
            var sum = 0.0
            var factor = 1.0
            let g = 1 / (1 + r)
            for cf in flows {
                factor *= g
                if cf != 0 { sum += cf * factor }
            }
            return sum
        }
        guard pv(0) > p else { return nil }
        var lo = 0.0
        var hi = 0.02
        guard pv(hi) < p else { return nil }
        for _ in 0..<80 {
            let mid = (lo + hi) / 2
            if pv(mid) > p { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// 每個月月底的本金餘額：B_0＝P、B_t＝B_{t−1}×(1+r) − CF_t（index t＝0…T）
    static func balances(principal p: Double, rate r: Double, flows: [Double]) -> [Double] {
        var out: [Double] = [p]
        out.reserveCapacity(flows.count + 1)
        var b = p
        for cf in flows {
            b = b * (1 + r) - cf
            out.append(b)
        }
        return out
    }
}

extension Recurrence {
    /// 一個週期幾個月（季繳 3、年繳 12）
    var periodMonths: Int { HouseLoanMath.periodMonths(self) }
}

// MARK: - 記帳貸款的期數（固定支出卡、車貸、其他貸款共用）

extension Expense {
    /// [v25.532] 貸款扣到第幾期、一共幾期，跟房屋卡片同一套規則：
    /// 第一期＝起始日＋1 個週期、扣款日 ≤ 今天才算繳了；一共幾期照年限（跟 suggestedEndDate 同樣取整），
    /// 有結束日（停扣、賣掉）就截到結束日。沒填年限也沒結束日回 nil——不再用「總貸款金額 ÷ 月付」去推，
    /// 那是本金、沒算利息，推出來的期數會少一大截。
    func loanPeriods(asOf now: Date = Date(), calendar cal: Calendar = .current) -> (paid: Int, total: Int)? {
        guard isRecurringFixed, fixedCategory == .loan, let rec = recurrence else { return nil }
        let (component, step) = rec.componentValue
        var total: Int
        if let years = loanYears, years > 0 {
            total = HouseLoanMath.contractPeriods(years: years, recurrence: rec)
            if let end = endDate {
                total = min(total, HouseLoanMath.duesOnOrBefore(end, start: date, component: component, step: step,
                                                                limit: total, calendar: cal))
            }
        } else if let end = endDate {
            total = HouseLoanMath.duesOnOrBefore(end, start: date, component: component, step: step,
                                                 limit: 1200, calendar: cal)
        } else {
            return nil
        }
        guard total > 0 else { return nil }
        let paid = HouseLoanMath.duesOnOrBefore(now, start: date, component: component, step: step,
                                                limit: total, calendar: cal)
        return (paid, total)
    }
}

// MARK: - 一間房子的房貸與數字

/// 一間房子要寫在卡片、看板、項目卡、理財總覽上的數字（照 VehicleFacts：值型別、build 一次、到處讀）
struct HouseFacts: Equatable {
    enum PrincipalSource: Equatable {
        /// 你在編輯頁填的「當初跟銀行借了多少」
        case entered
        /// 記帳裡各段房貸的「總貸款金額」都一樣
        case ledger
        /// 購入價 − 房屋價金（推算，畫面上寫「約」）
        case estimated
        /// 算不出來
        case unknown
    }

    /// 一段房貸（一筆連到這間房子的房貸固定支出；沒連結的舊段讀房貸項目自己的欄位）
    struct Segment: Equatable, Identifiable {
        /// 房貸項目的 id；只在記帳裡、沒有房貸項目的那種用支出的 id
        let id: UUID
        let linkedExpenseId: UUID?
        /// 段名：房貸項目的名稱，空的寫「房貸」
        let title: String
        /// 段數超過一段、名字又全是「房貸」時，改成「第 n 段」
        var displayTitle: String
        let start: Date
        let component: Calendar.Component
        let step: Int
        /// 一個週期幾個月（季繳 3、年繳 12）
        let periodMonths: Int
        /// 每期金額（季繳就是一季的錢）
        let perPeriod: Double
        /// 合約期數（不看結束日、賣出日；反推利率用）
        let contractPeriods: Int
        /// 排定的期數：截到結束日（停扣、提前還清）
        let scheduledPeriods: Int
        /// 算數的期數：再截到賣出日
        let countedPeriods: Int
        /// 已繳期數（扣款日 ≤ 今天，賣掉的停在賣出日）
        let paidPeriods: Int
        let endDate: Date?
        /// 有連到記帳的固定支出
        let isLinked: Bool
        /// 年限沒填、期數是猜的（多半是預設的 240 期）
        let termIsGuess: Bool

        /// 換算成每個月（季繳 ÷3、年繳 ÷12）
        var monthly: Double { perPeriod / Double(max(1, periodMonths)) }
        var hasStarted: Bool { paidPeriods > 0 }
        var isDone: Bool { countedPeriods > 0 && paidPeriods >= countedPeriods }

        func due(_ k: Int, calendar cal: Calendar = .current) -> Date {
            HouseLoanMath.dueDate(k, start: start, component: component, step: step, calendar: cal)
        }
        var firstDue: Date { due(1) }
        /// 最後一期算數的扣款日（沒有算數的期數時是 nil）
        var lastCountedDue: Date? { countedPeriods > 0 ? due(countedPeriods) : nil }
        /// 照排定（不看賣出）的最後一期；過了這天這段就繳完或停掉了
        var lastScheduledDue: Date? { scheduledPeriods > 0 ? due(scheduledPeriods) : nil }

        /// day 當天或之後的下一期（第幾期、哪天）；已經沒有算數的期數就 nil
        func nextDue(onOrAfter day: Date, calendar cal: Calendar = .current) -> (date: Date, index: Int)? {
            guard countedPeriods > 0 else { return nil }
            let before = HouseLoanMath.duesOnOrBefore(cal.date(byAdding: .day, value: -1, to: day) ?? day,
                                                      start: start, component: component, step: step,
                                                      limit: countedPeriods, calendar: cal)
            let k = before + 1
            guard k <= countedPeriods else { return nil }
            return (due(k, calendar: cal), k)
        }

        /// 某個月份（monthStart 是那個月的 1 號）是不是在第一期與最後一期之間
        func isPaying(inMonth monthStart: Date, calendar cal: Calendar) -> Bool {
            guard let last = lastCountedDue else { return false }
            let firstMonth = HouseFacts.monthStart(firstDue, cal)
            let lastMonth = HouseFacts.monthStart(last, cal)
            return firstMonth <= monthStart && monthStart <= lastMonth
        }
    }

    /// 月付從某個月開始改變（例如寬限期結束）
    struct MonthlyChange: Equatable {
        let month: Date
        let monthly: Double
    }

    /// 算到哪一天：今天；賣掉的房子是賣出日
    var asOf = Date()
    /// 估值 V：賣掉的用成交價；沒填（≤ 0）用購入價
    var value: Double = 0
    var valueIsFallback = false
    var segments: [Segment] = []
    var principal: Double? = nil
    var principalSource: PrincipalSource = .unknown
    var monthlyRate: Double? = nil
    /// 全部要繳 S（本金＋利息；算數期數 × 每期金額）
    var scheduledTotal: Double = 0
    /// 已繳（已繳期數 × 每期金額）
    var paid: Double = 0
    /// 還欠的本金 B（算得出本金和利率才有）
    var balance: Double? = nil
    var principalRepaid: Double? = nil
    var interestPaid: Double? = nil
    var interestThisYear: Double? = nil
    /// 這個月房貸 M（這個月落在第一期到最後一期之間的各段，換算成每月）
    var monthlyMortgage: Double = 0
    var nextChange: MonthlyChange? = nil
    var paidCount = 0
    var totalCount = 0
    /// 最早一段的起始日、第一期、最後一期（繳完）
    var firstStart: Date? = nil
    var firstDue: Date? = nil
    var payoffDate: Date? = nil

    // owed(at:) 查表用：從第一段起始那個月起，每個月的扣款日（那個月最晚的一筆）與月底本金
    private var baseMonth: Date? = nil
    private var monthDueDates: [Date?] = []
    private var monthBalances: [Double] = []

    var hasMortgage: Bool { !segments.isEmpty }
    var hasStarted: Bool { paidCount > 0 }
    var isPaidOff: Bool { hasMortgage && totalCount > 0 && paidCount >= totalCount }
    /// 還要繳 L（含利息）
    var left: Double { max(0, scheduledTotal - paid) }
    /// 還欠是用本金算的（否則是含利息的還要繳）
    var owedIsPrincipal: Bool { balance != nil }
    /// 本金是推算的，畫面寫「約」
    var owedIsEstimate: Bool { owedIsPrincipal && principalSource == .estimated }
    /// 算不出本金，退回含利息的還要繳
    var owedIsScheduled: Bool { hasMortgage && !owedIsPrincipal }
    /// 今天（賣掉的是賣出日）還欠多少
    var owed: Double { owed(at: asOf) }
    /// 扣掉房貸，真正是你的
    var equity: Double { value - owed }

    /// 某一天還欠多少：算得出本金就是本金餘額 B（扣款日 ≤ 那天的期數都扣掉之後），否則是含利息的還要繳。
    /// 第一段起始日之前是 0（預售屋還沒開始扣）；全部算數的期數都繳完、或提前停扣的段都停了，也是 0。
    func owed(at date: Date, calendar cal: Calendar = .current) -> Double {
        guard hasMortgage, let start = firstStart else { return 0 }
        let day = cal.startOfDay(for: date)
        guard day >= cal.startOfDay(for: start) else { return 0 }
        // 每一段排定的期數都過了：繳完或停掉了（賣出不算，賣出那天還欠多少照算）
        if segments.allSatisfy({ s in
            guard let last = s.lastScheduledDue else { return true }
            return cal.startOfDay(for: last) <= day
        }) { return 0 }

        if let base = baseMonth, !monthBalances.isEmpty, monthlyRate != nil {
            var m = cal.dateComponents([.month], from: base, to: HouseFacts.monthStart(day, cal)).month ?? 0
            let last = monthBalances.count - 1
            if m > last {
                let tail = monthBalances[last]
                return tail < 1 ? 0 : tail
            }
            if m < 0 { return 0 }
            if m >= 1, m < monthDueDates.count, let due = monthDueDates[m], cal.startOfDay(for: due) > day {
                m -= 1   // 這個月那一期還沒扣
            }
            let b = monthBalances[max(0, m)]
            return b < 1 ? 0 : b
        }
        // 算不出本金：還要繳的期數 × 每期金額
        var left = 0.0
        for s in segments where s.scheduledPeriods > 0 {
            let done = HouseLoanMath.duesOnOrBefore(day, start: s.start, component: s.component, step: s.step,
                                                    limit: s.scheduledPeriods, calendar: cal)
            left += Double(s.scheduledPeriods - done) * s.perPeriod
        }
        return left
    }

    static func monthStart(_ d: Date, _ cal: Calendar) -> Date {
        cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? cal.startOfDay(for: d)
    }

    static func build(_ re: RealEstate, expense e: ExpenseStore, now: Date = Date()) -> HouseFacts {
        build(re, expenses: e.expenses, now: now)
    }

    static func build(_ re: RealEstate, expenses: [Expense], now: Date = Date(),
                      calendar cal: Calendar = .current) -> HouseFacts {
        var f = HouseFacts()
        let soldDay: Date? = re.soldDate
        let asOf: Date = soldDay.map { min(now, $0) } ?? now
        f.asOf = asOf

        // 估值：賣掉的用成交價；沒填用購入價
        let rawValue = re.isSold ? (re.soldPrice ?? re.currentValue) : re.currentValue
        f.value = rawValue > 0 ? rawValue : re.purchasePrice
        f.valueIsFallback = rawValue <= 0

        // ── 段 ──
        let byId = Dictionary(expenses.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func isLoan(_ ex: Expense) -> Bool { ex.isRecurringFixed && ex.fixedCategory == .loan && ex.recurrence != nil }

        // 房貸項目 → 它連到的支出（同一筆支出只算一次）
        var itemLinks: [(item: RealEstateMortgageItem, expense: Expense?)] = []
        var usedExpenseIds = Set<UUID>()
        for m in re.mortgageItems {
            if let id = m.linkedExpenseId {
                guard !usedExpenseIds.contains(id) else { continue }
                usedExpenseIds.insert(id)
                if let ex = byId[id], isLoan(ex) {
                    itemLinks.append((item: m, expense: ex))
                } else {
                    itemLinks.append((item: m, expense: nil))
                }
            } else {
                itemLinks.append((item: m, expense: nil))
            }
        }
        // 記帳裡連到這間、但沒有房貸項目的房貸（舊版單筆連結、或只在記帳那邊建的）
        var orphans: [Expense] = []
        var seenOrphan = Set<UUID>()
        func addOrphan(_ ex: Expense) {
            guard !usedExpenseIds.contains(ex.id), !seenOrphan.contains(ex.id), isLoan(ex),
                  ex.loanSubCategory != .car, ex.loanSubCategory != .personal else { return }
            seenOrphan.insert(ex.id)
            orphans.append(ex)
        }
        if let legacy = re.linkedExpenseId, let ex = byId[legacy] { addOrphan(ex) }
        for ex in expenses where ex.linkedRealEstateId == re.id { addOrphan(ex) }
        // 沒連結的舊段剛好一段、記帳那邊也剛好一筆：當成同一筆（舊版遷移出來的就是這樣）
        let unlinkedIdx = itemLinks.indices.filter { itemLinks[$0].item.linkedExpenseId == nil }
        if unlinkedIdx.count == 1, orphans.count == 1 {
            itemLinks[unlinkedIdx[0]].expense = orphans[0]
            orphans.removeAll()
        }

        func makeSegment(id: UUID, title rawTitle: String, linked ex: Expense?, item: RealEstateMortgageItem?) -> Segment {
            let title = rawTitle.trimmingCharacters(in: .whitespaces).isEmpty ? "房貸" : rawTitle.trimmingCharacters(in: .whitespaces)
            if let ex = ex, let rec = ex.recurrence {
                let (component, step) = rec.componentValue
                var contract: Int
                var guess = false
                if let years = ex.loanYears, years > 0 {
                    contract = HouseLoanMath.contractPeriods(years: years, recurrence: rec)
                } else if let end = ex.endDate {
                    contract = HouseLoanMath.duesOnOrBefore(end, start: ex.date, component: component, step: step,
                                                            limit: 1200, calendar: cal)
                } else {
                    let months = min(1200, item?.totalPeriods ?? 240)
                    contract = max(1, months / max(1, rec.periodMonths))
                    guess = true
                }
                var scheduled = contract
                // 因為賣房停的（endReason＝資產已出售）不算提前還清：賣出那天還欠多少照算，截在下面的 counted
                if let end = ex.endDate, ex.endReason != .assetSold {
                    scheduled = min(scheduled, HouseLoanMath.duesOnOrBefore(end, start: ex.date, component: component,
                                                                           step: step, limit: contract, calendar: cal))
                }
                var counted = scheduled
                if let sold = soldDay {
                    counted = min(counted, HouseLoanMath.duesOnOrBefore(sold, start: ex.date, component: component,
                                                                       step: step, limit: scheduled, calendar: cal))
                }
                let paidN = HouseLoanMath.duesOnOrBefore(asOf, start: ex.date, component: component, step: step,
                                                         limit: counted, calendar: cal)
                return Segment(id: id, linkedExpenseId: ex.id, title: title, displayTitle: title,
                               start: ex.date, component: component, step: step, periodMonths: rec.periodMonths,
                               perPeriod: ex.amount, contractPeriods: contract, scheduledPeriods: scheduled,
                               countedPeriods: counted, paidPeriods: paidN, endDate: ex.endDate,
                               isLinked: true, termIsGuess: guess)
            }
            // 沒連到記帳的舊段：讀房貸項目自己的欄位，一律當月繳
            let start = item?.startDate ?? re.purchaseDate
            let contract = min(1200, max(0, item?.totalPeriods ?? 0))   // 最多 1200 期：資料壞掉時下面逐期展開才不會跑不完
            var counted = contract
            if let sold = soldDay {
                counted = min(counted, HouseLoanMath.duesOnOrBefore(sold, start: start, component: .month, step: 1,
                                                                   limit: contract, calendar: cal))
            }
            let paidN = HouseLoanMath.duesOnOrBefore(asOf, start: start, component: .month, step: 1,
                                                     limit: counted, calendar: cal)
            return Segment(id: id, linkedExpenseId: item?.linkedExpenseId, title: title, displayTitle: title,
                           start: start, component: .month, step: 1, periodMonths: 1,
                           perPeriod: item?.amount ?? 0, contractPeriods: contract, scheduledPeriods: contract,
                           countedPeriods: counted, paidPeriods: paidN, endDate: nil,
                           isLinked: false, termIsGuess: false)
        }

        var segs: [Segment] = itemLinks.map { makeSegment(id: $0.item.id, title: $0.item.title, linked: $0.expense, item: $0.item) }
        segs += orphans.map { makeSegment(id: $0.id, title: "房貸", linked: $0, item: nil) }
        segs = segs.filter { $0.contractPeriods > 0 && $0.perPeriod > 0 }
        segs.sort { $0.start < $1.start }
        if segs.count > 1, segs.allSatisfy({ $0.title == "房貸" }) {
            for i in segs.indices { segs[i].displayTitle = "第 \(i + 1) 段" }
        }
        f.segments = segs
        guard !segs.isEmpty else { return f }

        // ── 期數、已繳、全部要繳 ──
        f.paidCount = segs.reduce(0) { $0 + $1.paidPeriods }
        f.totalCount = segs.reduce(0) { $0 + $1.countedPeriods }
        f.paid = segs.reduce(0) { $0 + Double($1.paidPeriods) * $1.perPeriod }
        f.scheduledTotal = segs.reduce(0) { $0 + Double($1.countedPeriods) * $1.perPeriod }
        f.firstStart = segs.map(\.start).min()
        f.firstDue = segs.map(\.firstDue).min()
        f.payoffDate = segs.compactMap(\.lastCountedDue).max()

        // ── 這個月房貸、下一次月付改變 ──
        func monthlyTotal(_ month: Date) -> Double {
            segs.filter { $0.isPaying(inMonth: month, calendar: cal) }.reduce(0) { $0 + $1.monthly }
        }
        let thisMonth = monthStart(asOf, cal)
        f.monthlyMortgage = monthlyTotal(thisMonth)
        if !re.isSold, let payoff = f.payoffDate {
            let lastMonth = monthStart(payoff, cal)
            var m = cal.date(byAdding: .month, value: 1, to: thisMonth) ?? thisMonth
            var guardN = 0
            while m <= lastMonth && guardN < 1200 {
                let v = monthlyTotal(m)
                if abs(v - f.monthlyMortgage) >= 1 { f.nextChange = MonthlyChange(month: m, monthly: v); break }
                m = cal.date(byAdding: .month, value: 1, to: m) ?? lastMonth.addingTimeInterval(1)
                guardN += 1
            }
        }

        // ── 借款本金 P ──
        let contractTotal: Double = segs.reduce(0.0) { $0 + Double($1.contractPeriods) * $1.perPeriod }
        if let entered = re.loanPrincipal, entered > 0 {
            f.principal = entered
            f.principalSource = .entered
        } else {
            var ledger: [Double] = []
            for s in segs {
                guard let id = s.linkedExpenseId, let total = byId[id]?.loanTotalAmount, total > 0 else { continue }
                ledger.append(total)
            }
            if let lo = ledger.min(), let hi = ledger.max(), hi - lo < 1 {
                f.principal = lo
                f.principalSource = .ledger
            } else {
                // 購入價 − 房屋價金（paidItems＋舊資料裡歸錯章節的房屋價金變動支出，同一筆支出只算一次）
                var seen = Set<UUID>()
                var housePay = 0.0
                for p in re.paidItems {
                    if let id = p.linkedExpenseId { if seen.contains(id) { continue }; seen.insert(id) }
                    housePay += p.amount
                }
                for v in re.variableExpenses where v.category == .housePayment {
                    if let id = v.linkedExpenseId { if seen.contains(id) { continue }; seen.insert(id) }
                    housePay += v.amount
                }
                let est = re.purchasePrice - housePay
                if housePay > 0, re.purchasePrice > 0, est > 0, est < contractTotal {
                    f.principal = est
                    f.principalSource = .estimated
                }
            }
        }

        // ── 每個月的扣款 → 反推利率 → 每個月的本金 ──
        guard let p = f.principal, let start = f.firstStart else { return f }
        let base = monthStart(start, cal)
        var flows: [Double] = []
        var dues: [Date?] = [nil]   // index 0＝起始那個月
        for s in segs {
            for k in 1...s.contractPeriods {
                let d = s.due(k, calendar: cal)
                let t = cal.dateComponents([.month], from: base, to: monthStart(d, cal)).month ?? 0
                guard t >= 1 else { continue }
                if flows.count < t { flows += [Double](repeating: 0, count: t - flows.count) }
                if dues.count <= t { dues += [Date?](repeating: nil, count: t + 1 - dues.count) }
                flows[t - 1] += s.perPeriod
                if let old = dues[t] { dues[t] = max(old, d) } else { dues[t] = d }
            }
        }
        guard let r = HouseLoanMath.monthlyRate(principal: p, flows: flows) else { return f }
        f.monthlyRate = r
        f.baseMonth = base
        f.monthDueDates = dues
        f.monthBalances = HouseLoanMath.balances(principal: p, rate: r, flows: flows)

        let b = f.owed(at: asOf, calendar: cal)
        f.balance = b
        f.principalRepaid = p - b
        f.interestPaid = f.paid - (p - b)
        // 今年付的利息：今年每個月月初本金 × r（到今天這個月為止）
        let year = cal.component(.year, from: asOf)
        let nowIndex = cal.dateComponents([.month], from: base, to: thisMonth).month ?? 0
        var interest = 0.0
        if nowIndex >= 1 {
            for t in 1...min(nowIndex, f.monthBalances.count - 1) {
                guard let m = cal.date(byAdding: .month, value: t, to: base), cal.component(.year, from: m) == year else { continue }
                interest += max(0, f.monthBalances[t - 1]) * r
            }
        }
        f.interestThisYear = interest
        return f
    }
}

// MARK: - 賣房子時把房貸停在成交日

enum RealEstateSale {
    /// 這間房子連到的房貸固定支出 id（房貸項目＋舊版單筆連結）
    static func mortgageExpenseIds(of re: RealEstate, expenses: [Expense]) -> Set<UUID> {
        var ids = Set(re.mortgageItems.compactMap(\.linkedExpenseId))
        if let legacy = re.linkedExpenseId { ids.insert(legacy) }
        // 只在記帳那邊連到這間的房貸（HouseFacts 也把它們算成段），賣房時一樣要停
        for ex in expenses where ex.linkedRealEstateId == re.id && ex.isRecurringFixed && ex.fixedCategory == .loan
            && ex.loanSubCategory != .car && ex.loanSubCategory != .personal {
            ids.insert(ex.id)
        }
        return ids
    }

    /// [v25.532] 標成已售出：連到的房貸固定支出停在成交日（原本沒有結束日、或比成交日晚、或上次就是因為賣房停的），
    /// 記帳就不會在賣掉之後繼續每月扣；取消已售出：把「因為賣房停的」還原成照年限推算的最後一期。
    /// 只改傳進來的陣列，回傳有沒有改到，呼叫端一次寫回 store。
    @discardableResult
    static func syncMortgageStops(of re: RealEstate, soldDate: Date?, in expenses: inout [Expense],
                                  now: Date = Date(), calendar cal: Calendar = .current) -> Bool {
        let ids = mortgageExpenseIds(of: re, expenses: expenses)
        guard !ids.isEmpty else { return false }
        var changed = false
        for i in expenses.indices where ids.contains(expenses[i].id) && expenses[i].isRecurringFixed {
            if let sold = soldDate {
                let soldDay = cal.startOfDay(for: sold)
                let stoppedBySale = expenses[i].endReason == .assetSold
                let needsStop: Bool
                if let end = expenses[i].endDate {
                    let endDay = cal.startOfDay(for: end)
                    needsStop = endDay > soldDay || (stoppedBySale && endDay != soldDay)
                } else {
                    needsStop = true
                }
                if needsStop {
                    expenses[i].endDate = sold
                    expenses[i].endReason = .assetSold
                    changed = true
                }
            } else if expenses[i].endReason == .assetSold {
                let suggested = expenses[i].suggestedEndDate
                expenses[i].endDate = suggested
                if let s = suggested, s < now {
                    expenses[i].endReason = .paidOff
                } else {
                    expenses[i].endReason = nil
                }
                changed = true
            }
        }
        return changed
    }
}

// MARK: - 樓層標籤

/// [v25.532] 編輯頁的樓層是自由輸入的字（1F、1樓、一樓、B1、地下1樓、RF、屋頂、頂樓、夾層、3–5F…），
/// 以前排序和街景只認得「數字＋F」，其餘全當 0，大樓一律被畫成 1F。統一在這裡解析。
struct FloorLabel: Equatable {
    enum Kind: Equatable {
        case basement(Int)
        case floor(Int)
        case range(Int, Int)
        case mezzanine
        case roof
        case unknown
    }
    let kind: Kind
    let raw: String

    static func parse(_ text: String) -> FloorLabel {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 全形轉半形、大寫、拿掉空白
        var s = ""
        for ch in raw.unicodeScalars {
            if ch.value >= 0xFF01 && ch.value <= 0xFF5E, let half = Unicode.Scalar(ch.value - 0xFEE0) {
                s.unicodeScalars.append(half)
            } else if ch != " " && ch != "\u{3000}" {
                s.unicodeScalars.append(ch)
            }
        }
        s = s.uppercased()
        guard !s.isEmpty else { return FloorLabel(kind: .unknown, raw: raw) }

        if ["RF", "R", "ROOF", "PH", "屋頂", "頂樓", "頂", "屋突", "頂加"].contains(s) || s.hasPrefix("屋頂") || s.hasPrefix("頂樓") {
            return FloorLabel(kind: .roof, raw: raw)
        }
        if s.contains("夾層") || s == "M" || s == "MF" { return FloorLabel(kind: .mezzanine, raw: raw) }

        // 去掉尾巴的 F／樓／層
        var core = s
        for suffix in ["樓層", "樓", "層", "F"] where core.hasSuffix(suffix) && core.count > suffix.count {
            core.removeLast(suffix.count)
            break
        }
        // 地下室：B1、B1F、地下1樓、地下一層、-1
        var basementText: String? = nil
        if core.hasPrefix("地下") { basementText = String(core.dropFirst(2)) }
        else if core.hasPrefix("B") { basementText = String(core.dropFirst()) }
        else if core.hasPrefix("-") { basementText = String(core.dropFirst()) }
        if let bt = basementText {
            var t = bt
            for suffix in ["樓", "層", "F"] where t.hasSuffix(suffix) { t.removeLast(suffix.count) }
            if let n = number(t), n > 0 { return FloorLabel(kind: .basement(n), raw: raw) }
            if bt.isEmpty, core.hasPrefix("地下") { return FloorLabel(kind: .basement(1), raw: raw) }
            return FloorLabel(kind: .unknown, raw: raw)
        }
        // 範圍：3-5、3–5F、3~5樓、3至5
        for sep in ["-", "–", "—", "~", "～", "至", "到"] {
            let parts = core.components(separatedBy: sep)
            if parts.count == 2 {
                var a = parts[0], b = parts[1]
                for suffix in ["樓", "層", "F"] where a.hasSuffix(suffix) { a.removeLast(suffix.count) }
                for suffix in ["樓", "層", "F"] where b.hasSuffix(suffix) { b.removeLast(suffix.count) }
                if let x = number(a), let y = number(b), x > 0, y > 0 {
                    let kind: Kind = x == y ? .floor(x) : .range(min(x, y), max(x, y))
                    return FloorLabel(kind: kind, raw: raw)
                }
            }
        }
        if let n = number(core), n > 0 { return FloorLabel(kind: .floor(n), raw: raw) }
        return FloorLabel(kind: .unknown, raw: raw)
    }

    /// 阿拉伯數字或中文數字（一～九十九）
    private static func number(_ s: String) -> Int? {
        if let n = Int(s) { return n }
        let digits: [Character: Int] = ["零": 0, "〇": 0, "一": 1, "二": 2, "兩": 2, "三": 3, "四": 4, "五": 5,
                                        "六": 6, "七": 7, "八": 8, "九": 9]
        let chars = Array(s)
        guard !chars.isEmpty else { return nil }
        if let i = chars.firstIndex(of: "十") {
            let tens: Int
            if i == 0 { tens = 1 } else if i == 1, let d = digits[chars[0]] { tens = d } else { return nil }
            let rest = chars[(i + 1)...]
            if rest.isEmpty { return tens * 10 }
            guard rest.count == 1, let c = rest.first, let u = digits[c] else { return nil }
            return tens * 10 + u
        }
        guard chars.count == 1, let d = digits[chars[0]] else { return nil }
        return d
    }

    /// 排序用：B2 < B1 < 1F < 夾層（1F 與 2F 之間）< 2F … < 看不懂的 < RF
    var sortKey: Double {
        switch kind {
        case .basement(let n): return -Double(n)
        case .floor(let n): return Double(n)
        case .range(let a, _): return Double(a)
        case .mezzanine: return 1.5
        case .unknown: return 500
        case .roof: return 1000
        }
    }

    /// 短標籤：B1、1F、3–5F、夾層、RF；看不懂的照原字
    var short: String {
        switch kind {
        case .basement(let n): return "B\(n)"
        case .floor(let n): return "\(n)F"
        case .range(let a, let b): return "\(a)–\(b)F"
        case .mezzanine: return "夾層"
        case .roof: return "RF"
        case .unknown: return raw.isEmpty ? "樓層" : raw
        }
    }

    /// 地上一般樓層的範圍（地下室、夾層、屋頂、看不懂的是 nil）
    var aboveGround: ClosedRange<Int>? {
        switch kind {
        case .floor(let n): return n...n
        case .range(let a, let b): return a...b
        default: return nil
        }
    }

    /// 一串樓層照樓高排（同一層照原本順序）
    static func sorted(_ floors: [FloorInfo]) -> [FloorInfo] {
        floors.enumerated()
            .sorted { a, b in
                let ka = parse(a.element.floorNumber).sortKey, kb = parse(b.element.floorNumber).sortKey
                return ka != kb ? ka < kb : a.offset < b.offset
            }
            .map { $0.element }
    }

    /// 地上一般樓層的最低～最高（大樓「12F」「3–5F」用）；一層都看不懂回 nil
    static func aboveGroundSpan(_ floors: [FloorInfo]) -> ClosedRange<Int>? {
        let ranges = floors.compactMap { parse($0.floorNumber).aboveGround }
        guard let lo = ranges.map(\.lowerBound).min(), let hi = ranges.map(\.upperBound).max() else { return nil }
        return lo...hi
    }

    /// 透天有幾層地上一般樓層（一層都看不懂時退回 floors.count）
    static func aboveGroundCount(_ floors: [FloorInfo]) -> Int {
        var levels = Set<Int>()
        for f in floors {
            // [v25.532] 打錯成「1-99999999F」也不會一層一層塞到卡住；街景最多也只畫 200 層
            if let r = parse(f.floorNumber).aboveGround { levels.formUnion(r.clamped(to: 1...200)) }
        }
        return levels.isEmpty ? floors.count : levels.count
    }
}

// MARK: - [v25.534] 卡片要讀的唯讀數字（只新增，不動上面的算法）

extension HouseFacts {
    /// 照合約全部繳完的總額（Σ 合約期數 × 每期金額，不看停扣與賣出）。反推利率用的就是這一串扣款，
    /// 「要確認」區靠它分辨算不出利率的原因：借款本金比它還多，還是利率要超過每月 2%。
    var contractTotal: Double {
        segments.reduce(0.0) { $0 + Double($1.contractPeriods) * $1.perPeriod }
    }
}
