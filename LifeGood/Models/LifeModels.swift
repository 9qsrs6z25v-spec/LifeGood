import Foundation

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

    init(id: UUID = UUID(), role: FamilyMemberRole = .spouse,
         chineseName: String = "", englishName: String = "",
         birthday: Date? = nil,
         marriageDate: Date? = nil, isDivorced: Bool = false, divorceDate: Date? = nil) {
        self.id = id; self.role = role
        self.chineseName = chineseName; self.englishName = englishName
        self.birthday = birthday
        self.marriageDate = marriageDate
        self.isDivorced = isDivorced
        self.divorceDate = divorceDate
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
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, chineseName, englishName, birthday, marriageDate, isDivorced, divorceDate
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
        case .achievement: return "trophy.fill"
        case .travel: return "airplane"
        case .pet: return "pawprint.fill"
        case .health: return "cross.fill"
        case .other: return "star.fill"
        }
    }
}

// MARK: - 職涯子分類

enum CareerSubCategory: String, Codable, CaseIterable, Identifiable {
    case join = "入職"
    case promote = "升職"
    case transfer = "轉職"
    case demote = "降職"
    case resign = "離職"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .join: return "arrow.right.to.line"
        case .promote: return "arrow.up.circle.fill"
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

    init(id: UUID = UUID(), title: String, date: Date = Date(),
         category: MilestoneCategory = .other, note: String = "",
         careerSubCategory: CareerSubCategory? = nil,
         companyName: String? = nil, department: String? = nil,
         jobTitle: String? = nil, jobGrade: String? = nil,
         mood: String? = nil, futurePlan: String? = nil,
         isManagerial: Bool? = nil) {
        self.id = id; self.title = title; self.date = date
        self.category = category; self.note = note
        self.careerSubCategory = careerSubCategory
        self.companyName = companyName; self.department = department
        self.jobTitle = jobTitle; self.jobGrade = jobGrade
        self.mood = mood; self.futurePlan = futurePlan
        self.isManagerial = isManagerial
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
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, date, category, note
        case careerSubCategory, companyName, department, jobTitle, jobGrade
        case mood, futurePlan, isManagerial
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

// MARK: - 部屬

struct Subordinate: Identifiable, Codable {
    let id: UUID
    var name: String
    var jobTitle: String
    var department: String
    var note: String
    var gradeTitleId: UUID?

    init(id: UUID = UUID(), name: String, jobTitle: String = "",
         department: String = "", note: String = "", gradeTitleId: UUID? = nil) {
        self.id = id; self.name = name; self.jobTitle = jobTitle
        self.department = department; self.note = note; self.gradeTitleId = gradeTitleId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        jobTitle = try c.decode(String.self, forKey: .jobTitle)
        department = try c.decode(String.self, forKey: .department)
        note = try c.decode(String.self, forKey: .note)
        gradeTitleId = try c.decodeIfPresent(UUID.self, forKey: .gradeTitleId)
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
