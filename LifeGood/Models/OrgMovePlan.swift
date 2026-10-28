import Foundation

// MARK: - [v25.590 轉組織 v1a-1] 交接單的規則（純函式）
//（orgmove/judge.md §3.2、§3.9「純函式先算清單」、§4.2～§4.10、§11.6；orgmove/build/v1a-1/brief.md §2-2）
//
// 畫面、套用、sim 吃同一支：清單、預設、「為什麼這樣排」、膠囊上的字、頂端件數、〔全部交給〕、預覽句子、
// 交接單每一列的狀態（照現在的資料算）、四格、提示列、歷程、接手那一區、待分派卡、分享文字、復原的確認字都在這裡組好，
// 畫面只排版（body 裡不寫長運算式、不自己再篩一次資料）。sim_v1a-1.py 一個函式一個函式對照。
// 字的規矩：不用「他／她」，寫名字或「這位同仁」；不寫分數、考評、請假原因到任何通知、小工具（這裡的字只在 App 內頁與分享文字）。

/// 算交接要用的那幾包資料（主執行緒從 LifeStore 抽一份值型別；畫面、套用都吃它）
struct OrgMoveWorld {
    var subordinates: [Subordinate]
    var equipment: [ManagedEquipment]
    var departments: [Department]
    var orgPeople: [OrgPerson]
    var businessCards: [BusinessCard]
    var gradeTitles: [GradeTitle]
    var sideRoles: [LifeMilestone]
    var ballots: [PerformanceBallot]
    /// Apple 提醒事項同步開著、有權限（「Apple 提醒事項 N 件改成接手的人」那一行要不要出現）
    var remindersOn: Bool
    /// [v25.593 轉組織 v2] 你履歷上現在的管理單位（LifeStore.myCurrentManagedUnit；「調過去之後還是你的部屬嗎？」那一題用）
    var myManagedUnit: String?

    init(subordinates: [Subordinate], equipment: [ManagedEquipment], departments: [Department],
         orgPeople: [OrgPerson], businessCards: [BusinessCard] = [], gradeTitles: [GradeTitle] = [],
         sideRoles: [LifeMilestone] = [], ballots: [PerformanceBallot] = [], remindersOn: Bool = false,
         myManagedUnit: String? = nil) {
        self.subordinates = subordinates
        self.equipment = equipment
        self.departments = departments
        self.orgPeople = orgPeople
        self.businessCards = businessCards
        self.gradeTitles = gradeTitles
        self.sideRoles = sideRoles
        self.ballots = ballots
        self.remindersOn = remindersOn
        self.myManagedUnit = myManagedUnit
    }

    init(store: LifeStore) {
        self.init(subordinates: store.subordinates, equipment: store.equipmentPool,
                  departments: store.departments, orgPeople: store.orgPeople,
                  businessCards: store.businessCards, gradeTitles: store.gradeTitles,
                  sideRoles: store.sideRoles, ballots: store.performanceBallots,
                  remindersOn: ReminderBridge.enabledAndAuthorized,
                  myManagedUnit: store.myCurrentManagedUnit)
    }

    /// [v25.593 轉組織 v2] 在職的部屬（已轉出的不算；挑人清單、建議人、「這個部門是不是你帶的」用）。
    /// subordinates 照舊是全部（交接單、歷史、名字快照查得到已轉出的人）
    var activeSubordinates: [Subordinate] { OrgMoveIndex.activeOnly(subordinates) }

    func sub(_ id: UUID?) -> Subordinate? {
        guard let id else { return nil }
        return subordinates.first { $0.id == id }
    }

    /// 寫給使用者看的名字（沒名字＝「這位同仁」）
    func name(_ id: UUID?) -> String {
        let n = sub(id)?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return n.isEmpty ? "這位同仁" : n
    }

    func dept(_ id: UUID?) -> Department? {
        guard let id else { return nil }
        return departments.first { $0.id == id }
    }

    /// 句子裡的部門名（「製造一課」；沒名稱＝代碼）
    func deptShort(_ id: UUID?) -> String {
        guard let d = dept(id) else { return "" }
        let n = d.name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? d.code.trimmingCharacters(in: .whitespaces) : n
    }

    /// 部門清單、交接單快照的字（「EQ — 設備課」，同 LifeStore.departmentLabel）
    func deptLabel(_ id: UUID?) -> String {
        guard let d = dept(id) else { return "" }
        return LifeStore.departmentLabel(d)
    }

    func orgPerson(linkedTo subId: UUID) -> OrgPerson? {
        orgPeople.first { $0.linkedSubordinateId == subId }
    }

    func orgPersonName(_ id: UUID?) -> String {
        guard let id, let p = orgPeople.first(where: { $0.id == id }) else { return "" }
        return p.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func equipmentItem(_ id: UUID?) -> ManagedEquipment? {
        guard let id else { return nil }
        return equipment.first { $0.id == id }
    }

    func equipmentName(_ id: UUID?) -> String {
        guard let e = equipmentItem(id) else { return "已刪除的機台" }
        let n = e.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "未命名設備" : n
    }

    /// 「E3 — 工程師」（同部屬編輯頁）；沒職等＝部屬自己的職稱字
    func titleLabel(gradeTitleId: UUID?, jobTitle: String) -> String {
        if let gid = gradeTitleId, let gt = gradeTitles.first(where: { $0.id == gid }) {
            return "\(gt.grade) — \(gt.title)"
        }
        return jobTitle.trimmingCharacters(in: .whitespaces)
    }

    func sideRoleName(_ roleId: UUID?) -> String {
        let t = sideRoles.first(where: { $0.id == roleId })?.sideRoleName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? "兼任職務" : t
    }

    /// 兼任連結還接得上（兼任、那則待辦都還在）
    func sideRoleAlive(_ back: SideRoleBackLink) -> Bool {
        sideRoles.first(where: { $0.id == back.roleId })?
            .sideRoleTasks?.contains(where: { $0.id == back.taskId }) == true
    }
}

/// 精靈的草稿（第 ① 步填的＋第 ② 步的清單）。不存檔：按〔確認交接〕才變成一張 OrgMove
struct OrgMoveDraft {
    var personId: UUID
    var kind: OrgMoveKind = .move
    /// 生效日（v1a 只能今天或以前；預設今天）
    var effective: Date
    /// 新部門〔照舊（只交接）〕
    var keepDept: Bool = false
    var toDeptId: UUID?
    /// 新主管（組織人員 id；nil＝空白；只記在單上）
    var toManagerId: UUID?
    /// nil＝職稱照舊
    var toGradeTitleId: UUID?
    /// 新廠區（「P2」）
    var toPlant: String = ""
    /// 要加進新部門的管理人員
    var addToNewDeptManagers: Bool = false
    /// 你自己打的備註（只有你看得到）
    var note: String = ""
    /// 交接清單（含第 ① 步的管理人員那幾列）
    var lines: [OrgMoveLine] = []
    /// 順便更新生日提醒（標題有部門）
    var retitleBirthday: Bool = true
    /// [v25.592 轉組織 v1b] 生效日在以後時什麼時候做（預設〔現在就交接，11/1 才改部門〕，judge 第 6 題）；生效日今天或以前不看這個
    var timing: OrgMoveTiming = .handoverNow

    init(personId: UUID, effective: Date) {
        self.personId = personId
        self.effective = effective
    }
}

/// 一列能選的一顆
struct OrgMoveChoice: Identifiable, Equatable {
    let action: OrgMoveAction
    let label: String
    /// 選了要再挑人（交給…、換成…）
    let needsPerson: Bool
    /// [v25.591 轉組織 v1a-2] 已經帶好人的那一顆（〔改由 林志豪（會議主人）〕〔交給 陳怡君（新會議接著開）〕）：選了直接寫這位
    var toId: UUID? = nil
    var toName: String? = nil
    var id: String { action.rawValue + (toId?.uuidString ?? "") }
}

/// 頂端四個數（還沒決定・交給別人・跟著・待分派）＋不要了、每位接手的人幾項
struct OrgMoveTally: Equatable {
    var undecided = 0
    var given = 0
    var follow = 0
    var pending = 0
    var dropped = 0
    /// [v25.591 轉組織 v1a-2] 會議〔最後一場〕
    var ended = 0
    /// [v25.593 轉組織 v2]〔交出去〕（給不在部屬名單的人、給「我」）
    var handedOut = 0
    /// 接手的人 id → 幾項（照清單順序第一次出現排）
    var byReceiver: [(id: UUID, name: String, count: Int)] = []

    static func == (a: OrgMoveTally, b: OrgMoveTally) -> Bool {
        guard a.undecided == b.undecided, a.given == b.given, a.follow == b.follow,
              a.pending == b.pending, a.dropped == b.dropped, a.ended == b.ended, a.handedOut == b.handedOut,
              a.byReceiver.count == b.byReceiver.count else { return false }
        for i in a.byReceiver.indices {
            if a.byReceiver[i].id != b.byReceiver[i].id || a.byReceiver[i].count != b.byReceiver[i].count { return false }
        }
        return true
    }
}

/// 第 ② 步的一組（待辦／機台／週報題目／組織）
struct OrgMoveGroup: Identifiable {
    /// "tasks"／"equipment"／"meetings"／"reports"／"shifts"／"org"
    let id: String
    let title: String
    let lineIds: [UUID]
    /// 〔這組交給 ▾〕要不要出現（組織那組沒有）
    let canGiveAll: Bool
}

/// 第 ③ 步的一段
struct OrgMovePreviewBlock: Identifiable {
    let id: String
    let title: String
    let lines: [String]
}

/// 第 ③ 步（句子都組好，畫面只排版）
struct OrgMovePreview {
    var header = ""
    var dates = ""
    var blocks: [OrgMovePreviewBlock] = []
    var overdueWarning: String?
    var changes: [String] = []
    /// 有生日提醒可以改（☑ 順便更新生日提醒那一顆要不要出現）
    var birthdayOffer = false
    var untouched: [String] = []
    var deferred: String?
    var timingNote = "按下去就全部改好"
    /// [v25.592 轉組織 v1b] 「什麼時候做」那一區的兩顆（生效日在以後才有；生效日今天或以前＝空的，畫面不出現那一區）
    var timingOptions: [OrgMoveTimingOption] = []
    /// [v25.592 轉組織 v1b] ☑ 順便更新生日提醒 下面那行小字（生效日在以後：「11/1 在「今天生效」那張上按一下才改」）
    var birthdayNote: String?
    /// [v25.592 轉組織 v1b] 橘字提醒（「陳怡君 11/1 前就調走了，確定交給這位？」judge §5-1）
    var warnings: [String] = []
}

/// [v25.592 轉組織 v1b] 第 ③ 步「什麼時候做」的一顆
struct OrgMoveTimingOption: Identifiable, Equatable {
    let timing: OrgMoveTiming
    /// 「現在就交接，11/1 才改部門」「11/1 一起做」
    let label: String
    /// 選了之後下面那一行
    let note: String
    var id: String { timing.rawValue }
}

/// 交接單頁一列的狀態（照現在的資料算）
struct OrgMoveLineStatus: Equatable {
    enum Kind: String {
        case done, open, handed, backOnPerson, onBoth, elsewhere, skipped, missing
        case pending, pendingElsewhere, follow, closed, dropped, undone, org
        /// [v25.591 轉組織 v1a-2] 會議〔最後一場〕做好了
        case ended
        /// [v25.592 轉組織 v1b] 排好了、還沒做（〔11/1 一起做〕生效前）／你自己加的一項
        case planned, custom
        /// [v25.593 轉組織 v2] 交出去給不在部屬名單的人（→）／交出去給「我」（我接的：○ 還沒收掉、✓ 收掉了）
        case handedOut, mine
    }
    /// 這一列能按的那一顆
    enum Fix: String {
        /// ⚠ 又回到原人身上〔再交一次〕
        case redo
        /// ⚠ 同時在兩個人身上〔留陳怡君那份〕
        case keepReceiver
        /// 待分派〔分給…〕
        case resolve
        /// 不要了〔放回王小明〕（＝這一列〔拿回來〕）
        case putBack
    }
    var kind: Kind
    /// ✓ ○ ● ⚠ ・
    var mark: String
    var text: String
    /// 現在在誰身上（點一列打開那一筆用）
    var holderId: UUID?
    var fix: Fix?
    var fixLabel: String?
}

/// 四格（交出去／做完／待分派／跟著）
struct OrgMoveTile: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
    let sub: String
}

/// 看板下面那一條提示列
struct OrgMoveHint: Identifiable, Equatable {
    let moveId: UUID
    let text: String
    /// 橘點「待分派 1」
    let badge: String?
    /// 橘字（又回到原人身上、部門又被改回去、在兩個人身上）
    let warning: String?
    let isReceiver: Bool
    /// [v25.592 轉組織 v1b] 灰字一行（「排好之後多了 2 件（先跟著王小明）」）
    var note: String? = nil
    /// [v25.592 轉組織 v1b] 這一條上的按鈕（〔現在套用〕〔加進交接單〕〔只做交接〕〔選部門〕〔取消這張單〕）
    var actions: [OrgMoveHintAction] = []
    /// [v25.592 轉組織 v1b] 灰色那一種（接手的人「11/1 起會從王小明接手 6 項」：什麼都還沒交過來）
    var muted: Bool = false
    var id: String { moveId.uuidString + (isReceiver ? "-r" : "-p") }
}

/// [v25.592 轉組織 v1b] 提示列、「今天生效」卡上的按鈕（訂閱：〔現在套用〕〔只做交接〕〔取消這張單〕不用；〔加進交接單〕〔選部門〕要，judge §6）
enum OrgMoveHintAction: String, Identifiable, Equatable {
    case applyNow, addLate, skipOrg, pickDept, cancel
    var id: String { rawValue }
    var label: String {
        switch self {
        case .applyNow: return "現在套用"
        case .addLate: return "加進交接單"
        case .skipOrg: return "只做交接"
        case .pickDept: return "選部門"
        case .cancel: return "取消這張單"
        }
    }
    /// 要訂閱的（judge §6：改排好的單要；把開始了的做完、設錯的收掉不用）
    var needsPremium: Bool { self == .addLate || self == .pickDept }
}

/// 〔潛力性〕「歷程」裡轉組織那一列
struct OrgMoveHistoryRow: Identifiable, Equatable {
    let moveId: UUID
    /// 排序用（生效日那天 00:00）
    let date: Date
    /// 「2026/11/1 轉組織」
    let title: String
    /// 「製造一課 P1 → 設備課 P2」
    let detail: String
    /// 「交出去 5・跟著 2」／「（已復原）」
    let sub: String
    let isUndone: Bool
    var id: UUID { moveId }
}

/// 接手的人〔主動性〕最上面「從王小明接手（4）・11/2」那一區的一列
struct OrgMoveReceivedRow: Identifiable, Equatable {
    let lineId: UUID
    let mark: String
    let title: String
    let detail: String
    /// 任務／週報 id（點了開預覽）；機台＝nil。兼任那種＝接手的人身上那一筆（分身換人後是新 id）
    let taskId: UUID?
    let reportId: UUID?
    /// [v25.591 轉組織 v1a-2] OrgMoveLineKind 的字（畫面挑圖示：task／report／equipment／meeting／agenda／shifts／sideRole…）
    var kind: String = ""
    /// [v25.591 轉組織 v1a-2] 會議（新會議）、議程所在的會議：點了開那場會議的預覽（持有人＝meetingHolderId）
    var meetingId: UUID? = nil
    var meetingHolderId: UUID? = nil
    var id: UUID { lineId }
}

struct OrgMoveReceivedSection: Identifiable, Equatable {
    let moveId: UUID
    /// 「從王小明接手（4）・11/2」
    let header: String
    let rows: [OrgMoveReceivedRow]
    var id: UUID { moveId }
}

/// 部屬總覽「待分派」卡的一列
struct OrgMovePendingRow: Identifiable, Equatable {
    let moveId: UUID
    let lineId: UUID
    let equipmentId: UUID
    let personId: UUID
    /// 「純化器 P-12・原本 王小明・11/2 起」
    let title: String
    let extra: [String]
    var id: UUID { lineId }
}

/// 分享的一個選項（〔給陳怡君的 4 項〕〔整張（給新主管）〕）
struct OrgMoveShareTarget: Identifiable, Equatable {
    /// nil＝整張
    let receiverId: UUID?
    let label: String
    var id: String { receiverId?.uuidString ?? "all" }
}

/// 交接單頁一組（陳怡君（4）、林志豪（1）、待分派、跟著王小明、不要了、組織）
struct OrgMoveSheetGroup: Identifiable {
    let id: String
    let title: String
    let lineIds: [UUID]
    /// 預設收起來（跟著王小明那組）
    let collapsed: Bool
}

/// 「現在在誰身上」對照表（交接單頁、接手那一區每次畫面先建一張，每列查表；judge §2.6、§7.1-11）
struct OrgMoveHolderMap {
    struct TaskCopy {
        let holder: UUID
        let task: SubordinateTask
    }
    struct ReportCopy {
        let holder: UUID
        let report: WeeklyReport
    }
    /// [v25.591 轉組織 v1a-2] 議程現在在哪一場會議、誰的會議
    struct ItemCopy {
        let holder: UUID
        let meetingId: UUID
        let topic: String
        let session: Date
        let item: MeetingItem
    }
    var tasks: [UUID: [TaskCopy]] = [:]
    var reports: [UUID: [ReportCopy]] = [:]
    /// 機台 id → 現在的負責人（沒負責人不放）
    var owners: [UUID: UUID] = [:]
    var equipmentIds: Set<UUID> = []
    var names: [UUID: String] = [:]
    // [v25.591 轉組織 v1a-2] 會議、議程、班、兼任（同一次掃，不要每列各掃一次全部部屬）
    var items: [UUID: [ItemCopy]] = [:]
    /// 會議 id → 現在在誰名下（第一位）
    var meetingHolders: [UUID: UUID] = [:]
    var meetings: [UUID: SubordinateMeeting] = [:]
    /// 部屬 id →「2026-11-04」→ 那天的班
    var shiftDays: [UUID: [String: SubordinateShift]] = [:]
    /// 兼任待辦 id → 部屬身上連著它的那幾筆任務（分身、拉進來的）
    var sideRoleCopies: [UUID: [TaskCopy]] = [:]
    /// 兼任待辦 id → 那一則
    var sideRoleTasks: [UUID: SideRoleTask] = [:]
    /// 兼任待辦 id → 負責成員連到的部屬 id
    var sideRoleAssignees: [UUID: Set<UUID>] = [:]
    /// 兼任 id → 名稱
    var sideRoleNames: [UUID: String] = [:]
    /// 組織人員、名片 id → 部屬 id（議程負責人三種 id 反查）
    var ownerOf: [UUID: UUID] = [:]

    init(world: OrgMoveWorld) {
        for s in world.subordinates {
            let n = s.name.trimmingCharacters(in: .whitespacesAndNewlines)
            names[s.id] = n.isEmpty ? "這位同仁" : n
            for t in s.tasks {
                tasks[t.id, default: []].append(TaskCopy(holder: s.id, task: t))
                if let back = t.sideRoleLink {
                    sideRoleCopies[back.taskId, default: []].append(TaskCopy(holder: s.id, task: t))
                }
            }
            for r in s.weeklyReports {
                reports[r.id, default: []].append(ReportCopy(holder: s.id, report: r))
            }
            for m in s.meetings {
                if meetingHolders[m.id] == nil {
                    meetingHolders[m.id] = s.id
                    meetings[m.id] = m
                }
                let topic = m.topic.trimmingCharacters(in: .whitespacesAndNewlines)
                for ctx in m.itemContexts {
                    items[ctx.item.id, default: []].append(ItemCopy(holder: s.id, meetingId: m.id, topic: topic,
                                                                    session: ctx.sessionDate, item: ctx.item))
                }
            }
            var days: [String: SubordinateShift] = [:]
            for sh in s.shifts { days[OrgMovePlan.dayKey(sh.date)] = sh }
            shiftDays[s.id] = days
        }
        for e in world.equipment {
            equipmentIds.insert(e.id)
            if let o = e.ownerId { owners[e.id] = o }
        }
        let subIds = Set(world.subordinates.map(\.id))
        for p in world.orgPeople {
            guard let sid = p.linkedSubordinateId, subIds.contains(sid) else { continue }
            ownerOf[p.id] = sid
            if let cid = p.linkedBusinessCardId { ownerOf[cid] = sid }
        }
        for role in world.sideRoles {
            sideRoleNames[role.id] = role.sideRoleName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var memberTo: [UUID: UUID] = [:]
            for mb in role.sideRoleMembers ?? [] {
                if let pid = mb.linkedPersonId, subIds.contains(pid) { memberTo[mb.id] = pid }
            }
            for t in role.sideRoleTasks ?? [] {
                sideRoleTasks[t.id] = t
                var who = Set<UUID>()
                for mid in t.assigneeIds ?? [] {
                    if let pid = memberTo[mid] { who.insert(pid) }
                }
                sideRoleAssignees[t.id] = who
            }
        }
    }

    /// 議程做完算誰（照 meetingItemCredits：負責人反查成部屬；沒指派＝會議主人）
    func creditedPeople(_ c: ItemCopy) -> [UUID] {
        var out: [UUID] = []
        for id in c.item.assigneeIds {
            let sid: UUID? = names[id] != nil ? id : ownerOf[id]
            if let s = sid, !out.contains(s) { out.append(s) }
        }
        return out.isEmpty ? [c.holder] : out
    }

    func name(_ id: UUID?) -> String {
        guard let id else { return "" }
        return names[id] ?? "已刪除的同仁"
    }
}

// MARK: - 規則

enum OrgMovePlan {

    // MARK: 日子（都用手機當地的日子；存字串「2026-11-01」，同定期轉帳）

    /// [v25.590 轉組織 v1a-1 驗證] 一律西曆（同定期轉帳 WealthCal）：手機設民國曆時 Calendar.current 的年是 115，
    /// 存進同步鍵的「2026-11-01」會變成「0115-11-01」，另一台設西曆的比不起來（交接完成日、復原期限、膠囊收起都算錯），
    /// 歷程也會寫成「115/11/1 轉組織」。時區照手機（autoupdatingCurrent）。
    /// 要退回這一件：改回 `static var calendar: Calendar { Calendar.current }`（ballotLines 那一行可以留著）。
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "zh_TW")
        c.timeZone = TimeZone.autoupdatingCurrent
        return c
    }()

    static func dayKey(_ d: Date) -> String {
        OrgHandoffRules.dayKey(d, calendar: calendar)
    }

    /// 「2026-11-01」→ 那天 00:00（讀不懂回 nil）
    static func date(fromKey key: String?) -> Date? {
        guard let key else { return nil }
        let parts = key.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        var c = DateComponents()
        c.year = y
        c.month = m
        c.day = d
        return calendar.date(from: c)
    }

    static func addDays(_ key: String, _ n: Int) -> String {
        guard let d = date(fromKey: key), let e = calendar.date(byAdding: .day, value: n, to: d) else { return key }
        return dayKey(e)
    }

    private static let weekdayChars = ["日", "一", "二", "三", "四", "五", "六"]

    /// 「11/1」
    static func shortDay(_ key: String?) -> String {
        guard let d = date(fromKey: key) else { return "" }
        let c = calendar.dateComponents([.month, .day], from: d)
        return "\(c.month ?? 0)/\(c.day ?? 0)"
    }

    /// 「11/1（日）」
    static func dayText(_ key: String?) -> String {
        guard let d = date(fromKey: key) else { return "" }
        let c = calendar.dateComponents([.month, .day, .weekday], from: d)
        let wd = min(max((c.weekday ?? 1) - 1, 0), 6)
        return "\(c.month ?? 0)/\(c.day ?? 0)（\(weekdayChars[wd])）"
    }

    /// 「2026/11/1」
    static func fullDay(_ key: String?) -> String {
        guard let d = date(fromKey: key) else { return "" }
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return "\(c.year ?? 0)/\(c.month ?? 0)/\(c.day ?? 0)"
    }

    /// 交接完成日＝生效日＋10 天（judge 第 10 題）
    static func handoverByKey(effectiveKey: String) -> String {
        addDays(effectiveKey, 10)
    }

    /// 已逾期的待辦交出去：新的截止日＝生效日與今天取晚的＋7 天，遇六日挪週一（judge §3.2；例 11/9（一））
    static func newDueKey(effectiveKey: String, todayKey: String) -> String {
        let base = max(effectiveKey, todayKey)
        var k = addDays(base, 7)
        if let d = date(fromKey: k) {
            let wd = calendar.component(.weekday, from: d)
            if wd == 7 { k = addDays(k, 2) } else if wd == 1 { k = addDays(k, 1) }
        }
        return k
    }

    /// 機台警報任務交出去時已經逾期：今天＋3 天（同警報自動掛任務的規矩、不挪六日；同 OrgHandoffRules.newDueForAlarm）
    static func newAlarmDueKey(todayKey: String) -> String {
        addDays(todayKey, 3)
    }

    /// 新截止日的那一天＋原本截止的那個時刻（judge §1.4-13：原本 17:00 就是 11/9 17:00）
    static func dueDate(key: String, keepingTimeOf original: Date?) -> Date? {
        guard let day = date(fromKey: key) else { return nil }
        guard let original else { return day }
        let t = calendar.dateComponents([.hour, .minute, .second], from: original)
        var c = calendar.dateComponents([.year, .month, .day], from: day)
        c.hour = t.hour
        c.minute = t.minute
        c.second = t.second
        return calendar.date(from: c) ?? day
    }

    /// 復原的期限：生效日與按確認那天取晚的＋7 天（judge §3.8；例 11/1 生效、11/2 按 → 11/9）
    /// [v25.592 轉組織 v1b]「按確認那天」＝交接那一刻（handedAt；v1a 的單 handedAt＝appliedAt 同一刻）：
    /// 〔現在就交接〕10/28 按、11/2 才改部門 → 到 11/8（judge §3.8 v1b 例），不是照改部門那天算到 11/9。
    /// 要退回這一件：`m.handedAt ?? m.appliedAt` 改回 `m.appliedAt`
    static func undoUntilKey(_ m: OrgMove) -> String {
        let applied = (m.handedAt ?? m.appliedAt).map { dayKey($0) } ?? m.effectiveKey
        return addDays(max(m.effectiveKey, applied), 7)
    }

    /// [v25.592 轉組織 v1b] 部門還沒改的（排好的、交出去了還沒到生效日的）不給〔復原這次轉組織〕：用〔取消這張單〕
    ///（已經交出去的會問〔拿回來〕〔留給接手的人〕；judge §3.8 生效前那一列）。要退回這一件：拿掉 `!m.orgPending &&`
    static func canUndo(_ m: OrgMove, todayKey: String) -> Bool {
        // [v25.593 轉組織 v2] 回到我的部屬那一張沒有東西可以復原（要再收起來就再〔轉組織〕調出）。要退回這一件：拿掉 `!m.isBack &&`
        !m.isBack && !m.orgPending && m.wasApplied && !m.isUndone && m.deletedAt == nil && todayKey <= undoUntilKey(m)
    }

    /// 還在交接中（提示列、「交接自」膠囊、接手那一區要不要出現）：套用過、沒復原、沒按〔交接完成〕、
    /// 而且還沒過交接完成日或還有待分派（用算的、不寫）
    static func isOpen(_ m: OrgMove, todayKey: String) -> Bool {
        guard m.wasApplied, !m.isUndone, !m.isClosed, m.deletedAt == nil else { return false }
        if todayKey <= (m.handoverByKey ?? m.effectiveKey) { return true }
        // [v25.590 轉組織 v1a-1 驗證]「還有待分派」照機台現在的負責人算（同 pendingRows、tiles）：在機台編輯頁直接換過負責人
        // ＝算分好，交接完成日過了就收（judge §4.9、第 5／10 題）。要退回這一件：改回 `return pendingLineIds(m).isEmpty == false`
        let pendingEq: [UUID] = pendingLineIds(m).compactMap { m.line($0)?.refId }
        return OrgMoveIndex.stillPending(pendingEq, personId: m.personId)
    }

    // MARK: 第 ① 步

    /// 部門清單（照現在 departments 的順序）。「現在」那一列由畫面標灰字
    static func departmentChoices(_ world: OrgMoveWorld) -> [(id: UUID, label: String)] {
        world.departments.map { d -> (id: UUID, label: String) in
            let code = d.code.trimmingCharacters(in: .whitespaces)
            let name = d.name.trimmingCharacters(in: .whitespaces)
            let label = code.isEmpty ? name : (name.isEmpty ? code : "\(code) \(name)")
            return (id: d.id, label: label.isEmpty ? "未命名部門" : label)
        }
    }

    /// 新主管預設：新部門管理人員裡第一位
    static func suggestedManager(deptId: UUID?, world: OrgMoveWorld) -> UUID? {
        guard let d = world.dept(deptId) else { return nil }
        return d.managerIds.first { id in world.orgPeople.contains { $0.id == id } }
    }

    /// 「設備課 4 位裡 3 位在 P2」（這個部門的部屬最多人在哪個廠；不算這位同仁；沒有人回 nil）
    static func plantHint(deptId: UUID?, excluding personId: UUID, world: OrgMoveWorld) -> (plant: String, text: String)? {
        guard deptId != nil else { return nil }
        // [v25.593 轉組織 v2] 已轉出的不算這個部門的人。要退回這一件：activeSubordinates 改回 subordinates
        let people = world.activeSubordinates.filter { $0.departmentId == deptId && $0.id != personId }
        guard !people.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        var order: [String] = []
        for p in people {
            let k = p.plantArea.trimmingCharacters(in: .whitespaces)
            guard !k.isEmpty else { continue }
            if counts[k] == nil { order.append(k) }
            counts[k, default: 0] += 1
        }
        var best = ""
        var bestN = 0
        for k in order where (counts[k] ?? 0) > bestN {
            best = k
            bestN = counts[k] ?? 0
        }
        guard bestN > 0 else { return nil }
        let text = "\(world.deptShort(deptId)) \(people.count) 位裡 \(bestN) 位在 \(best)"
        return (plant: best, text: text)
    }

    /// 廠區膠囊：部屬們用過的廠區（照字排）
    static func plantChoices(_ world: OrgMoveWorld) -> [String] {
        let all = Set(world.subordinates.map { $0.plantArea.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        return all.sorted()
    }

    /// 〔全部交給 ▾〕的建議人：舊部門管理人員裡第一位是你部屬、又不是這位同仁的（C）
    static func suggestedReceiver(personId: UUID, world: OrgMoveWorld) -> UUID? {
        guard let sub = world.sub(personId), let d = world.dept(sub.departmentId) else { return nil }
        // [v25.593 轉組織 v2] 已轉出的不當建議人（judge §5-2）。要退回這一件：activeSubordinates 改回 subordinates
        let active = world.activeSubordinates
        for mid in d.managerIds {
            guard let p = world.orgPeople.first(where: { $0.id == mid }),
                  let sid = p.linkedSubordinateId, sid != personId,
                  active.contains(where: { $0.id == sid }) else { continue }
            return sid
        }
        return nil
    }

    /// 人名清單：先列「舊部門、同廠區」，再列其他部屬；這位同仁自己不列（judge §4.3）
    static func receiverCandidates(personId: UUID, world: OrgMoveWorld,
                                   sideRoleId: UUID? = nil) -> [(id: UUID, name: String, sub: String)] {
        guard let me = world.sub(personId) else { return [] }
        // [v25.593 轉組織 v2] 人名清單不列已轉出的（judge §3.6、§5-2；挑人頁 OrgMovePersonPicker 都走這一支）。
        // 要退回這一件：activeSubordinates 改回 subordinates
        let others = world.activeSubordinates.filter { $0.id != personId }
        // [v25.591 轉組織 v1a-2] 兼任〔到兼任換人…〕：這個兼任的成員排最前面（副標多「尾牙籌備成員」）；不是成員的選了會先加成員
        var memberIds: [UUID] = []
        if let rid = sideRoleId, let role = world.sideRoles.first(where: { $0.id == rid }) {
            for m in role.sideRoleMembers ?? [] {
                if let pid = m.linkedPersonId, pid != personId, others.contains(where: { $0.id == pid }),
                   !memberIds.contains(pid) { memberIds.append(pid) }
            }
        }
        let members = memberIds.compactMap { id in others.first(where: { $0.id == id }) }
        let memberSet = Set(memberIds)
        let near = others.filter { !memberSet.contains($0.id) && $0.departmentId == me.departmentId && $0.plantArea == me.plantArea }
        let nearIds = Set(near.map(\.id))
        let rest = others.filter { !nearIds.contains($0.id) && !memberSet.contains($0.id) }
        let roleName = sideRoleId.map { world.sideRoleName($0) } ?? ""
        return (members + near + rest).map { s -> (id: UUID, name: String, sub: String) in
            let n = s.name.trimmingCharacters(in: .whitespacesAndNewlines)
            var parts = [world.deptShort(s.departmentId), s.plantArea.trimmingCharacters(in: .whitespaces),
                         world.titleLabel(gradeTitleId: s.gradeTitleId, jobTitle: s.jobTitle)]
            if memberSet.contains(s.id) { parts.insert("\(roleName)成員", at: 0) }
            // [v25.592 轉組織 v1b] 接手的人自己也排了轉組織：副標多「11/9 也要調走」（judge §4.3、§5-1）。要退回這一件：刪這一行
            if let leaving = leavingNote(s.id) { parts.append(leaving) }
            return (id: s.id, name: n.isEmpty ? "未命名" : n, sub: parts.filter { !$0.isEmpty }.joined(separator: "・"))
        }
    }

    // MARK: 清單（第 ② 步）

    static func taskTitle(_ t: SubordinateTask) -> String {
        let topic = t.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !topic.isEmpty { return topic }
        let c = t.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return c.isEmpty ? "未命名任務" : c
    }

    /// 「11/6 月報：P1 良率」
    static func reportTitle(_ r: WeeklyReport) -> String {
        let topic = r.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = topic.isEmpty ? (r.reportType.isEmpty ? "未命名報告" : r.reportType) : topic
        return shortDay(dayKey(r.date)) + " " + t
    }

    /// 這位同仁手上還沒做完的待辦、機台、會議與議程、週報、以後的班，加上管理人員身分（judge §3.2）。
    /// 順序：待辦（截止早的先，同 TeamDay.incompleteTasks；兼任的任務、議程也在這組）→ 機台（照名字；每台後面接它還沒處理完的警報任務）
    /// → 會議與議程（每場會議後面接它的議程，再接別人會議裡交給這位同仁的）→ 週報（照報告日）→ 班 → 管理人員。
    /// kind == .plant（只換廠區）：只列機台（和它們的警報任務）、會議（預設照舊）、以後的班（judge §5-22）。
    /// [v25.591 轉組織 v1a-2] 加會議、議程、班、兼任四種（v1a-1 只有灰字「下一版才能在這裡交」）；
    /// plantChanges：廠區有換（班的預設：換了部門或廠區＝還沒決定，都沒換＝跟著）
    static func buildLines(personId: UUID, kind: OrgMoveKind, deptChanges: Bool, effectiveKey: String,
                           world: OrgMoveWorld, now: Date, plantChanges: Bool = false) -> [OrgMoveLine] {
        guard let sub = world.sub(personId) else { return [] }
        let todayKey = dayKey(now)
        let cut = cutKey(effectiveKey: effectiveKey, todayKey: todayKey)
        let owned = world.equipment.filter { $0.ownerId == personId }
            .sorted { a, b in
                let x = a.name.localizedStandardCompare(b.name)
                if x != .orderedSame { return x == .orderedAscending }
                return a.id.uuidString < b.id.uuidString
            }
        let ownedIds = Set(owned.map(\.id))
        let open = sub.tasks.filter { !$0.isCompleted }
            .sorted { a, b in
                let ka = a.dueDate ?? a.date
                let kb = b.dueDate ?? b.date
                if ka != kb { return ka < kb }
                return a.id.uuidString < b.id.uuidString
            }
        var taskLines: [OrgMoveLine] = []
        var alarmLines: [UUID: [OrgMoveLine]] = [:]
        var sideSeen = Set<UUID>()
        for t in open {
            let due = t.dueDate.map { dayKey($0) }
            let overdue = t.dueDate.map { $0 < now } ?? false
            if let link = t.equipmentLink, ownedIds.contains(link.equipmentId) {
                let l = OrgMoveLine(kind: OrgMoveLineKind.alarmTask.rawValue, refId: t.id, parentId: link.equipmentId,
                                    holderId: personId, title: taskTitle(t), dueKey: due,
                                    action: OrgMoveAction.withEquipment.rawValue,
                                    newDueKey: overdue ? newAlarmDueKey(todayKey: todayKey) : nil,
                                    lock: OrgMoveLock.alarm.rawValue)
                alarmLines[link.equipmentId, default: []].append(l)
                continue
            }
            // [v25.593 轉組織 v2] 調出、離職、退休跟換單位一樣列全部（只換廠區才只列機台、會議、班）。要退回這一件：改回 `kind == .move`
            guard kind != .plant else { continue }
            if let back = t.sideRoleLink, world.sideRoleAlive(back) {
                // [v25.591 轉組織 v1a-2] 不再鎖：〔照舊〕〔到兼任換人…〕（預設照舊；〔全部交給〕不動它）
                guard !sideSeen.contains(back.taskId) else { continue }
                sideSeen.insert(back.taskId)
                // [v25.591 轉組織 v1a-2 驗證] 標題：App 自動建的分身 topic 是兼任名稱（「尾牙籌備」），寫那件事（「尾牙場控彩排」）。
                // 要退回這一件：title 改回 taskTitle(t)
                taskLines.append(OrgMoveLine(kind: OrgMoveLineKind.sideRole.rawValue, refId: back.taskId, itemId: t.id,
                                             parentId: back.roleId, holderId: personId,
                                             title: sideRoleLineTitle(t, back: back, world: world),
                                             dueKey: due, action: OrgMoveAction.follow.rawValue))
                continue
            }
            if t.isDereliction {
                taskLines.append(OrgMoveLine(kind: OrgMoveLineKind.task.rawValue, refId: t.id, holderId: personId,
                                             title: taskTitle(t), dueKey: due, action: OrgMoveAction.follow.rawValue,
                                             lock: OrgMoveLock.dereliction.rawValue))
                continue
            }
            let parent: UUID? = t.linkedEquipmentIds.first(where: { ownedIds.contains($0) })
            taskLines.append(OrgMoveLine(kind: OrgMoveLineKind.task.rawValue, refId: t.id, parentId: parent,
                                         holderId: personId, title: taskTitle(t), dueKey: due,
                                         action: parent == nil ? nil : OrgMoveAction.withEquipment.rawValue,
                                         newDueKey: overdue ? newDueKey(effectiveKey: effectiveKey, todayKey: todayKey) : nil))
        }
        var eqLines: [OrgMoveLine] = []
        for e in owned {
            eqLines.append(OrgMoveLine(kind: OrgMoveLineKind.equipment.rawValue, refId: e.id, holderId: personId,
                                       title: world.equipmentName(e.id)))
            eqLines.append(contentsOf: alarmLines[e.id] ?? [])
        }
        // [v25.591 轉組織 v1a-2] 兼任的議程（拉進兼任的）接在待辦那組後面；會議與議程、以後的班
        if kind != .plant {
            taskLines.append(contentsOf: sideRoleAgendaLines(personId: personId, sub: sub, world: world, seen: &sideSeen))
        }
        let meetingLines = meetingAndAgendaLines(personId: personId, sub: sub, owned: owned, cutKey: cut,
                                                 withAgenda: kind != .plant, world: world)
        let changes = kind == .plant ? true : (deptChanges || plantChanges)
        let shiftLines: [OrgMoveLine] = shiftsLine(personId: personId, sub: sub, cutKey: cut,
                                                   defaultFollow: !changes).map { [$0] } ?? []
        var reportLines: [OrgMoveLine] = []
        var managerLines: [OrgMoveLine] = []
        if kind != .plant {
            let effStart = date(fromKey: effectiveKey) ?? now
            let reps = sub.weeklyReports.filter { !$0.isCompleted }
                .sorted { a, b in a.date != b.date ? a.date < b.date : a.id.uuidString < b.id.uuidString }
            for r in reps {
                let due = dayKey(r.date)
                if r.date < now {
                    reportLines.append(OrgMoveLine(kind: OrgMoveLineKind.report.rawValue, refId: r.id, holderId: personId,
                                                   title: reportTitle(r), dueKey: due,
                                                   action: OrgMoveAction.follow.rawValue,
                                                   lock: OrgMoveLock.pastDue.rawValue))
                } else if r.date < effStart {
                    reportLines.append(OrgMoveLine(kind: OrgMoveLineKind.report.rawValue, refId: r.id, holderId: personId,
                                                   title: reportTitle(r), dueKey: due,
                                                   action: OrgMoveAction.follow.rawValue))
                } else {
                    let isPM = r.reportType.trimmingCharacters(in: .whitespaces).uppercased() == "PM"
                    let linkedOwned: UUID? = r.linkedEquipmentIds.first(where: { ownedIds.contains($0) })
                    let parent: UUID? = isPM ? linkedOwned : nil
                    reportLines.append(OrgMoveLine(kind: OrgMoveLineKind.report.rawValue, refId: r.id, parentId: parent,
                                                   holderId: personId, title: reportTitle(r), dueKey: due,
                                                   action: parent == nil ? nil : OrgMoveAction.withEquipment.rawValue))
                }
            }
            if let op = world.orgPerson(linkedTo: personId) {
                for d in world.departments {
                    guard let idx = d.managerIds.firstIndex(of: op.id) else { continue }
                    // [v25.593 轉組織 v2] 調出、離職、退休：每一個部門的管理人員身分預設〔拿掉〕
                    let act: OrgMoveAction = (deptChanges || kind.isLeaving) ? .remove : .keep
                    managerLines.append(OrgMoveLine(kind: OrgMoveLineKind.manager.rawValue, refId: d.id,
                                                    title: "\(world.deptShort(d.id)) 管理人員",
                                                    action: act.rawValue, slot: idx))
                }
            }
        }
        var out = taskLines + eqLines + meetingLines + reportLines + shiftLines + managerLines
        // [v25.593 轉組織 v2] 調出、離職、退休的預設（judge §3.6「預設變了」、第 3 題；OrgMoveOut.swift）。要退回這一件：刪這一行
        applyLeavingDefaults(&out, kind: kind, personId: personId, world: world)
        return out
    }

    /// 第 ① 步改了（換單位／只換廠區、新部門、照舊）之後重算清單：同一筆（kind＋refId）你動過的（updatedAt 有值）照留，
    /// 沒動過的換成新的預設。管理人員那幾列跟著「部門有沒有換」換預設。
    static func rebuild(_ draft: inout OrgMoveDraft, world: OrgMoveWorld, now: Date) {
        let fresh = buildLines(personId: draft.personId, kind: draft.kind, deptChanges: deptChanges(draft, world: world),
                               effectiveKey: dayKey(draft.effective), world: world, now: now,
                               plantChanges: plantChanges(draft, world: world))
        var touched: [String: OrgMoveLine] = [:]
        let oldCustom = draft.lines.filter(\.isLiveCustom)
        for l in draft.lines where l.updatedAt != nil {
            let key = l.kind + "|" + (l.refId?.uuidString ?? "")
            touched[key] = l
        }
        draft.lines = fresh.map { (l: OrgMoveLine) -> OrgMoveLine in
            let key = l.kind + "|" + (l.refId?.uuidString ?? "")
            guard var t = touched[key] else { return l }
            // [v25.591 轉組織 v1a-2] 會議、班：你選的照留，交接那天（dueKey）與班的標題照新的生效日重算
            if l.kind == OrgMoveLineKind.meeting.rawValue || l.kind == OrgMoveLineKind.shifts.rawValue {
                t.dueKey = l.dueKey
                t.title = l.title
            }
            return t
        }
        // [v25.592 轉組織 v1b] 你自己加的一項（門禁卡、鑰匙…）重算時照留，排在最後（buildLines 不會長出這種）。要退回這一件：刪這一行
        draft.lines.append(contentsOf: oldCustom)
    }

    /// [v25.591 轉組織 v1a-2] 這次廠區有沒有換（班的預設用；只換廠區、換單位都看 toPlant）
    static func plantChanges(_ draft: OrgMoveDraft, world: OrgMoveWorld) -> Bool {
        let p = draft.toPlant.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty, let sub = world.sub(draft.personId) else { return false }
        return p != sub.plantArea.trimmingCharacters(in: .whitespaces)
    }

    /// 這次部門有沒有換（換單位、不是〔照舊〕、新部門跟現在的不一樣）
    static func deptChanges(_ draft: OrgMoveDraft, world: OrgMoveWorld) -> Bool {
        // [v25.593 轉組織 v2] 調出也改部門（離職、退休不改）。要退回這一件：改回 `draft.kind == .move`
        guard draft.kind.canChangeDept, !draft.keepDept, let to = draft.toDeptId else { return false }
        return world.sub(draft.personId)?.departmentId != to
    }

    /// 這一列的動作照「跟著機台」算到底（跟著 E-03 → E-03 交給陳怡君＝交給陳怡君）。回傳（動作, 接手的人 id, 名字）
    static func resolved(_ line: OrgMoveLine, in lines: [OrgMoveLine]) -> (action: OrgMoveAction?, toId: UUID?, toName: String?) {
        guard let a = line.lineAction else { return (nil, nil, nil) }
        if a == .withEquipment {
            guard let pid = line.parentId,
                  let p = lines.first(where: { $0.kind == OrgMoveLineKind.equipment.rawValue && $0.refId == pid })
            else { return (.follow, nil, nil) }
            return (p.lineAction, p.toId, p.toName)
        }
        return (a, line.toId, line.toName)
    }

    /// 這一列能選的（judge §3.2）。[v25.591 轉組織 v1a-2] 會議、議程、班、兼任要知道整張清單與這位同仁是誰：用這一支
    /// [v25.593 轉組織 v2] kind：調出、離職、退休時多〔交出去…〕、拿掉〔照舊〕〔跟著〕那幾顆（leavingChoices；OrgMoveOut.swift）。
    /// 呼叫端不給＝換單位（v1a～v1b 的行為）
    static func choices(_ line: OrgMoveLine, in lines: [OrgMoveLine], personId: UUID, personName: String,
                        world: OrgMoveWorld, kind: OrgMoveKind = .move) -> [OrgMoveChoice] {
        let base: [OrgMoveChoice]
        // [v25.592 轉組織 v1b] 你自己加的一項：〔交給…〕〔跟著王小明〕（拿掉這一項在那一列往左滑）
        if line.isCustom {
            base = customChoices(personName: personName)
        } else {
            switch line.lineKind {
            case .some(.meeting): base = meetingChoices(line, in: lines, world: world)
            case .some(.agenda): base = agendaChoices(line, personId: personId, world: world)
            case .some(.shifts): base = shiftsChoices(personName: personName)
            case .some(.sideRole):
                // v1a-1 存的舊單（鎖著）照舊只有〔照舊〕
                base = line.lineLock == .sideRole ? [OrgMoveChoice(action: .follow, label: "照舊", needsPerson: false)] : sideRoleChoices()
            default: base = choices(line, personName: personName, world: world)
            }
        }
        // 要退回這一件：改回直接 return base
        return leavingChoices(base, line: line, kind: kind)
    }

    /// 這一列能選的（v1a-1 那幾種；會議、議程、班、兼任請用上面那一支）
    static func choices(_ line: OrgMoveLine, personName: String, world: OrgMoveWorld) -> [OrgMoveChoice] {
        let follow = OrgMoveChoice(action: .follow, label: "跟著\(personName)", needsPerson: false)
        let give = OrgMoveChoice(action: .give, label: "交給…", needsPerson: true)
        let drop = OrgMoveChoice(action: .drop, label: "不要了", needsPerson: false)
        switch line.lineKind {
        case .some(.task):
            if line.lineLock == .dereliction {
                return [follow, OrgMoveChoice(action: .closeNow, label: "現在結案（−1 算\(personName)）", needsPerson: false)]
            }
            var out: [OrgMoveChoice] = []
            if line.parentId != nil {
                out.append(OrgMoveChoice(action: .withEquipment, label: "跟著 \(world.equipmentName(line.parentId))", needsPerson: false))
            }
            return out + [give, follow, drop]
        case .some(.report):
            if line.lineLock == .pastDue {
                return [follow, OrgMoveChoice(action: .drop, label: "不要了（扣分留\(personName)）", needsPerson: false)]
            }
            var out: [OrgMoveChoice] = []
            if line.parentId != nil {
                out.append(OrgMoveChoice(action: .withEquipment, label: "跟著 \(world.equipmentName(line.parentId))", needsPerson: false))
            }
            return out + [give, follow, drop]
        case .some(.equipment):
            return [give, OrgMoveChoice(action: .pending, label: "待分派", needsPerson: false), follow]
        case .some(.alarmTask):
            return [OrgMoveChoice(action: .withEquipment, label: "跟著 \(world.equipmentName(line.parentId))", needsPerson: false)]
        case .some(.sideRole):
            return line.lineLock == .sideRole ? [OrgMoveChoice(action: .follow, label: "照舊", needsPerson: false)] : sideRoleChoices()
        case .some(.meeting):
            return meetingChoices(line, in: [line], world: world)
        case .some(.agenda):
            return agendaChoices(line, personId: line.holderId ?? UUID(), world: world)
        case .some(.shifts):
            return shiftsChoices(personName: personName)
        case .some(.manager):
            return [OrgMoveChoice(action: .remove, label: "拿掉", needsPerson: false),
                    OrgMoveChoice(action: .keep, label: "照舊", needsPerson: false),
                    OrgMoveChoice(action: .replace, label: "換成…", needsPerson: true)]
        case .some(.managerAdd):
            return [OrgMoveChoice(action: .skip, label: "不用", needsPerson: false),
                    OrgMoveChoice(action: .add, label: "加", needsPerson: false)]
        case .none:
            return []
        }
    }

    /// 膠囊上的字（「交給 陳怡君」「🔗 跟著 蝕刻機 E-03 → 陳怡君」「🔒 跟著王小明」「照舊」「還沒決定」）
    static func capsuleText(_ line: OrgMoveLine, in lines: [OrgMoveLine], personName: String, world: OrgMoveWorld) -> String {
        // [v25.591 轉組織 v1a-2] 會議、議程、班、兼任的字在 OrgMoveMeetingPlan.swift
        if let t = moreCapsuleText(line, personName: personName, world: world),
           line.lineLock != .sideRole { return t }
        guard let a = line.lineAction else { return "還沒決定" }
        switch a {
        case .give:
            return "交給 \(line.toName ?? "")"
        case .follow:
            if line.lineLock == .sideRole { return "照舊" }
            if line.lineLock == .dereliction { return "🔒 跟著\(personName)" }
            return "跟著\(personName)"
        case .withEquipment:
            let eq = world.equipmentName(line.parentId)
            let r = resolved(line, in: lines)
            switch r.action {
            case .some(.give): return "🔗 跟著 \(eq) → \(r.toName ?? "")"
            case .some(.pending): return "🔗 跟著 \(eq)（待分派）"
            case .some(.follow): return "🔗 跟著 \(eq)（跟著\(personName)）"
            default: return "🔗 跟著 \(eq)"
            }
        case .pending: return "待分派"
        case .drop: return "不要了"
        case .closeNow: return "現在結案"
        case .remove: return "拿掉"
        case .keep: return "照舊"
        case .replace: return "換成 \(line.toName ?? "")"
        case .add: return "加"
        case .skip: return "不用"
        case .end: return "最後一場"
        case .newSeries: return "交給 \(line.toName ?? "")"
        // [v25.593 轉組織 v2]〔交出去〕：「交出去 黃冠宇」「我先接」
        case .handOut: return handOutCapsule(line)
        }
    }

    /// 灰字＝為什麼這樣排（一到三行）。[v25.591 轉組織 v1a-2] 會議、議程、班、兼任要整張清單與這位同仁：用這一支
    static func reasonLines(_ line: OrgMoveLine, in lines: [OrgMoveLine], personId: UUID, personName: String,
                            world: OrgMoveWorld, now: Date) -> [String] {
        // [v25.592 轉組織 v1b] 你自己加的一項
        if line.isCustom { return customReasons(line) }
        if line.lineLock != .sideRole,
           let r = moreReasonLines(line, in: lines, personId: personId, personName: personName, world: world, now: now) {
            return r
        }
        return reasonLines(line, personName: personName, world: world, now: now)
    }

    /// 灰字（v1a-1 那幾種；會議、議程、班、兼任請用上面那一支）
    static func reasonLines(_ line: OrgMoveLine, personName: String, world: OrgMoveWorld, now: Date) -> [String] {
        let todayKey = dayKey(now)
        if line.lineLock != .sideRole,
           let r = moreReasonLines(line, in: [line], personId: nil, personName: personName, world: world, now: now) {
            return r
        }
        switch line.lineKind {
        case .some(.task), .some(.sideRole), .some(.alarmTask):
            let taskId = line.kind == OrgMoveLineKind.sideRole.rawValue ? line.itemId : line.refId
            let task = world.sub(line.holderId)?.tasks.first { $0.id == taskId }
            var first = dueReason(line.dueKey, todayKey: todayKey, due: task?.dueDate, now: now)
            if line.kind == OrgMoveLineKind.alarmTask.rawValue {
                let alarmDay = task.map { shortDay(dayKey($0.date)) } ?? ""
                first = alarmDay.isEmpty ? first : "\(alarmDay) 的警報・" + first
            }
            if line.kind == OrgMoveLineKind.sideRole.rawValue {
                return ["兼任「\(world.sideRoleName(line.parentId))」・" + first,
                        "兼任的待辦請到兼任「\(world.sideRoleName(line.parentId))」換負責成員"]
            }
            if line.kind == OrgMoveLineKind.task.rawValue, line.parentId != nil {
                first += "・連到\(world.equipmentName(line.parentId))"
            }
            if line.lineLock == .dereliction {
                return [first, "缺失是這位同仁自己的：只能跟著或現在結案"]
            }
            return [first]
        case .some(.report):
            var first = "報告日 \(dayText(line.dueKey))"
            if line.parentId != nil { first += "・連到\(world.equipmentName(line.parentId))" }
            if line.lineLock == .pastDue {
                return [first, "這份已經過了交的日子，扣分是\(personName)的"]
            }
            if line.action == OrgMoveAction.follow.rawValue && line.updatedAt == nil {
                return [first, "生效前到期，\(personName)自己交"]
            }
            return [first]
        case .some(.equipment):
            var parts: [String] = []
            let e = world.equipmentItem(line.refId)
            let d = world.deptShort(e?.departmentId)
            if !d.isEmpty { parts.append(d) }
            let openAlarms = world.sub(line.holderId)?.tasks.filter {
                !$0.isCompleted && $0.equipmentLink?.equipmentId == line.refId
            }.count ?? 0
            if openAlarms > 0 { parts.append("沒處理完的警報 \(openAlarms)") }
            var out = [parts.isEmpty ? "機台" : parts.joined(separator: "・")]
            if line.action == OrgMoveAction.pending.rawValue {
                out.append("待分派時，新的警報照樣先掛給\(personName)（分好之前逾期不算\(personName)）")
            }
            return out
        case .some(.manager):
            return ["\(personName)是 \(line.title.replacingOccurrences(of: " 管理人員", with: "")) 的管理人員"]
        case .some(.managerAdd), .some(.meeting), .some(.agenda), .some(.shifts), .none:
            return []
        }
    }

    /// 「10/20 到期・已逾期 8 天」「11/5 到期」「沒有截止日」
    private static func dueReason(_ dueKey: String?, todayKey: String, due: Date?, now: Date) -> String {
        guard let k = dueKey else { return "沒有截止日" }
        let overdue = due.map { $0 < now } ?? (k < todayKey)
        if overdue, let a = date(fromKey: k), let b = date(fromKey: todayKey) {
            let days = calendar.dateComponents([.day], from: a, to: b).day ?? 0
            if days > 0 { return "\(shortDay(k)) 到期・已逾期 \(days) 天" }
            return "\(shortDay(k)) 到期・已逾期"
        }
        return "\(shortDay(k)) 到期"
    }

    /// 交出去的已逾期那件，膠囊下面多兩行（judge §4.3）：「新的截止日 11/9（一）」「逾期的扣分留在王小明，陳怡君從 11/9 算」。
    /// 只有算到底是〔交給〕、而且現在已經逾期的待辦、警報任務才有
    static func overdueNote(_ line: OrgMoveLine, in lines: [OrgMoveLine], personName: String,
                            world: OrgMoveWorld, now: Date) -> [String]? {
        guard line.kind == OrgMoveLineKind.task.rawValue || line.kind == OrgMoveLineKind.alarmTask.rawValue,
              line.lineLock != .dereliction, let nk = line.newDueKey else { return nil }
        let r = resolved(line, in: lines)
        guard r.action == .give else { return nil }
        let task = world.sub(line.holderId)?.tasks.first { $0.id == line.refId }
        guard let due = task?.dueDate, due < now else { return nil }
        let who = r.toName ?? ""
        return ["新的截止日 \(dayText(nk))", "逾期的扣分留在\(personName)，\(who)從 \(shortDay(nk)) 算"]
    }

    /// 頂端件數（不算組織那幾列；跟著機台的照那台機台現在的決定算）
    static func tally(_ lines: [OrgMoveLine]) -> OrgMoveTally {
        var t = OrgMoveTally()
        var order: [UUID] = []
        var names: [UUID: String] = [:]
        var counts: [UUID: Int] = [:]
        // [v25.592 轉組織 v1b] 你自己加的一項也算（交給陳怡君＝交給別人 +1）。要退回這一件：拿掉 `|| l.isCustom`
        for l in lines where !l.isOrgLine && (l.lineKind != nil || l.isLiveCustom) {
            let r = resolved(l, in: lines)
            switch r.action {
            case .none:
                t.undecided += 1
            case .some(.give):
                t.given += 1
                if let id = r.toId {
                    if counts[id] == nil { order.append(id) }
                    counts[id, default: 0] += 1
                    names[id] = r.toName ?? ""
                }
            case .some(.newSeries):
                // [v25.591 轉組織 v1a-2] 會議〔交給…〕＝交給別人
                t.given += 1
                if let id = r.toId {
                    if counts[id] == nil { order.append(id) }
                    counts[id, default: 0] += 1
                    names[id] = r.toName ?? ""
                }
            case .some(.pending):
                t.pending += 1
            case .some(.drop):
                t.dropped += 1
            case .some(.end):
                t.ended += 1
            case .some(.handOut):
                // [v25.593 轉組織 v2]〔交出去〕另外算（不在部屬名單的人、我）
                t.handedOut += 1
            default:
                t.follow += 1
            }
        }
        t.byReceiver = order.map { id -> (id: UUID, name: String, count: Int) in
            (id: id, name: names[id] ?? "", count: counts[id] ?? 0)
        }
        return t
    }

    /// 「還沒決定 0・交給別人 5・跟著 2・待分派 1」（不要了有才接「・不要了 1」；會議〔最後一場〕有才接「・結束 1」）
    static func tallyText(_ t: OrgMoveTally) -> String {
        var s = "還沒決定 \(t.undecided)・交給別人 \(t.given)・跟著 \(t.follow)・待分派 \(t.pending)"
        if t.dropped > 0 { s += "・不要了 \(t.dropped)" }
        if t.ended > 0 { s += "・結束 \(t.ended)" }
        // [v25.593 轉組織 v2] 「・交出去 2」（給不在部屬名單的人、給我）
        if t.handedOut > 0 { s += "・交出去 \(t.handedOut)" }
        return s
    }

    /// 「（陳怡君 4、林志豪 1）」（沒有交給任何人＝空字串）
    static func receiverText(_ t: OrgMoveTally) -> String {
        guard !t.byReceiver.isEmpty else { return "" }
        return "（" + t.byReceiver.map { "\($0.name) \($0.count)" }.joined(separator: "、") + "）"
    }

    /// 〔全部交給…〕／〔這組交給…〕：只把「還沒決定」的列設成同一人；有預設的（跟著、跟著機台）、你改過的、鎖住的、組織那幾列不動。
    /// onlyIds：nil＝全部；有值＝只動這一組。回傳改了幾列
    @discardableResult
    static func giveAll(_ lines: inout [OrgMoveLine], to: UUID, toName: String, onlyIds: Set<UUID>? = nil,
                        now: Date) -> Int {
        var n = 0
        for i in lines.indices {
            let l = lines[i]
            // [v25.592 轉組織 v1b] 你自己加的一項（還沒決定的）也一起帶。要退回這一件：拿掉 `|| l.isCustom`
            guard l.action == nil, !l.isLocked, !l.isOrgLine, l.lineKind != nil || l.isLiveCustom else { continue }
            if let only = onlyIds, !only.contains(l.id) { continue }
            lines[i].action = OrgMoveAction.give.rawValue
            lines[i].toId = to
            lines[i].toName = toName
            lines[i].updatedAt = now
            n += 1
        }
        return n
    }

    /// 改一列的動作（畫面上點膠囊選單）。交給／換成要帶人；其他會把人清掉
    static func setAction(_ lines: inout [OrgMoveLine], lineId: UUID, action: OrgMoveAction,
                          toId: UUID? = nil, toName: String? = nil, now: Date) {
        guard let i = lines.firstIndex(where: { $0.id == lineId }) else { return }
        let oldTo = lines[i].toId
        let oldAction = lines[i].action
        lines[i].action = action.rawValue
        // [v25.593 轉組織 v2]〔交出去〕也帶人（組織人員或「我」）。要退回這一件：拿掉 `|| action == .handOut`
        let keepsPerson = action == .give || action == .replace || action == .newSeries || action == .handOut
        lines[i].toId = keepsPerson ? toId : nil
        lines[i].toName = keepsPerson ? toName : nil
        lines[i].updatedAt = now
        // [v25.591 轉組織 v1a-2] 會議〔交給…〕：新會議的 id 先配好（兩台、重做都只有一條）
        if action == .newSeries, lines[i].newId == nil { lines[i].newId = UUID() }
        // 班換了接手的人：撞班那幾天重新問（換人之後撞的是別天）
        if lines[i].kind == OrgMoveLineKind.shifts.rawValue, oldTo != lines[i].toId || oldAction != action.rawValue {
            lines[i].days = nil
        }
    }

    /// 第 ② 步的分組（待辦／機台／週報題目／組織）；空的組不出現。機台那組裡警報任務緊接在它的機台後面（畫面縮排）
    static func groups(_ lines: [OrgMoveLine]) -> [OrgMoveGroup] {
        let tasks = lines.filter { $0.kind == OrgMoveLineKind.task.rawValue || $0.kind == OrgMoveLineKind.sideRole.rawValue }
        let eq = lines.filter { $0.kind == OrgMoveLineKind.equipment.rawValue || $0.kind == OrgMoveLineKind.alarmTask.rawValue }
        let mtg = lines.filter { $0.kind == OrgMoveLineKind.meeting.rawValue || $0.kind == OrgMoveLineKind.agenda.rawValue }
        let reps = lines.filter { $0.kind == OrgMoveLineKind.report.rawValue }
        let shifts = lines.filter { $0.kind == OrgMoveLineKind.shifts.rawValue }
        let org = lines.filter { $0.isOrgLine }
        let machines = eq.filter { $0.kind == OrgMoveLineKind.equipment.rawValue }.count
        let meetings = mtg.filter { $0.kind == OrgMoveLineKind.meeting.rawValue }.count
        let agenda = mtg.count - meetings
        var out: [OrgMoveGroup] = []
        if !tasks.isEmpty { out.append(OrgMoveGroup(id: "tasks", title: "待辦 \(tasks.count)", lineIds: tasks.map(\.id), canGiveAll: true)) }
        if !eq.isEmpty { out.append(OrgMoveGroup(id: "equipment", title: "機台 \(machines)", lineIds: eq.map(\.id), canGiveAll: true)) }
        if !mtg.isEmpty {
            // [v25.591 轉組織 v1a-2]「會議 1・議程 3」（〔這組交給〕只動還沒決定的議程：會議預設照舊）
            let title = [meetings > 0 ? "會議 \(meetings)" : "", agenda > 0 ? "議程 \(agenda)" : ""]
                .filter { !$0.isEmpty }.joined(separator: "・")
            out.append(OrgMoveGroup(id: "meetings", title: title, lineIds: mtg.map(\.id), canGiveAll: true))
        }
        if !reps.isEmpty { out.append(OrgMoveGroup(id: "reports", title: "週報題目 \(reps.count)", lineIds: reps.map(\.id), canGiveAll: true)) }
        if !shifts.isEmpty { out.append(OrgMoveGroup(id: "shifts", title: "以後的班", lineIds: shifts.map(\.id), canGiveAll: false)) }
        // [v25.592 轉組織 v1b]「自己加的 2」（門禁卡、鑰匙…；〔這組交給 ▾〕可以）。要退回這一件：刪這兩行
        let custom = lines.filter(\.isLiveCustom)
        if !custom.isEmpty { out.append(OrgMoveGroup(id: "custom", title: "自己加的 \(custom.count)", lineIds: custom.map(\.id), canGiveAll: true)) }
        if !org.isEmpty { out.append(OrgMoveGroup(id: "org", title: "組織 \(org.count)", lineIds: org.map(\.id), canGiveAll: false)) }
        return out
    }

    /// 第 ① 步底下按鈕「下一步：交接清單（9 項）」的件數＝第 ② 步會列的總列數（管理人員那幾列也算；新部門要不要加不算）
    static func lineCount(_ lines: [OrgMoveLine]) -> Int {
        lines.filter { $0.kind != OrgMoveLineKind.managerAdd.rawValue && $0.lineKind != nil }.count
    }

    /// 最下面灰字「下一版才能在這裡交：1on1 1・議程 3・11/2 以後的班 7 格（先到原本的地方改）」（v1a-1；沒有就 nil）。
    /// 會議：一對一（名稱像 1on1，同匯出的判斷）寫「1on1」，其他寫「會議」；議程＝自己會議裡沒做完的＋別人會議裡交給這位同仁的；
    /// 班＝生效日與今天取晚的那天（含）以後
    /// [v25.591 轉組織 v1a-2] 會議、議程、班、兼任都在清單上交了：一律 nil（灰字那一行不再出現）。
    /// 留著這支只是讓舊的呼叫端照樣編得過（G1 會拿掉呼叫）。要退回 v1a-1 的灰字：刪掉下面這一行 `return nil` 與 `_ = …`。
    static func deferredText(personId: UUID, effectiveKey: String, world: OrgMoveWorld, now: Date) -> String? {
        return nil
    }

    /// v1a-1 的灰字（只給 sim 對照、v1a-1 的舊單回看；畫面不用）
    static func deferredTextV1a1(personId: UUID, effectiveKey: String, world: OrgMoveWorld, now: Date) -> String? {
        guard let sub = world.sub(personId) else { return nil }
        let oneOnOne = sub.meetings.filter { SubExportComposer.isOneOnOneName($0.topic) }.count
        let otherMeetings = sub.meetings.count - oneOnOne
        var agenda = 0
        for m in sub.meetings {
            agenda += m.allItems.filter { !$0.isCompleted }.count
        }
        var mine: Set<UUID> = [personId]
        if let op = world.orgPerson(linkedTo: personId) {
            mine.insert(op.id)
            if let cid = op.linkedBusinessCardId { mine.insert(cid) }
        }
        for other in world.subordinates where other.id != personId {
            for m in other.meetings {
                agenda += m.allItems.filter { item in
                    !item.isCompleted && item.assigneeIds.contains(where: { mine.contains($0) })
                }.count
            }
        }
        let fromKey = max(effectiveKey, dayKey(now))
        let shifts = sub.shifts.filter { dayKey($0.date) >= fromKey }.count
        var parts: [String] = []
        if oneOnOne > 0 { parts.append("1on1 \(oneOnOne)") }
        if otherMeetings > 0 { parts.append("會議 \(otherMeetings)") }
        if agenda > 0 { parts.append("議程 \(agenda)") }
        if shifts > 0 { parts.append("\(shortDay(fromKey)) 以後的班 \(shifts) 格") }
        guard !parts.isEmpty else { return nil }
        return "下一版才能在這裡交：" + parts.joined(separator: "・") + "（先到原本的地方改）"
    }

    /// 最下面灰字「跟著王小明、不用交：11/12 有 1 筆請假」（今天以後的請假；沒有就 nil）
    static func leaveNote(personId: UUID, personName: String, world: OrgMoveWorld, now: Date) -> String? {
        guard let sub = world.sub(personId) else { return nil }
        let todayKey = dayKey(now)
        let future = sub.records.filter { $0.type == .leave && dayKey($0.endDate ?? $0.date) >= todayKey }
            .sorted { $0.date < $1.date }
        guard let first = future.first else { return nil }
        let day = shortDay(dayKey(first.date))
        if future.count == 1 { return "跟著\(personName)、不用交：\(day) 有 1 筆請假" }
        return "跟著\(personName)、不用交：\(day) 等 \(future.count) 筆請假"
    }

    // MARK: 第 ③ 步：預覽

    /// 「製造一課 P1」（部門照舊時只有廠區）
    static func sideText(_ s: OrgMoveSide, world: OrgMoveWorld) -> String {
        var dept = world.deptShort(s.deptId)
        if dept.isEmpty {
            let lbl = s.deptLabel ?? ""
            if let r = lbl.range(of: " — ") { dept = String(lbl[r.upperBound...]) } else { dept = lbl }
        }
        let parts = [dept, s.plant ?? ""].filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }

    /// 草稿 → 一張還沒套用的交接單（state 先寫 applied，LifeStore.applyOrgMove 做完才寫時間）
    static func makeMove(_ draft: OrgMoveDraft, world: OrgMoveWorld, now: Date) -> OrgMove {
        let sub = world.sub(draft.personId)
        let effKey = dayKey(draft.effective)
        let fromSide = OrgMoveSide(deptId: sub?.departmentId,
                                   deptLabel: sub.map { s in world.deptLabel(s.departmentId).isEmpty ? s.department : world.deptLabel(s.departmentId) },
                                   plant: sub?.plantArea,
                                   gradeTitleId: sub?.gradeTitleId,
                                   titleLabel: sub.map { world.titleLabel(gradeTitleId: $0.gradeTitleId, jobTitle: $0.jobTitle) },
                                   managerId: nil, managerName: nil)
        let changes = deptChanges(draft, world: world)
        let toDept: UUID? = changes ? draft.toDeptId : sub?.departmentId
        let toGrade: UUID? = draft.toGradeTitleId ?? sub?.gradeTitleId
        let plant = draft.toPlant.trimmingCharacters(in: .whitespaces)
        let toSide = OrgMoveSide(deptId: toDept,
                                 deptLabel: changes ? world.deptLabel(toDept) : fromSide.deptLabel,
                                 plant: plant.isEmpty ? sub?.plantArea : plant,
                                 gradeTitleId: toGrade,
                                 titleLabel: world.titleLabel(gradeTitleId: toGrade, jobTitle: sub?.jobTitle ?? ""),
                                 managerId: draft.toManagerId,
                                 managerName: draft.toManagerId.map { world.orgPersonName($0) })
        var lines = draft.lines
        // [v25.591 轉組織 v1a-2] 會議〔交給…〕：新會議的 id、名稱定下來（沒改過名稱＝原本的拿掉人名）
        for i in lines.indices where lines[i].kind == OrgMoveLineKind.meeting.rawValue {
            let a = lines[i].lineAction
            guard a == .newSeries || a == .give else { continue }
            if a == .newSeries, lines[i].newId == nil { lines[i].newId = UUID() }
            if (lines[i].newTopic ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines[i].newTopic = newSeriesTopic(lines[i], world: world)
            }
        }
        if changes, draft.addToNewDeptManagers, let d = toDept {
            lines.append(OrgMoveLine(kind: OrgMoveLineKind.managerAdd.rawValue, refId: d,
                                     title: "\(world.deptShort(d)) 管理人員", action: OrgMoveAction.add.rawValue))
        }
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        // [v25.592 轉組織 v1b] 生效日在以後：照你選的〔現在就交接，11/1 才改部門〕／〔11/1 一起做〕；今天或以前一律 "now"。
        // state 先寫 applied，LifeStore.applyOrgMove 照 timing 改成 handed／planned。要退回這一件：timing 改回 "now"
        let timingRaw = effKey > dayKey(now) ? draft.timing.rawValue : OrgMoveTiming.now.rawValue
        return OrgMove(personId: draft.personId, personName: world.name(draft.personId),
                       kind: draft.kind.rawValue, effectiveKey: effKey,
                       handoverByKey: handoverByKey(effectiveKey: effKey), timing: timingRaw,
                       // [v25.593 轉組織 v2] 調出也可以〔照舊（只交接）〕（部門照舊、只是不歸你管了）。要退回這一件：改回 `draft.kind == .move`
                       from: fromSide, to: toSide, keepDept: (draft.kind.canChangeDept && draft.keepDept) ? true : nil,
                       note: note.isEmpty ? nil : note, state: OrgMoveState.applied.rawValue,
                       lines: lines, retitleBirthday: draft.retitleBirthday, createdAt: now, updatedAt: now)
    }

    /// 第 ③ 步的句子（judge §4.4；v1a 沒有「什麼時候做」那一區，寫「按下去就全部改好」）
    static func preview(_ draft: OrgMoveDraft, world: OrgMoveWorld, now: Date) -> OrgMovePreview {
        let move = makeMove(draft, world: world, now: now)
        let person = world.name(draft.personId)
        let lines = move.allLines
        var p = OrgMovePreview()
        let fromText = sideText(move.from, world: world)
        let toText = sideText(move.to, world: world)
        p.header = fromText == toText ? "\(person)　\(fromText)（部門照舊）" : "\(person)　\(fromText) → \(toText)"
        // [v25.593 轉組織 v2]「王小明　製造一課 P1 → 品保課（調出我的管轄）」「王小明　離職（製造一課 P1）」。要退回這一件：刪這一行
        if let h = leavingHeader(move, world: world) { p.header = h }
        p.dates = "\(dayText(move.effectiveKey))生效・交接完成日 \(dayText(move.handoverByKey))"
        let t = tally(lines)
        // 交給每一位
        let cut = cutKey(move, now: now)
        for r in t.byReceiver {
            var taskTitles: [String] = []
            var eqLines: [String] = []
            var reports = 0
            // [v25.591 轉組織 v1a-2] 會議、議程、班、兼任
            var agenda = 0
            var agendaUnassigned = 0
            var meetingLines: [String] = []
            var shiftTitles: [String] = []
            var shiftNotes: [String] = []
            var sides: [String] = []
            // [v25.592 轉組織 v1b] 你自己加的一項（「自己加的 2（門禁卡、鑰匙）」）
            var customs: [String] = []
            for l in lines where !l.isOrgLine {
                let res = resolved(l, in: lines)
                guard res.action == .give || res.action == .newSeries, res.toId == r.id else { continue }
                if l.isCustom {
                    if l.isLiveCustom { customs.append(l.title) }
                    continue
                }
                switch l.lineKind {
                case .some(.task), .some(.alarmTask):
                    if let note = overdueNote(l, in: lines, personName: person, world: world, now: now), !note.isEmpty {
                        taskTitles.append("\(l.title) 新截止 \(shortDay(l.newDueKey))")
                    } else {
                        taskTitles.append(l.title)
                    }
                case .some(.equipment):
                    let alarms = lines.filter { $0.kind == OrgMoveLineKind.alarmTask.rawValue && $0.parentId == l.refId }.count
                    eqLines.append(alarms > 0 ? "\(l.title)（含沒處理完的警報 \(alarms)）" : l.title)
                case .some(.report):
                    reports += 1
                case .some(.agenda):
                    agenda += 1
                    let item = l.holderId.flatMap { h in world.sub(h)?.meetings.first(where: { $0.id == l.parentId }) }?
                        .allItems.first(where: { $0.id == l.refId })
                    if item?.assigneeIds.isEmpty == true { agendaUnassigned += 1 }
                case .some(.meeting):
                    meetingLines.append(contentsOf: previewMeetingLines(l, world: world))
                case .some(.shifts):
                    shiftTitles.append(l.title)
                    shiftNotes.append(contentsOf: shiftOverwriteLines(l, personName: person, world: world, cutKey: cut))
                case .some(.sideRole):
                    sides.append(l.title)
                default:
                    break
                }
            }
            var body: [String] = []
            if !taskTitles.isEmpty { body.append("待辦 \(taskTitles.count)（\(taskTitles.joined(separator: "、"))）") }
            body.append(contentsOf: eqLines)
            body.append(contentsOf: meetingLines)
            var small: [String] = []
            if agenda > 0 {
                small.append(agenda == agendaUnassigned ? "議程 \(agenda)（沒指派負責人，會寫上\(r.name)）" : "議程 \(agenda)")
            }
            if reports > 0 { small.append("週報 \(reports)") }
            small.append(contentsOf: shiftTitles)
            if !small.isEmpty { body.append(small.joined(separator: "・")) }
            if !sides.isEmpty { body.append("兼任 \(sides.count)（\(sides.joined(separator: "、"))，連兼任負責人一起換）") }
            if !customs.isEmpty { body.append("自己加的 \(customs.count)（\(customs.joined(separator: "、"))）") }
            body.append(contentsOf: shiftNotes)
            p.blocks.append(OrgMovePreviewBlock(id: "to-" + r.id.uuidString, title: "交給 \(r.name) \(r.count) 項", lines: body))
        }
        // [v25.593 轉組織 v2]「交出去給 黃冠宇 2 項：…」「我先接 1 項：…」（OrgMoveOut.swift）。要退回這一件：刪這一行
        p.blocks.append(contentsOf: handOutPreviewBlocks(lines, person: person))
        let pendingNames = lines.filter { $0.lineAction == .pending }.map(\.title)
        if !pendingNames.isEmpty {
            p.blocks.append(OrgMovePreviewBlock(id: "pending", title: "待分派 \(pendingNames.count)：\(pendingNames.joined(separator: "、"))", lines: []))
        }
        let followParts = followSummary(lines)
        if t.follow > 0 {
            let detail = followParts.isEmpty ? "" : "：" + followParts.joined(separator: "、")
            p.blocks.append(OrgMovePreviewBlock(id: "follow", title: "跟著\(person) \(t.follow) 項\(detail)", lines: []))
        }
        let dropped = lines.filter { !$0.isOrgLine && $0.lineAction == .drop }.map(\.title)
        if !dropped.isEmpty {
            p.blocks.append(OrgMovePreviewBlock(id: "drop", title: "不要了 \(dropped.count) 項：\(dropped.joined(separator: "、"))", lines: []))
        }
        // [v25.591 轉組織 v1a-2] 會議〔最後一場〕：一場一段（之後的加開取消、排好的議程搬到最後一場）
        for l in lines where l.kind == OrgMoveLineKind.meeting.rawValue && l.lineAction == .end {
            guard let m = meeting(l, world: world) else { continue }
            let f = meetingFacts(m, cutKey: cut)
            p.blocks.append(OrgMovePreviewBlock(id: "end-" + l.id.uuidString,
                                                title: "\(l.title)：\(meetingEndLabel(f, cutKey: cut))",
                                                lines: meetingEndNotes(f, cutKey: cut)))
        }
        if t.undecided > 0 {
            p.blocks.append(OrgMovePreviewBlock(id: "undecided", title: "還沒決定 \(t.undecided) 項 → 先跟著\(person)", lines: []))
        }
        // ⚠ 交出去時已經逾期
        var lateTo: [String] = []
        var lateDue = ""
        for l in lines {
            guard overdueNote(l, in: lines, personName: person, world: world, now: now) != nil else { continue }
            let r = resolved(l, in: lines)
            if let n = r.toName, !lateTo.contains(n) { lateTo.append(n) }
            if lateDue.isEmpty { lateDue = shortDay(l.newDueKey) }
        }
        let lateCount = lines.filter { overdueNote($0, in: lines, personName: person, world: world, now: now) != nil }.count
        if lateCount > 0 {
            let whoText = lateTo.joined(separator: "、")
            let from = lateCount == 1 ? "從 \(lateDue) 算" : "從新的截止日算"
            p.overdueWarning = "⚠ \(lateCount) 件交出去時已經逾期：扣分留在\(person)，\(whoText)\(from)"
        }
        p.changes = changeLines(move, world: world, now: now)
        p.birthdayOffer = birthdayOffer(move, world: world)
        p.untouched = untouchedLines(personId: draft.personId, world: world)
        // [v25.591 轉組織 v1a-2] 會議、議程、班、兼任都在清單上交了：灰字「下一版才能在這裡交」不再出現
        p.deferred = nil
        // [v25.592 轉組織 v1b] 生效日在以後：「什麼時候做」兩顆、生日提醒那行小字、接手的人比這張先調走的提醒（OrgMoveDue.swift）。
        // 要退回這一件：刪這一行
        applyScheduleTexts(&p, draft: draft, move: move, world: world, now: now)
        return p
    }

    /// [v25.591 轉組織 v1a-2] 確認頁「交給 陳怡君」裡會議那幾行：「週會・每週二 14:00（11/3 起）」
    /// 「新會議名稱：週會（這個名稱會出現在通知與手錶上，建議不要放人名）」「11/3 以後排好的場次與議程一起搬到新會議」
    static func previewMeetingLines(_ l: OrgMoveLine, world: OrgMoveWorld) -> [String] {
        guard let m = meeting(l, world: world) else { return [] }
        let cut = l.dueKey ?? dayKey(Date())
        let f = meetingFacts(m, cutKey: cut)
        let topic = newSeriesTopic(l, world: world)
        var out: [String] = []
        if l.lineAction == .newSeries {
            let start = f.firstRuleDate.map { "（\(shortDay(dayKey($0))) 起）" } ?? ""
            out.append("會議 \(topic)・\(f.schedule)\(start)")
        } else {
            out.append("會議 \(topic)・\(f.schedule)")
        }
        out.append("新會議名稱：\(topic)（這個名稱會出現在通知與手錶上，建議不要放人名）")
        if l.lineAction == .newSeries, let start = f.firstRuleDate, !(f.futureWithItems.isEmpty && f.futureEmpty.isEmpty) {
            out.append("\(shortDay(dayKey(start))) 以後排好的場次與議程一起搬到新會議")
        }
        return out
    }

    /// 「缺失 1、兼任 1、週報 1」（跟著那一項的內容；缺失只寫件數）
    private static func followSummary(_ lines: [OrgMoveLine]) -> [String] {
        var derel = 0, side = 0, tasks = 0, reports = 0, machines = 0
        var oneOnOne = 0, meetings = 0, agenda = 0, shifts = 0
        var customs = 0
        for l in lines where !l.isOrgLine {
            let a = resolved(l, in: lines).action
            guard a == .follow || a == .closeNow else { continue }
            if l.isCustom {
                customs += 1   // [v25.592 轉組織 v1b] 你自己加的一項〔跟著〕
                continue
            }
            switch l.lineKind {
            case .some(.task):
                if l.lineLock == .dereliction { derel += 1 } else { tasks += 1 }
            case .some(.alarmTask): tasks += 1
            case .some(.sideRole): side += 1
            case .some(.report): reports += 1
            case .some(.equipment): machines += 1
            case .some(.meeting):
                if SubExportComposer.isOneOnOneName(l.title) { oneOnOne += 1 } else { meetings += 1 }
            case .some(.agenda): agenda += 1
            case .some(.shifts): shifts += 1
            default: break
            }
        }
        var out: [String] = []
        if derel > 0 { out.append("缺失 \(derel)") }
        if side > 0 { out.append("兼任 \(side)") }
        if tasks > 0 { out.append("待辦 \(tasks)") }
        if machines > 0 { out.append("機台 \(machines)") }
        if oneOnOne > 0 { out.append(oneOnOne == 1 ? "1on1" : "1on1 \(oneOnOne)") }
        if meetings > 0 { out.append("會議 \(meetings)") }
        if agenda > 0 { out.append("議程 \(agenda)") }
        if reports > 0 { out.append("週報 \(reports)") }
        if shifts > 0 { out.append("以後的班") }
        if customs > 0 { out.append("自己加的 \(customs)") }
        return out
    }

    /// 「會一起改」那幾行
    static func changeLines(_ move: OrgMove, world: OrgMoveWorld, now: Date) -> [String] {
        var out: [String] = []
        let person = move.personName.isEmpty ? "這位同仁" : move.personName
        // [v25.593 轉組織 v2] 調出也改部門（changesDept）。要退回這一件：改回 `move.to.deptId != move.from.deptId && move.keepDept != true && move.kind == OrgMoveKind.move.rawValue`
        let deptChanged = move.changesDept
        let plantChanged = (move.to.plant ?? "") != (move.from.plant ?? "")
        let fromDept = sideText(OrgMoveSide(deptId: move.from.deptId, deptLabel: move.from.deptLabel), world: world)
        let toDept = sideText(OrgMoveSide(deptId: move.to.deptId, deptLabel: move.to.deptLabel), world: world)
        if deptChanged && plantChanged {
            out.append("部門、廠區、名片、組織圖：\(fromDept) → \(toDept)（\(move.to.plant ?? "")）")
        } else if deptChanged {
            out.append("部門、名片、組織圖：\(fromDept) → \(toDept)")
        } else if plantChanged {
            out.append("廠區：\(move.from.plant ?? "") → \(move.to.plant ?? "")")
        }
        if move.to.gradeTitleId != move.from.gradeTitleId {
            out.append("職稱：\(move.from.titleLabel ?? "") → \(move.to.titleLabel ?? "")（不會記成升職）")
        }
        for l in move.allLines where l.isOrgLine {
            let d = world.deptShort(l.refId)
            switch l.lineAction {
            case .some(.remove): out.append("\(d)管理人員：拿掉\(person)")
            case .some(.replace): out.append("\(d)管理人員：\(person)換成\(l.toName ?? "")")
            case .some(.add): out.append("\(d)管理人員：加上\(person)")
            default: break
            }
        }
        if let m = move.to.managerName, !m.isEmpty {
            out.append("新主管：\(m)（只記在交接單上）")
        }
        if world.remindersOn {
            var moved = 0, deleted = 0, checked = 0
            let lines = move.allLines
            let holder = world.sub(move.personId)
            for l in lines where l.kind == OrgMoveLineKind.task.rawValue || l.kind == OrgMoveLineKind.alarmTask.rawValue
                || (l.kind == OrgMoveLineKind.sideRole.rawValue && l.meetingId == nil) {
                let tid: UUID? = l.kind == OrgMoveLineKind.sideRole.rawValue ? l.itemId : l.refId
                guard let t = holder?.tasks.first(where: { $0.id == tid }), t.reminderId != nil else { continue }
                switch resolved(l, in: lines).action {
                case .some(.give): moved += 1
                case .some(.drop): deleted += 1
                case .some(.closeNow): checked += 1
                default: break
                }
            }
            var parts: [String] = []
            if moved > 0 { parts.append("\(moved) 件改成接手的人") }
            if deleted > 0 { parts.append("刪掉 \(deleted) 件") }
            if checked > 0 { parts.append("打勾 \(checked) 件") }
            if !parts.isEmpty { out.append("Apple 提醒事項 " + parts.joined(separator: "、")) }
        }
        // [v25.593 轉組織 v2] 調出、離職、退休：「11/1 起收進部屬名單最下面「已轉出」…」「組織圖：王小明標成已離職」、今年的互評不排（OrgMoveOut.swift）。
        // 要退回這一件：刪 if 這三行，留下 else 那一行
        if move.isLeaving {
            out.append(contentsOf: leavingChangeLines(move, world: world, now: now))
        } else {
            out.append(contentsOf: ballotLines(move, world: world, now: now))
        }
        return out
    }

    /// 今年還沒送出的互評票（judge §4.4；換了課或職等才出現；已經送出的不會動，所以不寫）
    static func ballotLines(_ move: OrgMove, world: OrgMoveWorld, now: Date) -> [String] {
        let deptChanged = move.to.deptId != move.from.deptId
        let gradeChanged = move.to.gradeTitleId != move.from.gradeTitleId
        guard deptChanged || gradeChanged else { return [] }
        // 互評票的 year 是 PerformanceReviewView／LifeStore 用 Calendar.current 記的（民國曆的手機是 115）：這裡要跟它一樣
        let year = Calendar.current.component(.year, from: now)
        let person = move.personName.isEmpty ? "這位同仁" : move.personName
        let open = world.ballots.filter { $0.year == year && !$0.isSubmitted }
        var out: [String] = []
        let dept = world.deptShort(move.to.deptId)
        let grade = world.gradeTitles.first(where: { $0.id == move.to.gradeTitleId })?.displayLabel ?? ""
        let group = [dept, grade].filter { !$0.isEmpty }.joined(separator: " ")
        if let mine = open.first(where: { $0.raterId == PerformanceBallot.selfRaterId }),
           mine.groups.contains(where: { g in g.entries.contains { $0.id == move.personId } }) {
            out.append("今年還沒送出的互評票：你那張的\(person)改排到\(group)那組最後（已排的順序要重排）")
        }
        if deptChanged, let own = open.first(where: { $0.raterId == move.personId }), own.rankedCount > 0 {
            out.append("\(person)那張會改排\(dept)的同仁（已排的順序清掉）")
        }
        if deptChanged {
            let others = open.filter { b in
                b.raterId != PerformanceBallot.selfRaterId && b.raterId != move.personId
                    && b.groups.contains(where: { g in g.entries.contains { $0.id == move.personId } })
            }
            if !others.isEmpty {
                out.append("另外 \(others.count) 張還沒送出的票會拿掉\(person)（不同課了）")
            }
        }
        return out
    }

    /// ☑ 順便更新生日提醒：部屬或組織人員有生日提醒、而且部門或職稱有換
    static func birthdayOffer(_ move: OrgMove, world: OrgMoveWorld) -> Bool {
        let changed = (move.to.deptId != move.from.deptId) || (move.to.gradeTitleId != move.from.gradeTitleId)
        guard changed else { return false }
        if world.sub(move.personId)?.birthdayEventId != nil { return true }
        return world.orgPerson(linkedTo: move.personId)?.birthdayEventId != nil
    }

    /// 「不會動」：已完成的任務、交過的週報、以前的會議、紀錄與分數
    static func untouchedLines(personId: UUID, world: OrgMoveWorld) -> [String] {
        guard let sub = world.sub(personId) else { return [] }
        let doneTasks = sub.tasks.filter { $0.isCompleted }.count
        let doneReports = sub.weeklyReports.filter { $0.isCompleted }.count
        var parts: [String] = []
        if doneTasks > 0 { parts.append("已完成的任務 \(doneTasks) 件") }
        if doneReports > 0 { parts.append("交過的週報 \(doneReports) 份") }
        parts.append("以前的會議、紀錄與分數")
        return [parts.joined(separator: "、")]
    }

    // MARK: 交接單頁（套用之後；狀態照現在的資料算）

    /// 這一列交給誰。套用之後每一列自己記著接手的人（toId）：跟著機台的在套用、待分派分好時寫上；
    /// 還沒套用（精靈的草稿）跟著機台的照那台機台的決定算
    static func receiver(_ line: OrgMoveLine, in move: OrgMove) -> (id: UUID?, name: String?) {
        switch line.lineAction {
        case .some(.give), .some(.newSeries):
            return (line.toId, line.toName)
        case .some(.withEquipment):
            if let to = line.toId { return (to, line.toName) }
            let r = resolved(line, in: move.allLines)
            if r.action == .give { return (r.toId, r.toName) }
            return (nil, nil)
        case .some(.pending):
            if line.state == OrgMoveLineState.resolved.rawValue, let to = line.toId { return (to, line.toName) }
            return (nil, nil)
        default:
            return (nil, nil)
        }
    }

    /// 套用之後的件數（歷程那一列「交出去 5・跟著 2」）：交出去＝有接手的人（含待分派後來分好的）；跟著＝跟著、還沒決定、現在結案
    static func handedCounts(_ move: OrgMove) -> (given: Int, follow: Int) {
        var g = 0
        var f = 0
        for l in move.allLines where !l.isOrgLine && l.lineKind != nil {
            // [v25.593 轉組織 v2]〔交出去〕（給不在部屬名單的人、給我）也算交出去。要退回這一件：拿掉 `|| l.lineAction == .handOut`
            if receiver(l, in: move).id != nil || l.lineAction == .handOut {
                g += 1
                continue
            }
            let a = resolved(l, in: move.allLines).action
            if a == nil || a == .follow || a == .closeNow { f += 1 }
        }
        return (g, f)
    }

    /// 任務、週報預覽多一行（judge §4.6）：「11/2 交接自 王小明（原訂 10/20）・備註：廠商窗口在名片夾『科達』…」
    static func receivedPreviewLine(_ r: OrgMoveIndex.Received) -> String {
        var s = "\(shortDay(dayKey(r.handedAt))) 交接自 \(r.fromName)"
        if r.wasOverdue, let k = r.dueKey { s += "（原訂 \(shortDay(k))）" }
        if !r.memo.isEmpty { s += "・備註：\(r.memo)" }
        return s
    }

    /// 還沒分好的待分派那幾列（照單上的狀態；畫面再對一次機台現在的負責人）
    static func pendingLineIds(_ move: OrgMove) -> [UUID] {
        move.allLines.filter {
            $0.kind == OrgMoveLineKind.equipment.rawValue && $0.action == OrgMoveAction.pending.rawValue
                && $0.state == OrgMoveLineState.done.rawValue
        }.map(\.id)
    }

    /// 交接單頁一列的狀態。整張已經復原的：只顯示、不給按（⚠ 又回到原人身上＝本來就該回去）
    static func status(_ line: OrgMoveLine, in move: OrgMove, map: OrgMoveHolderMap, now: Date) -> OrgMoveLineStatus {
        var s = rawStatus(line, in: move, map: map, now: now)
        guard move.isUndone else { return s }
        if s.kind == .backOnPerson {
            let person = move.personName.isEmpty ? "這位同仁" : move.personName
            s = OrgMoveLineStatus(kind: .undone, mark: "・", text: "已回到\(person)身上", holderId: move.personId, fix: nil, fixLabel: nil)
        }
        s.fix = nil
        s.fixLabel = nil
        return s
    }

    private static func rawStatus(_ line: OrgMoveLine, in move: OrgMove, map: OrgMoveHolderMap, now: Date) -> OrgMoveLineStatus {
        let person = move.personName.isEmpty ? "這位同仁" : move.personName
        let todayKey = dayKey(now)
        if line.state == OrgMoveLineState.undone.rawValue {
            return OrgMoveLineStatus(kind: .undone, mark: "・", text: "已復原", holderId: nil, fix: nil, fixLabel: nil)
        }
        if line.state == OrgMoveLineState.skipped.rawValue {
            return OrgMoveLineStatus(kind: .skipped, mark: "・", text: "交接時已經做完或找不到", holderId: nil, fix: nil, fixLabel: nil)
        }
        if line.isOrgLine {
            return OrgMoveLineStatus(kind: .org, mark: "・", text: line.title, holderId: nil, fix: nil, fixLabel: nil)
        }
        // [v25.592 轉組織 v1b] 你自己加的一項（只記在單上：已交／還沒交）；排好了、什麼都還沒做的單（「排好了：11/1 交給 陳怡君」）。
        // 要退回這一件：刪這兩個 if
        if line.isCustom { return customStatus(line, move: move) }
        if move.isPlanned { return plannedStatus(line, move: move) }
        // [v25.593 轉組織 v2]〔交出去〕：→ 交出去給 黃冠宇／我接的（○ 還沒收掉、✓ 收掉了）（OrgMoveOut.swift）。要退回這一件：刪這一行
        if line.lineAction == .handOut { return handOutStatus(line, move: move) }
        // [v25.591 轉組織 v1a-2] 會議、議程、班、兼任（v1a-1 存的鎖著的兼任列照舊走下面）
        if line.lineLock != .sideRole, let more = moreStatus(line, in: move, map: map, now: now) {
            return more
        }
        let r = resolved(line, in: move.allLines)
        let rec = receiver(line, in: move)
        switch line.lineKind {
        case .some(.equipment):
            return equipmentStatus(line, move: move, map: map, person: person)
        case .some(.task), .some(.alarmTask), .some(.sideRole), .some(.report):
            let isReport = line.kind == OrgMoveLineKind.report.rawValue
            let itemId = line.kind == OrgMoveLineKind.sideRole.rawValue ? line.itemId : line.refId
            if r.action == .drop {
                let fix: OrgMoveLineStatus.Fix? = line.removedJSON != nil ? .putBack : nil
                return OrgMoveLineStatus(kind: .dropped, mark: "・", text: "不要了",
                                         holderId: nil, fix: fix, fixLabel: fix == nil ? nil : "放回\(person)")
            }
            if r.action == .closeNow {
                return OrgMoveLineStatus(kind: .closed, mark: "✓", text: "已結案（−1 算\(person)）",
                                         holderId: move.personId, fix: nil, fixLabel: nil)
            }
            guard let target = rec.id else {
                let pendingNote = r.action == .pending ? "（跟著機台，待分派）" : ""
                return OrgMoveLineStatus(kind: .follow, mark: "・", text: "跟著\(person)" + pendingNote,
                                         holderId: move.personId, fix: nil, fixLabel: nil)
            }
            let holders: [UUID]
            var done = false
            var doneAt: Date?
            var due: Date?
            if isReport {
                let copies = map.reports[itemId ?? UUID()] ?? []
                holders = copies.map(\.holder)
                if let c = copies.first(where: { $0.holder == target }) ?? copies.first {
                    done = c.report.isCompleted
                    doneAt = c.report.completedAt
                    due = c.report.date
                }
            } else {
                let copies = map.tasks[itemId ?? UUID()] ?? []
                holders = copies.map(\.holder)
                if let c = copies.first(where: { $0.holder == target }) ?? copies.first {
                    done = c.task.isCompleted
                    doneAt = c.task.completedAt
                    due = c.task.dueDate
                }
            }
            if holders.isEmpty {
                return OrgMoveLineStatus(kind: .missing, mark: "・", text: "找不到了（可能被刪了）", holderId: nil, fix: nil, fixLabel: nil)
            }
            let onTarget = holders.contains(target)
            let onPerson = holders.contains(move.personId) && target != move.personId
            let targetName = rec.name ?? map.name(target)
            if onTarget && onPerson {
                return OrgMoveLineStatus(kind: .onBoth, mark: "⚠", text: "這項同時在\(person)和\(targetName)身上",
                                         holderId: target, fix: .keepReceiver, fixLabel: "留\(targetName)那份")
            }
            if onTarget {
                if done {
                    let at = doneAt.map { shortDay(dayKey($0)) + " 做完" } ?? "做完了"
                    return OrgMoveLineStatus(kind: .done, mark: "✓", text: at, holderId: target, fix: nil, fixLabel: nil)
                }
                var text = due.map { "截止 " + shortDay(dayKey($0)) } ?? "沒有截止日"
                if let d = due, d < now, let a = date(fromKey: dayKey(d)), let b = date(fromKey: todayKey) {
                    let days = calendar.dateComponents([.day], from: a, to: b).day ?? 0
                    text += days > 0 ? "・已逾期 \(days) 天" : "・已逾期"
                }
                if line.wasOverdue == true { text += "・交接時已逾期" }
                return OrgMoveLineStatus(kind: .open, mark: "○", text: text, holderId: target, fix: nil, fixLabel: nil)
            }
            if onPerson {
                if done {
                    return OrgMoveLineStatus(kind: .done, mark: "✓", text: "\(person)做完了", holderId: move.personId, fix: nil, fixLabel: nil)
                }
                return OrgMoveLineStatus(kind: .backOnPerson, mark: "⚠",
                                         text: "這項又回到\(person)身上（可能是還沒更新的 iPad 存回來的）",
                                         holderId: move.personId, fix: .redo, fixLabel: "再交一次")
            }
            let now0 = holders[0]
            if done {
                return OrgMoveLineStatus(kind: .done, mark: "✓", text: "\(map.name(now0))做完了", holderId: now0, fix: nil, fixLabel: nil)
            }
            return OrgMoveLineStatus(kind: .elsewhere, mark: "・", text: "現在在 \(map.name(now0)) 身上",
                                     holderId: now0, fix: nil, fixLabel: nil)
        case .some(.manager), .some(.managerAdd), .some(.meeting), .some(.agenda), .some(.shifts), .none:
            return OrgMoveLineStatus(kind: .org, mark: "・", text: line.title, holderId: nil, fix: nil, fixLabel: nil)
        }
    }

    private static func equipmentStatus(_ line: OrgMoveLine, move: OrgMove, map: OrgMoveHolderMap,
                                        person: String) -> OrgMoveLineStatus {
        guard let eid = line.refId, map.equipmentIds.contains(eid) else {
            return OrgMoveLineStatus(kind: .missing, mark: "・", text: "找不到這台了（可能被刪了）", holderId: nil, fix: nil, fixLabel: nil)
        }
        let owner = map.owners[eid]
        switch line.lineAction {
        case .some(.pending):
            if line.state == OrgMoveLineState.resolved.rawValue {
                let to = line.toId
                if owner == to {
                    let at = line.resolvedAt.map { shortDay(dayKey($0)) + " " } ?? ""
                    return OrgMoveLineStatus(kind: .handed, mark: "●", text: "負責人（\(at)從待分派分過來）",
                                             holderId: to, fix: nil, fixLabel: nil)
                }
                return ownerElsewhere(line, owner: owner, map: map, person: person, move: move)
            }
            if owner == move.personId {
                return OrgMoveLineStatus(kind: .pending, mark: "◌", text: "待分派", holderId: move.personId,
                                         fix: .resolve, fixLabel: "分給…")
            }
            if let o = owner {
                return OrgMoveLineStatus(kind: .pendingElsewhere, mark: "●", text: "已在別處換成 \(map.name(o))",
                                         holderId: o, fix: nil, fixLabel: nil)
            }
            return OrgMoveLineStatus(kind: .pendingElsewhere, mark: "・", text: "現在沒有負責人", holderId: nil, fix: nil, fixLabel: nil)
        case .some(.give):
            if owner == line.toId {
                return OrgMoveLineStatus(kind: .handed, mark: "●", text: "負責人", holderId: owner, fix: nil, fixLabel: nil)
            }
            if owner == move.personId {
                return OrgMoveLineStatus(kind: .backOnPerson, mark: "⚠",
                                         text: "這台又回到\(person)名下（可能是還沒更新的 iPad 存回來的）",
                                         holderId: move.personId, fix: .redo, fixLabel: "再交一次")
            }
            return ownerElsewhere(line, owner: owner, map: map, person: person, move: move)
        default:
            return OrgMoveLineStatus(kind: .follow, mark: "・", text: "跟著\(person)", holderId: owner, fix: nil, fixLabel: nil)
        }
    }

    private static func ownerElsewhere(_ line: OrgMoveLine, owner: UUID?, map: OrgMoveHolderMap,
                                       person: String, move: OrgMove) -> OrgMoveLineStatus {
        guard let o = owner else {
            return OrgMoveLineStatus(kind: .elsewhere, mark: "・", text: "現在沒有負責人", holderId: nil, fix: nil, fixLabel: nil)
        }
        return OrgMoveLineStatus(kind: .elsewhere, mark: "・", text: "現在是 \(map.name(o)) 負責", holderId: o, fix: nil, fixLabel: nil)
    }

    /// 「組織」那一列：部屬的部門、廠區、職稱，組織人員的部門，名片的部門，管理人員，照現在的資料跟單上的「到」比（judge §4.5）
    /// [v25.592 轉組織 v1b] 多 now（部門還沒改的那張到了沒、卡住了沒）；呼叫端不給＝現在
    static func orgStatus(_ move: OrgMove, world: OrgMoveWorld, now: Date = Date()) -> (ok: Bool, text: String) {
        let person = move.personName.isEmpty ? "這位同仁" : move.personName
        guard let sub = world.sub(move.personId) else { return (true, "找不到\(person)了") }
        // [v25.593 轉組織 v2] 調出也改部門（changesDept）。要退回這一件：改回 `move.kind == OrgMoveKind.move.rawValue && move.keepDept != true && move.to.deptId != move.from.deptId`
        let deptChanged = move.changesDept
        let plantChanged = (move.to.plant ?? "") != (move.from.plant ?? "")
        let gradeChanged = move.to.gradeTitleId != move.from.gradeTitleId
        let toDept = sideText(OrgMoveSide(deptId: move.to.deptId, deptLabel: move.to.deptLabel), world: world)
        let fromDept = sideText(OrgMoveSide(deptId: move.from.deptId, deptLabel: move.from.deptLabel), world: world)
        let op = world.orgPerson(linkedTo: move.personId)
        // [v25.592 轉組織 v1b 裁定] 用 undoneByCancel（〔留給接手的人〕之後再〔復原〕寫「已復原」）。要退回這一件：改回 `move.cancelledAt != nil`
        if move.isUndone { return (true, move.undoneByCancel ? "已取消" : "已復原") }
        // [v25.592 轉組織 v1b] 部門還沒改（排好的、交出去了還沒到生效日的）：「11/1 才改：設備課・P2」；到了卻卡住的寫為什麼；
        // 取消了調動、只做交接的寫那一句（cancelNote）。要退回這一件：刪這兩個 if
        if move.orgPending { return pendingOrgStatus(move, world: world, now: now) }
        if move.keepDept == true, let n = move.cancelNote, !n.isEmpty { return (true, "✓ 部門照舊・" + n) }
        if deptChanged {
            let subOK = sub.departmentId == move.to.deptId
            let orgOK = op.map { $0.departmentId == move.to.deptId } ?? true
            if !subOK {
                let back = sub.departmentId == move.from.deptId ? fromDept : (world.deptShort(sub.departmentId).isEmpty ? "別的部門" : world.deptShort(sub.departmentId))
                let note = orgOK ? "（組織圖是\(toDept)）" : ""
                return (false, "⚠ \(person)的部門又回到\(back)\(note)")
            }
            if !orgOK {
                return (false, "⚠ 組織圖上\(person)又回到\(fromDept)（部屬卡片是\(toDept)）")
            }
            if let b = move.before, let cid = b.cardId,
               let card = world.businessCards.first(where: { $0.id == cid }) {
                let cur = card.department.trimmingCharacters(in: .whitespaces)
                let label = world.deptLabel(move.to.deptId)
                let auto = Set(["", b.cardDept ?? "", b.deptText ?? "", move.from.deptLabel ?? "", fromDept])
                let wasAuto = auto.contains((b.cardDept ?? "").trimmingCharacters(in: .whitespaces))
                if wasAuto && cur != label && !label.isEmpty && cur == (b.cardDept ?? "").trimmingCharacters(in: .whitespaces) {
                    return (false, "⚠ \(person)的名片部門又回到\(fromDept)")
                }
            }
        }
        if plantChanged && sub.plantArea != (move.to.plant ?? "") {
            return (false, "⚠ \(person)的廠區又回到 \(sub.plantArea.isEmpty ? "未分廠區" : sub.plantArea)")
        }
        if gradeChanged && sub.gradeTitleId != move.to.gradeTitleId {
            return (false, "⚠ \(person)的職稱又回到 \(world.titleLabel(gradeTitleId: sub.gradeTitleId, jobTitle: sub.jobTitle))")
        }
        if let opId = op?.id {
            for l in move.allLines where l.isOrgLine && l.state != OrgMoveLineState.undone.rawValue {
                guard let d = world.dept(l.refId) else { continue }
                let has = d.managerIds.contains(opId)
                switch l.lineAction {
                case .some(.remove), .some(.replace):
                    if has { return (false, "⚠ \(world.deptShort(d.id))管理人員裡又有\(person)") }
                case .some(.add):
                    if !has { return (false, "⚠ \(world.deptShort(d.id))管理人員裡沒有\(person)") }
                default:
                    break
                }
            }
        }
        // [v25.593 轉組織 v2] 回到我的部屬、調出、離職、退休：組織人員已離職那一格、「✓ 已轉出・品保課」（OrgMoveOut.swift）。
        // 要退回這一件：刪這一行
        if let r = leavingOrgStatus(move, world: world, deptChanged: deptChanged, toDept: toDept) { return r }
        var what: [String] = []
        if deptChanged { what.append(toDept) }
        if plantChanged, let p = move.to.plant, !p.isEmpty { what.append(p) }
        if gradeChanged, let t = move.to.titleLabel, !t.isEmpty { what.append(t) }
        if what.isEmpty { return (true, "✓ 部門照舊") }
        let tail = deptChanged ? "（部門、組織圖、名片都對）" : ""
        return (true, "✓ " + what.joined(separator: "・") + tail)
    }

    /// 交接單頁的分組：交給每一位（照清單順序）→ 待分派 → 跟著（收起來）→ 不要了 → 組織
    static func sheetGroups(_ move: OrgMove) -> [OrgMoveSheetGroup] {
        let person = move.personName.isEmpty ? "這位同仁" : move.personName
        let lines = move.allLines.filter { !$0.isOrgLine && $0.lineKind != nil }
        var order: [UUID] = []
        var names: [UUID: String] = [:]
        var byTo: [UUID: [UUID]] = [:]
        var pending: [UUID] = []
        var follow: [UUID] = []
        var dropped: [UUID] = []
        var ended: [UUID] = []
        // [v25.593 轉組織 v2]〔交出去〕給不在部屬名單的人（一位一組）、給我（「我接的」）
        var outOrder: [UUID] = []
        var outNames: [UUID: String] = [:]
        var outBy: [UUID: [UUID]] = [:]
        var mine: [UUID] = []
        for l in lines {
            let rec = receiver(l, in: move)
            let a = resolved(l, in: move.allLines).action
            if a == .handOut, let t = handOutTarget(l) {
                if t.isMe {
                    mine.append(l.id)
                } else {
                    if outBy[t.id] == nil { outOrder.append(t.id) }
                    outBy[t.id, default: []].append(l.id)
                    outNames[t.id] = t.name
                }
            } else if let to = rec.id {
                if byTo[to] == nil { order.append(to) }
                byTo[to, default: []].append(l.id)
                names[to] = rec.name ?? ""
            } else if a == .pending {
                pending.append(l.id)
            } else if a == .drop {
                dropped.append(l.id)
            } else if a == .end {
                ended.append(l.id)
            } else {
                follow.append(l.id)
            }
        }
        var out: [OrgMoveSheetGroup] = []
        for to in order {
            let ids = byTo[to] ?? []
            out.append(OrgMoveSheetGroup(id: "to-" + to.uuidString, title: "\(names[to] ?? "")（\(ids.count)）", lineIds: ids, collapsed: false))
        }
        // [v25.593 轉組織 v2]「交出去給 黃冠宇（2）」「我接的（1）」接在交給每一位後面。要退回這一件：刪這兩段
        for to in outOrder {
            let ids = outBy[to] ?? []
            out.append(OrgMoveSheetGroup(id: "out-" + to.uuidString, title: "交出去給 \(outNames[to] ?? "")（\(ids.count)）",
                                         lineIds: ids, collapsed: false))
        }
        if !mine.isEmpty { out.append(OrgMoveSheetGroup(id: "mine", title: "我接的（\(mine.count)）", lineIds: mine, collapsed: false)) }
        if !pending.isEmpty { out.append(OrgMoveSheetGroup(id: "pending", title: "待分派（\(pending.count)）", lineIds: pending, collapsed: false)) }
        if !follow.isEmpty { out.append(OrgMoveSheetGroup(id: "follow", title: "跟著\(person)（\(follow.count)）", lineIds: follow, collapsed: true)) }
        if !dropped.isEmpty { out.append(OrgMoveSheetGroup(id: "drop", title: "不要了（\(dropped.count)）", lineIds: dropped, collapsed: true)) }
        if !ended.isEmpty { out.append(OrgMoveSheetGroup(id: "end", title: "結束的會議（\(ended.count)）", lineIds: ended, collapsed: false)) }
        // [v25.592 轉組織 v1b]「自己加的（2）」：門禁卡、鑰匙…（只記在單上、可以勾已交）。要退回這一件：刪這兩行
        let custom = move.allLines.filter(\.isLiveCustom)
        if !custom.isEmpty { out.append(OrgMoveSheetGroup(id: "custom", title: "自己加的（\(custom.count)）", lineIds: custom.map(\.id), collapsed: false)) }
        let org = move.allLines.filter { $0.isOrgLine }
        if !org.isEmpty { out.append(OrgMoveSheetGroup(id: "org", title: "組織", lineIds: org.map(\.id), collapsed: false)) }
        return out
    }

    /// 組織那幾列的字（「組織：製造一課管理人員 拿掉王小明」）
    static func orgLineText(_ line: OrgMoveLine, move: OrgMove, world: OrgMoveWorld) -> String {
        let person = move.personName.isEmpty ? "這位同仁" : move.personName
        let d = world.deptShort(line.refId).isEmpty ? line.title.replacingOccurrences(of: " 管理人員", with: "") : world.deptShort(line.refId)
        switch line.lineAction {
        case .some(.remove): return "組織：\(d)管理人員 拿掉\(person)"
        case .some(.replace): return "組織：\(d)管理人員 \(person)換成\(line.toName ?? "")"
        case .some(.add): return "組織：\(d)管理人員 加上\(person)"
        case .some(.keep): return "組織：\(d)管理人員 照舊"
        default: return "組織：\(d)管理人員"
        }
    }

    /// 四格（judge §4.5）：交出去／做完／待分派／跟著
    static func tiles(_ move: OrgMove, map: OrgMoveHolderMap, world: OrgMoveWorld, now: Date) -> [OrgMoveTile] {
        var given = 0, toDo = 0, done = 0
        var pendingNames: [String] = []
        var follow = 0
        var derel = 0, side = 0
        for l in move.allLines where !l.isOrgLine && l.lineKind != nil {
            if l.state == OrgMoveLineState.undone.rawValue { continue }
            let rec = receiver(l, in: move)
            let a = resolved(l, in: move.allLines).action
            // [v25.593 轉組織 v2]〔交出去〕算交出去、不算要做的（不在任何部屬身上）。要退回這一件：刪這個 if
            if a == .handOut {
                given += 1
                continue
            }
            if rec.id != nil {
                given += 1
                // [v25.591 轉組織 v1a-2] 會議、班跟機台一樣「交了就好」（●），不算要做的
                let handOnly = l.kind == OrgMoveLineKind.equipment.rawValue || l.kind == OrgMoveLineKind.meeting.rawValue
                    || l.kind == OrgMoveLineKind.shifts.rawValue
                if !handOnly {
                    toDo += 1
                    if status(l, in: move, map: map, now: now).kind == .done { done += 1 }
                }
            } else if a == .pending && l.kind == OrgMoveLineKind.equipment.rawValue {
                let s = status(l, in: move, map: map, now: now)
                if s.kind == .pending { pendingNames.append(l.title) }
            } else if a == .drop || a == .end {
                continue
            } else if a != .pending {
                follow += 1
                if l.lineLock == .dereliction { derel += 1 }
                if l.kind == OrgMoveLineKind.sideRole.rawValue { side += 1 }
            }
        }
        var followSub: [String] = []
        if derel > 0 { followSub.append("缺失 \(derel)") }
        if side > 0 { followSub.append("兼任 \(side)") }
        let rest = follow - derel - side
        if rest > 0 { followSub.append("其他 \(rest)") }
        return [
            OrgMoveTile(id: "given", label: "交出去", value: "\(given)", sub: "要做的 \(toDo) 件"),
            OrgMoveTile(id: "done", label: "做完", value: "\(done)", sub: "還有 \(max(0, toDo - done)) 件"),
            OrgMoveTile(id: "pending", label: "待分派", value: "\(pendingNames.count)",
                        sub: pendingNames.isEmpty ? "—" : pendingNames.joined(separator: "、")),
            OrgMoveTile(id: "follow", label: "跟著", value: "\(follow)",
                        sub: followSub.isEmpty ? "—" : followSub.joined(separator: "・"))
        ]
    }

    /// 交接單頁最上面兩行（「王小明　製造一課 P1 → 設備課 P2」「11/1（日）生效・11/2 交接・交接完成日 11/11」）
    static func sheetHeader(_ move: OrgMove, world: OrgMoveWorld) -> (title: String, dates: String) {
        let person = move.personName.isEmpty ? "這位同仁" : move.personName
        let f = sideText(move.from, world: world)
        let t = sideText(move.to, world: world)
        var title = f == t ? "\(person)　\(f)（部門照舊）" : "\(person)　\(f) → \(t)"
        // [v25.593 轉組織 v2] 調出、離職、退休、回到我的部屬的單頭（「王小明　製造一課 P1 → 品保課 P1（調出我的管轄）」
        // 「林志豪　離職（製造一課 P1）」「王小明　回到我的部屬（品保課 P1）」）。要退回這一件：刪這兩行、title 改回 let
        if let h = leavingHeader(move, world: world) { title = h }
        else if move.isBack { title = f.isEmpty ? "\(person)　回到我的部屬" : "\(person)　回到我的部屬（\(f)）" }
        var dates = "\(dayText(move.effectiveKey))生效"
        // [v25.592 轉組織 v1b] 排好的「（排好了）」；交出去了、部門還沒改的「・10/28 交接・11/1 才改部門」；
        // 生效那天才改部門的「・11/2 08:10 改的部門」（judge §7 v1b 做好標準 2）。要退回這一件：刪 scheduleHeaderParts 那一段
        if move.isPlanned { dates += "（排好了）" }
        if let h = move.handedAt ?? move.appliedAt { dates += "・\(shortDay(dayKey(h))) 交接" }
        dates += scheduleHeaderParts(move)
        dates += "・交接完成日 \(shortDay(move.handoverByKey))"
        if move.isUndone, let u = move.undoneAt {
            // [v25.592 轉組織 v1b 裁定] 用 undoneByCancel。要退回這一件：改回 `move.cancelledAt != nil`
            dates += move.undoneByCancel ? "・\(shortDay(dayKey(u))) 取消了" : "・\(shortDay(dayKey(u))) 已復原"
        }
        return (title, dates)
    }

    // MARK: 卡片：提示列、歷程、接手那一區

    /// 原人卡片的提示列（還在交接中才有；judge §4.7）
    static func personHint(personId: UUID, book: OrgMoveBook, world: OrgMoveWorld, now: Date) -> OrgMoveHint? {
        let todayKey = dayKey(now)
        // [v25.592 轉組織 v1b] 部門還沒改的那一張先（「11/1 起調設備課・交接單排好了（16 項）」「…・已交出 9 項」、
        // 到了還沒改的〔現在套用〕、卡住的為什麼；OrgMoveDue.swift）。要退回這一件：刪這一行
        if let h = pendingPersonHint(personId: personId, book: book, world: world, now: now) { return h }
        // [v25.593 轉組織 v2] 已轉出：「11/1 轉到品保課（已轉出）」灰（還有待分派的多橘點；judge §4.7）。要退回這一件：刪這一行
        if let h = archivedHint(personId: personId, book: book, world: world, now: now) { return h }
        guard let m = book.live.filter({ $0.personId == personId && isOpen($0, todayKey: todayKey) })
            .sorted(by: { ($0.appliedAt ?? Date.distantPast) > ($1.appliedAt ?? Date.distantPast) }).first
        else { return nil }
        let map = OrgMoveHolderMap(world: world)
        let tl = tiles(m, map: map, world: world, now: now)
        let given = tl.first(where: { $0.id == "given" })?.value ?? "0"
        let done = tl.first(where: { $0.id == "done" })?.value ?? "0"
        let eff = shortDay(m.effectiveKey)
        let head: String
        if m.kind == OrgMoveKind.plant.rawValue {
            head = "\(eff) 換到 \(m.to.plant ?? "")"
        } else if m.keepDept == true || m.to.deptId == m.from.deptId {
            head = "\(eff) 交接（部門照舊）"
        } else {
            let fromDept = sideText(OrgMoveSide(deptId: m.from.deptId, deptLabel: m.from.deptLabel), world: world)
            head = "\(eff) 從\(fromDept)調來"
        }
        let text = "\(head)・交出去 \(given)・做完 \(done)"
        let pend = tl.first(where: { $0.id == "pending" })?.value ?? "0"
        let badge: String? = pend == "0" ? nil : "待分派 \(pend)"
        var back = 0, both = 0
        for l in m.allLines where !l.isOrgLine {
            let s = status(l, in: m, map: map, now: now)
            if s.kind == .backOnPerson { back += 1 }
            if s.kind == .onBoth { both += 1 }
        }
        let person = m.personName.isEmpty ? "這位同仁" : m.personName
        var warning: String?
        let org = orgStatus(m, world: world, now: now)
        if back > 0 {
            warning = "有 \(back) 項又回到\(person)身上"
        } else if !org.ok {
            warning = org.text.replacingOccurrences(of: "⚠ ", with: "")
        } else if both > 0 {
            warning = "有 \(both) 項在兩個人身上"
        }
        var hint = OrgMoveHint(moveId: m.id, text: text, badge: badge, warning: warning, isReceiver: false)
        // [v25.592 轉組織 v1b]「排好之後多了 2 件（先跟著王小明）」〔加進交接單〕（生效那天改部門時記下的；judge §5-15）。
        // 要退回這一件：刪這三行
        let late = lateLines(m, world: world, now: now)
        if !late.isEmpty { hint.note = lateNote(late.count, person: person) }
        if !late.isEmpty { hint.actions = [.addLate] }
        return hint
    }

    /// 接手的人卡片的提示列（每一張還在交接中、有交給這位的單一條）
    static func receiverHints(personId: UUID, book: OrgMoveBook, world: OrgMoveWorld, now: Date) -> [OrgMoveHint] {
        let todayKey = dayKey(now)
        let map = OrgMoveHolderMap(world: world)
        // [v25.592 轉組織 v1b]〔11/1 一起做〕排好的：「11/1 起會從王小明接手 6 項」（灰；什麼都還沒交過來，judge §4.6、§4.7）。
        // 要退回這一件：改回 `var out: [OrgMoveHint] = []`
        var out: [OrgMoveHint] = plannedReceiverHints(personId: personId, book: book)
        for m in book.live where m.personId != personId && isOpen(m, todayKey: todayKey) {
            var n = 0, done = 0, both = 0
            for l in m.allLines where !l.isOrgLine && l.lineKind != nil && l.state != OrgMoveLineState.undone.rawValue {
                guard receiver(l, in: m).id == personId else { continue }
                n += 1
                let s = status(l, in: m, map: map, now: now)
                if s.kind == .done { done += 1 }
                if s.kind == .onBoth { both += 1 }
            }
            guard n > 0 else { continue }
            let from = m.personName.isEmpty ? "這位同仁" : m.personName
            out.append(OrgMoveHint(moveId: m.id, text: "從\(from)接手 \(n) 項・做完 \(done)", badge: nil,
                                   warning: both > 0 ? "有 \(both) 項在兩個人身上" : nil, isReceiver: true))
        }
        return out
    }

    /// 〔潛力性〕「歷程」裡的轉組織列（新到舊；畫面跟升職歷程混在同一條時間軸）
    static func historyRows(personId: UUID, book: OrgMoveBook, world: OrgMoveWorld) -> [OrgMoveHistoryRow] {
        book.live.filter { $0.personId == personId && $0.wasApplied }
            .sorted { $0.effectiveKey > $1.effectiveKey }
            .map { m -> OrgMoveHistoryRow in
                let f = sideText(m.from, world: world)
                let t = sideText(m.to, world: world)
                // [v25.593 轉組織 v2] 離職、退休、回到我的部屬只寫一邊（「製造一課 P1」）。要退回這一件：改回 `let detail = f == t ? …`
                let detail = historyDetail(m, from: f, to: t)
                let c = handedCounts(m)
                // [v25.592 轉組織 v1b] 生效前取消的寫「（已取消）」、取消了調動但交接照舊的多寫那一句；部門還沒改的寫「（11/1 才改部門）」。
                // 要退回這一件：sub、title 改回只看 isUndone 的那兩行
                let sub = historySub(m, given: c.given, follow: c.follow)
                let title = historyTitle(m)
                return OrgMoveHistoryRow(moveId: m.id, date: date(fromKey: m.effectiveKey) ?? Date.distantPast,
                                         title: title, detail: detail, sub: sub, isUndone: m.isUndone)
            }
    }

    /// 接手的人〔主動性〕最上面「從王小明接手（4）・11/2」那一區（還在交接中才有）
    static func receivedSections(personId: UUID, book: OrgMoveBook, world: OrgMoveWorld, now: Date) -> [OrgMoveReceivedSection] {
        let todayKey = dayKey(now)
        let map = OrgMoveHolderMap(world: world)
        var out: [OrgMoveReceivedSection] = []
        for m in book.live where m.personId != personId && isOpen(m, todayKey: todayKey) {
            var rows: [OrgMoveReceivedRow] = []
            for l in m.allLines where !l.isOrgLine && l.lineKind != nil && l.state != OrgMoveLineState.undone.rawValue {
                guard receiver(l, in: m).id == personId else { continue }
                let s = status(l, in: m, map: map, now: now)
                rows.append(receivedRow(l, status: s, move: m, map: map))
            }
            guard !rows.isEmpty else { continue }
            let from = m.personName.isEmpty ? "這位同仁" : m.personName
            let at = (m.handedAt ?? m.appliedAt).map { shortDay(dayKey($0)) } ?? shortDay(m.effectiveKey)
            out.append(OrgMoveReceivedSection(moveId: m.id, header: "從\(from)接手（\(rows.count)）・\(at)", rows: rows))
        }
        return out
    }

    /// [v25.591 轉組織 v1a-2] 接手那一區的一列：待辦、週報點了開預覽；會議（新會議）、議程點了開那場會議；兼任＝接手的人身上那一筆
    static func receivedRow(_ l: OrgMoveLine, status s: OrgMoveLineStatus, move: OrgMove, map: OrgMoveHolderMap) -> OrgMoveReceivedRow {
        var taskId: UUID?
        var reportId: UUID?
        var meetingId: UUID?
        var meetingHolder: UUID?
        var title = l.title
        switch l.lineKind {
        case .some(.task), .some(.alarmTask):
            taskId = l.refId
        case .some(.report):
            reportId = l.refId
        case .some(.sideRole):
            if let mid = l.meetingId {
                meetingId = mid
                meetingHolder = map.meetingHolders[mid]
            } else if let tid = l.refId, let to = l.toId {
                taskId = map.sideRoleCopies[tid]?.first(where: { $0.holder == to })?.task.id ?? l.itemId
            }
            title = l.title + "（兼任）"
        case .some(.meeting):
            meetingId = l.lineAction == .newSeries ? l.newId : l.refId
            meetingHolder = meetingId.flatMap { map.meetingHolders[$0] }
            title = l.lineAction == .newSeries ? "會議 " + (l.newTopic ?? l.title) : "會議 " + l.title
        case .some(.agenda):
            let c = l.refId.flatMap { map.items[$0]?.first }
            meetingId = c?.meetingId ?? l.parentId
            meetingHolder = c?.holder ?? l.holderId
            title = "議程：" + l.title
        default:
            break
        }
        return OrgMoveReceivedRow(lineId: l.id, mark: s.mark, title: title, detail: s.text, taskId: taskId,
                                  reportId: reportId, kind: l.kind, meetingId: meetingId, meetingHolderId: meetingHolder)
    }

    /// 部屬總覽「待分派」卡（judge §4.9）：照機台現在的負責人算——還是原人＝待分派；已經不是＝算分好了，不列
    static func pendingRows(book: OrgMoveBook, world: OrgMoveWorld) -> [OrgMovePendingRow] {
        var out: [OrgMovePendingRow] = []
        for m in book.live where m.wasApplied && !m.isUndone {
            let person = m.personName.isEmpty ? "這位同仁" : m.personName
            let handed = m.handedAt ?? m.appliedAt ?? Date.distantPast
            for lid in pendingLineIds(m) {
                guard let l = m.line(lid), let eid = l.refId,
                      let eq = world.equipmentItem(eid), eq.ownerId == m.personId else { continue }
                var extra: [String] = []
                let tasks = world.sub(m.personId)?.tasks ?? []
                let newAlarms = tasks.filter { t in
                    !t.isCompleted && t.equipmentLink?.equipmentId == eid && t.date >= handed
                }.sorted { $0.date < $1.date }
                if let first = newAlarms.first {
                    extra.append("\(shortDay(dayKey(first.date))) 有 \(newAlarms.count) 筆警報，任務先在\(person)身上（逾期不算\(person)）")
                }
                let reports = world.sub(m.personId)?.weeklyReports ?? []
                var linked = 0
                for x in m.allLines {
                    guard x.action == OrgMoveAction.withEquipment.rawValue, x.parentId == eid,
                          x.kind != OrgMoveLineKind.alarmTask.rawValue,
                          x.state != OrgMoveLineState.undone.rawValue, let ref = x.refId else { continue }
                    let openTask = tasks.contains(where: { $0.id == ref && !$0.isCompleted })
                    let openReport = reports.contains(where: { $0.id == ref && !$0.isCompleted })
                    if openTask || openReport { linked += 1 }
                }
                if linked > 0 { extra.append("連著 \(linked) 件待辦，會一起過去") }
                out.append(OrgMovePendingRow(moveId: m.id, lineId: lid, equipmentId: eid, personId: m.personId,
                                             title: "\(world.equipmentName(eid))・原本 \(person)・\(shortDay(dayKey(handed))) 起",
                                             extra: extra))
            }
        }
        return out
    }

    // MARK: 分享（只有文字；judge §4.10、§1.4-6：不照抄會寫分數的〔匯出文字〕）

    /// 〔給陳怡君的 4 項〕〔給林志豪的 1 項〕〔整張（給新主管）〕
    static func shareTargets(_ move: OrgMove) -> [OrgMoveShareTarget] {
        var order: [UUID] = []
        var names: [UUID: String] = [:]
        var counts: [UUID: Int] = [:]
        // [v25.592 轉組織 v1b] 你自己加的一項交給誰也算（只有門禁卡交給林志豪，也有〔給林志豪的 1 項〕）。要退回這一件：拿掉 `|| l.isCustom`
        for l in move.allLines where !l.isOrgLine && (l.lineKind != nil || l.isLiveCustom) && l.state != OrgMoveLineState.undone.rawValue {
            guard let to = receiver(l, in: move).id else { continue }
            if counts[to] == nil { order.append(to) }
            counts[to, default: 0] += 1
            names[to] = receiver(l, in: move).name ?? ""
        }
        var out = order.map { id in
            OrgMoveShareTarget(receiverId: id, label: "給\(names[id] ?? "")的 \(counts[id] ?? 0) 項")
        }
        // [v25.593 轉組織 v2]〔交出去〕給不在部屬名單的人：〔給黃冠宇的 2 項〕（給我的不出分享）。要退回這一件：刪這一行
        out.append(contentsOf: handOutShareTargets(move))
        out.append(OrgMoveShareTarget(receiverId: nil, label: "整張（給新主管）"))
        return out
    }

    /// 分享文字。不寫：分數、自訂分、缺失、考評、請假、你的備註（單上的 note）、交接時已逾期（只寫新的截止日）、
    /// 調動原因、任務自己的備註、議程備註——只寫你在這張單上打的「交接備註」
    static func shareText(_ move: OrgMove, receiverId: UUID?, map: OrgMoveHolderMap, world: OrgMoveWorld) -> String {
        let person = move.personName.isEmpty ? "這位同仁" : move.personName
        let dates = "\(shortDay(move.effectiveKey)) 生效，交接完成日 \(shortDay(move.handoverByKey))"
        var out: [String] = []
        if let rid = receiverId {
            let who = receiverName(rid, move: move, map: map)
            out.append("\(person) → \(who)　交接（\(dates)）")
            out.append(contentsOf: shareItems(move, receiverId: rid, map: map, world: world))
        } else {
            let f = sideText(OrgMoveSide(deptId: move.from.deptId, deptLabel: move.from.deptLabel), world: world)
            let t = sideText(OrgMoveSide(deptId: move.to.deptId, deptLabel: move.to.deptLabel), world: world)
            let route = f == t || f.isEmpty || t.isEmpty ? "" : "\(f) → \(t)，"
            out.append("\(person)　交接單（\(route)\(dates)）")
            for target in shareTargets(move) {
                guard let rid = target.receiverId else { continue }
                // [v25.593 轉組織 v2]〔交出去〕給的寫「交出去給 黃冠宇」。要退回這一件：改回 `out.append("交給 \(…)")`
                let verb = isHandOutTarget(rid, move: move) ? "交出去給" : "交給"
                out.append("\(verb) \(receiverName(rid, move: move, map: map))")
                out.append(contentsOf: shareItems(move, receiverId: rid, map: map, world: world))
            }
            // [v25.593 轉組織 v2]「我先接：E-03 腔體漏率改善」。要退回這一件：刪這兩行
            let mineTitles = handOutMineTitles(move)
            if !mineTitles.isEmpty { out.append("我先接：" + mineTitles.joined(separator: "、")) }
            let pend = move.allLines.filter { l in
                l.kind == OrgMoveLineKind.equipment.rawValue && receiver(l, in: move).id == nil
                    && resolved(l, in: move.allLines).action == .pending && l.state != OrgMoveLineState.undone.rawValue
            }.map(\.title)
            if !pend.isEmpty { out.append("待分派：" + pend.joined(separator: "、")) }
            var follows: [String] = []
            var ended: [String] = []
            for l in move.allLines where !l.isOrgLine && l.lineKind != nil && l.state != OrgMoveLineState.undone.rawValue {
                guard receiver(l, in: move).id == nil else { continue }
                let a = resolved(l, in: move.allLines).action
                // [v25.591 轉組織 v1a-2] 一對一的會議、一對一裡的議程不寫（judge §4.10）；結束的會議另一段
                guard shareFollowAllowed(l, map: map) else { continue }
                if a == .end {
                    let undo = OrgMoveMeetingUndo.decode(l.removedJSON)
                    let last = undo?.lastScheduled.map { "（\(shortDay(dayKey($0))) 是最後一場）" } ?? ""
                    ended.append(l.title + last)
                    continue
                }
                guard a == nil || a == .follow else { continue }
                if l.lineLock == .dereliction { continue }      // 缺失不寫
                if l.kind == OrgMoveLineKind.sideRole.rawValue {
                    follows.append("\(l.title)（兼任）")
                } else {
                    follows.append(l.title)
                }
            }
            if !follows.isEmpty { out.append("跟著\(person)的：" + follows.joined(separator: "、")) }
            if !ended.isEmpty { out.append("結束的會議：" + ended.joined(separator: "、")) }
        }
        return out.joined(separator: "\n")
    }

    private static func receiverName(_ id: UUID, move: OrgMove, map: OrgMoveHolderMap) -> String {
        for l in move.allLines {
            let r = receiver(l, in: move)
            if r.id == id, let n = r.name, !n.isEmpty { return n }
            // [v25.593 轉組織 v2]〔交出去〕給的組織人員不在部屬裡（map 查不到）：用單上的名字。要退回這一件：刪這一行
            if l.lineAction == .handOut, l.toId == id, let n = l.toName, !n.isEmpty { return n }
        }
        return map.name(id)
    }

    /// 給某一位的那幾項（待辦 → 機台 → 週報題目，各自一個小標；編號接著算）
    private static func shareItems(_ move: OrgMove, receiverId: UUID, map: OrgMoveHolderMap, world: OrgMoveWorld) -> [String] {
        // [v25.593 轉組織 v2]〔交出去〕給這位（組織人員）的也算（isShareTo）。要退回這一件：isShareTo 改回 `receiver(l, in: move).id == receiverId`
        let mine = move.allLines.filter { l in
            !l.isOrgLine && l.lineKind != nil && l.state != OrgMoveLineState.undone.rawValue
                && isShareTo(l, receiverId: receiverId, move: move)
        }
        // [v25.592 轉組織 v1b] 你自己加的一項（門禁卡、鑰匙…），排在最後一段「自己加的」
        let customs = move.allLines.filter { l in l.isLiveCustom && isShareTo(l, receiverId: receiverId, move: move) }
        let tasks = mine.filter { $0.kind == OrgMoveLineKind.task.rawValue } + mine.filter { $0.kind == OrgMoveLineKind.alarmTask.rawValue }
        let eqs = mine.filter { $0.kind == OrgMoveLineKind.equipment.rawValue }
        let reps = mine.filter { $0.kind == OrgMoveLineKind.report.rawValue }
        // [v25.591 轉組織 v1a-2] 會議、議程排在機台後面、週報前面；班、兼任排在週報後面
        let meetingsAgenda = mine.filter { $0.kind == OrgMoveLineKind.meeting.rawValue || $0.kind == OrgMoveLineKind.agenda.rawValue }
        let shiftsSides = mine.filter { $0.kind == OrgMoveLineKind.shifts.rawValue || $0.kind == OrgMoveLineKind.sideRole.rawValue }
        var out: [String] = []
        var n = 0
        if !tasks.isEmpty {
            out.append("待辦")
            for l in tasks {
                n += 1
                let copy = map.tasks[l.refId ?? UUID()]?.first
                let dueKey = copy?.task.dueDate.map { dayKey($0) } ?? (l.wasOverdue == true ? l.newDueKey : l.dueKey)
                var s = "\(n). \(l.title)"
                if let k = dueKey { s += "｜截止 \(shortDay(k))" }
                if l.kind == OrgMoveLineKind.alarmTask.rawValue, let t = copy?.task {
                    s += "（\(shortDay(dayKey(t.date))) 的警報）"
                } else if l.parentId != nil {
                    s += "｜相關機台 \(world.equipmentName(l.parentId))"
                }
                out.append(s)
                let memo = (l.memo ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !memo.isEmpty { out.append("   備註：\(memo)") }
            }
        }
        if !eqs.isEmpty {
            out.append("機台")
            for l in eqs {
                n += 1
                let d = world.deptShort(world.equipmentItem(l.refId)?.departmentId)
                out.append(d.isEmpty ? "\(n). \(l.title)" : "\(n). \(l.title)（\(d)）")
                let memo = (l.memo ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !memo.isEmpty { out.append("   備註：\(memo)") }
            }
        }
        out.append(contentsOf: moreShareItems(meetingsAgenda, move: move, map: map, world: world, n: &n))
        if !reps.isEmpty {
            out.append("週報題目")
            for l in reps {
                n += 1
                out.append("\(n). \(l.title)")
                let memo = (l.memo ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !memo.isEmpty { out.append("   備註：\(memo)") }
            }
        }
        out.append(contentsOf: moreShareItems(shiftsSides, move: move, map: map, world: world, n: &n))
        out.append(contentsOf: customShareItems(customs, n: &n))
        return out
    }

    /// 分享前先跳一次提醒（比照績效互評排名票）。名字＝這位同仁＋這份裡接手的人
    static func shareWarning(_ move: OrgMove, receiverId: UUID?, map: OrgMoveHolderMap) -> (title: String, message: String) {
        let person = move.personName.isEmpty ? "這位同仁" : move.personName
        var names: [String] = [person]
        for t in shareTargets(move) {
            guard let rid = t.receiverId else { continue }
            if let only = receiverId, only != rid { continue }
            let n = receiverName(rid, move: move, map: map)
            if !names.contains(n) { names.append(n) }
        }
        let msg = "這份交接單會寫出\(names.joined(separator: "、"))的名字和手上的工作，傳出去就收不回來了。分數、考評、缺失、請假不會放進去。"
        return ("要分享交接單嗎？", msg)
    }

    // MARK: 復原

    /// 〔復原這次轉組織〕（到 11/9）的字
    static func undoButtonTitle(_ move: OrgMove) -> String {
        "復原這次轉組織（到 \(shortDay(undoUntilKey(move)))）"
    }

    /// 復原的確認字（judge §10.4 ③-C3）。一列一列看「交出去之後有沒有被動過」：沒被動過的才退回
    static func undoPreview(_ move: OrgMove, map: OrgMoveHolderMap, world: OrgMoveWorld, now: Date) -> (title: String, message: String) {
        let person = move.personName.isEmpty ? "這位同仁" : move.personName
        var parts: [String] = []
        let org = orgStatus(move, world: world)
        // [v25.593 轉組織 v2] 調出也改部門（changesDept）；調出、離職、退休多「回到部屬名單」「組織圖上的已離職拿掉」。
        // 要退回這一件：deptChanged 改回 `move.kind == OrgMoveKind.move.rawValue && …`、刪 leavingUndoParts 那一行
        let deptChanged = move.changesDept
        let plantChanged = (move.to.plant ?? "") != (move.from.plant ?? "")
        if org.ok && (deptChanged || plantChanged) {
            parts.append("\(person)回到\(sideText(move.from, world: world))")
        }
        parts.append(contentsOf: leavingUndoParts(move))
        var back = 0
        var machines: [String] = []
        var putBack = 0
        var keptBy: [UUID: Int] = [:]
        var keptOrder: [UUID] = []
        var elsewhere = 0
        // [v25.593 轉組織 v2]〔交出去〕的（給不在部屬名單的人、給我）復原時同〔不要了〕放回。要退回這一件：刪 handedBack 那幾行
        var handedBack = 0
        for l in move.allLines where !l.isOrgLine && l.lineKind != nil && l.state != OrgMoveLineState.undone.rawValue {
            let s = status(l, in: move, map: map, now: now)
            switch s.kind {
            case .handedOut, .mine:
                if l.removedJSON != nil { handedBack += 1 }
            case .open:
                // [v25.591 轉組織 v1a-2] 兼任的另外寫（「兼任「尾牙籌備」負責人換回王小明」）
                if l.kind != OrgMoveLineKind.equipment.rawValue && l.kind != OrgMoveLineKind.sideRole.rawValue { back += 1 }
            case .handed:
                if l.kind == OrgMoveLineKind.equipment.rawValue { machines.append(l.title) }
            case .dropped:
                if l.removedJSON != nil { putBack += 1 }
            case .done:
                if let h = s.holderId, h != move.personId {
                    if keptBy[h] == nil { keptOrder.append(h) }
                    keptBy[h, default: 0] += 1
                }
            case .elsewhere:
                elsewhere += 1
            default:
                break
            }
        }
        if back > 0 { parts.append("還沒做完的 \(back) 件搬回\(person)") }
        if !machines.isEmpty { parts.append("\(machines.joined(separator: "、")) 換回\(person)顧") }
        parts.append(contentsOf: moreUndoParts(move, map: map, now: now))
        if putBack > 0 { parts.append("不要了的 \(putBack) 件放回\(person)") }
        if handedBack > 0 { parts.append("交出去的 \(handedBack) 件放回\(person)") }
        let mgr = move.allLines.filter { $0.isOrgLine && ($0.lineAction == .remove || $0.lineAction == .replace) }
        for l in mgr { parts.append("\(world.deptShort(l.refId))管理人員加回\(person)") }
        var kept: [String] = []
        for h in keptOrder { kept.append("\(map.name(h))已經做完的 \(keptBy[h] ?? 0) 件") }
        if !kept.isEmpty { parts.append(kept.joined(separator: "、") + "留在原地") }
        if elsewhere > 0 { parts.append("改給別人的 \(elsewhere) 件不動") }
        let msg = parts.isEmpty ? "沒有東西要搬回來。" : parts.joined(separator: "；") + "。"
        return ("復原 \(shortDay(move.effectiveKey)) 的轉組織？", msg)
    }
}
