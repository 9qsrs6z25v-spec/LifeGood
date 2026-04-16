import Foundation

// MARK: - 收入分類

enum IncomeCategory: String, Codable, CaseIterable, Identifiable {
    case salary = "薪水"
    case bonus = "獎金"
    case gift = "禮金"
    case luck = "確幸"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .salary: return "briefcase.fill"
        case .bonus: return "star.fill"
        case .gift: return "gift.fill"
        case .luck: return "clover.fill"
        }
    }

    var color: String {
        switch self {
        case .salary: return "SalaryColor"
        case .bonus: return "BonusColor"
        case .gift: return "GiftColor"
        case .luck: return "LuckColor"
        }
    }
}

// MARK: - 收入週期

enum IncomePeriod: String, Codable, CaseIterable, Identifiable {
    case once = "單次"
    case monthly = "每月"
    case yearly = "每年"

    var id: String { rawValue }
}

// MARK: - 收入資料模型

struct Income: Identifiable, Codable {
    let id: UUID
    var title: String
    var amount: Double
    var date: Date
    var category: IncomeCategory
    var period: IncomePeriod
    var isFixedSalary: Bool     // 薪水類別專用：是否為固定薪水（每月重複計算）
    var note: String

    init(
        id: UUID = UUID(),
        title: String,
        amount: Double,
        date: Date = Date(),
        category: IncomeCategory = .salary,
        period: IncomePeriod = .monthly,
        isFixedSalary: Bool = false,
        note: String = ""
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.date = date
        self.category = category
        self.period = period
        self.isFixedSalary = isFixedSalary
        self.note = note
    }

    /// 換算月收入
    var monthlyAmount: Double {
        if category == .salary && !isFixedSalary {
            return 0  // 非固定薪水不重複計算
        }
        switch period {
        case .once: return 0
        case .monthly: return amount
        case .yearly: return amount / 12
        }
    }

    /// 薪水月份代碼（如 2026年4月 → M604）
    static func salaryCode(for date: Date) -> String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return String(format: "M%d%02d", year % 10, month)
    }
}
