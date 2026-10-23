import Foundation

// MARK: - 手錶記的跑步帶進 iPhone、這週跑步送手錶（手錶 v4，v25.580；只屬於主 App）
//
// watch/judge.md §2.9、§5.7、§評論回覆 🟠1；watch/build/v4/brief.md §2；模擬：watch/build/v4/sim_v4.py（同名函式，改了兩邊一起改）。
//
// • WatchRunImport：HealthKitManager.makeImported／HealthSyncCenter.importedSession 帶進手錶那一趟時用的純規則——
//   是不是 LifeGood 手錶記的（isLifeGoodWatch：bundle id 是 iPhone 的 id＋「.watchkitapp」開頭，或附註 LifeGood.recorder
//   是「watch …」；isOwn 照舊只認 iPhone 自己，手錶記的照樣當成手錶的帶進來）、Apple 健康的暫停事件配成暫停清單（pauses：
//   手錶的自動暫停 motionPaused 記成 auto）、LifeGood.kmTimes 換成每公里分段（splits）、路線照暫停切段（segmented：
//   暫停前後不連線，最快幾公里也不會把暫停那幾分鐘算進去）。
// • WatchRunWeekBuilder：WatchExtrasWriter 寫手錶快取時算這週跑步（WatchRunWeek）：跟健康頁看板同一套 WorkoutFacts；
//   seen＝這週每一趟的 Apple 健康編號＋合成用掉的手錶編號＋最近 40 個「不再帶進來」（在 iPhone 刪掉的手錶那一趟）——
//   手錶自己記的那一趟在 seen 裡＝iPhone 已經算過或你刪掉了，手錶不再自己加（評論 🟠1 的四個洞：刪掉的、不到 60 秒的、
//   別種運動、週日歸零；後三個在手錶那邊擋，WatchRunText.home）。
//   ⚠️ 只讀 LifeStore（App 開著、寫快照的時候才叫）；被手錶叫醒的冷啟動不走這裡（judge §7.8-6）。

enum WatchRunImport {
    /// 手錶 App 的 bundle id 是 iPhone 的 id 後面接這個（com.lifegood.app.watchkitapp）
    static let watchBundleSuffix = ".watchkitapp"

    /// 是 LifeGood 手錶記的：來源的 bundle id 是「iPhone 的 id＋.watchkitapp」開頭，或 LifeGood.recorder 附註是「watch」／「watch …」。
    /// 例：「com.lifegood.app.watchkitapp」→ true；「com.lifegood.app」（iPhone 自己寫的，isOwn）→ false；
    /// 「com.apple.health.…」（手錶內建體能訓練）→ false
    static func isLifeGoodWatch(bundleId: String, appBundleId: String, recorder: String?) -> Bool {
        let base = appBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.isEmpty && bundleId.hasPrefix(base + watchBundleSuffix) {
            return true
        }
        guard let r = recorder?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty else { return false }
        return r == WatchRunMeta.recorderPrefix || r.hasPrefix(WatchRunMeta.recorderPrefix + " ")
    }

    /// Apple 健康的一個暫停事件（HealthKitManager 把 HKWorkoutEvent 換成這個：pause／resume＝你按的，
    /// motionPaused／motionResumed＝手錶的自動暫停；其他事件不放進來）
    enum EventKind: Equatable {
        case pause
        case resume
        case autoPause
        case autoResume
    }

    struct Event: Equatable {
        var kind: EventKind
        var at: Date
    }

    /// 暫停事件 → 暫停清單（同 WorkoutPause；成果頁「暫停 2 次・1:10（都是自動）」）。
    /// 照時間排（同一刻照原本的順序）；沒在暫停時的第一個暫停事件開一段、之後第一個繼續事件關；暫停中又來的暫停、
    /// 沒在暫停時的繼續都不理。開頭是 motionPaused 的那一段記 auto＝true（你按的 nil，同 iPhone RunTracker）。
    /// 每一段夾在開始～結束之間；沒有長度的、最後沒繼續就結束的那一段不算（同 iPhone「按完成前的最後那次暫停不算」）
    static func pauses(_ events: [Event], start: Date, end: Date) -> [WorkoutPause] {
        let ordered = events.enumerated().sorted { a, b in
            if a.element.at != b.element.at { return a.element.at < b.element.at }
            return a.offset < b.offset
        }.map { $0.element }
        var out: [WorkoutPause] = []
        var openAt: Date? = nil
        var openAuto = false
        for e in ordered {
            switch e.kind {
            case .pause, .autoPause:
                if openAt == nil {
                    openAt = e.at
                    openAuto = e.kind == .autoPause
                }
            case .resume, .autoResume:
                if let s = openAt {
                    let a = max(s, start)
                    let b = min(e.at, end)
                    if b > a {
                        out.append(WorkoutPause(start: a, end: b, auto: openAuto ? true : nil))
                    }
                    openAt = nil
                }
            }
        }
        return out
    }

    /// LifeGood.kmTimes（每跑滿一公里那一刻的移動秒數）→ 每公里分段（同 RouteMath.kmSplits 的樣子：整公里 1,000 公尺；
    /// 最後不滿一公里的那段 50 公尺以上才給）。kmTimes 不是一個比一個大＝整份不用（回空的，iPhone 改用路線推算）。
    /// 例：[365, 735, 1105, 1485, 1851]、5.20 公里、1,924 秒 → 365、370、370、380、366 秒＋200 公尺 73 秒
    static func splits(kmTimes: [Double], distanceKm: Double, movingSeconds: Double) -> [WorkoutSplit] {
        var out: [WorkoutSplit] = []
        var prev = 0.0
        for t in kmTimes {
            guard t.isFinite, t > prev else { return [] }
            out.append(WorkoutSplit(meters: 1000, seconds: t - prev, climbM: nil))
            prev = t
        }
        let tail = distanceKm * 1000 - Double(kmTimes.count) * 1000
        if tail.isFinite, tail >= 50, movingSeconds.isFinite, movingSeconds > prev {
            out.append(WorkoutSplit(meters: tail, seconds: movingSeconds - prev, climbM: nil))
        }
        return out
    }

    /// 帶進來的路線（RoutePoint.t＝離開始幾秒，含暫停）照暫停切段：第 n 個暫停結束之後的點是第 n 段（0 段＝nil，
    /// 同 RoutePoint.seg 的寫法）。沒暫停、不到 2 點原樣
    static func segmented(_ route: [RoutePoint], pauses: [WorkoutPause], start: Date) -> [RoutePoint] {
        guard !pauses.isEmpty, route.count >= 2 else { return route }
        let ends = pauses.map { $0.end.timeIntervalSince(start) }.sorted()
        return route.map { (p: RoutePoint) -> RoutePoint in
            var q = p
            let n = ends.filter { $0 <= p.t }.count
            q.seg = n == 0 ? nil : n
            return q
        }
    }
}

enum WatchRunWeekBuilder {
    /// seen 多放最近幾個「不再帶進來」的編號（帳上最多 2,000 個，全送太大；在 iPhone 刪掉的手錶那一趟一定是最近的）
    static let ignoredTail = 40

    /// 這週跑步（WatchExtrasWriter 寫手錶快取時叫；App 開著才有 LifeStore）。數字全照 WorkoutFacts（健康頁看板同一套）
    static func make(sessions: [WorkoutSession], prefs: WorkoutPrefs, leave: Set<Date>, ignored: [String],
                     now: Date) -> WatchRunWeek {
        let sport = WorkoutFacts.heroSport(prefs, sessions: sessions, now: now)
        let week = WorkoutFacts.week(of: now)
        var dayKm = [Double](repeating: 0, count: 7)
        var seen: [String] = []
        var counted = false
        for s in sessions where s.date >= week.start && s.date < week.end {
            if WorkoutFacts.counts(s) { counted = true }
            let i = WorkoutFacts.weekdayIndex(s.date)
            for e in s.exercises where e.kind == .cardio && e.resolvedSport == sport {
                if i >= 0 && i < 7 { dayKm[i] += max(0, e.distanceKm) }
            }
            if let id = s.healthKitUUID { seen.append(id) }
            if let merged = s.health?.mergedWatchUUID { seen.append(merged) }
        }
        seen.append(contentsOf: ignored.suffix(ignoredTail))
        var unique: [String] = []
        var taken = Set<String>()
        for id in seen where !taken.contains(id) {
            taken.insert(id)
            unique.append(id)
        }
        return WatchRunWeek(generatedAt: now,
                            sport: sport.rawValue,
                            weekStart: week.start,
                            doneKm: WorkoutFacts.weekDistanceKm(sessions, sport: sport, weekOf: now),
                            goalKm: prefs.goalKm(for: sport),
                            runs: WorkoutFacts.weekCount(sessions, sport: sport, weekOf: now),
                            dayKm: dayKm,
                            streakWeeks: WorkoutFacts.streak(sessions, leave: leave, now: now).weeks,
                            weekCounted: counted,
                            seen: unique)
    }
}
