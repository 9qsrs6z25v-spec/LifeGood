import Foundation

class LifeStore: ObservableObject {
    @Published var profile: UserProfile = UserProfile() { didSet { if !isLoading { save() } } }
    @Published var familyMembers: [FamilyMember] = [] { didSet { if !isLoading { save() } } }
    @Published var milestones: [LifeMilestone] = [] { didSet { if !isLoading { save() } } }
    @Published var relationships: [Relationship] = [] { didSet { if !isLoading { save() } } }
    @Published var pets: [Pet] = [] { didSet { if !isLoading { save() } } }
    @Published var schedules: [Schedule] = [] { didSet { if !isLoading { save() } } }

    private var isLoading = false

    init() { load() }

    // MARK: - 個人檔案

    func updateProfile(_ profile: UserProfile) { self.profile = profile }

    // MARK: - 家庭成員 CRUD

    func add(_ item: FamilyMember) { familyMembers.append(item) }
    func update(_ item: FamilyMember) {
        if let i = familyMembers.firstIndex(where: { $0.id == item.id }) { familyMembers[i] = item }
    }
    func deleteFamilyMember(_ item: FamilyMember) { familyMembers.removeAll { $0.id == item.id } }

    // MARK: - 里程碑 CRUD

    func add(_ item: LifeMilestone) { milestones.append(item) }
    func update(_ item: LifeMilestone) {
        if let i = milestones.firstIndex(where: { $0.id == item.id }) { milestones[i] = item }
    }
    func deleteMilestone(_ item: LifeMilestone) { milestones.removeAll { $0.id == item.id } }

    // MARK: - 人際關係 CRUD

    func add(_ item: Relationship) { relationships.append(item) }
    func update(_ item: Relationship) {
        if let i = relationships.firstIndex(where: { $0.id == item.id }) { relationships[i] = item }
    }
    func deleteRelationship(_ item: Relationship) { relationships.removeAll { $0.id == item.id } }

    // MARK: - 寵物 CRUD

    func add(_ item: Pet) { pets.append(item) }
    func update(_ item: Pet) {
        if let i = pets.firstIndex(where: { $0.id == item.id }) { pets[i] = item }
    }
    func deletePet(_ item: Pet) { pets.removeAll { $0.id == item.id } }

    // MARK: - 行程 CRUD

    func add(_ item: Schedule) { schedules.append(item) }
    func update(_ item: Schedule) {
        if let i = schedules.firstIndex(where: { $0.id == item.id }) { schedules[i] = item }
    }
    func deleteSchedule(_ item: Schedule) { schedules.removeAll { $0.id == item.id } }
    func toggleComplete(_ item: Schedule) {
        if let i = schedules.firstIndex(where: { $0.id == item.id }) {
            schedules[i].isCompleted.toggle()
        }
    }

    // MARK: - 家庭衍生里程碑

    /// 配偶（若有）
    var spouse: FamilyMember? {
        familyMembers.first(where: { $0.role == .spouse })
    }

    /// 從家庭成員衍生的虛擬里程碑（結婚 / 離婚 / 出生），ID 使用穩定命名空間避免重複
    var familyDerivedMilestones: [LifeMilestone] {
        var items: [LifeMilestone] = []
        for member in familyMembers {
            let name = member.chineseName.isEmpty ? (member.englishName.isEmpty ? member.role.rawValue : member.englishName) : member.chineseName
            if member.role == .spouse {
                if let md = member.marriageDate {
                    items.append(LifeMilestone(
                        id: deriveID(member.id, suffix: "marriage"),
                        title: "與 \(name) 結婚",
                        date: md,
                        category: .marriage,
                        note: ""
                    ))
                }
                if member.isDivorced, let dd = member.divorceDate {
                    items.append(LifeMilestone(
                        id: deriveID(member.id, suffix: "divorce"),
                        title: "與 \(name) 離婚",
                        date: dd,
                        category: .family,
                        note: ""
                    ))
                }
            } else if let bd = member.birthday {
                items.append(LifeMilestone(
                    id: deriveID(member.id, suffix: "birthday"),
                    title: "\(member.role.rawValue) \(name) 出生",
                    date: bd,
                    category: .family,
                    note: ""
                ))
            }
        }
        return items
    }

    /// 真實 + 衍生里程碑合併
    var allMilestones: [LifeMilestone] {
        milestones + familyDerivedMilestones
    }

    private func deriveID(_ base: UUID, suffix: String) -> UUID {
        let data = (base.uuidString + ":" + suffix).data(using: .utf8) ?? Data()
        var bytes = [UInt8](repeating: 0, count: 16)
        for (i, b) in data.prefix(16).enumerated() { bytes[i] = b }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                          bytes[4], bytes[5], bytes[6], bytes[7],
                          bytes[8], bytes[9], bytes[10], bytes[11],
                          bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    // MARK: - 統計

    var upcomingSchedules: [Schedule] {
        schedules
            .filter { !$0.isCompleted && $0.date >= Calendar.current.startOfDay(for: Date()) }
            .sorted { $0.date < $1.date }
    }

    var recentInteractions: [(relationship: Relationship, interaction: InteractionRecord)] {
        relationships.flatMap { rel in
            rel.interactions.map { (relationship: rel, interaction: $0) }
        }
        .sorted { $0.interaction.date > $1.interaction.date }
    }

    // MARK: - 持久化

    private func save() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(profile) {
            UserDefaults.standard.set(data, forKey: "life_profile")
        }
        if let data = try? encoder.encode(familyMembers) {
            UserDefaults.standard.set(data, forKey: "life_family")
        }
        if let data = try? encoder.encode(milestones) {
            UserDefaults.standard.set(data, forKey: "life_milestones")
        }
        if let data = try? encoder.encode(relationships) {
            UserDefaults.standard.set(data, forKey: "life_relationships")
        }
        if let data = try? encoder.encode(pets) {
            UserDefaults.standard.set(data, forKey: "life_pets")
        }
        if let data = try? encoder.encode(schedules) {
            UserDefaults.standard.set(data, forKey: "life_schedules")
        }
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        let decoder = JSONDecoder()

        if let data = UserDefaults.standard.data(forKey: "life_profile"),
           let p = try? decoder.decode(UserProfile.self, from: data) {
            profile = p
        }
        if let data = UserDefaults.standard.data(forKey: "life_family"),
           let items = try? decoder.decode([FamilyMember].self, from: data) {
            familyMembers = items
        }
        if let data = UserDefaults.standard.data(forKey: "life_milestones"),
           let items = try? decoder.decode([LifeMilestone].self, from: data) {
            milestones = items
        }
        if let data = UserDefaults.standard.data(forKey: "life_relationships"),
           let items = try? decoder.decode([Relationship].self, from: data) {
            relationships = items
        }
        if let data = UserDefaults.standard.data(forKey: "life_pets"),
           let items = try? decoder.decode([Pet].self, from: data) {
            pets = items
        }
        if let data = UserDefaults.standard.data(forKey: "life_schedules"),
           let items = try? decoder.decode([Schedule].self, from: data) {
            schedules = items
        }
    }

    // MARK: - 清除

    func clearAll() {
        profile = UserProfile()
        familyMembers.removeAll()
        milestones.removeAll()
        relationships.removeAll()
        pets.removeAll()
        schedules.removeAll()
    }
}
