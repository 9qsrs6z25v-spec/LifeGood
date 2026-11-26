// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.646 mac6 G3b] 記帳小鎮第二批的日子規則（judge_mac.md §T6-1～§T6-8）：今天沒花錢打卡、記帳月曆、每週回顧、自己的紀錄、徽章 +4。
//
// • 一律 MacGameRules.calendar；新函式都收 now:、calendar:。日子字 "2026-11-26"（照 WorkoutProgress.swift:671-686 讀法：
//   拆三段、範圍檢查、中午 12 點組回、startOfDay、再寫一次要等於原字才收）。
// • 不碰分帳（新增行不准提那幾個字，§T6-0）；沒有金額、名字；讀日誌只准 kind == .add、key、at（在 MacGameModel）。
// • `dayMark` 是燈和月曆唯一的判斷（§T6-4）。sim 編號 game#25～#49（sim_mac6 game_*6）。
// • 主控骨架：型別與簽名定案（跨組名稱表 §T7-6）；函式回空值，G3b 換內容（可以再加 static 函式，不准改這幾支的簽名）。
// • [G3b] 這裡只算、不存：打卡字、回顧字由 MacGameModel 存進 mac.game.state.<雜湊>（UserDefaults 只在 MacGameModel）。
//   Python 對照：build/mac6/sim6_game.py（逐支同名、同順序）。

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

/// [G3b] 一次算好的日子（只在記憶體；沒有金額、名字）
struct MacGameDayFacts: Equatable {
    /// 今天 00:00
    let today: Date
    /// 資料的記帳日（Mac 5 原式：變動支出、單次收入 date ≤ now 那天）
    let dataDays: Set<Date>
    /// 開始記帳那天 S（只看資料，打卡不讓 S 提前）
    let start: Date?
    /// 有效打卡（看得懂、S ≤ 那天 ≤ 今天）
    let checkins: Set<Date>
    /// 記帳日 R＝dataDays ∪ checkins
    let recordDays: Set<Date>
    /// 記帳週 W＝{ weekStart(d) | d ∈ R }
    let weeks: Set<Date>
    /// 有變動支出的日子（含今天以後預先記的）
    let variableDays: Set<Date>

    static let empty = MacGameDayFacts(today: Date(timeIntervalSinceReferenceDate: 0), dataDays: [], start: nil, checkins: [],
                                       recordDays: [], weeks: [], variableDays: [])
}

/// [G3b] 每週回顧卡（一個金額、一個名字都沒有）
struct MacGameReview: Equatable {
    /// 上週一 00:00
    let weekStart: Date
    /// 「上週回顧・11/23～11/29」
    let title: String
    /// 「記了 3 天・沒花錢 2 天・點亮：連續 4 週」
    let text: String
}

/// [G3b] 自己的紀錄（只跟自己比）
struct MacGameRecords: Equatable {
    /// 最長連續幾週（0＝不寫那行）
    let longest: Int
    /// 那一段（最早那段）的第一週
    let longestSince: Date?
    /// 最多星的月（同分取最早；nil＝不寫那行）
    let bestMonth: Date?
    let bestStars: Int

    var isEmpty: Bool { longest == 0 && bestStars == 0 }

    static let empty = MacGameRecords(longest: 0, longestSince: nil, bestMonth: nil, bestStars: 0)
}

/// [G3b] 這次成立的破紀錄（id 進 seen；text 進膠囊）
struct MacGameRecordHit: Equatable {
    let id: String
    let text: String
}

enum MacGameDays {
    /// 打卡最多留幾筆（§T6-3）
    static let noSpendLimit = 1000
    /// 補按期限：今天往回 6 天（含今天共 7 天）
    static let windowDays = 6
    /// 月曆最多往回幾個月（同 settledMonthStarts）
    static let monthsBack = 120
    /// 第二批 4 枚（v1 → v2 遷移時靜默補上）
    static let addedInV2: Set<String> = ["badge.firstMac", "badge.fixedTidy", "badge.week52", "badge.day100"]
    static let firstMacID = "badge.firstMac"

    // MARK: 日子字（§T6-1）

    /// 日子字 "2026-11-26"（§T6-1）
    // sim6: game#25（照抄 WorkoutProgress.swift:671-675 寫法：String(format: "%04d-%02d-%02d")）
    static func label(_ d: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 同 label（MacGameModel 用這個名字叫）
    static func dayKey(_ d: Date, calendar: Calendar) -> String {
        label(d, calendar: calendar)
    }

    /// 讀日子字；看不懂的（"2026-02-30"、"abc"）＝nil，不閃退（§T6-1）
    // sim6: game#25（長度 10、拆三段、2000～2200／1～12／1～31、中午 12 點組回、startOfDay、再寫一次＝原字才收）
    static func day(_ s: String, calendar: Calendar) -> Date? {
        guard s.count == 10 else { return nil }
        let parts = s.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        guard y >= 2000, y <= 2200, m >= 1, m <= 12, d >= 1, d <= 31 else { return nil }
        var c = DateComponents()
        c.year = y
        c.month = m
        c.day = d
        c.hour = 12
        guard let t = calendar.date(from: c) else { return nil }
        let out = calendar.startOfDay(for: t)
        return label(out, calendar: calendar) == s ? out : nil
    }

    /// 存的打卡字：看不懂的丟掉、去重、排序（字串排序＝日期排序）、留最後 1,000 個
    // sim6: game#28（1,000 上限：舊的先丟）
    static func cleanNoSpend(_ raw: [String], calendar: Calendar) -> [String] {
        let ok = Set(raw.filter { s in day(s, calendar: calendar) != nil })
        return Array(ok.sorted().suffix(noSpendLimit))
    }

    // MARK: 記帳日（§T6-2）

    // sim6: game#25（dataDays＝Mac 5 原式；S＝dataDays.min()；checkins＝看得懂、S ≤ d ≤ today；R＝dataDays ∪ checkins；W 吃 R；
    //               variableDays＝每筆變動支出那天，含以後；noSpend 空時 R、W、S 跟 Mac 5 逐位一樣）
    static func facts(variableDates: [Date], onceIncomeDates: [Date], noSpend: [String], now: Date,
                      calendar: Calendar) -> MacGameDayFacts {
        let today = calendar.startOfDay(for: now)
        let data = MacGameRules.recordDays(variableDates: variableDates, onceIncomeDates: onceIncomeDates, now: now,
                                           calendar: calendar)
        let start: Date? = data.min()
        var checkins = Set<Date>()
        if let s = start {
            for c in noSpend {
                guard let d = day(c, calendar: calendar), d >= s, d <= today else { continue }
                checkins.insert(d)
            }
        }
        let r = data.union(checkins)
        var weeks = Set<Date>()
        for d in r {
            weeks.insert(MacGameRules.weekStart(of: d, calendar: calendar))
        }
        var variableDays = Set<Date>()
        for d in variableDates {
            variableDays.insert(calendar.startOfDay(for: d))
        }
        return MacGameDayFacts(today: today, dataDays: data, start: start, checkins: checkins, recordDays: r, weeks: weeks,
                               variableDays: variableDays)
    }

    // MARK: 打卡（§T6-3）

    /// 在補按期限裡：[today − 6 天, today]
    static func inWindow(_ d: Date, today: Date, calendar: Calendar) -> Bool {
        let lo = calendar.date(byAdding: .day, value: -windowDays, to: today) ?? today
        return d >= lo && d <= today
    }

    // sim6: game#26（canCheck＝可寫 && S 有 && d ≥ S && 期限內 && 不是資料記帳日 && 那天沒有變動支出 && 還沒打過卡）
    static func canCheck(_ d: Date, facts f: MacGameDayFacts, noSpend: Set<String>, writable: Bool,
                         calendar: Calendar) -> Bool {
        guard writable, let s = f.start, d >= s, inWindow(d, today: f.today, calendar: calendar) else { return false }
        if f.dataDays.contains(d) || f.variableDays.contains(d) { return false }
        return !noSpend.contains(label(d, calendar: calendar))
    }

    // sim6: game#26（canUncheck＝可寫 && 期限內 && 打過卡；期限外的打卡留著、不能取消）
    static func canUncheck(_ d: Date, facts f: MacGameDayFacts, noSpend: Set<String>, writable: Bool,
                           calendar: Calendar) -> Bool {
        guard writable, inWindow(d, today: f.today, calendar: calendar) else { return false }
        return noSpend.contains(label(d, calendar: calendar))
    }

    // MARK: 燈（§T6-4）

    /// 燈和月曆唯一的判斷（§T6-4；d、today、start 都是 00:00）
    // sim6: game#29（以後→blank；S 之前→blank；資料記帳日→lamp；打卡→checked；今天→today；沒有變動支出→leaf；其餘→blank）
    static func dayMark(_ d: Date, today: Date, start: Date?, dataDays: Set<Date>, checkins: Set<Date>,
                        variableDays: Set<Date>) -> MacGameDayMark {
        if d > today { return .blank }
        guard let s = start, d >= s else { return .blank }
        if dataDays.contains(d) { return .lamp }
        if checkins.contains(d) { return .checked }
        if d == today { return .today }
        if !variableDays.contains(d) { return .leaf }
        return .blank
    }

    static func mark(_ d: Date, facts f: MacGameDayFacts) -> MacGameDayMark {
        dayMark(d, today: f.today, start: f.start, dataDays: f.dataDays, checkins: f.checkins, variableDays: f.variableDays)
    }

    /// 燈：lamp→.lamp、checked→.checked、leaf→.leaf、today／blank→.empty
    static func lightOf(_ m: MacGameDayMark) -> MacGameLight {
        switch m {
        case .lamp: return .lamp
        case .checked: return .checked
        case .leaf: return .leaf
        case .today, .blank: return .empty
        }
    }

    /// 本週 7 盞燈（週一到週日；checkins 空時＝MacGameRules.weekLights 逐格）
    // sim6: game#29
    static func weekLights(_ f: MacGameDayFacts, now: Date, calendar: Calendar) -> [MacGameLight] {
        let ws = MacGameRules.weekStart(of: now, calendar: calendar)
        var out: [MacGameLight] = []
        for i in 0..<7 {
            let d = calendar.date(byAdding: .day, value: i, to: ws) ?? ws
            out.append(lightOf(mark(d, facts: f)))
        }
        return out
    }

    // MARK: 記帳月曆（§T6-5）

    static func monthStart(_ d: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: d)) ?? calendar.startOfDay(for: d)
    }

    /// 能翻的月：lo＝monthStart(S ?? now)（最多往回 120 個月）、hi＝monthStart(now)（不翻到未來）
    // sim6: game#31
    static func monthRange(start: Date?, now: Date, calendar: Calendar) -> (lo: Date, hi: Date) {
        let hi = monthStart(now, calendar: calendar)
        let floor = calendar.date(byAdding: .month, value: -monthsBack, to: hi) ?? hi
        let lo = max(monthStart(start ?? now, calendar: calendar), floor)
        return (min(lo, hi), hi)
    }

    // sim6: game#31（‹ › 翻月：夾在 lo～hi）
    static func stepMonth(_ m: Date, by n: Int, start: Date?, now: Date, calendar: Calendar) -> Date {
        let r = monthRange(start: start, now: now, calendar: calendar)
        let t = calendar.date(byAdding: .month, value: n, to: m) ?? m
        let x = monthStart(t, calendar: calendar)
        return min(max(x, r.lo), r.hi)
    }

    /// 一格的說明：能按的寫怎麼按；不能按的寫那天的記號
    static func help(_ m: MacGameDayMark, canCheck: Bool, canUncheck: Bool) -> String {
        if canCheck { return MacGameText.checkHint }
        if canUncheck { return MacGameText.uncheckHint }
        switch m {
        case .lamp: return MacGameText.lightLamp
        case .checked: return MacGameText.lightChecked
        case .leaf: return MacGameText.lightLeaf
        case .today: return MacGameText.lightToday
        case .blank: return ""
        }
    }

    // sim6: game#30（cursor＝weekStart(月 1 號)，while cursor < 下月 1 號 && 列 < 7；7 天各 dayMark、inMonth、canCheck／canUncheck；
    //               counted＝cursor ∈ W；不分深淺、不打叉、不寫筆數金額）
    static func monthGrid(month: Date, facts f: MacGameDayFacts, noSpend: Set<String>, writable: Bool, streakWeeks: Int,
                          streakSince: Date?, now: Date, calendar: Calendar) -> MacGameCalendarGrid {
        let first = monthStart(month, calendar: calendar)
        let next = calendar.date(byAdding: .month, value: 1, to: first) ?? first
        var weeks: [MacGameCalWeek] = []
        var cursor = MacGameRules.weekStart(of: first, calendar: calendar)
        while cursor < next && weeks.count < 7 {
            var days: [MacGameCalDay] = []
            for i in 0..<7 {
                let d = calendar.date(byAdding: .day, value: i, to: cursor) ?? cursor
                days.append(calDay(d, first: first, next: next, facts: f, noSpend: noSpend, writable: writable,
                                   calendar: calendar))
            }
            weeks.append(MacGameCalWeek(start: cursor, days: days, counted: f.weeks.contains(cursor)))
            guard let n = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = n
        }
        let r = monthRange(start: f.start, now: now, calendar: calendar)
        let footer = [MacGameText.streakText(streakWeeks, since: streakSince, calendar: calendar), MacGameText.calendarFooter]
        return MacGameCalendarGrid(month: first, title: MacGameText.monthTitle(first, calendar: calendar), weeks: weeks,
                                   canBack: first > r.lo, canForward: first < r.hi, footer: footer)
    }

    private static func calDay(_ d: Date, first: Date, next: Date, facts f: MacGameDayFacts, noSpend: Set<String>,
                               writable: Bool, calendar: Calendar) -> MacGameCalDay {
        let m = mark(d, facts: f)
        let can = canCheck(d, facts: f, noSpend: noSpend, writable: writable, calendar: calendar)
        let undo = canUncheck(d, facts: f, noSpend: noSpend, writable: writable, calendar: calendar)
        return MacGameCalDay(date: d, day: calendar.component(.day, from: d), inMonth: d >= first && d < next, mark: m,
                             canCheck: can, canUncheck: undo, help: help(m, canCheck: can, canUncheck: undo))
    }

    // MARK: 每週回顧（§T6-6）

    // sim6: game#33（上週 [lastW, thisW)：記了幾天（含打卡）、沒花錢幾天（leaf／checked）、上週點亮的徽章（t > 0）、
    //               上週過完的那個月的星（≥ 1 才寫）、連續 k 週；可寫 && S < thisW && lastReview ≠ 這週一 && 有東西可講才出現）
    static func review(facts f: MacGameDayFacts, months: [MacGameMonth], earned: [String: Double], lastReview: String?,
                       streakWeeks: Int, writable: Bool, now: Date, calendar: Calendar) -> MacGameReview? {
        let thisW = MacGameRules.weekStart(of: now, calendar: calendar)
        guard writable, let s = f.start, s < thisW, lastReview != label(thisW, calendar: calendar) else { return nil }
        let lastW = calendar.date(byAdding: .day, value: -7, to: thisW) ?? thisW
        var days = 0
        var leaves = 0
        for i in 0..<7 {
            let d = calendar.date(byAdding: .day, value: i, to: lastW) ?? lastW
            if f.recordDays.contains(d) { days += 1 }
            let m = mark(d, facts: f)
            if m == .leaf || m == .checked { leaves += 1 }
        }
        let lo = lastW.timeIntervalSinceReferenceDate
        let hi = thisW.timeIntervalSinceReferenceDate
        let lit: [String] = MacGameBadge.all.filter { b in
            guard let t = earned[b.id] else { return false }
            return t > 0 && t >= lo && t < hi
        }.map { $0.name }
        var monthStars = 0
        var starMonth: Date? = nil
        for m in months where !m.isCurrent {
            let end = calendar.date(byAdding: .month, value: 1, to: m.start) ?? m.start
            if end > lastW && end <= thisW {
                monthStars = m.settledStars
                starMonth = m.start
            }
        }
        guard days >= 1 || !lit.isEmpty || monthStars >= 1 else { return nil }
        var parts: [String] = []
        if days > 0 { parts.append("記了 \(days) 天") }
        if leaves > 0 { parts.append("沒花錢 \(leaves) 天") }
        if !lit.isEmpty { parts.append(MacGameText.litText(lit)) }
        if monthStars >= 1, let ms = starMonth {
            parts.append(MacGameText.monthLabel(ms, calendar: calendar) + "拿到 \(monthStars) 顆星")
        }
        if f.weeks.contains(lastW) && streakWeeks >= 1 { parts.append("連續 \(streakWeeks) 週") }
        return MacGameReview(weekStart: lastW, title: MacGameText.reviewTitle(lastW, calendar: calendar),
                             text: parts.joined(separator: "・"))
    }

    // MARK: 自己的紀錄（§T6-7）

    // sim6: game#36（最長連續 L＋最早那段起點；最多星的月 n（同分取最早）；都照現在的資料算）
    static func records(weeks: Set<Date>, months: [MacGameMonth], calendar: Calendar) -> MacGameRecords {
        var best = 0
        var bestStart: Date? = nil
        var run = 0
        var runStart: Date? = nil
        var prev: Date? = nil
        for w in weeks.sorted() {
            if let p = prev, calendar.date(byAdding: .day, value: 7, to: p) == w {
                run += 1
            } else {
                run = 1
                runStart = w
            }
            if run > best {
                best = run
                bestStart = runStart
            }
            prev = w
        }
        var stars = 0
        var bestMonth: Date? = nil
        for m in months where !m.isCurrent && m.settledStars > stars {
            stars = m.settledStars
            bestMonth = m.start
        }
        return MacGameRecords(longest: best, longestSince: bestStart, bestMonth: bestMonth, bestStars: stars)
    }

    // sim6: game#37（週紀錄：(k, s)＝streak(W)；prev＝s 之前那些段的 longest；s 有 && prev ≥ 1 && k > prev；id＝record.week.<s>
    //               星紀錄：最新結算月 last；prev＝更早結算月最多幾顆；prev ≥ 1 && last > prev；id＝record.stars.<yyyy-MM>）
    static func recordHits(weeks: Set<Date>, months: [MacGameMonth], now: Date, calendar: Calendar) -> [MacGameRecordHit] {
        var out: [MacGameRecordHit] = []
        let cur = MacGameRules.streak(weeks, now: now, calendar: calendar)
        if let s = cur.since {
            let prev = MacGameRules.longestStreak(weeks.filter { w in w < s }, calendar: calendar)
            if prev >= 1 && cur.weeks > prev {
                out.append(MacGameRecordHit(id: "record.week." + label(s, calendar: calendar),
                                            text: "新紀錄：連續 \(cur.weeks) 週"))
            }
        }
        let settled = months.filter { m in !m.isCurrent }
        if let last = settled.last {
            let prev = settled.dropLast().map { m in m.settledStars }.max() ?? 0
            if prev >= 1 && last.settledStars > prev {
                out.append(MacGameRecordHit(id: "record.stars." + monthKey(last.start, calendar: calendar),
                                            text: "新紀錄：" + MacGameText.monthLabel(last.start, calendar: calendar)
                                                + "拿到 \(last.settledStars) 顆星"))
            }
        }
        return out
    }

    /// "2026-10"
    static func monthKey(_ d: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month], from: d)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    // MARK: 徽章 +4（§T6-8）

    /// 新 4 枚（§T6-8；Model 取 badges(longest:months:) 的聯集）
    static func badges2(longest: Int, dayCount: Int, macAdd: Bool, fixedTidy: Bool) -> Set<String> {
        var out = Set<String>()
        // sim6: game#39（badge.firstMac：同帳號的日誌有一筆收支 add）
        if macAdd { out.insert("badge.firstMac") }
        // sim6: game#40（badge.fixedTidy：進行中的固定支出都有分類、週期；一筆都沒有不亮）
        if fixedTidy { out.insert("badge.fixedTidy") }
        // sim6: game#41（badge.week52：longest ≥ 52，W 含打卡）
        if longest >= 52 { out.insert("badge.week52") }
        // sim6: game#42（badge.day100：|R| ≥ 100，累計、含打卡）
        if dayCount >= 100 { out.insert("badge.day100") }
        return out
    }

    // sim6: game#40（進行中＝固定支出 && date ≤ now && 沒停止（MacFixedBoard.swift:449）；舊資料＝分類或週期是 nil（MacEditPolicy.swift:274））
    static func fixedTidy(_ expenses: [Expense], now: Date, calendar: Calendar) -> Bool {
        let active = expenses.filter { e in
            e.expenseType == .fixed && e.date <= now && !e.macIsFixedEnded(now: now, calendar: calendar)
        }
        return !active.isEmpty && active.allSatisfy { e in e.fixedCategory != nil && e.recurrence != nil }
    }

    // sim6: game#47（徽章 popover 每排 4 枚：4／4／2）
    static func badgeRows(_ all: [MacGameBadge], per: Int) -> [[MacGameBadge]] {
        let n = max(1, per)
        var out: [[MacGameBadge]] = []
        var i = 0
        while i < all.count {
            out.append(Array(all[i..<min(i + n, all.count)]))
            i += n
        }
        return out
    }
}

// MARK: - 第二批的字（逐字照 sim6_game.GAME_TEXT6；一個金額、一個名字都沒有）

// sim6: game#48（字：沒有第三人稱代名詞、沒有那兩個字、沒有負面字）
extension MacGameText {
    static let lightChecked = "那天沒有花錢（打了卡）"
    static let noSpendButton = "今天沒花錢"
    static let noSpendHelp = "今天沒有花錢也算有記帳；打卡只存在這台 Mac"
    static let calendarHelp = "記帳月曆"
    static let calendarFooter = "打卡只存在這台 Mac，可以補按 6 天內"
    static let checkHint = "按一下：這天沒花錢"
    static let uncheckHint = "按一下：取消打卡"
    static let weekCounted = "這週算進連續週數"
    static let reviewDone = "好"
    static let scriptWeek = "Nice week!"
    static let scriptRecord = "New record!"
    static let recordsHeader = "自己的紀錄"
    static let recordsNote = "只跟自己比"
    static let readOnly = "這台 Mac 的小鎮是比較新的版本存的，這一版只看不改"

    /// 「2026 年 11 月」
    static func monthTitle(_ d: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month], from: d)
        return "\(c.year ?? 0) 年 \(c.month ?? 0) 月"
    }

    /// 「上週回顧・11/23～11/29」
    static func reviewTitle(_ lastW: Date, calendar: Calendar) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: lastW) ?? lastW
        return "上週回顧・" + monthDay(lastW, calendar: calendar) + "～" + monthDay(end, calendar: calendar)
    }

    /// 「點亮：連續 4 週、第一次在電腦記帳」（最多 3 個名字，多的「等 N 枚」）
    static func litText(_ names: [String]) -> String {
        let head = names.prefix(3).joined(separator: "、")
        return names.count > 3 ? "點亮：" + head + " 等 \(names.count) 枚" : "點亮：" + head
    }

    /// 自己的紀錄兩行（沒有的那行不寫；兩行都沒有＝空）
    static func recordLines(_ r: MacGameRecords, calendar: Calendar) -> [String] {
        var out: [String] = []
        if r.longest > 0 {
            let since = r.longestSince.map { d in "（" + monthDay(d, calendar: calendar) + " 那週起）" } ?? ""
            out.append("最長連續：\(r.longest) 週" + since)
        }
        if r.bestStars > 0, let m = r.bestMonth {
            out.append("最多星的月：" + monthTitle(m, calendar: calendar) + "・\(r.bestStars) 顆")
        }
        return out
    }
}
