import SwiftUI

// MARK: - 財富頁的字和數字（v25.564，財富 v3；wealth/judge.md §3.0–3.12）
//
// 照 HealthPageData：財富頁看板（頭部各種狀態、膠囊、一句話、手寫、VoiceOver 一句）、頂樓水塔（WealthTowerScene）、
// 存款組成條、四格、接下來 30 天・各帳戶夠不夠扣、信用卡／銀行／證券戶／保單／收起來的項目卡要的字，
// 全部在這裡一次組好（WealthPageData.build(facts:…)，在主執行緒的 .task(id:) 叫一次存 @State），body 只畫。
// 數字一律讀 WealthFacts（LifeStore.wealthFacts 的快取）。
//
// 分工：G1 實作（這個檔＋WealthBoard.swift、WealthItems.swift、LifeFinanceView.swift）。主控只開檔。
//
// [v25.564] G1：
// • 狀態（先符合先用；build/v3/brief.md §G1-1 表）：新手（沒有沒收起來的銀行、也沒有沒停用的卡）→ 只有卡 → 某帳戶 30 天內不夠扣
//   → 有逾期 → 領薪日起 3 天 → 有幣別沒匯率 → 要繳都 0 → 平常。
// • 膠囊挑一件：不夠扣 > 逾期 > 自己繳／每次問我的卡 14 天內截止 > 自動扣的卡 14 天內扣 > 要繳的都繳了 ✓ > 不出現。
// • 一句裡的萬不寫 NT$（「4.8萬」）；單筆對得上單據的寫到元（「18,600」）。遮住：金額換「••••」，日期、%、件數照常；
//   VoiceOver 念「金額已遮住」。
// • 水塔：塔＝沒收起來的銀行（照頁面順序，最多 5 座，第 6 個起併成一座「其他 ＋N」）；水位 √(存摺上÷最大那座)；
//   斜線 還沒扣÷存摺上；卡站在扣它卡費的那座塔下（沒設、帳戶收起來了：最後補一座灰色空塔「還沒選」）。
// • 排序：有 sortIndex 的照它（小的在前、沒有的排後面）；都沒排過：卡＝有要繳的在前、截止日近的在前；銀行＝最近 90 天進出筆數多到少。
// • 這裡不叫 LifeStore、不寫任何東西；NumberFormatter（ntdWanString）只在主執行緒用，所以 build 要在主執行緒叫。

// MARK: - 捲到哪一區

/// 財富頁看板上的格子、圖例點了捲到哪一區（ScrollViewReader 的 id）
enum WealthPageAnchor: Hashable {
    /// ③ 接下來 30 天・各帳戶夠不夠扣
    case upcoming
    /// ④ 信用卡
    case cards
    /// ⑤ 銀行帳戶
    case banks
}

// MARK: - 看板

/// ① 看板頭部（照 VehicleCardBoardData 的欄位）
struct WealthPageBoard {
    /// 「10/19 週一」
    let date: String
    let capsule: String?
    let capsuleIcon: String?
    /// 膠囊字色：neutral＝一般膠囊字色
    let capsuleTone: MoneyTone
    /// 「存款合計（存摺上）」「卡費還沒扣」「存款合計」
    let label: String
    /// 「NT$81.7萬」「NT$ ••••」「—」
    let big: String
    let bigTone: MoneyTone?
    /// 一句話（數字粗體、扣完能用負的才 bad）
    let line: FinanceLine
    /// 手寫（英文兩行）
    let greeting: [String]
    /// 整個頭部 VoiceOver 念的一句
    let accessibilityText: String
    let seed: Int
}

/// 看板下的一格（MoneyTile：圖示＋標籤／大字／一行灰字）
struct WealthPageTile: Identifiable {
    enum Kind: String {
        case due, unbilled, available, lowest
    }
    let kind: Kind
    let icon: String
    let tint: TripBoardTint
    let label: String
    let value: String
    let valueTone: MoneyTone?
    let detail: String?
    /// 灰字後面要上色的那一小段（「都繳了」good、「已過截止日」bad）
    let accent: String?
    let accentTone: MoneyTone
    /// 點了捲到哪一區
    let target: WealthPageAnchor

    var id: String { kind.rawValue }
}

/// 存款組成條下面的一個圖例
struct WealthPageLegend: Identifiable {
    let id: String
    let theme: MoneyArtTheme
    let text: String
}

/// 存款組成條（活存藍、定存金、外幣青；只有一種不畫條、只寫一行圖例）
struct WealthPageRibbon {
    /// 兩種以上才有（一種＝空陣列）
    let segments: [MoneyShareRibbon.Segment]
    let legend: [WealthPageLegend]
    let accessibilityText: String
}

// MARK: - ③ 接下來 30 天

/// ③ 一個帳戶一列：「薪轉（台新）　最低 約 7.6萬　✓ 夠扣」＋「10/21 交割 −52,340・11/5 月薪 +80,000」
struct WealthPageUpcomingRow: Identifiable {
    let id: UUID
    let name: String
    /// 「（台新）」：有暱稱才有
    let bank: String?
    /// 「最低 約 7.6萬」
    let lowest: String
    /// 「✓ 夠扣」「差 23,940」「現在是負的」
    let badge: String
    let badgeTone: MoneyTone
    /// 最大的兩件
    let detail: String
    let accessibilityText: String
}

/// 「看 6 件 ›」表單的一列（照日期排；FinanceLedgerRow）
struct WealthPageUpcomingItem: Identifiable {
    enum Mark {
        case income, card, stock, other
    }
    let id: String
    let day: String
    let month: String
    let glyph: String
    let mark: Mark
    let title: String
    /// 「薪轉・扣完剩 76,060」
    let detail: String
    let amount: String
    /// 扣完變負的（整列 warn）
    let negative: Bool
    let accessibilityText: String
}

struct WealthPageUpcoming {
    /// 「6 件」
    let trailing: String
    let rows: [WealthPageUpcomingRow]
    let all: [WealthPageUpcomingItem]
}

// MARK: - ④～⑧ 項目卡

/// 分組標頭（MoneyGroupHeader 的數字與合計）
struct WealthPageGroupHeader {
    let count: Int
    let total: String
}

/// ④ 一張信用卡
struct WealthPageCardRow: Identifiable {
    let id: UUID
    let item: MoneyItem
    /// 確認框用的名字（「國泰世華 CUBE」）
    let name: String
    /// 有要繳（長按才有〔標成已繳〕）
    let canMarkPaid: Bool
    /// 還在刷它的定期扣款幾筆（停用前問「要先改嗎？」）
    let recurringCount: Int
}

/// ⑤ 一個銀行帳戶
struct WealthPageBankRow: Identifiable {
    let id: UUID
    let item: MoneyItem
    let name: String
    /// 這個帳戶的幣別（對存摺選哪一格；兩個以上長按出子選單）
    let codes: [String]
}

/// ⑥ 一個證券戶
struct WealthPageBrokerRow: Identifiable {
    let id: UUID
    let item: MoneyItem
}

/// ⑦ 保單一列（v3 基本版）
struct WealthPagePolicyRow: Identifiable {
    let id: UUID
    let icon: String
    /// 「國泰人壽 醫療險」
    let title: String
    /// 「24,000」
    let amount: String
    /// 「/年」「躉繳」
    let unit: String?
    /// 「下次 2027/8/15・刷 CUBE」
    let detail: String?
    let accessibilityText: String
}

struct WealthPagePolicies {
    let rows: [WealthPagePolicyRow]
    /// 「一年約 NT$2.4萬」；算不出來 nil
    let trailing: String?
    /// 「儲蓄險 1 張記在理財 › 儲蓄險」；0 張 nil
    let savingsNote: String?
}

/// ⑧ 收起來的一列（緊湊項目卡、淡一點）
struct WealthPageHiddenRow: Identifiable {
    let id: UUID
    let item: MoneyItem
    /// 停用的卡（長按〔重新啟用〕）；false＝收起來的帳戶（〔不收起來〕）
    let isCard: Bool
}

struct WealthPageHidden {
    let rows: [WealthPageHiddenRow]
    /// 右邊灰字「玉山 Pi 卡・中華郵政」
    let names: String
}

// MARK: - 整頁

struct WealthPageData {
    enum Mode {
        /// 一個沒收起來的銀行、一張沒停用的卡都沒有
        case newbie
        /// 只有卡（沒有沒收起來的銀行）
        case cardsOnly
        case normal
    }

    let mode: Mode
    let board: WealthPageBoard
    let tower: WealthTowerScene
    let ribbon: WealthPageRibbon?
    /// 四格（沒有卡：只剩 30 天那一格；只有卡：前三格；新手：空的，換三顆大按鈕）
    let tiles: [WealthPageTile]
    /// ② 要確認（facts.pageChecks；0 件整區不出現）
    let checks: [WealthCheck]
    let upcoming: WealthPageUpcoming?
    let cardsHeader: WealthPageGroupHeader?
    let cards: [WealthPageCardRow]
    /// 沒有銀行帳戶（新手以外）：⑤ 換一張提示卡
    let showBankPrompt: Bool
    let banksHeader: WealthPageGroupHeader?
    let banks: [WealthPageBankRow]
    let brokersHeader: WealthPageGroupHeader?
    let brokers: [WealthPageBrokerRow]
    let policies: WealthPagePolicies?
    let hidden: WealthPageHidden?
    /// ⑨ 頁尾（新手不出現）
    let footer: FinanceLine?
    let masked: Bool

    /// 整頁一次組好（主執行緒：ntdWanString 用共用的 NumberFormatter）
    static func build(facts: WealthFacts, milestones: [LifeMilestone], book: WealthBook, expenses: [Expense],
                      insurances: [SavingsInsurance], rates: FinanceRates, ratesUpdatedAt: Date?,
                      now: Date, masked: Bool, dark: Bool) -> WealthPageData {
        let today = WealthCal.day(now)
        let banks = WealthPageText.orderBanks(facts.banks.filter { !$0.hidden })
        let allCards = facts.cards
        let active = WealthPageText.orderCards(allCards.filter { !$0.isDisabled })
        let mode: Mode = banks.isEmpty ? (active.isEmpty ? .newbie : .cardsOnly) : .normal

        let board = WealthPageText.board(facts: facts, mode: mode, banks: banks, cards: allCards,
                                         today: today, masked: masked)
        let tower = WealthPageText.tower(banks: banks, cards: active, mode: mode, today: today)
        let ribbon: WealthPageRibbon? = mode == .normal ? WealthPageText.ribbon(facts: facts, masked: masked) : nil
        let tiles: [WealthPageTile] = mode == .newbie
            ? []
            : WealthPageText.tiles(facts: facts, banks: banks, allCards: allCards, active: active,
                                   today: today, masked: masked)
        let upcoming = WealthPageText.upcoming(banks: banks, facts: facts, rates: rates, masked: masked)

        // ④ 信用卡
        var cardRows: [WealthPageCardRow] = []
        for c in active {
            let item = MoneyItem.wealthCard(c, masked: masked, now: now, dark: dark)
            cardRows.append(WealthPageCardRow(id: c.id, item: item, name: c.fullName, canMarkPaid: c.due > 0.5,
                                              recurringCount: WealthPageText.recurringCount(cardId: c.id,
                                                                                            expenses: expenses,
                                                                                            today: today)))
        }
        let owedActive = active.reduce(0) { $0 + $1.owed }
        let cardsHeader: WealthPageGroupHeader? = active.isEmpty ? nil
            : WealthPageGroupHeader(count: active.count,
                                    total: "還沒扣 " + (masked ? WealthFormat.masked : owedActive.ntdWanString))

        // ⑤ 銀行帳戶
        var bankRows: [WealthPageBankRow] = []
        for a in banks {
            let item = MoneyItem.wealthBank(a, facts: facts, rates: rates, masked: masked, now: now)
            bankRows.append(WealthPageBankRow(id: a.id, item: item, name: a.name, codes: WealthPageText.codes(a)))
        }
        let banksHeader: WealthPageGroupHeader? = banks.isEmpty ? nil
            : WealthPageGroupHeader(count: banks.count,
                                    total: "存摺合計 " + (masked ? WealthFormat.masked : facts.cashText))

        // ⑥ 證券戶（收起來的放 ⑧）
        let visibleBrokers = facts.brokers.filter { facts.account($0.id)?.hidden != true }
        var brokerRows: [WealthPageBrokerRow] = []
        for b in visibleBrokers {
            brokerRows.append(WealthPageBrokerRow(id: b.id, item: MoneyItem.wealthBroker(b, facts: facts, masked: masked)))
        }
        let marketValue = visibleBrokers.reduce(0) { $0 + $1.marketValue }
        let brokersHeader: WealthPageGroupHeader? = visibleBrokers.isEmpty ? nil
            : WealthPageGroupHeader(count: visibleBrokers.count,
                                    total: "持股市值 " + (masked ? WealthFormat.masked : marketValue.ntdWanString))

        let policies = WealthPageText.policies(milestones: milestones, book: book, facts: facts,
                                               insurances: insurances, today: today, masked: masked)
        let hidden = WealthPageText.hidden(facts: facts, rates: rates, masked: masked, now: now, dark: dark)
        let footer: FinanceLine? = mode == .newbie
            ? nil
            : WealthPageText.footer(banks: banks, rates: rates, ratesUpdatedAt: ratesUpdatedAt, today: today)

        return WealthPageData(mode: mode, board: board, tower: tower, ribbon: ribbon, tiles: tiles,
                              checks: facts.pageChecks, upcoming: upcoming,
                              cardsHeader: cardsHeader, cards: cardRows,
                              showBankPrompt: mode == .cardsOnly,
                              banksHeader: banksHeader, banks: bankRows,
                              brokersHeader: brokersHeader, brokers: brokerRows,
                              policies: policies, hidden: hidden, footer: footer, masked: masked)
    }
}

// MARK: - 字（全部在這裡組；body 只畫）

enum WealthPageText {
    /// 遮住時句子裡的數字
    static let dots = "••••"

    // MARK: 金額、日期

    /// 句子裡的萬不寫 NT$：「4.8萬」「1381.1萬」；一萬以下寫到元「9,800」；負的前面「-」
    static func wan(_ v: Double) -> String {
        if Swift.abs(v) >= 10_000 {
            return v.ntdWanString.replacingOccurrences(of: "NT$", with: "")
        }
        return WealthFormat.grouped(v.rounded(), decimals: 0)
    }

    /// VoiceOver 念的金額：「81 萬 6,800 元」「50 萬元」「1,860 元」「負 3,200 元」
    static func spoken(_ v: Double) -> String {
        let r = Swift.abs(v).rounded()
        guard r.isFinite, r < 9e15 else { return WealthFormat.grouped(v, decimals: 0) + " 元" }
        let n = Int64(r)
        let yi = n / 100_000_000
        let wanPart = (n % 100_000_000) / 10_000
        let rest = n % 10_000
        var s = ""
        if yi > 0 { s += "\(yi) 億" }
        if wanPart > 0 { s += (s.isEmpty ? "" : " ") + "\(wanPart) 萬" }
        if rest > 0 || s.isEmpty {
            s += (s.isEmpty ? "" : " ") + WealthFormat.grouped(Double(rest), decimals: 0) + " 元"
        } else {
            s += "元"
        }
        return (v < 0 && n != 0 ? "負 " : "") + s
    }

    /// 「10/27」
    static func md(_ d: Date) -> String { WealthFormat.monthDay(d) }

    /// VoiceOver 的日期「10 月 27 日」
    static func spokenDate(_ d: Date) -> String {
        let c = WealthCal.calendar.dateComponents([.month, .day], from: d)
        return "\(c.month ?? 0) 月 \(c.day ?? 0) 日"
    }

    /// 「2027/8/15」
    static func ymd(_ d: Date) -> String {
        let c = WealthCal.calendar.dateComponents([.year, .month, .day], from: d)
        return "\(c.year ?? 0)/\(c.month ?? 0)/\(c.day ?? 0)"
    }

    /// 看板日期列「10/19 週一」（只寫日期；樣稿①註 3）
    static func boardDate(_ d: Date) -> String {
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        let w = WealthCal.calendar.component(.weekday, from: d)
        let name = (w >= 1 && w <= 7) ? names[w - 1] : ""
        return md(d) + " 週" + name
    }

    /// 百分比的字「8.3%」
    static func percent(_ ratio: Double) -> String { WealthFormat.percent(ratio) }

    /// 使用率四段字（同 WealthFacts.Card.usageTierName：30／50／90%）
    static func tierName(_ u: Double) -> String {
        if u < 0.3 { return "很寬鬆" }
        if u < 0.5 { return "正常" }
        if u < 0.9 { return "偏高" }
        return "快刷滿了"
    }

    static func tier(_ u: Double) -> Int {
        if u < 0.3 { return 0 }
        if u < 0.5 { return 1 }
        if u < 0.9 { return 2 }
        return 3
    }

    // MARK: 名字

    /// 銀行簡稱：去「國際商業銀行」「商業銀行」「銀行」（「國泰世華商業銀行」→「國泰世華」）；去完只剩「台灣」照原名
    static func bankShort(_ name: String) -> String {
        let full = name.trimmingCharacters(in: .whitespaces)
        var s = full
        for suffix in ["國際商業銀行", "商業銀行", "銀行"] where s.hasSuffix(suffix) && s.count > suffix.count {
            s = String(s.dropLast(suffix.count))
            break
        }
        if s == "台灣" || s == "臺灣" { return full }
        return s
    }

    /// 卡的短名（去「@」）：「@GoGo」→「GoGo」
    static func cardShort(_ name: String) -> String {
        let s = name.replacingOccurrences(of: "@", with: "").trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? name : s
    }

    /// 卡費那一列的標題「@GoGo 10 月帳單（還沒繳）」→「GoGo」（沒有卡的 id 時用）
    static func cardShort(fromBillTitle title: String) -> String {
        let cut = title.replacingOccurrences(of: #"\s*\d+ 月帳單.*$"#, with: "", options: .regularExpression)
        return cardShort(cut.isEmpty ? title : cut)
    }

    /// 接下來那一列的短名：股票「交割」、卡費「GoGo」、其他照標題（最多 6 個字）
    static func shortName(_ row: WealthLedgerRow, facts: WealthFacts) -> String {
        switch row.kind {
        case .stockBuy, .stockSell:
            return "交割"
        case .dividend:
            return "股利"
        case .cardBill:
            if let c = facts.card(row.cardId) { return cardShort(c.name) }
            return cardShort(fromBillTitle: row.title)
        default:
            return String(row.title.prefix(6))
        }
    }

    /// 不夠扣那一筆的短名（WealthShortage 沒有卡的 id）
    static func shortName(_ s: WealthShortage) -> String {
        switch s.kind {
        case .stockBuy, .stockSell: return "交割"
        case .cardBill: return cardShort(fromBillTitle: s.title)
        default: return String(s.title.prefix(6))
        }
    }

    /// 接下來一列的金額「−52,340」「+80,000」「約 −23,000」（句子裡：台幣不寫 NT$）
    static func signed(_ row: WealthLedgerRow) -> String {
        let body = WealthFormat.plain(row.amount, code: row.code)
        return (row.isEstimate ? "約 " : "") + (row.isOutflow ? "−" : "+") + body
    }

    /// 一列換台幣（排「最大的兩件」用；查不到匯率照原數字）
    static func ntd(_ row: WealthLedgerRow, rates: FinanceRates) -> Double {
        row.amount * (rates.known(row.code) ?? 1)
    }

    /// 這個帳戶的幣別（對存摺選哪一格）：台幣在前；都沒有＝["NT$"]
    static func codes(_ a: WealthFacts.Account) -> [String] {
        a.currencies.isEmpty ? ["NT$"] : a.currencies
    }

    // MARK: 排序

    /// 銀行：有 sortIndex 的照它（小的在前）、沒有的排後面；都沒排過照最近 90 天進出筆數多到少
    static func orderBanks(_ list: [WealthFacts.Account]) -> [WealthFacts.Account] {
        list.enumerated().sorted { l, r in
            let a = l.element
            let b = r.element
            switch (a.sortIndex, b.sortIndex) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: break
            }
            if a.recentCount != b.recentCount { return a.recentCount > b.recentCount }
            return l.offset < r.offset
        }.map(\.element)
    }

    /// 卡：有 sortIndex 的照它；都沒排過：有要繳的在前、截止日近的在前
    static func orderCards(_ list: [WealthFacts.Card]) -> [WealthFacts.Card] {
        list.enumerated().sorted { l, r in
            let a = l.element
            let b = r.element
            switch (a.sortIndex, b.sortIndex) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: break
            }
            let aDue = a.due > 0.5
            let bDue = b.due > 0.5
            if aDue != bDue { return aDue }
            let ad = a.dueStatement?.due ?? a.nextDue
            let bd = b.dueStatement?.due ?? b.nextDue
            if ad != bd { return ad < bd }
            return l.offset < r.offset
        }.map(\.element)
    }

    /// 還在刷這張卡的定期扣款（同 WealthFacts #5 的認法：固定支出、有週期、還沒結束）
    static func recurringCount(cardId: UUID, expenses: [Expense], today: Date) -> Int {
        expenses.filter { e in
            guard e.linkedCreditCardMilestoneId == cardId, e.expenseType == .fixed, e.recurrence != nil else { return false }
            guard let end = e.endDate else { return true }
            return WealthCal.day(end) >= today
        }.count
    }
}

// MARK: - 看板頭部

/// 一句話一段一段組：畫面的字（數字粗體、上色）跟 VoiceOver 念的字一起組
private struct WealthLineBuilder {
    var runs: [FinanceRun] = []
    var spoken: String = ""
    let masked: Bool

    init(masked: Bool) {
        self.masked = masked
    }

    /// 念的時候「・」換成「，」（VoiceOver 照 judge §3.1 那句：「…還沒扣，扣完活存能用…」）
    mutating func text(_ s: String) {
        runs.append(FinanceRun(text: s))
        spoken += s.replacingOccurrences(of: "・", with: "，")
    }

    /// 金額：shown 是畫面上的字（「4.8萬」「18,600」）；遮住時「••••」、念「金額已遮住」
    mutating func money(_ v: Double, shown: String, tone: MoneyTone? = nil) {
        if masked {
            runs.append(FinanceRun(text: WealthPageText.dots, bold: true))
            spoken += "金額已遮住"
        } else {
            runs.append(FinanceRun(text: shown, bold: true, tone: tone))
            spoken += WealthPageText.spoken(v)
        }
    }

    /// 不換台幣念的金額（外幣入帳「美金 3,200.00」）：遮住時一樣「••••」
    mutating func raw(_ shown: String, spoken said: String) {
        if masked {
            runs.append(FinanceRun(text: WealthPageText.dots, bold: true))
            spoken += "金額已遮住"
        } else {
            runs.append(FinanceRun(text: shown, bold: true))
            spoken += said
        }
    }

    var line: FinanceLine { FinanceLine(runs: runs) }
}

/// 膠囊（挑一件）
private struct WealthCapsulePick {
    let text: String
    let icon: String
    let tone: MoneyTone
    let spoken: String
}

extension WealthPageText {
    /// ① 看板頭部：照狀態表挑小字、大字、一句、手寫；膠囊挑一件
    static func board(facts: WealthFacts, mode: WealthPageData.Mode, banks: [WealthFacts.Account],
                      cards: [WealthFacts.Card], today: Date, masked: Bool) -> WealthPageBoard {
        let date = boardDate(today)
        let pick = capsule(banks: banks, cards: cards, today: today, masked: masked)
        var b = WealthLineBuilder(masked: masked)
        let label: String
        let big: String
        var bigTone: MoneyTone? = nil
        let bigSpoken: String
        var greeting: [String] = ["Cash", "flows!"]

        switch mode {
        case .newbie:
            label = "存款合計"
            big = "—"
            bigSpoken = "存款合計，還沒有帳戶"
            b.text("加一個常用的帳戶，記帳扣款、卡費、薪水入帳就會接起來")
            greeting = ["Hello,", "wallet!"]
        case .cardsOnly:
            label = "卡費還沒扣"
            big = masked ? WealthFormat.masked : facts.owedCards.ntdWanString
            bigSpoken = "卡費還沒扣 " + (masked ? "金額已遮住" : spoken(facts.owedCards))
            cardsOnlyLine(&b, cards: cards)
            greeting = ["Pay", "on time!"]
        case .normal:
            label = "存款合計（存摺上）"
            big = masked ? WealthFormat.masked : facts.cashText
            if facts.cash < -0.5 { bigTone = .bad }
            let approx: String = facts.cashIsApprox ? "約 " : ""
            bigSpoken = masked ? "存款合計 金額已遮住" : "存款合計 \(approx)\(spoken(facts.cash))"
            greeting = normalLine(&b, facts: facts, banks: banks, cards: cards, today: today)
        }

        var a11y = bigSpoken + "。"
        if !b.spoken.isEmpty { a11y += b.spoken + "。" }
        if let p = pick { a11y += p.spoken + "。" }

        return WealthPageBoard(date: date, capsule: pick?.text, capsuleIcon: pick?.icon,
                               capsuleTone: pick?.tone ?? .neutral, label: label, big: big, bigTone: bigTone,
                               line: b.line, greeting: greeting, accessibilityText: a11y, seed: 71)
    }

    /// 只有卡：「要繳 18,600・還沒出帳 2.9萬」
    private static func cardsOnlyLine(_ b: inout WealthLineBuilder, cards: [WealthFacts.Card]) {
        let dueCards = cards.filter { $0.due > 0.5 }
        let due = dueCards.reduce(0) { $0 + $1.due }
        let unbilled = cards.reduce(0) { $0 + $1.unbilled }
        if due > 0.5 {
            b.text("要繳 ")
            b.money(due, shown: dueCards.count == 1 ? WealthFormat.grouped(due.rounded(), decimals: 0) : wan(due))
            if unbilled > 0.5 {
                b.text("・還沒出帳 ")
                b.money(unbilled, shown: wan(unbilled))
            }
        } else if unbilled > 0.5 {
            b.text("還沒出帳 ")
            b.money(unbilled, shown: wan(unbilled))
        } else {
            b.text("這期還沒刷")
        }
    }

    /// 有銀行帳戶：照狀態表組一句，回傳手寫
    private static func normalLine(_ b: inout WealthLineBuilder, facts: WealthFacts, banks: [WealthFacts.Account],
                                   cards: [WealthFacts.Card], today: Date) -> [String] {
        // 某帳戶 30 天內會不夠扣：照平常那句
        if banks.contains(where: { $0.shortage != nil }) {
            pendingLine(&b, facts: facts)
            return ["Top it", "up!"]
        }
        // 有逾期：「10/27 的 CUBE 帳單 18,600 還沒繳」
        if let c = cards.first(where: { $0.overdue > 0.5 }) {
            let due = c.dueStatement?.due ?? today
            b.text("\(md(due)) 的 \(c.name) 帳單 ")
            b.money(c.overdue, shown: WealthFormat.grouped(c.overdue.rounded(), decimals: 0))
            b.text(" 還沒繳")
            return ["Pay", "today!"]
        }
        // 領薪日起 3 天：「月薪 +80,000 進薪轉了・卡費還沒扣 2.9萬」
        if let pay = payday(banks: banks, today: today) {
            b.text(pay.row.title + " ")
            if FinanceRates.isNTD(pay.row.code) {
                b.money(pay.row.amount, shown: "+" + WealthFormat.plain(pay.row.amount, code: pay.row.code))
            } else {
                // 外幣入帳：念的時候照原幣寫（不換台幣）
                let plain = WealthFormat.plain(pay.row.amount, code: pay.row.code)
                b.raw("+" + plain, spoken: plain)
            }
            b.text(" 進" + pay.name + "了")
            if facts.owedCards > 0.5 {
                b.text("・卡費還沒扣 ")
                b.money(facts.owedCards, shown: wan(facts.owedCards))
            }
            return ["Pay", "day!"]
        }
        // 有幣別查不到匯率
        if facts.cashIsApprox, !facts.unknownCodes.isEmpty {
            b.text(facts.unknownCodes.joined(separator: "、") + "沒有匯率，先不算進合計")
            return ["Cash", "flows!"]
        }
        // 要繳都 0（有沒停用的卡；只剩停用的卡不算「都繳了」）
        if cards.contains(where: { !$0.isDisabled }), cards.allSatisfy({ $0.due < 0.5 }) {
            allPaidLine(&b, facts: facts)
            return ["All", "covered!"]
        }
        pendingLine(&b, facts: facts)
        return ["Cash", "flows!"]
    }

    /// 平常：「卡費 4.8萬、交割 5.2萬還沒扣・扣完活存能用 11.4萬」；只有一種「卡費還沒扣 4.8萬・扣完活存能用 16.7萬」
    private static func pendingLine(_ b: inout WealthLineBuilder, facts: WealthFacts) {
        var parts: [(name: String, value: Double)] = []
        if facts.owedCards > 0.5 { parts.append((name: "卡費", value: facts.owedCards)) }
        if facts.pendingSettlement > 0.5 { parts.append((name: "交割", value: facts.pendingSettlement)) }
        if facts.scheduledOut > 0.5 { parts.append((name: "其他", value: facts.scheduledOut)) }
        if parts.isEmpty {
            b.text("沒有還沒扣的錢・活存能用 ")
            usable(&b, facts.usable)
            return
        }
        if parts.count == 1, let only = parts.first {
            b.text(only.name + "還沒扣 ")
            b.money(only.value, shown: wan(only.value))
        } else {
            for (i, p) in parts.enumerated() {
                b.text((i == 0 ? "" : "、") + p.name + " ")
                b.money(p.value, shown: wan(p.value))
            }
            b.text("還沒扣")
        }
        b.text("・扣完活存能用 ")
        usable(&b, facts.usable)
    }

    /// 要繳都 0：「還沒出帳 2.9萬・扣完活存能用 11.4萬」（有交割、其他接在後面）
    private static func allPaidLine(_ b: inout WealthLineBuilder, facts: WealthFacts) {
        var parts: [(name: String, value: Double)] = []
        if facts.owedCards > 0.5 { parts.append((name: "還沒出帳", value: facts.owedCards)) }
        if facts.pendingSettlement > 0.5 { parts.append((name: "交割", value: facts.pendingSettlement)) }
        if facts.scheduledOut > 0.5 { parts.append((name: "其他", value: facts.scheduledOut)) }
        if parts.isEmpty {
            b.text("要繳的都繳了・活存能用 ")
            usable(&b, facts.usable)
            return
        }
        for (i, p) in parts.enumerated() {
            b.text((i == 0 ? "" : "、") + p.name + " ")
            b.money(p.value, shown: wan(p.value))
        }
        if parts.count > 1 || parts.first?.name != "還沒出帳" { b.text("還沒扣") }
        b.text("・扣完活存能用 ")
        usable(&b, facts.usable)
    }

    /// 扣完能用：負的才 bad
    private static func usable(_ b: inout WealthLineBuilder, _ v: Double) {
        b.money(v, shown: wan(v), tone: v < -0.5 ? .bad : nil)
    }

    /// 領薪日起 3 天：任一銀行今天往前 2 天內有月薪入帳（ledger 新到舊）
    private static func payday(banks: [WealthFacts.Account], today: Date) -> (row: WealthLedgerRow, name: String)? {
        for a in banks {
            for row in a.ledger where row.kind == .recurringIncome && !row.isOutflow {
                let d = WealthCal.days(from: row.date, to: today)
                if d >= 0 && d <= 2 { return (row: row, name: a.name) }
                if d > 2 { break }
            }
        }
        return nil
    }

    /// 膠囊挑一件：不夠扣 > 逾期 > 自己繳的卡 14 天內截止 > 自動扣的卡 14 天內扣 > 要繳的都繳了 ✓
    private static func capsule(banks: [WealthFacts.Account], cards: [WealthFacts.Card], today: Date,
                                masked: Bool) -> WealthCapsulePick? {
        // ① 不夠扣（最早那一筆）
        let shorts = banks.compactMap { a -> (WealthFacts.Account, WealthShortage)? in
            guard let s = a.shortage else { return nil }
            return (a, s)
        }.sorted { $0.1.date < $1.1.date }
        if let first = shorts.first {
            let a = first.0
            let s = first.1
            let head = "\(md(s.date)) \(a.name)"
            let text: String = masked ? "\(head)不夠扣" : "\(head)差 \(WealthFormat.plain(s.short, code: s.code))"
            var say = "\(spokenDate(s.date)) \(a.name)不夠扣"
            if !masked { say += "，差 \(spokenShort(s))" }
            return WealthCapsulePick(text: text, icon: "exclamationmark.triangle", tone: .warn, spoken: say)
        }
        // ② 逾期
        if let c = cards.first(where: { $0.overdue > 0.5 }) {
            let due = c.dueStatement?.due ?? today
            let n = Swift.max(1, WealthCal.days(from: due, to: today))
            return WealthCapsulePick(text: "\(c.name) 已過截止日 \(n) 天", icon: "exclamationmark.circle", tone: .bad,
                                     spoken: "\(c.fullName) 卡已過截止日 \(n) 天")
        }
        // ③ 自己繳／每次問我的卡 14 天內截止（最近的）
        let manual = cards.compactMap { c -> (WealthFacts.Card, Date)? in
            guard !c.payMode.isAuto, let s = c.dueStatement, s.status == .due else { return nil }
            let n = WealthCal.days(from: today, to: s.due)
            return (n >= 0 && n <= 14) ? (c, s.due) : nil
        }.sorted { $0.1 < $1.1 }
        if let first = manual.first {
            let c = first.0
            let due = first.1
            let n = WealthCal.days(from: today, to: due)
            let text = n == 0 ? "\(c.name) 今天截止" : "\(c.name) \(md(due)) 截止・\(n) 天"
            let say = n == 0 ? "\(c.fullName) 卡今天截止" : "\(c.fullName) 卡 \(spokenDate(due))截止，還有 \(n) 天"
            return WealthCapsulePick(text: text, icon: "creditcard", tone: n <= 3 ? .warn : .neutral, spoken: say)
        }
        // ④ 自動扣的卡有要繳、14 天內扣
        let auto = cards.compactMap { c -> (WealthFacts.Card, Date)? in
            guard c.payMode.isAuto, c.due > 0.5, let s = c.dueStatement, s.status == .due else { return nil }
            let n = WealthCal.days(from: today, to: s.due)
            return (n >= 0 && n <= 14) ? (c, s.due) : nil
        }.sorted { $0.1 < $1.1 }
        if let first = auto.first {
            let c = first.0
            let due = first.1
            let n = WealthCal.days(from: today, to: due)
            let from = c.payerName.map { "從\($0)扣" } ?? "扣款"
            let text = n == 0 ? "\(c.name) 今天\(from)" : "\(c.name) \(md(due)) \(from)・\(n) 天"
            let say = n == 0 ? "\(c.fullName) 卡今天\(from)" : "\(c.fullName) 卡 \(spokenDate(due))\(from)，還有 \(n) 天"
            return WealthCapsulePick(text: text, icon: "creditcard", tone: n <= 3 ? .warn : .neutral, spoken: say)
        }
        // ⑤ 卡的要繳都 0、最近 30 天有已繳
        if !cards.isEmpty, cards.allSatisfy({ $0.due < 0.5 }) {
            let recent = cards.contains { c in
                guard let p = c.lastPaid else { return false }
                let d = WealthCal.days(from: p.paidOn ?? p.due, to: today)
                return d >= 0 && d <= 30
            }
            if recent {
                return WealthCapsulePick(text: "要繳的都繳了 ✓", icon: "checkmark.circle", tone: .good,
                                         spoken: "要繳的都繳了")
            }
        }
        return nil
    }

    private static func spokenShort(_ s: WealthShortage) -> String {
        FinanceRates.isNTD(s.code) ? spoken(s.short) : WealthFormat.plain(s.short, code: s.code)
    }
}

// MARK: - 水塔、組成條、四格

extension WealthPageText {
    /// 頂樓水塔（規則照 WealthBoardScenes.swift 檔頭 A＋sim 3）
    static func tower(banks: [WealthFacts.Account], cards: [WealthFacts.Card], mode: WealthPageData.Mode,
                      today: Date) -> WealthTowerScene {
        if mode == .newbie {
            let empty = WealthTowerScene.Tower(level: 0, hatch: 0, kind: .empty, label: "", badge: nil, warn: false,
                                               dashed: true)
            return WealthTowerScene(towers: [empty, empty, empty], cards: [])
        }
        // 塔：前 5 座照頁面順序，第 6 個起併成一座。有卡沒設從哪扣（或扣款帳戶收起來了）要多補一座灰色空塔：
        // 那時只放 4 座＋併塔，整排最多 6 座（G4 照 6 座排塔寬）
        let bankIds = Set(banks.map(\.id))
        let needsEmpty = cards.contains { c in
            guard let p = c.payerId else { return true }
            return !bankIds.contains(p)
        }
        let limit = (needsEmpty && banks.count > 5) ? 4 : 5
        let shown = Array(banks.prefix(limit))
        let rest = Array(banks.dropFirst(limit))
        var totals: [Double] = shown.map(\.ntdTotal)
        if !rest.isEmpty { totals.append(rest.reduce(0) { $0 + $1.ntdTotal }) }
        let top = totals.map { Swift.max(0, $0) }.max() ?? 0

        var towers: [WealthTowerScene.Tower] = []
        var towerOf: [UUID: Int] = [:]
        for (i, a) in shown.enumerated() {
            towers.append(towerFor(a, top: top))
            towerOf[a.id] = i
        }
        if !rest.isEmpty {
            let total = rest.reduce(0) { $0 + $1.ntdTotal }
            let owed = rest.reduce(0) { $0 + $1.notYetDebited }
            let warn = rest.contains { $0.shortage != nil || $0.ntdTotal < -0.5 }
            towers.append(WealthTowerScene.Tower(level: level(total, top: top), hatch: hatch(owed, of: total),
                                                 kind: .live, label: "其他", badge: "＋\(rest.count)", warn: warn))
            for a in rest { towerOf[a.id] = towers.count - 1 }
        }

        // 卡：站在扣它卡費的那座塔下；沒設、帳戶收起來了＝最後補一座灰色空塔
        var sceneCards: [WealthTowerScene.Card] = []
        var emptyIndex: Int? = nil
        for c in cards {
            let index: Int
            if let p = c.payerId, let t = towerOf[p] {
                index = t
            } else if let e = emptyIndex {
                index = e
            } else {
                let label = towers.isEmpty ? "還沒選從哪扣" : "還沒選"
                towers.append(WealthTowerScene.Tower(level: 0, hatch: 0, kind: .empty, label: label, badge: nil,
                                                     warn: false))
                emptyIndex = towers.count - 1
                index = towers.count - 1
            }
            let next = c.dueStatement?.due ?? c.nextDue
            sceneCards.append(WealthTowerScene.Card(tower: index, dashed: !c.payMode.isAuto, color: c.faceColor,
                                                    label: md(next)))
        }
        return WealthTowerScene(towers: towers, cards: sceneCards)
    }

    private static func towerFor(_ a: WealthFacts.Account, top: Double) -> WealthTowerScene.Tower {
        let kind: WealthTowerScene.Tower.Kind
        var badge: String? = nil
        if a.isFixedDeposit {
            kind = .deposit
        } else if let code = foreignCode(a) {
            kind = .foreign
            badge = FinanceRates.isUSD(code) ? "US$" : String(code.prefix(3))
        } else {
            kind = .live
        }
        let label = a.nickname ?? String(bankShort(a.bankName).prefix(4))
        let warn = a.shortage != nil || a.ntdTotal < -0.5
        return WealthTowerScene.Tower(level: level(a.ntdTotal, top: top), hatch: hatch(a.notYetDebited, of: a.ntdTotal),
                                      kind: kind, label: label, badge: badge, warn: warn)
    }

    /// 外幣帳戶（種類是外幣、或只有一個不是台幣的幣別）的那個幣別；不是外幣帳戶 nil
    static func foreignCode(_ a: WealthFacts.Account) -> String? {
        if let c = a.singleCode, !FinanceRates.isNTD(c) { return c }
        if a.isForeignType {
            return a.currencies.first(where: { !FinanceRates.isNTD($0) }) ?? "外幣"
        }
        return nil
    }

    /// 水位 √(存摺上÷最大那座)；負的、0 元＝0
    private static func level(_ v: Double, top: Double) -> Double {
        guard top > 0.5, v > 0 else { return 0 }
        return Swift.min(1, (v / top).squareRoot())
    }

    /// 斜線 還沒扣÷存摺上（比水還多＝1）
    private static func hatch(_ owed: Double, of total: Double) -> Double {
        guard total > 0.5, owed > 0 else { return 0 }
        return Swift.min(1, owed / total)
    }

    /// 存款組成條：活存藍、定存金、外幣青（外幣一律「約」）
    static func ribbon(facts: WealthFacts, masked: Bool) -> WealthPageRibbon? {
        var parts: [(id: String, name: String, theme: MoneyArtTheme, value: Double, approx: Bool)] = []
        if facts.live > 0.5 { parts.append((id: "live", name: "活存", theme: .wealthLive, value: facts.live, approx: false)) }
        if facts.fixedDeposit > 0.5 {
            parts.append((id: "fixed", name: "定存", theme: .wealthDeposit, value: facts.fixedDeposit, approx: false))
        }
        if facts.foreign > 0.5 {
            parts.append((id: "foreign", name: "外幣", theme: .wealthForeign, value: facts.foreign, approx: true))
        }
        guard !parts.isEmpty else { return nil }
        let total = parts.reduce(0) { $0 + $1.value }
        let segments: [MoneyShareRibbon.Segment] = parts.count >= 2
            ? parts.map { MoneyShareRibbon.Segment(theme: $0.theme, value: $0.value) }
            : []
        var legend: [WealthPageLegend] = []
        var said: [String] = []
        for p in parts {
            let approx: String = p.approx ? "約" : ""
            let amount: String = masked ? dots : "\(approx)\(wan(p.value))"
            legend.append(WealthPageLegend(id: p.id, theme: p.theme, text: "\(p.name) \(amount)"))
            let pct: Int = total > 0 ? Int((p.value / total * 100).rounded()) : 0
            var one = "\(p.name) \(pct)%"
            if !masked { one += "，\(approx)\(spoken(p.value))" }
            said.append(one)
        }
        return WealthPageRibbon(segments: segments, legend: legend,
                                accessibilityText: "存款組成：" + said.joined(separator: "；"))
    }

    /// 四格（沒有卡：只剩 30 天那一格；只有卡：前三格）
    static func tiles(facts: WealthFacts, banks: [WealthFacts.Account], allCards: [WealthFacts.Card],
                      active: [WealthFacts.Card], today: Date, masked: Bool) -> [WealthPageTile] {
        var out: [WealthPageTile] = []
        if !active.isEmpty {
            out.append(dueTile(allCards, masked: masked))
            out.append(unbilledTile(allCards, active: active, masked: masked))
            out.append(availableTile(active, masked: masked))
        }
        if !banks.isEmpty {
            out.append(lowestTile(banks, facts: facts, today: today, masked: masked))
        }
        return out
    }

    /// 要繳：一張寫到元「NT$18,600」；兩張以上萬；0「NT$0」灰字「都繳了」（good）
    private static func dueTile(_ cards: [WealthFacts.Card], masked: Bool) -> WealthPageTile {
        let dueCards = cards.filter { $0.due > 0.5 }
            .sorted { ($0.dueStatement?.due ?? $0.nextDue) < ($1.dueStatement?.due ?? $1.nextDue) }
        let total = dueCards.reduce(0) { $0 + $1.due }
        var value: String
        var detail: String? = nil
        var accent: String? = nil
        var accentTone: MoneyTone = .neutral
        if dueCards.isEmpty {
            value = "NT$0"
            accent = "都繳了"
            accentTone = .good
        } else if dueCards.count == 1, let c = dueCards.first {
            value = WealthFormat.ntd(total)
            let due = c.dueStatement?.due ?? c.nextDue
            if c.overdue > 0.5 {
                accent = c.name + " 已過截止日"
                accentTone = .bad
            } else {
                detail = c.name + " " + md(due) + " 截止"
            }
        } else {
            value = total.ntdWanString
            let first = dueCards.first.map { $0.dueStatement?.due ?? $0.nextDue } ?? Date()
            detail = "\(dueCards.count) 張・最近 \(md(first))"
            if dueCards.contains(where: { $0.overdue > 0.5 }) {
                accent = "有逾期"
                accentTone = .bad
            }
        }
        if masked { value = WealthFormat.masked }
        return WealthPageTile(kind: .due, icon: "doc.text.fill", tint: .orange, label: "要繳", value: value,
                              valueTone: nil, detail: detail, accent: accent, accentTone: accentTone, target: .cards)
    }

    /// 還沒出帳「NT$2.9萬」「2 張・下次 10/25 結帳」
    private static func unbilledTile(_ cards: [WealthFacts.Card], active: [WealthFacts.Card],
                                     masked: Bool) -> WealthPageTile {
        let total = cards.reduce(0) { $0 + $1.unbilled }
        let n = cards.filter { $0.unbilled > 0.5 }.count
        let next = active.map(\.nextClose).min()
        var detail: String? = nil
        if let d = next {
            detail = (n > 0 ? "\(n) 張・下次 " : "下次 ") + md(d) + " 結帳"
        }
        return WealthPageTile(kind: .unbilled, icon: "creditcard.fill", tint: .mint, label: "還沒出帳",
                              value: masked ? WealthFormat.masked : total.ntdWanString, valueTone: nil,
                              detail: detail, accent: nil, accentTone: .neutral, target: .cards)
    }

    /// 還能刷：有額度的卡合計；「額度用了 9.6%・很寬鬆」（沒填額度的卡不算）
    private static func availableTile(_ active: [WealthFacts.Card], masked: Bool) -> WealthPageTile {
        let limited = active.filter { $0.limit != nil }
        let missing = active.count - limited.count
        guard !limited.isEmpty else {
            return WealthPageTile(kind: .available, icon: "gauge.with.dots.needle.33percent", tint: .purple,
                                  label: "還能刷", value: "—", valueTone: nil, detail: "沒填額度", accent: nil,
                                  accentTone: .neutral, target: .cards)
        }
        let available = limited.reduce(0) { $0 + ($1.available ?? 0) }
        let owed = limited.reduce(0) { $0 + $1.owed }
        let limit = limited.reduce(0) { $0 + ($1.limit ?? 0) }
        var detail = ""
        if limit > 0 {
            let u = owed / limit
            detail = "額度用了 " + percent(u) + "・" + tierName(u)
        }
        if missing > 0 { detail += (detail.isEmpty ? "" : "・") + "\(missing) 張沒填額度" }
        return WealthPageTile(kind: .available, icon: "gauge.with.dots.needle.33percent", tint: .purple,
                              label: "還能刷", value: masked ? WealthFormat.masked : available.ntdWanString,
                              valueTone: nil, detail: detail.isEmpty ? nil : detail, accent: nil,
                              accentTone: .neutral, target: .cards)
    }

    /// 30 天內最低：沒收起來的銀行 lowestNTD 最小那個；有不夠扣「差 NT$23,940」（warn）
    private static func lowestTile(_ banks: [WealthFacts.Account], facts: WealthFacts, today: Date,
                                   masked: Bool) -> WealthPageTile {
        let shorts = banks.compactMap { a -> (WealthFacts.Account, WealthShortage)? in
            guard let s = a.shortage else { return nil }
            return (a, s)
        }.sorted { $0.1.date < $1.1.date }
        var value: String
        var tone: MoneyTone? = nil
        let detail: String
        if let first = shorts.first {
            let a = first.0
            let s = first.1
            value = "差 " + WealthFormat.money(s.short, code: s.code)
            tone = .warn
            detail = "\(a.name)・\(md(s.date)) \(shortName(s))前"
            if masked { value = "差 " + WealthFormat.masked }
        } else {
            let lows = banks.compactMap { a -> (WealthFacts.Account, Double)? in
                guard let l = a.lowestNTD else { return nil }
                return (a, l)
            }
            if let best = lows.min(by: { $0.1 < $1.1 }) {
                let a = best.0
                let low = best.1
                value = "約 " + low.ntdWanString
                if low < -0.5 { tone = .bad }
                detail = lowestDetail(a, facts: facts, today: today)
            } else {
                let now = banks.map(\.ntdTotal).min() ?? 0
                value = now.ntdWanString
                if now < -0.5 { tone = .bad }
                detail = "30 天內沒有扣款"
            }
            if masked { value = WealthFormat.masked }
        }
        // ③ 不出現（30 天內都沒有進出）就捲到 ⑤
        let target: WealthPageAnchor = banks.contains(where: { !$0.next30.isEmpty }) ? .upcoming : .banks
        return WealthPageTile(kind: .lowest, icon: "drop.fill", tint: .blue, label: "30 天內最低", value: value,
                              valueTone: tone, detail: detail, accent: nil, accentTone: .neutral, target: target)
    }

    /// 「房貸扣款・11/5 房貸後」（最低那天最後一筆的短名＋「後」）；最低就是今天「房貸扣款・今天」
    private static func lowestDetail(_ a: WealthFacts.Account, facts: WealthFacts, today: Date) -> String {
        guard let d = a.lowestDate, WealthCal.day(d) > today else { return a.name + "・今天" }
        let day = WealthCal.day(d)
        if let last = a.next30.last(where: { WealthCal.day($0.date) == day }) {
            return "\(a.name)・\(md(d)) \(shortName(last, facts: facts))後"
        }
        return a.name + "・" + md(d)
    }
}

// MARK: - ③ 接下來 30 天

extension WealthPageText {
    /// 每個沒收起來、30 天內有進出的銀行一列；「看 6 件」照日期排全部
    static func upcoming(banks: [WealthFacts.Account], facts: WealthFacts, rates: FinanceRates,
                         masked: Bool) -> WealthPageUpcoming? {
        let listed = banks.filter { !$0.next30.isEmpty }
        guard !listed.isEmpty else { return nil }
        var rows: [WealthPageUpcomingRow] = []
        var all: [(date: Date, order: Int, item: WealthPageUpcomingItem)] = []
        var count = 0
        for (order, a) in listed.enumerated() {
            rows.append(upcomingRow(a, facts: facts, rates: rates, masked: masked))
            for row in a.next30 {
                count += 1
                all.append((date: row.date, order: order, item: upcomingItem(row, account: a, facts: facts, masked: masked)))
            }
        }
        let sorted = all.sorted { l, r in
            if l.date != r.date { return l.date < r.date }
            return l.order < r.order
        }.map(\.item)
        return WealthPageUpcoming(trailing: "\(count) 件", rows: rows, all: sorted)
    }

    private static func upcomingRow(_ a: WealthFacts.Account, facts: WealthFacts, rates: FinanceRates,
                                    masked: Bool) -> WealthPageUpcomingRow {
        let bank: String? = a.nickname == nil ? nil : "（" + bankShort(a.bankName) + "）"
        let low = a.lowestNTD ?? a.ntdTotal
        let lowest: String = masked ? "最低 \(dots)" : "最低 約 \(wan(low))"
        let badge: String
        let tone: MoneyTone
        var said: String
        if a.ntdTotal < -0.5 {
            badge = "現在是負的"
            tone = .bad
            said = "現在是負的"
        } else if let s = a.shortage {
            badge = masked ? "不夠扣" : "差 \(WealthFormat.plain(s.short, code: s.code))"
            tone = .warn
            said = "\(spokenDate(s.date))不夠扣"
            if !masked { said += "，差 \(spokenShort(s))" }
        } else {
            badge = "✓ 夠扣"
            tone = .good
            said = "夠扣"
        }
        // 第二行：最大的兩件（照 |金額|），再照日期排（next30 本來就是舊到新）
        let biggest = biggestTwo(a.next30, rates: rates)
        let pieces: [String] = biggest.map { row in
            let head = md(row.date) + " " + shortName(row, facts: facts)
            return masked ? head : head + " " + signed(row)
        }
        let detail = pieces.joined(separator: "・")
        let lowSaid: String = masked ? "金額已遮住" : "約 \(spoken(low))"
        var who: String = a.name
        if bank != nil { who += "，\(bankShort(a.bankName))" }
        said = "\(who)，30 天內最低 \(lowSaid)，\(said)。\(detail)"
        return WealthPageUpcomingRow(id: a.id, name: a.name, bank: bank, lowest: lowest, badge: badge, badgeTone: tone,
                                     detail: detail, accessibilityText: said)
    }

    /// 金額（換台幣）最大的兩件，照原本的先後（日期）回傳
    private static func biggestTwo(_ rows: [WealthLedgerRow], rates: FinanceRates) -> [WealthLedgerRow] {
        var indexed: [(index: Int, size: Double)] = []
        for (i, row) in rows.enumerated() {
            indexed.append((index: i, size: Swift.abs(ntd(row, rates: rates))))
        }
        indexed.sort { l, r in
            if l.size != r.size { return l.size > r.size }
            return l.index < r.index
        }
        let picked: [Int] = indexed.prefix(2).map { $0.index }.sorted()
        return picked.map { rows[$0] }
    }

    private static func upcomingItem(_ row: WealthLedgerRow, account a: WealthFacts.Account, facts: WealthFacts,
                                     masked: Bool) -> WealthPageUpcomingItem {
        let c = WealthCal.calendar.dateComponents([.month, .day], from: row.date)
        let mark: WealthPageUpcomingItem.Mark
        let glyph: String
        switch row.kind {
        case .stockBuy, .stockSell, .dividend:
            mark = .stock
            glyph = "股"
        case .cardBill:
            mark = .card
            glyph = "卡"
        default:
            if row.isOutflow {
                mark = .other
                glyph = row.kind == .transferOut ? "轉" : "扣"
            } else {
                mark = .income
                glyph = row.kind == .transferIn ? "轉" : "入"
            }
        }
        let after = WealthFormat.plain(row.balanceAfter, code: row.code)
        let detail = a.name + "・扣完剩 " + (masked ? dots : after)
        let amount = masked ? dots : signed(row)
        let negative = row.balanceAfter < -0.5
        var said = "\(spokenDate(row.date))，\(row.title)，\(a.name)，"
        said += masked ? "金額已遮住" : "\(signed(row))，扣完剩 \(after)"
        if negative { said += "，會不夠扣" }
        return WealthPageUpcomingItem(id: a.id.uuidString + "|" + row.id, day: "\(c.day ?? 0)",
                                      month: "\(c.month ?? 0)月", glyph: glyph, mark: mark, title: row.title,
                                      detail: detail, amount: amount, negative: negative, accessibilityText: said)
    }
}

// MARK: - ⑦ 保單、⑧ 收起來的、⑨ 頁尾

extension WealthPageText {
    /// ⑦ 保單（v3 基本版：保障型一張一列；儲蓄險在理財）
    static func policies(milestones: [LifeMilestone], book: WealthBook, facts: WealthFacts,
                         insurances: [SavingsInsurance], today: Date, masked: Bool) -> WealthPagePolicies? {
        let list = milestones.filter { m in
            m.category == .achievement && m.financeSubCategory == .insurance && book.account(m.id).hidden != true
        }
        guard !list.isEmpty else { return nil }
        let ordered = list.enumerated().sorted { l, r in
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

        var rows: [WealthPagePolicyRow] = []
        var yearly: Double = 0
        var hasYearly = false
        for m in ordered {
            let prefs = book.policy(m.id)
            let kind = prefs.kind ?? WealthPolicyKind.from(legacy: m.insuranceType)
            let company = (m.insuranceCompany ?? "").trimmingCharacters(in: .whitespaces)
            let title: String
            if let n = book.account(m.id).trimmedNickname {
                title = n
            } else if company.isEmpty {
                title = m.title
            } else {
                title = company + " " + kind.shortTitle
            }
            let premium = m.premiumAmount ?? 0
            var amount = "—"
            var unit: String? = nil
            var amountSaid = ""
            if premium > 0.5 {
                if let cycle = prefs.cycle {
                    if cycle.timesPerYear > 0 {
                        let y = premium * Double(cycle.timesPerYear)
                        yearly += y
                        hasYearly = true
                        amount = WealthFormat.grouped(y.rounded(), decimals: 0)
                        unit = "/年"
                        amountSaid = "一年 " + spoken(y)
                    } else {
                        amount = WealthFormat.grouped(premium.rounded(), decimals: 0)
                        unit = "躉繳"
                        amountSaid = "躉繳 " + spoken(premium)
                    }
                } else {
                    amount = WealthFormat.grouped(premium.rounded(), decimals: 0)
                    amountSaid = "保費 " + spoken(premium)
                }
                if masked {
                    amount = dots
                    amountSaid = "金額已遮住"
                }
            }
            var parts: [String] = []
            if let next = prefs.nextDue { parts.append("下次 " + ymd(next)) }
            if let pay = prefs.payFromId {
                if let c = facts.card(pay) {
                    parts.append("刷 " + c.name)
                } else if let acc = facts.account(pay) {
                    parts.append("從" + acc.name + "扣")
                }
            }
            let detail: String? = parts.isEmpty ? nil : parts.joined(separator: "・")
            var said: String = title
            if !amountSaid.isEmpty { said += "，\(amountSaid)" }
            if let d = detail { said += "，\(d)" }
            rows.append(WealthPagePolicyRow(id: m.id, icon: policyIcon(kind), title: title, amount: amount, unit: unit,
                                            detail: detail, accessibilityText: said))
        }
        var trailing: String? = nil
        if hasYearly { trailing = "一年約 " + (masked ? WealthFormat.masked : yearly.ntdWanString) }
        let savings = insurances.filter { WealthCal.day($0.maturityDate) >= today }.count
        let note: String? = savings > 0 ? "儲蓄險 \(savings) 張記在理財 › 儲蓄險" : nil
        return WealthPagePolicies(rows: rows, trailing: trailing, savingsNote: note)
    }

    private static func policyIcon(_ k: WealthPolicyKind) -> String {
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

    /// ⑧ 收起來的：停用的卡、收起來的銀行、收起來的證券戶（緊湊、淡一點）
    static func hidden(facts: WealthFacts, rates: FinanceRates, masked: Bool, now: Date,
                       dark: Bool) -> WealthPageHidden? {
        var rows: [WealthPageHiddenRow] = []
        var names: [String] = []
        for c in facts.cards where c.isDisabled {
            var item = MoneyItem.wealthCard(c, masked: masked, now: now, dark: dark)
            item.dimmed = true
            rows.append(WealthPageHiddenRow(id: c.id, item: item, isCard: true))
            names.append(c.fullName)
        }
        for a in facts.accounts where a.hidden {
            var item: MoneyItem
            if a.isSecurities, let b = facts.broker(a.id) {
                item = MoneyItem.wealthBroker(b, facts: facts, masked: masked)
            } else {
                item = MoneyItem.wealthBank(a, facts: facts, rates: rates, masked: masked, now: now)
            }
            item.dimmed = true
            rows.append(WealthPageHiddenRow(id: a.id, item: item, isCard: false))
            names.append(a.name)
        }
        guard !rows.isEmpty else { return nil }
        return WealthPageHidden(rows: rows, names: names.joined(separator: "・"))
    }

    /// ⑨ 頁尾：存摺上怎麼算＋外幣用哪個匯率（超過 3 天沒更新，最後那句琥珀色「匯率是 10/15 的」）
    static func footer(banks: [WealthFacts.Account], rates: FinanceRates, ratesUpdatedAt: Date?,
                       today: Date) -> FinanceLine {
        var runs: [FinanceRun] = [FinanceRun(text: footerBase)]
        var foreign: [String] = []
        for a in banks {
            for code in a.currencies where !FinanceRates.isNTD(code) && !foreign.contains(code) {
                foreign.append(code)
            }
        }
        let known = foreign.compactMap { code -> String? in
            guard let r = rates.known(code) else { return nil }
            return code + " " + WealthFormat.rate(r)
        }.prefix(2)
        guard !known.isEmpty else { return FinanceLine(runs: runs) }
        let list = known.joined(separator: "、")
        if let at = ratesUpdatedAt {
            let age = WealthCal.days(from: at, to: today)
            if age > 3 {
                runs.append(FinanceRun(text: "外幣用設定裡的匯率（" + list + "），"))
                runs.append(FinanceRun(text: "匯率是 " + md(at) + " 的。", bold: true, tone: .warn))
            } else {
                runs.append(FinanceRun(text: "外幣用設定裡的匯率（\(list)，\(md(at))）。"))
            }
        } else {
            runs.append(FinanceRun(text: "外幣用設定裡的匯率（" + list + "）。"))
        }
        return FinanceLine(runs: runs)
    }

    /// 頁尾前半（「這頁的數字怎麼算」也用；v3 不寫理財的淨資產，v4 才接）
    static let footerBase = "存摺上的數字：卡費在繳款截止日、股票交割在第 2 個營業日才扣，跟銀行 App 對得上。"
        + "記帳、股票、房子的扣款選單用的都是這個數。對不上時到帳戶裡按〔對存摺〕。"

    /// ⋯「這頁的數字怎麼算」
    static let howItWorks: [String] = [
        footerBase,
        "扣完能用＝存摺上 − 還沒扣（卡費要繳＋還沒出帳＋還沒交割的股票款）。存款合計不含證券戶的持股，持股市值在理財 › 股票。",
        "自己繳的卡過了截止日沒標成已繳，App 當作從「通常從」的帳戶繳了全額，隔天會在「要確認」問你一次；選「每次問我」的卡不會當作已繳。",
        "外幣照設定裡的匯率換台幣；查不到匯率的那一格不算進合計，大字前面會加「約」。",
        "繳款截止日、交割日遇到假日，銀行可能順延；App 不會自己順延。",
        "右上的眼睛可以把金額遮住（記在這台裝置）；關掉遮住要 Face ID。"
    ]

    /// ⋯「iCloud 與家人共享說明」（judge §7.3；使用者第 6 題：安全碼照樣加密存）
    static let iCloudNote: [String] = [
        "家人接受共享後看得到所有帳戶名稱、存摺數字、帳號後 4 碼。完整卡號、完整帳號、安全碼是加密的："
            + "用同一個 Apple ID 的裝置解得開，用不同 Apple ID 的家人解不開。",
        "看完整號碼要 Face ID，30 秒自動收回；App 切到背景時，財富的卡片頁和表單會先蓋住。",
        "小孩或家人的戶頭可以列著但不算進存款合計：到「⋯ › 排序與收起來」關掉「算進存款合計」。"
    ]
}
