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
}
