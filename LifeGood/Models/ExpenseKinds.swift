import Foundation

// MARK: - [v25.615] 政府稅費・規費・罰款 v1：記帳那筆的「細項」（radar/judge_govfee.md §C1–C8；build/govfee1/brief.md §2；
//   sim_govfee1.py 一個函式一個函式對照）
//
// • 一個存檔的分類值都不加（做法 C）：FixedCategory、VariableCategory、VehicleVariableCategory、VehicleFixedCategory、
//   RealEstateExpenseCategory 的 case 一個都沒加、rawValue 一個都沒改，Expense 一個欄位都沒加。記帳那筆照舊只寫舊版認得的值
//  （固定「稅費・地價稅」＝fixedCategory "其他"＋每年），真正的細項存在新的同步鍵 lifegood_expense_kinds_v1。
// • 為什麼不加在 Expense 上：還沒更新的 iPad 存一次記帳會用自己的 CodingKeys 重寫整包、洗掉不認得的欄位；這個鍵它不碰。
// • 讀只准問一支：ExpenseKindIndex.kind(of:)（有 tag、kind 不是 nil、base＝現在的簽名、認得的字在允許表裡才算；
//   對不上＝以那筆為準、不算、tag 留著）。主分類簽名只准用 ExpenseKindIndex.signature(_:)。
// • 寫只有新版、只有使用者按的時候：AddExpenseView 存檔（ExpenseKindStore.recordSave）、ExpenseStore 刪除（墓碑）、
//   備份取代／合併、iCloud 合併。開 App、背景、同步一律不寫 tag。
// • 兩台合併：tags 照 id 取 updatedAt 新的（一樣新留 self）；墓碑（kind nil）跟著 updatedAt 走、30 天後存檔時才清；
//   dismissed（v2〔不是〕）照 (id, kind) 取聯集、不清。不認得的欄位收進 extra 原樣寫回（照 Competency.swift）。
// • 隱私：這裡的字只在 App 內頁；通知、小工具、手錶、鎖定畫面、靈動島一個字都沒加（v1 鎖定畫面仍寫「固定支出」）。

// MARK: - 細項

/// 一個細項（地價稅、罰款…）。**存檔字＝顯示字，上線後不准改字**（要改顯示就另加 displayName）。
/// 不是 enum：讀到不認得的字（之後版本加的）照原字顯示、性質當稅。
struct ExpenseKind: Hashable, Identifiable {
    let raw: String

    init(_ raw: String) { self.raw = raw }

    var id: String { raw }

    static let landValueTax = ExpenseKind("地價稅")
    static let houseTax = ExpenseKind("房屋稅")
    static let landIncrementTax = ExpenseKind("土地增值稅")
    static let houseLandTax = ExpenseKind("房地合一稅")
    static let licenseTax = ExpenseKind("牌照稅")
    static let fuelFee = ExpenseKind("燃料費")
    static let fee = ExpenseKind("規費")
    static let otherTax = ExpenseKind("其他稅費")
    static let fine = ExpenseKind("罰款")

    /// 這一版認得的九個（順序＝一般變動「稅費」v4 的清單順序）
    static let known: [ExpenseKind] = [.landValueTax, .houseTax, .landIncrementTax, .houseLandTax,
                                       .licenseTax, .fuelFee, .fee, .otherTax, .fine]

    var isKnown: Bool { Self.known.contains(self) }

    /// 性質：罰款＝罰款、規費＝規費、其他（含不認得的字）＝稅
    enum Nature: Equatable {
        case tax, fee, fine
    }

    var nature: Nature {
        if self == .fine { return .fine }
        if self == .fee { return .fee }
        return .tax
    }

    /// 稅或規費（房屋卡「稅費・保險」、固定支出頁「稅費」組看這個；罰款不算）
    var isTaxOrFee: Bool { nature != .fine }

    /// 每年幾月繳（自用；選單旁寫月份、預設照月份猜、日期按鈕用）。沒有固定月份的是 nil
    private static let dueMonths: [ExpenseKind: Int] = [.landValueTax: 11, .houseTax: 5, .licenseTax: 4, .fuelFee: 7]

    var dueMonth: Int? { Self.dueMonths[self] }
}

/// kind(of:) 的回答。inferred＝推的（v2 起：固定「其他」＋每年＋連車、名稱有「牌照」→牌照稅；只顯示、不寫）。v1 一律 false
struct ExpenseKindHit: Equatable {
    let kind: ExpenseKind
    let inferred: Bool
}

// MARK: - 讀（只准問這一支）

struct ExpenseKindIndex {
    /// sim、preview、還沒有資料時明寫這個（純函式不給預設值）
    static let empty = ExpenseKindIndex(book: ExpenseKindBook())

    /// 每筆支出的原始 tag（含墓碑；同一個 id 有兩筆時留 updatedAt 新的）
    private let tags: [UUID: ExpenseKindTag]
    /// [v25.616] 〔不是〕過的「id|細項」（推的規則、一鍵整理候選都看這個；只增不刪）
    private let dismissedKeys: Set<String>

    init(book: ExpenseKindBook) {
        var map: [UUID: ExpenseKindTag] = [:]
        for t in book.tags ?? [] {
            if let old = map[t.id], (old.updatedAt ?? .distantPast) >= (t.updatedAt ?? .distantPast) { continue }
            map[t.id] = t
        }
        tags = map
        dismissedKeys = Set((book.dismissed ?? []).map { d in ExpenseKindIndex.dismissKey(d.id, d.kind) })
    }

    /// 主分類簽名（H1，只准這一支）。一律 `?.rawValue ?? ""`，不准用字串插值 Optional／enum。順序寫死：
    /// 固定 → "fixed.其他"；變動有車子子分類 → "vehicle.其他"；變動有房子子分類 → "re.稅費"；其他 → "var.稅費"
    static func signature(_ e: Expense) -> String {
        if e.expenseType == .fixed { return "fixed." + (e.fixedCategory?.rawValue ?? "") }
        if let v = e.vehicleExpenseCategory { return "vehicle." + v.rawValue }
        if let r = e.realEstateExpenseCategory { return "re." + r.rawValue }
        return "var." + (e.variableCategory?.rawValue ?? "")
    }

    /// 允許表（C2）：這個簽名可以掛哪些細項。表上沒有的簽名回空（認得的字都不算；不認得的字只看 base）
    static func allowed(_ signature: String) -> [ExpenseKind] {
        if signature == "fixed." + FixedCategory.other.rawValue {
            return [.landValueTax, .houseTax, .licenseTax, .fuelFee, .fee, .otherTax]
        }
        if signature == "vehicle." + VehicleVariableCategory.other.rawValue {
            return [.fee, .licenseTax, .fuelFee, .otherTax, .fine]
        }
        if signature == "re." + RealEstateExpenseCategory.tax.rawValue {
            return [.landValueTax, .houseTax, .landIncrementTax, .houseLandTax, .fee, .otherTax]
        }
        if signature == "var." + VariableCategory.tax.rawValue {
            return ExpenseKind.known
        }
        return []
    }

    /// 原始 tag（不驗證；AddExpenseView 存檔判斷要不要寫墓碑用）
    func rawTag(_ id: UUID) -> ExpenseKindTag? { tags[id] }

    /// 這筆的細項（C5）。對不上 → nil（以那筆為準、不算、tag 留著）
    func kind(of e: Expense) -> ExpenseKindHit? {
        // [v25.616] 連墓碑都沒有的那筆：照「推的」規則（只顯示、不寫；inferredHit 在檔尾 v2 那段）
        if tags[e.id] == nil { return inferredHit(e) }
        guard let t = tags[e.id], let raw = t.kind, !raw.isEmpty else { return nil }
        let sig = Self.signature(e)
        guard let base = t.base, base == sig else { return nil }
        let k = ExpenseKind(raw)
        if k.isKnown && !Self.allowed(sig).contains(k) { return nil }
        return ExpenseKindHit(kind: k, inferred: false)
    }

    /// 稅或規費的細項（罰款、沒有細項都回 nil）
    func taxKind(of e: Expense) -> ExpenseKind? {
        guard let hit = kind(of: e), hit.kind.isTaxOrFee else { return nil }
        return hit.kind
    }
}

// MARK: - 新鍵的資料長相（C4）

/// 同步鍵 lifegood_expense_kinds_v1：記帳那筆的「細項」（地價稅、罰款…）。
/// 不加在 Expense 上：還沒更新的 iPad 存一次記帳會用自己的 CodingKeys 重寫整包、洗掉不認得的欄位；這個鍵它不碰。
struct ExpenseKindBook: Codable, Equatable {
    /// 同步鍵（ExpenseKindStore 存讀、CloudSyncManager.syncKeys 用同一個字）
    static let syncKey = "lifegood_expense_kinds_v1"
    /// 墓碑留幾天（另一台還沒同步的舊 tag 不會把它長回來）
    static let tombstoneDays = 30

    /// 逐筆解（壞一筆只丟那筆，照 WealthTransferBook）
    var tags: [ExpenseKindTag]?
    /// 〔不是〕（v2 一鍵整理）：只增不刪，合併取聯集，不清
    var dismissed: [ExpenseKindDismissal]?
    var extra: [String: JSONValue]?
}

struct ExpenseKindTag: Codable, Equatable {
    /// ＝ Expense.id
    var id: UUID
    /// nil ＝ 墓碑
    var kind: String?
    /// 貼上去那時的簽名（ExpenseKindIndex.signature）
    var base: String?
    /// v4 補繳才用；v1 就放進結構，免得 v1 的裝置存回去洗掉
    var sameAs: UUID?
    /// 寫入一律填；讀到 nil 當 distantPast
    var updatedAt: Date?
    var extra: [String: JSONValue]?
}

struct ExpenseKindDismissal: Codable, Equatable {
    var id: UUID
    var kind: String
    var at: Date?
    var extra: [String: JSONValue]?
}

extension ExpenseKindBook {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case tags, dismissed
    }
    static let knownKeys: Set<String> = Set(CodingKeys.allCases.map { $0.rawValue })

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tags = CompetencyCoding.lossyArray(ExpenseKindTag.self, c, .tags)
        dismissed = CompetencyCoding.lossyArray(ExpenseKindDismissal.self, c, .dismissed)
        extra = CompetencyCoding.readExtra(decoder, known: Self.knownKeys)
    }

    func encode(to encoder: Encoder) throws {
        try CompetencyCoding.writeExtra(extra, encoder, known: Self.knownKeys)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(tags, forKey: .tags)
        try c.encodeIfPresent(dismissed, forKey: .dismissed)
    }
}

extension ExpenseKindTag {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, kind, base, sameAs, updatedAt
    }
    static let knownKeys: Set<String> = Set(CodingKeys.allCases.map { $0.rawValue })

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try? c.decodeIfPresent(String.self, forKey: .kind)
        base = try? c.decodeIfPresent(String.self, forKey: .base)
        sameAs = try? c.decodeIfPresent(UUID.self, forKey: .sameAs)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        extra = CompetencyCoding.readExtra(decoder, known: Self.knownKeys)
    }

    func encode(to encoder: Encoder) throws {
        try CompetencyCoding.writeExtra(extra, encoder, known: Self.knownKeys)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(kind, forKey: .kind)
        try c.encodeIfPresent(base, forKey: .base)
        try c.encodeIfPresent(sameAs, forKey: .sameAs)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}

extension ExpenseKindDismissal {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, kind, at
    }
    static let knownKeys: Set<String> = Set(CodingKeys.allCases.map { $0.rawValue })

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(String.self, forKey: .kind)
        at = try? c.decodeIfPresent(Date.self, forKey: .at)
        extra = CompetencyCoding.readExtra(decoder, known: Self.knownKeys)
    }

    func encode(to encoder: Encoder) throws {
        try CompetencyCoding.writeExtra(extra, encoder, known: Self.knownKeys)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(at, forKey: .at)
    }
}

// MARK: - 合併、清墓碑、寫（純函式；ExpenseKindStore 只叫這些）

extension ExpenseKindBook {
    var isEmpty: Bool { (tags ?? []).isEmpty && (dismissed ?? []).isEmpty }

    /// 同一個 id 的原始 tag（不驗證；有兩筆時留 updatedAt 新的）
    func rawTag(_ id: UUID) -> ExpenseKindTag? {
        var best: ExpenseKindTag? = nil
        for t in tags ?? [] where t.id == id {
            if let b = best, (b.updatedAt ?? .distantPast) >= (t.updatedAt ?? .distantPast) { continue }
            best = t
        }
        return best
    }

    /// 新增或整筆換掉（同一個 id 只留這一筆）
    mutating func upsert(_ t: ExpenseKindTag) {
        var list: [ExpenseKindTag] = tags ?? []
        list.removeAll { x in x.id == t.id }
        list.append(t)
        tags = list
    }

    private static func dismissKey(_ d: ExpenseKindDismissal) -> String { d.id.uuidString + "|" + d.kind }

    /// 兩台合併（iCloud 增量、第一次同步〔合併〕、備份〔合併〕）：tags 照 id 取 updatedAt 新的（一樣新留 self）；
    /// dismissed 照 (id, kind) 聯集；extra 合在一起（self 優先）
    func merged(with other: ExpenseKindBook) -> ExpenseKindBook {
        var out = self
        out.tags = CompetencyCoding.mergeList(tags, other.tags, key: { (t: ExpenseKindTag) -> UUID in t.id },
                                              stamp: { (t: ExpenseKindTag) -> Date in t.updatedAt ?? .distantPast })
        out.dismissed = CompetencyCoding.mergeList(dismissed, other.dismissed,
                                                   key: { (d: ExpenseKindDismissal) -> String in Self.dismissKey(d) },
                                                   stamp: { (_: ExpenseKindDismissal) -> Date in .distantPast })
        out.extra = CompetencyCoding.mergeExtra(extra, other.extra)
        return out
    }

    /// 清墓碑（存檔時叫）：只清 kind == nil 而且 updatedAt 超過 30 天的 tag；dismissed 不清。沒有要清的回 self
    func purged(now: Date) -> ExpenseKindBook {
        guard let list = tags else { return self }
        let limit: Date = now.addingTimeInterval(-Double(Self.tombstoneDays) * 86_400)
        let kept: [ExpenseKindTag] = list.filter { t in
            guard t.kind == nil else { return true }
            return (t.updatedAt ?? .distantPast) > limit
        }
        guard kept.count != list.count else { return self }
        var out = self
        out.tags = kept
        return out
    }

    static func tombstone(of r: ExpenseKindTag, now: Date) -> ExpenseKindTag {
        var t = r
        t.kind = nil
        t.base = nil
        t.sameAs = nil
        t.updatedAt = now
        return t
    }

    /// C6：AddExpenseView 存檔（e＝這次存的那筆）。回 nil＝不用寫。
    /// ① 這次有選細項 → 寫 {id, kind, base: 簽名(e), updatedAt: now}（一律蓋掉；原本的 sameAs、extra 留著）
    /// ② 沒選、原始 tag 有 kind、而且那個 tag 是這一版表單管得到的簽名（handledBases）→ 墓碑
    /// ③ 其他 → 不寫（例如 v2 才有畫面的「車子・罰款」在 v1 打開存檔：tag 留著，簽名對得上就照算）
    func savingTag(for e: Expense, kind: ExpenseKind?, now: Date) -> ExpenseKindBook? {
        let raw = rawTag(e.id)
        if let k = kind {
            var t: ExpenseKindTag = raw ?? ExpenseKindTag(id: e.id)
            t.kind = k.raw
            t.base = ExpenseKindIndex.signature(e)
            t.updatedAt = now
            var out = self
            out.upsert(t)
            return out
        }
        guard let r = raw, r.kind != nil, ExpenseKindForm.handledBases.contains(r.base ?? "") else { return nil }
        var out = self
        out.upsert(Self.tombstone(of: r, now: now))
        return out
    }

    /// 刪除記帳（ExpenseStore.delete）：有細項的寫墓碑。沒有要寫的回 nil
    func deleting(ids: Set<UUID>, now: Date) -> ExpenseKindBook? {
        var out = self
        var changed = false
        for id in ids {
            guard let r = out.rawTag(id), r.kind != nil else { continue }
            out.upsert(Self.tombstone(of: r, now: now))
            changed = true
        }
        return changed ? out : nil
    }

    /// 匯出：只帶這幾筆支出的 tag、dismissed（照定期轉帳跟著帳本走）
    func filtered(to ids: Set<UUID>) -> ExpenseKindBook {
        var out = self
        if let list = tags {
            out.tags = list.filter { t in ids.contains(t.id) }
        }
        if let list = dismissed {
            out.dismissed = list.filter { d in ids.contains(d.id) }
        }
        return out
    }

    /// 取代（只帶了一部分支出的檔案，例如旅遊）：這幾個 id 換成備份裡的，其他不動
    func replacing(ids: Set<UUID>, with other: ExpenseKindBook) -> ExpenseKindBook {
        var out = self
        let keepTags: [ExpenseKindTag] = (tags ?? []).filter { t in !ids.contains(t.id) }
        let inTags: [ExpenseKindTag] = (other.tags ?? []).filter { t in ids.contains(t.id) }
        let allTags: [ExpenseKindTag] = keepTags + inTags
        out.tags = (tags == nil && allTags.isEmpty) ? nil : allTags
        let keepDis: [ExpenseKindDismissal] = (dismissed ?? []).filter { d in !ids.contains(d.id) }
        let inDis: [ExpenseKindDismissal] = (other.dismissed ?? []).filter { d in ids.contains(d.id) }
        let allDis: [ExpenseKindDismissal] = keepDis + inDis
        out.dismissed = (dismissed == nil && allDis.isEmpty) ? nil : allDis
        return out
    }
}

// MARK: - 表單用的規則（AddExpenseView 只叫這裡；sim_govfee1.py 一支一支對照）

enum ExpenseKindForm {
    /// 這一版表單「管得到」的簽名：打開那筆存檔、這次沒選細項時，原本的 tag 是這種簽名才寫墓碑（v2 加 vehicle.其他、v3 加 re.稅費）
    static let handledBases: Set<String> = ["fixed." + FixedCategory.other.rawValue]

    /// 固定支出「分類」那段的 footer（一定寫：iOS 18 下拉選單不一定顯示第二行灰字，UX 2.1）
    static let fixedFooter = "地價稅、房屋稅、牌照稅、燃料費（燃料稅）、驗車換照這些規費都選這個。"

    /// 房屋卡〔＋ 記一筆〕→ 稅費 打開的固定・每年，表單上方那一行
    static let oneTimeSwitchText = "只繳這一次（例如土地增值稅）→ 改記一次性"

    /// 這筆固定支出連著什麼（決定細項清單）
    enum Link: Equatable {
        case realEstate
        case vehicle(VehiclePowerType?)
        case none
    }

    static func isElectric(_ p: VehiclePowerType?) -> Bool {
        p == .electric || p == .electricMotorcycle
    }

    /// 固定「稅費」的細項清單（C8）：連房子不放規費；連電車、電動機車不放燃料費
    static func fixedOptions(_ link: Link) -> [ExpenseKind] {
        switch link {
        case .realEstate:
            return [.landValueTax, .houseTax, .otherTax]
        case .vehicle(let power):
            var out: [ExpenseKind] = [.licenseTax]
            if !isElectric(power) { out.append(.fuelFee) }
            out.append(.fee)
            out.append(.otherTax)
            return out
        case .none:
            return [.landValueTax, .houseTax, .licenseTax, .fuelFee, .fee, .otherTax]
        }
    }

    /// 機車不照月份猜（機車牌照稅多半免徵、燃料費不寄單）
    static func guessesByMonth(_ link: Link) -> Bool {
        if case .vehicle(let p) = link, p == .motorcycle || p == .electricMotorcycle { return false }
        return true
    }

    /// 預設細項：照月份猜（11→地價稅、5→房屋稅、4→牌照稅、7→燃料費；清單裡要有）；猜不到停第一個
    static func defaultKind(_ link: Link, month: Int) -> ExpenseKind {
        let options = fixedOptions(link)
        if guessesByMonth(link), let k = options.first(where: { $0.dueMonth == month }) { return k }
        return options.first ?? .otherTax
    }

    /// 選單上的字：「地價稅（11 月）」「規費（驗車）」（只有連車的規費寫驗車）
    static func label(_ k: ExpenseKind, link: Link) -> String {
        if let m = k.dueMonth { return k.raw + "（\(m) 月）" }
        if k == .fee, case .vehicle(_) = link { return "規費（驗車）" }
        return k.raw
    }

    /// 選「稅費」時的週期：還是預設「每月」、沒動過 → 每年
    static func recurrenceAfterPickingTax(_ current: Recurrence, touched: Bool) -> Recurrence {
        (current == .monthly && !touched) ? .yearly : current
    }

    /// 年、月、日一律用西曆算（系統設成民國曆時年份才不會變 115），時區跟著傳進來的那個
    static func gregorian(_ calendar: Calendar) -> Calendar {
        var g = Calendar(identifier: .gregorian)
        g.timeZone = calendar.timeZone
        return g
    }

    /// 那一年那個月的最後一天（00:00）
    static func lastDay(month: Int, year: Int, calendar: Calendar) -> Date? {
        let g = gregorian(calendar)
        guard let first = g.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = g.range(of: .day, in: .month, for: first) else { return nil }
        return g.date(from: DateComponents(year: year, month: month, day: range.count))
    }

    /// 第一期建議日：今天在那個稅的月份 → 今天；不在 → 最近一次已過的那期的最後一天（11/10 的房屋稅 → 今年 5/31；3/1 的房屋稅 → 去年 5/31）
    static func suggestedFirstDate(_ k: ExpenseKind, today: Date, calendar: Calendar) -> Date? {
        guard let m = k.dueMonth else { return nil }
        let g = gregorian(calendar)
        let y = g.component(.year, from: today)
        let tm = g.component(.month, from: today)
        if tm == m { return g.startOfDay(for: today) }
        let year = tm > m ? y : y - 1
        return lastDay(month: m, year: year, calendar: calendar)
    }

    /// 日期下一行的灰字＋按鈕（不自動改日期）
    struct DateHint: Equatable {
        /// 「房屋稅每年 5/1–5/31 繳。」
        let text: String
        /// 「改成 2026/5/31」
        let buttonTitle: String
        let target: Date
    }

    /// 表單上的日期不在那個稅的月份才有；在的話 nil
    static func dateHint(_ k: ExpenseKind, date: Date, today: Date, calendar: Calendar) -> DateHint? {
        guard let m = k.dueMonth else { return nil }
        let g = gregorian(calendar)
        guard g.component(.month, from: date) != m,
              let target = suggestedFirstDate(k, today: today, calendar: calendar),
              let last = lastDay(month: m, year: g.component(.year, from: target), calendar: calendar) else { return nil }
        let lastNumber = g.component(.day, from: last)
        let ty = g.component(.year, from: target)
        let tm = g.component(.month, from: target)
        let td = g.component(.day, from: target)
        return DateHint(text: k.raw + "每年 \(m)/1–\(m)/\(lastNumber) 繳。",
                        buttonTitle: "改成 \(ty)/\(tm)/\(td)",
                        target: target)
    }

    /// 存檔前（只在新增）：這間房第一期那一年已經有一筆一次性的地價稅（或房屋稅）→ 回那一年；沒有 nil。
    /// 一次性＝房子變動「稅費」；名稱或備註有「地價」（房屋稅看「房屋稅」），或那筆的細項就是這個
    static func duplicateYear(kind: ExpenseKind, estateId: UUID?, firstDate: Date, expenses: [Expense],
                              kinds: ExpenseKindIndex, calendar: Calendar) -> Int? {
        guard let estateId, kind == .landValueTax || kind == .houseTax else { return nil }
        let g = gregorian(calendar)
        let year = g.component(.year, from: firstDate)
        let word = kind == .landValueTax ? "地價" : "房屋稅"
        let found = expenses.contains { e in
            guard e.expenseType == .variable, e.linkedRealEstateId == estateId,
                  e.realEstateExpenseCategory == .tax,
                  g.component(.year, from: e.date) == year else { return false }
            if e.title.contains(word) || e.note.contains(word) { return true }
            return kinds.kind(of: e)?.kind == kind
        }
        return found ? year : nil
    }

    /// 「2025 已經記過一筆地價稅（一次性），要從 2026 開始嗎？」
    static func duplicateTitle(kind: ExpenseKind, year: Int) -> String {
        "\(year) 已經記過一筆\(kind.raw)（一次性），要從 \(year + 1) 開始嗎？"
    }

    /// 〔從 2026 開始〕
    static func duplicateShiftButton(year: Int) -> String { "從 \(year + 1) 開始" }

    /// 〔照填的〕
    static let duplicateKeepButton = "照填的"
}

// MARK: - 固定支出類別選單的選項（「稅費」插在「管理費」後、「其他」前；選了存 fixedCategory .other）

enum FixedPick: Hashable, Identifiable {
    case category(FixedCategory)
    case tax

    var id: String {
        switch self {
        case .category(let c): return c.rawValue
        case .tax: return "稅費"
        }
    }

    static var all: [FixedPick] {
        var out: [FixedPick] = []
        for c in FixedCategory.allCases {
            if c == .other { out.append(.tax) }
            out.append(.category(c))
        }
        return out
    }

    /// 選單上那一項只寫「稅費」（不寫「稅費・規費」；說明在 footer）
    var title: String {
        switch self {
        case .category(let c): return c.rawValue
        case .tax: return "稅費"
        }
    }

    var icon: String {
        switch self {
        case .category(let c): return c.icon
        case .tax: return "building.columns.fill"
        }
    }
}

// MARK: - 固定支出頁的分組（有稅類／規費細項的「其他」歸「稅費」組；每一筆只歸一組）

enum FixedGroup: Hashable {
    case category(FixedCategory)
    case tax

    static func of(_ e: Expense, kinds: ExpenseKindIndex) -> FixedGroup {
        let c: FixedCategory = e.fixedCategory ?? .other
        if c == .other, kinds.taxKind(of: e) != nil { return .tax }
        return .category(c)
    }

    var title: String {
        switch self {
        case .category(let c): return c.rawValue
        case .tax: return "稅費"
        }
    }
}

// MARK: - 列上的字（不改 categoryName：categoryWords 等拿它比對）

extension Expense {
    /// 「稅費・地價稅」「汽車 - 罰款」「房地產 - 地價稅」；沒有細項照 categoryName
    func displayCategoryName(kinds: ExpenseKindIndex) -> String {
        guard let hit = kinds.kind(of: self) else { return categoryName }
        let k = hit.kind
        switch expenseType {
        case .fixed:
            return k.isTaxOrFee ? "稅費・" + k.raw : k.raw
        case .variable:
            if vehicleExpenseCategory != nil { return "汽車 - " + k.raw }
            if realEstateExpenseCategory != nil { return "房地產 - " + k.raw }
            return k.isTaxOrFee ? "稅費・" + k.raw : k.raw
        }
    }
}

// MARK: - 存、讀、同步（C7）

extension Notification.Name {
    /// ExpenseKindStore 的 book 變了（自己存、iCloud 合併、備份）。ExpenseStore 聽這個只跳 modifyID（不指派 expenses、不存、不推）
    static let expenseKindsDidChange = Notification.Name("expenseKindsDidChange")
}

final class ExpenseKindStore: ObservableObject {
    static let shared = ExpenseKindStore()

    @Published private(set) var book: ExpenseKindBook {
        didSet { index = ExpenseKindIndex(book: book) }
    }
    /// 所有畫面問這個（book 一變就重建）
    private(set) var index: ExpenseKindIndex

    private init() {
        let b = Self.readStored()
        book = b
        index = ExpenseKindIndex(book: b)
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

    private static func readStored() -> ExpenseKindBook {
        guard let d = UserDefaults.standard.data(forKey: ExpenseKindBook.syncKey),
              let b = try? JSONDecoder().decode(ExpenseKindBook.self, from: d) else { return ExpenseKindBook() }
        return b
    }

    /// 寫進 UserDefaults、推 iCloud。**不碰 expenses**（不會引發記帳整包重寫）
    private func persist() {
        if let d = try? JSONEncoder().encode(book) {
            UserDefaults.standard.set(d, forKey: ExpenseKindBook.syncKey)
        }
        CloudSyncManager.shared.pushAll()
    }

    /// 自己寫的唯一一條路：清墓碑 → 跟現在一樣就不動 → 存、推、通知重畫
    private func commit(_ next: ExpenseKindBook, now: Date) {
        let cleaned = next.purged(now: now)
        guard cleaned != book else { return }
        book = cleaned
        persist()
        NotificationCenter.default.post(name: .expenseKindsDidChange, object: nil)
    }

    /// AddExpenseView 存檔那一刻（dismiss 之後、下一個 runloop 叫）。kind＝這次選的細項（沒選 nil）
    func recordSave(_ e: Expense, kind: ExpenseKind?, now: Date = Date()) {
        guard let next = book.savingTag(for: e, kind: kind, now: now) else { return }
        commit(next, now: now)
    }

    /// ExpenseStore.delete：有細項的寫墓碑（刪車、刪房、取代匯入留孤兒，找不到 id 就不算）
    func recordDelete(ids: Set<UUID>, now: Date = Date()) {
        guard !ids.isEmpty, let next = book.deleting(ids: ids, now: now) else { return }
        commit(next, now: now)
    }

    /// 匯出：只帶這幾筆支出的
    func exportBook(for ids: Set<UUID>) -> ExpenseKindBook {
        book.filtered(to: ids)
    }

    /// 備份〔取代〕（整批記帳歸這份檔案管）：整包換成備份裡的
    func importReplacingAll(_ other: ExpenseKindBook, now: Date = Date()) {
        commit(other, now: now)
    }

    /// 備份〔取代〕（只帶了一部分支出，例如旅遊）：這幾個 id 換成備份裡的
    func importReplacing(ids: Set<UUID>, with other: ExpenseKindBook, now: Date = Date()) {
        commit(book.replacing(ids: ids, with: other), now: now)
    }

    /// 備份〔合併〕：照 id 合併（一樣新留本機的）
    func importMerging(_ other: ExpenseKindBook, now: Date = Date()) {
        commit(book.merged(with: other), now: now)
    }

    /// 設定「清除所有資料」（ExpenseStore.clearAll 叫）：寫一包空的推上去（不是刪鍵：刪鍵的話雲端那份不會被蓋掉）
    func clearAll() {
        let wasEmpty = book == ExpenseKindBook()
        book = ExpenseKindBook()
        persist()
        if !wasEmpty { NotificationCenter.default.post(name: .expenseKindsDidChange, object: nil) }
    }

    /// 聽 iCloud（M7，照 LifeStore.reloadFromCloud 的定期轉帳）：帶了 keys 而且含這個鍵 → 雲端那份併上本機剛才那份，
    /// 合出來跟雲端那份不一樣（本機有它沒有的）就存回去、推上去；沒帶 keys（以雲端覆蓋這台、第一次合併已經合好）照雲端那包
    @objc private func reloadFromCloud(_ note: Notification) {
        let keys = note.userInfo?["keys"] as? [String]
        if let keys, !keys.contains(ExpenseKindBook.syncKey) { return }
        let before = book
        let cloud = Self.readStored()
        let next: ExpenseKindBook = keys == nil ? cloud : cloud.merged(with: before)
        if next != before { book = next }
        if next != cloud { persist() }
        if next != before { NotificationCenter.default.post(name: .expenseKindsDidChange, object: nil) }
    }
}

/// 第一次同步〔合併〕（CloudSyncManager.resolveInitialSync）：這個鍵最上層是物件，mergeBlob 會整包留勝方、另一邊的細項不見；
/// 解成 Book 照 id 合併。解不開回 nil（退回原本的 mergeBlob）
enum ExpenseKindSync {
    static func handles(_ key: String) -> Bool {
        key == ExpenseKindBook.syncKey
    }

    static func mergeInitialBlob(local: Data?, cloud: Data?, localWins: Bool) -> Data? {
        guard let l = local, let c = cloud else { return nil }
        let dec = JSONDecoder()
        guard let lb = try? dec.decode(ExpenseKindBook.self, from: l),
              let cb = try? dec.decode(ExpenseKindBook.self, from: c) else { return nil }
        let merged: ExpenseKindBook = localWins ? lb.merged(with: cb) : cb.merged(with: lb)
        return try? JSONEncoder().encode(merged)
    }
}

// MARK: - [v25.616] 政府稅費 v2：車子「稅費」「罰款」、推的牌照稅／燃料費、一鍵整理（radar/judge_govfee.md §C9；
//   build/govfee2/brief.md；sim_govfee2.py 一個函式一個函式對照）
//
// • 上面 v25.615 的東西一行都沒改，只加：ExpenseKindIndex 多記 dismissed、kind(of:) 開頭多一行「沒 tag → 推的」。
// • 推的（只顯示、不寫，UX 2.6）：連墓碑都沒有的固定「其他」＋每年＋連車（沒連房子）、不是記成其他的車險，
//   名稱有「牌照」→ 牌照稅、有「燃料」→ 燃料費。〔不是〕過（dismissed）就不推。不推房子的、不推罰款、不看備註。
// • 寫只在使用者按的時候：AddExpenseView 存檔（recordFormSave，取代 recordSave 那一行）、一鍵整理〔改成…〕
//  （recordRetag）／〔不是〕（recordDismiss）、變動支出頁〔複製〕（recordCopy）。開 App、背景、同步一律不寫。
// • categories(for:) 不改（小工具「記到…」才不會多出「稅費」「罰款」）：虛擬項另外排（VehicleKindPick.all）。
// • 隱私：這裡的字只在 App 內頁；通知、小工具、手錶、鎖定畫面、靈動島一個字都沒加。

extension ExpenseKindIndex {
    /// dismissed 的比對字（id|細項字）
    static func dismissKey(_ id: UUID, _ kind: String) -> String {
        id.uuidString + "|" + kind
    }

    /// 〔不是〕過這筆的這個細項
    func isDismissed(_ id: UUID, _ k: ExpenseKind) -> Bool {
        dismissedKeys.contains(Self.dismissKey(id, k.raw))
    }

    /// 推的規則（C5）：只看那筆本身（不看 tag、不看 dismissed：那兩個在 inferredHit 看）
    static func inferredKind(_ e: Expense) -> ExpenseKind? {
        guard e.expenseType == .fixed, e.fixedCategory == .other, e.recurrence == .yearly,
              e.linkedVehicleId != nil, e.linkedRealEstateId == nil,
              !VehicleFixes.isInsuranceAsOther(e) else { return nil }
        if e.title.contains("牌照") { return .licenseTax }
        if e.title.contains("燃料") { return .fuelFee }
        return nil
    }

    /// 沒有 tag 的那筆推得出來、而且沒〔不是〕過 → inferred＝true（kind(of:) 開頭叫）
    fileprivate func inferredHit(_ e: Expense) -> ExpenseKindHit? {
        guard let k = Self.inferredKind(e), !isDismissed(e.id, k) else { return nil }
        return ExpenseKindHit(kind: k, inferred: true)
    }
}

extension ExpenseKindForm {
    /// v2 表單管得到的簽名：多了車子變動「其他」（v2 的「車子・罰款／稅費」在新版打開、改成別的存檔要寫墓碑）
    static let handledBasesV2: Set<String> = handledBases.union(["vehicle." + VehicleVariableCategory.other.rawValue])
}

/// 一鍵整理的一筆：哪一筆記帳、建議改成哪個細項
struct ExpenseKindPick {
    let expense: Expense
    let kind: ExpenseKind
}

extension ExpenseKindBook {
    /// v2 AddExpenseView 存檔（e＝這次存的那筆）。回 nil＝不用寫。
    /// ① 有選細項 → 同 savingTag（寫 tag、一律蓋掉）
    /// ② 沒選、原始 tag 有 kind、base 是 v2 管得到的簽名（固定其他、車子其他）→ 墓碑
    /// ③ 沒選、連墓碑都沒有、但這筆推得出來（推的那筆打開改選別的、仍是其他）→ 記〔不是〕，之後不再推
    /// ④ 其他 → 不寫
    func formSavingTag(for e: Expense, kind: ExpenseKind?, now: Date) -> ExpenseKindBook? {
        if let k = kind { return savingTag(for: e, kind: k, now: now) }
        if let r = rawTag(e.id) {
            guard r.kind != nil, ExpenseKindForm.handledBasesV2.contains(r.base ?? "") else { return nil }
            var out = self
            out.upsert(Self.tombstone(of: r, now: now))
            return out
        }
        guard let hit = ExpenseKindIndex(book: self).kind(of: e), hit.inferred else { return nil }
        return dismissing([ExpenseKindDismissal(id: e.id, kind: hit.kind.raw, at: now)])
    }

    /// 〔不是〕：只加不刪，(id, 細項) 已經有的不重複加。沒有新的回 nil
    func dismissing(_ list: [ExpenseKindDismissal]) -> ExpenseKindBook? {
        var all: [ExpenseKindDismissal] = dismissed ?? []
        var keys: Set<String> = Set(all.map { d in ExpenseKindIndex.dismissKey(d.id, d.kind) })
        var changed = false
        for d in list {
            let key = ExpenseKindIndex.dismissKey(d.id, d.kind)
            guard !keys.contains(key) else { continue }
            keys.insert(key)
            all.append(d)
            changed = true
        }
        guard changed else { return nil }
        var out = self
        out.dismissed = all
        return out
    }

    /// 一鍵整理〔改成罰款〕〔全部改〕：只寫 tag（base＝那筆現在的簽名）。現在的分類不能掛這個細項的跳過。沒有要寫的回 nil
    func retagging(_ picks: [ExpenseKindPick], now: Date) -> ExpenseKindBook? {
        var out = self
        var changed = false
        for p in picks where ExpenseKindIndex.allowed(ExpenseKindIndex.signature(p.expense)).contains(p.kind) {
            if let next = out.savingTag(for: p.expense, kind: p.kind, now: now) {
                out = next
                changed = true
            }
        }
        return changed ? out : nil
    }

    /// 變動支出頁〔複製〕（M2）：原本那筆有細項（不是推的）→ 新的那筆也寫一筆（同細項、base 照新的那筆重算）
    func copying(from src: Expense, to copy: Expense, now: Date) -> ExpenseKindBook? {
        guard let hit = ExpenseKindIndex(book: self).kind(of: src), !hit.inferred else { return nil }
        return savingTag(for: copy, kind: hit.kind, now: now)
    }
}

extension ExpenseKindStore {
    /// [v25.616] AddExpenseView 存檔（取代 v25.615 的 recordSave 那一行；dismiss 之後、下一個 runloop 叫）
    func recordFormSave(_ e: Expense, kind: ExpenseKind?, now: Date = Date()) {
        guard let next = book.formSavingTag(for: e, kind: kind, now: now) else { return }
        commit(next, now: now)
    }

    /// 一鍵整理〔改成…〕〔全部改〕：只寫細項那個鍵，記帳那筆一個欄位都不動。找不到那筆的跳過
    func recordRetag(_ candidates: [ExpenseKindCandidate], expenses: [Expense], now: Date = Date()) {
        let byId: [UUID: Expense] = Dictionary(expenses.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let picks: [ExpenseKindPick] = candidates.compactMap { c in
            byId[c.expenseId].map { e in ExpenseKindPick(expense: e, kind: c.kind) }
        }
        guard let next = book.retagging(picks, now: now) else { return }
        commit(next, now: now)
    }

    /// 一鍵整理〔不是〕：只加 dismissed（從合併後的現值加，不新做一本）
    func recordDismiss(_ candidates: [ExpenseKindCandidate], now: Date = Date()) {
        let list: [ExpenseKindDismissal] = candidates.map { c in
            ExpenseKindDismissal(id: c.expenseId, kind: c.kind.raw, at: now)
        }
        guard let next = book.dismissing(list) else { return }
        commit(next, now: now)
    }

    /// 變動支出頁〔複製〕：新的那筆跟著帶細項（VariableExpenseView.duplicateExpense 叫）
    func recordCopy(from src: Expense, to copy: Expense, now: Date = Date()) {
        guard let next = book.copying(from: src, to: copy, now: now) else { return }
        commit(next, now: now)
    }
}

// MARK: - [v25.616] 車子變動「支出類別」的虛擬項（存 vehicleExpenseCategory .other＋細項）

enum VehicleKindPick: Hashable, Identifiable {
    case category(VehicleVariableCategory)
    case tax
    case fine

    var id: String {
        switch self {
        case .category(let c): return c.rawValue
        case .tax: return "稅費"
        case .fine: return "罰款"
        }
    }

    /// categories(for:) 不改；「稅費」「罰款」插在「其他」前（沒有其他就接在最後）
    static func all(_ power: VehiclePowerType) -> [VehicleKindPick] {
        var out: [VehicleKindPick] = []
        var inserted = false
        for c in VehicleVariableCategory.categories(for: power) {
            if c == .other {
                out.append(.tax)
                out.append(.fine)
                inserted = true
            }
            out.append(.category(c))
        }
        if !inserted {
            out.append(.tax)
            out.append(.fine)
        }
        return out
    }

    var title: String {
        switch self {
        case .category(let c): return c.rawValue
        case .tax: return "稅費"
        case .fine: return "罰款"
        }
    }

    var icon: String {
        switch self {
        case .category(let c): return c.icon
        case .tax: return "building.columns"
        case .fine: return "exclamationmark.triangle"
        }
    }

    /// 虛擬項（稅費、罰款）才是 true
    var isVirtual: Bool {
        switch self {
        case .category: return false
        case .tax, .fine: return true
        }
    }
}

/// 車子的表單規則（AddExpenseView、AddVehicleView、VehicleDetailView 只叫這裡）
enum VehicleKindForm {
    /// 車子變動「稅費」的細項：規費｜牌照稅｜燃料費（電車、電動機車不出現）｜其他稅費
    static func taxOptions(_ power: VehiclePowerType?) -> [ExpenseKind] {
        var out: [ExpenseKind] = [.fee, .licenseTax]
        if !ExpenseKindForm.isElectric(power) { out.append(.fuelFee) }
        out.append(.otherTax)
        return out
    }

    /// 車子變動「稅費」預設規費（驗車最常見）
    static let defaultTaxKind: ExpenseKind = .fee

    /// 「規費（驗車、換照、過戶）」；其他照原字
    static func taxLabel(_ k: ExpenseKind) -> String {
        k == .fee ? "規費（驗車、換照、過戶）" : k.raw
    }

    static let taxFooter = "驗車、換照、過戶的規費，或補繳的牌照稅、燃料費（燃料稅）。每年固定繳的牌照稅建議記成固定支出・每年。"
    static let fineFooter = "罰單、拖吊、逾期補繳、滯納金都算。"

    /// 車輛區 footer：虛擬項才有（其他照舊）
    static func footer(_ pick: VehicleKindPick) -> String? {
        switch pick {
        case .tax: return taxFooter
        case .fine: return fineFooter
        case .category: return nil
        }
    }

    /// 地點欄提示字
    static let placePrompt = "監理站"

    /// 車子卡〔＋ 記一筆〕→「稅費（牌照稅、燃料費）」打開的固定・每年，表單上方那一行
    static let oneTimeSwitchText = "只繳這一次（例如驗車、換照、過戶）→ 改記一次性"

    /// 〔只繳這一次〕切過去的車子變動「稅費」預設細項
    static let oneTimeKind: ExpenseKind = .fee

    /// 車子卡〔＋ 記一筆〕→ 稅費（固定・每年）的細項：4 月牌照稅、7 月燃料費（電車沒有）、其他月份牌照稅；機車不照月份猜
    static func fixedTaxPresetKind(power: VehiclePowerType?, month: Int) -> ExpenseKind {
        ExpenseKindForm.defaultKind(.vehicle(power), month: month)
    }
}

// MARK: - [v25.616] 一鍵整理（車子卡、房屋卡「要確認」各最多一項；點開逐筆〔改成…〕〔不是〕）

/// 一鍵整理清單的一列（卡片算好字；ExpenseKindTidySheet 只排版）
struct ExpenseKindCandidate: Identifiable, Equatable {
    let expenseId: UUID
    let kind: ExpenseKind
    /// 列名（車子：帳本列標題；房子：去掉房名的名稱）
    let title: String
    /// 「2026/10/3・NT$600」
    let detail: String

    var id: UUID { expenseId }
}

/// 〔看一下〕打開的那一頁
struct ExpenseKindTidyRequest: Identifiable, Equatable {
    /// 「vehicle-<車 id>」「house-<房 id>」
    let id: String
    let title: String
    let candidates: [ExpenseKindCandidate]
    /// 房屋卡：名稱有地價稅、房屋稅但主分類是「管理費」等的那幾筆名稱（不建議，只寫一句）
    let notes: [String]
}

enum ExpenseKindTidy {
    static let fineWords: [String] = ["罰", "拖吊", "逾期"]
    static let feeWords: [String] = ["驗車", "換照", "過戶", "規費"]

    /// 車子：名稱或備註看得出來的（罰款優先：「逾期驗車罰款」算罰款）
    static func vehicleGuess(_ e: Expense) -> ExpenseKind? {
        let text = e.title + "\n" + e.note
        if fineWords.contains(where: { w in text.contains(w) }) { return .fine }
        if feeWords.contains(where: { w in text.contains(w) }) { return .fee }
        return nil
    }

    /// 房子：只看名稱（「地價」→ 地價稅、「房屋稅」→ 房屋稅）
    static func houseGuess(_ e: Expense) -> ExpenseKind? {
        if e.title.contains("地價") { return .landValueTax }
        if e.title.contains("房屋稅") { return .houseTax }
        return nil
    }

    /// 新的在前（同一天照 id）
    static func sorted(_ list: [ExpenseKindPick]) -> [ExpenseKindPick] {
        list.sorted { a, b in
            if a.expense.date != b.expense.date { return a.expense.date > b.expense.date }
            return a.expense.id.uuidString < b.expense.id.uuidString
        }
    }

    /// 車子：linked＝這台車的記帳（VehicleLinks.expenses；沒連到記帳的鏡像列不在裡面）。
    /// 變動「其他」、沒細項（kind(of:) 是 nil）、名稱或備註看得出來、沒〔不是〕過
    static func vehiclePicks(_ linked: [Expense], kinds: ExpenseKindIndex) -> [ExpenseKindPick] {
        var out: [ExpenseKindPick] = []
        for e in linked where e.expenseType == .variable && e.vehicleExpenseCategory == .other {
            if kinds.isTombstoned(e.id) { continue }   // [v25.617] 在表單拿掉過細項（墓碑）＝明確說不是，不再建議
            guard kinds.kind(of: e) == nil, let k = vehicleGuess(e), !kinds.isDismissed(e.id, k) else { continue }
            out.append(ExpenseKindPick(expense: e, kind: k))
        }
        return sorted(out)
    }

    /// 房子：連這間的固定「其他」、沒細項、名稱有「地價」「房屋稅」、沒〔不是〕過
    static func housePicks(estateId: UUID, expenses: [Expense], kinds: ExpenseKindIndex) -> [ExpenseKindPick] {
        var out: [ExpenseKindPick] = []
        for e in expenses where e.expenseType == .fixed && e.linkedRealEstateId == estateId && e.fixedCategory == .other {
            if kinds.isTombstoned(e.id) { continue }   // [v25.617] 在表單拿掉過細項（墓碑）＝明確說不是，不再建議
            guard kinds.kind(of: e) == nil, let k = houseGuess(e), !kinds.isDismissed(e.id, k) else { continue }
            out.append(ExpenseKindPick(expense: e, kind: k))
        }
        return sorted(out)
    }

    /// 房子：名稱有地價稅、房屋稅，但主分類是「管理費」等（不是其他）的固定支出（不建議，只寫一句）
    static func houseOtherCategory(estateId: UUID, expenses: [Expense], kinds: ExpenseKindIndex) -> [Expense] {
        expenses.filter { e in
            e.expenseType == .fixed && e.linkedRealEstateId == estateId && e.fixedCategory != .other
                && kinds.kind(of: e) == nil && houseGuess(e) != nil
        }
    }

    /// 「1 筆罰款、1 筆規費」（照 order 的順序）
    static func countsText(_ picks: [ExpenseKindPick], order: [ExpenseKind]) -> String {
        var parts: [String] = []
        for k in order {
            let n = picks.filter { p in p.kind == k }.count
            if n > 0 { parts.append("\(n) 筆\(k.raw)") }
        }
        return parts.joined(separator: "、")
    }

    static func distinctKinds(_ picks: [ExpenseKindPick]) -> [ExpenseKind] {
        var out: [ExpenseKind] = []
        for p in picks where !out.contains(p.kind) { out.append(p.kind) }
        return out
    }

    /// 車子卡「要確認」那一句：「有 2 筆「其他」可以分得更清楚（1 筆罰款、1 筆規費）」；只有一種：「…（罰款）」
    static func vehicleMessage(_ picks: [ExpenseKindPick]) -> String {
        let kinds = distinctKinds(picks)
        let tail: String = kinds.count == 1 ? kinds[0].raw : countsText(picks, order: [.fine, .fee])
        return "有 \(picks.count) 筆「其他」可以分得更清楚（\(tail)）"
    }

    /// 房屋卡「要確認」那一句：1 筆「「地價稅」目前算在固定費用，要改成稅費・地價稅嗎？」
    static func houseMessage(_ picks: [ExpenseKindPick]) -> String {
        let kinds = distinctKinds(picks)
        if picks.count == 1, let k = kinds.first {
            return "「\(k.raw)」目前算在固定費用，要改成稅費・\(k.raw)嗎？"
        }
        if kinds.count == 1, let k = kinds.first {
            return "有 \(picks.count) 筆\(k.raw)目前算在固定費用，要改成稅費嗎？"
        }
        return "有 \(picks.count) 筆固定支出可以改成稅費（\(countsText(picks, order: [.landValueTax, .houseTax]))）"
    }

    static let reviewButton = "看一下"
    static let vehicleSheetTitle = "分得更清楚"
    static let houseSheetTitle = "改成稅費"
    static func retagButton(_ k: ExpenseKind) -> String { "改成" + k.raw }
    static let dismissButton = "不是"
    static let allButton = "全部改"
    static let allConfirmTitle = "全部改？"
    static func allConfirmMessage(_ n: Int) -> String { "這 \(n) 筆金額、日期不會變，只是分類寫得更清楚。" }
    static func doneText(_ k: ExpenseKind) -> String { "已改成" + k.raw }
    static let dismissedText = "不會再問"
    static let sheetFooter = "只改這筆的分類說法，金額、日期、名稱都不會變；家人還沒更新的 iPad 或手機上仍顯示「其他」。按〔不是〕之後不會再問，想改的話打開那筆換類別就好。"
    static let houseOtherNote = "想改成稅費，打開那筆換類別就好。"

    /// 一列：detail＝「2026/10/3・NT$600」（金額是台幣）
    static func candidate(_ p: ExpenseKindPick, title: String, amount: Double) -> ExpenseKindCandidate {
        ExpenseKindCandidate(expenseId: p.expense.id, kind: p.kind, title: title,
                             detail: HouseCardFormat.ymd(p.expense.date) + "・" + MoneyFormat.short(amount))
    }
}

// MARK: - [v25.617] 政府稅費 v3：稅務頁、房子變動「稅費」細項（radar/judge_govfee.md §C10；build/govfee3/brief.md；
//   sim_govfee3.py 一個函式一個函式對照）
//
// • 上面 v25.615／v25.616 的東西一行都沒改，只加：isTombstoned（一鍵整理候選跳過墓碑：vehiclePicks／housePicks 各多一行）、
//   房子變動「稅費」的細項（RealEstateKindForm）、v3 存檔規則（handledBasesV3／formSavingTagV3／recordFormSaveV3）、
//   稅務頁的純函式（TaxPaid、TaxPaidText）。
// • 年度稅費＝TaxPaid.records：① 一般變動「稅費」② 房子變動「稅費」③ 固定「其他」有稅類／規費細項（含推的牌照稅、燃料費），
//   照扣款日一期一列、每期金額照金額歷史（WealthSchedule.amount）、算到今天、截結束日 ④ 車子變動「其他」有規費／稅類細項。
//   金額一律走 WealthSchedule.ntd（＝ExpenseStore.ntdValue 的規則：只有外幣儲蓄險是原幣存的；其他記帳存檔時就換成台幣，不再乘一次）。
//   最後照 (expenseId, periodDate) 去重，留簽名順序在前的那個來源（車子 → 房子 → 一般 → 固定）。
// • 不收：買房費用、罰款（另一行 TaxPaid.fines）、沒細項也推不出來的「其他・每年」（檢核寫「可能是稅費」，不算進大字；
//   拿掉過細項（墓碑）、推的按過〔不是〕的不寫：TaxPaid.saidNotTax，跟一鍵整理跳過墓碑同一個意思）。
// • 節稅（effectivelyTaxDeductible、taxSavingBySub、MoneyBoards）一行都沒碰。
// • 隱私：這裡的字只在 App 內稅務頁；通知、小工具、手錶、鎖定畫面、靈動島一個字都沒加（鎖定畫面只多「稅費」兩個字，
//   在 WidgetBillsBuilder，不寫金額、卡名、房名、車名）。

extension ExpenseKindIndex {
    /// [v25.617] 這筆有墓碑（表單拿掉細項、刪除後）：一鍵整理不再建議（使用者明確說不是）
    func isTombstoned(_ id: UUID) -> Bool {
        guard let t = rawTag(id) else { return false }
        return t.kind == nil
    }
}

extension ExpenseKindForm {
    /// v3 表單管得到的簽名：多了房子變動「稅費」（v3 的細項在新版打開、改成「不指定」或別的類別存檔要寫墓碑）
    static let handledBasesV3: Set<String> = handledBasesV2.union(["re." + RealEstateExpenseCategory.tax.rawValue])
}

extension ExpenseKindBook {
    /// v3 AddExpenseView 存檔（取代 v2 的 formSavingTag；規則同 v2，只是墓碑多管房子變動「稅費」）。回 nil＝不用寫
    /// ① 有選細項 → savingTag ② 沒選、原始 tag 有 kind、base 在 handledBasesV3 → 墓碑
    /// ③ 沒選、連墓碑都沒有、這筆推得出來 → 記〔不是〕 ④ 其他 → 不寫
    func formSavingTagV3(for e: Expense, kind: ExpenseKind?, now: Date) -> ExpenseKindBook? {
        if let k = kind { return savingTag(for: e, kind: k, now: now) }
        if let r = rawTag(e.id) {
            guard r.kind != nil, ExpenseKindForm.handledBasesV3.contains(r.base ?? "") else { return nil }
            var out = self
            out.upsert(Self.tombstone(of: r, now: now))
            return out
        }
        guard let hit = ExpenseKindIndex(book: self).kind(of: e), hit.inferred else { return nil }
        return dismissing([ExpenseKindDismissal(id: e.id, kind: hit.kind.raw, at: now)])
    }
}

extension ExpenseKindStore {
    /// [v25.617] AddExpenseView 存檔（取代 v25.616 的 recordFormSave 那一行；dismiss 之後、下一個 runloop 叫；只准這一處）
    func recordFormSaveV3(_ e: Expense, kind: ExpenseKind?, now: Date = Date()) {
        guard let next = book.formSavingTagV3(for: e, kind: kind, now: now) else { return }
        commit(next, now: now)
    }
}

// MARK: - [v25.617] 房子變動「稅費」的細項（Picker 那一項的字不改，仍是「稅費」）

enum RealEstateKindForm {
    /// 細項清單（＝允許表 re.稅費；第一項「不指定」＝nil，是預設）
    static let options: [ExpenseKind] = [.landValueTax, .houseTax, .landIncrementTax, .houseLandTax, .fee, .otherTax]
    /// 第一項
    static let unspecifiedLabel = "不指定"

    /// 「地價稅（11 月）」「房屋稅（5 月）」「土地增值稅」…（同固定「稅費」連房子的寫法）
    static func label(_ k: ExpenseKind) -> String {
        ExpenseKindForm.label(k, link: .realEstate)
    }

    /// 選了「稅費」或「買房費用」時 footer 多這一句
    static let purchaseCostFooter = "買房那次的契稅、印花稅、代書、登記規費 → 選「買房費用」，留收據，以後賣房可以算成本。"

    static func showsPurchaseCostFooter(_ c: RealEstateExpenseCategory) -> Bool {
        c == .tax || c == .purchaseCost
    }
}

// MARK: - [v25.617] 稅務頁：年度稅費、罰款另一行、檢核

/// 稅務頁「稅費紀錄」從哪裡來
enum TaxPaidSource: Equatable {
    /// ① 一般變動「稅費」
    case general
    /// ② 房子變動「稅費」（連的那間）
    case house(UUID?)
    /// ③ 固定支出（週期；連的房子、車子）
    case recurring(Recurrence, estateId: UUID?, vehicleId: UUID?)
    /// ④ 車子變動「其他」＋規費／稅類細項（連的那台）
    case vehicle(UUID?)
}

/// 稅務頁一列：變動一筆一列、固定一期一列
struct TaxPaidRecord: Identifiable, Equatable {
    let expenseId: UUID
    /// 變動＝那筆的日期；固定＝那一期的扣款日
    let periodDate: Date
    /// 台幣（WealthSchedule.ntd；固定照那一期的金額歷史）
    let amountNTD: Double
    let source: TaxPaidSource
    /// 細項（一般／房子變動「稅費」沒標的是 nil）
    let kind: ExpenseKind?

    /// 去重的鍵（同一筆、同一期只算一次）
    var id: String { expenseId.uuidString + "@" + String(Int(periodDate.timeIntervalSince1970.rounded())) }
}

/// 月份分佈一格
struct TaxPaidMonth: Equatable {
    let month: Int
    let amount: Double
}

/// 年度稅務檢核的狀態
enum TaxCheckState: Equatable {
    /// 已記
    case recorded
    /// 還沒到（今年那個月還沒到、或看的是明年以後）
    case notYet
    /// 還沒看到紀錄
    case missing
    /// 不用查（note 寫為什麼：8/31 後才買、電車…）
    case notNeeded
    /// 應注意（綜所稅、二代健保：沒有記帳可以對，照 25.616 以前）
    case reminder
    /// 沒有房子、車子（灰的，照 25.616 以前）
    case irrelevant

    /// 右邊膠囊的字（irrelevant 不寫）
    var text: String? {
        switch self {
        case .recorded: return "已記"
        case .notYet: return "還沒到"
        case .missing: return "還沒看到紀錄"
        case .notNeeded: return "不用查"
        case .reminder: return "應注意"
        case .irrelevant: return nil
        }
    }

    /// 圖示要不要用那一列的顏色（照 25.616 以前的 relevant）
    var isActive: Bool { self != .irrelevant }
}

/// 檢核一列
struct TaxCheckItem: Identifiable, Equatable {
    /// ＝title（一年裡不會重複）
    let id: String
    let title: String
    /// 「11月」「全年」（照 25.616 以前的寫法）
    let month: String
    /// 對應的細項（綜所稅、二代健保 nil）
    let kind: ExpenseKind?
    let state: TaxCheckState
    /// 灰字（「可能記了兩次（2 筆），打開確認。」「8/31 以後才買的…」）
    let note: String?
}

/// 稅務頁一次要用的數（TaxPaid.summary 算一次，畫面只排版）
struct TaxPaidSummary {
    /// 年度稅費（新到舊）
    let records: [TaxPaidRecord]
    /// 另外繳的罰款（新到舊；不算進年度稅費）
    let fines: [TaxPaidRecord]
    let total: Double
    let finesTotal: Double
    /// 有金額的月份（1→12）
    let byMonth: [TaxPaidMonth]
    let checks: [TaxCheckItem]
    /// 檢核下面的提示（可能是稅費、名稱有「罰」的稅費）
    let hints: [String]
}

enum TaxPaid {
    /// 西曆年（ExpenseKindForm.gregorian 不用：要跟稅務頁的 selectedYear 用同一個 Calendar.current）
    static func year(_ d: Date, _ calendar: Calendar) -> Int { calendar.component(.year, from: d) }

    // ── 四個來源（各自判斷；去重在 records 最後）──

    /// ① 一般變動「稅費」（照 25.616 以前 taxExpenses：variableCategory 是稅費）；標成罰款的不收
    static func isGeneral(_ e: Expense, kinds: ExpenseKindIndex) -> Bool {
        guard e.expenseType == .variable, e.variableCategory == .tax else { return false }
        return kinds.kind(of: e)?.kind.nature != .fine
    }

    /// ② 房子變動「稅費」（買房費用不收）
    static func isHouse(_ e: Expense, kinds: ExpenseKindIndex) -> Bool {
        guard e.expenseType == .variable, e.realEstateExpenseCategory == .tax else { return false }
        return kinds.kind(of: e)?.kind.nature != .fine
    }

    /// ③ 固定「其他」有稅類／規費細項（含推的牌照稅、燃料費）
    static func isFixedTax(_ e: Expense, kinds: ExpenseKindIndex) -> Bool {
        e.isRecurringFixed && e.fixedCategory == .other && kinds.taxKind(of: e) != nil
    }

    /// ④ 車子變動「其他」有規費／稅類細項
    static func isVehicleTax(_ e: Expense, kinds: ExpenseKindIndex) -> Bool {
        e.expenseType == .variable && e.vehicleExpenseCategory == .other && kinds.taxKind(of: e) != nil
    }

    /// 固定那筆在 year 那一年、到 now（含）為止的每一期扣款日：第一期＝起始日（貸款是下一期），第 k 期＝第一期＋k 個週期一次加，
    /// 結束日當期照算（同 Expense.fixedPeriodCount）。最多 1200 期
    static func fixedDueDates(_ e: Expense, year: Int, now: Date, calendar: Calendar) -> [Date] {
        guard e.isRecurringFixed, let rec = e.recurrence else { return [] }
        let (component, step) = rec.componentValue
        let first: Date = e.fixedCategory == .loan
            ? (calendar.date(byAdding: component, value: step, to: e.date) ?? e.date)
            : e.date
        let limit: Date = calendar.startOfDay(for: min(now, e.endDate ?? now))
        var out: [Date] = []
        var k = 0
        while k < 1200 {
            guard let due = calendar.date(byAdding: component, value: step * k, to: first) else { break }
            if calendar.startOfDay(for: due) > limit { break }
            let y = Self.year(due, calendar)
            if y > year { break }
            if y == year { out.append(due) }
            k += 1
        }
        return out
    }

    /// 新到舊（同一天照 id）
    static func sorted(_ list: [TaxPaidRecord]) -> [TaxPaidRecord] {
        list.sorted { a, b in
            if a.periodDate != b.periodDate { return a.periodDate > b.periodDate }
            return a.expenseId.uuidString < b.expenseId.uuidString
        }
    }

    /// 那一年的稅費紀錄（年度稅費的大字、稅費筆數、月份分佈都看這一份）
    static func records(year: Int, expenses: [Expense], kinds: ExpenseKindIndex, rates: FinanceRates,
                        now: Date, calendar: Calendar) -> [TaxPaidRecord] {
        var vehicle: [TaxPaidRecord] = []
        var house: [TaxPaidRecord] = []
        var general: [TaxPaidRecord] = []
        var fixed: [TaxPaidRecord] = []
        for e in expenses {
            if e.expenseType == .variable {
                guard Self.year(e.date, calendar) == year else { continue }
                let amount: Double = WealthSchedule.ntd(of: e, raw: e.amount, rates: rates)
                let k: ExpenseKind? = kinds.kind(of: e)?.kind
                if isVehicleTax(e, kinds: kinds) {
                    vehicle.append(TaxPaidRecord(expenseId: e.id, periodDate: e.date, amountNTD: amount,
                                                 source: .vehicle(e.linkedVehicleId), kind: k))
                }
                if isHouse(e, kinds: kinds) {
                    house.append(TaxPaidRecord(expenseId: e.id, periodDate: e.date, amountNTD: amount,
                                               source: .house(e.linkedRealEstateId), kind: k))
                }
                if isGeneral(e, kinds: kinds) {
                    general.append(TaxPaidRecord(expenseId: e.id, periodDate: e.date, amountNTD: amount,
                                                 source: .general, kind: k))
                }
            } else if isFixedTax(e, kinds: kinds), let rec = e.recurrence {
                let k: ExpenseKind? = kinds.taxKind(of: e)
                let history: [AmountSnapshot] = e.amountHistory.sorted { $0.date < $1.date }
                let src: TaxPaidSource = .recurring(rec, estateId: e.linkedRealEstateId, vehicleId: e.linkedVehicleId)
                for due in fixedDueDates(e, year: year, now: now, calendar: calendar) {
                    let raw: Double = WealthSchedule.amount(at: due, current: e.amount, sortedHistory: history)
                    fixed.append(TaxPaidRecord(expenseId: e.id, periodDate: due,
                                               amountNTD: WealthSchedule.ntd(of: e, raw: raw, rates: rates),
                                               source: src, kind: k))
                }
            }
        }
        var seen: Set<String> = []
        var out: [TaxPaidRecord] = []
        for r in vehicle + house + general + fixed where !seen.contains(r.id) {
            seen.insert(r.id)
            out.append(r)
        }
        return sorted(out)
    }

    /// 那一年另外繳的罰款（細項是罰款的變動支出；不算進年度稅費）
    static func fines(year: Int, expenses: [Expense], kinds: ExpenseKindIndex, rates: FinanceRates,
                      calendar: Calendar) -> [TaxPaidRecord] {
        var out: [TaxPaidRecord] = []
        for e in expenses where e.expenseType == .variable && Self.year(e.date, calendar) == year {
            guard let hit = kinds.kind(of: e), hit.kind.nature == .fine else { continue }
            let src: TaxPaidSource = e.vehicleExpenseCategory != nil ? .vehicle(e.linkedVehicleId) : .general
            out.append(TaxPaidRecord(expenseId: e.id, periodDate: e.date,
                                     amountNTD: WealthSchedule.ntd(of: e, raw: e.amount, rates: rates),
                                     source: src, kind: hit.kind))
        }
        return sorted(out)
    }

    static func total(_ list: [TaxPaidRecord]) -> Double {
        list.reduce(0.0) { $0 + $1.amountNTD }
    }

    /// 月份分佈（照那一期的扣款日；固定那筆在 11 月扣就在 11 月）
    static func byMonth(_ list: [TaxPaidRecord], calendar: Calendar) -> [TaxPaidMonth] {
        var sums: [Int: Double] = [:]
        for r in list { sums[calendar.component(.month, from: r.periodDate), default: 0] += r.amountNTD }
        var out: [TaxPaidMonth] = []
        for m in 1...12 {
            let a: Double = sums[m] ?? 0
            if a > 0 { out.append(TaxPaidMonth(month: m, amount: a)) }
        }
        return out
    }

    // ── 檢核 ──

    /// 沒標細項的那筆從名稱看（只給檢核「已記」用；不寫、不改紀錄的 kind）
    static func wordKind(_ title: String) -> ExpenseKind? {
        if title.contains("地價") { return .landValueTax }
        if title.contains("房屋稅") { return .houseTax }
        if title.contains("牌照") { return .licenseTax }
        if title.contains("燃料") { return .fuelFee }
        return nil
    }

    /// 檢核用的細項：有標照標的，沒標看名稱
    static func checkKind(_ r: TaxPaidRecord, byId: [UUID: Expense]) -> ExpenseKind? {
        if let k = r.kind { return k }
        guard let e = byId[r.expenseId] else { return nil }
        return wordKind(e.title)
    }

    /// 那一年還算持有（買進那年 ≤ year；賣掉的那年起不查）
    static func ownsEstate(_ re: RealEstate, year: Int, calendar: Calendar) -> Bool {
        guard Self.year(re.purchaseDate, calendar) <= year else { return false }
        if let sold = re.soldDate, Self.year(sold, calendar) <= year { return false }
        return true
    }

    static func ownsVehicle(_ v: Vehicle, year: Int, calendar: Calendar) -> Bool {
        guard Self.year(v.purchaseDate, calendar) <= year else { return false }
        if let sold = v.soldDate, Self.year(sold, calendar) <= year { return false }
        return true
    }

    static let landAfterAugNote = "8/31 以後才買的，那年的地價稅是前屋主繳的。"
    static let houseBuyYearNote = "買進那年的房屋稅可能已跟前屋主結算。"
    static let electricLicenseNote = "電動車目前免徵牌照稅，以稅單為準。"
    static func duplicateNote(_ n: Int) -> String { "可能記了兩次（\(n) 筆），打開確認。" }

    /// 一個細項的狀態：已記／還沒到／還沒看到紀錄（需要查的資產一個都沒有：有說明＝不用查，沒說明＝灰的）
    static func state(kind: ExpenseKind, needed: Bool, excusedNote: String?, recorded: Bool,
                      year: Int, now: Date, calendar: Calendar) -> (TaxCheckState, String?) {
        if recorded { return (.recorded, nil) }
        guard needed else {
            if let n = excusedNote { return (.notNeeded, n) }
            return (.irrelevant, nil)
        }
        let ty = Self.year(now, calendar)
        let tm = calendar.component(.month, from: now)
        let due: Int = kind.dueMonth ?? 12
        if year > ty || (year == ty && tm < due) { return (.notYet, nil) }
        return (.missing, nil)
    }

    /// 年度稅務檢核（順序照 25.616 以前：綜所稅、房屋稅、牌照稅、地價稅、燃料費、二代健保）。
    /// 排除：8/31 以後才買的房那年不查地價稅；買進那年的房屋稅寫「可能已跟前屋主結算」；電車牌照稅寫「目前免徵」；
    /// 燃料費只查油車、油電（機車、電車不要求；都沒有就不列）；賣掉的那年起不查。同一年同細項兩筆以上 →「可能記了兩次」
    static func checks(year: Int, records: [TaxPaidRecord], expenses: [Expense], estates: [RealEstate],
                       vehicles: [Vehicle], hasIncome: Bool, now: Date, calendar: Calendar) -> [TaxCheckItem] {
        let byId: [UUID: Expense] = Dictionary(expenses.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var ids: [ExpenseKind: Set<UUID>] = [:]
        for r in records {
            if let k = checkKind(r, byId: byId) { ids[k, default: []].insert(r.expenseId) }
        }
        let owned: [RealEstate] = estates.filter { ownsEstate($0, year: year, calendar: calendar) }
        let cars: [Vehicle] = vehicles.filter { ownsVehicle($0, year: year, calendar: calendar) }
        let landNeeded: Bool = owned.contains { re in
            !(Self.year(re.purchaseDate, calendar) == year && calendar.component(.month, from: re.purchaseDate) >= 9)
        }
        let houseNeeded: Bool = owned.contains { re in Self.year(re.purchaseDate, calendar) < year }
        let licenseNeeded: Bool = cars.contains { v in !ExpenseKindForm.isElectric(v.powerType) }
        let fuelNeeded: Bool = cars.contains { v in v.powerType == .gasoline || v.powerType == .hybrid }

        func item(_ title: String, _ month: String, _ k: ExpenseKind, needed: Bool, excused: String?) -> TaxCheckItem {
            let n: Int = ids[k]?.count ?? 0
            let (st, note) = state(kind: k, needed: needed, excusedNote: excused, recorded: n > 0,
                                   year: year, now: now, calendar: calendar)
            let dup: String? = n >= 2 ? duplicateNote(n) : nil
            return TaxCheckItem(id: title, title: title, month: month, kind: k, state: st, note: dup ?? note)
        }

        var out: [TaxCheckItem] = []
        let ty = Self.year(now, calendar)
        out.append(TaxCheckItem(id: "綜合所得稅申報", title: "綜合所得稅申報", month: "5月", kind: nil,
                                state: year < ty ? .reminder : .irrelevant, note: nil))
        out.append(item("房屋稅繳納", "5月", .houseTax, needed: houseNeeded,
                        excused: owned.isEmpty ? nil : houseBuyYearNote))
        out.append(item("汽機車使用牌照稅", "4月", .licenseTax, needed: licenseNeeded,
                        excused: cars.isEmpty ? nil : electricLicenseNote))
        out.append(item("地價稅繳納", "11月", .landValueTax, needed: landNeeded,
                        excused: owned.isEmpty ? nil : landAfterAugNote))
        if fuelNeeded || (ids[.fuelFee]?.isEmpty == false) {
            out.append(item("汽機車燃料費", "7月", .fuelFee, needed: fuelNeeded, excused: nil))
        }
        out.append(TaxCheckItem(id: "二代健保補充保費", title: "二代健保補充保費", month: "全年", kind: nil,
                                state: hasIncome ? .reminder : .irrelevant, note: nil))
        return out
    }

    /// 可能是稅費：固定「其他」＋每年、沒細項也推不出來、那一年有一期（車險記成其他那種）。不算進年度稅費
    /// （使用者明確說過不是的不寫：saidNotTax）
    static func maybeTax(year: Int, expenses: [Expense], kinds: ExpenseKindIndex, now: Date,
                         calendar: Calendar) -> [Expense] {
        expenses.filter { e in
            e.isRecurringFixed && e.fixedCategory == .other && e.recurrence == .yearly && kinds.kind(of: e) == nil
                && !saidNotTax(e, kinds: kinds)
                && !fixedDueDates(e, year: year, now: now, calendar: calendar).isEmpty
        }
    }

    /// 使用者明確說過這筆不是：在表單拿掉過細項（墓碑），或推的牌照稅／燃料費按過〔不是〕（跟一鍵整理同一個意思，不再提）
    static func saidNotTax(_ e: Expense, kinds: ExpenseKindIndex) -> Bool {
        if kinds.isTombstoned(e.id) { return true }
        if let k = ExpenseKindIndex.inferredKind(e), kinds.isDismissed(e.id, k) { return true }
        return false
    }

    /// 一般變動「稅費」裡名稱有「罰」的（L9：罰單、罰鍰不是稅費）
    static func fineNamed(_ records: [TaxPaidRecord], byId: [UUID: Expense]) -> [Expense] {
        var out: [Expense] = []
        for r in records where r.source == .general && r.kind == nil {
            if let e = byId[r.expenseId], e.title.contains("罰"), !out.contains(where: { $0.id == e.id }) { out.append(e) }
        }
        return out
    }

    /// 列名：「一日拾樂-地價稅」→ 名稱照存的；空的寫「固定支出」
    static func shownTitle(_ e: Expense) -> String {
        let t: String = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "固定支出" : t
    }

    /// 稅務頁要的全部（body 外面算一次）
    static func summary(year: Int, expenses: [Expense], kinds: ExpenseKindIndex, rates: FinanceRates,
                        estates: [RealEstate], vehicles: [Vehicle], hasIncome: Bool,
                        now: Date, calendar: Calendar) -> TaxPaidSummary {
        let recs = records(year: year, expenses: expenses, kinds: kinds, rates: rates, now: now, calendar: calendar)
        let fs = fines(year: year, expenses: expenses, kinds: kinds, rates: rates, calendar: calendar)
        let byId: [UUID: Expense] = Dictionary(expenses.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var hints: [String] = []
        let maybe: [String] = maybeTax(year: year, expenses: expenses, kinds: kinds, now: now, calendar: calendar)
            .map { shownTitle($0) }
        if let line = TaxPaidText.maybeTaxLine(maybe) { hints.append(line) }
        let fined: [String] = fineNamed(recs, byId: byId).map { shownTitle($0) }
        if let line = TaxPaidText.fineNamedLine(fined) { hints.append(line) }
        return TaxPaidSummary(records: recs, fines: fs, total: total(recs), finesTotal: total(fs),
                              byMonth: byMonth(recs, calendar: calendar),
                              checks: checks(year: year, records: recs, expenses: expenses, estates: estates,
                                             vehicles: vehicles, hasIncome: hasIncome, now: now, calendar: calendar),
                              hints: hints)
    }

    // ── 列上的字 ──

    /// 列名：有細項寫細項（「地價稅」），沒有寫那筆的名稱（空的寫「稅費」）
    static func rowTitle(_ r: TaxPaidRecord, expense: Expense?) -> String {
        if let k = r.kind { return k.raw }
        let t: String = expense?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? "稅費" : t
    }

    /// 來源膠囊（App 內才有）：「房子・一日拾樂」「車子・Swift Sport」「每年」；名字查不到寫「房子」「車子」
    static func sourceChips(_ s: TaxPaidSource, estateNames: [UUID: String], vehicleNames: [UUID: String]) -> [String] {
        func named(_ head: String, _ id: UUID?, _ names: [UUID: String]) -> String {
            guard let id, let n = names[id]?.trimmingCharacters(in: .whitespaces), !n.isEmpty else { return head }
            return head + "・" + n
        }
        switch s {
        case .general:
            return []
        case .house(let id):
            return [named("房子", id, estateNames)]
        case .vehicle(let id):
            return [named("車子", id, vehicleNames)]
        case .recurring(let rec, let estateId, let vehicleId):
            var out: [String] = []
            if estateId != nil { out.append(named("房子", estateId, estateNames)) }
            if vehicleId != nil { out.append(named("車子", vehicleId, vehicleNames)) }
            out.append(rec.rawValue)
            return out
        }
    }

    /// 固定那幾列（一期一列）才有：金額以繳款書為準
    static func isRecurring(_ s: TaxPaidSource) -> Bool {
        if case .recurring = s { return true }
        return false
    }
}

/// 稅務頁的字（只在 App 內稅務頁）
enum TaxPaidText {
    /// 「另外繳了罰款 NT$600（1 筆）・不算稅費」（點開列出）
    static func finesLine(_ amountText: String, count: Int) -> String {
        "另外繳了罰款 " + amountText + "（\(count) 筆）・不算稅費"
    }

    /// 「可能是稅費：「全險」（打開確認；是的話類別選「稅費」）」；三筆以上寫「等 N 筆」
    static func maybeTaxLine(_ names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        let shown: String = names.prefix(3).map { "「" + $0 + "」" }.joined(separator: "、")
        let more: String = names.count > 3 ? " 等 \(names.count) 筆" : ""
        return "可能是稅費：" + shown + more + "（打開確認；是的話類別選「稅費」，不算進上面的年度稅費）"
    }

    /// L9：「「停車罰單」名稱有「罰」：罰單、罰鍰不是稅費，汽車的記成車子「罰款」。」
    static func fineNamedLine(_ names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        let shown: String = names.prefix(3).map { "「" + $0 + "」" }.joined(separator: "、")
        return shown + "名稱有「罰」：罰單、罰鍰不是稅費，汽車的記成車子「罰款」。"
    }

    /// 固定那幾列下面的灰字
    static let recurringFooter = "每年固定的稅費照記帳的金額算，金額以繳款書為準。"

    /// 可收合的說明
    static let notesTitle = "稅費能不能抵稅？"
    static let notes: [String] = [
        "地價稅、房屋稅、牌照稅、燃料費都不能列舉扣除。",
        "出租的房子申報租賃所得、選核實減除時，那間房的地價稅、房屋稅可以當費用。",
        "買房那次的契稅、印花稅、代書、登記規費記「買房費用」，收據留著，以後賣房可以算成本。",
        "罰單、拖吊、滯納金是罰款，不算稅費，另外列一行。",
    ]
}
