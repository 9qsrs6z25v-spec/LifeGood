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
    /// 沒有墓碑的（[v25.592 轉組織 v1b] 排好、什麼都還沒做的〔取消〕寫 deletedAt＝墓碑；兩台合併時墓碑勝過比它舊的）
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
    /// nil／"now"＝確認那一刻全部做；[v25.592 轉組織 v1b] "handoverNow" 現在就交接、生效那天才改部門／"together" 生效那天一起做（OrgMoveTiming）
    var timing: String?
    var from: OrgMoveSide
    var to: OrgMoveSide
    /// 新部門〔照舊（只交接）〕：組織那幾格不動
    var keepDept: Bool?
    /// 你自己打的備註（「人事令 1015-07 號」）；只有你看得到，不上分享
    var note: String?
    /// "applied" 全部做完／"closed" 按了〔交接完成〕／"undone" 復原了；[v25.592 轉組織 v1b] "planned" 排好了／"handed" 事情交了、部門還沒改／"cancelled" 排好的取消了
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
    // [v25.592 轉組織 v1b] 排在以後（judge §3.5、§3.8、§5-15、§5-21、§7 v1b；orgmove/build/v1b/brief.md §2-1）。
    // 新欄位一律 Optional＋decodeIfPresent＋init 預設 nil：v1a 存的舊單沒有這幾個＝不影響；25.591 的 App 讀到不認得的欄位照樣解得開。
    // 要退回這一件：刪這 3 個欄位與 init／init(from:)／CodingKeys 裡對應的那幾行。
    /// 生效前取消的時間（排好的〔取消〕；已經交出去的〔拿回來〕〔留給接手的人〕；〔只做交接〕不算取消）
    var cancelledAt: Date?
    /// 取消、只做交接時寫下的一句（「原本 11/1 要調設備課，10/30 取消了調動；交出去的照舊」）；交接單「組織」那一列、歷程照寫
    var cancelNote: String?
    /// 生效那天改部門時（排好之後）原人身上多出來、單上沒有的待辦、週報 id（「排好之後多了 2 件」〔加進交接單〕；judge §5-15）
    var lateRefIds: [UUID]?

    init(id: UUID = UUID(), personId: UUID, personKind: String? = nil, personName: String,
         kind: String = OrgMoveKind.move.rawValue, effectiveKey: String, handoverByKey: String? = nil,
         timing: String? = nil, from: OrgMoveSide = OrgMoveSide(), to: OrgMoveSide = OrgMoveSide(),
         keepDept: Bool? = nil, note: String? = nil, state: String = OrgMoveState.applied.rawValue,
         handedAt: Date? = nil, appliedAt: Date? = nil, closedAt: Date? = nil, undoneAt: Date? = nil,
         lines: [OrgMoveLine]? = nil, before: OrgMoveRestore? = nil, retitleBirthday: Bool? = nil,
         createdAt: Date? = nil, updatedAt: Date? = nil, deletedAt: Date? = nil,
         cancelledAt: Date? = nil, cancelNote: String? = nil, lateRefIds: [UUID]? = nil) {
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
        self.cancelledAt = cancelledAt
        self.cancelNote = cancelNote
        self.lateRefIds = lateRefIds
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
        cancelledAt = try? c.decodeIfPresent(Date.self, forKey: .cancelledAt)
        cancelNote = try? c.decodeIfPresent(String.self, forKey: .cancelNote)
        lateRefIds = try? c.decodeIfPresent([UUID].self, forKey: .lateRefIds)
    }

    private enum CodingKeys: String, CodingKey {
        case id, personId, personKind, personName, kind, effectiveKey, handoverByKey, timing
        case from, to, keepDept, note, state, handedAt, appliedAt, closedAt, undoneAt
        case lines, before, retitleBirthday, createdAt, updatedAt, deletedAt
        case cancelledAt, cancelNote, lateRefIds
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
    // [v25.593 轉組織 v2] 調出、離職、退休、回到我的部屬（judge §2.2「已轉出也用算的」、§3.6；orgmove/build/v2/brief.md §2-1）。
    // 不加任何存檔欄位：kind 本來就是字串（25.592 的 App 讀到不認得的 kind＝只顯示、不套用，存回去照原樣）。
    // 要退回這一件：刪這 6 支，用到的地方改回 `kind == OrgMoveKind.move.rawValue && keepDept != true && …`
    /// 只在記憶體轉成列舉（不認得的字＝nil）
    var kindValue: OrgMoveKind? { OrgMoveKind(rawValue: kind) }
    /// 調出我的管轄、離職、退休（生效後這位同仁收進「已轉出」）
    var isLeaving: Bool { kindValue?.isLeaving == true }
    /// 離職、退休（組織人員同時設成「已離職」；沒有新部門、廠區、職稱）
    var isLeaveCompany: Bool { kindValue?.isLeaveCompany == true }
    /// 回到我的部屬（已轉出的人〔回到我的部屬〕記的那一張；什麼都不搬）
    var isBack: Bool { kind == OrgMoveKind.back.rawValue }
    /// 部門有改（換單位或調出、不是〔照舊（只交接）〕、新部門跟舊的不一樣）。
    /// v1a～v1b 寫成 `kind == "move" && keepDept != true && to.deptId != nil && to.deptId != from.deptId` 的地方都換成這一支（調出也改部門）
    var changesDept: Bool {
        (kindValue?.canChangeDept ?? false) && keepDept != true && to.deptId != nil && to.deptId != from.deptId
    }
    /// 組織那幾格做完了（生效了）：套用過、沒復原、不是排好／交了還沒改部門、沒墓碑。已轉出、班表照那天的部門都只看這種
    var orgDone: Bool { wasApplied && !isUndone && !orgPending && deletedAt == nil }
    /// 已經套用過（復原的也算：歷程照樣列一行灰字）
    var wasApplied: Bool { appliedAt != nil || handedAt != nil }
    /// [v25.592 轉組織 v1b] 排好了、什麼都還沒做（〔11/1 一起做〕，生效那天才一起做）
    var isPlanned: Bool { state == OrgMoveState.planned.rawValue }
    /// [v25.592 轉組織 v1b] 事情交出去了、部門還沒改（〔現在就交接，11/1 才改部門〕）
    var isHanded: Bool { state == OrgMoveState.handed.rawValue }
    /// [v25.592 轉組織 v1b] 排好的〔取消〕（什麼都沒做過；同時寫了 deletedAt，live 看不到）
    var isCancelled: Bool { state == OrgMoveState.cancelled.rawValue }
    /// [v25.592 轉組織 v1b 裁定] 生效前〔取消這張單〕〔拿回來〕復原的（記了取消的時間、沒有「取消了調動」那一句）：寫「已取消」。
    /// 〔留給接手的人〕之後 7 天內又按〔復原〕的（cancelNote 有值）照實寫「已復原」。
    /// 要退回這一件：刪這一支，歷程、單頭、「組織」那一列、交接單徽章那 5 處改回 `cancelledAt != nil`
    var undoneByCancel: Bool { isUndone && cancelledAt != nil && cancelNote == nil }
    /// [v25.592 轉組織 v1b] 部門、廠區還沒改（排好的、交出去了還沒到生效日的）：名單膠囊「11/1 起 設備課」、到期套用看這個
    var orgPending: Bool { (isPlanned || isHanded) && deletedAt == nil }
    /// [v25.592 轉組織 v1b] 什麼時候做（nil／"now"＝確認那一刻全部做）
    var timingValue: OrgMoveTiming { timing.flatMap { OrgMoveTiming(rawValue: $0) } ?? .now }

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
            // [v25.592 轉組織 v1b 驗證] 取了哪一份，另一份有、這一份沒有的 v1b 欄位補回來（keepingV1bFields）。
            // 要退回這一件：這個 if let 換回 `if let o = theirs[l.id], (o.updatedAt ?? Date.distantPast) > mineT { out.append(o) } else { out.append(l) }`
            if let o = theirs[l.id] {
                let oT: Date = o.updatedAt ?? Date.distantPast
                if oT > mineT {
                    out.append(keepingV1bFields(o, from: l, sameTime: false))
                } else {
                    out.append(keepingV1bFields(l, from: o, sameTime: oT == mineT))
                }
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
        // [v25.592 轉組織 v1b 驗證] 25.591 的 App 不認得 v1b 加的欄位：它那台一存檔（改了任何東西都整包重存、推上 iCloud）
        // 這幾個欄位就不見了，updatedAt 卻沒變（一樣新時本來取 a＝收進來的那份），取消調動那一句、「已交」就被洗掉。
        // 從另一份補回：取消的時間與那一句 v1b 從不清掉（排好、還沒生效的不補：那是另一台又改回排好的）；
        // lateRefIds〔加進交接單〕會清掉，只在一樣新時補。要退回這一件：刪這三行
        if !head.orgPending, head.cancelledAt == nil { head.cancelledAt = a.cancelledAt ?? b.cancelledAt }
        if !head.orgPending, head.cancelNote == nil { head.cancelNote = a.cancelNote ?? b.cancelNote }
        if aT == bT, head.lateRefIds == nil { head.lateRefIds = a.lateRefIds ?? b.lateRefIds }
        // [v25.593 轉組織 v2] 離職、退休前組織人員是不是已離職（復原用；25.592 的 App 存回來會少這兩個）：哪一份有就補回。
        // 要退回這一件：刪這兩行
        if head.before != nil, head.before?.orgInactive == nil { head.before?.orgInactive = a.before?.orgInactive ?? b.before?.orgInactive }
        if head.before != nil, head.before?.orgLeftDate == nil { head.before?.orgLeftDate = a.before?.orgLeftDate ?? b.before?.orgLeftDate }
        return head
    }

    /// [v25.592 轉組織 v1b 驗證] 同一列的兩份：win＝取的那一份；另一份有、win 沒有的 v1b 欄位補回（25.591 的 App 存回來會少這兩個）。
    /// addedLate v1b 從不清掉，一律補；checkedAt 你取消「已交」時會寫新的 updatedAt，只在一樣新時補（不會被舊的那份勾回來）。
    /// 要退回這一件：刪這支，merge 裡那個 if let 換回原本的兩行
    private static func keepingV1bFields(_ win: OrgMoveLine, from other: OrgMoveLine, sameTime: Bool) -> OrgMoveLine {
        var l = win
        if l.addedLate == nil { l.addedLate = other.addedLate }
        if sameTime, l.checkedAt == nil { l.checkedAt = other.checkedAt }
        return l
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
    ///／"meeting"／"agenda"／"shifts"（v1a-2）
    var kind: String
    /// 那一筆的 id（任務、機台、週報、會議、議程；manager／managerAdd＝部門 id；sideRole＝兼任待辦 id；shifts＝nil）
    var refId: UUID?
    /// 只有 sideRole：掛在這位同仁身上的那一筆（任務或議程）id
    var itemId: UUID?
    /// 警報任務／跟著機台的待辦、週報所屬的機台；sideRole 的兼任 id；agenda 所在的會議；meeting 連到的（要交的）機台
    var parentId: UUID?
    /// 東西掛在誰身上（agenda＝會議主人：別人會議裡的議程是那位；其他都是本人）
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
    // [v25.591 轉組織 v1a-2] 會議、議程、班、兼任（judge §2.1 OrgMoveLine 表的 newId／newTopic／days／removedShifts；
    // 新欄位一律 Optional＋decodeIfPresent：v1a-1 存的舊單沒有這幾個＝不影響）。
    // 要退回這一件：刪這 6 個欄位與 init／init(from:)／CodingKeys 裡對應的那幾行。
    /// 只有 sideRole（兼任的議程那種）：議程所在的會議 id（兼任待辦的任務那種＝nil）
    var meetingId: UUID?
    /// 會議〔交給…〕（newSeries）：新會議先配好的 id——兩台同時套用、重做也只有一條
    var newId: UUID?
    /// 會議〔交給…〕：新會議的名稱（原本的名稱拿掉人名，「王小明 週會」→「週會」；你可以改）
    var newTopic: String?
    /// 只有 shifts：撞班那幾天怎麼辦（"2026-11-04": "overwrite" 改成…／"drop" 這天清掉／"<部屬 id>" 這天交給別人）
    var days: [String: String]?
    /// 只有 shifts：搬走、清掉的班，和接手的人被蓋掉的那一格（復原放得回去）
    var removedShifts: [OrgMoveShiftCell]?
    /// 只有 agenda〔改由…〕：交接前的負責人（復原照這個放回；本來沒指派＝空陣列）
    var prevAssigneeIds: [UUID]?
    // [v25.592 轉組織 v1b] 你自己加的一項（kind "custom"：門禁卡、鑰匙、帳號…，只記在單上）、排好之後才加進來的那幾列。
    // 新欄位一律 Optional＋decodeIfPresent＋init 預設 nil。要退回這一件：刪這 2 個欄位與 init／init(from:)／CodingKeys 對應的那幾行。
    /// 只有 custom：勾了「已交」的時間（nil＝還沒交）
    var checkedAt: Date?
    /// 排好之後原人才多出來、你按〔加進交接單〕加進來的（交接單那一列多一行灰字「排好之後才加進來的」）
    var addedLate: Bool?

    init(id: UUID = UUID(), kind: String, refId: UUID? = nil, itemId: UUID? = nil, parentId: UUID? = nil,
         holderId: UUID? = nil, title: String, dueKey: String? = nil, action: String? = nil,
         toId: UUID? = nil, toName: String? = nil, newDueKey: String? = nil, wasOverdue: Bool? = nil,
         memo: String? = nil, lock: String? = nil, slot: Int? = nil, removedJSON: Data? = nil,
         state: String? = nil, resolvedAt: Date? = nil, updatedAt: Date? = nil,
         meetingId: UUID? = nil, newId: UUID? = nil, newTopic: String? = nil, days: [String: String]? = nil,
         removedShifts: [OrgMoveShiftCell]? = nil, prevAssigneeIds: [UUID]? = nil,
         checkedAt: Date? = nil, addedLate: Bool? = nil) {
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
        self.meetingId = meetingId
        self.newId = newId
        self.newTopic = newTopic
        self.days = days
        self.removedShifts = removedShifts
        self.prevAssigneeIds = prevAssigneeIds
        self.checkedAt = checkedAt
        self.addedLate = addedLate
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
        meetingId = try? c.decodeIfPresent(UUID.self, forKey: .meetingId)
        newId = try? c.decodeIfPresent(UUID.self, forKey: .newId)
        newTopic = try? c.decodeIfPresent(String.self, forKey: .newTopic)
        days = try? c.decodeIfPresent([String: String].self, forKey: .days)
        removedShifts = try? c.decodeIfPresent([OrgMoveShiftCell].self, forKey: .removedShifts)
        prevAssigneeIds = try? c.decodeIfPresent([UUID].self, forKey: .prevAssigneeIds)
        checkedAt = try? c.decodeIfPresent(Date.self, forKey: .checkedAt)
        addedLate = try? c.decodeIfPresent(Bool.self, forKey: .addedLate)
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, refId, itemId, parentId, holderId, title, dueKey, action, toId, toName
        case newDueKey, wasOverdue, memo, lock, slot, removedJSON, state, resolvedAt, updatedAt
        case meetingId, newId, newTopic, days, removedShifts, prevAssigneeIds
        case checkedAt, addedLate
    }

    // 只在記憶體轉成列舉（不認得的字＝nil：只顯示、不套用）
    var lineKind: OrgMoveLineKind? { OrgMoveLineKind(rawValue: kind) }
    var lineAction: OrgMoveAction? { action.flatMap { OrgMoveAction(rawValue: $0) } }
    var lineState: OrgMoveLineState? { state.flatMap { OrgMoveLineState(rawValue: $0) } }
    var lineLock: OrgMoveLock? { lock.flatMap { OrgMoveLock(rawValue: $0) } }
    var isLocked: Bool { lock != nil }
    /// 組織那幾列（第 ① 步問的；頂端四格不算）
    var isOrgLine: Bool { kind == OrgMoveLineKind.manager.rawValue || kind == OrgMoveLineKind.managerAdd.rawValue }

    /// [v25.592 轉組織 v1b] 你自己加的一項（門禁卡、鑰匙、帳號…）的 kind 字。**不放進 OrgMoveLineKind**：
    /// 加一個 case 要改二十幾個 switch（畫面那幾個檔各組各自的）；lineKind＝nil 的列原本就是「只顯示、不套用」，
    /// 剛好是這一種要的（只記在單上、不動任何資料）。要用到它的地方一律看 isCustom。25.591 的 App 讀到也只顯示不套用。
    static let customKind = "custom"
    var isCustom: Bool { kind == Self.customKind }
    /// 自己加的、沒被拿掉的（拿掉＝state "undone"：逐列合併時另一台還有這一列也不會長回來）
    var isLiveCustom: Bool { isCustom && state != OrgMoveLineState.undone.rawValue }
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
    // [v25.593 轉組織 v2] 離職、退休會把組織人員設成「已離職」：套用前的樣子（復原放回）。新欄位 Optional＋decodeIfPresent＋init 預設 nil；
    // 舊單沒有＝不影響。要退回這一件：刪這 2 個欄位與 init／init(from:)／CodingKeys 對應的那幾行
    /// 套用前組織人員是不是已離職（nil＝舊單或沒有組織人員；復原時當 false）
    var orgInactive: Bool?
    /// 套用前組織人員的離職日
    var orgLeftDate: Date?

    init(deptId: UUID? = nil, deptText: String? = nil, plant: String? = nil,
         gradeTitleId: UUID? = nil, jobTitle: String? = nil,
         orgPersonId: UUID? = nil, orgDeptId: UUID? = nil, orgJobTitle: String? = nil,
         orgGradeTitleId: UUID? = nil, createdOrgPerson: Bool? = nil,
         cardId: UUID? = nil, cardDept: String? = nil, cardJobTitle: String? = nil,
         orgInactive: Bool? = nil, orgLeftDate: Date? = nil) {
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
        self.orgInactive = orgInactive
        self.orgLeftDate = orgLeftDate
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
        orgInactive = try? c.decodeIfPresent(Bool.self, forKey: .orgInactive)
        orgLeftDate = try? c.decodeIfPresent(Date.self, forKey: .orgLeftDate)
    }

    private enum CodingKeys: String, CodingKey {
        case deptId, deptText, plant, gradeTitleId, jobTitle, orgPersonId, orgDeptId, orgJobTitle
        case orgGradeTitleId, createdOrgPerson, cardId, cardDept, cardJobTitle
        case orgInactive, orgLeftDate
    }
}

// MARK: - [v25.591 轉組織 v1a-2] 班、會議、議程的原樣（復原用）

/// 一格班的原樣（shifts 那一列的 removedShifts）：搬走的、清掉的、接手的人被蓋掉的那一格（judge §2.1、§3.2 班、§8 風險 18）
struct OrgMoveShiftCell: Codable, Equatable {
    /// 原本是誰的班
    var who: UUID
    /// 「2026-11-04」
    var day: String
    /// ShiftType 的字（「大夜班」「日值班」…）
    var type: String
    /// 原本那一格的 id（搬過去的同一格 id 不變）
    var id: UUID?
    /// 搬給誰（nil＝清掉了／被蓋掉了）
    var to: UUID?
    /// 這格是接手的人被蓋掉的那一格（復原時放回 who 身上）
    var overwritten: Bool?

    init(who: UUID, day: String, type: String, id: UUID? = nil, to: UUID? = nil, overwritten: Bool? = nil) {
        self.who = who
        self.day = day
        self.type = type
        self.id = id
        self.to = to
        self.overwritten = overwritten
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        who = try c.decode(UUID.self, forKey: .who)
        day = (try? c.decodeIfPresent(String.self, forKey: .day)) ?? ""
        type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? ""
        id = try? c.decodeIfPresent(UUID.self, forKey: .id)
        to = try? c.decodeIfPresent(UUID.self, forKey: .to)
        overwritten = try? c.decodeIfPresent(Bool.self, forKey: .overwritten)
    }

    private enum CodingKeys: String, CodingKey {
        case who, day, type, id, to, overwritten
    }
}

/// 會議那一列套用前後的樣子（存在 OrgMoveLine.removedJSON；會議、場次、議程沒有 Equatable，所以存 JSON）。
/// 〔最後一場〕：結束前的結束日、取消的覆寫場次（原樣）、搬到最後一場的議程原本在哪一場；
/// 〔交給…〕：結束前的結束日、搬到新系列的覆寫場次 id；只有一場的會議整場交出去：原本的名稱
struct OrgMoveMeetingUndo: Codable {
    /// 套用前的 rule.endDate（nil＝原本沒有結束日）
    var prevEndDate: Date?
    /// 套用時寫上的結束日（復原時現在還是這一天才改回）
    var setEndDate: Date?
    /// 取消的覆寫場次（原樣；有議程的那幾場議程先搬到最後一場）
    var removedOccurrences: [MeetingOccurrence]
    /// 搬到最後一場的議程 id（復原時從最後一場拿回原本那一場）
    var movedItemIds: [UUID]
    /// 最後一場的 scheduledDate（議程搬進去的那一場）
    var lastScheduled: Date?
    /// 最後一場的覆寫是套用時才建的（復原後空了就拿掉）
    var createdLast: Bool?
    /// 〔交給…〕：搬到新系列的覆寫場次 id
    var movedOccurrenceIds: [UUID]
    /// 名稱改過的：原本的名稱
    var oldTopic: String?

    init(prevEndDate: Date? = nil, setEndDate: Date? = nil, removedOccurrences: [MeetingOccurrence] = [],
         movedItemIds: [UUID] = [], lastScheduled: Date? = nil, createdLast: Bool? = nil,
         movedOccurrenceIds: [UUID] = [], oldTopic: String? = nil) {
        self.prevEndDate = prevEndDate
        self.setEndDate = setEndDate
        self.removedOccurrences = removedOccurrences
        self.movedItemIds = movedItemIds
        self.lastScheduled = lastScheduled
        self.createdLast = createdLast
        self.movedOccurrenceIds = movedOccurrenceIds
        self.oldTopic = oldTopic
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        prevEndDate = try? c.decodeIfPresent(Date.self, forKey: .prevEndDate)
        setEndDate = try? c.decodeIfPresent(Date.self, forKey: .setEndDate)
        removedOccurrences = (try? c.decodeIfPresent([MeetingOccurrence].self, forKey: .removedOccurrences)) ?? []
        movedItemIds = (try? c.decodeIfPresent([UUID].self, forKey: .movedItemIds)) ?? []
        lastScheduled = try? c.decodeIfPresent(Date.self, forKey: .lastScheduled)
        createdLast = try? c.decodeIfPresent(Bool.self, forKey: .createdLast)
        movedOccurrenceIds = (try? c.decodeIfPresent([UUID].self, forKey: .movedOccurrenceIds)) ?? []
        oldTopic = try? c.decodeIfPresent(String.self, forKey: .oldTopic)
    }

    private enum CodingKeys: String, CodingKey {
        case prevEndDate, setEndDate, removedOccurrences, movedItemIds, lastScheduled, createdLast
        case movedOccurrenceIds, oldTopic
    }

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func decode(_ data: Data?) -> OrgMoveMeetingUndo? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(OrgMoveMeetingUndo.self, from: data)
    }
}

/// 〔不要了〕的議程原樣（存在 OrgMoveLine.removedJSON）：放回原本那場會議的那一場
struct OrgMoveRemovedAgenda: Codable {
    var item: MeetingItem
    var meetingId: UUID
    /// 原本在哪一場（nil＝不重複的會議，議程掛在會議本身）
    var occurrenceId: UUID?
    /// 那一場的 scheduledDate（那一場的覆寫後來被回收了，就照這個日子再建一場）
    var scheduledDate: Date?

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func decode(_ data: Data?) -> OrgMoveRemovedAgenda? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(OrgMoveRemovedAgenda.self, from: data)
    }
}

// MARK: - 只在記憶體的列舉（存檔一律存字串）

enum OrgMoveKind: String {
    /// 換單位（還是我帶的）
    case move
    /// 只換廠區
    case plant
    /// [v25.593 轉組織 v2] 調出我的管轄／離職／退休（生效後收進部屬名單最下面「已轉出」；judge §3.6、第 7 題）
    case out, resign, retire
    /// [v25.593 轉組織 v2] 回到我的部屬（已轉出的人按〔回到我的部屬〕記的一張：什麼都不搬、只讓這位同仁回到在職名單）
    case back

    /// 調出、離職、退休
    var isLeaving: Bool { self == .out || self == .resign || self == .retire }
    /// 離職、退休（組織人員同時設成「已離職」；第 ① 步沒有新部門、廠區、職稱）
    var isLeaveCompany: Bool { self == .resign || self == .retire }
    /// 這一種會改部門（換單位、調出；〔照舊（只交接）〕另外看 keepDept）
    var canChangeDept: Bool { self == .move || self == .out }
    /// 精靈「這次是」那一排膠囊的字；歷程、單頭也用（「調出我的管轄」「離職」「退休」）
    var label: String {
        switch self {
        case .move: return "換單位"
        case .plant: return "只換廠區"
        case .out: return "調出我的管轄"
        case .resign: return "離職"
        case .retire: return "退休"
        case .back: return "回到我的部屬"
        }
    }
    /// 精靈「這次是」那一排（照這個順序；回到我的部屬不在這裡）
    static let wizardCases: [OrgMoveKind] = [.move, .plant, .out, .resign, .retire]
}

enum OrgMoveState: String {
    case applied, closed, undone
    /// [v25.592 轉組織 v1b] 排好了（什麼都還沒做）／事情交了、部門還沒改／排好的取消了（同時寫 deletedAt）
    case planned, handed, cancelled
}

/// [v25.592 轉組織 v1b] 什麼時候做（存字串在 OrgMove.timing）
enum OrgMoveTiming: String {
    /// 確認那一刻全部做（生效日今天或以前）
    case now
    /// 〔現在就交接，11/1 才改部門〕（v1b 預設，judge 第 6 題）
    case handoverNow
    /// 〔11/1 一起做〕：生效那天交接、改部門一起做
    case together
}

/// [v25.592 轉組織 v1b] applyOrgMove 這一次做哪一段（只在記憶體）
enum OrgMovePhase {
    /// 交接＋組織（v1a、生效日今天或以前、〔11/1 一起做〕到期）
    case all
    /// 只交接（〔現在就交接〕確認那一刻）
    case handover
    /// 只改組織那幾格（〔現在就交接〕到期那天）
    case org
}

/// [v25.592 轉組織 v1b] 到期套用的一張（「今天生效」那張、卡片〔現在套用〕之後跳的那張；字在 OrgMovePlan.dueResult 組好）
struct OrgMoveDueResult: Identifiable, Equatable {
    let moveId: UUID
    let personId: UUID
    /// 這次改好了（false＝卡住了：blockKind／detail 寫為什麼）
    let applied: Bool
    /// 「王小明 製造一課 → 設備課（P1 → P2）」
    let title: String
    /// 「✓ 已換好・交接完成日 11/11（三）」／「王小明現在已經在品保課了，這張單還要做嗎？」
    let detail: String
    /// nil＝沒卡住；"deptMoved"／"deptGone"／"personGone"（OrgMoveDueBlock）
    let blockKind: String?
    /// 「今天生效」上要不要有〔更新生日提醒〕（部屬或組織人員有生日提醒、部門或職稱有換、你確認時勾了）
    let birthdayOffer: Bool
    /// 自動套用沒動的 Apple 提醒事項件數（〔11/1 一起做〕到期自動做時才有；〔更新提醒事項〕）
    let reminderCount: Int
    var id: UUID { moveId }
}

/// [v25.592 轉組織 v1b] 到期那天為什麼不能自動改（照現在的資料算，不存）
enum OrgMoveDueBlock: String {
    /// 生效前你又把這位同仁的部門改了（現在不是單上的「從」）：〔只做交接〕〔取消這張單〕
    case deptMoved
    /// 新部門在生效前被刪了：〔選部門〕〔只做交接〕
    case deptGone
    /// 這位同仁被刪了：只能〔取消這張單〕
    case personGone
}

enum OrgMoveLineKind: String {
    case task, alarmTask, equipment, report, sideRole, manager, managerAdd
    /// [v25.591 轉組織 v1a-2] 固定會議／議程／生效日（與今天取晚的那天）以後的班
    case meeting, agenda, shifts
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
    /// [v25.591 轉組織 v1a-2] 會議：到交接那天前一天結束（〔10/27 是最後一場〕）／舊的結束、新的在 toId 名下接著開（〔交給…〕）
    case end, newSeries
    /// [v25.593 轉組織 v2] 交出去（給不在部屬名單的人＝組織人員 id，或給「我」＝OrgMovePlan.meId）：從原人拿掉、原樣存進交接單、
    /// 提醒事項刪掉；不算完成、不算任何人的分（交接那一刻已逾期的扣分照留原人）。只有待辦、週報、自己加的一項有（judge §3.6）
    case handOut
}

enum OrgMoveLineState: String {
    case done, skipped, resolved, undone
}

enum OrgMoveLock: String {
    /// 缺失：只能〔跟著〕〔現在結案〕
    case dereliction
    /// 兼任：v1a-1 只能〔照舊〕＋〔前往〕兼任那頁換（v1a-2 起新的單不再鎖：〔照舊〕〔到兼任換人…〕；舊單照樣認得）
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
        /// [v25.591 轉組織 v1a-2] 哪一種（OrgMoveLineKind 的字：task／report／equipment／meeting／agenda／sideRole／shifts…）
        var lineKind: String = ""
    }

    /// 任務／週報／機台 id → 最新一張交出它的那一列（接力：王小明 → 陳怡君 → 林志豪，用最新那張）
    static var receivedByItem: [UUID: Received] = [:]
    /// 原人 id → 待分派、還沒分好的機台 id → 交接那一刻（這幾台的警報任務在交接之後到期的，逾期不算原人）
    static var pendingEquipment: [UUID: [UUID: Date]] = [:]
    /// 〔不要了〕的任務、週報 id（合併匯入舊備份時不補回來）
    static var droppedItemIds: Set<UUID> = []
    /// [v25.591 轉組織 v1a-2] 接手的人 id →「2026-11-04」→ 那一天的班是從哪一張單交過來的（接手那一區、匯出的排班）
    static var receivedShiftDays: [UUID: [String: Received]] = [:]
    /// [v25.591 轉組織 v1a-2] 原人 id → 交出去、清掉的班那幾天（合併匯入舊備份時不把這幾天的班補回原人身上，judge §2.4）
    static var handedShiftDays: [UUID: Set<String>] = [:]
    /// [v25.592 轉組織 v1b] 排好、部門還沒改的那一張（一人一張；judge §2.6 plannedByPerson、§3.5、§5-21）
    struct Planned: Equatable {
        let moveId: UUID
        /// 「2026-11-01」
        let effectiveKey: String
        /// "planned"／"handed"
        let state: String
        /// "move"／"plant"
        let kind: String
        let keepDept: Bool
        let fromDeptId: UUID?
        let toDeptId: UUID?
        /// 單上的快照字「EQ — 設備課」
        let toDeptLabel: String
        let fromPlant: String
        let toPlant: String
    }
    /// [v25.592 轉組織 v1b] 部屬 id → 排好、部門還沒改的那一張（部屬名單「11/1 起 設備課」、組織圖「11/1 調設備課」、
    /// 挑人頁「11/9 也要調走」、精靈「已經排了」查這張；同一位有兩張時取後建的）
    static var plannedByPerson: [UUID: Planned] = [:]
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
        var shiftDays: [UUID: [String: Received]] = [:]
        var handedDays: [UUID: Set<String>] = [:]
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
                // [v25.591 轉組織 v1a-2] 〔不要了〕只記任務、週報、議程（班〔這幾天清掉〕沒有 refId，記在 handedShiftDays）
                // [v25.593 轉組織 v2]〔交出去〕的也記（一樣從原人拿掉了：合併匯入舊備份不讓它長回來）。要退回這一件：拿掉 `|| …handOut…`
                if l.action == OrgMoveAction.drop.rawValue || l.action == OrgMoveAction.handOut.rawValue, let r = l.refId,
                   l.kind != OrgMoveLineKind.shifts.rawValue { dropped.insert(r) }
                if l.action == OrgMoveAction.pending.rawValue, l.state == OrgMoveLineState.done.rawValue,
                   l.kind == OrgMoveLineKind.equipment.rawValue, let r = l.refId {
                    pending[m.personId, default: [:]][r] = handed
                }
                // [v25.591 轉組織 v1a-2] 班：交出去、清掉的那幾天（原人）；搬到誰身上的那幾天（接手的人）
                if l.kind == OrgMoveLineKind.shifts.rawValue, l.state == OrgMoveLineState.done.rawValue {
                    for c in l.removedShifts ?? [] where c.overwritten != true && c.who == m.personId {
                        handedDays[m.personId, default: []].insert(c.day)
                        guard let to = c.to else { continue }
                        let r = Received(moveId: m.id, lineId: l.id, fromId: m.personId, fromName: m.personName,
                                         toId: to, handedAt: handed, dueKey: c.day, wasOverdue: false,
                                         memo: (l.memo ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                                         handoverByKey: byKey, closed: m.isClosed, hasPending: hasPending,
                                         pendingEquipmentIds: pendingEq, lineKind: l.kind)
                        shiftDays[to, default: [:]][c.day] = r
                    }
                    continue
                }
                // 會議〔交給…〕：新會議的 id（舊的那場還在原人身上、只是結束了）
                let isSeries = l.kind == OrgMoveLineKind.meeting.rawValue && l.action == OrgMoveAction.newSeries.rawValue
                let key: UUID? = isSeries ? l.newId : l.refId
                guard let ref = key, let to = l.toId,
                      l.state == OrgMoveLineState.done.rawValue || l.state == OrgMoveLineState.resolved.rawValue,
                      l.kind != OrgMoveLineKind.manager.rawValue, l.kind != OrgMoveLineKind.managerAdd.rawValue
                else { continue }
                let given = l.action == OrgMoveAction.give.rawValue
                    || l.action == OrgMoveAction.withEquipment.rawValue
                    || isSeries
                    || (l.action == OrgMoveAction.pending.rawValue && l.state == OrgMoveLineState.resolved.rawValue)
                guard given else { continue }
                let at = l.state == OrgMoveLineState.resolved.rawValue ? (l.resolvedAt ?? handed) : handed
                let r = Received(moveId: m.id, lineId: l.id, fromId: m.personId, fromName: m.personName,
                                 toId: to, handedAt: at, dueKey: l.dueKey, wasOverdue: l.wasOverdue == true,
                                 memo: (l.memo ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                                 handoverByKey: byKey, closed: m.isClosed, hasPending: hasPending,
                                 pendingEquipmentIds: pendingEq, lineKind: l.kind)
                if let old = received[ref], old.handedAt > at { continue }
                received[ref] = r
            }
        }
        receivedByItem = received
        pendingEquipment = pending
        droppedItemIds = dropped
        receivedShiftDays = shiftDays
        handedShiftDays = handedDays
        plannedByPerson = plannedIndex(book)
        // [v25.593 轉組織 v2] 已轉出、那天在哪個部門（只看組織那幾格做完了的單）。要退回這一件：刪這三行
        let roster = rosterIndex(book)
        archived = roster.archived
        spans = roster.spans
    }

    // MARK: [v25.593 轉組織 v2] 已轉出、那天在哪個部門（judge §2.2、§3.6、§5-32；orgmove/build/v2/brief.md §2-1）

    /// 已轉出的那一位：最後一張「調出／離職／退休／回到我的部屬」是調出、離職、退休
    struct Archived: Equatable {
        let moveId: UUID
        /// "out"／"resign"／"retire"
        let kind: String
        /// 「2026-11-01」
        let effectiveKey: String
        /// 調出到哪個部門（離職、退休、部門照舊＝nil）
        let toDeptId: UUID?
        /// 單上的快照字「QA — 品保課」（部門之後改名、刪了也看得懂）
        let toDeptLabel: String
    }
    /// 部屬 id → 已轉出的那一張（沒有＝在職）
    static var archived: [UUID: Archived] = [:]

    /// 某一段日子這位同仁在哪：untilKey 以前（不含）、上一段以後是 deptId／plant（archived＝那一段已經轉出了）
    struct Span: Equatable {
        /// 「2026-11-01」（不含這一天）
        let untilKey: String
        let deptId: UUID?
        let plant: String
        let archived: Bool
    }
    /// 部屬 id → 照 untilKey 排好的幾段（最後一段以後＝現在的部門、廠區；沒有＝一直是現在的）
    static var spans: [UUID: [Span]] = [:]

    static func isArchived(_ id: UUID?) -> Bool {
        guard let id else { return false }
        return archived[id] != nil
    }

    /// 在職的（小工具、會議通知、今天時間軸、挑人清單…都讀這一份；judge §3.6）
    static func activeOnly(_ subs: [Subordinate]) -> [Subordinate] {
        guard !archived.isEmpty else { return subs }
        return subs.filter { archived[$0.id] == nil }
    }

    /// 那一天這位同仁在哪（「2026-10-15」）：nil＝跟現在一樣（看部屬身上的 departmentId、plantArea、是不是已轉出）
    static func placement(_ personId: UUID, dayKey: String) -> Span? {
        guard let list = spans[personId] else { return nil }
        return list.first { dayKey < $0.untilKey }
    }

    /// 組織那幾格做完了的單，照生效日（同一天照套用的時間）排：最後一張調出／離職／退休／回到我的部屬決定在不在職；
    /// 每一張有改部門、廠區、或調出、回來的，切一段「這天以前在哪」
    private static func rosterIndex(_ book: OrgMoveBook) -> (archived: [UUID: Archived], spans: [UUID: [Span]]) {
        var byPerson: [UUID: [OrgMove]] = [:]
        for m in book.live where m.orgDone {
            byPerson[m.personId, default: []].append(m)
        }
        var arch: [UUID: Archived] = [:]
        var out: [UUID: [Span]] = [:]
        for (pid, list) in byPerson {
            let sorted = list.sorted { a, b in
                if a.effectiveKey != b.effectiveKey { return a.effectiveKey < b.effectiveKey }
                let ta: Date = a.appliedAt ?? a.handedAt ?? a.createdAt ?? Date.distantPast
                let tb: Date = b.appliedAt ?? b.handedAt ?? b.createdAt ?? Date.distantPast
                return ta < tb
            }
            var wasArchived = false
            var last: OrgMove?
            var spansOut: [Span] = []
            for m in sorted {
                // [v25.593 驗證] 回到我的部屬那張只在「那時已轉出」才算：先〔回到我的部屬〕、再〔復原〕原本那張調出的，
                // 那張 back 不能切出「11/5 以前在品保課」那一段（不然回看 10 月製造一課的班表王小明跑到品保課）。
                // 要退回這一件：改回 `m.isLeaving || m.isBack`
                let roster: Bool = m.isLeaving || (m.isBack && wasArchived)
                // [v25.593 裁定] 拆成兩行、標型別（同一個條件；少讓型別檢查猜 `??` 與 Optional 比較）
                let deptMoved: Bool = m.from.deptId != m.to.deptId && m.keepDept != true && m.kindValue?.canChangeDept == true
                let plantMoved: Bool = (m.from.plant ?? "") != (m.to.plant ?? "")
                let moved: Bool = deptMoved || plantMoved
                guard roster || moved else { continue }
                spansOut.append(Span(untilKey: m.effectiveKey, deptId: m.from.deptId, plant: m.from.plant ?? "",
                                     archived: wasArchived))
                if m.isLeaving { wasArchived = true }
                if m.isBack { wasArchived = false }
                if roster { last = m }
            }
            if !spansOut.isEmpty { out[pid] = spansOut }
            if let m = last, m.isLeaving {
                let dept: UUID? = m.changesDept ? m.to.deptId : nil
                arch[pid] = Archived(moveId: m.id, kind: m.kind, effectiveKey: m.effectiveKey, toDeptId: dept,
                                     toDeptLabel: dept == nil ? "" : (m.to.deptLabel ?? ""))
            }
        }
        return (arch, out)
    }

    /// [v25.592 轉組織 v1b] 排好、部門還沒改的（planned／handed、沒刪）：一人取後建的那一張
    private static func plannedIndex(_ book: OrgMoveBook) -> [UUID: Planned] {
        var out: [UUID: Planned] = [:]
        var at: [UUID: Date] = [:]
        for m in book.live where m.orgPending {
            let made: Date = m.createdAt ?? m.updatedAt ?? Date.distantPast
            if let old = at[m.personId], old > made { continue }
            at[m.personId] = made
            out[m.personId] = Planned(moveId: m.id, effectiveKey: m.effectiveKey, state: m.state, kind: m.kind,
                                      keepDept: m.keepDept == true, fromDeptId: m.from.deptId, toDeptId: m.to.deptId,
                                      toDeptLabel: m.to.deptLabel ?? "", fromPlant: m.from.plant ?? "",
                                      toPlant: m.to.plant ?? "")
        }
        return out
    }

    /// 還在顯示期間的「交接自」（膠囊、提示列）：沒按〔交接完成〕、而且還沒過交接完成日或還有待分派。
    /// todayKey：手機當地的今天「2026-11-02」
    /// [v25.590 轉組織 v1a-1 驗證]「還有待分派」照機台現在的負責人算（同 OrgMovePlan.isOpen、pendingRows）
    static func receivedChip(_ itemId: UUID, holderId: UUID, todayKey: String) -> Received? {
        guard let r = receivedByItem[itemId], r.toId == holderId, !r.closed else { return nil }
        return stillShowing(r, todayKey: todayKey) ? r : nil
    }

    /// [v25.591 轉組織 v1a-2] 任務列的「交接自」：先照任務 id 找；兼任的分身換人後是新的 id，再照 sideRoleLink.taskId（兼任待辦 id）找
    ///（judge §4.6：兼任那種用接手的人那筆的 sideRoleLink.taskId 對）
    static func receivedChip(task t: SubordinateTask, holderId: UUID, todayKey: String) -> Received? {
        if let r = receivedChip(t.id, holderId: holderId, todayKey: todayKey) { return r }
        guard let back = t.sideRoleLink else { return nil }
        return receivedChip(back.taskId, holderId: holderId, todayKey: todayKey)
    }

    /// [v25.591 轉組織 v1a-2] 這位同仁那一天的班是交接過來的（還在顯示期間）
    static func receivedShift(holderId: UUID, dayKey: String, todayKey: String) -> Received? {
        guard let r = receivedShiftDays[holderId]?[dayKey], !r.closed else { return nil }
        return stillShowing(r, todayKey: todayKey) ? r : nil
    }

    /// 還在交接完成日以前、或這張單還有沒分好的待分派
    private static func stillShowing(_ r: Received, todayKey: String) -> Bool {
        let pending = r.hasPending && stillPending(r.pendingEquipmentIds, personId: r.fromId)
        return todayKey <= r.handoverByKey || pending
    }
}
