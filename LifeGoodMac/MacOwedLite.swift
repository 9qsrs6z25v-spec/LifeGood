// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.646 mac6 G2] 誰還欠我的唯讀精簡版（judge_mac.md §T3-2）：分帳包（lifegood_expense_splits_v1）解成畫面要的人、頓、還款。
//
// • 只給畫面：寫入層永遠不用這個檔的型別（macwrite 擋 Writer 收 MacOwed*；分帳寫入走 MacSplitPatch 的 raw JSON 局部改）。
// • 名字只在畫面（不進 .help、log、⌘C、日誌、備份檔名）；不存 accountId／depositId 的值，只存兩個 Bool。
// • 每支上一行「照抄 ES:行（258fea0）」；sim 編號 owed6#N（sim_mac6 owed_suite6／owed_text6）。
// • 型別、欄位、簽名照主控定案（跨組名稱表 §T7-6）；狀態那幾個 computed（ES:198-243）與 MacOwedText 的常數主控照抄、G2 逐字核對過。
// • 解碼用 iPhone 同一套 JSONDecoder 規則（ES:85-194 的 init(from:)；檔尾 MacOwed*Coded，只在這檔）。

import Foundation

// MARK: - 一筆還款、一個人、一頓

/// 照抄 ES:71-83、:168-194（258fea0）SplitRepayment：id 必填、date 讀不到＝distantPast（留著）、amount 讀不到 0
struct MacOwedRepay: Equatable {
    let id: UUID
    let date: Date
    let amount: Double
    /// 撤銷（〔改成還沒還〕）
    let removedAt: Date?
    /// accountId 解得出 UUID（照 iPhone：有帳戶名的那種還款）
    let account: Bool
    /// accountId 或 depositId 鍵在（值是什麼都算；頁面預先反灰用，比 iPhone 保守）
    let touchesBank: Bool

    /// 照抄 ES:198-200（258fea0）
    var isLive: Bool { removedAt == nil }
}

/// 照抄 ES:49-69、:133-164（258fea0）SplitShare（Mac 不解 isManual、updatedAt：畫面用不到）
struct MacOwedShare: Equatable {
    let id: UUID
    /// 名字快照（只在畫面）
    let name: String
    /// "treat"＝我請、"owe"＝要還我；看不懂的值一律照我請
    let role: String
    let amount: Double
    /// 逐筆解（壞一筆只丟那筆）；鍵不在＝[]
    let repayments: [MacOwedRepay]
    let removedAt: Date?

    // 照抄 ES:202-224（258fea0）
    var liveRepayments: [MacOwedRepay] { repayments.filter { r in r.isLive } }
    var hasRepayment: Bool { repayments.contains { r in r.isLive } }
    var repaidTotal: Double { liveRepayments.reduce(0) { $0 + $1.amount } }
    var isLive: Bool { removedAt == nil || hasRepayment }
    var owes: Bool { role == "owe" }
    var outstanding: Double { owes ? max(0, amount - repaidTotal) : 0 }
    var isSettled: Bool { owes && hasRepayment && outstanding < 0.5 }
    /// 最近一筆還沒撤銷的還款（日期新的；一樣新取後面那筆）
    var lastRepayment: MacOwedRepay? {
        var best: MacOwedRepay? = nil
        for r in liveRepayments {
            if let b = best, b.date > r.date { continue }
            best = r
        }
        return best
    }
}

/// 照抄 ES:34-46、:106-131（258fea0）ExpenseSplit（id＝Expense.id）
struct MacOwedSplit: Equatable {
    let id: UUID
    let baseAmount: Double
    let updatedAt: Date?
    let deletedAt: Date?
    let shares: [MacOwedShare]

    // 照抄 ES:229-236（258fea0）
    var liveShares: [MacOwedShare] {
        guard deletedAt == nil else { return [] }
        return shares.filter { s in s.isLive }
    }
    var owedTotal: Double { liveShares.filter { s in s.owes }.reduce(0) { $0 + $1.amount } }
    var treatTotal: Double { liveShares.filter { s in !s.owes }.reduce(0) { $0 + $1.amount } }
}

// MARK: - 誰還欠我：一人一頓、一個人、最上面那一列

/// 照抄 ES:700-716（258fea0）SplitOwedMeal；Mac 多帶給按鈕預判的四個欄位
struct MacOwedMeal: Identifiable, Equatable {
    let expenseID: UUID
    let shareID: UUID
    /// 只在畫面
    let name: String
    /// 吃飯那天（Expense.date）
    let date: Date
    /// 列上的字（店名；沒打名字用分類）
    let title: String
    /// 還沒還：還欠多少；還清了：還了多少
    let amount: Double
    /// 還沒還：等了幾天；還清了：隔了幾天才還
    let days: Int
    let repaidDate: Date?
    /// 最後一筆還款有帳戶（畫面寫「帳戶」，不讀存摺包）
    let account: Bool
    /// 那個人的 lastRepayment.id（〔改成還沒還〕的 ref）
    let lastRepaymentID: UUID?
    /// lastRepayment 有 accountId 或 depositId 鍵（預先反灰 deposit）
    let lastTouchesBank: Bool
    /// share.removedAt != nil（預先反灰 share_removed）
    let shareRemoved: Bool
    /// 有活的還款但 outstanding ≥ 0.5（預先反灰 partial）
    let partial: Bool

    /// 照抄 ES:715（258fea0）
    var id: String { expenseID.uuidString + "|" + shareID.uuidString }
}

/// 照抄 ES:719-726（258fea0）SplitOwedPerson（照名字原字串分組）
struct MacOwedPerson: Identifiable, Equatable {
    let name: String
    let total: Double
    let maxDays: Int
    let meals: [MacOwedMeal]

    var id: String { name }
}

/// 照抄 ES:728-738（258fea0）SplitOwedSummary
struct MacOwedSummary: Equatable {
    var people: Int = 0
    var total: Double = 0
    var meals: Int = 0
    /// 等了超過 30 天的筆數
    var lateCount: Int = 0
    var maxDays: Int = 0

    /// 入口要不要出現（還沒還的總額 ≥ 0.5）
    var showsEntry: Bool { total >= 0.5 }
}

// MARK: - 讀（畫面只問這個）

/// 照抄 ES:556-580（258fea0）ExpenseSplitIndex；寫入層永遠不用這個型別
struct MacOwedBook: Equatable {
    static let empty = MacOwedBook(data: nil)

    /// 只放 deletedAt == nil && !liveShares.isEmpty（同 id 留 updatedAt 新的、一樣新留先出現的）
    let byID: [UUID: MacOwedSplit]

    /// 頂層不是物件或 splits 不是陣列＝空（只給畫面）。照抄 ES:562-569（258fea0）ExpenseSplitIndex.init
    init(data: Data?) {
        // sim6: owed6#1 解碼：iPhone 同一個 JSONDecoder（日期＝2001 起算秒數）；壞一筆只丟那筆
        var splits: [MacOwedSplit] = []
        if let data, let book = try? JSONDecoder().decode(MacOwedBookCoded.self, from: data) {
            splits = book.splits
        }
        // sim6: owed6#2 同 id 留 updatedAt 新的（一樣新留先出現的）；只放 deletedAt == nil && !liveShares.isEmpty
        var best: [UUID: MacOwedSplit] = [:]
        for s in splits {
            if let b = best[s.id], (b.updatedAt ?? .distantPast) >= (s.updatedAt ?? .distantPast) { continue }
            best[s.id] = s
        }
        byID = best.filter { _, s in s.deletedAt == nil && !s.liveShares.isEmpty }
    }

    var isEmpty: Bool { byID.isEmpty }

    /// 照抄 ES:577-580（258fea0）：變動支出才算分帳
    func split(for e: Expense) -> MacOwedSplit? {
        guard e.expenseType == .variable else { return nil }
        return byID[e.id]
    }

    /// 照抄 ES:620-633（258fea0）還沒還（一人一頓一列）。只算 expenses 裡還在的變動支出（孤兒不出現）
    func owedMeals(expenses: [Expense], now: Date, calendar: Calendar) -> [MacOwedMeal] {
        // sim6: owed6#3 照傳進來的 expenses 順序；owes && !isSettled && outstanding >= 0.5
        guard !byID.isEmpty else { return [] }
        var out: [MacOwedMeal] = []
        for e in expenses {
            guard let s = split(for: e) else { continue }
            for sh in s.liveShares where sh.owes && !sh.isSettled && sh.outstanding >= 0.5 {
                out.append(Self.meal(e, sh, amount: sh.outstanding,
                                     days: MacOwedText.daysBetween(e.date, now, calendar: calendar), last: nil))
            }
        }
        return out
    }

    /// 照抄 ES:636-652（258fea0）最近 days 天內還清的（照最後一筆還款的日期）
    func settledMeals(expenses: [Expense], now: Date, calendar: Calendar, days: Int = 90) -> [MacOwedMeal] {
        // sim6: owed6#4 cutoff＝startOfDay(now) − days 天；last.date >= cutoff；amount＝repaidTotal；days＝吃飯那天到還錢那天
        guard !byID.isEmpty else { return [] }
        let today = calendar.startOfDay(for: now)
        let cutoff: Date = calendar.date(byAdding: .day, value: -days, to: today) ?? today
        var out: [MacOwedMeal] = []
        for e in expenses {
            guard let s = split(for: e) else { continue }
            for sh in s.liveShares where sh.isSettled {
                guard let last = sh.lastRepayment, last.date >= cutoff else { continue }
                out.append(Self.meal(e, sh, amount: sh.repaidTotal,
                                     days: MacOwedText.daysBetween(e.date, last.date, calendar: calendar), last: last))
            }
        }
        return out
    }

    /// 一頓（ES:626-629、:645-649 的 SplitOwedMeal(...)＋Mac 多帶的 4 個預判欄位；sim6: owed6#5）
    private static func meal(_ e: Expense, _ sh: MacOwedShare, amount: Double, days: Int, last: MacOwedRepay?) -> MacOwedMeal {
        let latest: MacOwedRepay? = sh.lastRepayment
        return MacOwedMeal(expenseID: e.id, shareID: sh.id, name: sh.name, date: e.date,
                           title: MacOwedText.mealTitle(e), amount: amount, days: days,
                           repaidDate: last?.date, account: last?.account ?? false,
                           lastRepaymentID: latest?.id, lastTouchesBank: latest?.touchesBank ?? false,
                           shareRemoved: sh.removedAt != nil,
                           partial: sh.hasRepayment && sh.outstanding >= 0.5)
    }

    /// 照抄 ES:655-672（258fea0）依人分組：人照金額由大到小（一樣多照名字），每頓照日期新到舊（同日照 id 字串）
    static func people(_ meals: [MacOwedMeal]) -> [MacOwedPerson] {
        // sim6: owed6#6 照名字原字串分組
        var byName: [String: [MacOwedMeal]] = [:]
        for m in meals { byName[m.name, default: []].append(m) }
        var out: [MacOwedPerson] = []
        for (name, list) in byName {
            let sorted: [MacOwedMeal] = list.sorted { a, b in
                if a.date != b.date { return a.date > b.date }
                return a.id < b.id
            }
            let total: Double = list.reduce(0) { $0 + $1.amount }
            let maxDays: Int = list.map { m in m.days }.max() ?? 0
            out.append(MacOwedPerson(name: name, total: total, maxDays: maxDays, meals: sorted))
        }
        return out.sorted { a, b in
            if a.total != b.total { return a.total > b.total }
            return a.name < b.name
        }
    }

    /// 照抄 ES:675-683（258fea0）最上面那一列：還沒還的人數（名字去重）、總額、筆數、超過 30 天的筆數、最久幾天
    func summary(expenses: [Expense], now: Date, calendar: Calendar) -> MacOwedSummary {
        // sim6: owed6#7
        let meals = owedMeals(expenses: expenses, now: now, calendar: calendar)
        let names = Set(meals.map { m in m.name })
        let total: Double = meals.reduce(0) { $0 + $1.amount }
        let late = meals.filter { m in m.days > MacOwedText.lateDays }
        let maxDays: Int = meals.map { m in m.days }.max() ?? 0
        return MacOwedSummary(people: names.count, total: total, meals: meals.count, lateCount: late.count, maxDays: maxDays)
    }

    /// 側欄用（Mac 自己的）：還沒還的人數（名字去重）、showsEntry（總額 ≥ 0.5）；跟日子無關（不算 days）
    func sidebarCount(expenses: [Expense]) -> (people: Int, shows: Bool) {
        // sim6: owed6#8 跟 summary 同一組條件（owedMeals 那一行），只是不算 days
        guard !byID.isEmpty else { return (0, false) }
        var names: Set<String> = []
        var total: Double = 0
        for e in expenses {
            guard let s = split(for: e) else { continue }
            for sh in s.liveShares where sh.owes && !sh.isSettled && sh.outstanding >= 0.5 {
                names.insert(sh.name)
                total += sh.outstanding
            }
        }
        return (names.count, total >= 0.5)
    }
}

// MARK: - 畫面上的字（照抄 ES:1171-1385（258fea0）ExpenseSplitText；只抄要用的）

enum MacOwedText {
    /// 照抄 ES:1173（258fea0）
    static let lateDays = 30
    /// 照抄 ES:1194（258fea0）
    static let undoCashTitle = "改成還沒還？"
    /// 照抄 ES:1202（258fea0）
    static let owedEmpty = "都還清了"
    /// 照抄 ES:1203（258fea0）
    static let owedSettledEmpty = "最近 90 天沒有還清的"
    /// 照抄 ES:1207（258fea0）
    static let repayCash = "現金（不記到存摺）"

    /// 照抄 ES:1217-1227（258fea0）「NT$1,500」：四捨五入到元（.5 進位）、千分位
    static func ntd(_ v: Double) -> String {
        // sim6: owed6#9
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

    /// 照抄 ES:1230-1233（258fea0）「11/20」
    static func md(_ d: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.month, .day], from: d)
        return "\(c.month ?? 0)/\(c.day ?? 0)"
    }

    /// 照抄 ES:1236-1239（258fea0）「2026/11/22」
    static func ymd(_ d: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return "\(c.year ?? 0)/\(c.month ?? 0)/\(c.day ?? 0)"
    }

    /// 照抄 ES:1242-1246（258fea0）兩天差幾天（各自的 startOfDay；負的算 0）
    static func daysBetween(_ from: Date, _ to: Date, calendar: Calendar) -> Int {
        let a = calendar.startOfDay(for: from)
        let b = calendar.startOfDay(for: to)
        return max(0, calendar.dateComponents([.day], from: a, to: b).day ?? 0)
    }

    /// 照抄 ES:1249-1252（258fea0）名稱（去空白），空的用分類（`.other` 這個 case，不寫字面值）
    static func mealTitle(_ e: Expense) -> String {
        let t = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? (e.variableCategory ?? .other).rawValue : t
    }

    /// 照抄 ES:1297-1299（258fea0）「已還 11/21・現金 ✓」；accountName 由呼叫端給 account ? "帳戶" : nil
    static func paidLine(date: Date, accountName: String?, calendar: Calendar) -> String {
        "已還 \(md(date, calendar))・\(accountName ?? "現金") ✓"
    }

    /// 照抄 ES:1302-1308（258fea0）詳情欄那一列右邊
    static func detailShare(_ s: MacOwedShare, accountName: String?, calendar: Calendar) -> String {
        // ES 的 roleTreatTitle／roleOweTitle 是「我請」「要還我」（MacOwedText 不另放常數）
        if !s.owes { return "我請 \(ntd(s.amount))" }
        if s.isSettled, let r = s.lastRepayment {
            return "已還 \(ntd(s.repaidTotal))・\(md(r.date, calendar))・\(accountName ?? "現金") ✓"
        }
        return "要還我 \(ntd(s.outstanding))"
    }

    /// 照抄 ES:1311-1322（258fea0）「這頓算你的 NT$750（自己 NT$375＋請客 NT$375）」
    static func detailOwn(_ split: MacOwedSplit, amount: Double) -> String {
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

    /// 照抄 ES:1325-1327（258fea0），Mac 字尾改「，請在 iPhone 重新分」
    static func amountChanged(base: Double, now: Double) -> String {
        "這筆金額改過了（分的時候 \(ntd(base))，現在 \(ntd(now))），請在 iPhone 重新分"
    }

    /// 照抄 ES:1330（258fea0）「王小明 還了 NT$375」（只在畫面）
    static func repayTitle(name: String, amount: Double) -> String { "\(name) 還了 \(ntd(amount))" }

    /// 照抄 ES:1333-1335（258fea0）「2026/11/22（今天）」
    static func repayDate(_ d: Date, now: Date, calendar: Calendar) -> String {
        calendar.isDate(d, inSameDayAs: now) ? "\(ymd(d, calendar))（今天）" : ymd(d, calendar)
    }

    /// 照抄 ES:1343-1346（258fea0）「記好了：王小明 已還（現金）」（只在狀態膠囊）
    static func repayDone(name: String, accountName: String?, amount: Double) -> String {
        if let a = accountName { return "記好了：\(a) ＋\(ntd(amount))" }
        return "記好了：\(name) 已還（現金）"
    }

    /// 照抄 ES:1364-1366（258fea0）「有 1 筆等了 35 天」（沒有超過 30 天的＝nil）
    static func owedLate(_ s: MacOwedSummary) -> String? {
        s.lateCount > 0 ? "有 \(s.lateCount) 筆等了 \(s.maxDays) 天" : nil
    }

    /// 照抄 ES:1369-1372（258fea0）「NT$375（1 頓・等了 35 天）」
    static func owedPersonValue(_ p: MacOwedPerson) -> String {
        let late = p.maxDays > lateDays ? "・等了 \(p.maxDays) 天" : ""
        return "\(ntd(p.total))（\(p.meals.count) 頓\(late)）"
    }
}

// MARK: - 解碼（照抄 ES:85-194（258fea0）的 init(from:)；只在這檔；看不懂的鍵不收、不寫回：這裡只給畫面）

/// 照抄 Competency.swift:162（258fea0）CompetencySkip
private struct MacOwedSkip: Decodable {}

/// 照抄 Competency.swift:121-132（258fea0）CompetencyCoding.lossyArray：一筆壞掉只丟那一筆；鍵不在或不是陣列＝nil
private func macOwedLossyArray<T: Decodable, K: CodingKey>(_ type: T.Type, _ c: KeyedDecodingContainer<K>, _ key: K) -> [T]? {
    guard c.contains(key), var arr = try? c.nestedUnkeyedContainer(forKey: key) else { return nil }
    var out: [T] = []
    while !arr.isAtEnd {
        if let v = try? arr.decode(T.self) {
            out.append(v)
        } else if (try? arr.decode(MacOwedSkip.self)) == nil {
            break
        }
    }
    return out
}

/// {"splits": [...]}；別的鍵一律不看（ES:96-100）
private struct MacOwedBookCoded: Decodable {
    let splits: [MacOwedSplit]

    private enum CodingKeys: String, CodingKey {
        case splits
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let list: [MacOwedSplitCoded] = macOwedLossyArray(MacOwedSplitCoded.self, c, .splits) ?? []
        splits = list.map { x in x.value }
    }
}

/// 照抄 ES:111-120（258fea0）ExpenseSplit.init(from:)：id 必填
private struct MacOwedSplitCoded: Decodable {
    let value: MacOwedSplit

    private enum CodingKeys: String, CodingKey {
        case id, baseAmount, shares, updatedAt, deletedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(UUID.self, forKey: .id)
        let baseAmount: Double = (try? c.decodeIfPresent(Double.self, forKey: .baseAmount)) ?? 0
        let shares: [MacOwedShareCoded] = macOwedLossyArray(MacOwedShareCoded.self, c, .shares) ?? []
        let updatedAt: Date? = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        let deletedAt: Date? = try? c.decodeIfPresent(Date.self, forKey: .deletedAt)
        value = MacOwedSplit(id: id, baseAmount: baseAmount, updatedAt: updatedAt, deletedAt: deletedAt,
                             shares: shares.map { x in x.value })
    }
}

/// 照抄 ES:138-150（258fea0）SplitShare.init(from:)：id 必填、name ""、role "treat"、amount 0（isManual、updatedAt 畫面用不到）
private struct MacOwedShareCoded: Decodable {
    let value: MacOwedShare

    private enum CodingKeys: String, CodingKey {
        case id, name, role, amount, repayments, removedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(UUID.self, forKey: .id)
        let name: String = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        let role: String = (try? c.decodeIfPresent(String.self, forKey: .role)) ?? "treat"
        let amount: Double = (try? c.decodeIfPresent(Double.self, forKey: .amount)) ?? 0
        let reps: [MacOwedRepayCoded] = macOwedLossyArray(MacOwedRepayCoded.self, c, .repayments) ?? []
        let removedAt: Date? = try? c.decodeIfPresent(Date.self, forKey: .removedAt)
        value = MacOwedShare(id: id, name: name, role: role, amount: amount, repayments: reps.map { x in x.value },
                             removedAt: removedAt)
    }
}

/// 照抄 ES:184-194（258fea0）SplitRepayment.init(from:)：id 必填、date 讀不到＝distantPast（留著）、amount 讀不到 0。
/// 不存 accountId／depositId 的值：account＝accountId 解得出 UUID；touchesBank＝兩個鍵任一個在（值是什麼都算，null 也算）
private struct MacOwedRepayCoded: Decodable {
    let value: MacOwedRepay

    private enum CodingKeys: String, CodingKey {
        case id, date, amount, accountId, depositId, removedAt
    }

    init(from decoder: Decoder) throws {
        // sim6: owed6#10 account／touchesBank（accountId 是怪字串：account false、touchesBank true）
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(UUID.self, forKey: .id)
        let date: Date = (try? c.decodeIfPresent(Date.self, forKey: .date)) ?? Date.distantPast
        let amount: Double = (try? c.decodeIfPresent(Double.self, forKey: .amount)) ?? 0
        let accountID: UUID? = try? c.decodeIfPresent(UUID.self, forKey: .accountId)
        let removedAt: Date? = try? c.decodeIfPresent(Date.self, forKey: .removedAt)
        let touches: Bool = c.contains(.accountId) || c.contains(.depositId)
        value = MacOwedRepay(id: id, date: date, amount: amount, removedAt: removedAt, account: accountID != nil,
                             touchesBank: touches)
    }
}
