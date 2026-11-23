// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.640 mac1] 讀 iCloud（brief.md §G2-2、judge_mac.md §O2、§O7）。
//
// • 固定 record ID（kv_<鍵>）＋ records(for:desiredKeys:)，**只讀 5 個白名單鍵**：拿不到部屬、評分、卡片、帳號、照片，
//   不是「拿到再過濾」。不用 CKFetchRecordZoneChangesOperation、不用 CKQuery。
// • 這個檔只有讀：不建 zone、不建記錄、不建訂閱、不存、不刪（寫入只在 MacCloudWriter.swift）。
// • 記錄格式照 iPhone CloudKitManager.swift：recordType KVBlob、zone LifeGoodZone、payload（CKAsset，iPhone UserDefaults 原樣的 JSON）、
//   updatedAt（iPhone 最後一次推上來的時間）、keyName。

import Foundation
import CloudKit

/// 一個鍵在雲端的樣子。原始 Data＋changeTag 才是真的資料；解碼出來的 [Expense]／[Income] 只拿來顯示、計算。
struct MacKVRecord {
    let key: String
    /// 剛抓到的那筆記錄（不存在＝nil）；Writer 一律拿「自己剛抓到的」改，不拿這裡的舊物件
    let record: CKRecord?
    /// payload 的原始 bytes（只抓 updatedAt 時＝nil）
    let data: Data?
    let changeTag: String?
    /// iPhone 最後一次推上來的時間（record["updatedAt"]，沒有就用 modificationDate）
    let updatedAt: Date?
    let fetchedAt: Date

    /// 雲端沒有這個鍵
    static func missing(_ key: String, fetchedAt: Date) -> MacKVRecord {
        MacKVRecord(key: key, record: nil, data: nil, changeTag: nil, updatedAt: nil, fetchedAt: fetchedAt)
    }

    var exists: Bool { record != nil }
}

enum MacCloudError: Error, Equatable {
    case noAccount, restricted, temporarilyUnavailable, couldNotDetermine, zoneNotFound, network
    case other(String)

    /// 給畫面的一句話（不含 email、不含記錄內容）
    var message: String {
        switch self {
        case .noAccount: return "這台 Mac 還沒登入 iCloud"
        case .restricted: return "這台 Mac 的 iCloud 被限制使用"
        case .temporarilyUnavailable: return "iCloud 暫時無法使用，等一下再按 ⌘R"
        case .couldNotDetermine: return "讀不到 iCloud 帳號狀態，等一下再按 ⌘R"
        case .zoneNotFound: return "這個 Apple 帳號還沒有 LifeGood 的資料"
        case .network: return "離線中"
        case .other(let s): return s
        }
    }
}

final class MacCloud: @unchecked Sendable {
    static let shared = MacCloud()

    static let containerID = "iCloud.com.lifegood.app"
    static let zoneName = "LifeGoodZone"

    static let expensesKey = "lifegood_expenses"
    static let incomesKey = "lifegood_incomes"
    static let ratesKey = "lifegood_currency_rates"
    static let splitsKey = "lifegood_expense_splits_v1"
    static let kindsKey = "lifegood_expense_kinds_v1"
    /// Mac 1 讀的 5 個鍵（judge_mac.md §O5）；這以外的鍵一律不讀
    static let readKeys: [String] = [expensesKey, incomesKey, ratesKey, splitsKey, kindsKey]

    let container: CKContainer
    let database: CKDatabase
    let zoneID: CKRecordZone.ID

    init() {
        container = CKContainer(identifier: MacCloud.containerID)
        database = container.privateCloudDatabase
        zoneID = CKRecordZone.ID(zoneName: MacCloud.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    /// iPhone 的 KVBlob 記錄名稱（CloudKitManager.swift:271 同一個寫法）
    func recordID(for key: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "kv_\(key)", zoneID: zoneID)
    }

    func accountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }

    /// 只拿來算本機資料夾名稱的雜湊（MacMoneyStore.accountHash）；不顯示、不記錄
    func userRecordName() async throws -> String {
        let id = try await container.userRecordID()
        return id.recordName
    }

    /// 抓幾個鍵。回傳每個鍵都有一筆：雲端沒有那個鍵（.unknownItem）＝record nil。
    /// withPayload：true＝payload、updatedAt、keyName（payload 的暫存檔**馬上**讀成 Data）；false＝只抓 updatedAt（比 changeTag 用）。
    /// zone 不存在 → .zoneNotFound；沒網路 → .network；其他 → 對應的 MacCloudError。
    func fetch(_ keys: [String], withPayload: Bool) async throws -> [String: MacKVRecord] {
        let ids = keys.map { recordID(for: $0) }
        let desired: [CKRecord.FieldKey] = withPayload ? ["payload", "updatedAt", "keyName"] : ["updatedAt"]
        let results: [CKRecord.ID: Result<CKRecord, Error>]
        do {
            results = try await database.records(for: ids, desiredKeys: desired)
        } catch {
            throw MacCloud.mapError(error)
        }
        let now = Date()
        var out: [String: MacKVRecord] = [:]
        for (key, id) in zip(keys, ids) {
            guard let result = results[id] else {
                out[key] = MacKVRecord.missing(key, fetchedAt: now)
                continue
            }
            switch result {
            case .success(let record):
                out[key] = try MacCloud.makeRecord(key: key, record: record, withPayload: withPayload, fetchedAt: now)
            case .failure(let error):
                if MacCloud.isUnknownItem(error) {
                    out[key] = MacKVRecord.missing(key, fetchedAt: now)
                } else {
                    throw MacCloud.mapError(error)
                }
            }
        }
        return out
    }

    // MARK: - 小工具

    /// 有 payload 卻讀不到檔（暫存檔被清掉、讀取失敗）→ 丟錯，不當成「沒有資料」：
    /// 不然總覽會變 0 筆、刪除前查分帳會以為沒有分帳（寧可這一輪讀失敗、按 ⌘R 再試）
    static func makeRecord(key: String, record: CKRecord, withPayload: Bool, fetchedAt: Date) throws -> MacKVRecord {
        var data: Data? = nil
        if withPayload, let asset = record["payload"] as? CKAsset {
            guard let url = asset.fileURL, let bytes = try? Data(contentsOf: url) else {
                throw MacCloudError.other("讀不到 iCloud 上的資料檔，請按 ⌘R 再試一次")
            }
            data = bytes
        }
        let updated = (record["updatedAt"] as? Date) ?? record.modificationDate
        return MacKVRecord(key: key, record: record, data: data, changeTag: record.recordChangeTag,
                           updatedAt: updated, fetchedAt: fetchedAt)
    }

    static func isUnknownItem(_ error: Error) -> Bool {
        (error as? CKError)?.code == .unknownItem
    }

    /// CloudKit 錯誤 → MacCloudError（逐筆、整體、partialFailure 內層都走這裡）
    static func mapError(_ error: Error) -> MacCloudError {
        if let e = error as? MacCloudError { return e }
        guard let ck = error as? CKError else { return .other("讀取 iCloud 失敗，請按 ⌘R 再試一次") }
        switch ck.code {
        case .zoneNotFound, .userDeletedZone:
            return .zoneNotFound
        case .networkUnavailable, .networkFailure:
            return .network
        case .notAuthenticated:
            return .noAccount
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return .other("iCloud 暫時忙碌，等一下再按 ⌘R")
        case .partialFailure:
            let inner = (ck.partialErrorsByItemID ?? [:]).values.map { e in MacCloud.mapError(e) }
            if inner.contains(.zoneNotFound) { return .zoneNotFound }
            if inner.contains(.network) { return .network }
            return inner.first ?? .other("讀取 iCloud 失敗，請按 ⌘R 再試一次")
        default:
            return .other("讀取 iCloud 失敗（代碼 \(ck.code.rawValue)），請按 ⌘R 再試一次")
        }
    }
}
