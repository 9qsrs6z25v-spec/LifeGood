import Foundation

// MARK: - 收入分類

enum IncomeCategory: String, Codable, CaseIterable, Identifiable {
    case salary = "薪水"
    case bonus = "獎金"
    case gift = "禮金"
    case luck = "確幸"
    case investment = "投資"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .salary: return "briefcase.fill"
        case .bonus: return "star.fill"
        case .gift: return "gift.fill"
        case .luck: return "sparkles"
        case .investment: return "chart.line.uptrend.xyaxis"
        }
    }

    var color: String {
        switch self {
        case .salary: return "SalaryColor"
        case .bonus: return "BonusColor"
        case .gift: return "GiftColor"
        case .luck: return "LuckColor"
        case .investment: return "InvestmentColor"
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

// MARK: - 固定薪水結束原因

/// 固定薪水（每月自動計入）設有結束日時，可標註結束原因；純標示用途，不影響計算。
enum SalaryEndReason: String, Codable, CaseIterable, Identifiable {
    case resigned = "離職"
    case jobChange = "換工作"
    case maternity = "產假"
    case parentalLeave = "育嬰留停"
    case retired = "退休"
    case layoff = "資遣"
    case other = "其他"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .resigned: return "figure.walk"
        case .jobChange: return "arrow.left.arrow.right"
        case .maternity: return "figure.and.child.holdinghands"
        case .parentalLeave: return "stroller"
        case .retired: return "sunset.fill"
        case .layoff: return "person.fill.xmark"
        case .other: return "ellipsis.circle"
        }
    }
}

// MARK: - 收入資料模型

struct Income: Identifiable, Codable {
    let id: UUID
    var title: String
    var amount: Double
    var date: Date
    var category: IncomeCategory
    var period: IncomePeriod
    var isFixedSalary: Bool
    var note: String
    var linkedStockId: UUID?
    var linkedBankMilestoneId: UUID?
    var linkedBankCurrency: String?
    /// 固定薪水結束日（換工作/離職/產假等）。nil = 持續計入。
    var endDate: Date?
    /// 固定薪水結束原因（僅標示用途）。
    var endReason: SalaryEndReason?

    init(
        id: UUID = UUID(),
        title: String,
        amount: Double,
        date: Date = Date(),
        category: IncomeCategory = .salary,
        period: IncomePeriod = .monthly,
        isFixedSalary: Bool = false,
        note: String = "",
        linkedStockId: UUID? = nil,
        linkedBankMilestoneId: UUID? = nil,
        linkedBankCurrency: String? = nil,
        endDate: Date? = nil,
        endReason: SalaryEndReason? = nil
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.date = date
        self.category = category
        self.period = period
        self.isFixedSalary = isFixedSalary
        self.note = note
        self.linkedStockId = linkedStockId
        self.linkedBankMilestoneId = linkedBankMilestoneId
        self.linkedBankCurrency = linkedBankCurrency
        self.endDate = endDate
        self.endReason = endReason
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        amount = try c.decode(Double.self, forKey: .amount)
        date = try c.decode(Date.self, forKey: .date)
        category = (try? c.decode(IncomeCategory.self, forKey: .category)) ?? .salary
        period = (try? c.decode(IncomePeriod.self, forKey: .period)) ?? .monthly
        isFixedSalary = (try? c.decode(Bool.self, forKey: .isFixedSalary)) ?? false
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        linkedStockId = try? c.decodeIfPresent(UUID.self, forKey: .linkedStockId)
        linkedBankMilestoneId = try? c.decodeIfPresent(UUID.self, forKey: .linkedBankMilestoneId)
        linkedBankCurrency = try? c.decodeIfPresent(String.self, forKey: .linkedBankCurrency)
        endDate = try? c.decodeIfPresent(Date.self, forKey: .endDate)
        endReason = try? c.decodeIfPresent(SalaryEndReason.self, forKey: .endReason)
    }
    private enum CodingKeys: String, CodingKey {
        case id, title, amount, date, category, period, isFixedSalary, note, linkedStockId, linkedBankMilestoneId, linkedBankCurrency, endDate, endReason
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

    /// 週期性收入（固定薪水）在指定月份是否仍計入。
    /// 未設結束日 → 一律計入；設了結束日 → 結束日所在月份（含）之前計入，之後不計入
    /// （多數情況離職當月仍領到最後一份薪水，故結束月採「含」）。
    func isActive(in month: Date, calendar: Calendar = .current) -> Bool {
        guard let endDate else { return true }
        let target = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let end = calendar.date(from: calendar.dateComponents([.year, .month], from: endDate)) ?? endDate
        return target <= end
    }

    /// 薪水月份代碼（如 2026年4月 → M604）
    static func salaryCode(for date: Date) -> String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return String(format: "M%d%02d", year % 10, month)
    }
}
