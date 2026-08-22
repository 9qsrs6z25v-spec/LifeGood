import Foundation
import EventKit
import Combine
import UIKit

/// 把 iOS 系統行事曆（EventKit）橋接到 LifeGood，供 MyCalendarView 顯示用。
/// 只讀取，不修改使用者的行事曆。
@MainActor
final class AppleCalendarBridge: ObservableObject {
    static let shared = AppleCalendarBridge()

    @Published private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined
    /// 行事曆內容變更時更新，讓 SwiftUI view 重新讀取
    @Published private(set) var lastChange: Date = Date()

    private let eventStore = EKEventStore()
    private var notificationObserver: NSObjectProtocol?
    // EKEventStoreChanged 對同一次使用者操作常連續觸發多次（iOS 已知行為），
    // 用短暫防抖合併成一次 lastChange 更新，避免 MyCalendarView 為同一操作
    // 連續全頁重繪多次造成畫面閃爍。
    private var changeDebounceTimer: Timer?

    private init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        // 監聽外部變更（其他 App 改、iCloud 同步等）
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleChangeUpdate()
        }
    }

    private func scheduleChangeUpdate() {
        changeDebounceTimer?.invalidate()
        changeDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.lastChange = Date()
        }
    }

    deinit {
        if let token = notificationObserver {
            NotificationCenter.default.removeObserver(token)
        }
        changeDebounceTimer?.invalidate()
    }

    /// 是否拿到讀取權限（iOS 17 改名為 .fullAccess，舊版用 .authorized）
    var hasAccess: Bool {
        if #available(iOS 17.0, *) {
            return authorizationStatus == .fullAccess
        }
        return authorizationStatus == .authorized
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    func refreshStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    /// 請求存取權；notDetermined 才會跳系統 prompt
    func requestAccess() async {
        do {
            if #available(iOS 17.0, *) {
                _ = try await eventStore.requestFullAccessToEvents()
            } else {
                _ = try await eventStore.requestAccess(to: .event)
            }
        } catch {
            // 忽略；refreshStatus 會反映最新狀態
        }
        refreshStatus()
    }

    /// 抓某段時間範圍的事件
    func events(in start: Date, end: Date) -> [EKEvent] {
        guard hasAccess else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        return eventStore.events(matching: predicate)
    }

    /// 抓某天（00:00 ~ 隔天 00:00）的事件
    func events(forDay date: Date, calendar cal: Calendar = .current) -> [EKEvent] {
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events(in: start, end: end)
    }

    /// 開系統行事曆 App 並跳到指定時間。`calshow:<seconds-since-2001>` URL scheme。
    func openInAppleCalendar(at date: Date) {
        let interval = Int(date.timeIntervalSinceReferenceDate)  // since 2001-01-01
        guard let url = URL(string: "calshow:\(interval)") else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - 寫入相關

    /// 可寫入的行事曆清單（給 PersonalEventEditor picker 用）
    var writableCalendars: [EKCalendar] {
        guard hasAccess else { return [] }
        return eventStore.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .sorted { $0.title < $1.title }
    }

    /// 預設要寫入的行事曆 ID
    var defaultCalendarId: String? {
        eventStore.defaultCalendarForNewEvents?.calendarIdentifier
    }

    /// 把 PersonalEvent 寫入或更新到 Apple 行事曆，回傳對應的 eventIdentifier
    func writeOrUpdate(from pe: PersonalEvent, calendarId: String?) -> String? {
        guard hasAccess else { return nil }

        let event: EKEvent = {
            if let existingId = pe.ekEventIdentifier,
               let found = eventStore.event(withIdentifier: existingId) {
                return found
            }
            return EKEvent(eventStore: eventStore)
        }()

        // 設定行事曆
        if let id = calendarId,
           let target = eventStore.calendar(withIdentifier: id),
           target.allowsContentModifications {
            event.calendar = target
        } else if event.calendar == nil {
            event.calendar = eventStore.defaultCalendarForNewEvents
        }
        guard event.calendar != nil else { return nil }

        // 基本欄位
        let cal = Calendar.current
        event.title = pe.title.isEmpty ? pe.kind.rawValue : pe.title
        event.notes = pe.note.isEmpty ? nil : pe.note
        event.location = pe.location.isEmpty ? nil : pe.location
        event.startDate = pe.date
        if pe.durationMinutes > 0 {
            event.endDate = cal.date(byAdding: .minute, value: pe.durationMinutes, to: pe.date) ?? pe.date
            event.isAllDay = false
        } else {
            // 全日：endDate 設為當日 23:59 同一天
            let startOfDay = cal.startOfDay(for: pe.date)
            event.endDate = cal.date(byAdding: .day, value: 1, to: startOfDay)?.addingTimeInterval(-1) ?? pe.date
            event.isAllDay = true
        }

        // 提醒
        event.alarms = nil
        if pe.reminderMinutes >= 0 {
            event.alarms = [EKAlarm(relativeOffset: -Double(pe.reminderMinutes * 60))]
        }

        // 重複
        let freq: EKRecurrenceFrequency? = {
            switch pe.recurrence {
            case .daily: return .daily
            case .weekly: return .weekly
            case .monthly: return .monthly
            case .yearly: return .yearly
            case .none: return nil
            }
        }()
        if let f = freq {
            let endRule: EKRecurrenceEnd? = pe.recurrenceEndDate.map { EKRecurrenceEnd(end: $0) }
            event.recurrenceRules = [EKRecurrenceRule(recurrenceWith: f, interval: 1, end: endRule)]
        } else {
            event.recurrenceRules = nil
        }

        do {
            try eventStore.save(event, span: .futureEvents, commit: true)
            return event.eventIdentifier
        } catch {
            return nil
        }
    }

    /// 建立（或更新）部屬生日提醒：全日事件、每年重複，提前 daysBefore 天的上午 9:00
    /// 跳提醒。years＝連續幾年（nil＝無限期，不設迄日）。回傳 eventIdentifier（失敗 nil）。
    /// 首次發生日取「下一次生日」（今年生日已過則從明年起算）。
    ///
    /// 兩個刻意的做法：
    /// 1. 循環迄止用 **明確迄日（UNTIL）** 而非次數（COUNT）——部分行事曆來源
    ///    （Google／Exchange）對 COUNT 規則的展開顯示不一致，曾造成「設 5 年
    ///    只看得到前兩年」；迄日行為在所有來源一致。
    /// 2. 更新走 **先建新、成功後刪舊**——反覆改同一個循環事件的規則在部分來源
    ///    會殘留舊佔位；建立失敗時舊提醒保留不動。
    func writeBirthdayReminder(existingId: String?, name: String, birthday: Date,
                               daysBefore: Int, years: Int?, calendarId: String? = nil) -> String? {
        guard hasAccess else { return nil }
        let event = EKEvent(eventStore: eventStore)
        // 指定行事曆（設定頁 Picker 選的）優先；沒選或已失效 fallback 預設
        if let id = calendarId,
           let target = eventStore.calendar(withIdentifier: id),
           target.allowsContentModifications {
            event.calendar = target
        } else {
            event.calendar = eventStore.defaultCalendarForNewEvents
        }
        guard event.calendar != nil else { return nil }

        let cal = Calendar.current
        var comps = cal.dateComponents([.month, .day], from: birthday)
        comps.year = cal.component(.year, from: Date())
        var next = cal.date(from: comps) ?? birthday
        if cal.startOfDay(for: next) < cal.startOfDay(for: Date()) {
            comps.year = (comps.year ?? 0) + 1
            next = cal.date(from: comps) ?? next
        }
        let startOfDay = cal.startOfDay(for: next)

        event.title = "🎂 \(name) 生日"
        event.notes = "美好人生・部屬生日提醒"
        event.startDate = startOfDay
        event.endDate = cal.date(byAdding: .day, value: 1, to: startOfDay)?.addingTimeInterval(-1) ?? startOfDay
        event.isAllDay = true
        // 全日事件的 alarm 以當天 00:00 為基準：提前 N 天的上午 9:00 提醒
        event.alarms = [EKAlarm(relativeOffset: TimeInterval(-daysBefore * 86400 + 9 * 3600))]
        let end: EKRecurrenceEnd? = years.map { y in
            // 連續 N 年＝首次發生日起含當年共 N 個生日；迄日取最後一個生日的隔天
            let lastBirthday = cal.date(byAdding: .year, value: max(1, y) - 1, to: startOfDay) ?? startOfDay
            let until = cal.date(byAdding: .day, value: 1, to: lastBirthday) ?? lastBirthday
            return EKRecurrenceEnd(end: until)
        }
        event.recurrenceRules = [EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: end)]
        do {
            try eventStore.save(event, span: .futureEvents, commit: true)
            // ⚠️ eventIdentifier 在部分來源（iCloud 同步中／Google／Exchange）save 後
            // 當下可能是 nil（EventKit 已知怪癖）——事件建成功了、id 卻拿不到，
            // 造成「行事曆有事件但鈴鐺不亮」。calendarItemIdentifier 一定拿得到，
            // 當備援存起來；查找/刪除端兩種 id 都認得（resolveEvent）。
            let newId = event.eventIdentifier ?? event.calendarItemIdentifier
            // 掃掉這個人其餘的生日提醒（含先前 id 沒記到的孤兒與被取代的舊提醒）
            removeBirthdayEvents(named: event.title ?? "", excludingItemId: event.calendarItemIdentifier)
            return newId
        } catch {
            return nil
        }
    }

    /// 用儲存的 id 找回事件：先當 eventIdentifier 查，查不到再當 calendarItemIdentifier 查
    ///（生日提醒的 id 兩種都可能，見 writeBirthdayReminder 註解）。
    private func resolveEvent(_ id: String) -> EKEvent? {
        if let e = eventStore.event(withIdentifier: id) { return e }
        return eventStore.calendarItem(withIdentifier: id) as? EKEvent
    }

    /// 清掉同名的生日提醒事件（標題＋App 備註標記辨識；排除剛建立的那一個）。
    /// 往後掃 400 天必含每年循環的下一次發生，從該發生以 futureEvents 移除即砍掉整串。
    private func removeBirthdayEvents(named title: String, excludingItemId: String) {
        guard !title.isEmpty else { return }
        let start = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: 400, to: start) else { return }
        let pred = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        var removed = false
        for e in eventStore.events(matching: pred)
        where e.title == title && e.notes == "美好人生・部屬生日提醒"
            && e.calendarItemIdentifier != excludingItemId {
            try? eventStore.remove(e, span: .futureEvents, commit: false)
            removed = true
        }
        if removed { try? eventStore.commit() }
    }

    /// 既有事件目前所屬的行事曆 id（生日提醒設定頁預填用）
    func calendarId(ofEvent id: String) -> String? {
        guard hasAccess, let e = resolveEvent(id) else { return nil }
        return e.calendar?.calendarIdentifier
    }

    /// 刪除指定 EKEvent（id 可為 eventIdentifier 或 calendarItemIdentifier，見 resolveEvent）
    func delete(eventIdentifier: String) {
        guard hasAccess,
              let event = resolveEvent(eventIdentifier) else { return }
        do {
            try eventStore.remove(event, span: .futureEvents, commit: true)
        } catch {
            // ignore
        }
    }
}

// MARK: - Apple 提醒事項橋接（家庭待辦＋部屬任務 → 提醒事項，單向）

/// 把 App 內的待辦同步到 Apple 提醒事項。**單向**（App → 提醒事項）：
/// 在 App 打勾/改期/刪除會同步過去；在提醒事項那邊改不會流回來——
/// 反向同步需要常駐監聽與衝突解決，先不做，UI 文案要說清楚。
///
/// 所有提醒集中放在名為「美好人生」的提醒事項清單，
/// 好認、也不污染使用者原本的清單。
@MainActor
final class ReminderBridge: ObservableObject {
    static let shared = ReminderBridge()

    private let store = EKEventStore()
    @Published private(set) var status: EKAuthorizationStatus =
        EKEventStore.authorizationStatus(for: .reminder)

    /// 同步總開關（UserDefaults；家庭待辦與部屬任務共用）
    static let enabledKey = "reminders_sync_enabled"
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey); objectWillChange.send() }
    }

    var hasAccess: Bool {
        if #available(iOS 17.0, *) { return status == .fullAccess }
        return status == .authorized
    }
    var isDenied: Bool { status == .denied || status == .restricted }

    private init() {}

    func refreshStatus() {
        status = EKEventStore.authorizationStatus(for: .reminder)
    }

    /// 請求提醒事項權限；回傳是否可用
    @discardableResult
    func requestAccess() async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                _ = try await store.requestFullAccessToReminders()
            } else {
                _ = try await store.requestAccess(to: .reminder)
            }
        } catch {}
        refreshStatus()
        return hasAccess
    }

    /// 新增或更新一則提醒。回傳提醒 id（呼叫端存回 task.reminderId）；失敗回傳原 id。
    /// EventKit 工作佇列。**所有查詢/寫入都在這裡跑，不佔主執行緒**——
    /// calendarItem(withIdentifier:)／save(commit:) 是對系統 remindd 服務的
    /// 同步往返，直接在主執行緒呼叫會讓「新增任務」按下去卡零點幾秒
    ///（v25.246 的教訓：使用者回報按新增比以前頓很多）。
    /// EKEventStore 本身跨執行緒安全；取出的物件只在同一個佇列裡用完就丟。
    private static let workQueue = DispatchQueue(label: "lifegood.reminder.bridge", qos: .utility)

    /// 開關＋權限的快速判斷（nonisolated：背景佇列與呼叫端都要能問）
    nonisolated static var enabledAndAuthorized: Bool {
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return false }
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if #available(iOS 17.0, *) { return status == .fullAccess }
        return status == .authorized
    }

    /// 新增或更新一則提醒（背景佇列執行）。回傳提醒 id；失敗回傳原 id。
    /// 未開同步或沒權限時不動作（回原 id），呼叫端不必自行判斷。
    nonisolated func upsertAsync(id existingId: String?, title: String, due: Date?,
                                 notes: String?, isCompleted: Bool) async -> String? {
        guard Self.enabledAndAuthorized else { return existingId }
        let store = self.store
        return await withCheckedContinuation { cont in
            Self.workQueue.async {
                let reminder: EKReminder
                if let existingId,
                   let found = store.calendarItem(withIdentifier: existingId) as? EKReminder {
                    reminder = found
                } else {
                    reminder = EKReminder(eventStore: store)
                    guard let cal = Self.appCalendar(in: store) else {
                        cont.resume(returning: existingId); return
                    }
                    reminder.calendar = cal
                }
                reminder.title = title.isEmpty ? "未命名待辦" : title
                reminder.notes = notes
                if let due {
                    // 帶時分的截止時間；整點的鬧鈴提醒交給提醒事項本身的規則
                    reminder.dueDateComponents = Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute], from: due)
                } else {
                    reminder.dueDateComponents = nil
                }
                reminder.isCompleted = isCompleted
                do {
                    try store.save(reminder, commit: true)
                    cont.resume(returning: reminder.calendarItemIdentifier)
                } catch {
                    cont.resume(returning: existingId)
                }
            }
        }
    }

    /// 刪除提醒（背景佇列、射後不理；找不到就當作已刪，不報錯）
    nonisolated func deleteAsync(id: String?) {
        guard let id, Self.enabledAndAuthorized else { return }
        let store = self.store
        Self.workQueue.async {
            guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
            try? store.remove(reminder, commit: true)
        }
    }

    /// 「美好人生」提醒清單（背景佇列版；找不到就建一個，失敗退預設清單）
    nonisolated private static func appCalendar(in store: EKEventStore) -> EKCalendar? {
        let all = store.calendars(for: .reminder)
        if let mine = all.first(where: { $0.title == "美好人生" }) { return mine }
        let cal = EKCalendar(for: .reminder, eventStore: store)
        cal.title = "美好人生"
        cal.source = store.defaultCalendarForNewReminders()?.source ?? all.first?.source
        do {
            try store.saveCalendar(cal, commit: true)
            return cal
        } catch {
            return store.defaultCalendarForNewReminders()
        }
    }
}
