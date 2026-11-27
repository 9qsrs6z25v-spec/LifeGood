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
// [v25.644 mac4 G1] judge_mac §R4～§R6（sim_mac4.py edit_field4／gate4／policy_block4／post_check4／own_add／delete_gate_for／
// can_stop／open_draft；sim4 編號 field4#、gate4#、post4#、own4#、stop4#、write4#4、journal4#3、entry4#3）：固定支出可改
// （表單固定模式、〔從今天起〕詢問框、〔停止扣款…〕）、editField 分類型（W4-1）、gate 多看新欄位值與 iPhone 剛改的金額（gate4#2）、
// postCheck P5～P8／A0／A3F、刪除只開這次開 App 電腦記的那筆（launchedAt＋ownAdd＋deleteGate）、看門狗〔補回〕照組。
// [v25.646 mac6 G1] judge_mac §T4-5、§T4-8（sim_mac6.py split6#23～#30）：檔尾誰還欠我的 4 支入口（標已還、改成還沒還）＋submitSplit／
// finishSplit；⌘Z／⌘⇧Z／〔改回〕／〔補回〕開頭分帳分流（收支那條一字不改）；ref(key:itemID:) 不認分帳；看門狗列〔看一下〕；
// 分帳自我檢查列；分帳備份不給〔挑一筆加回…〕。復原名稱只「標已還」「改成還沒還」；名字不進日誌、復原名稱、狀態列。
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
    /// [v25.644 mac4] 表單新記固定支出（A3F 只認這個旗標；var＋預設值：合成的 init 多一個可省的參數）
    var fixedForm: Bool = false
    /// [v25.644 mac4] 詢問框選的〔從今天起〕（P5 用同一個 cutoff、firstID、newID 重算）
    var amountPick: MacAmountPick? = nil
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
    /// [v25.644 mac4] 〔停止扣款…〕開的（只影響停止區的初值，R14）
    var startWithStop: Bool = false
    /// [v25.644 mac4] 固定支出頁 ⌘N：新記預設〔固定〕（只影響表單初值）
    var startsFixed: Bool = false

    var isNew: Bool { ref == nil }
}

/// [v25.644 mac4] editField 照那筆的類型挑對照（W4-1）
enum MacEntryKind { case income, variable, fixed }

struct MacDeleteAsk {
    let ref: MacEntryRef
    let key: String
    let itemID: String
    let label: String
    /// 週期收入（確認框多一句「每個月的收入統計都會少掉這筆。」）
    let recurring: Bool
    /// [v25.644 mac4] 這次開 App 電腦剛記的固定支出（確認框多一句 fixed_delete_own）
    var ownFixed: Bool = false
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
    /// [v25.644 mac4] 這次開 App 的時間（實例屬性，init 時就定；不用 static：static 第一次被讀到才初始化）。
    /// 固定支出只准刪這個時間之後電腦自己記、iPhone 沒碰過的那筆（W4-13）
    let launchedAt = Date()
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
            if e.expenseType == .fixed { return fixedDeleteReason(e) }
            return MacEditPolicy.expenseDeleteReason(e, rawEditable: rawEditable(LedgerMerge.expensesKey, id),
                                                     links: cachedLinks())
        case .income(let id):
            guard let i = money.income(id) else { return "找不到這一筆" }
            return MacEditPolicy.incomeDeleteReason(i, rawEditable: rawEditable(LedgerMerge.incomesKey, id))
        }
    }

    /// 固定支出：整筆鎖 → 那個字；這次開 App 電腦記的、雲端跟電腦寫的一模一樣 → 照 Mac 1 查照片、分帳、細項紀錄；其餘 fixed_delete
    private func fixedDeleteReason(_ e: Expense) -> String? {
        // sim4: del4#1（MacEditPolicy.expenseDeleteReason 固定那支只回整筆鎖或 fixed_delete；例外在這裡先判）
        let links = cachedLinks()
        let v = MacEditPolicy.expense(e, rawEditable: rawEditable(LedgerMerge.expensesKey, e.id), links: links)
        if let lock = v.lock { return lock }
        guard ownAddSame(e.id) else { return MacEditPolicy.reasonFixedDelete }
        if !e.photoFileNames.isEmpty { return MacEditPolicy.reasonPhoto }
        let upper = e.id.uuidString.uppercased()
        if links.splitRecordIDs.contains(upper) { return MacEditPolicy.reasonSplitRecord }
        if links.kindRecordIDs.contains(upper) { return MacEditPolicy.reasonKindRecord }
        return nil
    }

    /// 日誌裡這次開 App（at ≥ launchedAt）電腦記的、還沒結的那一筆新增（同 id 取最後一筆）— sim4: own4#1
    func ownAdd(_ id: String) -> MacJournalEntry? {
        // sim4: own4#1
        journal.entries.last { e in
            e.key == LedgerMerge.expensesKey && e.kind == .add && !e.resolved && e.itemID == id && e.at >= launchedAt
        }
    }

    /// 快取裡那筆跟 ownAdd 的 rawAfter 一模一樣（iPhone 沒碰過）
    private func ownAddSame(_ id: UUID) -> Bool {
        guard let raw = money.rawEntry(key: LedgerMerge.expensesKey, id: id), let rid = raw["id"] as? String,
              let after = ownAdd(rid)?.rawAfter else { return false }
        return LedgerMerge.same(raw, after)
    }

    /// W4-13：Writer 刪除前拿剛抓到那筆再比一次（支出那包的刪除一律給；剛抓到那筆是固定支出才看，變動支出照舊放行）
    private func deleteGateFor(_ job: MacWriteJob) -> (@MainActor ([String: Any]) -> String?)? {
        guard job.key == LedgerMerge.expensesKey, case .delete(let id) = job.action else { return nil }
        let after = ownAdd(id)?.rawAfter
        return { item in
            guard (item["expenseType"] as? String) == ExpenseType.fixed.rawValue else { return nil }
            if let after, LedgerMerge.same(item, after) { return nil }
            return MacEditPolicy.reasonFixedDelete
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
    func requestStop(_ ref: MacEntryRef) {
        // sim4: stop4#1 同 requestEdit，只是 startWithStop（停止區初值打開；originalFixedEnd 不變）
        guard writeEnabled else { show(writeLockText, isError: true); return }
        guard let v = verdict(ref) else { show("找不到這一筆", isError: true); return }
        if let lock = v.lock { show(lock, isError: true); return }
        guard canStop(ref) else {
            guard case .expense(let id) = ref, money.expense(id)?.expenseType == .fixed else {
                show("只有固定支出能設停止扣款", isError: true)
                return
            }
            show(v.reason(.endDate) ?? MacEditPolicy.reasonFixedEndReopen, isError: true)
            return
        }
        openEdit(ref, startWithStop: true)
    }

    /// 選單、右鍵、詳情鈕反灰用：canEdit 而且停止那欄能改、不是「原本停在以前」— sim4: stop4#2
    func canStop(_ ref: MacEntryRef) -> Bool {
        // sim4: stop4#2
        guard writeEnabled, case .expense(let id) = ref, let e = money.expense(id), e.expenseType == .fixed,
              let v = verdict(ref), v.lock == nil, v.canEdit(.endDate) else { return false }
        return !MacEntryRules.fixedEndClosedPast(e, now: Date())
    }

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
        var draft = MacEntryRules.Draft(title: "", amountText: "", day: Date(),
                                        expenseCategory: Self.lastExpenseCategory(),
                                        incomeCategory: Self.lastIncomeCategory(), note: "",
                                        period: .once, isFixedSalary: true)
        // [v25.644 mac4] 固定支出頁 ⌘N：預設〔固定〕；分類房租、每月、今天（Draft 預設值，照 iPhone）
        let startsFixed = !income && ui.page == .fixed
        draft.fixedMode = startsFixed
        clearStatus()
        sheet = MacEditorRequest(ref: nil, startsWithIncome: income, bases: bases, original: .newEntry, draft: draft,
                                 verdict: MacEditVerdict(lock: nil, fieldReasons: [:]), payment: "不指定",
                                 startsFixed: startsFixed)
    }

    func requestEdit(_ ref: MacEntryRef) {
        guard writeEnabled else { show(writeLockText, isError: true); return }
        guard let v = verdict(ref) else { show("找不到這一筆", isError: true); return }
        if let lock = v.lock { show(lock, isError: true); return }
        openEdit(ref, startWithStop: false)
    }

    /// 先重抓再開表單（requestEdit、requestStop 共用）
    private func openEdit(_ ref: MacEntryRef, startWithStop: Bool) {
        guard sheet == nil, !isOpening else { return }
        isOpening = true
        show("取得 iCloud 最新資料…", progress: true)
        Task { [weak self] in
            guard let self else { return }
            await self.money.refresh()
            self.isOpening = false
            self.finishOpenEdit(ref, startWithStop: startWithStop)
        }
    }

    private func finishOpenEdit(_ ref: MacEntryRef, startWithStop: Bool) {
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
            request = Self.editRequest(expense: e, ref: ref, base: base, key: key, verdict: v, startWithStop: startWithStop)
        case .income:
            guard let i = money.income(id) else { show("這筆已經在另一台刪掉了", isError: true); return }
            request = Self.editRequest(income: i, ref: ref, base: base, key: key, verdict: v)
        }
        clearStatus()
        sheet = request
    }

    private static func editRequest(expense e: Expense, ref: MacEntryRef, base: Data, key: String,
                                    verdict: MacEditVerdict, startWithStop: Bool) -> MacEditorRequest {
        let text = MacEntryRules.amountText(e.amount)
        let cat = e.variableCategory ?? .other
        var draft = MacEntryRules.Draft(title: e.title, amountText: text, day: e.date, expenseCategory: cat,
                                        incomeCategory: .salary, note: e.note, originalAmountText: text)
        if e.expenseType == .fixed {
            fillFixed(&draft, e, startWithStop: startWithStop)
        }
        var payment = "不指定"
        if e.linkedCreditCardMilestoneId != nil {
            payment = "信用卡"
        } else if e.linkedBankMilestoneId != nil {
            payment = "銀行"
        }
        return MacEditorRequest(ref: ref, startsWithIncome: false, bases: [key: base], original: .expense(e),
                                draft: draft, verdict: verdict, payment: payment, startWithStop: startWithStop)
    }

    /// [v25.644 mac4] 固定支出那筆的表單初值：分類、週期、停止區（有停止日：開、那天、原因 ?? 取消訂閱；沒有：關、第一期那天）。
    /// 〔停止扣款…〕而且原本沒停：只把 fixedEnd 換成預設，originalFixedEnd 不動（R14：沒按存就不會寫）
    private static func fillFixed(_ draft: inout MacEntryRules.Draft, _ e: Expense, startWithStop: Bool) {
        draft.fixedMode = true
        draft.fixedCategory = e.fixedCategory ?? .rent
        draft.recurrence = e.recurrence ?? .monthly
        let original: MacFixedEndDraft
        if let end = e.endDate {
            original = MacFixedEndDraft(enabled: true, day: end, reason: e.endReason ?? .cancelled)
        } else {
            original = MacFixedEndDraft(enabled: false, day: e.date, reason: .cancelled)
        }
        draft.originalFixedEnd = original
        draft.fixedEnd = original
        // sim4: entry4#3
        if startWithStop && !original.enabled {
            draft.fixedEnd = MacEntryRules.fixedStopDefault(e, now: Date())
        }
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
        var ownFixed = false
        if case .expense = ref, let e = money.expense(id), e.expenseType == .fixed { ownFixed = ownAddSame(id) }
        hostAsk = .delete(MacDeleteAsk(ref: ref, key: key, itemID: itemID, label: MacEntryRules.label(raw: raw),
                                       recurring: recurring, ownFixed: ownFixed))
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
        // sim4: gate4#2 開表單那份（job.base）裡的那筆；W4-13 刪除那道 deleteGate
        let baseItem = MacCloudWriter.item(job.action.itemID, in: job.base)
        let dgate = deleteGateFor(job)
        let outcome = await writer.save(key: job.key, action: job.action, base: job.base, resolution: resolution,
                                        journal: journal, golden: journal.golden, writeEnabled: writeEnabled,
                                        gate: { [weak self] item, changes, fresh in
                                            self?.gateReason(key: key, item: item, changes: changes, fresh: fresh,
                                                             baseItem: baseItem)
                                        },
                                        postCheck: { action, fetched, merged, fresh in
                                            MacEditCenter.postReason(key: key, job: job, action: action,
                                                                     fetched: fetched, merged: merged, fresh: fresh)
                                        },
                                        deleteGate: dgate)
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
            let kind = entryKind(ref)
            for field in changes.keys.sorted() {
                // sim2: block#2（S4）對不到表單欄位的一律擋；sim4: field4#1 照那筆的類型挑對照（W4-1）
                guard let f = Self.editField(field, key: key, kind: kind) else { return MacEditPolicy.reasonFieldUnknown }
                if let reason = v.reason(f) { return reason }
                // sim2: catto#2 換分類看新值（復原、改回：那筆現在已是每月／每年就不准換成薪水）
                if field == "category", case .income(let id) = ref, let i = money.income(id),
                   let reason = MacEditPolicy.incomeCategoryChangeReason(i, to: changes[field] ?? nil) {
                    return reason
                }
                // sim3: block3#2 支出換分類看新值（字串、8 類；復原、改回、補回也一樣）
                // sim4: block4 固定支出新開放欄位的值（分類六類、週期、停止原因、金額歷史 8-B 對快取那筆）
                if case .expense(let id) = ref, let e = money.expense(id),
                   let reason = Self.expenseValueReason(field, changes[field] ?? nil, model: e,
                                                        fetched: money.rawEntry(key: key, id: id)) {
                    return reason
                }
            }
            return nil
        }
    }

    /// 快取那筆的類型（editField 用）
    private func entryKind(_ ref: MacEntryRef) -> MacEntryKind {
        switch ref {
        case .income: return .income
        case .expense(let id): return money.expense(id)?.expenseType == .fixed ? .fixed : .variable
        }
    }

    /// 原字典欄位名 → 表單欄位（W4-1：照那筆的類型；對不到＝nil＝擋）— sim4: field4#1
    /// 收入 title note amount date category endDate endReason；變動 title note amount date variableCategory；
    /// 固定 title note amount amountHistory(→金額) date recurrence fixedCategory(→分類) endDate endReason(→停止)
    private static func editField(_ raw: String, key: String, kind: MacEntryKind) -> MacEditField? {
        // sim4: field4#1（包跟類型對不上＝nil，只會多擋）
        if (kind == .income) != (key == LedgerMerge.incomesKey) { return nil }
        switch (kind, raw) {
        case (_, "title"): return .title
        case (_, "note"): return .note
        case (_, "amount"): return .amount
        case (_, "date"): return .date
        case (.income, "category"), (.variable, "variableCategory"), (.fixed, "fixedCategory"): return .category
        case (.income, "endDate"), (.income, "endReason"), (.fixed, "endDate"), (.fixed, "endReason"): return .endDate
        case (.fixed, "amountHistory"): return .amount
        case (.fixed, "recurrence"): return .recurrence
        default: return nil
        }
    }

    /// 支出新欄位的值檢查（gate 對剛抓到那筆、policyBlock 對快取那筆；回原因、不含前綴；sim4 value_check4）
    static func expenseValueReason(_ field: String, _ value: Any?, model e: Expense, fetched item: [String: Any]?) -> String? {
        switch field {
        case "variableCategory": return MacEditPolicy.expenseCategoryChangeReason(e, to: value)
        case "fixedCategory": return MacEditPolicy.fixedCategoryChangeReason(e, to: value)
        case "recurrence": return MacEditPolicy.recurrenceValueReason(value)
        case "endReason": return e.expenseType == .fixed ? MacEditPolicy.fixedEndReasonValueReason(value) : nil
        case "amountHistory": return MacEditPolicy.amountHistoryValueReason(value, fetched: item?["amountHistory"])
        default: return nil
        }
    }

    /// S1：MacCloudWriter 重抓之後交過來剛抓到的那筆原字典＋這次的改動；nil＝放行，否則「這筆剛在 iPhone 改過，現在…」
    /// （sim2 gate；值已經跟剛抓到的那筆一樣的欄位跳過：〔用 iPhone 的〕換成雲端值的那幾欄等於沒改）
    /// [v25.642 mac3] fresh＝MacCloudWriter ② 同一次抓到的分帳、細項（支出用；收入 fetched＝false 不看）
    /// [v25.644 mac4] baseItem＝開表單那份（job.base）裡的那筆（gate4#2：iPhone 在這中間改了金額或扣款日就擋）
    func gateReason(key: String, item: [String: Any], changes: [String: Any?], fresh: MacFreshLinks,
                    baseItem: [String: Any]?) -> String? {
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
            // sim3: gate3#1 用剛抓到的分帳、細項（不是快取）；sim4: gate4#1 固定支出看存的這一刻（Date()）
            verdict = MacEditPolicy.expense(e, rawEditable: rawOK, links: Self.links(fresh), now: Date())
            expense = e
        }
        // sim2: gate#4 現在整筆鎖
        if let lock = verdict.lock { return prefix + lock }
        let kind: MacEntryKind = income != nil ? .income : (expense?.expenseType == .fixed ? .fixed : .variable)
        // sim2: gate#5 每一欄（sim4: gate4#1 照剛抓到那筆的類型挑對照、新欄位驗值）
        for k in changes.keys.sorted() {
            let value: Any? = changes[k] ?? nil
            if LedgerMerge.same(item[k], value) { continue }
            guard let f = Self.editField(k, key: key, kind: kind) else { return prefix + MacEditPolicy.reasonFieldUnknown }
            if let r = verdict.reason(f) { return prefix + r }
            // sim2: catto#3 換分類看新值是不是剛抓到那筆准的（單次 4 類；週期只在獎金、禮金、確幸）
            if k == "category", let i = income, let r = MacEditPolicy.incomeCategoryChangeReason(i, to: value) {
                return prefix + r
            }
            // sim3: catto3（gate）支出換分類看新值是不是 8 類裡的字串；sim4: gate4#1 固定支出分類、週期、停止原因、金額歷史
            if let e = expense, let r = Self.expenseValueReason(k, value, model: e, fetched: item) {
                return prefix + r
            }
        }
        if let e = expense, let r = Self.fixedGateReason(e, item: item, changes: changes, baseItem: baseItem) {
            return prefix + r
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

    /// 支出那筆的 gate4#3（W4-3 結束日不早於開始日，支出也跑）、gate4#2（W4-4 iPhone 剛改了金額或扣款日）；回原因、不含前綴
    private static func fixedGateReason(_ e: Expense, item: [String: Any], changes: [String: Any?],
                                        baseItem: [String: Any]?) -> String? {
        let isFixed = e.expenseType == .fixed
        // sim4: gate4#3 開始＝changes 的 date（是數字才算）否則剛抓到那筆；結束＝changes 有 endDate 用它、否則剛抓到那筆
        if isFixed || changes.keys.contains("endDate") {
            let start = MacEditPolicy.plainNumber(changes["date"] ?? nil) ?? MacEditPolicy.plainNumber(item["date"])
            let endRaw: Any? = changes.keys.contains("endDate") ? (changes["endDate"] ?? nil) : item["endDate"]
            if let start, let end = MacEditPolicy.plainNumber(endRaw) {
                let calendar = Calendar.current
                let startDay = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: start))
                if calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: end)) < startDay {
                    return MacEditPolicy.errorEndBefore
                }
            }
        }
        // sim4: gate4#2 這次真的改了金額或金額歷史，而開表單那份跟剛抓到那筆的金額、金額歷史、扣款日、週期不一樣 → 請重開表單
        guard isFixed, let baseItem else { return nil }
        let movedMine = ["amount", "amountHistory"].contains { k in
            changes.keys.contains(k) && !LedgerMerge.same(changes[k] ?? nil, item[k])
        }
        guard movedMine else { return nil }
        let movedThere = ["amount", "amountHistory", "date", "recurrence"].contains { k in
            !LedgerMerge.same(baseItem[k], item[k])
        }
        return movedThere ? MacEditPolicy.reasonFixedAmountMoved : nil
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
    /// [v25.644 mac4] 收 job（purpose、fixedForm、amountPick、base）；順序照 sim4 post_check4：P1 P2 P3 P4 P6 P7 P5 P8；新增 A1 A0 A2 A3F A3
    static func postReason(key: String, job: MacWriteJob, action: MacLedgerAction, fetched: [String: Any]?,
                           merged: [String: Any]?, fresh: MacFreshLinks) -> String? {
        guard let schema = LedgerMerge.schema(for: key) else { return MacEditPolicy.reasonPostShape }
        let isExpense = key == LedgerMerge.expensesKey
        let purpose = job.purpose
        switch action {
        case .delete:
            return nil
        case .edit(let id, let changes):
            // sim3: post3#P1 合併後那筆要在
            guard let merged else { return MacEditPolicy.reasonPostShape }
            let before: [String: Any] = fetched ?? [:]
            // sim4: post4#P2 依剛抓到那筆的類型挑准改的欄位；剛抓到和合併後類型不同 → 擋
            var isFixed = false
            if isExpense {
                if fetched != nil, !LedgerMerge.same(before["expenseType"], merged["expenseType"]) {
                    return MacEditPolicy.reasonPostShape
                }
                isFixed = (before["expenseType"] as? String) == ExpenseType.fixed.rawValue
            }
            // sim3: post3#P2 跟剛抓到那筆不同的鍵 ⊆ 這次改的鍵 ∩ 這包准改的欄位
            let allow = isExpense ? (isFixed ? MacEditPolicy.fixedPostKeys : MacEditPolicy.expensePostKeys)
                                  : MacEditPolicy.incomePostKeys
            let allowed = Set(changes.keys).intersection(allow)
            let keys = Set(before.keys).union(merged.keys)
            let diff = keys.filter { k in !LedgerMerge.same(before[k], merged[k]) }
            if !diff.isSubset(of: allowed) { return MacEditPolicy.reasonPostShape }
            // sim3: post3#P3 那幾個不同的鍵逐一值檢查（雲端本來就有的舊殘留不擋；固定支出走 fixedPostValueOK）
            for k in diff.sorted() where !postValueOK(key: key, isFixed: isFixed, field: k, value: merged[k], fetched: fetched) {
                return MacEditPolicy.reasonValueBad
            }
            // sim3: post3#P4 本來看得懂的那筆，合併後變成看不懂 → 擋
            if let fetched, LedgerMerge.editable(schema, raw: fetched), !LedgerMerge.editable(schema, raw: merged) {
                return MacEditPolicy.reasonPostShape
            }
            // sim4: post4#P6（★2）這次真的改了的鍵（跟開表單那份不同），合併後要剛好是交出去的值（拿掉的就要沒有）
            if let r = changedKeysLanded(changes: changes, baseItem: MacCloudWriter.item(id, in: job.base), merged: merged) {
                return r
            }
            // sim4: post4#P7 動到開始日、結束日、結束原因：合併後結束那天不早於開始那天
            if let r = endNotBeforeStart(diff: diff, merged: merged) { return r }
            let now = Date()
            // sim4: post4#P5（★3）表單改了金額（跟剛抓到的不同）：該問的一定帶〔從今天起〕那份金額歷史、逐筆一樣；不該問的不准動金額歷史
            if isFixed, case .form(let isNew) = purpose, !isNew, changes.keys.contains("amount"),
               !LedgerMerge.same(changes["amount"] ?? nil, before["amount"]) {
                if let r = fromTodayReason(changes: changes, fetched: fetched, pick: job.amountPick, now: now) { return r }
            }
            // sim4: post4#P8（★4）表單寫固定支出：今天以前每一期（日子、金額）跟剛抓到那筆一模一樣
            if isFixed, case .form = purpose, let fetched, let fe = decodeExpense(fetched) {
                guard let me = decodeExpense(merged),
                      MacFixedCal.samePast(MacFixedCal.pastPeriods(fe, now: now), MacFixedCal.pastPeriods(me, now: now)) else {
                    return MacEditPolicy.reasonFixedPast
                }
            }
            return nil
        case .add:
            // sim3: post3#A1 解得開、editable
            guard let merged, decodes(merged, expense: isExpense), LedgerMerge.editable(schema, raw: merged) else {
                return MacEditPolicy.reasonPostShape
            }
            // sim4: post4#A0 加回、補回、復原刪除：雲端已經有這筆 → 合併後要跟雲端那筆一模一樣（表單新記、⌘D 不看）
            if let fetched, !checksNewShape(purpose), !LedgerMerge.same(fetched, merged) {
                return MacEditPolicy.reasonPostShape
            }
            // sim3: post3#A2 加回擋連著的（支出用剛抓到的分帳細項；收入照 Mac 2）
            guard isExpense else { return MacEditPolicy.addBackReason(raw: merged) }
            if let reason = MacEditPolicy.expenseAddBackReason(raw: merged, links: links(fresh)) { return reason }
            // sim4: post4#A3F 表單新記固定支出（只認 job.fixedForm；沒旗標的固定支出照 A3 擋）
            if case .form(let isNew) = purpose, isNew, job.fixedForm {
                return fixedNewShapeOK(merged) ? nil : MacEditPolicy.reasonPostShape
            }
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

    /// P3：固定支出那筆走 fixedPostValueOK（金額歷史對剛抓到那筆的），其餘照 Mac 3
    private static func postValueOK(key: String, isFixed: Bool, field: String, value: Any?, fetched: [String: Any]?) -> Bool {
        if isFixed {
            return MacEditPolicy.fixedPostValueOK(field: field, value: value, fetchedHistory: fetched?["amountHistory"])
        }
        return MacEditPolicy.postValueOK(key: key, field: field, value: value)
    }

    /// P6：changes 裡跟開表單那份（baseItem）不同的鍵：值 nil → 合併後要沒有；否則合併後要 postSame（數字差 ≤ 1e-6）
    private static func changedKeysLanded(changes: [String: Any?], baseItem: [String: Any]?, merged: [String: Any]) -> String? {
        let b: [String: Any] = baseItem ?? [:]
        for k in changes.keys.sorted() {
            let v: Any? = changes[k] ?? nil
            if LedgerMerge.same(b[k], v) { continue }
            if let v {
                if !MacEditPolicy.postSame(merged[k], v) { return MacEditPolicy.reasonPostShape }
            } else if merged[k] != nil {
                return MacEditPolicy.reasonPostShape
            }
        }
        return nil
    }

    /// P7：這次合併動到 date、endDate、endReason，而合併後結束日、開始日都是數字 → 結束那天不早於開始那天
    private static func endNotBeforeStart(diff: Set<String>, merged: [String: Any]) -> String? {
        guard !diff.isDisjoint(with: ["date", "endDate", "endReason"]),
              let end = MacEditPolicy.plainNumber(merged["endDate"]),
              let start = MacEditPolicy.plainNumber(merged["date"]) else { return nil }
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: start))
        if calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: end)) < startDay {
            return MacEditPolicy.errorEndBefore
        }
        return nil
    }

    // 該問的條件照 AddExpenseView.swift:3985-3992、:4019-4021（f2c8892）amountChangeAsk／savedAmountHistory
    /// P5：剛抓到那筆是週期固定、第一期在今天以前、金額差 > 0.004 → 一定要帶 job 那份〔從今天起〕算出來的金額歷史（逐筆 postSame）；
    /// 不該問 → changes 不准有跟剛抓到不同的金額歷史
    private static func fromTodayReason(changes: [String: Any?], fetched: [String: Any]?, pick: MacAmountPick?,
                                        now: Date) -> String? {
        let fe = fetched.flatMap { raw in decodeExpense(raw) }
        let newAmount = MacEditPolicy.plainNumber(changes["amount"] ?? nil)
        if let fe, fe.recurrence != nil, MacFixedCal.isStarted(fe, now: now), let a = newAmount,
           Swift.abs(a - fe.amount) > 0.004 {
            guard case .fromToday(let cutoff, let firstID, let newID)? = pick, changes.keys.contains("amountHistory") else {
                return MacEditPolicy.reasonPostShape
            }
            let snaps = MacFixedCal.historyFrom(cutoff, history: fe.amountHistory, current: fe.amount, firstDate: fe.date,
                                                newAmount: a, firstID: firstID, newID: newID)
            let want = snaps.compactMap { MacEntryRules.dictionary($0) }
            return MacEditPolicy.postSame(changes["amountHistory"] ?? nil, want) ? nil : MacEditPolicy.reasonPostShape
        }
        if changes.keys.contains("amountHistory"),
           !LedgerMerge.same(changes["amountHistory"] ?? nil, fetched?["amountHistory"]) {
            return MacEditPolicy.reasonPostShape
        }
        return nil
    }

    /// A3F：表單新記的固定支出長相（六類、有週期、台幣、沒連著的鍵、沒照片、沒金額歷史、沒殘留欄位、停止兩欄成對）
    private static func fixedNewShapeOK(_ merged: [String: Any]) -> Bool {
        guard (merged["expenseType"] as? String) == ExpenseType.fixed.rawValue,
              let catRaw = merged["fixedCategory"] as? String, let cat = FixedCategory(rawValue: catRaw),
              MacEditPolicy.plainFixedCategories.contains(cat),
              let recRaw = merged["recurrence"] as? String, Recurrence(rawValue: recRaw) != nil else { return false }
        for k in newEntryBannedKeys + fixedNewBannedKeys where nonEmpty(merged[k]) {
            return false
        }
        for k in ["photoFileNames", "amountHistory"] {
            if let list = merged[k] as? [Any], !list.isEmpty { return false }
        }
        if let code = merged["currencyCode"], (code as? String) != "NT$" { return false }
        guard let e = decodeExpense(merged), !MacEditPolicy.hasFixedResidue(e) else { return false }
        return present(merged["endDate"]) == present(merged["endReason"])
    }

    /// A3F 另外不准出現的鍵（保險、貸款、節稅覆寫、變動支出分類）
    private static let fixedNewBannedKeys = [
        "insuranceSubCategory", "loanSubCategory", "loanTotalAmount", "loanYears", "loanRate", "insuranceRate",
        "taxDeductibleOverride", "variableCategory",
    ]

    /// 有這個鍵而且不是 null（空字串也算有）
    private static func present(_ value: Any?) -> Bool {
        guard let value else { return false }
        return !(value is NSNull)
    }

    /// 原字典 → Expense（解不開＝nil）
    private static func decodeExpense(_ raw: [String: Any]) -> Expense? {
        guard JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw, options: []) else { return nil }
        return try? JSONDecoder().decode(Expense.self, from: data)
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
        // sim4: write4#4 固定支出一律不給〔另存〕（新 id 接不回帳本付款歷史、保單連結）
        if (raw["expenseType"] as? String) != ExpenseType.variable.rawValue { return false }
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
        // sim6: split6#26 分帳那條走分帳的復原（收支那條一字不改）
        if entry.key == MacCloud.splitsKey { splitInverse(entry, purpose: Self.splitPurpose(purpose)); return }
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
        case .repay, .unrepay:
            return                                      // 分帳在 performInverse 開頭就分流（這裡到不了）
        }
    }

    /// 再做一次：新增→加回、刪除→再刪、改→改成電腦寫的值
    private func performForward(_ entry: MacJournalEntry, purpose: MacWritePurpose) {
        // sim6: split6#26 分帳那條走分帳的重做
        if entry.key == MacCloud.splitsKey { splitForward(entry); return }
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
        case .repay, .unrepay:
            return nil                                  // 分帳在 performForward 開頭就分流
        }
    }

    static func ref(key: String, itemID: String) -> MacEntryRef? {
        guard key != MacCloud.splitsKey else { return nil }   // sim6: split6#28 分帳日誌的 itemID 是「支出|那位」，不當成一筆支出
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
            // sim6: split6#27 分帳那條走 saveSplit（同一個 isBusy、一次寫一筆；收支那條一字不改）
            if item.entry.key == MacCloud.splitsKey {
                // 抓完最新再看一次：現在還是同一個原因才補（例：iPhone 已先撤掉自己那筆，repayTwice 就不能再撤電腦這筆）
                let still = journal.watchdog(records: money.records).contains { w in
                    w.entry.id == item.entry.id && w.reason == item.reason
                }
                guard still, let splitAction = Self.splitRestoreAction(item, now: Date()) else { continue }
                let (outcome, entry) = await submitSplit(splitAction, purpose: .restore(item.entry.id))
                switch outcome {
                case .saved(let record, _):
                    money.adopt(record)
                    journal.resolve(item.entry.id)
                    if let entry { registerSplitUndo(entry) }
                    done += 1
                case .nothingToWrite(let record):
                    money.adopt(record)
                    journal.resolve(item.entry.id)
                    done += 1
                default:
                    problem = Self.text(for: outcome)
                }
                if problem != nil { break }
                continue
            }
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
            // sim4: journal4#3 照 MacCloudWriter.fieldGroups 整組補（看門狗只回整組；這裡再展開一次、只留還在看的欄位）
            let keys = MacJournal.expandGroups(Set(item.revertedFields)).intersection(e.watchedFields)
            for k in keys.sorted() {
                if let pair = fields[k] { changes.updateValue(pair.after, forKey: k) }
            }
            return changes.isEmpty ? nil : .edit(id: e.itemID, changes: changes)
        case .deleteBack:
            if let ref = Self.ref(key: e.key, itemID: e.itemID), deleteReason(ref) != nil { return nil }
            return .delete(id: e.itemID)
        case .repayMissing, .unrepayBack, .repayTwice:
            return nil                                  // 分帳在 restoreAll 開頭分流（splitRestoreAction）
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
        // sim6: split6#26 分帳那條〔改回〕＝分帳的 ⌘Z
        if entry.key == MacCloud.splitsKey { splitInverse(entry, purpose: .revert(entryID)); return }
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
            if a.ownFixed { return "iPhone、iPad 也會一起刪掉。" + MacEditPolicy.fixedDeleteOwn }
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
        // [v25.644 mac4] W4-14 固定支出頁會藏已停止的列 → 也先回總覽
        if !ui.page.shows(ref) || ui.page == .variable || ui.page == .fixed { ui.page = .overview }
        ui.selection = ref
    }

    /// sim6: split6#28 分帳那列〔看一下〕＝換到誰還欠我、選那筆支出（只換頁、不寫）
    private func openOwed(_ id: UUID) {
        let ui = edit.ui
        ui.page = .owed
        ui.selection = .expense(id)
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
            if let id = MacEditCenter.splitExpenseID(item.entry) {
                Button("看一下") { openOwed(id) }
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
    /// [v25.644 mac4] 詢問框按〔從今天起〕那一刻定下的 cutoff、firstID、newID；存失敗重按、跳衝突再按都用同一份，表單關掉就丟
    @State private var pendingPick: MacAmountPick?
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
        .modifier(MacFormAskDialog(ask: $ask, run: run, fromToday: fromToday))
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
        case .ask(let a):
            ask = .amountFrom(a)
        }
    }

    /// 詢問框〔從今天起〕（確認框收起來之後才叫）：那一刻定下 cutoff、firstID、newID，再存一次
    private func fromToday() {
        if pendingPick == nil {
            pendingPick = MacAmountPick.fromToday(cutoff: Date(), firstID: UUID(), newID: UUID())
        }
        save()
    }

    private enum Prepared {
        case job(MacWriteJob)
        case nothing
        case error(String)
        /// [v25.644 mac4] 已開始那筆改金額：先問（不存）
        case ask(MacAmountAsk)
    }

    private func prepare() -> Prepared {
        if money.isOffline { return .error("離線中，連上網路再存") }
        switch request.original {
        case .newEntry:
            return prepareNew()
        case .expense(let e):
            // [v25.644 mac4] 照剛打開那筆的類型分流：固定支出走 fixedChanges（存的這一刻 Date()）、變動支出照 Mac 3
            if e.expenseType == .fixed {
                let f = MacEntryRules.fixedChanges(original: e, draft: draft, verdict: request.verdict, now: Date(),
                                                   pick: pendingPick)
                if let a = f.ask { return .ask(a) }
                return prepareEdit(changes: f.changes, error: f.error, pick: pendingPick)
            }
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
        let category: String?
        let stamp = newEntryStamp ?? Date()
        newEntryStamp = stamp
        let fixed = !isIncome && draft.fixedMode
        if isIncome {
            made = Self.makeIncome(draft, id: newEntryID, now: stamp)
            category = draft.incomeCategory.rawValue
        } else if fixed {
            // [v25.644 mac4] 新記固定支出（不記「上次用的分類」：沒有新的偏好鍵）
            made = Self.makeFixed(draft, id: newEntryID, now: stamp)
            category = nil
        } else {
            made = MacEntryRules.newExpense(title: draft.title, amountText: draft.amountText, day: draft.day,
                                            category: draft.expenseCategory, note: draft.note, id: newEntryID, now: stamp)
            category = draft.expenseCategory.rawValue
        }
        guard let raw = made.raw else { return .error(made.error ?? MacEntryRules.amountError) }
        let ref = MacEditCenter.ref(key: key, itemID: (raw["id"] as? String) ?? "")
        return .job(MacWriteJob(key: key, action: .add(raw: raw), base: base, purpose: .form(isNew: true), ref: ref,
                                rememberCategory: category, fixedForm: fixed))
    }

    /// 新記固定支出：停止區開著才交停止日
    private static func makeFixed(_ draft: MacEntryRules.Draft, id: UUID, now: Date) -> (raw: [String: Any]?, error: String?) {
        let end: (day: Date, reason: FixedEndReason)? =
            draft.fixedEnd.enabled ? (day: draft.fixedEnd.day, reason: draft.fixedEnd.reason) : nil
        return MacEntryRules.newFixed(title: draft.title, amountText: draft.amountText, day: draft.day,
                                      category: draft.fixedCategory, recurrence: draft.recurrence, note: draft.note,
                                      end: end, id: id, now: now)
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

    private func prepareEdit(changes: [String: Any?], error: String?, pick: MacAmountPick? = nil) -> Prepared {
        if let error { return .error(error) }
        if changes.isEmpty { return .nothing }
        guard let ref = request.ref else { return .error("找不到這一筆") }
        let key = MacEditCenter.key(of: ref)
        guard let base = request.bases[key] else { return .error("找不到這一筆") }
        let id = MacEditCenter.uuid(of: ref).uuidString
        let itemID = Self.itemID(in: base, matching: id)
        return .job(MacWriteJob(key: key, action: .edit(id: itemID, changes: changes), base: base,
                                purpose: .form(isNew: false), ref: ref, rememberCategory: nil, amountPick: pick))
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
            // sim4: write4#4 固定支出那筆在 iPhone 刪掉了：不給〔另存〕
            if case .expense(let e) = request.original, e.expenseType == .fixed {
                errorText = MacEditPolicy.reasonFixedDetach
                return
            }
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

/// 表單裡的確認框：iPhone 剛改了這筆／這筆在另一台刪掉了／[v25.644 mac4] 已開始那筆改金額
private enum MacFormAsk {
    case conflict(MacConflictAsk)
    /// 〔另存成新的一筆〕要寫的那一筆
    case gone(MacWriteJob)
    /// 〔從今天起（以前的照舊）〕〔取消〕（字照 iPhone，只拿掉〔全部都改〕）
    case amountFrom(MacAmountAsk)

    var title: String {
        switch self {
        case .conflict: return "iPhone 剛改了這筆"
        case .gone: return "這筆在另一台刪掉了"
        case .amountFrom(let a): return a.title
        }
    }

    var message: String {
        switch self {
        case .conflict(let a): return a.message
        case .gone: return "要把你填的另存成新的一筆嗎？不會把刪掉的那筆悄悄寫回去。"
        case .amountFrom(let a): return a.message
        }
    }
}

private struct MacFormAskDialog: ViewModifier {
    @Binding var ask: MacFormAsk?
    let run: @MainActor (MacWriteJob, MacConflictResolution) -> Void
    let fromToday: @MainActor () -> Void

    private var isPresented: Binding<Bool> {
        Binding(get: { ask != nil }, set: { shown in if !shown { ask = nil } })
    }

    func body(content: Content) -> some View {
        content.confirmationDialog(ask?.title ?? "", isPresented: isPresented, titleVisibility: .visible,
                                   presenting: ask) { a in
            MacFormAskButtons(ask: a, run: run, fromToday: fromToday)
        } message: { a in
            Text(a.message)
        }
    }
}

private struct MacFormAskButtons: View {
    let ask: MacFormAsk
    let run: @MainActor (MacWriteJob, MacConflictResolution) -> Void
    let fromToday: @MainActor () -> Void

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
        case .amountFrom:
            // 〔取消〕role: .cancel＋預設鍵（Return 不會誤選〔從今天起〕）
            MacFixedAskButtons(fromToday: fromToday)
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

    /// [v25.644 mac4] 固定支出模式（新記切〔固定〕、改固定支出那筆）
    private var showsFixed: Bool { !isIncome && draft.fixedMode }

    var body: some View {
        Form {
            if request.isNew {
                Section {
                    MacKindPicker(isIncome: $isIncome)
                    if !isIncome {
                        MacFixedModePicker(fixedMode: $draft.fixedMode)
                    }
                }
            }
            if showsFixed {
                MacFixedEditorSection(request: request, draft: $draft, amountFocused: amountFocused)
            } else {
                standardSection
            }
        }
        .formStyle(.grouped)
    }

    /// 收入、變動支出（Mac 1～3 那一區，內容不變）
    private var standardSection: some View {
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

/// [v25.644 mac4] 固定支出那一區：金額 → 名稱 → 分類 → 週期 → 扣款日 → 停止 → 付款方式 → 備註（欄位在 MacFixedFormFields.swift）
private struct MacFixedEditorSection: View {
    let request: MacEditorRequest
    @Binding var draft: MacEntryRules.Draft
    var amountFocused: FocusState<Bool>.Binding

    private var verdict: MacEditVerdict { request.verdict }

    /// 改的是哪一筆固定支出（新記＝nil）
    private var original: Expense? {
        if case .expense(let e) = request.original { return e }
        return nil
    }

    private var started: Bool {
        guard let e = original else { return false }
        return MacFixedCal.isStarted(e, now: Date())
    }

    /// 停止那一區：欄位鎖住的原因；原本停在以前 → 整區鎖（改晚、拿掉都會多出以前的期數）
    private var endReason: String? {
        if let r = verdict.reason(.endDate) { return r }
        guard let e = original, MacEntryRules.fixedEndClosedPast(e, now: Date()) else { return nil }
        return MacEditPolicy.reasonFixedEndReopen
    }

    /// 停止日下限：已開始＝max(今天, 第一期, 最近已扣過那期)；還沒開始＝max(今天, 表單上的第一期)；新記＝表單上的第一期
    private var endLower: Date {
        let first = MacFixedCal.day(draft.day)
        guard let e = original else { return first }
        let now = Date()
        if MacFixedCal.isStarted(e, now: now) { return MacFixedCal.stopLowerBound(e, now: now) }
        return max(MacFixedCal.day(now), first)
    }

    /// 打開停止開關時的預設
    private var defaultEnd: MacFixedEndDraft {
        if let e = original {
            // 第一期還沒到、表單上把扣款日改晚了：預設那天不早於下限（不然要等按存才被 end_before 擋）
            var d = MacEntryRules.fixedStopDefault(e, now: Date())
            let lower = endLower
            if MacFixedCal.day(d.day) < lower { d.day = MacEntryRules.combine(day: lower, timeOf: e.date) }
            return d
        }
        let reason = FixedEndReason.suggested(for: draft.fixedCategory).first ?? .cancelled
        return MacFixedEndDraft(enabled: true, day: max(MacFixedCal.day(Date()), MacFixedCal.day(draft.day)), reason: reason)
    }

    var body: some View {
        Section {
            MacLockableRow(reason: verdict.reason(.amount)) {
                TextField("金額", text: $draft.amountText, prompt: Text("NT$"))
                    .focused(amountFocused)
            }
            MacFixedAmountHint(show: started && verdict.canEdit(.amount))
            MacLockableRow(reason: verdict.reason(.title)) {
                TextField("名稱", text: $draft.title, prompt: Text("必填"))
            }
            MacFixedCategoryField(category: $draft.fixedCategory, reason: verdict.reason(.category),
                                  lockedName: original?.fixedCategory?.rawValue ?? "")
            MacFixedPeriodField(recurrence: $draft.recurrence, reason: verdict.reason(.recurrence))
            MacFixedDayField(day: $draft.day, isNew: request.isNew, reason: verdict.reason(.date))
            MacFixedEndField(end: $draft.fixedEnd, lower: endLower, defaultEnd: defaultEnd, category: draft.fixedCategory,
                             reason: endReason, lockedText: MacFixedEndField.endText(original))
            LabeledContent("付款方式") {
                Text(request.payment)
                    .foregroundStyle(.secondary)
            }
            MacLockableRow(reason: verdict.reason(.note)) {
                MacNoteEditor(note: $draft.note)
            }
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
                MacSplitGoldenRow(report: journal.splitGolden)
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

/// [v25.646 mac6 G1] 資料來源頁寫入區「分帳自我檢查 N/N」（sim6: split6#30）
private struct MacSplitGoldenRow: View {
    let report: MacSplitGolden.Report

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: report.allPassed ? "checkmark.seal.fill" : "xmark.octagon.fill")
                .foregroundStyle(report.allPassed ? Color.green : Color.red)
            Text(text)
        }
    }

    private var text: String {
        if report.allPassed { return "分帳自我檢查 \(report.passed)/\(report.total) 通過" }
        return "分帳自我檢查 \(report.passed)/\(report.total)，沒全過，這台 Mac 先不能標已還"
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
        case .repay: kind = "標已還"
        case .unrepay: kind = "改成還沒還"
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
            // sim6: split6#30 分帳的備份不給〔挑一筆加回…〕（加回一頓／一筆還款牽涉合併規則，不做）
            if file.key != MacCloud.splitsKey {
                Button("挑一筆加回…") { pick = file }
            }
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

    /// [v25.644 mac4] 選到的是固定支出
    private var isFixed: Bool {
        guard case .expense(let id) = ref, let e = edit.money.expense(id) else { return false }
        return e.expenseType == .fixed
    }

    var body: some View {
        if isFixed {
            MacFixedInspectorEditSection(ref: ref, edit: edit)
        } else {
            standardBody
        }
    }

    /// 收入、變動支出（Mac 2、Mac 3 那一段，內容不變）
    private var standardBody: some View {
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

/// [v25.644 mac4] 固定支出那筆：鎖頭清單 MacEditPolicy.fixedFields（停止那列寫「停止」）、〔編輯〕〔停止扣款…〕〔刪除…〕、
/// 最後一行 hintFixedIPhoneOnly
private struct MacFixedInspectorEditSection: View {
    let ref: MacEntryRef
    @ObservedObject var edit: MacEditCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("在電腦改")
                .font(.headline)
            if let v = edit.verdict(ref) {
                MacFixedLockList(verdict: v)
            } else {
                Text("找不到這一筆")
                    .foregroundStyle(.secondary)
            }
            MacFixedInspectorButtons(ref: ref, edit: edit)
            Text(MacEditPolicy.hintFixedIPhoneOnly)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MacFixedLockList: View {
    let verdict: MacEditVerdict

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let lock = verdict.lock {
                Label(lock, systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(MacEditPolicy.fixedFields, id: \.self) { f in
                    MacFieldLockRow(field: f, reason: verdict.reason(f), title: f == .endDate ? "停止" : f.label)
                }
            }
        }
        .font(.callout)
    }
}

/// 〔編輯〕〔停止扣款…〕（反灰＝!canStop）〔刪除…〕；不給〔複製〕
private struct MacFixedInspectorButtons: View {
    let ref: MacEntryRef
    @ObservedObject var edit: MacEditCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button("編輯") { edit.requestEdit(ref) }
                    .disabled(!edit.canEdit(ref))
                Button(MacEditPolicy.stopButton) { edit.requestStop(ref) }
                    .disabled(!edit.canStop(ref))
                Button("刪除…", role: .destructive) { edit.requestDelete(ref) }
                    .disabled(!edit.canDelete(ref))
            }
            MacInspectorHint(text: hint)
        }
    }

    private var hint: String? {
        if !edit.writeEnabled { return edit.writeLockText }
        guard let v = edit.verdict(ref), v.lock == nil else { return nil }
        if let r = edit.deleteReason(ref) { return "不能刪：\(r)" }
        return nil
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
    /// [v25.644 mac4] 列名（預設 field.label；固定支出的 .endDate 寫「停止」）
    var title: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title ?? field.label)
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

// MARK: - [v25.646 mac6 G1] 誰還欠我的入口（judge_mac.md §T4-8）

// 同檔 extension 才拿得到 private 的 writer、registerUndo、status、isBusy；共用同一個 isBusy（一次只寫一筆）。
// block 依序：寫入開關 → 分帳黃金 → 這次開 App 抓過且不是快照 → 離線 → 其餘寫入條件（帳號、收支黃金）→ isBusy。
// request → runSplit → submitSplit → writer.saveSplit → finishSplit。名字不進 registerUndo、日誌、狀態列。
extension MacEditCenter {
    /// 〔已還…〕反灰原因（nil＝可以按）
    func repayBlock(_ r: MacOwedMealRef) -> String? {
        splitBlock()
    }

    /// 〔記下來〕（表單按了才呼叫；date＝表單選的日子）
    func requestRepay(_ r: MacOwedMealRef, date: Date) {
        if let block = splitBlock() { show(block, isError: true); return }
        // sim6: split6#24 新 id（大寫 UUID）、整數秒；金額先放畫面看到的（寫入層換成剛抓到的 outstanding，差 ≥ 0.005 就擋）
        let rep = MacSplitPatch.repayment(id: UUID().uuidString, date: MacSplitPatch.seconds(date), amount: r.expected)
        let action = MacSplitAction.repay(expenseID: r.expenseID.uuidString, shareID: r.shareID.uuidString, repayment: rep,
                                          expected: r.expected)
        runSplit(action, purpose: .page)
    }

    /// 〔改成還沒還〕反灰原因（nil＝可以按）
    func unrepayBlock(_ r: MacOwedMealRef) -> String? {
        splitBlock()
    }

    /// 〔改成還沒還〕確認框按了才呼叫（頁面看到的 lastRepayment；寫入層在剛抓到的那份上再確認是最近一筆）
    func requestUnrepay(_ r: MacOwedMealRef) {
        if let block = splitBlock() { show(block, isError: true); return }
        let action = MacSplitAction.unrepay(expenseID: r.expenseID.uuidString, shareID: r.shareID.uuidString,
                                            repaymentID: r.repaymentID?.uuidString, at: MacSplitPatch.seconds(Date()),
                                            fromPage: true)
        runSplit(action, purpose: .page)
    }

    // sim6: split6#23 兩個鈕共用的反灰原因（頁面用 write_off／snapshot／offline 三個字換成一行說明）
    private func splitBlock() -> String? {
        if !journal.writeEnabled { return MacSplitPatch.reasonText("write_off") }
        if !journal.splitGolden.allPassed { return MacSplitPatch.reasonText("split_golden") }
        if !money.hasFetchedThisLaunch || money.showingCache { return MacSplitPatch.reasonText("snapshot") }
        if money.isOffline { return MacSplitPatch.reasonText("offline") }
        if !writeEnabled { return writeLockText.isEmpty ? MacSplitPatch.reasonText("write_off") : writeLockText }
        if isBusy { return "上一筆還在存，等一下再按" }
        return nil
    }

    // sim6: split6#25 不在表單裡的分帳寫入（頁面、⌘Z、⌘⇧Z、〔改回〕）
    private func runSplit(_ action: MacSplitAction, purpose: MacSplitPurpose) {
        guard !isBusy else { show("上一筆還在存，等一下再按", isError: true); return }
        show("存到 iCloud…", progress: true)
        Task { [weak self] in
            guard let self else { return }
            let (outcome, entry) = await self.submitSplit(action, purpose: purpose)
            self.finishSplit(action, purpose: purpose, outcome: outcome, entry: entry)
        }
    }

    /// 寫分帳（〔補回〕直接叫；回傳結果）
    func submitSplit(_ action: MacSplitAction, purpose: MacSplitPurpose) async -> (MacWriteOutcome, MacJournalEntry?) {
        guard !isBusy else { return (.failed("上一筆還在存，等一下再按"), nil) }
        isBusy = true
        let outcome = await writer.saveSplit(action, journal: journal, golden: journal.golden, splitGolden: journal.splitGolden,
                                             writeEnabled: writeEnabled, label: { raw in MacEditCenter.splitLabel(raw) })
        isBusy = false
        phase = nil
        if case .saved = outcome { return (outcome, writer.lastEntry) }
        return (outcome, nil)
    }

    /// 寫完：收進 MacMoneyStore、登記復原、狀態列（iPhone 剛做過＝灰字，不是錯誤）
    private func finishSplit(_ action: MacSplitAction, purpose: MacSplitPurpose, outcome: MacWriteOutcome,
                             entry: MacJournalEntry?) {
        switch outcome {
        case .saved(let record, _):
            money.adopt(record)
            afterSplitSaved(purpose, entry: entry)
        case .nothingToWrite(let record):
            money.adopt(record)
            if case .restore(let id) = purpose { journal.resolve(id) }
            show(MacSplitPatch.reasonText(Self.isRepay(action) ? "already_settled" : "already_undone"))
        default:
            show(Self.text(for: outcome), isError: true)
        }
        refreshWatchdog(money.records)
    }

    private func afterSplitSaved(_ purpose: MacSplitPurpose, entry: MacJournalEntry?) {
        let time = Self.clock(Date())
        switch purpose {
        case .page:
            if let entry { registerSplitUndo(entry) }
            let text = entry?.kind == .unrepay ? "已改成還沒還" : "記好了：已還（現金）"
            status = MacEditStatus(text: "\(text) \(time)", isError: false, isProgress: false, undoEntryID: entry?.id)
        case .undo:
            show("已復原 \(time)")                          // 復原、重做自己寫的那一筆不登記，不佔 20 步
        case .redo:
            show("已重做 \(time)")
        case .restore(let id):
            journal.resolve(id)
            if let entry { registerSplitUndo(entry) }
            show("已補回 \(time)")
        case .revert:
            if let entry { registerSplitUndo(entry) }
            show("已改回 \(time)")
        }
    }

    /// 復原名稱只准這兩個（不帶名字）
    private func registerSplitUndo(_ entry: MacJournalEntry) {
        if entry.kind == .unrepay {
            registerUndo(entry.id, name: "改成還沒還", redo: false)
        } else {
            registerUndo(entry.id, name: "標已還", redo: false)
        }
    }

    private static func isRepay(_ action: MacSplitAction) -> Bool {
        if case .repay = action { return true }
        return false
    }

    // MARK: ⌘Z／⌘⇧Z／〔改回〕／〔補回〕

    private static func splitPurpose(_ p: MacWritePurpose) -> MacSplitPurpose {
        switch p {
        case .redo: return .redo
        case .restore(let id): return .restore(id)
        case .revert(let id): return .revert(id)
        case .form, .delete, .undo, .addBack, .duplicate: return .undo
        }
    }

    // sim6: split6#26 ⌘Z（〔改回〕同）：標已還 → 撤「這一步現在代表的那筆」；改成還沒還 → 新 id 再標一次（同日期、同金額）
    private func splitInverse(_ entry: MacJournalEntry, purpose: MacSplitPurpose) {
        if let block = splitBlock() { show(block, isError: true); return }
        guard let action = Self.splitInverseAction(entry, entries: journal.entries, newID: UUID().uuidString, now: Date()) else {
            show("日誌裡這筆讀不懂，沒辦法復原", isError: true)
            return
        }
        runSplit(action, purpose: purpose)
    }

    /// ⌘⇧Z：標已還 → 新 id 再標一次（撤銷是黏的）；改成還沒還 → 撤上一步復原新建的那筆
    private func splitForward(_ entry: MacJournalEntry) {
        if let block = splitBlock() { show(block, isError: true); return }
        guard let action = Self.splitForwardAction(entry, entries: journal.entries, newID: UUID().uuidString, now: Date()) else {
            show("日誌裡這筆讀不懂，沒辦法重做", isError: true)
            return
        }
        runSplit(action, purpose: .redo)
    }

    static func splitInverseAction(_ entry: MacJournalEntry, entries: [MacJournalEntry], newID: String,
                                   now: Date) -> MacSplitAction? {
        guard let info = MacSplitPatch.entryInfo(entry.rawAfter) else { return nil }
        if entry.kind == .repay {
            let rid = splitCurrentID(entry, entries: entries, fallback: info.repaymentID)
            return .unrepay(expenseID: info.expenseID, shareID: info.shareID, repaymentID: rid, at: MacSplitPatch.seconds(now),
                            fromPage: false)
        }
        if entry.kind == .unrepay {
            // iPhone 記的還款日期可能帶小數秒（Date()）；再標一次一律取整數秒（S6 只收整數秒）
            let rep = MacSplitPatch.repayment(id: newID, date: info.date.rounded(.down), amount: info.amount)
            return .repay(expenseID: info.expenseID, shareID: info.shareID, repayment: rep, expected: info.amount)
        }
        return nil
    }

    static func splitForwardAction(_ entry: MacJournalEntry, entries: [MacJournalEntry], newID: String,
                                   now: Date) -> MacSplitAction? {
        guard let info = MacSplitPatch.entryInfo(entry.rawAfter) else { return nil }
        if entry.kind == .repay {
            let rep = MacSplitPatch.repayment(id: newID, date: info.date.rounded(.down), amount: info.amount)
            return .repay(expenseID: info.expenseID, shareID: info.shareID, repayment: rep, expected: info.amount)
        }
        if entry.kind == .unrepay {
            let rid = splitCurrentID(entry, entries: entries, fallback: info.repaymentID)
            return .unrepay(expenseID: info.expenseID, shareID: info.shareID, repaymentID: rid, at: MacSplitPatch.seconds(now),
                            fromPage: false)
        }
        return nil
    }

    /// 這一步現在代表的那筆還款：從這筆日誌起（含自己）同一頓同一位最後一筆「標已還」的 id（⌘Z／⌘⇧Z 每次新建的都算）；
    /// 沒有就是自己那筆。⌘⇧Z「改成還沒還」撤的是上一步復原新建的 R'，不是那位現在的 lastRepayment
    static func splitCurrentID(_ entry: MacJournalEntry, entries: [MacJournalEntry], fallback: String) -> String {
        guard let start = entries.firstIndex(where: { e in e.id == entry.id }) else { return fallback }
        var cur = fallback
        for e in entries[start...] where e.key == MacCloud.splitsKey && e.itemID == entry.itemID && e.kind == .repay {
            if let info = MacSplitPatch.entryInfo(e.rawAfter) { cur = info.repaymentID }
        }
        return cur
    }

    // sim6: split6#27 〔補回〕：repayMissing＝同 id、同日期、同金額再標；unrepayBack、repayTwice＝撤電腦那筆
    static func splitRestoreAction(_ item: MacWatchdogItem, now: Date) -> MacSplitAction? {
        guard let info = MacSplitPatch.entryInfo(item.entry.rawAfter) else { return nil }
        if item.reason == .repayMissing {
            let rep = MacSplitPatch.repayment(id: info.repaymentID, date: info.date, amount: info.amount)
            return .repay(expenseID: info.expenseID, shareID: info.shareID, repayment: rep, expected: info.amount)
        }
        if item.reason == .unrepayBack || item.reason == .repayTwice {
            return .unrepay(expenseID: info.expenseID, shareID: info.shareID, repaymentID: info.repaymentID,
                            at: MacSplitPatch.seconds(now), fromPage: false)
        }
        return nil
    }

    // MARK: 字

    // sim6: split6#29 日誌那一行「分帳還款・11/20 飲食」（照 iPhone 存摺備註 ES:1119-1125；不帶名字、店名、金額）
    static func splitLabel(_ raw: [String: Any]) -> String {
        var day = ""
        if let t = MacSplitPatch.number(raw["date"]) {
            let c = Calendar.current.dateComponents([.month, .day], from: Date(timeIntervalSinceReferenceDate: t))
            day = "\(c.month ?? 0)/\(c.day ?? 0)"
        }
        let category = (raw["variableCategory"] as? String).flatMap { s in VariableCategory(rawValue: s) } ?? VariableCategory.other
        return "分帳還款・" + day + " " + category.rawValue
    }

    /// 分帳日誌那筆支出的 id（itemID 前半；看門狗列〔看一下〕用，不經 ref(key:itemID:)）
    static func splitExpenseID(_ entry: MacJournalEntry) -> UUID? {
        guard entry.key == MacCloud.splitsKey else { return nil }
        return UUID(uuidString: entry.itemID.components(separatedBy: "|").first ?? "")
    }
}
