import SwiftUI

// MARK: - 財富頁的項目卡（v25.564，財富 v3；wealth/judge.md §3.7–3.11）
//
// 照 MoneyItem.vehicle（FinanceItems.swift）：extension MoneyItem { static func wealthCard／wealthBank／wealthBroker }（保單 v3 是白卡一列，不是項目卡），
// 一筆要寫什麼字全在工廠函式；信用卡的卡面走 MoneyItem.cardFace（WealthCardFacePanel，G4 畫），銀行、證券戶走 MoneyArtTheme 71–76。
//
// 分工：G1 實作。主控只開檔。
//
// [v25.564] G1：
// • MoneyItem.wealthCard(_:masked:now:dark:)：名稱「國泰世華 CUBE」、金額 要繳／還沒出帳／NT$0、第二行「10/27 截止・8 天・自己繳」
//   （色點＝卡面色；逾期、3 天內 warn）、膠囊「還沒出帳 6,200」或「9 月帳單已扣 ✓」＋「還能刷 27.5萬」、使用率條（四段色，不用紅綠）、
//   卡面＝一張小卡片（只有末四碼；遮住也遮）。主題照 72 但 tint 換成卡面色、進度條換成使用率那一段的顏色（MoneyItemCard 不用改）。
// • MoneyItem.wealthBank(_:facts:rates:masked:now:)：存摺上寫到元；「活存・台新 ••7890」；接下來兩件膠囊；外幣「匯率 32.0」；
//   負的「可能漏記了」；主題 71／73／74；不放銀行商標、不放帳號（只有 ••末 4 碼）。
// • MoneyItem.wealthBroker(_:facts:masked:)：市值讀股票頁；「證券戶・交割 薪轉（台新）」；膠囊交割、未實現（紅漲綠跌）。
// • 分區（④ 信用卡、⑤ 銀行帳戶、⑥ 證券戶、⑦ 保單、⑧ 收起來的）：點＝卡片頁；長按 contextMenu、VoiceOver accessibilityActions 同一組；
//   不做左滑。要開表單、要問的都交回財富頁（WealthPageActions），這裡不寫 store。

// MARK: - 財富頁的彈出頁（一個 enum、一個 .sheet(item:)）

/// 財富頁的彈出頁（LifeFinanceView 一個 .sheet(item:) { … .appStores() }）。id 帶帳戶的 UUID／字串
enum WealthSheet: Identifiable {
    /// 卡片頁（捲到哪一區）
    case card(UUID, WealthCardAnchor?)
    /// 新增（nil）／編輯財富帳戶
    case editor(WealthAccountKind, LifeMilestone?)
    /// 記一筆（存款／提款／利息／手續費）
    case record(UUID, WealthRecordKind)
    /// 轉帳（從這個帳戶轉出）
    case transfer(UUID)
    /// 對存摺（帳戶、幣別）
    case anchor(UUID, String)
    /// 標成已繳（最早沒繳的那一期）
    case paid(UUID)
    /// 刷這張卡記一筆（記帳表單，預先選好這張卡）
    case addExpense(UUID)
    /// 排序與收起來
    case order
    /// 「這頁的數字怎麼算」「iCloud 與家人共享說明」
    case info(WealthPageInfoTopic)
    /// 接下來 30 天全部
    case upcomingAll

    var id: String {
        switch self {
        case .card(let id, let anchor): return "card-\(id.uuidString)-\(anchor?.rawValue ?? "")"
        case .editor(let kind, let m): return "editor-\(kind.rawValue)-\(m?.id.uuidString ?? "new")"
        case .record(let id, let kind): return "record-\(id.uuidString)-\(kind.rawValue)"
        case .transfer(let id): return "transfer-\(id.uuidString)"
        case .anchor(let id, let code): return "anchor-\(id.uuidString)-\(code)"
        case .paid(let id): return "paid-\(id.uuidString)"
        case .addExpense(let id): return "expense-\(id.uuidString)"
        case .order: return "order"
        case .info(let topic): return "info-\(topic.rawValue)"
        case .upcomingAll: return "upcoming"
        }
    }

    /// 要訂閱（待決定 10）：新增、編輯、記一筆、轉帳、對存摺、刷這張卡記一筆。
    /// 不擋：看卡片頁、標成已繳、排序與收起來、說明、接下來全部
    var needsPremium: Bool {
        switch self {
        case .editor, .record, .transfer, .anchor, .addExpense: return true
        case .card, .paid, .order, .info, .upcomingAll: return false
        }
    }
}

/// ⋯ 的兩張說明
enum WealthPageInfoTopic: String {
    case howItWorks, iCloud

    var title: String {
        switch self {
        case .howItWorks: return "這頁的數字怎麼算"
        case .iCloud: return "iCloud 與家人共享說明"
        }
    }

    var paragraphs: [String] {
        switch self {
        case .howItWorks: return WealthPageText.howItWorks
        case .iCloud: return WealthPageText.iCloudNote
        }
    }
}

/// 長按「停用」「收起來」要先問（財富頁一個 confirmationDialog）
enum WealthPageConfirm: Identifiable {
    /// 停用一張卡：卡的 id、名字、還在刷它的定期扣款幾筆
    case disableCard(UUID, String, Int)
    /// 收起來一個帳戶（銀行：銷戶）
    case hideAccount(UUID, String)

    var id: String {
        switch self {
        case .disableCard(let id, _, _): return "disable-\(id.uuidString)"
        case .hideAccount(let id, _): return "hide-\(id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .disableCard(_, let name, _): return "停用「\(name)」？"
        case .hideAccount(_, let name): return "收起來「\(name)」？"
        }
    }

    var message: String {
        switch self {
        case .disableCard(_, _, let n):
            let base = "停用後不會出現在記帳的卡片選單，歷史帳單照算。"
            return n > 0 ? base + "還有 \(n) 筆定期扣款刷它，要先改嗎？" : base
        case .hideAccount:
            return "收起來：不算進存款合計、不出現在記帳選單；歷史照算，隨時可以在「⋯ › 排序與收起來」打開。"
        }
    }
}

/// 項目卡、分區要做的事（全部交回財富頁：開表單、付費擋、問確認、寫 store 都在那裡）
struct WealthPageActions {
    /// 打開一張彈出頁（要訂閱的那幾種財富頁自己擋）
    var open: (WealthSheet) -> Void = { _ in }
    /// 編輯：帳戶的 id、表單類型（財富頁拿 store 裡最新的那一筆里程碑）
    var edit: (UUID, WealthAccountKind) -> Void = { _, _ in }
    /// 停用、收起來先問
    var confirm: (WealthPageConfirm) -> Void = { _ in }
    /// 收起來的：重新啟用卡（true）／不收起來帳戶（false）
    var restore: (UUID, Bool) -> Void = { _, _ in }
}

// MARK: - 工廠：一張卡、一個帳戶、一個證券戶

/// 卡面色的代表色（同 WealthCardPalette 的 bottoms；那張表是 private，項目卡的色點、底色要 UInt32 才能組主題）
private let wealthFaceTints: [UInt32] = [0xE0453A, 0x1F7A9C, 0x1B8F63, 0x6B4BE0, 0x1C1C24, 0xD63F72]
/// 使用率四段色：很寬鬆／正常／偏高／快刷滿了（judge §3.16；不用紅綠）
private let wealthUsageLight: [UInt32] = [0x6B7FA3, 0xB98500, 0xD9731A, 0xB34A00]
private let wealthUsageDark: [UInt32] = [0x9FB0D0, 0xFFD166, 0xFF9F4D, 0xFF7A33]

extension MoneyItem {
    /// 信用卡的主題：照 72（Trends／STATEMENTS），色點與卡底的淡色換成卡面色（warn 時換注意色）、進度條換成使用率那一段的顏色
    static func wealthCardTheme(face: Int, tier: Int, warn: Bool, dark: Bool) -> MoneyArtTheme {
        let base = MoneyArtTheme.wealthCardTrends
        let t = Swift.min(Swift.max(tier, 0), 3)
        let bar: UInt32 = dark ? wealthUsageDark[t] : wealthUsageLight[t]
        let f = Swift.min(Swift.max(face, 0), 5)
        let tint: UInt32 = warn ? 0xA65300 : wealthFaceTints[f]
        return MoneyArtTheme(id: base.id, top: bar, bottom: bar, tint: tint, hero: base.hero, accent: base.accent,
                             pattern: base.pattern, word: base.word, caps: base.caps)
    }

    /// ④ 一張信用卡（judge §3.7）
    static func wealthCard(_ c: WealthFacts.Card, masked: Bool, now: Date, dark: Bool) -> MoneyItem {
        let today = WealthCal.day(now)
        let meta = wealthCardMeta(c, today: today)
        let tier = c.usage.map { WealthPageText.tier($0) } ?? 0
        var item = MoneyItem(id: c.id, theme: wealthCardTheme(face: c.faceColor, tier: tier, warn: meta.warn, dark: dark),
                             seed: seed(c.id), title: c.fullName, amount: "", category: meta.text)
        // 金額：有要繳寫要繳；沒有寫還沒出帳；都 0 寫 NT$0＋膠囊「這期還沒刷」
        var chips: [MoneyItemChip] = []
        if c.due > 0.5 {
            item.amount = WealthFormat.ntd(c.due)
            item.unit = "要繳"
            if c.unbilled > 0.5 {
                let unbilledText: String = masked ? WealthPageText.dots
                                                  : WealthFormat.grouped(c.unbilled.rounded(), decimals: 0)
                chips.append(MoneyItemChip(icon: "hourglass", text: "還沒出帳 \(unbilledText)"))
            }
        } else if c.unbilled > 0.5 {
            item.amount = WealthFormat.ntd(c.unbilled)
            item.unit = "還沒出帳"
            if let paid = wealthPaidChip(c, today: today) { chips.append(paid) }
        } else {
            item.amount = "NT$0"
            chips.append(MoneyItemChip(icon: "moon.zzz.fill", text: "這期還沒刷"))
        }
        if let a = c.available {
            let availableText: String = masked ? WealthPageText.dots : WealthPageText.wan(a)
            chips.append(MoneyItemChip(icon: "gauge.with.dots.needle.33percent", text: "還能刷 \(availableText)"))
        }
        item.chips = Array(chips.prefix(2))
        if masked { item.amount = WealthFormat.masked }

        // 使用率條（沒填額度不畫）
        if let u = c.usage, let limit = c.limit {
            let limitText = masked ? WealthPageText.dots : wealthLimitText(limit)
            item.progress = MoneyItemProgress(fraction: Swift.min(1, Swift.max(0, u)),
                                              leading: WealthFormat.percent(u) + "・" + WealthPageText.tierName(u),
                                              trailing: "額度 " + limitText)
        }
        item.cardFace = WealthCardFace(color: c.faceColor, last4: masked ? "••••" : (c.last4 ?? "••••"),
                                       disabled: c.isDisabled)
        item.badge = meta.badge
        item.scriptWord = "Credit"
        item.scriptCaps = wealthCardCaps(c.name)
        item.accessibilityText = wealthSpoken(title: c.fullName, amount: item.amount, unit: item.unit,
                                              category: meta.text, chips: item.chips, progress: item.progress,
                                              masked: masked)
        return item
    }

    /// 卡的第二行、左上小膠囊、要不要 warn
    private static func wealthCardMeta(_ c: WealthFacts.Card, today: Date) -> (text: String, badge: String?, warn: Bool) {
        let md = WealthPageText.md
        if c.isDisabled {
            let since = c.closedDate.map { md($0) + " 停用" } ?? "已停用"
            return (text: since, badge: nil, warn: false)
        }
        let mode = c.payMode == .askEachTime ? "每次問我" : "自己繳"
        let verb = c.payMode == .autoMin ? "扣最低" : "扣"
        if let s = c.dueStatement {
            if s.status == .overdue {
                return (text: md(s.due) + " 截止・還沒確認", badge: md(s.due) + " 截止", warn: true)
            }
            let n = WealthCal.days(from: today, to: s.due)
            if c.payMode.isAuto {
                let from = c.payerName.map { "從\($0)\(verb)" } ?? "還沒選從哪扣"
                if n <= 0 { return (text: "今天" + from, badge: "今天扣款", warn: true) }
                return (text: "\(md(s.due)) \(from)・\(n) 天", badge: "\(md(s.due)) 扣款", warn: n <= 3)
            }
            if n <= 0 { return (text: "今天截止・" + mode, badge: "今天截止", warn: true) }
            return (text: "\(md(s.due)) 截止・\(n) 天・\(mode)", badge: "\(md(s.due)) 截止", warn: n <= 3)
        }
        if c.payMode.isAuto {
            let from = c.payerName.map { md(c.nextDue) + " 從\($0)\(verb)" } ?? "還沒選從哪扣"
            return (text: "\(md(c.nextClose)) 結帳・\(from)", badge: "\(md(c.nextClose)) 結帳", warn: false)
        }
        return (text: "\(md(c.nextClose)) 結帳・\(mode)", badge: "\(md(c.nextClose)) 結帳", warn: false)
    }

    /// 「9 月帳單已扣 ✓」（自動扣）／「已繳 ✓」（自己繳）／「當作已繳」：最近一期 35 天內
    private static func wealthPaidChip(_ c: WealthFacts.Card, today: Date) -> MoneyItemChip? {
        guard let p = c.lastPaid else { return nil }
        let d = WealthCal.days(from: p.paidOn ?? p.due, to: today)
        guard d >= 0 && d <= 35 else { return nil }
        if p.status == .assumedPaid {
            return MoneyItemChip(icon: "questionmark.circle", text: p.label + "當作已繳")
        }
        let word = c.payMode.isAuto && !p.isExplicitPaid ? "已扣 ✓" : "已繳 ✓"
        return MoneyItemChip(icon: "checkmark.circle.fill", text: p.label + word, tone: .good)
    }

    /// 「額度 30 萬」「額度 6.8 萬」；一萬以下寫到元
    private static func wealthLimitText(_ limit: Double) -> String {
        if limit >= 10_000 {
            let w = (limit / 10_000 * 10).rounded() / 10
            let s = w == w.rounded() ? String(format: "%.0f", w) : String(format: "%.1f", w)
            return s + " 萬"
        }
        return WealthFormat.grouped(limit.rounded(), decimals: 0)
    }

    /// 卡面左下的大寫字：卡名的英數字（「CUBE」「GOGO」）；沒有英數字寫「CARD」
    private static func wealthCardCaps(_ name: String) -> String {
        let letters = name.uppercased().filter { ch in
            ch.isASCII && (ch.isLetter || ch.isNumber)
        }
        return letters.isEmpty ? "CARD" : String(letters.prefix(10))
    }

    /// ⑤ 一個銀行帳戶（judge §3.8）
    static func wealthBank(_ a: WealthFacts.Account, facts: WealthFacts, rates: FinanceRates, masked: Bool,
                           now: Date) -> MoneyItem {
        let foreign = WealthPageText.foreignCode(a)
        let theme: MoneyArtTheme = a.isFixedDeposit ? .wealthDeposit : (foreign != nil ? .wealthForeign : .wealthLive)
        let bank = WealthPageText.bankShort(a.bankName)
        var category: String
        if a.isFixedDeposit {
            category = "定存・" + bank
        } else if foreign != nil {
            category = "外幣・" + bank
            if a.hasUnknownRate {
                category += "・沒有匯率"
            } else if !masked {
                category += "・約 " + WealthFormat.ntd(a.ntdTotal)
            }
        } else {
            category = "活存・" + bank + (a.last4.map { " ••" + $0 } ?? "")
        }
        if a.hidden {
            let since: String = a.closedDate.map { "・\(WealthPageText.md($0))" } ?? ""
            category = "收起來\(since)・\(bank)"
        }
        var item = MoneyItem(id: a.id, theme: theme, seed: seed(a.id), title: a.name,
                             amount: masked ? WealthFormat.masked : a.balanceText, category: category)
        if a.ntdTotal < -0.5 { item.amountTone = .bad }
        // 好幾個幣別：第二行「NT$13.2萬＋美金 3,200.00」
        if a.singleCode == nil, !masked {
            item.detail = wealthMultiText(a)
        }
        item.chips = wealthBankChips(a, foreign: foreign, facts: facts, rates: rates, masked: masked)
        item.badge = wealthBankBadge(a)
        item.monogram = String(a.name.prefix(2))
        item.scriptCaps = wealthPurposeCaps(a.purpose)
        item.dimmed = a.hidden
        item.accessibilityText = wealthSpoken(title: a.name, amount: item.amount, unit: nil, category: category,
                                              chips: item.chips, progress: nil, masked: masked)
        return item
    }

    /// 「NT$13.2萬＋美金 3,200.00」（有數字的幣別，台幣在前）
    private static func wealthMultiText(_ a: WealthFacts.Account) -> String {
        var parts: [String] = []
        for code in a.currencies {
            let v = a.balance(code)
            guard Swift.abs(v) > 0.004 else { continue }
            parts.append(FinanceRates.isNTD(code) ? v.ntdWanString : WealthFormat.money(v, code: code))
        }
        return parts.joined(separator: "＋")
    }

    /// 膠囊：負的「可能漏記了」、外幣「匯率 32.0」、接下來兩件（出去的在前；一列放不下少放）
    private static func wealthBankChips(_ a: WealthFacts.Account, foreign: String?, facts: WealthFacts,
                                        rates: FinanceRates, masked: Bool) -> [MoneyItemChip] {
        var chips: [MoneyItemChip] = []
        if a.ntdTotal < -0.5 {
            chips.append(MoneyItemChip(icon: "exclamationmark.triangle.fill", text: "可能漏記了", tone: .bad))
        }
        if let code = foreign, !FinanceRates.isNTD(code) {
            if let r = rates.known(code) {
                chips.append(MoneyItemChip(icon: "dollarsign.arrow.circlepath", text: "匯率 " + WealthFormat.rate(r)))
            } else {
                chips.append(MoneyItemChip(icon: "exclamationmark.circle", text: "沒有匯率", tone: .warn))
            }
        }
        let outs = a.next30.filter { $0.isOutflow }
        let ins = a.next30.filter { !$0.isOutflow }
        for row in Array((outs + ins).prefix(2)) {
            chips.append(MoneyItemChip(icon: "calendar", text: wealthUpcomingChip(row, facts: facts, masked: masked)))
        }
        return chips
    }

    /// 「10/21 交割 52,340」「11/10 扣 @GoGo 約 2.3萬」（自動扣的卡費）「10/27 CUBE 18,600」「11/5 月薪 +80,000」
    private static func wealthUpcomingChip(_ row: WealthLedgerRow, facts: WealthFacts, masked: Bool) -> String {
        let head = WealthPageText.md(row.date) + " " + wealthUpcomingChipName(row, facts: facts)
        if masked { return head + " " + WealthPageText.dots }
        let sign = row.isOutflow ? "" : "+"
        if row.isEstimate, FinanceRates.isNTD(row.code) {
            return "\(head) 約 \(WealthPageText.wan(row.amount))"
        }
        return "\(head) \(sign)\(WealthFormat.plain(row.amount, code: row.code))"
    }

    /// 膠囊裡的短名：自動扣的卡費寫「扣 @GoGo」（卡名照寫，judge §3.8 那張表）；其他照 shortName（交割、CUBE、月薪）
    private static func wealthUpcomingChipName(_ row: WealthLedgerRow, facts: WealthFacts) -> String {
        if row.kind == .cardBill, let c = facts.card(row.cardId), c.payMode.isAuto {
            return "扣 \(c.name)"
        }
        return WealthPageText.shortName(row, facts: facts)
    }

    /// 卡面左上：「NT$」「US$」「美金」前 3 字；定存「定存」；好幾個幣別「多幣別」
    private static func wealthBankBadge(_ a: WealthFacts.Account) -> String {
        if a.isFixedDeposit { return "定存" }
        guard let code = a.singleCode else { return "多幣別" }
        if FinanceRates.isNTD(code) { return "NT$" }
        if FinanceRates.isUSD(code) { return "US$" }
        return String(code.prefix(3))
    }

    /// 卡面左下的小字照用途：薪轉 PAYROLL、扣款 AUTOPAY、存錢 SAVINGS、外幣 FOREIGN、零用 POCKET；沒填用主題的
    private static func wealthPurposeCaps(_ purpose: String?) -> String? {
        guard let p = purpose?.trimmingCharacters(in: .whitespaces), !p.isEmpty else { return nil }
        if p.contains("薪") { return "PAYROLL" }
        if p.contains("扣") { return "AUTOPAY" }
        if p.contains("存") { return "SAVINGS" }
        if p.contains("外") { return "FOREIGN" }
        if p.contains("零") { return "POCKET" }
        return nil
    }

    /// ⑥ 一個證券戶（券商名片；judge §3.9：市值、持股讀股票頁，不算進存款合計）
    static func wealthBroker(_ b: WealthFacts.Broker, facts: WealthFacts, masked: Bool) -> MoneyItem {
        let held = b.holdingIds.count
        var item = MoneyItem(id: b.id, theme: .wealthBroker, seed: seed(b.id), title: b.name, amount: "—",
                             category: "證券戶")
        item.monogram = String(b.name.prefix(2))
        let hidden = facts.account(b.id)?.hidden == true
        item.dimmed = hidden
        if held == 0 {
            item.category = "證券戶・還沒有持股"
            item.chips = [MoneyItemChip(icon: "info.circle", text: "股票表單選這個證券戶，持股就會出現在這裡")]
        } else {
            item.amount = masked ? WealthFormat.masked : b.marketValue.ntdWanString
            item.unit = "市值"
            item.badge = "\(held) 檔"
            item.category = "證券戶・" + wealthSettlementText(b, facts: facts)
            var chips: [MoneyItemChip] = []
            if let d = b.nextSettlementDate, Swift.abs(b.nextSettlementAmount) > 0.5 {
                let word = b.nextSettlementAmount > 0 ? " 交割 " : " 入帳 "
                let amount = masked ? WealthPageText.dots
                                    : WealthFormat.grouped(Swift.abs(b.nextSettlementAmount).rounded(), decimals: 0)
                chips.append(MoneyItemChip(icon: "calendar", text: WealthPageText.md(d) + word + amount))
            }
            if let r = b.unrealizedRatio {
                let sign = r >= 0 ? "+" : "-"
                chips.append(MoneyItemChip(icon: r >= 0 ? "arrow.up.right" : "arrow.down.right",
                                           text: "未實現 " + sign + String(format: "%.1f%%", Swift.abs(r) * 100),
                                           tone: MoneyTone.change(r)))
            }
            item.chips = chips
        }
        item.accessibilityText = wealthSpoken(title: b.name, amount: item.amount, unit: item.unit,
                                              category: item.category, chips: item.chips, progress: nil, masked: masked)
        return item
    }

    /// 「交割 薪轉（台新）」；沒有交割銀行「還沒選交割銀行」
    private static func wealthSettlementText(_ b: WealthFacts.Broker, facts: WealthFacts) -> String {
        guard b.settlementBankId != nil || b.settlementName != nil else { return "還沒選交割銀行" }
        if let acc = facts.account(b.settlementBankId) {
            if acc.nickname != nil { return "交割 \(acc.name)（\(WealthPageText.bankShort(acc.bankName))）" }
            return "交割 " + acc.name
        }
        return "交割 " + (b.settlementName ?? "")
    }

    /// VoiceOver 一整句（遮住時金額念「金額已遮住」，不念一串點）
    private static func wealthSpoken(title: String, amount: String, unit: String?, category: String,
                                     chips: [MoneyItemChip], progress: MoneyItemProgress?, masked: Bool) -> String {
        var parts: [String] = [title]
        if masked {
            parts.append("金額已遮住")
        } else if let u = unit {
            parts.append("\(amount) \(u)")
        } else {
            parts.append(amount)
        }
        parts.append(category)
        for c in chips {
            parts.append(c.text.replacingOccurrences(of: WealthPageText.dots, with: "金額已遮住"))
        }
        if let p = progress {
            parts.append("額度用了 " + p.leading)
        }
        return parts.joined(separator: "，")
    }
}

// MARK: - ④ 信用卡

/// ④ 信用卡：「信用卡 2」右「還沒扣 NT$4.8萬」＋一張卡一張項目卡
struct WealthPageCardsSection: View {
    let header: WealthPageGroupHeader
    let rows: [WealthPageCardRow]
    let actions: WealthPageActions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MoneyGroupHeader(theme: .wealthCardTrends, title: "信用卡", count: header.count, total: header.total,
                             unit: "張")
            VStack(spacing: 10) {
                ForEach(rows) { r in
                    card(r)
                }
            }
        }
    }

    /// 點：信用卡頁；長按：標成已繳（有要繳才有）、記一筆、編輯、停用
    private func card(_ r: WealthPageCardRow) -> some View {
        Button {
            actions.open(.card(r.id, nil))
        } label: {
            MoneyItemCard(item: r.item)
        }
        .buttonStyle(MoneyPressStyle())
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityHint("點兩下打開這張卡；長按有更多動作")
        .contextMenu {
            menu(r)
        }
        .accessibilityActions {
            menu(r)
        }
    }

    @ViewBuilder
    private func menu(_ r: WealthPageCardRow) -> some View {
        if r.canMarkPaid {
            Button {
                actions.open(.paid(r.id))
            } label: {
                Label("標成已繳", systemImage: "checkmark.circle")
            }
        }
        Button {
            actions.open(.addExpense(r.id))
        } label: {
            Label("記一筆", systemImage: "square.and.pencil")
        }
        Button {
            actions.edit(r.id, .card)
        } label: {
            Label("編輯", systemImage: "pencil")
        }
        Button {
            actions.confirm(.disableCard(r.id, r.name, r.recurringCount))
        } label: {
            Label("停用", systemImage: "nosign")
        }
    }
}

// MARK: - ⑤ 銀行帳戶

/// ⑤ 銀行帳戶：「銀行帳戶 4」右「存摺合計 NT$81.7萬」＋一個帳戶一張項目卡；沒有銀行帳戶換一張提示卡
struct WealthPageBanksSection: View {
    let header: WealthPageGroupHeader?
    let rows: [WealthPageBankRow]
    /// 沒有銀行帳戶（只有卡）：換一張提示卡
    let showPrompt: Bool
    let actions: WealthPageActions

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let h = header, !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                MoneyGroupHeader(theme: .wealthLive, title: "銀行帳戶", count: h.count, total: h.total, unit: "個")
                VStack(spacing: 10) {
                    ForEach(rows) { r in
                        card(r)
                    }
                }
            }
        } else if showPrompt {
            VStack(alignment: .leading, spacing: 10) {
                MoneySectionHeader(title: "銀行帳戶")
                prompt
            }
        }
    }

    /// 「記下你的薪轉帳戶，記帳扣款、月薪入帳就接起來 ›」（要訂閱：財富頁擋）
    private var prompt: some View {
        let pal = TripBoardPalette(scheme)
        return Button {
            actions.open(.editor(.bank, nil))
        } label: {
            HStack(spacing: 12) {
                TripBoardIconBadge(icon: "building.columns.fill", colors: pal.badge(.blue), diameter: 30, dark: pal.dark)
                Text("記下你的薪轉帳戶，記帳扣款、月薪入帳就接起來 ›")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(pal.hint)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .modifier(FinanceCardChrome())
            .contentShape(Rectangle())
        }
        .buttonStyle(MoneyPressStyle())
    }

    /// 點：銀行頁；長按：記一筆（存款／提款／利息／手續費）、對存摺、轉帳、編輯、收起來
    private func card(_ r: WealthPageBankRow) -> some View {
        Button {
            actions.open(.card(r.id, nil))
        } label: {
            MoneyItemCard(item: r.item)
        }
        .buttonStyle(MoneyPressStyle())
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityHint("點兩下打開這個帳戶；長按有更多動作")
        .contextMenu {
            menu(r)
        }
        .accessibilityActions {
            spokenActions(r)
        }
    }

    @ViewBuilder
    private func menu(_ r: WealthPageBankRow) -> some View {
        Menu {
            ForEach(WealthRecordKind.allCases) { k in
                Button(k.title) {
                    actions.open(.record(r.id, k))
                }
            }
        } label: {
            Label("記一筆", systemImage: "square.and.pencil")
        }
        anchorMenu(r)
        Button {
            actions.open(.transfer(r.id))
        } label: {
            Label("轉帳", systemImage: "arrow.left.arrow.right")
        }
        Button {
            actions.edit(r.id, .bank)
        } label: {
            Label("編輯", systemImage: "pencil")
        }
        Button {
            actions.confirm(.hideAccount(r.id, r.name))
        } label: {
            Label("收起來", systemImage: "archivebox")
        }
    }

    /// 對存摺：一個幣別直接開；好幾個幣別選一個
    @ViewBuilder
    private func anchorMenu(_ r: WealthPageBankRow) -> some View {
        if r.codes.count > 1 {
            Menu {
                ForEach(r.codes, id: \.self) { code in
                    Button(code) {
                        actions.open(.anchor(r.id, code))
                    }
                }
            } label: {
                Label("對存摺", systemImage: "checkmark.seal")
            }
        } else {
            Button {
                actions.open(.anchor(r.id, r.codes.first ?? "NT$"))
            } label: {
                Label("對存摺", systemImage: "checkmark.seal")
            }
        }
    }

    /// VoiceOver 的動作（子選單攤平）
    @ViewBuilder
    private func spokenActions(_ r: WealthPageBankRow) -> some View {
        ForEach(WealthRecordKind.allCases) { k in
            Button("記一筆" + k.title) {
                actions.open(.record(r.id, k))
            }
        }
        ForEach(r.codes, id: \.self) { code in
            Button(r.codes.count > 1 ? "對存摺 " + code : "對存摺") {
                actions.open(.anchor(r.id, code))
            }
        }
        Button("轉帳") {
            actions.open(.transfer(r.id))
        }
        Button("編輯") {
            actions.edit(r.id, .bank)
        }
        Button("收起來") {
            actions.confirm(.hideAccount(r.id, r.name))
        }
    }
}

// MARK: - ⑥ 證券戶

/// ⑥ 證券戶（券商名片）：「證券戶 1」右「持股市值 NT$86.4萬」＋灰字「股票的數字在理財」
struct WealthPageBrokersSection: View {
    let header: WealthPageGroupHeader
    let rows: [WealthPageBrokerRow]
    let actions: WealthPageActions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                MoneyGroupHeader(theme: .wealthBroker, title: "證券戶", count: header.count, total: header.total,
                                 unit: "個")
                Text("股票的數字在理財")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 39)
            }
            VStack(spacing: 10) {
                ForEach(rows) { r in
                    card(r)
                }
            }
        }
    }

    /// 點：證券戶頁；長按：編輯（沒有記一筆、轉帳、對存摺：v2 留下的④）
    private func card(_ r: WealthPageBrokerRow) -> some View {
        Button {
            actions.open(.card(r.id, nil))
        } label: {
            MoneyItemCard(item: r.item)
        }
        .buttonStyle(MoneyPressStyle())
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityHint("點兩下打開這個證券戶")
        .contextMenu {
            Button {
                actions.edit(r.id, .broker)
            } label: {
                Label("編輯", systemImage: "pencil")
            }
        }
        .accessibilityActions {
            Button("編輯") {
                actions.edit(r.id, .broker)
            }
        }
    }
}

// MARK: - ⑦ 保單（v3 基本版）

/// ⑦ 保單：「保單」右「一年約 NT$2.4萬」＋白卡一張一列；最下一列灰字「儲蓄險 1 張記在理財 › 儲蓄險」
struct WealthPagePoliciesSection: View {
    let data: WealthPagePolicies
    let actions: WealthPageActions

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "保單", trailing: data.trailing)
            list
                .modifier(FinanceCardChrome())
        }
    }

    private var list: some View {
        let pal = TripBoardPalette(scheme)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(data.rows.enumerated()), id: \.element.id) { i, r in
                if i > 0 {
                    Divider().padding(.leading, 56)
                }
                row(r, pal: pal)
            }
            if let note = data.savingsNote {
                Divider().padding(.leading, 14)
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func row(_ r: WealthPagePolicyRow, pal: TripBoardPalette) -> some View {
        Button {
            actions.open(.card(r.id, nil))
        } label: {
            WealthPagePolicyLine(row: r, pal: pal)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(r.accessibilityText)
        .accessibilityHint("點兩下打開這張保單")
        .contextMenu {
            Button {
                actions.edit(r.id, .policy)
            } label: {
                Label("編輯", systemImage: "pencil")
            }
        }
        .accessibilityActions {
            Button("編輯") {
                actions.edit(r.id, .policy)
            }
        }
    }
}

/// 保單一列：險種圖示、「國泰人壽 醫療險」、右「24,000/年」、第二行「下次 2027/8/15・刷 CUBE」
private struct WealthPagePolicyLine: View {
    let row: WealthPagePolicyRow
    let pal: TripBoardPalette

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            TripBoardIconBadge(icon: row.icon, colors: colors, diameter: 30, dark: pal.dark)
            texts
            Spacer(minLength: 6)
            amount
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private var colors: [Color] {
        [MoneyArtTheme.wealthPolicy.topColor, MoneyArtTheme.wealthPolicy.bottomColor]
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if let d = row.detail {
                Text(d)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    private var amount: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(row.amount)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(Color.primary)
            if let u = row.unit {
                Text(u)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}

// MARK: - ⑧ 收起來的

/// ⑧ 收起來的：一列「收起來的 2 ›」右灰字「玉山 Pi 卡・中華郵政」；點了就地展開（緊湊、淡一點）
struct WealthPageHiddenSection: View {
    let data: WealthPageHidden
    let actions: WealthPageActions

    @State private var expanded = false

    init(data: WealthPageHidden, actions: WealthPageActions) {
        self.data = data
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { expanded.toggle() }
            } label: {
                header
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityLabel(spokenTitle)
            .accessibilityValue(stateText)
            .accessibilityHint(hintText)
            if expanded {
                ForEach(data.rows) { r in
                    card(r)
                }
            }
        }
    }

    private var spokenTitle: String { "收起來的 \(data.rows.count) 個：" + data.names }
    private var stateText: String { expanded ? "已展開" : "已收起" }
    private var hintText: String { expanded ? "點兩下收起" : "點兩下展開" }

    private func restoreTitle(_ r: WealthPageHiddenRow) -> String { r.isCard ? "重新啟用" : "不收起來" }

    private var header: some View {
        HStack(spacing: 8) {
            Text("收起來的 \(data.rows.count)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 8)
            Text(data.names)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .modifier(FinanceCardChrome())
        .contentShape(Rectangle())
    }

    /// 點：卡片頁；長按：重新啟用（卡）／不收起來（帳戶）——都不擋訂閱
    private func card(_ r: WealthPageHiddenRow) -> some View {
        Button {
            actions.open(.card(r.id, nil))
        } label: {
            MoneyItemCard(item: r.item, compact: true)
        }
        .buttonStyle(MoneyPressStyle())
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contextMenu {
            Button {
                actions.restore(r.id, r.isCard)
            } label: {
                Label(restoreTitle(r), systemImage: "arrow.uturn.backward")
            }
        }
        .accessibilityActions {
            Button(restoreTitle(r)) {
                actions.restore(r.id, r.isCard)
            }
        }
    }
}
