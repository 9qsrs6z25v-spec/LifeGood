import Foundation
import UserNotifications

// MARK: - 通知〔看議程〕（手錶 v1，v25.574；watch/judge.md §3.5（工程，v1）；watch/build/v1/brief.md G2-5）
//
// 只屬於 LifeGoodWatch（整個手錶 target 只有這個檔 import UserNotifications，pbxwatch_check M 段）。
// 通知是 iPhone 排的（NotificationManager／MeetingReminders），iPhone 鎖著、錶戴著時轉到手錶；按鈕也是 iPhone 定義的
// （NotificationActions：部屬會議 LG_MEETING 〔5 分鐘後再提醒〕〔看議程〕）。
//   • 〔5 分鐘後再提醒〕是背景動作：在 iPhone 背景跑（v3），手錶這裡收不到。
//   • 〔看議程〕是前景動作：在手錶上按會打開手錶 App、交到這裡 → 用 userInfo["meeting_id"]（會議 UUID 字串，
//     WatchLink.meetingIdKey＝DeepLinkRouter.meetingNotificationKey）配包裡那一場（WatchText.meetingStopId），開細節頁。
//     點通知本身（UNNotificationDefaultActionIdentifier）也一樣開那一場。
// 手錶 App 自己不排通知、不要求通知權限；字串不抄 NotificationActions.swift（手錶不編那個檔，v3 §5-5），用 WatchLink。

final class WatchNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WatchNotificationDelegate()

    private override init() {
        super.init()
    }

    /// WatchAppDelegate 的 init 裝（App 啟動完成前就要設好，才接得到「按了通知把 App 叫起來」那一次）
    static func install() {
        UNUserNotificationCenter.current().delegate = shared
    }

    /// 手錶 App 開著時收到通知：照樣顯示（跟 iPhone AppDelegate 同一組）
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    /// 〔看議程〕或點通知本身：有會議 id 就開手錶 App 那一場的細節；其他通知只是打開 App（第一頁）
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let meeting = response.notification.request.content.userInfo[WatchLink.meetingIdKey] as? String
        let opensMeeting = action == WatchLink.viewAgendaAction || action == UNNotificationDefaultActionIdentifier
        if let meetingId = meeting, opensMeeting {
            Task { @MainActor in
                WatchModel.shared.openMeeting(meetingId: meetingId)
            }
        }
        completionHandler()
    }
}
