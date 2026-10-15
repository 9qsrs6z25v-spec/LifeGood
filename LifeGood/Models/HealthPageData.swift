import SwiftUI

// MARK: - 健康頁的資料（v25.553，健康 v3；health/judge.md §3）
//
// 整頁的字和數字在這裡一次算好（HealthPageData.build），健康頁在 .task(id:) 裡呼叫一次、存成 @State；
// body 只畫，不算（坑 #21／#22：卡片頁「資料只在 .task(id:) 算一次」的寫法）。
// id＝lifeStore.workoutsRevision（運動、健康頁設定、健康檔案一改就加一）＋今天的日期＋上次用的運動。
//
// 一套數字都讀 WorkoutFacts／WorkoutFormat（週一開始、跑走騎各算各的不相加、一位小數、6'11"）。
// 頁面不盯著記錄器：記錄中條（HealthLiveStrip）自己看 RunTracker，這裡不碰（跑步時整頁不再每秒重算，U1 D1）。
//
// 例（judge §8.0，10/15 週四 07:12、主角跑步、目標 20 公里）：
//   看板「10/15 週四・這週第 4 天」「連續 6 週」「這週跑了」「14.6 公里」「3 次・比上週同期多 3.6 公里」Keep / running!
//   目標格「這週目標 20 公里」「73%」「還差 5.4 公里・剩 4 天」；膠囊「健走 3.1 公里」「2 小時 10 分」
//   開始列「開始跑步」「再跑 5.4 公里這週就達標」；最近運動「這週 4 趟」；每週公里 12 週合計 154.9。
// 驗算：health/build/v3/sim_v3.py。

/// 看板頭部（照 VehicleCardBoardData 的資料合約）
struct HealthBoardData: Equatable {
    /// 「10/15 週四・這週第 4 天」；週日「10/18 週日・這週最後一天」
    var date = ""
    /// 日期列的圖示：看板主角的運動圖示（只有重訓：dumbbell.fill）
    var dateIcon = "figure.run"
    /// 右上膠囊：「連續 6 週」（連續 2 週以上）／「這週 2 次」（中性；算所有運動）；新手 nil
    var capsule: String? = nil
    var capsuleIcon: String? = nil
    /// 連續週數 .good；其他 .neutral（畫面上 .neutral 傳 capsuleTint nil）
    var capsuleTone: MoneyTone = .neutral
    /// 「這週跑了」「這週走了」「這週騎了」「這週爬了」；只有重訓「這週練了」
    var label = ""
    /// 「14.6 公里」；0 寫「0 公里」；只有重訓「2 次」（不超過 7 個字，不然手寫問候會被擠掉）
    var big = ""
    /// 一句話：「3 次・比上週同期多 **3.6 公里**」（多：粗體 .good；少：中性灰，不染紅）
    var line = FinanceLine()
    /// 手寫兩行（英文）：Goal / reached!、10 weeks / strong!、Let's / run!、New week, / let's go!、Keep / running!
    var greeting: [String] = []
    /// 整個頭部一句（風景 accessibilityHidden）
    var accessibilityText = ""
    /// 天空、雲、風景的種子（同一週長一樣）
    var seed = 0
}

/// 看板下的目標格（有設目標時）
struct HealthGoalData: Equatable {
    var sport: WorkoutSport
    /// 「這週目標 20 公里」
    var title: String
    /// 「73%」（可以超過 100%：「103%」）
    var percentText: String
    /// 進度條 0…1
    var fraction: Double
    /// 「還差 5.4 公里・剩 4 天」／達標「達標！多跑了 0.6 公里」（reached 時字用 .good）
    var detail: String
    var reached: Bool
    /// 進度條條頭的小圖示（運動圖示）
    var icon: String
}

/// 沒設目標時，目標格換成一行：「上週跑了 13.3 公里」＋右邊藍字「設一個每週目標 ›」
struct HealthGoalPrompt: Equatable {
    /// 「上週跑了 13.3 公里」；上週沒有就「還沒有每週目標」
    var text: String
    /// 「設一個每週目標」
    var action: String
}

/// 每週目標小表單要的東西（運動跟著看板主角；轉盤 5～100 公里、5 公里一格）
struct HealthGoalSuggestion: Equatable {
    var sport: WorkoutSport
    /// 表單標題「每週跑步目標」
    var title: String
    /// 現在的目標；nil＝沒設
    var current: Double?
    /// 建議（5 的倍數）：轉盤沒設過目標時停在這裡
    var suggestedKm: Double
    /// 近 4 個完整週平均（0＝近 4 週沒有）
    var averageKm: Double
    /// 「建議 20 公里（近 4 週平均 14.8 公里）」／「建議 10 公里（近 4 週還沒有跑步）」
    var hint: String
}

/// 開始列
struct HealthStartData: Equatable {
    /// 大鈕：「開始」＋上次用的那一種（run_last_sport）
    var sport: WorkoutSport
    /// 右邊三顆小膠囊（另外三種）
    var others: [WorkoutSport]
    /// 下面灰字：「再跑 5.4 公里這週就達標」／「這週已達標，這趟是加碼」／「上一趟：今天 06:05・晨跑 5.2 公里」；空字串＝不出現
    var sentence: String
}

/// 每週公里（近 12 週）
struct HealthWeeklySeries: Equatable {
    struct Week: Equatable, Identifiable {
        /// 那週的週一 00:00
        var start: Date
        /// 軸上的字「10/5」
        var label: String
        /// 按住時的字「10/5–10/11」
        var rangeLabel: String
        /// 每種有氧的公里（跑、走、騎、登山；沒有的不放）
        var km: [WorkoutSport: Double]
        /// 每種有氧的趟數
        var trips: [WorkoutSport: Int]
        /// 這週（到今天）：直條淡一點，底下寫「這週（到今天）」
        var isCurrent: Bool
        var id: Date { start }
    }
    /// 12 週，舊到新；最後一週是這週
    var weeks: [Week]
    /// 有資料的有氧，照 跑、走、騎、登山 的順序（膠囊：這幾種＋「全部」）
    var sports: [WorkoutSport]
    /// 一打開選哪一種：看板主角（主角沒資料就第一個有資料的）
    var initial: WorkoutSport
    /// 有設每週目標的運動（單一運動時畫「目標 20」虛線）
    var goalKm: [WorkoutSport: Double]

    /// 12 週合計（圖例「跑步 154.9 公里」）
    func total(_ sport: WorkoutSport) -> Double {
        weeks.reduce(0) { $0 + ($1.km[sport] ?? 0) }
    }
}

/// 整頁
struct HealthPageData {
    /// 看板主角（自動已經算好）
    var hero: WorkoutSport
    /// 一筆有氧都沒有、只有重訓：看板改「這週練了 2 次」，沒有目標格
    var strengthOnly: Bool
    var board: HealthBoardData
    var scene: HealthWeekScene
    /// 有設目標（主角那一種）；跟 goalPrompt 剛好一個有值（只有重訓時兩個都 nil）
    var goal: HealthGoalData?
    var goalPrompt: HealthGoalPrompt?
    var suggestion: HealthGoalSuggestion
    /// 看板下的膠囊（最多 4 顆、0 的不放、不能按）
    var chips: [MoneyBoardChip]
    var start: HealthStartData
    /// 最近運動：最新的 5 筆（新到舊）＋它們的項目卡
    var recent: [WorkoutSession]
    var recentItems: [MoneyItem]
    /// 「這週 4 趟」
    var weekTripCount: Int
    /// 「看全部紀錄（148 趟）」
    var totalCount: Int
    /// 每週公里；有氧資料不到 2 週是 nil
    var weekly: HealthWeeklySeries?
    /// weekly 是 nil、但有有氧紀錄時那一行：「再記一週，就會出現每週公里」
    var weeklyPrompt: String?
    /// 有重訓紀錄（⑥ 重訓那一區才出現）
    var hasStrength: Bool
    /// 一筆都沒有（新手）
    var isEmpty: Bool
}

extension HealthPageData {

    /// 跑、走、騎、登山（看板、膠囊、每週公里、開始列的順序）
    static let cardioSports: [WorkoutSport] = [.run, .walk, .bike, .hike]

    /// 整頁一次算好。在 .task(id:) 裡、主執行緒呼叫（MoneyItem.workout 用到共用的 formatter）
    @MainActor
    static func build(workouts: [WorkoutSession], prefs: WorkoutPrefs, bodyWeightKg: Double?,
                      lastSport: RunSport, now: Date = Date()) -> HealthPageData {
        let sessions = workouts.sorted { $0.date > $1.date }
        let week = WorkoutFacts.week(of: now)
        let thisWeek = sessions.filter { $0.date >= week.start && $0.date < week.end }
        let hasCardio = sessions.contains { !$0.cardioExercises.isEmpty }
        let hasStrength = sessions.contains { !$0.strengthExercises.isEmpty }
        let strengthOnly = !hasCardio && hasStrength
        let hero = WorkoutFacts.heroSport(prefs, sessions: sessions, now: now)
        let progress = WorkoutFacts.weekProgress(sessions, prefs: prefs, sport: hero, now: now)
        let startSport = WorkoutSport(lastSport)

        var page = HealthPageData(
            hero: hero, strengthOnly: strengthOnly,
            board: HealthBoardData(), scene: HealthWeekScene(),
            goal: nil, goalPrompt: nil,
            suggestion: makeSuggestion(sessions, prefs: prefs, sport: hero, now: now),
            chips: [], start: HealthStartData(sport: startSport, others: [], sentence: ""),
            recent: Array(sessions.prefix(5)), recentItems: [],
            weekTripCount: thisWeek.count, totalCount: sessions.count,
            weekly: nil, weeklyPrompt: nil,
            hasStrength: hasStrength, isEmpty: sessions.isEmpty)

        page.board = makeBoard(sessions, thisWeek: thisWeek, hero: hero, strengthOnly: strengthOnly,
                           progress: progress, startSport: startSport, now: now)
        page.scene = makeWeekScene(sessions, hero: hero, now: now)
        if !strengthOnly {
            if progress.goalKm != nil {
                page.goal = makeGoal(progress)
            } else {
                page.goalPrompt = makeGoalPrompt(sessions, sport: hero, now: now)
            }
        }
        page.chips = makeChips(sessions, thisWeek: thisWeek, hero: hero, strengthOnly: strengthOnly, now: now)
        page.start = makeStart(sessions, hero: hero, strengthOnly: strengthOnly, progress: progress,
                           startSport: startSport, now: now)
        page.recentItems = page.recent.map { MoneyItem.workout($0, bodyWeightKg: bodyWeightKg) }
        let weekly = makeWeeklySeries(sessions, prefs: prefs, hero: hero, now: now)
        page.weekly = weekly
        if weekly == nil, hasCardio { page.weeklyPrompt = "再記一週，就會出現每週公里" }
        return page
    }

    // MARK: 字

    /// 看板大字：「14.6 公里」；不到 0.05 寫「0 公里」（不寫 0.0）
    static func bigKm(_ km: Double) -> String {
        km < 0.05 ? "0 公里" : WorkoutFormat.km(km)
    }

    /// 目標格的公里：整數不寫小數（「20 公里」）、其他一位（「5.4 公里」）
    static func goalKmText(_ km: Double) -> String {
        guard km.isFinite, km > 0 else { return "0 公里" }
        if abs(km - km.rounded()) < 0.05 { return "\(Int(km.rounded())) 公里" }
        return WorkoutFormat.km(km)
    }

    /// 「今天 06:05」「昨天 19:20」「10/12 06:10」
    static func whenText(_ date: Date, now: Date) -> String {
        let cal = WorkoutFacts.calendar
        let time = WorkoutFormat.time(date)
        if cal.isDate(date, inSameDayAs: now) { return "今天 " + time }
        if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(date, inSameDayAs: y) {
            return "昨天 " + time
        }
        return WorkoutFormat.monthDay(date) + " " + time
    }

    /// 手寫第二行：Keep / running!、walking!、riding!、climbing!
    private static func keepWord(_ sport: WorkoutSport) -> String {
        switch sport {
        case .walk: return "walking!"
        case .bike: return "riding!"
        case .hike: return "climbing!"
        default: return "running!"
        }
    }

    /// 新手：Let's / run!、walk!、ride!、hike!
    private static func letsWord(_ sport: WorkoutSport) -> String {
        switch sport {
        case .walk: return "walk!"
        case .bike: return "ride!"
        case .hike: return "hike!"
        default: return "run!"
        }
    }

    // MARK: 看板頭部

    private static func makeBoard(_ sessions: [WorkoutSession], thisWeek: [WorkoutSession], hero: WorkoutSport,
                              strengthOnly: Bool, progress: WorkoutWeekProgress, startSport: WorkoutSport,
                              now: Date) -> HealthBoardData {
        var b = HealthBoardData()
        let idx = WorkoutFacts.weekdayIndex(now)
        let week = WorkoutFacts.week(of: now)
        b.date = WorkoutFormat.day(now) + (idx == 6 ? "・這週最後一天" : "・這週第 \(idx + 1) 天")
        b.dateIcon = strengthOnly ? "dumbbell.fill" : hero.icon
        b.seed = Int((week.start.timeIntervalSince1970 / 86_400).rounded()) % 9_973

        let streak = WorkoutFacts.streakWeeks(sessions, now: now)
        let weekAll = thisWeek.filter { WorkoutFacts.counts($0) }.count
        if streak >= 2 {
            b.capsule = "連續 \(streak) 週"
            b.capsuleIcon = "flame.fill"
            b.capsuleTone = .good
        } else if weekAll > 0 {
            b.capsule = "這週 \(weekAll) 次"
            b.capsuleIcon = "figure.mixed.cardio"
            b.capsuleTone = .neutral
        }

        let verb = WorkoutFacts.verb(hero)
        let heroCount = WorkoutFacts.weekCount(sessions, sport: hero, weekOf: now)
        let strengthCount = thisWeek.filter { !$0.strengthExercises.isEmpty }.count
        if strengthOnly {
            b.label = "這週練了"
            b.big = "\(strengthCount) 次"
            let minutes = thisWeek.reduce(0) { $0 + WorkoutFacts.movingMinutes($1) }
            if strengthCount > 0 {
                b.line = FinanceLine.text("共 " + WorkoutFormat.total(minutes: minutes))
            } else {
                b.line = FinanceLine.text("新的一週")
            }
        } else {
            b.label = "這週\(verb)了"
            b.big = bigKm(progress.doneKm)
            b.line = boardLine(sessions, hero: hero, heroCount: heroCount, progress: progress,
                               startSport: startSport, weekStart: week.start, now: now)
        }

        // 手寫：達標 → 連續 5／10／25／52 週那週 → 新手 → 只有重訓 → 這週還沒動 → 平常
        let countedThisWeek = weekAll > 0
        if progress.reached && !strengthOnly {
            b.greeting = ["Goal", "reached!"]
        } else if countedThisWeek, [5, 10, 25, 52].contains(streak) {
            b.greeting = ["\(streak) weeks", "strong!"]
        } else if sessions.isEmpty {
            b.greeting = ["Let's", letsWord(startSport)]
        } else if strengthOnly {
            b.greeting = ["Stay", "strong!"]
        } else if heroCount == 0 {
            b.greeting = ["New week,", "let's go!"]
        } else {
            b.greeting = ["Keep", keepWord(hero)]
        }

        // VoiceOver：「這週跑了 14.6 公里，3 次，比上週同期多 3.6 公里，連續 6 週，目標 20 公里還差 5.4 公里。」
        var parts: [String] = [b.label + " " + b.big]
        let plain = b.line.plain.replacingOccurrences(of: "・", with: "，")
        if !plain.isEmpty { parts.append(plain) }
        if let c = b.capsule { parts.append(c) }
        if !strengthOnly, let g = progress.goalKm {
            if progress.reached {
                parts.append("目標 " + goalKmText(g) + "已達標")
            } else {
                parts.append("目標 " + goalKmText(g) + "還差 " + goalKmText(progress.remainingKm))
            }
        }
        b.accessibilityText = parts.joined(separator: "，") + "。"
        return b
    }

    /// 看板那一句（主角是有氧時）
    private static func boardLine(_ sessions: [WorkoutSession], hero: WorkoutSport, heroCount: Int,
                                  progress: WorkoutWeekProgress, startSport: WorkoutSport,
                                  weekStart: Date, now: Date) -> FinanceLine {
        let verb = WorkoutFacts.verb(hero)
        if sessions.isEmpty {
            return FinanceLine.text("按下面「開始\(startSport.displayName)」記第一趟")
        }
        if heroCount == 0 {
            let last = WorkoutFacts.lastWeekKm(sessions, sport: hero, now: now)
            let anyThisWeek = sessions.contains { $0.date >= weekStart && $0.date <= now }
            let head = (WorkoutFacts.weekdayIndex(now) == 0 || !anyThisWeek) ? "新的一週" : "這週還沒\(verb)"
            if last >= 0.05 {
                return FinanceLine.text(head + "・上週\(verb)了 " + WorkoutFormat.km(last))
            }
            return FinanceLine.text(head)
        }
        let head = "\(heroCount) 次・"
        let hadBefore = sessions.contains { $0.date < weekStart }
        guard hadBefore else {
            return FinanceLine.text(head + "這是你記錄的第一週")
        }
        let prev = WorkoutFacts.lastWeekSamePeriodKm(sessions, sport: hero, now: now)
        let diff = progress.doneKm - prev
        if abs(diff) < 0.1 {
            return FinanceLine.text(head + "跟上週同期差不多")
        }
        if diff > 0 {
            return FinanceLine(runs: [FinanceRun(text: head + "比上週同期多 "),
                                      FinanceRun(text: WorkoutFormat.km(diff), bold: true, tone: .good)])
        }
        // 比較少：中性灰、不粗體、不染紅（U3 坑 #19）
        return FinanceLine(runs: [FinanceRun(text: head + "比上週同期少 "),
                                  FinanceRun(text: WorkoutFormat.km(-diff), bold: false, tone: .neutral)])
    }

    // MARK: 這週的河堤

    private static func makeWeekScene(_ sessions: [WorkoutSession], hero: WorkoutSport, now: Date) -> HealthWeekScene {
        let week = WorkoutFacts.week(of: now)
        let labels = ["一", "二", "三", "四", "五", "六", "日"]
        let today = WorkoutFacts.weekdayIndex(now)
        // 每天、每種有氧的公里；有沒有重訓
        var km = [[WorkoutSport: Double]](repeating: [:], count: 7)
        var lifted = [Bool](repeating: false, count: 7)
        for s in sessions where s.date >= week.start && s.date < week.end {
            let i = WorkoutFacts.weekdayIndex(s.date)
            guard i >= 0 && i < 7 else { continue }
            for e in s.exercises {
                if e.kind == .cardio {
                    km[i][e.resolvedSport, default: 0] += max(0, e.distanceKm)
                } else {
                    lifted[i] = true
                }
            }
        }
        var top = 0.0
        for d in km {
            for v in d.values { top = max(top, v) }
        }
        let order: [WorkoutSport] = [.run, .walk, .bike, .hike, .other]
        var scene = HealthWeekScene()
        scene.todayIndex = today
        for i in 0..<7 {
            let sorted = km[i].keys.sorted { a, b in
                let ka = km[i][a] ?? 0
                let kb = km[i][b] ?? 0
                if ka != kb { return ka > kb }
                return (order.firstIndex(of: a) ?? 9) < (order.firstIndex(of: b) ?? 9)
            }
            var flags = sorted.map { sp in
                HealthWeekScene.Flag(sport: sp, height: top > 0 ? (km[i][sp] ?? 0) / top : 0)
            }
            if lifted[i] { flags.append(HealthWeekScene.Flag(sport: .strength, height: 0)) }
            scene.days.append(HealthWeekScene.Day(label: labels[i],
                                                  flags: Array(flags.prefix(2)),
                                                  extraDots: max(0, flags.count - 2),
                                                  isFuture: i > today))
        }
        // 小跑者：最近一趟有氧的運動（「其他有氧」用主角）；沒有就是主角
        if let last = sessions.first(where: { !$0.cardioExercises.isEmpty }) {
            let sp = last.primarySport
            scene.runnerSport = (sp == .other || sp == .strength) ? hero : sp
        } else {
            scene.runnerSport = hero
        }
        return scene
    }

    // MARK: 目標格、目標表單

    private static func makeGoal(_ p: WorkoutWeekProgress) -> HealthGoalData {
        let g = p.goalKm ?? 0
        let verb = WorkoutFacts.verb(p.sport)
        let pct = Int((p.fraction * 100).rounded())
        let detail: String
        if p.reached {
            let over = p.doneKm - g
            detail = over >= 0.05 ? "達標！多\(verb)了 " + goalKmText(over) : "達標！"
        } else {
            detail = "還差 " + goalKmText(p.remainingKm) + "・剩 \(p.daysLeft) 天"
        }
        return HealthGoalData(sport: p.sport,
                              title: "這週目標 " + goalKmText(g),
                              percentText: "\(pct)%",
                              fraction: min(1, max(0, p.fraction)),
                              detail: detail,
                              reached: p.reached,
                              icon: p.sport.icon)
    }

    private static func makeGoalPrompt(_ sessions: [WorkoutSession], sport: WorkoutSport, now: Date) -> HealthGoalPrompt {
        let last = WorkoutFacts.lastWeekKm(sessions, sport: sport, now: now)
        let text = last >= 0.05
            ? "上週\(WorkoutFacts.verb(sport))了 " + WorkoutFormat.km(last)
            : "還沒有每週目標"
        return HealthGoalPrompt(text: text, action: "設一個每週目標")
    }

    private static func makeSuggestion(_ sessions: [WorkoutSession], prefs: WorkoutPrefs, sport: WorkoutSport,
                                   now: Date) -> HealthGoalSuggestion {
        let s = WorkoutFacts.suggestedGoal(sessions, sport: sport, now: now)
        let km = Int(s.km.rounded())
        let hint = s.average > 0
            ? "建議 \(km) 公里（近 4 週平均 " + WorkoutFormat.km(s.average) + "）"
            : "建議 \(km) 公里（近 4 週還沒有\(sport.displayName)紀錄）"
        return HealthGoalSuggestion(sport: sport,
                                    title: "每週\(sport.displayName)目標",
                                    current: prefs.goalKm(for: sport),
                                    suggestedKm: s.km,
                                    averageKm: s.average,
                                    hint: hint)
    }

    // MARK: 膠囊

    private static func makeChips(_ sessions: [WorkoutSession], thisWeek: [WorkoutSession], hero: WorkoutSport,
                              strengthOnly: Bool, now: Date) -> [MoneyBoardChip] {
        var out: [MoneyBoardChip] = []
        if !strengthOnly {
            for sp in cardioSports where sp != hero {
                let km = WorkoutFacts.weekDistanceKm(sessions, sport: sp, weekOf: now)
                if km >= 0.05 {
                    out.append(MoneyBoardChip(icon: sp.icon, label: sp.displayName, value: WorkoutFormat.km(km)))
                }
            }
            out = Array(out.prefix(3))
        }
        let minutes = thisWeek.reduce(0) { $0 + WorkoutFacts.movingMinutes($1) }
        if minutes >= 0.5 {
            out.append(MoneyBoardChip(icon: "stopwatch", label: "", value: WorkoutFormat.total(minutes: minutes)))
        }
        let lifts = thisWeek.filter { !$0.strengthExercises.isEmpty }.count
        if lifts > 0, !strengthOnly, out.count < 4 {
            out.append(MoneyBoardChip(icon: "dumbbell.fill", label: "重訓", value: "\(lifts) 次"))
        }
        return Array(out.prefix(4))
    }

    // MARK: 開始列

    private static func makeStart(_ sessions: [WorkoutSession], hero: WorkoutSport, strengthOnly: Bool,
                              progress: WorkoutWeekProgress, startSport: WorkoutSport, now: Date) -> HealthStartData {
        var sentence = ""
        if !strengthOnly, progress.goalKm != nil {
            sentence = progress.reached
                ? "這週已達標，這趟是加碼"
                : "再\(WorkoutFacts.verb(hero)) " + goalKmText(progress.remainingKm) + "這週就達標"
        } else if let last = sessions.first {
            let km = last.totalDistanceKm
            let head = "上一趟：" + whenText(last.date, now: now)
            let what = WorkoutFacts.title(last)
            let tail = km >= 0.05 ? " " + WorkoutFormat.km(km) : ""
            sentence = head + "・" + what + tail
        }
        return HealthStartData(sport: startSport,
                               others: cardioSports.filter { $0 != startSport },
                               sentence: sentence)
    }

    // MARK: 每週公里

    private static func makeWeeklySeries(_ sessions: [WorkoutSession], prefs: WorkoutPrefs, hero: WorkoutSport,
                                     now: Date) -> HealthWeeklySeries? {
        let cal = WorkoutFacts.calendar
        let thisStart = WorkoutFacts.weekStart(of: now)
        var starts: [Date] = []
        for back in stride(from: 11, through: 0, by: -1) {
            if let d = cal.date(byAdding: .day, value: -7 * back, to: thisStart) { starts.append(d) }
        }
        guard let first = starts.first, let thisEnd = cal.date(byAdding: .day, value: 7, to: thisStart) else {
            return nil
        }
        var index: [Date: Int] = [:]
        for (i, d) in starts.enumerated() { index[d] = i }
        var km = [[WorkoutSport: Double]](repeating: [:], count: starts.count)
        var trips = [[WorkoutSport: Int]](repeating: [:], count: starts.count)
        for s in sessions where s.date >= first && s.date < thisEnd {
            guard let i = index[WorkoutFacts.weekStart(of: s.date)] else { continue }
            var seen = Set<WorkoutSport>()
            for e in s.exercises where e.kind == .cardio {
                let sp = e.resolvedSport
                guard cardioSports.contains(sp) else { continue }
                km[i][sp, default: 0] += max(0, e.distanceKm)
                seen.insert(sp)
            }
            for sp in seen { trips[i][sp, default: 0] += 1 }
        }
        var weeks: [HealthWeeklySeries.Week] = []
        for (i, d) in starts.enumerated() {
            let last = cal.date(byAdding: .day, value: 6, to: d) ?? d
            weeks.append(HealthWeeklySeries.Week(
                start: d,
                label: WorkoutFormat.monthDay(d),
                rangeLabel: WorkoutFormat.monthDay(d) + "–" + WorkoutFormat.monthDay(last),
                km: km[i].filter { $0.value >= 0.05 },
                trips: trips[i],
                isCurrent: i == starts.count - 1))
        }
        let withData = weeks.filter { w in w.km.values.contains { $0 >= 0.05 } }.count
        guard withData >= 2 else { return nil }
        let sports = cardioSports.filter { sp in weeks.contains { ($0.km[sp] ?? 0) >= 0.05 } }
        guard let firstSport = sports.first else { return nil }
        var goals: [WorkoutSport: Double] = [:]
        for sp in sports {
            if let g = prefs.goalKm(for: sp) { goals[sp] = g }
        }
        return HealthWeeklySeries(weeks: weeks, sports: sports,
                                  initial: sports.contains(hero) ? hero : firstSport,
                                  goalKm: goals)
    }
}

// MARK: - 一趟的動作（健康頁、全部紀錄、成果頁共用）

/// [v25.553] 長按選單、成果頁「⋯」用的動作。寫 store 一律排到下一輪主執行緒（選單、提示框、sheet 先收完）。
/// 要不要擋訂閱由呼叫端決定（待決定 8：開始新的一趟、＋、編輯、複製、刪除要訂閱；在跑的那一趟一定讓你存完）。
@MainActor
enum WorkoutActions {

    /// 「複製到現在」只有重訓、手動補記（沒有路線）的才有：有路線的複製過去沒意義（那天真的跑過的路）
    static func canDuplicate(_ s: WorkoutSession) -> Bool {
        guard s.firstRouteExercise == nil else { return false }
        if s.primarySport == .strength { return true }
        let src = WorkoutFacts.source(of: s)
        return src == .manual || src == nil
    }

    /// [v25.388] 原封不動複製一份到現在（以前在 HealthView.duplicate）。帶「訓練內容」（名稱、動作、時間、場地、備註、運動種類），
    /// 不帶「那一次實際量到的」（Apple 健康編號、路線、爬升、量到的大卡、分段、暫停）；每個動作新的 id。
    /// 複製出來的算手動補記，大卡照新的距離時間估好存回。回傳新的那一筆（store 在下一輪主執行緒才寫，Apple 健康隨後寫）
    @discardableResult
    static func duplicate(_ s: WorkoutSession, store: LifeStore) -> WorkoutSession {
        var copy = WorkoutSession(
            date: Date(),
            title: s.title,
            exercises: s.exercises.map { e in
                WorkoutExercise(name: e.name, kind: e.kind,
                                reps: e.reps, sets: e.sets,
                                loadType: e.loadType, loadKg: e.loadKg,
                                distanceKm: e.distanceKm,
                                durationMinutes: e.durationMinutes,
                                note: e.note,
                                sport: e.sport)
            },
            durationMinutes: s.durationMinutes,
            place: s.place,
            note: s.note)
        copy.source = .manual
        WorkoutFacts.applyKcalEstimate(&copy, bodyWeightKg: store.latestBodyWeightKg)
        let saved = copy
        DispatchQueue.main.async {
            store.upsertWorkout(saved)
            Task { await WorkoutHealthWriter.push(saved, store: store) }
        }
        return saved
    }

    /// 存一筆（編輯表單存檔、補記）：寫 store＋Apple 健康。WorkoutEditorView 的 onSave 已經在關掉 sheet 之後的下一輪才呼叫
    static func save(_ s: WorkoutSession, store: LifeStore) {
        store.upsertWorkout(s)
        Task { await WorkoutHealthWriter.push(s, store: store) }
    }

    /// 刪除確認框的標題：「刪除 10/15 晨跑 5.2 公里？」
    static func deleteTitle(_ s: WorkoutSession) -> String {
        let km = s.totalDistanceKm
        return "刪除 " + WorkoutFormat.monthDay(s.date) + " " + WorkoutFacts.title(s)
            + (km >= 0.05 ? " " + WorkoutFormat.km(km) : "") + "？"
    }

    /// 刪除確認框的內文（連 Apple 健康一起刪是 v4）
    static func deleteMessage(_ s: WorkoutSession) -> String {
        s.healthKitUUID != nil
            ? "只刪 LifeGood 這一筆；Apple 健康裡的那一筆不會刪。"
            : "刪掉就找不回來了。"
    }

    /// 確認之後刪：提示框關掉那一次畫面更新先過，下一輪主執行緒才寫 store
    static func delete(_ id: UUID, store: LifeStore) {
        DispatchQueue.main.async { store.deleteWorkout(id: id) }
    }
}
