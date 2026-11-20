import Foundation

// MARK: - [v25.597 轉組織 v4] 暫時離開（借調、支援、留停）與轉進來
//（orgmove/judge.md §7 v4、§3.7、§2.1 personKind "org"／kind "temp"、"in"；orgmove/build/v4/brief.md §2；
// sim_v4.py 照這裡一行一行寫過、跑過）
//
// • 暫時離開＝一張 kind "temp" 的交接單：部門、廠區、職稱都不動；生效日（含）～回來那天（不含）在名單「借調中・到 1/29」那一區。
//   每一項多〔代理（回來還給本人）〕：action 照舊 "give"／"replace"＋OrgMoveLine.proxy＝true（套用、復原、交接單狀態全部照交給那一套）；
//   固定會議〔暫停到 1/29〕、週報〔暫停〕＝OrgMoveAction.pause；這段期間的班〔這幾天清掉〕。
//   回來那天問〔還給本人〕〔留給代理人〕（LifeStore.returnOrgMoveTemp；用〔拿回來〕那一支一列一列退）。
//   回來前 3 天 09:00「有一位同仁 1/29 回來，有 3 件要還」（OrgMoveNotices；不寫名字、部門、借調還是留停）。
//   留停期間：請假不算、到期的不算逾期（主動性不被扣到 0；TalentMatrixView 標「留停中」）。
// • 轉進來＝一張 kind "in"、personKind "org" 的交接單：新增部屬時連到公司組織裡既有的那一位（照片、關係、作品、名片都在），
//   personId 照樣是部屬 id（v4 不做「排在以後才轉進來」：人調過來那天新增，已知限制），before.orgPersonId 記那位組織人員。
//   接收清單＝這張單的 lines：前一位主管交過來的事（打字、匯入交接文字）變成這位同仁的待辦、接手的機台、新開的一對一。
// • 部屬、組織人員、部門一個欄位都不加（舊 iPad 存一次會洗掉；u1 §9.2）：狀態都在交接單（life_org_moves_v1）。
// • 隱私：名字只在 App 內頁；通知只有件數與日子。

/// 暫時離開的一段（OrgMoveIndex.away；交接單算的，不存）
struct OrgMoveAway: Equatable {
    let moveId: UUID
    /// "loan"／"support"／"leave"
    let tempKind: String
    /// 「2026-11-02」生效日（含）
    let fromKey: String
    /// 「2027-01-29」回來那天（不含）
    let untilKey: String
    /// 回來那天按過〔還給本人〕〔留給代理人〕了
    let returned: Bool

    var kindValue: OrgMoveTempKind { OrgMoveTempKind(rawValue: tempKind) ?? .loan }
    /// 這天在不在這一段（含開始、不含回來那天）
    func covers(_ dayKey: String) -> Bool { fromKey <= dayKey && dayKey < untilKey }
}

/// 一段日子（含開始、不含結束）
struct OrgMoveDaySpan: Equatable {
    let fromKey: String
    let untilKey: String
    func covers(_ dayKey: String) -> Bool { fromKey <= dayKey && dayKey < untilKey }
}

/// 部屬名單「借調中・到 1/29」那一區的一列
struct OrgMoveAwayRow: Identifiable, Equatable {
    let personId: UUID
    let moveId: UUID
    let name: String
    /// 「借調中・到 1/29」「留停中・到 6/1」「支援中・到 11/20」
    let text: String
    var id: UUID { personId }
}

/// 回來那天問的那一張（部屬總覽、卡片提示列）
struct OrgMoveReturnAsk: Identifiable, Equatable {
    let moveId: UUID
    let personId: UUID
    /// 「林志豪 1/29 回來了」
    let title: String
    /// 「代理的 3 件還沒做完：要還給林志豪，還是留給代理人？做完的不動。」
    let message: String
    /// 〔還給林志豪〕
    let backLabel: String
    /// 〔留給代理人〕
    let keepLabel: String
    /// 要還的件數
    let count: Int
    var id: UUID { moveId }
}

/// 新增部屬時公司組織裡同名的那一位（「是不是品保課那位張家瑋？」）
struct OrgMoveIntakeCandidate: Identifiable, Equatable {
    let orgPersonId: UUID
    let name: String
    let deptId: UUID?
    /// 「品保課」（沒有部門＝""）
    let deptShort: String
    /// 「品保課・工程師」（括號裡那一段；都沒有＝""）
    let place: String
    /// 組織頁標了已離職
    let inactive: Bool
    var id: UUID { orgPersonId }
}

/// 接收清單的一項（打字新增、或從匯入的交接文字讀出來的）
struct OrgMoveIntakeItem: Identifiable, Equatable {
    var id = UUID()
    var title: String
    /// 「2026-11-20」（沒寫截止＝nil）
    var dueKey: String?
    var memo: String = ""
    /// 交接文字裡的小標：「待辦」「機台」「週報題目」「會議與議程」…（打字的＝"待辦"）
    var section: String = "待辦"
    /// 「機台」那一段對得到名字的那一台（接收時改成〔接手〕這台，不另外建待辦）
    var equipmentId: UUID?
}

// MARK: - 查表（OrgMoveIndex.rebuild 最後叫 rebuildTemp）

extension OrgMoveIndex {
    /// 部屬 id → 暫時離開的每一段（照生效日排；做過、沒復原、沒刪的）
    static var away: [UUID: [OrgMoveAway]] = [:]
    /// 週報 id →〔暫停〕的那一段（這段期間到期的不算逾期）
    static var pausedReports: [UUID: OrgMoveDaySpan] = [:]
    /// 任務 id →「從品保課帶過來」（轉進來的接收清單；卡片上的膠囊）
    static var intakeByItem: [UUID: String] = [:]

    static func rebuildTemp(_ book: OrgMoveBook) {
        var aw: [UUID: [OrgMoveAway]] = [:]
        var paused: [UUID: OrgMoveDaySpan] = [:]
        var intake: [UUID: String] = [:]
        for m in book.live where !m.isUndone && m.wasApplied {
            // [v4 驗證] 生效前〔取消這張單〕〔留給接手的人〕的（state 還是 applied、只記 cancelledAt；isCancelled 抓不到）：
            // 暫時離開取消了＝這位同仁沒有離開，不算「借調中」「留停中」、暫停的週報也不免逾期。要退回這一件：拿掉 `m.cancelledAt == nil,`
            if m.isTemp, m.cancelledAt == nil, let until = m.returnKey, !until.isEmpty, until > m.effectiveKey {
                aw[m.personId, default: []].append(OrgMoveAway(moveId: m.id, tempKind: m.tempKindValue.rawValue,
                                                               fromKey: m.effectiveKey, untilKey: until,
                                                               returned: m.returnedAt != nil))
                for l in m.allLines where l.kind == OrgMoveLineKind.report.rawValue && l.lineAction == .pause
                    && l.state != OrgMoveLineState.undone.rawValue {
                    if let r = l.refId { paused[r] = OrgMoveDaySpan(fromKey: m.effectiveKey, untilKey: until) }
                }
            }
            if m.isIntake {
                let text = OrgMovePlan.intakeChipText(m)
                for l in m.allLines where l.kind == OrgMoveLineKind.task.rawValue && l.state != OrgMoveLineState.undone.rawValue {
                    if let r = l.refId { intake[r] = text }
                }
            }
        }
        var sorted: [UUID: [OrgMoveAway]] = [:]
        for (k, list) in aw {
            sorted[k] = list.sorted { a, b in a.fromKey != b.fromKey ? a.fromKey < b.fromKey : a.untilKey < b.untilKey }
        }
        away = sorted
        pausedReports = paused
        intakeByItem = intake
    }

    /// 這天暫時離開中的那一段（沒有＝nil）。todayKey：手機當地的今天「2026-11-02」
    static func awayNow(_ personId: UUID?, todayKey: String) -> OrgMoveAway? {
        guard let personId, let list = away[personId] else { return nil }
        return list.last(where: { $0.covers(todayKey) })
    }

    /// 這天在不在留停那一段（請假不算、到期的不算逾期）
    static func onLeave(_ personId: UUID, dayKey: String) -> Bool {
        guard let list = away[personId] else { return false }
        return list.contains { $0.kindValue == .leave && $0.covers(dayKey) }
    }

    /// 這份週報〔暫停〕了、而且報告日在暫停那一段裡（不算逾期）
    static func reportPaused(_ reportId: UUID, dayKey: String) -> Bool {
        pausedReports[reportId]?.covers(dayKey) == true
    }
}

// MARK: - 規則與字

extension OrgMovePlan {
    // MARK: 代理

    /// 這一列是〔代理（回來還給本人）〕：自己標了 proxy，或「跟著機台」而那台機台是代理的
    static func isProxyLine(_ l: OrgMoveLine, in lines: [OrgMoveLine]) -> Bool {
        if l.proxy == true { return true }
        guard l.lineAction == .withEquipment, let pid = l.parentId,
              let p = lines.first(where: { $0.kind == OrgMoveLineKind.equipment.rawValue && $0.refId == pid }) else { return false }
        return p.proxy == true
    }

    /// 精靈每一列多的那幾顆（只有暫時離開）：待辦、機台、議程多〔代理…（回來還給本人）〕；管理人員多〔代理人…（回來換回）〕；
    /// 有週期的固定會議多〔暫停到 1/29〕；週報（還沒過報告日的）多〔暫停〕。其他照舊（換單位那一套）
    static func tempChoices(_ base: [OrgMoveChoice], line: OrgMoveLine, kind: OrgMoveKind, returnKey: String?,
                            world: OrgMoveWorld) -> [OrgMoveChoice] {
        guard kind == .temp, !line.isCustom else { return base }
        let back = returnKey.map { shortDay($0) } ?? ""
        switch line.lineKind {
        case .some(.task), .some(.agenda), .some(.equipment):
            if line.lineLock == .dereliction { return base }
            let p = OrgMoveChoice(action: .give, label: "代理…（回來還給本人）", needsPerson: true, proxy: true)
            return [p] + base
        case .some(.manager):
            let p = OrgMoveChoice(action: .replace, label: "代理人…（回來換回）", needsPerson: true, proxy: true)
            return base + [p]
        case .some(.meeting):
            guard let m = meeting(line, world: world), m.rule != nil else { return base }
            let label = back.isEmpty ? "暫停" : "暫停到 \(back)"
            return [OrgMoveChoice(action: .pause, label: label, needsPerson: false)] + base
        case .some(.report):
            if line.lineLock == .pastDue || line.parentId != nil { return base }
            return [OrgMoveChoice(action: .pause, label: "暫停（這段期間到期的不算逾期）", needsPerson: false)] + base
        default:
            return base
        }
    }

    /// 暫時離開的預設（buildLines 最後；只有 kind temp）：期間到期的週報〔暫停〕（回來以後才到期的〔跟著〕）、一對一〔暫停到 1/29〕（其他固定會議照舊）、
    /// 議程還沒決定（要選代理、交給、跟著）、班只列這段期間的〔這幾天清掉〕（沒有就不列）、管理人員〔照舊〕
    static func applyTempDefaults(_ lines: inout [OrgMoveLine], kind: OrgMoveKind, personId: UUID, effectiveKey: String,
                                  returnKey: String?, world: OrgMoveWorld, now: Date) {
        guard kind == .temp, let ret = returnKey else { return }
        let cut = cutKey(effectiveKey: effectiveKey, todayKey: dayKey(now))
        var out: [OrgMoveLine] = []
        for var l in lines {
            switch l.lineKind {
            case .some(.report):
                // 這段期間到期的〔暫停〕；回來那天以後才到期的〔跟著〕（回來自己交）
                if l.lineLock != .pastDue, l.parentId == nil, let d = l.dueKey, d >= effectiveKey {
                    if d < ret {
                        l.action = OrgMoveAction.pause.rawValue
                    } else if l.action == nil {
                        l.action = OrgMoveAction.follow.rawValue
                    }
                }
            case .some(.meeting):
                // 一對一（名稱像一對一、有週期）〔暫停到 1/29〕；其他固定會議照舊（要暫停自己選）
                if let m = meeting(l, world: world), m.rule != nil, SubExportComposer.isOneOnOneName(m.topic) {
                    l.action = OrgMoveAction.pause.rawValue
                }
            case .some(.agenda):
                l.action = nil
            case .some(.shifts):
                let n = world.sub(personId)?.shifts.filter { s in
                    let k = dayKey(s.date)
                    return k >= cut && k < ret
                }.count ?? 0
                guard n > 0 else { continue }
                l.title = "\(shortDay(cut))～\(shortDay(addDays(ret, -1))) 的班 \(n) 格"
                l.action = OrgMoveAction.drop.rawValue
            case .some(.manager):
                l.action = OrgMoveAction.keep.rawValue
            default:
                break
            }
            out.append(l)
        }
        lines = out
    }

    /// 還沒決定的（暫時離開）：確認鈕上面那一行（nil＝可以按）
    static func tempConfirmBlock(_ draft: OrgMoveDraft) -> String? {
        guard draft.kind == .temp else { return nil }
        let back = dayKey(draft.returnDate)
        guard back > dayKey(draft.effective) else { return "回來那天要比生效日晚" }
        let t = tally(draft.lines)
        guard t.undecided > 0 else { return nil }
        return "還有 \(t.undecided) 項還沒決定：暫時離開這段期間要交給誰代理（或選〔跟著〕〔交給…〕）"
    }

    /// 膠囊上的字（暫時離開那幾種；nil＝照原本的）
    static func tempCapsuleText(_ line: OrgMoveLine, returnKey: String?) -> String? {
        switch line.lineAction {
        case .some(.give):
            guard line.proxy == true else { return nil }
            return "代理 \(line.toName ?? "")（回來還）"
        case .some(.replace):
            guard line.proxy == true else { return nil }
            return "代理人 \(line.toName ?? "")（回來換回）"
        case .some(.pause):
            if line.kind == OrgMoveLineKind.meeting.rawValue {
                return returnKey.map { "暫停到 \(shortDay($0))" } ?? "暫停"
            }
            return "暫停"
        default:
            return nil
        }
    }

    /// 灰字（暫時離開那幾種；nil＝照原本的）
    static func tempReasonLines(_ line: OrgMoveLine, in lines: [OrgMoveLine], personName: String, effectiveKey: String,
                                returnKey: String?, world: OrgMoveWorld, now: Date) -> [String]? {
        guard let ret = returnKey else { return nil }
        let cut = cutKey(effectiveKey: effectiveKey, todayKey: dayKey(now))
        let span = "\(shortDay(cut))～\(shortDay(addDays(ret, -1)))"
        if isProxyLine(line, in: lines), line.lineAction != .withEquipment {
            let who = line.toName ?? "代理人"
            if line.lineAction == .replace {
                return ["\(span) 由\(who)代理", "\(shortDay(ret)) 回來那天問要不要換回\(personName)"]
            }
            return ["代理期間做完的算\(who)", "\(shortDay(ret)) 回來那天問要還給\(personName)還是留給\(who)（做完的不動）"]
        }
        switch line.lineAction {
        case .some(.pause):
            if line.kind == OrgMoveLineKind.meeting.rawValue {
                guard let m = meeting(line, world: world) else { return nil }
                let n = pauseSessionCount(m, fromKey: cut, untilKey: ret)
                return ["\(span) 的 \(n) 場先取消，\(shortDay(ret)) 起照常"]
            }
            return ["留在\(personName)身上；\(span) 到期的不算逾期"]
        case .some(.drop):
            guard line.kind == OrgMoveLineKind.shifts.rawValue else { return nil }
            return ["只清 \(span) 的班；\(shortDay(ret)) 以後的照舊"]
        default:
            return nil
        }
    }

    /// 這段期間（含開始、不含回來那天）還沒取消的場次有幾場（〔暫停到 1/29〕前後算的同一套）
    static func pauseSessionCount(_ m: SubordinateMeeting, fromKey: String, untilKey: String) -> Int {
        guard m.rule != nil, let start = date(fromKey: fromKey), let end = date(fromKey: untilKey) else { return 0 }
        return m.expandedOccurrences(from: start, horizon: end).filter { o in
            !o.isCancelled && o.date >= start && o.date < end
        }.count
    }

    /// 頂端那一行多的「・代理 3」（tallyText 後面接）
    static func proxyCount(_ lines: [OrgMoveLine]) -> Int {
        lines.filter { l in
            !l.isOrgLine && l.lineKind != nil && l.lineAction != .withEquipment && l.proxy == true
        }.count
    }

    // MARK: 第 ③ 步、交接單單頭

    /// 第 ③ 步：單頭兩行換成暫時離開的字、最上面一段「借調 11/2～1/28，1/29 回來」；接手的人那一段寫「代理 陳怡君 3 項」
    static func applyTempPreview(_ p: inout OrgMovePreview, draft: OrgMoveDraft, move: OrgMove, world: OrgMoveWorld, now: Date) {
        guard move.isTemp, let ret = move.returnKey else { return }
        let person = world.name(draft.personId)
        let where0 = sideText(move.from, world: world)
        let kindText = move.tempKindValue.label
        p.header = where0.isEmpty ? "\(person)　\(kindText)" : "\(person)　\(kindText)（\(where0)）"
        p.dates = "\(dayText(move.effectiveKey))起・\(dayText(ret))回來"
        let lines = move.allLines
        let cut = cutKey(move, now: now)
        var top: [String] = []
        let proxied = lines.filter { isProxyLine($0, in: lines) && $0.lineAction != .withEquipment && !$0.isOrgLine }.count
        if proxied > 0 {
            top.append("代理的 \(proxied) 件：\(shortDay(ret)) 回來那天問要還給\(person)還是留給代理人")
        }
        for l in lines where l.kind == OrgMoveLineKind.meeting.rawValue && l.lineAction == .pause {
            guard let m = meeting(l, world: world) else { continue }
            let n = pauseSessionCount(m, fromKey: cut, untilKey: ret)
            top.append("\(l.title) 暫停 \(n) 場，\(shortDay(ret)) 起照常")
        }
        let pausedReports = lines.filter { $0.kind == OrgMoveLineKind.report.rawValue && $0.lineAction == .pause }.count
        if pausedReports > 0 { top.append("週報暫停 \(pausedReports) 份：這段期間到期的不算逾期") }
        if move.tempKindValue == .leave {
            top.append("留停期間的請假不算、到期的不算逾期：主動性不會被扣")
        }
        top.append("部門、廠區、職稱都照舊；\(shortDay(ret)) 起回到名單原本的位置")
        let head = OrgMovePreviewBlock(id: "temp", title: "\(kindText) \(shortDay(cut))～\(shortDay(addDays(ret, -1)))，\(shortDay(ret)) 回來",
                                       lines: top)
        // 「交給 陳怡君 3 項」→ 全部是代理的寫「代理 陳怡君 3 項（回來還）」、有一部分的寫「交給 陳怡君 3 項（代理 2）」
        var blocks: [OrgMovePreviewBlock] = []
        for b in p.blocks {
            guard b.id.hasPrefix("to-"), let rid = UUID(uuidString: String(b.id.dropFirst(3))) else {
                blocks.append(b)
                continue
            }
            var given = 0
            var proxy = 0
            for l in lines where !l.isOrgLine && l.lineKind != nil {
                let r = resolved(l, in: lines)
                guard r.action == .give, r.toId == rid else { continue }
                given += 1
                if isProxyLine(l, in: lines) { proxy += 1 }
            }
            let name = world.name(rid)
            var title = b.title
            if proxy > 0 && proxy == given {
                title = "代理 \(name) \(given) 項（回來還）"
            } else if proxy > 0 {
                title = "\(b.title)（代理 \(proxy)）"
            }
            blocks.append(OrgMovePreviewBlock(id: b.id, title: title, lines: b.lines))
        }
        p.blocks = [head] + blocks
    }

    /// 交接單單頭（暫時離開）：(「林志豪　借調（製造一課 P1）」, 「11/2（一）起・1/29（五）回來」)；不是暫時離開＝nil
    static func tempSheetHeader(_ move: OrgMove, world: OrgMoveWorld) -> (title: String, dates: String)? {
        guard move.isTemp, let ret = move.returnKey else { return nil }
        let person = move.personName.isEmpty ? "這位同仁" : move.personName
        let where0 = sideText(move.from, world: world)
        let k = move.tempKindValue.label
        let title = where0.isEmpty ? "\(person)　\(k)" : "\(person)　\(k)（\(where0)）"
        var dates = "\(dayText(move.effectiveKey))起・\(dayText(ret))回來"
        if let at = move.returnedAt {
            let how = move.returnChoice == OrgMoveReturnChoice.keep.rawValue ? "留給代理人" : "還給本人"
            dates += "・\(shortDay(dayKey(at))) \(how)"
        }
        return (title, dates)
    }

    // MARK: 名單、人才矩陣

    /// 「借調中・到 1/29」「留停中・到 6/1」「支援中・到 11/20」
    static func awayText(_ a: OrgMoveAway) -> String {
        "\(a.kindValue.label)中・到 \(shortDay(a.untilKey))"
    }

    /// 部屬名單「暫時離開」那一區（今天暫時離開中的在職部屬；照回來那天排，同一天照名單順序）
    static func awayRows(world: OrgMoveWorld, todayKey: String) -> [OrgMoveAwayRow] {
        var out: [(row: OrgMoveAwayRow, key: String, idx: Int)] = []
        for (i, s) in world.activeSubordinates.enumerated() {
            guard let a = OrgMoveIndex.awayNow(s.id, todayKey: todayKey) else { continue }
            let n = s.name.trimmingCharacters(in: .whitespacesAndNewlines)
            out.append((OrgMoveAwayRow(personId: s.id, moveId: a.moveId, name: n.isEmpty ? "這位同仁" : n, text: awayText(a)),
                        a.untilKey, i))
        }
        return out.sorted { x, y in x.key != y.key ? x.key < y.key : x.idx < y.idx }.map { $0.row }
    }

    /// 名單那一區的標題「暫時離開（2）」
    static func awaySectionTitle(_ n: Int) -> String { "暫時離開（\(n)）" }

    /// 人才矩陣名字旁邊的小字（今天留停中＝「留停中」；其他＝nil）
    static func talentAwayBadge(personId: UUID, todayKey: String) -> String? {
        guard let a = OrgMoveIndex.awayNow(personId, todayKey: todayKey), a.kindValue == .leave else { return nil }
        return "留停中"
    }

    // MARK: 回來那天

    /// 這一張回來那天要還的那幾列（〔代理〕的、做過的、還沒退的；跟著代理機台的警報任務、待辦也算進來，機台退的時候一起回）
    static func returnLineIds(_ move: OrgMove) -> Set<UUID> {
        let lines = move.allLines
        var out = Set<UUID>()
        for l in lines where isProxyLine(l, in: lines) && l.state == OrgMoveLineState.done.rawValue {
            out.insert(l.id)
        }
        return out
    }

    /// 要還的件數（「有 3 件要還」）：代理的待辦、議程還在代理人身上沒做完、機台還是代理人負責、管理人員那一格還是代理人。
    /// 跟著機台的警報任務、待辦不另外算（機台算一件）
    static func returnItemCount(_ move: OrgMove, map: OrgMoveHolderMap) -> Int {
        guard move.isTemp else { return 0 }
        let lines = move.allLines
        var n = 0
        for l in lines where l.proxy == true && l.state == OrgMoveLineState.done.rawValue {
            guard let to = l.toId else { continue }
            switch l.lineKind {
            case .some(.task):
                guard let r = l.refId else { continue }
                if map.tasks[r]?.contains(where: { $0.holder == to && !$0.task.isCompleted }) == true { n += 1 }
            case .some(.equipment):
                guard let r = l.refId else { continue }
                if map.owners[r] == to { n += 1 }
            case .some(.agenda):
                guard let r = l.refId else { continue }
                let open: Bool = map.items[r]?.contains(where: { c in !c.item.isCompleted && map.creditedPeople(c).contains(to) }) == true
                if open { n += 1 }
            case .some(.manager):
                n += 1
            default:
                break
            }
        }
        return n
    }

    /// 回來那天（或之後）還沒按〔還給本人〕〔留給代理人〕、還有要還的：問一次。不是這種＝nil
    static func returnAsk(_ move: OrgMove, map: OrgMoveHolderMap, todayKey: String) -> OrgMoveReturnAsk? {
        // [v4 驗證] 生效前取消了（〔留給接手的人〕，cancelledAt）的不問：這位同仁沒有離開。要退回這一件：拿掉 `move.cancelledAt == nil,`
        guard move.isTemp, move.wasApplied, !move.isUndone, move.deletedAt == nil, move.returnedAt == nil,
              move.cancelledAt == nil, let ret = move.returnKey, todayKey >= ret else { return nil }
        let n = returnItemCount(move, map: map)
        guard n > 0 else { return nil }
        let person = move.personName.isEmpty ? "這位同仁" : move.personName
        return OrgMoveReturnAsk(moveId: move.id, personId: move.personId,
                                title: "\(person) \(shortDay(ret)) 回來了",
                                message: "代理的 \(n) 件還沒做完：要還給\(person)，還是留給代理人？做完的不動。",
                                backLabel: "還給\(person)", keepLabel: "留給代理人", count: n)
    }

    /// 部屬總覽最上面「回來了」那幾張（照回來那天排）
    static func returnAsks(book: OrgMoveBook, world: OrgMoveWorld, todayKey: String) -> [OrgMoveReturnAsk] {
        let temps = book.live.filter { $0.isTemp && $0.returnedAt == nil && ($0.returnKey ?? "9") <= todayKey }
        guard !temps.isEmpty else { return [] }
        let map = OrgMoveHolderMap(world: world)
        let ids = Set(world.subordinates.map(\.id))
        return temps.filter { ids.contains($0.personId) }
            .sorted { ($0.returnKey ?? "") < ($1.returnKey ?? "") }
            .compactMap { returnAsk($0, map: map, todayKey: todayKey) }
    }

    /// 〔暫停〕那幾列的字：會議「暫停到 1/29（13 場取消）」、週報「暫停：11/2～1/28 到期的不算逾期」（還沒做、復原了的＝nil，照原本的）
    static func tempPauseStatus(_ line: OrgMoveLine, in move: OrgMove) -> OrgMoveLineStatus? {
        guard move.isTemp, line.lineAction == .pause, line.state == OrgMoveLineState.done.rawValue,
              let ret = move.returnKey else { return nil }
        if line.kind == OrgMoveLineKind.meeting.rawValue {
            let u = OrgMovePauseUndo.decode(line.removedJSON)
            let n = (u?.createdIds?.count ?? 0) + (u?.flippedIds?.count ?? 0)
            return OrgMoveLineStatus(kind: .follow, mark: "・", text: "暫停到 \(shortDay(ret))（\(n) 場取消）",
                                     holderId: move.personId, fix: nil, fixLabel: nil)
        }
        let span = "\(shortDay(move.effectiveKey))～\(shortDay(addDays(ret, -1)))"
        return OrgMoveLineStatus(kind: .follow, mark: "・", text: "暫停：\(span) 到期的不算逾期",
                                 holderId: move.personId, fix: nil, fixLabel: nil)
    }

    /// 交接單那一列（暫時離開）：〔暫停〕的照 tempPauseStatus；代理的回來之後還給本人＝「1/29 還給林志豪 ✓」、留給代理人＝「留給 陳怡君」。
    /// 不是這種＝nil（照原本的 status）
    static func tempReturnedStatus(_ line: OrgMoveLine, in move: OrgMove) -> OrgMoveLineStatus? {
        if let p = tempPauseStatus(line, in: move) { return p }
        guard move.isTemp, let at = move.returnedAt, isProxyLine(line, in: move.allLines) else { return nil }
        let person = move.personName.isEmpty ? "這位同仁" : move.personName
        if move.returnChoice == OrgMoveReturnChoice.keep.rawValue {
            let who = receiver(line, in: move).name ?? line.toName ?? ""
            return OrgMoveLineStatus(kind: .open, mark: "○", text: "留給 \(who)（\(shortDay(dayKey(at))) 決定）",
                                     holderId: receiver(line, in: move).id, fix: nil, fixLabel: nil)
        }
        guard line.state == OrgMoveLineState.undone.rawValue else { return nil }
        return OrgMoveLineStatus(kind: .done, mark: "✓", text: "\(shortDay(dayKey(at))) 還給\(person)",
                                 holderId: move.personId, fix: nil, fixLabel: nil)
    }

    // MARK: 轉進來

    /// 新增部屬打完名字：公司組織裡同名的人（全公司，不限部門；已經連到在名單裡的部屬的不算——那一位已經是你的部屬了）
    static func intakeCandidates(name: String, world: OrgMoveWorld) -> [OrgMoveIntakeCandidate] {
        let key = LifeStore.normalizedPersonName(name)
        guard !key.isEmpty else { return [] }
        let subIds = Set(world.subordinates.map(\.id))
        var out: [OrgMoveIntakeCandidate] = []
        for p in world.orgPeople where LifeStore.normalizedPersonName(p.name) == key {
            if let sid = p.linkedSubordinateId, subIds.contains(sid) { continue }
            let d = world.deptShort(p.departmentId)
            let t = p.jobTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let place = [d, t].filter { !$0.isEmpty }.joined(separator: "・")
            out.append(OrgMoveIntakeCandidate(orgPersonId: p.id, name: p.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                              deptId: p.departmentId, deptShort: d, place: place, inactive: p.isInactive))
        }
        return out
    }

    /// 問的那一句（一位）：(「公司裡已經有 張家瑋（品保課・工程師）」, 「是同一位嗎？…」, 〔是，從品保課轉進來〕, 〔不是，另一位〕)
    static func intakeAsk(_ c: OrgMoveIntakeCandidate) -> (title: String, message: String, yes: String, no: String) {
        let who = c.place.isEmpty ? c.name : "\(c.name)（\(c.place)）"
        let yes = c.deptShort.isEmpty ? "是，同一位" : "是，從\(c.deptShort)轉進來"
        var msg = "是同一位嗎？選〔是〕會連到原本那一筆：照片、關係、作品、名片都留著，組織圖只有一個\(c.name)。"
        if c.inactive { msg += "（組織頁標了已離職：連過來就拿掉已離職）" }
        return ("公司裡已經有 \(who)", msg, yes, "不是，另一位")
    }

    /// 同名的有好幾位：每一位一顆〔是品保課那位〕＋〔都不是，另一位〕
    static func intakePickLabel(_ c: OrgMoveIntakeCandidate) -> String {
        c.deptShort.isEmpty ? "是\(c.place.isEmpty ? c.name : c.place)那位" : "是\(c.deptShort)那位"
    }

    /// 卡片任務上的膠囊「從品保課帶過來」
    static func intakeChipText(_ m: OrgMove) -> String {
        let from = labelShort(m.from.deptLabel ?? "")
        return from.isEmpty ? "轉進來時帶過來" : "從\(from)帶過來"
    }

    /// 交接單單頭（轉進來）：(「張家瑋　從品保課轉進來」, 「11/16（一）・設備課 P1」)；不是轉進來＝nil
    static func intakeSheetHeader(_ move: OrgMove, world: OrgMoveWorld) -> (title: String, dates: String)? {
        guard move.isIntake else { return nil }
        let person = move.personName.isEmpty ? "這位同仁" : move.personName
        let from = labelShort(move.from.deptLabel ?? "")
        let to = sideText(move.to, world: world)
        let title = from.isEmpty ? "\(person)　轉進來" : "\(person)　從\(from)轉進來"
        return (title, to.isEmpty ? dayText(move.effectiveKey) : "\(dayText(move.effectiveKey))・\(to)")
    }

    /// 接收清單「點一下接手」：新部門裡還沒有負責人的機台（照名字排）
    static func intakeUnownedEquipment(deptId: UUID?, world: OrgMoveWorld) -> [ManagedEquipment] {
        guard let deptId else { return [] }
        return world.equipment.filter { $0.departmentId == deptId && $0.ownerId == nil }
            .sorted { a, b in
                let x = a.name.localizedStandardCompare(b.name)
                if x != .orderedSame { return x == .orderedAscending }
                return a.id.uuidString < b.id.uuidString
            }
    }

    /// 〔開一對一〕帶的時段：你其他一對一（名稱像一對一、有週期）最常用的星期幾＋幾點（一樣多取最早建的那個）。
    /// 回傳 (weekday 1=週日…7=週六, hour, minute, durationMinutes, reminderMinutes)；沒有別的一對一＝nil（畫面用預設：下週同一天 10:00）
    static func intakeOneOnOneSlot(world: OrgMoveWorld, excluding personId: UUID) -> (weekday: Int, hour: Int, minute: Int, duration: Int, reminder: Int)? {
        var counts: [String: Int] = [:]
        var first: [String: (weekday: Int, hour: Int, minute: Int, duration: Int, reminder: Int, made: Date)] = [:]
        let cal = calendar
        for s in world.activeSubordinates where s.id != personId {
            for m in s.meetings where m.rule != nil && SubExportComposer.isOneOnOneName(m.topic) {
                let wd = m.rule?.weekdays.first ?? cal.component(.weekday, from: m.date)
                let h = cal.component(.hour, from: m.date)
                let mi = cal.component(.minute, from: m.date)
                let k = "\(wd)-\(h)-\(mi)"
                counts[k, default: 0] += 1
                if let old = first[k], old.made <= m.createdAt { continue }
                first[k] = (wd, h, mi, m.durationMinutes, m.reminderMinutes, m.createdAt)
            }
        }
        guard let best = counts.keys.sorted(by: { a, b in
            let ca = counts[a] ?? 0
            let cb = counts[b] ?? 0
            if ca != cb { return ca > cb }
            return (first[a]?.made ?? Date.distantFuture) < (first[b]?.made ?? Date.distantFuture)
        }).first, let f = first[best] else { return nil }
        return (f.weekday, f.hour, f.minute, f.duration, f.reminder)
    }

    /// 〔開一對一〕第一場：今天以後（不含今天）第一個那個星期幾的那個時刻
    static func intakeOneOnOneStart(weekday: Int, hour: Int, minute: Int, now: Date) -> Date {
        let cal = calendar
        let today = cal.startOfDay(for: now)
        for i in 1...7 {
            guard let d = cal.date(byAdding: .day, value: i, to: today) else { continue }
            if cal.component(.weekday, from: d) == weekday {
                return cal.date(bySettingHour: hour, minute: minute, second: 0, of: d) ?? d
            }
        }
        return now
    }

    /// 匯入的交接文字（OrgMovePlan.shareText 那種：「1. E-05 備品清點｜截止 11/20」「   備註：…」，小標「待辦」「機台」…）
    /// 讀成接收清單的幾項。沒有編號的行、單頭、「交給 …」「跟著…的：」那幾行不讀。截止「11/20」照今天往後找最近的那一年。
    /// 「機台」那一段的名字對得到新部門（或沒有負責人）的機台＝equipmentId（接收時改成接手那台）
    static func parseIntakeText(_ text: String, todayKey: String, world: OrgMoveWorld) -> [OrgMoveIntakeItem] {
        let sections: Set<String> = ["待辦", "機台", "週報題目", "會議與議程", "會議", "議程", "排班", "兼任", "自己加的"]
        var out: [OrgMoveIntakeItem] = []
        var section = "待辦"
        let raw = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for rawLine in raw.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if sections.contains(line) {
                section = line
                continue
            }
            if line.hasPrefix("備註：") {
                guard !out.isEmpty else { continue }
                let memo = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                let i = out.count - 1
                out[i].memo = out[i].memo.isEmpty ? memo : out[i].memo + "\n" + memo
                continue
            }
            guard let body = numberedBody(line) else { continue }
            let parts = body.components(separatedBy: "｜")
            var title = (parts.first ?? "").trimmingCharacters(in: .whitespaces)
            var due: String?
            for p in parts.dropFirst() {
                let t = p.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("截止") {
                    due = monthDayKey(String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces), todayKey: todayKey)
                }
            }
            // 「E-03 蝕刻機（製造一課）」機台那一段後面括號是部門；「（10/27 的警報）」是警報任務：拿掉括號那一段當名字
            if section == "機台", let r = title.range(of: "（") { title = String(title[..<r.lowerBound]) }
            title = title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            var item = OrgMoveIntakeItem(title: title, dueKey: due, section: section)
            if section == "機台" {
                let key = title.lowercased()
                item.equipmentId = world.equipment.first { $0.name.trimmingCharacters(in: .whitespaces).lowercased() == key }?.id
            }
            out.append(item)
        }
        return out
    }

    /// 「12. 標題…」→「標題…」（沒有編號＝nil）
    private static func numberedBody(_ line: String) -> String? {
        var digits = 0
        var idx = line.startIndex
        while idx < line.endIndex, line[idx].isNumber, line[idx].isASCII {
            digits += 1
            idx = line.index(after: idx)
        }
        guard digits > 0, idx < line.endIndex, line[idx] == "." else { return nil }
        return String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
    }

    /// 「11/20」→「2026-11-20」：今年這天在今天往前 60 天以內或以後＝今年，不然明年（交接文字只寫月／日）
    static func monthDayKey(_ s: String, todayKey: String) -> String? {
        let head = s.components(separatedBy: CharacterSet(charactersIn: "（( ")).first ?? s
        let mmdd = head.components(separatedBy: "/")
        guard mmdd.count == 2, let mo = Int(mmdd[0]), let d = Int(mmdd[1]), (1...12).contains(mo), (1...31).contains(d),
              let year = Int(todayKey.prefix(4)) else { return nil }
        let thisYear = String(format: "%04d-%02d-%02d", year, mo, d)
        // 2/30 這種不存在的日子：組回來的日子跟字對不上＝不讀（Calendar 會自己往後滾成 3/2）
        guard let t = date(fromKey: thisYear), dayKey(t) == thisYear else { return nil }
        if thisYear >= addDays(todayKey, -60) { return thisYear }
        let next = String(format: "%04d-%02d-%02d", year + 1, mo, d)
        guard let n = date(fromKey: next), dayKey(n) == next else { return nil }
        return next
    }
}

/// [v25.597 轉組織 v4] 固定會議〔暫停到 1/29〕做了什麼（存在那一列的 removedJSON；復原、改回來那天、照常用）
struct OrgMovePauseUndo: Codable, Equatable {
    /// 暫停時新建的「取消」場次（規則推導、原本沒有覆寫的那幾場）
    var createdIds: [UUID]?
    /// 原本就有覆寫（改期、有議程、加開）、暫停時改成取消的那幾場
    var flippedIds: [UUID]?
    /// 「2026-11-02」暫停從這天（含）
    var fromKey: String?
    /// 「2027-01-29」到這天（不含；回來那天）
    var untilKey: String?

    init(createdIds: [UUID]? = nil, flippedIds: [UUID]? = nil, fromKey: String? = nil, untilKey: String? = nil) {
        self.createdIds = createdIds
        self.flippedIds = flippedIds
        self.fromKey = fromKey
        self.untilKey = untilKey
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        createdIds = try? c.decodeIfPresent([UUID].self, forKey: .createdIds)
        flippedIds = try? c.decodeIfPresent([UUID].self, forKey: .flippedIds)
        fromKey = try? c.decodeIfPresent(String.self, forKey: .fromKey)
        untilKey = try? c.decodeIfPresent(String.self, forKey: .untilKey)
    }

    private enum CodingKeys: String, CodingKey {
        case createdIds, flippedIds, fromKey, untilKey
    }

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func decode(_ data: Data?) -> OrgMovePauseUndo? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(OrgMovePauseUndo.self, from: data)
    }
}

// MARK: - 卡片提示列（OrgMovePlan.personHint 第一行叫）

extension OrgMovePlan {
    /// 暫時離開那位同仁卡片的提示列：生效前「11/2 起借調・代理 3 件」、期間「借調中・到 1/29・代理 3 件（做完 1）」、
    /// 回來那天以後還沒按的「1/29 回來了・代理的 3 件還沒還」（〔還給本人〕〔留給代理人〕卡片另外放：returnAsk）。
    /// 到了生效日還沒套用（orgPending）的不接（照舊走 pendingPersonHint 的〔現在套用〕）；按過回來的不接。不是暫時離開＝nil
    static func tempPersonHint(personId: UUID, book: OrgMoveBook, world: OrgMoveWorld, now: Date) -> OrgMoveHint? {
        let todayKey = dayKey(now)
        let temps = book.live.filter { m in
            // [v4 驗證] 生效前取消了（cancelledAt）的不接：要退回這一件：拿掉 `&& m.cancelledAt == nil`
            m.isTemp && m.personId == personId && m.wasApplied && !m.isUndone && m.returnedAt == nil && m.returnKey != nil
                && m.cancelledAt == nil
        }.sorted { a, b in a.effectiveKey > b.effectiveKey }
        guard let m = temps.first, let ret = m.returnKey else { return nil }
        if m.orgPending && m.effectiveKey <= todayKey { return nil }
        let k = m.tempKindValue.label
        let map = OrgMoveHolderMap(world: world)
        let proxied = proxyCount(m.allLines)
        let left = returnItemCount(m, map: map)
        let done = max(0, proxied - left)
        let tail: String = proxied > 0 ? "・代理 \(proxied) 件" + (done > 0 ? "（做完 \(done)）" : "") : ""
        let text: String
        if todayKey < m.effectiveKey {
            text = "\(shortDay(m.effectiveKey)) 起\(k)・到 \(shortDay(ret))\(tail)"
        } else if todayKey < ret {
            text = "\(k)中・到 \(shortDay(ret))\(tail)"
        } else {
            guard left > 0 else { return nil }
            text = "\(shortDay(ret)) 回來了・代理的 \(left) 件還沒還"
        }
        return OrgMoveHint(moveId: m.id, text: text, badge: nil, warning: nil, isReceiver: false)
    }

    /// 轉進來那位同仁卡片的提示列（交接完成日以前）：「11/16 從品保課轉進來・接收清單 2 項」（點了打開那張單＝接收清單）。沒有＝nil
    static func intakeHint(personId: UUID, book: OrgMoveBook, todayKey: String) -> OrgMoveHint? {
        guard let m = book.live.filter({ $0.isIntake && $0.personId == personId && !$0.isUndone })
            .sorted(by: { $0.effectiveKey > $1.effectiveKey }).first,
              todayKey <= (m.handoverByKey ?? m.effectiveKey) else { return nil }
        let from = labelShort(m.from.deptLabel ?? "")
        let n = m.allLines.filter { $0.state != OrgMoveLineState.undone.rawValue }.count
        let head = from.isEmpty ? "\(shortDay(m.effectiveKey)) 轉進來" : "\(shortDay(m.effectiveKey)) 從\(from)轉進來"
        return OrgMoveHint(moveId: m.id, text: "\(head)・接收清單 \(n) 項", badge: nil, warning: nil, isReceiver: false)
    }
}
