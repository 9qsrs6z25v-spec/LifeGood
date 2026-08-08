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
    /// 是否已有一輪 fetchChanges 正在進行中。`queue` 只序列化「送出操作」那一刻，
    /// ensureZoneExists／CKFetchRecordZoneChangesOperation 的完成回呼落在 CloudKit 自己的
    /// 佇列上，並不會被 `queue` 擋住；若 CloudSyncManager.performSync（30 秒節流）與
    /// handleRemoteNotification（silent push，未經過 CloudSyncManager.isSyncing 守衛）
    /// 前後腳呼叫，兩個 CKFetchRecordZoneChangesOperation 會針對同一個 zone 並行拉取，
    /// 各自獨立存檔 change token 並各自觸發 Store reload。這裡補上旗標，讓後到的呼叫直接
    /// 視為失敗跳過，只保留最先開始的那一輪。
    private var isFetching = false
    private let zoneCreatedKey = "ck_zone_created"
    private let subscriptionCreatedKey = "ck_zone_sub_created"
    private let serverChangeTokenKey = "ck_server_change_token"
    private let initialPullDoneKey = "ck_initial_pull_done"

    // accountStatus 由 accountChanged/refreshAccountStatus 在主執行緒寫入，
    // 但 isAvailable 被 queue（背景 utility 佇列）上的 push/pull 大量讀取，
    // 加鎖避免跨執行緒讀寫同一屬性的競態條件。
    private let statusLock = NSLock()
    private var _accountStatus: CKAccountStatus = .couldNotDetermine
    private(set) var accountStatus: CKAccountStatus {
        get { statusLock.lock(); defer { statusLock.unlock() }; return _accountStatus }
        set { statusLock.lock(); _accountStatus = newValue; statusLock.unlock() }
    }

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
            // 將寫入統一移到主執行緒，消除背景執行緒與主執行緒並行讀寫 accountStatus 的競態條件
            DispatchQueue.main.async {
                self.accountStatus = status
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

            // JSON 寫到暫存檔做為 CKAsset；使用確定性檔名（不含 UUID），
            // 若行程在 write 後、cleanup 前被 kill，下次上傳同一 key 會直接覆蓋舊檔，
            // 避免 UUID 命名造成孤兒檔無限累積。queue 為 serial，同一 key 不會並行上傳。
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("kv_\(key).json")
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
                    // 延遲 0.5s 再重試，避免立即重打造成 CloudKit rate-limit
                    if Self.isServerRecordChanged(error), retriesLeft > 0 {
                        self?.queue.asyncAfter(deadline: .now() + 0.5) {
                            self?.modifyKV(key: key, data: data, retriesLeft: retriesLeft - 1, completion: completion)
                        }
                    } else if let ck = error as? CKError,
                              ck.code == .zoneNotFound || ck.code == .userDeletedZone,
                              retriesLeft > 0 {
                        // zone 不存在（常見於「zone 已建立」快取旗標與目前環境不符：
                        // 例如 Xcode 開發版建過 Development zone、TestFlight/App Store 版
                        // 讀到同一個旗標而跳過 Production zone 建立）→ 清旗標重建後重推一次
                        guard let self else { completion?(false); return }
                        self.defaults.removeObject(forKey: self.zoneCreatedKey)
                        self.defaults.removeObject(forKey: self.subscriptionCreatedKey)
                        self.queue.async {
                            self.ensureZoneExists { ok in
                                guard ok else { completion?(false); return }
                                self.modifyKV(key: key, data: data, retriesLeft: retriesLeft - 1, completion: completion)
                            }
                        }
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
    func uploadPhoto(directory: String, fileName: String, retryOnZoneMissing: Bool = true, completion: ((Bool) -> Void)? = nil) {
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

                self.privateDB.fetch(withRecordID: recID) { [weak self] existing, fetchError in
                    guard let self else { completion?(false); return }
                    // fetch 失敗但「不是查無此筆」→ 真錯誤；若仍繼續存空 CKRecord 會因
                    // 缺少 recordChangeTag 而觸發不必要的 .serverRecordChanged 衝突
                    if existing == nil, let fe = fetchError as? CKError, fe.code != .unknownItem {
                        self.report(fe, context: "上傳照片 \(fileName)")
                        completion?(false); return
                    }
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
                            if let ck = error as? CKError,
                               ck.code == .zoneNotFound || ck.code == .userDeletedZone,
                               retryOnZoneMissing,
                               let self {
                                // zone 不存在（快取旗標與目前環境不符）→ 清旗標重建後重傳一次
                                // （同型修法見 modifyKV zoneNotFound 分支）
                                self.defaults.removeObject(forKey: self.zoneCreatedKey)
                                self.defaults.removeObject(forKey: self.subscriptionCreatedKey)
                                self.queue.async {
                                    self.ensureZoneExists { ok in
                                        guard ok else { completion?(false); return }
                                        self.uploadPhoto(directory: directory, fileName: fileName, retryOnZoneMissing: false, completion: completion)
                                    }
                                }
                            } else {
                                self?.report(error, context: "上傳照片 \(fileName)")
                                completion?(false)
                            }
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
            guard !self.isFetching else { completion?(false); return }
            self.isFetching = true
            let wrapped: (Bool) -> Void = { ok in
                self.queue.async { self.isFetching = false }
                completion?(ok)
            }
            self.ensureZoneExists { ok in
                guard ok else { wrapped(false); return }
                self.runFetch(completion: wrapped)
            }
        }
    }

    private func runFetch(retriesLeft: Int = 1, completion: ((Bool) -> Void)?) {
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
                        // 推播的變更可能是本裝置剛推送的內容原樣回彈（CloudKit 的 server change token
                        // 只在拉取時前進，推送後緊接的下一次拉取一定會看到自己剛寫入的 record）。
                        // 若內容與本地已存的完全相同，視為 echo，跳過寫入與通知，避免各 Store 收到
                        // 「已變更」的 key 而整批 reload 未變動的資料，造成畫面閃爍。
                        if self.defaults.data(forKey: key) != data {
                            self.defaults.set(data, forKey: key)
                            lock.lock(); pulledKVKeys.insert(key); lock.unlock()
                        }
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
                        // 與上方 KVBlob 分支同理：本裝置剛推送的照片，下一次節流拉取幾乎必然把
                        // 自己剛寫入、內容其實沒變的同一張照片也算成「已變更」而回彈。寫入前先比對
                        // 內容是否與本機既有檔案相同，相同則視為 echo 跳過，避免無謂的磁碟 I/O 與
                        // SettingsView「從 iCloud 收到更新」提示無故閃爍。
                        let downloadedData = try? Data(contentsOf: url)
                        let existingData = try? Data(contentsOf: dest)
                        if downloadedData != nil && downloadedData == existingData {
                            // echo：內容相同，不動作
                        } else {
                            try? FileManager.default.removeItem(at: dest)
                            do {
                                try FileManager.default.copyItem(at: url, to: dest)
                                lock.lock(); pulledPhotos.insert("\(dir)/\(name)"); lock.unlock()
                            } catch {
                                self.report(error, context: "寫入照片 \(dir)/\(name)")
                            }
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
                switch result {
                case .success:
                    // 成功：資料完整，才發通知觸發各 Store reload
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
                    completion?(true)
                case .failure(let err):
                    if let ck = err as? CKError, ck.code == .changeTokenExpired {
                        // token 過期：不發部分資料通知，避免以不完整資料觸發 Store reload 造成畫面閃爍；
                        // 清掉 token 後重抓完整變更，retry 成功時才一次性發通知。
                        // 限制重試次數，防止 token 持續失效時的無限遞迴。
                        self.clearChangeToken()
                        if retriesLeft > 0 {
                            self.queue.async { self.runFetch(retriesLeft: retriesLeft - 1, completion: completion) }
                        } else {
                            self.report(err, context: "拉取雲端變更（token 反覆過期）")
                            completion?(false)
                        }
                    } else if let ck = err as? CKError, ck.code == .zoneNotFound || ck.code == .userDeletedZone {
                        // zone 被刪 → 清掉本地旗標讓下次重建；已拉取的部分資料仍發通知
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
                        self.defaults.removeObject(forKey: self.zoneCreatedKey)
                        self.defaults.removeObject(forKey: self.subscriptionCreatedKey)
                        self.clearChangeToken()
                        self.report(err, context: "拉取雲端變更")
                        completion?(false)
                    } else {
                        // 其他錯誤：已拉取的部分資料仍發通知
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
            // 等每張照片實際上傳完成才回呼，而非僅等排隊迴圈跑完；
            // 否則呼叫端會誤以為「上傳全部完成」而提早重置同步中旗標。
            let group = DispatchGroup()
            for dir in Self.photoDirectories {
                let url = docs.appendingPathComponent(dir, isDirectory: true)
                guard let files = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { continue }
                for f in files where !f.hasPrefix(".") {
                    group.enter()
                    self.uploadPhoto(directory: dir, fileName: f) { _ in group.leave() }
                }
            }
            group.notify(queue: .main) { completion?() }
        }
    }

    // MARK: - 一次性：把所有 UserDefaults blob 推到 iCloud

    /// - Parameter completion: 全部 key 皆推送成功才回傳 true；任一失敗即 false。
    ///   呼叫端可用此結果判斷是否要標記「已同步」，避免把失敗的一輪誤標成功。
    func pushAllKV(keys: [String], completion: ((Bool) -> Void)? = nil) {
        guard isAvailable else { completion?(false); return }
        let group = DispatchGroup()
        let lock = NSLock()
        var allOK = true
        for key in keys {
            if let data = defaults.data(forKey: key) {
                group.enter()
                pushKV(key: key, data: data) { ok in
                    if !ok {
                        lock.lock(); allOK = false; lock.unlock()
                    }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { completion?(allOK) }
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
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else { completion(.noData); return }
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

    // CKRecord.ID name 限制：英數 _ - .，不可 / 開頭
    private static let ckRecordIDAllowedCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-."
    )

    private func sanitize(_ s: String) -> String {
        return String(s.unicodeScalars.map {
            Self.ckRecordIDAllowedCharacters.contains($0) ? Character($0) : "_"
        })
    }

    // MARK: - 雲端驗證（設定頁「驗證雲端資料」）

    /// 雲端抽查結果：結構化資料筆數 + 最近照片抽查 + 伺服器端最後修改時間
    struct CloudVerifyResult {
        var kvFound = 0                 // 伺服器上找到的 KVBlob 筆數
        var kvTotal = 0                 // 本機有資料、應該在雲端的 KVBlob 筆數
        var latestKVDate: Date?         // 伺服器端最新一筆資料的修改時間
        var photoFound = 0              // 抽查照片中伺服器上找到的張數
        var photoChecked = 0            // 抽查張數（本機最近 N 張）
        var latestPhotoDate: Date?      // 伺服器端最新一張照片的修改時間
        var errorMessage: String?
    }

    /// 直接向 iCloud 伺服器抽查驗證：本機有資料的 syncKeys 對應 KVBlob 記錄是否存在、
    /// 本機最近 N 張照片對應的 Photo 記錄是否存在，並回報伺服器端的最後修改時間。
    /// 只抓記錄中繼資料（不下載 CKAsset 本體），流量極小；完成後回主執行緒。
    func verifyCloudData(keys: [String], samplePhotoLimit: Int = 5,
                         completion: @escaping (CloudVerifyResult) -> Void) {
        guard isAvailable else {
            completion(CloudVerifyResult(errorMessage: "iCloud 帳號未登入或不可用"))
            return
        }
        // 只驗證本機真的有資料的 key（沒用過的功能本來就不會有雲端記錄）
        let localKeys = keys.filter { defaults.data(forKey: $0) != nil }
        var ids: [CKRecord.ID] = localKeys.map { CKRecord.ID(recordName: "kv_\($0)", zoneID: zoneID) }

        // 本機各照片資料夾中最近修改的 N 張，抽查其雲端 Photo 記錄
        var photoPathKeys: [String] = []
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            var candidates: [(path: String, date: Date)] = []
            for dir in Self.photoDirectories {
                let dirURL = docs.appendingPathComponent(dir, isDirectory: true)
                guard let files = try? FileManager.default.contentsOfDirectory(
                    at: dirURL, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
                for f in files where f.pathExtension.lowercased() == "jpg" {
                    let d = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                    candidates.append(("\(dir)/\(f.lastPathComponent)", d))
                }
            }
            photoPathKeys = candidates.sorted { $0.date > $1.date }.prefix(samplePhotoLimit).map(\.path)
        }
        ids.append(contentsOf: photoPathKeys.map { CKRecord.ID(recordName: "photo_\(sanitize($0))", zoneID: zoneID) })

        guard !ids.isEmpty else {
            completion(CloudVerifyResult(errorMessage: "本機尚無可驗證的資料"))
            return
        }

        var result = CloudVerifyResult()
        result.kvTotal = localKeys.count
        result.photoChecked = photoPathKeys.count
        var zoneMissing = false
        let lock = NSLock()

        let op = CKFetchRecordsOperation(recordIDs: ids)
        op.desiredKeys = ["updatedAt"]   // 只取中繼資料，不下載照片/JSON 內容
        op.qualityOfService = .userInitiated
        op.perRecordResultBlock = { recID, recResult in
            lock.lock(); defer { lock.unlock() }
            switch recResult {
            case .success(let record):
                let mod = record.modificationDate
                if recID.recordName.hasPrefix("kv_") {
                    result.kvFound += 1
                    if let m = mod, m > (result.latestKVDate ?? .distantPast) { result.latestKVDate = m }
                } else {
                    result.photoFound += 1
                    if let m = mod, m > (result.latestPhotoDate ?? .distantPast) { result.latestPhotoDate = m }
                }
            case .failure(let error):
                // unknownItem＝查無此筆（尚未上雲，預期情況）；
                // zoneNotFound＝整個資料區不存在＝同步從未在此環境成功，需特別診斷
                if let ck = error as? CKError, ck.code == .zoneNotFound || ck.code == .userDeletedZone {
                    zoneMissing = true
                }
            }
        }
        op.fetchRecordsResultBlock = { [weak self] opResult in
            lock.lock()
            if case .failure(let error) = opResult {
                if let ck = error as? CKError, ck.code == .zoneNotFound || ck.code == .userDeletedZone {
                    zoneMissing = true
                } else if (error as? CKError)?.code != .partialFailure {
                    // partialFailure（部分記錄不存在）屬預期情況：以 found/total 呈現，不當整體錯誤
                    result.errorMessage = error.localizedDescription
                }
            }
            if zoneMissing {
                // 雲端資料區不存在＝「zone 已建立」快取旗標與目前環境不符（例如 Xcode 開發版
                // 建過 Development zone，TestFlight/App Store 版讀同一旗標而跳過 Production
                // zone 建立）。清掉旗標讓下一次同步重建 zone 並重新推送全部資料。
                if let self {
                    self.defaults.removeObject(forKey: self.zoneCreatedKey)
                    self.defaults.removeObject(forKey: self.subscriptionCreatedKey)
                }
                result.errorMessage = "雲端資料區不存在：同步從未在此環境成功寫入。已自動重設，請按「立即同步」重建後再驗證一次。"
            }
            let final = result
            lock.unlock()
            DispatchQueue.main.async { completion(final) }
        }
        privateDB.add(op)
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
// MARK: - 照片儲存壓縮

/// 照片存檔前的統一壓縮：長邊縮到 1920pt 內（1080P）+ JPEG 80%。
/// 各模型的 savePhoto/saveSketch 寫檔前呼叫，縮小本機占用、iCloud 上傳量與匯出備份檔大小。
enum ImageCompressor {
    /// 長邊上限（1080P 規格的長邊 1920）。
    static let maxDimension: CGFloat = 1920
    /// JPEG 壓縮品質。
    static let jpegQuality: CGFloat = 0.8

    /// 壓縮影像資料：解碼 → 長邊超過 1920pt 就等比例縮小 → JPEG 80% 重新編碼。
    /// 無法解碼（非影像資料）時原樣返回；壓縮結果反而更大（來源已是小圖/高壓縮檔）時也原樣返回。
    static func compressForStorage(_ data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let pixelW = image.size.width * image.scale
        let pixelH = image.size.height * image.scale
        let longest = max(pixelW, pixelH)

        let output: UIImage
        if longest > maxDimension {
            let ratio = maxDimension / longest
            let newSize = CGSize(width: (pixelW * ratio).rounded(.down),
                                 height: (pixelH * ratio).rounded(.down))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1   // newSize 已是像素尺寸，避免再乘裝置 scale
            output = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        } else {
            output = image
        }

        guard let jpeg = output.jpegData(compressionQuality: jpegQuality), jpeg.count < data.count else {
            return data
        }
        return jpeg
    }

    // MARK: 一鍵壓縮既有照片

    /// 批次壓縮結果統計。
    struct BatchResult {
        var scanned = 0          // 掃描檔案數
        var compressed = 0       // 實際被壓縮（變小）的檔案數
        var bytesBefore = 0      // 掃描檔案原始總大小
        var bytesAfter = 0       // 處理後總大小
        var savedMB: Double { Double(bytesBefore - bytesAfter) / 1_048_576 }
    }

    /// App 內所有照片資料夾。直接沿用 CloudKitManager.photoDirectories，
    /// 避免兩份清單分開維護而漏掉新資料夾（原本這裡缺少 "RealEstateDocuments"，
    /// 導致以「文件」流程匯入的收據/權狀照片永遠不會被一鍵壓縮工具處理到）。
    static let knownPhotoDirectories: [String] = CloudKitManager.photoDirectories

    /// 一鍵壓縮既有照片：走訪所有照片資料夾，逐檔套用 compressForStorage，
    /// 變小才回寫並重新上傳 iCloud 覆蓋雲端大圖；已是小圖者不動。
    /// 同步阻塞（IO 密集），請在背景執行緒呼叫。
    static func recompressAllStoredPhotos() -> BatchResult {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        var result = BatchResult()
        for dirName in knownPhotoDirectories {
            let dir = docs.appendingPathComponent(dirName, isDirectory: true)
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in files where url.pathExtension.lowercased() == "jpg" {
                guard let data = try? Data(contentsOf: url) else { continue }
                result.scanned += 1
                result.bytesBefore += data.count
                let out = compressForStorage(data)
                // 壓縮期間使用者可能已從畫面刪除這張照片（原始檔＋CloudKit 紀錄都已移除），
                // 寫回前重新確認檔案仍存在，避免把已刪除的照片復活並重新上傳到 iCloud
                if out.count < data.count, FileManager.default.fileExists(atPath: url.path),
                   (try? out.write(to: url)) != nil {
                    result.compressed += 1
                    result.bytesAfter += out.count
                    // 覆蓋雲端同名檔，避免下次同步又把大圖拉回來
                    PhotoCloudSync.upload(directory: dirName, fileName: url.lastPathComponent)
                } else {
                    result.bytesAfter += data.count
                }
            }
        }
        return result
    }
}

enum PhotoCloudSync {
    // 呼叫端含背景執行緒（相片壓縮／上傳走 Task.detached），改讀鎖保護的
    // isEnabledThreadSafe，避免跨執行緒讀寫 @Published isEnabled 的資料競態。
    static func upload(directory: String, fileName: String) {
        guard CloudSyncManager.shared.isEnabledThreadSafe else { return }
        CloudKitManager.shared.uploadPhoto(directory: directory, fileName: fileName)
    }

    static func delete(directory: String, fileName: String) {
        guard CloudSyncManager.shared.isEnabledThreadSafe else { return }
        CloudKitManager.shared.deletePhoto(directory: directory, fileName: fileName)
    }
}
