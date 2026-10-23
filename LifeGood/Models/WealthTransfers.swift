import Foundation

// MARK: - [v25.575] 定期轉帳（transfer/judge.md §2、§3；transfer/build/v1a/brief.md §2；sim_v1a.py 照這裡一行一行寫過、跑過）
//
// 一條定期轉帳＝一條「規則」，每一期像固定支出、月薪、定存一樣**算出來**（不寫成 BankDeposit、不幫你轉錢）：
// 轉出帳戶一列「轉給 存錢」、轉入帳戶一列「來自 薪轉」，存摺上、接下來 30 天、30 天內最低、不夠扣、明細每列餘額、
// 淨資產回推、網頁版那包全部自動吃到（WealthFacts.makeAccount 第 ⑥ 段）。
// • 存在新的同步鍵 life_wealth_transfers_v1（WealthTransferBook.syncKey）：不放進財富帳本、不加在 BankDeposit 上——
//   還沒更新的 iPad（25.563～25.574）存一次帳本、里程碑會用它自己的 CodingKeys 重寫整包、洗掉不認得的欄位；新鍵它不碰。
// • 全部欄位 Optional＋decodeIfPresent（id 除外）；rules 逐筆解（一條壞掉只丟那一條）；週期、誰轉、狀態一律**存字串**：
//   不認得的值＝這條不展開但留著（存回去照原樣），不會整包解不開。
// • 日子一律存西曆日字串「2026-10-30」（startKey、endKey、每一期的 key、註記的 dayKey）：存 Date 的話，人在洛杉磯時
//   台北 10/30 00:00 是 10/29，每週五整條變星期四。組回日子只用 WealthTransferSchedule.date(fromKey:)（DateComponents＋WealthCal.calendar）。
//   按的時間（at、updatedAt、createdAt、deletedAt）照舊存 Date。
// • 改金額、改帳戶、暫停＝「從哪一期起長這樣」加一段（segments，v1b 起才有畫面）；跳過、沒轉成、改這一期、補轉＝那一期一個註記（notes，
//   key＝那一期**原本的**日子）。v1a 只寫一段（fromKey ""）、只寫註記；讀的時候照多段算（v1b 寫的照樣認得）。
// • 兩台合併（你和太太各加各的）：照 id；同一條取「最後改的時間」新的（刪掉＝墓碑 deletedAt，勝過比它舊的內容，30 天後存檔時才清）；
//   同一期的註記取 updatedAt 新的。註記〔復原〕不刪掉、留一個只有時間的空註記（不然另一台的舊註記會長回來）。
// • 安全：不存任何帳號（App 不幫你轉，用不到）；名字、備註存檔前掃「像帳號的數字串」（WealthTransferText.accountLikeTail）。

/// 週期（存字串；不認得＝這條不展開但留著）。v4 起加 biweekly、yearly
enum WealthTransferCycle: String {
    case monthly, weekly
}

/// 一期的註記狀態（存字串；不認得＝照規則）
enum WealthTransferStatus: String {
    /// 你按了轉好了（自己轉，v2）
    case done
    /// 這期不轉（銀行自動轉的：〔銀行這期取消了〕；自己轉的：〔這期不轉〕）
    case skip
    /// 沒轉成（兩邊都不算，可以〔今天補轉〕）
    case failed
    /// 沒轉成之後補轉（算在 dayKey 那天）
    case redo
    /// 還沒轉（自己轉，v2；算在 max(那天, 明天)）
    case notYet
}

// MARK: - 整包

struct WealthTransferBook: Codable, Equatable {
    /// 同步鍵（LifeStore 存讀、CloudSyncManager.syncKeys 用同一個字）
    static let syncKey = "life_wealth_transfers_v1"
    /// 刪掉的規則留墓碑幾天（另一台還沒同步的舊內容不會把它長回來）
    static let tombstoneDays = 30

    /// 每一條規則（已結束的也留著：以前的期要照算；刪掉的留墓碑，見 deletedAt）
    var rules: [WealthTransferRule]?
    /// 財富頁「在銀行設了預約轉帳？」那行邀請按過〔不用了〕（v1b）
    var inviteDismissed: Bool?

    init(rules: [WealthTransferRule]? = nil, inviteDismissed: Bool? = nil) {
        self.rules = rules
        self.inviteDismissed = inviteDismissed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 逐筆解：一條壞掉不會讓整包定期轉帳消失（同 WealthDepositBook）
        var list: [WealthTransferRule] = []
        var found = false
        if var arr = try? c.nestedUnkeyedContainer(forKey: .rules) {
            found = true
            while !arr.isAtEnd {
                if let r = try? arr.decode(WealthTransferRule.self) {
                    list.append(r)
                } else if (try? arr.decode(WealthTransferSkip.self)) == nil {
                    break
                }
            }
        }
        rules = found ? list : nil
        inviteDismissed = try? c.decodeIfPresent(Bool.self, forKey: .inviteDismissed)
    }

    private enum CodingKeys: String, CodingKey {
        case rules, inviteDismissed
    }

    var isEmpty: Bool { (rules ?? []).isEmpty && inviteDismissed != true }

    /// 全部（含墓碑）
    var all: [WealthTransferRule] { rules ?? [] }

    /// 沒刪掉的，照建立的先後（同一天兩條的先後＝一套數字第 ⑥ 段的先後；sort 不保證穩定，帶著位置比）
    var live: [WealthTransferRule] {
        let list: [WealthTransferRule] = all.filter { $0.deletedAt == nil }
        return list.enumerated().sorted { x, y in
            let a: Date = x.element.createdAt ?? .distantPast
            let b: Date = y.element.createdAt ?? .distantPast
            if a != b { return a < b }
            return x.offset < y.offset
        }.map { $0.element }
    }

    /// 沒刪掉的那一條
    func rule(_ id: UUID) -> WealthTransferRule? {
        all.first { $0.id == id && $0.deletedAt == nil }
    }

    /// 新增或整條換掉（同一個 id；墓碑也是換掉）
    mutating func upsert(_ r: WealthTransferRule) {
        var list = all
        if let i = list.firstIndex(where: { $0.id == r.id }) { list[i] = r } else { list.append(r) }
        rules = list
    }

    /// 兩台合併（收到 iCloud 的更新、備份「合併」）：照 id；同一條取最後改的時間新的那邊（墓碑也算），一樣新留自己的；
    /// 註記一期一期合（WealthTransferRule.merge）；只有一邊有的照留。邀請按過〔不用了〕取聯集
    func merged(with other: WealthTransferBook) -> WealthTransferBook {
        var list = all
        for theirs in other.all {
            if let i = list.firstIndex(where: { $0.id == theirs.id }) {
                list[i] = WealthTransferRule.merge(list[i], theirs)
            } else {
                list.append(theirs)
            }
        }
        var out = self
        out.rules = list.isEmpty ? rules : list
        if other.inviteDismissed == true { out.inviteDismissed = true }
        return out
    }

    /// 刪掉超過 30 天的墓碑拿掉（存檔時叫；沒有要拿的回 self）
    func purged(now: Date) -> WealthTransferBook {
        let limit: Date = now.addingTimeInterval(-Double(Self.tombstoneDays) * 86_400)
        let kept: [WealthTransferRule] = all.filter { r in
            guard let d = r.deletedAt else { return true }
            return d > limit
        }
        guard kept.count != all.count else { return self }
        var out = self
        out.rules = kept
        return out
    }
}

/// 解不出來的那一條跳過用（任何 JSON 物件都解得出來，只是什麼都不留）
private struct WealthTransferSkip: Decodable {}

// MARK: - 一條規則

struct WealthTransferRule: Codable, Equatable, Identifiable {
    let id: UUID
    /// "monthly" 每月／"weekly" 每週（不認得＝不展開）
    var cycle: String?
    /// 每月第幾天 1～31（31＝每月最後一天）；每週不用（星期幾＝第一期那天）
    var day: Int?
    /// 選 29～31 日時，沒有這天的月份：nil／"last"＝當月最後一天；"next"＝下個月 1 號（國泰世華）
    var short: String?
    /// 每年才用（v4）
    var month: Int?
    /// 第一期（含）「2026-11-06」：一定是一個期的日子
    var startKey: String?
    /// 最後一期（含）＝銀行那邊設到哪天；nil＝不設
    var endKey: String?
    /// nil／"auto"＝銀行會自動轉；"manual"＝我自己轉（v1 一律當作那天轉了）
    var mode: String?
    /// nil＝照當天；"next"／"prev"（v4 起才看）
    var holiday: String?
    /// 從哪一期起長這樣（至少一段，第一段 fromKey ""）
    var segments: [WealthTransferSegment]?
    /// 每一期的註記（key＝那一期原本的日子；沒動過的期不存）
    var notes: [String: WealthTransferNote]?
    /// 你取的名字（空＝「薪轉 → 存錢」）
    var name: String?
    var memo: String?
    /// 這條要不要提醒（nil＝要；v2）
    var remind: Bool?
    /// 改週期、改日子時接上一條（v1b）
    var previousId: UUID?
    var createdAt: Date?
    /// 最後一次改這條（不含註記）
    var updatedAt: Date?
    /// 刪掉的時間＝墓碑（不展開、不列）
    var deletedAt: Date?
    /// 結束的原因：nil 你按的／"accountDeleted"／"accountHidden"
    var endedBy: String?

    init(id: UUID = UUID(), cycle: String? = nil, day: Int? = nil, short: String? = nil, month: Int? = nil,
         startKey: String? = nil, endKey: String? = nil, mode: String? = nil, holiday: String? = nil,
         segments: [WealthTransferSegment]? = nil, notes: [String: WealthTransferNote]? = nil,
         name: String? = nil, memo: String? = nil, remind: Bool? = nil, previousId: UUID? = nil,
         createdAt: Date? = nil, updatedAt: Date? = nil, deletedAt: Date? = nil, endedBy: String? = nil) {
        self.id = id
        self.cycle = cycle
        self.day = day
        self.short = short
        self.month = month
        self.startKey = startKey
        self.endKey = endKey
        self.mode = mode
        self.holiday = holiday
        self.segments = segments
        self.notes = notes
        self.name = name
        self.memo = memo
        self.remind = remind
        self.previousId = previousId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.endedBy = endedBy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        // 每一欄 try?：一欄的型別不對只丟那一欄，不會整條解不開
        cycle = try? c.decodeIfPresent(String.self, forKey: .cycle)
        day = try? c.decodeIfPresent(Int.self, forKey: .day)
        short = try? c.decodeIfPresent(String.self, forKey: .short)
        month = try? c.decodeIfPresent(Int.self, forKey: .month)
        startKey = try? c.decodeIfPresent(String.self, forKey: .startKey)
        endKey = try? c.decodeIfPresent(String.self, forKey: .endKey)
        mode = try? c.decodeIfPresent(String.self, forKey: .mode)
        holiday = try? c.decodeIfPresent(String.self, forKey: .holiday)
        segments = try? c.decodeIfPresent([WealthTransferSegment].self, forKey: .segments)
        notes = try? c.decodeIfPresent([String: WealthTransferNote].self, forKey: .notes)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        memo = try? c.decodeIfPresent(String.self, forKey: .memo)
        remind = try? c.decodeIfPresent(Bool.self, forKey: .remind)
        previousId = try? c.decodeIfPresent(UUID.self, forKey: .previousId)
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        deletedAt = try? c.decodeIfPresent(Date.self, forKey: .deletedAt)
        endedBy = try? c.decodeIfPresent(String.self, forKey: .endedBy)
    }

    private enum CodingKeys: String, CodingKey {
        case id, cycle, day, short, month, startKey, endKey, mode, holiday, segments, notes, name, memo, remind
        case previousId, createdAt, updatedAt, deletedAt, endedBy
    }

    /// 週期（不認得＝nil：不展開）
    var cycleKind: WealthTransferCycle? { cycle.flatMap { WealthTransferCycle(rawValue: $0) } }

    /// 我自己轉（v1 一律當作那天轉了；銀行頁膠囊算它）
    var isManual: Bool { mode == "manual" }

    /// 段照 fromKey 排好（"" 最前）
    var sortedSegments: [WealthTransferSegment] {
        (segments ?? []).sorted { ($0.fromKey ?? "") < ($1.fromKey ?? "") }
    }

    /// 那一期長怎樣：fromKey ≤ key 的最後一段；沒有＝nil（壞掉）
    func segment(at key: String) -> WealthTransferSegment? {
        var found: WealthTransferSegment? = nil
        for s in sortedSegments where (s.fromKey ?? "") <= key { found = s }
        return found
    }

    /// 最後一段（規則頁、卡片「從 → 到」沒有下一期時用）
    var lastSegment: WealthTransferSegment? { sortedSegments.last }

    /// 這條有沒有碰到這個帳戶（任何一段的從或到）
    func touches(_ accountId: UUID) -> Bool {
        (segments ?? []).contains { $0.fromId == accountId || $0.toId == accountId }
    }

    /// 還在跑：沒刪、沒設最後一期，或最後一期是今天（含）以後、而且不早於第一期（〔設錯了，一期都不算〕＝最後一期在第一期前一天）
    func isRunning(todayKey: String) -> Bool {
        guard deletedAt == nil else { return false }
        guard let ek = endKey else { return true }
        if let sk = startKey, ek < sk { return false }
        return ek >= todayKey
    }

    /// 最後改的時間（內容或刪掉，取晚的）：合併時比這個
    var stamp: Date { Swift.max(updatedAt ?? .distantPast, deletedAt ?? .distantPast) }

    /// 兩台的同一條：內容取 stamp 新的那邊（一樣新留 mine）；註記一期一期合，同一期取 updatedAt 新的（一樣新留 mine 的）
    static func merge(_ mine: WealthTransferRule, _ theirs: WealthTransferRule) -> WealthTransferRule {
        var out: WealthTransferRule = theirs.stamp > mine.stamp ? theirs : mine
        var notes: [String: WealthTransferNote] = mine.notes ?? [:]
        for (k, n) in theirs.notes ?? [:] {
            if let m = notes[k] {
                if (n.updatedAt ?? .distantPast) > (m.updatedAt ?? .distantPast) { notes[k] = n }
            } else {
                notes[k] = n
            }
        }
        out.notes = notes.isEmpty ? nil : notes
        return out
    }
}

/// 一段：從 fromKey 那一期（含）起，從哪、到哪、多少
struct WealthTransferSegment: Codable, Equatable {
    /// ""＝第一期起；「2027-01-06」＝那一期（含）起
    var fromKey: String?
    /// 轉出帳戶、幣別（nil＝NT$）；沒有 fromId 的段＝壞掉，略過
    var fromId: UUID?
    var fromCode: String?
    /// 轉入帳戶、幣別
    var toId: UUID?
    var toCode: String?
    /// 每期轉出多少（轉出幣別）；0＝暫停
    var amount: Double?
    /// 對方收到多少（兩邊幣別不同才有，v4；寫死，不跟設定的匯率）
    var toAmount: Double?

    init(fromKey: String? = "", fromId: UUID? = nil, fromCode: String? = nil, toId: UUID? = nil,
         toCode: String? = nil, amount: Double? = nil, toAmount: Double? = nil) {
        self.fromKey = fromKey
        self.fromId = fromId
        self.fromCode = fromCode
        self.toId = toId
        self.toCode = toCode
        self.amount = amount
        self.toAmount = toAmount
    }
}

/// 一期的註記（只存你動過的）
struct WealthTransferNote: Codable, Equatable {
    /// WealthTransferStatus 的 rawValue；nil＝照規則
    var status: String?
    /// 這期實際哪天（改日子、補轉）「2026-11-09」
    var dayKey: String?
    /// 這期實際轉多少
    var amount: Double?
    /// 這期對方實際收到多少（換匯，v4）
    var toAmount: Double?
    /// 這期在那天對存摺之後才扣（轉出那邊）／才進（轉入那邊）：同一天排在對存摺後面
    var lateOut: Bool?
    var lateIn: Bool?
    /// 你按的時間
    var at: Date?
    /// 這個註記最後改的時間（合併時同一期取新的）
    var updatedAt: Date?

    init(status: String? = nil, dayKey: String? = nil, amount: Double? = nil, toAmount: Double? = nil,
         lateOut: Bool? = nil, lateIn: Bool? = nil, at: Date? = nil, updatedAt: Date? = nil) {
        self.status = status
        self.dayKey = dayKey
        self.amount = amount
        self.toAmount = toAmount
        self.lateOut = lateOut
        self.lateIn = lateIn
        self.at = at
        self.updatedAt = updatedAt
    }

    var statusKind: WealthTransferStatus? { status.flatMap { WealthTransferStatus(rawValue: $0) } }
}

// MARK: - 一期（展開出來的；只在記憶體）

struct WealthTransferPeriod: Identifiable, Equatable {
    enum State: Equatable {
        /// 日子還沒到（算進接下來、最低、不夠扣）
        case planned
        /// 日子到了（含今天）：銀行自動轉＝當作轉了（v1 自己轉的也一樣）；補轉的照補轉那天
        case done
        /// 這期不轉（兩邊都不算）
        case skipped
        /// 沒轉成（兩邊都不算）
        case failed
        /// 落在暫停那一段（金額 0；不算）
        case paused
        /// 那一段沒有從或到（壞掉；不算）
        case broken
    }

    let ruleId: UUID
    /// 那一期原本的日子「2026-12-06」（註記的 key）
    let key: String
    /// 原本的日子 00:00
    let original: Date
    /// 實際那天 00:00（改了日子、補轉、v2 還沒轉往後挪）
    let day: Date
    let fromId: UUID?
    let fromCode: String
    let toId: UUID?
    let toCode: String
    /// 轉出多少（轉出幣別）
    let amount: Double
    /// 對方收到多少（同幣別＝amount）
    let toAmount: Double
    let state: State
    /// 註記的狀態（原字；nil＝照規則）
    let status: WealthTransferStatus?
    /// 這期改過（金額或日子；補轉不算）
    let edited: Bool
    let lateOut: Bool
    let lateIn: Bool

    var id: String { ruleId.uuidString + "-" + key }

    /// 算進兩個帳戶（還沒到、已轉）
    var counts: Bool { state == .planned || state == .done }
}

// MARK: - 展開

enum WealthTransferSchedule {
    /// 一條最多幾期（同 fixedPeriods；每週＝23 年）
    static let maxPeriods = 1200

    /// 「2026-10-30」→ 手機日曆的那天 00:00（DateComponents 組回；在哪個時區都是那一天）。格式不對、沒有這天（2-30）＝nil
    static func date(fromKey key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        var c = DateComponents()
        c.year = y
        c.month = m
        c.day = d
        guard let date = WealthCal.calendar.date(from: c) else { return nil }
        // 2026-02-30 這種 Calendar 會往後挪到 3/2：組回來的不是同一天就當壞的
        guard WealthCal.dayKey(date) == key else { return nil }
        return WealthCal.day(date)
    }

    /// 那天的 key「2026-10-30」
    static func key(of d: Date) -> String { WealthCal.dayKey(d) }

    /// y 年 m 月（m 可以超過 12、小於 1，自己進位）第 day 天 00:00；那個月沒有這天：short "next"＝下個月 1 號，其他＝月底
    static func monthDate(year: Int, month: Int, day: Int, short: String?) -> Date? {
        let total = year * 12 + (month - 1)
        let y = total >= 0 ? total / 12 : (total - 11) / 12
        let m = total - y * 12 + 1
        var c = DateComponents()
        c.year = y
        c.month = m
        c.day = 1
        let cal = WealthCal.calendar
        guard let first = cal.date(from: c) else { return nil }
        let last = cal.range(of: .day, in: .month, for: first)?.count ?? 28
        let d = Swift.min(Swift.max(day, 1), 31)
        if d <= last {
            c.day = d
            return cal.date(from: c)
        }
        if short == "next" {
            return cal.date(byAdding: .month, value: 1, to: first)
        }
        c.day = last
        return cal.date(from: c)
    }

    /// 照規則算的「原本的日子」：第一期（含）起，到 through（含）與最後一期（含）為止，最多 1200 期（一次加，D8：
    /// 每月＝第一期那個月起第 k 個月的第 day 天；每週＝第一期＋7k 天）。週期不認得、沒有第一期＝空的
    static func originalDates(_ r: WealthTransferRule, through until: Date) -> [Date] {
        guard let kind = r.cycleKind, let sk = r.startKey, let start = date(fromKey: sk) else { return [] }
        var limit = WealthCal.day(until)
        if let ek = r.endKey, let end = date(fromKey: ek), end < limit { limit = end }
        var out: [Date] = []
        switch kind {
        case .weekly:
            var k = 0
            while k < maxPeriods {
                let d = WealthCal.addDays(7 * k, to: start)
                if d > limit { break }
                out.append(d)
                k += 1
            }
        case .monthly:
            let comps = WealthCal.calendar.dateComponents([.year, .month, .day], from: start)
            guard let y = comps.year, let m = comps.month else { return [] }
            let dayOfMonth: Int = r.day ?? (comps.day ?? 1)
            // 從第一期的前一個月算起：〔下個月 1 號〕那種，上個月那期可能就落在第一期那天（11 月那期＝12/1）
            var k = -1
            while out.count < maxPeriods && k <= maxPeriods {
                guard let d = monthDate(year: y, month: m + k, day: dayOfMonth, short: r.short) else { break }
                k += 1
                if d < start { continue }
                if d > limit { break }
                out.append(d)
            }
        }
        return out
    }

    /// 每一期（含這期不轉、沒轉成、暫停、壞掉的：規則頁要列；算數字只用 counts 的）。today：今天 00:00
    static func periods(_ r: WealthTransferRule, through until: Date, today: Date) -> [WealthTransferPeriod] {
        let t = WealthCal.day(today)
        let tomorrow = WealthCal.addDays(1, to: t)
        var out: [WealthTransferPeriod] = []
        for d in originalDates(r, through: until) {
            let k = key(of: d)
            let seg = r.segment(at: k)
            let n: WealthTransferNote? = r.notes?[k]
            let st: WealthTransferStatus? = n?.statusKind
            var day = d
            if let dk = n?.dayKey, let moved = date(fromKey: dk) { day = moved }
            let amount: Double = n?.amount ?? (seg?.amount ?? 0)
            let toAmount: Double = n?.toAmount ?? (seg?.toAmount ?? amount)
            let state: WealthTransferPeriod.State
            if seg == nil || seg?.fromId == nil || seg?.toId == nil {
                state = .broken
            } else if amount <= 0.004 {
                state = .paused
            } else if st == .skip {
                state = .skipped
            } else if st == .failed {
                state = .failed
            } else {
                if st == .notYet && day < tomorrow { day = tomorrow }
                state = day <= t ? .done : .planned
            }
            let edited: Bool = n?.amount != nil || (n?.dayKey != nil && st != .redo)
            out.append(WealthTransferPeriod(
                ruleId: r.id, key: k, original: d, day: day, fromId: seg?.fromId,
                fromCode: WealthFacts.norm(seg?.fromCode ?? "NT$"), toId: seg?.toId,
                toCode: WealthFacts.norm(seg?.toCode ?? "NT$"), amount: amount, toAmount: toAmount, state: state,
                status: st, edited: edited, lateOut: n?.lateOut == true, lateIn: n?.lateIn == true))
        }
        return out
    }

    /// 今天以後（不含今天）第一個算進去的期（暫停、這期不轉的跳過）；看到 400 天後為止
    static func next(_ r: WealthTransferRule, today: Date) -> WealthTransferPeriod? {
        let t = WealthCal.day(today)
        let list = periods(r, through: WealthCal.addDays(400, to: t), today: t)
        return list.first { $0.counts && $0.day > t }
    }

    /// 今天（含）以前最近的一期原本的日子（〔結束〕「最後一次是哪一期？」預設）；沒有＝nil
    static func lastOriginal(_ r: WealthTransferRule, onOrBefore day: Date) -> Date? {
        originalDates(r, through: day).last
    }

    /// 新增表單：週期、哪天（每月 day＋short；每週 weekday 1＝星期日…7＝星期六）在 from 那天（含）以後的第一期
    static func firstDate(cycle: WealthTransferCycle, day: Int, short: String?, weekday: Int,
                          onOrAfter from: Date) -> Date? {
        let d0 = WealthCal.day(from)
        switch cycle {
        case .weekly:
            let w = WealthCal.calendar.component(.weekday, from: d0)
            let diff = ((weekday - w) % 7 + 7) % 7
            return WealthCal.addDays(diff, to: d0)
        case .monthly:
            let comps = WealthCal.calendar.dateComponents([.year, .month], from: d0)
            guard let y = comps.year, let m = comps.month else { return nil }
            var best: Date? = nil
            for k in -1...1 {
                guard let d = monthDate(year: y, month: m + k, day: day, short: short), d >= d0 else { continue }
                if let b = best, b <= d { continue }
                best = d
            }
            return best
        }
    }

    /// 〔共幾次〕：第 n 期（從第一期算，含）原本的日子（不看 endKey）；n < 1 或算不出來＝nil
    static func nthDate(_ r: WealthTransferRule, times n: Int) -> Date? {
        guard n >= 1, let sk = r.startKey, let start = date(fromKey: sk) else { return nil }
        var open = r
        open.endKey = nil
        let until = WealthCal.addDays(Swift.min(n, maxPeriods) * 31 + 31, to: start)
        let list = originalDates(open, through: until)
        guard list.count >= n else { return list.last }
        return list[n - 1]
    }

    /// 〔到哪天〕：那天（含）以前最後一期原本的日子（不看 endKey）；第一期以前＝nil
    static func lastDate(_ r: WealthTransferRule, onOrBefore day: Date) -> Date? {
        var open = r
        open.endKey = nil
        return originalDates(open, through: day).last
    }
}

// MARK: - 一套數字用的：每一期動到哪個帳戶（WealthFacts.makeAccount 第 ⑥ 段）

/// 一期動到一個帳戶的一筆（轉出那邊 delta 負、轉入那邊正）
struct WealthTransferRef {
    /// 「tr-<規則>-<key>-o」（轉出）／「…-i」（轉入）：換匯兩列在同一個帳戶也不撞
    let id: String
    let accountId: UUID
    let day: Date
    let code: String
    let delta: Double
    /// 「轉給 存錢」「來自 薪轉」（對方刪掉了：「轉給 別的帳戶」）
    let title: String
    /// 明細細字（WealthLedgerRow.note）：銀行自動轉「每週五」「每月 6 日」「每月最後一天」；自己轉「自己轉」
    let note: String
    let ruleId: UUID
    let key: String
    /// 這一邊記了「對存摺之後才扣／才進」：同一天排在對存摺後面
    let late: Bool
    let manual: Bool
}

extension WealthTransferSchedule {
    /// 每一條沒刪掉的規則展開到 horizon（含），照帳戶分好（一次掃）。bankIds：銀行帳戶（含收起來的；證券戶、找不到的那一邊不記）。
    /// names：帳戶的顯示名（暱稱 → 銀行名）
    static func refs(_ book: WealthTransferBook, bankIds: Set<UUID>, names: [UUID: String], today: Date,
                     horizon: Date) -> [UUID: [WealthTransferRef]] {
        var out: [UUID: [WealthTransferRef]] = [:]
        // 改了日子的那期可能往前挪：多展開一個月再照實際那天篩
        let until = WealthCal.addDays(31, to: horizon)
        for r in book.live {
            let manual = r.isManual
            let note: String = manual ? "自己轉" : WealthTransferText.cycleText(r)
            for p in periods(r, through: until, today: today) where p.counts {
                guard p.day <= horizon else { continue }
                let base = "tr-" + r.id.uuidString + "-" + p.key
                if let f = p.fromId, bankIds.contains(f), p.amount > 0.004 {
                    let other: String = p.toId.flatMap { names[$0] } ?? "別的帳戶"
                    out[f, default: []].append(WealthTransferRef(
                        id: base + "-o", accountId: f, day: p.day, code: p.fromCode, delta: -p.amount,
                        title: "轉給 " + other, note: note, ruleId: r.id, key: p.key, late: p.lateOut, manual: manual))
                }
                if let t = p.toId, bankIds.contains(t), p.toAmount > 0.004 {
                    let other: String = p.fromId.flatMap { names[$0] } ?? "別的帳戶"
                    out[t, default: []].append(WealthTransferRef(
                        id: base + "-i", accountId: t, day: p.day, code: p.toCode, delta: p.toAmount,
                        title: "來自 " + other, note: note, ruleId: r.id, key: p.key, late: p.lateIn, manual: manual))
                }
            }
        }
        return out
    }
}

// MARK: - 一套數字裡的「一條定期轉帳」（財富頁定期轉帳卡、規則頁、要確認用；只在記憶體）

extension WealthFacts {
    struct TransferRule: Identifiable {
        let id: UUID
        /// 存的那一條（規則頁、一期小表單照它展開）
        let rule: WealthTransferRule
        /// 你取的名字；空＝「薪轉 → 存錢」
        let title: String
        /// 下一期那一段（沒有下一期＝最後一段）的從、到
        let fromId: UUID?
        let toId: UUID?
        /// 帳戶的顯示名；找不到的帳戶＝「別的帳戶」
        let fromName: String
        let toName: String
        /// 每期多少（下一期；沒有下一期＝最後一段）
        let amount: Double
        /// 轉出幣別（v1 一律 NT$）
        let code: String
        /// 「每週五」「每月 6 日」「每月最後一天」
        let cycleText: String
        /// 「銀行自動轉」「自己轉」
        let modeText: String
        let isManual: Bool
        /// 今天以後下一個算進去的期（沒有＝nil）
        let next: WealthTransferPeriod?
        /// 今天（含）以前最近一期原本的日子
        let lastPast: Date?
        /// 第一期、最後一期（nil＝不設）
        let firstDay: Date?
        let lastDay: Date?
        /// 已結束（最後一期在今天以前，或設錯了一期都不算）
        let isEnded: Bool
        /// 從／到的帳戶收起來了、找不到了（舊版收起來、刪掉的）
        let fromHidden: Bool
        let toHidden: Bool
        let fromMissing: Bool
        let toMissing: Bool
        /// 一個月大約轉出多少（每月＝每期；每週＝每期 × 52 ÷ 12）；已結束＝0
        let monthlyOut: Double
        /// 建立的先後（同一天 ⑥ 的先後；卡片頁排序第二層）
        let order: Int
    }

    /// 那一條（沒刪掉的；已結束的也找得到）
    func transferRule(_ id: UUID?) -> TransferRule? {
        guard let id else { return nil }
        return transferRules.first { $0.id == id }
    }

    /// 還在跑的（財富頁定期轉帳卡上面那幾列）
    var runningTransfers: [TransferRule] { transferRules.filter { !$0.isEnded } }

    /// 還在跑、碰到這個帳戶的（收起來、刪帳戶確認框那一句）
    func runningTransfers(touching accountId: UUID) -> [TransferRule] {
        runningTransfers.filter { $0.rule.touches(accountId) }
    }

    /// 收起來確認框多一句：「有 1 條定期轉帳轉進這裡，會一起結束」；沒有＝nil
    func hideTransferSentence(_ accountId: UUID) -> String? {
        let list = runningTransfers(touching: accountId)
        guard !list.isEmpty else { return nil }
        let outs = list.filter { $0.fromId == accountId }.count
        let ins = list.filter { $0.toId == accountId }.count
        let how: String
        if outs > 0 && ins == 0 { how = "從這裡轉出" } else if ins > 0 && outs == 0 { how = "轉進這裡" } else { how = "從這裡轉出或轉進" }
        return "有 \(list.count) 條定期轉帳\(how)，會一起結束"
    }

    /// 那一條每一期（規則頁；含這期不轉、沒轉成、暫停的）到 through（含）
    func transferPeriods(_ id: UUID, through: Date) -> [WealthTransferPeriod] {
        guard let r = transferBook.rule(id) else { return [] }
        return WealthTransferSchedule.periods(r, through: through, today: today)
    }

    /// 那一條的那一期（key＝原本的日子）
    func transferPeriod(_ id: UUID, key: String) -> WealthTransferPeriod? {
        guard let r = transferBook.rule(id), let d = WealthTransferSchedule.date(fromKey: key) else { return nil }
        let until = WealthCal.addDays(62, to: Swift.max(d, today))
        return WealthTransferSchedule.periods(r, through: until, today: today).first { $0.key == key }
    }

    /// 那一期在轉出帳戶 30 天內「扣完會是負的」那一筆（一期小表單第一行橘字「銀行可能轉不過去」）；沒有＝nil
    func transferShortage(_ id: UUID, key: String) -> WealthShortage? {
        for a in accounts {
            if let s = a.shortages.first(where: { $0.transferRuleId == id && $0.periodKey == key }) { return s }
        }
        return nil
    }

    /// 對存摺表單「這天還有：來自 薪轉 +3,000（定期・每週五）」的一邊
    struct TransferSide: Identifiable {
        let ruleId: UUID
        /// 那一期原本的日子（註記的 key）
        let key: String
        /// true＝這個帳戶是轉出那邊（記 lateOut）；false＝轉入那邊（記 lateIn）
        let out: Bool
        /// 這一邊的金額（正的）
        let amount: Double
        let code: String
        /// 「來自 薪轉」「轉給 存錢」
        let title: String
        /// 「定期・每週五」「定期・自己轉」
        let note: String
        /// 現在已經記了「對存摺之後才進／才扣」
        let late: Bool
        /// 選〔還沒有〕時「App 算的」要加多少（轉入那邊 −金額、轉出那邊 ＋金額：這一筆改排在對存摺後面，那天結束時對存摺之前沒有它）
        var appDelta: Double { out ? amount : -amount }
        var id: String { ruleId.uuidString + "-" + key + (out ? "-o" : "-i") }
    }

    /// 這個帳戶 day 那天算進去的定期轉帳每一邊（轉出、轉進都算；照建立的先後）：對存摺表單問「存摺上已經有了嗎」
    func transferSides(accountId: UUID, on day: Date) -> [TransferSide] {
        let d = WealthCal.day(day)
        var out: [TransferSide] = []
        for r in transferBook.live {
            let note = "定期・" + (r.isManual ? "自己轉" : WealthTransferText.cycleText(r))
            for p in WealthTransferSchedule.periods(r, through: WealthCal.addDays(31, to: d), today: today)
                where p.counts && p.day == d {
                if p.fromId == accountId {
                    let other = p.toId.flatMap { account($0)?.name } ?? "別的帳戶"
                    out.append(TransferSide(ruleId: r.id, key: p.key, out: true, amount: p.amount, code: p.fromCode,
                                            title: "轉給 " + other, note: note, late: p.lateOut))
                }
                if p.toId == accountId {
                    let other = p.fromId.flatMap { account($0)?.name } ?? "別的帳戶"
                    out.append(TransferSide(ruleId: r.id, key: p.key, out: false, amount: p.toAmount, code: p.toCode,
                                            title: "來自 " + other, note: note, late: p.lateIn))
                }
            }
        }
        return out
    }

    /// 新增定期轉帳「從」的預設：有每月收入入帳的帳戶（入的最多那個）；找不到＝存摺上台幣最多的活存（沒收起來、不是定存）
    var defaultTransferFromId: UUID? {
        var best: (id: UUID, amount: Double)? = nil
        let from = WealthCal.addDays(-40, to: today)
        for a in pickerBanks {
            let rows: [WealthLedgerRow] = a.next30 + a.ledger.filter { WealthCal.day($0.date) >= from }
            let got: Double = rows.filter { $0.kind == .recurringIncome && $0.code == "NT$" }.map(\.amount).max() ?? 0
            guard got > 0.5 else { continue }
            if let b = best, b.amount >= got { continue }
            best = (id: a.id, amount: got)
        }
        if let b = best { return b.id }
        var rich: Account? = nil
        for a in pickerBanks where a.balance("NT$") > 0.5 {
            if let r = rich, r.balance("NT$") >= a.balance("NT$") { continue }
            rich = a
        }
        return rich?.id ?? pickerBanks.first?.id
    }

    /// build 用：每一條沒刪掉的規則（accounts 建好之後）
    static func makeTransferRules(_ book: WealthTransferBook, accounts: [Account], names: [UUID: String],
                                  today: Date) -> [TransferRule] {
        let byId = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let todayKey = WealthCal.dayKey(today)
        var out: [TransferRule] = []
        for (i, r) in book.live.enumerated() {
            let next = WealthTransferSchedule.next(r, today: today)
            let seg: WealthTransferSegment? = next.flatMap { r.segment(at: $0.key) } ?? r.lastSegment
            let fromId = seg?.fromId
            let toId = seg?.toId
            let fromAcc = fromId.flatMap { byId[$0] }
            let toAcc = toId.flatMap { byId[$0] }
            let fromName: String = fromAcc?.name ?? fromId.flatMap { names[$0] } ?? "別的帳戶"
            let toName: String = toAcc?.name ?? toId.flatMap { names[$0] } ?? "別的帳戶"
            let trimmed = (r.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let title: String = trimmed.isEmpty ? fromName + " → " + toName : trimmed
            let amount: Double = next?.amount ?? (seg?.amount ?? 0)
            let ended = !r.isRunning(todayKey: todayKey)
            let monthly: Double
            if ended {
                monthly = 0
            } else if r.cycleKind == .weekly {
                monthly = amount * 52 / 12
            } else {
                monthly = amount
            }
            out.append(TransferRule(
                id: r.id, rule: r, title: title, fromId: fromId, toId: toId, fromName: fromName, toName: toName,
                amount: amount, code: WealthFacts.norm(seg?.fromCode ?? "NT$"),
                cycleText: WealthTransferText.cycleText(r), modeText: WealthTransferText.modeText(r),
                isManual: r.isManual, next: ended ? nil : next,
                lastPast: WealthTransferSchedule.lastOriginal(r, onOrBefore: today),
                firstDay: r.startKey.flatMap { WealthTransferSchedule.date(fromKey: $0) },
                lastDay: r.endKey.flatMap { WealthTransferSchedule.date(fromKey: $0) },
                isEnded: ended,
                fromHidden: fromAcc?.hidden == true, toHidden: toAcc?.hidden == true,
                fromMissing: fromId != nil && fromAcc == nil, toMissing: toId != nil && toAcc == nil,
                monthlyOut: monthly, order: i))
        }
        return out
    }
}

// MARK: - 字

enum WealthTransferText {
    /// 「每週五」「每月 6 日」「每月最後一天」（不認得的週期「定期」）
    static func cycleText(_ r: WealthTransferRule) -> String {
        switch r.cycleKind {
        case .weekly?:
            guard let sk = r.startKey, let s = WealthTransferSchedule.date(fromKey: sk) else { return "每週" }
            return "每週" + weekdayName(s)
        case .monthly?:
            let d = r.day ?? 1
            if d >= 31 && r.short != "next" { return "每月最後一天" }
            return "每月 \(d) 日"
        case nil:
            return "定期"
        }
    }

    /// 星期幾一個字「五」（西曆、手機時區）
    static func weekdayName(_ d: Date) -> String {
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        let w = WealthCal.calendar.component(.weekday, from: d)
        return (w >= 1 && w <= 7) ? names[w - 1] : ""
    }

    /// 「銀行自動轉」「自己轉」
    static func modeText(_ r: WealthTransferRule) -> String {
        r.isManual ? "自己轉" : "銀行自動轉"
    }

    /// 數字之間可以夾的字（同 WealthPhotoScan：空白、各種連字號）
    private static let separators: Set<Character> = [" ", "-", "‐", "–", "—", "－", "\u{00A0}"]
    /// 幾位以上的連續數字算「像帳號」
    static let accountLikeDigits = 10

    /// 半形 0–9 照用；全形０–９換成半形；其他不算（同 WealthPhotoScan）
    private static func asciiDigit(_ ch: Character) -> Character? {
        let scalars = ch.unicodeScalars
        guard scalars.count == 1, let s = scalars.first else { return nil }
        let v = s.value
        if v >= 0x30 && v <= 0x39 { return ch }
        if v >= 0xFF10 && v <= 0xFF19, let u = Unicode.Scalar(v - 0xFF10 + 0x30) { return Character(u) }
        return nil
    }

    /// 一串字裡每一段數字：(數字, 第一個數字的位置, 最後一個數字的位置)；數字之間最多夾 3 個分隔字（同 WealthPhotoScan.digitRuns）
    private static func runs(_ chars: [Character]) -> [(digits: String, first: Int, last: Int)] {
        var out: [(digits: String, first: Int, last: Int)] = []
        var cur = ""
        var first = 0
        var last = 0
        var gap = 0
        for (i, ch) in chars.enumerated() {
            if let d = asciiDigit(ch) {
                if cur.isEmpty { first = i }
                cur.append(d)
                last = i
                gap = 0
            } else if separators.contains(ch), !cur.isEmpty, gap < 3 {
                gap += 1
            } else {
                if !cur.isEmpty { out.append((digits: cur, first: first, last: last)) }
                cur = ""
                gap = 0
            }
        }
        if !cur.isEmpty { out.append((digits: cur, first: first, last: last)) }
        return out
    }

    /// 名字、備註裡第一串像帳號的數字（10 位以上）的最後 4 碼；沒有＝nil（「轉 012-345-678901 給媽」→「8901」）
    static func accountLikeTail(_ text: String) -> String? {
        for r in runs(Array(text)) where r.digits.count >= accountLikeDigits {
            return String(r.digits.suffix(4))
        }
        return nil
    }

    /// 〔只留後 4 碼〕：每一串像帳號的數字換成「••8901」（「轉 012-345-678901 給媽」→「轉 ••8901 給媽」）
    static func maskAccountLike(_ text: String) -> String {
        let chars = Array(text)
        let found = runs(chars).filter { $0.digits.count >= accountLikeDigits }
        guard !found.isEmpty else { return text }
        var out = ""
        var i = 0
        for r in found {
            if r.first > i { out += String(chars[i..<r.first]) }
            out += "••" + String(r.digits.suffix(4))
            i = r.last + 1
        }
        if i < chars.count { out += String(chars[i..<chars.count]) }
        return out
    }
}

// MARK: - 存規則時認得「記帳湊的」（judge §4.6；只看正在存的這一條）

/// 記帳裡像這條的固定支出（扣款帳戶＝從、同金額、日子差 3 天內、每月）或收入（入帳帳戶＝到、同金額、日子差 3 天內、每月）
struct WealthTransferMatch: Identifiable, Equatable {
    enum Kind: Equatable {
        case expense, income
    }
    let kind: Kind
    /// Expense.id／Income.id
    let itemId: UUID
    /// 「記帳裡的『轉玉山存錢』每月 6 日 20,000 從 薪轉 扣，跟這條是同一筆嗎？」
    let question: String
    /// 〔是：從下一期起結束〕記帳那筆結束在哪天：固定支出＝跟這條第一期對上的那一期的前一天（endDate 那天那期照扣）；
    /// 收入＝那一期的前一個月月底（Income.endDate 照月份算、結束那個月含）
    let endDay: Date

    var id: String { (kind == .expense ? "e-" : "i-") + itemId.uuidString }
}

enum WealthTransferMatcher {
    /// 每月幾號差幾天以內算「同一天」（月底、月初跨月也算：31 號 vs 1 號差 1 天）
    static let dayWindow = 3

    static func closeDays(_ a: Int, _ b: Int) -> Bool {
        let d = Swift.abs(a - b)
        return Swift.min(d, 31 - d) <= dayWindow
    }

    /// 這條（每月的、還沒存的）跟記帳裡哪幾筆像同一筆：固定支出在前、收入在後。excluded：帳本「這筆不算」的記帳（不再問）
    static func matches(rule r: WealthTransferRule, fromName: String, toName: String, expenses: [Expense],
                        incomes: [Income], excluded: Set<String>) -> [WealthTransferMatch] {
        guard r.cycleKind == .monthly, let sk = r.startKey, let first = WealthTransferSchedule.date(fromKey: sk),
              let seg = r.segment(at: sk), let amount = seg.amount, amount > 0.004 else { return [] }
        let cal = WealthCal.calendar
        let ruleDay = cal.component(.day, from: first)
        let early = WealthCal.addDays(-dayWindow, to: first)
        let until = WealthCal.addDays(35, to: first)
        let amountText = WealthFormat.grouped(amount.rounded(), decimals: 0)
        var out: [WealthTransferMatch] = []
        if let from = seg.fromId {
            for e in expenses where e.expenseType == .fixed && e.recurrence == .monthly {
                guard e.linkedCreditCardMilestoneId == nil, e.linkedBankMilestoneId == from,
                      e.originalCurrencyAmount == nil, !excluded.contains(e.id.uuidString),
                      Swift.abs(e.amount - amount) < 0.5 else { continue }
                if let end = e.endDate, WealthCal.day(end) < early { continue }
                let eDay = cal.component(.day, from: e.date)
                guard closeDays(eDay, ruleDay) else { continue }
                let hit = WealthSchedule.fixedPeriods(e, through: until).first { WealthCal.day($0.date) >= early }
                let endDay: Date = hit.map { WealthCal.addDays(-1, to: WealthCal.day($0.date)) }
                    ?? WealthCal.addDays(-1, to: first)
                let q = "記帳裡的『\(e.title)』每月 \(eDay) 日 \(amountText) 從 \(fromName) 扣，跟這條是同一筆嗎？"
                out.append(WealthTransferMatch(kind: .expense, itemId: e.id, question: q, endDay: endDay))
            }
        }
        if let to = seg.toId {
            for inc in incomes where inc.period == .monthly {
                guard inc.linkedBankMilestoneId == to, Swift.abs(inc.amount - amount) < 0.5,
                      inc.isActive(in: first, calendar: cal) else { continue }
                let iDay = cal.component(.day, from: inc.date)
                guard closeDays(iDay, ruleDay) else { continue }
                let hit = WealthSchedule.incomePeriods(inc, through: until).first { WealthCal.day($0.date) >= early }
                let month: Date = WealthCal.startOfMonth(hit.map { $0.date } ?? first)
                let endDay = WealthCal.addDays(-1, to: month)
                let q = "記帳裡的收入『\(inc.title)』每月 \(iDay) 日 \(amountText) 入 \(toName)，是同一筆嗎？"
                out.append(WealthTransferMatch(kind: .income, itemId: inc.id, question: q, endDay: endDay))
            }
        }
        return out
    }
}
