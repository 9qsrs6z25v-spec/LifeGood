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
    @Published var healthProfile: HealthProfile = HealthProfile() { didSet { if !isLoading { save() } } }
    @Published var familyTasks: [FamilyTask] = [] { didSet { if !isLoading { save() } } }
    /// 機台池：全公司的設備（機台）共用清單。機台屬於部門（departmentId）、
    /// 由部屬擔任負責人（ownerId）；PM／警報等生老病死記錄跟著機台，換負責人不搬記錄。
    @Published var equipmentPool: [ManagedEquipment] = [] { didSet { if !isLoading { save() } } }

    private var isLoading = false
    private let saveQueue = DispatchQueue(label: "com.lifegood.lifestore.save", qos: .utility)
    /// 記錄每個 key 上次成功套用到 @Published 屬性的原始 Data，供 load() 判斷是否真的有變更。
    /// reloadFromCloud() 只要有任一 owned key 命中就會整批呼叫 load()，但雲端這輪可能只改了
    /// 其中一個 key（例如 life_pets）；若不比對直接照舊全部重新賦值，其餘 12 個集合會用「完全相同」
    /// 的資料再次觸發 @Published／進場動畫，造成畫面無謂重繪閃爍。
    private var lastLoadedRawData: [String: Data] = [:]

    /// 本 Store 負責的所有 UserDefaults key，供 reloadFromCloud 比對 userInfo["keys"] 用
    private static let ownedKeys: Set<String> = [
        "life_profile", "life_family", "life_milestones", "life_relationships",
        "life_pets", "life_schedules", "life_subordinates", "life_departments",
        "life_grade_titles", "life_business_cards", "life_personal_events",
        "life_org_people", "life_health_profile", "life_family_tasks",
        "life_equipment_pool"
    ]

    init() {
        load()
        // 用 defer 重置，避免日後在中間加入 guard/return 導致 isLoading 卡死為 true（save() 永久停擺）
        isLoading = true
        defer { isLoading = false }
        let didBackfill = backfillOrgPeopleFromSubordinates()
        let didRepair = repairSideRoleMemberLinks()
        let didMigrateEq = migrateLegacyEquipmentsToPool()
        if didBackfill || didRepair || didMigrateEq { save() }
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

    @objc private func reloadFromCloud(_ note: Notification) {
        // userInfo["keys"] 有帶入且與本 Store 無關時（例如只有 ExpenseStore/FinanceStore 的
        // 資料變更）跳過重載，避免家庭/組織圖/行事曆等不相關畫面無謂重繪、進場動畫重播；
        // 未帶 keys（首次同步覆蓋／合併）維持全量重載。
        if let keys = note.userInfo?["keys"] as? [String],
           Set(keys).isDisjoint(with: Self.ownedKeys) {
            return
        }
        load()
        // backfill 期間暫停 save()，避免剛從雲端拉取就立刻回寫；用 defer 重置，
        // 避免日後在中間加入 guard/return 導致 isLoading 卡死為 true（save() 永久停擺）
        isLoading = true
        defer { isLoading = false }
        let didBackfill = backfillOrgPeopleFromSubordinates()
        let didRepair = repairSideRoleMemberLinks()
        // 雲端另一台裝置若仍是舊版（機台存在部屬身上），拉下來後在這裡搬進機台池
        let didMigrateEq = migrateLegacyEquipmentsToPool()
        // 若 backfill 新建了 OrgPerson/BusinessCard 或修復了成員連結，立即持久化避免重啟後消失
        if didBackfill || didRepair || didMigrateEq { save() }
    }

    // MARK: - 個人檔案

    func updateProfile(_ profile: UserProfile) { self.profile = profile }

    // MARK: - 健康檔案

    func updateHealthProfile(_ profile: HealthProfile) { self.healthProfile = profile }

    // MARK: - 家庭成員 CRUD

    func add(_ item: FamilyMember) { familyMembers.append(item) }
    func update(_ item: FamilyMember) {
        if let i = familyMembers.firstIndex(where: { $0.id == item.id }) { familyMembers[i] = item }
    }
    func deleteFamilyMember(_ item: FamilyMember) {
        isLoading = true
        defer { isLoading = false }
        Self.cleanupFamilyMemberFiles(item)
        familyMembers.removeAll { $0.id == item.id }
        // 解除配偶配對：ResumeView 儲存配偶關係時會雙向寫入 spouseId（見 ResumeView.swift
        // 附近 "spouseId = memberId" 的配對邏輯），刪除任一方若不清掉另一方的 spouseId，
        // 會永久指向一筆已不存在的成員 id，比照 deleteSubordinate 解除 linkedSubordinateId 的既有寫法補上。
        if let i = familyMembers.firstIndex(where: { $0.spouseId == item.id }) {
            familyMembers[i].spouseId = nil
        }
        // 家庭待辦的指派一併解除，避免懸空 id（待辦本身保留——事情還是要做）
        for i in familyTasks.indices where familyTasks[i].assigneeIds.contains(item.id) {
            familyTasks[i].assigneeIds.removeAll { $0 == item.id }
        }
        save()
    }

    /// 刪除家庭成員時一併清掉兒女記錄照片與家庭相簿照片，
    /// 否則檔案會永久留在磁碟並被 CloudKitManager.uploadAllLocalPhotos() 當成
    /// 「未上傳的本機照片」反覆重傳（對齊 deleteOrgPerson／deleteBusinessCard 的既有寫法）。
    private static func cleanupFamilyMemberFiles(_ item: FamilyMember) {
        for record in item.childRecords {
            if let name = record.photoFileName { ChildRecord.deletePhoto(name) }
        }
        for photo in item.familyPhotos {
            if let name = photo.photoFileName { FamilyAlbumPhoto.deletePhoto(name) }
        }
    }

    // MARK: - 家庭待辦 CRUD（含 Apple 提醒事項同步）

    /// 家庭待辦的提醒事項標題／備註（家庭與部屬兩邊格式一致，方便在提醒事項裡辨識）
    private func familyTaskReminderPayload(_ t: FamilyTask) -> (title: String, notes: String) {
        let names = t.assigneeIds.compactMap { id -> String? in
            guard let m = familyMembers.first(where: { $0.id == id }) else { return nil }
            return m.chineseName.isEmpty ? m.englishName : m.chineseName
        }.filter { !$0.isEmpty }
        var notes = "美好人生・家庭待辦"
        if !names.isEmpty { notes += "｜指派：\(names.joined(separator: "、"))" }
        if !t.note.isEmpty { notes += "\n\(t.note)" }
        return (t.content, notes)
    }

    @MainActor
    func upsertFamilyTask(_ task: FamilyTask) {
        // 先落地（按鈕立即有反應），提醒事項在背景補——EventKit 是對系統服務的
        // 同步往返，放在儲存路徑上會讓每次按「新增」卡零點幾秒（v25.246 教訓）
        if let i = familyTasks.firstIndex(where: { $0.id == task.id }) { familyTasks[i] = task }
        else { familyTasks.append(task) }
        scheduleFamilyTaskReminderSync(task.id)
    }

    /// 家庭待辦的提醒同步（背景執行，完成後寫回 reminderId）
    @MainActor
    private func scheduleFamilyTaskReminderSync(_ taskId: UUID) {
        guard ReminderBridge.enabledAndAuthorized,
              let t = familyTasks.first(where: { $0.id == taskId }) else { return }
        let payload = familyTaskReminderPayload(t)
        Task { [weak self] in
            let newId = await ReminderBridge.shared.upsertAsync(
                id: t.reminderId, title: payload.title,
                due: t.dueDate, notes: payload.notes, isCompleted: t.isCompleted)
            guard let self, newId != t.reminderId else { return }
            await MainActor.run {
                guard let i = self.familyTasks.firstIndex(where: { $0.id == taskId }) else { return }
                self.familyTasks[i].reminderId = newId
            }
        }
    }

    @MainActor
    func deleteFamilyTask(_ taskId: UUID) {
        if let t = familyTasks.first(where: { $0.id == taskId }) {
            ReminderBridge.shared.deleteAsync(id: t.reminderId)
        }
        familyTasks.removeAll { $0.id == taskId }
    }

    @MainActor
    func toggleFamilyTaskCompletion(_ taskId: UUID) {
        guard var t = familyTasks.first(where: { $0.id == taskId }) else { return }
        t.isCompleted.toggle()
        t.completedAt = t.isCompleted ? Date() : nil
        upsertFamilyTask(t)
    }

    // MARK: - 部屬任務 → 提醒事項

    /// 部屬任務的提醒同步（家庭與部屬共用 ReminderBridge；未開同步時整段 no-op）。
    /// EventKit 在背景佇列執行、完成後回主執行緒寫回 reminderId——
    /// 同步版本曾讓「新增任務」按鈕卡零點幾秒（使用者回報）。
    @MainActor
    func syncReminderForSubordinateTask(subordinateId: UUID, taskId: UUID) {
        guard ReminderBridge.enabledAndAuthorized else { return }
        guard let si = subordinates.firstIndex(where: { $0.id == subordinateId }),
              let ti = subordinates[si].tasks.firstIndex(where: { $0.id == taskId }) else { return }
        let t = subordinates[si].tasks[ti]
        let title = t.content.isEmpty ? (t.topic.isEmpty ? "部屬任務" : t.topic) : t.content
        var notes = "美好人生・部屬任務｜\(subordinates[si].name)"
        if !t.note.isEmpty { notes += "\n\(t.note)" }
        Task { [weak self] in
            let newId = await ReminderBridge.shared.upsertAsync(
                id: t.reminderId, title: title, due: t.dueDate,
                notes: notes, isCompleted: t.isCompleted)
            guard let self, newId != t.reminderId else { return }
            await MainActor.run {
                guard let si = self.subordinates.firstIndex(where: { $0.id == subordinateId }),
                      let ti = self.subordinates[si].tasks.firstIndex(where: { $0.id == taskId })
                else { return }
                self.isLoading = true
                self.subordinates[si].tasks[ti].reminderId = newId
                self.isLoading = false
                self.save()
            }
        }
    }

    /// 開啟同步時的一次性回補：把現有「未完成」的家庭待辦與部屬任務全部建進提醒事項。
    /// 已完成的不回補——把幾百筆做完的事塞進提醒事項只會變垃圾山。
    /// 整批在背景逐筆執行（幾十筆＝幾十次系統服務往返，同步跑會凍住 UI 好幾秒），
    /// 全部完成後一次寫回 reminderId。
    @MainActor
    func backfillRemindersForAllTasks() {
        guard ReminderBridge.enabledAndAuthorized else { return }
        // 先在主執行緒收集工作清單（值型別快照，背景用不到 @Published）
        struct Job { let kind: Int; let ownerId: UUID; let taskId: UUID
                     let existingId: String?; let title: String; let due: Date?; let notes: String }
        var jobs: [Job] = []
        for t in familyTasks where !t.isCompleted {
            let p = familyTaskReminderPayload(t)
            jobs.append(Job(kind: 0, ownerId: t.id, taskId: t.id,
                            existingId: t.reminderId, title: p.title, due: t.dueDate, notes: p.notes))
        }
        for sub in subordinates {
            for t in sub.tasks where !t.isCompleted {
                let title = t.content.isEmpty ? (t.topic.isEmpty ? "部屬任務" : t.topic) : t.content
                var notes = "美好人生・部屬任務｜\(sub.name)"
                if !t.note.isEmpty { notes += "\n\(t.note)" }
                jobs.append(Job(kind: 1, ownerId: sub.id, taskId: t.id,
                                existingId: t.reminderId, title: title, due: t.dueDate, notes: notes))
            }
        }
        guard !jobs.isEmpty else { return }
        Task { [weak self] in
            var results: [(Job, String?)] = []
            for job in jobs {
                let newId = await ReminderBridge.shared.upsertAsync(
                    id: job.existingId, title: job.title, due: job.due,
                    notes: job.notes, isCompleted: false)
                if newId != job.existingId { results.append((job, newId)) }
            }
            guard let self, !results.isEmpty else { return }
            await MainActor.run {
                self.isLoading = true
                for (job, newId) in results {
                    if job.kind == 0 {
                        if let i = self.familyTasks.firstIndex(where: { $0.id == job.taskId }) {
                            self.familyTasks[i].reminderId = newId
                        }
                    } else if let si = self.subordinates.firstIndex(where: { $0.id == job.ownerId }),
                              let ti = self.subordinates[si].tasks.firstIndex(where: { $0.id == job.taskId }) {
                        self.subordinates[si].tasks[ti].reminderId = newId
                    }
                }
                self.isLoading = false
                self.save()
            }
        }
    }

    // MARK: - 里程碑 CRUD

    func add(_ item: LifeMilestone) { milestones.append(item) }
    func update(_ item: LifeMilestone) {
        if let i = milestones.firstIndex(where: { $0.id == item.id }) { milestones[i] = item }
    }
    func deleteMilestone(_ item: LifeMilestone) { milestones.removeAll { $0.id == item.id } }

    // MARK: - 配偶協定

    /// 對某位家庭成員就地改一次，保證只觸發一次 familyMembers 的 didSet
    ///（一次存檔、一次 CloudKit 推送）。
    func mutateFamilyMember(_ id: UUID, _ body: (inout FamilyMember) -> Void) {
        guard let i = familyMembers.firstIndex(where: { $0.id == id }) else { return }
        var m = familyMembers[i]
        body(&m)
        familyMembers[i] = m
    }

    func upsertAgreement(_ agreement: SpouseAgreement, for memberId: UUID) {
        mutateFamilyMember(memberId) { m in
            var list = m.agreements ?? []
            if let i = list.firstIndex(where: { $0.id == agreement.id }) { list[i] = agreement }
            else { list.append(agreement) }
            m.agreements = list
        }
    }

    func deleteAgreement(_ agreementId: UUID, for memberId: UUID) {
        mutateFamilyMember(memberId) { $0.agreements?.removeAll { $0.id == agreementId } }
    }

    // MARK: - 兼任職務

    /// 全部兼任職務里程碑，新到舊
    var sideRoles: [LifeMilestone] {
        milestones.filter { $0.isSideRole }.sorted { $0.date > $1.date }
    }

    /// 已啟用專屬管理頁的兼任職務（在任的排前面，其次依就任日新到舊）
    var sideRoleWorkspaces: [LifeMilestone] {
        sideRoles.filter { $0.hasSideRoleWorkspace }
            .sorted {
                if $0.isActiveSideRole != $1.isActiveSideRole { return $0.isActiveSideRole }
                return $0.date > $1.date
            }
    }

    /// 有內容但管理頁被關掉的兼任職務。
    /// 用來在管理中樞底下列出「已停用」區塊——關開關只隱藏入口、資料仍在，
    /// 但如果畫面上完全看不到，使用者會判定資料遺失並重新輸入一遍，
    /// 那就等於白做了「不清除」的保護。
    var dormantSideRoles: [LifeMilestone] {
        sideRoles.filter { !$0.hasSideRoleWorkspace && $0.hasAnySideRoleContent }
    }

    /// 指定時間點上的本職職稱（兼任職務卡片要顯示「當時我是副理」）。
    /// 同樣只看本職異動，不會被兼任自己污染。
    func baseJobTitle(at date: Date) -> String? {
        let employmentSubs: Set<CareerSubCategory> = [.join, .promote, .transfer, .demote]
        return milestones
            .filter { m in
                guard m.category == .career, m.date <= date,
                      let sub = m.careerSubCategory else { return false }
                return employmentSubs.contains(sub)
            }
            .sorted { $0.date > $1.date }
            .first
            .flatMap { $0.jobTitle?.trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    /// 對某筆兼任職務就地改一次。所有子項目 CRUD 都走這裡，
    /// 保證只觸發一次 milestones 的 didSet（一次存檔、一次 CloudKit 推送）。
    func mutateSideRole(_ id: UUID, _ body: (inout LifeMilestone) -> Void) {
        guard let i = milestones.firstIndex(where: { $0.id == id }) else { return }
        var m = milestones[i]
        body(&m)
        milestones[i] = m
    }

    /// 寫入兼任待辦，並立刻把連結同步到部屬那一側。
    /// 所有寫入點（編輯頁存檔、待辦列打勾）都走這裡，同步邏輯才只有一份。
    func upsertSideRoleTask(_ task: SideRoleTask, in roleId: UUID) {
        batched {
            mutateSideRole(roleId) { m in
                var list = m.sideRoleTasks ?? []
                if let i = list.firstIndex(where: { $0.id == task.id }) { list[i] = task }
                else { list.append(task) }
                m.sideRoleTasks = list
            }
            syncSideRoleTaskLinksBody(task.id, in: roleId)
        }
    }

    /// 刪除兼任待辦。系統自動建立的部屬任務一併刪掉（那是這則待辦的分身）；
    /// 從部屬那邊拉進來的紀錄只解除連結——那筆本來就存在，不該替使用者刪掉。
    func deleteSideRoleTask(_ taskId: UUID, in roleId: UUID) {
        let links = milestones.first { $0.id == roleId }?
            .sideRoleTasks?.first { $0.id == taskId }?.links ?? []
        batched {
            detachLinks(links)
            mutateSideRole(roleId) { $0.sideRoleTasks?.removeAll { $0.id == taskId } }
        }
    }

    /// 這則待辦會連帶刪掉幾筆自動建立的部屬任務（刪除確認用）
    func autoCreatedLinkCount(taskId: UUID, in roleId: UUID) -> Int {
        (milestones.first { $0.id == roleId }?
            .sideRoleTasks?.first { $0.id == taskId }?.links ?? [])
            .filter(\.isAutoCreated).count
    }

    func upsertSideRoleMember(_ member: SideRoleMember, in roleId: UUID) {
        mutateSideRole(roleId) { m in
            var list = m.sideRoleMembers ?? []
            if let i = list.firstIndex(where: { $0.id == member.id }) { list[i] = member }
            else { list.append(member) }
            m.sideRoleMembers = list
        }
    }

    func deleteSideRoleMember(_ memberId: UUID, in roleId: UUID) {
        var affected: [UUID] = []
        batched {
            mutateSideRole(roleId) { m in
                m.sideRoleMembers?.removeAll { $0.id == memberId }
                // 連帶把待辦上的指派清掉，否則會留下指向不存在成員的懸空引用——
                // 那些待辦在成員頁查不到、在待辦列上又會顯示一個空白的負責人。
                // 比照 deleteFamilyMember 解除 spouseId、deleteMilestoneCleaningLinks 的既有做法。
                m.sideRoleTasks = m.sideRoleTasks?.map { t in
                    guard var ids = t.assigneeIds, ids.contains(memberId) else { return t }
                    ids.removeAll { $0 == memberId }
                    var copy = t
                    copy.assigneeIds = ids.isEmpty ? nil : ids
                    affected.append(copy.id)
                    return copy
                }
            }
            // 少了一位負責人，他名下自動建立的部屬任務就該收回——
            // 不重跑同步的話，那些任務會留在對方的清單上，而兼任這邊已經查不到了。
            for tid in affected { syncSideRoleTaskLinksBody(tid, in: roleId) }
        }
    }

    // MARK: - 兼任待辦 ↔ 部屬紀錄 雙向連結
    //
    // 使用者要的是「同一件事的兩面」，不是兩筆各自獨立的紀錄：
    //   • 指派給部屬 → 自動在他的任務清單建一筆（不用兩邊各打一次字）
    //   • 任一邊打勾 → 另一邊跟著完成
    //   • 評分只算一次（走兼任那邊的 +3，本職那邊跳過），否則同一件事 +6
    //
    // 兩側各存一份指標（SideRoleTaskLink / SideRoleBackLink）。只存單側的話，
    // 從部屬那邊打勾就得掃遍所有兼任職務的所有待辦才找得到對象——而打勾是熱路徑。

    /// 把一段會多次寫入 @Published 陣列的操作包成「只存一次檔」。
    /// 連結同步一次可能改到三、四位部屬，每次 subscript 寫回都會觸發
    /// didSet → save() → CloudKit 推送，不批次的話一次指派就是十幾次存檔。
    /// 巢狀呼叫安全：內層還原成外層原本的值，只有最外層那次真的 save()。
    private func batched(_ body: () -> Void) {
        let wasLoading = isLoading
        isLoading = true
        body()
        isLoading = wasLoading
        if !wasLoading { save() }
    }

    /// 把某筆兼任待辦的狀態推到部屬那一側：
    /// 補上新指派的人、收回取消指派的人、同步內容與完成狀態。
    func syncSideRoleTaskLinks(_ taskId: UUID, in roleId: UUID) {
        batched { syncSideRoleTaskLinksBody(taskId, in: roleId) }
    }

    private func syncSideRoleTaskLinksBody(_ taskId: UUID, in roleId: UUID) {
        guard let ri = milestones.firstIndex(where: { $0.id == roleId }),
              let ti = milestones[ri].sideRoleTasks?.firstIndex(where: { $0.id == taskId }),
              var task = milestones[ri].sideRoleTasks?[ti] else { return }

        let roleTitle = milestones[ri].sideRoleName?.trimmingCharacters(in: .whitespaces) ?? ""
        let topic = roleTitle.isEmpty ? "兼任職務" : roleTitle

        // 指派對象 → 部屬 id。名片與組織人員不是部屬，沒有任務清單可以放，
        // 硬要建會產生一筆沒有歸屬的孤兒任務。
        let subIds = Set(subordinates.map(\.id))
        var linkOf: [UUID: UUID] = [:]
        for m in milestones[ri].sideRoleMembers ?? [] where m.linkedPersonId != nil {
            linkOf[m.id] = m.linkedPersonId
        }
        var desired = Set<UUID>()
        for mid in task.assigneeIds ?? [] {
            if let pid = linkOf[mid], subIds.contains(pid) { desired.insert(pid) }
        }

        var links = task.links ?? []
        let back = SideRoleBackLink(roleId: roleId, taskId: taskId)

        // 1. 取消指派 → 收回當初自動建立的那筆任務。
        //    手動拉進來的連結不受指派變動影響：那是使用者刻意接上的一筆既有紀錄，
        //    不該因為指派名單一動就自己斷掉（要斷請按解除連結）。
        var dropped: [SideRoleTaskLink] = []
        links.removeAll { link in
            guard link.isAutoCreated, !desired.contains(link.subordinateId) else { return false }
            dropped.append(link)
            return true
        }
        detachLinks(dropped)

        // 2. 既有連結：同步內容與完成狀態
        for link in links {
            guard let si = subordinates.firstIndex(where: { $0.id == link.subordinateId }) else { continue }
            switch link.kind {
            case .task:
                guard let i = subordinates[si].tasks.firstIndex(where: { $0.id == link.itemId }) else { continue }
                if link.isAutoCreated {
                    // 自動建立的那筆是分身，內容以兼任這邊為準
                    subordinates[si].tasks[i].topic = topic
                    subordinates[si].tasks[i].content = task.content
                    subordinates[si].tasks[i].dueDate = task.dueDate
                    subordinates[si].tasks[i].note = task.note
                }
                subordinates[si].tasks[i].isCompleted = task.isCompleted
                subordinates[si].tasks[i].completedAt = task.completedAt
                subordinates[si].tasks[i].sideRoleLink = back
            case .meetingItem:
                guard let mid = link.meetingId,
                      let mi = subordinates[si].meetings.firstIndex(where: { $0.id == mid }) else { continue }
                mutateMeetingItem(&subordinates[si].meetings[mi], itemId: link.itemId) { item in
                    item.isCompleted = task.isCompleted
                    item.completedAt = task.completedAt
                    item.sideRoleLink = back
                }
            }
        }

        // 3. 新指派的人：自動建一筆任務
        let linked = Set(links.map(\.subordinateId))
        for pid in desired where !linked.contains(pid) {
            guard let si = subordinates.firstIndex(where: { $0.id == pid }) else { continue }
            let newTask = SubordinateTask(topic: topic, content: task.content,
                                          date: Date(), dueDate: task.dueDate, note: task.note,
                                          isCompleted: task.isCompleted, completedAt: task.completedAt,
                                          sideRoleLink: back)
            subordinates[si].tasks.append(newTask)
            links.append(SideRoleTaskLink(kind: .task, subordinateId: pid,
                                          itemId: newTask.id, isAutoCreated: true))
        }

        task.links = links.isEmpty ? nil : links
        milestones[ri].sideRoleTasks?[ti] = task
    }

    /// 把某筆既有的部屬任務／會議議程項目「拉進」某則兼任待辦。
    /// isAutoCreated = false，所以日後解除連結時只斷線、不刪紀錄。
    func linkExistingItemToSideRoleTask(_ link: SideRoleTaskLink, taskId: UUID, in roleId: UUID) {
        guard let ri = milestones.firstIndex(where: { $0.id == roleId }),
              let ti = milestones[ri].sideRoleTasks?.firstIndex(where: { $0.id == taskId }) else { return }
        var links = milestones[ri].sideRoleTasks?[ti].links ?? []
        // 同一筆紀錄只連一次
        guard !links.contains(where: { $0.itemId == link.itemId }) else { return }
        batched {
            links.append(link)
            milestones[ri].sideRoleTasks?[ti].links = links
            syncSideRoleTaskLinksBody(taskId, in: roleId)
        }
    }

    /// 解除一條連結（不刪兼任待辦本身）
    func unlinkSideRoleTaskLink(itemId: UUID, taskId: UUID, in roleId: UUID) {
        guard let ri = milestones.firstIndex(where: { $0.id == roleId }),
              let ti = milestones[ri].sideRoleTasks?.firstIndex(where: { $0.id == taskId }) else { return }
        batched {
            var links = milestones[ri].sideRoleTasks?[ti].links ?? []
            let removed = links.filter { $0.itemId == itemId }
            links.removeAll { $0.itemId == itemId }
            milestones[ri].sideRoleTasks?[ti].links = links.isEmpty ? nil : links
            detachLinks(removed)
            // 立刻重跑同步：若那個人還在指派名單上，規則是「指派就要有一筆」，
            // 這裡會補一筆自動建立的給他。不重跑的話狀態要拖到下次存檔才收斂，
            // 使用者會看到「解除後什麼都沒發生、隔一陣子又冒出一筆」。
            syncSideRoleTaskLinksBody(taskId, in: roleId)
        }
    }

    /// 從部屬那一側打勾時呼叫：更新兼任待辦，再散布到同一則待辦的其他連結。
    /// 刻意不走 upsertSideRoleTask——那會再繞回來，形成來回同步。
    func propagateCompletionToSideRole(_ back: SideRoleBackLink, isCompleted: Bool) {
        guard let ri = milestones.firstIndex(where: { $0.id == back.roleId }),
              let ti = milestones[ri].sideRoleTasks?.firstIndex(where: { $0.id == back.taskId }) else { return }
        milestones[ri].sideRoleTasks?[ti].isCompleted = isCompleted
        milestones[ri].sideRoleTasks?[ti].completedAt = isCompleted ? Date() : nil
        let task = milestones[ri].sideRoleTasks?[ti]
        for link in task?.links ?? [] {
            guard let si = subordinates.firstIndex(where: { $0.id == link.subordinateId }) else { continue }
            switch link.kind {
            case .task:
                guard let i = subordinates[si].tasks.firstIndex(where: { $0.id == link.itemId }) else { continue }
                subordinates[si].tasks[i].isCompleted = isCompleted
                subordinates[si].tasks[i].completedAt = task?.completedAt
            case .meetingItem:
                guard let mid = link.meetingId,
                      let mi = subordinates[si].meetings.firstIndex(where: { $0.id == mid }) else { continue }
                mutateMeetingItem(&subordinates[si].meetings[mi], itemId: link.itemId) { item in
                    item.isCompleted = isCompleted
                    item.completedAt = task?.completedAt
                }
            }
        }
    }

    /// 連結列要顯示的文字。對象已被刪除時給明確字樣，不留空白列。
    func sideRoleLinkDescription(_ link: SideRoleTaskLink) -> (title: String, subtitle: String) {
        guard let sub = subordinates.first(where: { $0.id == link.subordinateId }) else {
            return ("已刪除的紀錄", "原負責人已不在部屬名單")
        }
        let who = sub.name.isEmpty ? "未命名部屬" : sub.name
        switch link.kind {
        case .task:
            guard let t = sub.tasks.first(where: { $0.id == link.itemId }) else {
                return ("已刪除的任務", who)
            }
            let title = t.content.isEmpty ? (t.topic.isEmpty ? "未命名任務" : t.topic) : t.content
            return (title, "\(who)・任務")
        case .meetingItem:
            for m in sub.meetings {
                guard let item = m.allItems.first(where: { $0.id == link.itemId }) else { continue }
                let title = item.content.isEmpty ? "未填內容" : item.content
                return (title, "\(who)・\(m.topic.isEmpty ? "會議" : m.topic)")
            }
            return ("已刪除的議程項目", who)
        }
    }

    /// 收回連結：自動建立的紀錄整筆刪掉，拉進來的只清掉回指。
    private func detachLinks(_ links: [SideRoleTaskLink]) {
        for link in links {
            guard let si = subordinates.firstIndex(where: { $0.id == link.subordinateId }) else { continue }
            switch link.kind {
            case .task:
                if link.isAutoCreated {
                    subordinates[si].tasks.removeAll { $0.id == link.itemId }
                } else if let i = subordinates[si].tasks.firstIndex(where: { $0.id == link.itemId }) {
                    subordinates[si].tasks[i].sideRoleLink = nil
                }
            case .meetingItem:
                // 議程項目一律是「拉進來的」——系統不會自動建會議
                guard let mid = link.meetingId,
                      let mi = subordinates[si].meetings.firstIndex(where: { $0.id == mid }) else { continue }
                mutateMeetingItem(&subordinates[si].meetings[mi], itemId: link.itemId) { $0.sideRoleLink = nil }
            }
        }
    }

    /// 改一筆議程項目——不重複的會議住在 items，有週期的住在各場次，
    /// 兩處都要找，只找 items 的話週期會議上的連結會靜默失效。
    private func mutateMeetingItem(_ meeting: inout SubordinateMeeting, itemId: UUID,
                                   _ body: (inout MeetingItem) -> Void) {
        if let i = meeting.items.firstIndex(where: { $0.id == itemId }) {
            body(&meeting.items[i]); return
        }
        for oi in meeting.occurrences.indices {
            guard let i = meeting.occurrences[oi].items.firstIndex(where: { $0.id == itemId }) else { continue }
            body(&meeting.occurrences[oi].items[i]); return
        }
    }

    /// 部屬評分所需的整批預算結果。
    ///
    /// 兩份都是 O(全體) 的全量掃描，一次算好往下傳，不讓每一列各自重算
    ///（mentionedCounts 的既有教訓）。打包成一個型別而非兩個平行參數：
    /// 評分因子將來還會增加，每加一個就要動遍所有中間層函式的簽章太脆弱。
    struct ScoreContext {
        var mentions: [UUID: Int] = [:]
        var sideRoles: [UUID: (done: Int, total: Int)] = [:]
        func mention(_ id: UUID) -> Int { mentions[id] ?? 0 }
        func sideRoleDone(_ id: UUID) -> Int { sideRoles[id]?.done ?? 0 }
        func sideRoleTotal(_ id: UUID) -> Int { sideRoles[id]?.total ?? 0 }
    }

    func makeScoreContext() -> ScoreContext {
        ScoreContext(mentions: mentionedCounts(), sideRoles: sideRoleTaskCounts())
    }

    /// 一次性修復：把兼任職務成員裡「指向名片」的連結改指回對應的部屬。
    ///
    /// v25.218～v25.224 之間，挑人清單會把同一位部屬同時列成「部屬」與「名片」兩列
    ///（每位有部門的部屬都會自動產生一張名片）。使用者若點到名片那一列，
    /// linkedPersonId 就會存成名片 id——後果是部屬明細頁的「兼任職務參與」查不到、
    /// 他完成的兼任待辦也不計入主動性評分。清單重複已修掉，但已經存進去的資料
    /// 要在這裡改回來。
    ///
    /// 回傳是否有實際變更（供呼叫端決定要不要 save）。
    @discardableResult
    func repairSideRoleMemberLinks() -> Bool {
        // 名片 id → 部屬 id（循「名片 ← 組織人員 → 部屬」的既有連結還原）
        let subIds = Set(subordinates.map(\.id))
        var cardToSub: [UUID: UUID] = [:]
        for p in orgPeople {
            guard let sid = p.linkedSubordinateId, subIds.contains(sid),
                  let cid = p.linkedBusinessCardId else { continue }
            cardToSub[cid] = sid
        }
        guard !cardToSub.isEmpty else { return false }

        var changed = false
        for i in milestones.indices where milestones[i].isSideRole {
            guard var members = milestones[i].sideRoleMembers, !members.isEmpty else { continue }
            var touched = false
            for j in members.indices {
                guard let pid = members[j].linkedPersonId, let sid = cardToSub[pid] else { continue }
                // 這位部屬已經在名單裡（使用者兩列都加過）→ 不要製造兩筆指向同一人，
                // 保留既有那筆、把這筆的連結清掉即可，成員本身不刪（姓名可能已被改過）。
                if members.contains(where: { $0.linkedPersonId == sid }) {
                    members[j].linkedPersonId = nil
                } else {
                    members[j].linkedPersonId = sid
                }
                touched = true
            }
            if touched {
                milestones[i].sideRoleMembers = members
                changed = true
            }
        }
        return changed
    }

    /// 這個人（部屬／名片 id）參與了哪些兼任職務，以及他在各職務裡的成員資料。
    /// 反向查詢用：從部屬明細頁列出「他在哪些兼任職務裡、負責什麼」。
    func sideRoleParticipations(of personId: UUID) -> [(role: LifeMilestone, member: SideRoleMember)] {
        sideRoles.compactMap { role in
            guard let m = role.sideRoleMembers?.first(where: { $0.linkedPersonId == personId })
            else { return nil }
            return (role, m)
        }
    }

    /// 全體「已連結人員」的兼任待辦統計，key 是部屬／名片 id。
    ///
    /// 一次算好整批往下傳，比照 mentionedCounts() 的既有做法——評分被列表、
    /// 人才矩陣、明細頁十餘處呼叫，每處各自全量掃描會是效能災難。
    ///
    /// 只計入 linkedPersonId 有值的成員：手打姓名的外部人員不是部屬，
    /// 不該影響任何人的評分。
    func sideRoleTaskCounts() -> [UUID: (done: Int, total: Int)] {
        var out: [UUID: (done: Int, total: Int)] = [:]
        for role in milestones where role.isSideRole {
            let members = role.sideRoleMembers ?? []
            guard !members.isEmpty else { continue }
            // memberId → personId，避免內層迴圈對成員清單重複線性搜尋
            var linkOf: [UUID: UUID] = [:]
            for m in members where m.linkedPersonId != nil {
                linkOf[m.id] = m.linkedPersonId
            }
            guard !linkOf.isEmpty else { continue }
            for t in role.sideRoleTasks ?? [] {
                for mid in t.assigneeIds ?? [] {
                    guard let pid = linkOf[mid] else { continue }
                    var cur = out[pid] ?? (0, 0)
                    cur.total += 1
                    if t.isCompleted { cur.done += 1 }
                    out[pid] = cur
                }
            }
        }
        return out
    }

    /// 把某位部屬／名片人員加進某筆兼任職務的成員名單。
    /// 已經在名單裡就只回傳 false，不重複新增。
    @discardableResult
    func addPersonToSideRole(_ person: SideRolePersonCandidate, roleId: UUID,
                             dutyInRole: String = "") -> Bool {
        guard let role = milestones.first(where: { $0.id == roleId }) else { return false }
        if (role.sideRoleMembers ?? []).contains(where: { $0.linkedPersonId == person.id }) {
            return false
        }
        let member = SideRoleMember(name: person.name,
                                    dutyInRole: dutyInRole.isEmpty ? person.subtitle : dutyInRole,
                                    contact: person.contact,
                                    linkedPersonId: person.id)
        upsertSideRoleMember(member, in: roleId)
        return true
    }

    /// 某位成員被指派的待辦（依「未完成優先、再依截止日」排序）
    func sideRoleTasks(of memberId: UUID, in role: LifeMilestone) -> [SideRoleTask] {
        (role.sideRoleTasks ?? [])
            .filter { $0.assigneeIds?.contains(memberId) == true }
            .sorted { a, b in
                if a.isCompleted != b.isCompleted { return !a.isCompleted }
                return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture)
            }
    }

    func upsertSideRoleMeeting(_ meeting: SideRoleMeeting, in roleId: UUID) {
        mutateSideRole(roleId) { m in
            var list = m.sideRoleMeetings ?? []
            if let i = list.firstIndex(where: { $0.id == meeting.id }) { list[i] = meeting }
            else { list.append(meeting) }
            m.sideRoleMeetings = list.sorted { $0.date > $1.date }
        }
    }

    func deleteSideRoleMeeting(_ meetingId: UUID, in roleId: UUID) {
        mutateSideRole(roleId) { $0.sideRoleMeetings?.removeAll { $0.id == meetingId } }
    }

    func upsertSideRoleKeyDate(_ keyDate: SideRoleKeyDate, in roleId: UUID) {
        mutateSideRole(roleId) { m in
            var list = m.sideRoleKeyDates ?? []
            if let i = list.firstIndex(where: { $0.id == keyDate.id }) { list[i] = keyDate }
            else { list.append(keyDate) }
            m.sideRoleKeyDates = list.sorted { $0.date < $1.date }
        }
    }

    func deleteSideRoleKeyDate(_ keyDateId: UUID, in roleId: UUID) {
        mutateSideRole(roleId) { $0.sideRoleKeyDates?.removeAll { $0.id == keyDateId } }
    }

    func upsertSideRoleResolution(_ resolution: SideRoleResolution, in roleId: UUID) {
        mutateSideRole(roleId) { m in
            var list = m.sideRoleResolutions ?? []
            if let i = list.firstIndex(where: { $0.id == resolution.id }) { list[i] = resolution }
            else { list.append(resolution) }
            // 新到舊：重大決議通常回頭查最近定案的
            m.sideRoleResolutions = list.sorted { $0.date > $1.date }
        }
    }

    func deleteSideRoleResolution(_ resolutionId: UUID, in roleId: UUID) {
        mutateSideRole(roleId) { $0.sideRoleResolutions?.removeAll { $0.id == resolutionId } }
    }

    /// 找同名兼任職務的上一屆（例：2026 尾牙負責人的上一屆是 2025 那筆）。
    /// 年度性職務每年一筆，名單通常大同小異，重打十幾個人不合理。
    func previousTermOfSideRole(_ role: LifeMilestone) -> LifeMilestone? {
        guard let name = role.sideRoleName?.trimmingCharacters(in: .whitespaces),
              !name.isEmpty else { return nil }
        return sideRoles
            .filter { $0.id != role.id && $0.date < role.date
                      && $0.sideRoleName?.trimmingCharacters(in: .whitespaces) == name }
            .max(by: { $0.date < $1.date })
    }

    /// 把上一屆的成員名單整包複製過來（各人配一組新 id，避免兩屆共用同一個 id）。
    /// 刻意只複製成員：待辦與會議逐屆內容不同，複製過來只會製造要逐條刪除的雜訊。
    /// 回傳實際複製的人數。
    @discardableResult
    func copyMembersFromPreviousTerm(into role: LifeMilestone) -> Int {
        guard let prev = previousTermOfSideRole(role),
              let source = prev.sideRoleMembers, !source.isEmpty else { return 0 }
        let existingNames = Set((role.sideRoleMembers ?? []).map {
            $0.name.trimmingCharacters(in: .whitespaces)
        })
        let incoming = source
            .filter { !existingNames.contains($0.name.trimmingCharacters(in: .whitespaces)) }
            .map {
                SideRoleMember(name: $0.name, dutyInRole: $0.dutyInRole,
                               contact: $0.contact, linkedPersonId: $0.linkedPersonId,
                               note: $0.note)
            }
        guard !incoming.isEmpty else { return 0 }
        mutateSideRole(role.id) { $0.sideRoleMembers = ($0.sideRoleMembers ?? []) + incoming }
        return incoming.count
    }

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
        defer { isLoading = false }
        subordinates.append(item)
        syncOrgPersonFor(subordinate: item)
        save()
    }
    func update(_ item: Subordinate) {
        isLoading = true
        defer { isLoading = false }
        if let i = subordinates.firstIndex(where: { $0.id == item.id }) { subordinates[i] = item }
        syncOrgPersonFor(subordinate: item)
        save()
    }
    func deleteSubordinate(_ item: Subordinate) {
        isLoading = true
        defer { isLoading = false }
        // 刪除其任務對應的 Apple 提醒（先收集 id，人刪了就查不到了）
        let reminderIds = item.tasks.compactMap(\.reminderId)
        for rid in reminderIds { ReminderBridge.shared.deleteAsync(id: rid) }
        // 生日提醒的行事曆事件一併刪除（bridge 是 main actor 隔離，繞主執行緒呼叫）
        if let bid = item.birthdayEventId {
            Task { @MainActor in AppleCalendarBridge.shared.delete(eventIdentifier: bid) }
        }
        subordinates.removeAll { $0.id == item.id }
        // 機台留在池中（生老病死跟著機台），只解除這個人的負責人身分
        for i in equipmentPool.indices where equipmentPool[i].ownerId == item.id {
            equipmentPool[i].ownerId = nil
        }
        // 解除與公司組織人員的連結（保留人員資料以維持歷史）
        if let i = orgPeople.firstIndex(where: { $0.linkedSubordinateId == item.id }) {
            orgPeople[i].linkedSubordinateId = nil
        }
        // 解除其他部屬會議議程項目指派給此人的負責人連結，避免懸空 id
        for si in subordinates.indices {
            for mi in subordinates[si].meetings.indices {
                for ii in subordinates[si].meetings[mi].items.indices {
                    subordinates[si].meetings[mi].items[ii].assigneeIds.removeAll { $0 == item.id }
                }
                for oi in subordinates[si].meetings[mi].occurrences.indices {
                    for ii in subordinates[si].meetings[mi].occurrences[oi].items.indices {
                        subordinates[si].meetings[mi].occurrences[oi].items[ii].assigneeIds.removeAll { $0 == item.id }
                    }
                }
            }
        }
        // 兼任待辦上指向這位部屬的連結一併清掉，否則會留下指向不存在部屬的
        // 懸空引用：同步時查不到人（靜默跳過），但刪除確認會多報一筆。
        for ri in milestones.indices {
            guard milestones[ri].sideRoleTasks != nil else { continue }
            for ti in milestones[ri].sideRoleTasks!.indices {
                guard var links = milestones[ri].sideRoleTasks![ti].links,
                      links.contains(where: { $0.subordinateId == item.id }) else { continue }
                links.removeAll { $0.subordinateId == item.id }
                milestones[ri].sideRoleTasks![ti].links = links.isEmpty ? nil : links
            }
        }
        save()
    }

    /// 切換某位部屬底下某筆任務的完成狀態（總覽頁與詳情頁的快速打勾共用）。
    /// 標記完成時記下 completedAt，取消完成則清空。
    func toggleTaskCompletion(subordinateId: UUID, taskId: UUID) {
        guard let si = subordinates.firstIndex(where: { $0.id == subordinateId }),
              let ti = subordinates[si].tasks.firstIndex(where: { $0.id == taskId }) else { return }
        // isLoading = true 防止兩次 subscript 寫回各自觸發 didSet → save()，
        // 避免「isCompleted 已翻轉但 completedAt 尚未設定」的中間態被持久化。
        // 用 defer 重置，避免日後在中間加入 guard/return 導致 isLoading 卡死為 true（save() 永久停擺）。
        isLoading = true
        defer { isLoading = false }
        subordinates[si].tasks[ti].isCompleted.toggle()
        subordinates[si].tasks[ti].completedAt = subordinates[si].tasks[ti].isCompleted ? Date() : nil
        // 這筆若是某則兼任待辦的另一面，兩邊要一起完成（含指派給同一件事的其他人）
        if let back = subordinates[si].tasks[ti].sideRoleLink {
            propagateCompletionToSideRole(back, isCompleted: subordinates[si].tasks[ti].isCompleted)
        }
        save()
        // Apple 提醒事項同步（開啟時）；hop 到 MainActor 是 ReminderBridge 的隔離要求
        Task { @MainActor in
            self.syncReminderForSubordinateTask(subordinateId: subordinateId, taskId: taskId)
        }
    }

    /// 切換某場會議底下某個議程項目的完成狀態（部屬詳情頁與總覽頁的打勾共用）。
    /// 標記完成時記下 completedAt，取消完成則清空。
    func toggleMeetingItemCompletion(subordinateId: UUID, meetingId: UUID, itemId: UUID) {
        guard let si = subordinates.firstIndex(where: { $0.id == subordinateId }),
              let mi = subordinates[si].meetings.firstIndex(where: { $0.id == meetingId }) else { return }
        // isLoading 阻斷 didSet → save() 的隱式觸發，確保只有下方的顯式 save() 被執行一次
        isLoading = true
        defer { isLoading = false }
        // 有週期的會議，議程項目住在各場次底下；不重複的會議才住在 items。
        // 只找 items 的話，週期會議上的打勾會靜默失效（按了沒反應）。
        var back: SideRoleBackLink?
        var nowCompleted = false
        mutateMeetingItem(&subordinates[si].meetings[mi], itemId: itemId) { item in
            item.isCompleted.toggle()
            item.completedAt = item.isCompleted ? Date() : nil
            back = item.sideRoleLink
            nowCompleted = item.isCompleted
        }
        // 這個項目若是某則兼任待辦的另一面，兩邊要一起完成
        if let back { propagateCompletionToSideRole(back, isCompleted: nowCompleted) }
        save()
    }

    /// 切換某份週報的完成狀態。標記完成時記下 completedAt，取消完成則清空。
    func toggleWeeklyReportCompletion(subordinateId: UUID, reportId: UUID) {
        guard let si = subordinates.firstIndex(where: { $0.id == subordinateId }),
              let ri = subordinates[si].weeklyReports.firstIndex(where: { $0.id == reportId }) else { return }
        // isLoading 阻斷 didSet → save() 的隱式觸發，確保只有下方的顯式 save() 被執行一次
        isLoading = true
        defer { isLoading = false }
        subordinates[si].weeklyReports[ri].isCompleted.toggle()
        subordinates[si].weeklyReports[ri].completedAt = subordinates[si].weeklyReports[ri].isCompleted ? Date() : nil
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
        defer { isLoading = false }
        subordinates[si].shifts.removeAll { cal.isDate($0.date, inSameDayAs: day) }
        if let type = type {
            subordinates[si].shifts.append(SubordinateShift(date: day, type: type))
        }
        save()
    }

    /// 套用大夜班輪班範本（一次 8 天、不循環）：
    /// 第 1 天時差假 → 第 2–7 天大夜班（6 天）→ 第 8 天休息。
    /// 該廠區在指定日期是否已有「其他」部屬排大夜班。
    /// 週五套大夜輪班時的自動分岔判斷（v25.282）：週六晚上該廠已有人輪
    /// （代表對方的輪班到週日結尾、週日交接重疊）→ 本人週六休、週日起大夜；
    /// 週六沒人 → 本人週六就要上、標準序列。
    func plantHasNightShift(on date: Date, plantArea: String, excluding subId: UUID) -> Bool {
        let cal = Calendar.current
        return subordinates.contains { s in
            s.id != subId && s.plantArea == plantArea
                && s.shifts.contains { cal.isDate($0.date, inSameDayAs: date) && $0.type == .nightShift }
        }
    }

    /// 套用大夜班輪班（8 天序列；使用者規則 v25.281 逐日確認版）。
    ///
    /// 標準型（skipSaturday = false）：**點選日＝時差、隔天起大夜 6 晚、第 8 天休**——
    ///   按週一：一時差、二〜日大夜、下週一休；按週二：二時差、三〜下週一大夜、下週二休；
    ///   按週三：三時差、四〜下週二大夜、下週三休…以此類推（含按週五：五時差、
    ///   六〜下週四大夜、下週五休）。
    /// 週五特別型（skipSaturday = true）：**週五時差、週六休（本來就是假日）、
    ///   週日起大夜 6 晚（日〜五）**——只有點選日是週五時 UI 才提供這個選項。
    ///
    /// 背景：大夜班每天每個廠都要有一個人輪值，交接落在週日時新舊兩人會重疊一天，
    /// 這是覆蓋規則的正常現象，排班照樣各自套各自的序列。
    func applyNightShiftRotation(subordinateId: UUID, startDate: Date, skipSaturday: Bool = false) {
        guard let si = subordinates.firstIndex(where: { $0.id == subordinateId }) else { return }
        let cal = Calendar.current
        // 以中午為錨點往後加天數，避開午夜 / 時區邊界造成的整天位移
        let start = cal.date(bySettingHour: 12, minute: 0, second: 0,
                             of: cal.startOfDay(for: startDate)) ?? startDate
        var plan: [(Int, ShiftType)] = [(0, .jetLagLeave)]
        if skipSaturday {
            plan.append((1, .restDay))                       // 週六：本來就休假
            for d in 2...7 { plan.append((d, .nightShift)) } // 週日〜週五：大夜 6 晚
        } else {
            for d in 1...6 { plan.append((d, .nightShift)) } // 隔天起：大夜 6 晚
            plan.append((7, .restDay))                       // 第 8 天：休
        }
        // 以 isLoading 批次保護整個迴圈：8 次 removeAll+append 否則每次都觸發 didSet → save()，
        // 產生多次不必要的背景序列化，且各次中間態（部分班別已寫、部分尚未）也會被持久化。
        isLoading = true
        defer { isLoading = false }
        for (offset, type) in plan {
            guard let noon = cal.date(byAdding: .day, value: offset, to: start) else { continue }
            let day = cal.startOfDay(for: noon)
            subordinates[si].shifts.removeAll { cal.isDate($0.date, inSameDayAs: day) }
            subordinates[si].shifts.append(SubordinateShift(date: day, type: type))
        }
        save()
    }

    /// 套用小夜班：一律對齊 startDate 所在「整週的週一至週五」共 5 天，
    /// 不論點到該週哪一天，都填同一週的一~五（不覆蓋週末）。
    func applyEveningShiftWeekdays(subordinateId: UUID, startDate: Date) {
        guard let si = subordinates.firstIndex(where: { $0.id == subordinateId }) else { return }
        let cal = Calendar.current
        // 以中午為錨點，避開午夜 / 時區邊界造成的整天位移
        let anchor = cal.date(bySettingHour: 12, minute: 0, second: 0,
                              of: cal.startOfDay(for: startDate)) ?? startDate
        // 找到該週的週一：weekday 1=日…7=六，距離週一的天數 = (wd + 5) % 7
        let wd = cal.component(.weekday, from: anchor)
        let offsetToMonday = (wd + 5) % 7
        guard let monday = cal.date(byAdding: .day, value: -offsetToMonday, to: anchor) else { return }
        // 批次保護：避免迴圈中每次 append 都觸發 didSet → save()
        isLoading = true
        defer { isLoading = false }
        for i in 0..<5 {
            guard let noon = cal.date(byAdding: .day, value: i, to: monday) else { continue }
            let d = cal.startOfDay(for: noon)
            subordinates[si].shifts.removeAll { cal.isDate($0.date, inSameDayAs: d) }
            subordinates[si].shifts.append(SubordinateShift(date: d, type: .eveningShift))
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
        // ⚠️ 這裡只看「本職異動」——入職／升職／調薪／轉職／降職／離職。
        //
        // 原本的寫法是「排除離職」的黑名單，而且第一道判斷是
        // `careers.first?.careerSubCategory == .resign`。兼任職務也是 .career 類別，
        // 所以只要新增一筆日期比離職還新的兼任里程碑，那道短路就失效，
        // 迴圈接著往下找到更舊的入職紀錄、把前東家的名稱復活。
        // 名片頁與公司組織都靠這個屬性抓公司名，錯了會連鎖出錯。
        //
        // 改成白名單，日後再新增任何「非本職」子分類也不會重蹈覆轍。
        let employmentSubs: Set<CareerSubCategory> = [.join, .promote, .salaryAdjust,
                                                      .transfer, .demote, .resign]
        let careers = milestones
            .filter { m in
                guard m.category == .career, let sub = m.careerSubCategory else { return false }
                return employmentSubs.contains(sub)
            }
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

    /// 我目前的管理單位：最近一筆「入職／升職／調轉／降職」里程碑為管理職時，
    /// 取其管理單位名稱；不是管理職、已離職或沒填單位則 nil。
    /// 公司組織的部門詳細頁以名稱比對，把「我」列進該部門的管理人員名單。
    var myCurrentManagedUnit: String? {
        let positionSubs: Set<CareerSubCategory> = [.join, .promote, .transfer, .demote]
        let employmentSubs: Set<CareerSubCategory> = [.join, .promote, .salaryAdjust,
                                                      .transfer, .demote, .resign]
        let careers = milestones
            .filter { m in
                guard m.category == .career, let sub = m.careerSubCategory else { return false }
                return employmentSubs.contains(sub)
            }
            .sorted { $0.date > $1.date }
        // 最近事件為離職 → 目前無業，沒有管理單位
        if careers.first?.careerSubCategory == .resign { return nil }
        // 最近一筆「職位異動」決定目前是否管理職（調薪不影響職位）
        guard let latest = careers.first(where: { positionSubs.contains($0.careerSubCategory ?? .join) }),
              latest.isManagerial == true else { return nil }
        let unit = (latest.managedUnit ?? "").trimmingCharacters(in: .whitespaces)
        return unit.isEmpty ? nil : unit
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
    func deleteDepartment(_ item: Department) {
        isLoading = true
        defer { isLoading = false }
        departments.removeAll { $0.id == item.id }
        // 機台留在池中（歷史跟著機台），只解除部門歸屬避免懸空 id
        for i in equipmentPool.indices where equipmentPool[i].departmentId == item.id {
            equipmentPool[i].departmentId = nil
        }
        save()
    }

    // MARK: - 機台池（部門所屬設備）CRUD

    func upsertEquipment(_ eq: ManagedEquipment) {
        isLoading = true
        defer { isLoading = false }
        if let i = equipmentPool.firstIndex(where: { $0.id == eq.id }) { equipmentPool[i] = eq }
        else { equipmentPool.append(eq) }
        save()
    }

    func deleteEquipment(id: UUID) {
        equipmentPool.removeAll { $0.id == id }
    }

    /// 指派／解除機台負責人（ownerId 為 nil 即解除）。只動負責人欄位，PM／警報記錄不動。
    func assignEquipmentOwner(equipmentId: UUID, ownerId: UUID?) {
        guard let i = equipmentPool.firstIndex(where: { $0.id == equipmentId }) else { return }
        equipmentPool[i].ownerId = ownerId
    }

    /// 機台警報自動掛任務：設備儲存時對「這次新增的警報」呼叫。
    /// 機台要有負責人才建立；同一筆警報全 App 只掛一次（跨部屬掃描防重複——
    /// 例如换過負責人後再開舊警報存檔，不會再掛給新人一次）。
    /// 任務預設截止時間＝警報發生後 3 天，內容帶警報內容，可再編輯；
    /// 關閉任務（打勾完成）與一般任務完全相同。
    /// @MainActor：尾端呼叫的 syncReminderForSubordinateTask 是 main actor 隔離；
    /// 呼叫端（EquipmentEditorSheet.save）本來就在主執行緒。
    @MainActor
    func createTasksForNewAlarms(equipment: ManagedEquipment, newAlarms: [EquipmentAlarm]) {
        guard let ownerId = equipment.ownerId, !newAlarms.isEmpty,
              let si = subordinates.firstIndex(where: { $0.id == ownerId }) else { return }
        let linkedAlarmIds = Set(subordinates.flatMap(\.tasks).compactMap { $0.equipmentLink?.alarmId })
        var createdIds: [UUID] = []
        isLoading = true
        let name = equipment.name.isEmpty ? "未命名設備" : equipment.name
        for al in newAlarms where !linkedAlarmIds.contains(al.id) {
            let task = SubordinateTask(
                topic: "機台警報處理：\(name)",
                content: al.content.isEmpty ? "警報（未填內容）" : al.content,
                date: al.date,
                dueDate: Calendar.current.date(byAdding: .day, value: 3, to: al.date),
                equipmentLink: EquipmentAlarmLink(equipmentId: equipment.id, alarmId: al.id,
                                                  equipmentName: name, system: equipment.system)
            )
            subordinates[si].tasks.append(task)
            createdIds.append(task.id)
        }
        isLoading = false
        guard !createdIds.isEmpty else { return }
        save()
        // Apple 提醒事項同步（開啟時才動作），與手動新增任務一致
        for tid in createdIds { syncReminderForSubordinateTask(subordinateId: ownerId, taskId: tid) }
    }

    /// 一次性搬遷：把舊版存在各部屬身上的執掌設備搬進共用機台池。
    /// 機台的生老病死（PM／警報）跟著機台不跟著人；搬遷後部屬只以 ownerId 連結機台。
    /// 冪等：部屬身上清空後不再觸發。呼叫端需自行處理 isLoading 批次與 save()。
    @discardableResult
    func migrateLegacyEquipmentsToPool() -> Bool {
        var changed = false
        for si in subordinates.indices where !subordinates[si].equipments.isEmpty {
            for eq in subordinates[si].equipments {
                if let pi = equipmentPool.firstIndex(where: { $0.id == eq.id }) {
                    // 已在池中（例如另一台裝置已搬遷過）：只補負責人／部門，不覆蓋既有記錄
                    if equipmentPool[pi].ownerId == nil { equipmentPool[pi].ownerId = subordinates[si].id }
                    if equipmentPool[pi].departmentId == nil { equipmentPool[pi].departmentId = subordinates[si].departmentId }
                } else {
                    var moved = eq
                    moved.ownerId = subordinates[si].id
                    if moved.departmentId == nil { moved.departmentId = subordinates[si].departmentId }
                    equipmentPool.append(moved)
                }
            }
            subordinates[si].equipments = []
            changed = true
        }
        return changed
    }

    // MARK: - 檢視卡片就地編輯寫回（InlineEditBlock）
    // 只改單一文字欄位（備註/內容/處理措施/回復結果…）不必經過完整編輯頁的重建流程，
    // 也就不會碰到「重建漏帶欄位」那一類風險；閉包就地修改，isLoading 批次後存檔一次。

    func mutateSubordinateTaskFields(subordinateId: UUID, taskId: UUID,
                                     _ mutate: (inout SubordinateTask) -> Void) {
        guard let si = subordinates.firstIndex(where: { $0.id == subordinateId }),
              let ti = subordinates[si].tasks.firstIndex(where: { $0.id == taskId }) else { return }
        isLoading = true
        defer { isLoading = false }
        mutate(&subordinates[si].tasks[ti])
        save()
    }

    func mutateSubordinateMeetingFields(subordinateId: UUID, meetingId: UUID,
                                        _ mutate: (inout SubordinateMeeting) -> Void) {
        guard let si = subordinates.firstIndex(where: { $0.id == subordinateId }),
              let mi = subordinates[si].meetings.firstIndex(where: { $0.id == meetingId }) else { return }
        isLoading = true
        defer { isLoading = false }
        mutate(&subordinates[si].meetings[mi])
        save()
    }

    func mutateWeeklyReportFields(subordinateId: UUID, reportId: UUID,
                                  _ mutate: (inout WeeklyReport) -> Void) {
        guard let si = subordinates.firstIndex(where: { $0.id == subordinateId }),
              let ri = subordinates[si].weeklyReports.firstIndex(where: { $0.id == reportId }) else { return }
        isLoading = true
        defer { isLoading = false }
        mutate(&subordinates[si].weeklyReports[ri])
        save()
    }

    func mutateSubordinateRecordFields(subordinateId: UUID, recordId: UUID,
                                       _ mutate: (inout SubordinateRecord) -> Void) {
        guard let si = subordinates.firstIndex(where: { $0.id == subordinateId }),
              let ri = subordinates[si].records.firstIndex(where: { $0.id == recordId }) else { return }
        isLoading = true
        defer { isLoading = false }
        mutate(&subordinates[si].records[ri])
        save()
    }

    /// 機台備註就地編輯（機台詳情卡片）
    func mutateEquipmentFields(equipmentId: UUID, _ mutate: (inout ManagedEquipment) -> Void) {
        guard let i = equipmentPool.firstIndex(where: { $0.id == equipmentId }) else { return }
        isLoading = true
        defer { isLoading = false }
        mutate(&equipmentPool[i])
        save()
    }

    // MARK: - 職等對應職稱 CRUD

    func add(_ item: GradeTitle) { gradeTitles.append(item) }
    func update(_ item: GradeTitle) {
        if let i = gradeTitles.firstIndex(where: { $0.id == item.id }) { gradeTitles[i] = item }
    }

    // MARK: - 公司組織人員 CRUD

    func add(_ item: OrgPerson) { orgPeople.append(item) }
    func update(_ item: OrgPerson) {
        if let i = orgPeople.firstIndex(where: { $0.id == item.id }) { orgPeople[i] = item }
        // [v25.297] 部門反向同步：組織人員改了部門，連動的部屬也要跟著搬。
        // 原本只有部屬→組織人員的單向同步，從公司組織頁調部門時部屬端
        // 停在舊部門，設備編輯器等依部屬 departmentId 篩選的地方就對不上。
        if let sid = item.linkedSubordinateId,
           let si = subordinates.firstIndex(where: { $0.id == sid }),
           subordinates[si].departmentId != item.departmentId {
            subordinates[si].departmentId = item.departmentId
            subordinates[si].department = item.departmentId.flatMap { did in
                departments.first { $0.id == did }?.name
            } ?? ""
        }
    }
    func deleteOrgPerson(_ item: OrgPerson) {
        if let name = item.photoFileName { OrgPerson.deletePhoto(name) }
        isLoading = true
        defer { isLoading = false }
        // 生日提醒的行事曆事件一併刪除（比照 deleteSubordinate；bridge 是 main actor 隔離）
        if let bid = item.birthdayEventId {
            Task { @MainActor in AppleCalendarBridge.shared.delete(eventIdentifier: bid) }
        }
        // 解除名片反向連結
        if let cid = item.linkedBusinessCardId,
           let i = businessCards.firstIndex(where: { $0.id == cid }),
           businessCards[i].linkedOrgPersonId == item.id {
            businessCards[i].linkedOrgPersonId = nil
        }
        for i in orgPeople.indices {
            orgPeople[i].relations.removeAll { $0.personId == item.id }
        }
        // 從各部門的管理人員名單移除，避免懸空 id（部門列會顯示不出名字）
        for i in departments.indices where departments[i].managerIds.contains(item.id) {
            departments[i].managerIds.removeAll { $0 == item.id }
        }
        orgPeople.removeAll { $0.id == item.id }
        save()
    }

    func add(_ item: BusinessCard) { businessCards.append(item) }
    func update(_ item: BusinessCard) {
        if let i = businessCards.firstIndex(where: { $0.id == item.id }) { businessCards[i] = item }
    }
    func deleteBusinessCard(_ item: BusinessCard) {
        if let name = item.photoFileName { BusinessCard.deletePhoto(name) }
        isLoading = true
        defer { isLoading = false }
        // 解除組織人員反向連結
        if let pid = item.linkedOrgPersonId,
           let i = orgPeople.firstIndex(where: { $0.id == pid }),
           orgPeople[i].linkedBusinessCardId == item.id {
            orgPeople[i].linkedBusinessCardId = nil
        }
        businessCards.removeAll { $0.id == item.id }
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

    // MARK: - 批次修改

    /// 供外部（View 層）在一次操作中對多筆、甚至跨集合（departments/orgPeople/subordinates…）
    /// 呼叫多次 update() 時使用：暫停期間每筆 didSet 都不觸發 save()，body 結束後只統一存檔一次。
    /// 用法與本檔案內部既有的 `isLoading = true; defer { isLoading = false }; ...; save()` 手法一致，
    /// 只是包成公開函式給 View 端的迴圈（例如刪除部門時連動清除其他部門/人員的關聯）使用，
    /// 避免迴圈跑 N 次就各自觸發 N 次「全量 12 個集合重編碼 + CloudKit 推送節流 + 畫面重繪」。
    func withBatch(_ body: () -> Void) {
        isLoading = true
        defer { isLoading = false }
        body()
        save()
    }

    // MARK: - 持久化

    private func save() {
        // 捕捉 struct 快照（值型別複製，安全傳入背景執行緒），避免主執行緒同步序列化 12 份資料
        let snap = (
            profile: profile, familyMembers: familyMembers, milestones: milestones,
            relationships: relationships, pets: pets, schedules: schedules,
            subordinates: subordinates, departments: departments, gradeTitles: gradeTitles,
            businessCards: businessCards, personalEvents: personalEvents, orgPeople: orgPeople,
            healthProfile: healthProfile, familyTasks: familyTasks, equipmentPool: equipmentPool
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
            if let d = try? encoder.encode(snap.healthProfile)  { ud.set(d, forKey: "life_health_profile") }
            if let d = try? encoder.encode(snap.familyTasks)    { ud.set(d, forKey: "life_family_tasks") }
            if let d = try? encoder.encode(snap.equipmentPool)  { ud.set(d, forKey: "life_equipment_pool") }
            CloudSyncManager.shared.pushAll()
        }
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        let decoder = JSONDecoder()

        if let data = rawDataIfChanged("life_profile"),
           let p = try? decoder.decode(UserProfile.self, from: data) {
            profile = p
        }
        // 各集合改用「逐筆容錯」解碼：單一筆損壞不會讓整批消失（避免家庭/部屬等資料整批不見）
        if let items = lossyDecodeArray([FamilyMember].self, key: "life_family", decoder: decoder) { familyMembers = items }
        if let items = lossyDecodeArray([LifeMilestone].self, key: "life_milestones", decoder: decoder) { milestones = items }
        if let items = lossyDecodeArray([Relationship].self, key: "life_relationships", decoder: decoder) { relationships = items }
        if let items = lossyDecodeArray([Pet].self, key: "life_pets", decoder: decoder) { pets = items }
        if let items = lossyDecodeArray([Schedule].self, key: "life_schedules", decoder: decoder) { schedules = items }
        if let items = lossyDecodeArray([Subordinate].self, key: "life_subordinates", decoder: decoder) { subordinates = items }
        if let items = lossyDecodeArray([Department].self, key: "life_departments", decoder: decoder) { departments = items }
        if let items = lossyDecodeArray([GradeTitle].self, key: "life_grade_titles", decoder: decoder) { gradeTitles = items }
        if let items = lossyDecodeArray([BusinessCard].self, key: "life_business_cards", decoder: decoder) { businessCards = items }
        if let items = lossyDecodeArray([PersonalEvent].self, key: "life_personal_events", decoder: decoder) { personalEvents = items }
        if let items = lossyDecodeArray([OrgPerson].self, key: "life_org_people", decoder: decoder) { orgPeople = items }
        if let items = lossyDecodeArray([FamilyTask].self, key: "life_family_tasks", decoder: decoder) { familyTasks = items }
        if let items = lossyDecodeArray([ManagedEquipment].self, key: "life_equipment_pool", decoder: decoder) { equipmentPool = items }
        if let data = rawDataIfChanged("life_health_profile"),
           let h = try? decoder.decode(HealthProfile.self, from: data) {
            healthProfile = h
        }
    }

    /// 讀取 key 目前在 UserDefaults 的原始 Data；若與上次成功套用的內容完全相同則回傳 nil，
    /// 讓呼叫端略過解碼／賦值，避免同一批資料重複觸發 @Published 造成無謂重繪。
    private func rawDataIfChanged(_ key: String) -> Data? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        if lastLoadedRawData[key] == data { return nil }
        lastLoadedRawData[key] = data
        return data
    }

    /// 逐筆容錯解碼：先試整批，失敗再逐筆解、跳過損壞的元素，保留其餘資料。
    /// key 不存在、或與上次套用的內容相同 → 回傳 nil（不覆蓋現有值）；存在且有變更但全空 → 回傳 []。
    private func lossyDecodeArray<Element: Decodable>(
        _ type: [Element].Type, key: String, decoder: JSONDecoder
    ) -> [Element]? {
        guard let data = rawDataIfChanged(key) else { return nil }
        if let items = try? decoder.decode([Element].self, from: data) { return items }
        // 整批失敗 → 逐筆解碼保留可解的元素
        if let raw = try? decoder.decode([FailableDecodable<Element>].self, from: data) {
            return raw.compactMap { $0.value }
        }
        return nil
    }

    /// 包裝單一元素，解碼失敗時不丟錯、回傳 nil
    private struct FailableDecodable<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws {
            value = try? T(from: decoder)
        }
    }

    // MARK: - 清除

    /// 對齊 clearAll() 涵蓋範圍的「本 Store 是否完全沒有資料」判斷，供 SettingsView 危險操作區
    /// 的「清除所有資料」按鈕啟用/停用依據；沿用同一份欄位清單，避免兩處各自列舉而漏算新分類。
    var isEmpty: Bool {
        profile.isEmpty && familyMembers.isEmpty && milestones.isEmpty && relationships.isEmpty &&
        pets.isEmpty && schedules.isEmpty && subordinates.isEmpty &&
        departments.isEmpty && gradeTitles.isEmpty && businessCards.isEmpty &&
        personalEvents.isEmpty && orgPeople.isEmpty && healthProfile.isEmpty
    }

    func clearAll() {
        isLoading = true
        defer { isLoading = false }
        // 清空前先刪除所有內嵌照片檔案，否則「清除所有資料」後照片仍留在磁碟／iCloud，
        // 使用者會誤以為資料已完全清除（對齊 deleteFamilyMember／deleteOrgPerson／
        // deleteBusinessCard 刪除單筆時的既有清理寫法）。
        for member in familyMembers { Self.cleanupFamilyMemberFiles(member) }
        for card in businessCards {
            if let name = card.photoFileName { BusinessCard.deletePhoto(name) }
        }
        for person in orgPeople {
            if let name = person.photoFileName { OrgPerson.deletePhoto(name) }
        }
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
        healthProfile = HealthProfile()
        save()
    }
}
