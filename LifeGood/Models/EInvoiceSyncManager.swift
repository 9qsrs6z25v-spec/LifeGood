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

    private static let autoSyncKey = "einvoice_auto_sync"
    private static let intervalKey = "einvoice_sync_interval_hours"
    private static let splitKey = "einvoice_split_items"
    private static let lastSyncDateKey = "einvoice_last_sync_date"
    private static let cardNoKey = "einvoice_card_no"
    private static let cardEncryptKeychainAccount = "einvoice_card_encrypt"

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first!
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

    /// 手動同步：從上次同步日（或預設 30 天前）到今天
    func syncNow(expenseStore: ExpenseStore) async {
        guard let carrier else { return }
        let end = Date()
        let start = lastSyncDate ?? Calendar.current.date(byAdding: .day, value: -30, to: end) ?? end
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
        var errors: [String] = []
        let alreadyImported = Set(importHistory.map { $0.invNum })

        do {
            let headers = try await client.fetchHeaders(carrier: carrier, from: start, to: end)
            for header in headers {
                if alreadyImported.contains(header.invNum) {
                    skipped += 1
                    continue
                }
                do {
                    let items = try await client.fetchDetail(carrier: carrier, header: header)
                    let category = InvoiceCategorizer.shared.categorize(seller: header.sellerName,
                                                                        items: items)
                    let expenseIds = writeExpenses(header: header, items: items,
                                                    category: category, store: expenseStore)
                    let record = EInvoiceImportRecord(
                        invNum: header.invNum, invDate: header.invDate,
                        sellerName: header.sellerName, amount: header.amount,
                        expenseIds: expenseIds, assignedCategory: category)
                    importHistory.insert(record, at: 0)
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

        // Trim history to most recent 500
        if importHistory.count > 500 {
            importHistory = Array(importHistory.prefix(500))
        }
        persistHistory()

        let result = EInvoiceSyncResult(importedCount: imported, skippedCount: skipped,
                                        failedCount: failed, errors: errors,
                                        timestamp: Date())
        self.lastSync = result
        self.lastSyncDate = result.timestamp
        UserDefaults.standard.set(result.timestamp, forKey: Self.lastSyncDateKey)
    }

    private func writeExpenses(header: EInvoiceHeader, items: [EInvoiceItem],
                                category: VariableCategory, store: ExpenseStore) -> [UUID] {
        let note = "電子發票 \(header.invNum)"

        if splitItems && !items.isEmpty {
            // 拆成多筆，每個品項一筆（一次性 append 避免每筆各觸發 didSet → save → CloudKit push）
            let newExpenses = items.map { item in
                Expense(
                    title: item.description.isEmpty ? header.sellerName : item.description,
                    amount: item.amount,
                    date: header.invDate,
                    expenseType: .variable,
                    variableCategory: category,
                    note: "\(note)（\(header.sellerName)）"
                )
            }
            store.expenses.append(contentsOf: newExpenses)
            return newExpenses.map(\.id)
        } else {
            // 整張一筆
            let exp = Expense(
                title: header.sellerName,
                amount: header.amount,
                date: header.invDate,
                expenseType: .variable,
                variableCategory: category,
                note: note
            )
            store.expenses.append(exp)
            return [exp.id]
        }
    }

    // MARK: - 歷史 / 取消匯入

    /// 撤銷已匯入的發票（連同對應的支出一起刪除）
    func revert(_ record: EInvoiceImportRecord, expenseStore: ExpenseStore) {
        expenseStore.expenses.removeAll { record.expenseIds.contains($0.id) }
        importHistory.removeAll { $0.id == record.id }
        persistHistory()
    }

    func clearHistory() {
        importHistory.removeAll()
        persistHistory()
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL),
              let decoded = try? JSONDecoder().decode([EInvoiceImportRecord].self, from: data) else { return }
        importHistory = decoded
    }

    private func persistHistory() {
        guard let data = try? JSONEncoder().encode(importHistory) else { return }
        try? data.write(to: historyURL, options: .atomic)
    }
}
