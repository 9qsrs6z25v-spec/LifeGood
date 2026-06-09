import Foundation
import CloudKit
import Combine

/// 遠端管理：
/// - 全功能免費的「總開關」（CloudKit Public DB，影響所有使用者，不必改版送審）
/// - 不重複 iCloud 使用者人數統計
/// - 對外人數顯示開關 / 門檻
///
/// 設計：
/// - `AppConfig`（recordName=app_config）：allFree / showCountPublicly / countThreshold，
///   只有建立者（你的 iCloud 帳號）能寫，其他人唯讀。
/// - `GlobalStats`（recordName=global_stats）：userCount，新使用者註冊時 +1。
/// - `Installation`（recordName=inst_<iCloudUserID>）：去重用，每位 iCloud 使用者只算一次。
///
/// 所有結果都快取到 UserDefaults，離線 / 未登入 iCloud 時沿用快取，預設「全功能免費」。
final class RemoteAdminManager: ObservableObject {
    static let shared = RemoteAdminManager()

    @Published private(set) var allFree: Bool
    @Published private(set) var userCount: Int
    @Published private(set) var showCountPublicly: Bool
    @Published private(set) var countThreshold: Int
    @Published private(set) var lastError: String?
    @Published var isBusy: Bool = false

    private let container = CKContainer(identifier: "iCloud.com.lifegood.app")
    private var db: CKDatabase { container.publicCloudDatabase }
    private let configID = CKRecord.ID(recordName: "app_config")
    private let statsID  = CKRecord.ID(recordName: "global_stats")

    private let defaults = UserDefaults.standard
    private enum K {
        static let allFree     = "ra_all_free"
        static let userCount   = "ra_user_count"
        static let showPublic  = "ra_show_public"
        static let threshold   = "ra_threshold"
        static let didRegister = "ra_did_register"
        static let pin         = "ra_admin_pin"
    }
    static let defaultPIN = "0318"

    private init() {
        allFree         = defaults.object(forKey: K.allFree) as? Bool ?? true   // 預設全功能免費
        userCount       = defaults.integer(forKey: K.userCount)
        showCountPublicly = defaults.bool(forKey: K.showPublic)
        countThreshold  = defaults.object(forKey: K.threshold) as? Int ?? 1000
    }

    /// 對外是否該顯示人數（開啟 + 達門檻）
    var shouldShowPublicCount: Bool { showCountPublicly && userCount >= countThreshold }

    var adminPIN: String { defaults.string(forKey: K.pin) ?? Self.defaultPIN }
    func setAdminPIN(_ pin: String) {
        let trimmed = pin.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        defaults.set(trimmed, forKey: K.pin)
    }

    // MARK: - 啟動

    /// App 啟動時呼叫：拉設定 + 人數，並（若需要）註冊本使用者
    func bootstrap() {
        refresh()
        registerUserIfNeeded()
    }

    private func persist() {
        defaults.set(allFree, forKey: K.allFree)
        defaults.set(userCount, forKey: K.userCount)
        defaults.set(showCountPublicly, forKey: K.showPublic)
        defaults.set(countThreshold, forKey: K.threshold)
    }

    // MARK: - 讀取設定 + 人數

    func refresh() {
        let op = CKFetchRecordsOperation(recordIDs: [configID, statsID])
        op.qualityOfService = .utility
        op.perRecordResultBlock = { [weak self] recID, result in
            guard let self = self, case .success(let rec) = result else { return }
            DispatchQueue.main.async {
                if recID == self.configID {
                    if let v = rec["allFree"] as? NSNumber { self.allFree = (v.intValue != 0) }
                    if let v = rec["showCountPublicly"] as? NSNumber { self.showCountPublicly = (v.intValue != 0) }
                    if let v = rec["countThreshold"] as? NSNumber { self.countThreshold = v.intValue }
                    self.persist()
                    // 伺服器確認的免費狀態才套用到訂閱（含早鳥蓋章）
                    SubscriptionManager.shared.applyRemoteFreeAccess(self.allFree)
                } else if recID == self.statsID {
                    if let v = rec["userCount"] as? NSNumber { self.userCount = v.intValue; self.persist() }
                }
            }
        }
        db.add(op)
    }

    // MARK: - 使用者註冊（去重計數）

    func registerUserIfNeeded() {
        guard !defaults.bool(forKey: K.didRegister) else { return }
        container.fetchUserRecordID { [weak self] uid, _ in
            guard let self = self, let uid = uid else { return }
            let instID = CKRecord.ID(recordName: "inst_\(uid.recordName)")
            self.db.fetch(withRecordID: instID) { [weak self] existing, _ in
                guard let self = self else { return }
                if existing != nil {
                    // 同一位 iCloud 使用者（可能換機 / 重裝）→ 不重複計數
                    self.defaults.set(true, forKey: K.didRegister)
                    return
                }
                let rec = CKRecord(recordType: "Installation", recordID: instID)
                rec["registeredAt"] = Date() as NSDate
                let save = CKModifyRecordsOperation(recordsToSave: [rec], recordIDsToDelete: nil)
                save.savePolicy = .ifServerRecordUnchanged
                save.modifyRecordsResultBlock = { [weak self] result in
                    guard let self = self else { return }
                    switch result {
                    case .success:
                        self.defaults.set(true, forKey: K.didRegister)
                        self.incrementUserCount()
                    case .failure:
                        // 競爭或權限不足 → 視為已註冊，不再嘗試
                        self.defaults.set(true, forKey: K.didRegister)
                    }
                }
                self.db.add(save)
            }
        }
    }

    private func incrementUserCount(retriesLeft: Int = 3) {
        db.fetch(withRecordID: statsID) { [weak self] existing, _ in
            guard let self = self else { return }
            let rec = existing ?? CKRecord(recordType: "GlobalStats", recordID: self.statsID)
            let next = (((rec["userCount"] as? NSNumber)?.int64Value) ?? 0) + 1
            rec["userCount"] = next as Int64
            let save = CKModifyRecordsOperation(recordsToSave: [rec], recordIDsToDelete: nil)
            save.savePolicy = .ifServerRecordUnchanged
            save.modifyRecordsResultBlock = { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success:
                    DispatchQueue.main.async { self.userCount = Int(next); self.persist() }
                case .failure(let err):
                    // 兩位使用者同時 +1 → 重抓最新再加
                    if (err as? CKError)?.code == .serverRecordChanged, retriesLeft > 0 {
                        self.incrementUserCount(retriesLeft: retriesLeft - 1)
                    }
                }
            }
            self.db.add(save)
        }
    }

    // MARK: - 管理寫入（僅你的裝置會用到）

    func adminSetAllFree(_ value: Bool, completion: ((Bool) -> Void)? = nil) {
        writeConfig({ $0["allFree"] = (value ? 1 : 0) as Int64 }) { [weak self] ok in
            if ok {
                DispatchQueue.main.async {
                    self?.allFree = value; self?.persist()
                    SubscriptionManager.shared.applyRemoteFreeAccess(value)
                }
            }
            completion?(ok)
        }
    }

    func adminSetPublicDisplay(enabled: Bool, threshold: Int, completion: ((Bool) -> Void)? = nil) {
        writeConfig({
            $0["showCountPublicly"] = (enabled ? 1 : 0) as Int64
            $0["countThreshold"] = Int64(max(0, threshold))
        }) { [weak self] ok in
            if ok {
                DispatchQueue.main.async {
                    self?.showCountPublicly = enabled
                    self?.countThreshold = max(0, threshold)
                    self?.persist()
                }
            }
            completion?(ok)
        }
    }

    private func writeConfig(_ mutate: @escaping (CKRecord) -> Void,
                             completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { self.isBusy = true }
        db.fetch(withRecordID: configID) { [weak self] existing, _ in
            guard let self = self else { return }
            let rec = existing ?? CKRecord(recordType: "AppConfig", recordID: self.configID)
            mutate(rec)
            let op = CKModifyRecordsOperation(recordsToSave: [rec], recordIDsToDelete: nil)
            op.savePolicy = .changedKeys
            op.modifyRecordsResultBlock = { [weak self] result in
                DispatchQueue.main.async {
                    self?.isBusy = false
                    switch result {
                    case .success:
                        self?.lastError = nil
                        completion(true)
                    case .failure(let e):
                        self?.lastError = CloudKitManager.describe(e)
                        completion(false)
                    }
                }
            }
            self.db.add(op)
        }
    }
}
