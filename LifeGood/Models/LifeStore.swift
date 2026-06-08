import Foundation

class LifeStore: ObservableObject {
    @Published var profile: UserProfile = UserProfile() { didSet { if !isLoading { save() } } }
    @Published var familyMembers: [FamilyMember] = [] { didSet { if !isLoading { save() } } }
    @Published var milestones: [LifeMilestone] = [] { didSet { if !isLoading { save() } } }
    @Published var relationships: [Relationship] = [] { didSet { if !isLoading { save() } } }
    @Published var pets: [Pet] = [] { didSet { if !isLoading { save() } } }
    @Published var schedules: [Schedule] = [] { didSet { if !isLoading { save() } } }
    @Published var subordinates: [Subordinate] = [] { didSet { if !isLoading { save() } } }
    @Published var departments: [Department] = [] { didSet { if !isLoading { save() } } }
    @Published var gradeTitles: [GradeTitle] = [] { didSet { if !isLoading { save() } } }
    @Published var businessCards: [BusinessCard] = [] { didSet { if !isLoading { save() } } }
    @Published var personalEvents: [PersonalEvent] = [] { didSet { if !isLoading { save() } } }
    @Published var orgPeople: [OrgPerson] = [] { didSet { if !isLoading { save() } } }

    private var isLoading = false
    private let saveQueue = DispatchQueue(label: "com.lifegood.lifestore.save", qos: .utility)

    init() {
        load()
        isLoading = true
        let didBackfill = backfillOrgPeopleFromSubordinates()
        isLoading = false
        if didBackfill { save() }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadFromCloud),
            name: .cloudSyncDidPullChanges,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func reloadFromCloud() {
        load()
        // backfill 期間暫停 save()，避免剛從雲端拉取就立刻回寫
        isLoading = true
        let didBackfill = backfillOrgPeopleFromSubordinates()
        isLoading = false
        // 若 backfill 新建了 OrgPerson/BusinessCard，立即持久化避免重啟後消失
        if didBackfill { save() }
    }

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

    // MARK: - 部屬 CRUD

    func add(_ item: Subordinate) {
        isLoading = true
        subordinates.append(item)
        syncOrgPersonFor(subordinate: item)
        isLoading = false
        save()
    }
    func update(_ item: Subordinate) {
        isLoading = true
        if let i = subordinates.firstIndex(where: { $0.id == item.id }) { subordinates[i] = item }
        syncOrgPersonFor(subordinate: item)
        isLoading = false
        save()
    }
    func deleteSubordinate(_ item: Subordinate) {
        isLoading = true
        subordinates.removeAll { $0.id == item.id }
        // 解除與公司組織人員的連結（保留人員資料以維持歷史）
        if let i = orgPeople.firstIndex(where: { $0.linkedSubordinateId == item.id }) {
            orgPeople[i].linkedSubordinateId = nil
        }
        isLoading = false
        save()
    }

    /// 切換某位部屬底下某筆任務的完成狀態（總覽頁與詳情頁的快速打勾共用）。
    /// 標記完成時記下 completedAt，取消完成則清空。
    func toggleTaskCompletion(subordinateId: UUID, taskId: UUID) {
        guard let si = subordinates.firstIndex(where: { $0.id == subordinateId }),
              let ti = subordinates[si].tasks.firstIndex(where: { $0.id == taskId }) else { return }
        // isLoading = true 防止兩次 subscript 寫回各自觸發 didSet → save()，
        // 避免「isCompleted 已翻轉但 completedAt 尚未設定」的中間態被持久化。
        isLoading = true
        subordinates[si].tasks[ti].isCompleted.toggle()
        subordinates[si].tasks[ti].completedAt = subordinates[si].tasks[ti].isCompleted ? Date() : nil
        isLoading = false
        save()
    }

    // MARK: - 班表（班別指派）

    /// 設定某位部屬某一天的班別；type 傳 nil 表示清除該天班別。
    func setShift(subordinateId: UUID, date: Date, type: ShiftType?) {
        guard let si = subordinates.firstIndex(where: { $0.id == subordinateId }) else { return }
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        // 以 isLoading 批次保護：removeAll 與 append 之間的中間態（班別已刪但未寫入）不應被持久化。
        isLoading = true
        subordinates[si].shifts.removeAll { cal.isDate($0.date, inSameDayAs: day) }
        if let type = type {
            subordinates[si].shifts.append(SubordinateShift(date: day, type: type))
        }
        isLoading = false
        save()
    }

    /// 套用大夜班輪班範本（一次 8 天、不循環）：
    /// 第 1 天時差假 → 第 2–7 天大夜班（6 天）→ 第 8 天休息。
    func applyNightShiftRotation(subordinateId: UUID, startDate: Date) {
        guard let si = subordinates.firstIndex(where: { $0.id == subordinateId }) else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: startDate)
        var plan: [(Int, ShiftType)] = [(0, .jetLagLeave)]
        for d in 1...6 { plan.append((d, .nightShift)) }
        plan.append((7, .restDay))
        // 以 isLoading 批次保護整個迴圈：8 次 removeAll+append 否則每次都觸發 didSet → save()，
        // 共產生 16 次不必要的背景序列化，且各次中間態（部分班別已寫、部分尚未）也會被持久化。
        isLoading = true
        for (offset, type) in plan {
            guard let day = cal.date(byAdding: .day, value: offset, to: start) else { continue }
            subordinates[si].shifts.removeAll { cal.isDate($0.date, inSameDayAs: day) }
            subordinates[si].shifts.append(SubordinateShift(date: day, type: type))
        }
        isLoading = false
        save()
    }

    /// 套用小夜班（5 天，僅週一至週五）：從 startDate 起算往後填滿 5 個平日，
    /// 遇週六日自動跳過、不覆蓋週末。
    func applyEveningShiftWeekdays(subordinateId: UUID, startDate: Date) {
        guard let si = subordinates.firstIndex(where: { $0.id == subordinateId }) else { return }
        let cal = Calendar.current
        var day = cal.startOfDay(for: startDate)
        var filled = 0
        var safety = 0
        while filled < 5 && safety < 21 {
            let wd = cal.component(.weekday, from: day)   // 1 = 週日, 7 = 週六
            if wd != 1 && wd != 7 {
                subordinates[si].shifts.removeAll { cal.isDate($0.date, inSameDayAs: day) }
                subordinates[si].shifts.append(SubordinateShift(date: day, type: .eveningShift))
                filled += 1
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            safety += 1
        }
        save()
    }

    /// 把部屬資料同步到公司組織人員：
    /// - 已連結 → 更新姓名/職稱/部門
    /// - 未連結但有部門 → 新建 OrgPerson + 自動連動產生 BusinessCard
    /// - 未連結且無部門 → 不動
    /// 我目前的公司：取「career 類別最新的非離職」里程碑的 companyName，
    /// 找不到就退到 profile.company。
    var myCurrentCompany: String {
        let careers = milestones
            .filter { $0.category == .career }
            .sorted { $0.date > $1.date }
        // 最近事件為離職 → 目前無業，直接用個人資料的公司欄位
        if careers.first?.careerSubCategory == .resign {
            return profile.company.trimmingCharacters(in: .whitespaces)
        }
        // 找最近一筆非離職且有公司名稱的紀錄
        for m in careers {
            if m.careerSubCategory == .resign { continue }
            if let name = m.companyName?.trimmingCharacters(in: .whitespaces),
               !name.isEmpty {
                return name
            }
        }
        return profile.company.trimmingCharacters(in: .whitespaces)
    }

    private func syncOrgPersonFor(subordinate sub: Subordinate) {
        // 解析職稱：若有 gradeTitleId 用 GradeTitle.title，沒有則用 sub.jobTitle
        let resolvedTitle: String = {
            if let gtId = sub.gradeTitleId,
               let gt = gradeTitles.first(where: { $0.id == gtId }) {
                return gt.title.trimmingCharacters(in: .whitespaces)
            }
            return sub.jobTitle
        }()

        if let i = orgPeople.firstIndex(where: { $0.linkedSubordinateId == sub.id }) {
            var p = orgPeople[i]
            p.name = sub.name
            p.jobTitle = resolvedTitle
            p.gradeTitleId = sub.gradeTitleId
            p.departmentId = sub.departmentId
            orgPeople[i] = p
            return
        }
        guard let deptId = sub.departmentId else { return }

        let personId = UUID()
        let cardId = UUID()
        let deptName = departments.first(where: { $0.id == deptId })?.name ?? sub.department

        // 自動產生對應名片
        let card = BusinessCard(
            id: cardId,
            name: sub.name,
            company: myCurrentCompany,
            department: deptName,
            jobTitle: resolvedTitle,
            phone: "",
            email: "",
            address: "",
            note: "",
            date: Date(),
            photoFileName: nil,
            linkedOrgPersonId: personId
        )
        businessCards.append(card)

        // 建立組織人員
        let person = OrgPerson(
            id: personId,
            name: sub.name,
            jobTitle: resolvedTitle,
            departmentId: deptId,
            dateAdded: Date(),
            linkedBusinessCardId: cardId,
            linkedSubordinateId: sub.id,
            gradeTitleId: sub.gradeTitleId
        )
        orgPeople.append(person)
    }

    /// 一次性 backfill：把舊有部屬補出對應的公司組織人員（之前沒有同步過的）。
    /// 回傳值表示是否有新建立任何條目（供呼叫端決定是否需要額外 save）。
    @discardableResult
    func backfillOrgPeopleFromSubordinates() -> Bool {
        let before = orgPeople.count
        let linked = Set(orgPeople.compactMap(\.linkedSubordinateId))
        for sub in subordinates where !linked.contains(sub.id) {
            syncOrgPersonFor(subordinate: sub)
        }
        return orgPeople.count > before
    }

    // MARK: - 部門 CRUD

    func add(_ item: Department) { departments.append(item) }
    func update(_ item: Department) {
        if let i = departments.firstIndex(where: { $0.id == item.id }) { departments[i] = item }
    }
    func deleteDepartment(_ item: Department) { departments.removeAll { $0.id == item.id } }

    // MARK: - 職等對應職稱 CRUD

    func add(_ item: GradeTitle) { gradeTitles.append(item) }
    func update(_ item: GradeTitle) {
        if let i = gradeTitles.firstIndex(where: { $0.id == item.id }) { gradeTitles[i] = item }
    }
    func deleteGradeTitle(_ item: GradeTitle) { gradeTitles.removeAll { $0.id == item.id } }

    // MARK: - 公司組織人員 CRUD

    func add(_ item: OrgPerson) { orgPeople.append(item) }
    func update(_ item: OrgPerson) {
        if let i = orgPeople.firstIndex(where: { $0.id == item.id }) { orgPeople[i] = item }
    }
    func deleteOrgPerson(_ item: OrgPerson) {
        if let name = item.photoFileName { OrgPerson.deletePhoto(name) }
        isLoading = true
        // 解除名片反向連結
        if let cid = item.linkedBusinessCardId,
           let i = businessCards.firstIndex(where: { $0.id == cid }),
           businessCards[i].linkedOrgPersonId == item.id {
            businessCards[i].linkedOrgPersonId = nil
        }
        orgPeople.removeAll { $0.id == item.id }
        isLoading = false
        save()
    }

    func add(_ item: BusinessCard) { businessCards.append(item) }
    func update(_ item: BusinessCard) {
        if let i = businessCards.firstIndex(where: { $0.id == item.id }) { businessCards[i] = item }
    }
    func deleteBusinessCard(_ item: BusinessCard) {
        if let name = item.photoFileName { BusinessCard.deletePhoto(name) }
        isLoading = true
        // 解除組織人員反向連結
        if let pid = item.linkedOrgPersonId,
           let i = orgPeople.firstIndex(where: { $0.id == pid }),
           orgPeople[i].linkedBusinessCardId == item.id {
            orgPeople[i].linkedBusinessCardId = nil
        }
        businessCards.removeAll { $0.id == item.id }
        isLoading = false
        save()
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
                        category: .marriage,
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

    /// 房地產衍生里程碑（傳入理財房地產列表，產生購入/售出虛擬里程碑）
    func realEstateDerivedMilestones(from realEstates: [RealEstate]) -> [LifeMilestone] {
        var items: [LifeMilestone] = []
        for re in realEstates {
            let priceNote = re.purchasePrice > 0
                ? String(format: "%.0f 萬", re.purchasePrice / 10000) : ""
            items.append(LifeMilestone(
                id: deriveID(re.id, suffix: "re-purchase"),
                title: "購入 \(re.name)",
                date: re.purchaseDate,
                category: .realEstate,
                note: priceNote
            ))
            if let sd = re.soldDate {
                items.append(LifeMilestone(
                    id: deriveID(re.id, suffix: "re-sold"),
                    title: "售出 \(re.name)",
                    date: sd,
                    category: .realEstate,
                    note: ""
                ))
            }
        }
        return items
    }

    /// 結合所有里程碑（含家庭與房地產衍生）
    func combinedMilestones(realEstates: [RealEstate]) -> [LifeMilestone] {
        allMilestones + realEstateDerivedMilestones(from: realEstates)
    }

    private func deriveID(_ base: UUID, suffix: String) -> UUID {
        // 使用 FNV-1a 雜湊完整字串（含 suffix），避免 prefix(16) 截掉 suffix 造成所有衍生 ID 相同
        let fullString = base.uuidString + ":" + suffix
        var h: UInt64 = 14_695_981_039_346_656_037
        for b in fullString.utf8 { h = (h ^ UInt64(b)) &* 1_099_511_628_211 }
        let lo = h
        let hi = (h >> 32) ^ (h << 17) ^ 0xA5A5_A5A5_A5A5_A5A5
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 { bytes[i]     = UInt8((lo >> (i * 8)) & 0xff) }
        for i in 0..<8 { bytes[i + 8] = UInt8((hi >> (i * 8)) & 0xff) }
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
        // 捕捉 struct 快照（值型別複製，安全傳入背景執行緒），避免主執行緒同步序列化 12 份資料
        let snap = (
            profile: profile, familyMembers: familyMembers, milestones: milestones,
            relationships: relationships, pets: pets, schedules: schedules,
            subordinates: subordinates, departments: departments, gradeTitles: gradeTitles,
            businessCards: businessCards, personalEvents: personalEvents, orgPeople: orgPeople
        )
        saveQueue.async {
            let encoder = JSONEncoder()
            let ud = UserDefaults.standard
            if let d = try? encoder.encode(snap.profile)        { ud.set(d, forKey: "life_profile") }
            if let d = try? encoder.encode(snap.familyMembers)  { ud.set(d, forKey: "life_family") }
            if let d = try? encoder.encode(snap.milestones)     { ud.set(d, forKey: "life_milestones") }
            if let d = try? encoder.encode(snap.relationships)  { ud.set(d, forKey: "life_relationships") }
            if let d = try? encoder.encode(snap.pets)           { ud.set(d, forKey: "life_pets") }
            if let d = try? encoder.encode(snap.schedules)      { ud.set(d, forKey: "life_schedules") }
            if let d = try? encoder.encode(snap.subordinates)   { ud.set(d, forKey: "life_subordinates") }
            if let d = try? encoder.encode(snap.departments)    { ud.set(d, forKey: "life_departments") }
            if let d = try? encoder.encode(snap.gradeTitles)    { ud.set(d, forKey: "life_grade_titles") }
            if let d = try? encoder.encode(snap.businessCards)  { ud.set(d, forKey: "life_business_cards") }
            if let d = try? encoder.encode(snap.personalEvents) { ud.set(d, forKey: "life_personal_events") }
            if let d = try? encoder.encode(snap.orgPeople)      { ud.set(d, forKey: "life_org_people") }
            CloudSyncManager.shared.pushAll()
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
        if let data = UserDefaults.standard.data(forKey: "life_subordinates"),
           let items = try? decoder.decode([Subordinate].self, from: data) {
            subordinates = items
        }
        if let data = UserDefaults.standard.data(forKey: "life_departments"),
           let items = try? decoder.decode([Department].self, from: data) {
            departments = items
        }
        if let data = UserDefaults.standard.data(forKey: "life_grade_titles"),
           let items = try? decoder.decode([GradeTitle].self, from: data) {
            gradeTitles = items
        }
        if let data = UserDefaults.standard.data(forKey: "life_business_cards"),
           let items = try? decoder.decode([BusinessCard].self, from: data) {
            businessCards = items
        }
        if let data = UserDefaults.standard.data(forKey: "life_personal_events"),
           let items = try? decoder.decode([PersonalEvent].self, from: data) {
            personalEvents = items
        }
        if let data = UserDefaults.standard.data(forKey: "life_org_people"),
           let items = try? decoder.decode([OrgPerson].self, from: data) {
            orgPeople = items
        }
    }

    // MARK: - 清除

    func clearAll() {
        isLoading = true
        profile = UserProfile()
        familyMembers.removeAll()
        milestones.removeAll()
        relationships.removeAll()
        pets.removeAll()
        schedules.removeAll()
        subordinates.removeAll()
        departments.removeAll()
        gradeTitles.removeAll()
        businessCards.removeAll()
        personalEvents.removeAll()
        orgPeople.removeAll()
        isLoading = false
        save()
    }
}
