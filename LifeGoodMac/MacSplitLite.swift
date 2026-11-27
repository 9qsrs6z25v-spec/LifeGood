// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.640 mac1] 分帳（lifegood_expense_splits_v1）的唯讀精簡版：只為了「只算自己那份」（brief.md §G2-4、judge_mac.md §C5、§O7）。
//
// • 只解 id、baseAmount、updatedAt、deletedAt、shares[id, role, amount, removedAt, repayments[id, removedAt]]；
//   Mac 1 **不解人名**、不解還款金額、帳戶、存摺。看不懂的那一筆、那一個人、那一筆還款照 iOS 逐筆丟掉（CompetencyCoding.lossyArray）。
// • 這裡的型別只拿來算數字，**永遠不進寫入層**（macwrite.py 擋 Writer 收 Lite 型別）；Mac 1 不寫這個鍵。
// • 規則照抄 ExpenseSplits.swift（25.639）：ExpenseSplitIndex.init（:560-569）、SplitShare.isLive／hasRepayment（:206-209）、
//   ExpenseSplit.liveShares／owedTotal（:229-234）、ownAmount（:584-588）、deducted（:609-617）。sim_mac1.py split_index／own_amount／deducted 對照。

import Foundation

// MARK: - 讀（統計只准問這個）

struct MacSplitIndex {
    static let empty = MacSplitIndex(data: nil)

    /// 只放有人、不是整頓墓碑的（同一個 id 兩筆留 updatedAt 新的）；值＝那頓還在的人
    private let byId: [UUID: [MacSplitLiteShare]]

    /// 解不開（不是物件、沒有這個鍵）＝空的，跟 ExpenseSplitStore.readStored 一樣
    init(data: Data?) {
        var book = MacSplitLiteBook()
        if let data, let b = try? JSONDecoder().decode(MacSplitLiteBook.self, from: data) {
            book = b
        }
        // 照抄 ExpenseSplits.swift:560-569（25.639）ExpenseSplitIndex.init
        var best: [UUID: MacSplitLiteSplit] = [:]
        for s in book.splits ?? [] {
            if let b = best[s.id], (b.updatedAt ?? .distantPast) >= (s.updatedAt ?? .distantPast) { continue }
            best[s.id] = s
        }
        var live: [UUID: [MacSplitLiteShare]] = [:]
        for (id, s) in best {
            let shares = s.liveShares
            if s.deletedAt == nil && !shares.isEmpty { live[id] = shares }
        }
        byId = live
    }

    var isEmpty: Bool { byId.isEmpty }

    /// 有分帳（還有人在）的那幾筆支出 id（MacEditPolicy 用：這幾筆金額、日期、分類請在 iPhone 改）
    var liveIDs: Set<UUID> { Set(byId.keys) }

    /// 變動支出才算分帳（固定支出、分類換掉的舊紀錄一律當沒有）
    func liveShares(for e: Expense) -> [MacSplitLiteShare]? {
        guard e.expenseType == .variable else { return nil }
        return byId[e.id]
    }

    /// 要還我的加總（已還、沒還都算：那是別人的錢）（照抄 ExpenseSplits.swift:234 owedTotal）
    func owedTotal(for e: Expense) -> Double {
        guard let shares = liveShares(for: e) else { return 0 }
        return shares.filter { s in s.owes }.reduce(0) { $0 + $1.amount }
    }

    /// 這筆算你自己的錢（照抄 ExpenseSplits.swift:584-588（25.639）ExpenseSplitIndex.ownAmount）
    func ownAmount(_ e: Expense) -> Double {
        guard liveShares(for: e) != nil else { return e.amount }
        let owed = owedTotal(for: e)
        return owed > 0 ? max(0, e.amount - owed) : e.amount
    }

    /// 那個月的變動支出因為分帳扣掉多少（照抄 ExpenseSplits.swift:609-617（25.639）ExpenseSplitIndex.deducted）
    func deducted(expenses: [Expense], month: Date, calendar: Calendar) -> Double {
        guard !byId.isEmpty else { return 0 }
        var sum = 0.0
        for e in expenses where e.expenseType == .variable && byId[e.id] != nil
            && calendar.isDate(e.date, equalTo: month, toGranularity: .month) {
            sum += e.amount - ownAmount(e)
        }
        return sum
    }
}

// MARK: - 資料長相（唯讀；不解人名）

/// {"splits": [...]}；其他鍵一律不看
struct MacSplitLiteBook: Decodable {
    var splits: [MacSplitLiteSplit]?

    private enum CodingKeys: String, CodingKey {
        case splits
    }

    init() {
        splits = nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        splits = macSplitLossyArray(MacSplitLiteSplit.self, c, .splits)
    }
}

/// 一頓飯的分帳（id ＝ Expense.id）
struct MacSplitLiteSplit: Decodable {
    var id: UUID
    var baseAmount: Double
    var shares: [MacSplitLiteShare]?
    var updatedAt: Date?
    var deletedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, baseAmount, shares, updatedAt, deletedAt
    }

    // 照抄 ExpenseSplits.swift:111-120（25.639）ExpenseSplit.init(from:)（不解 extra）
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        baseAmount = (try? c.decodeIfPresent(Double.self, forKey: .baseAmount)) ?? 0
        shares = macSplitLossyArray(MacSplitLiteShare.self, c, .shares)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        deletedAt = try? c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    /// 還在的人（整頓墓碑＝沒有人）（照抄 ExpenseSplits.swift:229-232）
    var liveShares: [MacSplitLiteShare] {
        guard deletedAt == nil else { return [] }
        return (shares ?? []).filter { s in s.isLive }
    }
}

/// 一個人（不含「我」）；Mac 1 不解人名
struct MacSplitLiteShare: Decodable {
    static let roleOwe = "owe"
    static let roleTreat = "treat"

    var id: UUID
    /// "treat"＝我請、"owe"＝要還我；看不懂的值一律照我請
    var role: String
    var amount: Double
    var repayments: [MacSplitLiteRepayment]?
    var removedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, role, amount, repayments, removedAt
    }

    // 照抄 ExpenseSplits.swift:138-150（25.639）SplitShare.init(from:)（只留算錢要的欄位）
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        role = (try? c.decodeIfPresent(String.self, forKey: .role)) ?? MacSplitLiteShare.roleTreat
        amount = (try? c.decodeIfPresent(Double.self, forKey: .amount)) ?? 0
        repayments = macSplitLossyArray(MacSplitLiteRepayment.self, c, .repayments)
        removedAt = try? c.decodeIfPresent(Date.self, forKey: .removedAt)
    }

    /// 有還過（還沒撤銷）（照抄 ExpenseSplits.swift:206）
    var hasRepayment: Bool { (repayments ?? []).contains { r in r.removedAt == nil } }
    /// 還在這頓裡（沒拿掉；拿掉了但還過錢的也算）（照抄 ExpenseSplits.swift:209）
    var isLive: Bool { removedAt == nil || hasRepayment }
    /// 要還我（照抄 ExpenseSplits.swift:211）
    var owes: Bool { role == MacSplitLiteShare.roleOwe }
}

/// 一筆還款：只看有沒有撤銷
struct MacSplitLiteRepayment: Decodable {
    var id: UUID
    var removedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, removedAt
    }

    // 照抄 ExpenseSplits.swift:184-194（25.639）SplitRepayment.init(from:)：id 一定要有；日期、金額 Mac 1 不看
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        removedAt = try? c.decodeIfPresent(Date.self, forKey: .removedAt)
    }
}

// MARK: - 逐筆解（照抄 Competency.swift:121-132（25.639）CompetencyCoding.lossyArray）

private struct MacSplitSkip: Decodable {}

private func macSplitLossyArray<T: Decodable, K: CodingKey>(_ type: T.Type, _ c: KeyedDecodingContainer<K>, _ key: K) -> [T]? {
    guard c.contains(key), var arr = try? c.nestedUnkeyedContainer(forKey: key) else { return nil }
    var out: [T] = []
    while !arr.isAtEnd {
        if let v = try? arr.decode(T.self) {
            out.append(v)
        } else if (try? arr.decode(MacSplitSkip.self)) == nil {
            break
        }
    }
    return out
}
