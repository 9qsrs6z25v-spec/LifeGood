import Foundation

// MARK: - 里程碑分類

enum MilestoneCategory: String, Codable, CaseIterable, Identifiable {
    case career = "職涯"
    case education = "學歷"
    case family = "家庭"
    case marriage = "結婚"
    case pet = "寵物"
    case health = "健康"
    case travel = "旅行"
    case achievement = "成就"
    case other = "其他"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .career: return "briefcase.fill"
        case .education: return "graduationcap.fill"
        case .family: return "heart.fill"
        case .marriage: return "heart.circle.fill"
        case .pet: return "pawprint.fill"
        case .health: return "cross.fill"
        case .travel: return "airplane"
        case .achievement: return "trophy.fill"
        case .other: return "star.fill"
        }
    }
}

struct LifeMilestone: Identifiable, Codable {
    let id: UUID
    var title: String
    var date: Date
    var category: MilestoneCategory
    var note: String

    init(id: UUID = UUID(), title: String, date: Date = Date(),
         category: MilestoneCategory = .other, note: String = "") {
        self.id = id; self.title = title; self.date = date
        self.category = category; self.note = note
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
