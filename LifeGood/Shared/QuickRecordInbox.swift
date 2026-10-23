import Foundation

// MARK: - 一按就記的收件匣（v2）
//
// 這個檔案同時屬於「主 App」與「LifeGoodWidgets」兩個 target。
//
// 小工具「一按就記」的按鈕不開 App：QuickRecordIntent（小工具 target）在小工具的行程裡
// 把一筆「待入帳」寫進 App Group；App 在啟動、回前景（以及 App 正在前景時收到 Darwin 通知）
// 由 QuickRecordImporter（App target）把它們變成 Expense、一次 addExpenses。
//
// ── 檔案長相：一筆一個檔，不是一個大檔 ──────────────────────────────────────────
//   <App Group>/Widgets/quick_inbox_v1/<UUID>.json    待入帳（小工具寫、小工具「復原」時刪）
//   <App Group>/Widgets/quick_inbox_v1/<UUID>.taken   App 收走中（App 改名過來、存好帳之後刪）
//
// 為什麼不是一個 quick_inbox_v1.json 大檔＋讀改寫：兩個行程都要改同一個檔，就得用
// NSFileCoordinator 或檔案鎖。檔案鎖在 App Group 裡被系統暫停時還握著，App 會被系統直接殺掉
//（0xdead10cc）；檔案協調在 App 被暫停、還在協調中時，小工具那邊會卡住。
// 一筆一個檔就不用協調：每個檔同一時間只有一個主人，主人換手靠「改名」——同一個磁碟上的
// rename 是原子的，兩邊同時動手只會有一邊成功：
//   • 新增：小工具用原子寫入（先寫暫存檔再改名）寫一個全新的 <id>.json，不會跟誰撞。
//   • 復原：小工具刪 <id>.json。刪成功＝App 還沒收走；刪失敗＝App 已經改名成 .taken（來不及了）。
//   • 收走：App 把 <id>.json 改名成 <id>.taken。改名成功＝這筆歸 App；失敗＝剛好被復原了，跳過。
//   • App 存好帳之後才刪 .taken（finish）；中途被殺，下次 take() 會把留下的 .taken 再交出來，
//     App 用「收件匣 id＝Expense id」判斷已經存過就不再建一筆（防重收）。
//
// ⚠️ 只准用 Foundation 與同 target 的 WidgetSnapshotStore（WidgetSnapshot.swift）。
//
// [手錶 v2] v25.576（watch/judge.md §1.4-1、§1.4-2、§4.3；watch/build/v2/brief.md §2）：手錶記的帳也進這個收件匣——
//   • QuickRecordEntry.source：nil＝iPhone 小工具；"watch"＝手錶（iPhone 的 WatchBridge 收到 WatchRecord 轉的；舊檔沒有也解得開）
//   • pending(includeWatch:)：預設**不含**手錶來的——小工具「待入帳 N 筆」「✓ 已記…〔復原〕」只畫自己按的，
//     手錶那筆不會在 iPhone 上被〔復原〕刪掉（小工具的程式一行不用改）
//   • take(where:)：只收指定的（QuickRecordImporter.importFromWatch 只收手錶來的；小工具剛按、還在 10 分鐘
//     復原時間裡的那幾筆原封不動）。take() 照舊收全部（App 回前景）
//   • add 判斷「3 秒內同一顆」看全部（含手錶來的）；手錶自己打數字的那筆 templateId 是「watch.<編號>」，每筆都不一樣
//   • watchIds()：收件匣裡手錶來的編號（組手錶包的 queuedIds；純檔案，被手錶叫醒的冷啟動也能叫）

/// 收件匣裡的一筆（使用者按了一顆「7-11 咖啡 NT$65」）
struct QuickRecordEntry: Codable, Equatable, Identifiable {
    /// 收件匣 id；App 建 Expense 時**直接當 Expense 的 id**（防重收）
    var id: UUID
    /// 從哪個範本按的（WidgetQuickTemplate.id）；同一顆 3 秒內連按兩次只算一次
    var templateId: String
    /// 「7-11 咖啡」→ Expense.title
    var title: String
    /// 65（台幣）→ Expense.amount
    var amount: Double
    /// 「NT$65」（小工具畫「✓ 已記 7-11 咖啡 NT$65」用；隱藏金額時換成 mask）
    var amountText: String
    /// VariableCategory.rawValue → Expense.variableCategory（解不開退回「其他」）
    var categoryKey: String
    /// 連到哪台車（App 照 AddExpenseView 存檔的寫法連車、寫車子鏡像）
    var vehicleId: UUID? = nil
    /// VehicleVariableCategory.rawValue
    var vehicleCategoryKey: String? = nil
    /// 按下去的時間 → Expense.date
    var createdAt: Date
    /// [手錶 v2] 哪裡來的：nil＝iPhone 小工具；QuickRecordInbox.watchSource（"watch"）＝手錶。舊檔沒有這一欄＝nil
    var source: String? = nil

    /// [手錶 v2] 手錶記的
    var isFromWatch: Bool { source == QuickRecordInbox.watchSource }

    /// 從範本做一筆（小工具的 QuickRecordIntent 用；它手上是範本的各個欄位，見 init(templateId:…)）
    init(template t: WidgetQuickTemplate, now: Date = Date()) {
        self.init(templateId: t.id, title: t.title, amount: t.amount, amountText: t.amountText,
                  categoryKey: t.categoryKey, vehicleId: t.vehicleId,
                  vehicleCategoryKey: t.vehicleCategoryKey, now: now)
    }

    /// 欄位一個一個給（AppIntent 的參數只能是 String／Double 這類，沒辦法直接帶整個範本）
    init(templateId: String, title: String, amount: Double, amountText: String,
         categoryKey: String, vehicleId: UUID?, vehicleCategoryKey: String?, now: Date = Date()) {
        self.id = UUID()
        self.templateId = templateId
        self.title = title
        self.amount = amount
        self.amountText = amountText
        self.categoryKey = categoryKey
        self.vehicleId = vehicleId
        self.vehicleCategoryKey = vehicleCategoryKey
        self.createdAt = now
    }
}

enum QuickRecordInbox {
    /// <App Group>/Widgets/ 底下的資料夾
    static let folderName = "quick_inbox_v1"
    /// 同一個範本這麼多秒內再按一次當成手滑，不記第二筆
    static let doubleTapWindow: TimeInterval = 3
    /// 「✓ 已記 7-11 咖啡 NT$65・復原」在小工具上留多久（之後只剩「待入帳 N 筆」）
    static let bannerDuration: TimeInterval = 10 * 60
    /// 小工具記了一筆／復原了一筆時發的 Darwin 通知（App 在前景時收到就馬上收）
    static let darwinNotificationName = "com.lifegood.app.quickinbox.changed"
    /// [手錶 v2] QuickRecordEntry.source：手錶記的
    static let watchSource = "watch"

    private static let pendingExtension = "json"
    private static let takenExtension = "taken"

    // MARK: 位置

    /// <App Group>/Widgets/quick_inbox_v1/。create 為 true 時順手建（保護等級跟快照一樣）
    static func folderURL(create: Bool) -> URL? {
        guard let base = WidgetSnapshotStore.folderURL(create: create) else { return nil }
        let folder = base.appendingPathComponent(folderName, isDirectory: true)
        if create {
            let attributes: [FileAttributeKey: Any] = [
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ]
            do {
                try FileManager.default.createDirectory(at: folder,
                                                        withIntermediateDirectories: true,
                                                        attributes: attributes)
            } catch {
                return nil
            }
        }
        return folder
    }

    private static func fileURL(_ id: UUID, ext: String, in folder: URL) -> URL {
        folder.appendingPathComponent(id.uuidString + "." + ext, isDirectory: false)
    }

    /// 資料夾裡某個副檔名、檔名是 UUID 的檔（原子寫入時的暫存檔、其他雜檔一律不理）
    private static func files(withExtension ext: String, in folder: URL) -> [(id: UUID, url: URL)] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: folder,
                                                     includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles]) else { return [] }
        var out: [(id: UUID, url: URL)] = []
        for url in urls where url.pathExtension == ext {
            let name = url.deletingPathExtension().lastPathComponent
            if let id = UUID(uuidString: name) {
                out.append((id: id, url: url))
            }
        }
        return out
    }

    private static func decode(_ url: URL) -> QuickRecordEntry? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? WidgetSnapshotStore.makeDecoder().decode(QuickRecordEntry.self, from: data)
    }

    // MARK: 小工具用

    /// 還沒被 App 收走的，依按下的時間由舊到新（小工具畫「待入帳 N 筆」「✓ 已記…」用）。
    /// [手錶 v2] includeWatch 預設 false：手錶來的不算（小工具不畫、不能〔復原〕）；要全部的（add 判斷手滑、
    /// QuickRecordImporter.importOverdue）傳 true
    static func pending(includeWatch: Bool = false) -> [QuickRecordEntry] {
        guard let folder = folderURL(create: false) else { return [] }
        let entries = files(withExtension: pendingExtension, in: folder).compactMap { decode($0.url) }
        let kept = includeWatch ? entries : entries.filter { !$0.isFromWatch }
        return kept.sorted { $0.createdAt < $1.createdAt }
    }

    enum AddResult: Equatable {
        case added
        /// 同一個範本 doubleTapWindow 秒內已經有一筆，這次不記
        case ignoredDoubleTap
        /// App Group 打不開、寫檔失敗
        case failed
    }

    /// 記一筆（QuickRecordIntent 呼叫）。寫完記得 postChanged() 並重畫。
    @discardableResult
    static func add(_ entry: QuickRecordEntry) -> AddResult {
        // [手錶 v2] 看全部（含手錶來的）：同一筆從手錶的兩條路都到時，第二份在這裡就擋掉
        let isDoubleTap = pending(includeWatch: true).contains {
            $0.templateId == entry.templateId
                && abs(entry.createdAt.timeIntervalSince($0.createdAt)) < doubleTapWindow
        }
        if isDoubleTap { return .ignoredDoubleTap }
        guard let folder = folderURL(create: true),
              let data = try? WidgetSnapshotStore.makeEncoder().encode(entry) else { return .failed }
        let url = fileURL(entry.id, ext: pendingExtension, in: folder)
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return .added
        } catch {
            return .failed
        }
    }

    /// 復原（UndoQuickRecordIntent 呼叫）：App 還沒收走就刪掉、回 true；
    /// 已經被 App 收走（或根本沒有）回 false——這時要刪只能到 App 裡刪。
    @discardableResult
    static func undo(id: UUID) -> Bool {
        guard let folder = folderURL(create: false) else { return false }
        do {
            try FileManager.default.removeItem(at: fileURL(id, ext: pendingExtension, in: folder))
            return true
        } catch {
            return false
        }
    }

    // MARK: App 用（QuickRecordImporter）

    /// 把待入帳一筆一筆改名成 .taken（改名成功的才算 App 的），連同上次沒收完留下的 .taken 一起交出來，
    /// 依按下的時間由舊到新。解不開的 .taken 直接刪掉（不然每次都卡在那裡）。
    ///
    /// 交出來的每一筆，App 要嘛存進帳本、要嘛確認帳本裡已經有同 id 的支出，然後呼叫 finish。
    static func take() -> [QuickRecordEntry] {
        take(where: { _ in true })
    }

    /// [手錶 v2] 只收 include 回 true 的（QuickRecordImporter.importFromWatch：只收手錶來的）。
    /// 不收的 .json 原封不動（小工具剛按、還能〔復原〕的那筆）；不收的 .taken 也留著，等它自己那一支收。
    /// 解不開的 .json 不管 include 照樣改名、再當壞檔刪掉（跟 take() 原本一樣，不然每次都卡在那裡）。
    static func take(where include: (QuickRecordEntry) -> Bool) -> [QuickRecordEntry] {
        guard let folder = folderURL(create: false) else { return [] }
        let fm = FileManager.default
        for item in files(withExtension: pendingExtension, in: folder) {
            if let entry = decode(item.url), !include(entry) {
                continue
            }
            let dest = fileURL(item.id, ext: takenExtension, in: folder)
            if fm.fileExists(atPath: dest.path) {
                // 同一個 id 已經在收走中（不該發生）：留著的那份為準，這份丟掉
                try? fm.removeItem(at: item.url)
                continue
            }
            // 失敗＝剛好被小工具復原（檔案沒了），跳過
            try? fm.moveItem(at: item.url, to: dest)
        }
        var out: [QuickRecordEntry] = []
        for item in files(withExtension: takenExtension, in: folder) {
            if let entry = decode(item.url) {
                if include(entry) {
                    out.append(entry)
                }
            } else {
                try? fm.removeItem(at: item.url)
            }
        }
        return out.sorted { $0.createdAt < $1.createdAt }
    }

    /// [手錶 v2] 收件匣裡（待入帳＋收走中）手錶來的編號，依編號字串排好、不重複（組手錶包的 queuedIds）。
    /// 純檔案：被手錶叫醒的冷啟動也能叫
    static func watchIds() -> [UUID] {
        guard let folder = folderURL(create: false) else { return [] }
        var seen = Set<UUID>()
        for ext in [pendingExtension, takenExtension] {
            for item in files(withExtension: ext, in: folder) {
                if let entry = decode(item.url), entry.isFromWatch {
                    seen.insert(entry.id)
                }
            }
        }
        return seen.sorted { $0.uuidString < $1.uuidString }
    }

    /// 帳本確定有這幾筆之後呼叫：刪掉它們的 .taken。
    static func finish(_ ids: Set<UUID>) {
        guard !ids.isEmpty, let folder = folderURL(create: false) else { return }
        for id in ids {
            try? FileManager.default.removeItem(at: fileURL(id, ext: takenExtension, in: folder))
        }
    }

    // MARK: 通知

    /// 小工具記了／復原了一筆：叫一聲（App 在前景時 QuickRecordImporter 收到就馬上收）。
    /// Darwin 通知不帶資料、App 被暫停時收不到——那種情況靠 App 回前景時收，不靠它。
    static func postChanged() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let name = CFNotificationName(rawValue: darwinNotificationName as CFString)
        CFNotificationCenterPostNotification(center, name, nil, nil, true)
    }
}
