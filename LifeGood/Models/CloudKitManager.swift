import Foundation
import CloudKit
import Combine
import UIKit

/// 把 LifeGood 全部資料（結構化資料 + 使用者上傳照片）放到 iCloud Private Database。
///
/// 設計概念：
/// - 結構化資料：每一個 `UserDefaults` key 對應一筆 record（type = `KVBlob`），
///   JSON 內容存在 `payload` (CKAsset) 欄位，避免 1MB 欄位上限。
/// - 照片：每張照片一筆 record（type = `Photo`），檔案以 CKAsset 上傳，
///   `pathKey` 為 `<directory>/<fileName>`。
/// - 使用自訂 zone (`LifeGoodZone`) 才能跑 `CKFetchRecordZoneChangesOperation`
///   做增量同步，並訂閱 zone 變更推播。
final class CloudKitManager {
    static let shared = CloudKitManager()

    static let containerID = "iCloud.com.lifegood.app"
    static let zoneName = "LifeGoodZone"
    static let kvBlobRecordType = "KVBlob"
    static let photoRecordType = "Photo"
    static let zoneSubscriptionID = "LifeGoodZoneSub"

    /// 內部使用的通知（給 CloudSyncManager 收）
    static let didPullKVChangesNotification = Notification.Name("CloudKitManager.didPullKVChanges")
    static let didPullPhotoChangesNotification = Notification.Name("CloudKitManager.didPullPhotoChanges")
    static let accountStatusDidChangeNotification = Notification.Name("CloudKitManager.accountStatusDidChange")
    /// 任何 CloudKit 操作失敗時發送，userInfo["message"] 為可讀錯誤字串（給 SettingsView 顯示）
    static let didEncounterErrorNotification = Notification.Name("CloudKitManager.didEncounterError")

    /// 已知的本地照片資料夾（與 LifeModels / FinanceModels / Expense 中 photosDirectory 對應）
    static let photoDirectories: [String] = [
        "FamilyAlbumPhotos",
        "ChildRecordPhotos",
        "RenovationPhotos",
        "ElevatorPhotos",
        "UtilityPhotos",
        "ExpensePhotos",
        "BusinessCardPhotos",
        "OrgPersonPhotos",
        "RealEstateDocuments"
    ]

    private let container: CKContainer
    private let privateDB: CKDatabase
    private let zoneID: CKRecordZone.ID

    /// 為避免並行衝突，所有 push/pull 用同一序列佇列。
    private let queue = DispatchQueue(label: "CloudKitManager.queue", qos: .utility)

    private let defaults = UserDefaults.standard
    private let fetchLock = NSLock()
    private let zoneCreatedKey = "ck_zone_created"
    private let subscriptionCreatedKey = "ck_zone_sub_created"
    private let serverChangeTokenKey = "ck_server_change_token"
    private let initialPullDoneKey = "ck_initial_pull_done"

    private(set) var accountStatus: CKAccountStatus = .couldNotDetermine

    private init() {
        self.container = CKContainer(identifier: Self.containerID)
        self.privateDB = container.privateCloudDatabase
        self.zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)

        NotificationCenter.default.addObserver(
            self, selector: #selector(accountChanged),
            name: .CKAccountChanged, object: nil
        )
    }

    // MARK: - 帳號狀態

    @objc private func accountChanged() {
        refreshAccountStatus { _ in }
    }

    func refreshAccountStatus(completion: @escaping (CKAccountStatus) -> Void) {
        container.accountStatus { [weak self] status, _ in
            guard let self = self else { completion(.couldNotDetermine); return }
            self.accountStatus = status
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.accountStatusDidChangeNotification, object: nil)
                completion(status)
            }
        }
    }

    var isAvailable: Bool { accountStatus == .available }

    // MARK: - 啟動：建立 zone + 訂閱 + 拉取所有變更

    func bootstrap(completion: ((Bool) -> Void)? = nil) {
        refreshAccountStatus { [weak self] status in
            guard let self = self, status == .available else {
                completion?(false); return
            }
            self.queue.async {
                self.ensureZoneExists { ok in
                    guard ok else { completion?(false); return }
                    self.ensureSubscriptionExists { _ in
                        self.fetchChanges { _ in
                            completion?(true)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Zone

    private func ensureZoneExists(completion: @escaping (Bool) -> Void) {
        if defaults.bool(forKey: zoneCreatedKey) { completion(true); return }
        let zone = CKRecordZone(zoneID: zoneID)
        let op = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
        op.qualityOfService = .utility
        op.modifyRecordZonesResultBlock = { [weak self] result in
            switch result {
            case .success:
                if let self = self {
                    self.defaults.set(true, forKey: self.zoneCreatedKey)
                }
                completion(true)
            case .failure(let error):
                self?.report(error, context: "建立 iCloud 資料區")
                completion(false)
            }
        }
        privateDB.add(op)
    }

    // MARK: - Subscription（zone 變更靜默推播）

    private func ensureSubscriptionExists(completion: @escaping (Bool) -> Void) {
        if defaults.bool(forKey: subscriptionCreatedKey) { completion(true); return }
        let sub = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: Self.zoneSubscriptionID)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        sub.notificationInfo = info

        let op = CKModifySubscriptionsOperation(subscriptionsToSave: [sub], subscriptionIDsToDelete: nil)
        op.qualityOfService = .utility
        op.modifySubscriptionsResultBlock = { [weak self] result in
            switch result {
            case .success:
                if let self = self {
                    self.defaults.set(true, forKey: self.subscriptionCreatedKey)
                }
                completion(true)
            case .failure(let error):
                self?.report(error, context: "建立 iCloud 訂閱")
                completion(false)
            }
        }
        privateDB.add(op)
    }

    // MARK: - 推送結構化 KV blob

    /// 把指定 UserDefaults key 的資料推到 iCloud。
    func pushKV(key: String, data: Data, completion: ((Bool) -> Void)? = nil) {
        guard isAvailable else { completion?(false); return }
        queue.async {
            self.ensureZoneExists { ok in
                guard ok else { completion?(false); return }
                self.modifyKV(key: key, data: data, completion: completion)
            }
        }
    }

    private func modifyKV(key: String, data: Data, retriesLeft: Int = 1, completion: ((Bool) -> Void)?) {
        let recID = CKRecord.ID(recordName: "kv_\(key)", zoneID: zoneID)
        // 先抓既有 record（為了拿 recordChangeTag 避免 conflict），再覆蓋
        privateDB.fetch(withRecordID: recID) { [weak self] existing, fetchError in
            guard let self = self else { return }
            // fetch 失敗但「不是查無此筆」→ 真錯誤，回報後結束
            if existing == nil, let fe = fetchError as? CKError, fe.code != .unknownItem {
                self.report(fe, context: "上傳 \(key)")
                completion?(false); return
            }
            let record = existing ?? CKRecord(recordType: Self.kvBlobRecordType, recordID: recID)

            // JSON 寫到暫存檔做為 CKAsset
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("kv_\(key)_\(UUID().uuidString).json")
            do {
                try data.write(to: tmp, options: .atomic)
            } catch {
                self.report(error, context: "上傳 \(key)")
                completion?(false); return
            }
            record["payload"] = CKAsset(fileURL: tmp)
            record["updatedAt"] = Date() as NSDate
            record["keyName"] = key as NSString

            let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            op.savePolicy = .changedKeys
            op.qualityOfService = .utility
            op.modifyRecordsResultBlock = { [weak self] result in
                try? FileManager.default.removeItem(at: tmp)
                switch result {
                case .success:
                    completion?(true)
                case .failure(let error):
                    // 兩台同時改同一筆 → 重新抓最新版本再覆蓋一次（整份快照，last-writer-wins）
                    if Self.isServerRecordChanged(error), retriesLeft > 0 {
                        self?.modifyKV(key: key, data: data, retriesLeft: retriesLeft - 1, completion: completion)
                    } else {
                        self?.report(error, context: "上傳 \(key)")
                        completion?(false)
                    }
                }
            }
            self.privateDB.add(op)
        }
    }

    // MARK: - 推送照片

    /// 上傳指定本地照片檔到 iCloud；若檔案不存在則跳過。
    func uploadPhoto(directory: String, fileName: String, completion: ((Bool) -> Void)? = nil) {
        guard isAvailable else { completion?(false); return }
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            completion?(false); return
        }
        let fileURL = docs.appendingPathComponent(directory).appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { completion?(false); return }

        queue.async {
            self.ensureZoneExists { ok in
                guard ok else { completion?(false); return }
                let pathKey = "\(directory)/\(fileName)"
                let recID = CKRecord.ID(recordName: "photo_\(self.sanitize(pathKey))", zoneID: self.zoneID)

                self.privateDB.fetch(withRecordID: recID) { [weak self] existing, _ in
                    guard let self else { completion?(false); return }
                    let record = existing ?? CKRecord(recordType: Self.photoRecordType, recordID: recID)
                    record["pathKey"] = pathKey as NSString
                    record["directory"] = directory as NSString
                    record["fileName"] = fileName as NSString
                    record["asset"] = CKAsset(fileURL: fileURL)
                    record["updatedAt"] = Date() as NSDate

                    let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
                    op.savePolicy = .changedKeys
                    op.qualityOfService = .utility
                    op.modifyRecordsResultBlock = { [weak self] result in
                        switch result {
                        case .success: completion?(true)
                        case .failure(let error):
                            self?.report(error, context: "上傳照片 \(fileName)")
                            completion?(false)
                        }
                    }
                    self.privateDB.add(op)
                }
            }
        }
    }

    /// 從 iCloud 刪除一張照片紀錄。
    func deletePhoto(directory: String, fileName: String, completion: ((Bool) -> Void)? = nil) {
        guard isAvailable else { completion?(false); return }
        queue.async {
            let pathKey = "\(directory)/\(fileName)"
            let recID = CKRecord.ID(recordName: "photo_\(self.sanitize(pathKey))", zoneID: self.zoneID)
            self.privateDB.delete(withRecordID: recID) { _, error in
                completion?(error == nil)
            }
        }
    }

    // MARK: - 增量拉取

    /// 抓取 zone 中所有自上次以來的變更（KV + Photo）。
    func fetchChanges(completion: ((Bool) -> Void)? = nil) {
        guard isAvailable else { completion?(false); return }
        queue.async {
            self.ensureZoneExists { ok in
                guard ok else { completion?(false); return }
                self.runFetch(completion: completion)
            }
        }
    }

    private func runFetch(completion: ((Bool) -> Void)?) {
        var token: CKServerChangeToken? = loadChangeToken()
        let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration(
            previousServerChangeToken: token,
            resultsLimit: nil, desiredKeys: nil
        )
        let op = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zoneID],
            configurationsByRecordZoneID: [zoneID: configuration]
        )
        op.qualityOfService = .utility
        op.fetchAllChanges = true

        var pulledKVKeys = Set<String>()
        var pulledPhotos = Set<String>() // pathKey
        var deletedPhotos = Set<String>() // pathKey
        let lock = self.fetchLock

        op.recordWasChangedBlock = { [weak self] _, result in
            guard let self = self else { return }
            switch result {
            case .success(let record):
                if record.recordType == Self.kvBlobRecordType {
                    if let key = record["keyName"] as? String,
                       let asset = record["payload"] as? CKAsset,
                       let url = asset.fileURL,
                       let data = try? Data(contentsOf: url) {
                        self.defaults.set(data, forKey: key)
                        lock.lock(); pulledKVKeys.insert(key); lock.unlock()
                    }
                } else if record.recordType == Self.photoRecordType {
                    if let dir = record["directory"] as? String,
                       let name = record["fileName"] as? String,
                       let asset = record["asset"] as? CKAsset,
                       let url = asset.fileURL,
                       let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                        let dirURL = docs.appendingPathComponent(dir, isDirectory: true)
                        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                        let dest = dirURL.appendingPathComponent(name)
                        try? FileManager.default.removeItem(at: dest)
                        do {
                            try FileManager.default.copyItem(at: url, to: dest)
                            lock.lock(); pulledPhotos.insert("\(dir)/\(name)"); lock.unlock()
                        } catch {
                            self.report(error, context: "寫入照片 \(dir)/\(name)")
                        }
                    }
                }
            case .failure:
                break
            }
        }

        op.recordWithIDWasDeletedBlock = { recID, _ in
            // 只能由 recordName 判斷種類
            let name = recID.recordName
            if name.hasPrefix("photo_") {
                // 對應的 pathKey 不易回推（已 sanitize），靠檔案系統清掃法處理
                lock.lock(); deletedPhotos.insert(name); lock.unlock()
            }
        }

        op.recordZoneChangeTokensUpdatedBlock = { [weak self] _, newToken, _ in
            if let newToken = newToken { self?.saveChangeToken(newToken) }
        }
        op.recordZoneFetchResultBlock = { [weak self] _, result in
            if case .success(let success) = result {
                token = success.serverChangeToken
                if let t = token { self?.saveChangeToken(t) }
            }
        }
        op.fetchRecordZoneChangesResultBlock = { [weak self] result in
            guard let self = self else { completion?(false); return }
            DispatchQueue.main.async {
                if !pulledKVKeys.isEmpty {
                    NotificationCenter.default.post(
                        name: Self.didPullKVChangesNotification, object: nil,
                        userInfo: ["keys": Array(pulledKVKeys)]
                    )
                }
                if !pulledPhotos.isEmpty || !deletedPhotos.isEmpty {
                    NotificationCenter.default.post(
                        name: Self.didPullPhotoChangesNotification, object: nil,
                        userInfo: ["pulled": Array(pulledPhotos), "deletedRecords": Array(deletedPhotos)]
                    )
                }
                switch result {
                case .success: completion?(true)
                case .failure(let err):
                    // 若 server change token expired → 清除重抓
                    if let ck = err as? CKError, ck.code == .changeTokenExpired {
                        self.clearChangeToken()
                        self.fetchChanges(completion: completion)
                    } else if let ck = err as? CKError, ck.code == .zoneNotFound || ck.code == .userDeletedZone {
                        // zone 被刪 → 清掉本地旗標讓下次重建
                        self.defaults.removeObject(forKey: self.zoneCreatedKey)
                        self.defaults.removeObject(forKey: self.subscriptionCreatedKey)
                        self.clearChangeToken()
                        self.report(err, context: "拉取雲端變更")
                        completion?(false)
                    } else {
                        self.report(err, context: "拉取雲端變更")
                        completion?(false)
                    }
                }
            }
        }

        privateDB.add(op)
    }

    // MARK: - 一次性：把所有本地照片掃描後上傳（確保歷史檔案不漏）

    func uploadAllLocalPhotos(completion: (() -> Void)? = nil) {
        guard isAvailable else { completion?(); return }
        queue.async {
            guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                completion?(); return
            }
            for dir in Self.photoDirectories {
                let url = docs.appendingPathComponent(dir, isDirectory: true)
                guard let files = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { continue }
                for f in files where !f.hasPrefix(".") {
                    self.uploadPhoto(directory: dir, fileName: f)
                }
            }
            completion?()
        }
    }

    // MARK: - 一次性：把所有 UserDefaults blob 推到 iCloud

    func pushAllKV(keys: [String]) {
        guard isAvailable else { return }
        for key in keys {
            if let data = defaults.data(forKey: key) {
                pushKV(key: key, data: data)
            }
        }
    }

    /// 非破壞性地把雲端所有 KVBlob 讀進記憶體：不寫入本機 UserDefaults、也不更新 change token。
    /// 給「首次開啟同步」的覆蓋／合併決策使用（需要先知道雲端有什麼、有多少）。
    func fetchAllKVToMemory(completion: @escaping ([String: Data]) -> Void) {
        guard isAvailable else { completion([:]); return }
        queue.async {
            self.ensureZoneExists { ok in
                guard ok else { DispatchQueue.main.async { completion([:]) }; return }
                // previousServerChangeToken: nil → 整批拉取；且刻意不保存回傳 token，保持非破壞性
                let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration(
                    previousServerChangeToken: nil, resultsLimit: nil, desiredKeys: nil)
                let op = CKFetchRecordZoneChangesOperation(
                    recordZoneIDs: [self.zoneID],
                    configurationsByRecordZoneID: [self.zoneID: config])
                op.qualityOfService = .userInitiated
                op.fetchAllChanges = true
                var result: [String: Data] = [:]
                let lock = NSLock()
                op.recordWasChangedBlock = { _, res in
                    if case .success(let record) = res,
                       record.recordType == Self.kvBlobRecordType,
                       let key = record["keyName"] as? String,
                       let asset = record["payload"] as? CKAsset,
                       let url = asset.fileURL,
                       let data = try? Data(contentsOf: url) {
                        lock.lock(); result[key] = data; lock.unlock()
                    }
                }
                op.fetchRecordZoneChangesResultBlock = { _ in
                    DispatchQueue.main.async { completion(result) }
                }
                self.privateDB.add(op)
            }
        }
    }

    /// 由 AppDelegate / SwiftUI 接到 silent push 時呼叫
    func handleRemoteNotification(userInfo: [AnyHashable: Any], completion: @escaping (UIBackgroundFetchResult) -> Void) {
        let notif = CKNotification(fromRemoteNotificationDictionary: userInfo)
        guard notif != nil else { completion(.noData); return }
        fetchChanges { ok in
            completion(ok ? .newData : .failed)
        }
    }

    // MARK: - 重置（測試 / 切換帳號用）

    func resetLocalState() {
        defaults.removeObject(forKey: zoneCreatedKey)
        defaults.removeObject(forKey: subscriptionCreatedKey)
        defaults.removeObject(forKey: serverChangeTokenKey)
        defaults.removeObject(forKey: initialPullDoneKey)
    }

    // MARK: - 錯誤回報（把過去被吞掉的 CloudKit 失敗變成可見訊息）

    /// 把錯誤翻成可讀中文並廣播 + DEBUG console 印出。nil 代表沒有錯誤。
    func report(_ error: Error?, context: String) {
        guard let error = error else { return }
        let msg = Self.describe(error)
        #if DEBUG
        print("☁️ CloudKit 錯誤[\(context)]：\(msg)　原始：\(error)")
        #endif
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.didEncounterErrorNotification, object: nil,
                userInfo: ["message": "\(context)：\(msg)"]
            )
        }
    }

    /// 把 CKError 轉成使用者看得懂的描述
    static func describe(_ error: Error) -> String {
        guard let ck = error as? CKError else { return error.localizedDescription }
        switch ck.code {
        case .networkUnavailable, .networkFailure:        return "網路無法連線"
        case .notAuthenticated:                           return "未登入 iCloud，或 iCloud Drive 未開啟"
        case .quotaExceeded:                              return "iCloud 儲存空間不足"
        case .zoneNotFound, .userDeletedZone:             return "iCloud 資料區不存在（將重建）"
        case .changeTokenExpired:                         return "同步標記過期（將重新整批拉取）"
        case .serverRecordChanged:                        return "兩台裝置同時修改了同一筆資料"
        case .permissionFailure:                          return "iCloud 權限不足"
        case .managedAccountRestricted:                   return "此 iCloud 帳號受限制"
        case .requestRateLimited, .serviceUnavailable, .zoneBusy:
                                                          return "iCloud 暫時忙碌，稍後會自動重試"
        case .partialFailure:
            if let first = ck.partialErrorsByItemID?.values.compactMap({ $0 as? CKError }).first {
                return describe(first)
            }
            return "部分資料同步失敗"
        default:                                          return ck.localizedDescription
        }
    }

    /// 是否為「伺服器上的版本較新」衝突（含 partialFailure 內層）
    static func isServerRecordChanged(_ error: Error) -> Bool {
        guard let ck = error as? CKError else { return false }
        if ck.code == .serverRecordChanged { return true }
        if ck.code == .partialFailure,
           let byID = ck.partialErrorsByItemID {
            return byID.values.contains { ($0 as? CKError)?.code == .serverRecordChanged }
        }
        return false
    }

    // MARK: - Helpers

    private func sanitize(_ s: String) -> String {
        // CKRecord.ID name 限制：英數 _ - .，不可 / 開頭
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-.")
        return String(s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }

    private func saveChangeToken(_ token: CKServerChangeToken) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            defaults.set(data, forKey: serverChangeTokenKey)
        }
    }

    private func loadChangeToken() -> CKServerChangeToken? {
        guard let data = defaults.data(forKey: serverChangeTokenKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func clearChangeToken() {
        defaults.removeObject(forKey: serverChangeTokenKey)
    }

    var hasInitialPull: Bool {
        get { defaults.bool(forKey: initialPullDoneKey) }
        set { defaults.set(newValue, forKey: initialPullDoneKey) }
    }
}

// MARK: - 模型 photo helpers 用的單一入口

/// 由 LifeModels / FinanceModels 中各 `savePhoto` / `deletePhoto` 呼叫。
/// 本身 thread-safe，未開啟 iCloud 同步時為 no-op。
enum PhotoCloudSync {
    static func upload(directory: String, fileName: String) {
        guard CloudSyncManager.shared.isEnabled else { return }
        CloudKitManager.shared.uploadPhoto(directory: directory, fileName: fileName)
    }

    static func delete(directory: String, fileName: String) {
        guard CloudSyncManager.shared.isEnabled else { return }
        CloudKitManager.shared.deletePhoto(directory: directory, fileName: fileName)
    }
}
