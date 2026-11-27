import SwiftUI

// MARK: - [v25.566] 定存表單（財富 v5；wealth/judge.md §5.5、§4.2 ⑥、§5.6；build/v5/brief.md §G3）
//
// 一個入口 WealthTimeDepositSheet(accountId:editing:)：新增／看／改一期定存，提前解約、到期轉活存、刪除也在這張。
// 誰會打開它（呼叫端一律 .sheet(item:) { … .appStores() }，要訂閱：新增、編輯、刪除，待決定 10）：
// • 財富頁右上＋「定存」（accountId nil：第一欄選哪個銀行帳戶）
// • 銀行帳戶頁 ⑥ 定存〔＋ 定存〕、點一期、記一筆選單「定存」、明細／接下來 30 天點「轉定存」「定存到期」那幾列
// • 要確認〔補資料〕（舊的「定存」種類帳戶：WealthCheck.Fix.editTimeDeposit(accountId:depositId: nil)）
// 存的地方：LifeStore.saveTimeDeposit（財富帳本・定存那一包，同步鍵 life_wealth_deposits_v1）。
// 數字一律讀 WealthFacts（lifeStore.wealthFacts，打開表單時抓一次存 @State，打字不重算）；預估利息用 WealthDepositMath（純算式）。
// 先 dismiss、下一個 runloop 才寫 store；儲存鈕忙碌守衛；刪除一律先問；表單自己掛 WealthPrivacyCurtain。
//
// 分工：G3 實作（這個檔＋WealthEditors.swift）。主控只放能編譯的入口，簽章不要改（G1、G2、WealthEditors 在叫）。
//
// 做法（G3）：
// • 打開時抓一次（onAppear → load）：帳戶選單（facts.banks 沒收起來的，含舊的定存種類；帶了帳戶或編輯時鎖住那個帳戶）、
//   轉進哪個帳戶的選單（facts.pickerBanks）、這一期的狀態（facts.timeDeposit(editing)）、帳本那一筆（lifeStore.timeDepositRecord：
//   自動續存還沒寫進帳本的那一期也給，previousId 在）、同一串有幾期與起存時從活存轉出多少（刪除時問）。
// • 欄位（§5.5）：銀行帳戶、幣別（這個帳戶有的）、本金（元或萬）、年利率（選填）、起存日、期別（1／3／6／9／12／24／36 個月或自己選
//   到期日）、到期怎麼處理（本金續存、轉活存才問轉進哪個帳戶）、從活存轉出（新增預設開；舊的定存種類帳戶、自動續存的那一期不問）、
//   存單號碼末 4 碼（只存末 4 碼）、到期前 7 天提醒、備註。
// • 即時預估：欄位組一筆草稿 WealthTimeDeposit（draft），讀它自己的 maturityDate／estimatedInterest（＝WealthDepositMath，跟一套數字同一支），
//   不另外算一份。
// • 舊的「定存」種類帳戶〔補資料〕（還沒有任何一期）：本金帶存摺上、起存日帶這個帳戶最早一筆紀錄的日子（沒有用開戶日）、期別 12；
//   [審查] 那天一年以前的話，一年一年往後推到現在這一期（今天以前到期的那幾期利息不會再記進存摺一次，存完存款合計不變）。
// • 看／改：最上面一句（TimeDeposit.maturityLine、modeSentence）；到期再決定已經到期〔到期了，轉活存〕、〔提前解約〕／〔取消解約〕、
//   〔刪除這筆定存〕，都先問（WealthDepositAskDialog，一個 enum 管）。
// • 已經到期、自動續存成下一期的那一期只能看、可以刪：改它的本金、利率、到期處理會讓已經接上的下一期對不上
//   （下一期的本金、起存日是照它算的；saveTimeDeposit 只換掉這一筆、不會拿掉下一期，改成轉活存錢會算兩次），要改請打開下一期。
//   [審查] 到期轉活存結束的那一期沒有下一期，照樣可以改（記錯本金、利率改得回來）。
// • 欄位連動用自訂 Binding（換帳戶、起存日、期別），不用 onChange：打開時帶值不會觸發連動、蓋掉帶進來的到期日。
// • [v25.566 裁定] 整串都已經結束（到期轉回活存、解約）的定存，刪除只有一顆〔刪除〕、不給〔留著那一筆轉出〕：
//   錢早就回到活存了，留著轉出＝只剩一筆提款、到期入帳那一列卻跟著拿掉，存摺上平白少本息（例 −508,500）。

/// 定存表單（新增：editing nil；看／改：editing＝WealthFacts.TimeDeposit.id，自動續存還沒寫進帳本的那一期也可以）
struct WealthTimeDepositSheet: View {
    /// 帶這個帳戶（財富頁右上＋「定存」沒帶＝nil：第一欄選）
    var accountId: UUID? = nil
    /// 看／改哪一期（nil＝新增）
    var editing: UUID? = nil

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @Environment(\.dismiss) private var dismiss

    /// 選單一列（打開時從 WealthFacts 抓一次）
    struct DepositBank: Identifiable, Equatable {
        let id: UUID
        /// 「薪轉」「台灣銀行」
        let name: String
        /// 帳戶選單：「薪轉（台新銀行）」「台灣銀行・以前記的定存」
        let label: String
        /// 轉進哪個帳戶：「薪轉（台新銀行・存摺 NT$12.8萬）」
        let pickerLabel: String
        /// 這個帳戶有的幣別（台幣在前）
        let codes: [String]
        /// 舊的「定存」種類帳戶（存摺上就是定存的錢）
        let legacy: Bool
        /// 每個幣別的存摺上（舊的定存帳戶〔補資料〕帶本金）
        let balances: [String: Double]
        /// 開戶日（沒有任何紀錄時當起存日）
        let openedDate: Date

        init(_ a: WealthFacts.Account) {
            id = a.id
            name = a.name
            var s = a.name
            if a.name != a.bankName { s += "（" + a.bankName + "）" }
            if a.isFixedDeposit { s += "・以前記的定存" }
            label = s
            pickerLabel = a.pickerLabel
            codes = a.currencies.isEmpty ? ["NT$"] : a.currencies
            legacy = a.isFixedDeposit
            balances = a.balances
            openedDate = a.openedDate
        }
    }

    /// 期別（月）；選單最後一個 0＝自己選到期日
    private static let termChoices: [Int] = [1, 3, 6, 9, 12, 24, 36]

    private static let noBankText = "還沒有銀行帳戶：先在財富頁右上＋新增一個銀行帳戶，再回來記定存。"
    private static let legacyPrefillHint = "本金帶的是存摺上的數字，起存日從這個帳戶最早一筆紀錄的日子一年一年往後推到現在這一期；跟存單不一樣就改。"
    private static let legacyNoTransfer = "這個帳戶是以前記的定存：存摺上的數字就是這筆定存，不另外轉出。"
    private static let renewedNoTransfer = "這一期是上一期自動續存的，錢本來就在定存裡，不另外轉出。"
    private static let rateHint = "沒填利率就不估利息"
    private static let estimateHint = "利息只是預估（單利、未扣稅），以銀行入帳為準。"
    private static let reopenHint = "解約記錯了才按：這筆定存回到存著的樣子，解約那天的入帳拿掉。"
    private static let endedDeleteHint = "這筆定存已經結束（到期轉回活存或解約）：刪掉的話，明細裡它算出來的那幾列（轉定存、到期入帳、利息）都一起拿掉，存摺上的數字跟著變。"

    // 打開時抓一次
    @State private var loaded = false
    @State private var today = WealthCal.day(Date())
    @State private var banks: [DepositBank] = []
    @State private var payoutBanks: [DepositBank] = []
    @State private var record: WealthTimeDeposit?
    @State private var term: WealthFacts.TimeDeposit?
    /// 帳戶鎖住（帶了帳戶、編輯）
    @State private var lockAccount = false
    /// 同一串有幾期（刪除時說「自動續存的那幾期也一起刪」）
    @State private var chainCount = 1
    /// 起存時從活存轉出的本金（「500,000」；沒有＝nil：刪除只有一顆〔刪除〕）
    @State private var movedText: String?
    /// [v25.566 裁定] 整串都結束了（到期轉回活存、解約；一套數字裡沒有任何一期還存著）：錢已經回到活存，
    /// 刪除不給〔留著那一筆轉出〕（留著＝只剩一筆提款、到期入帳那一列卻拿掉了，存摺上平白少本息）
    @State private var chainEnded = false
    /// 新增那一筆的 id（草稿每次重組都用同一個）
    @State private var newId = UUID()
    /// 編輯的那一期期別不在選單裡（例：18 個月）
    @State private var oddTerm: Int?
    /// 舊的定存帳戶〔補資料〕：本金、起存日是帶進來的
    @State private var prefilledLegacy = false

    // 欄位
    @State private var pickedAccount: UUID?
    @State private var code = "NT$"
    @State private var principalText = ""
    @State private var rateText = ""
    @State private var start = Date()
    @State private var termMonths = 12
    @State private var customMaturity = Date()
    @State private var mode: WealthMaturityMode = .renewAll
    /// 轉進哪個帳戶（nil＝這個帳戶自己）
    @State private var payout: UUID?
    @State private var fromLive = true
    @State private var last4 = ""
    @State private var remind = true
    @State private var note = ""

    // 提前解約、確認框
    @State private var closing = false
    @State private var closeDate = Date()
    @State private var closeInterestText = ""
    @State private var ask: WealthDepositAsk?
    @State private var isSaving = false

    // MARK: 狀態

    private var isNew: Bool { editing == nil }

    private var navTitle: String { isNew ? "新增定存" : "定存" }

    /// 編輯的那一筆找不到了（刪掉了）
    private var missing: Bool { editing != nil && loaded && record == nil }

    /// 新增、一個銀行帳戶都沒有
    private var noBanks: Bool { isNew && loaded && banks.isEmpty }

    /// 已經到期、自動續存成下一期的那一期（不在一套數字的「沒開始、存著、到期待決定」裡、不是解約、到期處理是續存）：只能看、可以刪。
    /// [審查] 到期轉活存結束的那一期沒有接下一期，改了不會對不上，照樣可以改
    private var locked: Bool {
        guard let r = record else { return false }
        return term == nil && r.closedDate == nil && r.mode.renews
    }

    private var showsFields: Bool { !missing && !noBanks }

    private var pickedBank: DepositBank? { banks.first { $0.id == pickedAccount } }

    private var isLegacy: Bool { pickedBank?.legacy ?? (term?.isLegacyAccount ?? false) }

    /// 帳戶名（「台灣銀行」）
    private var accountName: String { pickedBank?.name ?? term?.accountName ?? "這個帳戶" }

    private var bankCodes: [String] { pickedBank?.codes ?? ["NT$"] }

    /// 幣別選單（編輯的那一筆幣別不在帳戶裡也放進來）
    private var codeOptions: [String] {
        var list = bankCodes
        if !list.contains(code) { list.append(code) }
        return list
    }

    private var termOptions: [Int] {
        var list = Self.termChoices
        if let o = oddTerm, !list.contains(o) {
            list.append(o)
            list.sort()
        }
        list.append(0)
        return list
    }

    /// 本金（元或萬；台幣到元、外幣到 0.01）；讀不懂或 ≤ 0＝nil
    private var principalValue: Double? {
        guard let v = WealthFormText.number(principalText), v > 0 else { return nil }
        if FinanceRates.isNTD(code) { return v.rounded() }
        return (v * 100).rounded() / 100
    }

    /// 「＝ NT$500,000」（打「50萬」時看得到換算）
    private var principalEcho: String? {
        principalValue.map { "＝ " + WealthFormat.money($0, code: code) }
    }

    private var rateClean: String {
        rateText.replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "％", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    /// 年利率（%）；沒填、0、看不懂＝nil
    private var rateValue: Double? {
        guard let v = Double(rateClean), v.isFinite, v > 0, v < 100 else { return nil }
        return v
    }

    private var rateInvalid: Bool {
        let t = rateClean
        guard !t.isEmpty else { return false }
        guard let v = Double(t), v.isFinite else { return true }
        return v < 0 || v >= 100
    }

    private var showsPayout: Bool { mode == .renewPrincipal || mode == .toLive }

    /// 存的 payoutId：看得到選單時照選的（選自己＝nil）；看不到時不改原本的
    private var savedPayout: UUID? {
        guard showsPayout else { return record?.payoutId }
        guard let p = payout, p != pickedAccount else { return nil }
        return p
    }

    private var payoutChoices: [DepositBank] { payoutBanks.filter { $0.id != pickedAccount } }

    private var selfPayoutLabel: String {
        guard let b = pickedBank else { return "這個帳戶" }
        return b.name + "（這個帳戶）"
    }

    /// 錢轉進哪裡（字）
    private var payoutName: String {
        guard let p = payout, p != pickedAccount else { return accountName }
        return payoutBanks.first(where: { $0.id == p })?.name ?? "選的帳戶"
    }

    /// 從活存轉出：舊的定存種類帳戶、自動續存的那一期不問
    private var showsFromLiveToggle: Bool { !isLegacy && record?.previousId == nil }

    private var minMaturity: Date { WealthCal.addDays(1, to: WealthCal.day(start)) }

    /// 照欄位組一筆（存檔、即時預估都用它：到期日、預估利息讀 WealthTimeDeposit 自己的算法）
    private var draft: WealthTimeDeposit {
        // 每個值先放進有型別的常數（呼叫式裡不放三元＋nil，型別檢查快）
        let custom: Bool = termMonths <= 0
        let id: UUID = record?.id ?? newId
        let bank: UUID = pickedAccount ?? newId
        let principal: Double = principalValue ?? 0
        let currency: String? = FinanceRates.isNTD(code) ? nil : code
        let day: Date = WealthCal.day(start)
        let months: Int? = custom ? nil : termMonths
        let maturity: Date? = custom ? WealthCal.day(customMaturity) : nil
        let onMaturity: String? = mode == .renewAll ? nil : mode.rawValue
        let moved: Bool? = (fromLive && showsFromLiveToggle) ? true : nil
        let cert: String = WealthFormText.digits(last4, limit: 4)
        let certValue: String? = cert.isEmpty ? nil : cert
        let remindValue: Bool? = remind ? nil : false
        let trimmedNote: String = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteValue: String? = trimmedNote.isEmpty ? nil : trimmedNote
        return WealthTimeDeposit(id: id, bankId: bank, principal: principal, currency: currency, rate: rateValue,
                                 start: day, months: months, maturity: maturity, onMaturity: onMaturity,
                                 fromLive: moved, payoutId: savedPayout, certificateLast4: certValue,
                                 remind: remindValue, closedDate: record?.closedDate,
                                 closedInterest: record?.closedInterest, previousId: record?.previousId,
                                 note: noteValue)
    }

    /// 到期日晚於起存日
    private var maturityOK: Bool {
        guard let m = draft.maturityDate else { return false }
        return m > WealthCal.day(start)
    }

    /// 必填：帳戶、本金 > 0、到期日（期別或自己選）晚於起存日；利率打了要看得懂
    private var canSave: Bool {
        guard loaded, !missing, !locked, pickedBank != nil, principalValue != nil, !rateInvalid else { return false }
        return maturityOK
    }

    /// 「預估利息 約 8,500（單利、未扣稅）・到期 2027/3/15・本息 508,500」
    private var previewText: String? {
        let d = draft
        guard let m = d.maturityDate, m > WealthCal.day(d.start) else { return nil }
        let end = "到期 " + WealthFormat.ymd(m)
        guard d.principal > 0 else { return end }
        guard (d.rate ?? 0) > 0 else { return "沒填利率，不估利息・" + end }
        let i: Double = d.estimatedInterest
        let interest: String = WealthFormat.plain(i, code: d.code)
        let total: String = WealthFormat.plain(d.principal + i, code: d.code)
        return "預估利息 約 \(interest)（單利、未扣稅）・\(end)・本息 \(total)"
    }

    private var depositFooter: String {
        var parts: [String] = []
        if rateInvalid {
            parts.append("利率看不懂：打數字就好（例：1.7）。")
        } else if rateValue == nil {
            parts.append(Self.rateHint)
        } else {
            parts.append(Self.estimateHint)
        }
        if prefilledLegacy { parts.append(Self.legacyPrefillHint) }
        return parts.joined(separator: "\n")
    }

    /// 期間那一段的紅字（沒問題＝nil）
    private var periodError: String? {
        maturityOK ? nil : "到期日要晚於起存日"
    }

    private var modeFooter: String {
        switch mode {
        case .renewAll: return "到期那天本息自動接成下一期，不用再記。"
        case .renewPrincipal: return "到期那天本金接成下一期，利息轉進" + payoutName + "。"
        case .toLive: return "到期那天本息轉進" + payoutName + "，存摺上跟著變。"
        case .decide: return "到期那天先留在定存裡，要確認會問你要轉活存還是續存。"
        }
    }

    /// 「起存那天這個帳戶的明細多一列「轉定存 −500,000」」
    private var fromLiveFooter: String {
        guard fromLive else {
            return "關掉：錢不是從這個帳戶的活存轉過去的（例如拿現金去存），存摺上的數字不動。"
        }
        let amount: String = principalValue.map { WealthFormat.plain($0, code: code) } ?? "本金"
        return "起存那天這個帳戶的明細多一列「轉定存 −" + amount + "」"
    }

    private var extrasFooter: String {
        var s = "存單號碼只存末 4 碼。"
        if remind {
            let md: String = draft.maturityDate.map { WealthFormat.monthDay($0) } ?? "到期日"
            s += "通知只寫「定存 \(md) 到期（7 天後）」，不寫銀行、金額、號碼；設定 › 財富提醒關掉時都不排。"
        } else {
            s += "這一筆不提醒。"
        }
        return s
    }

    /// 已經到期結束的那一期（一套數字裡沒有、不是解約）最上面那一句：續存的只能看；轉活存的可以改（沒有就 nil）
    private var endedText: String? {
        guard let r = record, term == nil, r.closedDate == nil else { return nil }
        let end: String = r.maturityDate.map { WealthFormat.ymd($0) } ?? ""
        if r.mode.renews {
            return "這一期 " + end + " 到期，已經自動續存成下一期了；要改利率、到期處理請打開下一期。這裡只能看，也可以刪掉整串。"
        }
        return "這一期 " + end + " 到期，本息已經轉進" + payoutName + "。記錯了可以改，那天入帳的數字跟著變。"
    }

    /// 解約記錄那一列：「2026/11/1・利息 2,000」
    private var closedDayText: String {
        guard let r = record, let c = r.closedDate else { return "" }
        var s = WealthFormat.ymd(c)
        if let i = r.closedInterest, i > 0 { s += "・利息 " + WealthFormat.plain(i, code: r.code) }
        return s
    }

    /// 解約、到期轉活存的錢轉進哪裡
    private var closeTarget: String { term?.payoutName ?? term?.accountName ?? accountName }

    private var closeInterestValue: Double? {
        WealthFormText.number(closeInterestText).flatMap { $0 > 0 ? $0 : nil }
    }

    /// 解約日：不早於起存日、早於到期日
    private var closeRange: ClosedRange<Date> {
        let lo: Date = WealthCal.day(record?.start ?? today)
        var hi: Date = WealthCal.addDays(3650, to: today)
        if let m = record?.maturityDate { hi = WealthCal.addDays(-1, to: m) }
        if hi < lo { hi = lo }
        return lo...hi
    }

    private var closeFooter: String {
        if closing {
            return "實拿利息照銀行給的數字；沒填當 0。本金加利息轉進" + closeTarget + "。"
        }
        return "解約那天本金加實拿的利息轉進" + closeTarget + "，之後不再算定存。"
    }

    /// 「本息 508,500 在 3/15 那天轉進台灣銀行」
    private var toLiveSentence: String {
        guard let t = term else { return "本息轉進" + closeTarget }
        let total: String = WealthFormat.plain(t.maturityAmount, code: t.code)
        let day: String = t.maturityText(today) ?? "到期日"
        let to: String = t.payoutName ?? t.accountName
        return "本息 \(total) 在 \(day) 那天轉進\(to)"
    }

    private var toLiveFooter: String {
        toLiveSentence + "。要續存的話，在上面「到期怎麼處理」改好再按儲存。"
    }

    private var removeTitle: String { "一起拿掉（錢回到" + accountName + "）" }

    private var askTitle: String {
        guard let a = ask else { return "" }
        switch a {
        case .toLive: return "到期了，轉活存？"
        case .close: return "提前解約這筆定存？"
        case .reopen: return "取消解約？"
        case .delete: return "刪掉這筆定存？"
        }
    }

    private var askMessage: String {
        guard let a = ask else { return "" }
        switch a {
        case .toLive:
            return toLiveSentence + "，存摺上跟著變。"
        case .close:
            return closeSentence
        case .reopen:
            return Self.reopenHint
        case .delete:
            return deleteSentence
        }
    }

    /// 「2026/11/1 解約：本金 500,000＋利息 2,000 轉進台灣銀行，之後不再算定存。」
    private var closeSentence: String {
        guard let r = record else { return "" }
        let day: String = WealthFormat.ymd(closeDate)
        let p: String = WealthFormat.plain(r.principal, code: r.code)
        let i: String = WealthFormat.plain(closeInterestValue ?? 0, code: r.code)
        let to: String = closeTarget
        return "\(day) 解約：本金 \(p)＋利息 \(i) 轉進\(to)，之後不再算定存。"
    }

    private var deleteSentence: String {
        var parts: [String] = []
        if chainCount > 1 {
            parts.append("自動續存的那幾期也一起刪（共 \(chainCount) 期）。")
        } else if !chainEnded {
            parts.append("刪掉後不再算進存款合計。")
        }
        if chainEnded {
            parts.append(Self.endedDeleteHint)
        } else if let m = movedText {
            let name: String = accountName
            parts.append("起存時從活存轉出的 \(m)：一起拿掉，錢回到\(name)；留著，記成一筆提款，存摺上的錢不回來。")
        }
        return parts.joined(separator: "\n")
    }

    // MARK: 連動（只在你動了才連動；打開時帶值不觸發）

    private var accountBinding: Binding<UUID?> {
        Binding(get: { pickedAccount }, set: { new in
            pickedAccount = new
            accountChanged(to: new)
        })
    }

    /// 改起存日：自己選的到期日不晚於起存日時，改成起存日後一年
    private var startBinding: Binding<Date> {
        Binding(get: { start }, set: { new in
            start = new
            let lo = WealthCal.addDays(1, to: WealthCal.day(new))
            if customMaturity < lo { customMaturity = WealthCal.addMonths(12, to: WealthCal.day(new)) }
        })
    }

    /// 改成「自己選到期日」：到期日先帶原本期別算出來的那天
    private var termBinding: Binding<Int> {
        Binding(get: { termMonths }, set: { new in
            if new <= 0 && termMonths > 0 {
                customMaturity = WealthCal.addMonths(termMonths, to: WealthCal.day(start))
            }
            termMonths = new
        })
    }

    // MARK: 畫面（body 只排 Section）

    var body: some View {
        NavigationStack {
            Form {
                topSection
                mainSections
                moreSections
                actionSections
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                WealthSaveToolbar(title: isNew ? "存" : "儲存", isSaving: isSaving, disabled: !canSave,
                                  showsSave: showsFields && !locked,
                                  onCancel: { dismiss() }, onSave: { save() })
            }
            .onAppear { load() }
            .modifier(WealthDepositAskDialog(ask: $ask, title: askTitle, message: askMessage,
                                             removeTitle: removeTitle, offersKeep: movedText != nil,
                                             onChoose: { a, keep in perform(a, keepTransfer: keep) }))
        }
        .presentationDetents([.medium, .large])
        .modifier(WealthPrivacyCurtain(armed: true))
    }

    @ViewBuilder
    private var topSection: some View {
        if missing {
            Section {
                Text("找不到這筆定存，可能已經刪掉了。")
                    .foregroundStyle(.secondary)
            }
        } else if noBanks {
            Section {
                Text(Self.noBankText)
                    .foregroundStyle(.secondary)
            }
        } else if let t = term {
            Section {
                summaryRow(t)
            }
        } else if let s = endedText {
            Section {
                Text(s)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func summaryRow(_ t: WealthFacts.TimeDeposit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t.displayTitle)
                .font(.headline)
            Text(summaryLine(t))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(t.modeSentence(masked: false))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// 「3/15 到期・還有 147 天・預估利息 8,500」（自動續存的那一期加「・第 2 期」）
    private func summaryLine(_ t: WealthFacts.TimeDeposit) -> String {
        var s = t.maturityLine(today: today, masked: false)
        if t.termIndex > 0 { s += "・第 \(t.termIndex + 1) 期" }
        return s
    }

    @ViewBuilder
    private var mainSections: some View {
        if showsFields {
            depositSection
            periodSection
            maturitySection
        }
    }

    @ViewBuilder
    private var moreSections: some View {
        if showsFields {
            fromLiveSection
            extrasSection
            previewSection
            noteSection
        }
    }

    private var depositSection: some View {
        Section {
            accountRow
            codeRow
            principalRow
            rateRow
        } header: {
            WealthFormHeader(title: "這筆定存", icon: "lock.fill", color: .orange)
        } footer: {
            Text(depositFooter)
        }
        .disabled(locked)
    }

    @ViewBuilder
    private var accountRow: some View {
        if lockAccount {
            LabeledContent("銀行帳戶", value: pickedBank?.label ?? accountName)
        } else {
            Picker("銀行帳戶", selection: accountBinding) {
                Text("請選擇").tag(nil as UUID?)
                ForEach(banks) { b in
                    Text(b.label).tag(b.id as UUID?)
                }
            }
        }
    }

    @ViewBuilder
    private var codeRow: some View {
        if codeOptions.count > 1 {
            Picker("幣別", selection: $code) {
                ForEach(codeOptions, id: \.self) { c in
                    Text(Self.codeName(c)).tag(c)
                }
            }
        } else {
            LabeledContent("幣別", value: Self.codeName(code))
        }
    }

    private var principalRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("本金")
                Spacer()
                TextField("500,000 或 50萬", text: $principalText)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
            }
            if let echo = principalEcho {
                Text(echo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rateRow: some View {
        HStack {
            Text("年利率（%）")
            Spacer()
            TextField("選填，例：1.7", text: $rateText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }

    private var periodSection: some View {
        Section {
            DatePicker("起存日", selection: startBinding, displayedComponents: .date)
            Picker("期別", selection: termBinding) {
                ForEach(termOptions, id: \.self) { m in
                    Text(Self.termTitle(m)).tag(m)
                }
            }
            if termMonths <= 0 {
                DatePicker("到期日", selection: $customMaturity, in: minMaturity..., displayedComponents: .date)
            }
        } header: {
            WealthFormHeader(title: "期間", icon: "calendar", color: .orange)
        } footer: {
            if let e = periodError {
                Text(e).foregroundStyle(Color.red)
            }
        }
        .disabled(locked)
    }

    private var maturitySection: some View {
        Section {
            Picker("到期怎麼處理", selection: $mode) {
                ForEach(WealthMaturityMode.allCases) { m in
                    Text(m.title).tag(m)
                }
            }
            if showsPayout {
                payoutPicker
            }
        } header: {
            WealthFormHeader(title: "到期", icon: "arrow.triangle.2.circlepath", color: .orange)
        } footer: {
            Text(modeFooter)
        }
        .disabled(locked)
    }

    private var payoutPicker: some View {
        Picker("轉進哪個帳戶", selection: $payout) {
            Text(selfPayoutLabel).tag(nil as UUID?)
            ForEach(payoutChoices) { b in
                Text(b.pickerLabel).tag(b.id as UUID?)
            }
        }
    }

    @ViewBuilder
    private var fromLiveSection: some View {
        // [審查] 舊的定存種類帳戶、自動續存的那一期不出現「從活存轉出」這一項（brief G3-2），只留一句為什麼
        if isLegacy {
            Section {
                Text(Self.legacyNoTransfer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else if record?.previousId != nil {
            Section {
                Text(Self.renewedNoTransfer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                Toggle("從活存轉出", isOn: $fromLive)
            } footer: {
                Text(fromLiveFooter)
            }
            .disabled(locked)
        }
    }

    private var extrasSection: some View {
        Section {
            certificateRow
            Toggle("到期前 7 天提醒", isOn: $remind)
        } header: {
            WealthFormHeader(title: "存單與提醒", icon: "bell.fill", color: .orange)
        } footer: {
            Text(extrasFooter)
        }
        .disabled(locked)
    }

    private var certificateRow: some View {
        HStack {
            Text("存單號碼末 4 碼")
            Spacer()
            TextField("選填", text: $last4)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospaced())
                .frame(maxWidth: 120)
                .onChange(of: last4) { _, v in
                    let d = WealthFormText.digits(v, limit: 4)
                    if d != v { last4 = d }
                }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if let s = previewText {
            Section {
                Text(s)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                WealthFormHeader(title: "預估", icon: "sparkles", color: .orange)
            }
        }
    }

    private var noteSection: some View {
        Section {
            TextField("備註（選填）", text: $note, axis: .vertical)
                .lineLimit(1...3)
        }
        .disabled(locked)
    }

    // MARK: 看／改的最下面三段（都先問）

    @ViewBuilder
    private var actionSections: some View {
        if record != nil {
            if term?.status == .waiting {
                toLiveSection
            }
            if record?.closedDate != nil {
                reopenSection
            } else if term?.status == .active {
                closeSection
            }
            deleteSection
        }
    }

    /// 到期再決定、已經到期：〔到期了，轉活存〕
    private var toLiveSection: some View {
        Section {
            Button {
                ask = .toLive
            } label: {
                Label("到期了，轉活存", systemImage: "arrow.down.to.line")
            }
        } footer: {
            Text(toLiveFooter)
        }
    }

    /// 〔提前解約〕→ 解約日、實拿利息 →〔確定解約〕
    private var closeSection: some View {
        Section {
            if closing {
                DatePicker("解約日", selection: $closeDate, in: closeRange, displayedComponents: .date)
                closeInterestRow
                Button(role: .destructive) {
                    ask = .close
                } label: {
                    Label("確定解約", systemImage: "xmark.circle")
                }
            } else {
                Button {
                    startClosing()
                } label: {
                    Label("提前解約", systemImage: "xmark.circle")
                }
            }
        } header: {
            WealthFormHeader(title: "提前解約", icon: "xmark.circle", color: .red)
        } footer: {
            Text(closeFooter)
        }
    }

    private var closeInterestRow: some View {
        HStack {
            Text("實拿利息（選填）")
            Spacer()
            TextField("0", text: $closeInterestText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }

    /// 已經解約（或排好那天解約）：〔取消解約〕
    private var reopenSection: some View {
        Section {
            LabeledContent("解約日", value: closedDayText)
            Button {
                ask = .reopen
            } label: {
                Label("取消解約", systemImage: "arrow.uturn.left")
            }
        } header: {
            WealthFormHeader(title: "已經解約", icon: "xmark.circle", color: .red)
        } footer: {
            Text(Self.reopenHint)
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                ask = .delete
            } label: {
                Label("刪除這筆定存", systemImage: "trash")
            }
        }
    }

    // MARK: 字

    /// 「台幣」「美金」
    private static func codeName(_ c: String) -> String {
        FinanceRates.isNTD(c) ? "台幣" : c
    }

    /// 期別選單：「6 個月」「12 個月（一年）」「自己選到期日」
    private static func termTitle(_ m: Int) -> String {
        switch m {
        case 0: return "自己選到期日"
        case 12: return "12 個月（一年）"
        case 24: return "24 個月（兩年）"
        case 36: return "36 個月（三年）"
        default: return "\(m) 個月"
        }
    }

    // MARK: 帶入

    private func load() {
        guard !loaded else { return }
        let day = WealthCal.day(Date())
        let facts = lifeStore.wealthFacts(expense: expenseStore, finance: financeStore)
        let rec: WealthTimeDeposit? = editing.flatMap { lifeStore.timeDepositRecord($0) }
        var list: [DepositBank] = facts.banks.filter { !$0.hidden }.map { DepositBank($0) }
        // 帶進來的帳戶、編輯那一筆的帳戶收起來了也放進來（鎖住、不給選）
        let mine: UUID? = rec?.bankId ?? accountId
        if let id = mine, !list.contains(where: { $0.id == id }), let a = facts.account(id), !a.isSecurities {
            list.insert(DepositBank(a), at: 0)
        }
        var outs: [DepositBank] = facts.pickerBanks.map { DepositBank($0) }
        if let r = rec, let p = r.payoutId, p != r.bankId, !outs.contains(where: { $0.id == p }), let a = facts.account(p) {
            outs.append(DepositBank(a))
        }
        today = day
        banks = list
        payoutBanks = outs
        record = rec
        term = facts.timeDeposit(editing)
        closeDate = day
        lockAccount = rec != nil || (mine.map { id in list.contains(where: { $0.id == id }) } ?? false)
        loaded = true
        if let r = rec {
            fill(from: r)
            let legacy: Bool = list.first(where: { $0.id == r.bankId })?.legacy ?? false
            let holding: Set<UUID> = Set(facts.timeDeposits.map { $0.id })
            countChain(r, through: day, legacy: legacy, holding: holding)
        } else {
            startNew(day)
        }
    }

    /// 看／改：欄位帶帳本那一筆
    private func fill(from r: WealthTimeDeposit) {
        pickedAccount = r.bankId
        code = r.code
        principalText = WealthFormText.editable(r.principal)
        rateText = r.rate.map { WealthFormText.rateText($0) } ?? ""
        start = WealthCal.day(r.start)
        if let m = r.months, m > 0 {
            termMonths = m
            if !Self.termChoices.contains(m) { oddTerm = m }
            customMaturity = WealthCal.addMonths(m, to: WealthCal.day(r.start))
        } else {
            termMonths = 0
            customMaturity = r.maturity.map { WealthCal.day($0) } ?? WealthCal.addMonths(12, to: WealthCal.day(r.start))
        }
        mode = r.mode
        payout = r.payoutId == r.bankId ? nil : r.payoutId
        fromLive = r.fromLive == true
        last4 = r.certificateLast4 ?? ""
        remind = r.remind != false
        note = r.note ?? ""
    }

    /// 新增：帶了帳戶（或只有一個帳戶）先選好；起存日今天、一年、本息續存、從活存轉出、提醒
    private func startNew(_ day: Date) {
        var first: UUID? = nil
        if let a = accountId, banks.contains(where: { $0.id == a }) {
            first = a
        } else if banks.count == 1 {
            first = banks.first?.id
        }
        pickedAccount = first
        code = banks.first(where: { $0.id == first })?.codes.first ?? "NT$"
        start = day
        termMonths = 12
        customMaturity = WealthCal.addMonths(12, to: day)
        mode = .renewAll
        fromLive = true
        remind = true
        prefillLegacy(first)
    }

    /// 舊的「定存」種類帳戶、還沒有任何一期（要確認〔補資料〕）：本金帶存摺上、起存日帶最早一筆紀錄（沒有用開戶日）、期別 12
    private func prefillLegacy(_ id: UUID?) {
        guard isNew, principalText.isEmpty, let id, let b = banks.first(where: { $0.id == id }), b.legacy,
              !lifeStore.wealthDeposits.all.contains(where: { $0.bankId == id }) else { return }
        let c: String = b.codes.first(where: { (b.balances[$0] ?? 0) > 0.5 }) ?? (b.codes.first ?? "NT$")
        code = c
        let v: Double = b.balances[c] ?? 0
        if v > 0.5 { principalText = WealthFormText.editable(v) }
        let earliest: Date? = lifeStore.milestones.first(where: { $0.id == id })?.bankDeposits?.map(\.date).min()
        let s = Self.currentTermStart(from: earliest ?? b.openedDate, today: today)
        start = s
        termMonths = 12
        customMaturity = WealthCal.addMonths(12, to: s)
        prefilledLegacy = true
    }

    /// [審查] 舊的定存帳戶〔補資料〕的起存日：最早一筆紀錄（沒有用開戶日）一年一年往後推到「現在這一期」（起存日 ≤ 今天 < 到期日）。
    /// 直接用好幾年前的那天、又選本息續存的話，今天以前到期的那幾期利息會再記進存摺（舊的定存種類帳戶：利息記進這個帳戶），
    /// 存完存款合計就變了（brief §9-10「存完存款合計不變」）；存摺上的數字本來就是現在這一期的本金
    private static func currentTermStart(from first: Date, today: Date) -> Date {
        let base = WealthCal.day(first)
        let t = WealthCal.day(today)
        var k = 0
        while k < WealthDepositChain.maxRenewals, WealthCal.addMonths(12 * (k + 1), to: base) <= t {
            k += 1
        }
        return WealthCal.addMonths(12 * k, to: base)
    }

    /// 新增時換帳戶：幣別換成新帳戶有的；轉進的帳戶是它自己就改回「這個帳戶」；舊的定存帳戶帶存摺上
    private func accountChanged(to id: UUID?) {
        guard isNew else { return }
        let list: [String] = banks.first(where: { $0.id == id })?.codes ?? ["NT$"]
        if !list.contains(code) { code = list.first ?? "NT$" }
        if payout == id { payout = nil }
        if prefilledLegacy {
            // 換掉帶進來的那個舊定存帳戶：帶進來的本金、起存日拿掉
            principalText = ""
            start = today
            customMaturity = WealthCal.addMonths(12, to: today)
            prefilledLegacy = false
        }
        prefillLegacy(id)
    }

    /// 同一串有幾期、起存時從活存轉出多少（刪除時問；舊的定存種類帳戶不轉出）。
    /// holding：一套數字裡還在的那幾期（沒開始、存著、到期待決定；WealthFacts.timeDeposits 的 id）
    private func countChain(_ r: WealthTimeDeposit, through day: Date, legacy: Bool, holding: Set<UUID>) {
        let all: [WealthTimeDeposit] = WealthDepositChain.terms(lifeStore.wealthDeposits.all, through: day).map { $0.deposit }
        let ids = WealthDepositChain.chainIds(containing: r.id, in: all)
        let chain: [WealthTimeDeposit] = all.filter { ids.contains($0.id) }
        chainCount = Swift.max(1, chain.count)
        // [v25.566 裁定] 整串都結束了：錢已經回到活存，刪除只有一顆〔刪除〕（見 chainEnded）
        let ended: Bool = !chain.contains(where: { holding.contains($0.id) })
        chainEnded = ended
        guard !legacy, !ended else {
            movedText = nil
            return
        }
        let moved: [WealthTimeDeposit] = chain.filter { $0.fromLive == true }
        guard let first = moved.first else {
            movedText = nil
            return
        }
        let total: Double = moved.reduce(0.0) { $0 + $1.principal }
        movedText = WealthFormat.plain(total, code: first.code)
    }

    private func startClosing() {
        let r = closeRange
        closeDate = Swift.min(Swift.max(today, r.lowerBound), r.upperBound)
        withAnimation(.easeInOut(duration: 0.2)) { closing = true }
    }

    // MARK: 存檔、問過之後（先 dismiss、下一個 runloop 才寫 store）

    private func save() {
        guard !isSaving, canSave else { return }
        isSaving = true
        let d = draft
        let life = lifeStore
        dismiss()
        DispatchQueue.main.async {
            life.saveTimeDeposit(d)
        }
    }

    private func perform(_ a: WealthDepositAsk, keepTransfer: Bool) {
        guard !isSaving, let id = record?.id else { return }
        isSaving = true
        let life = lifeStore
        let day = closeDate
        let got = closeInterestValue
        dismiss()
        DispatchQueue.main.async {
            switch a {
            case .toLive:
                life.setTimeDepositOnMaturity(id, mode: .toLive)
            case .close:
                life.closeTimeDeposit(id, on: day, interest: got)
            case .reopen:
                life.reopenTimeDeposit(id)
            case .delete:
                life.deleteTimeDeposit(id, keepTransfer: keepTransfer)
            }
        }
    }
}

// MARK: - [v25.566] 定存表單要先問的四件事（一個 enum 管；確認框拆成 ViewModifier，坑 #7）

enum WealthDepositAsk: String, Identifiable {
    /// 到期再決定、已經到期：〔到期了，轉活存〕
    case toLive
    /// 〔確定解約〕
    case close
    /// 〔取消解約〕
    case reopen
    /// 〔刪除這筆定存〕（整串一起刪；有從活存轉出的再分兩顆）
    case delete

    var id: String { rawValue }
}

/// 確認框：轉活存〔轉活存〕；解約〔解約〕；取消解約〔取消解約〕；刪除〔一起拿掉（錢回到台灣銀行）〕〔留著那一筆轉出〕或〔刪除〕。
/// onChoose 的第二個參數＝留著那一筆轉出（LifeStore.deleteTimeDeposit keepTransfer）
struct WealthDepositAskDialog: ViewModifier {
    @Binding var ask: WealthDepositAsk?
    let title: String
    let message: String
    /// 「一起拿掉（錢回到台灣銀行）」
    let removeTitle: String
    /// 刪除時有「從活存轉出」那一筆：多一顆〔留著那一筆轉出〕
    let offersKeep: Bool
    let onChoose: (WealthDepositAsk, Bool) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            title,
            isPresented: Binding(get: { ask != nil }, set: { if !$0 { ask = nil } }),
            titleVisibility: .visible,
            presenting: ask
        ) { a in
            buttons(a)
        } message: { _ in
            Text(message)
        }
    }

    @ViewBuilder
    private func buttons(_ a: WealthDepositAsk) -> some View {
        switch a {
        case .toLive:
            Button("轉活存") { onChoose(a, false) }
            Button("取消", role: .cancel) {}
        case .close:
            Button("解約", role: .destructive) { onChoose(a, false) }
            Button("取消", role: .cancel) {}
        case .reopen:
            Button("取消解約") { onChoose(a, false) }
            Button("先不要", role: .cancel) {}
        case .delete:
            if offersKeep {
                Button(removeTitle, role: .destructive) { onChoose(a, false) }
                Button("留著那一筆轉出", role: .destructive) { onChoose(a, true) }
            } else {
                Button("刪除", role: .destructive) { onChoose(a, false) }
            }
            Button("取消", role: .cancel) {}
        }
    }
}
