// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.648 mac7 G3] 記帳小鎮第三批：年度星路（judge_mac.md §U5-3、§U5-5）。只算不寫：road 是純函式，翻到哪一年只在記憶體。
//
// • 規則只用 Foundation 型別；月界一律 MacGameRules.calendar（台北、洛杉磯各跑；sim 編號 game#55～#64）。
// • 沒有金額、名字；不比較（不寫「比去年」）；以前沒開始的月份寫「還沒開始記帳」（灰），以後的月份是空框。
// • 主控骨架（C0）：型別、簽名、字（extension MacGameText）定案（§U7-6）；road 回 12 個 .future、popover EmptyView()。G3 換內容。

import SwiftUI

/// 星路要的量（MacGameModel.recompute 填；只在記憶體）
struct MacGameYearInput: Equatable {
    /// 結算月（舊到新；最多往回 120 個）
    let months: [MacGameMonth]
    let current: MacGameMonth?
    /// 開始記帳那天
    let start: Date?
    /// 記帳週（週一 00:00）
    let weeks: Set<Date>
    /// 點亮的徽章 id → 點亮時間（timeIntervalSinceReferenceDate；0＝第一次打開補上的）
    let earned: [String: Double]

    static let empty = MacGameYearInput(months: [], current: nil, start: nil, weeks: [], earned: [:])
}

enum MacGameYearNodeKind: Equatable {
    case settled, current, future, notStarted
}

/// 星路上的一個月
struct MacGameYearNode: Identifiable, Equatable {
    /// 1～12
    let month: Int
    /// 那年那月 1 號 00:00
    let start: Date
    let kind: MacGameYearNodeKind
    /// settled、current 才有
    let stars: MacGameMonth?
    /// 那個月點亮的徽章數（t > 0 的才算）
    let badges: Int

    var id: Int { month }
}

/// 一年的星路
struct MacGameYearRoad: Equatable {
    let year: Int
    let title: String
    let nodes: [MacGameYearNode]
    let starsTotal: Int
    let weeks: Int
    let canBack: Bool
    let canForward: Bool
    let footer: String
}

enum MacGameYearRules {
    // sim7: game#55（G3 換內容：hi＝now 的年、lo＝start 的年（沒有＝hi））
    static func bounds(start: Date?, now: Date, calendar: Calendar) -> (lo: Int, hi: Int) {
        let y = calendar.component(.year, from: now)
        return (y, y)
    }

    // sim7: game#55（G3 換內容：夾在 [lo, hi]、不翻到未來）
    static func step(_ year: Int, by n: Int, start: Date?, now: Date, calendar: Calendar) -> Int {
        year
    }

    // sim7: game#56～#60（G3 換內容；骨架：12 個 .future）
    static func road(year: Int, input: MacGameYearInput, now: Date, calendar: Calendar) -> MacGameYearRoad {
        var nodes: [MacGameYearNode] = []
        for m in 1...12 {
            let start = calendar.date(from: DateComponents(year: year, month: m, day: 1)) ?? now
            nodes.append(MacGameYearNode(month: m, start: start, kind: .future, stars: nil, badges: 0))
        }
        return MacGameYearRoad(year: year, title: MacGameText.yearTitle(year), nodes: nodes, starsTotal: 0, weeks: 0,
                               canBack: false, canForward: false, footer: MacGameText.yearEmpty)
    }
}

/// 年度星路 popover（寬 520；遊戲列〔☆〕開）
struct MacGameYearPopover: View {
    var body: some View {
        EmptyView()
    }
}

// MARK: - 字（§U5-5；沒有金額、名字、比較）

extension MacGameText {
    static let yearHelp = "年度星路"
    static let yearEmpty = "這一年還沒有記帳"
    static let yearBefore = "還沒開始記帳"
    static let yearLater = "還沒到"
    static let yearNote = "照每筆帳的日期即時算，補記以前的也算；這個月要到月底才結算。"
    static let townHelp = "小鎮照等級蓋；這週有記帳的日子會亮一扇窗，沒花錢的日子種一棵樹"

    // sim7: game#60
    static func yearTitle(_ year: Int) -> String {
        "\(year) 年的星路"
    }

    // sim7: game#60（星數、週數都 0＝「這一年還沒有記帳」；不是今年寫「2025 年拿到…」）
    static func yearFooter(year: Int, stars: Int, weeks: Int, isThisYear: Bool) -> String {
        if stars == 0 && weeks == 0 {
            return yearEmpty
        }
        return (isThisYear ? "今年" : "\(year) 年") + "拿到 \(stars) 顆星・有記帳 \(weeks) 週"
    }
}
