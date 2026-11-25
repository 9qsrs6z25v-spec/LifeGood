// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.642 mac3 G3] 細項 Lite（只顯示「汽車 - 罰款」「稅費・地價稅」；judge_mac §Q7 ⑭）。
// [v25.644 mac4 G3] Mac 4 補推的規則與 dismissed（judge_mac §R7 ⑱）：沒有 tag 的那筆照 iPhone 推的規則（固定、分類選最後一項、
// 每年、連車沒連房子、不是記成那一類的車險；名稱有「牌照」→ 牌照稅、有「燃料」→ 燃料費），〔不是〕過（dismissed）就不推；
// taxKind、固定支出頁分組 MacFixedGroupKey.of 照抄。只顯示、只分組，電腦不寫細項這一包。
// 照抄 ExpenseKinds.swift（48c51a2；Mac 4 那幾支 f2c8892）讀的那幾支：ExpenseKind（不抄 id、dueMonths）、ExpenseKindIndex.init（Mac 4 起含 dismissed）、
// signature、allowed、kind(of:)（Mac 4 起沒有 tag 走推的規則）、displayCategoryName、inferredKind、taxKind、FixedGroup.of。
// 只解 tags[].id、kind、base、updatedAt，以及 dismissed[].id、kind（Decodable only）；sameAs、dismissed 的 at、extra 不解。
// 那個 9 個字清單裡的「…稅費」用 VehicleVariableCategory.other.rawValue + RealEstateExpenseCategory.tax.rawValue 拼
//（＝ExpenseKinds.swift:36 那個字；Mac 字面值不寫那兩個字）。sim3: kinds#14（sim_mac3.py kind_index／kind_of／display_category_name）
import Foundation

// MARK: - 細項（照抄 ExpenseKinds.swift:22-57（48c51a2）ExpenseKind）

struct MacLiteKind: Hashable {
    let raw: String

    init(_ raw: String) { self.raw = raw }

    static let landValueTax = MacLiteKind("地價稅")
    static let houseTax = MacLiteKind("房屋稅")
    static let landIncrementTax = MacLiteKind("土地增值稅")
    static let houseLandTax = MacLiteKind("房地合一稅")
    static let licenseTax = MacLiteKind("牌照稅")
    static let fuelFee = MacLiteKind("燃料費")
    static let fee = MacLiteKind("規費")
    static let otherTax = MacLiteKind(VehicleVariableCategory.other.rawValue + RealEstateExpenseCategory.tax.rawValue)
    static let fine = MacLiteKind("罰款")

    /// 這一版認得的九個（順序＝一般變動「稅費」v4 的清單順序）
    static let known: [MacLiteKind] = [.landValueTax, .houseTax, .landIncrementTax, .houseLandTax,
                                       .licenseTax, .fuelFee, .fee, .otherTax, .fine]

    var isKnown: Bool { Self.known.contains(self) }

    /// 性質：罰款＝罰款、規費＝規費、不認得的字＝稅
    enum Nature: Equatable {
        case tax, fee, fine
    }

    var nature: Nature {
        if self == .fine { return .fine }
        if self == .fee { return .fee }
        return .tax
    }

    /// 稅或規費（罰款不算）
    var isTaxOrFee: Bool { nature != .fine }
}

// MARK: - 讀（{"tags": [...]}；其他鍵一律不看）

/// 一筆 tag（照抄 ExpenseKindTag 的逐欄容錯：id 一定要是 UUID，其他欄解不開＝nil）
struct MacKindLiteTag: Decodable {
    var id: UUID
    var kind: String?
    var base: String?
    var updatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, kind, base, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try? c.decodeIfPresent(String.self, forKey: .kind)
        base = try? c.decodeIfPresent(String.self, forKey: .base)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

/// [v25.644 mac4] 一筆〔不是〕（照抄 ExpenseKindDismissal 的 id、kind；at、extra 不解；id 不是 UUID、kind 不是字串＝整筆丟掉）— sim4: kinds4#2
struct MacKindLiteDismissal: Decodable {
    var id: UUID
    var kind: String

    private enum CodingKeys: String, CodingKey {
        case id, kind
    }
}

/// 細項那包（只解 tags、dismissed；壞一筆只丟那筆）
struct MacKindLiteBook: Decodable {
    var tags: [MacKindLiteTag]?
    /// [v25.644 mac4] 〔不是〕過的（推的規則看這個）— sim4: kinds4#2
    var dismissed: [MacKindLiteDismissal]?

    private enum CodingKeys: String, CodingKey {
        case tags, dismissed
    }

    init() {
        tags = nil
        dismissed = nil
    }

    // 照抄 ExpenseKinds.swift:183-188（f2c8892）ExpenseKindBook.init(from:)（extra 不解）
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tags = macKindLossyArray(MacKindLiteTag.self, c, .tags)
        dismissed = macKindLossyArray(MacKindLiteDismissal.self, c, .dismissed)
    }
}

struct MacKindIndex {
    static let empty = MacKindIndex(data: nil)

    /// 每筆支出的原始 tag（含墓碑；同一個 id 有兩筆時留 updatedAt 新的）
    private let tags: [UUID: MacKindLiteTag]
    /// [v25.644 mac4] 〔不是〕過的「id|細項」（推的規則看這個；id 一律大寫標準形）— sim4: kinds4#2
    private let dismissedKeys: Set<String>

    // 照抄 ExpenseKinds.swift:82-90（48c51a2）ExpenseKindIndex.init(book:)（Mac 4 起含 dismissed：f2c8892 :89）；整包解不開＝空
    init(data: Data?) {
        var book = MacKindLiteBook()
        if let data, let b = try? JSONDecoder().decode(MacKindLiteBook.self, from: data) {
            book = b
        }
        var map: [UUID: MacKindLiteTag] = [:]
        for t in book.tags ?? [] {
            if let old = map[t.id], (old.updatedAt ?? .distantPast) >= (t.updatedAt ?? .distantPast) { continue }
            map[t.id] = t
        }
        tags = map
        dismissedKeys = Set((book.dismissed ?? []).map { d in MacKindIndex.dismissKey(d.id, d.kind) })
    }

    // 照抄 ExpenseKinds.swift:94-99（48c51a2）
    static func signature(_ e: Expense) -> String {
        if e.expenseType == .fixed { return "fixed." + (e.fixedCategory?.rawValue ?? "") }
        if let v = e.vehicleExpenseCategory { return "vehicle." + v.rawValue }
        if let r = e.realEstateExpenseCategory { return "re." + r.rawValue }
        return "var." + (e.variableCategory?.rawValue ?? "")
    }

    // 照抄 ExpenseKinds.swift:102-116（48c51a2）
    static func allowed(_ signature: String) -> [MacLiteKind] {
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
            return MacLiteKind.known
        }
        return []
    }

    // 照抄 ExpenseKinds.swift:122-131（f2c8892）kind(of:)；[v25.644 mac4] 連墓碑都沒有的那筆照推的規則（inferredHit）— sim4: kinds4#1
    func hit(of e: Expense) -> MacLiteKind? {
        if tags[e.id] == nil { return inferredHit(e) }
        guard let t = tags[e.id], let raw = t.kind, !raw.isEmpty else { return nil }
        let sig = Self.signature(e)
        guard let base = t.base, base == sig else { return nil }
        let k = MacLiteKind(raw)
        if k.isKnown && !Self.allowed(sig).contains(k) { return nil }
        return k
    }

    /// 這筆的細項字（沒有＝nil）— sim3: kinds#14
    func kind(of e: Expense) -> String? { hit(of: e)?.raw }

    // [v25.644 mac4] 照抄 ExpenseKinds.swift:134-137（f2c8892）taxKind（簽名照總設計骨架，不准改）
    /// 稅或規費的細項（罰款、沒有細項都回 nil）— sim4: kinds4#3
    func taxKind(of e: Expense) -> MacLiteKind? {
        guard let k = hit(of: e), k.isTaxOrFee else { return nil }
        return k
    }

    // MARK: [v25.644 mac4] 推的規則與〔不是〕（照抄 ExpenseKinds.swift:730-753（f2c8892）；只顯示、不寫）

    // 照抄 ExpenseKinds.swift:730-732（f2c8892）dismissKey
    /// dismissed 的比對字（id|細項字）
    static func dismissKey(_ id: UUID, _ kind: String) -> String {
        id.uuidString + "|" + kind
    }

    // 照抄 ExpenseKinds.swift:735-737（f2c8892）isDismissed
    /// 〔不是〕過這筆的這個細項
    func isDismissed(_ id: UUID, _ k: MacLiteKind) -> Bool {
        dismissedKeys.contains(Self.dismissKey(id, k.raw))
    }

    // 照抄 ExpenseKinds.swift:740-747（f2c8892）inferredKind（字「牌照」「燃料」照抄）— sim4: kinds4#1
    /// 推的規則：只看那筆本身（不看 tag、不看 dismissed：那兩個在 inferredHit 看）
    static func inferredKind(_ e: Expense) -> MacLiteKind? {
        guard e.expenseType == .fixed, e.fixedCategory == .other, e.recurrence == .yearly,
              e.linkedVehicleId != nil, e.linkedRealEstateId == nil,
              !MacKindIndex.isInsuranceAsOther(e) else { return nil }
        if e.title.contains("牌照") { return .licenseTax }
        if e.title.contains("燃料") { return .fuelFee }
        return nil
    }

    // 照抄 ExpenseKinds.swift:750-753（f2c8892）inferredHit（Mac 的 hit 只回細項，不帶 inferred 旗標）
    /// 沒有 tag 的那筆推得出來、而且沒〔不是〕過 → 那個細項（hit(of:) 開頭叫）
    private func inferredHit(_ e: Expense) -> MacLiteKind? {
        guard let k = Self.inferredKind(e), !isDismissed(e.id, k) else { return nil }
        return k
    }

    // 照抄 VehicleCardData.swift:2982（f2c8892）VehicleFixes.insuranceWords — sim4: kinds4#1
    /// 名稱或備註裡有這些字，就看得出是車險
    static let insuranceWords = ["保險", "車險", "強制險", "綜合險", "乙式", "丙式", "甲式", "第三人責任", "竊盜險", "車體險"]

    // 照抄 VehicleCardData.swift:2986-2991（f2c8892）VehicleFixes.isInsuranceAsOther — sim4: kinds4#1
    /// 記成分類最後一項（或沒有分類）的車險：週期固定支出、名稱或備註看得出是車險
    static func isInsuranceAsOther(_ ex: Expense) -> Bool {
        guard ex.expenseType == .fixed, ex.isRecurringFixed else { return false }
        guard ex.fixedCategory == .other || ex.fixedCategory == nil else { return false }
        let text = ex.title + "\n" + ex.note
        return insuranceWords.contains { text.contains($0) }
    }
}

// MARK: - [v25.644 mac4] 固定支出頁的分組（照抄 ExpenseKinds.swift:555-571（f2c8892）FixedGroup；總設計先放骨架，G3 填 of）

enum MacFixedGroupKey: Hashable {
    case category(FixedCategory)
    case tax

    // 照抄 ExpenseKinds.swift:559-563（f2c8892）FixedGroup.of（簽名照總設計骨架，不准改）
    /// 有稅類／規費細項的最後一類歸「稅費」組；每一筆只歸一組 — sim4: kinds4#4
    static func of(_ e: Expense, kinds: MacKindIndex) -> MacFixedGroupKey {
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

extension Expense {
    // 照抄 ExpenseKinds.swift:577-588（48c51a2）displayCategoryName(kinds:)
    /// 「汽車 - 罰款」「稅費・地價稅」；沒有細項照 categoryName
    func macDisplayCategoryName(kinds: MacKindIndex) -> String {
        guard let hit = kinds.hit(of: self) else { return categoryName }
        let k = hit
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

// MARK: - 逐筆容錯（照抄 Competency.swift:121-132（48c51a2）CompetencyCoding.lossyArray）

private struct MacKindSkip: Decodable {}

fileprivate func macKindLossyArray<T: Decodable, K: CodingKey>(_ type: T.Type, _ c: KeyedDecodingContainer<K>,
                                                               _ key: K) -> [T]? {
    guard c.contains(key), var arr = try? c.nestedUnkeyedContainer(forKey: key) else { return nil }
    var out: [T] = []
    while !arr.isAtEnd {
        if let v = try? arr.decode(T.self) {
            out.append(v)
        } else if (try? arr.decode(MacKindSkip.self)) == nil {
            break
        }
    }
    return out
}
