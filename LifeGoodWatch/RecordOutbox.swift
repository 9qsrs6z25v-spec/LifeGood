import Foundation

// MARK: - 手錶的待送盒（手錶 v2，v25.576；watch/judge.md §2.6「記好了」、§2.15、§4.3、§4.4；watch/build/v2/brief.md §2）
//
// 只屬於 LifeGoodWatch。手錶記的每一筆先放這裡（一筆一個檔，照 iPhone QuickRecordInbox 的寫法），
// 10 秒內〔復原〕＝只刪手錶上這個檔、根本還沒送出去；過了 10 秒（或按〔完成〕、翻走、手腕放下）才送：
//   transferUserInfo（排隊、保證送到、照順序）＋ iPhone 在旁邊時再 sendMessage（會把 iPhone 在背景叫醒、有回話）。
//   兩條都到也只記一次：iPhone 用編號擋（WatchImportedLog＋收件匣 id＝支出 id）。
// 時間一律是按下去那一刻（WatchRecord.createdAt），不是送到的時間。
//
// 檔：手錶 App Group 的 Widgets/watch_outbox_v1/<編號>.json（只有手錶 App 這個行程碰，手錶小格不讀）。
// 狀態（WatchOutboxItem.State）：
//   holding 10 秒內還在手錶上 → sent 送出了（系統排隊中）→ delivered iPhone 收到了（transferUserInfo 送完）
//   → queued 在 iPhone 收件匣等打開 App（iPhone 回話、或新包的 queuedIds）／imported 已經入帳（iPhone 回話）
//   → 新包的 includedIds 有它：刪檔。
//   已經送出、連續 3 包（每包都比送出晚 60 秒以上、同一包不重算）兩張名單都沒有它（例：在 iPhone 上刪了）
//   → deleted「在 iPhone 上被刪掉了」（灰字），24 小時後刪檔——不會永遠卡在「已送出」。
//   之後的包 queuedIds 又有它（iPhone 收件匣裡有＝沒被刪）：改回 queued（[裁定] watch/build/v2/adjudicate.md §2）。
//   [手錶 v6] 系統排隊裡還沒送完的（WatchSync.outstandingRecordIds，transferUserInfo 還在手錶上）＝iPhone 根本還沒收到：
//   那幾包沒有它**不算**「沒有它」（v2 已知限制：iPhone 在家時一直有更新，回到身邊先被數成「在 iPhone 上被刪掉了」）。
//   已經被數成 deleted 的也改回 sent。sim_v6.py outbox_reconcile_v6。
// 規則跟 scratchpad/watch/build/v2/sim_v2.py 的 outbox_* 一模一樣（改了兩邊一起改、重跑 sim）。
//
// ⚠️ RecordOutboxStore（檔案）在 WatchSync 的背景執行緒也會被叫（收到新包就收尾）：一律過 lock。
//    RecordOutbox（畫面用的那一份）在主執行緒；WatchSync 要叫它一律 Task { @MainActor in … }。

/// 待送盒的一筆
struct WatchOutboxItem: Codable, Equatable, Identifiable {
    enum State: String, Codable {
        /// 10 秒內還在手錶上（按〔復原〕就不記）
        case holding
        /// 送出了（transferUserInfo 在系統排隊中）
        case sent
        /// iPhone 收到了（transferUserInfo 送完、沒有錯）
        case delivered
        /// 在 iPhone 收件匣等打開 iPhone 上的 LifeGood 才入帳
        case queued
        /// iPhone 回「已經入帳」（等新包的 includedIds 帶著它回來才刪檔）
        case imported
        /// 在 iPhone 上被刪掉了（24 小時後刪檔）
        case deleted
    }

    var record: WatchRecord
    /// 這個時間以後才送（按下去＋10 秒）
    var sendAfter: Date
    var state: State
    /// 第一次送出的時間
    var sentAt: Date? = nil
    /// 上一次拿來對名單的那一包（generatedAt）：同一包不重算
    var lastPackageAt: Date? = nil
    /// 已經送出之後，連續幾包兩張名單都沒有它
    var misses: Int = 0
    /// 標成 deleted 的時間
    var deletedAt: Date? = nil

    var id: UUID { record.id }
    /// 還沒送到 iPhone（設定「還沒送到 iPhone：N 筆」）
    var isUnsent: Bool { state == .holding || state == .sent }
}

// MARK: - 檔案（任何執行緒都可以叫；一律過 lock）

enum RecordOutboxStore {
    /// <手錶 App Group>/Widgets/ 底下的資料夾
    static let folderName = "watch_outbox_v1"
    /// 連續幾包都沒有它就當作在 iPhone 上被刪掉了
    static let missLimit = 3
    /// 包要比送出晚這麼多才算一次「沒有它」（iPhone 還沒收到時組的包不算）
    static let missSlack: TimeInterval = 60
    /// 「在 iPhone 上被刪掉了」留多久
    static let deletedKeep: TimeInterval = 24 * 3600

    private static let lock = NSLock()

    // MARK: 位置

    static func folderURL(create: Bool) -> URL? {
        guard let base = WidgetSnapshotStore.folderURL(create: create) else { return nil }
        let folder = base.appendingPathComponent(folderName, isDirectory: true)
        if create {
            let attributes: [FileAttributeKey: Any] = [
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ]
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                        attributes: attributes)
            } catch {
                return nil
            }
        }
        return folder
    }

    private static func fileURL(_ id: UUID, in folder: URL) -> URL {
        folder.appendingPathComponent(id.uuidString + ".json", isDirectory: false)
    }

    // MARK: 讀寫（呼叫的人自己拿 lock 的那幾支是 private 的 unlocked 版本）

    /// 全部，依按下去的時間由舊到新（同一刻編號字串小的先）
    static func loadAll() -> [WatchOutboxItem] {
        lock.lock()
        defer { lock.unlock() }
        return unlockedLoadAll()
    }

    /// 寫一筆（原子寫入、跟 iPhone 收件匣同一個保護等級）。寫不進去回 false
    @discardableResult
    static func save(_ item: WatchOutboxItem) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return unlockedSave(item)
    }

    static func remove(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        unlockedRemove(id)
    }

    /// 讀出那一筆、改、寫回；沒有那一筆回 false
    @discardableResult
    static func update(_ id: UUID, _ change: (inout WatchOutboxItem) -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard var item = unlockedLoadAll().first(where: { $0.id == id }) else { return false }
        change(&item)
        return unlockedSave(item)
    }

    /// 收到 iPhone 的新包（WatchSync.applyData 寫好檔之後，背景執行緒）：對 includedIds／queuedIds 收尾。
    /// [v6] outstanding＝系統排隊裡還沒送完的記帳編號（WatchSync.outstandingRecordIds）
    static func reconcile(with package: WatchPackage, now: Date, outstanding: Set<UUID> = []) {
        lock.lock()
        defer { lock.unlock() }
        let old = unlockedLoadAll()
        let result = reconciled(old, package: package, now: now, outstanding: outstanding)
        for id in result.remove {
            unlockedRemove(id)
        }
        for item in result.keep where !old.contains(item) {
            unlockedSave(item)
        }
    }

    // MARK: 規則（純函式；sim_v2.py outbox_reconcile）

    /// 對一包收尾：在 includedIds＝刪；在 queuedIds＝queued（已經標成 deleted 的也改回來）；已送出而且連續 3 包都沒有＝deleted；
    /// deleted 滿 24 小時＝刪。
    /// 還在 10 秒內（holding）的不動。[v6] 還在系統排隊裡（outstanding）的不數「沒有它」，deleted 的改回 sent
    static func reconciled(_ items: [WatchOutboxItem], package: WatchPackage, now: Date,
                           outstanding: Set<UUID> = []) -> (keep: [WatchOutboxItem], remove: [UUID]) {
        let included = Set(package.includedIds ?? [])
        let queued = Set(package.queuedIds ?? [])
        var keep: [WatchOutboxItem] = []
        var remove: [UUID] = []
        for original in items {
            var item = original
            if item.state == .holding {
                keep.append(item)
                continue
            }
            if included.contains(item.id) {
                remove.append(item.id)
                continue
            }
            // [裁定] queuedIds 排在 deleted 前面：iPhone 收件匣裡有它＝沒被刪掉。iPhone 在家時錶面推送的舊包
            // 一回到身邊連著到 3 包、手錶那份 transferUserInfo 還沒被 iPhone 收進去，會先被數成「被刪掉了」；
            // 之後的包說它在收件匣，就改回「在 iPhone 等著入帳」（不然要等打開 iPhone 入帳、或 24 小時才變）
            if queued.contains(item.id) {
                item.state = .queued
                item.misses = 0
                item.deletedAt = nil
                item.lastPackageAt = package.generatedAt
                keep.append(item)
                continue
            }
            // [v6] iPhone 根本還沒收到（transferUserInfo 還在手錶的系統排隊裡）：這一包沒有它不算數
            if outstanding.contains(item.id) {
                if item.state == .deleted {
                    item.state = .sent
                    item.deletedAt = nil
                    item.misses = 0
                }
                keep.append(item)
                continue
            }
            if item.state == .deleted {
                if let at = item.deletedAt, now.timeIntervalSince(at) >= deletedKeep {
                    remove.append(item.id)
                } else {
                    keep.append(item)
                }
                continue
            }
            guard let sent = item.sentAt, package.generatedAt > sent.addingTimeInterval(missSlack) else {
                keep.append(item)
                continue
            }
            if let last = item.lastPackageAt, package.generatedAt <= last {
                keep.append(item)
                continue
            }
            item.lastPackageAt = package.generatedAt
            item.misses += 1
            if item.misses >= missLimit {
                item.state = .deleted
                item.deletedAt = now
            }
            keep.append(item)
        }
        return (keep: keep, remove: remove)
    }

    // MARK: 沒拿 lock 的版本

    private static func unlockedLoadAll() -> [WatchOutboxItem] {
        guard let folder = folderURL(create: false) else { return [] }
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                      options: [.skipsHiddenFiles]) else { return [] }
        var out: [WatchOutboxItem] = []
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let item = try? WidgetSnapshotStore.makeDecoder().decode(WatchOutboxItem.self, from: data) {
                out.append(item)
            } else {
                // 解不開的壞檔刪掉（不然每次都卡在這裡）
                try? FileManager.default.removeItem(at: url)
            }
        }
        return out.sorted { a, b in
            if a.record.createdAt != b.record.createdAt { return a.record.createdAt < b.record.createdAt }
            return a.id.uuidString < b.id.uuidString
        }
    }

    @discardableResult
    private static func unlockedSave(_ item: WatchOutboxItem) -> Bool {
        guard let folder = folderURL(create: true),
              let data = try? WidgetSnapshotStore.makeEncoder().encode(item) else { return false }
        do {
            try data.write(to: fileURL(item.id, in: folder),
                           options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }

    private static func unlockedRemove(_ id: UUID) {
        guard let folder = folderURL(create: false) else { return }
        try? FileManager.default.removeItem(at: fileURL(id, in: folder))
    }
}

// MARK: - 畫面用的那一份（主執行緒）

@MainActor
final class RecordOutbox: ObservableObject {
    static let shared = RecordOutbox()

    /// 〔復原〕可以按多久（也是幾秒後才送）
    static let undoSeconds: TimeInterval = 10
    /// sendMessage 送出後等 iPhone 回話多久，沒回就寫「還沒送到 iPhone，先存在手錶上」
    static let replyTimeout: TimeInterval = 5

    enum AddResult: Equatable {
        case added
        /// 3 秒內同一格：不記
        case ignoredDoubleTap
        /// 手錶上寫不進檔（幾乎不會發生）
        case failed
    }

    /// 待送盒裡全部（含在 iPhone 上被刪掉、24 小時內的）
    @Published private(set) var items: [WatchOutboxItem]
    /// 這次打開 App 記的幾筆送到哪了（記好了那一頁、記帳台橫幅看）；App 重開就沒有（看 items 的 state）
    @Published private(set) var status: [UUID: RecordSendState] = [:]

    private init() {
        items = RecordOutboxStore.loadAll()
    }

    // MARK: 讀

    func reload() {
        items = RecordOutboxStore.loadAll()
    }

    /// 還沒送到 iPhone 的筆數（設定第一行「還沒送到 iPhone：N 筆」；0 筆整行不出現）
    var unsentCount: Int {
        RecordText.unsentCount(items)
    }

    /// 這一筆送到哪了：這次送的看 status；App 重開過的照檔裡的 state 推
    func sendState(of id: UUID) -> RecordSendState? {
        if let s = status[id] { return s }
        guard let item = items.first(where: { $0.id == id }) else { return nil }
        return RecordText.sendState(for: item, unsent: unsentCount)
    }

    // MARK: 記、復原

    /// 記一筆（記帳台點一格、〔記下來〕）：寫進待送盒，10 秒後才送。3 秒內同一格不記
    @discardableResult
    func add(_ record: WatchRecord, now: Date = Date()) -> AddResult {
        if let tid = record.templateId, RecordText.isDoubleTap(templateId: tid, at: now, in: items) {
            return .ignoredDoubleTap
        }
        let item = WatchOutboxItem(record: record, sendAfter: now.addingTimeInterval(Self.undoSeconds), state: .holding)
        guard RecordOutboxStore.save(item) else { return .failed }
        reload()
        status[record.id] = .holding
        scheduleSendDue(after: Self.undoSeconds)
        return .added
    }

    /// 〔復原〕：還在 10 秒內（holding）就刪掉、回 true；已經送出去回 false（要刪到 iPhone 刪）
    @discardableResult
    func undo(_ id: UUID) -> Bool {
        guard let item = items.first(where: { $0.id == id }), item.state == .holding else { return false }
        RecordOutboxStore.remove(id)
        status[id] = nil
        reload()
        return true
    }

    // MARK: 送

    /// 到期的送出（10 秒到了、回前景、收到包、WCSession activate 好）
    func sendDue(now: Date = Date()) {
        send(items.filter { $0.state == .holding && $0.sendAfter <= now }, now: now)
    }

    /// 〔完成〕、翻走、手腕放下、App 進背景：還在 10 秒內的也馬上送（等於你接受了）
    func sendHoldingNow(now: Date = Date()) {
        send(items.filter { $0.state == .holding }, now: now)
    }

    /// 設定〔現在送〕：還在手錶上的＋送出了但系統排隊裡已經沒有、iPhone 也還沒確認收到的，再送一次（iPhone 用編號擋重複）
    func resendUnconfirmed(now: Date = Date()) {
        let outstanding = WatchSync.shared.outstandingRecordIds()
        let list = items.filter { item in
            item.state == .holding || (item.state == .sent && !outstanding.contains(item.id))
        }
        send(list, now: now)
    }

    private func send(_ list: [WatchOutboxItem], now: Date) {
        guard !list.isEmpty else { return }
        var waiting: [UUID] = []
        for item in list {
            // 還沒 activate 好、手錶上沒有 WatchConnectivity：留著（holding 照舊），下次再送
            guard WatchSync.shared.sendRecord(item.record) else { continue }
            RecordOutboxStore.update(item.id) { stored in
                if stored.state == .holding {
                    stored.state = .sent
                }
                if stored.sentAt == nil {
                    stored.sentAt = now
                }
            }
            waiting.append(item.id)
        }
        reload()
        let reachable = WatchSync.shared.isPhoneReachable
        for id in waiting {
            if reachable {
                status[id] = .waiting
            } else {
                status[id] = .offline(count: unsentCount)
            }
        }
        if reachable && !waiting.isEmpty {
            scheduleReplyTimeout(waiting)
        }
    }

    // MARK: WatchSync 回來（主執行緒）

    /// sendMessage 的回話：["ok": "imported"|"queued"|"failed", "today": 3]
    func phoneReplied(_ id: UUID, ok: String?, today: Int?) {
        switch ok {
        case WatchLink.okImported:
            RecordOutboxStore.update(id) { $0.state = .imported }
            status[id] = .imported(today: today)
        case WatchLink.okQueued:
            RecordOutboxStore.update(id) { $0.state = .queued }
            status[id] = .queued
        default:
            reload()
            status[id] = .offline(count: unsentCount)
            return
        }
        reload()
    }

    /// sendMessage 失敗（iPhone 不在旁邊、LifeGood 被滑掉…）：transferUserInfo 那一份照樣排著
    func phoneUnreachable(_ id: UUID) {
        // 已經有 iPhone 的回話（imported／queued）就不蓋掉
        if let s = status[id], s.hasPhoneReply { return }
        reload()
        status[id] = .offline(count: unsentCount)
    }

    /// transferUserInfo 送完、沒有錯：iPhone 收到了（還沒回話、也還沒在包裡的，至少不再算「還沒送到」）
    func markDelivered(_ id: UUID) {
        RecordOutboxStore.update(id) { stored in
            if stored.state == .sent {
                stored.state = .delivered
            }
        }
        reload()
    }

    /// WatchSync 收到新包、RecordOutboxStore.reconcile 做完之後：重讀、把到期沒送的補送
    func packageApplied() {
        reload()
        sendDue()
    }

    // MARK: 計時

    private func scheduleSendDue(after seconds: TimeInterval) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            RecordOutbox.shared.sendDue()
        }
    }

    private func scheduleReplyTimeout(_ ids: [UUID]) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(RecordOutbox.replyTimeout * 1_000_000_000))
            RecordOutbox.shared.replyTimedOut(ids)
        }
    }

    private func replyTimedOut(_ ids: [UUID]) {
        reload()
        for id in ids where status[id] == .waiting {
            status[id] = .offline(count: unsentCount)
        }
    }
}
