// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.640 mac1] 寫入日誌、寫前備份（14 天）、復原（20 步）、看門狗、黃金案例、寫入開關（judge_mac §O6、§O7）。
// 本機檔只放 Application Support/LifeGoodMac/<帳號雜湊>/（journal.json、backups/<鍵>-<時間>-<fingerprint>.json）；
// 換 Apple 帳號整個刪掉別的帳號資料夾。偏好一律 mac. 開頭。log 只用 .private，不 print。
// 看門狗照 scratchpad/radar/build/mac1/ledger_sim.py 的 Mac.watchdog：新增的不見、改的欄位變回改之前的值、刪的回來；
// 別台後來又改成第三個值不提示。
import Foundation
import os

/// 一筆在電腦做的動作（只存在這台 Mac 的沙盒）
struct MacJournalEntry: Codable, Identifiable {
    enum Kind: String, Codable {
        case add, edit, delete
    }

    let id: String
    let key: String
    let kind: Kind
    let itemID: String
    let at: Date
    let label: String
    /// edit：{"欄位": {"b": 改之前, "a": 改之後}}（"b"／"a" 不在＝那欄沒有值）
    let fieldsJSON: Data?
    /// delete：刪前那筆的原字典（復原、補回用；不認得的欄位也在）
    let rawBeforeJSON: Data?
    /// add、edit：寫出去之後那筆的原字典（補回用）
    let rawAfterJSON: Data?
    /// 已經處理過（補回成功、或之後在電腦又動了同一筆）
    var resolved: Bool
    /// edit：之後在電腦又改過的欄位（看門狗不再看這幾欄）
    var supersededFields: [String]

    var rawBefore: [String: Any]? { Self.object(rawBeforeJSON) }
    var rawAfter: [String: Any]? { Self.object(rawAfterJSON) }

    /// edit 的欄位：欄位 → (改之前, 改之後)
    var fields: [String: (before: Any?, after: Any?)] {
        guard let obj = Self.object(fieldsJSON) else { return [:] }
        var out: [String: (before: Any?, after: Any?)] = [:]
        for (k, v) in obj {
            let pair = v as? [String: Any]
            out[k] = (before: pair?["b"], after: pair?["a"])
        }
        return out
    }

    /// 還要看門狗看的欄位
    var watchedFields: [String] {
        let skip = Set(supersededFields)
        return fields.keys.filter { k in !skip.contains(k) }.sorted()
    }

    static func object(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        return (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any]
    }

    static func encode(_ object: [String: Any]?) -> Data? {
        guard let object, JSONSerialization.isValidJSONObject(object) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object, options: [])
    }

    /// 欄位 → (改之前, 改之後) 編成 fieldsJSON
    static func encodeFields(_ fields: [String: (before: Any?, after: Any?)]) -> Data? {
        var obj: [String: Any] = [:]
        for (k, pair) in fields {
            var p: [String: Any] = [:]
            if let b = pair.before { p.updateValue(b, forKey: "b") }
            if let a = pair.after { p.updateValue(a, forKey: "a") }
            obj.updateValue(p, forKey: k)
        }
        return encode(obj)
    }
}

/// 看門狗抓到的一筆
enum MacWatchdogReason: String {
    case addMissing, editReverted, editMissing, deleteBack
}

struct MacWatchdogItem: Identifiable {
    let entry: MacJournalEntry
    let reason: MacWatchdogReason
    /// editReverted：被蓋回去的欄位
    let revertedFields: [String]

    var id: String { entry.id }

    var text: String {
        switch reason {
        case .addMissing: return "電腦記的「\(entry.label)」不見了"
        case .editReverted: return "電腦改的「\(entry.label)」被改回原本的值"
        case .editMissing: return "電腦改過的「\(entry.label)」在另一台不見了"
        case .deleteBack: return "電腦刪掉的「\(entry.label)」又回來了"
        }
    }
}

/// 一份寫前備份
struct MacBackupFile: Identifiable, Hashable {
    let url: URL
    let key: String
    let at: Date
    var id: String { url.lastPathComponent }

    var keyName: String { key == LedgerMerge.incomesKey ? "收入" : "支出" }
}

@MainActor
final class MacJournal: ObservableObject {
    static let undoLimit = 20
    static let backupDays = 14
    static let recentDays = 7

    /// LedgerMerge 黃金案例（啟動跑一次；沒全過就不准寫）
    let golden: LedgerMergeGolden.Report

    @Published private(set) var accountHash: String?
    @Published private(set) var entries: [MacJournalEntry] = []
    @Published private(set) var backups: [MacBackupFile] = []
    /// 寫入開關（mac.writeEnabled.<帳號雜湊>，預設關）
    @Published private(set) var writeEnabled = false
    /// 看門狗〔不用了〕過的日誌 id（mac.watchdog.dismissed）
    @Published private(set) var dismissed: Set<String> = []
    /// 這次開 App 能復原的動作（日誌 id，舊的在前；最多 undoLimit 步）
    @Published private(set) var undoable: [String] = []

    private var lastAccountHash: String?
    private let logger = Logger(subsystem: "com.lifegood.app.mac", category: "journal")

    init() {
        let g = LedgerMergeGolden.run()
        golden = g
        dismissed = Set(UserDefaults.standard.stringArray(forKey: "mac.watchdog.dismissed") ?? [])
        if !g.allPassed {
            logger.error("LedgerMerge 自我檢查沒全過 \(g.passed, privacy: .private)/\(g.total, privacy: .private)")
        }
    }

    // MARK: - 帳號

    /// 換帳號：刪掉別的帳號資料夾、重新載入日誌與備份。回傳 true＝真的換成另一個帳號（呼叫端清復原堆疊）
    @discardableResult
    func switchAccount(_ hash: String?) -> Bool {
        guard hash != accountHash else { return false }
        accountHash = hash
        guard let hash else {
            // 登出或還在確認：鎖住、記憶體清空（檔案等下一個帳號登入時再決定刪不刪）
            entries = []
            backups = []
            undoable = []
            writeEnabled = false
            return false
        }
        let changed = lastAccountHash != nil && lastAccountHash != hash
        lastAccountHash = hash
        if changed {
            undoable = []
            dismissed = []
            UserDefaults.standard.set([String](), forKey: "mac.watchdog.dismissed")
        }
        removeOtherAccounts(keep: hash)
        entries = loadEntries()
        pruneEntries(now: Date())
        pruneBackups(now: Date())
        backups = scanBackups()
        writeEnabled = UserDefaults.standard.bool(forKey: "mac.writeEnabled.\(hash)") && golden.allPassed
        return changed
    }

    /// 寫入開關。黃金案例沒全過、沒有帳號一律打不開
    func setWriteEnabled(_ on: Bool) {
        guard let hash = accountHash else {
            writeEnabled = false
            return
        }
        let value = on && golden.allPassed
        UserDefaults.standard.set(value, forKey: "mac.writeEnabled.\(hash)")
        writeEnabled = value
    }

    // MARK: - 資料夾

    static func rootFolder() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("LifeGoodMac", isDirectory: true)
    }

    private var accountFolder: URL? {
        guard let hash = accountHash, let root = Self.rootFolder() else { return nil }
        return root.appendingPathComponent(hash, isDirectory: true)
    }

    private var backupFolder: URL? {
        accountFolder?.appendingPathComponent("backups", isDirectory: true)
    }

    private var journalURL: URL? {
        accountFolder?.appendingPathComponent("journal.json", isDirectory: false)
    }

    private func removeOtherAccounts(keep hash: String) {
        let fm = FileManager.default
        guard let root = Self.rootFolder() else { return }
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        let names = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
        for name in names where name != hash {
            try? fm.removeItem(at: root.appendingPathComponent(name))
        }
        if let folder = accountFolder {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    // MARK: - 寫前備份（雲端那份原 bytes；14 天）

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    /// 寫前備份；寫不進去回 false（MacCloudWriter 就不寫）
    func backup(key: String, data: Data) -> Bool {
        guard let dir = backupFolder else { return false }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            logger.error("備份資料夾建不起來 \(error.localizedDescription, privacy: .private)")
            return false
        }
        let fp = LedgerMerge.fingerprint(data)
        // 最新那份一模一樣就不再存一份
        if let latest = backups.first(where: { b in b.key == key }),
           latest.url.lastPathComponent.hasSuffix("-\(fp).json") {
            return true
        }
        let now = Date()
        let name = "\(key)-\(Self.stampFormatter.string(from: now))-\(fp).json"
        do {
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
        } catch {
            logger.error("備份寫不進去 \(error.localizedDescription, privacy: .private)")
            return false
        }
        pruneBackups(now: now)
        backups = scanBackups()
        return true
    }

    func loadBackup(_ file: MacBackupFile) -> Data? {
        try? Data(contentsOf: file.url)
    }

    /// 新的在前
    private func scanBackups() -> [MacBackupFile] {
        guard let dir = backupFolder else { return [] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        var out: [MacBackupFile] = []
        for name in names where name.hasSuffix(".json") {
            guard let parsed = Self.parseBackupName(name) else { continue }
            out.append(MacBackupFile(url: dir.appendingPathComponent(name), key: parsed.key, at: parsed.at))
        }
        return out.sorted { a, b in a.at > b.at }
    }

    /// 「<鍵>-yyyyMMdd-HHmmss-<fingerprint>.json」→ (鍵, 時間)
    private static func parseBackupName(_ name: String) -> (key: String, at: Date)? {
        for key in LedgerMerge.keys {
            let prefix = key + "-"
            guard name.hasPrefix(prefix) else { continue }
            let rest = name.dropFirst(prefix.count)
            guard rest.count >= 15 else { return nil }
            let stamp = String(rest.prefix(15))
            guard let at = stampFormatter.date(from: stamp) else { return nil }
            return (key: key, at: at)
        }
        return nil
    }

    private func pruneBackups(now: Date) {
        let limit = Double(Self.backupDays) * 86400
        for b in scanBackups() where now.timeIntervalSince(b.at) > limit {
            try? FileManager.default.removeItem(at: b.url)
        }
    }

    // MARK: - 日誌（7 天）

    @discardableResult
    func record(key: String, kind: MacJournalEntry.Kind, itemID: String, label: String,
                fields: [String: (before: Any?, after: Any?)], rawBefore: [String: Any]?,
                rawAfter: [String: Any]?) -> MacJournalEntry {
        let changed = Set(fields.keys)
        for i in entries.indices where entries[i].key == key && entries[i].itemID == itemID && !entries[i].resolved {
            switch kind {
            case .add, .delete:
                entries[i].resolved = true                         // 之後在電腦又加又刪：舊的那筆不再看
            case .edit:
                if entries[i].kind == .edit {
                    var s = Set(entries[i].supersededFields)
                    s.formUnion(changed)
                    entries[i].supersededFields = s.sorted()
                    if entries[i].watchedFields.isEmpty { entries[i].resolved = true }
                }
            }
        }
        let entry = MacJournalEntry(id: UUID().uuidString, key: key, kind: kind, itemID: itemID, at: Date(),
                                    label: label, fieldsJSON: kind == .edit ? MacJournalEntry.encodeFields(fields) : nil,
                                    rawBeforeJSON: MacJournalEntry.encode(rawBefore),
                                    rawAfterJSON: MacJournalEntry.encode(rawAfter),
                                    resolved: false, supersededFields: [])
        entries.append(entry)
        pruneEntries(now: Date())
        persist()
        return entry
    }

    func entry(_ id: String) -> MacJournalEntry? {
        entries.first { e in e.id == id }
    }

    func canUndo(_ entryID: String) -> Bool {
        undoable.contains(entryID)
    }

    /// 登記成能復原的一步（編輯器登記到視窗 UndoManager 時叫；復原、重做自己寫的那一筆不登記，才不會擠掉最舊那一步）
    func markUndoable(_ entryID: String) {
        guard !undoable.contains(entryID) else { return }
        undoable.append(entryID)
        if undoable.count > Self.undoLimit {
            undoable.removeFirst(undoable.count - Self.undoLimit)
        }
    }

    func clearUndo() {
        undoable = []
    }

    /// 補回成功、或使用者改回了：不再看
    func resolve(_ entryID: String) {
        guard let i = entries.firstIndex(where: { e in e.id == entryID }) else { return }
        entries[i].resolved = true
        persist()
    }

    /// 7 天內的，新的在前（資料來源頁「最近在電腦改的」）
    func recentEntries(now: Date = Date()) -> [MacJournalEntry] {
        let limit = Double(Self.recentDays) * 86400
        return entries.filter { e in now.timeIntervalSince(e.at) <= limit }.sorted { a, b in a.at > b.at }
    }

    private func pruneEntries(now: Date) {
        let limit = Double(Self.recentDays) * 86400
        entries.removeAll { e in now.timeIntervalSince(e.at) > limit }
    }

    private func loadEntries() -> [MacJournalEntry] {
        guard let url = journalURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([MacJournalEntry].self, from: data)) ?? []
    }

    private func persist() {
        guard let url = journalURL else { return }
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("日誌寫不進去 \(error.localizedDescription, privacy: .private)")
        }
    }

    // MARK: - 看門狗（sim Mac.watchdog）

    func watchdog(records: [String: MacKVRecord]) -> [MacWatchdogItem] {
        var out: [MacWatchdogItem] = []
        var parsed: [String: (arr: [Any], pos: [String: Int])] = [:]
        let limit = Double(Self.recentDays) * 86400
        let now = Date()
        for e in entries where !e.resolved && !dismissed.contains(e.id) && now.timeIntervalSince(e.at) <= limit {
            if parsed[e.key] == nil {
                guard let data = records[e.key]?.data, let arr = LedgerMerge.parseArray(data) else { continue }
                parsed[e.key] = (arr, LedgerMerge.index(arr).pos)
            }
            guard let current = parsed[e.key] else { continue }
            let at = current.pos[e.itemID]
            switch e.kind {
            case .add:
                if at == nil {
                    out.append(MacWatchdogItem(entry: e, reason: .addMissing, revertedFields: []))
                }
            case .edit:
                guard let at else {
                    out.append(MacWatchdogItem(entry: e, reason: .editMissing, revertedFields: []))
                    continue
                }
                let cur: [String: Any] = (current.arr[at] as? [String: Any]) ?? [:]
                let fields = e.fields
                var reverted: [String] = []
                for k in e.watchedFields {
                    guard let pair = fields[k] else { continue }
                    if !LedgerMerge.same(pair.before, pair.after) && LedgerMerge.same(cur[k], pair.before) {
                        reverted.append(k)
                    }
                }
                if !reverted.isEmpty {
                    out.append(MacWatchdogItem(entry: e, reason: .editReverted, revertedFields: reverted))
                }
            case .delete:
                if at != nil {
                    out.append(MacWatchdogItem(entry: e, reason: .deleteBack, revertedFields: []))
                }
            }
        }
        return out
    }

    /// 〔不用了〕
    func dismiss(_ items: [MacWatchdogItem]) {
        for item in items { dismissed.insert(item.id) }
        let keep = Set(entries.map { e in e.id })
        dismissed = dismissed.intersection(keep)
        UserDefaults.standard.set(Array(dismissed), forKey: "mac.watchdog.dismissed")
    }
}
