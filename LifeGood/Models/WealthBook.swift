import Foundation

// MARK: - [v25.563] 財富帳本（wealth/judge.md §3.14）
//
// 帳戶本身不搬：銀行、信用卡、證券、保險仍是原本那筆 LifeMilestone（category .achievement＋financeSubCategory），
// 記帳、收入、股票、BankDeposit 上既有的連結照舊指著它，一條都不用搬。
// 這裡只放「新欄位」，存在 LifeStore.wealthBook，同步鍵 life_wealth_book_v1——
// 跟 v25.557 請假週同一招：還沒更新的 iPad 不認得這個鍵，存東西時不會把它蓋掉
// （新欄位要是加在 LifeMilestone 上，舊 iPad 存一次里程碑就全丟）。
// 舊 iPad、網頁版、醫療地圖要讀的舊欄位照寫一份（例：改扣款帳戶時同時寫回卡的 linkedBankMilestoneId）。
//
// 全部欄位 Optional＋decodeIfPresent（壞一個欄位不會整本讀不出來）；編碼走合成版、只認 CodingKeys，
// 新欄位一定要在 CodingKeys 加，不然存不進去、也不會有編譯錯誤。
// v2 用到：cards[].payFrom（改扣款帳戶從哪一期起）、notices（「為什麼數字變了」說明過了）。
// 其他欄位 v2 先定好、照讀照存（畫面 v3 起）：沒設＝跟以前一樣。
// [v25.564] v3 加：policies（保單繳法）、incomeHistory（月薪金額歷史從記帳那一包搬來）、linkFrom（定期扣款／收入改卡改帳戶
// 從哪天起）、excludedExpenses（要確認 #4「這筆不算」）；帳戶加 accountNumberCipher／currencies／settlementBankId；
// 卡加 免年費條件、算到下一期的刷卡；帳單註記加 notPaid。全部 Optional＋decodeIfPresent（合成編碼，只認 CodingKeys）。

struct WealthBook: Codable, Equatable {
    /// 每個銀行／證券帳戶的設定（key＝帳戶那筆 LifeMilestone 的 id.uuidString）
    var accounts: [String: WealthAccountPrefs]?
    /// 每張信用卡的設定（key＝卡那筆 LifeMilestone 的 id.uuidString）
    var cards: [String: WealthCardPrefs]?
    /// 要確認按過「知道了」的 key（v3 起）
    var dismissed: [String]?
    /// 說明過一次的事（WealthBook.passbookNoticeKey＝v2「為什麼數字變了」）；跟 iCloud 同步，換一台不會再說一次
    var notices: [String]?
    /// [v25.564] 保單的新欄位（key＝保單那筆 LifeMilestone 的 id.uuidString；v3 先存繳法、繳費年期、險種）
    var policies: [String: WealthPolicyPrefs]?
    /// [v25.564] 週期性收入（月薪）的金額歷史（key＝Income.id.uuidString）。
    /// v2 放在 Income.amountHistory（記帳那一包）：還沒更新的 iPad 一記帳就把它洗掉；v3 起以這裡為準，Income 那份照寫一份
    var incomeHistory: [String: [AmountSnapshot]]?
    /// [v25.564] 定期扣款／週期性收入改卡、改帳戶的歷史（key＝Expense.id 或 Income.id 的 uuidString）。
    /// fromKey＝「2026-11-06」（那天起，WealthCal.dayKey）、accountId＝那一段的卡或銀行帳戶；
    /// 跟 cards[].payFrom 同一招：最後一段一律以記帳那筆現在的連結為準（還沒更新的 iPad 改了也跟得上）
    var linkFrom: [String: [WealthPayFrom]]?
    /// [v25.564] 要確認 #4 按了「這筆不算」的記帳（像「繳卡費」的支出，Expense.id.uuidString）：那筆不扣任何帳戶（記帳照留）
    var excludedExpenses: [String]?

    /// [v25.563] 「銀行的數字改成跟存摺一樣」那段說明的 key
    static let passbookNoticeKey = "v2-passbook"

    init(accounts: [String: WealthAccountPrefs]? = nil, cards: [String: WealthCardPrefs]? = nil,
         dismissed: [String]? = nil, notices: [String]? = nil,
         policies: [String: WealthPolicyPrefs]? = nil, incomeHistory: [String: [AmountSnapshot]]? = nil,
         linkFrom: [String: [WealthPayFrom]]? = nil, excludedExpenses: [String]? = nil) {
        self.accounts = accounts
        self.cards = cards
        self.dismissed = dismissed
        self.notices = notices
        self.policies = policies
        self.incomeHistory = incomeHistory
        self.linkFrom = linkFrom
        self.excludedExpenses = excludedExpenses
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try? c.decodeIfPresent([String: WealthAccountPrefs].self, forKey: .accounts)
        cards = try? c.decodeIfPresent([String: WealthCardPrefs].self, forKey: .cards)
        dismissed = try? c.decodeIfPresent([String].self, forKey: .dismissed)
        notices = try? c.decodeIfPresent([String].self, forKey: .notices)
        // [v25.564] 下面四個 v2 的帳本沒有＝nil（跟 CodingKeys 第二行成對）
        policies = try? c.decodeIfPresent([String: WealthPolicyPrefs].self, forKey: .policies)
        incomeHistory = try? c.decodeIfPresent([String: [AmountSnapshot]].self, forKey: .incomeHistory)
        linkFrom = try? c.decodeIfPresent([String: [WealthPayFrom]].self, forKey: .linkFrom)
        excludedExpenses = try? c.decodeIfPresent([String].self, forKey: .excludedExpenses)
    }

    private enum CodingKeys: String, CodingKey {
        case accounts, cards, dismissed, notices
        case policies, incomeHistory, linkFrom, excludedExpenses
    }

    var isEmpty: Bool {
        (accounts ?? [:]).isEmpty && (cards ?? [:]).isEmpty
            && (dismissed ?? []).isEmpty && (notices ?? []).isEmpty
            && (policies ?? [:]).isEmpty && (incomeHistory ?? [:]).isEmpty
            && (linkFrom ?? [:]).isEmpty && (excludedExpenses ?? []).isEmpty
    }

    /// 這個帳戶的設定（沒設過＝全部 nil，等於跟以前一樣）
    func account(_ id: UUID) -> WealthAccountPrefs {
        accounts?[id.uuidString] ?? WealthAccountPrefs()
    }

    /// 這張卡的設定（沒設過＝全部 nil）
    func card(_ id: UUID) -> WealthCardPrefs {
        cards?[id.uuidString] ?? WealthCardPrefs()
    }

    mutating func setAccount(_ prefs: WealthAccountPrefs, for id: UUID) {
        var all = accounts ?? [:]
        if prefs.isEmpty { all.removeValue(forKey: id.uuidString) } else { all[id.uuidString] = prefs }
        accounts = all.isEmpty ? nil : all
    }

    mutating func setCard(_ prefs: WealthCardPrefs, for id: UUID) {
        var all = cards ?? [:]
        if prefs.isEmpty { all.removeValue(forKey: id.uuidString) } else { all[id.uuidString] = prefs }
        cards = all.isEmpty ? nil : all
    }

    /// 刪帳戶、刪卡時把它的設定一起清掉（LifeStore.deleteFinanceMilestone）
    mutating func remove(_ id: UUID) {
        if var a = accounts { a.removeValue(forKey: id.uuidString); accounts = a.isEmpty ? nil : a }
        if var c = cards { c.removeValue(forKey: id.uuidString); cards = c.isEmpty ? nil : c }
        if var p = policies { p.removeValue(forKey: id.uuidString); policies = p.isEmpty ? nil : p }
    }

    // MARK: - [v25.564] v3 的存取

    /// 這張保單的設定（沒設過＝全部 nil）
    func policy(_ id: UUID) -> WealthPolicyPrefs {
        policies?[id.uuidString] ?? WealthPolicyPrefs()
    }

    mutating func setPolicy(_ prefs: WealthPolicyPrefs, for id: UUID) {
        var all = policies ?? [:]
        if prefs.isEmpty { all.removeValue(forKey: id.uuidString) } else { all[id.uuidString] = prefs }
        policies = all.isEmpty ? nil : all
    }

    /// 這筆收入的金額歷史（帳本沒有＝nil，呼叫端再退回 Income.amountHistory）
    func incomeAmountHistory(_ incomeId: UUID) -> [AmountSnapshot]? {
        incomeHistory?[incomeId.uuidString]
    }

    /// nil 或空＝拿掉（全部都改、新增）
    mutating func setIncomeAmountHistory(_ history: [AmountSnapshot]?, for incomeId: UUID) {
        var all = incomeHistory ?? [:]
        if let h = history, !h.isEmpty { all[incomeId.uuidString] = h } else { all.removeValue(forKey: incomeId.uuidString) }
        incomeHistory = all.isEmpty ? nil : all
    }

    /// 這筆定期扣款／收入改卡改帳戶的歷史（沒有＝nil）
    func links(_ itemId: UUID) -> [WealthPayFrom]? {
        linkFrom?[itemId.uuidString]
    }

    mutating func setLinks(_ history: [WealthPayFrom]?, for itemId: UUID) {
        var all = linkFrom ?? [:]
        if let h = history, !h.isEmpty { all[itemId.uuidString] = h } else { all.removeValue(forKey: itemId.uuidString) }
        linkFrom = all.isEmpty ? nil : all
    }

    func isExcluded(_ expenseId: UUID) -> Bool {
        (excludedExpenses ?? []).contains(expenseId.uuidString)
    }

    mutating func setExcluded(_ expenseId: UUID, _ excluded: Bool) {
        var all = excludedExpenses ?? []
        let k = expenseId.uuidString
        if excluded { if !all.contains(k) { all.append(k) } } else { all.removeAll { $0 == k } }
        excludedExpenses = all.isEmpty ? nil : all
    }

    /// 要確認按過「知道了」（key 帶事件：下個月同樣的事 key 不一樣，會再出現）
    func isDismissed(_ key: String) -> Bool { (dismissed ?? []).contains(key) }

    mutating func dismiss(_ key: String) {
        var all = dismissed ?? []
        guard !key.isEmpty, !all.contains(key) else { return }
        all.append(key)
        dismissed = all
    }

    /// 改一期帳單的註記（標成已繳、帳單金額不一樣、還沒繳）；改完是空的就拿掉
    mutating func updateStatement(cardId: UUID, key: String, _ body: (inout WealthStatementNote) -> Void) {
        var prefs = card(cardId)
        var all = prefs.statements ?? [:]
        var note = all[key] ?? WealthStatementNote()
        body(&note)
        if note.isEmpty { all.removeValue(forKey: key) } else { all[key] = note }
        prefs.statements = all.isEmpty ? nil : all
        setCard(prefs, for: cardId)
    }

    func hasNotice(_ key: String) -> Bool { (notices ?? []).contains(key) }

    mutating func addNotice(_ key: String) {
        var all = notices ?? []
        guard !key.isEmpty, !all.contains(key) else { return }
        all.append(key)
        notices = all
    }

    /// 合併匯入：說明過的、知道了的、這筆不算的取聯集；帳戶、卡、保單、金額歷史、改卡歷史本機有的留本機的，本機沒有的帶進來
    func merged(with other: WealthBook) -> WealthBook {
        var out = self
        for k in other.notices ?? [] { out.addNotice(k) }
        var d = out.dismissed ?? []
        for k in other.dismissed ?? [] where !d.contains(k) { d.append(k) }
        out.dismissed = d.isEmpty ? nil : d
        var a = out.accounts ?? [:]
        for (k, v) in other.accounts ?? [:] where a[k] == nil { a[k] = v }
        out.accounts = a.isEmpty ? nil : a
        var c = out.cards ?? [:]
        for (k, v) in other.cards ?? [:] where c[k] == nil { c[k] = v }
        out.cards = c.isEmpty ? nil : c
        var p = out.policies ?? [:]
        for (k, v) in other.policies ?? [:] where p[k] == nil { p[k] = v }
        out.policies = p.isEmpty ? nil : p
        var ih = out.incomeHistory ?? [:]
        for (k, v) in other.incomeHistory ?? [:] where ih[k] == nil { ih[k] = v }
        out.incomeHistory = ih.isEmpty ? nil : ih
        var lf = out.linkFrom ?? [:]
        for (k, v) in other.linkFrom ?? [:] where lf[k] == nil { lf[k] = v }
        out.linkFrom = lf.isEmpty ? nil : lf
        var ex = out.excludedExpenses ?? []
        for k in other.excludedExpenses ?? [] where !ex.contains(k) { ex.append(k) }
        out.excludedExpenses = ex.isEmpty ? nil : ex
        return out
    }
}

/// 一個銀行／證券帳戶的新欄位（judge §3.14；v2 只定好、照讀照存，畫面 v3 起）
struct WealthAccountPrefs: Codable, Equatable {
    /// 暱稱「薪轉」（卡片、選單、水塔牌子用）
    var nickname: String?
    /// 你排的順序（小的在前）
    var sortIndex: Int?
    /// 收起來（銷戶）：不算進合計、不出現在選單；歷史照算
    var hidden: Bool?
    /// 銷戶日
    var closedDate: Date?
    /// 算不算進存款合計（nil＝算；小孩的戶頭可以關掉）
    var countInCash: Bool?
    /// 用途（薪轉／扣款／存錢／外幣／零用），卡面小字用
    var purpose: String?
    /// 卡面顏色
    var colorId: Int?
    /// 帳號末 4 碼（v3 起新記的帳戶預設只存這個）
    var accountLast4: String?
    /// [v25.564] 完整帳號的密文（CardVault.seal；表單「存完整帳號」打開才有，待決定 7）。
    /// 明碼絕不寫進帳本或里程碑：帳本整包進 iCloud、備份、網頁版。看要 CardVault.unlock＋open
    var accountNumberCipher: Data?
    /// [v25.564] 新增帳戶時勾的幣別（台幣以外；沒有紀錄也列得出來，WealthFacts.currencies 會併進去）
    var currencies: [String]?
    /// [v25.564] 證券戶的交割銀行（沒填＝這個證券戶的股票最常用的交割帳戶，WealthFacts.Broker）
    var settlementBankId: UUID?

    init(nickname: String? = nil, sortIndex: Int? = nil, hidden: Bool? = nil, closedDate: Date? = nil,
         countInCash: Bool? = nil, purpose: String? = nil, colorId: Int? = nil, accountLast4: String? = nil,
         accountNumberCipher: Data? = nil, currencies: [String]? = nil, settlementBankId: UUID? = nil) {
        self.nickname = nickname
        self.sortIndex = sortIndex
        self.hidden = hidden
        self.closedDate = closedDate
        self.countInCash = countInCash
        self.purpose = purpose
        self.colorId = colorId
        self.accountLast4 = accountLast4
        self.accountNumberCipher = accountNumberCipher
        self.currencies = currencies
        self.settlementBankId = settlementBankId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nickname = try? c.decodeIfPresent(String.self, forKey: .nickname)
        sortIndex = try? c.decodeIfPresent(Int.self, forKey: .sortIndex)
        hidden = try? c.decodeIfPresent(Bool.self, forKey: .hidden)
        closedDate = try? c.decodeIfPresent(Date.self, forKey: .closedDate)
        countInCash = try? c.decodeIfPresent(Bool.self, forKey: .countInCash)
        purpose = try? c.decodeIfPresent(String.self, forKey: .purpose)
        colorId = try? c.decodeIfPresent(Int.self, forKey: .colorId)
        accountLast4 = try? c.decodeIfPresent(String.self, forKey: .accountLast4)
        accountNumberCipher = try? c.decodeIfPresent(Data.self, forKey: .accountNumberCipher)
        currencies = try? c.decodeIfPresent([String].self, forKey: .currencies)
        settlementBankId = try? c.decodeIfPresent(UUID.self, forKey: .settlementBankId)
    }

    private enum CodingKeys: String, CodingKey {
        case nickname, sortIndex, hidden, closedDate, countInCash, purpose, colorId, accountLast4
        case accountNumberCipher, currencies, settlementBankId
    }

    var isEmpty: Bool {
        nickname == nil && sortIndex == nil && hidden == nil && closedDate == nil
            && countInCash == nil && purpose == nil && colorId == nil && accountLast4 == nil
            && accountNumberCipher == nil && (currencies ?? []).isEmpty && settlementBankId == nil
    }

    /// 暱稱（空白當沒有）
    var trimmedNickname: String? {
        guard let n = nickname?.trimmingCharacters(in: .whitespaces), !n.isEmpty else { return nil }
        return n
    }
}

/// 一張信用卡的新欄位（judge §3.14）。v2 只用 payFrom；其他照讀照存（v3 起）
struct WealthCardPrefs: Codable, Equatable {
    /// 卡費怎麼繳：autoFull（自動扣全額）／autoMin／manual（自己繳）／askEachTime。
    /// v2 一律當 autoFull（judge §8 v2：所有連了銀行的卡先當自動扣全額，「自己繳」在 v3）
    var payMode: String?
    /// 扣款帳戶的歷史（D10：改扣款帳戶問從哪一期起，以前的帳單照舊從原本的帳戶扣）。
    /// 照 fromKey 由小到大；最後一段一律以卡現在的 linkedBankMilestoneId 為準（還沒更新的 iPad 改了扣款帳戶也跟得上）。
    /// nil 或空＝整張卡一直是現在這個帳戶（舊資料，跟以前一樣）
    var payFrom: [WealthPayFrom]?
    /// 從這天起才追已繳（v3：改版前的帳單一律當作繳了）
    var trackFrom: Date?
    /// 每一期帳單的註記（key＝帳單 key「2026-10」；v3：標成已繳、帳單金額不一樣）
    var statements: [String: WealthStatementNote]?
    /// 卡面顏色 0–5（v3）
    var faceColor: Int?
    /// 免年費條件（v3）
    var feeRule: String?
    /// 回饋小抄（v3，一段字，App 不估回饋）
    var perksNote: String?
    /// 提醒（v4）
    var remind: Bool?
    /// [v25.564] 免年費：一年刷滿 N 元（只認這兩種，judge §3.13 C-7；兩個都填以元為準）
    var feeWaiveAmount: Double?
    /// [v25.564] 免年費：一年刷滿 N 筆
    var feeWaiveCount: Int?
    /// [v25.564] 卡片年度從幾月起（1–12；nil＝日曆年 1/1–12/31）
    var feeYearStartMonth: Int?
    /// [v25.564] 長按〔算到下一期〕的刷卡（WealthCardEntry.id「cc-<支出>」「cc-<支出>-<k>」）：銀行入帳晚了、這一筆算下一期
    var nextPeriodEntries: [String]?

    init(payMode: String? = nil, payFrom: [WealthPayFrom]? = nil, trackFrom: Date? = nil,
         statements: [String: WealthStatementNote]? = nil, faceColor: Int? = nil, feeRule: String? = nil,
         perksNote: String? = nil, remind: Bool? = nil,
         feeWaiveAmount: Double? = nil, feeWaiveCount: Int? = nil, feeYearStartMonth: Int? = nil,
         nextPeriodEntries: [String]? = nil) {
        self.payMode = payMode
        self.payFrom = payFrom
        self.trackFrom = trackFrom
        self.statements = statements
        self.faceColor = faceColor
        self.feeRule = feeRule
        self.perksNote = perksNote
        self.remind = remind
        self.feeWaiveAmount = feeWaiveAmount
        self.feeWaiveCount = feeWaiveCount
        self.feeYearStartMonth = feeYearStartMonth
        self.nextPeriodEntries = nextPeriodEntries
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        payMode = try? c.decodeIfPresent(String.self, forKey: .payMode)
        payFrom = try? c.decodeIfPresent([WealthPayFrom].self, forKey: .payFrom)
        trackFrom = try? c.decodeIfPresent(Date.self, forKey: .trackFrom)
        statements = try? c.decodeIfPresent([String: WealthStatementNote].self, forKey: .statements)
        faceColor = try? c.decodeIfPresent(Int.self, forKey: .faceColor)
        feeRule = try? c.decodeIfPresent(String.self, forKey: .feeRule)
        perksNote = try? c.decodeIfPresent(String.self, forKey: .perksNote)
        remind = try? c.decodeIfPresent(Bool.self, forKey: .remind)
        feeWaiveAmount = try? c.decodeIfPresent(Double.self, forKey: .feeWaiveAmount)
        feeWaiveCount = try? c.decodeIfPresent(Int.self, forKey: .feeWaiveCount)
        feeYearStartMonth = try? c.decodeIfPresent(Int.self, forKey: .feeYearStartMonth)
        nextPeriodEntries = try? c.decodeIfPresent([String].self, forKey: .nextPeriodEntries)
    }

    private enum CodingKeys: String, CodingKey {
        case payMode, payFrom, trackFrom, statements, faceColor, feeRule, perksNote, remind
        case feeWaiveAmount, feeWaiveCount, feeYearStartMonth, nextPeriodEntries
    }

    var isEmpty: Bool {
        payMode == nil && (payFrom ?? []).isEmpty && trackFrom == nil && (statements ?? [:]).isEmpty
            && faceColor == nil && feeRule == nil && perksNote == nil && remind == nil
            && feeWaiveAmount == nil && feeWaiveCount == nil && feeYearStartMonth == nil
            && (nextPeriodEntries ?? []).isEmpty
    }

    /// [v25.564] 卡費怎麼繳（沒設＝自動扣全額，跟 v2 一樣）
    var mode: WealthPayMode { WealthPayMode.of(payMode) }

    /// [v25.564] 改卡費怎麼繳：改成「自動扣最低」「自己繳」或「每次問我」時，從今天起才追（改版前、改之前的帳單一律當作繳了，
    /// judge §3.13 C-4；不會一打開跳出幾十張「繳了嗎」）。trackFrom 已經有就不動。
    /// 自動扣最低也要設：不然改的那天以前每一期都會重算成「只扣 10%、剩下的滾到下一期」，存摺上、還沒出帳整個變掉
    ///（驗證 build/v3/verify/data_edges.py G）
    mutating func setMode(_ m: WealthPayMode, now: Date) {
        payMode = m == .autoFull ? nil : m.rawValue
        if m != .autoFull && trackFrom == nil {
            trackFrom = WealthCal.day(now)
        }
    }
}

/// [v25.564] 卡費怎麼繳（judge §5.2；帳本存 rawValue 字串，舊版讀不懂也只是 nil＝自動扣全額）
enum WealthPayMode: String, CaseIterable, Identifiable {
    case autoFull, autoMin, manual, askEachTime

    var id: String { rawValue }

    static func of(_ raw: String?) -> WealthPayMode {
        guard let raw, let m = WealthPayMode(rawValue: raw) else { return .autoFull }
        return m
    }

    /// 表單的四顆、卡片資料那一列
    var title: String {
        switch self {
        case .autoFull: return "自動扣全額"
        case .autoMin: return "自動扣最低"
        case .manual: return "自己繳"
        case .askEachTime: return "每次問我"
        }
    }

    var isAuto: Bool { self == .autoFull || self == .autoMin }
}

/// 扣款帳戶的一段：從 fromKey 那一期起從 accountId 扣
struct WealthPayFrom: Codable, Equatable {
    /// 帳單 key「2026-11」（結帳日在那個月的那一期）；""＝最早那一期起
    var fromKey: String
    /// 從哪個帳戶扣（nil＝沒設）
    var accountId: UUID?

    init(fromKey: String, accountId: UUID?) {
        self.fromKey = fromKey
        self.accountId = accountId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fromKey = (try? c.decodeIfPresent(String.self, forKey: .fromKey)) ?? ""
        accountId = try? c.decodeIfPresent(UUID.self, forKey: .accountId)
    }

    private enum CodingKeys: String, CodingKey {
        case fromKey, accountId
    }
}

/// 一期帳單的註記（v3：標成已繳、帳單金額不一樣）
struct WealthStatementNote: Codable, Equatable {
    /// 帳單上寫的金額（你輸入的；App 算的不一樣時以它為準）。judge 叫它 override；
    /// override 是 Swift 的關鍵字（宣告修飾詞），當名字容易出事，所以叫 statedAmount
    var statedAmount: Double?
    /// 標成已繳的日子
    var paidDate: Date?
    /// 從哪個帳戶繳（nil＝別的方式：現金、超商）
    var paidAccount: UUID?
    /// 繳了多少（nil＝全額）
    var paidAmount: Double?
    /// [v25.564] 你說「還沒繳」（要確認 #2〔不是〕、#3〔還沒〕）：過了截止日也不當作已繳，變成逾期
    var notPaid: Bool?

    init(statedAmount: Double? = nil, paidDate: Date? = nil, paidAccount: UUID? = nil, paidAmount: Double? = nil,
         notPaid: Bool? = nil) {
        self.statedAmount = statedAmount
        self.paidDate = paidDate
        self.paidAccount = paidAccount
        self.paidAmount = paidAmount
        self.notPaid = notPaid
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        statedAmount = try? c.decodeIfPresent(Double.self, forKey: .statedAmount)
        paidDate = try? c.decodeIfPresent(Date.self, forKey: .paidDate)
        paidAccount = try? c.decodeIfPresent(UUID.self, forKey: .paidAccount)
        paidAmount = try? c.decodeIfPresent(Double.self, forKey: .paidAmount)
        notPaid = try? c.decodeIfPresent(Bool.self, forKey: .notPaid)
    }

    private enum CodingKeys: String, CodingKey {
        case statedAmount, paidDate, paidAccount, paidAmount
        case notPaid
    }

    var isEmpty: Bool {
        statedAmount == nil && paidDate == nil && paidAccount == nil && paidAmount == nil && notPaid == nil
    }
}

/// [v25.564] 一張保單的新欄位（judge §3.14、§5.4；v3 先存繳法、繳費年期、險種、誰的保單，v6 連記帳的保費）
struct WealthPolicyPrefs: Codable, Equatable {
    /// 險種：medical／accident／cancer／disability／life／travel／other（WealthPolicyKind.rawValue）。
    /// 里程碑的 insuranceType 照寫最接近的舊值（癌症→醫療），給舊 iPad、醫療地圖
    var coverageKind: String?
    /// 被保險人、要保人（本人或家人的名字）
    var insured: String?
    var policyholder: String?
    /// 繳法：year／half／quarter／month／single（WealthPolicyCycle.rawValue）
    var payCycle: String?
    /// 繳費年期（年；躉繳 nil）
    var payYears: Int?
    /// 保障到：「終身」「2045」「75 歲」（字，照你填的寫）
    var coverageUntil: String?
    /// 保障內容（你自己寫的幾列：「住院日額 2,000／天」）
    var coverageItems: [String]?
    /// 下次扣款日
    var nextDue: Date?
    /// 從哪扣（銀行帳戶或信用卡的 id；v3 先存，v6 寫進記帳那筆）
    var payFromId: UUID?
    /// 連到的記帳保費（v6）
    var linkedExpenseId: UUID?

    init(coverageKind: String? = nil, insured: String? = nil, policyholder: String? = nil, payCycle: String? = nil,
         payYears: Int? = nil, coverageUntil: String? = nil, coverageItems: [String]? = nil, nextDue: Date? = nil,
         payFromId: UUID? = nil, linkedExpenseId: UUID? = nil) {
        self.coverageKind = coverageKind
        self.insured = insured
        self.policyholder = policyholder
        self.payCycle = payCycle
        self.payYears = payYears
        self.coverageUntil = coverageUntil
        self.coverageItems = coverageItems
        self.nextDue = nextDue
        self.payFromId = payFromId
        self.linkedExpenseId = linkedExpenseId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        coverageKind = try? c.decodeIfPresent(String.self, forKey: .coverageKind)
        insured = try? c.decodeIfPresent(String.self, forKey: .insured)
        policyholder = try? c.decodeIfPresent(String.self, forKey: .policyholder)
        payCycle = try? c.decodeIfPresent(String.self, forKey: .payCycle)
        payYears = try? c.decodeIfPresent(Int.self, forKey: .payYears)
        coverageUntil = try? c.decodeIfPresent(String.self, forKey: .coverageUntil)
        coverageItems = try? c.decodeIfPresent([String].self, forKey: .coverageItems)
        nextDue = try? c.decodeIfPresent(Date.self, forKey: .nextDue)
        payFromId = try? c.decodeIfPresent(UUID.self, forKey: .payFromId)
        linkedExpenseId = try? c.decodeIfPresent(UUID.self, forKey: .linkedExpenseId)
    }

    private enum CodingKeys: String, CodingKey {
        case coverageKind, insured, policyholder, payCycle, payYears, coverageUntil, coverageItems, nextDue
        case payFromId, linkedExpenseId
    }

    var isEmpty: Bool {
        coverageKind == nil && insured == nil && policyholder == nil && payCycle == nil && payYears == nil
            && coverageUntil == nil && (coverageItems ?? []).isEmpty && nextDue == nil && payFromId == nil
            && linkedExpenseId == nil
    }

    var kind: WealthPolicyKind? { coverageKind.flatMap { WealthPolicyKind(rawValue: $0) } }
    var cycle: WealthPolicyCycle? { payCycle.flatMap { WealthPolicyCycle(rawValue: $0) } }
}

/// [v25.564] 保單險種（judge §5.4 先選險種；儲蓄險、車險、房屋險不在這裡記，表單導去理財、車子卡、房屋卡）
enum WealthPolicyKind: String, CaseIterable, Identifiable {
    case medical, accident, cancer, disability, life, travel, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .medical: return "醫療（含實支實付、住院日額）"
        case .accident: return "意外"
        case .cancer: return "癌症／重大疾病"
        case .disability: return "失能／長照"
        case .life: return "壽險"
        case .travel: return "旅平"
        case .other: return "其他"
        }
    }

    /// 短名（項目卡、看板）
    var shortTitle: String {
        switch self {
        case .medical: return "醫療險"
        case .accident: return "意外險"
        case .cancer: return "癌症險"
        case .disability: return "失能險"
        case .life: return "壽險"
        case .travel: return "旅平險"
        case .other: return "保單"
        }
    }

    /// 寫回里程碑的舊險種（給舊 iPad、網頁版、醫療地圖；InsuranceType 不加新 case）
    var legacyType: InsuranceType {
        switch self {
        case .medical, .cancer, .disability: return .health
        case .accident: return .accident
        case .life, .other: return .life
        case .travel: return .travel
        }
    }

    /// 舊資料只有 insuranceType：照它推一個（車險推 other，表單照留照顯示）
    static func from(legacy t: InsuranceType?) -> WealthPolicyKind {
        switch t {
        case .health?: return .medical
        case .accident?: return .accident
        case .travel?: return .travel
        case .life?: return .life
        case .car?, nil: return .other
        }
    }
}

/// [v25.564] 保費繳法
enum WealthPolicyCycle: String, CaseIterable, Identifiable {
    case year, half, quarter, month, single

    var id: String { rawValue }

    var title: String {
        switch self {
        case .year: return "年繳"
        case .half: return "半年繳"
        case .quarter: return "季繳"
        case .month: return "月繳"
        case .single: return "躉繳"
        }
    }

    /// 一年繳幾次（躉繳 0）
    var timesPerYear: Int {
        switch self {
        case .year: return 1
        case .half: return 2
        case .quarter: return 4
        case .month: return 12
        case .single: return 0
        }
    }
}
