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
    case otherRelative = "其他親屬"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .spouse: return "heart.circle.fill"
        case .father: return "figure.stand"
        case .mother: return "figure.stand.dress"
        case .son, .daughter: return "figure.child"
        case .elderBrother, .youngerBrother: return "figure.stand"
        case .elderSister, .youngerSister: return "figure.stand.dress"
        case .otherRelative: return "person.2.fill"
        }
    }

    /// 適用「家族側」（我的家人 / 配偶家人）的角色
    var supportsFamilySide: Bool {
        switch self {
        case .father, .mother, .elderBrother, .elderSister,
             .youngerBrother, .youngerSister, .otherRelative:
            return true
        case .spouse, .son, .daughter:
            return false
        }
    }

    /// 父母 role 對應的「另一半」候選 role
    var spouseCandidateRole: FamilyMemberRole? {
        switch self {
        case .father: return .mother
        case .mother: return .father
        default: return nil
        }
    }
}

// MARK: - 家族側

enum FamilySide: String, Codable, CaseIterable, Identifiable {
    case mine = "我的"
    case spouse = "配偶的"
    var id: String { rawValue }
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
    var birthYear: Int?
    var idNumber: String?
    var relativeNote: String?
    var familyEvents: [FamilyEvent]
    var familyPhotos: [FamilyAlbumPhoto]
    /// 家族側：我的 / 配偶的（僅父母 / 兄姊弟妹 / 其他親屬適用）
    var familySide: FamilySide?
    /// 父母配對：媽媽指向爸爸（或反向），自由不選
    var spouseId: UUID?

    init(id: UUID = UUID(), role: FamilyMemberRole = .spouse,
         chineseName: String = "", englishName: String = "",
         birthday: Date? = nil,
         marriageDate: Date? = nil, isDivorced: Bool = false, divorceDate: Date? = nil,
         childRecords: [ChildRecord] = [], dailyRecords: [DailyRecord] = [],
         birthYear: Int? = nil, idNumber: String? = nil, relativeNote: String? = nil,
         familyEvents: [FamilyEvent] = [], familyPhotos: [FamilyAlbumPhoto] = [],
         familySide: FamilySide? = nil, spouseId: UUID? = nil) {
        self.id = id; self.role = role
        self.chineseName = chineseName; self.englishName = englishName
        self.birthday = birthday
        self.marriageDate = marriageDate
        self.isDivorced = isDivorced
        self.divorceDate = divorceDate
        self.childRecords = childRecords
        self.dailyRecords = dailyRecords
        self.birthYear = birthYear
        self.idNumber = idNumber
        self.relativeNote = relativeNote
        self.familyEvents = familyEvents
        self.familyPhotos = familyPhotos
        self.familySide = familySide
        self.spouseId = spouseId
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
        birthYear = try? c.decodeIfPresent(Int.self, forKey: .birthYear)
        idNumber = try? c.decodeIfPresent(String.self, forKey: .idNumber)
        relativeNote = try? c.decodeIfPresent(String.self, forKey: .relativeNote)
        familyEvents = (try? c.decode([FamilyEvent].self, forKey: .familyEvents)) ?? []
        familyPhotos = (try? c.decode([FamilyAlbumPhoto].self, forKey: .familyPhotos)) ?? []
        familySide = try? c.decodeIfPresent(FamilySide.self, forKey: .familySide)
        spouseId = try? c.decodeIfPresent(UUID.self, forKey: .spouseId)
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
        try c.encodeIfPresent(birthYear, forKey: .birthYear)
        try c.encodeIfPresent(idNumber, forKey: .idNumber)
        try c.encodeIfPresent(relativeNote, forKey: .relativeNote)
        try c.encode(familyEvents, forKey: .familyEvents)
        try c.encode(familyPhotos, forKey: .familyPhotos)
        try c.encodeIfPresent(familySide, forKey: .familySide)
        try c.encodeIfPresent(spouseId, forKey: .spouseId)
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, chineseName, englishName, birthday, marriageDate, isDivorced, divorceDate, childRecords, dailyRecords
        case birthYear, idNumber, relativeNote, familyEvents, familyPhotos
        case familySide, spouseId
    }

    /// 顯示用稱謂：依 familySide 與 role 自動套用「我的」或「配偶的」前綴
    var displayRoleLabel: String {
        guard let side = familySide, side == .spouse, role.supportsFamilySide else {
            return role.rawValue
        }
        switch role {
        case .father: return "配偶的父親"
        case .mother: return "配偶的母親"
        case .elderBrother: return "配偶的哥哥"
        case .elderSister: return "配偶的姐姐"
        case .youngerBrother: return "配偶的弟弟"
        case .youngerSister: return "配偶的妹妹"
        case .otherRelative: return "配偶的親屬"
        default: return role.rawValue
        }
    }
}

// MARK: - 家人履歷紀錄 / 相簿照片

struct FamilyEvent: Identifiable, Codable, Equatable {
    let id: UUID
    var date: Date
    var title: String
    var content: String

    init(id: UUID = UUID(), date: Date = Date(), title: String = "", content: String = "") {
        self.id = id; self.date = date; self.title = title; self.content = content
    }
}

struct FamilyAlbumPhoto: Identifiable, Codable, Equatable {
    let id: UUID
    var date: Date
    var title: String
    var photoFileName: String?
    var note: String

    init(id: UUID = UUID(), date: Date = Date(), title: String = "",
         photoFileName: String? = nil, note: String = "") {
        self.id = id; self.date = date; self.title = title
        self.photoFileName = photoFileName; self.note = note
    }

    var photoURL: URL? {
        guard let name = photoFileName else { return nil }
        return Self.photosDirectory.appendingPathComponent(name)
    }

    static var photosDirectory: URL {
        let dir = (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("FamilyAlbumPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func savePhoto(_ data: Data, id: UUID) -> String {
        let name = "\(id.uuidString).jpg"
        let url = photosDirectory.appendingPathComponent(name)
        try? data.write(to: url)
        PhotoCloudSync.upload(directory: "FamilyAlbumPhotos", fileName: name)
        return name
    }

    static func deletePhoto(_ fileName: String) {
        let url = photosDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
        PhotoCloudSync.delete(directory: "FamilyAlbumPhotos", fileName: fileName)
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
        let dir = (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("ChildRecordPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func savePhoto(_ data: Data, id: UUID) -> String {
        let name = "\(id.uuidString).jpg"
        try? data.write(to: photosDirectory.appendingPathComponent(name))
        PhotoCloudSync.upload(directory: "ChildRecordPhotos", fileName: name)
        return name
    }

    static func saveSketch(_ data: Data, id: UUID) -> String {
        let name = "\(id.uuidString)_sketch.jpg"
        try? data.write(to: photosDirectory.appendingPathComponent(name))
        PhotoCloudSync.upload(directory: "ChildRecordPhotos", fileName: name)
        return name
    }

    static func deletePhoto(_ fileName: String) {
        try? FileManager.default.removeItem(at: photosDirectory.appendingPathComponent(fileName))
        PhotoCloudSync.delete(directory: "ChildRecordPhotos", fileName: fileName)
        let sketchName = fileName.replacingOccurrences(of: ".jpg", with: "_sketch.jpg")
        try? FileManager.default.removeItem(at: photosDirectory.appendingPathComponent(sketchName))
        PhotoCloudSync.delete(directory: "ChildRecordPhotos", fileName: sketchName)
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
        guard let gradientOutput = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: cx, y: cy),
            "inputRadius0": min(rx, ry),
            "inputRadius1": max(extent.width, extent.height) * 0.55,
            "inputColor0": CIColor.white,
            "inputColor1": CIColor.black
        ])?.outputImage else { return nil }
        let gradientMask = gradientOutput.cropped(to: extent)

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
    /// 由「沖正」功能建立的調整紀錄；用來在列表上顯示「沖正」徽章
    var isAdjust: Bool
    /// 備註（沖正調整原因等）
    var note: String?

    init(id: UUID = UUID(), date: Date = Date(), amount: Double = 0,
         currencyCode: String = "NT$", isWithdrawal: Bool = false,
         linkedExpenseId: UUID? = nil, linkedStockId: UUID? = nil,
         isAdjust: Bool = false, note: String? = nil) {
        self.id = id; self.date = date; self.amount = amount
        self.currencyCode = currencyCode
        self.isWithdrawal = isWithdrawal
        self.linkedExpenseId = linkedExpenseId
        self.linkedStockId = linkedStockId
        self.isAdjust = isAdjust
        self.note = note
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
        isAdjust = (try? c.decode(Bool.self, forKey: .isAdjust)) ?? false
        note = try? c.decodeIfPresent(String.self, forKey: .note)
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, amount, currencyCode, isWithdrawal, linkedExpenseId, linkedStockId, isAdjust, note
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
    /// 信用卡是否已停用（停用後不會出現在新增支出的信用卡選單，但歷史紀錄保留）
    var isDisabled: Bool?
    /// 信用卡綁定的悠遊卡卡號
    var easyCardNumber: String?
    /// 信用卡綁定的一卡通卡號
    var iPassNumber: String?
    /// 信用卡綁定的 Happy Go 會員卡號
    var happyGoNumber: String?

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
        isDisabled = try? c.decodeIfPresent(Bool.self, forKey: .isDisabled)
        easyCardNumber = try? c.decodeIfPresent(String.self, forKey: .easyCardNumber)
        iPassNumber = try? c.decodeIfPresent(String.self, forKey: .iPassNumber)
        happyGoNumber = try? c.decodeIfPresent(String.self, forKey: .happyGoNumber)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, date, category, note
        case careerSubCategory, companyName, department, jobTitle, jobGrade
        case mood, futurePlan, isManagerial, salary, salaryBefore, salaryAfter
        case financeSubCategory, bankName, branchName, accountNumber, bankAccountType
        case cardName, cardLastFour, creditLimit, annualFee, billingDay, paymentDay, expiryDate
        case securitiesAccountType, insuranceCompany, policyNumber, insuranceType, premiumAmount, beneficiary, bankDeposits, linkedBankMilestoneId
        case isDisabled
        case easyCardNumber, iPassNumber, happyGoNumber
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
    case leave = "請假"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .pro: return "hand.thumbsup.fill"
        case .con: return "hand.thumbsdown.fill"
        case .achievement: return "trophy.fill"
        case .improvement: return "arrow.up.circle.fill"
        case .fault: return "exclamationmark.triangle.fill"
        case .missOperation: return "xmark.octagon.fill"
        case .leave: return "calendar.badge.minus"
        }
    }
}

enum MissOpSeverity: String, Codable, CaseIterable, Identifiable {
    case minor = "輕微"
    case normal = "一般"
    case severe = "嚴重"
    var id: String { rawValue }
}

enum LeaveType: String, Codable, CaseIterable, Identifiable {
    case personal = "事假"
    case sick = "病假"
    case annual = "特休"
    case marriage = "婚假"
    case funeral = "喪假"
    case maternity = "產假"
    case paternity = "陪產假"
    case official = "公假"
    case workInjury = "公傷假"

    var id: String { rawValue }
}

// MARK: - 部屬記錄

struct SubordinateRecord: Identifiable, Codable {
    let id: UUID
    var type: SubordinateRecordType
    var content: String
    var date: Date
    var endDate: Date?
    var note: String
    var severity: MissOpSeverity?
    var leaveType: LeaveType?
    var leaveHours: Double?

    init(id: UUID = UUID(), type: SubordinateRecordType = .pro,
         content: String = "", date: Date = Date(), endDate: Date? = nil, note: String = "",
         severity: MissOpSeverity? = nil,
         leaveType: LeaveType? = nil, leaveHours: Double? = nil) {
        self.id = id; self.type = type; self.content = content
        self.date = date; self.endDate = endDate; self.note = note
        self.severity = severity
        self.leaveType = leaveType; self.leaveHours = leaveHours
    }
}

// MARK: - 會議

enum MeetingRecurrence: String, Codable, CaseIterable, Identifiable {
    case daily = "每日"
    case weekly = "每週"
    case biweekly = "隔週"
    case monthly = "每月"
    var id: String { rawValue }
}

struct MeetingItem: Identifiable, Codable {
    let id: UUID
    var content: String
    var assigneeId: UUID?
    var dueDate: Date?

    init(id: UUID = UUID(), content: String = "", assigneeId: UUID? = nil, dueDate: Date? = nil) {
        self.id = id; self.content = content; self.assigneeId = assigneeId; self.dueDate = dueDate
    }
}

struct SubordinateMeeting: Identifiable, Codable {
    let id: UUID
    var topic: String
    var date: Date
    var durationMinutes: Int
    var recurrence: MeetingRecurrence?
    var items: [MeetingItem]
    var note: String

    init(id: UUID = UUID(), topic: String = "", date: Date = Date(),
         durationMinutes: Int = 60, recurrence: MeetingRecurrence? = nil,
         items: [MeetingItem] = [], note: String = "") {
        self.id = id; self.topic = topic; self.date = date
        self.durationMinutes = durationMinutes; self.recurrence = recurrence
        self.items = items; self.note = note
    }
}

// MARK: - 任務

struct SubordinateTask: Identifiable, Codable {
    let id: UUID
    var topic: String
    var content: String
    var date: Date
    var dueDate: Date?
    var note: String
    var isCompleted: Bool
    var completedAt: Date?

    init(id: UUID = UUID(), topic: String = "", content: String = "",
         date: Date = Date(), dueDate: Date? = nil, note: String = "",
         isCompleted: Bool = false, completedAt: Date? = nil) {
        self.id = id; self.topic = topic; self.content = content
        self.date = date; self.dueDate = dueDate; self.note = note
        self.isCompleted = isCompleted; self.completedAt = completedAt
    }

    // 自訂解碼：isCompleted / completedAt 為後加欄位，舊存檔沒有這兩個 key。
    // 用 decodeIfPresent 容錯，避免單筆缺欄位導致整個 subordinates 陣列解碼失敗、資料消失。
    enum CodingKeys: String, CodingKey {
        case id, topic, content, date, dueDate, note, isCompleted, completedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        topic = try c.decodeIfPresent(String.self, forKey: .topic) ?? ""
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
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
    var meetings: [SubordinateMeeting]
    var tasks: [SubordinateTask]

    init(id: UUID = UUID(), name: String, jobTitle: String = "",
         department: String = "", note: String = "", gradeTitleId: UUID? = nil,
         departmentId: UUID? = nil, records: [SubordinateRecord] = [], joinDate: Date? = nil,
         meetings: [SubordinateMeeting] = [], tasks: [SubordinateTask] = []) {
        self.id = id; self.name = name; self.jobTitle = jobTitle
        self.department = department; self.note = note; self.gradeTitleId = gradeTitleId
        self.departmentId = departmentId; self.records = records; self.joinDate = joinDate
        self.meetings = meetings; self.tasks = tasks
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
        meetings = (try? c.decode([SubordinateMeeting].self, forKey: .meetings)) ?? []
        tasks = (try? c.decode([SubordinateTask].self, forKey: .tasks)) ?? []
    }
}

// MARK: - 名片

struct BusinessCard: Identifiable, Codable {
    let id: UUID
    var name: String
    var company: String
    var department: String
    var jobTitle: String
    /// 多筆電話（手機 / 公司 / 副線 等）；可含分機字串如「02-1234-5678 分機 123」
    var phones: [String]
    /// 多筆 Email（公司 / 個人 等）
    var emails: [String]
    /// 傳真號碼
    var faxes: [String]
    var address: String
    var note: String
    var date: Date
    /// 主要業務 / 經營項目（可被搜尋欄位命中）
    var primaryBusiness: String
    /// 名片頭像照片檔名（存於 BusinessCardPhotos 目錄）
    var photoFileName: String?
    /// 連結的公司組織人員 ID（雙向同步：OrgPerson.linkedBusinessCardId 也會指回來）
    var linkedOrgPersonId: UUID?

    /// Backward-compatible 單值 accessor：讀取第一筆、寫入更新第一筆，
    /// 主要供舊有 `.phone` / `.email` 程式碼維持運作。
    var phone: String {
        get { phones.first ?? "" }
        set {
            let v = newValue.trimmingCharacters(in: .whitespaces)
            if phones.isEmpty {
                phones = v.isEmpty ? [] : [v]
            } else if v.isEmpty {
                phones.removeFirst()
            } else {
                phones[0] = v
            }
        }
    }
    var email: String {
        get { emails.first ?? "" }
        set {
            let v = newValue.trimmingCharacters(in: .whitespaces)
            if emails.isEmpty {
                emails = v.isEmpty ? [] : [v]
            } else if v.isEmpty {
                emails.removeFirst()
            } else {
                emails[0] = v
            }
        }
    }

    init(id: UUID = UUID(), name: String = "", company: String = "",
         department: String = "", jobTitle: String = "",
         phone: String = "", email: String = "", address: String = "",
         note: String = "", date: Date = Date(),
         photoFileName: String? = nil,
         linkedOrgPersonId: UUID? = nil,
         phones: [String] = [], emails: [String] = [], faxes: [String] = [],
         primaryBusiness: String = "") {
        self.id = id; self.name = name; self.company = company
        self.department = department; self.jobTitle = jobTitle
        // 多值優先；只給單值時包成單元素陣列（空字串忽略）
        if !phones.isEmpty {
            self.phones = phones
        } else {
            self.phones = phone.isEmpty ? [] : [phone]
        }
        if !emails.isEmpty {
            self.emails = emails
        } else {
            self.emails = email.isEmpty ? [] : [email]
        }
        self.faxes = faxes
        self.address = address; self.note = note; self.date = date
        self.photoFileName = photoFileName
        self.linkedOrgPersonId = linkedOrgPersonId
        self.primaryBusiness = primaryBusiness
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        company = (try? c.decode(String.self, forKey: .company)) ?? ""
        department = (try? c.decode(String.self, forKey: .department)) ?? ""
        jobTitle = (try? c.decode(String.self, forKey: .jobTitle)) ?? ""
        // 多值優先；舊資料只有單值時自動轉成單元素陣列
        if let arr = try? c.decode([String].self, forKey: .phones) {
            phones = arr.filter { !$0.isEmpty }
        } else if let single = try? c.decode(String.self, forKey: .phone), !single.isEmpty {
            phones = [single]
        } else {
            phones = []
        }
        if let arr = try? c.decode([String].self, forKey: .emails) {
            emails = arr.filter { !$0.isEmpty }
        } else if let single = try? c.decode(String.self, forKey: .email), !single.isEmpty {
            emails = [single]
        } else {
            emails = []
        }
        faxes = (try? c.decode([String].self, forKey: .faxes))?.filter { !$0.isEmpty } ?? []
        address = (try? c.decode(String.self, forKey: .address)) ?? ""
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        date = (try? c.decode(Date.self, forKey: .date)) ?? Date()
        photoFileName = try? c.decodeIfPresent(String.self, forKey: .photoFileName)
        linkedOrgPersonId = try? c.decodeIfPresent(UUID.self, forKey: .linkedOrgPersonId)
        primaryBusiness = (try? c.decodeIfPresent(String.self, forKey: .primaryBusiness)) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(company, forKey: .company)
        try c.encode(department, forKey: .department)
        try c.encode(jobTitle, forKey: .jobTitle)
        try c.encode(phones, forKey: .phones)
        try c.encode(emails, forKey: .emails)
        try c.encode(faxes, forKey: .faxes)
        try c.encode(address, forKey: .address)
        try c.encode(note, forKey: .note)
        try c.encode(date, forKey: .date)
        try c.encodeIfPresent(photoFileName, forKey: .photoFileName)
        try c.encodeIfPresent(linkedOrgPersonId, forKey: .linkedOrgPersonId)
        try c.encode(primaryBusiness, forKey: .primaryBusiness)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, company, department, jobTitle
        case phone, email                                 // legacy 單值（讀取相容）
        case phones, emails, faxes                        // 新多值
        case address, note, date, photoFileName, linkedOrgPersonId
        case primaryBusiness
    }

    // MARK: - 名片頭像照片儲存

    static var photosDirectory: URL {
        let dir = (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("BusinessCardPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func savePhoto(_ data: Data, id: UUID) -> String {
        let name = "\(id.uuidString).jpg"
        let url = photosDirectory.appendingPathComponent(name)
        try? data.write(to: url)
        PhotoCloudSync.upload(directory: "BusinessCardPhotos", fileName: name)
        return name
    }

    static func deletePhoto(_ fileName: String) {
        let url = photosDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
        PhotoCloudSync.delete(directory: "BusinessCardPhotos", fileName: fileName)
    }

    var photoURL: URL? {
        guard let name = photoFileName else { return nil }
        return Self.photosDirectory.appendingPathComponent(name)
    }
}

// MARK: - 部門名稱

struct Department: Identifiable, Codable {
    let id: UUID
    var code: String
    var name: String
    var function: String
    var upstreamIds: [UUID]
    var downstreamIds: [UUID]
    /// 同層級部門（peer / 平行單位）
    var peerIds: [UUID]

    init(id: UUID = UUID(), code: String = "", name: String = "",
         function: String = "",
         upstreamIds: [UUID] = [],
         downstreamIds: [UUID] = [],
         peerIds: [UUID] = []) {
        self.id = id; self.code = code; self.name = name
        self.function = function
        self.upstreamIds = upstreamIds
        self.downstreamIds = downstreamIds
        self.peerIds = peerIds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        code = (try? c.decode(String.self, forKey: .code)) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        function = (try? c.decode(String.self, forKey: .function)) ?? ""
        upstreamIds = (try? c.decode([UUID].self, forKey: .upstreamIds)) ?? []
        downstreamIds = (try? c.decode([UUID].self, forKey: .downstreamIds)) ?? []
        peerIds = (try? c.decode([UUID].self, forKey: .peerIds)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, code, name, function, upstreamIds, downstreamIds, peerIds
    }
}

// MARK: - 公司組織人員

struct OrgPersonChild: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var birthday: Date?
    var note: String

    init(id: UUID = UUID(), name: String = "", birthday: Date? = nil, note: String = "") {
        self.id = id; self.name = name; self.birthday = birthday; self.note = note
    }
}

enum OrgRelationType: String, Codable, CaseIterable, Identifiable {
    case ally = "同盟"
    case neutral = "中立"
    case rival = "對手"
    case mentor = "前輩"
    case mentee = "後輩"
    case other = "其他"

    var id: String { rawValue }

    var color: String {
        switch self {
        case .ally: return "green"
        case .neutral: return "gray"
        case .rival: return "red"
        case .mentor: return "indigo"
        case .mentee: return "teal"
        case .other: return "secondary"
        }
    }
}

struct OrgPersonRelation: Identifiable, Codable, Equatable {
    let id: UUID
    var personId: UUID
    var type: OrgRelationType
    var note: String

    init(id: UUID = UUID(), personId: UUID, type: OrgRelationType = .neutral, note: String = "") {
        self.id = id; self.personId = personId; self.type = type; self.note = note
    }
}

struct OrgPerson: Identifiable, Codable {
    let id: UUID
    var name: String
    var jobTitle: String
    var departmentId: UUID?
    var photoFileName: String?
    var birthday: Date?
    /// 我與他的利害關係描述
    var relationship: String
    /// 相關記事
    var note: String
    var children: [OrgPersonChild]
    var relations: [OrgPersonRelation]
    var dateAdded: Date
    /// 是否離職
    var isInactive: Bool
    var leftDate: Date?
    /// 連結的名片 ID（雙向同步：BusinessCard.linkedOrgPersonId 也會指回來）
    var linkedBusinessCardId: UUID?
    /// 從職涯管理「部屬」自動連動產生的對應 ID（用於同步）
    var linkedSubordinateId: UUID?
    /// 連結的職等職稱 ID（讀取 lifeStore.gradeTitles），nil 代表使用 jobTitle 自訂文字
    var gradeTitleId: UUID?

    init(id: UUID = UUID(), name: String = "", jobTitle: String = "",
         departmentId: UUID? = nil, photoFileName: String? = nil,
         birthday: Date? = nil, relationship: String = "", note: String = "",
         children: [OrgPersonChild] = [], relations: [OrgPersonRelation] = [],
         dateAdded: Date = Date(),
         isInactive: Bool = false, leftDate: Date? = nil,
         linkedBusinessCardId: UUID? = nil,
         linkedSubordinateId: UUID? = nil,
         gradeTitleId: UUID? = nil) {
        self.id = id; self.name = name; self.jobTitle = jobTitle
        self.departmentId = departmentId; self.photoFileName = photoFileName
        self.birthday = birthday; self.relationship = relationship
        self.note = note; self.children = children; self.relations = relations
        self.dateAdded = dateAdded
        self.isInactive = isInactive; self.leftDate = leftDate
        self.linkedBusinessCardId = linkedBusinessCardId
        self.linkedSubordinateId = linkedSubordinateId
        self.gradeTitleId = gradeTitleId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        jobTitle = (try? c.decode(String.self, forKey: .jobTitle)) ?? ""
        departmentId = try? c.decodeIfPresent(UUID.self, forKey: .departmentId)
        photoFileName = try? c.decodeIfPresent(String.self, forKey: .photoFileName)
        birthday = try? c.decodeIfPresent(Date.self, forKey: .birthday)
        relationship = (try? c.decode(String.self, forKey: .relationship)) ?? ""
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        children = (try? c.decode([OrgPersonChild].self, forKey: .children)) ?? []
        relations = (try? c.decode([OrgPersonRelation].self, forKey: .relations)) ?? []
        dateAdded = (try? c.decode(Date.self, forKey: .dateAdded)) ?? Date()
        isInactive = (try? c.decode(Bool.self, forKey: .isInactive)) ?? false
        leftDate = try? c.decodeIfPresent(Date.self, forKey: .leftDate)
        linkedBusinessCardId = try? c.decodeIfPresent(UUID.self, forKey: .linkedBusinessCardId)
        linkedSubordinateId = try? c.decodeIfPresent(UUID.self, forKey: .linkedSubordinateId)
        gradeTitleId = try? c.decodeIfPresent(UUID.self, forKey: .gradeTitleId)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, jobTitle, departmentId, photoFileName, birthday
        case relationship, note, children, relations, dateAdded
        case isInactive, leftDate, linkedBusinessCardId, linkedSubordinateId, gradeTitleId
    }

    /// 主導關係：取所有 relations 中出現最多次的類型，沒有則 nil
    var dominantRelationType: OrgRelationType? {
        guard !relations.isEmpty else { return nil }
        var counts: [OrgRelationType: Int] = [:]
        for r in relations { counts[r.type, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    static var photosDirectory: URL {
        let dir = (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("OrgPersonPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func savePhoto(_ data: Data, id: UUID) -> String {
        let name = "\(id.uuidString).jpg"
        let url = photosDirectory.appendingPathComponent(name)
        try? data.write(to: url)
        PhotoCloudSync.upload(directory: "OrgPersonPhotos", fileName: name)
        return name
    }

    static func deletePhoto(_ fileName: String) {
        let url = photosDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
        PhotoCloudSync.delete(directory: "OrgPersonPhotos", fileName: fileName)
    }

    var photoURL: URL? {
        guard let name = photoFileName else { return nil }
        return Self.photosDirectory.appendingPathComponent(name)
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


// MARK: - 個人行事曆事件

enum PersonalEventKind: String, Codable, CaseIterable, Identifiable {
    case task = "事務"
    case meeting = "會議"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .task: return "checklist"
        case .meeting: return "person.3.fill"
        }
    }
}

/// 重複規則
enum EventRecurrence: String, Codable, CaseIterable, Identifiable {
    case none = "不重複"
    case daily = "每天"
    case weekly = "每週"
    case monthly = "每月"
    case yearly = "每年"

    var id: String { rawValue }
}

/// 事前提醒（單位：分鐘）
enum EventReminder: Int, Codable, CaseIterable, Identifiable {
    case none = -1
    case atTime = 0
    case minutes5 = 5
    case minutes15 = 15
    case minutes30 = 30
    case hour1 = 60
    case day1 = 1440

    var id: Int { rawValue }
    var displayName: String {
        switch self {
        case .none:      return "不提醒"
        case .atTime:    return "事件當下"
        case .minutes5:  return "5 分鐘前"
        case .minutes15: return "15 分鐘前"
        case .minutes30: return "30 分鐘前"
        case .hour1:     return "1 小時前"
        case .day1:      return "1 天前"
        }
    }
}

struct PersonalEvent: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var kind: PersonalEventKind
    var date: Date              // 開始日期時間
    var durationMinutes: Int    // 長度（分鐘），0 = 全日
    var note: String
    var recurrence: EventRecurrence
    var recurrenceEndDate: Date?    // 可選：重複結束日（含當天為最後一次）
    var reminderMinutes: Int        // -1 = 不提醒；0 = 事件當下；正整數 = N 分鐘前
    /// 地點（同步到 Apple 行事曆時對應 EKEvent.location）
    var location: String
    /// 是否同步到 Apple 行事曆
    var syncToAppleCalendar: Bool
    /// 寫入哪個 iOS 行事曆（EKCalendar.calendarIdentifier）
    var appleCalendarId: String?
    /// 已寫入的 EKEvent 識別碼，用於更新與刪除
    var ekEventIdentifier: String?

    init(id: UUID = UUID(),
         title: String = "",
         kind: PersonalEventKind = .meeting,
         date: Date = Date(),
         durationMinutes: Int = 30,
         note: String = "",
         recurrence: EventRecurrence = .none,
         recurrenceEndDate: Date? = nil,
         reminderMinutes: Int = EventReminder.none.rawValue,
         location: String = "",
         syncToAppleCalendar: Bool = false,
         appleCalendarId: String? = nil,
         ekEventIdentifier: String? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.date = date
        self.durationMinutes = durationMinutes
        self.note = note
        self.recurrence = recurrence
        self.recurrenceEndDate = recurrenceEndDate
        self.reminderMinutes = reminderMinutes
        self.location = location
        self.syncToAppleCalendar = syncToAppleCalendar
        self.appleCalendarId = appleCalendarId
        self.ekEventIdentifier = ekEventIdentifier
    }

    /// 向下相容：舊版 JSON 沒有 recurrence / reminder / Apple 同步欄位
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        kind = try c.decode(PersonalEventKind.self, forKey: .kind)
        date = try c.decode(Date.self, forKey: .date)
        durationMinutes = try c.decode(Int.self, forKey: .durationMinutes)
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        recurrence = (try? c.decode(EventRecurrence.self, forKey: .recurrence)) ?? .none
        recurrenceEndDate = try? c.decode(Date.self, forKey: .recurrenceEndDate)
        reminderMinutes = (try? c.decode(Int.self, forKey: .reminderMinutes)) ?? EventReminder.none.rawValue
        location = (try? c.decode(String.self, forKey: .location)) ?? ""
        syncToAppleCalendar = (try? c.decode(Bool.self, forKey: .syncToAppleCalendar)) ?? false
        appleCalendarId = try? c.decodeIfPresent(String.self, forKey: .appleCalendarId)
        ekEventIdentifier = try? c.decodeIfPresent(String.self, forKey: .ekEventIdentifier)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, kind, date, durationMinutes, note, recurrence, recurrenceEndDate, reminderMinutes
        case location, syncToAppleCalendar, appleCalendarId, ekEventIdentifier
    }

    /// 結束時間
    var endDate: Date {
        Calendar.current.date(byAdding: .minute, value: durationMinutes, to: date) ?? date
    }

    /// 此事件是否在指定日期發生（含重複展開）
    func occurs(on day: Date, calendar: Calendar = .current) -> Bool {
        let target = calendar.startOfDay(for: day)
        let start  = calendar.startOfDay(for: date)
        // 早於原始日期 → 不發生
        if target < start { return false }
        // 已過重複結束日 → 不發生
        if let endRec = recurrenceEndDate,
           target > calendar.startOfDay(for: endRec) { return false }

        switch recurrence {
        case .none:
            return calendar.isDate(target, inSameDayAs: start)
        case .daily:
            return true
        case .weekly:
            let comps = calendar.dateComponents([.day], from: start, to: target)
            return (comps.day ?? 0) % 7 == 0
        case .monthly:
            let dayOfMonth = calendar.component(.day, from: start)
            return calendar.component(.day, from: target) == dayOfMonth
        case .yearly:
            let m = calendar.component(.month, from: start)
            let d = calendar.component(.day, from: start)
            return calendar.component(.month, from: target) == m
                && calendar.component(.day, from: target) == d
        }
    }

    /// 計算指定日期的「實際」事件 datetime（保留時、分）
    func occurrenceDate(on day: Date, calendar: Calendar = .current) -> Date {
        let timeComp = calendar.dateComponents([.hour, .minute], from: date)
        var dayComp = calendar.dateComponents([.year, .month, .day], from: day)
        dayComp.hour = timeComp.hour
        dayComp.minute = timeComp.minute
        return calendar.date(from: dayComp) ?? date
    }
}
