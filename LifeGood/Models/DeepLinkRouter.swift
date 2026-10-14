import Foundation
import SwiftUI

// MARK: - 深層連結與推播的落點（v25.454）
//
// 從 App 外面點進來的路徑有兩條：
//   • 靈動島／鎖定畫面的即時動態（lifegood://today?stop=…）
//   • 旅遊規劃的跨裝置推播（點通知）
//
// 兩條都要做兩件事：先把分頁切到對的位置，再告訴那一頁「打開這一筆」。
// 分頁切換寫 @AppStorage 就生效（MainTabView 的導覽狀態全部是 @AppStorage）；
// 「打開這一筆」沒辦法用 UserDefaults 表達——它是一次性的動作，不是狀態——
// 所以放在這個 router 上，由目標頁面取走後清掉。

/// 一次性的「打開這一筆」請求。頁面取走後要清掉，不然返回上一頁又會再開一次。
///
/// ⚠️ 不要在 class 層級加 @MainActor：嚴格並行下會讓 View 裡的
///    `@StateObject private var x = X.shared` 編不過（LocationProvider 的教訓）。
///    只標註會改狀態的方法——而這裡連那個都不需要：所有呼叫點都已經在主執行緒上
///    （onAppear／onChange／onOpenURL 的閉包繼承 body 的 @MainActor，
///    推播回呼那條另外用 Task { @MainActor in } 包起來）。方法標了 @MainActor
///    反而會讓 View 的私有方法呼叫不到——View 的方法不是 isolated 的。
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()
    private init() {}

    /// [v25.455] 部屬會議提醒通知的 userInfo 鍵。點通知要知道是哪一場會議。
    static let meetingNotificationKey = "meeting_id"

    /// 靈動島點進來要打開哪一筆行程的卡片（場次 id，格式見 DayTimelineLink）
    @Published private(set) var pendingTimelineStopId: String?
    /// 旅遊推播點進來要打開哪一份行程
    @Published private(set) var pendingTripPlanId: UUID?

    func requestTimelineStop(_ id: String?) {
        pendingTimelineStopId = id
    }

    /// 取走並清掉。沒有人要開的時候回 nil。
    func takeTimelineStop() -> String? {
        defer { pendingTimelineStopId = nil }
        return pendingTimelineStopId
    }

    func requestTripPlan(_ id: UUID?) {
        pendingTripPlanId = id
    }

    func takeTripPlan() -> UUID? {
        defer { pendingTripPlanId = nil }
        return pendingTripPlanId
    }

    // MARK: [v2] 小工具

    /// 小工具／控制項「新增支出」：MainTabView 取走後開 AddExpenseView（預填分類／車子、數字鍵盤跳出）
    @Published private(set) var pendingAddExpense: WidgetAddExpenseRequest?
    /// 小工具「接下來要繳」點某一列：固定支出、房子、車子、保單頁各取自己那一種，打開那一張
    @Published private(set) var pendingItem: DeepLinkItem?
    /// 這次啟動是從小工具點進來的（網址帶 src=widget）。設成 true 就不再改回：
    /// LaunchGate 看到就不播開場動畫、這次不跳「本次更新」
    @Published private(set) var widgetLaunch = false
    /// 每收到一個認得的網址就換一個：MainTabView 收到就關掉設定頁（停在設定頁也要能跳過去）
    @Published private(set) var routeToken = UUID()

    func requestAddExpense(_ request: WidgetAddExpenseRequest) {
        pendingAddExpense = request
    }

    /// 取走並清掉；沒有回 nil（沒有的時候不動 @Published，不會多一次重畫）
    func takeAddExpense() -> WidgetAddExpenseRequest? {
        guard let request = pendingAddExpense else { return nil }
        pendingAddExpense = nil
        return request
    }

    func requestItem(_ item: DeepLinkItem) {
        pendingItem = item
    }

    /// 固定支出頁取走「打開這一筆」。不是固定支出的請求就不動（留給那一頁）
    func takeFixedExpense() -> UUID? {
        guard case .fixedExpense(let id)? = pendingItem else { return nil }
        pendingItem = nil
        return id
    }

    /// 房地產頁取走「打開這一間」
    func takeHouse() -> UUID? {
        guard case .house(let id)? = pendingItem else { return nil }
        pendingItem = nil
        return id
    }

    /// 載具頁取走「打開這一台」
    func takeVehicle() -> UUID? {
        guard case .vehicle(let id)? = pendingItem else { return nil }
        pendingItem = nil
        return id
    }

    /// 儲蓄險頁取走「打開這一張」
    func takeInsurance() -> UUID? {
        guard case .insurance(let id)? = pendingItem else { return nil }
        pendingItem = nil
        return id
    }

    func markWidgetLaunch() {
        if !widgetLaunch { widgetLaunch = true }
    }

    func markRoute() {
        routeToken = UUID()
    }
}

/// [v2] 小工具「新增支出」的請求（WidgetLink.apply 建、MainTabView 取走）。
/// 三個都 nil＝空白表單；categoryKey＝VariableCategory.rawValue；
/// vehicleId＋vehicleCategoryKey（VehicleVariableCategory.rawValue）＝從車子記（Taycan 電費）
struct WidgetAddExpenseRequest: Identifiable, Equatable {
    let id = UUID()
    let categoryKey: String?
    let vehicleId: UUID?
    let vehicleCategoryKey: String?
}

/// [v2] 「打開這一筆」：小工具「接下來要繳」點某一列
enum DeepLinkItem: Equatable {
    case fixedExpense(UUID)
    case house(UUID)
    case vehicle(UUID)
    case insurance(UUID)
}

/// [v2] 列表頁收「打開這一筆」的兩個時機：冷啟動時網址比這一頁先到（onAppear）、
/// 已經停在這一頁時再點一次（onChange）。照 MyCalendarView 收靈動島的寫法，
/// 包成一個修飾器，列表頁那一長串修飾器只多一個。
private struct DeepLinkItemReceiver: ViewModifier {
    @ObservedObject private var deepLink = DeepLinkRouter.shared
    /// 不叫 open：open 是存取層級的關鍵字（open(set)），放在敘述開頭呼叫容易被當成宣告修飾詞
    let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func body(content: Content) -> some View {
        content
            .onAppear { action() }
            .onChange(of: deepLink.pendingItem) { _, _ in action() }
    }
}

extension View {
    /// [v2] 固定支出、載具、房地產、儲蓄險頁：收到「打開這一筆」時呼叫 action（action 裡自己 take 自己那一種）
    func onDeepLinkItem(_ action: @escaping () -> Void) -> some View {
        modifier(DeepLinkItemReceiver(action: action))
    }
}

// MARK: - 分頁切換

/// 寫 MainTabView 的導覽 @AppStorage。
///
/// ⚠️ 一定要用列舉的 rawValue，不要寫字面字串——v25.454 修的 bug 就是這個：
///    appMode 的 rawValue 是中文「人生」，原本的程式碼寫了 "life"，
///    AppMode(rawValue: "life") 解不出來就靜靜退回 .expense，
///    於是點靈動島永遠跳到記帳頁。用列舉的話，哪天 rawValue 改了編譯器會攔下來。
enum AppNavigation {

    static func goToMyCalendar() {
        let d = UserDefaults.standard
        d.set(AppMode.life.rawValue, forKey: "appMode")
        d.set(LifeFeature.career.rawValue, forKey: "life_feature")
        d.set(ManagementFeature.calendar.rawValue, forKey: "management_feature")
    }

    static func goToTravelMap() {
        let d = UserDefaults.standard
        d.set(AppMode.life.rawValue, forKey: "appMode")
        d.set(LifeFeature.travelMap.rawValue, forKey: "life_feature")
    }

    /// [v25.545] 「還能花」小工具 → 收支「總覽」。鍵名照 MainTabView 的 @AppStorage
    ///（"appMode"、"expense_feature"）；AppMode.expense 的 rawValue 是「記帳」。
    static func goToExpenseOverview() {
        let d = UserDefaults.standard
        d.set(AppMode.expense.rawValue, forKey: "appMode")
        d.set(ExpenseFeature.overview.rawValue, forKey: "expense_feature")
    }

    /// [v2] 「接下來要繳」→ 收支「固定支出」
    static func goToFixedExpenses() {
        let d = UserDefaults.standard
        d.set(AppMode.expense.rawValue, forKey: "appMode")
        d.set(ExpenseFeature.fixed.rawValue, forKey: "expense_feature")
    }

    /// [v2] 小工具「新增支出」：新增支出的表單開在「變動支出」頁上面最自然（存完就看得到那一筆）
    static func goToVariableExpenses() {
        let d = UserDefaults.standard
        d.set(AppMode.expense.rawValue, forKey: "appMode")
        d.set(ExpenseFeature.variable.rawValue, forKey: "expense_feature")
    }

    /// [v2] 「接下來要繳」→ 理財的房地產／載具／儲蓄險。鍵名照 MainTabView 的 @AppStorage
    ///（"appMode"、"finance_feature"）；AppMode.finance 的 rawValue 是「理財」。
    /// 沒訂閱照樣切過去：付費頁本來就是「訂閱功能僅供閱覽」（決定 5 只擋會改資料的）
    static func goToFinance(_ feature: FinanceFeature) {
        let d = UserDefaults.standard
        d.set(AppMode.finance.rawValue, forKey: "appMode")
        d.set(feature.rawValue, forKey: "finance_feature")
    }
}

// MARK: - 靈動島：網址 → 要打開的卡片

/// 時間軸上那一筆對應到哪一張卡
enum TimelineRouteTarget {
    /// 部屬會議 → SubordinateItemCard
    case meeting(subId: UUID, meeting: SubordinateMeeting)
    /// 我的行事曆的個人事件 → CalendarEventCard
    case personalEvent(PersonalEvent)
}

extension DayTimelineLink {

    /// 主 App 收到 lifegood://today 時要落在哪裡。
    ///
    /// [v25.469] 軸上多了旅遊景點之後，落點不再只有「我的行事曆」：
    /// 景點要開的是那一趟行程，開到行事曆去等於什麼也沒找到。
    /// 需要 store 是因為場次 id 只帶 UUID 的前 8 碼（ContentState 有 4KB 上限），
    /// 要還原成真正的行程得查一次。
    @discardableResult
    static func apply(_ url: URL, store: LifeStore) -> Bool {
        guard isTodayLink(url) else { return false }
        let stop = stopId(from: url)
        if let stop, stop.first == "t" {
            let prefix = String(stop.dropFirst().prefix(8)).uppercased()
            if let plan = store.tripPlans.first(where: { $0.id.uuidString.hasPrefix(prefix) }) {
                AppNavigation.goToTravelMap()
                DeepLinkRouter.shared.requestTripPlan(plan.id)
                return true
            }
            // 那趟行程已經被刪掉了：退回行事曆，至少不是停在原地沒反應
        }
        AppNavigation.goToMyCalendar()
        DeepLinkRouter.shared.requestTimelineStop(stop)
        return true
    }

    /// [v25.455] 反過來組一個「指向某場部屬會議」的場次 id。
    ///
    /// 給鬧鐘警示上的「打開 LifeGood」用：那裡只有會議 id，沒有場次時間。
    /// 時間那一段（epoch）在 resolve 時並沒有被用到——反查只看來源字母與 UUID 前
    /// 8 碼——所以補 0 就夠，不需要把開會時間一路傳下來。
    /// 格式必須與 TodayAgenda.stopId（v25.545 前在 DayTimelineController）一致，
    /// 長度也要過 resolve 的 > 9 檢查。
    static func stopIdForMeeting(uuidString: String) -> String {
        "m" + String(uuidString.prefix(8)) + "0"
    }

    /// 把場次 id 還原成實際的那一筆。
    ///
    /// id 的長相是「來源字母 + UUID 前 8 碼 + 開始時間的 epoch」
    ///（TodayAgenda.stopId，v25.545 前在 DayTimelineController；當初為了擠進 ContentState 的 4KB 上限
    /// 才只放 8 碼，不是完整 UUID）。8 碼 hex 在個人資料量下碰撞機率可以忽略。
    ///
    /// 系統行事曆（'e'）的事件回 nil——它的 id 來自 EventKit，不在我們的資料裡，
    /// 沒有對應的卡片可以開，就只切到行事曆頁。
    /// 旅遊景點（'t'）也回 nil：它在 apply 就被接走開旅遊了，不會走到這裡。
    static func resolve(stopId: String, store: LifeStore) -> TimelineRouteTarget? {
        guard let kind = stopId.first, stopId.count > 9 else { return nil }
        let uuidPrefix = String(stopId.dropFirst().prefix(8)).uppercased()
        switch kind {
        case "m":
            for sub in store.subordinates {
                if let m = sub.meetings.first(where: { $0.id.uuidString.hasPrefix(uuidPrefix) }) {
                    return .meeting(subId: sub.id, meeting: m)
                }
            }
            return nil
        case "p":
            if let e = store.personalEvents.first(where: { $0.id.uuidString.hasPrefix(uuidPrefix) }) {
                return .personalEvent(e)
            }
            return nil
        default:
            return nil
        }
    }
}

// MARK: - 小工具／靈動島：網址的總入口（v25.545）

extension WidgetLink {

    /// 主 App 收到 lifegood:// 的唯一入口（LifeGoodApp.onOpenURL）。
    ///
    /// 解析在共用檔（WidgetLink.parse，小工具組網址用同一份）；「切到哪一頁」碰得到
    /// AppMode／ExpenseFeature，只能寫在 App 側——v25.454 的教訓（共用檔寫 "life"，
    /// rawValue 其實是「人生」，點靈動島永遠跳錯頁）。
    ///
    /// - lifegood://today…：原封不動交給 DayTimelineLink.apply（靈動島既有行為一個字都不改；
    ///   旅遊景點開那一趟、其他開我的行事曆那一場的卡片）
    /// - lifegood://expense/overview：收支「總覽」
    /// - [v2] lifegood://add/expense…：切到變動支出、請 MainTabView 開新增支出（預填分類／車子、數字鍵盤跳出）
    /// - [v2] lifegood://expense/fixed…、lifegood://finance/house|vehicle|insurance…：切頁，帶 id 就請那一頁打開那一張
    /// - 認不得的網址回 false、什麼都不做（跟以前只認 today 時一樣）
    ///
    /// [v2] 控制項「記一筆」（LifeGoodOpenIntent → WidgetOpenAppHandoff）也走這裡，跟 onOpenURL 同一個總入口。
    /// route.fromWidget（網址帶 src=widget）→ markWidgetLaunch：不播開場動畫、這次不跳本次更新（LaunchGate）；
    /// 每個認得的網址都換 routeToken：MainTabView 收到就關掉設定頁。
    @discardableResult
    static func apply(_ url: URL, store: LifeStore) -> Bool {
        guard let route = parse(url) else { return false }
        let router = DeepLinkRouter.shared
        if route.fromWidget { router.markWidgetLaunch() }
        router.markRoute()
        switch route.destination {
        case .today:
            return DayTimelineLink.apply(url, store: store)
        case .expenseOverview:
            AppNavigation.goToExpenseOverview()
            return true
        case .addExpense(let categoryKey, let vehicleId, let vehicleCategoryKey):
            AppNavigation.goToVariableExpenses()
            router.requestAddExpense(WidgetAddExpenseRequest(categoryKey: categoryKey,
                                                             vehicleId: vehicleId,
                                                             vehicleCategoryKey: vehicleCategoryKey))
            return true
        case .fixedExpense(let id):
            AppNavigation.goToFixedExpenses()
            if let id { router.requestItem(.fixedExpense(id)) }
            return true
        case .financeHouse(let id):
            AppNavigation.goToFinance(.realEstate)
            if let id { router.requestItem(.house(id)) }
            return true
        case .financeVehicle(let id):
            AppNavigation.goToFinance(.vehicle)
            if let id { router.requestItem(.vehicle(id)) }
            return true
        case .financeInsurance(let id):
            AppNavigation.goToFinance(.insurance)
            if let id { router.requestItem(.insurance(id)) }
            return true
        }
    }
}
