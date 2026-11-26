// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.646 mac6 G3b] 記帳小鎮第二批的日子規則（judge_mac.md §T6-1～§T6-8）：今天沒花錢打卡、記帳月曆、每週回顧、自己的紀錄、徽章 +4。
//
// • 一律 MacGameRules.calendar；新函式都收 now:、calendar:。日子字 "2026-11-26"（照 WorkoutProgress.swift:671-686 讀法：
//   拆三段、範圍檢查、中午 12 點組回、startOfDay、再寫一次要等於原字才收）。
// • 不碰分帳（新增行不准提那幾個字，§T6-0）；沒有金額、名字；讀日誌只准 kind == .add、key、at（在 MacGameModel）。
// • `dayMark` 是燈和月曆唯一的判斷（§T6-4）。sim 編號 game#25～#49（sim_mac6 game_*6）。
// • 主控骨架：型別與簽名定案（跨組名稱表 §T7-6）；函式回空值，G3b 換內容（可以再加 static 函式，不准改這幾支的簽名）。

import Foundation

/// 一天的記號（燈：lamp→.lamp、checked→.checked、leaf→.leaf、today／blank→.empty）
enum MacGameDayMark: Equatable {
    case lamp, checked, leaf, today, blank
}

/// 月曆一格
struct MacGameCalDay: Identifiable, Equatable {
    /// 那天 00:00
    let date: Date
    /// 幾號
    let day: Int
    /// 是不是這個月的（鄰月格子淡 0.45，照樣能補按）
    let inMonth: Bool
    let mark: MacGameDayMark
    let canCheck: Bool
    let canUncheck: Bool
    /// 滑過去的說明（「按一下：這天沒花錢」／「按一下：取消打卡」／那天的記號）
    let help: String

    var id: Date { date }
}

/// 月曆一列（週一開始）
struct MacGameCalWeek: Identifiable, Equatable {
    let start: Date
    let days: [MacGameCalDay]
    /// 這週算進連續週數（第 8 欄打勾）
    let counted: Bool

    var id: Date { start }
}

/// 一個月的月曆（4～6 列）
struct MacGameCalendarGrid: Equatable {
    /// 那個月 1 號 00:00
    let month: Date
    /// 「2026 年 11 月」
    let title: String
    let weeks: [MacGameCalWeek]
    let canBack: Bool
    let canForward: Bool
    /// 「連續 6 週・9/7 那週起」＋「打卡只存在這台 Mac，可以補按 6 天內」
    let footer: [String]
}

enum MacGameDays {
    /// 打卡最多留幾筆（§T6-3）
    static let noSpendLimit = 1000

    /// 日子字 "2026-11-26"（§T6-1）。主控骨架：空字
    static func label(_ d: Date, calendar: Calendar) -> String {
        ""
    }

    /// 讀日子字；看不懂的（"2026-02-30"、"abc"）＝nil，不閃退（§T6-1）。主控骨架：nil
    static func day(_ s: String, calendar: Calendar) -> Date? {
        nil
    }

    /// 燈和月曆唯一的判斷（§T6-4；d、today、start 都是 00:00）。主控骨架：blank
    static func dayMark(_ d: Date, today: Date, start: Date?, dataDays: Set<Date>, checkins: Set<Date>,
                        variableDays: Set<Date>) -> MacGameDayMark {
        .blank
    }

    /// 新 4 枚（§T6-8；Model 取 badges(longest:months:) 的聯集）。主控骨架：空
    static func badges2(longest: Int, dayCount: Int, macAdd: Bool, fixedTidy: Bool) -> Set<String> {
        []
    }
}
