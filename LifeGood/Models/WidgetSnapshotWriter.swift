import Foundation
import SwiftUI
import UIKit
import Combine
import WidgetKit

// MARK: - 小工具快照的寫手（v25.545，只屬於主 App；v2 加 bills 與 money 的 v2 欄位）
//
// 從 ExpenseStore／FinanceStore／LifeStore 組出 WidgetMoneySnapshot／WidgetLifeSnapshot／WidgetBillsSnapshot
// （LifeGood/Shared/WidgetSnapshot.swift），防抖 3 秒、內容沒變就不寫，
// 真的寫了才叫重畫（WidgetRefresh.reload，WidgetKind.moneyKinds／lifeKinds／billsKinds）。
//
// 金額的字一律用 App 現有的 MoneyFormat／ntdWanString 組，小工具不再格式化。
// 規格見 scratchpad/widgets/v1/brief.md 的 G1、scratchpad/widgets/v2/brief.md 的 G1-4。
//
// [v2] money 多寫：每一天的 todayText／incomeText／隱藏版／鎖定畫面版的字、月底之後的下個月 1–7 號、
//      分類、最常記的分類、車子卡、常記範本（WidgetMoneyExtras.swift）；
//      新的 bills_v1.json：接下來要繳（WidgetBillsBuilder.swift）。
// [v3] money 多寫車子選單（vehicleOptions：記帳台按鈕、控制項「記到…」），寫了也重畫「記到…」控制項；
//      life 多寫隔天每一種的第一場（nextDayFirstStops：「今天」關掉某幾種時用）與旅行（trips：旅行小工具）。
//      規格見 scratchpad/widgets/v3/brief.md 的 G1-6。
// [v4] 新的 finance_v1.json：股票今天、金價匯率、我的車、淨資產（WidgetFinanceBuilder.swift）。
//      記帳＋理財那條防抖多寫 finance；股價、匯率更新成功時（價錢剛好沒變、store 不會動）
//      報價那兩支叫 noteQuotesUpdated()，防抖 3 秒後只寫 finance（快照多了「App 是幾點更新的」）。
//      只重畫受影響的那幾種（financeKindsToReload）。規格見 scratchpad/widgets/v4/brief.md 的 G1-3。
// [v5] life 多寫部屬今天（hasTeam、team 今天明天各一份、plantAreas）、家庭待辦（familyTasks）、
//      倒數（countdowns）——WidgetLifeExtras.swift，判斷走 TeamDay（部屬總覽同一套）。部屬（請假、班表、任務、
//      報告、生日）、家庭待辦、家人、兼任職務都在 LifeStore 的 @Published 裡，現有的 life 防抖那條就接得到，
//      不用加新的監聽。life 也改成只重畫受影響的那幾種（lifeKindsToReload）；今天有沒有行程變了另外重畫
//      控制項「今日行程」（關的時候寫「今天沒有行程」／「未顯示」）。規格見 scratchpad/widgets/v5/brief.md 的 G1-5。
// [v25.558] 健康 v7b（build/v7b/brief.md §6 G1）：life 多寫「今天（大）」最下面那一行運動（workout，今天、明天各一份；
//      字在 WorkoutFacts.widgetWorkoutDays，WorkoutLifeLinks.swift）。運動、目標（workoutPrefs）、請假（workoutLeave）都在
//      LifeStore 的 @Published 裡，現有的 life 防抖 3 秒那條就接得到，不用加監聽；lifeKindsToReload 多看 workout
//      （只有那一行真的變了才多重畫「今天」，鎖定畫面「下一場」、旅行、部屬今天不受影響）。
// [財富 v4] v25.565（wealth/build/v4/brief.md §6 G2-10、11）：財富（銀行帳戶、信用卡＝人生的里程碑＋財富帳本）
//      跟記帳、理財互相牽動——
//      • 接下來要繳（卡費、交割）、淨資產（存款、卡費與交割）讀財富的一套數字（LifeStore.wealthFacts）：
//        人生那條防抖如果財富變了（LifeStore.wealthRevision 跟上次寫 bills／finance 時不一樣），也重寫 bills、finance；
//        只改了家人、行程（revision 沒變）照舊只寫 life，不多算兩份 FinanceLoanIndex。
//      • 今天小工具的財富日子（卡費截止、交割，CalendarDayItems）會跟著記帳（刷卡）、股票（買賣）變：
//        記帳＋理財那條防抖多寫 life（內容沒變 write 回 false，不重畫）。
// [手錶 v1] v25.574（watch/build/v1/brief.md G1-2）：writeNow 最後面寫手錶附加資料快取（WatchExtrasWriter，寫 bills 時；
//      哪幾期卡費是自己繳）、叫 WatchBridge.snapshotsDidChange()（只讀 App Group 的檔組手錶包、內容變了才送；還沒 start 也叫，
//      冷啟動時拿現成的檔組包）。
// [手錶 v2] v25.576（watch/build/v2/brief.md G1-2）：寫 money 的時候也重寫手錶附加資料快取（手錶記的帳收完只寫 [.money]，
//      快取裡的今天記的帳、includedIds 要跟著變，手錶的待送盒才收得了尾）。
//
// 什麼時候寫：
//   • 啟動（start）：掛好監聽後馬上寫一次全部
//   • 記帳有變：ExpenseStore.objectWillChange 防抖 3 秒 → money、bills
//     （存檔的 didSet 與 iCloud 重讀 load() 都會改 @Published，兩條都接得到；所以不必改 ExpenseStore）
//   • [v2] 理財有變：FinanceStore.objectWillChange 跟記帳併成同一個防抖 3 秒 → money（車子卡、範本的車）、
//     bills（房貸、車貸、保費）；[v4] 再加 finance（股票、匯率、車子、淨資產）
//   • [v4] 股價、匯率更新成功（StockView.refreshAllPrices、ExpenseStore.autoUpdateCurrencyRates）：
//     noteQuotesUpdated() 防抖 3 秒 → finance
//   • 人生／系統行事曆有變：LifeStore、AppleCalendarBridge 的 objectWillChange 防抖 3 秒 → life
//     （[財富 v4] 財富變了（wealthRevision）再加 bills、finance：lifeChanged()）
//   • [財富 v4] 記帳、理財有變也寫 life（今天小工具的卡費截止、交割）
//   • 背景收到 iCloud 變更（iPad／Mac 記的帳）：包在背景工作裡馬上寫全部——背景的防抖計時器
//     不一定等得到 3 秒（App 隨時會被暫停）
//   • 時間大跳（過午夜、換時區、改系統時間）：寫全部；出國落地換時區後，快照的每一天要用新時區重切
//   • 回前景、進背景：LifeGoodApp 呼叫 writeNow()
//
// 寫的規矩（judge.md §3.2）：
//   • 只讀不寫：不改任何 store、不呼叫 FinanceOverviewData.build（它會寫每月淨資產紀錄）
//   • 「今天花了」只用 OverviewBoardData.todayVariable，不用 ExpenseStore.todayTotal（那個含固定支出攤提）
//   • WidgetSnapshotStore.write 回 false（內容沒變或寫失敗）就不叫重畫：App 在背景叫重畫會吃小工具每天的額度
//
// @MainActor：MoneyFormat 的 NumberFormatter、AppleCalendarBridge 都只在主執行緒用。

@MainActor
final class WidgetSnapshotWriter {

    static let shared = WidgetSnapshotWriter()

    /// 哪一份快照
    enum Part: Hashable {
        /// money_v1.json（還能花、記帳台、一按就記、鎖定畫面「已花」）
        case money
        /// life_v1.json（今天、鎖定畫面「下一場」）
        case life
        /// [v2] bills_v1.json（接下來要繳、鎖定畫面「下一筆要繳」）
        case bills
        /// [v4] finance_v1.json（股票今天、金價匯率、我的車、淨資產）
        case finance
    }

    /// 防抖秒數：連續改（一次存檔常常改好幾個 @Published）只寫一次
    private static let debounceSeconds = 3

    private var expenseStore: ExpenseStore?
    /// [v2] 車子卡、常記範本的車、接下來要繳的理財那幾件
    private var financeStore: FinanceStore?
    private var lifeStore: LifeStore?
    private var cancellables = Set<AnyCancellable>()
    private var started = false
    /// 背景收到 iCloud 變更時撐住 App 寫完快照
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    /// [v4] 股價、匯率剛更新成功（noteQuotesUpdated）：防抖之後只寫 finance
    private let quotesNudge = PassthroughSubject<Void, Never>()
    /// [財富 v4] 上次寫 bills＋finance 時 LifeStore.wealthRevision 是多少（-1＝還沒寫過）：
    /// 人生那條防抖看它決定要不要連 bills、finance 一起重寫（財富沒變就不用多算）
    private var lastWealthRevision = -1

    private init() {}

    // MARK: - 對外

    /// 啟動時呼叫一次（重複呼叫無害，第二次起什麼都不做）：掛監聽，然後馬上寫一次全部。
    /// [v2] 多收 finance（簽名改了，LifeGoodApp 一起改）。
    func start(expense: ExpenseStore, finance: FinanceStore, life: LifeStore) {
        guard !started else { return }
        started = true
        expenseStore = expense
        financeStore = finance
        lifeStore = life

        // [v2] 理財改了（車子、房貸、保單）也要重寫：車子卡、範本的車、接下來要繳的理財那幾件。
        // 跟記帳併成同一個防抖：記一筆連車的支出會同時改兩邊（帳本＋車子鏡像），只算一次
        //（bills 每次要建兩份 FinanceLoanIndex，不要連算兩遍）
        // [v4] 再加 finance：匯率、外幣保單、車子的記帳、股票、房子都會動到理財那四個小工具
        // [財富 v4] 再加 life：今天小工具的卡費截止、交割跟著刷卡、買賣股票變（內容沒變 write 回 false，不重畫）
        expense.objectWillChange
            .merge(with: finance.objectWillChange)
            .debounce(for: .seconds(Self.debounceSeconds), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.writeNow([.money, .bills, .finance, .life]) }
            .store(in: &cancellables)

        // [v4] 股價、匯率剛更新成功：價錢跟原本一樣時 store 不會變（上面那條接不到），
        // 可是快照裡「App 是幾點更新的」變了（小工具抓不到價時寫「13:30 的價」），只寫 finance
        quotesNudge
            .debounce(for: .seconds(Self.debounceSeconds), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.writeNow([.finance]) }
            .store(in: &cancellables)

        // 系統行事曆變了（別的 App 改、授權剛打開）也要重寫「今天」：
        // AppleCalendarBridge 收到 EKEventStoreChanged 會改 lastChange
        // [財富 v4] 財富（帳戶、卡、財富帳本）變了再加 bills、finance（lifeChanged）
        life.objectWillChange
            .merge(with: AppleCalendarBridge.shared.objectWillChange)
            .debounce(for: .seconds(Self.debounceSeconds), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.lifeChanged() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .cloudSyncDidPullChanges)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.cloudDidPullChanges() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.writeNow() }
            .store(in: &cancellables)

        writeNow()
    }

    /// [財富 v4] 人生那條防抖到了：一律寫 life；財富的 revision 跟上次寫 bills＋finance 時不一樣（加了卡、改了扣款帳戶、
    /// 標成已繳、對存摺…）再加 bills、finance（接下來要繳的卡費、交割，淨資產的存款、卡費與交割）
    private func lifeChanged() {
        var parts: Set<Part> = [.life]
        if let life = lifeStore, life.wealthRevision != lastWealthRevision {
            parts.insert(.bills)
            parts.insert(.finance)
        }
        writeNow(parts)
    }

    /// [v4] 股價（StockView.refreshAllPrices）、匯率（ExpenseStore.autoUpdateCurrencyRates）更新成功時叫：
    /// 防抖 3 秒後只寫 finance。還沒 start 就什麼都不做
    func noteQuotesUpdated() {
        quotesNudge.send(())
    }

    /// 立刻組＋寫（啟動、回前景、進背景、背景收到 iCloud 變更）。還沒 start 就什麼都不做
    ///（start 會馬上寫一次）。[v2] 預設三份都寫；一按就記收完帳（QuickRecordImporter）只叫 [.money]。
    /// [v4] 預設四份都寫（多 finance）
    func writeNow(_ parts: Set<Part> = [.money, .life, .bills, .finance]) {
        let now = Date()
        if parts.contains(.money), let expense = expenseStore {
            let snapshot = Self.moneySnapshot(expense: expense, finance: financeStore, now: now)
            if WidgetSnapshotStore.write(snapshot) {
                WidgetRefresh.reload(WidgetKind.moneyKinds)
                // [v3] 「記到…」控制項的「Taycan 電費」從 money 快照讀（車改名、賣掉要跟著變）
                WidgetRefresh.reloadControls(WidgetKind.moneyControlKinds)
            }
        }
        if parts.contains(.life), let life = lifeStore {
            // [v5] 只重畫內容真的變了的那幾種（同 finance）；先讀舊檔才比得出來
            let old = WidgetSnapshotStore.read(WidgetLifeSnapshot.self)
            let snapshot = Self.lifeSnapshot(life: life, now: now)
            if WidgetSnapshotStore.write(snapshot) {
                WidgetRefresh.reload(Self.lifeKindsToReload(old: old, new: snapshot))
                if Self.dayTimelineControlNeedsReload(old: old, new: snapshot, now: now) {
                    WidgetRefresh.reloadControls(WidgetKind.dayTimelineControlKinds)
                }
            } else if Self.restampLife(snapshot, now: now) {
                // write 回 false（內容沒變）時，前景且舊檔夠舊就只換時間戳記（restampLife）
                WidgetRefresh.reload(WidgetKind.lifeKinds)
            }
        }
        if parts.contains(.bills), let expense = expenseStore, let finance = financeStore {
            let snapshot = WidgetBillsBuilder.snapshot(expense: expense, finance: finance, now: now)
            if WidgetSnapshotStore.write(snapshot) {
                WidgetRefresh.reload(WidgetKind.billsKinds)
            }
        }
        // [v4] 理財四個小工具：只重畫內容真的變了的那幾種（App 在背景叫重畫會吃小工具每天的額度）
        if parts.contains(.finance), let expense = expenseStore, let finance = financeStore {
            let old = WidgetSnapshotStore.read(WidgetFinanceSnapshot.self)
            let snapshot = WidgetFinanceBuilder.snapshot(expense: expense, finance: finance, now: now)
            if WidgetSnapshotStore.write(snapshot) {
                WidgetRefresh.reload(Self.financeKindsToReload(old: old, new: snapshot))
            }
        }
        // [財富 v4] bills、finance 兩份都用這一版的財富重寫過了：記下 revision（人生那條防抖財富沒變就不再多寫）。
        // 只寫其中一份（股價匯率那條只寫 finance）不記，免得 bills 漏了財富的變動
        if parts.contains(.bills), parts.contains(.finance), expenseStore != nil, financeStore != nil {
            lastWealthRevision = lifeStore?.wealthRevision ?? -1
        }
        // [手錶 v1、v2] 手錶附加資料快取（寫 bills 或 money 的時候；App 開著才有三份資料）＋手錶包（只讀檔組包、內容變了才送）。
        // [v2] 手錶記的帳收完只寫 [.money]：今天記的帳、includedIds 要跟著重寫，手錶才知道那筆入帳了
        if parts.contains(.bills) || parts.contains(.money), let expense = expenseStore, let finance = financeStore,
           let life = lifeStore {
            WatchExtrasWriter.write(expense: expense, finance: finance, life: life, now: now)
        }
        WatchBridge.shared.snapshotsDidChange()
    }

    /// [v4] finance_v1.json 寫了之後要重畫哪幾種：沒有舊檔（第一次寫、schema 換了）＝全部；
    /// 否則 stocks 變了→股票今天（小、中）、rates 變了→金價匯率、vehicles 或日子變了→我的車、
    /// netWorth 或日子變了→淨資產（我的車、淨資產右下的「10/11 的數字」看 dataDay）
    static func financeKindsToReload(old: WidgetFinanceSnapshot?, new: WidgetFinanceSnapshot) -> [String] {
        guard let old else { return WidgetKind.financeKinds }
        let dayChanged = old.dataDay != new.dataDay
        var kinds: [String] = []
        if old.stocks != new.stocks { kinds += WidgetKind.stockKinds }
        if old.rates != new.rates { kinds += WidgetKind.ratesKinds }
        if dayChanged || old.vehicles != new.vehicles { kinds += WidgetKind.vehicleKinds }
        if dayChanged || old.netWorth != new.netWorth { kinds += WidgetKind.netWorthKinds }
        return kinds
    }

    /// [v5] life_v1.json 寫了之後要重畫哪幾種：沒有舊檔＝全部；換日（dataDay／validUntil 變了）＝全部；
    /// 否則 今天：days、trips、team、familyTasks、countdowns、hasTeam 任一個變了（大型都用到）；
    /// 下一場（鎖定畫面）：days；旅行：trips；部屬今天：team、plantAreas、hasTeam
    /// [健康 v7b] 今天多看 workout（大型最下面那一行運動；跑完一趟、改目標、請假才會變），其他三種不受影響
    static func lifeKindsToReload(old: WidgetLifeSnapshot?, new: WidgetLifeSnapshot) -> [String] {
        guard let old else { return WidgetKind.lifeKinds }
        if old.dataDay != new.dataDay || old.validUntil != new.validUntil { return WidgetKind.lifeKinds }
        let daysChanged = old.days != new.days
        let tripsChanged = old.trips != new.trips
        let teamChanged = old.team != new.team || old.hasTeam != new.hasTeam
        let todayExtrasChanged = old.familyTasks != new.familyTasks || old.countdowns != new.countdowns
        let workoutChanged = old.workout != new.workout
        var kinds: [String] = []
        if daysChanged || tripsChanged || teamChanged || todayExtrasChanged || workoutChanged {
            kinds.append(WidgetKind.today)
        }
        if daysChanged { kinds.append(WidgetKind.lockNextStop) }
        if tripsChanged { kinds.append(WidgetKind.travel) }
        if teamChanged || old.plantAreas != new.plantAreas { kinds += WidgetKind.teamKinds }
        return kinds
    }

    /// [v5] 控制項「今日行程」關著時寫「今天沒有行程」或「未顯示」（看 life 快照今天有沒有行程）：
    /// 沒有舊檔、換日、今天「有沒有行程」變了才重畫（控制項只關心有沒有，不關心是哪幾場）
    static func dayTimelineControlNeedsReload(old: WidgetLifeSnapshot?, new: WidgetLifeSnapshot, now: Date) -> Bool {
        guard let old else { return true }
        if old.dataDay != new.dataDay { return true }
        let hadStops: Bool = !(old.day(at: now)?.stops.isEmpty ?? true)
        let hasStops: Bool = !(new.day(at: now)?.stops.isEmpty ?? true)
        return hadStops != hasStops
    }

    // MARK: - 「10:02 更新」的時間戳記

    /// [情境驗證補] 中型「今天」右下角的「10:02 更新」是提醒「LifeGood 沒打開，就不知道你在 Outlook／
    /// 行事曆 App 改的會議」（judge §2.3）。可是內容沒變時 WidgetSnapshotStore.write 不寫，generatedAt
    /// 停在上一次內容變的時候：早上 07:30 寫過、下午 14:00 打開 App 重看過行事曆、什麼都沒變，
    /// 小工具到晚上還寫「07:30 更新」。
    /// App 在前景時叫重畫不算小工具每天的額度，所以舊檔超過這麼久就照樣寫一次，只把時間換成現在。
    private static let lifeRestampAfter: TimeInterval = 30 * 60

    /// 只在前景做（背景叫重畫會吃額度：進背景、背景收到 iCloud 變更都不做）。寫了回 true。
    private static func restampLife(_ snapshot: WidgetLifeSnapshot, now: Date) -> Bool {
        guard UIApplication.shared.applicationState != .background,
              let old = WidgetSnapshotStore.read(WidgetLifeSnapshot.self),
              now.timeIntervalSince(old.generatedAt) >= lifeRestampAfter,
              let url = WidgetSnapshotStore.fileURL(WidgetLifeSnapshot.file, create: true),
              let data = try? WidgetSnapshotStore.makeEncoder().encode(snapshot) else { return false }
        do {
            // 跟 WidgetSnapshotStore.write 同一組寫法：整檔換掉、開機後第一次解鎖就能讀
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }

    // MARK: - 背景的 iCloud 變更

    /// 前景不用做事：各 store 重讀會發 objectWillChange，防抖那條會接。
    /// 背景（雲端推播把 App 叫醒）時防抖計時器可能等不到，所以包在背景工作裡直接寫。
    /// 已經 receive(on: main) 過一次（各 store 的 reloadFromCloud 是同步觀察者，發通知時就跑完了），
    /// 再排一次主執行緒是保險：萬一哪個 store 之後改成非同步重讀。
    private func cloudDidPullChanges() {
        guard UIApplication.shared.applicationState == .background else { return }
        beginBackgroundTask()
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.writeNow()
            self.endBackgroundTask()
        }
    }

    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "LifeGoodWidgetSnapshot") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: - 還能花（money_v1.json）

    /// 今天到月底每天一份。第 0 天就是收支總覽頭部那一份（同一個 OverviewBoardData.build 呼叫）；
    /// 之後每一天是「今天花的歸零、剩餘天數減一、每天還能花重算」，本月支出、收入基準照今天的。
    ///
    /// [v2] 每一天再補 todayText／incomeText／隱藏版／鎖定畫面版的字（WidgetMoneyExtras.decorate）；
    /// 月底之後接下個月 1–7 號（WidgetMoneyExtras.nextMonthBoard：下個月的收入基準與固定支出，
    /// 字跟今天那份同一套 moneyDay＋decorate），11/1 早上沒開 App 也是 11 月的數；
    /// 快照補分類、最常記的分類、車子卡、常記範本。finance 是 nil（還沒 start）時沒有車子卡、範本是空的。
    static func moneySnapshot(expense: ExpenseStore, finance: FinanceStore?, now: Date,
                              calendar cal: Calendar = .current) -> WidgetMoneySnapshot {
        let today = OverviewBoardData.build(store: expense, now: now)
        let todayStart = cal.startOfDay(for: now)
        let lastOffset = max(0, today.daysInMonth - today.day)
        var days: [WidgetMoneyDay] = []
        for k in 0...lastOffset {
            guard let dayStart = cal.date(byAdding: .day, value: k, to: todayStart),
                  let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { continue }
            let board = k == 0 ? today : projected(today, daysAhead: k)
            days.append(decoratedDay(board, dayStart: dayStart, dayEnd: dayEnd))
        }
        // [v2] 下個月 1–7 號：接在這個月最後一天的隔天 00:00 後面
        if let monthEnd = days.last?.dayEnd {
            for k in 0..<WidgetMoneyExtras.nextMonthDays {
                guard let dayStart = cal.date(byAdding: .day, value: k, to: monthEnd),
                      let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { continue }
                let board = WidgetMoneyExtras.nextMonthBoard(expense: expense, day: dayStart, calendar: cal)
                days.append(decoratedDay(board, dayStart: dayStart, dayEnd: dayEnd))
            }
        }
        var snapshot = WidgetMoneySnapshot(generatedAt: now,
                                           dataDay: WidgetDateText.dayKey(now),
                                           month: today.month,
                                           days: days)
        snapshot.categories = WidgetMoneyExtras.categories()
        var car: WidgetVehicleCard? = nil
        var templates: [WidgetQuickTemplate] = []
        if let finance {
            car = WidgetMoneyExtras.vehicleCard(expense: expense, finance: finance, now: now, calendar: cal)
            templates = WidgetMoneyExtras.templates(expense: expense, finance: finance, now: now, calendar: cal)
        }
        snapshot.vehicleCard = car
        snapshot.topCategoryKeys = WidgetMoneyExtras.topCategoryKeys(expense: expense, hasVehicleCard: car != nil,
                                                                     now: now, calendar: cal)
        snapshot.templates = templates
        // [v3] 車子選單（記帳台按鈕、控制項「記到…」）；finance 還沒有（還沒 start）是空陣列
        snapshot.vehicleOptions = finance.map { WidgetMoneyExtras.vehicleOptions(finance: $0, now: now) } ?? []
        return snapshot
    }

    /// [v2] 一天的 v1 字（moneyDay）再補 v2 的字（decorate）
    private static func decoratedDay(_ board: OverviewBoardData, dayStart: Date, dayEnd: Date) -> WidgetMoneyDay {
        var day = moneyDay(board, dayStart: dayStart, dayEnd: dayEnd)
        WidgetMoneyExtras.decorate(&day, board: board)
        return day
    }

    /// 往後推 k 天：複製今天那一份、只改這三樣，其餘（remainingDays、left、allowancePerDay、
    /// hasBase、spending）交給 OverviewBoardData 自己的推導屬性——跟 App 同一套算式。
    private static func projected(_ today: OverviewBoardData, daysAhead k: Int) -> OverviewBoardData {
        var d = today
        d.day = today.day + k
        d.todayVariable = 0
        d.todayCount = 0
        d.daily = today.daily + Array(repeating: 0.0, count: k)
        return d
    }

    /// 一天的字。判斷與寫法照收支總覽：頭部（OverviewBoard.header／capsule）、
    /// 「每天還能花」格（allowanceTile）、「今天花了」格（todayTile）。
    /// 金額只用 MoneyFormat.short、MoneyFormat.percent。
    private static func moneyDay(_ d: OverviewBoardData, dayStart: Date, dayEnd: Date) -> WidgetMoneyDay {
        let ratio = d.hasBase ? d.spending / d.base : 0
        let state: WidgetMoneyState
        let title: String
        let hero: String
        let line: String
        let footer: String
        if !d.hasBase {
            state = .noIncome
            title = "本月支出"
            hero = MoneyFormat.short(d.spending)
            line = "記一筆收入，才算得出還能花"
            footer = d.todayCount > 0
                ? "今天 " + MoneyFormat.short(d.todayVariable) + "・\(d.todayCount) 筆"
                : "今天 還沒花錢"
        } else if d.left >= 0 {
            state = .normal
            title = "本月還能花"
            hero = MoneyFormat.short(d.left)
            line = "每天 " + MoneyFormat.short(d.allowancePerDay)
            footer = progressText(ratio: ratio, remainingDays: d.remainingDays)
        } else {
            state = .over
            title = "本月已超支"
            hero = MoneyFormat.short(-d.left)
            line = "每天 已超支"
            footer = progressText(ratio: ratio, remainingDays: d.remainingDays)
        }
        return WidgetMoneyDay(dayKey: WidgetDateText.dayKey(dayStart),
                              dayStart: dayStart,
                              dayEnd: dayEnd,
                              dateText: WidgetDateText.dayLabel(dayStart),
                              state: state,
                              title: title,
                              hero: hero,
                              line: line,
                              footer: footer,
                              spentRatio: finite(ratio),
                              remainingDays: d.remainingDays,
                              bar: moneyBar(d))
    }

    /// 「已花 62%・還有 19 天」。「已花 62%」跟總覽頭部膠囊同一個寫法（只在有收入基準時用）。
    private static func progressText(ratio: Double, remainingDays: Int) -> String {
        "已花 " + MoneyFormat.percent(finite(ratio)) + "・還有 \(remainingDays) 天"
    }

    /// 「這個月的錢」橫條縮短版：以 max(收入基準, 本月支出, 1) 為整條；固定＋變動不超過 1
    private static func moneyBar(_ d: OverviewBoardData) -> WidgetMoneyBar {
        let scale = max(d.base, d.spending, 1)
        let fixed = clamp01(d.fixed / scale)
        let variable = min(clamp01(d.variable / scale), 1 - fixed)
        let income: Double? = d.hasBase ? clamp01(d.base / scale) : nil
        return WidgetMoneyBar(fixed: fixed, variable: variable, income: income)
    }

    private static func clamp01(_ v: Double) -> Double {
        guard v.isFinite else { return 0 }
        return min(max(v, 0), 1)
    }

    /// 寫進快照的數字一律有限（MoneyFormat.percent 遇到 inf／nan 會在 Int(...) 當掉）
    private static func finite(_ v: Double) -> Double {
        v.isFinite ? v : 0
    }

    // MARK: - 今天（life_v1.json）

    /// [0] 今天、[1] 明天；validUntil＝後天 00:00。
    /// 行程跟靈動島同一段程式（TodayAgenda，不裁站數），全天的事照我的行事曆（CalendarDayItems）。
    /// [v3] 每一天多寫隔天每一種的第一場（nextDayFirstStops）；整份多寫旅行（trips，不受 validUntil 管）。
    /// [v5] 多寫 hasTeam／team／plantAreas／familyTasks／countdowns（WidgetLifeExtras）。
    /// [健康 v7b] 多寫 workout（「今天（大）」最下面那一行運動，今天、明天各一份；WorkoutFacts.widgetWorkoutDays）。
    static func lifeSnapshot(life: LifeStore, now: Date,
                             calendar cal: Calendar = .current) -> WidgetLifeSnapshot {
        let start0 = cal.startOfDay(for: now)
        let start1 = cal.date(byAdding: .day, value: 1, to: start0) ?? start0
        let start2 = cal.date(byAdding: .day, value: 2, to: start0) ?? start1

        let agenda0 = TodayAgenda.items(on: start0, store: life, calendar: cal)
        let agenda1 = TodayAgenda.items(on: start1, store: life, calendar: cal)
        // 後天：明天那一份的「明天 08:30／早會」要第一場；[v3] 每一種的第一場要整天（原本只拿 .first）
        let agenda2 = TodayAgenda.items(on: start2, store: life, calendar: cal)

        let day0 = lifeDay(start: start0, end: start1, agenda: agenda0,
                           nextDayAgenda: agenda1, life: life, calendar: cal)
        let day1 = lifeDay(start: start1, end: start2, agenda: agenda1,
                           nextDayAgenda: agenda2, life: life, calendar: cal)
        var snap = WidgetLifeSnapshot(generatedAt: now,
                                      dataDay: WidgetDateText.dayKey(now),
                                      validUntil: day1.dayEnd,
                                      days: [day0, day1],
                                      trips: trips(life: life, now: now, calendar: cal))
        // [v5] 部屬今天、廠區、家庭待辦（今天、明天各一份，跟 days 同兩天）、倒數（WidgetLifeExtras）
        snap.hasTeam = !life.subordinates.isEmpty
        snap.team = WidgetLifeExtras.team(life: life, dayStarts: [start0, start1], now: now, calendar: cal)
        snap.plantAreas = WidgetLifeExtras.plantAreas(life: life)
        snap.familyTasks = WidgetLifeExtras.familyTasks(life: life, dayStarts: [start0, start1], calendar: cal)
        snap.countdowns = WidgetLifeExtras.countdowns(life: life, now: now, calendar: cal)
        // [健康 v7b] 「今天（大）」最下面那一行運動（今天、明天各一份；字在 WorkoutFacts.widgetWorkoutDays）
        snap.workout = WorkoutFacts.widgetWorkoutDays(life.workouts, prefs: life.workoutPrefs, leave: life.workoutLeave,
                                                      dayStarts: [start0, start1], now: now, calendar: cal)
        return snap
    }

    /// [v3] nextDayFirst（隔天第一場）改從隔天整天的 agenda 拿 .first（跟原本傳進來的同一場），
    /// 另外補隔天每一種的第一場（nextDayFirstStops）
    private static func lifeDay(start: Date, end: Date,
                                agenda: [TodayAgenda.Item],
                                nextDayAgenda: [TodayAgenda.Item],
                                life: LifeStore,
                                calendar cal: Calendar) -> WidgetLifeDay {
        WidgetLifeDay(dayKey: WidgetDateText.dayKey(start),
                      dayStart: start,
                      dayEnd: end,
                      dateText: WidgetDateText.dayLabel(start),
                      shortDateText: WidgetDateText.shortDate(start),
                      stops: agenda.map { widgetStop($0) },
                      allDay: CalendarDayItems.allDay(on: start, store: life, calendar: cal),
                      greeting: greeting(on: start, life: life, calendar: cal),
                      hidesMeetings: life.hidesMeetings(on: start),
                      nextDayFirstStop: nextDayAgenda.first.map { widgetStop($0) },
                      nextDayFirstStops: firstPerKind(nextDayAgenda))
    }

    private static func widgetStop(_ item: TodayAgenda.Item) -> WidgetStop {
        WidgetStop(stop: item.stop, location: item.location, lockTitle: item.lockTitle)
    }

    /// [v3] 每一種行程只留第一場（items 已依開始時間排好，照原順序），最多 4 個（四種）。
    /// 「今天」小工具關掉某幾種時，「明天 08:30 …」從留下的種類挑（WidgetLifeDay.filtered(kinds:)）
    private static let maxFirstStops = 4

    private static func firstPerKind(_ items: [TodayAgenda.Item]) -> [WidgetStop] {
        var seen = Set<TimelineStopKind>()
        var out: [WidgetStop] = []
        for item in items {
            guard out.count < maxFirstStops else { break }
            if seen.insert(item.stop.kind).inserted {
                out.append(widgetStop(item))
            }
        }
        return out
    }

    // MARK: - [v3] 旅行（life_v1.json 的 trips）

    /// 旅行小工具最多看幾趟（還沒回來的、依出發時間）
    private static let maxTrips = 3
    /// 出發超過這麼多天前的行程先跳過（不用為了舊行程算 timeline）
    private static let tripLookbackDays = 60

    /// 還沒回來的旅行（進行中＋接下來的），依（出發時間、id）排好，最多 3 趟。
    /// 「回來了」＝過了最後一天的隔天 00:00（firstDay＋dayCount 天，跟 App「旅遊期間」以天為單位一樣）。
    /// TripPlan.endDate／dayCount 每次都要算時間軸，同一份各只叫一次。
    static func trips(life: LifeStore, now: Date, calendar cal: Calendar = .current) -> [WidgetTrip] {
        let today = cal.startOfDay(for: now)
        let oldest = cal.date(byAdding: .day, value: -tripLookbackDays, to: today) ?? today
        var out: [WidgetTrip] = []
        for plan in life.tripPlans {
            let firstDay = cal.startOfDay(for: plan.startDate)
            guard firstDay >= oldest else { continue }
            let count = max(plan.dayCount, 1)
            guard let after = cal.date(byAdding: .day, value: count, to: firstDay), after > now else { continue }
            let trimmed = plan.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let packing = plan.checklistProgress(.packing)
            out.append(WidgetTrip(id: plan.id,
                                  title: trimmed.isEmpty ? "旅行" : trimmed,
                                  startDate: plan.startDate,
                                  endDate: plan.endDate,
                                  firstDay: firstDay,
                                  dayCount: count,
                                  afterLastDay: after,
                                  packingDone: packing.done,
                                  packingTotal: packing.total,
                                  link: WidgetLink.trip(plan.id).absoluteString))
        }
        out.sort { a, b in
            if a.startDate != b.startDate { return a.startDate < b.startDate }
            return a.id.uuidString < b.id.uuidString
        }
        return Array(out.prefix(maxTrips))
    }

    // MARK: 手寫問候（寫死、不靠 AI）

    /// 星期用固定的英文陣列，不靠語系（Calendar 的 weekday：1＝星期日）
    private static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday",
                                       "Thursday", "Friday", "Saturday"]

    /// 中型右上角兩行：家人生日＞出發去旅行＞週末＞平常
    static func greeting(on day: Date, life: LifeStore, calendar cal: Calendar = .current) -> [String] {
        if let member = CalendarDayItems.birthdayMembers(on: day, store: life, calendar: cal).first {
            let english = member.englishName.trimmingCharacters(in: .whitespacesAndNewlines)
            return english.isEmpty ? ["Happy", "birthday!"] : ["Happy birthday,", english + "!"]
        }
        if life.tripPlans.contains(where: { cal.isDate($0.startDate, inSameDayAs: day) }) {
            return ["Have a nice", "trip!"]
        }
        if cal.isDateInWeekend(day) {
            return ["Enjoy your", "weekend!"]
        }
        let weekday = cal.component(.weekday, from: day)
        let index = min(max(weekday - 1, 0), weekdayNames.count - 1)
        return ["Have a nice", weekdayNames[index] + "!"]
    }
}
