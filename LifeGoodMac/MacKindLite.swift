// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.642 mac3 G3] 細項 Lite（只顯示「汽車 - 罰款」「稅費・地價稅」；judge_mac §Q7 ⑭）。
// 照抄 ExpenseKinds.swift（48c51a2）讀的那幾支：ExpenseKind（不抄 id、dueMonths）、ExpenseKindIndex.init（不抄 dismissed）、
// signature、allowed、kind(of:)（沒有 tag 一律 nil：不抄推的規則，Mac 4 再決定）、displayCategoryName。
// 只解 tags[].id、kind、base、updatedAt（Decodable only）；sameAs、dismissed、extra 不解。
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

/// 細項那包（只解 tags；壞一筆只丟那筆）
struct MacKindLiteBook: Decodable {
    var tags: [MacKindLiteTag]?

    private enum CodingKeys: String, CodingKey {
        case tags
    }

    init() {
        tags = nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tags = macKindLossyArray(MacKindLiteTag.self, c, .tags)
    }
}

struct MacKindIndex {
    static let empty = MacKindIndex(data: nil)

    /// 每筆支出的原始 tag（含墓碑；同一個 id 有兩筆時留 updatedAt 新的）
    private let tags: [UUID: MacKindLiteTag]

    // 照抄 ExpenseKinds.swift:82-90（48c51a2）ExpenseKindIndex.init(book:)（不抄 dismissed）；整包解不開＝空
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

    // 照抄 ExpenseKinds.swift:122-131（48c51a2）kind(of:)；沒有 tag 回 nil（不抄 inferredHit）
    func hit(of e: Expense) -> MacLiteKind? {
        if tags[e.id] == nil { return nil }
        guard let t = tags[e.id], let raw = t.kind, !raw.isEmpty else { return nil }
        let sig = Self.signature(e)
        guard let base = t.base, base == sig else { return nil }
        let k = MacLiteKind(raw)
        if k.isKnown && !Self.allowed(sig).contains(k) { return nil }
        return k
    }

    /// 這筆的細項字（沒有＝nil）— sim3: kinds#14
    func kind(of e: Expense) -> String? { hit(of: e)?.raw }

    // [v25.644 mac4] 總設計先放骨架（G3 照抄 ExpenseKinds.swift:134-137（f2c8892）taxKind；簽名不准改）
    /// 稅或規費的細項（罰款、沒有細項都回 nil）— sim4: kinds4#3
    func taxKind(of e: Expense) -> MacLiteKind? { nil }
}

// MARK: - [v25.644 mac4] 固定支出頁的分組（照抄 ExpenseKinds.swift:555-571（f2c8892）FixedGroup；總設計先放骨架，G3 填 of）

enum MacFixedGroupKey: Hashable {
    case category(FixedCategory)
    case tax

    /// 有稅類／規費細項的最後一類歸「稅費」組；每一筆只歸一組 — sim4: kinds4#4
    static func of(_ e: Expense, kinds: MacKindIndex) -> MacFixedGroupKey {
        .category(e.fixedCategory ?? .other)
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
