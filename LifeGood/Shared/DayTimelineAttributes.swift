import Foundation
import ActivityKit

// MARK: - 今日行程時間軸 · Live Activity 資料（v25.377）
//
// 這個檔案同時屬於「主 App」與「LifeGoodWidgets」兩個 target：
// 主 App 負責產生內容並啟動／更新 Live Activity，Widget Extension 負責畫出來。
//
// ⚠️ ContentState 有 4KB 上限（ActivityKit 硬限制），超過會直接啟動失敗。
//    所以場次數量與文字長度都要先裁切，見 DayTimelineSnapshotBuilder。

/// 時間軸上的一站（一場會議）
struct TimelineStop: Codable, Hashable, Identifiable {
    /// 會議場次的識別字串（會議 id + 場次時間）
    var id: String
    var title: String
    var start: Date
    var durationMinutes: Int
    /// 誰的會議（部屬姓名）
    var owner: String
    /// 內容摘要：議程項目或備註，已裁切
    var detail: String

    var end: Date { start.addingTimeInterval(TimeInterval(durationMinutes * 60)) }

    init(id: String, title: String, start: Date, durationMinutes: Int,
         owner: String, detail: String) {
        self.id = id
        self.title = title
        self.start = start
        self.durationMinutes = durationMinutes
        self.owner = owner
        self.detail = detail
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

    /// 收合狀態的右側文字：進行中顯示結束時間，否則顯示下一場開始時間
    static func compactTrailing(_ state: DayTimelineAttributes.ContentState,
                                now: Date = Date()) -> String {
        if let cur = state.currentStop(now) { return time(cur.end) }
        if let next = state.nextStop(now) { return time(next.start) }
        return "\(state.stops.count) 場"
    }
}

// MARK: - App Group

enum DayTimelineAppGroup {
    /// ⚠️ 這個值必須與兩個 target 的 entitlements、以及 Apple Developer 後台註冊的
    ///    App Group 識別碼完全一致，改了要三個地方一起改。
    static let identifier = "group.com.lifegood.app"

    static var defaults: UserDefaults? { UserDefaults(suiteName: identifier) }

    /// Live Activity 之外的備援快照：extension 需要在沒有 Activity 的情況下
    /// （例如未來要做鎖定畫面小工具）也讀得到今天的行程。
    static let snapshotKey = "day_timeline_snapshot"
}
