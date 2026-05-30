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
                bootstrapAndPushAll()
            }
        }
    }

    // 防抖：2 秒內多次 pushAll() 合併為一次
    private var pushDebounceTimer: Timer?

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
        DispatchQueue.main.async {
            self.lastChangeReason = .accountChange
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

    /// 開啟同步時：建立 zone/subscription、把本地全推上去、首次拉取
    private func bootstrapAndPushAll() {
        CloudKitManager.shared.bootstrap { [weak self] ok in
            guard let self = self, ok else { return }
            CloudKitManager.shared.pushAllKV(keys: Self.syncKeys)
            CloudKitManager.shared.uploadAllLocalPhotos()
            self.markSynced()
            DispatchQueue.main.async {
                self.lastChangeReason = .initialSync
            }
        }
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
        if !force, let last = lastSyncDate,
           Date().timeIntervalSince(last) < 30 {
            // 30 秒內已同步，跳過
            return
        }
        CloudKitManager.shared.refreshAccountStatus { [weak self] status in
            guard let self = self else { return }
            self.updateAccountStatus(status)
            guard status == .available, self.isEnabled else { return }
            CloudKitManager.shared.bootstrap { ok in
                guard ok else { return }
                CloudKitManager.shared.fetchChanges { _ in
                    CloudKitManager.shared.pushAllKV(keys: Self.syncKeys)
                    CloudKitManager.shared.uploadAllLocalPhotos()
                    self.markSynced()
                }
            }
        }
    }

    // MARK: - Pull（被 CloudKitManager 通知）

    @objc private func handleKVChanges(_ note: Notification) {
        DispatchQueue.main.async {
            self.lastChangeReason = .serverChange
        }
        markSynced()
        // 重發舊版同名通知，所有 Store 都已監聽
        NotificationCenter.default.post(name: .cloudSyncDidPullChanges, object: nil)
    }

    @objc private func handlePhotoChanges(_ note: Notification) {
        DispatchQueue.main.async {
            self.lastChangeReason = .serverChange
            // 通知 UI 重新載入照片
            NotificationCenter.default.post(name: .cloudSyncPhotosDidUpdate, object: nil)
        }
        markSynced()
    }

    // MARK: - Helpers

    private func markSynced() {
        let now = Date()
        DispatchQueue.main.async {
            self.lastSyncDate = now
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
