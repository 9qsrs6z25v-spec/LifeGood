import Foundation

/// 手錶端使用的精簡支出模型。
///
/// 重要：CodingKeys 必須與 iPhone 端 `Expense` 完全一致，
/// 才能讓 iPhone 透過原本的 `Expense.init(from:)` 解碼出完整 Expense（缺漏欄位以可選或預設處理）。
struct WatchExpense: Codable, Identifiable {
    let id: UUID
    var title: String
    var amount: Double
    var date: Date
    var expenseType: String          // "變動支出" / "固定支出"
    var variableCategory: String?    // 例：飲食、交通、娛樂…
    var note: String
    var currencyCode: String
    var updatedAt: Date
    var sourceDevice: String         // 固定為 "watch"

    init(amount: Double,
         category: WatchVariableCategory,
         title: String? = nil,
         note: String = "",
         currencyCode: String = "NT$",
         date: Date = Date()) {
        self.id = UUID()
        self.amount = amount
        self.title = title?.isEmpty == false ? title! : category.rawValue
        self.date = date
        self.expenseType = "變動支出"
        self.variableCategory = category.rawValue
        self.note = note
        self.currencyCode = currencyCode
        self.updatedAt = Date()
        self.sourceDevice = "watch"
    }

    /// 由 cloud 傳回的 raw expense 解碼用 — 容忍欄位缺漏
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        amount = (try? c.decode(Double.self, forKey: .amount)) ?? 0
        date = (try? c.decode(Date.self, forKey: .date)) ?? Date()
        expenseType = (try? c.decode(String.self, forKey: .expenseType)) ?? "變動支出"
        variableCategory = try? c.decodeIfPresent(String.self, forKey: .variableCategory)
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        currencyCode = (try? c.decode(String.self, forKey: .currencyCode)) ?? "NT$"
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? date
        sourceDevice = (try? c.decodeIfPresent(String.self, forKey: .sourceDevice)) ?? "unknown"
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, amount, date, expenseType, variableCategory
        case note, currencyCode, updatedAt, sourceDevice
    }
}

/// 手錶端使用的變動支出分類（rawValue 與 iPhone 端 `VariableCategory` 一致）
enum WatchVariableCategory: String, CaseIterable, Identifiable {
    case food = "飲食"
    case transportation = "交通"
    case vehicle = "汽車"
    case entertainment = "娛樂"
    case shopping = "購物"
    case dailyNecessities = "日用品"
    case medical = "醫療"
    case education = "教育"
    case social = "社交"
    case other = "其他"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .food: return "fork.knife"
        case .transportation: return "car.fill"
        case .vehicle: return "car.circle.fill"
        case .entertainment: return "gamecontroller.fill"
        case .shopping: return "bag.fill"
        case .dailyNecessities: return "house.fill"
        case .medical: return "cross.case.fill"
        case .education: return "book.fill"
        case .social: return "person.2.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}
