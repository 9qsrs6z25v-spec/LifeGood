import Foundation
import UserNotifications

/// 個人行事曆事件提醒管理器：負責申請權限與排程 / 取消通知。
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    // MARK: - 權限

    /// 請求通知權限（已授權則直接 true，被拒絕則 false）
    @discardableResult
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default:
            return false
        }
    }

    // MARK: - 排程 / 取消

    /// 取消事件對應的所有通知
    func cancel(eventId: UUID) {
        let center = UNUserNotificationCenter.current()
        let id = eventId.uuidString
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// 為事件排定通知（會先取消舊的）
    func schedule(_ event: PersonalEvent) async {
        let center = UNUserNotificationCenter.current()
        cancel(eventId: event.id)

        // 不需要提醒
        guard event.reminderMinutes >= 0 else { return }

        // 確認權限
        let authorized = await requestAuthorization()
        guard authorized else { return }

        let trigger = makeTrigger(for: event)
        guard let trigger else { return }

        let content = UNMutableNotificationContent()
        content.title = event.title.isEmpty ? event.kind.rawValue : event.title
        content.body = makeBody(for: event)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: event.id.uuidString,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    // MARK: - 內部

    private func makeBody(for event: PersonalEvent) -> String {
        let f = DateFormatter()
        f.dateFormat = event.durationMinutes == 0 ? "M/d" : "M/d HH:mm"
        let timeStr = f.string(from: event.date)
        let kindLabel = event.kind.rawValue
        let durStr: String = {
            if event.durationMinutes == 0 { return "全日" }
            if event.durationMinutes >= 60 {
                let h = Double(event.durationMinutes) / 60.0
                return String(format: "%.1f 小時", h)
            }
            return "\(event.durationMinutes) 分鐘"
        }()
        let pieces = [kindLabel, timeStr, durStr] + (event.note.isEmpty ? [] : [event.note])
        return pieces.joined(separator: " · ")
    }

    /// 把事件的「提醒時間」轉換為 NotificationTrigger
    private func makeTrigger(for event: PersonalEvent) -> UNNotificationTrigger? {
        let cal = Calendar.current
        // 一次性事件 → 用絕對時間 trigger
        if event.recurrence == .none {
            let fireDate = cal.date(byAdding: .minute, value: -event.reminderMinutes, to: event.date) ?? event.date
            // 已過時間 → 不排
            if fireDate <= Date() { return nil }
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        }

        // 重複事件 → 用 DateComponents + repeats: true
        let fireDate = cal.date(byAdding: .minute, value: -event.reminderMinutes, to: event.date) ?? event.date
        var comps = DateComponents()
        switch event.recurrence {
        case .daily:
            comps.hour = cal.component(.hour, from: fireDate)
            comps.minute = cal.component(.minute, from: fireDate)
        case .weekly:
            comps.weekday = cal.component(.weekday, from: fireDate)
            comps.hour = cal.component(.hour, from: fireDate)
            comps.minute = cal.component(.minute, from: fireDate)
        case .monthly:
            comps.day = cal.component(.day, from: fireDate)
            comps.hour = cal.component(.hour, from: fireDate)
            comps.minute = cal.component(.minute, from: fireDate)
        case .yearly:
            comps.month = cal.component(.month, from: fireDate)
            comps.day = cal.component(.day, from: fireDate)
            comps.hour = cal.component(.hour, from: fireDate)
            comps.minute = cal.component(.minute, from: fireDate)
        case .none:
            return nil
        }
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
    }
}
