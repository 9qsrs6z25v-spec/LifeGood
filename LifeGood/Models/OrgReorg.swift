import Foundation

// MARK: - [v25.598 轉組織 v5] 組織重整（部門改名、合併、拆成兩個）與我自己調動（同步鍵 life_org_reorgs_v1）
//（orgmove/judge.md §7「v5 組織重整、我自己調動」、§5-8、§1.3 嫁接 C「部門改名時問一次你履歷的管理單位、合併後舊部門留著標已併入」；
//  u2_cases.md S5、S13；design_C.md §3.11、§4.9；orgmove/build/v5/brief.md §2；sim_v5.py 一個函式一個函式對照）
//
// • 「已併入製造課」不存在部門身上（Subordinate／OrgPerson／Department 加欄位會被還沒更新的 iPad 存一次洗掉，u1 §9.2）：
//   存在新的同步鍵 life_org_reorgs_v1（OrgReorgBook.syncKey）。舊 iPad 不認得這個鍵、不會碰；它看到的是一個沒有人的舊部門（可以接受）。
// • 真正的改動照舊寫在原本的地方（部屬 departmentId＋部門字、組織人員、機台、名片、部門的名稱／管理人員／上下游），
//   舊 iPad、網頁版看到的人、機台都在新部門。
// • 一次重整＝一筆 OrgUnitChange（改名、合併、拆成兩個）；只記「改之前的樣子」（復原用）與快照字（之後改名、刪掉也看得懂）。
//   人沒換工作：不開交接單、不搬待辦會議週報（judge §7 v5：一次改人、機台、管理人員、部門字樣、名片）。
// • 我自己調動＝一筆 OrgTeamMove：跟我走的人（kind "move"，可選一起調到新部門）＋其餘每位一張 kind "out" 的交接單（部門照舊），
//   這筆把它們串成「一份全組交接單」。每一張交接單照舊在 life_org_moves_v1（套用、復原、到期、已轉出全部走既有那一套）。
// • 全部欄位 Optional＋decodeIfPresent（id 除外）；changes、teams 逐筆解（一筆壞掉只丟那一筆）；kind、state 存字串。
// • 兩台合併：照 id 各取 updatedAt 新的（一樣新留收進來的那份）；墓碑（deletedAt）跟著那一筆走。
// • 隱私：這裡的字只在 App 內頁與你自己按的分享；通知、小工具、手錶、鎖定畫面一個字都沒加。字不用「他／她」。

/// 組織重整、我自己調動那一包（同步鍵 life_org_reorgs_v1；跟 iCloud 同步、進完整備份與「職涯」匯出）
struct OrgReorgBook: Codable, Equatable {
    static let syncKey = "life_org_reorgs_v1"

    /// 部門改名、合併、拆成兩個（復原的也留著）
    var changes: [OrgUnitChange]?
    /// 我自己調動（一份全組交接單）
    var teams: [OrgTeamMove]?

    init(changes: [OrgUnitChange]? = nil, teams: [OrgTeamMove]? = nil) {
        self.changes = changes
        self.teams = teams
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 逐筆解：一筆壞掉不會讓整包消失（同 OrgMoveBook）
        var cs: [OrgUnitChange] = []
        var foundC = false
        if var arr = try? c.nestedUnkeyedContainer(forKey: .changes) {
            foundC = true
            while !arr.isAtEnd {
                if let v = try? arr.decode(OrgUnitChange.self) {
                    cs.append(v)
                } else if (try? arr.decode(OrgReorgSkip.self)) == nil {
                    break
                }
            }
        }
        changes = foundC ? cs : nil
        var ts: [OrgTeamMove] = []
        var foundT = false
        if var arr = try? c.nestedUnkeyedContainer(forKey: .teams) {
            foundT = true
            while !arr.isAtEnd {
                if let v = try? arr.decode(OrgTeamMove.self) {
                    ts.append(v)
                } else if (try? arr.decode(OrgReorgSkip.self)) == nil {
                    break
                }
            }
        }
        teams = foundT ? ts : nil
    }

    private enum CodingKeys: String, CodingKey {
        case changes, teams
    }

    var allChanges: [OrgUnitChange] { changes ?? [] }
    var allTeams: [OrgTeamMove] { teams ?? [] }
    /// 沒有墓碑的
    var liveChanges: [OrgUnitChange] { allChanges.filter { $0.deletedAt == nil } }
    var liveTeams: [OrgTeamMove] { allTeams.filter { $0.deletedAt == nil } }
    var isEmpty: Bool { allChanges.isEmpty && allTeams.isEmpty }

    func change(_ id: UUID) -> OrgUnitChange? {
        allChanges.first { $0.id == id }
    }

    func team(_ id: UUID) -> OrgTeamMove? {
        allTeams.first { $0.id == id }
    }

    mutating func upsertChange(_ x: OrgUnitChange) {
        var list = allChanges
        if let i = list.firstIndex(where: { $0.id == x.id }) {
            list[i] = x
        } else {
            list.append(x)
        }
        changes = list
    }

    mutating func upsertTeam(_ x: OrgTeamMove) {
        var list = allTeams
        if let i = list.firstIndex(where: { $0.id == x.id }) {
            list[i] = x
        } else {
            list.append(x)
        }
        teams = list
    }

    /// 兩台合併（收到 iCloud 的更新、備份「合併」）：self＝收進來的那份，other＝另一份。同一筆取 updatedAt 新的（一樣新留 self）
    func merged(with other: OrgReorgBook) -> OrgReorgBook {
        var b = self
        var cs = allChanges
        var seenC = Set(cs.map(\.id))
        for o in other.allChanges {
            if let i = cs.firstIndex(where: { $0.id == o.id }) {
                let mine: Date = cs[i].updatedAt ?? Date.distantPast
                let theirs: Date = o.updatedAt ?? Date.distantPast
                if theirs > mine { cs[i] = o }
            } else if !seenC.contains(o.id) {
                seenC.insert(o.id)
                cs.append(o)
            }
        }
        var ts = allTeams
        var seenT = Set(ts.map(\.id))
        for o in other.allTeams {
            if let i = ts.firstIndex(where: { $0.id == o.id }) {
                let mine: Date = ts[i].updatedAt ?? Date.distantPast
                let theirs: Date = o.updatedAt ?? Date.distantPast
                if theirs > mine { ts[i] = o }
            } else if !seenT.contains(o.id) {
                seenT.insert(o.id)
                ts.append(o)
            }
        }
        b.changes = cs.isEmpty ? changes : cs
        b.teams = ts.isEmpty ? teams : ts
        return b
    }
}

/// 逐筆解時跳過壞掉的那一筆用（任何 JSON 物件都解得出來）
private struct OrgReorgSkip: Decodable {}

// MARK: - 一次組織重整

/// 部門改名、合併、拆成兩個（一次按下去＝一筆）
struct OrgUnitChange: Codable, Equatable, Identifiable {
    let id: UUID
    /// "rename" 改名／"merge" 合併／"split" 拆成兩個（OrgUnitChangeKind）
    var kind: String
    /// 生效日「2027-01-01」（只能今天或以前；按下去就全部改好）
    var effectiveKey: String
    /// rename：那個部門；merge：留下的那個（併進去的）；split：原本的部門
    var deptId: UUID
    /// merge：併進來的部門（照你選的順序；第一個是你打開的那個）
    var sourceIds: [UUID]?
    /// split：拆出來的新部門
    var newDeptId: UUID?
    /// 這次新建的部門（合併到新設的「製造課」、拆出來的那個）：復原時空了就拿掉
    var createdDeptId: UUID?
    /// rename：改之前的名稱、代碼；merge／split：快照
    var fromName: String?
    var fromCode: String?
    /// rename：改成的名稱、代碼；merge：留下的那個的名稱；split：新部門的名稱
    var toName: String?
    var toCode: String?
    /// merge：併進來的部門快照字「MFG1 — 製造一課」（之後刪掉也看得懂）
    var sourceLabels: [String]?
    /// 你履歷的管理單位一起改了：改之前、改成的字，改的是哪一筆里程碑（復原照這個改回）
    var myUnitFrom: String?
    var myUnitTo: String?
    var myUnitMilestoneId: UUID?
    /// 搬了誰（部屬、組織人員）：改之前／改成的部門與部門字（復原時現在還是改成的那樣才改回）
    var people: [OrgUnitPersonSnap]?
    /// 搬了哪幾台機台
    var equipment: [OrgUnitEquipSnap]?
    /// 改了哪幾張名片的部門字
    var cards: [OrgUnitCardSnap]?
    /// 動到的部門改之前的樣子（名稱、代碼、上下游、管理人員）
    var depts: [OrgUnitDeptSnap]?
    /// 排好（還沒生效）的交接單裡要調進／調出這幾個部門的，改成新的部門
    var retargets: [OrgUnitRetarget]?
    /// 快照：幾位、幾台（歷程、部門頁「組織重整」那一列）
    var peopleCount: Int?
    var equipmentCount: Int?
    /// "applied"／"undone"
    var state: String
    var appliedAt: Date?
    var undoneAt: Date?
    var createdAt: Date?
    var updatedAt: Date?
    var deletedAt: Date?

    init(id: UUID = UUID(), kind: String, effectiveKey: String, deptId: UUID, sourceIds: [UUID]? = nil,
         newDeptId: UUID? = nil, createdDeptId: UUID? = nil, fromName: String? = nil, fromCode: String? = nil,
         toName: String? = nil, toCode: String? = nil, sourceLabels: [String]? = nil,
         myUnitFrom: String? = nil, myUnitTo: String? = nil, myUnitMilestoneId: UUID? = nil,
         people: [OrgUnitPersonSnap]? = nil, equipment: [OrgUnitEquipSnap]? = nil, cards: [OrgUnitCardSnap]? = nil,
         depts: [OrgUnitDeptSnap]? = nil, retargets: [OrgUnitRetarget]? = nil,
         peopleCount: Int? = nil, equipmentCount: Int? = nil,
         state: String = OrgUnitChangeState.applied.rawValue, appliedAt: Date? = nil, undoneAt: Date? = nil,
         createdAt: Date? = nil, updatedAt: Date? = nil, deletedAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.effectiveKey = effectiveKey
        self.deptId = deptId
        self.sourceIds = sourceIds
        self.newDeptId = newDeptId
        self.createdDeptId = createdDeptId
        self.fromName = fromName
        self.fromCode = fromCode
        self.toName = toName
        self.toCode = toCode
        self.sourceLabels = sourceLabels
        self.myUnitFrom = myUnitFrom
        self.myUnitTo = myUnitTo
        self.myUnitMilestoneId = myUnitMilestoneId
        self.people = people
        self.equipment = equipment
        self.cards = cards
        self.depts = depts
        self.retargets = retargets
        self.peopleCount = peopleCount
        self.equipmentCount = equipmentCount
        self.state = state
        self.appliedAt = appliedAt
        self.undoneAt = undoneAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? ""
        effectiveKey = (try? c.decodeIfPresent(String.self, forKey: .effectiveKey)) ?? ""
        deptId = try c.decode(UUID.self, forKey: .deptId)
        sourceIds = try? c.decodeIfPresent([UUID].self, forKey: .sourceIds)
        newDeptId = try? c.decodeIfPresent(UUID.self, forKey: .newDeptId)
        createdDeptId = try? c.decodeIfPresent(UUID.self, forKey: .createdDeptId)
        fromName = try? c.decodeIfPresent(String.self, forKey: .fromName)
        fromCode = try? c.decodeIfPresent(String.self, forKey: .fromCode)
        toName = try? c.decodeIfPresent(String.self, forKey: .toName)
        toCode = try? c.decodeIfPresent(String.self, forKey: .toCode)
        sourceLabels = try? c.decodeIfPresent([String].self, forKey: .sourceLabels)
        myUnitFrom = try? c.decodeIfPresent(String.self, forKey: .myUnitFrom)
        myUnitTo = try? c.decodeIfPresent(String.self, forKey: .myUnitTo)
        myUnitMilestoneId = try? c.decodeIfPresent(UUID.self, forKey: .myUnitMilestoneId)
        people = try? c.decodeIfPresent([OrgUnitPersonSnap].self, forKey: .people)
        equipment = try? c.decodeIfPresent([OrgUnitEquipSnap].self, forKey: .equipment)
        cards = try? c.decodeIfPresent([OrgUnitCardSnap].self, forKey: .cards)
        depts = try? c.decodeIfPresent([OrgUnitDeptSnap].self, forKey: .depts)
        retargets = try? c.decodeIfPresent([OrgUnitRetarget].self, forKey: .retargets)
        peopleCount = try? c.decodeIfPresent(Int.self, forKey: .peopleCount)
        equipmentCount = try? c.decodeIfPresent(Int.self, forKey: .equipmentCount)
        state = (try? c.decodeIfPresent(String.self, forKey: .state)) ?? OrgUnitChangeState.applied.rawValue
        appliedAt = try? c.decodeIfPresent(Date.self, forKey: .appliedAt)
        undoneAt = try? c.decodeIfPresent(Date.self, forKey: .undoneAt)
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        deletedAt = try? c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, effectiveKey, deptId, sourceIds, newDeptId, createdDeptId
        case fromName, fromCode, toName, toCode, sourceLabels
        case myUnitFrom, myUnitTo, myUnitMilestoneId
        case people, equipment, cards, depts, retargets, peopleCount, equipmentCount
        case state, appliedAt, undoneAt, createdAt, updatedAt, deletedAt
    }

    var kindValue: OrgUnitChangeKind? { OrgUnitChangeKind(rawValue: kind) }
    var isMerge: Bool { kind == OrgUnitChangeKind.merge.rawValue }
    var isRename: Bool { kind == OrgUnitChangeKind.rename.rawValue }
    var isSplit: Bool { kind == OrgUnitChangeKind.split.rawValue }
    var isUndone: Bool { state == OrgUnitChangeState.undone.rawValue }
    /// 有效（做了、沒復原、沒墓碑）
    var isLive: Bool { !isUndone && deletedAt == nil && appliedAt != nil }
    var allSourceIds: [UUID] { sourceIds ?? [] }
}

/// 搬了一位（部屬、組織人員各記一格；只有組織人員的 subId＝nil）
struct OrgUnitPersonSnap: Codable, Equatable {
    var subId: UUID?
    var orgPersonId: UUID?
    var fromDeptId: UUID?
    var toDeptId: UUID?
    /// 部屬身上的部門字（改之前／改成的）
    var fromText: String?
    var toText: String?

    init(subId: UUID? = nil, orgPersonId: UUID? = nil, fromDeptId: UUID? = nil, toDeptId: UUID? = nil,
         fromText: String? = nil, toText: String? = nil) {
        self.subId = subId
        self.orgPersonId = orgPersonId
        self.fromDeptId = fromDeptId
        self.toDeptId = toDeptId
        self.fromText = fromText
        self.toText = toText
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subId = try? c.decodeIfPresent(UUID.self, forKey: .subId)
        orgPersonId = try? c.decodeIfPresent(UUID.self, forKey: .orgPersonId)
        fromDeptId = try? c.decodeIfPresent(UUID.self, forKey: .fromDeptId)
        toDeptId = try? c.decodeIfPresent(UUID.self, forKey: .toDeptId)
        fromText = try? c.decodeIfPresent(String.self, forKey: .fromText)
        toText = try? c.decodeIfPresent(String.self, forKey: .toText)
    }

    private enum CodingKeys: String, CodingKey {
        case subId, orgPersonId, fromDeptId, toDeptId, fromText, toText
    }
}

/// 搬了一台機台
struct OrgUnitEquipSnap: Codable, Equatable {
    var id: UUID
    var fromDeptId: UUID?
    var toDeptId: UUID?

    init(id: UUID, fromDeptId: UUID? = nil, toDeptId: UUID? = nil) {
        self.id = id
        self.fromDeptId = fromDeptId
        self.toDeptId = toDeptId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        fromDeptId = try? c.decodeIfPresent(UUID.self, forKey: .fromDeptId)
        toDeptId = try? c.decodeIfPresent(UUID.self, forKey: .toDeptId)
    }

    private enum CodingKeys: String, CodingKey {
        case id, fromDeptId, toDeptId
    }
}

/// 改了一張名片的部門字
struct OrgUnitCardSnap: Codable, Equatable {
    var id: UUID
    var fromText: String
    var toText: String

    init(id: UUID, fromText: String, toText: String) {
        self.id = id
        self.fromText = fromText
        self.toText = toText
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        fromText = (try? c.decodeIfPresent(String.self, forKey: .fromText)) ?? ""
        toText = (try? c.decodeIfPresent(String.self, forKey: .toText)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id, fromText, toText
    }
}

/// 一個部門改之前的樣子（Department 沒有 Equatable，這裡另存一份）
struct OrgUnitDeptSnap: Codable, Equatable {
    var id: UUID
    var code: String
    var name: String
    var upstreamIds: [UUID]
    var downstreamIds: [UUID]
    var peerIds: [UUID]
    var managerIds: [UUID]

    init(_ d: Department) {
        id = d.id
        code = d.code
        name = d.name
        upstreamIds = d.upstreamIds
        downstreamIds = d.downstreamIds
        peerIds = d.peerIds
        managerIds = d.managerIds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        code = (try? c.decodeIfPresent(String.self, forKey: .code)) ?? ""
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        upstreamIds = (try? c.decodeIfPresent([UUID].self, forKey: .upstreamIds)) ?? []
        downstreamIds = (try? c.decodeIfPresent([UUID].self, forKey: .downstreamIds)) ?? []
        peerIds = (try? c.decodeIfPresent([UUID].self, forKey: .peerIds)) ?? []
        managerIds = (try? c.decodeIfPresent([UUID].self, forKey: .managerIds)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, code, name, upstreamIds, downstreamIds, peerIds, managerIds
    }
}

/// 排好（還沒生效）的交接單改了哪一邊：side "to" 調進這個部門／"from" 從這個部門調出（這位同仁被一起搬了）
struct OrgUnitRetarget: Codable, Equatable {
    var moveId: UUID
    var side: String
    var fromDeptId: UUID?
    var toDeptId: UUID?

    init(moveId: UUID, side: String, fromDeptId: UUID?, toDeptId: UUID?) {
        self.moveId = moveId
        self.side = side
        self.fromDeptId = fromDeptId
        self.toDeptId = toDeptId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        moveId = try c.decode(UUID.self, forKey: .moveId)
        side = (try? c.decodeIfPresent(String.self, forKey: .side)) ?? "to"
        fromDeptId = try? c.decodeIfPresent(UUID.self, forKey: .fromDeptId)
        toDeptId = try? c.decodeIfPresent(UUID.self, forKey: .toDeptId)
    }

    private enum CodingKeys: String, CodingKey {
        case moveId, side, fromDeptId, toDeptId
    }
}

// MARK: - 我自己調動（一份全組交接單）

/// 我自己調動（u2 S5）：跟我走的人＋其餘一次轉出。每一位的交接單照舊在 life_org_moves_v1，這筆把它們串起來
struct OrgTeamMove: Codable, Equatable, Identifiable {
    let id: UUID
    /// 生效日「2027-01-01」（＝你履歷那筆轉職的日子）
    var effectiveKey: String
    /// 你履歷上那筆「轉職」里程碑
    var milestoneId: UUID?
    /// 調動前你的管理單位（「製造課」）、調到哪（「廠務部」）：只是快照字
    var fromUnit: String?
    var toUnit: String?
    /// 跟我走的人（部屬 id）
    var followerIds: [UUID]?
    /// 跟我走的人一起調到的部門（nil＝部門照舊）
    var followerDeptId: UUID?
    /// 跟我走的人那幾張交接單（kind "move"；部門照舊就沒有）
    var followerMoveIds: [UUID]?
    /// 其餘一次轉出的那幾張交接單（kind "out"、部門照舊）
    var moveIds: [UUID]?
    /// 接任的人（組織人員 id；打名字的＝這次配的 id，只記在單上）
    var successorId: UUID?
    var successorName: String?
    /// 接任的人是組織裡的人（false＝打的名字）
    var successorIsOrg: Bool?
    var createdAt: Date?
    var updatedAt: Date?
    var deletedAt: Date?

    init(id: UUID = UUID(), effectiveKey: String, milestoneId: UUID? = nil, fromUnit: String? = nil, toUnit: String? = nil,
         followerIds: [UUID]? = nil, followerDeptId: UUID? = nil, followerMoveIds: [UUID]? = nil, moveIds: [UUID]? = nil,
         successorId: UUID? = nil, successorName: String? = nil, successorIsOrg: Bool? = nil,
         createdAt: Date? = nil, updatedAt: Date? = nil, deletedAt: Date? = nil) {
        self.id = id
        self.effectiveKey = effectiveKey
        self.milestoneId = milestoneId
        self.fromUnit = fromUnit
        self.toUnit = toUnit
        self.followerIds = followerIds
        self.followerDeptId = followerDeptId
        self.followerMoveIds = followerMoveIds
        self.moveIds = moveIds
        self.successorId = successorId
        self.successorName = successorName
        self.successorIsOrg = successorIsOrg
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        effectiveKey = (try? c.decodeIfPresent(String.self, forKey: .effectiveKey)) ?? ""
        milestoneId = try? c.decodeIfPresent(UUID.self, forKey: .milestoneId)
        fromUnit = try? c.decodeIfPresent(String.self, forKey: .fromUnit)
        toUnit = try? c.decodeIfPresent(String.self, forKey: .toUnit)
        followerIds = try? c.decodeIfPresent([UUID].self, forKey: .followerIds)
        followerDeptId = try? c.decodeIfPresent(UUID.self, forKey: .followerDeptId)
        followerMoveIds = try? c.decodeIfPresent([UUID].self, forKey: .followerMoveIds)
        moveIds = try? c.decodeIfPresent([UUID].self, forKey: .moveIds)
        successorId = try? c.decodeIfPresent(UUID.self, forKey: .successorId)
        successorName = try? c.decodeIfPresent(String.self, forKey: .successorName)
        successorIsOrg = try? c.decodeIfPresent(Bool.self, forKey: .successorIsOrg)
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        deletedAt = try? c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, effectiveKey, milestoneId, fromUnit, toUnit, followerIds, followerDeptId, followerMoveIds, moveIds
        case successorId, successorName, successorIsOrg, createdAt, updatedAt, deletedAt
    }

    var allFollowerIds: [UUID] { followerIds ?? [] }
    var allFollowerMoveIds: [UUID] { followerMoveIds ?? [] }
    var allMoveIds: [UUID] { moveIds ?? [] }
    /// 這份全組交接單裡的每一張（跟我走的在前）
    var everyMoveId: [UUID] { allFollowerMoveIds + allMoveIds }
}

// MARK: - 只在記憶體的列舉（存檔一律存字串）

enum OrgUnitChangeKind: String {
    case rename, merge, split

    /// 部門頁「組織重整」那一列、確認框的字
    var label: String {
        switch self {
        case .rename: return "改名"
        case .merge: return "合併"
        case .split: return "拆成兩個"
        }
    }
}

enum OrgUnitChangeState: String {
    case applied, undone
}

/// 合併到哪：既有的部門、或新設一個
enum OrgReorgTarget: Equatable {
    case existing(UUID)
    case new(code: String, name: String)
}

// MARK: - 只在記憶體的查表

/// LifeStore.orgReorgs 的 didSet 重建（同 OrgMoveIndex）。預設空的（＝沒有任何重整，行為跟以前一模一樣）
enum OrgReorgIndex {
    /// 一個已併入的部門
    struct Merged: Equatable {
        let changeId: UUID
        /// 併進哪個部門
        let intoId: UUID
        /// 「2027-01-01」
        let effectiveKey: String
        /// 合併那時留下的那個的名稱（之後刪掉也看得懂）
        let intoName: String
    }

    /// 已併入的部門 id → 併進哪（同一個部門有兩筆時取生效日晚的、同一天取後做的）
    static var mergedInto: [UUID: Merged] = [:]
    /// 交接單 id → 那一份全組交接單（OrgTeamMove）id
    static var teamOfMove: [UUID: UUID] = [:]

    static func rebuild(_ book: OrgReorgBook) {
        var out: [UUID: Merged] = [:]
        var at: [UUID: (String, Date)] = [:]
        // [v5 驗證] 只算做了、沒復原的（isLive）：〔復原〕了的合併，舊部門要回到挑選清單、組織樹（sim M-39；網頁版 buildMergedIndex 同）
        for c in book.liveChanges where c.isMerge && c.isLive {
            let made: Date = c.appliedAt ?? c.createdAt ?? Date.distantPast
            for s in c.allSourceIds where s != c.deptId {
                if let old = at[s] {
                    if old.0 > c.effectiveKey { continue }
                    if old.0 == c.effectiveKey && old.1 > made { continue }
                }
                at[s] = (c.effectiveKey, made)
                out[s] = Merged(changeId: c.id, intoId: c.deptId, effectiveKey: c.effectiveKey, intoName: c.toName ?? "")
            }
        }
        // 留下的那個後來又被拆回、或你又把它設回來的（之後一筆把它當成合併的「留下的那個」）：照樣看最後那一筆
        mergedInto = out
        var tm: [UUID: UUID] = [:]
        for t in book.liveTeams {
            for m in t.everyMoveId { tm[m] = t.id }
        }
        teamOfMove = tm
    }

    static func isMerged(_ id: UUID?) -> Bool {
        guard let id else { return false }
        return mergedInto[id] != nil
    }

    /// 一路往下找最後併進的那個（A 併進 B、B 又併進 C → C）；最多走 16 步（防繞圈）
    static func finalTarget(_ id: UUID) -> UUID {
        var cur = id
        var steps = 0
        while let m = mergedInto[cur], steps < 16 {
            if m.intoId == id { break }
            cur = m.intoId
            steps += 1
        }
        return cur
    }

    /// 最後併進 target 的所有部門（不含 target 自己；照合併的生效日、再照 id 排，結果固定）
    static func mergeSources(_ target: UUID) -> [UUID] {
        guard !mergedInto.isEmpty else { return [] }
        let ids = mergedInto.keys.filter { $0 != target && finalTarget($0) == target }
        return ids.sorted { a, b in
            let ka = mergedInto[a]?.effectiveKey ?? ""
            let kb = mergedInto[b]?.effectiveKey ?? ""
            if ka != kb { return ka < kb }
            return a.uuidString < b.uuidString
        }
    }
}

// MARK: - 規則與字（純函式；畫面、LifeStore、sim 吃同一支）

/// 合併、改名、拆成兩個要搬的那一群
struct OrgReorgMembers: Equatable {
    /// 部屬 id（含已轉出、暫時離開中的：部門換了，回來那天回到新部門；v4 brief §14）
    var subIds: [UUID] = []
    /// 組織人員 id（含沒連到部屬的；已離職的也搬，組織圖才不會留一個人在舊部門）
    var orgIds: [UUID] = []
    var equipmentIds: [UUID] = []
    /// 「17 位」：組織人員（沒離職的）＋沒有組織人員的部屬
    var peopleCount: Int = 0
}

/// 預覽（合併、改名、拆成兩個的確認頁）
struct OrgReorgPreview: Equatable {
    /// 「2027/1/1 製造一課、製造二課 → 製造課」
    let title: String
    /// 一行一句
    let lines: [String]
    /// 擋住的原因（nil＝可以按）
    let block: String?
}

/// 「你履歷的管理單位也是製造一課，要一起改成製造課嗎？」
struct OrgReorgUnitAsk: Equatable {
    let title: String
    let message: String
    let yes: String
    let no: String
    /// 現在的管理單位字（「製造一課」）、要改成的（「製造課」）
    let from: String
    let to: String
}

/// 部門頁「組織重整」那一區的一列
struct OrgReorgRow: Identifiable, Equatable {
    let changeId: UUID
    /// 「2027/1/1 併入製造課」「2027/1/1 製造一課、製造二課併進來」「2027/1/1 改名：設備課 → 設備工程課」
    let title: String
    /// 「17 位・14 台」
    let sub: String
    let undone: Bool
    var id: UUID { changeId }
}

enum OrgReorgPlan {

    // MARK: 挑選清單

    /// 挑部門的清單不列已併入的部門（keeping：這一筆現在就在那個已併入的部門，照樣列，不然畫面上選不到現在的值）
    static func pickable(_ depts: [Department], keeping: UUID? = nil) -> [Department] {
        guard !OrgReorgIndex.mergedInto.isEmpty else { return depts }
        return depts.filter { !OrgReorgIndex.isMerged($0.id) || $0.id == keeping }
    }

    /// 「已併入製造課」（沒併入＝nil）。名字照留下的那個現在的名字；那個刪了用合併那時的快照
    static func mergedNote(_ deptId: UUID?, world: OrgMoveWorld) -> String? {
        guard let id = deptId, let m = OrgReorgIndex.mergedInto[id] else { return nil }
        let now = world.deptShort(OrgReorgIndex.finalTarget(id))
        let name = now.isEmpty ? m.intoName.trimmingCharacters(in: .whitespaces) : now
        return name.isEmpty ? "已併入其他部門" : "已併入\(name)"
    }

    /// 「2027/1/1 併入製造課」（部門頁頂端那一條）
    static func mergedDetail(_ deptId: UUID?, world: OrgMoveWorld) -> String? {
        guard let id = deptId, let m = OrgReorgIndex.mergedInto[id], let note = mergedNote(id, world: world) else { return nil }
        let rest = note.hasPrefix("已") ? String(note.dropFirst()) : note
        return "\(OrgMovePlan.fullDay(m.effectiveKey)) \(rest)"
    }

    // MARK: 部門字

    /// 「MFG — 製造課」（同 LifeStore.departmentLabel）
    static func label(code: String, name: String) -> String {
        let c = code.trimmingCharacters(in: .whitespaces)
        let n = name.trimmingCharacters(in: .whitespaces)
        if c.isEmpty { return n }
        if n.isEmpty { return c }
        return "\(c) — \(n)"
    }

    /// 句子裡的部門名（「製造課」；沒名稱＝代碼）
    static func short(code: String, name: String) -> String {
        let n = name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? code.trimmingCharacters(in: .whitespaces) : n
    }

    /// App 自動寫的部門字（空白、名稱、代碼、「代碼 — 名稱」、「代碼 名稱」）：跟這幾種一樣才換成新的；你自己改過字的不動
    static func autoTexts(code: String, name: String) -> Set<String> {
        let c = code.trimmingCharacters(in: .whitespaces)
        let n = name.trimmingCharacters(in: .whitespaces)
        var out: Set<String> = ["", n, c, label(code: c, name: n)]
        if !c.isEmpty && !n.isEmpty { out.insert("\(c) \(n)") }
        return out
    }

    /// 部門字要不要換：原本是 App 自動寫的（autoTexts）＝新的字；你自己改過的＝原樣
    static func retitled(_ text: String, fromCode: String, fromName: String, to newLabel: String) -> String {
        let t = text.trimmingCharacters(in: .whitespaces)
        return autoTexts(code: fromCode, name: fromName).contains(t) ? newLabel : text
    }

    // MARK: 要搬的人與機台

    static func members(_ deptIds: Set<UUID>, world: OrgMoveWorld) -> OrgReorgMembers {
        var m = OrgReorgMembers()
        guard !deptIds.isEmpty else { return m }
        var linked = Set<UUID>()
        for p in world.orgPeople {
            guard let d = p.departmentId, deptIds.contains(d) else { continue }
            m.orgIds.append(p.id)
            if !p.isInactive { m.peopleCount += 1 }
        }
        for p in world.orgPeople {
            if let s = p.linkedSubordinateId { linked.insert(s) }
        }
        for s in world.subordinates {
            guard let d = s.departmentId, deptIds.contains(d) else { continue }
            m.subIds.append(s.id)
            if !linked.contains(s.id) { m.peopleCount += 1 }
        }
        for e in world.equipment {
            guard let d = e.departmentId, deptIds.contains(d) else { continue }
            m.equipmentIds.append(e.id)
        }
        return m
    }

    /// 管理人員合在一起：照部門的順序接起來、同一位只留第一次（還在組織裡的）
    static func managersUnion(_ ordered: [Department], world: OrgMoveWorld) -> [UUID] {
        var out: [UUID] = []
        var seen = Set<UUID>()
        for d in ordered {
            for id in d.managerIds where !seen.contains(id) {
                seen.insert(id)
                if world.orgPeople.contains(where: { $0.id == id }) { out.append(id) }
            }
        }
        return out
    }

    // MARK: 你履歷的管理單位

    /// 「你履歷的管理單位也是製造一課，要一起改成製造課嗎？」（你的管理單位不是這幾個名字＝nil）
    static func myUnitAsk(oldNames: [String], newName: String, myUnit: String?) -> OrgReorgUnitAsk? {
        let unit = (myUnit ?? "").trimmingCharacters(in: .whitespaces)
        let to = newName.trimmingCharacters(in: .whitespaces)
        guard !unit.isEmpty, !to.isEmpty, unit != to else { return nil }
        let olds = oldNames.map { $0.trimmingCharacters(in: .whitespaces) }
        guard olds.contains(unit) else { return nil }
        return OrgReorgUnitAsk(title: "你履歷的管理單位也是\(unit)",
                               message: "要一起改成\(to)嗎？不改的話，「我」會從\(to)的管理人員消失（App 用管理單位的名字比對）。",
                               yes: "一起改", no: "不用", from: unit, to: to)
    }

    // MARK: 預覽

    /// 合併的確認頁。sources＝要併進去的（第一個是你打開的那個）；target＝既有的部門或新設一個
    static func mergePreview(sources: [UUID], target: OrgReorgTarget, keepManagers: Bool, effectiveKey: String,
                             book: OrgMoveBook, world: OrgMoveWorld, todayKey: String) -> OrgReorgPreview {
        let srcDepts: [Department] = sources.compactMap { world.dept($0) }
        var targetName = ""
        var targetLabel = ""
        var targetDept: Department?
        switch target {
        case .existing(let id):
            targetDept = world.dept(id)
            targetName = world.deptShort(id)
            targetLabel = world.deptLabel(id)
        case .new(let code, let name):
            targetName = short(code: code, name: name)
            targetLabel = label(code: code, name: name)
        }
        let srcNames: [String] = srcDepts.map { short(code: $0.code, name: $0.name) }
        let title = "\(OrgMovePlan.fullDay(effectiveKey)) \(srcNames.joined(separator: "、")) → \(targetName)"
        var block: String?
        if srcDepts.isEmpty {
            block = "請選要併進去的部門"
        } else if targetName.isEmpty {
            block = "請選要併到哪個部門，或打新部門的名稱"
        } else if let t = targetDept, sources.contains(t.id) {
            block = "不能併到自己"
        } else if effectiveKey > todayKey {
            block = "生效日只能選今天或以前（排在以後的組織重整，到那天再按）"
        }
        var lines: [String] = []
        var countParts: [String] = []
        var total = 0
        for d in srcDepts {
            let n = members([d.id], world: world).peopleCount
            total += n
            countParts.append("\(short(code: d.code, name: d.name)) \(n) 位")
        }
        if let t = targetDept {
            let n = members([t.id], world: world).peopleCount
            if n > 0 {
                total += n
                countParts.append("\(targetName) \(n) 位")
            }
        }
        lines.append(countParts.joined(separator: "＋") + "＝\(targetName) \(total) 位")
        var eqParts: [String] = []
        var eqTotal = 0
        for d in srcDepts {
            let n = members([d.id], world: world).equipmentIds.count
            eqTotal += n
            eqParts.append("\(n)")
        }
        if let t = targetDept {
            let n = members([t.id], world: world).equipmentIds.count
            if n > 0 {
                eqTotal += n
                eqParts.append("\(n)")
            }
        }
        if eqTotal > 0 { lines.append("機台 " + eqParts.joined(separator: "＋") + "＝\(eqTotal) 台") }
        if !targetLabel.isEmpty { lines.append("部屬身上的部門字、名片一起改成「\(targetLabel)」（你自己改過字的不動）") }
        if keepManagers {
            var ordered: [Department] = []
            if let t = targetDept { ordered.append(t) }
            ordered.append(contentsOf: srcDepts)
            let names = managersUnion(ordered, world: world).map { world.orgPersonName($0) }.filter { !$0.isEmpty }
            lines.append(names.isEmpty ? "管理人員：沒有（之後在部門頁設定）" : "管理人員合在一起：" + names.joined(separator: "、"))
        } else {
            lines.append("管理人員：\(targetName)照舊（之後在部門頁重新選）")
        }
        let oldNames = srcNames.joined(separator: "、")
        lines.append("舊的\(oldNames)留著，標「已併入\(targetName)」，挑部門的清單不再出現")
        lines.append("還沒送出的互評票：同職等的接成一組，排好的順序照留；送出的不動")
        lines.append("人沒換工作，不用交接：待辦、會議、週報、班照舊在原本的人身上")
        let srcSet = Set(sources)
        var planned = 0
        for m in book.live where m.orgPending {
            let toHit: Bool = m.to.deptId.map { srcSet.contains($0) } ?? false
            let fromHit: Bool = m.from.deptId.map { srcSet.contains($0) } ?? false
            if toHit || fromHit { planned += 1 }
        }
        if planned > 0 { lines.append("排好還沒生效的交接單 \(planned) 張，部門改成\(targetName)") }
        var awayN = 0
        for sid in members(srcSet, world: world).subIds where OrgMoveIndex.awayNow(sid, todayKey: todayKey) != nil { awayN += 1 }
        if awayN > 0 { lines.append("暫時離開中的 \(awayN) 位照樣搬（回來那天回到\(targetName)）") }
        return OrgReorgPreview(title: title, lines: lines, block: block)
    }

    /// 改名的確認頁
    static func renamePreview(deptId: UUID, newCode: String, newName: String, effectiveKey: String,
                              world: OrgMoveWorld, todayKey: String) -> OrgReorgPreview {
        let d = world.dept(deptId)
        let oldShort = d.map { short(code: $0.code, name: $0.name) } ?? ""
        let newShort = short(code: newCode, name: newName)
        let newLabel = label(code: newCode, name: newName)
        let title = "\(OrgMovePlan.fullDay(effectiveKey)) 改名：\(oldShort) → \(newShort)"
        var block: String?
        if newName.trimmingCharacters(in: .whitespaces).isEmpty {
            block = "請打新的名稱"
        } else if let d, d.name.trimmingCharacters(in: .whitespaces) == newName.trimmingCharacters(in: .whitespaces),
                  d.code.trimmingCharacters(in: .whitespaces) == newCode.trimmingCharacters(in: .whitespaces) {
            block = "名稱、代碼都沒有變"
        } else if effectiveKey > todayKey {
            block = "生效日只能選今天或以前"
        }
        let m = members([deptId], world: world)
        var lines: [String] = []
        let subN = m.subIds.count
        if subN > 0 { lines.append("部屬 \(subN) 位身上的部門字改成「\(newLabel)」（你自己改過字的不動）") }
        let cardN = cardCount(orgIds: m.orgIds, code: d?.code ?? "", name: d?.name ?? "", world: world)
        if cardN > 0 { lines.append("名片 \(cardN) 張的部門字一起改") }
        lines.append("組織圖、機台、管理人員照舊（同一個部門，只是換名字）")
        lines.append("交接單、互評票上的舊名字不改（那是當時的紀錄）")
        return OrgReorgPreview(title: title, lines: lines, block: block)
    }

    /// 拆成兩個的確認頁（orgIds＝在部門頁勾的人；subIds＝沒有組織人員的部屬）
    static func splitPreview(deptId: UUID, newCode: String, newName: String, orgIds: Set<UUID>, subIds: Set<UUID>,
                             equipmentIds: Set<UUID>, effectiveKey: String, world: OrgMoveWorld, todayKey: String) -> OrgReorgPreview {
        let oldShort = world.deptShort(deptId)
        let newShort = short(code: newCode, name: newName)
        let title = "\(OrgMovePlan.fullDay(effectiveKey)) \(oldShort) 拆出 \(newShort)"
        let all = members([deptId], world: world)
        var moved = 0
        for p in world.orgPeople where orgIds.contains(p.id) && p.departmentId == deptId && !p.isInactive { moved += 1 }
        for s in world.subordinates where subIds.contains(s.id) && s.departmentId == deptId { moved += 1 }
        var block: String?
        if newName.trimmingCharacters(in: .whitespaces).isEmpty {
            block = "請打新部門的名稱"
        } else if world.departments.contains(where: { $0.name.trimmingCharacters(in: .whitespaces) == newName.trimmingCharacters(in: .whitespaces) }) {
            block = "已經有叫「\(newShort)」的部門了"
        } else if moved == 0 && equipmentIds.isEmpty {
            block = "請勾要過去的人或機台"
        } else if effectiveKey > todayKey {
            block = "生效日只能選今天或以前"
        }
        var lines: [String] = []
        lines.append("\(oldShort) \(all.peopleCount) 位 → \(oldShort) \(max(all.peopleCount - moved, 0)) 位＋\(newShort) \(moved) 位")
        if !equipmentIds.isEmpty { lines.append("機台 \(equipmentIds.count) 台到\(newShort)") }
        lines.append("過去的人身上的部門字、名片一起改成「\(label(code: newCode, name: newName))」")
        lines.append("新部門的管理人員、上下游部門之後在部門頁設定")
        lines.append("人沒換工作，不用交接：待辦、會議、週報、班照舊在原本的人身上")
        return OrgReorgPreview(title: title, lines: lines, block: block)
    }

    /// 這幾位組織人員的名片裡，部門字是 App 自動寫的（會一起改的）張數
    static func cardCount(orgIds: [UUID], code: String, name: String, world: OrgMoveWorld) -> Int {
        let auto = autoTexts(code: code, name: name)
        var n = 0
        for id in orgIds {
            guard let p = world.orgPeople.first(where: { $0.id == id }), let cid = p.linkedBusinessCardId,
                  let card = world.businessCards.first(where: { $0.id == cid }) else { continue }
            if auto.contains(card.department.trimmingCharacters(in: .whitespaces)) { n += 1 }
        }
        return n
    }

    // MARK: 互評票：兩課同職等接成一組

    /// 還沒送出的票重新分組時，fresh 那一組（製造課・E3）要接上的舊順序：完全同一組的先、再來是併進這一課的舊課同職等那幾組（照票上的先後），
    /// 同一個人只留第一次；舊順序裡已經不在 fresh 的人拿掉，fresh 多出來的人接在最後。一組都對不到＝nil（照 fresh 原樣）
    static func carriedEntries(for fresh: PerformanceRankGroup, in old: [PerformanceRankGroup]) -> [PerformanceRankEntry]? {
        var picked: [PerformanceRankGroup] = []
        if let exact = old.first(where: { $0.departmentId == fresh.departmentId && $0.gradeId == fresh.gradeId }) {
            picked.append(exact)
        }
        if let target = fresh.departmentId {
            let sources = Set(OrgReorgIndex.mergeSources(target))
            if !sources.isEmpty {
                for g in old where g.gradeId == fresh.gradeId {
                    guard let d = g.departmentId, sources.contains(d) else { continue }
                    picked.append(g)
                }
            }
        }
        guard !picked.isEmpty else { return nil }
        let validIds = Set(fresh.entries.map(\.id))
        var seen = Set<UUID>()
        var ordered: [PerformanceRankEntry] = []
        for g in picked {
            for e in g.entries where validIds.contains(e.id) && !seen.contains(e.id) {
                seen.insert(e.id)
                ordered.append(e)
            }
        }
        for e in fresh.entries where !seen.contains(e.id) {
            seen.insert(e.id)
            ordered.append(e)
        }
        let nameOf = Dictionary(fresh.entries.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return ordered.map { PerformanceRankEntry(id: $0.id, name: nameOf[$0.id] ?? $0.name) }
    }

    // MARK: 部門頁「組織重整」、復原

    /// 復原的期限：生效日與按下去那天取晚的＋7 天（同轉組織）
    static func undoUntilKey(_ c: OrgUnitChange) -> String {
        let applied = c.appliedAt.map { OrgMovePlan.dayKey($0) } ?? c.effectiveKey
        return OrgMovePlan.addDays(max(c.effectiveKey, applied), 7)
    }

    static func canUndo(_ c: OrgUnitChange, todayKey: String) -> Bool {
        c.isLive && todayKey <= undoUntilKey(c)
    }

    /// 這個部門的重整紀錄（新到舊）：改名、合併（併進來的、併出去的）、拆出去／拆出來
    static func rows(deptId: UUID, book: OrgReorgBook, world: OrgMoveWorld) -> [OrgReorgRow] {
        var out: [(String, Date, OrgReorgRow)] = []
        for c in book.allChanges where c.deletedAt == nil && c.appliedAt != nil {
            let involved = c.deptId == deptId || c.allSourceIds.contains(deptId) || c.newDeptId == deptId
            guard involved else { continue }
            out.append((c.effectiveKey, c.appliedAt ?? Date.distantPast,
                        OrgReorgRow(changeId: c.id, title: rowTitle(c, deptId: deptId, world: world),
                                    sub: rowSub(c), undone: c.isUndone)))
        }
        return out.sorted { a, b in a.0 != b.0 ? a.0 > b.0 : a.1 > b.1 }.map { $0.2 }
    }

    static func rowTitle(_ c: OrgUnitChange, deptId: UUID, world: OrgMoveWorld) -> String {
        let d = OrgMovePlan.fullDay(c.effectiveKey)
        let undone = c.isUndone ? "（已復原）" : ""
        switch c.kindValue {
        case .some(.rename):
            let f = short(code: c.fromCode ?? "", name: c.fromName ?? "")
            let t = short(code: c.toCode ?? "", name: c.toName ?? "")
            return "\(d) 改名：\(f) → \(t)\(undone)"
        case .some(.merge):
            let into = (c.toName ?? "").trimmingCharacters(in: .whitespaces)
            if c.deptId == deptId {
                let names = (c.sourceLabels ?? []).map { OrgMovePlan.labelShort($0) }.filter { !$0.isEmpty }
                return "\(d) \(names.joined(separator: "、"))併進來\(undone)"
            }
            return "\(d) 併入\(into.isEmpty ? world.deptShort(c.deptId) : into)\(undone)"
        case .some(.split):
            let t = short(code: c.toCode ?? "", name: c.toName ?? "")
            if c.newDeptId == deptId {
                let f = short(code: c.fromCode ?? "", name: c.fromName ?? "")
                return "\(d) 從\(f)拆出來\(undone)"
            }
            return "\(d) 拆出 \(t)\(undone)"
        case .none:
            return "\(d) 組織重整\(undone)"
        }
    }

    static func rowSub(_ c: OrgUnitChange) -> String {
        var parts: [String] = []
        if let n = c.peopleCount, n > 0 { parts.append("\(n) 位") }
        if let n = c.equipmentCount, n > 0 { parts.append("\(n) 台") }
        if c.myUnitTo != nil { parts.append("履歷的管理單位一起改") }
        return parts.joined(separator: "・")
    }

    /// 〔復原〕確認框
    static func undoAsk(_ c: OrgUnitChange, world: OrgMoveWorld) -> (title: String, message: String) {
        let d = OrgMovePlan.shortDay(c.effectiveKey)
        switch c.kindValue {
        case .some(.rename):
            let f = short(code: c.fromCode ?? "", name: c.fromName ?? "")
            return ("復原 \(d) 的改名？", "部門名稱改回「\(f)」，部屬身上的部門字、名片照改之前的樣子（之後你自己改過的不動）。")
        case .some(.merge):
            // [v5 裁定] 原本寫「互評票已經接成一組的不拆回」，跟實際對不上：還沒送出的票照「現在的課 × 職等」分組，
            // 復原後人回到兩課就分回兩組；合併期間打開過的票（已存成「製造課・E3」）找不到舊組，那幾組回到預設順序。送出的不動。
            // 要退回這一件：改回原本那一句
            return ("復原 \(d) 的合併？", "搬過去的人、機台回到原本的部門，管理人員、上下游改回合併前的樣子；之後你自己改過的不動。還沒送出的互評票照原本的課分回去（合併後打開過的，那幾組的順序要重排）；送出的不動。")
        default:
            return ("復原 \(d) 的拆分？", "拆過去的人、機台回到原本的部門；新部門空了就拿掉。之後你自己改過的不動。")
        }
    }
}
