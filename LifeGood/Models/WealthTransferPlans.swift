import Foundation

// MARK: - [v25.577] 定期轉帳 v1b 好用（transfer/judge.md §3.1-3、§3.6、§4.1、§4.2、§4.6、§4.7、§4.8；transfer/build/v1b/brief.md §2；
// sim_v1b.py 照這裡一行一行寫過、跑過）
//
// v1a（WealthTransfers.swift）定下來的資料**一個欄位都不加**：v1a 的 iPhone 讀到不認得的欄位、再存回去會把它丟掉（v1a 已知限制 3）。
// v1b 要記的東西全部用 v1a 就認得、會原樣留著的欄位：
// • 改金額、改帳戶「從哪一期起」＝多段 segments（v1a 就照多段讀：segment(at:)）；
// • 帳戶收起來又打開〔接著轉〕＝拿掉 endKey、收起來那段加一段金額 0（暫停）、下一期起照原本那段（還是 segments）；
// • 改週期或日子「從哪天起」＝舊的那條結束（endKey）、新的一條接上（previousId，v1a 就有這欄）；
// • 新手邀請〔不用了〕＝WealthTransferBook.inviteDismissed（v1a 就有）。
// 這個檔只放算法與字（純函式；畫面、LifeStore、WealthFacts 叫），不碰存檔。
// [v25.583] v4（transfer/build/v4/brief.md §2）：〔改金額或帳戶〕多改幣別、對方收到多少（換匯：toAmount 照你填的，不跟匯率；同幣別＝nil）；
// 「下一期」「選一期」「從哪天起照新的日子」照遇六日挪過的那天比；每年的往後多看幾年；表單提示看遇六日；單次轉帳跟某一期重複只看台幣對台幣。

// MARK: - 從哪一期起改（judge §3.1-3）

/// 〔改金額或帳戶〕要改的欄位（nil＝沒改）
struct WealthTransferSegmentChange: Equatable {
    var fromId: UUID? = nil
    var toId: UUID? = nil
    var amount: Double? = nil
    /// [v25.583] 換了轉出、轉入幣別（兩個都填，"NT$" 或外幣代碼）；nil＝沒改
    var codes: WealthTransferCodes? = nil
    /// [v25.583] 對方收到多少（換匯）：改了金額、幣別或這個數時照這個寫；nil＝換匯的照留原本的、同幣別的拿掉
    var toAmount: Double? = nil

    var isEmpty: Bool { fromId == nil && toId == nil && amount == nil && codes == nil && toAmount == nil }
}

/// [v25.583] 一條規則（一段）的兩個幣別
struct WealthTransferCodes: Equatable {
    var from: String
    var to: String
}

extension WealthTransferRule {
    /// 從 key 那一期（含）起改：那一期插一段（那一期已經有一段就改那一段），內容抄「那一期原本那段」再改你動的欄位；
    /// **那一期以後的每一段，同一個欄位一起改**（先排「12/4 起暫停、12/25 恢復」再改「11/13 起從國泰世華轉」，12/25 以後也是國泰世華）；
    /// 改金額時，後面暫停（0）的段照舊是 0。key ""＝〔全部都改〕。改完把「跟前一段一模一樣」的段併掉（結果不變，段比較少）。
    /// [v25.583] 幣別（codes）跟從、到一樣每一段一起換；金額、幣別、對方收到多少有改的段：換完還是換匯＝toAmount 照 c.toAmount（沒給＝照留），
    /// 同幣別＝toAmount 拿掉（v1b 原本「改金額＝toAmount 拿掉」就是同幣別這一種）
    func changed(from key: String, _ c: WealthTransferSegmentChange) -> WealthTransferRule {
        guard !c.isEmpty else { return self }
        var segs: [WealthTransferSegment] = sortedSegments
        var cur: WealthTransferSegment = segment(at: key) ?? segs.last ?? WealthTransferSegment()
        cur.fromKey = key
        segs.removeAll { ($0.fromKey ?? "") == key }
        segs.append(cur)
        segs.sort { ($0.fromKey ?? "") < ($1.fromKey ?? "") }
        let money: Bool = c.amount != nil || c.codes != nil || c.toAmount != nil
        for i in segs.indices where (segs[i].fromKey ?? "") >= key {
            let isCur: Bool = (segs[i].fromKey ?? "") == key
            if let f = c.fromId { segs[i].fromId = f }
            if let t = c.toId { segs[i].toId = t }
            if let cc = c.codes {
                segs[i].fromCode = WealthTransferExchange.storedCode(cc.from)
                segs[i].toCode = WealthTransferExchange.storedCode(cc.to)
            }
            guard money else { continue }
            let paused: Bool = (segs[i].amount ?? 0) <= 0.004
            guard isCur || !paused else {
                segs[i].toAmount = nil
                continue
            }
            if let v = c.amount { segs[i].amount = v }
            let exchange: Bool = WealthFacts.norm(segs[i].fromCode ?? "NT$") != WealthFacts.norm(segs[i].toCode ?? "NT$")
            if !exchange {
                segs[i].toAmount = nil
            } else if let ta = c.toAmount {
                segs[i].toAmount = ta
            }
        }
        var out = self
        out.segments = Self.compacted(segs)
        return out
    }

    /// 跟前一段一模一樣（從、到、幣別、金額都一樣）的段拿掉；第一段一定留著
    static func compacted(_ segs: [WealthTransferSegment]) -> [WealthTransferSegment] {
        var out: [WealthTransferSegment] = []
        for s in segs {
            if let last = out.last, last.fromId == s.fromId, last.fromCode == s.fromCode, last.toId == s.toId,
               last.toCode == s.toCode, last.amount == s.amount, last.toAmount == s.toAmount {
                continue
            }
            out.append(s)
        }
        return out
    }

    /// 要確認〔接著轉〕（帳戶收起來時結束、又打開了）：拿掉最後一期與結束的原因；原本最後一期之後、明天以前的期記成暫停（加一段金額 0），
    /// 下一期（明天起第一期）起照「那一期原本那段」接著轉；那段裡改過金額或日子的註記記成這期不轉（不然註記的金額會讓那期算進去）。
    /// 沒有最後一期、明天起 400 天內找不到下一期＝nil。銀行那邊原本設的結束日收起來時已經蓋掉了：接著轉之後沒有結束日（已知限制）
    func resumed(today: Date, now: Date) -> WealthTransferRule? {
        guard let ek = endKey else { return nil }
        var opened = self
        opened.endKey = nil
        opened.endedBy = nil
        let t = WealthCal.day(today)
        let tomorrow = WealthCal.addDays(1, to: t)
        let list: [Date] = WealthTransferSchedule.originalDates(opened, through: WealthCal.addDays(400, to: t))
        guard let b = list.first(where: { $0 >= tomorrow }) else { return nil }
        let kb = WealthTransferSchedule.key(of: b)
        if let a = list.first(where: { WealthTransferSchedule.key(of: $0) > ek }), a < b {
            let ka = WealthTransferSchedule.key(of: a)
            let atA: WealthTransferSegment? = segment(at: ka)
            let atB: WealthTransferSegment? = segment(at: kb)
            var segs: [WealthTransferSegment] = sortedSegments.filter { s in
                let k = s.fromKey ?? ""
                return !(k >= ka && k < kb)
            }
            if var pause = atA ?? atB {
                pause.fromKey = ka
                pause.amount = 0
                pause.toAmount = nil
                segs.append(pause)
            }
            if !segs.contains(where: { ($0.fromKey ?? "") == kb }), var resume = atB {
                resume.fromKey = kb
                segs.append(resume)
            }
            opened.segments = segs.sorted { ($0.fromKey ?? "") < ($1.fromKey ?? "") }
            var notes: [String: WealthTransferNote] = opened.notes ?? [:]
            for k in notes.keys.sorted() where k >= ka && k < kb {
                guard var n = notes[k], n.amount != nil || n.dayKey != nil else { continue }
                n.status = WealthTransferStatus.skip.rawValue
                n.at = now
                n.updatedAt = now
                notes[k] = n
            }
            opened.notes = notes.isEmpty ? nil : notes
        }
        return opened
    }
}

/// 〔改金額或帳戶〕〔改週期或日子〕存檔時問的那幾個選項要的日子（規則頁、表單都叫）
enum WealthTransferPlan {
    /// 〔下一期起〕：今天以後（不含今天）第一期原本的日子（暫停、這期不轉的也算一期）；沒有＝nil。
    /// [v25.583] 照遇六日挪過的那天比（提前到星期五、今天就轉的那期不算「下一期」）；每年的往後看 3 年多
    static func nextKey(_ r: WealthTransferRule, today: Date) -> String? {
        let t = WealthCal.day(today)
        let h = r.holidayKind
        let list = WealthTransferSchedule.originalDates(r, through: WealthCal.addDays(WealthTransferSchedule.lookAheadDays(r.cycleKind), to: t))
        return list.first(where: { WealthTransferSchedule.shifted($0, holiday: h) > t }).map { WealthTransferSchedule.key(of: $0) }
    }

    /// 〔選一期…〕可以選的期：今天（含）以前最近 24 期＋以後 12 期（原本的日子，舊到新）。[v25.583] 以前／以後照挪過的那天分；每年的往後看 3 年多
    static func pickDates(_ r: WealthTransferRule, today: Date) -> [Date] {
        let t = WealthCal.day(today)
        let h = r.holidayKind
        let list = WealthTransferSchedule.originalDates(r, through: WealthCal.addDays(WealthTransferSchedule.lookAheadDays(r.cycleKind), to: t))
        let past: [Date] = list.filter { WealthTransferSchedule.shifted($0, holiday: h) <= t }
        let future: [Date] = list.filter { WealthTransferSchedule.shifted($0, holiday: h) > t }
        return Array(past.suffix(24)) + Array(future.prefix(12))
    }

    /// 〔全部都改〕那行灰字的「以前的 2 期」：今天（含）以前算進去的期數
    static func pastCount(_ r: WealthTransferRule, today: Date) -> Int {
        let t = WealthCal.day(today)
        return WealthTransferSchedule.periods(r, through: t, today: t).filter { $0.counts && $0.day <= t }.count
    }

    /// 改週期或日子「從哪天起照新的日子」：effective＝從哪天起（〔下一期起〕＝明天；〔選一天…〕＝選的那天，不早於明天）。
    /// 新的一條的第一期＝新的日子 effective（含）以後第一期；算不出來＝nil。
    /// [v25.583] 每年多 month；遇六日照新的那條（實際那天在 effective（含）以後的第一期，回原本的日子）
    static func splitStart(cycle: WealthTransferCycle, day: Int, short: String?, weekday: Int, month: Int = 1,
                           holiday: WealthTransferHoliday = .onDay, from effective: Date) -> Date? {
        WealthTransferSchedule.firstScheduled(cycle: cycle, day: day, short: short, weekday: weekday, month: month,
                                              holiday: holiday, onOrAfter: WealthCal.day(effective))
    }

    /// 改週期或日子：舊的那條最後一期＝effective 前一天（含）以前最後一期（effective 以後的舊日子都不轉了：每月 6 日 → 8 日、
    /// 12/23 改，舊的停在 12/6、新的從 2027/1/8 起，1 月不會 6 日、8 日各一筆）；一期都沒有＝nil（LifeStore 記成一期都不算）
    static func splitLastKey(_ old: WealthTransferRule, from effective: Date) -> String? {
        WealthTransferSchedule.lastOriginal(old, onOrBefore: WealthCal.addDays(-1, to: WealthCal.day(effective)))
            .map { WealthTransferSchedule.key(of: $0) }
    }
}

// MARK: - 帶好欄位打開新增表單（要確認〔轉帳過去〕小表單的〔改成每月定期轉帳〕；judge §4.1、sim R2-11）

/// 新增表單帶好的欄位（WealthTransferRuleForm(preset:)）
struct WealthTransferPreset: Identifiable, Equatable {
    let id = UUID()
    var fromId: UUID? = nil
    var toId: UUID? = nil
    var amount: Double? = nil
    var cycle: WealthTransferCycle = .monthly
    /// 每月幾日 1～31（31＝每月最後一天）
    var day: Int? = nil
    var short: String? = nil
    /// 〔轉帳過去〕小表單最下面那一行「『房貸』每月 10 日都要從這裡扣：」
    var offer: String? = nil
    /// [v25.581] 要確認 v3 帶來的記帳那一筆固定支出／收入：存檔時「是同一筆嗎？」一定問它（你在表單改了金額、日子也照問；
    /// WealthTransferMatcher.forcedExpense／forcedIncome）。放最後、有預設：既有的呼叫不用改
    var matchExpenseId: UUID? = nil
    var matchIncomeId: UUID? = nil
    /// [v25.581] 新增表單最上面一行（「照記帳的『轉玉山存錢』帶好了；存檔時會問記帳那筆怎麼辦」）；nil＝不出現
    var lead: String? = nil
}

// MARK: - 字

extension WealthTransferText {
    /// 「12/5」；不是今年「2027/5/8」
    static func dayText(_ d: Date, today: Date) -> String {
        let cal = WealthCal.calendar
        if cal.component(.year, from: d) == cal.component(.year, from: today) { return WealthFormat.monthDay(d) }
        return WealthFormat.ymd(d)
    }

    /// 「+20,000」「−20,000」（減號 U+2212，同 coverLine）
    static func signed(_ v: Double) -> String {
        let body = WealthFormat.grouped(Swift.abs(v).rounded(), decimals: 0)
        return (v < 0 ? "−" : "+") + body
    }

    /// 星期六、星期日
    static func isWeekend(_ d: Date) -> Bool {
        let w = WealthCal.calendar.component(.weekday, from: d)
        return w == 1 || w == 7
    }

    /// 遇六日順延到星期一（不是六日＝那天）
    static func nextWeekday(_ d: Date) -> Date {
        var x = WealthCal.day(d)
        var n = 0
        while isWeekend(x) && n < 3 {
            x = WealthCal.addDays(1, to: x)
            n += 1
        }
        return x
    }
}

// MARK: - 表單提示（judge §4.2「提示，有才出現」、§5 月薪遇六日／順延撞扣款日；sim R2-5）

/// 一行提示（gray＝第 2 輪多的兩種灰字：只是提示、不改數字）
struct WealthTransferHint: Identifiable, Equatable {
    let id: String
    let text: String
    let gray: Bool
}

enum WealthTransferHints {
    /// 「轉進帳戶這期後幾天內有扣款」算數的天數
    static let debitWindow = 3
    /// 看接下來幾期
    static let lookPeriods = 12

    /// 還沒存的那一條（每月的；每週的不給提示）的提示：
    /// ① 轉出帳戶同一天有入帳「月薪也是 5 號：銀行可能先轉、月薪還沒進來，建議設 6 號以後。」
    /// ② 轉進帳戶這期後 0～3 天有扣款「房貸扣款 每月 10 日扣房貸：設 8 日剛好，留兩天。」（1 天「只留一天」、同一天「同一天轉進又扣款…」）
    /// ③ 灰字：轉出帳戶的入帳接下來 12 期遇六日、這條在它後面 1～2 天「12/5 月薪是星期六：公司要是延到 12/7（一）才發，12/6 那筆可能轉不過去」
    /// ④ 灰字：這條接下來 12 期遇六日、順延到星期一會碰到（或晚過）轉進帳戶的扣款「2027/5/8 是星期六：銀行要是順延到 5/10（一），會跟房貸同一天」
    /// book：帳本（改帳戶的歷史 links）；toName：轉進帳戶的名字
    static func make(rule r: WealthTransferRule, toName: String, expenses: [Expense], incomes: [Income],
                     book: WealthBook, today: Date) -> [WealthTransferHint] {
        guard r.cycleKind == .monthly, let sk = r.startKey, let first = WealthTransferSchedule.date(fromKey: sk),
              let seg = r.segment(at: sk), let from = seg.fromId, let to = seg.toId else { return [] }
        let cal = WealthCal.calendar
        let horizon = WealthCal.addDays(400, to: first)
        let periods: [Date] = Array(WealthTransferSchedule.originalDates(r, through: horizon).prefix(lookPeriods))
        guard !periods.isEmpty else { return [] }
        let early = WealthCal.addDays(-debitWindow, to: first)
        let firstKey = WealthCal.dayKey(first)
        let ruleDay = cal.component(.day, from: first)
        // [v25.583] 遇六日：第一期實際那天（①② 照它比）；順延的那條 ④ 不是「銀行要是順延」而是一定會挪
        let holiday: WealthTransferHoliday = r.holidayKind
        let firstDay: Date = WealthTransferSchedule.shifted(first, holiday: holiday)

        // 轉出帳戶的每月入帳（照第一期那天的帳戶）
        var incomeDates: [(date: Date, title: String)] = []
        for inc in incomes where inc.period == .monthly {
            let payer = WealthCardCycle.payer(statementKey: firstKey, linked: inc.linkedBankMilestoneId,
                                              history: book.links(inc.id))
            guard payer == from else { continue }
            for p in WealthSchedule.incomePeriods(inc, through: horizon) {
                let d = WealthCal.day(p.date)
                if d >= early { incomeDates.append((date: d, title: inc.title)) }
            }
        }
        incomeDates.sort { $0.date < $1.date }
        // 轉進帳戶的每月扣款（直接扣這個帳戶的每月固定支出；照第一期那天的帳戶）
        let excluded = Set(book.excludedExpenses ?? [])
        var debitDates: [(date: Date, title: String)] = []
        for e in expenses where e.expenseType == .fixed && e.recurrence == .monthly {
            guard !excluded.contains(e.id.uuidString),
                  WealthFacts.recurringTarget(e, at: first, history: book.links(e.id)) == to else { continue }
            for p in WealthSchedule.fixedPeriods(e, through: horizon) {
                let d = WealthCal.day(p.date)
                if d >= early { debitDates.append((date: d, title: e.title)) }
            }
        }
        debitDates.sort { $0.date < $1.date }

        var out: [WealthTransferHint] = []
        // ① 同一天有入帳
        if let inc = incomeDates.first(where: { $0.date == firstDay }) {
            let suggest: String = ruleDay < 28 ? "建議設 \(ruleDay + 1) 號以後" : "建議晚一天以上"
            out.append(WealthTransferHint(id: "same-income",
                                          text: "\(inc.title)也是 \(ruleDay) 號：銀行可能先轉、\(inc.title)還沒進來，\(suggest)。",
                                          gray: false))
        }
        // ② 轉進帳戶這期後 0～3 天有扣款（照第一期）
        if let deb = debitDates.first(where: { d in
            let n = WealthCal.days(from: firstDay, to: d.date)
            return n >= 0 && n <= debitWindow
        }) {
            let gap = WealthCal.days(from: firstDay, to: deb.date)
            let eDay = cal.component(.day, from: deb.date)
            let text: String
            switch gap {
            case 0:
                text = "同一天轉進又扣款，銀行先跑哪個說不準，建議提前一天以上。"
            case 1:
                text = "\(toName) 每月 \(eDay) 日扣\(deb.title)：設 \(ruleDay) 日只留一天，建議再提前一天。"
            default:
                let word: String = gap == 2 ? "兩" : "三"
                text = "\(toName) 每月 \(eDay) 日扣\(deb.title)：設 \(ruleDay) 日剛好，留\(word)天。"
            }
            out.append(WealthTransferHint(id: "debit", text: text, gray: false))
        }
        // ③ 灰字：入帳遇六日、這條在它後面 1～2 天（延到星期一才發的話，這期轉的時候錢還沒進來）
        hint3: for inc in incomeDates where WealthTransferText.isWeekend(inc.date) {
            let monday = WealthTransferText.nextWeekday(inc.date)
            for x in periods {
                let n = WealthCal.days(from: inc.date, to: x)
                guard n >= 1 && n <= 2 && x < monday else { continue }
                let w = WealthTransferText.weekdayName(inc.date)
                let text = WealthTransferText.dayText(inc.date, today: today) + " \(inc.title)是星期\(w)：公司要是延到 "
                    + WealthTransferText.dayText(monday, today: today) + "（一）才發，"
                    + WealthTransferText.dayText(x, today: today) + " 那筆可能轉不過去"
                out.append(WealthTransferHint(id: "income-weekend", text: text, gray: true))
                break hint3
            }
        }
        // ④ 灰字：這條遇六日、順延到星期一會碰到（或晚過）轉進帳戶的扣款。
        // [v25.583] 選了〔順延到星期一〕＝一定會挪：橘的提示「…順延到 5/10（一），會跟房貸同一天」；〔提前到星期五〕不會晚過扣款，不提示
        hint4: for x in periods where WealthTransferText.isWeekend(x) && holiday != .prev {
            let shifted = WealthTransferText.nextWeekday(x)
            for deb in debitDates where deb.date > x && deb.date <= shifted {
                let w = WealthTransferText.weekdayName(x)
                let tail: String = deb.date == shifted
                    ? "會跟\(deb.title)同一天"
                    : "會晚過\(deb.title)（\(WealthFormat.monthDay(deb.date))）"
                let lead: String = holiday == .next ? " 是星期\(w)：順延到 " : " 是星期\(w)：銀行要是順延到 "
                let text = WealthTransferText.dayText(x, today: today) + lead
                    + WealthFormat.monthDayWeek(shifted) + "，" + tail
                out.append(WealthTransferHint(id: "shift-debit", text: text, gray: holiday != .next))
                break hint4
            }
        }
        return out
    }
}

// MARK: - 最下面的預覽「11/8 轉完，薪轉約剩 61,400 ✓」（judge §4.2；sim §6）

/// 預覽一行（warn＝橘字：轉完會不夠）
struct WealthTransferPreviewLine: Identifiable, Equatable {
    let id: String
    let text: String
    let warn: Bool
}

enum WealthTransferPreview {
    /// 轉進帳戶這一期之後幾天內的扣款要講
    static let debitWindow = 3

    /// before：現在的一套數字；after：帶著這條（還沒存的、或改過的）重算的（LifeStore.wealthFactsPreview）。
    /// ① 轉出帳戶：這條 30 天內有一期扣完會是負的＝橘字「11/8 轉完，薪轉會是 −1,400，銀行可能轉不過去」（自己轉的「轉之前要先補錢」）；
    ///    不然第一期「11/8 轉完，薪轉約剩 61,400 ✓」。
    /// ② 轉進帳戶：原本 30 天內有不夠扣、在第一期（含）以後：「房貸扣款 11/10 扣完房貸剩 1,200 ✓（原本差 23,800）」（還是不夠＝橘字「還差」）；
    ///    沒有的話第一期後 3 天內有扣款「房貸扣款 11/10 扣完房貸剩 1,200 ✓」。都沒有＝不寫。遮住：數字寫 ••••
    static func lines(rule r: WealthTransferRule, before: WealthFacts, after: WealthFacts,
                      masked: Bool) -> [WealthTransferPreviewLine] {
        let today = after.today
        let list = WealthTransferSchedule.periods(r, through: WealthCal.addDays(400, to: today), today: today)
        guard let p = list.first(where: { $0.counts && $0.day >= today }), let fromId = p.fromId,
              let toId = p.toId else { return [] }
        func num(_ v: Double) -> String { masked ? "••••" : WealthFormat.grouped(v.rounded(), decimals: 0) }
        // [v25.583 驗證修] 轉出那一邊照那一格的幣別寫（v4 起可以從外幣那格轉出：美金戶「約剩 US$1,500.00」，不寫成「約剩 1,500」）；
        // 台幣跟 num 一模一樣（WealthFormat.plain 的台幣＝grouped(rounded)）
        func numIn(_ v: Double, _ code: String) -> String { masked ? "••••" : WealthFormat.plain(v, code: code) }
        let fromAcc = after.account(fromId)
        let toAcc = after.account(toId)
        let fromName: String = fromAcc?.name ?? "轉出的帳戶"
        let toName: String = toAcc?.name ?? "轉進的帳戶"
        var out: [WealthTransferPreviewLine] = []

        // ① 轉出帳戶（30 天內不夠扣的那一筆；第一期在 30 天以後、轉完是負的也一樣講）
        let tail: String = r.isManual ? "轉之前要先補錢" : "銀行可能轉不過去"
        if let s = fromAcc?.shortages.first(where: { $0.transferRuleId == r.id }) {
            let text = WealthTransferText.dayText(s.date, today: today) + " 轉完，" + fromName + "會是 −"
                + numIn(s.short, s.code) + "，" + tail
            out.append(WealthTransferPreviewLine(id: "from", text: text, warn: true))
        } else if let a = fromAcc {
            let rowId = "tr-" + r.id.uuidString + "-" + p.key + "-o"
            if let row = (a.upcoming + a.ledger).first(where: { $0.id == rowId }) {
                let head = WealthTransferText.dayText(p.day, today: today) + " 轉完，" + fromName
                if row.balanceAfter < -0.5 {
                    out.append(WealthTransferPreviewLine(id: "from", text: head + "會是 −" + numIn(-row.balanceAfter, row.code) + "，"
                                                         + tail, warn: true))
                } else {
                    out.append(WealthTransferPreviewLine(id: "from", text: head + "約剩 " + numIn(row.balanceAfter, row.code) + " ✓",
                                                         warn: false))
                }
            }
        }

        // ② 轉進帳戶
        let firstDay = WealthCal.day(p.day)
        if let a = toAcc,
           let bs = before.account(toId)?.shortages.first(where: { $0.code == "NT$" && WealthCal.day($0.date) >= firstDay }),
           let row = a.upcoming.first(where: { $0.id == bs.rowId }) {
            let head = toName + " " + WealthTransferText.dayText(row.date, today: today) + " 扣完" + row.title
            let was = "（原本差 " + num(bs.short) + "）"
            if row.balanceAfter >= -0.5 {
                out.append(WealthTransferPreviewLine(id: "to", text: head + "剩 " + num(row.balanceAfter) + " ✓" + was,
                                                     warn: false))
            } else {
                out.append(WealthTransferPreviewLine(id: "to", text: head + "還差 " + num(-row.balanceAfter) + was,
                                                     warn: true))
            }
        } else if let a = toAcc, let row = a.upcoming.first(where: { x in
            guard x.isOutflow, x.code == "NT$", x.transferRuleId != r.id else { return false }
            let n = WealthCal.days(from: firstDay, to: x.date)
            return n >= 0 && n <= debitWindow
        }) {
            let head = toName + " " + WealthTransferText.dayText(row.date, today: today) + " 扣完" + row.title
            if row.balanceAfter >= -0.5 {
                out.append(WealthTransferPreviewLine(id: "to", text: head + "剩 " + num(row.balanceAfter) + " ✓", warn: false))
            } else {
                out.append(WealthTransferPreviewLine(id: "to", text: head + "會是 −" + num(-row.balanceAfter), warn: true))
            }
        }
        return out
    }
}

// MARK: - 從以前開始算〔更早…〕先算給你看（judge §3.6、§1.4-8；sim §6「從以前開始算」）

struct WealthTransferEarlyImpact: Equatable {
    /// 「從 2026/1/6 起：以前 10 期都會出現在明細；存錢上次對存摺 10/1 → 只有 10/6 那期會算進今天（+20,000）；薪轉 10/23 對過 → 今天的數字不變」
    let text: String
    /// 「其中 8/6、9/6、10/6 你手記過了，會算兩次」；沒有＝nil
    let duplicateText: String?
    /// 今天（含）以前算進去的期數
    let pastCount: Int
    /// 〔改成從下一期起〕的那一期（今天以後第一期）；沒有＝nil
    let nextDay: Date?
}

/// 存一筆單次轉帳時「這筆跟定期轉帳『薪轉 → 存錢』11/6 那期一樣，App 已經算進去了」（judge §4.6；sim §7）
struct WealthTransferDuplicate: Equatable {
    let ruleId: UUID
    let key: String
    let day: Date
    let question: String
}

extension WealthFacts {
    /// 從以前開始算：這條（還沒存的，第一期在今天以前）今天（含）以前的期，照每個帳戶**最近一次對存摺（含開戶那筆）**算會不會動到今天的數字：
    /// 對存摺那天（含）以前的被對存摺蓋掉、之後的才算進今天。fromDeposits：轉出帳戶的存提款紀錄（找「你手記過」的單次轉帳：
    /// 同兩個帳戶、同金額、前後 3 天內）。今天以前一期都沒有＝nil。遮住：不寫金額
    func transferEarlyImpact(rule r: WealthTransferRule, fromDeposits: [BankDeposit],
                             masked: Bool) -> WealthTransferEarlyImpact? {
        guard let sk = r.startKey, let start = WealthTransferSchedule.date(fromKey: sk) else { return nil }
        let t = today
        let past: [WealthTransferPeriod] = WealthTransferSchedule.periods(r, through: t, today: t)
            .filter { $0.counts && $0.day <= t }
        guard !past.isEmpty else { return nil }
        let next: Date? = WealthTransferSchedule.next(r, today: t)?.day
        var parts: [String] = ["從 " + WealthFormat.ymd(start) + " 起：以前 \(past.count) 期都會出現在明細"]
        // 轉進那邊先講、再講轉出（樣稿②-2）
        let toId: UUID? = past.first?.toId
        let fromId: UUID? = past.first?.fromId
        // [v25.583 驗證修] 同一個帳戶兩格互換（換匯）：兩格各講一句，名字後面寫哪一格（「存錢 USD 從沒對過存摺…」「存錢台幣 10/1 對過…」）；
        // 以前只講轉進那一格，台幣那格少掉的錢沒講
        let sameAccount: Bool = toId != nil && toId == fromId
        if let id = toId, let line = earlySide(id, out: false, past: past, masked: masked, sideNamed: sameAccount) {
            parts.append(line)
        }
        if let id = fromId, id != toId || sameAccount,
           let line = earlySide(id, out: true, past: past, masked: masked, sideNamed: sameAccount) {
            parts.append(line)
        }
        // 手記過的單次轉帳（[v25.583 驗證修] 只比台幣轉出的期：手記的那筆是台幣）
        var dupDays: [Date] = []
        if let f = fromId, let to = toId {
            for d in fromDeposits where d.isTransfer && d.isWithdrawal && d.counterpartyId == to
                && FinanceRates.isNTD(d.currencyCode) {
                let day = WealthCal.day(d.date)
                let hit = past.contains { p in
                    p.fromId == f && p.fromCode == "NT$" && Swift.abs(p.amount - d.amount) < 0.5
                        && Swift.abs(WealthCal.days(from: p.day, to: day)) <= 3
                }
                if hit && !dupDays.contains(day) { dupDays.append(day) }
            }
        }
        dupDays.sort()
        var dupText: String? = nil
        if !dupDays.isEmpty {
            if dupDays.count <= 4 {
                let list = dupDays.map { WealthTransferText.dayText($0, today: t) }.joined(separator: "、")
                dupText = "其中 " + list + " 你手記過了，會算兩次"
            } else {
                let a = WealthTransferText.dayText(dupDays[0], today: t)
                let b = WealthTransferText.dayText(dupDays[dupDays.count - 1], today: t)
                dupText = "其中 " + a + "～" + b + " 有 \(dupDays.count) 筆你手記過了，會算兩次"
            }
        }
        return WealthTransferEarlyImpact(text: parts.joined(separator: "；"), duplicateText: dupText,
                                         pastCount: past.count, nextDay: next)
    }

    /// 一個帳戶那一句：「存錢上次對存摺 10/1 → 只有 10/6 那期會算進今天（+20,000）」「薪轉 10/23 對過 → 今天的數字不變」
    /// 「零用錢從沒對過存摺 → 10 期都會算進今天（+30,000）」；帳戶找不到＝nil
    /// [v25.583 驗證修] sideNamed：同一個帳戶兩格互換時名字後面寫哪一格（「存錢台幣」「存錢 USD」）；金額照那一格的幣別（外幣「+US$900.00」）
    private func earlySide(_ id: UUID, out: Bool, past: [WealthTransferPeriod], masked: Bool,
                           sideNamed: Bool = false) -> String? {
        guard let a = account(id) else { return nil }
        let t = today
        // [驗證修] 這一邊那個幣別（v1 一律台幣）最近一次對存摺：lastAnchorDate 是任何幣別的，外幣帳戶只對了美金那格
        //（10/15）、台幣那格上次是 8/1 時，台幣 8/6～10/6 那幾期照樣會算進今天（makeAccount 一個幣別一條 running）
        let code: String = past.first(where: { out ? $0.fromId == id : $0.toId == id })
            .map { out ? $0.fromCode : $0.toCode } ?? "NT$"
        let anchor: Date? = a.ledger.first(where: { $0.kind == .anchor && WealthFacts.norm($0.code) == code })
            .map { WealthCal.day($0.date) }
        let hits: [WealthTransferPeriod] = past.filter { p in
            let mine: Bool = out ? p.fromId == id : p.toId == id
            guard mine else { return false }
            guard let x = anchor else { return true }
            let d = WealthCal.day(p.day)
            let late: Bool = out ? p.lateOut : p.lateIn
            return d > x || (d == x && late)
        }
        let total: Double = hits.reduce(0) { $0 + (out ? $1.amount : $1.toAmount) }
        let money: String = masked ? "" : "（" + WealthFacts.earlySigned(out ? -total : total, code: code) + "）"
        // 同一個帳戶兩格：「存錢台幣」「存錢 USD 」（英文代碼後面空一格再接中文）
        let isNTD: Bool = FinanceRates.isNTD(code)
        let name: String = sideNamed ? (isNTD ? a.name + "台幣" : a.name + " " + code + " ") : a.name
        let bare: String = sideNamed ? (isNTD ? a.name + "台幣" : a.name + " " + code) : a.name
        guard let x = anchor else {
            return name + "從沒對過存摺 → \(hits.count) 期都會算進今天" + money
        }
        let when = WealthTransferText.dayText(x, today: t)
        if hits.isEmpty { return bare + " " + when + " 對過 → 今天的數字不變" }
        let mineCount = past.filter { out ? $0.fromId == id : $0.toId == id }.count
        let which: String
        if hits.count == 1 {
            which = WealthTransferText.dayText(hits[0].day, today: t) + " 那期"
        } else if hits.count <= 3 {
            which = hits.map { WealthTransferText.dayText($0.day, today: t) }.joined(separator: "、") + " 那 \(hits.count) 期"
        } else {
            which = WealthTransferText.dayText(hits[0].day, today: t) + "～"
                + WealthTransferText.dayText(hits[hits.count - 1].day, today: t) + " 那 \(hits.count) 期"
        }
        let lead: String = hits.count < mineCount ? "只有 " : ""
        return name + "上次對存摺 " + when + " → " + lead + which + "會算進今天" + money
    }

    /// [v25.583 驗證修] 〔更早…〕那一句的金額：台幣「+20,000」「−9,600」（同 v1b，WealthTransferText.signed）、外幣「+US$900.00」
    private static func earlySigned(_ v: Double, code: String) -> String {
        if FinanceRates.isNTD(code) { return WealthTransferText.signed(v) }
        return (v < 0 ? "−" : "+") + WealthFormat.plain(Swift.abs(v), code: code)
    }

    /// 存一筆單次轉帳（同幣別台幣）時：同兩個帳戶、同金額、前後 3 天內有一期算進去的定期轉帳＝那一期（最近的那一期）；沒有＝nil
    func transferDuplicate(fromId: UUID, toId: UUID, amount: Double, on date: Date) -> WealthTransferDuplicate? {
        let d = WealthCal.day(date)
        var best: (dist: Int, dup: WealthTransferDuplicate)? = nil
        for r in transferBook.live {
            for p in WealthTransferSchedule.periods(r, through: WealthCal.addDays(4, to: d), today: today) where p.counts {
                // [v25.583] 只比台幣對台幣（單次轉帳這一問只問台幣；換匯、外幣的期金額是別的幣別）
                guard p.fromId == fromId, p.toId == toId, p.fromCode == "NT$", p.toCode == "NT$",
                      Swift.abs(p.amount - amount) < 0.5 else { continue }
                let n = Swift.abs(WealthCal.days(from: p.day, to: d))
                guard n <= 3 else { continue }
                if let b = best, b.dist <= n { continue }
                let title: String = transferRule(r.id)?.title ?? "定期轉帳"
                let q = "這筆跟定期轉帳『" + title + "』" + WealthTransferText.dayText(p.day, today: today)
                    + " 那期一樣，App 已經算進去了"
                best = (dist: n, dup: WealthTransferDuplicate(ruleId: r.id, key: p.key, day: p.day, question: q))
            }
        }
        return best?.dup
    }

    /// 要確認 #1〔轉帳過去〕小表單最下面〔改成每月定期轉帳〕：這個帳戶第一筆不夠扣的是**每月**的固定支出（台幣）→ 帶好
    /// 從（月薪入帳的帳戶；就是這個帳戶的話換存摺上台幣最多的另一個活存）、到（這個帳戶）、金額（那一期固定支出）、每月、
    /// 日子＝扣款日前 2 天（扣款日 1、2 號＝每月最後一天）。不是的話 nil
    func monthlyTransferPreset(forShortageOf accountId: UUID, expenses: [Expense]) -> WealthTransferPreset? {
        guard let a = account(accountId), !a.hidden, let s = a.shortage, s.kind == .fixedExpense, s.code == "NT$",
              let eid = s.expenseId, let e = expenses.first(where: { $0.id == eid }),
              e.recurrence == .monthly else { return nil }
        let debitDay = WealthCal.calendar.component(.day, from: s.date)
        let day: Int = debitDay <= 2 ? 31 : debitDay - 2
        var from: UUID? = defaultTransferFromId
        if from == nil || from == accountId { from = transferSourceId(excluding: accountId) }
        return WealthTransferPreset(fromId: from, toId: accountId, amount: s.amount.rounded(), cycle: .monthly,
                                    day: day, short: nil, offer: "『\(e.title)』每月 \(debitDay) 日都要從這裡扣：")
    }

    /// 存摺上台幣最多的另一個活存（沒收起來、不是定存、不是證券戶、有錢）；都沒有＝nil
    func transferSourceId(excluding id: UUID) -> UUID? {
        var best: Account? = nil
        for a in pickerBanks where a.id != id && a.balance("NT$") > 0.5 {
            if let b = best, b.balance("NT$") >= a.balance("NT$") { continue }
            best = a
        }
        return best?.id
    }
}
