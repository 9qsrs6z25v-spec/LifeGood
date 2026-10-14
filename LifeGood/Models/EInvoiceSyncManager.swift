import Foundation
import Combine

@MainActor
final class EInvoiceSyncManager: ObservableObject {
    static let shared = EInvoiceSyncManager()

    // MARK: - 公開狀態

    @Published private(set) var carrier: EInvoiceCarrier?
    @Published var autoSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(autoSyncEnabled, forKey: Self.autoSyncKey) }
    }
    /// 自動同步間隔（小時）
    @Published var autoSyncIntervalHours: Int {
        didSet { UserDefaults.standard.set(autoSyncIntervalHours, forKey: Self.intervalKey) }
    }
    @Published var splitItems: Bool {
        didSet { UserDefaults.standard.set(splitItems, forKey: Self.splitKey) }
    }
    @Published private(set) var importHistory: [EInvoiceImportRecord] = []
    @Published private(set) var isSyncing: Bool = false
    @Published private(set) var lastSync: EInvoiceSyncResult?
    @Published private(set) var lastSyncDate: Date?

    // MARK: - 私有

    private let client = EInvoiceClient()
    private let historyURL: URL
    private let stateURL: URL
    private let persistQueue = DispatchQueue(label: "com.lifegood.einvoice.persist", qos: .utility)

    private static let autoSyncKey = "einvoice_auto_sync"
    private static let intervalKey = "einvoice_sync_interval_hours"
    private static let splitKey = "einvoice_split_items"
    private static let lastSyncDateKey = "einvoice_last_sync_date"
    private static let cardNoKey = "einvoice_card_no"
    private static let cardEncryptKeychainAccount = "einvoice_card_encrypt"

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        if !FileManager.default.fileExists(atPath: support.path) {
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        }
        self.historyURL = support.appendingPathComponent("einvoice_history.json")
        self.stateURL   = support.appendingPathComponent("einvoice_state.json")

        self.autoSyncEnabled = UserDefaults.standard.bool(forKey: Self.autoSyncKey)
        self.autoSyncIntervalHours = UserDefaults.standard.object(forKey: Self.intervalKey) as? Int ?? 24
        self.splitItems = UserDefaults.standard.object(forKey: Self.splitKey) as? Bool ?? false

        if let ts = UserDefaults.standard.object(forKey: Self.lastSyncDateKey) as? Date {
            self.lastSyncDate = ts
        }
        loadHistory()
        loadCarrier()
    }

    // MARK: - 載具

    var isLinked: Bool { carrier != nil }

    func linkCarrier(cardNo: String, cardEncrypt: String) {
        let trimmed = EInvoiceCarrier(cardNo: cardNo.trimmingCharacters(in: .whitespacesAndNewlines),
                                      cardEncrypt: cardEncrypt.trimmingCharacters(in: .whitespacesAndNewlines))
        UserDefaults.standard.set(trimmed.cardNo, forKey: Self.cardNoKey)
        KeychainHelper.save(trimmed.cardEncrypt, for: Self.cardEncryptKeychainAccount)
        self.carrier = trimmed
    }

    func unlinkCarrier() {
        UserDefaults.standard.removeObject(forKey: Self.cardNoKey)
        KeychainHelper.delete(for: Self.cardEncryptKeychainAccount)
        self.carrier = nil
    }

    private func loadCarrier() {
        guard let cardNo = UserDefaults.standard.string(forKey: Self.cardNoKey),
              !cardNo.isEmpty,
              let encrypt = KeychainHelper.read(for: Self.cardEncryptKeychainAccount),
              !encrypt.isEmpty else {
            self.carrier = nil
            return
        }
        self.carrier = EInvoiceCarrier(cardNo: cardNo, cardEncrypt: encrypt)
    }

    // MARK: - 同步入口

    /// 財政部載具查詢平台的發票入帳有已知延遲（部分商家/特店延後批次上傳，常見 1～3 天），
    /// 若每次都直接從「上次同步當下」當作查詢起點，lastSyncDate 逐次前進，
    /// 一旦某張發票在它自己的開立日當天查不到、要等 1～3 天後才會出現在平台上，
    /// 下一次同步的起點早已經過了它的開立日，之後永遠不會再查到那個區間 → 該筆消費永久漏匯入。
    /// 每次同步固定往回多查 3 天當緩衝；重疊區間已查過的發票靠 alreadyImported（invNum）去重，
    /// 不會造成重複匯入，只是多打幾天份的查詢。
    private static let syncLookbackBuffer: TimeInterval = 3 * 86400

    /// 手動同步：從上次同步日（或預設 30 天前）到今天
    func syncNow(expenseStore: ExpenseStore) async {
        guard let carrier else { return }
        let end = Date()
        let start = lastSyncDate.map { $0.addingTimeInterval(-Self.syncLookbackBuffer) }
            ?? Calendar.current.date(byAdding: .day, value: -30, to: end) ?? end
        await performSync(carrier: carrier, from: start, to: end, expenseStore: expenseStore)
    }

    /// 啟動時：若距上次同步已超過設定間隔，則自動同步
    func syncIfDue(expenseStore: ExpenseStore) async {
        guard autoSyncEnabled, let _ = carrier else { return }
        let interval = TimeInterval(autoSyncIntervalHours * 3600)
        if let last = lastSyncDate, Date().timeIntervalSince(last) < interval { return }
        await syncNow(expenseStore: expenseStore)
    }

    // MARK: - 核心流程

    private func performSync(carrier: EInvoiceCarrier, from start: Date, to end: Date,
                             expenseStore: ExpenseStore) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        var imported = 0
        var skipped = 0
        var failed = 0
        var merged = 0
        var errors: [String] = []
        let alreadyImported = Set(importHistory.map { $0.invNum })
        // 收集所有待寫入的支出，迴圈結束後一次 append，只觸發一次 save() → CloudKit push
        var pendingExpenses: [Expense] = []
        // 同樣收集新紀錄，避免在迴圈內每次 insert(at:0) 造成 O(n²) 移位與 N 次 @Published 通知
        var newHistoryRecords: [EInvoiceImportRecord] = []
        // [v2] 電子發票防重複：「一按就記」記的支出是候選；已經被別張發票認領過的不再認領
        //（歷史紀錄裡的 + 這一輪的，同一輪不會兩張發票併到同一筆）
        let calendar = Calendar.current
        var claimedIds = Set(importHistory.compactMap { $0.mergedExpenseId })
        // 使用者「拿掉發票」過的配對不再併（不然下一輪往回多查 3 天又會併回同一筆）
        let declinedPairs = Self.declinedMergePairs()
        // 併入的發票標頭（紀錄 id → 標頭）：迴圈後那筆支出不見了要改回一般匯入時用
        var mergedHeaders: [UUID: EInvoiceHeader] = [:]

        do {
            let headers = try await client.fetchHeaders(carrier: carrier, from: start, to: end)
            // [v2] App 在背景被叫起來時（QuickRecordImporter.start 不收）收件匣可能還留著早就按過的，
            // 先收進帳本，不然那杯咖啡的發票會另建一筆（剛按、還能復原的不會被提早收走，見 importOverdue）
            QuickRecordImporter.shared.importOverdue()
            // [v2] 候選在查完發票標頭之後才挑：查詢期間 App 回前景收進來的一按記也算得到
            let quickCandidates = Self.quickRecordCandidates(in: expenseStore.expenses,
                                                             from: start, calendar: calendar)
            // [v2 情境驗證補] 這一輪每張發票要併到哪一筆，先整批配好：同一天的先配、前後一天的後配。
            // 平台常晚 1～3 天才上傳（見 syncLookbackBuffer），前一天另一筆同金額的發票跟今天這杯咖啡的
            // 發票同一輪查到時，照順序一張一張配，前一天那張（日差 1）會先搶走今天那筆，
            // 今天這張反而另建一筆——帳上同一天多出一筆 65 元
            let quickAssignments = Self.quickRecordAssignments(for: headers, skipping: alreadyImported,
                                                               candidates: quickCandidates,
                                                               claimed: claimedIds, declined: declinedPairs,
                                                               calendar: calendar)
            for header in headers {
                if alreadyImported.contains(header.invNum) {
                    skipped += 1
                    continue
                }
                // 作廢發票不應計入支出：政府 API 的 invStatus 非「開立」（例如「作廢」）代表商家已作廢此發票
                if header.invStatus != "開立" {
                    skipped += 1
                    continue
                }
                // [v2] 先找「一按就記」記過的同一筆（在 fetchDetail 之前，省一次網路）：
                // 找到就不另建支出，記一筆「併入既有」，備註在迴圈後照當時的帳本補
                if let match = quickAssignments[header.invNum], !claimedIds.contains(match.id) {
                    claimedIds.insert(match.id)
                    let record = EInvoiceImportRecord(
                        invNum: header.invNum, invDate: header.invDate,
                        sellerName: header.sellerName, amount: header.amount,
                        expenseIds: [], assignedCategory: match.variableCategory ?? .other,
                        mergedExpenseId: match.id)
                    newHistoryRecords.append(record)
                    mergedHeaders[record.id] = header
                    merged += 1
                    continue
                }
                do {
                    let items = try await client.fetchDetail(carrier: carrier, header: header)
                    let category = InvoiceCategorizer.shared.categorize(seller: header.sellerName,
                                                                        items: items)
                    let newExpenses = buildExpenses(header: header, items: items, category: category)
                    let expenseIds = newExpenses.map(\.id)
                    pendingExpenses.append(contentsOf: newExpenses)
                    let record = EInvoiceImportRecord(
                        invNum: header.invNum, invDate: header.invDate,
                        sellerName: header.sellerName, amount: header.amount,
                        expenseIds: expenseIds, assignedCategory: category)
                    newHistoryRecords.append(record)
                    imported += 1
                } catch {
                    failed += 1
                    errors.append("\(header.invNum)：\(error.localizedDescription)")
                }
            }
        } catch {
            failed += 1
            errors.append(error.localizedDescription)
        }

        // [v2] 併入既有：迴圈裡有 await，這段時間那筆可能被改過——照「現在」的帳本補備註，
        // 不拿迴圈前的舊拷貝蓋回去。那筆已經被刪掉、或改到對不上了（金額、不是一按記的），
        // 這張發票改回一般匯入（不然這筆消費就不見了）
        var mergedUpdates: [Expense] = []
        for index in newHistoryRecords.indices {
            let record = newHistoryRecords[index]
            guard let expenseId = record.mergedExpenseId,
                  let header = mergedHeaders[record.id] else { continue }
            let current = expenseStore.expenses.first(where: { $0.id == expenseId })
            if var e = current, Self.isStillMergeable(e, header: header) {
                e.note = Self.noteAddingInvoice(e.note, invNum: header.invNum)
                mergedUpdates.append(e)
            } else {
                let category = InvoiceCategorizer.shared.categorize(seller: header.sellerName, items: [])
                let rebuilt = buildExpenses(header: header, items: [], category: category)
                pendingExpenses.append(contentsOf: rebuilt)
                newHistoryRecords[index] = EInvoiceImportRecord(
                    invNum: header.invNum, invDate: header.invDate,
                    sellerName: header.sellerName, amount: header.amount,
                    expenseIds: rebuilt.map(\.id), assignedCategory: category)
                merged -= 1
                imported += 1
            }
        }

        // 一次性 prepend，只觸發一次 @Published 通知
        if !newHistoryRecords.isEmpty {
            importHistory.insert(contentsOf: newHistoryRecords, at: 0)
        }

        // 一次性 append，只觸發一次 didSet → save() → CloudKit push
        //（[v2] 有併入既有的：補備註＋新增包在同一個 withBatch，一樣只存一次）
        if !mergedUpdates.isEmpty {
            expenseStore.withBatch {
                for e in mergedUpdates {
                    expenseStore.update(e)
                }
                expenseStore.addExpenses(pendingExpenses)
            }
        } else if !pendingExpenses.isEmpty {
            expenseStore.addExpenses(pendingExpenses)
        }

        // Trim history to most recent 500
        if importHistory.count > 500 {
            importHistory = Array(importHistory.prefix(500))
        }
        persistHistory()

        let result = EInvoiceSyncResult(importedCount: imported, skippedCount: skipped,
                                        failedCount: failed, errors: errors,
                                        timestamp: Date(), mergedCount: merged)
        self.lastSync = result
        self.lastSyncDate = result.timestamp
        UserDefaults.standard.set(result.timestamp, forKey: Self.lastSyncDateKey)
    }

    /// 將單張發票建成 Expense 物件列表，不直接寫入 store（由 performSync 統一批次寫入）
    private func buildExpenses(header: EInvoiceHeader, items: [EInvoiceItem],
                                category: VariableCategory) -> [Expense] {
        let note = "電子發票 \(header.invNum)"

        if splitItems && !items.isEmpty {
            return items.map { item in
                Expense(
                    title: item.description.isEmpty ? header.sellerName : item.description,
                    amount: item.amount,
                    date: header.invDate,
                    expenseType: .variable,
                    variableCategory: category,
                    note: "\(note)（\(header.sellerName)）"
                )
            }
        } else {
            return [Expense(
                title: header.sellerName,
                amount: header.amount,
                date: header.invDate,
                expenseType: .variable,
                variableCategory: category,
                note: note
            )]
        }
    }

    // MARK: - [v2] 電子發票防重複（只比對「一按就記」記的支出）

    /// 發票日期與支出日期最多差幾天還算同一筆（23:50 按、發票開隔天也要併得到）
    private static let quickRecordDayTolerance = 1
    /// 備註裡的發票資訊（跟 buildExpenses 同一個寫法）
    private static func invoiceNoteTag(_ invNum: String) -> String {
        "電子發票 " + invNum
    }

    /// 這一輪可以被認領的：一按就記、變動支出、備註裡還沒有任何發票號碼，
    /// 日期不早於查詢起點那天的前兩天（容許的日差 1 天再多留 1 天；更早的這一輪不可能對得上）。
    /// 手動記的帳一律不碰。
    private static func quickRecordCandidates(in expenses: [Expense], from start: Date,
                                              calendar: Calendar) -> [Expense] {
        let earliest = calendar.date(byAdding: .day, value: -(quickRecordDayTolerance + 1),
                                     to: calendar.startOfDay(for: start)) ?? start
        return expenses.filter { e in
            e.isQuickRecord
                && e.expenseType == .variable
                && e.date >= earliest
                && !e.note.contains("電子發票 ")
        }
    }

    /// [v2 情境驗證補] 這一輪每張發票要併到哪一筆（發票號碼 → 支出）。分兩趟配：第一趟只配同一天的，
    /// 第二趟才配前後一天的；一筆支出只給一張發票。已經匯過的、不是「開立」的不配（迴圈裡本來就略過）。
    /// 沒配到的發票照一般匯入。
    private static func quickRecordAssignments(for headers: [EInvoiceHeader],
                                               skipping alreadyImported: Set<String>,
                                               candidates: [Expense], claimed: Set<UUID>,
                                               declined: Set<String>, calendar: Calendar) -> [String: Expense] {
        guard !candidates.isEmpty else { return [:] }
        let eligible = headers.filter { !alreadyImported.contains($0.invNum) && $0.invStatus == "開立" }
        var taken = claimed
        var out: [String: Expense] = [:]
        for maxGap in 0...quickRecordDayTolerance {
            for header in eligible where out[header.invNum] == nil {
                guard let match = quickRecordMatch(for: header, in: candidates, excluding: taken,
                                                   declined: declined, maxGap: maxGap,
                                                   calendar: calendar) else { continue }
                taken.insert(match.id)
                out[header.invNum] = match
            }
        }
        return out
    }

    /// 一張發票要併到哪一筆：整張金額相同（差不到 0.5 元）、日曆天差 ≤ maxGap（最多 1）、還沒被認領、
    /// 使用者沒有對這一對「拿掉發票」過。
    /// 多筆符合：日差小的優先（同一天最優先），再來日期早的。都沒有回 nil（照一般匯入）。
    private static func quickRecordMatch(for header: EInvoiceHeader, in candidates: [Expense],
                                         excluding claimed: Set<UUID>, declined: Set<String>,
                                         maxGap: Int, calendar: Calendar) -> Expense? {
        let invoiceDay = calendar.startOfDay(for: header.invDate)
        var best: Expense?
        var bestGap = Int.max
        for e in candidates where !claimed.contains(e.id) {
            guard abs(e.amount - header.amount) < 0.5 else { continue }
            guard !declined.contains(mergePairKey(invNum: header.invNum, expenseId: e.id)) else { continue }
            let expenseDay = calendar.startOfDay(for: e.date)
            let gap = abs(calendar.dateComponents([.day], from: invoiceDay, to: expenseDay).day ?? 99)
            guard gap <= min(maxGap, quickRecordDayTolerance) else { continue }
            if let current = best {
                if gap < bestGap || (gap == bestGap && e.date < current.date) {
                    best = e
                    bestGap = gap
                }
            } else {
                best = e
                bestGap = gap
            }
        }
        return best
    }

    /// 迴圈後補備註前再看一次：那筆現在還是一按記的變動支出、金額還對得上
    private static func isStillMergeable(_ e: Expense, header: EInvoiceHeader) -> Bool {
        e.isQuickRecord && e.expenseType == .variable && abs(e.amount - header.amount) < 0.5
    }

    // 「拿掉發票」過的配對（發票號碼｜支出 id），存 UserDefaults，最多留 200 組
    private static let declinedMergeKey = "einvoice_declined_quick_merges"
    private static let declinedMergeLimit = 200

    private static func mergePairKey(invNum: String, expenseId: UUID) -> String {
        invNum + "|" + expenseId.uuidString
    }

    private static func declinedMergePairs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: declinedMergeKey) ?? [])
    }

    private static func rememberDeclinedMerge(invNum: String, expenseId: UUID) {
        var list = UserDefaults.standard.stringArray(forKey: declinedMergeKey) ?? []
        let key = mergePairKey(invNum: invNum, expenseId: expenseId)
        guard !list.contains(key) else { return }
        list.append(key)
        if list.count > declinedMergeLimit {
            list.removeFirst(list.count - declinedMergeLimit)
        }
        UserDefaults.standard.set(list, forKey: declinedMergeKey)
    }

    /// 備註補上「電子發票 AB12345678」：原本空的直接放，否則換行接在後面；已經有了就不重複加
    private static func noteAddingInvoice(_ note: String, invNum: String) -> String {
        let tag = invoiceNoteTag(invNum)
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return tag }
        if trimmed.contains(tag) { return note }
        return trimmed + "\n" + tag
    }

    /// 備註拿掉「電子發票 AB12345678」（連同前面的換行），去頭尾空白
    private static func noteRemovingInvoice(_ note: String, invNum: String) -> String {
        let tag = invoiceNoteTag(invNum)
        let withoutLine = note.replacingOccurrences(of: "\n" + tag, with: "")
        let withoutTag = withoutLine.replacingOccurrences(of: tag, with: "")
        return withoutTag.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 歷史 / 取消匯入

    /// 撤銷已匯入的發票（連同對應的支出一起刪除）。
    /// [v2] 「併入既有」的紀錄（record.isMerged）只拿掉那筆支出備註裡的發票資訊，不刪支出、不動車子鏡像；
    /// 並記住這一對，之後同步再查到這張發票就不再併到那筆（照一般發票匯入成另一筆）。
    @MainActor
    func revert(_ record: EInvoiceImportRecord, expenseStore: ExpenseStore) {
        if let mergedId = record.mergedExpenseId {
            Self.rememberDeclinedMerge(invNum: record.invNum, expenseId: mergedId)
            if var e = expenseStore.expenses.first(where: { $0.id == mergedId }) {
                let cleaned = Self.noteRemovingInvoice(e.note, invNum: record.invNum)
                if cleaned != e.note {
                    e.note = cleaned
                    expenseStore.update(e)
                }
            }
            importHistory.removeAll { $0.id == record.id }
            persistHistory()
            return
        }
        // 先轉成 Set，將每筆 expense 的查詢從 O(m) 降為 O(1)
        let idsToRemove = Set(record.expenseIds)
        for expense in expenseStore.expenses where idsToRemove.contains(expense.id) {
            for name in expense.photoFileNames { Expense.deletePhoto(name) }
        }
        expenseStore.expenses.removeAll { idsToRemove.contains($0.id) }
        // [v25.538] 匯入的支出後來改連到車子、再撤銷時，車子身上指到它的鏡像也要拿掉，
        // 不然留成孤兒，車子照樣把這筆算進花費（直接改 expenses 不會經過 ExpenseStore.delete）
        VehicleMirrors.removeMirrors(of: idsToRemove)
        importHistory.removeAll { $0.id == record.id }
        persistHistory()
    }

    func clearHistory() {
        importHistory.removeAll()
        persistHistory()
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL) else { return }
        // 逐筆容錯解碼：單一筆損壞的匯入紀錄不應讓整份發票匯入歷史消失
        // （對齊 LifeStore/ExpenseStore/FinanceStore 既有的逐筆容錯規格）。
        if let decoded = Self.lossyDecodeArray([EInvoiceImportRecord].self, from: data) {
            importHistory = decoded
        }
    }

    /// 逐筆容錯解碼：先試整批，失敗再逐筆解、跳過損壞的元素，保留其餘資料。
    private static func lossyDecodeArray<Element: Decodable>(_ type: [Element].Type, from data: Data) -> [Element]? {
        let decoder = JSONDecoder()
        if let items = try? decoder.decode([Element].self, from: data) { return items }
        if let raw = try? decoder.decode([FailableDecodable<Element>].self, from: data) {
            return raw.compactMap { $0.value }
        }
        return nil
    }

    /// 包裝單一元素，解碼失敗時不丟錯、回傳 nil
    private struct FailableDecodable<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws {
            value = try? T(from: decoder)
        }
    }

    private func persistHistory() {
        let snapshot = importHistory
        let url = historyURL
        persistQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
