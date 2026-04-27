import Foundation
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - 個人檔案

struct UserProfile: Codable {
    var chineseName: String
    var englishName: String
    var company: String
    var jobTitle: String
    var spouse: String

    init(chineseName: String = "", englishName: String = "",
         company: String = "", jobTitle: String = "", spouse: String = "") {
        self.chineseName = chineseName
        self.englishName = englishName
        self.company = company
        self.jobTitle = jobTitle
        self.spouse = spouse
    }
}

// MARK: - 家庭成員

enum FamilyMemberRole: String, Codable, CaseIterable, Identifiable {
    case spouse = "配偶"
    case father = "爸爸"
    case mother = "媽媽"
    case son = "兒子"
    case daughter = "女兒"
    case elderBrother = "哥哥"
    case elderSister = "姐姐"
    case youngerBrother = "弟弟"
    case youngerSister = "妹妹"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .spouse: return "heart.circle.fill"
        case .father: return "figure.stand"
        case .mother: return "figure.stand.dress"
        case .son, .daughter: return "figure.child"
        case .elderBrother, .youngerBrother: return "figure.stand"
        case .elderSister, .youngerSister: return "figure.stand.dress"
        }
    }
}

struct FamilyMember: Identifiable, Codable {
    let id: UUID
    var role: FamilyMemberRole
    var chineseName: String
    var englishName: String
    var birthday: Date?
    var marriageDate: Date?
    var isDivorced: Bool
    var divorceDate: Date?
    var childRecords: [ChildRecord]
    var dailyRecords: [DailyRecord]

    init(id: UUID = UUID(), role: FamilyMemberRole = .spouse,
         chineseName: String = "", englishName: String = "",
         birthday: Date? = nil,
         marriageDate: Date? = nil, isDivorced: Bool = false, divorceDate: Date? = nil,
         childRecords: [ChildRecord] = [], dailyRecords: [DailyRecord] = []) {
        self.id = id; self.role = role
        self.chineseName = chineseName; self.englishName = englishName
        self.birthday = birthday
        self.marriageDate = marriageDate
        self.isDivorced = isDivorced
        self.divorceDate = divorceDate
        self.childRecords = childRecords
        self.dailyRecords = dailyRecords
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        role = try c.decode(FamilyMemberRole.self, forKey: .role)
        chineseName = (try? c.decode(String.self, forKey: .chineseName)) ?? ""
        englishName = (try? c.decode(String.self, forKey: .englishName)) ?? ""
        birthday = try? c.decode(Date.self, forKey: .birthday)
        marriageDate = try? c.decode(Date.self, forKey: .marriageDate)
        isDivorced = (try? c.decode(Bool.self, forKey: .isDivorced)) ?? false
        divorceDate = try? c.decode(Date.self, forKey: .divorceDate)
        childRecords = (try? c.decode([ChildRecord].self, forKey: .childRecords)) ?? []
        dailyRecords = (try? c.decode([DailyRecord].self, forKey: .dailyRecords)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(role, forKey: .role)
        try c.encode(chineseName, forKey: .chineseName)
        try c.encode(englishName, forKey: .englishName)
        try c.encodeIfPresent(birthday, forKey: .birthday)
        try c.encodeIfPresent(marriageDate, forKey: .marriageDate)
        try c.encode(isDivorced, forKey: .isDivorced)
        try c.encodeIfPresent(divorceDate, forKey: .divorceDate)
        try c.encode(childRecords, forKey: .childRecords)
        try c.encode(dailyRecords, forKey: .dailyRecords)
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, chineseName, englishName, birthday, marriageDate, isDivorced, divorceDate, childRecords, dailyRecords
    }
}

// MARK: - 兒女日常記錄

enum DailyRecordType: String, Codable, CaseIterable, Identifiable {
    case milk = "喝奶"
    case food = "食物"
    case sleep = "睡眠"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .milk: return "cup.and.saucer.fill"
        case .food: return "carrot.fill"
        case .sleep: return "moon.zzz.fill"
        }
    }
}

struct DailyRecord: Identifiable, Codable {
    let id: UUID
    var type: DailyRecordType
    var date: Date
    var milkBrand: String?
    var mlAmount: Double?
    var foodName: String?
    var sleepEnd: Date?
    var note: String

    init(id: UUID = UUID(), type: DailyRecordType = .milk, date: Date = Date(),
         milkBrand: String? = nil, mlAmount: Double? = nil, foodName: String? = nil,
         sleepEnd: Date? = nil, note: String = "") {
        self.id = id; self.type = type; self.date = date
        self.milkBrand = milkBrand; self.mlAmount = mlAmount
        self.foodName = foodName; self.sleepEnd = sleepEnd; self.note = note
    }
}

// MARK: - 兒女記錄

enum ChildRecordType: String, Codable, CaseIterable, Identifiable {
    case vaccination = "疫苗"
    case allergy = "過敏"
    case growth = "成長記錄"
    case medical = "就醫記錄"
    case education = "教育里程碑"
    case hobby = "興趣才藝"
    case memorable = "紀念時刻"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .vaccination: return "syringe"
        case .allergy: return "allergens"
        case .growth: return "figure.child"
        case .medical: return "cross.case"
        case .education: return "graduationcap.fill"
        case .hobby: return "music.note"
        case .memorable: return "star.fill"
        }
    }
}

enum AllergySeverity: String, Codable, CaseIterable, Identifiable {
    case mild = "輕度"
    case moderate = "中度"
    case severe = "重度"
    var id: String { rawValue }
}

struct ChildRecord: Identifiable, Codable {
    let id: UUID
    var type: ChildRecordType
    var date: Date
    var title: String
    var detail: String
    var note: String
    var heightCm: Double?
    var weightKg: Double?
    var dose: String?
    var severity: AllergySeverity?
    var photoFileName: String?

    init(id: UUID = UUID(), type: ChildRecordType = .memorable,
         date: Date = Date(), title: String = "", detail: String = "", note: String = "",
         heightCm: Double? = nil, weightKg: Double? = nil,
         dose: String? = nil, severity: AllergySeverity? = nil,
         photoFileName: String? = nil) {
        self.id = id; self.type = type; self.date = date
        self.title = title; self.detail = detail; self.note = note
        self.heightCm = heightCm; self.weightKg = weightKg
        self.dose = dose; self.severity = severity
        self.photoFileName = photoFileName
    }

    var photoURL: URL? {
        guard let name = photoFileName else { return nil }
        return Self.photosDirectory.appendingPathComponent(name)
    }

    var sketchURL: URL? {
        guard let name = photoFileName else { return nil }
        let sketchName = name.replacingOccurrences(of: ".jpg", with: "_sketch.jpg")
        let url = Self.photosDirectory.appendingPathComponent(sketchName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static var photosDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChildRecordPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func savePhoto(_ data: Data, id: UUID) -> String {
        let name = "\(id.uuidString).jpg"
        try? data.write(to: photosDirectory.appendingPathComponent(name))
        return name
    }

    static func saveSketch(_ data: Data, id: UUID) -> String {
        let name = "\(id.uuidString)_sketch.jpg"
        try? data.write(to: photosDirectory.appendingPathComponent(name))
        return name
    }

    static func deletePhoto(_ fileName: String) {
        try? FileManager.default.removeItem(at: photosDirectory.appendingPathComponent(fileName))
        let sketchName = fileName.replacingOccurrences(of: ".jpg", with: "_sketch.jpg")
        try? FileManager.default.removeItem(at: photosDirectory.appendingPathComponent(sketchName))
    }

    /// 將照片轉為素描風格（鉛筆畫效果 + 四周高斯模糊暈散）
    static func applySketchEffect(_ image: UIImage) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }
        let context = CIContext()
        let extent = ciImage.extent

        // 素描效果
        let gray = ciImage.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0
        ])
        let inverted = gray.applyingFilter("CIColorInvert")
        let blurred = inverted.applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: 15
        ])
        let sketch = blurred.applyingFilter("CIColorDodgeBlendMode", parameters: [
            kCIInputBackgroundImageKey: gray
        ])

        // 四周高斯模糊的素描版
        let edgeBlurred = sketch.applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: 25
        ])

        // 橢圓漸層遮罩：中心清晰、四周漸層到模糊
        let cx = extent.midX, cy = extent.midY
        let rx = extent.width * 0.38, ry = extent.height * 0.38
        let gradientMask = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: cx, y: cy),
            "inputRadius0": min(rx, ry),
            "inputRadius1": max(extent.width, extent.height) * 0.55,
            "inputColor0": CIColor.white,
            "inputColor1": CIColor.black
        ])!.outputImage!.cropped(to: extent)

        // 混合：遮罩白色區域顯示清晰素描，黑色區域顯示模糊素描
        let blended = sketch.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: edgeBlurred,
            kCIInputMaskImageKey: gradientMask
        ])

        guard let cgImage = context.createCGImage(blended, from: extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - 里程碑分類

enum MilestoneCategory: String, Codable, CaseIterable, Identifiable {
    case marriage = "結婚"
    case family = "家庭"
    case realEstate = "房地產"
    case career = "職涯"
    case education = "學歷"
    case achievement = "成就"
    case travel = "旅行"
    case pet = "寵物"
    case health = "健康"
    case other = "其他"

    var id: String { rawValue }

    /// UI 顯示名稱（可與 rawValue 不同，以保持資料向下相容）
    var displayName: String {
        switch self {
        case .marriage: return "配偶"
        case .achievement: return "財富"
        default: return rawValue
        }
    }

    var icon: String {
        switch self {
        case .marriage: return "heart.circle.fill"
        case .family: return "heart.fill"
        case .realEstate: return "building.2.fill"
        case .career: return "briefcase.fill"
        case .education: return "graduationcap.fill"
        case .achievement: return "banknote.fill"
        case .travel: return "airplane"
        case .pet: return "pawprint.fill"
        case .health: return "cross.fill"
        case .other: return "star.fill"
        }
    }
}

// MARK: - 銀行存款記錄

struct BankDeposit: Identifiable, Codable {
    let id: UUID
    var date: Date
    var amount: Double
    var currencyCode: String
    var isWithdrawal: Bool
    var linkedExpenseId: UUID?
    var linkedStockId: UUID?

    init(id: UUID = UUID(), date: Date = Date(), amount: Double = 0,
         currencyCode: String = "NT$", isWithdrawal: Bool = false,
         linkedExpenseId: UUID? = nil, linkedStockId: UUID? = nil) {
        self.id = id; self.date = date; self.amount = amount
        self.currencyCode = currencyCode
        self.isWithdrawal = isWithdrawal
        self.linkedExpenseId = linkedExpenseId
        self.linkedStockId = linkedStockId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        amount = try c.decode(Double.self, forKey: .amount)
        currencyCode = try c.decode(String.self, forKey: .currencyCode)
        isWithdrawal = (try? c.decode(Bool.self, forKey: .isWithdrawal)) ?? false
        linkedExpenseId = try? c.decodeIfPresent(UUID.self, forKey: .linkedExpenseId)
        linkedStockId = try? c.decodeIfPresent(UUID.self, forKey: .linkedStockId)
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, amount, currencyCode, isWithdrawal, linkedExpenseId, linkedStockId
    }
}

// MARK: - 理財子分類

enum FinanceSubCategory: String, Codable, CaseIterable, Identifiable {
    case bank = "銀行"
    case creditCard = "信用卡"
    case securities = "證券"
    case insurance = "保險"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .bank: return "building.columns.fill"
        case .creditCard: return "creditcard.fill"
        case .securities: return "chart.bar.fill"
        case .insurance: return "shield.fill"
        }
    }
}

enum BankAccountType: String, Codable, CaseIterable, Identifiable {
    case savings = "活存"
    case fixed = "定存"
    case foreign = "外幣"
    var id: String { rawValue }
}

enum SecuritiesAccountType: String, Codable, CaseIterable, Identifiable {
    case regular = "一般"
    case margin = "融資融券"
    var id: String { rawValue }
}

enum InsuranceType: String, Codable, CaseIterable, Identifiable {
    case life = "壽險"
    case health = "醫療"
    case accident = "意外"
    case travel = "旅平"
    case car = "車險"
    var id: String { rawValue }
}

// MARK: - 職涯子分類

enum CareerSubCategory: String, Codable, CaseIterable, Identifiable {
    case join = "入職"
    case promote = "升職"
    case salaryAdjust = "調薪"
    case transfer = "轉職"
    case demote = "降職"
    case resign = "離職"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .join: return "arrow.right.to.line"
        case .promote: return "arrow.up.circle.fill"
        case .salaryAdjust: return "dollarsign.arrow.circlepath"
        case .transfer: return "arrow.left.arrow.right"
        case .demote: return "arrow.down.circle.fill"
        case .resign: return "arrow.right.square"
        }
    }
}

struct LifeMilestone: Identifiable, Codable {
    let id: UUID
    var title: String
    var date: Date
    var category: MilestoneCategory
    var note: String

    // 職涯專屬欄位
    var careerSubCategory: CareerSubCategory?
    var companyName: String?
    var department: String?
    var jobTitle: String?
    var jobGrade: String?
    var mood: String?
    var futurePlan: String?
    var isManagerial: Bool?
    var salary: Double?
    var salaryBefore: Double?
    var salaryAfter: Double?

    // 理財專屬欄位
    var financeSubCategory: FinanceSubCategory?
    var bankName: String?
    var branchName: String?
    var accountNumber: String?
    var bankAccountType: BankAccountType?
    var cardName: String?
    var cardLastFour: String?
    var creditLimit: Double?
    var annualFee: Double?
    var billingDay: Int?
    var paymentDay: Int?
    var expiryDate: Date?
    var securitiesAccountType: SecuritiesAccountType?
    var insuranceCompany: String?
    var policyNumber: String?
    var insuranceType: InsuranceType?
    var premiumAmount: Double?
    var beneficiary: String?
    var bankDeposits: [BankDeposit]?
    var linkedBankMilestoneId: UUID?

    init(id: UUID = UUID(), title: String, date: Date = Date(),
         category: MilestoneCategory = .other, note: String = "",
         careerSubCategory: CareerSubCategory? = nil,
         companyName: String? = nil, department: String? = nil,
         jobTitle: String? = nil, jobGrade: String? = nil,
         mood: String? = nil, futurePlan: String? = nil,
         isManagerial: Bool? = nil,
         salary: Double? = nil, salaryBefore: Double? = nil, salaryAfter: Double? = nil,
         financeSubCategory: FinanceSubCategory? = nil,
         bankName: String? = nil, branchName: String? = nil, accountNumber: String? = nil,
         bankAccountType: BankAccountType? = nil,
         cardName: String? = nil, cardLastFour: String? = nil,
         creditLimit: Double? = nil, annualFee: Double? = nil,
         billingDay: Int? = nil, paymentDay: Int? = nil, expiryDate: Date? = nil,
         securitiesAccountType: SecuritiesAccountType? = nil,
         insuranceCompany: String? = nil, policyNumber: String? = nil,
         insuranceType: InsuranceType? = nil, premiumAmount: Double? = nil,
         beneficiary: String? = nil,
         linkedBankMilestoneId: UUID? = nil) {
        self.id = id; self.title = title; self.date = date
        self.category = category; self.note = note
        self.careerSubCategory = careerSubCategory
        self.companyName = companyName; self.department = department
        self.jobTitle = jobTitle; self.jobGrade = jobGrade
        self.mood = mood; self.futurePlan = futurePlan
        self.isManagerial = isManagerial
        self.salary = salary; self.salaryBefore = salaryBefore; self.salaryAfter = salaryAfter
        self.financeSubCategory = financeSubCategory
        self.bankName = bankName; self.branchName = branchName; self.accountNumber = accountNumber
        self.bankAccountType = bankAccountType
        self.cardName = cardName; self.cardLastFour = cardLastFour
        self.creditLimit = creditLimit; self.annualFee = annualFee
        self.billingDay = billingDay; self.paymentDay = paymentDay; self.expiryDate = expiryDate
        self.securitiesAccountType = securitiesAccountType
        self.insuranceCompany = insuranceCompany; self.policyNumber = policyNumber
        self.insuranceType = insuranceType; self.premiumAmount = premiumAmount
        self.beneficiary = beneficiary
        self.linkedBankMilestoneId = linkedBankMilestoneId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        date = try c.decode(Date.self, forKey: .date)
        category = try c.decode(MilestoneCategory.self, forKey: .category)
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        careerSubCategory = try? c.decode(CareerSubCategory.self, forKey: .careerSubCategory)
        companyName = try? c.decode(String.self, forKey: .companyName)
        department = try? c.decode(String.self, forKey: .department)
        jobTitle = try? c.decode(String.self, forKey: .jobTitle)
        jobGrade = try? c.decode(String.self, forKey: .jobGrade)
        mood = try? c.decode(String.self, forKey: .mood)
        futurePlan = try? c.decode(String.self, forKey: .futurePlan)
        isManagerial = try? c.decode(Bool.self, forKey: .isManagerial)
        salary = try? c.decode(Double.self, forKey: .salary)
        salaryBefore = try? c.decode(Double.self, forKey: .salaryBefore)
        salaryAfter = try? c.decode(Double.self, forKey: .salaryAfter)
        financeSubCategory = try? c.decode(FinanceSubCategory.self, forKey: .financeSubCategory)
        bankName = try? c.decode(String.self, forKey: .bankName)
        branchName = try? c.decode(String.self, forKey: .branchName)
        accountNumber = try? c.decode(String.self, forKey: .accountNumber)
        bankAccountType = try? c.decode(BankAccountType.self, forKey: .bankAccountType)
        cardName = try? c.decode(String.self, forKey: .cardName)
        cardLastFour = try? c.decode(String.self, forKey: .cardLastFour)
        creditLimit = try? c.decode(Double.self, forKey: .creditLimit)
        annualFee = try? c.decode(Double.self, forKey: .annualFee)
        billingDay = try? c.decode(Int.self, forKey: .billingDay)
        paymentDay = try? c.decode(Int.self, forKey: .paymentDay)
        expiryDate = try? c.decode(Date.self, forKey: .expiryDate)
        securitiesAccountType = try? c.decode(SecuritiesAccountType.self, forKey: .securitiesAccountType)
        insuranceCompany = try? c.decode(String.self, forKey: .insuranceCompany)
        policyNumber = try? c.decode(String.self, forKey: .policyNumber)
        insuranceType = try? c.decode(InsuranceType.self, forKey: .insuranceType)
        premiumAmount = try? c.decode(Double.self, forKey: .premiumAmount)
        beneficiary = try? c.decode(String.self, forKey: .beneficiary)
        bankDeposits = try? c.decode([BankDeposit].self, forKey: .bankDeposits)
        linkedBankMilestoneId = try? c.decodeIfPresent(UUID.self, forKey: .linkedBankMilestoneId)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, date, category, note
        case careerSubCategory, companyName, department, jobTitle, jobGrade
        case mood, futurePlan, isManagerial, salary, salaryBefore, salaryAfter
        case financeSubCategory, bankName, branchName, accountNumber, bankAccountType
        case cardName, cardLastFour, creditLimit, annualFee, billingDay, paymentDay, expiryDate
        case securitiesAccountType, insuranceCompany, policyNumber, insuranceType, premiumAmount, beneficiary, bankDeposits, linkedBankMilestoneId
    }

    /// 信用卡實際扣款日：以消費日推算結帳後的繳款日
    /// billCloseMonth = 消費日 > 結帳日 ? 下個月 : 當月
    /// paymentOffset = 繳款日 ≤ 結帳日 ? +1 : 0（繳款日在結帳日之後 → 同月繳）
    static func creditCardWithdrawalDate(for expenseDate: Date, billingDay: Int?, paymentDay: Int?) -> Date {
        let calendar = Calendar.current
        let payDay = paymentDay ?? 15
        let billDay = billingDay ?? 25
        let expenseDay = calendar.component(.day, from: expenseDate)
        var components = calendar.dateComponents([.year, .month], from: expenseDate)
        let billCloseOffset = expenseDay > billDay ? 1 : 0
        let paymentOffset = payDay <= billDay ? 1 : 0
        components.month = (components.month ?? 1) + billCloseOffset + paymentOffset
        components.day = payDay
        return calendar.date(from: components) ?? expenseDate
    }
}

// MARK: - 人際關係群組

enum RelationshipGroup: String, Codable, CaseIterable, Identifiable {
    case family = "家人"
    case friend = "朋友"
    case colleague = "同事"
    case client = "客戶"
    case other = "其他"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .family: return "house.fill"
        case .friend: return "person.2.fill"
        case .colleague: return "building.2.fill"
        case .client: return "person.crop.rectangle.fill"
        case .other: return "person.fill"
        }
    }
}

struct InteractionRecord: Identifiable, Codable {
    let id: UUID
    var date: Date
    var note: String

    init(id: UUID = UUID(), date: Date = Date(), note: String = "") {
        self.id = id; self.date = date; self.note = note
    }
}

struct Relationship: Identifiable, Codable {
    let id: UUID
    var name: String
    var group: RelationshipGroup
    var birthday: Date?
    var anniversary: Date?
    var phone: String
    var note: String
    var interactions: [InteractionRecord]

    init(id: UUID = UUID(), name: String, group: RelationshipGroup = .friend,
         birthday: Date? = nil, anniversary: Date? = nil,
         phone: String = "", note: String = "",
         interactions: [InteractionRecord] = []) {
        self.id = id; self.name = name; self.group = group
        self.birthday = birthday; self.anniversary = anniversary
        self.phone = phone; self.note = note; self.interactions = interactions
    }
}

// MARK: - 寵物類型

enum PetType: String, Codable, CaseIterable, Identifiable {
    case dog = "狗"
    case cat = "貓"
    case bird = "鳥"
    case fish = "魚"
    case hamster = "倉鼠"
    case rabbit = "兔子"
    case reptile = "爬蟲"
    case other = "其他"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dog: return "dog.fill"
        case .cat: return "cat.fill"
        case .bird: return "bird.fill"
        case .fish: return "fish.fill"
        case .hamster: return "hare.fill"
        case .rabbit: return "rabbit.fill"
        case .reptile: return "lizard.fill"
        case .other: return "pawprint.fill"
        }
    }
}

enum PetHealthType: String, Codable, CaseIterable, Identifiable {
    case vaccine = "疫苗"
    case visit = "就診"
    case medication = "用藥"
    case grooming = "美容"
    case checkup = "健檢"
    case other = "其他"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .vaccine: return "syringe.fill"
        case .visit: return "stethoscope"
        case .medication: return "pills.fill"
        case .grooming: return "scissors"
        case .checkup: return "heart.text.clipboard.fill"
        case .other: return "cross.case.fill"
        }
    }
}

struct PetHealthRecord: Identifiable, Codable {
    let id: UUID
    var date: Date
    var type: PetHealthType
    var title: String
    var cost: Double
    var note: String

    init(id: UUID = UUID(), date: Date = Date(), type: PetHealthType = .visit,
         title: String = "", cost: Double = 0, note: String = "") {
        self.id = id; self.date = date; self.type = type
        self.title = title; self.cost = cost; self.note = note
    }
}

struct Pet: Identifiable, Codable {
    let id: UUID
    var name: String
    var type: PetType
    var breed: String
    var birthday: Date?
    var weight: Double
    var note: String
    var healthRecords: [PetHealthRecord]

    init(id: UUID = UUID(), name: String, type: PetType = .dog,
         breed: String = "", birthday: Date? = nil, weight: Double = 0,
         note: String = "", healthRecords: [PetHealthRecord] = []) {
        self.id = id; self.name = name; self.type = type; self.breed = breed
        self.birthday = birthday; self.weight = weight
        self.note = note; self.healthRecords = healthRecords
    }

    var age: Double? {
        guard let birthday else { return nil }
        let days = Calendar.current.dateComponents([.day], from: birthday, to: Date()).day ?? 0
        return Double(max(0, days)) / 365.0
    }
}

// MARK: - 行程分類

enum ScheduleCategory: String, Codable, CaseIterable, Identifiable {
    case appointment = "約會"
    case travel = "旅遊"
    case meeting = "會議"
    case reminder = "提醒"
    case birthday = "生日"
    case other = "其他"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .appointment: return "calendar.badge.clock"
        case .travel: return "airplane.departure"
        case .meeting: return "person.3.fill"
        case .reminder: return "bell.fill"
        case .birthday: return "gift.fill"
        case .other: return "calendar"
        }
    }
}

struct Schedule: Identifiable, Codable {
    let id: UUID
    var title: String
    var date: Date
    var endDate: Date?
    var category: ScheduleCategory
    var location: String
    var isCompleted: Bool
    var note: String

    init(id: UUID = UUID(), title: String, date: Date = Date(),
         endDate: Date? = nil, category: ScheduleCategory = .other,
         location: String = "", isCompleted: Bool = false, note: String = "") {
        self.id = id; self.title = title; self.date = date
        self.endDate = endDate; self.category = category
        self.location = location; self.isCompleted = isCompleted; self.note = note
    }
}

// MARK: - 部屬記錄類型

enum SubordinateRecordType: String, Codable, CaseIterable, Identifiable {
    case pro = "優點"
    case con = "缺點"
    case achievement = "成就"
    case improvement = "改善"
    case fault = "缺失"
    case missOperation = "Miss Operation"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .pro: return "hand.thumbsup.fill"
        case .con: return "hand.thumbsdown.fill"
        case .achievement: return "trophy.fill"
        case .improvement: return "arrow.up.circle.fill"
        case .fault: return "exclamationmark.triangle.fill"
        case .missOperation: return "xmark.octagon.fill"
        }
    }
}

enum MissOpSeverity: String, Codable, CaseIterable, Identifiable {
    case minor = "輕微"
    case normal = "一般"
    case severe = "嚴重"
    var id: String { rawValue }
}

// MARK: - 部屬記錄

struct SubordinateRecord: Identifiable, Codable {
    let id: UUID
    var type: SubordinateRecordType
    var content: String
    var date: Date
    var note: String
    var severity: MissOpSeverity?

    init(id: UUID = UUID(), type: SubordinateRecordType = .pro,
         content: String = "", date: Date = Date(), note: String = "",
         severity: MissOpSeverity? = nil) {
        self.id = id; self.type = type; self.content = content
        self.date = date; self.note = note; self.severity = severity
    }
}

// MARK: - 部屬

struct Subordinate: Identifiable, Codable {
    let id: UUID
    var name: String
    var jobTitle: String
    var department: String
    var note: String
    var gradeTitleId: UUID?
    var departmentId: UUID?
    var records: [SubordinateRecord]
    var joinDate: Date?

    init(id: UUID = UUID(), name: String, jobTitle: String = "",
         department: String = "", note: String = "", gradeTitleId: UUID? = nil,
         departmentId: UUID? = nil, records: [SubordinateRecord] = [], joinDate: Date? = nil) {
        self.id = id; self.name = name; self.jobTitle = jobTitle
        self.department = department; self.note = note; self.gradeTitleId = gradeTitleId
        self.departmentId = departmentId; self.records = records; self.joinDate = joinDate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        jobTitle = try c.decode(String.self, forKey: .jobTitle)
        department = try c.decode(String.self, forKey: .department)
        note = try c.decode(String.self, forKey: .note)
        gradeTitleId = try c.decodeIfPresent(UUID.self, forKey: .gradeTitleId)
        departmentId = try c.decodeIfPresent(UUID.self, forKey: .departmentId)
        records = (try? c.decode([SubordinateRecord].self, forKey: .records)) ?? []
        joinDate = try c.decodeIfPresent(Date.self, forKey: .joinDate)
    }
}

// MARK: - 部門名稱

struct Department: Identifiable, Codable {
    let id: UUID
    var code: String
    var name: String

    init(id: UUID = UUID(), code: String = "", name: String = "") {
        self.id = id; self.code = code; self.name = name
    }
}

// MARK: - 職等對應職稱

struct GradeTitle: Identifiable, Codable {
    let id: UUID
    var grade: String
    var title: String

    init(id: UUID = UUID(), grade: String = "", title: String = "") {
        self.id = id; self.grade = grade; self.title = title
    }
}
