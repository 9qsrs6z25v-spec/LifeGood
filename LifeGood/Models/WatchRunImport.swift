import Foundation

// MARK: - 手錶記的跑步帶進 iPhone、這週跑步送手錶（手錶 v4，v25.580；只屬於主 App）
//
// watch/judge.md §2.9、§5.7、§評論回覆 🟠1；watch/build/v4/brief.md §2；模擬：watch/build/v4/sim_v4.py（同名函式，改了兩邊一起改）。
//
// • WatchRunImport：HealthKitManager.makeImported／HealthSyncCenter.importedSession 帶進手錶那一趟時用的純規則——
//   是不是 LifeGood 手錶記的（isLifeGoodWatch：bundle id 是 iPhone 的 id＋「.watchkitapp」開頭，或附註 LifeGood.recorder
//   是「watch …」；[v25.586] Apple 在 iPhone 上把手錶 LifeGood 存的來源標成 iPhone 的 id，所以 isOwn 另外看「在手錶上記的」、
//   附註 isWatchRecorder，手錶記的照樣當成手錶的帶進來）、Apple 健康的暫停事件配成暫停清單（pauses：
//   手錶的自動暫停 motionPaused 記成 auto）、LifeGood.kmTimes 換成每公里分段（splits）、路線照暫停切段（segmented：
//   暫停前後不連線，最快幾公里也不會把暫停那幾分鐘算進去）。
// • WatchRunWeekBuilder：WatchExtrasWriter 寫手錶快取時算這週跑步（WatchRunWeek）：跟健康頁看板同一套 WorkoutFacts；
//   seen＝這週每一趟的 Apple 健康編號＋合成用掉的手錶編號＋最近 40 個「不再帶進來」（在 iPhone 刪掉的手錶那一趟）——
//   手錶自己記的那一趟在 seen 裡＝iPhone 已經算過或你刪掉了，手錶不再自己加（評論 🟠1 的四個洞：刪掉的、不到 60 秒的、
//   別種運動、週日歸零；後三個在手錶那邊擋，WatchRunText.home）。
//   ⚠️ 只讀 LifeStore（App 開著、寫快照的時候才叫）；被手錶叫醒的冷啟動不走這裡（judge §7.8-6）。
//
// [手錶 v5] v25.582（watch/judge.md §2.12、§2.13、§6.1；watch/build/v5/brief.md §2；sim_v5.py 同名函式）：
// • WatchRunWeekBuilder.make 多填 recent（這週那幾趟）、latest（最新一趟的亮點字）——組法在 WatchRunRecentBuilder：
//   – 名字兩種：抬手照你取的（「河濱晨跑」）、手腕放下你取的換時段名（「晨跑」，WorkoutFacts.isCustomTitle）
//   – 路線只送 0～1000 的相對形狀（等比例、置中、北在上、最多 40 點、同一點連續的只留一個）：**沒有經緯度、沒有比例尺**
//   – 亮點照存檔時算好的 WorkoutSession.highlights 寫字（WorkoutFacts.routeCapsule／routeDeltaText／recordValueText，
//     不重算）：「河濱老路線・第 12 次」＋「比上次快 42 秒」、手腕放下「老路線・第 12 次」、「最快 5 公里 新紀錄 30:51（快 18 秒）」
//   – 不送：地點（place）、備註、心率、照片、同行者、Apple 健康以外的編號

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
        return isWatchRecorder(recorder)
    }

    /// [v25.586] LifeGood.recorder 附註是不是手錶寫的（「watch」／「watch 25.580」）。
    /// 手錶 LifeGood 存的運動，Apple 在 iPhone 上把來源標成 iPhone App 的 id（不是 .watchkitapp），所以要靠這個附註分辨
    static func isWatchRecorder(_ recorder: String?) -> Bool {
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
                            seen: unique,
                            recent: WatchRunRecentBuilder.recent(sessions, now: now),
                            latest: WatchRunRecentBuilder.latest(sessions, now: now))
    }
}

/// [手錶 v5] 這週那幾趟、最新一趟的亮點字（WatchRunWeekBuilder.make 叫；App 開著才有 LifeStore）。sim_v5.py 同名函式
enum WatchRunRecentBuilder {
    /// 這週最多送幾趟
    static let maxRecent = 5
    /// 路線形狀最多幾點
    static let shapeMaxPoints = 40
    /// 0～1000
    static let shapeScale: Double = 1000
    /// 整條路線框起來不到這麼大（公尺）不送形狀（原地繞圈、跑步機；同手錶 WatchRunMath.shapeMinSpanMeters）
    static let shapeMinSpanMeters: Double = 50
    /// latest：多久以內的那一趟（週日晚上跑、週一才帶進來也找得到）
    static let latestWindow: TimeInterval = 2 * 86_400
    /// 有路線的四種（手錶 WatchSport 也只有這四種）
    static let sports: Set<WorkoutSport> = [.run, .walk, .bike, .hike]

    /// 這週（週一 00:00 起）跑走騎登山的那幾趟，新到舊、最多 5 趟
    static func recent(_ sessions: [WorkoutSession], now: Date) -> [WatchRunRecent] {
        let week = WorkoutFacts.week(of: now)
        let list = sessions.filter { s in
            s.date >= week.start && s.date < week.end && sports.contains(s.primarySport)
        }.sorted { $0.date > $1.date }
        return Array(list.prefix(maxRecent)).map { row($0) }
    }

    /// 一趟 → 手錶清單的一列
    static func row(_ s: WorkoutSession) -> WatchRunRecent {
        let sport = s.primarySport
        var km = 0.0
        for e in s.exercises where e.kind == .cardio && e.resolvedSport == sport {
            km += max(0, e.distanceKm)
        }
        let route = s.firstRouteExercise?.route ?? []
        return WatchRunRecent(id: s.id.uuidString,
                              workoutId: workoutId(s),
                              sport: sport.rawValue,
                              title: shownTitle(s),
                              privateTitle: privateTitle(s),
                              start: s.date,
                              km: km,
                              movingSeconds: max(0, WorkoutFacts.movingMinutes(s) * 60),
                              byLifeGoodWatch: s.health?.byLifeGoodWatch == true,
                              shape: shape(route),
                              highlight: highlight(s))
    }

    /// Apple 健康編號：跟手錶那筆合成過的用手錶那筆（mergedWatchUUID），不然 healthKitUUID
    static func workoutId(_ s: WorkoutSession) -> String? {
        s.health?.mergedWatchUUID ?? s.healthKitUUID
    }

    /// 抬手的名字：照 iPhone 畫面上那一支（WorkoutFacts.title：自己取的照用；只是運動名「跑步」的照時段「夜跑」）
    static func shownTitle(_ s: WorkoutSession) -> String {
        WorkoutFacts.title(s)
    }

    /// 手腕放下的名字：你自己取的（可能是地名）換成時段名「晨跑」；本來就是時段名、運動名的照用
    static func privateTitle(_ s: WorkoutSession) -> String {
        let t = shownTitle(s)
        guard WorkoutFacts.isCustomTitle(t) else { return t }
        return WorkoutFacts.timeOfDayName(s.primarySport, start: s.date)
    }

    /// 最新一趟 LifeGood 手錶記的（或跟手錶那筆合成過的）、2 天內：它的亮點字。都沒有亮點也送（手錶才知道「算好了、沒有」）
    static func latest(_ sessions: [WorkoutSession], now: Date) -> WatchRunHighlight? {
        let from = now.addingTimeInterval(-latestWindow)
        var best: WorkoutSession? = nil
        for s in sessions where s.date >= from && s.date <= now {
            guard s.health?.byLifeGoodWatch == true || s.health?.mergedWatchUUID != nil else { continue }
            if let b = best, b.date >= s.date { continue }
            best = s
        }
        guard let s = best else { return nil }
        return highlight(s) ?? WatchRunHighlight(sessionId: s.id.uuidString, workoutId: workoutId(s), start: s.date)
    }

    /// 這一趟的亮點字（存檔時算好的 s.highlights；不重算）；同一條路第 2 次起、破紀錄都沒有回 nil
    static func highlight(_ s: WorkoutSession) -> WatchRunHighlight? {
        var h = WatchRunHighlight(sessionId: s.id.uuidString, workoutId: workoutId(s), start: s.date)
        var any = false
        if let head = WorkoutFacts.routeCapsule(s), let m = s.highlights?.route, let n = m.count {
            h.routeHead = head
            h.routePrivateHead = "老路線・第 \(n) 次"
            if let d = WorkoutFacts.routeDeltaText(m.deltaSeconds) {
                h.routeDelta = d
                h.routeFaster = d.hasPrefix("比上次快")
            }
            any = true
        }
        for mark in s.highlights?.records ?? [] {
            guard let kind = WorkoutRecordKind(rawValue: mark.kind) else { continue }
            let value = WorkoutFacts.recordValueText(kind, value: mark.value)
            h.recordShort = kind.title + " " + value
            h.recordLine = kind.title + " 新紀錄 " + value + "（" + gain(kind, mark) + "）"
            any = true
            break
        }
        return any ? h : nil
    }

    /// 「快 18 秒」「快 1 分 05 秒」；最長「多 0.3 公里」（同 WorkoutFacts.recordGainText 括號裡那一段）
    static func gain(_ kind: WorkoutRecordKind, _ m: WorkoutRecordMark) -> String {
        if kind.smallerIsBetter {
            let faster = WorkoutFormat.wholeSeconds(m.previous - m.value)
            let gap = faster >= 60 ? "\(faster / 60) 分 " + String(format: "%02d 秒", faster % 60) : "\(faster) 秒"
            return "快 " + gap
        }
        return "多 " + WorkoutFormat.kmNumber(m.value - m.previous) + " 公里"
    }

    /// 路線 → 0～1000 相對形狀：等距投影（經度乘 cos 緯度）、框起來等比例縮進 0～1000、置中、北在上；
    /// 平均抽到最多 40 點（最後一點一定留）、同一點連續的只留一個；第幾段照 RoutePoint.seg（nil＝0）。
    /// 不到 2 點、整條框起來不到 50 公尺回 nil（不送）。**輸出裡沒有經緯度**
    static func shape(_ route: [RoutePoint], maxPoints: Int = shapeMaxPoints) -> [WatchRunShapeXY]? {
        let pts = route.filter { $0.lat.isFinite && $0.lon.isFinite && abs($0.lat) <= 90 && abs($0.lon) <= 180 }
        guard pts.count >= 2, maxPoints >= 2 else { return nil }
        var minLat = pts[0].lat, maxLat = pts[0].lat, minLon = pts[0].lon, maxLon = pts[0].lon
        for p in pts {
            minLat = min(minLat, p.lat)
            maxLat = max(maxLat, p.lat)
            minLon = min(minLon, p.lon)
            maxLon = max(maxLon, p.lon)
        }
        let k = cos((minLat + maxLat) / 2 * .pi / 180)
        let w = (maxLon - minLon) * k
        let h = maxLat - minLat
        let span = max(w, h)
        // 1 度緯度約 111,195 公尺
        guard span > 0, span * 111_195 >= shapeMinSpanMeters else { return nil }
        let offX = (1 - w / span) / 2
        let offY = (1 - h / span) / 2
        var picked: [RoutePoint] = []
        if pts.count <= maxPoints {
            picked = pts
        } else {
            let step = Double(pts.count - 1) / Double(maxPoints - 1)
            for i in 0..<maxPoints {
                let idx = min(pts.count - 1, Int((Double(i) * step).rounded()))
                picked.append(pts[idx])
            }
        }
        var out: [WatchRunShapeXY] = []
        for p in picked {
            let x = offX + (p.lon - minLon) * k / span
            let y = offY + (maxLat - p.lat) / span
            let q = WatchRunShapeXY(x: unit(x), y: unit(y), s: max(0, p.seg ?? 0))
            if let last = out.last, last == q { continue }
            out.append(q)
        }
        return out.count >= 2 ? out : nil
    }

    /// 0～1 → 0～1000（夾住；NaN 當 0）
    static func unit(_ v: Double) -> Int {
        guard v.isFinite else { return 0 }
        return Int((min(max(v, 0), 1) * shapeScale).rounded())
    }
}
