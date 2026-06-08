import Foundation
import UserNotifications

/// 個人行事曆事件提醒管理器：負責申請權限與排程 / 取消通知。
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()
    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d HH:mm"; return f
    }()

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

    /// 取消事件對應的所有通知（含多筆 #N 形式的子請求）。fire-and-forget；
    /// `schedule()` 內部會再額外 await 一次以保證 race-free。
    nonisolated func cancel(eventId: UUID) {
        let center = UNUserNotificationCenter.current()
        let prefix = eventId.uuidString
        center.getPendingNotificationRequests { reqs in
            let ids = reqs.map(\.identifier).filter { $0 == prefix || $0.hasPrefix(prefix + "#") }
            if !ids.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
    }

    /// 為事件排定通知（會先清掉舊的）。已支援：
    /// - 一次性事件：單一 trigger
    /// - 重複事件無截止日：repeats: true 的單一 trigger
    /// - 重複事件有截止日：逐次列出實際發生時間，分別建一次性 trigger（上限 60 筆，避開 iOS 64 上限）
    func schedule(_ event: PersonalEvent) async {
        let center = UNUserNotificationCenter.current()
        await Self.awaitRemovePending(prefix: event.id.uuidString)

        guard event.reminderMinutes >= 0 else { return }
        let authorized = await requestAuthorization()
        guard authorized else { return }

        let cal = Calendar.current
        let baseFire = cal.date(byAdding: .minute, value: -event.reminderMinutes, to: event.date) ?? event.date

        switch event.recurrence {
        case .none:
            if baseFire <= Date() { return }
            await addRequest(event: event, fireDate: baseFire, repeats: false, indexSuffix: nil, infiniteRecurrence: false)
        case .daily, .weekly, .monthly, .yearly:
            if let endDate = event.recurrenceEndDate {
                // 有截止日 → 逐次列出每次的觸發時間，個別排
                if endDate < Date() { return }
                let fires = enumerateFires(start: baseFire, end: endDate, recurrence: event.recurrence, cal: cal)
                    .filter { $0 > Date() }
                let capped = Array(fires.prefix(60))
                for (i, f) in capped.enumerated() {
                    await addRequest(event: event, fireDate: f, repeats: false, indexSuffix: i, infiniteRecurrence: false)
                }
            } else {
                // 無截止日 → repeats: true 的單一 trigger
                let comps = recurringComponents(from: baseFire, recurrence: event.recurrence, cal: cal)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                let content = makeContent(event: event, fireDate: nil, infiniteRecurrence: true)
                let req = UNNotificationRequest(identifier: event.id.uuidString, content: content, trigger: trigger)
                try? await center.add(req)
            }
        }
    }

    /// 啟動時把所有事件的提醒重排一次，讓既有事件升級到新版的 body / 多 trigger / 截止日邏輯
    func rescheduleAll(events: [PersonalEvent]) async {
        for event in events where event.reminderMinutes >= 0 {
            await schedule(event)
        }
    }

    // MARK: - 內部

    private static func awaitRemovePending(prefix: String) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0 == prefix || $0.hasPrefix(prefix + "#") }
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private func addRequest(
        event: PersonalEvent,
        fireDate: Date,
        repeats: Bool,
        indexSuffix: Int?,
        infiniteRecurrence: Bool
    ) async {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: repeats)
        let content = makeContent(event: event, fireDate: fireDate, infiniteRecurrence: infiniteRecurrence)
        let id: String = {
            if let i = indexSuffix { return "\(event.id.uuidString)#\(i)" }
            return event.id.uuidString
        }()
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(req)
    }

    private func makeContent(
        event: PersonalEvent,
        fireDate: Date?,
        infiniteRecurrence: Bool
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = event.title.isEmpty ? event.kind.rawValue : event.title
        content.body = makeBody(for: event, fireDate: fireDate, infiniteRecurrence: infiniteRecurrence)
        content.sound = .default
        return content
    }

    private func makeBody(
        for event: PersonalEvent,
        fireDate: Date?,
        infiniteRecurrence: Bool
    ) -> String {
        let kindLabel = event.kind.rawValue
        let durStr: String = {
            if event.durationMinutes == 0 { return "全日" }
            if event.durationMinutes >= 60 {
                let h = Double(event.durationMinutes) / 60.0
                return String(format: "%.1f 小時", h)
            }
            return "\(event.durationMinutes) 分鐘"
        }()

        let timeStr: String
        if infiniteRecurrence {
            // 無限重複事件不放具體 M/d，避免使用者誤以為通知是「某月某日」的；
            // 改放重複規則 + 時間（全日事件就只放規則）
            let pattern = recurrenceLabel(for: event)
            if event.durationMinutes == 0 {
                timeStr = pattern
            } else {
                timeStr = "\(pattern) · \(Self.timeFormatter.string(from: event.date))"
            }
        } else {
            // 一次性事件，或重複事件已展開成多筆 → 用該筆實際的觸發時間
            let dateToShow = fireDate ?? event.date
            let fmt = event.durationMinutes == 0 ? Self.dateFormatter : Self.dateTimeFormatter
            timeStr = fmt.string(from: dateToShow)
        }

        let pieces = [kindLabel, timeStr, durStr] + (event.note.isEmpty ? [] : [event.note])
        return pieces.joined(separator: " · ")
    }

    /// 把 fireDate 拆成 UNCalendarNotificationTrigger 用的 DateComponents
    private func recurringComponents(
        from fireDate: Date,
        recurrence: EventRecurrence,
        cal: Calendar
    ) -> DateComponents {
        var comps = DateComponents()
        switch recurrence {
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
            break
        }
        return comps
    }

    /// 從 start 開始，依 recurrence 一步一步往後算實際觸發時間，直到超過 end
    private func enumerateFires(
        start: Date,
        end: Date,
        recurrence: EventRecurrence,
        cal: Calendar
    ) -> [Date] {
        let step: Calendar.Component
        switch recurrence {
        case .daily:   step = .day
        case .weekly:  step = .weekOfYear
        case .monthly: step = .month
        case .yearly:  step = .year
        case .none:    return [start]
        }
        var fires: [Date] = []
        var current = start
        var safety = 0
        while current <= end, safety < 5000 {
            fires.append(current)
            guard let next = cal.date(byAdding: step, value: 1, to: current) else { break }
            current = next
            safety += 1
        }
        return fires
    }

    /// 顯示在通知 body 的重複規則文字
    private func recurrenceLabel(for event: PersonalEvent) -> String {
        let cal = Calendar.current
        switch event.recurrence {
        case .daily:
            return "每天"
        case .weekly:
            let names = ["日", "一", "二", "三", "四", "五", "六"]
            let wd = cal.component(.weekday, from: event.date)
            if wd >= 1, wd <= 7 { return "每週\(names[wd - 1])" }
            return "每週"
        case .monthly:
            return "每月 \(cal.component(.day, from: event.date)) 日"
        case .yearly:
            return "每年 \(cal.component(.month, from: event.date))/\(cal.component(.day, from: event.date))"
        case .none:
            return ""
        }
    }
}
