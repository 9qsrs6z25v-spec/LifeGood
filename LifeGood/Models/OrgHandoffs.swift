import Foundation

// MARK: - [v25.589 轉組織 v0b] 一筆一筆換人：「交出去時已逾期」的帳＋換人前要問的那一句
//（orgmove/judge.md §7 v0b、§13；orgmove/build/v0b/brief.md §2；sim_v0b.py 照這裡一行一行寫過、跑過）
//
// 為什麼要有這一包：§13 第 2 題「交接那一刻已經逾期的，不管交給誰，逾期扣分都留在原本那位；接手的人拿新的截止日」。
// 任務換人是同一筆搬過去（id 不變），搬走之後原人身上就沒有它了——Subordinate.overdueOpenCount 只數陣列裡的，
// 扣分會跟著任務走（原人的扣分不見、接手的人還沒動手就先被扣）。所以「交出去時已逾期」另外記一筆，記在原人名下。
// • 存在新的同步鍵 life_org_handoffs_v1（OrgHandoffBook.syncKey）：不加在 Subordinate／SubordinateTask 上——
//   還沒更新的 iPad 存一次部屬，會用它自己的 CodingKeys 重寫整包、洗掉不認得的欄位；新鍵它不認得、不會碰。
// • 全部欄位 Optional＋decodeIfPresent（id、itemId、fromId 除外）；entries 逐筆解（一筆壞掉只丟那一筆）。
// • 只增不改：一筆寫下去就不再改；兩台合併＝照 id 取聯集（OrgHandoffBook.merged）；「清除全部資料」才清空。
// • 用法只有一個：Subordinate.overdueOpenCount（TalentMatrixView.swift）多算「記在這位名下、而且這位身上現在沒有照算逾期」的件數
//   （OrgHandoffIndex.overdueIds）。舊 iPad 把任務存回原人身上、陣列那邊已經算到了，就不重複扣（judge §1.4-8）。
// • 隱私：只在 App 裡用（分數、明細那一行）；不上通知、小工具、手錶、分享。名字是快照（之後人改名、刪了也看得懂）。
// • v1a 的交接單（life_org_moves_v1）交出去的已逾期那件，也寫一筆進來（via "orgMove"），扣分只看這一包。

/// 「交出去時已逾期」那一包（同步鍵 life_org_handoffs_v1；跟 iCloud 同步、進完整備份與「職涯」匯出）
struct OrgHandoffBook: Codable, Equatable {
    /// 同步鍵（LifeStore 存讀、CloudSyncManager.syncKeys、匯出用同一個字）
    static let syncKey = "life_org_handoffs_v1"

    /// 每一筆（只增不改）
    var entries: [OrgHandoff]?

    init(entries: [OrgHandoff]? = nil) {
        self.entries = entries
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 逐筆解：一筆壞掉不會讓整包消失（同 WealthTransferBook）
        var list: [OrgHandoff] = []
        var found = false
        if var arr = try? c.nestedUnkeyedContainer(forKey: .entries) {
            found = true
            while !arr.isAtEnd {
                if let e = try? arr.decode(OrgHandoff.self) {
                    list.append(e)
                } else if (try? arr.decode(OrgHandoffSkip.self)) == nil {
                    break
                }
            }
        }
        entries = found ? list : nil
    }

    private enum CodingKeys: String, CodingKey {
        case entries
    }

    var all: [OrgHandoff] { entries ?? [] }
    var isEmpty: Bool { all.isEmpty }

    /// 加一筆（同一個 id 已經有就不加：重做、兩台都做不多一份）
    mutating func append(_ e: OrgHandoff) {
        var list = all
        guard !list.contains(where: { $0.id == e.id }) else { return }
        list.append(e)
        entries = list
    }

    /// 兩台合併（收到 iCloud 的更新、備份「合併」）：照 id 取聯集，本機有的留本機的（一筆寫下去就不再改，兩邊一樣）
    func merged(with other: OrgHandoffBook) -> OrgHandoffBook {
        var list = all
        var seen = Set(list.map(\.id))
        for e in other.all where !seen.contains(e.id) {
            list.append(e)
            seen.insert(e.id)
        }
        var out = self
        out.entries = list.isEmpty ? entries : list
        return out
    }

    /// 部屬 id → 交出去時已逾期、扣分留在這位的任務／週報 id
    func overdueIdsByPerson() -> [UUID: Set<UUID>] {
        var out: [UUID: Set<UUID>] = [:]
        for e in all where e.wasOverdue != false {
            out[e.fromId, default: []].insert(e.itemId)
        }
        return out
    }
}

/// 逐筆解時跳過壞掉的那一筆用（任何 JSON 物件都解得出來）
private struct OrgHandoffSkip: Decodable {}

/// 一筆：某一件在交出去那一刻已經逾期（扣分留 fromId）
struct OrgHandoff: Codable, Equatable, Identifiable {
    let id: UUID
    /// "task"（v0b 只有這種）／"report"（之後的版本）
    var kind: String?
    /// 那一筆（任務、週報）的 id
    let itemId: UUID
    /// 原本那位（部屬 id；扣分留在這位）
    let fromId: UUID
    var fromName: String?
    /// 接手的人（部屬 id）
    var toId: UUID?
    var toName: String?
    /// 交出去那時候的標題（之後任務被刪了也看得懂）
    var title: String?
    /// 原本的截止日「2026-10-20」、給接手的人的新截止日「2026-11-04」
    var dueKey: String?
    var newDueKey: String?
    /// nil／true＝交出去時已逾期（扣分留 fromId；v0b 只寫這種）；false＝只是紀錄、不算扣分（之後的版本）
    var wasOverdue: Bool?
    /// "editor" 任務編輯頁換人／"equipment" 換機台負責人帶走的警報任務／之後 "orgMove" 交接單
    var via: String?
    /// 按下去的時間
    var handedAt: Date?

    init(id: UUID = UUID(), kind: String? = "task", itemId: UUID, fromId: UUID, fromName: String? = nil,
         toId: UUID? = nil, toName: String? = nil, title: String? = nil,
         dueKey: String? = nil, newDueKey: String? = nil, wasOverdue: Bool? = true,
         via: String? = nil, handedAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.itemId = itemId
        self.fromId = fromId
        self.fromName = fromName
        self.toId = toId
        self.toName = toName
        self.title = title
        self.dueKey = dueKey
        self.newDueKey = newDueKey
        self.wasOverdue = wasOverdue
        self.via = via
        self.handedAt = handedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        itemId = try c.decode(UUID.self, forKey: .itemId)
        fromId = try c.decode(UUID.self, forKey: .fromId)
        kind = try? c.decodeIfPresent(String.self, forKey: .kind)
        fromName = try? c.decodeIfPresent(String.self, forKey: .fromName)
        toId = try? c.decodeIfPresent(UUID.self, forKey: .toId)
        toName = try? c.decodeIfPresent(String.self, forKey: .toName)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        dueKey = try? c.decodeIfPresent(String.self, forKey: .dueKey)
        newDueKey = try? c.decodeIfPresent(String.self, forKey: .newDueKey)
        wasOverdue = try? c.decodeIfPresent(Bool.self, forKey: .wasOverdue)
        via = try? c.decodeIfPresent(String.self, forKey: .via)
        handedAt = try? c.decodeIfPresent(Date.self, forKey: .handedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, itemId, fromId, fromName, toId, toName, title
        case dueKey, newDueKey, wasOverdue, via, handedAt
    }
}

// MARK: - 只在記憶體的查表

/// LifeStore.orgHandoffs 的 didSet 重建（照 CardVault.cipherProbe 由 LifeStore 設進靜態變數的先例）。
/// 預設空的（＝沒有任何記錄，分數跟以前一模一樣）：預覽畫面、沒有 LifeStore 的地方也不會錯。
enum OrgHandoffIndex {
    /// 部屬 id → 交出去時已逾期、扣分留在這位的任務／週報 id
    static var overdueIds: [UUID: Set<UUID>] = [:]
    /// [v25.590 轉組織 v1a-1] 部屬 id → 那一筆 id →「E-03 腔體漏率改善 → 陳怡君」（〔不要了〕的：「…（不要了）」）。
    /// 主動性明細「交出去時已逾期 ×1（…）」那一行用（judge §3.3：王小明身上已經沒有 T1 還被扣，要看得懂為什麼）
    static var labels: [UUID: [UUID: String]] = [:]

    static func rebuild(_ book: OrgHandoffBook) {
        overdueIds = book.overdueIdsByPerson()
        var out: [UUID: [UUID: String]] = [:]
        for e in book.all where e.wasOverdue != false {
            let t = (e.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let title = t.isEmpty ? "未命名" : t
            let to = (e.toName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            out[e.fromId, default: [:]][e.itemId] = to.isEmpty ? "\(title)（不要了）" : "\(title) → \(to)"
        }
        labels = out
    }
}

// MARK: - 規則（純函式；sim_v0b.py 的 new_due_task／new_due_alarm／due_text 一字不差）

enum OrgHandoffRules {
    /// 交出去時已逾期的待辦：給接手的人的新截止日＝今天＋7 天，遇六日挪到週一；
    /// 時刻用原本截止的那個時刻（judge §3.2「已逾期的待辦」、§1.4-13）。例：10/28（三）換人、原本 10/20 17:00 → 11/4（三）17:00
    static func newDueForTask(originalDue: Date, now: Date, calendar: Calendar = .current) -> Date {
        newDue(originalDue: originalDue, now: now, days: 7, skipWeekend: true, calendar: calendar)
    }

    /// 換機台負責人帶走的、已逾期的警報任務：今天＋3 天（同警報自動掛任務「發生後 3 天」的規矩，不挪六日），時刻照原本
    static func newDueForAlarm(originalDue: Date, now: Date, calendar: Calendar = .current) -> Date {
        newDue(originalDue: originalDue, now: now, days: 3, skipWeekend: false, calendar: calendar)
    }

    private static func newDue(originalDue: Date, now: Date, days: Int, skipWeekend: Bool,
                               calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: now)
        guard var day = calendar.date(byAdding: .day, value: days, to: start) else { return originalDue }
        if skipWeekend {
            // weekday：1＝星期日 … 7＝星期六
            let wd = calendar.component(.weekday, from: day)
            if wd == 7 {
                day = calendar.date(byAdding: .day, value: 2, to: day) ?? day
            } else if wd == 1 {
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            }
        }
        let t = calendar.dateComponents([.hour, .minute, .second], from: originalDue)
        var c = calendar.dateComponents([.year, .month, .day], from: day)
        c.hour = t.hour
        c.minute = t.minute
        c.second = t.second
        return calendar.date(from: c) ?? day
    }

    /// 「2026-10-20」（交接帳的 dueKey、newDueKey）
    static func dayKey(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04ld-%02ld-%02ld", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static let weekdayChars = ["日", "一", "二", "三", "四", "五", "六"]

    /// 「10/20（二）17:00」；00:00 只寫日子「10/20（二）」
    static func dueText(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.month, .day, .weekday, .hour, .minute], from: d)
        let wd = min(max((c.weekday ?? 1) - 1, 0), 6)
        let day = "\(c.month ?? 0)/\(c.day ?? 0)（\(weekdayChars[wd])）"
        let h = c.hour ?? 0
        let m = c.minute ?? 0
        if h == 0 && m == 0 { return day }
        return day + String(format: "%02ld:%02ld", h, m)
    }
}

// MARK: - 換人前要問的那一句

/// 任務編輯頁、會議編輯頁換人前的確認框（字都在 LifeStore.taskMoveNotice／meetingMoveNotice 組好，畫面只顯示）
struct HandoffNotice: Equatable {
    var title: String
    var message: String
    /// 確認鈕的字（「一起換」「換」）；nil＝不能換（只有〔好〕）
    var confirm: String?
}
