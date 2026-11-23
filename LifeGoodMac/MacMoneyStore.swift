// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.640 mac1] Mac 的收支資料（brief.md §G2-5、judge_mac.md §O2、§C4(3)）。
//
// • 每個鍵的**原始 bytes＋changeTag（records）才是真的資料**；解碼出來的 expenses／incomes 只拿來顯示、計算。
// • 沒有 didSet、沒有 save、不碰 UserDefaults、不推、不寫 iCloud（寫入只在 MacCloudWriter，寫成功後用 adopt 交回）。
// • 重新整理只從 MacAppModel（啟動的下一個 runloop、60 秒計時器、帳號換了）、MacShell 的 scenePhase、⌘R、⟳、表單打開前叫；
//   不在 body、.task 裡叫。
// • 統計一支一支照抄 ExpenseStore.swift（25.639），只多 now:、calendar: 參數（iOS 寫死 Date()、Calendar.current），算法逐字一樣；
//   每支上方寫原始行號。sim_mac1.py §一 一支對一支。

import Foundation
import Combine
import CloudKit
import CryptoKit

// MARK: - 一筆的參照（選取、詳情、編輯都用它）

enum MacEntryRef: Hashable, Identifiable {
    case expense(UUID)
    case income(UUID)

    var id: String {
        switch self {
        case .expense(let u): return "e-" + u.uuidString
        case .income(let u): return "i-" + u.uuidString
        }
    }

    var uuid: UUID {
        switch self {
        case .expense(let u): return u
        case .income(let u): return u
        }
    }

    /// 這筆在哪個同步鍵
    var key: String {
        switch self {
        case .expense: return MacCloud.expensesKey
        case .income: return MacCloud.incomesKey
        }
    }

    var isExpense: Bool {
        if case .expense = self { return true }
        return false
    }
}

// MARK: - 帳號／資料狀態

enum MacAccountState: Equatable {
    case unknown, checking, available, noAccount, restricted, temporarilyUnavailable, couldNotDetermine, noData, notOwner
    case failed(String)

    /// 資料來源頁「iCloud 帳號」那一行
    var summary: String {
        switch self {
        case .unknown, .checking: return "正在確認…"
        case .available: return "已登入 ✓"
        case .noAccount: return "還沒登入"
        case .restricted: return "被限制使用"
        case .temporarilyUnavailable: return "暫時無法使用"
        case .couldNotDetermine: return "讀不到帳號狀態"
        case .noData: return "已登入，但這個帳號還沒有 LifeGood 的資料"
        case .notOwner: return "已登入（家人共享的成員）"
        case .failed(let s): return s
        }
    }

    /// 能顯示總覽（有收支資料）
    var hasLedger: Bool { self == .available }
}

// MARK: - 總覽用的值

struct MacCategoryRow: Identifiable {
    let category: VariableCategory
    let amount: Double
    /// 占比（本月變動合計 ≤ 0 時 nil）
    let share: Double?
    let count: Int
    var id: String { category.rawValue }
}

struct MacRecentRow: Identifiable, Hashable {
    enum Kind: Hashable { case variable, fixed, income }
    let ref: MacEntryRef
    let kind: Kind
    let date: Date
    let title: String
    /// 括號裡那段：變動＝分類（飲食）；固定＝固定・分類；收入＝收入
    let detail: String
    /// 台幣（ntdValue；收入原樣）
    let amount: Double
    var id: MacEntryRef { ref }
}

struct MacOverviewNumbers {
    let income: Double
    let yearToDateIncome: Double
    let variable: Double
    let fixed: Double
    let today: Double
    /// 分帳已扣掉別人那份
    let splitDeducted: Double
    let categories: [MacCategoryRow]
    let recent: [MacRecentRow]

    var spend: Double { variable + fixed }
    var balance: Double { income - spend }
}

// MARK: - Store

@MainActor
final class MacMoneyStore: ObservableObject {
    @Published private(set) var expenses: [Expense] = []
    @Published private(set) var incomes: [Income] = []
    @Published private(set) var rates: [CurrencyRate] = []
    @Published private(set) var splitIndex: MacSplitIndex = .empty
    /// 每個鍵剛抓到的樣子（5 個讀的鍵；雲端沒有＝record nil）
    @Published private(set) var records: [String: MacKVRecord] = [:]
    /// 每個鍵有幾筆（JSONSerialization 數陣列；分帳數 splits、細項數 tags）；解不開＝沒有值
    @Published private(set) var counts: [String: Int] = [:]
    @Published private(set) var account: MacAccountState = .unknown
    /// userRecordName 的 SHA256 前 16 碼（本機資料夾名稱；不是 email、不顯示）
    @Published private(set) var accountHash: String?
    @Published private(set) var lastFetch: Date?
    @Published private(set) var isOffline: Bool = false
    @Published private(set) var hasFetchedThisLaunch: Bool = false
    @Published private(set) var isRefreshing: Bool = false
    /// 已經有資料時這一輪讀失敗的原因（資料照留；下一輪成功就清掉）
    @Published private(set) var lastProblem: String?

    let cloud: MacCloud
    /// 原始字典陣列（收支兩個鍵；records 的 data 解成 JSONSerialization 的陣列）
    private var rawArrays: [String: [Any]] = [:]
    /// 每個鍵上次解碼時的 changeTag（同一個 tag 不重解）
    private var decodedTags: [String: String] = [:]
    private var inFlight: Task<Void, Never>?
    /// adopt 的流水號：鍵 → 第幾次 adopt。在那之前就出發的那一輪讀取，回來時不准用舊的蓋掉剛寫進去的那份
    ///（不然總覽少掉剛記的那筆、看門狗誤報「電腦記的不見了」，要等下一輪 60 秒才回來）
    private var adoptSerial = 0
    private var adoptedSerials: [String: Int] = [:]

    init(cloud: MacCloud = .shared) {
        self.cloud = cloud
    }

    // MARK: 重新整理

    /// 讀一次 iCloud。同時有人叫就等正在跑的那一輪（不重複抓）。
    func refresh() async {
        if let running = inFlight {
            await running.value
            return
        }
        let task = Task {
            self.isRefreshing = true
            await self.runRefresh()
            self.isRefreshing = false
            self.inFlight = nil
        }
        inFlight = task
        await task.value
    }

    /// 上次讀成功到現在超過 seconds 秒才讀（視窗回到前景用；避免連續切換一直抓）
    func refreshIfStale(_ seconds: TimeInterval) async {
        if let last = lastFetch, Date().timeIntervalSince(last) < seconds, !isOffline { return }
        await refresh()
    }

    /// iCloud 帳號換了（.CKAccountChanged）：清空再讀
    func accountChanged() async {
        if let running = inFlight { await running.value }
        clearData()
        accountHash = nil
        account = .checking
        await refresh()
    }

    private func runRefresh() async {
        // 只有還不知道狀態時才轉圈（沒登入、沒資料的空白頁每 60 秒重讀時不要閃成「正在讀取」）
        if account == .unknown { account = .checking }
        let status: CKAccountStatus
        do {
            status = try await cloud.accountStatus()
        } catch {
            applyFailure(MacCloud.mapError(error))
            return
        }
        guard status == .available else {
            applyAccountStatus(status)
            return
        }
        let name: String
        do {
            name = try await cloud.userRecordName()
        } catch {
            applyFailure(MacCloud.mapError(error))
            return
        }
        let hash = MacMoneyStore.hashAccount(name)
        if let old = accountHash, old != hash { clearData() }
        if accountHash != hash { accountHash = hash }
        do {
            let serial = adoptSerial
            let fetched = try await fetchLatest()
            apply(fetched, since: serial)
        } catch {
            applyFailure(MacCloud.mapError(error))
        }
    }

    /// 第一次（或帳號剛換）整包抓；之後先只抓 updatedAt 比 changeTag，有變的鍵才抓 payload（judge_mac.md §O2-2 MacCloud）
    private func fetchLatest() async throws -> [String: MacKVRecord] {
        let keys = MacCloud.readKeys
        guard hasFetchedThisLaunch else { return try await cloud.fetch(keys, withPayload: true) }
        let heads = try await cloud.fetch(keys, withPayload: false)
        let now = Date()
        var out: [String: MacKVRecord] = [:]
        var changed: [String] = []
        for key in keys {
            let head = heads[key] ?? MacKVRecord.missing(key, fetchedAt: now)
            if let old = records[key], let tag = old.changeTag, tag == head.changeTag, old.data != nil {
                out[key] = MacKVRecord(key: key, record: old.record, data: old.data, changeTag: tag,
                                       updatedAt: head.updatedAt ?? old.updatedAt, fetchedAt: head.fetchedAt)
            } else if head.record == nil {
                out[key] = head
            } else {
                changed.append(key)
            }
        }
        if !changed.isEmpty {
            let full = try await cloud.fetch(changed, withPayload: true)
            for key in changed {
                out[key] = full[key] ?? MacKVRecord.missing(key, fetchedAt: now)
            }
        }
        return out
    }

    /// Writer 寫成功後交回剛寫進去的那一份（record＝寫完讀回的記錄、data＝寫進去的 bytes）
    func adopt(_ record: MacKVRecord) {
        guard MacCloud.readKeys.contains(record.key) else { return }
        adoptSerial += 1
        adoptedSerials[record.key] = adoptSerial
        var next = records
        next[record.key] = record
        records = next
        if record.record != nil && record.data == nil { return }   // 只有中繼資料：不動解碼結果
        decodedTags[record.key] = record.changeTag
        decode(record.key, record.data)
        if record.key == MacCloud.expensesKey || record.key == MacCloud.incomesKey {
            if account == .noData && record.record != nil { account = .available }
        }
    }

    /// serial＝這一輪出發時的 adopt 流水號；之後才 adopt 的鍵留著 adopt 的那份（這一輪抓到的可能比它舊）
    private func apply(_ fetched: [String: MacKVRecord], since serial: Int) {
        var next = records
        for key in MacCloud.readKeys {
            if (adoptedSerials[key] ?? 0) > serial, records[key] != nil { continue }
            let rec = fetched[key] ?? MacKVRecord.missing(key, fetchedAt: Date())
            let same = rec.changeTag != nil && decodedTags[key] == rec.changeTag && records[key] != nil
            next[key] = rec
            if same { continue }
            if rec.record != nil && rec.data == nil { continue }   // 有記錄但沒有 payload：不動解碼結果
            decodedTags[key] = rec.changeTag
            decode(key, rec.data)
        }
        records = next
        isOffline = false
        lastProblem = nil
        lastFetch = Date()
        hasFetchedThisLaunch = true
        let hasLedger = next[MacCloud.expensesKey]?.record != nil || next[MacCloud.incomesKey]?.record != nil
        account = hasLedger ? .available : .noData
    }

    /// 一個鍵解碼（收支照抄 ExpenseStore.swift:955-964 load()＋:978-987 lossyDecodeArray（25.639）逐筆容錯）
    private func decode(_ key: String, _ data: Data?) {
        let n = MacMoneyStore.countItems(data)
        if counts[key] != n { counts[key] = n }
        switch key {
        case MacCloud.expensesKey:
            rawArrays[key] = data.flatMap { d in LedgerMerge.parseArray(d) }
            if data == nil { expenses = [] } else if let v = MacMoneyStore.lossyDecodeArray([Expense].self, data) { expenses = v }
        case MacCloud.incomesKey:
            rawArrays[key] = data.flatMap { d in LedgerMerge.parseArray(d) }
            if data == nil { incomes = [] } else if let v = MacMoneyStore.lossyDecodeArray([Income].self, data) { incomes = v }
        case MacCloud.ratesKey:
            if data == nil { rates = [] } else if let v = MacMoneyStore.lossyDecodeArray([CurrencyRate].self, data) { rates = v }
        case MacCloud.splitsKey:
            splitIndex = MacSplitIndex(data: data)
        default:
            break   // 細項（kinds）Mac 1 只數筆數、不解碼
        }
    }

    private func applyAccountStatus(_ status: CKAccountStatus) {
        switch status {
        case .noAccount:
            clearData()
            accountHash = nil
            account = .noAccount
        case .restricted:
            clearData()
            accountHash = nil
            account = .restricted
        case .temporarilyUnavailable:
            clearData()
            account = .temporarilyUnavailable
        case .couldNotDetermine:
            clearData()
            account = .couldNotDetermine
        case .available:
            break
        @unknown default:
            clearData()
            account = .couldNotDetermine
        }
    }

    private func applyFailure(_ error: MacCloudError) {
        switch error {
        case .noAccount:
            clearData()
            accountHash = nil
            account = .noAccount
        case .restricted:
            clearData()
            accountHash = nil
            account = .restricted
        case .temporarilyUnavailable:
            clearData()
            account = .temporarilyUnavailable
        case .couldNotDetermine:
            clearData()
            account = .couldNotDetermine
        case .zoneNotFound:
            // 這個帳號沒有 LifeGoodZone（審核員、還沒打開 iCloud 同步）：只顯示空白狀態，絕不建 zone
            clearData()
            lastFetch = Date()
            account = .noData
        case .network:
            // 離線：手上的資料照留，畫面寫「離線中，資料停在 hh:mm」
            isOffline = true
            if !hasFetchedThisLaunch { account = .failed("離線中，連上網路後按 ⌘R") }
        case .other(let message):
            if hasFetchedThisLaunch {
                lastProblem = message
            } else {
                account = .failed(message)
            }
        }
    }

    private func clearData() {
        expenses = []
        incomes = []
        rates = []
        splitIndex = .empty
        records = [:]
        counts = [:]
        rawArrays = [:]
        decodedTags = [:]
        hasFetchedThisLaunch = false
        lastFetch = nil
        isOffline = false
        lastProblem = nil
    }

    // MARK: 查一筆

    /// 那一筆在雲端的原字典（Writer、EditPolicy 用；沒有＝nil）
    func rawEntry(key: String, id: UUID) -> [String: Any]? {
        guard let arr = rawArrays[key] else { return nil }
        for item in arr {
            if let d = item as? [String: Any], let s = d["id"] as? String, UUID(uuidString: s) == id { return d }
        }
        return nil
    }

    func expense(_ id: UUID) -> Expense? {
        expenses.first { e in e.id == id }
    }

    func income(_ id: UUID) -> Income? {
        incomes.first { i in i.id == id }
    }

    /// 5 個鍵 updatedAt 最大的＝iPhone 最後一次推上來的時間
    var lastPhoneSync: Date? {
        records.values.compactMap { r in r.updatedAt }.max()
    }

    // MARK: 小工具

    static func hashAccount(_ recordName: String) -> String {
        let digest = SHA256.hash(data: Data(recordName.utf8))
        let hex = digest.map { b in String(format: "%02x", b) }.joined()
        return String(hex.prefix(16))
    }

    /// 筆數：陣列＝元素數；物件＝splits（分帳）或 tags（細項）的元素數
    static func countItems(_ data: Data?) -> Int? {
        guard let data, let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let arr = obj as? [Any] { return arr.count }
        if let dict = obj as? [String: Any] {
            if let arr = dict["splits"] as? [Any] { return arr.count }
            if let arr = dict["tags"] as? [Any] { return arr.count }
            return 0
        }
        return nil
    }

    /// 逐筆容錯解碼：先試整批，失敗再逐筆解、跳過損壞的元素（照抄 ExpenseStore.swift:978-987（25.639）lossyDecodeArray；
    /// Mac 沒有 UserDefaults，直接吃雲端 bytes）。解不開＝nil（呼叫端保留原值）
    static func lossyDecodeArray<Element: Decodable>(_ type: [Element].Type, _ data: Data?) -> [Element]? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        if let items = try? decoder.decode([Element].self, from: data) { return items }
        if let raw = try? decoder.decode([MacFailableDecodable<Element>].self, from: data) {
            return raw.compactMap { $0.value }
        }
        return nil
    }

    // MARK: - 統計（照抄 ExpenseStore.swift（25.639）；Mac 多 now:、calendar: 參數）

    /// 這筆算你自己的錢（照抄 ExpenseStore.swift:114-116：ExpenseSplitIndex.ownAmount）
    func ownAmount(_ e: Expense) -> Double {
        splitIndex.ownAmount(e)
    }

    // 照抄 ExpenseStore.swift:432-439（25.639）
    func ntdValue(of expense: Expense) -> Double {
        let code = expense.currencyCode
        guard expense.fixedCategory == .insurance,
              expense.insuranceSubCategory == .savings,
              code != "NT$", code != "TWD", !code.isEmpty,
              let rate = rates.first(where: { $0.code == code }), rate.rate > 0
        else { return expense.amount }
        return expense.amount * rate.rate
    }

    // 照抄 ExpenseStore.swift:531-558（25.639）
    func projectedAmount(for expense: Expense, in period: TimePeriod) -> Double {
        guard expense.expenseType == .fixed, let recurrence = expense.recurrence else {
            return expense.amount
        }

        // 外幣儲蓄險先換算 NT$ 再投射（修正：原本 USD 原幣金額被直接當 NT$）
        let amount = ntdValue(of: expense)
        switch (recurrence, period) {
        // 每月 → 各區間
        case (.monthly, .daily):    return amount / 30.0
        case (.monthly, .weekly):   return amount / 4.33
        case (.monthly, .monthly):  return amount
        case (.monthly, .quarterly): return amount * 3.0
        case (.monthly, .yearly):   return amount * 12.0
        // 每季 → 各區間
        case (.quarterly, .daily):    return amount / 91.0
        case (.quarterly, .weekly):   return amount / 13.0
        case (.quarterly, .monthly):  return amount / 3.0
        case (.quarterly, .quarterly): return amount
        case (.quarterly, .yearly):   return amount * 4.0
        // 每年 → 各區間
        case (.yearly, .daily):    return amount / 365.0
        case (.yearly, .weekly):   return amount / 52.0
        case (.yearly, .monthly):  return amount / 12.0
        case (.yearly, .quarterly): return amount / 4.0
        case (.yearly, .yearly):   return amount
        }
    }

    // 照抄 ExpenseStore.swift:561-567（25.639）
    func projectedFixedTotal(for periodDate: Date, period: TimePeriod, calendar: Calendar) -> Double {
        let allFixed = expenses.filter { $0.expenseType == .fixed && $0.recurrence != nil }
        return projectedFixedTotal(from: allFixed, for: periodDate, period: period, calendar: calendar)
    }

    // 照抄 ExpenseStore.swift:571-578（25.639）
    func projectedFixedTotal(from fixedExpenses: [Expense], for periodDate: Date,
                             period: TimePeriod, calendar: Calendar) -> Double {
        let dayOfPeriod = calendar.startOfDay(for: periodDate)
        // [v25.347] 除了「已經開始」，也要求「還沒結束」
        let active = fixedExpenses.filter { $0.isFixedActive(on: dayOfPeriod, calendar: calendar) }
        return active.reduce(0) { $0 + projectedAmount(for: $1, in: period) }
    }

    // 照抄 ExpenseStore.swift:191-207（25.639）currentMonthIncomeTotal（now、calendar 由參數帶進來）
    func currentMonthIncomeTotal(now: Date, calendar: Calendar) -> Double {
        // 單次收入：只計本月實際紀錄的
        let onceTotal = incomes
            .filter { $0.period == .once && calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }

        // 週期性收入：建立日期 <= 本月、且尚未結束的，換算為月金額
        let recurringTotal = incomes
            .filter { $0.period != .once && calendar.startOfDay(for: $0.date) <= calendar.startOfDay(for: now) && $0.isActive(in: now, calendar: calendar) }
            .reduce(0) { $0 + $1.monthlyAmount }

        return onceTotal + recurringTotal
    }

    // 照抄 ExpenseStore.swift:320-340（25.639）incomeTotal(for:)（「今天」改成參數 now）
    func incomeTotal(for date: Date, now: Date, calendar: Calendar) -> Double {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return 0 }

        // 週期收入計入上限：過去月份用該月月底；查詢月份含今天時收斂到「明天 00:00」
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? monthEnd
        let recurringCutoff = min(monthEnd, tomorrow)

        let onceTotal = incomes
            .filter { $0.period == .once && calendar.isDate($0.date, equalTo: date, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }

        let recurringTotal = incomes
            .filter { $0.period != .once && $0.date < recurringCutoff && $0.isActive(in: date, calendar: calendar) }
            .reduce(0) { $0 + $1.monthlyAmount }

        return onceTotal + recurringTotal
    }

    // 照抄 ExpenseStore.swift:303-317（25.639）yearToDateIncomeTotal
    func yearToDateIncomeTotal(now: Date, calendar: Calendar) -> Double {
        let currentMonth = calendar.component(.month, from: now)
        var comps = calendar.dateComponents([.year], from: now)
        comps.day = 1
        var total: Double = 0
        for month in 1...currentMonth {
            comps.month = month
            if let monthDate = calendar.date(from: comps) {
                total += incomeTotal(for: monthDate, now: now, calendar: calendar)
            }
        }
        return total
    }

    // 照抄 ExpenseStore.swift:357-363（25.639）currentMonthExpenses
    func currentMonthExpenses(now: Date, calendar: Calendar) -> [Expense] {
        expenses.filter {
            calendar.isDate($0.date, equalTo: now, toGranularity: .month)
        }
    }

    // 照抄 ExpenseStore.swift:366-370（25.639）
    func currentMonthVariableTotal(now: Date, calendar: Calendar) -> Double {
        currentMonthExpenses(now: now, calendar: calendar)
            .filter { $0.expenseType == .variable }
            .reduce(0) { $0 + ownAmount($1) }
    }

    // 照抄 ExpenseStore.swift:373-377（25.639）
    func currentMonthFixedTotal(now: Date, calendar: Calendar) -> Double {
        projectedFixedTotal(for: now, period: .monthly, calendar: calendar)
    }

    // 照抄 ExpenseStore.swift:379-381（25.639）
    func currentMonthTotal(now: Date, calendar: Calendar) -> Double {
        currentMonthVariableTotal(now: now, calendar: calendar) + currentMonthFixedTotal(now: now, calendar: calendar)
    }

    // 照抄 ExpenseStore.swift:385-398（25.639）todayTotal（isDateInToday 換成 isDate(_:inSameDayAs: now)：now＝Date() 時一樣）
    func todayTotal(now: Date, calendar: Calendar) -> Double {
        // 變動支出：只計今天實際紀錄的
        let variableToday = expenses
            .filter { $0.expenseType == .variable && calendar.isDate($0.date, inSameDayAs: now) }
            .reduce(0) { $0 + ownAmount($1) }

        // 固定支出：依週期換算每日金額
        let fixedDaily = projectedFixedTotal(for: now, period: .daily, calendar: calendar)

        return variableToday + fixedDaily
    }

    // 照抄 ExpenseStore.swift:402-421（25.639）variableCategoryTotals(for:)＋筆數＋占比；
    // 同額照 VariableCategory.allCases 順序（iOS 沒定、字典順序不固定；Mac 定下來，brief 取捨 8）
    func categoryRows(now: Date, calendar: Calendar) -> [MacCategoryRow] {
        let filtered = expenses.filter {
            $0.expenseType == .variable &&
            calendar.isDate($0.date, equalTo: now, toGranularity: .month)
        }
        var totals: [VariableCategory: Double] = [:]
        var tally: [VariableCategory: Int] = [:]
        for expense in filtered {
            if let cat = expense.variableCategory {
                totals[cat, default: 0] += ownAmount(expense)
                tally[cat, default: 0] += 1
            }
        }
        let sum = totals.values.reduce(0, +)
        let order = VariableCategory.allCases
        let sorted = totals.sorted { a, b in
            if a.value != b.value { return a.value > b.value }
            return (order.firstIndex(of: a.key) ?? order.count) < (order.firstIndex(of: b.key) ?? order.count)
        }
        return sorted.map { kv in
            MacCategoryRow(category: kv.key, amount: kv.value, share: sum > 0 ? kv.value / sum : nil,
                           count: tally[kv.key] ?? 0)
        }
    }

    /// 分帳已扣掉別人那份（照抄 ExpenseSplits.swift:609-617 deducted；本月）
    func splitDeducted(now: Date, calendar: Calendar) -> Double {
        splitIndex.deducted(expenses: expenses, month: now, calendar: calendar)
    }

    /// 最近交易（brief 取捨 9）：變動、固定、收入（單次＋週期）照 date 新到舊、同時間照 id 字串；未來日期不列。
    /// 固定支出用它存的 date（起始日），不展開。
    func recentRows(now: Date, limit: Int = 10) -> [MacRecentRow] {
        var rows: [MacRecentRow] = []
        for e in expenses where e.date <= now {
            rows.append(MacMoneyStore.recentRow(e, amount: ntdValue(of: e)))
        }
        for i in incomes where i.date <= now {
            rows.append(MacMoneyStore.recentRow(i))
        }
        rows.sort { a, b in
            if a.date != b.date { return a.date > b.date }
            return a.ref.uuid.uuidString < b.ref.uuid.uuidString
        }
        return Array(rows.prefix(limit))
    }

    /// 總覽一次算完（body 裡叫：只讀、不寫 store）
    func overview(now: Date, calendar: Calendar) -> MacOverviewNumbers {
        MacOverviewNumbers(
            income: currentMonthIncomeTotal(now: now, calendar: calendar),
            yearToDateIncome: yearToDateIncomeTotal(now: now, calendar: calendar),
            variable: currentMonthVariableTotal(now: now, calendar: calendar),
            fixed: currentMonthFixedTotal(now: now, calendar: calendar),
            today: todayTotal(now: now, calendar: calendar),
            splitDeducted: splitDeducted(now: now, calendar: calendar),
            categories: categoryRows(now: now, calendar: calendar),
            recent: recentRows(now: now, limit: 10)
        )
    }

    private static func recentRow(_ e: Expense, amount: Double) -> MacRecentRow {
        let isFixed = e.expenseType == .fixed
        let detail = isFixed ? "固定・" + e.categoryName : e.categoryName
        let title = e.title.trimmingCharacters(in: .whitespaces).isEmpty ? e.categoryName : e.title
        return MacRecentRow(ref: .expense(e.id), kind: isFixed ? .fixed : .variable, date: e.date,
                            title: title, detail: detail, amount: amount)
    }

    private static func recentRow(_ i: Income) -> MacRecentRow {
        let title = i.title.trimmingCharacters(in: .whitespaces).isEmpty ? i.category.rawValue : i.title
        return MacRecentRow(ref: .income(i.id), kind: .income, date: i.date, title: title, detail: "收入", amount: i.amount)
    }
}

/// 包裝單一元素，解碼失敗時不丟錯、回傳 nil（照抄 ExpenseStore.swift:990-995（25.639）FailableDecodable）
struct MacFailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
