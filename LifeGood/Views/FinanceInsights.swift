import SwiftUI

// MARK: - 理財看板的計算（v25.527）
//
// 使用者：「接著我們來做理財介面，幫我仔細規劃完整」，看過規劃與樣稿：「就照你建議的吧，一次做完」。
// 規劃裡要新算的數字都在這裡（看板在 FinanceBoards.swift，風景在 FinanceBoardScenes.swift）：
// - 淨資產＝資產（全部換成台幣）− 貸款還欠多少
// - 每個月理財的現金流（進來：租金、股利；出去：房貸、保費、養車）
// - 接下來 30 天要繳、要領的（保費、房貸、保單滿期；車子的車貸、保險、稅費、月租、訂閱與保養估計）
// - 每個月的淨資產：從現在起每月記一筆；之前的月份回推，畫面上標「估算」
//
// 跟 FinanceStore 原本的總計不一樣的地方（原本的照舊留著，人生頁還在用）：
// - 儲蓄險用「今天」的價值（SavingsInsurance.value(at:)）。存檔裡的 currentValue 是最後一次
//   編輯那天算的、之後不會更新，放兩年就停在兩年前。外幣保單一律換成台幣。
//   已經滿期的保單不再算資產（錢已經領回去了）。
// - 已經賣掉的車不算（以前 FinanceStore.totalVehicleValue 連賣掉的也加進去，v25.539 起也不算了）。
//   [v25.538] 但它還在扣的車貸照算進負債，算到那筆貸款停扣那天（車子賣了，貸款不一定跟著停）。
// - [v25.532] 房貸算的是還欠銀行的本金（HouseFacts：用借款本金和每期金額反推，沒填借款本金時
//   用購入價減自備款推算，畫面上寫「約」；連本金都推不出來才退回含利息的「還要繳」）。
//   以前房貸也是含利息的還要繳，淨資產被利息多扣了一大截，跟房屋卡片上的數字也對不起來。
// - [v25.539] 車貸也改算還欠的本金（VehicleFacts：用總貸款金額和每期金額反推，同房貸；算不出來的那筆
//   才退回含利息的還要繳）。車子的估值、每月養車、接下來要繳的也都讀 VehicleFacts，跟車子卡片、列表同一個數。
// - 其他貸款仍是「還要繳」＝剩下的期數 × 每期金額，含利息，所以這部分會偏保守一點（畫面上有寫）。
//   房子的房貸、車子連結的車貸、記帳裡其他的貸款各算一次：連結到房子、車子的那幾筆
//   固定支出不會在「其他貸款」裡再算一次。
// - [v25.565] 財富 v4（wealth/judge.md §6.4；build/v4/brief.md §2）：資產多「存款」（財富頁的存款合計，存摺上）；
//   負債多「卡費」（卡費還沒扣＋已經排定的提款）與「待交割」（成交了、還沒交割的股票款）。數字一律讀財富的一套數字
//   （AppStores.life.wealthFacts，跟財富頁同一份快取）：買股票那天股票多了市值、待交割多了股款，交割那天存款少了、待交割歸零，
//   兩天淨資產都只差手續費。以前的月份照財富帳戶的紀錄回推（WealthFacts.history，口徑 4）。
//   接下來 30 天多「卡費」「交割」：刷卡的定期扣款（保費、車子的訂閱…）併進那一期卡費，自己不再另外一列（待決定 4）。
//   現金流不加卡費（卡費是記帳支出的另一面，加了算兩次）。

// MARK: - 資產類別

enum FinanceAssetKind: String, CaseIterable, Identifiable {
    /// [v25.565] cash＝存款（財富頁的存款合計）。這個列舉不存檔、不同步（rawValue 只當小工具的 key），可以加
    case realEstate, savings, stock, vehicle, cash

    var id: String { rawValue }

    var name: String {
        switch self {
        case .realEstate: return "房地產"
        case .savings: return "儲蓄險"
        case .stock: return "股票"
        case .vehicle: return "載具"
        case .cash: return "存款"
        }
    }

    /// 點明信片要切到的理財分頁。[v25.565] 存款不在理財：nil＝切到人生 › 財富（AppNavigation.goToWealth()）
    var feature: FinanceFeature? {
        switch self {
        case .realEstate: return .realEstate
        case .savings: return .insurance
        case .stock: return .stock
        case .vehicle: return .vehicle
        case .cash: return nil
        }
    }

    var theme: MoneyArtTheme {
        switch self {
        case .realEstate: return .finHome
        case .savings: return .finSavings
        case .stock: return .finStock
        case .vehicle: return .finDrive
        case .cash: return .wealthLive
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

    /// [v25.562] 不經 ExpenseStore、直接拿一份匯率表建（房屋水電編輯器手上只有 [CurrencyRate]）。
    /// 規則跟 init(_:) 一模一樣：rate > 0 的才收，同名的後面蓋前面。
    init(rates: [CurrencyRate]) {
        var m: [String: Double] = ["NT$": 1, "TWD": 1, "": 1]
        for r in rates where r.rate > 0 { m[r.code] = r.rate }
        map = m
    }

    /// [v25.562] 這個幣別是不是美元（使用者自己取的名字：「美金」「美元」「USD」「US$」都算）
    static func isUSD(_ code: String) -> Bool {
        if FXRateService.isoCode(for: code) == "USD" { return true }
        let up = code.uppercased()
        return up.contains("USD") || up.contains("US$")
    }

    /// [v25.562] 一筆台幣金額要寫進帳戶的哪一格、寫多少（全 App 只有這一支：記帳、AI 記帳、收入、
    /// 複製收入／支出、固定支出與月薪展開、股票交割、房屋水電都走這裡）。規則一行一條：
    /// 1. 帳戶這格是台幣 → 台幣金額照寫
    /// 2. 原本就是這個幣別（外幣儲蓄險的原幣保費）→ 原幣金額照寫
    /// 3. 設定裡有這個幣別的匯率 → 台幣 ÷ 匯率，四捨五入到 0.01
    /// 4. 查不到匯率 → 寫進這個帳戶的台幣那一格（錢至少對），不再把台幣數字標成外幣
    func accountAmount(ntd: Double, original: (amount: Double, code: String)? = nil,
                       into code: String) -> (amount: Double, code: String) {
        if Self.isNTD(code) { return (ntd, code.isEmpty ? "NT$" : code) }
        if let o = original, o.code == code { return (o.amount, code) }
        if let r = known(code), r > 0 {
            let converted: Double = (ntd / r * 100).rounded() / 100
            return (converted, code)
        }
        return (ntd, "NT$")
    }

    /// [v25.562] 一筆支出直接扣銀行時寫多少、寫哪一格（帳戶幣別＝exp.linkedBankCurrency，沒存當台幣）。
    /// ntd 由呼叫端用 ExpenseStore.ntdValue(of:) 算好傳進來（換台幣只有那一支）。
    func bankAmount(of exp: Expense, ntd: Double) -> (amount: Double, code: String) {
        accountAmount(ntd: ntd, original: exp.originalCurrencyAmount, into: exp.linkedBankCurrency ?? "NT$")
    }
}

extension Stock {
    /// [v25.562] 這檔股票自己有交割帳戶（銀行或證券戶）：跟它有關的收入、支出（配息、賣出獲利／虧損、
    /// 從記帳買的那筆）不再碰銀行，銀行的錢只看股票自己寫的交割、股利紀錄（不然在收入頁改一次就多入帳一次）。
    /// 記帳「買 0050（台新）」建出來的股票沒有交割帳戶 → 那筆記帳照樣扣台新。
    var hasOwnSettlementAccount: Bool {
        (linkedBankMilestoneId ?? linkedSecuritiesMilestoneId) != nil
    }
}

extension Expense {
    /// [v25.562] 金額是不是用原幣存的：只有外幣儲蓄險（amount 沒乘匯率，見 ExpenseStore.ntdValue(of:)）。
    /// 其他支出存檔時就換成台幣了，currencyCode 只是當初輸入的幣別。
    var originalCurrencyAmount: (amount: Double, code: String)? {
        guard fixedCategory == .insurance, insuranceSubCategory == .savings,
              !FinanceRates.isNTD(currencyCode) else { return nil }
        return (amount, currencyCode)
    }
}

// MARK: - 某一天的資產與貸款

struct FinanceSnapshot: Equatable {
    var realEstate: Double = 0
    var savings: Double = 0
    var stock: Double = 0
    var vehicle: Double = 0
    /// [v25.532] 房貸還欠多少（每間 HouseFacts.owed(at:)：本金；算不出本金的那間才是含利息的還要繳）
    var mortgage: Double = 0
    /// [v25.539] 車貸還欠多少（每台 VehicleFacts 的每一筆車貸 owed(at:)：本金；算不出本金的那筆才是含利息的還要繳）
    var carLoan: Double = 0
    /// 記帳裡其他的貸款（沒有連結到房子、車子的）
    var otherLoan: Double = 0
    /// [v25.532] 有房子還欠的本金是推算的（購入價 − 自備款）：畫面寫「約」
    var mortgageEstimated = false
    /// [v25.532] 有房子算不出本金、退回含利息的還要繳：畫面寫「還要繳」
    var mortgageScheduled = false
    /// [v25.539] 有車貸算不出本金（沒填總貸款金額等）、退回含利息的還要繳：畫面要寫車貸時寫「還要繳」
    var carLoanScheduled = false
    /// [v25.539] 有車貸的本金是用平均利率反推的（利率 > 0；零利率的本金剛好是借款 − 已繳，不算推估）：
    /// 畫面寫「約」，同 mortgageEstimated（決定 2）
    var carLoanEstimated = false
    /// [v25.565] 存款（財富頁的存款合計，存摺上；算進存款合計、沒收起來的銀行帳戶，換台幣）
    var cash: Double = 0
    /// [v25.565] 有幣別查不到匯率（存款前面寫「約」）
    var cashApprox = false
    /// [v25.565] 卡費：卡費還沒扣（要繳＋還沒出帳）＋已經排定、還沒到的提款（WealthFacts.netWorthCardOwed）
    var cardOwed: Double = 0
    /// [v25.565] 待交割：成交了、還沒交割的股票款
    var pendingSettlement: Double = 0
    /// [v25.565 裁定] 賣股票還沒入帳（WealthFacts.pendingIncoming；以前的月份查 history）：算進「存款」那一類（value(.cash)）。
    /// 成交當天股票市值就少了、賣出款 T+2 才進存摺，不加淨資產會假跌兩天（買的那一邊是 pendingSettlement 擋掉）
    var pendingIncoming: Double = 0
    /// [v25.565] 以前的月份：有財富帳戶那天還沒開始記（存款是往前平推的）
    var wealthEstimated = false

    /// [v25.565] 資產含存款（[v25.565 裁定] ＋賣股票還沒入帳，算在存款那一類）
    var assets: Double { realEstate + savings + stock + vehicle + cash + pendingIncoming }
    /// [v25.565] 負債含卡費、待交割
    var debt: Double { mortgage + carLoan + otherLoan + cardOwed + pendingSettlement }
    var netWorth: Double { assets - debt }
    /// [v25.565] 只有貸款（房貸＋車貸＋其他貸款）：「貸款還欠 900萬」、「沒有貸款」看這個
    var loans: Double { mortgage + carLoan + otherLoan }
    /// [v25.565] 卡費與交割（「卡費與交割 10萬」；0 不寫）
    var wealthOwed: Double { cardOwed + pendingSettlement }

    func value(_ k: FinanceAssetKind) -> Double {
        switch k {
        case .realEstate: return realEstate
        case .savings: return savings
        case .stock: return stock
        case .vehicle: return vehicle
        case .cash: return cash + pendingIncoming
        }
    }
}

enum FinanceLoans {
    /// 一筆貸款類的週期性固定支出，在 date 那天還要繳多少（台幣）。
    /// [v25.532] 記帳分類是貸款、有年限或結束日 → 照期數算（Expense.moneyLoanSchedule，跟房屋卡片同一套期數）；
    /// 不是貸款分類（車子連結的定期支出）只有結束日 → 數到結束日還有幾期；都沒有 → nil（不知道還要繳多久，不猜）。
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

    /// 已經算在房子裡的貸款（房子連結的記帳固定支出），「其他貸款」不再算一次。
    /// [v25.538] 車子的不在這裡排除，改在 FinanceLoanIndex 用「有沒有算進某台車」排除（同一份名單）：
    /// 以前連到車子的一律排除、賣掉的車又整台跳過，還在扣的車貸就從負債消失
    static func linkedExpenseIds(_ f: FinanceStore) -> Set<UUID> {
        var ids = Set<UUID>()
        for re in f.realEstates {
            if let id = re.linkedExpenseId { ids.insert(id) }
            for m in re.mortgageItems { if let id = m.linkedExpenseId { ids.insert(id) } }
        }
        return ids
    }

    /// 一台車的車貸：車子定期支出裡連結的車貸，加上記帳裡連結到這台車的貸款（兩邊只算一次）。
    /// [v25.539] 理財總覽不再用它：改讀 VehicleFacts.loans（同一筆只算給記帳 linkedVehicleId 那一台，
    /// 鏡像指到別台車的不算），跟車子卡片同一份名單
    static func carLoanIds(_ v: Vehicle, expenses: [Expense]) -> Set<UUID> {
        var ids = Set(v.fixedExpenses.filter { $0.category == .carLoan }.compactMap(\.linkedExpenseId))
        for ex in expenses where ex.linkedVehicleId == v.id && ex.isRecurringFixed && ex.fixedCategory == .loan {
            ids.insert(ex.id)
        }
        return ids
    }
}

/// 掃一次記帳的支出，把貸款整理好：回推好幾年的每月淨資產時每個月都要用，不要每個月重掃
struct FinanceLoanIndex {
    /// [v25.539] 車子 → 算在它身上的車貸（VehicleLoan 的 id＝記帳支出 id）。同一筆只算給一台，負債不會扣兩次
    let carLoanIds: [UUID: Set<UUID>]
    /// 沒有連結到房子、車子的貸款（「其他貸款」）
    let otherLoans: [Expense]
    /// [v25.532] 房子 → 它的 HouseFacts（含已售出的）。每間只建一次，淨資產、現金流、接下來 30 天、
    /// 每月回推都讀這一份，跟房屋卡片、看板同一套數字；回推每個月只查表（owed(at:)），不重算。
    let houses: [UUID: HouseFacts]
    /// [v25.539] 車子 → 它的 VehicleFacts（含已售出的），照 houses：每台只建一次，淨資產（估值、車貸還欠）、
    /// 現金流（每月養車）、接下來 30 天都讀這一份，跟車子卡片、列表、載具頁看板同一個數。
    /// 車貸的利率在 build 時只解一次，回推每個月只查表（VehicleLoan.owed(at:)）。
    let vehicles: [UUID: VehicleFacts]
    /// [v25.565] 財富的一套數字（AppStores.life.wealthFacts：跟財富頁同一份快取）。**一律是今天的**（不看 now）：
    /// 小工具「接下來要繳」往後推 15 天建第二份 index 時，財富還是今天這一份（卡費、交割照今天算好的日子列）
    let wealth: WealthFacts

    /// 呼叫端簽章不變；財富讀 AppStores.life（主執行緒：理財頁的 .task、小工具快照的寫手都在主執行緒）
    init(finance f: FinanceStore, expense e: ExpenseStore, now: Date = Date()) {
        wealth = AppStores.life.wealthFacts(expense: e, finance: f)
        var h: [UUID: HouseFacts] = [:]
        for re in f.realEstates {
            h[re.id] = HouseFacts.build(re, expenses: e.expenses, now: now)
        }
        houses = h
        let cars = FinanceLoanIndex.vehicleFacts(f, expense: e, now: now)
        vehicles = cars
        // [v25.538] 含已售出的車：車子賣了，車貸不一定跟著停（FinanceSnapshot 照每筆的結束日算到停扣那天）。
        // [v25.539] 名單改讀 VehicleFacts：記帳 linkedVehicleId＝這台 ∪ 鏡像找得到的，鏡像指到的那筆
        // linkedVehicleId 是別台時只算那一台（舊的 carLoanIds 兩台都會撿）。兩台的鏡像都指著同一筆、
        // 記帳又沒寫是哪台時，照車子的順序只算給第一台
        var counted = Set<UUID>()
        var ownedByVehicle = Set<UUID>()
        var car: [UUID: Set<UUID>] = [:]
        for v in f.vehicles {
            guard let facts = cars[v.id] else { continue }
            let ids = Set(facts.loans.map(\.id)).subtracting(counted)
            counted.formUnion(ids)
            car[v.id] = ids
            ownedByVehicle.formUnion(facts.ledgerExpenseIds)
        }
        carLoanIds = car
        // [v25.538] 連結到房子的不算（房貸在 houses）；算進某台車的也不算（同一份名單）：
        // 一筆貸款不會兩邊都算、也不會兩邊都沒算。
        // [v25.539] 用整台車的記帳名單排除，不只排除建得出車貸的那幾筆：每期 0 元、結束日比第一期還早
        // 這種建不出車貸的，算車貸是 0，也不該跑去「其他貸款」
        let linked = FinanceLoans.linkedExpenseIds(f)
        let realEstateIds = Set(f.realEstates.map(\.id))
        let loans = e.expenses.filter { $0.isRecurringFixed && $0.fixedCategory == .loan }
        otherLoans = loans.filter { ex in
            if ownedByVehicle.contains(ex.id) { return false }
            if linked.contains(ex.id) { return false }
            if let id = ex.linkedRealEstateId, realEstateIds.contains(id) { return false }
            return true
        }
    }

    /// [v25.539] 每台車（含已售出）的 VehicleFacts。現金流、接下來 30 天沒拿到 index 時也用這個自己建
    static func vehicleFacts(_ f: FinanceStore, expense e: ExpenseStore, now: Date = Date()) -> [UUID: VehicleFacts] {
        var map: [UUID: VehicleFacts] = [:]
        for v in f.vehicles {
            map[v.id] = VehicleFacts.build(v, expense: e, now: now)
        }
        return map
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
        let loans = index ?? FinanceLoanIndex(finance: f, expense: e, now: now)

        // [v25.532] 估值與還欠都讀 HouseFacts：估值沒填時用購入價（賣掉的用成交價），還欠看本金
        for re in f.realEstates {
            guard re.purchaseDate <= date else { continue }
            if let sold = re.soldDate, sold <= date { continue }
            let facts = loans.houses[re.id]
            let value = facts?.value ?? re.currentValue
            s.realEstate += isNow ? value
                : lerp(re.purchasePrice, value, from: re.purchaseDate, to: re.soldDate ?? now, at: date)
            let owed = facts?.owed(at: date, calendar: cal) ?? 0
            s.mortgage += owed
            if owed > 0, facts?.owedIsEstimate == true { s.mortgageEstimated = true }
            if owed > 0, facts?.owedIsScheduled == true { s.mortgageScheduled = true }
        }

        // [v25.539] 估值與車貸都讀 VehicleFacts（同車子卡片）：估值 0 而且沒有更新日＝還沒填，用購入價；
        // 賣掉的用成交價（沒填用估值）；車貸看本金。車貸的扣款日是西曆算的，查表也用西曆
        let greg = Calendar(identifier: .gregorian)
        for v in f.vehicles {
            let facts = loans.vehicles[v.id]
            // [v25.538] 車貸先算、而且只看那筆貸款自己的起訖日：車子賣了貸款不一定跟著停，
            // 以前賣掉的車整台跳過，還在扣的車貸就從負債消失。賣車時停掉的（結束日＝賣出日）之後是 0
            if let facts, let ids = loans.carLoanIds[v.id] {
                for l in facts.loans where ids.contains(l.id) {
                    let owed = l.owed(at: date, calendar: greg)
                    s.carLoan += owed
                    if owed > 0, !l.hasBalance { s.carLoanScheduled = true }
                    if owed > 0, l.hasBalance, (l.monthlyRate ?? 0) > 0 { s.carLoanEstimated = true }
                }
            }
            guard v.purchaseDate <= date else { continue }
            // 跟列表、看板同一個「已售出」：售出日當天起就算賣了
            if v.isSold(asOf: date) { continue }
            let value = facts?.value ?? v.currentValue
            // 回推的終點是 asOf（已售出＝售出日、用成交價；還沒賣＝今天、用估值）：售出日填在未來的，
            // 估值是今天的估值，不是那天的
            let end = min(v.soldDate ?? now, now)
            s.vehicle += isNow ? value
                : lerp(v.purchasePrice, value, from: v.purchaseDate, to: end, at: date)
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

        // [v25.565] 存款、卡費、待交割：現在讀財富的一套數字；以前的月份查 WealthFacts.history（口徑 4）
        let w = loans.wealth
        if isNow {
            s.cash = w.cash
            s.cashApprox = w.cashIsApprox
            s.cardOwed = w.netWorthCardOwed
            s.pendingSettlement = w.pendingSettlement
            s.pendingIncoming = w.pendingIncoming
        } else {
            let p = w.history.point(endOf: date)
            s.cash = p.cash
            s.cardOwed = p.cardOwed
            s.pendingSettlement = p.pending
            s.pendingIncoming = p.incoming
            s.wealthEstimated = p.estimated
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
    /// [v25.539] 車子：持有中每台的每月養車（VehicleFacts.monthly，含車貸月付；跟車子卡片、列表、看板同一個數）
    /// ＋已售出的車還在扣的定期支出（停車月租、訂閱這類賣車不會自動停的，扣到停掉為止）
    var vehicle: Double = 0

    var inflow: Double { rent + dividends }
    var outflow: Double { mortgage + premiums + vehicle }
    var net: Double { inflow - outflow }
    var isEmpty: Bool { inflow <= 0 && outflow <= 0 }

    /// [v25.532] houses 是 FinanceLoanIndex.houses：房貸用 HouseFacts 的「這個月房貸」
    /// （這個月有在繳的段，季繳年繳換算成每月），跟房屋卡片同一個數。以前把每期金額直接當月付，
    /// 哪幾段在繳也是另一套期數規則。
    /// [v25.539] vehicles 是 FinanceLoanIndex.vehicles（請傳進來，每台只建一次）；沒傳時用全 App 那份記帳自己建
    static func build(finance f: FinanceStore, rates: FinanceRates, houses: [UUID: HouseFacts],
                      vehicles: [UUID: VehicleFacts]? = nil, now: Date = Date()) -> FinanceCashFlow {
        let cal = Calendar.current
        let yearAgo = cal.date(byAdding: .year, value: -1, to: now) ?? now
        var c = FinanceCashFlow()
        for re in f.realEstates where !re.isSold {
            c.rent += re.monthlyRental
            c.mortgage += houses[re.id]?.monthlyMortgage ?? 0
        }
        for s in f.stocks {
            c.dividends += s.moneyCashDividends(from: yearAgo, to: now) / 12
        }
        for ins in f.insurances where ins.startDate <= now && now < ins.maturityDate
            && ins.elapsedPeriods < ins.totalPeriods {
            c.premiums += rates.ntd(ins.annualPremium / 12, code: ins.currencyCode)
        }
        // [v25.539] 以前這裡另寫一份：車子鏡像的定期月均＋近 12 個月變動 ÷ 12，季繳當月繳、繳完停掉的照算、
        // 只靠記帳連過來的不算，跟列表卡不是同一個數；賣掉的車整台跳過，賣了還在扣的停車月租、訂閱就不見了
        let cars = vehicles ?? FinanceLoanIndex.vehicleFacts(f, expense: AppStores.expense, now: now)
        for v in f.vehicles {
            guard let facts = cars[v.id] else { continue }
            c.vehicle += facts.isSold ? facts.soldStillPayingMonthly : facts.monthly
        }
        return c
    }
}

// MARK: - 接下來 30 天

struct FinanceUpcoming: Identifiable, Equatable {
    /// [v25.565] cardBill＝信用卡卡費（含刷這張卡的定期扣款）、settlement＝股票交割（財富 v4）
    enum Kind: Equatable { case premium, maturity, mortgage, vehicle, cardBill, settlement }

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
    /// [v25.565] 財富的那一張：卡費＝那張卡、交割＝交割銀行帳戶。點了彈出財富卡片頁（不切分頁，judge §6.8）；其他種類 nil。
    /// [v25.566] 定存到期（kind .maturity）＝那個銀行帳戶：有 wealthId 的一律彈出財富卡片頁
    var wealthId: UUID? = nil
    /// [v25.566] 換一個圖示（定存到期「lock.open.fill」）；nil＝照種類
    var symbol: String? = nil

    var icon: String {
        if let s = symbol { return s }
        switch kind {
        case .premium: return "shield.lefthalf.filled"
        case .maturity: return "star.fill"
        case .mortgage: return "house.fill"
        case .vehicle: return "car.fill"
        case .cardBill: return "creditcard.fill"
        case .settlement: return "arrow.left.arrow.right"
        }
    }

    var tint: TripBoardTint {
        switch kind {
        case .premium: return .blue
        case .maturity: return .orange
        case .mortgage: return .purple
        case .vehicle: return .mint
        case .cardBill: return .orange
        case .settlement: return .violet
        }
    }

    /// houses 是 FinanceLoanIndex.houses（房貸的扣款日、第幾期都讀它）。
    /// [v25.539] vehicles 是 FinanceLoanIndex.vehicles（車子的列都讀 VehicleFacts.upcoming）；沒傳時自己建
    /// [v25.565] wealth 是 FinanceLoanIndex.wealth（卡費、交割；沒傳時讀 AppStores.life 那一份快取）。財富一律是今天的：
    /// now 往後推（小工具第二次叫）時，卡費、交割照今天算好的日子落在這個窗裡的才列
    /// [v25.566] includeDeposits：定存到期也列（理財總覽「接下來 30 天」傳 true；小工具「接下來要繳」不列：那不是要繳的錢）
    static func build(finance f: FinanceStore, expense e: ExpenseStore, houses: [UUID: HouseFacts],
                      vehicles: [UUID: VehicleFacts]? = nil,
                      now: Date = Date(), days: Int = 30, wealth: WealthFacts? = nil,
                      includeDeposits: Bool = false) -> [FinanceUpcoming] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard let horizon = cal.date(byAdding: .day, value: days + 1, to: today) else { return [] }
        var out: [FinanceUpcoming] = []
        func away(_ d: Date) -> Int {
            max(0, cal.dateComponents([.day], from: today, to: cal.startOfDay(for: d)).day ?? 0)
        }
        // [v25.565] 刷卡的定期扣款（保費、車子的訂閱…）那一期併進卡費那一列，這裡不另外列（待決定 4）
        let w: WealthFacts = wealth ?? AppStores.life.wealthFacts(expense: e, finance: f)
        let book = AppStores.life.wealthBook
        let cardIds = Set(w.cards.map(\.id))
        let expensesById = Dictionary(e.expenses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func onCard(_ expenseId: UUID?, _ date: Date) -> Bool {
            guard !cardIds.isEmpty, let id = expenseId, let ex = expensesById[id] else { return false }
            guard let t = WealthFacts.recurringTarget(ex, at: date, history: book.links(ex.id)) else { return false }
            return cardIds.contains(t)
        }
        // 保單 → 它的保費那筆記帳（保單上記的、或記帳那邊連到這張保單的）
        var premiumExpense: [UUID: UUID] = [:]
        for ins in f.insurances {
            if let id = ins.linkedExpenseId { premiumExpense[ins.id] = id }
        }
        for ex in e.expenses {
            if let insId = ex.linkedInsuranceId, premiumExpense[insId] == nil { premiumExpense[insId] = ex.id }
        }

        // 保費：起始日當天扣第一期，之後每期一次（跟 SavingsInsurance.elapsedPeriods 同一套）
        for ins in f.insurances {
            if let due = ins.moneyNextDue(now: now), due >= today, due < horizon, !onCard(premiumExpense[ins.id], due) {
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

        // [v25.532] 房貸：每一段的下一期讀 HouseFacts（跟房屋卡片、記帳固定支出同一套期數規則），
        // 以前這裡自己用月份差展開，第幾期常跟卡片差一期
        for re in f.realEstates where !re.isSold {
            guard let facts = houses[re.id] else { continue }
            for seg in facts.segments {
                guard let next = seg.nextDue(onOrAfter: today, calendar: cal), next.date < horizon else { continue }
                // [v25.565] 房貸刷卡（很少見）：併進卡費
                if onCard(seg.linkedExpenseId, next.date) { continue }
                let d = next.date
                let detail = "第 \(next.index)／\(seg.countedPeriods) 期"
                let title = re.name + " " + seg.displayTitle
                let amount = seg.perPeriod.ntdWanString
                out.append(FinanceUpcoming(id: "r-\(seg.id)", kind: .mortgage, title: title,
                                           detail: detail, date: d, daysAway: away(d),
                                           amount: amount, isIncome: false))
            }
        }

        // [v25.539] 車子：讀 VehicleFacts.upcoming（跟車子卡片的「接下來」同一份）。以前只看車子鏡像，
        // 只靠記帳 linkedVehicleId 連過來的車貸、保險都不見，標籤又一律寫鏡像分類（停車月租也叫「稅費」）。
        // 現在含保險、「第 26／60 期」，標籤是你取的名字，沒有才寫分類名（車位租金、保險、訂閱、稅費、其他固定）。
        // 已售出的車也看：它的 upcoming 只剩賣了還在扣的（停車月租、訂閱、沒停的車貸），那些錢還是會扣
        let cars = vehicles ?? FinanceLoanIndex.vehicleFacts(f, expense: e, now: now)
        var seenVehicleItems = Set<String>()
        for v in f.vehicles {
            guard let facts = cars[v.id] else { continue }
            // 保養超過預計日期的（日期在今天以前）不列，留給車子卡片提醒
            for u in facts.upcoming where u.date >= today && u.date < horizon {
                // [v25.565] 刷卡的（車險、停車月租、訂閱刷卡）：併進卡費
                if onCard(vehicleExpenseId(u), u.date) { continue }
                // 兩台車的鏡像都指著同一筆（記帳沒寫是哪台）時只列一次：id 是「fixed-支出id」這種，不會跨車撞
                guard seenVehicleItems.insert(u.id).inserted else { continue }
                out.append(vehicleItem(u, vehicleName: v.name, loans: facts.loans, daysAway: away(u.date)))
            }
        }

        // [v25.565] 卡費：每張卡接下來要繳的幾期（刷卡的定期扣款已經併在裡面，小字「含 Netflix、Spotify」）。
        // 過了截止日還沒繳的放在財富的今天（不跟著 now 往後推：小工具第二次叫不會多一列）
        for c in w.cards {
            for d in c.dues {
                let day: Date = d.status == .overdue ? w.today : cal.startOfDay(for: d.due)
                guard day >= today, day < horizon else { continue }
                var parts: [String] = [d.modeText]
                if let r = d.recurringText { parts.append(r) }
                out.append(FinanceUpcoming(id: "c-\(c.id.uuidString)-\(d.key)", kind: .cardBill,
                                           title: c.name + " 卡費", detail: parts.joined(separator: "・"),
                                           date: day, daysAway: away(day), amount: d.amountText,
                                           isIncome: false, wealthId: c.id))
            }
        }
        // [v25.565] 交割：買＝從交割銀行扣、賣＝入帳（同一天相抵）
        for st in w.settlements {
            let day = cal.startOfDay(for: st.day)
            guard day >= today, day < horizon else { continue }
            out.append(FinanceUpcoming(id: "s-" + st.id, kind: .settlement, title: st.title,
                                       detail: st.directionText, date: day, daysAway: away(day),
                                       amount: (st.isOutflow ? "" : "+") + st.amountText,
                                       isIncome: !st.isOutflow, wealthId: st.accountId))
        }
        // [v25.566] 定存到期（judge §6.4「定存到期（v5）」）：「台灣銀行 定存到期」「本息續存」「約 NT$508,500」；
        // 轉活存的寫「轉進薪轉」、金額「約 +NT$508,500」（錢會進活存）。點了彈出那個帳戶的卡片頁
        if includeDeposits {
            for t in w.timeDeposits where t.status == .active || t.status == .notStarted {
                guard let m = t.maturity else { continue }
                let day = cal.startOfDay(for: m)
                guard day >= today, day < horizon else { continue }
                let detail: String
                switch t.mode {
                case .renewAll: detail = "本息續存"
                case .renewPrincipal: detail = "本金續存・利息轉進" + (t.payoutName ?? t.accountName)
                case .toLive: detail = "轉進" + (t.payoutName ?? t.accountName)
                case .decide: detail = "到期再決定"
                }
                let incoming = t.mode == .toLive
                let amount = "約 " + (incoming ? "+" : "") + WealthFormat.money(t.maturityAmount, code: t.code)
                out.append(FinanceUpcoming(id: "d-" + t.id.uuidString, kind: .maturity, title: t.accountName + " 定存到期",
                                           detail: detail, date: day, daysAway: away(day), amount: amount,
                                           isIncome: incoming, wealthId: t.accountId, symbol: "lock.open.fill"))
            }
        }
        return out.sorted { $0.date == $1.date ? $0.title < $1.title : $0.date < $1.date }
    }

    /// [v25.565] 車子的一件連的是哪一筆記帳（定期支出、車貸；保養沒有）
    private static func vehicleExpenseId(_ u: VehicleUpcoming) -> UUID? {
        switch u.kind {
        case .fixed(let id): return id
        case .loan(let id): return id
        case .maintenance: return nil
        }
    }

    /// [v25.539] 車子的一件：細字只留週期（「每月」）或期數（「第 26／60 期」），「上次 10/5」在 30 天清單裡用不到；
    /// 保養是估計的，金額寫「約」
    private static func vehicleItem(_ u: VehicleUpcoming, vehicleName: String, loans: [VehicleLoan],
                                    daysAway: Int) -> FinanceUpcoming {
        var title = u.title
        let detail: String?
        let amount: String
        switch u.kind {
        case .loan(let loanId):
            // 同一台兩筆都沒取名時，卡片在「車貸」區底下寫「第 1 筆」看得懂；這張清單沒有區塊標題，
            // 只寫「Taycan 第 1 筆」看不出是什麼，前面補回分類名「車貸（第 1 筆）」
            if let l = loans.first(where: { $0.id == loanId }), l.displayTitle != l.title {
                title = l.title + "（" + l.displayTitle + "）"
            }
            detail = u.detail
            amount = u.amount.ntdWanString
        case .fixed:
            detail = u.detail.components(separatedBy: "・").first
            amount = u.amount.ntdWanString
        case .maintenance:
            detail = u.detail.components(separatedBy: "・").first
            amount = u.amount > 0 ? "約 " + u.amount.ntdWanString : "—"
        }
        return FinanceUpcoming(id: "v-" + u.id, kind: .vehicle, title: vehicleName + " " + title,
                               detail: detail, date: u.date, daysAway: daysAway,
                               amount: amount, isIncome: false)
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

    /// [v25.532] 記下來的數字是哪一套口徑算的。v25.532 起房貸改算還欠的本金（之前是含利息的還要繳），
    /// 舊紀錄的負債多了一大截利息；不分開的話，改版那個月淨資產會突然跳一階、「比上月」也會假漲。
    /// 沒有這欄（舊紀錄，解碼是 nil）＝房貸含利息；2＝房貸算本金。
    /// [v25.539] 3＝車貸也算本金（以前是含利息的還要繳）：同房貸那次，舊口徑的月份負債用現在這套重算，
    /// 改版那個月淨資產不會突然跳一階、「比上月」也不會假漲
    /// [v25.565] 4＝資產含存款、負債含卡費與待交割（財富 v4）：舊口徑的月份照財富帳戶的紀錄回推那個月底的
    /// 存款、卡費、待交割加回去（WealthFacts.history），改版那個月不跳一階、「比上月」不假漲。
    /// 還沒更新的 iPad 寫的口徑 3 紀錄，新版一律重新加回（不採用它的數字）
    private static let currentBasis = 4

    private struct Record: Codable {
        let month: String
        let assets: Double
        let debt: Double
        /// [v25.532] 口徑（見 currentBasis）；舊紀錄、舊版 App 同步過來的是 nil
        let basis: Int?
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
        // [v25.532] 舊口徑的紀錄就算數字一樣也要重寫，才會換成新口徑
        if let old = map[k], old.basis == currentBasis,
           abs(old.assets - s.assets) < 1, abs(old.debt - s.debt) < 1 { return }
        map[k] = Record(month: k, assets: s.assets, debt: s.debt, basis: currentBasis)
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
    /// [v25.532] index：呼叫端已經建好的就傳進來（HouseFacts 每間只建一次），沒傳才自己建。
    static func series(months: Int, finance f: FinanceStore, expense e: ExpenseStore, rates: FinanceRates,
                       now: Date = Date(), index: FinanceLoanIndex? = nil) -> [FinanceMonthPoint] {
        let cal = Calendar.current
        guard months > 0, let thisMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) else {
            return []
        }
        let records = load()
        let weekly = StockValueHistory.load()
        let loans = index ?? FinanceLoanIndex(finance: f, expense: e, now: now)
        var out: [FinanceMonthPoint] = []
        for back in stride(from: months - 1, through: 0, by: -1) {
            guard let start = cal.date(byAdding: .month, value: -back, to: thisMonth) else { continue }
            if back == 0 {
                let s = FinanceSnapshot.current(finance: f, expense: e, rates: rates, now: now, index: loans)
                out.append(FinanceMonthPoint(month: start, assets: s.assets, debt: s.debt, recorded: true))
                continue
            }
            guard let next = cal.date(byAdding: .month, value: 1, to: start) else { continue }
            let end = next.addingTimeInterval(-1)
            if let r = records[monthFmt.string(from: start)] {
                if r.basis == currentBasis {
                    out.append(FinanceMonthPoint(month: start, assets: r.assets, debt: r.debt, recorded: true))
                    continue
                }
                // [v25.532] 舊口徑（房貸含利息；v25.539 起車貸含利息也是舊口徑）：資產照存的，負債用現在這套重算那個月月底，
                // 改版那個月才不會跳一階、「比上月」也不會因為少扣利息而假漲
                // [v25.565] redo 已含那個月底的存款、卡費、待交割（WealthFacts.history）
                let redo = FinanceSnapshot.compute(finance: f, expense: e, rates: rates, at: end, now: now,
                                                   stockValue: nil, index: loans)
                if r.basis == 3 {
                    // 口徑 3（房貸、車貸已是本金）：照存的，加回那個月底的存款、卡費、待交割
                    // [v25.565 裁定] 存款含賣股票還沒入帳（redo.value(.cash)）
                    out.append(FinanceMonthPoint(month: start, assets: r.assets + redo.value(.cash),
                                                 debt: r.debt + redo.cardOwed + redo.pendingSettlement, recorded: true))
                } else {
                    // 口徑 2 以前：資產照存的再加存款；負債整個用現在這套（含卡費、待交割）
                    out.append(FinanceMonthPoint(month: start, assets: r.assets + redo.value(.cash), debt: redo.debt,
                                                 recorded: true))
                }
                continue
            }
            // 股票：那個月底前 45 天內有每週市值紀錄就用，沒有就用持股成本
            let stockValue = weekly.last { $0.weekStart <= end && $0.weekStart > end.addingTimeInterval(-45 * 86_400) }?.value
            let s = FinanceSnapshot.compute(finance: f, expense: e, rates: rates, at: end, now: now,
                                            stockValue: stockValue, index: loans)
            out.append(FinanceMonthPoint(month: start, assets: s.assets, debt: s.debt, recorded: false))
        }
        return out
    }
}
