import SwiftUI

// MARK: - [v25.588] 部屬匯出可選：選項、快照、篩好的一份、組字（主控寫好，各組只呼叫、不改）
//
// 使用者原話：「人員部屬匯出文字或圖片功能我希望給我選別功能，匯出可以選擇含不含上方summary看板，
// 以及匯出可多選任務/會議/完成項目/請假，幫我盤點涵蓋完整點」。
// 規格：scratchpad/orgmove/export/design.md（§2 選項、§3 每一塊、§4 分享前提醒、§8 部屬總覽）；
// 對照模擬：scratchpad/orgmove/build/export/sim_export.py、sim_team.py——每一條規則、每一個字都要對得上。
//
// 這支只放「純資料＋純函式」：圖、文、件數、提醒都吃同一份 resolve() 的結果（SubExportModel／TeamExportModel），
// 選項頁（SubordinateExportSheet.swift）、出圖（SubordinateExportImage.swift）只讀這裡的東西。
// 唯一碰 LifeStore 的是 SubExportSnapshot.make（@MainActor）：把這一次要用的資料抽出來，之後組字不碰 store。
//
// 日子一律用西曆（gregorian）的 DateComponents 算、組字（修 B9：手機設民國曆時不再寫成 115 年），不用 DateFormatter。
// 寫給使用者的字不用人稱代名詞，用名字或「這位同仁」。

// MARK: - 共用小型別

enum SubExportFormat: String, CaseIterable, Identifiable {
    case image, text
    var id: String { rawValue }
    var label: String { self == .image ? "圖片" : "文字" }
}

/// 部屬卡片「…」▸〔部屬卡片…〕〔匯出文字…〕→ 選項頁（.sheet(item:)）
struct SubExportRequest: Identifiable {
    let id = UUID()
    let format: SubExportFormat
}

/// 部屬總覽右上 ⤴ ▸〔匯出圖片…〕〔匯出文字…〕→ 選項頁（.sheet(item:)）
struct TeamExportRequest: Identifiable {
    let id = UUID()
    let format: SubExportFormat
}

/// 分享面板（ShareSheet）的 .sheet(item:) 包裝：圖片暫存檔 URL 或純文字
struct SubExportSharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

/// 出圖結果：urls＝實際出得來的；expected＝應該要有幾張（少了就說「有 N 張出不來」）
struct SubExportRenderResult {
    let urls: [URL]
    let expected: Int
}

/// 只要看板（0 列）走整張單圖；有列走 PagedImageExporter.exportSections（它 0 列會回空陣列，§6.4-15）
enum SubExportImageRoute { case single, paged }

// MARK: - 區塊（照卡片順序；輸出也照這個順序）

enum SubExportBlock: String, CaseIterable, Identifiable {
    // 主動性
    case reports, meetings, tasks, mentioned, sideRoles, leaves, completed
    // 潛力性（考評）
    case history, proCon, achievements, improvements, faults, missOps
    // 執掌
    case equipment, timeline
    // 卡片上沒有的
    case shifts

    var id: String { rawValue }

    /// 出廠預設勾的（design §0-4；§6.6 第 1、4 題）
    static let factory: Set<SubExportBlock> = [.tasks, .meetings, .completed, .leaves, .reports, .sideRoles, .equipment]
    /// 考評五樣（勾了而且有寫出來才點名）
    static let evaluation: [SubExportBlock] = [.proCon, .achievements, .improvements, .faults, .missOps]
    /// 提醒「和手上的工作（…）」裡的區塊，照卡片順序
    static let work: [SubExportBlock] = [.reports, .meetings, .tasks, .sideRoles, .completed, .equipment, .timeline, .shifts]
    /// 底下那條「任務 6・會議 2・…」的順序
    static let countOrder: [SubExportBlock] = [.tasks, .meetings, .completed, .leaves, .reports, .sideRoles, .mentioned,
                                               .history, .proCon, .achievements, .improvements, .faults, .missOps,
                                               .equipment, .timeline, .shifts]

    /// 選項頁、空區塊「（這段期間沒有：…）」、提醒用的名字。
    /// [v25.590 轉組織 v1a-1] history「升職歷程」→「歷程」（升職、轉組織同一區）：只改這一個字，
    /// 記住的選擇（rawValue "history"）照樣有效。要退回這一件：改回 "升職歷程"。
    var label: String {
        switch self {
        case .reports: return "報告"
        case .meetings: return "會議"
        case .tasks: return "任務"
        case .mentioned: return "被標註的項目"
        case .sideRoles: return "兼任職務"
        case .leaves: return "請假"
        case .completed: return "完成項目"
        case .history: return "歷程"
        case .proCon: return "優缺點"
        case .achievements: return "成就"
        case .improvements: return "改善"
        case .faults: return "缺失紀錄"
        case .missOps: return "Miss Operation"
        case .equipment: return "執掌設備"
        case .timeline: return "PM／警報時間軸"
        case .shifts: return "排班"
        }
    }

    /// 提醒「和手上的工作（…）」裡的字
    var workLabel: String {
        switch self {
        case .sideRoles: return "兼任"
        case .timeline: return "PM／警報"
        default: return label
        }
    }

    /// 底下那條的短字（請假、執掌另外組，見 SubExportComposer.countLine）
    var countLabel: String {
        switch self {
        case .completed: return "完成"
        case .sideRoles: return "兼任"
        case .mentioned: return "被標註"
        case .history: return "歷程"
        case .missOps: return "Miss"
        case .timeline: return "時間軸"
        default: return label
        }
    }
}

enum SubExportPeriod: String, CaseIterable, Identifiable {
    case all, thisYear, last3Months, thisMonth, custom
    /// v2（25.593）起只有已轉出的人才出現；這版選項頁不放這一顆，型別先留著
    case whileMine
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "全部"
        case .thisYear: return "今年"
        case .last3Months: return "近 3 個月"
        case .thisMonth: return "本月"
        case .custom: return "自訂…"
        case .whileMine: return "在我這裡的時候"
        }
    }
    /// 選項頁的五顆膠囊（這版）
    static let pickerCases: [SubExportPeriod] = [.all, .thisYear, .last3Months, .thisMonth, .custom]
}

enum SubExportCompletedKind: String, CaseIterable, Identifiable {
    case task, agenda, report
    var id: String { rawValue }
    var label: String {
        switch self {
        case .task: return "任務"
        case .agenda: return "議程"
        case .report: return "報告"
        }
    }
}

// MARK: - 選項（記住上次：存這台 @AppStorage("sub_export_options_v1") 的 JSON 字串，不跟 iCloud）
//
// ⚠️ 不要讓這個型別同時 Codable＋RawRepresentable<String> 直接塞 @AppStorage：
//    Encodable 的預設實作會走 rawValue，rawValue 又呼叫 JSONEncoder → 無限遞迴（design §6.4-12）。
//    一律存 String，自己 load／json()。
// 每個欄位 decodeIfPresent、讀不懂就用出廠值：以後加欄位、舊版存的 JSON 都不會整包洗回出廠。
// 區塊、完成項目種類存成字串陣列：以後多一種區塊，舊版讀到不認得的字只略過那一個，不會整個集合讀失敗。

struct SubExportOptions: Equatable, Codable {
    var includeBoard = true
    /// 看板的〔生日〕（只有月日；年份永遠不出去）
    var boardBirthday = false
    /// 看板的〔分數〕：分數三格（至今累計）＋第一列優點／缺點／成就／Miss／請假小格（期間內）。看板關了不作用
    var boardScores = false
    var blocks: Set<SubExportBlock> = SubExportBlock.factory
    var period: SubExportPeriod = .last3Months
    var customStart: Date? = nil
    var customEnd: Date? = nil
    /// 還沒做完、還沒到的不管期間都列（§2.5）
    var openItemsIgnorePeriod = true
    /// 〔逾期、準時與自訂分〕：任務逾期幾天、完成章、自訂分、「交接時已逾期」（[v25.590 轉組織 v1a-1]）
    var includeMarks = false
    /// 〔備註〕：任務、議程、會議、報告、紀錄、升職的備註（可能 @ 到別的同仁）
    var includeNotes = false
    /// 請假〔事由〕
    var leaveReason = false
    /// 任務〔機台警報〕
    var taskAlarm = true
    /// 任務〔缺失任務〕（完成項目裡結案的缺失也跟這個勾）
    var taskDereliction = false
    /// 任務〔內容與處理〕：內容、處理措施、回復結果
    var taskDetails = true
    /// 完成項目〔任務〕〔議程〕〔報告〕（至少留一個）
    var completedKinds: Set<SubExportCompletedKind> = Set(SubExportCompletedKind.allCases)
    /// 會議〔別人會議交給這位同仁的〕
    var othersAgenda = false
    /// [v25.590 轉組織 v1a-1] 時間軸〔只列接手之後〕：從交接單收到的機台，PM、警報、件數都從交到這位同仁手上那一刻起算
    ///（選項頁只有這位同仁有從交接單收到的機台才出現這一顆；25.588 就存在記住的那包裡，預設開）
    var timelineAfterHandover = true

    init() {}

    enum CodingKeys: String, CodingKey {
        case includeBoard, boardBirthday, boardScores, blocks, period, customStart, customEnd
        case openItemsIgnorePeriod, includeMarks, includeNotes, leaveReason
        case taskAlarm, taskDereliction, taskDetails, completedKinds, othersAgenda, timelineAfterHandover
    }

    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        includeBoard = (try? c.decodeIfPresent(Bool.self, forKey: .includeBoard)) ?? includeBoard
        boardBirthday = (try? c.decodeIfPresent(Bool.self, forKey: .boardBirthday)) ?? boardBirthday
        boardScores = (try? c.decodeIfPresent(Bool.self, forKey: .boardScores)) ?? boardScores
        if let raw = try? c.decodeIfPresent([String].self, forKey: .blocks) {
            blocks = Set(raw.compactMap { SubExportBlock(rawValue: $0) })
        }
        if let raw = try? c.decodeIfPresent(String.self, forKey: .period),
           let p = SubExportPeriod(rawValue: raw) {
            period = p
        }
        customStart = try? c.decodeIfPresent(Date.self, forKey: .customStart)
        customEnd = try? c.decodeIfPresent(Date.self, forKey: .customEnd)
        openItemsIgnorePeriod = (try? c.decodeIfPresent(Bool.self, forKey: .openItemsIgnorePeriod)) ?? openItemsIgnorePeriod
        includeMarks = (try? c.decodeIfPresent(Bool.self, forKey: .includeMarks)) ?? includeMarks
        includeNotes = (try? c.decodeIfPresent(Bool.self, forKey: .includeNotes)) ?? includeNotes
        leaveReason = (try? c.decodeIfPresent(Bool.self, forKey: .leaveReason)) ?? leaveReason
        taskAlarm = (try? c.decodeIfPresent(Bool.self, forKey: .taskAlarm)) ?? taskAlarm
        taskDereliction = (try? c.decodeIfPresent(Bool.self, forKey: .taskDereliction)) ?? taskDereliction
        taskDetails = (try? c.decodeIfPresent(Bool.self, forKey: .taskDetails)) ?? taskDetails
        if let raw = try? c.decodeIfPresent([String].self, forKey: .completedKinds) {
            let kinds = Set(raw.compactMap { SubExportCompletedKind(rawValue: $0) })
            // 細項最後一個勾不能取消（§2.10）：讀到空的（壞掉的 JSON）就回三種都要
            if !kinds.isEmpty { completedKinds = kinds }
        }
        othersAgenda = (try? c.decodeIfPresent(Bool.self, forKey: .othersAgenda)) ?? othersAgenda
        timelineAfterHandover = (try? c.decodeIfPresent(Bool.self, forKey: .timelineAfterHandover)) ?? timelineAfterHandover
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(includeBoard, forKey: .includeBoard)
        try c.encode(boardBirthday, forKey: .boardBirthday)
        try c.encode(boardScores, forKey: .boardScores)
        try c.encode(blocks.map { $0.rawValue }.sorted(), forKey: .blocks)
        try c.encode(period.rawValue, forKey: .period)
        try c.encodeIfPresent(customStart, forKey: .customStart)
        try c.encodeIfPresent(customEnd, forKey: .customEnd)
        try c.encode(openItemsIgnorePeriod, forKey: .openItemsIgnorePeriod)
        try c.encode(includeMarks, forKey: .includeMarks)
        try c.encode(includeNotes, forKey: .includeNotes)
        try c.encode(leaveReason, forKey: .leaveReason)
        try c.encode(taskAlarm, forKey: .taskAlarm)
        try c.encode(taskDereliction, forKey: .taskDereliction)
        try c.encode(taskDetails, forKey: .taskDetails)
        try c.encode(completedKinds.map { $0.rawValue }.sorted(), forKey: .completedKinds)
        try c.encode(othersAgenda, forKey: .othersAgenda)
        try c.encode(timelineAfterHandover, forKey: .timelineAfterHandover)
    }

    /// 讀記住的那一包；空字串、讀不懂都回出廠，不會當掉
    static func load(_ json: String) -> SubExportOptions {
        guard !json.isEmpty, let data = json.data(using: .utf8),
              let o = try? JSONDecoder().decode(SubExportOptions.self, from: data) else { return SubExportOptions() }
        return o
    }

    func json() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    /// 〔全選〕：所有區塊打勾；**不動**看板分數、逾期準時與自訂分、備註、事由、生日、缺失任務（§2.8）
    mutating func selectAllBlocks() {
        blocks = Set(SubExportBlock.allCases)
    }

    /// 〔只要看板〕：看板開、區塊全關
    mutating func boardOnly() {
        includeBoard = true
        blocks = []
    }
}

// MARK: - 快照：從 LifeStore 抽出這一次要用的資料（組字不碰 LifeStore，才能用 Python 對照）

struct SubExportSnapshot {
    struct SideRoleLine: Identifiable {
        let id: UUID
        let name: String
        let isActive: Bool
        let duty: String
        let start: Date
        let end: Date?
        let done: Int
        let total: Int
    }

    struct EquipmentLine: Identifiable {
        let id: UUID
        let name: String
        let system: String
        let department: String
        let pmRecords: [EquipmentPMRecord]
        let alarms: [EquipmentAlarm]
    }

    /// 被標註：kind 只會是「任務」「會議」「報告」——別的同仁的缺失任務也只寫「任務」（那是別人的考評）
    struct MentionLine: Identifiable {
        let id: String
        let kind: String
        let topic: String
        let ownerName: String
        /// 任務＝立案日、報告＝報告日、會議＝最近一場（今天以前）
        let date: Date
        let isDone: Bool
        /// 會議名稱像一對一：永遠不出去（別的同仁的一對一）
        let isOneOnOne: Bool
    }

    /// 別的同仁的會議裡，交給這位同仁的議程（卡片上看不到、分數有算）
    struct OthersAgendaLine: Identifiable {
        let meetingId: UUID
        let meetingTopic: String
        let ownerName: String
        let item: MeetingItem
        let sessionDate: Date
        let isOneOnOne: Bool
        var id: UUID { item.id }
    }

    var subordinateId: UUID
    /// 這位同仁已經不在名單上（iCloud 從別台刪掉）：選項頁自己關掉、不出檔
    var isGone = false
    var name = ""
    var gradeTitle = ""
    var department = ""
    var plantArea = ""
    var joinDate: Date? = nil
    /// 「3.2」（年資，算到今天；同看板）
    var seniority: String? = nil
    /// 「3/14・雙魚座」（只有月日；年份永遠不放）
    var birthdayText: String? = nil
    /// 至今累計（不跟期間）
    var scores: (proactivity: Int, potential: Int, overall: Int) = (0, 0, 0)
    var tasks: [SubordinateTask] = []
    var meetings: [SubordinateMeeting] = []
    var reports: [WeeklyReport] = []
    var records: [SubordinateRecord] = []
    var promotions: [PromotionRecord] = []
    var shifts: [SubordinateShift] = []
    var sideRoles: [SideRoleLine] = []
    var equipment: [EquipmentLine] = []
    var mentioned: [MentionLine] = []
    var othersAgenda: [OthersAgendaLine] = []
    /// 議程負責人 id → 名字（部屬／組織人員／名片）
    var personNames: [UUID: String] = [:]
    /// 人員 id（部屬、組織人員、名片）→ 對應的部屬 id（同 LifeStore.meetingItemCredits 的反查）
    var ownerSubIds: [UUID: UUID] = [:]
    /// 解析成這位同仁的 id（本人、連到本人的組織人員與名片）
    var meIds: Set<UUID> = []
    /// 機台 id → 現在的名字、系統別（任務的關聯機台、警報來源機台）
    var equipmentNames: [UUID: String] = [:]
    var equipmentSystems: [UUID: String] = [:]
    /// 兼任職務 id → 名稱（任務的兼任膠囊）
    var sideRoleNames: [UUID: String] = [:]
    /// 提醒「也會寫出…的名字」掃全文用：部屬＋公司組織人員＋名片的名字（2 字以上、去重）
    var knownNames: [String] = []

    /// [v25.590 轉組織 v1a-1] 從交接單接手的那一筆（任務、報告的「｜交接自 王小明」）。
    /// 只記名字與「交接時已逾期」：交接備註、你的備註、原本的截止日都不進匯出（design §5.2）。
    struct HandoverMark: Equatable {
        /// 交出來的那位同仁（交接單上的名字快照；空的寫「這位同仁」）
        let fromName: String
        /// 交接那一刻已經逾期（只在〔逾期、準時與自訂分〕開著時寫出去）
        let wasOverdue: Bool
    }

    /// [v25.590 轉組織 v1a-1] 任務、週報 id → 交接自誰（跟卡片膠囊同一個條件：OrgMoveIndex.receivedChip，交接完成就收起來）
    var handovers: [UUID: HandoverMark] = [:]
    /// [v25.590 轉組織 v1a-1] 歷程的轉組織那幾列（OrgMovePlan.historyRows；已復原的不放；不寫調動原因、交接備註、你的備註）
    var orgHistory: [SubExportModel.HistoryLine] = []
    /// [v25.590 轉組織 v1a-1] 現在負責、而且是從交接單收到的機台 id → 交到這位同仁手上的那一刻
    ///（OrgMoveIndex.receivedByItem、toId 是這位同仁才算；不看膠囊期間）。時間軸〔只列接手之後〕用
    var equipmentSince: [UUID: Date] = [:]

    /// 抽一次快照。mentioned 由卡片算好傳進來（`mentionedItemsCache`；很貴，不在選項頁重掃，design §6.4-8）。
    @MainActor
    static func make(store: LifeStore, subordinateId: UUID, mentioned: [SubordinateItemRef],
                     now: Date = Date()) -> SubExportSnapshot {
        var snap = SubExportSnapshot(subordinateId: subordinateId)
        guard let sub = store.subordinates.first(where: { $0.id == subordinateId }) else {
            snap.isGone = true
            return snap
        }
        let cal = SubExportComposer.gregorian

        // 看板的基本資料（同卡片的 gradeTitleText／departmentText）
        snap.name = sub.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let gt = store.gradeTitles.first(where: { $0.id == sub.gradeTitleId }) {
            snap.gradeTitle = "\(gt.grade) — \(gt.title)"
        } else {
            snap.gradeTitle = sub.jobTitle
        }
        if let dept = store.departments.first(where: { $0.id == sub.departmentId }) {
            snap.department = dept.code.isEmpty ? dept.name : "\(dept.code) \(dept.name)"
        } else {
            snap.department = sub.department
        }
        snap.plantArea = sub.plantArea.trimmingCharacters(in: .whitespacesAndNewlines)
        snap.joinDate = sub.joinDate
        snap.seniority = SubordinateDetailView.seniorityYears(from: sub.joinDate, now: now)
        if let bd = sub.birthday {
            let c = cal.dateComponents([.month, .day], from: bd)
            snap.birthdayText = "\(c.month ?? 1)/\(c.day ?? 1)・\(zodiacSign(for: bd))"
        }

        // 分數：同卡片看板（至今累計）
        var sideRoleDone = 0
        for role in store.sideRoles {
            guard let member = role.sideRoleMembers?.first(where: { $0.linkedPersonId == subordinateId }) else { continue }
            for t in role.sideRoleTasks ?? [] where t.isCompleted && t.assigneeIds?.contains(member.id) == true {
                sideRoleDone += 1
            }
        }
        let itemDone = store.meetingItemCredits()[subordinateId] ?? 0
        let proactivity = sub.proactivityScore(mentionedCount: mentioned.count, sideRoleDone: sideRoleDone, itemDone: itemDone)
        let overall = sub.overallScore(mentionedCount: mentioned.count, sideRoleDone: sideRoleDone, itemDone: itemDone)
        snap.scores = (proactivity, sub.potentialScore, overall)

        snap.tasks = sub.tasks
        snap.meetings = sub.meetings
        snap.reports = sub.weeklyReports
        snap.records = sub.records
        snap.promotions = sub.promotions
        snap.shifts = sub.shifts

        // 人：名字表、id → 部屬（同 meetingItemCredits）
        let subIds = Set(store.subordinates.map { $0.id })
        var names: [UUID: String] = [:]
        var ownerOf: [UUID: UUID] = [:]
        for s in store.subordinates {
            names[s.id] = s.name.trimmingCharacters(in: .whitespacesAndNewlines)
            ownerOf[s.id] = s.id
        }
        for card in store.businessCards where names[card.id] == nil {
            names[card.id] = card.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for p in store.orgPeople {
            if names[p.id] == nil { names[p.id] = p.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard let sid = p.linkedSubordinateId, subIds.contains(sid) else { continue }
            ownerOf[p.id] = sid
            if let cid = p.linkedBusinessCardId { ownerOf[cid] = sid }
        }
        snap.personNames = names.filter { !$0.value.isEmpty }
        snap.ownerSubIds = ownerOf
        var me = Set<UUID>()
        for (pid, sid) in ownerOf where sid == subordinateId { me.insert(pid) }
        snap.meIds = me

        var known: [String] = []
        var seenNames = Set<String>()
        let allNames = store.subordinates.map { $0.name } + store.orgPeople.map { $0.name } + store.businessCards.map { $0.name }
        for raw in allNames {
            let n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard n.count >= 2, !seenNames.contains(n) else { continue }
            seenNames.insert(n)
            known.append(n)
        }
        snap.knownNames = known

        // 機台
        for eq in store.equipmentPool {
            snap.equipmentNames[eq.id] = eq.name.isEmpty ? "未命名設備" : eq.name
            snap.equipmentSystems[eq.id] = eq.system
        }
        let deptNames = Dictionary(store.departments.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let mine = store.equipmentPool
            .filter { $0.ownerId == subordinateId }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        for eq in mine {
            let dept: String = eq.departmentId.flatMap { deptNames[$0] } ?? ""
            snap.equipment.append(EquipmentLine(id: eq.id, name: eq.name.isEmpty ? "未命名設備" : eq.name,
                                                system: eq.system, department: dept,
                                                pmRecords: eq.pmRecords, alarms: eq.alarms))
        }

        // 兼任
        for role in store.sideRoles {
            snap.sideRoleNames[role.id] = SideRoleFormat.displayName(role)
        }
        for part in store.sideRoleParticipations(of: subordinateId) {
            let ts = store.sideRoleTasks(of: part.member.id, in: part.role)
            let done = ts.filter { $0.isCompleted }.count
            snap.sideRoles.append(SideRoleLine(id: part.role.id, name: SideRoleFormat.displayName(part.role),
                                               isActive: part.role.isActiveSideRole,
                                               duty: part.member.dutyInRole.trimmingCharacters(in: .whitespacesAndNewlines),
                                               start: part.role.date, end: part.role.sideRoleEndDate,
                                               done: done, total: ts.count))
        }

        // 被標註（卡片算好的那一份）
        func ownerName(_ id: UUID) -> String {
            let n = store.subordinates.first(where: { $0.id == id })?.name ?? ""
            return n.isEmpty ? "未命名" : n
        }
        for ref in mentioned {
            switch ref {
            case .task(let sid, let t):
                snap.mentioned.append(MentionLine(id: "t_" + t.id.uuidString, kind: "任務",
                                                  topic: t.topic.isEmpty ? "未命名任務" : t.topic,
                                                  ownerName: ownerName(sid), date: t.date,
                                                  isDone: t.isCompleted, isOneOnOne: false))
            case .meeting(let sid, let m):
                let hasOpen = m.allItems.contains { !$0.isCompleted }
                let last = SubExportComposer.lastSession(m, upTo: now, cal: cal) ?? m.date
                snap.mentioned.append(MentionLine(id: "m_" + m.id.uuidString, kind: "會議",
                                                  topic: m.topic.isEmpty ? "未命名會議" : m.topic,
                                                  ownerName: ownerName(sid), date: last,
                                                  isDone: !hasOpen,
                                                  isOneOnOne: SubExportComposer.isOneOnOneName(m.topic)))
            case .report(let sid, let r):
                snap.mentioned.append(MentionLine(id: "r_" + r.id.uuidString, kind: "報告",
                                                  topic: r.topic.isEmpty ? "未命名報告" : r.topic,
                                                  ownerName: ownerName(sid), date: r.date,
                                                  isDone: r.isCompleted, isOneOnOne: false))
            case .leave, .record:
                continue
            }
        }

        // 別人會議交給這位同仁的議程
        for other in store.subordinates where other.id != subordinateId {
            let owner = other.name.isEmpty ? "未命名" : other.name
            for m in other.meetings {
                let isOne = SubExportComposer.isOneOnOneName(m.topic)
                for ctx in m.itemContexts {
                    let owners = Set(ctx.item.assigneeIds.compactMap { ownerOf[$0] })
                    guard owners.contains(subordinateId) else { continue }
                    snap.othersAgenda.append(OthersAgendaLine(meetingId: m.id,
                                                              meetingTopic: m.topic.isEmpty ? "未命名會議" : m.topic,
                                                              ownerName: owner, item: ctx.item,
                                                              sessionDate: ctx.sessionDate, isOneOnOne: isOne))
                }
            }
        }

        // [v25.590 轉組織 v1a-1] 交接：「交接自」、接手的機台、歷程的轉組織列（export/design.md §5.2）。
        // 要退回這一件：刪掉這一段＋上面三個欄位（handovers／orgHistory／equipmentSince）。
        let todayKey = OrgMovePlan.dayKey(now)
        for t in sub.tasks {
            if let r = OrgMoveIndex.receivedChip(t.id, holderId: subordinateId, todayKey: todayKey) {
                snap.handovers[t.id] = HandoverMark(fromName: handoverName(r.fromName), wasOverdue: r.wasOverdue)
            }
        }
        for rep in sub.weeklyReports {
            if let r = OrgMoveIndex.receivedChip(rep.id, holderId: subordinateId, todayKey: todayKey) {
                snap.handovers[rep.id] = HandoverMark(fromName: handoverName(r.fromName), wasOverdue: r.wasOverdue)
            }
        }
        for eq in mine {
            if let r = OrgMoveIndex.receivedByItem[eq.id], r.toId == subordinateId {
                snap.equipmentSince[eq.id] = r.handedAt
            }
        }
        // 這位同仁沒有任何交接單就不建 OrgMoveWorld（快照 0.3 秒重抽一次，省一次整包複製）
        if store.orgMoves.live.contains(where: { $0.personId == subordinateId }) {
            let world = OrgMoveWorld(store: store)
            let rows = OrgMovePlan.historyRows(personId: subordinateId, book: store.orgMoves, world: world)
            for row in rows where !row.isUndone {
                snap.orgHistory.append(SubExportModel.HistoryLine(id: row.moveId, date: row.date,
                                                                  kind: SubExportModel.HistoryLine.orgMoveKind,
                                                                  text: row.detail + "（" + row.sub + "）", note: ""))
            }
        }
        return snap
    }

    /// 交接單上的名字快照（去頭尾空白；空的寫「這位同仁」）
    private static func handoverName(_ raw: String) -> String {
        let n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "這位同仁" : n
    }
}

// MARK: - 篩好的一份（圖、文、件數、提醒都吃它）

struct SubExportModel {
    struct MeetingBlock: Identifiable {
        let meeting: SubordinateMeeting
        /// 沒做完的議程（照場次、截止排）
        let openItems: [SubordinateMeeting.ItemContext]
        /// 固定會議的下一場（沒有＝單次會議或已結束）
        let next: Date?
        /// 固定會議已結束（rule.endDate 已過）
        let isEnded: Bool
        /// 已結束時的最後一場
        let lastSession: Date?
        var id: UUID { meeting.id }
    }

    /// 別人的會議（同一場會議的議程併成一段）
    struct OthersGroup: Identifiable {
        let meetingId: UUID
        let topic: String
        let ownerName: String
        let items: [SubExportSnapshot.OthersAgendaLine]
        var id: UUID { meetingId }
    }

    struct CompletedLine: Identifiable {
        let id: UUID
        let kind: SubExportCompletedKind
        /// 結案的缺失任務（勾了〔缺失任務〕才會在這裡）
        let isDereliction: Bool
        let title: String
        /// 議程＝會議名；報告＝分類；任務＝空
        let sub: String
        let at: Date?
        let due: Date?
    }

    struct HistoryLine: Identifiable {
        /// [v25.590 轉組織 v1a-1] 轉組織那一列的 kind（文字「｜轉組織｜」、圖片藍色雙箭頭圓）
        static let orgMoveKind = "轉組織"

        let id: UUID
        let date: Date
        /// 「升職」「轉組織」
        let kind: String
        let text: String
        let note: String

        var isOrgMove: Bool { kind == HistoryLine.orgMoveKind }
    }

    struct EquipmentRow: Identifiable {
        let line: SubExportSnapshot.EquipmentLine
        let pmCount: Int
        let alarmCount: Int
        let lastPM: Date?
        /// [v25.590 轉組織 v1a-1] 〔只列接手之後〕切過的那一刻（沒切＝nil）：件數後面寫「（11/2 接手之後）」
        var since: Date? = nil
        var id: UUID { line.id }
    }

    struct TimelineLine: Identifiable {
        let id: UUID
        let date: Date
        let isAlarm: Bool
        let machine: String
        /// PM：「停機」「完成復機」「保養」；警報：空
        let phase: String
        /// PM＝保養內容；警報＝警報內容
        let text: String
        let daysAfterPM: Int?
    }

    struct ShiftRun: Identifiable {
        let type: ShiftType
        let start: Date
        let end: Date
        let days: Int
        var id: Date { start }
    }

    let snapshot: SubExportSnapshot
    let options: SubExportOptions
    /// 期間（含頭含尾的那一天 00:00；nil＝不限）
    let rangeStart: Date?
    let rangeEnd: Date?
    let now: Date
    let calendar: Calendar
    /// 會議範圍沒選的（每次照名稱重算、不記）
    let excludedMeetings: Set<UUID>

    var reports: [WeeklyReport] = []
    var meetings: [MeetingBlock] = []
    var othersAgenda: [OthersGroup] = []
    var tasks: [SubordinateTask] = []
    var mentioned: [SubExportSnapshot.MentionLine] = []
    var sideRoles: [SubExportSnapshot.SideRoleLine] = []
    var leaves: [SubordinateRecord] = []
    var completed: [CompletedLine] = []
    var history: [HistoryLine] = []
    var records: [SubExportBlock: [SubordinateRecord]] = [:]
    var equipment: [EquipmentRow] = []
    var timeline: [TimelineLine] = []
    var shiftRuns: [ShiftRun] = []
    /// 看板〔分數〕第一列：期間內的優點、缺點、成就、Miss、請假筆數
    var recordTally: [SubordinateRecordType: Int] = [:]

    init(snapshot: SubExportSnapshot, options: SubExportOptions, rangeStart: Date?, rangeEnd: Date?,
         now: Date, calendar: Calendar, excludedMeetings: Set<UUID>) {
        self.snapshot = snapshot
        self.options = options
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.now = now
        self.calendar = calendar
        self.excludedMeetings = excludedMeetings
    }

    func isSelected(_ b: SubExportBlock) -> Bool { options.blocks.contains(b) }

    /// 這一區會寫出幾列（不管勾沒勾；選項頁每一格右邊的數字）
    func rowCount(_ b: SubExportBlock) -> Int {
        switch b {
        case .reports: return reports.count
        case .meetings: return meetings.count + othersAgenda.count
        case .tasks: return tasks.count
        case .mentioned: return mentioned.count
        case .sideRoles: return sideRoles.count
        case .leaves: return leaves.count
        case .completed: return completed.count
        case .history: return history.count
        case .proCon, .achievements, .improvements, .faults, .missOps: return records[b]?.count ?? 0
        case .equipment: return equipment.count
        case .timeline: return timeline.count
        case .shifts: return shiftRuns.count
        }
    }

    /// 勾了才算（看板小格、底下那條、提醒、能不能按）
    func selectedCount(_ b: SubExportBlock) -> Int { isSelected(b) ? rowCount(b) : 0 }

    var selectedTotal: Int {
        SubExportBlock.allCases.reduce(0) { $0 + selectedCount($1) }
    }

    /// 這份請假的總時數
    var leaveHours: Double {
        leaves.reduce(0) { $0 + ($1.leaveHours ?? 0) }
    }

    /// 排班的總天數（標題「排班（8 天）」）
    var shiftDays: Int {
        shiftRuns.reduce(0) { $0 + $1.days }
    }

    /// 未完成議程的總條數（選項頁「會議」格的小字）
    var openAgendaCount: Int {
        meetings.reduce(0) { $0 + $1.openItems.count } + othersAgenda.reduce(0) { $0 + $1.items.count }
    }

    /// 看板小格（第二列）：這份匯出的件數，照勾的區塊取前 5 格（H10）
    var boardCells: [(label: String, value: Int)] {
        let order: [(SubExportBlock, String)] = [(.tasks, "待辦任務"), (.meetings, "會議"), (.completed, "已完成"),
                                                 (.reports, "未交報告"), (.leaves, "請假"), (.mentioned, "被標註"),
                                                 (.sideRoles, "兼任"), (.equipment, "執掌")]
        var out: [(label: String, value: Int)] = []
        for (b, label) in order where isSelected(b) {
            out.append((label: label, value: rowCount(b)))
            if out.count == 5 { break }
        }
        return out
    }

    /// 看板〔分數〕第一列（H9）：期間內的筆數。請假＝請假那一區同一份（含還沒到的），兩列的「請假」才對得上
    var boardRecordCells: [(label: String, value: Int)] {
        [(label: "優點", value: recordTally[.pro] ?? 0),
         (label: "缺點", value: recordTally[.con] ?? 0),
         (label: "成就", value: recordTally[.achievement] ?? 0),
         (label: "Miss", value: recordTally[.missOperation] ?? 0),
         (label: "請假", value: leaves.count)]
    }

    /// 分頁用的列數（PagedImageExporter 只數 row）：會議一個系列＋它的每條議程各算一列
    var pageRowCount: Int {
        var n = 0
        for b in SubExportBlock.allCases where isSelected(b) {
            if b == .meetings {
                n += meetings.reduce(0) { $0 + 1 + $1.openItems.count }
                n += othersAgenda.reduce(0) { $0 + 1 + $1.items.count }
            } else {
                n += rowCount(b)
            }
        }
        return n
    }

    /// 〔全部一張〕的估計高度（pt；§2.9）
    var estimatedHeight: CGFloat {
        SubExportComposer.estimatedHeight(self)
    }
}

// MARK: - 組字（純函式；對照 sim_export.py）

enum SubExportComposer {
    static let divider = "━━━━━━━━━━━━━━"
    /// 名稱像一對一的會議（judge §4.10：一對一常是考績、家裡的事、想調單位）
    static let oneOnOneWords = ["1on1", "1 on 1", "one on one", "一對一", "面談", "個談", "1:1"]
    /// Calendar .weekday 1＝日 … 7＝六
    static let weekdayChars = ["日", "一", "二", "三", "四", "五", "六"]
    static let fileBase = "部屬卡片"
    static let teamFileBase = "部屬總覽"
    /// 文字超過這個字數，底下那條變橘字（LINE 的上限沒有實測，只說「可能」）
    static let longTextChars = 4_000
    /// 〔全部一張〕超過這個高度會先說字會變小變糊；超過 12,000 不給選
    static let blurHeight: CGFloat = 4_000
    static let maxSingleHeight: CGFloat = 12_000
    /// 分頁超過這個張數，底下那條變橘字
    static let manyPages = 20

    /// 每次都拿一份新的（時區跟著手機現在的設定）
    static var gregorian: Calendar { Calendar(identifier: .gregorian) }

    // MARK: 判斷

    static func isOneOnOneName(_ topic: String) -> Bool {
        let t = topic.lowercased()
        return oneOnOneWords.contains { t.contains($0) }
    }

    /// 會議範圍的預設：名稱像一對一的不勾（每次打開照這條重算、不記）
    static func defaultExcludedMeetings(_ meetings: [SubordinateMeeting]) -> Set<UUID> {
        Set(meetings.filter { isOneOnOneName($0.topic) }.map { $0.id })
    }

    // MARK: 期間

    /// 期間的頭尾（那一天 00:00，含頭含尾；nil＝不限）
    static func periodRange(_ o: SubExportOptions, joinDate: Date?, now: Date, cal: Calendar) -> (start: Date?, end: Date?) {
        let today = cal.startOfDay(for: now)
        switch o.period {
        case .all:
            return (nil, nil)
        case .thisYear:
            let y = cal.component(.year, from: today)
            let s = cal.date(from: DateComponents(year: y, month: 1, day: 1))
            let e = cal.date(from: DateComponents(year: y, month: 12, day: 31))
            return (s, e)
        case .thisMonth:
            let comps = cal.dateComponents([.year, .month], from: today)
            guard let s = cal.date(from: comps),
                  let next = cal.date(byAdding: .month, value: 1, to: s),
                  let e = cal.date(byAdding: .day, value: -1, to: next) else { return (nil, today) }
            return (s, e)
        case .last3Months:
            guard let back = cal.date(byAdding: .month, value: -3, to: today),
                  let s = cal.date(byAdding: .day, value: 1, to: back) else { return (nil, today) }
            return (cal.startOfDay(for: s), today)
        case .custom:
            let s = o.customStart.map { cal.startOfDay(for: $0) }
            let e = o.customEnd.map { cal.startOfDay(for: $0) }
            if let s, let e, s > e { return (e, s) }   // 記住的兩個日子顛倒了就對調，不出空的一份
            return (s, e)
        case .whileMine:
            // v2 起：已轉出的人＝轉進來（或入職）～轉出生效日；這版只有「還在的人」＝入職～今天
            return (joinDate.map { cal.startOfDay(for: $0) }, today)
        }
    }

    /// 這一天在不在期間裡（nil 日子只在「全部」算在內）
    static func inRange(_ d: Date?, _ start: Date?, _ end: Date?, cal: Calendar) -> Bool {
        guard let d else { return start == nil && end == nil }
        let day = cal.startOfDay(for: d)
        if let start, day < start { return false }
        if let end, day > end { return false }
        return true
    }

    /// start～end 這段跟期間有沒有重疊（請假、紀錄、兼任職務）
    static func overlaps(_ start: Date, _ end: Date?, _ rs: Date?, _ re: Date?, cal: Calendar) -> Bool {
        let a = cal.startOfDay(for: start)
        let b = max(a, cal.startOfDay(for: end ?? start))
        if let rs, b < rs { return false }
        if let re, a > re { return false }
        return true
    }

    // MARK: 日期字（西曆）

    /// 今年寫「10/20」、別年寫「2025/7/1」；wd 加「（二）」
    static func md(_ d: Date, wd: Bool = false, now: Date, cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day, .weekday], from: d)
        let thisYear = cal.component(.year, from: now)
        let y = c.year ?? 0, mo = c.month ?? 0, dd = c.day ?? 0
        var s = y == thisYear ? "\(mo)/\(dd)" : "\(y)/\(mo)/\(dd)"
        if wd, let w = c.weekday, (1...7).contains(w) { s += "（\(weekdayChars[w - 1])）" }
        return s
    }

    static func ymd(_ d: Date, cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return "\(c.year ?? 0)/\(c.month ?? 0)/\(c.day ?? 0)"
    }

    /// 「M/d」（部屬總覽用，不管年）
    static func shortMD(_ d: Date, cal: Calendar) -> String {
        let c = cal.dateComponents([.month, .day], from: d)
        return "\(c.month ?? 0)/\(c.day ?? 0)"
    }

    static func hm(_ d: Date, cal: Calendar) -> String {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// 檔名用的時間戳「20261028_1020」（西曆）
    static func fileStamp(_ d: Date, cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: d)
        return String(format: "%04d%02d%02d_%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    /// 單張圖的檔名（不放名字；design §6.6 第 6 題）：「部屬卡片_20261028_1020.jpg」
    static func singleFileName(base: String, now: Date) -> String {
        PagedImageExporter.sanitizeFileName(base) + "_" + fileStamp(now, cal: gregorian) + ".jpg"
    }

    /// 兩個日子差幾天（以日為單位）
    static func dayDiff(from a: Date, to b: Date, cal: Calendar) -> Int {
        cal.dateComponents([.day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: b)).day ?? 0
    }

    static func hoursText(_ h: Double) -> String {
        String(format: "%g", h) + " 小時"
    }

    static func trim(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 頁尾、文字最後一行「美好人生・2026/10/28 10:20 匯出」
    static func footer(now: Date) -> String {
        let g = gregorian
        return "美好人生・" + ymd(now, cal: g) + " " + hm(now, cal: g) + " 匯出"
    }

    // MARK: 會議

    /// 固定會議的下一場（今天這一刻以後、沒取消的第一場）；單次會議回 nil
    static func nextSession(_ m: SubordinateMeeting, now: Date, cal: Calendar) -> Date? {
        guard m.rule != nil else { return nil }
        let horizon = cal.date(byAdding: .day, value: 400, to: now) ?? now
        let occ = m.expandedOccurrences(from: now, horizon: horizon)
        return occ.first(where: { !$0.isCancelled && $0.date > now })?.date
    }

    /// 最近一場（這一刻以前、沒取消）
    static func lastSession(_ m: SubordinateMeeting, upTo now: Date, cal: Calendar) -> Date? {
        let anchor = min(m.rule?.endDate ?? now, now)
        let from = cal.date(byAdding: .day, value: -62, to: anchor) ?? anchor
        let occ = m.expandedOccurrences(from: from, horizon: now)
        return occ.last(where: { !$0.isCancelled && $0.date <= now })?.date
    }

    /// 期間內有沒有開過（沒取消的場次）。固定會議：期間有尾就看到尾、沒有尾就看到今天；單次會議看那一天（含臨時加開的）
    static func hadSession(_ m: SubordinateMeeting, start: Date?, end: Date?, now: Date, cal: Calendar) -> Bool {
        if m.rule == nil {
            if inRange(m.date, start, end, cal: cal) { return true }
            return m.occurrences.contains { !$0.isCancelled && inRange($0.effectiveDate, start, end, cal: cal) }
        }
        let first = cal.startOfDay(for: m.date)
        let lo = max(start ?? first, first)
        let hi = end ?? cal.startOfDay(for: now)
        guard lo <= hi, let hiEnd = cal.date(byAdding: .day, value: 1, to: hi) else { return false }
        // 從 lo 開始展開（expandedOccurrences 會大步跳到附近，不會從系列第一場慢慢走、撞 1,200 次保險絲）
        let occ = m.expandedOccurrences(from: lo, horizon: hiEnd)
        return occ.contains { o in
            let d = cal.startOfDay(for: o.date)
            return !o.isCancelled && d >= lo && d <= hi
        }
    }

    static func isEnded(_ m: SubordinateMeeting, now: Date, cal: Calendar) -> Bool {
        guard let end = m.rule?.endDate else { return false }
        return cal.startOfDay(for: end) < cal.startOfDay(for: now)
    }

    /// 「每週四 10:00」「每週二、四 14:00」「隔週一 09:00」「每日 08:30」「每月 15 日 10:00」
    static func ruleText(_ m: SubordinateMeeting, cal: Calendar) -> String {
        guard let r = m.rule else { return "" }
        let time = hm(m.date, cal: cal)
        switch r.frequency {
        case .daily:
            return "每日 " + time
        case .monthly:
            return "每月 \(cal.component(.day, from: m.date)) 日 " + time
        case .weekly, .biweekly:
            let days: [Int] = r.weekdays.isEmpty ? [cal.component(.weekday, from: m.date)] : r.weekdays.sorted()
            let chars = days.filter { (1...7).contains($0) }.map { weekdayChars[$0 - 1] }
            return r.frequency.rawValue + chars.joined(separator: "、") + " " + time
        }
    }

    /// 會議那一列「每週四 10:00・60 分鐘｜下一場 10/29（四）」或「10/15（四）15:00・60 分鐘」
    static func meetingWhenText(_ b: SubExportModel.MeetingBlock, now: Date, cal: Calendar) -> String {
        let m = b.meeting
        if m.rule == nil {
            return md(m.date, wd: true, now: now, cal: cal) + hm(m.date, cal: cal) + "・\(m.durationMinutes) 分鐘"
        }
        var s = ruleText(m, cal: cal) + "・\(m.durationMinutes) 分鐘"
        if let next = b.next {
            s += "｜下一場 " + md(next, wd: true, now: now, cal: cal)
        } else if b.isEnded {
            if let last = b.lastSession {
                s += "｜已結束（最後一場 " + md(last, now: now, cal: cal) + "）"
            } else {
                s += "｜已結束"
            }
        }
        return s
    }

    /// 議程寫「10/22 那場」；取消的「（取消）」、臨時加開的「（臨時）」、改期的寫改過的那天＋「（改期）」
    static func sessionText(_ ctx: SubordinateMeeting.ItemContext, now: Date, cal: Calendar) -> String {
        var s = md(ctx.sessionDate, now: now, cal: cal) + " 那場"
        if ctx.isCancelled { s += "（取消）" }
        else if ctx.isAdHoc { s += "（臨時）" }
        else if ctx.isRescheduled { s += "（改期）" }
        return s
    }

    /// 議程負責人（不是這位同仁的那幾位）的名字
    static func assigneeOthers(_ item: MeetingItem, _ s: SubExportSnapshot) -> [String] {
        var out: [String] = []
        for id in item.assigneeIds where !s.meIds.contains(id) {
            if let n = s.personNames[id], !n.isEmpty, !out.contains(n) { out.append(n) }
        }
        return out
    }

    /// 這條議程算不算這位同仁的（同 meetingItemCredits：沒指派、或負責人都不是部屬＝會議主人；有指派就看有沒有本人）
    static func isMine(_ item: MeetingItem, _ s: SubExportSnapshot) -> Bool {
        let owners = Set(item.assigneeIds.compactMap { s.ownerSubIds[$0] })
        return owners.isEmpty || owners.contains(s.subordinateId)
    }

    // MARK: 任務

    static func scoreText(_ score: Int) -> String {
        score > 0 ? "+\(score)分" : "\(score)分"
    }

    /// 截止近→遠，沒截止的放最後；同截止看立案日
    static func taskBefore(_ a: SubordinateTask, _ b: SubordinateTask) -> Bool {
        switch (a.dueDate, b.dueDate) {
        case let (x?, y?):
            if x != y { return x < y }
            return a.date < b.date
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return a.date < b.date
        }
    }

    /// 警報任務的來源機台名字、系統別（優先現查機台池，機台被刪退回快照）
    static func alarmInfo(_ t: SubordinateTask, _ s: SubExportSnapshot) -> (name: String, system: String)? {
        guard let link = t.equipmentLink else { return nil }
        let name = s.equipmentNames[link.equipmentId] ?? (link.equipmentName.isEmpty ? "未命名設備" : link.equipmentName)
        let system = s.equipmentSystems[link.equipmentId] ?? link.system
        return (name, system)
    }

    static func sideRoleName(_ t: SubordinateTask, _ s: SubExportSnapshot) -> String? {
        guard let back = t.sideRoleLink else { return nil }
        let n = trim(s.sideRoleNames[back.roleId] ?? "")
        return n.isEmpty ? "兼任職務" : n
    }

    /// 任務的逾期天數（〔逾期、準時與自訂分〕開著、沒做完、截止那天已經過了才有）
    static func overdueDays(_ t: SubordinateTask, now: Date, cal: Calendar) -> Int? {
        guard !t.isCompleted, let due = t.dueDate else { return nil }
        let n = dayDiff(from: due, to: now, cal: cal)
        return n > 0 ? n : nil
    }

    /// 完成章：「準時」「超前」「逾期 3 天」（以日為單位，同 completionTiming）
    static func timingText(at: Date?, due: Date?, cal: Calendar) -> String? {
        guard let at, let due else { return nil }
        let d = dayDiff(from: due, to: at, cal: cal)
        if d == 0 { return "準時" }
        return d < 0 ? "超前" : "逾期 \(d) 天"
    }

    // MARK: [v25.590 轉組織 v1a-1] 交接

    /// 〔只列接手之後〕：since nil＝不切；有值＝那一刻（含）以後才算
    static func notBefore(_ d: Date, _ since: Date?) -> Bool {
        guard let since else { return true }
        return d >= since
    }

    /// 任務、報告那一列後面的「｜交接自 王小明」；marks（〔逾期、準時與自訂分〕）開著、交接時已逾期再接「｜交接時已逾期」。
    /// 不是從交接單接手的（或交接完成、收起來了）回空字串。交接備註不寫（只在交接單的分享）
    static func handoverText(_ id: UUID, _ s: SubExportSnapshot, marks: Bool) -> String {
        guard let h = s.handovers[id] else { return "" }
        var out = "｜交接自 " + h.fromName
        if marks && h.wasOverdue { out += "｜交接時已逾期" }
        return out
    }

    /// 執掌設備件數後面的「（11/2 接手之後）」（沒切＝空字串）
    static func sinceSuffix(_ x: SubExportModel.EquipmentRow, now: Date, cal: Calendar) -> String {
        guard let since = x.since else { return "" }
        return "（" + md(since, now: now, cal: cal) + " 接手之後）"
    }

    /// 選項頁〔只列接手之後〕底下的灰字：「蝕刻機 E-03 從 11/2 接手：PM、警報、件數都從那一刻起算」
    static func handoverTimelineCaption(_ s: SubExportSnapshot, now: Date, cal: Calendar = SubExportComposer.gregorian) -> String {
        let got = s.equipment.filter { s.equipmentSince[$0.id] != nil }
        guard let first = got.first else { return "" }
        if got.count == 1, let since = s.equipmentSince[first.id] {
            return first.name + " 從 " + md(since, now: now, cal: cal) + " 接手：PM、警報、件數都從那一刻起算"
        }
        let names = got.prefix(3).map { $0.name }.joined(separator: "、")
        let more = got.count > 3 ? "等 \(got.count) 台" : ""
        return names + more + "是從交接單收到的：PM、警報、件數都從接手那一刻起算"
    }

    // MARK: 兼任

    /// 「2026/9～12」「2025/3～2026/2」「2026/9 起」
    static func sideRolePeriod(start: Date, end: Date?, cal: Calendar) -> String {
        let a = cal.dateComponents([.year, .month], from: start)
        let head = "\(a.year ?? 0)/\(a.month ?? 0)"
        guard let end else { return head + " 起" }
        let b = cal.dateComponents([.year, .month], from: end)
        if b.year == a.year { return head + "～\(b.month ?? 0)" }
        return head + "～\(b.year ?? 0)/\(b.month ?? 0)"
    }

    // MARK: resolve：圖文共用的一份

    static func resolve(_ s: SubExportSnapshot, _ o: SubExportOptions, excludedMeetings: Set<UUID>,
                        now: Date, cal: Calendar = SubExportComposer.gregorian) -> SubExportModel {
        let range = periodRange(o, joinDate: s.joinDate, now: now, cal: cal)
        let rs = range.start, re = range.end
        var m = SubExportModel(snapshot: s, options: o, rangeStart: rs, rangeEnd: re, now: now,
                               calendar: cal, excludedMeetings: excludedMeetings)
        let keepOpen = o.openItemsIgnorePeriod
        let today = cal.startOfDay(for: now)

        // 任務：只放未完成（做完的在完成項目），截止近→遠
        var tasks: [SubordinateTask] = []
        for t in s.tasks {
            if t.isCompleted { continue }
            if t.isDereliction && !o.taskDereliction { continue }
            if t.equipmentLink != nil && !o.taskAlarm { continue }
            if !keepOpen && !inRange(t.date, rs, re, cal: cal) { continue }
            tasks.append(t)
        }
        m.tasks = tasks.sorted(by: taskBefore)

        // 會議：照會議範圍；期間內有開過、或還有沒做完的議程
        var meetingBlocks: [SubExportModel.MeetingBlock] = []
        for meeting in s.meetings where !excludedMeetings.contains(meeting.id) {
            var open: [SubordinateMeeting.ItemContext] = []
            for ctx in meeting.itemContexts where !ctx.item.isCompleted {
                if keepOpen || inRange(ctx.sessionDate, rs, re, cal: cal) { open.append(ctx) }
            }
            let had = hadSession(meeting, start: rs, end: re, now: now, cal: cal)
            if !had && open.isEmpty { continue }
            open.sort { a, b in
                if a.sessionDate != b.sessionDate { return a.sessionDate < b.sessionDate }
                return (a.item.dueDate ?? .distantFuture) < (b.item.dueDate ?? .distantFuture)
            }
            let next = nextSession(meeting, now: now, cal: cal)
            let ended = next == nil && isEnded(meeting, now: now, cal: cal)
            let last: Date? = ended ? lastSession(meeting, upTo: now, cal: cal) : nil
            meetingBlocks.append(SubExportModel.MeetingBlock(meeting: meeting, openItems: open, next: next,
                                                             isEnded: ended, lastSession: last))
        }
        m.meetings = meetingBlocks

        // 別人會議交給這位同仁的（細項，預設關）；別人的一對一永遠不出去；同一場會議併一段
        if o.othersAgenda {
            var groups: [SubExportModel.OthersGroup] = []
            var order: [UUID] = []
            var byMeeting: [UUID: [SubExportSnapshot.OthersAgendaLine]] = [:]
            var head: [UUID: (topic: String, owner: String)] = [:]
            for x in s.othersAgenda {
                if x.isOneOnOne || x.item.isCompleted { continue }
                if !keepOpen && !inRange(x.sessionDate, rs, re, cal: cal) { continue }
                if byMeeting[x.meetingId] == nil {
                    order.append(x.meetingId)
                    head[x.meetingId] = (x.meetingTopic, x.ownerName)
                }
                byMeeting[x.meetingId, default: []].append(x)
            }
            for id in order {
                let items = (byMeeting[id] ?? []).sorted { $0.sessionDate < $1.sessionDate }
                let h = head[id] ?? (topic: "", owner: "")
                groups.append(SubExportModel.OthersGroup(meetingId: id, topic: h.topic, ownerName: h.owner, items: items))
            }
            m.othersAgenda = groups
        }

        // 完成項目：completedAt 在期間內；議程只算本人的（同 meetingItemCredits）
        var comp: [SubExportModel.CompletedLine] = []
        if o.completedKinds.contains(.task) {
            for t in s.tasks where t.isCompleted && inRange(t.completedAt, rs, re, cal: cal) {
                if t.isDereliction && !o.taskDereliction { continue }
                comp.append(SubExportModel.CompletedLine(id: t.id, kind: .task, isDereliction: t.isDereliction,
                                                         title: t.topic.isEmpty ? "未命名任務" : t.topic, sub: "",
                                                         at: t.completedAt, due: t.dueDate))
            }
        }
        if o.completedKinds.contains(.agenda) {
            for meeting in s.meetings where !excludedMeetings.contains(meeting.id) {
                let topic = meeting.topic.isEmpty ? "會議" : meeting.topic
                for item in meeting.allItems where item.isCompleted && inRange(item.completedAt, rs, re, cal: cal) {
                    guard isMine(item, s) else { continue }
                    comp.append(SubExportModel.CompletedLine(id: item.id, kind: .agenda, isDereliction: false,
                                                             title: item.content.isEmpty ? "未填內容" : item.content,
                                                             sub: topic, at: item.completedAt, due: item.dueDate))
                }
            }
        }
        if o.completedKinds.contains(.report) {
            for r in s.reports where r.isCompleted && inRange(r.completedAt, rs, re, cal: cal) {
                comp.append(SubExportModel.CompletedLine(id: r.id, kind: .report, isDereliction: false,
                                                         title: r.topic.isEmpty ? "未命名報告" : r.topic,
                                                         sub: trim(r.reportType), at: r.completedAt, due: r.date))
            }
        }
        m.completed = comp.sorted { ($0.at ?? .distantPast) > ($1.at ?? .distantPast) }

        // 報告：只放未交的，報告日近→遠
        m.reports = s.reports
            .filter { !$0.isCompleted && (keepOpen || inRange($0.date, rs, re, cal: cal)) }
            .sorted { $0.date < $1.date }

        // 請假：date～endDate 跟期間重疊；還沒到的照「不管期間」開關；全部列（沒有 10 筆上限）
        var leaves: [SubordinateRecord] = []
        for r in s.records where r.type == .leave {
            let future = cal.startOfDay(for: r.date) > today
            if (future && keepOpen) || overlaps(r.date, r.endDate, rs, re, cal: cal) { leaves.append(r) }
        }
        m.leaves = leaves.sorted { $0.date > $1.date }

        // 被標註：別人的一對一永遠不出去；沒做完的照開關，其餘看底層項目的日子
        m.mentioned = s.mentioned.filter { x in
            if x.isOneOnOne { return false }
            return (!x.isDone && keepOpen) || inRange(x.date, rs, re, cal: cal)
        }

        // 兼任：在任的都列；卸任的看職務期間（不跟「不管期間」開關，卸任＝已經發生的事）
        m.sideRoles = s.sideRoles.filter { $0.isActive || overlaps($0.start, $0.end, rs, re, cal: cal) }

        // 歷程（升職＋[v25.590 轉組織 v1a-1] 轉組織；照期間、新到舊混排）
        var hist: [SubExportModel.HistoryLine] = []
        for p in s.promotions where inRange(p.date, rs, re, cal: cal) {
            let to = p.toTitle.isEmpty ? "—" : p.toTitle
            let text = p.fromTitle.isEmpty ? to : p.fromTitle + " → " + to
            hist.append(SubExportModel.HistoryLine(id: p.id, date: p.date, kind: "升職", text: text, note: trim(p.note)))
        }
        for h in s.orgHistory where inRange(h.date, rs, re, cal: cal) {
            hist.append(h)
        }
        m.history = hist.sorted { $0.date > $1.date }

        // 紀錄類（考評）：date～endDate 跟期間重疊，新到舊（優缺點混排）
        var recs: [SubExportBlock: [SubordinateRecord]] = [:]
        var tally: [SubordinateRecordType: Int] = [:]
        for r in s.records where overlaps(r.date, r.endDate, rs, re, cal: cal) {
            tally[r.type, default: 0] += 1
            let block: SubExportBlock?
            switch r.type {
            case .pro, .con: block = .proCon
            case .achievement: block = .achievements
            case .improvement: block = .improvements
            case .fault: block = .faults
            case .missOperation: block = .missOps
            case .leave: block = nil
            }
            if let block { recs[block, default: []].append(r) }
        }
        for (k, v) in recs { recs[k] = v.sorted { $0.date > $1.date } }
        m.records = recs
        m.recordTally = tally

        // 執掌設備（清單＝現在負責的）＋期間內 PM、警報件數；上次 PM 不跟期間（也不跟〔只列接手之後〕：那是機台現在的狀態）。
        // [v25.590 轉組織 v1a-1] 〔只列接手之後〕開著：從交接單收到的機台，PM、警報、件數、時間軸都從交到這位同仁手上那一刻起算
        //（「PM 後 N 天」照樣用機台全部的 PM 算）。要退回這一件：since 一律 nil。
        var eqRows: [SubExportModel.EquipmentRow] = []
        var tl: [SubExportModel.TimelineLine] = []
        for e in s.equipment {
            let since: Date? = o.timelineAfterHandover ? s.equipmentSince[e.id] : nil
            let pmIn = e.pmRecords.filter { inRange($0.date, rs, re, cal: cal) && notBefore($0.date, since) }
            let alIn = e.alarms.filter { inRange($0.date, rs, re, cal: cal) && notBefore($0.date, since) }
            let lastPM = e.pmRecords.map { $0.date }.max()
            eqRows.append(SubExportModel.EquipmentRow(line: e, pmCount: pmIn.count, alarmCount: alIn.count, lastPM: lastPM,
                                                      since: since))

            // 時間軸：PM 分停機／完成復機／保養；警報寫「PM 後 N 天」
            let pmDays = e.pmRecords.map { cal.startOfDay(for: $0.date) }.sorted()
            for p in pmIn {
                let phase: String
                switch p.phase {
                case .some(.shutdown): phase = "停機"
                case .some(.restored): phase = "完成復機"
                case .none: phase = "保養"
                }
                tl.append(SubExportModel.TimelineLine(id: p.id, date: p.date, isAlarm: false, machine: e.name,
                                                      phase: phase, text: trim(p.note), daysAfterPM: nil))
            }
            for a in alIn {
                let aDay = cal.startOfDay(for: a.date)
                let prior = pmDays.last(where: { $0 <= aDay })
                let after: Int? = prior.map { dayDiff(from: $0, to: aDay, cal: cal) }
                tl.append(SubExportModel.TimelineLine(id: a.id, date: a.date, isAlarm: true, machine: e.name,
                                                      phase: "", text: trim(a.content), daysAfterPM: after))
            }
        }
        m.equipment = eqRows
        m.timeline = tl.sorted { $0.date > $1.date }

        // 排班：期間內，連續同一種班併成一段
        let shifts = s.shifts.filter { inRange($0.date, rs, re, cal: cal) }.sorted { $0.date < $1.date }
        var runs: [SubExportModel.ShiftRun] = []
        for sh in shifts {
            let day = cal.startOfDay(for: sh.date)
            if let last = runs.last, last.type == sh.type, dayDiff(from: last.end, to: day, cal: cal) == 1 {
                runs[runs.count - 1] = SubExportModel.ShiftRun(type: last.type, start: last.start, end: day, days: last.days + 1)
            } else if let last = runs.last, dayDiff(from: last.end, to: day, cal: cal) == 0 {
                continue   // 同一天兩筆（舊資料）只算一次
            } else {
                runs.append(SubExportModel.ShiftRun(type: sh.type, start: day, end: day, days: 1))
            }
        }
        m.shiftRuns = runs
        return m
    }

    // MARK: 文字版

    /// 期間的核心字「2026/10/1～10/31」「全部」（圖片每頁抬頭右邊也用這一段）
    static func periodCore(_ m: SubExportModel) -> String {
        let cal = m.calendar
        guard m.rangeStart != nil || m.rangeEnd != nil else { return "全部" }
        let head: String = m.rangeStart.map { ymd($0, cal: cal) } ?? "最早"
        var tail = "今天"
        if let e = m.rangeEnd {
            if let s = m.rangeStart, cal.component(.year, from: e) == cal.component(.year, from: s) {
                tail = md(e, now: m.now, cal: cal)
            } else {
                tail = ymd(e, cal: cal)
            }
        }
        return head + "～" + tail
    }

    /// 「2026/10/1～10/31（還沒做完、還沒到的不管期間都列）」
    static func periodText(_ m: SubExportModel) -> String {
        periodCore(m) + (m.options.openItemsIgnorePeriod ? "（還沒做完、還沒到的不管期間都列）" : "")
    }

    static func text(_ m: SubExportModel) -> String {
        let s = m.snapshot, o = m.options
        let name = s.name.isEmpty ? "這位同仁" : s.name
        var lines: [String] = ["👤 \(name)｜部屬卡片", "🗓 期間：" + periodText(m), divider]
        if o.includeBoard { appendBoard(&lines, m) }
        var empty: [String] = []
        for b in SubExportBlock.allCases where m.isSelected(b) {
            if m.rowCount(b) == 0 {
                empty.append(b.label)
                continue
            }
            lines.append("")
            switch b {
            case .reports: appendReports(&lines, m)
            case .meetings: appendMeetings(&lines, m)
            case .tasks: appendTasks(&lines, m)
            case .mentioned: appendMentioned(&lines, m)
            case .sideRoles: appendSideRoles(&lines, m)
            case .leaves: appendLeaves(&lines, m)
            case .completed: appendCompleted(&lines, m)
            case .history: appendHistory(&lines, m)
            case .proCon, .achievements, .improvements, .faults, .missOps: appendRecords(&lines, m, b)
            case .equipment: appendEquipment(&lines, m)
            case .timeline: appendTimeline(&lines, m)
            case .shifts: appendShifts(&lines, m)
            }
        }
        if !empty.isEmpty {
            lines.append("")
            lines.append("（這段期間沒有：" + empty.joined(separator: "、") + "）")
        }
        lines.append(divider)
        lines.append(footer(now: m.now))
        return lines.joined(separator: "\n")
    }

    private static func appendBoard(_ L: inout [String], _ m: SubExportModel) {
        let s = m.snapshot, o = m.options, cal = m.calendar
        if !trim(s.gradeTitle).isEmpty { L.append("💼 職稱：" + s.gradeTitle) }
        var dept: [String] = []
        if !trim(s.department).isEmpty { dept.append(s.department) }
        if !s.plantArea.isEmpty { dept.append(s.plantArea + " 廠區") }
        if !dept.isEmpty { L.append("🏢 部門：" + dept.joined(separator: "・")) }
        if let jd = s.joinDate {
            var row = "📅 入職：" + ymd(jd, cal: cal)
            if let y = s.seniority { row += "（\(y) 年資歷）" }
            L.append(row)
        }
        if o.boardBirthday, let bd = s.birthdayText { L.append("🎂 生日：" + bd) }
        if o.boardScores {
            L.append("📊 主動性 \(s.scores.proactivity)｜潛力性 \(s.scores.potential)｜綜合 \(s.scores.overall)（至今累計，不跟期間）")
        }
        let cells = m.boardCells
        if !cells.isEmpty {
            L.append("🗂 " + cells.map { "\($0.label) \($0.value)" }.joined(separator: "｜"))
        }
    }

    private static func appendReports(_ L: inout [String], _ m: SubExportModel) {
        L.append("📄 報告（未交 \(m.reports.count)）")
        for r in m.reports {
            var row = "⬜️ "
            let type = trim(r.reportType)
            if !type.isEmpty { row += "【\(type)】" }
            row += (r.topic.isEmpty ? "未命名報告" : r.topic) + "｜報告日 " + md(r.date, wd: true, now: m.now, cal: m.calendar)
            row += handoverText(r.id, m.snapshot, marks: false)   // [v25.590 轉組織 v1a-1]「｜交接自 王小明」
            L.append(row)
            let note = trim(r.note)
            if m.options.includeNotes && !note.isEmpty { L.append("　備註：" + note) }
        }
    }

    private static func appendMeetings(_ L: inout [String], _ m: SubExportModel) {
        let s = m.snapshot, o = m.options, cal = m.calendar
        L.append("👥 會議（\(m.rowCount(.meetings))）")
        for b in m.meetings {
            let mt = b.meeting
            L.append("• " + (mt.topic.isEmpty ? "未命名會議" : mt.topic) + "｜" + meetingWhenText(b, now: m.now, cal: cal))
            let mNote = trim(mt.note)
            if o.includeNotes && !mNote.isEmpty { L.append("　備註：" + mNote) }
            for ctx in b.openItems {
                var row = "　⬜️ " + (ctx.item.content.isEmpty ? "未填內容" : ctx.item.content)
                if mt.rule != nil || ctx.occurrenceId != nil { row += "｜" + sessionText(ctx, now: m.now, cal: cal) }
                if let due = ctx.item.dueDate { row += "｜截止 " + md(due, wd: true, now: m.now, cal: cal) }
                let who = assigneeOthers(ctx.item, s)
                if !who.isEmpty { row += "｜負責 " + who.joined(separator: "、") }
                L.append(row)
                let iNote = trim(ctx.item.note)
                if o.includeNotes && !iNote.isEmpty { L.append("　　備註：" + iNote) }
            }
        }
        let name = s.name.isEmpty ? "這位同仁" : s.name
        for g in m.othersAgenda {
            L.append("• 別人的會議交給\(name)的：\(g.topic)（\(g.ownerName)）")
            for x in g.items {
                var row = "　⬜️ " + (x.item.content.isEmpty ? "未填內容" : x.item.content)
                row += "｜" + md(x.sessionDate, now: m.now, cal: cal) + " 那場"
                if let due = x.item.dueDate { row += "｜截止 " + md(due, wd: true, now: m.now, cal: cal) }
                L.append(row)
                let iNote = trim(x.item.note)
                if o.includeNotes && !iNote.isEmpty { L.append("　　備註：" + iNote) }
            }
        }
    }

    private static func appendTasks(_ L: inout [String], _ m: SubExportModel) {
        let s = m.snapshot, o = m.options, cal = m.calendar
        L.append("📋 任務（未完成 \(m.tasks.count)）")
        for t in m.tasks {
            var row = "⬜️ " + (t.topic.isEmpty ? "未命名任務" : t.topic)
            if let due = t.dueDate {
                row += "｜截止 " + md(due, wd: true, now: m.now, cal: cal)
                if o.includeMarks, let n = overdueDays(t, now: m.now, cal: cal) { row += "（逾期 \(n) 天）" }
            } else {
                row += "｜立案 " + md(t.date, now: m.now, cal: cal)   // 沒截止的寫立案日：看得出是幾個月前開的
            }
            if t.isDereliction { row += "｜⚠️ 缺失任務" }
            if let info = alarmInfo(t, s) {
                row += "｜🚨 " + info.name + (info.system.isEmpty ? "" : "・" + info.system)
            }
            for id in t.linkedEquipmentIds {
                if let n = s.equipmentNames[id] { row += "｜🔧 " + n }
            }
            if let side = sideRoleName(t, s) { row += "｜🔗 兼任 " + side }
            row += handoverText(t.id, s, marks: o.includeMarks)   // [v25.590 轉組織 v1a-1]「｜交接自 王小明｜交接時已逾期」
            if o.includeMarks, let cs = t.customScore, !t.isDereliction { row += "｜" + scoreText(cs) }
            L.append(row)
            if o.taskDetails {
                let content = trim(t.content), action = trim(t.responseAction), result = trim(t.responseResult)
                if !content.isEmpty { L.append("　內容：" + content) }
                if !action.isEmpty { L.append("　處理措施：" + action) }
                if !result.isEmpty { L.append("　回復結果：" + result) }
            }
            let note = trim(t.note)
            if o.includeNotes && !note.isEmpty { L.append("　備註：" + note) }
        }
    }

    private static func appendMentioned(_ L: inout [String], _ m: SubExportModel) {
        L.append("🏷 被標註的項目（\(m.mentioned.count)）")
        for x in m.mentioned {
            L.append("• \(x.kind)「\(x.topic)」｜來自 \(x.ownerName)｜" + md(x.date, now: m.now, cal: m.calendar))
        }
    }

    private static func appendSideRoles(_ L: inout [String], _ m: SubExportModel) {
        L.append("🤝 兼任職務（\(m.sideRoles.count)）")
        for x in m.sideRoles {
            var row = "• " + x.name + (x.isActive ? "（在任）" : "（卸任）")
            if !x.duty.isEmpty { row += "｜" + x.duty }
            row += "｜" + sideRolePeriod(start: x.start, end: x.end, cal: m.calendar)
            if x.total > 0 { row += "｜待辦 \(x.done)/\(x.total)" }
            L.append(row)
        }
    }

    private static func appendLeaves(_ L: inout [String], _ m: SubExportModel) {
        let cal = m.calendar, o = m.options
        let today = cal.startOfDay(for: m.now)
        let h = m.leaveHours
        L.append(h > 0 ? "🌴 請假（\(m.leaves.count) 筆・" + hoursText(h) + "）" : "🌴 請假（\(m.leaves.count) 筆）")
        for r in m.leaves {
            var when = md(r.date, wd: true, now: m.now, cal: cal)
            if let end = r.endDate, cal.startOfDay(for: end) > cal.startOfDay(for: r.date) {
                when += "～" + md(end, wd: true, now: m.now, cal: cal)
            }
            var row = "• " + when
            if let lt = r.leaveType { row += "｜" + lt.rawValue }
            if let hours = r.leaveHours, hours > 0 { row += "｜" + hoursText(hours) }
            if cal.startOfDay(for: r.date) > today { row += "｜還沒到" }
            let reason = trim(r.content)
            if o.leaveReason && !reason.isEmpty { row += "｜事由：" + reason }
            L.append(row)
            let note = trim(r.note)
            if o.includeNotes && !note.isEmpty { L.append("　備註：" + note) }
        }
    }

    /// 完成項目那一列的種類字：「任務」「缺失任務」「議程・P1 製程檢討會」「報告・周報」
    static func completedKindText(_ c: SubExportModel.CompletedLine) -> String {
        switch c.kind {
        case .task: return c.isDereliction ? "缺失任務" : "任務"
        case .agenda: return "議程・" + c.sub
        case .report: return c.sub.isEmpty ? "報告" : "報告・" + c.sub
        }
    }

    private static func appendCompleted(_ L: inout [String], _ m: SubExportModel) {
        L.append("✅ 完成項目（\(m.completed.count)）")
        for c in m.completed {
            var row = "✅ "
            if let at = c.at { row += md(at, now: m.now, cal: m.calendar) + "｜" }
            row += c.title + "｜" + completedKindText(c)
            if m.options.includeMarks, let tm = timingText(at: c.at, due: c.due, cal: m.calendar) { row += "｜" + tm }
            L.append(row)
        }
    }

    private static func appendHistory(_ L: inout [String], _ m: SubExportModel) {
        L.append("🧭 " + SubExportBlock.history.label)
        for h in m.history {
            L.append("• " + ymd(h.date, cal: m.calendar) + "｜" + h.kind + "｜" + h.text)
            if m.options.includeNotes && !h.note.isEmpty { L.append("　備註：" + h.note) }
        }
    }

    static func recordIcon(_ b: SubExportBlock) -> String {
        switch b {
        case .proCon: return "👍"
        case .achievements: return "🏆"
        case .improvements: return "📈"
        case .faults: return "⚠️"
        case .missOps: return "❌"
        default: return "•"
        }
    }

    private static func appendRecords(_ L: inout [String], _ m: SubExportModel, _ b: SubExportBlock) {
        let rows = m.records[b] ?? []
        L.append(recordIcon(b) + " " + b.label + "（\(rows.count)）")
        for r in rows {
            var row = "• "
            if b == .proCon { row += r.type == .pro ? "優點｜" : "缺點｜" }
            row += (r.content.isEmpty ? "未填內容" : r.content) + "｜" + md(r.date, now: m.now, cal: m.calendar)
            if b == .missOps, let sev = r.severity { row += "｜" + sev.rawValue }
            L.append(row)
            let note = trim(r.note)
            if m.options.includeNotes && !note.isEmpty { L.append("　備註：" + note) }
        }
    }

    private static func appendEquipment(_ L: inout [String], _ m: SubExportModel) {
        L.append("🛠 執掌設備（\(m.equipment.count) 台）")
        for x in m.equipment {
            var row = "• " + x.line.name
            if !trim(x.line.system).isEmpty { row += "｜" + x.line.system }
            if !trim(x.line.department).isEmpty { row += "｜" + x.line.department }
            if let last = x.lastPM { row += "｜上次 PM " + md(last, now: m.now, cal: m.calendar) }
            row += "｜這段期間 PM 紀錄 \(x.pmCount)・警報 \(x.alarmCount)"
            row += sinceSuffix(x, now: m.now, cal: m.calendar)   // [v25.590 轉組織 v1a-1]「（11/2 接手之後）」
            L.append(row)
        }
    }

    private static func appendTimeline(_ L: inout [String], _ m: SubExportModel) {
        let cal = m.calendar
        L.append("⏱ PM／警報時間軸（\(m.timeline.count)）")
        for x in m.timeline {
            if x.isAlarm {
                var row = "🚨 " + md(x.date, now: m.now, cal: cal) + " " + hm(x.date, cal: cal) + "｜" + x.machine
                row += "｜" + (x.text.isEmpty ? "警報" : x.text)
                if let n = x.daysAfterPM { row += "｜PM 後 \(n) 天" }
                L.append(row)
            } else {
                var row = "🔧 " + md(x.date, now: m.now, cal: cal) + "｜" + x.machine + "｜PM " + x.phase
                if !x.text.isEmpty { row += "｜" + x.text }
                L.append(row)
            }
        }
    }

    private static func appendShifts(_ L: inout [String], _ m: SubExportModel) {
        let cal = m.calendar
        L.append("🗓 排班（\(m.shiftDays) 天）")
        for r in m.shiftRuns {
            var row = "• " + md(r.start, wd: true, now: m.now, cal: cal)
            if r.days > 1 { row += "～" + md(r.end, wd: true, now: m.now, cal: cal) }
            row += "｜" + r.type.rawValue
            if r.days > 1 { row += "（\(r.days) 天）" }
            L.append(row)
        }
    }

    // MARK: 件數、長度

    /// 勾了但這段期間 0 筆的區塊名（文字最後一行、圖片最後一張的灰字「（這段期間沒有：…）」）
    static func emptyBlockLabels(_ m: SubExportModel) -> [String] {
        SubExportBlock.allCases.filter { m.isSelected($0) && m.rowCount($0) == 0 }.map { $0.label }
    }

    /// 底下那條「任務 6・會議 2・完成 9・請假 4 筆（36 小時）・報告 2・兼任 1・執掌 2 台」
    static func countLine(_ m: SubExportModel) -> String {
        var parts: [String] = []
        for b in SubExportBlock.countOrder where m.isSelected(b) {
            let n = m.rowCount(b)
            switch b {
            case .leaves:
                let h = m.leaveHours
                parts.append(h > 0 ? "請假 \(n) 筆（" + hoursText(h) + "）" : "請假 \(n) 筆")
            case .equipment:
                parts.append("執掌 \(n) 台")
            default:
                parts.append(b.countLabel + " \(n)")
            }
        }
        return parts.joined(separator: "・")
    }

    /// 文字的行數、字數（字數照 unicode scalar 算，跟 Python 的 len 一樣）
    static func textStats(_ text: String) -> (lines: Int, chars: Int) {
        (text.components(separatedBy: "\n").count, text.unicodeScalars.count)
    }

    /// 約幾張：perPage nil＝全部一張
    static func pageEstimate(rows: Int, perPage: Int?) -> Int {
        guard let perPage, rows > 0 else { return 1 }
        let per = max(1, min(perPage, rows))
        return (rows + per - 1) / per
    }

    static func imageRoute(_ m: SubExportModel) -> SubExportImageRoute {
        m.pageRowCount == 0 ? .single : .paged
    }

    /// §2.10：按鈕能不能按、底下那條寫什麼
    static func canExport(_ m: SubExportModel) -> (ok: Bool, reason: String) {
        let o = m.options
        if !o.includeBoard && o.blocks.isEmpty { return (false, "至少選一樣") }
        if !o.includeBoard && m.selectedTotal == 0 { return (false, "這段期間沒有東西可以匯出") }
        return (true, "")
    }

    /// 〔全部一張〕的估計高度（pt）：看板 300（＋分數 70）、區塊標題 54、任務 96＋細節每行 22、會議 62、議程 30…
    static func estimatedHeight(_ m: SubExportModel) -> CGFloat {
        let o = m.options
        var h: CGFloat = 40 + 36 + 40   // 抬頭、頁尾、上下留白
        if o.includeBoard { h += 300 + (o.boardScores ? 70 : 0) + 16 }
        for b in SubExportBlock.allCases where m.isSelected(b) && m.rowCount(b) > 0 {
            h += 54 + 16
            switch b {
            case .tasks:
                for t in m.tasks {
                    h += 96
                    if o.taskDetails {
                        let n = [t.content, t.responseAction, t.responseResult].filter { !trim($0).isEmpty }.count
                        h += CGFloat(22 * n)
                    }
                }
            case .meetings:
                for x in m.meetings { h += 62 + CGFloat(30 * x.openItems.count) }
                for g in m.othersAgenda { h += 62 + CGFloat(30 * g.items.count) }
            case .completed, .reports, .sideRoles, .mentioned:
                h += CGFloat(58 * m.rowCount(b))
            case .leaves, .history, .timeline:
                h += CGFloat(56 * m.rowCount(b))
            case .equipment:
                h += CGFloat(66 * m.rowCount(b))
            case .shifts:
                h += CGFloat(46 * m.rowCount(b))
            case .proCon, .achievements, .improvements, .faults, .missOps:
                h += CGFloat(56 * m.rowCount(b))
            }
        }
        return h
    }

    // MARK: 分享前提醒（§4.2：只點名這份真的寫出來的）

    /// 這份有沒有真的寫出逾期天數、自訂分、完成章、「交接時已逾期」
    static func marksWritten(_ m: SubExportModel) -> Bool {
        guard m.options.includeMarks else { return false }
        if m.isSelected(.tasks) {
            for t in m.tasks {
                if overdueDays(t, now: m.now, cal: m.calendar) != nil && t.dueDate != nil { return true }
                if t.customScore != nil && !t.isDereliction { return true }
                // [v25.590 轉組織 v1a-1]「｜交接時已逾期」也是逾期標記
                if m.snapshot.handovers[t.id]?.wasOverdue == true { return true }
            }
        }
        if m.isSelected(.completed) {
            if m.completed.contains(where: { $0.at != nil && $0.due != nil }) { return true }
        }
        return false
    }

    /// 這份有沒有真的寫出缺失任務（任務區或完成項目裡結案的）
    static func derelictionWritten(_ m: SubExportModel) -> Bool {
        if m.isSelected(.tasks) && m.tasks.contains(where: { $0.isDereliction }) { return true }
        if m.isSelected(.completed) && m.completed.contains(where: { $0.isDereliction }) { return true }
        return false
    }

    /// 全文裡實際出現的別的同仁名字（照第一次出現的順序）：議程負責人、被標註來源、別人會議的主人、
    /// 交接自、內容或備註裡 @ 到的都算；沒勾的區塊不會誤點名
    static func otherNames(in text: String, known: [String], subject: String) -> [String] {
        var found: [(index: Int, name: String)] = []
        var seen = Set<String>()
        for raw in known {
            let n = trim(raw)
            guard n.count >= 2, n != subject, !seen.contains(n) else { continue }
            if !subject.isEmpty && subject.contains(n) { continue }
            seen.insert(n)
            if let r = text.range(of: n) {
                found.append((index: text.distance(from: text.startIndex, to: r.lowerBound), name: n))
            }
        }
        found.sort { a, b in a.index != b.index ? a.index < b.index : a.name < b.name }
        return found.map { $0.name }
    }

    /// 超過 3 位只寫前 3 位＋「等 N 位同仁」
    static func namesPhrase(_ names: [String]) -> String {
        if names.count <= 3 { return names.joined(separator: "、") }
        return names.prefix(3).joined(separator: "、") + "等 \(names.count) 位同仁"
    }

    /// 分享前提醒。text 傳 text(m) 組好的那一份（提醒和內容同一份，不會差一拍）
    static func warning(_ m: SubExportModel, text: String) -> (title: String, message: String) {
        let s = m.snapshot, o = m.options
        let name = s.name.isEmpty ? "這位同仁" : s.name
        var msg = "這份會寫出\(name)的名字"
        if o.includeBoard { msg += "、職稱、部門" }
        let work = SubExportBlock.work.filter { m.selectedCount($0) > 0 }.map { $0.workLabel }
        if !work.isEmpty { msg += "和手上的工作（" + work.joined(separator: "、") + "）" }
        var extra: [String] = []
        if m.selectedCount(.leaves) > 0 {
            let reason = o.leaveReason && m.leaves.contains { !trim($0.content).isEmpty }
            extra.append("請假（日期、假別、時數" + (reason ? "、事由" : "") + "）")
        }
        if o.includeBoard && o.boardBirthday && s.birthdayText != nil { extra.append("生日") }
        if o.includeBoard && o.boardScores { extra.append("分數（至今累計）") }
        if marksWritten(m) { extra.append("逾期、準時標記與自訂分") }
        if derelictionWritten(m) { extra.append("缺失任務") }
        let ev = SubExportBlock.evaluation.filter { m.selectedCount($0) > 0 }.map { $0.label }
        if !ev.isEmpty { extra.append(ev.joined(separator: "、")) }
        if m.selectedCount(.history) > 0 { extra.append(SubExportBlock.history.label) }
        if text.contains("　備註：") { extra.append("備註") }
        if m.selectedCount(.mentioned) > 0 { extra.append("被標註的項目（是別的同仁的事）") }
        if !extra.isEmpty { msg += "，還有你勾的：" + extra.joined(separator: "、") }
        msg += "。"
        let others = otherNames(in: text, known: s.knownNames, subject: s.name)
        if !others.isEmpty { msg += "也會寫出" + namesPhrase(others) + "的名字。" }
        msg += "傳出去就收不回來了，請確認收的人適合看到。"
        return ("要分享\(name)的部屬卡片嗎？", msg)
    }

    // MARK: 會議範圍頁

    struct MeetingScopeRow: Identifiable {
        let id: UUID
        let topic: String
        /// 「每週二 14:00」或「10/15（四）15:00」
        let whenText: String
        /// 期間內有沒有開
        let hadSession: Bool
        /// 未完成議程幾條（不管期間）
        let openCount: Int
        let isOneOnOne: Bool
    }

    static func meetingScopeRows(_ s: SubExportSnapshot, start: Date?, end: Date?, now: Date,
                                 cal: Calendar = SubExportComposer.gregorian) -> [MeetingScopeRow] {
        s.meetings.map { mt -> MeetingScopeRow in
            let when: String = mt.rule == nil
                ? md(mt.date, wd: true, now: now, cal: cal) + hm(mt.date, cal: cal)
                : ruleText(mt, cal: cal)
            return MeetingScopeRow(id: mt.id, topic: mt.topic.isEmpty ? "未命名會議" : mt.topic, whenText: when,
                                   hadSession: hadSession(mt, start: start, end: end, now: now, cal: cal),
                                   openCount: mt.allItems.filter { !$0.isCompleted }.count,
                                   isOneOnOne: isOneOnOneName(mt.topic))
        }
    }

    // MARK: 項目卡（會議細節頁等）的短提醒（§4.4）

    struct ItemShareFacts {
        var subjectName: String
        /// 這份會不會寫出這位同仁的名字（項目卡的圖有「負責部屬」那張卡＝true；文字版沒有寫負責人＝false，E2 B15）
        var writesName = true
        /// 請假，而且事由有填
        var leaveReason = false
        /// 缺失任務
        var dereliction = false
        /// 出圖時任務卡會畫「任務分數」
        var taskScore = false
        /// 考評紀錄（優缺點、成就、改善、缺失、Miss）
        var evaluation = false
        /// 名稱像一對一的會議，而且有議程
        var oneOnOne = false
        /// 議程負責人（不是這位同仁的那幾位）
        var assigneeNames: [String] = []
    }

    static func itemShareWarning(_ f: ItemShareFacts, isImage: Bool) -> (title: String, message: String) {
        let name = trim(f.subjectName).isEmpty ? "這位同仁" : trim(f.subjectName)
        var extra: [String] = []
        if f.leaveReason { extra.append("請假事由") }
        if f.dereliction { extra.append("缺失") }
        if f.taskScore { extra.append("任務分數") }
        if f.evaluation { extra.append("考評紀錄") }
        if f.oneOnOne { extra.append("一對一會議的議程") }
        if !f.assigneeNames.isEmpty { extra.append(namesPhrase(f.assigneeNames) + "的名字") }
        var msg = (isImage ? "這張" : "這份") + (f.writesName ? "會寫出\(name)的名字和這件事的內容" : "會寫出這件事的內容")
        if !extra.isEmpty { msg += "，還有：" + extra.joined(separator: "、") }
        msg += "。傳出去就收不回來了。"
        return ("要分享這一件嗎？", msg)
    }
}

// MARK: - 部屬總覽的匯出（design §8）

enum TeamExportBlock: String, CaseIterable, Identifiable {
    case leaves, reports, meetings, tasks, completed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .leaves: return "請假"
        case .reports: return "報告"
        case .meetings: return "會議"
        case .tasks: return "任務"
        case .completed: return "完成項目"
        }
    }
    var countLabel: String { self == .completed ? "完成" : label }
}

enum TeamTaskKind: String, CaseIterable, Identifiable {
    case day, open
    var id: String { rawValue }
    var label: String { self == .day ? "當日任務" : "未完成任務" }
}

enum TeamMeetingKind: String, CaseIterable, Identifiable {
    case day, items
    var id: String { rawValue }
    var label: String { self == .day ? "當日會議" : "未完成條目" }
}

enum TeamCompletedRange: String, CaseIterable, Identifiable {
    case day, week, month, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .day: return "當天"
        case .week: return "這一週"
        case .month: return "這個月"
        case .all: return "全部"
        }
    }
}

/// 部屬總覽的記住上次：存這台 @AppStorage("team_export_options_v1")，跟卡片那包互不影響。
/// 不記：日期、〔只看○○〕開關、〔圖片｜文字〕。
struct TeamExportOptions: Equatable, Codable {
    var includeBoard = true
    var blocks: Set<TeamExportBlock> = Set(TeamExportBlock.allCases)
    var taskKinds: Set<TeamTaskKind> = Set(TeamTaskKind.allCases)
    var meetingKinds: Set<TeamMeetingKind> = Set(TeamMeetingKind.allCases)
    var completedRange: TeamCompletedRange = .week
    var completedKinds: Set<SubExportCompletedKind> = Set(SubExportCompletedKind.allCases)
    var leaveReason = false
    var includeOneOnOne = false
    var includeDereliction = false

    init() {}

    enum CodingKeys: String, CodingKey {
        case includeBoard, blocks, taskKinds, meetingKinds, completedRange, completedKinds
        case leaveReason, includeOneOnOne, includeDereliction
    }

    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        includeBoard = (try? c.decodeIfPresent(Bool.self, forKey: .includeBoard)) ?? includeBoard
        if let raw = try? c.decodeIfPresent([String].self, forKey: .blocks) {
            blocks = Set(raw.compactMap { TeamExportBlock(rawValue: $0) })
        }
        if let raw = try? c.decodeIfPresent([String].self, forKey: .taskKinds) {
            let v = Set(raw.compactMap { TeamTaskKind(rawValue: $0) })
            if !v.isEmpty { taskKinds = v }
        }
        if let raw = try? c.decodeIfPresent([String].self, forKey: .meetingKinds) {
            let v = Set(raw.compactMap { TeamMeetingKind(rawValue: $0) })
            if !v.isEmpty { meetingKinds = v }
        }
        if let raw = try? c.decodeIfPresent(String.self, forKey: .completedRange),
           let r = TeamCompletedRange(rawValue: raw) {
            completedRange = r
        }
        if let raw = try? c.decodeIfPresent([String].self, forKey: .completedKinds) {
            let v = Set(raw.compactMap { SubExportCompletedKind(rawValue: $0) })
            if !v.isEmpty { completedKinds = v }
        }
        leaveReason = (try? c.decodeIfPresent(Bool.self, forKey: .leaveReason)) ?? leaveReason
        includeOneOnOne = (try? c.decodeIfPresent(Bool.self, forKey: .includeOneOnOne)) ?? includeOneOnOne
        includeDereliction = (try? c.decodeIfPresent(Bool.self, forKey: .includeDereliction)) ?? includeDereliction
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(includeBoard, forKey: .includeBoard)
        try c.encode(blocks.map { $0.rawValue }.sorted(), forKey: .blocks)
        try c.encode(taskKinds.map { $0.rawValue }.sorted(), forKey: .taskKinds)
        try c.encode(meetingKinds.map { $0.rawValue }.sorted(), forKey: .meetingKinds)
        try c.encode(completedRange.rawValue, forKey: .completedRange)
        try c.encode(completedKinds.map { $0.rawValue }.sorted(), forKey: .completedKinds)
        try c.encode(leaveReason, forKey: .leaveReason)
        try c.encode(includeOneOnOne, forKey: .includeOneOnOne)
        try c.encode(includeDereliction, forKey: .includeDereliction)
    }

    static func load(_ json: String) -> TeamExportOptions {
        guard !json.isEmpty, let data = json.data(using: .utf8),
              let o = try? JSONDecoder().decode(TeamExportOptions.self, from: data) else { return TeamExportOptions() }
        return o
    }

    func json() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    mutating func selectAllBlocks() { blocks = Set(TeamExportBlock.allCases) }

    mutating func boardOnly() {
        includeBoard = true
        blocks = []
    }
}

struct TeamExportModel {
    struct CompletedLine: Identifiable {
        let id: UUID
        let sub: Subordinate
        let kind: SubExportCompletedKind
        let title: String
        /// 報告、任務＝名字；議程＝「名字・會議名」
        let subtitle: String
        let at: Date?
        let due: Date?
        let isOneOnOne: Bool
        let isDereliction: Bool
    }

    let options: TeamExportOptions
    /// 畫面上選的那一天
    let day: Date
    let now: Date
    /// 抬頭下一行「🔎 只看：王小明」（沒有篩選＝nil）
    let onlyPersonName: String?
    let knownNames: [String]
    var subs: [Subordinate] = []
    var leaves: [(sub: Subordinate, rec: SubordinateRecord)] = []
    /// 只放未交的（交過的在完成項目）
    var reports: [(sub: Subordinate, report: WeeklyReport, status: TeamDay.ReportStatus)] = []
    var dayMeetings: [(sub: Subordinate, meeting: SubordinateMeeting)] = []
    var meetingItems: [(sub: Subordinate, meeting: SubordinateMeeting, ctx: SubordinateMeeting.ItemContext)] = []
    var dayTasks: [(sub: Subordinate, task: SubordinateTask)] = []
    var openTasks: [(sub: Subordinate, task: SubordinateTask)] = []
    /// 看板「待辦任務」：全部未完成（缺失沒勾就不算它）
    var openTaskTotal = 0
    var completed: [CompletedLine] = []
    /// 完成項目的範圍 [start, end)（nil＝全部）
    var completedStart: Date? = nil
    var completedEnd: Date? = nil

    init(options: TeamExportOptions, day: Date, now: Date, onlyPersonName: String?, knownNames: [String]) {
        self.options = options
        self.day = day
        self.now = now
        self.onlyPersonName = onlyPersonName
        self.knownNames = knownNames
    }

    func isSelected(_ b: TeamExportBlock) -> Bool { options.blocks.contains(b) }

    func rowCount(_ b: TeamExportBlock) -> Int {
        switch b {
        case .leaves: return leaves.count
        case .reports: return reports.count
        case .meetings: return dayMeetings.count + meetingItems.count
        case .tasks: return dayTasks.count + openTasks.count
        case .completed: return completed.count
        }
    }

    func selectedCount(_ b: TeamExportBlock) -> Int { isSelected(b) ? rowCount(b) : 0 }

    var selectedTotal: Int { TeamExportBlock.allCases.reduce(0) { $0 + selectedCount($1) } }

    /// 分頁用的列數（每一筆一列）
    var pageRowCount: Int { selectedTotal }
}

enum TeamExportComposer {

    /// 完成項目的範圍 [start, end)：當天、這一週（TeamDay.weekInterval：手機設定的週起始日）、這個月、全部
    static func completedRange(_ r: TeamCompletedRange, day: Date, cal: Calendar) -> (start: Date?, end: Date?) {
        switch r {
        case .day:
            let s = cal.startOfDay(for: day)
            return (s, cal.date(byAdding: .day, value: 1, to: s))
        case .week:
            let w = TeamDay.weekInterval(for: day, calendar: cal)
            return (w.start, w.end)
        case .month:
            guard let i = cal.dateInterval(of: .month, for: day) else { return (nil, nil) }
            return (i.start, i.end)
        case .all:
            return (nil, nil)
        }
    }

    /// 清單一律呼叫畫面同一支（TeamDay），再套勾選：匯出跟畫面是同一份判斷。
    /// cal 傳畫面用的 Calendar.current（週起始日跟手機設定）；組字另外用西曆。
    static func resolve(subordinates: [Subordinate], onlyPersonId: UUID?, options o: TeamExportOptions,
                        day: Date, now: Date, cal: Calendar, knownNames: [String]) -> TeamExportModel {
        var subs = subordinates
        var onlyName: String? = nil
        if let pid = onlyPersonId {
            subs = subordinates.filter { $0.id == pid }
            onlyName = subs.first.map { $0.name.isEmpty ? "未命名" : $0.name }
        }
        var m = TeamExportModel(options: o, day: day, now: now, onlyPersonName: onlyName, knownNames: knownNames)
        m.subs = subs
        let hideOne = !o.includeOneOnOne
        let derelOK: (SubordinateTask) -> Bool = { t in o.includeDereliction || !t.isDereliction }

        m.leaves = TeamDay.leaves(on: day, in: subs, calendar: cal)
        m.reports = TeamDay.reports(on: day, in: subs, calendar: cal).filter { $0.status != .done }

        if o.meetingKinds.contains(.day) {
            var list: [(sub: Subordinate, meeting: SubordinateMeeting)] = []
            for s in subs {
                for mt in s.meetings where cal.isDate(mt.date, inSameDayAs: day) {
                    if hideOne && SubExportComposer.isOneOnOneName(mt.topic) { continue }
                    list.append((sub: s, meeting: mt))
                }
            }
            m.dayMeetings = list.sorted { $0.meeting.date < $1.meeting.date }
        }
        if o.meetingKinds.contains(.items) {
            var list: [(sub: Subordinate, meeting: SubordinateMeeting, ctx: SubordinateMeeting.ItemContext)] = []
            for s in subs {
                for mt in s.meetings {
                    if hideOne && SubExportComposer.isOneOnOneName(mt.topic) { continue }
                    for ctx in mt.itemContexts where !ctx.item.isCompleted {
                        list.append((sub: s, meeting: mt, ctx: ctx))
                    }
                }
            }
            m.meetingItems = list.sorted { $0.meeting.date > $1.meeting.date }
        }

        let allOpen = TeamDay.incompleteTasks(in: subs).filter { derelOK($0.task) }
        m.openTaskTotal = allOpen.count
        if o.taskKinds.contains(.day) {
            m.dayTasks = TeamDay.dayTasks(on: day, in: subs, calendar: cal).filter { derelOK($0.task) }
        }
        if o.taskKinds.contains(.open) {
            m.openTasks = allOpen
        }

        let range = completedRange(o.completedRange, day: day, cal: cal)
        m.completedStart = range.start
        m.completedEnd = range.end
        func inC(_ d: Date?) -> Bool {
            guard let d else { return range.start == nil && range.end == nil }
            if let s = range.start, d < s { return false }
            if let e = range.end, d >= e { return false }
            return true
        }
        var comp: [TeamExportModel.CompletedLine] = []
        for s in subs {
            let who = s.name.isEmpty ? "未命名" : s.name
            if o.completedKinds.contains(.report) {
                for r in s.weeklyReports where r.isCompleted && inC(r.completedAt) {
                    comp.append(TeamExportModel.CompletedLine(id: r.id, sub: s, kind: .report,
                                                              title: r.topic.isEmpty ? "未命名報告" : r.topic,
                                                              subtitle: who, at: r.completedAt, due: r.date,
                                                              isOneOnOne: false, isDereliction: false))
                }
            }
            if o.completedKinds.contains(.agenda) {
                for mt in s.meetings {
                    let isOne = SubExportComposer.isOneOnOneName(mt.topic)
                    if isOne && hideOne { continue }
                    let sub = who + "・" + (mt.topic.isEmpty ? "會議" : mt.topic)
                    for item in mt.allItems where item.isCompleted && inC(item.completedAt) {
                        comp.append(TeamExportModel.CompletedLine(id: item.id, sub: s, kind: .agenda,
                                                                  title: item.content.isEmpty ? "未填內容" : item.content,
                                                                  subtitle: sub, at: item.completedAt, due: item.dueDate,
                                                                  isOneOnOne: isOne, isDereliction: false))
                    }
                }
            }
            if o.completedKinds.contains(.task) {
                for t in s.tasks where t.isCompleted && derelOK(t) && inC(t.completedAt) {
                    comp.append(TeamExportModel.CompletedLine(id: t.id, sub: s, kind: .task,
                                                              title: t.topic.isEmpty ? "未命名任務" : t.topic,
                                                              subtitle: who, at: t.completedAt, due: t.dueDate,
                                                              isOneOnOne: false, isDereliction: t.isDereliction))
                }
            }
        }
        m.completed = comp.sorted { ($0.at ?? .distantPast) > ($1.at ?? .distantPast) }
        return m
    }

    /// 「2026/10/28 (週三)」（西曆）
    static func shareDate(_ d: Date) -> String {
        let g = SubExportComposer.gregorian
        let w = g.component(.weekday, from: d)
        let wd = (1...7).contains(w) ? SubExportComposer.weekdayChars[w - 1] : ""
        return SubExportComposer.ymd(d, cal: g) + " (週" + wd + ")"
    }

    /// 完成項目範圍的字：「這一週 10/25～10/31」「這個月 10/1～10/31」「當天」「全部」
    static func completedRangeText(_ m: TeamExportModel) -> String {
        let r = m.options.completedRange
        guard r == .week || r == .month, let s = m.completedStart, let e = m.completedEnd else { return r.label }
        let g = SubExportComposer.gregorian
        let last = g.date(byAdding: .day, value: -1, to: e) ?? e
        return r.label + " " + SubExportComposer.shortMD(s, cal: g) + "～" + SubExportComposer.shortMD(last, cal: g)
    }

    /// 「今日」（是今天）或「當日」
    static func dayWord(_ m: TeamExportModel) -> String {
        SubExportComposer.gregorian.isDate(m.day, inSameDayAs: m.now) ? "今日" : "當日"
    }

    /// 勾了但這天 0 筆的（文字最後一行、圖片最後一張的灰字「（這天沒有：…）」），照畫面順序
    static func emptyLabels(_ m: TeamExportModel) -> [String] {
        let o = m.options
        var out: [String] = []
        if m.isSelected(.leaves) && m.leaves.isEmpty { out.append("請假") }
        if m.isSelected(.reports) && m.reports.isEmpty { out.append("報告") }
        if m.isSelected(.meetings) {
            if o.meetingKinds.contains(.day) && m.dayMeetings.isEmpty { out.append("當日會議") }
            if o.meetingKinds.contains(.items) && m.meetingItems.isEmpty { out.append("未完成會議條目") }
        }
        if m.isSelected(.tasks) {
            if o.taskKinds.contains(.day) && m.dayTasks.isEmpty { out.append("當日任務") }
            if o.taskKinds.contains(.open) && m.openTasks.isEmpty { out.append("未完成任務") }
        }
        if m.isSelected(.completed) && m.completed.isEmpty { out.append("完成項目（" + completedRangeText(m) + "）") }
        return out
    }

    static func text(_ m: TeamExportModel) -> String {
        let g = SubExportComposer.gregorian
        let o = m.options
        var L: [String] = ["📊 部屬總覽｜" + shareDate(m.day)]
        if let n = m.onlyPersonName { L.append("🔎 只看：" + n) }
        L.append(SubExportComposer.divider)
        if o.includeBoard {
            let w = dayWord(m)
            L.append("👥 共 \(m.subs.count) 人｜\(w)請假 \(m.leaves.count)｜\(w)會議 \(m.dayMeetings.count)｜待辦任務 \(m.openTaskTotal)")
        }
        var empty: [String] = []
        if m.isSelected(.leaves) {
            if m.leaves.isEmpty { empty.append("請假") } else {
                L.append("")
                L.append("🌴 當日請假（\(m.leaves.count)）")
                for it in m.leaves {
                    var row = "• " + (it.sub.name.isEmpty ? "未命名" : it.sub.name)
                    if let lt = it.rec.leaveType { row += "｜" + lt.rawValue }
                    if let h = it.rec.leaveHours, h > 0 { row += "｜" + SubExportComposer.hoursText(h) }
                    let reason = SubExportComposer.trim(it.rec.content)
                    if o.leaveReason && !reason.isEmpty { row += "｜事由：" + reason }
                    L.append(row)
                }
            }
        }
        if m.isSelected(.reports) {
            if m.reports.isEmpty { empty.append("報告") } else {
                L.append("")
                L.append("📄 報告（本週・待辦 \(m.reports.count)）")
                for it in m.reports {
                    var row = "⬜️ "
                    let type = SubExportComposer.trim(it.report.reportType)
                    if !type.isEmpty { row += "【\(type)】" }
                    row += (it.report.topic.isEmpty ? "未命名報告" : it.report.topic)
                    row += "｜" + (it.sub.name.isEmpty ? "未命名" : it.sub.name) + "｜"
                    let d = SubExportComposer.shortMD(it.report.date, cal: g)
                    row += it.status == .overdue ? "⚠️ 逾期 " + d : d
                    L.append(row)
                }
            }
        }
        if m.isSelected(.meetings) {
            if o.meetingKinds.contains(.day) {
                if m.dayMeetings.isEmpty { empty.append("當日會議") } else {
                    L.append("")
                    L.append("👥 當日會議（\(m.dayMeetings.count)）")
                    for it in m.dayMeetings {
                        var row = "• " + (it.meeting.topic.isEmpty ? "未命名會議" : it.meeting.topic)
                        row += "｜" + (it.sub.name.isEmpty ? "未命名" : it.sub.name)
                        row += "｜" + SubExportComposer.hm(it.meeting.date, cal: g) + "｜\(it.meeting.durationMinutes) 分鐘"
                        L.append(row)
                    }
                }
            }
            if o.meetingKinds.contains(.items) {
                if m.meetingItems.isEmpty { empty.append("未完成會議條目") } else {
                    L.append("")
                    L.append("🗂 未完成會議條目（\(m.meetingItems.count)）")
                    for it in m.meetingItems {
                        var row = "⬜️ " + (it.ctx.item.content.isEmpty ? "未填內容" : it.ctx.item.content)
                        row += "｜" + (it.sub.name.isEmpty ? "未命名" : it.sub.name) + "・"
                        row += it.meeting.topic.isEmpty ? "會議" : it.meeting.topic
                        row += "｜🗓 開會 " + SubExportComposer.shortMD(it.ctx.sessionDate, cal: g)
                        if let due = it.ctx.item.dueDate { row += "｜⏰ 截止 " + SubExportComposer.shortMD(due, cal: g) }
                        L.append(row)
                    }
                }
            }
        }
        if m.isSelected(.tasks) {
            if o.taskKinds.contains(.day) {
                if m.dayTasks.isEmpty { empty.append("當日任務") } else {
                    L.append("")
                    L.append("📋 當日任務（\(m.dayTasks.count)）")
                    for it in m.dayTasks { L.append(taskRow(it.task, it.sub, showCreated: false)) }
                }
            }
            if o.taskKinds.contains(.open) {
                if m.openTasks.isEmpty { empty.append("未完成任務") } else {
                    L.append("")
                    L.append("📋 未完成任務（\(m.openTasks.count)）")
                    for it in m.openTasks { L.append(taskRow(it.task, it.sub, showCreated: true)) }
                }
            }
        }
        if m.isSelected(.completed) {
            let rl = completedRangeText(m)
            if m.completed.isEmpty { empty.append("完成項目（" + rl + "）") } else {
                L.append("")
                L.append("✅ 完成項目（" + rl + "・\(m.completed.count)）")
                for c in m.completed {
                    var row = "🏁 "
                    if let at = c.at { row += SubExportComposer.shortMD(at, cal: g) + "｜" }
                    row += completedEmoji(c.kind) + " " + c.title + "｜" + c.subtitle
                    L.append(row)
                }
            }
        }
        if !empty.isEmpty {
            L.append("")
            L.append("（這天沒有：" + empty.joined(separator: "、") + "）")
        }
        L.append(SubExportComposer.divider)
        L.append(SubExportComposer.footer(now: m.now))
        return L.joined(separator: "\n")
    }

    static func completedEmoji(_ k: SubExportCompletedKind) -> String {
        switch k {
        case .report: return "📄"
        case .agenda: return "👥"
        case .task: return "📋"
        }
    }

    private static func taskRow(_ t: SubordinateTask, _ s: Subordinate, showCreated: Bool) -> String {
        let g = SubExportComposer.gregorian
        var row = "⬜️ " + (t.topic.isEmpty ? "未命名任務" : t.topic) + "｜" + (s.name.isEmpty ? "未命名" : s.name)
        if let due = t.dueDate {
            row += "｜⏰ 截止 " + SubExportComposer.shortMD(due, cal: g)
        } else if showCreated {
            row += "｜立案 " + SubExportComposer.shortMD(t.date, cal: g)
        }
        if t.isDereliction { row += "｜⚠️ 缺失任務" }
        return row
    }

    /// 底下那條「請假 1・報告 3・會議 3・任務 11・完成 1」
    static func countLine(_ m: TeamExportModel) -> String {
        TeamExportBlock.allCases.filter { m.isSelected($0) }
            .map { $0.countLabel + " \(m.rowCount($0))" }
            .joined(separator: "・")
    }

    static func canExport(_ m: TeamExportModel) -> (ok: Bool, reason: String) {
        let o = m.options
        if !o.includeBoard && o.blocks.isEmpty { return (false, "至少選一樣") }
        if !o.includeBoard && m.selectedTotal == 0 { return (false, "這天沒有東西可以匯出") }
        return (true, "")
    }

    static func imageRoute(_ m: TeamExportModel) -> SubExportImageRoute {
        m.pageRowCount == 0 ? .single : .paged
    }

    /// 這份有沒有真的寫出一對一會議的議程
    static func oneOnOneWritten(_ m: TeamExportModel) -> Bool {
        guard m.options.includeOneOnOne else { return false }
        if m.isSelected(.meetings) {
            if m.meetingItems.contains(where: { SubExportComposer.isOneOnOneName($0.meeting.topic) }) { return true }
            if m.dayMeetings.contains(where: { SubExportComposer.isOneOnOneName($0.meeting.topic) }) { return true }
        }
        if m.isSelected(.completed) && m.completed.contains(where: { $0.isOneOnOne }) { return true }
        return false
    }

    static func warning(_ m: TeamExportModel, text: String) -> (title: String, message: String) {
        let people = SubExportComposer.otherNames(in: text, known: m.knownNames, subject: "")
        var msg = "這份會寫出" + (people.isEmpty ? "部屬" : SubExportComposer.namesPhrase(people)) + "的名字"
        let pairs: [(TeamExportBlock, String)] = [(.reports, "報告"), (.meetings, "會議"), (.tasks, "任務"), (.completed, "完成項目")]
        let work = pairs.filter { m.selectedCount($0.0) > 0 }.map { $0.1 }
        if !work.isEmpty { msg += "和手上的工作（" + work.joined(separator: "、") + "）" }
        var extra: [String] = []
        if m.selectedCount(.leaves) > 0 {
            let reason = m.options.leaveReason && m.leaves.contains { !SubExportComposer.trim($0.rec.content).isEmpty }
            extra.append("請假（假別、時數" + (reason ? "、事由" : "") + "）")
        }
        if text.contains("⚠️ 缺失任務") { extra.append("缺失任務") }
        if oneOnOneWritten(m) { extra.append("一對一會議的議程") }
        if !extra.isEmpty { msg += "，還有你勾的：" + extra.joined(separator: "、") }
        msg += "。傳出去就收不回來了，請確認收的人適合看到。"
        return ("要分享部屬總覽嗎？", msg)
    }
}
