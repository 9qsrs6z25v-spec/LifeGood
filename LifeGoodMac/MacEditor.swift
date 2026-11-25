// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.640 mac1] 電腦上記、改、刪、復原（judge_mac §O5、§O6）。
// MacEditCenter：開表單前重抓、所有寫入都走 MacCloudWriter（復原、補回、從備份加回也一樣）、看門狗、狀態列、復原堆疊。
// 畫面規則：sheet 一律 sheet(item:)＋.macStores(app)；dismiss 之後才寫 store（DispatchQueue.main.async）；不在 body 寫 store。
// 字一律不用第三人稱代名詞，用「這筆」「另一台」「iPhone」。
// [v25.641 mac2 G1] 存的時候 gate（S1，gateReason）、加回擋連著的（S2）、欄位對不到一律擋（S4）、選取三個洞（S3）、
// 收入表單接週期／固定薪水／結束日（MacIncomeFormFields.swift）、刪週期收入多一句、詳情鎖頭清單用 MacEditField.fields(for:income:)。
// [v25.642 mac3 G1] judge_mac §Q4、§Q6（sim_mac3.py policy_block3／gate3／post_check；sim3 編號 block3#、gate3#、post3#）：
// 判斷一律帶 MacLinkIDs（畫面用快取 cachedLinks()、存的那一刻用剛抓到的 links(_:)）；gate 看剛抓到的分帳細項、換分類看新值；
// postCheck（postReason）看合併後那筆；從備份加回支出也擋；⌘D 複製成新的一筆（確認框、復原、選取）；詳情欄〔複製成新的一筆〕＋一行提示。
import Combine
import Foundation
import SwiftUI

// MARK: - 寫入工作

/// 這次寫入是從哪裡來的（決定成功之後狀態列寫什麼、要不要登記復原）
enum MacWritePurpose {
    case form(isNew: Bool)
    case delete
    case undo
    case redo
    /// 看門狗〔補回〕（日誌 id）
    case restore(String)
    /// 「最近在電腦改的」〔改回〕（日誌 id）
    case revert(String)
    case addBack
    /// [v25.642 mac3] ⌘D 複製成新的一筆（當成新記：復原名稱「複製」、存完選到新那筆）
    case duplicate
}

/// 一次要寫的東西：哪個鍵、什麼動作、base（開表單／重抓那時的雲端原字典陣列）
struct MacWriteJob {
    let key: String
    let action: MacLedgerAction
    let base: Data
    let purpose: MacWritePurpose
    /// 寫好之後要選取的那一筆
    let ref: MacEntryRef?
    /// 新記的那一筆用的分類（存成「上次用的」）
    let rememberCategory: String?
}

/// 表單要開的那一筆
struct MacEditorRequest: Identifiable {
    enum Original {
        case newEntry
        case expense(Expense)
        case income(Income)
    }

    let id = UUID()
    /// nil＝新的一筆
    let ref: MacEntryRef?
    let startsWithIncome: Bool
    /// 開表單那時兩個鍵的雲端原字典陣列（新的一筆兩個都放，支出／收入切換用）
    let bases: [String: Data]
    let original: Original
    let draft: MacEntryRules.Draft
    let verdict: MacEditVerdict
    let payment: String

    var isNew: Bool { ref == nil }
}

struct MacDeleteAsk {
    let ref: MacEntryRef
    let key: String
    let itemID: String
    let label: String
    /// 週期收入（確認框多一句「每個月的收入統計都會少掉這筆。」）
    let recurring: Bool
}

struct MacConflictAsk {
    let conflicts: [MacFieldConflict]
    let job: MacWriteJob

    /// 「金額：NT$120 → NT$150（iPhone）／NT$200（你填的）」
    var message: String {
        conflicts.map { (c: MacFieldConflict) -> String in
            let name = MacEntryRules.fieldName(c.field)
            let before = MacEntryRules.display(field: c.field, value: c.before)
            let iphone = MacEntryRules.display(field: c.field, value: c.iphone)
            let mine = MacEntryRules.display(field: c.field, value: c.mine)
            return "\(name)：\(before) → \(iphone)（iPhone）／\(mine)（你填的）"
        }.joined(separator: "\n")
    }
}

struct MacRevertAsk {
    let job: MacWriteJob
    let fieldNames: String
}

/// cachedLinks() 快取：哪一份分帳、細項 bytes 算出來的
private struct MacLinksCache {
    let splits: Data?
    let kinds: Data?
    let links: MacLinkIDs
}

/// ⌘D 確認框：raw 在打開那一刻定下（新 id、日期＝那一刻）
struct MacDuplicateAsk {
    let ref: MacEntryRef
    let raw: [String: Any]
    let label: String
}

/// 主視窗上的確認框（一次只會有一個）
enum MacHostAsk: Identifiable {
    case delete(MacDeleteAsk)
    case conflict(MacConflictAsk)
    case revert(MacRevertAsk)
    case duplicate(MacDuplicateAsk)

    var id: String {
        switch self {
        case .delete(let a): return "delete-" + a.itemID
        case .conflict(let a): return "conflict-" + a.job.action.itemID
        case .revert(let a): return "revert-" + a.job.action.itemID
        case .duplicate(let a): return "duplicate-" + (a.raw["id"] as? String ?? "")
        }
    }

    var title: String {
        switch self {
        case .delete(let a): return "刪掉『\(a.label)』？"
        case .conflict: return "iPhone 剛改了這筆"
        case .revert: return "這筆在另一台又改過了"
        case .duplicate(let a): return MacEditPolicy.duplicateConfirm(a.label)
        }
    }
}

/// 狀態列
struct MacEditStatus: Identifiable {
    let id = UUID()
    let text: String
    let isError: Bool
    let isProgress: Bool
    /// 「已刪除〔復原〕」：按了復原哪一步
    let undoEntryID: String?
}

// MARK: - MacEditCenter

@MainActor
final class MacEditCenter: ObservableObject {
    let money: MacMoneyStore
    let journal: MacJournal
    let ui: MacUIState
    private let writer: MacCloudWriter

    @Published var sheet: MacEditorRequest?
    @Published var hostAsk: MacHostAsk?
    @Published private(set) var status: MacEditStatus?
    @Published private(set) var watchdogItems: [MacWatchdogItem] = []
    @Published private(set) var isBusy = false
    @Published private(set) var isOpening = false
    /// 表單存檔進度（按鈕字）
    @Published private(set) var phase: MacWritePhase?

    /// 視窗的 UndoManager（macEditorHost 的 .onAppear 交過來）
    weak var undoManager: UndoManager?
    /// [v25.642 mac3] ⌘D 存失敗（離線、讀不回來）時留著：10 分鐘內同一筆再按 ⌘D＝同一個 raw（同一 id），不會在 iCloud 多一筆
    private var pendingDuplicate: MacDuplicateAsk?
    private var pendingDuplicateAt: Date?
    /// [v25.642 mac3] cachedLinks() 的快取（不是 @Published：畫面重畫時讀寫不觸發更新）
    private var linksCache: MacLinksCache?
    private var bag: Set<AnyCancellable> = []

    init(money: MacMoneyStore, journal: MacJournal, ui: MacUIState) {
        self.money = money
        self.journal = journal
        self.ui = ui
        self.writer = MacCloudWriter()
        writer.onPhase = { [weak self] p in self?.phase = p }
        money.$records
            .sink { [weak self] records in self?.refreshWatchdog(records) }
            .store(in: &bag)
        money.$accountHash
            .sink { [weak self] hash in self?.accountChanged(hash) }
            .store(in: &bag)
        journal.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
        money.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
    }

    func attach(_ manager: UndoManager?) {
        undoManager = manager
    }

    // MARK: 能不能寫

    /// 寫入開關打開、黃金案例全過、這次開 App 從 iCloud 拉成功過、帳號對得上
    var writeEnabled: Bool {
        journal.writeEnabled && canEnableWrites
    }

    /// 寫入開關能不能打開（第一次拉成功＋黃金案例全過）
    var canEnableWrites: Bool {
        guard journal.golden.allPassed, money.hasFetchedThisLaunch else { return false }
        guard money.account == .available, let hash = money.accountHash else { return false }
        return journal.accountHash == hash
    }

    var writeLockText: String {
        if !journal.golden.allPassed {
            return "自我檢查 \(journal.golden.passed)/\(journal.golden.total) 沒全過，這台 Mac 先不能改"
        }
        if money.account != .available || money.accountHash == nil { return "這台 Mac 還沒讀到 iCloud 上的資料" }
        if !money.hasFetchedThisLaunch { return "還在讀 iCloud，讀完才能改" }
        if !journal.writeEnabled { return "電腦版打開「允許這台 Mac 修改」之後才能改（資料來源頁）" }
        return ""
    }

    static func key(of ref: MacEntryRef) -> String {
        switch ref {
        case .expense: return LedgerMerge.expensesKey
        case .income: return LedgerMerge.incomesKey
        }
    }

    static func uuid(of ref: MacEntryRef) -> UUID {
        switch ref {
        case .expense(let id): return id
        case .income(let id): return id
        }
    }

    private func rawEditable(_ key: String, _ id: UUID) -> Bool {
        guard let schema = LedgerMerge.schema(for: key), let raw = money.rawEntry(key: key, id: id) else { return false }
        return LedgerMerge.editable(schema, raw: raw)
    }

    /// [v25.642 mac3] 畫面用：快取的分帳、細項（money.records；存的那一刻 gate、postCheck 改用剛抓到的 links(_:)）
    /// 選單、詳情欄每畫一次會叫好幾次：同一份分帳、細項 bytes 只解一次（bytes 變了就重解）
    func cachedLinks() -> MacLinkIDs {
        let splits = money.records[MacCloud.splitsKey]?.data
        let kinds = money.records[MacCloud.kindsKey]?.data
        let live = money.splitIndex.liveIDs
        if let c = linksCache, c.splits == splits, c.kinds == kinds, c.links.liveSplitIDs == live {
            return c.links
        }
        let links = MacLinkIDs(liveSplitIDs: live,
                               splitRecordIDs: MacEditPolicy.splitRecordIDs(splits),
                               kindRecordIDs: MacEditPolicy.kindRecordIDs(kinds),
                               liveKindIDs: MacEditPolicy.liveKindIDs(kinds))
        linksCache = MacLinksCache(splits: splits, kinds: kinds, links: links)
        return links
    }

    /// [v25.642 mac3] 存的那一刻：MacCloudWriter ② 同一次抓到的分帳、細項（MacSplitIndex 只在這個檔用，不進 Writer）
    static func links(_ fresh: MacFreshLinks) -> MacLinkIDs {
        MacLinkIDs(liveSplitIDs: MacSplitIndex(data: fresh.splitData).liveIDs,
                   splitRecordIDs: MacEditPolicy.splitRecordIDs(fresh.splitData),
                   kindRecordIDs: MacEditPolicy.kindRecordIDs(fresh.kindData),
                   liveKindIDs: MacEditPolicy.liveKindIDs(fresh.kindData))
    }

    /// 每欄能不能改（找不到那筆＝nil）
    func verdict(_ ref: MacEntryRef) -> MacEditVerdict? {
        switch ref {
        case .expense(let id):
            guard let e = money.expense(id) else { return nil }
            return MacEditPolicy.expense(e, rawEditable: rawEditable(LedgerMerge.expensesKey, id),
                                         links: cachedLinks())
        case .income(let id):
            guard let i = money.income(id) else { return nil }
            return MacEditPolicy.income(i, rawEditable: rawEditable(LedgerMerge.incomesKey, id))
        }
    }

    /// 不能刪的原因（nil＝能刪；存的時候 MacCloudWriter 還會重抓分帳、細項再確認一次）
    func deleteReason(_ ref: MacEntryRef) -> String? {
        switch ref {
        case .expense(let id):
            guard let e = money.expense(id) else { return "找不到這一筆" }
            return MacEditPolicy.expenseDeleteReason(e, rawEditable: rawEditable(LedgerMerge.expensesKey, id),
                                                     links: cachedLinks())
        case .income(let id):
            guard let i = money.income(id) else { return "找不到這一筆" }
            return MacEditPolicy.incomeDeleteReason(i, rawEditable: rawEditable(LedgerMerge.incomesKey, id))
        }
    }

    func canEdit(_ ref: MacEntryRef) -> Bool {
        writeEnabled && (verdict(ref)?.canEditAny ?? false)
    }

    func canDelete(_ ref: MacEntryRef) -> Bool {
        writeEnabled && verdict(ref) != nil && deleteReason(ref) == nil
    }

    // [v25.642 mac3] ⌘D 複製成新的一筆（總設計先放骨架：G1 寫內容、G2 的右鍵選單叫；簽名不准改）

    /// 先跳確認框（打開那一刻定下 id、now），〔複製〕才寫
    func requestDuplicate(_ ref: MacEntryRef) {
        guard writeEnabled else { show(writeLockText, isError: true); return }
        guard hostAsk == nil else { return }
        guard !isBusy else { show("上一筆還在存，等一下再按", isError: true); return }
        guard case .expense(let id) = ref, let e = money.expense(id) else {
            show("只有變動支出能在電腦複製", isError: true)
            return
        }
        if let reason = duplicateReason(ref) { show(reason, isError: true); return }
        guard let raw = MacEntryRules.duplicate(e, id: UUID(), now: Date()) else {
            show("這筆編不出來，請再試一次", isError: true)
            return
        }
        // 上次存失敗的那一筆（10 分鐘內、原本那筆內容沒變）：同一個 raw（同一 id、同一個時間）
        if let pending = pendingDuplicate, pending.ref == ref, let at = pendingDuplicateAt,
           Date().timeIntervalSince(at) < 600, Self.sameCopy(pending.raw, raw) {
            hostAsk = .duplicate(pending)
            return
        }
        let label = MacEntryRules.label(raw: money.rawEntry(key: LedgerMerge.expensesKey, id: id))
        hostAsk = .duplicate(MacDuplicateAsk(ref: ref, raw: raw, label: label))
    }

    /// 兩份複製出來的原字典除了 id、date 都一樣（原本那筆在這中間被改過＝不一樣，要重新複製）
    private static func sameCopy(_ a: [String: Any], _ b: [String: Any]) -> Bool {
        var x = a
        var y = b
        for k in ["id", "date"] {
            x.removeValue(forKey: k)
            y.removeValue(forKey: k)
        }
        return (x as NSDictionary).isEqual(y as NSDictionary)
    }

    /// 選單、右鍵、詳情鈕反灰用
    func canDuplicate(_ ref: MacEntryRef) -> Bool {
        guard writeEnabled, case .expense(let id) = ref, let e = money.expense(id) else { return false }
        return MacEditPolicy.expenseDuplicateReason(e, rawEditable: rawEditable(LedgerMerge.expensesKey, id),
                                                    links: cachedLinks()) == nil
    }

    /// 不能複製的原因（nil＝能；詳情欄提示用）
    func duplicateReason(_ ref: MacEntryRef) -> String? {
        guard case .expense(let id) = ref else { return "只有變動支出能在電腦複製" }
        guard let e = money.expense(id) else { return "找不到這一筆" }
        return MacEditPolicy.expenseDuplicateReason(e, rawEditable: rawEditable(LedgerMerge.expensesKey, id),
                                                    links: cachedLinks())
    }

    // [v25.644 mac4] 〔停止扣款…〕（總設計先放骨架：G1 寫內容、G2 的右鍵選單叫；簽名不准改，judge_mac §R6 W4-15）

    /// 開同一張編輯表單、停止區預設打開（存檔走 §R4 #6 同一條路）— sim4: stop4#1
    func requestStop(_ ref: MacEntryRef) {}

    /// 選單、右鍵、詳情鈕反灰用：canEdit 而且停止那欄能改、不是「原本停在以前」— sim4: stop4#2
    func canStop(_ ref: MacEntryRef) -> Bool { false }

    /// 確認框〔複製〕：確認框收起來之後才寫（新增一筆；policyBlock、postCheck A1～A3 照擋）
    func confirmDuplicate(_ ask: MacDuplicateAsk) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let base = self.money.records[LedgerMerge.expensesKey]?.data else {
                self.show("iCloud 上還沒有這份資料", isError: true)
                return
            }
            self.pendingDuplicate = ask
            self.pendingDuplicateAt = Date()
            let ref = Self.ref(key: LedgerMerge.expensesKey, itemID: (ask.raw["id"] as? String) ?? "")
            self.run(MacWriteJob(key: LedgerMerge.expensesKey, action: .add(raw: ask.raw), base: base,
                                 purpose: .duplicate, ref: ref, rememberCategory: nil))
        }
    }

    // MARK: 開表單（先重抓；那筆不在就不開）

    func newExpense() { openNew(income: false) }

    func newIncome() { openNew(income: true) }

    private func openNew(income: Bool) {
        guard writeEnabled else { show(writeLockText, isError: true); return }
        guard sheet == nil, !isOpening else { return }
        isOpening = true
        show("取得 iCloud 最新資料…", progress: true)
        Task { [weak self] in
            guard let self else { return }
            await self.money.refresh()
            self.isOpening = false
            self.finishOpenNew(income: income)
        }
    }

    private func finishOpenNew(income: Bool) {
        if money.isOffline { show("離線中，連上網路再記", isError: true); return }
        var bases: [String: Data] = [:]
        for key in LedgerMerge.keys {
            if money.records[key]?.record != nil, let data = money.records[key]?.data { bases[key] = data }
        }
        let key = income ? LedgerMerge.incomesKey : LedgerMerge.expensesKey
        guard bases[key] != nil else {
            show("iCloud 上還沒有這份資料，先在 iPhone 打開 iCloud 同步", isError: true)
            return
        }
        // 新記收入：週期預設單次、薪水的「固定薪水」預設開（跟 iPhone AddIncomeView 一樣）
        let draft = MacEntryRules.Draft(title: "", amountText: "", day: Date(),
                                        expenseCategory: Self.lastExpenseCategory(),
                                        incomeCategory: Self.lastIncomeCategory(), note: "",
                                        period: .once, isFixedSalary: true)
        clearStatus()
        sheet = MacEditorRequest(ref: nil, startsWithIncome: income, bases: bases, original: .newEntry, draft: draft,
                                 verdict: MacEditVerdict(lock: nil, fieldReasons: [:]), payment: "不指定")
    }

    func requestEdit(_ ref: MacEntryRef) {
        guard writeEnabled else { show(writeLockText, isError: true); return }
        guard let v = verdict(ref) else { show("找不到這一筆", isError: true); return }
        if let lock = v.lock { show(lock, isError: true); return }
        guard sheet == nil, !isOpening else { return }
        isOpening = true
        show("取得 iCloud 最新資料…", progress: true)
        Task { [weak self] in
            guard let self else { return }
            await self.money.refresh()
            self.isOpening = false
            self.finishOpenEdit(ref)
        }
    }

    private func finishOpenEdit(_ ref: MacEntryRef) {
        if money.isOffline { show("離線中，連上網路再改", isError: true); return }
        let key = Self.key(of: ref)
        let id = Self.uuid(of: ref)
        guard let base = money.records[key]?.data, money.rawEntry(key: key, id: id) != nil,
              let v = verdict(ref) else {
            show("這筆已經在另一台刪掉了", isError: true)
            return
        }
        if let lock = v.lock { show(lock, isError: true); return }
        let request: MacEditorRequest
        switch ref {
        case .expense:
            guard let e = money.expense(id) else { show("這筆已經在另一台刪掉了", isError: true); return }
            request = Self.editRequest(expense: e, ref: ref, base: base, key: key, verdict: v)
        case .income:
            guard let i = money.income(id) else { show("這筆已經在另一台刪掉了", isError: true); return }
            request = Self.editRequest(income: i, ref: ref, base: base, key: key, verdict: v)
        }
        clearStatus()
        sheet = request
    }

    private static func editRequest(expense e: Expense, ref: MacEntryRef, base: Data, key: String,
                                    verdict: MacEditVerdict) -> MacEditorRequest {
        let text = MacEntryRules.amountText(e.amount)
        let cat = e.variableCategory ?? .other
        let draft = MacEntryRules.Draft(title: e.title, amountText: text, day: e.date, expenseCategory: cat,
                                        incomeCategory: .salary, note: e.note, originalAmountText: text)
        var payment = "不指定"
        if e.linkedCreditCardMilestoneId != nil {
            payment = "信用卡"
        } else if e.linkedBankMilestoneId != nil {
            payment = "銀行"
        }
        return MacEditorRequest(ref: ref, startsWithIncome: false, bases: [key: base], original: .expense(e),
                                draft: draft, verdict: verdict, payment: payment)
    }

    private static func editRequest(income i: Income, ref: MacEntryRef, base: Data, key: String,
                                    verdict: MacEditVerdict) -> MacEditorRequest {
        let text = MacEntryRules.amountText(i.amount)
        // 結束那一區：沒設過時日子先放今天（不早於開始日），原因先放「換工作」（跟 iPhone 預設一樣）；originalEnd 同值＝沒動就不寫
        let end = MacIncomeEndDraft(enabled: i.endDate != nil, day: i.endDate ?? max(i.date, Date()),
                                    reason: i.endReason ?? .jobChange)
        let draft = MacEntryRules.Draft(title: i.title, amountText: text, day: i.date, expenseCategory: .food,
                                        incomeCategory: i.category, note: i.note, originalAmountText: text,
                                        period: i.period, isFixedSalary: i.isFixedSalary, end: end, originalEnd: end)
        let payment = i.linkedBankMilestoneId != nil ? "銀行" : "不指定"
        return MacEditorRequest(ref: ref, startsWithIncome: true, bases: [key: base], original: .income(i),
                                draft: draft, verdict: verdict, payment: payment)
    }

    // MARK: 上次用的分類（只存這台）

    static func lastExpenseCategory() -> VariableCategory {
        let raw = UserDefaults.standard.string(forKey: "mac.lastCategory") ?? ""
        if let c = VariableCategory(rawValue: raw), MacEditPolicy.eightCategories.contains(c) { return c }
        return .food
    }

    static func lastIncomeCategory() -> IncomeCategory {
        let raw = UserDefaults.standard.string(forKey: "mac.lastIncomeCategory") ?? ""
        if let c = IncomeCategory(rawValue: raw), MacEditPolicy.incomeCategories.contains(c) { return c }
        return .salary
    }

    private static func remember(_ category: String?, key: String) {
        guard let category else { return }
        if key == LedgerMerge.incomesKey {
            UserDefaults.standard.set(category, forKey: "mac.lastIncomeCategory")
        } else {
            UserDefaults.standard.set(category, forKey: "mac.lastCategory")
        }
    }

    // MARK: 刪除（要確認）

    func requestDelete(_ ref: MacEntryRef) {
        guard writeEnabled else { show(writeLockText, isError: true); return }
        if let reason = deleteReason(ref) { show(reason, isError: true); return }
        let key = Self.key(of: ref)
        let id = Self.uuid(of: ref)
        guard let raw = money.rawEntry(key: key, id: id), let itemID = raw["id"] as? String else {
            show("找不到這一筆", isError: true)
            return
        }
        var recurring = false
        if case .income = ref, let i = money.income(id) { recurring = i.period != .once }
        hostAsk = .delete(MacDeleteAsk(ref: ref, key: key, itemID: itemID, label: MacEntryRules.label(raw: raw),
                                       recurring: recurring))
    }

    /// 確認框〔刪除〕：確認框收起來之後才寫
    func confirmDelete(_ ask: MacDeleteAsk) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let base = self.money.records[ask.key]?.data else {
                self.show("iCloud 上還沒有這份資料", isError: true)
                return
            }
            let job = MacWriteJob(key: ask.key, action: .delete(id: ask.itemID), base: base, purpose: .delete,
                                  ref: ask.ref, rememberCategory: nil)
            self.run(job)
        }
    }

    // MARK: 寫入（表單、刪除、復原、補回、加回都走這裡）

    /// 表單直接叫：回傳結果，表單決定怎麼收（成功時表單先 dismiss，再叫 finish）
    func submit(_ job: MacWriteJob, resolution: MacConflictResolution) async -> (MacWriteOutcome, MacJournalEntry?) {
        guard !isBusy else { return (.failed("上一筆還在存，等一下再按"), nil) }
        isBusy = true
        let key = job.key
        let purpose = job.purpose
        let outcome = await writer.save(key: job.key, action: job.action, base: job.base, resolution: resolution,
                                        journal: journal, golden: journal.golden, writeEnabled: writeEnabled,
                                        gate: { [weak self] item, changes, fresh in
                                            self?.gateReason(key: key, item: item, changes: changes, fresh: fresh)
                                        },
                                        postCheck: { action, fetched, merged, fresh in
                                            MacEditCenter.postReason(key: key, purpose: purpose, action: action,
                                                                     fetched: fetched, merged: merged, fresh: fresh)
                                        })
        isBusy = false
        phase = nil
        if case .saved = outcome { return (outcome, writer.lastEntry) }
        return (outcome, nil)
    }

    /// 不在表單裡的寫入
    func run(_ job: MacWriteJob, resolution: MacConflictResolution = .askFirst) {
        guard !isBusy else { show("上一筆還在存，等一下再按", isError: true); return }
        if let reason = policyBlock(job.action, key: job.key) { show(reason, isError: true); return }
        show("存到 iCloud…", progress: true)
        Task { [weak self] in
            guard let self else { return }
            let (outcome, entry) = await self.submit(job, resolution: resolution)
            self.finish(job, outcome: outcome, entry: entry)
        }
    }

    /// 不在表單裡的改、刪（復原、重做、改回、補回）也照 MacEditPolicy：那筆現在鎖住的欄位不動、不能刪的不刪。
    /// 新增（加回刪前原字典、從備份加回、〔補回〕）：收入原字典連著銀行或股票不加回（S2）。找不到那筆＝交給 MacCloudWriter（會回 goneElsewhere）
    private func policyBlock(_ action: MacLedgerAction, key: String) -> String? {
        switch action {
        case .add(let raw):
            // sim2: block#1（S2）收入照 Mac 2
            if key == LedgerMerge.incomesKey { return MacEditPolicy.addBackReason(raw: raw) }
            // sim3: block3#1 支出：解不開、整筆鎖、連著銀行／照片／分帳／細項 → 不加回（快取的分帳細項；存的那一刻 postCheck 再看剛抓到的）
            return MacEditPolicy.expenseAddBackReason(raw: raw, links: cachedLinks())
        case .delete(let itemID):
            guard let ref = Self.ref(key: key, itemID: itemID), verdict(ref) != nil else { return nil }
            return deleteReason(ref)
        case .edit(let itemID, let changes):
            guard let ref = Self.ref(key: key, itemID: itemID), let v = verdict(ref) else { return nil }
            if let lock = v.lock { return lock }
            for field in changes.keys.sorted() {
                // sim2: block#2（S4）對不到表單欄位的一律擋
                guard let f = Self.editField(field, key: key) else { return MacEditPolicy.reasonFieldUnknown }
                if let reason = v.reason(f) { return reason }
                // sim2: catto#2 換分類看新值（復原、改回：那筆現在已是每月／每年就不准換成薪水）
                if field == "category", case .income(let id) = ref, let i = money.income(id),
                   let reason = MacEditPolicy.incomeCategoryChangeReason(i, to: changes[field] ?? nil) {
                    return reason
                }
                // sim3: block3#2 支出換分類看新值（字串、8 類；復原、改回、補回也一樣）
                if field == "variableCategory", case .expense(let id) = ref, let e = money.expense(id),
                   let reason = MacEditPolicy.expenseCategoryChangeReason(e, to: changes[field] ?? nil) {
                    return reason
                }
            }
            return nil
        }
    }

    /// 原字典欄位名 → 表單欄位（endDate、endReason 只在收入那包對到結束日；支出那包回 nil＝擋）
    private static func editField(_ raw: String, key: String) -> MacEditField? {
        switch raw {
        case "title": return .title
        case "note": return .note
        case "amount": return .amount
        case "date": return .date
        case "variableCategory", "category": return .category
        case "endDate", "endReason": return key == LedgerMerge.incomesKey ? .endDate : nil
        default: return nil
        }
    }

    /// S1：MacCloudWriter 重抓之後交過來剛抓到的那筆原字典＋這次的改動；nil＝放行，否則「這筆剛在 iPhone 改過，現在…」
    /// （sim2 gate；值已經跟剛抓到的那筆一樣的欄位跳過：〔用 iPhone 的〕換成雲端值的那幾欄等於沒改）
    /// [v25.642 mac3] fresh＝MacCloudWriter ② 同一次抓到的分帳、細項（支出用；收入 fetched＝false 不看）
    func gateReason(key: String, item: [String: Any], changes: [String: Any?], fresh: MacFreshLinks) -> String? {
        let prefix = MacEditPolicy.reasonGatePrefix
        // sim3: gate3#1 支出那包一定要有剛抓到的分帳細項（Writer 一定傳 true；防呆只會多擋）
        if key == LedgerMerge.expensesKey && !fresh.fetched { return prefix + MacEditPolicy.reasonLinksUnknown }
        // sim2: gate#3 剛抓到的那筆用這一版的模型解得開才往下（解不開＝較新的 iPhone 版記的）
        guard let schema = LedgerMerge.schema(for: key), JSONSerialization.isValidJSONObject(item),
              let data = try? JSONSerialization.data(withJSONObject: item, options: []) else {
            return prefix + MacEditPolicy.reasonNewer
        }
        let rawOK = LedgerMerge.editable(schema, raw: item)
        let verdict: MacEditVerdict
        var start: Date?
        var income: Income?
        var expense: Expense?
        if key == LedgerMerge.incomesKey {
            guard let i = try? JSONDecoder().decode(Income.self, from: data) else { return prefix + MacEditPolicy.reasonNewer }
            verdict = MacEditPolicy.income(i, rawEditable: rawOK)
            start = i.date
            income = i
        } else {
            guard let e = try? JSONDecoder().decode(Expense.self, from: data) else { return prefix + MacEditPolicy.reasonNewer }
            // sim3: gate3#1 用剛抓到的分帳、細項（不是快取）
            verdict = MacEditPolicy.expense(e, rawEditable: rawOK, links: Self.links(fresh))
            expense = e
        }
        // sim2: gate#4 現在整筆鎖
        if let lock = verdict.lock { return prefix + lock }
        // sim2: gate#5 每一欄
        for k in changes.keys.sorted() {
            let value: Any? = changes[k] ?? nil
            if LedgerMerge.same(item[k], value) { continue }
            guard let f = Self.editField(k, key: key) else { return prefix + MacEditPolicy.reasonFieldUnknown }
            if let r = verdict.reason(f) { return prefix + r }
            // sim2: catto#3 換分類看新值是不是剛抓到那筆准的（單次 4 類；週期只在獎金、禮金、確幸）
            if k == "category", let i = income, let r = MacEditPolicy.incomeCategoryChangeReason(i, to: value) {
                return prefix + r
            }
            // sim3: catto3（gate）支出換分類看新值是不是 8 類裡的字串
            if k == "variableCategory", let e = expense, let r = MacEditPolicy.expenseCategoryChangeReason(e, to: value) {
                return prefix + r
            }
        }
        // sim2: gate#6 結束日不能早於剛抓到的開始那天
        if let start, let end = (changes["endDate"] ?? nil) as? Double {
            let calendar = Calendar.current
            let endDay = Date(timeIntervalSinceReferenceDate: end)
            if calendar.startOfDay(for: endDay) < calendar.startOfDay(for: start) {
                return prefix + MacEditPolicy.errorEndBefore
            }
        }
        return nil
    }

    /// 寫完：收進 MacMoneyStore、登記復原、狀態列
    func finish(_ job: MacWriteJob, outcome: MacWriteOutcome, entry: MacJournalEntry?) {
        if case .duplicate = job.purpose {
            // 存好（或 iCloud 上已經有這筆）才忘掉；其餘留著，再按 ⌘D 用同一個 raw
            switch outcome {
            case .saved, .nothingToWrite:
                pendingDuplicate = nil
                pendingDuplicateAt = nil
            default: break
            }
        }
        switch outcome {
        case .saved(let record, let merged):
            money.adopt(record)
            afterSaved(job, entry: entry, merged: merged)
        case .nothingToWrite(let record):
            money.adopt(record)
            if case .restore(let id) = job.purpose { journal.resolve(id) }
            show(Self.text(for: outcome))
        case .needsDecision(let conflicts):
            clearStatus()
            hostAsk = .conflict(MacConflictAsk(conflicts: conflicts, job: job))
        default:
            show(Self.text(for: outcome), isError: true)
        }
        refreshWatchdog(money.records)
    }

    private func afterSaved(_ job: MacWriteJob, entry: MacJournalEntry?, merged: Bool) {
        let time = Self.clock(Date())
        switch job.purpose {
        case .form(let isNew):
            if let entry { registerUndo(entry.id, name: isNew ? "記一筆" : "修改", redo: false) }
            if isNew { Self.remember(job.rememberCategory, key: job.key) }
            if let ref = job.ref, ui.page.shows(ref) { ui.selection = ref }   // sim2: sel#4 只在這一頁看得到時選
            show(merged ? "iPhone 剛改過別的欄位，已一起保留" : "已存 \(time)")
        case .delete:
            if let entry { registerUndo(entry.id, name: "刪除", redo: false) }
            if let ref = job.ref, ui.selection == ref { ui.selection = nil }
            showDeleted(entryID: entry?.id)
        case .undo:
            show("已復原 \(time)")                          // 復原、重做自己寫的那一筆不登記，不佔 20 步
        case .redo:
            show("已重做 \(time)")
        case .restore(let id):
            journal.resolve(id)
            if let entry { registerUndo(entry.id, name: "補回", redo: false) }
            show("已補回 \(time)")
        case .revert:
            if let entry { registerUndo(entry.id, name: "改回", redo: false) }
            show("已改回 \(time)")
        case .addBack:
            if let entry { registerUndo(entry.id, name: "從備份加回", redo: false) }
            if let ref = job.ref, ui.page.shows(ref) { ui.selection = ref }   // sim2: sel#4
            show("已從備份加回 \(time)")
        case .duplicate:
            if let entry { registerUndo(entry.id, name: "複製", redo: false) }
            if let ref = job.ref, ui.page.shows(ref) { ui.selection = ref }
            show("已複製 \(time)")
        }
    }

    // MARK: postCheck（W-4：合併後真正要寫的那一筆；static：不靠 self，self 不在也照擋）

    /// MacCloudWriter ⑥ 之後、⑦ 之前叫：fetched＝剛抓到那筆、merged＝合併後那筆、fresh＝剛抓到的分帳細項。nil＝放行
    static func postReason(key: String, purpose: MacWritePurpose, action: MacLedgerAction, fetched: [String: Any]?,
                           merged: [String: Any]?, fresh: MacFreshLinks) -> String? {
        guard let schema = LedgerMerge.schema(for: key) else { return MacEditPolicy.reasonPostShape }
        let isExpense = key == LedgerMerge.expensesKey
        switch action {
        case .delete:
            return nil
        case .edit(_, let changes):
            // sim3: post3#P1 合併後那筆要在
            guard let merged else { return MacEditPolicy.reasonPostShape }
            // sim3: post3#P2 跟剛抓到那筆不同的鍵 ⊆ 這次改的鍵 ∩ 這包准改的欄位
            let allow = isExpense ? MacEditPolicy.expensePostKeys : MacEditPolicy.incomePostKeys
            let allowed = Set(changes.keys).intersection(allow)
            let before: [String: Any] = fetched ?? [:]
            let keys = Set(before.keys).union(merged.keys)
            let diff = keys.filter { k in !LedgerMerge.same(before[k], merged[k]) }
            if !diff.isSubset(of: allowed) { return MacEditPolicy.reasonPostShape }
            // sim3: post3#P3 那幾個不同的鍵逐一值檢查（雲端本來就有的舊殘留不擋）
            for k in diff.sorted() where !MacEditPolicy.postValueOK(key: key, field: k, value: merged[k]) {
                return MacEditPolicy.reasonValueBad
            }
            // sim3: post3#P4 本來看得懂的那筆，合併後變成看不懂 → 擋
            if let fetched, LedgerMerge.editable(schema, raw: fetched), !LedgerMerge.editable(schema, raw: merged) {
                return MacEditPolicy.reasonPostShape
            }
            return nil
        case .add:
            // sim3: post3#A1 解得開、editable
            guard let merged, decodes(merged, expense: isExpense), LedgerMerge.editable(schema, raw: merged) else {
                return MacEditPolicy.reasonPostShape
            }
            // sim3: post3#A2 加回擋連著的（支出用剛抓到的分帳細項；收入照 Mac 2）
            guard isExpense else { return MacEditPolicy.addBackReason(raw: merged) }
            if let reason = MacEditPolicy.expenseAddBackReason(raw: merged, links: links(fresh)) { return reason }
            // sim3: post3#A3 表單新記、⌘D 複製、〔另存〕：只准 8 類變動支出，不准連著的鍵、一按就記、照片、金額歷史
            guard checksNewShape(purpose) else { return nil }
            guard (merged["expenseType"] as? String) == ExpenseType.variable.rawValue,
                  MacEditPolicy.expenseCategoryValueOK(merged["variableCategory"]) else {
                return MacEditPolicy.reasonPostShape
            }
            for k in newEntryBannedKeys where nonEmpty(merged[k]) {
                return MacEditPolicy.reasonPostShape
            }
            for k in ["photoFileNames", "amountHistory"] {
                if let list = merged[k] as? [Any], !list.isEmpty { return MacEditPolicy.reasonPostShape }
            }
            return nil
        }
    }

    /// post3#A3 新的一筆不准出現的鍵（在、不是 NSNull、不是空字串就擋）
    private static let newEntryBannedKeys = [
        "linkedBankMilestoneId", "linkedBankCurrency", "linkedCreditCardMilestoneId", "linkedStockId",
        "linkedRealEstateId", "linkedVehicleId", "linkedInsuranceId", "linkedTripPlanId", "linkedTripStopId",
        "fromQuickRecord",
    ]

    /// A3 只看表單新記（含〔另存〕）與 ⌘D 複製
    private static func checksNewShape(_ purpose: MacWritePurpose) -> Bool {
        switch purpose {
        case .form(let isNew): return isNew
        case .duplicate: return true
        default: return false
        }
    }

    /// 〔另存成新的一筆〕之前先看 post3#A3 一定擋的兩種（fromQuickRecord、amountHistory；detachedCopy 會照留）。
    /// 只管支出（收入 A3 不看）；連著的鍵、照片 detachedCopy 已經回 nil。false＝不給另存
    static func detachedCopyPasses(key: String, raw: [String: Any]) -> Bool {
        guard key == LedgerMerge.expensesKey else { return true }
        if nonEmpty(raw["fromQuickRecord"]) { return false }
        if let list = raw["amountHistory"] as? [Any], !list.isEmpty { return false }
        return true
    }

    private static func nonEmpty(_ value: Any?) -> Bool {
        guard let v = value, !(v is NSNull) else { return false }
        if let s = v as? String { return !s.isEmpty }
        return true
    }

    /// 原字典用這一版的模型解得開
    private static func decodes(_ raw: [String: Any], expense: Bool) -> Bool {
        guard JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw, options: []) else { return false }
        if expense { return (try? JSONDecoder().decode(Expense.self, from: data)) != nil }
        return (try? JSONDecoder().decode(Income.self, from: data)) != nil
    }

    /// 寫入結果 → 一句話
    static func text(for outcome: MacWriteOutcome) -> String {
        switch outcome {
        case .saved: return "已存"
        case .nothingToWrite: return "iCloud 上已經是這樣了，不用再存"
        case .keptByOtherDevice: return "另一台剛改過這筆，先留著沒刪"
        case .needsDecision: return "iPhone 剛改了這筆"
        case .goneElsewhere: return "這筆在另一台已經刪掉了"
        case .busy: return "iPhone 剛好也在存，等幾秒再按一次"
        case .offline: return "離線中，連上網路再存"
        case .notSignedIn: return "這台 Mac 沒登入 iCloud（系統設定 → Apple 帳號）"
        case .noRecord: return "iCloud 上還沒有這份資料，先在 iPhone 打開 iCloud 同步"
        case .locked(let reason): return reason
        case .selfCheckFailed(let problems): return "存之前的自我檢查沒過，這次沒有寫（\(problems.first ?? "")）"
        case .cannotMerge: return "iCloud 上那份看不懂，這次沒有寫"
        case .failed(let message): return message
        }
    }

    // MARK: 衝突、改回的確認框

    /// 〔用我填的〕〔用 iPhone 的〕：確認框收起來之後才寫
    func resolveConflict(_ ask: MacConflictAsk, resolution: MacConflictResolution) {
        DispatchQueue.main.async { [weak self] in
            self?.run(ask.job, resolution: resolution)
        }
    }

    func confirmRevert(_ ask: MacRevertAsk) {
        DispatchQueue.main.async { [weak self] in
            self?.run(ask.job, resolution: .mine)
        }
    }

    // MARK: 復原（⌘Z／⌘⇧Z；最多 20 步；走同一條寫入路徑）

    private func registerUndo(_ entryID: String, name: String, redo: Bool) {
        guard let manager = undoManager else { return }
        journal.markUndoable(entryID)
        manager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                if redo {
                    target.redoStep(entryID, name: name)
                } else {
                    target.undoStep(entryID, name: name)
                }
            }
        }
        manager.setActionName(name)
    }

    private func undoStep(_ entryID: String, name: String) {
        registerUndo(entryID, name: name, redo: true)
        guard journal.canUndo(entryID), let entry = journal.entry(entryID) else {
            show("這一步已經不能復原（最多 \(MacJournal.undoLimit) 步）", isError: true)
            return
        }
        performInverse(entry, purpose: .undo)
    }

    private func redoStep(_ entryID: String, name: String) {
        registerUndo(entryID, name: name, redo: false)
        guard journal.canUndo(entryID), let entry = journal.entry(entryID) else {
            show("這一步已經不能重做", isError: true)
            return
        }
        performForward(entry, purpose: .redo)
    }

    /// 狀態列「已刪除〔復原〕」
    func undoFromStatus(_ entryID: String) {
        if let manager = undoManager, manager.canUndo {
            manager.undo()
        } else if let entry = journal.entry(entryID) {
            performInverse(entry, purpose: .undo)
        }
    }

    /// 反過來做：新增→刪掉、刪除→把刪前原字典加回、改→只改回這次改的欄位（那欄現在不是電腦寫的值 → 先問）
    private func performInverse(_ entry: MacJournalEntry, purpose: MacWritePurpose) {
        guard writeEnabled else { show(writeLockText, isError: true); return }
        show("取得 iCloud 最新資料…", progress: true)
        Task { [weak self] in
            guard let self else { return }
            await self.money.refresh()
            self.inverseAfterRefresh(entry, purpose: purpose)
        }
    }

    private func inverseAfterRefresh(_ entry: MacJournalEntry, purpose: MacWritePurpose) {
        guard let base = money.records[entry.key]?.data else {
            show("iCloud 上還沒有這份資料", isError: true)
            return
        }
        let ref = Self.ref(key: entry.key, itemID: entry.itemID)
        switch entry.kind {
        case .add:
            run(MacWriteJob(key: entry.key, action: .delete(id: entry.itemID), base: base, purpose: purpose,
                            ref: ref, rememberCategory: nil))
        case .delete:
            guard let raw = entry.rawBefore else { show("日誌裡沒有刪前那筆，沒辦法加回", isError: true); return }
            run(MacWriteJob(key: entry.key, action: .add(raw: raw), base: base, purpose: purpose, ref: ref,
                            rememberCategory: nil))
        case .edit:
            guard let current = MacCloudWriter.item(entry.itemID, in: base) else {
                show("這筆已經在另一台刪掉了", isError: true)
                return
            }
            var changes: [String: Any?] = [:]
            var drifted: [String] = []
            for (k, pair) in entry.fields {
                changes.updateValue(pair.before, forKey: k)
                if !LedgerMerge.same(current[k], pair.after) { drifted.append(k) }
            }
            let job = MacWriteJob(key: entry.key, action: .edit(id: entry.itemID, changes: changes), base: base,
                                  purpose: purpose, ref: ref, rememberCategory: nil)
            if drifted.isEmpty {
                run(job)
            } else {
                clearStatus()
                let names = drifted.sorted().map { k in MacEntryRules.fieldName(k) }.joined(separator: "、")
                hostAsk = .revert(MacRevertAsk(job: job, fieldNames: names))
            }
        }
    }

    /// 再做一次：新增→加回、刪除→再刪、改→改成電腦寫的值
    private func performForward(_ entry: MacJournalEntry, purpose: MacWritePurpose) {
        guard writeEnabled else { show(writeLockText, isError: true); return }
        show("取得 iCloud 最新資料…", progress: true)
        Task { [weak self] in
            guard let self else { return }
            await self.money.refresh()
            guard let base = self.money.records[entry.key]?.data, let action = Self.forwardAction(entry) else {
                self.show("iCloud 上還沒有這份資料", isError: true)
                return
            }
            let ref = Self.ref(key: entry.key, itemID: entry.itemID)
            self.run(MacWriteJob(key: entry.key, action: action, base: base, purpose: purpose, ref: ref,
                                 rememberCategory: nil))
        }
    }

    private static func forwardAction(_ entry: MacJournalEntry) -> MacLedgerAction? {
        switch entry.kind {
        case .add:
            guard let raw = entry.rawAfter else { return nil }
            return .add(raw: raw)
        case .delete:
            return .delete(id: entry.itemID)
        case .edit:
            var changes: [String: Any?] = [:]
            for (k, pair) in entry.fields { changes.updateValue(pair.after, forKey: k) }
            return .edit(id: entry.itemID, changes: changes)
        }
    }

    static func ref(key: String, itemID: String) -> MacEntryRef? {
        guard let uuid = UUID(uuidString: itemID) else { return nil }
        return key == LedgerMerge.incomesKey ? .income(uuid) : .expense(uuid)
    }

    // MARK: 看門狗、補回、改回、從備份加回

    private func refreshWatchdog(_ records: [String: MacKVRecord]) {
        watchdogItems = journal.watchdog(records: records)
    }

    private func accountChanged(_ hash: String?) {
        if journal.switchAccount(hash) {
            undoManager?.removeAllActions(withTarget: self)
            sheet = nil
            hostAsk = nil
            clearStatus()
        }
        refreshWatchdog(money.records)
    }

    /// 〔不用了〕
    func dismissWatchdog() {
        journal.dismiss(watchdogItems)
        refreshWatchdog(money.records)
    }

    /// 〔補回〕：一筆一筆走一般寫入路徑（每次只寫一個鍵）
    func restore(_ items: [MacWatchdogItem]) {
        guard writeEnabled else { show(writeLockText, isError: true); return }
        guard !isBusy, !items.isEmpty else { return }
        show("取得 iCloud 最新資料…", progress: true)
        Task { [weak self] in
            guard let self else { return }
            await self.money.refresh()
            await self.restoreAll(items)
        }
    }

    private func restoreAll(_ items: [MacWatchdogItem]) async {
        var done = 0
        var problem: String?
        for item in items {
            guard let action = restoreAction(item) else { continue }
            if let reason = policyBlock(action, key: item.entry.key) {
                problem = reason
                break
            }
            guard let base = money.records[item.entry.key]?.data else {
                problem = "iCloud 上還沒有這份資料"
                break
            }
            let job = MacWriteJob(key: item.entry.key, action: action, base: base, purpose: .restore(item.entry.id),
                                  ref: Self.ref(key: item.entry.key, itemID: item.entry.itemID), rememberCategory: nil)
            let (outcome, entry) = await submit(job, resolution: .mine)
            switch outcome {
            case .saved(let record, _):
                money.adopt(record)
                journal.resolve(item.entry.id)
                if let entry { registerUndo(entry.id, name: "補回", redo: false) }
                done += 1
            case .nothingToWrite(let record):
                money.adopt(record)
                journal.resolve(item.entry.id)
                done += 1
            default:
                problem = Self.text(for: outcome)
            }
            if problem != nil { break }
        }
        refreshWatchdog(money.records)
        if let problem {
            show("補回 \(done) 筆，其餘沒補回：\(problem)", isError: true)
        } else {
            show("已補回 \(done) 筆 \(Self.clock(Date()))")
        }
    }

    private func restoreAction(_ item: MacWatchdogItem) -> MacLedgerAction? {
        let e = item.entry
        switch item.reason {
        case .addMissing, .editMissing:
            guard let raw = e.rawAfter else { return nil }
            return .add(raw: raw)
        case .editReverted:
            let fields = e.fields
            var changes: [String: Any?] = [:]
            for k in item.revertedFields {
                if let pair = fields[k] { changes.updateValue(pair.after, forKey: k) }
            }
            return changes.isEmpty ? nil : .edit(id: e.itemID, changes: changes)
        case .deleteBack:
            if let ref = Self.ref(key: e.key, itemID: e.itemID), deleteReason(ref) != nil { return nil }
            return .delete(id: e.itemID)
        }
    }

    /// 「最近在電腦改的」：被蓋回去的〔補回〕
    func restoreEntry(_ entryID: String) {
        let items = watchdogItems.filter { item in item.entry.id == entryID }
        restore(items)
    }

    /// 「最近在電腦改的」：〔改回〕＝把那次動作反過來做
    func revertEntry(_ entryID: String) {
        guard let entry = journal.entry(entryID) else { return }
        performInverse(entry, purpose: .revert(entryID))
    }

    /// 從備份挑一筆加回（不整包還原）
    func addBack(raw: [String: Any], key: String) {
        guard writeEnabled else { show(writeLockText, isError: true); return }
        show("取得 iCloud 最新資料…", progress: true)
        Task { [weak self] in
            guard let self else { return }
            await self.money.refresh()
            guard let base = self.money.records[key]?.data else {
                self.show("iCloud 上還沒有這份資料", isError: true)
                return
            }
            let ref = Self.ref(key: key, itemID: (raw["id"] as? String) ?? "")
            self.run(MacWriteJob(key: key, action: .add(raw: raw), base: base, purpose: .addBack, ref: ref,
                                 rememberCategory: nil))
        }
    }

    // MARK: 狀態列

    func show(_ text: String, isError: Bool = false, progress: Bool = false) {
        status = MacEditStatus(text: text, isError: isError, isProgress: progress, undoEntryID: nil)
    }

    private func showDeleted(entryID: String?) {
        let s = MacEditStatus(text: "已刪除", isError: false, isProgress: false, undoEntryID: entryID)
        status = s
        let time = Self.clock(Date())
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard let self, self.status?.id == s.id else { return }
            self.show("已刪除 \(time)")
        }
    }

    func clearStatus() {
        status = nil
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    static func clock(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }
}

// MARK: - 選單（⌘N ⌘⇧N ⌘E ⌘⌫；寫入開關關著時反灰）

@MainActor
struct MacEditCommands: Commands {
    @ObservedObject var edit: MacEditCenter
    @ObservedObject var ui: MacUIState

    private var blocked: Bool {
        !edit.writeEnabled || edit.sheet != nil || edit.isOpening
    }

    // sim2: sel#3 搜尋框有焦點（⌘⌫ 留給文字框）、選到的不在這一頁 → 反灰
    private var canEditSelection: Bool {
        guard let ref = ui.selection, !blocked, !ui.searchFieldFocused, ui.page.shows(ref) else { return false }
        return edit.canEdit(ref)
    }

    private var canDeleteSelection: Bool {
        guard let ref = ui.selection, !blocked, !ui.searchFieldFocused, ui.page.shows(ref) else { return false }
        return edit.canDelete(ref)
    }

    // [v25.642 mac3] ⌘D：同 ⌘E 的條件，只給支出
    private var canDuplicateSelection: Bool {
        guard let ref = ui.selection, !blocked, !ui.searchFieldFocused, ui.page.shows(ref) else { return false }
        guard case .expense = ref else { return false }
        return edit.canDuplicate(ref)
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("記一筆支出") { edit.newExpense() }
                .keyboardShortcut("n")
                .disabled(blocked)
            Button("記一筆收入") { edit.newIncome() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(blocked)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("編輯這一筆") { editSelection() }
                .keyboardShortcut("e")
                .disabled(!canEditSelection)
            Button("複製成新的一筆") { duplicateSelection() }
                .keyboardShortcut("d")
                .disabled(!canDuplicateSelection)
            Button("刪除這一筆") { deleteSelection() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!canDeleteSelection)
        }
    }

    private func editSelection() {
        if let ref = ui.selection { edit.requestEdit(ref) }
    }

    private func deleteSelection() {
        if let ref = ui.selection { edit.requestDelete(ref) }
    }

    private func duplicateSelection() {
        if let ref = ui.selection { edit.requestDuplicate(ref) }
    }
}

// MARK: - 主視窗：表單、確認框、Debug 紅條、看門狗橫幅、狀態列

extension View {
    func macEditorHost(_ app: MacAppModel) -> some View {
        modifier(MacEditorHostModifier(app: app, edit: app.edit))
    }
}

private struct MacEditorHostModifier: ViewModifier {
    let app: MacAppModel
    @ObservedObject var edit: MacEditCenter
    @Environment(\.undoManager) private var undoManager

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                MacEditorTopBars(edit: edit)
            }
            .overlay(alignment: .bottom) {
                MacEditStatusBar(edit: edit)
            }
            .sheet(item: $edit.sheet) { request in
                MacEditorSheet(request: request).macStores(app)
            }
            .modifier(MacHostAskDialog(edit: edit))
            .onAppear { edit.attach(undoManager) }
            .onChange(of: undoManager) { _, manager in edit.attach(manager) }
    }
}

/// 刪除確認、衝突詢問（不在表單時）、改回前詢問：同一個確認框，一次一個
private struct MacHostAskDialog: ViewModifier {
    @ObservedObject var edit: MacEditCenter

    private var isPresented: Binding<Bool> {
        Binding(get: { edit.hostAsk != nil }, set: { shown in if !shown { edit.hostAsk = nil } })
    }

    func body(content: Content) -> some View {
        content.confirmationDialog(edit.hostAsk?.title ?? "", isPresented: isPresented, titleVisibility: .visible,
                                   presenting: edit.hostAsk) { ask in
            MacHostAskButtons(ask: ask, edit: edit)
        } message: { ask in
            Text(Self.message(ask))
        }
    }

    private static func message(_ ask: MacHostAsk) -> String {
        switch ask {
        case .delete(let a):
            return a.recurring ? "iPhone、iPad 也會一起刪掉。每個月的收入統計都會少掉這筆。" : "iPhone、iPad 也會一起刪掉。"
        case .conflict(let a): return a.message
        case .revert(let a): return "「\(a.fieldNames)」在另一台又改過，還要改回電腦改之前的值嗎？"
        case .duplicate: return "iPhone、iPad 也會多這一筆。"
        }
    }
}

private struct MacHostAskButtons: View {
    let ask: MacHostAsk
    let edit: MacEditCenter

    var body: some View {
        switch ask {
        case .delete(let a):
            Button("刪除", role: .destructive) { edit.confirmDelete(a) }
            Button("取消", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        case .conflict(let a):
            Button("用我填的") { edit.resolveConflict(a, resolution: .mine) }
            Button("用 iPhone 的") { edit.resolveConflict(a, resolution: .theirs) }
            Button("取消", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        case .revert(let a):
            Button("改回") { edit.confirmRevert(a) }
            Button("取消", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        case .duplicate(let a):
            Button(MacEditPolicy.duplicateButton) { edit.confirmDuplicate(a) }
                .keyboardShortcut(.defaultAction)
            Button("取消", role: .cancel) {}
        }
    }
}

private struct MacEditorTopBars: View {
    @ObservedObject var edit: MacEditCenter

    var body: some View {
        VStack(spacing: 0) {
            MacDebugBar()
            if !edit.watchdogItems.isEmpty {
                MacWatchdogBanner(edit: edit)
            }
        }
    }
}

private struct MacDebugBar: View {
    var body: some View {
        #if DEBUG
        Text("這是 Xcode 版，改的是你真正的資料")
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(Color.red)
        #else
        EmptyView()
        #endif
    }
}

private struct MacWatchdogBanner: View {
    @ObservedObject var edit: MacEditCenter
    @State var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MacWatchdogHeader(edit: edit, expanded: $expanded)
            if expanded {
                ForEach(edit.watchdogItems) { item in
                    MacWatchdogRow(item: item, edit: edit)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.18))
    }
}

private struct MacWatchdogHeader: View {
    @ObservedObject var edit: MacEditCenter
    @Binding var expanded: Bool

    private var toggleTitle: String {
        expanded ? "收起來" : "看一下"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("你在電腦改的 \(edit.watchdogItems.count) 筆被另一台用舊資料蓋回去了")
            Spacer()
            Button(toggleTitle) { expanded.toggle() }
            Button("補回") { edit.restore(edit.watchdogItems) }
                .disabled(!edit.writeEnabled || edit.isBusy)
            Button("不用了") { edit.dismissWatchdog() }
        }
    }
}

private struct MacWatchdogRow: View {
    let item: MacWatchdogItem
    let edit: MacEditCenter

    /// 目前這一頁看不到那筆就先換到總覽（換頁會清選取），再選
    private func select(_ ref: MacEntryRef) {
        let ui = edit.ui
        // [review mac3 select-1] 變動支出頁有搜尋字或篩選時那列可能不在表上（守門會清掉選取）→ 一律回總覽再選
        if !ui.page.shows(ref) || ui.page == .variable { ui.page = .overview }
        ui.selection = ref
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(item.text)
                .font(.callout)
            Spacer()
            if let ref = MacEditCenter.ref(key: item.entry.key, itemID: item.entry.itemID), item.reason != .addMissing {
                Button("選這筆") { select(ref) }
                    .buttonStyle(.borderless)
            }
        }
    }
}

private struct MacEditStatusBar: View {
    @ObservedObject var edit: MacEditCenter

    var body: some View {
        if let s = edit.status {
            MacEditStatusCapsule(status: s, edit: edit)
                .padding(.bottom, 10)
        }
    }
}

private struct MacEditStatusCapsule: View {
    let status: MacEditStatus
    let edit: MacEditCenter

    var body: some View {
        HStack(spacing: 8) {
            if status.isProgress {
                ProgressView()
                    .controlSize(.small)
            }
            Text(status.text)
                .font(.callout)
                .foregroundStyle(status.isError ? Color.red : Color.primary)
            if let entryID = status.undoEntryID {
                Button("復原") { edit.undoFromStatus(entryID) }
            }
            Button { edit.clearStatus() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }
}

// MARK: - 表單 sheet

private struct MacEditorSheet: View {
    let request: MacEditorRequest
    @EnvironmentObject private var edit: MacEditCenter
    @EnvironmentObject private var money: MacMoneyStore
    @Environment(\.dismiss) private var dismiss
    @State private var isIncome: Bool
    @State private var draft: MacEntryRules.Draft
    @State private var errorText: String?
    @State private var saving = false
    @State private var ask: MacFormAsk?
    /// 新的一筆：id、時間在這張表單開著的期間固定。存失敗（離線、讀不回來）但其實已經寫進去時，
    /// 再按一次存＝同一個 id（合併當成同一筆），不會在 iCloud 多一筆
    @State private var newEntryID = UUID()
    @State private var newEntryStamp: Date?
    @FocusState private var amountFocused: Bool

    init(request: MacEditorRequest) {
        self.request = request
        _isIncome = State(initialValue: request.startsWithIncome)
        _draft = State(initialValue: request.draft)
    }

    var body: some View {
        VStack(spacing: 0) {
            MacEditorFields(request: request, isIncome: $isIncome, draft: $draft, amountFocused: $amountFocused)
                .disabled(saving)
            Divider()
            MacEditorFooter(errorText: errorText, offline: money.isOffline, saving: saving,
                            phase: edit.phase, canSave: edit.writeEnabled, cancel: cancel, save: save)
        }
        .frame(minWidth: 460, idealWidth: 500, minHeight: 440)
        .modifier(MacFormAskDialog(ask: $ask, run: run))
        .onAppear {
            DispatchQueue.main.async { amountFocused = true }
        }
    }

    private func cancel() {
        dismiss()
    }

    private func save() {
        errorText = nil
        switch prepare() {
        case .job(let job):
            run(job, .askFirst)
        case .nothing:
            dismiss()
        case .error(let message):
            errorText = message
        }
    }

    private enum Prepared {
        case job(MacWriteJob)
        case nothing
        case error(String)
    }

    private func prepare() -> Prepared {
        if money.isOffline { return .error("離線中，連上網路再存") }
        switch request.original {
        case .newEntry:
            return prepareNew()
        case .expense(let e):
            let r = MacEntryRules.expenseChanges(original: e, draft: draft, verdict: request.verdict)
            return prepareEdit(changes: r.changes, error: r.error)
        case .income(let i):
            let r = MacEntryRules.incomeChanges(original: i, draft: draft, verdict: request.verdict)
            return prepareEdit(changes: r.changes, error: r.error)
        }
    }

    private func prepareNew() -> Prepared {
        let key = isIncome ? LedgerMerge.incomesKey : LedgerMerge.expensesKey
        guard let base = request.bases[key] else { return .error("iCloud 上還沒有這份資料，先在 iPhone 打開 iCloud 同步") }
        let made: (raw: [String: Any]?, error: String?)
        let category: String
        let stamp = newEntryStamp ?? Date()
        newEntryStamp = stamp
        if isIncome {
            made = Self.makeIncome(draft, id: newEntryID, now: stamp)
            category = draft.incomeCategory.rawValue
        } else {
            made = MacEntryRules.newExpense(title: draft.title, amountText: draft.amountText, day: draft.day,
                                            category: draft.expenseCategory, note: draft.note, id: newEntryID, now: stamp)
            category = draft.expenseCategory.rawValue
        }
        guard let raw = made.raw else { return .error(made.error ?? MacEntryRules.amountError) }
        let ref = MacEditCenter.ref(key: key, itemID: (raw["id"] as? String) ?? "")
        return .job(MacWriteJob(key: key, action: .add(raw: raw), base: base, purpose: .form(isNew: true), ref: ref,
                                rememberCategory: category))
    }

    /// 新記收入：薪水看「固定薪水」（開＝每月、關＝單次），其餘照選的週期；結束日只在薪水＋固定薪水＋開關開時交
    private static func makeIncome(_ draft: MacEntryRules.Draft, id: UUID, now: Date) -> (raw: [String: Any]?, error: String?) {
        let isSalary = draft.incomeCategory == .salary
        let period: IncomePeriod = isSalary ? (draft.isFixedSalary ? .monthly : .once) : draft.period
        let end: (day: Date, reason: SalaryEndReason)? =
            (isSalary && draft.isFixedSalary && draft.end.enabled) ? (day: draft.end.day, reason: draft.end.reason) : nil
        return MacEntryRules.newIncome(title: draft.title, amountText: draft.amountText, day: draft.day,
                                       category: draft.incomeCategory, note: draft.note, period: period,
                                       isFixedSalary: draft.isFixedSalary, end: end, id: id, now: now)
    }

    private func prepareEdit(changes: [String: Any?], error: String?) -> Prepared {
        if let error { return .error(error) }
        if changes.isEmpty { return .nothing }
        guard let ref = request.ref else { return .error("找不到這一筆") }
        let key = MacEditCenter.key(of: ref)
        guard let base = request.bases[key] else { return .error("找不到這一筆") }
        let id = MacEditCenter.uuid(of: ref).uuidString
        let itemID = Self.itemID(in: base, matching: id)
        return .job(MacWriteJob(key: key, action: .edit(id: itemID, changes: changes), base: base,
                                purpose: .form(isNew: false), ref: ref, rememberCategory: nil))
    }

    /// 原字典裡的 id 字串（JSONEncoder 寫的是大寫；舊資料若是小寫也找得到）
    private static func itemID(in base: Data, matching id: String) -> String {
        guard let arr = LedgerMerge.parseArray(base) else { return id }
        let pos = LedgerMerge.index(arr).pos
        if pos[id] != nil { return id }
        return pos.keys.first { k in k.caseInsensitiveCompare(id) == .orderedSame } ?? id
    }

    private func run(_ job: MacWriteJob, _ resolution: MacConflictResolution) {
        saving = true
        Task { @MainActor in
            let (outcome, entry) = await edit.submit(job, resolution: resolution)
            saving = false
            handle(outcome, entry: entry, job: job)
        }
    }

    private func handle(_ outcome: MacWriteOutcome, entry: MacJournalEntry?, job: MacWriteJob) {
        switch outcome {
        case .saved, .nothingToWrite:
            let center = edit
            dismiss()
            DispatchQueue.main.async {
                center.finish(job, outcome: outcome, entry: entry)
            }
        case .needsDecision(let conflicts):
            ask = .conflict(MacConflictAsk(conflicts: conflicts, job: job))
        case .goneElsewhere:
            if case .edit(let id, let changes) = job.action,
               let raw = MacEntryRules.detachedCopy(base: job.base, id: id, changes: changes) {
                // [v25.642 mac3 裁定] 一按就記、有金額歷史的支出：另存那筆 post3#A3 一定擋 → 先不給〔另存〕，不會按了才失敗
                guard MacEditCenter.detachedCopyPasses(key: job.key, raw: raw) else {
                    errorText = "這筆在另一台已經刪掉了，而且是一按就記或改過金額的那種，請在 iPhone 重記一筆"
                    return
                }
                let ref = MacEditCenter.ref(key: job.key, itemID: (raw["id"] as? String) ?? "")
                let copy = MacWriteJob(key: job.key, action: .add(raw: raw), base: job.base,
                                       purpose: .form(isNew: true), ref: ref, rememberCategory: nil)
                ask = .gone(copy)
            } else {
                errorText = "這筆在另一台已經刪掉了，而且連著別的資料（銀行、卡、旅行、照片等），請在 iPhone 處理"
            }
        default:
            errorText = MacEditCenter.text(for: outcome)
        }
    }
}

/// 表單裡的確認框：iPhone 剛改了這筆／這筆在另一台刪掉了
private enum MacFormAsk {
    case conflict(MacConflictAsk)
    /// 〔另存成新的一筆〕要寫的那一筆
    case gone(MacWriteJob)

    var title: String {
        switch self {
        case .conflict: return "iPhone 剛改了這筆"
        case .gone: return "這筆在另一台刪掉了"
        }
    }

    var message: String {
        switch self {
        case .conflict(let a): return a.message
        case .gone: return "要把你填的另存成新的一筆嗎？不會把刪掉的那筆悄悄寫回去。"
        }
    }
}

private struct MacFormAskDialog: ViewModifier {
    @Binding var ask: MacFormAsk?
    let run: @MainActor (MacWriteJob, MacConflictResolution) -> Void

    private var isPresented: Binding<Bool> {
        Binding(get: { ask != nil }, set: { shown in if !shown { ask = nil } })
    }

    func body(content: Content) -> some View {
        content.confirmationDialog(ask?.title ?? "", isPresented: isPresented, titleVisibility: .visible,
                                   presenting: ask) { a in
            MacFormAskButtons(ask: a, run: run)
        } message: { a in
            Text(a.message)
        }
    }
}

private struct MacFormAskButtons: View {
    let ask: MacFormAsk
    let run: @MainActor (MacWriteJob, MacConflictResolution) -> Void

    var body: some View {
        switch ask {
        case .conflict(let a):
            Button("用我填的") { later(a.job, .mine) }
            Button("用 iPhone 的") { later(a.job, .theirs) }
            Button("取消", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        case .gone(let job):
            Button("另存成新的一筆") { later(job, .askFirst) }
            Button("取消", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        }
    }

    /// 確認框收起來之後才寫
    private func later(_ job: MacWriteJob, _ resolution: MacConflictResolution) {
        let go = run
        DispatchQueue.main.async { go(job, resolution) }
    }
}

private struct MacEditorFields: View {
    let request: MacEditorRequest
    @Binding var isIncome: Bool
    @Binding var draft: MacEntryRules.Draft
    var amountFocused: FocusState<Bool>.Binding

    private var verdict: MacEditVerdict { request.verdict }

    var body: some View {
        Form {
            if request.isNew {
                Section {
                    MacKindPicker(isIncome: $isIncome)
                }
            }
            Section {
                MacLockableRow(reason: verdict.reason(.amount)) {
                    TextField("金額", text: $draft.amountText, prompt: Text("NT$"))
                        .focused(amountFocused)
                }
                MacLockableRow(reason: verdict.reason(.title)) {
                    TextField("名稱", text: $draft.title, prompt: Text("留空＝用分類名稱"))
                }
                MacEditorCategoryField(isIncome: isIncome, draft: $draft, reason: verdict.reason(.category),
                                       lockedName: lockedCategoryName, incomeChoices: incomeChoices)
                if isIncome {
                    MacIncomePeriodField(isNew: request.isNew, draft: $draft, original: originalIncome)
                }
                MacLockableRow(reason: verdict.reason(.date)) {
                    DatePicker(dateTitle, selection: $draft.day, displayedComponents: .date)
                }
                if isIncome {
                    MacIncomeEndField(isNew: request.isNew, draft: $draft, start: draft.day,
                                      reason: verdict.reason(.endDate), original: originalIncome)
                }
                LabeledContent("付款方式") {
                    Text(request.payment)
                        .foregroundStyle(.secondary)
                }
                MacLockableRow(reason: verdict.reason(.note)) {
                    MacNoteEditor(note: $draft.note)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// 改的是哪一筆收入（新的一筆、支出＝nil）
    private var originalIncome: Income? {
        if case .income(let i) = request.original { return i }
        return nil
    }

    /// 週期收入、新記的週期收入或固定薪水：日期叫「開始日」
    private var dateTitle: String {
        guard isIncome else { return "日期" }
        if let i = originalIncome { return i.period == .once ? "日期" : "開始日" }
        guard request.isNew else { return "日期" }
        if draft.incomeCategory == .salary { return draft.isFixedSalary ? "開始日" : "日期" }
        return draft.period == .once ? "日期" : "開始日"
    }

    /// 收入分類選單：改既有的週期收入只列獎金、禮金、確幸；其餘照 Mac 1 四類
    private var incomeChoices: [IncomeCategory] {
        if let i = originalIncome, i.period != .once { return MacEditPolicy.recurringIncomeCategories }
        return MacEditPolicy.incomeCategories
    }

    /// 分類鎖住時顯示原本的分類名稱
    private var lockedCategoryName: String {
        switch request.original {
        case .newEntry: return ""
        case .expense(let e): return e.categoryName
        case .income(let i): return i.category.rawValue
        }
    }
}

private struct MacKindPicker: View {
    @Binding var isIncome: Bool

    var body: some View {
        Picker("記", selection: $isIncome) {
            Text("支出").tag(false)
            Text("收入").tag(true)
        }
        .pickerStyle(.segmented)
    }
}

private struct MacEditorCategoryField: View {
    let isIncome: Bool
    @Binding var draft: MacEntryRules.Draft
    let reason: String?
    let lockedName: String
    let incomeChoices: [IncomeCategory]

    var body: some View {
        if let reason {
            LabeledContent("分類") {
                MacLockedValue(text: lockedName, reason: reason)
            }
        } else if isIncome {
            Picker("分類", selection: $draft.incomeCategory) {
                ForEach(incomeChoices, id: \.self) { c in
                    Text(c.rawValue).tag(c)
                }
            }
        } else {
            Picker("分類", selection: $draft.expenseCategory) {
                ForEach(MacEditPolicy.eightCategories, id: \.self) { c in
                    Text(c.rawValue).tag(c)
                }
            }
        }
    }
}

private struct MacLockedValue: View {
    let text: String
    let reason: String

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .foregroundStyle(.secondary)
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
        }
        .help(reason)
    }
}

private struct MacNoteEditor: View {
    @Binding var note: String

    var body: some View {
        LabeledContent("備註") {
            TextEditor(text: $note)
                .font(.body)
                .frame(minHeight: 60, maxHeight: 120)
        }
    }
}

/// 鎖住的欄位：反灰＋鎖頭＋滑過去顯示原因
private struct MacLockableRow<Content: View>: View {
    let reason: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 6) {
            content()
                .disabled(reason != nil)
            if reason != nil {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .help(reason ?? "")
    }
}

private struct MacEditorFooter: View {
    let errorText: String?
    let offline: Bool
    let saving: Bool
    let phase: MacWritePhase?
    let canSave: Bool
    let cancel: @MainActor () -> Void
    let save: @MainActor () -> Void

    private var saveTitle: String {
        guard saving else { return "存" }
        return phase == .saving ? "存到 iCloud…" : "取得 iCloud 最新資料…"
    }

    private var note: String? {
        if let errorText { return errorText }
        if offline { return "離線中" }
        return nil
    }

    var body: some View {
        HStack(spacing: 10) {
            if let note {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(Color.red)
                    .lineLimit(3)
            }
            Spacer()
            MacSaveShortcut(disabled: saving || offline || !canSave, save: save)
            Button("取消", role: .cancel) { cancel() }
                .keyboardShortcut(.cancelAction)
                .disabled(saving)
            Button(saveTitle) { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(saving || offline || !canSave)
        }
        .padding(14)
    }
}

/// ⌘S（看不見；Return 是〔存〕本身的 .defaultAction，備註欄裡 Return 是換行）
private struct MacSaveShortcut: View {
    let disabled: Bool
    let save: @MainActor () -> Void

    var body: some View {
        Button("存") { save() }
            .keyboardShortcut("s")
            .disabled(disabled)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }
}

// MARK: - 資料來源頁：寫入開關、自我檢查、最近在電腦改的、備份

struct MacWriteSettingsSection: View {
    @EnvironmentObject private var edit: MacEditCenter
    @EnvironmentObject private var journal: MacJournal
    @EnvironmentObject private var app: MacAppModel
    @State private var askEnable = false
    @State private var pickBackup: MacBackupFile?

    init() {}

    private var toggle: Binding<Bool> {
        Binding(get: { journal.writeEnabled }, set: { on in
            if on {
                askEnable = true
            } else {
                journal.setWriteEnabled(false)
            }
        })
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                MacWriteToggleRow(toggle: toggle, canEnable: edit.canEnableWrites, lockText: edit.writeLockText,
                                  isOn: journal.writeEnabled)
                MacGoldenRow(report: journal.golden)
                Divider()
                MacRecentEditsList(edit: edit, entries: journal.recentEntries())
                Divider()
                MacBackupList(backups: journal.backups, pick: $pickBackup)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        } label: {
            Text("在電腦改")
        }
        .confirmationDialog("iPhone、iPad 都已更新到 25.640 以上了嗎？", isPresented: $askEnable,
                            titleVisibility: .visible) {
            Button("都更新了，打開") { enableLater() }
            Button("取消", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: {
            Text("還沒更新的那台存檔時，可能把電腦改的蓋回去。")
        }
        .sheet(item: $pickBackup) { file in
            MacBackupPickerSheet(file: file).macStores(app)
        }
    }

    private func enableLater() {
        let j = journal
        DispatchQueue.main.async { j.setWriteEnabled(true) }
    }
}

private struct MacWriteToggleRow: View {
    let toggle: Binding<Bool>
    let canEnable: Bool
    let lockText: String
    let isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("允許這台 Mac 修改", isOn: toggle)
                .disabled(!canEnable && !isOn)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var caption: String {
        if !canEnable { return "第一次從 iCloud 讀到資料、自我檢查全過之後才能打開。" }
        if isOn { return "這台 Mac 改的會寫回 iCloud，iPhone、iPad 也會看到。" }
        return lockText
    }
}

private struct MacGoldenRow: View {
    let report: LedgerMergeGolden.Report

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: report.allPassed ? "checkmark.seal.fill" : "xmark.octagon.fill")
                .foregroundStyle(report.allPassed ? Color.green : Color.red)
            Text(text)
        }
    }

    private var text: String {
        if report.allPassed { return "自我檢查 \(report.passed)/\(report.total) 通過" }
        return "自我檢查 \(report.passed)/\(report.total)，沒全過，這台 Mac 先不能改"
    }
}

private struct MacRecentEditsList: View {
    @ObservedObject var edit: MacEditCenter
    let entries: [MacJournalEntry]

    private var flagged: Set<String> {
        Set(edit.watchdogItems.map { item in item.entry.id })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("最近在電腦改的（\(MacJournal.recentDays) 天）")
                .font(.headline)
            if entries.isEmpty {
                Text("這 \(MacJournal.recentDays) 天沒有在電腦改過")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { e in
                    MacRecentEntryRow(entry: e, flagged: flagged.contains(e.id), edit: edit)
                }
            }
        }
    }
}

private struct MacRecentEntryRow: View {
    let entry: MacJournalEntry
    let flagged: Bool
    @ObservedObject var edit: MacEditCenter

    private var caption: String {
        let kind: String
        switch entry.kind {
        case .add: kind = "記一筆"
        case .edit: kind = "修改"
        case .delete: kind = "刪除"
        }
        let c = Calendar.current.dateComponents([.month, .day], from: entry.at)
        return "\(kind)・\(c.month ?? 0)/\(c.day ?? 0) \(MacEditCenter.clock(entry.at))"
            + (flagged ? "・被另一台蓋回去了" : "")
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.label)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(flagged ? Color.orange : Color.secondary)
            }
            Spacer()
            MacRecentEntryButton(entryID: entry.id, flagged: flagged, edit: edit)
        }
    }
}

private struct MacRecentEntryButton: View {
    let entryID: String
    let flagged: Bool
    @ObservedObject var edit: MacEditCenter

    var body: some View {
        if flagged {
            Button("補回") { edit.restoreEntry(entryID) }
                .disabled(!edit.writeEnabled || edit.isBusy)
        } else {
            Button("改回") { edit.revertEntry(entryID) }
                .disabled(!edit.writeEnabled || edit.isBusy)
        }
    }
}

private struct MacBackupList: View {
    let backups: [MacBackupFile]
    @Binding var pick: MacBackupFile?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("寫前備份（\(MacJournal.backupDays) 天）")
                .font(.headline)
            if backups.isEmpty {
                Text("還沒有備份：電腦每次存之前會先留一份")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(backups) { b in
                    MacBackupRowView(file: b, pick: $pick)
                }
            }
        }
    }
}

private struct MacBackupRowView: View {
    let file: MacBackupFile
    @Binding var pick: MacBackupFile?

    private var title: String {
        let c = Calendar.current.dateComponents([.month, .day], from: file.at)
        return "\(file.keyName)・\(c.month ?? 0)/\(c.day ?? 0) \(MacEditCenter.clock(file.at))"
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button("挑一筆加回…") { pick = file }
        }
    }
}

/// 從備份挑一筆加回（只列 iCloud 上已經沒有的那幾筆；不整包還原）
private struct MacBackupItem: Identifiable {
    let id: String
    let label: String
    let raw: [String: Any]
}

private struct MacBackupPickerSheet: View {
    let file: MacBackupFile
    @EnvironmentObject private var edit: MacEditCenter
    @EnvironmentObject private var journal: MacJournal
    @EnvironmentObject private var money: MacMoneyStore
    @Environment(\.dismiss) private var dismiss
    @State private var items: [MacBackupItem] = []
    @State private var loaded = false

    init(file: MacBackupFile) {
        self.file = file
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("從備份加回一筆（\(file.keyName)）")
                .font(.headline)
            MacBackupItemsList(items: items, loaded: loaded, canAdd: edit.writeEnabled, add: add)
            HStack {
                Spacer()
                Button("關閉", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 360)
        .onAppear { load() }
    }

    private func load() {
        guard !loaded else { return }
        items = Self.missingItems(backup: journal.loadBackup(file), current: money.records[file.key]?.data)
        loaded = true
    }

    private static func missingItems(backup: Data?, current: Data?) -> [MacBackupItem] {
        guard let backup, let arr = LedgerMerge.parseArray(backup) else { return [] }
        var have = Set<String>()
        if let current, let now = LedgerMerge.parseArray(current) {
            let idx = LedgerMerge.index(now)
            have = Set(idx.pos.keys).union(idx.dup)
        }
        var out: [MacBackupItem] = []
        var seen = Set<String>()
        for element in arr {
            guard let d = element as? [String: Any], let id = d["id"] as? String,
                  !have.contains(id), !seen.contains(id) else { continue }
            seen.insert(id)
            out.append(MacBackupItem(id: id, label: MacEntryRules.label(raw: d), raw: d))
        }
        return out
    }

    private func add(_ item: MacBackupItem) {
        let center = edit
        let key = file.key
        dismiss()
        DispatchQueue.main.async { center.addBack(raw: item.raw, key: key) }
    }
}

private struct MacBackupItemsList: View {
    let items: [MacBackupItem]
    let loaded: Bool
    let canAdd: Bool
    let add: @MainActor (MacBackupItem) -> Void

    var body: some View {
        if loaded && items.isEmpty {
            Text("這份備份裡的每一筆，iCloud 上都還在。")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            List(items) { item in
                HStack {
                    Text(item.label)
                    Spacer()
                    Button("加回") { add(item) }
                        .disabled(!canAdd)
                }
            }
        }
    }
}

// MARK: - 詳情欄：每欄能不能改＋原因、〔編輯〕〔刪除〕

struct MacInspectorEditSection: View {
    let ref: MacEntryRef
    @EnvironmentObject private var edit: MacEditCenter

    /// 選到的是收入：那一筆（支出＝nil）
    private var income: Income? {
        if case .income(let id) = ref { return edit.money.income(id) }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("在電腦改")
                .font(.headline)
            if let v = edit.verdict(ref) {
                MacFieldLockList(verdict: v, fields: MacEditField.fields(for: ref, income: income),
                                 recurring: (income?.period ?? .once) != .once)
            } else {
                Text("找不到這一筆")
                    .foregroundStyle(.secondary)
            }
            MacInspectorButtons(ref: ref, edit: edit)
            if isExpense {
                // [v25.642 mac3] 這幾欄電腦只能看（hint_iphone_only）
                Text(MacEditPolicy.hintIPhoneOnly)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isExpense: Bool {
        if case .expense = ref { return true }
        return false
    }
}

private struct MacFieldLockList: View {
    let verdict: MacEditVerdict
    /// MacEditField.fields(for:income:)：週期收入多結束日
    let fields: [MacEditField]
    /// 週期收入：多一列「週期、固定薪水開關請在 iPhone 改」
    let recurring: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let lock = verdict.lock {
                Label(lock, systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            } else {
                MacFieldLockRows(verdict: verdict, fields: fields, recurring: recurring)
            }
        }
        .font(.callout)
    }
}

private struct MacFieldLockRows: View {
    let verdict: MacEditVerdict
    let fields: [MacEditField]
    let recurring: Bool

    var body: some View {
        ForEach(fields, id: \.self) { f in
            MacFieldLockRow(field: f, reason: verdict.reason(f))
        }
        if recurring {
            Label(MacEditPolicy.reasonIncomePeriod, systemImage: "lock.fill")
                .foregroundStyle(.secondary)
        }
    }
}

private struct MacFieldLockRow: View {
    let field: MacEditField
    let reason: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(field.label)
                .frame(width: 48, alignment: .leading)
            if let reason {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                Text(reason)
                    .foregroundStyle(.secondary)
            } else {
                Text("可以改")
            }
        }
    }
}

private struct MacInspectorButtons: View {
    let ref: MacEntryRef
    @ObservedObject var edit: MacEditCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button("編輯") { edit.requestEdit(ref) }
                    .disabled(!edit.canEdit(ref))
                if isExpense {
                    Button("複製成新的一筆") { edit.requestDuplicate(ref) }
                        .disabled(!edit.canDuplicate(ref))
                }
                Button("刪除", role: .destructive) { edit.requestDelete(ref) }
                    .disabled(!edit.canDelete(ref))
            }
            MacInspectorHint(text: hint)
        }
    }

    private var isExpense: Bool {
        if case .expense = ref { return true }
        return false
    }

    private var hint: String? {
        if !edit.writeEnabled { return edit.writeLockText }
        guard let v = edit.verdict(ref), v.lock == nil else { return nil }
        var lines: [String] = []
        if let r = edit.deleteReason(ref) { lines.append("不能刪：\(r)") }
        if isExpense, let r = edit.duplicateReason(ref) { lines.append("不能複製：\(r)") }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

private struct MacInspectorHint: View {
    let text: String?

    var body: some View {
        if let text, !text.isEmpty {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
