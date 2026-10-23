import Foundation

// MARK: - 運動跟人生其他地方的連接（v25.558，健康 v7b；health/judge.md §6 v7 那一列的後半，只屬於主 App）
//
// 主控寫好的一套數字（各組只讀、不另寫第二份；build/v7b/brief.md §2）：
//   • 小工具「今天（大）」最下面那一行運動：widgetWorkoutDays（今天、明天各一份，WidgetSnapshotWriter 寫進 life 快照）
//       今天有運動「今天 晨跑 5.2 公里」；沒有就是這週的進度「這週跑了 14.6 公里・目標 20」。
//   • 我的行事曆：那一天的運動 sessions(on:in:)、一列的字 calendarTitle「晨跑 5.2 公里」、calendarDetail「跑步・32:10」。
//   • 運動里程碑（judge §1.3「記成人生里程碑」→ design_C §2.8 的清單，主控挑過）：milestones（自動算、不存），
//       記成人生里程碑時存 LifeMilestone.sourceKey＝key；isRecorded 判斷記過沒。
//   • 累積公里換風景（judge §3.12 最後一句「河堤 → 黃昏河濱 → 山路 → 海岸」、U4 第 13 條的門檻）：
//       HealthSceneryStage、sceneryStage、yearChip「今年 523.4 公里」、sceneryGainText「今年跑了 250.3 公里，看板換成山路了」。
//   • 成果頁心率（judge §5.2 ⑦）：heartWindow、heartSummary「平均 152・最高 171」；樣本只放記憶體（不存、不進 iCloud）。
//
// 全部是純函式（只讀傳進來的值），在主執行緒呼叫（WorkoutFormat 的 DateFormatter 共用）。
// 驗算：build/v7b/sim_v7b.py（逐行照這個檔寫；輸出 build/v7b/sim_v7b_output.txt）。

// MARK: - 小工具「今天（大）」那一行

extension WorkoutFacts {

    /// [健康 v7b] 「今天（大）」最下面那一行，一天一份。dayStarts＝[今天 00:00, 明天 00:00]
    /// （WidgetSnapshotWriter.lifeSnapshot 的兩天，Calendar.current 切的）。每一天用「那一天的現在」算：
    /// 今天用 now、明天用明天 00:00（還沒跑；明天是週一就換新的一週）
    static func widgetWorkoutDays(_ sessions: [WorkoutSession], prefs: WorkoutPrefs, leave: WorkoutLeaveBook,
                                  dayStarts: [Date], now: Date,
                                  calendar cal: Calendar = .current) -> [WidgetWorkoutDay] {
        var out: [WidgetWorkoutDay] = []
        for start in dayStarts {
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
            let ref: Date = (now >= start && now < end) ? now : start
            out.append(widgetWorkoutDay(sessions, prefs: prefs, leave: leave, dayStart: start, dayEnd: end, ref: ref))
        }
        return out
    }

    /// [健康 v7b] 一天那一行：那一天到 ref 為止有算數的運動（counts）→ 最晚開始的那一趟；沒有 → 這週的進度（widgetWeekLine）；
    /// 都沒有 → text、privateText 都是空字串（那一天不畫）
    static func widgetWorkoutDay(_ sessions: [WorkoutSession], prefs: WorkoutPrefs, leave: WorkoutLeaveBook,
                                 dayStart: Date, dayEnd: Date, ref: Date) -> WidgetWorkoutDay {
        let key = WidgetDateText.dayKey(dayStart)
        let today = sessions.filter { s in
            s.date >= dayStart && s.date < dayEnd && s.date <= ref && counts(s)
        }
        let latest = today.max { a, b in a.date < b.date }
        if let s = latest {
            let sport = s.primarySport
            let words = widgetSessionWords(s)
            return WidgetWorkoutDay(dayKey: key, dayStart: dayStart, dayEnd: dayEnd, icon: sport.icon,
                                    text: "今天 " + title(s) + words,
                                    privateText: "今天 " + sport.displayName + words,
                                    link: WidgetLink.health(s.id).absoluteString)
        }
        let link = WidgetLink.health(nil).absoluteString
        guard let week = widgetWeekLine(sessions, prefs: prefs, leave: leave, ref: ref) else {
            return WidgetWorkoutDay(dayKey: key, dayStart: dayStart, dayEnd: dayEnd, icon: "figure.run",
                                    text: "", privateText: "", link: link)
        }
        return WidgetWorkoutDay(dayKey: key, dayStart: dayStart, dayEnd: dayEnd, icon: week.icon,
                                text: week.text, privateText: week.text, link: link)
    }

    /// 名字後面那一段：有距離「 5.2 公里」；沒有距離、有時間「・45 分鐘」；都沒有是空字串
    private static func widgetSessionWords(_ s: WorkoutSession) -> String {
        let km = s.totalDistanceKm
        if km >= 0.05 { return " " + WorkoutFormat.km(km) }
        let m = movingMinutes(s)
        if m >= 1 { return "・" + WorkoutFormat.total(minutes: m) }
        return ""
    }

    /// [健康 v7b] 這週的進度（看板主角那一種，同健康頁看板的 heroSport／weekProgress；請假同 WorkoutFacts.isLeave）。
    /// 順序：這週還沒動又請假 → 有目標 → 沒目標有公里 → 沒目標沒公里（看上週）。一筆運動都沒有回 nil。
    /// 例（judge §8.0，10/15 週四、目標 20）：「這週跑了 14.6 公里・目標 20」；週日達標「這週跑了 20.6 公里・達標」；
    /// 沒設目標「這週跑了 14.6 公里」；週一還沒跑、沒目標「新的一週・上週跑了 14.6 公里」（週二起「這週還沒跑・上週跑了 …」）；
    /// 有目標的週一「這週跑了 0 公里・目標 20」；這週請假還沒動「這週請假・上週跑了 13.3 公里」；只有重訓「這週練了 2 次」
    static func widgetWeekLine(_ sessions: [WorkoutSession], prefs: WorkoutPrefs, leave: WorkoutLeaveBook,
                               ref: Date) -> (icon: String, text: String)? {
        guard !sessions.isEmpty else { return nil }
        let hasCardio = sessions.contains { !$0.cardioExercises.isEmpty }
        if !hasCardio {
            let w = week(of: ref)
            let n = sessions.filter { s in
                s.date >= w.start && s.date < w.end && s.date <= ref && !s.strengthExercises.isEmpty
            }.count
            guard n > 0 else { return nil }
            return ("dumbbell.fill", "這週練了 \(n) 次")
        }
        let hero = heroSport(prefs, sessions: sessions, now: ref)
        let v = verb(hero)
        let p = weekProgress(sessions, prefs: prefs, sport: hero, now: ref)
        let last = lastWeekKm(sessions, sport: hero, now: ref)
        if p.doneKm < 0.05 && isLeave(leave, weekOf: ref) {
            let tail: String = last >= 0.05 ? "・上週\(v)了 " + WorkoutFormat.km(last) : ""
            return (hero.icon, "這週請假" + tail)
        }
        if let g = p.goalKm {
            if p.reached {
                return (hero.icon, "這週\(v)了 " + WorkoutFormat.km(p.doneKm) + "・達標")
            }
            return (hero.icon, "這週\(v)了 " + HealthPageData.bigKm(p.doneKm) + "・目標 " + widgetGoalNumber(g))
        }
        if p.doneKm >= 0.05 {
            return (hero.icon, "這週\(v)了 " + WorkoutFormat.km(p.doneKm))
        }
        guard last >= 0.05 else { return nil }
        let head: String = weekdayIndex(ref) == 0 ? "新的一週" : "這週還沒\(v)"
        return (hero.icon, head + "・上週\(v)了 " + WorkoutFormat.km(last))
    }

    /// 目標格同一套寫法的數字（整數不寫小數「20」、其他「12.5」）：HealthPageData.goalKmText 去掉「 公里」
    private static func widgetGoalNumber(_ km: Double) -> String {
        HealthPageData.goalKmText(km).replacingOccurrences(of: " 公里", with: "")
    }
}

// MARK: - 我的行事曆

extension WorkoutFacts {

    /// [健康 v7b] 那一天的運動（開始時間在那一天，舊到新）。cal 傳我的行事曆自己的 Calendar（Calendar.current），兩邊同一天
    static func sessions(on day: Date, in sessions: [WorkoutSession],
                         calendar cal: Calendar = .current) -> [WorkoutSession] {
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        let hits = sessions.filter { $0.date >= start && $0.date < end }
        return hits.sorted { a, b in a.date < b.date }
    }

    /// [健康 v7b] 我的行事曆一列的標題：「晨跑 5.2 公里」「河濱自行車道 23.4 公里」；沒有距離「胸推日 45 分鐘」；都沒有「重量訓練」
    static func calendarTitle(_ s: WorkoutSession) -> String {
        let name = title(s)
        let km = s.totalDistanceKm
        if km >= 0.05 { return name + " " + WorkoutFormat.km(km) }
        let m = movingMinutes(s)
        if m >= 1 { return name + " " + WorkoutFormat.total(minutes: m) }
        return name
    }

    /// [健康 v7b] 我的行事曆一列的小字：「跑步・32:10」「健走・38:40」；重訓「重訓」；手錶記的多「・Apple Watch」
    static func calendarDetail(_ s: WorkoutSession) -> String {
        var parts: [String] = [s.primarySport.displayName]
        let m = movingMinutes(s)
        if s.totalDistanceKm >= 0.05, m > 0 {
            parts.append(WorkoutFormat.clock(minutes: m))
        }
        if source(of: s) == .watch {
            parts.append("Apple Watch")
        }
        return parts.joined(separator: "・")
    }
}

// MARK: - 運動里程碑（記成人生里程碑）

/// [健康 v7b] 一個運動里程碑（自動算、不存）。清單照 design_C §2.8，主控挑過（judge §1.3：記成人生里程碑是 C 的、v7 做）：
///   第一次：跑完 5 公里／10 公里／半馬／全馬；騎超過 50／100 公里
///   累積（各運動分開）：跑步 100／500／1,000；騎車 500／1,000／3,000；健走 100／500 公里
///   連續：12／26／52 週有運動（同看板的連續週數：有任何一趟就算、請假週不加不斷）
///   次數：第 100、365 次運動
/// 破個人紀錄不放（個人紀錄卡已經有，一年會破好幾次，進人生里程碑會洗版：design_C 待決定 8 的理由）
struct WorkoutMilestone: Identifiable, Equatable {
    /// 「run.first.10k」「run.total.500」「bike.first.100」「streak.26」「count.100」：記成人生里程碑時存 LifeMilestone.sourceKey
    let key: String
    /// 「第一次跑完 10 公里」「跑步累積 500 公里」「連續 26 週有運動」「第 100 次運動」
    let title: String
    /// 達成那一趟的開始時間（人生里程碑的日期）
    let date: Date
    /// 達成那一趟（成果頁、健康頁點了開它）
    let sessionId: UUID
    /// 人生里程碑備註的預設：「10.3 公里・1:06:40」「河濱晨跑 5.2 公里」「從 2026/4/13 那週起」
    let note: String
    /// 圖示圓的顏色：那一種運動；nil＝綠（連續、次數）
    let sport: WorkoutSport?

    var id: String { key }
    /// SF Symbol（全部一樣：終點方格旗）
    var icon: String { "flag.checkered" }
}

extension WorkoutFacts {

    /// 第一次跑完：（門檻公里、key 尾巴、標題）。比的是一位小數（畫面上寫成 10.0 就算）
    static let milestoneRunFirsts: [(km: Double, tag: String, title: String)] = [
        (5, "5k", "第一次跑完 5 公里"),
        (10, "10k", "第一次跑完 10 公里"),
        (21.0975, "half", "第一次跑完半馬"),
        (42.195, "full", "第一次跑完全馬")
    ]
    /// 第一次騎超過
    static let milestoneBikeFirsts: [Double] = [50, 100]
    /// 累積（各運動分開）
    static let milestoneTotals: [(sport: WorkoutSport, kms: [Double])] = [
        (.run, [100, 500, 1_000]),
        (.bike, [500, 1_000, 3_000]),
        (.walk, [100, 500])
    ]
    /// 連續幾週有運動
    static let milestoneStreaks: [Int] = [12, 26, 52]
    /// 第幾次運動
    static let milestoneCounts: [Int] = [100, 365]

    /// [健康 v7b] 全部達成過的運動里程碑，達成日舊到新（同一天照上面清單的順序）。
    /// 照開始時間由舊到新掃一遍，記下「第幾趟讓它成立」。leave：請假的那幾週（WorkoutFacts.leaveWeeks(LifeStore.workoutLeave)）
    static func milestones(_ sessions: [WorkoutSession], leave: Set<Date> = []) -> [WorkoutMilestone] {
        let ordered = sessions.sorted { a, b in
            if a.date != b.date { return a.date < b.date }
            return a.id.uuidString < b.id.uuidString
        }
        var out: [WorkoutMilestone] = []
        var done = Set<String>()
        var totals: [WorkoutSport: Double] = [:]
        var count = 0
        for s in ordered {
            // 第一次跑完、騎超過（這一趟裡那一種運動的公里）
            let runKm = sportKm(s, .run)
            for f in milestoneRunFirsts {
                let key = "run.first." + f.tag
                if !done.contains(key), oneDecimal(runKm) >= oneDecimal(f.km) {
                    done.insert(key)
                    out.append(WorkoutMilestone(key: key, title: f.title, date: s.date, sessionId: s.id,
                                                note: firstNote(km: runKm, s), sport: .run))
                }
            }
            let bikeKm = sportKm(s, .bike)
            for t in milestoneBikeFirsts {
                let key = "bike.first." + String(Int(t))
                if !done.contains(key), oneDecimal(bikeKm) >= oneDecimal(t) {
                    done.insert(key)
                    out.append(WorkoutMilestone(key: key, title: "第一次騎超過 \(groupedInt(t)) 公里", date: s.date,
                                                sessionId: s.id, note: firstNote(km: bikeKm, s), sport: .bike))
                }
            }
            // 累積
            for row in milestoneTotals {
                let km = sportKm(s, row.sport)
                guard km > 0 else { continue }
                let total = (totals[row.sport] ?? 0) + km
                totals[row.sport] = total
                for t in row.kms {
                    let key = row.sport.rawValue + ".total." + String(Int(t))
                    if !done.contains(key), total >= t - 0.05 {
                        done.insert(key)
                        out.append(WorkoutMilestone(key: key,
                                                    title: row.sport.displayName + "累積 \(groupedInt(t)) 公里",
                                                    date: s.date, sessionId: s.id,
                                                    note: title(s) + " " + WorkoutFormat.km(km), sport: row.sport))
                    }
                }
            }
            // 第幾次運動（算數的才算：1 分鐘以上或有重訓動作，同連續週數）
            if counts(s) {
                count += 1
                for n in milestoneCounts where count == n {
                    let key = "count." + String(n)
                    if !done.contains(key) {
                        done.insert(key)
                        out.append(WorkoutMilestone(key: key, title: "第 \(n) 次運動", date: s.date, sessionId: s.id,
                                                    note: title(s), sport: nil))
                    }
                }
            }
        }
        out.append(contentsOf: streakMilestones(ordered, leave: leave, done: done))
        return out.sorted { a, b in
            if a.date != b.date { return a.date < b.date }
            return milestoneRank(a.key) < milestoneRank(b.key)
        }
    }

    /// 連續 12／26／52 週：從第一個有運動的週往後一週一週數（有運動 +1；沒運動但請假：不加、不斷；都沒有：歸零），
    /// 第一次數到 n 的那一週裡第一趟算數的運動就是達成的那一趟。ordered 已經舊到新
    private static func streakMilestones(_ ordered: [WorkoutSession], leave: Set<Date>,
                                         done: Set<String>) -> [WorkoutMilestone] {
        var firstInWeek: [Date: WorkoutSession] = [:]
        for s in ordered where counts(s) {
            let w = weekStart(of: s.date)
            if firstInWeek[w] == nil { firstInWeek[w] = s }
        }
        guard let first = firstInWeek.keys.min(), let last = firstInWeek.keys.max() else { return [] }
        var out: [WorkoutMilestone] = []
        var seen = done
        var streak = 0
        var since: Date? = nil
        var cursor = first
        var guardCount = 0
        while cursor <= last && guardCount < 3_000 {
            guardCount += 1
            if let s = firstInWeek[cursor] {
                if streak == 0 { since = cursor }
                streak += 1
                for n in milestoneStreaks where streak == n {
                    let key = "streak." + String(n)
                    if !seen.contains(key) {
                        seen.insert(key)
                        let from: String = since.map { "從 " + WorkoutFormat.date($0) + " 那週起" } ?? ""
                        out.append(WorkoutMilestone(key: key, title: "連續 \(n) 週有運動", date: s.date,
                                                    sessionId: s.id, note: from, sport: nil))
                    }
                }
            } else if !leave.contains(cursor) {
                streak = 0
                since = nil
            }
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        return out
    }

    /// 同一天達成好幾個時的順序：第一次跑完 → 第一次騎超過 → 累積（跑、騎、走）→ 次數 → 連續
    private static func milestoneRank(_ key: String) -> Int {
        if key.hasPrefix("run.first.") { return 0 }
        if key.hasPrefix("bike.first.") { return 1 }
        if key.hasPrefix("run.total.") { return 2 }
        if key.hasPrefix("bike.total.") { return 3 }
        if key.hasPrefix("walk.total.") { return 4 }
        if key.hasPrefix("count.") { return 5 }
        return 6
    }

    /// 這一趟裡某一種運動的公里（有氧動作加總）
    private static func sportKm(_ s: WorkoutSession, _ sport: WorkoutSport) -> Double {
        var km = 0.0
        for e in s.exercises where e.kind == .cardio && e.resolvedSport == sport {
            km += max(0, e.distanceKm)
        }
        return km
    }

    /// 一位小數比大小（10.04 寫成 10.0：算跑完 10 公里）
    private static func oneDecimal(_ km: Double) -> Int {
        guard km.isFinite, km > 0 else { return 0 }
        return Int((km * 10).rounded())
    }

    /// 「10.3 公里・1:06:40」（移動時間；沒有時間只寫公里）
    private static func firstNote(km: Double, _ s: WorkoutSession) -> String {
        let m = movingMinutes(s)
        guard m > 0 else { return WorkoutFormat.km(km) }
        return WorkoutFormat.km(km) + "・" + WorkoutFormat.clock(minutes: m)
    }

    /// 「1,000」「3,000」「500」（整數、千分位；不用 NumberFormatter：地區設定不同也一樣）
    static func groupedInt(_ v: Double) -> String {
        guard v.isFinite else { return "0" }
        let n = Int(v.rounded())
        let raw = String(abs(n))
        var out = ""
        for (i, ch) in raw.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        let body = String(out.reversed())
        return n < 0 ? "-" + body : body
    }

    /// [健康 v7b] 這一趟達成的（成果頁那張卡）。照達成順序
    static func milestones(reachedBy id: UUID, in sessions: [WorkoutSession],
                           leave: Set<Date> = []) -> [WorkoutMilestone] {
        milestones(sessions, leave: leave).filter { $0.sessionId == id }
    }

    /// [健康 v7b] 最近 days 天內達成的，新到舊、最多 limit 個（健康頁「健康里程碑」上面那幾列；記過沒在畫面上看 isRecorded）
    static func recentMilestones(_ sessions: [WorkoutSession], leave: Set<Date> = [], now: Date = Date(),
                                 days: Int = 90, limit: Int = 5) -> [WorkoutMilestone] {
        let from = now.addingTimeInterval(-Double(days) * 86_400)
        let hits = milestones(sessions, leave: leave).filter { $0.date >= from && $0.date <= now }
        return Array(hits.reversed().prefix(max(0, limit)))
    }

    /// [健康 v7b] 記成人生里程碑了沒：有一筆的 sourceKey 是這個 key；或（還沒更新的 iPad 存過、sourceKey 被丟掉時）
    /// 健康類、同一天、標題或備註跟預設的一樣
    static func isRecorded(_ m: WorkoutMilestone, in life: [LifeMilestone]) -> Bool {
        recordedMilestone(m, in: life) != nil
    }

    /// [健康 v7b] 記過的那一筆（點了可以去編輯）；沒有回 nil
    static func recordedMilestone(_ m: WorkoutMilestone, in life: [LifeMilestone]) -> LifeMilestone? {
        if let hit = life.first(where: { $0.sourceKey == m.key }) { return hit }
        return life.first { item in
            item.category == .health && calendar.isDate(item.date, inSameDayAs: m.date)
                && (item.title == m.title || (!m.note.isEmpty && item.note == m.note))
        }
    }

    /// [健康 v7b] 要存的那一筆人生里程碑：健康類、日期＝達成那一趟、備註＝預設、sourceKey＝key。
    /// title 是使用者在提示框改過的字（去頭尾空白；空的用預設標題）
    static func lifeMilestone(_ m: WorkoutMilestone, title: String) -> LifeMilestone {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var item = LifeMilestone(title: t.isEmpty ? m.title : t, date: m.date, category: .health, note: m.note)
        item.sourceKey = m.key
        return item
    }
}

// MARK: - 累積公里換風景

/// [健康 v7b] 健康頁看板的風景跟著「今年」累積公里換（judge §3.12：河堤 → 黃昏河濱 → 山路 → 海岸；門檻照 U4 第 13 條）。
/// 每年 1/1 從清晨河堤重新走一次。看的是看板主角那一種（跑、走、登山同一組門檻；騎車公里多，門檻 ×4）。
/// rawValue 存進 HealthWeekScene.stage（只放記憶體，不存檔）
enum HealthSceneryStage: Int, CaseIterable, Equatable {
    /// 0–49 公里：清晨河堤（v3 的樣子）
    case dawnRiver = 0
    /// 50–249：黃昏河濱，遠方多一座橋
    case duskRiver = 1
    /// 250–999：山路，遠方多一排山
    case mountain = 2
    /// 1,000 以上：海岸，遠方是海和一座燈塔
    case coast = 3

    /// 「清晨河堤」「黃昏河濱」「山路」「海岸」（收穫那一句、VoiceOver）
    var name: String {
        switch self {
        case .dawnRiver: return "清晨河堤"
        case .duskRiver: return "黃昏河濱"
        case .mountain: return "山路"
        case .coast: return "海岸"
        }
    }

    /// 看板膠囊「今年 523.4 公里」的圖示
    var icon: String {
        switch self {
        case .dawnRiver: return "sunrise.fill"
        case .duskRiver: return "sunset.fill"
        case .mountain: return "mountain.2.fill"
        case .coast: return "water.waves"
        }
    }

    /// 換到這一景要今年累積幾公里（跑、走、登山；騎車 ×4）
    func threshold(for sport: WorkoutSport) -> Double {
        let base: Double
        switch self {
        case .dawnRiver: base = 0
        case .duskRiver: base = 50
        case .mountain: base = 250
        case .coast: base = 1_000
        }
        return sport == .bike ? base * 4 : base
    }
}

extension WorkoutFacts {

    /// [健康 v7b] 這一天那一年的 1/1 00:00（西曆、手機時區）
    static func yearStart(of date: Date) -> Date {
        let y = calendar.component(.year, from: date)
        return calendar.date(from: DateComponents(year: y, month: 1, day: 1)) ?? calendar.startOfDay(for: date)
    }

    /// [健康 v7b] 今年（now 那一年）某一種運動的公里（一趟裡只加那種運動的動作，同 weekDistanceKm）
    static func yearDistanceKm(_ sessions: [WorkoutSession], sport: WorkoutSport, now: Date = Date()) -> Double {
        let start = yearStart(of: now)
        let end = calendar.date(byAdding: .year, value: 1, to: start) ?? start.addingTimeInterval(366 * 86_400)
        return distanceKm(sessions, sport: sport, from: start, to: end)
    }

    /// [健康 v7b] 今年累積 km 是哪一景（門檻差不到 0.05 也算到了：畫面一位小數已經寫成一樣）
    static func sceneryStage(km: Double, sport: WorkoutSport) -> HealthSceneryStage {
        var best = HealthSceneryStage.dawnRiver
        for st in HealthSceneryStage.allCases where km >= st.threshold(for: sport) - 0.05 {
            best = st
        }
        return best
    }

    /// [健康 v7b] 看板下的膠囊「今年 523.4 公里」（圖示跟著風景）；今年還沒有這一種回 nil
    static func yearChip(_ sessions: [WorkoutSession], sport: WorkoutSport, now: Date = Date()) -> MoneyBoardChip? {
        let km = yearDistanceKm(sessions, sport: sport, now: now)
        guard km >= 0.05 else { return nil }
        let st = sceneryStage(km: km, sport: sport)
        return MoneyBoardChip(icon: st.icon, label: "今年", value: WorkoutFormat.km(km))
    }

    /// [健康 v7b] VoiceOver：「今年跑了 523.4 公里」；今年還沒有回 nil
    static func yearSpoken(_ sessions: [WorkoutSession], sport: WorkoutSport, now: Date = Date()) -> String? {
        let km = yearDistanceKm(sessions, sport: sport, now: now)
        guard km >= 0.05 else { return nil }
        return "今年\(verb(sport))了 " + WorkoutFormat.km(km)
    }

    /// [健康 v7b] 這一趟讓看板換了風景（成果頁「這趟的收穫」）：「今年跑了 250.3 公里，看板換成山路了」。
    /// sport＝看板主角（WorkoutFacts.heroSport）；這一趟沒有那一種、沒跨過門檻回 nil。
    /// 算法：同一年、比這一趟早開始的那一種公里（不含這一趟）→ 加上這一趟 → 前後是不是不同景
    static func sceneryGainText(for s: WorkoutSession, among sessions: [WorkoutSession],
                                sport: WorkoutSport) -> String? {
        sceneryGain(for: s, among: sessions, sport: sport)?.text
    }

    /// [健康 v7b] 同 sceneryGainText，多回換到哪一景（收穫那一列的圖示用 stage.icon）
    static func sceneryGain(for s: WorkoutSession, among sessions: [WorkoutSession],
                            sport: WorkoutSport) -> (text: String, stage: HealthSceneryStage)? {
        let trip = sportKm(s, sport)
        guard trip > 0 else { return nil }
        let start = yearStart(of: s.date)
        let others = sessions.filter { $0.id != s.id }
        let before = distanceKm(others, sport: sport, from: start, to: s.date)
        let after = before + trip
        let a = sceneryStage(km: before, sport: sport)
        let b = sceneryStage(km: after, sport: sport)
        guard b.rawValue > a.rawValue else { return nil }
        return ("今年\(verb(sport))了 " + WorkoutFormat.km(after) + "，看板換成\(b.name)了", b)
    }
}

// MARK: - 成果頁心率

/// [健康 v7b] 一筆心率（Apple 健康讀回來的：手錶、心率帶記的；iPhone 自己量不到）。只放記憶體，不存、不進 iCloud
struct WorkoutHeartSample: Equatable {
    let date: Date
    /// 每分鐘幾下
    let bpm: Double
}

/// [健康 v7b] 這一趟要讀哪一段時間的心率（開始～結束，含暫停）
struct WorkoutHeartWindow: Equatable {
    let start: Date
    let end: Date
}

/// [健康 v7b] 心率小折線的一點（從開始過了幾分鐘、那一段的平均）
struct WorkoutHeartPoint: Identifiable, Equatable {
    let minute: Double
    let bpm: Double
    var id: Double { minute }
}

/// [健康 v7b] 成果頁 ⑦ 心率（judge §5.2 ⑦）：「平均 152・最高 171」＋小折線
struct WorkoutHeartSummary: Equatable {
    let average: Int
    let maximum: Int
    /// 最多 60 點（等分時間、每段平均），舊到新
    let points: [WorkoutHeartPoint]
    /// 縱軸範圍（最低那一點 −5、最高 +5，取到 5 的倍數）
    let lowBpm: Double
    let highBpm: Double
    /// 橫軸長度（分鐘，開始到結束）
    let minutes: Double

    /// 「平均 152・最高 171」
    var text: String { "平均 \(average)・最高 \(maximum)" }
    /// VoiceOver：「心率平均每分鐘 152 下，最高 171 下」
    var spoken: String { "心率平均每分鐘 \(average) 下，最高 \(maximum) 下" }
}

extension WorkoutFacts {

    /// 少於這麼多筆不畫（手錶沒戴好、只量到一兩下）
    static let heartMinSamples = 5
    /// 小折線最多幾點
    static let heartMaxPoints = 60

    /// [健康 v7b] 要讀心率的時間：開始～結束（WorkoutFacts.endDate：App 記的是真正結束；含暫停）。
    /// 移動時間不到 2 分鐘、時間不合理回 nil（整區不出現、也不去讀）
    static func heartWindow(_ s: WorkoutSession) -> WorkoutHeartWindow? {
        guard movingMinutes(s) >= 2 else { return nil }
        let end = endDate(s)
        guard end.timeIntervalSince(s.date) >= 120 else { return nil }
        return WorkoutHeartWindow(start: s.date, end: end)
    }

    /// [健康 v7b] 心率樣本 → 平均、最高、小折線。只收時間在窗內、30～240 下的；不到 heartMinSamples 筆回 nil（整區不出現）。
    /// 平均＝每一筆的平均（四捨五入）；最高＝最高那一筆；折線＝時間等分成 min(60, 筆數) 段、每段平均（空的段跳過）
    static func heartSummary(_ samples: [WorkoutHeartSample], window: WorkoutHeartWindow) -> WorkoutHeartSummary? {
        let span = window.end.timeIntervalSince(window.start)
        guard span > 0 else { return nil }
        let good = samples.filter { x in
            x.bpm.isFinite && x.bpm >= 30 && x.bpm <= 240 && x.date >= window.start && x.date <= window.end
        }
        guard good.count >= heartMinSamples else { return nil }
        let sum = good.reduce(0.0) { $0 + $1.bpm }
        let avg = sum / Double(good.count)
        let top = good.reduce(0.0) { max($0, $1.bpm) }
        let n = min(heartMaxPoints, good.count)
        var bucketSum = [Double](repeating: 0, count: n)
        var bucketCount = [Int](repeating: 0, count: n)
        for x in good {
            let f = x.date.timeIntervalSince(window.start) / span
            let i = min(n - 1, max(0, Int(f * Double(n))))
            bucketSum[i] += x.bpm
            bucketCount[i] += 1
        }
        var points: [WorkoutHeartPoint] = []
        for i in 0..<n where bucketCount[i] > 0 {
            let mid = (Double(i) + 0.5) / Double(n) * span / 60
            points.append(WorkoutHeartPoint(minute: mid, bpm: bucketSum[i] / Double(bucketCount[i])))
        }
        let lowest = points.reduce(top) { min($0, $1.bpm) }
        let low = max(0, ((lowest - 5) / 5).rounded(.down) * 5)
        let high = ((top + 5) / 5).rounded(.up) * 5
        return WorkoutHeartSummary(average: Int(avg.rounded()), maximum: Int(top.rounded()), points: points,
                                   lowBpm: low, highBpm: high, minutes: span / 60)
    }
}
