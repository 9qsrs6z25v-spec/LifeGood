import Foundation

// [v25.640 mac1] 收支同步補強：只給 iPhone／iPad（只勾 LifeGood target，不進 Mac、小工具、手錶）。
//
// 每個收支鍵（lifegood_expenses、lifegood_incomes）存兩份：
//   - base：這台上次跟雲端對齊的那一份（推成功的、或合併完的雲端那份）。三方合併的共同祖先。
//   - inbox：拉下來、還沒在主執行緒合併的雲端那一份。
//   - pending：推出去、還沒收到成功回報的那一份（回報掉了但其實寫進去時，拉回來認得是自己的回音）。
// 放 Application Support/LedgerSync/<鍵>.base.json、.inbox.json、.pending.json；不是同步鍵、不進 UserDefaults、不推上雲。
// 內容就是本來已經在 UserDefaults 裡的收支，不是新的資料外流。
// 重置、換帳號、共享切換、zone 重建（CloudKitManager 清推送帳本的三處）一律 clearAll()：沒有 base＝退回以前的行為。
// 讀寫都在自己的序列佇列上（CloudKit 佇列、主執行緒都會叫；這個佇列裡不會再叫回自己，不會死鎖）。
final class LedgerSyncState {
    static let shared = LedgerSyncState()

    private let queue = DispatchQueue(label: "LedgerSyncState.queue", qos: .utility)
    private let directory: URL?

    private init() {
        let fm = FileManager.default
        if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dir = support.appendingPathComponent("LedgerSync", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            directory = dir
        } else {
            directory = nil
        }
    }

    // MARK: - base

    func base(_ key: String) -> Data? {
        queue.sync { read(key, kind: "base") }
    }

    func setBase(_ key: String, _ data: Data) {
        queue.sync { write(key, kind: "base", data: data) }
    }

    /// 推成功：base＝推上去的那份，pending 清掉
    func didPush(_ key: String, _ data: Data) {
        queue.sync {
            write(key, kind: "base", data: data)
            remove(key, kind: "pending")
        }
    }

    /// runFetch 收支分支：拉下來的這一份是不是回音（是＝不放 inbox）。sim: NewDevice.pull
    /// ① 跟 base 一樣（自己剛推的）
    /// ② 跟 pending 一樣（推出去但沒收到成功回報、其實寫進去了）→ 當 base
    /// ③ 還沒有 base、而且 UserDefaults 裡那份跟它一樣 → 當 base（兩邊本來就一樣）
    func absorbEcho(_ key: String, _ data: Data, defaultsData: Data?) -> Bool {
        queue.sync {
            let b = read(key, kind: "base")
            if b == data { return true }
            if read(key, kind: "pending") == data {
                write(key, kind: "base", data: data)
                remove(key, kind: "pending")
                return true
            }
            if b == nil, defaultsData == data {
                write(key, kind: "base", data: data)
                return true
            }
            return false
        }
    }

    // MARK: - pending（推出去、還不知道有沒有寫進去的那份）

    /// modifyKV 送出 CKModifyRecordsOperation 之前記一份
    func setPending(_ key: String, _ data: Data) {
        queue.sync { write(key, kind: "pending", data: data) }
    }

    // MARK: - inbox

    func inbox(_ key: String) -> Data? {
        queue.sync { read(key, kind: "inbox") }
    }

    func hasInbox(_ key: String) -> Bool {
        inbox(key) != nil
    }

    func putInbox(_ key: String, _ data: Data) {
        queue.sync { write(key, kind: "inbox", data: data) }
    }

    func clearInbox(_ key: String) {
        queue.sync { remove(key, kind: "inbox") }
    }

    /// 合併完只清「合併的那一份」：主執行緒合併期間 CloudKit 執行緒又放進新的一份（R2）就留著，
    /// 排在後面的那次通知會拿它跟這次的 base 再合併一次
    func clearInbox(_ key: String, ifEqual data: Data) {
        queue.sync {
            if read(key, kind: "inbox") == data { remove(key, kind: "inbox") }
        }
    }

    // MARK: - 清掉

    /// 這個鍵的 base、inbox 都清（整包覆蓋類流程：覆蓋本機、合併、還原、共享切換）
    func clear(_ key: String) {
        queue.sync {
            remove(key, kind: "base")
            remove(key, kind: "inbox")
            remove(key, kind: "pending")
        }
    }

    /// 兩個鍵全部清（resetLocalState、zone 重建、雲端資料區不存在）
    func clearAll() {
        queue.sync {
            for key in LedgerMerge.keys {
                remove(key, kind: "base")
                remove(key, kind: "inbox")
                remove(key, kind: "pending")
            }
        }
    }

    // MARK: - 檔案（只在 queue 上叫）

    private func url(_ key: String, kind: String) -> URL? {
        guard LedgerMerge.handles(key), let dir = directory else { return nil }
        return dir.appendingPathComponent("\(key).\(kind).json")
    }

    private func read(_ key: String, kind: String) -> Data? {
        guard let u = url(key, kind: kind) else { return nil }
        return try? Data(contentsOf: u)
    }

    private func write(_ key: String, kind: String, data: Data) {
        guard let u = url(key, kind: kind) else { return }
        try? data.write(to: u, options: .atomic)
    }

    private func remove(_ key: String, kind: String) {
        guard let u = url(key, kind: kind) else { return }
        try? FileManager.default.removeItem(at: u)
    }
}
