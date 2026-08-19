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

    /// 是否完全空白（供匯入合併模式判斷是否可安全覆蓋，避免清空使用者既有的個人資料）
    var isEmpty: Bool {
        chineseName.isEmpty && englishName.isEmpty && company.isEmpty && jobTitle.isEmpty && spouse.isEmpty
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

// MARK: - 配偶協定
//
// 「跟配偶談好的事」——一次性的約定（今年不買車）、家事分工（垃圾我倒）、
// 財務約定（每月家用各出三萬）。掛在 FamilyMember 底下，所以協定跟著人走。
//
// ⚠️ 以下四個列舉的 rawValue 一律用英文識別字。
//    這是 CareerSubCategory 的教訓：它把中文字面值當 rawValue，等於把顯示名稱
//    一起凍住了——想把「調薪」改成「薪資調整」就會讓所有舊資料解不出子分類。
//    識別字凍結、顯示名稱走 title，隨時可以改。

enum SpouseAgreementCategory: String, Codable, CaseIterable, Identifiable {
    case chore, finance, living, parenting, majorDecision, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .chore:         return "家事分工"
        case .finance:       return "財務"
        case .living:        return "生活"
        case .parenting:     return "育兒"
        case .majorDecision: return "重大決定"
        case .other:         return "其他"
        }
    }

    var icon: String {
        switch self {
        case .chore:         return "house.fill"
        case .finance:       return "dollarsign.circle.fill"
        case .living:        return "sun.max.fill"
        case .parenting:     return "figure.and.child.holdinghands"
        case .majorDecision: return "star.fill"
        case .other:         return "text.bubble.fill"
        }
    }

    /// 這個分類預設要不要顯示「負責方」與「金額」欄位。
    /// 只是預設值，表單上仍可自由開關——家事分工也可能有金額（請鐘點的費用）。
    var suggestsParty: Bool { self == .chore || self == .parenting }
    var suggestsAmount: Bool { self == .finance }
}

/// 誰負責。用於家事分工。
enum SpouseAgreementParty: String, Codable, CaseIterable, Identifiable {
    case me, partner, both
    var id: String { rawValue }

    var title: String {
        switch self {
        case .me:      return "我"
        case .partner: return "對方"
        case .both:    return "雙方"
        }
    }

    var icon: String {
        switch self {
        case .me:      return "person.fill"
        case .partner: return "person.fill.checkmark"
        case .both:    return "person.2.fill"
        }
    }
}

enum SpouseAgreementStatus: String, Codable, CaseIterable, Identifiable {
    case active, done, void
    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return "進行中"
        case .done:   return "已完成"
        case .void:   return "已作廢"
        }
    }
}

/// 週期。家事分工的「每天倒垃圾」與財務的「每月家用」都用得到。
enum SpouseAgreementCadence: String, Codable, CaseIterable, Identifiable {
    case oneTime, perTime, daily, weekly, monthly, yearly
    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneTime: return "一次性"
        case .perTime: return "每次"
        case .daily:   return "每天"
        case .weekly:  return "每週"
        case .monthly: return "每月"
        case .yearly:  return "每年"
        }
    }
}

/// 一則與配偶的協定。
/// 解碼紀律同兼任職務的子項目：除 id 外一律 decodeIfPresent + 預設值——
/// 這是掛在 FamilyMember 底下的陣列元素，任何一欄硬 decode 失敗，
/// 使用者失去的是整位家庭成員（連同小孩的成長紀錄與照片），不只是一則協定。
struct SpouseAgreement: Identifiable, Codable {
    let id: UUID
    /// 協定內容（例：今年不買車、垃圾我倒、每月家用各出三萬）
    var title: String
    var category: SpouseAgreementCategory
    /// 談定的日期
    var agreedDate: Date
    var status: SpouseAgreementStatus
    /// 詳細說明／前因後果
    var detail: String
    /// 誰負責；nil 代表這則協定沒有分工概念
    var party: SpouseAgreementParty?
    /// 金額（NT$）；nil 代表這則協定沒有金額
    var amount: Double?
    /// 週期；nil 代表沒特別指定
    var cadence: SpouseAgreementCadence?
    var note: String

    init(id: UUID = UUID(), title: String = "",
         category: SpouseAgreementCategory = .living,
         agreedDate: Date = Date(),
         status: SpouseAgreementStatus = .active,
         detail: String = "",
         party: SpouseAgreementParty? = nil,
         amount: Double? = nil,
         cadence: SpouseAgreementCadence? = nil,
         note: String = "") {
        self.id = id; self.title = title; self.category = category
        self.agreedDate = agreedDate; self.status = status; self.detail = detail
        self.party = party; self.amount = amount; self.cadence = cadence; self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        category = (try? c.decodeIfPresent(SpouseAgreementCategory.self, forKey: .category)) ?? .living
        agreedDate = (try? c.decodeIfPresent(Date.self, forKey: .agreedDate)) ?? Date()
        status = (try? c.decodeIfPresent(SpouseAgreementStatus.self, forKey: .status)) ?? .active
        detail = (try? c.decodeIfPresent(String.self, forKey: .detail)) ?? ""
        party = try? c.decodeIfPresent(SpouseAgreementParty.self, forKey: .party)
        amount = try? c.decodeIfPresent(Double.self, forKey: .amount)
        cadence = try? c.decodeIfPresent(SpouseAgreementCadence.self, forKey: .cadence)
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, category, agreedDate, status, detail, party, amount, cadence, note
    }

    /// 卡片副標：「每月 · NT$30,000」「雙方 · 每週」
    var subtitleText: String {
        var parts: [String] = []
        if let party { parts.append(party.title) }
        if let cadence { parts.append(cadence.title) }
        if let amount, amount > 0 {
            parts.append("NT$" + (NumberFormatter.spouseAgreementAmount
                .string(from: NSNumber(value: amount)) ?? String(Int(amount))))
        }
        return parts.joined(separator: " · ")
    }
}

extension NumberFormatter {
    /// 協定金額用的千分位格式（整數）
    static let spouseAgreementAmount: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()
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
    /// 兒童疫苗接種狀態（對應 VaccineSchedule.taiwan 的各劑次；有施打日期＝已完成）
    var vaccinations: [VaccineDose]
    /// 與這位家人談定的協定（目前只有配偶頁在用，掛在 FamilyMember 上讓它跟著人走）
    var agreements: [SpouseAgreement]?

    init(id: UUID = UUID(), role: FamilyMemberRole = .spouse,
         chineseName: String = "", englishName: String = "",
         birthday: Date? = nil,
         marriageDate: Date? = nil, isDivorced: Bool = false, divorceDate: Date? = nil,
         childRecords: [ChildRecord] = [], dailyRecords: [DailyRecord] = [],
         birthYear: Int? = nil, idNumber: String? = nil, relativeNote: String? = nil,
         familyEvents: [FamilyEvent] = [], familyPhotos: [FamilyAlbumPhoto] = [],
         familySide: FamilySide? = nil, spouseId: UUID? = nil,
         vaccinations: [VaccineDose] = []) {
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
        self.vaccinations = vaccinations
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
        vaccinations = (try? c.decodeIfPresent([VaccineDose].self, forKey: .vaccinations)) ?? []
        agreements = try? c.decodeIfPresent([SpouseAgreement].self, forKey: .agreements)
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
        try c.encode(vaccinations, forKey: .vaccinations)
        // ⚠️ FamilyMember 與 LifeMilestone 不同，它有自訂 encode(to:)。
        //    漏了這一行，協定永遠寫不進 JSON——而且完全不會編譯錯，
        //    只會在殺掉 App 重開後靜默消失。
        try c.encodeIfPresent(agreements, forKey: .agreements)
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, chineseName, englishName, birthday, marriageDate, isDivorced, divorceDate, childRecords, dailyRecords
        case birthYear, idNumber, relativeNote, familyEvents, familyPhotos
        case familySide, spouseId, vaccinations
        case agreements
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

    static func savePhoto(_ data: Data, id: UUID) -> String? {
        let data = ImageCompressor.compressForStorage(data)   // 存檔前統一壓縮：1080P 長邊 + JPEG 80%
        let name = "\(id.uuidString).jpg"
        let url = photosDirectory.appendingPathComponent(name)
        guard (try? data.write(to: url)) != nil else { return nil }
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
    /// 就醫記錄體溫（°C，選填）：合成 Codable 的 Optional 欄位缺 key 時自動為 nil，舊資料相容
    var temperatureC: Double?

    init(id: UUID = UUID(), type: ChildRecordType = .memorable,
         date: Date = Date(), title: String = "", detail: String = "", note: String = "",
         heightCm: Double? = nil, weightKg: Double? = nil,
         dose: String? = nil, severity: AllergySeverity? = nil,
         photoFileName: String? = nil, temperatureC: Double? = nil) {
        self.id = id; self.type = type; self.date = date
        self.title = title; self.detail = detail; self.note = note
        self.heightCm = heightCm; self.weightKg = weightKg
        self.dose = dose; self.severity = severity
        self.photoFileName = photoFileName
        self.temperatureC = temperatureC
    }

    var photoURL: URL? {
        guard let name = photoFileName else { return nil }
        return Self.photosDirectory.appendingPathComponent(name)
    }

    static var photosDirectory: URL {
        let dir = (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("ChildRecordPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func savePhoto(_ data: Data, id: UUID) -> String? {
        let data = ImageCompressor.compressForStorage(data)   // 存檔前統一壓縮：1080P 長邊 + JPEG 80%
        let name = "\(id.uuidString).jpg"
        guard (try? data.write(to: photosDirectory.appendingPathComponent(name))) != nil else { return nil }
        PhotoCloudSync.upload(directory: "ChildRecordPhotos", fileName: name)
        return name
    }

    static func deletePhoto(_ fileName: String) {
        try? FileManager.default.removeItem(at: photosDirectory.appendingPathComponent(fileName))
        PhotoCloudSync.delete(directory: "ChildRecordPhotos", fileName: fileName)
        // 素描功能已移除（v25.167），但舊版可能留有 *_sketch.jpg 伴生檔：刪照片時一併清掉
        let sketchName = fileName.replacingOccurrences(of: ".jpg", with: "_sketch.jpg")
        try? FileManager.default.removeItem(at: photosDirectory.appendingPathComponent(sketchName))
        PhotoCloudSync.delete(directory: "ChildRecordPhotos", fileName: sketchName)
    }

    /// 一次性清除既有素描伴生檔（素描功能移除後的善後）：本機 *_sketch.jpg 連同雲端記錄一併刪除，
    /// 釋放本機空間並停止這些檔案繼續佔用 iCloud 同步流量。旗標守衛，僅執行一次。
    static func purgeLegacySketchFiles() {
        let flag = "child_sketch_purged_v1"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)
        DispatchQueue.global(qos: .utility).async {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: photosDirectory.path) else { return }
            for f in files where f.hasSuffix("_sketch.jpg") {
                try? FileManager.default.removeItem(at: photosDirectory.appendingPathComponent(f))
                PhotoCloudSync.delete(directory: "ChildRecordPhotos", fileName: f)
            }
        }
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
    /// 與本職並行的額外職務（例：副理同時兼任氣體化學執行秘書、尾牙負責人）。
    ///
    /// ⚠️ rawValue 刻意用英文識別字，與上面六個舊 case 的中文 rawValue 不同——
    /// rawValue 會直接寫進 iCloud 與備份 JSON，上線後永久凍結；舊 case 當年
    /// 把中文字面值當識別字用，等於把「顯示名稱」也一起凍住了（想把「調薪」
    /// 改成「薪資調整」就會讓所有舊資料解不出子分類）。新 case 不重蹈覆轍：
    /// 識別字凍結、顯示名稱走下面的 title，隨時可以改。
    case sideRole = "sideRole"
    var id: String { rawValue }

    /// 畫面上顯示的名稱。舊 case 的 rawValue 本身就是中文所以直接回傳，
    /// 新 case 一律在這裡給中文——不要再讓 rawValue 兼任顯示字串。
    var title: String {
        switch self {
        case .sideRole: return "兼任"
        default:        return rawValue
        }
    }

    var icon: String {
        switch self {
        case .join: return "arrow.right.to.line"
        case .promote: return "arrow.up.circle.fill"
        case .salaryAdjust: return "dollarsign.arrow.circlepath"
        case .transfer: return "arrow.left.arrow.right"
        case .demote: return "arrow.down.circle.fill"
        case .resign: return "arrow.right.square"
        case .sideRole: return "person.badge.plus"
        }
    }

    /// 期間型子分類（有起訖），與其餘「事件點」型不同。
    /// 職涯統計要把兩者分開算，否則年資與異動次數會失真。
    var isPeriodType: Bool { self == .sideRole }
}

// MARK: - 兼任職務的管理頁資料
//
// 四個型別共同的解碼紀律：**除了 id 以外一律 decodeIfPresent + 預設值**。
// 理由不是潔癖：LifeStore.load() 的容錯粒度是「一筆 LifeMilestone」，
// 這些 struct 是掛在 milestone 底下的陣列元素，任何一欄硬 decode 失敗，
// 使用者失去的是整筆職涯里程碑，不只是一則待辦。
//
// 也因此刻意「不」複用既有的 SubordinateMeeting／SubordinateTask：
// 那兩個是 Swift 合成解碼（沒有自訂 init(from:)），缺一個 key 就整筆炸掉。
// 複用等於把那個脆弱點接到兼任職務上。

/// 兼任待辦 ↔ 部屬紀錄的連結（兼任這一側）。
///
/// 兩側都存一份指標，是刻意的：只存單側的話，另一側要找對象就得掃全部人／
/// 全部兼任職務，而完成狀態同步是在每次打勾時觸發的熱路徑。
struct SideRoleTaskLink: Codable, Hashable {
    enum Kind: String, Codable { case task, meetingItem }
    var kind: Kind
    var subordinateId: UUID
    /// SubordinateTask.id 或 MeetingItem.id
    var itemId: UUID
    /// kind == .meetingItem 才有值
    var meetingId: UUID?
    /// true＝指派時由系統自動建立的部屬任務（刪兼任待辦時一併刪掉）；
    /// false＝從部屬那邊既有的紀錄拉進來的（刪兼任待辦時只解除連結，
    /// 那筆紀錄本來就存在，不該替使用者刪掉）。
    var isAutoCreated: Bool

    init(kind: Kind, subordinateId: UUID, itemId: UUID,
         meetingId: UUID? = nil, isAutoCreated: Bool) {
        self.kind = kind; self.subordinateId = subordinateId
        self.itemId = itemId; self.meetingId = meetingId; self.isAutoCreated = isAutoCreated
    }

    enum CodingKeys: String, CodingKey { case kind, subordinateId, itemId, meetingId, isAutoCreated }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .task
        subordinateId = try c.decode(UUID.self, forKey: .subordinateId)
        itemId = try c.decode(UUID.self, forKey: .itemId)
        meetingId = try? c.decodeIfPresent(UUID.self, forKey: .meetingId)
        isAutoCreated = (try? c.decodeIfPresent(Bool.self, forKey: .isAutoCreated)) ?? false
    }
}

/// 部屬紀錄 ↔ 兼任待辦的回指（部屬這一側）。
/// 有值代表「這件事同時是某個兼任職務的待辦」——完成狀態雙向同步，
/// 而且**評分只算一次**（走兼任那邊的 +3，本職這邊跳過）。
struct SideRoleBackLink: Codable, Hashable {
    /// 兼任職務（LifeMilestone）的 id
    var roleId: UUID
    /// SideRoleTask 的 id
    var taskId: UUID

    init(roleId: UUID, taskId: UUID) { self.roleId = roleId; self.taskId = taskId }

    enum CodingKeys: String, CodingKey { case roleId, taskId }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        roleId = try c.decode(UUID.self, forKey: .roleId)
        taskId = try c.decode(UUID.self, forKey: .taskId)
    }
}

/// 兼任職務的待辦事項
struct SideRoleTask: Identifiable, Codable {
    let id: UUID
    var content: String
    var dueDate: Date?
    var isCompleted: Bool
    var completedAt: Date?
    var note: String
    /// 與部屬任務／會議議程項目的連結（同一件事的另一面）
    var links: [SideRoleTaskLink]?
    /// 負責這則待辦的成員（對應同一筆兼任職務底下 SideRoleMember.id）。
    /// 用陣列而非單一 id：一件事常常是兩三個人一起扛，而單人只是「陣列長度 1」，
    /// 反過來用單一欄位就表達不了多人。nil／空陣列＝尚未指派。
    var assigneeIds: [UUID]?
    /// 成員名單之外的負責人（文字快照，比照出席者）：手動輸入或從全公司
    /// 人員清單挑進來的人。**不參與**部屬任務自動建立與評分——那條管線
    /// 靠成員的 linkedPersonId，文字快照連不回本人。
    var extraAssignees: [String]?
    /// 系統分類（與重大決議共用同一組代碼；空＝未分類）
    var categories: [SideRoleResolutionCategory]

    init(id: UUID = UUID(), content: String = "", dueDate: Date? = nil,
         isCompleted: Bool = false, completedAt: Date? = nil, note: String = "",
         assigneeIds: [UUID]? = nil, links: [SideRoleTaskLink]? = nil,
         extraAssignees: [String]? = nil, categories: [SideRoleResolutionCategory] = []) {
        self.id = id; self.content = content; self.dueDate = dueDate
        self.isCompleted = isCompleted; self.completedAt = completedAt; self.note = note
        self.assigneeIds = assigneeIds; self.links = links
        self.extraAssignees = extraAssignees; self.categories = categories
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // id 用 try? 而非硬 decode：id 壞掉時寧可生一個新的，也不要讓整筆
        // 職涯里程碑被 lossyDecodeArray 丟掉。代價是兩台裝置各自解一次會產生
        // 不同 id——但那只發生在資料本來就已經損壞的情況。
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        content = (try? c.decodeIfPresent(String.self, forKey: .content)) ?? ""
        dueDate = try? c.decodeIfPresent(Date.self, forKey: .dueDate)
        isCompleted = (try? c.decodeIfPresent(Bool.self, forKey: .isCompleted)) ?? false
        completedAt = try? c.decodeIfPresent(Date.self, forKey: .completedAt)
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        assigneeIds = try? c.decodeIfPresent([UUID].self, forKey: .assigneeIds)
        links = try? c.decodeIfPresent([SideRoleTaskLink].self, forKey: .links)
        extraAssignees = try? c.decodeIfPresent([String].self, forKey: .extraAssignees)
        categories = (try? c.decodeIfPresent([SideRoleResolutionCategory].self, forKey: .categories)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, content, dueDate, isCompleted, completedAt, note, assigneeIds, links,
             extraAssignees, categories
    }
}

/// 兼任職務的相關人員（例：尾牙負責人底下的場控、攝影、各組窗口）。
/// name 一律存文字快照，linkedPersonId 只是「額外」的連結：兼任團隊常含
/// 跨部門或外部人員，只存 UUID 的話對方被刪除後名單會變成空白列。
struct SideRoleMember: Identifiable, Codable {
    let id: UUID
    var name: String
    /// 在本職務中的分工，如「場控」「攝影」「總務」
    var dutyInRole: String
    var contact: String
    /// 對應部屬或名片的 id；外部人員為 nil
    var linkedPersonId: UUID?
    var note: String

    init(id: UUID = UUID(), name: String = "", dutyInRole: String = "",
         contact: String = "", linkedPersonId: UUID? = nil, note: String = "") {
        self.id = id; self.name = name; self.dutyInRole = dutyInRole
        self.contact = contact; self.linkedPersonId = linkedPersonId; self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        dutyInRole = (try? c.decodeIfPresent(String.self, forKey: .dutyInRole)) ?? ""
        contact = (try? c.decodeIfPresent(String.self, forKey: .contact)) ?? ""
        linkedPersonId = try? c.decodeIfPresent(UUID.self, forKey: .linkedPersonId)
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, dutyInRole, contact, linkedPersonId, note
    }
}

/// 兼任職務的會議紀錄。
/// 欄位比照 SubordinateMeeting 的語意，但解碼全部容錯——見本區塊開頭的說明。
struct SideRoleMeeting: Identifiable, Codable {
    let id: UUID
    var date: Date
    var topic: String
    /// 出席者姓名（文字快照，不綁 id：外部與會者很常見）
    var attendees: [String]
    /// 決議事項
    var decisions: String
    var note: String

    init(id: UUID = UUID(), date: Date = Date(), topic: String = "",
         attendees: [String] = [], decisions: String = "", note: String = "") {
        self.id = id; self.date = date; self.topic = topic
        self.attendees = attendees; self.decisions = decisions; self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        date = (try? c.decodeIfPresent(Date.self, forKey: .date)) ?? Date()
        topic = (try? c.decodeIfPresent(String.self, forKey: .topic)) ?? ""
        attendees = (try? c.decodeIfPresent([String].self, forKey: .attendees)) ?? []
        decisions = (try? c.decodeIfPresent(String.self, forKey: .decisions)) ?? ""
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, topic, attendees, decisions, note
    }
}

/// 重大決議的系統分類（使用者指定的廠務系統代碼）。
/// rawValue 即代碼本身（英文、穩定），顯示直接用代碼——這批本來就是縮寫術語。
enum SideRoleResolutionCategory: String, Codable, CaseIterable, Identifiable {
    case cda = "CDA"
    case bgs = "BGS"
    case sgs = "SGS"
    case chm = "CHM"
    case mix = "MIX"
    case waste = "Waste"
    case slurry = "Slurry"
    case gis = "GIS"
    case cis = "CIS"
    case esh = "ESH"
    case other = "Other"
    var id: String { rawValue }
}

/// 兼任職務的重大決議（例：預算核定、場地定案）。
/// 與會議紀錄裡的「決議事項」不同：這是跨會議、值得單獨列出來查的定案，
/// 有自己的標題、內容與系統分類，會被「我的行事曆」搜尋索引到（含分類代碼）。
struct SideRoleResolution: Identifiable, Codable {
    let id: UUID
    var date: Date
    var title: String
    var content: String
    /// 系統分類（可多選；空陣列＝未分類）。一則決議常橫跨多個系統
    ///（例：廢水處理動到 Waste + CHM），單選表達不了。
    var categories: [SideRoleResolutionCategory]
    /// 決議發起人。文字快照（比照出席者）：發起人常是跨部門或外部的人，
    /// 存 id 的話對方被刪除就變空白；可手動輸入、也可從人員清單挑
    var initiator: String

    init(id: UUID = UUID(), date: Date = Date(), title: String = "", content: String = "",
         categories: [SideRoleResolutionCategory] = [], initiator: String = "") {
        self.id = id; self.date = date; self.title = title; self.content = content
        self.categories = categories; self.initiator = initiator
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        date = (try? c.decodeIfPresent(Date.self, forKey: .date)) ?? Date()
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        content = (try? c.decodeIfPresent(String.self, forKey: .content)) ?? ""
        if let list = try? c.decodeIfPresent([SideRoleResolutionCategory].self, forKey: .categories) {
            categories = list
        } else if let legacy = try? decoder.container(keyedBy: LegacyKeys.self),
                  let single = try? legacy.decodeIfPresent(SideRoleResolutionCategory.self, forKey: .category) {
            // 升級遷移：v25.249~251 的單選分類收進多選陣列
            categories = [single]
        } else {
            categories = []
        }
        initiator = (try? c.decodeIfPresent(String.self, forKey: .initiator)) ?? ""
    }

    private enum CodingKeys: String, CodingKey { case id, date, title, content, categories, initiator }
    /// 舊版單選分類。獨立 CodingKey 讓 encode 仍可用合成版
    ///（CodingKeys 出現沒有對應屬性的 case 會讓合成的 encode 編不過）。
    private enum LegacyKeys: String, CodingKey { case category }
}

/// 兼任職務的重要日期（例：尾牙的場勘日、彩排日、正式日）。
/// 會同步顯示在「我的行事曆」上。
struct SideRoleKeyDate: Identifiable, Codable {
    let id: UUID
    var date: Date
    var title: String
    /// 提前幾天提醒；0 代表當天、nil 代表不提醒
    var remindDaysBefore: Int?
    var note: String

    init(id: UUID = UUID(), date: Date = Date(), title: String = "",
         remindDaysBefore: Int? = nil, note: String = "") {
        self.id = id; self.date = date; self.title = title
        self.remindDaysBefore = remindDaysBefore; self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        date = (try? c.decodeIfPresent(Date.self, forKey: .date)) ?? Date()
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        remindDaysBefore = try? c.decodeIfPresent(Int.self, forKey: .remindDaysBefore)
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, title, remindDaysBefore, note
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

    // 兼任職務專屬欄位（careerSubCategory == .sideRole 時才有值）
    //
    // 就任日沿用 LifeMilestone.date。「同時兼任多個職務」＝多筆里程碑，
    // 不是一筆裡塞陣列——後者無法表達各自的起訖與各自的管理頁。
    //
    // 這些欄位刻意不進 memberwise init 的參數列（比照既有的 bankDeposits /
    // isDisabled / easyCardNumber），那個 init 已經有 30 餘個參數，
    // 再膨脹會加重 SwiftUI 呼叫端的型別推導負擔。
    /// 兼任職務名稱（例：氣體化學執行秘書、尾牙負責人）
    var sideRoleName: String?
    /// 主辦單位（例：台灣氣體化學工業協會、員工福委會）。
    /// 刻意不寫進 companyName——那個欄位是 LifeStore.myCurrentCompany 判斷
    /// 「我目前在哪家公司」的依據，名片與公司組織都靠它，污染了會連鎖出錯。
    var sideRoleOrg: String?
    /// 卸任日；nil 代表仍在任
    var sideRoleEndDate: Date?
    /// 是否為此職務的主責者（使用者口中的「額外職務仲裁者」）；false / nil＝協辦或掛名
    var sideRoleIsLead: Bool?
    /// 負責範圍
    var sideRoleScope: String?
    /// 是否為這筆兼任職務啟用專屬管理頁面。
    /// 關閉只隱藏入口，底下的待辦／成員／會議／重要日期永遠原樣保留。
    var sideRoleWorkspaceEnabled: Bool?
    /// 專屬管理頁：待辦
    var sideRoleTasks: [SideRoleTask]?
    /// 專屬管理頁：成員名單
    var sideRoleMembers: [SideRoleMember]?
    /// 專屬管理頁：會議紀錄
    var sideRoleMeetings: [SideRoleMeeting]?
    /// 專屬管理頁：重要日期（會同步到我的行事曆）
    var sideRoleKeyDates: [SideRoleKeyDate]?
    /// 兼任職務的重大決議（放在會議紀錄下方）
    var sideRoleResolutions: [SideRoleResolution]?

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
        // 兼任職務
        sideRoleName = try? c.decodeIfPresent(String.self, forKey: .sideRoleName)
        sideRoleOrg = try? c.decodeIfPresent(String.self, forKey: .sideRoleOrg)
        sideRoleEndDate = try? c.decodeIfPresent(Date.self, forKey: .sideRoleEndDate)
        sideRoleIsLead = try? c.decodeIfPresent(Bool.self, forKey: .sideRoleIsLead)
        sideRoleScope = try? c.decodeIfPresent(String.self, forKey: .sideRoleScope)
        sideRoleWorkspaceEnabled = try? c.decodeIfPresent(Bool.self, forKey: .sideRoleWorkspaceEnabled)
        sideRoleTasks = try? c.decodeIfPresent([SideRoleTask].self, forKey: .sideRoleTasks)
        sideRoleMembers = try? c.decodeIfPresent([SideRoleMember].self, forKey: .sideRoleMembers)
        sideRoleMeetings = try? c.decodeIfPresent([SideRoleMeeting].self, forKey: .sideRoleMeetings)
        sideRoleKeyDates = try? c.decodeIfPresent([SideRoleKeyDate].self, forKey: .sideRoleKeyDates)
        sideRoleResolutions = try? c.decodeIfPresent([SideRoleResolution].self, forKey: .sideRoleResolutions)
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
        // ⚠️ 這五行與上面 init(from:) 的十行必須成對存在。
        //    本型別有自訂 init(from:) 與顯式 CodingKeys 但沒有自訂 encode(to:)，
        //    所以編碼走合成版、只認 CodingKeys；漏在這裡加＝新欄位永遠寫不進
        //    JSON，而且完全不會編譯錯，只會在殺掉 App 重開後靜默丟失。
        case sideRoleName, sideRoleOrg, sideRoleEndDate, sideRoleIsLead
        case sideRoleScope, sideRoleWorkspaceEnabled
        case sideRoleTasks, sideRoleMembers, sideRoleMeetings, sideRoleKeyDates, sideRoleResolutions
    }

    // MARK: 兼任職務便利屬性

    /// 這筆是不是兼任職務
    var isSideRole: Bool { careerSubCategory == .sideRole }

    /// 是否仍在任（沒填卸任日，或卸任日還沒到）
    var isActiveSideRole: Bool {
        guard isSideRole else { return false }
        guard let end = sideRoleEndDate else { return true }
        return end >= Calendar.current.startOfDay(for: Date())
    }

    /// 這筆兼任職務是否已啟用專屬管理頁（必須同時是主責者）。
    /// 「關閉開關」只讓這個回 false、隱藏入口，底下的資料一律原樣保留。
    var hasSideRoleWorkspace: Bool {
        isSideRole && sideRoleIsLead == true && sideRoleWorkspaceEnabled == true
    }

    /// 管理頁裡已經累積了多少內容。用來在關閉開關時據實告訴使用者「保留了什麼」，
    /// 而不是只給一句沒有憑據的「資料會保留」。
    var sideRoleContentCount: (tasks: Int, members: Int, meetings: Int, keyDates: Int, resolutions: Int) {
        (sideRoleTasks?.count ?? 0, sideRoleMembers?.count ?? 0,
         sideRoleMeetings?.count ?? 0, sideRoleKeyDates?.count ?? 0,
         sideRoleResolutions?.count ?? 0)
    }

    var hasAnySideRoleContent: Bool {
        let c = sideRoleContentCount
        return c.tasks + c.members + c.meetings + c.keyDates + c.resolutions > 0
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
        // Calendar.date(from:) 對超出目標月天數的 day（如小月填 31 日）不會回傳 nil，
        // 而是靜默溢位到下個月，導致扣款日與月份彙總跑到錯誤的月份。
        // 比照 MyCalendarView.annualOccurrence 的做法，先把 day 截至目標月實際天數。
        if let refDate = calendar.date(from: DateComponents(year: components.year, month: components.month, day: 1)) {
            let maxDay = calendar.range(of: .day, in: .month, for: refDate)?.count ?? payDay
            components.day = min(payDay, maxDay)
        } else {
            components.day = payDay
        }
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

    /// 不列入主動性扣分的假別（非個人意願的假：喪假／公假）
    var isScoreExempt: Bool { self == .funeral || self == .official }
}

// MARK: - 班別（部屬班表）

enum ShiftType: String, Codable, CaseIterable, Identifiable {
    case nightShift = "大夜班"
    case eveningShift = "小夜班"
    case holidayDuty = "假日值班"
    case dayDuty = "日值班"
    case jetLagLeave = "時差假"
    case restDay = "休息"

    var id: String { rawValue }

    /// 是否有上下班時間（時差假 / 休息沒有）
    var hasWorkTime: Bool {
        self == .nightShift || self == .eveningShift || self == .holidayDuty || self == .dayDuty
    }

    /// 班表格子上的精簡標示
    var shortLabel: String {
        switch self {
        case .nightShift:  return "大夜"
        case .eveningShift: return "小夜"
        case .holidayDuty:  return "假值"
        case .dayDuty:      return "日值"
        case .jetLagLeave:  return "時差"
        case .restDay:      return "休"
        }
    }
}

/// 某位部屬在某一天的班別指派（以 date 的當日比對）
struct SubordinateShift: Identifiable, Codable {
    let id: UUID
    var date: Date
    var type: ShiftType

    init(id: UUID = UUID(), date: Date, type: ShiftType) {
        self.id = id; self.date = date; self.type = type
    }
}

/// 班別時間（以「距離午夜的分鐘數」儲存，0...1439；跨夜時 end 可能小於 start）
struct ShiftTimeRange: Codable, Equatable {
    var startMinutes: Int
    var endMinutes: Int

    static func hhmm(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
    var display: String { "\(Self.hhmm(startMinutes))–\(Self.hhmm(endMinutes))" }
}

/// 可自訂的班別時間表（平日 / 假日各一組；僅 hasWorkTime 的班別需要）
struct ShiftSchedule: Codable {
    var weekday: [String: ShiftTimeRange]   // key = ShiftType.rawValue
    var holiday: [String: ShiftTimeRange]
    var rest: [String: ShiftTimeRange]      // 休息時間（不分平假日）；用於請假時數自動扣除

    func range(for type: ShiftType, isHoliday: Bool) -> ShiftTimeRange? {
        (isHoliday ? holiday : weekday)[type.rawValue]
    }
    mutating func set(_ range: ShiftTimeRange, for type: ShiftType, isHoliday: Bool) {
        if isHoliday { holiday[type.rawValue] = range } else { weekday[type.rawValue] = range }
    }
    /// 該班別的休息時間（可自訂；請假時數會自動扣除與休息時段重疊的部分）
    func restRange(for type: ShiftType) -> ShiftTimeRange? { rest[type.rawValue] }
    mutating func setRest(_ range: ShiftTimeRange, for type: ShiftType) { rest[type.rawValue] = range }

    init(weekday: [String: ShiftTimeRange], holiday: [String: ShiftTimeRange],
         rest: [String: ShiftTimeRange] = ShiftSchedule.defaultRest) {
        self.weekday = weekday; self.holiday = holiday; self.rest = rest
    }

    // 容錯解碼：rest 為後加欄位，舊存檔沒有此 key，缺少時套用預設休息時間
    enum CodingKeys: String, CodingKey { case weekday, holiday, rest }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weekday = (try? c.decode([String: ShiftTimeRange].self, forKey: .weekday)) ?? ShiftSchedule.default.weekday
        holiday = (try? c.decode([String: ShiftTimeRange].self, forKey: .holiday)) ?? ShiftSchedule.default.holiday
        rest = (try? c.decode([String: ShiftTimeRange].self, forKey: .rest)) ?? ShiftSchedule.defaultRest
    }

    /// 預設休息時間：日值班 / 假日值班 12:00–13:00；小夜班 17:30–18:30（大夜班預設無）
    static let defaultRest: [String: ShiftTimeRange] = [
        ShiftType.dayDuty.rawValue:      ShiftTimeRange(startMinutes: 12 * 60,      endMinutes: 13 * 60),      // 12:00–13:00
        ShiftType.holidayDuty.rawValue:  ShiftTimeRange(startMinutes: 12 * 60,      endMinutes: 13 * 60),      // 12:00–13:00
        ShiftType.eveningShift.rawValue: ShiftTimeRange(startMinutes: 17 * 60 + 30, endMinutes: 18 * 60 + 30)  // 17:30–18:30
    ]

    static let `default` = ShiftSchedule(
        weekday: [
            ShiftType.nightShift.rawValue:   ShiftTimeRange(startMinutes: 0,    endMinutes: 8 * 60 + 30),   // 00:00–08:30
            ShiftType.eveningShift.rawValue: ShiftTimeRange(startMinutes: 16 * 60, endMinutes: 0),          // 16:00–00:00
            ShiftType.holidayDuty.rawValue:  ShiftTimeRange(startMinutes: 8 * 60 + 30, endMinutes: 17 * 60 + 30), // 08:30–17:30
            ShiftType.dayDuty.rawValue:      ShiftTimeRange(startMinutes: 8 * 60 + 30, endMinutes: 17 * 60 + 30)  // 08:30–17:30
        ],
        holiday: [
            ShiftType.nightShift.rawValue:   ShiftTimeRange(startMinutes: 20 * 60 + 30, endMinutes: 8 * 60 + 30), // 20:30–08:30
            ShiftType.eveningShift.rawValue: ShiftTimeRange(startMinutes: 12 * 60, endMinutes: 20 * 60 + 30),     // 12:00–20:30
            ShiftType.holidayDuty.rawValue:  ShiftTimeRange(startMinutes: 8 * 60 + 30, endMinutes: 20 * 60 + 30), // 08:30–20:30
            ShiftType.dayDuty.rawValue:      ShiftTimeRange(startMinutes: 8 * 60 + 30, endMinutes: 17 * 60 + 30)  // 08:30–17:30
        ],
        rest: defaultRest
    )
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

/// 會議時間的顯示格式。使用者要求 24 小時制，所以刻意不用 .formatted(date:time:)
/// ——那個會跟著 zh-TW 語系跑出「下午 3:00」。
enum MeetingTimeFormat {
    static let time24: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "HH:mm"; return f
    }()
    static let dateTime24: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "yyyy/M/d (E) HH:mm"; return f
    }()
    /// 「14:00 – 15:00（60 分鐘）」
    static func rangeText(start: Date, minutes: Int) -> String {
        let end = start.addingTimeInterval(TimeInterval(max(0, minutes) * 60))
        return "\(time24.string(from: start)) – \(time24.string(from: end))"
    }
}

struct MeetingItem: Identifiable, Codable {
    let id: UUID
    var content: String
    /// 負責人（可多位）。id 可能是部屬、名片或組織人員——挑人清單三種來源共用同一個欄位，
    /// 用 LifeStore.sideRolePerson(_:) 反查現在的姓名／職稱。
    /// 舊資料只有單一 assigneeId，解碼時會折進這裡（見下方 LegacyKeys）。
    var assigneeIds: [UUID]
    var dueDate: Date?
    var isCompleted: Bool
    var completedAt: Date?
    /// 項目層級備註（可 @ 標註人員）
    var note: String
    /// 連到某筆兼任職務待辦（同一件事）。完成狀態雙向同步，且評分只算一次。
    var sideRoleLink: SideRoleBackLink?

    init(id: UUID = UUID(), content: String = "", assigneeIds: [UUID] = [],
         dueDate: Date? = nil, isCompleted: Bool = false, completedAt: Date? = nil,
         note: String = "", sideRoleLink: SideRoleBackLink? = nil) {
        self.id = id; self.content = content; self.assigneeIds = assigneeIds
        self.dueDate = dueDate; self.isCompleted = isCompleted; self.completedAt = completedAt
        self.note = note; self.sideRoleLink = sideRoleLink
    }

    enum CodingKeys: String, CodingKey {
        case id, content, assigneeIds, dueDate, isCompleted, completedAt, note, sideRoleLink
    }

    /// 舊版單一負責人欄位。刻意放在獨立的 CodingKey，讓 encode 仍可用合成版
    /// （CodingKeys 裡出現沒有對應屬性的 case 會讓合成的 encode 編不過）。
    private enum LegacyKeys: String, CodingKey { case assigneeId }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        content = (try? c.decode(String.self, forKey: .content)) ?? ""
        if let list = try? c.decodeIfPresent([UUID].self, forKey: .assigneeIds), !list.isEmpty {
            assigneeIds = list
        } else if let legacy = try? decoder.container(keyedBy: LegacyKeys.self),
                  let single = try? legacy.decodeIfPresent(UUID.self, forKey: .assigneeId) {
            // 升級遷移：舊的單一負責人收進多選陣列，否則既有議程項目的負責人會全部消失
            assigneeIds = [single]
        } else {
            assigneeIds = []
        }
        dueDate = try? c.decodeIfPresent(Date.self, forKey: .dueDate)
        // 舊資料沒有 isCompleted → 視為未完成（避免整批會議解碼失敗）
        isCompleted = (try? c.decode(Bool.self, forKey: .isCompleted)) ?? false
        completedAt = try? c.decodeIfPresent(Date.self, forKey: .completedAt)
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        sideRoleLink = try? c.decodeIfPresent(SideRoleBackLink.self, forKey: .sideRoleLink)
    }
}

/// 週期規則。frequency 沿用舊的 MeetingRecurrence（每日／每週／隔週／每月），
/// 額外可指定「每週的哪幾天」與「重複到哪一天」。
struct MeetingRecurrenceRule: Codable, Equatable {
    var frequency: MeetingRecurrence
    /// 1=週日 … 7=週六，對齊 Calendar.component(.weekday, from:)。
    /// 空陣列＝沿用起始日的星期幾（舊資料遷移過來就是這樣）。只有每週／隔週會看這個欄位。
    var weekdays: [Int]
    /// 重複到這天（含當天）為止。nil＝無限期，展開時只算到「今天起三個月」。
    var endDate: Date?

    init(frequency: MeetingRecurrence, weekdays: [Int] = [], endDate: Date? = nil) {
        self.frequency = frequency; self.weekdays = weekdays; self.endDate = endDate
    }

    enum CodingKeys: String, CodingKey { case frequency, weekdays, endDate }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frequency = (try? c.decodeIfPresent(MeetingRecurrence.self, forKey: .frequency)) ?? .weekly
        weekdays = (try? c.decodeIfPresent([Int].self, forKey: .weekdays)) ?? []
        endDate = try? c.decodeIfPresent(Date.self, forKey: .endDate)
    }
}

/// 單一場次的覆寫。**只存使用者動過的場次**——沒動過的場次由規則即時推導出來，
/// 不落地。這與 App 既有的固定支出／信用卡／收入週期展開是同一個作法：
/// 規則是真相，展開結果是畫面。差別在這裡多了「取消」與「改期」兩種覆寫。
struct MeetingOccurrence: Identifiable, Codable {
    let id: UUID
    /// 原定日期時間。這是與規則推導結果配對的鍵，改期後也不會變動，
    /// 否則改期一次就再也對不回原本那一場、下次展開會多出一場。
    var scheduledDate: Date
    /// 改期後的日期時間。nil＝按原定時間。
    var movedTo: Date?
    var isCancelled: Bool
    /// 這一場自己的議程項目
    var items: [MeetingItem]
    /// 臨時加開的一場（不是規則推導出來的）。這種場次「存在」本身就是狀態，
    /// 就算還沒填議程也不能被回收——回收了它就從清單上消失。
    var isAdHoc: Bool

    /// 實際開會時間
    var effectiveDate: Date { movedTo ?? scheduledDate }
    /// 是否還留著任何「值得存檔」的狀態。全部清空的場次會被回收，避免存檔無限膨脹。
    var isMeaningful: Bool { isCancelled || movedTo != nil || !items.isEmpty || isAdHoc }

    init(id: UUID = UUID(), scheduledDate: Date, movedTo: Date? = nil,
         isCancelled: Bool = false, items: [MeetingItem] = [], isAdHoc: Bool = false) {
        self.id = id; self.scheduledDate = scheduledDate
        self.movedTo = movedTo; self.isCancelled = isCancelled; self.items = items
        self.isAdHoc = isAdHoc
    }

    enum CodingKeys: String, CodingKey { case id, scheduledDate, movedTo, isCancelled, items, isAdHoc }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        scheduledDate = (try? c.decodeIfPresent(Date.self, forKey: .scheduledDate)) ?? Date()
        movedTo = try? c.decodeIfPresent(Date.self, forKey: .movedTo)
        isCancelled = (try? c.decodeIfPresent(Bool.self, forKey: .isCancelled)) ?? false
        items = (try? c.decodeIfPresent([MeetingItem].self, forKey: .items)) ?? []
        isAdHoc = (try? c.decodeIfPresent(Bool.self, forKey: .isAdHoc)) ?? false
    }
}

/// 展開後的一場會議（規則推導 + 覆寫合併的結果）。純顯示用，不落地。
struct ResolvedMeetingOccurrence: Identifiable {
    /// 用原定日期當 id：同一場在多次展開之間 id 要穩定，才不會每次重畫都動畫閃一下
    var id: Date { scheduledDate }
    let scheduledDate: Date
    let date: Date
    let isCancelled: Bool
    let isMoved: Bool
    let items: [MeetingItem]
    /// 已經落地成覆寫（使用者動過）
    let isMaterialised: Bool
    /// 臨時加開（非規則推導）
    let isAdHoc: Bool
}

struct SubordinateMeeting: Identifiable, Codable {
    let id: UUID
    var topic: String
    var date: Date
    var durationMinutes: Int
    /// 舊的週期欄位。保留是為了讓尚未升級的匯出檔仍讀得懂頻率；
    /// 真正驅動展開的是 rule；建構子與編輯頁存檔時兩者一起維護。
    var recurrence: MeetingRecurrence?
    var rule: MeetingRecurrenceRule?
    /// 不重複的會議：議程項目就放這裡。
    /// 有週期的會議：議程項目改放各場次自己身上，這裡會是空的
    ///（切換「設定週期」時由編輯頁負責搬動，見 MeetingEditorSheet 的 onChange）。
    var items: [MeetingItem]
    var note: String
    /// Task 產生時間：這個會議主題「當初是什麼時候立的」，與開會時間分開。
    /// 舊資料沒有這個欄位，解碼時退回 date（開會時間），不會出現 1970 年。
    var createdAt: Date
    /// 有狀態的場次（被取消／被改期／有議程項目）。沒動過的場次不會出現在這裡。
    var occurrences: [MeetingOccurrence]

    init(id: UUID = UUID(), topic: String = "", date: Date = Date(),
         durationMinutes: Int = 60, recurrence: MeetingRecurrence? = nil,
         rule: MeetingRecurrenceRule? = nil,
         items: [MeetingItem] = [], note: String = "", createdAt: Date? = nil,
         occurrences: [MeetingOccurrence] = []) {
        self.id = id; self.topic = topic; self.date = date
        self.durationMinutes = durationMinutes
        self.rule = rule
        self.recurrence = rule?.frequency ?? recurrence
        self.items = items; self.note = note
        self.createdAt = createdAt ?? date
        self.occurrences = occurrences
    }

    /// 依時長推出的結束時間（編輯頁與清單顯示「14:00–15:00」用）
    var endDate: Date {
        date.addingTimeInterval(TimeInterval(max(0, durationMinutes) * 60))
    }

    var isRecurring: Bool { rule != nil }

    /// 全部議程項目（不分場次）。評分、行事曆待辦、搜尋、匯出一律走這裡——
    /// 直接用 items 的話，場次上的項目都會憑空消失。
    /// items＋各場次相加：有週期時 items 是空的，沒週期時也可能有臨時加開的場次
    ///（v25.237 起不開週期也能加場），兩邊都要算。
    var allItems: [MeetingItem] {
        items + occurrences.flatMap(\.items)
    }

    enum CodingKeys: String, CodingKey {
        case id, topic, date, durationMinutes, recurrence, rule, items, note, createdAt, occurrences
    }

    // 自訂解碼：createdAt／rule／occurrences 為後加欄位。這裡的容錯粒度是「整個部屬」——
    // 少一個 key 若讓 SubordinateMeeting 解碼失敗，整位部屬的資料都會消失。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        topic = (try? c.decodeIfPresent(String.self, forKey: .topic)) ?? ""
        date = (try? c.decodeIfPresent(Date.self, forKey: .date)) ?? Date()
        durationMinutes = (try? c.decodeIfPresent(Int.self, forKey: .durationMinutes)) ?? 60
        recurrence = try? c.decodeIfPresent(MeetingRecurrence.self, forKey: .recurrence)
        items = (try? c.decodeIfPresent([MeetingItem].self, forKey: .items)) ?? []
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? date
        occurrences = (try? c.decodeIfPresent([MeetingOccurrence].self, forKey: .occurrences)) ?? []

        if let r = try? c.decodeIfPresent(MeetingRecurrenceRule.self, forKey: .rule) {
            rule = r
        } else if let legacy = recurrence {
            // 升級遷移：舊的週期會議沒有 rule，也沒有場次概念——它的議程項目
            // 是整個系列共用一份。依使用者確認的作法，把那份項目歸到「第一場」，
            // 之後每一場才各自累積。不搬的話升級後所有項目都會落在沒人看得到的地方。
            rule = MeetingRecurrenceRule(frequency: legacy)
            if !items.isEmpty && occurrences.isEmpty {
                occurrences = [MeetingOccurrence(scheduledDate: date, items: items)]
                items = []
            }
        } else {
            rule = nil
        }
    }

    /// 展開這個系列的場次。
    ///
    /// 規則是真相、展開結果是畫面——與固定支出／信用卡／收入的週期展開同一個模式，
    /// 同樣用 1200 次的上限當失控保險。差別是這裡要把「使用者動過的場次」疊回去，
    /// 而且改期到規則之外的日期也必須出現在清單上（否則改完期那一場就人間蒸發）。
    ///
    /// - Parameters:
    ///   - from: 只需要這天之後的場次（呼叫端通常給「七天前」）。給了就會依規則
    ///     大步跳到附近再開始逐一推進——一個開了三年的每日會議若從第一天慢慢走，
    ///     還沒走到今天就會先撞上保險絲，畫面只剩三年前的場次。
    ///   - horizon: 沒設結束日時要展開到哪天為止（呼叫端通常給「今天 + 3 個月」）
    func expandedOccurrences(from: Date? = nil, horizon: Date) -> [ResolvedMeetingOccurrence] {
        let overrides = Dictionary(occurrences.map { ($0.scheduledDate.timeIntervalSinceReferenceDate, $0) },
                                   uniquingKeysWith: { a, _ in a })
        guard let rule else {
            // 沒有週期：主場次（會議本身）＋臨時加開的場次。
            // 主場次標 isMaterialised——它就是這個會議，顯示窗的舊日期過濾不該把它濾掉。
            var out = [ResolvedMeetingOccurrence(scheduledDate: date, date: date,
                                                 isCancelled: false, isMoved: false,
                                                 items: items, isMaterialised: true,
                                                 isAdHoc: false)]
            for o in occurrences {
                out.append(ResolvedMeetingOccurrence(scheduledDate: o.scheduledDate,
                                                     date: o.effectiveDate,
                                                     isCancelled: o.isCancelled,
                                                     isMoved: o.movedTo != nil,
                                                     items: o.items,
                                                     isMaterialised: true,
                                                     isAdHoc: o.isAdHoc))
            }
            return out.sorted { $0.date < $1.date }
        }

        let limit = rule.endDate.map { max($0, date) } ?? max(horizon, date)
        var dates: [Date] = []
        let cal = Calendar.current
        var cursor = from.map { fastForward(to: $0, rule: rule, cal: cal) } ?? date
        var guardIdx = 0
        while cursor <= limit && guardIdx < 1200 {
            guardIdx += 1
            if matchesWeekdayFilter(cursor, rule: rule, cal: cal) { dates.append(cursor) }
            guard let next = advance(cursor, rule: rule, cal: cal) else { break }
            cursor = next
        }

        var out: [ResolvedMeetingOccurrence] = []
        var seen = Set<TimeInterval>()
        for d in dates {
            let key = d.timeIntervalSinceReferenceDate
            seen.insert(key)
            let o = overrides[key]
            out.append(ResolvedMeetingOccurrence(scheduledDate: d,
                                                 date: o?.effectiveDate ?? d,
                                                 isCancelled: o?.isCancelled ?? false,
                                                 isMoved: o?.movedTo != nil,
                                                 items: o?.items ?? [],
                                                 isMaterialised: o != nil,
                                                 isAdHoc: o?.isAdHoc ?? false))
        }
        // 落在展開範圍外的覆寫（例如把某場改期到結束日之後，或縮短了結束日）
        // 仍然要看得到——它承載著使用者親手填的議程項目。
        for o in occurrences where !seen.contains(o.scheduledDate.timeIntervalSinceReferenceDate) {
            out.append(ResolvedMeetingOccurrence(scheduledDate: o.scheduledDate,
                                                 date: o.effectiveDate,
                                                 isCancelled: o.isCancelled,
                                                 isMoved: o.movedTo != nil,
                                                 items: o.items,
                                                 isMaterialised: true,
                                                 isAdHoc: o.isAdHoc))
        }
        return out.sorted { $0.date < $1.date }
    }

    /// 依規則的節奏「大步跳」到 target 附近，保持與起始日同相位。
    /// 一律少跳一步（隔週就是少跳兩週），讓落點稍早於 target，
    /// 免得剛好把 target 當週的場次跳過去。
    private func fastForward(to target: Date, rule: MeetingRecurrenceRule, cal: Calendar) -> Date {
        guard target > date else { return date }
        switch rule.frequency {
        case .daily:
            let d = cal.dateComponents([.day], from: date, to: target).day ?? 0
            return cal.date(byAdding: .day, value: max(0, d - 14), to: date) ?? date
        case .weekly, .biweekly:
            let step = rule.frequency == .biweekly ? 2 : 1
            let w = cal.dateComponents([.weekOfYear], from: date, to: target).weekOfYear ?? 0
            let n = max(0, ((w - step) / step) * step)
            return cal.date(byAdding: .weekOfYear, value: n, to: date) ?? date
        case .monthly:
            let m = cal.dateComponents([.month], from: date, to: target).month ?? 0
            return cal.date(byAdding: .month, value: max(0, m - 1), to: date) ?? date
        }
    }

    private func matchesWeekdayFilter(_ d: Date, rule: MeetingRecurrenceRule, cal: Calendar) -> Bool {
        guard rule.frequency == .weekly || rule.frequency == .biweekly,
              !rule.weekdays.isEmpty else { return true }
        return rule.weekdays.contains(cal.component(.weekday, from: d))
    }

    private func advance(_ d: Date, rule: MeetingRecurrenceRule, cal: Calendar) -> Date? {
        switch rule.frequency {
        case .daily:
            return cal.date(byAdding: .day, value: 1, to: d)
        case .weekly, .biweekly:
            // 有指定星期幾時逐日前進、由 matchesWeekdayFilter 篩選；
            // 隔週則在跨過週日換週時多跳一週，維持「隔一週」的語意。
            if !rule.weekdays.isEmpty {
                guard let next = cal.date(byAdding: .day, value: 1, to: d) else { return nil }
                guard rule.frequency == .biweekly else { return next }
                let wasWeek = cal.component(.weekOfYear, from: d)
                let nowWeek = cal.component(.weekOfYear, from: next)
                if wasWeek != nowWeek { return cal.date(byAdding: .day, value: 7, to: next) }
                return next
            }
            return cal.date(byAdding: .day, value: rule.frequency == .biweekly ? 14 : 7, to: d)
        case .monthly:
            return cal.date(byAdding: .month, value: 1, to: d)
        }
    }

    /// 回收沒有任何狀態的場次覆寫（使用者把改期取消、項目也刪光了）。
    mutating func pruneOccurrences() {
        occurrences.removeAll { !$0.isMeaningful }
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

    /// 連到某筆兼任職務待辦（同一件事）。完成狀態雙向同步，且評分只算一次
    ///（走兼任那邊的 +3，本職這邊跳過，否則同一件事會被計兩次分）。
    var sideRoleLink: SideRoleBackLink?
    /// Apple 提醒事項的對應 id（開啟同步後由 ReminderBridge 寫入；App → 提醒事項單向）
    var reminderId: String?

    init(id: UUID = UUID(), topic: String = "", content: String = "",
         date: Date = Date(), dueDate: Date? = nil, note: String = "",
         isCompleted: Bool = false, completedAt: Date? = nil,
         sideRoleLink: SideRoleBackLink? = nil, reminderId: String? = nil) {
        self.id = id; self.topic = topic; self.content = content
        self.date = date; self.dueDate = dueDate; self.note = note
        self.isCompleted = isCompleted; self.completedAt = completedAt
        self.sideRoleLink = sideRoleLink; self.reminderId = reminderId
    }

    // 自訂解碼：isCompleted / completedAt 為後加欄位，舊存檔沒有這兩個 key。
    // 用 decodeIfPresent 容錯，避免單筆缺欄位導致整個 subordinates 陣列解碼失敗、資料消失。
    enum CodingKeys: String, CodingKey {
        case id, topic, content, date, dueDate, note, isCompleted, completedAt, sideRoleLink, reminderId
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
        sideRoleLink = try? c.decodeIfPresent(SideRoleBackLink.self, forKey: .sideRoleLink)
        reminderId = try? c.decodeIfPresent(String.self, forKey: .reminderId)
    }
}

/// 家庭待辦事項（家庭頁「家庭成員」上方的待辦區；可指派給家庭成員，
/// 可選擇同步到 Apple 提醒事項）。
struct FamilyTask: Identifiable, Codable {
    let id: UUID
    var content: String
    /// 指派的家庭成員（可多位；空＝未指派）
    var assigneeIds: [UUID]
    var createdAt: Date
    var dueDate: Date?
    var isCompleted: Bool
    var completedAt: Date?
    var note: String
    /// Apple 提醒事項的對應 id（App → 提醒事項單向同步）
    var reminderId: String?

    init(id: UUID = UUID(), content: String = "", assigneeIds: [UUID] = [],
         createdAt: Date = Date(), dueDate: Date? = nil,
         isCompleted: Bool = false, completedAt: Date? = nil,
         note: String = "", reminderId: String? = nil) {
        self.id = id; self.content = content; self.assigneeIds = assigneeIds
        self.createdAt = createdAt; self.dueDate = dueDate
        self.isCompleted = isCompleted; self.completedAt = completedAt
        self.note = note; self.reminderId = reminderId
    }

    enum CodingKeys: String, CodingKey {
        case id, content, assigneeIds, createdAt, dueDate, isCompleted, completedAt, note, reminderId
    }

    // 逐欄容錯：這是頂層陣列（lossyDecodeArray 逐筆容錯），單筆內缺欄位
    // 也不該讓那一筆整個消失
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        content = (try? c.decodeIfPresent(String.self, forKey: .content)) ?? ""
        assigneeIds = (try? c.decodeIfPresent([UUID].self, forKey: .assigneeIds)) ?? []
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        dueDate = try? c.decodeIfPresent(Date.self, forKey: .dueDate)
        isCompleted = (try? c.decodeIfPresent(Bool.self, forKey: .isCompleted)) ?? false
        completedAt = try? c.decodeIfPresent(Date.self, forKey: .completedAt)
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        reminderId = try? c.decodeIfPresent(String.self, forKey: .reminderId)
    }
}

// MARK: - 部屬

/// 部屬週報題目（可勾選完成；完成數併入主動性評分）
struct WeeklyReport: Identifiable, Codable {
    let id: UUID
    var topic: String
    var date: Date
    var note: String
    var isCompleted: Bool
    var completedAt: Date?

    init(id: UUID = UUID(), topic: String = "", date: Date = Date(), note: String = "", isCompleted: Bool = false, completedAt: Date? = nil) {
        self.id = id; self.topic = topic; self.date = date; self.note = note; self.isCompleted = isCompleted; self.completedAt = completedAt
    }

    enum CodingKeys: String, CodingKey { case id, topic, date, note, isCompleted, completedAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        topic = (try? c.decode(String.self, forKey: .topic)) ?? ""
        date = (try? c.decode(Date.self, forKey: .date)) ?? Date()
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        isCompleted = (try? c.decode(Bool.self, forKey: .isCompleted)) ?? false
        completedAt = try? c.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}

/// 部屬升職紀錄：from/to 存「當時的職等職稱快照文字」，
/// 職稱表日後改名或刪除都不影響歷史紀錄的可讀性
struct PromotionRecord: Identifiable, Codable {
    let id: UUID
    var date: Date              // 生效日期
    var fromTitle: String       // 升職前職稱（快照）
    var toTitle: String         // 升職後職稱（快照）
    var toGradeTitleId: UUID?   // 升任的職等職稱 ID（供對照，可能已被刪除）
    var note: String

    init(id: UUID = UUID(), date: Date = Date(), fromTitle: String = "",
         toTitle: String = "", toGradeTitleId: UUID? = nil, note: String = "") {
        self.id = id; self.date = date; self.fromTitle = fromTitle
        self.toTitle = toTitle; self.toGradeTitleId = toGradeTitleId; self.note = note
    }
}

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
    var shifts: [SubordinateShift]
    /// 廠區（選填，例如 A / B、P1 / P2）；空字串代表未分廠區
    var plantArea: String
    /// 週報題目（可勾選完成；完成數併入主動性評分）
    var weeklyReports: [WeeklyReport]
    /// 執掌設備（含預防保養 PM 記錄與警報記錄）
    var equipments: [ManagedEquipment]
    /// 升職歷程（新到舊不強制，顯示時再排序）
    var promotions: [PromotionRecord]

    init(id: UUID = UUID(), name: String, jobTitle: String = "",
         department: String = "", note: String = "", gradeTitleId: UUID? = nil,
         departmentId: UUID? = nil, records: [SubordinateRecord] = [], joinDate: Date? = nil,
         meetings: [SubordinateMeeting] = [], tasks: [SubordinateTask] = [],
         shifts: [SubordinateShift] = [], plantArea: String = "", weeklyReports: [WeeklyReport] = [],
         equipments: [ManagedEquipment] = [], promotions: [PromotionRecord] = []) {
        self.id = id; self.name = name; self.jobTitle = jobTitle
        self.department = department; self.note = note; self.gradeTitleId = gradeTitleId
        self.departmentId = departmentId; self.records = records; self.joinDate = joinDate
        self.meetings = meetings; self.tasks = tasks; self.shifts = shifts
        self.plantArea = plantArea; self.weeklyReports = weeklyReports
        self.equipments = equipments
        self.promotions = promotions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        // name/jobTitle/department/note 舊資料若缺欄位不應讓整筆部屬解碼失敗
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        jobTitle = (try? c.decode(String.self, forKey: .jobTitle)) ?? ""
        department = (try? c.decode(String.self, forKey: .department)) ?? ""
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        gradeTitleId = try? c.decodeIfPresent(UUID.self, forKey: .gradeTitleId)
        departmentId = try? c.decodeIfPresent(UUID.self, forKey: .departmentId)
        joinDate = try? c.decodeIfPresent(Date.self, forKey: .joinDate)
        // 逐元素容錯：單一壞紀錄只跳過該筆，不會整個陣列（任務 / 會議 / 報告…）一起消失
        records = (try? c.decode(LossyArray<SubordinateRecord>.self, forKey: .records))?.elements ?? []
        meetings = (try? c.decode(LossyArray<SubordinateMeeting>.self, forKey: .meetings))?.elements ?? []
        tasks = (try? c.decode(LossyArray<SubordinateTask>.self, forKey: .tasks))?.elements ?? []
        shifts = (try? c.decode(LossyArray<SubordinateShift>.self, forKey: .shifts))?.elements ?? []
        plantArea = (try? c.decode(String.self, forKey: .plantArea)) ?? ""
        weeklyReports = (try? c.decode(LossyArray<WeeklyReport>.self, forKey: .weeklyReports))?.elements ?? []
        equipments = (try? c.decode(LossyArray<ManagedEquipment>.self, forKey: .equipments))?.elements ?? []
        promotions = (try? c.decode(LossyArray<PromotionRecord>.self, forKey: .promotions))?.elements ?? []
    }
}

// MARK: - 部屬執掌設備（含 PM 保養與警報記錄）

/// 部屬管理（執掌）的設備：記錄預防保養（PM）時間與警報事件，
/// 供部屬卡片「執掌」分頁以時間軸並列檢視 PM 與警報的相關性。
struct ManagedEquipment: Identifiable, Codable {
    let id: UUID
    /// 設備名稱（如：CVD-01、冰機 A）
    var name: String
    /// 備註（位置、型號等）
    var note: String
    /// 預防保養（PM）記錄
    var pmRecords: [EquipmentPMRecord]
    /// 警報記錄
    var alarms: [EquipmentAlarm]

    init(id: UUID = UUID(), name: String = "", note: String = "",
         pmRecords: [EquipmentPMRecord] = [], alarms: [EquipmentAlarm] = []) {
        self.id = id; self.name = name; self.note = note
        self.pmRecords = pmRecords; self.alarms = alarms
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        pmRecords = (try? c.decode(LossyArray<EquipmentPMRecord>.self, forKey: .pmRecords))?.elements ?? []
        alarms = (try? c.decode(LossyArray<EquipmentAlarm>.self, forKey: .alarms))?.elements ?? []
    }
    private enum CodingKeys: String, CodingKey { case id, name, note, pmRecords, alarms }
}

/// 單筆預防保養（PM）記錄。
struct EquipmentPMRecord: Identifiable, Codable {
    let id: UUID
    var date: Date
    /// 保養內容／項目（選填）
    var note: String

    init(id: UUID = UUID(), date: Date = Date(), note: String = "") {
        self.id = id; self.date = date; self.note = note
    }
}

/// 單筆警報記錄。
struct EquipmentAlarm: Identifiable, Codable {
    let id: UUID
    /// 警報發生時間（含時分）
    var date: Date
    /// 警報內容
    var content: String

    init(id: UUID = UUID(), date: Date = Date(), content: String = "") {
        self.id = id; self.date = date; self.content = content
    }
}

/// 逐元素容錯解碼陣列：單一壞元素只跳過該筆，不會導致整個陣列解碼失敗（回傳空陣列）。
struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]
    private struct AnyDecodable: Decodable {}   // 用來消耗（跳過）無法解碼的元素
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        while !container.isAtEnd {
            let before = container.currentIndex
            do {
                result.append(try container.decode(Element.self))
            } catch {
                _ = try? container.decode(AnyDecodable.self)   // 跳過壞元素
            }
            if container.currentIndex == before { break }       // 無法前進 → 中止避免無限迴圈
        }
        elements = result
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

    static func savePhoto(_ data: Data, id: UUID) -> String? {
        let data = ImageCompressor.compressForStorage(data)   // 存檔前統一壓縮：1080P 長邊 + JPEG 80%
        let name = "\(id.uuidString).jpg"
        let url = photosDirectory.appendingPathComponent(name)
        guard (try? data.write(to: url)) != nil else { return nil }
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
    /// 管理人員（OrgPerson id，可多位——主管＋代理人是常態）。
    /// 在部門詳細頁設定；目錄檢視的部門列會直接顯示管理人姓名。
    var managerIds: [UUID]

    init(id: UUID = UUID(), code: String = "", name: String = "",
         function: String = "",
         upstreamIds: [UUID] = [],
         downstreamIds: [UUID] = [],
         peerIds: [UUID] = [],
         managerIds: [UUID] = []) {
        self.id = id; self.code = code; self.name = name
        self.function = function
        self.upstreamIds = upstreamIds
        self.downstreamIds = downstreamIds
        self.peerIds = peerIds
        self.managerIds = managerIds
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
        managerIds = (try? c.decode([UUID].self, forKey: .managerIds)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, code, name, function, upstreamIds, downstreamIds, peerIds, managerIds
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

    static func savePhoto(_ data: Data, id: UUID) -> String? {
        let data = ImageCompressor.compressForStorage(data)   // 存檔前統一壓縮：1080P 長邊 + JPEG 80%
        let name = "\(id.uuidString).jpg"
        let url = photosDirectory.appendingPathComponent(name)
        guard (try? data.write(to: url)) != nil else { return nil }
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
            // 不能只比對「日」是否相同：NotificationManager 用 Calendar.byAdding(.month)
            // 逐期展開通知時，月天數不足會把結果夾到當月最後一天（例如每月 31 號事件在
            // 2/4/6/9/11 月會夾到 28/30 號），若這裡仍嚴格比對「日 == 起始日」，短月份
            // 永遠比對不到，事件會從行事曆畫面消失，卻仍會收到通知，兩邊顯示不一致。
            // 改為用同一套 Calendar.byAdding 邏輯算出「這個月的實際發生日」再比對，
            // 確保行事曆畫面與通知時間永遠一致。
            let sy = calendar.component(.year, from: start), sm = calendar.component(.month, from: start)
            let ty = calendar.component(.year, from: target), tm = calendar.component(.month, from: target)
            let monthsDiff = (ty - sy) * 12 + (tm - sm)
            guard monthsDiff >= 0,
                  let expected = calendar.date(byAdding: .month, value: monthsDiff, to: start) else { return false }
            return calendar.isDate(calendar.startOfDay(for: expected), inSameDayAs: target)
        case .yearly:
            // 同月份邏輯：閏年 2/29 事件在平年會被 Calendar.byAdding(.year) 夾到 2/28，
            // 改用同一套邏輯算出「這一年的實際發生日」再比對，避免與通知時間脫勾。
            let yearsDiff = calendar.component(.year, from: target) - calendar.component(.year, from: start)
            guard yearsDiff >= 0,
                  let expected = calendar.date(byAdding: .year, value: yearsDiff, to: start) else { return false }
            return calendar.isDate(calendar.startOfDay(for: expected), inSameDayAs: target)
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

// MARK: - 完成準時度（打勾時間戳與逾期/準時/超前判定）

/// 相對於目標日期的完成準時度
enum CompletionTiming {
    case ahead    // 超前（完成日早於目標日）
    case onTime   // 準時（同一天完成）
    case overdue  // 逾期（完成日晚於目標日）
}

/// 依「完成時間」與「目標日期」判定準時度（以日為粒度）。
/// 任一為 nil（未完成或無目標日）→ 回傳 nil（不顯示準時度，只顯示時間戳）。
func completionTiming(completedAt: Date?, due: Date?, calendar: Calendar = .current) -> CompletionTiming? {
    guard let completedAt, let due else { return nil }
    let c = calendar.startOfDay(for: completedAt)
    let d = calendar.startOfDay(for: due)
    if c < d { return .ahead }
    if c > d { return .overdue }
    return .onTime
}
