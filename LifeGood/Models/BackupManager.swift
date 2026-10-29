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

    // 防止並行快照：createSnapshotIfNeeded 由 .onAppear 與 .onChange(scenePhase) 兩處呼叫，
    // 冷啟動後立刻切背景（例如點通知進 App 又馬上切走）時兩者可能在同一秒內先後觸發，
    // 此時 lastSnapshotDate 尚未被前一次寫入更新，第二次呼叫會判斷「還沒到間隔」失敗而重跑一次，
    // 兩個背景佇列工作各自編碼並寫入同一個以秒為單位命名的檔案，造成競態覆寫與重複運算。
    // 比照 CloudSyncManager.isSyncing／EInvoiceSyncManager.isSyncing 既有寫法補上旗標。
    private var isSnapshotting = false

    // MARK: - 建立快照

    func createSnapshotIfNeeded(expense: ExpenseStore, finance: FinanceStore, life: LifeStore) {
        guard !isSnapshotting else { return }
        let now = Date()
        if let last = lastSnapshotDate, now.timeIntervalSince(last) < minInterval { return }
        createSnapshot(expense: expense, finance: finance, life: life)
    }

    @discardableResult
    func createSnapshot(expense: ExpenseStore, finance: FinanceStore, life: LifeStore) -> URL? {
        guard !isSnapshotting else { return nil }
        isSnapshotting = true
        // 只有「讀取 @Published 屬性、組出 UnifiedExport 結構」需要在主執行緒完成（純 struct copy，很快）；
        // 實際 JSONEncoder 編碼本身不碰 @Published，改到背景佇列做，避免資料量大時（App 啟動／進背景這種
        // 執行窗口極短的時機）卡住主執行緒。與 FullBackup.export 已採用的模式一致。
        let payload = UnifiedExport.build(expense: expense, finance: finance, life: life)
        // 統一使用同一個 Date 實例：檔名時間戳與 lastSnapshotDate 保持一致，
        // 避免兩次 Date() 因執行緒切換產生些微落差造成 availableSnapshots() 比對偏差。
        let now = Date()
        let ts = Int(now.timeIntervalSince1970)
        let url = backupDir.appendingPathComponent("backup_\(ts).json")
        // JSON 編碼、檔案寫入與清理都移到背景佇列，避免阻塞主執行緒造成 UI 卡頓
        // lastSnapshotDate 在寫入成功後才更新，避免 App 被 kill 時留下
        // 指向不存在檔案的時間戳，導致 debounce 誤判跳過下次快照。
        DispatchQueue.global(qos: .utility).async { [weak self] in
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(payload)
                try data.write(to: url, options: .atomic)
                DispatchQueue.main.async { self?.lastSnapshotDate = now }
            } catch {
                // 編碼或寫入失敗：不更新時間戳，讓下次 createSnapshotIfNeeded 能再試一次
            }
            self?.cleanOldBackups()
            DispatchQueue.main.async { self?.isSnapshotting = false }
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
