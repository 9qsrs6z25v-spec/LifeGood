import SwiftUI

// MARK: - 財富的表單、小表單、要確認（v25.564，財富 v3；wealth/judge.md §5、§4.5、§3.5、§5.6）
//
// • WealthAccountEditor：新增／編輯銀行帳戶、信用卡、證券戶、保單（從履歷搬出來；類型開了就鎖住）。
//   存的地方還是 LifeMilestone（身分＋舊欄位，給舊 iPad、網頁版、醫療地圖）＋財富帳本（LifeStore.saveWealthAccount）。
//   安全碼（使用者第 6 題「我要存」）：「記錄檢核碼（CVV／CVC）」開關＋欄位照留（預設關），CardVault 加密、Face ID 才看得到。
//   刪除只在編輯頁最下面（FinanceDeleteAlert＋LifeStore.deleteFinanceMilestone；卡先建議〔改成停用〕、銀行先建議〔收起來就好〕）。
// • 小表單（.presentationDetents([.medium, .large])）：記一筆、轉帳、對存摺、標成已繳、帳單金額不一樣、一次改到別張卡／改到別的帳戶、
//   排序與收起來、匯率。
// • WealthChecksSection：財富頁 ②、卡片頁 ② 共用的「要確認」（FinanceCardHeader＋白卡裡 FinanceCheckRow；0 件整區不出現），
//   按鈕照 WealthCheck.Fix 開表單或叫 LifeStore。
// 每個表單自己掛 WealthPrivacyCurtain（有號碼的表單 armed）；儲存鈕忙碌守衛；刪除一律先問；先 dismiss、下一個 runloop 才寫 store。
// 數字一律讀 lifeStore.wealthFacts（打開表單時抓一次存進 @State，打字不重算，judge §4.5）。
//
// 分工：G3 實作（這個檔＋ResumeView、MyCalendarView、AddExpenseView）。主控放的入口簽章不改（G1、G2 在叫）。
//
// [v25.565] 財富 v4（build/v4/brief.md §G4-6、§G4-7）：
// • 要確認 #12〔看綁了哪些〕（WealthCheck.Fix.openCard）：WealthChecksSection(onOpenCard:) 交給呼叫端（財富頁開卡片頁、卡片頁捲到
//   定期扣款）；沒給就自己開 WealthFormSheet.card（WealthCardPage 捲到 .recurring）。看卡片頁不擋訂閱。
// • 信用卡表單「提醒我繳卡費」：WealthCardPrefs.remind（v2 留好的欄位；開＝存 nil、關＝存 false）。通知不寫卡名、金額、號碼。
//
// [v25.566] 財富 v5（build/v5/brief.md §G3；定存表單本身在 WealthDepositForms.swift）：
// • 要確認三個新按鈕（WealthChecksSection.tap）：#13〔改成轉活存〕〔改成本息續存〕〔轉活存〕〔本息續存〕＝Fix.setMaturity
//   （下一個 runloop 叫 LifeStore.setTimeDepositOnMaturity；不擋訂閱，跟標成已繳一樣是處理到期的事）；舊的定存帳戶〔補資料〕＝
//   Fix.editTimeDeposit（開 WealthTimeDepositSheet，要訂閱）；#14 存款保險〔知道了〕＝Fix.quietInsurance（這家銀行一年內不再提）。
// • WealthFormSheet.timeDeposit(accountId:editing:)：要確認、表單裡開定存表單。
// • 轉帳表單換匯模式 WealthTransferSheet(…, exchange: true)：同一個帳戶兩個幣別互轉也是轉帳（兩筆同一個 transferPairId，
//   LifeStore.addTransfer 放寬成「不同帳戶，或同一個帳戶不同幣別」）。帳戶有兩個以上幣別＝自己換（台幣 → 第一個外幣）；
//   只有一個外幣＝從存摺上台幣最多的另一個活存換進來（v2 就能換匯）。同一個帳戶時兩邊幣別一定不一樣。
// • 銀行帳戶表單「種類與幣別」footer 多一句：定存不是帳戶種類，存好帳戶後到帳戶頁〔＋ 定存〕記。

/// 表單的類型（開了就鎖住）
enum WealthAccountKind: String, CaseIterable, Identifiable {
    case bank, card, broker, policy

    var id: String { rawValue }

    /// 里程碑的子分類 → 表單類型（沒有子分類＝nil：那是一件財富大事，用原本的里程碑表單）
    init?(sub: FinanceSubCategory?) {
        switch sub {
        case .bank?: self = .bank
        case .creditCard?: self = .card
        case .securities?: self = .broker
        case .insurance?: self = .policy
        case nil: return nil
        }
    }

    var sub: FinanceSubCategory {
        switch self {
        case .bank: return .bank
        case .card: return .creditCard
        case .broker: return .securities
        case .policy: return .insurance
        }
    }

    /// 「銀行帳戶」「信用卡」「證券戶」「保單」（＋選單、表單標題「新增銀行帳戶」）
    var title: String {
        switch self {
        case .bank: return "銀行帳戶"
        case .card: return "信用卡"
        case .broker: return "證券戶"
        case .policy: return "保單"
        }
    }

    var icon: String {
        switch self {
        case .bank: return "building.columns.fill"
        case .card: return "creditcard.fill"
        case .broker: return "chart.line.uptrend.xyaxis"
        case .policy: return "cross.case.fill"
        }
    }
}

/// 從要確認點進表單時先捲到哪一段
enum WealthEditorFocus: String {
    case cardDays, payFrom, settlement
}

// MARK: - 新增／編輯財富帳戶（judge §5；樣稿③-C1，但安全碼照留——使用者第 6 題「我要存」）

/// 常用清單（只是字，不放商標）
enum WealthNameLists {
    static let banks: [String] = [
        "台灣銀行", "土地銀行", "合作金庫", "第一銀行", "華南銀行", "彰化銀行", "兆豐銀行", "國泰世華", "中國信託",
        "台北富邦", "玉山銀行", "台新銀行", "永豐銀行", "元大銀行", "凱基銀行", "星展銀行", "滙豐銀行", "中華郵政",
        "LINE Bank", "將來銀行", "樂天銀行"
    ]
    static let brokers: [String] = [
        "元大證券", "凱基證券", "富邦證券", "國泰證券", "永豐金證券", "群益金鼎證券", "統一證券", "元富證券",
        "玉山證券", "台新證券", "中信證券", "兆豐證券", "華南永昌證券"
    ]
    static let insurers: [String] = [
        "國泰人壽", "富邦人壽", "南山人壽", "新光人壽", "台灣人壽", "中國人壽", "全球人壽", "三商美邦人壽",
        "遠雄人壽", "安聯人壽", "保誠人壽", "富邦產險", "國泰產險", "新光產險"
    ]
    static let purposes: [String] = ["薪轉", "扣款", "存錢", "外幣", "零用"]
}

/// 存檔前在主執行緒封好的密文（加密失敗就不存）
struct WealthSealed {
    var accountCipher: Data? = nil
    var cardNumber: Data? = nil
    var security: Data? = nil
    var cardLast4: String? = nil
}

/// 表單上的欄位（一個 struct 存全部：@State 少、帶入／存檔是純函式，型別檢查不爆）
struct WealthAccountForm {
    // 共通
    /// 銀行／發卡銀行／券商／保險公司
    var name = ""
    /// 暱稱（保單：保單名稱）
    var nickname = ""
    var note = ""
    /// 開戶日／核卡日／生效日
    var date = Date()
    var photos: [String] = []
    // 銀行、證券戶的帳號（第 7 題：預設只存末 4 碼；開關打開才加密存完整帳號）
    var branch = ""
    var last4 = ""
    var storeFullNumber = false
    var fullNumber = ""
    var accountCipher: Data? = nil
    var accountUnlocked = true
    /// 解鎖了但這台裝置解不開（沒有金鑰）：欄位空著，沒重打就把原本的密文原封帶回（別台解得開，不能洗掉）
    var accountVaultLost = false
    /// 里程碑上是舊的明碼完整帳號（存檔後搬進密文、里程碑只留末 4 碼，brief §1-4）
    var legacyFullNumber = false
    var bankType: BankAccountType = .savings
    /// 台幣以外勾的幣別
    var currencies: [String] = []
    /// 新增：今天存摺上有多少（幣別 → 打的字）
    var openings: [String: String] = [:]
    var purpose = ""
    var colorId: Int? = nil
    var countsInCash = true
    // 信用卡
    var cardName = ""
    var faceColor = 0
    /// [v25.565] 提醒我繳卡費（帳本 WealthCardPrefs.remind：nil／true＝提醒、false＝這張不提醒；沒設過＝開）
    var remind = true
    /// 1–31；0＝沒填
    var billingDay = 0
    var paymentDay = 0
    var limitText = ""
    var payMode: WealthPayMode = .autoFull
    /// 卡：扣款帳戶／通常從；保單：從哪扣
    var payFrom: UUID? = nil
    var cardNumber = ""
    var cardLast4 = ""
    var cardCipher: Data? = nil
    var securityCipher: Data? = nil
    var cardUnlocked = true
    /// 解鎖了但這台裝置解不開卡號／檢核碼（沒有金鑰）：沒重打就原封帶回密文
    var cardVaultLost = false
    var securityVaultLost = false
    var wantsSecurity = false
    var security = ""
    var hasExpiry = false
    var expiry = Date()
    var annualFeeText = ""
    var waiveAmountText = ""
    var waiveCountText = ""
    /// 卡片年度從幾月起（0＝日曆年）
    var feeYearStart = 0
    var perks = ""
    var easyCard = ""
    var iPass = ""
    var happyGo = ""
    // 證券戶
    var settlementBankId: UUID? = nil
    var secType: SecuritiesAccountType = .regular
    // 保單
    var policyKind: WealthPolicyKind = .medical
    var insured = ""
    var policyholder = ""
    var beneficiary = ""
    var premiumText = ""
    var payCycle: WealthPolicyCycle = .year
    var payYearsText = ""
    var hasNextDue = false
    var nextDue = Date()
    var coverageUntil = ""
    var coverageText = ""
    var policyNumber = ""

    static func trimmed(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// 帳號末 4 碼：有打用打的；沒打但有解開的完整帳號，取最後 4 個數字
    var accountTail: String {
        let typed = WealthFormText.digits(last4, limit: 4)
        if !typed.isEmpty { return typed }
        guard accountUnlocked, storeFullNumber else { return "" }
        let d = fullNumber.filter { $0.isASCII && $0.isNumber }
        return String(d.suffix(4))
    }

    /// 新增銀行帳戶「今天存摺上有多少」：幣別 → 數字（空著的不寫）
    var openingBalances: [String: Double] {
        var out: [String: Double] = [:]
        for code in ["NT$"] + currencies {
            if let t = openings[code], let v = WealthFormText.number(t) { out[code] = v }
        }
        return out
    }

    /// 里程碑標題（履歷、行事曆照讀）：有暱稱「薪轉（台新銀行）」；不然照以前的規則（分行不再寫進標題）
    func title(kind: WealthAccountKind) -> String {
        let n = name.trimmingCharacters(in: .whitespaces)
        let nick = nickname.trimmingCharacters(in: .whitespaces)
        if !nick.isEmpty { return nick + "（" + n + "）" }
        switch kind {
        case .bank, .broker:
            return "開戶 " + n
        case .card:
            let c = cardName.trimmingCharacters(in: .whitespaces)
            return c.isEmpty ? n + " 信用卡" : n + " " + c
        case .policy:
            return n + " " + policyKind.shortTitle
        }
    }
}

extension WealthAccountForm {
    /// 編輯：從里程碑＋帳本帶入
    static func load(_ m: LifeMilestone, kind: WealthAccountKind, book: WealthBook) -> WealthAccountForm {
        var f = WealthAccountForm()
        let prefs = book.account(m.id)
        f.nickname = prefs.nickname ?? ""
        f.note = m.note
        f.date = m.date
        f.photos = m.photoFileNames ?? []
        switch kind {
        case .bank, .broker:
            f.name = m.bankName ?? ""
            f.branch = m.branchName ?? ""
            f.loadAccountNumber(m, prefs: prefs)
            f.bankType = m.bankAccountType ?? .savings
            f.currencies = (prefs.currencies ?? []).filter { !FinanceRates.isNTD($0) }
            f.purpose = prefs.purpose ?? ""
            f.colorId = prefs.colorId
            f.countsInCash = prefs.countInCash != false
            f.settlementBankId = prefs.settlementBankId
            f.secType = m.securitiesAccountType ?? .regular
        case .card:
            f.loadCard(m, book: book)
        case .policy:
            f.loadPolicy(m, book: book)
        }
        return f
    }

    mutating func loadAccountNumber(_ m: LifeMilestone, prefs: WealthAccountPrefs) {
        let raw = (m.accountNumber ?? "").trimmingCharacters(in: .whitespaces)
        let digits = raw.filter { $0.isASCII && $0.isNumber }
        if let c = prefs.accountNumberCipher {
            accountCipher = c
            storeFullNumber = true
            accountUnlocked = false
        } else if digits.count > 4 {
            legacyFullNumber = true
            storeFullNumber = true
            fullNumber = raw
        }
        last4 = prefs.accountLast4 ?? String(digits.suffix(4))
    }

    mutating func loadCard(_ m: LifeMilestone, book: WealthBook) {
        let cp = book.card(m.id)
        name = m.bankName ?? ""
        cardName = m.cardName ?? ""
        faceColor = cp.faceColor ?? WealthFacts.defaultFaceColor(m.id)
        remind = cp.remind != false
        if let b = m.billingDay { billingDay = Swift.min(Swift.max(b, 1), 31) }
        if let p = m.paymentDay { paymentDay = Swift.min(Swift.max(p, 1), 31) }
        if let l = m.creditLimit, l > 0 { limitText = WealthFormat.grouped(l, decimals: 0) }
        payMode = cp.mode
        payFrom = m.linkedBankMilestoneId
        cardLast4 = m.cardLastFour ?? ""
        cardCipher = m.cardNumberCipher
        securityCipher = m.cardSecurityCipher
        cardUnlocked = m.cardNumberCipher == nil && m.cardSecurityCipher == nil && m.expiryDate == nil
        wantsSecurity = m.cardSecurityCipher != nil
        if let e = m.expiryDate {
            hasExpiry = true
            expiry = e
        }
        if let a = m.annualFee, a > 0 { annualFeeText = WealthFormText.editable(a) }
        if let w = cp.feeWaiveAmount, w > 0 { waiveAmountText = WealthFormText.editable(w) }
        if let n = cp.feeWaiveCount, n > 0 { waiveCountText = "\(n)" }
        feeYearStart = cp.feeYearStartMonth ?? 0
        perks = cp.perksNote ?? ""
        easyCard = m.easyCardNumber ?? ""
        let rawIPass = m.iPassNumber ?? ""
        iPass = CardVault.isSafeToRegroup(rawIPass)
            ? CardVault.grouped(rawIPass, limit: CardVault.iPassDigits) : rawIPass
        happyGo = m.happyGoNumber ?? ""
    }

    mutating func loadPolicy(_ m: LifeMilestone, book: WealthBook) {
        let pp = book.policy(m.id)
        name = m.insuranceCompany ?? ""
        policyKind = pp.kind ?? WealthPolicyKind.from(legacy: m.insuranceType)
        insured = pp.insured ?? ""
        policyholder = pp.policyholder ?? ""
        beneficiary = m.beneficiary ?? ""
        if let p = m.premiumAmount, p > 0 { premiumText = WealthFormText.editable(p) }
        payCycle = pp.cycle ?? .year
        if let y = pp.payYears, y > 0 { payYearsText = "\(y)" }
        payFrom = pp.payFromId
        if let d = pp.nextDue {
            hasNextDue = true
            nextDue = d
        }
        coverageUntil = pp.coverageUntil ?? ""
        coverageText = (pp.coverageItems ?? []).joined(separator: "\n")
        policyNumber = m.policyNumber ?? ""
    }

    /// 寫進里程碑（身分＋舊欄位，給舊 iPad、網頁版、醫療地圖）。m 是 store 裡最新的那一筆（或新的）
    func apply(to m: inout LifeMilestone, kind: WealthAccountKind, sealed: WealthSealed) {
        m.title = title(kind: kind)
        m.date = date
        m.category = .achievement
        m.financeSubCategory = kind.sub
        m.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        m.photoFileNames = photos.isEmpty ? nil : photos
        let n: String? = Self.trimmed(name)
        let tail = accountTail
        switch kind {
        case .bank:
            m.bankName = n
            m.branchName = Self.trimmed(branch)
            m.accountNumber = tail.isEmpty ? nil : tail
            m.bankAccountType = bankType
        case .broker:
            m.bankName = n
            m.accountNumber = tail.isEmpty ? nil : tail
            m.securitiesAccountType = secType
        case .card:
            applyCard(to: &m, issuer: n, sealed: sealed)
        case .policy:
            m.insuranceCompany = n
            m.policyNumber = Self.trimmed(policyNumber)
            // 舊資料的車險讀進來是「其他」（WealthPolicyKind.from(legacy:)）；沒換險種就照舊留車險，
            // 不然存一次就變成壽險（醫療地圖、舊 iPad 照讀這一欄）
            if !(policyKind == .other && m.insuranceType == .car) {
                m.insuranceType = policyKind.legacyType
            }
            m.premiumAmount = WealthFormText.number(premiumText).flatMap { $0 > 0 ? $0 : nil }
            m.beneficiary = Self.trimmed(beneficiary)
        }
    }

    private func applyCard(to m: inout LifeMilestone, issuer: String?, sealed: WealthSealed) {
        m.bankName = issuer
        m.cardName = Self.trimmed(cardName)
        m.cardLastFour = sealed.cardLast4
        m.creditLimit = WealthFormText.limit(limitText)
        m.annualFee = WealthFormText.number(annualFeeText).flatMap { $0 > 0 ? $0 : nil }
        m.billingDay = billingDay > 0 ? billingDay : nil
        m.paymentDay = paymentDay > 0 ? paymentDay : nil
        m.linkedBankMilestoneId = payFrom
        m.cardNumberCipher = sealed.cardNumber
        m.cardSecurityCipher = sealed.security
        // 沒解鎖：有效期限看不到也改不了，照原本的留著
        if cardUnlocked { m.expiryDate = hasExpiry ? expiry : nil }
        m.easyCardNumber = Self.trimmed(easyCard)
        m.iPassNumber = Self.trimmed(iPass)
        m.happyGoNumber = Self.trimmed(happyGo)
    }

    /// 帳本 accounts[id]（base＝存檔那一刻帳本裡的，只改表單管的欄位）
    func accountPrefs(_ base: WealthAccountPrefs, kind: WealthAccountKind, sealed: WealthSealed) -> WealthAccountPrefs {
        var p = base
        p.nickname = Self.trimmed(nickname)
        let tail = accountTail
        switch kind {
        case .bank:
            p.accountLast4 = tail.isEmpty ? nil : tail
            p.accountNumberCipher = sealed.accountCipher
            p.currencies = currencies.isEmpty ? nil : currencies
            p.purpose = Self.trimmed(purpose)
            p.colorId = colorId
            p.countInCash = countsInCash ? nil : false
        case .broker:
            p.accountLast4 = tail.isEmpty ? nil : tail
            p.accountNumberCipher = sealed.accountCipher
            p.settlementBankId = settlementBankId
        case .card, .policy:
            break
        }
        return p
    }

    /// 帳本 cards[id]：卡費怎麼繳（改了才 setMode：改成自己繳／每次問我從今天起才追）、卡面色、年費、回饋小抄
    func cardPrefs(_ base: WealthCardPrefs, now: Date) -> WealthCardPrefs {
        var c = base
        if c.mode != payMode { c.setMode(payMode, now: now) }
        c.faceColor = faceColor
        // [v25.565] 開＝存 nil（跟沒設過一樣）、關＝存 false（WealthReminders 只看 != false）
        c.remind = remind ? nil : false
        c.perksNote = Self.trimmed(perks)
        c.feeWaiveAmount = WealthFormText.number(waiveAmountText).flatMap { $0 > 0 ? $0 : nil }
        let count: Int? = Int(waiveCountText.trimmingCharacters(in: .whitespaces))
        c.feeWaiveCount = count.flatMap { $0 > 0 ? $0 : nil }
        c.feeYearStartMonth = feeYearStart > 0 ? feeYearStart : nil
        return c
    }

    /// 帳本 policies[id]
    func policyPrefs(_ base: WealthPolicyPrefs) -> WealthPolicyPrefs {
        var p = base
        p.coverageKind = policyKind.rawValue
        p.insured = Self.trimmed(insured)
        p.policyholder = Self.trimmed(policyholder)
        p.payCycle = payCycle.rawValue
        let years: Int? = Int(payYearsText.trimmingCharacters(in: .whitespaces))
        p.payYears = payCycle == .single ? nil : years.flatMap { $0 > 0 ? $0 : nil }
        p.coverageUntil = Self.trimmed(coverageUntil)
        let lines: [String] = coverageText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let items: [String] = lines.filter { !$0.isEmpty }
        p.coverageItems = items.isEmpty ? nil : items
        p.nextDue = hasNextDue ? WealthCal.day(nextDue) : nil
        p.payFromId = payFrom
        return p
    }
}

/// [v25.563] 信用卡改扣款帳戶時問「從哪一期起」（D10）。v3 從履歷搬過來（履歷不再編輯財富帳戶）。
/// 拆成 modifier：表單的修飾器鏈已經很長，不再往 body 裡塞閉包
struct CardDebitChangeDialog: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    /// 「11 月帳單」
    let nextLabel: String
    let onNext: () -> Void
    let onAll: () -> Void

    private var nextButtonTitle: String { "從下一期（\(nextLabel)）起" }

    func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: $isPresented, titleVisibility: .visible) {
            Button(nextButtonTitle) { onNext() }
            Button("以前的帳單也改") { onAll() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("選下一期：以前的帳單照舊算在原本的帳戶，財富頁銀行的數字不會突然變。")
        }
    }
}

/// 卡號保管室的說明／錯誤（拆成 modifier，坑 #7）
struct WealthVaultMessageAlert: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.alert("卡號與安全資訊", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("好") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }
}

/// 刪銀行先問〔收起來就好〕〔仍要刪除〕（judge §5.6；拆成 modifier，坑 #7）
struct WealthBankDeleteDialog: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let onHide: () -> Void
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: $isPresented, titleVisibility: .visible) {
            Button("收起來就好") { onHide() }
            Button("仍要刪除", role: .destructive) { onDelete() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("收起來：不算進合計、選單不出現，以前的帳照算，可以再打開。")
        }
    }
}

/// 新增／編輯財富帳戶（judge §5）。onSaved：存好之後（履歷的里程碑表單要跟著關）
struct WealthAccountEditor: View {
    let kind: WealthAccountKind
    var editing: LifeMilestone? = nil
    var focus: WealthEditorFocus? = nil
    var onSaved: (() -> Void)? = nil

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var f = WealthAccountForm()
    /// 新增時里程碑的 id（照片檔名一打開就要用）
    @State private var draftId = UUID()
    @State private var loaded = false
    @State private var isSaving = false
    /// 選單（打開時抓一次）
    @State private var banks: [WealthFormAccountChoice] = []
    @State private var cards: [WealthFormAccountChoice] = []
    /// 設定裡的外幣（銀行帳戶勾幣別）
    @State private var foreignCodes: [String] = []
    /// 編輯前的扣款帳戶（帳戶已經不在了＝nil）
    @State private var originalPayFrom: UUID?
    /// 「編輯 CUBE」
    @State private var editName = ""
    @State private var unlocking = false
    @State private var vaultMessage: String?
    @State private var askDebitChange = false
    @State private var askBankDelete = false
    @State private var pendingDelete: FinanceDeletionImpact?
    @State private var showPremium = false
    /// 保單選了儲蓄險／車險／房屋險（導走，不在這裡記）
    @State private var redirect: Int?

    private static let redirects: [(title: String, message: String)] = [
        ("儲蓄險", "儲蓄險在理財 › 儲蓄險記，會算現在值多少、到期領多少。"),
        ("車險", "車險到理財 › 車子那張卡記，保費、到期日跟著車子。"),
        ("房屋險", "房屋險到理財 › 房屋那張卡記。")
    ]

    private var navTitle: String {
        if editing != nil { return "編輯 " + (editName.isEmpty ? kind.title : editName) }
        return "新增" + kind.title
    }

    private var canSave: Bool {
        guard redirect == nil else { return false }
        return !f.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var hasUnsavedPhotoChanges: Bool { f.photos != (editing?.photoFileNames ?? []) }

    /// 編輯中的卡改了扣款帳戶 → 存檔前問從哪一期起
    private var debitChangeNeedsAsking: Bool {
        guard kind == .card, editing != nil else { return false }
        return originalPayFrom != f.payFrom
    }

    /// 「下一期」＝明天起刷的那一期（結帳日用表單上的；沒填先當 25 日）
    private var nextStatement: (key: String, label: String) {
        WealthCardCycle.nextStatement(billingDay: f.billingDay > 0 ? f.billingDay : nil, now: Date())
    }

    private var debitChangeTitle: String {
        guard let id = f.payFrom else { return "這張卡不再設扣款帳戶，從哪一期開始？" }
        let name: String = banks.first(where: { $0.id == id })?.name ?? "新的帳戶"
        return "卡費改從「" + name + "」扣，從哪一期開始？"
    }

    private var bankDeleteTitle: String {
        "刪除" + (editName.isEmpty ? f.name : editName) + "？"
    }

    // MARK: 主體（修飾器拆兩段：表單一段、彈窗一段；坑 #7）

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                editorForm(proxy)
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                WealthSaveToolbar(title: "存", isSaving: isSaving, disabled: !canSave,
                                  onCancel: { cancel() }, onSave: { requestSave() })
            }
            .onAppear { load() }
        }
        .modifier(WealthVaultMessageAlert(message: $vaultMessage))
        .modifier(CardDebitChangeDialog(isPresented: $askDebitChange, title: debitChangeTitle,
                                        nextLabel: nextStatement.label,
                                        onNext: { save(payFromAll: false) },
                                        onAll: { save(payFromAll: true) }))
        .modifier(WealthBankDeleteDialog(isPresented: $askBankDelete, title: bankDeleteTitle,
                                         onHide: { hideBank() }, onDelete: { confirmBankDelete() }))
        .modifier(FinanceDeleteAlert(pending: $pendingDelete,
                                     onDisable: { m in disableCard(m) },
                                     onDelete: { m in deleteAccount(m) }))
        .premiumLockAlert(isPresented: $showPremium)
        .interactiveDismissDisabled(hasUnsavedPhotoChanges)
        .presentationDetents([.large])
        // 打到一半的號碼不收回，只蓋（這張表單是 sheet，掛在 App 最外層蓋不到，所以自己掛）
        .modifier(WealthPrivacyCurtain(armed: true))
    }

    private func editorForm(_ proxy: ScrollViewProxy) -> some View {
        Form {
            kindSections
            photoSection
            if editing != nil {
                deleteSection
            }
        }
        .task(id: loaded) { await scrollToFocus(proxy) }
    }

    @ViewBuilder
    private var kindSections: some View {
        switch kind {
        case .bank: bankSections
        case .card: cardSections
        case .broker: brokerSections
        case .policy: policySections
        }
    }

    /// 從要確認點進來：捲到那一段
    private func scrollToFocus(_ proxy: ScrollViewProxy) async {
        guard loaded, let target = focus else { return }
        try? await Task.sleep(nanoseconds: 350_000_000)
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(target.rawValue, anchor: .top)
        }
    }

    // MARK: 共用列

    /// 銀行名（常用清單＋自己打）
    private func nameRow(_ placeholder: String, list: [String]) -> some View {
        HStack {
            TextField(placeholder, text: $f.name)
            Menu {
                ForEach(list, id: \.self) { n in
                    Button(n) { f.name = n }
                }
            } label: {
                Image(systemName: "list.bullet.circle")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityLabel("常用清單")
        }
    }

    /// 6 個色點（卡面色；銀行帳戶的顏色也用這 6 個）。selected nil＝沒選
    private func colorDots(_ title: String, selected: Int?, onPick: @escaping (Int) -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { i in
                    colorDot(i, on: selected == i, onPick: onPick)
                }
            }
        }
    }

    private func colorDot(_ i: Int, on: Bool, onPick: @escaping (Int) -> Void) -> some View {
        let fill = LinearGradient(colors: [WealthCardPalette.top(i, dark: false), WealthCardPalette.bottom(i, dark: false)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        return Button {
            onPick(i)
        } label: {
            Circle()
                .fill(fill)
                .frame(width: 24, height: 24)
                .overlay(Circle().stroke(Color.primary.opacity(on ? 0.85 : 0), lineWidth: 2).padding(-3))
                .padding(3)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(WealthCardPalette.names[i])
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// 一顆膠囊（卡費怎麼繳、險種）
    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 34)
                .foregroundStyle(on ? Color.white : Color.primary)
                .background(on ? Color.indigo : Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.borderless)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var noteRow: some View {
        TextField("備註（選填）", text: $f.note, axis: .vertical)
            .lineLimit(1...4)
    }

    // MARK: 銀行帳戶（§5.1）

    @ViewBuilder
    private var bankSections: some View {
        Section {
            nameRow("銀行", list: WealthNameLists.banks)
            TextField("暱稱（選填，例：薪轉）", text: $f.nickname)
            TextField("分行（選填）", text: $f.branch)
        } header: {
            WealthFormHeader(title: "這個帳戶", icon: "building.columns.fill", color: .blue)
        }
        accountNumberSection
        bankTypeSection
        if editing == nil {
            openingSection
        }
        Section {
            purposePicker
            colorDots("顏色", selected: f.colorId, onPick: { i in f.colorId = (f.colorId == i) ? nil : i })
            Toggle("算進存款合計", isOn: $f.countsInCash)
            DatePicker("開戶日", selection: $f.date, displayedComponents: .date)
            noteRow
        } header: {
            WealthFormHeader(title: "其他", icon: "slider.horizontal.3", color: .secondary)
        } footer: {
            Text("小孩的戶頭可以列著、不算進存款合計。")
        }
    }

    private var accountNumberSection: some View {
        Section {
            HStack {
                Text("帳號末 4 碼")
                Spacer()
                TextField("7890", text: $f.last4)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.body.monospaced())
                    .frame(maxWidth: 120)
                    .onChange(of: f.last4) { _, v in
                        let d = WealthFormText.digits(v, limit: 4)
                        if d != v { f.last4 = d }
                    }
            }
            Toggle("存完整帳號（加密）", isOn: $f.storeFullNumber.animation())
            if f.storeFullNumber {
                fullNumberRow
            }
        } header: {
            WealthFormHeader(title: "帳號", icon: "lock.shield.fill", color: .red)
        } footer: {
            Text(accountFootnote)
        }
    }

    private var accountFootnote: String {
        if f.legacyFullNumber {
            return "以前記的完整帳號是沒加密的；存檔後改成加密存，列表、選單只露末 4 碼。還沒更新的 iPad 上只看得到末 4 碼。"
        }
        return "列表、選單、卡面只用末 4 碼。完整帳號要打開開關才存，加密後才存起來，要看得先過 Face ID。"
    }

    @ViewBuilder
    private var fullNumberRow: some View {
        if f.accountUnlocked {
            VStack(alignment: .leading, spacing: 4) {
                Text(f.legacyFullNumber ? "完整帳號（舊的，存檔後改成加密）" : "完整帳號")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                SecureField("打完整帳號", text: $f.fullNumber)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.body.monospaced())
                    .onChange(of: f.fullNumber) { _, v in fullNumberChanged(v) }
            }
        } else {
            Button {
                unlockAccount()
            } label: {
                HStack {
                    Text("完整帳號").foregroundStyle(Color.primary)
                    Spacer()
                    Text("•••• " + f.last4)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                    Image(systemName: unlocking ? "hourglass" : "lock.fill")
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                }
                .contentShape(Rectangle())
            }
            .disabled(unlocking)
        }
    }

    /// 打了完整帳號：末 4 碼跟著帶
    private func fullNumberChanged(_ v: String) {
        let d = v.filter { $0.isASCII && $0.isNumber }
        if d.count >= 4 { f.last4 = String(d.suffix(4)) }
    }

    private var bankTypeSection: some View {
        Section {
            if f.bankType == .fixed {
                LabeledContent("種類", value: "定存（以前記的）")
            } else {
                Picker("種類", selection: $f.bankType) {
                    Text(BankAccountType.savings.rawValue).tag(BankAccountType.savings)
                    Text(BankAccountType.foreign.rawValue).tag(BankAccountType.foreign)
                }
                .pickerStyle(.segmented)
            }
            LabeledContent("台幣", value: "一定有")
            ForEach(foreignCodes, id: \.self) { code in
                Toggle(code, isOn: currencyBinding(code))
            }
        } header: {
            WealthFormHeader(title: "種類與幣別", icon: "dollarsign.circle.fill", color: .teal)
        } footer: {
            Text(bankTypeFootnote)
        }
    }

    /// [v25.566] 定存不是帳戶種類（judge §5.1、§5.5）：記在帳戶裡
    private static let depositTypeHint = "定存不是帳戶種類：存好帳戶後，到帳戶頁按〔＋ 定存〕記本金、利率、到期日。"

    /// 「種類與幣別」footer：外幣一句＋[v25.566] 定存一句
    private var bankTypeFootnote: String {
        let currencies: String = foreignCodes.isEmpty
            ? "要記外幣，先到設定 › 匯率加幣別。"
            : "勾這個帳戶有的外幣；存提款、對存摺都分幣別記。"
        return currencies + "\n" + Self.depositTypeHint
    }

    private func currencyBinding(_ code: String) -> Binding<Bool> {
        Binding(
            get: { f.currencies.contains(code) },
            set: { on in
                if on {
                    if !f.currencies.contains(code) { f.currencies.append(code) }
                } else {
                    f.currencies.removeAll { $0 == code }
                }
            }
        )
    }

    private var openingCodes: [String] { ["NT$"] + f.currencies }

    private var openingSection: some View {
        Section {
            ForEach(openingCodes, id: \.self) { code in
                openingRow(code)
            }
        } header: {
            WealthFormHeader(title: "今天存摺上有多少", icon: "checkmark.seal.fill", color: .orange)
        } footer: {
            Text("不知道可以先空著。存成第一次「對存摺」，以前的每一筆不用補，之後記的都從這裡往後算。")
        }
    }

    private func openingRow(_ code: String) -> some View {
        HStack {
            Text(code == "NT$" ? "台幣" : code)
            Spacer()
            TextField(code == "NT$" ? "例：128,400" : "例：3,200.00", text: openingBinding(code))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }

    private func openingBinding(_ code: String) -> Binding<String> {
        Binding(get: { f.openings[code] ?? "" }, set: { f.openings[code] = $0 })
    }

    private var purposeOptions: [String] {
        var list = WealthNameLists.purposes
        let p = f.purpose.trimmingCharacters(in: .whitespaces)
        if !p.isEmpty && !list.contains(p) { list.append(p) }
        return list
    }

    private var purposePicker: some View {
        Picker("用途", selection: $f.purpose) {
            Text("不填").tag("")
            ForEach(purposeOptions, id: \.self) { p in
                Text(p).tag(p)
            }
        }
    }

    // MARK: 信用卡（§5.2；安全碼照留）

    @ViewBuilder
    private var cardSections: some View {
        Section {
            nameRow("發卡銀行", list: WealthNameLists.banks)
            TextField("卡名（例：CUBE 卡）", text: $f.cardName)
            TextField("暱稱（選填）", text: $f.nickname)
            colorDots("卡面顏色", selected: f.faceColor, onPick: { i in f.faceColor = i })
        } header: {
            WealthFormHeader(title: "這張卡", icon: "creditcard.fill", color: .orange)
        } footer: {
            Text("發卡銀行只是卡上印的銀行，跟卡費從哪個帳戶扣可以不一樣（玉山的卡可以從台新扣）。")
        }
        cardBillSection
        payModeSection
        remindSection
        cardVaultSection
        cardFeeSection
        Section {
            TextField("悠遊卡卡號（選填）", text: $f.easyCard)
                .keyboardType(.numbersAndPunctuation)
            TextField("一卡通卡號（選填，16 碼）", text: $f.iPass)
                .keyboardType(.numberPad)
                .font(.body.monospaced())
                .onChange(of: f.iPass) { _, v in
                    let g = CardVault.grouped(v, limit: CardVault.iPassDigits)
                    if g != v { f.iPass = g }
                }
            TextField("Happy Go 卡號（選填）", text: $f.happyGo)
                .keyboardType(.numbersAndPunctuation)
        } header: {
            WealthFormHeader(title: "綁定的票證與會員", icon: "wallet.pass.fill", color: .teal)
        }
        Section {
            DatePicker("核卡日", selection: $f.date, displayedComponents: .date)
            noteRow
        } header: {
            WealthFormHeader(title: "其他", icon: "slider.horizontal.3", color: .secondary)
        }
    }

    private var cardBillSection: some View {
        Section {
            dayWheelRow("結帳日", selection: $f.billingDay)
                .id(WealthEditorFocus.cardDays.rawValue)
            dayWheelRow("繳款截止日", selection: $f.paymentDay)
            limitRow
        } header: {
            WealthFormHeader(title: "帳單", icon: "calendar", color: .orange)
        } footer: {
            Text(cardDaysFootnote)
        }
    }

    private var cardDaysFootnote: String {
        if f.billingDay > 0, f.paymentDay > 0, f.paymentDay <= f.billingDay {
            return "截止日比結帳日小，就是下個月 \(f.paymentDay) 日。小月沒有那一天就取月底。"
        }
        if f.billingDay == 0 || f.paymentDay == 0 {
            return "沒填的話先當每月 25 日結帳、隔月 15 日繳；照帳單上寫的填，數字才準。"
        }
        return "叫法跟帳單一樣；小月沒有那一天就取月底。"
    }

    /// 一個轉盤一列（兩個轉盤並排時會搶到對方的手勢，所以分兩列）
    private func dayWheelRow(_ title: String, selection: Binding<Int>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker(title, selection: selection) {
                Text("沒填").tag(0)
                ForEach(1...31, id: \.self) { d in
                    Text("每月 \(d) 日").tag(d)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 150, height: 96)
            .clipped()
        }
    }

    private var limitRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("額度")
                Spacer()
                TextField("68,000 或 6.8萬", text: $f.limitText)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
            }
            if let v = WealthFormText.limit(f.limitText) {
                Text("＝ " + v.ntdWanString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var payModeSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(WealthPayMode.allCases) { m in
                    chip(m.title, on: f.payMode == m, action: { f.payMode = m })
                }
            }
            .padding(.vertical, 4)
            Text(payModeNote)
                .font(.caption)
                .foregroundStyle(.secondary)
            payFromPicker
                .id(WealthEditorFocus.payFrom.rawValue)
        } header: {
            WealthFormHeader(title: "卡費怎麼繳", icon: "arrow.uturn.left.circle.fill", color: .orange)
        } footer: {
            Text("發卡銀行跟扣款帳戶可以不一樣（玉山的卡從台新扣）。")
        }
    }

    private var payModeNote: String {
        switch f.payMode {
        case .autoFull:
            return "每期在繳款截止日從扣款帳戶扣全額。"
        case .autoMin:
            return "截止日只扣最低應繳（約 10%），剩下的算進下期帳單，會有循環利息。"
        case .manual:
            return "你自己繳。過了截止日還沒標已繳，App 當作你從「通常從」的帳戶在截止日繳了全額，隔天在要確認問你一次。"
        case .askEachTime:
            return "過了截止日不當作已繳，在要確認問你繳了沒；還沒繳就算逾期。"
        }
    }

    /// [v25.565] 提醒我繳卡費（WealthCardPrefs.remind；通知由 WealthReminders 排，不寫卡名、金額、號碼）
    private var remindSection: some View {
        Section {
            Toggle("提醒我繳卡費", isOn: $f.remind)
        } header: {
            WealthFormHeader(title: "提醒", icon: "bell.badge.fill", color: .orange)
        } footer: {
            Text(Self.remindFootnote)
        }
    }

    static let remindFootnote =
        "截止前 3 天、當天早上 9 點；自動扣的卡只在可能不夠扣時提醒。通知不寫卡名和金額。"
        + "設定裡的「財富提醒」關掉就全部不提醒。"

    private var payFromPicker: some View {
        Picker(f.payMode.isAuto ? "扣款帳戶" : "通常從", selection: $f.payFrom) {
            Text("不設").tag(nil as UUID?)
            ForEach(banks) { c in
                Text(c.label).tag(c.id as UUID?)
            }
        }
    }

    private var cardVaultSection: some View {
        Section {
            cardNumberRows
            cardExpiryRows
            cardSecurityRows
        } header: {
            WealthFormHeader(title: "卡號與安全", icon: "lock.shield.fill", color: .red)
        } footer: {
            Text(Self.cardVaultFootnote)
        }
    }

    static let cardVaultFootnote =
        "完整卡號、有效期限、檢核碼會加密後才存起來，金鑰放在系統鑰匙圈，備份檔與桌面網頁版都讀不到明碼。"
        + "要看或修改一定要先通過 Face ID 或裝置密碼。檢核碼預設不記，由你自己決定。"

    @ViewBuilder
    private var cardNumberRows: some View {
        if f.cardUnlocked {
            HStack {
                Text("卡號")
                Spacer()
                TextField("打完整卡號，加密存", text: $f.cardNumber)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.body.monospaced())
                    .onChange(of: f.cardNumber) { _, v in cardNumberChanged(v) }
            }
        } else {
            Button {
                unlockCard()
            } label: {
                HStack {
                    Text("卡號").foregroundStyle(Color.primary)
                    Spacer()
                    Text(CardVault.masked(lastFour: f.cardLast4))
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                    Image(systemName: unlocking ? "hourglass" : "lock.fill")
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                }
                .contentShape(Rectangle())
            }
            .disabled(unlocking)
        }
        HStack {
            Text("末 4 碼")
            Spacer()
            TextField("5678", text: $f.cardLast4)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospaced())
                .frame(maxWidth: 100)
                .disabled(!f.cardUnlocked || !f.cardNumber.isEmpty)
                .onChange(of: f.cardLast4) { _, v in
                    let d = WealthFormText.digits(v, limit: 4)
                    if d != v { f.cardLast4 = d }
                }
        }
    }

    /// 邊打邊每四碼補「-」；末 4 碼跟著帶
    private func cardNumberChanged(_ v: String) {
        let g = CardVault.grouped(v)
        if g != v {
            f.cardNumber = g
            return
        }
        let tail = CardVault.lastFour(g)
        if !tail.isEmpty { f.cardLast4 = tail }
    }

    /// 有效期限：跟卡號同一把鎖
    @ViewBuilder
    private var cardExpiryRows: some View {
        if f.cardUnlocked {
            Toggle("填有效期限", isOn: $f.hasExpiry)
            if f.hasExpiry {
                expiryPicker
            }
        } else {
            HStack {
                Text("有效期限")
                Spacer()
                Text(f.hasExpiry ? "••/••" : "未填")
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
            }
        }
    }

    /// 年＋月兩個選單（有效期限只記到月；西曆）
    private var expiryPicker: some View {
        let cal = WealthCal.calendar
        let nowYear = cal.component(.year, from: Date())
        let years: [Int] = Array((nowYear - 2)...(nowYear + 20))
        let yearBinding = Binding<Int>(
            get: { cal.component(.year, from: f.expiry) },
            set: { y in setExpiry(year: y, month: nil) }
        )
        let monthBinding = Binding<Int>(
            get: { cal.component(.month, from: f.expiry) },
            set: { m in setExpiry(year: nil, month: m) }
        )
        return HStack {
            Text("到期").foregroundStyle(.secondary)
            Spacer()
            Picker("年", selection: yearBinding) {
                ForEach(years, id: \.self) { y in
                    Text(String(y) + " 年").tag(y)
                }
            }
            .pickerStyle(.menu)
            Picker("月", selection: monthBinding) {
                ForEach(1...12, id: \.self) { m in
                    Text("\(m) 月").tag(m)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private func setExpiry(year: Int?, month: Int?) {
        let cal = WealthCal.calendar
        var c = cal.dateComponents([.year, .month], from: f.expiry)
        if let year { c.year = year }
        if let month { c.month = month }
        c.day = 1
        if let d = cal.date(from: c) { f.expiry = d }
    }

    /// 檢核碼：完全由你決定要不要記（第 6 題「我要存」：開關照留，預設關）
    @ViewBuilder
    private var cardSecurityRows: some View {
        if f.cardUnlocked {
            Toggle("記錄檢核碼（CVV／CVC）", isOn: $f.wantsSecurity.animation())
            if f.wantsSecurity {
                HStack {
                    Text("檢核碼")
                    Spacer()
                    SecureField("3 碼", text: $f.security)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                        .onChange(of: f.security) { _, v in
                            let d = WealthFormText.digits(v, limit: 4)
                            if d != v { f.security = d }
                        }
                }
            }
        } else if f.securityCipher != nil {
            HStack {
                Text("檢核碼")
                Spacer()
                Text(CardVault.maskedCode())
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
            }
        }
    }

    private var cardFeeSection: some View {
        Section {
            HStack {
                Text("年費")
                Spacer()
                TextField("0", text: $f.annualFeeText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Text("免年費：一年刷滿")
                Spacer()
                TextField("元", text: $f.waiveAmountText)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Text("或刷滿幾筆")
                Spacer()
                TextField("筆", text: $f.waiveCountText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            Picker("卡片年度從", selection: $f.feeYearStart) {
                Text("1 月（跟日曆一樣）").tag(0)
                ForEach(2...12, id: \.self) { m in
                    Text("\(m) 月").tag(m)
                }
            }
            TextField("回饋小抄（例：玩數位 3%，每期上限 300 點）", text: $f.perks, axis: .vertical)
                .lineLimit(2...6)
        } header: {
            WealthFormHeader(title: "年費與回饋", icon: "gift.fill", color: .pink)
        } footer: {
            Text("免年費只認「一年刷滿 N 元」「刷滿 N 筆」；卡片頁會算你今年刷到哪了。")
        }
    }

    // MARK: 證券戶（§5.3）

    @ViewBuilder
    private var brokerSections: some View {
        Section {
            nameRow("券商", list: WealthNameLists.brokers)
            TextField("暱稱（選填）", text: $f.nickname)
        } header: {
            WealthFormHeader(title: "這個證券戶", icon: "chart.line.uptrend.xyaxis", color: .purple)
        }
        accountNumberSection
        Section {
            Picker("交割銀行", selection: $f.settlementBankId) {
                Text("沒選（照股票最常用的）").tag(nil as UUID?)
                ForEach(banks) { c in
                    Text(c.label).tag(c.id as UUID?)
                }
            }
            .id(WealthEditorFocus.settlement.rawValue)
            Picker("類型", selection: $f.secType) {
                ForEach(SecuritiesAccountType.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            DatePicker("開戶日", selection: $f.date, displayedComponents: .date)
            noteRow
        } header: {
            WealthFormHeader(title: "交割與其他", icon: "building.columns.fill", color: .purple)
        } footer: {
            Text("持股、買賣、股利在理財 › 股票記；選了這個證券戶的股票會自動出現在這裡。")
        }
    }

    // MARK: 保單（§5.4；保障型）

    @ViewBuilder
    private var policySections: some View {
        policyKindSection
        Section {
            nameRow("保險公司", list: WealthNameLists.insurers)
            TextField("保單名稱（選填，例：住院醫療）", text: $f.nickname)
            TextField("被保險人（選填）", text: $f.insured)
            TextField("要保人（選填）", text: $f.policyholder)
            TextField("受益人（選填）", text: $f.beneficiary)
        } header: {
            WealthFormHeader(title: "這張保單", icon: "person.text.rectangle.fill", color: .green)
        }
        policyPremiumSection
        Section {
            DatePicker("生效日", selection: $f.date, displayedComponents: .date)
            TextField("保障到（例：終身、2045、75 歲）", text: $f.coverageUntil)
            TextField("保障內容（一行一項，例：住院日額 2,000／天）", text: $f.coverageText, axis: .vertical)
                .lineLimit(2...8)
            TextField("保單號碼（選填）", text: $f.policyNumber)
            noteRow
        } header: {
            WealthFormHeader(title: "保障", icon: "cross.case.fill", color: .green)
        }
    }

    private var policyKindSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(WealthPolicyKind.allCases) { k in
                    chip(k.shortTitle, on: redirect == nil && f.policyKind == k, action: { pickPolicyKind(k) })
                }
                ForEach(Self.redirects.indices, id: \.self) { i in
                    chip(Self.redirects[i].title, on: redirect == i, action: { redirect = i })
                }
            }
            .padding(.vertical, 4)
            if let i = redirect {
                Text(Self.redirects[i].message)
                    .font(.subheadline)
                    .foregroundStyle(Color.orange)
            } else {
                Text(f.policyKind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            WealthFormHeader(title: "險種", icon: "shield.fill", color: .green)
        }
    }

    private func pickPolicyKind(_ k: WealthPolicyKind) {
        redirect = nil
        f.policyKind = k
    }

    private var policyPremiumSection: some View {
        Section {
            HStack {
                Text("保費")
                Spacer()
                TextField("每次繳多少", text: $f.premiumText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            Picker("繳法", selection: $f.payCycle) {
                ForEach(WealthPolicyCycle.allCases) { c in
                    Text(c.title).tag(c)
                }
            }
            if f.payCycle != .single {
                HStack {
                    Text("繳費年期")
                    Spacer()
                    TextField("年", text: $f.payYearsText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
            }
            Picker("從哪扣", selection: $f.payFrom) {
                Text("沒填").tag(nil as UUID?)
                ForEach(banks) { c in
                    Text(c.label).tag(c.id as UUID?)
                }
                ForEach(cards) { c in
                    Text(c.label).tag(c.id as UUID?)
                }
            }
            Toggle("填下次扣款日", isOn: $f.hasNextDue)
            if f.hasNextDue {
                DatePicker("下次扣款日", selection: $f.nextDue, displayedComponents: .date)
            }
        } header: {
            WealthFormHeader(title: "保費", icon: "calendar.badge.clock", color: .green)
        } footer: {
            Text("保費的記帳照舊在記帳裡記；連起來、自動建記帳在下一版。")
        }
    }

    // MARK: 照片、刪除

    private var photoTitle: String {
        switch kind {
        case .card: return "權益與說明照片"
        case .policy: return "保單照片"
        case .bank, .broker: return "照片"
        }
    }

    private var photoFootnote: String {
        switch kind {
        case .card:
            return "權益說明、優惠 DM、帳單說明都可以拍；請不要拍卡片正面或背面——卡號和檢核碼填在上面的「卡號與安全」，那裡會加密。"
        case .bank, .broker:
            return "請不要拍存摺內頁的完整帳號；完整帳號填在上面，那裡會加密。"
        case .policy:
            return "保單首頁、保障內容都可以拍下來。"
        }
    }

    private var photoSection: some View {
        let id = editing?.id ?? draftId
        return Section {
            MultiPhotoGallery(
                fileNames: $f.photos,
                urlFor: { LifeMilestone.photoURL(for: $0) },
                onSaveImage: { LifeMilestone.savePhoto($0, milestoneId: id) },
                onDeleteFile: { LifeMilestone.deletePhoto($0) },
                onSavePDF: { LifeMilestone.savePDF($0, milestoneId: id) },
                title: photoTitle
            )
            .padding(.vertical, 4)
        } header: {
            WealthFormHeader(title: photoTitle, icon: "doc.text.image", color: .orange)
        } footer: {
            Text(photoFootnote).font(.caption2)
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                deleteTapped()
            } label: {
                Text(kind == .card ? "刪除這張卡" : "刪除這個帳戶")
                    .frame(maxWidth: .infinity)
            }
        } footer: {
            Text(kind == .card ? "不用了可以先停用：記帳選單不出現，以前刷的帳照算。"
                 : "不用了可以先收起來：不算進合計，以前的帳照算。")
        }
    }

    // MARK: 帶入

    private func load() {
        guard !loaded else { return }
        let facts = lifeStore.wealthFacts(expense: expenseStore, finance: financeStore)
        let book = lifeStore.wealthBook
        var form = WealthAccountForm()
        if let m = editing {
            form = WealthAccountForm.load(m, kind: kind, book: book)
            editName = WealthFacts.displayName(of: m, book: book)
            // v2 的帳戶沒勾過幣別：已經有外幣紀錄的那幾個先勾好（一套數字本來就把它們算進這個帳戶）
            if kind == .bank, let a = facts.account(m.id) {
                for c in a.currencies where !FinanceRates.isNTD(c) && !form.currencies.contains(c) {
                    form.currencies.append(c)
                }
            }
        } else {
            form.faceColor = WealthFacts.defaultFaceColor(draftId)
        }
        let extra: UUID? = kind == .broker ? form.settlementBankId : form.payFrom
        banks = WealthFormAccountChoice.banks(facts, including: extra, excluding: editing?.id)
        cards = kind == .policy ? WealthFormAccountChoice.cards(facts) : []
        // 指到已經不在的帳戶：選單對不上，先當沒設（要確認 #7 會帶你來選）
        if let p = form.payFrom, !banks.contains(where: { $0.id == p }), !cards.contains(where: { $0.id == p }) {
            form.payFrom = nil
        }
        if let s = form.settlementBankId, !banks.contains(where: { $0.id == s }) {
            form.settlementBankId = nil
        }
        originalPayFrom = kind == .card ? form.payFrom : nil
        var codes: [String] = []
        for r in expenseStore.currencyRates where !FinanceRates.isNTD(r.code) && !codes.contains(r.code) {
            codes.append(r.code)
        }
        for c in form.currencies where !codes.contains(c) { codes.append(c) }
        foreignCodes = codes
        f = form
        loaded = true
    }

    // MARK: 解鎖（Face ID）

    private func unlockCard() {
        guard !unlocking else { return }
        unlocking = true
        Task { @MainActor in
            defer { unlocking = false }
            switch await CardVault.unlock(reason: "檢視或修改完整卡號") {
            case .ok:
                let number = Self.openIfKey(f.cardCipher) ?? ""
                let code = Self.openIfKey(f.securityCipher) ?? ""
                f.cardNumber = CardVault.grouped(number)
                f.security = code
                // 這台解不開（沒有金鑰）：欄位空著，存檔時原本的密文照留（sealVault）；重打才換掉
                f.cardVaultLost = f.cardCipher != nil && number.isEmpty
                f.securityVaultLost = f.securityCipher != nil && code.isEmpty
                f.wantsSecurity = !code.isEmpty || f.securityVaultLost
                if f.cardVaultLost || f.securityVaultLost {
                    vaultMessage = Self.missingKeyMessage(f.cardVaultLost ? "卡號" : "檢核碼")
                }
                f.cardUnlocked = true
            case .denied:
                break
            case .unavailable(let message):
                vaultMessage = message
            }
        }
    }

    private func unlockAccount() {
        guard !unlocking else { return }
        unlocking = true
        Task { @MainActor in
            defer { unlocking = false }
            switch await CardVault.unlock(reason: "檢視或修改完整帳號") {
            case .ok:
                let number = Self.openIfKey(f.accountCipher) ?? ""
                f.accountVaultLost = f.accountCipher != nil && number.isEmpty
                if number.isEmpty {
                    vaultMessage = Self.missingKeyMessage("帳號")
                }
                f.fullNumber = number
                f.accountUnlocked = true
            case .denied:
                break
            case .unavailable(let message):
                vaultMessage = message
            }
        }
    }

    /// 這台有金鑰才解：沒有金鑰時 CardVault.open 會先產生一把新的寫進 iCloud 鑰匙圈（可能蓋掉別台那把），
    /// 新的那把也解不開原本的密文——直接當作解不開（欄位空著、存檔時原本的密文照留）
    private static func openIfKey(_ cipher: Data?) -> String? {
        guard CardVault.hasKey else { return nil }
        return CardVault.open(cipher)
    }

    private static func missingKeyMessage(_ what: String) -> String {
        "這台裝置沒有解密金鑰，看不到原本存的完整" + what + "。"
            + "金鑰是透過 iCloud 鑰匙圈同步的，請確認「設定 → Apple ID → iCloud → 密碼與鑰匙圈」已開啟；"
            + "若金鑰已經遺失，只能重新輸入一次。沒有重新輸入就存的話，原本存的會照樣留著。"
    }

    private static func sealFailedMessage(_ what: String) -> String {
        what + "加密失敗：系統鑰匙圈寫不進金鑰，這次沒有儲存。"
            + "請把 App 完全關掉再打開試一次；若持續失敗，請確認裝置已設定密碼。"
    }

    // MARK: 存檔

    /// 存：要訂閱（第 10 題）；卡改了扣款帳戶先問從哪一期起
    private func requestSave() {
        guard !isSaving, canSave else { return }
        guard subscription.isPremium else {
            showPremium = true
            return
        }
        if debitChangeNeedsAsking {
            askDebitChange = true
        } else {
            save(payFromAll: nil)
        }
    }

    /// 號碼封成密文（主執行緒）；鑰匙圈寫不進金鑰就不存並提示（nil）
    private func sealVault() -> WealthSealed? {
        var out = WealthSealed()
        switch kind {
        case .bank, .broker:
            if !f.storeFullNumber {
                out.accountCipher = nil
            } else if !f.accountUnlocked {
                out.accountCipher = f.accountCipher
            } else {
                let full = f.fullNumber.trimmingCharacters(in: .whitespaces)
                if !full.isEmpty {
                    guard let c = CardVault.seal(full) else {
                        vaultMessage = Self.sealFailedMessage("完整帳號")
                        return nil
                    }
                    out.accountCipher = c
                } else if f.accountVaultLost {
                    // 這台解不開、你也沒重打：原本的密文照留（不然別台存的完整帳號會被洗掉）
                    out.accountCipher = f.accountCipher
                }
            }
        case .card:
            let typed = WealthFormText.digits(f.cardLast4, limit: 4)
            if f.cardUnlocked {
                let digits = CardVault.digits(f.cardNumber)
                if !digits.isEmpty {
                    guard let c = CardVault.seal(digits) else {
                        vaultMessage = Self.sealFailedMessage("卡號")
                        return nil
                    }
                    out.cardNumber = c
                } else if f.cardVaultLost {
                    // 這台解不開、你也沒重打：原本的密文照留（不然別台存的卡號會被洗掉）
                    out.cardNumber = f.cardCipher
                }
                let code = f.security.trimmingCharacters(in: .whitespaces)
                if f.wantsSecurity && !code.isEmpty {
                    guard let c = CardVault.seal(code) else {
                        vaultMessage = Self.sealFailedMessage("檢核碼")
                        return nil
                    }
                    out.security = c
                } else if f.wantsSecurity && f.securityVaultLost {
                    // 同上：開關還開著、沒重打 → 原本的檢核碼密文照留（使用者第 6 題「我要存」）；你自己關掉開關才刪
                    out.security = f.securityCipher
                }
                let derived = CardVault.lastFour(f.cardNumber)
                let tail = derived.isEmpty ? typed : derived
                out.cardLast4 = tail.isEmpty ? nil : tail
            } else {
                // 沒解鎖：看不到內容，原封帶回既有密文（絕不能洗掉）
                out.cardNumber = f.cardCipher
                out.security = f.securityCipher
                out.cardLast4 = typed.isEmpty ? nil : typed
            }
        case .policy:
            break
        }
        return out
    }

    /// payFromAll：卡改了扣款帳戶時確認框選的（true＝以前的帳單也改；false／nil＝從下一期起）。
    /// 先關畫面、下一個 runloop 才寫：里程碑一次＋帳本一次（LifeStore.saveWealthAccount），改扣款帳戶再記一段歷史
    private func save(payFromAll: Bool?) {
        guard !isSaving, canSave else { return }
        guard let sealed = sealVault() else { return }
        isSaving = true
        let form = f
        let k = kind
        let id: UUID = editing?.id ?? draftId
        let isNew = editing == nil
        let base: LifeMilestone = editing
            ?? LifeMilestone(id: id, title: "", category: .achievement, financeSubCategory: kind.sub)
        let changePayFrom = debitChangeNeedsAsking
        let oldPayFrom = originalPayFrom
        let fromKey: String? = payFromAll == true ? nil : nextStatement.key
        let life = lifeStore
        let done = onSaved
        dismiss()
        DispatchQueue.main.async {
            var m: LifeMilestone = life.milestones.first(where: { $0.id == id }) ?? base
            form.apply(to: &m, kind: k, sealed: sealed)
            let book = life.wealthBook
            let prefs = form.accountPrefs(book.account(id), kind: k, sealed: sealed)
            let card: WealthCardPrefs? = k == .card ? form.cardPrefs(book.card(id), now: Date()) : nil
            let policy: WealthPolicyPrefs? = k == .policy ? form.policyPrefs(book.policy(id)) : nil
            let openings: [String: Double] = (isNew && k == .bank) ? form.openingBalances : [:]
            life.saveWealthAccount(m, prefs: prefs, card: card, policy: policy, openingBalances: openings)
            if changePayFrom {
                life.recordCardPayFromChange(cardId: id, oldAccount: oldPayFrom, newAccount: form.payFrom,
                                             fromKey: fromKey)
            }
            done?()
        }
    }

    /// 取消：這次新加的照片刪掉；這次刪掉的舊照片檔已經沒了，把原本那一筆的檔名清單改成還在的那些
    private func cancel() {
        let original: [String] = editing?.photoFileNames ?? []
        let originalSet = Set(original)
        for name in f.photos where !originalSet.contains(name) {
            LifeMilestone.deletePhoto(name)
        }
        let kept = Set(f.photos)
        let remaining: [String] = original.filter { kept.contains($0) }
        let editId: UUID? = editing?.id
        let changed = remaining.count != original.count
        let life = lifeStore
        dismiss()
        guard changed, let editId else { return }
        DispatchQueue.main.async {
            guard var latest = life.milestones.first(where: { $0.id == editId }) else { return }
            latest.photoFileNames = remaining.isEmpty ? nil : remaining
            life.update(latest)
        }
    }

    // MARK: 刪除（要訂閱；卡先建議停用、銀行先建議收起來）

    private func deleteTapped() {
        guard let m = editing else { return }
        guard subscription.isPremium else {
            showPremium = true
            return
        }
        if kind == .bank {
            askBankDelete = true
        } else {
            pendingDelete = lifeStore.financeDeletionImpact(m, finance: financeStore, expense: expenseStore)
        }
    }

    /// 〔仍要刪除〕：確認框收起來之後才跳「會動到什麼」（同一刻疊兩個彈窗，iOS 會把第二個吃掉）
    private func confirmBankDelete() {
        guard let m = editing else { return }
        let impact = lifeStore.financeDeletionImpact(m, finance: financeStore, expense: expenseStore)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            pendingDelete = impact
        }
    }

    private func hideBank() {
        guard let m = editing else { return }
        let life = lifeStore
        let id = m.id
        dismiss()
        DispatchQueue.main.async { life.setWealthHidden(id, hidden: true) }
    }

    private func disableCard(_ m: LifeMilestone) {
        let life = lifeStore
        let id = m.id
        dismiss()
        DispatchQueue.main.async { life.setCardDisabled(id, disabled: true) }
    }

    private func deleteAccount(_ m: LifeMilestone) {
        let life = lifeStore
        let fs = financeStore
        let es = expenseStore
        dismiss()
        DispatchQueue.main.async { life.deleteFinanceMilestone(m, finance: fs, expense: es) }
    }
}

/// 記一筆的種類（存款／提款／利息／手續費；轉帳、對存摺另外兩張小表單）
enum WealthRecordKind: String, CaseIterable, Identifiable {
    case deposit, withdrawal, interest, fee

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deposit: return "存款"
        case .withdrawal: return "提款"
        case .interest: return "利息"
        case .fee: return "手續費"
        }
    }
}

extension WealthRecordKind {
    /// 錢是不是離開帳戶（提款、手續費）
    var isOutflow: Bool { self == .withdrawal || self == .fee }

    /// BankDeposit.kind 的值
    var depositKind: String {
        switch self {
        case .deposit: return BankDeposit.kindDeposit
        case .withdrawal: return BankDeposit.kindWithdrawal
        case .interest: return BankDeposit.kindInterest
        case .fee: return BankDeposit.kindFee
        }
    }

    /// 以前記的那一筆是哪一種（舊資料沒有 kind：照 isWithdrawal）
    static func of(_ dep: BankDeposit) -> WealthRecordKind {
        let k: String = dep.kind ?? ""
        if k == BankDeposit.kindInterest { return .interest }
        if k == BankDeposit.kindFee { return .fee }
        if k == BankDeposit.kindWithdrawal { return .withdrawal }
        if k == BankDeposit.kindDeposit { return .deposit }
        return dep.isWithdrawal ? .withdrawal : .deposit
    }
}

// MARK: - 共用小零件

/// 表單 Section 標題：4pt 漸層側條＋圖示＋粗體字（同履歷表單、以前存提款表單那一套）
struct WealthFormHeader: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Capsule()
                .fill(LinearGradient(colors: [color, color.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 16)
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
        }
        .textCase(nil)
    }
}

/// 表單的數字、字（只在主執行緒叫）
enum WealthFormText {
    /// 數字帶回輸入框：四捨五入到兩位小數、去尾 0（123.45 →「123.45」、1200 →「1200」）
    static func editable(_ v: Double) -> String {
        let rounded: Double = (v * 100).rounded() / 100
        var s = String(format: "%.2f", rounded)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// 匯率帶回輸入框：4 位小數去尾 0（32.05 →「32.05」）
    static func rateText(_ r: Double) -> String {
        var s = String(format: "%.4f", r)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// 打的數字：去掉逗號、空白、「NT$」；尾巴「萬」×10,000（「6.8萬」→ 68,000）；讀不懂＝nil
    static func number(_ raw: String) -> Double? {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: ",", with: "")
        t = t.replacingOccurrences(of: "，", with: "")
        t = t.replacingOccurrences(of: "NT$", with: "")
        t = t.replacingOccurrences(of: " ", with: "")
        var scale: Double = 1
        if t.hasSuffix("萬") || t.hasSuffix("万") {
            scale = 10_000
            t.removeLast()
        }
        guard !t.isEmpty, let v = Double(t), v.isFinite else { return nil }
        return v * scale
    }

    /// 額度：「68,000」「6.8萬」都可以；沒寫「萬」又小於 1,000 的當萬（以前的表單單位是萬元）。四捨五入到元
    static func limit(_ raw: String) -> Double? {
        guard let v = number(raw), v > 0 else { return nil }
        let hasWan = raw.contains("萬") || raw.contains("万")
        let yuan: Double = (!hasWan && v < 1000) ? v * 10_000 : v
        return yuan.rounded()
    }

    /// 只留半形數字並截到 n 個
    static func digits(_ raw: String, limit n: Int) -> String {
        String(raw.filter { $0.isASCII && $0.isNumber }.prefix(n))
    }

    /// 「10/19（一）」
    static func dayWithWeekday(_ d: Date) -> String {
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        let wd = WealthCal.calendar.component(.weekday, from: d)
        let i = Swift.min(Swift.max(wd - 1, 0), 6)
        return WealthFormat.monthDay(d) + "（" + names[i] + "）"
    }

    /// 差額一行的數字：「+1.20」「-120」（台幣到元、外幣兩位）
    static func signed(_ v: Double, code: String) -> String {
        let body = WealthFormat.money(Swift.abs(v), code: code)
        if Swift.abs(v) < 0.005 { return "0" }
        return (v > 0 ? "+" : "-") + body
    }
}

/// 表單左上「取消」、右上「存」（忙碌守衛＋轉圈）
struct WealthSaveToolbar: ToolbarContent {
    let title: String
    let isSaving: Bool
    let disabled: Bool
    var showsSave: Bool = true
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("取消") { onCancel() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 6) {
                if isSaving {
                    ProgressView().scaleEffect(0.7).tint(.green)
                }
                if showsSave {
                    Button(title) { onSave() }
                        .bold()
                        .foregroundStyle(Color.green)
                        .disabled(disabled || isSaving)
                }
            }
        }
    }
}

/// 刪一筆先問：轉帳〔兩邊一起刪〕〔只刪這一筆〕〔取消〕；其他〔刪除〕〔取消〕。onDelete 參數＝兩邊一起刪
struct WealthDeleteAsk: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let message: String
    var isPair: Bool = false
    let onDelete: (Bool) -> Void

    func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented) {
            if isPair {
                Button("兩邊一起刪", role: .destructive) { onDelete(true) }
                Button("只刪這一筆") { onDelete(false) }
            } else {
                Button("刪除", role: .destructive) { onDelete(false) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}

/// 小表單的帳戶選單一列（打開時從 WealthFacts 抓一次，打字不重算）
struct WealthFormAccountChoice: Identifiable, Equatable {
    let id: UUID
    /// 「薪轉」「台新銀行」「國泰世華 CUBE」
    let name: String
    /// 選單那一列「薪轉（台新銀行・存摺 NT$12.8萬）」
    let label: String
    /// 這個帳戶的幣別（台幣在前；卡＝["NT$"]）
    let codes: [String]

    /// 銀行帳戶（不列證券戶、收起來的、定存；extra：這張表單本來就是它，不在選單裡也放最前面）。
    /// includeFixed：記一筆、轉帳也列定存帳戶（judge §4.5「證券戶以外的所有銀行」；v2 轉帳就能轉進定存）
    static func banks(_ facts: WealthFacts, including extra: UUID? = nil,
                      excluding skip: UUID? = nil, includeFixed: Bool = false) -> [WealthFormAccountChoice] {
        var list: [WealthFacts.Account] = includeFixed
            ? facts.banks.filter { !$0.hidden }
            : facts.pickerBanks
        if let e = extra, !list.contains(where: { $0.id == e }), let a = facts.account(e), !a.isSecurities {
            list.insert(a, at: 0)
        }
        return list.filter { $0.id != skip }.map { (a: WealthFacts.Account) -> WealthFormAccountChoice in
            let codes: [String] = a.currencies.isEmpty ? ["NT$"] : a.currencies
            return WealthFormAccountChoice(id: a.id, name: a.name, label: a.pickerLabel, codes: codes)
        }
    }

    /// 信用卡（沒停用的；「CUBE（還能刷 27.5萬）」）
    static func cards(_ facts: WealthFacts, excluding skip: UUID? = nil) -> [WealthFormAccountChoice] {
        facts.pickerCards.filter { $0.id != skip }.map { (c: WealthFacts.Card) -> WealthFormAccountChoice in
            var label = c.fullName
            if let left = c.available { label += "（還能刷 " + WealthFormChoiceText.wan(left) + "）" }
            return WealthFormAccountChoice(id: c.id, name: c.fullName, label: label, codes: ["NT$"])
        }
    }
}

/// 選單字（萬）：「27.5萬」（不寫 NT$，跟記帳卡選單同一個寫法）
enum WealthFormChoiceText {
    static func wan(_ v: Double) -> String {
        let s = v.ntdWanString
        if s.hasPrefix("NT$") { return String(s.dropFirst(3)) }
        return s
    }
}

/// 從要確認、表單裡打開的另一張表單（一個畫面一個 .sheet(item:)；內容外面呼叫端再掛 .appStores()）
enum WealthFormSheet: Identifiable {
    case editor(kind: WealthAccountKind, item: LifeMilestone?, focus: WealthEditorFocus?)
    case transfer(from: UUID?, to: UUID?, amount: Double?)
    case paid(cardId: UUID, key: String?)
    case move(fromId: UUID, expenseIds: [UUID], toCards: Bool)
    case anchor(accountId: UUID, code: String)
    case rates
    case expense(token: UUID, preset: AddExpensePreset)
    /// [v25.565] 要確認 #12〔看綁了哪些〕：那張卡的卡片頁、捲到綁在這張卡的定期扣款
    case card(UUID)
    /// [v25.566] 定存表單（要確認〔補資料〕：舊的定存帳戶、editing nil）
    case timeDeposit(accountId: UUID?, editing: UUID?)

    var id: String {
        switch self {
        case .editor(let k, let m, _):
            return "editor-" + k.rawValue + "-" + (m?.id.uuidString ?? "new")
        case .transfer(let f, let t, _):
            return "transfer-" + (f?.uuidString ?? "-") + "-" + (t?.uuidString ?? "-")
        case .paid(let c, let k):
            return "paid-" + c.uuidString + "-" + (k ?? "")
        case .move(let f, _, let toCards):
            return "move-" + f.uuidString + (toCards ? "-card" : "-bank")
        case .anchor(let a, let code):
            return "anchor-" + a.uuidString + "-" + code
        case .rates:
            return "rates"
        case .expense(let token, _):
            return "expense-" + token.uuidString
        case .card(let c):
            return "card-" + c.uuidString
        case .timeDeposit(let a, let e):
            return "deposit-" + (a?.uuidString ?? "new") + "-" + (e?.uuidString ?? "new")
        }
    }

    /// 內容（型別在這裡抹成 AnyView，坑 #6）
    var view: AnyView {
        switch self {
        case .editor(let k, let m, let focus):
            return AnyView(WealthAccountEditor(kind: k, editing: m, focus: focus))
        case .transfer(let f, let t, let amount):
            return AnyView(WealthTransferSheet(fromId: f, toId: t, amount: amount))
        case .paid(let c, let k):
            return AnyView(WealthPaidSheet(cardId: c, statementKey: k))
        case .move(let f, let ids, let toCards):
            return AnyView(WealthMoveLinksSheet(fromId: f, expenseIds: ids, incomeIds: [], toCards: toCards))
        case .anchor(let a, let code):
            return AnyView(WealthAnchorSheet(accountId: a, code: code))
        case .rates:
            return AnyView(WealthRatesSheet())
        case .expense(_, let p):
            // 記帳表單外面包布幕（切到背景蓋住；它疊在財富表單上）
            return AnyView(AddExpenseView(expenseType: .variable, preset: p)
                .modifier(WealthPrivacyCurtain(armed: true)))
        case .card(let c):
            // 卡片頁自己掛布幕（WealthCardPage.body）
            return AnyView(WealthCardPage(accountId: c, scrollTo: .recurring))
        case .timeDeposit(let a, let e):
            // [v25.566] 定存表單自己掛布幕（WealthTimeDepositSheet.body）
            return AnyView(WealthTimeDepositSheet(accountId: a, editing: e))
        }
    }
}

// MARK: - 記一筆（存款、提款、利息、手續費；judge §4.5）

/// 記一筆（存款、提款、利息、手續費）；editing：點明細裡財富頁自己記的那一筆
struct WealthRecordSheet: View {
    let accountId: UUID
    var kind: WealthRecordKind = .deposit
    var code: String? = nil
    var editing: BankDeposit? = nil

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @Environment(\.dismiss) private var dismiss

    @State private var choices: [WealthFormAccountChoice] = []
    @State private var pickedAccount: UUID?
    @State private var pickedKind: WealthRecordKind = .deposit
    @State private var pickedCode = "NT$"
    @State private var amountText = ""
    @State private var date = Date()
    @State private var note = ""
    /// 轉帳那一筆的唯讀一行（打開時組好）
    @State private var transferLine = ""
    @State private var loaded = false
    @State private var isSaving = false
    @State private var confirmDelete = false

    private var isTransferEdit: Bool { editing?.isTransfer == true }

    private var navTitle: String {
        if isTransferEdit { return "轉帳" }
        return editing != nil ? "編輯一筆" : "記一筆"
    }

    private var pickedChoice: WealthFormAccountChoice? {
        choices.first { $0.id == pickedAccount }
    }

    private var codes: [String] { pickedChoice?.codes ?? ["NT$"] }

    private var saveDisabled: Bool {
        guard pickedAccount != nil, let v = WealthFormText.number(amountText) else { return true }
        return v <= 0
    }

    private var deleteMessage: String {
        if isTransferEdit { return transferLine + "。對方帳戶也記了一筆，要兩邊一起刪嗎？" }
        return "刪掉後存摺上的數字會跟著變。"
    }

    var body: some View {
        NavigationStack {
            Form {
                if isTransferEdit {
                    transferSection
                } else {
                    mainSection
                }
                if editing != nil {
                    deleteSection
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                WealthSaveToolbar(title: editing != nil ? "儲存" : "存", isSaving: isSaving,
                                  disabled: saveDisabled, showsSave: !isTransferEdit,
                                  onCancel: { dismiss() }, onSave: { save() })
            }
            .onAppear { load() }
            .onChange(of: pickedAccount) { _, _ in fixCode() }
            .modifier(WealthDeleteAsk(isPresented: $confirmDelete,
                                      title: isTransferEdit ? "這是一筆轉帳" : "刪除這筆紀錄？",
                                      message: deleteMessage, isPair: isTransferEdit,
                                      onDelete: { both in performDelete(includingPair: both) }))
        }
        .presentationDetents([.medium, .large])
        .modifier(WealthPrivacyCurtain(armed: true))
    }

    private var mainSection: some View {
        Section {
            accountRow
            Picker("種類", selection: $pickedKind) {
                ForEach(WealthRecordKind.allCases) { k in
                    Text(k.title).tag(k)
                }
            }
            .pickerStyle(.segmented)
            codeRow
            amountRow
            DatePicker("日期", selection: $date, displayedComponents: .date)
            TextField("備註（選填）", text: $note, axis: .vertical)
                .lineLimit(1...3)
        } header: {
            WealthFormHeader(title: "記一筆", icon: "banknote.fill", color: .green)
        }
    }

    @ViewBuilder
    private var accountRow: some View {
        if editing != nil || choices.count < 2 {
            LabeledContent("帳戶", value: pickedChoice?.name ?? "")
        } else {
            Picker("帳戶", selection: $pickedAccount) {
                ForEach(choices) { c in
                    Text(c.label).tag(c.id as UUID?)
                }
            }
        }
    }

    @ViewBuilder
    private var codeRow: some View {
        if codes.count > 1 {
            Picker("幣別", selection: $pickedCode) {
                ForEach(codes, id: \.self) { c in
                    Text(c).tag(c)
                }
            }
        } else {
            LabeledContent("幣別", value: pickedCode)
        }
    }

    private var amountRow: some View {
        HStack {
            Text(pickedCode).foregroundStyle(.secondary)
            TextField("金額", text: $amountText)
                .keyboardType(.decimalPad)
        }
    }

    /// 編輯一筆轉帳：只看不改（兩邊綁在一起），要改就刪掉重記
    private var transferSection: some View {
        Section {
            Text(transferLine).font(.subheadline)
            if let n = editing?.note, !n.isEmpty {
                Text(n).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            WealthFormHeader(title: "轉帳", icon: "arrow.left.arrow.right", color: .blue)
        } footer: {
            Text("要改金額請刪掉重記；刪的時候會問要不要兩邊一起刪。")
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("刪除這一筆", systemImage: "trash")
            }
        }
    }

    // MARK: 帶入、存檔、刪除

    private func load() {
        guard !loaded else { return }
        loaded = true
        let facts = lifeStore.wealthFacts(expense: expenseStore, finance: financeStore)
        choices = WealthFormAccountChoice.banks(facts, including: accountId, includeFixed: true)
        pickedAccount = accountId
        pickedKind = kind
        let first: String = choices.first(where: { $0.id == accountId })?.codes.first ?? "NT$"
        pickedCode = code.map { WealthFacts.norm($0) } ?? first
        guard let e = editing else { return }
        date = e.date
        note = e.note ?? ""
        amountText = WealthFormText.editable(e.amount)
        pickedCode = WealthFacts.norm(e.currencyCode)
        pickedKind = WealthRecordKind.of(e)
        if e.isTransfer {
            let other: String = facts.account(e.counterpartyId)?.name ?? "別的帳戶"
            var s: String = (e.isWithdrawal ? "轉給 " : "來自 ") + other
            s += "・" + WealthFormat.money(e.amount, code: e.currencyCode)
            s += "・" + WealthFormat.monthDay(e.date)
            if let r = e.fxRate, r > 0 { s += "・匯率 " + WealthFormat.rate(r) }
            transferLine = s
        }
    }

    /// 換帳戶：新帳戶沒有這個幣別就換成它的第一個
    private func fixCode() {
        guard editing == nil else { return }
        let list = codes
        if !list.contains(pickedCode) { pickedCode = list.first ?? "NT$" }
    }

    /// 編輯時從原本那筆改（連結、以前的沖正旗標都留著）；先關畫面、下一個 runloop 才寫
    private func save() {
        guard !isSaving, !isTransferEdit, let id = pickedAccount,
              let amount = WealthFormText.number(amountText), amount > 0 else { return }
        isSaving = true
        var dep: BankDeposit = editing ?? BankDeposit()
        dep.date = date
        dep.amount = amount
        dep.currencyCode = pickedCode
        dep.isWithdrawal = pickedKind.isOutflow
        dep.kind = pickedKind.depositKind
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        dep.note = trimmed.isEmpty ? nil : trimmed
        let life = lifeStore
        let saved = dep
        dismiss()
        DispatchQueue.main.async {
            life.upsertBankDeposit(saved, in: id)
        }
    }

    private func performDelete(includingPair: Bool) {
        guard let e = editing else { dismiss(); return }
        let life = lifeStore
        let id = accountId
        let depId = e.id
        dismiss()
        DispatchQueue.main.async {
            life.deleteBankDeposit(depId, in: id, includingPair: includingPair)
        }
    }
}

// MARK: - 轉帳（含換匯；judge §4.5）

/// 轉帳（含換匯）；要確認〔轉帳過去〕帶 to、from、amount。
/// [v25.566] exchange：帳戶頁〔換匯〕（fromId＝toId＝那個帳戶）——同一個帳戶兩個幣別互轉也是轉帳（兩筆同一個 transferPairId）；
/// 只有一個外幣的帳戶＝從存摺上台幣最多的另一個活存換進來
struct WealthTransferSheet: View {
    var fromId: UUID? = nil
    var toId: UUID? = nil
    var amount: Double? = nil
    /// [v25.566] 換匯模式（標題「換匯」、「到」也列自己、同一個帳戶時兩邊幣別不一樣）
    var exchange: Bool = false

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @Environment(\.dismiss) private var dismiss

    @State private var choices: [WealthFormAccountChoice] = []
    @State private var from: UUID?
    @State private var to: UUID?
    @State private var fromCode = "NT$"
    @State private var toCode = "NT$"
    @State private var amountText = ""
    @State private var rateText = ""
    @State private var feeText = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var rates = FinanceRates(rates: [])
    @State private var loaded = false
    @State private var isSaving = false

    private func codes(of id: UUID?) -> [String] {
        choices.first { $0.id == id }?.codes ?? ["NT$"]
    }

    private var toChoices: [WealthFormAccountChoice] {
        // [v25.566] 換匯：同一個帳戶兩個幣別互轉，「到」也列自己
        if exchange { return choices }
        return choices.filter { $0.id != from }
    }

    /// [v25.566] 同一個帳戶自己換（換匯）
    private var sameAccount: Bool { from != nil && from == to }

    /// [v25.566] 兩邊可以存：不同帳戶，或同一個帳戶不同幣別（LifeStore.addTransfer 同一條規則）
    private var pairOK: Bool { from != to || fromCode != toCode }

    /// 兩邊幣別不同、有一邊是台幣：可以改匯率（還沒選對方＝不出現）
    private var showsRateField: Bool {
        guard to != nil, fromCode != toCode else { return false }
        return fromCode == "NT$" || toCode == "NT$"
    }

    private var bothForeign: Bool {
        guard to != nil, fromCode != toCode else { return false }
        return fromCode != "NT$" && toCode != "NT$"
    }

    private var rateLabel: String {
        let foreign = fromCode == "NT$" ? toCode : fromCode
        return "匯率（1 \(foreign)＝幾台幣）"
    }

    private var rateInvalid: Bool {
        guard showsRateField else { return false }
        let t = rateText.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return false }
        return (Double(t) ?? 0) <= 0
    }

    private var usedRate: Double? {
        guard showsRateField else { return nil }
        if let r = Double(rateText.trimmingCharacters(in: .whitespaces)), r > 0 { return r }
        return WealthFacts.defaultTransferRate(from: fromCode, to: toCode, rates: rates)
    }

    private func received(_ v: Double) -> Double? {
        WealthFacts.transferAmount(v, from: fromCode, to: toCode, rate: usedRate, rates: rates)
    }

    /// 「對方收到 美金 1,560.06」（[v25.566] 同一個帳戶「換到 US$1,000.00」）；查不到匯率＝紅字；還沒選對方或沒打金額＝nil
    private var preview: (text: String, ok: Bool)? {
        guard to != nil else { return nil }
        if !pairOK { return ("同一個帳戶要選兩個不同的幣別", false) }
        guard let v = WealthFormText.number(amountText), v > 0 else { return nil }
        guard let r = received(v) else { return ("設定裡找不到匯率，先到設定加這個幣別的匯率", false) }
        let lead: String = sameAccount ? "換到 " : "對方收到 "
        return (lead + WealthFormat.money(r, code: toCode), true)
    }

    private var saveDisabled: Bool {
        guard from != nil, to != nil, pairOK, !rateInvalid,
              let v = WealthFormText.number(amountText), v > 0, let r = received(v) else { return true }
        return r <= 0
    }

    // [v25.566] 換匯模式的字（標題、段落、footer）
    private var navTitle: String { exchange ? "換匯" : "轉帳" }
    private var fromHeader: String { exchange ? "換出" : "從哪個帳戶" }
    private var toHeader: String { exchange ? "換入" : "轉到" }
    private var fromCodeLabel: String { exchange ? "換出幣別" : "轉出幣別" }
    private var toCodeLabel: String { exchange ? "換入幣別" : "對方幣別" }
    private var amountHeader: String { exchange ? "換多少" : "轉多少" }
    private var amountPlaceholder: String { exchange ? "換出金額" : "轉出金額" }
    private var amountFooter: String {
        if exchange {
            return "台幣、外幣兩格各記一筆、綁在一起；刪一邊會問要不要兩邊一起刪。手續費記在換出的那一格。"
        }
        return "兩邊各記一筆、綁在一起；刪一邊時會問要不要兩邊一起刪。手續費記在轉出的帳戶。"
    }

    var body: some View {
        NavigationStack {
            Form {
                fromSection
                toSection
                amountSection
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                WealthSaveToolbar(title: "存", isSaving: isSaving, disabled: saveDisabled,
                                  onCancel: { dismiss() }, onSave: { save() })
            }
            .onAppear { load() }
            .onChange(of: from) { _, _ in fromChanged() }
            .onChange(of: to) { _, _ in toChanged() }
            .onChange(of: fromCode) { _, _ in fromCodeChanged() }
            .onChange(of: toCode) { _, _ in resetRate() }
        }
        .presentationDetents([.medium, .large])
        .modifier(WealthPrivacyCurtain(armed: true))
    }

    private var fromSection: some View {
        Section {
            Picker("從", selection: $from) {
                ForEach(choices) { c in
                    Text(c.label).tag(c.id as UUID?)
                }
            }
            if codes(of: from).count > 1 {
                Picker(fromCodeLabel, selection: $fromCode) {
                    ForEach(codes(of: from), id: \.self) { c in
                        Text(c).tag(c)
                    }
                }
            }
        } header: {
            WealthFormHeader(title: fromHeader, icon: "arrow.up.right", color: .blue)
        }
    }

    private var toSection: some View {
        Section {
            Picker("到", selection: $to) {
                Text("請選擇").tag(nil as UUID?)
                ForEach(toChoices) { c in
                    Text(c.label).tag(c.id as UUID?)
                }
            }
            if to != nil, codes(of: to).count > 1 {
                Picker(toCodeLabel, selection: $toCode) {
                    ForEach(codes(of: to), id: \.self) { c in
                        Text(c).tag(c)
                    }
                }
            }
        } header: {
            WealthFormHeader(title: toHeader, icon: "arrow.down.left", color: .blue)
        }
    }

    private var amountSection: some View {
        let p = preview
        return Section {
            HStack {
                Text(fromCode).foregroundStyle(.secondary)
                TextField(amountPlaceholder, text: $amountText)
                    .keyboardType(.decimalPad)
            }
            if showsRateField {
                HStack {
                    Text(rateLabel).foregroundStyle(.secondary)
                    Spacer()
                    TextField("匯率", text: $rateText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            } else if bothForeign {
                Text("兩邊都是外幣：用設定裡的匯率換算")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let p {
                Text(p.text)
                    .font(.subheadline)
                    .foregroundStyle(p.ok ? Color.secondary : Color.red)
            }
            HStack {
                Text("手續費（選填）").foregroundStyle(.secondary)
                Spacer()
                TextField("0", text: $feeText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            DatePicker("日期", selection: $date, displayedComponents: .date)
            TextField("備註（選填）", text: $note)
        } header: {
            WealthFormHeader(title: amountHeader, icon: "arrow.left.arrow.right", color: .blue)
        } footer: {
            Text(amountFooter)
        }
    }

    // MARK: 帶入、存檔

    private func load() {
        guard !loaded else { return }
        loaded = true
        rates = FinanceRates(expenseStore)
        let facts = lifeStore.wealthFacts(expense: expenseStore, finance: financeStore)
        choices = WealthFormAccountChoice.banks(facts, including: exchange ? (toId ?? fromId) : fromId, includeFixed: true)
        // [v25.566] 換匯：照那個帳戶的幣別決定兩邊（同一個帳戶自己換，或從別的台幣活存換進來）
        if exchange, let t = toId, loadExchange(t, facts: facts) {
            if let a = amount, a > 0 { amountText = WealthFormText.editable(a) }
            resetRate()
            return
        }
        // 沒指定從哪轉：先挑活存（不是定存）的另一個帳戶
        let liveFirst: UUID? = facts.pickerBanks.first(where: { $0.id != toId })?.id
        let start: UUID? = fromId ?? liveFirst ?? choices.first(where: { $0.id != toId })?.id
        from = start
        fromCode = codes(of: start).first ?? "NT$"
        if let t = toId, t != start, choices.contains(where: { $0.id == t }) {
            to = t
            let list = codes(of: t)
            toCode = list.contains(fromCode) ? fromCode : (list.first ?? "NT$")
        }
        if let a = amount, a > 0 { amountText = WealthFormText.editable(a) }
        resetRate()
    }

    /// [v25.566] 換匯打開時：帳戶有兩個以上幣別 → 同一個帳戶自己換（台幣 → 第一個外幣；沒有台幣就第一個 → 第二個）；
    /// 只有一個外幣 → 從存摺上台幣最多的另一個活存（facts.pickerBanks）換進來。帳戶不在選單裡、只有台幣＝false（照一般轉帳帶）
    private func loadExchange(_ t: UUID, facts: WealthFacts) -> Bool {
        guard choices.contains(where: { $0.id == t }) else { return false }
        let list = codes(of: t)
        if list.count >= 2 {
            let fc: String = list.contains("NT$") ? "NT$" : list[0]
            from = t
            to = t
            fromCode = fc
            toCode = list.first(where: { $0 != fc }) ?? fc
            return true
        }
        guard let only = list.first, only != "NT$" else { return false }
        let others: [WealthFacts.Account] = facts.pickerBanks.filter { a in
            a.id != t && choices.contains(where: { $0.id == a.id })
        }
        let richest: WealthFacts.Account? = others.max(by: { $0.balance("NT$") < $1.balance("NT$") })
        let source: UUID? = richest?.id ?? choices.first(where: { $0.id != t })?.id
        from = source
        let fromList = codes(of: source)
        fromCode = fromList.contains("NT$") ? "NT$" : (fromList.first ?? "NT$")
        to = t
        toCode = only
        return true
    }

    private func fromChanged() {
        let list = codes(of: from)
        if !list.contains(fromCode) { fromCode = list.first ?? "NT$" }
        if exchange {
            // [v25.566] 換匯不清掉「到」；換回同一個帳戶時兩邊幣別要不一樣
            keepCodesApart()
        } else if to == from {
            to = nil
        }
        resetRate()
    }

    /// 換對方帳戶：對方有這邊的幣別就收同一個幣別，不然收對方第一個幣別。
    /// [v25.566] 換匯：收跟這邊不一樣的幣別（對方只有這個幣別才收同一個）
    private func toChanged() {
        guard to != nil else { return }
        let list = codes(of: to)
        if exchange {
            toCode = list.first(where: { $0 != fromCode }) ?? (list.first ?? "NT$")
        } else {
            toCode = list.contains(fromCode) ? fromCode : (list.first ?? "NT$")
        }
        resetRate()
    }

    /// [v25.566] 換匯、同一個帳戶：換出幣別改成跟換入一樣時，換入改成另一個
    private func fromCodeChanged() {
        if exchange { keepCodesApart() }
        resetRate()
    }

    /// [v25.566] 同一個帳戶時兩邊幣別一律不一樣（帳戶只有一個幣別就不動，存檔鈕會擋）
    private func keepCodesApart() {
        guard sameAccount, fromCode == toCode else { return }
        if let other = codes(of: to).first(where: { $0 != fromCode }) { toCode = other }
    }

    private func resetRate() {
        if let r = WealthFacts.defaultTransferRate(from: fromCode, to: toCode, rates: rates) {
            rateText = WealthFormText.rateText(r)
        } else {
            rateText = ""
        }
    }

    private func save() {
        // [v25.566] 不同帳戶，或同一個帳戶不同幣別（換匯）
        guard !isSaving, let f = from, let t = to, f != t || fromCode != toCode,
              let v = WealthFormText.number(amountText), v > 0,
              let got = received(v), got > 0 else { return }
        isSaving = true
        let life = lifeStore
        let fc = fromCode
        let tc = toCode
        let rate: Double? = (fc == tc) ? nil : usedRate
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteValue: String? = trimmed.isEmpty ? nil : trimmed
        let day = date
        // let（不是 var）：下一個 runloop 的閉包不能抓會變的區域變數
        let fee: Double? = WealthFormText.number(feeText).flatMap { $0 > 0 ? $0 : nil }
        dismiss()
        DispatchQueue.main.async {
            life.addTransfer(from: f, fromCode: fc, amount: v, to: t, toCode: tc,
                             toAmount: got, fxRate: rate, date: day, note: noteValue)
            if let fee {
                let dep = BankDeposit(date: day, amount: fee, currencyCode: fc, isWithdrawal: true,
                                      note: "轉帳手續費", kind: BankDeposit.kindFee)
                life.upsertBankDeposit(dep, in: f)
            }
        }
    }
}

// MARK: - 對存摺（取代沖正；judge §4.5、樣稿③-C3）

/// 差額是什麼（選填）
enum WealthAnchorReason: String, CaseIterable, Identifiable {
    case interest, fee, missedExpense, missedIncome, unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .interest: return "利息"
        case .fee: return "手續費"
        case .missedExpense: return "漏記的支出"
        case .missedIncome: return "漏記的收入"
        case .unknown: return "不知道"
        }
    }
}

/// 對存摺（取代沖正）；editing：點明細裡的對存摺那一列
struct WealthAnchorSheet: View {
    let accountId: UUID
    var code: String = "NT$"
    var editing: BankDeposit? = nil

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @Environment(\.dismiss) private var dismiss

    @State private var codes: [String] = ["NT$"]
    @State private var accountName = ""
    @State private var pickedCode = "NT$"
    @State private var date = Date()
    @State private var amountText = ""
    @State private var reason: WealthAnchorReason?
    /// App 算的「這個幣別那天結束時」：只在打開、換日期、換幣別時算（打字不算）
    @State private var appBalance: Double?
    @State private var appBalanceKey = ""
    @State private var loaded = false
    @State private var isSaving = false
    @State private var confirmDelete = false
    /// 漏記的支出：存好對存摺後開記帳
    @State private var sheet: WealthFormSheet?

    private var taskKey: String { WealthCal.dayKey(date) + "|" + pickedCode + "|" + (loaded ? "1" : "0") }
    private var balanceReady: Bool { appBalance != nil && appBalanceKey == taskKey }

    /// 存摺上 − App 算的，四捨五入到 0.01
    private var diff: Double? {
        guard balanceReady, let app = appBalance, let target = WealthFormText.number(amountText) else { return nil }
        return ((target - app) * 100).rounded() / 100
    }

    private var navTitle: String {
        if pickedCode == "NT$" { return "對存摺" }
        return "對存摺・" + pickedCode
    }

    var body: some View {
        NavigationStack {
            Form {
                mainSection
                diffSection
                reasonSection
                if editing != nil {
                    deleteSection
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                WealthSaveToolbar(title: "存", isSaving: isSaving, disabled: diff == nil,
                                  onCancel: { dismiss() }, onSave: { save() })
            }
            .onAppear { load() }
            .task(id: taskKey) { refresh() }
            .modifier(WealthDeleteAsk(isPresented: $confirmDelete, title: "刪除這次對存摺？",
                                      message: "刪掉這次對存摺，之後的數字回到 App 算的。",
                                      onDelete: { _ in performDelete() }))
            .sheet(item: $sheet, onDismiss: { dismiss() }) { s in
                s.view.appStores()
            }
        }
        .presentationDetents([.medium, .large])
        .modifier(WealthPrivacyCurtain(armed: true))
    }

    private var mainSection: some View {
        Section {
            if codes.count > 1 && editing == nil {
                Picker("幣別", selection: $pickedCode) {
                    ForEach(codes, id: \.self) { c in
                        Text(c).tag(c)
                    }
                }
            } else {
                LabeledContent("幣別", value: pickedCode)
            }
            DatePicker("日期", selection: $date, displayedComponents: .date)
            LabeledContent("App 算的", value: appBalanceText)
            HStack {
                Text("存摺上寫")
                Spacer()
                TextField(pickedCode, text: $amountText)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            WealthFormHeader(title: accountName.isEmpty ? "對存摺" : accountName, icon: "checkmark.seal.fill",
                             color: .orange)
        } footer: {
            Text("打存摺（或網銀）上 " + WealthFormText.dayWithWeekday(date) + " 結束時的數字，以後就從這裡往後算。")
        }
    }

    private var appBalanceText: String {
        guard balanceReady, let v = appBalance else { return "算一下…" }
        return WealthFormat.money(v, code: pickedCode)
    }

    @ViewBuilder
    private var diffSection: some View {
        if let d = diff, let target = WealthFormText.number(amountText) {
            Section {
                Text(diffLine(d, target: target))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Swift.abs(d) < 0.005 ? Color.secondary : Color.blue)
            }
        }
    }

    private func diffLine(_ d: Double, target: Double) -> String {
        "差 " + WealthFormText.signed(d, code: pickedCode) + "：之後從 "
            + WealthFormat.money(target, code: pickedCode) + " 往後算"
    }

    private var reasonSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(WealthAnchorReason.allCases) { r in
                    reasonChip(r)
                }
            }
            .padding(.vertical, 4)
        } header: {
            WealthFormHeader(title: "差額是什麼（選填）", icon: "questionmark.circle", color: .orange)
        } footer: {
            Text(reasonFootnote)
        }
    }

    private var reasonFootnote: String {
        "選「利息」「手續費」就記成那一筆；選「漏記的支出」存好後打開記帳。只比 " + pickedCode + " 這一格，不跟別的幣別混著比。"
    }

    private func reasonChip(_ r: WealthAnchorReason) -> some View {
        let on = reason == r
        return Button {
            reason = on ? nil : r
        } label: {
            Text(r.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .frame(maxWidth: .infinity)
                .foregroundStyle(on ? Color.white : Color.primary)
                .background(on ? Color.indigo : Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("刪除這次對存摺", systemImage: "trash")
            }
        }
    }

    // MARK: 帶入、算、存

    private func load() {
        guard !loaded else { return }
        let facts = lifeStore.wealthFacts(expense: expenseStore, finance: financeStore)
        if let a = facts.account(accountId) {
            accountName = a.name
            codes = a.currencies.isEmpty ? ["NT$"] : a.currencies
        }
        pickedCode = WealthFacts.norm(code)
        if !codes.contains(pickedCode) { codes.append(pickedCode) }
        if let e = editing {
            date = e.date
            pickedCode = WealthFacts.norm(e.currencyCode)
            if let v = e.anchorAmount { amountText = WealthFormText.editable(v) }
        }
        loaded = true
    }

    /// App 算的：一套數字重算一次（不走快取）；編輯以前的對存摺不算它自己
    private func refresh() {
        guard loaded else { return }
        let key = taskKey
        let excluding: UUID? = editing?.id
        appBalance = lifeStore.passbookBalance(accountId: accountId, code: pickedCode, endOf: date,
                                               excluding: excluding, expense: expenseStore, finance: financeStore)
        appBalanceKey = key
    }

    private func save() {
        guard !isSaving, let d = diff, let target = WealthFormText.number(amountText) else { return }
        isSaving = true
        let life = lifeStore
        let id = accountId
        let c = pickedCode
        let day = date
        let r = reason
        let isNew = editing == nil
        // 利息（存摺多了）、手續費（存摺少了）：記成那一種，不是對存摺
        if isNew, r == .interest, d > 0.004 {
            let dep = BankDeposit(date: day, amount: d, currencyCode: c, isWithdrawal: false,
                                  note: "對存摺時補記", kind: BankDeposit.kindInterest)
            dismiss()
            DispatchQueue.main.async { life.upsertBankDeposit(dep, in: id) }
            return
        }
        if isNew, r == .fee, d < -0.004 {
            let dep = BankDeposit(date: day, amount: -d, currencyCode: c, isWithdrawal: true,
                                  note: "對存摺時補記", kind: BankDeposit.kindFee)
            dismiss()
            DispatchQueue.main.async { life.upsertBankDeposit(dep, in: id) }
            return
        }
        let noteText: String? = r?.title ?? editing?.note
        let anchor = BankDeposit(id: editing?.id ?? UUID(), date: day, amount: Swift.abs(d), currencyCode: c,
                                 isWithdrawal: d < 0, isAdjust: true, note: noteText,
                                 kind: BankDeposit.kindAnchor, anchorAmount: target)
        // 漏記的支出（台幣、存摺少了）：先存對存摺（這張表單還開著），再打開記帳（金額先填好）；記帳關掉這張也關
        if isNew, r == .missedExpense, d < -0.004, c == "NT$" {
            life.upsertBankDeposit(anchor, in: id)
            let preset = AddExpensePreset(date: day, paymentBankId: id, amount: -d)
            sheet = .expense(token: UUID(), preset: preset)
            return
        }
        dismiss()
        DispatchQueue.main.async { life.upsertBankDeposit(anchor, in: id) }
    }

    private func performDelete() {
        guard let e = editing else { dismiss(); return }
        let life = lifeStore
        let id = accountId
        let depId = e.id
        dismiss()
        DispatchQueue.main.async {
            life.deleteBankDeposit(depId, in: id, includingPair: false)
        }
    }
}

// MARK: - 標成已繳（樣稿③-C2；不擋付費）

/// 標成已繳（哪一期 nil＝最早沒繳的那一期）；也是〔不是，改一下〕〔繳了〕打開的
struct WealthPaidSheet: View {
    let cardId: UUID
    var statementKey: String? = nil

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @Environment(\.dismiss) private var dismiss

    /// 可以選的那幾期（已經結帳的最近 6 期，新的在前）
    @State private var options: [WealthStatement] = []
    @State private var banks: [WealthFormAccountChoice] = []
    @State private var cardName = ""
    @State private var key = ""
    @State private var amountText = ""
    @State private var payFrom: UUID?
    @State private var date = Date()
    @State private var loaded = false
    @State private var isSaving = false

    private var current: WealthStatement? { options.first { $0.key == key } }

    private var saveDisabled: Bool {
        guard current != nil, let v = WealthFormText.number(amountText) else { return true }
        return v <= 0
    }

    var body: some View {
        NavigationStack {
            Form {
                if options.isEmpty {
                    Section {
                        Text("這張卡還沒有已經結帳的帳單。")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    mainSection
                    undoSection
                }
            }
            .navigationTitle("標成已繳")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                WealthSaveToolbar(title: "存", isSaving: isSaving, disabled: saveDisabled,
                                  onCancel: { dismiss() }, onSave: { save() })
            }
            .onAppear { load() }
            .onChange(of: key) { _, _ in fill() }
        }
        .presentationDetents([.medium, .large])
        .modifier(WealthPrivacyCurtain(armed: true))
    }

    private var mainSection: some View {
        Section {
            Picker("哪一期", selection: $key) {
                ForEach(options) { s in
                    Text(optionLabel(s)).tag(s.key)
                }
            }
            HStack {
                Text("繳多少")
                Spacer()
                TextField("全額", text: $amountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            if let line = remainderLine {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("從哪個帳戶", selection: $payFrom) {
                ForEach(banks) { c in
                    Text(c.label).tag(c.id as UUID?)
                }
                Text("別的方式（現金、超商）").tag(nil as UUID?)
            }
            DatePicker("日期", selection: $date, displayedComponents: .date)
        } header: {
            WealthFormHeader(title: cardName.isEmpty ? "帳單" : cardName, icon: "checkmark.circle.fill", color: .green)
        } footer: {
            Text("不會另記一筆支出（刷卡時已經記過）。只繳一部分時，剩下的會算進下一期「前期未繳」。")
        }
    }

    /// 「10 月帳單 18,600」「9 月帳單 23,000・已繳」
    private func optionLabel(_ s: WealthStatement) -> String {
        var t = s.label + " " + WealthFormat.grouped(s.amount, decimals: 0)
        switch s.status {
        case .paid: t += "・已繳"
        case .assumedPaid: t += "・當作已繳"
        case .overdue: t += "・逾期"
        default: break
        }
        return t
    }

    /// 小於全額：「剩下 12,600 會算進下期帳單（前期未繳），會有循環利息」
    private var remainderLine: String? {
        guard let s = current, let v = WealthFormText.number(amountText) else { return nil }
        let left = s.amount - v
        guard left > 0.5 else { return nil }
        return "剩下 " + WealthFormat.grouped(left, decimals: 0) + " 會算進下期帳單（前期未繳），會有循環利息"
    }

    @ViewBuilder
    private var undoSection: some View {
        if let s = current {
            if s.isExplicitPaid {
                Section {
                    Button("取消已繳") { clearPaid() }
                        .foregroundStyle(Color.red)
                }
            } else if s.status == .assumedPaid {
                Section {
                    Button("其實還沒繳") { markNotPaid() }
                        .foregroundStyle(Color.red)
                } footer: {
                    Text("過了截止日就算逾期：可能有循環利息與違約金。")
                }
            }
        }
    }

    // MARK: 帶入、存

    private func load() {
        guard !loaded else { return }
        loaded = true
        let facts = lifeStore.wealthFacts(expense: expenseStore, finance: financeStore)
        guard let card = facts.card(cardId) else { return }
        cardName = card.fullName
        // 這張卡現在的扣款帳戶收起來了也列著（不然預設的「從哪個帳戶」對不上，會被換成別的方式）
        banks = WealthFormAccountChoice.banks(facts, including: card.payerId)
        var list: [WealthStatement] = Array(card.statements.filter { $0.isClosed }.reversed().prefix(6))
        if let k = statementKey, !list.contains(where: { $0.key == k }),
           let s = card.statements.first(where: { $0.key == k }) {
            list.insert(s, at: 0)
        }
        options = list
        if let k = statementKey, list.contains(where: { $0.key == k }) {
            key = k
        } else if let k = card.dueStatement?.key, list.contains(where: { $0.key == k }) {
            key = k
        } else {
            key = list.first?.key ?? ""
        }
        fill()
    }

    /// 換一期：金額＝全額（你標過的照你標的）、帳戶＝那一期通常從的（你標過的照你標的）、日期＝今天（標過的照那天）
    private func fill() {
        guard let s = current else { return }
        // 你標過的、已經扣了的（自動扣全額／最低、改版前的）：照扣的那天、那個帳戶、那個數。不然自動扣的卡從〔＋〕→標成已繳
        //（預設最近一期）直接按存，扣款會從截止日搬到今天（中間對過存摺的話今天又多扣一次）、自動扣最低變成扣全額
        //（驗證 build/v3/verify/card_text.py H）
        if s.isExplicitPaid || s.status == .paid {
            amountText = WealthFormText.editable(s.paidAmount)
            payFrom = s.paidFrom
            date = s.paidOn ?? Date()
        } else {
            amountText = WealthFormText.editable(s.amount)
            payFrom = s.payerId
            date = Date()
        }
        // 帳戶不在選單裡（收起來了）就改成別的方式，不然 Picker 對不上
        if let p = payFrom, !banks.contains(where: { $0.id == p }) { payFrom = nil }
    }

    private func save() {
        guard !isSaving, let s = current, let v = WealthFormText.number(amountText), v > 0 else { return }
        isSaving = true
        let paid: Double? = v >= s.amount - 0.5 ? nil : v
        let life = lifeStore
        let id = cardId
        let k = s.key
        let day = date
        let src = payFrom
        dismiss()
        DispatchQueue.main.async {
            life.markStatementPaid(cardId: id, key: k, date: day, account: src, amount: paid)
        }
    }

    private func clearPaid() {
        guard !isSaving, let s = current else { return }
        isSaving = true
        let life = lifeStore
        let id = cardId
        let k = s.key
        dismiss()
        DispatchQueue.main.async { life.clearStatementPaid(cardId: id, key: k) }
    }

    private func markNotPaid() {
        guard !isSaving, let s = current else { return }
        isSaving = true
        let life = lifeStore
        let id = cardId
        let k = s.key
        dismiss()
        DispatchQueue.main.async { life.markStatementNotPaid(cardId: id, key: k) }
    }
}

// MARK: - 帳單金額不一樣（不擋付費）

/// 帳單金額不一樣（哪一期 nil＝最近一期已結帳的）
struct WealthStatedAmountSheet: View {
    let cardId: UUID
    var statementKey: String? = nil

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @Environment(\.dismiss) private var dismiss

    @State private var options: [WealthStatement] = []
    @State private var key = ""
    @State private var statedText = ""
    @State private var loaded = false
    @State private var isSaving = false
    @State private var askTopUp = false
    /// 〔補記〕：開記帳（刷這張卡、金額＝差額）
    @State private var sheet: WealthFormSheet?

    private var current: WealthStatement? { options.first { $0.key == key } }

    /// App 算的＝刷卡加總＋前期未繳（不含你輸入的）
    private var appAmount: Double {
        guard let s = current else { return 0 }
        return s.computedAmount + s.carriedIn
    }

    private var stated: Double? {
        guard let v = WealthFormText.number(statedText), v >= 0 else { return nil }
        return v
    }

    private var diff: Double? { stated.map { $0 - appAmount } }

    /// 打了字但讀不懂才擋（空白＝拿掉，回到 App 算的）
    private var saveDisabled: Bool {
        if current == nil { return true }
        let t = statedText.trimmingCharacters(in: .whitespaces)
        return !t.isEmpty && stated == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if options.isEmpty {
                    Section {
                        Text("這張卡還沒有已經結帳的帳單。")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    mainSection
                }
            }
            .navigationTitle("帳單金額不一樣")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                WealthSaveToolbar(title: "存", isSaving: isSaving, disabled: saveDisabled,
                                  onCancel: { dismiss() }, onSave: { saveTapped() })
            }
            .onAppear { load() }
            .onChange(of: key) { _, _ in fill() }
            .confirmationDialog("差額要補記成一筆刷這張卡的支出嗎？", isPresented: $askTopUp, titleVisibility: .visible) {
                Button("補記（例：國外交易手續費）") { saveAndTopUp() }
                Button("不用") { save() }
                Button("取消", role: .cancel) {}
            }
            .sheet(item: $sheet, onDismiss: { dismiss() }) { s in
                s.view.appStores()
            }
        }
        .presentationDetents([.medium, .large])
        .modifier(WealthPrivacyCurtain(armed: true))
    }

    private var mainSection: some View {
        Section {
            Picker("哪一期", selection: $key) {
                ForEach(options) { s in
                    Text(s.label).tag(s.key)
                }
            }
            LabeledContent("App 算的", value: WealthFormat.grouped(appAmount, decimals: 0))
            HStack {
                Text("帳單上寫")
                Spacer()
                TextField("跟 App 一樣就空著", text: $statedText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            if let d = diff {
                Text("差 " + WealthFormText.signed(d, code: "NT$"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Swift.abs(d) < 0.5 ? Color.secondary : Color.blue)
            }
        } header: {
            WealthFormHeader(title: "以帳單為準", icon: "doc.text.magnifyingglass", color: .orange)
        } footer: {
            Text("存了以後這一期的「要繳」照帳單上寫的；空著存＝回到 App 算的。")
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let facts = lifeStore.wealthFacts(expense: expenseStore, finance: financeStore)
        guard let card = facts.card(cardId) else { return }
        var list: [WealthStatement] = Array(card.statements.filter { $0.isClosed }.reversed().prefix(6))
        if let k = statementKey, !list.contains(where: { $0.key == k }),
           let s = card.statements.first(where: { $0.key == k }) {
            list.insert(s, at: 0)
        }
        options = list
        if let k = statementKey, list.contains(where: { $0.key == k }) {
            key = k
        } else {
            key = list.first?.key ?? ""
        }
        fill()
    }

    private func fill() {
        if let v = current?.statedAmount {
            statedText = WealthFormText.editable(v)
        } else {
            statedText = ""
        }
    }

    /// 帳單比 App 算的多：先問要不要補記差額；不然直接存
    private func saveTapped() {
        guard !isSaving else { return }
        if let d = diff, d > 0.5 {
            askTopUp = true
        } else {
            save()
        }
    }

    private func save() {
        guard !isSaving, let s = current else { return }
        isSaving = true
        let life = lifeStore
        let id = cardId
        let k = s.key
        let v = stated
        dismiss()
        DispatchQueue.main.async { life.setStatementStatedAmount(cardId: id, key: k, amount: v) }
    }

    /// 〔補記〕：先存帳單金額（這張表單還開著），再打開記帳（刷這張卡、金額＝差額、日期＝結帳日）；記帳關掉這張也關
    private func saveAndTopUp() {
        guard !isSaving, let s = current, let v = stated, let d = diff, d > 0.5 else { return }
        isSaving = true
        lifeStore.setStatementStatedAmount(cardId: cardId, key: s.key, amount: v)
        let preset = AddExpensePreset(date: s.close, paymentCardId: cardId, amount: d, title: "帳單差額")
        // 確認框收起來之後才開記帳（同一刻疊兩個彈窗，iOS 會把第二個吃掉）
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            sheet = .expense(token: UUID(), preset: preset)
        }
    }
}

// MARK: - 一次改到別張卡／改到別的帳戶

/// 一次改到別張卡（toCards true）／改到別的帳戶（false）：選新的、從哪天起（LifeStore.moveWealthLinks）
struct WealthMoveLinksSheet: View {
    let fromId: UUID
    var expenseIds: [UUID] = []
    var incomeIds: [UUID] = []
    var toCards: Bool = true

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @Environment(\.dismiss) private var dismiss

    @State private var targets: [WealthFormAccountChoice] = []
    @State private var target: UUID?
    @State private var rows: [String] = []
    @State private var fromName = ""
    @State private var fromDay = Date()
    @State private var allPast = false
    @State private var loaded = false
    @State private var isSaving = false

    private var saveDisabled: Bool { target == nil || (expenseIds.isEmpty && incomeIds.isEmpty) }

    var body: some View {
        NavigationStack {
            Form {
                itemsSection
                targetSection
                whenSection
            }
            .navigationTitle(toCards ? "改到別張卡" : "改到別的帳戶")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                WealthSaveToolbar(title: "存", isSaving: isSaving, disabled: saveDisabled,
                                  onCancel: { dismiss() }, onSave: { save() })
            }
            .onAppear { load() }
        }
        .presentationDetents([.medium, .large])
        .modifier(WealthPrivacyCurtain(armed: true))
    }

    private var itemsSection: some View {
        Section {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                Text(r).font(.subheadline)
            }
        } header: {
            WealthFormHeader(title: fromName.isEmpty ? "要搬的" : "現在在「" + fromName + "」",
                             icon: "arrow.triangle.swap", color: .blue)
        }
    }

    private var targetSection: some View {
        Section {
            if targets.isEmpty {
                Text(toCards ? "沒有別張還在用的卡。" : "沒有別的銀行帳戶。")
                    .foregroundStyle(.secondary)
            } else {
                Picker(toCards ? "改刷" : "改從", selection: $target) {
                    Text("請選擇").tag(nil as UUID?)
                    ForEach(targets) { c in
                        Text(c.label).tag(c.id as UUID?)
                    }
                }
            }
        } header: {
            WealthFormHeader(title: "搬到", icon: toCards ? "creditcard.fill" : "building.columns.fill", color: .blue)
        }
    }

    private var whenSection: some View {
        Section {
            Toggle("以前的也改", isOn: $allPast)
            if !allPast {
                DatePicker("從哪天起", selection: $fromDay, displayedComponents: .date)
            }
        } header: {
            WealthFormHeader(title: "從什麼時候", icon: "calendar", color: .blue)
        } footer: {
            Text(allPast ? "以前的帳也一起算到新的地方。" : "以前的帳照舊記在原本的地方。")
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let facts = lifeStore.wealthFacts(expense: expenseStore, finance: financeStore)
        if toCards {
            targets = WealthFormAccountChoice.cards(facts, excluding: fromId)
            fromName = facts.card(fromId)?.fullName ?? facts.account(fromId)?.name ?? ""
        } else {
            targets = WealthFormAccountChoice.banks(facts, excluding: fromId)
            fromName = facts.account(fromId)?.name ?? facts.card(fromId)?.fullName ?? ""
        }
        var list: [String] = []
        for e in expenseStore.expenses where expenseIds.contains(e.id) {
            list.append(expenseRow(e))
        }
        for i in expenseStore.incomes where incomeIds.contains(i.id) {
            list.append(incomeRow(i))
        }
        rows = list
    }

    /// 「Netflix・NT$390／月」
    private func expenseRow(_ e: Expense) -> String {
        let v = expenseStore.ntdValue(of: e)
        var s = e.title + "・" + WealthFormat.ntd(v)
        if let r = e.recurrence {
            switch r {
            case .monthly: s += "／月"
            case .quarterly: s += "／季"
            case .yearly: s += "／年"
            }
        }
        return s
    }

    /// 「月薪・NT$80,000／月」
    private func incomeRow(_ i: Income) -> String {
        var s = i.title + "・" + WealthFormat.ntd(i.amount)
        switch i.period {
        case .monthly: s += "／月"
        case .yearly: s += "／年"
        case .once: break
        }
        return s
    }

    private func save() {
        guard !isSaving, let t = target else { return }
        isSaving = true
        let life = lifeStore
        let es = expenseStore
        let eIds = expenseIds
        let iIds = incomeIds
        let day: Date? = allPast ? nil : WealthCal.day(fromDay)
        dismiss()
        DispatchQueue.main.async {
            life.moveWealthLinks(expenseIds: eIds, incomeIds: iIds, to: t, from: day, expense: es)
        }
    }
}

// MARK: - 排序與收起來（judge §3.12 最後一列；不擋付費）

/// 排序與收起來的一列
struct WealthOrderItem: Identifiable, Equatable {
    let id: UUID
    let name: String
    let detail: String
    /// 算進存款合計（銀行）
    var counts: Bool
    /// 收起來（銀行、證券戶）／停用（卡）
    var hidden: Bool
    let originalCounts: Bool
    let originalHidden: Bool
}

/// 排序與收起來（⋯ → 一張表單；List edit mode，三段：銀行、信用卡、證券）
struct WealthOrderSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @Environment(\.dismiss) private var dismiss

    @State private var banks: [WealthOrderItem] = []
    @State private var cards: [WealthOrderItem] = []
    @State private var brokers: [WealthOrderItem] = []
    @State private var loaded = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            List {
                bankSection
                cardSection
                brokerSection
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("排序與收起來")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                WealthSaveToolbar(title: "完成", isSaving: isSaving, disabled: false,
                                  onCancel: { dismiss() }, onSave: { save() })
            }
            .onAppear { load() }
        }
        .presentationDetents([.medium, .large])
        .modifier(WealthPrivacyCurtain(armed: true))
    }

    @ViewBuilder
    private var bankSection: some View {
        if !banks.isEmpty {
            Section {
                ForEach($banks) { $item in
                    bankRow($item)
                }
                .onMove { from, to in banks.move(fromOffsets: from, toOffset: to) }
            } header: {
                Text("銀行帳戶")
            } footer: {
                Text("收起來：不算進合計、選單不出現，以前的帳照算；可以再打開。")
            }
        }
    }

    @ViewBuilder
    private var cardSection: some View {
        if !cards.isEmpty {
            Section {
                ForEach($cards) { $item in
                    cardRow($item)
                }
                .onMove { from, to in cards.move(fromOffsets: from, toOffset: to) }
            } header: {
                Text("信用卡")
            } footer: {
                Text("停用：記帳選單不出現，以前刷的帳照算。")
            }
        }
    }

    @ViewBuilder
    private var brokerSection: some View {
        if !brokers.isEmpty {
            Section {
                ForEach($brokers) { $item in
                    brokerRow($item)
                }
                .onMove { from, to in brokers.move(fromOffsets: from, toOffset: to) }
            } header: {
                Text("證券戶")
            }
        }
    }

    private func titleLine(_ item: WealthOrderItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.name).font(.body.weight(.semibold))
            if !item.detail.isEmpty {
                Text(item.detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func bankRow(_ item: Binding<WealthOrderItem>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            titleLine(item.wrappedValue)
            Toggle("算進存款合計", isOn: item.counts).font(.footnote)
            Toggle("收起來", isOn: item.hidden).font(.footnote)
        }
        .padding(.vertical, 2)
    }

    private func cardRow(_ item: Binding<WealthOrderItem>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            titleLine(item.wrappedValue)
            Toggle("停用", isOn: item.hidden).font(.footnote)
        }
        .padding(.vertical, 2)
    }

    private func brokerRow(_ item: Binding<WealthOrderItem>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            titleLine(item.wrappedValue)
            Toggle("收起來", isOn: item.hidden).font(.footnote)
        }
        .padding(.vertical, 2)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let facts = lifeStore.wealthFacts(expense: expenseStore, finance: financeStore)
        // 照財富頁現在的順序列（同 WealthPageData：沒排過的銀行照最近 90 天進出筆數、卡照有要繳／截止日近的在前）；
        // 不然打開什麼都沒動、按〔完成〕，財富頁的順序就被改成里程碑建立的先後（驗證 build/v3/verify/card_text.py G）
        let bankList = WealthPageText.orderBanks(facts.banks)
        banks = bankList.map { a in
            WealthOrderItem(id: a.id, name: a.name, detail: a.nickname != nil ? a.bankName : "",
                            counts: a.countsInCash, hidden: a.hidden,
                            originalCounts: a.countsInCash, originalHidden: a.hidden)
        }
        let cardList = WealthPageText.orderCards(facts.cards)
        cards = cardList.map { c in
            WealthOrderItem(id: c.id, name: c.fullName, detail: c.issuer ?? "",
                            counts: true, hidden: c.isDisabled,
                            originalCounts: true, originalHidden: c.isDisabled)
        }
        let brokerList = Self.ordered(facts.securities.map { ($0.sortIndex, $0) })
        brokers = brokerList.map { a in
            WealthOrderItem(id: a.id, name: a.name, detail: "",
                            counts: a.countsInCash, hidden: a.hidden,
                            originalCounts: a.countsInCash, originalHidden: a.hidden)
        }
    }

    /// 照你排的順序（沒排過的放後面、照原本的先後）
    private static func ordered<T>(_ pairs: [(Int?, T)]) -> [T] {
        var keyed: [(offset: Int, key: Int, value: T)] = []
        for (i, p) in pairs.enumerated() {
            keyed.append((offset: i, key: p.0 ?? Int.max, value: p.1))
        }
        keyed.sort { a, b in
            if a.key != b.key { return a.key < b.key }
            return a.offset < b.offset
        }
        return keyed.map { $0.value }
    }

    /// 完成：先關畫面；下一個 runloop 寫順序（三段串起來一次）、改過的開關
    private func save() {
        guard !isSaving else { return }
        isSaving = true
        let life = lifeStore
        let ids: [UUID] = banks.map(\.id) + cards.map(\.id) + brokers.map(\.id)
        let bankItems = banks
        let cardItems = cards
        let brokerItems = brokers
        dismiss()
        DispatchQueue.main.async {
            life.setWealthOrder(ids)
            for b in bankItems {
                if b.counts != b.originalCounts { life.setWealthCountInCash(b.id, b.counts) }
                if b.hidden != b.originalHidden { life.setWealthHidden(b.id, hidden: b.hidden) }
            }
            for c in cardItems where c.hidden != c.originalHidden {
                life.setCardDisabled(c.id, disabled: c.hidden)
            }
            for s in brokerItems where s.hidden != s.originalHidden {
                life.setWealthHidden(s.id, hidden: s.hidden)
            }
        }
    }
}

// MARK: - 匯率（要確認〔去設定〕；設定頁那一段是 private，這裡另外一張小表單）

/// 匯率一列
struct WealthRateRow: Identifiable {
    let id: UUID
    let code: String
    let original: Double
    var text: String
}

/// 匯率（要確認〔去設定〕；設定頁那一段是 private，這裡另外一張小表單改 ExpenseStore.currencyRates）
struct WealthRatesSheet: View {
    @EnvironmentObject var expenseStore: ExpenseStore
    @Environment(\.dismiss) private var dismiss

    @State private var rows: [WealthRateRow] = []
    @State private var newCode = ""
    @State private var newRate = ""
    @State private var loaded = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                listSection
                addSection
            }
            .navigationTitle("匯率")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                WealthSaveToolbar(title: "存", isSaving: isSaving, disabled: false,
                                  onCancel: { dismiss() }, onSave: { save() })
            }
            .onAppear { load() }
        }
        .presentationDetents([.medium, .large])
        .modifier(WealthPrivacyCurtain(armed: true))
    }

    @ViewBuilder
    private var listSection: some View {
        if !rows.isEmpty {
            Section {
                ForEach($rows) { $row in
                    rateRow($row)
                }
            } header: {
                Text("1 單位＝幾台幣")
            } footer: {
                Text("跟設定 › 匯率是同一份；有開自動更新的，下次更新會換成最新的。")
            }
        }
    }

    private func rateRow(_ row: Binding<WealthRateRow>) -> some View {
        HStack {
            Text(row.wrappedValue.code)
            Spacer()
            TextField("匯率", text: row.text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
        }
    }

    private var addSection: some View {
        Section {
            TextField("幣別（例：美金）", text: $newCode)
            TextField("1 單位＝幾台幣（例：32.05）", text: $newRate)
                .keyboardType(.decimalPad)
        } header: {
            Text("加一個幣別")
        } footer: {
            Text("幣別的名字要跟記帳、銀行帳戶裡用的一樣（例：美金）。")
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        rows = expenseStore.currencyRates.map { r in
            WealthRateRow(id: r.id, code: r.code, original: r.rate, text: WealthFormText.rateText(r.rate))
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        var list: [CurrencyRate] = rows.map { (r: WealthRateRow) -> CurrencyRate in
            var v = r.original
            if let x = Double(r.text.trimmingCharacters(in: .whitespaces)), x > 0, x.isFinite { v = x }
            return CurrencyRate(id: r.id, code: r.code, rate: v)
        }
        let code = newCode.trimmingCharacters(in: .whitespaces)
        if !code.isEmpty, !list.contains(where: { $0.code == code }),
           let x = Double(newRate.trimmingCharacters(in: .whitespaces)), x > 0, x.isFinite {
            list.append(CurrencyRate(code: code, rate: x))
        }
        let es = expenseStore
        let changed = list.count != rows.count || zip(list, rows).contains(where: { pair in pair.0.rate != pair.1.original })
        dismiss()
        guard changed else { return }
        let result = list
        DispatchQueue.main.async { es.currencyRates = result }
    }
}

// MARK: - 要確認（judge §3.5、樣稿③-C5；財富頁 ②、卡片頁 ② 共用）

/// 會改資料、要先問一句的那兩種
enum WealthCheckAsk: Identifiable {
    case endRecurring(ids: [UUID], on: Date, title: String, message: String)
    case fixFX(accountId: UUID, depositId: UUID, amount: Double, title: String, message: String)

    var id: String {
        switch self {
        case .endRecurring(let ids, _, _, _): return "end-" + ids.map(\.uuidString).joined(separator: ",")
        case .fixFX(_, let dep, _, _, _): return "fx-" + dep.uuidString
        }
    }

    var title: String {
        switch self {
        case .endRecurring(_, _, let t, _): return t
        case .fixFX(_, _, _, let t, _): return t
        }
    }

    var message: String {
        switch self {
        case .endRecurring(_, _, _, let m): return m
        case .fixFX(_, _, _, _, let m): return m
        }
    }

    var confirmTitle: String {
        switch self {
        case .endRecurring: return "已經退訂"
        case .fixFX: return "改過來"
        }
    }
}

/// 確認框（拆成 ViewModifier：Section 的 body 已經掛了 sheet、付費說明，坑 #7）
struct WealthCheckAskDialog: ViewModifier {
    @Binding var ask: WealthCheckAsk?
    let onConfirm: (WealthCheckAsk) -> Void

    func body(content: Content) -> some View {
        content.alert(
            ask?.title ?? "",
            isPresented: Binding(get: { ask != nil }, set: { if !$0 { ask = nil } }),
            presenting: ask
        ) { a in
            Button(a.confirmTitle) { onConfirm(a) }
            Button("取消", role: .cancel) {}
        } message: { a in
            Text(a.message)
        }
    }
}

/// 要確認（財富頁 ②、卡片頁 ② 共用；0 件整區不出現）。limit：先放幾件，「再看 N 件」
struct WealthChecksSection: View {
    let checks: [WealthCheck]
    var limit: Int? = 3
    /// [v25.565] #12〔看綁了哪些〕（WealthCheck.Fix.openCard）交給呼叫端：財富頁開那張卡的卡片頁、卡片頁自己捲到定期扣款。
    /// nil＝這裡自己開一張卡片頁（WealthFormSheet.card，捲到定期扣款）
    var onOpenCard: ((UUID) -> Void)? = nil

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.colorScheme) private var scheme

    @State private var expanded = false
    @State private var sheet: WealthFormSheet?
    @State private var ask: WealthCheckAsk?
    @State private var showPremium = false

    private var visible: [WealthCheck] {
        guard let n = limit, !expanded, checks.count > n else { return checks }
        return Array(checks.prefix(n))
    }

    var body: some View {
        if !checks.isEmpty {
            content
                .sheet(item: $sheet) { s in
                    s.view.appStores()
                }
                .modifier(WealthCheckAskDialog(ask: $ask, onConfirm: { a in perform(a) }))
                .premiumLockAlert(isPresented: $showPremium)
        }
    }

    private var content: some View {
        let pal = TripBoardPalette(scheme)
        let rows = visible
        let more = checks.count - rows.count
        return VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "要確認", trailing: "\(checks.count) 件")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, c in
                    if i > 0 {
                        Divider().padding(.leading, 44)
                    }
                    row(c, pal: pal)
                }
                if more > 0 {
                    moreRow(more)
                }
            }
            .modifier(FinanceCardChrome())
        }
    }

    private func row(_ c: WealthCheck, pal: TripBoardPalette) -> some View {
        FinanceCheckRow(icon: c.icon, message: c.text, buttons: buttons(c),
                        accessibilityLabel: c.accessibilityLabel, pal: pal)
    }

    private func buttons(_ c: WealthCheck) -> [FinanceCheckButton] {
        c.actions.map { a in
            FinanceCheckButton(title: a.title, action: { tap(a.fix, check: c) })
        }
    }

    private func moreRow(_ n: Int) -> some View {
        VStack(spacing: 0) {
            Divider().padding(.leading, 14)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded = true }
            } label: {
                Text("再看 \(n) 件")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
    }

    // MARK: 按鈕（不在背景偷偷改，都是你按了才改；開表單的照那張表單擋付費）

    private func tap(_ fix: WealthCheck.Fix, check: WealthCheck) {
        let life = lifeStore
        switch fix {
        case .dismiss:
            life.dismissWealthCheck(check.id)
        case .transfer(let toId, let fromId, let amount):
            guard subscription.isPremium else { showPremium = true; return }
            sheet = .transfer(from: fromId, to: toId, amount: amount)
        case .confirmPaid(let cardId, let key, let day, let src):
            life.markStatementPaid(cardId: cardId, key: key, date: day, account: src, amount: nil)
        case .editPaid(let cardId, let key):
            sheet = .paid(cardId: cardId, key: key)
        case .markNotPaid(let cardId, let key):
            life.markStatementNotPaid(cardId: cardId, key: key)
        case .excludeExpense(let expenseId):
            life.excludeExpenseFromWealth(expenseId, excluded: true)
        case .moveRecurring(let cardId, let ids):
            guard subscription.isPremium else { showPremium = true; return }
            sheet = .move(fromId: cardId, expenseIds: ids, toCards: true)
        case .endRecurring(let ids, let day):
            ask = endRecurringAsk(ids, on: day)
        case .editAccount(let id):
            guard subscription.isPremium else { showPremium = true; return }
            openEditor(id, check: check)
        case .fixLegacyFX(let accountId, let depositId, let amount):
            ask = fixFXAsk(accountId: accountId, depositId: depositId, amount: amount)
        case .openRates:
            sheet = .rates
        case .anchor(let accountId, let code):
            guard subscription.isPremium else { showPremium = true; return }
            sheet = .anchor(accountId: accountId, code: code)
        case .openCard(let cardId):
            // [v25.565] #12〔看綁了哪些〕：看卡片頁不擋訂閱（改綁定要到記帳改，那邊自己擋）
            openCard(cardId)
        case .setMaturity(let depositId, let raw):
            // [v25.566] #13 改到期處理（改成轉活存／本息續存）：不擋訂閱（跟標成已繳一樣是處理到期的事）；
            // 下一個 runloop 才寫（自動續存還沒寫進帳本的那一期，LifeStore 先寫進去再改）
            let mode = WealthMaturityMode.of(raw)
            DispatchQueue.main.async {
                life.setTimeDepositOnMaturity(depositId, mode: mode)
            }
        case .editTimeDeposit(let accountId, let depositId):
            // [v25.566] 舊的定存帳戶〔補資料〕：開定存表單（要訂閱）
            guard subscription.isPremium else { showPremium = true; return }
            sheet = .timeDeposit(accountId: accountId, editing: depositId)
        case .quietInsurance(let key):
            // [v25.566] #14 存款保險〔知道了〕：這家銀行一年內不再提（不擋訂閱）
            life.quietDepositInsurance(key)
        }
    }

    /// [v25.565] 打開那張卡、捲到綁在這張卡的定期扣款：呼叫端有給就交給它，不然這裡自己開一張
    private func openCard(_ id: UUID) {
        if let handler = onOpenCard {
            handler(id)
        } else {
            sheet = .card(id)
        }
    }

    /// 〔填日子〕捲到帳單那段、〔選帳戶〕捲到卡費怎麼繳
    private func openEditor(_ id: UUID, check: WealthCheck) {
        guard let m = lifeStore.milestones.first(where: { $0.id == id }),
              let kind = WealthAccountKind(sub: m.financeSubCategory) else { return }
        let focus: WealthEditorFocus?
        switch check.kind {
        case .cardDaysMissing: focus = .cardDays
        case .noPayer: focus = .payFrom
        default: focus = nil
        }
        sheet = .editor(kind: kind, item: m, focus: focus)
    }

    /// 「Disney+ 從 6/30 起不再扣？」
    private func endRecurringAsk(_ ids: [UUID], on day: Date) -> WealthCheckAsk {
        let names: [String] = expenseStore.expenses.filter { ids.contains($0.id) }.map(\.title)
        let who: String = names.isEmpty ? "這幾筆定期扣款" : names.joined(separator: "、")
        let title = who + " 從 " + WealthFormat.monthDay(day) + " 起不再扣？"
        let message = "那天那一期照扣，之後不再算進卡費；記帳裡的這幾筆會設好結束日。"
        return .endRecurring(ids: ids, on: day, title: title, message: message)
    }

    /// 「改成 美金 10.00？」原本記成多少 → 改成多少
    private func fixFXAsk(accountId: UUID, depositId: UUID, amount: Double) -> WealthCheckAsk {
        let dep: BankDeposit? = lifeStore.milestones.first(where: { $0.id == accountId })?
            .bankDeposits?.first(where: { $0.id == depositId })
        let code: String = dep?.currencyCode ?? "NT$"
        let after = WealthFormat.money(amount, code: code)
        let title = "改成 " + after + "？"
        var message = "照現在的匯率改成 " + after + "。"
        if let d = dep {
            message = "原本記成 " + WealthFormat.money(d.amount, code: code) + "（那是台幣的數字），照現在的匯率改成 "
                + after + "。"
        }
        return .fixFX(accountId: accountId, depositId: depositId, amount: amount, title: title, message: message)
    }

    private func perform(_ a: WealthCheckAsk) {
        switch a {
        case .endRecurring(let ids, let day, _, _):
            lifeStore.endRecurring(expenseIds: ids, on: day, expense: expenseStore)
        case .fixFX(let accountId, let depositId, let amount, _, _):
            lifeStore.fixLegacyFX(accountId: accountId, depositId: depositId, amount: amount)
        }
    }
}
