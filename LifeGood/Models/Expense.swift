import Foundation
import SwiftUI

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
    case tax = "稅費"
    case taxSaving = "節稅"
    case entertainment = "娛樂"
    case shopping = "購物"
    case dailyNecessities = "日用品"
    case medical = "醫療"
    case education = "教育"
    case social = "社交"
    case other = "其他"

    var id: String { rawValue }

    static var allCases: [VariableCategory] {
        [.food, .vehicle, .stock, .realEstate, .tax, .taxSaving, .entertainment, .shopping, .dailyNecessities, .medical, .education, .social, .other]
    }

    var icon: String {
        switch self {
        case .food: return "fork.knife"
        case .transportation: return "car.fill"
        case .vehicle: return "car.circle.fill"
        case .stock: return "chart.line.uptrend.xyaxis"
        case .realEstate: return "building.2.fill"
        case .tax: return "doc.text.fill"
        case .taxSaving: return "lightbulb.fill"
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
        case .tax: return "OtherColor"
        case .taxSaving: return "OtherColor"
        case .other: return "OtherColor"
        }
    }

    var accentColor: Color {
        switch self {
        case .food:             return Color(red: 1.00, green: 0.58, blue: 0.22)
        case .transportation:   return Color(red: 0.27, green: 0.67, blue: 0.99)
        case .vehicle:          return Color(red: 0.27, green: 0.67, blue: 0.99)
        case .entertainment:    return Color(red: 0.68, green: 0.40, blue: 1.00)
        case .shopping:         return Color(red: 1.00, green: 0.35, blue: 0.55)
        case .dailyNecessities: return Color(red: 0.25, green: 0.80, blue: 0.62)
        case .medical:          return Color(red: 1.00, green: 0.25, blue: 0.32)
        case .education:        return Color(red: 0.31, green: 0.55, blue: 0.98)
        case .social:           return Color(red: 1.00, green: 0.72, blue: 0.18)
        case .stock:            return Color(red: 0.20, green: 0.78, blue: 0.48)
        case .realEstate:       return Color(red: 0.47, green: 0.60, blue: 0.82)
        case .tax:              return Color(red: 0.60, green: 0.60, blue: 0.65)
        case .taxSaving:        return Color(red: 0.45, green: 0.72, blue: 0.55)
        case .other:            return Color.secondary
        }
    }
}

// MARK: - 社交子分類

enum SocialSubCategory: String, Codable, CaseIterable, Identifiable {
    case birthdayGift = "生日禮金"
    case newYearRedEnvelope = "過年紅包"
    case weddingGift = "結婚禮金"
    case funeralGift = "白包"
    case babyShower = "彌月禮"
    case visitGift = "探病禮"
    case promotionHousewarming = "升遷／喬遷"
    case other = "其他"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .birthdayGift: return "gift.fill"
        case .newYearRedEnvelope: return "envelope.fill"
        case .weddingGift: return "heart.fill"
        case .funeralGift: return "leaf.fill"
        case .babyShower: return "figure.child"
        case .visitGift: return "cross.case.fill"
        case .promotionHousewarming: return "sparkles"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

// MARK: - 節稅子分類

/// 變動支出分類為「節稅」時可細分的子分類，
/// 與台灣個人綜合所得稅可列舉/特別扣除額對應，提供累積金額追蹤。
enum TaxSavingSubCategory: String, Codable, CaseIterable, Identifiable {
    case donation = "捐贈"
    case insurance = "保險費"
    case medical = "醫療"
    case mortgage = "房貸利息"
    case rent = "房租"
    case education = "教育學費"
    case childcare = "幼兒學前"
    case longCare = "長期照顧"
    case disability = "身心障礙"
    case other = "其他"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .donation: return "gift.fill"
        case .insurance: return "shield.fill"
        case .medical: return "cross.case.fill"
        case .mortgage: return "house.fill"
        case .rent: return "building.2.fill"
        case .education: return "graduationcap.fill"
        case .childcare: return "figure.child"
        case .longCare: return "heart.text.square.fill"
        case .disability: return "figure.roll"
        case .other: return "ellipsis.circle.fill"
        }
    }

    /// 年度扣除上限（NT$）；nil 代表「核實認列、無單一上限或依比例」。
    var annualLimit: Double? {
        switch self {
        case .donation: return nil          // 對政府/教育機構：所得 20% 以內，無固定數字上限
        case .insurance: return 24_000      // 每人 2.4 萬人身保險（健保不計入此上限）
        case .medical: return nil           // 核實認列無上限
        case .mortgage: return 300_000      // 自用住宅貸款利息每年最高 30 萬
        case .rent: return 180_000          // 無自有住宅每年最高 18 萬
        case .education: return 25_000      // 大專以上子女學費每人每年 2.5 萬
        case .childcare: return 120_000     // 5 歲以下子女每人每年 12 萬
        case .longCare: return 120_000      // 每人每年 12 萬
        case .disability: return 207_000    // 每人每年 20.7 萬
        case .other: return nil
        }
    }

    /// 限額說明文字（顯示在進度條下方）
    var limitNote: String {
        switch self {
        case .donation: return "對政府或教育機構無上限；其他公益依綜合所得 20% 內"
        case .insurance: return "人身保險每人每年最高 2.4 萬（全民健保另計、無上限）"
        case .medical: return "醫療生育費用核實認列、無上限"
        case .mortgage: return "自用住宅貸款利息，每年最高 30 萬"
        case .rent: return "無自有住宅者，每年最高 18 萬"
        case .education: return "大專以上子女學費，每人每年最高 2.5 萬"
        case .childcare: return "5 歲以下子女，每人每年 12 萬"
        case .longCare: return "每人每年 12 萬"
        case .disability: return "每人每年 20.7 萬"
        case .other: return "其他可抵稅項目，請依實際扣除規範認列"
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
    var taxSavingSubCategory: TaxSavingSubCategory?  // 節稅變動支出子分類
    var socialSubCategory: SocialSubCategory?  // 社交變動支出子分類（禮金 / 紅包 / 白包 等）
    /// 社交禮金的收受人姓名清單（多筆以逗號分隔）；對應家人或人際關係紀錄
    var socialRecipient: String?
    /// 固定支出是否列入稅務頁節稅追蹤；nil 採自動推斷（見 TaxOverviewView）。
    /// true / false 是使用者明確覆寫。
    var taxDeductibleOverride: Bool?
    var note: String
    var currencyCode: String
    var diningMember: String?
    var loanTotalAmount: Double?
    var loanYears: Double?
    var loanRate: Double?
    var linkedBankMilestoneId: UUID?
    var linkedBankCurrency: String?
    var linkedCreditCardMilestoneId: UUID?
    /// 飲食記錄附帶的店家地址（MKLocalSearch 解析）
    var placeAddress: String?
    /// 飲食記錄附帶的店家緯度
    var placeLatitude: Double?
    /// 飲食記錄附帶的店家經度
    var placeLongitude: Double?
    /// 此筆支出附帶的照片檔名（多張）
    var photoFileNames: [String]

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
        taxSavingSubCategory: TaxSavingSubCategory? = nil,
        socialSubCategory: SocialSubCategory? = nil,
        socialRecipient: String? = nil,
        taxDeductibleOverride: Bool? = nil,
        note: String = "",
        currencyCode: String = "NT$",
        diningMember: String? = nil,
        loanTotalAmount: Double? = nil,
        loanYears: Double? = nil,
        loanRate: Double? = nil,
        linkedBankMilestoneId: UUID? = nil,
        linkedBankCurrency: String? = nil,
        linkedCreditCardMilestoneId: UUID? = nil,
        placeAddress: String? = nil,
        placeLatitude: Double? = nil,
        placeLongitude: Double? = nil,
        photoFileNames: [String] = []
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
        self.taxSavingSubCategory = taxSavingSubCategory
        self.socialSubCategory = socialSubCategory
        self.socialRecipient = socialRecipient
        self.taxDeductibleOverride = taxDeductibleOverride
        self.note = note
        self.currencyCode = currencyCode
        self.diningMember = diningMember
        self.loanTotalAmount = loanTotalAmount
        self.loanYears = loanYears
        self.loanRate = loanRate
        self.linkedBankMilestoneId = linkedBankMilestoneId
        self.linkedBankCurrency = linkedBankCurrency
        self.linkedCreditCardMilestoneId = linkedCreditCardMilestoneId
        self.placeAddress = placeAddress
        self.placeLatitude = placeLatitude
        self.placeLongitude = placeLongitude
        self.photoFileNames = photoFileNames
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
        taxSavingSubCategory = try? c.decodeIfPresent(TaxSavingSubCategory.self, forKey: .taxSavingSubCategory)
        socialSubCategory = try? c.decodeIfPresent(SocialSubCategory.self, forKey: .socialSubCategory)
        socialRecipient = try? c.decodeIfPresent(String.self, forKey: .socialRecipient)
        taxDeductibleOverride = try? c.decodeIfPresent(Bool.self, forKey: .taxDeductibleOverride)
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        currencyCode = (try? c.decode(String.self, forKey: .currencyCode)) ?? "NT$"
        diningMember = try? c.decode(String.self, forKey: .diningMember)
        loanTotalAmount = try? c.decode(Double.self, forKey: .loanTotalAmount)
        loanYears = try? c.decode(Double.self, forKey: .loanYears)
        loanRate = try? c.decode(Double.self, forKey: .loanRate)
        linkedBankMilestoneId = try? c.decode(UUID.self, forKey: .linkedBankMilestoneId)
        linkedBankCurrency = try? c.decode(String.self, forKey: .linkedBankCurrency)
        linkedCreditCardMilestoneId = try? c.decodeIfPresent(UUID.self, forKey: .linkedCreditCardMilestoneId)
        placeAddress = try? c.decodeIfPresent(String.self, forKey: .placeAddress)
        placeLatitude = try? c.decodeIfPresent(Double.self, forKey: .placeLatitude)
        placeLongitude = try? c.decodeIfPresent(Double.self, forKey: .placeLongitude)
        photoFileNames = (try? c.decodeIfPresent([String].self, forKey: .photoFileNames)) ?? []
    }
    private enum CodingKeys: String, CodingKey {
        case id, title, amount, date, expenseType, variableCategory, fixedCategory, recurrence
        case insuranceSubCategory, loanSubCategory
        case linkedInsuranceId, linkedStockId, linkedRealEstateId, linkedVehicleId
        case vehicleExpenseCategory, realEstateExpenseCategory, taxSavingSubCategory
        case socialSubCategory, socialRecipient, taxDeductibleOverride, note, currencyCode, diningMember
        case loanTotalAmount, loanYears, loanRate
        case linkedBankMilestoneId, linkedBankCurrency, linkedCreditCardMilestoneId
        case placeAddress, placeLatitude, placeLongitude, photoFileNames
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
            if variableCategory == .taxSaving, let sub = taxSavingSubCategory {
                return "節稅 - \(sub.rawValue)"
            }
            if variableCategory == .social, let sub = socialSubCategory {
                return "社交 - \(sub.rawValue)"
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

    // MARK: - 節稅推斷（固定支出）

    /// 若此筆固定支出可被視為節稅項目，回傳對應的子分類；否則 nil。
    /// 規則：壽險 / 意外 / 綜合險 / 強制險 → 保險費；房貸 → 房貸利息；房租 → 房租。
    /// 儲蓄險不自動納入（使用者可在編輯時手動勾選 taxDeductibleOverride = true）。
    var inferredTaxSavingSubCategory: TaxSavingSubCategory? {
        guard expenseType == .fixed else { return nil }
        switch fixedCategory {
        case .insurance: return .insurance
        case .loan: return loanSubCategory == .mortgage ? .mortgage : nil
        case .rent: return .rent
        default: return nil
        }
    }

    /// 自動推斷此筆固定支出是否預設列入節稅。
    /// 儲蓄險預設不算（使用者可手動覆寫）。
    var autoTaxDeductible: Bool {
        guard expenseType == .fixed else { return false }
        switch fixedCategory {
        case .insurance: return insuranceSubCategory != .savings
        case .loan: return loanSubCategory == .mortgage
        case .rent: return true
        default: return false
        }
    }

    /// 此筆固定支出在稅務頁是否實際被視為節稅項目（覆寫優先於自動推斷）。
    var effectivelyTaxDeductible: Bool {
        if let override = taxDeductibleOverride { return override }
        return autoTaxDeductible
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

// MARK: - 支出照片儲存（多張）

extension Expense {
    static var photosDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ExpensePhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 將 jpeg 資料寫入並回傳檔名（同時推送 CloudKit）
    static func savePhoto(_ data: Data, expenseId: UUID, photoId: UUID = UUID()) -> String {
        let name = "\(expenseId.uuidString)_\(photoId.uuidString).jpg"
        let url = photosDirectory.appendingPathComponent(name)
        try? data.write(to: url)
        PhotoCloudSync.upload(directory: "ExpensePhotos", fileName: name)
        return name
    }

    static func deletePhoto(_ fileName: String) {
        let url = photosDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
        PhotoCloudSync.delete(directory: "ExpensePhotos", fileName: fileName)
    }

    static func photoURL(for fileName: String) -> URL {
        photosDirectory.appendingPathComponent(fileName)
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
