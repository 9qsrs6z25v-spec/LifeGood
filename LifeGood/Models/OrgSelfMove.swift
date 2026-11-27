import Foundation

// MARK: - [v25.598 轉組織 v5] 我自己調動：先選哪些人跟我走，其餘一次轉出、一份全組交接單
//（orgmove/judge.md §7「v5 組織重整、我自己調動」那一列、§13 第 3／7 題；u2_cases.md S5；orgmove/build/v5/brief.md §2-3；sim_v5.py 對照）
//
// • 入口：你在履歷新增一筆「轉職」里程碑存好的那一刻（CareerView、ResumeView 的新增；OrgSelfMoveOffer 判斷要不要問）。
// • 跟我走的人：還是你的部屬。選了「一起調到 廠務部」就每人一張 kind "move" 的交接單（只改部門；東西都跟著本人）；部門照舊＝不開單。
// • 其餘的人：每人一張 kind "out"、部門照舊的交接單（「調出我的管轄」，收進部屬名單最下面「已轉出」）。預設：
//   沒做完的待辦、警報任務、週報〔交出去（給 接任的人）〕（從這位同仁身上拿掉、原樣存在交接單、提醒事項刪掉；不算任何人的分）；
//   過了報告日的週報〔不要了〕；缺失〔現在結案〕（§13 第 3 題：調出預設結案）；固定會議〔最後一場〕、只開一次的照舊；
//   機台、班、別人會議裡的議程、兼任、這位同仁的管理人員身分〔照舊〕（人沒換工作，只是不歸你管了）。
// • 生效日＝那筆轉職的日子：今天或以前＝按下去就全部做；在以後＝〔那天一起做〕（v1b：那天打開 App、你的手機、iCloud 拉完才自動做）。
// • 一份全組交接單＝OrgTeamMove（life_org_reorgs_v1）把這幾張串起來；每一張照舊在 life_org_moves_v1（套用、復原、到期、已轉出都走既有那一套）。
// • 字不用「他／她」；分享文字只在你自己按的分享（寫名字，分享前提醒含個資；不寫分數、考評、缺失、請假）。

/// 我自己調動的草稿（不存檔：按〔確認〕才變成幾張交接單＋一筆 OrgTeamMove）
struct OrgSelfMoveDraft: Equatable {
    /// 你履歷上那筆「轉職」里程碑
    var milestoneId: UUID?
    /// 生效日（＝里程碑的日子）
    var effective: Date
    /// 我原本的管理單位（快照字）、調到哪（「廠務部」）
    var fromUnit: String = ""
    var toUnit: String = ""
    /// 跟我走的人（部屬 id；預設沒有）
    var followerIds: Set<UUID> = []
    /// 跟我走的人一起調到的部門（nil＝部門照舊）
    var followerDeptId: UUID?
    /// 接任的人：組織人員 id（nil＝用打的名字）
    var successorOrgId: UUID?
    /// 打的名字（successorOrgId 有值時是那位的名字）
    var successorName: String = ""
    /// 打名字的接任者先配好的 id（重做也是同一個）
    var typedSuccessorId: UUID = UUID()

    init(milestoneId: UUID? = nil, effective: Date) {
        self.milestoneId = milestoneId
        self.effective = effective
    }
}

/// 「哪些人跟我走」那一頁的一列
struct OrgSelfMoveCandidate: Identifiable, Equatable {
    let id: UUID
    /// 「王小明」
    let name: String
    /// 「製造課・P1・E3 工程師」
    let sub: String
    /// 身上還沒交出去的件數（待辦＋週報＋機台；同刪除確認框）
    let openCount: Int
    /// 分組的部門名（「製造課」；沒部門＝「未分部門」）
    let deptName: String
}

/// 確認頁的一段
struct OrgSelfMovePreview: Equatable {
    /// 「2027/1/1 我調到 廠務部」
    let title: String
    let lines: [String]
    /// 擋住的原因（nil＝可以按）
    let block: String?
    /// 按鈕的字（「確認：2 位跟我走、19 位轉出」）
    let confirmTitle: String
}

/// 一份全組交接單那一頁的一列（一位同仁一張）
struct OrgTeamSheetRow: Identifiable, Equatable {
    let moveId: UUID
    let personId: UUID
    /// 「王小明」
    let name: String
    /// 「跟我走・調到廠務部」「已轉出・交出去 3 項」「1/1 轉出（排好了）」「已復原」
    let detail: String
    let isFollower: Bool
    var id: UUID { moveId }
}

enum OrgSelfMovePlan {

    // MARK: 要不要問

    /// 剛存好的這筆里程碑要不要問「你調動了，哪些人跟你走？」：轉職、還有在職的部屬、這筆還沒有全組交接單
    static func shouldOffer(milestone m: LifeMilestone, activeCount: Int, book: OrgReorgBook) -> Bool {
        guard m.category == .career, m.careerSubCategory == .transfer, activeCount > 0 else { return false }
        return !book.liveTeams.contains { $0.milestoneId == m.id }
    }

    /// 問的那一句（確認框）
    static func offerAsk(milestone m: LifeMilestone, activeCount: Int) -> (title: String, message: String) {
        let unit = toUnitText(m)
        let to = unit.isEmpty ? "新單位" : unit
        return ("你調到\(to)了，部屬要一起整理嗎？",
                "先選哪些人跟你走，其餘 \(activeCount) 位裡沒選的一次轉出（收進部屬名單最下面「已轉出」，卡片、歷史、分數都留著），留一份全組交接單給接任的人。")
    }

    /// 里程碑上的新單位：管理單位優先，沒有用部門
    static func toUnitText(_ m: LifeMilestone) -> String {
        let unit = (m.managedUnit ?? "").trimmingCharacters(in: .whitespaces)
        if !unit.isEmpty { return unit }
        return (m.department ?? "").trimmingCharacters(in: .whitespaces)
    }

    // MARK: 第一頁：誰跟我走

    /// 在職的部屬（照部門、再照名字）
    static func candidates(world: OrgMoveWorld) -> [OrgSelfMoveCandidate] {
        let list = world.activeSubordinates.sorted { a, b in
            let da = world.deptShort(a.departmentId)
            let db = world.deptShort(b.departmentId)
            if da != db { return da.localizedStandardCompare(db) == .orderedAscending }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return list.map { s in
            let dept = world.deptShort(s.departmentId)
            let parts = [dept, s.plantArea.trimmingCharacters(in: .whitespaces),
                         world.titleLabel(gradeTitleId: s.gradeTitleId, jobTitle: s.jobTitle)]
            let sub = parts.filter { !$0.isEmpty }.joined(separator: "・")
            let n = s.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return OrgSelfMoveCandidate(id: s.id, name: n.isEmpty ? "這位同仁" : n, sub: sub,
                                        openCount: OrgMovePlan.openItemCount(personId: s.id, world: world),
                                        deptName: dept.isEmpty ? "未分部門" : dept)
        }
    }

    /// 跟我走的人預設調到的部門：名稱跟新單位一樣的（挑得到的）部門；沒有＝nil（部門照舊）
    static func defaultFollowerDept(toUnit: String, world: OrgMoveWorld) -> UUID? {
        let u = toUnit.trimmingCharacters(in: .whitespaces)
        guard !u.isEmpty else { return nil }
        return OrgReorgPlan.pickable(world.departments).first { $0.name.trimmingCharacters(in: .whitespaces) == u }?.id
    }

    /// 接任的人挑人頁：沒離職、不是在職部屬的組織人員（新單位以外；照名字）
    static func successorCandidates(world: OrgMoveWorld) -> [OrgMoveHandOutCandidate] {
        let activeIds = Set(world.activeSubordinates.map(\.id))
        let pool = world.orgPeople.filter { p in
            guard !p.isInactive else { return false }
            if let sid = p.linkedSubordinateId, activeIds.contains(sid) { return false }
            return !p.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let sorted = pool.sorted { a, b in a.name.localizedStandardCompare(b.name) == .orderedAscending }
        return sorted.map { p in
            let parts = [world.deptShort(p.departmentId), p.jobTitle.trimmingCharacters(in: .whitespaces)]
            let sub = parts.filter { !$0.isEmpty }.joined(separator: "・")
            return OrgMoveHandOutCandidate(id: p.id, name: p.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                           sub: sub, isMe: false)
        }
    }

    /// 接任的人（id、名字）：挑的組織人員、或打的名字（都沒有＝nil）
    static func successor(_ d: OrgSelfMoveDraft, world: OrgMoveWorld) -> (id: UUID, name: String, isOrg: Bool)? {
        if let oid = d.successorOrgId {
            let n = world.orgPersonName(oid)
            if !n.isEmpty { return (oid, n, true) }
        }
        let typed = d.successorName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return nil }
        return (d.typedSuccessorId, typed, false)
    }

    // MARK: 每一張交接單

    /// 其餘的人（一次轉出）那一張的預設（buildLines 的調出預設之後再蓋一次）
    static func applySelfMoveDefaults(_ lines: inout [OrgMoveLine], personId: UUID, successorId: UUID,
                                      successorName: String, world: OrgMoveWorld) {
        for i in lines.indices {
            let l = lines[i]
            switch l.lineKind {
            case .some(.task):
                if l.lineLock == .dereliction {
                    setAction(&lines[i], .closeNow)
                } else {
                    setHandOut(&lines[i], to: successorId, name: successorName)
                }
            case .some(.alarmTask):
                setHandOut(&lines[i], to: successorId, name: successorName)
            case .some(.report):
                if l.lineLock == .pastDue {
                    setAction(&lines[i], .drop)
                } else {
                    setHandOut(&lines[i], to: successorId, name: successorName)
                }
            case .some(.equipment), .some(.shifts), .some(.sideRole):
                setAction(&lines[i], .follow)
            case .some(.meeting):
                let recurring = OrgMovePlan.meeting(l, world: world)
                    .map { OrgMovePlan.meetingFacts($0, cutKey: l.dueKey ?? "").isRecurring } ?? false
                setAction(&lines[i], recurring ? .end : .follow)
            case .some(.agenda):
                // 自己會議裡的：跟著會議（會議最後一場之後就停了）；別人會議裡的照預設（交回會議主人）
                if l.holderId == nil || l.holderId == personId || l.action == nil { setAction(&lines[i], .follow) }
            case .some(.manager):
                setAction(&lines[i], .keep)
            case .some(.managerAdd):
                setAction(&lines[i], .skip)
            case .none:
                if l.action == nil && !l.isCustom { setAction(&lines[i], .follow) }
            }
        }
    }

    private static func setAction(_ l: inout OrgMoveLine, _ a: OrgMoveAction) {
        l.action = a.rawValue
        l.toId = nil
        l.toName = nil
    }

    private static func setHandOut(_ l: inout OrgMoveLine, to id: UUID, name: String) {
        l.action = OrgMoveAction.handOut.rawValue
        l.toId = id
        l.toName = name
    }

    /// 組好的那幾張（還沒套用）＋那一份全組交接單。followers＝跟我走的（kind move，部門照舊就沒有）、outs＝其餘一次轉出的
    static func buildMoves(_ d: OrgSelfMoveDraft, world: OrgMoveWorld, now: Date)
        -> (followers: [OrgMove], outs: [OrgMove], team: OrgTeamMove)? {
        guard let succ = successor(d, world: world) else { return nil }
        let effKey = OrgMovePlan.dayKey(d.effective)
        let future = effKey > OrgMovePlan.dayKey(now)
        let active = world.activeSubordinates
        var followers: [OrgMove] = []
        var outs: [OrgMove] = []
        for s in active where d.followerIds.contains(s.id) {
            guard let to = d.followerDeptId, to != s.departmentId else { continue }
            var draft = OrgMoveDraft(personId: s.id, effective: d.effective)
            draft.kind = .move
            draft.toDeptId = to
            draft.timing = .together
            draft.retitleBirthday = false
            draft.lines = OrgMovePlan.buildLines(personId: s.id, kind: .move, deptChanges: true, effectiveKey: effKey,
                                                 world: world, now: now)
            for i in draft.lines.indices { draft.lines[i].updatedAt = now }
            var m = OrgMovePlan.makeMove(draft, world: world, now: now)
            if !future { m.timing = OrgMoveTiming.now.rawValue }
            followers.append(m)
        }
        for s in active where !d.followerIds.contains(s.id) {
            var draft = OrgMoveDraft(personId: s.id, effective: d.effective)
            draft.kind = .out
            draft.keepDept = true
            draft.toDeptId = s.departmentId
            draft.timing = .together
            draft.retitleBirthday = false
            var lines = OrgMovePlan.buildLines(personId: s.id, kind: .out, deptChanges: false, effectiveKey: effKey,
                                               world: world, now: now)
            applySelfMoveDefaults(&lines, personId: s.id, successorId: succ.id, successorName: succ.name, world: world)
            for i in lines.indices { lines[i].updatedAt = now }
            draft.lines = lines
            outs.append(OrgMovePlan.makeMove(draft, world: world, now: now))
        }
        let team = OrgTeamMove(effectiveKey: effKey, milestoneId: d.milestoneId,
                               fromUnit: d.fromUnit.isEmpty ? nil : d.fromUnit,
                               toUnit: d.toUnit.isEmpty ? nil : d.toUnit,
                               followerIds: active.filter { d.followerIds.contains($0.id) }.map(\.id),
                               followerDeptId: d.followerDeptId,
                               followerMoveIds: followers.map(\.id), moveIds: outs.map(\.id),
                               successorId: succ.id, successorName: succ.name, successorIsOrg: succ.isOrg,
                               createdAt: now, updatedAt: now)
        return (followers, outs, team)
    }

    // MARK: 確認頁

    static func preview(_ d: OrgSelfMoveDraft, world: OrgMoveWorld, now: Date) -> OrgSelfMovePreview {
        let effKey = OrgMovePlan.dayKey(d.effective)
        let future = effKey > OrgMovePlan.dayKey(now)
        let to = d.toUnit.trimmingCharacters(in: .whitespaces)
        let title = "\(OrgMovePlan.fullDay(effKey)) 我調到\(to.isEmpty ? "新單位" : to)"
        let active = world.activeSubordinates
        let fol = active.filter { d.followerIds.contains($0.id) }
        let rest = active.filter { !d.followerIds.contains($0.id) }
        let succ = successor(d, world: world)
        var lines: [String] = []
        if fol.isEmpty {
            lines.append("跟我走：沒有")
        } else {
            let names = fol.map { world.name($0.id) }.joined(separator: "、")
            if let did = d.followerDeptId {
                lines.append("跟我走 \(fol.count) 位：\(names)（調到\(world.deptShort(did))，東西都跟著本人）")
            } else {
                lines.append("跟我走 \(fol.count) 位：\(names)（部門照舊，還是你的部屬）")
            }
        }
        if !rest.isEmpty {
            lines.append("其餘 \(rest.count) 位一次轉出：收進部屬名單最下面「已轉出」，卡片、歷史、分數都留著")
            var handed = 0
            for s in rest {
                handed += OrgMovePlan.openItemCount(personId: s.id, world: world)
            }
            let who = succ?.name ?? "接任的人"
            lines.append("沒做完的待辦、週報交出去給 \(who)（從同仁身上拿掉、留在交接單；不算任何人的分）")
            lines.append("機台、班、兼任照舊在本人身上；固定會議到 \(OrgMovePlan.shortDay(effKey)) 前一場結束；缺失現在結案")
            if handed > 0 { lines.append("一共 \(handed) 項（含機台）寫進一份全組交接單，可以分享給 \(who)") }
        }
        if future {
            lines.append("\(OrgMovePlan.shortDay(effKey)) 以前什麼都不動；\(OrgMovePlan.shortDay(effKey)) 打開 App 時一起做（在你自己的手機上）")
        }
        var block: String?
        if active.isEmpty {
            block = "沒有在職的部屬"
        } else if succ == nil && !rest.isEmpty {
            block = "請選接任的人（組織裡的人，或打名字）"
        }
        let confirm: String
        if rest.isEmpty {
            confirm = "確認：\(fol.count) 位跟我走"
        } else if fol.isEmpty {
            confirm = "確認：\(rest.count) 位轉出"
        } else {
            confirm = "確認：\(fol.count) 位跟我走、\(rest.count) 位轉出"
        }
        return OrgSelfMovePreview(title: title, lines: lines, block: block, confirmTitle: confirm)
    }

    // MARK: 一份全組交接單

    /// 單頭「2027/1/1 我調到廠務部　全組交接單」「交給 趙志明・19 位轉出・2 位跟我走」
    static func teamHeader(_ t: OrgTeamMove) -> (title: String, sub: String) {
        let to = (t.toUnit ?? "").trimmingCharacters(in: .whitespaces)
        let title = "\(OrgMovePlan.fullDay(t.effectiveKey)) 我調到\(to.isEmpty ? "新單位" : to)　全組交接單"
        var parts: [String] = []
        let who = (t.successorName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !who.isEmpty { parts.append("交給 \(who)") }
        parts.append("\(t.allMoveIds.count) 位轉出")
        if !t.allFollowerIds.isEmpty { parts.append("\(t.allFollowerIds.count) 位跟我走") }
        return (title, parts.joined(separator: "・"))
    }

    /// 一位同仁一列（跟我走的在前；照名字）
    static func teamRows(_ t: OrgTeamMove, book: OrgMoveBook, world: OrgMoveWorld) -> [OrgTeamSheetRow] {
        var out: [OrgTeamSheetRow] = []
        for (ids, isF) in [(t.allFollowerMoveIds, true), (t.allMoveIds, false)] {
            var rows: [OrgTeamSheetRow] = []
            for id in ids {
                guard let m = book.move(id) else { continue }
                let name = m.personName.isEmpty ? "這位同仁" : m.personName
                rows.append(OrgTeamSheetRow(moveId: m.id, personId: m.personId, name: name,
                                            detail: rowDetail(m, isFollower: isF, world: world), isFollower: isF))
            }
            rows.sort { a, b in a.name.localizedStandardCompare(b.name) == .orderedAscending }
            out.append(contentsOf: rows)
        }
        return out
    }

    static func rowDetail(_ m: OrgMove, isFollower: Bool, world: OrgMoveWorld) -> String {
        if m.isUndone { return "已復原" }
        // [v5 驗證] 排在以後、還沒生效就〔復原這次調動〕的（取消＋墓碑，什麼都沒做過）：不是「已轉出」
        if m.isCancelled || m.deletedAt != nil { return "已取消（沒有生效）" }
        if m.isPlanned {
            return isFollower ? "\(OrgMovePlan.shortDay(m.effectiveKey)) 跟我走（排好了）" : "\(OrgMovePlan.shortDay(m.effectiveKey)) 轉出（排好了）"
        }
        if isFollower {
            let d = world.deptShort(m.to.deptId)
            return d.isEmpty ? "跟我走" : "跟我走・調到\(d)"
        }
        let n = m.allLines.filter { $0.lineAction == .handOut && $0.state == OrgMoveLineState.done.rawValue }.count
        return n > 0 ? "已轉出・交出去 \(n) 項" : "已轉出"
    }

    /// 分享文字（給接任的人）：每位一段（照 OrgMovePlan.shareText 只寫交出去給接任者的那幾項），沒有東西的不寫。
    /// 不寫分數、考評、缺失、請假、任務備註（同 shareText）
    static func teamShareText(_ t: OrgTeamMove, book: OrgMoveBook, map: OrgMoveHolderMap, world: OrgMoveWorld) -> String {
        let head = teamHeader(t)
        var out: [String] = [head.title, head.sub]
        var empty: [String] = []
        // [v5 驗證] 取消了的（排在以後、生效前就〔復原這次調動〕）也不寫：什麼都沒交出去
        let moves: [OrgMove] = t.allMoveIds.compactMap { book.move($0) }
            .filter { !$0.isUndone && !$0.isCancelled && $0.deletedAt == nil }
            .sorted { a, b in a.personName.localizedStandardCompare(b.personName) == .orderedAscending }
        for m in moves {
            guard let sid = t.successorId,
                  m.allLines.contains(where: { $0.lineAction == .handOut && $0.toId == sid && $0.state != OrgMoveLineState.undone.rawValue }) else {
                empty.append(m.personName.isEmpty ? "這位同仁" : m.personName)
                continue
            }
            out.append("")
            out.append(OrgMovePlan.shareText(m, receiverId: sid, map: map, world: world))
        }
        if !empty.isEmpty {
            out.append("")
            out.append("沒有要交的：" + empty.joined(separator: "、"))
        }
        return out.joined(separator: "\n")
    }

    /// 分享前的提醒（同交接單：會寫名字和手上的工作）
    static func teamShareWarning(_ t: OrgTeamMove) -> (title: String, message: String) {
        let n = t.allMoveIds.count
        let who = (t.successorName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let to = who.isEmpty ? "" : "和\(who)"
        return ("要分享全組交接單嗎？",
                "這份會寫出 \(n) 位同仁\(to)的名字和手上的工作，傳出去就收不回來了。分數、考評、缺失、請假不會放進去。")
    }

    /// 整份能不能〔復原〕：裡面還有一張能復原、或還沒生效（排好的）的
    static func canUndoTeam(_ t: OrgTeamMove, book: OrgMoveBook, todayKey: String) -> Bool {
        t.everyMoveId.contains { id in
            guard let m = book.move(id) else { return false }
            return OrgMovePlan.canUndo(m, todayKey: todayKey) || (m.isPlanned && m.deletedAt == nil)
        }
    }

    static func undoTeamAsk(_ t: OrgTeamMove) -> (title: String, message: String) {
        ("復原這次調動？",
         "轉出的同仁回到在職，交出去的待辦、週報放回本人身上；跟我走的同仁部門改回去。之後你自己改過的不動。排好還沒生效的直接取消。")
    }
}
