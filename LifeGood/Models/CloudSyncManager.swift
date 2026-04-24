import Foundation
import Combine

/// 管理 NSUbiquitousKeyValueStore（iCloud KV Store）與本地 UserDefaults 的雙向同步。
/// 同一 Apple ID 的裝置間，啟用後資料會自動推送/拉取。
final class CloudSyncManager: ObservableObject {
    static let shared = CloudSyncManager()

    // MARK: - Keys

    /// 需要同步至 iCloud 的所有儲存 key（對應三個 Store 的 UserDefaults key）
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
        "life_grade_titles"
    ]

    private static let enabledKey = "icloud_sync_enabled"
    private static let lastSyncKey = "icloud_last_sync_date"

    // MARK: - Published State

    /// 是否開啟 iCloud 同步
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled {
                pushAllToCloud()
            }
        }
    }

    /// iCloud 帳號是否可用（使用者已登入）
    @Published private(set) var isAccountAvailable: Bool = false

    /// 最近一次成功同步的時間
    @Published private(set) var lastSyncDate: Date?

    /// 最近一次外部變更原因（顯示用）
    @Published private(set) var lastChangeReason: ChangeReason = .none

    enum ChangeReason: String {
        case none = ""
        case serverChange = "從 iCloud 收到更新"
        case initialSync = "初次同步完成"
        case quotaViolation = "超過 iCloud 配額"
        case accountChange = "iCloud 帳號已變更"
    }

    // MARK: - Private

    private let kvStore = NSUbiquitousKeyValueStore.default
    private var observer: NSObjectProtocol?

    // MARK: - Init

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        if let date = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date {
            self.lastSyncDate = date
        }

        updateAccountStatus()

        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore,
            queue: .main
        ) { [weak self] note in
            self?.handleExternalChange(note)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ubiquityIdentityDidChange),
            name: .NSUbiquityIdentityDidChange,
            object: nil
        )

        kvStore.synchronize()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - Status

    func updateAccountStatus() {
        isAccountAvailable = FileManager.default.ubiquityIdentityToken != nil
    }

    @objc private func ubiquityIdentityDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.updateAccountStatus()
            self?.lastChangeReason = .accountChange
        }
    }

    // MARK: - Push

    /// 單一 key 的變更推送至 iCloud（Store save() 後呼叫）
    func push(key: String) {
        guard isEnabled, isAccountAvailable else { return }
        guard Self.syncKeys.contains(key) else { return }
        if let data = UserDefaults.standard.data(forKey: key) {
            kvStore.set(data, forKey: key)
        } else {
            kvStore.removeObject(forKey: key)
        }
        kvStore.synchronize()
        markSynced()
    }

    /// 任何 Store 的 save() 都會觸發：將所有 sync key 一次推送
    func pushAll() {
        guard isEnabled, isAccountAvailable else { return }
        for key in Self.syncKeys {
            if let data = UserDefaults.standard.data(forKey: key) {
                kvStore.set(data, forKey: key)
            }
        }
        kvStore.synchronize()
        markSynced()
    }

    /// 開啟同步時，立即將目前所有本地資料推送至 iCloud
    private func pushAllToCloud() {
        guard isAccountAvailable else { return }
        for key in Self.syncKeys {
            if let data = UserDefaults.standard.data(forKey: key) {
                kvStore.set(data, forKey: key)
            }
        }
        kvStore.synchronize()
        markSynced()
    }

    /// 手動觸發同步（下拉 iCloud 並推送本地）
    func syncNow() {
        updateAccountStatus()
        guard isAccountAvailable else { return }
        kvStore.synchronize()
        if isEnabled {
            pushAllToCloud()
        }
    }

    // MARK: - Pull

    private func handleExternalChange(_ note: Notification) {
        guard let userInfo = note.userInfo else { return }

        if let reasonRaw = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int {
            switch reasonRaw {
            case NSUbiquitousKeyValueStoreServerChange:
                lastChangeReason = .serverChange
            case NSUbiquitousKeyValueStoreInitialSyncChange:
                lastChangeReason = .initialSync
            case NSUbiquitousKeyValueStoreQuotaViolationChange:
                lastChangeReason = .quotaViolation
            case NSUbiquitousKeyValueStoreAccountChange:
                lastChangeReason = .accountChange
            default:
                break
            }
        }

        guard isEnabled,
              let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
        else { return }

        var pulledAny = false
        for key in changedKeys where Self.syncKeys.contains(key) {
            if let data = kvStore.data(forKey: key) {
                UserDefaults.standard.set(data, forKey: key)
                pulledAny = true
            } else {
                UserDefaults.standard.removeObject(forKey: key)
                pulledAny = true
            }
        }

        if pulledAny {
            markSynced()
            NotificationCenter.default.post(name: .cloudSyncDidPullChanges, object: nil)
        }
    }

    // MARK: - Helpers

    private func markSynced() {
        let now = Date()
        lastSyncDate = now
        UserDefaults.standard.set(now, forKey: Self.lastSyncKey)
    }
}

extension Notification.Name {
    /// iCloud 拉到外部變更後發送，Store 收到應重新從 UserDefaults 載入
    static let cloudSyncDidPullChanges = Notification.Name("cloudSyncDidPullChanges")
}
