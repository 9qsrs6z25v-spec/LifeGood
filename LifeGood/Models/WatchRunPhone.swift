import Foundation
import HealthKit

// MARK: - iPhone 這一頭的手錶跑步：「我跑完了」的旗子、「用手錶記／用 iPhone 記」（手錶 v5，v25.582；只屬於主 App）
//
// watch/judge.md §2.12（沒存成）、§5.7 最後一段（我跑完了）、§8 v5 做好標準 5、6、附錄 B；watch/build/v5/brief.md §2；
// 規則照 scratchpad/watch/build/v5/sim_v5.py 的同名函式（改了兩邊一起改）。
//
// • WatchRunFlags：手錶送來的「我跑完了」（ranWorkout：Apple 健康編號＋結束時間）、「沒存成」（unsavedRun）記在 App Group 的
//   UserDefaults（WidgetShared.defaults）。**被手錶叫醒的冷啟動也會寫這裡**（WatchBridge 的 delegate 方法）：只碰 UserDefaults，
//   不碰 AppStores、LifeStore、HealthSyncCenter（judge §7.8-6；pkg_keys_check D 段擋 WatchBridge）。寫完在主執行緒發
//   WatchRunFlags.changed：健康頁開著就馬上同步（HealthView 收）。
//   – 我跑完了：pending［編號 → 收到的時間］；24 小時內每次健康頁回前景都找一次（HealthSyncCenter.syncForWatchRun），
//     帶進來了（或你刪掉、不再帶進來）就拿掉；空字串＝手錶存好了但讀不到編號（同步一次就拿掉）
//   – 沒存成：手錶說有一趟存不進 Apple 健康、留在手錶上 → 健康頁最上面一行（unsavedBanner）；手錶〔再存一次〕存好送 ranWorkout
//     或送 unsavedRun＝0 就清掉；7 天沒消息也清掉（手錶 RunStash 那一份 7 天就不要了）
//   – 手錶上次跑完（設定頁 Apple Watch 段「手錶上次跑完 06:45」）
// • WatchRunStarter：健康頁「▶ 開始跑步」、跑步畫面〔開始〕戴著手錶時先問「用手錶記（有心率，可以不帶手機）／用 iPhone 記」，
//   可勾「記住我的選擇」（UserDefaults.standard，只這支 iPhone；設定頁 Apple Watch 段改）。用手錶記＝
//   HKHealthStore.startWatchApp(toHandle:)：手錶 LifeGood 被叫起來、打開準備頁（不自己開跑，WatchAppDelegate.handle）；
//   **iPhone 不開記錄器、不多記一筆**。叫不起來就回一句話，畫面上可以改用 iPhone 記。
//   iPad、Mac 上沒有手錶（WatchBridge 不啟動，isWatchAppInstalled 一直是 false）：一律用 iPhone 記、不問。

// MARK: - 我跑完了、沒存成（手錶 → iPhone）

enum WatchRunFlags {
    /// JSON［Apple 健康編號（""＝讀不到編號）: 收到的時間（1970 起的秒）］
    static let pendingKey = "watch_run_pending"
    /// 手錶說有一趟沒存成的時間（1970 起的秒，Double）；0／沒有＝沒有
    static let unsavedKey = "watch_run_unsaved"
    /// 手錶上次跑完（那一趟結束的時間，1970 起的秒，Double）
    static let lastRanKey = "watch_run_last_ran"
    /// 「我跑完了」多久以內每次回前景再找
    static let pendingWindow: TimeInterval = 24 * 3600
    /// 「沒存成」多久沒消息就不寫了（手錶那一份 7 天就丟）
    static let unsavedKeep: TimeInterval = 7 * 86_400
    /// 旗子變了（主執行緒發；健康頁收到就看要不要馬上同步、最上面那一行要不要出現）
    static let changed = Notification.Name("LifeGoodWatchRunFlagsChanged")

    /// 健康頁最上面那一行（judge §2.12「手錶上有 1 趟沒存進 Apple 健康，打開手錶上的 LifeGood 再存一次」）
    static let unsavedBanner = "手錶上有 1 趟沒存進 Apple 健康，打開手錶上的 LifeGood 再存一次"

    private static var defaults: UserDefaults? { WidgetShared.defaults }

    /// 手錶說「我跑完了」（存好、或〔再存一次〕存好）：記編號、清掉「沒存成」、記上次跑完的時間
    static func noteRan(workoutId: String, endedAt: Date?, now: Date) {
        var map = pendingMap()
        map[workoutId.trimmingCharacters(in: .whitespacesAndNewlines)] = now.timeIntervalSince1970
        savePending(pruned(map, now: now))
        defaults?.set(0.0, forKey: unsavedKey)
        if let end = endedAt, end.timeIntervalSince1970 > 0 {
            defaults?.set(end.timeIntervalSince1970, forKey: lastRanKey)
        }
        post()
    }

    /// 手錶說有一趟沒存成（on＝true）／沒有了（false）
    static func noteUnsaved(_ on: Bool, now: Date) {
        defaults?.set(on ? now.timeIntervalSince1970 : 0.0, forKey: unsavedKey)
        post()
    }

    /// 24 小時內收到、還沒帶進來的編號（含 ""）；舊的順手拿掉
    static func pending(now: Date) -> [String] {
        let map = pendingMap()
        let kept = pruned(map, now: now)
        if kept.count != map.count { savePending(kept) }
        return kept.keys.sorted()
    }

    /// 帶進來了（或不再帶進來）的那幾個拿掉
    static func clear(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        var map = pendingMap()
        for id in ids { map.removeValue(forKey: id) }
        savePending(map)
    }

    /// 健康頁最上面要不要寫「手錶上有 1 趟沒存進 Apple 健康…」（7 天內說過、之後沒存好）
    static func hasUnsaved(now: Date) -> Bool {
        let t = defaults?.double(forKey: unsavedKey) ?? 0
        guard t > 0 else { return false }
        return now.timeIntervalSince1970 - t < unsavedKeep
    }

    /// 手錶上次跑完的時間；沒收過 nil
    static var lastRanAt: Date? {
        let t = defaults?.double(forKey: lastRanKey) ?? 0
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    // MARK: 內部

    private static func pendingMap() -> [String: Double] {
        guard let data = defaults?.data(forKey: pendingKey),
              let map = try? JSONDecoder().decode([String: Double].self, from: data) else { return [:] }
        return map
    }

    private static func savePending(_ map: [String: Double]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults?.set(data, forKey: pendingKey)
    }

    /// 只留 24 小時內的（收到的時間比現在晚的〔手機時間被改過〕也留著）
    static func pruned(_ map: [String: Double], now: Date) -> [String: Double] {
        let cut = now.timeIntervalSince1970 - pendingWindow
        return map.filter { $0.value >= cut }
    }

    /// 主執行緒發 changed（WatchBridge 的 delegate 方法已經包在 Task { @MainActor }；保險起見再排到主佇列）
    private static func post() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: WatchRunFlags.changed, object: nil)
        }
    }
}

// MARK: - 用手錶記／用 iPhone 記

@MainActor
enum WatchRunStarter {
    /// 「記住我的選擇」（UserDefaults.standard：只這支 iPhone；設定頁 Apple Watch 段可以改回「每次問」）
    enum Choice: String, CaseIterable, Identifiable {
        case ask
        case watch
        case phone

        var id: String { rawValue }

        /// 設定頁那一列的選項字
        var title: String {
            switch self {
            case .ask: return "每次問"
            case .watch: return "用手錶記"
            case .phone: return "用 iPhone 記"
            }
        }
    }

    /// 按「▶ 開始跑步」要做什麼
    enum Route: Equatable {
        /// 先問（彈出 WatchRunChoiceSheet）
        case ask
        /// 直接叫手錶（記住選了手錶）
        case watch
        /// 照舊用 iPhone 記
        case phone
    }

    static let choiceKey = "watch_run_start_choice"
    /// 剛在健康頁選了「用 iPhone 記」：跑步畫面的〔開始〕不再問一次（10 分鐘內）
    static let phoneChosenKey = "watch_run_phone_chosen_at"
    static let phoneChosenWindow: TimeInterval = 10 * 60

    // MARK: 字（View 不自己拼）

    static let askTitle = "這一趟用哪個記？"
    static let watchOption = "用手錶記"
    static let watchOptionNote = "有心率，可以不帶手機"
    static let phoneOption = "用 iPhone 記"
    static let phoneOptionNote = "地圖跟著你走，鎖定畫面看得到"
    static let rememberTitle = "記住我的選擇"
    static let rememberNote = "之後可以在 設定 › Apple Watch 改"
    static let startingText = "正在叫醒手錶…"
    static let startedText = "已經在手錶上打開準備頁，在手錶上按〔開始〕"
    /// Apple 健康同步沒開：手錶那一趟帶不進 LifeGood（「健身」App 照樣有）
    static let startedNoSyncText = "已經在手錶上打開準備頁。健康頁的「Apple 健康」同步打開，跑完才帶得進 LifeGood"
    static let usePhoneTitle = "改用 iPhone 記"
    static let okTitle = "好"
    /// 設定頁那一列
    static let settingsRowTitle = "開始跑步時"

    /// 叫不起來的那一句
    static func failedText(_ reason: String) -> String {
        let r = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.isEmpty ? "沒叫醒手錶，可以改用 iPhone 記" : "沒叫醒手錶（" + r + "），可以改用 iPhone 記"
    }

    // MARK: 判斷

    /// 記住的選擇（沒設定過＝每次問）
    static var choice: Choice {
        let raw = UserDefaults.standard.string(forKey: choiceKey) ?? ""
        return Choice(rawValue: raw) ?? .ask
    }

    static func setChoice(_ c: Choice) {
        UserDefaults.standard.set(c.rawValue, forKey: choiceKey)
    }

    /// 這支 iPhone 配了手錶、手錶上裝了 LifeGood（WCSession activated＋isPaired＋isWatchAppInstalled，WatchBridge 算好的）；
    /// iPad、Mac 是 false
    static var watchReady: Bool {
        WatchBridge.shared.isWatchAppInstalled && HKHealthStore.isHealthDataAvailable()
    }

    /// 剛選了「用 iPhone 記」（健康頁那一問）：記下時間，跑步畫面〔開始〕10 分鐘內不再問
    static func notePhoneChosen(now: Date) {
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: phoneChosenKey)
    }

    static func phoneChosenRecently(now: Date) -> Bool {
        let t = UserDefaults.standard.double(forKey: phoneChosenKey)
        guard t > 0 else { return false }
        let gap = now.timeIntervalSince1970 - t
        return gap >= 0 && gap < phoneChosenWindow
    }

    /// 有路線的四種才交給手錶（重訓、其他有氧照舊用 iPhone）
    static func canUseWatch(_ sport: WorkoutSport) -> Bool {
        sport == .run || sport == .walk || sport == .bike || sport == .hike
    }

    /// 按「▶ 開始跑步」（fromRunScreen＝跑步畫面的〔開始〕：剛在健康頁選過 iPhone 的不再問）。sim_v5.py start_route
    static func route(sport: WorkoutSport, now: Date, fromRunScreen: Bool) -> Route {
        guard watchReady, canUseWatch(sport) else { return .phone }
        switch choice {
        case .watch:
            return .watch
        case .phone:
            return .phone
        case .ask:
            if fromRunScreen && phoneChosenRecently(now: now) { return .phone }
            return .ask
        }
    }

    // MARK: 叫手錶

    private static let store = HKHealthStore()

    /// 這種運動的設定（室外；同手錶 WorkoutManager.configuration）
    static func configuration(for sport: WorkoutSport) -> HKWorkoutConfiguration {
        let c = HKWorkoutConfiguration()
        switch sport {
        case .walk:
            c.activityType = .walking
        case .bike:
            c.activityType = .cycling
        case .hike:
            c.activityType = .hiking
        default:
            c.activityType = .running
        }
        c.locationType = .outdoor
        return c
    }

    /// 叫手錶 LifeGood 打開準備頁（HKHealthStore.startWatchApp(toHandle:)，iOS 10 起；系統在背景叫醒手錶 App、
    /// 交給 WKApplicationDelegate.handle(_:)）。成功回 nil；失敗回一句給使用者看的話（failedText）。
    /// iPhone 這邊什麼都不記（RunTracker 不開）
    static func startOnWatch(sport: WorkoutSport) async -> String? {
        guard watchReady else { return failedText("") }
        do {
            try await store.startWatchApp(toHandle: configuration(for: sport))
            return nil
        } catch {
            return failedText(error.localizedDescription)
        }
    }

    /// 成功之後那一句（Apple 健康同步沒開要提醒，不然手錶那一趟帶不進 LifeGood）
    static func startedMessage(syncOn: Bool) -> String {
        syncOn ? startedText : startedNoSyncText
    }
}
