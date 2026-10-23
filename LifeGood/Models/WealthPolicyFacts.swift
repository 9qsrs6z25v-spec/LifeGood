import Foundation

// MARK: - [v25.567] 保單總表（財富 v6；wealth/judge.md §3.10、§4.4、§5.4、§6.7、§6.10 R8 R9；build/v6/brief.md §2）
//
// 一筆保費只算一次。保險的錢住在四個地方，這裡合成一張表（財富頁 ⑦、保單頁、要確認 #15、一年一約到期提醒都讀這一份）：
// • 財富頁的保障型保單（LifeMilestone .insurance）——保費＝記帳那一筆固定支出（帳本 policies[id].linkedExpenseId 連著的）；
//   沒連的照 v3：里程碑的 premiumAmount＋帳本的繳法、下次扣款日、從哪扣。
// • 儲蓄險（FinanceStore.insurances，滿期的不列）——保費＝它連的記帳固定支出（SavingsInsurance.linkedExpenseId，或記帳那筆
//   linkedInsuranceId 指著它）；找不到就用保單上的保費與繳法。
// • 車險（記帳保險固定支出 linkedVehicleId ≠ nil，車子卡就是這樣認的；賣掉的車不列）。
// • 房屋險（RealEstate.insuranceItems[].linkedExpenseId；賣掉的房子不列；沒連記帳的那一項照它的金額當一年）。
// 認領順序（先認先得，一筆記帳保費只被一張認領）：保單連結 → 儲蓄險 → 車 → 房。
// 剩下「記帳保險固定支出、週期性、不是儲蓄險、還在扣」而且沒被認領的＝灰字「記帳裡還有 N 筆保費沒有保單資料」〔補保單〕；
// 其中跟某張還沒連的保單像同一張的（金額一樣，或標題有保險公司／保單名稱）不放灰字，改成要確認 #15 問「是同一張嗎？」。
// 一年合計：每一列「每期 × 一年幾次」換台幣（只有外幣儲蓄險是原幣存的；查不到匯率的不算、標「外幣照今天匯率」）。
// 保障型＝不是儲蓄險的那幾列（醫療、意外、車險、房屋險…）。不算「應該保多少」（judge §3.10）。
// 保障六格（醫療・意外・癌症／重大疾病・失能／長照・壽險・其他）：財富頁的保障型保單有這一種就亮、寫保險公司；沒有灰「還沒記」。
// 一年一約＝繳費年期 1 年、不是躉繳：生效日每年同一天到期；60 天內要確認提醒續保、30 天前 09:00 通知（不寫公司、金額）。
// 純值、在 WealthFacts.build 裡建一次（LifeStore.wealthFacts 的快取；記帳、理財、帳本一改就重算）。
// 字：金額、日期的字在這裡組好（WealthFormat，哪個執行緒都可以）；要「萬」的那兩句（一年約、保障型）是 computed，請在主執行緒叫。

/// 保單總表一列從哪裡來（點了開哪裡）
enum WealthPolicySource: Equatable {
    /// 財富頁的保障型保單（里程碑 id）→ 保單頁
    case policy(UUID)
    /// 儲蓄險（SavingsInsurance.id）→ 彈出 InsurancePolicyCard
    case savings(UUID)
    /// 車險（車子 id）→ 彈出 VehicleDetailView
    case vehicle(UUID)
    /// 房屋險（房子 id）→ 彈出 RealEstateDetailView
    case house(UUID)
}

struct WealthPolicyFacts {
    /// 保單總表的一列
    struct Row: Identifiable {
        /// 「p-<保單>」「s-<儲蓄險>」「v-<記帳>」「h-<房子>-<那一項>」
        let id: String
        let source: WealthPolicySource
        /// SF Symbol（iOS 18 都有）
        let icon: String
        /// 「國泰人壽 醫療險」「富邦人壽 美元儲蓄險」「Taycan 車險」「苗栗的家 住宅火險」
        let title: String
        /// 「24,000」「US$3,000」；不知道金額「—」
        let amountText: String
        /// 「/年」「/月」「/季」「/半年」「躉繳」「繳完了」；不知道繳法 nil
        let unitText: String?
        /// 右邊小字（點了開別的頁）：「儲蓄險」「車子卡」「房屋卡」；保障型保單 nil
        let tag: String?
        /// 「下次 2027/8/15・刷 CUBE」「下次 2027/2/1・從美金扣」；都沒有 nil
        let detail: String?
        /// 一年（台幣）；查不到匯率、不知道金額 nil
        let yearlyNTD: Double?
        /// 不是儲蓄險
        let isProtection: Bool
        /// 認領的記帳保費（沒有 nil）
        let expenseId: UUID?
        /// 原幣（台幣 "NT$"）
        let code: String
        /// VoiceOver：「國泰人壽 醫療險，一年 24,000 元，下次 2027/8/15・刷 CUBE」（金額遮住由畫面換掉）
        let accessibilityText: String
    }

    /// 財富頁的一張保障型保單（保單頁、要確認、提醒都讀這一份）
    struct Policy: Identifiable {
        let id: UUID
        /// 暱稱 → 「保險公司 醫療險」→ 里程碑標題
        let title: String
        let company: String
        let kind: WealthPolicyKind
        /// 連著的記帳保費（帳本 linkedExpenseId 而且記帳裡找得到）；沒連 nil
        let expenseId: UUID?
        /// 原幣（連著＝記帳那筆的幣別；沒連 "NT$"）
        let code: String
        /// 每期（原幣；連著＝記帳那筆現在的金額，記帳改了這裡跟著；沒連＝你填的保費）；不知道 0
        let perPeriod: Double
        /// 繳法（連著＝記帳那筆的週期；沒連＝帳本的繳法）；不知道 nil
        let cycle: WealthPolicyCycle?
        /// 舊資料：有保費、沒連記帳、沒寫繳法（保單頁要確認問「是一年繳一次嗎？」）
        let cycleMissing: Bool
        /// 一年（原幣；躉繳、繳完了 0）
        let yearly: Double
        /// 一年（台幣；查不到匯率 nil）
        let yearlyNTD: Double?
        let nextDue: Date?
        let payerId: UUID?
        /// 「刷 CUBE」「從薪轉扣」；沒有 nil
        let payerText: String?
        /// 生效日（里程碑的日期）
        let start: Date
        /// 繳費年期（年；沒填、躉繳 nil）
        let payYears: Int?
        /// 第幾年（生效日起滿幾年＋1；還沒生效 0）
        let yearIndex: Int
        /// 已繳幾年（有繳費年期才有：min(第幾年, 繳費年期)）
        let paidYears: Int?
        /// 繳費年期滿了（一年一約每年續約，不算），或連著的記帳那筆已經停了
        let finished: Bool
        /// 連著的記帳那筆到今天扣了幾期（沒連 nil）
        let paidPeriods: Int?
        /// 一共幾期（繳費年期 × 一年幾次；不知道 nil）
        let totalPeriods: Int?
        /// 一年一約（繳費年期 1 年、不是躉繳）
        let isOneYear: Bool
        /// 一年一約的下次到期（生效日每年同一天，今天或以後）；不是一年一約 nil
        let renewal: Date?
        /// 收起來了（帳本 hidden）
        let hidden: Bool

        var isLinked: Bool { expenseId != nil }
    }

    /// 記帳裡有、沒有保單資料的保費（灰字一行〔補保單〕）
    struct Unclaimed: Identifiable {
        let expenseId: UUID
        let title: String
        /// 「1,200/年」
        let amountText: String
        let yearlyNTD: Double?

        var id: UUID { expenseId }
        /// 「中國人壽意外險 1,200/年」
        var text: String { title + " " + amountText }
    }

    /// 保障六格的一格
    struct Cell: Identifiable {
        /// 「medical」「accident」「cancer」「disability」「life」「other」
        let id: String
        /// 「醫療」「意外」「癌症／重大疾病」「失能／長照」「壽險」「其他」
        let title: String
        let icon: String
        let on: Bool
        /// 有：「國泰人壽」「國泰人壽、南山人壽 等 3 張」；沒有：「還沒記」
        let detail: String
        let policyIds: [UUID]
    }

    /// 要確認 #15：這張保單跟記帳的這一筆保費像同一張
    struct Match {
        let policyId: UUID
        let expenseId: UUID
        /// 3 金額和名字都對、2 金額一樣、1 標題有保險公司／保單名稱
        let score: Int
        /// 「國泰人壽 醫療險：記帳裡有一筆一樣的保費（每年 8/15・24,000・刷 CUBE），是同一張嗎？」
        let text: String
    }

    let rows: [Row]
    let policies: [Policy]
    let unclaimed: [Unclaimed]
    let cells: [Cell]
    let matches: [Match]
    /// 一年合計（台幣；rows 裡算得出來的）
    let yearlyNTD: Double
    /// 保障型一年（不是儲蓄險的那幾列）
    let protectionNTD: Double
    let hasSavings: Bool
    let hasForeign: Bool
    /// 有一列查不到匯率（合計前面加「約」）
    let hasUnknownRate: Bool
    /// 被認領的記帳保費
    let claimed: Set<UUID>

    init(rows: [Row] = [], policies: [Policy] = [], unclaimed: [Unclaimed] = [], cells: [Cell] = [],
         matches: [Match] = [], yearlyNTD: Double = 0, protectionNTD: Double = 0, hasSavings: Bool = false,
         hasForeign: Bool = false, hasUnknownRate: Bool = false, claimed: Set<UUID> = []) {
        self.rows = rows
        self.policies = policies
        self.unclaimed = unclaimed
        self.cells = cells
        self.matches = matches
        self.yearlyNTD = yearlyNTD
        self.protectionNTD = protectionNTD
        self.hasSavings = hasSavings
        self.hasForeign = hasForeign
        self.hasUnknownRate = hasUnknownRate
        self.claimed = claimed
    }

    func policy(_ id: UUID?) -> Policy? {
        guard let id else { return nil }
        return policies.first { $0.id == id }
    }

    /// 連著這一筆記帳保費的保單（AddExpenseView 寫回、保單頁）；沒有 nil
    func policy(linkedTo expenseId: UUID) -> Policy? {
        policies.first { $0.expenseId == expenseId }
    }

    /// 這張保單 #15 的候選（保單頁〔是同一張，連起來〕用；沒有 nil）
    func match(for policyId: UUID) -> Match? {
        matches.first { $0.policyId == policyId }
    }

    /// 保費刷這張卡／從這個帳戶扣的保單（#12 卡片效期：保單頁也看得到「刷的 CUBE 3 月到期」）
    func policyIds(paidBy payer: UUID) -> [UUID] {
        policies.filter { $0.payerId == payer && !$0.hidden }.map(\.id)
    }

    /// 財富頁 ⑦ 右上「一年約 NT$16萬」（查不到匯率的不算、前面照樣寫「約」）；一列都算不出來 nil。ntdWanString：主執行緒
    var trailingText: String? {
        guard rows.contains(where: { $0.yearlyNTD != nil }) else { return nil }
        return "一年約 " + yearlyNTD.ntdWanString
    }

    /// 財富頁 ⑦ 最下灰字「保障型一年 6.4萬（不含儲蓄險）・外幣照今天匯率」；都不用寫 nil。主執行緒
    var footerText: String? {
        var parts: [String] = []
        if hasSavings && protectionNTD > 0.5 {
            parts.append("保障型一年 " + WealthPolicyFacts.wan(protectionNTD) + "（不含儲蓄險）")
        }
        if hasForeign { parts.append("外幣照今天匯率") }
        return parts.isEmpty ? nil : parts.joined(separator: "・")
    }

    /// 「記帳裡還有 1 筆保費沒有保單資料：中國人壽意外險 1,200/年」；沒有 nil
    var unclaimedText: String? {
        guard let first = unclaimed.first else { return nil }
        var s = "記帳裡還有 \(unclaimed.count) 筆保費沒有保單資料：" + first.text
        if unclaimed.count > 1 { s += " 等" }
        return s
    }

    /// 「6.4萬」「2,100」（ntdWanString 去掉 NT$；一萬以下寫到元）
    static func wan(_ v: Double) -> String {
        if Swift.abs(v) >= 10_000 {
            return v.ntdWanString.replacingOccurrences(of: "NT$", with: "")
        }
        return WealthFormat.grouped(v.rounded(), decimals: 0)
    }

    // MARK: 字

    /// 保單列的金額：台幣「24,000」（不寫 NT$）；外幣整數「US$3,000」、有零頭「US$3,000.50」
    static func amountText(_ v: Double, code: String) -> String {
        if FinanceRates.isNTD(code) { return WealthFormat.grouped(v.rounded(), decimals: 0) }
        let whole = Swift.abs(v - v.rounded()) < 0.005
        return WealthFormat.foreignPrefix(code) + WealthFormat.grouped(v, decimals: whole ? 0 : 2)
    }

    /// 繳法的單位：「/年」「/半年」「/季」「/月」「躉繳」
    static func unitText(_ c: WealthPolicyCycle) -> String {
        switch c {
        case .year: return "/年"
        case .half: return "/半年"
        case .quarter: return "/季"
        case .month: return "/月"
        case .single: return "躉繳"
        }
    }

    /// 險種圖示（財富頁 ⑦、保障六格、保單頁）
    static func icon(_ k: WealthPolicyKind) -> String {
        switch k {
        case .medical: return "cross.case.fill"
        case .accident: return "bandage.fill"
        case .cancer: return "heart.text.square.fill"
        case .disability: return "figure.roll"
        case .life: return "heart.fill"
        case .travel: return "airplane"
        case .other: return "shield.fill"
        }
    }

    /// 保單的名字（同財富頁 ⑦、保單頁工具列）：暱稱 →「保險公司 醫療險」→ 里程碑標題
    static func title(of m: LifeMilestone, book: WealthBook) -> String {
        let kind = book.policy(m.id).kind ?? WealthPolicyKind.from(legacy: m.insuranceType)
        if let n = book.account(m.id).trimmedNickname { return n }
        let company = (m.insuranceCompany ?? "").trimmingCharacters(in: .whitespaces)
        return company.isEmpty ? m.title : company + " " + kind.shortTitle
    }

    /// 「刷 CUBE」「從薪轉扣」（卡優先；名字照財富的暱稱）；都沒有 nil
    static func payerText(cardId: UUID?, bankId: UUID?, names: [UUID: String]) -> String? {
        if let c = cardId, let n = names[c] { return "刷 " + n }
        if let b = bankId, let n = names[b] { return "從" + n + "扣" }
        return nil
    }

    // MARK: build

    /// 一次建好（WealthFacts.build 叫；names＝WealthFacts 的帳戶、卡名字；cardIds＝信用卡的 id：帳本 payFromId 是卡還是銀行靠它分）
    static func build(milestones: [LifeMilestone], book: WealthBook, expenses: [Expense],
                      insurances: [SavingsInsurance], vehicles: [Vehicle], realEstates: [RealEstate],
                      names: [UUID: String], cardIds: Set<UUID>, rates: FinanceRates, today: Date) -> WealthPolicyFacts {
        let byId = Dictionary(expenses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var claimed = Set<UUID>()
        var rows: [Row] = []
        var policies: [Policy] = []

        // ① 財富頁的保障型保單（照你排的順序，沒排照生效日）
        let policyMs = WealthPolicyLink.orderedPolicies(milestones, book: book)
        for m in policyMs {
            let prefs = book.policy(m.id)
            var linked: Expense? = nil
            if let eid = prefs.linkedExpenseId, let e = byId[eid], !claimed.contains(eid) {
                linked = e
                claimed.insert(eid)
            }
            let p = makePolicy(m, prefs: prefs, book: book, expense: linked, names: names, cardIds: cardIds,
                               rates: rates, today: today)
            policies.append(p)
            if !p.hidden { rows.append(policyRow(p)) }
        }

        // ② 儲蓄險（滿期的不列）
        let liveSavings = insurances.filter { WealthCal.day($0.maturityDate) > today }
            .sorted { a, b in a.startDate != b.startDate ? a.startDate < b.startDate : a.id.uuidString < b.id.uuidString }
        for ins in liveSavings {
            var e: Expense? = nil
            if let eid = ins.linkedExpenseId, let found = byId[eid], !claimed.contains(eid) {
                e = found
            } else {
                e = expenses.first { $0.linkedInsuranceId == ins.id && !claimed.contains($0.id) }
            }
            if let x = e { claimed.insert(x.id) }
            rows.append(savingsRow(ins, expense: e, names: names, rates: rates, today: today))
        }

        // ③ 車險（記帳保險固定支出連到車；賣掉的車不列；停了的不列）
        let liveVehicles = vehicles.filter { !$0.isSold(asOf: today) }
        for v in liveVehicles {
            let mine = expenses.filter { e in
                e.linkedVehicleId == v.id && e.expenseType == .fixed && e.fixedCategory == .insurance
                    && e.recurrence != nil && !claimed.contains(e.id) && !WealthPolicyLink.isEnded(e, today: today)
            }.sorted { a, b in a.date != b.date ? a.date < b.date : a.id.uuidString < b.id.uuidString }
            for e in mine {
                claimed.insert(e.id)
                rows.append(vehicleRow(v, expense: e, names: names, rates: rates, today: today))
            }
        }

        // ④ 房屋險（RealEstate.insuranceItems；賣掉的房子不列）
        for re in realEstates where re.soldDate == nil {
            for item in re.insuranceItems {
                var e: Expense? = nil
                if let eid = item.linkedExpenseId {
                    if claimed.contains(eid) { continue }
                    if let found = byId[eid] {
                        if WealthPolicyLink.isEnded(found, today: today) { continue }
                        e = found
                        claimed.insert(eid)
                    }
                }
                guard e != nil || item.amount > 0.5 else { continue }
                rows.append(houseRow(re, item: item, expense: e, names: names, rates: rates, today: today))
            }
        }

        // ⑤ 沒被認領的記帳保費：像某張還沒連的保單 → #15；其他 → 灰字
        let free: [Expense] = expenses.filter { e in
            WealthPolicyLink.isPremiumExpense(e, today: today) && !claimed.contains(e.id)
        }.sorted { a, b in a.date != b.date ? a.date < b.date : a.id.uuidString < b.id.uuidString }
        var used = Set<UUID>()
        var matches: [Match] = []
        for p in policies where !p.hidden && !p.isLinked {
            var best: Expense? = nil
            var bestScore = 0
            for e in free where !used.contains(e.id) {
                if book.isDismissed(WealthPolicyLink.matchKey(policyId: p.id, expenseId: e.id)) { continue }
                let s = WealthPolicyLink.score(e, amount: p.perPeriod, company: p.company,
                                               nickname: book.account(p.id).trimmedNickname, rates: rates)
                if s > bestScore {
                    best = e
                    bestScore = s
                }
            }
            guard let e = best, bestScore > 0 else { continue }
            used.insert(e.id)
            matches.append(Match(policyId: p.id, expenseId: e.id, score: bestScore,
                                 text: matchText(p, expense: e, score: bestScore, names: names, rates: rates)))
        }
        var unclaimed: [Unclaimed] = []
        for e in free where !used.contains(e.id) {
            let raw = e.amount
            let per = WealthPolicyLink.cycle(of: e.recurrence)
            let times = Double(per?.timesPerYear ?? 1)
            let ntd: Double? = ntdPerYear(raw * times, expense: e, rates: rates)
            let unit = per.map { unitText($0) } ?? ""
            unclaimed.append(Unclaimed(expenseId: e.id, title: e.title.trimmingCharacters(in: .whitespacesAndNewlines),
                                       amountText: amountText(raw, code: expenseCode(e)) + unit, yearlyNTD: ntd))
        }

        // 合計
        var total: Double = 0
        var protection: Double = 0
        var unknown = false
        var foreign = false
        var savings = false
        for r in rows {
            if !FinanceRates.isNTD(r.code) {
                foreign = true
                if rates.known(r.code) == nil { unknown = true }
            }
            if !r.isProtection { savings = true }
            guard let v = r.yearlyNTD else { continue }
            total += v
            if r.isProtection { protection += v }
        }

        return WealthPolicyFacts(rows: rows, policies: policies, unclaimed: unclaimed,
                                 cells: makeCells(policies), matches: matches,
                                 yearlyNTD: total, protectionNTD: protection, hasSavings: savings,
                                 hasForeign: foreign, hasUnknownRate: unknown, claimed: claimed)
    }

    /// 記帳那筆的幣別：只有外幣儲蓄險是原幣存的，其他都是台幣（AddExpenseView 存檔時已經換過）
    static func expenseCode(_ e: Expense) -> String {
        if let o = e.originalCurrencyAmount { return WealthFacts.norm(o.code) }
        return "NT$"
    }

    /// 一年（原幣）換台幣：外幣儲蓄險照設定匯率（查不到 nil）；其他已經是台幣
    /// [v25.567 裁] 名字不跟屬性 yearlyNTD 同名（規則上可以編，但沒編譯環境時不冒險）
    private static func ntdPerYear(_ yearlyRaw: Double, expense e: Expense?, rates: FinanceRates) -> Double? {
        guard let e, let o = e.originalCurrencyAmount else { return yearlyRaw }
        guard let r = rates.known(o.code) else { return nil }
        return yearlyRaw * r
    }

    private static func ntdPerYear(_ yearlyRaw: Double, code: String, rates: FinanceRates) -> Double? {
        if FinanceRates.isNTD(code) { return yearlyRaw }
        guard let r = rates.known(code) else { return nil }
        return yearlyRaw * r
    }

    /// 「下次 2027/8/15・刷 CUBE」；都沒有 nil
    private static func detailText(next: Date?, payer: String?) -> String? {
        var parts: [String] = []
        if let n = next { parts.append("下次 " + WealthFormat.ymd(n)) }
        if let p = payer { parts.append(p) }
        return parts.isEmpty ? nil : parts.joined(separator: "・")
    }

    private static func spokenAmount(_ yearly: Double?, code: String) -> String {
        guard let v = yearly else { return "" }
        if FinanceRates.isNTD(code) { return "，一年 " + WealthFormat.grouped(v.rounded(), decimals: 0) + " 元" }
        return "，一年 " + WealthFormat.money(v, code: code)
    }

    // MARK: 一張保障型保單

    private static func makePolicy(_ m: LifeMilestone, prefs: WealthPolicyPrefs, book: WealthBook, expense e: Expense?,
                                   names: [UUID: String], cardIds: Set<UUID>, rates: FinanceRates, today: Date) -> Policy {
        let kind = prefs.kind ?? WealthPolicyKind.from(legacy: m.insuranceType)
        let company = (m.insuranceCompany ?? "").trimmingCharacters(in: .whitespaces)
        let start = WealthCal.day(m.date)
        let payYears: Int? = prefs.payYears.flatMap { $0 > 0 ? $0 : nil }
        var yearIndex = 0
        if start <= today {
            let full = WealthCal.calendar.dateComponents([.year], from: start, to: today).year ?? 0
            yearIndex = Swift.max(0, full) + 1
        }
        let paidYears: Int? = payYears.map { Swift.min(yearIndex, $0) }

        let code: String
        let per: Double
        let cycle: WealthPolicyCycle?
        let next: Date?
        let payerId: UUID?
        let payerText: String?
        var finished = false
        var paidPeriods: Int? = nil
        if let e {
            code = expenseCode(e)
            per = e.amount
            cycle = WealthPolicyLink.cycle(of: e.recurrence)
            next = e.nextFixedDueDate(onOrAfter: today, calendar: WealthCal.calendar)
            payerId = e.linkedCreditCardMilestoneId ?? e.linkedBankMilestoneId
            payerText = Self.payerText(cardId: e.linkedCreditCardMilestoneId, bankId: e.linkedBankMilestoneId, names: names)
            paidPeriods = WealthSchedule.fixedPeriods(e, through: today).count
            if WealthPolicyLink.isEnded(e, today: today) || (e.recurrence != nil && next == nil) { finished = true }
        } else {
            code = "NT$"
            per = m.premiumAmount ?? 0
            cycle = prefs.cycle
            var n = prefs.nextDue.map { WealthCal.day($0) }
            // 你填的下次扣款日已經過了：照繳法往後推到今天以後（只有年／半年／季／月；推不動就不寫）
            if let d = n, d < today, let c = cycle, c.timesPerYear > 0 {
                let months = 12 / c.timesPerYear
                var k = 1
                var cur = d
                while cur < today && k < 1200 {
                    cur = WealthCal.addMonths(months * k, to: d)
                    k += 1
                }
                n = cur >= today ? cur : nil
            }
            next = n
            payerId = prefs.payFromId
            let isCard: Bool = prefs.payFromId.map { cardIds.contains($0) } ?? false
            payerText = isCard ? Self.payerText(cardId: prefs.payFromId, bankId: nil, names: names)
                               : Self.payerText(cardId: nil, bankId: prefs.payFromId, names: names)
        }
        let isOneYear = payYears == 1 && cycle != .single
        // [v25.567 驗] 一年一約每年續約：第 2 年起不是「繳完了」（以前第 2 年起當繳完了：列寫「2,400 繳完了」、不算進一年合計、沒有下次）
        if let py = payYears, yearIndex > py, !isOneYear { finished = true }
        // 一年（原幣）：繳完了、躉繳 0；不知道繳法也 0（不算進一年合計，保單頁要確認問「是一年繳一次嗎？」）
        var yearly: Double = 0
        if let c = cycle, !finished, c.timesPerYear > 0 { yearly = per * Double(c.timesPerYear) }
        var renewal: Date? = nil
        if isOneYear {
            // [v25.567 驗] 到期＝生效日之後的週年（最早是生效滿一年那天）：今天才生效、還沒生效的不是「今天到期」
            //（以前滿 0 年時拿生效日本身當到期日：新增一張今天生效的一年一約，馬上跳「今天到期：記得續保」）
            let full = Swift.max(0, WealthCal.calendar.dateComponents([.year], from: start, to: today).year ?? 0)
            let years = Swift.max(1, full)
            var cand = WealthCal.calendar.date(byAdding: .year, value: years, to: start) ?? start
            if WealthCal.day(cand) < today {
                cand = WealthCal.calendar.date(byAdding: .year, value: years + 1, to: start) ?? cand
            }
            renewal = WealthCal.day(cand)
        }
        var total: Int? = nil
        if let py = payYears, let c = cycle, c.timesPerYear > 0 { total = py * c.timesPerYear }
        return Policy(id: m.id, title: title(of: m, book: book), company: company, kind: kind,
                      expenseId: e?.id, code: code, perPeriod: per, cycle: cycle,
                      cycleMissing: e == nil && per > 0.5 && prefs.cycle == nil,
                      yearly: yearly, yearlyNTD: cycle == nil ? nil : ntdPerYear(yearly, code: code, rates: rates),
                      nextDue: finished ? nil : next, payerId: payerId, payerText: payerText,
                      start: start, payYears: payYears, yearIndex: yearIndex, paidYears: paidYears,
                      finished: finished, paidPeriods: paidPeriods, totalPeriods: total,
                      isOneYear: isOneYear, renewal: renewal, hidden: book.account(m.id).hidden == true)
    }

    /// 財富頁 ⑦ 保單那一列：「24,000 /年」；躉繳「120,000 躉繳」；繳完了「24,000 繳完了」（不算進一年）；
    /// 不知道繳法「24,000」（不算進一年）；沒填保費「—」
    private static func policyRow(_ p: Policy) -> Row {
        var amount = "—"
        var unit: String? = nil
        var yearly: Double? = nil
        if p.perPeriod > 0.5 {
            if let c = p.cycle {
                if c == .single {
                    amount = amountText(p.perPeriod, code: p.code)
                    unit = "躉繳"
                } else if p.finished {
                    amount = amountText(p.perPeriod * Double(c.timesPerYear), code: p.code)
                    unit = "繳完了"
                } else {
                    amount = amountText(p.yearly, code: p.code)
                    unit = "/年"
                    yearly = p.yearlyNTD
                }
            } else {
                amount = amountText(p.perPeriod, code: p.code)
            }
        }
        let detail = detailText(next: p.nextDue, payer: p.payerText)
        var said = p.title + spokenAmount(unit == "/年" ? p.yearly : nil, code: p.code)
        if let d = detail { said += "，" + d }
        return Row(id: "p-" + p.id.uuidString, source: .policy(p.id), icon: icon(p.kind), title: p.title,
                   amountText: amount, unitText: unit, tag: nil, detail: detail, yearlyNTD: yearly,
                   isProtection: true, expenseId: p.expenseId, code: p.code, accessibilityText: said)
    }

    private static func savingsRow(_ ins: SavingsInsurance, expense e: Expense?, names: [UUID: String],
                                   rates: FinanceRates, today: Date) -> Row {
        let company = ins.company.trimmingCharacters(in: .whitespaces)
        let name = ins.name.trimmingCharacters(in: .whitespaces)
        let title: String
        if company.isEmpty { title = name.isEmpty ? "儲蓄險" : name }
        else if name.isEmpty { title = company + " 儲蓄險" }
        else if name.hasPrefix(company) { title = name }
        else { title = company + " " + name }
        let code = WealthFacts.norm(ins.currencyCode)
        let cycle = WealthPolicyLink.cycle(of: ins.paymentPeriod)
        let times = Double(cycle?.timesPerYear ?? 1)
        let paidUp = ins.elapsedPeriods(at: today) >= ins.totalPeriods && ins.totalPeriods > 0
        let yearlyRaw = paidUp ? 0 : ins.premiumAmount * times
        let next: Date? = paidUp ? nil
            : (e?.nextFixedDueDate(onOrAfter: today, calendar: WealthCal.calendar) ?? ins.moneyNextDue(now: today))
        let payer = e.flatMap { x in payerText(cardId: x.linkedCreditCardMilestoneId, bankId: x.linkedBankMilestoneId, names: names) }
        let detail = detailText(next: next, payer: payer)
        let ntd = ntdPerYear(yearlyRaw, code: code, rates: rates)
        var said = title + spokenAmount(yearlyRaw, code: code)
        if let d = detail { said += "，" + d }
        return Row(id: "s-" + ins.id.uuidString, source: .savings(ins.id), icon: "leaf.fill", title: title,
                   amountText: amountText(paidUp ? ins.premiumAmount * times : yearlyRaw, code: code),
                   unitText: paidUp ? "繳完了" : "/年", tag: "儲蓄險", detail: detail, yearlyNTD: ntd,
                   isProtection: false, expenseId: e?.id, code: code, accessibilityText: said)
    }

    private static func vehicleRow(_ v: Vehicle, expense e: Expense, names: [UUID: String],
                                   rates: FinanceRates, today: Date) -> Row {
        let what: String
        switch e.insuranceSubCategory {
        case .compulsory?: what = "強制險"
        case .comprehensive?: what = "綜合險"
        default: what = "車險"
        }
        let name = v.name.trimmingCharacters(in: .whitespaces)
        let title = name.isEmpty ? what : name + " " + what
        let cycle = WealthPolicyLink.cycle(of: e.recurrence)
        let raw = e.amount
        let yearlyRaw = raw * Double(cycle?.timesPerYear ?? 1)
        let next = e.nextFixedDueDate(onOrAfter: today, calendar: WealthCal.calendar)
        let payer = payerText(cardId: e.linkedCreditCardMilestoneId, bankId: e.linkedBankMilestoneId, names: names)
        let detail = detailText(next: next, payer: payer)
        var said = title + spokenAmount(yearlyRaw, code: "NT$")
        if let d = detail { said += "，" + d }
        return Row(id: "v-" + e.id.uuidString, source: .vehicle(v.id), icon: "car.fill", title: title,
                   amountText: amountText(yearlyRaw, code: "NT$"), unitText: "/年", tag: "車子卡", detail: detail,
                   yearlyNTD: yearlyRaw, isProtection: true, expenseId: e.id, code: "NT$", accessibilityText: said)
    }

    private static func houseRow(_ re: RealEstate, item: RealEstateInsuranceItem, expense e: Expense?,
                                 names: [UUID: String], rates: FinanceRates, today: Date) -> Row {
        let estate = re.name.trimmingCharacters(in: .whitespaces)
        var what = "房屋險"
        if let x = e {
            let cleaned = HouseCardFormat.cleanTitle(x.title, estateName: estate).trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty && cleaned != "保險" { what = cleaned }
        }
        let title = estate.isEmpty ? what : estate + " " + what
        let cycle = WealthPolicyLink.cycle(of: e?.recurrence)
        let raw = e?.amount ?? item.amount
        // 沒連記帳、或記帳那筆不是週期性的：房子那一項的金額當一年
        let yearlyRaw = (e?.recurrence != nil) ? raw * Double(cycle?.timesPerYear ?? 1) : raw
        let next = e?.nextFixedDueDate(onOrAfter: today, calendar: WealthCal.calendar)
        let payer = e.flatMap { x in payerText(cardId: x.linkedCreditCardMilestoneId, bankId: x.linkedBankMilestoneId, names: names) }
        let detail = detailText(next: next, payer: payer)
        var said = title + spokenAmount(yearlyRaw, code: "NT$")
        if let d = detail { said += "，" + d }
        return Row(id: "h-" + re.id.uuidString + "-" + item.id.uuidString, source: .house(re.id), icon: "house.fill",
                   title: title, amountText: amountText(yearlyRaw, code: "NT$"), unitText: "/年", tag: "房屋卡",
                   detail: detail, yearlyNTD: yearlyRaw, isProtection: true, expenseId: e?.id, code: "NT$",
                   accessibilityText: said)
    }

    /// 「國泰人壽 醫療險：記帳裡有一筆一樣的保費（每年 8/15・24,000・刷 CUBE），是同一張嗎？」
    private static func matchText(_ p: Policy, expense e: Expense, score: Int, names: [UUID: String],
                                  rates: FinanceRates) -> String {
        var parts: [String] = [WealthPolicyLink.scheduleText(e)]
        parts.append(amountText(e.amount, code: expenseCode(e)))
        if let pay = payerText(cardId: e.linkedCreditCardMilestoneId, bankId: e.linkedBankMilestoneId, names: names) {
            parts.append(pay)
        }
        let like = score >= 2 ? "一樣的" : "像是它的"
        let title = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let which = (score >= 2 || title.isEmpty) ? "" : "「" + title + "」"
        // [v25.567 編] 拆兩段（一個運算式 8 個 + 太長，沒編譯環境時少冒險）
        let lead: String = p.title + "：記帳裡有一筆" + like + "保費" + which
        let detail: String = parts.joined(separator: "・")
        return lead + "（" + detail + "），是同一張嗎？"
    }

    // MARK: 保障六格

    private static func makeCells(_ policies: [Policy]) -> [Cell] {
        let groups: [(id: String, title: String, kinds: [WealthPolicyKind], icon: String)] = [
            (id: "medical", title: "醫療", kinds: [.medical], icon: icon(.medical)),
            (id: "accident", title: "意外", kinds: [.accident], icon: icon(.accident)),
            (id: "cancer", title: "癌症／重大疾病", kinds: [.cancer], icon: icon(.cancer)),
            (id: "disability", title: "失能／長照", kinds: [.disability], icon: icon(.disability)),
            (id: "life", title: "壽險", kinds: [.life], icon: icon(.life)),
            (id: "other", title: "其他", kinds: [.travel, .other], icon: icon(.other)),
        ]
        var out: [Cell] = []
        for g in groups {
            let mine = policies.filter { !$0.hidden && g.kinds.contains($0.kind) }
            var names: [String] = []
            for p in mine {
                let n = p.company.isEmpty ? p.title : p.company
                if !names.contains(n) { names.append(n) }
            }
            var detail = "還沒記"
            if !names.isEmpty {
                detail = names.prefix(2).joined(separator: "、")
                if mine.count > 2 { detail += " 等 \(mine.count) 張" }
            }
            out.append(Cell(id: g.id, title: g.title, icon: g.icon, on: !mine.isEmpty, detail: detail,
                            policyIds: mine.map(\.id)))
        }
        return out
    }

    // MARK: 要確認（WealthFacts.makeChecks 收進去：#15 像同一張、舊資料沒寫繳法、一年一約 60 天內到期）

    func checks(today: Date) -> [WealthCheck] {
        var out: [WealthCheck] = []
        // #15 保單跟記帳的保費像同一張
        for m in matches {
            out.append(WealthCheck(id: WealthPolicyLink.matchKey(policyId: m.policyId, expenseId: m.expenseId),
                                   kind: .policyMatch, tone: .info, text: m.text,
                                   actions: [WealthCheck.Action(title: "是同一張，連起來",
                                                                fix: .linkPolicy(policyId: m.policyId, expenseId: m.expenseId)),
                                             WealthCheck.Action(title: "不是", fix: .dismiss)],
                                   accountIds: [m.policyId]))
        }
        for p in policies where !p.hidden {
            // 舊資料沒寫繳法（保單頁才出現）
            if p.cycleMissing {
                let amount = WealthFormat.grouped(p.perPeriod.rounded(), decimals: 0)
                out.append(WealthCheck(id: "polcycle-" + p.id.uuidString, kind: .policyCycle, tone: .info,
                                       text: p.title + " " + amount + " 是一年繳一次嗎？",
                                       actions: [WealthCheck.Action(title: "年繳",
                                                                    fix: .setPolicyCycle(policyId: p.id,
                                                                                         cycle: WealthPolicyCycle.year.rawValue)),
                                                 WealthCheck.Action(title: "改繳法", fix: .editAccount(p.id))],
                                       accountIds: [p.id], onPage: false))
            }
            // 一年一約 60 天內到期（記得續保；續了照樣每年提醒）
            if let r = p.renewal {
                let left = WealthCal.days(from: today, to: r)
                if left >= 0 && left <= 60 {
                    let when = left == 0 ? "今天到期" : WealthFormat.monthDay(r) + " 到期"
                    out.append(WealthCheck(id: "polrenew-" + p.id.uuidString + "-" + WealthCal.dayKey(r),
                                           kind: .policyRenewal, tone: .warn,
                                           text: p.title + "一年一約，" + when + "：記得續保（續了就不用管）",
                                           actions: [WealthCheck.Action(title: "知道了", fix: .dismiss)],
                                           accountIds: [p.id]))
                }
            }
        }
        return out
    }
}

// MARK: - 保單 ↔ 記帳保費（一筆，只有一份；judge §5.4-3、§6.10 R8）

enum WealthPolicyLink {
    /// 要確認 #15 的 key（〔不是〕記進帳本 dismissed；下一筆像的還會再問）
    static func matchKey(policyId: UUID, expenseId: UUID) -> String {
        "polmatch-" + policyId.uuidString + "-" + expenseId.uuidString
    }

    /// 自動建記帳保費的第一期（保單表單、保單頁〔新建一筆〕）：你填的下次扣款日（今天或以後）；沒填或已經過了＝
    /// 那一天（沒填用生效日）照繳法往後推到今天或以後。以前的期數不補記：補了會讓以前的存摺上、卡費多扣，
    /// 跟你已經對過的存摺對不上（保單頁的「第 6／20 年」照生效日算，不看記帳那筆從哪天起）
    static func firstDue(start: Date, nextDue: Date?, cycle: WealthPolicyCycle, today: Date) -> Date {
        if let n = nextDue, WealthCal.day(n) >= today { return WealthCal.day(n) }
        let base = WealthCal.day(nextDue ?? start)
        guard cycle.timesPerYear > 0 else { return base < today ? today : base }
        let months = 12 / cycle.timesPerYear
        var k = 0
        var cur = base
        while cur < today && k < 1200 {
            k += 1
            cur = WealthCal.addMonths(months * k, to: base)
        }
        return cur
    }

    /// [v25.567 驗] 自動建的記帳保費最後扣到哪天（Expense.endDate）：生效日＋繳費年期的前一天
    ///（20 年期、2021/8/15 生效＝2041/8/14，最後一期 2040/8/15）。一年一約（繳費年期 1 年）每年續約、沒填繳費年期＝nil（不停）。
    /// 以前沒有停止日：繳費年期滿了記帳照樣每年扣（存摺上、卡費、稅務頁都多算），已經繳完的保單存檔還會新建一筆
    static func premiumStop(start: Date?, payYears: Int?) -> Date? {
        guard let s = start, let py = payYears, py > 1,
              let end = WealthCal.calendar.date(byAdding: .year, value: py, to: WealthCal.day(s)) else { return nil }
        return WealthCal.addDays(-1, to: end)
    }

    /// 記帳的週期 → 保單繳法（每年／每季／每月；沒有週期 nil）
    static func cycle(of r: Recurrence?) -> WealthPolicyCycle? {
        switch r {
        case .yearly?: return .year
        case .quarterly?: return .quarter
        case .monthly?: return .month
        case nil: return nil
        }
    }

    /// 保單繳法 → 記帳的週期（半年繳、躉繳記帳沒有對應的週期：不自動建記帳）
    static func recurrence(of c: WealthPolicyCycle) -> Recurrence? {
        switch c {
        case .year: return .yearly
        case .quarter: return .quarterly
        case .month: return .monthly
        case .half, .single: return nil
        }
    }

    /// 自動建的記帳保費用哪個保險子分類（人身保險：意外、旅平＝意外險；其他＝壽險。稅務頁都算保險費）
    static func insuranceSub(_ k: WealthPolicyKind) -> InsuranceSubCategory {
        switch k {
        case .accident, .travel: return .accident
        case .medical, .cancer, .disability, .life, .other: return .life
        }
    }

    /// 這筆記帳停了（結束日在今天以前）
    static func isEnded(_ e: Expense, today: Date) -> Bool {
        guard let end = e.endDate else { return false }
        return WealthCal.day(end) < today
    }

    /// 記帳裡的一筆保障型保費：固定支出、保險、週期性、不是儲蓄險、沒連儲蓄險／車子、還在扣
    static func isPremiumExpense(_ e: Expense, today: Date) -> Bool {
        guard e.expenseType == .fixed, e.fixedCategory == .insurance, e.recurrence != nil else { return false }
        if e.insuranceSubCategory == .savings || e.linkedInsuranceId != nil || e.linkedVehicleId != nil { return false }
        return !isEnded(e, today: today)
    }

    /// 像不像同一張：3 金額一樣而且標題有保險公司／保單名稱、2 金額一樣、1 只有名字對、0 不像。
    /// amount＝保單每期的保費（台幣）；記帳那筆的金額照台幣比（差不到 1 元算一樣）
    static func score(_ e: Expense, amount: Double, company: String, nickname: String?, rates: FinanceRates) -> Int {
        let ntd = WealthSchedule.ntd(of: e, raw: e.amount, rates: rates)
        let sameAmount = amount > 0.5 && Swift.abs(ntd - amount) < 0.5
        let title = e.title
        var sameName = false
        let c = company.trimmingCharacters(in: .whitespaces)
        if c.count >= 2 && title.contains(c) { sameName = true }
        if !sameName {
            let brand = brandName(c)
            if brand.count >= 2 && title.contains(brand) { sameName = true }
        }
        if !sameName, let n = nickname?.trimmingCharacters(in: .whitespaces), n.count >= 2, title.contains(n) {
            sameName = true
        }
        if sameAmount && sameName { return 3 }
        if sameAmount { return 2 }
        if sameName { return 1 }
        return 0
    }

    /// 「國泰人壽」→「國泰」（記帳標題常只寫品牌）
    static func brandName(_ company: String) -> String {
        var s = company
        for suffix in ["人壽保險", "產物保險", "人壽", "產險", "保險"] where s.hasSuffix(suffix) {
            s = String(s.dropLast(suffix.count))
            break
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// 「每年 8/15」「每月 6 日」「每季 6 日」（同 WealthCardText.schedule）
    static func scheduleText(_ e: Expense) -> String {
        let day = WealthCal.calendar.component(.day, from: e.date)
        switch e.recurrence {
        case .monthly?: return "每月 \(day) 日"
        case .quarterly?: return "每季 \(day) 日"
        case .yearly?: return "每年 " + WealthFormat.monthDay(e.date)
        case nil: return WealthFormat.monthDay(e.date)
        }
    }

    /// 財富頁的保障型保單：照你排的順序，沒排照生效日（收起來的也在裡面，看 Policy.hidden）
    static func orderedPolicies(_ milestones: [LifeMilestone], book: WealthBook) -> [LifeMilestone] {
        let list = milestones.filter { $0.category == .achievement && $0.financeSubCategory == .insurance }
        return list.enumerated().sorted { l, r in
            let a = book.account(l.element.id).sortIndex
            let b = book.account(r.element.id).sortIndex
            switch (a, b) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: break
            }
            if l.element.date != r.element.date { return l.element.date < r.element.date }
            return l.offset < r.offset
        }.map(\.element)
    }
}
