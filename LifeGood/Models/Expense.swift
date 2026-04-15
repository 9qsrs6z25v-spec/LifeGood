import Foundation

// MARK: - 支出類型
enum ExpenseType: String, Codable, CaseIterable {
    case variable = "變動支出"
    case fixed = "固定支出"
}

// MARK: - 變動支出分類
enum VariableCategory: String, Codable, CaseIterable, Identifiable {
    case food = "飲食"
    case transportation = "交通"
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
        case .entertainment: return "gamecontroller.fill"
        case .shopping: return "bag.fill"
        case .dailyNecessities: return "house.fill"
        case .medical: return "cross.case.fill"
        case .education: return "book.fill"
        case .social: return "person.2.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .food: return "FoodColor"
        case .transportation: return "TransportColor"
        case .entertainment: return "EntertainmentColor"
        case .shopping: return "ShoppingColor"
        case .dailyNecessities: return "DailyColor"
        case .medical: return "MedicalColor"
        case .education: return "EducationColor"
        case .social: return "SocialColor"
        case .other: return "OtherColor"
        }
    }
}

// MARK: - 固定支出分類
enum FixedCategory: String, Codable, CaseIterable, Identifiable {
    case rent = "房租"
    case utilities = "水電瓦斯"
    case insurance = "保險"
    case subscription = "訂閱服務"
    case loan = "貸款"
    case telecom = "電信費"
    case management = "管理費"
    case other = "其他"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .rent: return "building.2.fill"
        case .utilities: return "bolt.fill"
        case .insurance: return "shield.fill"
        case .subscription: return "creditcard.fill"
        case .loan: return "banknote.fill"
        case .telecom: return "phone.fill"
        case .management: return "wrench.and.screwdriver.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

// MARK: - 週期
enum Recurrence: String, Codable, CaseIterable {
    case monthly = "每月"
    case quarterly = "每季"
    case yearly = "每年"
}

// MARK: - 保險子分類
enum InsuranceSubCategory: String, Codable, CaseIterable, Identifiable {
    case savings = "儲蓄險"
    case life = "壽險"
    case accident = "意外險"
    case compulsory = "強制險"
    case comprehensive = "綜合險"

    var id: String { rawValue }
}

// MARK: - 貸款子分類
enum LoanSubCategory: String, Codable, CaseIterable, Identifiable {
    case car = "車貸"
    case mortgage = "房貸"
    case personal = "信貸"

    var id: String { rawValue }
}

// MARK: - 支出資料模型
struct Expense: Identifiable, Codable {
    let id: UUID
    var title: String
    var amount: Double
    var date: Date
    var expenseType: ExpenseType
    var variableCategory: VariableCategory?
    var fixedCategory: FixedCategory?
    var recurrence: Recurrence?
    var insuranceSubCategory: InsuranceSubCategory?
    var loanSubCategory: LoanSubCategory?
    var linkedInsuranceId: UUID?      // 連結理財模式的儲蓄險 ID
    var linkedRealEstateId: UUID?     // 連結理財模式的房地產 ID
    var note: String

    init(
        id: UUID = UUID(),
        title: String,
        amount: Double,
        date: Date = Date(),
        expenseType: ExpenseType,
        variableCategory: VariableCategory? = nil,
        fixedCategory: FixedCategory? = nil,
        recurrence: Recurrence? = nil,
        insuranceSubCategory: InsuranceSubCategory? = nil,
        loanSubCategory: LoanSubCategory? = nil,
        linkedInsuranceId: UUID? = nil,
        linkedRealEstateId: UUID? = nil,
        note: String = ""
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.date = date
        self.expenseType = expenseType
        self.variableCategory = variableCategory
        self.fixedCategory = fixedCategory
        self.recurrence = recurrence
        self.insuranceSubCategory = insuranceSubCategory
        self.loanSubCategory = loanSubCategory
        self.linkedInsuranceId = linkedInsuranceId
        self.linkedRealEstateId = linkedRealEstateId
        self.note = note
    }

    var categoryName: String {
        switch expenseType {
        case .variable:
            return variableCategory?.rawValue ?? "未分類"
        case .fixed:
            if fixedCategory == .insurance, let sub = insuranceSubCategory {
                return "保險 - \(sub.rawValue)"
            }
            if fixedCategory == .loan, let sub = loanSubCategory {
                return "貸款 - \(sub.rawValue)"
            }
            return fixedCategory?.rawValue ?? "未分類"
        }
    }

    var categoryIcon: String {
        switch expenseType {
        case .variable:
            return variableCategory?.icon ?? "questionmark.circle"
        case .fixed:
            return fixedCategory?.icon ?? "questionmark.circle"
        }
    }
}

// MARK: - 圖表資料點
struct ChartDataPoint: Identifiable {
    let id = UUID()
    let label: String
    let amount: Double
    let date: Date
}

// MARK: - 時間區間
enum TimePeriod: String, CaseIterable {
    case daily = "日"
    case weekly = "週"
    case monthly = "月"
    case quarterly = "季"
    case yearly = "年"
}
