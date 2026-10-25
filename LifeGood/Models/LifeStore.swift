import Foundation

class LifeStore: ObservableObject {
    @Published var profile: UserProfile = UserProfile() { didSet { if !isLoading { save() } } }
    @Published var familyMembers: [FamilyMember] = [] { didSet { if !isLoading { save() } } }
    /// [v25.563] 一改 wealthRevision 加一：財富的一套數字（wealthFacts）靠它決定要不要重算
    @Published var milestones: [LifeMilestone] = [] { didSet { wealthRevision &+= 1; if !isLoading { save() } } }
    @Published var relationships: [Relationship] = [] { didSet { if !isLoading { save() } } }
    @Published var pets: [Pet] = [] { didSet { if !isLoading { save() } } }
    @Published var schedules: [Schedule] = [] { didSet { if !isLoading { save() } } }
    @Published var subordinates: [Subordinate] = [] { didSet { if !isLoading { save() } } }
    @Published var departments: [Department] = [] { didSet { if !isLoading { save() } } }
    /// [v25.348] 績效互評票（年度同儕排名）
    @Published var performanceBallots: [PerformanceBallot] = [] { didSet { if !isLoading { save() } } }
    /// [v25.351] 健身紀錄：一筆＝一次訓練，底下掛多個動作
    /// [v25.553] 每次改（含 iCloud 拉下來、匯入）workoutsRevision 加一：健康頁的 .task(id:) 靠它決定要不要重算
    @Published var workouts: [WorkoutSession] = [] { didSet { workoutsRevision &+= 1; if !isLoading { save() } } }
    /// [v25.553] 健康頁的設定（看板主角、每週目標）；跟 iCloud 同步、進完整備份
    @Published var workoutPrefs: WorkoutPrefs = WorkoutPrefs() { didSet { workoutsRevision &+= 1; if !isLoading { save() } } }
    /// [v25.554] LifeGood 對 Apple 健康的帳（不再帶進來的編號、兩筆都留、舊紀錄先不要接回）；跟 iCloud 同步、進完整備份。
    /// 一改 workoutsRevision 也加一（健康頁「要確認」跟著重算）
    @Published var workoutHealthLedger: WorkoutHealthLedger = WorkoutHealthLedger() { didSet { workoutsRevision &+= 1; if !isLoading { save() } } }
    /// [v25.557] 請假週（出差、生病的那一週不讓連續週數斷掉）；跟 iCloud 同步、進完整備份。一改 workoutsRevision 也加一（看板、月曆重算）
    @Published var workoutLeave: WorkoutLeaveBook = WorkoutLeaveBook() { didSet { workoutsRevision &+= 1; if !isLoading { save() } } }
    /// [v25.563] 財富帳本（WealthBook.swift；鍵 life_wealth_book_v1，跟 iCloud 同步、進完整備份與「理財」匯出）：
    /// 扣款帳戶的歷史、說明過的事…（v3 起暱稱、排序、收起來、標成已繳）。單獨一個鍵：還沒更新的 iPad 不會把它蓋掉。
    /// 一改 wealthRevision 也加一
    @Published var wealthBook: WealthBook = WealthBook() { didSet { wealthRevision &+= 1; if !isLoading { save() } } }
    /// [v25.566] 財富帳本・定存那一包（WealthBook.swift WealthDepositBook；鍵 life_wealth_deposits_v1，跟 iCloud 同步、
    /// 進完整備份與「理財」匯出）。不放進 wealthBook：v25.563–565 的 iPad 存一次帳本會把它不認得的欄位洗掉，另一個鍵它不碰。
    /// 一改 wealthRevision 也加一
    @Published var wealthDeposits: WealthDepositBook = WealthDepositBook() { didSet { wealthRevision &+= 1; if !isLoading { save() } } }
    /// [v25.568] 號碼密文那一包（WealthVault.swift WealthVaultBook；鍵 life_wealth_vault_v1，跟 iCloud 同步、進完整備份與
    /// 「記帳理財」匯出——裡面只有密文）：有效期限、保單號碼、票證號。不放進 wealthBook：25.564–25.567 的 iPad 存一次帳本會把
    /// 不認得的欄位洗掉，另一個鍵它不碰。一改 wealthRevision 也加一（有效期限的快取、財富的一套數字跟著重算）
    @Published var wealthVault: WealthVaultBook = WealthVaultBook() { didSet { wealthRevision &+= 1; if !isLoading { save() } } }
    /// [v25.575] 定期轉帳那一包（WealthTransfers.swift WealthTransferBook；鍵 life_wealth_transfers_v1，跟 iCloud 同步、進完整備份與
    /// 「記帳理財」匯出）。不放進 wealthBook、不加在 BankDeposit 上：還沒更新的 iPad 存一次會把不認得的欄位洗掉，另一個鍵它不碰。
    /// 一改 wealthRevision 也加一（一套數字的快取跟著重算：每一期算進兩個帳戶）
    @Published var wealthTransfers: WealthTransferBook = WealthTransferBook() { didSet { wealthRevision &+= 1; if !isLoading { save() } } }
    /// [v25.357] 公司廠區據點：與重大決議的「廠區」欄位對應，長成每個廠的歷史年線
    @Published var companySites: [CompanySite] = [] { didSet { if !isLoading { save() } } }
    /// [v25.399] 旅遊規劃（要去的行程；與旅遊地圖「去過的地點」是兩回事）
    @Published var tripPlans: [TripPlan] = [] { didSet { if !isLoading { save() } } }
    @Published var gradeTitles: [GradeTitle] = [] { didSet { if !isLoading { save() } } }
    @Published var businessCards: [BusinessCard] = [] { didSet { if !isLoading { save() } } }
    @Published var personalEvents: [PersonalEvent] = [] { didSet { if !isLoading { save() } } }
    @Published var orgPeople: [OrgPerson] = [] { didSet { if !isLoading { save() } } }
    /// [v25.553] 體重變了，估的大卡跟著變：健康頁也要重算（workoutsRevision）
    @Published var healthProfile: HealthProfile = HealthProfile() { didSet { workoutsRevision &+= 1; if !isLoading { save() } } }
    @Published var familyTasks: [FamilyTask] = [] { didSet { if !isLoading { save() } } }
    /// 機台池：全公司的設備（機台）共用清單。機台屬於部門（departmentId）、
    /// 由部屬擔任負責人（ownerId）；PM／警報等生老病死記錄跟著機台，換負責人不搬記錄。
    @Published var equipmentPool: [ManagedEquipment] = [] { didSet { if !isLoading { save() } } }

    /// [v25.553] 只放記憶體的遞增數字：workouts、workoutPrefs、healthProfile 一改就加一（不存檔、不發通知；
    /// 那三個本身是 @Published，畫面會重畫，重畫時讀到新的數字，.task(id:) 才重算一次）
    private(set) var workoutsRevision = 0

    /// [v25.563] 只放記憶體的遞增數字：milestones、wealthBook 一改就加一（財富的一套數字的快取 key 之一）
    private(set) var wealthRevision = 0
    /// [v25.563] 財富的一套數字的快取（wealthFacts(expense:finance:)；key 對得上就不重算，打字時不重算）
    private var wealthFactsCache: (key: String, facts: WealthFacts)?

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
        "life_equipment_pool", "life_performance_ballots", "life_workouts",
        "life_company_sites", "life_trip_plans", "life_workout_prefs", "life_workout_health",
        "life_workout_leave", "life_wealth_book_v1", "life_wealth_deposits_v1",
        // [v25.568] 號碼密文那一包（life_wealth_facts_v1 不在這裡：App 只寫給網頁版、自己不讀）
        "life_wealth_vault_v1",
        // [v25.575] 定期轉帳那一包（WealthTransferBook.syncKey）
        "life_wealth_transfers_v1"
    ]

    init() {
        // [v25.568] CardVault 問「整份資料裡有沒有任何號碼密文」問這裡（有密文、這台沒金鑰時不准產生新金鑰：CardVault 規矩 2）。
        // 所有屬性都有預設值，這裡已經可以用 self；weak：store 不在了就當「有」（寧可擋下）
        CardVault.cipherProbe = { [weak self] in self?.hasAnyWealthCipher ?? true }
        load()
        // 用 defer 重置，避免日後在中間加入 guard/return 導致 isLoading 卡死為 true（save() 永久停擺）
        isLoading = true
        defer { isLoading = false }
        let didBackfill = backfillOrgPeopleFromSubordinates()
        let didRepair = repairSideRoleMemberLinks()
        let didMigrateEq = migrateLegacyEquipmentsToPool()
        let didSerial = migrateResolutionSerials()
        // [v25.568] 舊的明碼號碼搬成密文（新版第一次打開；這台封不了的整筆不動，下次再搬）
        // [v25.568 裁定] 這裡還沒跟 iCloud 拉過：這台沒有金鑰就先不搬（allowNewKey: false＝不准在這裡產生新金鑰）。
        // 不然兩台都沒存過號碼、iCloud 鑰匙圈還沒同步時，各自用本機的舊資料產生一把，後寫的蓋掉先寫的，先搬那台的號碼就解不開了。
        // 等 iCloud 拉完（reloadFromCloud）、打開財富頁、匯入備份時再搬；這台已經有金鑰（大多數人）照樣在這裡搬
        let didVault = migrateWealthSecrets(allowNewKey: false) > 0
        if didBackfill || didRepair || didMigrateEq || didSerial || didVault { save() }
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
        // [v25.454] 旅遊規劃的跨裝置通知：拉取前的樣子要在 load() 之前先留下來，
        // 不然就只剩「拉完之後」，沒有東西可以比。
        //
        // 只有帶了 keys 且其中包含 life_trip_plans 的增量拉取才報。沒帶 keys 的
        // 全量重載是「以雲端覆蓋這台」那種操作，整份行程都會算成新的——那不是
        // 「別人剛新增了什麼」。
        let tripKeyTouched = (note.userInfo?["keys"] as? [String])?.contains("life_trip_plans") ?? false
        let tripsBefore = tripKeyTouched ? tripPlans : []
        // [v25.575] 定期轉帳：你和太太各加各的（transfer/judge.md §2.3 #9）。增量拉取帶了這個鍵＝別台改過，load() 會整包換成雲端那份；
        // 先留下本機的，load() 之後照 id＋updatedAt 合併（墓碑勝過比它舊的）——不然後同步的那台會把另一台剛加的那條洗掉。
        // 沒帶 keys 的全量重載（以雲端覆蓋這台、第一次合併）照雲端那包，不併
        let transfersKeyTouched = (note.userInfo?["keys"] as? [String])?.contains(WealthTransferBook.syncKey) ?? false
        let transfersBefore = wealthTransfers
        load()
        // backfill 期間暫停 save()，避免剛從雲端拉取就立刻回寫；用 defer 重置，
        // 避免日後在中間加入 guard/return 導致 isLoading 卡死為 true（save() 永久停擺）
        isLoading = true
        defer { isLoading = false }
        let didBackfill = backfillOrgPeopleFromSubordinates()
        let didRepair = repairSideRoleMemberLinks()
        // 雲端另一台裝置若仍是舊版（機台存在部屬身上），拉下來後在這裡搬進機台池
        let didMigrateEq = migrateLegacyEquipmentsToPool()
        let didSerial = migrateResolutionSerials()
        // [v25.568] 還沒更新的 iPad 又寫回明碼（舊版表單打了完整號碼）、或這台的金鑰剛同步過來：拉下來就搬成密文
        let didVault = migrateWealthSecrets() > 0
        // [v25.575] 定期轉帳：雲端那份（剛 load 進來的）併上本機剛才那份；合出來跟雲端那份不一樣（本機有它沒有的）就存回去、推上去
        var didTransfers = false
        if transfersKeyTouched {
            let merged = wealthTransfers.merged(with: transfersBefore)
            if merged != wealthTransfers {
                wealthTransfers = merged
                didTransfers = true
            }
        }
        // 若 backfill 新建了 OrgPerson/BusinessCard 或修復了成員連結，立即持久化避免重啟後消失
        if didBackfill || didRepair || didMigrateEq || didSerial || didVault || didTransfers { save() }
        // [v25.454] 比對拉取前後的旅遊規劃，把別台裝置新增的行程／景點／攜帶物品／
        // 伴手禮寫成本機通知。
        if tripKeyTouched {
            TripChangeNotifier.report(before: tripsBefore, after: tripPlans)
        }
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
    func deleteMilestone(_ item: LifeMilestone) {
        // [v25.559] 信用卡說明照片跟著刪（照片檔不在 JSON 裡，不刪會留在手機和 iCloud）
        let photos = milestones.first(where: { $0.id == item.id })?.photoFileNames ?? item.photoFileNames ?? []
        milestones.removeAll { $0.id == item.id }
        for name in photos { LifeMilestone.deletePhoto(name) }
    }

    // MARK: - [v25.563] 財富的一套數字（WealthFacts.swift）

    /// 全 App 跟「錢在哪個帳戶」有關的數字都拿這一份：財富頁、卡片頁、記帳／收入／股票／房屋水電的扣款選單、轉帳、對存摺。
    /// 快取 key＝里程碑／財富帳本的 revision＋記帳、理財的 modifyID＋匯率＋日期：資料沒變就不重算（打字時不重算，U1 P1、P5）。
    /// 在主執行緒叫（畫面的 body、.task、按鈕）。
    func wealthFacts(expense: ExpenseStore, finance: FinanceStore, now: Date = Date()) -> WealthFacts {
        let key = WealthFacts.cacheKey(revision: wealthRevision, expense: expense, finance: finance, now: now)
        if let c = wealthFactsCache, c.key == key { return c.facts }
        // [v25.567] 保單總表要儲蓄險、車子、房子（四個來源去重）；cacheKey 已經含理財的 modifyID
        // [v25.568] 有效期限 v7 起是密文：每張卡那個月 1 號由 cardExpiryMonths 解好給（行事曆、要確認 #12、通知照舊）
        let f = WealthFacts.build(milestones: milestones, book: wealthBook, deposits: wealthDeposits,
                                  transfers: wealthTransfers,
                                  expenses: expense.expenses, incomes: expense.incomes, stocks: finance.stocks,
                                  rates: FinanceRates(expense), now: now, insurances: finance.insurances,
                                  vehicles: finance.vehicles, realEstates: finance.realEstates,
                                  expiryMonths: cardExpiryMonths())
        wealthFactsCache = (key: key, facts: f)
        return f
    }

    // MARK: - [v25.568] 財富 v7：號碼加密（WealthVault.swift；CardVault 規矩）

    /// 整份資料裡有沒有任何號碼密文（卡號、安全碼、完整帳號、有效期限、保單號碼、票證號）。
    /// CardVault.cipherProbe 問這個：有密文、這台沒有金鑰＝還沒同步過來，不准產生新金鑰
    var hasAnyWealthCipher: Bool {
        if wealthVault.hasAnyCipher { return true }
        if (wealthBook.accounts ?? [:]).values.contains(where: { (p: WealthAccountPrefs) -> Bool in p.accountNumberCipher != nil }) {
            return true
        }
        return milestones.contains { (m: LifeMilestone) -> Bool in m.cardNumberCipher != nil || m.cardSecurityCipher != nil }
    }

    /// 有效期限的快取（wealthRevision 對得上就不重解；只在記憶體）
    private var expiryMonthsCache: (revision: Int, hasKey: Bool, months: [UUID: Date])?

    /// 每張卡有效期限那個月 1 號（行事曆「卡片到期」、要確認 #12、通知用；judge §7.1 行事曆「只有卡片到期那天」）：
    /// 還沒搬的明碼照用；密文那一包的，這台有金鑰才解（CardVault.open 從不產生金鑰）、只取年月、只放記憶體。
    /// 這台還沒同步到金鑰：密文的那幾張先沒有（行事曆、提醒少那幾張，金鑰同步過來就回來）。
    /// 網頁版那一包、匯出、CSV、小工具的快照都不叫這支拿有效期限本身（CardVault 規矩 4）
    func cardExpiryMonths() -> [UUID: Date] {
        let canOpen = CardVault.hasKey
        if let c = expiryMonthsCache, c.revision == wealthRevision, c.hasKey == canOpen { return c.months }
        var out: [UUID: Date] = [:]
        for m in milestones where m.financeSubCategory == .creditCard {
            if let raw = m.expiryDate {
                out[m.id] = WealthCal.startOfMonth(raw)
                continue
            }
            guard canOpen, let cipher = wealthVault.entry(m.id).expiryCipher,
                  let text = CardVault.open(cipher), let d = WealthSecrets.expiryDate(text) else { continue }
            out[m.id] = d
        }
        expiryMonthsCache = (revision: wealthRevision, hasKey: canOpen, months: out)
        return out
    }

    /// 舊的明碼號碼搬成密文（judge §8 v7）：完整帳號 → 帳本 accounts[id].accountNumberCipher（里程碑只留後 4 碼）；
    /// 有效期限、保單號碼、票證號 → 密文那一包（保單號碼、票證號只留後 4 碼，有效期限清掉）。
    /// 一筆裡有一個封不了（這台還沒同步到金鑰、鑰匙圈寫不進去）整筆不動，照舊留明碼，下次再搬。沒有要搬的什麼都不做。
    /// 讀檔、從 iCloud 拉到新資料（init、reloadFromCloud）、打開財富頁、匯入備份之後叫；在主執行緒。
    /// milestones、wealthBook、wealthVault 各最多指派一次。回傳搬了幾筆
    /// [v25.568 裁定] allowNewKey: false（init，還沒跟 iCloud 拉過）＝這台沒有金鑰就先不搬，絕不在這裡產生新金鑰
    @discardableResult
    func migrateWealthSecrets(allowNewKey: Bool = true) -> Int {
        // [v25.568 裁定] 金鑰剛從 iCloud 鑰匙圈同步過來（上次解有效期限時這台還沒有）：當作財富資料改了一次（wealthRevision 加一），
        // 財富的一套數字、財富頁／卡片頁的快取、小工具快照跟著重算，畫面重畫一次——行事曆「卡片到期」、要確認 #12、
        // 效期通知那幾張卡就回來（不用等資料改動或重開 App）。資料本身沒動、不存檔
        if let c = expiryMonthsCache, !c.hasKey, CardVault.hasKey {
            wealthRevision &+= 1
            objectWillChange.send()
        }
        guard milestones.contains(where: { (m: LifeMilestone) -> Bool in WealthSecrets.needsMigration(m) }) else { return 0 }
        if !allowNewKey && !CardVault.hasKey { return 0 }
        var list = milestones
        var book = wealthBook
        var vault = wealthVault
        var moved = 0
        for i in list.indices {
            let m = list[i]
            guard WealthSecrets.needsMigration(m) else { continue }
            guard let r = WealthSecrets.migrate(m, prefs: book.account(m.id), entry: vault.entry(m.id),
                                                seal: { (text: String) -> Data? in CardVault.seal(text) }) else { continue }
            list[i] = r.milestone
            book.setAccount(r.prefs, for: m.id)
            vault.setEntry(r.entry, for: m.id)
            moved += 1
        }
        guard moved > 0 else { return 0 }
        // 先寫密文、再清明碼（萬一中間被打斷，最多是明碼還在、密文也有，下次再搬一次；不會兩邊都沒有）
        if vault != wealthVault { wealthVault = vault }
        if book != wealthBook { wealthBook = book }
        milestones = list
        return moved
    }

    /// 改號碼密文那一包（改完跟原本一樣就不寫）
    func updateWealthVault(_ body: (inout WealthVaultBook) -> Void) {
        var v = wealthVault
        body(&v)
        if v != wealthVault { wealthVault = v }
    }

    /// 「號碼改成加密存了」說明一次（財富頁打開時；judge §8 v7【待確認】還沒更新的 iPad 只看得到後 4 碼）。
    /// 說明過（WealthBook.vaultNoticeKey，跟 iCloud 同步，換一台不會再說）或一筆加密的帳號、有效期限、保單號碼、票證號都沒有＝nil
    var wealthVaultNotice: (title: String, message: String)? {
        guard !wealthBook.hasNotice(WealthBook.vaultNoticeKey) else { return nil }
        let accountCipher = (wealthBook.accounts ?? [:]).values.contains(where: { (p: WealthAccountPrefs) -> Bool in
            p.accountNumberCipher != nil
        })
        guard accountCipher || wealthVault.hasAnyCipher else { return nil }
        return (title: WealthSecrets.vaultNoticeTitle, message: WealthSecrets.vaultNoticeMessage)
    }

    /// [v25.563] 對存摺要的「App 算的數字」：這個帳戶這個幣別在 day 那天結束時（excluding：編輯以前那筆對存摺時不算它自己）。
    /// 重算一次（不走快取）：只在打開對存摺、換日期時叫，打字時不要叫
    func passbookBalance(accountId: UUID, code: String, endOf day: Date, excluding: UUID?,
                         expense: ExpenseStore, finance: FinanceStore) -> Double {
        WealthFacts.passbookBalance(accountId: accountId, code: code, endOf: day, excluding: excluding,
                                    milestones: milestones, book: wealthBook, deposits: wealthDeposits,
                                    transfers: wealthTransfers, expenses: expense.expenses, incomes: expense.incomes, stocks: finance.stocks,
                                    rates: FinanceRates(expense))
    }

    /// [v25.563] 改財富帳本（改完跟原本一樣就不寫，不白跑一次存檔與 iCloud）
    func updateWealthBook(_ body: (inout WealthBook) -> Void) {
        var b = wealthBook
        body(&b)
        if b != wealthBook { wealthBook = b }
    }

    /// [v25.563] 說明過一次了（「為什麼數字變了」：WealthBook.passbookNoticeKey）
    func markWealthNoticeSeen(_ key: String) {
        updateWealthBook { $0.addNotice(key) }
    }

    /// [v25.563] 信用卡改扣款帳戶（D10，履歷的卡片表單存檔時叫；卡的 linkedBankMilestoneId 由表單照舊寫成新帳戶）。
    /// fromKey：從哪一期起改（帳單 key「2026-11」，WealthCardCycle.nextStatement）；nil＝以前的帳單也改（整張卡一直是新帳戶）。
    /// 以前的帳單照舊從原本的帳戶扣：第一次改時補一段「最早 → 原本的帳戶」，再加「這一期起 → 新帳戶」
    func recordCardPayFromChange(cardId: UUID, oldAccount: UUID?, newAccount: UUID?, fromKey: String?) {
        updateWealthBook { book in
            var prefs = book.card(cardId)
            if let key = fromKey {
                var h = (prefs.payFrom ?? []).sorted { $0.fromKey < $1.fromKey }
                if h.isEmpty {
                    h.append(WealthPayFrom(fromKey: "", accountId: oldAccount))
                } else {
                    // 最新那一段原本是「跟著卡現在的帳戶」，現在要定下來＝原本的帳戶
                    h[h.count - 1].accountId = oldAccount
                }
                h.removeAll { !$0.fromKey.isEmpty && $0.fromKey >= key }
                h.append(WealthPayFrom(fromKey: key, accountId: newAccount))
                prefs.payFrom = h
            } else {
                prefs.payFrom = nil
            }
            book.setCard(prefs, for: cardId)
        }
    }

    /// [v25.563] 轉帳：兩邊各寫一筆、同一個 transferPairId（刪一邊時問要不要兩筆一起刪）；
    /// 兩邊幣別不同時記 fxRate（1 外幣＝幾台幣）。toAmount 由呼叫端用 WealthFacts.transferAmount 算好。milestones 只指派一次
    /// [v25.566] 換匯：同一個帳戶、兩個幣別互轉也走這支（fromId＝toId、幣別不同；兩筆記在同一個帳戶）
    func addTransfer(from fromId: UUID, fromCode: String, amount: Double, to toId: UUID, toCode: String,
                     toAmount: Double, fxRate: Double?, date: Date, note: String?) {
        let sameAccount = fromId == toId
        guard !sameAccount || WealthFacts.norm(fromCode) != WealthFacts.norm(toCode),
              amount > 0, toAmount > 0 else { return }
        var list = milestones
        guard let fi = list.firstIndex(where: { $0.id == fromId }),
              let ti = list.firstIndex(where: { $0.id == toId }) else { return }
        let pair = UUID()
        let sameCode = WealthFacts.norm(fromCode) == WealthFacts.norm(toCode)
        let rate: Double? = sameCode ? nil : fxRate
        var outList = list[fi].bankDeposits ?? []
        outList.append(BankDeposit(date: date, amount: amount, currencyCode: fromCode, isWithdrawal: true,
                                   note: note, kind: BankDeposit.kindTransfer,
                                   transferPairId: pair, counterpartyId: toId, fxRate: rate))
        list[fi].bankDeposits = outList
        var inList = list[ti].bankDeposits ?? []
        inList.append(BankDeposit(date: date, amount: toAmount, currencyCode: toCode, isWithdrawal: false,
                                  note: note, kind: BankDeposit.kindTransfer,
                                  transferPairId: pair, counterpartyId: fromId, fxRate: rate))
        list[ti].bankDeposits = inList
        milestones = list
    }

    /// [v25.563] 刪一筆存提款紀錄；includingPair：轉帳的話兩邊一起刪。milestones 只指派一次
    func deleteBankDeposit(_ depositId: UUID, in accountId: UUID, includingPair: Bool) {
        var list = milestones
        guard let ai = list.firstIndex(where: { $0.id == accountId }),
              let dep = list[ai].bankDeposits?.first(where: { $0.id == depositId }) else { return }
        list[ai].bankDeposits = (list[ai].bankDeposits ?? []).filter { $0.id != depositId }
        if includingPair, let pair = dep.transferPairId {
            for i in list.indices {
                guard let deps = list[i].bankDeposits, deps.contains(where: { $0.transferPairId == pair }) else { continue }
                list[i].bankDeposits = deps.filter { $0.transferPairId != pair }
            }
        }
        milestones = list
    }

    // MARK: - [v25.564] 財富 v3：卡片頁、要確認、小表單會叫的（都只寫一次 milestones 或一次 wealthBook）

    /// 要確認按了〔知道了〕〔不用改〕〔它不是卡費〕：key 記進帳本（帶事件，下個月同樣的事會再出現）
    func dismissWealthCheck(_ key: String) {
        updateWealthBook { $0.dismiss(key) }
    }

    /// 標成已繳（一期帳單）：哪一天、從哪個帳戶（nil＝別的方式：現金、超商）、繳多少（nil＝全額）。
    /// 寫在帳本（不寫成支出：刷卡時已經記過；還沒更新的 iPad 照舊刷卡當天扣，不會重複扣）。順手清掉「還沒繳」
    func markStatementPaid(cardId: UUID, key: String, date: Date, account: UUID?, amount: Double?) {
        updateWealthBook { book in
            book.updateStatement(cardId: cardId, key: key) { note in
                note.paidDate = WealthCal.day(date)
                note.paidAccount = account
                note.paidAmount = amount
                note.notPaid = nil
            }
        }
    }

    /// 〔取消已繳〕：拿掉你標的已繳（帳單金額不一樣那一欄留著）
    func clearStatementPaid(cardId: UUID, key: String) {
        updateWealthBook { book in
            book.updateStatement(cardId: cardId, key: key) { note in
                note.paidDate = nil
                note.paidAccount = nil
                note.paidAmount = nil
            }
        }
    }

    /// 要確認〔還沒〕〔不是〕之後選了「還沒繳」：過了截止日變逾期，不再當作已繳
    func markStatementNotPaid(cardId: UUID, key: String) {
        updateWealthBook { book in
            book.updateStatement(cardId: cardId, key: key) { note in
                note.paidDate = nil
                note.paidAccount = nil
                note.paidAmount = nil
                note.notPaid = true
            }
        }
    }

    /// 帳單金額不一樣：帳單上寫的數字（nil＝拿掉，回到 App 算的）
    func setStatementStatedAmount(cardId: UUID, key: String, amount: Double?) {
        updateWealthBook { book in
            book.updateStatement(cardId: cardId, key: key) { note in
                note.statedAmount = amount
            }
        }
    }

    /// 長按刷卡〔算到下一期〕／〔算回這一期〕（entryId＝WealthCardEntry.id）
    func setEntryNextPeriod(cardId: UUID, entryId: String, _ next: Bool) {
        updateWealthBook { book in
            var prefs = book.card(cardId)
            var all = prefs.nextPeriodEntries ?? []
            if next { if !all.contains(entryId) { all.append(entryId) } } else { all.removeAll { $0 == entryId } }
            prefs.nextPeriodEntries = all.isEmpty ? nil : all
            book.setCard(prefs, for: cardId)
        }
    }

    /// 要確認 #4〔這筆不算〕：那筆記帳不扣任何帳戶（記帳照留）；excluded false＝算回來
    func excludeExpenseFromWealth(_ expenseId: UUID, excluded: Bool = true) {
        updateWealthBook { $0.setExcluded(expenseId, excluded) }
    }

    /// 帳戶、卡的排序（照陣列的順序寫 sortIndex 0、1、2…）
    func setWealthOrder(_ ids: [UUID]) {
        updateWealthBook { book in
            for (i, id) in ids.enumerated() {
                var prefs = book.account(id)
                prefs.sortIndex = i
                book.setAccount(prefs, for: id)
            }
        }
    }

    /// 收起來（銀行：銷戶）／打開：不算進合計、不出現在選單；歷史照算
    /// [v25.575] 收起來時，碰到這個帳戶、還在跑的定期轉帳一律結束：最後一期＝收起來那天以前的最後一期（endedBy "accountHidden"）。
    /// 收起來有 4 個入口（財富頁、卡片頁、刪銀行時〔收起來就好〕、排序與收起來頁一次好幾個）全部走這支，結束放在這裡就不會漏
    func setWealthHidden(_ id: UUID, hidden: Bool, on date: Date = Date()) {
        updateWealthBook { book in
            var prefs = book.account(id)
            prefs.hidden = hidden ? true : nil
            prefs.closedDate = hidden ? WealthCal.day(date) : nil
            book.setAccount(prefs, for: id)
        }
        if hidden {
            endTransferRules(touching: id, lastOnOrBefore: WealthCal.addDays(-1, to: WealthCal.day(date)),
                             endedBy: "accountHidden", now: date)
        }
    }

    /// 算不算進存款合計（小孩的戶頭可以列著但不算）
    func setWealthCountInCash(_ id: UUID, _ counts: Bool) {
        updateWealthBook { book in
            var prefs = book.account(id)
            prefs.countInCash = counts ? nil : false
            book.setAccount(prefs, for: id)
        }
    }

    /// 停用／啟用一張卡：里程碑 isDisabled（記帳選單、舊 iPad 照讀）＋帳本記停用日
    func setCardDisabled(_ cardId: UUID, disabled: Bool, on date: Date = Date()) {
        if let i = milestones.firstIndex(where: { $0.id == cardId }) {
            var m = milestones[i]
            m.isDisabled = disabled ? true : nil
            milestones[i] = m
        }
        updateWealthBook { book in
            var prefs = book.account(cardId)
            prefs.closedDate = disabled ? WealthCal.day(date) : nil
            book.setAccount(prefs, for: cardId)
        }
    }

    /// 新增或改一筆財富自己記的紀錄（存款、提款、利息、手續費、對存摺）。milestones 只指派一次
    func upsertBankDeposit(_ dep: BankDeposit, in accountId: UUID) {
        var list = milestones
        guard let ai = list.firstIndex(where: { $0.id == accountId }) else { return }
        var deps = list[ai].bankDeposits ?? []
        if let di = deps.firstIndex(where: { $0.id == dep.id }) { deps[di] = dep } else { deps.append(dep) }
        list[ai].bankDeposits = deps
        milestones = list
    }

    /// 要確認 #8〔改過來〕：舊版記錯的外幣扣款改成換算後的數字（WealthCheck.Fix.fixLegacyFX 帶來的）
    func fixLegacyFX(accountId: UUID, depositId: UUID, amount: Double) {
        var list = milestones
        guard let ai = list.firstIndex(where: { $0.id == accountId }),
              var deps = list[ai].bankDeposits,
              let di = deps.firstIndex(where: { $0.id == depositId }) else { return }
        deps[di].amount = amount
        list[ai].bankDeposits = deps
        milestones = list
    }

    /// 月薪的金額歷史寫進帳本（AddIncomeView 存檔時；Income.amountHistory 照寫一份給還沒更新的版本）
    func setIncomeAmountHistory(_ incomeId: UUID, _ history: [AmountSnapshot]?) {
        updateWealthBook { $0.setIncomeAmountHistory(history, for: incomeId) }
    }

    /// 定期扣款、月薪改到別張卡或別的帳戶（一次改到別張卡…、〔改到別的帳戶…〕、要確認〔改刷別張〕）。
    /// from：從哪天起（nil＝以前的也改）。以前的照舊記在原本的卡或帳戶：帳本 linkFrom 第一次改時補一段「最早 → 原本的」，
    /// 再加「這天起 → 新的」；最後一段一律跟著記帳那筆現在的連結（跟 recordCardPayFromChange 同一招）。
    /// 記帳那筆的連結照新的寫：改到卡＝linkedCreditCardMilestoneId＋那張卡現在的扣款帳戶（選卡時本來就一起寫）；
    /// 改到銀行＝清掉卡、linkedBankMilestoneId＝那個帳戶（幣別回台幣）。收入只改 linkedBankMilestoneId。
    func moveWealthLinks(expenseIds: [UUID], incomeIds: [UUID], to target: UUID, from day: Date?,
                         expense: ExpenseStore) {
        let isCard = milestones.contains { $0.id == target && $0.financeSubCategory == .creditCard }
        let cardPayer: UUID? = isCard ? milestones.first(where: { $0.id == target })?.linkedBankMilestoneId : nil
        let fromKey: String? = day.map { WealthCal.dayKey($0) }
        var expenses = expense.expenses
        var incomes = expense.incomes
        var expensesChanged = false
        var incomesChanged = false
        var book = wealthBook
        for i in expenses.indices where expenseIds.contains(expenses[i].id) {
            let old: UUID? = expenses[i].linkedCreditCardMilestoneId ?? expenses[i].linkedBankMilestoneId
            guard old != target else { continue }
            book.setLinks(Self.linkHistory(book.links(expenses[i].id), old: old, new: target, fromKey: fromKey),
                          for: expenses[i].id)
            if isCard {
                expenses[i].linkedCreditCardMilestoneId = target
                expenses[i].linkedBankMilestoneId = cardPayer
                expenses[i].linkedBankCurrency = nil
            } else {
                expenses[i].linkedCreditCardMilestoneId = nil
                expenses[i].linkedBankMilestoneId = target
                expenses[i].linkedBankCurrency = nil
            }
            expensesChanged = true
        }
        if !isCard {
            for i in incomes.indices where incomeIds.contains(incomes[i].id) {
                let old = incomes[i].linkedBankMilestoneId
                guard old != target else { continue }
                book.setLinks(Self.linkHistory(book.links(incomes[i].id), old: old, new: target, fromKey: fromKey),
                              for: incomes[i].id)
                incomes[i].linkedBankMilestoneId = target
                incomes[i].linkedBankCurrency = nil
                incomesChanged = true
            }
        }
        if book != wealthBook { wealthBook = book }
        if expensesChanged { expense.expenses = expenses }
        if incomesChanged { expense.incomes = incomes }
    }

    /// 改連結的歷史：fromKey nil＝整段都是新的（拿掉歷史）；不然第一次改先補「最早 → 原本的」，最新那一段定成原本的，
    /// 拿掉 fromKey 以後的段，再加「fromKey → 新的」（最後一段讀的時候一律跟著現在的連結）
    static func linkHistory(_ h0: [WealthPayFrom]?, old: UUID?, new: UUID?, fromKey: String?) -> [WealthPayFrom]? {
        guard let key = fromKey else { return nil }
        var h = (h0 ?? []).sorted { $0.fromKey < $1.fromKey }
        if h.isEmpty {
            h.append(WealthPayFrom(fromKey: "", accountId: old))
        } else {
            h[h.count - 1].accountId = old
        }
        h.removeAll { !$0.fromKey.isEmpty && $0.fromKey >= key }
        h.append(WealthPayFrom(fromKey: key, accountId: new))
        return h
    }

    /// 要確認 #5〔已經退訂〕：這幾筆定期扣款在那天結束（endDate；那天那期照扣）
    func endRecurring(expenseIds: [UUID], on day: Date, expense: ExpenseStore) {
        var expenses = expense.expenses
        var changed = false
        for i in expenses.indices where expenseIds.contains(expenses[i].id) {
            expenses[i].endDate = WealthCal.day(day)
            changed = true
        }
        if changed { expense.expenses = expenses }
    }

    /// 新增／編輯一個財富帳戶（WealthAccountEditor 存檔）：里程碑一次指派（身分＋舊欄位，給舊 iPad、網頁版、醫療地圖），
    /// 帳本一次寫（暱稱、卡費怎麼繳、保單繳法…）。openingBalances：新增銀行帳戶時「今天存摺上有多少」（幣別 → 數字），
    /// 每個幣別寫一筆對存摺（kind anchor；amount／isWithdrawal 照寫差額給舊 iPad——新帳戶 App 算的是 0）。
    /// 日期記在「昨天結束時」：對存摺是那天結束時的數字（同一天記的會被它吸收），記成今天的話，
    /// 開完帳戶馬上記一筆今天的扣款，數字會不動；記昨天，今天起記的每一筆都會算進去。
    /// 卡費怎麼繳改成自己繳／每次問我時，從今天起才追（呼叫端先用 WealthCardPrefs.setMode 設好）。
    /// [v25.568] vault：這一筆的號碼密文（有效期限、保單號碼、票證號；表單 sealVault 封好的）。nil＝不動那一包
    ///（先寫密文那一包、再寫里程碑：里程碑上的明碼由表單換成後 4 碼）
    func saveWealthAccount(_ item: LifeMilestone, prefs: WealthAccountPrefs, card: WealthCardPrefs?,
                           policy: WealthPolicyPrefs?, openingBalances: [String: Double], now: Date = Date(),
                           vault: WealthVaultEntry? = nil) {
        if let vault {
            let vid = item.id
            updateWealthVault { $0.setEntry(vault, for: vid) }
        }
        var m = item
        if !openingBalances.isEmpty {
            var deps = m.bankDeposits ?? []
            let anchorDay = WealthCal.addDays(-1, to: WealthCal.day(now))
            for (code, value) in openingBalances.sorted(by: { $0.key < $1.key }) {
                deps.append(BankDeposit(date: anchorDay, amount: Swift.abs(value), currencyCode: code,
                                        isWithdrawal: value < 0, isAdjust: true, note: "開戶時的存摺",
                                        kind: BankDeposit.kindAnchor, anchorAmount: value))
            }
            m.bankDeposits = deps
        }
        var list = milestones
        if let i = list.firstIndex(where: { $0.id == m.id }) { list[i] = m } else { list.append(m) }
        milestones = list
        let id = m.id
        updateWealthBook { book in
            book.setAccount(prefs, for: id)
            if let card { book.setCard(card, for: id) }
            if let policy { book.setPolicy(policy, for: id) }
        }
    }

    // MARK: - [v25.566] 財富 v5：定存（WealthDepositBook；build/v5/brief.md §2）

    /// 改定存那一包（改完跟原本一樣就不寫，不白跑一次存檔與 iCloud）
    func updateWealthDeposits(_ body: (inout WealthDepositBook) -> Void) {
        var b = wealthDeposits
        body(&b)
        if b != wealthDeposits { wealthDeposits = b }
    }

    /// 到期本息續存／本金續存、自動接的下一期寫進帳本（同一個 id：WealthTimeDeposit.successorId；寫過的不再寫，不重複）。
    /// 財富頁打開、回到前景時叫（在下一個 runloop：不在畫面更新當中寫 store）；沒有要寫的什麼都不做。
    /// 還沒寫進去以前，WealthFacts 照樣把下一期算進去（數字不等這一支）
    func rollOverTimeDeposits(now: Date = Date()) {
        if let b = wealthDeposits.rolledOver(through: WealthCal.day(now)) {
            wealthDeposits = b
        }
    }

    /// 新增／改一期定存（WealthTimeDepositSheet 存檔）：先把自動續存算出來的那幾期寫進來，再整筆換掉
    /// （改的是自動續存的那一期也一樣：同一個 id）
    func saveTimeDeposit(_ d: WealthTimeDeposit, now: Date = Date()) {
        updateWealthDeposits { book in
            if let rolled = book.rolledOver(through: WealthCal.day(now)) { book = rolled }
            book.upsert(d)
        }
    }

    /// 改到期怎麼處理（要確認 #13〔改成轉活存〕〔改成本息續存〕、到期再決定〔轉活存〕〔本息續存〕）。
    /// 先寫進自動續存的那幾期（改的可能是還沒寫進帳本的那一期）；改成不續存時，這一期以後自動接的拿掉
    func setTimeDepositOnMaturity(_ id: UUID, mode: WealthMaturityMode, now: Date = Date()) {
        updateWealthDeposits { book in
            if let rolled = book.rolledOver(through: WealthCal.day(now)) { book = rolled }
            guard var d = book.deposit(id) else { return }
            d.onMaturity = mode == .renewAll ? nil : mode.rawValue
            book.upsert(d)
            if !mode.renews { Self.dropSuccessors(of: id, in: &book) }
        }
    }

    /// 提前解約（那天、實拿的利息；本金＋利息轉進到期轉進的帳戶）：這一期以後自動接的拿掉
    func closeTimeDeposit(_ id: UUID, on day: Date, interest: Double?, now: Date = Date()) {
        updateWealthDeposits { book in
            if let rolled = book.rolledOver(through: WealthCal.day(now)) { book = rolled }
            guard var d = book.deposit(id) else { return }
            d.closedDate = WealthCal.day(day)
            d.closedInterest = interest.flatMap { $0 > 0 ? $0 : nil }
            book.upsert(d)
            Self.dropSuccessors(of: id, in: &book)
        }
    }

    /// 取消提前解約（解約記錯了）
    func reopenTimeDeposit(_ id: UUID) {
        updateWealthDeposits { book in
            guard var d = book.deposit(id) else { return }
            d.closedDate = nil
            d.closedInterest = nil
            book.upsert(d)
        }
    }

    /// 刪一筆定存（judge §5.6：先問）：整串一起刪（只刪一期的話上一期會再自動續存出同一期）。
    /// keepTransfer：起存時「從活存轉出」的那一筆要留著（錢不回到活存）→ 在那個帳戶記一筆真的提款（起存日、本金）
    func deleteTimeDeposit(_ id: UUID, keepTransfer: Bool, now: Date = Date()) {
        // 先寫進自動續存算出來的那幾期（刪的可能是還沒寫進帳本的那一期：不先寫進來就找不到它的上一期）
        var book = wealthDeposits
        if let rolled = book.rolledOver(through: WealthCal.day(now)) { book = rolled }
        let ids = WealthDepositChain.chainIds(containing: id, in: book.all)
        let chain = book.all.filter { ids.contains($0.id) }
        if keepTransfer {
            let isLegacy: (UUID) -> Bool = { bid in
                self.milestones.first(where: { $0.id == bid })?.bankAccountType == .fixed
            }
            var list = milestones
            var changed = false
            for d in chain where d.fromLive == true && !isLegacy(d.bankId) {
                guard let ai = list.firstIndex(where: { $0.id == d.bankId }) else { continue }
                var deps = list[ai].bankDeposits ?? []
                deps.append(BankDeposit(date: WealthCal.day(d.start), amount: d.principal, currencyCode: d.code,
                                        isWithdrawal: true, note: "轉定存（定存紀錄已刪）",
                                        kind: BankDeposit.kindWithdrawal))
                list[ai].bankDeposits = deps
                changed = true
            }
            if changed { milestones = list }
        }
        book.removeChain(containing: id)
        if book != wealthDeposits { wealthDeposits = book }
    }

    /// 定存表單要的那一筆（帳本裡的；自動續存還沒寫進帳本的那一期照算出來的給，previousId 都在）。只讀，不寫任何東西：
    /// 表單改一份副本，存檔叫 saveTimeDeposit（會先把自動續存的那幾期寫進來，再整筆換掉）
    func timeDepositRecord(_ id: UUID, now: Date = Date()) -> WealthTimeDeposit? {
        if let d = wealthDeposits.deposit(id) { return d }
        let terms = WealthDepositChain.terms(wealthDeposits.all, through: WealthCal.day(now))
        return terms.first(where: { $0.deposit.id == id })?.deposit
    }

    /// 要確認 #14 存款保險〔知道了〕：這家銀行一年內不再提
    func quietDepositInsurance(_ bankKey: String, now: Date = Date()) {
        updateWealthDeposits { $0.quietInsurance(bankKey, until: WealthCal.addDays(365, to: WealthCal.day(now))) }
    }

    /// 這一期以後自動接的（previousId 一路指回它的）全部拿掉
    private static func dropSuccessors(of id: UUID, in book: inout WealthDepositBook) {
        var drop = Set<UUID>()
        var frontier: [UUID] = [id]
        var n = 0
        while let cur = frontier.popLast(), n < 10_000 {
            n += 1
            for d in book.all where d.previousId == cur && !drop.contains(d.id) {
                drop.insert(d.id)
                frontier.append(d.id)
            }
        }
        guard !drop.isEmpty else { return }
        book.deposits = book.all.filter { !drop.contains($0.id) }
    }

    // MARK: - [v25.575] 定期轉帳 v1a（WealthTransferBook；transfer/build/v1a/brief.md §2）
    // 規則只算不寫：這裡只改規則與每一期的註記（不寫 BankDeposit、不碰記帳，除了「是同一筆嗎？」答〔是〕那兩支）。
    // 每支只指派一次 wealthTransfers（一次存檔、一次推 iCloud）；刪掉超過 30 天的墓碑順手清掉。畫面先 dismiss、下一個 runloop 才叫

    /// 改定期轉帳那一包（改完跟原本一樣就不寫；順手清掉超過 30 天的墓碑）
    func updateWealthTransfers(now: Date = Date(), _ body: (inout WealthTransferBook) -> Void) {
        var b = wealthTransfers
        body(&b)
        b = b.purged(now: now)
        if b != wealthTransfers { wealthTransfers = b }
    }

    /// 新增（或整條換掉）一條定期轉帳（新增表單存檔；要訂閱，畫面擋）。createdAt 沒有就補上今天這一刻、updatedAt＝現在
    func saveTransferRule(_ rule: WealthTransferRule, now: Date = Date()) {
        var r = rule
        if r.createdAt == nil { r.createdAt = now }
        r.updatedAt = now
        r.deletedAt = nil
        updateWealthTransfers(now: now) { $0.upsert(r) }
    }

    /// 〔結束〕〔結束這條〕：最後一期＝lastKey（那一期原本的日子，含）；nil＝一期都不算（〔設錯了〕：最後一期設在第一期前一天）。
    /// 規則留在「已結束」，以前的期照算（不擋訂閱）
    func endTransferRule(_ id: UUID, lastKey: String?, endedBy: String? = nil, now: Date = Date()) {
        updateWealthTransfers(now: now) { book in
            guard var r = book.rule(id) else { return }
            r.endKey = lastKey ?? Self.transferKeyBeforeStart(r)
            r.endedBy = endedBy
            r.updatedAt = now
            book.upsert(r)
        }
    }

    /// 刪除這條＝墓碑（deletedAt；不展開、不列，30 天後才真的清掉，另一台還沒同步的舊內容不會把它長回來）。要訂閱，畫面擋
    func deleteTransferRule(_ id: UUID, now: Date = Date()) {
        updateWealthTransfers(now: now) { book in
            guard var r = book.rule(id) else { return }
            r.deletedAt = now
            r.updatedAt = now
            book.upsert(r)
        }
    }

    /// 一期的註記：status（WealthTransferStatus.rawValue；nil＝照規則）、dayKey（實際哪天；nil＝原本那天）、amount（nil＝照規則）
    /// 三個一起換掉（lateOut／lateIn 照留）。〔改這一期〕〔銀行這期取消了〕〔這期不轉〕〔沒轉成〕〔今天補轉〕〔復原〕〔銀行還是轉了〕都走這支
    /// （不擋訂閱）。全部回到照規則時留一個只有時間的空註記：不然另一台的舊註記合併時會長回來
    func setTransferNote(ruleId: UUID, key: String, status: String?, dayKey: String?, amount: Double?,
                         now: Date = Date()) {
        updateWealthTransfers(now: now) { book in
            guard var r = book.rule(ruleId) else { return }
            var notes = r.notes ?? [:]
            var n = notes[key] ?? WealthTransferNote()
            n.status = status
            n.dayKey = dayKey == key ? nil : dayKey
            n.amount = amount
            n.at = now
            n.updatedAt = now
            notes[key] = n
            r.notes = notes
            book.upsert(r)
        }
    }

    /// [v25.583] 換匯那一期〔改這一期〕〔今天補轉〕：同上，再加對方收到多少 toAmount（nil＝照規則；跟這一段一樣由呼叫端傳 nil）。
    /// 四個一起換掉（lateOut／lateIn 照留）。例：每月 1 日 NT$9,600 → US$300.00，11/1 那期銀行實際 31.85＝amount 9,555、toAmount nil。
    /// 不擋訂閱（同〔改這一期〕）。不帶 toAmount 的那一支（上面）照舊把 toAmount 留著（〔改到明天〕不會把換匯那期改過的美金洗掉）
    func setTransferNote(ruleId: UUID, key: String, status: String?, dayKey: String?, amount: Double?, toAmount: Double?,
                         now: Date = Date()) {
        updateWealthTransfers(now: now) { book in
            guard var r = book.rule(ruleId) else { return }
            var notes = r.notes ?? [:]
            var n = notes[key] ?? WealthTransferNote()
            n.status = status
            n.dayKey = dayKey == key ? nil : dayKey
            n.amount = amount
            n.toAmount = toAmount
            n.at = now
            n.updatedAt = now
            notes[key] = n
            r.notes = notes
            book.upsert(r)
        }
    }

    /// 只改一期的狀態：〔銀行這期取消了〕〔這期不轉〕"skip"、〔沒轉成〕"failed"、〔復原〕〔銀行還是轉了〕〔還是要轉〕nil（不擋訂閱）。
    /// 金額照留（〔改這一期〕改過的不會不見）；從補轉（原本 "redo"）改成別的時，補轉那天（dayKey）一起拿掉
    func setTransferStatus(ruleId: UUID, key: String, status: String?, now: Date = Date()) {
        updateWealthTransfers(now: now) { book in
            guard var r = book.rule(ruleId) else { return }
            var notes = r.notes ?? [:]
            var n = notes[key] ?? WealthTransferNote()
            if n.status == WealthTransferStatus.redo.rawValue && status != n.status { n.dayKey = nil }
            n.status = status
            n.at = now
            n.updatedAt = now
            notes[key] = n
            r.notes = notes
            book.upsert(r)
        }
    }

    /// 對存摺表單「這天還有：來自 薪轉 +3,000」〔還沒有〕／〔存摺上已經有了〕：那一期這一邊在對存摺之後才進（out＝轉出那邊）
    func setTransferLate(ruleId: UUID, key: String, out: Bool, late: Bool, now: Date = Date()) {
        updateWealthTransfers(now: now) { book in
            guard var r = book.rule(ruleId) else { return }
            var notes = r.notes ?? [:]
            var n = notes[key] ?? WealthTransferNote()
            let value: Bool? = late ? true : nil
            if out {
                guard n.lateOut != value else { return }
                n.lateOut = value
            } else {
                guard n.lateIn != value else { return }
                n.lateIn = value
            }
            n.updatedAt = now
            notes[key] = n
            r.notes = notes
            book.upsert(r)
        }
    }

    /// 存規則時「是同一筆嗎？」收入那筆答〔是〕：那筆週期性收入結束在 day（Income.endDate 照月份算、那個月含：
    /// WealthTransferMatch.endDay 已經是前一個月月底）
    func endRecurringIncome(_ incomeId: UUID, on day: Date, expense: ExpenseStore) {
        var incomes = expense.incomes
        guard let i = incomes.firstIndex(where: { $0.id == incomeId }) else { return }
        incomes[i].endDate = WealthCal.day(day)
        expense.incomes = incomes
    }

    /// 收起來、刪帳戶：碰到這個帳戶、還在跑的規則一律結束，最後一期＝limit（含）以前的最後一期；一期都沒有＝一期都不算
    func endTransferRules(touching accountId: UUID, lastOnOrBefore limit: Date, endedBy: String, now: Date = Date()) {
        let todayKey = WealthCal.dayKey(now)
        updateWealthTransfers(now: now) { book in
            for r0 in book.live where r0.touches(accountId) && r0.isRunning(todayKey: todayKey) {
                var r = r0
                let last: Date? = WealthTransferSchedule.lastOriginal(r, onOrBefore: limit)
                r.endKey = last.map { WealthCal.dayKey($0) } ?? Self.transferKeyBeforeStart(r)
                r.endedBy = endedBy
                r.updatedAt = now
                book.upsert(r)
            }
        }
    }

    /// 第一期的前一天（〔設錯了，一期都不算〕的最後一期）；沒有第一期＝今天前一天
    private static func transferKeyBeforeStart(_ r: WealthTransferRule) -> String {
        let start: Date = r.startKey.flatMap { WealthTransferSchedule.date(fromKey: $0) } ?? WealthCal.day(Date())
        return WealthCal.dayKey(WealthCal.addDays(-1, to: start))
    }

    // MARK: - [v25.577] 定期轉帳 v1b（transfer/build/v1b/brief.md §2；算法在 WealthTransferPlans.swift）
    // 一樣只改規則（不寫 BankDeposit、不碰記帳）、每支只指派一次 wealthTransfers；**不加任何新欄位**（v1a 的 iPhone 會原樣留著）。

    /// 〔改金額或帳戶〕存檔（要訂閱，畫面擋）：body 拿到的是存著的那條**最新的**（另一台剛合併進來的註記不會被表單打開時的舊內容蓋掉），
    /// 改完 updatedAt＝現在。刪掉的（墓碑）不改。分段用 WealthTransferRule.changed(from:_:)
    func updateTransferRule(_ id: UUID, now: Date = Date(), _ body: (inout WealthTransferRule) -> Void) {
        updateWealthTransfers(now: now) { book in
            guard var r = book.rule(id) else { return }
            let before = r
            body(&r)
            guard r != before else { return }
            r.updatedAt = now
            book.upsert(r)
        }
    }

    /// 改週期或日子〔下一期起（以前的照舊）〕（要訂閱，畫面擋）：舊的那條最後一期＝lastKey（nil＝一期都不算：第一期前一天）、
    /// 新的一條接上（previousId＝舊的 id、createdAt／updatedAt＝現在）。兩件事一次寫
    func splitTransferRule(_ oldId: UUID, lastKey: String?, next newRule: WealthTransferRule, now: Date = Date()) {
        updateWealthTransfers(now: now) { book in
            guard var old = book.rule(oldId) else { return }
            old.endKey = lastKey ?? Self.transferKeyBeforeStart(old)
            old.endedBy = nil
            old.updatedAt = now
            book.upsert(old)
            var r = newRule
            r.previousId = oldId
            r.createdAt = now
            r.updatedAt = now
            r.deletedAt = nil
            r.endedBy = nil
            book.upsert(r)
        }
    }

    /// 要確認〔接著轉〕（帳戶收起來時結束、又打開了；不擋訂閱）：WealthTransferRule.resumed（收起來那段記成暫停、下一期起接著轉）
    func resumeTransferRule(_ id: UUID, now: Date = Date()) {
        updateWealthTransfers(now: now) { book in
            guard let r = book.rule(id), r.endedBy == "accountHidden",
                  var resumedRule = r.resumed(today: WealthCal.day(now), now: now) else { return }
            resumedRule.updatedAt = now
            book.upsert(resumedRule)
        }
    }

    /// 財富頁新手邀請〔不用了〕（WealthTransferBook.inviteDismissed：v1a 就有這欄、跟 iCloud 同步）
    func dismissTransferInvite() {
        updateWealthTransfers { book in
            if book.inviteDismissed != true { book.inviteDismissed = true }
        }
    }

    /// 新增／改定期轉帳表單最下面的預覽：帶一包還沒存的定期轉帳重算一次（**不走快取**、很重：畫面停 0.5 秒才叫，打字時不叫）。
    /// 第 4 個 build 呼叫點（其他三個：wealthFacts、passbookBalance、settlementMovePlan），參數照 wealthFacts 那一份
    func wealthFactsPreview(transfers: WealthTransferBook, expense: ExpenseStore, finance: FinanceStore,
                            now: Date = Date()) -> WealthFacts {
        WealthFacts.build(milestones: milestones, book: wealthBook, deposits: wealthDeposits,
                          transfers: transfers,
                          expenses: expense.expenses, incomes: expense.incomes, stocks: finance.stocks,
                          rates: FinanceRates(expense), now: now, insurances: finance.insurances,
                          vehicles: finance.vehicles, realEstates: finance.realEstates,
                          expiryMonths: cardExpiryMonths())
    }

    // MARK: - [v25.579] 定期轉帳 v2 會提醒你（transfer/build/v2/brief.md §2；算法在 WealthTransferNotices.swift）
    // 一樣只改規則與註記（不寫 BankDeposit、不碰記帳）、每支只指派一次 wealthTransfers；**不加任何新欄位**（v1a、v1b 的手機會原樣留著）。
    // 都不擋訂閱（judge §6：〔轉好了〕〔轉了〕〔還沒〕〔暫停〕〔恢復〕是記下銀行真的發生了什麼、銀行那邊停了 App 也要停得了）。
    // 畫面先 dismiss（或關掉小框）、下一個 runloop 才叫

    /// 〔轉好了〕〔今天轉好了〕：那一期記成你轉好了（status "done"）、實際那天 day（＝原本那天就不存 dayKey）、
    /// 實際轉了多少 amount（nil＝照留；跟這一段每期一樣＝不存）、今天對存摺的時候還沒轉的那一邊 lateOut／lateIn（nil＝照留；
    /// true＝排在對存摺後面、false＝拿掉）。〔轉了〕（過了日子那一期當天就轉了）走 setTransferStatus(… "done")，日子照留
    /// [v25.583] toAmount：換匯那一期對方實際收到多少（nil＝照留；跟這一段一樣＝不存）
    func markTransferDone(ruleId: UUID, key: String, day: Date, amount: Double? = nil, lateOut: Bool? = nil,
                          lateIn: Bool? = nil, toAmount: Double? = nil, now: Date = Date()) {
        updateWealthTransfers(now: now) { book in
            guard var r = book.rule(ruleId) else { return }
            var notes = r.notes ?? [:]
            var n = notes[key] ?? WealthTransferNote()
            n.status = WealthTransferStatus.done.rawValue
            let dk = WealthCal.dayKey(day)
            n.dayKey = dk == key ? nil : dk
            if let v = amount {
                let seg: Double = r.segment(at: key)?.amount ?? 0
                // [v25.583 裁定修] 跟這一段一樣＝不存：台幣 ±0.5、外幣轉出（美金戶自己轉）±0.005
                //（US$300.40 跟規則的 300.00 不一樣，要存；以前一律 ±0.5 會被當成一樣）
                let fromNTD: Bool = FinanceRates.isNTD(r.segment(at: key)?.fromCode ?? "NT$")
                let tol: Double = fromNTD ? 0.5 : 0.005
                n.amount = Swift.abs(v - seg) < tol ? nil : v
            }
            if let ta = toAmount {
                let segTo: Double = r.segment(at: key)?.toAmount ?? (r.segment(at: key)?.amount ?? 0)
                n.toAmount = Swift.abs(ta - segTo) < 0.005 ? nil : ta
            }
            if let lo = lateOut { n.lateOut = lo ? true : nil }
            if let li = lateIn { n.lateIn = li ? true : nil }
            n.at = now
            n.updatedAt = now
            notes[key] = n
            r.notes = notes
            book.upsert(r)
        }
    }

    /// 〔暫停〕：從 fromKey 那一期（含）起暫停，到 untilKey 那一期恢復（nil＝〔先不設〕）；WealthTransferRule.paused（金額 0 的一段）
    func pauseTransferRule(_ id: UUID, from fromKey: String, until untilKey: String?, now: Date = Date()) {
        updateTransferRule(id, now: now) { r in
            r = r.paused(from: fromKey, until: untilKey, now: now)
        }
    }

    /// 〔恢復〕：從 fromKey 那一期（含）起照轉（WealthTransferRule.unpaused；以前暫停過的期照舊不算）
    func unpauseTransferRule(_ id: UUID, from fromKey: String, now: Date = Date()) {
        updateTransferRule(id, now: now) { r in
            r = r.unpaused(from: fromKey)
        }
    }

    /// 規則頁「這條要提醒我」：rule.remind（nil＝要；v1a 就有這欄）。關掉＝這條的三種通知都不排（要確認照樣問）
    func setTransferRemind(_ id: UUID, on: Bool, now: Date = Date()) {
        updateTransferRule(id, now: now) { r in
            r.remind = on ? nil : false
        }
    }

    // MARK: - [v25.581] 定期轉帳 v3 以前湊的找出來（transfer/build/v3/brief.md §2；算法在 WealthTransferFinds.swift）
    // 不加任何存檔欄位、不開新的同步鍵。要確認 v3 的〔不是〕〔知道了〕走 dismissWealthCheck、〔是同一筆…〕走 endRecurring／
    // excludeExpenseFromWealth／endRecurringIncome、〔那期沒轉成〕走 setTransferStatus "failed"（都是既有的）；新的只有下面這支。

    /// 對存摺〔把差的記成「零用錢」支出〕（judge §3.8、第 8 題）：記帳一筆變動支出（標題「零用錢」、類別其他、台幣、扣這個帳戶、
    /// 日子＝對存摺那天）＋這個帳戶一筆扣款（BankDeposit linkedExpenseId：同 AI 記帳那條路，財富照這筆扣）＋這次對存摺，milestones 只指派一次。
    /// 扣款跟對存摺同一天：對存摺排最後（那天結束時的數字），存摺不會再扣一次；anchor 的差額（amount／isWithdrawal）由呼叫端照
    /// 「扣掉這筆之後」算好（約 0）。spend < 0.5 或找不到帳戶＝只存對存摺。記帳本來就不擋訂閱（對存摺表單打開時擋過了）
    func savePocketAnchor(_ anchor: BankDeposit, accountId: UUID, spend: Double, expense: ExpenseStore) {
        let amount = spend.rounded()
        guard amount >= 0.5, let ai = milestones.firstIndex(where: { $0.id == accountId }) else {
            upsertBankDeposit(anchor, in: accountId)
            return
        }
        let e = Expense(title: WealthTransferFinds.pocketTitle, amount: amount, date: anchor.date, expenseType: .variable,
                        variableCategory: .other, note: WealthTransferFinds.pocketNote, currencyCode: "NT$",
                        linkedBankMilestoneId: accountId)
        expense.add(e)
        var list = milestones
        var deps = list[ai].bankDeposits ?? []
        deps.append(BankDeposit(date: anchor.date, amount: amount, currencyCode: "NT$", isWithdrawal: true,
                                linkedExpenseId: e.id))
        if let di = deps.firstIndex(where: { $0.id == anchor.id }) { deps[di] = anchor } else { deps.append(anchor) }
        list[ai].bankDeposits = deps
        milestones = list
    }

    // MARK: - [v25.567] 財富 v6：證券戶交割、保單連記帳、從哪扣（build/v6/brief.md §2；都只寫一次 milestones／帳本／記帳／理財）

    /// 股票的交割紀錄重寫一次（股票表單、股票卡加交易、記帳改舊版單筆股票都叫這一支；以前三份各寫各的）：
    /// 這檔股票的交割紀錄（linkedStockId、不是股利）先從**所有**帳戶清掉，再一筆一筆寫進「那一天」該記的帳戶
    /// （WealthStockSettle：帳本 linkFrom 改交割銀行的歷史 → 股票現在的交割銀行 → 證券戶）；股利入帳不動。
    /// 每一筆一個新 id（同以前）；金額、幣別照 stockAmountForAccount 一條規則。milestones 只指派一次
    func rewriteStockSettlements(_ stock: Stock, rates: FinanceRates) {
        let keep = WealthIDs.dividendDepositIds(of: stock)
        let book = wealthBook
        var all = milestones
        var changed = false
        for i in all.indices {
            guard let deps = all[i].bankDeposits else { continue }
            let kept = deps.filter { !($0.linkedStockId == stock.id && !keep.contains($0.id)) }
            if kept.count != deps.count {
                all[i].bankDeposits = kept
                changed = true
            }
        }
        func add(_ raw: Double, on day: Date, out: Bool) {
            guard raw > 0, let acc = WealthStockSettle.account(for: stock, on: day, book: book),
                  let idx = all.firstIndex(where: { $0.id == acc }) else { return }
            let code = WealthStockSettle.currency(for: stock, account: acc)
            let w = stockAmountForAccount(raw, stock: stock, accountCurrency: code, rates: rates)
            var list = all[idx].bankDeposits ?? []
            list.append(BankDeposit(id: UUID(), date: day, amount: w.amount, currencyCode: w.code,
                                    isWithdrawal: out, linkedExpenseId: nil, linkedStockId: stock.id))
            all[idx].bankDeposits = list
            changed = true
        }
        if !stock.transactions.isEmpty {
            for tx in stock.transactions {
                add(tx.amount, on: tx.settlementDate, out: tx.kind == .buy)
            }
        } else {
            add(stock.shares * stock.purchasePrice, on: StockTransaction.taiwanSettlementDate(from: stock.purchaseDate),
                out: true)
            if stock.isSold, stock.soldPrice > 0, let sd = stock.soldDate {
                add(stock.shares * stock.soldPrice, on: StockTransaction.taiwanSettlementDate(from: sd), out: false)
            }
        }
        if changed { milestones = all }
    }

    /// 證券戶改交割銀行時選「這幾檔也一起改」（judge §4.3 ⑥：以前的交割不動）：這個證券戶還沒賣掉的股票（台幣交割的；
    /// [v25.567 驗] 外幣交割的不動）交割銀行改成 bankId，
    /// 帳本 linkFrom[股票] 記「今天起 → 新的」（以前的照舊記在原本的帳戶）；今天以後（含今天）還沒交割的那幾筆搬到新的銀行。
    /// 證券戶自己的 settlementBankId 由表單照舊寫（saveWealthAccount）。帳本、milestones、股票各只指派一次
    func moveBrokerStocks(_ brokerId: UUID, to bankId: UUID, finance: FinanceStore, now: Date = Date()) {
        let today = WealthCal.day(now)
        let fromKey = WealthCal.dayKey(today)
        var stocks = finance.stocks
        var book = wealthBook
        var all = milestones
        var moved = Set<UUID>()
        var stocksChanged = false
        for i in stocks.indices where stocks[i].linkedSecuritiesMilestoneId == brokerId && !stocks[i].isSold {
            let s = stocks[i]
            guard s.linkedBankMilestoneId != bankId else { continue }
            // [v25.567 驗] 外幣交割的（複委託從美金子帳戶扣）不跟著改：證券戶的交割銀行是台幣那一個；以前一起搬，
            // 今天以後的美金交割原封搬進台幣帳戶（多一個美金格子），之後重寫又把以前的美金交割換成台幣記在原本的帳戶
            guard FinanceRates.isNTD(s.linkedBankCurrency ?? "NT$") else { continue }
            let old: UUID? = s.linkedBankMilestoneId ?? s.linkedSecuritiesMilestoneId
            book.setLinks(Self.linkHistory(book.links(s.id), old: old, new: bankId, fromKey: fromKey), for: s.id)
            stocks[i].linkedBankMilestoneId = bankId
            stocks[i].linkedBankCurrency = nil
            moved.insert(s.id)
            stocksChanged = true
        }
        guard stocksChanged else { return }
        // 今天以後的交割（還沒發生）搬到新的銀行；股利不動
        var dividendIds = Set<UUID>()
        for s in stocks where moved.contains(s.id) { dividendIds.formUnion(WealthIDs.dividendDepositIds(of: s)) }
        var carry: [BankDeposit] = []
        for i in all.indices where all[i].id != bankId {
            guard let deps = all[i].bankDeposits else { continue }
            var kept: [BankDeposit] = []
            for d in deps {
                if let sid = d.linkedStockId, moved.contains(sid), !dividendIds.contains(d.id),
                   WealthCal.day(d.date) >= today {
                    carry.append(d)
                } else {
                    kept.append(d)
                }
            }
            if kept.count != deps.count { all[i].bankDeposits = kept }
        }
        if !carry.isEmpty, let bi = all.firstIndex(where: { $0.id == bankId }) {
            var list = all[bi].bankDeposits ?? []
            list.append(contentsOf: carry)
            all[bi].bankDeposits = list
        }
        if book != wealthBook { wealthBook = book }
        if !carry.isEmpty { milestones = all }
        finance.stocks = stocks
    }

    /// #16〔搬到薪轉〕、證券戶頁 ④：先算「會動到哪些」（你看過、按確定才 moveLegacySettlements）。沒有可搬的、沒有交割銀行＝nil。
    /// 算「搬完的樣子」要重算一次一套數字（只在打開那張確認表單時叫一次，打字不會叫）
    func settlementMovePlan(brokerId: UUID, expense: ExpenseStore, finance: FinanceStore,
                            now: Date = Date()) -> WealthSettlementMovePlan? {
        let facts = wealthFacts(expense: expense, finance: finance, now: now)
        guard let b = facts.broker(brokerId), let bankId = b.settlementBankId,
              let km = milestones.first(where: { $0.id == brokerId }) else { return nil }
        let stocksById = Dictionary(finance.stocks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let rates = FinanceRates(expense)
        var dividendIds = Set<UUID>()
        for s in finance.stocks { dividendIds.formUnion(WealthIDs.dividendDepositIds(of: s)) }
        var moves: [WealthSettlementMovePlan.Move] = []
        var skipIds: [UUID] = []
        var keepIds: [UUID] = []
        var buys = 0, sells = 0, dividends = 0
        var total: Double = 0
        for dep in km.bankDeposits ?? [] where dep.linkedStockId != nil && !dep.isTransfer && !dep.isAnchor {
            guard let sid = dep.linkedStockId, let s = stocksById[sid] else {
                keepIds.append(dep.id)
                continue
            }
            // 每一筆搬到那檔股票自己的交割銀行（沒有＝證券戶的交割銀行）
            let target: UUID = s.linkedBankMilestoneId ?? bankId
            let targetDeps: [BankDeposit] = milestones.first(where: { $0.id == target })?.bankDeposits ?? []
            let day = WealthCal.day(dep.date)
            let dup = targetDeps.contains { d in
                d.linkedStockId == sid && d.isWithdrawal == dep.isWithdrawal && WealthCal.day(d.date) == day
                    && Swift.abs(d.amount - dep.amount) < 0.5
            }
            if dup {
                skipIds.append(dep.id)
                continue
            }
            moves.append(WealthSettlementMovePlan.Move(depositId: dep.id, targetId: target))
            if dividendIds.contains(dep.id) { dividends += 1 } else if dep.isWithdrawal { buys += 1 } else { sells += 1 }
            let r = rates.known(WealthFacts.norm(dep.currencyCode)) ?? 1
            total += (dep.isWithdrawal ? -dep.amount : dep.amount) * r
        }
        guard !moves.isEmpty || !skipIds.isEmpty else { return nil }
        let stockIds: [UUID] = finance.stocks.filter {
            $0.linkedSecuritiesMilestoneId == brokerId && $0.linkedBankMilestoneId == nil
        }.map(\.id)
        var plan = WealthSettlementMovePlan(
            brokerId: brokerId, brokerName: b.name, bankId: bankId, bankName: b.settlementName ?? "交割銀行",
            moves: moves, skipIds: skipIds, keepIds: keepIds, buys: buys, sells: sells, dividends: dividends,
            total: total, stockIds: stockIds, bankBefore: facts.account(bankId)?.ntdTotal ?? 0, bankAfter: 0,
            cashBefore: facts.cash, cashAfter: 0, lastAnchor: facts.account(bankId)?.lastAnchorDate)
        let applied = WealthSettlementMovePlan.applied(plan, milestones: milestones, stocks: finance.stocks)
        let after = WealthFacts.build(milestones: applied.milestones, book: wealthBook, deposits: wealthDeposits,
                                      transfers: wealthTransfers,
                                      expenses: expense.expenses, incomes: expense.incomes, stocks: applied.stocks,
                                      rates: rates, now: now)
        plan.bankAfter = after.account(bankId)?.ntdTotal ?? 0
        plan.cashAfter = after.cash
        return plan
    }

    /// 你按了確定：照計畫搬（證券戶拿掉要搬的、已經有同一筆的；交割銀行加上搬過去的，id 不變；這個證券戶還沒有交割銀行的股票
    /// 改成交割銀行＝它）。milestones、股票各只指派一次。搬完證券戶不再有那幾筆，#16 自己不見
    /// [v25.567 驗] 帳本改交割銀行的歷史裡指著這個證券戶的那一段（舊資料只選證券戶、之後證券戶〔一起改〕記的「以前→證券戶」）
    /// 改成那檔股票的交割銀行（沒有＝證券戶的交割銀行，同搬過去的地方）：不然之後重寫交割（股票卡加一筆、股票表單存檔）
    /// 又把以前的寫回證券戶，#16 又跳出來
    func moveLegacySettlements(_ plan: WealthSettlementMovePlan, finance: FinanceStore) {
        let applied = WealthSettlementMovePlan.applied(plan, milestones: milestones, stocks: finance.stocks)
        milestones = applied.milestones
        if applied.stocksChanged { finance.stocks = applied.stocks }
        var book = wealthBook
        for s in applied.stocks {
            guard var h = book.links(s.id), h.contains(where: { $0.accountId == plan.brokerId }) else { continue }
            let dest: UUID = s.linkedBankMilestoneId ?? plan.bankId
            for i in h.indices where h[i].accountId == plan.brokerId { h[i].accountId = dest }
            book.setLinks(h, for: s.id)
        }
        if book != wealthBook { wealthBook = book }
    }

    /// 保單連到記帳的這一筆保費（#15〔是同一張，連起來〕、保單頁〔連到記帳的保費〕）：帳本 policies[id].linkedExpenseId；
    /// 這一筆原本連著別張保單的那張解開（一筆只連一張）。舊欄位照記帳那一筆寫一份（里程碑 premiumAmount、帳本繳法、從哪扣、
    /// 下次扣款日：給還沒更新的 iPad、網頁版；畫面一律讀記帳那一筆）
    func linkPolicy(_ policyId: UUID, expenseId: UUID, expense: ExpenseStore, now: Date = Date()) {
        guard let e = expense.expenses.first(where: { $0.id == expenseId }) else { return }
        var book = wealthBook
        var all = book.policies ?? [:]
        for key in Array(all.keys) where key != policyId.uuidString {
            if all[key]?.linkedExpenseId == expenseId { all[key]?.linkedExpenseId = nil }
        }
        book.policies = all.isEmpty ? nil : all
        var prefs = book.policy(policyId)
        prefs.linkedExpenseId = expenseId
        Self.mirrorPolicy(&prefs, expense: e, now: now)
        book.setPolicy(prefs, for: policyId)
        if book != wealthBook { wealthBook = book }
        mirrorPolicyPremium(policyId, expense: e)
    }

    /// 解開保單跟記帳保費的連結（保單頁、刪保單「只解開連結」）：記帳那一筆不動
    func unlinkPolicy(_ policyId: UUID) {
        updateWealthBook { book in
            var prefs = book.policy(policyId)
            prefs.linkedExpenseId = nil
            book.setPolicy(prefs, for: policyId)
        }
    }

    /// 保單頁〔年繳〕：舊資料沒寫繳法（raw＝WealthPolicyCycle.rawValue）
    func setPolicyCycle(_ policyId: UUID, cycle raw: String) {
        guard WealthPolicyCycle(rawValue: raw) != nil else { return }
        updateWealthBook { book in
            var prefs = book.policy(policyId)
            prefs.payCycle = raw
            book.setPolicy(prefs, for: policyId)
        }
    }

    /// 保單表單存檔後的保費（judge §5.4-3，保費＝記帳那一筆）。呼叫端先 saveWealthAccount 存好保單本身，再叫這支（下一個 runloop）：
    /// • 連著記帳那一筆（或 useExpenseId：你選「用那一筆」）→ 改那一筆：金額改了從今天起（以前的期數照原本的金額，同記帳表單
    ///   「從今天起」AmountHistoryChange）、週期（記帳有對應的才改）、從哪扣改了從今天起（以前的期數照舊記在原本的卡／帳戶，帳本 linkFrom）
    /// • 沒連、create＝true → 新建一筆記帳固定支出（保險、人身保險子分類、第一期＝draft.firstDue）並連起來；
    ///   半年繳、躉繳記帳沒有對應的週期，不建（回 nil，表單 footer 講）；[v25.567 驗] 有繳費年期的扣到期滿那天
    ///  （WealthPolicyLink.premiumStop，endDate），已經繳完的不建
    /// 回傳連著的記帳 id。帳本、記帳、里程碑各只指派一次
    @discardableResult
    func savePolicyPremium(policyId: UUID, draft: WealthPolicyPremiumDraft, useExpenseId: UUID?, create: Bool,
                           expense: ExpenseStore, now: Date = Date()) -> UUID? {
        let today = WealthCal.day(now)
        var expenses = expense.expenses
        var book = wealthBook
        var linkedId: UUID? = useExpenseId ?? book.policy(policyId).linkedExpenseId
        if let lid = linkedId, !expenses.contains(where: { $0.id == lid }) { linkedId = nil }
        let cardPayer: UUID? = draft.cardId.flatMap { cid in milestones.first(where: { $0.id == cid })?.linkedBankMilestoneId }
        var expensesChanged = false
        if let lid = linkedId, let i = expenses.firstIndex(where: { $0.id == lid }) {
            var e = expenses[i]
            if draft.amount > 0, Swift.abs(e.amount - draft.amount) > 0.004 {
                e.amountHistory = AmountHistoryChange.from(now, history: e.amountHistory, current: e.amount,
                                                           firstDate: e.date, newAmount: draft.amount)
                e.amount = draft.amount
            }
            if let r = WealthPolicyLink.recurrence(of: draft.cycle), e.recurrence != r { e.recurrence = r }
            let old: UUID? = e.linkedCreditCardMilestoneId ?? e.linkedBankMilestoneId
            let new: UUID? = draft.cardId ?? draft.bankId
            if old != new {
                book.setLinks(Self.linkHistory(book.links(e.id), old: old, new: new, fromKey: WealthCal.dayKey(today)),
                              for: e.id)
                e.linkedCreditCardMilestoneId = draft.cardId
                e.linkedBankMilestoneId = draft.cardId != nil ? cardPayer : draft.bankId
                e.linkedBankCurrency = draft.cardId != nil ? nil : draft.bankCode
            } else if draft.cardId == nil, draft.bankId != nil, e.linkedBankCurrency != draft.bankCode {
                e.linkedBankCurrency = draft.bankCode
            }
            if !Self.sameExpense(e, expenses[i]) {
                expenses[i] = e
                expensesChanged = true
            }
            linkedId = e.id
        } else if create, let r = WealthPolicyLink.recurrence(of: draft.cycle), draft.amount > 0 {
            // [v25.567 驗] 繳費年期滿了就停（生效日＋繳費年期的前一天；一年一約每年續約、沒填年期不停）；
            // 第一期已經在那之後＝這張保單繳完了，不建（以前照樣建一筆每年扣、沒有停止日的保費）
            let stop: Date? = WealthPolicyLink.premiumStop(start: milestones.first(where: { $0.id == policyId })?.date,
                                                           payYears: book.policy(policyId).payYears)
            let first: Date = WealthCal.day(draft.firstDue)
            let paidUp: Bool = stop.map { first > $0 } ?? false
            if !paidUp {
                let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let e = Expense(title: title.isEmpty ? "保費" : title, amount: draft.amount, date: first,
                                expenseType: .fixed, fixedCategory: .insurance, recurrence: r,
                                insuranceSubCategory: WealthPolicyLink.insuranceSub(draft.kind),
                                note: "", currencyCode: "NT$",
                                linkedBankMilestoneId: draft.cardId != nil ? cardPayer : draft.bankId,
                                linkedBankCurrency: draft.cardId != nil ? nil : draft.bankCode,
                                linkedCreditCardMilestoneId: draft.cardId, endDate: stop)
                expenses.append(e)
                expensesChanged = true
                linkedId = e.id
            }
        }
        var prefs = book.policy(policyId)
        prefs.linkedExpenseId = linkedId
        let linkedExpense: Expense? = linkedId.flatMap { lid in expenses.first(where: { $0.id == lid }) }
        if let e = linkedExpense { Self.mirrorPolicy(&prefs, expense: e, now: now) }
        book.setPolicy(prefs, for: policyId)
        if book != wealthBook { wealthBook = book }
        if expensesChanged { expense.expenses = expenses }
        if let e = linkedExpense { mirrorPolicyPremium(policyId, expense: e) }
        return linkedId
    }

    /// 記帳改了一筆保費（AddExpenseView 存檔後叫，下一個 runloop）：連著它的保單，舊欄位照寫一份（畫面本來就讀記帳那一筆）
    func policyExpenseChanged(_ e: Expense, now: Date = Date()) {
        guard let entry = (wealthBook.policies ?? [:]).first(where: { $0.value.linkedExpenseId == e.id }),
              let pid = UUID(uuidString: entry.key) else { return }
        updateWealthBook { book in
            var prefs = book.policy(pid)
            Self.mirrorPolicy(&prefs, expense: e, now: now)
            book.setPolicy(prefs, for: pid)
        }
        mirrorPolicyPremium(pid, expense: e)
    }

    /// 改一筆記帳固定支出從哪扣（儲蓄險表單「從哪扣」、房屋卡／車子卡貸款列「從哪扣」）：卡優先（卡＝刷卡、銀行跟著那張卡的扣款帳戶）；
    /// from：從哪天起（nil＝以前的也改）。以前的期數照舊記在原本的卡或帳戶（帳本 linkFrom，同 moveWealthLinks）；
    /// 幣別照選的（外幣子帳戶，例：美元儲蓄險從玉山美金扣）。帳本、記帳各只指派一次；什麼都沒變就不寫
    func setExpensePayer(_ expenseId: UUID, bankId: UUID?, bankCode: String?, cardId: UUID?, from day: Date?,
                         expense: ExpenseStore) {
        var expenses = expense.expenses
        guard let i = expenses.firstIndex(where: { $0.id == expenseId }) else { return }
        var e = expenses[i]
        let old: UUID? = e.linkedCreditCardMilestoneId ?? e.linkedBankMilestoneId
        let new: UUID? = cardId ?? bankId
        let cardPayer: UUID? = cardId.flatMap { cid in milestones.first(where: { $0.id == cid })?.linkedBankMilestoneId }
        var book = wealthBook
        if old != new {
            book.setLinks(Self.linkHistory(book.links(e.id), old: old, new: new, fromKey: day.map { WealthCal.dayKey($0) }),
                          for: e.id)
        }
        e.linkedCreditCardMilestoneId = cardId
        e.linkedBankMilestoneId = cardId != nil ? cardPayer : bankId
        e.linkedBankCurrency = cardId != nil ? nil : (bankId != nil ? bankCode : nil)
        guard !Self.sameExpense(e, expenses[i]) || book != wealthBook else { return }
        expenses[i] = e
        if book != wealthBook { wealthBook = book }
        expense.expenses = expenses
    }

    /// 保單的舊欄位照記帳那一筆寫（繳法、從哪扣、下次扣款日的快照）
    private static func mirrorPolicy(_ prefs: inout WealthPolicyPrefs, expense e: Expense, now: Date) {
        if let c = WealthPolicyLink.cycle(of: e.recurrence) { prefs.payCycle = c.rawValue }
        prefs.payFromId = e.linkedCreditCardMilestoneId ?? e.linkedBankMilestoneId
        prefs.nextDue = e.nextFixedDueDate(onOrAfter: WealthCal.day(now), calendar: WealthCal.calendar)
    }

    /// 里程碑的保費照記帳那一筆寫一份（醫療地圖、舊 iPad、網頁版讀這一欄）
    private func mirrorPolicyPremium(_ policyId: UUID, expense e: Expense) {
        guard let i = milestones.firstIndex(where: { $0.id == policyId }) else { return }
        let amount: Double? = e.amount > 0 ? e.amount : nil
        guard milestones[i].premiumAmount != amount else { return }
        var m = milestones[i]
        m.premiumAmount = amount
        milestones[i] = m
    }

    /// 這幾個欄位一樣就不寫（Expense 不是 Equatable）
    private static func sameExpense(_ a: Expense, _ b: Expense) -> Bool {
        a.amount == b.amount && a.recurrence == b.recurrence && a.linkedBankMilestoneId == b.linkedBankMilestoneId
            && a.linkedBankCurrency == b.linkedBankCurrency
            && a.linkedCreditCardMilestoneId == b.linkedCreditCardMilestoneId
            && a.amountHistory == b.amountHistory
    }

    // MARK: - [v25.562] 刪財富帳戶（財富卡片、履歷的刪除都呼叫這一支；以前兩份各寫一次，都漏了卡）

    /// 刪一筆里程碑，並清掉其他資料指到它的連結。任何分類都走這支；財富的銀行、信用卡多做幾件事：
    /// - 刪銀行：掛在它底下的卡改成「沒有扣款帳戶」——以前卡還指著已刪的銀行，財富頁整張卡不見
    /// - 刪卡：[v25.563] 這張卡的每一期帳單，照「那一期的扣款帳戶」各寫回一筆提款，日期＝那一期的繳款截止日
    ///   （還沒到的那幾期到截止日照樣扣）：扣款帳戶的存摺上今天、以後都跟刪之前一樣，對過存摺的也不受影響
    ///   （v1 是合成一筆寫今天：v2 卡費改在截止日才扣、又有對存摺，合成一筆會把還沒扣的、對存摺以前的都扣一次）。
    ///   記帳裡刷這張卡的，卡和銀行兩個連結一起清（銀行連結是選卡時一起設的）
    /// - 股票、記帳、收入指到它的連結照舊清掉；財富帳本裡它的設定一起清
    /// 刪卡之前先問「改成停用」（financeDeletionImpact 的字）。milestones 只指派一次（一次存檔、一次推 iCloud）。
    func deleteFinanceMilestone(_ item: LifeMilestone, finance: FinanceStore, expense: ExpenseStore,
                                now: Date = Date()) {
        let id = item.id
        let target = milestones.first(where: { $0.id == id }) ?? item
        let isCard = target.category == .achievement && target.financeSubCategory == .creditCard
        var list = milestones

        if isCard {
            let cardExpenseIds = Set(expense.expenses.filter { $0.linkedCreditCardMilestoneId == id }.map(\.id))
            // 連到刷卡支出的舊扣款紀錄（正常不會有；有的話以前被「刷卡」規則跳過，清掉卡的連結後會突然算進去）
            if !cardExpenseIds.isEmpty {
                for i in list.indices {
                    guard let deps = list[i].bankDeposits else { continue }
                    let kept = deps.filter { dep in
                        guard let eid = dep.linkedExpenseId else { return true }
                        return !cardExpenseIds.contains(eid)
                    }
                    if kept.count != deps.count { list[i].bankDeposits = kept }
                }
            }
            // 每一期帳單照它的扣款帳戶寫回一筆（先算再清連結）
            let name = target.cardName.flatMap { $0.isEmpty ? nil : $0 } ?? target.title
            let statements = WealthFacts.cardStatements(for: target, milestones: milestones, book: wealthBook,
                                                        expenses: expense.expenses, rates: FinanceRates(expense),
                                                        now: now)
            // [v25.564] 已繳的照「那天從哪個帳戶扣多少」（你標的、自動扣最低只扣一部分）；還沒繳的照截止日從扣款帳戶扣全額。
            // 逾期的、自己繳截止日當天還沒標的：錢還沒離開帳戶（WealthFacts.billRef 算明天），寫成截止日會讓今天的存摺上先少一筆
            //（驗證 build/v3/verify/data_edges.py A、B），所以寫明天
            let today = WealthCal.day(now)
            let tomorrow = WealthCal.addDays(1, to: today)
            for s in statements where s.amount > 0.004 {
                let account: UUID? = s.isPaid ? s.paidFrom : s.payerId
                let unpaidDay: Date = WealthCal.day(s.due) > today ? s.due : tomorrow
                let day: Date = s.isPaid ? (s.paidOn ?? s.due) : unpaidDay
                let amount: Double = s.isPaid ? s.paidAmount : s.amount
                guard amount > 0.004, let payer = account,
                      let bi = list.firstIndex(where: { $0.id == payer }) else { continue }
                var deps = list[bi].bankDeposits ?? []
                deps.append(BankDeposit(date: day, amount: amount, currencyCode: "NT$", isWithdrawal: true,
                                        note: "「\(name)」\(s.label)（刪卡前刷的）"))
                list[bi].bankDeposits = deps
            }
        }

        // 掛在它底下的卡（刪的是銀行時）改成沒有扣款帳戶
        for i in list.indices where list[i].linkedBankMilestoneId == id {
            list[i].linkedBankMilestoneId = nil
        }
        // 照片檔不在 JSON 裡，跟著刪（同 deleteMilestone）
        let photos = target.photoFileNames ?? []
        list.removeAll { $0.id == id }
        milestones = list
        for name in photos { LifeMilestone.deletePhoto(name) }
        // [v25.563] 財富帳本裡它的設定（扣款帳戶的歷史、暱稱…）
        updateWealthBook { $0.remove(id) }
        // [v25.568] 它的號碼密文（有效期限、保單號碼、票證號）
        updateWealthVault { $0.remove(id) }
        // [v25.566] 這個帳戶的定存一起刪；別的定存還沒到期、說好轉進它的，改回轉進自己的帳戶
        // [v25.566 驗證修正] 先寫進自動續存算出來的那幾期（同 save／setMaturity／close／delete）：上一期已經到期、
        // 下一期還沒寫進帳本時，下一期照上一期的 payoutId 算，不先寫進來就改不到，到期的錢會轉進刪掉的帳戶、從合計消失
        updateWealthDeposits { book in
            if let rolled = book.rolledOver(through: WealthCal.day(now)) { book = rolled }
            book.removeBank(id, today: now)
        }
        // [v25.575] 碰到它的定期轉帳結束在今天（今天以前的期照算；不刪規則：另一邊的列寫「轉給 別的帳戶」）
        endTransferRules(touching: id, lastOnOrBefore: WealthCal.day(now), endedBy: "accountDeleted", now: now)

        var stocks = finance.stocks
        var stocksChanged = false
        for i in stocks.indices {
            if stocks[i].linkedBankMilestoneId == id {
                stocks[i].linkedBankMilestoneId = nil
                stocks[i].linkedBankCurrency = nil
                stocksChanged = true
            }
            if stocks[i].linkedSecuritiesMilestoneId == id {
                stocks[i].linkedSecuritiesMilestoneId = nil
                stocksChanged = true
            }
        }
        if stocksChanged { finance.stocks = stocks }

        var expenses = expense.expenses
        var expensesChanged = false
        for i in expenses.indices {
            if expenses[i].linkedCreditCardMilestoneId == id {
                // 刪卡：卡和銀行一起清（不然定期扣款會變成直接扣銀行）
                expenses[i].linkedCreditCardMilestoneId = nil
                expenses[i].linkedBankMilestoneId = nil
                expensesChanged = true
            }
            if expenses[i].linkedBankMilestoneId == id {
                expenses[i].linkedBankMilestoneId = nil
                expensesChanged = true
            }
        }
        if expensesChanged { expense.expenses = expenses }

        var incomes = expense.incomes
        var incomesChanged = false
        for i in incomes.indices where incomes[i].linkedBankMilestoneId == id {
            incomes[i].linkedBankMilestoneId = nil
            incomesChanged = true
        }
        if incomesChanged { expense.incomes = incomes }
    }

    /// [v25.562] 刪之前確認框要講的話：會動到什麼，全部是數出來的。財富卡片、履歷兩邊共用。
    /// [v25.563] 卡費改成一期一期（WealthFacts.cardStatements）：已經扣的、還沒扣的分開講
    func financeDeletionImpact(_ item: LifeMilestone, finance: FinanceStore, expense: ExpenseStore,
                               now: Date = Date()) -> FinanceDeletionImpact {
        let id = item.id
        let target = milestones.first(where: { $0.id == id }) ?? item
        let isFinance = target.category == .achievement
        let isBank = isFinance && target.financeSubCategory == .bank
        let isCard = isFinance && target.financeSubCategory == .creditCard
        let linkedCards = milestones.filter { $0.linkedBankMilestoneId == id }.count
        let directExpenses = expense.expenses.filter {
            $0.linkedBankMilestoneId == id && $0.linkedCreditCardMilestoneId == nil
        }.count
        let incomeCount = expense.incomes.filter { $0.linkedBankMilestoneId == id }.count
        let stockCount = finance.stocks.filter {
            $0.linkedBankMilestoneId == id || $0.linkedSecuritiesMilestoneId == id
        }.count
        // [v25.566] 這個帳戶的定存（每一串算一筆：自動續存的不重複數）
        let depositCount = isBank ? wealthDeposits.all.filter { $0.bankId == id && $0.previousId == nil }.count : 0
        // [v25.575] 碰到它、還在跑的定期轉帳（刪掉時結束在今天）
        let todayKey = WealthCal.dayKey(now)
        let transferCount = isBank
            ? wealthTransfers.live.filter { $0.touches(id) && $0.isRunning(todayKey: todayKey) }.count : 0

        var bankName: String?
        var paidTotal: Double = 0
        var unpaidTotal: Double = 0
        var cardCount = 0
        var recurring: [String] = []
        if isCard {
            if let bid = target.linkedBankMilestoneId, let b = milestones.first(where: { $0.id == bid }) {
                bankName = b.bankName.flatMap { $0.isEmpty ? nil : $0 } ?? b.title
            }
            let cardExpenses = expense.expenses.filter { $0.linkedCreditCardMilestoneId == id }
            cardCount = cardExpenses.count
            let statements = WealthFacts.cardStatements(for: target, milestones: milestones, book: wealthBook,
                                                        expenses: expense.expenses, rates: FinanceRates(expense),
                                                        now: now)
            // [v25.564] 已繳的看實際從銀行扣的（paidFrom／paidAmount），還沒繳的看扣款帳戶
            for s in statements {
                if s.isPaid {
                    if s.paidFrom != nil { paidTotal += s.paidAmount }
                } else if s.payerId != nil {
                    unpaidTotal += s.amount
                }
            }
            for exp in cardExpenses where exp.expenseType == .fixed {
                guard let r = exp.recurrence else { continue }
                if let end = exp.endDate, end <= now { continue }
                let unit: String
                switch r {
                case .monthly: unit = "月"
                case .quarterly: unit = "季"
                case .yearly: unit = "年"
                }
                recurring.append("\(exp.title) \(expense.ntdValue(of: exp).ntdWanString)／\(unit)")
            }
        }
        let name: String = {
            if isBank { return target.bankName.flatMap { $0.isEmpty ? nil : $0 } ?? target.title }
            if isCard { return target.cardName.flatMap { $0.isEmpty ? nil : $0 } ?? target.title }
            return target.title
        }()
        return FinanceDeletionImpact(
            item: target, displayName: name, isBank: isBank, isCard: isCard,
            linkedCardCount: linkedCards, directExpenseCount: directExpenses, incomeCount: incomeCount,
            stockCount: stockCount, debitBankName: bankName, cardTotal: paidTotal,
            unpaidCardTotal: unpaidTotal,
            cardExpenseCount: cardCount, recurringTexts: recurring, timeDepositCount: depositCount,
            transferRuleCount: transferCount)
    }

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
    /// [v25.389] completedAt：要押在兩邊的完成時間。nil＝押現在。
    ///
    /// ⚠️ 這個參數不是裝飾用的。本方法在最後會把兼任那筆的 completedAt 抄回
    ///    **所有**連結的部屬任務／議程項目，包含剛剛觸發它的那一筆。若這裡自己
    ///    另外呼叫一次 Date()，呼叫端剛寫好的壓線時間會在這裡被無聲蓋掉
    ///    （強制準時完成就等於完全沒作用，而且不會有任何錯誤）。
    func propagateCompletionToSideRole(_ back: SideRoleBackLink, isCompleted: Bool,
                                       completedAt: Date? = nil) {
        guard let ri = milestones.firstIndex(where: { $0.id == back.roleId }),
              let ti = milestones[ri].sideRoleTasks?.firstIndex(where: { $0.id == back.taskId }) else { return }
        milestones[ri].sideRoleTasks?[ti].isCompleted = isCompleted
        milestones[ri].sideRoleTasks?[ti].completedAt = isCompleted ? (completedAt ?? Date()) : nil
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

    // MARK: - 績效互評（年度同儕排名）

    /// [v25.348] 評分者要排的名單：依「課別 × 職等」分組。
    ///
    /// 分組規則（使用者定義）：只排同課的人，再依職等分組，評分者自己也在組內（含自評）。
    /// 「我」（selfRaterId）不屬於單一課，所以要排全部課的每一組。
    /// 單人組不產生（自己排自己沒有意義，也拿不出相對名次）。
    func performanceGroups(forRater raterId: UUID) -> [PerformanceRankGroup] {
        let scopeDeptId: UUID??   // nil＝不限課（我）；.some(x)＝限定該課（含 x == nil 的未分部門）
        if raterId == PerformanceBallot.selfRaterId {
            scopeDeptId = nil
        } else if let me = subordinates.first(where: { $0.id == raterId }) {
            scopeDeptId = .some(me.departmentId)
        } else {
            return []
        }
        // 分組鍵：課別 id + 職等 id（都可能是 nil）
        struct Key: Hashable { let dept: UUID?; let grade: UUID? }
        var buckets: [Key: [Subordinate]] = [:]
        for s in subordinates {
            if let scope = scopeDeptId, s.departmentId != scope { continue }
            buckets[Key(dept: s.departmentId, grade: s.gradeTitleId), default: []].append(s)
        }
        let deptName: (UUID?) -> String = { id in
            guard let id, let d = self.departments.first(where: { $0.id == id }) else { return "未分部門" }
            return d.name.isEmpty ? (d.code.isEmpty ? "未命名部門" : d.code) : d.name
        }
        let gradeName: (UUID?) -> String = { id in
            guard let id, let g = self.gradeTitles.first(where: { $0.id == id }) else { return "未設職等" }
            return g.displayLabel.isEmpty ? "未命名職等" : g.displayLabel
        }
        return buckets
            // [v25.372] 單人組以前被濾掉，結果那個職等只有一個人的同仁從頭到尾
            // 不會出現在任何一張票上，評分加總也永遠看不到他。現在一併列入：
            // 一個人的組就是第 1 名、基礎分 1 分。
            .map { key, people in
                PerformanceRankGroup(
                    departmentId: key.dept, departmentName: deptName(key.dept),
                    gradeId: key.grade, gradeLabel: gradeName(key.grade),
                    // 預設順序：沿用部屬清單既有順序，評分者再自行拖曳
                    entries: people.map { PerformanceRankEntry(id: $0.id, name: $0.name.isEmpty ? "未命名" : $0.name) }
                )
            }
            .sorted { a, b in
                if a.departmentName != b.departmentName { return a.departmentName < b.departmentName }
                return a.gradeLabel < b.gradeLabel
            }
    }

    /// 取某年某人的票；沒有就回 nil
    func performanceBallot(year: Int, raterId: UUID) -> PerformanceBallot? {
        performanceBallots.first { $0.year == year && $0.raterId == raterId }
    }

    /// 取出（或建立）某年某人的票，並把名單與目前的部屬狀態同步：
    /// 新人加進組末、已離開的人移除、組別有增減也一併補上——
    /// 但**已經排好的順序完全保留**，不會因為有人加入就被打散。
    func performanceBallotSynced(year: Int, raterId: UUID,
                                 raterGradeId: UUID?) -> PerformanceBallot {
        let fresh = performanceGroups(forRater: raterId)
        var ballot = performanceBallot(year: year, raterId: raterId)
            ?? PerformanceBallot(year: year, raterId: raterId)
        var merged: [PerformanceRankGroup] = []
        for var g in fresh {
            if let old = ballot.groups.first(where: { $0.departmentId == g.departmentId && $0.gradeId == g.gradeId }) {
                let validIds = Set(g.entries.map(\.id))
                // 舊順序中仍有效的人照舊排在前面，新加入的人接在後面
                var ordered = old.entries.filter { validIds.contains($0.id) }
                let seen = Set(ordered.map(\.id))
                ordered.append(contentsOf: g.entries.filter { !seen.contains($0.id) })
                // 姓名用最新的（改名要跟著更新，離開的人不在名單裡本來就不影響）
                let nameOf = Dictionary(g.entries.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
                g.entries = ordered.map { PerformanceRankEntry(id: $0.id, name: nameOf[$0.id] ?? $0.name) }
            }
            merged.append(g)
        }
        ballot.groups = merged
        // 評分者資料（姓名／職等／權重）以「現在」為準；送出後才凍結成快照
        if raterId == PerformanceBallot.selfRaterId {
            ballot.raterName = profile.chineseName.isEmpty ? "我" : profile.chineseName
        } else if let s = subordinates.first(where: { $0.id == raterId }) {
            ballot.raterName = s.name.isEmpty ? "未命名" : s.name
        }
        let grade = raterGradeId.flatMap { gid in gradeTitles.first(where: { $0.id == gid }) }
        ballot.raterGradeId = raterGradeId
        ballot.raterGradeLabel = grade?.displayLabel ?? ""
        ballot.raterWeight = grade?.weightValue ?? 1
        return ballot
    }

    func upsertPerformanceBallot(_ ballot: PerformanceBallot) {
        isLoading = true
        defer { isLoading = false }
        if let i = performanceBallots.firstIndex(where: { $0.id == ballot.id }) {
            performanceBallots[i] = ballot
        } else if let i = performanceBallots.firstIndex(where: {
            $0.year == ballot.year && $0.raterId == ballot.raterId
        }) {
            performanceBallots[i] = ballot
        } else {
            performanceBallots.append(ballot)
        }
        save()
    }

    func deletePerformanceBallot(_ id: UUID) {
        performanceBallots.removeAll { $0.id == id }
    }

    /// 有票的年度（新到舊）；沒有任何票時回傳今年
    var performanceYears: [Int] {
        let ys = Set(performanceBallots.map(\.year))
        let thisYear = Calendar.current.component(.year, from: Date())
        return ys.isEmpty ? [thisYear] : Array(ys.union([thisYear])).sorted(by: >)
    }

    /// 年度加總：每張票的每一組，第 1 名拿「組人數」分，往下遞減，再乘上該票的權重。
    /// 只計已送出的票（草稿不計）。人被移出課別或離職，票裡的快照仍在，分數照樣保留。
    func performanceScores(year: Int) -> [PerformanceScore] {
        var totals: [UUID: PerformanceScore] = [:]
        // 每個人被排在哪個職等：票上的快照可能不只一種（例如年中升職），取出現最多次的那個
        var gradeVotes: [UUID: [PerformanceGradeKey: Int]] = [:]
        for ballot in performanceBallots where ballot.year == year && ballot.isSubmitted {
            for g in ballot.groups {
                let n = g.entries.count
                // [v25.372] 單人組也算（第 1 名基礎分 1）；空組才跳過
                guard n >= 1 else { continue }
                let key = PerformanceGradeKey(id: g.gradeId, label: g.gradeLabel)
                for (idx, entry) in g.entries.enumerated() {
                    gradeVotes[entry.id, default: [:]][key, default: 0] += 1
                    let src = PerformanceScoreSource(
                        raterId: ballot.raterId, raterName: ballot.raterName,
                        raterGradeLabel: ballot.raterGradeLabel, weight: ballot.raterWeight,
                        rank: idx + 1, groupSize: n, groupTitle: g.title
                    )
                    var cur = totals[entry.id] ?? PerformanceScore(
                        personId: entry.id, name: entry.name, total: 0, sources: []
                    )
                    // 姓名以目前的部屬資料優先（改名跟著更新），查不到才用票上的快照
                    if let s = subordinates.first(where: { $0.id == entry.id }), !s.name.isEmpty {
                        cur.name = s.name
                    }
                    cur.total += src.points
                    cur.sources.append(src)
                    totals[entry.id] = cur
                }
            }
        }
        for (personId, votes) in gradeVotes {
            let top = votes.max { a, b in
                if a.value != b.value { return a.value < b.value }
                return a.key.label < b.key.label
            }
            guard var score = totals[personId], let best = top?.key else { continue }
            score.gradeId = best.id
            score.gradeLabel = best.label
            totals[personId] = score
        }
        // [v25.372] 併入綜合分數：最終分數＝排名分數 × 占比 ＋ 綜合分數 × (1 − 占比)。
        // 三份輸入（被標註／兼任完成／議程項目）各自要掃全庫，所以在迴圈外先算好一次。
        let share = performanceShare(year: year)
        let mentions = mentionedCounts()
        let sideRole = sideRoleTaskCounts()
        let itemCredits = meetingItemCredits()
        for (personId, var score) in totals {
            if let sub = subordinates.first(where: { $0.id == personId }) {
                let act = sub.proactivityScore(mentionedCount: mentions[personId] ?? 0,
                                               sideRoleDone: sideRole[personId]?.done ?? 0,
                                               itemDone: itemCredits[personId] ?? 0)
                score.overallScore = (Double(sub.potentialScore) + Double(act)) / 2
                score.hasOverall = true
            } else {
                // 已轉出／離職：部屬清單裡沒有這個人，算不出現在的綜合分數
                score.overallScore = 0
                score.hasOverall = false
            }
            totals[personId] = score
        }
        // [v25.373] 正規化：每個職等各自找出兩段分數的最高值當 100 分。
        // 基準取**整個職等**（不分課別），所以畫面上套課別篩選不會讓分數跟著變動。
        var rankBasis: [PerformanceGradeKey: Double] = [:]
        var overallBasis: [PerformanceGradeKey: Double] = [:]
        for s in totals.values {
            let key = PerformanceGradeKey(id: s.gradeId, label: s.gradeLabel)
            rankBasis[key] = max(rankBasis[key] ?? 0, s.total)
            overallBasis[key] = max(overallBasis[key] ?? 0, s.overallScore)
        }
        for (personId, var score) in totals {
            let key = PerformanceGradeKey(id: score.gradeId, label: score.gradeLabel)
            let rBase = rankBasis[key] ?? 0
            let oBase = overallBasis[key] ?? 0
            score.rankBasis = rBase
            score.overallBasis = oBase
            score.normalizedRank = rBase > 0 ? score.total / rBase * 100 : 0
            score.normalizedOverall = oBase > 0 ? score.overallScore / oBase * 100 : 0
            score.finalScore = score.normalizedRank * share.rank
                + score.normalizedOverall * share.overall
            // 未正規化的同一式：跨職等對照用（正規化後每個職等的第一名都是 100，比不出來）
            score.rawFinalScore = score.total * share.rank + score.overallScore * share.overall
            totals[personId] = score
        }
        return totals.values.sorted { a, b in
            if a.finalScore != b.finalScore { return a.finalScore > b.finalScore }
            if a.total != b.total { return a.total > b.total }
            return a.name < b.name
        }
    }

    /// [v25.372] 年度採用的「排名分數占比」：所有已送出票填的百分比，
    /// 依各自的評分者職等權重做加權平均。
    /// 例：31 職等(×1) 填 20%、32 職等(×2) 填 10% → (20×1 + 10×2)/(1+2) = 13.3%。
    /// 沒有任何票（或權重總和為 0）時回 0%＝完全沿用綜合分數，與舊版行為一致。
    func performanceShare(year: Int) -> PerformanceShare {
        var votes: [PerformanceShareVote] = []
        for b in performanceBallots where b.year == year && b.isSubmitted {
            votes.append(PerformanceShareVote(
                raterId: b.raterId, raterName: b.raterName.isEmpty ? "未命名" : b.raterName,
                raterGradeLabel: b.raterGradeLabel.isEmpty ? "未設職等" : b.raterGradeLabel,
                weight: b.raterWeight, percent: b.rankSharePercent))
        }
        // 沒有人填過＝還沒設定：rank 固定 1（100% 用排名分數），維持加入占比之前的行為。
        // 這裡不能當成「排名占 0%」，那會把整頁默默換成綜合分數排名。
        let configured = votes.contains { $0.percent > 0 }
        let weightSum = votes.reduce(0.0) { $0 + $1.weight }
        guard configured, weightSum > 0 else {
            return PerformanceShare(rank: 1, votes: votes, isConfigured: false)
        }
        let weighted = votes.reduce(0.0) { $0 + $1.weighted } / weightSum
        // 0～100 夾住：填 120% 或負數都不該讓最終分數失控
        let clamped = min(max(weighted, 0), 100)
        return PerformanceShare(rank: clamped / 100, votes: votes, isConfigured: true)
    }

    /// [v25.349] 依職等切開的加總結果：職等權重高的排前面（權重相同再比職等名稱），未設職等墊底。
    /// 名次在各自的職等內重新編號——不同職等的人數與權重都不同，混在一起排沒有意義。
    func performanceGradeSections(year: Int, deptId: UUID?) -> [PerformanceGradeSection] {
        performanceGradeSections(scores: performanceScores(year: year), deptId: deptId)
    }

    /// [v25.372] 接收已經算好的分數。performanceScores 現在要掃被標註／兼任／議程三份全庫，
    /// 呼叫端（評分加總頁）同時要用「全部分數」與「切好職等的分組」，
    /// 走這個版本就只算一次，不會在同一次畫面更新裡重跑兩遍。
    func performanceGradeSections(scores input: [PerformanceScore],
                                  deptId: UUID?) -> [PerformanceGradeSection] {
        var scores = input
        if let deptId {
            scores = scores.filter { s in
                subordinates.first(where: { $0.id == s.personId })?.departmentId == deptId
            }
        }
        var buckets: [PerformanceGradeKey: [PerformanceScore]] = [:]
        for s in scores { buckets[PerformanceGradeKey(id: s.gradeId, label: s.gradeLabel), default: []].append(s) }
        return buckets.map { key, items in
            let weight = key.id.flatMap { id in gradeTitles.first(where: { $0.id == id })?.weightValue }
            return PerformanceGradeSection(
                gradeId: key.id,
                label: key.label.isEmpty ? "未設職等" : key.label,
                weight: weight,
                // [v25.372] 名次依最終分數（已含占比加權）排，不再只看排名分數
                scores: items.sorted { a, b in
                    if a.finalScore != b.finalScore { return a.finalScore > b.finalScore }
                    if a.total != b.total { return a.total > b.total }
                    return a.name < b.name
                })
        }
        .sorted { a, b in
            // 未設職等永遠最後
            if (a.gradeId == nil) != (b.gradeId == nil) { return b.gradeId == nil }
            let wa = a.weight ?? 1, wb = b.weight ?? 1
            if wa != wb { return wa > wb }
            return a.label > b.label
        }
    }

    // MARK: - 公司廠區據點（v25.357）

    func upsertCompanySite(_ site: CompanySite) {
        if let i = companySites.firstIndex(where: { $0.id == site.id }) {
            companySites[i] = site
        } else {
            companySites.append(site)
        }
    }

    func deleteCompanySite(id: UUID) {
        companySites.removeAll { $0.id == id }
    }

    /// 全部兼任職務的重大決議（附所屬職務），新到舊
    var allSideRoleResolutions: [(role: LifeMilestone, resolution: SideRoleResolution)] {
        milestones.filter { $0.isSideRole }.flatMap { role in
            (role.sideRoleResolutions ?? []).map { (role: role, resolution: $0) }
        }.sorted { $0.resolution.date > $1.resolution.date }
    }

    /// [v25.358] 依時間把決議掛到據點：一筆決議屬於「啟用年月 <= 決議日期」之中最晚的那個據點。
    /// 不看決議上的廠區文字——A 廠蓋好之後才發生的事，如果那時 B 廠已經啟用，
    /// 該算在 B 廠那個時間點上。沒填啟用年月的據點不參與分期（拿不到時間就無從判斷）。
    struct SiteEraGrouping {
        /// 據點 id → 落在它期間內的決議（新到舊）
        var bySite: [UUID: [(role: LifeMilestone, resolution: SideRoleResolution)]] = [:]
        /// 早於最早一個據點的決議
        var beforeAny: [(role: LifeMilestone, resolution: SideRoleResolution)] = []
        /// 據點 id → 期間結束時間（＝下一個據點的啟用；最後一個為 nil＝至今）
        var eraEnd: [UUID: Date] = [:]
    }

    func groupResolutionsByEra() -> SiteEraGrouping {
        var out = SiteEraGrouping()
        // 依啟用時間由早到晚；沒填年月的不參與分期
        let timeline = companySites
            .compactMap { site -> (site: CompanySite, start: Date)? in
                guard let d = site.startDate else { return nil }
                return (site, d)
            }
            .sorted { $0.start < $1.start }
        guard !timeline.isEmpty else {
            out.beforeAny = allSideRoleResolutions
            return out
        }
        for (i, entry) in timeline.enumerated() where i + 1 < timeline.count {
            out.eraEnd[entry.site.id] = timeline[i + 1].start
        }
        for pair in allSideRoleResolutions {
            let date = pair.resolution.date
            // 找出啟用時間不晚於這筆決議的最後一個據點
            guard let owner = timeline.last(where: { $0.start <= date }) else {
                out.beforeAny.append(pair)
                continue
            }
            out.bySite[owner.site.id, default: []].append(pair)
        }
        return out
    }

    /// 決議上填過、但還沒建成據點的廠區字串。
    /// v25.358 起歸屬看時間不看名字，這份清單只是「照著既有決議把廠區補建起來」的方便入口。
    ///
    /// [v25.461] 只收「第一欄還叫廠區」的職務。v25.460 開放每個兼任職務自訂欄位名稱後，
    /// 那一欄可能已經被改成「活動場地」、「負責單位」之類與廠區無關的東西——
    /// 照樣撈進來的話，這裡會一直提示使用者把那些值「建成廠區據點」，
    /// 而那是個一按下去就產生垃圾資料的建議。
    var unregisteredResolutionSites: [String] {
        let known = Set(companySites.flatMap { $0.matchKeys.map { $0.lowercased() } })
        var seen: Set<String> = []
        var out: [String] = []
        for pair in allSideRoleResolutions {
            let schema = pair.role.sideRoleResolutionSchema ?? SideRoleResolutionSchema()
            guard schema.site == SideRoleResolutionSchema.defaultSiteLabel else { continue }
            let raw = pair.resolution.site.trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty else { continue }
            let key = raw.lowercased()
            guard !known.contains(key), !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(raw)
        }
        return out.sorted()
    }

    // MARK: - 健身紀錄（v25.351）

    /// 自身體重動作的等效負荷：健康檔案最近一次的體重；沒填過就回 nil
    var latestBodyWeightKg: Double? {
        // latestWeight 是具名 tuple，不能用 key path，要自己拆
        guard let w = healthProfile.latestWeight else { return nil }
        return w.kg
    }

    /// 依日期新到舊
    var workoutsByDateDesc: [WorkoutSession] {
        workouts.sorted { $0.date > $1.date }
    }

    func upsertWorkout(_ session: WorkoutSession) {
        if let i = workouts.firstIndex(where: { $0.id == session.id }) {
            workouts[i] = session
        } else {
            workouts.append(session)
        }
    }

    func deleteWorkout(id: UUID) {
        workouts.removeAll { $0.id == id }
    }

    /// [v25.553] 每週目標（公里）：nil＝不設目標。只動這一種運動的，其他種的目標留著
    func setWeeklyGoal(_ km: Double?, for sport: WorkoutSport) {
        var p = workoutPrefs
        p.setGoal(km, for: sport)
        if p != workoutPrefs { workoutPrefs = p }
    }

    /// [v25.553] 看板主角（跑步／健走／騎車／登山／自動）
    func setHeroChoice(_ choice: WorkoutHeroChoice) {
        guard workoutPrefs.heroChoice != choice || workoutPrefs.heroSport == nil else { return }
        var p = workoutPrefs
        p.heroSport = choice.rawValue
        workoutPrefs = p
    }

    /// [v25.554] 這個 Apple 健康編號以後不再帶進來（刪掉手錶那筆、合成、接回路線、只刪 LifeGood 那筆時）
    func ignoreHealthWorkout(_ uuid: String) {
        var l = workoutHealthLedger
        l.ignore(uuid)
        if l != workoutHealthLedger { workoutHealthLedger = l }
    }

    /// [v25.554] 手錶和 App 同一趟：「兩筆都留」（以後不再問這一對）
    func keepWorkoutPair(appId: UUID, watchUUID: String) {
        var l = workoutHealthLedger
        l.keepPair(appId: appId, watchUUID: watchUUID)
        if l != workoutHealthLedger { workoutHealthLedger = l }
    }

    /// [v25.554] 舊紀錄找回路線：「先不要」（以後不再問這一趟）
    func skipRouteRecovery(_ sessionId: UUID) {
        var l = workoutHealthLedger
        l.skipRecovery(sessionId)
        if l != workoutHealthLedger { workoutHealthLedger = l }
    }

    /// [v25.557] 這一天所在的那一週請假（on）或取消請假（off）。呼叫端在選單收起來之後的下一輪主執行緒才叫（不跟收選單搶同一輪）
    func setLeave(_ on: Bool, weekOf date: Date) {
        var b = workoutLeave
        b.set(on, key: WorkoutFacts.leaveKey(weekOf: date))
        if b != workoutLeave { workoutLeave = b }
    }

    /// 出現過的動作名稱（依使用次數多寡），給新增時快速挑選
    func workoutExerciseNames(kind: WorkoutKind? = nil) -> [String] {
        var counts: [String: Int] = [:]
        for s in workouts {
            for e in s.exercises where kind == nil || e.kind == kind {
                let n = e.name.trimmingCharacters(in: .whitespaces)
                guard !n.isEmpty else { continue }
                counts[n, default: 0] += 1
            }
        }
        return counts.sorted { a, b in
            if a.value != b.value { return a.value > b.value }
            return a.key < b.key
        }.map(\.key)
    }

    /// 某個動作的所有紀錄（新到舊），用來畫單一動作的進步曲線
    func workoutHistory(exerciseName: String) -> [(date: Date, exercise: WorkoutExercise)] {
        workouts.flatMap { s in
            s.exercises.filter { $0.name == exerciseName }.map { (date: s.date, exercise: $0) }
        }.sorted { $0.date > $1.date }
    }

    /// 該年度應投票但還沒送出的人（含我）；用來提醒還要催誰
    func performancePendingRaters(year: Int) -> [(id: UUID, name: String)] {
        var out: [(UUID, String)] = []
        let submitted = Set(performanceBallots.filter { $0.year == year && $0.isSubmitted }.map(\.raterId))
        if !submitted.contains(PerformanceBallot.selfRaterId) {
            out.append((PerformanceBallot.selfRaterId, profile.chineseName.isEmpty ? "我" : profile.chineseName))
        }
        for s in subordinates where !submitted.contains(s.id) {
            // 沒有任何可排的組（例如整課只有他一人）就不用投票
            guard !performanceGroups(forRater: s.id).isEmpty else { continue }
            out.append((s.id, s.name.isEmpty ? "未命名" : s.name))
        }
        return out.map { (id: $0.0, name: $0.1) }
    }

    /// 部屬評分所需的整批預算結果。
    ///
    /// 兩份都是 O(全體) 的全量掃描，一次算好往下傳，不讓每一列各自重算
    ///（mentionedCounts 的既有教訓）。打包成一個型別而非兩個平行參數：
    /// 評分因子將來還會增加，每加一個就要動遍所有中間層函式的簽章太脆弱。
    struct ScoreContext {
        var mentions: [UUID: Int] = [:]
        var sideRoles: [UUID: (done: Int, total: Int)] = [:]
        /// [v25.334] 部屬 id → 名下已完成議程項目數（看項目指派給誰）
        var itemCredits: [UUID: Int] = [:]
        func mention(_ id: UUID) -> Int { mentions[id] ?? 0 }
        func sideRoleDone(_ id: UUID) -> Int { sideRoles[id]?.done ?? 0 }
        func sideRoleTotal(_ id: UUID) -> Int { sideRoles[id]?.total ?? 0 }
        func itemDone(_ id: UUID) -> Int { itemCredits[id] ?? 0 }
    }

    func makeScoreContext() -> ScoreContext {
        ScoreContext(mentions: mentionedCounts(), sideRoles: sideRoleTaskCounts(),
                     itemCredits: meetingItemCredits())
    }

    /// [v25.334] 會議議程項目的完成分歸屬（使用者定義）：
    /// 項目有指派負責人 → 計給每位負責人（多人各計一次）；沒指派、或負責人都不是部屬
    ///（外部名片／組織人員）→ 計給會議掛名的負責人。連到兼任待辦的項目跳過（兼任那邊已計分）。
    /// 指派 id 可能是部屬、組織人員（連結部屬）或名片（經組織人員連結部屬），三種都反查回部屬。
    /// 整批一次算好往下傳，比照 mentionedCounts()／sideRoleTaskCounts()。
    func meetingItemCredits() -> [UUID: Int] {
        let subIds = Set(subordinates.map(\.id))
        var viaOrg: [UUID: UUID] = [:]     // orgPerson id → subordinate id
        var viaCard: [UUID: UUID] = [:]    // businessCard id → subordinate id
        for p in orgPeople {
            guard let sid = p.linkedSubordinateId, subIds.contains(sid) else { continue }
            viaOrg[p.id] = sid
            if let cid = p.linkedBusinessCardId { viaCard[cid] = sid }
        }
        func resolve(_ pid: UUID) -> UUID? {
            if subIds.contains(pid) { return pid }
            return viaOrg[pid] ?? viaCard[pid]
        }
        var out: [UUID: Int] = [:]
        for s in subordinates {
            for m in s.meetings {
                for item in m.allItems where item.isCompleted && item.sideRoleLink == nil {
                    let owners = Set(item.assigneeIds.compactMap(resolve))
                    if owners.isEmpty { out[s.id, default: 0] += 1 }
                    else { for id in owners { out[id, default: 0] += 1 } }
                }
            }
        }
        return out
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
            var item = resolution
            // [v25.299] 流水號：沒有就補（同職務內接續最大號；已有則沿用，不重編）
            if item.serial == nil {
                item.serial = (list.compactMap(\.serial).max() ?? 0) + 1
            }
            if let i = list.firstIndex(where: { $0.id == item.id }) { list[i] = item }
            else { list.append(item) }
            // 新到舊：重大決議通常回頭查最近定案的
            m.sideRoleResolutions = list.sorted { $0.date > $1.date }
        }
    }

    /// [v25.299] 一次性遷移：舊有重大決議補流水號（同職務內依日期舊到新編號，
    /// 已有流水號的沿用並從最大號接續）。冪等：沒有缺號直接回 false。
    @discardableResult
    func migrateResolutionSerials() -> Bool {
        var changed = false
        for mi in milestones.indices {
            guard var list = milestones[mi].sideRoleResolutions,
                  list.contains(where: { $0.serial == nil }) else { continue }
            var next = (list.compactMap(\.serial).max() ?? 0) + 1
            // 依日期舊到新補號，讓早期決議拿到小號
            let orderedIds = list.sorted { $0.date < $1.date }.map(\.id)
            for id in orderedIds {
                guard let i = list.firstIndex(where: { $0.id == id }), list[i].serial == nil else { continue }
                list[i].serial = next; next += 1
            }
            milestones[mi].sideRoleResolutions = list
            changed = true
        }
        return changed
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
    /// [v25.389] forcedCompletedAt：打勾時要押的完成時間。nil＝押現在（原本的行為）；
    /// 有值＝壓線補登（逾期確認視窗選「強制準時完成」時傳截止時間進來）。
    /// 取消打勾時一律清成 nil，與這個參數無關。
    func toggleTaskCompletion(subordinateId: UUID, taskId: UUID, forcedCompletedAt: Date? = nil) {
        guard let si = subordinates.firstIndex(where: { $0.id == subordinateId }),
              let ti = subordinates[si].tasks.firstIndex(where: { $0.id == taskId }) else { return }
        // isLoading = true 防止兩次 subscript 寫回各自觸發 didSet → save()，
        // 避免「isCompleted 已翻轉但 completedAt 尚未設定」的中間態被持久化。
        // 用 defer 重置，避免日後在中間加入 guard/return 導致 isLoading 卡死為 true（save() 永久停擺）。
        isLoading = true
        defer { isLoading = false }
        subordinates[si].tasks[ti].isCompleted.toggle()
        subordinates[si].tasks[ti].completedAt =
            subordinates[si].tasks[ti].isCompleted ? (forcedCompletedAt ?? Date()) : nil
        // 這筆若是某則兼任待辦的另一面，兩邊要一起完成（含指派給同一件事的其他人）
        if let back = subordinates[si].tasks[ti].sideRoleLink {
            propagateCompletionToSideRole(back,
                                          isCompleted: subordinates[si].tasks[ti].isCompleted,
                                          completedAt: subordinates[si].tasks[ti].completedAt)
        }
        save()
        // Apple 提醒事項同步（開啟時）；hop 到 MainActor 是 ReminderBridge 的隔離要求
        Task { @MainActor in
            self.syncReminderForSubordinateTask(subordinateId: subordinateId, taskId: taskId)
        }
    }

    /// 切換某場會議底下某個議程項目的完成狀態（部屬詳情頁與總覽頁的打勾共用）。
    /// 標記完成時記下 completedAt，取消完成則清空。
    /// forcedCompletedAt 的意義同 toggleTaskCompletion
    func toggleMeetingItemCompletion(subordinateId: UUID, meetingId: UUID, itemId: UUID,
                                     forcedCompletedAt: Date? = nil) {
        guard let si = subordinates.firstIndex(where: { $0.id == subordinateId }),
              let mi = subordinates[si].meetings.firstIndex(where: { $0.id == meetingId }) else { return }
        // isLoading 阻斷 didSet → save() 的隱式觸發，確保只有下方的顯式 save() 被執行一次
        isLoading = true
        defer { isLoading = false }
        // 有週期的會議，議程項目住在各場次底下；不重複的會議才住在 items。
        // 只找 items 的話，週期會議上的打勾會靜默失效（按了沒反應）。
        var back: SideRoleBackLink?
        var nowCompleted = false
        var nowCompletedAt: Date?
        mutateMeetingItem(&subordinates[si].meetings[mi], itemId: itemId) { item in
            item.isCompleted.toggle()
            item.completedAt = item.isCompleted ? (forcedCompletedAt ?? Date()) : nil
            back = item.sideRoleLink
            nowCompleted = item.isCompleted
            nowCompletedAt = item.completedAt
        }
        // 這個項目若是某則兼任待辦的另一面，兩邊要一起完成（時間也要一致，
        // 不然壓線時間會被 propagate 裡的 Date() 蓋掉）
        if let back {
            propagateCompletionToSideRole(back, isCompleted: nowCompleted,
                                          completedAt: nowCompletedAt)
        }
        save()
    }

    /// 切換某份週報的完成狀態。標記完成時記下 completedAt，取消完成則清空。
    /// forcedCompletedAt 的意義同 toggleTaskCompletion
    func toggleWeeklyReportCompletion(subordinateId: UUID, reportId: UUID,
                                      forcedCompletedAt: Date? = nil) {
        guard let si = subordinates.firstIndex(where: { $0.id == subordinateId }),
              let ri = subordinates[si].weeklyReports.firstIndex(where: { $0.id == reportId }) else { return }
        // isLoading 阻斷 didSet → save() 的隱式觸發，確保只有下方的顯式 save() 被執行一次
        isLoading = true
        defer { isLoading = false }
        subordinates[si].weeklyReports[ri].isCompleted.toggle()
        subordinates[si].weeklyReports[ri].completedAt =
            subordinates[si].weeklyReports[ri].isCompleted ? (forcedCompletedAt ?? Date()) : nil
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

        // [v25.394] 建新的之前，先找有沒有「同名、同部門、而且還沒連到任何部屬」的
        // 既有人員可以認領。
        //
        // ⚠️ 這是重複人員的主要成因：deleteSubordinate 會保留組織人員、只把
        //    linkedSubordinateId 清成 nil（刻意的，人還在公司，只是不再是我的部屬）。
        //    之後同一個人重新被加成部屬時（重新加、從備份還原、或 iCloud 把 subordinates
        //    拉回來），這裡找不到有連結的人員就會再建一個全新的——同一個人兩筆。
        //    subordinates 曾經整批重來過的話（換手機、首次雲端同步），全公司會整批變兩倍。
        if let i = orgPeople.firstIndex(where: {
            $0.linkedSubordinateId == nil
                && $0.departmentId == deptId
                && Self.normalizedPersonName($0.name) == Self.normalizedPersonName(sub.name)
                && !Self.normalizedPersonName($0.name).isEmpty
        }) {
            orgPeople[i].linkedSubordinateId = sub.id
            orgPeople[i].jobTitle = resolvedTitle
            orgPeople[i].gradeTitleId = sub.gradeTitleId
            return
        }

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
        // isLoading 批次保護：底下會動到 equipmentPool 與多位部屬，
        // 不包起來的話每一次 subscript 寫入都各觸發一次 didSet → save() → CloudKit 推送。
        // 用 defer 重置，避免日後在中間加 guard/return 讓旗標卡在 true（save() 永久停擺）。
        isLoading = true
        defer { isLoading = false; save() }
        equipmentPool.removeAll { $0.id == id }
        // [v25.384] 別台機台還指著這台的上下游關係要一起清掉，
        // 不然清單上會出現點不開的鬼影
        for i in equipmentPool.indices {
            equipmentPool[i].upstreamIds.removeAll { $0 == id }
            equipmentPool[i].downstreamIds.removeAll { $0 == id }
        }
        // [v25.391] 任務／報告／會議指著這台的關聯也一併清掉。
        // 顯示端本來就會略過查不到的 id，所以留著不會壞畫面，但會一直累積在存檔與
        // iCloud 同步裡；而且機台一刪，那些關聯在語意上就已經不存在了。
        for i in subordinates.indices {
            for j in subordinates[i].tasks.indices {
                subordinates[i].tasks[j].linkedEquipmentIds.removeAll { $0 == id }
            }
            for j in subordinates[i].weeklyReports.indices {
                subordinates[i].weeklyReports[j].linkedEquipmentIds.removeAll { $0 == id }
            }
            for j in subordinates[i].meetings.indices {
                subordinates[i].meetings[j].linkedEquipmentIds.removeAll { $0 == id }
            }
        }
    }

    // MARK: - [v25.384] 機台上下游

    func equipment(id: UUID) -> ManagedEquipment? {
        equipmentPool.first { $0.id == id }
    }

    /// 建立上下游關係。**兩邊一起寫**：把 other 設成 id 的下游，
    /// 就等於把 id 設成 other 的上游——只寫一邊的話，從另一台點進去會看不到關係。
    /// 這是唯一該改 upstreamIds／downstreamIds 的地方。
    func linkEquipment(_ id: UUID, with otherId: UUID, asDownstream: Bool) {
        guard id != otherId else { return }            // 自己不能是自己的上下游
        guard let a = equipmentPool.firstIndex(where: { $0.id == id }),
              let b = equipmentPool.firstIndex(where: { $0.id == otherId }) else { return }
        isLoading = true
        defer { isLoading = false }
        // 先把兩個方向的舊關係清掉，避免同一對機台同時是上游又是下游
        removeLink(a, b)
        if asDownstream {
            equipmentPool[a].downstreamIds.append(otherId)
            equipmentPool[b].upstreamIds.append(id)
        } else {
            equipmentPool[a].upstreamIds.append(otherId)
            equipmentPool[b].downstreamIds.append(id)
        }
        save()
    }

    /// 解除兩台之間的關係（不分方向）
    func unlinkEquipment(_ id: UUID, from otherId: UUID) {
        guard let a = equipmentPool.firstIndex(where: { $0.id == id }),
              let b = equipmentPool.firstIndex(where: { $0.id == otherId }) else { return }
        isLoading = true
        defer { isLoading = false }
        removeLink(a, b)
        save()
    }

    /// 清掉 a、b 兩台之間所有方向的連結。呼叫端負責 isLoading 與 save。
    private func removeLink(_ a: Int, _ b: Int) {
        let aId = equipmentPool[a].id
        let bId = equipmentPool[b].id
        equipmentPool[a].upstreamIds.removeAll { $0 == bId }
        equipmentPool[a].downstreamIds.removeAll { $0 == bId }
        equipmentPool[b].upstreamIds.removeAll { $0 == aId }
        equipmentPool[b].downstreamIds.removeAll { $0 == aId }
    }

    /// 某台機台的上游／下游清單（已解析成實體，查不到的 id 自動略過）
    func relatedEquipment(of id: UUID, downstream: Bool) -> [ManagedEquipment] {
        guard let eq = equipment(id: id) else { return [] }
        let ids = downstream ? eq.downstreamIds : eq.upstreamIds
        return ids.compactMap { rid in equipmentPool.first { $0.id == rid } }
    }

    /// 還可以被選來當上下游的機台：排除自己與已經連上的
    func equipmentLinkCandidates(for id: UUID) -> [ManagedEquipment] {
        guard let eq = equipment(id: id) else { return [] }
        let taken = Set(eq.upstreamIds + eq.downstreamIds + [id])
        return equipmentPool
            .filter { !taken.contains($0.id) }
            .sorted { ($0.name.isEmpty ? "未命名設備" : $0.name) < ($1.name.isEmpty ? "未命名設備" : $1.name) }
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

    // MARK: - [v25.443] 會議的開會時間

    /// 改這一場的開會時間。
    ///
    /// 不重複的會議直接改 meeting.date；週期會議的某一場改 movedTo——
    /// ⚠️ scheduledDate 必須保持原值，它是「與規則推導結果配對的鍵」，
    ///    改掉的話下次展開規則會對不回這一場，清單上就會多出一場。
    func setMeetingSessionDate(subordinateId: UUID, meetingId: UUID,
                               occurrenceId: UUID?, to newDate: Date) {
        mutateSubordinateMeetingFields(subordinateId: subordinateId, meetingId: meetingId) { m in
            guard let oid = occurrenceId else { m.date = newDate; return }
            guard let i = m.occurrences.firstIndex(where: { $0.id == oid }) else { return }
            if m.occurrences[i].isAdHoc {
                // 臨時加開的場次沒有「原定時間」可言，改 scheduledDate 才符合直覺
                //（否則它會一直顯示成「已改期」，但根本沒有原本的時間可以恢復）
                m.occurrences[i].scheduledDate = newDate
                m.occurrences[i].movedTo = nil
            } else {
                m.occurrences[i].movedTo = newDate
            }
        }
        rebuildMeetingReminders()
    }

    /// 取消改期，回到規則排出來的原定時間
    func restoreMeetingSessionDate(subordinateId: UUID, meetingId: UUID, occurrenceId: UUID) {
        mutateSubordinateMeetingFields(subordinateId: subordinateId, meetingId: meetingId) { m in
            guard let i = m.occurrences.firstIndex(where: { $0.id == occurrenceId }) else { return }
            m.occurrences[i].movedTo = nil
        }
        rebuildMeetingReminders()
    }

    /// [v25.458] 改動開會時間之後把提醒重排一次。
    ///
    /// 這是 v25.455 的漏洞：改期與「另外加開一場」都是走這幾支 mutator（不經過
    /// 會議編輯頁的 save），所以新時間不會進到已排好的提醒裡——要等下次 App 回到
    /// 前景才補上。剛加開一場、而那一場就在不久之後時，提醒就這樣被漏掉了。
    ///
    /// 刻意放在 mutator 裡而不是呼叫端：這三支就是「開會時間變了」的意思，
    /// 日後多一個呼叫端也不會忘記重排。而非時間類的改動（例如打勾完成議程項目）
    /// 不會經過這裡，不必為了那些去重排幾十則通知。
    private func rebuildMeetingReminders() {
        let events = personalEvents
        let subs = subordinates
        let trips = tripPlans
        Task { await ReminderCenter.rebuildAll(events: events, subordinates: subs,
                                               tripPlans: trips) }
    }

    /// 為某一條議程項目「額外召開」一場，並把那一項搬過去。
    ///
    /// 搬而不是複製：同一件事出現在兩場會議上，完成狀態與評分都會算兩次。
    func conveneExtraMeetingSession(subordinateId: UUID, meetingId: UUID,
                                    itemId: UUID, at date: Date) {
        mutateSubordinateMeetingFields(subordinateId: subordinateId, meetingId: meetingId) { m in
            var moved: MeetingItem?
            if let i = m.items.firstIndex(where: { $0.id == itemId }) {
                moved = m.items.remove(at: i)
            } else {
                for oi in m.occurrences.indices {
                    if let i = m.occurrences[oi].items.firstIndex(where: { $0.id == itemId }) {
                        moved = m.occurrences[oi].items.remove(at: i)
                        break
                    }
                }
            }
            guard let moved else { return }
            m.occurrences.append(MeetingOccurrence(scheduledDate: date,
                                                   items: [moved], isAdHoc: true))
        }
        rebuildMeetingReminders()
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

    // MARK: - [v25.394] 公司組織人員重複偵測與合併

    /// 比對用的正規化姓名：去掉前後與中間的空白（含全形），大小寫統一。
    /// 「王小明」與「王 小明」是同一個人。
    static func normalizedPersonName(_ s: String) -> String {
        s.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{3000}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// 一組重複人員（同名、同部門）。keeper 是要留下來的那一筆。
    struct OrgPersonDuplicateGroup: Identifiable {
        let id: String
        let name: String
        let departmentId: UUID?
        let keeper: OrgPerson
        let duplicates: [OrgPerson]
        /// 留下這一筆的理由（顯示在檢查畫面上，讓使用者看得懂而不是盲按）
        let keepReason: String
    }

    /// 這筆人員資料的「豐富度」——合併時用來決定留哪一筆。
    private func orgPersonRichness(_ p: OrgPerson) -> Int {
        var score = 0
        if p.photoFileName != nil { score += 3 }
        if p.birthday != nil { score += 2 }
        if !p.relationship.trimmingCharacters(in: .whitespaces).isEmpty { score += 2 }
        if !p.note.trimmingCharacters(in: .whitespaces).isEmpty { score += 2 }
        score += p.children.count
        score += p.relations.count
        score += p.works.count
        if p.linkedBusinessCardId != nil { score += 1 }
        if p.gradeTitleId != nil { score += 1 }
        return score
    }

    /// 找出同名同部門的重複人員。只比同一個部門內：同名的人被分到兩個部門，
    /// 有可能是真的轉調過，不該自作主張合併。
    func orgPersonDuplicateGroups() -> [OrgPersonDuplicateGroup] {
        var buckets: [String: [OrgPerson]] = [:]
        for p in orgPeople {
            let key = Self.normalizedPersonName(p.name)
            guard !key.isEmpty else { continue }   // 沒名字的不比對，避免全部黏成一坨
            let deptKey = p.departmentId?.uuidString ?? "-"
            buckets[key + "|" + deptKey, default: []].append(p)
        }
        var out: [OrgPersonDuplicateGroup] = []
        for (key, group) in buckets where group.count > 1 {
            // 留哪一筆：① 有連到部屬的（拆掉這條連結會讓部屬同步斷掉）
            //           ② 資料比較完整的　③ 最早建立的
            let sorted = group.sorted { a, b in
                let la = a.linkedSubordinateId != nil, lb = b.linkedSubordinateId != nil
                if la != lb { return la }
                let ra = orgPersonRichness(a), rb = orgPersonRichness(b)
                if ra != rb { return ra > rb }
                return a.dateAdded < b.dateAdded
            }
            guard let keeper = sorted.first else { continue }
            let reason: String
            if keeper.linkedSubordinateId != nil {
                reason = "已連結到部屬資料"
            } else if orgPersonRichness(keeper) > 0 {
                reason = "資料最完整"
            } else {
                reason = "最早建立"
            }
            out.append(OrgPersonDuplicateGroup(
                id: key,
                name: keeper.name.trimmingCharacters(in: .whitespaces),
                departmentId: keeper.departmentId,
                keeper: keeper,
                duplicates: Array(sorted.dropFirst()),
                keepReason: reason))
        }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 某個部門裡「多出來的」人數（重複的份）。0＝沒有重複。
    ///
    /// 這個會在部門頁每次重繪時被呼叫，所以不走 orgPersonDuplicateGroups()——
    /// 那個要排序、要組理由字串，只為了一個數字不值得。
    func orgPersonDuplicateCount(departmentId: UUID?) -> Int {
        var counts: [String: Int] = [:]
        for p in orgPeople where p.departmentId == departmentId {
            let key = Self.normalizedPersonName(p.name)
            guard !key.isEmpty else { continue }
            counts[key, default: 0] += 1
        }
        return counts.values.reduce(0) { $0 + max(0, $1 - 1) }
    }

    /// 合併重複人員：把要刪掉那幾筆身上「keeper 沒有的東西」搬過去，
    /// 再把所有指向它們的參照改指到 keeper，最後才移除。
    ///
    /// ⚠️ 刻意不走 deleteOrgPerson：那個方法會刪照片檔與生日行事曆事件，
    ///    但這裡的照片／事件可能剛剛才被 keeper 接收過去，刪掉就變成空頭參照。
    @discardableResult
    func mergeOrgPersonDuplicates(_ groups: [OrgPersonDuplicateGroup]) -> Int {
        guard !groups.isEmpty else { return 0 }
        isLoading = true
        defer { isLoading = false; save() }

        var removed = 0
        for group in groups {
            guard let ki = orgPeople.firstIndex(where: { $0.id == group.keeper.id }) else { continue }
            var keeper = orgPeople[ki]
            for dup in group.duplicates {
                guard dup.id != keeper.id else { continue }
                // ① 補齊 keeper 缺的欄位（有值的不覆蓋）
                if keeper.photoFileName == nil { keeper.photoFileName = dup.photoFileName }
                if keeper.birthday == nil {
                    keeper.birthday = dup.birthday
                    keeper.birthdayEventId = dup.birthdayEventId
                }
                if keeper.relationship.trimmingCharacters(in: .whitespaces).isEmpty {
                    keeper.relationship = dup.relationship
                }
                if keeper.jobTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                    keeper.jobTitle = dup.jobTitle
                }
                if keeper.gradeTitleId == nil { keeper.gradeTitleId = dup.gradeTitleId }
                if keeper.linkedBusinessCardId == nil {
                    keeper.linkedBusinessCardId = dup.linkedBusinessCardId
                }
                if keeper.linkedSubordinateId == nil {
                    keeper.linkedSubordinateId = dup.linkedSubordinateId
                }
                // 備註兩邊都有就接起來，不要丟掉任何一邊寫過的字
                let dupNote = dup.note.trimmingCharacters(in: .whitespacesAndNewlines)
                if !dupNote.isEmpty && !keeper.note.contains(dupNote) {
                    keeper.note = keeper.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? dupNote : keeper.note + "\n" + dupNote
                }
                // ② 子項目照 id 併入
                let childIds = Set(keeper.children.map(\.id))
                keeper.children.append(contentsOf: dup.children.filter { !childIds.contains($0.id) })
                let workIds = Set(keeper.works.map(\.id))
                keeper.works.append(contentsOf: dup.works.filter { !workIds.contains($0.id) })
                // 人際關係依「對象」去重，不是依 relation 自己的 id——
                // 兩筆重複人員對同一個人各記一筆，合併後會變成同一個人出現兩次
                var relTargets = Set(keeper.relations.map(\.personId))
                for r in dup.relations where !relTargets.contains(r.personId) && r.personId != keeper.id {
                    keeper.relations.append(r)
                    relTargets.insert(r.personId)
                }

                // ③ 把指向 dup 的參照改指 keeper
                //
                // ⚠️ keeper 的本地副本要自己改一次。下面那個迴圈掃的是 orgPeople 陣列，
                //    keeper 在陣列上那一格確實會被改到，但這個函式最後是用本地副本
                //    `keeper` 寫回去的——不同步改的話，剛改好的值會被舊值蓋回來。
                for j in keeper.relations.indices where keeper.relations[j].personId == dup.id {
                    keeper.relations[j].personId = keeper.id
                }
                for i in orgPeople.indices {
                    for j in orgPeople[i].relations.indices
                    where orgPeople[i].relations[j].personId == dup.id {
                        orgPeople[i].relations[j].personId = keeper.id
                    }
                }
                for i in departments.indices where departments[i].managerIds.contains(dup.id) {
                    departments[i].managerIds.removeAll { $0 == dup.id }
                    if !departments[i].managerIds.contains(keeper.id) {
                        departments[i].managerIds.append(keeper.id)
                    }
                }
                for i in businessCards.indices where businessCards[i].linkedOrgPersonId == dup.id {
                    businessCards[i].linkedOrgPersonId = keeper.id
                }
                // ④ dup 的照片若沒被 keeper 接收才刪，否則會把剛接過去的檔案刪掉
                if let name = dup.photoFileName, keeper.photoFileName != name {
                    OrgPerson.deletePhoto(name)
                }
                orgPeople.removeAll { $0.id == dup.id }
                removed += 1
            }
            // keeper 可能已經因為上面的 removeAll 換了位置，重新定位再寫回
            if let idx = orgPeople.firstIndex(where: { $0.id == keeper.id }) {
                orgPeople[idx] = keeper
            }
            // 自己不該是自己的關係人
            if let idx = orgPeople.firstIndex(where: { $0.id == keeper.id }) {
                orgPeople[idx].relations.removeAll { $0.personId == keeper.id }
            }
        }
        return removed
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

    // MARK: - 名片重複檢查與合併（v25.400）

    /// 一組可能重複的名片。keeper 是建議留下來的那一張。
    struct BusinessCardDuplicateGroup: Identifiable {
        let id: String
        let name: String
        let company: String
        let keeper: BusinessCard
        let duplicates: [BusinessCard]
        /// 建議留這一張的理由（顯示在檢查畫面上，讓使用者看得懂而不是盲按）
        let keepReason: String
    }

    /// 合併做了什麼的回報。刻意連「放棄了什麼」也回報——
    /// 一張名片只能連一位組織人員，兩張都連了不同人時一定得放棄一條，
    /// 那件事必須讓使用者知道，不能無聲無息地掉。
    struct BusinessCardMergeReport {
        var mergedCount = 0
        var orgPeopleRelinked = 0
        var meetingAssigneesRemapped = 0
        var sideRoleMembersRemapped = 0
        var sideRoleMembersCleared = 0
        var droppedPersonLinks: [String] = []
    }

    /// 名片的「豐富度」——合併時用來決定留哪一張。
    private func businessCardRichness(_ c: BusinessCard) -> Int {
        var score = 0
        if c.photoFileName != nil { score += 3 }
        if c.linkedOrgPersonId != nil { score += 2 }
        score += c.phones.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        score += c.emails.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        score += c.faxes.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        if !c.note.trimmingCharacters(in: .whitespaces).isEmpty { score += 2 }
        if !c.address.trimmingCharacters(in: .whitespaces).isEmpty { score += 1 }
        if !c.primaryBusiness.trimmingCharacters(in: .whitespaces).isEmpty { score += 1 }
        if !c.jobTitle.trimmingCharacters(in: .whitespaces).isEmpty { score += 1 }
        if !c.department.trimmingCharacters(in: .whitespaces).isEmpty { score += 1 }
        return score
    }

    /// 找出「同名同公司」的重複名片。
    ///
    /// ⚠️ 刻意把公司也算進比對鍵：同名但在兩家公司，多半是兩個不同的人；
    ///    就算真的是同一個人換了工作，舊公司那張名片本身就是一段歷史，
    ///    合併掉等於把它抹掉。跨公司的同名一律不視為重複（比照
    ///    orgPersonDuplicateGroups() 只比同部門的道理）。
    func businessCardDuplicateGroups() -> [BusinessCardDuplicateGroup] {
        var buckets: [String: [BusinessCard]] = [:]
        for c in businessCards {
            let nameKey = Self.normalizedPersonName(c.name)
            guard !nameKey.isEmpty else { continue }   // 沒名字的不比對，避免全部黏成一坨
            let companyKey = Self.normalizedPersonName(c.company)
            buckets[nameKey + "|" + companyKey, default: []].append(c)
        }
        var out: [BusinessCardDuplicateGroup] = []
        for (key, group) in buckets where group.count > 1 {
            // 留哪一張：① 有連到組織人員的（拆掉這條連結會讓雙向同步斷掉）
            //           ② 資料比較完整的　③ 最早建立的
            let sorted = group.sorted { a, b in
                let la = a.linkedOrgPersonId != nil, lb = b.linkedOrgPersonId != nil
                if la != lb { return la }
                let ra = businessCardRichness(a), rb = businessCardRichness(b)
                if ra != rb { return ra > rb }
                return a.date < b.date
            }
            guard let keeper = sorted.first else { continue }
            let reason: String
            if keeper.linkedOrgPersonId != nil {
                reason = "已連結公司組織人員"
            } else if businessCardRichness(keeper) > 0 {
                reason = "資料最完整"
            } else {
                reason = "最早建立"
            }
            out.append(BusinessCardDuplicateGroup(
                id: key,
                name: keeper.name.trimmingCharacters(in: .whitespaces),
                company: keeper.company.trimmingCharacters(in: .whitespaces),
                keeper: keeper,
                duplicates: Array(sorted.dropFirst()),
                keepReason: reason))
        }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 重複出來的張數（不是組數）。0＝沒有重複。
    ///
    /// 名片頁每次重繪都會問這個，所以不走 businessCardDuplicateGroups()——
    /// 那個要排序、要組理由字串，只為了一個數字不值得。
    func businessCardDuplicateCount() -> Int {
        var counts: [String: Int] = [:]
        for c in businessCards {
            let nameKey = Self.normalizedPersonName(c.name)
            guard !nameKey.isEmpty else { continue }
            counts[nameKey + "|" + Self.normalizedPersonName(c.company), default: 0] += 1
        }
        return counts.values.reduce(0) { $0 + max(0, $1 - 1) }
    }

    /// 這幾張名片裡建議留哪一張（與重複檢查用的是同一套排序）。
    /// 給多選合併畫面當預設值用——使用者還是可以自己改。
    func suggestedBusinessCardKeeper(among ids: [UUID]) -> UUID? {
        let cards = businessCards.filter { ids.contains($0.id) }
        return cards.sorted { a, b in
            let la = a.linkedOrgPersonId != nil, lb = b.linkedOrgPersonId != nil
            if la != lb { return la }
            let ra = businessCardRichness(a), rb = businessCardRichness(b)
            if ra != rb { return ra > rb }
            return a.date < b.date
        }.first?.id
    }

    /// 合併名片：把被併掉那幾張身上「keeper 沒有的東西」搬過去，
    /// 再把所有指向它們的參照改指到 keeper，最後才移除。
    @discardableResult
    func mergeBusinessCards(keepId: UUID, absorbIds: [UUID]) -> BusinessCardMergeReport {
        isLoading = true
        defer { isLoading = false; save() }
        var report = BusinessCardMergeReport()
        performBusinessCardMerge(keepId: keepId, absorbIds: absorbIds, into: &report)
        return report
    }

    /// 一次合併多組（重複檢查畫面用）。
    @discardableResult
    func mergeBusinessCardDuplicates(_ groups: [BusinessCardDuplicateGroup]) -> BusinessCardMergeReport {
        guard !groups.isEmpty else { return BusinessCardMergeReport() }
        isLoading = true
        defer { isLoading = false; save() }
        var report = BusinessCardMergeReport()
        for g in groups {
            performBusinessCardMerge(keepId: g.keeper.id,
                                     absorbIds: g.duplicates.map(\.id), into: &report)
        }
        return report
    }

    /// 合併的本體。
    ///
    /// ⚠️ 刻意**不**走 deleteBusinessCard，那個方法對合併來說是壞的：
    ///    ① 它無條件刪掉 photoFileName 的檔案。keeper 沒照片時合併會把被併那張的
    ///       照片接手過去，檔名不變（photoURL 只是把存的名字接到目錄後面，不需要改名），
    ///       接著刪掉就把剛接手的檔案連 iCloud 一起刪了，keeper 只剩空頭檔名。
    ///    ② 它把組織人員的 linkedBusinessCardId 設成 nil。合併要的是「改指到 keeper」，
    ///       設成 nil 等於把這次要保住的關聯弄丟，而且只處理它自己記著的那一位，
    ///       別人身上指過來的連結會留成懸空 id。
    ///    ③ 它自己會 isLoading = true / defer { isLoading = false } 再 save()，
    ///       包在外層的批次守衛裡會被它的 defer 提早關掉，變成每併一張存一次。
    ///
    /// ⚠️ 也**不**依賴 repairSideRoleMemberLinks()：那個只把名片 id 換成部屬 id，
    ///    而且只在啟動與雲端重載時跑，這裡的改名換 id 它看不到。
    private func performBusinessCardMerge(keepId: UUID, absorbIds: [UUID],
                                          into report: inout BusinessCardMergeReport) {
        guard let ki = businessCards.firstIndex(where: { $0.id == keepId }) else { return }
        // 先把被併的那幾張抓成值：迴圈裡會一邊移除，索引會跑掉
        let losers = absorbIds.filter { $0 != keepId }
            .compactMap { id in businessCards.first(where: { $0.id == id }) }
        guard !losers.isEmpty else { return }

        var keeper = businessCards[ki]
        for loser in losers {
            let loserId = loser.id, keeperId = keeper.id

            // ① 欄位：keeper 空的才補，有值的一律不覆蓋
            if keeper.name.trimmingCharacters(in: .whitespaces).isEmpty { keeper.name = loser.name }
            if keeper.company.trimmingCharacters(in: .whitespaces).isEmpty { keeper.company = loser.company }
            if keeper.department.trimmingCharacters(in: .whitespaces).isEmpty { keeper.department = loser.department }
            if keeper.jobTitle.trimmingCharacters(in: .whitespaces).isEmpty { keeper.jobTitle = loser.jobTitle }
            if keeper.address.trimmingCharacters(in: .whitespaces).isEmpty { keeper.address = loser.address }
            if keeper.primaryBusiness.trimmingCharacters(in: .whitespaces).isEmpty {
                keeper.primaryBusiness = loser.primaryBusiness
            }
            // 電話／Email／傳真是多筆，合併後併集去重：兩張名片各記一支電話是
            // 重複名片最常見的樣子，只取一邊等於把另一支丟掉
            keeper.phones = Self.mergedContactList(keeper.phones, loser.phones)
            keeper.emails = Self.mergedContactList(keeper.emails, loser.emails)
            keeper.faxes = Self.mergedContactList(keeper.faxes, loser.faxes)
            // 備註兩邊都有就接起來，不要丟掉任何一邊寫過的字
            let loserNote = loser.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !loserNote.isEmpty && !keeper.note.contains(loserNote) {
                keeper.note = keeper.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? loserNote : keeper.note + "\n" + loserNote
            }
            // 日期取較早的那個：這欄是「拿到名片的日子」，先認識的那次才是真的
            if loser.date < keeper.date { keeper.date = loser.date }
            if keeper.photoFileName == nil { keeper.photoFileName = loser.photoFileName }

            // ② 組織人員連結：改指到 keeper，不是設成 nil
            //
            // 掃全表而不是只看 loser.linkedOrgPersonId——那一欄可能是 nil 或過期的，
            // 但人員身上指過來的連結還在，漏掉就留下懸空 id。
            var keeperPersonId = keeper.linkedOrgPersonId
            for i in orgPeople.indices where orgPeople[i].linkedBusinessCardId == loserId {
                if keeperPersonId == nil || keeperPersonId == orgPeople[i].id {
                    orgPeople[i].linkedBusinessCardId = keeperId
                    keeperPersonId = orgPeople[i].id
                    report.orgPeopleRelinked += 1
                } else {
                    // 留下的名片已經連到另一位人員。一張名片只能對一位，
                    // 所以這條只能放棄——但要記下來回報，不能無聲無息地掉。
                    orgPeople[i].linkedBusinessCardId = nil
                    report.droppedPersonLinks.append(
                        orgPeople[i].name.trimmingCharacters(in: .whitespaces))
                }
            }
            // loser 自己記著的人員（反向連結沒建好的情況）：對方還沒被別張名片佔走才接手
            if keeperPersonId == nil, let pid = loser.linkedOrgPersonId,
               let pi = orgPeople.firstIndex(where: { $0.id == pid }),
               orgPeople[pi].linkedBusinessCardId == nil {
                orgPeople[pi].linkedBusinessCardId = keeperId
                keeperPersonId = pid
                report.orgPeopleRelinked += 1
            }
            keeper.linkedOrgPersonId = keeperPersonId

            // ③ 會議議程項目的負責人：改指，不是移除
            //
            // deleteSubordinate 走的是 removeAll（那邊人真的走了），合併不能照抄——
            // 移除等於把「這件事是誰負責的」弄掉，是有損的。
            // 兩張名片同時被指派到同一個項目時，改指後要去重，否則同一人列兩次。
            for si in subordinates.indices {
                for mi in subordinates[si].meetings.indices {
                    for ii in subordinates[si].meetings[mi].items.indices {
                        if Self.remapAssignee(&subordinates[si].meetings[mi].items[ii].assigneeIds,
                                              from: loserId, to: keeperId) {
                            report.meetingAssigneesRemapped += 1
                        }
                    }
                    // 週期性會議的每一次開會各存一份議程，兩邊都要掃
                    for oi in subordinates[si].meetings[mi].occurrences.indices {
                        for ii in subordinates[si].meetings[mi].occurrences[oi].items.indices {
                            if Self.remapAssignee(&subordinates[si].meetings[mi]
                                                    .occurrences[oi].items[ii].assigneeIds,
                                                  from: loserId, to: keeperId) {
                                report.meetingAssigneesRemapped += 1
                            }
                        }
                    }
                }
            }

            // ④ 兼任職務成員的 linkedPersonId
            //
            // 同一個職務裡已經有人指向 keeper 時，把這筆的連結清成 nil 就好，
            // 不要製造兩列指向同一個人；成員那一列本身不刪——name／contact／dutyInRole
            // 都是使用者自己編過的快照（比照 repairSideRoleMemberLinks 的既有做法）。
            for i in milestones.indices {
                guard var members = milestones[i].sideRoleMembers,
                      members.contains(where: { $0.linkedPersonId == loserId }) else { continue }
                for j in members.indices where members[j].linkedPersonId == loserId {
                    if members.contains(where: { $0.linkedPersonId == keeperId }) {
                        members[j].linkedPersonId = nil
                        report.sideRoleMembersCleared += 1
                    } else {
                        members[j].linkedPersonId = keeperId
                        report.sideRoleMembersRemapped += 1
                    }
                }
                milestones[i].sideRoleMembers = members
            }

            // ⑤ 照片：keeper 沒接手才刪，否則會把剛交出去的檔案連 iCloud 一起刪掉
            if let name = loser.photoFileName, keeper.photoFileName != name {
                BusinessCard.deletePhoto(name)
            }

            // ⑥ 移除被併掉的那張
            businessCards.removeAll { $0.id == loserId }
            report.mergedCount += 1
        }
        // keeper 可能因為上面的 removeAll 換了位置，重新定位再寫回
        if let idx = businessCards.firstIndex(where: { $0.id == keeper.id }) {
            businessCards[idx] = keeper
        }
    }

    /// 把一份負責人清單裡的 loser 換成 keeper 並去重；回傳有沒有改到。
    /// 兩張名片同時被指派到同一個項目時，不去重會讓同一個人列兩次。
    private static func remapAssignee(_ ids: inout [UUID],
                                      from loserId: UUID, to keeperId: UUID) -> Bool {
        guard ids.contains(loserId) else { return false }
        var seen = Set<UUID>()
        var out: [UUID] = []
        for id in ids {
            let mapped = (id == loserId) ? keeperId : id
            if seen.insert(mapped).inserted { out.append(mapped) }
        }
        ids = out
        return true
    }

    /// 兩份多值聯絡資料的併集（去空白、去重複，保留原有順序）。
    static func mergedContactList(_ a: [String], _ b: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for v in a + b {
            let t = v.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            // 比對時去掉分隔符號：02-1234-5678 與 0212345678 是同一支
            let key = t.filter { !" -()".contains($0) }
            if seen.insert(key.isEmpty ? t : key).inserted { out.append(t) }
        }
        return out
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

    // MARK: - [v25.399] 旅遊規劃 CRUD

    func upsertTripPlan(_ plan: TripPlan) {
        if let i = tripPlans.firstIndex(where: { $0.id == plan.id }) { tripPlans[i] = plan }
        else { tripPlans.append(plan) }
    }

    func deleteTripPlan(id: UUID) {
        // 照片是實體檔案，跟著行程一起刪；只清陣列會留下孤兒檔，
        // 而且 CloudKit 的照片同步會一直把它們當成「還沒上傳的本機照片」重傳
        //（同 deleteOrgPerson／deleteBusinessCard 的既有寫法）
        if let plan = tripPlans.first(where: { $0.id == id }) {
            for stop in plan.stops {
                for name in stop.photoFileNames { TripStop.deletePhoto(name) }
            }
        }
        tripPlans.removeAll { $0.id == id }
    }

    func tripPlan(id: UUID) -> TripPlan? {
        tripPlans.first { $0.id == id }
    }

    // MARK: - 旅遊期間（v25.470）

    /// 使用者設定：旅遊期間不顯示／不提醒部屬會議（代理人會處理）。預設開。
    static let hideMeetingsDuringTripKey = "hide_meetings_during_trip"

    static var hideMeetingsDuringTrip: Bool {
        // 沒設定過的裝置要回 true；UserDefaults.bool 對不存在的 key 回 false，
        // 直接用會讓預設變成「關」。
        UserDefaults.standard.object(forKey: hideMeetingsDuringTripKey) as? Bool ?? true
    }

    /// 這一天落在哪一趟旅遊的期間內（沒有就回 nil）。
    /// 判斷規則與記帳表單的「關聯旅遊」選單一致：以「天」比對起訖日。
    func tripPlan(covering date: Date) -> TripPlan? {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        return tripPlans.first { plan in
            let from = cal.startOfDay(for: plan.startDate)
            let to = cal.startOfDay(for: plan.endDate)
            return day >= from && day <= to
        }
    }

    /// 這一天要不要把部屬會議藏起來。
    ///
    /// 只管部屬會議——使用者的原話是「我的代理人會幫我處理」，那指的是部屬那一側的
    /// 會議。我的行事曆的個人事件、系統行事曆的事件不受影響：那些是自己的事，
    /// 旅行中照樣該看得到。
    func hidesMeetings(on date: Date) -> Bool {
        Self.hideMeetingsDuringTrip && tripPlan(covering: date) != nil
    }

    /// 刪掉某一站，連帶清掉它的照片，並讓「下一站」的路線快取失效
    ///（前一站換人了，那段路就不是原來那段）。
    func deleteTripStop(planId: UUID, stopId: UUID) {
        guard let pi = tripPlans.firstIndex(where: { $0.id == planId }),
              let si = tripPlans[pi].stops.firstIndex(where: { $0.id == stopId }) else { return }
        for name in tripPlans[pi].stops[si].photoFileNames { TripStop.deletePhoto(name) }
        tripPlans[pi].stops.remove(at: si)
        invalidateLeg(planIndex: pi, at: si)
    }

    /// 搬動站的順序。搬完之後受影響的段落快取要作廢。
    func moveTripStops(planId: UUID, from source: IndexSet, to destination: Int) {
        guard let pi = tripPlans.firstIndex(where: { $0.id == planId }) else { return }
        tripPlans[pi].stops.move(fromOffsets: source, toOffset: destination)
        // 搬動會讓「哪一站接在哪一站後面」整批改變，逐段比指紋成本比猜哪幾段變了低，
        // 所以直接全部作廢，讓路線計算自己重跑（它本來就只算指紋對不上的段落）。
        for i in tripPlans[pi].stops.indices {
            tripPlans[pi].stops[i].legStamp = nil
        }
    }

    // MARK: 現場打卡（v25.421）

    /// 打卡：沒到 →（按一下）我到了 →（再按一下）玩完了 →（再按一下）回到沒到。
    ///
    /// 一顆按鈕走完三個狀態而不是分兩顆：當天站在景點門口，畫面上按鈕愈少愈好。
    /// 按過頭就再按一圈回來，不必找「重設」藏在哪裡。
    func advanceTripStopCheckIn(planId: UUID, stopId: UUID, now: Date = Date()) {
        guard let pi = tripPlans.firstIndex(where: { $0.id == planId }),
              let si = tripPlans[pi].stops.firstIndex(where: { $0.id == stopId }) else { return }
        switch tripPlans[pi].stops[si].checkInState {
        case .notArrived:
            tripPlans[pi].stops[si].actualArrival = now
        case .arrived:
            // 離開時間不能早於抵達時間（連按兩下的話會是同一秒，這裡至少讓它是 0 分）
            let arrival = tripPlans[pi].stops[si].actualArrival ?? now
            tripPlans[pi].stops[si].actualDeparture = max(now, arrival)
        case .departed:
            tripPlans[pi].stops[si].actualArrival = nil
            tripPlans[pi].stops[si].actualDeparture = nil
        }
    }

    /// 換掉某一站的照片清單（景點卡直接加減照片時用）
    /// [v25.519] 刪掉的剛好是封面那張的話，TripStop.photoFileNames 的 didSet 會把封面退回自動
    func updateTripStopPhotos(planId: UUID, stopId: UUID, fileNames: [String]) {
        guard let pi = tripPlans.firstIndex(where: { $0.id == planId }),
              let si = tripPlans[pi].stops.firstIndex(where: { $0.id == stopId }),
              tripPlans[pi].stops[si].photoFileNames != fileNames else { return }
        tripPlans[pi].stops[si].photoFileNames = fileNames
    }

    /// [v25.519] 換某一站的封面（自動／某一張照片／衛星空照）。
    ///
    /// 跟 toggleTripStopMustVisit 一樣就地改那一站（等於拿最新的那份來改），
    /// 不帶整份行程的快照去 upsert——那樣會蓋掉別處剛做的改動。
    /// 指定的照片不在這一站的照片裡（剛被刪掉）就不設：不留一個指向不存在照片的封面。
    func setTripStopCover(planId: UUID, stopId: UUID, cover: TripStopCover) {
        // 使用者明確選了一個：還在背景跑的「從相簿加一張當封面」寫回時只加照片、不再改封面
        // （見 coverImportTokens）。放在最前面：選的跟現在一樣、提早 return 的情況也算數。
        coverImportTokens[stopId] = nil
        guard let pi = tripPlans.firstIndex(where: { $0.id == planId }),
              let si = tripPlans[pi].stops.firstIndex(where: { $0.id == stopId }) else { return }
        if case .photo(let name) = cover,
           !tripPlans[pi].stops[si].photoFileNames.contains(name) { return }
        guard tripPlans[pi].stops[si].cover != cover else { return }
        tripPlans[pi].stops[si].cover = cover
    }

    /// [v25.519] 「從相簿加一張當封面」還在背景匯入的那一批：stopId → 那一批的記號。
    ///
    /// 匯入要等 iCloud 原圖下載（加上匯入中心前面排著的別批），可能好幾十秒；畫面上還寫著
    /// 「可以先離開這個畫面」，這段時間使用者可能又點了「自動」、另一張照片，或從長按選單「改回自動」。
    /// 匯入寫回時記號已經對不上，就只把照片加進去、不動封面：**後來的明確選擇優先**。
    /// 只活在這次啟動，不存檔、不同步（App 被關掉，匯入本來就跟著沒了）。
    private var coverImportTokens: [UUID: UUID] = [:]

    /// [v25.519] 開始一批「從相簿加一張當封面」。回傳這一批的記號，匯入完成時帶回 addTripStopCoverPhotos。
    /// 同一站連選兩次相簿，第二次會換掉記號：第一批只加照片，第二批才設封面。
    func beginTripStopCoverImport(stopId: UUID) -> UUID {
        let token = UUID()
        coverImportTokens[stopId] = token
        return token
    }

    /// [v25.519] 「從相簿加一張當封面」匯入完成：照片加進這一站；這一批還是最後一次要求的話，
    /// 第一張同時設成封面——**一次寫入**（tripPlans 的 didSet 每改一次就存一次檔、推一次 iCloud，分兩步就是兩次）。
    ///
    /// 記號對不上（匯入期間使用者自己選了封面，或又從相簿選了另一批）：照片照樣加進去
    /// （使用者確實選了這張，不能丟），封面不動。
    ///
    /// - Parameter fileNames: 空的（讀圖或存檔失敗）也要交回來，這一批的記號才會收掉。
    /// - Returns: false＝那一站已經不在了（匯入期間被刪掉），呼叫端要把剛寫好的檔案刪掉，不留孤兒檔。
    @discardableResult
    func addTripStopCoverPhotos(planId: UUID, stopId: UUID, fileNames: [String], token: UUID) -> Bool {
        // 不管成不成，這一批都結束了。記號對得上才收掉：對不上＝後面還有一批，或使用者已經自己選了
        let isLatest = coverImportTokens[stopId] == token
        if isLatest { coverImportTokens[stopId] = nil }
        guard let first = fileNames.first else { return true }
        guard let pi = tripPlans.firstIndex(where: { $0.id == planId }),
              let si = tripPlans[pi].stops.firstIndex(where: { $0.id == stopId }) else { return false }
        var stop = tripPlans[pi].stops[si]
        for name in fileNames where !stop.photoFileNames.contains(name) {
            stop.photoFileNames.append(name)
        }
        if isLatest { stop.cover = .photo(first) }
        tripPlans[pi].stops[si] = stop
        return true
    }

    /// 直接把打卡時間設成指定值（景點卡上直接選狀態時用）。
    /// departure 傳 nil＝收回「已離開」，人還在那一站。
    func setTripStopCheckIn(planId: UUID, stopId: UUID,
                            arrival: Date?, departure: Date?) {
        guard let pi = tripPlans.firstIndex(where: { $0.id == planId }),
              let si = tripPlans[pi].stops.firstIndex(where: { $0.id == stopId }) else { return }
        tripPlans[pi].stops[si].actualArrival = arrival
        // 離開不能早於抵達，否則停留時間會是負的
        if let d = departure, let a = arrival {
            tripPlans[pi].stops[si].actualDeparture = max(d, a)
        } else {
            tripPlans[pi].stops[si].actualDeparture = departure
        }
    }

    /// 清掉某一站的打卡紀錄
    func clearTripStopCheckIn(planId: UUID, stopId: UUID) {
        guard let pi = tripPlans.firstIndex(where: { $0.id == planId }),
              let si = tripPlans[pi].stops.firstIndex(where: { $0.id == stopId }) else { return }
        tripPlans[pi].stops[si].actualArrival = nil
        tripPlans[pi].stops[si].actualDeparture = nil
    }

    /// 把某一站的實際停留時間寫回「預計停留」。
    /// 當天玩完之後可以用它把計畫校正成真實的樣子，下次照抄就準了。
    func adoptActualDwell(planId: UUID, stopId: UUID) {
        guard let pi = tripPlans.firstIndex(where: { $0.id == planId }),
              let si = tripPlans[pi].stops.firstIndex(where: { $0.id == stopId }),
              let seconds = tripPlans[pi].stops[si].actualDwellSeconds else { return }
        tripPlans[pi].stops[si].dwellMinutes = max(0, Int((seconds / 60).rounded()))
    }

    // MARK: - [v25.451] 行前準備清單

    /// 兩份清單共用同一組 CRUD——它們的操作完全一樣，差別只在存在哪個欄位。
    /// 分成兩套函式只會是同一段程式碼寫兩遍。
    private func mutateChecklist(planId: UUID, kind: TripChecklistKind,
                                 _ body: (inout [TripChecklistItem]) -> Void) {
        guard let pi = tripPlans.firstIndex(where: { $0.id == planId }) else { return }
        switch kind {
        case .packing: body(&tripPlans[pi].packingItems)
        case .souvenir: body(&tripPlans[pi].souvenirItems)
        }
    }

    func addTripChecklistItem(planId: UUID, kind: TripChecklistKind,
                              _ item: TripChecklistItem) {
        mutateChecklist(planId: planId, kind: kind) { $0.append(item) }
    }

    func updateTripChecklistItem(planId: UUID, kind: TripChecklistKind,
                                 _ item: TripChecklistItem) {
        mutateChecklist(planId: planId, kind: kind) { list in
            guard let i = list.firstIndex(where: { $0.id == item.id }) else { return }
            list[i] = item
        }
    }

    func toggleTripChecklistItem(planId: UUID, kind: TripChecklistKind, itemId: UUID) {
        mutateChecklist(planId: planId, kind: kind) { list in
            guard let i = list.firstIndex(where: { $0.id == itemId }) else { return }
            list[i].isDone.toggle()
        }
    }

    func deleteTripChecklistItem(planId: UUID, kind: TripChecklistKind, itemId: UUID) {
        mutateChecklist(planId: planId, kind: kind) { $0.removeAll { $0.id == itemId } }
    }

    func moveTripChecklistItems(planId: UUID, kind: TripChecklistKind,
                                from source: IndexSet, to destination: Int) {
        mutateChecklist(planId: planId, kind: kind) { $0.move(fromOffsets: source, toOffset: destination) }
    }

    /// 把已經打勾的整批清掉（回程整理用）
    func clearDoneTripChecklistItems(planId: UUID, kind: TripChecklistKind) {
        mutateChecklist(planId: planId, kind: kind) { $0.removeAll(where: \.isDone) }
    }

    /// [v25.435] 切換某一站的「必去」。
    ///
    /// 抽到 store 來的理由：時間軸的「…」選單與景點卡上的星星鈕都要做同一件事，
    /// 各寫一份就會有兩種讀寫方式（一個整份 upsert、一個改陣列），
    /// 哪天加了副作用只會改到其中一邊。
    func toggleTripStopMustVisit(planId: UUID, stopId: UUID) {
        guard let pi = tripPlans.firstIndex(where: { $0.id == planId }),
              let si = tripPlans[pi].stops.firstIndex(where: { $0.id == stopId }) else { return }
        tripPlans[pi].stops[si].isMustVisit.toggle()
    }

    /// 把真實路線的結果寫回某一段。
    ///
    /// 用「目的地那一站的 id」定位而不是索引：算路線是非同步的，回來的時候
    /// 使用者可能已經搬過站的順序，用索引寫會寫到別段去。
    func applyTripRoute(planId: UUID, stopId: UUID, meters: Double, seconds: Double) {
        guard let pi = tripPlans.firstIndex(where: { $0.id == planId }),
              let si = tripPlans[pi].stops.firstIndex(where: { $0.id == stopId }),
              si > 0 else { return }
        var plan = tripPlans[pi]
        if plan.applyRoute(meters: meters, seconds: seconds, at: si) {
            tripPlans[pi] = plan
        }
    }

    /// 讓某一段重新計算路線（使用者按「重新計算」時用）
    func invalidateTripLeg(planId: UUID, stopId: UUID) {
        guard let pi = tripPlans.firstIndex(where: { $0.id == planId }),
              let si = tripPlans[pi].stops.firstIndex(where: { $0.id == stopId }),
              si > 0 else { return }
        tripPlans[pi].stops[si].legStamp = nil
        tripPlans[pi].stops[si].legNeedsRetry = false
    }

    /// 讓整份行程所有「當下要不到才退回估算」的段落重新計算
    func retryTripPlanRouting(planId: UUID) {
        guard let pi = tripPlans.firstIndex(where: { $0.id == planId }) else { return }
        isLoading = true
        defer { isLoading = false; save() }
        for i in tripPlans[pi].stops.indices where i > 0 {
            guard tripPlans[pi].stops[i].legNeedsRetry
                    || tripPlans[pi].stops[i].legIsEstimated else { continue }
            // 大眾運輸與飛機本來就沒有路線可問，清了也只是再估一次，不用動
            guard tripPlans[pi].effectiveMode(at: i).supportsRouting else { continue }
            tripPlans[pi].stops[i].legStamp = nil
            tripPlans[pi].stops[i].legNeedsRetry = false
        }
    }

    /// 讓第 index 站的「進站路線」失效（index 可能已超出範圍，代表刪的是最後一站）
    private func invalidateLeg(planIndex pi: Int, at index: Int) {
        guard tripPlans[pi].stops.indices.contains(index) else { return }
        tripPlans[pi].stops[index].legStamp = nil
    }

    // MARK: 住過的地方（v25.405）

    /// 以前標過「在這裡過夜」的地方，供新增景點時快速選。
    struct LodgingSuggestion: Identifiable {
        let id: String
        let name: String
        let address: String
        let latitude: Double?
        let longitude: Double?
        /// 上次在這裡設的退房時刻（沿用比重打一次快）
        let checkOutTime: Date?
        /// 最近一次住的行程出發日
        let lastUsed: Date
        /// 住過幾次
        let useCount: Int
    }

    /// 地點的比對鍵：去空白、統一大小寫。
    /// 名稱＋地址一起比，因為連鎖飯店同名不同家是常態。
    private static func lodgingKey(name: String, address: String) -> String {
        func norm(_ s: String) -> String {
            s.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "\u{3000}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }
        return norm(name) + "|" + norm(address)
    }

    /// 住過的地方，去重後依最近使用排序。
    ///
    /// 座標取「最近那一次有座標的」而不是最新那一次：同一家飯店早期可能是手打的
    /// 沒座標，後來才從地圖搜尋帶進來，反過來取會把座標弄丟。
    func lodgingSuggestions(limit: Int = 12) -> [LodgingSuggestion] {
        var byKey: [String: LodgingSuggestion] = [:]
        // 依行程出發日由舊到新掃，後面的覆蓋前面的，最後留下的就是最新那一次
        for plan in tripPlans.sorted(by: { $0.startDate < $1.startDate }) {
            for stop in plan.stops where stop.isOvernight {
                let name = stop.name.trimmingCharacters(in: .whitespaces)
                let address = stop.address.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty || !address.isEmpty else { continue }
                let key = Self.lodgingKey(name: name, address: address)
                let prev = byKey[key]
                byKey[key] = LodgingSuggestion(
                    id: key,
                    name: name.isEmpty ? (prev?.name ?? "") : name,
                    address: address.isEmpty ? (prev?.address ?? "") : address,
                    latitude: stop.latitude ?? prev?.latitude,
                    longitude: stop.longitude ?? prev?.longitude,
                    checkOutTime: stop.checkOutTime ?? prev?.checkOutTime,
                    lastUsed: plan.startDate,
                    useCount: (prev?.useCount ?? 0) + 1)
            }
        }
        return byKey.values
            .sorted { $0.lastUsed > $1.lastUsed }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - 持久化

    private func save() {
        // 捕捉 struct 快照（值型別複製，安全傳入背景執行緒），避免主執行緒同步序列化 12 份資料
        let snap = (
            profile: profile, familyMembers: familyMembers, milestones: milestones,
            relationships: relationships, pets: pets, schedules: schedules,
            subordinates: subordinates, departments: departments, gradeTitles: gradeTitles,
            businessCards: businessCards, personalEvents: personalEvents, orgPeople: orgPeople,
            healthProfile: healthProfile, familyTasks: familyTasks, equipmentPool: equipmentPool,
            performanceBallots: performanceBallots, workouts: workouts,
            companySites: companySites, tripPlans: tripPlans, workoutPrefs: workoutPrefs,
            workoutHealthLedger: workoutHealthLedger, workoutLeave: workoutLeave,
            wealthBook: wealthBook, wealthDeposits: wealthDeposits, wealthVault: wealthVault,
            wealthTransfers: wealthTransfers
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
            if let d = try? encoder.encode(snap.performanceBallots) { ud.set(d, forKey: "life_performance_ballots") }
            if let d = try? encoder.encode(snap.workouts)       { ud.set(d, forKey: "life_workouts") }
            if let d = try? encoder.encode(snap.companySites)   { ud.set(d, forKey: "life_company_sites") }
            if let d = try? encoder.encode(snap.tripPlans)      { ud.set(d, forKey: "life_trip_plans") }
            if let d = try? encoder.encode(snap.workoutPrefs)   { ud.set(d, forKey: "life_workout_prefs") }
            if let d = try? encoder.encode(snap.workoutHealthLedger) { ud.set(d, forKey: "life_workout_health") }
            if let d = try? encoder.encode(snap.workoutLeave)   { ud.set(d, forKey: "life_workout_leave") }
            if let d = try? encoder.encode(snap.wealthBook)     { ud.set(d, forKey: "life_wealth_book_v1") }
            if let d = try? encoder.encode(snap.wealthDeposits) { ud.set(d, forKey: "life_wealth_deposits_v1") }
            if let d = try? encoder.encode(snap.wealthVault)    { ud.set(d, forKey: WealthVaultBook.syncKey) }
            if let d = try? encoder.encode(snap.wealthTransfers) { ud.set(d, forKey: WealthTransferBook.syncKey) }
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
        if let items = lossyDecodeArray([PerformanceBallot].self, key: "life_performance_ballots", decoder: decoder) { performanceBallots = items }
        if let items = lossyDecodeArray([WorkoutSession].self, key: "life_workouts", decoder: decoder) { workouts = items }
        if let items = lossyDecodeArray([CompanySite].self, key: "life_company_sites", decoder: decoder) { companySites = items }
        if let items = lossyDecodeArray([TripPlan].self, key: "life_trip_plans", decoder: decoder) { tripPlans = items }
        if let data = rawDataIfChanged("life_health_profile"),
           let h = try? decoder.decode(HealthProfile.self, from: data) {
            healthProfile = h
        }
        // [v25.553] 健康頁的設定（看板主角、每週目標）
        if let data = rawDataIfChanged("life_workout_prefs"),
           let wp = try? decoder.decode(WorkoutPrefs.self, from: data) {
            workoutPrefs = wp
        }
        // [v25.554] Apple 健康的帳（不再帶進來的編號、兩筆都留、先不要接回）
        if let data = rawDataIfChanged("life_workout_health"),
           let hl = try? decoder.decode(WorkoutHealthLedger.self, from: data) {
            workoutHealthLedger = hl
        }
        // [v25.557] 請假週
        if let data = rawDataIfChanged("life_workout_leave"),
           let lb = try? decoder.decode(WorkoutLeaveBook.self, from: data) {
            workoutLeave = lb
        }
        // [v25.563] 財富帳本
        if let data = rawDataIfChanged("life_wealth_book_v1"),
           let wb = try? decoder.decode(WealthBook.self, from: data) {
            wealthBook = wb
        }
        // [v25.566] 財富帳本・定存那一包
        if let data = rawDataIfChanged("life_wealth_deposits_v1"),
           let wd = try? decoder.decode(WealthDepositBook.self, from: data) {
            wealthDeposits = wd
        }
        // [v25.568] 號碼密文那一包
        if let data = rawDataIfChanged(WealthVaultBook.syncKey),
           let wv = try? decoder.decode(WealthVaultBook.self, from: data) {
            wealthVault = wv
        }
        // [v25.575] 定期轉帳那一包
        if let data = rawDataIfChanged(WealthTransferBook.syncKey),
           let wt = try? decoder.decode(WealthTransferBook.self, from: data) {
            wealthTransfers = wt
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
    /// [v25.552] 運動紀錄也算（clearAll 本來就會清）：只記運動的人「清除所有資料」以前是灰的、按不下去（U1 C14）
    var isEmpty: Bool {
        profile.isEmpty && familyMembers.isEmpty && milestones.isEmpty && relationships.isEmpty &&
        pets.isEmpty && schedules.isEmpty && subordinates.isEmpty &&
        departments.isEmpty && gradeTitles.isEmpty && businessCards.isEmpty &&
        personalEvents.isEmpty && orgPeople.isEmpty && healthProfile.isEmpty &&
        workouts.isEmpty
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
        workouts.removeAll()
        workoutPrefs = WorkoutPrefs()
        workoutHealthLedger = WorkoutHealthLedger()
        workoutLeave = WorkoutLeaveBook()
        wealthBook = WealthBook()
        wealthDeposits = WealthDepositBook()
        wealthVault = WealthVaultBook()
        wealthTransfers = WealthTransferBook()
        companySites.removeAll()
        // 行程的照片檔也要一起清，不然會留下沒人指向的孤兒檔被雲端一直重傳
        for plan in tripPlans {
            for stop in plan.stops {
                for name in stop.photoFileNames { TripStop.deletePhoto(name) }
            }
        }
        tripPlans.removeAll()
        save()
    }
}

// MARK: - [v25.562] 刪財富帳戶的確認字

/// 刪一筆財富帳戶前，確認框要講的話。LifeStore.financeDeletionImpact 數好，財富卡片、履歷兩邊共用同一段字。
/// 例：刪銀行「有 2 張卡從這裡扣卡費，刪掉後會變成沒有扣款帳戶（卡還在財富頁）；記帳裡從這裡扣的 37 筆會留著，
/// 但不再算任何帳戶；這個帳戶自己的存提款紀錄會一起刪掉，無法復原。」
/// 刪卡「建議改成停用…仍要刪除的話：以前從玉山扣的卡費 NT$12萬 會合成一筆留在玉山，玉山的數字不變；
/// 記帳裡刷這張卡的 127 筆會留著，但不再連到任何卡；Disney+ NT$270／月不會再從任何帳戶扣。」
struct FinanceDeletionImpact {
    /// 要刪的那一筆（按「仍要刪除」時拿它去刪）
    let item: LifeMilestone
    let displayName: String
    let isBank: Bool
    let isCard: Bool
    /// 從這個帳戶扣卡費的卡（刪銀行）
    let linkedCardCount: Int
    /// 記帳裡直接從這裡扣的（不含刷卡）
    let directExpenseCount: Int
    /// 收入裡入這個帳戶的
    let incomeCount: Int
    /// 用它當交割帳戶或證券戶的股票
    let stockCount: Int
    /// 刪卡：扣款帳戶的名字（沒設＝nil）
    let debitBankName: String?
    /// 刪卡：[v25.563] 已經扣的卡費（截止日到了的每一期，台幣）：一期一筆留在當時的扣款帳戶
    let cardTotal: Double
    /// 刪卡：[v25.563] 還沒扣的卡費（要繳＋還沒出帳）：到繳款截止日照樣從扣款帳戶扣
    let unpaidCardTotal: Double
    /// 刪卡：記帳裡刷這張卡的筆數
    let cardExpenseCount: Int
    /// 刪卡：還在扣的定期扣款（「Disney+ NT$270／月」）
    let recurringTexts: [String]
    /// [v25.566] 刪銀行：這個帳戶的定存（一串算一筆）會一起刪
    var timeDepositCount: Int = 0
    /// [v25.575] 刪銀行：碰到它、還在跑的定期轉帳（會在今天結束，以前的期照算）
    var transferRuleCount: Int = 0

    var title: String { "刪掉「\(displayName)」？" }
    /// 還在用的卡先建議改成停用
    var offersDisable: Bool { isCard && item.isDisabled != true }
    var deleteButtonTitle: String { offersDisable ? "仍要刪除" : "刪除" }

    var message: String {
        var parts: [String] = []
        if isCard {
            if let bank = debitBankName {
                if cardTotal > 0 {
                    parts.append("以前從\(bank)扣的卡費 \(cardTotal.ntdWanString) 會一期一筆留在\(bank)的明細，\(bank)的數字不變")
                } else {
                    parts.append("\(bank)的數字不變")
                }
                if unpaidCardTotal > 0 {
                    parts.append("還沒扣的 \(unpaidCardTotal.ntdWanString) 到繳款截止日照樣從\(bank)扣")
                }
            }
            if cardExpenseCount > 0 {
                parts.append("記帳裡刷這張卡的 \(cardExpenseCount) 筆會留著，但不再連到任何卡")
            }
            if !recurringTexts.isEmpty {
                let shown = recurringTexts.prefix(3).joined(separator: "、")
                let more = recurringTexts.count > 3 ? " 等 \(recurringTexts.count) 筆" : ""
                parts.append(shown + more + "不會再從任何帳戶扣")
            }
            if parts.isEmpty { parts.append("刪掉後無法復原") }
            let body = parts.joined(separator: "；") + "。"
            guard offersDisable else { return body }
            return "建議改成停用：記帳的選單不會再出現這張卡，以前的紀錄和數字都不動。\n\n仍要刪除的話：" + body
        }
        if isBank, linkedCardCount > 0 {
            parts.append("有 \(linkedCardCount) 張卡從這裡扣卡費，刪掉後會變成沒有扣款帳戶（卡還在財富頁）")
        }
        var kept: [String] = []
        if directExpenseCount > 0 { kept.append("記帳裡從這裡扣的 \(directExpenseCount) 筆") }
        if incomeCount > 0 { kept.append("收入裡入這個帳戶的 \(incomeCount) 筆") }
        if !kept.isEmpty { parts.append(kept.joined(separator: "、") + "會留著，但不再算任何帳戶") }
        if stockCount > 0 { parts.append("\(stockCount) 檔股票的交割帳戶會清掉") }
        if timeDepositCount > 0 { parts.append("這個帳戶的 \(timeDepositCount) 筆定存會一起刪掉") }
        if transferRuleCount > 0 { parts.append("有 \(transferRuleCount) 條定期轉帳會在今天結束（以前轉的照算）") }
        parts.append(isBank ? "這個帳戶自己的存提款紀錄會一起刪掉，無法復原" : "刪掉後無法復原")
        return parts.joined(separator: "；") + "。"
    }
}

// MARK: - [v25.567] 證券戶舊交割搬家的計畫（#16〔搬到薪轉〕；judge §4.3 ④：搬之前先給你看會動到哪些）

/// LifeStore.settlementMovePlan 算好、WealthSettlementMoveSheet 照著寫字，你按確定才 LifeStore.moveLegacySettlements
struct WealthSettlementMovePlan: Identifiable {
    /// 一筆要搬的：哪一筆、搬到哪個帳戶（那檔股票自己的交割銀行，沒有＝證券戶的交割銀行）
    struct Move: Equatable {
        let depositId: UUID
        let targetId: UUID
    }

    let brokerId: UUID
    let brokerName: String
    let bankId: UUID
    let bankName: String
    let moves: [Move]
    /// 交割銀行已經有同一筆（同日、同額、同一檔、同方向）：從證券戶拿掉、不再寫一份
    let skipIds: [UUID]
    /// 股票已經刪了的：留在證券戶當紀錄
    let keepIds: [UUID]
    let buys: Int
    let sells: Int
    let dividends: Int
    /// 搬的那幾筆合計（台幣，有正負：買入是負的）
    let total: Double
    /// 這個證券戶還沒有交割銀行的股票（搬完交割銀行＝它，之後的交割都從它扣）
    let stockIds: [UUID]
    /// 交割銀行今天的存摺上（台幣）：搬之前、搬之後
    let bankBefore: Double
    var bankAfter: Double
    /// 存款合計：搬之前、搬之後
    let cashBefore: Double
    var cashAfter: Double
    /// 交割銀行最近一次對存摺（那天以前的交割不會改變現在的數字）
    let lastAnchor: Date?

    var id: UUID { brokerId }

    /// 「會動到 18 筆（買入 12・賣出 4・股利 2），合計 −1,250,000」
    var summary: String {
        var kinds: [String] = []
        if buys > 0 { kinds.append("買入 \(buys)") }
        if sells > 0 { kinds.append("賣出 \(sells)") }
        if dividends > 0 { kinds.append("股利 \(dividends)") }
        let sign = total < 0 ? "−" : "+"
        var s = "會動到 \(moves.count) 筆"
        if !kinds.isEmpty { s += "（" + kinds.joined(separator: "・") + "）" }
        return s + "，合計 " + sign + WealthFormat.grouped(Swift.abs(total).rounded(), decimals: 0)
    }

    /// 「薪轉的存摺上：128,400 → 128,400（不變）」
    var bankLine: String {
        let before = WealthFormat.grouped(bankBefore.rounded(), decimals: 0)
        let after = WealthFormat.grouped(bankAfter.rounded(), decimals: 0)
        let same = Swift.abs(bankAfter - bankBefore) < 0.5
        return bankName + "的存摺上：" + before + " → " + after + (same ? "（不變）" : "")
    }

    /// 「薪轉 10/1 對過存摺：那天以前的交割不會改變現在的數字」；沒對過 nil
    var anchorLine: String? {
        guard let d = lastAnchor else { return nil }
        return bankName + " " + WealthFormat.monthDay(d) + " 對過存摺：那天以前的交割不會改變現在的數字"
    }

    /// 「3 筆薪轉已經有同一筆（同日、同額、同一檔），會跳過」；沒有 nil
    var skipLine: String? {
        guard !skipIds.isEmpty else { return nil }
        return "\(skipIds.count) 筆\(bankName)已經有同一筆（同日、同額、同一檔），會跳過"
    }

    /// 「2 筆的股票已經刪了，留在證券戶當紀錄」；沒有 nil
    var keepLine: String? {
        guard !keepIds.isEmpty else { return nil }
        return "\(keepIds.count) 筆的股票已經刪了，留在\(brokerName)當紀錄"
    }

    /// 「這 3 檔股票之後的交割都從薪轉扣」；沒有 nil
    var stocksLine: String? {
        guard !stockIds.isEmpty else { return nil }
        return "這 \(stockIds.count) 檔股票之後的交割都從\(bankName)扣"
    }

    /// 「存款合計：NT$81.7萬 → NT$76.5萬」（ntdWanString：主執行緒）
    var cashLine: String {
        "存款合計：" + cashBefore.ntdWanString + " → " + cashAfter.ntdWanString
    }

    /// 照計畫搬完的樣子（純函式：settlementMovePlan 算「搬之後」、moveLegacySettlements 真的寫，都用這一支）
    static func applied(_ plan: WealthSettlementMovePlan, milestones: [LifeMilestone],
                        stocks: [Stock]) -> (milestones: [LifeMilestone], stocks: [Stock], stocksChanged: Bool) {
        var all = milestones
        var moving: [UUID: UUID] = [:]
        for m in plan.moves { moving[m.depositId] = m.targetId }
        let drop = Set(plan.skipIds)
        var carry: [UUID: [BankDeposit]] = [:]
        if let ki = all.firstIndex(where: { $0.id == plan.brokerId }) {
            var kept: [BankDeposit] = []
            for d in all[ki].bankDeposits ?? [] {
                if let t = moving[d.id] {
                    carry[t, default: []].append(d)
                } else if !drop.contains(d.id) {
                    kept.append(d)
                }
            }
            all[ki].bankDeposits = kept
        }
        for (target, list) in carry {
            guard let ti = all.firstIndex(where: { $0.id == target }) else { continue }
            var deps = all[ti].bankDeposits ?? []
            deps.append(contentsOf: list)
            all[ti].bankDeposits = deps
        }
        var out = stocks
        var changed = false
        let relink = Set(plan.stockIds)
        for i in out.indices where relink.contains(out[i].id) && out[i].linkedBankMilestoneId == nil {
            out[i].linkedBankMilestoneId = plan.bankId
            changed = true
        }
        return (milestones: all, stocks: out, stocksChanged: changed)
    }
}

/// [v25.567] 保單表單存檔時的保費（LifeStore.savePolicyPremium；judge §5.4-3）
struct WealthPolicyPremiumDraft {
    /// 新建記帳那一筆的名字「國泰人壽 醫療險」
    var title: String
    /// 每期（台幣）
    var amount: Double
    var cycle: WealthPolicyCycle
    var kind: WealthPolicyKind
    /// 新建時的第一期（下次扣款日；沒填用生效日）
    var firstDue: Date
    /// 從哪扣：銀行（＋幣別）或卡（卡優先）
    var bankId: UUID?
    var bankCode: String?
    var cardId: UUID?
}
