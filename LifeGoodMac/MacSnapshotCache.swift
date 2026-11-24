// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.641 mac2 G3] 本機快照（brief.md §2 G3 第 1～2 條、judge_mac.md §P9 G3、scout_macui §8）。
//
// • 放 Application Support/LifeGoodMac/<帳號雜湊>/snapshot/：每個鍵一個「<鍵>.json」＝雲端 payload 原樣的 bytes，
//   另存 meta.json（changeTag、updatedAt、fetchedAt、bytes、sha256）。換帳號時 MacJournal.removeOtherAccounts 整個資料夾刪掉。
// • 只存 MacCloud.readKeys 那 5 個鍵（這個檔不寫任何鍵名字面值）。這是本機檔案，不是同步鍵，不推、不寫 iCloud。
// • 只有「上次的帳號雜湊」放 UserDefaults（mac.snapshot.account）：放根目錄的檔案會被 MacJournal 刪掉。
// • 讀寫都在背景佇列 mac.snapshot（序列，所以先寫的一定先完成）；MacJournal.rootFolder() 是 MainActor，資料夾 URL 在主執行緒拿好再交下去。
// • 快照只拿來顯示：MacMoneyStore 不放進它「這次從雲端拿到的」那份、也不讓「這次抓成功過」變 true（寫入照舊鎖到真的抓到）。
// • 讀不到、bytes 或 sha256 對不上＝那個鍵不收（照整包抓）；寫失敗就算了（只是下次打開慢一點），不跳錯；log 只 .private。

import Foundation
import CryptoKit
import os

/// 一個鍵的快照（payload 原樣的 bytes＋抓到時的 changeTag）
struct MacSnapshotEntry: Sendable {
    let key: String
    let data: Data
    let changeTag: String?
    let updatedAt: Date?
    let fetchedAt: Date
}

/// meta.json：{ "v": 1, "keys": { 鍵: { changeTag, updatedAt, fetchedAt, bytes, sha256 } } }
struct MacSnapshotMeta: Codable {
    var v: Int = 1
    var keys: [String: MacSnapshotKeyMeta] = [:]
}

struct MacSnapshotKeyMeta: Codable {
    let changeTag: String?
    let updatedAt: Date?
    let fetchedAt: Date
    let bytes: Int
    let sha256: String
}

enum MacSnapshotCache {
    /// 上次存快照的帳號雜湊（MacMoneyStore.hashAccount 的 16 碼；不是 email）
    static let accountKey = "mac.snapshot.account"
    private static let queue = DispatchQueue(label: "mac.snapshot", qos: .utility)
    private static let metaName = "meta.json"
    private static let logger = Logger(subsystem: "com.lifegood.app.mac", category: "snapshot")

    // MARK: - 資料夾、帳號

    /// <根目錄>/<帳號雜湊>/snapshot/（雜湊不是 16 碼十六進位＝nil：不拿 UserDefaults 裡奇怪的字拼路徑）
    @MainActor
    static func folder(for hash: String) -> URL? {
        guard isAccountHash(hash) else { return nil }
        return MacJournal.rootFolder()?
            .appendingPathComponent(hash, isDirectory: true)
            .appendingPathComponent("snapshot", isDirectory: true)
    }

    /// 上次存快照的帳號（沒有＝nil）
    @MainActor
    static var savedAccount: String? {
        guard let s = UserDefaults.standard.string(forKey: accountKey), isAccountHash(s) else { return nil }
        return s
    }

    @MainActor
    static func remember(account hash: String) {
        guard isAccountHash(hash) else { return }
        if UserDefaults.standard.string(forKey: accountKey) != hash {
            UserDefaults.standard.set(hash, forKey: accountKey)
        }
    }

    private static func isAccountHash(_ s: String) -> Bool {
        s.count == 16 && s.allSatisfy { c in c.isHexDigit }
    }

    // MARK: - 讀

    /// 背景讀 meta.json＋各鍵的檔；bytes、sha256 都對得上的鍵才收
    static func load(from folder: URL) async -> [String: MacSnapshotEntry] {
        await withCheckedContinuation { (cont: CheckedContinuation<[String: MacSnapshotEntry], Never>) in
            MacSnapshotCache.queue.async {
                cont.resume(returning: MacSnapshotCache.readAll(folder))
            }
        }
    }

    /// 只在 queue 上跑
    private static func readAll(_ folder: URL) -> [String: MacSnapshotEntry] {
        guard let meta = readMeta(folder), meta.v == 1 else { return [:] }
        var out: [String: MacSnapshotEntry] = [:]
        for key in MacCloud.readKeys {
            // sim2: snap#3 bytes、sha256 都對才收；任何錯誤＝那個鍵不收（MacMoneyStore 照整包抓）
            guard let m = meta.keys[key],
                  let data = try? Data(contentsOf: fileURL(folder, key)),
                  data.count == m.bytes,
                  sha256Hex(data) == m.sha256 else { continue }
            out[key] = MacSnapshotEntry(key: key, data: data, changeTag: m.changeTag,
                                        updatedAt: m.updatedAt, fetchedAt: m.fetchedAt)
        }
        return out
    }

    private static func readMeta(_ folder: URL) -> MacSnapshotMeta? {
        guard let data = try? Data(contentsOf: metaURL(folder)) else { return nil }
        return try? JSONDecoder().decode(MacSnapshotMeta.self, from: data)
    }

    // MARK: - 存

    /// 背景存幾個鍵（只收 MacCloud.readKeys 的）；dropped＝雲端已經沒有的鍵，快照也拿掉。
    /// 先寫各鍵、最後讀舊 meta 合併再寫 meta.json；失敗就算了，不跳錯。
    static func save(_ entries: [MacSnapshotEntry], dropping dropped: [String] = [], to folder: URL) {
        // sim2: snap#4 只存 MacCloud.readKeys 那 5 個鍵
        let keep = entries.filter { e in MacCloud.readKeys.contains(e.key) }
        let drop = dropped.filter { k in MacCloud.readKeys.contains(k) }
        guard !keep.isEmpty || !drop.isEmpty else { return }
        queue.async {
            MacSnapshotCache.writeAll(keep, drop: drop, to: folder)
        }
    }

    /// 只在 queue 上跑
    private static func writeAll(_ entries: [MacSnapshotEntry], drop: [String], to folder: URL) {
        let fm = FileManager.default
        // 只是拿掉、資料夾本來就沒有：什麼都不做（不為了拿掉而建資料夾）
        if entries.isEmpty && !fm.fileExists(atPath: folder.path) { return }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            logger.error("快照資料夾建不起來 \(error.localizedDescription, privacy: .private)")
            return
        }
        var meta = readMeta(folder) ?? MacSnapshotMeta()
        if meta.v != 1 { meta = MacSnapshotMeta() }
        for key in drop {
            meta.keys.removeValue(forKey: key)
            try? fm.removeItem(at: fileURL(folder, key))
        }
        for e in entries {
            do {
                try e.data.write(to: fileURL(folder, e.key), options: .atomic)
                meta.keys[e.key] = MacSnapshotKeyMeta(changeTag: e.changeTag, updatedAt: e.updatedAt, fetchedAt: e.fetchedAt,
                                                      bytes: e.data.count, sha256: sha256Hex(e.data))
            } catch {
                // 寫不進去：meta 拿掉這個鍵（舊檔就算還在，下次也不會用）
                meta.keys.removeValue(forKey: e.key)
                logger.error("快照寫不進去 \(error.localizedDescription, privacy: .private)")
            }
        }
        do {
            let out = try JSONEncoder().encode(meta)
            try out.write(to: metaURL(folder), options: .atomic)
        } catch {
            logger.error("快照的 meta 寫不進去 \(error.localizedDescription, privacy: .private)")
        }
    }

    // MARK: - 小工具

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { b in String(format: "%02x", b) }.joined()
    }

    private static func fileURL(_ folder: URL, _ key: String) -> URL {
        folder.appendingPathComponent(key + ".json", isDirectory: false)
    }

    private static func metaURL(_ folder: URL) -> URL {
        folder.appendingPathComponent(metaName, isDirectory: false)
    }
}
