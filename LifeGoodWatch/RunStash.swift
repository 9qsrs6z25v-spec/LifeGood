import Foundation

// MARK: - 跑步存檔（手錶 v4，v25.580；watch/judge.md §2.11「當機重開後」、§2.12「存不進 Apple 健康時」；watch/build/v4/brief.md §2）
//
// 只屬於 LifeGoodWatch（主控寫好；各組只准叫，不准改）。手錶 App 自己的 Application Support/RunCheckpoints/ 底下兩個檔：
//   • current.json：跑步中的這一趟（WorkoutManager 按開始那一刻先寫一次、之後每 30 秒、暫停、繼續、每滿一公里再寫）。
//     當機重開：系統叫 handleActiveWorkoutRecovery → WorkoutManager 接回 session、從這裡拿回每公里時間、暫停、路線點；
//     系統沒叫（session 已經沒了）→ 這一份變成「沒存成的那一趟」（unsaved），摘要〔再存一次〕。存好或丟掉就刪。
//   • unsaved.json：存不進 Apple 健康的那一趟（跑到一半把健康權限關掉、系統出錯）。下次打開 App 也還在，〔再存一次〕存好才刪。
// 不放 App Group（手錶小格用不到；路線點只留在手錶 App 自己的資料夾）、不進備份；檔案保護
// completeUntilFirstUserAuthentication（同 iPhone 收件匣）。寫都在一條背景佇列排隊；讀用同一條佇列 sync（讀到的一定是排在前面的寫之後）。

enum RunStash {
    private static let queue = DispatchQueue(label: "com.lifegood.watch.run.stash", qos: .utility)
    static let currentName = "current.json"
    static let unsavedName = "unsaved.json"
    /// 超過這麼久的檔不要（當機那一趟一個禮拜都沒打開 App：不接、不存）
    static let maxAge: TimeInterval = 7 * 86_400

    /// 資料夾（第一次用到時建好、不進備份）；拿不到回 nil（什麼都不寫，不會閃退）
    static func directory() -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        var dir = base.appendingPathComponent("RunCheckpoints", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                return nil
            }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? dir.setResourceValues(values)
        }
        return dir
    }

    // MARK: 跑步中

    /// 寫跑步中的這一趟（背景；覆蓋）
    static func saveCurrent(_ record: WatchRunRecord) {
        write(record, name: currentName)
    }

    /// 讀跑步中的那一趟（沒有、解不開、太舊回 nil）
    static func loadCurrent() -> WatchRunRecord? {
        read(name: currentName)
    }

    /// 刪（存好了、丟掉了、變成 unsaved 了）
    static func clearCurrent() {
        remove(name: currentName)
    }

    // MARK: 沒存成的那一趟

    static func saveUnsaved(_ record: WatchRunRecord) {
        write(record, name: unsavedName)
    }

    static func loadUnsaved() -> WatchRunRecord? {
        read(name: unsavedName)
    }

    static func clearUnsaved() {
        remove(name: unsavedName)
    }

    // MARK: 內部

    private static func write(_ record: WatchRunRecord, name: String) {
        queue.async {
            guard let url = RunStash.directory()?.appendingPathComponent(name),
                  let data = try? JSONEncoder().encode(record) else { return }
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    private static func read(name: String) -> WatchRunRecord? {
        queue.sync { () -> WatchRunRecord? in
            guard let url = RunStash.directory()?.appendingPathComponent(name),
                  let data = try? Data(contentsOf: url) else { return nil }
            guard let record = try? JSONDecoder().decode(WatchRunRecord.self, from: data),
                  Date().timeIntervalSince(record.updatedAt) <= RunStash.maxAge else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return record
        }
    }

    private static func remove(name: String) {
        queue.async {
            guard let url = RunStash.directory()?.appendingPathComponent(name) else { return }
            try? FileManager.default.removeItem(at: url)
        }
    }
}
