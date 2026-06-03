import Foundation

class BackupManager {
    static let shared = BackupManager()

    private let backupDir: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = docs.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let minInterval: TimeInterval = 600   // 兩次快照最短間隔 10 分鐘
    private let maxAge: TimeInterval = 86400       // 保留 24 小時

    private var lastSnapshotDate: Date? {
        get { UserDefaults.standard.object(forKey: "lifegood_last_backup") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lifegood_last_backup") }
    }

    // MARK: - 建立快照

    func createSnapshotIfNeeded(expense: ExpenseStore, finance: FinanceStore, life: LifeStore) {
        let now = Date()
        if let last = lastSnapshotDate, now.timeIntervalSince(last) < minInterval { return }
        createSnapshot(expense: expense, finance: finance, life: life)
    }

    @discardableResult
    func createSnapshot(expense: ExpenseStore, finance: FinanceStore, life: LifeStore) -> URL? {
        // JSON 編碼需存取 @Published 屬性，必須在呼叫端（主執行緒）完成
        let data = UnifiedExporter.exportJSON(expense: expense, finance: finance, life: life)
        let ts = Int(Date().timeIntervalSince1970)
        let url = backupDir.appendingPathComponent("backup_\(ts).json")
        lastSnapshotDate = Date()
        // 檔案寫入與清理移到背景佇列，避免阻塞主執行緒造成 UI 卡頓
        DispatchQueue.global(qos: .utility).async { [weak self] in
            do {
                try data.write(to: url, options: .atomic)
            } catch {}
            self?.cleanOldBackups()
        }
        return url
    }

    // MARK: - 查詢可用快照

    func availableSnapshots() -> [(url: URL, date: Date)] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [] }

        return files.compactMap { url -> (url: URL, date: Date)? in
            let name = url.deletingPathExtension().lastPathComponent
            guard name.hasPrefix("backup_"),
                  let ts = TimeInterval(name.dropFirst("backup_".count)) else { return nil }
            return (url, Date(timeIntervalSince1970: ts))
        }
        .sorted { $0.date > $1.date }
    }

    func findRestoreCandidate() -> (url: URL, date: Date)? {
        let oneHourAgo = Date().addingTimeInterval(-3600)
        return availableSnapshots().first { $0.date <= oneHourAgo }
    }

    // MARK: - 復原

    func restore(from url: URL, expense: ExpenseStore, finance: FinanceStore, life: LifeStore) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard (try? decoder.decode(UnifiedExport.self, from: data)) != nil else { return false }
        _ = UnifiedImporter.importData(
            data: data, mode: .replace,
            expense: expense, finance: finance, life: life
        )
        return true
    }

    // MARK: - 清理

    private func cleanOldBackups() {
        let cutoff = Date().addingTimeInterval(-maxAge)
        for snapshot in availableSnapshots() where snapshot.date < cutoff {
            try? FileManager.default.removeItem(at: snapshot.url)
        }
    }
}
