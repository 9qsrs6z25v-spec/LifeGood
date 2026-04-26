import Foundation

// MARK: - 支出類型
enum ExpenseType: String, Codable, CaseIterable {
    case variable = "變動支出"
    case fixed = "固定支出"
}

// MARK: - 變動支出分類
enum VariableCategory: String, Codable, Identifiable {
    case food = "飲食"
    case transportation = "交通"
    case vehicle = "汽車"
    case stock = "股票"
    case realEstate = "房地產"
    case entertainment = "娛樂"
    case shopping = "購物"
    case dailyNecessities = "日用品"
    case medical = "醫療"
    case education = "教育"
    case social = "社交"
    case other = "其他"

    var id: String { rawValue }

    static var allCases: [VariableCategory] {
        [.food, .vehicle, .stock, .realEstate, .entertainment, .shopping, .dailyNecessities, .medical, .education, .social, .other]
    }

    var icon: String {
        switch self {
        case .food: return "fork.knife"
        case .transportation: return "car.fill"
        case .vehicle: return "car.circle.fill"
        case .stock: return "chart.line.uptrend.xyaxis"
        case .realEstate: return "building.2.fill"
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
        case .vehicle: return "VehicleColor"
        case .stock: return "StockColor"
        case .realEstate: return "RealEstateColor"
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
    var linkedStockId: UUID?          // 連結理財模式的股票 ID
    var linkedRealEstateId: UUID?     // 連結理財模式的房地產 ID
    var linkedVehicleId: UUID?        // 連結理財模式的汽車 ID
    var vehicleExpenseCategory: VehicleVariableCategory?  // 汽車變動支出子分類
    var realEstateExpenseCategory: RealEstateExpenseCategory?  // 房地產變動支出子分類
    var note: String
    var currencyCode: String
    var diningMember: String?
    var loanTotalAmount: Double?
    var loanYears: Double?
    var loanRate: Double?
    var linkedBankMilestoneId: UUID?
    var linkedBankCurrency: String?
    var linkedCreditCardMilestoneId: UUID?
    /// 最後修改時間 — 用於 iCloud 多裝置（含 Apple Watch）同步衝突解決
    var updatedAt: Date
    /// 來源裝置標記（"iphone" / "watch"），用於衝突 UI 顯示
    var sourceDevice: String?

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
        linkedStockId: UUID? = nil,
        linkedRealEstateId: UUID? = nil,
        linkedVehicleId: UUID? = nil,
        vehicleExpenseCategory: VehicleVariableCategory? = nil,
        realEstateExpenseCategory: RealEstateExpenseCategory? = nil,
        note: String = "",
        currencyCode: String = "NT$",
        diningMember: String? = nil,
        loanTotalAmount: Double? = nil,
        loanYears: Double? = nil,
        loanRate: Double? = nil,
        linkedBankMilestoneId: UUID? = nil,
        linkedBankCurrency: String? = nil,
        linkedCreditCardMilestoneId: UUID? = nil,
        updatedAt: Date = Date(),
        sourceDevice: String? = nil
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
        self.linkedStockId = linkedStockId
        self.linkedRealEstateId = linkedRealEstateId
        self.linkedVehicleId = linkedVehicleId
        self.vehicleExpenseCategory = vehicleExpenseCategory
        self.realEstateExpenseCategory = realEstateExpenseCategory
        self.note = note
        self.currencyCode = currencyCode
        self.diningMember = diningMember
        self.loanTotalAmount = loanTotalAmount
        self.loanYears = loanYears
        self.loanRate = loanRate
        self.linkedBankMilestoneId = linkedBankMilestoneId
        self.linkedBankCurrency = linkedBankCurrency
        self.linkedCreditCardMilestoneId = linkedCreditCardMilestoneId
        self.updatedAt = updatedAt
        self.sourceDevice = sourceDevice
    }

    // MARK: - 向下相容解碼
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        amount = try c.decode(Double.self, forKey: .amount)
        date = try c.decode(Date.self, forKey: .date)
        expenseType = try c.decode(ExpenseType.self, forKey: .expenseType)
        variableCategory = try? c.decode(VariableCategory.self, forKey: .variableCategory)
        fixedCategory = try? c.decode(FixedCategory.self, forKey: .fixedCategory)
        recurrence = try? c.decode(Recurrence.self, forKey: .recurrence)
        insuranceSubCategory = try? c.decode(InsuranceSubCategory.self, forKey: .insuranceSubCategory)
        loanSubCategory = try? c.decode(LoanSubCategory.self, forKey: .loanSubCategory)
        linkedInsuranceId = try? c.decode(UUID.self, forKey: .linkedInsuranceId)
        linkedStockId = try? c.decode(UUID.self, forKey: .linkedStockId)
        linkedRealEstateId = try? c.decode(UUID.self, forKey: .linkedRealEstateId)
        linkedVehicleId = try? c.decode(UUID.self, forKey: .linkedVehicleId)
        vehicleExpenseCategory = try? c.decode(VehicleVariableCategory.self, forKey: .vehicleExpenseCategory)
        realEstateExpenseCategory = try? c.decode(RealEstateExpenseCategory.self, forKey: .realEstateExpenseCategory)
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        currencyCode = (try? c.decode(String.self, forKey: .currencyCode)) ?? "NT$"
        diningMember = try? c.decode(String.self, forKey: .diningMember)
        loanTotalAmount = try? c.decode(Double.self, forKey: .loanTotalAmount)
        loanYears = try? c.decode(Double.self, forKey: .loanYears)
        loanRate = try? c.decode(Double.self, forKey: .loanRate)
        linkedBankMilestoneId = try? c.decode(UUID.self, forKey: .linkedBankMilestoneId)
        linkedBankCurrency = try? c.decode(String.self, forKey: .linkedBankCurrency)
        linkedCreditCardMilestoneId = try? c.decodeIfPresent(UUID.self, forKey: .linkedCreditCardMilestoneId)
        // 向下相容：舊資料無 updatedAt 時，回退使用 date 作為時間戳
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? (try? c.decode(Date.self, forKey: .date)) ?? Date()
        sourceDevice = try? c.decodeIfPresent(String.self, forKey: .sourceDevice)
    }
    private enum CodingKeys: String, CodingKey {
        case id, title, amount, date, expenseType, variableCategory, fixedCategory, recurrence
        case insuranceSubCategory, loanSubCategory
        case linkedInsuranceId, linkedStockId, linkedRealEstateId, linkedVehicleId
        case vehicleExpenseCategory, realEstateExpenseCategory, note, currencyCode, diningMember
        case loanTotalAmount, loanYears, loanRate
        case linkedBankMilestoneId, linkedBankCurrency, linkedCreditCardMilestoneId
        case updatedAt, sourceDevice
    }

    var categoryName: String {
        switch expenseType {
        case .variable:
            if variableCategory == .vehicle, let sub = vehicleExpenseCategory {
                return "汽車 - \(sub.rawValue)"
            }
            if linkedRealEstateId != nil, let sub = realEstateExpenseCategory {
                return "房地產 - \(sub.rawValue)"
            }
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
