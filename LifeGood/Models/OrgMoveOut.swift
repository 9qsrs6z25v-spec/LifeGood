import Foundation

// MARK: - [v25.593 轉組織 v2] 調出、離職、退休：規則、字（OrgMovePlan 的延伸）
//（orgmove/judge.md §2.2「已轉出也用算的」、§3.2「轉出」那一欄、§3.6、§4.7、§4.8、§4.9、§5-2、§5-32、§5-34、§7 v2、§13 第 3／7／9 題；
//  orgmove/build/v2/brief.md §2；sim_v2.py 一個函式一個函式對照）
//
// • 「已轉出」不存在部屬身上（Subordinate／OrgPerson／Department 加欄位會被還沒更新的 iPad 洗掉）：用交接單算——
//   最後一張組織做完了的「調出／離職／退休／回到我的部屬」是調出、離職、退休的那位＝已轉出（OrgMoveIndex.archived）。
//   〔回到我的部屬〕記成另一張 kind "back" 的交接單（每個欄位 25.592 的 App 都認得，舊 iPad 存回來也洗不掉）。
// • 已轉出的人照樣在 LifeStore.subordinates 裡（分數、議程負責人、兼任、@ 標註、互評、機台歷史都靠部屬 id 找人）；
//   讀「在職的」改讀 LifeStore.activeSubordinates／OrgMoveIndex.activeOnly（小工具、會議通知、今天時間軸、挑人清單…）。
// • 預設（調出、離職、退休）：一般待辦、機台、班＝還沒決定（必選：確認前要選完）；缺失＝現在結案（−1 算本人）；
//   週報＝不要了（生效前到期的照舊這位同仁自己交）；固定會議＝最後一場；自己會議裡的議程＝還沒決定；兼任＝照舊（離職、退休＝還沒決定）；
//   管理人員＝拿掉。多一種〔交出去…〕：給不在部屬名單的人（組織人員）或給「我」（部屬總覽「我接的」）。
// • 字的規矩：不用「他／她」，寫名字或「這位同仁」。這裡的字只在 App 內頁與你自己按的分享；
//   通知、小工具、手錶、鎖定畫面一個字都沒加（不寫名字、部門、是調走還是離職）。

/// 部屬名單最下面「已轉出（1）」那一區的一列（judge §3.6、§4.8）
struct OrgMoveArchivedRow: Identifiable, Equatable {
    let personId: UUID
    /// 那一張調出／離職／退休的交接單
    let moveId: UUID
    /// 「王小明」
    let name: String
    /// 「11/1 轉到品保課」「11/1 調出」「11/1 離職」「11/1 退休」
    let detail: String
    /// 排序用「2026-11-01」
    let effectiveKey: String
    var id: UUID { personId }
}

/// 部屬總覽「我接的（1）」的一列（〔交出去〕給「我」的待辦、週報、自己加的一項；judge §3.6、§5-34）
struct OrgMoveMineRow: Identifiable, Equatable {
    let moveId: UUID
    let lineId: UUID
    /// 「E-03 腔體漏率改善」
    let title: String
    /// 「從王小明・11/1・原訂 11/9」
    let detail: String
    /// 打勾收掉了
    let checked: Bool
    var id: UUID { lineId }
}

/// 〔交出去…〕挑人頁的一列：組織人員（不在部屬名單的人）或「我」
struct OrgMoveHandOutCandidate: Identifiable, Equatable {
    /// 組織人員 id；「我」＝OrgMovePlan.meId
    let id: UUID
    /// 「黃冠宇」「我」
    let name: String
    /// 「品保課・課長」「我先接：放在部屬總覽「我接的」，不算任何人的分數」
    let sub: String
    let isMe: Bool
}

/// 班表那個月要列的一位（照那天在哪個部門；judge §5-32、v1a-1 adjudicate §8-17）
struct OrgMoveRosterMember: Equatable {
    let personId: UUID
    /// 分組用的廠區（這個月在這個部門的最後那一天的廠區）
    let plant: String
}

extension OrgMovePlan {

    /// 〔交出去〕給「我」：toId 寫這個（同互評票的「我」）
    static let meId: UUID = PerformanceBallot.selfRaterId
    /// 看板頭像旁、名單那一列的膠囊字
    static let archivedChipText = "已轉出"

    // MARK: 已轉出

    /// 「11/1 轉到品保課」「11/1 調出」（部門照舊）「11/1 離職」「11/1 退休」
    static func archivedText(_ a: OrgMoveIndex.Archived, world: OrgMoveWorld) -> String {
        let d = shortDay(a.effectiveKey)
        switch OrgMoveKind(rawValue: a.kind) {
        case .some(.resign): return "\(d) 離職"
        case .some(.retire): return "\(d) 退休"
        default:
            let now = a.toDeptId.map { world.deptShort($0) } ?? ""
            let name = now.isEmpty ? labelShort(a.toDeptLabel) : now
            return name.isEmpty ? "\(d) 調出" : "\(d) 轉到\(name)"
        }
    }

    /// 這位同仁已轉出的那一句（在職＝nil）
    static func archivedText(personId: UUID, world: OrgMoveWorld) -> String? {
        guard let a = OrgMoveIndex.archived[personId] else { return nil }
        return archivedText(a, world: world)
    }

    /// 部屬名單最下面「已轉出（N）」（生效日新的在前；同一天照名字）
    static func archivedRows(world: OrgMoveWorld) -> [OrgMoveArchivedRow] {
        var out: [OrgMoveArchivedRow] = []
        for s in world.subordinates {
            guard let a = OrgMoveIndex.archived[s.id] else { continue }
            let n = s.name.trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(OrgMoveArchivedRow(personId: s.id, moveId: a.moveId, name: n.isEmpty ? "這位同仁" : n,
                                          detail: archivedText(a, world: world), effectiveKey: a.effectiveKey))
        }
        return out.sorted { a, b in
            if a.effectiveKey != b.effectiveKey { return a.effectiveKey > b.effectiveKey }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// 卡片看板下那一條（已轉出，灰）：「11/1 轉到品保課（已轉出）」；那張單還有待分派的多橘點「待分派 1」（judge §4.7）
    /// [v25.593 轉組織 v2 裁定] 還在交接中的那幾天，⚠ 照樣寫出來（同 personHint 的三種：又回到原人身上、部門／組織圖又被改回去、
    /// 在兩個人身上；judge §4.7 v1a 那幾列）。已轉出的人不在任何清單，提示列不寫就沒人看得到：還沒更新的 iPad 沒拉到就存回來、
    /// 25.592 的 iPad 先打開而只做了一半（部門沒改、組織人員沒標已離職）時，你在卡片上就看得到，點進交接單〔再交一次〕〔再改一次〕。
    /// 平常（沒有 ⚠）跟 v2 原本一模一樣。要退回這一件：warning 改回 nil、刪 archivedWarning
    static func archivedHint(personId: UUID, book: OrgMoveBook, world: OrgMoveWorld, now: Date) -> OrgMoveHint? {
        guard let a = OrgMoveIndex.archived[personId], let m = book.move(a.moveId) else { return nil }
        let text = archivedText(a, world: world) + "（已轉出）"
        var badge: String?
        var warning: String?
        if isOpen(m, todayKey: dayKey(now)) {
            let map = OrgMoveHolderMap(world: world)
            let pend = tiles(m, map: map, world: world, now: now).first(where: { $0.id == "pending" })?.value ?? "0"
            badge = pend == "0" ? nil : "待分派 \(pend)"
            warning = archivedWarning(m, map: map, world: world, now: now)
        }
        return OrgMoveHint(moveId: m.id, text: text, badge: badge, warning: warning, isReceiver: false, muted: true)
    }

    /// [v25.593 轉組織 v2 裁定] 已轉出那一條的 ⚠（字、先後同 personHint：又回到原人身上 → 組織那一列 → 在兩個人身上）。沒有＝nil
    private static func archivedWarning(_ m: OrgMove, map: OrgMoveHolderMap, world: OrgMoveWorld, now: Date) -> String? {
        var back = 0
        var both = 0
        for l in m.allLines where !l.isOrgLine {
            let k: OrgMoveLineStatus.Kind = status(l, in: m, map: map, now: now).kind
            if k == .backOnPerson { back += 1 }
            if k == .onBoth { both += 1 }
        }
        let person = m.personName.isEmpty ? "這位同仁" : m.personName
        if back > 0 { return "有 \(back) 項又回到\(person)身上" }
        let org = orgStatus(m, world: world, now: now)
        if !org.ok { return org.text.replacingOccurrences(of: "⚠ ", with: "") }
        if both > 0 { return "有 \(both) 項在兩個人身上" }
        return nil
    }

    /// 已轉出的卡片最上面那一行（唯讀感）：「已轉出（11/1 轉到品保課）：卡片、歷史、分數都留著；要再交事情給這位同仁，先〔回到我的部屬〕」
    static func archivedReadOnlyNote(personId: UUID, world: OrgMoveWorld) -> String? {
        guard let t = archivedText(personId: personId, world: world) else { return nil }
        return "已轉出（\(t)）：卡片、歷史、分數都留著；要再交事情給這位同仁，先〔回到我的部屬〕"
    }

    // MARK: 回到我的部屬

    /// 〔回到我的部屬〕的確認框（不用訂閱：把設錯的收回來，同〔復原〕）
    static func returnAsk(personId: UUID, world: OrgMoveWorld) -> (title: String, message: String) {
        let person = world.name(personId)
        var msg = "回到部屬名單、總覽、小工具、班表、互評名單。"
        if let a = OrgMoveIndex.archived[personId], OrgMoveKind(rawValue: a.kind)?.isLeaveCompany == true,
           world.orgPerson(linkedTo: personId) != nil {
            msg += "組織圖上的「已離職」會拿掉。"
        }
        let dept = world.deptShort(world.sub(personId)?.departmentId)
        if !dept.isEmpty { msg += "部門照舊是\(dept)；要改部門請再按〔轉組織〕。" }
        msg += "之前交出去的事不會拿回來。"
        return ("\(person)回到你的部屬名單？", msg)
    }

    /// 回到我的部屬那一張（LifeStore.returnArchivedSubordinate 存下來）：什麼都不搬、一存就是收起來的（closed）。
    /// 在職的（沒有已轉出）＝nil
    static func makeBackMove(personId: UUID, world: OrgMoveWorld, now: Date) -> OrgMove? {
        guard let s = world.sub(personId), OrgMoveIndex.archived[personId] != nil else { return nil }
        let label = world.deptLabel(s.departmentId)
        let side = OrgMoveSide(deptId: s.departmentId, deptLabel: label.isEmpty ? s.department : label,
                               plant: s.plantArea, gradeTitleId: s.gradeTitleId,
                               titleLabel: world.titleLabel(gradeTitleId: s.gradeTitleId, jobTitle: s.jobTitle))
        let k = dayKey(now)
        return OrgMove(personId: personId, personName: world.name(personId), kind: OrgMoveKind.back.rawValue,
                       effectiveKey: k, handoverByKey: k, timing: OrgMoveTiming.now.rawValue, from: side, to: side,
                       state: OrgMoveState.closed.rawValue, handedAt: now, appliedAt: now, closedAt: now,
                       lines: [], createdAt: now, updatedAt: now)
    }

    // MARK: 第 ① 步：這次是〔調出我的管轄〕〔離職〕〔退休〕

    /// 這個部門是不是你帶的：你履歷上現在的管理單位就是這個名字，或這個部門有你別的在職部屬。
    /// 不是＝〔換單位〕選了它要先問「調過去之後還是你的部屬嗎？」（judge §3.6；沒有部門＝當成是，不問）
    static func isMyDept(_ deptId: UUID?, personId: UUID, world: OrgMoveWorld) -> Bool {
        guard let did = deptId, let d = world.dept(did) else { return true }
        let unit = (world.myManagedUnit ?? "").trimmingCharacters(in: .whitespaces)
        if !unit.isEmpty, unit == d.name.trimmingCharacters(in: .whitespaces) { return true }
        return world.activeSubordinates.contains { $0.id != personId && $0.departmentId == did }
    }

    /// 「王小明調到品保課之後，還是你的部屬嗎？」〔不是了〕〔還是我的部屬〕（judge §3.6：App 不自己猜）
    static func stillMineAsk(deptId: UUID?, personId: UUID, world: OrgMoveWorld) -> (title: String, message: String) {
        let person = world.name(personId)
        let dept = world.deptShort(deptId)
        let d = dept.isEmpty ? "那個部門" : dept
        let msg = "\(d)沒有你的其他部屬。選〔不是了〕：交接完收進部屬名單最下面「已轉出」，小工具、會議通知、班表、互評都不再出現；卡片、歷史、分數都留著。"
        return ("\(person)調到\(d)之後，還是你的部屬嗎？", msg)
    }

    /// 〔交出去…〕挑人頁：第一列「我」，再來是不在部屬名單、沒離職的組織人員——新部門的管理人員排前面（黃冠宇），再來新部門的人，其他照名字
    static func handOutCandidates(personId: UUID, toDeptId: UUID?, world: OrgMoveWorld) -> [OrgMoveHandOutCandidate] {
        var out: [OrgMoveHandOutCandidate] = [
            OrgMoveHandOutCandidate(id: meId, name: "我", sub: "我先接：放在部屬總覽「我接的」，不算任何人的分數", isMe: true)
        ]
        let activeIds = Set(world.activeSubordinates.map(\.id))
        let selfOrg: UUID? = world.orgPerson(linkedTo: personId)?.id
        let managers: [UUID] = toDeptId.flatMap { world.dept($0)?.managerIds } ?? []
        let pool = world.orgPeople.filter { p in
            guard !p.isInactive, p.id != selfOrg else { return false }
            if let sid = p.linkedSubordinateId, activeIds.contains(sid) { return false }
            return !p.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        func rank(_ p: OrgPerson) -> Int {
            if let i = managers.firstIndex(of: p.id) { return i }
            if toDeptId != nil, p.departmentId == toDeptId { return 1000 }
            return 2000
        }
        let sorted = pool.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        for p in sorted {
            let parts = [world.deptShort(p.departmentId), p.jobTitle.trimmingCharacters(in: .whitespaces)]
            let sub = parts.filter { !$0.isEmpty }.joined(separator: "・")
            out.append(OrgMoveHandOutCandidate(id: p.id, name: p.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                               sub: sub, isMe: false))
        }
        return out
    }

    /// 調出、離職、退休：還有沒決定的就不能確認（judge §3.6「交給…（必選）」）。nil＝可以按〔確認交接〕
    static func confirmBlock(_ draft: OrgMoveDraft) -> String? {
        guard draft.kind.isLeaving else { return nil }
        let t = tally(draft.lines)
        guard t.undecided > 0 else { return nil }
        let when: String
        switch draft.kind {
        case .resign: when = "離職之後"
        case .retire: when = "退休之後"
        default: when = "調出之後"
        }
        return "還有 \(t.undecided) 項還沒決定：\(when)這位同仁不在名單裡，請選交給誰（或〔交出去〕〔不要了〕）"
    }

    // MARK: 第 ② 步：預設、選項、膠囊

    /// 調出、離職、退休的預設（buildLines 最後呼叫；換單位、只換廠區不動）
    static func applyLeavingDefaults(_ lines: inout [OrgMoveLine], kind: OrgMoveKind, personId: UUID, world: OrgMoveWorld) {
        guard kind.isLeaving else { return }
        for i in lines.indices {
            let l = lines[i]
            switch l.lineKind {
            case .some(.task):
                // 缺失：現在結案（−1 算本人；judge 第 3 題）。其他照舊（還沒決定；連到要交的機台的跟著機台）
                if l.lineLock == .dereliction { lines[i].action = OrgMoveAction.closeNow.rawValue }
            case .some(.report):
                // 過了報告日的、生效以後的：不要了（扣分留本人）；生效前到期的照舊〔跟著〕（這位同仁自己交）；PM 跟著機台的照舊
                if l.lineLock == .pastDue || l.action == nil { lines[i].action = OrgMoveAction.drop.rawValue }
            case .some(.equipment), .some(.shifts):
                // 必選：機台交給…／待分派；班交給…／這幾天清掉（調出之後不能掛在已轉出的人身上）
                lines[i].action = nil
            case .some(.meeting):
                // 固定會議：最後一場；只開一次的：還沒決定（交給…）
                let recurring = meeting(l, world: world).map { meetingFacts($0, cutKey: l.dueKey ?? "").isRecurring } ?? false
                lines[i].action = recurring ? OrgMoveAction.end.rawValue : nil
            case .some(.agenda):
                // 自己會議裡的：還沒決定（會議結束了，要改由誰或不要了）；別人會議裡的照舊交回會議主人
                if l.holderId == nil || l.holderId == personId { lines[i].action = nil }
            case .some(.sideRole):
                // 調出：照舊（兼任跨部門）；離職、退休：還沒決定（到兼任換人）
                if kind.isLeaveCompany { lines[i].action = nil }
            default:
                break
            }
        }
    }

    /// 調出、離職、退休這一列能選的：待辦、週報、自己加的一項多〔交出去…〕；機台、會議、班拿掉〔跟著〕〔照舊〕
    static func leavingChoices(_ base: [OrgMoveChoice], line: OrgMoveLine, kind: OrgMoveKind) -> [OrgMoveChoice] {
        guard kind.isLeaving else { return base }
        if line.isCustom { return insertHandOut(base) }
        switch line.lineKind {
        case .some(.equipment), .some(.meeting), .some(.shifts):
            return base.filter { $0.action != .follow }
        case .some(.task), .some(.report):
            // 缺失（跟著／現在結案）、過了報告日（跟著／不要了）、警報任務（跟著機台）照舊
            guard line.lineLock == nil else { return base }
            return insertHandOut(base)
        default:
            return base
        }
    }

    private static func insertHandOut(_ base: [OrgMoveChoice]) -> [OrgMoveChoice] {
        var out = base
        let c = OrgMoveChoice(action: .handOut, label: "交出去…（不在部屬名單的人、我）", needsPerson: true)
        if let i = out.firstIndex(where: { $0.action == .give }) {
            out.insert(c, at: i + 1)
        } else {
            out.append(c)
        }
        return out
    }

    // MARK: 任務〔拆成兩件〕（judge §5-3：兩件各算一次分，所以不預設；第 ② 步一般待辦那一列的選單最下面）

    /// 這一列能不能〔拆成兩件…〕：一般待辦（不是缺失、警報任務、兼任、自己加的）。換單位、只換廠區也給
    static func canSplit(_ line: OrgMoveLine) -> Bool {
        line.lineKind == .task && line.lineLock == nil && !line.isCustom && line.refId != nil
    }

    /// 第二件預設的名字「整理 11 月報表（二）」（框裡可以改）
    static func splitDefaultTitle(_ title: String) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return (t.isEmpty ? "這件事" : t) + "（二）"
    }

    /// 〔拆成兩件…〕框的說明（不寫分數以外的個資）
    static let splitAskMessage = "兩件各算一次分（做完的人各拿各的），可以各交給不同的人。第一件不變；第二件的內容、截止日、關聯機台照第一件。現在就拆：沒按〔確認交接〕也會留著兩件。"

    /// 〔交出去〕那一列的對象（組織人員或「我」）；不是〔交出去〕＝nil
    static func handOutTarget(_ line: OrgMoveLine) -> (id: UUID, name: String, isMe: Bool)? {
        guard line.lineAction == .handOut, let to = line.toId else { return nil }
        let isMe = to == meId
        let n = (line.toName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (id: to, name: isMe ? "我" : (n.isEmpty ? "不在名單的同仁" : n), isMe: isMe)
    }

    /// 膠囊字「交出去 黃冠宇」「我先接」
    static func handOutCapsule(_ line: OrgMoveLine) -> String {
        guard let t = handOutTarget(line) else { return "交出去…" }
        return t.isMe ? "我先接" : "交出去 \(t.name)"
    }

    // MARK: 第 ③ 步：預覽

    /// 「王小明　製造一課 P1 → 品保課（調出我的管轄）」「王小明　離職（製造一課 P1）」（換單位、只換廠區＝nil）
    static func leavingHeader(_ move: OrgMove, world: OrgMoveWorld) -> String? {
        guard move.isLeaving else { return nil }
        let person = move.personName.isEmpty ? "這位同仁" : move.personName
        let f = sideText(move.from, world: world)
        if move.isLeaveCompany {
            let w = move.kind == OrgMoveKind.resign.rawValue ? "離職" : "退休"
            return f.isEmpty ? "\(person)　\(w)" : "\(person)　\(w)（\(f)）"
        }
        let t = sideText(move.to, world: world)
        if f == t || t.isEmpty { return f.isEmpty ? "\(person)　調出我的管轄" : "\(person)　\(f)（調出我的管轄）" }
        return "\(person)　\(f) → \(t)（調出我的管轄）"
    }

    /// 「交出去給 黃冠宇 2 項：…」「我先接 1 項：…」
    static func handOutPreviewBlocks(_ lines: [OrgMoveLine], person: String) -> [OrgMovePreviewBlock] {
        var order: [UUID] = []
        var names: [UUID: String] = [:]
        var titles: [UUID: [String]] = [:]
        var mine: [String] = []
        for l in lines where !l.isOrgLine && (l.lineKind != nil || l.isLiveCustom) {
            guard let t = handOutTarget(l) else { continue }
            if t.isMe {
                mine.append(l.title)
                continue
            }
            if titles[t.id] == nil { order.append(t.id) }
            titles[t.id, default: []].append(l.title)
            names[t.id] = t.name
        }
        var out: [OrgMovePreviewBlock] = []
        for id in order {
            let list = titles[id] ?? []
            out.append(OrgMovePreviewBlock(id: "out-" + id.uuidString,
                                           title: "交出去給 \(names[id] ?? "") \(list.count) 項：\(list.joined(separator: "、"))",
                                           lines: ["不在部屬名單：從\(person)身上拿掉、記在交接單上，不算任何人的分數"]))
        }
        if !mine.isEmpty {
            out.append(OrgMovePreviewBlock(id: "mine", title: "我先接 \(mine.count) 項：\(mine.joined(separator: "、"))",
                                           lines: ["放在部屬總覽「我接的」，做完自己打勾收掉；不算任何人的分數"]))
        }
        return out
    }

    /// 「會一起改」那幾行（調出、離職、退休；換單位那種的互評兩行換成「今年不排」）
    static func leavingChangeLines(_ move: OrgMove, world: OrgMoveWorld, now: Date) -> [String] {
        guard move.isLeaving else { return [] }
        let person = move.personName.isEmpty ? "這位同仁" : move.personName
        let d = shortDay(move.effectiveKey)
        var out: [String] = []
        out.append("部屬名單：\(d) 起收進最下面「已轉出」（卡片、歷史、分數都留著；可以〔回到我的部屬〕）")
        out.append("\(d) 起小工具、會議通知、班表、人才矩陣、互評名單、挑人清單都不再出現\(person)")
        if move.isLeaveCompany, world.orgPerson(linkedTo: move.personId) != nil {
            out.append("組織圖：\(person)標成已離職（\(d)）")
        }
        // 互評票的 year 是 Calendar.current 記的（民國曆的手機是 115）：跟 ballotLines 一樣
        let year = Calendar.current.component(.year, from: now)
        let word = leavingWord(move)
        let open = world.ballots.filter { b in
            b.year == year && !b.isSubmitted && b.raterId != move.personId
                && b.groups.contains(where: { g in g.entries.contains { $0.id == move.personId } })
        }
        if !open.isEmpty {
            out.append("今年還沒送出的互評票：拿掉\(person)（\(open.count) 張；\(word)那年不排，已經送出的票不動）")
        }
        if world.ballots.contains(where: { $0.year == year && !$0.isSubmitted && $0.raterId == move.personId }) {
            out.append("\(person)自己那張還沒送出的票：不再列在「還沒投票的人」")
        }
        return out
    }

    /// 「調出」「離職」「退休」（換單位＝轉組織）
    static func leavingWord(_ move: OrgMove) -> String {
        switch move.kindValue {
        case .some(.resign): return "離職"
        case .some(.retire): return "退休"
        case .some(.out): return "調出"
        default: return "轉組織"
        }
    }

    // MARK: 交接單頁

    /// 〔交出去〕那一列：→「交出去給 黃冠宇（不在部屬名單）」；給我＝○「我接的・還沒收掉」／✓「11/3 收掉了（我接的）」；
    /// 自己加的一項交出去：○「交出去給 黃冠宇・還沒交」／✓「11/3 已交給 黃冠宇」
    static func handOutStatus(_ line: OrgMoveLine, move: OrgMove) -> OrgMoveLineStatus {
        guard let t = handOutTarget(line) else {
            let person = move.personName.isEmpty ? "這位同仁" : move.personName
            return OrgMoveLineStatus(kind: .follow, mark: "・", text: "跟著\(person)", holderId: move.personId, fix: nil, fixLabel: nil)
        }
        if t.isMe {
            if let at = line.checkedAt {
                return OrgMoveLineStatus(kind: .mine, mark: "✓", text: "\(shortDay(dayKey(at))) 收掉了（我接的）",
                                         holderId: nil, fix: nil, fixLabel: nil)
            }
            return OrgMoveLineStatus(kind: .mine, mark: "○", text: "我接的・還沒收掉", holderId: nil, fix: nil, fixLabel: nil)
        }
        if line.isCustom {
            if let at = line.checkedAt {
                return OrgMoveLineStatus(kind: .handedOut, mark: "✓", text: "\(shortDay(dayKey(at))) 已交給 \(t.name)",
                                         holderId: nil, fix: nil, fixLabel: nil)
            }
            return OrgMoveLineStatus(kind: .handedOut, mark: "○", text: "交出去給 \(t.name)・還沒交",
                                     holderId: nil, fix: nil, fixLabel: nil)
        }
        return OrgMoveLineStatus(kind: .handedOut, mark: "→", text: "交出去給 \(t.name)（不在部屬名單）",
                                 holderId: nil, fix: nil, fixLabel: nil)
    }

    /// 「組織」那一列（調出、離職、退休、回到我的部屬；部門、廠區、職稱、管理人員已經對過了才走到這裡）
    static func leavingOrgStatus(_ move: OrgMove, world: OrgMoveWorld, deptChanged: Bool, toDept: String) -> (ok: Bool, text: String)? {
        if move.isBack { return (true, "✓ 回到我的部屬（\(shortDay(move.effectiveKey))）") }
        guard move.isLeaving else { return nil }
        let person = move.personName.isEmpty ? "這位同仁" : move.personName
        if move.isLeaveCompany {
            if let op = world.orgPerson(linkedTo: move.personId), !op.isInactive {
                return (false, "⚠ 組織圖上\(person)還沒標成已離職")
            }
            return (true, "✓ 已轉出・\(leavingWord(move))（組織圖標成已離職）")
        }
        if deptChanged { return (true, "✓ 已轉出・\(toDept)（部門、組織圖、名片都對）") }
        return (true, "✓ 已轉出（部門照舊）")
    }

    /// 歷程那一列的灰字前半（「製造一課 P1 → 品保課」；離職、退休、回到我的部屬只寫一邊）
    static func historyDetail(_ m: OrgMove, from f: String, to t: String) -> String {
        if m.isLeaveCompany || m.isBack { return f }
        return f == t ? "\(f)（部門照舊）" : "\(f) → \(t)"
    }

    /// 歷程、單頭的那個字：轉組織／調出／離職／退休／回到我的部屬
    static func historyWord(_ m: OrgMove) -> String {
        if m.isBack { return "回到我的部屬" }
        return leavingWord(m)
    }

    /// 〔復原這次轉組織〕確認字多的那兩句（調出、離職、退休）
    static func leavingUndoParts(_ move: OrgMove) -> [String] {
        guard move.isLeaving, move.orgDone else { return [] }
        let person = move.personName.isEmpty ? "這位同仁" : move.personName
        var out = ["\(person)回到部屬名單（在職）"]
        if move.isLeaveCompany { out.append("組織圖上的「已離職」拿掉") }
        return out
    }

    // MARK: 分享

    /// 這一列要不要寫進給 receiverId 的那一份（交給這位的、〔交出去〕給這位組織人員的）
    static func isShareTo(_ l: OrgMoveLine, receiverId: UUID, move: OrgMove) -> Bool {
        if receiver(l, in: move).id == receiverId { return true }
        return l.lineAction == .handOut && l.toId == receiverId && receiverId != meId
    }

    /// 〔交出去〕給的組織人員（給我的不出分享）：〔給黃冠宇的 2 項〕
    static func handOutShareTargets(_ move: OrgMove) -> [OrgMoveShareTarget] {
        var order: [UUID] = []
        var names: [UUID: String] = [:]
        var counts: [UUID: Int] = [:]
        for l in move.allLines where !l.isOrgLine && (l.lineKind != nil || l.isLiveCustom)
            && l.state != OrgMoveLineState.undone.rawValue {
            guard let t = handOutTarget(l), !t.isMe else { continue }
            if counts[t.id] == nil { order.append(t.id) }
            counts[t.id, default: 0] += 1
            names[t.id] = t.name
        }
        return order.map { id in
            OrgMoveShareTarget(receiverId: id, label: "給\(names[id] ?? "")的 \(counts[id] ?? 0) 項")
        }
    }

    /// 這個 id 是〔交出去〕給的組織人員（整張分享寫「交出去給 黃冠宇」）
    static func isHandOutTarget(_ id: UUID, move: OrgMove) -> Bool {
        move.allLines.contains { $0.lineAction == .handOut && $0.toId == id && id != meId }
    }

    /// 整張分享的「我先接：…」
    static func handOutMineTitles(_ move: OrgMove) -> [String] {
        move.allLines.filter { l in
            l.lineAction == .handOut && l.toId == meId && l.state != OrgMoveLineState.undone.rawValue
                && (l.lineKind != nil || l.isLiveCustom)
        }.map(\.title)
    }

    // MARK: 排在以後（v1b 那幾支的延伸）

    /// 「什麼時候做」那兩顆（調出、離職、退休）；其他＝空的（照 timingOptions）
    static func leavingTimingOptions(_ move: OrgMove) -> [OrgMoveTimingOption] {
        guard move.isLeaving else { return [] }
        let d = shortDay(move.effectiveKey)
        let w = leavingWord(move)
        let org = move.isLeaveCompany ? "組織圖標成已離職" : "部門、組織圖改好"
        return [
            OrgMoveTimingOption(timing: .handoverNow, label: "現在就交接，\(d) 才\(w)",
                                note: "按下去就把事情交出去；\(d) 起收進「已轉出」、\(org)（\(d) 打開 App 時在你自己的手機上改）"),
            OrgMoveTimingOption(timing: .together, label: "\(d) 一起做",
                                note: "\(d) 以前什麼都不動；\(d) 照那天的資料一起交接、收進「已轉出」（那天已經逾期的會重新給新的截止日）")
        ]
    }

    /// 「11/1 起調出到品保課」「11/1 起調出我的管轄」「11/1 起離職」「11/1 起退休」（換單位、只換廠區＝nil）
    static func leavingPendingHead(_ m: OrgMove, world: OrgMoveWorld) -> String? {
        guard m.isLeaving else { return nil }
        let d = shortDay(m.effectiveKey)
        switch m.kindValue {
        case .some(.resign): return "\(d) 起離職"
        case .some(.retire): return "\(d) 起退休"
        default:
            guard m.changesDept else { return "\(d) 起調出我的管轄" }
            let dept = sideText(OrgMoveSide(deptId: m.to.deptId, deptLabel: m.to.deptLabel), world: world)
            return "\(d) 起調出到\(dept)"
        }
    }

    /// 「組織」那一列（還沒到生效日）「11/1 才改：品保課・收進「已轉出」」多的那幾格
    static func leavingWhat(_ move: OrgMove) -> [String] {
        guard move.isLeaving else { return [] }
        var out: [String] = []
        if move.isLeaveCompany { out.append("標成已離職") }
        out.append("收進「已轉出」")
        return out
    }

    /// 「今天生效」那一列的標題（調出、離職、退休）：「王小明 製造一課 → 品保課（調出）」「王小明 離職（製造一課）」
    static func leavingDueTitle(_ m: OrgMove, world: OrgMoveWorld) -> String? {
        guard m.isLeaving else { return nil }
        let person = m.personName.isEmpty ? "這位同仁" : m.personName
        let f = sideText(OrgMoveSide(deptId: m.from.deptId, deptLabel: m.from.deptLabel), world: world)
        if m.isLeaveCompany {
            let w = leavingWord(m)
            return f.isEmpty ? "\(person) \(w)" : "\(person) \(w)（\(f)）"
        }
        guard m.changesDept else { return f.isEmpty ? "\(person) 調出我的管轄" : "\(person) 調出我的管轄（\(f)）" }
        let t = sideText(OrgMoveSide(deptId: m.to.deptId, deptLabel: m.to.deptLabel), world: world)
        return "\(person) \(f) → \(t)（調出）"
    }

    /// 精靈完成畫面（調出、離職、退休）
    static func leavingDoneTexts(_ m: OrgMove) -> (headline: String, sub: String?)? {
        guard m.isLeaving else { return nil }
        let d = shortDay(m.effectiveKey)
        let person = m.personName.isEmpty ? "這位同仁" : m.personName
        if m.isPlanned {
            return ("交接單排好了", "\(d) 以前什麼都不動；\(d) 打開 App 時一起交接、收進「已轉出」（在你自己的手機上）")
        }
        if m.isHanded {
            return ("事情交出去了", "\(d) 起收進「已轉出」（\(d) 打開 App 時在你自己的手機上改）")
        }
        return ("交接單做好了", "\(person)收進部屬名單最下面「已轉出」（卡片、歷史、分數都留著）")
    }

    /// 部門頁「異動」那一列中間的字（舊部門那頁）：「調到 設備課」「調出到 品保課」「調出我的管轄」「離職」「退休」
    static func deptRowVerb(_ m: OrgMove, to: String) -> String {
        switch m.kindValue {
        case .some(.out): return m.changesDept ? "調出到 \(to)" : "調出我的管轄"
        case .some(.resign): return "離職"
        case .some(.retire): return "退休"
        default: return "調到 \(to)"
        }
    }

    // MARK: 部屬總覽「我接的」

    /// 〔交出去〕給「我」的那幾項（套用過、沒復原、做了的那一列）。includeChecked＝false：只列還沒收掉的
    static func mineRows(book: OrgMoveBook, world: OrgMoveWorld, includeChecked: Bool = false) -> [OrgMoveMineRow] {
        var out: [OrgMoveMineRow] = []
        for m in book.live where m.wasApplied && !m.isUndone {
            let person = m.personName.isEmpty ? "這位同仁" : m.personName
            let handed: Date = m.handedAt ?? m.appliedAt ?? Date.distantPast
            for l in m.allLines where l.lineAction == .handOut && l.toId == meId
                && l.state == OrgMoveLineState.done.rawValue {
                let checked = l.checkedAt != nil
                if checked && !includeChecked { continue }
                var detail = "從\(person)・\(shortDay(dayKey(handed)))"
                if let k = l.dueKey { detail += "・原訂 \(shortDay(k))" }
                out.append(OrgMoveMineRow(moveId: m.id, lineId: l.id, title: l.title, detail: detail, checked: checked))
            }
        }
        return out
    }

    // MARK: 班表照那天的部門

    /// 班表那個月要列的人（judge §5-32、v1a-1 adjudicate §8-17）：這個月有任何一天在職、而且在 deptId 這個部門（nil＝全部部門）就列；
    /// 分組的廠區＝符合的最後那一天的廠區。回看 10 月製造一課看得到 11/1 調走、已轉出的王小明；11 月就沒有
    static func rosterMembers(_ subs: [Subordinate], deptId: UUID?, dayKeys: [String]) -> [OrgMoveRosterMember] {
        var out: [OrgMoveRosterMember] = []
        for s in subs {
            var plant: String?
            let nowArchived = OrgMoveIndex.isArchived(s.id)
            for d in dayKeys {
                let p = OrgMoveIndex.placement(s.id, dayKey: d)
                let archived = p?.archived ?? nowArchived
                if archived { continue }
                let dept: UUID? = p == nil ? s.departmentId : p?.deptId
                if deptId == nil || dept == deptId { plant = p?.plant ?? s.plantArea }
            }
            if let pl = plant { out.append(OrgMoveRosterMember(personId: s.id, plant: pl)) }
        }
        return out
    }

    // MARK: 往左滑〔刪除〕三選一（judge §3.6）

    /// 身上還沒交出去的（沒做完的待辦〔負責的機台的警報不另外算〕＋還沒交的週報＋負責的機台；同 directDeptChangeMessage 的件數）
    static func openItemCount(personId: UUID, world: OrgMoveWorld) -> Int {
        guard let sub = world.sub(personId) else { return 0 }
        let ownedIds = Set(world.equipment.filter { $0.ownerId == personId }.map(\.id))
        let tasks = sub.tasks.filter { t in
            if t.isCompleted { return false }
            guard let link = t.equipmentLink else { return true }
            return !ownedIds.contains(link.equipmentId)
        }
        return tasks.count + sub.weeklyReports.filter { !$0.isCompleted }.count + ownedIds.count
    }

    /// 「王小明是轉走了嗎？」〔轉組織…〕〔真的刪除〕〔取消〕
    static func deleteChoice(personId: UUID, world: OrgMoveWorld) -> (title: String, message: String) {
        let person = world.name(personId)
        let msg = "調走、離職、退休請用〔轉組織…〕：事情交出去、收進部屬名單最下面「已轉出」，紀錄和分數都留著。〔真的刪除〕會把全部紀錄一起刪，不能復原。"
        return ("\(person)是轉走了嗎？", msg)
    }

    /// 〔真的刪除〕前那一句：「王小明身上還有 3 件沒交出去。」（只提醒不擋；沒有＝nil）
    static func deleteOpenNote(personId: UUID, world: OrgMoveWorld) -> String? {
        let n = openItemCount(personId: personId, world: world)
        guard n > 0 else { return nil }
        return "\(world.name(personId))身上還有 \(n) 件沒交出去。"
    }

    // MARK: 部屬匯出（export design §1.3、§5.4）

    /// 〔在我這裡的時候〕的最後一天：已轉出＝轉出生效日「2026-11-01」；在職＝nil（到今天）
    static func whileMineEndKey(personId: UUID) -> String? {
        OrgMoveIndex.archived[personId]?.effectiveKey
    }

    /// 匯出文字部門那一行後面：「（11/1 轉出）」「（11/1 離職）」「（11/1 退休）」；在職＝nil
    static func exportDeptSuffix(personId: UUID) -> String? {
        guard let a = OrgMoveIndex.archived[personId] else { return nil }
        let d = shortDay(a.effectiveKey)
        switch OrgMoveKind(rawValue: a.kind) {
        case .some(.resign): return "（\(d) 離職）"
        case .some(.retire): return "（\(d) 退休）"
        default: return "（\(d) 轉出）"
        }
    }
}
