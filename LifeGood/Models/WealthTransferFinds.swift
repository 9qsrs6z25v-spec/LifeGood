import Foundation

// MARK: - [v25.581] 定期轉帳 v3 以前湊的找出來（transfer/judge.md §2.5、§3.6「差額剛好是一期」、§3.8、§4.1、§4.6、§4.8 v3、§5、§6、
// 第 8、9 題；transfer/build/v3/brief.md §2；sim_v3.py 照這裡一行一行寫過、跑過）
//
// v1a（WealthTransfers.swift）定下來的資料**一個欄位都不加**、**沒有新的同步鍵**（v1a 已知限制 3：25.575～25.580 的手機讀到不認得的欄位，
// 存回去會丟掉）。這一版要記的全部用以前就有的：
// • 〔不是〕〔知道了〕＝財富帳本 dismissed（WealthBook.dismiss；25.563 起每一版都認得、跟 iCloud 同步）。key 不帶日子＝記住、不再問。
// • 〔改成定期轉帳〕〔合成一條定期轉帳〕〔設成每月都轉〕〔設成每月〕＝打開新增表單（WealthTransferPreset 帶好從、到、金額、每月幾日；要訂閱）；
//   存檔時記帳那筆照 v1a「是同一筆嗎？」三個選項（endRecurring／excludedExpenses／收入 endDate）——你不按就不動，以前的月份不改。
// • 〔是同一筆…〕＝同一套三個選項（規則已經存了，只問記帳那筆）；不擋訂閱（同〔已經退訂〕〔這筆不算〕）。
// • 〔那期沒轉成〕＝那一期 status "failed"（v1a 就認得）。
// • 〔把差的記成「零用錢」支出〕＝記帳一筆變動支出＋那個帳戶一筆扣款（BankDeposit linkedExpenseId，同 AI 記帳那條路），日子＝對存摺那天：
//   同一天對存摺排最後（那天結束時的數字），存摺不會再扣一次（LifeStore.savePocketAnchor）。
// 這個檔只放算法與字（純函式；WealthFacts.makeChecks、畫面、LifeStore 叫），不碰存檔。
//
// • 要確認 v3 四種（WealthTransferFinds.checks；**一列都 ≤ 2 顆**）：
//   ① transferItemDup（warn）：記帳的每月固定支出（從 A 扣）或每月收入（入 B）跟一條還在跑的每月定期轉帳對得上（同 v1a 存規則時問的條件：
//      從／到、同金額、每月幾號差 3 天內）——存規則時關掉沒答的、25.580 以前答過的：「…像同一筆：薪轉每個月會扣兩次」〔是同一筆…〕〔不是〕。
//      v25.581 起存規則時按〔不是，兩筆都要〕會記住（WealthTransferFinds.notSameKeys），不會再問。
//   ② transferPair（warn）：同一天、同金額的每月固定支出（從 A 扣）＋每月收入（入 B）一對、沒有定期轉帳對得上〔合成一條定期轉帳〕〔不是〕。
//   ③ transferSuspect（warn）：記帳裡像轉到自己帳戶的每月固定支出（標題有自己另一個帳戶的暱稱或銀行名＋「轉」或「存」、扣款帳戶是你的銀行、
//      類別不是房租、台幣、還在扣、不在 ①② 裡）〔改成定期轉帳〕〔不是〕。
//   ④ transferRepeat（info）：同兩個帳戶、同金額、每月差不多同一天（差 3 天內）的單次轉帳連 3 個月（最近一筆 45 天內、沒有同從同到同金額
//      還在跑的定期轉帳）〔設成每月都轉〕〔知道了〕。[裁定修] 那三個月有一個月記了 3 筆以上（多半是每週手記的）不問。
// • 對存摺：差額剛好是對存摺那天前 1～7 天某一期的這一邊（±1 元）→ 存檔前問〔那期沒轉成〕〔不是，照存摺就好〕（WealthFacts.transferMiss）；
//   零用錢帳戶（用途「零用」、名字有「零用」、或每週有一條定期轉帳轉進來；WealthFacts.isPocketAccount）存摺比 App 算的少
//   →〔把差的記成「零用錢」支出〕。

// MARK: - 常數、id、字

enum WealthTransferFinds {
    /// 連 3 個月手記的單次轉帳：最近那一筆要在今天往前幾天內
    static let repeatRecentDays = 45
    /// 往前看幾天的單次轉帳（3 個月＋一點）
    static let repeatLookbackDays = 120
    /// [裁定修] 連 3 個月那三個月裡，同一組（同從、同到、同金額）有一個月記了幾筆以上＝不是每月一次（多半是每週手記的，
    /// 例 v1a 以前每週五轉零用錢 3,000）：不問（每週一定每個月都有一筆差 3 天內，會被當成「每月」帶錯）
    static let repeatMonthMax = 3
    /// 對存摺差額剛好是一期：對存摺那天往前幾天內的期（不含那天：那天的在表單「這天還有」問過）
    static let missDays = 7
    /// 差額跟那一期差多少以內算「剛好」（±1 元）
    static let missTolerance: Double = 1
    /// 記帳那一筆還要有下一期：往後看幾天
    static let nextLookDays = 62
    /// 〔把差的記成「零用錢」支出〕記帳那筆的標題、備註
    static let pocketTitle = "零用錢"
    static let pocketNote = "對存摺時補記"

    /// 要確認的 id（也是〔不是〕〔知道了〕記在帳本 dismissed 的 key；不帶日子＝答了就不再問）
    static func suspectId(_ expenseId: UUID) -> String { "trsus-" + expenseId.uuidString }
    static func pairId(expenseId: UUID, incomeId: UUID) -> String {
        "trpair-" + expenseId.uuidString + "-" + incomeId.uuidString
    }
    static func dupExpenseId(ruleId: UUID, expenseId: UUID) -> String {
        "trdupx-" + ruleId.uuidString + "-" + expenseId.uuidString
    }
    static func dupIncomeId(ruleId: UUID, incomeId: UUID) -> String {
        "trdupi-" + ruleId.uuidString + "-" + incomeId.uuidString
    }
    static func repeatId(fromId: UUID, toId: UUID, amount: Double) -> String {
        "trrep-" + fromId.uuidString + "-" + toId.uuidString + "-" + String(Int(amount.rounded()))
    }

    /// 存規則時「是同一筆嗎？」按了〔不是，兩筆都要〕〔不是〕（不是關掉）：要確認不再問的那幾個 key——
    /// 那條規則 × 那一筆（①）、那一筆像轉到自己帳戶（③：你在表單改了金額、日子，它對不上規則了也不再問）、
    /// 要確認 ② 帶來的那一對（preset 兩筆都有時）
    static func notSameKeys(ruleId: UUID, match m: WealthTransferMatch, preset: WealthTransferPreset?) -> [String] {
        var out: [String] = []
        switch m.kind {
        case .expense:
            out.append(dupExpenseId(ruleId: ruleId, expenseId: m.itemId))
            out.append(suspectId(m.itemId))
        case .income:
            out.append(dupIncomeId(ruleId: ruleId, incomeId: m.itemId))
        }
        if let p = preset, let e = p.matchExpenseId, let i = p.matchIncomeId, m.itemId == e || m.itemId == i {
            out.append(pairId(expenseId: e, incomeId: i))
        }
        return out
    }

    /// 句子裡的金額「20,000」（台幣到元）
    static func amountText(_ v: Double) -> String {
        WealthFormat.grouped(v.rounded(), decimals: 0)
    }

    /// 每月幾號（西曆、手機時區）
    static func dayOfMonth(_ d: Date) -> Int {
        WealthCal.calendar.component(.day, from: d)
    }

    /// 那天是那個月的最後一天
    static func isMonthEnd(_ d: Date) -> Bool {
        dayOfMonth(WealthCal.addDays(1, to: WealthCal.day(d))) == 1
    }

    /// 每月幾號差多少（月底、月初跨月也算：31 號 vs 1 號差 1 天；同 WealthTransferMatcher.closeDays）
    static func dayGap(_ a: Int, _ b: Int) -> Int {
        let d = Swift.abs(a - b)
        return Swift.min(d, 31 - d)
    }

    /// 規則每月幾號（day；沒有＝第一期那天）
    static func ruleDay(_ r: WealthTransferRule) -> Int {
        if let d = r.day { return d }
        guard let sk = r.startKey, let s = WealthTransferSchedule.date(fromKey: sk) else { return 1 }
        return dayOfMonth(s)
    }

    /// 名字比對用：去空白、臺→台
    static func normalized(_ s: String) -> String {
        var out = ""
        for ch in s where !ch.isWhitespace {
            out.append(ch == "臺" ? "台" : ch)
        }
        return out
    }

    /// 一個帳戶在標題裡認得出來的名字（2 個字以上）：暱稱（name）、銀行名、銀行名去掉「商業銀行」「銀行」
    static func nameKeys(_ a: WealthFacts.Account) -> [String] {
        var keys: [String] = []
        func add(_ raw: String) {
            let k = normalized(raw)
            guard k.count >= 2, !keys.contains(k) else { return }
            keys.append(k)
        }
        add(a.name)
        add(a.bankName)
        let b = normalized(a.bankName)
        if b.hasSuffix("商業銀行") {
            add(String(b.dropLast(4)))
        } else if b.hasSuffix("銀行") {
            add(String(b.dropLast(2)))
        }
        return keys
    }

    /// 標題認得出來的「自己另一個帳戶」：標題有「轉」或「存」、有那個帳戶的名字（好幾個都有＝名字最長的那個；一樣長取前面的）；
    /// 扣款的那個帳戶自己不算。沒有＝nil（「轉玉山存錢」→ 存錢（玉山）；「給家裡」→ nil）
    static func titleTarget(_ title: String, payer: UUID, banks: [WealthFacts.Account]) -> WealthFacts.Account? {
        let t = normalized(title)
        guard t.contains("轉") || t.contains("存") else { return nil }
        var best: WealthFacts.Account? = nil
        var bestLength = 0
        for a in banks where a.id != payer {
            for k in nameKeys(a) where t.contains(k) && k.count > bestLength {
                best = a
                bestLength = k.count
            }
        }
        return best
    }

    // MARK: 記帳那一筆

    /// 固定支出今天以後（不含今天）的下一期那天 00:00（62 天內；沒有＝已經結束或很久以後才開始）
    static func nextExpensePeriod(_ e: Expense, today: Date) -> Date? {
        let t = WealthCal.day(today)
        let list = WealthSchedule.fixedPeriods(e, through: WealthCal.addDays(nextLookDays, to: t))
        return list.map { WealthCal.day($0.date) }.first { $0 > t }
    }

    /// 收入今天以後（不含今天）的下一期那天 00:00（62 天內）
    static func nextIncomePeriod(_ inc: Income, today: Date) -> Date? {
        let t = WealthCal.day(today)
        let list = WealthSchedule.incomePeriods(inc, through: WealthCal.addDays(nextLookDays, to: t))
        return list.map { WealthCal.day($0.date) }.first { $0 > t }
    }

    /// 可以當成「定期轉帳湊的」的每月固定支出：扣你的銀行（不是刷卡）、台幣、不是房租、沒標「這筆不算」、還有下一期 → 扣款帳戶
    static func expensePayer(_ e: Expense, bankIds: Set<UUID>, excluded: Set<String>, today: Date) -> UUID? {
        guard e.expenseType == .fixed, e.recurrence == .monthly, e.linkedCreditCardMilestoneId == nil,
              let payer = e.linkedBankMilestoneId, bankIds.contains(payer), e.originalCurrencyAmount == nil,
              e.fixedCategory != .rent, !excluded.contains(e.id.uuidString), e.amount >= 0.5 else { return nil }
        // [驗證修] 從外幣那一格扣的（扣款帳戶選「玉山・美金」：一套數字從那一格扣）不看——v1 規則只有台幣，帶好的會變成從台幣那格轉
        //（同 incomeTarget 看 linkedBankCurrency）
        if let c = e.linkedBankCurrency, !FinanceRates.isNTD(c) { return nil }
        guard nextExpensePeriod(e, today: today) != nil else { return nil }
        return payer
    }

    /// 可以當成「定期轉帳湊的」的每月收入：入你的銀行、台幣、不是股票的、還有下一期 → 入帳帳戶
    static func incomeTarget(_ inc: Income, bankIds: Set<UUID>, today: Date) -> UUID? {
        guard inc.period == .monthly, inc.linkedStockId == nil, let into = inc.linkedBankMilestoneId,
              bankIds.contains(into), inc.amount >= 0.5 else { return nil }
        if let c = inc.linkedBankCurrency, !FinanceRates.isNTD(c) { return nil }
        guard nextIncomePeriod(inc, today: today) != nil else { return nil }
        return into
    }

    /// 一條還在跑的每月定期轉帳跟這筆對得上（同 v1a 存規則時問的條件：從（或到）同一個帳戶、同金額、每月幾號差 3 天內）；沒有＝nil
    static func coveringRule(from payer: UUID?, to into: UUID?, amount: Double, day: Int,
                             transfers: [WealthFacts.TransferRule]) -> WealthFacts.TransferRule? {
        for t in transfers where !t.isEnded && t.rule.cycleKind == .monthly {
            if let p = payer, t.fromId != p { continue }
            if let i = into, t.toId != i { continue }
            guard Swift.abs(t.amount - amount) < 0.5,
                  dayGap(ruleDay(t.rule), day) <= WealthTransferMatcher.dayWindow else { continue }
            return t
        }
        return nil
    }

    // MARK: 帶好欄位

    /// 每月一條的帶好欄位（從、到、金額到元、每月幾日；day 31＝每月最後一天）。lead：表單最上面一行；expenseId／incomeId：存檔時一定問的那一筆
    static func preset(fromId: UUID, toId: UUID, amount: Double, day: Int, lead: String?,
                       expenseId: UUID? = nil, incomeId: UUID? = nil) -> WealthTransferPreset {
        WealthTransferPreset(fromId: fromId, toId: toId, amount: amount.rounded(), cycle: .monthly,
                             day: Swift.min(Swift.max(day, 1), 31), short: nil, offer: nil,
                             matchExpenseId: expenseId, matchIncomeId: incomeId, lead: lead)
    }

    /// 那天轉的每月幾號：月底而且是 30、31 號＝31（每月最後一天）；其他照那天（2/28 照 28 號）
    static func monthlyDay(of d: Date) -> Int {
        let n = dayOfMonth(d)
        return (n >= 30 && isMonthEnd(d)) ? 31 : n
    }

    /// [v25.581] 明細一筆單次轉帳長按〔設成每月〕：帶好從（轉出那邊）、到、金額、每月幾日（那天）。
    /// 只做台幣、兩個不同的帳戶（換匯、外幣的 v4）；不是單次轉帳＝nil。accountId：這一筆記在哪個帳戶
    static func monthlyPreset(for dep: BankDeposit, in accountId: UUID) -> WealthTransferPreset? {
        guard dep.isTransfer, !dep.isAnchor, let other = dep.counterpartyId, other != accountId,
              FinanceRates.isNTD(dep.currencyCode), dep.fxRate == nil, dep.amount >= 0.5 else { return nil }
        let from: UUID = dep.isWithdrawal ? accountId : other
        let to: UUID = dep.isWithdrawal ? other : accountId
        let lead = "照 " + WealthFormat.monthDay(dep.date) + " 這筆帶好了；這筆照留，從下一期起算"
        return preset(fromId: from, toId: to, amount: dep.amount, day: monthlyDay(of: dep.date), lead: lead)
    }

    /// [v25.581] 單次轉帳表單最下面「每個月都會轉？」〔改成定期轉帳〕：帶好從、到、金額、每月幾日（表單上的日子）；台幣、兩個不同的帳戶
    static func monthlyPreset(fromId: UUID, toId: UUID, amount: Double, on date: Date) -> WealthTransferPreset? {
        guard fromId != toId, amount >= 0.5 else { return nil }
        let n = monthlyDay(of: date)
        let when: String = n >= 31 ? "每月最後一天" : "每月 \(n) 日"
        return preset(fromId: fromId, toId: toId, amount: amount, day: n, lead: "照這筆轉帳帶好了：" + when)
    }

    // MARK: 連 3 個月

    /// 連 3 個月：最近一筆 L（今天往前 45 天內）、L 的前一個月與前兩個月各有一筆每月幾號跟 L 差 3 天內（那個月取最接近的）。
    /// 回三筆（舊到新）與每月幾日（三筆都是月底＝31，不然＝L 那天）；沒有＝nil。
    /// [裁定修] 那三個月裡有一個月這一組記了 3 筆以上（repeatMonthMax；多半是每週手記的）＝nil
    static func repeatDays(_ list: [Date], today: Date) -> (days: [Date], day: Int)? {
        let t = WealthCal.day(today)
        let sorted: [Date] = list.map { WealthCal.day($0) }.sorted()
        guard let last = sorted.last, last <= t, WealthCal.days(from: last, to: t) <= repeatRecentDays else { return nil }
        let lastDay = dayOfMonth(last)
        let lastMonth = WealthCal.startOfMonth(last)
        let lastCount: Int = sorted.filter({ WealthCal.startOfMonth($0) == lastMonth }).count
        guard lastCount < repeatMonthMax else { return nil }
        var picked: [Date] = [last]
        for back in 1...2 {
            let month = WealthCal.startOfMonth(WealthCal.addMonths(-back, to: lastMonth))
            var best: Date? = nil
            var bestGap = Int.max
            var inMonth = 0
            for d in sorted where WealthCal.startOfMonth(d) == month {
                inMonth += 1
                let g = dayGap(dayOfMonth(d), lastDay)
                guard g <= WealthTransferMatcher.dayWindow, g < bestGap else { continue }
                best = d
                bestGap = g
            }
            guard inMonth < repeatMonthMax, let b = best else { return nil }
            picked.insert(b, at: 0)
        }
        let allEnd = picked.allSatisfy { isMonthEnd($0) }
        return (days: picked, day: allEnd ? 31 : lastDay)
    }

    // MARK: 要確認 v3 四種

    /// WealthFacts.makeChecks 叫（按過〔不是〕〔知道了〕的那邊照帳本 dismissed 濾）。banks：沒收起來的銀行帳戶（不含證券戶）；
    /// bankMs：銀行的里程碑（單次轉帳在它們的 bankDeposits）；excluded：帳本「這筆不算」的記帳
    static func checks(transfers: [WealthFacts.TransferRule], banks: [WealthFacts.Account], bankMs: [LifeMilestone],
                       expenses: [Expense], incomes: [Income], excluded: Set<String>, today: Date) -> [WealthCheck] {
        let t = WealthCal.day(today)
        let bankIds: Set<UUID> = Set(banks.map { $0.id })
        var names: [UUID: String] = [:]
        for a in banks where names[a.id] == nil { names[a.id] = a.name }
        func name(_ id: UUID?) -> String { id.flatMap { names[$0] } ?? "別的帳戶" }
        var out: [WealthCheck] = []

        // 每月固定支出、每月收入（扣／入你的銀行、台幣、還有下一期）
        var exps: [(e: Expense, payer: UUID, day: Int)] = []
        for e in expenses {
            guard let payer = expensePayer(e, bankIds: bankIds, excluded: excluded, today: t) else { continue }
            exps.append((e: e, payer: payer, day: dayOfMonth(e.date)))
        }
        var incs: [(i: Income, into: UUID, day: Int)] = []
        for inc in incomes {
            guard let into = incomeTarget(inc, bankIds: bankIds, today: t) else { continue }
            incs.append((i: inc, into: into, day: dayOfMonth(inc.date)))
        }

        // ① 跟一條還在跑的定期轉帳像同一筆
        var covered = Set<UUID>()
        for x in exps {
            guard let r = coveringRule(from: x.payer, to: nil, amount: x.e.amount, day: x.day, transfers: transfers) else { continue }
            covered.insert(x.e.id)
            let text = "記帳的『\(x.e.title)』每月 \(x.day) 日 \(amountText(x.e.amount)) 從 \(name(x.payer)) 扣，"
                + "跟定期轉帳『\(r.title)』像同一筆：\(name(x.payer))每個月會扣兩次"
            let ids: [UUID] = [x.payer, r.toId].compactMap { $0 }.filter { bankIds.contains($0) }
            out.append(WealthCheck(
                id: dupExpenseId(ruleId: r.id, expenseId: x.e.id), kind: .transferItemDup, tone: .warn, text: text,
                actions: [WealthCheck.Action(title: "是同一筆…", fix: .askTransferItem(ruleId: r.id, itemId: x.e.id, isIncome: false)),
                          WealthCheck.Action(title: "不是", fix: .dismiss)],
                accountIds: ids))
        }
        for y in incs {
            guard let r = coveringRule(from: nil, to: y.into, amount: y.i.amount, day: y.day, transfers: transfers) else { continue }
            covered.insert(y.i.id)
            let text = "記帳的收入『\(y.i.title)』每月 \(y.day) 日 \(amountText(y.i.amount)) 入 \(name(y.into))，"
                + "跟定期轉帳『\(r.title)』像同一筆：\(name(y.into))每個月會進兩次"
            let ids: [UUID] = [r.fromId, y.into].compactMap { $0 }.filter { bankIds.contains($0) }
            out.append(WealthCheck(
                id: dupIncomeId(ruleId: r.id, incomeId: y.i.id), kind: .transferItemDup, tone: .warn, text: text,
                actions: [WealthCheck.Action(title: "是同一筆…", fix: .askTransferItem(ruleId: r.id, itemId: y.i.id, isIncome: true)),
                          WealthCheck.Action(title: "不是", fix: .dismiss)],
                accountIds: ids))
        }

        // ② 同一天、同金額的固定支出（從 A 扣）＋收入（入 B）一對
        var paired = Set<UUID>()
        for x in exps where !covered.contains(x.e.id) {
            guard let y = incs.first(where: { y in
                !covered.contains(y.i.id) && !paired.contains(y.i.id) && y.into != x.payer && y.day == x.day
                    && Swift.abs(y.i.amount - x.e.amount) < 0.5
            }) else { continue }
            paired.insert(x.e.id)
            paired.insert(y.i.id)
            let text = "記帳的『\(x.e.title)』（支出）和『\(y.i.title)』（收入）同一天、同金額，是同一筆轉帳嗎？"
            let lead = "照記帳的『\(x.e.title)』和『\(y.i.title)』帶好了；存檔時會一筆一筆問記帳那兩筆怎麼辦"
            let p = preset(fromId: x.payer, toId: y.into, amount: x.e.amount, day: x.day, lead: lead,
                           expenseId: x.e.id, incomeId: y.i.id)
            out.append(WealthCheck(
                id: pairId(expenseId: x.e.id, incomeId: y.i.id), kind: .transferPair, tone: .warn, text: text,
                actions: [WealthCheck.Action(title: "合成一條定期轉帳", fix: .newTransferRule(p)),
                          WealthCheck.Action(title: "不是", fix: .dismiss)],
                accountIds: [x.payer, y.into]))
        }

        // ③ 像轉到自己帳戶的固定支出
        for x in exps where !covered.contains(x.e.id) && !paired.contains(x.e.id) {
            guard let target = titleTarget(x.e.title, payer: x.payer, banks: banks) else { continue }
            let money = amountText(x.e.amount)
            let text = "記帳的『\(x.e.title)』每月 \(x.day) 日 \(money) 從 \(name(x.payer)) 扣，看起來是轉到你自己的 \(target.name)。"
                + "記成支出會讓記帳每月多算 \(money) 的花費、\(target.name)那邊收不到。"
            let lead = "照記帳的『\(x.e.title)』帶好了；存檔時會問記帳那筆怎麼辦"
            let p = preset(fromId: x.payer, toId: target.id, amount: x.e.amount, day: x.day, lead: lead, expenseId: x.e.id)
            out.append(WealthCheck(
                id: suspectId(x.e.id), kind: .transferSuspect, tone: .warn, text: text,
                actions: [WealthCheck.Action(title: "改成定期轉帳", fix: .newTransferRule(p)),
                          WealthCheck.Action(title: "不是", fix: .dismiss)],
                accountIds: [x.payer, target.id]))
        }

        // ④ 連 3 個月手記的單次轉帳（從那邊的那一筆；照 從、到、金額 分好）
        let earliest = WealthCal.addDays(-repeatLookbackDays, to: t)
        var groups: [WealthTransferRepeatKey: [Date]] = [:]
        var order: [WealthTransferRepeatKey] = []
        for m in bankMs where bankIds.contains(m.id) {
            for dep in m.bankDeposits ?? [] {
                guard dep.isTransfer, dep.isWithdrawal, !dep.isAnchor, let to = dep.counterpartyId, to != m.id,
                      bankIds.contains(to), FinanceRates.isNTD(dep.currencyCode), dep.fxRate == nil,
                      dep.amount >= 0.5 else { continue }
                let d = WealthCal.day(dep.date)
                guard d <= t, d >= earliest else { continue }
                let k = WealthTransferRepeatKey(fromId: m.id, toId: to, cents: Int((dep.amount * 100).rounded()))
                if groups[k] == nil { order.append(k) }
                groups[k, default: []].append(d)
            }
        }
        for k in order {
            guard let list = groups[k], let hit = repeatDays(list, today: t) else { continue }
            let amount = Double(k.cents) / 100
            let ruled = transfers.contains { r in
                !r.isEnded && r.fromId == k.fromId && r.toId == k.toId && Swift.abs(r.amount - amount) < 0.5
            }
            guard !ruled else { continue }
            let days = hit.days.map { WealthTransferText.dayText($0, today: t) }.joined(separator: "、")
            let text = "\(days) 都從 \(name(k.fromId)) 轉 \(amountText(amount)) 到 \(name(k.toId))，每個月都會轉嗎？"
            let lead = "照 \(days) 手記的帶好了；以前手記的照留，從下一期起算"
            let p = preset(fromId: k.fromId, toId: k.toId, amount: amount, day: hit.day, lead: lead)
            out.append(WealthCheck(
                id: repeatId(fromId: k.fromId, toId: k.toId, amount: amount), kind: .transferRepeat, tone: .info, text: text,
                actions: [WealthCheck.Action(title: "設成每月都轉", fix: .newTransferRule(p)),
                          WealthCheck.Action(title: "知道了", fix: .dismiss)],
                accountIds: [k.fromId, k.toId]))
        }
        return out
    }
}

/// 連 3 個月那一種的分組（從、到、金額到分）
private struct WealthTransferRepeatKey: Hashable {
    let fromId: UUID
    let toId: UUID
    let cents: Int
}

// MARK: - 存規則時一定問的那一筆（要確認 v3 帶來的；judge §4.8「v3〔改成定期轉帳〕存好後再問記帳那筆」）

extension WealthTransferMatcher {
    /// [v25.581] 那一筆固定支出：不看金額、日子、扣款帳戶（你在表單改過也照問）；結束日照 matches 同一招（跟這條第一期對上的那一期的前一天：
    /// 那一期起不扣，以前的月份照舊）。那筆在這條第一期 3 天前就已經結束了＝nil（不用問）
    static func forcedExpense(rule r: WealthTransferRule, expense e: Expense, payerName: String) -> WealthTransferMatch? {
        guard let sk = r.startKey, let first = WealthTransferSchedule.date(fromKey: sk) else { return nil }
        let early = WealthCal.addDays(-dayWindow, to: first)
        if let end = e.endDate, WealthCal.day(end) < early { return nil }
        let until = WealthCal.addDays(WealthTransferFinds.nextLookDays, to: first)
        guard let hit = WealthSchedule.fixedPeriods(e, through: until).first(where: { WealthCal.day($0.date) >= early }) else {
            return nil
        }
        let endDay = WealthCal.addDays(-1, to: WealthCal.day(hit.date))
        let eDay = WealthTransferFinds.dayOfMonth(e.date)
        let q = "記帳裡的『\(e.title)』每月 \(eDay) 日 \(WealthTransferFinds.amountText(e.amount)) 從 \(payerName) 扣，跟這條是同一筆嗎？"
        return WealthTransferMatch(kind: .expense, itemId: e.id, question: q, endDay: endDay)
    }

    /// [v25.581] 那一筆收入：不看金額、日子、入帳帳戶；結束在跟這條第一期對上的那一期的前一個月月底（Income.endDate 照月份算、結束那個月含）。
    /// 那筆在這條第一期那個月以前就結束了＝nil
    static func forcedIncome(rule r: WealthTransferRule, income inc: Income, intoName: String) -> WealthTransferMatch? {
        guard let sk = r.startKey, let first = WealthTransferSchedule.date(fromKey: sk) else { return nil }
        guard inc.isActive(in: first, calendar: WealthCal.calendar) else { return nil }
        let early = WealthCal.addDays(-dayWindow, to: first)
        let until = WealthCal.addDays(WealthTransferFinds.nextLookDays, to: first)
        guard let hit = WealthSchedule.incomePeriods(inc, through: until).first(where: { WealthCal.day($0.date) >= early }) else {
            return nil
        }
        let endDay = WealthCal.addDays(-1, to: WealthCal.startOfMonth(hit.date))
        let iDay = WealthTransferFinds.dayOfMonth(inc.date)
        let q = "記帳裡的收入『\(inc.title)』每月 \(iDay) 日 \(WealthTransferFinds.amountText(inc.amount)) 入 \(intoName)，是同一筆嗎？"
        return WealthTransferMatch(kind: .income, itemId: inc.id, question: q, endDay: endDay)
    }
}

// MARK: - 〔是同一筆…〕之後的確認框（要確認 ①）

/// 規則已經存了，只問記帳那筆：固定支出〔是：記帳那筆從下一期起結束〕〔是，但記帳照記（還能花先扣掉）〕；收入〔是：那筆收入從下個月起結束〕
struct WealthTransferItemAsk: Identifiable, Equatable {
    let ruleId: UUID
    let itemId: UUID
    let isIncome: Bool
    /// 「『轉玉山存錢』從 11/6 那期起不再從 薪轉 扣？」／「收入『玉山存錢』從 11 月起不再入 存錢？」
    let title: String
    let message: String
    /// 〔是：從下一期起結束〕結束在哪天：固定支出＝下一期的前一天（11/6 那期起不扣 → 11/5）；收入＝下一期那個月的前一天（10/31：10 月含）
    let endDay: Date

    var id: String { (isIncome ? "i-" : "e-") + ruleId.uuidString + "-" + itemId.uuidString }
}

extension WealthFacts {
    /// [v25.581] 要確認 ①〔是同一筆…〕：那一筆（固定支出或收入）怎麼結束、確認框的字。找不到、已經沒有下一期＝nil
    func transferItemAsk(ruleId: UUID, itemId: UUID, isIncome: Bool, expenses: [Expense],
                         incomes: [Income]) -> WealthTransferItemAsk? {
        let ruleTitle: String = transferRule(ruleId)?.title ?? "定期轉帳"
        if isIncome {
            guard let inc = incomes.first(where: { $0.id == itemId }),
                  let next = WealthTransferFinds.nextIncomePeriod(inc, today: today) else { return nil }
            let into: String = account(inc.linkedBankMilestoneId)?.name ?? "那個帳戶"
            let title = "收入『\(inc.title)』從 \(WealthCal.month(next)) 月起不再入 \(into)？"
            let message = "定期轉帳『\(ruleTitle)』已經算了這筆錢；以前的月份照舊。"
            return WealthTransferItemAsk(ruleId: ruleId, itemId: itemId, isIncome: true, title: title, message: message,
                                         endDay: WealthCal.addDays(-1, to: WealthCal.startOfMonth(next)))
        }
        guard let e = expenses.first(where: { $0.id == itemId }),
              let next = WealthTransferFinds.nextExpensePeriod(e, today: today) else { return nil }
        let payer: String = account(e.linkedBankMilestoneId)?.name ?? "那個帳戶"
        let money = WealthTransferFinds.amountText(e.amount)
        let title = "『\(e.title)』從 \(WealthTransferText.dayText(next, today: today)) 那期起不再從 \(payer) 扣？"
        let message = "定期轉帳『\(ruleTitle)』照轉，以前的月份照舊算花費。本月還能花每月會多 \(money)——那是你存起來的錢，"
            + "不是多出來能花的；想先存再花，選〔是，但記帳照記〕。"
        return WealthTransferItemAsk(ruleId: ruleId, itemId: itemId, isIncome: false, title: title, message: message,
                                     endDay: WealthCal.addDays(-1, to: next))
    }
}

// MARK: - 對存摺：差額剛好是一期、零用錢帳戶（judge §3.6、§3.8、第 8 題；樣稿③-C4）

/// 對存摺差額剛好是 7 天內某一期的這一邊
struct WealthTransferMiss: Identifiable, Equatable {
    let ruleId: UUID
    /// 那一期原本的日子（註記的 key）
    let key: String
    /// true＝這個帳戶是轉出那邊（存摺比 App 多）；false＝轉入那邊（存摺比 App 少）
    let out: Bool
    let amount: Double
    /// 那一期實際那天
    let day: Date
    /// 「差的 20,000 剛好是 11/6『薪轉 → 存錢』那一期」
    let title: String
    /// 「存錢 11/9：App 算的 206,000、存摺上 186,000、差 −20,000。選〔那期沒轉成〕：那期兩邊都不算，薪轉多 20,000（薪轉那邊下次對存摺時也會對上）。」
    let message: String
    /// 選〔那期沒轉成〕之後這次對存摺的差額（存摺上 − App 算的；±1 元內）
    let diffAfter: Double

    var id: String { ruleId.uuidString + "-" + key + (out ? "-o" : "-i") }
}

extension WealthFacts {
    /// [v25.581] 新的一筆對存摺（day 那天、code 那一格；app＝表單「App 算的」跟存摺比的那個數、target＝存摺上）：差額（target − app）剛好是
    /// 這個帳戶 day 前 1～7 天某一期定期轉帳的這一邊（±1 元；轉入那邊差的是負的、轉出那邊差的是正的）＝那一期。那一期要在這個帳戶這一格
    /// 上一次對存摺之後（那天以前的被它蓋掉了；同一天排在它後面的照算）。好幾期都對得上取最近的（一樣近取建立在前的規則）。
    /// v1 規則只有台幣：不是台幣、差不到 1 元＝nil
    func transferMiss(accountId: UUID, code: String, on day: Date, app: Double, target: Double) -> WealthTransferMiss? {
        let d = WealthCal.day(day)
        let c = WealthFacts.norm(code)
        let diff = ((target - app) * 100).rounded() / 100
        guard c == "NT$", Swift.abs(diff) >= 1, let a = account(accountId) else { return nil }
        let prev: Date? = a.ledger
            .filter { $0.kind == .anchor && WealthFacts.norm($0.code) == c && WealthCal.day($0.date) <= d }
            .map { WealthCal.day($0.date) }
            .max()
        let earliest = WealthCal.addDays(-WealthTransferFinds.missDays, to: d)
        var best: (p: WealthTransferPeriod, out: Bool, amount: Double, expected: Double, rule: WealthTransferRule)? = nil
        for r in transferBook.live {
            for p in WealthTransferSchedule.periods(r, through: d, today: today) where p.counts {
                let pd = WealthCal.day(p.day)
                guard pd < d, pd >= earliest else { continue }
                for side in [true, false] {
                    let mine: Bool = side ? (p.fromId == accountId && p.fromCode == c) : (p.toId == accountId && p.toCode == c)
                    guard mine else { continue }
                    let late: Bool = side ? p.lateOut : p.lateIn
                    if let x = prev, pd < x || (pd == x && !late) { continue }
                    let amt: Double = side ? p.amount : p.toAmount
                    let expected: Double = side ? amt : -amt
                    guard Swift.abs(diff - expected) <= WealthTransferFinds.missTolerance else { continue }
                    if let b = best, WealthCal.day(b.p.day) >= pd { continue }
                    best = (p: p, out: side, amount: amt, expected: expected, rule: r)
                }
            }
        }
        guard let b = best else { return nil }
        let ruleTitle: String = transferRule(b.rule.id)?.title ?? "定期轉帳"
        let otherId: UUID? = b.out ? b.p.toId : b.p.fromId
        let other: String = account(otherId)?.name ?? "另一個帳戶"
        let money: String = WealthFormat.plain(b.amount, code: c)
        let when: String = WealthTransferText.dayText(b.p.day, today: today)
        let title = "差的 \(money) 剛好是 \(when)『\(ruleTitle)』那一期"
        let appText: String = WealthFormat.plain(app, code: c)
        let targetText: String = WealthFormat.plain(target, code: c)
        let diffText: String = WealthTransferText.signed(diff)
        let change: String = b.out ? "少" : "多"
        let head = "\(a.name) \(WealthFormat.monthDay(d))：App 算的 \(appText)、存摺上 \(targetText)、差 \(diffText)。"
        let message = head + "選〔那期沒轉成〕：那期兩邊都不算，\(other)\(change) \(money)（\(other)那邊下次對存摺時也會對上）。"
        let after = ((diff - b.expected) * 100).rounded() / 100
        return WealthTransferMiss(ruleId: b.rule.id, key: b.p.key, out: b.out, amount: b.amount, day: b.p.day,
                                  title: title, message: message, diffAfter: after)
    }

    /// [v25.581] 零用錢帳戶（judge §3.8、第 8 題：轉過去不算花掉，對存摺差的一鍵記成支出）：用途寫「零用」、名字有「零用」、
    /// 或每週有一條還在跑的定期轉帳轉進來。證券戶、定存帳戶不算
    func isPocketAccount(_ id: UUID) -> Bool {
        guard let a = account(id), !a.isSecurities, !a.isFixedDeposit else { return false }
        if (a.purpose ?? "").contains("零用") || a.name.contains("零用") { return true }
        return runningTransfers.contains { $0.toId == id && $0.rule.cycleKind == .weekly }
    }
}

extension WealthTransferFinds {
    /// 對存摺〔把差的記成「零用錢」支出〕那顆的字：「把差的 11,500 記成「零用錢」支出」
    static func pocketButton(_ spend: Double) -> String {
        "把差的 " + amountText(spend) + " 記成「" + pocketTitle + "」支出"
    }

    /// 那顆下面的小字：「記帳多一筆變動支出「零用錢」（類別其他、從 零用錢 扣）；存摺照這次的數字往後算，不會再扣一次。」
    static func pocketFooter(accountName: String) -> String {
        "記帳多一筆變動支出「" + pocketTitle + "」（類別其他、從 " + accountName + " 扣），本月還能花跟著扣；"
            + "存摺照這次的數字往後算，不會再扣一次。"
    }
}
