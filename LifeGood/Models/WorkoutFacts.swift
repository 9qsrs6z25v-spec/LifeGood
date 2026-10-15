import Foundation
import CoreLocation

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
        return nil
    }

    /// 這個動作的爬升（公尺）；不知道回 nil（畫面不顯示、不加總、不進紀錄）。
    /// 知道的只有 App 記、有路線的（v25.551 起氣壓計／GPS 去雜訊）；舊版只存到起點的是灌水的，
    /// 手動補記沒填、Apple 健康帶進來的目前寫 0（v4 才讀手錶的爬升），都當不知道
    static func climb(_ e: WorkoutExercise, in s: WorkoutSession) -> Double? {
        guard e.kind == .cardio, e.hasRoute else { return nil }
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

    /// 連續幾週有運動：從這週往回數；這週還沒動就從上週數（待決定 3）
    static func streakWeeks(_ sessions: [WorkoutSession], now: Date = Date()) -> Int {
        var weeks = Set<Date>()
        for s in sessions where counts(s) {
            weeks.insert(weekStart(of: s.date))
        }
        var cursor = weekStart(of: now)
        if !weeks.contains(cursor) {
            guard let prev = calendar.date(byAdding: .day, value: -7, to: cursor) else { return 0 }
            cursor = prev
        }
        var n = 0
        while weeks.contains(cursor) {
            n += 1
            guard let prev = calendar.date(byAdding: .day, value: -7, to: cursor) else { break }
            cursor = prev
        }
        return n
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
    /// 名稱 v2 還是運動名（「跑步」）；時段取名（晨跑、夜跑）是 v5。
    static func makeSession(from r: RunResult, bodyWeightKg: Double?) -> WorkoutSession {
        let splits = splitsWithClimb(RouteMath.kmSplits(r.route), kmClimb: r.kmClimb, totalClimb: r.elevation)
        let exercise = WorkoutExercise(
            name: r.sport.rawValue, kind: .cardio, reps: 0, sets: 0, loadType: .none,
            loadKg: 0, distanceKm: r.distanceKm, durationMinutes: r.movingMinutes,
            route: RouteMath.simplified(r.route), elevationGainM: r.elevation,
            sport: WorkoutSport(r.sport), splits: splits.isEmpty ? nil : splits)
        var session = WorkoutSession(
            date: r.startedAt,                 // 按開始那一刻
            title: r.sport.rawValue,
            exercises: [exercise],
            durationMinutes: r.movingMinutes,  // 扣掉暫停的移動時間
            endedAt: r.endedAt,                // 最後一次按暫停那一刻
            source: .app,
            pauses: r.pauses.isEmpty ? nil : r.pauses)
        applyKcalEstimate(&session, bodyWeightKg: bodyWeightKg)
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
