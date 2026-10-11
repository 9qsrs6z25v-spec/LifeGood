import Foundation

// [v25.539] 一台車的數字全 App 只算這一套（照 HouseFacts：值型別、build 一次、到處讀）。
//
// 以前同一台車有好幾套算法：列表卡、載具頁看板、理財現金流各自用車子身上的鏡像（fixedExpenses／
// variableExpenses）算，季繳被當成月繳、繳完或停掉的定期照算、近 12 個月的變動一律 ÷ 12（買兩個月也除 12），
// 車貸用「含利息還要繳」當負債，兩台車共用一筆記帳時看板還會加兩次。現在：
// - 以記帳為準：一台車的錢＝記帳裡 linkedVehicleId＝這台的支出 ∪ 鏡像 linkedExpenseId 找得到的，用支出 id 去重；
//   金額一律台幣（ntd 閉包＝ExpenseStore.ntdValue），週期、起訖日、年限、總貸款金額都讀那筆 Expense。
//   鏡像只當索引；沒連到記帳的舊鏡像才讀它自己的欄位。
// - 同一筆支出只算給 linkedVehicleId 那一台：鏡像在 A、記帳那筆的 linkedVehicleId 指 B，只算 B。
// - 車貸數學全部重用 HouseLoanMath（期數、扣款日、反推利率、每月本金），只多一條零利率規則。
// - 日期一律西曆（build 預設 Calendar(identifier: .gregorian)），手機設民國曆也不會算錯年份。

// MARK: - 一筆車貸

/// 一筆車貸（一筆連到這台車的貸款固定支出）
struct VehicleLoan: Identifiable, Equatable {
    enum Status: Equatable { case notStarted, paying, done, stopped, soldSettled }

    /// 算不出利率（還欠本金）的原因，「要確認」照這個寫
    enum RateIssue: Equatable {
        /// 沒填年限也沒有結束日：不知道一共幾期（沒填年限、結束日是賣車時設的也是：原本幾期不知道）
        case noTerm
        /// 沒填總貸款金額
        case noPrincipal
        /// 每期加起來比借的還少（可能有期末尾款）
        case belowPrincipal
        /// 要超過每月 2% 才湊得出來（資料對不上，不硬算）
        case tooHigh
    }

    /// 支出 id
    let id: UUID
    /// 你取的名稱 → 備註第一行 → 「車貸」
    let title: String
    /// 同一台兩筆以上都叫「車貸」時改成「第 n 筆」（build 已經改好，畫面直接用這個）
    var displayTitle: String
    let start: Date
    /// 一個週期幾個月（季繳 3、年繳 12）
    let periodMonths: Int
    /// 每期金額（台幣；季繳就是一季的錢）
    let perPeriod: Double
    /// 合約期數 N（照年限；沒填年限用結束日推）。反推利率、利息總額用這個，不看停扣和賣出
    let contractPeriods: Int
    /// 已繳期數 n（扣款日 ≤ asOf，截到結束日）
    let paidPeriods: Int
    /// 沒填年限也沒有結束日：期數是不知道的（contractPeriods＝0）
    let termIsGuess: Bool
    let endDate: Date?
    /// 借款本金 P（loanTotalAmount > 0 才有）
    let principal: Double?
    /// 月利率 r：|S−P| ≤ 0.5%P 時是 0（零利率）；S < 0.995P、或要超過每月 2% 才湊得出來時 nil
    let monthlyRate: Double?
    let status: Status

    var recurrence: Recurrence = .monthly
    var component: Calendar.Component = .month
    var step: Int = 1
    var endReason: FixedEndReason? = nil
    /// 排定期數：截到結束日（停扣、提前還清）；因為賣車停的不截——賣出那天還欠多少照算
    var scheduledPeriods: Int = 0
    /// 真的會扣的期數：截到結束日（不管什麼原因停的）
    var countedPeriods: Int = 0
    /// 第一期扣款日＝起始日＋1 個週期
    var firstDue: Date
    var rateIssue: RateIssue? = nil
    /// S＝N × 每期（全部繳完總共多少，含利息）
    var scheduledTotal: Double = 0
    /// 已繳＝n × 每期
    var paid: Double = 0
    /// 還要繳 L＝(排定期數 − n) × 每期（含利息）。賣出時結清的是賣出那天、結清之前還沒繳的
    var left: Double = 0
    /// 還欠本金 B（asOf 那天）；r＝0 時就是 P − 已繳。算不出利率時 nil
    var balance: Double? = nil
    /// P − B
    var principalRepaid: Double? = nil
    /// 已繳 − 已還本金
    var interestPaid: Double? = nil
    /// S − P
    var interestTotal: Double? = nil
    /// 最後一期扣款日（真的會扣的最後一期）；沒填年限 nil
    var payoffDate: Date? = nil
    /// 下一次扣款日（asOf 當天或之後）；繳完、停了、賣出時結清是 nil
    var nextDue: Date? = nil
    /// 下一次是第幾期（「第 26／60 期」）
    var nextIndex: Int? = nil

    /// 換算成每月（季繳 ÷ 3、年繳 ÷ 12）
    var monthly: Double { perPeriod / Double(max(1, periodMonths)) }
    var hasStarted: Bool { paidPeriods > 0 }
    /// 算得出還欠本金（有每個月的本金表）
    var hasBalance: Bool { !monthBalances.isEmpty }

    // owed(at:) 查表用：利率只解一次，之後每個日子都查這張表（理財總覽回推每個月的淨資產會一直問）
    /// 從這天起算欠（起始日；起始日還沒到的車貸從建立 facts 那天起算，免得「還沒開始」被當成沒欠）
    fileprivate var owedFrom: Date
    fileprivate var baseMonth: Date? = nil
    fileprivate var monthDueDates: [Date?] = []
    fileprivate var monthBalances: [Double] = []

    fileprivate init(id: UUID, title: String, start: Date, periodMonths: Int, perPeriod: Double,
                     contractPeriods: Int, paidPeriods: Int, termIsGuess: Bool, endDate: Date?,
                     principal: Double?, monthlyRate: Double?, status: Status, firstDue: Date, owedFrom: Date) {
        self.id = id
        self.title = title
        self.displayTitle = title
        self.start = start
        self.periodMonths = periodMonths
        self.perPeriod = perPeriod
        self.contractPeriods = contractPeriods
        self.paidPeriods = paidPeriods
        self.termIsGuess = termIsGuess
        self.endDate = endDate
        self.principal = principal
        self.monthlyRate = monthlyRate
        self.status = status
        self.firstDue = firstDue
        self.owedFrom = owedFrom
    }

    /// 第 k 期（從 1 起算）的扣款日
    func due(_ k: Int, calendar cal: Calendar = Calendar(identifier: .gregorian)) -> Date {
        HouseLoanMath.dueDate(k, start: start, component: component, step: step, calendar: cal)
    }

    /// 扣款日 ≤ day 的期數（截到結束日；沒填年限的最多數 1200 期）
    func paidCount(onOrBefore day: Date, calendar cal: Calendar = Calendar(identifier: .gregorian)) -> Int {
        let limit = termIsGuess ? 1200 : countedPeriods
        return HouseLoanMath.duesOnOrBefore(day, start: start, component: component, step: step,
                                            limit: limit, calendar: cal)
    }

    /// day 當天或之後的下一期（哪天、第幾期）；已經沒有會扣的期數時 nil
    func next(onOrAfter day: Date, calendar cal: Calendar = Calendar(identifier: .gregorian)) -> (date: Date, index: Int)? {
        let limit = termIsGuess ? 1200 : countedPeriods
        guard limit > 0 else { return nil }
        // 用「前一天為止扣了幾期」：今天剛好是扣款日時，下一期就是今天這期（不是下個月那期）
        let prev = cal.date(byAdding: .day, value: -1, to: day) ?? day
        let before = HouseLoanMath.duesOnOrBefore(prev, start: start, component: component, step: step,
                                                  limit: limit, calendar: cal)
        let k = before + 1
        guard k <= limit else { return nil }
        return (due(k, calendar: cal), k)
    }

    /// 某個月份是不是在第一期與最後一期之間（每月養車、進度格的「每月」用）
    func isPaying(inMonth month: Date, calendar: Calendar) -> Bool {
        let m = VehicleFacts.monthStart(month, calendar)
        guard VehicleFacts.monthStart(firstDue, calendar) <= m else { return false }
        if termIsGuess { return true }
        guard countedPeriods > 0 else { return false }
        return m <= VehicleFacts.monthStart(due(countedPeriods, calendar: calendar), calendar)
    }

    /// 某一天還欠多少：算得出本金就用本金 B（扣款日 ≤ 那天的期數扣掉之後），否則用含利息的還要繳 L。
    /// 結束日之後是 0（賣車時結清、提前還清、停扣）；排定的期數都扣完了也是 0；沒填年限的不知道，算 0。
    func owed(at date: Date, calendar cal: Calendar) -> Double {
        guard perPeriod > 0, !termIsGuess else { return 0 }
        let day = cal.startOfDay(for: date)
        guard day >= cal.startOfDay(for: owedFrom) else { return 0 }
        if let end = endDate, day > cal.startOfDay(for: end) { return 0 }
        let done = HouseLoanMath.duesOnOrBefore(day, start: start, component: component, step: step,
                                                limit: scheduledPeriods, calendar: cal)
        if scheduledPeriods > 0, done >= scheduledPeriods { return 0 }
        if let base = baseMonth, !monthBalances.isEmpty {
            var m = cal.dateComponents([.month], from: base, to: VehicleFacts.monthStart(day, cal)).month ?? 0
            let last = monthBalances.count - 1
            if m > last {
                let tail = monthBalances[last]
                return tail < 1 ? 0 : tail
            }
            if m < 0 { return monthBalances[0] }   // 起始日還沒到：整筆都還欠
            if m >= 1, m < monthDueDates.count, let dueDay = monthDueDates[m], cal.startOfDay(for: dueDay) > day {
                m -= 1   // 這個月那一期還沒扣
            }
            let b = monthBalances[max(0, m)]
            return b < 1 ? 0 : b
        }
        return Double(max(0, scheduledPeriods - done)) * perPeriod
    }

    /// (from, to] 之間扣的錢裡，利息和本金各多少（帳本年列「利息約 6.6萬・本金約 28.4萬」）。
    /// 用 owed(at:) 前後相減，各段加起來＝已還本金／已付利息；算不出本金、或這段沒有扣款時 nil。
    /// to 請夾在 asOf 以內（結束日之後 owed 是 0，會把結清的錢算成本金）。
    func split(after from: Date, through to: Date,
               calendar cal: Calendar = Calendar(identifier: .gregorian)) -> (interest: Double, principal: Double)? {
        guard let p = principal, monthlyRate != nil, hasBalance else { return nil }
        let k = paidCount(onOrBefore: to, calendar: cal) - paidCount(onOrBefore: from, calendar: cal)
        guard k > 0 else { return nil }
        let paidAmount = Double(k) * perPeriod
        let startOwed = cal.startOfDay(for: from) < cal.startOfDay(for: start) ? p : owed(at: from, calendar: cal)
        let endOwed = owed(at: to, calendar: cal)
        let principalPart = startOwed - endOwed
        let interest = paidAmount - principalPart
        guard principalPart > -1, interest > -1 else { return nil }
        return (max(0, interest), max(0, principalPart))
    }

    /// 從一筆記帳的貸款固定支出建出來；不是週期性、每期 0、或結束日比第一期還早（一期都沒有）時 nil
    fileprivate static func make(_ ex: Expense, title: String, perPeriod: Double, asOf: Date,
                                 calendar cal: Calendar) -> VehicleLoan? {
        guard ex.isRecurringFixed, let rec = ex.recurrence, perPeriod > 0 else { return nil }
        let (component, step) = rec.componentValue
        let start = ex.date
        let firstDue = HouseLoanMath.firstDue(start: start, component: component, step: step, calendar: cal)

        // ── 期數 ──
        var contract = 0
        var guess = false
        if let years = ex.loanYears, years > 0 {
            contract = HouseLoanMath.contractPeriods(years: years, recurrence: rec)
        } else if let end = ex.endDate {
            contract = HouseLoanMath.duesOnOrBefore(end, start: start, component: component, step: step,
                                                    limit: 1200, calendar: cal)
        } else {
            guess = true
        }
        if !guess && contract <= 0 { return nil }
        // [v25.539] 沒填年限、結束日是賣車時設的（endReason＝資產已出售）：原本一共幾期已經不知道了，
        // 「扣到賣出日的期數」不是合約。拿它反推利率會變成「每期加起來比借的少」，被誤報成可能有期末尾款；
        // 扣到結束日也不是「繳完」，是賣出時結清
        let saleCutNoTerm = !guess && (ex.loanYears ?? 0) <= 0 && ex.endReason == .assetSold
        var scheduled = contract
        var counted = contract
        if !guess, let end = ex.endDate {
            counted = min(contract, HouseLoanMath.duesOnOrBefore(end, start: start, component: component, step: step,
                                                                 limit: contract, calendar: cal))
            // 因為賣車停的（endReason＝資產已出售）不算提前還清：賣出那天還欠多少照合約算
            if ex.endReason != .assetSold { scheduled = counted }
        }
        let paidN = HouseLoanMath.duesOnOrBefore(asOf, start: start, component: component, step: step,
                                                 limit: guess ? 1200 : counted, calendar: cal)

        // ── 狀態 ──
        let status: Status
        if guess {
            status = paidN == 0 ? .notStarted : .paying
        } else if saleCutNoTerm && paidN >= counted {
            status = .soldSettled
        } else if paidN >= contract {
            status = .done
        } else if counted < contract && paidN >= counted {
            // 結束日比合約早、而且到 asOf 已經沒有會扣的期數了
            switch ex.endReason {
            case .assetSold?: status = .soldSettled
            case .paidOff?: status = .done
            default: status = .stopped
            }
        } else if paidN == 0 {
            status = .notStarted
        } else {
            status = .paying
        }

        // ── 本金、利率、每個月的本金表 ──
        let principal: Double? = (ex.loanTotalAmount ?? 0) > 0 ? ex.loanTotalAmount : nil
        var rate: Double? = nil
        var issue: RateIssue? = nil
        var base: Date? = nil
        var dues: [Date?] = []
        var balances: [Double] = []
        if guess || saleCutNoTerm {
            issue = principal == nil ? .noPrincipal : .noTerm
        } else if let p = principal {
            let baseMonth = VehicleFacts.monthStart(start, cal)
            var flows: [Double] = []
            var dd: [Date?] = [nil]   // index 0＝起始那個月
            for k in 1...contract {
                let d = HouseLoanMath.dueDate(k, start: start, component: component, step: step, calendar: cal)
                let t = cal.dateComponents([.month], from: baseMonth, to: VehicleFacts.monthStart(d, cal)).month ?? 0
                guard t >= 1 else { continue }
                if flows.count < t { flows += [Double](repeating: 0, count: t - flows.count) }
                if dd.count <= t { dd += [Date?](repeating: nil, count: t + 1 - dd.count) }
                flows[t - 1] += perPeriod
                if let old = dd[t] { dd[t] = max(old, d) } else { dd[t] = d }
            }
            let s = Double(contract) * perPeriod
            if abs(s - p) <= p * 0.005 {
                rate = 0   // 月付加起來剛好等於借款：零利率（車商常見）
            } else if s < p * 0.995 {
                issue = .belowPrincipal
            } else if let r = HouseLoanMath.monthlyRate(principal: p, flows: flows) {
                rate = r
            } else {
                issue = .tooHigh
            }
            if let r = rate {
                base = baseMonth
                dues = dd
                balances = HouseLoanMath.balances(principal: p, rate: r, flows: flows)
            }
        } else {
            issue = .noPrincipal
        }

        let asOfDay = cal.startOfDay(for: asOf)
        let owedFrom = min(cal.startOfDay(for: start), asOfDay)
        var l = VehicleLoan(id: ex.id, title: title, start: start, periodMonths: rec.periodMonths,
                            perPeriod: perPeriod, contractPeriods: guess ? 0 : contract, paidPeriods: paidN,
                            termIsGuess: guess, endDate: ex.endDate, principal: principal, monthlyRate: rate,
                            status: status, firstDue: firstDue, owedFrom: owedFrom)
        l.recurrence = rec
        l.component = component
        l.step = step
        l.endReason = ex.endReason
        l.scheduledPeriods = guess ? 0 : scheduled
        l.countedPeriods = guess ? 0 : counted
        l.rateIssue = issue
        l.baseMonth = base
        l.monthDueDates = dues
        l.monthBalances = balances
        l.scheduledTotal = guess ? 0 : Double(contract) * perPeriod
        l.paid = Double(paidN) * perPeriod
        l.left = guess ? 0 : Double(max(0, scheduled - paidN)) * perPeriod
        if let p = principal, !balances.isEmpty {
            let b = l.owed(at: asOf, calendar: cal)
            l.balance = b
            l.principalRepaid = p - b
            l.interestPaid = l.paid - (p - b)
            l.interestTotal = max(0, l.scheduledTotal - p)
        }
        if !guess, counted > 0 { l.payoffDate = l.due(counted, calendar: cal) }
        if status == .paying || status == .notStarted, let n = l.next(onOrAfter: asOf, calendar: cal) {
            l.nextDue = n.date
            l.nextIndex = n.index
        }
        return l
    }
}

// MARK: - 里程

/// 所有連到這台車、有里程錶讀數的支出（電費、油錢、保養、維修）
struct VehicleOdometer: Equatable {
    struct Reading: Equatable {
        let date: Date
        let km: Double
        let expenseId: UUID
    }

    /// 比前面最大的讀數還小、沒採用的那一筆（「要確認」：「10/3 的 23,000 比 9/20 的 23,400 還少」）
    struct Regression: Equatable {
        let reading: Reading
        let previous: Reading
    }

    /// 採用的讀數，依日期（比前面最大值還小的不採用）
    let readings: [Reading]
    let regressions: [Regression]
    /// (最後 − 最早) ÷ 天數 × 365；跨度不到 30 天、或沒有往上走時 nil
    var annualKm: Double?

    var latestKm: Double? { readings.last?.km }
    var latestDate: Date? { readings.last?.date }
    /// 有讀數比前一筆小（誤填、換過錶）
    var hasRegression: Bool { !regressions.isEmpty }

    /// expenses：不用先篩，這裡只取 odometer > 0 的
    init(expenses: [Expense], calendar cal: Calendar = Calendar(identifier: .gregorian)) {
        let raw: [Reading] = expenses.compactMap { e -> Reading? in
            guard let km = e.odometer, km > 0, km.isFinite else { return nil }
            return Reading(date: e.date, km: km, expenseId: e.id)
        }
        // 同一天的照里程由小到大，才不會把同一天先加油、後保養當成倒退
        let sorted = raw.sorted { $0.date != $1.date ? $0.date < $1.date : $0.km < $1.km }
        var kept: [Reading] = []
        var back: [Regression] = []
        var top: Reading? = nil
        for r in sorted {
            if let t = top, r.km < t.km {
                back.append(Regression(reading: r, previous: t))
                continue
            }
            kept.append(r)
            top = r
        }
        readings = kept
        regressions = back
        annualKm = nil
        if let first = kept.first, let last = kept.last {
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: first.date),
                                          to: cal.startOfDay(for: last.date)).day ?? 0
            let km = last.km - first.km
            // 拿兩週的資料乘 26 倍是在編故事：跨度 30 天以上才推一年
            if days >= 30, km > 0 { annualKm = km / Double(days) * 365 }
        }
    }
}

/// 漏記的一段（中間一定有沒記到的充電或加油）：這段不算進每公里、每度跑、油耗，「要確認」列出來
struct VehicleEnergyGap: Identifiable, Equatable {
    /// 後一筆支出的 id
    let id: UUID
    let from: Date
    let to: Date
    let km: Double
    /// 後一筆的度數或公升
    let amount: Double
}

// MARK: - 加油

/// 油錢（有 fuelLiters 的才算得出每公升、油耗）
struct VehicleFuelAnalytics: Equatable {
    struct Fill: Equatable {
        let id: UUID
        let date: Date
        let place: String
        let cost: Double
        let liters: Double?
        let odometer: Double?
    }

    /// 一段「每公升跑幾公里」的合理上限：超過就是中間漏記了加油
    static let maxKmPerLiter: Double = 40

    /// 全部加油次數、有填的公升合計、全部金額
    var fills: Int = 0
    var liters: Double = 0
    var cost: Double = 0
    /// 有填公升數的那幾次：次數、金額（每公升＝這個金額 ÷ 公升）
    var litersFills: Int = 0
    var litersCost: Double = 0
    /// 每公升＝Σ金額 ÷ Σ公升（只算有填公升的）
    var perLiter: Double? = nil
    /// 油耗＝Σ區間公里 ÷ Σ區間公升（區間裡有公升數的；km ÷ 公升 > 40 那段不算）
    var kmPerLiter: Double? = nil
    /// 每公里油錢＝Σ區間金額 ÷ Σ區間公里
    var perKm: Double? = nil
    var intervalCount: Int = 0
    var trackedKm: Double = 0
    var firstDate: Date? = nil
    var latest: Fill? = nil
    var gaps: [VehicleEnergyGap] = []

    var avgCost: Double? { fills > 0 ? cost / Double(fills) : nil }

    init() {}

    /// expenses：已經篩到「這台車 × 油錢 × 日期 ≤ asOf」；金額走 ntd
    init(expenses: [Expense], ntd: (Expense) -> Double) {
        let list: [Fill] = expenses
            .sorted { $0.date < $1.date }
            .map { e -> Fill in
                let place = (e.placeName ?? e.placeAddress ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let l = e.fuelLiters ?? 0
                let km = e.odometer ?? 0
                return Fill(id: e.id, date: e.date, place: place, cost: ntd(e),
                            liters: l > 0 ? l : nil, odometer: km > 0 ? km : nil)
            }
        fills = list.count
        cost = list.reduce(0) { $0 + $1.cost }
        firstDate = list.first?.date
        latest = list.last
        for f in list {
            guard let l = f.liters else { continue }
            liters += l
            litersFills += 1
            litersCost += f.cost
        }
        if liters > 0 { perLiter = litersCost / liters }

        // 區間：相鄰兩筆都有里程錶、0 < km ≤ 2000，公升和金額取後一筆（同 VehicleChargeAnalytics.intervals）
        let withOdo = list.filter { $0.odometer != nil }
        var kmAll = 0.0
        var costAll = 0.0
        var kmLiters = 0.0
        var litersIn = 0.0
        if withOdo.count >= 2 {
            for i in 1..<withOdo.count {
                let prev = withOdo[i - 1]
                let cur = withOdo[i]
                guard let a = prev.odometer, let b = cur.odometer else { continue }
                let km = b - a
                guard km > 0, km <= 2000 else { continue }
                if let l = cur.liters {
                    guard km / l <= Self.maxKmPerLiter else {
                        gaps.append(VehicleEnergyGap(id: cur.id, from: prev.date, to: cur.date, km: km, amount: l))
                        continue
                    }
                    kmLiters += km
                    litersIn += l
                }
                kmAll += km
                costAll += cur.cost
                intervalCount += 1
            }
        }
        trackedKm = kmAll
        if litersIn > 0, kmLiters > 0 { kmPerLiter = kmLiters / litersIn }
        if kmAll > 0 { perKm = costAll / kmAll }
    }
}

// MARK: - 充電摘要

/// 從 VehicleChargeAnalytics 摘出卡片、列表、看板要的數（VehicleChargeAnalytics 不是 Equatable，facts 存這份）
struct VehicleChargeSummary: Equatable {
    struct Point: Equatable {
        let date: Date
        let value: Double
        var isHome = false
    }

    struct Session: Equatable {
        let date: Date
        /// 沒填地點時是「未填地點」
        let place: String
        let kwh: Double
        let cost: Double
        let fromPct: Double?
        let toPct: Double?
        let isHome: Bool
    }

    var count = 0
    var totalKwh: Double = 0
    var totalCost: Double = 0
    /// 每度電＝Σ金額 ÷ Σ度數
    var avgPricePerKwh: Double? = nil
    var hasHomeKeyword = false
    var homeCount = 0
    var awayCount = 0
    var homePricePerKwh: Double? = nil
    var awayPricePerKwh: Double? = nil
    /// 每公里電費、每度跑（有里程錶的相鄰兩次，擋掉漏記的段）
    var avgCostPerKm: Double? = nil
    var kmPerKwh: Double? = nil
    var intervalCount = 0
    var trackedKm: Double = 0
    /// 年里程（VehicleOdometer，跟車輛資料同一個數）
    var annualKm: Double? = nil
    var firstDate: Date? = nil
    var latest: Session? = nil
    /// 電池跟最初比的變化（−0.02＝少 2%）；資料不夠 nil
    var sohChange: Double? = nil
    var sohScope: String? = nil
    /// 推估容量的樣本數（電池要 10 筆才寫）
    var capacityPointCount = 0
    /// 記帳裡這台車的電費、沒填度數的筆數
    var missingKwhCount = 0
    /// 每次充電的每度電價（點圖）、每段的每度跑、推估容量（舊卡片的走勢）
    var prices: [Point] = []
    var efficiency: [Point] = []
    var capacity: [Point] = []
    /// 漏記充電的段
    var gaps: [VehicleEnergyGap] = []

    var avgKwhPerSession: Double? { count > 0 ? totalKwh / Double(count) : nil }
    var avgCostPerSession: Double? { count > 0 ? totalCost / Double(count) : nil }

    init() {}

    init(_ a: VehicleChargeAnalytics, missingKwhCount: Int) {
        count = a.count
        totalKwh = a.totalKwh
        totalCost = a.totalCost
        avgPricePerKwh = a.avgPricePerKwh
        hasHomeKeyword = a.hasHomeKeyword
        let home = a.homeSessions
        let away = a.awaySessions
        homeCount = home.count
        awayCount = away.count
        homePricePerKwh = a.avgPrice(of: home)
        awayPricePerKwh = a.avgPrice(of: away)
        avgCostPerKm = a.avgCostPerKm
        kmPerKwh = a.avgKmPerKwh
        let ivs = a.intervals
        intervalCount = ivs.count
        trackedKm = a.totalTrackedKm
        annualKm = a.annualizedKm
        firstDate = a.sessions.first?.date
        if let s = a.sessions.last {
            latest = Session(date: s.date, place: s.place, kwh: s.kwh, cost: s.cost,
                             fromPct: s.fromPct, toPct: s.toPct, isHome: s.isHome)
        }
        if let soh = a.soh {
            sohChange = soh.change
            sohScope = soh.scope
        }
        let caps = a.capacityPoints
        capacityPointCount = caps.count
        self.missingKwhCount = missingKwhCount
        prices = a.sessions.compactMap { s in
            s.pricePerKwh.map { Point(date: s.date, value: $0, isHome: s.isHome) }
        }
        efficiency = ivs.map { Point(date: $0.date, value: $0.kmPerKwh) }
        capacity = caps.map { Point(date: $0.date, value: $0.estimate, isHome: $0.isHome) }
        gaps = a.skippedIntervals
    }
}

// MARK: - 接下來

struct VehicleUpcoming: Identifiable, Equatable {
    enum Kind: Equatable { case fixed(UUID), loan(UUID), maintenance }
    /// 「fixed-支出id」「loan-支出id」「maintenance-車子id」（理財總覽把好幾台車排在一起也不會撞）
    let id: String
    let date: Date
    let kind: Kind
    /// 支出名稱（你取的名字優先，沒有就寫分類名）；保養是「保養（估計）」
    let title: String
    /// 「每月・上次 10/5」「第 26／60 期」「平均每 6 個月一次・上次 2026/7/3」
    let detail: String
    /// 台幣；保養是金額中位數（畫面寫「約」）
    let amount: Double
    var isEstimate: Bool = false
    /// 保養超過預計日期幾天（> 0 才有）
    var overdueDays: Int? = nil
}

/// 保養紀錄推算（照片紀錄的「保養維修」也算；前後 3 天內算同一次）
struct VehicleMaintenance: Equatable {
    /// 幾次保養（合併之後）
    var count = 0
    var last: Date? = nil
    /// 最後一次只有照片紀錄、沒有支出
    var lastIsPhotoOnly = false
    /// 每一次都只有照片紀錄（標題寫「保養維修」：照片分類也包含維修）
    var photoOnly = false
    /// 相鄰兩次天數的中位數（小於 14 天的間隔不算；至少 2 次才有）
    var medianDays: Int? = nil
    /// 有 2 次以上填了里程錶時，里程間隔的中位數
    var medianKm: Double? = nil
    /// 下次大約（天數、里程換成日期，兩個取早的）
    var next: Date? = nil
    /// 金額中位數（只看有支出的那幾次）
    var amount: Double? = nil
    /// 超過預計日期幾天（> 0 才有）
    var overdueDays: Int? = nil
}

// MARK: - 每月養車

/// 每月養車各段（原值，未四捨五入）
struct VehicleMonthlyParts: Equatable {
    /// 這個月在扣的車貸月付合計（含沒連到記帳的舊車貸鏡像）
    var loan: Double = 0
    /// 車貸裡的利息（Σ B×r）；這個月在扣的每一筆都算得出本金和利率時才有，否則畫面合成一段「車貸」
    var loanInterest: Double? = nil
    /// 定期（保險、稅費、月租、訂閱；電動機車的訂閱改算能源）
    var fixed: Double = 0
    var energy: Double = 0
    /// 只有電「充電」、只有油「加油」、都有「油電」；電動機車換電月租「換電・充電」
    var energyLabel: String = "能源"
    /// 保養、維修
    var care: Double = 0
    /// 停車、洗車、其他、沒有子分類（含不是週期的固定支出）
    var other: Double = 0

    var total: Double { loan + fixed + energy + care + other }
    /// 還本金＝車貸 − 利息（拆得出利息時才有）
    var loanPrincipal: Double? { loanInterest.map { max(0, loan - $0) } }
}

// MARK: - 一台車連到哪些記帳

/// 記帳 linkedVehicleId＝這台 ∪ 鏡像 linkedExpenseId 找得到的（用支出 id 去重）；
/// 鏡像找到的那筆 linkedVehicleId 是別台時只算那一台（記帳的連結優先）。
struct VehicleLinks {
    /// 這台車的記帳支出，依日期
    var expenses: [Expense] = []
    /// 沒連到記帳的舊鏡像（linkedExpenseId 是空的、或記帳裡找不到）：只有它們才讀鏡像自己的欄位
    var legacyFixed: [VehicleFixedExpense] = []
    var legacyVariable: [VehicleVariableExpense] = []
    /// 鏡像有 linkedExpenseId、記帳裡卻找不到（鏡像 id）
    var orphanMirrorIds: Set<UUID> = []
    /// 鏡像指到的記帳連到別台車（鏡像 id）：這台不算
    var foreignMirrorIds: Set<UUID> = []

    static func make(_ v: Vehicle, expenses all: [Expense]) -> VehicleLinks {
        var out = VehicleLinks()
        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<UUID>()
        var list: [Expense] = []
        for ex in all where ex.linkedVehicleId == v.id {
            if seen.insert(ex.id).inserted { list.append(ex) }
        }
        /// 鏡像指到的那筆：回 true＝算這台；false＝不算（舊鏡像或連到別台）
        func take(_ mirrorId: UUID, _ linked: UUID?) -> Bool {
            guard let id = linked else { return false }
            guard let ex = byId[id] else {
                out.orphanMirrorIds.insert(mirrorId)
                return false
            }
            if let owner = ex.linkedVehicleId, owner != v.id {
                out.foreignMirrorIds.insert(mirrorId)
                return true   // 有找到，只是不歸這台：不當成舊鏡像
            }
            if seen.insert(ex.id).inserted { list.append(ex) }
            return true
        }
        for m in v.fixedExpenses where !take(m.id, m.linkedExpenseId) { out.legacyFixed.append(m) }
        for m in v.variableExpenses where !take(m.id, m.linkedExpenseId) { out.legacyVariable.append(m) }
        out.expenses = list.sorted { $0.date != $1.date ? $0.date < $1.date : $0.id.uuidString < $1.id.uuidString }
        return out
    }
}

// MARK: - 一台車的數字

/// 一台車要寫在卡片、列表項目卡、載具頁看板、理財總覽上的數字（每台在 .task 裡 build 一次，到處讀）
struct VehicleFacts: Equatable {
    // —— 既有欄位（呼叫端還在用，值改成新算法）——
    /// 每度電（電車、電動機車、油電有度數才有）
    var perKwh: Double? = nil
    /// 每公里：電車讀充電分析、油車讀加油分析；油電不放（兩種區間混不起來）
    var perKm: Double? = nil
    /// 期間油錢 ÷ 期間月數（每月養車裡油錢那一部分）
    var fuelPerMonth: Double? = nil
    /// 每月養車＝parts.total（原值；畫面寫「約」並四捨五入到百位）
    var monthly: Double = 0
    /// 項目卡進度條：多筆車貸合併（已繳、總期數加總），依起始日
    var loan: MoneyLoanSchedule? = nil
    /// Σ 還要繳 L（含利息）
    var loanLeft: Double = 0

    // —— 新欄位 ——
    /// 算到哪一天：今天；已售出＝min(今天, 售出日)
    var asOf: Date = Date()
    /// isSold(asOf: 今天)
    var isSold = false
    /// 估值（決定 10）：沒有更新日的 0＝還沒填 → 用購入價；已售出用成交價，沒填成交價用目前估值
    var value: Double = 0
    /// 估值是借用購入價（還沒填）
    var valueIsFallback = false
    /// 已售出但沒填成交價，用估值當賣價
    var saleUsesEstimate = false
    var purchase: Double = 0
    /// purchase − value（≥ 0 才是折舊，負的是增值）
    var depreciation: Double = 0
    /// value ÷ purchase − 1（分數，−0.27＝折舊 27%）；購入價 ≤ 0、或估值還沒填時 nil
    var depreciationRate: Double? = nil
    /// 購入那個月到 asOf 那個月差幾個月
    var heldMonths: Int = 0
    /// 折舊每月＝depreciation ÷ max(1, heldMonths)；購入價 > 0、真的有折、持有至少 3 個月、估值有填才有
    var depreciationMonthly: Double? = nil
    /// 這台車的記帳支出 id（記帳 linkedVehicleId ∪ 鏡像找得到的）
    var ledgerExpenseIds: Set<UUID> = []
    var parts = VehicleMonthlyParts()
    /// 每月養車的期間：起點＝max(購入日, asOf − 12 個月)，月數＝月差＋(日差 ≥ 15 ? 1 : 0)，夾在 1…12
    var periodStart: Date = Date()
    var periodMonths: Int = 12
    /// 依起始日排序
    var loans: [VehicleLoan] = []
    /// 這個月在扣的車貸月付合計（＝parts.loan）
    var loanMonthly: Double = 0
    var loanPaid: Double = 0
    /// 決定 2：Σ(算得出本金用 B，否則用 L)
    var owed: Double = 0
    /// 有一筆用的是含利息的 L（畫面寫「還要繳」）
    var owedIsScheduled = false
    /// 有在扣、但沒填年限的車貸（不知道還要繳多少，沒算進 owed）
    var owedMissingTerm = false
    var equity: Double { value - owed }
    var charge: VehicleChargeSummary? = nil
    var fuel: VehicleFuelAnalytics? = nil
    var odometer: VehicleOdometer? = nil
    /// 今天＋12 個月內：每筆定期只列下一次（含保險、車貸「第 26／60 期」）；保養估計（已售出不估）。
    /// 已售出的車只剩還在扣的定期（停車月租、訂閱這類賣車不會自動停的）
    var upcoming: [VehicleUpcoming] = []
    var maintenance = VehicleMaintenance()
    /// 期間內沒有任何連到這台車的保險扣款
    var missingInsurance = false
    /// 持有不滿 12 個月，而且期間內沒有任何稅費扣款
    var firstYearNoTax = false
    /// 第一筆油錢、電費比期間開始晚 60 天以上（那天）
    var energyStartedLate: Date? = nil
    /// 油車、油電（持有中）沒有任何連到這台車、還有效、每年扣的稅費（「接下來」最下面提示牌照稅、燃料費）
    var needsTaxReminder = false
    /// 今年（今天的西曆年）實際扣掉的：定期數今年扣了幾期 × 每期，變動讀記帳今年的（算到 asOf）
    var yearSpent: Double = 0
    /// 已售出的車還在扣的定期支出換算成每月（理財現金流要算到停掉為止）；持有中是 0
    var soldStillPayingMonthly: Double = 0
    /// 已售出、結束日是空的或比售出日晚的週期固定支出（「要確認」：在賣出日停止）
    var soldStillPayingIds: [UUID] = []
    /// 沒連到記帳的舊鏡像（鏡像 id）、記帳找不到的孤兒鏡像、指到別台車的鏡像
    var legacyMirrorIds: Set<UUID> = []
    var orphanMirrorIds: Set<UUID> = []
    var foreignMirrorIds: Set<UUID> = []

    /// 某一天的車貸還欠（每筆的利率只解一次，之後查表；賣掉時結清的車貸結束日之後是 0）
    func owed(at date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Double {
        loans.reduce(0) { $0 + $1.owed(at: date, calendar: calendar) }
    }

    /// 充電紀錄（有度數的電費）
    static func chargeExpenses(_ v: Vehicle, expenses: [Expense]) -> [Expense] {
        expenses.filter { $0.linkedVehicleId == v.id && $0.vehicleExpenseCategory == .electricity && ($0.evKwh ?? 0) > 0 }
    }

    static func build(_ v: Vehicle, expense e: ExpenseStore, now: Date = Date()) -> VehicleFacts {
        build(v, expenses: e.expenses, ntd: { e.ntdValue(of: $0) }, now: now)
    }

    static func monthStart(_ d: Date, _ cal: Calendar) -> Date {
        cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? cal.startOfDay(for: d)
    }

    /// 兩個日子所在的月份差幾個月（同 HouseCardFormat.monthsBetween，曆法跟著傳進來的）
    static func monthsBetween(_ a: Date, _ b: Date, _ cal: Calendar) -> Int {
        cal.dateComponents([.month], from: monthStart(a, cal), to: monthStart(b, cal)).month ?? 0
    }

    // MARK: 名稱

    /// 這些字是自動填的分類名，不是你取的名字
    private static let categoryWords: Set<String> = {
        var s: Set<String> = ["汽車", "未分類", "車位租金", "其他固定", "保險", "稅費", "固定支出", "變動支出"]
        for c in FixedCategory.allCases { s.insert(c.rawValue) }
        for c in VehicleVariableCategory.allCases { s.insert(c.rawValue) }
        for c in VehicleFixedCategory.allCases { s.insert(c.rawValue) }
        for c in LoanSubCategory.allCases { s.insert(c.rawValue) }
        for c in InsuranceSubCategory.allCases { s.insert(c.rawValue) }
        return s
    }()

    /// 車子用的分類名：.rent「車位租金」、保險（強制險／綜合險）、.subscription「訂閱」、.loan「車貸」、
    /// .other 每年扣「稅費」否則「其他固定」；變動用子分類
    static func categoryLabel(_ ex: Expense) -> String {
        switch ex.expenseType {
        case .variable:
            return ex.vehicleExpenseCategory?.rawValue ?? ex.variableCategory?.rawValue ?? "其他"
        case .fixed:
            switch ex.fixedCategory {
            case .rent?: return "車位租金"
            case .insurance?:
                if let sub = ex.insuranceSubCategory, sub == .compulsory || sub == .comprehensive { return sub.rawValue }
                return "保險"
            case .subscription?: return "訂閱"
            case .loan?: return "車貸"
            case .other?: return ex.recurrence == .yearly ? "稅費" : "其他固定"
            case nil: return "其他固定"
            case let c?: return c.rawValue
            }
        }
    }

    /// 你自己取的名稱：去掉「項目 N：」「車名-」之後，只剩分類名的不算（決定 19）
    static func ownName(_ ex: Expense, vehicleName: String) -> String? {
        let cleaned = HouseCardFormat.cleanTitle(ex.title, estateName: vehicleName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if categoryWords.contains(cleaned) || cleaned == ex.categoryName { return nil }
        return cleaned
    }

    /// 帳本列、接下來的標題：地點 → 你取的名稱 → 備註第一行 → 分類名
    static func label(_ ex: Expense, vehicleName: String) -> String {
        if let p = ex.placeName?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty { return p }
        if let own = ownName(ex, vehicleName: vehicleName) { return own }
        let memo = ex.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = memo.split(separator: "\n").first {
            let line = String(first).trimmingCharacters(in: .whitespaces)
            if !line.isEmpty { return line }
        }
        return categoryLabel(ex)
    }

    // MARK: build

    static func build(_ v: Vehicle, expenses: [Expense], ntd: (Expense) -> Double, now: Date = Date(),
                      calendar cal: Calendar = Calendar(identifier: .gregorian)) -> VehicleFacts {
        var f = VehicleFacts()
        let sold = v.isSold(asOf: now)
        let asOf: Date = sold ? min(now, v.soldDate ?? now) : now
        f.asOf = asOf
        f.isSold = sold
        let asOfDay = cal.startOfDay(for: asOf)
        let today = cal.startOfDay(for: now)
        func onOrBeforeAsOf(_ d: Date) -> Bool { cal.startOfDay(for: d) <= asOfDay }

        // ── 估值、折舊、持有 ──
        f.purchase = v.purchasePrice
        if sold, let sp = v.soldPrice, sp > 0 {
            f.value = sp
        } else if v.currentValue <= 0, v.valueUpdatedAt == nil, v.purchasePrice > 0 {
            // 決定 10：沒有更新日的 0＝還沒填，先用購入價；按過「就是 0（報廢）」（有更新日）才照 0 算
            f.value = v.purchasePrice
            f.valueIsFallback = true
        } else {
            f.value = max(0, v.currentValue)
        }
        f.saleUsesEstimate = sold && (v.soldPrice ?? 0) <= 0
        f.depreciation = f.purchase - f.value
        if f.purchase > 0, !f.valueIsFallback { f.depreciationRate = f.value / f.purchase - 1 }
        f.heldMonths = max(0, monthsBetween(v.purchaseDate, asOf, cal))
        if f.purchase > 0, !f.valueIsFallback, f.value < f.purchase, f.heldMonths >= 3 {
            f.depreciationMonthly = f.depreciation / Double(max(1, f.heldMonths))
        }

        // ── 連到哪些記帳 ──
        let links = VehicleLinks.make(v, expenses: expenses)
        let ledger = links.expenses
        f.ledgerExpenseIds = Set(ledger.map(\.id))
        f.legacyMirrorIds = Set(links.legacyFixed.map(\.id) + links.legacyVariable.map(\.id))
        f.orphanMirrorIds = links.orphanMirrorIds
        f.foreignMirrorIds = links.foreignMirrorIds

        // ── 車貸 ──
        var loans: [VehicleLoan] = []
        for ex in ledger where ex.isRecurringFixed && ex.fixedCategory == .loan {
            if let l = VehicleLoan.make(ex, title: label(ex, vehicleName: v.name), perPeriod: ntd(ex),
                                        asOf: asOf, calendar: cal) {
                loans.append(l)
            }
        }
        loans.sort { $0.start != $1.start ? $0.start < $1.start : $0.id.uuidString < $1.id.uuidString }
        if loans.count > 1, loans.allSatisfy({ $0.title == "車貸" }) {
            for i in loans.indices { loans[i].displayTitle = "第 \(i + 1) 筆" }
        }
        f.loans = loans
        f.loanPaid = loans.reduce(0) { $0 + $1.paid }
        f.loanLeft = loans.reduce(0) { $0 + $1.left }
        f.owed = loans.reduce(0) { $0 + $1.owed(at: asOf, calendar: cal) }
        f.owedIsScheduled = loans.contains { !$0.hasBalance && $0.owed(at: asOf, calendar: cal) > 0 }
        f.owedMissingTerm = loans.contains { $0.termIsGuess && $0.status == .paying }
        let known = loans.filter { !$0.termIsGuess && $0.countedPeriods > 0 }
        if let lastKnown = known.last {
            let elapsed = known.reduce(0) { $0 + $1.paidPeriods }
            let total = known.reduce(0) { $0 + $1.countedPeriods }
            let remainCount = total - elapsed
            let remainAmount = known.reduce(0.0) { $0 + Double(max(0, $1.countedPeriods - $1.paidPeriods)) * $1.perPeriod }
            // 好幾筆合併時每期金額取剩下的平均，MoneyLoanSchedule.left 才會等於各筆剩下的加總
            let per = remainCount > 0 ? remainAmount / Double(remainCount) : lastKnown.perPeriod
            let monthlyNow = known.filter { $0.isPaying(inMonth: asOf, calendar: cal) }.reduce(0.0) { $0 + $1.monthly }
            f.loan = MoneyLoanSchedule(elapsed: elapsed, total: total, perPeriod: per,
                                       monthly: monthlyNow > 0 ? monthlyNow : lastKnown.monthly)
        }

        // ── 每月養車：期間 ──
        let back = cal.date(byAdding: .month, value: -12, to: asOf) ?? asOf
        let periodStart = max(v.purchaseDate, back)
        let comps = cal.dateComponents([.month, .day], from: periodStart, to: asOf)
        let months = min(12, max(1, (comps.month ?? 0) + ((comps.day ?? 0) >= 15 ? 1 : 0)))
        let startDay = cal.startOfDay(for: periodStart)
        let thisMonth = monthStart(asOf, cal)
        f.periodStart = periodStart
        f.periodMonths = months
        func inPeriod(_ d: Date) -> Bool {
            let day = cal.startOfDay(for: d)
            return day >= startDay && day <= asOfDay
        }

        var parts = VehicleMonthlyParts()
        let isScooterSwap = v.powerType == .electricMotorcycle
        var swapMonthly = 0.0

        // 車貸：這個月落在第一期到最後一期之間的各筆，換算成每月；每一筆都算得出本金和利率才拆利息
        var interest = 0.0
        var canSplit = true
        var anyPaying = false
        for l in loans where l.isPaying(inMonth: thisMonth, calendar: cal) {
            anyPaying = true
            parts.loan += l.monthly
            if let r = l.monthlyRate, let b = l.balance {
                interest += min(l.monthly, max(0, b) * r)
            } else {
                canSplit = false
            }
        }

        // 沒連到記帳的舊定期鏡像：讀它自己的週期（年 ÷ 12）
        var legacyLoan = 0.0
        for m in links.legacyFixed {
            let monthly = m.period.toMonthly(m.amount)
            switch m.category {
            case .carLoan: legacyLoan += monthly
            case .subscription where isScooterSwap: swapMonthly += monthly
            default: parts.fixed += monthly
            }
        }
        parts.loan += legacyLoan
        if anyPaying, canSplit, legacyLoan == 0 { parts.loanInterest = interest }

        // 定期：不是貸款、這個月還有效（起始日 ≤ asOf、結束日空的或 ≥ 這個月 1 號），照它自己的週期換算
        for ex in ledger where ex.isRecurringFixed && ex.fixedCategory != .loan {
            guard let rec = ex.recurrence, onOrBeforeAsOf(ex.date) else { continue }
            if let end = ex.endDate, cal.startOfDay(for: end) < thisMonth { continue }
            let m = ntd(ex) / Double(max(1, rec.periodMonths))
            if isScooterSwap && ex.fixedCategory == .subscription {
                swapMonthly += m   // 電動機車的訂閱是換電資費：算能源
            } else {
                parts.fixed += m
            }
        }

        // 變動（含不是週期的固定支出）：期間內各類合計 ÷ 期間月數
        var fuelSum = 0.0
        var elecSum = 0.0
        var careSum = 0.0
        var otherSum = 0.0
        var firstEnergy: Date? = nil
        func addVariable(_ cat: VehicleVariableCategory?, _ amount: Double, _ date: Date) {
            guard inPeriod(date) else { return }
            switch cat {
            case .fuel?:
                fuelSum += amount
                firstEnergy = min(firstEnergy ?? date, date)
            case .electricity?:
                elecSum += amount
                firstEnergy = min(firstEnergy ?? date, date)
            case .maintenance?, .repair?:
                careSum += amount
            default:
                otherSum += amount
            }
        }
        for ex in ledger {
            if ex.expenseType == .variable {
                addVariable(ex.vehicleExpenseCategory, ntd(ex), ex.date)
            } else if !ex.isRecurringFixed && ex.fixedCategory != .loan {
                addVariable(nil, ntd(ex), ex.date)
            }
        }
        for m in links.legacyVariable { addVariable(m.category, m.amount, m.date) }

        let dm = Double(months)
        parts.energy = (fuelSum + elecSum) / dm + swapMonthly
        parts.care = careSum / dm
        parts.other = otherSum / dm
        let hasElec = elecSum > 0 || swapMonthly > 0
        let hasFuel = fuelSum > 0
        if hasElec && hasFuel {
            parts.energyLabel = "油電"
        } else if hasElec {
            parts.energyLabel = swapMonthly > 0 ? "換電・充電" : "充電"
        } else if hasFuel {
            parts.energyLabel = "加油"
        } else {
            switch v.powerType {
            case .electric, .electricMotorcycle: parts.energyLabel = "充電"
            case .gasoline, .motorcycle: parts.energyLabel = "加油"
            case .hybrid: parts.energyLabel = "油電"
            }
        }
        f.parts = parts
        f.monthly = parts.total
        f.loanMonthly = parts.loan
        if fuelSum > 0 { f.fuelPerMonth = fuelSum / dm }
        if let fe = firstEnergy,
           let late = cal.dateComponents([.day], from: startDay, to: cal.startOfDay(for: fe)).day, late >= 60 {
            f.energyStartedLate = fe
        }

        // ── 提示：沒保險、第一年沒稅費、油車沒記稅費 ──
        let dayBeforeStart = cal.date(byAdding: .day, value: -1, to: startDay) ?? startDay
        func debitedInPeriod(_ ex: Expense) -> Bool {
            if ex.isRecurringFixed {
                return ex.fixedPeriodCount(until: asOf, calendar: cal) - ex.fixedPeriodCount(until: dayBeforeStart, calendar: cal) > 0
            }
            return inPeriod(ex.date)
        }
        func isYearlyTax(_ ex: Expense) -> Bool {
            ex.isRecurringFixed && ex.recurrence == .yearly && ex.fixedCategory != .insurance && ex.fixedCategory != .loan
        }
        f.missingInsurance = !ledger.contains { $0.expenseType == .fixed && $0.fixedCategory == .insurance && debitedInPeriod($0) }
        let heldFullMonths = cal.dateComponents([.month], from: v.purchaseDate, to: asOf).month ?? 0
        f.firstYearNoTax = heldFullMonths < 12 && !ledger.contains { isYearlyTax($0) && debitedInPeriod($0) }
        if !sold, v.powerType == .gasoline || v.powerType == .hybrid {
            f.needsTaxReminder = !ledger.contains { ex in
                guard isYearlyTax(ex) else { return false }
                if let end = ex.endDate { return cal.startOfDay(for: end) >= today }
                return true
            }
        }

        // ── 里程（所有有里程錶的：電費、油錢、保養、維修）──
        let odoList = ledger.filter { ($0.odometer ?? 0) > 0 && onOrBeforeAsOf($0.date) }
        let odo = VehicleOdometer(expenses: odoList, calendar: cal)
        if !odo.readings.isEmpty || odo.hasRegression { f.odometer = odo }

        // ── 充電 ──
        if v.hasBattery {
            let chargeList = chargeExpenses(v, expenses: ledger).filter { onOrBeforeAsOf($0.date) }
            let missing = ledger.filter {
                $0.vehicleExpenseCategory == .electricity && ($0.evKwh ?? 0) <= 0 && onOrBeforeAsOf($0.date)
            }.count
            let a = VehicleChargeAnalytics(expenses: chargeList, capacityKWh: v.batteryCapacityKWh,
                                           homeKeyword: v.homeChargePlace, powerType: v.powerType,
                                           odometerExpenses: odoList)
            if a.count > 0 || missing > 0 { f.charge = VehicleChargeSummary(a, missingKwhCount: missing) }
            f.perKwh = a.avgPricePerKwh
        }

        // ── 加油 ──
        let fills = ledger.filter { $0.expenseType == .variable && $0.vehicleExpenseCategory == .fuel && onOrBeforeAsOf($0.date) }
        if !fills.isEmpty { f.fuel = VehicleFuelAnalytics(expenses: fills, ntd: ntd) }

        switch v.powerType {
        case .electric, .electricMotorcycle: f.perKm = f.charge?.avgCostPerKm
        case .gasoline, .motorcycle: f.perKm = f.fuel?.perKm
        case .hybrid: f.perKm = nil
        }

        // ── 保養 ──
        f.maintenance = maintenanceSummary(v, ledger: ledger, ntd: ntd, odometer: odo, asOf: asOf,
                                           today: today, calendar: cal)

        // ── 接下來 ──
        f.upcoming = upcomingItems(v, ledger: ledger, loans: loans, maintenance: sold ? nil : f.maintenance,
                                   ntd: ntd, now: now, calendar: cal)

        // ── 今年已花（實際扣款）──
        if let yearStart = cal.date(from: cal.dateComponents([.year], from: now)) {
            let yearEnd = min(now, asOf)
            if cal.startOfDay(for: yearStart) <= cal.startOfDay(for: yearEnd) {
                let beforeYear = cal.date(byAdding: .day, value: -1, to: yearStart) ?? yearStart
                var spent = 0.0
                for ex in ledger {
                    if ex.isRecurringFixed && ex.fixedCategory == .loan {
                        if let l = loans.first(where: { $0.id == ex.id }) {
                            let k = l.paidCount(onOrBefore: yearEnd, calendar: cal) - l.paidCount(onOrBefore: beforeYear, calendar: cal)
                            spent += Double(max(0, k)) * l.perPeriod
                        }
                    } else if ex.isRecurringFixed {
                        let k = ex.fixedPeriodCount(until: yearEnd, calendar: cal) - ex.fixedPeriodCount(until: beforeYear, calendar: cal)
                        spent += Double(max(0, k)) * ntd(ex)
                    } else {
                        let d = cal.startOfDay(for: ex.date)
                        if d >= cal.startOfDay(for: yearStart), d <= cal.startOfDay(for: yearEnd) { spent += ntd(ex) }
                    }
                }
                for m in links.legacyVariable {
                    let d = cal.startOfDay(for: m.date)
                    if d >= cal.startOfDay(for: yearStart), d <= cal.startOfDay(for: yearEnd) { spent += m.amount }
                }
                // 舊定期鏡像沒有起始日：照舊用月均 × 今年持有的月數
                let from = max(yearStart, v.purchaseDate)
                if from <= yearEnd {
                    let heldThisYear = (cal.dateComponents([.month], from: from, to: yearEnd).month ?? 0) + 1
                    let legacyMonthly = links.legacyFixed.reduce(0.0) { $0 + $1.period.toMonthly($1.amount) }
                    spent += legacyMonthly * Double(min(12, max(0, heldThisYear)))
                }
                f.yearSpent = spent
            }
        }

        // ── 賣了還在扣 ──
        if sold, let soldDate = v.soldDate {
            let soldDay = cal.startOfDay(for: soldDate)
            let nowMonth = monthStart(now, cal)
            for ex in ledger where ex.isRecurringFixed {
                if let end = ex.endDate, cal.startOfDay(for: end) <= soldDay { continue }
                f.soldStillPayingIds.append(ex.id)
                guard let rec = ex.recurrence, cal.startOfDay(for: ex.date) <= today else { continue }
                if ex.fixedCategory == .loan {
                    if let l = loans.first(where: { $0.id == ex.id }), l.isPaying(inMonth: nowMonth, calendar: cal) {
                        f.soldStillPayingMonthly += l.monthly
                    }
                } else {
                    if let end = ex.endDate, cal.startOfDay(for: end) < nowMonth { continue }
                    f.soldStillPayingMonthly += ntd(ex) / Double(max(1, rec.periodMonths))
                }
            }
        }
        return f
    }

    // MARK: 保養

    private struct MaintEvent {
        var date: Date
        var lastDate: Date
        var fromExpense: Bool
        var amount: Double?
        var km: Double?
    }

    /// 保養事件＝記帳裡這台車 .maintenance 的日期，加上照片紀錄 .maintenance 的日期；前後 3 天內算同一次。
    /// 至少 2 次才估下一次：相鄰兩次天數的中位數（小於 14 天的間隔不算，同 HouseElevatorData），
    /// 有 2 次以上填了里程錶時另算里程間隔，用年里程換成日期，兩個取早的
    private static func maintenanceSummary(_ v: Vehicle, ledger: [Expense], ntd: (Expense) -> Double,
                                           odometer odo: VehicleOdometer, asOf: Date, today: Date,
                                           calendar cal: Calendar) -> VehicleMaintenance {
        let asOfDay = cal.startOfDay(for: asOf)
        var raw: [MaintEvent] = []
        for ex in ledger where ex.vehicleExpenseCategory == .maintenance && cal.startOfDay(for: ex.date) <= asOfDay {
            let d = cal.startOfDay(for: ex.date)
            let km = ex.odometer ?? 0
            raw.append(MaintEvent(date: d, lastDate: d, fromExpense: true, amount: ntd(ex), km: km > 0 ? km : nil))
        }
        for p in v.photoRecords where p.category == .maintenance && cal.startOfDay(for: p.date) <= asOfDay {
            let d = cal.startOfDay(for: p.date)
            raw.append(MaintEvent(date: d, lastDate: d, fromExpense: false, amount: nil, km: nil))
        }
        raw.sort { $0.date != $1.date ? $0.date < $1.date : ($0.fromExpense && !$1.fromExpense) }

        var events: [MaintEvent] = []
        for e in raw {
            if var last = events.last,
               let gap = cal.dateComponents([.day], from: last.lastDate, to: e.date).day, gap <= 3 {
                // 同一次：有支出就用支出那天、金額相加、里程取大的
                if e.fromExpense && !last.fromExpense { last.date = e.date }
                last.fromExpense = last.fromExpense || e.fromExpense
                if let a = e.amount { last.amount = (last.amount ?? 0) + a }
                if let k = e.km { last.km = max(last.km ?? 0, k) }
                last.lastDate = e.date
                events[events.count - 1] = last
            } else {
                events.append(e)
            }
        }

        var m = VehicleMaintenance()
        m.count = events.count
        guard let last = events.last else { return m }
        m.last = last.date
        m.lastIsPhotoOnly = !last.fromExpense
        m.photoOnly = events.allSatisfy { !$0.fromExpense }
        let amounts = events.compactMap(\.amount).filter { $0 > 0 }
        if !amounts.isEmpty { m.amount = median(amounts) }
        guard events.count >= 2 else { return m }

        var gaps: [Int] = []
        for i in 1..<events.count {
            let d = cal.dateComponents([.day], from: events[i - 1].date, to: events[i].date).day ?? 0
            if d >= 14 { gaps.append(d) }
        }
        gaps.sort()
        var next: Date? = nil
        if !gaps.isEmpty {
            let mid = gaps.count / 2
            let med = gaps.count % 2 == 1 ? gaps[mid] : Int((Double(gaps[mid - 1] + gaps[mid]) / 2).rounded())
            if med > 0 {
                m.medianDays = med
                next = cal.date(byAdding: .day, value: med, to: last.date)
            }
        }
        // 里程間隔：填了里程錶的那幾次，相鄰兩次的里程差中位數
        let withKm = events.filter { $0.km != nil }
        if withKm.count >= 2 {
            var kmGaps: [Double] = []
            for i in 1..<withKm.count {
                if let a = withKm[i - 1].km, let b = withKm[i].km, b > a { kmGaps.append(b - a) }
            }
            if !kmGaps.isEmpty {
                let medKm = median(kmGaps)
                m.medianKm = medKm
                if let lastKm = withKm.last?.km, let annual = odo.annualKm, annual > 0,
                   let latestKm = odo.latestKm, let latestDate = odo.latestDate {
                    let leftKm = lastKm + medKm - latestKm
                    let days = Int((leftKm / annual * 365).rounded())
                    if let byKm = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: latestDate)) {
                        next = next.map { min($0, byKm) } ?? byKm
                    }
                }
            }
        }
        m.next = next
        if let n = next, let over = cal.dateComponents([.day], from: n, to: today).day, over > 0 {
            m.overdueDays = over
        }
        return m
    }

    private static func median(_ v: [Double]) -> Double {
        let s = v.sorted()
        guard !s.isEmpty else { return 0 }
        let mid = s.count / 2
        return s.count % 2 == 1 ? s[mid] : (s[mid - 1] + s[mid]) / 2
    }

    /// 「1 萬公里」「8,000 公里」（不到 1 萬取到百位）
    private static func kmText(_ km: Double) -> String {
        if km >= 10_000 {
            let w = (km / 1_000).rounded() / 10
            let t = w == w.rounded() ? String(format: "%.0f", w) : String(format: "%.1f", w)
            return t + " 萬公里"
        }
        let r = Int((km / 100).rounded() * 100)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return (f.string(from: NSNumber(value: r)) ?? "\(r)") + " 公里"
    }

    /// 「6 個月」「45 天」
    private static func intervalText(days: Int) -> String {
        if days < 45 { return "\(days) 天" }
        let months = max(1, Int((Double(days) / 30.44).rounded()))
        return "\(months) 個月"
    }

    // MARK: 接下來

    private static func upcomingItems(_ v: Vehicle, ledger: [Expense], loans: [VehicleLoan],
                                      maintenance: VehicleMaintenance?, ntd: (Expense) -> Double,
                                      now: Date, calendar cal: Calendar) -> [VehicleUpcoming] {
        let today = cal.startOfDay(for: now)
        let horizon = cal.date(byAdding: .month, value: 12, to: today) ?? today
        let yesterday = cal.date(byAdding: .day, value: -1, to: today) ?? today
        var out: [VehicleUpcoming] = []
        for ex in ledger where ex.isRecurringFixed {
            guard let rec = ex.recurrence else { continue }
            if ex.fixedCategory == .loan {
                guard let l = loans.first(where: { $0.id == ex.id }),
                      let n = l.next(onOrAfter: today, calendar: cal), n.date <= horizon else { continue }
                let detail = l.termIsGuess ? "第 \(n.index) 期" : "第 \(n.index)／\(l.scheduledPeriods) 期"
                out.append(VehicleUpcoming(id: "loan-" + ex.id.uuidString, date: n.date, kind: .loan(ex.id),
                                           title: l.displayTitle, detail: detail, amount: l.perPeriod))
            } else {
                guard let next = ex.nextFixedDueDate(onOrAfter: today, calendar: cal), next <= horizon else { continue }
                var detail = rec.rawValue
                // 上一期＝第 fixedPeriodCount 期（數到昨天：今天剛好要扣時，上次是上一個週期那天）
                let n = ex.fixedPeriodCount(until: yesterday, calendar: cal)
                if n > 0 {
                    let (component, step) = rec.componentValue
                    if let lastDue = cal.date(byAdding: component, value: step * (n - 1), to: ex.date) {
                        detail += "・上次 " + HouseCardFormat.shortDate(lastDue, now: now)
                    }
                }
                out.append(VehicleUpcoming(id: "fixed-" + ex.id.uuidString, date: next, kind: .fixed(ex.id),
                                           title: label(ex, vehicleName: v.name), detail: detail, amount: ntd(ex)))
            }
        }
        if let m = maintenance, let next = m.next, let last = m.last, next <= horizon {
            // 「平均每 6 個月一次」；有里程間隔時「平均每 6 個月或 1 萬公里一次」
            var every: [String] = []
            if let d = m.medianDays { every.append(intervalText(days: d)) }
            if let km = m.medianKm { every.append(kmText(km)) }
            var detail = "平均每 " + every.joined(separator: "或 ") + " 一次・上次 " + HouseCardFormat.ymd(last)
            if m.lastIsPhotoOnly { detail += "（照片紀錄）" }
            let title = m.photoOnly ? "保養維修（估計）" : "保養（估計）"
            out.append(VehicleUpcoming(id: "maintenance-" + v.id.uuidString, date: next, kind: .maintenance,
                                       title: title, detail: detail, amount: m.amount ?? 0,
                                       isEstimate: true, overdueDays: m.overdueDays))
        }
        out.sort { $0.date != $1.date ? $0.date < $1.date : $0.title < $1.title }
        return out
    }
}

// MARK: - 賣車時把車貸、保險、稅費停在賣出日

enum VehicleSale {
    /// 連到這台車的車貸、保險、稅費（fixedCategory .loan／.insurance／.other 每年）。
    /// 停車月租、訂閱可能賣了還要留著，不自動停，交給「要確認」（決定 6）
    static func stoppableExpenseIds(of v: Vehicle, expenses: [Expense]) -> Set<UUID> {
        var ids = Set<UUID>()
        for ex in VehicleLinks.make(v, expenses: expenses).expenses where ex.isRecurringFixed {
            switch ex.fixedCategory {
            case .loan?, .insurance?:
                ids.insert(ex.id)
            case .other? where ex.recurrence == .yearly:
                ids.insert(ex.id)
            default:
                break
            }
        }
        return ids
    }

    /// 照 RealEstateSale.syncMortgageStops：標成已售出時，原本沒有結束日、結束日比賣出日晚、或上次就是因為賣車停的，
    /// 結束日改成賣出日、endReason＝.assetSold；soldDate 為 nil（取消已售出）時把 .assetSold 的還原：
    /// 車貸回到照年限推算的最後一期（suggestedEndDate），保險、稅費回到沒有結束日。
    /// 只改傳進來的陣列，回傳有沒有改到，呼叫端一次寫回 store。
    @discardableResult
    static func syncStops(of v: Vehicle, soldDate: Date?, in expenses: inout [Expense],
                          now: Date = Date(), calendar cal: Calendar = Calendar(identifier: .gregorian)) -> Bool {
        let ids = stoppableExpenseIds(of: v, expenses: expenses)
        guard !ids.isEmpty else { return false }
        var changed = false
        for i in expenses.indices where ids.contains(expenses[i].id) {
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
                if expenses[i].fixedCategory == .loan {
                    let suggested = expenses[i].suggestedEndDate
                    expenses[i].endDate = suggested
                    if let s = suggested, s < now {
                        expenses[i].endReason = .paidOff
                    } else {
                        expenses[i].endReason = nil
                    }
                } else {
                    expenses[i].endDate = nil
                    expenses[i].endReason = nil
                }
                changed = true
            }
        }
        return changed
    }
}
