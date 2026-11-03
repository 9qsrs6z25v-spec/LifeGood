import Foundation
import UIKit

// MARK: - 一按就記的 App 端：收件匣（QuickRecordInbox）→ Expense、連車與鏡像、防重收（小工具 v2）
//
// 只屬於「LifeGood」target。由 G2 實作，規格見 scratchpad/widgets/v2/brief.md。
//
// 小工具「一按就記」的按鈕不開 App：QuickRecordIntent 在小工具的行程裡把一筆「待入帳」寫進
// App Group（一筆一個檔，見 QuickRecordInbox.swift 檔頭）。這裡在
//   • App 啟動（LifeGoodApp 的 .task 最前面呼叫 start）
//   • 回前景（scenePhase == .active 呼叫 importPending）
//   • App 正在前景時收到小工具的 Darwin 通知（darwinPing；主控定案 13：不在前景不收，
//     不然 App 剛進背景還活著那幾秒就把剛按的收走，「復原」等於沒有）
// 把收件匣裡的每一筆變成一筆 Expense，一次 addExpenses（一次存檔、一次同步）。
//
// 防重收：收件匣 id 直接當 Expense id。take() 交出來的（含上次沒收完留下的 .taken），
// 帳本裡已經有同 id 的就跳過；存檔是丟到背景佇列寫的（ExpenseStore.save），
// 所以晚 2 秒才 finish（刪 .taken）——中途被殺，下次 take() 會再交出來、這裡擋掉重複。
// 防同時寫檔：兩個行程從來不改同一個檔（小工具寫 / 刪 <id>.json，App 原子改名成 .taken、刪 .taken），
// 不用檔案協調也不用鎖（0xdead10cc）。
//
// 訂閱：記帳免費，一按就記不擋（決定 5 只擋付費功能的資料；AddExpenseView 連車也不擋）。
//
// [手錶 v2] v25.576（watch/judge.md §1.4-2、§4.3；watch/build/v2/brief.md §2）：手錶記的帳也走這裡——
//   • isReady：start 叫過、記帳與理財兩份資料還在。WatchBridge 收到手錶的帳時，是才 importFromWatch，不是就只放收件匣
//     （被手錶叫醒的冷啟動不碰三份大資料，judge §5.4）
//   • importFromWatch()：只收手錶來的（QuickRecordInbox.take(where:)）——小工具剛按、還在 10 分鐘復原時間裡的不動
//   • importPending()（啟動、回前景）照舊收全部，手錶來的也一起收
//   • 手錶來的一入帳（或帳本裡早就有），編號記進 WatchImportedLog（watch_imported_ids）：同一筆從另一條路再到，連收件匣都不進
//   • importOverdue 看全部（pending(includeWatch: true)）：手錶那筆也要在發票比對前先進帳本，才會跟發票合成一筆
//
// [手錶 v6] v25.578（watch/judge.md §2.14、§4.1；watch/build/v6/brief.md §2）：旅途中記的帳——
//   • start 多收 life（預設 nil，舊的呼叫照樣編得過；LifeGoodApp 傳 lifeStore）：入帳時確認那一趟、那一站還在才連
//   • makeExpense：金額一律用收件匣那一筆的台幣（手錶上看到的那個，不用今天的匯率重算）；currencyCode＝那一筆的幣別
//     （沒有＝"NT$"）；連旅遊照 AddExpenseView 存檔那一段：只有變動支出、那一趟還在才連，站要還在那一趟裡（不在＝算整趟）

@MainActor
final class QuickRecordImporter {
    static let shared = QuickRecordImporter()

    private weak var expenseStore: ExpenseStore?
    private weak var financeStore: FinanceStore?
    /// [手錶 v6] 旅途中記的帳要連到那一趟、那一站：入帳時看它還在不在（沒給＝不連）
    private weak var lifeStore: LifeStore?
    /// Darwin 通知只掛一次（singleton 不會釋放，不用拿掉）
    private var observingDarwin = false

    /// 收完之後等多久才刪 .taken：ExpenseStore 的存檔丟到背景佇列寫，等它寫完
    private static let finishDelay: TimeInterval = 2

    private init() {}

    // MARK: - 對外

    /// [手錶 v2] start 叫過、兩份資料都還在（App 開著、或剛用過還活著）。WatchBridge 看這個決定「馬上入帳」還是「只放收件匣」
    var isReady: Bool { expenseStore != nil && financeStore != nil }

    /// 啟動時呼叫一次（重複呼叫無害）：記住 store、掛 Darwin 通知、馬上收一次。
    /// 被系統叫起來在背景跑的（還沒人看到畫面）先不收，等回前景（importPending）再收，
    /// 小工具上的「復原」才不會莫名失效（同主控定案 13 的理由）。
    func start(expense: ExpenseStore, finance: FinanceStore, life: LifeStore? = nil) {
        expenseStore = expense
        financeStore = finance
        if let life {
            lifeStore = life
        }
        if !observingDarwin {
            observingDarwin = true
            let observer = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
            Self.addDarwinObserver(observer)
        }
        guard UIApplication.shared.applicationState != .background else { return }
        importPending()
    }

    /// 收件匣 → 帳本，回傳這次新增幾筆。啟動、回前景（LifeGoodApp）、App 在前景時收到 Darwin 通知時呼叫
    @discardableResult
    func importPending() -> Int {
        guard isReady else { return 0 }
        return importEntries(QuickRecordInbox.take())
    }

    /// [手錶 v2] 只收手錶來的（WatchBridge 收到手錶的帳、App 活著時叫）。小工具那幾筆照舊等 App 回前景（主控定案 13）
    @discardableResult
    func importFromWatch() -> Int {
        guard isReady else { return 0 }
        return importEntries(QuickRecordInbox.take(where: { $0.isFromWatch }))
    }

    /// 交出來的那幾筆 → 帳本，回傳新增幾筆（importPending、importFromWatch 共用）
    private func importEntries(_ entries: [QuickRecordEntry]) -> Int {
        guard let expense = expenseStore, let finance = financeStore else { return 0 }
        guard !entries.isEmpty else { return 0 }

        // 帳本裡已經有同 id 的（上次存好了、.taken 還沒刪）跳過
        var known = Set(expense.expenses.map(\.id))
        var vehicles = finance.vehicles
        // [手錶 v6] 旅途中記的那幾筆：那一趟、那一站還在不在（沒給 life＝空的，一律不連）
        let plans: [TripPlan] = lifeStore?.tripPlans ?? []
        var vehiclesChanged = false
        var newExpenses: [Expense] = []

        for entry in entries {
            guard !known.contains(entry.id) else { continue }
            guard let built = Self.makeExpense(from: entry, vehicles: vehicles, plans: plans) else { continue }
            known.insert(entry.id)
            newExpenses.append(built)
            if let vid = built.linkedVehicleId,
               Self.appendVehicleMirror(for: built, vehicleId: vid, in: &vehicles) {
                vehiclesChanged = true
            }
        }

        // 一次 didSet、一次存檔與推送；車子鏡像也一次指派（照 VehicleMirrors 的寫法）
        expense.addExpenses(newExpenses)
        if vehiclesChanged {
            finance.vehicles = vehicles
        }

        // 交出來的每一筆（含跳過、壞掉的）都要 finish，不然每次都卡在收件匣
        let ids = Set(entries.map(\.id))
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.finishDelay) {
            QuickRecordInbox.finish(ids)
        }

        // [手錶 v2] 手錶來的、帳本裡確定有了（這次新增的＋早就有的）：記進 watch_imported_ids
        let watchImported: [UUID] = entries.filter { $0.isFromWatch && known.contains($0.id) }.map(\.id)
        WatchImportedLog.note(watchImported, at: Date())

        // 「待入帳 N 筆」立刻消失（小工具只畫自己按的：只有收到小工具那幾筆才重畫）；有新增就立刻重寫「今天 N 筆」（不等 3 秒防抖）
        if entries.contains(where: { !$0.isFromWatch }) {
            WidgetRefresh.reload([WidgetKind.quickRecord])
        }
        if !newExpenses.isEmpty {
            WidgetSnapshotWriter.shared.writeNow([.money])
        }
        return newExpenses.count
    }

    /// Darwin 通知的落點：只有 App 正在前景（.active）才收（主控定案 13）
    func darwinPing() {
        guard UIApplication.shared.applicationState == .active else { return }
        importPending()
    }

    /// 電子發票比對之前呼叫（EInvoiceSyncManager.performSync）：start 在背景被叫起來時不收，
    /// 收件匣可能還留著早就過了「復原」時間（bannerDuration，小工具上已經沒有復原鈕）的幾筆；
    /// 沒先收進帳本，同一杯咖啡的發票就會另建一筆。有這種的才收（take 會連剛按的一起收）；
    /// 全部都還在復原時間內就不動——剛按的那筆，發票也還不可能查得到。
    @discardableResult
    func importOverdue(now: Date = Date()) -> Int {
        // [手錶 v2] 看全部（含手錶來的：手錶那杯咖啡也要先進帳本，晚上的發票才會跟它合成一筆）
        let hasOverdue = QuickRecordInbox.pending(includeWatch: true).contains { entry in
            now.timeIntervalSince(entry.createdAt) >= QuickRecordInbox.bannerDuration
        }
        guard hasOverdue else { return 0 }
        return importPending()
    }

    // MARK: - 建支出

    /// 收件匣一筆 → Expense（還沒存）。金額不是正的有限數字就不建（回 nil，照樣 finish 掉）。
    /// 連車照 AddExpenseView 的規則（targetVehicleId／variableVehicleLinked）：分類是「汽車」
    /// 而且那台車還在才連，否則 linkedVehicleId、vehicleExpenseCategory 都是 nil。
    /// [手錶 v6] 幣別照那一筆（金額已經是台幣）；旅途中記的連到那一趟、那一站（tripLink）
    private static func makeExpense(from entry: QuickRecordEntry, vehicles: [Vehicle], plans: [TripPlan]) -> Expense? {
        guard entry.amount.isFinite, entry.amount > 0 else { return nil }
        let category = VariableCategory(rawValue: entry.categoryKey) ?? .other
        let trimmedTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedTitle.isEmpty ? category.rawValue : trimmedTitle
        let vehicleId = linkableVehicleId(entry, category: category, vehicles: vehicles)
        let carCategory = vehicleCategory(of: entry)
        var expense = Expense(
            id: entry.id,
            title: title,
            amount: entry.amount,
            date: entry.createdAt,
            expenseType: .variable,
            variableCategory: category,
            linkedVehicleId: vehicleId,
            vehicleExpenseCategory: vehicleId == nil ? nil : carCategory,
            note: "",
            currencyCode: currencyCode(of: entry)
        )
        expense.fromQuickRecord = true
        // [手錶 v6] 旅途中記的（不在 memberwise init，照 AddExpenseView 存檔端指派）
        let link = tripLink(entry, plans: plans)
        expense.linkedTripPlanId = link.planId
        expense.linkedTripStopId = link.stopId
        return expense
    }

    /// [手錶 v6] 幣別：收件匣那一筆的寫法（去頭尾空白）；沒有、空的＝"NT$"
    static func currencyCode(of entry: QuickRecordEntry) -> String {
        let code = (entry.currencyCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return code.isEmpty ? "NT$" : code
    }

    /// [手錶 v6] 連到哪一趟、哪一站（照 AddExpenseView 存檔那一段）：那一趟還在才連；
    /// 站要還在那一趟裡，不在（被刪了）＝算在整趟上（stopId nil）
    static func tripLink(_ entry: QuickRecordEntry, plans: [TripPlan]) -> (planId: UUID?, stopId: UUID?) {
        guard let pid = entry.tripPlanId, let plan = plans.first(where: { $0.id == pid }) else {
            return (planId: nil, stopId: nil)
        }
        let sid: UUID? = plan.stops.first(where: { $0.id == entry.tripStopId })?.id
        return (planId: pid, stopId: sid)
    }

    /// 這筆要連到哪台車（nil＝不連）
    private static func linkableVehicleId(_ entry: QuickRecordEntry, category: VariableCategory,
                                          vehicles: [Vehicle]) -> UUID? {
        guard category == .vehicle, let vid = entry.vehicleId else { return nil }
        return vehicles.contains(where: { $0.id == vid }) ? vid : nil
    }

    /// 車子分類（解不開退回「其他」）
    private static func vehicleCategory(of entry: QuickRecordEntry) -> VehicleVariableCategory {
        guard let key = entry.vehicleCategoryKey,
              let category = VehicleVariableCategory(rawValue: key) else { return .other }
        return category
    }

    /// 照 AddExpenseView.syncVehicleVariableExpense 寫車子鏡像（在 vehicles 拷貝上改）：
    /// 那台車還沒有指到這筆的才加。有加回 true。
    private static func appendVehicleMirror(for expense: Expense, vehicleId: UUID,
                                            in vehicles: inout [Vehicle]) -> Bool {
        guard let index = vehicles.firstIndex(where: { $0.id == vehicleId }) else { return false }
        let alreadyLinked = vehicles[index].variableExpenses.contains { $0.linkedExpenseId == expense.id }
        guard !alreadyLinked else { return false }
        let mirror = VehicleVariableExpense(
            id: UUID(),
            category: expense.vehicleExpenseCategory ?? .other,
            amount: expense.amount,
            date: expense.date,
            linkedExpenseId: expense.id
        )
        vehicles[index].variableExpenses.append(mirror)
        return true
    }

    // MARK: - Darwin 通知

    /// 掛 Darwin 通知。nonisolated：C 函式指標的閉包不能帶 MainActor（也不能捕捉任何東西），
    /// 所以閉包寫在非隔離的地方，裡面只丟一個回主執行緒的 Task。
    nonisolated private static func addDarwinObserver(_ observer: UnsafeRawPointer) {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, _, _, _, _ in
                Task { @MainActor in
                    QuickRecordImporter.shared.darwinPing()
                }
            },
            QuickRecordInbox.darwinNotificationName as CFString,
            nil,
            .deliverImmediately
        )
    }
}
