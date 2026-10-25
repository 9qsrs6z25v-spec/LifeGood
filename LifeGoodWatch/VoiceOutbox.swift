import Foundation

// MARK: - 說一句的待送盒（手錶 v7a，v25.585；watch/judge.md §4.1「說一句」、§4.3、§5.5、§6.1、附錄 B；watch/build/v7a/brief.md §2）
//
// 只屬於 LifeGoodWatch。跟記一筆（RecordOutbox，v2）同一套送法，一句一個檔：
//   手錶 App Group 的 Widgets/watch_voice_outbox_v1/<編號>.json（只有手錶 App 這個行程碰，手錶小格不讀）。
//   講完（TextFieldLink 送出）＝馬上送（系統聽寫的畫面上你已經看過字、按了完成，不再多 10 秒〔復原〕）：
//   transferUserInfo（排隊、保證送到、iPhone 不在旁邊也排著、回到身邊系統自己補送）＋ iPhone 在旁邊再 sendMessage（有回話）——
//   WatchSync.sendVoice（G2）。兩條都到、手錶重送，iPhone 只記一次（編號＝支出編號＋iPhone 的 WatchVoiceLog）。
//   時間一律是講完那一刻（WatchVoice.saidAt）。
//
// 狀態（WatchVoiceItem.State，只往前走、不往回）：
//   pending 還沒交給系統（WCSession 還沒啟動好）→ sent 交給系統了（transferUserInfo 排隊中）
//   → delivered iPhone 收到了（transferUserInfo 送完，還沒回話）／working iPhone 的 LifeGood 開著正在記／queued LifeGood 沒開
//   → done 有結果了（WatchVoiceSaid：記好了，或為什麼沒記成）
// ⚠️ 你講的原文（voice.text）只在送到 iPhone 之前留在這裡（judge §4.1、§6.1）：一變成 delivered／working／queued／done
//    就清成 ""（VoiceOutboxRule.advanced）。iPhone 回話確定收到了，系統排隊裡那一份也取消（WatchSync.cancelVoiceTransfer）。
//    畫面上的原文只在「說一句」那一頁打開時留在記憶體（RecordSheet 的 @State），手腕放下不畫。
// 留多久（VoiceOutboxRule.shouldRemove）：結果看過了（seenAt）就刪；記好了、沒看到的 24 小時後刪；
//   沒記成、沒看到的留到看到為止（最多 7 天；記帳台最下面那一行一直寫，不准默默丟掉）；
//   在 iPhone 等著記（delivered／working／queued）超過 7 天的刪（iPhone 那邊的檔還在，打開 iPhone 就會記）；
//   還沒送到的（pending／sent）不自己刪（設定〔現在送〕）。
// 規則跟 scratchpad/watch/build/v7a/sim_v7a.py 的 outbox_* 一模一樣（改了兩邊一起改、重跑 sim）。
//
// ⚠️ VoiceOutboxStore（檔案）在 WatchSync 的背景執行緒也會被叫（收到結果就寫進檔）：一律過 lock。
//    VoiceOutbox（畫面用的那一份）在主執行緒；WatchSync 要叫它一律 Task { @MainActor in … }。

/// 手錶設定「記帳台第 4 格：🎤 說一句」（手錶 App Group；沒設定過＝開）。關掉＝第 4 格照 v2 放常記的第 4 筆
enum WatchVoiceSettings {
    static let tileKey = "watch_voice_tile"

    static var tileOn: Bool {
        guard let d = WidgetShared.defaults, d.object(forKey: tileKey) != nil else { return true }
        return d.bool(forKey: tileKey)
    }

    static func setTileOn(_ on: Bool) {
        WidgetShared.defaults?.set(on, forKey: tileKey)
    }
}

/// 待送盒的一句
struct WatchVoiceItem: Codable, Equatable, Identifiable {
    enum State: String, Codable {
        /// 還沒交給系統（WCSession 還沒啟動好）
        case pending
        /// 交給系統了（transferUserInfo 排隊中；iPhone 在旁邊也 sendMessage 了）
        case sent
        /// iPhone 收到了（transferUserInfo 送完、沒有錯），還沒回話
        case delivered
        /// iPhone 回「正在記」（上面的 LifeGood 開著）
        case working
        /// iPhone 回「先排著」（上面的 LifeGood 沒開，打開才記）
        case queued
        /// 有結果了（said）
        case done
    }

    /// 送 iPhone 的那一句（text 送到就清成 ""）
    var voice: WatchVoice
    var state: State
    /// 第一次交給系統的時間
    var sentAt: Date? = nil
    /// iPhone 回的結果（done 才有）
    var said: WatchVoiceSaid? = nil
    /// 收到結果的時間
    var doneAt: Date? = nil
    /// 結果在手錶上被看過（「說一句」那一頁顯示了、記帳台最下面那一行點了）
    var seenAt: Date? = nil

    var id: UUID { voice.id }
    /// 還沒送到 iPhone（設定「說一句還沒送到 iPhone：N 句」）
    var isUnsent: Bool { state == .pending || state == .sent }
    /// 在 iPhone 等著記（已經送到，還沒有結果）
    var isWaitingPhone: Bool { state == .delivered || state == .working || state == .queued }
}

/// 記帳台最下面那一行（點了：結果那種＝看過了）
struct VoiceDeskLine: Equatable {
    /// 結果那一種才有（點了 markSeen）；在等的、還沒送到的是 nil
    var id: UUID?
    var text: String
    /// 琥珀（沒記成、還沒送到）
    var isWarning: Bool
}

// MARK: - 規則（純函式；sim_v7a.py outbox_*）

enum VoiceOutboxRule {
    /// 記好了、沒看到：留 24 小時
    static let recordedKeep: TimeInterval = 24 * 3600
    /// 沒記成沒看到、在 iPhone 等著記：最多留 7 天
    static let staleKeep: TimeInterval = 7 * 24 * 3600

    /// 狀態的先後（只往前走）
    static func rank(_ s: WatchVoiceItem.State) -> Int {
        switch s {
        case .pending: return 0
        case .sent: return 1
        case .delivered: return 2
        case .working, .queued: return 3
        case .done: return 4
        }
    }

    /// 往前走到 state（比現在的後面才換；working／queued 同一級，後到的蓋前面的）。送到 iPhone 了（delivered 以後）原文清掉
    static func advanced(_ item: WatchVoiceItem, to state: WatchVoiceItem.State) -> WatchVoiceItem {
        var out = item
        let now = rank(item.state)
        let next = rank(state)
        if next > now || (next == now && next == 3) {
            out.state = state
        }
        if rank(out.state) >= 2 {
            out.voice.text = ""
        }
        return out
    }

    /// 收到結果：done、記結果與時間、原文清掉（同一句的結果到第二次不改）
    static func withSaid(_ item: WatchVoiceItem, said: WatchVoiceSaid, now: Date) -> WatchVoiceItem {
        guard item.state != .done else { return item }
        var out = advanced(item, to: .done)
        out.said = said
        out.doneAt = now
        return out
    }

    /// 這一句可以從手錶刪了嗎（見檔頭「留多久」）
    static func shouldRemove(_ item: WatchVoiceItem, now: Date) -> Bool {
        switch item.state {
        case .pending, .sent:
            return false
        case .delivered, .working, .queued:
            guard let at = item.sentAt else { return false }
            return now.timeIntervalSince(at) >= staleKeep
        case .done:
            if item.seenAt != nil { return true }
            guard let at = item.doneAt else { return true }
            let keep: TimeInterval = (item.said?.isRecorded ?? false) ? recordedKeep : staleKeep
            return now.timeIntervalSince(at) >= keep
        }
    }

    /// 還沒送到 iPhone 的句數
    static func unsentCount(_ items: [WatchVoiceItem]) -> Int {
        items.filter { $0.isUnsent }.count
    }

    /// 這一句送到哪了（waiting＝這次送出去還在等回話、5 秒還沒到）
    static func status(of item: WatchVoiceItem, waiting: Bool, unsent: Int) -> WatchVoiceStatus {
        switch item.state {
        case .done:
            if let said = item.said { return .done(said) }
            return .done(WatchVoiceSaid(id: item.id, kind: WatchVoiceOutcome.notUnderstood.rawValue))
        case .working: return .working
        case .queued: return .queued
        case .delivered: return .delivered
        case .sent: return waiting ? .sending : .offline(count: max(unsent, 1))
        case .pending: return .offline(count: max(unsent, 1))
        }
    }

    /// 設定第一段「說一句還沒送到 iPhone：N 句」；0 句 nil
    static func unsentLine(_ items: [WatchVoiceItem]) -> String? {
        let n = unsentCount(items)
        guard n > 0 else { return nil }
        return "說一句還沒送到 iPhone：\(n) 句"
    }

    /// 記帳台最下面那一行：① 最新一句還沒看過的結果「上一句・已記一筆：…」（沒記成琥珀）；
    /// ② 不然在 iPhone 等著記的「1 句在 iPhone 等著記」；③ 不然還沒送到的「1 句還沒送到 iPhone」（琥珀）；都沒有 nil
    static func deskLine(_ items: [WatchVoiceItem], masked: Bool) -> VoiceDeskLine? {
        let unseen = items.filter { $0.state == .done && $0.seenAt == nil && $0.said != nil }
        if let latest = unseen.max(by: { a, b in (a.doneAt ?? .distantPast) < (b.doneAt ?? .distantPast) }),
           let said = latest.said {
            return VoiceDeskLine(id: latest.id, text: "上一句・" + WatchVoiceText.saidLine(said, masked: masked),
                                 isWarning: !said.isRecorded)
        }
        let waiting = items.filter { $0.isWaitingPhone }.count
        if waiting > 0 {
            return VoiceDeskLine(id: nil, text: "\(waiting) 句在 iPhone 等著記", isWarning: false)
        }
        let unsent = unsentCount(items)
        if unsent > 0 {
            return VoiceDeskLine(id: nil, text: "\(unsent) 句還沒送到 iPhone", isWarning: true)
        }
        return nil
    }
}

// MARK: - 檔案（任何執行緒都可以叫；一律過 lock）

enum VoiceOutboxStore {
    /// <手錶 App Group>/Widgets/ 底下的資料夾
    static let folderName = "watch_voice_outbox_v1"

    private static let lock = NSLock()

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

    /// 全部，依講完的時間由舊到新（同一刻編號字串小的先）；順手刪掉該刪的（shouldRemove）
    static func loadAll(now: Date = Date()) -> [WatchVoiceItem] {
        lock.lock()
        defer { lock.unlock() }
        var out: [WatchVoiceItem] = []
        for item in unlockedLoadAll() {
            if VoiceOutboxRule.shouldRemove(item, now: now) {
                unlockedRemove(item.id)
            } else {
                out.append(item)
            }
        }
        return out
    }

    /// 寫一筆（原子寫入、跟 iPhone 收件匣同一個保護等級）。寫不進去回 false
    @discardableResult
    static func save(_ item: WatchVoiceItem) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return unlockedSave(item)
    }

    /// 讀出那一筆、改、寫回；沒有那一筆回 false
    @discardableResult
    static func update(_ id: UUID, _ change: (inout WatchVoiceItem) -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard var item = unlockedLoadAll().first(where: { $0.id == id }) else { return false }
        let before = item
        change(&item)
        guard item != before else { return true }
        return unlockedSave(item)
    }

    /// 收到 iPhone 的結果（WatchSync 的背景執行緒、或回話）：那一句換成 done。手錶上沒有這一句（早就刪了）回 false
    @discardableResult
    static func applySaid(_ said: WatchVoiceSaid, now: Date) -> Bool {
        update(said.id) { item in
            item = VoiceOutboxRule.withSaid(item, said: said, now: now)
        }
    }

    // MARK: 沒拿 lock 的版本

    private static func unlockedLoadAll() -> [WatchVoiceItem] {
        guard let folder = folderURL(create: false) else { return [] }
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                      options: [.skipsHiddenFiles]) else { return [] }
        var out: [WatchVoiceItem] = []
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let item = try? WidgetSnapshotStore.makeDecoder().decode(WatchVoiceItem.self, from: data) {
                out.append(item)
            } else {
                // 解不開的壞檔刪掉（不然每次都卡在這裡）
                try? FileManager.default.removeItem(at: url)
            }
        }
        return out.sorted { a, b in
            if a.voice.saidAt != b.voice.saidAt { return a.voice.saidAt < b.voice.saidAt }
            return a.id.uuidString < b.id.uuidString
        }
    }

    @discardableResult
    private static func unlockedSave(_ item: WatchVoiceItem) -> Bool {
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
final class VoiceOutbox: ObservableObject {
    static let shared = VoiceOutbox()

    /// sendMessage 送出後等 iPhone 回話多久，沒回就寫「還沒送到 iPhone，先存在手錶上」
    static let replyTimeout: TimeInterval = 5

    /// 待送盒裡全部（含有結果、還沒看過的）
    @Published private(set) var items: [WatchVoiceItem]
    /// 這次送出去、還在等回話的（5 秒內寫「送到 iPhone…」）
    @Published private(set) var waiting: Set<UUID> = []

    private init() {
        items = VoiceOutboxStore.loadAll()
    }

    // MARK: 讀

    func reload() {
        items = VoiceOutboxStore.loadAll()
    }

    var unsentCount: Int {
        VoiceOutboxRule.unsentCount(items)
    }

    /// 這一句送到哪了；手錶上沒有這一句 nil
    func status(of id: UUID) -> WatchVoiceStatus? {
        guard let item = items.first(where: { $0.id == id }) else { return nil }
        return VoiceOutboxRule.status(of: item, waiting: waiting.contains(id), unsent: unsentCount)
    }

    // MARK: 講完

    /// 講完（TextFieldLink 送出）：去頭尾空白、沒字回 nil；寫進待送盒、馬上送。回這一句的編號（「說一句」那一頁看它）。
    /// target、currency：旅途中記到哪一站、外幣（照 v6 記一筆的預設那一站；不在旅途中都是 nil）
    func add(text: String, now: Date = Date(), target: WatchTripRecordTarget?, currency: WatchCurrency?) -> UUID? {
        let cleaned = WatchVoiceRule.cleanText(text)
        guard !cleaned.isEmpty else { return nil }
        var voice = WatchVoice(id: UUID(), text: cleaned, saidAt: now)
        if let target {
            voice.tripPlanId = target.planId
            voice.tripStopId = target.stopId
            voice.currency = currency
        }
        let item = WatchVoiceItem(voice: voice, state: .pending)
        guard VoiceOutboxStore.save(item) else { return nil }
        reload()
        send(item, now: now)
        return voice.id
    }

    // MARK: 送

    /// 還沒交給系統的（pending）現在送：WCSession 啟動好、iPhone 回到身邊、回前景（WatchSync、WatchModel 叫）
    func sendDue(now: Date = Date()) {
        for item in items where item.state == .pending {
            send(item, now: now)
        }
    }

    /// 設定〔現在送〕：還沒交給系統的＋交給系統了但系統排隊裡已經沒有、iPhone 也還沒確認收到的，再送一次（iPhone 用編號擋重複）
    func resendUnconfirmed(now: Date = Date()) {
        let outstanding = WatchSync.shared.outstandingVoiceIds()
        for item in items where item.state == .pending || (item.state == .sent && !outstanding.contains(item.id)) {
            send(item, now: now)
        }
    }

    private func send(_ item: WatchVoiceItem, now: Date) {
        // 還沒啟動好、手錶上沒有 WatchConnectivity：留著 pending，下次再送
        guard WatchSync.shared.sendVoice(item.voice) else { return }
        VoiceOutboxStore.update(item.id) { stored in
            stored = VoiceOutboxRule.advanced(stored, to: .sent)
            if stored.sentAt == nil {
                stored.sentAt = now
            }
        }
        reload()
        if WatchSync.shared.isPhoneReachable {
            waiting.insert(item.id)
            scheduleTimeout(item.id)
        }
    }

    // MARK: WatchSync 回來（主執行緒）

    /// sendMessage 的回話：["ok": "working"|"queued"|"done"|"failed", "said": Data（done 才有）]
    func phoneReplied(_ id: UUID, ok: String?, said: WatchVoiceSaid?) {
        waiting.remove(id)
        if let said, said.id == id {
            saidArrived(said)
            return
        }
        var next: WatchVoiceItem.State? = nil
        if ok == WatchLink.okWorking {
            next = .working
        } else if ok == WatchLink.okQueued {
            next = .queued
        }
        if let next {
            VoiceOutboxStore.update(id) { stored in
                stored = VoiceOutboxRule.advanced(stored, to: next)
            }
            // iPhone 確定收到了（已經寫進它的 watch_voice_v1）：系統排隊裡那一份（裡面有原文）不用再送
            WatchSync.shared.cancelVoiceTransfer(id)
        }
        // failed／解不開：transferUserInfo 那一份照樣排著（「還沒送到 iPhone，先存在手錶上」）
        reload()
    }

    /// sendMessage 失敗（iPhone 不在旁邊了、LifeGood 被滑掉…）：transferUserInfo 那一份照樣排著
    func phoneUnreachable(_ id: UUID) {
        waiting.remove(id)
        reload()
    }

    /// transferUserInfo 送完、沒有錯：iPhone 收到了（原文清掉）
    func markDelivered(_ id: UUID) {
        VoiceOutboxStore.update(id) { stored in
            stored = VoiceOutboxRule.advanced(stored, to: .delivered)
        }
        reload()
    }

    /// 結果來了（WatchSync 已經在背景寫進檔、或回話帶來的）：寫進檔（已經寫過不改）、重讀
    func saidArrived(_ said: WatchVoiceSaid) {
        VoiceOutboxStore.applySaid(said, now: Date())
        waiting.remove(said.id)
        reload()
    }

    /// 結果看過了（「說一句」那一頁顯示了結果、記帳台最下面那一行點了）：下次重讀就刪
    func markSeen(_ id: UUID) {
        VoiceOutboxStore.update(id) { stored in
            if stored.state == .done && stored.seenAt == nil {
                stored.seenAt = Date()
            }
        }
        reload()
    }

    // MARK: 計時

    private func scheduleTimeout(_ id: UUID) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(VoiceOutbox.replyTimeout * 1_000_000_000))
            VoiceOutbox.shared.replyTimedOut(id)
        }
    }

    private func replyTimedOut(_ id: UUID) {
        guard waiting.contains(id) else { return }
        waiting.remove(id)
        reload()
    }
}
