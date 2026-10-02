import Foundation
import SwiftUI
import AppIntents
// AlarmKit 是 iOS 26 才有的框架，但 import 本身不受部署目標限制——
// 實際使用一律由 @available(iOS 26.1, *) 把關。
// 若這行報「no such module」，代表 Xcode 版本太舊，那就是該升 Xcode 的訊號。
import AlarmKit

// MARK: - 會議提醒：通知 or 鬧鐘（v25.455）
//
// 使用者要求：會議提醒除了通知，也要有「像鬧鐘那樣、要人去按掉」的選項。
//
// iOS 上能做到「真的會響、穿透靜音與專注模式、要按停止才停」的只有兩條路：
//   • 關鍵警示（Critical Alerts）——需要向 Apple 個別申請特殊權利，
//     實務上只發給醫療／公共安全／居家安防類 App，生活記錄 App 幾乎必被拒。
//   • AlarmKit（iOS 26 起）——第三方 App 的正式鬧鐘 API，不需要特別申請，
//     只要 Info.plist 有 NSAlarmKitUsageDescription 並取得使用者授權。
// 所以走 AlarmKit。低於 iOS 26.1 沒有這個 API，會自動退回通知（見 effective）。
//
// ⚠️ 為什麼關卡是 26.1 而不是 AlarmKit 本身的 26.0：
//    警示內容的建構子 AlarmPresentation.Alert(title:secondaryButton:secondaryButtonBehavior:)
//    是 iOS 26.1 才有的。26.0 只有 init(title:stopButton:secondaryButton:...)，
//    而那個已經被 Apple 標記 deprecated——停止鈕現在由系統自己提供，不該由 App 傳。
//    為了多支援 26.0 去用一個已棄用的建構子，等於自己種一顆未來會爆的雷；
//    26.0 與 26.1 之間的使用者本來就極少（26.1 已經發佈將近一年），
//    而且他們還是會收到通知，不是什麼都沒有。
//    ⚠️ 不要為了這件事去動專案的 IPHONEOS_DEPLOYMENT_TARGET（18.0）——
//       那會讓整支 App 放棄 iOS 18～26.0 的所有使用者。該升的是這裡的關卡。
//
// ⚠️ 刻意只用 alert 狀態、不做 countdown presentation。
//    Apple 的文件寫得很明白：「AlarmKit expects a widget extension if an app
//    supports a countdown presentation. Otherwise, the system may unexpectedly
//    dismiss alarms and fail to alert.」只有 alert 就不需要 widget extension，
//    也就不必把 AlarmAttributes 的 metadata 型別搬進 Widget target。
//    哪天要做倒數膠囊，記得同時補上 widget extension，不然鬧鐘會變成不響。

// MARK: - 全域預設

/// 「通知 or 鬧鐘」的全域預設值。單筆事件／會議可以各自覆寫（存 nil＝跟隨這裡）。
enum MeetingAlertPreference {

    static let globalKey = "meeting_alert_style"

    /// 全域預設。出廠是通知——升級後不該有人的手機突然開始響。
    static var globalDefault: MeetingAlertStyle {
        get {
            let raw = UserDefaults.standard.string(forKey: globalKey) ?? ""
            return MeetingAlertStyle(rawValue: raw) ?? .notification
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: globalKey) }
    }

    /// 單筆的覆寫值（nil＝跟隨全域）換算成實際要用的那一種。
    ///
    /// 這一層還會做「降級」：使用者選了鬧鐘但這台手機低於 iOS 26.1，
    /// 就退回通知。不降級的話那些提醒會完全不存在——寧可響得不夠凶，
    /// 也不能安靜地什麼都不發生。
    static func effective(_ override: MeetingAlertStyle?) -> MeetingAlertStyle {
        let wanted = override ?? globalDefault
        if wanted == .alarm, !MeetingAlarmScheduler.isSupported { return .notification }
        return wanted
    }
}

// MARK: - 一則待排的提醒

/// 來源（事件／會議場次）攤平之後的一則提醒。
/// 排程層只看這個結構，不必知道它來自哪裡——通知與鬧鐘兩條路才能共用同一份挑選邏輯。
struct ReminderJob: Identifiable, Hashable {
    /// 穩定的識別字串。通知用它當 request identifier；鬧鐘用它對應回來源。
    let key: String
    let title: String
    let body: String
    /// 要在什麼時候響
    let fireDate: Date
    /// 這一則來自哪一場會議（給鬧鐘的「看會議」按鈕用；個人事件沒有就是 nil）
    let meetingId: UUID?

    var id: String { key }
}

// MARK: - 排程中樞

/// 把「所有該提醒的東西」算出來，再分流到通知或鬧鐘。
///
/// 為什麼要有這一層：通知與鬧鐘的額度都很小（通知是每個 App 64 則待送、
/// 鬧鐘有 AlarmKit 自己的上限），而「哪些該排」的邏輯（週期展開、改期、取消、
/// 已過去的場次）兩邊完全一樣。分開寫兩份，遲早會長歪成兩種行為。
enum ReminderCenter {

    /// 往後看幾天。再遠的下次打開 App 時會重新排——不預先排滿是因為額度有限，
    /// 而且行程經常改，排太遠只是排一堆過期的東西。
    private static let horizonDays = 30

    /// 部屬會議的通知額度。iOS 每個 App 只保留最近的 64 則待送通知，
    /// 超過的會被靜靜丟掉；個人事件那邊已經會用掉不少，所以這裡要克制。
    private static let meetingNotificationLimit = 20

    /// 全部重排。App 啟動、回到前景、以及任何一筆提醒被改動後呼叫。
    ///
    /// 一律整批重算而不是增量維護：提醒的來源有週期會議的展開、改期、加開場次、
    /// 取消場次，增量維護要處理的狀態轉移太多，而整批重算很便宜（純記憶體計算）。
    @MainActor
    static func rebuildAll(events: [PersonalEvent], subordinates: [Subordinate]) async {
        let now = Date()
        let jobs = meetingJobs(subordinates: subordinates, now: now)

        // 1) 個人事件。通知型走既有那條路（它有「無限重複用單一 repeats trigger」
        //    這種額度上的優化，不該為了統一而丟掉）；鬧鐘型改走鬧鐘。
        await NotificationManager.shared.rescheduleAll(events: events)

        // 2) 部屬會議的通知型
        let notificationJobs = jobs
            .filter { MeetingAlertPreference.effective(styleOfMeeting($0, subordinates)) == .notification }
        await NotificationManager.shared.scheduleMeetingJobs(
            Array(notificationJobs.prefix(meetingNotificationLimit)))

        // 3) 鬧鐘型（個人事件 + 部屬會議一起排，因為鬧鐘的額度是共用的）
        let alarmJobs = (eventAlarmJobs(events: events, now: now) + jobs.filter {
            MeetingAlertPreference.effective(styleOfMeeting($0, subordinates)) == .alarm
        }).sorted { $0.fireDate < $1.fireDate }
        await MeetingAlarmScheduler.shared.rebuild(alarmJobs)
    }

    /// job 對應的那場會議目前設的樣式
    private static func styleOfMeeting(_ job: ReminderJob,
                                       _ subordinates: [Subordinate]) -> MeetingAlertStyle? {
        guard let mid = job.meetingId else { return nil }
        for sub in subordinates {
            if let m = sub.meetings.first(where: { $0.id == mid }) { return m.alertStyle }
        }
        return nil
    }

    // MARK: 挑出該提醒的東西

    /// 部屬會議：展開未來 horizonDays 天內的場次，取還沒到的那些。
    static func meetingJobs(subordinates: [Subordinate], now: Date) -> [ReminderJob] {
        let cal = Calendar.current
        let from = cal.date(byAdding: .day, value: -1, to: now) ?? now
        let horizon = cal.date(byAdding: .day, value: horizonDays, to: now) ?? now
        var out: [ReminderJob] = []

        for sub in subordinates {
            for meeting in sub.meetings where meeting.reminderMinutes >= 0 {
                for occ in meeting.expandedOccurrences(from: from, horizon: horizon) {
                    guard !occ.isCancelled else { continue }
                    let fire = cal.date(byAdding: .minute,
                                        value: -meeting.reminderMinutes, to: occ.date) ?? occ.date
                    guard fire > now else { continue }
                    // 有週期的會議，議程項目掛在各場次上；不重複的會議掛在會議本身
                    let itemCount = occ.items.isEmpty ? meeting.items.count : occ.items.count
                    out.append(ReminderJob(
                        key: "mtg_\(meeting.id.uuidString)_\(Int(occ.date.timeIntervalSince1970))",
                        title: meeting.topic.isEmpty ? "部屬會議" : meeting.topic,
                        body: meetingBody(sub: sub, meeting: meeting,
                                          at: occ.date, itemCount: itemCount),
                        fireDate: fire,
                        meetingId: meeting.id))
                }
            }
        }
        return out.sorted { $0.fireDate < $1.fireDate }
    }

    /// 個人事件裡選了鬧鐘的那些。
    ///
    /// 逐日問 occurs(on:) 而不是自己重算一套週期規則——重複規則的真相只有
    /// PersonalEvent 自己知道（含截止日、含被 Calendar 夾過的月底日期），
    /// 另寫一份一定會跟畫面上顯示的日期對不起來。30 天 × 事件數的迴圈很便宜。
    static func eventAlarmJobs(events: [PersonalEvent], now: Date) -> [ReminderJob] {
        let cal = Calendar.current
        var out: [ReminderJob] = []
        let alarmEvents = events.filter {
            $0.reminderMinutes >= 0 && MeetingAlertPreference.effective($0.alertStyle) == .alarm
        }
        guard !alarmEvents.isEmpty else { return [] }

        for dayOffset in 0...horizonDays {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            for event in alarmEvents where event.occurs(on: day, calendar: cal) {
                let start = event.occurrenceDate(on: day, calendar: cal)
                let fire = cal.date(byAdding: .minute,
                                    value: -event.reminderMinutes, to: start) ?? start
                guard fire > now else { continue }
                out.append(ReminderJob(
                    key: "evt_\(event.id.uuidString)_\(Int(start.timeIntervalSince1970))",
                    title: event.title.isEmpty ? event.kind.rawValue : event.title,
                    body: eventBody(event, at: start),
                    fireDate: fire,
                    meetingId: nil))
            }
        }
        return out.sorted { $0.fireDate < $1.fireDate }
    }

    // MARK: 文字

    private static let dtFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d HH:mm"
        return f
    }()

    private static func meetingBody(sub: Subordinate, meeting: SubordinateMeeting,
                                    at date: Date, itemCount: Int) -> String {
        var pieces = [sub.name.isEmpty ? "部屬" : sub.name, dtFmt.string(from: date)]
        if meeting.durationMinutes > 0 { pieces.append("\(meeting.durationMinutes) 分鐘") }
        if itemCount > 0 { pieces.append("\(itemCount) 個議程項目") }
        return pieces.joined(separator: " · ")
    }

    private static func eventBody(_ event: PersonalEvent, at date: Date) -> String {
        var pieces = [event.kind.rawValue, dtFmt.string(from: date)]
        if event.durationMinutes > 0 { pieces.append("\(event.durationMinutes) 分鐘") }
        let place = event.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !place.isEmpty { pieces.append(place) }
        return pieces.joined(separator: " · ")
    }
}

// MARK: - AlarmKit 鬧鐘

/// AlarmKit 的封裝。所有 AlarmKit 的呼叫都關在這支裡面，
/// 而且集中在底下那個 @available(iOS 26.1, *) 的 extension 裡——
/// 這個框架很新，簽名有變動時只有一處要改。
final class MeetingAlarmScheduler: ObservableObject {

    static let shared = MeetingAlarmScheduler()
    private init() {}

    /// 最近一次失敗的原因，設定頁會顯示
    @Published private(set) var lastError: String?
    /// 目前排了幾個鬧鐘
    @Published private(set) var scheduledCount = 0

    /// 一次最多掛幾個鬧鐘。AlarmKit 有自己的上限（超過丟 maximumLimitReached），
    /// 文件沒寫是多少，所以保守抓。反正每次打開 App 都會重排，
    /// 排滿未來好幾週沒有意義。
    private let maxAlarms = 8

    /// 這台手機支援不支援真鬧鐘
    static var isSupported: Bool {
        if #available(iOS 26.1, *) { return true }
        return false
    }

    // MARK: 對外（版本無關的門面）

    @MainActor
    func requestAuthorization() async -> Bool {
        if #available(iOS 26.1, *) { return await requestAuthorizationImpl() }
        lastError = "這台手機的 iOS 版本沒有鬧鐘功能（需要 iOS 26.1 以上），提醒會自動改用通知。"
        return false
    }

    @MainActor
    var authorizationText: String {
        if #available(iOS 26.1, *) { return authorizationTextImpl }
        return "需要 iOS 26.1 以上"
    }

    @MainActor
    func rebuild(_ jobs: [ReminderJob]) async {
        guard Self.isSupported else { return }
        if #available(iOS 26.1, *) {
            await rebuildImpl(Array(jobs.prefix(maxAlarms)))
        }
    }

    @MainActor
    func cancelAll() async {
        if #available(iOS 26.1, *) { cancelAllImpl() }
        scheduledCount = 0
    }

    /// 設定頁的「試響一次」：10 秒後響，讓使用者先看清楚鬧鐘長什麼樣、
    /// 確認自己真的要用這個模式，而不是等到開會前才第一次被嚇到。
    @MainActor
    func fireTestAlarm() async {
        guard Self.isSupported else {
            lastError = "這台手機的 iOS 版本沒有鬧鐘功能（需要 iOS 26.1 以上）。"
            return
        }
        if #available(iOS 26.1, *) { await fireTestAlarmImpl() }
    }
}

// MARK: - AlarmKit 實作（唯一碰到 AlarmKit 的地方）

@available(iOS 26.1, *)
extension MeetingAlarmScheduler {

    /// AlarmAttributes 是泛型，metadata 就算傳 nil 也得有個具體型別來定住泛型參數，
    /// 所以放一個空的。欄位之後要加（例如部屬姓名）再加。
    struct MeetingAlarmMetadata: AlarmMetadata {
        init() {}
    }

    @MainActor
    fileprivate func requestAuthorizationImpl() async -> Bool {
        // 已經授權就不要再呼叫 requestAuthorization——這段每次啟動／回前景都會跑到
        if case .authorized = AlarmManager.shared.authorizationState { return true }
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            if state != .authorized {
                lastError = "鬧鐘權限沒有開。要到「設定 →  LifeGood」把鬧鐘打開，否則提醒會改用通知。"
            } else {
                lastError = nil
            }
            return state == .authorized
        } catch {
            lastError = "要鬧鐘權限時失敗：\(error.localizedDescription)"
            return false
        }
    }

    @MainActor
    fileprivate var authorizationTextImpl: String {
        switch AlarmManager.shared.authorizationState {
        case .authorized:    return "已允許"
        case .denied:        return "已拒絕"
        case .notDetermined: return "尚未詢問"
        @unknown default:    return "未知"
        }
    }

    @MainActor
    fileprivate func rebuildImpl(_ jobs: [ReminderJob]) async {
        // 沒有鬧鐘要排、而且從來沒問過鬧鐘權限 → 完全不要碰 AlarmKit。
        // 不然從不用鬧鐘的人每次啟動都會為了「清掉舊鬧鐘」去讀一次鬧鐘清單，
        // 讀失敗還會在設定頁留一個他看不懂、也不需要處理的錯誤訊息。
        if jobs.isEmpty, case .notDetermined = AlarmManager.shared.authorizationState {
            scheduledCount = 0
            return
        }
        // 先全部清掉再重排。這支 App 排的鬧鐘全部由這裡管理，
        // 所以 AlarmManager 裡看到的就是我們自己的，可以安全清空。
        cancelAllImpl()

        guard !jobs.isEmpty else { scheduledCount = 0; return }
        guard await requestAuthorizationImpl() else { scheduledCount = 0; return }

        var done = 0
        for job in jobs {
            guard job.fireDate > Date() else { continue }
            do {
                let alert = AlarmPresentation.Alert(
                    title: LocalizedStringResource(stringLiteral: job.title),
                    secondaryButton: AlarmButton(text: "打開 LifeGood",
                                                 textColor: .white,
                                                 systemImageName: "calendar"),
                    secondaryButtonBehavior: .custom)
                let attributes = AlarmAttributes(
                    presentation: AlarmPresentation(alert: alert),
                    metadata: MeetingAlarmMetadata(),
                    tintColor: Color.orange)
                let config = AlarmManager.AlarmConfiguration.alarm(
                    schedule: .fixed(job.fireDate),
                    attributes: attributes,
                    secondaryIntent: OpenMeetingAlarmIntent(meetingId: job.meetingId?.uuidString ?? ""))
                _ = try await AlarmManager.shared.schedule(id: UUID(), configuration: config)
                done += 1
            } catch {
                // 撞到上限就停手，不要繼續對每一筆都丟同一個錯
                if let e = error as? AlarmManager.AlarmError,
                   case .maximumLimitReached = e {
                    lastError = "系統的鬧鐘數量已達上限，只排到最近的 \(done) 場。"
                    break
                }
                lastError = "排鬧鐘失敗：\(error.localizedDescription)"
                break
            }
        }
        scheduledCount = done
    }

    @MainActor
    fileprivate func cancelAllImpl() {
        // 正在響的那一個不能砍——使用者可能剛被叫醒、還沒按停止。
        // 回到前景就重排是常態（App 啟動、切回來都會），砍掉等於幫他把鬧鐘關了。
        for alarm in (try? AlarmManager.shared.alarms) ?? [] {
            if case .alerting = alarm.state { continue }
            try? AlarmManager.shared.cancel(id: alarm.id)
        }
    }

    @MainActor
    fileprivate func fireTestAlarmImpl() async {
        guard await requestAuthorizationImpl() else { return }
        do {
            let alert = AlarmPresentation.Alert(
                title: "LifeGood 鬧鐘測試",
                secondaryButton: AlarmButton(text: "打開 LifeGood",
                                             textColor: .white,
                                             systemImageName: "calendar"),
                secondaryButtonBehavior: .custom)
            let attributes = AlarmAttributes(
                presentation: AlarmPresentation(alert: alert),
                metadata: MeetingAlarmMetadata(),
                tintColor: Color.orange)
            let config = AlarmManager.AlarmConfiguration.alarm(
                schedule: .fixed(Date().addingTimeInterval(10)),
                attributes: attributes)
            _ = try await AlarmManager.shared.schedule(id: UUID(), configuration: config)
            lastError = nil
        } catch {
            lastError = "試響失敗：\(error.localizedDescription)"
        }
    }
}

// MARK: - 鬧鐘上的「打開 LifeGood」

/// 鬧鐘警示畫面上的第二顆按鈕。按下去開 App，有帶會議 id 就直接落到那場會議。
///
/// 走 LiveActivityIntent 是 AlarmKit 的要求（secondaryIntent 的型別就是它）。
/// 實際的落點交給 v25.454 做的 DeepLinkRouter，不另外長一套導覽邏輯。
@available(iOS 26.1, *)
struct OpenMeetingAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "打開 LifeGood"
    static var description = IntentDescription("打開 LifeGood 看這場會議")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "會議")
    var meetingId: String

    init() { meetingId = "" }
    init(meetingId: String) { self.meetingId = meetingId }

    func perform() async throws -> some IntentResult {
        let mid = meetingId
        await MainActor.run {
            AppNavigation.goToMyCalendar()
            guard !mid.isEmpty else { return }
            // 與靈動島走同一條反查路徑，不另長一套
            DeepLinkRouter.shared.requestTimelineStop(
                DayTimelineLink.stopIdForMeeting(uuidString: mid))
        }
        return .result()
    }
}

// MARK: - 「提醒方式」三態列

/// 跟隨全域／通知／鬧鐘。
///
/// 放在這個檔案而不是某個 View 檔裡：個人事件編輯器與部屬會議編輯器都要用，
/// 放其中一邊另一邊就得跨檔引用，兩份遲早長歪。
///（同檔放 View 的先例：Models/TripWeather.swift 裡的 TripWeatherChip。）
///
/// 「跟隨全域」是 nil 而不是一個 case——與這支 App 的樣式覆寫同一套語意。
struct MeetingAlertStylePicker: View {
    @Binding var selection: MeetingAlertStyle?

    var body: some View {
        Picker("提醒方式", selection: $selection) {
            Text("跟隨全域（\(MeetingAlertPreference.globalDefault.displayName)）")
                .tag(MeetingAlertStyle?.none)
            ForEach(MeetingAlertStyle.allCases) { s in
                Label(s.displayName, systemImage: s.icon).tag(MeetingAlertStyle?.some(s))
            }
        }
        Text(hint)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private var hint: String {
        let wanted = selection ?? MeetingAlertPreference.globalDefault
        if wanted == .alarm, !MeetingAlarmScheduler.isSupported {
            return "這台手機的 iOS 版本沒有鬧鐘功能（需要 iOS 26.1 以上），這一筆會自動改用通知。"
        }
        return wanted.hint
    }
}
