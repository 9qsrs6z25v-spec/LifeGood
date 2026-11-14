import Foundation

// MARK: - Apple Pay 自動記帳（v25.608 wallet）
//
// 只屬於「LifeGood」target。規格：scratchpad/radar/judge_wallet.md §C；分工：scratchpad/radar/build/wallet/brief.md。
//
// 捷徑 App 的「交易」自動化（用 Apple Pay 付款那一刻觸發）→ LifeGood 的捷徑動作「記一筆支出」
// （WalletRecordIntent：在 App 的行程裡跑、不打開 App）→ 這裡的 WalletIntake.record：
//   1. 金額字（parseAmount：「NT$65」「$12.50」「1,280」）；看不懂＝不記、回失敗字
//   2. 幣別（resolveMoney）：寫明的幣別 > 這張卡設定的「沒寫幣別時當作」 > 台幣；
//      外幣照記帳表單：台幣金額＝原幣 × 設定裡的匯率（AddExpenseView 的 rawAmount * currencyMultiplier），currencyCode＝設定裡那個幣別的寫法
//   3. 防重（isDuplicate）：同商家＋同金額＋同一張卡 90 秒內第二次不記（回覆照樣「已記一筆」）
//   4. 寫一筆進一按就記的收件匣（QuickRecordInbox，source "wallet"）；App 正開著（QuickRecordImporter.isReady）就當場只收 wallet 的
//   5. QuickRecordImporter 入帳時叫 WalletImport.makeExpense：變動支出、分類照同商家上一次、連卡片（這台的對應表）
//
// 這台記住（App Group 的 UserDefaults；不跟 iCloud、不進備份、不是同步鍵）：
//   wallet_card_links（捷徑給的卡片名稱 → 信用卡／銀行帳戶）、wallet_recent_ids（最近自動記的）、wallet_missed（沒記到的）
// 隱私：不存卡號（捷徑本來就不給，只有卡片名稱）；不發通知；捷徑回覆只有「已記一筆」／「沒有記到，打開 LifeGood 看看」。
// 不連網：解析、對應全部在本機。
//
// [learn] v25.611（radar/judge_learn.md §C1～C3；radar/build/learn/brief.md）：從你的修改學——
//   • C3 分類：先找「同一個錢包原始店名」的自動記帳（WalletRecentItem.merchant；舊的從防重指紋拆）那一筆**現在的**分類，
//     找不到才退回 25.608 的 lastCategory（名稱一樣的最新一筆）。改了店名（7-ELEVEN → 小七）也對得到
//   • C2 同行人員：同一家店最近一筆有同行人員的那一筆的 diningMember；只帶進有同行人員欄位的分類
//     （memberCategories＝AddExpenseView.memberCategories），設定頁開關「同行人員照上一次」（WalletPrefs，出廠開）
//   • C1 卡片：在支出編輯頁（AddExpenseView 編輯存檔，掛鉤點）把自動記的那一筆改連別的卡／帳戶 → WalletLearn 把那張卡的對應
//     設成新帳戶；改成不連不學。以前沒連的不自動改，設定頁那張卡寫「還有 N 筆沒連〔一起連〕」（unlinkedCounts）
//   新存的只有 App Group 一個鍵 wallet_member_from_last（這台的開關，不是同步鍵）；Expense 不加欄位

// MARK: - 純資料

/// 金額字解析的結果
struct WalletParsedAmount: Equatable {
    /// 數字（> 0，四捨五入到 0.01）
    var value: Double
    /// 寫明的幣別（ISO：「TWD」「USD」「JPY」）；nil＝沒寫幣別或只寫「$」
    var iso: String?
    /// 只寫「$」（沒寫 NT$／US$）
    var bareDollar: Bool
}

/// 金額 → 要存的台幣
enum WalletMoney: Equatable {
    /// 台幣
    case twd(amount: Double)
    /// 外幣：amount 是台幣（原幣 × 匯率），code 是設定裡那個幣別的寫法（「美金」）
    case foreign(amount: Double, code: String, original: Double, rate: Double)
    /// 外幣，但設定裡沒有這個幣別的匯率：不記
    case noRate(iso: String, original: Double)
}

/// 卡片對到哪一種帳戶
enum WalletLinkTarget: String, Codable, Equatable {
    /// 財富裡的信用卡
    case card
    /// 財富裡的銀行帳戶（金融卡、簽帳卡）
    case bank
    /// 使用者選了〔不連帳戶〕（存的字是 "none"）
    case noAccount = "none"
}

/// 自動對應、〔選一張〕的候選（財富裡的一張信用卡或一個銀行帳戶）
struct WalletLinkCandidate: Equatable, Identifiable {
    var id: UUID
    var kind: WalletLinkTarget
    /// 畫面上寫的名字（信用卡：卡名，沒有用標題；銀行：銀行名，沒有用標題）
    var display: String
    /// 拿來比對的名字（卡名／銀行名、標題）
    var names: [String]
    /// 信用卡末四碼（捷徑給的卡片名稱裡有這四個數字＝優先對到它）
    var lastFour: String?
}

/// 這台記住的一張卡（捷徑給的卡片名稱 → 帳戶）
struct WalletCardLink: Codable, Equatable, Identifiable {
    /// WalletAutoRecord.cardKey（去空白、去「卡」字、小寫）
    var key: String
    /// 捷徑最近一次給的卡片名稱原字
    var name: String
    /// WalletLinkTarget.rawValue；nil＝還沒對應
    var target: String?
    /// 對到的 LifeMilestone.id（target 是 card／bank 才有）
    var milestoneId: UUID?
    /// 是自動對到的（不是使用者選的）
    var auto: Bool
    /// 這張卡的金額沒寫幣別、只寫「$」時當作哪個幣別（設定裡幣別的寫法，例「美金」）；nil＝台幣
    var dollarCode: String?
    /// 最近一次用這張卡自動記的時間
    var lastSeen: Date

    var id: String { key }
    var linkTarget: WalletLinkTarget? { target.flatMap { WalletLinkTarget(rawValue: $0) } }
    /// 對應好了（連信用卡、連銀行帳戶、〔不連帳戶〕都算）
    var isDecided: Bool { linkTarget != nil }
}

/// 最近自動記的一筆（id＝收件匣 id＝Expense id）
struct WalletRecentItem: Codable, Equatable, Identifiable {
    var id: UUID
    var at: Date
    /// WalletAutoRecord.cardKey；沒給卡片＝""
    var cardKey: String
    /// 捷徑給的卡片名稱原字；沒給＝""
    var cardName: String
    /// 防重用（WalletAutoRecord.fingerprint）
    var fingerprint: String
    /// [learn] 捷徑給的原始商家（cleanMerchant 之後）。v25.611 起才存；舊的沒有＝nil（解得開：Optional 照 decodeIfPresent）
    var merchant: String? = nil

    /// [learn] 比對同一家店用：有存原始商家用它（titleKey），舊的從防重指紋拆（WalletAutoRecord.merchantKey(fromFingerprint:)）
    var merchantKey: String {
        if let m = merchant { return WalletAutoRecord.titleKey(m) }
        return WalletAutoRecord.merchantKey(fromFingerprint: fingerprint)
    }
}

/// 沒記到的一筆（設定頁「沒記到的」）
struct WalletMissedItem: Codable, Equatable, Identifiable {
    var id: UUID
    var at: Date
    /// 捷徑給的金額原字（最多 60 字）
    var amountText: String
    /// 為什麼沒記（WalletAutoRecord.reason…）
    var reason: String
}

/// 入帳時要連的帳戶（照 AIExpenseCommitter：信用卡＋它的扣款銀行；或直接扣銀行）
struct WalletAccountLink: Equatable {
    var cardId: UUID?
    var bankId: UUID?
    var bankCurrency: String?
}

/// [learn] 同一家店上一次的分類與同行人員（WalletAutoRecord.shopMemory）
struct WalletShopMemory: Equatable {
    var category: VariableCategory
    /// 同一家店最近一筆**有同行人員**的那一筆的同行人員（去頭尾空白）；沒有＝nil。要不要帶進去看 carriedMember
    var member: String?
    /// 分類是從「同一個錢包原始店名的自動記帳」找到的（false＝照名稱一樣的 25.608 規則，或找不到＝其他）
    var fromWallet: Bool
}

/// [learn] 一筆支出連的帳戶（WalletLearn.account(of:)）
struct WalletLearnedLink: Equatable {
    var target: WalletLinkTarget
    var milestoneId: UUID
}

// MARK: - 純函式（sim_wallet.py 一支一支對照）

enum WalletAutoRecord {
    /// 同商家＋同金額＋同一張卡這麼多秒內第二次不記
    static let dedupeWindow: TimeInterval = 90
    /// 商家是空的時候的名稱
    static let defaultMerchant = "Apple Pay"
    /// 捷徑回覆（不帶金額、商家、卡名）
    static let recordedReply = "已記一筆"
    static let failedReply = "沒有記到，打開 LifeGood 看看"
    /// 存的台幣上限（同手錶 WatchVoiceRule.maxTWD）
    static let maxTWD: Double = 9_999_999
    /// 解析前的數字上限（再大當看不懂，免得換成分的時候溢位）
    static let maxParsedValue: Double = 1_000_000_000
    /// 商家、卡名、金額字最多留幾個字
    static let maxTextLength = 60
    /// 記帳設定的匯率表（ExpenseStore.currencyRatesKey；App 存在 UserDefaults.standard）
    static let ratesKey = "lifegood_currency_rates"

    // 沒記到的原因（設定頁「沒記到的」）
    static let reasonUnreadable = "金額看不懂"
    static let reasonTooLarge = "金額太大"
    static let reasonWriteFailed = "存不進待入帳"
    static func reasonNoRate(_ iso: String) -> String { "設定裡沒有 \(iso) 的匯率" }

    static func reply(recorded: Bool) -> String { recorded ? recordedReply : failedReply }

    /// 幣別符號、代碼 → ISO（比對前已經轉大寫）
    private static let markers: [String: String] = [
        "NT$": "TWD", "NT": "TWD", "NTD": "TWD", "TWD": "TWD", "台幣": "TWD", "臺幣": "TWD", "新台幣": "TWD", "新臺幣": "TWD",
        "元": "TWD", "圓": "TWD",
        "US$": "USD", "US": "USD", "USD": "USD", "美金": "USD", "美元": "USD",
        "¥": "JPY", "JP¥": "JPY", "JPY": "JPY", "円": "JPY", "日圓": "JPY", "日幣": "JPY", "日元": "JPY",
        "CN¥": "CNY", "RMB": "CNY", "CNY": "CNY", "人民幣": "CNY",
        "€": "EUR", "EUR": "EUR", "£": "GBP", "GBP": "GBP", "₩": "KRW", "KRW": "KRW",
        "HK$": "HKD", "HKD": "HKD", "S$": "SGD", "SGD": "SGD", "A$": "AUD", "AUD": "AUD", "C$": "CAD", "CAD": "CAD",
        "฿": "THB", "THB": "THB", "₫": "VND", "VND": "VND", "₱": "PHP", "PHP": "PHP",
        "MOP$": "MOP", "MOP": "MOP", "RM": "MYR", "MYR": "MYR"
    ]

    /// 空白（含不換行空白）一律換成一個半形空白（parseAmount 拿它當數字的分段，不算幣別字）、全形數字與符號轉半形
    static func normalizedAmountText(_ raw: String) -> String {
        var out = ""
        for scalar in raw.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                out.append(" ")
                continue
            }
            let v = scalar.value
            if v >= 0xFF10, v <= 0xFF19, let ascii = Unicode.Scalar(v - 0xFF10 + 0x30) {
                out.unicodeScalars.append(ascii)
                continue
            }
            switch scalar {
            case "＄": out.append("$")
            case "，": out.append(",")
            case "．": out.append(".")
            case "￥": out.append("¥")
            case "－": out.append("-")
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    /// 數字那一段 → 數字（千分位要三個一組；小數點最多一個；> 0；四捨五入到 0.01）。看不懂回 nil
    static func numberValue(_ raw: String) -> Double? {
        var t = raw
        while t.hasSuffix(".") || t.hasSuffix(",") {
            t.removeLast()
        }
        let parts = t.components(separatedBy: ".")
        guard parts.count <= 2 else { return nil }
        let groups = parts[0].components(separatedBy: ",")
        if groups.count > 1 {
            guard (1...3).contains(groups[0].count),
                  groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
        }
        let digits = groups.joined()
        guard !digits.isEmpty else { return nil }
        var plain = digits
        if parts.count == 2 {
            guard !parts[1].isEmpty, !parts[1].contains(",") else { return nil }
            plain += "." + parts[1]
        }
        guard var d = Decimal(string: plain, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &d, 2, .plain)
        let v = NSDecimalNumber(decimal: rounded).doubleValue
        guard v.isFinite, v > 0, v < maxParsedValue else { return nil }
        return v
    }

    /// 數字以外的字 → 幣別。空的＝沒寫；「$」＝只寫錢號；認不得的字回 nil（整筆當看不懂）。
    /// 先整段比（「日圓」「美元」「港元」「韓元」本身就是幣別），比不到才拿掉尾巴多的一個「元／圓」再比
    /// （「新台幣65元」「NT$65元」）——先拿掉的話「日圓」會變成「日」，反而看不懂
    static func currencyMarker(_ raw: String) -> (iso: String?, bareDollar: Bool)? {
        let m = raw.uppercased()
        if let hit = markerLookup(m) { return hit }
        guard m.count > 1, m.hasSuffix("元") || m.hasSuffix("圓") else { return nil }
        return markerLookup(String(m.dropLast()))
    }

    /// currencyMarker 的一次比對（m 已經轉大寫）
    private static func markerLookup(_ m: String) -> (iso: String?, bareDollar: Bool)? {
        if m.isEmpty { return (iso: nil, bareDollar: false) }
        if m == "$" { return (iso: nil, bareDollar: true) }
        if let iso = markers[m] { return (iso: iso, bareDollar: false) }
        let isThreeLetters = m.count == 3 && m.allSatisfy { $0 >= "A" && $0 <= "Z" }
        if isThreeLetters, !m.hasPrefix("XA") { return (iso: m, bareDollar: false) }
        if let iso = FXRateService.isoCode(for: m), iso.count == 3, !iso.hasPrefix("XA") {
            return (iso: iso, bareDollar: false)
        }
        return nil
    }

    /// 捷徑給的金額字 →（數字、幣別）。只准一段數字（空白也會切段）；有負號（退款）、認不得的字、0 都回 nil
    static func parseAmount(_ raw: String) -> WalletParsedAmount? {
        let text = normalizedAmountText(raw).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.count <= maxTextLength else { return nil }
        if text.contains("-") || text.contains("−") { return nil }
        var number = ""
        var marker = ""
        var runs = 0
        var inRun = false
        for ch in text {
            if ch == " " {
                // 空白把數字切開（「65 70」是兩段＝看不懂），本身不算幣別字（「NT$ 65」照樣是台幣）
                inRun = false
                continue
            }
            let isDigit = ch >= "0" && ch <= "9"
            if isDigit || (inRun && (ch == "," || ch == ".")) {
                if !inRun {
                    runs += 1
                    inRun = true
                }
                number.append(ch)
            } else {
                inRun = false
                marker.append(ch)
            }
        }
        guard runs == 1, let value = numberValue(number), let cur = currencyMarker(marker) else { return nil }
        return WalletParsedAmount(value: value, iso: cur.iso, bareDollar: cur.bareDollar)
    }

    /// 設定裡對到這個 ISO 的那一個幣別（「美金」「USD」都算；匯率要是正的；排前面的優先）
    static func rateEntry(iso: String, rates: [CurrencyRate]) -> CurrencyRate? {
        rates.first { r in
            guard r.rate > 0, r.rate.isFinite else { return false }
            return FXRateService.isoCode(for: r.code) == iso || r.code.uppercased() == iso
        }
    }

    /// 幣別規則：寫明的幣別 > 這張卡的「沒寫幣別時當作」（cardCurrency，設定裡幣別的寫法） > 台幣
    static func resolveMoney(_ p: WalletParsedAmount, cardCurrency: String?,
                             rates: [CurrencyRate]) -> WalletMoney {
        if let iso = p.iso {
            if iso == "TWD" { return .twd(amount: p.value) }
            if let r = rateEntry(iso: iso, rates: rates) {
                return .foreign(amount: p.value * r.rate, code: r.code, original: p.value, rate: r.rate)
            }
            return .noRate(iso: iso, original: p.value)
        }
        let card = (cardCurrency ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if card.isEmpty || FinanceRates.isNTD(card) { return .twd(amount: p.value) }
        if let r = rates.first(where: { $0.code == card && $0.rate > 0 && $0.rate.isFinite }) {
            return .foreign(amount: p.value * r.rate, code: r.code, original: p.value, rate: r.rate)
        }
        return .noRate(iso: FXRateService.isoCode(for: card) ?? card, original: p.value)
    }

    /// 記帳設定的匯率表（App 存在 UserDefaults.standard；讀不到＝空的，外幣一律當沒有匯率）
    static func savedRates() -> [CurrencyRate] {
        guard let data = UserDefaults.standard.data(forKey: ratesKey),
              let list = try? JSONDecoder().decode([CurrencyRate].self, from: data) else { return [] }
        return list
    }

    // MARK: 商家、卡名

    /// 商家：去頭尾空白、最多 60 字；空的＝「Apple Pay」
    static func cleanMerchant(_ raw: String?) -> String {
        let t = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return defaultMerchant }
        return String(t.prefix(maxTextLength))
    }

    /// 卡名：去頭尾空白、最多 60 字；沒給＝""
    static func cleanCard(_ raw: String?) -> String {
        let t = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return String(t.prefix(maxTextLength))
    }

    /// 卡名拆成幾段（小寫；拿掉「信用卡」「金融卡」「簽帳卡」「卡」與 debit／credit／card；空白與標點當分隔）
    static func cardTokens(_ raw: String) -> [String] {
        var s = raw.lowercased()
        for word in ["簽帳金融卡", "信用卡", "金融卡", "簽帳卡", "debit", "credit", "card"] {
            s = s.replacingOccurrences(of: word, with: " ")
        }
        s = s.replacingOccurrences(of: "卡", with: " ")
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "-_・·/()（）[]【】,，.。|｜"))
        return s.components(separatedBy: separators).filter { !$0.isEmpty }
    }

    /// 這台對應表的鍵（cardTokens 接起來）。「國泰世華 CUBE 卡」→「國泰世華cube」
    static func cardKey(_ raw: String) -> String {
        cardTokens(raw).joined()
    }

    /// 捷徑給的卡名跟財富裡某個名字對不對得上：一樣、一邊包含另一邊、
    /// 或一邊的每一段都在另一邊裡（「國泰世華 CUBE 卡」對「國泰 CUBE」）。兩邊都要至少兩個字
    static func namesMatch(wallet: String, candidate: String) -> Bool {
        let a = cardKey(wallet)
        let b = cardKey(candidate)
        guard a.count >= 2, b.count >= 2 else { return false }
        if a == b || a.contains(b) || b.contains(a) { return true }
        let tb = cardTokens(candidate)
        if !tb.isEmpty, tb.allSatisfy({ a.contains($0) }) { return true }
        let ta = cardTokens(wallet)
        if !ta.isEmpty, ta.allSatisfy({ b.contains($0) }) { return true }
        return false
    }

    /// 第一次看到的卡自動對：末四碼只對到一張信用卡 → 它；名稱只對到一張信用卡 → 它；
    /// 信用卡一張都對不到、銀行帳戶只對到一個 → 它；其他（對不到、對到兩個以上）→ nil（設定頁「還沒對應的卡」）
    static func autoMatch(walletName: String, cards: [WalletLinkCandidate],
                          banks: [WalletLinkCandidate]) -> WalletLinkCandidate? {
        let byLastFour = cards.filter { c in
            guard let l = c.lastFour, l.count == 4 else { return false }
            return walletName.contains(l)
        }
        if byLastFour.count == 1 { return byLastFour[0] }
        let cardHits = cards.filter { c in c.names.contains { namesMatch(wallet: walletName, candidate: $0) } }
        if cardHits.count == 1 { return cardHits[0] }
        if cardHits.count > 1 { return nil }
        let bankHits = banks.filter { b in b.names.contains { namesMatch(wallet: walletName, candidate: $0) } }
        return bankHits.count == 1 ? bankHits[0] : nil
    }

    // MARK: 分類、防重

    /// 比對商家用：小寫、拿掉所有空白
    static func titleKey(_ raw: String) -> String {
        raw.lowercased().components(separatedBy: .whitespacesAndNewlines).joined()
    }

    /// 同一個商家上一次記的分類（變動支出、名稱一樣、日期最新的那一筆；同一天同時間取排前面的）。
    /// 找不到＝其他；上一次是股票、房地產（要連東西才有意義）也當其他
    static func lastCategory(for merchant: String, in ledger: [Expense]) -> VariableCategory {
        let key = titleKey(merchant)
        guard !key.isEmpty else { return .other }
        var best: Expense? = nil
        for e in ledger where e.expenseType == .variable && e.variableCategory != nil && titleKey(e.title) == key {
            if let b = best, e.date <= b.date { continue }
            best = e
        }
        guard let c = best?.variableCategory else { return .other }
        return (c == .stock || c == .realEstate) ? .other : c
    }

    /// 防重的指紋：商家（titleKey）｜金額（分）｜卡（cardKey）
    static func fingerprint(merchant: String, value: Double, cardKey: String) -> String {
        let cents = Int((value * 100).rounded())
        return titleKey(merchant) + "|" + String(cents) + "|" + cardKey
    }

    /// 90 秒內有同一個指紋＝重複（捷徑偶爾觸發兩次）
    static func isDuplicate(fingerprint: String, now: Date, recent: [WalletRecentItem]) -> Bool {
        recent.contains { $0.fingerprint == fingerprint && abs(now.timeIntervalSince($0.at)) < dedupeWindow }
    }

    // MARK: [learn] 同一家店上一次（C2、C3）

    /// 有「同行人員」欄位的分類（照 AddExpenseView.memberCategories——那邊是 private，抄一份；keycheck_learn 對照兩邊一樣）
    static let memberCategories: Set<VariableCategory> = [
        .food, .entertainment, .shopping, .dailyNecessities,
        .medical, .education, .social, .other
    ]

    /// 防重指紋（titleKey｜分｜cardKey）拆回商家那一段。cardKey 不會有「|」（cardTokens 拿它當分隔），
    /// 分是整數，所以拿掉最後兩段就是商家（商家自己有「|」也對）。拆不開＝""
    static func merchantKey(fromFingerprint fp: String) -> String {
        let parts = fp.components(separatedBy: "|")
        guard parts.count >= 3 else { return "" }
        return parts.dropLast(2).joined(separator: "|")
    }

    /// 同行人員去頭尾空白；空的＝nil
    static func cleanMember(_ raw: String?) -> String? {
        let t = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// 最近清單裡同一個原始店名（merchantKey）的自動記帳、還在帳本、是變動支出的那幾筆（照 recent 的順序：
    /// 傳 WalletRecentLog.all() 就是新到舊）。excluding＝正在入帳的這一筆
    static func walletMatches(merchant: String, excluding: UUID?, recent: [WalletRecentItem],
                              ledger: [Expense]) -> [Expense] {
        let key = titleKey(merchant)
        guard !key.isEmpty, !recent.isEmpty else { return [] }
        var byId: [UUID: Expense] = [:]
        for e in ledger where byId[e.id] == nil {
            byId[e.id] = e
        }
        var seen = Set<UUID>()
        var out: [Expense] = []
        for item in recent where item.id != excluding && !seen.contains(item.id) && item.merchantKey == key {
            seen.insert(item.id)
            if let e = byId[item.id], e.expenseType == .variable {
                out.append(e)
            }
        }
        return out
    }

    /// 名稱一樣的變動支出裡、有同行人員的最新一筆的同行人員（同 lastCategory 的挑法：日期最新、同時間取排前面的）
    static func lastMember(for merchant: String, in ledger: [Expense]) -> String? {
        let key = titleKey(merchant)
        guard !key.isEmpty else { return nil }
        var best: Expense? = nil
        for e in ledger where e.expenseType == .variable && cleanMember(e.diningMember) != nil && titleKey(e.title) == key {
            if let b = best, e.date <= b.date { continue }
            best = e
        }
        return cleanMember(best?.diningMember)
    }

    /// 同一家店上一次（C3）：分類＝同一個錢包原始店名、最新那一筆自動記帳**現在的**分類（有分類的；股票、房地產當其他）；
    /// 找不到退回 lastCategory（25.608）。同行人員（C2）＝那幾筆裡最新一筆有同行人員的；都沒有再退回名稱一樣的 lastMember
    static func shopMemory(merchant: String, excluding: UUID?, recent: [WalletRecentItem],
                           ledger: [Expense]) -> WalletShopMemory {
        let matches = walletMatches(merchant: merchant, excluding: excluding, recent: recent, ledger: ledger)
        var category: VariableCategory = .other
        var fromWallet = false
        if let c = matches.first(where: { $0.variableCategory != nil })?.variableCategory {
            category = (c == .stock || c == .realEstate) ? .other : c
            fromWallet = true
        } else {
            category = lastCategory(for: merchant, in: ledger)
        }
        var member: String? = nil
        for e in matches {
            if let m = cleanMember(e.diningMember) {
                member = m
                break
            }
        }
        if member == nil {
            member = lastMember(for: merchant, in: ledger)
        }
        return WalletShopMemory(category: category, member: member, fromWallet: fromWallet)
    }

    /// 這一筆要帶的同行人員：開關開著、分類有同行人員欄位（memberCategories）才帶
    static func carriedMember(_ memory: WalletShopMemory, enabled: Bool) -> String? {
        guard enabled, memberCategories.contains(memory.category) else { return nil }
        return memory.member
    }

    /// [learn] 每張卡（cardKey）以前自動記、還在帳本、沒連任何卡或帳戶的筆數（設定頁「還有 N 筆沒連」；
    /// 條件同 WalletImport.unlinkedPast，一次算全部的卡）
    static func unlinkedCounts(recent: [WalletRecentItem], ledger: [Expense]) -> [String: Int] {
        var unlinked = Set<UUID>()
        for e in ledger where e.linkedCreditCardMilestoneId == nil && e.linkedBankMilestoneId == nil {
            unlinked.insert(e.id)
        }
        var seen = Set<UUID>()
        var out: [String: Int] = [:]
        for item in recent where !item.cardKey.isEmpty && !seen.contains(item.id) && unlinked.contains(item.id) {
            seen.insert(item.id)
            out[item.cardKey, default: 0] += 1
        }
        return out
    }

    // MARK: 設定頁的字

    /// 「最近自動記的」一列：「11/7 7-ELEVEN NT$65・國泰 CUBE」（account 是 nil 就不寫「・…」）
    static func rowText(date: Date, title: String, amountText: String, account: String?,
                        calendar: Calendar) -> String {
        let c = calendar.dateComponents([.month, .day], from: date)
        var s = "\(c.month ?? 0)/\(c.day ?? 0) \(title) \(amountText)"
        if let a = account, !a.isEmpty { s += "・" + a }
        return s
    }

    /// 「11/7」（還沒對應的卡「最近一筆 11/7」）
    static func shortDate(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.month, .day], from: date)
        return "\(c.month ?? 0)/\(c.day ?? 0)"
    }

    /// 帳戶顯示名（照 AIExpenseCommitter：信用卡用卡名、銀行用銀行名，沒填用標題）
    static func accountName(_ ms: LifeMilestone) -> String {
        let preferred: String? = ms.financeSubCategory == .creditCard ? ms.cardName : ms.bankName
        let p = (preferred ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty ? ms.title : p
    }

    /// 財富裡可以連的信用卡（沒停用）與銀行帳戶（照 AIExpenseCommitter.creditCardOptions／bankOptions 的條件）
    static func candidates(_ milestones: [LifeMilestone]) -> (cards: [WalletLinkCandidate], banks: [WalletLinkCandidate]) {
        var cards: [WalletLinkCandidate] = []
        var banks: [WalletLinkCandidate] = []
        for ms in milestones where ms.category == .achievement {
            if ms.financeSubCategory == .creditCard, ms.isDisabled != true {
                let names = [ms.cardName ?? "", ms.title].filter { !$0.isEmpty }
                cards.append(WalletLinkCandidate(id: ms.id, kind: .card, display: accountName(ms),
                                                 names: names, lastFour: ms.cardLastFour))
            } else if ms.financeSubCategory == .bank {
                let names = [ms.bankName ?? "", ms.title].filter { !$0.isEmpty }
                banks.append(WalletLinkCandidate(id: ms.id, kind: .bank, display: accountName(ms),
                                                 names: names, lastFour: nil))
            }
        }
        return (cards: cards, banks: banks)
    }
}

// MARK: - 這台記住的（App Group 的 UserDefaults）

enum WalletDefaults {
    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = WidgetShared.defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        guard let d = WidgetShared.defaults, let data = try? JSONEncoder().encode(value) else { return }
        d.set(data, forKey: key)
    }
}

/// 捷徑給的卡片名稱 → 帳戶（這台；不跟 iCloud）
enum WalletCardBook {
    static let key = "wallet_card_links"

    /// 全部，最近用過的在前
    static func all() -> [WalletCardLink] {
        let list = WalletDefaults.load([WalletCardLink].self, key: key) ?? []
        return list.sorted { a, b in
            if a.lastSeen != b.lastSeen { return a.lastSeen > b.lastSeen }
            return a.key < b.key
        }
    }

    static func find(_ cardKey: String) -> WalletCardLink? {
        guard !cardKey.isEmpty else { return nil }
        return all().first { $0.key == cardKey }
    }

    /// 存一張（同 key 的換掉）
    static func save(_ link: WalletCardLink) {
        guard !link.key.isEmpty else { return }
        var list = all().filter { $0.key != link.key }
        list.append(link)
        WalletDefaults.save(list, key: key)
    }

    /// 自動記了一筆：名稱換成最新的字、記下時間；沒看過的新增一張「還沒對應」
    static func noteSeen(name: String, at date: Date) {
        let k = WalletAutoRecord.cardKey(name)
        guard !k.isEmpty else { return }
        var link = find(k) ?? WalletCardLink(key: k, name: name, target: nil, milestoneId: nil,
                                             auto: false, dollarCode: nil, lastSeen: date)
        link.name = name
        link.lastSeen = max(link.lastSeen, date)
        save(link)
    }

    /// 使用者〔選一張〕／〔不連帳戶〕
    static func setTarget(_ cardKey: String, target: WalletLinkTarget, milestoneId: UUID?) {
        guard var link = find(cardKey) else { return }
        link.target = target.rawValue
        link.milestoneId = target == .noAccount ? nil : milestoneId
        link.auto = false
        save(link)
    }

    /// 使用者改「沒寫幣別時當作」（nil／台幣＝台幣）
    static func setDollarCode(_ cardKey: String, code: String?) {
        guard var link = find(cardKey) else { return }
        let c = (code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        link.dollarCode = (c.isEmpty || FinanceRates.isNTD(c)) ? nil : c
        save(link)
    }

    /// 〔忘記這張卡〕
    static func remove(_ cardKey: String) {
        let list = all().filter { $0.key != cardKey }
        WalletDefaults.save(list, key: key)
    }
}

/// 最近自動記的（這台；最多留 200 筆，設定頁畫最新 30 筆）
enum WalletRecentLog {
    static let key = "wallet_recent_ids"
    static let maxCount = 200
    static let shownCount = 30

    /// 新到舊
    static func all() -> [WalletRecentItem] {
        let list = WalletDefaults.load([WalletRecentItem].self, key: key) ?? []
        return list.sorted { a, b in
            if a.at != b.at { return a.at > b.at }
            return a.id.uuidString < b.id.uuidString
        }
    }

    static func note(_ item: WalletRecentItem) {
        var list = all().filter { $0.id != item.id }
        list.insert(item, at: 0)
        WalletDefaults.save(Array(list.prefix(maxCount)), key: key)
    }

    static func remove(_ id: UUID) {
        WalletDefaults.save(all().filter { $0.id != id }, key: key)
    }
}

/// 沒記到的（這台；最多留 10 筆）
enum WalletMissedLog {
    static let key = "wallet_missed"
    static let maxCount = 10

    /// 新到舊
    static func all() -> [WalletMissedItem] {
        let list = WalletDefaults.load([WalletMissedItem].self, key: key) ?? []
        return list.sorted { $0.at > $1.at }
    }

    static func note(amountText: String, reason: String, at date: Date) {
        var list = all()
        list.insert(WalletMissedItem(id: UUID(), at: date, amountText: amountText, reason: reason), at: 0)
        WalletDefaults.save(Array(list.prefix(maxCount)), key: key)
    }

    static func clear() {
        WidgetShared.defaults?.removeObject(forKey: key)
    }
}

/// [learn] 這台的開關（App Group；不跟 iCloud、不進備份、不是同步鍵）
enum WalletPrefs {
    static let memberFromLastKey = "wallet_member_from_last"

    /// 「同行人員照上一次」：出廠開（沒存過＝開）
    static var memberFromLast: Bool {
        (WidgetShared.defaults?.object(forKey: memberFromLastKey) as? Bool) ?? true
    }

    static func setMemberFromLast(_ on: Bool) {
        WidgetShared.defaults?.set(on, forKey: memberFromLastKey)
    }
}

// MARK: - [learn] 從你的修改學卡片（C1；掛鉤點：AddExpenseView 編輯存檔）

enum WalletLearn {
    /// 一筆支出連的帳戶：信用卡優先（刷卡那筆可能也帶著扣款銀行），再來直接扣的銀行帳戶；都沒連＝nil
    static func account(of e: Expense) -> WalletLearnedLink? {
        if let c = e.linkedCreditCardMilestoneId { return WalletLearnedLink(target: .card, milestoneId: c) }
        if let b = e.linkedBankMilestoneId { return WalletLearnedLink(target: .bank, milestoneId: b) }
        return nil
    }

    /// 純判斷：自動記的那一筆（item：最近清單裡同 id 的那一項）手動改了連的帳戶 → 要學成什麼；不用學＝nil。
    /// 沒給卡名的不學；改成「不連」不學；跟改之前一樣不學；對應表已經是這個帳戶不學（免得把「自動對到」洗成你選的）
    static func learned(before: Expense, after: Expense, item: WalletRecentItem?,
                        current: WalletCardLink?) -> WalletLearnedLink? {
        guard before.id == after.id, let item, item.id == after.id, !item.cardKey.isEmpty else { return nil }
        guard let changed = account(of: after) else { return nil }
        guard changed != account(of: before) else { return nil }
        if let c = current, c.linkTarget == changed.target, c.milestoneId == changed.milestoneId { return nil }
        return changed
    }

    /// 掛鉤點叫（AddExpenseView 編輯存檔、dismiss 之後的下一個 runloop）：學到就寫這台的對應表（WalletCardBook.setTarget），
    /// 回傳有沒有學。不是自動記的（最近清單沒有這個 id）什麼都不做。對應表沒有這張卡（〔忘記這張卡〕過）就照最近清單的卡名補一張
    @discardableResult
    static func noteManualEdit(before: Expense, after: Expense) -> Bool {
        guard let item = WalletRecentLog.all().first(where: { $0.id == after.id }) else { return false }
        let current = WalletCardBook.find(item.cardKey)
        guard let changed = learned(before: before, after: after, item: item, current: current) else { return false }
        if current == nil {
            let name = item.cardName.isEmpty ? item.cardKey : item.cardName
            WalletCardBook.save(WalletCardLink(key: item.cardKey, name: name, target: nil, milestoneId: nil,
                                               auto: false, dollarCode: nil, lastSeen: item.at))
        }
        WalletCardBook.setTarget(item.cardKey, target: changed.target, milestoneId: changed.milestoneId)
        return true
    }
}

// MARK: - 捷徑動作進來（WalletRecordIntent.perform 叫）

struct WalletIntakeResult: Equatable {
    /// 回「已記一筆」（重複的那次也是 true）
    var recorded: Bool
    /// 90 秒內同一筆，這次沒寫
    var duplicate: Bool = false
    /// 寫進收件匣的那一筆
    var entryId: UUID? = nil

    var reply: String { WalletAutoRecord.reply(recorded: recorded) }
}

@MainActor
enum WalletIntake {
    /// 捷徑的三個參數 → 收件匣一筆。不碰三份大資料（AppStores）：App 沒開著就只放收件匣，等 App 回前景收
    static func record(amountText raw: String, merchant: String?, card: String?,
                       now: Date = Date()) -> WalletIntakeResult {
        let shownText = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(WalletAutoRecord.maxTextLength))
        guard let parsed = WalletAutoRecord.parseAmount(raw) else {
            WalletMissedLog.note(amountText: shownText, reason: WalletAutoRecord.reasonUnreadable, at: now)
            return WalletIntakeResult(recorded: false)
        }
        let title = WalletAutoRecord.cleanMerchant(merchant)
        let cardName = WalletAutoRecord.cleanCard(card)
        let cardKey = WalletAutoRecord.cardKey(cardName)
        let fp = WalletAutoRecord.fingerprint(merchant: title, value: parsed.value, cardKey: cardKey)
        if WalletAutoRecord.isDuplicate(fingerprint: fp, now: now, recent: WalletRecentLog.all()) {
            return WalletIntakeResult(recorded: true, duplicate: true)
        }
        let dollar = WalletCardBook.find(cardKey)?.dollarCode
        let money = WalletAutoRecord.resolveMoney(parsed, cardCurrency: dollar, rates: WalletAutoRecord.savedRates())
        var amount: Double = parsed.value
        var code: String? = nil
        var foreign: Double? = nil
        var rate: Double? = nil
        switch money {
        case .twd(let a):
            amount = a
        case .foreign(let a, let c, let o, let r):
            amount = a
            code = c
            foreign = o
            rate = r
        case .noRate(let iso, _):
            WalletMissedLog.note(amountText: shownText, reason: WalletAutoRecord.reasonNoRate(iso), at: now)
            return WalletIntakeResult(recorded: false)
        }
        guard amount.isFinite, amount > 0, amount <= WalletAutoRecord.maxTWD else {
            WalletMissedLog.note(amountText: shownText, reason: WalletAutoRecord.reasonTooLarge, at: now)
            return WalletIntakeResult(recorded: false)
        }
        var entry = QuickRecordEntry(templateId: "wallet." + UUID().uuidString, title: title, amount: amount,
                                     amountText: "", categoryKey: VariableCategory.other.rawValue,
                                     vehicleId: nil, vehicleCategoryKey: nil, now: now)
        entry.source = QuickRecordInbox.walletSource
        entry.currencyCode = code
        entry.foreignAmount = foreign
        entry.rateShown = rate
        entry.walletCard = cardName.isEmpty ? nil : cardName
        guard QuickRecordInbox.add(entry) != .failed else {
            WalletMissedLog.note(amountText: shownText, reason: WalletAutoRecord.reasonWriteFailed, at: now)
            return WalletIntakeResult(recorded: false)
        }
        WalletRecentLog.note(WalletRecentItem(id: entry.id, at: now, cardKey: cardKey, cardName: cardName,
                                              fingerprint: fp, merchant: title))
        if !cardKey.isEmpty {
            WalletCardBook.noteSeen(name: cardName, at: now)
        }
        QuickRecordInbox.postChanged()
        let importer = QuickRecordImporter.shared
        if importer.isReady {
            importer.importFromWallet()
        }
        return WalletIntakeResult(recorded: true, entryId: entry.id)
    }
}

// MARK: - 入帳與設定頁要用的（QuickRecordImporter、WalletAutoRecordView 叫）

@MainActor
enum WalletImport {
    /// 收件匣 wallet 那一筆 → Expense（還沒存）：變動支出、title＝商家、台幣金額、date＝付款那一刻、
    /// 分類照同商家上一次（[learn] 先比錢包原始店名）、同行人員照上一次（[learn]）、連卡片（對應表；第一次看到先自動對）、
    /// fromQuickRecord＝true（電子發票防重複會併）。
    /// 不連車、不連旅遊、不連房地產
    static func makeExpense(from entry: QuickRecordEntry, ledger: [Expense], life: LifeStore?,
                            expense: ExpenseStore, finance: FinanceStore, now: Date = Date()) -> Expense? {
        guard entry.amount.isFinite, entry.amount > 0 else { return nil }
        let title = WalletAutoRecord.cleanMerchant(entry.title)
        // [learn] v25.611 C2／C3：分類、同行人員照同一家店上一次（先比錢包原始店名的自動記帳，再退回名稱一樣的）
        let memory = WalletAutoRecord.shopMemory(merchant: title, excluding: entry.id, recent: WalletRecentLog.all(),
                                                 ledger: ledger)
        let category = memory.category
        let link = resolveLink(cardName: entry.walletCard ?? "", life: life, expense: expense,
                               finance: finance, now: now)
        let code = (entry.currencyCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var e = Expense(
            id: entry.id,
            title: title,
            amount: entry.amount,
            date: entry.createdAt,
            expenseType: .variable,
            variableCategory: category,
            note: "",
            currencyCode: code.isEmpty ? "NT$" : code,
            linkedBankMilestoneId: link?.bankId,
            linkedBankCurrency: link?.bankCurrency,
            linkedCreditCardMilestoneId: link?.cardId
        )
        e.fromQuickRecord = true
        // [learn] 同行人員照上一次（設定頁開關；只帶進有同行人員欄位的分類）。不在 memberwise init 的順序裡找位置，存檔前指派
        e.diningMember = WalletAutoRecord.carriedMember(memory, enabled: WalletPrefs.memberFromLast)
        return e
    }

    /// 這張卡要連哪裡：對應表有決定的照決定；還沒對應的先試自動對（對到就記進對應表），對不到＝不連
    static func resolveLink(cardName: String, life: LifeStore?, expense: ExpenseStore,
                            finance: FinanceStore, now: Date) -> WalletAccountLink? {
        let key = WalletAutoRecord.cardKey(cardName)
        guard !key.isEmpty, let life else { return nil }
        var link = WalletCardBook.find(key) ?? WalletCardLink(key: key, name: cardName, target: nil, milestoneId: nil,
                                                              auto: false, dollarCode: nil, lastSeen: now)
        if !link.isDecided {
            let pool = WalletAutoRecord.candidates(life.milestones)
            if let hit = WalletAutoRecord.autoMatch(walletName: cardName, cards: pool.cards, banks: pool.banks) {
                link.target = hit.kind.rawValue
                link.milestoneId = hit.id
                link.auto = true
            }
            WalletCardBook.save(link)
        }
        return accountLink(for: link, life: life, expense: expense, finance: finance)
    }

    /// 對應表的一張 → 要連的帳戶（對到的帳戶不見了、〔不連帳戶〕、還沒對應＝nil）
    static func accountLink(for link: WalletCardLink, life: LifeStore, expense: ExpenseStore,
                            finance: FinanceStore) -> WalletAccountLink? {
        guard let target = link.linkTarget, let mid = link.milestoneId,
              let ms = life.milestones.first(where: { $0.id == mid }) else { return nil }
        switch target {
        case .card:
            guard ms.financeSubCategory == .creditCard else { return nil }
            let bank = ms.linkedBankMilestoneId
            return WalletAccountLink(cardId: ms.id, bankId: bank, bankCurrency: bank == nil ? nil : "NT$")
        case .bank:
            guard ms.financeSubCategory == .bank else { return nil }
            let codes = WealthFacts.currencies(forAccount: ms, expenses: expense.expenses, incomes: expense.incomes,
                                               stocks: finance.stocks)
            return WalletAccountLink(cardId: nil, bankId: ms.id, bankCurrency: codes.first ?? "NT$")
        case .noAccount:
            return nil
        }
    }

    /// 對到的帳戶顯示名（設定頁；不見了＝nil）
    static func accountDisplay(for link: WalletCardLink, life: LifeStore) -> String? {
        guard let mid = link.milestoneId, let ms = life.milestones.first(where: { $0.id == mid }) else { return nil }
        return WalletAutoRecord.accountName(ms)
    }

    /// 一筆支出連到的卡或帳戶的顯示名（「最近自動記的」那一列；都沒連＝nil）
    static func accountDisplay(of e: Expense, life: LifeStore) -> String? {
        guard let mid = e.linkedCreditCardMilestoneId ?? e.linkedBankMilestoneId,
              let ms = life.milestones.first(where: { $0.id == mid }) else { return nil }
        return WalletAutoRecord.accountName(ms)
    }

    /// 已經存好的那幾筆裡、直接扣銀行帳戶（沒連信用卡）的：寫銀行扣款紀錄（照 AIExpenseCommitter.syncBankWithdrawal）
    static func syncBankWithdrawals(_ list: [Expense], expense: ExpenseStore, life: LifeStore) {
        let rates = FinanceRates(expense)
        for e in list where e.linkedCreditCardMilestoneId == nil && e.linkedBankMilestoneId != nil {
            syncBankWithdrawal(for: e, life: life, rates: rates, ntd: expense.ntdValue(of: e))
        }
    }

    /// 照 AIExpenseCommitter.syncBankWithdrawal（新紀錄；那個帳戶已經有指到這筆的就不再寫）
    private static func syncBankWithdrawal(for exp: Expense, life: LifeStore, rates: FinanceRates, ntd: Double) {
        guard exp.linkedCreditCardMilestoneId == nil,
              let bankId = exp.linkedBankMilestoneId,
              var ms = life.milestones.first(where: { $0.id == bankId }) else { return }
        var list = ms.bankDeposits ?? []
        guard !list.contains(where: { $0.linkedExpenseId == exp.id }) else { return }
        let withdrawal = rates.bankAmount(of: exp, ntd: ntd)
        list.append(BankDeposit(
            id: UUID(), date: exp.date, amount: withdrawal.amount,
            currencyCode: withdrawal.code,
            isWithdrawal: true, linkedExpenseId: exp.id
        ))
        ms.bankDeposits = list
        life.update(ms)
    }

    /// 以前用這張卡自動記、還沒連任何卡或帳戶的（還在帳本裡的才算）
    static func unlinkedPast(key: String, expense: ExpenseStore) -> [Expense] {
        guard !key.isEmpty else { return [] }
        let ids = Set(WalletRecentLog.all().filter { $0.cardKey == key }.map(\.id))
        guard !ids.isEmpty else { return [] }
        return expense.expenses.filter { e in
            ids.contains(e.id) && e.linkedCreditCardMilestoneId == nil && e.linkedBankMilestoneId == nil
        }
    }

    /// 〔一起連〕：把以前那幾筆照這張卡現在的對應連起來（一次存檔；直接扣銀行的補扣款紀錄）。回傳連了幾筆
    @discardableResult
    static func linkPast(key: String, expense: ExpenseStore, life: LifeStore, finance: FinanceStore) -> Int {
        guard let card = WalletCardBook.find(key),
              let link = accountLink(for: card, life: life, expense: expense, finance: finance) else { return 0 }
        let targets = unlinkedPast(key: key, expense: expense)
        guard !targets.isEmpty else { return 0 }
        var updated: [Expense] = []
        expense.withBatch {
            for var e in targets {
                e.linkedCreditCardMilestoneId = link.cardId
                e.linkedBankMilestoneId = link.bankId
                e.linkedBankCurrency = link.bankCurrency
                expense.update(e)
                updated.append(e)
            }
        }
        syncBankWithdrawals(updated, expense: expense, life: life)
        return updated.count
    }

    /// 設定頁〔刪除〕：照 VariableExpenseView.deleteWithSync 一筆的寫法（房地產、股票、銀行扣款一起清），
    /// 再 ExpenseStore.delete（照片、車子鏡像）；最近清單拿掉這一筆
    static func delete(_ e: Expense, expense: ExpenseStore, life: LifeStore, finance: FinanceStore) {
        if let reId = e.linkedRealEstateId,
           var re = finance.realEstates.first(where: { $0.id == reId }) {
            re.paidItems.removeAll { $0.linkedExpenseId == e.id }
            re.variableExpenses.removeAll { $0.linkedExpenseId == e.id }
            re.insuranceItems.removeAll { $0.linkedExpenseId == e.id }
            re.propertyAssets.removeAll { $0.linkedExpenseId == e.id }
            for up in re.utilityPayments where up.linkedExpenseId == e.id {
                up.photoFileNames.forEach { UtilityPayment.deletePhoto($0) }
            }
            re.utilityPayments.removeAll { $0.linkedExpenseId == e.id }
            finance.update(re)
        }
        if let stockId = e.linkedStockId,
           var stock = finance.stocks.first(where: { $0.id == stockId }),
           stock.linkedExpenseId == e.id {
            stock.linkedExpenseId = nil
            finance.update(stock)
        }
        if let bankId = e.linkedBankMilestoneId,
           var ms = life.milestones.first(where: { $0.id == bankId }) {
            ms.bankDeposits?.removeAll { $0.linkedExpenseId == e.id }
            life.update(ms)
        }
        expense.delete(e)
        WalletRecentLog.remove(e.id)
    }
}
