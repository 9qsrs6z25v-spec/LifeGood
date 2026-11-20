import Foundation

// MARK: - [v25.599 職能雷達 v1a-1] 職能項目設定與評分（同步鍵 life_competency_setup_v1、life_competency_ratings_v1）
//（radar/judge.md §2 資料模型、§2.3 合併、§2.4 登記、§1.4-1 不認得的欄位原樣保留、§1.4-2 範例固定代號、§13 使用者決定；
//  radar/build/v1a-1/brief.md §2；sim_v1a-1.py 一個函式一個函式對照）
//
// • 題目（設定）跟答案（評分）分兩個鍵：一台改設定、一台在評分，各推各的鍵，不會整包互蓋。
// • 部屬、組織人員、部門、職等、部屬紀錄一個欄位都沒加（舊 iPad 存一次會洗掉）；新的東西全部在這兩個鍵裡。
// • 全部欄位 Optional＋容錯解（id 除外）；陣列逐筆解（一筆壞掉只丟那一筆）；kind、raterKind 存字串。
// • 每一種型別都有 extra：這台 App 看不懂的欄位（之後版本才加的）解碼時收起來、存檔時原樣寫回去
//  （先寫 extra、再寫已知欄位；extra 裡跟已知欄位同名的不寫）。兩個 Book 有 formatVersion（v1a＝1）：
//   比這台認得的新 → 這個鍵唯讀（看得到、不能改），畫面頂上一行「這台的 App 比較舊，評分請在已更新的那台做」。
// • 合併：照 id 取 updatedAt 新的（一樣新留 self＝收進來的那份）；墓碑（deletedAt）跟著那一筆走；
//   同一張評分「逐格」合併（每一格各比自己的 updatedAt／clearedAt）。
// • 範例（〔用範例開始〕）的組、項目用固定代號；人格特質那一組不管怎麼建都是 traitGroupId——兩台各按一次合併後只有一份。
// • §13：每一分出廠不帶名字（levels 空）；分數範圍 0 ≤ low < high ≤ 100。
// • 隱私：這裡的字只在 App 內頁；通知、小工具、手錶、鎖定畫面、靈動島一個字都沒加。

// MARK: - 不認得的欄位原樣保留

/// 任何 JSON 值（只用在 extra：原樣收、原樣寫）
enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
            return
        }
        // Bool 要先試：JSONDecoder 不會把 true 當成數字
        if let b = try? c.decode(Bool.self) {
            self = .bool(b)
            return
        }
        if let d = try? c.decode(Double.self) {
            self = .number(d)
            return
        }
        if let s = try? c.decode(String.self) {
            self = .string(s)
            return
        }
        if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
            return
        }
        if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
            return
        }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "不認得的 JSON 值")
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let s):
            var c = encoder.singleValueContainer()
            try c.encode(s)
        case .number(let d):
            var c = encoder.singleValueContainer()
            try c.encode(d)
        case .bool(let b):
            var c = encoder.singleValueContainer()
            try c.encode(b)
        case .array(let a):
            var c = encoder.unkeyedContainer()
            for v in a { try c.encode(v) }
        case .object(let o):
            // 照鍵排序寫：每次存出來的字一樣（不會因為字典順序不同就被當成「改過」又推一次）
            var c = encoder.container(keyedBy: CompetencyAnyKey.self)
            for k in o.keys.sorted() {
                if let v = o[k] { try c.encode(v, forKey: CompetencyAnyKey(k)) }
            }
        case .null:
            var c = encoder.singleValueContainer()
            try c.encodeNil()
        }
    }
}

/// 動態鍵（收 extra、寫 extra 用）
struct CompetencyAnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

/// 解碼、存檔共用的小工具
enum CompetencyCoding {
    /// 已知鍵以外的全部收進來（沒有就回 nil）
    static func readExtra(_ decoder: Decoder, known: Set<String>) -> [String: JSONValue]? {
        guard let c = try? decoder.container(keyedBy: CompetencyAnyKey.self) else { return nil }
        var out: [String: JSONValue] = [:]
        for k in c.allKeys where !known.contains(k.stringValue) {
            if let v = try? c.decode(JSONValue.self, forKey: k) {
                out[k.stringValue] = v
            }
        }
        return out.isEmpty ? nil : out
    }

    /// 先寫 extra（跟已知欄位同名的跳過，已知的會在後面寫）
    static func writeExtra(_ extra: [String: JSONValue]?, _ encoder: Encoder, known: Set<String>) throws {
        guard let extra, !extra.isEmpty else { return }
        var c = encoder.container(keyedBy: CompetencyAnyKey.self)
        for k in extra.keys.sorted() where !known.contains(k) {
            if let v = extra[k] { try c.encode(v, forKey: CompetencyAnyKey(k)) }
        }
    }

    /// 陣列逐筆解：一筆壞掉只丟那一筆（照 OrgReorgBook.init(from:)）。鍵不在＝nil
    static func lossyArray<T: Decodable, K: CodingKey>(_ type: T.Type, _ c: KeyedDecodingContainer<K>, _ key: K) -> [T]? {
        guard c.contains(key), var arr = try? c.nestedUnkeyedContainer(forKey: key) else { return nil }
        var out: [T] = []
        while !arr.isAtEnd {
            if let v = try? arr.decode(T.self) {
                out.append(v)
            } else if (try? arr.decode(CompetencySkip.self)) == nil {
                break
            }
        }
        return out
    }

    /// 兩包 extra 合在一起（self 那包優先）
    static func mergeExtra(_ a: [String: JSONValue]?, _ b: [String: JSONValue]?) -> [String: JSONValue]? {
        guard let b, !b.isEmpty else { return a }
        var out = a ?? [:]
        for (k, v) in b where out[k] == nil { out[k] = v }
        return out.isEmpty ? nil : out
    }

    /// 照 id 合併兩份清單：同一筆取 stamp 新的（一樣新留 mine）；只有一邊有就留著。兩邊都是 nil 回 nil
    static func mergeList<T, K: Hashable>(_ mine: [T]?, _ other: [T]?, key: (T) -> K, stamp: (T) -> Date) -> [T]? {
        if mine == nil && other == nil { return nil }
        var out: [T] = mine ?? []
        var index: [K: Int] = [:]
        for (i, x) in out.enumerated() { index[key(x)] = i }
        for o in other ?? [] {
            let k = key(o)
            if let i = index[k] {
                if stamp(o) > stamp(out[i]) { out[i] = o }
            } else {
                index[k] = out.count
                out.append(o)
            }
        }
        return out
    }
}

/// 逐筆解時跳過壞掉的那一筆用（任何 JSON 物件都解得出來）
private struct CompetencySkip: Decodable {}

// MARK: - 範圍（幾分到幾分）

/// 一個分數範圍：0 ≤ low < high ≤ 100（§13）。不做半分
struct CompetencyRange: Equatable, Hashable {
    var low: Int
    var high: Int

    /// 出廠 1–5
    static let standard = CompetencyRange(low: 1, high: 5)
    static let minValue = 0
    static let maxValue = 100

    static func isValid(low: Int, high: Int) -> Bool {
        low >= minValue && low < high && high <= maxValue
    }

    /// 存檔讀到不合理的範圍（別台亂寫、壞掉）→ 回出廠 1–5
    static func safe(low: Int?, high: Int?) -> CompetencyRange {
        guard let l = low, let h = high, isValid(low: l, high: h) else { return standard }
        return CompetencyRange(low: l, high: h)
    }

    /// 幾級（1–5＝5 級、0–100＝101 級）
    var levelCount: Int { high - low + 1 }
    /// high ≤ 10 用圓按鈕；超過用滑桿＋數字欄＋〔－〕〔＋〕（§13）
    var usesButtons: Bool { high <= 10 }
    /// 「1–5」
    var text: String { "\(low)–\(high)" }

    func clamp(_ v: Int) -> Int { min(max(v, low), high) }
    func contains(_ v: Int) -> Bool { v >= low && v <= high }
}

// MARK: - 設定（life_competency_setup_v1）

/// 每一分的名字＋一句說明（§13：出廠空的；名字頁在 v1a-2）
struct CompetencyLevel: Codable, Equatable {
    var value: Int?
    var name: String?
    var detail: String?
    var extra: [String: JSONValue]?
}

extension CompetencyLevel {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case value, name, detail
    }
    static let knownKeys: Set<String> = Set(CodingKeys.allCases.map { $0.rawValue })

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = try? c.decodeIfPresent(Int.self, forKey: .value)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        detail = try? c.decodeIfPresent(String.self, forKey: .detail)
        extra = CompetencyCoding.readExtra(decoder, known: Self.knownKeys)
    }

    func encode(to encoder: Encoder) throws {
        try CompetencyCoding.writeExtra(extra, encoder, known: Self.knownKeys)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(value, forKey: .value)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(detail, forKey: .detail)
    }
}

/// 一份等級表：代號固定 "trait"（人格特質）、"skill"（本職學能，所有系統共用）
struct CompetencyScale: Codable, Equatable, Identifiable {
    var id: String
    var low: Int?
    var high: Int?
    var levels: [CompetencyLevel]?
    /// 「能獨立」「能教人」是第幾級（v2 才用；nil＝比例 0.5／0.75 最接近的一級）
    var independentLevel: Int?
    var trainerLevel: Int?
    var updatedAt: Date?
    var extra: [String: JSONValue]?

    /// 這份表現在的範圍（壞掉的回 1–5）
    var range: CompetencyRange { CompetencyRange.safe(low: low, high: high) }

    /// 那一分的名字（§13：出廠沒有 → nil）
    func levelName(_ value: Int) -> String? {
        guard let lv = levels?.first(where: { $0.value == value }),
              let n = lv.name?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty else { return nil }
        return n
    }

    var hasLevelNames: Bool {
        (levels ?? []).contains { !($0.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

extension CompetencyScale {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, low, high, levels, independentLevel, trainerLevel, updatedAt
    }
    static let knownKeys: Set<String> = Set(CodingKeys.allCases.map { $0.rawValue })

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        low = try? c.decodeIfPresent(Int.self, forKey: .low)
        high = try? c.decodeIfPresent(Int.self, forKey: .high)
        levels = CompetencyCoding.lossyArray(CompetencyLevel.self, c, .levels)
        independentLevel = try? c.decodeIfPresent(Int.self, forKey: .independentLevel)
        trainerLevel = try? c.decodeIfPresent(Int.self, forKey: .trainerLevel)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        extra = CompetencyCoding.readExtra(decoder, known: Self.knownKeys)
    }

    func encode(to encoder: Encoder) throws {
        try CompetencyCoding.writeExtra(extra, encoder, known: Self.knownKeys)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(low, forKey: .low)
        try c.encodeIfPresent(high, forKey: .high)
        try c.encodeIfPresent(levels, forKey: .levels)
        try c.encodeIfPresent(independentLevel, forKey: .independentLevel)
        try c.encodeIfPresent(trainerLevel, forKey: .trainerLevel)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}

/// 一組＝一張雷達：人格特質一組（固定代號 traitGroupId）、每個系統一組
struct CompetencyGroup: Codable, Equatable, Identifiable {
    var id: UUID
    /// "trait"（只會有一組）／"system"
    var kind: String?
    var name: String?
    /// 短名（最多 10 字；熱力表欄頭、膠囊用）
    var shortName: String?
    /// 卡片順序（插在中間用小數）
    var order: Double?
    /// 這個系統拿掉的共用學習項目
    var hiddenSharedItemIds: [UUID]?
    /// 停用（不畫、不評、分數留著）
    var archivedAt: Date?
    /// 這組用哪一份等級表（nil＝照 kind；先留著，未定）
    var scaleId: String?
    /// 對應的機台系統別（v5）
    var equipmentSystem: String?
    /// 這組自己的顏色 hex（未定）
    var color: String?
    var createdAt: Date?
    var updatedAt: Date?
    var deletedAt: Date?
    var extra: [String: JSONValue]?

    static let kindTrait = "trait"
    static let kindSystem = "system"

    var isTrait: Bool { kind == Self.kindTrait || id == CompetencySetupBook.traitGroupId }
    var isLive: Bool { deletedAt == nil }
    var isActive: Bool { deletedAt == nil && archivedAt == nil }
    /// 顯示用名字（空的寫「未命名系統」）
    var displayName: String {
        let n = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { return n }
        return isTrait ? "人格特質" : "未命名系統"
    }
    /// 合併用的時間
    var stamp: Date { updatedAt ?? deletedAt ?? createdAt ?? Date.distantPast }
}

extension CompetencyGroup {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, kind, name, shortName, order, hiddenSharedItemIds, archivedAt, scaleId, equipmentSystem, color
        case createdAt, updatedAt, deletedAt
    }
    static let knownKeys: Set<String> = Set(CodingKeys.allCases.map { $0.rawValue })

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try? c.decodeIfPresent(String.self, forKey: .kind)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        shortName = try? c.decodeIfPresent(String.self, forKey: .shortName)
        order = try? c.decodeIfPresent(Double.self, forKey: .order)
        hiddenSharedItemIds = try? c.decodeIfPresent([UUID].self, forKey: .hiddenSharedItemIds)
        archivedAt = try? c.decodeIfPresent(Date.self, forKey: .archivedAt)
        scaleId = try? c.decodeIfPresent(String.self, forKey: .scaleId)
        equipmentSystem = try? c.decodeIfPresent(String.self, forKey: .equipmentSystem)
        color = try? c.decodeIfPresent(String.self, forKey: .color)
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        deletedAt = try? c.decodeIfPresent(Date.self, forKey: .deletedAt)
        extra = CompetencyCoding.readExtra(decoder, known: Self.knownKeys)
    }

    func encode(to encoder: Encoder) throws {
        try CompetencyCoding.writeExtra(extra, encoder, known: Self.knownKeys)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(kind, forKey: .kind)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(shortName, forKey: .shortName)
        try c.encodeIfPresent(order, forKey: .order)
        try c.encodeIfPresent(hiddenSharedItemIds, forKey: .hiddenSharedItemIds)
        try c.encodeIfPresent(archivedAt, forKey: .archivedAt)
        try c.encodeIfPresent(scaleId, forKey: .scaleId)
        try c.encodeIfPresent(equipmentSystem, forKey: .equipmentSystem)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }
}

/// 一個項目：人格特質的（groupId＝traitGroupId）、共用學習項目（groupId＝nil）、某個系統自己的（groupId＝那個系統）。
/// **分數掛在這個 id 上**（改名，舊分數跟著新名字）
struct CompetencyItem: Codable, Equatable, Identifiable {
    var id: UUID
    var groupId: UUID?
    var name: String?
    /// 短名（最多 4 字；9 項以上軸上寫這個）
    var shortName: String?
    /// 雷達軸順序（12 點鐘起順時針）
    var order: Double?
    /// 這一項自己的每分說明（v1b）
    var levelDetails: [CompetencyLevel]?
    /// 權重（不打算做，先留位置）
    var weight: Double?
    var archivedAt: Date?
    var createdAt: Date?
    var updatedAt: Date?
    var deletedAt: Date?
    var extra: [String: JSONValue]?

    var isShared: Bool { groupId == nil }
    var isLive: Bool { deletedAt == nil }
    var isActive: Bool { deletedAt == nil && archivedAt == nil }
    var displayName: String {
        let n = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "未命名項目" : n
    }
    var stamp: Date { updatedAt ?? deletedAt ?? createdAt ?? Date.distantPast }
}

extension CompetencyItem {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, groupId, name, shortName, order, levelDetails, weight, archivedAt, createdAt, updatedAt, deletedAt
    }
    static let knownKeys: Set<String> = Set(CodingKeys.allCases.map { $0.rawValue })

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        groupId = try? c.decodeIfPresent(UUID.self, forKey: .groupId)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        shortName = try? c.decodeIfPresent(String.self, forKey: .shortName)
        order = try? c.decodeIfPresent(Double.self, forKey: .order)
        levelDetails = CompetencyCoding.lossyArray(CompetencyLevel.self, c, .levelDetails)
        weight = try? c.decodeIfPresent(Double.self, forKey: .weight)
        archivedAt = try? c.decodeIfPresent(Date.self, forKey: .archivedAt)
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        deletedAt = try? c.decodeIfPresent(Date.self, forKey: .deletedAt)
        extra = CompetencyCoding.readExtra(decoder, known: Self.knownKeys)
    }

    func encode(to encoder: Encoder) throws {
        try CompetencyCoding.writeExtra(extra, encoder, known: Self.knownKeys)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(groupId, forKey: .groupId)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(shortName, forKey: .shortName)
        try c.encodeIfPresent(order, forKey: .order)
        try c.encodeIfPresent(levelDetails, forKey: .levelDetails)
        try c.encodeIfPresent(weight, forKey: .weight)
        try c.encodeIfPresent(archivedAt, forKey: .archivedAt)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }
}

/// 照職等的目標（v1b 才有畫面；v1a 先宣告，別台寫的原樣保留）
struct CompetencyTarget: Codable, Equatable, Identifiable {
    var id: UUID
    var gradeTitleId: UUID?
    var gradeLabel: String?
    /// "trait"／"skill"
    var scope: String?
    var groupId: UUID?
    var itemId: UUID?
    var level: Int?
    var low: Int?
    var high: Int?
    var updatedAt: Date?
    var deletedAt: Date?
    var extra: [String: JSONValue]?

    var stamp: Date { updatedAt ?? deletedAt ?? Date.distantPast }
}

extension CompetencyTarget {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, gradeTitleId, gradeLabel, scope, groupId, itemId, level, low, high, updatedAt, deletedAt
    }
    static let knownKeys: Set<String> = Set(CodingKeys.allCases.map { $0.rawValue })

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        gradeTitleId = try? c.decodeIfPresent(UUID.self, forKey: .gradeTitleId)
        gradeLabel = try? c.decodeIfPresent(String.self, forKey: .gradeLabel)
        scope = try? c.decodeIfPresent(String.self, forKey: .scope)
        groupId = try? c.decodeIfPresent(UUID.self, forKey: .groupId)
        itemId = try? c.decodeIfPresent(UUID.self, forKey: .itemId)
        level = try? c.decodeIfPresent(Int.self, forKey: .level)
        low = try? c.decodeIfPresent(Int.self, forKey: .low)
        high = try? c.decodeIfPresent(Int.self, forKey: .high)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        deletedAt = try? c.decodeIfPresent(Date.self, forKey: .deletedAt)
        extra = CompetencyCoding.readExtra(decoder, known: Self.knownKeys)
    }

    func encode(to encoder: Encoder) throws {
        try CompetencyCoding.writeExtra(extra, encoder, known: Self.knownKeys)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(gradeTitleId, forKey: .gradeTitleId)
        try c.encodeIfPresent(gradeLabel, forKey: .gradeLabel)
        try c.encodeIfPresent(scope, forKey: .scope)
        try c.encodeIfPresent(groupId, forKey: .groupId)
        try c.encodeIfPresent(itemId, forKey: .itemId)
        try c.encodeIfPresent(level, forKey: .level)
        try c.encodeIfPresent(low, forKey: .low)
        try c.encodeIfPresent(high, forKey: .high)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }
}

/// 帶訓者（v5；先宣告）
struct CompetencyMentor: Codable, Equatable {
    var groupId: UUID?
    var mentorId: UUID?
    var mentorName: String?
    /// 開始學的日子「2026-05-04」
    var startKey: String?
    var extra: [String: JSONValue]?
}

extension CompetencyMentor {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case groupId, mentorId, mentorName, startKey
    }
    static let knownKeys: Set<String> = Set(CodingKeys.allCases.map { $0.rawValue })

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        groupId = try? c.decodeIfPresent(UUID.self, forKey: .groupId)
        mentorId = try? c.decodeIfPresent(UUID.self, forKey: .mentorId)
        mentorName = try? c.decodeIfPresent(String.self, forKey: .mentorName)
        startKey = try? c.decodeIfPresent(String.self, forKey: .startKey)
        extra = CompetencyCoding.readExtra(decoder, known: Self.knownKeys)
    }

    func encode(to encoder: Encoder) throws {
        try CompetencyCoding.writeExtra(extra, encoder, known: Self.knownKeys)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(groupId, forKey: .groupId)
        try c.encodeIfPresent(mentorId, forKey: .mentorId)
        try c.encodeIfPresent(mentorName, forKey: .mentorName)
        try c.encodeIfPresent(startKey, forKey: .startKey)
    }
}

/// 每位同仁一筆：不用學哪些系統。**id＝部屬 id**（一位只會有一筆，兩台各勾一次也不會長兩筆）。
/// 沒有這筆＝全部都要學（新加的系統大家預設要學）
struct CompetencyAssignment: Codable, Equatable, Identifiable {
    var id: UUID
    var skippedGroupIds: [UUID]?
    var mentors: [CompetencyMentor]?
    var updatedAt: Date?
    var deletedAt: Date?
    var extra: [String: JSONValue]?

    var stamp: Date { updatedAt ?? deletedAt ?? Date.distantPast }
}

extension CompetencyAssignment {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, skippedGroupIds, mentors, updatedAt, deletedAt
    }
    static let knownKeys: Set<String> = Set(CodingKeys.allCases.map { $0.rawValue })

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        skippedGroupIds = try? c.decodeIfPresent([UUID].self, forKey: .skippedGroupIds)
        mentors = CompetencyCoding.lossyArray(CompetencyMentor.self, c, .mentors)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        deletedAt = try? c.decodeIfPresent(Date.self, forKey: .deletedAt)
        extra = CompetencyCoding.readExtra(decoder, known: Self.knownKeys)
    }

    func encode(to encoder: Encoder) throws {
        try CompetencyCoding.writeExtra(extra, encoder, known: Self.knownKeys)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(skippedGroupIds, forKey: .skippedGroupIds)
        try c.encodeIfPresent(mentors, forKey: .mentors)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }
}

/// 職能項目設定那一包（同步鍵 life_competency_setup_v1；跟 iCloud 同步、進完整備份與「職涯」匯出）
struct CompetencySetupBook: Codable, Equatable {
    static let syncKey = "life_competency_setup_v1"
    /// 這一版認得的格式（比它新 → 唯讀）
    static let currentFormat = 1
    static let traitScaleId = "trait"
    static let skillScaleId = "skill"
    /// 人格特質那一組：不管走〔用範例開始〕還是〔自己設定〕都是這個代號（兩台合併後只有一組）
    static let traitGroupId = UUID(uuidString: "C0A1D000-0000-4000-8000-000000000001")!

    var formatVersion: Int?
    var scales: [CompetencyScale]?
    var groups: [CompetencyGroup]?
    var items: [CompetencyItem]?
    var targets: [CompetencyTarget]?
    var assignments: [CompetencyAssignment]?
    var extra: [String: JSONValue]?

    var allScales: [CompetencyScale] { scales ?? [] }
    var allGroups: [CompetencyGroup] { groups ?? [] }
    var allItems: [CompetencyItem] { items ?? [] }
    var allTargets: [CompetencyTarget] { targets ?? [] }
    var allAssignments: [CompetencyAssignment] { assignments ?? [] }

    var isEmpty: Bool {
        allScales.isEmpty && allGroups.isEmpty && allItems.isEmpty && allTargets.isEmpty && allAssignments.isEmpty
    }
    /// 別台的 App 比較新、改了格式：這台只看、不寫
    var isReadOnlyHere: Bool { (formatVersion ?? 1) > Self.currentFormat }
    /// 設好了沒（有人格特質項目或有系統）：沒有 → 〔職能〕分頁顯示〔用範例開始〕〔自己設定〕
    var isConfigured: Bool {
        allItems.contains { $0.isLive && !$0.isShared } || allGroups.contains { $0.isLive && !$0.isTrait }
    }

    // MARK: 查

    func scale(_ id: String) -> CompetencyScale? { allScales.first { $0.id == id } }
    /// 人格特質現在的範圍（沒有就 1–5）
    var traitRange: CompetencyRange { scale(Self.traitScaleId)?.range ?? CompetencyRange.standard }
    /// 本職學能現在的範圍（所有系統共用）
    var skillRange: CompetencyRange { scale(Self.skillScaleId)?.range ?? CompetencyRange.standard }
    func range(forGroup groupId: UUID) -> CompetencyRange {
        groupId == Self.traitGroupId ? traitRange : skillRange
    }
    func scaleFor(group groupId: UUID) -> CompetencyScale? {
        scale(groupId == Self.traitGroupId ? Self.traitScaleId : Self.skillScaleId)
    }

    func group(_ id: UUID) -> CompetencyGroup? { allGroups.first { $0.id == id } }
    func item(_ id: UUID) -> CompetencyItem? { allItems.first { $0.id == id } }

    /// 人格特質那一組（沒有墓碑才算）
    var traitGroup: CompetencyGroup? {
        guard let g = group(Self.traitGroupId), g.isLive else { return nil }
        return g
    }
    /// 啟用中的系統（照順序）
    var activeSystems: [CompetencyGroup] {
        Self.sortedGroups(allGroups.filter { $0.isActive && !$0.isTrait })
    }
    /// 已停用的系統（沒刪）
    var archivedSystems: [CompetencyGroup] {
        Self.sortedGroups(allGroups.filter { $0.isLive && $0.archivedAt != nil && !$0.isTrait })
    }
    /// 人格特質啟用中的項目（照順序）
    var traitItems: [CompetencyItem] {
        Self.sortedItems(allItems.filter { $0.isActive && $0.groupId == Self.traitGroupId })
    }
    /// 共用學習項目（啟用中，照順序）
    var sharedItems: [CompetencyItem] {
        Self.sortedItems(allItems.filter { $0.isActive && $0.isShared })
    }
    /// 某個系統自己的項目（啟用中，照順序）
    func ownItems(_ groupId: UUID) -> [CompetencyItem] {
        Self.sortedItems(allItems.filter { $0.isActive && $0.groupId == groupId })
    }
    /// 已停用的項目（沒刪）：人格的、共用的、系統自己的都在這
    var archivedItems: [CompetencyItem] {
        Self.sortedItems(allItems.filter { $0.isLive && $0.archivedAt != nil })
    }

    /// 這一組雷達的軸（judge §2.7 activeAxes）：人格＝人格項目；系統＝共用（扣掉這個系統拿掉的）照共用順序在前＋這個系統自己的接在後面
    func axes(for groupId: UUID) -> [CompetencyItem] {
        if groupId == Self.traitGroupId { return traitItems }
        let hidden = Set(group(groupId)?.hiddenSharedItemIds ?? [])
        let shared = sharedItems.filter { !hidden.contains($0.id) }
        return shared + ownItems(groupId)
    }

    /// 這位同仁不用學的系統
    func skippedGroupIds(_ subordinateId: UUID) -> Set<UUID> {
        guard let a = allAssignments.first(where: { $0.id == subordinateId }), a.deletedAt == nil else { return [] }
        return Set(a.skippedGroupIds ?? [])
    }

    /// 某個共用項目套用在幾個系統（設定頁「3 個系統」）
    func systemCount(usingShared itemId: UUID) -> Int {
        activeSystems.filter { !($0.hiddenSharedItemIds ?? []).contains(itemId) }.count
    }

    // MARK: 排序

    static func sortedItems(_ list: [CompetencyItem]) -> [CompetencyItem] {
        list.sorted { a, b in
            let oa: Double = a.order ?? Double.greatestFiniteMagnitude
            let ob: Double = b.order ?? Double.greatestFiniteMagnitude
            if oa != ob { return oa < ob }
            let ca: Date = a.createdAt ?? Date.distantPast
            let cb: Date = b.createdAt ?? Date.distantPast
            if ca != cb { return ca < cb }
            return a.id.uuidString < b.id.uuidString
        }
    }

    static func sortedGroups(_ list: [CompetencyGroup]) -> [CompetencyGroup] {
        list.sorted { a, b in
            let oa: Double = a.order ?? Double.greatestFiniteMagnitude
            let ob: Double = b.order ?? Double.greatestFiniteMagnitude
            if oa != ob { return oa < ob }
            let ca: Date = a.createdAt ?? Date.distantPast
            let cb: Date = b.createdAt ?? Date.distantPast
            if ca != cb { return ca < cb }
            return a.id.uuidString < b.id.uuidString
        }
    }

    // MARK: 改（呼叫端負責 LifeStore.batched）

    mutating func upsertScale(_ x: CompetencyScale) {
        var list = allScales
        if let i = list.firstIndex(where: { $0.id == x.id }) { list[i] = x } else { list.append(x) }
        scales = list
    }

    mutating func upsertGroup(_ x: CompetencyGroup) {
        var list = allGroups
        if let i = list.firstIndex(where: { $0.id == x.id }) { list[i] = x } else { list.append(x) }
        groups = list
    }

    mutating func upsertItem(_ x: CompetencyItem) {
        var list = allItems
        if let i = list.firstIndex(where: { $0.id == x.id }) { list[i] = x } else { list.append(x) }
        items = list
    }

    mutating func upsertAssignment(_ x: CompetencyAssignment) {
        var list = allAssignments
        if let i = list.firstIndex(where: { $0.id == x.id }) { list[i] = x } else { list.append(x) }
        assignments = list
    }

    /// 寫入時蓋上這一版的格式（不會把別台比較新的格式往下改：唯讀時呼叫端根本不寫）
    mutating func stampFormat() {
        formatVersion = max(formatVersion ?? Self.currentFormat, Self.currentFormat)
    }

    // MARK: 範例、自己設定

    /// 〔自己設定〕：只建人格特質那一組（固定代號）與兩份等級表（1–5、不帶名字）；已經有的不動
    func ensuringBasics(now: Date) -> CompetencySetupBook {
        var b = self
        if b.scale(Self.traitScaleId) == nil {
            b.upsertScale(CompetencyScale(id: Self.traitScaleId, low: 1, high: 5, levels: nil, updatedAt: now))
        }
        if b.scale(Self.skillScaleId) == nil {
            b.upsertScale(CompetencyScale(id: Self.skillScaleId, low: 1, high: 5, levels: nil, updatedAt: now))
        }
        if b.group(Self.traitGroupId) == nil {
            b.upsertGroup(CompetencyGroup(id: Self.traitGroupId, kind: CompetencyGroup.kindTrait, name: "人格特質",
                                          order: 0, createdAt: now, updatedAt: now))
        }
        b.stampFormat()
        return b
    }

    /// 〔用範例開始〕：人格特質「團隊合作、領導力、學習能力」（1–5）；共用學習項目「P&ID、緊急應變、值班技能」；
    /// 系統「Gas System、Slurry System、Chemical System」（本職 1–5）。全部固定代號；已經有的（同一個代號）一個都不動。
    /// §13：每一分不帶名字
    func addingSample(now: Date) -> CompetencySetupBook {
        var b = ensuringBasics(now: now)
        for g in CompetencySample.groups(now: now) where b.group(g.id) == nil {
            b.upsertGroup(g)
        }
        for it in CompetencySample.items(now: now) where b.item(it.id) == nil {
            b.upsertItem(it)
        }
        b.stampFormat()
        return b
    }

    // MARK: 合併

    /// 兩台合併（收到 iCloud 的更新、備份「合併」、第一次同步〔合併〕）：self＝收進來的那份（一樣新時留它），other＝另一份。
    /// 照 id 各取 updatedAt 新的；等級表照代號 "trait"／"skill"
    func merged(with other: CompetencySetupBook) -> CompetencySetupBook {
        var b = self
        let fa: Int = formatVersion ?? 0
        let fb: Int = other.formatVersion ?? 0
        let f: Int = max(fa, fb)
        b.formatVersion = f == 0 ? nil : f
        b.scales = CompetencyCoding.mergeList(scales, other.scales, key: { $0.id }, stamp: { $0.updatedAt ?? Date.distantPast })
        b.groups = CompetencyCoding.mergeList(groups, other.groups, key: { $0.id }, stamp: { $0.stamp })
        b.items = CompetencyCoding.mergeList(items, other.items, key: { $0.id }, stamp: { $0.stamp })
        b.targets = CompetencyCoding.mergeList(targets, other.targets, key: { $0.id }, stamp: { $0.stamp })
        b.assignments = CompetencyCoding.mergeList(assignments, other.assignments, key: { $0.id }, stamp: { $0.stamp })
        b.extra = CompetencyCoding.mergeExtra(extra, other.extra)
        return b
    }
}

extension CompetencySetupBook {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case formatVersion, scales, groups, items, targets, assignments
    }
    static let knownKeys: Set<String> = Set(CodingKeys.allCases.map { $0.rawValue })

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try? c.decodeIfPresent(Int.self, forKey: .formatVersion)
        scales = CompetencyCoding.lossyArray(CompetencyScale.self, c, .scales)
        groups = CompetencyCoding.lossyArray(CompetencyGroup.self, c, .groups)
        items = CompetencyCoding.lossyArray(CompetencyItem.self, c, .items)
        targets = CompetencyCoding.lossyArray(CompetencyTarget.self, c, .targets)
        assignments = CompetencyCoding.lossyArray(CompetencyAssignment.self, c, .assignments)
        extra = CompetencyCoding.readExtra(decoder, known: Self.knownKeys)
    }

    func encode(to encoder: Encoder) throws {
        try CompetencyCoding.writeExtra(extra, encoder, known: Self.knownKeys)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(formatVersion, forKey: .formatVersion)
        try c.encodeIfPresent(scales, forKey: .scales)
        try c.encodeIfPresent(groups, forKey: .groups)
        try c.encodeIfPresent(items, forKey: .items)
        try c.encodeIfPresent(targets, forKey: .targets)
        try c.encodeIfPresent(assignments, forKey: .assignments)
    }
}

/// 〔用範例開始〕的固定代號（兩台各按一次，合併後只有一份）
enum CompetencySample {
    static let gasId = UUID(uuidString: "C0A1D000-0000-4000-8000-000000000002")!
    static let slurryId = UUID(uuidString: "C0A1D000-0000-4000-8000-000000000003")!
    static let chemicalId = UUID(uuidString: "C0A1D000-0000-4000-8000-000000000004")!
    static let teamworkId = UUID(uuidString: "C0A1D000-0000-4000-8000-000000000101")!
    static let leadershipId = UUID(uuidString: "C0A1D000-0000-4000-8000-000000000102")!
    static let learningId = UUID(uuidString: "C0A1D000-0000-4000-8000-000000000103")!
    static let pidId = UUID(uuidString: "C0A1D000-0000-4000-8000-000000000201")!
    static let emergencyId = UUID(uuidString: "C0A1D000-0000-4000-8000-000000000202")!
    static let dutyId = UUID(uuidString: "C0A1D000-0000-4000-8000-000000000203")!

    static func groups(now: Date) -> [CompetencyGroup] {
        [
            CompetencyGroup(id: gasId, kind: CompetencyGroup.kindSystem, name: "Gas System", order: 1, createdAt: now, updatedAt: now),
            CompetencyGroup(id: slurryId, kind: CompetencyGroup.kindSystem, name: "Slurry System", order: 2, createdAt: now, updatedAt: now),
            CompetencyGroup(id: chemicalId, kind: CompetencyGroup.kindSystem, name: "Chemical System", order: 3, createdAt: now, updatedAt: now)
        ]
    }

    static func items(now: Date) -> [CompetencyItem] {
        let t = CompetencySetupBook.traitGroupId
        return [
            CompetencyItem(id: teamworkId, groupId: t, name: "團隊合作", order: 0, createdAt: now, updatedAt: now),
            CompetencyItem(id: leadershipId, groupId: t, name: "領導力", order: 1, createdAt: now, updatedAt: now),
            CompetencyItem(id: learningId, groupId: t, name: "學習能力", order: 2, createdAt: now, updatedAt: now),
            CompetencyItem(id: pidId, groupId: nil, name: "P&ID", order: 0, createdAt: now, updatedAt: now),
            CompetencyItem(id: emergencyId, groupId: nil, name: "緊急應變", order: 1, createdAt: now, updatedAt: now),
            CompetencyItem(id: dutyId, groupId: nil, name: "值班技能", order: 2, createdAt: now, updatedAt: now)
        ]
    }
}

// MARK: - 評分（life_competency_ratings_v1）

/// 一格的位置：哪一組 × 哪一項（人格特質也是一組，所以不用特例）
struct CompetencyCellKey: Hashable {
    let groupId: UUID
    let itemId: UUID
}

/// 一格分數
struct CompetencyScore: Codable, Equatable {
    var groupId: UUID
    var itemId: UUID
    /// 原始分數（照那一張的範圍）；不適用時 nil
    var value: Int?
    /// 不適用（跟「沒評」不同：沒評根本沒有這一格）
    var na: Bool?
    /// 一句評語（v1a-2 才有畫面；別台寫的原樣保留）
    var comment: String?
    /// 這句評語可以給對方看（v4）
    var showToPerson: Bool?
    /// 名字快照（停用、刪除之後舊紀錄還看得懂）
    var groupName: String?
    var itemName: String?
    /// 那一分當時的名字（§13：出廠沒有名字 → nil）
    var levelName: String?
    /// 這一格最後改的時間（同一張兩台各改不同格，逐格合併）
    var updatedAt: Date?
    /// 這一格被清掉的時間（比 updatedAt 新＝清掉了）
    var clearedAt: Date?
    /// 連到潛力性的紀錄當證據（v5）
    var evidenceRecordIds: [UUID]?
    var extra: [String: JSONValue]?

    var key: CompetencyCellKey { CompetencyCellKey(groupId: groupId, itemId: itemId) }
    var isNA: Bool { na == true }
    /// 清掉了（clearedAt 比 updatedAt 新或一樣）
    var isCleared: Bool {
        guard let c = clearedAt else { return false }
        return c >= (updatedAt ?? Date.distantPast)
    }
    /// 真的有評（有分數或不適用，而且沒被清掉）
    var isLive: Bool { !isCleared && (value != nil || isNA) }
    /// 逐格合併用的時間
    var stamp: Date { max(updatedAt ?? Date.distantPast, clearedAt ?? Date.distantPast) }
}

extension CompetencyScore {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case groupId, itemId, value, na, comment, showToPerson, groupName, itemName, levelName
        case updatedAt, clearedAt, evidenceRecordIds
    }
    static let knownKeys: Set<String> = Set(CodingKeys.allCases.map { $0.rawValue })

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        groupId = try c.decode(UUID.self, forKey: .groupId)
        itemId = try c.decode(UUID.self, forKey: .itemId)
        value = try? c.decodeIfPresent(Int.self, forKey: .value)
        na = try? c.decodeIfPresent(Bool.self, forKey: .na)
        comment = try? c.decodeIfPresent(String.self, forKey: .comment)
        showToPerson = try? c.decodeIfPresent(Bool.self, forKey: .showToPerson)
        groupName = try? c.decodeIfPresent(String.self, forKey: .groupName)
        itemName = try? c.decodeIfPresent(String.self, forKey: .itemName)
        levelName = try? c.decodeIfPresent(String.self, forKey: .levelName)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        clearedAt = try? c.decodeIfPresent(Date.self, forKey: .clearedAt)
        evidenceRecordIds = try? c.decodeIfPresent([UUID].self, forKey: .evidenceRecordIds)
        extra = CompetencyCoding.readExtra(decoder, known: Self.knownKeys)
    }

    func encode(to encoder: Encoder) throws {
        try CompetencyCoding.writeExtra(extra, encoder, known: Self.knownKeys)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(groupId, forKey: .groupId)
        try c.encode(itemId, forKey: .itemId)
        try c.encodeIfPresent(value, forKey: .value)
        try c.encodeIfPresent(na, forKey: .na)
        try c.encodeIfPresent(comment, forKey: .comment)
        try c.encodeIfPresent(showToPerson, forKey: .showToPerson)
        try c.encodeIfPresent(groupName, forKey: .groupName)
        try c.encodeIfPresent(itemName, forKey: .itemName)
        try c.encodeIfPresent(levelName, forKey: .levelName)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(clearedAt, forKey: .clearedAt)
        try c.encodeIfPresent(evidenceRecordIds, forKey: .evidenceRecordIds)
    }
}

/// 一次評分（一位同仁、一天一張；同一天再按〔評分〕打開的就是這一張）
struct CompetencySession: Codable, Equatable, Identifiable {
    var id: UUID
    var subordinateId: UUID
    /// 評分日「2026-10-30」（字串不存 Date：跨時區不會跑一天）
    var dayKey: String
    /// v1a 只有 "me"；"self"、"mentor" 先留
    var raterKind: String?
    var raterId: UUID?
    var raterName: String?
    /// 評分當時的職等快照
    var gradeTitleId: UUID?
    var gradeLabel: String?
    /// 評分當時的兩個範圍
    var traitLow: Int?
    var traitHigh: Int?
    var skillLow: Int?
    var skillHigh: Int?
    /// 這次評了的格子（沒評的不放、不存 0）
    var scores: [CompetencyScore]?
    /// 這次的總評（只有你看得到）
    var note: String?
    var createdAt: Date?
    var updatedAt: Date?
    var deletedAt: Date?
    var extra: [String: JSONValue]?

    static let raterMe = "me"

    var allScores: [CompetencyScore] { scores ?? [] }
    var liveScores: [CompetencyScore] { allScores.filter { $0.isLive } }
    var isLive: Bool { deletedAt == nil }
    var isByMe: Bool { raterKind == nil || raterKind == Self.raterMe }
    var traitRange: CompetencyRange { CompetencyRange.safe(low: traitLow, high: traitHigh) }
    var skillRange: CompetencyRange { CompetencyRange.safe(low: skillLow, high: skillHigh) }
    /// 這一張某一組用的範圍
    func range(forGroup groupId: UUID) -> CompetencyRange {
        groupId == CompetencySetupBook.traitGroupId ? traitRange : skillRange
    }
    func score(_ key: CompetencyCellKey) -> CompetencyScore? {
        allScores.first { $0.key == key }
    }
    var stamp: Date { updatedAt ?? deletedAt ?? createdAt ?? Date.distantPast }

    /// 同一張兩台各改：日期、總評、評分人照整張 updatedAt 取新的；每一格照（組, 項目）對齊、各比自己的時間（一樣新留 self）
    func merged(with other: CompetencySession) -> CompetencySession {
        var head: CompetencySession = other.stamp > stamp ? other : self
        if scores == nil && other.scores == nil {
            head.scores = nil
        } else {
            head.scores = CompetencyCoding.mergeList(scores, other.scores, key: { $0.key }, stamp: { $0.stamp })
        }
        head.extra = CompetencyCoding.mergeExtra(head.extra, other.stamp > stamp ? extra : other.extra)
        return head
    }
}

extension CompetencySession {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, subordinateId, dayKey, raterKind, raterId, raterName, gradeTitleId, gradeLabel
        case traitLow, traitHigh, skillLow, skillHigh, scores, note, createdAt, updatedAt, deletedAt
    }
    static let knownKeys: Set<String> = Set(CodingKeys.allCases.map { $0.rawValue })

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        subordinateId = try c.decode(UUID.self, forKey: .subordinateId)
        dayKey = try c.decode(String.self, forKey: .dayKey)
        raterKind = try? c.decodeIfPresent(String.self, forKey: .raterKind)
        raterId = try? c.decodeIfPresent(UUID.self, forKey: .raterId)
        raterName = try? c.decodeIfPresent(String.self, forKey: .raterName)
        gradeTitleId = try? c.decodeIfPresent(UUID.self, forKey: .gradeTitleId)
        gradeLabel = try? c.decodeIfPresent(String.self, forKey: .gradeLabel)
        traitLow = try? c.decodeIfPresent(Int.self, forKey: .traitLow)
        traitHigh = try? c.decodeIfPresent(Int.self, forKey: .traitHigh)
        skillLow = try? c.decodeIfPresent(Int.self, forKey: .skillLow)
        skillHigh = try? c.decodeIfPresent(Int.self, forKey: .skillHigh)
        scores = CompetencyCoding.lossyArray(CompetencyScore.self, c, .scores)
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        deletedAt = try? c.decodeIfPresent(Date.self, forKey: .deletedAt)
        extra = CompetencyCoding.readExtra(decoder, known: Self.knownKeys)
    }

    func encode(to encoder: Encoder) throws {
        try CompetencyCoding.writeExtra(extra, encoder, known: Self.knownKeys)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(subordinateId, forKey: .subordinateId)
        try c.encode(dayKey, forKey: .dayKey)
        try c.encodeIfPresent(raterKind, forKey: .raterKind)
        try c.encodeIfPresent(raterId, forKey: .raterId)
        try c.encodeIfPresent(raterName, forKey: .raterName)
        try c.encodeIfPresent(gradeTitleId, forKey: .gradeTitleId)
        try c.encodeIfPresent(gradeLabel, forKey: .gradeLabel)
        try c.encodeIfPresent(traitLow, forKey: .traitLow)
        try c.encodeIfPresent(traitHigh, forKey: .traitHigh)
        try c.encodeIfPresent(skillLow, forKey: .skillLow)
        try c.encodeIfPresent(skillHigh, forKey: .skillHigh)
        try c.encodeIfPresent(scores, forKey: .scores)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }
}

/// 升職當時凍結的一份（v5；先宣告）
struct CompetencyMilestone: Codable, Equatable, Identifiable {
    var id: UUID
    var subordinateId: UUID?
    var kind: String?
    var dayKey: String?
    var promotionRecordId: UUID?
    var gradeLabel: String?
    var frozen: [CompetencyScore]?
    var traitLow: Int?
    var traitHigh: Int?
    var skillLow: Int?
    var skillHigh: Int?
    var createdAt: Date?
    var updatedAt: Date?
    var deletedAt: Date?
    var extra: [String: JSONValue]?

    var stamp: Date { updatedAt ?? deletedAt ?? createdAt ?? Date.distantPast }
}

extension CompetencyMilestone {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, subordinateId, kind, dayKey, promotionRecordId, gradeLabel, frozen
        case traitLow, traitHigh, skillLow, skillHigh, createdAt, updatedAt, deletedAt
    }
    static let knownKeys: Set<String> = Set(CodingKeys.allCases.map { $0.rawValue })

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        subordinateId = try? c.decodeIfPresent(UUID.self, forKey: .subordinateId)
        kind = try? c.decodeIfPresent(String.self, forKey: .kind)
        dayKey = try? c.decodeIfPresent(String.self, forKey: .dayKey)
        promotionRecordId = try? c.decodeIfPresent(UUID.self, forKey: .promotionRecordId)
        gradeLabel = try? c.decodeIfPresent(String.self, forKey: .gradeLabel)
        frozen = CompetencyCoding.lossyArray(CompetencyScore.self, c, .frozen)
        traitLow = try? c.decodeIfPresent(Int.self, forKey: .traitLow)
        traitHigh = try? c.decodeIfPresent(Int.self, forKey: .traitHigh)
        skillLow = try? c.decodeIfPresent(Int.self, forKey: .skillLow)
        skillHigh = try? c.decodeIfPresent(Int.self, forKey: .skillHigh)
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        deletedAt = try? c.decodeIfPresent(Date.self, forKey: .deletedAt)
        extra = CompetencyCoding.readExtra(decoder, known: Self.knownKeys)
    }

    func encode(to encoder: Encoder) throws {
        try CompetencyCoding.writeExtra(extra, encoder, known: Self.knownKeys)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(subordinateId, forKey: .subordinateId)
        try c.encodeIfPresent(kind, forKey: .kind)
        try c.encodeIfPresent(dayKey, forKey: .dayKey)
        try c.encodeIfPresent(promotionRecordId, forKey: .promotionRecordId)
        try c.encodeIfPresent(gradeLabel, forKey: .gradeLabel)
        try c.encodeIfPresent(frozen, forKey: .frozen)
        try c.encodeIfPresent(traitLow, forKey: .traitLow)
        try c.encodeIfPresent(traitHigh, forKey: .traitHigh)
        try c.encodeIfPresent(skillLow, forKey: .skillLow)
        try c.encodeIfPresent(skillHigh, forKey: .skillHigh)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }
}

/// 評分那一包（同步鍵 life_competency_ratings_v1；跟 iCloud 同步、進完整備份與「職涯」匯出）
struct CompetencyRatingBook: Codable, Equatable {
    static let syncKey = "life_competency_ratings_v1"
    static let currentFormat = 1

    var formatVersion: Int?
    var sessions: [CompetencySession]?
    var milestones: [CompetencyMilestone]?
    var extra: [String: JSONValue]?

    var allSessions: [CompetencySession] { sessions ?? [] }
    var allMilestones: [CompetencyMilestone] { milestones ?? [] }
    var isEmpty: Bool { allSessions.isEmpty && allMilestones.isEmpty }
    var isReadOnlyHere: Bool { (formatVersion ?? 1) > Self.currentFormat }

    func session(_ id: UUID) -> CompetencySession? { allSessions.first { $0.id == id } }

    /// 這位同仁我評的、沒刪的（照日子、再照最後改的時間排）
    func liveSessions(of subordinateId: UUID) -> [CompetencySession] {
        let list = allSessions.filter { $0.subordinateId == subordinateId && $0.isLive && $0.isByMe }
        return CompetencyRatingBook.sortedSessions(list)
    }

    /// 刪除確認框「職能評分 2 次會先留著」用
    func liveSessionCount(of subordinateId: UUID) -> Int {
        allSessions.filter { $0.subordinateId == subordinateId && $0.isLive && $0.isByMe }.count
    }

    static func sortedSessions(_ list: [CompetencySession]) -> [CompetencySession] {
        list.sorted { a, b in
            if a.dayKey != b.dayKey { return a.dayKey < b.dayKey }
            return a.stamp < b.stamp
        }
    }

    mutating func upsertSession(_ x: CompetencySession) {
        var list = allSessions
        if let i = list.firstIndex(where: { $0.id == x.id }) { list[i] = x } else { list.append(x) }
        sessions = list
    }

    mutating func stampFormat() {
        formatVersion = max(formatVersion ?? Self.currentFormat, Self.currentFormat)
    }

    /// 兩台合併：self＝收進來的那份（一樣新時留它）。同一張逐格合併（CompetencySession.merged）
    func merged(with other: CompetencyRatingBook) -> CompetencyRatingBook {
        var b = self
        let fa: Int = formatVersion ?? 0
        let fb: Int = other.formatVersion ?? 0
        let f: Int = max(fa, fb)
        b.formatVersion = f == 0 ? nil : f
        if sessions == nil && other.sessions == nil {
            b.sessions = nil
        } else {
            var out: [CompetencySession] = sessions ?? []
            var index: [UUID: Int] = [:]
            for (i, s) in out.enumerated() { index[s.id] = i }
            for o in other.sessions ?? [] {
                if let i = index[o.id] {
                    out[i] = out[i].merged(with: o)
                } else {
                    index[o.id] = out.count
                    out.append(o)
                }
            }
            b.sessions = out
        }
        b.milestones = CompetencyCoding.mergeList(milestones, other.milestones, key: { $0.id }, stamp: { $0.stamp })
        b.extra = CompetencyCoding.mergeExtra(extra, other.extra)
        return b
    }
}

extension CompetencyRatingBook {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case formatVersion, sessions, milestones
    }
    static let knownKeys: Set<String> = Set(CodingKeys.allCases.map { $0.rawValue })

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try? c.decodeIfPresent(Int.self, forKey: .formatVersion)
        sessions = CompetencyCoding.lossyArray(CompetencySession.self, c, .sessions)
        milestones = CompetencyCoding.lossyArray(CompetencyMilestone.self, c, .milestones)
        extra = CompetencyCoding.readExtra(decoder, known: Self.knownKeys)
    }

    func encode(to encoder: Encoder) throws {
        try CompetencyCoding.writeExtra(extra, encoder, known: Self.knownKeys)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(formatVersion, forKey: .formatVersion)
        try c.encodeIfPresent(sessions, forKey: .sessions)
        try c.encodeIfPresent(milestones, forKey: .milestones)
    }
}

// MARK: - 只在記憶體的查表（judge §2.7；照 OrgReorgIndex：兩個 book 的 didSet 重建一次，畫面查表、不在 body 裡掃全部評分）

enum CompetencyIndex {
    /// 部屬 id → 我評的、沒刪的評分（照日子排）
    static var sessionsBySub: [UUID: [CompetencySession]] = [:]

    static func rebuild(_ book: CompetencyRatingBook) {
        var out: [UUID: [CompetencySession]] = [:]
        for s in book.allSessions where s.isLive && s.isByMe {
            out[s.subordinateId, default: []].append(s)
        }
        for k in Array(out.keys) {
            out[k] = CompetencyRatingBook.sortedSessions(out[k] ?? [])
        }
        sessionsBySub = out
    }

    static func sessions(of subordinateId: UUID) -> [CompetencySession] {
        sessionsBySub[subordinateId] ?? []
    }
}

// MARK: - 第一次打開 iCloud 同步選〔合併〕（judge §2.4 第 7 處）

/// CloudSyncManager.resolveInitialSync 的 mergeBlob 只會逐筆合併「最上層是陣列」的鍵；這兩個鍵最上層是物件 →
/// 解成 Book → merged(with:)（localWins 只決定「一樣新時」留哪邊）→ 編回去。解不開、或有一邊格式比這台新 → 回 nil（呼叫端退回原本的 mergeBlob）
enum CompetencySync {
    static func handles(_ key: String) -> Bool {
        key == CompetencySetupBook.syncKey || key == CompetencyRatingBook.syncKey
    }

    static func mergeInitialBlob(key: String, local: Data?, cloud: Data?, localWins: Bool) -> Data? {
        guard let l = local, let c = cloud else { return nil }
        let dec = JSONDecoder()
        let enc = JSONEncoder()
        if key == CompetencySetupBook.syncKey {
            guard let lb = try? dec.decode(CompetencySetupBook.self, from: l),
                  let cb = try? dec.decode(CompetencySetupBook.self, from: c),
                  !lb.isReadOnlyHere, !cb.isReadOnlyHere else { return nil }
            let merged: CompetencySetupBook = localWins ? lb.merged(with: cb) : cb.merged(with: lb)
            return try? enc.encode(merged)
        }
        if key == CompetencyRatingBook.syncKey {
            guard let lb = try? dec.decode(CompetencyRatingBook.self, from: l),
                  let cb = try? dec.decode(CompetencyRatingBook.self, from: c),
                  !lb.isReadOnlyHere, !cb.isReadOnlyHere else { return nil }
            let merged: CompetencyRatingBook = localWins ? lb.merged(with: cb) : cb.merged(with: lb)
            return try? enc.encode(merged)
        }
        return nil
    }
}
