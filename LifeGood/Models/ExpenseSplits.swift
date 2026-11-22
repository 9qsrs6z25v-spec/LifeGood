import Foundation

// MARK: - [v25.634] 分帳：一頓飯誰我請、誰要還我、還了沒（radar/judge_companions.md §C1–C5、C8、C10、C11；
//   build/companions1/brief.md §0–§3；sim_companions1.py 一個函式一個函式對照）
//
// • Expense 一個欄位都沒加：「誰」照舊用「、」串在 Expense.diningMember（還沒更新的 iPad 認得、名單外的名字原樣留著）；
//   「我請／要還我、每人多少、還款」放新的同步鍵 lifegood_expense_splits_v1，key＝Expense.id。舊版的 syncKeys 沒有這個鍵＝不讀也不寫。
// • 兩台合併一個人一個人合（SplitShare.id）：欄位取 updatedAt 新的；還款照 id 聯集、任一邊撤銷就算撤銷。
//   兩台同時改不會把〔已還〕弄掉（存摺上那筆錢還在，使用者就不會再按一次〔已還〕多記一筆存款）。
// • 還過錢的人一律算「還在」（拿掉、換分類、換成固定支出都留著：錢已經進來了）。
// • 讀只准問 ExpenseSplitIndex（整頓墓碑、拿掉的人、空的分帳都濾掉）；統計只准用 ExpenseSplitIndex.ownAmount
//  （ExpenseStore.ownAmount 包這一支）。沒有分帳的支出＝原樣 e.amount，所以沒用分帳的使用者每個數字都跟以前一樣。
// • 寫只有新版、只有使用者按的時候：AddExpenseView 存檔（recordSave）、〔已還〕（recordRepayment）、〔改成還沒還〕
//  （undoRepayment）、ExpenseStore 刪除（墓碑）、備份取代／合併、iCloud 合併。開 App、背景、同步一律不自己寫。
// • 〔已還〕寫的 BankDeposit：linkedExpenseId 一定是 nil（記帳存檔會清掉指到那頓的存摺紀錄、WealthFacts 會把它當成被取代），
//   note 只寫「分帳還款・11/20 飲食」，不寫人名、不寫店名。還錢不建 Income（「還能花」的基準才不會灌水）。
// • 隱私：名字、欠款只在 App 內頁；通知、小工具、手錶、鎖定畫面、靈動島一個字都沒加；分享一律不放分帳。

// MARK: - 資料長相（C2）

/// 同步鍵 lifegood_expense_splits_v1：一頓飯誰我請、誰要還我、還了沒（Expense 一個欄位都不加，舊 iPad 存檔才不會丟）
struct ExpenseSplitBook: Codable, Equatable {
    /// 同步鍵（ExpenseSplitStore 存讀、CloudSyncManager.syncKeys 用同一個字）
    static let syncKey = "lifegood_expense_splits_v1"
    /// 墓碑留幾天（另一台還沒同步的舊資料不會把它長回來）
    static let tombstoneDays = 30

    /// 逐筆解（壞一筆只丟那筆）
    var splits: [ExpenseSplit]?
    var extra: [String: JSONValue]?
}

/// 一頓飯的分帳（id ＝ Expense.id）
struct ExpenseSplit: Codable, Equatable, Identifiable {
    /// ＝ Expense.id
    var id: UUID
    /// 分的時候這頓多少（台幣）；跟 e.amount 差 ≥ 1 ＝ 金額被改過（詳情卡提示重新分）
    var baseAmount: Double = 0
    /// 不含「我」；我那份＝baseAmount − 還在的人的 amount 加總
    var shares: [SplitShare]?
    /// 寫入一律填；讀到 nil 當 distantPast
    var updatedAt: Date?
    /// 整頓的墓碑（那筆支出刪掉了）
    var deletedAt: Date?
    var extra: [String: JSONValue]?
}

/// 一個人（不含「我」）
struct SplitShare: Codable, Equatable, Identifiable {
    static let roleTreat = "treat"
    static let roleOwe = "owe"

    /// 這一列自己的 id（同名的兩個人也分得開）
    var id: UUID
    /// 名字快照（更舊的 iPad 洗掉 diningMember 也還在）
    var name: String = ""
    /// "treat"＝我請、"owe"＝要還我；看不懂的值一律照我請（不扣、不列欠款：往安全的方向錯）
    var role: String = "treat"
    /// 這個人那份（台幣，平分出來是整數元）
    var amount: Double = 0
    /// 手改過金額（平分時不動）；nil＝沒有
    var isManual: Bool?
    /// 還款（v1 畫面最多一筆、而且是全額；陣列留給之後的部分還款）
    var repayments: [SplitRepayment]?
    var updatedAt: Date?
    /// 這個人的墓碑（從名單拿掉了）；還過錢的不會被拿掉（isLive）
    var removedAt: Date?
    var extra: [String: JSONValue]?
}

/// 一筆還款
struct SplitRepayment: Codable, Equatable, Identifiable {
    var id: UUID
    var date: Date
    var amount: Double
    /// 錢進哪個帳戶（nil＝現金，沒記到存摺）
    var accountId: UUID?
    /// 存摺那筆 BankDeposit.id（現金＝nil）
    var depositId: UUID?
    /// 撤銷（〔改成還沒還〕）
    var removedAt: Date?
    var extra: [String: JSONValue]?
}

// MARK: - Codable（knownKeys＋extra 原樣寫回、陣列 lossyArray 逐筆解；照 ExpenseKinds.swift）

extension ExpenseSplitBook {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case splits
    }
    static let knownKeys: Set<String> = Set(CodingKeys.allCases.map { $0.rawValue })

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        splits = CompetencyCoding.lossyArray(ExpenseSplit.self, c, .splits)
        extra = CompetencyCoding.readExtra(decoder, known: Self.knownKeys)
    }

    func encode(to encoder: Encoder) throws {
        try CompetencyCoding.writeExtra(extra, encoder, known: Self.knownKeys)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(splits, forKey: .splits)
    }
}

extension ExpenseSplit {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, baseAmount, shares, updatedAt, deletedAt
    }
    static let knownKeys: Set<String> = Set(CodingKeys.allCases.map { $0.rawValue })

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        baseAmount = (try? c.decodeIfPresent(Double.self, forKey: .baseAmount)) ?? 0
        shares = CompetencyCoding.lossyArray(SplitShare.self, c, .shares)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        deletedAt = try? c.decodeIfPresent(Date.self, forKey: .deletedAt)
        extra = CompetencyCoding.readExtra(decoder, known: Self.knownKeys)
    }

    func encode(to encoder: Encoder) throws {
        try CompetencyCoding.writeExtra(extra, encoder, known: Self.knownKeys)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(baseAmount, forKey: .baseAmount)
        try c.encodeIfPresent(shares, forKey: .shares)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }
}

extension SplitShare {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, role, amount, isManual, repayments, updatedAt, removedAt
    }
    static let knownKeys: Set<String> = Set(CodingKeys.allCases.map { $0.rawValue })

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        role = (try? c.decodeIfPresent(String.self, forKey: .role)) ?? SplitShare.roleTreat
        amount = (try? c.decodeIfPresent(Double.self, forKey: .amount)) ?? 0
        isManual = try? c.decodeIfPresent(Bool.self, forKey: .isManual)
        repayments = CompetencyCoding.lossyArray(SplitRepayment.self, c, .repayments)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        removedAt = try? c.decodeIfPresent(Date.self, forKey: .removedAt)
        extra = CompetencyCoding.readExtra(decoder, known: Self.knownKeys)
    }

    func encode(to encoder: Encoder) throws {
        try CompetencyCoding.writeExtra(extra, encoder, known: Self.knownKeys)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(role, forKey: .role)
        try c.encode(amount, forKey: .amount)
        try c.encodeIfPresent(isManual, forKey: .isManual)
        try c.encodeIfPresent(repayments, forKey: .repayments)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(removedAt, forKey: .removedAt)
    }
}

extension SplitRepayment {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, date, amount, accountId, depositId, removedAt
    }
    static let knownKeys: Set<String> = Set(CodingKeys.allCases.map { $0.rawValue })

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        // 日期、金額讀不到也留著這一筆（丟掉的話會變成「還沒還」，使用者再按一次〔已還〕就多記一筆存款）
        date = (try? c.decodeIfPresent(Date.self, forKey: .date)) ?? Date.distantPast
        amount = (try? c.decodeIfPresent(Double.self, forKey: .amount)) ?? 0
        accountId = try? c.decodeIfPresent(UUID.self, forKey: .accountId)
        depositId = try? c.decodeIfPresent(UUID.self, forKey: .depositId)
        removedAt = try? c.decodeIfPresent(Date.self, forKey: .removedAt)
        extra = CompetencyCoding.readExtra(decoder, known: Self.knownKeys)
    }

    func encode(to encoder: Encoder) throws {
        try CompetencyCoding.writeExtra(extra, encoder, known: Self.knownKeys)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(date, forKey: .date)
        try c.encode(amount, forKey: .amount)
        try c.encodeIfPresent(accountId, forKey: .accountId)
        try c.encodeIfPresent(depositId, forKey: .depositId)
        try c.encodeIfPresent(removedAt, forKey: .removedAt)
    }
}

// MARK: - 一個人、一頓的狀態（純函式）

extension SplitRepayment {
    var isLive: Bool { removedAt == nil }
}

extension SplitShare {
    /// 還沒撤銷的還款
    var liveRepayments: [SplitRepayment] { (repayments ?? []).filter { r in r.isLive } }
    /// 有還過（還沒撤銷）＝鎖住：編輯器不能改、選單不能取消、拿掉也留著
    var hasRepayment: Bool { (repayments ?? []).contains { r in r.isLive } }
    var repaidTotal: Double { liveRepayments.reduce(0) { $0 + $1.amount } }
    /// 還在這頓裡（沒拿掉；拿掉了但還過錢的也算）
    var isLive: Bool { removedAt == nil || hasRepayment }
    /// 要還我（看不懂的 role 一律當我請）
    var owes: Bool { role == SplitShare.roleOwe }
    /// 還欠多少（我請的＝0）
    var outstanding: Double { owes ? max(0, amount - repaidTotal) : 0 }
    /// 要還我、還過、而且還清了（差不到 0.5 元算清）
    var isSettled: Bool { owes && hasRepayment && outstanding < 0.5 }
    /// 最近一筆還沒撤銷的還款（日期新的；一樣新取後面那筆）
    var lastRepayment: SplitRepayment? {
        var best: SplitRepayment? = nil
        for r in liveRepayments {
            if let b = best, b.date > r.date { continue }
            best = r
        }
        return best
    }
}

extension ExpenseSplit {
    /// 還在的人（整頓墓碑＝沒有人）
    var liveShares: [SplitShare] {
        guard deletedAt == nil else { return [] }
        return (shares ?? []).filter { s in s.isLive }
    }
    /// 要還我的加總（已還、沒還都算：那是別人的錢）
    var owedTotal: Double { liveShares.filter { s in s.owes }.reduce(0) { $0 + $1.amount } }
    /// 我請的加總
    var treatTotal: Double { liveShares.filter { s in !s.owes }.reduce(0) { $0 + $1.amount } }
    /// 還欠多少
    var outstandingTotal: Double { liveShares.reduce(0) { $0 + $1.outstanding } }
    /// 還沒還的人數
    var unpaidCount: Int { liveShares.filter { s in s.owes && !s.isSettled && s.outstanding >= 0.5 }.count }
    /// 要還我的人數
    var oweCount: Int { liveShares.filter { s in s.owes }.count }
}

// MARK: - 合併、清墓碑、寫（純函式；ExpenseSplitStore 只叫這些）（C3）

extension ExpenseSplitBook {
    var isEmpty: Bool { (splits ?? []).isEmpty }

    /// 同一個 id 的原始分帳（不驗證；有兩筆時留 updatedAt 新的）
    func rawSplit(_ id: UUID) -> ExpenseSplit? {
        var best: ExpenseSplit? = nil
        for s in splits ?? [] where s.id == id {
            if let b = best, (b.updatedAt ?? .distantPast) >= (s.updatedAt ?? .distantPast) { continue }
            best = s
        }
        return best
    }

    /// 新增或整筆換掉（同一個 id 只留這一筆，位置不動）
    mutating func upsert(_ s: ExpenseSplit) {
        var list: [ExpenseSplit] = []
        var placed = false
        for x in splits ?? [] {
            if x.id == s.id {
                if !placed {
                    list.append(s)
                    placed = true
                }
            } else {
                list.append(x)
            }
        }
        if !placed { list.append(s) }
        splits = list
    }

    /// 兩台合併（iCloud 增量、第一次同步〔合併〕、備份〔合併〕）：整頓照 id 對；一個人一個人合（ExpenseSplit.merge）；
    /// extra 合在一起（self 優先）。冪等：a.merged(with: a) == a
    func merged(with other: ExpenseSplitBook) -> ExpenseSplitBook {
        var out = self
        if splits == nil && other.splits == nil {
            out.extra = CompetencyCoding.mergeExtra(extra, other.extra)
            return out
        }
        var list: [ExpenseSplit] = splits ?? []
        var at: [UUID: Int] = [:]
        for (i, s) in list.enumerated() where at[s.id] == nil {
            at[s.id] = i
        }
        for o in other.splits ?? [] {
            if let i = at[o.id] {
                list[i] = ExpenseSplit.merge(list[i], o)
            } else {
                at[o.id] = list.count
                list.append(o)
            }
        }
        out.splits = list
        out.extra = CompetencyCoding.mergeExtra(extra, other.extra)
        return out
    }

    /// 清墓碑（存檔時叫）：整頓墓碑、拿掉的人（沒還過錢的）、撤銷的還款，超過 30 天才清。
    /// 孤兒（找不到那筆支出）不清：那筆支出可能還在同步的路上，讀的時候 ExpenseSplitIndex 會濾掉。沒有要清的回 self
    func purged(now: Date) -> ExpenseSplitBook {
        guard let list = splits else { return self }
        let limit: Date = now.addingTimeInterval(-Double(Self.tombstoneDays) * 86_400)
        var changed = false
        var kept: [ExpenseSplit] = []
        for s in list {
            if let d = s.deletedAt, d <= limit {
                changed = true
                continue
            }
            let p = s.purgedParts(limit: limit)
            if p != s { changed = true }
            kept.append(p)
        }
        guard changed else { return self }
        var out = self
        out.splits = kept
        return out
    }

    /// C7 存檔：draft＝這次存的分帳（nil 或沒有人＝這筆不能分帳了／沒有別人）。回 nil＝不用寫
    /// • 有人：建或改那一頓（baseAmount＝draft.total；名單上沒有、沒還過的人標拿掉；改了的那幾列 updatedAt＝now；還過錢的那列不動）
    /// • 沒有人：沒還過的人標拿掉；一個人都不剩就寫整頓墓碑；還過錢的留著
    func saving(expenseId: UUID, draft: ExpenseSplitDraft?, now: Date) -> ExpenseSplitBook? {
        let raw = rawSplit(expenseId)
        let rows: [ExpenseSplitDraftRow] = draft?.rows ?? []
        if rows.isEmpty {
            guard var s = raw, s.deletedAt == nil else { return nil }
            var shares: [SplitShare] = s.shares ?? []
            var changed = false
            for i in shares.indices where shares[i].removedAt == nil && !shares[i].hasRepayment {
                shares[i].removedAt = now
                shares[i].updatedAt = now
                changed = true
            }
            if !shares.contains(where: { x in x.isLive }) {
                s.deletedAt = now
                changed = true
            }
            guard changed else { return nil }
            s.shares = shares
            s.updatedAt = now
            var out = self
            out.upsert(s)
            return out
        }
        let total: Double = draft?.total ?? 0
        var s: ExpenseSplit = raw ?? ExpenseSplit(id: expenseId)
        var changed = raw == nil || s.deletedAt != nil
        s.deletedAt = nil
        if s.baseAmount != total {
            s.baseAmount = total
            changed = true
        }
        var shares: [SplitShare] = s.shares ?? []
        let draftIds: Set<UUID> = Set(rows.map { r in r.id })
        for i in shares.indices where !draftIds.contains(shares[i].id)
            && shares[i].removedAt == nil && !shares[i].hasRepayment {
            shares[i].removedAt = now
            shares[i].updatedAt = now
            changed = true
        }
        for r in rows {
            if let i = shares.firstIndex(where: { x in x.id == r.id }) {
                var x = shares[i]
                // 還過錢的那列不動（編輯器鎖住；這裡是第二道防線）
                if x.hasRepayment { continue }
                let same = x.name == r.name && x.role == r.role && x.amount == r.amount
                    && (x.isManual ?? false) == r.isManual && x.removedAt == nil
                if same { continue }
                x.name = r.name
                x.role = r.role
                x.amount = r.amount
                x.isManual = r.isManual ? true : nil
                x.removedAt = nil
                x.updatedAt = now
                shares[i] = x
                changed = true
            } else {
                shares.append(SplitShare(id: r.id, name: r.name, role: r.role, amount: r.amount,
                                         isManual: r.isManual ? true : nil, updatedAt: now))
                changed = true
            }
        }
        guard changed else { return nil }
        s.shares = shares
        s.updatedAt = now
        var out = self
        out.upsert(s)
        return out
    }

    /// ExpenseStore.delete：有分帳的寫整頓墓碑（存摺上已經入帳的錢不動）
    func deleting(ids: Set<UUID>, now: Date) -> ExpenseSplitBook? {
        var out = self
        var changed = false
        for id in ids {
            guard var s = out.rawSplit(id), s.deletedAt == nil else { continue }
            s.deletedAt = now
            s.updatedAt = now
            out.upsert(s)
            changed = true
        }
        return changed ? out : nil
    }

    /// 〔已還〕：那個人多一筆還款（同一個 id 已經有就不寫）
    func repaying(expenseId: UUID, shareId: UUID, repayment: SplitRepayment) -> ExpenseSplitBook? {
        guard var s = rawSplit(expenseId), var shares = s.shares,
              let i = shares.firstIndex(where: { x in x.id == shareId }) else { return nil }
        var list: [SplitRepayment] = shares[i].repayments ?? []
        guard !list.contains(where: { r in r.id == repayment.id }) else { return nil }
        list.append(repayment)
        shares[i].repayments = list
        s.shares = shares
        var out = self
        out.upsert(s)
        return out
    }

    /// 〔改成還沒還〕：那一筆還款寫 removedAt（已經撤銷、找不到就不寫）
    func undoingRepayment(expenseId: UUID, shareId: UUID, repaymentId: UUID, now: Date) -> ExpenseSplitBook? {
        guard var s = rawSplit(expenseId), var shares = s.shares,
              let i = shares.firstIndex(where: { x in x.id == shareId }) else { return nil }
        var list: [SplitRepayment] = shares[i].repayments ?? []
        guard let j = list.firstIndex(where: { r in r.id == repaymentId && r.removedAt == nil }) else { return nil }
        list[j].removedAt = now
        shares[i].repayments = list
        s.shares = shares
        var out = self
        out.upsert(s)
        return out
    }

    /// 匯出：只帶這幾筆支出的
    func filtered(to ids: Set<UUID>) -> ExpenseSplitBook {
        var out = self
        if let list = splits {
            out.splits = list.filter { s in ids.contains(s.id) }
        }
        return out
    }

    /// 取代（只帶了一部分支出的檔案，例如旅遊）：這幾個 id 換成備份裡的，其他不動
    func replacing(ids: Set<UUID>, with other: ExpenseSplitBook) -> ExpenseSplitBook {
        var out = self
        let keep: [ExpenseSplit] = (splits ?? []).filter { s in !ids.contains(s.id) }
        let incoming: [ExpenseSplit] = (other.splits ?? []).filter { s in ids.contains(s.id) }
        let all: [ExpenseSplit] = keep + incoming
        out.splits = (splits == nil && all.isEmpty) ? nil : all
        return out
    }
}

extension ExpenseSplit {
    /// 同一頓兩邊都有：baseAmount、deletedAt、updatedAt 取 updatedAt 新的那邊（一樣新留 a）；
    /// 人一個一個合（SplitShare.mergeList）；extra 合在一起（a 優先）
    static func merge(_ a: ExpenseSplit, _ b: ExpenseSplit) -> ExpenseSplit {
        let bNewer = (b.updatedAt ?? .distantPast) > (a.updatedAt ?? .distantPast)
        var out: ExpenseSplit = bNewer ? b : a
        out.shares = SplitShare.mergeList(a.shares, b.shares)
        out.extra = CompetencyCoding.mergeExtra(a.extra, b.extra)
        return out
    }

    /// 清這一頓裡面超過期限的墓碑：拿掉的人（沒還過錢的）、撤銷的還款
    func purgedParts(limit: Date) -> ExpenseSplit {
        guard let list = shares else { return self }
        var kept: [SplitShare] = []
        for s in list {
            if let r = s.removedAt, r <= limit, !s.hasRepayment { continue }
            var x = s
            if let reps = s.repayments {
                x.repayments = reps.filter { r in
                    guard let gone = r.removedAt else { return true }
                    return gone > limit
                }
            }
            kept.append(x)
        }
        var out = self
        out.shares = kept
        return out
    }
}

extension SplitShare {
    /// 照 id 合併兩份名單：同一個人欄位取 updatedAt 新的（一樣新留 mine）；還款聯集（SplitRepayment.union）。兩邊都 nil 回 nil
    static func mergeList(_ mine: [SplitShare]?, _ other: [SplitShare]?) -> [SplitShare]? {
        if mine == nil && other == nil { return nil }
        var out: [SplitShare] = mine ?? []
        var at: [UUID: Int] = [:]
        for (i, s) in out.enumerated() where at[s.id] == nil {
            at[s.id] = i
        }
        for o in other ?? [] {
            if let i = at[o.id] {
                out[i] = merge(out[i], o)
            } else {
                at[o.id] = out.count
                out.append(o)
            }
        }
        return out
    }

    static func merge(_ a: SplitShare, _ b: SplitShare) -> SplitShare {
        let bNewer = (b.updatedAt ?? .distantPast) > (a.updatedAt ?? .distantPast)
        var out: SplitShare = bNewer ? b : a
        out.repayments = SplitRepayment.union(a.repayments, b.repayments)
        out.extra = CompetencyCoding.mergeExtra(a.extra, b.extra)
        return out
    }
}

extension SplitRepayment {
    /// 還款照 id 聯集：兩邊都有時欄位留 mine 的、removedAt 任一邊有就算撤銷（兩邊都有取早的）。兩邊都 nil 回 nil
    static func union(_ mine: [SplitRepayment]?, _ other: [SplitRepayment]?) -> [SplitRepayment]? {
        if mine == nil && other == nil { return nil }
        var out: [SplitRepayment] = mine ?? []
        var at: [UUID: Int] = [:]
        for (i, r) in out.enumerated() where at[r.id] == nil {
            at[r.id] = i
        }
        for o in other ?? [] {
            if let i = at[o.id] {
                var x = out[i]
                if let p = x.removedAt, let q = o.removedAt {
                    x.removedAt = min(p, q)
                } else if x.removedAt == nil {
                    x.removedAt = o.removedAt
                }
                x.extra = CompetencyCoding.mergeExtra(x.extra, o.extra)
                out[i] = x
            } else {
                at[o.id] = out.count
                out.append(o)
            }
        }
        return out
    }
}

// MARK: - 讀（C4、C8、C9、C11）：所有畫面、統計、CSV 只問這個

/// 純值：從 book 建（主執行緒的 ExpenseSplitStore.index；CSV 從備份那一包自己建，可以在背景）
struct ExpenseSplitIndex {
    static let empty = ExpenseSplitIndex(book: ExpenseSplitBook())

    /// 只放有人、不是整頓墓碑的（同一個 id 兩筆留 updatedAt 新的）
    let byId: [UUID: ExpenseSplit]

    init(book: ExpenseSplitBook) {
        var best: [UUID: ExpenseSplit] = [:]
        for s in book.splits ?? [] {
            if let b = best[s.id], (b.updatedAt ?? .distantPast) >= (s.updatedAt ?? .distantPast) { continue }
            best[s.id] = s
        }
        byId = best.filter { _, s in s.deletedAt == nil && !s.liveShares.isEmpty }
    }

    var isEmpty: Bool { byId.isEmpty }

    /// 這筆的分帳（沒有＝nil）
    func split(_ id: UUID) -> ExpenseSplit? { byId[id] }

    /// 變動支出才算分帳（固定支出、分類換掉的舊紀錄一律當沒有）
    func split(for e: Expense) -> ExpenseSplit? {
        guard e.expenseType == .variable else { return nil }
        return byId[e.id]
    }

    /// C8：這筆算你自己的錢。變動支出有分帳＝amount − 要還我（已還、沒還都扣），最少 0；
    /// 沒有分帳、或不是變動支出＝原樣 e.amount（全面換掉也不會改到沒用分帳的人的數字）
    func ownAmount(_ e: Expense) -> Double {
        guard let s = split(for: e) else { return e.amount }
        let owed = s.owedTotal
        return owed > 0 ? max(0, e.amount - owed) : e.amount
    }

    /// 這筆還欠多少（CSV「要還我還沒還」、清單）
    func outstanding(_ e: Expense) -> Double {
        split(for: e)?.outstandingTotal ?? 0
    }

    /// C9：金額被改過（分的時候跟現在差 ≥ 1 元）
    func amountChanged(_ e: Expense) -> Bool {
        guard let s = split(for: e) else { return false }
        return abs(e.amount - s.baseAmount) >= 1
    }

    /// C9：列上的膠囊（有人還沒還＝「2 人要還」橘；有人要還、全部還清＝「已還清」綠；全部我請＝nil）
    func chip(_ e: Expense) -> ExpenseSplitChip? {
        guard let s = split(for: e), s.oweCount > 0 else { return nil }
        let n = s.unpaidCount
        return n > 0 ? .unpaid(n) : .settled
    }

    /// C8 說明小字：那個月的變動支出因為分帳扣掉多少（＝Σ amount − ownAmount）
    func deducted(expenses: [Expense], month: Date, calendar: Calendar) -> Double {
        guard !byId.isEmpty else { return 0 }
        var sum = 0.0
        for e in expenses where e.expenseType == .variable && byId[e.id] != nil
            && calendar.isDate(e.date, equalTo: month, toGranularity: .month) {
            sum += e.amount - ownAmount(e)
        }
        return sum
    }

    /// C11：還沒還的（一人一頓一列）。只算 expenses 裡還在的變動支出（孤兒不出現）
    func owedMeals(expenses: [Expense], now: Date, calendar: Calendar) -> [SplitOwedMeal] {
        guard !byId.isEmpty else { return [] }
        var out: [SplitOwedMeal] = []
        for e in expenses {
            guard let s = split(for: e) else { continue }
            for sh in s.liveShares where sh.owes && !sh.isSettled && sh.outstanding >= 0.5 {
                out.append(SplitOwedMeal(expenseId: e.id, shareId: sh.id, name: sh.name, date: e.date,
                                         title: ExpenseSplitText.mealTitle(e), amount: sh.outstanding,
                                         days: ExpenseSplitText.daysBetween(e.date, now, calendar: calendar),
                                         repaidDate: nil, accountId: nil))
            }
        }
        return out
    }

    /// C11「還清了」：最近 days 天內還清的（照最後一筆還款的日期）
    func settledMeals(expenses: [Expense], now: Date, calendar: Calendar, days: Int = 90) -> [SplitOwedMeal] {
        guard !byId.isEmpty else { return [] }
        let today = calendar.startOfDay(for: now)
        let cutoff: Date = calendar.date(byAdding: .day, value: -days, to: today) ?? today
        var out: [SplitOwedMeal] = []
        for e in expenses {
            guard let s = split(for: e) else { continue }
            for sh in s.liveShares where sh.isSettled {
                guard let last = sh.lastRepayment, last.date >= cutoff else { continue }
                out.append(SplitOwedMeal(expenseId: e.id, shareId: sh.id, name: sh.name, date: e.date,
                                         title: ExpenseSplitText.mealTitle(e), amount: sh.repaidTotal,
                                         days: ExpenseSplitText.daysBetween(e.date, last.date, calendar: calendar),
                                         repaidDate: last.date, accountId: last.accountId))
            }
        }
        return out
    }

    /// C11 依人分組：人照金額由大到小（一樣多照名字），每頓照日期新到舊
    static func people(_ meals: [SplitOwedMeal]) -> [SplitOwedPerson] {
        var byName: [String: [SplitOwedMeal]] = [:]
        for m in meals { byName[m.name, default: []].append(m) }
        var out: [SplitOwedPerson] = []
        for (name, list) in byName {
            let sorted: [SplitOwedMeal] = list.sorted { a, b in
                if a.date != b.date { return a.date > b.date }
                return a.id < b.id
            }
            let total: Double = list.reduce(0) { $0 + $1.amount }
            let maxDays: Int = list.map { m in m.days }.max() ?? 0
            out.append(SplitOwedPerson(name: name, total: total, maxDays: maxDays, meals: sorted))
        }
        return out.sorted { a, b in
            if a.total != b.total { return a.total > b.total }
            return a.name < b.name
        }
    }

    /// C11 入口那一列（變動支出頁）：還沒還的人數、總額、筆數、超過 30 天的筆數、最久幾天
    func owedSummary(expenses: [Expense], now: Date, calendar: Calendar) -> SplitOwedSummary {
        let meals = owedMeals(expenses: expenses, now: now, calendar: calendar)
        let names = Set(meals.map { m in m.name })
        let total: Double = meals.reduce(0) { $0 + $1.amount }
        let late = meals.filter { m in m.days > ExpenseSplitText.lateDays }
        let maxDays: Int = meals.map { m in m.days }.max() ?? 0
        return SplitOwedSummary(people: names.count, total: total, meals: meals.count,
                                lateCount: late.count, maxDays: maxDays)
    }
}

/// 列上的膠囊
enum ExpenseSplitChip: Equatable {
    case unpaid(Int)
    case settled

    var text: String {
        switch self {
        case .unpaid(let n): return "\(n) 人要還"
        case .settled: return "已還清"
        }
    }
}

/// 誰還欠我：一人一頓
struct SplitOwedMeal: Identifiable, Equatable {
    let expenseId: UUID
    let shareId: UUID
    let name: String
    /// 吃飯那天（Expense.date）
    let date: Date
    /// 列上的字（店名；沒打名字用分類）
    let title: String
    /// 還沒還：還欠多少；還清了：還了多少
    let amount: Double
    /// 還沒還：等了幾天（吃飯那天到今天）；還清了：隔了幾天才還
    let days: Int
    let repaidDate: Date?
    let accountId: UUID?

    var id: String { expenseId.uuidString + "|" + shareId.uuidString }
}

/// 誰還欠我：一個人（照名字分組）
struct SplitOwedPerson: Identifiable, Equatable {
    let name: String
    let total: Double
    let maxDays: Int
    let meals: [SplitOwedMeal]

    var id: String { name }
}

struct SplitOwedSummary: Equatable {
    var people: Int = 0
    var total: Double = 0
    var meals: Int = 0
    /// 等了超過 30 天的筆數
    var lateCount: Int = 0
    var maxDays: Int = 0

    /// 入口要不要出現（還沒還的總額大於 0）
    var showsEntry: Bool { total >= 0.5 }
}

// MARK: - 表單用的草稿與平分（C7；ExpenseSplitEditor、AddExpenseView 只叫這裡）

/// 編輯器裡的一列（不含「我」）
struct ExpenseSplitDraftRow: Equatable, Identifiable {
    /// ＝ SplitShare.id（新加的人新編號）
    var id: UUID
    var name: String
    var role: String
    var amount: Double
    var isManual: Bool
    /// 有還過錢：不能改角色、金額，選單不能取消
    var locked: Bool
}

/// 這次表單裡的分帳（total＝這頓存檔的台幣金額）
struct ExpenseSplitDraft: Equatable {
    var total: Double
    var rows: [ExpenseSplitDraftRow]

    /// 分給別人的加總
    var assigned: Double { rows.reduce(0) { $0 + $1.amount } }
    /// 我那份（剩下的；分超過時是負的）
    var meAmount: Double { total - assigned }
    var owedTotal: Double { rows.filter { r in r.role == SplitShare.roleOwe }.reduce(0) { $0 + $1.amount } }
    var owedCount: Int { rows.filter { r in r.role == SplitShare.roleOwe }.count }
    var treatTotal: Double { rows.filter { r in r.role != SplitShare.roleOwe }.reduce(0) { $0 + $1.amount } }
    /// 分出去比這筆多多少
    var overBy: Double { max(0, assigned - total) }
    /// 超過總額（〔完成〕灰掉）
    var isOver: Bool { overBy >= 0.5 }
    /// 記帳只算你多少
    var ownAmount: Double { max(0, total - owedTotal) }
    var hasManual: Bool { rows.contains { r in r.isManual && !r.locked } }
}

enum ExpenseSplitMath {
    /// 預設角色（§K 使用者還沒回，先照建議）：家人＝我請，其他人＝要還我。要改只改這一行
    static func defaultRole(_ name: String, family: Set<String>) -> String {
        family.contains(name) ? SplitShare.roleTreat : SplitShare.roleOwe
    }

    /// 平分：沒手改、沒還過的人每人 floor((總額 − 手改／還過的合計) ÷ (人數＋1 − 手改／還過的人數))；零頭全部算我。
    /// 例：1,000 元 3 人 → 我 334、別人 333、333
    static func rebalanced(_ d: ExpenseSplitDraft) -> ExpenseSplitDraft {
        var out = d
        let fixedRows = d.rows.filter { r in r.isManual || r.locked }
        let fixedSum: Double = fixedRows.reduce(0) { $0 + $1.amount }
        let freeCount = d.rows.count - fixedRows.count
        guard freeCount > 0 else { return out }
        let left: Double = max(0, d.total - fixedSum)
        let each: Double = (left / Double(freeCount + 1)).rounded(.down)
        for i in out.rows.indices where !out.rows[i].isManual && !out.rows[i].locked {
            out.rows[i].amount = each
        }
        return out
    }

    /// 存起來的那一頓 → 編輯器的列（還在的人，照原本的順序）
    static func rows(from split: ExpenseSplit) -> [ExpenseSplitDraftRow] {
        split.liveShares.map { s in
            ExpenseSplitDraftRow(id: s.id, name: s.name, role: s.role, amount: s.amount,
                                 isManual: s.isManual ?? false, locked: s.hasRepayment)
        }
    }

    /// 選人跟分帳對得上：names＝現在選的人（照 orderedSelected、去掉本人、去重）。
    /// 名單上有、列裡有的留著；新選的照預設角色加一列；取消的拿掉（還過錢的留著，選單本來就鎖住）；然後重新平分
    static func synced(_ d: ExpenseSplitDraft, names: [String], family: Set<String>) -> ExpenseSplitDraft {
        var out = d
        var rows: [ExpenseSplitDraftRow] = []
        var used = Set<UUID>()
        var seen = Set<String>()
        for name in names where !name.isEmpty && !seen.contains(name) {
            seen.insert(name)
            if let r = d.rows.first(where: { x in x.name == name && !used.contains(x.id) }) {
                rows.append(r)
                used.insert(r.id)
            } else {
                rows.append(ExpenseSplitDraftRow(id: UUID(), name: name, role: defaultRole(name, family: family),
                                                 amount: 0, isManual: false, locked: false))
            }
        }
        for r in d.rows where r.locked && !used.contains(r.id) {
            rows.append(r)
            used.insert(r.id)
        }
        out.rows = rows
        return rebalanced(out)
    }

    /// 表單現在的分帳：edited（使用者在「誰付多少」改過的）優先，沒有就用打開時那一包；照現在的人、現在的總額對一次
    static func resolve(edited: ExpenseSplitDraft?, loaded: ExpenseSplit?, names: [String], family: Set<String>,
                        total: Double) -> ExpenseSplitDraft {
        var base: ExpenseSplitDraft = edited
            ?? ExpenseSplitDraft(total: total, rows: loaded.map { s in rows(from: s) } ?? [])
        base.total = total
        return synced(base, names: names, family: family)
    }

    /// 改一個人的金額：標手改、重新平分其他人（還過錢的不能改）
    static func settingAmount(_ d: ExpenseSplitDraft, id: UUID, amount: Double) -> ExpenseSplitDraft {
        var out = d
        guard let i = out.rows.firstIndex(where: { r in r.id == id }), !out.rows[i].locked else { return d }
        out.rows[i].amount = max(0, amount.isFinite ? amount.rounded(.down) : 0)
        out.rows[i].isManual = true
        return rebalanced(out)
    }

    /// 改一個人的角色（金額不動）
    static func settingRole(_ d: ExpenseSplitDraft, id: UUID, role: String) -> ExpenseSplitDraft {
        var out = d
        guard let i = out.rows.firstIndex(where: { r in r.id == id }), !out.rows[i].locked else { return d }
        out.rows[i].role = role
        return out
    }

    /// 〔我請客〕：全部改成我請（還過錢的不動）
    static func allTreat(_ d: ExpenseSplitDraft) -> ExpenseSplitDraft {
        var out = d
        for i in out.rows.indices where !out.rows[i].locked {
            out.rows[i].role = SplitShare.roleTreat
        }
        return out
    }

    /// 〔大家平分〕：全部改成要還我、清掉手改、重新平分（還過錢的不動）
    static func evenOwe(_ d: ExpenseSplitDraft) -> ExpenseSplitDraft {
        var out = d
        for i in out.rows.indices where !out.rows[i].locked {
            out.rows[i].role = SplitShare.roleOwe
            out.rows[i].isManual = false
        }
        return rebalanced(out)
    }

    /// 〔重新平分〕：清掉手改、重新平分（角色不動）
    static func resetManual(_ d: ExpenseSplitDraft) -> ExpenseSplitDraft {
        var out = d
        for i in out.rows.indices where !out.rows[i].locked {
            out.rows[i].isManual = false
        }
        return rebalanced(out)
    }

    /// 金額欄打的字 → 整數元（空的、不是數字、負的＝nil）
    static func parseAmount(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
        guard !t.isEmpty, let v = Double(t), v.isFinite, v >= 0 else { return nil }
        return v.rounded(.down)
    }
}

// MARK: - 人（C6、C12）

/// 名字檢查的結果（搜尋框直接打名字）
enum SplitNameCheck: Equatable {
    case ok(String)
    case empty
    case badChar
    case tooLong
}

/// 搜尋框打的字 → 選單最上面那一列〔＋ 加「張家瑋」〕
struct SplitAddRow: Equatable {
    let name: String
    let enabled: Bool
    /// 灰掉時的小字
    let message: String?

    var title: String { "＋ 加「\(name)」" }
}

enum SplitPeople {
    /// 名字裡不准的字：「、」（diningMember 用它串）、逗號、分號、換行（載入用 `,、，` 切）
    static let forbidden = CharacterSet(charactersIn: "、,，;；\n\r")
    static let maxNameLength = 20

    /// 去掉前後空白；1–20 個字；不能有「、」逗號分號換行
    static func checkName(_ raw: String) -> SplitNameCheck {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return .empty }
        if t.rangeOfCharacter(from: forbidden) != nil { return .badChar }
        if t.count > maxNameLength { return .tooLong }
        return .ok(t)
    }

    /// 選單最上面那一列：nil＝不出現（沒打字、或名單裡已經有一模一樣的名字——直接勾那個人；跟本人一樣＝勾「我」）。
    /// knownNames＝名單上所有人＋已選的＋本人
    static func addRow(query: String, knownNames: Set<String>) -> SplitAddRow? {
        let t = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        switch checkName(query) {
        case .ok(let name):
            if knownNames.contains(name) { return nil }
            return SplitAddRow(name: name, enabled: true, message: nil)
        case .badChar:
            return SplitAddRow(name: t, enabled: false, message: ExpenseSplitText.nameBadChar)
        case .tooLong:
            return SplitAddRow(name: String(t.prefix(maxNameLength)) + "…", enabled: false,
                               message: ExpenseSplitText.nameTooLong)
        case .empty:
            return nil
        }
    }

    /// diningMember／socialRecipient 的字 → 名字（用 `,、，` 切、去空白、去重、照原本順序）
    static func names(in raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        var out: [String] = []
        var seen = Set<String>()
        for part in raw.components(separatedBy: CharacterSet(charactersIn: ",、，")) {
            let n = part.trimmingCharacters(in: .whitespaces)
            guard !n.isEmpty, !seen.contains(n) else { continue }
            seen.insert(n)
            out.append(n)
        }
        return out
    }

    /// C6 存檔的順序：本人 → 家人（照家人名單順序）→ 其他名字（排序後）。名單外的舊名字照留（不會被洗掉）。
    /// familyOrder＝AddExpenseView.familyNames（本人在第一個）
    static func ordered(_ selected: Set<String>, familyOrder: [String]) -> [String] {
        var out: [String] = []
        for n in familyOrder where selected.contains(n) && !out.contains(n) {
            out.append(n)
        }
        let rest: [String] = selected.subtracting(familyOrder).sorted()
        return out + rest
    }

    /// C6 打開舊的那筆：diningMember 用 `,、，` 切，再把分帳裡還在的人的名字併進來
    /// （更舊的 iPad 把名字洗掉時，這次存檔就會補回來）
    static func loadedMembers(diningMember: String?, split: ExpenseSplit?) -> Set<String> {
        var out = Set(names(in: diningMember))
        for s in split?.liveShares ?? [] {
            let n = s.name.trimmingCharacters(in: .whitespaces)
            if !n.isEmpty { out.insert(n) }
        }
        return out
    }

    /// 「最近一起吃過」：最近 days 天的變動支出裡 diningMember 出現最多的 limit 個名字（不含本人）。
    /// 一筆裡同一個名字只算一次；一樣多照最近一次新的、再照名字
    static func recentCompanions(expenses: [Expense], meName: String, now: Date, calendar: Calendar,
                                 limit: Int = 8, days: Int = 90) -> [String] {
        let today = calendar.startOfDay(for: now)
        let cutoff: Date = calendar.date(byAdding: .day, value: -days, to: today) ?? today
        var count: [String: Int] = [:]
        var last: [String: Date] = [:]
        for e in expenses where e.expenseType == .variable && e.date >= cutoff {
            for n in names(in: e.diningMember) where n != meName {
                count[n, default: 0] += 1
                if let d = last[n], d >= e.date { continue }
                last[n] = e.date
            }
        }
        let sorted: [String] = count.keys.sorted { a, b in
            let ca = count[a] ?? 0
            let cb = count[b] ?? 0
            if ca != cb { return ca > cb }
            let da = last[a] ?? .distantPast
            let db = last[b] ?? .distantPast
            if da != db { return da > db }
            return a < b
        }
        return Array(sorted.prefix(limit))
    }

    /// 本人＋家人的名字（錢包自動記帳只帶這些人；AddExpenseView 的 familyNames 同一套：中文名、空的不算）
    static func meAndFamily(profileName: String, family: [String]) -> Set<String> {
        var out = Set<String>()
        let me = profileName.trimmingCharacters(in: .whitespaces)
        if !me.isEmpty { out.insert(me) }
        for n in family {
            let t = n.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { out.insert(t) }
        }
        return out
    }

    static func meAndFamily(_ life: LifeStore) -> Set<String> {
        meAndFamily(profileName: life.profile.chineseName, family: life.familyMembers.map { m in m.chineseName })
    }

    /// C12 錢包自動記帳：帶過來的同行人員只留本人＋家人（朋友、同事、部屬拿掉；一個都不剩＝nil）。永遠不自動產生分帳
    static func familyOnly(_ raw: String?, allowed: Set<String>) -> String? {
        let kept = names(in: raw).filter { n in allowed.contains(n) }
        return kept.isEmpty ? nil : kept.joined(separator: "、")
    }
}

// MARK: - 〔已還〕、〔改成還沒還〕（C10）

/// 〔已還〕sheet(item:) 的 item
struct SplitRepayTarget: Identifiable, Equatable {
    let expenseId: UUID
    let shareId: UUID

    var id: UUID { shareId }
}

/// 開一張只看的 sheet（誰還欠我、誰付多少）用的 item
struct SplitSheetToken: Identifiable, Equatable {
    let id = UUID()
}

/// 〔改成還沒還〕要問的事
struct SplitUndoAsk: Identifiable, Equatable {
    let expenseId: UUID
    let shareId: UUID
    let repaymentId: UUID
    let depositId: UUID?
    let accountId: UUID?
    /// 「存摺上 11/21 那筆 NT$375 要一起刪掉嗎？」／現金「改成還沒還？」
    let title: String

    var id: UUID { repaymentId }
    /// 有存款（問〔一起刪〕〔只改成還沒還〕）；現金只問〔改成還沒還〕
    var hasDeposit: Bool { depositId != nil && accountId != nil }

    /// 那個人最近一筆還沒撤銷的還款；沒有回 nil
    static func make(split: ExpenseSplit, shareId: UUID, calendar: Calendar) -> SplitUndoAsk? {
        guard let s = split.liveShares.first(where: { x in x.id == shareId }), let r = s.lastRepayment else { return nil }
        let hasDeposit = r.depositId != nil && r.accountId != nil
        let title = hasDeposit
            ? ExpenseSplitText.undoDepositTitle(date: r.date, amount: r.amount, calendar: calendar)
            : ExpenseSplitText.undoCashTitle
        return SplitUndoAsk(expenseId: split.id, shareId: shareId, repaymentId: r.id,
                            depositId: r.depositId, accountId: r.accountId, title: title)
    }
}

enum ExpenseSplitRepay {
    /// 「上次用的」帳戶：只存這支手機（不同步）
    static let lastAccountKey = "lifegood.splitRepay.lastAccount"

    /// 能入帳的帳戶：照 AddIncomeView.bankMilestones（成就・銀行），再排除停用的
    static func accounts(_ milestones: [LifeMilestone]) -> [LifeMilestone] {
        milestones.filter { m in
            m.category == .achievement && m.financeSubCategory == .bank && m.isDisabled != true
        }
    }

    static func accountName(_ m: LifeMilestone) -> String {
        m.bankName ?? m.title
    }

    static func lastAccountId() -> UUID? {
        guard let s = UserDefaults.standard.string(forKey: lastAccountKey) else { return nil }
        return UUID(uuidString: s)
    }

    /// nil＝現金
    static func rememberAccount(_ id: UUID?) {
        if let id {
            UserDefaults.standard.set(id.uuidString, forKey: lastAccountKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastAccountKey)
        }
    }

    /// 預設選哪一個：上次用的還在就用它，不然第一個帳戶；沒有帳戶＝nil（現金）
    static func defaultAccountId(accounts: [LifeMilestone], last: UUID?) -> UUID? {
        if let last, accounts.contains(where: { m in m.id == last }) { return last }
        return accounts.first?.id
    }

    /// 存摺那一筆的備註：只有吃飯那天＋分類（不寫人名、不寫店名）。例「分帳還款・11/20 飲食」
    static func note(mealDate: Date, category: String, calendar: Calendar) -> String {
        "分帳還款・" + ExpenseSplitText.md(mealDate, calendar) + " " + category
    }

    static func note(for e: Expense, calendar: Calendar) -> String {
        note(mealDate: e.date, category: (e.variableCategory ?? .other).rawValue, calendar: calendar)
    }

    /// 存摺那一筆：存款、台幣、**linkedExpenseId 一定是 nil**
    static func deposit(id: UUID, date: Date, amount: Double, note: String) -> BankDeposit {
        BankDeposit(id: id, date: date, amount: amount, currencyCode: "NT$", isWithdrawal: false,
                    linkedExpenseId: nil, note: note, kind: BankDeposit.kindDeposit)
    }
}

/// 寫 store 的動作（一律在 dismiss 之後、下一個 runloop 叫：DispatchQueue.main.async { … }）
enum ExpenseSplitActions {
    /// 〔記下來〕：先寫存款、再標已還（中途當掉最壞是「多一筆存款、沒標已還」，看得到也能修）。
    /// 金額＝那個人還欠的全額（v1 不能改）。account nil＝現金。回完成提示的字；找不到那頓／那個人回 nil
    @discardableResult
    static func repay(expense e: Expense, shareId: UUID, date: Date, account: LifeMilestone?, life: LifeStore,
                      store: ExpenseSplitStore, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let split = store.index.split(for: e),
              let share = split.liveShares.first(where: { x in x.id == shareId }), share.owes else { return nil }
        let amount = share.outstanding
        guard amount >= 0.5 else { return nil }
        var depositId: UUID? = nil
        if let acc = account {
            let dep = ExpenseSplitRepay.deposit(id: UUID(), date: date, amount: amount,
                                                note: ExpenseSplitRepay.note(for: e, calendar: calendar))
            life.upsertBankDeposit(dep, in: acc.id)
            depositId = dep.id
        }
        let r = SplitRepayment(id: UUID(), date: date, amount: amount, accountId: account?.id, depositId: depositId)
        store.recordRepayment(expenseId: e.id, shareId: shareId, repayment: r, now: now)
        ExpenseSplitRepay.rememberAccount(account?.id)
        return ExpenseSplitText.repayDone(name: share.name, accountName: account.map { m in ExpenseSplitRepay.accountName(m) },
                                          amount: amount)
    }

    /// 〔一起刪〕／〔只改成還沒還〕：要刪的話先刪存摺那筆（找不到那筆或帳戶 deleteBankDeposit 自己略過），再撤銷還款
    static func undo(_ ask: SplitUndoAsk, deleteDeposit: Bool, life: LifeStore, store: ExpenseSplitStore,
                     now: Date = Date()) {
        if deleteDeposit, let dep = ask.depositId, let acc = ask.accountId {
            life.deleteBankDeposit(dep, in: acc, includingPair: false)
        }
        store.undoRepayment(expenseId: ask.expenseId, shareId: ask.shareId, repaymentId: ask.repaymentId, now: now)
    }
}

// MARK: - 畫面上的字（各組照叫，不要自己拼；sim 逐字對照）

enum ExpenseSplitText {
    /// 「有 1 筆等了 35 天」的門檻（超過 30 天）
    static let lateDays = 30

    static let rowTitle = "誰付多少"
    static let zeroAmount = "先填金額"
    static let treatAll = "我請客"
    static let evenAll = "大家平分"
    static let resetEven = "重新平分"
    static let manualTag = "手改"
    static let roleOweTitle = "要還我"
    static let roleTreatTitle = "我請"
    static let lockedNote = "已經還了；要改請到分帳那裡按〔改成還沒還〕"
    static let pickerTitle = "同行人員"
    static let pickerPrompt = "搜尋名字、部門、課別"
    static let pickerSubtitle = "家人、朋友、同事、部屬、名片都可以選；找不到就直接打名字"
    static let pickerLocked = "已經還了，要先在分帳裡改成還沒還"
    static let recentGroupTitle = "最近一起吃過"
    static let nameBadChar = "名字裡不能有「、」、逗號或分號"
    static let nameTooLong = "名字最多 20 個字"
    static let detailTitle = "分帳"
    static let repayButton = "已還"
    static let undoButton = "改成還沒還"
    static let undoCashTitle = "改成還沒還？"
    static let undoDeleteBoth = "一起刪"
    static let undoOnly = "只改成還沒還"
    static let reSplitButton = "重新分"
    static let owedTitle = "誰還欠我"
    static let owedOpenButton = "看誰還欠我"
    static let owedTabUnpaid = "還沒還"
    static let owedTabSettled = "還清了"
    static let owedEmpty = "都還清了"
    static let owedSettledEmpty = "最近 90 天沒有還清的"
    static let owedPrivacy = "這裡只在 App 裡看得到，不會出現在通知、小工具、手錶或鎖定畫面。"
    static let repayDateLabel = "日期"
    static let repayWhereLabel = "進哪裡"
    static let repayCash = "現金（不記到存摺）"
    static let repayLastTag = "（上次用的）"
    static let repaySave = "記下來"
    static let dropConfirm = "還是換"
    static let shareAskTitle = "要分享的內容有同行成員和社交對象的名字"
    static let shareDropNames = "拿掉名字再分享"
    static let shareAsIs = "照樣分享"
    static let walletFamilyOnly = "只會帶家人，朋友、同事不會自動帶。"

    /// 「NT$1,500」：四捨五入到元（.5 進位）、千分位
    static func ntd(_ v: Double) -> String {
        guard v.isFinite, abs(v) < 1e15 else { return "NT$0" }
        let r = Int(abs(v).rounded(.toNearestOrAwayFromZero))
        let digits = String(r)
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return (v < 0 && r > 0 ? "-" : "") + "NT$" + out
    }

    /// 「11/20」
    static func md(_ d: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.month, .day], from: d)
        return "\(c.month ?? 0)/\(c.day ?? 0)"
    }

    /// 「2026/11/22」
    static func ymd(_ d: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return "\(c.year ?? 0)/\(c.month ?? 0)/\(c.day ?? 0)"
    }

    /// 兩天差幾天（各自的 startOfDay；負的算 0）
    static func daysBetween(_ from: Date, _ to: Date, calendar: Calendar) -> Int {
        let a = calendar.startOfDay(for: from)
        let b = calendar.startOfDay(for: to)
        return max(0, calendar.dateComponents([.day], from: a, to: b).day ?? 0)
    }

    /// 清單上那一頓的字：名稱（去空白），空的用分類
    static func mealTitle(_ e: Expense) -> String {
        let t = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? (e.variableCategory ?? .other).rawValue : t
    }

    /// 表單那一列右邊：「2 人要還我・NT$750」／「我請客」
    static func summaryValue(_ d: ExpenseSplitDraft) -> String {
        d.owedCount > 0 ? "\(d.owedCount) 人要還我・\(ntd(d.owedTotal))" : treatAll
    }

    /// 編輯器最上面：「這頓 NT$1,500・4 人」（人數含我）
    static func editorHeader(_ d: ExpenseSplitDraft) -> String {
        "這頓 \(ntd(d.total))・\(d.rows.count + 1) 人"
    }

    /// 「我（張家瑋）」；profile 沒名字＝「我」
    static func meLabel(_ meName: String) -> String {
        meName.isEmpty ? "我" : "我（\(meName)）"
    }

    /// 「NT$375（剩下的）」
    static func meValue(_ d: ExpenseSplitDraft) -> String {
        "\(ntd(d.meAmount))（剩下的）"
    }

    /// 段尾第一行：「要還你 2 人・NT$750」／全部我請「全部我請客」
    static func footerOwe(_ d: ExpenseSplitDraft) -> String {
        d.owedCount > 0 ? "要還你 \(d.owedCount) 人・\(ntd(d.owedTotal))" : "全部我請客"
    }

    /// 段尾第二行：「記帳只算你 NT$750（自己 NT$375＋請客 NT$375）；刷卡、扣款照 NT$1,500」
    static func footerOwn(_ d: ExpenseSplitDraft) -> String {
        var s = "記帳只算你 \(ntd(d.ownAmount))"
        if d.treatTotal >= 0.5 && d.owedCount > 0 {
            s += "（自己 \(ntd(d.meAmount))＋請客 \(ntd(d.treatTotal))）"
        }
        return s + "；刷卡、扣款照 \(ntd(d.total))"
    }

    /// 超過總額（紅字）：「分出去的 NT$1,700 比這筆 NT$1,500 多 NT$200」
    static func overText(_ d: ExpenseSplitDraft) -> String {
        "分出去的 \(ntd(d.assigned)) 比這筆 \(ntd(d.total)) 多 \(ntd(d.overBy))"
    }

    /// 超過 8 人摺起來：「還有 3 人 ›」
    static func foldedText(_ n: Int) -> String { "還有 \(n) 人 ›" }

    /// 已還那一列：「已還 11/21・國泰世華 ✓」／現金「已還 11/21・現金 ✓」
    static func paidLine(date: Date, accountName: String?, calendar: Calendar) -> String {
        "已還 \(md(date, calendar))・\(accountName ?? "現金") ✓"
    }

    /// 詳情卡那一列右邊：要還我「要還我 NT$375」、我請「我請 NT$375」、已還「已還 NT$375・11/21・國泰世華 ✓」
    static func detailShare(_ s: SplitShare, accountName: String?, calendar: Calendar) -> String {
        if !s.owes { return "\(roleTreatTitle) \(ntd(s.amount))" }
        if s.isSettled, let r = s.lastRepayment {
            return "已還 \(ntd(s.repaidTotal))・\(md(r.date, calendar))・\(accountName ?? "現金") ✓"
        }
        return "\(roleOweTitle) \(ntd(s.outstanding))"
    }

    /// 詳情卡最後一行：「這頓算你的 NT$750（自己 NT$375＋請客 NT$375）」
    static func detailOwn(_ split: ExpenseSplit, amount: Double) -> String {
        let live = split.liveShares
        let assigned: Double = live.reduce(0) { $0 + $1.amount }
        let owed = split.owedTotal
        let treat = split.treatTotal
        let own: Double = owed > 0 ? max(0, amount - owed) : amount
        var s = "這頓算你的 \(ntd(own))"
        if treat >= 0.5 && owed > 0 {
            s += "（自己 \(ntd(amount - assigned))＋請客 \(ntd(treat))）"
        }
        return s
    }

    /// 金額改過（黃字）：「這筆金額改過了（分的時候 NT$1,500，現在 NT$1,800），要重新分嗎？」
    static func amountChanged(base: Double, now: Double) -> String {
        "這筆金額改過了（分的時候 \(ntd(base))，現在 \(ntd(now))），要重新分嗎？"
    }

    /// 〔已還〕sheet 標題：「王小明 還了 NT$375」
    static func repayTitle(name: String, amount: Double) -> String { "\(name) 還了 \(ntd(amount))" }

    /// 「2026/11/22（今天）」
    static func repayDate(_ d: Date, now: Date, calendar: Calendar) -> String {
        calendar.isDate(d, inSameDayAs: now) ? "\(ymd(d, calendar))（今天）" : ymd(d, calendar)
    }

    /// 「選帳戶的話，存摺會多一筆 NT$375 的存款「分帳還款・11/20 飲食」。」
    static func repayExplain(amount: Double, note: String) -> String {
        "選帳戶的話，存摺會多一筆 \(ntd(amount)) 的存款「\(note)」。"
    }

    /// 完成提示：「記好了：國泰世華 ＋NT$375」／現金「記好了：王小明 已還（現金）」
    static func repayDone(name: String, accountName: String?, amount: Double) -> String {
        if let a = accountName { return "記好了：\(a) ＋\(ntd(amount))" }
        return "記好了：\(name) 已還（現金）"
    }

    /// 「存摺上 11/21 那筆 NT$375 要一起刪掉嗎？」
    static func undoDepositTitle(date: Date, amount: Double, calendar: Calendar) -> String {
        "存摺上 \(md(date, calendar)) 那筆 \(ntd(amount)) 要一起刪掉嗎？"
    }

    /// 誰還欠我最上面：「還欠你 NT$750・2 人・2 筆」
    static func owedHeader(_ s: SplitOwedSummary) -> String {
        "還欠你 \(ntd(s.total))・\(s.people) 人・\(s.meals) 筆"
    }

    /// 變動支出頁入口右邊：「2 人・NT$750」
    static func owedEntryValue(_ s: SplitOwedSummary) -> String {
        "\(s.people) 人・\(ntd(s.total))"
    }

    /// 入口的橘字：「有 1 筆等了 35 天」（沒有超過 30 天的＝nil）
    static func owedLate(_ s: SplitOwedSummary) -> String? {
        s.lateCount > 0 ? "有 \(s.lateCount) 筆等了 \(s.maxDays) 天" : nil
    }

    /// 一個人那一行右邊：「NT$375（1 頓）」／「NT$375（1 頓・等了 35 天）」
    static func owedPersonValue(_ p: SplitOwedPerson) -> String {
        let late = p.maxDays > lateDays ? "・等了 \(p.maxDays) 天" : ""
        return "\(ntd(p.total))（\(p.meals.count) 頓\(late)）"
    }

    /// 一頓那一行左邊：「11/20 鼎泰豐 信義店」
    static func owedMealLabel(_ m: SplitOwedMeal, calendar: Calendar) -> String {
        "\(md(m.date, calendar)) \(m.title)"
    }

    /// 換成不能分帳的分類時的 alert：「換成「交通」就不能分帳，王小明、陳怡君 還沒還的 NT$750 會一起拿掉。」
    static func dropMessage(target: String, names: [String], amount: Double) -> String {
        "換成「\(target)」就不能分帳，\(names.joined(separator: "、")) 還沒還的 \(ntd(amount)) 會一起拿掉。"
    }

    /// 統計說明小字（這個月有扣才出現）：「有分帳的飯只算你自己那份：這個月扣掉要還你的 NT$750。」
    static func statsNote(_ deducted: Double) -> String? {
        deducted >= 0.5 ? "有分帳的飯只算你自己那份：這個月扣掉要還你的 \(ntd(deducted))。" : nil
    }
}

/// C7 換分類 alert 要的東西（AddExpenseView 存檔前算；nil＝不用問）
struct SplitDropAsk: Identifiable, Equatable {
    let id = UUID()
    let message: String

    /// loaded＝打開時那一包；canSplit＝這次存的還能不能分帳；target＝換成的分類字（固定支出寫「固定支出」）
    static func make(loaded: ExpenseSplit?, canSplit: Bool, target: String) -> SplitDropAsk? {
        guard !canSplit, let s = loaded else { return nil }
        let unpaid = s.liveShares.filter { x in x.owes && !x.hasRepayment && x.outstanding >= 0.5 }
        guard !unpaid.isEmpty else { return nil }
        let total: Double = unpaid.reduce(0) { $0 + $1.outstanding }
        return SplitDropAsk(message: ExpenseSplitText.dropMessage(target: target, names: unpaid.map { x in x.name },
                                                                  amount: total))
    }
}

// MARK: - 存、讀、同步（C4；照 ExpenseKindStore）

extension Notification.Name {
    /// ExpenseSplitStore 的 book 變了（自己存、iCloud 合併、備份）。ExpenseStore 聽這個只跳 modifyID（不指派 expenses、不存、不推）
    static let expenseSplitsDidChange = Notification.Name("expenseSplitsDidChange")
}

final class ExpenseSplitStore: ObservableObject {
    static let shared = ExpenseSplitStore()

    @Published private(set) var book: ExpenseSplitBook {
        didSet { index = ExpenseSplitIndex(book: book) }
    }
    /// 所有畫面、統計問這個（book 一變就重建；不要每次算統計都重建）
    private(set) var index: ExpenseSplitIndex

    private init() {
        let b = Self.readStored()
        book = b
        index = ExpenseSplitIndex(book: b)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadFromCloud(_:)),
            name: .cloudSyncDidPullChanges,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private static func readStored() -> ExpenseSplitBook {
        guard let d = UserDefaults.standard.data(forKey: ExpenseSplitBook.syncKey),
              let b = try? JSONDecoder().decode(ExpenseSplitBook.self, from: d) else { return ExpenseSplitBook() }
        return b
    }

    /// 寫進 UserDefaults、推 iCloud。**不碰 expenses**（不會引發記帳整包重寫）。
    /// 編碼失敗：印一行、不覆蓋舊資料、不推（照 UtilityReadingStore）
    private func persist() {
        do {
            let d = try JSONEncoder().encode(book)
            UserDefaults.standard.set(d, forKey: ExpenseSplitBook.syncKey)
        } catch {
            print("[ExpenseSplitStore] 分帳那一包編碼失敗，沒有存：\(error)")
            return
        }
        CloudSyncManager.shared.pushAll()
    }

    /// 自己寫的唯一一條路：清墓碑 → 跟現在一樣就不動 → 存、推、通知重畫
    private func commit(_ next: ExpenseSplitBook, now: Date) {
        let cleaned = next.purged(now: now)
        guard cleaned != book else { return }
        book = cleaned
        persist()
        NotificationCenter.default.post(name: .expenseSplitsDidChange, object: nil)
    }

    /// AddExpenseView 存檔那一刻（dismiss 之後、下一個 runloop 叫；每次存檔都叫，它自己判斷要不要寫）。
    /// draft＝這次存的分帳（這筆不能分帳、或沒有別人＝nil）
    func recordSave(expenseId: UUID, draft: ExpenseSplitDraft?, now: Date = Date()) {
        guard let next = book.saving(expenseId: expenseId, draft: draft, now: now) else { return }
        commit(next, now: now)
    }

    /// ExpenseStore.delete：有分帳的寫整頓墓碑
    func recordDelete(ids: Set<UUID>, now: Date = Date()) {
        guard !ids.isEmpty, let next = book.deleting(ids: ids, now: now) else { return }
        commit(next, now: now)
    }

    /// 〔已還〕（ExpenseSplitActions.repay 叫；存款已經先寫好）
    func recordRepayment(expenseId: UUID, shareId: UUID, repayment: SplitRepayment, now: Date = Date()) {
        guard let next = book.repaying(expenseId: expenseId, shareId: shareId, repayment: repayment) else { return }
        commit(next, now: now)
    }

    /// 〔改成還沒還〕（ExpenseSplitActions.undo 叫）
    func undoRepayment(expenseId: UUID, shareId: UUID, repaymentId: UUID, now: Date = Date()) {
        guard let next = book.undoingRepayment(expenseId: expenseId, shareId: shareId, repaymentId: repaymentId,
                                               now: now) else { return }
        commit(next, now: now)
    }

    /// 匯出：只帶這幾筆支出的
    func exportBook(for ids: Set<UUID>) -> ExpenseSplitBook {
        book.filtered(to: ids)
    }

    /// 備份〔取代〕（整批記帳歸這份檔案管）：整包換成備份裡的
    func importReplacingAll(_ other: ExpenseSplitBook, now: Date = Date()) {
        commit(other, now: now)
    }

    /// 備份〔取代〕（只帶了一部分支出，例如旅遊）：這幾個 id 換成備份裡的
    func importReplacing(ids: Set<UUID>, with other: ExpenseSplitBook, now: Date = Date()) {
        commit(book.replacing(ids: ids, with: other), now: now)
    }

    /// 備份〔合併〕：一個人一個人合（一樣新留本機的）
    func importMerging(_ other: ExpenseSplitBook, now: Date = Date()) {
        commit(book.merged(with: other), now: now)
    }

    /// 設定「清除所有資料」（ExpenseStore.clearAll 叫）：寫一包空的推上去（不是刪鍵：刪鍵的話雲端那份不會被蓋掉）
    func clearAll() {
        let wasEmpty = book == ExpenseSplitBook()
        book = ExpenseSplitBook()
        persist()
        if !wasEmpty { NotificationCenter.default.post(name: .expenseSplitsDidChange, object: nil) }
    }

    /// 聽 iCloud（照 ExpenseKindStore.reloadFromCloud）：帶了 keys 而且含這個鍵 → 雲端那份併上本機剛才那份，
    /// 合出來跟雲端那份不一樣（本機有它沒有的）就存回去、推上去；沒帶 keys（以雲端覆蓋這台、第一次合併已經合好）照雲端那包
    @objc private func reloadFromCloud(_ note: Notification) {
        let keys = note.userInfo?["keys"] as? [String]
        if let keys, !keys.contains(ExpenseSplitBook.syncKey) { return }
        let before = book
        let cloud = Self.readStored()
        let next: ExpenseSplitBook = keys == nil ? cloud : cloud.merged(with: before)
        if next != before { book = next }
        if next != cloud { persist() }
        if next != before { NotificationCenter.default.post(name: .expenseSplitsDidChange, object: nil) }
    }
}

/// 第一次同步〔合併〕（CloudSyncManager.resolveInitialSync）：這個鍵最上層是物件，mergeBlob 會整包留勝方、另一邊的分帳不見；
/// 解成 Book 一個人一個人合併。解不開回 nil（退回原本的 mergeBlob）
enum ExpenseSplitSync {
    static func handles(_ key: String) -> Bool {
        key == ExpenseSplitBook.syncKey
    }

    static func mergeInitialBlob(local: Data?, cloud: Data?, localWins: Bool) -> Data? {
        guard let l = local, let c = cloud else { return nil }
        let dec = JSONDecoder()
        guard let lb = try? dec.decode(ExpenseSplitBook.self, from: l),
              let cb = try? dec.decode(ExpenseSplitBook.self, from: c) else { return nil }
        let merged: ExpenseSplitBook = localWins ? lb.merged(with: cb) : cb.merged(with: lb)
        return try? JSONEncoder().encode(merged)
    }
}
