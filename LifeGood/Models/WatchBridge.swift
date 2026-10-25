import Foundation
import UIKit
import WatchConnectivity

// MARK: - iPhone 這一頭的手錶傳話（手錶 v1，v25.574；只屬於主 App；watch/judge.md §5.2、§5.4、§7.8-5／6、附錄 B；
//         watch/build/v1/brief.md G1-1；送不送、走哪條路照 watch/build/v1/sim_v1.py 的 bridge_decide）
//
// 誰叫：
//   • AppDelegate.didFinishLaunching → activate()（手錶叫醒 iPhone 時要有人接；iPad、Mac 上 isSupported 是 false，什麼都不做）
//   • WidgetSnapshotWriter.writeNow 寫完 → snapshotsDidChange()
//   • 設定頁改了「送到手錶」的開關、「隱藏金額」→ settingsChanged()
//   • [v2] 設定頁「手機條碼」開關、EInvoiceSyncManager 連結／拿掉手機條碼 → settingsChanged()
//   • [v2] 手錶記一筆（sendMessage 帶 "record"、transferUserInfo）→ receiveRecord
//   • [v6] 手錶打卡（sendMessage 帶 "checkIn"、transferUserInfo）→ receiveCheckIn
//   • [v6] 系統換時區（NSSystemTimeZoneDidChange，activate() 裡掛一次）→ timeZoneChanged()
//
// 送包（refresh）：WatchPackageBuilder 只讀 App Group 的檔組一包 → WidgetSnapshotStore.write（iPhone 自己的 watch_v1.json，
// 拿掉 generatedAt 比內容）回 true＝內容變了。下面三種「不比內容也送」：
//   • 換錶、重新配對、手錶版第一次裝好：session.watchDirectoryURL（每支錶一個、手錶版刪掉時系統一起清）底下沒有記號檔
//   • 上次沒送成（還沒啟動好、沒配對、沒裝、送的時候出錯）：App Group 的 watch_send_pending
//   • 手錶要（sendMessage ["want": "pkg"]）：直接回覆那一包
// 走哪條路：壓完 ≤ 48 KB 用 updateApplicationContext（只留最新一份）；錶面的字變了（WatchPackageDiff.widgetKinds 不是空的）
// 而且錶面真的放了 LifeGood、系統還有額度、今天用不到 30 次 → 再多走 transferCurrentComplicationUserInfo（比較快叫醒手錶）；
// 壓完 > 48 KB 改用 transferFile。
//
// ⚠️ 被手錶叫醒的冷啟動也會跑到這裡：每個 delegate 方法只讀寫 App Group 的檔與 UserDefaults，
//    不碰 App 的三份大資料、不 start 任何寫入器、不算數字（judge §5.4、§7.8-6；pkg_keys_check.py D 段擋）。
//    回「給我最新的」時先叫 WidgetSnapshotWriter.shared.writeNow()：App 活著＝先重寫快照；冷啟動時寫手還沒 start、什麼都不做。
// ⚠️ WCSession 的 delegate 方法在背景執行緒：一律 nonisolated、要動狀態包 Task { @MainActor in … }（照 RunTracker 的寫法）。
//
// [手錶 v2] v25.576（watch/judge.md §4.1、§4.3、§5.4、§5.5、附錄 B；watch/build/v2/brief.md G1-1）：收手錶記的帳——
//   • 手錶每一筆走兩條路：transferUserInfo（排隊、保證送到；didReceiveUserInfo，沒有回話）＋ iPhone 在旁邊時再 sendMessage
//     （didReceiveMessage 帶 "record"，回 ["ok": "imported" | "queued" | "failed", "today": 3]）。兩條路都走 receiveRecord
//   • receiveRecord：解開 → 撐 3 秒背景時間（蓋過收件匣晚 2 秒收尾；連記好幾筆用最後一筆的 3 秒）
//     → watch_imported_ids 有＝另一條路早就入帳了，直接回 imported（不再進收件匣，iPhone 小工具不會冒出「待入帳 1 筆」）
//     → 放進收件匣（純檔案；收件匣編號＝那筆支出的編號，兩條路都到只記一次）
//     → QuickRecordImporter 準備好了（App 開著、或剛用過還活著）才 importFromWatch（只收手錶來的；小工具剛按、
//       還能〔復原〕的那筆不動）→ 入帳了回 imported＋今天幾筆（讀剛寫好的 money 快照）
//     → 不是（被手錶叫醒的冷啟動）：只重組包（queuedIds 變了就送）、回 queued，打開 iPhone 上的 LifeGood 才入帳
//   • 冷啟動照舊不碰三份大資料：收件匣、watch_imported_ids、小工具快照都只是 App Group 的檔
//
// [手錶 v6] v25.578（watch/judge.md §4.1、§4.4、§5.2「換時區」、§5.4、附錄 B 打卡那一列；watch/build/v6/brief.md G1-1）：
//   • 收手錶的打卡〔到了〕〔離開〕：跟記一筆一樣兩條路（transferUserInfo＋iPhone 在旁邊再 sendMessage，鍵 "checkIn"），
//     三支 delegate 方法（有回話、沒回話的 didReceiveMessage、didReceiveUserInfo）都走 receiveCheckIn
//   • receiveCheckIn：解開 → 撐 3 秒背景時間（跟記一筆同一個）→ WatchActionApplier 準備好了（App 開著、或剛用過還活著）
//     就馬上寫進行程（只補 iPhone 上還沒有的；寫進去它自己重寫 life 快照、手錶包跟著送），
//     回 ["ok": "done"]／["ok": "already", "at": 秒]（那一站本來就打過卡，不蓋）／["ok": "gone"]（那一站被刪了）
//     → 不是（被手錶叫醒的冷啟動）：只寫 watch_actions_v1/<編號>.json 一個小檔（WatchActionInbox.add）、回 queued；
//       打開 iPhone 上的 LifeGood（.task、回前景 WatchActionApplier.applyPending）才照按下去的時間順序寫進行程
//   • 寫行程一律經 WatchActionApplier（這個檔不直接動 LifeStore；pkg_keys_check.py D3 段擋）
//   • 換時區：收到 NSSystemTimeZoneDidChange（App 活著才收得到）→ timeZoneChanged：清掉系統時區的快取
//     （NSTimeZone.resetSystemTimeZone，Calendar.current 才是新的）→ WidgetSnapshotWriter.writeNow() 全部用新時區重寫
//     （快取的 timeZoneId 跟著換）→ 最後它自己叫 snapshotsDidChange() 重組重送。冷啟動時寫手沒 start，只會用現成的檔重組
//
// [手錶 v5] v25.582（watch/judge.md §2.12、§5.4、§5.7 最後一段、附錄 B ranWorkout／unsavedRun；watch/build/v5/brief.md G1-1；
//         sim_v5.py §7）：收手錶的「我跑完了」「沒存成」——
//   • 手錶兩條路一起送：transferUserInfo（排隊、保證送到；didReceiveUserInfo）＋ iPhone 在旁邊再 sendMessage
//     （replyHandler: nil，走沒回話的 didReceiveMessage）。三支 delegate 方法都在背景執行緒先拆好：
//     "ranWorkout"（Apple 健康編號；有這個鍵就是「我跑完了」，空字串＝讀不到編號也算）、"ranAt"（那一趟結束的時間，秒）、
//     "unsavedRun"（1＝有一趟存不進 Apple 健康、留在手錶上；0＝沒有了）
//   • 主執行緒 receiveRun：**只寫 WatchRunFlags**（App Group 的 UserDefaults；被手錶叫醒的冷啟動也對）。
//     有編號 → noteRan（記編號、清「沒存成」、記上次跑完）；不然有 unsavedRun → noteUnsaved。
//     不碰 Apple 健康同步、App 的三份大資料、不 refresh（旗子跟包無關）；健康頁回前景、收到 WatchRunFlags.changed 才去找那一筆
//   • 有回話的那支：記一筆、打卡都沒有、只有跑步 → 回 ["ok": "queued"]（手錶其實不等回話；保險）
//
// 對外的名字（WidgetSnapshotWriter、AppDelegate、設定頁在叫）不准改。

/// App Group 的鍵與檔名（WidgetShared.defaults；delegate 方法在背景執行緒也要讀得到，放在 actor 外面）
private enum WatchBridgeKeys {
    /// 上次送到手錶的時間（1970 起的秒，Double）
    static let lastSentAt = "watch_last_sent_at"
    /// 上次送到手錶的大小（壓縮後的位元組，Int）
    static let lastSentBytes = "watch_last_sent_bytes"
    /// 上次沒送成，下次一有機會就送（Bool）
    static let pending = "watch_send_pending"
    /// 錶面快速推送：哪一天（「2026-10-22」）、那天用了幾次
    static let facePushDay = "watch_face_push_day"
    static let facePushCount = "watch_face_push_count"
    /// 送到過這支錶的記號檔（session.watchDirectoryURL 底下）
    static let markerFile = "lg_watch_pkg_v1"
    /// 壓完超過 48 KB 改用 transferFile 時，暫存檔的開頭（「watch_v1_<秒>_<8 碼>.lzfse」；送完就刪）。
    /// 後面多 8 碼：同一秒送兩次時，被取消的舊那份收尾刪檔不會刪到新的那份
    static let tempFilePrefix = "watch_v1_"
    /// 錶面快速推送每天最多幾次（系統一天 50 次，留 20 次給 v2 記帳後馬上更新）
    static let facePushDailyCap = 30
}

@MainActor
final class WatchBridge: NSObject, ObservableObject {
    static let shared = WatchBridge()

    /// 這支 iPhone 有配對手錶（設定頁「Apple Watch」段沒配對就整段不出現）
    @Published private(set) var isPaired = false
    /// 手錶上裝了 LifeGood 手錶版
    @Published private(set) var isWatchAppInstalled = false
    /// 上次送到手錶的時間、大小（壓縮後的位元組）
    @Published private(set) var lastSentAt: Date?
    @Published private(set) var lastSentBytes: Int = 0

    /// activate() 叫過了（在這之前 refresh 什麼都不做）
    private var activationRequested = false

    /// [v2] 收手錶記的帳時撐的背景時間（照 WidgetSnapshotWriter 的 beginBackgroundTask 寫法）
    private var recordTask: UIBackgroundTaskIdentifier = .invalid
    /// [v2] 第幾次撐：連記好幾筆時，只有最後一筆的 3 秒到了才收掉
    private var recordHoldGeneration = 0
    /// [v2] 撐幾秒：要比收件匣晚 2 秒收尾（QuickRecordImporter.finishDelay）長
    private static let recordHoldSeconds: UInt64 = 3

    /// [v6] 系統換時區的監聽（activate() 裡掛一次；跟著 shared 活一輩子，不拿掉）
    private var timeZoneObserver: NSObjectProtocol?

    private override init() {
        super.init()
        let d = WidgetShared.defaults
        let sentAt = d?.double(forKey: WatchBridgeKeys.lastSentAt) ?? 0
        if sentAt > 0 {
            lastSentAt = Date(timeIntervalSince1970: sentAt)
        }
        lastSentBytes = d?.integer(forKey: WatchBridgeKeys.lastSentBytes) ?? 0
    }

    /// AppDelegate.didFinishLaunching 叫（先問 WCSession.isSupported()；iPad、Mac 什麼都不做）
    func activate() {
        guard WCSession.isSupported(), !activationRequested else { return }
        activationRequested = true
        let session = WCSession.default
        session.delegate = self
        session.activate()
        // [v6] 出國落地換時區（App 活著才收得到）：快照、手錶快取的 timeZoneId 用新時區重寫、重送。
        // 閉包不抓 self（主執行緒佇列；Swift 5 模式不會有 Sendable 警告）
        if timeZoneObserver == nil {
            timeZoneObserver = NotificationCenter.default.addObserver(forName: .NSSystemTimeZoneDidChange,
                                                                      object: nil, queue: .main) { _ in
                Task { @MainActor in
                    WatchBridge.shared.timeZoneChanged()
                }
            }
        }
    }

    /// [v6] 系統換時區了：清掉系統時區的快取（Calendar.current 才是新的）→ 全部重寫。
    /// writeNow 最後自己會叫 snapshotsDidChange() 送包；冷啟動時寫手還沒 start，只會用現成的檔重組
    func timeZoneChanged() {
        NSTimeZone.resetSystemTimeZone()
        WidgetSnapshotWriter.shared.writeNow()
    }

    /// WidgetSnapshotWriter.writeNow 寫完叫：組包（只讀檔）、內容變了才送
    func snapshotsDidChange() {
        refresh()
    }

    /// 設定頁改了「送到手錶」的開關、「隱藏金額」：重組重送。
    /// [v2] 設定頁「手機條碼」開關、電子發票連結或拿掉手機條碼（EInvoiceSyncManager）也叫
    func settingsChanged() {
        refresh()
    }

    // MARK: - 送不送

    /// 上次沒送成（App Group；冷啟動、下次打開都看得到）
    private var pending: Bool {
        get { WidgetShared.defaults?.bool(forKey: WatchBridgeKeys.pending) ?? false }
        set { WidgetShared.defaults?.set(newValue, forKey: WatchBridgeKeys.pending) }
    }

    /// 現在能送：啟動好了、有配對、手錶上裝了 LifeGood
    private static func canSend(_ session: WCSession) -> Bool {
        session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
    }

    /// 組包、跟 iPhone 上存的那一包比，該送才送（sim_v1.py bridge_decide）
    private func refresh() {
        guard WCSession.isSupported(), activationRequested else { return }
        let old = WidgetSnapshotStore.read(WatchPackage.self)
        guard let pkg = WatchPackageBuilder.build(now: Date()) else { return }
        let changed = WidgetSnapshotStore.write(pkg)
        let session = WCSession.default
        guard Self.canSend(session) else {
            // 還沒啟動好、沒配對、沒裝：記著，啟動好、裝好（watchStateChanged）再送
            if changed { pending = true }
            return
        }
        guard changed || pending || isNewWatch(session) else { return }
        let faceKinds: [String] = changed ? WatchPackageDiff.widgetKinds(old: old, new: pkg) : []
        send(pkg, faceKinds: faceKinds, session: session)
    }

    /// 送一包：≤ 48 KB 走 application context（＋錶面的字變了再走錶面那條）；> 48 KB 走 transferFile
    private func send(_ pkg: WatchPackage, faceKinds: [String], session: WCSession) {
        guard let data = WatchPackageCodec.encode(pkg) else { return }
        let now = Date()
        if data.count > WatchLink.maxContextBytes {
            guard sendFile(data, at: now, session: session) else {
                pending = true
                return
            }
        } else {
            let payload = Self.payload(data, at: now)
            do {
                try session.updateApplicationContext(payload)
            } catch {
                pending = true
                return
            }
            if !faceKinds.isEmpty {
                pushFace(payload, session: session, now: now)
            }
        }
        didSend(bytes: data.count, at: now, session: session)
    }

    /// ["pkg": LZFSE, "v": 1, "t": 秒]（t 讓每一次的內容都不一樣：強制重送也送得出去）
    private static func payload(_ data: Data, at now: Date) -> [String: Any] {
        [WatchLink.packageKey: data,
         WatchLink.versionKey: WatchPackage.schemaVersion,
         WatchLink.sentAtKey: now.timeIntervalSince1970]
    }

    /// 壓完 > 48 KB：寫成暫存檔、取消還沒送完的舊檔、transferFile。寫不出檔回 false
    private func sendFile(_ data: Data, at now: Date, session: WCSession) -> Bool {
        let stamp: String = String(Int(now.timeIntervalSince1970))
        let unique: String = String(UUID().uuidString.prefix(8))
        let name: String = WatchBridgeKeys.tempFilePrefix + stamp + "_" + unique + ".lzfse"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: false)
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            return false
        }
        for transfer in session.outstandingFileTransfers {
            transfer.cancel()
        }
        let metadata: [String: Any] = [WatchLink.versionKey: WatchPackage.schemaVersion,
                                       WatchLink.sentAtKey: now.timeIntervalSince1970]
        _ = session.transferFile(url, metadata: metadata)
        return true
    }

    /// 錶面快速推送：錶面真的放了 LifeGood、系統還有額度、今天用不到 30 次（換日歸零）
    private func pushFace(_ payload: [String: Any], session: WCSession, now: Date) {
        guard session.isComplicationEnabled, session.remainingComplicationUserInfoTransfers > 0 else { return }
        let d = WidgetShared.defaults
        let day = WidgetDateText.dayKey(now)
        var used = d?.integer(forKey: WatchBridgeKeys.facePushCount) ?? 0
        if d?.string(forKey: WatchBridgeKeys.facePushDay) != day {
            used = 0
        }
        guard used < WatchBridgeKeys.facePushDailyCap else { return }
        _ = session.transferCurrentComplicationUserInfo(payload)
        d?.set(day, forKey: WatchBridgeKeys.facePushDay)
        d?.set(used + 1, forKey: WatchBridgeKeys.facePushCount)
    }

    /// 送成了：清 pending、這支錶寫記號、記上次送的時間與大小（設定頁「上次送到手錶 09:24・6 KB」）
    private func didSend(bytes: Int, at now: Date, session: WCSession) {
        pending = false
        markWatch(session)
        lastSentAt = now
        lastSentBytes = bytes
        let d = WidgetShared.defaults
        d?.set(now.timeIntervalSince1970, forKey: WatchBridgeKeys.lastSentAt)
        d?.set(bytes, forKey: WatchBridgeKeys.lastSentBytes)
    }

    // MARK: - 換錶、第一次裝好

    /// 這支錶的記號檔（沒配對、沒裝手錶版時 watchDirectoryURL 是 nil）
    private func markerURL(_ session: WCSession) -> URL? {
        session.watchDirectoryURL?.appendingPathComponent(WatchBridgeKeys.markerFile, isDirectory: false)
    }

    /// 換錶、重新配對、手錶版第一次裝好（含刪掉重裝、TestFlight 自動安裝）：記號檔不在
    private func isNewWatch(_ session: WCSession) -> Bool {
        guard let url = markerURL(session) else { return false }
        return !FileManager.default.fileExists(atPath: url.path)
    }

    private func markWatch(_ session: WCSession) {
        guard let url = markerURL(session) else { return }
        try? Data().write(to: url, options: [.atomic])
    }

    // MARK: - 狀態變了、手錶來要

    /// 啟動好了、配對或安裝狀態變了：更新設定頁那兩個；裝著就 refresh（新錶、pending 會在裡面送）
    private func watchStateChanged() {
        let session = WCSession.default
        let activated = session.activationState == .activated
        let paired = activated && session.isPaired
        let installed = paired && session.isWatchAppInstalled
        if isPaired != paired { isPaired = paired }
        if isWatchAppInstalled != installed { isWatchAppInstalled = installed }
        if installed {
            refresh()
        }
    }

    /// 手錶要「給我最新的」：活著先重寫快照（冷啟動什麼都不做）→ 只讀檔組包 → 回覆那一包。
    /// 沒有包回 ["none": 1]；壓完 > 48 KB 改走 transferFile、回 ["none": 1]
    private func replyPackage(_ wants: Bool) -> [String: Any] {
        guard wants else { return [:] }
        WidgetSnapshotWriter.shared.writeNow()
        let now = Date()
        guard let pkg = WatchPackageBuilder.build(now: now) else { return [WatchLink.noneKey: 1] }
        WidgetSnapshotStore.write(pkg)
        guard let data = WatchPackageCodec.encode(pkg) else { return [WatchLink.noneKey: 1] }
        let session = WCSession.default
        if data.count > WatchLink.maxContextBytes {
            if sendFile(data, at: now, session: session) {
                didSend(bytes: data.count, at: now, session: session)
            } else {
                pending = true
            }
            return [WatchLink.noneKey: 1]
        }
        didSend(bytes: data.count, at: now, session: session)
        return Self.payload(data, at: now)
    }

    /// transferFile 沒送成（不是被新的那一份取消）：下次一有機會就送
    private func fileTransferFailed() {
        if WCSession.default.outstandingFileTransfers.isEmpty {
            pending = true
        }
    }

    // MARK: - [v2] 收手錶記的帳

    /// 手錶記的一筆（sendMessage、transferUserInfo 兩條路都走這裡；主執行緒）。
    /// 回 ["ok": "imported", "today": 3]／["ok": "queued"]／["ok": "failed"]（transferUserInfo 那條沒有回話，丟掉）
    private func receiveRecord(_ data: Data) -> [String: Any] {
        let now = Date()
        guard let record = WatchRecordCodec.decode(data),
              let entry = WatchRecordInbox.entry(from: record, now: now) else {
            return [WatchLink.okKey: WatchLink.okFailed]
        }
        holdForRecord()
        // 另一條路早就入帳了：不再進收件匣
        if WatchImportedLog.contains(record.id) {
            return importedReply(now: now)
        }
        // .ignoredDoubleTap＝同一筆兩條路幾乎同時到、第一份還在收件匣：照樣往下走
        if QuickRecordInbox.add(entry) == .failed {
            return [WatchLink.okKey: WatchLink.okFailed]
        }
        let importer = QuickRecordImporter.shared
        // App 開著、或剛用過還活著：入帳 → writeNow([.money]) → 手錶快取、手錶包跟著重寫重送
        if importer.isReady {
            importer.importFromWatch()
            if WatchImportedLog.contains(record.id) {
                return importedReply(now: now)
            }
        }
        // 冷啟動：只讀檔重組包（queuedIds 變了就送）
        refresh()
        return [WatchLink.okKey: WatchLink.okQueued]
    }

    /// ["ok": "imported"]，money 快照讀得到今天幾筆就多帶 "today"
    private func importedReply(now: Date) -> [String: Any] {
        var reply: [String: Any] = [WatchLink.okKey: WatchLink.okImported]
        if let n = WidgetSnapshotStore.read(WidgetMoneySnapshot.self)?.day(at: now)?.todayCount {
            reply[WatchLink.todayCountKey] = n
        }
        return reply
    }

    /// 撐 3 秒背景時間（被手錶叫醒、或 App 剛進背景時，收件匣寫檔與入帳做得完）；再叫一次就從那時候重算 3 秒
    private func holdForRecord() {
        if recordTask == .invalid {
            recordTask = UIApplication.shared.beginBackgroundTask(withName: "watch.record") { [weak self] in
                self?.endRecordHold()
            }
        }
        recordHoldGeneration += 1
        let generation = recordHoldGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: WatchBridge.recordHoldSeconds * 1_000_000_000)
            guard let self, self.recordHoldGeneration == generation else { return }
            self.endRecordHold()
        }
    }

    private func endRecordHold() {
        guard recordTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(recordTask)
        recordTask = .invalid
    }

    // MARK: - [v6] 收手錶的打卡

    /// 手錶按〔到了〕〔離開〕送來的一筆（sendMessage、transferUserInfo 兩條路都走這裡；主執行緒）。
    /// 回 ["ok": "done"]／["ok": "already", "at": 秒]／["ok": "gone"]／["ok": "queued"]／["ok": "failed"]
    /// （transferUserInfo 那條沒有回話，丟掉）。時間一律是手錶按下去那一刻（WatchCheckIn 裡帶的），不是送到的時間
    private func receiveCheckIn(_ data: Data) -> [String: Any] {
        guard let checkIn = WatchCheckInCodec.decode(data) else {
            return [WatchLink.okKey: WatchLink.okFailed]
        }
        // 同一個 3 秒背景時間（寫行程、重寫 life、組包、回話）
        holdForRecord()
        let applier = WatchActionApplier.shared
        // App 開著、或剛用過還活著：馬上寫（寫進去了它自己 writeNow([.life]) → 手錶快取、手錶包跟著重寫重送）
        if applier.isReady {
            switch applier.apply(checkIn) {
            case .applied:
                return [WatchLink.okKey: WatchLink.okDone]
            case .already(let at):
                return [WatchLink.okKey: WatchLink.okAlready, WatchLink.checkInAtKey: at.timeIntervalSince1970]
            case .gone:
                return [WatchLink.okKey: WatchLink.okGone]
            }
        }
        // 冷啟動：只寫一個小檔，打開 LifeGood 才寫進行程（兩條路都到＝同一個編號同一個檔，不會變兩筆）
        guard WatchActionInbox.add(checkIn) else {
            return [WatchLink.okKey: WatchLink.okFailed]
        }
        return [WatchLink.okKey: WatchLink.okQueued]
    }

    // MARK: - [v5] 收手錶的「我跑完了」「沒存成」

    /// 手錶跑完存好（或〔再存一次〕存好）送的編號、存不進 Apple 健康送的旗子（兩條路都走這裡；主執行緒）。
    /// 只寫 WatchRunFlags（App Group 的 UserDefaults；冷啟動也對），寫完它自己在主執行緒發 WatchRunFlags.changed
    private func receiveRun(ranId: String?, ranAt: Date?, unsaved: Int?) {
        if let ranId {
            WatchRunFlags.noteRan(workoutId: ranId, endedAt: ranAt, now: Date())
        } else if let unsaved {
            WatchRunFlags.noteUnsaved(unsaved == 1, now: Date())
        }
    }
}

// MARK: - WCSessionDelegate（背景執行緒；一律 nonisolated，要動狀態包 Task { @MainActor in … }）

extension WatchBridge: WCSessionDelegate {

    /// 啟動好了（iOS、watchOS 都必寫）：看到配對＋已安裝就 refresh（新錶、pending 不比內容也送）
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in
            self.watchStateChanged()
        }
    }

    /// 配對、安裝、錶面有沒有放 LifeGood 變了（同啟動好）
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.watchStateChanged()
        }
    }

    /// iOS 必寫（少寫編不過）：換錶中，舊的 session 還在送完手上的東西，這裡什麼都不做
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
    }

    /// iOS 必寫：換錶，舊的 session 關掉了 → 再 activate 一次接新錶（Apple 範例 SessionDelegator 同一句）
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// 手錶來要「給我最新的」、[v2] 手錶記的一筆、[v6] 手錶的打卡（要回覆的那種）、[v5] 我跑完了／沒存成（保險：手錶送這兩種不等回話）。
    /// 訊息在這裡先拆好，主執行緒只拿一個 Bool、兩份 Data、跑步那三樣
    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        let wants = (message[WatchLink.wantKey] as? String) == WatchLink.wantPackage
        let recordData = message[WatchLink.recordKey] as? Data
        let checkInData = message[WatchLink.checkInKey] as? Data
        // [v5] 有 "ranWorkout" 這個鍵就是「我跑完了」（空字串＝讀不到編號，也算）；"unsavedRun" 1／0
        let ranId = message[WatchLink.ranWorkoutKey] as? String
        let ranAt = (message[WatchLink.ranAtKey] as? Double).map { Date(timeIntervalSince1970: $0) }
        let unsaved = message[WatchLink.unsavedRunKey] as? Int
        let hasRun = ranId != nil || unsaved != nil
        Task { @MainActor in
            if hasRun {
                self.receiveRun(ranId: ranId, ranAt: ranAt, unsaved: unsaved)
            }
            if let recordData {
                replyHandler(self.receiveRecord(recordData))
            } else if let checkInData {
                replyHandler(self.receiveCheckIn(checkInData))
            } else if hasRun && !wants {
                replyHandler([WatchLink.okKey: WatchLink.okQueued])
            } else {
                replyHandler(self.replyPackage(wants))
            }
        }
    }

    /// 不用回覆的訊息：[v2] 萬一帶了一筆記帳、[v6] 一筆打卡，照樣收（沒有回話）；
    /// [v5] 手錶的「我跑完了」「沒存成」走這支（sendMessage 的 replyHandler 是 nil）
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let recordData = message[WatchLink.recordKey] as? Data
        let checkInData = message[WatchLink.checkInKey] as? Data
        let ranId = message[WatchLink.ranWorkoutKey] as? String
        let ranAt = (message[WatchLink.ranAtKey] as? Double).map { Date(timeIntervalSince1970: $0) }
        let unsaved = message[WatchLink.unsavedRunKey] as? Int
        let hasRun = ranId != nil || unsaved != nil
        guard recordData != nil || checkInData != nil || hasRun else { return }
        Task { @MainActor in
            if let recordData {
                _ = self.receiveRecord(recordData)
            }
            if let checkInData {
                _ = self.receiveCheckIn(checkInData)
            }
            if hasRun {
                self.receiveRun(ranId: ranId, ranAt: ranAt, unsaved: unsaved)
            }
        }
    }

    /// [v2] 手錶 transferUserInfo 來的一筆記帳、[v6] 一筆打卡、[v5] 我跑完了／沒存成（排隊、保證送到；沒有回話）。
    /// iOS 也有這個 delegate 方法
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let recordData = userInfo[WatchLink.recordKey] as? Data
        let checkInData = userInfo[WatchLink.checkInKey] as? Data
        let ranId = userInfo[WatchLink.ranWorkoutKey] as? String
        let ranAt = (userInfo[WatchLink.ranAtKey] as? Double).map { Date(timeIntervalSince1970: $0) }
        let unsaved = userInfo[WatchLink.unsavedRunKey] as? Int
        let hasRun = ranId != nil || unsaved != nil
        guard recordData != nil || checkInData != nil || hasRun else { return }
        Task { @MainActor in
            if let recordData {
                _ = self.receiveRecord(recordData)
            }
            if let checkInData {
                _ = self.receiveCheckIn(checkInData)
            }
            if hasRun {
                self.receiveRun(ranId: ranId, ranAt: ranAt, unsaved: unsaved)
            }
        }
    }

    /// transferFile 送完（或被取消、失敗）：刪暫存檔；失敗了記 pending
    nonisolated func session(_ session: WCSession,
                             didFinish fileTransfer: WCSessionFileTransfer,
                             error: Error?) {
        let url = fileTransfer.file.fileURL
        if url.lastPathComponent.hasPrefix(WatchBridgeKeys.tempFilePrefix) {
            try? FileManager.default.removeItem(at: url)
        }
        guard error != nil else { return }
        Task { @MainActor in
            self.fileTransferFailed()
        }
    }
}
