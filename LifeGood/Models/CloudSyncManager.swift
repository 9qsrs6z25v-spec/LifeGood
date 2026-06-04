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
        "life_org_people"
    ]

    private static let enabledKey = "icloud_sync_enabled"
    private static let lastSyncKey = "icloud_last_sync_date"

    // MARK: - Published State

    @Published var isEnabled: Bool {
        didSet {
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
    private var isSyncing = false

    @Published private(set) var isAccountAvailable: Bool = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var lastChangeReason: ChangeReason = .none

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

    @objc private func handleAccountStatusChanged() {
        let status = CloudKitManager.shared.accountStatus
        updateAccountStatus(status)
        DispatchQueue.main.async { [weak self] in
            self?.lastChangeReason = .accountChange
        }
    }

    // MARK: - Push（給 Stores 呼叫）

    /// 單一 key 的變更推送至 iCloud（Store save() 後可呼叫）
    func push(key: String) {
        guard isEnabled, isAccountAvailable else { return }
        guard Self.syncKeys.contains(key) else { return }
        if let data = UserDefaults.standard.data(forKey: key) {
            CloudKitManager.shared.pushKV(key: key, data: data) { [weak self] _ in
                self?.markSynced()
            }
        }
    }

    /// 任何 Store 的 save() 都會觸發：2 秒防抖後將所有 sync key 一次推送
    func pushAll() {
        guard isEnabled, isAccountAvailable else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pushDebounceTimer?.invalidate()
            self.pushDebounceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                self?.flushPushAll()
            }
        }
    }

    private func flushPushAll() {
        guard isEnabled, isAccountAvailable else { return }
        let keys = Self.syncKeys
        let group = DispatchGroup()
        for key in keys {
            if let data = UserDefaults.standard.data(forKey: key) {
                group.enter()
                CloudKitManager.shared.pushKV(key: key, data: data) { _ in group.leave() }
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.markSynced()
        }
    }

    /// 開啟同步時：建立 zone/subscription，非破壞性預讀雲端。
    /// - 雲端沒資料 → 直接把本機推上去（種子）。
    /// - 雲端已有資料 → 設定 pendingInitialSync，由 UI 詢問使用者要覆蓋還是合併。
    private func beginInitialSync() {
        CloudKitManager.shared.bootstrap { [weak self] ok in
            guard let self = self, ok else { return }
            CloudKitManager.shared.fetchAllKVToMemory { [weak self] cloudBlobs in
                guard let self = self else { return }
                let count = Self.itemCount(cloudBlobs)
                if count == 0 {
                    // 雲端沒資料：把本機推上去當種子，不需詢問
                    CloudKitManager.shared.pushAllKV(keys: Self.syncKeys)
                    CloudKitManager.shared.uploadAllLocalPhotos()
                    self.markSynced()
                    DispatchQueue.main.async { self.lastChangeReason = .initialSync }
                } else {
                    DispatchQueue.main.async {
                        self.pendingInitialSync = InitialSyncInfo(cloudItemCount: count, cloudBlobs: cloudBlobs)
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
            for (key, data) in cloudBlobs { defaults.set(data, forKey: key) }
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

        // 把（覆蓋／合併後的）本機資料推回雲端，並上傳本機照片
        CloudKitManager.shared.pushAllKV(keys: Self.syncKeys)
        CloudKitManager.shared.uploadAllLocalPhotos()
        markSynced()
        DispatchQueue.main.async { self.lastChangeReason = .initialSync }
    }

    /// 使用者在首次同步選項中取消 → 關回同步開關
    func cancelInitialSync() {
        pendingInitialSync = nil
        isEnabled = false
    }

    /// 計算一批 KV blob 內的資料筆數（陣列型 blob 的元素數加總）
    static func itemCount(_ blobs: [String: Data]) -> Int {
        var n = 0
        for (_, data) in blobs {
            if let arr = (try? JSONSerialization.jsonObject(with: data)) as? [Any] {
                n += arr.count
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
                self.isSyncing = false
                return
            }
            CloudKitManager.shared.bootstrap { [weak self] ok in
                // bootstrap completion 可能由 CloudKit 背景佇列呼叫，
                // 強制回主執行緒再修改 isSyncing，避免競態條件
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard ok else {
                        self.isSyncing = false
                        return
                    }
                    CloudKitManager.shared.fetchChanges { [weak self] _ in
                        CloudKitManager.shared.pushAllKV(keys: Self.syncKeys)
                        CloudKitManager.shared.uploadAllLocalPhotos()
                        DispatchQueue.main.async { [weak self] in
                            self?.isSyncing = false
                            self?.markSynced()
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
        DispatchQueue.main.async { [weak self] in
            self?.lastChangeReason = .serverChange
            self?.markSynced()
            NotificationCenter.default.post(name: .cloudSyncDidPullChanges, object: nil)
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

    private func markSynced() {
        let now = Date()
        DispatchQueue.main.async { [weak self] in
            self?.lastSyncDate = now
        }
        UserDefaults.standard.set(now, forKey: Self.lastSyncKey)
    }
}

extension Notification.Name {
    /// iCloud 拉到結構化資料變更後發送，Store 收到應重新從 UserDefaults 載入
    static let cloudSyncDidPullChanges = Notification.Name("cloudSyncDidPullChanges")
    /// iCloud 拉到照片變更後發送，UI 需重新載入圖片
    static let cloudSyncPhotosDidUpdate = Notification.Name("cloudSyncPhotosDidUpdate")
}
