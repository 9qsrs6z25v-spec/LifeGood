import Foundation
import CoreLocation
// [v25.553] WorkoutPalette 用 Color；WorkoutRouteShape 用 CGPoint
import SwiftUI

// MARK: - 健康的一套數字（v25.552，健康 v2；health/judge.md §3.13）
//
// 運動的數字和字全 App 只算這一套（照 VehicleFacts／HouseFacts：純函式、值型別、日期一律西曆）。
// 健康頁的綠卡、訓練紀錄、跑步橫幅、開始運動、Apple 健康寫入都讀這裡；v3 的新看板、項目卡、成果頁也是。
//
// • 週：西曆、週一開始、手機時區；date 落在［週一 00:00, 下週一 00:00）。以前用手機地區設定，
//   台灣地區的 iPhone 有時把週日當第一天，週六騎車、週日跑步會被拆成兩週。
// • 連續週數：那一週有任何一趟運動（1 分鐘以上、或有重訓動作；跑、騎、走、登山、重訓、手錶記的都算）就算；
//   這週還沒動就從上週數（待決定 3）。
// • 大卡：手錶量的照用；沒有就用 MET 表估（（MET − 1）× 體重 × 小時），估的存回那一趟並記 kcalEstimated，
//   畫面前面加「約」、取到十位。以前一律 8 MET，健走 60 分鐘寫 576 大卡（現在約 180）。
// • 配速：一律 6'11"、秒數四捨五入（v25.551 起）；「6.2 分/公里」全部拿掉。騎車寫時速不寫配速。
// • 距離：清單、膠囊、看板一位小數「5.2 公里」；成果頁、跑步中兩位「5.20」；騎車跑步中 10 公里以上一位。
// • 時間：「32:10」「1:05:12」（從分鐘的小數算回秒）；合計才寫「2 小時 10 分」。
// • 爬升：不到 10 公尺寫「平路」；舊版記的（App 記、路線只有起點）是灌水的，當成不知道。
// • 存檔：App 記的一趟（按完成、救回中途存檔）一律走 makeSession(from:bodyWeightKg:)：
//   先用完整的點算每公里分段，再把路線簡化（誤差 1.5 公尺內、至少每 10 秒留一點；5 公里 889 → 約 228 點）。
// 模擬與驗算：health/build/v2/sim_v2.py（簡化、分段、大卡、週、連續週數、格式的數字例子都在裡面）。
//
// [v25.553] 健康 v3（新健康頁、項目卡、成果頁）加的，全部在檔尾「v3」那幾段：
// • 名字：title(_:)——名字只是運動名（「跑步」、手錶的「走路」、空白）就照時段取名（晨跑、晚走、晨騎、登山）；
//   scriptCaps(_:)——卡面手寫小字 MORNING／NOON／AFTERNOON／EVENING／NIGHT，週六日騎車 WEEKEND。
// • 看板主角 heroSport（自動＝近 28 天次數最多的有氧）、上週同期、每週目標進度 weekProgress、建議目標 suggestedGoal。
// • 每公里分段能不能用 validSplits（編輯過距離或時間就對不上，成果頁不顯示）、高度 elevation（GPS 平滑的形狀×存下來的爬升）、
//   配速五級 WorkoutPaceLevel、成果看板的「這一趟的路」trailScene、卡面路線形狀 routeShape、顏色 WorkoutPalette。
// 驗算：health/build/v3/sim_v3.py（judge §8.0 假資料：14.6 公里、3 次、多 3.6、連續 6 週、73%、剩 4 天、建議 20…）。

enum WorkoutFacts {

    // MARK: 週（週一開始、西曆、手機時區）

    /// 西曆、zh_TW、手機時區（autoupdating：出國換時區也跟著）
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "zh_TW")
        c.timeZone = TimeZone.autoupdatingCurrent
        c.firstWeekday = 2
        return c
    }()

    /// 這一天所在那一週的週一 00:00
    static func weekStart(of date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)    // 週日 1、週一 2 … 週六 7
        let back = (weekday + 5) % 7                               // 週一 0、週二 1 … 週日 6
        return calendar.date(byAdding: .day, value: -back, to: day) ?? day
    }

    /// 這一天所在那一週：［週一 00:00, 下週一 00:00）
    static func week(of date: Date) -> (start: Date, end: Date) {
        let s = weekStart(of: date)
        let e = calendar.date(byAdding: .day, value: 7, to: s) ?? s.addingTimeInterval(7 * 86_400)
        return (s, e)
    }

    static func isInWeek(_ date: Date, of reference: Date) -> Bool {
        let w = week(of: reference)
        return date >= w.start && date < w.end
    }

    // MARK: 一趟的基本數字

    /// 移動時間（分鐘）：整場時間有填用它（App 記的就是扣掉暫停的移動時間），不然用有氧動作的時間加總
    static func movingMinutes(_ s: WorkoutSession) -> Double {
        s.durationMinutes > 0 ? s.durationMinutes : s.totalCardioMinutes
    }

    /// 這一趟算不算「有運動」（連續週數用）：1 分鐘以上，或有重訓動作
    static func counts(_ s: WorkoutSession) -> Bool {
        movingMinutes(s) >= 1 || !s.strengthExercises.isEmpty
    }

    /// 這一趟怎麼記的；舊資料沒存：有 endedAt（v25.551 起 App 記的）或路線只存到起點（v25.550 以前 App 記的）→ App；
    /// 其他看不出來回 nil（手動補記和 Apple 健康帶進來的舊資料分不出來）
    static func source(of s: WorkoutSession) -> WorkoutSource? {
        if let x = s.source { return x }
        if s.endedAt != nil || s.isLegacyRouteMissing { return .app }
        // [v25.554] v25.552 以前從 Apple 健康帶進來的（那時沒記來源）：有編號、有路線、沒有真正結束時間——
        // App 記、有路線的一定有 endedAt（v25.551 起），所以這種只可能是手錶的（舊紀錄找回路線、合成要認得它）
        if s.healthKitUUID != nil, s.firstRouteExercise != nil { return .watch }
        return nil
    }

    /// 這個動作的爬升（公尺）；不知道回 nil（畫面不顯示、不加總、不進紀錄）。
    /// 知道的只有 App 記、有路線的（v25.551 起氣壓計／GPS 去雜訊）；舊版只存到起點的是灌水的，
    /// 手動補記沒填，都當不知道。
    /// [v25.554] 先看 health.climbKnown：手錶帶進來的（Apple 健康的 HKMetadataKeyElevationAscended，0＝平路）、
    /// 跟手錶合成過的舊紀錄（灌水的爬升換成手錶的；手錶沒量就 false＝不知道）照它；nil 才照上面的舊規則
    static func climb(_ e: WorkoutExercise, in s: WorkoutSession) -> Double? {
        guard e.kind == .cardio else { return nil }
        if let known = s.health?.climbKnown {
            return known ? max(0, e.elevationGainM) : nil
        }
        guard e.hasRoute else { return nil }
        guard source(of: s) == .app else { return nil }
        return max(0, e.elevationGainM)
    }

    // MARK: 這一週（v3 看板用；v2 先建好）

    /// 這一週裡、某種運動的公里數（一趟裡只加那種運動的動作；跑、走、騎各算各的不相加）
    static func weekDistanceKm(_ sessions: [WorkoutSession], sport: WorkoutSport, weekOf date: Date) -> Double {
        let w = week(of: date)
        var km = 0.0
        for s in sessions where s.date >= w.start && s.date < w.end {
            for e in s.exercises where e.kind == .cardio && e.resolvedSport == sport {
                km += max(0, e.distanceKm)
            }
        }
        return km
    }

    /// 這一週裡、含這種運動的趟數
    static func weekCount(_ sessions: [WorkoutSession], sport: WorkoutSport, weekOf date: Date) -> Int {
        let w = week(of: date)
        return sessions.filter { s in
            s.date >= w.start && s.date < w.end && s.exercises.contains { $0.resolvedSport == sport }
        }.count
    }

    /// 連續幾週有運動：從這週往回數；這週還沒動就從上週數（待決定 3）。
    /// [v25.557] leave：請假的那幾週（週一 00:00；WorkoutFacts.leaveWeeks(LifeStore.workoutLeave)）：沒運動但請假的週不加、不斷（streak）
    static func streakWeeks(_ sessions: [WorkoutSession], leave: Set<Date> = [], now: Date = Date()) -> Int {
        streak(sessions, leave: leave, now: now).weeks
    }

    /// [v25.557] 連續週數的細節（看板膠囊、這趟的收穫、月曆下面那一行）。build/v7/sim_v7.py streak：
    /// 從這週往回數；那週有任何一趟運動 +1；沒運動但請假：跳過（不加、不斷）；都沒有：停。
    /// 這週還沒動、也沒請假就從上週數（待決定 3）。since＝數到的最早那一週有運動的週一；leaveWeeks＝中間跳過幾個請假週
    static func streak(_ sessions: [WorkoutSession], leave: Set<Date> = [], now: Date = Date()) -> WorkoutStreak {
        var weeks = Set<Date>()
        for s in sessions where counts(s) {
            weeks.insert(weekStart(of: s.date))
        }
        var cursor = weekStart(of: now)
        if !weeks.contains(cursor) && !leave.contains(cursor) {
            guard let prev = calendar.date(byAdding: .day, value: -7, to: cursor) else { return WorkoutStreak() }
            cursor = prev
        }
        var out = WorkoutStreak()
        var pending = 0
        for _ in 0..<600 {
            if weeks.contains(cursor) {
                // [v25.557 裁定] 只算「中間」的請假週：最近那一頭的（這週請假還沒動）不算，不然月曆下面會寫「中間請假 1 週」
                if out.weeks > 0 { out.leaveWeeks += pending }
                out.weeks += 1
                out.since = cursor
                pending = 0
            } else if leave.contains(cursor) {
                pending += 1
            } else {
                break
            }
            guard let prev = calendar.date(byAdding: .day, value: -7, to: cursor) else { break }
            cursor = prev
        }
        return out
    }

    // MARK: 大卡（judge §3.13 的 MET 表）

    /// 跑步：時速（公里）→ MET，表內線性內插、表外夾在頭尾
    static let runMET: [(kmh: Double, met: Double)] = [
        (8.0, 8.3), (8.4, 9.0), (9.7, 9.8), (10.8, 10.5), (11.3, 11.0), (12.1, 11.8)
    ]
    /// 健走：時速（公里）→ MET
    static let walkMET: [(kmh: Double, met: Double)] = [
        (4.0, 3.0), (4.8, 3.5), (5.6, 4.3), (6.4, 5.0)
    ]

    /// 依時速在表裡線性內插；表外夾在頭尾
    static func interpolate(_ x: Double, _ table: [(kmh: Double, met: Double)]) -> Double {
        guard let first = table.first, let last = table.last else { return 0 }
        if x <= first.kmh { return first.met }
        if x >= last.kmh { return last.met }
        for i in 1..<table.count {
            let a = table[i - 1]
            let b = table[i]
            if x <= b.kmh {
                let k = (x - a.kmh) / (b.kmh - a.kmh)
                return a.met + (b.met - a.met) * k
            }
        }
        return last.met
    }

    /// 這種運動、這個時速的 MET。時速不知道（沒填距離）用中間值：跑步 9.7、健走 4.8 公里/時、騎車 6.8
    static func met(sport: WorkoutSport, speedKmh: Double?) -> Double {
        switch sport {
        case .run:
            return interpolate(speedKmh ?? 9.7, runMET)
        case .walk:
            return interpolate(speedKmh ?? 4.8, walkMET)
        case .bike:
            guard let v = speedKmh else { return 6.8 }
            if v < 16 { return 4.0 }
            if v < 19 { return 6.8 }
            if v < 22.5 { return 8.0 }
            return 10.0
        case .hike:
            return 6.0
        case .strength:
            return 5.0
        case .other:
            return 5.0
        }
    }

    /// 估這一趟的大卡：每個有氧動作（MET − 1）× 體重 × 小時；剩下沒算到的時間（重訓、有氧沒填時間）用這一趟的主運動。
    /// 沒有體重、或一分鐘都沒有回 nil（不亂猜）。
    /// 例：72.4 公斤、跑步 5.2 公里 32:10（9.7 公里/時，MET 9.8）→ 341.6 → 畫面「約 340 大卡」；
    ///     健走 60 分鐘沒填距離（MET 3.5）→ 181 →「約 180 大卡」（以前一律 8 MET＝576）
    static func estimatedKcal(_ s: WorkoutSession, bodyWeightKg: Double?) -> Double? {
        guard let w = bodyWeightKg, w > 0 else { return nil }
        var total = 0.0
        var counted = 0.0
        for e in s.cardioExercises where e.durationMinutes > 0 {
            let speed = WorkoutFormat.speedKmh(km: e.distanceKm, minutes: e.durationMinutes)
            total += (met(sport: e.resolvedSport, speedKmh: speed) - 1) * w * (e.durationMinutes / 60)
            counted += e.durationMinutes
        }
        let rest = movingMinutes(s) - counted
        if rest > 0.5 {
            let sport: WorkoutSport = s.strengthExercises.isEmpty ? s.primarySport : .strength
            total += (met(sport: sport, speedKmh: nil) - 1) * w * (rest / 60)
        }
        guard total.isFinite, total > 0 else { return nil }
        return total
    }

    /// 畫面用的大卡：有存（手錶量的、或存檔時估好的）用存的；沒有就當場估（estimated = true）；都沒有回 nil
    static func kcal(_ s: WorkoutSession, bodyWeightKg: Double?) -> (kcal: Double, estimated: Bool)? {
        if s.activeEnergyKcal > 0 { return (s.activeEnergyKcal, s.kcalEstimated == true) }
        guard let e = estimatedKcal(s, bodyWeightKg: bodyWeightKg) else { return nil }
        return (e, true)
    }

    /// 存檔前呼叫（跑完、救回、表單存檔）：沒有量到的大卡用 MET 表估好存回去、記 kcalEstimated；
    /// 之前估的照新的距離時間重估；手錶量的（kcalEstimated 不是 true 而且 > 0）不動
    static func applyKcalEstimate(_ s: inout WorkoutSession, bodyWeightKg: Double?) {
        guard s.activeEnergyKcal <= 0 || s.kcalEstimated == true else { return }
        if let e = estimatedKcal(s, bodyWeightKg: bodyWeightKg) {
            s.activeEnergyKcal = (e * 10).rounded() / 10
            s.kcalEstimated = true
        } else {
            s.activeEnergyKcal = 0
            s.kcalEstimated = nil
        }
    }

    // MARK: 存檔（App 記的一趟）

    /// [v25.552] App 記的一趟 → 存檔用的 WorkoutSession。RunTrackingView 按完成、RunRecoveryCenter 救回中途存檔都走這裡：
    /// 1. 先用完整的點算每公里分段（RouteMath.kmSplits：跳過暫停空隙、用移動時間），每公里爬升用記錄器記的 kmClimb；
    /// 2. 再把路線簡化（RouteMath.simplified：誤差 1.5 公尺內、至少每 10 秒留一點）；
    /// 3. 運動種類、來源 .app、暫停、真正結束時間、估的大卡一起填好。
    /// [v25.555] 名稱存檔時就取好（autoTitle：起點 150 公尺內有你改過名字的同一種運動就沿用那個名字，不然照時段「晨跑」「夜跑」）；
    /// sessions 傳 store 裡全部的運動（沒傳＝只照時段）。動作的名稱還是運動名（「跑步」：舊版 iPad 看名字猜運動種類）。
    /// 記錄時 GPS 好不好（RunResult.gps）一起存（成果頁「要確認」那一句）。
    static func makeSession(from r: RunResult, bodyWeightKg: Double?,
                            sessions: [WorkoutSession] = []) -> WorkoutSession {
        let splits = splitsWithClimb(RouteMath.kmSplits(r.route), kmClimb: r.kmClimb, totalClimb: r.elevation)
        let sport = WorkoutSport(r.sport)
        let title = autoTitle(sport: sport, start: r.startedAt, startPoint: r.route.first, sessions: sessions)
        // [v25.557] 最快 1／5／10 公里、半馬：跟分段一樣在簡化之前用完整的點算（只有跑步；沒有夠長的那幾段就不存）
        let efforts = sport == .run ? bestEfforts(r.route) : []
        let exercise = WorkoutExercise(
            name: r.sport.rawValue, kind: .cardio, reps: 0, sets: 0, loadType: .none,
            loadKg: 0, distanceKm: r.distanceKm, durationMinutes: r.movingMinutes,
            route: RouteMath.simplified(r.route), elevationGainM: r.elevation,
            sport: WorkoutSport(r.sport), splits: splits.isEmpty ? nil : splits,
            efforts: efforts.isEmpty ? nil : efforts)
        var session = WorkoutSession(
            date: r.startedAt,                 // 按開始那一刻
            title: title,                      // [v25.555] 「晨跑」「河濱晨跑」（以前存「跑步」，畫面上才換成時段名）
            exercises: [exercise],
            durationMinutes: r.movingMinutes,  // 扣掉暫停的移動時間
            endedAt: r.endedAt,                // 最後一次按暫停那一刻
            source: .app,
            pauses: r.pauses.isEmpty ? nil : r.pauses,
            gps: r.gps)
        applyKcalEstimate(&session, bodyWeightKg: bodyWeightKg)
        // [v25.557] 這一趟的亮點（破了哪幾個個人紀錄、同一條路第幾次、比上次快多少）：跟 store 裡比它早的每一趟比一次存起來，之後打開不重算
        session.highlights = highlights(for: session, among: sessions)
        // [v25.554] 寫進 Apple 健康用簡化前的點（judge §6 v4）：完整的點只放記憶體一下，寫的時候拿走（WorkoutRouteStash）
        WorkoutRouteStash.keep(r.route, for: session.id)
        return session
    }

    /// 每公里爬升：kmClimb[i]＝記錄器走到第 i+1 公里那一刻的累計爬升。
    /// 整公里用相鄰兩個的差；第一個對不到 kmClimb 的（最後不滿一公里那段）用總爬升減前一個；再後面的不知道（nil）。
    /// kmClimb 是空的、分段卻不只一段（不該發生）就全部不填。
    static func splitsWithClimb(_ splits: [WorkoutSplit], kmClimb: [Double], totalClimb: Double) -> [WorkoutSplit] {
        guard !splits.isEmpty else { return [] }
        if kmClimb.isEmpty && splits.count > 1 { return splits }
        var out = splits
        var prev = 0.0
        var tailDone = false
        for i in out.indices {
            if i < kmClimb.count {
                out[i].climbM = max(0, kmClimb[i] - prev)
                prev = kmClimb[i]
            } else if !tailDone {
                out[i].climbM = max(0, totalClimb - prev)
                tailDone = true
            }
        }
        return out
    }
}

// MARK: - 一趟的主運動

extension WorkoutSession {
    /// [v25.552] 這一趟算哪一種運動：第一個有氧動作的種類；沒有有氧、有重訓 → 重訓；什麼都沒有 → 其他有氧
    var primarySport: WorkoutSport {
        if let c = cardioExercises.first { return c.resolvedSport }
        if !strengthExercises.isEmpty { return .strength }
        return .other
    }
}

// MARK: - 字（全部純函式）

enum WorkoutFormat {

    /// 秒數取整數（四捨五入）；NaN、無限大、負的都當 0，超大夾住（Int(Double) 碰到這些會閃退）
    static func wholeSeconds(_ seconds: Double) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int(min(seconds, 360_000_000).rounded())
    }

    // MARK: 距離

    /// 「5.2」：清單、膠囊、看板（一位小數）
    static func kmNumber(_ km: Double) -> String {
        guard km.isFinite, km > 0 else { return "0.0" }
        return String(format: "%.1f", km)
    }

    /// 「5.2 公里」
    static func km(_ km: Double) -> String { kmNumber(km) + " 公里" }

    /// 「5.20」：成果頁、跑步中（兩位）；騎車 10 公里以上一位（「12.6」）
    static func preciseKmNumber(_ km: Double, sport: WorkoutSport? = nil) -> String {
        guard km.isFinite, km > 0 else { return "0.00" }
        if sport == .bike, km >= 10 { return String(format: "%.1f", km) }
        return String(format: "%.2f", km)
    }

    // MARK: 時間

    /// 「32:10」「1:05:12」（秒數四捨五入；不到一小時不補前面的 0）
    static func clock(seconds: Double) -> String {
        let s = wholeSeconds(seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    /// 分鐘（可以有小數）→「32:10」
    static func clock(minutes: Double) -> String { clock(seconds: minutes * 60) }

    /// 合計：「2 小時 10 分」「45 分鐘」
    static func total(minutes: Double) -> String {
        let m = wholeSeconds(minutes * 60 + 30) / 60    // 四捨五入到分鐘
        if m >= 60 { return "\(m / 60) 小時 \(m % 60) 分" }
        return "\(m) 分鐘"
    }

    // MARK: 配速、速度

    /// 配速「6'11"」：秒數四捨五入（6'09.9" 寫 6'10"）；算不出來或超過 60 分/公里寫「—」
    static func pace(_ minPerKm: Double?) -> String {
        guard let p = minPerKm, p.isFinite, p > 0, p < 60 else { return "—" }
        let total = Int((p * 60).rounded())
        return String(format: "%d'%02d\"", total / 60, total % 60)
    }

    /// 距離、分鐘 → 配速字；距離或時間是 0 寫「—」
    static func pace(km: Double, minutes: Double) -> String {
        guard km > 0, minutes > 0 else { return "—" }
        return pace(minutes / km)
    }

    /// 時速（公里）；距離或時間是 0 回 nil
    static func speedKmh(km: Double, minutes: Double) -> Double? {
        guard km > 0, minutes > 0, km.isFinite, minutes.isFinite else { return nil }
        return km / (minutes / 60)
    }

    /// 「21.5」
    static func speedNumber(_ kmh: Double) -> String {
        guard kmh.isFinite, kmh > 0 else { return "0.0" }
        return String(format: "%.1f", kmh)
    }

    /// 「21.5 公里/時」（騎車不寫配速）
    static func speed(_ kmh: Double) -> String { speedNumber(kmh) + " 公里/時" }

    // MARK: 爬升、大卡

    /// 爬升：不到 10 公尺寫「平路」；其他「18 m」
    static func climb(_ meters: Double) -> String {
        guard meters.isFinite, meters >= 10 else { return "平路" }
        return "\(wholeSeconds(meters)) m"
    }

    /// 大卡：量的「402 大卡」；估的「約 340 大卡」（估的取到十位）
    static func kcal(_ kcal: Double, estimated: Bool) -> String {
        if estimated {
            let tens = wholeSeconds(kcal / 10)
            return "約 \(tens * 10) 大卡"
        }
        return "\(wholeSeconds(kcal)) 大卡"
    }

    // MARK: 日期（固定西曆＋zh_TW，手機設民國曆也一樣）

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = format
        return f
    }

    private static let dayFormatter = formatter("M/d EEE")
    private static let dateFormatter = formatter("yyyy/M/d")
    private static let timeFormatter = formatter("HH:mm")
    private static let monthDayFormatter = formatter("M/d")

    /// 「10/15 週四」
    static func day(_ date: Date) -> String { dayFormatter.string(from: date) }
    /// 「2026/10/15」
    static func date(_ date: Date) -> String { dateFormatter.string(from: date) }
    /// 「06:05」
    static func time(_ date: Date) -> String { timeFormatter.string(from: date) }
    /// 「10/15」
    static func monthDay(_ date: Date) -> String { monthDayFormatter.string(from: date) }

    // MARK: 表單的時間欄

    /// 表單裡打的時間：「35」＝35 分（可以有小數）；「35:20」＝35 分 20 秒；「1:05:12」＝1 小時 5 分 12 秒。
    /// 全形冒號也認。空白回 0；看不懂（秒數 60 以上、不是數字、負的）回 nil
    static func parseMinutes(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "：", with: ":")
        if t.isEmpty { return 0 }
        let parts = t.split(separator: ":", omittingEmptySubsequences: false).map { String($0) }
        guard parts.count >= 1, parts.count <= 3 else { return nil }
        var nums: [Double] = []
        for p in parts {
            guard let v = Double(p), v.isFinite, v >= 0 else { return nil }
            nums.append(v)
        }
        let minutes: Double
        switch nums.count {
        case 1:
            minutes = nums[0]
        case 2:
            guard nums[1] < 60 else { return nil }
            minutes = nums[0] + nums[1] / 60
        default:
            guard nums[1] < 60, nums[2] < 60 else { return nil }
            minutes = nums[0] * 60 + nums[1] + nums[2] / 60
        }
        // 小時打到三百多位數，乘 60 會變無限大：存進去 JSON 寫不出來（整份訓練紀錄存不了），當成看不懂
        guard minutes.isFinite else { return nil }
        return minutes
    }

    /// 反過來：表單一打開顯示的字。整分鐘「45」；有秒「32:10」（分鐘可以超過 60：「65:12」）；0 是空白
    static func minutesInput(_ minutes: Double) -> String {
        let s = wholeSeconds(minutes * 60)
        guard s > 0 else { return "" }
        if s % 60 == 0 { return "\(s / 60)" }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - 路線：存檔前簡化、每公里分段（v25.552）

extension RouteMath {

    /// [v25.552] 存檔前把路線變小：暫停切開的每一段各自用「拉直線」（Douglas–Peucker）簡化，
    /// 離直線不到 tolerance 公尺的中間點拿掉；再補回「離上一個留下的點 maxGap 秒以上就留」。
    /// 每段頭尾一定留。河濱 5.2 公里：889 → 約 228 點（health/build/v2/sim_v2.py）。
    /// 每公里分段要在簡化**之前**算（kmSplits）；畫面上的即時線不用這個。
    static func simplified(_ route: [RoutePoint], tolerance: Double = 1.5, maxGap: Double = 10) -> [RoutePoint] {
        guard route.count > 2 else { return route }
        var out: [RoutePoint] = []
        out.reserveCapacity(route.count / 3 + 2)
        var start = 0
        while start < route.count {
            let s = route[start].seg ?? 0
            var end = start
            while end + 1 < route.count, (route[end + 1].seg ?? 0) == s {
                end += 1
            }
            out.append(contentsOf: simplifiedRun(route, from: start, to: end, tolerance: tolerance, maxGap: maxGap))
            start = end + 1
        }
        return out
    }

    /// 一段（同一個 seg）的簡化；from、to 是 route 的索引（含）
    private static func simplifiedRun(_ r: [RoutePoint], from a: Int, to b: Int,
                                      tolerance: Double, maxGap: Double) -> [RoutePoint] {
        let n = b - a + 1
        if n <= 2 { return Array(r[a...b]) }
        // 平面近似（公尺）：這一段第一點當原點（跟 sim_v2.py 一樣用 111,320 公尺／度）
        let kx = 111_320.0 * cos(r[a].lat * .pi / 180)
        let ky = 111_320.0
        var xs = [Double](repeating: 0, count: n)
        var ys = [Double](repeating: 0, count: n)
        for i in 0..<n {
            xs[i] = (r[a + i].lon - r[a].lon) * kx
            ys[i] = (r[a + i].lat - r[a].lat) * ky
        }
        var keep = [Bool](repeating: false, count: n)
        keep[0] = true
        keep[n - 1] = true
        var stack: [(Int, Int)] = [(0, n - 1)]
        while let pair = stack.popLast() {
            let i = pair.0
            let j = pair.1
            if j - i < 2 { continue }
            let dx = xs[j] - xs[i]
            let dy = ys[j] - ys[i]
            let len = max((dx * dx + dy * dy).squareRoot(), 1e-9)
            var best = -1.0
            var idx = -1
            for k in (i + 1)..<j {
                let d = abs(dy * (xs[k] - xs[i]) - dx * (ys[k] - ys[i])) / len
                if d > best {
                    best = d
                    idx = k
                }
            }
            if best > tolerance, idx > 0 {
                keep[idx] = true
                stack.append((i, idx))
                stack.append((idx, j))
            }
        }
        // 至少每 maxGap 秒留一點（每公里分段、v4 寫 Apple 健康、v5 這一公里配速都靠點上的時間）
        var out: [RoutePoint] = []
        var lastT = -Double.greatestFiniteMagnitude
        for i in 0..<n {
            let p = r[a + i]
            if keep[i] || p.t - lastT >= maxGap {
                out.append(p)
                lastT = p.t
            }
        }
        return out
    }

    /// [v25.552] 每公里分段（在簡化**之前**算）：只加同一段裡相鄰兩點的距離（暫停的空隙不算距離、也不算時間），
    /// 時間＝那兩點的時間差（移動時間）；跨過整公里的那一步照距離比例切開。
    /// 最後不滿一公里的那段 50 公尺以上才給（例：5.2 公里 → 5 段 1,000 m＋1 段約 200 m）。
    static func kmSplits(_ route: [RoutePoint]) -> [WorkoutSplit] {
        guard route.count >= 2 else { return [] }
        var out: [WorkoutSplit] = []
        var meters = 0.0
        var seconds = 0.0
        for i in 1..<route.count {
            let p = route[i - 1]
            let q = route[i]
            guard (p.seg ?? 0) == (q.seg ?? 0) else { continue }
            var d = CLLocation(latitude: p.lat, longitude: p.lon)
                .distance(from: CLLocation(latitude: q.lat, longitude: q.lon))
            var dt = max(0, q.t - p.t)
            while d > 0, meters + d >= 1000 {
                let need = 1000 - meters
                let k = need / d
                out.append(WorkoutSplit(meters: 1000, seconds: seconds + dt * k, climbM: nil))
                d -= need
                dt -= dt * k
                meters = 0
                seconds = 0
            }
            meters += d
            seconds += dt
        }
        if meters >= 50 {
            out.append(WorkoutSplit(meters: meters, seconds: seconds, climbM: nil))
        }
        return out
    }
}

// MARK: - v3：名字（時段取名、卡面手寫小字）

extension WorkoutFacts {

    /// 一天的時段：05:00–09:59 早上、10:00–13:59 中午、14:00–17:59 下午、18:00–23:59 晚上、00:00–04:59 深夜
    enum DayPart {
        case morning, noon, afternoon, evening, night
    }

    static func dayPart(_ date: Date) -> DayPart {
        let h = calendar.component(.hour, from: date)
        if h >= 5 && h < 10 { return .morning }
        if h >= 10 && h < 14 { return .noon }
        if h >= 14 && h < 18 { return .afternoon }
        if h >= 18 { return .evening }
        return .night
    }

    /// 照時段取的名字（judge §4.3）：跑步 晨跑／午跑／午後跑步／夜跑／深夜跑步；健走 晨走／午間健走／午後健走／晚走／深夜健走；
    /// 騎車 晨騎／午騎／午後騎車／夜騎／深夜騎車；登山一律「登山」；重訓、其他有氧就是運動名
    static func timeOfDayName(_ sport: WorkoutSport, start: Date) -> String {
        let p = dayPart(start)
        switch sport {
        case .run:
            switch p {
            case .morning: return "晨跑"
            case .noon: return "午跑"
            case .afternoon: return "午後跑步"
            case .evening: return "夜跑"
            case .night: return "深夜跑步"
            }
        case .walk:
            switch p {
            case .morning: return "晨走"
            case .noon: return "午間健走"
            case .afternoon: return "午後健走"
            case .evening: return "晚走"
            case .night: return "深夜健走"
            }
        case .bike:
            switch p {
            case .morning: return "晨騎"
            case .noon: return "午騎"
            case .afternoon: return "午後騎車"
            case .evening: return "夜騎"
            case .night: return "深夜騎車"
            }
        case .hike:
            return "登山"
        case .strength, .other:
            return sport.displayName
        }
    }

    /// 只是運動名、不是自己取的名字（App 記的存「跑步」、手錶帶進來的「跑步」「走路」「健行」、補記沒填的運動名）
    static let genericTitles: Set<String> = ["", "跑步", "健走", "騎車", "登山", "走路", "健行", "散步", "單車", "自行車"]

    /// [v25.553] 畫面上一趟的名字（項目卡、成果頁、刪除確認、清單、記錄中條都用這一支）：
    /// 自己取的名字照用（「河濱晨跑」「胸推日」）；名字只是跑、走、騎、登山的運動名（或空白）就照時段取名（「晨跑」「晚走」）；
    /// 其他照 displayTitle（重訓沒名字寫第一個動作「臥推 等 3 項」）。資料不改，只改畫面上的字。
    static func title(_ s: WorkoutSession) -> String {
        let t = s.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let sport = s.primarySport
        let named = [WorkoutSport.run, .walk, .bike, .hike].contains(sport)
        if named, genericTitles.contains(t) {
            return timeOfDayName(sport, start: s.date)
        }
        if t.isEmpty { return s.displayTitle }
        return t
    }

    /// [v25.553] 卡面左下手寫字下面那行小字：MORNING／NOON／AFTERNOON／EVENING／NIGHT；週六、週日騎車寫 WEEKEND
    static func scriptCaps(_ s: WorkoutSession) -> String {
        if s.primarySport == .bike {
            let wd = calendar.component(.weekday, from: s.date)      // 週日 1、週六 7
            if wd == 1 || wd == 7 { return "WEEKEND" }
        }
        switch dayPart(s.date) {
        case .morning: return "MORNING"
        case .noon: return "NOON"
        case .afternoon: return "AFTERNOON"
        case .evening: return "EVENING"
        case .night: return "NIGHT"
        }
    }

    /// 看板、目標、開始列的動詞：跑步「跑」、健走「走」、騎車「騎」、登山「爬」、重訓「練」、其他「動」
    /// （「這週跑了」「再騎 5.4 公里」「達標！多走了 0.6 公里」）
    static func verb(_ sport: WorkoutSport) -> String {
        switch sport {
        case .run: return "跑"
        case .walk: return "走"
        case .bike: return "騎"
        case .hike: return "爬"
        case .strength: return "練"
        case .other: return "動"
        }
    }
}

// MARK: - v3：看板主角、上週同期、每週目標

/// [v25.557] 連續週數（WorkoutFacts.streak）
struct WorkoutStreak: Equatable {
    /// 連續幾週（請假週不算進去）
    var weeks = 0
    /// 數到的最早那一週有運動的週一（「9/7 那週起」）；0 週是 nil
    var since: Date? = nil
    /// 中間跳過幾個請假週（「中間請假 1 週」）
    var leaveWeeks = 0
}

/// [v25.553] 這一週某種運動的進度（看板下的目標格、開始列那一句、成果頁「這趟的收穫」共用）
struct WorkoutWeekProgress: Equatable {
    var sport: WorkoutSport
    /// 這週到現在的公里
    var doneKm: Double
    /// 每週目標；nil＝沒設
    var goalKm: Double?
    /// 這週還剩幾天（含今天）：週四是 4、週日是 1
    var daysLeft: Int

    /// 還差幾公里（沒設目標是 0）
    var remainingKm: Double { max(0, (goalKm ?? 0) - doneKm) }
    /// 達標（差不到 0.05 公里也算：畫面一位小數已經寫成一樣了）
    var reached: Bool {
        guard let g = goalKm else { return false }
        return doneKm >= g - 0.05
    }
    /// 進度（可以超過 1）；沒設目標是 0
    var fraction: Double {
        guard let g = goalKm, g > 0 else { return 0 }
        return doneKm / g
    }
}

extension WorkoutFacts {

    /// 某段時間［from, to）裡、某種運動的公里（一趟裡只加那種運動的動作）
    static func distanceKm(_ sessions: [WorkoutSession], sport: WorkoutSport, from: Date, to: Date) -> Double {
        var km = 0.0
        for s in sessions where s.date >= from && s.date < to {
            for e in s.exercises where e.kind == .cardio && e.resolvedSport == sport {
                km += max(0, e.distanceKm)
            }
        }
        return km
    }

    /// 看板主角：設定的那一種；自動＝近 28 天次數最多的有氧（跑、走、騎、登山），平手照跑步、健走、騎車、登山的順序；
    /// 近 28 天都沒有有氧＝跑步
    static func heroSport(_ prefs: WorkoutPrefs, sessions: [WorkoutSession], now: Date = Date()) -> WorkoutSport {
        if let fixed = prefs.heroChoice.sport { return fixed }
        let from = now.addingTimeInterval(-28 * 86_400)
        var counts: [WorkoutSport: Int] = [:]
        for s in sessions where s.date >= from && s.date <= now {
            let kinds = Set(s.cardioExercises.map(\.resolvedSport))
            for k in kinds where k != .other {
                counts[k, default: 0] += 1
            }
        }
        var best = WorkoutSport.run
        var bestN = 0
        for k in [WorkoutSport.run, .walk, .bike, .hike] {
            let n = counts[k] ?? 0
            if n > bestN {
                best = k
                bestN = n
            }
        }
        return best
    }

    /// 這週星期幾的索引：週一 0 … 週日 6
    static func weekdayIndex(_ date: Date) -> Int {
        let wd = calendar.component(.weekday, from: date)     // 週日 1、週一 2 … 週六 7
        return (wd + 5) % 7
    }

    /// 上週同期：上週一 00:00 到「現在減 7 天」（不含）。例：10/15 07:12 → 10/5 00:00～10/8 07:12
    static func lastWeekSamePeriodKm(_ sessions: [WorkoutSession], sport: WorkoutSport, now: Date = Date()) -> Double {
        let thisStart = weekStart(of: now)
        guard let lastStart = calendar.date(byAdding: .day, value: -7, to: thisStart),
              let cut = calendar.date(byAdding: .day, value: -7, to: now) else { return 0 }
        return distanceKm(sessions, sport: sport, from: lastStart, to: cut)
    }

    /// 上週整週（週一到週日）的公里
    static func lastWeekKm(_ sessions: [WorkoutSession], sport: WorkoutSport, now: Date = Date()) -> Double {
        let thisStart = weekStart(of: now)
        guard let lastStart = calendar.date(byAdding: .day, value: -7, to: thisStart) else { return 0 }
        return distanceKm(sessions, sport: sport, from: lastStart, to: thisStart)
    }

    /// 這週某種運動的目標進度（目標讀 prefs）
    static func weekProgress(_ sessions: [WorkoutSession], prefs: WorkoutPrefs, sport: WorkoutSport,
                             now: Date = Date()) -> WorkoutWeekProgress {
        WorkoutWeekProgress(sport: sport,
                            doneKm: weekDistanceKm(sessions, sport: sport, weekOf: now),
                            goalKm: prefs.goalKm(for: sport),
                            daysLeft: 7 - weekdayIndex(now))
    }

    /// 每週目標的建議：近 4 個完整週（不含這週）平均 × 1.1，往上取到 5 的倍數，夾在 5～100；
    /// 近 4 週都沒有就用預設（騎車 30、其他 10）。例：15.2、16.8、14.0、13.3 → 平均 14.8 × 1.1＝16.3 → 20
    static func suggestedGoal(_ sessions: [WorkoutSession], sport: WorkoutSport,
                              now: Date = Date()) -> (km: Double, average: Double) {
        let thisStart = weekStart(of: now)
        guard let from = calendar.date(byAdding: .day, value: -28, to: thisStart) else {
            return (sport == .bike ? 30 : 10, 0)
        }
        let avg = distanceKm(sessions, sport: sport, from: from, to: thisStart) / 4
        guard avg >= 0.05 else { return (sport == .bike ? 30 : 10, 0) }
        let up = (avg * 1.1 / 5).rounded(.up) * 5
        return (min(max(up, 5), 100), avg)
    }
}

// MARK: - v3：每公里分段能不能用、高度

/// [v25.553] 一趟的高度（成果頁「高度」、成果看板的地面）。
/// 形狀用 GPS 高度（RoutePoint.alt）沿距離平滑（前後 50 公尺平均）。App 記的那一趟「爬升」用存下來的（氣壓計／GPS 去雜訊）：
/// • 下降：GPS 照 4 公尺門檻累加，再乘「存下來的爬升 ÷ GPS 算的爬升」（累加的東西 GPS 雜訊會灌水，一起縮）；
/// • 高低差、最高比起點高、高度圖：GPS 的高低差超過存下來的爬升就整條等比例壓到爬升那麼高（高低差不可能比總爬升大；
///   平路氣壓計 0 m → 整條壓平），不然照 GPS（平滑後的高低差不太灌水）。
/// 模擬（build/v3/sim_v3.py）：河濱 5.2 公里（真的最高比起點高 9 m、氣壓計 18 m）30/30 次畫平的河濱；25 m 的坡 30/30 次畫山稜
struct WorkoutElevation: Equatable {
    struct Sample: Equatable {
        /// 從起點走了幾公里（暫停的空隙不算）
        var km: Double
        /// 比起點高幾公尺（可以是負的）
        var meters: Double
    }
    /// 爬升（公尺）；不知道（手錶帶進來、舊版、手動）是 nil——成果頁不出現「高度」那一區
    var gainM: Double?
    /// 下降（公尺）
    var lossM: Double
    /// 最高比起點高幾公尺（不會是負的）
    var maxAboveStartM: Double
    /// 高度對距離，最多 120 點
    var samples: [Sample]
    /// 最高減最低 20 公尺以上：成果看板把路畫在山稜上；不然畫平的河濱（河濱 5.2 公里爬升 18 m 也算平的：上下河堤、過橋）
    var hilly: Bool
}

extension WorkoutFacts {

    /// 每公里分段還能不能用：分段加起來要跟這個動作現在的距離（差 60 公尺或 3% 內）、移動時間（差 60 秒或 5% 內）對得上。
    /// 編輯過距離或時間（例：5.20 改成 5.0）就對不上 → nil：成果頁不顯示每公里、最快一公里，側面的路也不畫快慢。
    /// （分段是記錄當時用 GPS 點算的，改了距離不重算：沒辦法知道改掉的那 200 公尺在哪一段）
    static func validSplits(_ e: WorkoutExercise) -> [WorkoutSplit]? {
        guard let sp = e.splits, !sp.isEmpty else { return nil }
        let meters = sp.reduce(0) { $0 + $1.meters }
        let seconds = sp.reduce(0) { $0 + $1.seconds }
        let wantM = e.distanceKm * 1000
        let wantS = e.durationMinutes * 60
        guard meters.isFinite, seconds.isFinite, wantM > 0, wantS > 0 else { return nil }
        guard abs(meters - wantM) <= max(60, wantM * 0.03) else { return nil }
        guard abs(seconds - wantS) <= max(60, wantS * 0.05) else { return nil }
        return sp
    }

    /// 一個動作的高度；路線不到 2 點、或整條都沒有高度（全是 0）回 nil
    static func elevation(_ e: WorkoutExercise, in s: WorkoutSession) -> WorkoutElevation? {
        let r = e.route
        guard r.count >= 2, r.contains(where: { $0.alt != 0 }) else { return nil }
        // 1. 沿路的距離（暫停的空隙不算）
        var cum = [Double](repeating: 0, count: r.count)
        for i in 1..<r.count {
            let p = r[i - 1]
            let q = r[i]
            var d = 0.0
            if (p.seg ?? 0) == (q.seg ?? 0) {
                d = CLLocation(latitude: p.lat, longitude: p.lon)
                    .distance(from: CLLocation(latitude: q.lat, longitude: q.lon))
                if !d.isFinite { d = 0 }
            }
            cum[i] = cum[i - 1] + d
        }
        // 2. 前後 50 公尺平均（兩個指標往前走，O(n)）
        var smooth = [Double](repeating: 0, count: r.count)
        var lo = 0
        var hi = 0
        var sum = 0.0
        for i in 0..<r.count {
            while hi < r.count && cum[hi] <= cum[i] + 50 {
                sum += r[hi].alt
                hi += 1
            }
            while lo < i && cum[lo] < cum[i] - 50 {
                sum -= r[lo].alt
                lo += 1
            }
            smooth[i] = sum / Double(max(1, hi - lo))
        }
        // 3. 4 公尺門檻算 GPS 的爬升、下降
        var gpsGain = 0.0
        var gpsLoss = 0.0
        var anchor = smooth[0]
        for v in smooth {
            if v - anchor >= 4 {
                gpsGain += v - anchor
                anchor = v
            } else if anchor - v >= 4 {
                gpsLoss += anchor - v
                anchor = v
            }
        }
        // 4. App 記的：存下來的爬升比較準。下降照「爬升的比例」縮（GPS 爬升不到 1 公尺就不縮）；
        //    高低差超過存下來的爬升就整條壓到爬升那麼高（c）
        let known = climb(e, in: s)
        var k = 1.0
        if let known, gpsGain >= 1 { k = max(0, known) / gpsGain }
        let start = smooth[0]
        let top = smooth.max() ?? start
        let bottom = smooth.min() ?? start
        let range = top - bottom
        var c = 1.0
        if let known, range > 0 { c = min(1, max(0, known) / range) }
        // 5. 最多 120 點（照距離等分取樣、線性內插）
        let total = cum[r.count - 1]
        var samples: [WorkoutElevation.Sample] = []
        if total > 0 {
            let n = 120
            var j = 0
            for step in 0..<n {
                let x = total * Double(step) / Double(n - 1)
                while j + 1 < r.count - 1 && cum[j + 1] < x { j += 1 }
                let x0 = cum[j]
                let x1 = cum[min(j + 1, r.count - 1)]
                let y0 = smooth[j]
                let y1 = smooth[min(j + 1, r.count - 1)]
                let t = x1 > x0 ? (x - x0) / (x1 - x0) : 0
                let y = y0 + (y1 - y0) * min(1, max(0, t))
                samples.append(WorkoutElevation.Sample(km: x / 1000, meters: (y - start) * c))
            }
        }
        return WorkoutElevation(gainM: known,
                                lossM: gpsLoss * k,
                                maxAboveStartM: max(0, (top - start) * c),
                                samples: samples,
                                hilly: range * c >= 20)
    }
}

// MARK: - v3：配速五級（成果頁地圖、每公里、側面的路）

/// [v25.553] 一段跟這一趟自己的平均比（不跟別趟比）：藍快、琥珀慢、灰差不多（不用紅綠：股票紅漲綠跌，綠和紅只給對你好、不好的事）
enum WorkoutPaceLevel: Int, CaseIterable {
    case muchFaster = 0
    case faster
    case even
    case slower
    case muchSlower

    /// 圖例上的字
    var label: String {
        switch self {
        case .muchFaster: return "快很多"
        case .faster: return "快"
        case .even: return "差不多"
        case .slower: return "慢"
        case .muchSlower: return "慢很多"
        }
    }

    /// 跑、走、登山：配速（秒/公里）跟平均差多少。快 20 秒以上＝快很多、快 7～20 秒＝快、前後 7 秒內＝差不多、
    /// 慢 7～20 秒＝慢、慢 20 秒以上＝慢很多。例：平均 6'11"，第 1 公里 6'02"（快 9 秒）＝快、第 4 公里 6'20"＝慢
    static func forPace(seconds s: Double, average a: Double) -> WorkoutPaceLevel {
        let d = s - a
        if d <= -20 { return .muchFaster }
        if d <= -7 { return .faster }
        if d < 7 { return .even }
        if d < 20 { return .slower }
        return .muchSlower
    }

    /// 騎車：時速（公里/時）跟平均差多少；前後 1.5、4 公里/時當級距
    static func forSpeed(kmh v: Double, average a: Double) -> WorkoutPaceLevel {
        let d = v - a
        if d >= 4 { return .muchFaster }
        if d >= 1.5 { return .faster }
        if d > -1.5 { return .even }
        if d > -4 { return .slower }
        return .muchSlower
    }
}

// MARK: - v3：顏色（judge §3.14，跟 MoneyArtTheme 61–66 同一組）

enum WorkoutPalette {
    /// 運動色：旗子、卡面的線、圖表的直條、圓點
    static func sport(_ s: WorkoutSport, dark: Bool) -> Color {
        switch s {
        case .run: return Color(tb: dark ? 0xD95926 : 0xEB6834)
        case .walk: return Color(tb: dark ? 0x199E70 : 0x1BAF7A)
        case .bike: return Color(tb: dark ? 0x3987E5 : 0x2A78D6)
        case .hike: return Color(tb: dark ? 0xC98500 : 0xEDA100)
        case .strength: return Color(tb: dark ? 0x9085E9 : 0x6250D6)
        case .other: return Color(tb: dark ? 0x9AA3B5 : 0x5B6478)
        }
    }

    /// 配速五級（淺色地圖／深色地圖）：快很多 1C5CAB／9EC5F4、快 6DA7EC／3987E5、差不多 A8A7A1／6B6A65、
    /// 慢 E39B1E／C98500、慢很多 9A6100／F5C56B
    static func pace(_ l: WorkoutPaceLevel, dark: Bool) -> Color {
        switch l {
        case .muchFaster: return Color(tb: dark ? 0x9EC5F4 : 0x1C5CAB)
        case .faster: return Color(tb: dark ? 0x3987E5 : 0x6DA7EC)
        case .even: return Color(tb: dark ? 0x6B6A65 : 0xA8A7A1)
        case .slower: return Color(tb: dark ? 0xC98500 : 0xE39B1E)
        case .muchSlower: return Color(tb: dark ? 0xF5C56B : 0x9A6100)
        }
    }

    /// 線外面那一圈邊（灰色那段才看得到）：淺色白、深色地圖深藍
    static func casing(dark: Bool) -> Color {
        dark ? Color(tb: 0x0B1B45) : Color.white
    }

    /// 開始鈕的綠（跟 FinanceAddButton、要確認的綠同一個 1F9D57；不再手寫 Color(0.20, 0.78, 0.45)）
    static let go = Color(tb: 0x1F9D57)

    /// [v25.557] 月曆格子的深淺（WorkoutFacts.heatLevel 0…4；一個藍色由淺到深＝動得越久，跟配速的「快」同一族藍、不用紅綠）
    static func heat(_ level: Int, dark: Bool) -> Color {
        switch level {
        case 1: return Color(tb: dark ? 0x1D3557 : 0xDCEBFB)
        case 2: return Color(tb: dark ? 0x24508A : 0xA9CDF5)
        case 3: return Color(tb: dark ? 0x2F6BBF : 0x6DA7EC)
        case 4: return Color(tb: dark ? 0x3987E5 : 0x2A78D6)
        default: return Color(tb: dark ? 0x1C2230 : 0xEEF1F6)
        }
    }

    /// [v25.557] 月曆格子上日期數字的顏色：第 4 階（最深）白字，其他照一般字色（深色模式一律淺色字）
    static func heatInk(_ level: Int, dark: Bool) -> Color {
        if dark { return Color(tb: 0xE8EEF8) }
        return level >= 4 ? Color.white : Color(tb: 0x1F2A3D)
    }
}

// MARK: - v3：卡面的路線形狀（不打任何地圖請求）

/// [v25.553] 一趟路線換成 0…1 的形狀（項目卡的卡面、緊湊模式的小方塊畫它）。
/// 投影：等距圓柱（經度 × cos 緯度），兩邊至少 200 公尺（操場一圈 400 公尺才看得出是橢圓、不縮成一團；
/// 旅行的 TripBoardCellInk.route 是 2 公里），長寬比夾在 1:4～4:1（太長的那一邊不動、短的那一邊放寬置中）
struct WorkoutRouteShape: Equatable {
    /// 0…1；x 往東、y 往南（畫面往下）
    var points: [CGPoint]
    /// 新的一段從第幾點開始（不含 0）：暫停斷開的地方不連線
    var breaks: [Int]
    /// 寬 ÷ 高（公尺），0.25～4：畫的時候照這個比例放進卡面
    var aspect: Double
}

extension WorkoutFacts {

    /// 一趟路線的形狀；不到 2 點（或座標壞掉）回 nil。最多約 maxPoints 點（每段第一點一定留，暫停多的話會多幾點）
    static func routeShape(_ route: [RoutePoint], maxPoints: Int = 120, minSpanMeters: Double = 200) -> WorkoutRouteShape? {
        let pts = route.filter { $0.lat.isFinite && $0.lon.isFinite && abs($0.lat) <= 90 && abs($0.lon) <= 180 }
        guard pts.count >= 2,
              let minLat = pts.map(\.lat).min(), let maxLat = pts.map(\.lat).max(),
              let minLon = pts.map(\.lon).min(), let maxLon = pts.map(\.lon).max() else { return nil }
        let mPerDeg = 111_320.0
        let kx = max(0.2, cos((minLat + maxLat) / 2 * Double.pi / 180))
        let spanX = (maxLon - minLon) * kx * mPerDeg
        let spanY = (maxLat - minLat) * mPerDeg
        var sx = max(spanX, minSpanMeters)
        var sy = max(spanY, minSpanMeters)
        if sx > sy * 4 { sy = sx / 4 }
        if sy > sx * 4 { sx = sy / 4 }
        let padX = (sx - spanX) / 2
        let padY = (sy - spanY) / 2
        // 1. 換成 0…1；同一段裡離上一個留下的點不到 1% 的不留（GPS 原地抖動）
        var kept: [(p: CGPoint, seg: Int)] = []
        kept.reserveCapacity(pts.count)
        for q in pts {
            let x = ((q.lon - minLon) * kx * mPerDeg + padX) / sx
            let y = ((maxLat - q.lat) * mPerDeg + padY) / sy
            let p = CGPoint(x: min(1, max(0, x)), y: min(1, max(0, y)))
            let seg = q.seg ?? 0
            if let l = kept.last, l.seg == seg, abs(l.p.x - p.x) < 0.01, abs(l.p.y - p.y) < 0.01 { continue }
            kept.append((p: p, seg: seg))
        }
        // 終點一定留（實心點畫在真的終點）
        if let last = pts.last {
            let x = ((last.lon - minLon) * kx * mPerDeg + padX) / sx
            let y = ((maxLat - last.lat) * mPerDeg + padY) / sy
            let p = CGPoint(x: min(1, max(0, x)), y: min(1, max(0, y)))
            if let l = kept.last, l.p != p { kept.append((p: p, seg: last.seg ?? 0)) }
        }
        guard kept.count >= 2 else { return nil }
        // 2. 太多點就等距抽樣（頭尾、每段第一點和前一段最後一點一定留）
        var chosen = Set<Int>()
        if kept.count > maxPoints {
            let step = Double(kept.count - 1) / Double(max(1, maxPoints - 1))
            for k in 0..<maxPoints {
                chosen.insert(min(kept.count - 1, Int((Double(k) * step).rounded())))
            }
            for i in 1..<kept.count where kept[i].seg != kept[i - 1].seg {
                chosen.insert(i)
                chosen.insert(i - 1)
            }
        } else {
            for i in 0..<kept.count { chosen.insert(i) }
        }
        var out: [CGPoint] = []
        var breaks: [Int] = []
        var prevSeg: Int? = nil
        for i in chosen.sorted() {
            let k = kept[i]
            if let ps = prevSeg, ps != k.seg { breaks.append(out.count) }
            out.append(k.p)
            prevSeg = k.seg
        }
        return WorkoutRouteShape(points: out, breaks: breaks, aspect: sx / sy)
    }
}

// MARK: - v3：成果看板「這一趟的路」（從側面看；畫法在 Life/HealthBoardScenes.swift）

extension WorkoutFacts {

    /// 一趟的側面風景資料：
    /// • 有路線：每整公里一根柱子（騎車每 5 公里），最快那一公里（騎車最快那 5 公里）的柱子頂上一顆星；
    ///   路面照每公里分段的快慢五級上色（跟這一趟的平均比）；地面是高度（hilly 才畫山稜）。
    ///   分段對不上（編輯過距離或時間）：沒有柱子、路面全灰。
    /// • 重訓：一個動作一片槓片（大小跟訓練量成正比，沒有負荷的用總下數；最多 8 片）。
    /// • 沒有路線（舊紀錄、手動補記、手錶沒路線）：平的河堤＋小牌「這趟沒有路線」。
    static func trailScene(_ s: WorkoutSession, bodyWeightKg: Double?) -> WorkoutTrailScene {
        var scene = WorkoutTrailScene()
        scene.sport = s.primarySport
        if s.primarySport == .strength {
            scene.kind = .strength
            let sizes = s.strengthExercises.prefix(8).map { e -> Double in
                if let v = e.volume(bodyWeightKg: bodyWeightKg), v > 0 { return v }
                return Double(e.totalReps)
            }
            let top = sizes.max() ?? 0
            scene.plates = sizes.map { top > 0 ? 0.35 + 0.65 * ($0 / top) : 0.6 }
            return scene
        }
        guard let e = s.firstRouteExercise else {
            scene.kind = .noRoute
            scene.note = "這趟沒有路線"
            return scene
        }
        scene.kind = .route
        scene.sport = e.resolvedSport
        if let el = elevation(e, in: s) {
            scene.hilly = el.hilly
            let ms = el.samples.map(\.meters)
            if let lo = ms.min(), let hi = ms.max(), hi - lo >= 1 {
                scene.profile = ms.map { ($0 - lo) / (hi - lo) }
            }
        }
        guard let splits = validSplits(e) else { return scene }
        let totalM = splits.reduce(0) { $0 + $1.meters }
        let totalS = splits.reduce(0) { $0 + $1.seconds }
        guard totalM > 0, totalS > 0 else { return scene }
        let isBike = e.resolvedSport == .bike
        // 路面：每一段一塊顏色
        let avgPace = totalS / (totalM / 1000)                 // 秒/公里
        let avgSpeed = (totalM / 1000) / (totalS / 3600)       // 公里/時
        var acc = 0.0
        for sp in splits {
            let from = acc / totalM
            acc += sp.meters
            let to = acc / totalM
            var level = WorkoutPaceLevel.even
            if sp.meters >= 200, sp.seconds > 0 {
                if isBike {
                    level = WorkoutPaceLevel.forSpeed(kmh: (sp.meters / 1000) / (sp.seconds / 3600), average: avgSpeed)
                } else {
                    level = WorkoutPaceLevel.forPace(seconds: sp.seconds / (sp.meters / 1000), average: avgPace)
                }
            }
            scene.bands.append(WorkoutTrailScene.Band(from: from, to: to, level: level))
        }
        // 柱子：跑走登山每公里、騎車每 5 公里（只算整的）
        let every = isBike ? 5 : 1
        var meters = 0.0
        var chunkSeconds = 0.0
        var chunkCount = 0
        var best: (index: Int, seconds: Double)? = nil
        for sp in splits where sp.meters >= 999 {
            meters += sp.meters
            chunkSeconds += sp.seconds
            chunkCount += 1
            if chunkCount == every {
                scene.marks.append(meters / totalM)
                scene.markLabels.append("\(scene.marks.count * every)")
                let faster = best.map { chunkSeconds < $0.seconds } ?? true
                if faster {
                    best = (index: scene.marks.count - 1, seconds: chunkSeconds)
                }
                chunkSeconds = 0
                chunkCount = 0
            }
        }
        if scene.marks.count >= 2 { scene.star = best?.index }
        return scene
    }
}

// MARK: - v4：Apple 健康（同一趟、合成、接回路線、改過要更新、寫進去的數字）
//
// [v25.554] 健康 v4（health/judge.md §6 v4、§2.5 舊紀錄、§3.4 要確認、§5.3 刪除、待決定 10；build/v4/brief.md）。
// 全部純函式（照 VehicleFacts）：Apple 健康的讀寫在 HealthKitManager，流程在 HealthSyncCenter（HealthSync.swift），
// 這裡只放「怎麼判斷、怎麼合、字怎麼寫」，好在 Python 逐行驗算（build/v4/sim_v4.py）。
// • 同一趟（sameOuting）：時間重疊至少較短那趟的一半，或開始、結束都差 5 分鐘內；運動一樣（健走、登山算同一類）。
// • 合成（merged）：大卡用手錶量的；路線用比較密的那條（手錶那條先對齊到 App 這一趟的時間、切掉暫停中的點，
//   而且要至少有 App 那條九成長）；名字、分段、暫停、距離、時間照 App 的。舊版記的那一趟（路線沒存到）整趟改用手錶的
//   時間、距離、路線、爬升（那時的開始時間是推回去的、距離含 GPS 飄移、爬升灌水），名字照 App 的。
// • 改過要更新（healthStale）：寫進去那一刻的距離（差 0.05 公里）、移動時間（差 30 秒）、開始（差 1 分鐘）、運動跟現在不一樣。

/// [v25.554] 手錶和 App 同時記到同一趟（健康頁、成果頁「要確認」：〔合成一筆〕〔兩筆都留〕；舊紀錄〔接回來〕）
struct WorkoutDuplicate: Identifiable, Equatable {
    /// WorkoutHealthLedger.pairKey（按「兩筆都留」記這個）
    var id: String
    /// App 記的那一趟
    var appId: UUID
    /// 手錶帶進來的那一趟（LifeGood 裡的 id）
    var watchId: UUID
    /// 手錶那一筆的 Apple 健康編號
    var watchUUID: String
    /// App 那一趟的運動
    var sport: WorkoutSport
    var appStart: Date
    var appEnd: Date
    var watchStart: Date
    var watchEnd: Date
    /// 手錶那一趟的距離（公里）
    var watchKm: Double
    /// App 那一趟是舊版記的、路線沒存到（問句改成「接回來」；手錶那一趟一定有路線）
    var legacy: Bool
}

/// [v25.554] 寫進 Apple 健康以後又改過（〔更新〕＝刪掉 Apple 健康裡舊的那筆、照現在的寫一筆新的）
struct WorkoutHealthStale: Identifiable, Equatable {
    /// 那一趟的 id
    var id: UUID
    var date: Date
    /// 畫面上的名字（WorkoutFacts.title）
    var title: String
    /// 寫進去那時的距離；距離沒改（改的是時間、開始、運動）是 nil
    var writtenKm: Double?
}

/// [v25.554] 寫進 Apple 健康的距離種類（HealthKitManager 對到 HKQuantityTypeIdentifier）
enum WorkoutHealthDistance: Equatable {
    /// 跑步、健走、登山：步行＋跑步距離
    case walkingRunning
    /// 騎車：騎車距離（v25.553 以前一律寫成步行＋跑步，健身 App 的步行距離被灌了騎的公里）
    case cycling
    /// 重訓、其他有氧（橢圓機、划船、游泳…）：不寫距離（寫成步行＋跑步是錯的）
    case none
}

extension WorkoutFacts {

    /// 打開健康頁時，離上次同步超過這麼久就自動同步（judge §6 v4）
    static let healthAutoSyncInterval: TimeInterval = 15 * 60
    /// 手錶的路線比那筆運動晚到：結束後這麼久以內，每次同步都再找一次（judge §6 v4、u4 §4.3）
    static let healthLateRouteWindow: TimeInterval = 24 * 3_600
    /// 同一趟的「前後容許」
    static let healthOverlapSlack: TimeInterval = 5 * 60

    // MARK: 寫進去

    /// 一趟的結束時間：App 記的用真正結束（endedAt，對得上才用），其他「開始＋移動時間」（WorkoutSession.workoutEnd）
    static func endDate(_ s: WorkoutSession) -> Date {
        s.workoutEnd(movingMinutes: movingMinutes(s))
    }

    /// 寫進 Apple 健康的距離種類：跑步、健走、登山＝步行＋跑步；騎車＝騎車；重訓、其他有氧不寫距離
    static func healthDistance(for sport: WorkoutSport) -> WorkoutHealthDistance {
        switch sport {
        case .run, .walk, .hike:
            return .walkingRunning
        case .bike:
            return .cycling
        case .strength, .other:
            return .none
        }
    }

    /// 寫進 Apple 健康的暫停（一次暫停＝一個「暫停」事件＋一個「繼續」事件）：照開始排好、夾在［start, end］裡、
    /// 不到 1 秒的不要、重疊或相接的併成一段。例：06:00 開始、06:20–06:30 暫停、06:52 結束 → 健身 App 移動時間 42 分鐘
    static func healthPauses(_ s: WorkoutSession, start: Date, end: Date) -> [WorkoutPause] {
        guard end > start else { return [] }
        let sorted = (s.pauses ?? []).sorted { $0.start < $1.start }
        var out: [WorkoutPause] = []
        for p in sorted {
            let a = max(p.start, start)
            let b = min(p.end, end)
            guard b.timeIntervalSince(a) >= 1 else { continue }
            if let last = out.last, a <= last.end {
                if b > last.end { out[out.count - 1].end = b }
            } else {
                out.append(WorkoutPause(start: a, end: b))
            }
        }
        return out
    }

    /// 寫進去成功時記下來的數字（成果頁「已存進 Apple 健康・06:40」、之後比對要不要〔更新〕）；
    /// 帶進來、合成、爬升的欄位照原本的留著
    static func healthStamp(_ s: WorkoutSession, at date: Date) -> WorkoutHealthLink {
        var h = s.health ?? WorkoutHealthLink()
        h.written = true
        h.writtenAt = date
        h.writtenKm = s.totalDistanceKm
        h.writtenMinutes = movingMinutes(s)
        h.writtenStart = s.date
        h.writtenSport = s.primarySport.rawValue
        return h
    }

    // MARK: 改過要更新

    /// LifeGood 寫進 Apple 健康以後又改過：距離差 0.05 公里以上、移動時間差 30 秒以上、開始差 1 分鐘以上、或運動換了。
    /// 只看 LifeGood 寫的（health.written == true、有編號、沒跟手錶合成過）；寫進去那時沒記的數字（nil）不比
    static func healthStale(_ s: WorkoutSession) -> WorkoutHealthStale? {
        guard s.healthKitUUID != nil, let h = s.health, h.written == true, h.mergedWatchUUID == nil else { return nil }
        var kmChanged = false
        if let w = h.writtenKm, abs(s.totalDistanceKm - w) >= 0.05 { kmChanged = true }
        var changed = kmChanged
        if let w = h.writtenMinutes, abs(movingMinutes(s) - w) >= 0.5 { changed = true }
        if let w = h.writtenStart, abs(s.date.timeIntervalSince(w)) >= 60 { changed = true }
        if let w = h.writtenSport, w != s.primarySport.rawValue { changed = true }
        guard changed else { return nil }
        return WorkoutHealthStale(id: s.id, date: s.date, title: title(s), writtenKm: kmChanged ? h.writtenKm : nil)
    }

    /// 全部改過、Apple 健康裡還是舊的那幾趟（新到舊）
    static func staleWrites(_ sessions: [WorkoutSession]) -> [WorkoutHealthStale] {
        sessions.compactMap { healthStale($0) }.sorted { $0.date > $1.date }
    }

    // MARK: 同步

    /// 這次同步從什麼時候抓起：上次同步往回 1 天（手錶跑完到 App 打開中間的那一趟、晚到的不會漏）；
    /// 第一次（或上次同步時間在未來：手機時間被改過）抓 90 天
    static func healthSyncStart(lastSync: Date?, now: Date) -> Date {
        if let l = lastSync, l <= now { return l.addingTimeInterval(-86_400) }
        return calendar.date(byAdding: .day, value: -90, to: now) ?? now.addingTimeInterval(-90 * 86_400)
    }

    /// 打開健康頁要不要自動同步：沒同步過、離上次 15 分鐘以上、或上次同步時間在未來
    static func healthSyncDue(lastSync: Date?, now: Date) -> Bool {
        guard let l = lastSync else { return true }
        let gap = now.timeIntervalSince(l)
        return gap >= healthAutoSyncInterval || gap < 0
    }

    /// 這一趟要不要再讀一次 Apple 健康那一筆：
    /// • 手錶帶進來的：v4 以前帶進來、還沒讀過（補爬升、騎車距離、路線）；或跑走騎登山、還沒有路線、結束 24 小時內（路線晚到）。
    /// • 其他有編號的（LifeGood 寫的、舊資料看不出來的）：還不知道是不是 LifeGood 寫的（health.written 是 nil）、也還沒讀過——
    ///   讀一次補上寫進去的數字（之後才知道要不要〔更新〕、刪除時能不能一起刪）。合成過的不讀
    static func needsHealthRefresh(_ s: WorkoutSession, now: Date) -> Bool {
        guard let uuid = s.healthKitUUID, UUID(uuidString: uuid) != nil else { return false }
        if source(of: s) == .watch {
            if s.health?.refreshedAt == nil { return true }
            guard [WorkoutSport.run, .walk, .bike, .hike].contains(s.primarySport),
                  s.firstRouteExercise == nil else { return false }
            let since = now.timeIntervalSince(endDate(s))
            return since >= 0 && since <= healthLateRouteWindow
        }
        if s.health?.mergedWatchUUID != nil { return false }
        return s.health?.written == nil && s.health?.refreshedAt == nil
    }

    // MARK: 同一趟

    /// 同一種運動才算同一趟；健走和登山算同一類（手錶選「戶外步行」、App 選登山）
    static func sportsMatch(_ a: WorkoutSport, _ b: WorkoutSport) -> Bool {
        if a == b { return true }
        let pair: Set<WorkoutSport> = [a, b]
        return pair == [.walk, .hike]
    }

    /// 兩段時間重疊的秒數（不重疊是 0）
    static func overlapSeconds(aStart: Date, aEnd: Date, bStart: Date, bEnd: Date) -> Double {
        let a1 = max(aEnd, aStart)
        let b1 = max(bEnd, bStart)
        return max(0, min(a1, b1).timeIntervalSince(max(aStart, bStart)))
    }

    /// 是不是同一趟出門：開始、結束都差 5 分鐘內；或重疊的時間至少是較短那一趟的一半（最短當 1 分鐘算）
    static func sameOuting(aStart: Date, aEnd: Date, bStart: Date, bEnd: Date) -> Bool {
        let a1 = max(aEnd, aStart)
        let b1 = max(bEnd, bStart)
        if abs(aStart.timeIntervalSince(bStart)) <= healthOverlapSlack
            && abs(a1.timeIntervalSince(b1)) <= healthOverlapSlack {
            return true
        }
        let overlap = overlapSeconds(aStart: aStart, aEnd: a1, bStart: bStart, bEnd: b1)
        guard overlap > 0 else { return false }
        let shorter = max(60, min(a1.timeIntervalSince(aStart), b1.timeIntervalSince(bStart)))
        return overlap >= shorter * 0.5
    }

    /// 這一趟跟 Apple 健康裡某一筆（開始、結束、運動）是不是同一趟（舊紀錄找回路線用）
    static func matchesOuting(_ s: WorkoutSession, start: Date, end: Date, sport: WorkoutSport?) -> Bool {
        guard let sport, sportsMatch(s.primarySport, sport) else { return false }
        return sameOuting(aStart: s.date, aEnd: endDate(s), bStart: start, bEnd: end)
    }

    /// 手錶和 App 同時記到的同一趟（新到舊）。App 那一趟＝App 記的有氧、還沒合成過；手錶那一趟＝帶進來的有氧、有編號。
    /// 一趟 App 只配重疊最多的那一筆手錶、一筆手錶只配一趟；按過「兩筆都留」的那一對不再出現。
    /// 舊版記的（路線沒存到）只在手錶那一筆有路線時才配（問句是「接回來」）
    static func duplicates(_ sessions: [WorkoutSession], ledger: WorkoutHealthLedger) -> [WorkoutDuplicate] {
        let watches = sessions.filter { w in
            source(of: w) == .watch && w.healthKitUUID != nil && w.primarySport.isCardio
        }
        guard !watches.isEmpty else { return [] }
        let apps = sessions
            .filter { a in
                source(of: a) == .app && a.primarySport.isCardio && a.health?.mergedWatchUUID == nil
            }
            .sorted { $0.date > $1.date }
        var used = Set<UUID>()
        var out: [WorkoutDuplicate] = []
        for a in apps {
            let aEnd = endDate(a)
            let legacy = a.isLegacyRouteMissing
            var best: WorkoutSession?
            var bestOverlap = -1.0
            for w in watches where !used.contains(w.id) {
                guard let hk = w.healthKitUUID, !ledger.keeps(appId: a.id, watchUUID: hk) else { continue }
                guard abs(w.date.timeIntervalSince(a.date)) <= 86_400 else { continue }
                guard sportsMatch(a.primarySport, w.primarySport) else { continue }
                if legacy && w.firstRouteExercise == nil { continue }
                let wEnd = endDate(w)
                guard sameOuting(aStart: a.date, aEnd: aEnd, bStart: w.date, bEnd: wEnd) else { continue }
                let ov = overlapSeconds(aStart: a.date, aEnd: aEnd, bStart: w.date, bEnd: wEnd)
                if ov > bestOverlap {
                    best = w
                    bestOverlap = ov
                }
            }
            guard let w = best, let hk = w.healthKitUUID else { continue }
            used.insert(w.id)
            out.append(WorkoutDuplicate(
                id: WorkoutHealthLedger.pairKey(appId: a.id, watchUUID: hk),
                appId: a.id, watchId: w.id, watchUUID: hk, sport: a.primarySport,
                appStart: a.date, appEnd: aEnd, watchStart: w.date, watchEnd: endDate(w),
                watchKm: w.totalDistanceKm, legacy: legacy))
        }
        return out
    }

    /// 舊版記的、路線沒存到、還要去 Apple 健康找路線的那幾趟（新到舊）：按過「先不要」的不找；
    /// 手錶那筆已經帶進 LifeGood 的（duplicates 裡有 legacy 的那一對）走合成，不用再找
    static func legacyNeedingRoute(_ sessions: [WorkoutSession], ledger: WorkoutHealthLedger,
                                   duplicates: [WorkoutDuplicate]) -> [WorkoutSession] {
        let paired = Set(duplicates.filter { $0.legacy }.map { $0.appId })
        return sessions
            .filter { $0.isLegacyRouteMissing && !ledger.skipped($0.id) && !paired.contains($0.id) }
            .sorted { $0.date > $1.date }
    }

    // MARK: 合成

    /// 路線長度（公尺；同一段 seg 裡相加，暫停的空隙不算）
    static func routeLengthMeters(_ route: [RoutePoint]) -> Double {
        guard route.count >= 2 else { return 0 }
        var total = 0.0
        for i in 1..<route.count {
            let p = route[i - 1]
            let q = route[i]
            guard (p.seg ?? 0) == (q.seg ?? 0) else { continue }
            let d = CLLocation(latitude: p.lat, longitude: p.lon)
                .distance(from: CLLocation(latitude: q.lat, longitude: q.lon))
            if d.isFinite { total += d }
        }
        return total
    }

    /// 手錶的路線對齊到 App 這一趟：每一點的時間改成「距 App 開始幾秒」；App 開始前、結束後（前後容許 1 秒）、
    /// App 暫停中的點不要；第幾次暫停之後就是第幾段（seg，0 寫 nil）
    static func routeRebased(_ route: [RoutePoint], routeStart: Date, start: Date, end: Date,
                             pauses: [WorkoutPause]?) -> [RoutePoint] {
        let ps = (pauses ?? []).filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        let lo = start.addingTimeInterval(-1)
        let hi = end.addingTimeInterval(1)
        var out: [RoutePoint] = []
        out.reserveCapacity(route.count)
        for p in route {
            let at = routeStart.addingTimeInterval(p.t)
            guard at >= lo, at <= hi else { continue }
            var seg = 0
            var inPause = false
            for q in ps {
                if at > q.start && at < q.end {
                    inPause = true
                    break
                }
                if at >= q.end { seg += 1 }
            }
            if inPause { continue }
            out.append(RoutePoint(lat: p.lat, lon: p.lon, t: max(0, at.timeIntervalSince(start)),
                                  alt: p.alt, seg: seg == 0 ? nil : seg))
        }
        return out
    }

    /// 合成時要不要換成手錶那條路線：App 那條不到 2 點就換；不然手錶那條要至少有 App 那條九成長（手錶晚按、早停的不換），
    /// 而且每公里的點比較多（比較密）
    static func prefersWatchRoute(mine: [RoutePoint], watch: [RoutePoint]) -> Bool {
        guard watch.count >= 2 else { return false }
        guard mine.count >= 2 else { return true }
        let lw = routeLengthMeters(watch)
        let lm = routeLengthMeters(mine)
        guard lm > 0, lw >= lm * 0.9 else { return false }
        let dw = Double(watch.count) / max(lw / 1000, 0.1)
        let dm = Double(mine.count) / max(lm / 1000, 0.1)
        return dw > dm
    }

    /// 一趟裡要換路線、換數字的那個動作：有路線的那個；沒有就第一個有氧
    static func mainCardioIndex(_ s: WorkoutSession) -> Int? {
        s.exercises.firstIndex { $0.hasRoute } ?? s.exercises.firstIndex { $0.kind == .cardio }
    }

    /// 手錶和 App 同一趟合成一筆（待決定 10：大卡、心率用手錶的，路線用比較密的那條，名稱用 App 的）。
    /// 回傳的是 App 那一趟（同一個 id）；healthKitUUID 不動（要不要改指向手錶那筆，看 LifeGood 自己寫的那筆刪掉了沒，
    /// HealthSyncCenter 決定）；health.mergedWatchUUID 記手錶那筆。大卡手錶沒量時，呼叫端再 applyKcalEstimate 一次
    static func merged(app a: WorkoutSession, watch w: WorkoutSession) -> WorkoutSession {
        var out = a
        if out.source == nil { out.source = source(of: a) ?? .app }
        var link = a.health ?? WorkoutHealthLink()
        link.mergedWatchUUID = w.healthKitUUID
        if w.activeEnergyKcal > 0 && w.kcalEstimated != true {
            out.activeEnergyKcal = w.activeEnergyKcal
            out.kcalEstimated = nil
        }
        guard let i = mainCardioIndex(a) else {
            out.health = link
            return out
        }
        if a.isLegacyRouteMissing {
            // 舊版記的：開始時間是「按完成減掉時間」推回去的、距離含 GPS 飄移、爬升灌水——整趟改用手錶的
            if let we = w.firstRouteExercise ?? w.cardioExercises.first {
                out.date = w.date
                out.endedAt = endDate(w)
                let moving = movingMinutes(w)
                if moving > 0 {
                    out.durationMinutes = moving
                    out.exercises[i].durationMinutes = moving
                }
                if we.distanceKm > 0 { out.exercises[i].distanceKm = we.distanceKm }
                out.exercises[i].route = we.route
                out.exercises[i].splits = nil
                let wc = climb(we, in: w)
                out.exercises[i].elevationGainM = wc ?? 0
                link.climbKnown = wc != nil
                out.pauses = nil
            }
        } else if let we = w.firstRouteExercise {
            let rebased = routeRebased(we.route, routeStart: w.date, start: a.date, end: endDate(a), pauses: a.pauses)
            if prefersWatchRoute(mine: out.exercises[i].route, watch: rebased) {
                out.exercises[i].route = rebased
            }
        }
        out.health = link
        return out
    }

    // MARK: 字（健康頁、成果頁「要確認」）

    /// 健康頁：「Apple Watch 也記了 10/8 06:04–06:41 這一趟（6.0 公里），要合成一筆嗎？」；
    /// 舊紀錄「9/20 的跑步是舊版記的，路線沒存到；Apple Watch 同一時間有路線。」
    static func duplicatePrompt(_ d: WorkoutDuplicate) -> String {
        if d.legacy { return legacyRoutePrompt(date: d.appStart, sport: d.sport) }
        var s = "Apple Watch 也記了 " + WorkoutFormat.monthDay(d.watchStart) + " "
            + WorkoutFormat.time(d.watchStart) + "–" + WorkoutFormat.time(d.watchEnd) + " 這一趟"
        if d.watchKm >= 0.05 { s += "（" + WorkoutFormat.km(d.watchKm) + "）" }
        return s + "，要合成一筆嗎？"
    }

    /// 健康頁：舊紀錄（手錶那筆還沒帶進來、或已經帶進來）「9/20 的跑步是舊版記的，路線沒存到；Apple Watch 同一時間有路線。」
    static func legacyRoutePrompt(date: Date, sport: WorkoutSport) -> String {
        WorkoutFormat.monthDay(date) + " 的" + sport.displayName + "是舊版記的，路線沒存到；Apple Watch 同一時間有路線。"
    }

    /// 成果頁（看的是 App 那一趟）：「Apple Watch 也記了這一趟（06:04–06:39），要合成一筆嗎？」；
    /// 看的是手錶那一趟：「LifeGood 也記了這一趟（06:05–06:39），要合成一筆嗎？」；舊紀錄改成「接回來」的說法
    static func duplicateDetailPrompt(_ d: WorkoutDuplicate, viewingWatch: Bool) -> String {
        if d.legacy {
            return viewingWatch
                ? "LifeGood 舊版也記了這一趟，路線當時沒存到；可以把這一筆的路線接回去、合成一筆。"
                : "這一趟是舊版記錄的，路線當時沒存到；Apple Watch 同一時間有路線，可以接回來。"
        }
        if viewingWatch {
            return "LifeGood 也記了這一趟（" + WorkoutFormat.time(d.appStart) + "–" + WorkoutFormat.time(d.appEnd)
                + "），要合成一筆嗎？"
        }
        return "Apple Watch 也記了這一趟（" + WorkoutFormat.time(d.watchStart) + "–" + WorkoutFormat.time(d.watchEnd)
            + "），要合成一筆嗎？"
    }

    /// 健康頁：「10/12 晨跑改過了，Apple 健康裡還是 4.0 公里。」；距離沒改「…Apple 健康裡還是改之前的樣子。」
    static func stalePrompt(_ st: WorkoutHealthStale) -> String {
        let head = WorkoutFormat.monthDay(st.date) + " " + st.title + "改過了，Apple 健康裡還是"
        if let km = st.writtenKm { return head + " " + WorkoutFormat.km(km) + "。" }
        return head + "改之前的樣子。"
    }

    /// 成果頁 Apple 健康那一列：「Apple 健康裡還是改之前的 5.0 公里」；距離沒改「Apple 健康裡還是改之前的樣子」
    static func staleDetail(_ st: WorkoutHealthStale) -> String {
        if let km = st.writtenKm { return "Apple 健康裡還是改之前的 " + WorkoutFormat.km(km) }
        return "Apple 健康裡還是改之前的樣子"
    }

    /// 健康頁：v4 多要一項讀寫權限（騎車距離），還沒同意過
    static let moreAccessPrompt = "Apple 健康多了一項要你同意：騎車距離。"
}

// MARK: - v5：跑步畫面的數字、存檔時取名、GPS 弱、分享（v25.555，健康 v5；health/judge.md §4、§5.3、build/v5/brief.md §2）
//
// 全部是純函式（同 v2～v4），build/v5/sim_v5.py 逐行照寫、驗算（這一公里、時速、這一段、取名、剪頭尾 200 公尺、GPS 弱那一句）。
// • 跑步中「這一公里」那一格＝最近 30 秒存下來的點走了多遠、花多久（不到 50 公尺寫「—」）；騎車「時速」＝最近 10 秒。
//   只算同一段（暫停之後重新算）；最近 30 秒都沒有新點（站著、隧道）就是「—」。
// • 「這一公里」小步道：跑走登山每 1 公里一段、騎車每 5 公里一段；用了多久＝現在的移動時間減掉走滿上一段那一刻的移動時間
//   （RunTracker.kmTimes）。
// • 存檔時取名：起點 150 公尺內有「你改過名字」的同一種運動（最近那一趟）就沿用那個名字；不然照時段（timeOfDayName）。
//   「改過名字」＝不是運動名、也不是時段名（自動取的「晨跑」不算，不然晚上從同一個地方出發也叫晨跑）。
// • 分享圖的路線形狀：頭尾各剪掉 200 公尺（家門口不會出現在圖上）；剪完不到 200 公尺就不給放。

/// [v25.555] 跑步中「這一公里」小步道（騎車「這 5 公里」）
struct RunLegProgress: Equatable {
    /// 一段多長（公尺）：跑步、健走、登山 1,000；騎車 5,000
    var legMeters: Double
    /// 第幾段（1 起）：跑步走到 3.42 公里是第 4 段（畫面「第 4 公里」）；騎車 12.6 公里是第 3 段
    var index: Int
    /// 這一段走了幾公尺（0…legMeters）
    var doneMeters: Double
    /// 這一段用了幾秒（移動時間，暫停不算）；記錄器沒記到上一段的時間是 nil
    var seconds: Double?

    /// 小步道填多滿（0…1）
    var fraction: Double { legMeters > 0 ? min(1, max(0, doneMeters / legMeters)) : 0 }
}

/// [v25.555] 開始前面板下面那兩行（樣稿②-2）
struct RunIntro: Equatable {
    /// 「這週跑了 9.4 公里・目標 20」「這週還沒騎・目標 50」「這週走了 3.1 公里」
    var week: String
    /// 「上一趟：昨天 06:10・晨跑 5.1 公里」（這種運動的上一趟）；沒有是 nil
    var last: String?
}

extension WorkoutFacts {

    // MARK: 存檔時取名

    /// 起點離你改過名字的那一趟起點多近（公尺）就沿用那個名字
    static let sameStartMeters: Double = 150

    /// 時段取的名字全部（timeOfDayName 的四種運動 × 五個時段；登山一律「登山」）：用來分辨「自動取的」和「你改過的」
    static let autoTitles: Set<String> = {
        var out: Set<String> = []
        for sport in [WorkoutSport.run, .walk, .bike, .hike] {
            for hour in [7, 12, 15, 20, 2] {
                var c = DateComponents()
                c.year = 2026
                c.month = 1
                c.day = 5
                c.hour = hour
                if let d = WorkoutFacts.calendar.date(from: c) {
                    out.insert(WorkoutFacts.timeOfDayName(sport, start: d))
                }
            }
        }
        return out
    }()

    /// 名字是你自己取的：不是空白、不是運動名（「跑步」「走路」…）、也不是時段名（「晨跑」「夜騎」…）
    static func isCustomTitle(_ title: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && !genericTitles.contains(t) && !autoTitles.contains(t)
    }

    /// 一趟的起點（第一個有路線的動作的第一點）；沒有路線（舊版只存到起點的也算沒有）是 nil
    static func startPoint(_ s: WorkoutSession) -> RoutePoint? {
        s.firstRouteExercise?.route.first
    }

    /// 起點 150 公尺內、同一種運動、你改過名字的那幾趟裡最近的那一趟的名字；沒有是 nil
    static func inheritedTitle(sport: WorkoutSport, startPoint: RoutePoint?,
                               sessions: [WorkoutSession]) -> String? {
        guard let p = startPoint, p.lat.isFinite, p.lon.isFinite else { return nil }
        let here = CLLocation(latitude: p.lat, longitude: p.lon)
        var best: (date: Date, title: String)? = nil
        for s in sessions where s.primarySport == sport && isCustomTitle(s.title) {
            // 參數也叫 startPoint：這裡一律寫 WorkoutFacts.startPoint(_:)
            guard let q = WorkoutFacts.startPoint(s), q.lat.isFinite, q.lon.isFinite else { continue }
            let d = here.distance(from: CLLocation(latitude: q.lat, longitude: q.lon))
            guard d <= sameStartMeters else { continue }
            if let b = best, b.date >= s.date { continue }
            best = (date: s.date, title: s.title.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return best?.title
    }

    /// 存檔時的名字：沿用改過的名字（inheritedTitle），不然照時段（「晨跑」）
    static func autoTitle(sport: WorkoutSport, start: Date, startPoint: RoutePoint?,
                          sessions: [WorkoutSession]) -> String {
        inheritedTitle(sport: sport, startPoint: startPoint, sessions: sessions)
            ?? timeOfDayName(sport, start: start)
    }

    // MARK: 跑步中（RunTracker 每秒讀；畫面只讀記錄器算好的值）

    /// 「這一公里」那一格看最近幾秒
    static let recentPaceSeconds: Double = 30
    /// 最近 30 秒不到這麼多公尺寫「—」（剛起跑、站著）
    static let recentPaceMinMeters: Double = 50
    /// 騎車「時速」看最近幾秒
    static let recentSpeedSeconds: Double = 10
    /// 最近 10 秒裡存下來的點至少要跨這麼多秒才算時速
    static let recentSpeedMinSeconds: Double = 3

    /// 最近 seconds 秒（nowT 往回）存下來的點：同一段（暫停之後重算）、相鄰兩點距離加總、第一點到最後一點的時間差。
    /// nowT＝現在離按開始幾秒（RoutePoint.t 的同一把尺，含暫停）。最後一點也太舊（站著、隧道）、不到兩點回 nil
    static func recentWindow(_ points: [RoutePoint], nowT: Double, seconds: Double) -> (meters: Double, seconds: Double)? {
        guard let last = points.last, nowT.isFinite, last.t >= nowT - seconds else { return nil }
        let seg = last.seg ?? 0
        var meters = 0.0
        var firstT = last.t
        var i = points.count - 1
        while i > 0 {
            let p = points[i - 1]
            let q = points[i]
            guard (p.seg ?? 0) == seg, (q.seg ?? 0) == seg, p.t >= nowT - seconds else { break }
            meters += CLLocation(latitude: p.lat, longitude: p.lon)
                .distance(from: CLLocation(latitude: q.lat, longitude: q.lon))
            firstT = p.t
            i -= 1
        }
        let dt = last.t - firstT
        guard dt > 0, meters.isFinite else { return nil }
        return (meters: meters, seconds: dt)
    }

    /// 「這一公里」那一格（分鐘／公里）：最近 30 秒走不到 50 公尺回 nil（畫面寫「—」）
    static func recentPace(_ points: [RoutePoint], nowT: Double) -> Double? {
        guard let w = recentWindow(points, nowT: nowT, seconds: recentPaceSeconds),
              w.meters >= recentPaceMinMeters else { return nil }
        return (w.seconds / 60) / (w.meters / 1000)
    }

    /// 騎車「時速」（公里／時）：最近 10 秒；點跨不到 3 秒回 nil（畫面寫「—」）
    static func recentSpeedKmh(_ points: [RoutePoint], nowT: Double) -> Double? {
        guard let w = recentWindow(points, nowT: nowT, seconds: recentSpeedSeconds),
              w.seconds >= recentSpeedMinSeconds else { return nil }
        return (w.meters / 1000) / (w.seconds / 3600)
    }

    /// 「這一公里」小步道。kmTimes[i]＝走滿第 i+1 公里那一刻的移動時間（秒；RunTracker 記的）。
    /// 例：3,420 公尺、移動 1,265 秒、kmTimes [365, 735, 1105] → 第 4 公里、420 公尺、160 秒（2'40"）；
    ///     騎車 12,600 公尺 → 第 3 段（10～15 公里）、2,600 公尺
    static func legProgress(distanceMeters: Double, elapsed: Double, kmTimes: [Double],
                            sport: WorkoutSport) -> RunLegProgress {
        let legKm = sport == .bike ? 5 : 1
        let legMeters = Double(legKm) * 1000
        let d = distanceMeters.isFinite ? max(0, distanceMeters) : 0
        let done = Int(min(d / legMeters, 100_000).rounded(.down))      // 走滿幾段
        let doneMeters = d - Double(done) * legMeters
        var seconds: Double? = nil
        if done == 0 {
            seconds = max(0, elapsed)
        } else {
            let k = done * legKm - 1                                       // 走滿上一段那一刻＝第 done×legKm 公里
            if k >= 0, k < kmTimes.count {
                seconds = max(0, elapsed - kmTimes[k])
            }
        }
        return RunLegProgress(legMeters: legMeters, index: done + 1, doneMeters: doneMeters, seconds: seconds)
    }

    /// 小步道右邊的字：跑走登山「420／1000 m・2'40"」（時間不知道「420／1000 m」）；騎車「這 5 公里 2.6／5 公里」
    static func legText(_ p: RunLegProgress, sport: WorkoutSport) -> String {
        if sport == .bike {
            return "這 5 公里 " + String(format: "%.1f", max(0, p.doneMeters) / 1000) + "／5 公里"
        }
        let m = WorkoutFormat.wholeSeconds(p.doneMeters.rounded(.down))
        var text = "\(min(m, 999))／1000 m"
        if let sec = p.seconds { text += "・" + legClock(sec) }
        return text
    }

    /// 「2'40"」（這一段用了多久，秒數四捨五入：159.6 秒寫 2'40"，跟「21:05 − 18:25」心算對得上）；一小時以上「1:02'05"」
    static func legClock(_ seconds: Double) -> String {
        let s = WorkoutFormat.wholeSeconds(seconds)
        if s >= 3600 {
            return String(format: "%d:%02d'%02d\"", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%d'%02d\"", s / 60, s % 60)
    }

    /// 面板右上：跑走登山「第 4 公里」；騎車寫時速（畫面自己組），這裡只給跑走登山的字
    static func legTitle(_ p: RunLegProgress) -> String {
        "第 \(p.index) 公里"
    }

    /// 跑步中「約 220 大卡」那一格（點中間那格換到大卡）：（MET − 1）× 體重 × 小時，MET 照這一趟到現在的平均速度；
    /// 沒有體重、不到 1 分鐘回 nil（畫面寫「—」）
    static func liveKcal(sport: WorkoutSport, km: Double, movingSeconds: Double, bodyWeightKg: Double?) -> Double? {
        guard let w = bodyWeightKg, w > 0, movingSeconds >= 60, movingSeconds.isFinite else { return nil }
        let minutes = movingSeconds / 60
        let speed = WorkoutFormat.speedKmh(km: km, minutes: minutes)
        let k = (met(sport: sport, speedKmh: speed) - 1) * w * (minutes / 60)
        guard k.isFinite, k > 0 else { return nil }
        return k
    }

    /// 開始前面板下面兩行（樣稿②-2）：「這週跑了 9.4 公里・目標 20」＋「上一趟：昨天 06:10・晨跑 5.1 公里」
    static func runIntro(_ sessions: [WorkoutSession], prefs: WorkoutPrefs, sport: WorkoutSport,
                         now: Date = Date()) -> RunIntro {
        let p = weekProgress(sessions, prefs: prefs, sport: sport, now: now)
        let v = verb(sport)
        var week = p.doneKm >= 0.05 ? "這週\(v)了 " + WorkoutFormat.km(p.doneKm) : "這週還沒\(v)"
        if let g = p.goalKm {
            week += "・目標 " + HealthPageData.goalKmText(g).replacingOccurrences(of: " 公里", with: "")
        }
        var lastSession: WorkoutSession? = nil
        for s in sessions where s.date <= now && s.primarySport == sport {
            if let l = lastSession, l.date >= s.date { continue }
            lastSession = s
        }
        var last: String? = nil
        if let s = lastSession {
            let km = s.totalDistanceKm
            last = "上一趟：" + HealthPageData.whenText(s.date, now: now) + "・" + title(s)
                + (km >= 0.05 ? " " + WorkoutFormat.km(km) : "")
        }
        return RunIntro(week: week, last: last)
    }

    // MARK: GPS 弱（judge §4.1 第 9 列、§5.2 ③）

    /// 誤差超過這個（公尺）算弱（同 RunTracker.goodAccuracy：超過就不起點、不算距離）
    static let gpsWeakAccuracy: Double = 20
    /// 弱（或收不到）連續這麼多秒才出現「GPS 訊號弱，距離可能少算」
    static let gpsWeakSeconds: Double = 10

    /// 成果頁「要確認」（只提醒）：記錄 2 分鐘以上、一半以上的時間 GPS 弱。
    /// 「這趟大部分時間 GPS 訊號很弱（平均誤差 35 公尺），距離可能少算。」；沒有平均誤差就不寫括號
    static func gpsWeakPrompt(_ s: WorkoutSession) -> String? {
        guard let g = s.gps, let tracked = g.trackedSeconds, tracked >= 120,
              let weak = g.weakSeconds, weak >= tracked * 0.5 else { return nil }
        if let a = g.averageAccuracyM, a.isFinite, a > 0 {
            return "這趟大部分時間 GPS 訊號很弱（平均誤差 \(WorkoutFormat.wholeSeconds(a)) 公尺），距離可能少算。"
        }
        return "這趟大部分時間 GPS 訊號很弱，距離可能少算。"
    }

    // MARK: 分享（judge §5.3、待決定 9：預設不放路線形狀；要放時頭尾 200 公尺剪掉、不放地圖底；只寫日期不寫幾點）

    /// 分享圖的路線頭尾各剪掉幾公尺
    static let shareTrimMeters: Double = 200

    /// 路線頭尾各剪掉 meters 公尺（沿著路線量；暫停的空隙不算距離），剪的地方內插一點。
    /// 剪完不到 200 公尺（整條不到 600 公尺）回 nil：不給放路線形狀
    static func trimmedRoute(_ route: [RoutePoint], meters: Double = 200) -> [RoutePoint]? {
        guard route.count >= 2, meters >= 0 else { return nil }
        // 每一點離起點沿路線幾公尺（同一段裡相鄰兩點才加）
        var cum = [Double](repeating: 0, count: route.count)
        for i in 1..<route.count {
            let p = route[i - 1]
            let q = route[i]
            var d = 0.0
            if (p.seg ?? 0) == (q.seg ?? 0) {
                d = CLLocation(latitude: p.lat, longitude: p.lon)
                    .distance(from: CLLocation(latitude: q.lat, longitude: q.lon))
                if !d.isFinite { d = 0 }
            }
            cum[i] = cum[i - 1] + d
        }
        let total = cum[route.count - 1]
        let from = meters
        let to = total - meters
        guard to - from >= 200 else { return nil }
        var out: [RoutePoint] = []
        for i in 1..<route.count {
            let a = cum[i - 1]
            let b = cum[i]
            let p = route[i - 1]
            let q = route[i]
            // 剪的那一刀落在這一步裡：內插一點（只會落在同一段裡：跨段那一步距離是 0）
            if a < from, b >= from, b > a {
                out.append(interpolated(p, q, k: (from - a) / (b - a)))
            }
            if a >= from, a <= to, out.last.map({ $0.t != p.t || $0.lat != p.lat || $0.lon != p.lon }) ?? true {
                out.append(p)
            }
            if a < to, b >= to, b > a {
                out.append(interpolated(p, q, k: (to - a) / (b - a)))
                break
            }
        }
        return out.count >= 2 ? out : nil
    }

    /// p 到 q 之間 k（0…1）的那一點（座標、時間、高度線性內插；段號用 q 的）
    private static func interpolated(_ p: RoutePoint, _ q: RoutePoint, k: Double) -> RoutePoint {
        let t = min(1, max(0, k))
        return RoutePoint(lat: p.lat + (q.lat - p.lat) * t,
                          lon: p.lon + (q.lon - p.lon) * t,
                          t: p.t + (q.t - p.t) * t,
                          alt: p.alt + (q.alt - p.alt) * t,
                          seg: q.seg)
    }

    /// 分享圖要放的路線形狀（頭尾剪掉 200 公尺再換成 0…1；不打地圖請求、沒有街名）；沒有路線或太短回 nil
    static func shareRouteShape(_ s: WorkoutSession) -> WorkoutRouteShape? {
        guard let e = s.firstRouteExercise, let t = trimmedRoute(e.route, meters: shareTrimMeters) else { return nil }
        return routeShape(t, maxPoints: 160, minSpanMeters: 200)
    }

    /// 分享圖的日期：只寫「10/15」，不寫幾點、不寫星期
    static func shareDate(_ s: WorkoutSession) -> String {
        WorkoutFormat.monthDay(s.date)
    }

    /// 分享圖中間那一行：「河濱晨跑　5.2 公里・32:10・配速 6'11"」；騎車「…・時速 21.5」；沒距離「胸推日　45 分鐘」
    static func shareHeadline(_ s: WorkoutSession) -> String {
        let name = title(s)
        let km = s.totalDistanceKm
        let moving = movingMinutes(s)
        guard km >= 0.05 else {
            return moving > 0 ? name + "　" + WorkoutFormat.total(minutes: moving) : name
        }
        var parts = [WorkoutFormat.km(km)]
        if moving > 0 {
            parts.append(WorkoutFormat.clock(minutes: moving))
            if s.primarySport == .bike {
                if let v = WorkoutFormat.speedKmh(km: km, minutes: moving) {
                    parts.append("時速 " + WorkoutFormat.speedNumber(v))
                }
            } else {
                parts.append("配速 " + WorkoutFormat.pace(km: km, minutes: moving))
            }
        }
        return name + "　" + parts.joined(separator: "・")
    }
}
