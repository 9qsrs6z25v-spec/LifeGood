import Foundation
import UserNotifications

// MARK: - 通知能按（手錶 v3，v25.572；watch/judge.md §3.5、§6.5、§8 v3；watch/build/v3/brief.md §2；sim_v3.py 照這裡寫過、跑過）
//
// iPhone 排的本機通知，iPhone 鎖著、手錶戴著時系統會轉到手錶；按鈕定義在 iPhone，手錶上就有，
// 按了在 iPhone **背景**跑。這一版只改 iPhone，手錶 App 還沒有任何程式。
//
// 分類（categoryIdentifier；AppDelegate 一啟動就 registerCategories）：
//   LG_MEETING       部屬會議（NotificationManager.scheduleMeetingJobs）〔5 分鐘後再提醒〕（v1 再加〔看議程〕）
//   LG_EVENT         我的行事曆的個人事件（NotificationManager）〔5 分鐘後再提醒〕
//   LG_WEALTH        財富提醒：卡費截止前 3 天、自動扣款可能不夠扣、交割、卡片到期、定存、保單〔明天 9 點再提醒〕
//   LG_WEALTH_TODAY  卡費今天截止（wealth.due.….0）〔晚上再提醒〕：20:00 以前按＝今天 20:00；20:00 以後按＝1 小時後
// 旅遊變更、跑步暫停 30 分鐘、鬧鐘型會議提醒（AlarmKit）不加按鈕。
//
// 再提醒（handle）：
//   • 原通知內容整份複製（標題、內文、聲音、分類、串、userInfo 都照舊），識別字「snooze.<來源>.<觸發時間秒>」，
//     來源＝userInfo[sourceKey]（排的時候填：mtg.<會議 UUID>／evt.<事件 UUID>／wealth.<帳戶 UUID>）。
//     不能用 mtg_／wealth. 開頭：重排時 NotificationManager、WealthReminderCenter 照前綴整批清掉。
//   • userInfo 多兩把鍵：originKey＝原本那則的 identifier（再提醒的再提醒照舊帶第一則的）、madeKey＝按下去的時間（秒）。
//   • 同一則（同 origin）只留最新的一個；同時最多 5 則再提醒，第 6 則把最早按的換掉（iOS 一個 App 最多 64 則待送）。
//   • 卡費 3 天前那則（wealth.due.<卡>.<期>.3）延到的時間，同一期「今天截止」那則（….0）已經排在那時或更早：不另排（免得同一刻兩則）。
//   • **只碰通知中心**：iPhone 背景冷啟動也跑這裡，不碰 AppStores、三份資料、App Group 檔案、鑰匙圈（judge §1.4-4）。排好才叫 completion。
//
// 重排時清掉來源不在了的再提醒（staleSnoozes；「還在不在」由各排程端判斷）：
//   • 個人事件（NotificationManager.rescheduleAll／cancel）：事件刪了，或時間指紋 eventStamp 變了（改時間、改重複、改提醒）
//   • 部屬會議（NotificationManager.scheduleMeetingJobs）：原本那則的「mtg_<會議>_<場次秒>」不在現在的場次裡（刪了、改時間、取消那一場）
//   • 財富（WealthReminderCenter）：原本那則的 key 不在現在的候選裡（標成已繳、這張卡不提醒、財富提醒整個關掉）
//
// 全部是 nonisolated 的靜態函式（enum 沒有 actor）：AppDelegate 的通知回呼、@MainActor 的 NotificationManager、
// WealthReminderCenter 都可以直接叫。

enum NotificationActions {

    // MARK: 分類與按鈕

    static let meetingCategory = "LG_MEETING"
    static let eventCategory = "LG_EVENT"
    static let wealthCategory = "LG_WEALTH"
    static let wealthTodayCategory = "LG_WEALTH_TODAY"

    /// 〔5 分鐘後再提醒〕（會議、個人事件）
    static let snoozeFiveAction = "LG_SNOOZE_5M"
    /// 〔明天 9 點再提醒〕（財富）
    static let snoozeTomorrowAction = "LG_SNOOZE_TOMORROW_9"
    /// 〔晚上再提醒〕（卡費今天截止）
    static let snoozeEveningAction = "LG_SNOOZE_EVENING"

    // MARK: userInfo 的鍵

    /// 這則通知是誰排的：「mtg.<會議 UUID>」「evt.<事件 UUID>」「wealth.<帳戶 UUID>」
    static let sourceKey = "lg_src"
    /// 個人事件的時間指紋（eventStamp）；重排時跟現在的事件比，不一樣＝改過時間，再提醒拿掉
    static let stampKey = "lg_stamp"
    /// 再提醒：原本那一則的 identifier（「mtg_<會議>_<場次秒>」「<事件 UUID>#3」「wealth.due.<卡>.<期>.3」）
    static let originKey = "lg_origin"
    /// 再提醒：按下去的時間（1970 起的秒，Int）
    static let madeKey = "lg_made"

    /// 再提醒的識別字開頭
    static let snoozePrefix = "snooze."
    /// 再提醒同時最多幾則
    static let maxSnoozes = 5

    // MARK: 來源

    static func meetingSource(_ meetingId: UUID) -> String { "mtg." + meetingId.uuidString }
    static func eventSource(_ eventId: UUID) -> String { "evt." + eventId.uuidString }
    static func wealthSource(_ accountId: UUID) -> String { "wealth." + accountId.uuidString }

    /// 「mtg.<UUID>」→ UUID（格式不對＝nil）
    static func sourceId(_ source: String) -> UUID? {
        guard let dot = source.firstIndex(of: ".") else { return nil }
        return UUID(uuidString: String(source[source.index(after: dot)...]))
    }

    /// 個人事件的時間指紋：開始（秒）｜重複規則｜重複結束日（秒，沒有＝0）｜提醒分鐘。
    /// 改標題、地點、備註不會變（再提醒照留）；改時間、改重複、改提醒會變（再提醒拿掉）
    static func eventStamp(_ event: PersonalEvent) -> String {
        let start = Int(event.date.timeIntervalSince1970)
        let end = event.recurrenceEndDate.map { Int($0.timeIntervalSince1970) } ?? 0
        return "\(start)|\(event.recurrence.rawValue)|\(end)|\(event.reminderMinutes)"
    }

    /// 財富提醒用哪一類：卡費今天截止（wealth.due.<卡>.<期>.0）＝LG_WEALTH_TODAY，其他＝LG_WEALTH
    static func categoryForWealth(key: String) -> String {
        if key.hasPrefix(WealthReminders.prefix + "due."), key.hasSuffix(".0") { return wealthTodayCategory }
        return wealthCategory
    }

    // MARK: 註冊

    /// AppDelegate.didFinishLaunching 一啟動就叫（每次都要叫：系統只記最後一次給的那一組）
    static func registerCategories() {
        let five = UNNotificationAction(identifier: snoozeFiveAction, title: "5 分鐘後再提醒", options: [])
        let tomorrow = UNNotificationAction(identifier: snoozeTomorrowAction, title: "明天 9 點再提醒", options: [])
        let evening = UNNotificationAction(identifier: snoozeEveningAction, title: "晚上再提醒", options: [])
        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(identifier: meetingCategory, actions: [five], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: eventCategory, actions: [five], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: wealthCategory, actions: [tomorrow], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: wealthTodayCategory, actions: [evening], intentIdentifiers: [], options: [])
        ]
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    // MARK: 再提醒的時間

    /// 再提醒排在什麼時候
    struct SnoozePlan: Equatable {
        let fireDate: Date
        /// true＝幾秒後（UNTimeIntervalNotificationTrigger）；false＝那個時刻（UNCalendarNotificationTrigger，到分）
        let isRelative: Bool
    }

    static func isSnoozeAction(_ identifier: String) -> Bool {
        identifier == snoozeFiveAction || identifier == snoozeTomorrowAction || identifier == snoozeEveningAction
    }

    /// 〔5 分鐘後〕＝現在＋5 分鐘；〔明天 9 點〕＝日曆的明天 09:00；〔晚上〕＝今天 20:00，20:00（含）以後按＝1 小時後
    static func snoozePlan(action: String, now: Date, calendar: Calendar) -> SnoozePlan? {
        if action == snoozeFiveAction {
            return SnoozePlan(fireDate: now.addingTimeInterval(5 * 60), isRelative: true)
        }
        if action == snoozeTomorrowAction {
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
                  let at9 = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) else { return nil }
            return SnoozePlan(fireDate: at9, isRelative: false)
        }
        if action == snoozeEveningAction {
            if let at20 = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now), at20 > now {
                return SnoozePlan(fireDate: at20, isRelative: false)
            }
            return SnoozePlan(fireDate: now.addingTimeInterval(60 * 60), isRelative: true)
        }
        return nil
    }

    /// 「snooze.mtg.<會議 UUID>.<觸發時間秒>」
    static func snoozeIdentifier(source: String, fireDate: Date) -> String {
        snoozePrefix + source + "." + String(Int(fireDate.timeIntervalSince1970))
    }

    // MARK: 排之前要拿掉的、要不要排

    /// 排一則新的再提醒之前要拿掉的：同一則（同 origin）的舊再提醒；其他的再提醒已經有 5 則時，最早按的那幾則
    static func snoozesToDrop(pending: [UNNotificationRequest], origin: String) -> [String] {
        var drop: [String] = []
        var rest: [(id: String, made: Int)] = []
        for request in pending where request.identifier.hasPrefix(snoozePrefix) {
            let info = request.content.userInfo
            if (info[AnyHashable(originKey)] as? String) == origin {
                drop.append(request.identifier)
            } else {
                let made = (info[AnyHashable(madeKey)] as? Int) ?? 0
                rest.append((id: request.identifier, made: made))
            }
        }
        let over = rest.count - (maxSnoozes - 1)
        if over > 0 {
            let oldest = rest.sorted { a, b in
                if a.made != b.made { return a.made < b.made }
                return a.id < b.id
            }
            drop.append(contentsOf: oldest.prefix(over).map { $0.id })
        }
        return drop
    }

    /// 卡費 3 天前那則延到的時間，同一期「今天截止」那則已經排在那時或更早（差 1 分鐘內也算）：不另排
    static func coveredBySibling(origin: String, fireDate: Date, pending: [UNNotificationRequest]) -> Bool {
        guard origin.hasPrefix(WealthReminders.prefix + "due."), origin.hasSuffix(".3") else { return false }
        let sibling = String(origin.dropLast(2)) + ".0"
        guard let request = pending.first(where: { $0.identifier == sibling }),
              let next = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() else { return false }
        return next <= fireDate.addingTimeInterval(60)
    }

    // MARK: 按了

    /// AppDelegate.userNotificationCenter(_:didReceive:) **第一件事**叫這支。
    /// 是再提醒的按鈕：排好再提醒、叫 completion、回 true（呼叫端直接 return，不往下走到 AppStores）。
    /// 不是（點通知本身、v1 的〔看議程〕）：回 false、completion 不叫，照原本的路走。
    static func handle(_ response: UNNotificationResponse, completion: @escaping () -> Void) -> Bool {
        let action = response.actionIdentifier
        guard isSnoozeAction(action) else { return false }
        let now = Date()
        let calendar = Calendar.current
        let original = response.notification.request
        guard let plan = snoozePlan(action: action, now: now, calendar: calendar),
              let content = original.content.mutableCopy() as? UNMutableNotificationContent else {
            completion()
            return true
        }
        var info = original.content.userInfo
        let origin = (info[AnyHashable(originKey)] as? String) ?? original.identifier
        let source = (info[AnyHashable(sourceKey)] as? String) ?? "other"
        info[AnyHashable(originKey)] = origin
        info[AnyHashable(madeKey)] = Int(now.timeIntervalSince1970)
        content.userInfo = info

        let trigger: UNNotificationTrigger
        if plan.isRelative {
            let seconds = max(1, plan.fireDate.timeIntervalSince(now))
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        } else {
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate)
            trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        }
        let identifier = snoozeIdentifier(source: source, fireDate: plan.fireDate)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        let center = UNUserNotificationCenter.current()
        let fireDate = plan.fireDate
        center.getPendingNotificationRequests { pending in
            if NotificationActions.coveredBySibling(origin: origin, fireDate: fireDate, pending: pending) {
                DispatchQueue.main.async { completion() }
                return
            }
            let drop = NotificationActions.snoozesToDrop(pending: pending, origin: origin)
            if !drop.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: drop)
            }
            center.add(request) { _ in
                DispatchQueue.main.async { completion() }
            }
        }
        return true
    }

    // MARK: 重排時清掉來源不在了的

    /// 重排時要拿掉的再提醒：識別字是「snooze.<kind>」開頭、而 isLive 說來源不在了。
    /// kind：「mtg.」「evt.」「wealth.」。isLive 拿到 (origin, source, stamp)：origin＝原本那則的 identifier、
    /// source＝「mtg.<UUID>」…、stamp＝個人事件的時間指紋（其他是 nil）。少了 origin 的給空字串
    static func staleSnoozes(in pending: [UNNotificationRequest], kind: String,
                             isLive: (_ origin: String, _ source: String, _ stamp: String?) -> Bool) -> [String] {
        var out: [String] = []
        for request in pending where request.identifier.hasPrefix(snoozePrefix + kind) {
            let info = request.content.userInfo
            let origin = (info[AnyHashable(originKey)] as? String) ?? ""
            let source = (info[AnyHashable(sourceKey)] as? String) ?? ""
            let stamp = info[AnyHashable(stampKey)] as? String
            if !isLive(origin, source, stamp) { out.append(request.identifier) }
        }
        return out
    }
}
