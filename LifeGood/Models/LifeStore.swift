import Foundation

class LifeStore: ObservableObject {
    @Published var milestones: [LifeMilestone] = [] { didSet { if !isLoading { save() } } }
    @Published var relationships: [Relationship] = [] { didSet { if !isLoading { save() } } }
    @Published var pets: [Pet] = [] { didSet { if !isLoading { save() } } }
    @Published var schedules: [Schedule] = [] { didSet { if !isLoading { save() } } }

    private var isLoading = false

    init() { load() }

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
}
