import Foundation

// MARK: - [v25.583] 定期轉帳 v4 換匯、每兩週、每年、遇六日（transfer/judge.md §2.1、§3.2、§4.2、§4.4、§5、§11.5、§13；
// transfer/build/v4/brief.md §2；sim_v4.py 照這裡一行一行寫過、跑過）
//
// v1a（WealthTransfers.swift）定下來的資料**一個欄位都不加**、**沒有新的同步鍵**（照舊 life_wealth_transfers_v1）：
// • 週期：cycle 多兩個字 "biweekly"（每兩週）、"yearly"（每年；month＋day）——v1a 就存字串，25.575～25.581 的手機讀到＝這條不展開、存一次照原樣留著。
// • 遇六日：holiday nil／"next"／"prev"（v1a 就有這欄、只存不用）。只看星期六、日（同交割 taiwanSettlementDate 的週末判斷），**不內建國定假日表**
//  （第 10 題照建議）；哪一期銀行挪了別天，點那一期改日子。預設照當天，換匯預設順延（表單帶）。
// • 換匯／外幣：段的 fromCode／toCode（nil＝台幣）＋toAmount（對方收到多少，寫死、不跟設定的匯率）、每一期註記的 toAmount（那一期銀行實際換多少）
//  ——v1a 都有。設定裡改匯率，規則裡這兩個數不變（存款合計照新匯率換算外幣格，那是外幣本來就會漂的部分）。
// 這個檔只放算法與字（純函式；WealthTransfers.swift 展開、畫面、WealthFacts、LifeStore 叫），不碰存檔。
//
// 例（judge §11.5，今天 2026/10/23（五），匯率美金 32.0）：「每月 1 日 NT$9,600 → 存錢美金 US$300.00・遇六日順延」——
// 2026/11/1 是星期日 → 11/2（一）存錢台幣格 −9,600、美金格 +US$300.00（US$3,200.00 → US$3,500.00）；那一期的 key 照舊「2026-11-01」。
// 設定改匯率 32.5：那兩個數照舊 −9,600、+US$300.00。那一期銀行實際 31.85＝那一期 amount 9,555（toAmount 照規則 300.00）。

/// 遇六日（WealthTransferRule.holiday 存字串：nil 照當天、"next" 順延到星期一、"prev" 提前到星期五；不認得的字＝照當天）
enum WealthTransferHoliday: Equatable {
    case onDay, next, prev

    init(raw: String?) {
        switch raw {
        case "next"?: self = .next
        case "prev"?: self = .prev
        default: self = .onDay
        }
    }

    /// 存回去的字（照當天＝nil）
    var raw: String? {
        switch self {
        case .onDay: return nil
        case .next: return "next"
        case .prev: return "prev"
        }
    }
}

extension WealthTransferRule {
    /// [v25.583] 遇六日（holiday 的字；不認得＝照當天）
    var holidayKind: WealthTransferHoliday { WealthTransferHoliday(raw: holiday) }
}

// MARK: - 日子

extension WealthTransferSchedule {
    /// 照遇六日挪過的那天（只看星期六、日；不是六日＝那天）：順延＝下一個星期一、提前＝前一個星期五
    static func shifted(_ d: Date, holiday: WealthTransferHoliday) -> Date {
        let x = WealthCal.day(d)
        switch holiday {
        case .onDay: return x
        case .next: return WealthTransferText.nextWeekday(x)
        case .prev: return WealthTransferText.prevWeekday(x)
        }
    }

    /// 一期大約幾天（〔共幾次〕、〔到哪一期恢復〕往後看多遠）：每週 7、每兩週 14、每月 31、每年 366
    static func periodDays(_ c: WealthTransferCycle) -> Int {
        switch c {
        case .weekly: return 7
        case .biweekly: return 14
        case .monthly: return 31
        case .yearly: return 366
        }
    }

    /// 規則頁、〔選一期…〕、〔暫停〕、我的行事曆往後看幾天：每年的看 3 年多（不然「接下來」只有一期），其他照舊 400 天
    static func lookAheadDays(_ c: WealthTransferCycle?) -> Int {
        c == .yearly ? 366 * 3 + 31 : 400
    }

    /// 〔改這一期〕第一期、最後一期那一邊放寬幾天（不能跨過前後一期）：每週 6、每兩週 13、每月 27、每年 364；不認得的照每月
    static func editGapDays(_ c: WealthTransferCycle?) -> Int {
        switch c {
        case .weekly?: return 6
        case .biweekly?: return 13
        case .yearly?: return 364
        case .monthly?, nil: return 27
        }
    }

    /// 新增表單「下一期」：照週期、哪天（firstDate 同一套）＋遇六日，**實際那天**在 from（含）以後的第一期——回**原本的日子**（startKey 存它）。
    /// 例：每月 1 日、提前到星期五、今天 10/30（五）：11/1（日）那期提前到今天 → 回 11/1（今天剛好是那一期：表單問「這期呢？」，註記的 key 是「2026-11-01」）。
    /// 每兩週照每週找（那個星期幾的下一個）；表單選〔下週那個星期幾〕再加 7 天
    static func firstScheduled(cycle: WealthTransferCycle, day: Int, short: String?, weekday: Int, month: Int = 1,
                               holiday: WealthTransferHoliday, onOrAfter from: Date) -> Date? {
        let d0 = WealthCal.day(from)
        var probe = WealthCal.addDays(-3, to: d0)
        for _ in 0..<6 {
            guard let c = firstDate(cycle: cycle, day: day, short: short, weekday: weekday, month: month,
                                    onOrAfter: probe) else { return nil }
            if shifted(c, holiday: holiday) >= d0 { return c }
            probe = WealthCal.addDays(1, to: c)
        }
        return nil
    }
}

// MARK: - 字

extension WealthTransferText {
    /// 星期六、日往前挪到星期五（不是六日＝那天）
    static func prevWeekday(_ d: Date) -> Date {
        var x = WealthCal.day(d)
        var n = 0
        while isWeekend(x) && n < 3 {
            x = WealthCal.addDays(-1, to: x)
            n += 1
        }
        return x
    }

    /// 規則卡、規則頁、④ 那一列第二行：「遇六日順延」「遇六日提前」；照當天＝nil
    static func holidayText(_ r: WealthTransferRule) -> String? {
        switch r.holidayKind {
        case .onDay: return nil
        case .next: return "遇六日順延"
        case .prev: return "遇六日提前"
        }
    }

    /// 表單「遇六日」三顆的字
    static func holidayLabel(_ h: WealthTransferHoliday) -> String {
        switch h {
        case .onDay: return "照當天"
        case .next: return "順延到星期一"
        case .prev: return "提前到星期五"
        }
    }

    /// 表單「遇六日」那一列下面的小字（judge §4.2；第 10 題：不內建國定假日）
    static let holidayFooter = "台新、國泰世華、LINE Bank 現在都是照當天；換匯多半順延。只看星期六、日，國定假日那一期銀行挪了，點那一期改日子。"

    /// 同一個帳戶兩格互換那兩列（明細、接下來、對存摺「這天還有」；同單次換匯 classify 的字）
    static let exchangeOutTitle = "換匯（換出）"
    static let exchangeInTitle = "換匯（換入）"

    /// 幣別的名字：台幣「台幣」、外幣照代碼（「USD」「美金」，跟設定裡打的一樣）
    static func codeName(_ code: String) -> String {
        FinanceRates.isNTD(code) ? "台幣" : code
    }

    /// 規則沒取名字時的標題：「薪轉 → 存錢」；同一個帳戶兩格互換「存錢 台幣 → USD」
    static func pairTitle(fromName: String, toName: String, fromCode: String, toCode: String,
                          sameAccount: Bool) -> String {
        if sameAccount {
            return fromName + " " + codeName(fromCode) + " → " + codeName(toCode)
        }
        return fromName + " → " + toName
    }

    /// 兩邊金額：同幣別「20,000」（money＝「NT$20,000」）；換匯「9,600 → US$300.00」（money＝「NT$9,600 → US$300.00」）；
    /// approx＝前面加「約 」（未來的換匯那一期）。遮住由呼叫端換成 ••••
    static func pair(_ amount: Double, code: String, to toAmount: Double, toCode: String, money: Bool = false,
                     approx: Bool = false) -> String {
        let a: String = money ? WealthFormat.money(amount, code: code) : WealthFormat.plain(amount, code: code)
        let lead: String = approx ? "約 " : ""
        guard WealthFacts.norm(code) != WealthFacts.norm(toCode) else { return lead + a }
        let b: String = money ? WealthFormat.money(toAmount, code: toCode) : WealthFormat.plain(toAmount, code: toCode)
        return lead + a + " → " + b
    }

    /// 一期兩邊的字（規則頁每一列、一期小表單的頭）：WealthTransferPeriod 的 amount／toAmount、isApprox
    static func pair(_ p: WealthTransferPeriod, money: Bool = false) -> String {
        pair(p.amount, code: p.fromCode, to: p.toAmount, toCode: p.toCode, money: money, approx: p.isApprox)
    }
}

// MARK: - 換匯的金額（表單）

enum WealthTransferExchange {
    /// 段裡存的幣別：台幣＝nil（v1a 的寫法）、外幣照代碼
    static func storedCode(_ code: String) -> String? {
        FinanceRates.isNTD(code) ? nil : code
    }

    /// 表單「對方收到多少」預設：剛好一邊是台幣、設定裡查得到匯率＝照現在的匯率換（台幣到元、外幣到 0.01；存了之後不跟著匯率）；
    /// 同幣別＝amount；兩邊都是外幣、查不到匯率＝nil（judge §5「兩邊都外幣：兩邊金額都你填」）。
    /// 例：台幣 9,600 → 美金、匯率 32.0 → 300.00
    static func defaultToAmount(_ amount: Double, from fromCode: String, to toCode: String,
                                rates: FinanceRates) -> Double? {
        let f = WealthFacts.norm(fromCode)
        let t = WealthFacts.norm(toCode)
        if f == t { return amount }
        guard f == "NT$" || t == "NT$",
              let r = WealthFacts.defaultTransferRate(from: f, to: t, rates: rates) else { return nil }
        return WealthFacts.transferAmount(amount, from: f, to: t, rate: r, rates: rates)
    }

    /// 這兩個數隱含的匯率（1 外幣＝幾台幣；剛好一邊是台幣、兩個數都 > 0 才有）：表單、一期小表單的小字「等於 1 USD＝32.0」
    static func impliedRate(_ amount: Double, code: String, to toAmount: Double, toCode: String) -> Double? {
        let f = WealthFacts.norm(code)
        let t = WealthFacts.norm(toCode)
        guard f != t, amount > 0.004, toAmount > 0.004 else { return nil }
        if f == "NT$" { return amount / toAmount }
        if t == "NT$" { return toAmount / amount }
        return nil
    }

    /// 「等於 1 USD＝32.0」（查不到＝nil）
    static func rateLine(_ amount: Double, code: String, to toAmount: Double, toCode: String) -> String? {
        guard let r = impliedRate(amount, code: code, to: toAmount, toCode: toCode) else { return nil }
        let foreign: String = FinanceRates.isNTD(code) ? toCode : code
        return "等於 1 " + foreign + "＝" + WealthFormat.rate(r)
    }
}

// MARK: - 規則頁「改週期的歷史」（judge §4.4：「2027/1/8 起改成每月 8 日（以前每月 6 日）」，以前那條的期照樣列在「以前的」）

/// 一條規則改週期、改日子〔下一期起〕接上來的前後（previousId；LifeStore.splitTransferRule 接的）
struct WealthTransferHistory {
    /// 頭下面的灰字（新到舊）：「2027/1/8 起改成每月 8 日（以前每月 6 日）」；改了兩次就兩行
    let lines: [String]
    /// 接上來的以前那幾條（近到遠；previousId 一路往前，最多 maxDepth 條、繞圈的停下）
    let predecessors: [WealthFacts.TransferRule]
    /// 這條是被接的舊那條時：接下去的新那條（規則頁〔看新的那條〕）＋那一行「2027/1/8 起改成每月 8 日（新的那條）」；沒有＝nil
    let successor: WealthFacts.TransferRule?
    let successorLine: String?

    /// 往前最多看幾條
    static let maxDepth = 12
}

extension WealthFacts {
    /// [v25.583] 那一條改週期的歷史（規則頁叫；找不到＝空的）。字的日子照年份（今年「1/8」、不是今年「2027/1/8」）
    func transferHistory(_ id: UUID) -> WealthTransferHistory {
        guard let t = transferRule(id) else {
            return WealthTransferHistory(lines: [], predecessors: [], successor: nil, successorLine: nil)
        }
        var lines: [String] = []
        var chain: [TransferRule] = []
        var seen: Set<UUID> = [t.id]
        var cur: TransferRule = t
        while chain.count < WealthTransferHistory.maxDepth, let pid = cur.rule.previousId, !seen.contains(pid),
              let prev = transferRule(pid) {
            if let first = cur.firstDay {
                lines.append(WealthTransferText.dayText(first, today: today) + " 起改成" + cur.cycleText
                             + "（以前" + prev.cycleText + "）")
            }
            chain.append(prev)
            seen.insert(pid)
            cur = prev
        }
        // 接下去的新那條：previousId 指著這條、沒刪掉的（好幾條取最早建立的）
        let next: TransferRule? = transferRules.first { $0.rule.previousId == id && $0.id != id }
        var nextLine: String? = nil
        if let n = next, let first = n.firstDay {
            nextLine = WealthTransferText.dayText(first, today: today) + " 起改成" + n.cycleText + "（新的那條）"
        }
        return WealthTransferHistory(lines: lines, predecessors: chain, successor: next, successorLine: nextLine)
    }

    /// [v25.583] 接上來的以前那幾條、今天（含）以前的期（規則頁「以前的」照樣列；新到舊；每一期帶著自己那條的 ruleId，點了開那一條的那一期）。
    /// 含這期不轉、沒轉成、暫停的（同規則頁）
    func transferPredecessorPeriods(_ id: UUID) -> [WealthTransferPeriod] {
        let h = transferHistory(id)
        var out: [WealthTransferPeriod] = []
        for p in h.predecessors {
            let list = WealthTransferSchedule.periods(p.rule, through: today, today: today)
            out.append(contentsOf: list.filter { $0.day <= today || $0.original <= today })
        }
        return out.sorted { $0.day > $1.day }
    }
}
