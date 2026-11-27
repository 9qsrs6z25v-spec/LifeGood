// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.645 mac5 G3] 記帳小鎮（遊戲元素第一批）的規則（judge_mac.md §S4）：只 import Foundation，純函式，不碰 UI、不存任何東西。
//
// • 只看「有沒有記帳的週」與「每個月的比例」：不看金額大小、不看筆數、不看記帳天數；沒有扣分、沒有排行、沒有倒數。
// • 所有函式收 calendar:、now:（sim 換台北、洛杉磯）；頁面傳 MacGameRules.calendar（照抄 WorkoutFacts.swift:38-44（9f25bf5））。
// • 主控骨架：型別與簽名定案（不准改）；G3 換內容，Swift 每段照 §S4 編號寫 // sim5: game#N。
// • 字（MacGameText）逐字照 sim_mac5 GAME_TEXT、strip_title、streak_text、next_text、star_help、light_help、earned_text、toast_for（★1）。
// • [v25.646 mac6 G3b] MacGameLight 表尾加 checked（打勾的葉子）、徽章表尾加 4 枚（前 6 枚一字不改）、lightsHelp／footer 改字、
//   toast 加預設參數 newRecords（舊兩參數呼叫結果一字不變）。第二批的規則在 MacGameDays.swift。

import Foundation

/// 一顆星：拿到／還沒拿到（灰）／不算（沒有收入的月份，灰橫線）／月底結算（本月的守住、存下兩成）
enum MacGameStar: Equatable {
    case got, notYet, notCounted, pending
}

/// 本週一盞燈：金燈（那天有記帳）／葉子（那天沒有花錢）／空心（以後、開始記帳以前、今天還沒記）
// sim6: game#29（[v25.646 mac6] 表尾加 checked＝打勾的葉子（按了今天沒花錢））
enum MacGameLight: Equatable {
    case lamp, leaf, empty, checked
}

/// 一個月的收支（★2、★3 用；照抄 MacIncomeBoard.swift:154-165（9f25bf5）上個月存下幾成那條）
struct MacGameMonthLedger: Equatable {
    /// 那個月 1 號 00:00
    let start: Date
    /// 下個月 1 號 00:00
    let end: Date
    let income: Double
    let variable: Double
    let fixed: Double

    var saved: Double { income - variable - fixed }
}

/// 一個月的三顆星
struct MacGameMonth: Equatable {
    let start: Date
    /// 本月：★1 到今天為止，★2、★3 一律 pending；本月的星不進經驗值、不進徽章
    let isCurrent: Bool
    /// ★1：這個月有記帳日的不同週數／要幾週（min(4, span)）
    let weeksGot: Int
    let weeksNeed: Int
    let record: MacGameStar
    let hold: MacGameStar
    let save: MacGameStar

    /// 結算月拿到幾顆（本月＝0）
    var settledStars: Int {
        if isCurrent { return 0 }
        var n = 0
        if record == .got { n += 1 }
        if hold == .got { n += 1 }
        if save == .got { n += 1 }
        return n
    }
}

/// 徽章（第一批 6 枚；表尾加、不改舊 id 條件）
struct MacGameBadge: Identifiable, Equatable {
    enum Tone: Equatable { case medal, save, gold }

    let id: String
    let name: String
    let icon: String
    let tone: Tone
    /// 還沒點亮時的字
    let hint: String

    static let all: [MacGameBadge] = [
        MacGameBadge(id: "badge.week4", name: "連續 4 週", icon: "calendar.badge.checkmark", tone: .medal,
                     hint: "連續 4 週都有記帳就會亮"),
        MacGameBadge(id: "badge.week12", name: "一整季", icon: "calendar", tone: .medal,
                     hint: "連續 12 週都有記帳就會亮"),
        MacGameBadge(id: "badge.week26", name: "半年不間斷", icon: "calendar.circle.fill", tone: .medal,
                     hint: "連續 26 週都有記帳就會亮"),
        MacGameBadge(id: "badge.save20", name: "第一次存下兩成", icon: "leaf.fill", tone: .save,
                     hint: "有一個月存下兩成就會亮"),
        MacGameBadge(id: "badge.hold3", name: "三個月都守住", icon: "checkmark.shield.fill", tone: .save,
                     hint: "連續 3 個月守住就會亮（沒有收入的月份跳過）"),
        MacGameBadge(id: "badge.stars3", name: "第一次三顆星", icon: "star.circle.fill", tone: .gold,
                     hint: "有一個月拿到三顆星就會亮"),
        // [v25.646 mac6] 第二批 4 枚（§T6-8；條件在 MacGameDays.badges2）— sim6: game#39～#42
        MacGameBadge(id: "badge.firstMac", name: "第一次在電腦記帳", icon: "keyboard", tone: .medal,
                     hint: "在電腦按 ⌘N 記一筆就會亮"),
        MacGameBadge(id: "badge.fixedTidy", name: "固定支出整理好", icon: "checklist", tone: .save,
                     hint: "每一筆固定支出都有分類和週期就會亮（舊資料在 iPhone 打開存一次）"),
        MacGameBadge(id: "badge.week52", name: "一整年", icon: "trophy.fill", tone: .medal,
                     hint: "連續 52 週都有記帳就會亮"),
        MacGameBadge(id: "badge.day100", name: "記帳一百天", icon: "sun.max.fill", tone: .gold,
                     hint: "有記帳的日子累計 100 天就會亮"),
    ]
}

enum MacGameRules {
    // 照抄 WorkoutFacts.swift:38-44（9f25bf5）：西曆、zh_TW、跟著這台 Mac 的時區、週一開始
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "zh_TW")
        c.timeZone = TimeZone.autoupdatingCurrent
        c.firstWeekday = 2
        return c
    }()

    /// game#3　這一天所在那一週的週一 00:00（照抄 WorkoutFacts.swift:47-52（9f25bf5））
    // sim5: game#3（記帳週 W＝{ weekStart(d) | d ∈ R }，Model 那邊收）
    static func weekStart(of date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)    // 週日 1、週一 2 … 週六 7
        let back = (weekday + 5) % 7                               // 週一 0、週二 1 … 週日 6
        return calendar.date(byAdding: .day, value: -back, to: day) ?? day
    }

    /// game#1　記帳日：變動支出、單次收入 date ≤ now 的那天 00:00（固定支出、每月／每年收入是自動的，不算）
    // sim5: game#1（record_days：呼叫端只傳變動支出的 date、單次收入的 date；預先記的以後日期不算）
    static func recordDays(variableDates: [Date], onceIncomeDates: [Date], now: Date, calendar: Calendar) -> Set<Date> {
        var out = Set<Date>()
        for d in variableDates where d <= now {
            out.insert(calendar.startOfDay(for: d))
        }
        for d in onceIncomeDates where d <= now {
            out.insert(calendar.startOfDay(for: d))
        }
        return out
    }

    /// game#5　連續週數：從這週往回數；這週還沒記從上週數；最多 600 次（照抄 WorkoutFacts.swift:135-163（9f25bf5），拿掉請假週）
    // sim5: game#5（streak）
    static func streak(_ weeks: Set<Date>, now: Date, calendar: Calendar) -> (weeks: Int, since: Date?) {
        var cursor = weekStart(of: now, calendar: calendar)
        if !weeks.contains(cursor) {
            guard let prev = calendar.date(byAdding: .day, value: -7, to: cursor) else { return (0, nil) }
            cursor = prev
        }
        var count = 0
        var since: Date? = nil
        for _ in 0..<600 {
            if weeks.contains(cursor) {
                count += 1
                since = cursor
            } else {
                break
            }
            guard let prev = calendar.date(byAdding: .day, value: -7, to: cursor) else { break }
            cursor = prev
        }
        return (count, since)
    }

    /// game#6　最長一段相鄰差 7 天（calendar.date(byAdding: .day, value: 7)，避開日光節約）
    // sim5: game#6（longest）
    static func longestStreak(_ weeks: Set<Date>, calendar: Calendar) -> Int {
        var best = 0
        var run = 0
        var prev: Date? = nil
        for w in weeks.sorted() {
            if let p = prev, calendar.date(byAdding: .day, value: 7, to: p) == w {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            prev = w
        }
        return best
    }

    /// game#7　本週 7 盞燈（週一到週日）
    // sim5: game#7（week_lights：以後→空心；S 之前→空心；記帳日→金燈；以前而且沒有變動支出→葉子；其餘（今天還沒記）→空心）
    static func weekLights(recordDays: Set<Date>, variableDays: Set<Date>, start: Date?, now: Date,
                           calendar: Calendar) -> [MacGameLight] {
        let today = calendar.startOfDay(for: now)
        let ws = weekStart(of: now, calendar: calendar)
        let first: Date? = start.map { calendar.startOfDay(for: $0) }
        var out: [MacGameLight] = []
        for i in 0..<7 {
            let d = calendar.date(byAdding: .day, value: i, to: ws) ?? ws
            out.append(light(d, today: today, first: first, recordDays: recordDays, variableDays: variableDays))
        }
        return out
    }

    private static func light(_ d: Date, today: Date, first: Date?, recordDays: Set<Date>,
                              variableDays: Set<Date>) -> MacGameLight {
        if d > today { return .empty }
        guard let f = first, d >= f else { return .empty }
        if recordDays.contains(d) { return .lamp }
        if d < today && !variableDays.contains(d) { return .leaf }
        return .empty
    }

    /// game#8～#10　一個月的三顆星（days＝記帳日；firstDay＝開始記帳那天 S）
    static func month(_ ledger: MacGameMonthLedger, days: Set<Date>, firstDay: Date?, now: Date,
                      calendar: Calendar) -> MacGameMonth {
        let today = calendar.startOfDay(for: now)
        let isCurrent = ledger.start <= now && now < ledger.end
        // sim5: game#8（★1 有在記：got＝這個月有記帳日的不同週；span＝max(mStart, S)～min(mEnd − 1 天, today) 碰到幾週；need＝min(4, span)）
        var gotWeeks = Set<Date>()
        for d in days where d >= ledger.start && d < ledger.end {
            gotWeeks.insert(weekStart(of: d, calendar: calendar))
        }
        let got = gotWeeks.count
        var span = 0
        if let first = firstDay {
            let lo = max(ledger.start, calendar.startOfDay(for: first))
            let lastDay = calendar.date(byAdding: .day, value: -1, to: ledger.end) ?? ledger.end
            let hi = min(lastDay, today)
            if lo <= hi {
                let a = weekStart(of: lo, calendar: calendar)
                let b = weekStart(of: hi, calendar: calendar)
                let gap = calendar.dateComponents([.day], from: a, to: b).day ?? 0
                span = gap / 7 + 1
            }
        }
        let need = min(4, span)
        let record: MacGameStar = (need >= 1 && got >= need) ? .got : .notYet
        // sim5: game#9（★2 守住：income > 0 && saved >= 0；本月 pending；沒有收入 notCounted）
        // sim5: game#10（★3 存下兩成：income > 0 && saved >= 0.2 * income（乘法））
        let saved = ledger.saved
        let hold: MacGameStar
        let save: MacGameStar
        if isCurrent {
            hold = .pending
            save = .pending
        } else if ledger.income <= 0 {
            hold = .notCounted
            save = .notCounted
        } else {
            hold = saved >= 0 ? .got : .notYet
            save = saved >= 0.2 * ledger.income ? .got : .notYet
        }
        return MacGameMonth(start: ledger.start, isCurrent: isCurrent, weeksGot: got, weeksNeed: need,
                            record: record, hold: hold, save: save)
    }

    /// game#4　結算月：< 本月 1 號、≥ S 所在月份 1 號；最多往回 120 個；舊到新
    // sim5: game#4（settled_months）
    static func settledMonthStarts(firstDay: Date?, now: Date, calendar: Calendar) -> [Date] {
        guard let first = firstDay,
              let cur = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let lo = calendar.date(from: calendar.dateComponents([.year, .month], from: first)) else { return [] }
        var out: [Date] = []
        var m: Date? = calendar.date(byAdding: .month, value: -1, to: cur)
        while let x = m, x >= lo, out.count < 120 {
            out.append(x)
            m = calendar.date(byAdding: .month, value: -1, to: x)
        }
        return Array(out.reversed())
    }

    /// game#11　經驗值＝20×記帳週數＋30×結算月星數＋50×徽章數（不看金額、筆數、天數）
    // sim5: game#11（xp_of）
    static func xp(weeks: Int, stars: Int, badges: Int) -> Int {
        20 * weeks + 30 * stars + 50 * badges
    }

    /// 門檻 T(n)＝50×n×(n＋1)
    static func threshold(_ n: Int) -> Int {
        50 * n * (n + 1)
    }

    /// game#12　等級：門檻 T(n)＝50×n×(n＋1)；level＝最大的 n（0…99）使 T(n) ≤ xp；floor＝T(level)、next＝T(level＋1)
    // sim5: game#12（level_of）
    static func level(xp: Int) -> (level: Int, floor: Int, next: Int) {
        var lv = 0
        for n in 0..<100 where threshold(n) <= xp {
            lv = n
        }
        return (lv, threshold(lv), threshold(lv + 1))
    }

    /// game#13　小鎮的景（SF Symbols）
    // sim5: game#13（stage：≥ 9 一律天際線）
    static func stage(_ level: Int) -> (name: String, icon: String) {
        switch level {
        case ..<1: return ("空地", "leaf.fill")
        case 1: return ("小屋", "house.fill")
        case 2: return ("菜園", "tree.fill")
        case 3: return ("街角", "building.fill")
        case 4: return ("小巷", "building.2.fill")
        case 5: return ("市集", "cart.fill")
        case 6: return ("小鎮", "flag.fill")
        case 7: return ("河港", "ferry.fill")
        case 8: return ("城市", "building.columns.fill")
        default: return ("天際線", "sparkles")
        }
    }

    /// game#14　下一景的名字（★2：Lv.10 起「天際線 Lv.N」）
    // sim5: game#14（target_name、next_text：大約再記 ⌈gap ÷ 20⌉ 週到〔下一景〕）
    static func targetName(_ n: Int) -> String {
        n <= 9 ? stage(n).name : "天際線 Lv.\(n)"
    }

    static func nextText(xp shown: Int) -> String {
        let lv = level(xp: shown)
        let gap = lv.next - shown
        let weeks = gap <= 0 ? 0 : (gap + 19) / 20
        return "大約再記 \(weeks) 週到" + targetName(lv.level + 1)
    }

    /// game#15～#20　現在成立的徽章（只看結算月）
    static func badges(longest: Int, months: [MacGameMonth]) -> Set<String> {
        var out = Set<String>()
        // sim5: game#15（badge.week4：longest ≥ 4）
        if longest >= 4 { out.insert("badge.week4") }
        // sim5: game#16（badge.week12：longest ≥ 12）
        if longest >= 12 { out.insert("badge.week12") }
        // sim5: game#17（badge.week26：longest ≥ 26）
        if longest >= 26 { out.insert("badge.week26") }
        // sim5: game#18（badge.save20：任一結算月 ★3）
        if months.contains(where: { !$0.isCurrent && $0.save == .got }) { out.insert("badge.save20") }
        // sim5: game#19（badge.hold3：結算月依序，不算的跳過（不加、不斷），連續 3 個 ★2）
        var run = 0
        for m in months where !m.isCurrent && m.hold != .notCounted {
            run = m.hold == .got ? run + 1 : 0
            if run >= 3 { out.insert("badge.hold3") }
        }
        // sim5: game#20（badge.stars3：任一結算月 3 顆）
        if months.contains(where: { $0.settledStars == 3 }) { out.insert("badge.stars3") }
        return out
    }

    /// game#9　一個月的收支：照抄 MacIncomeBoard.swift:154-165（9f25bf5）（收入 incomeTotal、變動 ownAmount、固定月等值 mEnd − 1 秒）
    // 照抄 MacIncomeBoard.swift:154-165（9f25bf5）— sim5: game#9（month_ledger）
    @MainActor
    static func monthLedger(money: MacMoneyStore, start: Date, end: Date, now: Date, calendar: Calendar) -> MacGameMonthLedger {
        let income = money.incomeTotal(for: start, now: now, calendar: calendar)
        let variable = money.expenses
            .filter { $0.expenseType == .variable && $0.date >= start && $0.date < end && $0.date <= now }
            .reduce(0) { $0 + money.ownAmount($1) }
        let fixed = money.fixedMonthlyTotal(for: end.addingTimeInterval(-1), calendar: calendar)
        return MacGameMonthLedger(start: start, end: end, income: income, variable: variable, fixed: fixed)
    }
}

// MARK: - 字（★1：逐字照 sim_mac5；一個金額、一個名字都沒有）

enum MacGameText {
    static let notStarted = "Lv.0 空地・記下第一筆，小鎮就開始蓋"
    static let streakZero = "這週記一筆，就開始算連續週數"
    static let lightsHelp = "金燈＝那天有記帳，葉子＝那天沒有花錢，打勾的葉子＝按了今天沒花錢"
    static let lightLamp = "那天有記帳"
    static let lightLeaf = "那天沒有花錢"
    static let lightToday = "今天還沒記"
    static let weekdays: [String] = ["一", "二", "三", "四", "五", "六", "日"]
    static let starNames: [String] = ["有在記", "守住", "存下兩成"]
    static let pending = "月底結算"
    static let notCounted = "這個月沒有收入紀錄，這顆不算"
    static let footer = "照每筆帳的日期算，補記以前的也算。看過的徽章、打卡只存在這台 Mac，不會上 iCloud，也不會傳到 iPhone。"
    static let turnOff = "關掉遊戲元素"
    static let earnedZero = "已點亮"
    static let scriptLevel = "Level up!"
    static let scriptGoal = "Goal reached!"
    static let greeting = "Cozy town"
    static let badgeHeader = "徽章"
    static let monthsHeader = "最近幾個月"

    /// strip_title：「Lv.3 街角」
    static func stripTitle(_ level: Int) -> String {
        "Lv.\(level) " + MacGameRules.stage(level).name
    }

    /// streak_text：「連續 6 週・9/7 那週起」；0 週「這週記一筆，就開始算連續週數」
    static func streakText(_ weeks: Int, since: Date?, calendar: Calendar) -> String {
        guard weeks > 0, let since else { return streakZero }
        return "連續 \(weeks) 週・" + monthDay(since, calendar: calendar) + " 那週起"
    }

    /// badge_count_text：「徽章 3／6」
    static func badgeCount(_ n: Int) -> String {
        "徽章 \(n)／\(MacGameBadge.all.count)"
    }

    /// xp_text：「經驗值 640／1,000」
    static func xpText(_ xp: Int, next: Int) -> String {
        "經驗值 " + grouped(xp) + "／" + grouped(next)
    }

    /// month_label：「11 月」
    static func monthLabel(_ start: Date, calendar: Calendar) -> String {
        "\(calendar.component(.month, from: start)) 月"
    }

    /// star_help（which＝0 有在記、1 守住、2 存下兩成）
    static func starHelp(_ month: MacGameMonth, which: Int) -> String {
        let st: MacGameStar = which == 0 ? month.record : (which == 1 ? month.hold : month.save)
        let name = starNames[min(max(which, 0), 2)]
        if st == .pending { return pending }
        if st == .notCounted { return notCounted }
        if month.isCurrent && which == 0 { return "這個月已有 \(month.weeksGot) 週有記帳" }
        return name + (st == .got ? "（拿到了）" : "（這個月沒有這顆）")
    }

    /// light_help
    static func lightHelp(_ light: MacGameLight, isToday: Bool) -> String {
        switch light {
        case .lamp: return lightLamp
        case .leaf: return lightLeaf
        case .empty: return isToday ? lightToday : ""
        case .checked: return lightChecked
        }
    }

    /// earned_text：0＝第一次打開補上的「已點亮」；其餘「11/25 點亮」
    static func earnedText(_ v: Double, calendar: Calendar) -> String {
        if v <= 0 { return earnedZero }
        return monthDay(Date(timeIntervalSinceReferenceDate: v), calendar: calendar) + " 點亮"
    }

    /// backfill：「以前記的帳也算進來了：已點亮 5 枚」
    static func backfill(_ n: Int) -> String {
        "以前記的帳也算進來了：已點亮 \(n) 枚"
    }

    /// toast_for（newBadges 照 MacGameBadge.all 的順序）：1 個「剛剛點亮：連續 4 週」／「升到 Lv.4 小巷」，2 個以上「剛剛點亮 N 個，點遊戲列看」
    /// [v25.646 mac6] newRecords＝破紀錄的字（「新紀錄：連續 9 週」）；手寫 Level up! ＞ New record! ＞ Goal reached!
    // sim6: game#38（合計 ≥ 2 一則；只有 1 個紀錄寫那句；不傳 newRecords 時結果一字不變）
    static func toast(newLevel: Int?, newBadges: [String], newRecords: [String] = []) -> (text: String, script: String)? {
        let n = (newLevel == nil ? 0 : 1) + newBadges.count + newRecords.count
        if n == 0 { return nil }
        let script = newLevel != nil ? scriptLevel : (newRecords.isEmpty ? scriptGoal : scriptRecord)
        if n >= 2 { return ("剛剛點亮 \(n) 個，點遊戲列看", script) }
        if let lv = newLevel { return ("升到 Lv.\(lv) " + MacGameRules.stage(lv).name, script) }
        if let r = newRecords.first { return (r, script) }
        let name = MacGameBadge.all.first(where: { $0.id == newBadges[0] })?.name ?? ""
        return ("剛剛點亮：" + name, script)
    }

    /// M/d（照 sim md()：那個 calendar 的時區）
    static func monthDay(_ d: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.month, .day], from: d)
        return "\(c.month ?? 0)/\(c.day ?? 0)"
    }

    /// 千分位（只給經驗值用；不是金額）
    static func grouped(_ n: Int) -> String {
        let s = String(abs(n))
        var out = ""
        let count = s.count
        for (i, ch) in s.enumerated() {
            if i > 0 && (count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return n < 0 ? "-" + out : out
    }
}
