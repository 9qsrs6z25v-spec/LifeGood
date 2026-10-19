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

struct WealthBook: Codable, Equatable {
    /// 每個銀行／證券帳戶的設定（key＝帳戶那筆 LifeMilestone 的 id.uuidString）
    var accounts: [String: WealthAccountPrefs]?
    /// 每張信用卡的設定（key＝卡那筆 LifeMilestone 的 id.uuidString）
    var cards: [String: WealthCardPrefs]?
    /// 要確認按過「知道了」的 key（v3 起）
    var dismissed: [String]?
    /// 說明過一次的事（WealthBook.passbookNoticeKey＝v2「為什麼數字變了」）；跟 iCloud 同步，換一台不會再說一次
    var notices: [String]?

    /// [v25.563] 「銀行的數字改成跟存摺一樣」那段說明的 key
    static let passbookNoticeKey = "v2-passbook"

    init(accounts: [String: WealthAccountPrefs]? = nil, cards: [String: WealthCardPrefs]? = nil,
         dismissed: [String]? = nil, notices: [String]? = nil) {
        self.accounts = accounts
        self.cards = cards
        self.dismissed = dismissed
        self.notices = notices
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try? c.decodeIfPresent([String: WealthAccountPrefs].self, forKey: .accounts)
        cards = try? c.decodeIfPresent([String: WealthCardPrefs].self, forKey: .cards)
        dismissed = try? c.decodeIfPresent([String].self, forKey: .dismissed)
        notices = try? c.decodeIfPresent([String].self, forKey: .notices)
    }

    private enum CodingKeys: String, CodingKey {
        case accounts, cards, dismissed, notices
    }

    var isEmpty: Bool {
        (accounts ?? [:]).isEmpty && (cards ?? [:]).isEmpty
            && (dismissed ?? []).isEmpty && (notices ?? []).isEmpty
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
    }

    func hasNotice(_ key: String) -> Bool { (notices ?? []).contains(key) }

    mutating func addNotice(_ key: String) {
        var all = notices ?? []
        guard !key.isEmpty, !all.contains(key) else { return }
        all.append(key)
        notices = all
    }

    /// 合併匯入：說明過的、知道了的取聯集；帳戶、卡的設定本機有的留本機的，本機沒有的帶進來
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

    init(nickname: String? = nil, sortIndex: Int? = nil, hidden: Bool? = nil, closedDate: Date? = nil,
         countInCash: Bool? = nil, purpose: String? = nil, colorId: Int? = nil, accountLast4: String? = nil) {
        self.nickname = nickname
        self.sortIndex = sortIndex
        self.hidden = hidden
        self.closedDate = closedDate
        self.countInCash = countInCash
        self.purpose = purpose
        self.colorId = colorId
        self.accountLast4 = accountLast4
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
    }

    private enum CodingKeys: String, CodingKey {
        case nickname, sortIndex, hidden, closedDate, countInCash, purpose, colorId, accountLast4
    }

    var isEmpty: Bool {
        nickname == nil && sortIndex == nil && hidden == nil && closedDate == nil
            && countInCash == nil && purpose == nil && colorId == nil && accountLast4 == nil
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

    init(payMode: String? = nil, payFrom: [WealthPayFrom]? = nil, trackFrom: Date? = nil,
         statements: [String: WealthStatementNote]? = nil, faceColor: Int? = nil, feeRule: String? = nil,
         perksNote: String? = nil, remind: Bool? = nil) {
        self.payMode = payMode
        self.payFrom = payFrom
        self.trackFrom = trackFrom
        self.statements = statements
        self.faceColor = faceColor
        self.feeRule = feeRule
        self.perksNote = perksNote
        self.remind = remind
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
    }

    private enum CodingKeys: String, CodingKey {
        case payMode, payFrom, trackFrom, statements, faceColor, feeRule, perksNote, remind
    }

    var isEmpty: Bool {
        payMode == nil && (payFrom ?? []).isEmpty && trackFrom == nil && (statements ?? [:]).isEmpty
            && faceColor == nil && feeRule == nil && perksNote == nil && remind == nil
    }
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

    init(statedAmount: Double? = nil, paidDate: Date? = nil, paidAccount: UUID? = nil, paidAmount: Double? = nil) {
        self.statedAmount = statedAmount
        self.paidDate = paidDate
        self.paidAccount = paidAccount
        self.paidAmount = paidAmount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        statedAmount = try? c.decodeIfPresent(Double.self, forKey: .statedAmount)
        paidDate = try? c.decodeIfPresent(Date.self, forKey: .paidDate)
        paidAccount = try? c.decodeIfPresent(UUID.self, forKey: .paidAccount)
        paidAmount = try? c.decodeIfPresent(Double.self, forKey: .paidAmount)
    }

    private enum CodingKeys: String, CodingKey {
        case statedAmount, paidDate, paidAccount, paidAmount
    }
}
