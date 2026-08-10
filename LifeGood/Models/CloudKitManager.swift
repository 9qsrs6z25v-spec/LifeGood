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
    /// 同步進度文字（例「上傳照片 12/87」）；userInfo["text"] 為 nil 代表進度結束
    static let syncProgressNotification = Notification.Name("CloudKitManager.syncProgress")

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
        "RealEstateDocuments",
        "VehiclePhotos"
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
    /// 照片上傳帳本：pathKey → 「大小-修改時間」簽章。簽章相同＝檔案沒變且已上傳過，
    /// 下輪同步直接跳過——沒有這本帳，每次同步都會把數百張照片重新上傳一遍
    ///（也是行動數據暴增與「同步中」轉不完的主因）。
    private let uploadLedgerKey = "ck_uploaded_photo_ledger"

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


    /// 為 CloudKit 操作加上明確逾時：預設設定下操作可能被系統長時間掛起，
    /// 卡住呼叫端的 isSyncing 旗標（使用者回報「同步中…」跨日不結束）。
    /// 單一請求 30 秒、整體資源（含 CKAsset 上傳/下載）5 分鐘內須完成，逾時即回錯誤。
    private func applyTimeouts(_ op: CKOperation) {
        op.configuration.timeoutIntervalForRequest = 30
        op.configuration.timeoutIntervalForResource = 300
    }

    // MARK: - Zone

    private func ensureZoneExists(completion: @escaping (Bool) -> Void) {
        if defaults.bool(forKey: zoneCreatedKey) { completion(true); return }
        let zone = CKRecordZone(zoneID: zoneID)
        let op = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
        op.qualityOfService = .userInitiated
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
        applyTimeouts(op)
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
        op.qualityOfService = .userInitiated
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
        applyTimeouts(op)
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
            op.qualityOfService = .userInitiated
            // 個別記錄結果：整體 modifyRecordsResultBlock 成功「不代表」個別記錄成功——
            // 個別失敗（最典型：iCloud 空間不足 quotaExceeded）走 perRecordSaveBlock 回報，
            // 過去沒掛這個回呼，個別失敗被靜默吞掉、整輪同步被誤標成功
            var perRecordError: Error?
            op.perRecordSaveBlock = { _, res in
                if case .failure(let e) = res { perRecordError = e }
            }
            op.modifyRecordsResultBlock = { [weak self] result in
                try? FileManager.default.removeItem(at: tmp)
                switch result {
                case .success:
                    if let pe = perRecordError {
                        self?.report(pe, context: "上傳 \(key)（個別記錄失敗）")
                        completion?(false)
                        return
                    }
                    // 寫入自我驗證哨兵：v25.137 雲端普查揭露「推送回報成功但 zone 完全是空的」
                    // 矛盾（診斷第 6 層純欄位寫入卻能讀回），在真實路徑上加裝哨兵——
                    // 成功回報後立刻以中繼資料 fetch 讀回同一筆，讀不回就視為失敗並回報可見錯誤
                    guard let self else { completion?(true); return }
                    let verifyOp = CKFetchRecordsOperation(recordIDs: [recID])
                    verifyOp.desiredKeys = ["updatedAt"]
                    verifyOp.qualityOfService = .userInitiated
                    var readBack = false
                    var readBackError: Error?
                    verifyOp.perRecordResultBlock = { _, res in
                        switch res {
                        case .success: readBack = true
                        case .failure(let e): readBackError = e
                        }
                    }
                    verifyOp.fetchRecordsResultBlock = { [weak self] overall in
                        if readBack { completion?(true); return }
                        if case .failure(let e) = overall, readBackError == nil { readBackError = e }
                        let detail = (readBackError as NSError?).map { "\($0.domain)#\($0.code)" } ?? "查無此筆"
                        self?.report(NSError(
                            domain: "LifeGoodSync", code: -99,
                            userInfo: [NSLocalizedDescriptionKey:
                                "伺服器回報寫入成功，但立即讀回失敗（\(detail)）——請截圖回報"]
                        ), context: "上傳 \(key)")
                        completion?(false)
                    }
                    self.applyTimeouts(verifyOp)
                    self.privateDB.add(verifyOp)
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
                        self.defaults.removeObject(forKey: self.uploadLedgerKey)   // zone 重建＝雲端照片全沒了，帳本作廢
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
            self.applyTimeouts(op)
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

                // 只取中繼資料（desiredKeys）確認記錄是否存在：先前用便利 fetch
                // 會連舊照片的 CKAsset 檔案一起下載回來——數百張照片每輪同步
                // 都「先下載一遍再上傳一遍」，流量直接翻倍
                let fetchOp = CKFetchRecordsOperation(recordIDs: [recID])
                fetchOp.desiredKeys = ["updatedAt"]
                fetchOp.qualityOfService = .userInitiated
                var existing: CKRecord?
                var fetchError: Error?
                fetchOp.perRecordResultBlock = { _, res in
                    switch res {
                    case .success(let r): existing = r
                    case .failure(let e): fetchError = e
                    }
                }
                fetchOp.fetchRecordsResultBlock = { [weak self] overall in
                    guard let self else { completion?(false); return }
                    if case .failure(let e) = overall, fetchError == nil { fetchError = e }
                    // fetch 失敗但「不是查無此筆」→ 真錯誤；若仍繼續存空 CKRecord 會因
                    // 缺少 recordChangeTag 而觸發不必要的 .serverRecordChanged 衝突
                    if existing == nil, let fe = fetchError,
                       (fe as? CKError)?.code != .unknownItem {
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
                    op.qualityOfService = .userInitiated
                    // 個別記錄失敗（如 iCloud 空間不足）不一定捲入整體結果，必須另掛回呼檢查
                    var perRecordError: Error?
                    op.perRecordSaveBlock = { _, res in
                        if case .failure(let e) = res { perRecordError = e }
                    }
                    op.modifyRecordsResultBlock = { [weak self] result in
                        switch result {
                        case .success:
                            if let pe = perRecordError {
                                self?.report(pe, context: "上傳照片 \(fileName)（個別記錄失敗）")
                                completion?(false)
                            } else {
                                completion?(true)
                            }
                        case .failure(let error):
                            if let ck = error as? CKError,
                               ck.code == .zoneNotFound || ck.code == .userDeletedZone,
                               retryOnZoneMissing,
                               let self {
                                // zone 不存在（快取旗標與目前環境不符）→ 清旗標重建後重傳一次
                                // （同型修法見 modifyKV zoneNotFound 分支）
                                self.defaults.removeObject(forKey: self.zoneCreatedKey)
                                self.defaults.removeObject(forKey: self.subscriptionCreatedKey)
                                self.defaults.removeObject(forKey: self.uploadLedgerKey)   // zone 重建＝雲端照片全沒了，帳本作廢
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
                    self.applyTimeouts(op)
                    self.privateDB.add(op)
                }
                self.applyTimeouts(fetchOp)
                self.privateDB.add(fetchOp)
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
        op.qualityOfService = .userInitiated
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

        applyTimeouts(op)
        privateDB.add(op)
    }

    // MARK: - 一次性：把所有本地照片掃描後上傳（確保歷史檔案不漏）

    /// 掃描上傳的併發守衛（都只在 queue 上讀寫）：同一時間只允許一輪掃描上傳。
    /// 使用者按「重置」再按「立即同步」時，舊迴圈仍在背景跑，第二輪疊上去會
    /// 兩組進度數字交錯跳動（例 16/375、52/403）且同批照片重複上傳。
    private var uploadSweepActive = false
    private var uploadSweepCompletions: [() -> Void] = []
    private var uploadSweepGeneration = 0

    /// 使用者按「重置」時呼叫：進行中的照片掃描上傳會在下一個批次邊界中止
    func cancelPhotoSweep() {
        queue.async { self.uploadSweepGeneration += 1 }
    }

    func uploadAllLocalPhotos(completion: (() -> Void)? = nil) {
        guard isAvailable else { completion?(); return }
        queue.async {
            // 已有一輪在跑 → 不疊加第二輪，把回呼併入進行中那輪、結束時一起通知
            if self.uploadSweepActive {
                if let completion { self.uploadSweepCompletions.append(completion) }
                return
            }
            guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                completion?(); return
            }
            self.uploadSweepActive = true
            let generation = self.uploadSweepGeneration

            /// 收尾（在 queue 上呼叫）：放下守衛旗標、通知本輪與併入的所有回呼
            func finishSweep() {
                self.uploadSweepActive = false
                let merged = self.uploadSweepCompletions
                self.uploadSweepCompletions = []
                DispatchQueue.main.async {
                    completion?()
                    merged.forEach { $0() }
                }
            }

            // 先用帳本掃出「真正需要上傳」的清單：簽章（大小-修改時間）相同＝已上傳且沒變，
            // 直接跳過不打任何網路——沒帳本前每輪同步都重傳全部照片，是流量與時間爆炸的主因
            let ledger = self.uploadLedger()
            var pending: [(dir: String, file: String, pathKey: String, signature: String)] = []
            for dir in Self.photoDirectories {
                let url = docs.appendingPathComponent(dir, isDirectory: true)
                guard let files = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { continue }
                for f in files where !f.hasPrefix(".") {
                    let pathKey = "\(dir)/\(f)"
                    guard let sig = self.fileSignature(url.appendingPathComponent(f)) else { continue }
                    if ledger[pathKey] == sig { continue }
                    pending.append((dir, f, pathKey, sig))
                }
            }
            guard !pending.isEmpty else {
                finishSweep()
                return
            }
            let total = pending.count
            self.postSyncProgress("上傳照片 0/\(total)")

            // 4 張一批依序上傳：先前是全部照片同時排隊（數百個並發作業），
            // 既塞爆佇列也讓進度無從掌握；批次化後可回報「上傳照片 X/Y」即時進度
            func runBatch(_ index: Int) {
                // 被取消（重置）→ 中止剩餘批次；已傳成功的照片留在帳本，下輪不會重傳
                guard generation == self.uploadSweepGeneration else {
                    self.postSyncProgress(nil)
                    finishSweep()
                    return
                }
                guard index < pending.count else {
                    self.postSyncProgress(nil)
                    finishSweep()
                    return
                }
                let batch = pending[index..<min(index + 4, pending.count)]
                let group = DispatchGroup()
                for item in batch {
                    // 斷網短路：前面的照片已因網路無法連線失敗，剩餘照片不再逐張嘗試
                    //（每張都要枯等逾時）；待網路恢復下輪再傳
                    if self.isNetworkLikelyBlocked { continue }
                    group.enter()
                    self.uploadPhoto(directory: item.dir, fileName: item.file) { ok in
                        // 成功才記帳；失敗的下輪同步會再嘗試
                        if ok { self.markUploaded(pathKey: item.pathKey, signature: item.signature) }
                        group.leave()
                    }
                }
                group.notify(queue: self.queue) {
                    self.postSyncProgress("上傳照片 \(min(index + 4, total))/\(total)")
                    runBatch(index + 4)
                }
            }
            runBatch(0)
        }
    }

    // MARK: - 照片上傳帳本

    /// 檔案簽章：大小-修改時間。任一變動（重拍、壓縮、覆寫）簽章就不同 → 會重新上傳。
    private func fileSignature(_ url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return nil }
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(size)-\(Int(mtime))"
    }

    private func uploadLedger() -> [String: String] {
        (defaults.dictionary(forKey: uploadLedgerKey) as? [String: String]) ?? [:]
    }

    /// 記帳一律排到 queue 上做讀改寫，避免多張照片同時完成時互相蓋掉彼此的紀錄
    private func markUploaded(pathKey: String, signature: String) {
        queue.async {
            var ledger = self.uploadLedger()
            ledger[pathKey] = signature
            self.defaults.set(ledger, forKey: self.uploadLedgerKey)
        }
    }

    /// 廣播同步進度文字（nil＝進度結束），主執行緒送出供 UI 顯示
    private func postSyncProgress(_ text: String?) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.syncProgressNotification, object: nil,
                userInfo: text.map { ["text": $0] } ?? [:]
            )
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
                self.applyTimeouts(op)
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
        defaults.removeObject(forKey: uploadLedgerKey)
    }

    // MARK: - 同步診斷（逐層測試，顯示原始錯誤碼）

    /// 逐層診斷同步鏈路：一般網路 → iCloud 帳號 → 私有資料庫讀 → 寫 → 自訂 zone。
    /// 每層回報 ✓/✗ 與原始錯誤（domain#code＋底層 NSError），供精準定位斷點。
    ///
    /// 關鍵設計：CloudKit 在系統層判定「無網路」時不會回錯誤，而是把作業**無限排隊**
    /// 等網路恢復（這正是「同步中」轉不停的元凶）。因此每一步都有獨立的逾時守門——
    /// 卡住的那一步會標成「逾時＝被系統排隊」然後繼續跑下一步，
    /// 「哪一步逾時」本身就是最重要的診斷結果。
    func runDiagnostics(completion: @escaping (String) -> Void) {
        var lines: [String] = []
        let lock = NSLock()

        func raw(_ error: Error?) -> String {
            guard let e = error as NSError? else { return "無錯誤" }
            var out = "\(e.domain)#\(e.code)：\(e.localizedDescription)"
            if let u = e.userInfo[NSUnderlyingErrorKey] as? NSError {
                out += "\n    底層：\(u.domain)#\(u.code)：\(u.localizedDescription)"
            }
            if let partials = e.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: NSError],
               let p = partials.values.first {
                out += "\n    個別：\(p.domain)#\(p.code)：\(p.localizedDescription)"
            }
            return out
        }

        /// 為 CloudKit 作業套上「快速失敗」設定：診斷要的是立即答案，不是排隊等網路
        func fastFail(_ op: CKOperation) {
            op.configuration.timeoutIntervalForRequest = 15
            op.configuration.timeoutIntervalForResource = 20
            op.configuration.qualityOfService = .userInitiated
        }

        let steps: [(title: String, timeout: TimeInterval, body: (@escaping (String) -> Void) -> Void)] = [
            ("1. 一般網路", 12, { done in
                var req = URLRequest(url: URL(string: "https://www.apple.com/library/test/success.html")!)
                req.timeoutInterval = 10
                URLSession.shared.dataTask(with: req) { _, resp, err in
                    if let err {
                        done("✗ 1. 一般網路：\(raw(err))")
                    } else {
                        done("✓ 1. 一般網路：HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)")
                    }
                }.resume()
            }),
            ("2. iCloud 帳號", 10, { done in
                self.container.accountStatus { status, acctErr in
                    let statusName: String = {
                        switch status {
                        case .available: return "available（正常）"
                        case .noAccount: return "noAccount（未登入）"
                        case .restricted: return "restricted（受限制）"
                        case .couldNotDetermine: return "couldNotDetermine（無法判定）"
                        case .temporarilyUnavailable: return "temporarilyUnavailable（暫時不可用）"
                        @unknown default: return "未知(\(status.rawValue))"
                        }
                    }()
                    if let acctErr {
                        done("✗ 2. iCloud 帳號：\(statusName)\n    \(raw(acctErr))")
                    } else {
                        done("\(status == .available ? "✓" : "✗") 2. iCloud 帳號：\(statusName)")
                    }
                }
            }),
            ("3. 資料庫讀取", 25, { done in
                // default zone 探測：查無此筆（unknownItem）＝連線正常
                let probeID = CKRecord.ID(recordName: "diag_probe")
                let op = CKFetchRecordsOperation(recordIDs: [probeID])
                fastFail(op)
                op.fetchRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        done("✓ 3. 資料庫讀取：連線正常")
                    case .failure(let error):
                        let codes: [CKError.Code?] = [
                            (error as? CKError)?.code,
                            ((error as? CKError)?.partialErrorsByItemID?.values.first as? CKError)?.code
                        ]
                        if codes.contains(.unknownItem) {
                            done("✓ 3. 資料庫讀取：連線正常（查無測試筆，符合預期）")
                        } else {
                            done("✗ 3. 資料庫讀取：\(raw(error))")
                        }
                    }
                }
                self.privateDB.add(op)
            }),
            ("4. 資料庫寫入", 25, { done in
                let testRec = CKRecord(recordType: "DiagTest",
                                       recordID: CKRecord.ID(recordName: "diag_write_test"))
                testRec["note"] = "sync diagnostics" as NSString
                let op = CKModifyRecordsOperation(recordsToSave: [testRec])
                op.savePolicy = .allKeys   // 直接覆寫既有測試筆，避免版本衝突干擾判讀
                fastFail(op)
                op.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        done("✓ 4. 資料庫寫入：成功")
                    case .failure(let error):
                        if let ck = error as? CKError, ck.code == .serverRecordChanged {
                            done("✓ 4. 資料庫寫入：連線正常（測試筆已存在）")
                        } else {
                            done("✗ 4. 資料庫寫入：\(raw(error))")
                        }
                    }
                }
                self.privateDB.add(op)
            }),
            ("5. 資料區 LifeGoodZone", 22, { done in
                let op = CKFetchRecordZonesOperation(recordZoneIDs: [self.zoneID])
                fastFail(op)
                var zoneLine: String?
                op.perRecordZoneResultBlock = { _, result in
                    switch result {
                    case .success:
                        zoneLine = "✓ 5. 資料區 LifeGoodZone：存在"
                    case .failure(let error):
                        if let ck = error as? CKError, ck.code == .zoneNotFound {
                            zoneLine = "✗ 5. 資料區 LifeGoodZone：不存在（按「立即同步」會重建）"
                        } else {
                            zoneLine = "✗ 5. 資料區 LifeGoodZone：\(raw(error))"
                        }
                    }
                }
                op.fetchRecordZonesResultBlock = { result in
                    if let zoneLine {
                        done(zoneLine)
                    } else if case .failure(let error) = result {
                        done("✗ 5. 資料區 LifeGoodZone：\(raw(error))")
                    } else {
                        done("✗ 5. 資料區 LifeGoodZone：無回應")
                    }
                }
                self.privateDB.add(op)
            }),
            ("6. LifeGoodZone 寫入讀回", 30, { done in
                // 關鍵測試：App 實際同步用的就是這個 zone——寫一筆測試記錄再「立刻讀回」。
                // 寫入成功＋讀回成功＝整條鏈路正常；寫入成功但讀不回＝重大異常，直指病灶
                let recID = CKRecord.ID(recordName: "diag_zone_test", zoneID: self.zoneID)
                let rec = CKRecord(recordType: "DiagTest", recordID: recID)
                rec["note"] = "zone diagnostics" as NSString
                let save = CKModifyRecordsOperation(recordsToSave: [rec])
                save.savePolicy = .allKeys
                fastFail(save)
                save.modifyRecordsResultBlock = { result in
                    switch result {
                    case .failure(let e):
                        done("✗ 6. LifeGoodZone 寫入讀回：寫入失敗 \(raw(e))")
                    case .success:
                        let fetch = CKFetchRecordsOperation(recordIDs: [recID])
                        fastFail(fetch)
                        fetch.fetchRecordsResultBlock = { r in
                            switch r {
                            case .success:
                                done("✓ 6. LifeGoodZone 寫入讀回：寫入後立即讀回成功")
                            case .failure(let e):
                                done("✗ 6. LifeGoodZone 寫入讀回：寫入成功但讀不回！\(raw(e))")
                            }
                        }
                        self.privateDB.add(fetch)
                    }
                }
                self.privateDB.add(save)
            }),
            ("7. 真實推送路徑（含附件）", 40, { done in
                // 決定性測試：第 6 層寫的是純欄位測試筆，真正同步推的是「帶 CKAsset 附件」的
                // KVBlob——嫌疑鎖定在附件路徑上。這裡直接呼叫生產環境同一條 pushKV
                //（fetch→組 CKAsset→.changedKeys 寫入），成功後再讀回驗證
                let payload = Data("{\"diag\":true}".utf8)
                self.pushKV(key: "diag_pipeline_test", data: payload) { ok in
                    guard ok else {
                        done("✗ 7. 真實推送路徑：pushKV 回報失敗（原始錯誤見「同步錯誤」列）")
                        return
                    }
                    let recID = CKRecord.ID(recordName: "kv_diag_pipeline_test", zoneID: self.zoneID)
                    let fetch = CKFetchRecordsOperation(recordIDs: [recID])
                    fetch.desiredKeys = ["updatedAt"]
                    fastFail(fetch)
                    var found = false
                    fetch.perRecordResultBlock = { _, res in
                        if case .success = res { found = true }
                    }
                    fetch.fetchRecordsResultBlock = { r in
                        if found {
                            done("✓ 7. 真實推送路徑（KVBlob＋附件）：寫入並讀回成功")
                        } else if case .failure(let e) = r {
                            done("✗ 7. 真實推送路徑：寫入回報成功但讀不回！\(raw(e))")
                        } else {
                            done("✗ 7. 真實推送路徑：寫入回報成功但讀不回（查無此筆）")
                        }
                    }
                    self.privateDB.add(fetch)
                }
            }),
            // 第 8、9 層：變因切割。第 6 層（DiagTest 無附件）能過、第 7 層（KVBlob＋附件）
            // 不過——到底毒在「KVBlob 記錄型別」還是「CKAsset 附件」？各測一半
            ("8. KVBlob 純欄位（無附件）", 30, { done in
                let recID = CKRecord.ID(recordName: "diag_kvblob_noasset", zoneID: self.zoneID)
                let rec = CKRecord(recordType: Self.kvBlobRecordType, recordID: recID)
                rec["keyName"] = "diag_kvblob_noasset" as NSString
                rec["updatedAt"] = Date() as NSDate
                let op = CKModifyRecordsOperation(recordsToSave: [rec])
                op.savePolicy = .allKeys
                fastFail(op)
                var perErr: Error?
                op.perRecordSaveBlock = { _, r in if case .failure(let e) = r { perErr = e } }
                op.modifyRecordsResultBlock = { result in
                    if case .failure(let e) = result { done("✗ 8. KVBlob 純欄位：寫入失敗 \(raw(e))"); return }
                    if let perErr { done("✗ 8. KVBlob 純欄位：整體成功但個別記錄失敗 \(raw(perErr))"); return }
                    let f = CKFetchRecordsOperation(recordIDs: [recID])
                    fastFail(f)
                    var found = false
                    f.perRecordResultBlock = { _, r in if case .success = r { found = true } }
                    f.fetchRecordsResultBlock = { _ in
                        done(found ? "✓ 8. KVBlob 純欄位（無附件）：寫入並讀回成功"
                                   : "✗ 8. KVBlob 純欄位：寫入回報成功但讀不回")
                    }
                    self.privateDB.add(f)
                }
                self.privateDB.add(op)
            }),
            ("9. 附件（CKAsset）寫入", 35, { done in
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("diag_asset_test.json")
                try? Data("{\"diag\":1}".utf8).write(to: tmp)
                let recID = CKRecord.ID(recordName: "diag_asset_test", zoneID: self.zoneID)
                let rec = CKRecord(recordType: "DiagTest", recordID: recID)
                rec["payload"] = CKAsset(fileURL: tmp)
                let op = CKModifyRecordsOperation(recordsToSave: [rec])
                op.savePolicy = .allKeys
                fastFail(op)
                var perErr: Error?
                op.perRecordSaveBlock = { _, r in if case .failure(let e) = r { perErr = e } }
                op.modifyRecordsResultBlock = { result in
                    try? FileManager.default.removeItem(at: tmp)
                    if case .failure(let e) = result { done("✗ 9. 附件寫入：失敗 \(raw(e))"); return }
                    if let perErr { done("✗ 9. 附件寫入：整體成功但個別記錄失敗 \(raw(perErr))"); return }
                    let f = CKFetchRecordsOperation(recordIDs: [recID])
                    fastFail(f)
                    var found = false
                    f.perRecordResultBlock = { _, r in if case .success = r { found = true } }
                    f.fetchRecordsResultBlock = { _ in
                        done(found ? "✓ 9. 附件（CKAsset）寫入：寫入並讀回成功"
                                   : "✗ 9. 附件寫入：寫入回報成功但讀不回")
                    }
                    self.privateDB.add(f)
                }
                self.privateDB.add(op)
            })
        ]

        func runStep(_ i: Int) {
            guard i < steps.count else {
                DispatchQueue.main.async { completion(lines.joined(separator: "\n")) }
                return
            }
            let step = steps[i]
            var finished = false
            func finish(_ line: String) {
                lock.lock()
                guard !finished else { lock.unlock(); return }
                finished = true
                lock.unlock()
                lines.append(line)
                runStep(i + 1)
            }
            // 守門計時器：逾時＝作業被系統排隊（CloudKit 判定無網路時的典型行為）
            DispatchQueue.global().asyncAfter(deadline: .now() + step.timeout) {
                finish("✗ \(step.title)：逾時（\(Int(step.timeout)) 秒無回應）→ 作業被系統排隊＝系統層判定「無網路」，這就是同步卡住的原因")
            }
            step.body { finish($0) }
        }
        runStep(0)
    }

    // MARK: - 錯誤回報（把過去被吞掉的 CloudKit 失敗變成可見訊息）

    /// 最近一次網路無法連線錯誤的時間：供批次上傳短路——一張照片因斷網失敗後，
    /// 其餘數百張不再逐張嘗試（每張都要枯等逾時，是「同步中」轉很久的主因之一）。
    private let networkErrorLock = NSLock()
    private var _lastNetworkErrorAt: Date?
    private(set) var lastNetworkErrorAt: Date? {
        get { networkErrorLock.lock(); defer { networkErrorLock.unlock() }; return _lastNetworkErrorAt }
        set { networkErrorLock.lock(); _lastNetworkErrorAt = newValue; networkErrorLock.unlock() }
    }
    /// 10 秒內發生過網路錯誤 → 視為目前斷網，批次作業直接跳過剩餘項目
    var isNetworkLikelyBlocked: Bool {
        guard let at = lastNetworkErrorAt else { return false }
        return Date().timeIntervalSince(at) < 10
    }

    /// 把錯誤翻成可讀中文並廣播 + DEBUG console 印出。nil 代表沒有錯誤。
    func report(_ error: Error?, context: String) {
        guard let error = error else { return }
        if let ck = error as? CKError, ck.code == .networkUnavailable || ck.code == .networkFailure {
            lastNetworkErrorAt = Date()
        }
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
        case .networkUnavailable, .networkFailure:
            return "網路無法連線。若正在使用行動數據，請到 iPhone 設定 → 行動網路 → 確認 LifeGood 已允許使用行動數據；或連上 Wi-Fi 後再按「立即同步」。"
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
        // 雲端普查（第二階段）：不猜 record ID，直接列出 zone 裡實際的記錄總數。
        // 抽查 0 筆時可分辨「雲端真的空（推送回報與實際不符）」vs「記錄在但 ID 對不上」。
        var censusKV = -1               // zone 內實際 KVBlob 總數（-1＝普查失敗）
        var censusPhoto = -1            // zone 內實際 Photo 總數（-1＝普查失敗）
        var censusSamples: [String] = []// 實際記錄 ID 樣本（供與預期 ID 比對）
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
                    self.defaults.removeObject(forKey: self.uploadLedgerKey)   // zone 不存在＝雲端照片不存在，帳本作廢
                }
                result.errorMessage = "雲端資料區不存在：同步從未在此環境成功寫入。已自動重設，請按「立即同步」重建後再驗證一次。"
            }
            var final = result
            lock.unlock()
            // 第二階段「雲端普查」：直接掃 zone 裡實際存在的記錄（不經由預測的 ID），
            // 讓「抽查 0 筆」能進一步分辨是雲端真的空、還是 ID 對不上
            guard let self, final.errorMessage == nil else {
                DispatchQueue.main.async { completion(final) }
                return
            }
            self.censusZone { kvCount, photoCount, samples, censusErr in
                if censusErr == nil {
                    final.censusKV = kvCount
                    final.censusPhoto = photoCount
                    final.censusSamples = samples
                }
                completion(final)   // censusZone 已回主執行緒
            }
        }
        applyTimeouts(op)
        privateDB.add(op)
    }

    /// 雲端普查：以 nil change token 全量掃描 LifeGoodZone，只取 updatedAt 中繼資料，
    /// 統計 KVBlob／Photo 實際總數並取前幾筆記錄 ID 樣本。流量極小（不下載 asset）。
    private func censusZone(completion: @escaping (Int, Int, [String], String?) -> Void) {
        let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration(
            previousServerChangeToken: nil, resultsLimit: nil, desiredKeys: ["updatedAt"])
        let op = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zoneID], configurationsByRecordZoneID: [zoneID: config])
        op.fetchAllChanges = true
        op.qualityOfService = .userInitiated
        var kv = 0, photo = 0
        var samples: [String] = []
        let lock = NSLock()
        op.recordWasChangedBlock = { id, res in
            guard case .success(let rec) = res else { return }
            lock.lock()
            if rec.recordType == Self.kvBlobRecordType { kv += 1 }
            else if rec.recordType == Self.photoRecordType { photo += 1 }
            if samples.count < 4 { samples.append(id.recordName) }
            lock.unlock()
        }
        op.fetchRecordZoneChangesResultBlock = { result in
            lock.lock()
            let kvFinal = kv, photoFinal = photo, samplesFinal = samples
            lock.unlock()
            var err: String?
            if case .failure(let e) = result { err = e.localizedDescription }
            DispatchQueue.main.async { completion(kvFinal, photoFinal, samplesFinal, err) }
        }
        applyTimeouts(op)
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
