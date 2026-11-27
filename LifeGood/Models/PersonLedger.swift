import Foundation

// [v25.635] 名片看得到往來（peoplehub1；judge_peoplehub §C1、§F、§G）
//
// 全部是純函式：只讀傳進來的支出陣列、ExpenseSplitIndex、LifeStore 的名單；
// 不寫 store、不寫 UserDefaults、不存任何新資料、沒有新同步鍵。這個檔只進 App target（小工具、手錶都不編）。
// - 名字對人：兩邊都套 LifeStore.normalizedPersonName（去半形／全形空白、trim、轉小寫），完全相等才算。
//   不比子字串（「小明」≠「王小明」）、不去括號（「王小明（業務）」≠「王小明」）、不另外去分隔符號。
// - 範圍：變動支出；同行的人用 SplitPeople.loadedMembers（跟「誰還欠我」、記帳表單載入同一套）。
// - 每頓只看分帳裡還在的人（liveShares：拿掉但還過錢的照留）裡名字對上的那幾列；同一頓同名兩列金額加總。
// - 只同行、沒分帳（或分帳裡沒有這位）＝「一起」：算次數，金額一律 0，不加進任何合計。
// - 一起吃飯只算飲食；其他有同行的分類算「一起出去」。
// - 還欠我＝跟「誰還欠我」同一條（要還我、還沒還清、還欠 ≥ 0.5 元）；已還算全部時間（不套「還清了」的 90 天）。
// - 自己（個人資料的中文名；中文名空才用英文名）在名字組合裡 → 只寫「這是你自己的名片」，什麼都不算。
// 名字、金額只在 App 內頁：不上通知、小工具、手錶、鎖定畫面、靈動島；名片 QR、vCard、匯出到聯絡人都不帶（複製出來的名片同名，改名前往來一樣）。
// [v25.636] peoplehub2：同名提醒裡分組是「家人」的人際關係算「家人」（以前寫「朋友」）；多一支通用的 snapshot(subject:…)
// 給家人頁、朋友頁用（PersonLedgerSubject；名片頁照舊用 cardSnapshot，一行沒改）；snapshot 多 privacyText（卡片最底下那行小字）。
// 朋友（既有 Relationship，一個欄位都沒加）的純函式在 Models/FriendBook.swift。

// MARK: - 值

/// 這一頓這位是什麼：我請、要還我、只是一起（同一頓同名有我請也有要還我 → .owe，我請那份記在 treatAmount）
enum PersonLedgerRole: String, Equatable {
    case treat
    case owe
    case together
}

/// 還欠我的一列（一頓裡同名兩列就兩個 part；〔已還〕一次還一列，跟 SplitRepaySheet 一樣）
struct PersonLedgerOwedPart: Identifiable, Equatable {
    let expenseId: UUID
    let shareId: UUID
    /// 吃飯那天（Expense.date）
    let date: Date
    /// 店名；沒打名字用分類（ExpenseSplitText.mealTitle）
    let title: String
    /// 還欠多少
    let amount: Double

    var id: String { expenseId.uuidString + "|" + shareId.uuidString }

    init(expenseId: UUID, shareId: UUID, date: Date, title: String, amount: Double) {
        self.expenseId = expenseId
        self.shareId = shareId
        self.date = date
        self.title = title
        self.amount = amount
    }
}

/// 一頓一列
struct PersonLedgerEntry: Identifiable, Equatable {
    let expenseId: UUID
    let date: Date
    let title: String
    /// 飲食＝一起吃飯；其他分類＝一起出去
    let isFood: Bool
    let role: PersonLedgerRole
    /// 這位那份裡「要還我」的加總（已還、沒還都算）
    let oweAmount: Double
    /// 這位那份裡「我請」的加總（看不懂的角色也算我請，跟 ExpenseSplitIndex 一致）
    let treatAmount: Double
    /// 有沒有我請的那一列（金額 0 也算一次）
    let hasTreat: Bool
    /// 還欠多少（跟「誰還欠我」同一條）
    let outstanding: Double
    /// 已還（還沒撤銷的還款；只算要還我的列）
    let repaid: Double
    let lastRepaidDate: Date?
    /// 這一頓對上的分帳列（同名兩列就兩個）
    let shareIds: [UUID]
    /// 還欠我的那幾列（〔已還〕用）
    let owedParts: [PersonLedgerOwedPart]

    var id: UUID { expenseId }

    /// 這位那份（我請＋要還我；只是一起＝0）
    var amount: Double { oweAmount + treatAmount }

    init(expenseId: UUID, date: Date, title: String, isFood: Bool, role: PersonLedgerRole,
         oweAmount: Double, treatAmount: Double, hasTreat: Bool, outstanding: Double, repaid: Double,
         lastRepaidDate: Date?, shareIds: [UUID], owedParts: [PersonLedgerOwedPart]) {
        self.expenseId = expenseId
        self.date = date
        self.title = title
        self.isFood = isFood
        self.role = role
        self.oweAmount = oweAmount
        self.treatAmount = treatAmount
        self.hasTreat = hasTreat
        self.outstanding = outstanding
        self.repaid = repaid
        self.lastRepaidDate = lastRepaidDate
        self.shareIds = shareIds
        self.owedParts = owedParts
    }
}

/// 卡片上面的數字
struct PersonLedgerSummary: Equatable {
    /// 一起吃飯幾頓（只算飲食）
    var mealCount: Int = 0
    /// 一起出去幾次（飲食以外有同行的分類）
    var outingCount: Int = 0
    /// 最新一筆的日期
    var lastDate: Date? = nil
    /// 我請幾次、這位那份加總（不是整頓的錢）
    var treatCount: Int = 0
    var treatTotal: Double = 0
    /// 還欠我（Σ outstanding）
    var owedTotal: Double = 0
    /// 已還（全部時間）
    var repaidTotal: Double = 0
    /// 還沒還的頓數
    var unpaidCount: Int = 0
    /// 還沒還的都是飲食（「還有 1 頓沒還」；有別的分類寫「筆」）
    var unpaidAllFood: Bool = true

    init() {}
}

/// 名單的來源（同名提醒只寫類別和人數，不寫是誰）
enum PersonSource: String, CaseIterable {
    case family
    case relationship
    case subordinate
    case orgPerson
    case businessCard

    var label: String {
        switch self {
        case .family: return "家人"
        case .relationship: return "朋友"
        case .subordinate: return "部屬"
        case .orgPerson: return "公司組織"
        case .businessCard: return "名片"
        }
    }
}

/// 名單上的一位（只有來源和名字 key；部屬只讀 name）
struct PersonLedgerCandidate: Equatable {
    let source: PersonSource
    let key: String

    init(source: PersonSource, key: String) {
        self.source = source
        self.key = key
    }
}

/// 數同名時不算的那幾筆（就是這一位自己：這張名片、連到的組織圖人員、那位人員連到的部屬）
struct PersonLedgerExclude: Equatable {
    var cardId: UUID?
    var orgPersonId: UUID?
    var subordinateId: UUID?
    var relationshipId: UUID?
    var familyMemberId: UUID?

    init(cardId: UUID? = nil, orgPersonId: UUID? = nil, subordinateId: UUID? = nil,
         relationshipId: UUID? = nil, familyMemberId: UUID? = nil) {
        self.cardId = cardId
        self.orgPersonId = orgPersonId
        self.subordinateId = subordinateId
        self.relationshipId = relationshipId
        self.familyMemberId = familyMemberId
    }
}

/// [v25.636] 家人頁、朋友頁的往來卡要算誰（名字組合、數同名時不算的那一筆、是自己時那一行字）
struct PersonLedgerSubject: Equatable {
    let primary: String
    let extra: [String]
    let exclude: PersonLedgerExclude
    let selfText: String

    init(primary: String, extra: [String], exclude: PersonLedgerExclude, selfText: String) {
        self.primary = primary
        self.extra = extra
        self.exclude = exclude
        self.selfText = selfText
    }

    /// 朋友：Relationship.name（v3 才加別名）
    static func friend(_ r: Relationship) -> PersonLedgerSubject {
        PersonLedgerSubject(primary: r.name, extra: [], exclude: PersonLedgerExclude(relationshipId: r.id),
                            selfText: PersonLedgerText.selfPerson)
    }

    /// 家人：中文名；中文名空才用英文名（跟 SplitPeople.meAndFamily 一致）
    static func family(_ m: FamilyMember) -> PersonLedgerSubject {
        let c = m.chineseName.trimmingCharacters(in: .whitespaces)
        return PersonLedgerSubject(primary: c.isEmpty ? m.englishName : c, extra: [],
                                   exclude: PersonLedgerExclude(familyMemberId: m.id),
                                   selfText: PersonLedgerText.selfPerson)
    }
}

/// 往來卡要的全部（畫面只拿這個；@State 放一份）
struct PersonLedgerSnapshot: Equatable {
    var entries: [PersonLedgerEntry] = []
    var summary = PersonLedgerSummary()
    /// 同名提醒（沒有同名＝nil）
    var sameNameText: String? = nil
    /// 是自己＝「這是你自己的名片」（其他都不算）
    var selfText: String? = nil
    /// [v25.636] 卡片最底下那行隱私小字（名片頁照舊；家人頁、朋友頁用 PersonLedgerText.privacyPerson）
    var privacyText: String = PersonLedgerText.privacy

    init() {}

    /// 卡片要不要放（沒有任何紀錄、也不是自己＝整張不放）
    var shows: Bool { selfText != nil || !entries.isEmpty }
}

// MARK: - 算

enum PersonLedger {
    /// 比對用的 key（只做 LifeStore.normalizedPersonName：去半形、全形空白、trim、轉小寫）
    static func key(_ s: String) -> String {
        LifeStore.normalizedPersonName(s)
    }

    /// 這一位的名字組合（key 的集合；空的丟掉）。名片：卡名＋連到的組織圖人員名
    static func names(primary: String, extra: [String]) -> Set<String> {
        var out = Set<String>()
        for n in [primary] + extra {
            let k = PersonLedger.key(n)
            if !k.isEmpty { out.insert(k) }
        }
        return out
    }

    /// 顯示用的名字（去前後空白、key 一樣的只留第一個、照原本順序）
    static func displayNames(primary: String, extra: [String]) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for n in [primary] + extra {
            let t = n.trimmingCharacters(in: .whitespacesAndNewlines)
            let k = PersonLedger.key(t)
            guard !k.isEmpty, !seen.contains(k) else { continue }
            seen.insert(k)
            out.append(t)
        }
        return out
    }

    /// 本人的 key（分帳裡的「我」用中文名；中文名空才用英文名，跟 SplitPeople.meAndFamily 一致）
    static func meKeys(_ profile: UserProfile) -> Set<String> {
        let c = profile.chineseName.trimmingCharacters(in: .whitespaces)
        return names(primary: c.isEmpty ? profile.englishName : c, extra: [])
    }

    /// 名字組合裡有本人 → 是自己
    static func isSelf(keys: Set<String>, meKeys: Set<String>) -> Bool {
        !keys.isDisjoint(with: meKeys)
    }

    /// 一筆支出 → 這一位的那一列（不是變動支出、同行裡沒有這位＝nil）
    static func entry(for e: Expense, split: ExpenseSplit?, keys: Set<String>) -> PersonLedgerEntry? {
        guard e.expenseType == .variable, !keys.isEmpty else { return nil }
        let members = SplitPeople.loadedMembers(diningMember: e.diningMember, split: split)
        let hit = members.contains { n in keys.contains(PersonLedger.key(n)) }
        guard hit else { return nil }
        let title = ExpenseSplitText.mealTitle(e)
        let isFood = (e.variableCategory ?? .other) == .food
        var owe = 0.0
        var treat = 0.0
        var hasOwe = false
        var hasTreat = false
        var outstanding = 0.0
        var repaid = 0.0
        var last: Date? = nil
        var ids: [UUID] = []
        var parts: [PersonLedgerOwedPart] = []
        for sh in split?.liveShares ?? [] where keys.contains(PersonLedger.key(sh.name)) {
            ids.append(sh.id)
            guard sh.owes else {
                hasTreat = true
                treat += sh.amount
                continue
            }
            hasOwe = true
            owe += sh.amount
            repaid += sh.repaidTotal
            if let r = sh.lastRepayment, r.date > (last ?? .distantPast) {
                last = r.date
            }
            let left = sh.outstanding
            if !sh.isSettled && left >= 0.5 {
                outstanding += left
                parts.append(PersonLedgerOwedPart(expenseId: e.id, shareId: sh.id, date: e.date,
                                                  title: title, amount: left))
            }
        }
        let role: PersonLedgerRole = hasOwe ? .owe : (hasTreat ? .treat : .together)
        return PersonLedgerEntry(expenseId: e.id, date: e.date, title: title, isFood: isFood, role: role,
                                 oweAmount: owe, treatAmount: treat, hasTreat: hasTreat,
                                 outstanding: outstanding, repaid: repaid, lastRepaidDate: last,
                                 shareIds: ids, owedParts: parts)
    }

    /// 這一位的每一頓（日期新到舊；一樣新照 id）。是自己、沒有名字＝空的
    static func entries(expenses: [Expense], index: ExpenseSplitIndex, keys: Set<String>,
                        meKeys: Set<String>) -> [PersonLedgerEntry] {
        guard !keys.isEmpty, !isSelf(keys: keys, meKeys: meKeys) else { return [] }
        var out: [PersonLedgerEntry] = []
        for e in expenses {
            if let x = entry(for: e, split: index.split(for: e), keys: keys) {
                out.append(x)
            }
        }
        return out.sorted { a, b in
            if a.date != b.date { return a.date > b.date }
            return a.expenseId.uuidString < b.expenseId.uuidString
        }
    }

    /// 卡片上面的數字（只同行的那幾頓只加次數）
    static func summary(_ entries: [PersonLedgerEntry]) -> PersonLedgerSummary {
        var s = PersonLedgerSummary()
        for x in entries {
            if x.isFood {
                s.mealCount += 1
            } else {
                s.outingCount += 1
            }
            if x.date > (s.lastDate ?? .distantPast) {
                s.lastDate = x.date
            }
            if x.hasTreat {
                s.treatCount += 1
                s.treatTotal += x.treatAmount
            }
            s.owedTotal += x.outstanding
            s.repaidTotal += x.repaid
            if !x.owedParts.isEmpty {
                s.unpaidCount += 1
                if !x.isFood { s.unpaidAllFood = false }
            }
        }
        return s
    }

    /// 名單上所有人（家人：中文名，中文名空才用英文名；朋友；部屬只讀 name；組織圖同事；名片），不含 exclude 那幾筆
    static func candidates(life: LifeStore, exclude: PersonLedgerExclude) -> [PersonLedgerCandidate] {
        var out: [PersonLedgerCandidate] = []
        func add(_ source: PersonSource, _ name: String) {
            let k = PersonLedger.key(name)
            if !k.isEmpty { out.append(PersonLedgerCandidate(source: source, key: k)) }
        }
        for m in life.familyMembers where m.id != exclude.familyMemberId {
            let c = m.chineseName.trimmingCharacters(in: .whitespaces)
            add(.family, c.isEmpty ? m.englishName : c)
        }
        for r in life.relationships where r.id != exclude.relationshipId {
            // [v25.636] 分組是「家人」的算家人（同名提醒寫「家人」不寫「朋友」）
            add(r.group == .family ? .family : .relationship, r.name)
        }
        for s in life.subordinates where s.id != exclude.subordinateId {
            add(.subordinate, s.name)
        }
        for p in life.orgPeople where p.id != exclude.orgPersonId {
            add(.orgPerson, p.name)
        }
        for c in life.businessCards where c.id != exclude.cardId {
            add(.businessCard, c.name)
        }
        return out
    }

    /// 名單裡還有幾位同名（照來源分）
    static func sameNameHits(keys: Set<String>, candidates: [PersonLedgerCandidate]) -> [PersonSource: Int] {
        var out: [PersonSource: Int] = [:]
        for c in candidates where keys.contains(c.key) {
            out[c.source, default: 0] += 1
        }
        return out
    }

    static func sameNameHits(keys: Set<String>, life: LifeStore, exclude: PersonLedgerExclude) -> [PersonSource: Int] {
        sameNameHits(keys: keys, candidates: candidates(life: life, exclude: exclude))
    }

    /// 名片詳情頁的往來卡（.task(id:) 裡叫；只讀）
    static func cardSnapshot(card: BusinessCard, life: LifeStore, expenses: [Expense],
                             index: ExpenseSplitIndex) -> PersonLedgerSnapshot {
        let person: OrgPerson? = card.linkedOrgPersonId.flatMap { pid in
            life.orgPeople.first { p in p.id == pid }
        }
        let extra: [String] = person.map { p in [p.name] } ?? []
        let keys = names(primary: card.name, extra: extra)
        var snap = PersonLedgerSnapshot()
        guard !keys.isEmpty else { return snap }
        let me = meKeys(life.profile)
        if isSelf(keys: keys, meKeys: me) {
            snap.selfText = PersonLedgerText.selfCard
            return snap
        }
        let list = entries(expenses: expenses, index: index, keys: keys, meKeys: me)
        guard !list.isEmpty else { return snap }
        snap.entries = list
        snap.summary = summary(list)
        let exclude = PersonLedgerExclude(cardId: card.id, orgPersonId: person?.id,
                                          subordinateId: person?.linkedSubordinateId)
        let hits = sameNameHits(keys: keys, life: life, exclude: exclude)
        snap.sameNameText = PersonLedgerText.sameName(names: displayNames(primary: card.name, extra: extra),
                                                      hits: hits)
        return snap
    }

    /// [v25.636] 家人頁、朋友頁的往來卡（.task(id:) 裡叫；只讀）。規則跟 cardSnapshot 一樣，只是名字組合、
    /// 不算同名的那一筆、是自己時那一行字由 subject 給；隱私小字換成 privacyPerson
    static func snapshot(subject: PersonLedgerSubject, life: LifeStore, expenses: [Expense],
                         index: ExpenseSplitIndex) -> PersonLedgerSnapshot {
        let keys = names(primary: subject.primary, extra: subject.extra)
        var snap = PersonLedgerSnapshot()
        snap.privacyText = PersonLedgerText.privacyPerson
        guard !keys.isEmpty else { return snap }
        let me = meKeys(life.profile)
        if isSelf(keys: keys, meKeys: me) {
            snap.selfText = subject.selfText
            return snap
        }
        let list = entries(expenses: expenses, index: index, keys: keys, meKeys: me)
        guard !list.isEmpty else { return snap }
        snap.entries = list
        snap.summary = summary(list)
        let hits = sameNameHits(keys: keys, life: life, exclude: subject.exclude)
        snap.sameNameText = PersonLedgerText.sameName(names: displayNames(primary: subject.primary, extra: subject.extra),
                                                      hits: hits)
        return snap
    }

    /// C4 選人單：名單裡的名字能不能勾（有「、」逗號分號換行、超過 20 字、空的都不行；不幫使用者改名）
    static func canPick(_ name: String) -> Bool {
        switch SplitPeople.checkName(name) {
        case .ok:
            return true
        case .empty, .badChar, .tooLong:
            return false
        }
    }
}

// MARK: - 畫面上的字（往來卡、選人單灰掉的列都從這裡拿；寫名字或「這位」，不用代名詞）

enum PersonLedgerText {
    static let title = "往來"
    static let selfCard = "這是你自己的名片"
    static let owedSection = "還欠我"
    static let recentSection = "最近"
    static let together = "一起"
    /// 「最近」先列幾筆
    static let recentLimit = 5
    static let collapseAll = "收起來"
    static let privacy = "照記帳時選的名字算；只在 App 裡看得到，名片 QR、匯出到聯絡人都不會帶到。複製出來的名片改名之前，往來會跟原本那張一樣。"
    static let pickerBlockedNote = "名字裡有逗號或太長，請先到名片改名"
    /// [v25.636] 家人頁、朋友頁往來卡最底下那行
    static let privacyPerson = "照記帳時選的名字算；只在 App 裡看得到，不會上通知、小工具、手錶、鎖定畫面。"
    /// [v25.636] 家人頁、朋友頁：名字跟個人資料一樣
    static let selfPerson = "名字跟你自己的一樣，往來不另外算"
    /// [v25.636] 往來卡收合那一行的 VoiceOver 值
    static let a11yExpanded = "展開"
    static let a11yCollapsed = "收合"

    /// 收合那一行：「一起吃飯 6 頓・一起出去 2 次・最近 11/18」（沒有金額）
    static func header(_ s: PersonLedgerSummary, calendar: Calendar) -> String {
        var parts: [String] = []
        if s.mealCount > 0 { parts.append("一起吃飯 \(s.mealCount) 頓") }
        if s.outingCount > 0 { parts.append("一起出去 \(s.outingCount) 次") }
        if let d = s.lastDate { parts.append("最近 " + ExpenseSplitText.md(d, calendar)) }
        return parts.joined(separator: "・")
    }

    /// 收合那一行下面：「還有 1 頓沒還」（沒有金額；都還了＝nil）
    static func unpaid(_ s: PersonLedgerSummary) -> String? {
        guard s.unpaidCount > 0 else { return nil }
        return "還有 \(s.unpaidCount) " + (s.unpaidAllFood ? "頓" : "筆") + "沒還"
    }

    /// 展開後的摘要：「我請 2 次 NT$1,840」「還欠我 NT$375」「已還 NT$750」；0 的那項不顯示
    static func totals(_ s: PersonLedgerSummary) -> [String] {
        var out: [String] = []
        if s.treatCount > 0 { out.append("我請 \(s.treatCount) 次 " + ExpenseSplitText.ntd(s.treatTotal)) }
        if s.owedTotal >= 0.5 { out.append("還欠我 " + ExpenseSplitText.ntd(s.owedTotal)) }
        if s.repaidTotal >= 0.5 { out.append("已還 " + ExpenseSplitText.ntd(s.repaidTotal)) }
        return out
    }

    /// 一列左邊：「11/20 鼎泰豐 信義店」
    static func rowLabel(date: Date, title: String, calendar: Calendar) -> String {
        ExpenseSplitText.md(date, calendar) + " " + title
    }

    /// 「最近」那一列右邊：「我請 NT$460」「要還我 NT$375」「已還 NT$375」「一起」
    static func rowValue(_ x: PersonLedgerEntry) -> String {
        switch x.role {
        case .together:
            return together
        case .treat:
            return "我請 " + ExpenseSplitText.ntd(x.treatAmount)
        case .owe:
            if x.outstanding >= 0.5 { return "要還我 " + ExpenseSplitText.ntd(x.outstanding) }
            if x.repaid >= 0.5 { return "已還 " + ExpenseSplitText.ntd(x.repaid) }
            return "要還我 " + ExpenseSplitText.ntd(x.oweAmount)
        }
    }

    /// 〔看全部 12 筆〕
    static func seeAll(_ n: Int) -> String { "看全部 \(n) 筆" }

    /// 同名提醒：「照名字「王小明」對；名單裡還有 1 位同名（部屬），紀錄會算在一起。」（只寫類別和人數；沒有同名＝nil）
    static func sameName(names: [String], hits: [PersonSource: Int]) -> String? {
        let total: Int = hits.values.reduce(0, +)
        guard total > 0 else { return nil }
        let kinds: [String] = PersonSource.allCases.filter { s in (hits[s] ?? 0) > 0 }.map { s in s.label }
        let shown: String = names.map { n in "「" + n + "」" }.joined()
        return "照名字" + shown + "對；名單裡還有 \(total) 位同名（" + kinds.joined(separator: "、") + "），紀錄會算在一起。"
    }
}
