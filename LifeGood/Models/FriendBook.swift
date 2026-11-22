import Foundation

// [v25.636] 朋友履歷（peoplehub2；judge_peoplehub §C1 剩下的、C5–C12、§F、§G）
//
// 朋友＝既有的 Relationship（同步鍵 life_relationships；一個欄位都沒加、RelationshipGroup 一個 case 都沒加），
// 所以舊 iPad 看得懂、存檔整份重寫時也會帶著朋友。沒有新同步鍵、沒有 Codable 模型。這個檔只進 App target。
// - 上半（extension PersonLedger、FriendBook、FriendText）全是純函式：只讀傳進來的值，不寫 store、不寫 UserDefaults。
// - FriendActions 是唯一會寫 LifeStore 的地方：只在按鈕 action 裡叫，而且一律放到下一個 runloop
//   （有 dismiss 的先 dismiss）；一次加好幾位包 life.withBatch（relationships 的 didSet 會直接 save，v25.46 教訓）。
// - FriendSuggestMemory：建議卡「不要再提」只記這台的 UserDefaults.standard（不放 App Group，小工具讀不到；只存名字 key，不存金額）。
// 名字規則沿用 PersonLedger.key（LifeStore.normalizedPersonName）／SplitPeople.checkName：完全相等才算，不做模糊比對。
// 名字、欠款只在 App 內頁：不上通知、小工具、手錶、鎖定畫面、靈動島；朋友頁沒有分享鈕。

// MARK: - 值

/// 常一起吃、還沒存成朋友的人（朋友頁最上面那張建議卡）
struct PersonLedgerCompanion: Identifiable, Equatable {
    /// 顯示用：最近那一筆裡的寫法（去前後空白）
    let name: String
    let key: String
    /// 幾筆（同一筆裡同一個人只算一次；所有有同行的分類都算）
    let count: Int
    /// 最近一起的那天
    let lastDate: Date

    var id: String { key }

    init(name: String, key: String, count: Int, lastDate: Date) {
        self.name = name
        self.key = key
        self.count = count
        self.lastDate = lastDate
    }
}

/// 朋友頁「送過的禮」一筆（社交支出、收受人裡有這位）
struct PersonLedgerGift: Identifiable, Equatable {
    let expenseId: UUID
    let date: Date
    /// 記帳的名稱；空的用子分類（「生日禮金」），都沒有寫「社交」
    let title: String
    /// 子分類（「生日禮金」）；沒有＝""
    let kind: String
    /// 整筆（跟家人頁「收到的禮金」一致；多人合送也是整筆算給每一位）
    let amount: Double
    /// 收受人不只一位
    let shared: Bool

    var id: UUID { expenseId }

    init(expenseId: UUID, date: Date, title: String, kind: String, amount: Double, shared: Bool) {
        self.expenseId = expenseId
        self.date = date
        self.title = title
        self.kind = kind
        self.amount = amount
        self.shared = shared
    }
}

/// 改名後會對不上幾筆（FriendEditor 改名提醒用）
struct FriendRenameImpact: Equatable {
    var count: Int = 0
    /// 對不上的都是飲食（「4 頓」；有別的分類寫「筆」）
    var allFood: Bool = true

    init() {}
}

/// 朋友列表的一段（朋友、同事、客戶、其他；舊資料分在「家人」的放「其他」）
struct FriendSection: Identifiable {
    let title: String
    let friends: [Relationship]

    var id: String { title }

    init(title: String, friends: [Relationship]) {
        self.title = title
        self.friends = friends
    }
}

/// 編輯器打名字時的狀態：能不能按〔完成〕＋一行字（擋的原因或同名提醒）
struct FriendNameState: Equatable {
    let canSave: Bool
    let message: String?

    init(canSave: Bool, message: String?) {
        self.canSave = canSave
        self.message = message
    }
}

/// 朋友頁 sheet(item:) 的 item（id＝Relationship.id）
struct FriendDetailTarget: Identifiable, Equatable {
    let id: UUID

    init(id: UUID) {
        self.id = id
    }
}

/// 朋友編輯器 sheet(item:) 的 item：每次打開一個新的 id；base＝nil 是新增（預設朋友）
struct FriendEditorTarget: Identifiable {
    let id: UUID
    let base: Relationship?

    init(id: UUID, base: Relationship?) {
        self.id = id
        self.base = base
    }

    static func adding() -> FriendEditorTarget {
        FriendEditorTarget(id: UUID(), base: nil)
    }

    static func editing(_ r: Relationship) -> FriendEditorTarget {
        FriendEditorTarget(id: UUID(), base: r)
    }
}

/// 朋友編輯器的草稿（全是 Relationship 原有的欄位）
struct FriendDraft {
    var name: String
    var group: RelationshipGroup
    var hasBirthday: Bool
    var birthday: Date
    var hasAnniversary: Bool
    var anniversary: Date
    var phone: String
    var note: String
    var interactions: [InteractionRecord]

    /// 新增（base＝nil）預設朋友；編輯照原本的值。沒填的日期先放 now（開關關著就不存）
    init(_ base: Relationship?, now: Date) {
        name = base?.name ?? ""
        group = base?.group ?? .friend
        hasBirthday = base?.birthday != nil
        birthday = base?.birthday ?? now
        hasAnniversary = base?.anniversary != nil
        anniversary = base?.anniversary ?? now
        phone = base?.phone ?? ""
        note = base?.note ?? ""
        interactions = base?.interactions ?? []
    }

    /// 存檔用：名字、電話去前後空白；開關關著的日期存 nil。id 照原本那一位（新增時給新的 id）
    func relationship(id: UUID) -> Relationship {
        Relationship(id: id,
                     name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                     group: group,
                     birthday: hasBirthday ? birthday : nil,
                     anniversary: hasAnniversary ? anniversary : nil,
                     phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
                     note: note,
                     interactions: interactions)
    }
}

// MARK: - 算（C1 剩下的：unknownCompanions／newFriends，以及朋友頁要的）

extension PersonLedger {
    /// 名單上已經有的名字 key：本人（中文名、英文名）、家人（中文名、英文名）、人際關係（含分在家人的）、部屬（只讀 name）、
    /// 組織圖同事、名片。〔存成朋友〕、建議卡都排除這些
    static func knownKeys(life: LifeStore) -> Set<String> {
        var out = Set<String>()
        func add(_ s: String) {
            let k = PersonLedger.key(s)
            if !k.isEmpty { out.insert(k) }
        }
        add(life.profile.chineseName)
        add(life.profile.englishName)
        for m in life.familyMembers {
            add(m.chineseName)
            add(m.englishName)
        }
        for r in life.relationships { add(r.name) }
        for s in life.subordinates { add(s.name) }
        for p in life.orgPeople { add(p.name) }
        for c in life.businessCards { add(c.name) }
        return out
    }

    /// C10-b 常一起吃、還沒存的人：變動支出的同行人員（SplitPeople.loadedMembers：diningMember＋分帳裡還在的人）裡，
    /// 不在 knownKeys、不是本人、沒被「不要再提」、名字合格（canPick）的。同一筆同一個人只算一次。
    /// 顯示最近那一筆的寫法；排序：最近一起的新到舊 → 次數多到少 → key。最多 limit 位
    static func unknownCompanions(expenses: [Expense], index: ExpenseSplitIndex, knownKeys: Set<String>,
                                  meKeys: Set<String>, dismissed: Set<String>, limit: Int = 8) -> [PersonLedgerCompanion] {
        let ordered: [Expense] = expenses.filter { e in e.expenseType == .variable }.sorted { a, b in
            if a.date != b.date { return a.date > b.date }
            return a.id.uuidString < b.id.uuidString
        }
        var count: [String: Int] = [:]
        var last: [String: Date] = [:]
        var shown: [String: String] = [:]
        for e in ordered {
            let members = SplitPeople.loadedMembers(diningMember: e.diningMember, split: index.split(for: e))
            var seen = Set<String>()
            for n in members.sorted() {
                guard case .ok(let t) = SplitPeople.checkName(n) else { continue }
                let k = PersonLedger.key(t)
                if k.isEmpty || seen.contains(k) { continue }
                if knownKeys.contains(k) || meKeys.contains(k) || dismissed.contains(k) { continue }
                seen.insert(k)
                count[k, default: 0] += 1
                if last[k] == nil { last[k] = e.date }
                if shown[k] == nil { shown[k] = t }
            }
        }
        let keys: [String] = count.keys.sorted { a, b in
            let da = last[a] ?? .distantPast
            let db = last[b] ?? .distantPast
            if da != db { return da > db }
            let ca = count[a] ?? 0
            let cb = count[b] ?? 0
            if ca != cb { return ca > cb }
            return a < b
        }
        var out: [PersonLedgerCompanion] = []
        for k in keys.prefix(max(0, limit)) {
            out.append(PersonLedgerCompanion(name: shown[k] ?? k, key: k, count: count[k] ?? 0,
                                             lastDate: last[k] ?? .distantPast))
        }
        return out
    }

    /// C10 寫入前最後一次去重：每個名字過 SplitPeople.checkName（存去前後空白的寫法）、key 不在 existingKeys、
    /// 這一批裡 key 一樣的只留第一個；照 pending 的順序建 Relationship(name:, group: .friend)
    static func newFriends(pending: [String], existingKeys: Set<String>) -> [Relationship] {
        var out: [Relationship] = []
        var seen = existingKeys
        for raw in pending {
            guard case .ok(let t) = SplitPeople.checkName(raw) else { continue }
            let k = PersonLedger.key(t)
            if k.isEmpty || seen.contains(k) { continue }
            seen.insert(k)
            out.append(Relationship(name: t, group: .friend))
        }
        return out
    }

    /// C10-a 記帳存檔時要存成朋友的名字：pending 裡、而且真的存進這筆（diningMember／socialRecipient）的，照存檔的順序
    static func pendingToSave(pending: Set<String>, saved: [String]) -> [String] {
        var out: [String] = []
        for n in saved where pending.contains(n) && !out.contains(n) {
            out.append(n)
        }
        return out
    }

    /// C6 朋友列表每一列的數字：一次掃完所有變動支出，建「key → 摘要」（不要每一列各掃一遍）。
    /// keys 由呼叫端給（朋友的 key，已經拿掉本人）；每一個 key 的摘要＝summary(entries(keys: [key]))
    static func summaries(expenses: [Expense], index: ExpenseSplitIndex, keys: Set<String>) -> [String: PersonLedgerSummary] {
        guard !keys.isEmpty else { return [:] }
        var lists: [String: [PersonLedgerEntry]] = [:]
        for e in expenses where e.expenseType == .variable {
            let split = index.split(for: e)
            let members = SplitPeople.loadedMembers(diningMember: e.diningMember, split: split)
            var hit = Set<String>()
            for n in members {
                let k = PersonLedger.key(n)
                if keys.contains(k) { hit.insert(k) }
            }
            for k in hit {
                if let x = entry(for: e, split: split, keys: [k]) {
                    lists[k, default: []].append(x)
                }
            }
        }
        var out: [String: PersonLedgerSummary] = [:]
        for (k, list) in lists {
            out[k] = summary(list)
        }
        return out
    }

    /// C8 改名提醒：用舊名字記的那幾筆（變動支出、同行人員有舊名字、沒有新名字）。key 一樣（只差空白、大小寫）＝0
    static func renameImpact(oldName: String, newName: String, expenses: [Expense],
                             index: ExpenseSplitIndex) -> FriendRenameImpact {
        var out = FriendRenameImpact()
        let oldKey = PersonLedger.key(oldName)
        let newKey = PersonLedger.key(newName)
        guard !oldKey.isEmpty, oldKey != newKey else { return out }
        for e in expenses where e.expenseType == .variable {
            let members = SplitPeople.loadedMembers(diningMember: e.diningMember, split: index.split(for: e))
            var keys = Set<String>()
            for n in members { keys.insert(PersonLedger.key(n)) }
            guard keys.contains(oldKey), !keys.contains(newKey) else { continue }
            out.count += 1
            if (e.variableCategory ?? .other) != .food { out.allFood = false }
        }
        return out
    }

    /// C12 送過的禮：變動支出「社交」、收受人（SplitPeople.names(in:)）的 key 有對上的；整筆算給每一位（跟家人頁一致）。新到舊
    static func gifts(expenses: [Expense], keys: Set<String>) -> [PersonLedgerGift] {
        guard !keys.isEmpty else { return [] }
        var out: [PersonLedgerGift] = []
        for e in expenses where e.expenseType == .variable && e.variableCategory == .social {
            let names = SplitPeople.names(in: e.socialRecipient)
            guard names.contains(where: { n in keys.contains(PersonLedger.key(n)) }) else { continue }
            let kind = e.socialSubCategory?.rawValue ?? ""
            let t = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = !t.isEmpty ? t : (kind.isEmpty ? VariableCategory.social.rawValue : kind)
            out.append(PersonLedgerGift(expenseId: e.id, date: e.date, title: title, kind: kind,
                                        amount: e.amount, shared: names.count > 1))
        }
        return out.sorted { a, b in
            if a.date != b.date { return a.date > b.date }
            return a.expenseId.uuidString < b.expenseId.uuidString
        }
    }

    /// C9 名片頁：同名的朋友（key 一樣的第一位；沒有＝nil）
    static func friend(named name: String, in list: [Relationship]) -> Relationship? {
        let k = PersonLedger.key(name)
        guard !k.isEmpty else { return nil }
        return list.first { r in PersonLedger.key(r.name) == k }
    }

    /// C7 朋友頁：同名的名片（v2 只靠名字；多張就列多張，照名片原本的順序）
    static func cards(named name: String, in list: [BusinessCard]) -> [BusinessCard] {
        let k = PersonLedger.key(name)
        guard !k.isEmpty else { return [] }
        return list.filter { c in PersonLedger.key(c.name) == k }
    }
}

// MARK: - 朋友頁的分段、編輯器的規則

enum FriendBook {
    /// 列表的段（照 K3）：朋友、同事、客戶、其他；分在「家人」的舊資料放「其他」
    static let sectionOrder: [RelationshipGroup] = [.friend, .colleague, .client, .other]

    /// 舊資料分在「家人」的放哪一段
    static func sectionGroup(_ g: RelationshipGroup) -> RelationshipGroup {
        g == .family ? .other : g
    }

    /// C6 列表：搜尋（名字、電話、備註；去前後空白、不分大小寫、包含就算）→ 分段（空的段不出現）。段裡照存的順序
    static func sections(_ list: [Relationship], query: String) -> [FriendSection] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var buckets: [RelationshipGroup: [Relationship]] = [:]
        for r in list {
            if !q.isEmpty {
                let hit = r.name.lowercased().contains(q) || r.phone.lowercased().contains(q)
                    || r.note.lowercased().contains(q)
                if !hit { continue }
            }
            buckets[sectionGroup(r.group), default: []].append(r)
        }
        var out: [FriendSection] = []
        for g in sectionOrder {
            if let friends = buckets[g], !friends.isEmpty {
                out.append(FriendSection(title: g.rawValue, friends: friends))
            }
        }
        return out
    }

    /// C8 分組選項：朋友、同事、客戶、其他；只有原本就是「家人」的那一筆才多列「家人」（Picker 要包含目前值）
    static func groupChoices(current: RelationshipGroup?) -> [RelationshipGroup] {
        var out: [RelationshipGroup] = sectionOrder
        if current == .family { out.append(.family) }
        return out
    }

    /// C8 名字：checkName 不過、或是本人 → 不能存；名單裡有同名 → 可以存，但寫一行提醒（只寫類別和人數）。
    /// editingId＝正在改的那一位（不算同名）；新增傳 nil
    static func nameState(_ raw: String, editingId: UUID?, life: LifeStore) -> FriendNameState {
        switch SplitPeople.checkName(raw) {
        case .empty:
            return FriendNameState(canSave: false, message: FriendText.nameEmpty)
        case .badChar:
            return FriendNameState(canSave: false, message: ExpenseSplitText.nameBadChar)
        case .tooLong:
            return FriendNameState(canSave: false, message: ExpenseSplitText.nameTooLong)
        case .ok(let t):
            let keys = PersonLedger.names(primary: t, extra: [])
            if PersonLedger.isSelf(keys: keys, meKeys: PersonLedger.meKeys(life.profile)) {
                return FriendNameState(canSave: false, message: FriendText.nameIsSelf)
            }
            let hits = PersonLedger.sameNameHits(keys: keys, life: life,
                                                 exclude: PersonLedgerExclude(relationshipId: editingId))
            return FriendNameState(canSave: true, message: FriendText.sameNameWarn(hits))
        }
    }
}

// MARK: - 畫面上的字（寫名字、「這位」或「朋友」，不用代名詞；家人寫家人）

enum FriendText {
    static let title = "朋友履歷"
    static let empty = "還沒有朋友。記帳時打的名字可以存成朋友，或按〔＋〕新增。"
    static let searchPrompt = "搜尋名字、電話、備註"
    static let suggestTitle = "常一起吃、還沒存的人"
    static let suggestNote = "記帳時打過的名字；往左滑可以不要再提（只記在這支手機）。"
    static let saveAsFriend = "存成朋友"
    static let pendingMarked = "記帳存檔時會存成朋友 ✓"
    static let dontSuggest = "不要再提"
    static let addToFriends = "加到朋友履歷"
    static let openFriend = "朋友履歷"
    static let suggestFamilyNote = "建議放到家人履歷"
    static let familyGroupWarn = "分在家人的人，記帳預設是我請，錢包自動記帳也會帶到。"
    static let deleteButton = "刪除這位朋友"
    static let deleteConfirm = "只刪朋友資料，記帳和分帳都不會改。"
    static let nameEmpty = "請輸入名字"
    static let nameIsSelf = "這是你自己的名字"
    static let newTitle = "新增朋友"
    static let editTitle = "編輯朋友"
    static let detailTitle = "朋友"
    static let giftsTitle = "送過的禮"
    static let giftShared = "多人合送"
    static let interactionsTitle = "互動紀錄"
    static let addInteraction = "記一筆"
    static let interactionEmpty = "還沒有互動紀錄"
    static let noteTitle = "備註"
    static let cardsTitle = "名片"
    static let notFound = "這位朋友已經不在了（可能在別台刪掉了）"

    /// 列表那一列：「生日 5/1」（沒填＝nil）
    static func birthdayLine(_ d: Date?, calendar: Calendar) -> String? {
        guard let d else { return nil }
        return "生日 " + ExpenseSplitText.md(d, calendar)
    }

    /// 朋友頁頭卡：「生日 1990/5/1」「紀念日 2020/3/14」（沒填＝nil）
    static func dateLine(_ label: String, _ d: Date?, calendar: Calendar) -> String? {
        guard let d else { return nil }
        return label + " " + ExpenseSplitText.ymd(d, calendar)
    }

    /// 電話 → 撥號用的 tel: 網址（只留數字和 + * # ,；分機字、空白、括號都拿掉；沒有數字＝nil）
    static func telURL(_ phone: String) -> URL? {
        let allowed = Set("0123456789+*#,")
        let s = String(phone.filter { ch in allowed.contains(ch) })
        guard s.contains(where: { ch in ch.isNumber }) else { return nil }
        return URL(string: "tel:" + s)
    }

    /// 建議卡一列：「一起 3 次・最近 11/18」
    static func suggestRow(_ c: PersonLedgerCompanion, calendar: Calendar) -> String {
        "一起 \(c.count) 次・最近 " + ExpenseSplitText.md(c.lastDate, calendar)
    }

    /// 列表那一列的灰色小字：「還欠 NT$375」（沒有欠＝nil）
    static func rowOwed(_ s: PersonLedgerSummary?) -> String? {
        guard let s, s.owedTotal >= 0.5 else { return nil }
        return "還欠 " + ExpenseSplitText.ntd(s.owedTotal)
    }

    /// 列表那一列：「一起吃飯 6 頓・最近 11/18」（沒有任何紀錄＝nil）
    static func rowStats(_ s: PersonLedgerSummary?, calendar: Calendar) -> String? {
        guard let s else { return nil }
        let t = PersonLedgerText.header(s, calendar: calendar)
        return t.isEmpty ? nil : t
    }

    /// 存好了的提示：「阿傑 存成朋友了」「3 位存成朋友了」
    static func savedToast(_ names: [String]) -> String {
        if names.count == 1, let n = names.first { return n + " 存成朋友了" }
        return "\(names.count) 位存成朋友了"
    }

    /// 改名提醒：「改名後，過去用「阿傑」記的 4 頓會對不上（下一版會自動記住舊名字）」（0 筆＝nil）
    static func renameWarning(oldName: String, impact: FriendRenameImpact) -> String? {
        guard impact.count > 0 else { return nil }
        let old = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = impact.allFood ? "頓" : "筆"
        return "改名後，過去用「" + old + "」記的 \(impact.count) " + unit + "會對不上（下一版會自動記住舊名字）"
    }

    /// 同名提醒：「名單裡已經有 1 位同名（名片），往來會算在一起。」（沒有＝nil）
    static func sameNameWarn(_ hits: [PersonSource: Int]) -> String? {
        let total: Int = hits.values.reduce(0, +)
        guard total > 0 else { return nil }
        let kinds: [String] = PersonSource.allCases.filter { s in (hits[s] ?? 0) > 0 }.map { s in s.label }
        return "名單裡已經有 \(total) 位同名（" + kinds.joined(separator: "、") + "），往來會算在一起。"
    }

    /// 送過的禮標頭：「3 次・NT$5,600」
    static func giftsHeader(_ gifts: [PersonLedgerGift]) -> String {
        let total: Double = gifts.reduce(0) { sum, g in sum + g.amount }
        return "\(gifts.count) 次・" + ExpenseSplitText.ntd(total)
    }

    /// 送過的禮一列左邊：「11/20 生日禮金」；子分類跟名稱不一樣時「11/20 生日禮金・蛋糕」
    static func giftLabel(_ g: PersonLedgerGift, calendar: Calendar) -> String {
        var t = ExpenseSplitText.md(g.date, calendar) + " "
        if !g.kind.isEmpty && g.kind != g.title {
            t += g.kind + "・"
        }
        return t + g.title
    }

    /// 朋友頁「名片：王小明・○○公司」（沒有公司＝「名片：王小明」）
    static func cardRow(_ c: BusinessCard) -> String {
        let company = c.company.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = c.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return "名片：" + name + (company.isEmpty ? "" : "・" + company)
    }
}

// MARK: - 唯一會寫的地方（只在按鈕 action 裡、下一個 runloop 叫；有 dismiss 的先 dismiss）

enum FriendActions {
    /// C10〔存成朋友〕：用**當下**的名單再去重一次（knownKeys），一律 .friend；好幾位包 withBatch 只存一次。回傳真的存了誰
    @discardableResult
    static func save(names: [String], life: LifeStore) -> [String] {
        let list = PersonLedger.newFriends(pending: names, existingKeys: PersonLedger.knownKeys(life: life))
        guard !list.isEmpty else { return [] }
        life.withBatch {
            for r in list {
                life.add(r)
            }
        }
        return list.map { r in r.name }
    }

    /// C9 名片〔加到朋友履歷〕：只跟朋友比（名片本身就在名單裡）。名字不合格、是本人＝nil；
    /// 已經有同名朋友＝那位的 id；不然新增一位（電話帶第一支）。不寫任何連結 id
    @discardableResult
    static func addFromCard(_ card: BusinessCard, life: LifeStore) -> UUID? {
        guard case .ok(let t) = SplitPeople.checkName(card.name) else { return nil }
        if PersonLedger.isSelf(keys: PersonLedger.names(primary: t, extra: []), meKeys: PersonLedger.meKeys(life.profile)) {
            return nil
        }
        if let r = PersonLedger.friend(named: t, in: life.relationships) { return r.id }
        let phone = (card.phones.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let r = Relationship(name: t, group: .friend, phone: phone)
        life.add(r)
        return r.id
    }

    /// C8 編輯器存檔：有這位就整筆換掉（id 不變）、沒有就新增
    static func upsert(_ r: Relationship, life: LifeStore) {
        if life.relationships.contains(where: { x in x.id == r.id }) {
            life.update(r)
        } else {
            life.add(r)
        }
    }

    /// C8 刪除：只刪 Relationship（記帳、分帳一個字都不動）
    static func delete(id: UUID, life: LifeStore) {
        guard let r = life.relationships.first(where: { x in x.id == id }) else { return }
        life.deleteRelationship(r)
    }

    /// C7 朋友頁〔記一筆〕互動紀錄
    static func addInteraction(_ rec: InteractionRecord, friendId: UUID, life: LifeStore) {
        guard var r = life.relationships.first(where: { x in x.id == friendId }) else { return }
        r.interactions.append(rec)
        life.update(r)
    }

    /// C7 朋友頁左滑刪一筆互動紀錄
    static func deleteInteraction(id: UUID, friendId: UUID, life: LifeStore) {
        guard var r = life.relationships.first(where: { x in x.id == friendId }) else { return }
        r.interactions.removeAll { x in x.id == id }
        life.update(r)
    }
}

// MARK: - 建議卡「不要再提」（只記這台；UserDefaults.standard，不放 App Group；只存名字 key）

enum FriendSuggestMemory {
    static let defaultsKey = "friend_suggest_dismissed_keys"
    /// 最多記幾個（超過丟最舊的）
    static let maxCount = 200

    static func load(_ d: UserDefaults = .standard) -> Set<String> {
        Set(d.stringArray(forKey: defaultsKey) ?? [])
    }

    static func dismiss(_ key: String, _ d: UserDefaults = .standard) {
        guard !key.isEmpty else { return }
        var list: [String] = d.stringArray(forKey: defaultsKey) ?? []
        list.removeAll { k in k == key }
        list.append(key)
        if list.count > maxCount { list.removeFirst(list.count - maxCount) }
        d.set(list, forKey: defaultsKey)
    }
}
