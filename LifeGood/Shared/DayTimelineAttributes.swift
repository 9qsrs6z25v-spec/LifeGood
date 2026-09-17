import Foundation
import ActivityKit

// MARK: - 今日行程時間軸 · Live Activity 資料（v25.377）
//
// 這個檔案同時屬於「主 App」與「LifeGoodWidgets」兩個 target：
// 主 App 負責產生內容並啟動／更新 Live Activity，Widget Extension 負責畫出來。
//
// ⚠️ ContentState 有 4KB 上限（ActivityKit 硬限制），超過會直接啟動失敗。
//    所以場次數量與文字長度都要先裁切，見 DayTimelineSnapshotBuilder。

/// [v25.380] 這一站是哪裡來的。決定點的顏色與詳情裡的來源標籤。
enum TimelineStopKind: String, Codable, Hashable {
    /// 部屬的會議
    case meeting
    /// 我的行事曆裡的個人事件
    case personal
    /// [v25.383] iOS 系統行事曆（EventKit）讀進來的事件
    case appleCalendar

    var label: String {
        switch self {
        case .meeting:       return "部屬會議"
        case .personal:      return "我的行事曆"
        case .appleCalendar: return "系統行事曆"
        }
    }
}

/// 時間軸上的一站
struct TimelineStop: Codable, Hashable, Identifiable {
    /// 場次的識別字串（來源 id + 場次時間）
    var id: String
    var title: String
    var start: Date
    var durationMinutes: Int
    /// 部屬會議＝部屬姓名；個人事件＝地點，沒填就用事件分類
    var owner: String
    /// 內容摘要：議程項目或備註，已裁切
    var detail: String
    var kind: TimelineStopKind

    var end: Date { start.addingTimeInterval(TimeInterval(durationMinutes * 60)) }

    init(id: String, title: String, start: Date, durationMinutes: Int,
         owner: String, detail: String, kind: TimelineStopKind) {
        self.id = id
        self.title = title
        self.start = start
        self.durationMinutes = durationMinutes
        self.owner = owner
        self.detail = detail
        self.kind = kind
    }
}

struct DayTimelineAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// 今天的場次，已依時間排序
        var stops: [TimelineStop]
        /// 展開時要顯示哪一站的詳情（小點點按下去就改這個值）
        var selectedIndex: Int
        /// 這份快照產生的時間；主 App 重新整理時會更新
        var generatedAt: Date

        init(stops: [TimelineStop], selectedIndex: Int = 0, generatedAt: Date = Date()) {
            self.stops = stops
            self.selectedIndex = selectedIndex
            self.generatedAt = generatedAt
        }

        /// 夾在有效範圍內：場次被移除後舊的索引可能已經越界
        var safeIndex: Int {
            guard !stops.isEmpty else { return 0 }
            return min(max(selectedIndex, 0), stops.count - 1)
        }

        var selected: TimelineStop? {
            stops.isEmpty ? nil : stops[safeIndex]
        }

        /// 時間軸左端＝第一場開始，右端＝最後一場結束。
        /// 只有一場時左右會重疊，所以至少撐開一小時，點才不會擠在同一個位置。
        var axisStart: Date { stops.first?.start ?? Date() }
        var axisEnd: Date {
            guard let last = stops.last else { return Date().addingTimeInterval(3600) }
            let end = last.end
            let minimum = axisStart.addingTimeInterval(3600)
            return max(end, minimum)
        }

        /// 某一站在軸上的相對位置（0...1）
        func position(of stop: TimelineStop) -> Double {
            let span = axisEnd.timeIntervalSince(axisStart)
            guard span > 0 else { return 0 }
            let offset = stop.start.timeIntervalSince(axisStart)
            return min(max(offset / span, 0), 1)
        }

        /// 現在時間在軸上的位置；還沒開始或已經結束時回 nil（不畫游標）
        func nowPosition(_ now: Date = Date()) -> Double? {
            let span = axisEnd.timeIntervalSince(axisStart)
            guard span > 0, now >= axisStart, now <= axisEnd else { return nil }
            return now.timeIntervalSince(axisStart) / span
        }

        /// 目前進行中的那一站（給收合狀態用）
        func currentStop(_ now: Date = Date()) -> TimelineStop? {
            stops.first { $0.start <= now && now < $0.end }
        }

        /// 下一站
        func nextStop(_ now: Date = Date()) -> TimelineStop? {
            stops.first { $0.start > now }
        }
    }

    /// 這份 Live Activity 代表哪一天（例：9/16（三））
    var dayLabel: String

    init(dayLabel: String) { self.dayLabel = dayLabel }
}

// MARK: - 共用格式

enum DayTimelineFormat {
    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "HH:mm"
        return f
    }()

    static func time(_ d: Date) -> String { clock.string(from: d) }

    /// 「14:00–15:00」
    static func range(_ stop: TimelineStop) -> String {
        time(stop.start) + "–" + time(stop.end)
    }

    /// [v25.382] 時長：「45 分」「1 小時」「1.5 小時」
    static func duration(_ stop: TimelineStop) -> String {
        let m = stop.durationMinutes
        if m < 60 { return "\(m) 分" }
        let hours = Double(m) / 60
        if hours == hours.rounded() { return String(format: "%.0f 小時", hours) }
        return String(format: "%.1f 小時", hours)
    }

    /// 收合狀態的右側文字：進行中顯示結束時間，否則顯示下一場開始時間。
    /// [v25.381] 兩者都沒有＝今天的行程都跑完了。原本回「N 場」看不出這件事，
    /// 而且現在軸上不只會議，「場」這個量詞也不對了。
    static func compactTrailing(_ state: DayTimelineAttributes.ContentState,
                                now: Date = Date()) -> String {
        if let cur = state.currentStop(now) { return time(cur.end) }
        if let next = state.nextStop(now) { return time(next.start) }
        return "已結束"
    }
}

// MARK: - 深層連結

enum DayTimelineLink {
    /// [v25.381] 點靈動島一定是開 App（長按才展開，這是系統行為改不了），
    /// 那至少要開到有用的地方——「我的行事曆」就是這條時間軸的完整版。
    static let today = URL(string: "lifegood://today")

    /// App 端收到這個網址時要切到哪三個位置。
    /// MainTabView 的導覽狀態全部是 @AppStorage，直接寫 UserDefaults 就會生效，
    /// 不需要碰任何 navigation stack。
    static func apply(_ url: URL) -> Bool {
        guard url.scheme == "lifegood", url.host == "today" else { return false }
        let d = UserDefaults.standard
        d.set("life", forKey: "appMode")
        d.set("career", forKey: "life_feature")
        d.set("calendar", forKey: "management_feature")
        return true
    }
}

// MARK: - 為什麼這裡沒有 App Group
//
// v25.377 曾經加了一個 App Group，只為了把快照多存一份「給未來的鎖定畫面小工具用」。
// 那個小工具還不存在，卻讓兩個 target 都背上 application-groups entitlement——
// App Group 必須先在 Apple Developer 後台註冊、並掛到兩個 App ID 上，
// 否則 App Store 的封裝簽章會直接失敗（v25.379 遇到的就是這件事）。
//
// Live Activity 的資料是透過 ActivityAttributes / ContentState 走 ActivityKit 傳遞的，
// 本來就不需要 App Group。等真的要做小工具時再加，不要提前借債。
