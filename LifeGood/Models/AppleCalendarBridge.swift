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

    private init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        // 監聽外部變更（其他 App 改、iCloud 同步等）
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            self?.lastChange = Date()
        }
    }

    deinit {
        if let token = notificationObserver {
            NotificationCenter.default.removeObserver(token)
        }
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

    /// 刪除指定 EKEvent
    func delete(eventIdentifier: String) {
        guard hasAccess,
              let event = eventStore.event(withIdentifier: eventIdentifier) else { return }
        do {
            try eventStore.remove(event, span: .futureEvents, commit: true)
        } catch {
            // ignore
        }
    }
}
