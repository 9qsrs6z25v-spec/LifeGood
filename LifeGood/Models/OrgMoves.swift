import Foundation

// MARK: - [v25.590 轉組織 v1a-1] 交接單（同步鍵 life_org_moves_v1）
//（orgmove/judge.md §2、§3.8、§3.9、§7 v1a-1、§13；orgmove/build/v1a-1/brief.md §2；sim_v1a-1.py 照這裡一行一行寫過、跑過）
//
// 一張交接單＝一位同仁的一次轉組織。只記「當時決定什麼」；「現在在誰身上、做完沒」打開時照現在的資料算（OrgMovePlan）。
// • 新的同步鍵 life_org_moves_v1（OrgMoveBook.syncKey）：**部屬、組織人員、部門、任務一個欄位都不加**——
//   還沒更新的 iPad 存一次部屬會用它自己的 CodingKeys 重寫整包、洗掉不認得的欄位；新鍵它不認得、不會碰（u1 §9.2-12）。
// • 真正的改動照舊寫在原本的地方（部門、機台負責人、任務搬到誰身上），舊 iPad、網頁版看到的結果也是對的。
// • 全部欄位 Optional＋decodeIfPresent（id 除外）；moves、lines 逐筆解（一張壞掉只丟那一張、一列壞掉只丟那一列）。
// • kind／action／state 一律存字串：不認得的值＝只顯示、不套用，存回去照原樣（以後的版本加 "meeting"、"out"…）。
// • 日子存西曆日字串「2026-11-01」（OrgHandoffRules.dayKey／OrgMovePlan.date(fromKey:)）；按下去的時間存 Date。
// • 兩台合併：逐張、逐列（單頭取 updatedAt 新的；lines 照列 id 各取 updatedAt 新的）——iPhone 改 P-12、iPad 改 T3，兩列都留得住。
// • 已套用過的不給刪（刪了「不要了」的原樣與交接紀錄就跟著不見）；「清除全部資料」例外。
// • 交出去那一刻已逾期的扣分：照 v0b 寫進 life_org_handoffs_v1（OrgHandoff via "orgMove"），這裡不另外算。
// • 隱私：名字、備註只在 App 內頁與你自己按的分享文字；不上通知、小工具、手錶、鎖定畫面。

/// 交接單那一包（同步鍵 life_org_moves_v1；跟 iCloud 同步、進完整備份與「職涯」匯出）
struct OrgMoveBook: Codable, Equatable {
    /// 同步鍵（LifeStore 存讀、CloudSyncManager.syncKeys、匯出用同一個字）
    static let syncKey = "life_org_moves_v1"

    /// 每一張交接單（做完的、復原的都留著）
    var moves: [OrgMove]?

    init(moves: [OrgMove]? = nil) {
        self.moves = moves
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 逐張解：一張壞掉不會讓整包消失（同 WealthTransferBook、OrgHandoffBook）
        var list: [OrgMove] = []
        var found = false
        if var arr = try? c.nestedUnkeyedContainer(forKey: .moves) {
            found = true
            while !arr.isAtEnd {
                if let m = try? arr.decode(OrgMove.self) {
                    list.append(m)
                } else if (try? arr.decode(OrgMoveSkip.self)) == nil {
                    break
                }
            }
        }
        moves = found ? list : nil
    }

    private enum CodingKeys: String, CodingKey {
        case moves
    }

    var all: [OrgMove] { moves ?? [] }
    /// 沒有墓碑的（v1a-1 不會刪；欄位先留給 v1b 的「排好、還沒做的可以刪」）
    var live: [OrgMove] { all.filter { $0.deletedAt == nil } }
    var isEmpty: Bool { all.isEmpty }

    func move(_ id: UUID) -> OrgMove? {
        all.first { $0.id == id }
    }

    /// 新增或整張換掉（同 id）
    mutating func upsert(_ m: OrgMove) {
        var list = all
        if let i = list.firstIndex(where: { $0.id == m.id }) {
            list[i] = m
        } else {
            list.append(m)
        }
        moves = list
    }

    /// 兩台合併（收到 iCloud 的更新、備份「合併」）：self＝收進來的那份（雲端／本機），other＝另一份。
    /// 同一張：單頭取 updatedAt 新的（一樣新留 self）；lines 照列 id 各取 updatedAt 新的；只有一邊有的列都留。
    /// 只有一邊有的那一張整張留。
    func merged(with other: OrgMoveBook) -> OrgMoveBook {
        var theirs: [UUID: OrgMove] = [:]
        for m in other.all where theirs[m.id] == nil { theirs[m.id] = m }
        var out: [OrgMove] = []
        var seen = Set<UUID>()
        for m in all where !seen.contains(m.id) {
            seen.insert(m.id)
            if let o = theirs[m.id] {
                out.append(OrgMove.merge(m, o))
            } else {
                out.append(m)
            }
        }
        for o in other.all where !seen.contains(o.id) {
            seen.insert(o.id)
            out.append(o)
        }
        var b = self
        b.moves = out.isEmpty ? moves : out
        return b
    }
}

/// 逐筆解時跳過壞掉的那一筆用（任何 JSON 物件都解得出來）
private struct OrgMoveSkip: Decodable {}

// MARK: - 一張交接單

/// 一張交接單（一位同仁的一次轉組織）
struct OrgMove: Codable, Equatable, Identifiable {
    let id: UUID
    /// 部屬 id
    var personId: UUID
    /// nil／"sub"＝部屬（v4 轉進來才有 "org"）
    var personKind: String?
    /// 名字快照（人之後改名、刪了也看得懂）
    var personName: String
    /// "move" 換單位（還是我帶的）／"plant" 只換廠區（v2 起 "out"、"resign"、"retire"；v4 "temp"、"in"）
    var kind: String
    /// 生效日「2026-11-01」（v1a 只能今天或以前）
    var effectiveKey: String
    /// 交接完成日（生效日＋10 天）
    var handoverByKey: String?
    /// nil／"now"＝確認那一刻全部做（v1a 只有這個）
    var timing: String?
    var from: OrgMoveSide
    var to: OrgMoveSide
    /// 新部門〔照舊（只交接）〕：組織那幾格不動
    var keepDept: Bool?
    /// 你自己打的備註（「人事令 1015-07 號」）；只有你看得到，不上分享
    var note: String?
    /// "applied" 全部做完／"closed" 按了〔交接完成〕／"undone" 復原了（v1b 起 "planned"、"handed"、"cancelled"）
    var state: String
    var handedAt: Date?
    var appliedAt: Date?
    var closedAt: Date?
    var undoneAt: Date?
    /// 交接清單的每一列
    var lines: [OrgMoveLine]?
    /// 套用前的樣子（復原、⚠〔再改一次〕用）；第一次套用才存
    var before: OrgMoveRestore?
    /// 確認那時勾了「順便更新生日提醒」（只在按的那台改，這裡只是紀錄）
    var retitleBirthday: Bool?
    var createdAt: Date?
    var updatedAt: Date?
    var deletedAt: Date?

    init(id: UUID = UUID(), personId: UUID, personKind: String? = nil, personName: String,
         kind: String = OrgMoveKind.move.rawValue, effectiveKey: String, handoverByKey: String? = nil,
         timing: String? = nil, from: OrgMoveSide = OrgMoveSide(), to: OrgMoveSide = OrgMoveSide(),
         keepDept: Bool? = nil, note: String? = nil, state: String = OrgMoveState.applied.rawValue,
         handedAt: Date? = nil, appliedAt: Date? = nil, closedAt: Date? = nil, undoneAt: Date? = nil,
         lines: [OrgMoveLine]? = nil, before: OrgMoveRestore? = nil, retitleBirthday: Bool? = nil,
         createdAt: Date? = nil, updatedAt: Date? = nil, deletedAt: Date? = nil) {
        self.id = id
        self.personId = personId
        self.personKind = personKind
        self.personName = personName
        self.kind = kind
        self.effectiveKey = effectiveKey
        self.handoverByKey = handoverByKey
        self.timing = timing
        self.from = from
        self.to = to
        self.keepDept = keepDept
        self.note = note
        self.state = state
        self.handedAt = handedAt
        self.appliedAt = appliedAt
        self.closedAt = closedAt
        self.undoneAt = undoneAt
        self.lines = lines
        self.before = before
        self.retitleBirthday = retitleBirthday
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        personId = try c.decode(UUID.self, forKey: .personId)
        personKind = try? c.decodeIfPresent(String.self, forKey: .personKind)
        personName = (try? c.decodeIfPresent(String.self, forKey: .personName)) ?? ""
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? OrgMoveKind.move.rawValue
        effectiveKey = (try? c.decodeIfPresent(String.self, forKey: .effectiveKey)) ?? ""
        handoverByKey = try? c.decodeIfPresent(String.self, forKey: .handoverByKey)
        timing = try? c.decodeIfPresent(String.self, forKey: .timing)
        from = (try? c.decodeIfPresent(OrgMoveSide.self, forKey: .from)) ?? OrgMoveSide()
        to = (try? c.decodeIfPresent(OrgMoveSide.self, forKey: .to)) ?? OrgMoveSide()
        keepDept = try? c.decodeIfPresent(Bool.self, forKey: .keepDept)
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        state = (try? c.decodeIfPresent(String.self, forKey: .state)) ?? OrgMoveState.applied.rawValue
        handedAt = try? c.decodeIfPresent(Date.self, forKey: .handedAt)
        appliedAt = try? c.decodeIfPresent(Date.self, forKey: .appliedAt)
        closedAt = try? c.decodeIfPresent(Date.self, forKey: .closedAt)
        undoneAt = try? c.decodeIfPresent(Date.self, forKey: .undoneAt)
        // 逐列解：一列壞掉只丟那一列
        var list: [OrgMoveLine] = []
        var found = false
        if var arr = try? c.nestedUnkeyedContainer(forKey: .lines) {
            found = true
            while !arr.isAtEnd {
                if let l = try? arr.decode(OrgMoveLine.self) {
                    list.append(l)
                } else if (try? arr.decode(OrgMoveSkip.self)) == nil {
                    break
                }
            }
        }
        lines = found ? list : nil
        before = try? c.decodeIfPresent(OrgMoveRestore.self, forKey: .before)
        retitleBirthday = try? c.decodeIfPresent(Bool.self, forKey: .retitleBirthday)
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        deletedAt = try? c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, personId, personKind, personName, kind, effectiveKey, handoverByKey, timing
        case from, to, keepDept, note, state, handedAt, appliedAt, closedAt, undoneAt
        case lines, before, retitleBirthday, createdAt, updatedAt, deletedAt
    }

    var allLines: [OrgMoveLine] { lines ?? [] }

    func line(_ id: UUID) -> OrgMoveLine? {
        allLines.first { $0.id == id }
    }

    /// 改一列（找不到就不動）
    mutating func updateLine(_ id: UUID, _ body: (inout OrgMoveLine) -> Void) {
        guard var list = lines, let i = list.firstIndex(where: { $0.id == id }) else { return }
        body(&list[i])
        lines = list
    }

    var isUndone: Bool { state == OrgMoveState.undone.rawValue }
    var isClosed: Bool { state == OrgMoveState.closed.rawValue || closedAt != nil }
    /// 已經套用過（復原的也算：歷程照樣列一行灰字）
    var wasApplied: Bool { appliedAt != nil || handedAt != nil }

    /// 同一張的兩份合併（見 OrgMoveBook.merged）
    static func merge(_ a: OrgMove, _ b: OrgMove) -> OrgMove {
        let aT: Date = a.updatedAt ?? Date.distantPast
        let bT: Date = b.updatedAt ?? Date.distantPast
        var head = bT > aT ? b : a
        var theirs: [UUID: OrgMoveLine] = [:]
        for l in b.allLines where theirs[l.id] == nil { theirs[l.id] = l }
        var out: [OrgMoveLine] = []
        var seen = Set<UUID>()
        for l in a.allLines where !seen.contains(l.id) {
            seen.insert(l.id)
            let mineT: Date = l.updatedAt ?? Date.distantPast
            if let o = theirs[l.id], (o.updatedAt ?? Date.distantPast) > mineT {
                out.append(o)
            } else {
                out.append(l)
            }
        }
        for l in b.allLines where !seen.contains(l.id) {
            seen.insert(l.id)
            out.append(l)
        }
        head.lines = out.isEmpty ? head.lines : out
        // 套用前的樣子只在第一次套用時存：哪一邊有就用哪一邊（兩邊都有用先存的那份＝a）
        if head.before == nil { head.before = a.before ?? b.before }
        return head
    }
}

/// 前／後各一份：快照文字＋可對照的 id
struct OrgMoveSide: Codable, Equatable {
    var deptId: UUID?
    /// 「MFG1 — 製造一課」（部門之後改名、刪掉也看得懂）
    var deptLabel: String?
    /// 「P1」
    var plant: String?
    var gradeTitleId: UUID?
    /// 「E3 — 工程師」
    var titleLabel: String?
    /// 新主管（組織人員 id；只記在單上，App 沒有「直屬主管」欄位）
    var managerId: UUID?
    var managerName: String?

    init(deptId: UUID? = nil, deptLabel: String? = nil, plant: String? = nil,
         gradeTitleId: UUID? = nil, titleLabel: String? = nil,
         managerId: UUID? = nil, managerName: String? = nil) {
        self.deptId = deptId
        self.deptLabel = deptLabel
        self.plant = plant
        self.gradeTitleId = gradeTitleId
        self.titleLabel = titleLabel
        self.managerId = managerId
        self.managerName = managerName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deptId = try? c.decodeIfPresent(UUID.self, forKey: .deptId)
        deptLabel = try? c.decodeIfPresent(String.self, forKey: .deptLabel)
        plant = try? c.decodeIfPresent(String.self, forKey: .plant)
        gradeTitleId = try? c.decodeIfPresent(UUID.self, forKey: .gradeTitleId)
        titleLabel = try? c.decodeIfPresent(String.self, forKey: .titleLabel)
        managerId = try? c.decodeIfPresent(UUID.self, forKey: .managerId)
        managerName = try? c.decodeIfPresent(String.self, forKey: .managerName)
    }

    private enum CodingKeys: String, CodingKey {
        case deptId, deptLabel, plant, gradeTitleId, titleLabel, managerId, managerName
    }
}

/// 交接清單的一列
struct OrgMoveLine: Codable, Equatable, Identifiable {
    let id: UUID
    /// OrgMoveLineKind 的字："task"／"alarmTask"／"equipment"／"report"／"sideRole"／"manager"／"managerAdd"
    ///（v1a-2 起 "meeting"、"agenda"、"shifts"）
    var kind: String
    /// 那一筆的 id（任務、機台、週報；manager／managerAdd＝部門 id；sideRole＝兼任待辦 id）
    var refId: UUID?
    /// 只有 sideRole：掛在這位同仁身上的那一筆任務 id
    var itemId: UUID?
    /// 警報任務／跟著機台的待辦、週報所屬的機台；sideRole 的兼任 id
    var parentId: UUID?
    /// 東西掛在誰身上（v1a-1 都是本人）
    var holderId: UUID?
    /// 列出來那時的名字（快照）
    var title: String
    /// 原本的截止日「2026-10-20」（週報＝報告日）
    var dueKey: String?
    /// OrgMoveAction 的字；nil＝還沒決定（套用時當〔跟著〕）
    var action: String?
    /// 接手的人（部屬 id；managerAdd／manager replace＝組織人員 id）
    var toId: UUID?
    var toName: String?
    /// 交出去的已逾期那件的新截止日（寫回任務時用原本截止的那個時刻）
    var newDueKey: String?
    /// 交接那一刻已經逾期（扣分留原人；寫在 life_org_handoffs_v1）
    var wasOverdue: Bool?
    /// 交接備註（只在 App 內頁、分享文字）
    var memo: String?
    /// OrgMoveLock 的字：為什麼鎖住（"dereliction" 缺失／"sideRole" 兼任／"alarm" 跟著機台／"pastDue" 過了報告日）
    var lock: String?
    /// manager：這位同仁在 managerIds 的位置（復原放回原位）
    var slot: Int?
    /// 〔不要了〕的那一筆原樣（任務／週報的 JSON）：交接單回看、復原、合併匯入不補
    var removedJSON: Data?
    /// nil 還沒做／"done" 做了／"skipped" 套用時已經做完或找不到／"resolved" 待分派後來分好了／"undone" 這一列復原了
    var state: String?
    /// 待分派分好的時間；缺失〔現在結案〕押的完成時間
    var resolvedAt: Date?
    /// 這一列最後改的時間（逐列合併用；畫面上你動過這一列也寫，套用時全部寫）
    var updatedAt: Date?

    init(id: UUID = UUID(), kind: String, refId: UUID? = nil, itemId: UUID? = nil, parentId: UUID? = nil,
         holderId: UUID? = nil, title: String, dueKey: String? = nil, action: String? = nil,
         toId: UUID? = nil, toName: String? = nil, newDueKey: String? = nil, wasOverdue: Bool? = nil,
         memo: String? = nil, lock: String? = nil, slot: Int? = nil, removedJSON: Data? = nil,
         state: String? = nil, resolvedAt: Date? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.refId = refId
        self.itemId = itemId
        self.parentId = parentId
        self.holderId = holderId
        self.title = title
        self.dueKey = dueKey
        self.action = action
        self.toId = toId
        self.toName = toName
        self.newDueKey = newDueKey
        self.wasOverdue = wasOverdue
        self.memo = memo
        self.lock = lock
        self.slot = slot
        self.removedJSON = removedJSON
        self.state = state
        self.resolvedAt = resolvedAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? ""
        refId = try? c.decodeIfPresent(UUID.self, forKey: .refId)
        itemId = try? c.decodeIfPresent(UUID.self, forKey: .itemId)
        parentId = try? c.decodeIfPresent(UUID.self, forKey: .parentId)
        holderId = try? c.decodeIfPresent(UUID.self, forKey: .holderId)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        dueKey = try? c.decodeIfPresent(String.self, forKey: .dueKey)
        action = try? c.decodeIfPresent(String.self, forKey: .action)
        toId = try? c.decodeIfPresent(UUID.self, forKey: .toId)
        toName = try? c.decodeIfPresent(String.self, forKey: .toName)
        newDueKey = try? c.decodeIfPresent(String.self, forKey: .newDueKey)
        wasOverdue = try? c.decodeIfPresent(Bool.self, forKey: .wasOverdue)
        memo = try? c.decodeIfPresent(String.self, forKey: .memo)
        lock = try? c.decodeIfPresent(String.self, forKey: .lock)
        slot = try? c.decodeIfPresent(Int.self, forKey: .slot)
        removedJSON = try? c.decodeIfPresent(Data.self, forKey: .removedJSON)
        state = try? c.decodeIfPresent(String.self, forKey: .state)
        resolvedAt = try? c.decodeIfPresent(Date.self, forKey: .resolvedAt)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, refId, itemId, parentId, holderId, title, dueKey, action, toId, toName
        case newDueKey, wasOverdue, memo, lock, slot, removedJSON, state, resolvedAt, updatedAt
    }

    // 只在記憶體轉成列舉（不認得的字＝nil：只顯示、不套用）
    var lineKind: OrgMoveLineKind? { OrgMoveLineKind(rawValue: kind) }
    var lineAction: OrgMoveAction? { action.flatMap { OrgMoveAction(rawValue: $0) } }
    var lineState: OrgMoveLineState? { state.flatMap { OrgMoveLineState(rawValue: $0) } }
    var lineLock: OrgMoveLock? { lock.flatMap { OrgMoveLock(rawValue: $0) } }
    var isLocked: Bool { lock != nil }
    /// 組織那幾列（第 ① 步問的；頂端四格不算）
    var isOrgLine: Bool { kind == OrgMoveLineKind.manager.rawValue || kind == OrgMoveLineKind.managerAdd.rawValue }
}

/// 套用前的樣子（復原、⚠〔再改一次〕用）。管理人員的差異記在各自那一列（slot），不存整串
struct OrgMoveRestore: Codable, Equatable {
    var deptId: UUID?
    var deptText: String?
    var plant: String?
    var gradeTitleId: UUID?
    var jobTitle: String?
    /// 連到這位同仁的組織人員（套用時才補建的也記：createdOrgPerson＝true，復原不刪）
    var orgPersonId: UUID?
    var orgDeptId: UUID?
    var orgJobTitle: String?
    var orgGradeTitleId: UUID?
    var createdOrgPerson: Bool?
    var cardId: UUID?
    var cardDept: String?
    var cardJobTitle: String?

    init(deptId: UUID? = nil, deptText: String? = nil, plant: String? = nil,
         gradeTitleId: UUID? = nil, jobTitle: String? = nil,
         orgPersonId: UUID? = nil, orgDeptId: UUID? = nil, orgJobTitle: String? = nil,
         orgGradeTitleId: UUID? = nil, createdOrgPerson: Bool? = nil,
         cardId: UUID? = nil, cardDept: String? = nil, cardJobTitle: String? = nil) {
        self.deptId = deptId
        self.deptText = deptText
        self.plant = plant
        self.gradeTitleId = gradeTitleId
        self.jobTitle = jobTitle
        self.orgPersonId = orgPersonId
        self.orgDeptId = orgDeptId
        self.orgJobTitle = orgJobTitle
        self.orgGradeTitleId = orgGradeTitleId
        self.createdOrgPerson = createdOrgPerson
        self.cardId = cardId
        self.cardDept = cardDept
        self.cardJobTitle = cardJobTitle
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deptId = try? c.decodeIfPresent(UUID.self, forKey: .deptId)
        deptText = try? c.decodeIfPresent(String.self, forKey: .deptText)
        plant = try? c.decodeIfPresent(String.self, forKey: .plant)
        gradeTitleId = try? c.decodeIfPresent(UUID.self, forKey: .gradeTitleId)
        jobTitle = try? c.decodeIfPresent(String.self, forKey: .jobTitle)
        orgPersonId = try? c.decodeIfPresent(UUID.self, forKey: .orgPersonId)
        orgDeptId = try? c.decodeIfPresent(UUID.self, forKey: .orgDeptId)
        orgJobTitle = try? c.decodeIfPresent(String.self, forKey: .orgJobTitle)
        orgGradeTitleId = try? c.decodeIfPresent(UUID.self, forKey: .orgGradeTitleId)
        createdOrgPerson = try? c.decodeIfPresent(Bool.self, forKey: .createdOrgPerson)
        cardId = try? c.decodeIfPresent(UUID.self, forKey: .cardId)
        cardDept = try? c.decodeIfPresent(String.self, forKey: .cardDept)
        cardJobTitle = try? c.decodeIfPresent(String.self, forKey: .cardJobTitle)
    }

    private enum CodingKeys: String, CodingKey {
        case deptId, deptText, plant, gradeTitleId, jobTitle, orgPersonId, orgDeptId, orgJobTitle
        case orgGradeTitleId, createdOrgPerson, cardId, cardDept, cardJobTitle
    }
}

// MARK: - 只在記憶體的列舉（存檔一律存字串）

enum OrgMoveKind: String {
    /// 換單位（還是我帶的）
    case move
    /// 只換廠區
    case plant
}

enum OrgMoveState: String {
    case applied, closed, undone
}

enum OrgMoveLineKind: String {
    case task, alarmTask, equipment, report, sideRole, manager, managerAdd
}

enum OrgMoveAction: String {
    /// 跟著這位同仁
    case follow
    /// 交給 toId
    case give
    /// 跟著那台機台（parentId）：機台給誰就給誰
    case withEquipment
    /// 待分派（只有機台）
    case pending
    /// 不要了
    case drop
    /// 現在結案（只有缺失）
    case closeNow
    /// 管理人員：拿掉／照舊／換成 toId
    case remove, keep, replace
    /// 新部門的管理人員：加進去／不用
    case add, skip
}

enum OrgMoveLineState: String {
    case done, skipped, resolved, undone
}

enum OrgMoveLock: String {
    /// 缺失：只能〔跟著〕〔現在結案〕
    case dereliction
    /// 兼任：v1a-1 只能〔照舊〕＋〔前往〕兼任那頁換
    case sideRole
    /// 機台警報任務：跟著機台
    case alarm
    /// 週報過了報告日：只能〔跟著〕〔不要了〕
    case pastDue
}

// MARK: - 只在記憶體的查表

/// LifeStore.orgMoves 的 didSet 重建（照 OrgHandoffIndex、CardVault.cipherProbe 由 LifeStore 設進靜態變數的先例）。
/// 預設空的（＝沒有任何交接單，行為跟以前一模一樣）：預覽畫面、沒有 LifeStore 的地方也不會錯。
/// 只看交接單、不看部屬（部屬每一次打勾都不用重建）。「現在在誰身上」不在這裡（OrgMoveHolderMap 打開時算）。
enum OrgMoveIndex {
    /// 這一筆是從哪一張單交過來的（「交接自 王小明」膠囊、預覽那一行、匯出）
    struct Received: Equatable {
        let moveId: UUID
        let lineId: UUID
        let fromId: UUID
        let fromName: String
        let toId: UUID
        /// 交到這位手上的那一刻（待分派後來分好的＝分好那一刻）
        let handedAt: Date
        /// 「2026-10-20」原本的截止
        let dueKey: String?
        let wasOverdue: Bool
        let memo: String
        /// 交接完成日（過了、沒有待分派就收起來；用算的）
        let handoverByKey: String
        /// 按了〔交接完成〕
        let closed: Bool
        /// 這張單還有沒分好的待分派
        let hasPending: Bool
        /// [v25.590 轉組織 v1a-1 驗證] 這張單上還沒分好的待分派機台 id：receivedChip 照機台現在的負責人再對一次
        ///（在機台編輯頁直接換過負責人＝算分好，交接完成日過了照樣收；judge §4.9、第 5／10 題）。
        /// 要退回這一件：刪這個欄位、rebuild 裡的 pendingEq、receivedChip 改回 `|| r.hasPending`
        let pendingEquipmentIds: [UUID]
    }

    /// 任務／週報／機台 id → 最新一張交出它的那一列（接力：王小明 → 陳怡君 → 林志豪，用最新那張）
    static var receivedByItem: [UUID: Received] = [:]
    /// 原人 id → 待分派、還沒分好的機台 id → 交接那一刻（這幾台的警報任務在交接之後到期的，逾期不算原人）
    static var pendingEquipment: [UUID: [UUID: Date]] = [:]
    /// 〔不要了〕的任務、週報 id（合併匯入舊備份時不補回來）
    static var droppedItemIds: Set<UUID> = []
    /// [v25.590 轉組織 v1a-1 驗證] 機台 id → 現在的負責人（LifeStore.equipmentPool 一改就設；預設空的）。
    /// 「還有沒有待分派」照機台現在的負責人算（judge §4.9、第 5 題：在機台編輯頁直接換過＝算分好），
    /// 不然直接換過負責人的那張單，提示列、「交接自」膠囊、接手那一區過了交接完成日也一直不收。
    static var equipmentOwners: [UUID: UUID] = [:]

    /// LifeStore.equipmentPool 的 didSet 呼叫（只記有負責人的）
    static func setEquipmentOwners(_ pool: [ManagedEquipment]) {
        var out: [UUID: UUID] = [:]
        for e in pool {
            if let o = e.ownerId { out[e.id] = o }
        }
        equipmentOwners = out
    }

    /// 單上還沒分好的待分派機台裡，還有一台現在是原人負責（＝真的還在待分派）
    static func stillPending(_ equipmentIds: [UUID], personId: UUID) -> Bool {
        equipmentIds.contains { equipmentOwners[$0] == personId }
    }

    static func rebuild(_ book: OrgMoveBook) {
        var received: [UUID: Received] = [:]
        var pending: [UUID: [UUID: Date]] = [:]
        var dropped = Set<UUID>()
        for m in book.live where !m.isUndone && m.wasApplied {
            let handed: Date = m.handedAt ?? m.appliedAt ?? Date.distantPast
            let byKey = m.handoverByKey ?? m.effectiveKey
            let hasPending = m.allLines.contains { l in
                l.action == OrgMoveAction.pending.rawValue && l.state == OrgMoveLineState.done.rawValue
            }
            var pendingEq: [UUID] = []
            for l in m.allLines where l.kind == OrgMoveLineKind.equipment.rawValue
                && l.action == OrgMoveAction.pending.rawValue && l.state == OrgMoveLineState.done.rawValue {
                if let r = l.refId { pendingEq.append(r) }
            }
            for l in m.allLines {
                if l.state == OrgMoveLineState.undone.rawValue { continue }
                if l.action == OrgMoveAction.drop.rawValue, let r = l.refId { dropped.insert(r) }
                if l.action == OrgMoveAction.pending.rawValue, l.state == OrgMoveLineState.done.rawValue,
                   l.kind == OrgMoveLineKind.equipment.rawValue, let r = l.refId {
                    pending[m.personId, default: [:]][r] = handed
                }
                guard let ref = l.refId, let to = l.toId,
                      l.state == OrgMoveLineState.done.rawValue || l.state == OrgMoveLineState.resolved.rawValue,
                      l.kind != OrgMoveLineKind.manager.rawValue, l.kind != OrgMoveLineKind.managerAdd.rawValue
                else { continue }
                let given = l.action == OrgMoveAction.give.rawValue
                    || l.action == OrgMoveAction.withEquipment.rawValue
                    || (l.action == OrgMoveAction.pending.rawValue && l.state == OrgMoveLineState.resolved.rawValue)
                guard given else { continue }
                let at = l.state == OrgMoveLineState.resolved.rawValue ? (l.resolvedAt ?? handed) : handed
                let r = Received(moveId: m.id, lineId: l.id, fromId: m.personId, fromName: m.personName,
                                 toId: to, handedAt: at, dueKey: l.dueKey, wasOverdue: l.wasOverdue == true,
                                 memo: (l.memo ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                                 handoverByKey: byKey, closed: m.isClosed, hasPending: hasPending,
                                 pendingEquipmentIds: pendingEq)
                if let old = received[ref], old.handedAt > at { continue }
                received[ref] = r
            }
        }
        receivedByItem = received
        pendingEquipment = pending
        droppedItemIds = dropped
    }

    /// 還在顯示期間的「交接自」（膠囊、提示列）：沒按〔交接完成〕、而且還沒過交接完成日或還有待分派。
    /// todayKey：手機當地的今天「2026-11-02」
    /// [v25.590 轉組織 v1a-1 驗證]「還有待分派」照機台現在的負責人算（同 OrgMovePlan.isOpen、pendingRows）
    static func receivedChip(_ itemId: UUID, holderId: UUID, todayKey: String) -> Received? {
        guard let r = receivedByItem[itemId], r.toId == holderId, !r.closed else { return nil }
        let pending = r.hasPending && stillPending(r.pendingEquipmentIds, personId: r.fromId)
        guard todayKey <= r.handoverByKey || pending else { return nil }
        return r
    }
}
