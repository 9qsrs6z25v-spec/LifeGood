import Foundation
import CloudKit
import Combine

/// 對外的同步開關 / 狀態 ObservableObject。
///
/// 介面與舊版 NSUbiquitousKeyValueStore 版本相容（`pushAll`、`push(key:)`、
/// `syncNow`、`isEnabled`、`isAccountAvailable`、`lastSyncDate`、`lastChangeReason`），
/// 底層改由 `CloudKitManager` 走 CloudKit Private Database。
final class CloudSyncManager: ObservableObject {
    static let shared = CloudSyncManager()

    // MARK: - 同步的 UserDefaults keys（含照片無法走 KV 的所有結構化資料）

    static let syncKeys: [String] = [
        // ExpenseStore
        "lifegood_expenses",
        "lifegood_incomes",
        "lifegood_currency_rates",
        // FinanceStore
        "lifegood_insurances",
        "lifegood_stocks",
        "lifegood_vehicles",
        "lifegood_realestates",
        // LifeStore
        "life_profile",
        "life_family",
        "life_milestones",
        "life_relationships",
        "life_pets",
        "life_schedules",
        "life_subordinates",
        "life_departments",
        "life_grade_titles",
        "life_business_cards",
        "life_personal_events",
        "life_org_people",
        "life_health_profile",
        "life_family_tasks",
        "life_equipment_pool",
        // 股票每週市值快照（英雄卡背景折線）：同步安全性依賴「先拉後推」順序——
        // 少用的裝置會先拉到主力機的完整歷史，記錄本週快照時是在完整清單上加點再推回，
        // 歷史只增不減；不需自訂合併邏輯
        "stock_value_weekly_history",
        // 進階設定＋AI 供應商選擇的打包 blob（KV 機制只搬 Data，散裝 Double/Int/Bool
        // 由 AppPreferenceSync 推送前打包／拉取後解包）
        AppPreferenceSync.blobKey
    ]

    private static let enabledKey = "icloud_sync_enabled"
    private static let lastSyncKey = "icloud_last_sync_date"

    // MARK: - Published State

    // isEnabled 只在主執行緒被寫入（Settings Toggle／init），但 PhotoCloudSync.upload/delete
    // 會從背景執行緒（Task.detached 的相片壓縮／上傳流程）讀取，@Published 本身不保證跨執行緒讀寫安全。
    // 比照 CloudKitManager.accountStatus 既有的 NSLock 鏡射寫法，另存一份鎖保護的鏡像值供背景執行緒讀取。
    private let isEnabledLock = NSLock()
    private var _isEnabledThreadSafe: Bool = false
    var isEnabledThreadSafe: Bool {
        isEnabledLock.lock(); defer { isEnabledLock.unlock() }
        return _isEnabledThreadSafe
    }

    @Published var isEnabled: Bool {
        didSet {
            isEnabledLock.lock(); _isEnabledThreadSafe = isEnabled; isEnabledLock.unlock()
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled {
                beginInitialSync()
            }
        }
    }

    /// 首次開啟同步、且雲端已有資料時的待決狀態（由 SettingsView 跳出選項詢問使用者）
    @Published var pendingInitialSync: InitialSyncInfo? = nil

    struct InitialSyncInfo: Identifiable {
        let id = UUID()
        let cloudItemCount: Int        // 雲端目前約有幾筆資料（給使用者參考）
        let cloudBlobs: [String: Data] // 預讀到的雲端資料（用於覆蓋／合併）
    }

    enum InitialSyncChoice {
        case overwriteCloud   // 以這台覆蓋雲端
        case overwriteLocal   // 以雲端覆蓋這台
        case mergeLocalWins   // 合併，重複以本機為準
        case mergeCloudWins   // 合併，重複以雲端為準
    }

    // 防抖：2 秒內多次 pushAll() 合併為一次
    private var pushDebounceTimer: Timer?
    // 防止並行 sync：syncNow + onChange(scenePhase) 同時觸發時只執行一次
    // 改為 @Published：讓設定頁「立即同步」按鈕能顯示同步中轉圈（先前是私有變數，
    // 按下去毫無視覺回饋，使用者回報「不太有按鈕感覺」）。
    // didSet 看門狗：使用者回報「同步中…」跨日不結束——任何一條路徑的 completion 沒回來
    // （網路中斷、系統掛起操作），isSyncing 就永遠卡 true，之後所有同步（含手動立即同步）
    // 都被 guard 跳過，整個同步系統死鎖。改為旗標升起自動起 3 分鐘看門狗，逾時強制重置。
    @Published private(set) var isSyncing = false {
        didSet {
            if isSyncing { armSyncWatchdog() }
            else {
                syncWatchdogTimer?.invalidate(); syncWatchdogTimer = nil
                syncProgressText = nil
            }
        }
    }
    /// 上傳進度文字（例「上傳照片 12/87」）；供設定頁「同步中…」列顯示即時進度
    @Published private(set) var syncProgressText: String?
    private var syncWatchdogTimer: Timer?

    /// isSyncing 升起後 3 分鐘未落下即強制重置（等待「覆蓋/合併」使用者選擇屬合法長等待，
    /// 另給 10 分鐘，仍未選擇視為放棄、關回同步開關避免永久卡死）。
    private func armSyncWatchdog() {
        syncWatchdogTimer?.invalidate()
        syncWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: false) { [weak self] _ in
            guard let self, self.isSyncing else { return }
            if self.pendingInitialSync != nil {
                self.syncWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: false) { [weak self] _ in
                    guard let self, self.isSyncing, self.pendingInitialSync != nil else { return }
                    self.cancelInitialSync()
                    self.setSyncError("雲端整合選擇逾時未完成，同步已暫停。重新開啟「啟用 iCloud 同步」即可再次選擇。")
                }
                return
            }
            self.isSyncing = false
            // 同步取消進行中的照片上傳迴圈，避免下一輪「立即同步」與殘留迴圈疊加
            CloudKitManager.shared.cancelPhotoSweep()
            self.setSyncError("同步逾時（超過 3 分鐘無回應），已自動重置。請再按一次「立即同步」。")
        }
    }

    @Published private(set) var isAccountAvailable: Bool = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var lastChangeReason: ChangeReason = .none
    /// 最近一次 CloudKit 失敗的可讀訊息（成功同步後清空）；給 SettingsView 顯示
    @Published private(set) var lastErrorMessage: String?

    enum ChangeReason: String {
        case none = ""
        case serverChange = "從 iCloud 收到更新"
        case initialSync = "初次同步完成"
        case quotaViolation = "超過 iCloud 配額"
        case accountChange = "iCloud 帳號已變更"
    }

    // MARK: - Init

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        if let date = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date {
            self.lastSyncDate = date
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAccountStatusChanged),
            name: CloudKitManager.accountStatusDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKVChanges(_:)),
            name: CloudKitManager.didPullKVChangesNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePhotoChanges(_:)),
            name: CloudKitManager.didPullPhotoChangesNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSyncError(_:)),
            name: CloudKitManager.didEncounterErrorNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSyncProgress(_:)),
            name: CloudKitManager.syncProgressNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSharingStateChanged(_:)),
            name: CloudKitManager.sharingStateDidChangeNotification,
            object: nil
        )

        // 啟動時取一次帳號狀態
        CloudKitManager.shared.refreshAccountStatus { [weak self] status in
            self?.updateAccountStatus(status)
        }
    }

    // MARK: - Account

    func updateAccountStatus() {
        CloudKitManager.shared.refreshAccountStatus { [weak self] status in
            self?.updateAccountStatus(status)
        }
    }

    private func updateAccountStatus(_ status: CKAccountStatus) {
        let avail = (status == .available)
        DispatchQueue.main.async { [weak self] in
            self?.isAccountAvailable = avail
        }
    }

    /// 上傳進度：更新顯示文字，並「餵看門狗」——首次全量上傳幾百張照片
    /// 合法地超過 3 分鐘，只要進度仍在推進就不該被看門狗誤判為卡死強制重置。
    @objc private func handleSyncProgress(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.syncProgressText = note.userInfo?["text"] as? String
            if self.isSyncing, self.syncProgressText != nil { self.armSyncWatchdog() }
        }
    }

    /// 共享狀態變更（接受邀請／退出共享）：資料區已切換（共享 zone ↔ 自己的 zone），
    /// 重跑「覆蓋/合併」初始流程，讓使用者決定本機資料與新資料區的整合方式。
    @objc private func handleSharingStateChanged(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let joined = (note.userInfo?["joined"] as? Bool) ?? false
            // 未開同步的裝置：接受邀請視同想要同步，自動開啟開關再走初始流程
            if joined, !self.isEnabled { self.isEnabled = true }
            guard self.isEnabled, self.isAccountAvailable else { return }
            self.forceResetSyncState()
            self.lastErrorMessage = nil
            self.repromptInitialSync()
        }
    }

    @objc private func handleAccountStatusChanged() {
        let status = CloudKitManager.shared.accountStatus
        updateAccountStatus(status)
        DispatchQueue.main.async { [weak self] in
            self?.lastChangeReason = .accountChange
        }
    }

    // MARK: - Push（給 Stores 呼叫）

    /// 單一 key 的變更推送至 iCloud（不走 2 秒防抖，已無外部呼叫者；保留為 private 防止繞過節流）
    private func push(key: String) {
        guard isEnabled, isAccountAvailable else { return }
        guard Self.syncKeys.contains(key) else { return }
        if let data = UserDefaults.standard.data(forKey: key) {
            CloudKitManager.shared.pushKV(key: key, data: data) { [weak self] _ in
                self?.markSynced()
            }
        }
    }

    /// 任何 Store 的 save() 都會觸發：2 秒防抖後將所有 sync key 一次推送
    /// 可從任意執行緒呼叫；@Published 屬性的讀寫統一在主執行緒完成，避免資料競態。
    func pushAll() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isEnabled, self.isAccountAvailable else { return }
            self.pushDebounceTimer?.invalidate()
            self.pushDebounceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                self?.flushPushAll()
            }
        }
    }

    private func flushPushAll() {
        // isSyncing 期間跳過：避免與進行中的 performSync 並行打同一批 key 導致 serverRecordChanged 衝突
        guard isEnabled, isAccountAvailable, !isSyncing else { return }
        isSyncing = true
        CloudKitManager.shared.pushAllKV(keys: Self.syncKeys) { [weak self] allOK in
            // 只在全部 key 都推送成功才 markSynced()，避免失敗的一輪被誤標為已同步
            // （清空 lastErrorMessage、更新 lastSyncDate，讓 UI 誤以為已同步且延後下次重試）。
            self?.isSyncing = false
            if allOK { self?.markSynced() }
        }
    }

    /// 手動再跑一次「覆蓋／合併」選擇流程（即使已啟用同步），方便日後重新統一兩端資料
    func repromptInitialSync() {
        guard isAccountAvailable else { return }
        beginInitialSync()
    }

    /// 開啟同步時：建立 zone/subscription，非破壞性預讀雲端。
    /// - 雲端沒資料 → 直接把本機推上去（種子）。
    /// - 雲端已有資料 → 設定 pendingInitialSync，由 UI 詢問使用者要覆蓋還是合併。
    ///
    /// 全程以 isSyncing 守衛：避免使用者連續點擊「立即同步」與「重新選擇同步方式」時，
    /// 此流程與 performSync() 並行打同一批 key 造成 serverRecordChanged 衝突。
    private func beginInitialSync() {
        guard !isSyncing else { return }
        isSyncing = true
        CloudKitManager.shared.bootstrap { [weak self] ok in
            // bootstrap completion 可能由 CloudKit 背景佇列呼叫，
            // 強制回主執行緒再修改 isSyncing，避免競態條件
            DispatchQueue.main.async { [weak self] in
                guard let self = self, ok else { self?.isSyncing = false; return }
                CloudKitManager.shared.fetchAllKVToMemory { [weak self] cloudBlobs in
                    guard let self = self else { return }
                    let count = Self.itemCount(cloudBlobs)
                    if count == 0 {
                        // 雲端沒資料：把本機推上去當種子，不需詢問
                        CloudKitManager.shared.pushAllKV(keys: Self.syncKeys) { [weak self] pushOK in
                            CloudKitManager.shared.uploadAllLocalPhotos {
                                self?.isSyncing = false
                                if pushOK { self?.markSynced() }
                                DispatchQueue.main.async { [weak self] in self?.lastChangeReason = .initialSync }
                            }
                        }
                    } else {
                        // 保持 isSyncing = true 直到使用者做出覆蓋／合併選擇（resolveInitialSync）
                        // 或取消（cancelInitialSync），避免決策期間被自動同步搶跑。
                        DispatchQueue.main.async { [weak self] in
                            self?.pendingInitialSync = InitialSyncInfo(cloudItemCount: count, cloudBlobs: cloudBlobs)
                        }
                    }
                }
            }
        }
    }

    /// 使用者在首次同步選項中做出選擇後執行
    func resolveInitialSync(_ choice: InitialSyncChoice) {
        let cloudBlobs = pendingInitialSync?.cloudBlobs ?? [:]
        pendingInitialSync = nil
        let defaults = UserDefaults.standard

        switch choice {
        case .overwriteCloud:
            // 用本機覆蓋雲端：本機不動，下方直接 push 即可
            break
        case .overwriteLocal:
            // 用雲端覆蓋本機：把預讀到的雲端資料寫回本機，再通知各 Store 重載
            // 雲端從未寫入過的 key（例如另一台裝置從未使用過的資料類別）也要一併清空本機，
            // 否則「覆蓋本機」只會覆蓋雲端已有的類別，其餘本機舊資料會殘留並在下方 pushAllKV 時被誤傳回雲端。
            for key in Self.syncKeys {
                if let data = cloudBlobs[key] {
                    defaults.set(data, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
            NotificationCenter.default.post(name: .cloudSyncDidPullChanges, object: nil)
        case .mergeLocalWins, .mergeCloudWins:
            let localWins = (choice == .mergeLocalWins)
            let keys = Set(Self.syncKeys).union(cloudBlobs.keys)
            for key in keys {
                if let merged = Self.mergeBlob(local: defaults.data(forKey: key),
                                               cloud: cloudBlobs[key],
                                               localWins: localWins) {
                    defaults.set(merged, forKey: key)
                }
            }
            NotificationCenter.default.post(name: .cloudSyncDidPullChanges, object: nil)
        }

        // 「以雲端覆蓋本機」時先清空前綴託管的命名空間：unpack() 在雲端沒有 blob 時
        // 會直接 return，本機的樣式覆寫會原封不動留下、再被下方 pushAllKV 推回雲端。
        if choice == .overwriteLocal { HeroStyleStore.shared.resetNamespace() }
        // 覆蓋本機／合併後：進階設定 blob 也可能剛被雲端值覆蓋，解包回散裝鍵
        AppPreferenceSync.unpack()

        // 把（覆蓋／合併後的）本機資料推回雲端，並上傳本機照片
        isSyncing = true
        CloudKitManager.shared.pushAllKV(keys: Self.syncKeys) { [weak self] pushOK in
            CloudKitManager.shared.uploadAllLocalPhotos {
                self?.isSyncing = false
                if pushOK { self?.markSynced() }
                DispatchQueue.main.async { [weak self] in self?.lastChangeReason = .initialSync }
            }
        }
    }

    /// 使用者在首次同步選項中取消 → 關回同步開關
    func cancelInitialSync() {
        pendingInitialSync = nil
        isSyncing = false
        isEnabled = false
    }

    /// 計算一批 KV blob 內的資料筆數：陣列型 blob 加總元素數；
    /// 非陣列（物件型，如 life_profile／life_health_profile 為單一 Codable struct）
    /// 只要能解出非空物件就算 1 筆，避免被誤判為「雲端沒資料」而略過覆蓋／合併詢問、
    /// 靜默把本機資料當種子推上去覆蓋雲端既有資料。
    static func itemCount(_ blobs: [String: Data]) -> Int {
        var n = 0
        for (_, data) in blobs {
            if let arr = (try? JSONSerialization.jsonObject(with: data)) as? [Any] {
                n += arr.count
            } else if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], !obj.isEmpty {
                n += 1
            }
        }
        return n
    }

    /// 以 id 為鍵合併兩個陣列型 KV blob；重複的同一筆由 localWins 決定以哪邊為準。
    /// 非陣列（設定類）blob 無法逐筆合併，直接採用勝方版本。
    static func mergeBlob(local: Data?, cloud: Data?, localWins: Bool) -> Data? {
        func arr(_ d: Data?) -> [[String: Any]]? {
            guard let d else { return nil }
            return (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]]
        }
        guard let localArr = arr(local), let cloudArr = arr(cloud) else {
            // 其中一邊不是物件陣列 → 用勝方資料
            return localWins ? (local ?? cloud) : (cloud ?? local)
        }
        func idOf(_ o: [String: Any]) -> String? {
            if let s = o["id"] as? String { return s }
            if let n = o["id"] as? NSNumber { return n.stringValue }
            return nil
        }
        var byId: [String: [String: Any]] = [:]
        var order: [String] = []
        let loserFirst = localWins ? cloudArr : localArr
        let winnerSecond = localWins ? localArr : cloudArr
        for o in loserFirst { if let i = idOf(o) { if byId[i] == nil { order.append(i) }; byId[i] = o } }
        for o in winnerSecond { if let i = idOf(o) { if byId[i] == nil { order.append(i) }; byId[i] = o } }
        let merged = order.compactMap { byId[$0] }
        return try? JSONSerialization.data(withJSONObject: merged)
    }

    /// 手動觸發同步：刷新帳號狀態 → 拉取 → 推送
    /// 開放給「使用者明確要求同步」用的入口；忽略節流
    func syncNow() {
        performSync(force: true)
    }

    /// 給 scenePhase 變動時自動觸發的入口：30 秒內已同步過就跳過，
    /// 避免使用者快速切換 App 時頻繁拉雲端造成畫面閃爍
    func syncNowIfDue() {
        performSync(force: false)
    }

    private func performSync(force: Bool) {
        guard !isSyncing else { return }
        if !force, let last = lastSyncDate,
           Date().timeIntervalSince(last) < 30 {
            // 30 秒內已同步，跳過
            return
        }
        isSyncing = true
        CloudKitManager.shared.refreshAccountStatus { [weak self] status in
            guard let self = self else { return }
            self.updateAccountStatus(status)
            guard status == .available, self.isEnabled else {
                // refreshAccountStatus 已確保回到主執行緒
                if self.isEnabled {
                    self.setSyncError("iCloud 帳號不可用，同步中止。請到 設定 → Apple ID → iCloud 確認已登入並開啟 LifeGood。")
                }
                self.isSyncing = false
                return
            }
            CloudKitManager.shared.bootstrap { [weak self] ok in
                // bootstrap completion 可能由 CloudKit 背景佇列呼叫，
                // 強制回主執行緒再修改 isSyncing，避免競態條件
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard ok else {
                        self.setSyncError("iCloud 初始化失敗（建立資料區/拉取變更），請稍後再試。")
                        self.isSyncing = false
                        return
                    }
                    CloudKitManager.shared.fetchChanges { [weak self] ok in
                        // fetchChanges completion 已保證在主執行緒執行，直接重置旗標
                        // 拉取失敗時不推送：避免以過期本地資料覆蓋雲端（潛在資料遺失）
                        guard ok else {
                            self?.setSyncError("拉取雲端變更失敗，本次未推送（避免以過期資料覆蓋雲端）。")
                            self?.isSyncing = false
                            return
                        }
                        // 等 push／上傳實際完成才重置 isSyncing、且只在全部成功時才 markSynced()，
                        // 避免失敗的一輪被誤標為已同步（清空錯誤訊息、讓 30 秒節流延後下次重試）。
                        CloudKitManager.shared.pushAllKV(keys: Self.syncKeys) { [weak self] pushOK in
                            CloudKitManager.shared.uploadAllLocalPhotos {
                                self?.isSyncing = false
                                if pushOK { self?.markSynced() }
                                else { self?.setSyncError("部分資料推送失敗，請稍後再按一次「立即同步」。") }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Pull（被 CloudKitManager 通知）

    @objc private func handleKVChanges(_ note: Notification) {
        // 必須在主執行緒發送通知，避免各 Store 的 reloadFromCloud 在背景執行緒
        // 修改 @Published 屬性造成競態條件
        // 附帶轉發 CloudKitManager 算出的實際變更 key（userInfo["keys"]），讓各 Store 只在
        // 自己負責的 key 有異動時才 load()，避免任一 Store 的雲端變更都讓所有 Store 全量重載、
        // 觸發不相關畫面（圖表／組織圖／行事曆等）不必要的重繪與進場動畫重播。
        let keys = note.userInfo?["keys"] as? [String]
        // 進階設定 blob 從雲端更新：解包回散裝 @AppStorage 鍵，畫面即時生效
        if keys == nil || keys?.contains(AppPreferenceSync.blobKey) == true {
            AppPreferenceSync.unpack()
        }
        DispatchQueue.main.async { [weak self] in
            self?.lastChangeReason = .serverChange
            self?.markSynced()
            var userInfo: [AnyHashable: Any]? = nil
            if let keys { userInfo = ["keys": keys] }
            NotificationCenter.default.post(name: .cloudSyncDidPullChanges, object: nil, userInfo: userInfo)
        }
    }

    private static let errorTimeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    @objc private func handleSyncError(_ note: Notification) {
        let msg = note.userInfo?["message"] as? String
        DispatchQueue.main.async { [weak self] in
            // 帶上發生時間：讓使用者能分辨「同步錯誤」列顯示的是剛剛的錯誤還是舊殘留
            self?.lastErrorMessage = msg.map { "[\(Self.errorTimeFmt.string(from: Date()))] \($0)" }
        }
    }

    @objc private func handlePhotoChanges(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.lastChangeReason = .serverChange
            self?.markSynced()
            NotificationCenter.default.post(name: .cloudSyncPhotosDidUpdate, object: nil)
        }
    }

    // MARK: - Helpers

    /// 手動強制重置同步狀態：給設定頁「同步中」列的「重置」按鈕使用。
    /// 看門狗（3 分鐘）之外的即時逃生口——任何未知路徑卡住 isSyncing 都能立即解鎖。
    func forceResetSyncState() {
        pendingInitialSync = nil
        isSyncing = false
        // 真正取消進行中的照片上傳迴圈：先前重置只放下旗標、舊迴圈仍在背景跑，
        // 再按「立即同步」會疊上第二輪，兩組進度數字交錯跳動且照片重複上傳
        CloudKitManager.shared.cancelPhotoSweep()
        setSyncError("已手動重置同步狀態，請再按一次「立即同步」。")
    }

    /// 同步中止/失敗時把原因寫進 lastErrorMessage（設定頁「同步錯誤」列會顯示），
    /// 取代先前 guard 直接 return 的靜默失敗——按了立即同步卻毫無動靜、無從診斷。
    private func setSyncError(_ message: String) {
        let stamped = "[\(Self.errorTimeFmt.string(from: Date()))] \(message)"
        if Thread.isMainThread { lastErrorMessage = stamped }
        else { DispatchQueue.main.async { self.lastErrorMessage = stamped } }
    }

    private func markSynced() {
        let now = Date()
        // @Published 屬性與 UserDefaults 必須在同一執行緒/批次寫入，
        // 避免非主執行緒路徑下 UserDefaults 先更新完畢、lastSyncDate 尚未更新，
        // 導致 syncNowIfDue 在空窗內讀到舊值而誤觸一次完整同步。
        if Thread.isMainThread {
            lastSyncDate = now
            lastErrorMessage = nil
            UserDefaults.standard.set(now, forKey: Self.lastSyncKey)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.lastSyncDate = now
                self?.lastErrorMessage = nil
                UserDefaults.standard.set(now, forKey: Self.lastSyncKey)
            }
        }
    }
}

extension Notification.Name {
    /// iCloud 拉到結構化資料變更後發送，Store 收到應重新從 UserDefaults 載入
    static let cloudSyncDidPullChanges = Notification.Name("cloudSyncDidPullChanges")
    /// iCloud 拉到照片變更後發送，UI 需重新載入圖片
    static let cloudSyncPhotosDidUpdate = Notification.Name("cloudSyncPhotosDidUpdate")
}

// MARK: - 進階設定／AI 偏好打包同步

/// KV 同步機制只搬「Data 型別」的 UserDefaults 值，@AppStorage 的散裝
/// Double/Int/Bool/String（進階設定的模板參數、AI 供應商選擇）不會被搬。
/// 解法：打包成單一 JSON blob 進 syncKeys——每次推送前（CloudKitManager.pushAllKV
/// 開頭）打包、拉取到 blob 變更後（handleKVChanges／resolveInitialSync）解包。
/// 衝突語意：最後推送者贏（模板偏好可容忍）。
/// 注意：AI 的 API Key 存 Keychain、不進此 blob——Key 走 iCloud 鑰匙圈
/// （kSecAttrSynchronizable）同步，端對端加密且不進 App 的 CloudKit 資料區。
enum AppPreferenceSync {
    static let blobKey = "app_preferences_blob_v1"

    /// 要同步的散裝偏好鍵（新增進階設定參數時記得補進來）
    static let scalarKeys: [String] = [
        // 趨勢曲線模板
        "hero_trend_point_count", "hero_trend_opacity", "hero_trend_line_width",
        "hero_trend_blur", "hero_trend_left_pos", "hero_trend_right_pos",
        "hero_trend_rot_x", "hero_trend_rot_y", "hero_trend_rot_z",
        "hero_trend_end_opacity", "hero_trend_show_end_label",
        // 股票量柱
        "hero_volume_bar_opacity",
        // 閃卡樣式
        "flash_card_corner_radius", "flash_card_border_scale", "flash_card_value_size",
        "flash_card_bokeh", "flash_card_shine", "flash_card_shadow", "flash_card_animation",
        // 英雄卡樣式
        "hero_card_corner_radius", "hero_card_bokeh", "hero_card_shine",
        "hero_card_shadow", "hero_card_kpi_value_size",
        // 法人連續買超天數
        "inst_streak_days",
        // 語音 AI 助手：供應商選擇（API Key 走 iCloud 鑰匙圈，不在此）
        "LifeGood.ai.activeProvider"
    ]

    /// 前綴託管的命名空間：整片掃描搬運，不逐把列舉。
    /// 英雄卡樣式（hs.）的鍵數是「24 卡 × 8 項」量級，硬列舉必爆炸。
    static let managedPrefixes = ["hs."]
    /// blob 內宣告本次推送涵蓋哪些前綴——舊版 App 推的 blob 沒有這把，
    /// 解包端據此判斷「可不可以刪本機多出來的鍵」（墓碑語意）
    private static let markerKey = "__managedPrefixes"

    /// 推送前呼叫：把散裝值打包成 blob。內容沒變就不重寫，
    /// 避免每輪同步都讓 blob 變髒、觸發無謂推送。
    static func pack() {
        let d = UserDefaults.standard
        var dict: [String: Any] = [:]
        for k in scalarKeys {
            if let v = d.object(forKey: k), v is NSNumber || v is String {
                dict[k] = v
            }
        }
        // 前綴託管的鍵整片收進來（dictionaryRepresentation 全程只呼叫一次）
        let all = d.dictionaryRepresentation()
        for (k, v) in all where managedPrefixes.contains(where: k.hasPrefix) {
            if v is NSNumber || v is String { dict[k] = v }
        }
        dict[markerKey] = managedPrefixes
        guard let data = try? JSONSerialization.data(withJSONObject: dict,
                                                     options: [.sortedKeys]) else { return }
        if d.data(forKey: blobKey) != data {
            d.set(data, forKey: blobKey)
        }
    }

    /// 拉取到 blob 變更後呼叫：解包回散裝鍵（值相同不重寫，畫面即時生效）
    static func unpack() {
        let d = UserDefaults.standard
        guard let data = d.data(forKey: blobKey),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            HeroStyleStore.shared.invalidate()
            return
        }
        // 墓碑語意：對方有宣告同一前綴，才刪本機多出來的鍵——
        // 「取消覆寫」是刪鍵，沒有這段就同步不過去。舊版 App 的 blob 沒有 marker，
        // 只做加法、不會把新版的覆寫整片清光。
        let peer = (dict[markerKey] as? [String]) ?? []
        let all = d.dictionaryRepresentation()
        for pre in managedPrefixes where peer.contains(pre) {
            let incoming = Set(dict.keys.filter { $0.hasPrefix(pre) })
            for k in all.keys where k.hasPrefix(pre) && !incoming.contains(k) {
                d.removeObject(forKey: k)
            }
        }
        for (k, v) in dict where k != markerKey
            && (scalarKeys.contains(k) || managedPrefixes.contains(where: k.hasPrefix)) {
            if let old = d.object(forKey: k) as? NSNumber, let new = v as? NSNumber,
               old == new { continue }
            if let old = d.object(forKey: k) as? String, let new = v as? String,
               old == new { continue }
            d.set(v, forKey: k)
        }
        HeroStyleStore.shared.invalidate()
    }
}
