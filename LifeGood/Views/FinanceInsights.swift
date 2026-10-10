import SwiftUI

// MARK: - 理財看板的計算（v25.527）
//
// 使用者：「接著我們來做理財介面，幫我仔細規劃完整」，看過規劃與樣稿：「就照你建議的吧，一次做完」。
// 規劃裡要新算的數字都在這裡（看板在 FinanceBoards.swift，風景在 FinanceBoardScenes.swift）：
// - 淨資產＝資產（全部換成台幣）− 貸款還要繳
// - 每個月理財的現金流（進來：租金、股利；出去：房貸、保費、養車）
// - 接下來 30 天要繳、要領的（保費、房貸、車貸與車子的稅費、保單滿期）
// - 每個月的淨資產：從現在起每月記一筆；之前的月份回推，畫面上標「估算」
//
// 跟 FinanceStore 原本的總計不一樣的地方（原本的照舊留著，人生頁還在用）：
// - 儲蓄險用「今天」的價值（SavingsInsurance.value(at:)）。存檔裡的 currentValue 是最後一次
//   編輯那天算的、之後不會更新，放兩年就停在兩年前。外幣保單一律換成台幣。
//   已經滿期的保單不再算資產（錢已經領回去了）。
// - 已經賣掉的車不算（FinanceStore.totalVehicleValue 連賣掉的也加進去）。
// - 貸款「還要繳」＝剩下的期數 × 每期金額，含利息，所以淨資產會偏保守一點（畫面上有寫）。
//   房地產的房貸期數、車子連結的車貸、記帳裡其他的貸款各算一次：連結到房子、車子的那幾筆
//   固定支出不會在「其他貸款」裡再算一次。

// MARK: - 資產類別

enum FinanceAssetKind: String, CaseIterable, Identifiable {
    case realEstate, savings, stock, vehicle

    var id: String { rawValue }

    var name: String {
        switch self {
        case .realEstate: return "房地產"
        case .savings: return "儲蓄險"
        case .stock: return "股票"
        case .vehicle: return "載具"
        }
    }

    /// 點明信片要切到的理財分頁
    var feature: FinanceFeature {
        switch self {
        case .realEstate: return .realEstate
        case .savings: return .insurance
        case .stock: return .stock
        case .vehicle: return .vehicle
        }
    }

    var theme: MoneyArtTheme {
        switch self {
        case .realEstate: return .finHome
        case .savings: return .finSavings
        case .stock: return .finStock
        case .vehicle: return .finDrive
        }
    }
}

// MARK: - 台幣換算

/// 幣別 → 台幣匯率（記帳設定裡的匯率表：「美金」→ 32）。查不到的幣別當 1（跟原本一樣）。
struct FinanceRates {
    private let map: [String: Double]

    init(_ store: ExpenseStore) {
        var m: [String: Double] = ["NT$": 1, "TWD": 1, "": 1]
        for r in store.currencyRates where r.rate > 0 { m[r.code] = r.rate }
        map = m
    }

    func rate(_ code: String) -> Double { map[code] ?? 1 }

    /// 設定裡有沒有這個幣別的匯率（沒有是 nil；rate(_:) 查不到會當 1）
    func known(_ code: String) -> Double? { map[code] }

    func ntd(_ amount: Double, code: String) -> Double { amount * rate(code) }

    static func isNTD(_ code: String) -> Bool { code == "NT$" || code == "TWD" || code.isEmpty }
}

// MARK: - 某一天的資產與貸款

struct FinanceSnapshot: Equatable {
    var realEstate: Double = 0
    var savings: Double = 0
    var stock: Double = 0
    var vehicle: Double = 0
    /// 房貸還要繳（房地產的貸款項目：剩下的期數 × 每期金額）
    var mortgage: Double = 0
    /// 車貸還要繳（車子連結的記帳固定支出）
    var carLoan: Double = 0
    /// 記帳裡其他的貸款（沒有連結到房子、車子的）
    var otherLoan: Double = 0

    var assets: Double { realEstate + savings + stock + vehicle }
    var debt: Double { mortgage + carLoan + otherLoan }
    var netWorth: Double { assets - debt }

    func value(_ k: FinanceAssetKind) -> Double {
        switch k {
        case .realEstate: return realEstate
        case .savings: return savings
        case .stock: return stock
        case .vehicle: return vehicle
        }
    }
}

enum FinanceLoans {
    /// 一筆貸款類的週期性固定支出，在 date 那天還要繳多少（台幣）。
    /// 有年期或總額 → 照期數算（Expense.moneyLoanSchedule）；只有結束日 → 數到結束日還有幾期；
    /// 兩個都沒有 → nil（不知道還要繳多久，不猜）。
    static func remaining(_ e: Expense, at date: Date, store: ExpenseStore,
                          calendar cal: Calendar = .current) -> Double? {
        guard e.isRecurringFixed, let rec = e.recurrence else { return nil }
        let day = cal.startOfDay(for: date)
        guard cal.startOfDay(for: e.date) <= day else { return nil }
        if let end = e.endDate, cal.startOfDay(for: end) < day { return 0 }
        if let s = e.moneyLoanSchedule(now: date, calendar: cal) {
            return s.isDone ? 0 : s.left
        }
        guard let end = e.endDate,
              let afterEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: end)) else { return nil }
        // 第 k 期＝第一期＋k 個週期（貸款的第一期是起始日的下一期，跟 Expense.nextFixedDueDate 同一套）。
        // 用算的找出「今天以後的第一期」與「結束日以後的第一期」，相減就是還有幾期（回推好幾年的
        // 每月淨資產時每個月都要算，不能一期一期數）。
        let (component, step) = rec.componentValue
        let first = e.fixedCategory == .loan ? (cal.date(byAdding: component, value: step, to: e.date) ?? e.date) : e.date
        func index(atOrAfter target: Date) -> Int {
            let t = cal.startOfDay(for: target)
            let n = cal.dateComponents([component], from: first, to: t).value(for: component) ?? 0
            var k = max(0, n / step - 1)
            var steps = 0
            while steps < 8, let d = cal.date(byAdding: component, value: step * k, to: first), cal.startOfDay(for: d) < t {
                k += 1
                steps += 1
            }
            return k
        }
        return Double(max(0, index(atOrAfter: afterEnd) - index(atOrAfter: day))) * store.ntdValue(of: e)
    }

    /// 已經算在房子、車子裡的貸款（它們連結的記帳固定支出），「其他貸款」不再算一次
    static func linkedExpenseIds(_ f: FinanceStore) -> Set<UUID> {
        var ids = Set<UUID>()
        for re in f.realEstates {
            if let id = re.linkedExpenseId { ids.insert(id) }
            for m in re.mortgageItems { if let id = m.linkedExpenseId { ids.insert(id) } }
        }
        for v in f.vehicles {
            for fe in v.fixedExpenses { if let id = fe.linkedExpenseId { ids.insert(id) } }
        }
        return ids
    }

    /// 一台車的車貸：車子定期支出裡連結的車貸，加上記帳裡連結到這台車的貸款（兩邊只算一次）
    static func carLoanIds(_ v: Vehicle, expenses: [Expense]) -> Set<UUID> {
        var ids = Set(v.fixedExpenses.filter { $0.category == .carLoan }.compactMap(\.linkedExpenseId))
        for ex in expenses where ex.linkedVehicleId == v.id && ex.isRecurringFixed && ex.fixedCategory == .loan {
            ids.insert(ex.id)
        }
        return ids
    }

    /// 房貸一個項目在 date 那天還剩幾期（還沒開始的那一段不算欠）
    static func mortgagePeriodsLeft(_ m: RealEstateMortgageItem, at date: Date,
                                    calendar cal: Calendar = .current) -> Int {
        guard m.startDate <= date else { return 0 }
        let months = cal.dateComponents([.month], from: m.startDate, to: date).month ?? 0
        return max(0, m.totalPeriods - min(max(0, months), m.totalPeriods))
    }
}

/// 掃一次記帳的支出，把貸款整理好：回推好幾年的每月淨資產時每個月都要用，不要每個月重掃
struct FinanceLoanIndex {
    /// 車子 → 它的車貸
    let carLoans: [UUID: [Expense]]
    /// 沒有連結到房子、車子的貸款（「其他貸款」）
    let otherLoans: [Expense]

    init(finance f: FinanceStore, expense e: ExpenseStore) {
        let byId = Dictionary(e.expenses.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let loans = e.expenses.filter { $0.isRecurringFixed && $0.fixedCategory == .loan }
        var car: [UUID: [Expense]] = [:]
        for v in f.vehicles {
            car[v.id] = FinanceLoans.carLoanIds(v, expenses: loans).compactMap { byId[$0] }
        }
        carLoans = car
        // 連結到房子、車子的不算（房貸看房地產的貸款項目、車貸在 carLoans）
        let linked = FinanceLoans.linkedExpenseIds(f)
        let realEstateIds = Set(f.realEstates.map(\.id))
        let vehicleIds = Set(f.vehicles.map(\.id))
        otherLoans = loans.filter { ex in
            if linked.contains(ex.id) { return false }
            if let id = ex.linkedRealEstateId, realEstateIds.contains(id) { return false }
            if let id = ex.linkedVehicleId, vehicleIds.contains(id) { return false }
            return true
        }
    }
}

extension FinanceSnapshot {
    /// 現在的資產與貸款
    static func current(finance f: FinanceStore, expense e: ExpenseStore, rates: FinanceRates,
                        now: Date = Date(), index: FinanceLoanIndex? = nil) -> FinanceSnapshot {
        compute(finance: f, expense: e, rates: rates, at: now, now: now, stockValue: nil, index: index)
    }

    /// 某一天的資產與貸款。date 是現在就照現在的資料；過去的日子回推：
    /// 房子、車子在買入價與現在的估值之間平均變化；儲蓄險照複利公式回算（精確）；
    /// 股票有那幾天的市值紀錄就用（stockValue），沒有就用當時持股的成本。
    static func compute(finance f: FinanceStore, expense e: ExpenseStore, rates: FinanceRates,
                        at date: Date, now: Date, stockValue: Double?,
                        index: FinanceLoanIndex? = nil) -> FinanceSnapshot {
        let cal = Calendar.current
        let isNow = abs(date.timeIntervalSince(now)) < 60
        var s = FinanceSnapshot()
        let loans = index ?? FinanceLoanIndex(finance: f, expense: e)

        for re in f.realEstates {
            guard re.purchaseDate <= date else { continue }
            if let sold = re.soldDate, sold <= date { continue }
            s.realEstate += isNow ? re.currentValue
                : lerp(re.purchasePrice, re.currentValue, from: re.purchaseDate, to: re.soldDate ?? now, at: date)
            for m in re.mortgageItems {
                s.mortgage += Double(FinanceLoans.mortgagePeriodsLeft(m, at: date, calendar: cal)) * m.amount
            }
        }

        for v in f.vehicles {
            guard v.purchaseDate <= date else { continue }
            if let sold = v.soldDate, sold <= date { continue }
            s.vehicle += isNow ? v.currentValue
                : lerp(v.purchasePrice, v.currentValue, from: v.purchaseDate, to: v.soldDate ?? now, at: date)
            for ex in loans.carLoans[v.id] ?? [] {
                if let left = FinanceLoans.remaining(ex, at: date, store: e, calendar: cal) { s.carLoan += left }
            }
        }

        for ins in f.insurances where ins.startDate <= date && date < ins.maturityDate {
            s.savings += rates.ntd(ins.value(at: date), code: ins.currencyCode)
        }

        if isNow {
            s.stock = f.stocks.filter { !$0.isSold }.reduce(0) { $0 + $1.marketValue }
        } else if let stockValue {
            s.stock = stockValue
        } else {
            s.stock = f.stocks.reduce(0) { $0 + $1.moneyCostHeld(at: date) }
        }

        for ex in loans.otherLoans {
            if let left = FinanceLoans.remaining(ex, at: date, store: e, calendar: cal) { s.otherLoan += left }
        }
        return s
    }

    /// 兩個日子之間平均變化（買入價沒填就整段用現在的估值）
    private static func lerp(_ a: Double, _ b: Double, from: Date, to: Date, at: Date) -> Double {
        guard a > 0 else { return b }
        let span = to.timeIntervalSince(from)
        guard span > 0 else { return b }
        let t = min(1, max(0, at.timeIntervalSince(from) / span))
        return a + (b - a) * t
    }
}

// MARK: - 股票的幾個數字

extension Stock {
    /// date 那天還持有幾股（照交易紀錄；沒有交易紀錄的舊資料用買入日／賣出日判斷）
    func moneySharesHeld(at date: Date) -> Double {
        if transactions.isEmpty {
            guard purchaseDate <= date else { return 0 }
            if isSold, let sold = soldDate, sold <= date { return 0 }
            return shares
        }
        var held: Double = 0
        for tx in transactions where tx.date <= date {
            held += tx.kind == .buy ? tx.shares : -tx.shares
        }
        for d in dividends where d.kind == .stock && d.date <= date {
            held += d.sharesEarned
        }
        return max(0, held)
    }

    /// date 那天持股的成本（台幣）：回推過去的股票市值時，沒有市值紀錄就用這個
    func moneyCostHeld(at date: Date) -> Double {
        moneySharesHeld(at: date) * purchasePrice * currencyFactor
    }

    /// 已實現損益（台幣）：賣出金額 − 賣出股數 × 成本均價。賣光的、賣一部分的都算。
    /// 原本的 profitLoss 只看「還持有的」（賣光之後股數是 0，損益也變 0），所以另外算。
    var moneyRealizedProfit: Double {
        if transactions.isEmpty {
            guard isSold, shares > 0, soldPrice > 0 else { return 0 }
            return shares * (soldPrice - purchasePrice) * currencyFactor
        }
        var sellShares: Double = 0
        var sellAmount: Double = 0
        for tx in transactions where tx.kind == .sell {
            sellShares += tx.shares
            sellAmount += tx.shares * tx.price
        }
        guard sellShares > 0 else { return 0 }
        return (sellAmount - sellShares * purchasePrice) * currencyFactor
    }

    /// 某一段時間領到的現金股利（台幣）
    func moneyCashDividends(from start: Date, to end: Date) -> Double {
        dividends
            .filter { $0.kind == .cash && $0.date >= start && $0.date <= end }
            .reduce(0) { $0 + $1.cashTotal } * currencyFactor
    }

    /// 「今日漲跌」要比的那個價錢：前一個交易日的收盤價。
    /// 先用報價時記下來的（StockPreviousClose）；沒有就看日線快取：
    /// 最後一根是今天、或現價就是最後一根的收盤（週末、假日）→ 比它前一根；
    /// 現價跟最後一根不一樣（快取是舊的）→ 比最後一根。都沒有是 nil（不顯示，不猜）。
    func moneyPreviousClose(now: Date = Date()) -> Double? {
        guard !symbol.isEmpty else { return nil }
        if let p = StockPreviousClose.value(symbol, now: now) { return p }
        let pts = StockDailyHistory.cached(symbol: symbol)
        guard pts.count >= 2, let last = pts.last, now.timeIntervalSince(last.date) < 5 * 86_400 else { return nil }
        let sameSession = Calendar.current.isDate(last.date, inSameDayAs: now)
            || abs(currentPrice - last.close) <= last.close * 0.0001
        return sameSession ? pts[pts.count - 2].close : last.close
    }
}

/// 報價時順便記下「前一個交易日的收盤價」（MIS 的 y、興櫃的前日均價、Yahoo 的 chartPreviousClose），
/// 股票看板與卡片的「今日漲跌」用。只是快取：不同步，清掉也沒關係（退回日線快取）。
enum StockPreviousClose {
    private static let key = "stock_previous_close_v1"

    static func remember(_ quotes: [String: TWQuoteService.Quote], at now: Date = Date()) {
        var map = (UserDefaults.standard.dictionary(forKey: key) as? [String: [Double]]) ?? [:]
        var changed = false
        for (sym, q) in quotes {
            guard let p = q.previousClose, p > 0 else { continue }
            map[sym] = [p, now.timeIntervalSince1970]
            changed = true
        }
        if changed { UserDefaults.standard.set(map, forKey: key) }
    }

    /// 四天內記的才算（跨一個週末還有效；放太久的不知道是哪一天的）
    static func value(_ symbol: String, now: Date = Date()) -> Double? {
        guard let map = UserDefaults.standard.dictionary(forKey: key) as? [String: [Double]],
              let v = map[symbol], v.count == 2, v[0] > 0,
              now.timeIntervalSince1970 - v[1] < 4 * 86_400 else { return nil }
        return v[0]
    }
}

// MARK: - 儲蓄險的幾個日子

extension SavingsInsurance {
    /// 一期幾個月
    var moneyMonthsPerPeriod: Int { paymentPeriod == .monthly ? 1 : (paymentPeriod == .quarterly ? 3 : 12) }

    /// 一年繳幾期
    var moneyPeriodsPerYear: Int { 12 / moneyMonthsPerPeriod }

    /// 還沒滿期（滿期那天起錢就領回去了，不再算資產）
    func moneyIsLive(now: Date = Date()) -> Bool { now < maturityDate }

    /// 下一期保費哪天扣（起始日當天扣第一期，之後每期一次）；都繳完了是 nil
    func moneyNextDue(now: Date = Date()) -> Date? {
        let paid = elapsedPeriods(at: now)
        guard paid < totalPeriods else { return nil }
        return Calendar.current.date(byAdding: .month, value: paid * moneyMonthsPerPeriod, to: startDate)
    }

    /// 整張保單的保費總額（每期 × 總期數）
    var moneyFullPremium: Double { premiumAmount * Double(totalPeriods) }

    /// 到期領回比全部保費多幾成（0.15＝多 15%）；沒有保費是 nil
    var moneyGainRate: Double? {
        let full = moneyFullPremium
        guard full > 0 else { return nil }
        return calculatedExpectedReturn / full - 1
    }
}

// MARK: - 每個月理財的現金流

struct FinanceCashFlow: Equatable {
    /// 進來（每月）
    var rent: Double = 0
    /// 近 12 個月的現金股利 ÷ 12
    var dividends: Double = 0
    /// 出去（每月）
    var mortgage: Double = 0
    /// 還在繳的保單：年繳保費 ÷ 12（換成台幣）
    var premiums: Double = 0
    /// 車子：定期支出的月均＋近 12 個月的變動支出 ÷ 12
    var vehicle: Double = 0

    var inflow: Double { rent + dividends }
    var outflow: Double { mortgage + premiums + vehicle }
    var net: Double { inflow - outflow }
    var isEmpty: Bool { inflow <= 0 && outflow <= 0 }

    static func build(finance f: FinanceStore, rates: FinanceRates, now: Date = Date()) -> FinanceCashFlow {
        let cal = Calendar.current
        let yearAgo = cal.date(byAdding: .year, value: -1, to: now) ?? now
        var c = FinanceCashFlow()
        for re in f.realEstates where !re.isSold {
            c.rent += re.monthlyRental
            c.mortgage += re.monthlyMortgage
        }
        for s in f.stocks {
            c.dividends += s.moneyCashDividends(from: yearAgo, to: now) / 12
        }
        for ins in f.insurances where ins.startDate <= now && now < ins.maturityDate
            && ins.elapsedPeriods < ins.totalPeriods {
            c.premiums += rates.ntd(ins.annualPremium / 12, code: ins.currencyCode)
        }
        for v in f.vehicles where !v.isSold {
            let recent = v.variableExpenses.filter { $0.date >= yearAgo && $0.date <= now }.reduce(0) { $0 + $1.amount }
            c.vehicle += v.monthlyFixedTotal + recent / 12
        }
        return c
    }
}

// MARK: - 接下來 30 天

struct FinanceUpcoming: Identifiable, Equatable {
    enum Kind: Equatable { case premium, maturity, mortgage, vehicle }

    let id: String
    let kind: Kind
    let title: String
    let detail: String?
    let date: Date
    /// 0＝今天、1＝明天…
    let daysAway: Int
    let amount: String
    /// 會領回來的錢（保單滿期）：金額前面加 +、綠色
    let isIncome: Bool

    var icon: String {
        switch kind {
        case .premium: return "shield.lefthalf.filled"
        case .maturity: return "star.fill"
        case .mortgage: return "house.fill"
        case .vehicle: return "car.fill"
        }
    }

    var tint: TripBoardTint {
        switch kind {
        case .premium: return .blue
        case .maturity: return .orange
        case .mortgage: return .purple
        case .vehicle: return .mint
        }
    }

    static func build(finance f: FinanceStore, expense e: ExpenseStore, now: Date = Date(),
                      days: Int = 30) -> [FinanceUpcoming] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard let horizon = cal.date(byAdding: .day, value: days + 1, to: today) else { return [] }
        let expenseById = Dictionary(e.expenses.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [FinanceUpcoming] = []
        func away(_ d: Date) -> Int {
            max(0, cal.dateComponents([.day], from: today, to: cal.startOfDay(for: d)).day ?? 0)
        }

        // 保費：起始日當天扣第一期，之後每期一次（跟 SavingsInsurance.elapsedPeriods 同一套）
        for ins in f.insurances {
            if let due = ins.moneyNextDue(now: now), due >= today, due < horizon {
                out.append(FinanceUpcoming(id: "p-\(ins.id)", kind: .premium, title: ins.name,
                                           detail: "第 \(ins.elapsedPeriods(at: now) + 1)／\(ins.totalPeriods) 期",
                                           date: due, daysAway: away(due),
                                           amount: FinanceText.money(ins.premiumAmount, code: ins.currencyCode),
                                           isIncome: false))
            }
            if ins.maturityDate >= today, ins.maturityDate < horizon {
                out.append(FinanceUpcoming(id: "m-\(ins.id)", kind: .maturity, title: ins.name + " 滿期",
                                           detail: "可以領回", date: ins.maturityDate,
                                           daysAway: away(ins.maturityDate),
                                           amount: "+" + FinanceText.money(ins.calculatedExpectedReturn,
                                                                           code: ins.currencyCode),
                                           isIncome: true))
            }
        }

        // 房貸：有連結記帳固定支出就照那一筆的扣款日，沒有就從起始日每月一期
        for re in f.realEstates where !re.isSold {
            for m in re.mortgageItems where m.isPayingNow || m.startDate >= today {
                var due: Date?
                if let id = m.linkedExpenseId, let ex = expenseById[id] {
                    due = ex.nextFixedDueDate(onOrAfter: today, calendar: cal)
                } else {
                    let months = max(0, cal.dateComponents([.month], from: m.startDate, to: today).month ?? 0)
                    for k in months...(months + 1) where k < m.totalPeriods {
                        if let d = cal.date(byAdding: .month, value: k, to: m.startDate), d >= today {
                            due = d
                            break
                        }
                    }
                }
                guard let d = due, d < horizon else { continue }
                let index = (cal.dateComponents([.month], from: m.startDate, to: d).month ?? 0) + 1
                let name = m.title.trimmingCharacters(in: .whitespaces).isEmpty ? "房貸" : m.title
                out.append(FinanceUpcoming(id: "r-\(m.id)", kind: .mortgage, title: re.name + " " + name,
                                           detail: index <= m.totalPeriods ? "第 \(index)／\(m.totalPeriods) 期" : nil,
                                           date: d, daysAway: away(d), amount: m.amount.ntdWanString, isIncome: false))
            }
        }

        // 車子的定期支出（車貸、稅費、訂閱）：只有連結了記帳固定支出的才知道哪天扣
        for v in f.vehicles where !v.isSold {
            for fe in v.fixedExpenses {
                guard let id = fe.linkedExpenseId, let ex = expenseById[id],
                      let d = ex.nextFixedDueDate(onOrAfter: today, calendar: cal), d < horizon else { continue }
                out.append(FinanceUpcoming(id: "v-\(fe.id)", kind: .vehicle, title: v.name + " " + fe.category.rawValue,
                                           detail: nil, date: d, daysAway: away(d),
                                           amount: e.ntdValue(of: ex).ntdWanString, isIncome: false))
            }
        }
        return out.sorted { $0.date == $1.date ? $0.title < $1.title : $0.date < $1.date }
    }
}

// MARK: - 每個月的淨資產

struct FinanceMonthPoint: Identifiable, Equatable {
    /// 那個月的第一天
    let month: Date
    let assets: Double
    let debt: Double
    /// true＝那個月有打開過理財頁、存下來的；false＝回推的估算
    let recorded: Bool

    var netWorth: Double { assets - debt }
    var id: Date { month }
}

enum FinanceHistory {
    /// 跟股票每週市值一樣放進 iCloud 同步（CloudSyncManager.syncKeys）：先拉後推，歷史只增不減
    static let key = "finance_month_records_v1"

    private struct Record: Codable {
        let month: String
        let assets: Double
        let debt: Double
    }

    private static let monthFmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f
    }()

    private static func load() -> [String: Record] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Record].self, from: data) else { return [:] }
        return Dictionary(list.map { ($0.month, $0) }, uniquingKeysWith: { _, b in b })
    }

    /// 記下這個月（同一個月覆寫成最新的）。值幾乎沒變就不寫，免得每次打開都觸發同步。
    static func record(_ s: FinanceSnapshot, now: Date = Date()) {
        guard s.assets > 0 || s.debt > 0 else { return }
        var map = load()
        let k = monthFmt.string(from: now)
        if let old = map[k], abs(old.assets - s.assets) < 1, abs(old.debt - s.debt) < 1 { return }
        map[k] = Record(month: k, assets: s.assets, debt: s.debt)
        var list = map.values.sorted { $0.month < $1.month }
        if list.count > 240 { list.removeFirst(list.count - 240) }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// 從哪個月開始有資料（最早買的房子、車子、股票、保單）；最多往回 10 年
    static func firstMonth(finance f: FinanceStore, now: Date = Date()) -> Date {
        let cal = Calendar.current
        var dates: [Date] = f.realEstates.map(\.purchaseDate) + f.vehicles.map(\.purchaseDate)
            + f.insurances.map(\.startDate) + f.stocks.map(\.purchaseDate)
        dates += f.stocks.flatMap { $0.transactions.map(\.date) }
        let earliest = dates.min() ?? now
        let floor = cal.date(byAdding: .year, value: -10, to: now) ?? now
        let d = max(earliest, floor)
        return cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? d
    }

    /// 最近 months 個月，每月一點（最後一點是現在）。有存下來的用存下來的，沒有的回推。
    static func series(months: Int, finance f: FinanceStore, expense e: ExpenseStore, rates: FinanceRates,
                       now: Date = Date()) -> [FinanceMonthPoint] {
        let cal = Calendar.current
        guard months > 0, let thisMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) else {
            return []
        }
        let records = load()
        let weekly = StockValueHistory.load()
        let index = FinanceLoanIndex(finance: f, expense: e)
        var out: [FinanceMonthPoint] = []
        for back in stride(from: months - 1, through: 0, by: -1) {
            guard let start = cal.date(byAdding: .month, value: -back, to: thisMonth) else { continue }
            if back == 0 {
                let s = FinanceSnapshot.current(finance: f, expense: e, rates: rates, now: now, index: index)
                out.append(FinanceMonthPoint(month: start, assets: s.assets, debt: s.debt, recorded: true))
                continue
            }
            if let r = records[monthFmt.string(from: start)] {
                out.append(FinanceMonthPoint(month: start, assets: r.assets, debt: r.debt, recorded: true))
                continue
            }
            guard let next = cal.date(byAdding: .month, value: 1, to: start) else { continue }
            let end = next.addingTimeInterval(-1)
            // 股票：那個月底前 45 天內有每週市值紀錄就用，沒有就用持股成本
            let stockValue = weekly.last { $0.weekStart <= end && $0.weekStart > end.addingTimeInterval(-45 * 86_400) }?.value
            let s = FinanceSnapshot.compute(finance: f, expense: e, rates: rates, at: end, now: now,
                                            stockValue: stockValue, index: index)
            out.append(FinanceMonthPoint(month: start, assets: s.assets, debt: s.debt, recorded: false))
        }
        return out
    }
}
