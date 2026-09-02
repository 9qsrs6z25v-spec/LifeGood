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

        await addScheduleRequests(for: event)
    }

    /// 啟動時把所有事件的提醒重排一次，讓既有事件升級到新版的 body / 多 trigger / 截止日邏輯。
    /// 一次取得 pendingNotificationRequests，批次移除後再逐一建立，避免 N 次系統 API 呼叫。
    func rescheduleAll(events: [PersonalEvent]) async {
        let authorized = await requestAuthorization()
        guard authorized else { return }

        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let prefixes = Set(events.map { $0.id.uuidString })
        let toRemove = pending.map(\.identifier).filter { id in
            prefixes.contains(where: { id == $0 || id.hasPrefix($0 + "#") })
        }
        if !toRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: toRemove)
        }

        for event in events where event.reminderMinutes >= 0 {
            await addScheduleRequests(for: event)
        }
    }

    /// 僅新增排程請求，不做移除（移除由呼叫端負責）。
    private func addScheduleRequests(for event: PersonalEvent) async {
        let center = UNUserNotificationCenter.current()
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
                // baseFire 永遠是「事件原始那一次」的時間，不會隨時間推進；enumerateFires
                // 內建 61 筆安全上限，若 baseFire 已是很久以前（例如每天重複的事件建立超過
                // 61 天），61 筆全部列在過去，下面 filter 後變空陣列，導致這個仍在截止日內、
                // 理應繼續提醒的事件從此再也排不到任何通知。先跳過已過去的次數，
                // 從第一個 >= 現在的次數開始列舉，61 筆上限才會涵蓋到未來的次數。
                //
                // 注意：advanceToNextOccurrence 回傳的日期可能已被 Calendar 夾過（例如每月 31 號
                // 事件跳到 2 月會夾成 28 號）。若把這個「已夾過的日期」當成 enumerateFires 的新錨點，
                // 後續每一期都會改成從 28 號往後加，永久與 occurs(on:)（永遠錨定在原始 baseFire）脫勾、
                // 導致通知時間與行事曆畫面顯示的日期不同。因此改為只取起始的期數索引，
                // enumerateFires 仍錨定在原始 baseFire 計算每一期，避免二次夾日造成的漂移。
                let (_, startIndex) = advanceToNextOccurrence(
                    from: baseFire, onOrAfter: Date(), recurrence: event.recurrence, cal: cal
                )
                let fires = enumerateFires(baseStart: baseFire, startIndex: startIndex, end: endDate, recurrence: event.recurrence, cal: cal)
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

    /// 把 start 依 recurrence 步進跳過所有早於 now 的次數，回傳第一個 >= now 的次數
    /// （start 已經 >= now 時原樣回傳）。用於 enumerateFires 前先把列舉起點移到未來，
    /// 避免 61 筆安全上限被已過去的次數用完。
    /// 回傳第一個 >= now 的次數，以及該次數距離 start 的期數索引（給 enumerateFires 當起點用，
    /// 避免呼叫端拿「已被 Calendar 夾過的日期」當新錨點而與 start 脫鉤）。
    private func advanceToNextOccurrence(
        from start: Date,
        onOrAfter now: Date,
        recurrence: EventRecurrence,
        cal: Calendar
    ) -> (date: Date, index: Int) {
        guard start < now else { return (start, 0) }
        let step: Calendar.Component
        switch recurrence {
        case .daily:   step = .day
        case .weekly:  step = .weekOfYear
        case .monthly: step = .month
        case .yearly:  step = .year
        case .none:    return (start, 0)
        }
        var current = start
        var n = 0
        var safety = 0
        // 上限給到遠大於實務上會遇到的天數差距（daily 步進下相當於 10 年以上）
        // 每次都從原始 start 重新加 n 期，而非鏈式從上一步結果累加：Calendar 對月/年天數不足
        // 會把結果夾到當月最後一天（例如每月 31 號遇到 2 月會夾到 28 號），若鏈式累加，
        // 這個被夾住的日期會變成下一步的起點，往後每個月都固定卡在 28 號，
        // 永久遺失原本 31 號的錨點，與行事曆畫面顯示的日期脫勾。
        while current < now, safety < 4000 {
            n += 1
            guard let next = cal.date(byAdding: step, value: n, to: start) else { break }
            current = next
            safety += 1
        }
        return (current, n)
    }

    /// 從 baseStart 開始（第 startIndex 期），依 recurrence 一步一步往後算實際觸發時間，直到超過 end。
    /// 一律以原始 baseStart 為錨點重新加期數，不可用中途已被 Calendar 夾過的日期當新錨點，
    /// 否則會與 PersonalEvent.occurs(on:)（永遠錨定在原始日期）算出的日期脫勾。
    private func enumerateFires(
        baseStart: Date,
        startIndex: Int,
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
        case .none:    return [baseStart]
        }
        guard let first = cal.date(byAdding: step, value: startIndex, to: baseStart) else { return [] }
        var fires: [Date] = []
        var current = first
        var n = startIndex
        var safety = 0
        // 呼叫端只取前 60 筆（iOS 系統通知上限），上限設 61 避免多餘計算（原 5000 會浪費高達 4940 次）
        while current <= end, safety < 61 {
            fires.append(current)
            n += 1
            guard let next = cal.date(byAdding: step, value: n, to: baseStart) else { break }
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
