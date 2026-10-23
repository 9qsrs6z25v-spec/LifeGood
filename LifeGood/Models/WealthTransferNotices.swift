import Foundation

// MARK: - [v25.579] 定期轉帳 v2 會提醒你（transfer/judge.md §4.5、§4.6〔暫停〕、§4.8 v2、§4.9、§4.10、§5；transfer/build/v2/brief.md §2；
// sim_v2.py 照這裡一行一行寫過、跑過）
//
// v1a（WealthTransfers.swift）定下來的資料**一個欄位都不加**（v1a 已知限制 3：v1a、v1b 的手機讀到不認得的欄位、存回去會丟掉）：
// • 自己轉的〔轉好了〕〔轉了〕＝那一期的註記 status "done"（今天才轉好的另記 dayKey＝今天）；〔還沒〕＝"notYet"
//  （v1a 就認得：算在 max(那天, 明天)，每天往後挪）；〔改到明天〕＝dayKey 明天。
// • 〔暫停〕＝金額 0 的一段（v1a 就照「暫停」不算）、〔恢復〕＝那一期起接回暫停以前那段；暫停裡改過金額的期記成這期不轉（同 v1b〔接著轉〕）。
// • 這條要不要提醒＝rule.remind（v1a 就有這欄、只存不用；nil＝要）。
// • 規則頁〔結束〕記 endedBy "user"（v1a、v1b 不認得的字＝照舊當成你按的；這一版拿它分「你按的結束」跟「銀行那邊設到哪天」）。
// 所以 25.575～25.578 的手機存回去不會丟、數字也照算（只是沒有提醒、沒有〔轉好了〕那幾顆）。
//
// 這個檔只放算法與字（純函式；畫面、LifeStore、WealthFacts、WealthReminders 叫）：
// • 自己轉那一期在哪一步（WealthTransferPeriod.manualPhase）：預計／今天要轉／轉好了／過了日子還沒回答（7 天內問）／當作轉了／還沒轉。
// • 〔暫停〕〔恢復〕的分段（WealthTransferRule.paused／unpaused）、卡上「暫停到 12/24」（pauseInfo）、暫停表單那一句（WealthTransferPlan.pauseSummary）。
// • 要確認 v2 四條（WealthTransferNotices.checks；WealthFacts.makeChecks 叫）：今天要轉〔轉好了〕〔看這一期〕、
//   過了日子「轉了嗎？」〔轉了〕〔還沒…〕、還沒轉掛滿 7 天〔今天轉好了〕〔這期不轉了〕、銀行設的最後一次 14 天內〔已經續設〕〔知道了〕——一列都 ≤ 2 顆。
// • 通知三種（WealthTransferNotices.candidates；WealthReminders.candidates 叫）：自己轉那天 09:00（同一天幾條併一則）、
//   自動轉可能轉不過去前一天 20:00（同一天併一則）、銀行設的最後一次前 14 天 09:00。
//   **字一律不寫帳戶、銀行、金額、對方、名字**（你取的名字可能是「給媽媽」；手錶戴著時通知原樣轉過去）。日子可以寫。
// • 我的行事曆（WealthDates.transferItems；MyCalendarView 叫）：自己轉的每條接下來 2 期（橘）、銀行自動轉每月的接下來 2 期（灰）、每週的不放。
//   **不放進 WealthDates.all／items**：CalendarDayItems（今天小工具 → 手錶今天頁）讀的是那一份，轉帳一個字都不會流過去。

// MARK: - 自己轉那一期在哪一步

/// 自己轉的那一期在哪一步（只在記憶體；規則頁、一期小表單、要確認、通知共用）
enum WealthTransferManualPhase: Equatable {
    /// 日子還沒到（預計）
    case upcoming
    /// 今天要轉（還沒按〔轉好了〕）
    case today
    /// 你按了〔轉好了〕〔轉了〕
    case done
    /// 過了日子、還沒回答（7 天內）：App 先當作轉了，要確認問「轉了嗎？」
    case waiting
    /// 過了日子、還沒回答、超過 7 天：照舊當作轉了（不再問）
    case assumed
    /// 你說〔還沒〕：算在明天（每天往後挪，直到〔轉好了〕或〔這期不轉〕）
    case notYet
}

extension WealthTransferPeriod {
    /// 自己轉的這一期在哪一步（呼叫端先確定這條是自己轉的）；不算進去的（這期不轉、沒轉成、暫停、壞掉）、補轉的＝nil（照 state 畫）
    func manualPhase(today: Date) -> WealthTransferManualPhase? {
        guard counts else { return nil }
        switch status {
        case .done?: return .done
        case .notYet?: return .notYet
        case .redo?: return nil
        default: break
        }
        let t = WealthCal.day(today)
        let d = WealthCal.day(day)
        if d > t { return .upcoming }
        if d == t { return .today }
        let n = WealthCal.days(from: d, to: t)
        return n <= WealthTransferNotices.askDays ? .waiting : .assumed
    }
}

// MARK: - 〔暫停〕〔恢復〕（judge §4.6；sim §5）

/// 卡上「暫停到 12/24」、規則頁〔恢復〕要的（只在記憶體）
struct WealthTransferPauseInfo: Equatable {
    /// 今天以後第一個落在暫停裡的那一期原本的日子
    let start: Date
    /// 恢復的那一期原本的日子；nil＝先不設（一直暫停到你按〔恢復〕，或到最後一期）
    let resume: Date?
    /// 今天以後第一期就在暫停裡（暫停中）；false＝還沒開始（排好的暫停）
    let active: Bool
    /// 「暫停到 12/24」「暫停中」「12/4 起暫停到 12/24」「12/4 起暫停」
    let text: String
}

extension WealthTransferRule {
    /// k（含）以前最後一段金額 > 0 的（暫停以前那段）；沒有＝nil
    func liveSegment(at k: String) -> WealthTransferSegment? {
        var found: WealthTransferSegment? = nil
        for s in sortedSegments where (s.fromKey ?? "") <= k && (s.amount ?? 0) > 0.004 { found = s }
        return found
    }

    /// 〔暫停〕：從 a 那一期（含）起暫停，到 b 那一期（含）恢復；b nil＝〔先不設〕（一直暫停到你按〔恢復〕）。
    /// 那段裡原本的段拿掉、a 插一段金額 0（帳戶照 a 那一期原本那段）；b 插一段「b 那一期原本那段」（暫停以前那段：中間改過帳戶、金額的照帶過去；
    /// b 本來就有一段金額 > 0 的就留它）。暫停裡改過金額的期（註記有金額）記成這期不轉（不然註記的金額會讓那期算進去；同 v1b〔接著轉〕）。
    /// 例：零用錢 12/4 起、12/25 恢復 → 12/4、12/11、12/18 三期不算，12/25 照轉
    func paused(from a: String, until b: String?, now: Date) -> WealthTransferRule {
        func inPause(_ k: String) -> Bool {
            guard k >= a else { return false }
            guard let end = b else { return true }
            return k < end
        }
        var segs: [WealthTransferSegment] = sortedSegments
        let atA: WealthTransferSegment = segment(at: a) ?? segs.last ?? WealthTransferSegment()
        let resumeBase: WealthTransferSegment? = b.flatMap { liveSegment(at: $0) }
        segs.removeAll { inPause($0.fromKey ?? "") }
        var pause = atA
        pause.fromKey = a
        pause.amount = 0
        pause.toAmount = nil
        segs.append(pause)
        if let end = b, var resume = resumeBase {
            resume.fromKey = end
            if let i = segs.firstIndex(where: { ($0.fromKey ?? "") == end }) {
                if (segs[i].amount ?? 0) <= 0.004 { segs[i] = resume }
            } else {
                segs.append(resume)
            }
        }
        segs.sort { ($0.fromKey ?? "") < ($1.fromKey ?? "") }
        var out = self
        out.segments = Self.compacted(segs)
        var ns: [String: WealthTransferNote] = notes ?? [:]
        for k in ns.keys.sorted() where inPause(k) {
            guard var n = ns[k], n.amount != nil else { continue }
            n.status = WealthTransferStatus.skip.rawValue
            n.at = now
            n.updatedAt = now
            ns[k] = n
        }
        out.notes = ns.isEmpty ? nil : ns
        return out
    }

    /// 〔恢復〕：從 k 那一期（含）起照轉——k（含）以後的暫停段（金額 0）都拿掉；k 那一期還落在更早開始的暫停裡，就在 k 插一段
    /// 「暫停以前最後那段」。以前暫停過的期照舊不算（歷史不改）。沒有能接回去的段＝原封不動
    func unpaused(from k: String) -> WealthTransferRule {
        guard let base = liveSegment(at: k) ?? sortedSegments.first(where: { ($0.amount ?? 0) > 0.004 }) else { return self }
        var segs: [WealthTransferSegment] = sortedSegments.filter { s in
            !((s.fromKey ?? "") >= k && (s.amount ?? 0) <= 0.004)
        }
        var cur: WealthTransferSegment? = nil
        for s in segs where (s.fromKey ?? "") <= k { cur = s }
        if let c = cur, (c.amount ?? 0) <= 0.004 {
            var resume = base
            resume.fromKey = k
            segs.removeAll { ($0.fromKey ?? "") == k }
            segs.append(resume)
            segs.sort { ($0.fromKey ?? "") < ($1.fromKey ?? "") }
        }
        var out = self
        out.segments = Self.compacted(segs)
        return out
    }

    /// 卡上第三行、規則頁〔恢復〕：今天以後（不含今天）400 天內有落在暫停裡的期才有。還在跑的才看。
    /// 暫停中（今天以後第一期就在暫停裡）：「暫停到 12/24」（恢復那一期的前一天）／「暫停中」（沒設恢復）；
    /// 還沒開始：「12/4 起暫停到 12/24」／「12/4 起暫停」
    func pauseInfo(today: Date) -> WealthTransferPauseInfo? {
        let t = WealthCal.day(today)
        guard isRunning(todayKey: WealthCal.dayKey(t)) else { return nil }
        let list: [WealthTransferPeriod] = WealthTransferSchedule.periods(self, through: WealthCal.addDays(400, to: t), today: t)
            .filter { $0.original > t }
        // [v25.579 驗證] 落在暫停裡＝金額 0 的那一段：〔暫停〕時「暫停裡改過金額、記成這期不轉」的期（state .skipped、段的金額 0）也算。
        // 只看 .paused 的話，那一期會被當成恢復的那期（12/11 改過金額：卡上變「暫停到 12/10」），三期都改過就整個看不到暫停
        func inPause(_ p: WealthTransferPeriod) -> Bool {
            if p.state == .paused { return true }
            return p.state == .skipped && (segment(at: p.key)?.amount ?? 0) <= 0.004
        }
        guard let i = list.firstIndex(where: { inPause($0) }) else { return nil }
        let start = list[i].original
        var resume: Date? = nil
        for p in list[(i + 1)...] where !inPause(p) {
            resume = p.original
            break
        }
        let active = i == 0
        let until: String? = resume.map { WealthTransferText.dayText(WealthCal.addDays(-1, to: $0), today: t) }
        let text: String
        if active {
            text = until.map { "暫停到 " + $0 } ?? "暫停中"
        } else {
            let head = WealthTransferText.dayText(start, today: t) + " 起暫停"
            text = until.map { head + "到 " + $0 } ?? head
        }
        return WealthTransferPauseInfo(start: start, resume: resume, active: active, text: text)
    }
}

extension WealthTransferPlan {
    /// 〔暫停〕「從哪一期起暫停？」可以選的：今天以後（不含今天）12 期原本的日子（第一個＝〔下一期〕）
    static func pauseStarts(_ r: WealthTransferRule, today: Date) -> [Date] {
        let t = WealthCal.day(today)
        let list = WealthTransferSchedule.originalDates(r, through: WealthCal.addDays(400, to: t))
        return Array(list.filter { $0 > t }.prefix(12))
    }

    /// 「到哪一期恢復？」可以選的：暫停那一期以後 26 期原本的日子（〔先不設〕另外一顆）
    static func pauseResumes(_ r: WealthTransferRule, after start: Date) -> [Date] {
        let s = WealthCal.day(start)
        let list = WealthTransferSchedule.originalDates(r, through: WealthCal.addDays(31 * 27, to: s))
        return Array(list.filter { $0 > s }.prefix(26))
    }

    /// 暫停表單最下面那一句：「12/4、12/11、12/18 這 3 期不算，12/25 起照轉」「12/4～2027/1/29 這 9 期不算，2/5 起照轉」
    /// 「12/4 起每一期都不算，到你按〔恢復〕為止」
    static func pauseSummary(_ r: WealthTransferRule, from start: Date, until resume: Date?, today: Date) -> String {
        let t = WealthCal.day(today)
        guard let end = resume else {
            return WealthTransferText.dayText(start, today: t) + " 起每一期都不算，到你按〔恢復〕為止"
        }
        let tail = "，" + WealthTransferText.dayText(end, today: t) + " 起照轉"
        let list: [Date] = WealthTransferSchedule.originalDates(r, through: WealthCal.addDays(-1, to: end))
            .filter { $0 >= WealthCal.day(start) }
        guard let first = list.first, let last = list.last else { return "沒有要暫停的期" + tail }
        let which: String
        if list.count <= 3 {
            which = list.map { WealthTransferText.dayText($0, today: t) }.joined(separator: "、")
        } else {
            which = WealthTransferText.dayText(first, today: t) + "～" + WealthTransferText.dayText(last, today: t)
        }
        return which + " 這 \(list.count) 期不算" + tail
    }
}

// MARK: - 一套數字裡要的（〔轉好了〕今天對過存摺、銀行設的最後一次）

/// 〔轉好了〕的那一期，兩邊帳戶今天有沒有對過存摺（那個幣別）：有的話先問「今天對存摺的時候，這筆轉了嗎？」
struct WealthTransferReconciled: Equatable {
    /// 轉出帳戶今天對過存摺（〔還沒，對完才轉的〕＝記 lateOut）
    let from: Bool
    /// 轉進帳戶今天對過存摺（＝記 lateIn）
    let to: Bool

    var any: Bool { from || to }
}

extension WealthFacts {
    /// [v25.579] 那一期兩邊帳戶今天有沒有對過存摺（那一邊那個幣別；judge §3.6「v2〔轉好了〕的那天」）
    func transferReconciledToday(ruleId: UUID, key: String) -> WealthTransferReconciled {
        guard let p = transferPeriod(ruleId, key: key) else { return WealthTransferReconciled(from: false, to: false) }
        let t = today
        func anchoredToday(_ id: UUID?, code: String) -> Bool {
            guard let a = account(id) else { return false }
            return a.ledger.contains { row in
                row.kind == .anchor && WealthCal.day(row.date) == t && WealthFacts.norm(row.code) == code
            }
        }
        return WealthTransferReconciled(from: anchoredToday(p.fromId, code: p.fromCode),
                                        to: anchoredToday(p.toId, code: p.toCode))
    }

    /// [v25.579] 銀行設的最後一次（新增表單「銀行那邊設到哪天」）那天：還在跑、最後一期在今天（含）以後、
    /// 是銀行那邊設的（endedBy nil：不是規則頁〔結束〕"user"、不是收起來、刪帳戶結束的）、沒有改日子接上的新那條。不是＝nil
    func transferBankEndDay(_ t: TransferRule) -> Date? {
        let successors: Set<UUID> = Set(transferBook.live.compactMap { $0.previousId })
        return WealthTransferNotices.bankEndDay(t, successors: successors, today: today)
    }
}

// MARK: - 要確認 v2 四條、通知三種

enum WealthTransferNotices {
    /// 過了日子幾天內問「轉了嗎？」（1～7 天）
    static let askDays = 7
    /// 〔還沒〕之後掛滿幾天再問一次「還要轉嗎？」
    static let hangDays = 7
    /// 銀行設的最後一次前幾天開始講
    static let endSoonDays = 14
    /// 規則頁〔結束〕記在 endedBy（v1a 的 nil＝你按的；這一版起規則頁按的寫這個字，跟「銀行那邊設到哪天」分開）
    static let endedByUser = "user"
    /// 自己轉那天的提醒：每條最多排接下來幾期（每週自己轉的不會把 10 則的額度用光；每次打開 App 會往後補）
    static let doPerRule = 2
    /// 自己轉那天幾點、自動轉可能轉不過去前一天幾點、銀行最後一次前 14 天幾點
    static let doHour = 9
    static let shortHour = 20
    static let endHour = 9

    /// 銀行設的最後一次那天（WealthFacts.transferBankEndDay）；successors：有接上新那條的規則 id
    static func bankEndDay(_ t: WealthFacts.TransferRule, successors: Set<UUID>, today: Date) -> Date? {
        guard !t.isEnded, t.rule.endedBy == nil, !successors.contains(t.id), let last = t.lastDay else { return nil }
        guard WealthCal.day(last) >= WealthCal.day(today) else { return nil }
        return last
    }

    /// 要確認 v2 的四條（WealthFacts.makeChecks 叫；按過〔知道了〕的那邊濾）。names：帳戶的顯示名（ctx.nameById）。
    /// ① 今天要轉（自己轉、今天那一期還沒按）：「今天要自己從 薪轉 轉 5,000 到 台灣銀行」〔轉好了〕〔看這一期〕
    /// ② 過了日子沒按（7 天內、每條只問最近那期）：「10/31 該從 薪轉 轉 5,000 到 台灣銀行，轉了嗎？（App 先當作轉了）」〔轉了〕〔還沒…〕
    /// ③ 你說〔還沒〕、掛滿 7 天：「10/31 那筆 5,000 還沒轉（一直算在明天）。還要轉嗎？」〔今天轉好了〕〔這期不轉了〕
    /// ④ 銀行設的最後一次 14 天內：「『薪轉 → 零用錢』4/9 是最後一次（你設的銀行到期日）。要繼續的話記得去銀行續設」〔已經續設〕〔知道了〕
    static func checks(transfers: [WealthFacts.TransferRule], names: [UUID: String], bankIds: Set<UUID>,
                       today: Date) -> [WealthCheck] {
        let t = WealthCal.day(today)
        let successors: Set<UUID> = Set(transfers.compactMap { $0.rule.previousId })
        var out: [WealthCheck] = []
        for r in transfers {
            // [v25.579 驗證] 已結束的也看（銀行設的最後一次、規則頁〔結束〕、改日子接上新的那條）：最後那幾期照樣問「轉了嗎？」
            // 「還要轉嗎？」——那天 09:00 的通知寫了「沒按的話，明天會問你一次」、規則頁也列「當作轉了・等你回答」。
            // 帳戶收起來、刪掉時結束的不問；④ 銀行設的最後一次 bankEndDay 本來就只看還在跑的
            if r.isEnded && (r.rule.endedBy == "accountHidden" || r.rule.endedBy == "accountDeleted") { continue }
            let ids: [UUID] = [r.fromId, r.toId].compactMap { $0 }.filter { bankIds.contains($0) }
            if r.isManual {
                let list = WealthTransferSchedule.periods(r.rule, through: WealthCal.addDays(62, to: t), today: t)
                for p in list where p.manualPhase(today: t) == .today {
                    out.append(WealthCheck(
                        id: "trtoday-\(r.id.uuidString)-\(p.key)", kind: .transferToday, tone: .warn,
                        text: "今天要自己從 \(name(p.fromId, names)) 轉 \(money(p)) 到 \(name(p.toId, names))",
                        actions: [WealthCheck.Action(title: "轉好了", fix: .transferDoneToday(ruleId: r.id, key: p.key)),
                                  WealthCheck.Action(title: "看這一期", fix: .openTransferPeriod(ruleId: r.id, key: p.key))],
                        accountIds: ids))
                }
                if let p = list.last(where: { $0.manualPhase(today: t) == .waiting }) {
                    let md = WealthTransferText.dayText(p.day, today: t)
                    out.append(WealthCheck(
                        id: "trask-\(r.id.uuidString)-\(p.key)", kind: .transferAsk, tone: .warn,
                        text: "\(md) 該從 \(name(p.fromId, names)) 轉 \(money(p)) 到 \(name(p.toId, names))，轉了嗎？（App 先當作轉了）",
                        actions: [WealthCheck.Action(title: "轉了",
                                                     fix: .setTransferStatus(ruleId: r.id, key: p.key,
                                                                             status: WealthTransferStatus.done.rawValue)),
                                  WealthCheck.Action(title: "還沒…", fix: .askTransferNotYet(ruleId: r.id, key: p.key))],
                        accountIds: ids))
                }
                for p in list where p.manualPhase(today: t) == .notYet && hanging(p, rule: r.rule, today: t) {
                    let md = WealthTransferText.dayText(p.original, today: t)
                    out.append(WealthCheck(
                        id: "trlate-\(r.id.uuidString)-\(p.key)", kind: .transferHanging, tone: .warn,
                        text: "\(md) 那筆 \(money(p)) 還沒轉（一直算在明天）。還要轉嗎？",
                        actions: [WealthCheck.Action(title: "今天轉好了", fix: .transferDoneToday(ruleId: r.id, key: p.key)),
                                  WealthCheck.Action(title: "這期不轉了",
                                                     fix: .setTransferStatus(ruleId: r.id, key: p.key,
                                                                             status: WealthTransferStatus.skip.rawValue))],
                        accountIds: ids))
                }
            }
            if let last = bankEndDay(r, successors: successors, today: t), WealthCal.days(from: t, to: last) <= endSoonDays {
                let md = WealthTransferText.dayText(last, today: t)
                out.append(WealthCheck(
                    id: "trend-\(r.id.uuidString)-\(WealthCal.dayKey(last))", kind: .transferEnding, tone: .warn,
                    text: "『\(r.title)』\(md) 是最後一次（你設的銀行到期日）。要繼續的話記得去銀行續設",
                    actions: [WealthCheck.Action(title: "已經續設", fix: .renewTransferEnd(r.id)),
                              WealthCheck.Action(title: "知道了", fix: .dismiss)],
                    accountIds: ids))
            }
        }
        return out
    }

    /// 你說〔還沒〕之後掛滿 7 天（照你按的那天 at；沒有 at＝原本那天的隔天）
    static func hanging(_ p: WealthTransferPeriod, rule r: WealthTransferRule, today: Date) -> Bool {
        let note: WealthTransferNote? = r.notes?[p.key]
        let pressed: Date? = note?.at
        let answered: Date = pressed.map { WealthCal.day($0) } ?? WealthCal.addDays(1, to: p.original)
        return WealthCal.days(from: answered, to: WealthCal.day(today)) >= hangDays
    }

    /// 帳戶的名字（找不到「別的帳戶」）
    private static func name(_ id: UUID?, _ names: [UUID: String]) -> String {
        id.flatMap { names[$0] } ?? "別的帳戶"
    }

    /// 句子裡的金額「5,000」
    private static func money(_ p: WealthTransferPeriod) -> String {
        WealthFormat.plain(p.amount, code: p.fromCode)
    }

    /// 通知三種（WealthReminders.candidates 叫；不看時間、不限則數，jobs(from:now:) 再篩）。這條 remind == false 不排。
    /// ① wealth.tr.do.<日子>：自己轉那天 09:00「今天有 1 筆轉帳要轉」（同一天幾條併一則；還沒按的、今天以後 35 天內、每條最多接下來 2 期）
    /// ② wealth.tr.short.<日子>：自動轉那天轉出帳戶可能不夠（shortages 裡有那一期）前一天 20:00「明天一早有自動轉帳」（同一天併一則）
    /// ③ wealth.tr.end.<規則>.<日子>：銀行設的最後一次前 14 天 09:00「有一條定期轉帳 4/9 是最後一次」
    /// 點了開那天第一筆的轉出帳戶（accountId；延後的再提醒也照它認來源）
    static func candidates(facts: WealthFacts) -> [WealthReminderJob] {
        let t = facts.today
        let prefix = WealthReminders.prefix
        let horizon = WealthCal.addDays(WealthFacts.upcomingDays, to: t)
        var out: [WealthReminderJob] = []

        // ① 自己轉那天 09:00
        var doCount: [String: Int] = [:]
        var doFrom: [String: UUID] = [:]
        var doDay: [String: Date] = [:]
        for r in facts.transferRules where !r.isEnded && r.isManual && r.rule.remind != false {
            var taken = 0
            for p in WealthTransferSchedule.periods(r.rule, through: WealthCal.addDays(31, to: horizon), today: t) {
                guard p.status == nil, let ph = p.manualPhase(today: t), ph == .today || ph == .upcoming,
                      let f = p.fromId else { continue }
                let d = WealthCal.day(p.day)
                guard d <= horizon, taken < doPerRule else { continue }
                taken += 1
                let k = WealthCal.dayKey(d)
                if doCount[k] == nil {
                    doFrom[k] = f
                    doDay[k] = d
                }
                doCount[k, default: 0] += 1
            }
        }
        for k in doCount.keys.sorted() {
            guard let d = doDay[k], let f = doFrom[k] else { continue }
            let n = doCount[k] ?? 1
            out.append(WealthReminderJob(key: prefix + "tr.do." + k, title: "今天有 \(n) 筆轉帳要轉",
                                         body: "轉好了到財富頁按「轉好了」；沒按的話，明天會問你一次。",
                                         fireDate: at(d, hour: doHour), accountId: f))
        }

        // ② 自動轉可能轉不過去：前一天 20:00
        var shortFrom: [String: UUID] = [:]
        var shortDay: [String: Date] = [:]
        for a in facts.accounts where !a.isSecurities && !a.hidden {
            for s in a.shortages {
                guard let rid = s.transferRuleId, !s.transferManual, let r = facts.transferRule(rid),
                      r.rule.remind != false else { continue }
                let d = WealthCal.day(s.date)
                guard d > t else { continue }
                let k = WealthCal.dayKey(d)
                if shortFrom[k] == nil {
                    shortFrom[k] = a.id
                    shortDay[k] = d
                }
            }
        }
        for k in shortFrom.keys.sorted() {
            guard let d = shortDay[k], let f = shortFrom[k] else { continue }
            out.append(WealthReminderJob(key: prefix + "tr.short." + k, title: "明天一早有自動轉帳",
                                         body: "轉出的帳戶可能不夠，打開看看。",
                                         fireDate: at(WealthCal.addDays(-1, to: d), hour: shortHour), accountId: f))
        }

        // ③ 銀行設的最後一次前 14 天 09:00
        for r in facts.transferRules where r.rule.remind != false {
            guard let last = facts.transferBankEndDay(r), let f = r.fromId else { continue }
            out.append(WealthReminderJob(key: prefix + "tr.end." + r.id.uuidString + "." + WealthCal.dayKey(last),
                                         title: "有一條定期轉帳 " + WealthFormat.monthDay(last) + " 是最後一次",
                                         body: "要繼續的話，記得去銀行續設，再回 App 改結束日。",
                                         fireDate: at(WealthCal.addDays(-endSoonDays, to: last), hour: endHour),
                                         accountId: f))
        }
        return out
    }

    /// 那天幾點整（西曆、手機時區；同 WealthReminders.at）
    private static func at(_ day: Date, hour: Int) -> Date {
        WealthCal.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: WealthCal.day(day)) ?? day
    }
}

// MARK: - 我的行事曆（judge §4.9；App 裡，可以有金額）

extension WealthDates {
    /// 每條放接下來幾期
    static let transfersPerRule = 2

    /// 我的行事曆的定期轉帳（今天起；照日子、同一天照標題）：自己轉的每條接下來 2 期（isManual，橘）、銀行自動轉**每月**的接下來 2 期（灰）、
    /// 每週自動轉的不放（太多）。標題＝你取的名字或「薪轉 → 台灣銀行」；灰字「自己轉・NT$5,000」「銀行自動轉・NT$20,000」（遮住「NT$ ••••」）。
    /// widgetTitle／lockTitle 只寫「轉帳」：**這一份不給 CalendarDayItems**（今天小工具、手錶都不放；all／items 不含它）
    static func transferItems(facts: WealthFacts, masked: Bool) -> [WealthDateItem] {
        let t = facts.today
        var out: [WealthDateItem] = []
        for r in facts.transferRules where !r.isEnded {
            guard r.isManual || r.rule.cycleKind == .monthly else { continue }
            var shown = 0
            for p in WealthTransferSchedule.periods(r.rule, through: WealthCal.addDays(400, to: t), today: t) where p.counts {
                let d = WealthCal.day(p.day)
                guard d >= t, let f = p.fromId ?? r.fromId else { continue }
                if shown >= transfersPerRule { break }
                shown += 1
                let money: String = masked ? WealthFormat.masked : WealthFormat.money(p.amount, code: p.fromCode)
                let detail: String = (r.isManual ? "自己轉" : "銀行自動轉") + "・" + money
                out.append(WealthDateItem(id: "wd-tr-" + r.id.uuidString + "-" + p.key, day: d, kind: .transfer,
                                          title: r.title, detail: detail, widgetTitle: "轉帳", lockTitle: "轉帳",
                                          icon: "arrow.left.arrow.right", accountId: f, isManual: r.isManual))
            }
        }
        return out.enumerated().sorted { x, y in
            if x.element.day != y.element.day { return x.element.day < y.element.day }
            if x.element.title != y.element.title { return x.element.title < y.element.title }
            return x.offset < y.offset
        }.map { $0.element }
    }

    /// 那一天的定期轉帳（MyCalendarView.eventsOn）
    static func transferItems(on day: Date, facts: WealthFacts, masked: Bool) -> [WealthDateItem] {
        let d = WealthCal.day(day)
        return transferItems(facts: facts, masked: masked).filter { $0.day == d }
    }
}
