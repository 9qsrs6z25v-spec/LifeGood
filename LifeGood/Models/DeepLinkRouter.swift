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
    /// 格式必須與 DayTimelineController.stopId 一致，長度也要過 resolve 的 > 9 檢查。
    static func stopIdForMeeting(uuidString: String) -> String {
        "m" + String(uuidString.prefix(8)) + "0"
    }

    /// 把場次 id 還原成實際的那一筆。
    ///
    /// id 的長相是「來源字母 + UUID 前 8 碼 + 開始時間的 epoch」
    ///（DayTimelineController.stopId；當初為了擠進 ContentState 的 4KB 上限
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
