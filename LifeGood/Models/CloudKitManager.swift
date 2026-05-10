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

    /// 已知的本地照片資料夾（與 LifeModels / FinanceModels / Expense 中 photosDirectory 對應）
    static let photoDirectories: [String] = [
        "FamilyAlbumPhotos",
        "ChildRecordPhotos",
        "RenovationPhotos",
        "ElevatorPhotos",
        "UtilityPhotos",
        "ExpensePhotos",
        "BusinessCardPhotos",
        "OrgPersonPhotos"
    ]

    private let container: CKContainer
    private let privateDB: CKDatabase
    private let zoneID: CKRecordZone.ID

    /// 為避免並行衝突，所有 push/pull 用同一序列佇列。
    private let queue = DispatchQueue(label: "CloudKitManager.queue", qos: .utility)

    private let defaults = UserDefaults.standard
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
                self?.defaults.set(true, forKey: self?.zoneCreatedKey ?? "")
                completion(true)
            case .failure:
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
                self?.defaults.set(true, forKey: self?.subscriptionCreatedKey ?? "")
                completion(true)
            case .failure:
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

    private func modifyKV(key: String, data: Data, completion: ((Bool) -> Void)?) {
        let recID = CKRecord.ID(recordName: "kv_\(key)", zoneID: zoneID)
        // 先抓既有 record（為了拿 recordChangeTag 避免 conflict），再覆蓋
        privateDB.fetch(withRecordID: recID) { [weak self] existing, _ in
            guard let self = self else { return }
            let record = existing ?? CKRecord(recordType: Self.kvBlobRecordType, recordID: recID)

            // JSON 寫到暫存檔做為 CKAsset
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("kv_\(key)_\(UUID().uuidString).json")
            do {
                try data.write(to: tmp, options: .atomic)
            } catch {
                completion?(false); return
            }
            record["payload"] = CKAsset(fileURL: tmp)
            record["updatedAt"] = Date() as NSDate
            record["keyName"] = key as NSString

            let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            op.savePolicy = .changedKeys
            op.qualityOfService = .utility
            op.modifyRecordsResultBlock = { result in
                try? FileManager.default.removeItem(at: tmp)
                switch result {
                case .success: completion?(true)
                case .failure: completion?(false)
                }
            }
            self.privateDB.add(op)
        }
    }

    // MARK: - 推送照片

    /// 上傳指定本地照片檔到 iCloud；若檔案不存在則跳過。
    func uploadPhoto(directory: String, fileName: String, completion: ((Bool) -> Void)? = nil) {
        guard isAvailable else { completion?(false); return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = docs.appendingPathComponent(directory).appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { completion?(false); return }

        queue.async {
            self.ensureZoneExists { ok in
                guard ok else { completion?(false); return }
                let pathKey = "\(directory)/\(fileName)"
                let recID = CKRecord.ID(recordName: "photo_\(self.sanitize(pathKey))", zoneID: self.zoneID)

                self.privateDB.fetch(withRecordID: recID) { existing, _ in
                    let record = existing ?? CKRecord(recordType: Self.photoRecordType, recordID: recID)
                    record["pathKey"] = pathKey as NSString
                    record["directory"] = directory as NSString
                    record["fileName"] = fileName as NSString
                    record["asset"] = CKAsset(fileURL: fileURL)
                    record["updatedAt"] = Date() as NSDate

                    let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
                    op.savePolicy = .changedKeys
                    op.qualityOfService = .utility
                    op.modifyRecordsResultBlock = { result in
                        switch result {
                        case .success: completion?(true)
                        case .failure: completion?(false)
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
            self.privateDB.delete(withRecordID: recID) { _, _ in
                completion?(true)
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
                        pulledKVKeys.insert(key)
                    }
                } else if record.recordType == Self.photoRecordType {
                    if let dir = record["directory"] as? String,
                       let name = record["fileName"] as? String,
                       let asset = record["asset"] as? CKAsset,
                       let url = asset.fileURL {
                        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        let dirURL = docs.appendingPathComponent(dir, isDirectory: true)
                        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                        let dest = dirURL.appendingPathComponent(name)
                        try? FileManager.default.removeItem(at: dest)
                        do {
                            try FileManager.default.copyItem(at: url, to: dest)
                            pulledPhotos.insert("\(dir)/\(name)")
                        } catch {
                            // ignore
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
                deletedPhotos.insert(name)
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
        op.fetchRecordZoneChangesResultBlock = { result in
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
                    } else {
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
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
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

    // MARK: - 接收靜默推播後

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
