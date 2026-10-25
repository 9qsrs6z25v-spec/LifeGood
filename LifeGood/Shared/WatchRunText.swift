import Foundation

// MARK: - 手錶跑步的字與規則（手錶 v4，v25.580；watch/judge.md §2.9～§2.12、§5.7、§7.3「跑步那一條照抄不搬」；
//         watch/build/v4/brief.md §2；模擬：watch/build/v4/sim_v4.py；照抄核對：watch/build/v4/run_check.py）
//
// 這個檔屬於手錶 App 與手錶小格兩個 target（iPhone 兩個 target 不編，同 WatchTripText.swift）。只准 Foundation。
// 放 Shared/ 不放 LifeGoodWatch/（judge §7.4 寫的是 LifeGoodWatch/RunText.swift）：v5 錶面「這週跑步」小格要用同一套數字。
//
// 三種東西：
// 1. **照抄** iPhone（只換名字：WorkoutSport → WatchSport、WorkoutFormat → WatchRunFormat、WorkoutFacts → WatchRunFacts、
//    WorkoutPaceLevel → WatchPaceLevel；run_check.py 每版核對函式本體一個 token 都不差）：
//    • WatchRunFormat ← WorkoutFormat（WorkoutFacts.swift）：wholeSeconds、kmNumber、preciseKmNumber、clock(seconds:)、
//      pace(_:)、pace(km:minutes:)、speedKmh、speedNumber、kcal
//    • WatchRunFacts ← WorkoutFacts：calendar、weekStart（週一起算，台灣地區系統預設是週日，不能用 Calendar.current）、week、
//      weekdayIndex、dayPart、timeOfDayName、verb、recentPace／Speed 的四個常數；
//      WorkoutProgress.swift 的 voiceDuration、voiceSpeed、voiceKm、voiceAutoPause、voiceAutoResume（每公里那一句跟 iPhone 一字不差）
//    • WatchPaceLevel ← WorkoutPaceLevel（forPace、forSpeed）
// 2. **手錶自己的規則**（sim_v4.py 同名函式；改了兩邊一起改）：走滿整公里那一刻（kmCrossings）、「這一公里」最近 30 秒配速
//    （recentPace，同 iPhone 30 秒、50 公尺的規則，只是手錶用累計距離算）、③ 這週（home：iPhone 的 runWeek＋手錶自己記、
//    seen 裡沒有的那幾趟）、準備頁那一行（prepLine）、跑步中四個數字（live）、每公里那一頁（kmFlash）、跑完摘要（summary）、
//    路線小圖（routeShape）。
// 3. 手錶自己存的小東西（手錶 App Group 的 UserDefaults；手錶小格 v5 也讀）：WatchRunLog（手錶記過的每一趟：編號、運動、
//    時間、公里，最多 30 趟、14 天）、WatchRunPrefs（每公里講一句、震一下、上一次用的運動）。
//
// ⚠️ 這裡沒有 HealthKit、CoreLocation（小格不能 import）：路線點、暫停、一趟的紀錄都是這個檔自己的 Codable 型別，
//    手錶 App 的 WorkoutManager／RouteRecorder 把 HKWorkout、CLLocation 換成這幾個。
// ⚠️ 隱私（judge §6.1）：跑步中頁首只寫時段名「晨跑」（不寫地名）；路線小圖是 0～1 相對形狀（不畫地圖、不送 iPhone）；
//    心率只在手錶上顯示，不存進 iPhone 的 LifeGood。
//
// [手錶 v5] v25.582（watch/build/v5/brief.md §2）：只加不改——
//   • WatchRunHome 多幾個數字欄（km、goalKm、runs、streakWeeks、daysLeft、hasData、dayKm、ownExtra；都有預設值）：
//     「這週」7 根小柱、錶面「這週跑步」小格用同一份（WatchRunWeekText，Shared/WatchRunWeekText.swift）。home() 的規則一行沒改
//   • WatchRunLogEntry 多 heartAvg、heartMax、shape（選填；「那一趟」的心率、小圖：手錶自己記的那幾趟）

// MARK: - 運動種類

/// 手錶上的運動（rawValue＝iPhone WorkoutSport 的 run／walk／bike／hike；重訓、其他有氧手錶不記）
enum WatchSport: String, Codable, CaseIterable, Identifiable {
    case run
    case walk
    case bike
    case hike

    var id: String { rawValue }

    /// 畫面上的字（同 iPhone WorkoutSport.displayName）
    var displayName: String {
        switch self {
        case .run: return "跑步"
        case .walk: return "健走"
        case .bike: return "騎車"
        case .hike: return "登山"
        }
    }

    /// SF Symbols（同 iPhone WorkoutSport.icon；watchOS 9 起都有）
    var icon: String {
        switch self {
        case .run: return "figure.run"
        case .walk: return "figure.walk"
        case .bike: return "figure.outdoor.cycle"
        case .hike: return "figure.hiking"
        }
    }

    /// 運動色（iPhone WorkoutPalette.sport 淺色那組：手錶夜空、純黑底上要亮一點；judge §2.9「🏃 跑步亮色 EB6834」）
    var tint: UInt32 {
        switch self {
        case .run: return 0xEB6834
        case .walk: return 0x1BAF7A
        case .bike: return 0x2A78D6
        case .hike: return 0xEDA100
        }
    }

    /// 底部主鈕「開始跑步」「開始騎車」
    var startTitle: String { "開始" + displayName }

    /// 準備頁轉錶冠的順序：跑步 → 健走 → 騎車 → 登山
    static let crownOrder: [WatchSport] = [.run, .walk, .bike, .hike]

    /// 準備頁第二行：另外三種「健走・騎車・登山」
    var others: String {
        WatchSport.crownOrder.filter { $0 != self }.map { $0.displayName }.joined(separator: "・")
    }
}

// MARK: - 照抄 WorkoutFormat（WorkoutFacts.swift；run_check.py 核對）

enum WatchRunFormat {

    /// 秒數取整數（四捨五入）；NaN、無限大、負的都當 0，超大夾住（Int(Double) 碰到這些會閃退）
    static func wholeSeconds(_ seconds: Double) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int(min(seconds, 360_000_000).rounded())
    }

    /// 「5.2」：清單、膠囊、看板（一位小數）
    static func kmNumber(_ km: Double) -> String {
        guard km.isFinite, km > 0 else { return "0.0" }
        return String(format: "%.1f", km)
    }

    /// 「5.20」：成果頁、跑步中（兩位）；騎車 10 公里以上一位（「12.6」）
    static func preciseKmNumber(_ km: Double, sport: WatchSport? = nil) -> String {
        guard km.isFinite, km > 0 else { return "0.00" }
        if sport == .bike, km >= 10 { return String(format: "%.1f", km) }
        return String(format: "%.2f", km)
    }

    /// 「32:10」「1:05:12」（秒數四捨五入；不到一小時不補前面的 0）
    static func clock(seconds: Double) -> String {
        let s = wholeSeconds(seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

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

    /// 大卡：量的「402 大卡」；估的「約 340 大卡」（估的取到十位）
    static func kcal(_ kcal: Double, estimated: Bool) -> String {
        if estimated {
            let tens = wholeSeconds(kcal / 10)
            return "約 \(tens * 10) 大卡"
        }
        return "\(wholeSeconds(kcal)) 大卡"
    }
}

// MARK: - 照抄 WorkoutFacts（週、時段名、動詞、每公里語音；run_check.py 核對）

enum WatchRunFacts {

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

    /// 這週星期幾的索引：週一 0 … 週日 6
    static func weekdayIndex(_ date: Date) -> Int {
        let wd = calendar.component(.weekday, from: date)     // 週日 1、週一 2 … 週六 7
        return (wd + 5) % 7
    }

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
    /// 騎車 晨騎／午騎／午後騎車／夜騎／深夜騎車；登山一律「登山」
    static func timeOfDayName(_ sport: WatchSport, start: Date) -> String {
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
        }
    }

    /// 看板、目標的動詞：跑步「跑」、健走「走」、騎車「騎」、登山「爬」（「這週跑了」「這週還沒騎」）
    static func verb(_ sport: WatchSport) -> String {
        switch sport {
        case .run: return "跑"
        case .walk: return "走"
        case .bike: return "騎"
        case .hike: return "爬"
        }
    }

    // MARK: 跑步中「這一公里」（同 iPhone 的常數）

    /// 「這一公里」那一格看最近幾秒
    static let recentPaceSeconds: Double = 30
    /// 最近 30 秒不到這麼多公尺寫「—」（剛起跑、站著）
    static let recentPaceMinMeters: Double = 50
    /// 騎車「時速」看最近幾秒
    static let recentSpeedSeconds: Double = 10
    /// 最近 10 秒裡存下來的點至少要跨這麼多秒才算時速
    static let recentSpeedMinSeconds: Double = 3

    // MARK: 每公里語音（照抄 WorkoutProgress.swift）

    /// 語音唸的時間：「6 分 02 秒」「18 分 25 秒」「1 小時 05 分 12 秒」「45 秒」
    static func voiceDuration(_ seconds: Double) -> String {
        let s = WatchRunFormat.wholeSeconds(seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return "\(h) 小時 " + String(format: "%02d 分 %02d 秒", m, sec) }
        if m > 0 { return "\(m) 分 " + String(format: "%02d 秒", sec) }
        return "\(sec) 秒"
    }

    /// 時速一位小數（「22.3」）；算不出來「0.0」
    private static func voiceSpeed(_ kmh: Double) -> String {
        guard kmh.isFinite, kmh > 0 else { return "0.0" }
        return String(format: "%.1f", kmh)
    }

    /// 走滿第 k 公里（k＝kmTimes.count；kmTimes＝每走滿一整公里那一刻的移動時間，暫停不算）那一刻要講的一句。
    /// 跑、走、登山每公里：「1 公里，用時 6 分 02 秒。」「3 公里，這一公里 6 分 15 秒，總時間 18 分 25 秒，平均配速 6 分 08 秒。」
    /// 騎車只有 5 的倍數：「5 公里，總時間 13 分 38 秒，平均時速 22.0 公里。」
    /// 「10 公里，這 5 公里時速 22.0 公里，總時間 27 分 16 秒，平均時速 22.0 公里。」；其他公里回 nil（不講）
    static func voiceKm(sport: WatchSport, kmTimes: [Double]) -> String? {
        let k = kmTimes.count
        guard k >= 1, let total = kmTimes.last else { return nil }
        if sport == .bike {
            guard k % 5 == 0 else { return nil }
            let avg = total > 0 ? Double(k) / (total / 3600) : 0
            if k == 5 {
                return "5 公里，總時間 " + voiceDuration(total) + "，平均時速 " + voiceSpeed(avg) + " 公里。"
            }
            let leg = total - kmTimes[k - 6]
            let legSpeed = leg > 0 ? 5 / (leg / 3600) : 0
            return "\(k) 公里，這 5 公里時速 " + voiceSpeed(legSpeed) + " 公里，總時間 " + voiceDuration(total)
                + "，平均時速 " + voiceSpeed(avg) + " 公里。"
        }
        if k == 1 {
            return "1 公里，用時 " + voiceDuration(total) + "。"
        }
        let leg = total - kmTimes[k - 2]
        return "\(k) 公里，這一公里 " + voiceDuration(leg) + "，總時間 " + voiceDuration(total)
            + "，平均配速 " + voiceDuration(total / Double(k)) + "。"
    }

    /// 自動暫停、自動繼續那一刻講的
    static let voiceAutoPause = "自動暫停。"
    static let voiceAutoResume = "繼續。"
}

// MARK: - 照抄 WorkoutPaceLevel（配速五級：藍快、琥珀慢、灰差不多；run_check.py 核對）

enum WatchPaceLevel: Int, CaseIterable {
    case muchFaster = 0
    case faster
    case even
    case slower
    case muchSlower

    /// 跑、走、登山：配速（秒/公里）跟平均差多少。快 20 秒以上＝快很多、快 7～20 秒＝快、前後 7 秒內＝差不多、
    /// 慢 7～20 秒＝慢、慢 20 秒以上＝慢很多。例：平均 6'11"，第 1 公里 6'02"（快 9 秒）＝快、第 4 公里 6'20"＝慢
    static func forPace(seconds s: Double, average a: Double) -> WatchPaceLevel {
        let d = s - a
        if d <= -20 { return .muchFaster }
        if d <= -7 { return .faster }
        if d < 7 { return .even }
        if d < 20 { return .slower }
        return .muchSlower
    }

    /// 騎車：時速（公里/時）跟平均差多少；前後 1.5、4 公里/時當級距
    static func forSpeed(kmh v: Double, average a: Double) -> WatchPaceLevel {
        let d = v - a
        if d >= 4 { return .muchFaster }
        if d >= 1.5 { return .faster }
        if d > -1.5 { return .even }
        if d > -4 { return .slower }
        return .muchSlower
    }

    /// 深色那組（iPhone WorkoutPalette.pace(dark: true)）：很快 9EC5F4、快 3987E5、差不多 6B6A65、慢 C98500、很慢 F5C56B
    var darkHex: UInt32 {
        switch self {
        case .muchFaster: return 0x9EC5F4
        case .faster: return 0x3987E5
        case .even: return 0x6B6A65
        case .slower: return 0xC98500
        case .muchSlower: return 0xF5C56B
        }
    }
}

// MARK: - 一趟的紀錄（手錶 App 的 RunStash 存成檔：當機接回、存不進 Apple 健康時〔再存一次〕都靠它）

/// 一個路線點（CLLocation 換成這個：手錶小格不能 import CoreLocation）
struct WatchRunPoint: Codable, Equatable {
    var lat: Double
    var lon: Double
    /// 海拔（公尺）
    var alt: Double
    /// 定位的時間
    var at: Date
    /// 那一刻的移動秒數（暫停不算；路線小圖照它分到第幾公里上色）
    var moving: Double
    /// 水平誤差（公尺）
    var acc: Double
    /// 第幾段（每次暫停再繼續 +1；小圖段與段之間不連線）
    var seg: Int
}

/// 一次暫停（你按的，或手錶的自動暫停）
struct WatchRunPause: Codable, Equatable {
    var start: Date
    /// 還在暫停是 nil
    var end: Date? = nil
    /// 自動暫停（HKWorkoutEventType.motionPaused）
    var auto: Bool

    /// 暫停了幾秒（還在暫停的算 0）
    var seconds: Double {
        guard let end else { return 0 }
        return max(0, end.timeIntervalSince(start))
    }
}

/// 一趟（跑步中、跑完、沒存成都用這一份）
struct WatchRunRecord: Codable, Equatable, Identifiable {
    /// 手錶自己的編號（不是 Apple 健康的）
    var id: UUID
    var sport: WatchSport
    /// 3、2、1 數到 0 那一刻（＝startActivity／beginCollection 的時間）
    var start: Date
    /// 按住結束那一刻；還在跑是 nil
    var end: Date? = nil
    /// 移動秒數（HKLiveWorkoutBuilder.elapsedTime，扣掉暫停）
    var movingSeconds: Double = 0
    /// 距離（公尺；builder 的步行＋跑步距離，騎車用騎車距離——跟「健身」App、iPhone 帶進來的同一個數）
    var meters: Double = 0
    /// 動態大卡（手錶量的）
    var kcal: Double = 0
    var heartAvg: Double? = nil
    var heartMax: Double? = nil
    /// 每跑滿一整公里那一刻的移動秒數
    var kmTimes: [Double] = []
    var pauses: [WatchRunPause] = []
    /// 收下來的路線點（暫停中不收；誤差 50 公尺以上不收）
    var points: [WatchRunPoint] = []
    /// Apple 健康編號（存好才有）
    var workoutId: String? = nil
    /// 存進 Apple 健康的時間（nil＝還沒存好）
    var savedAt: Date? = nil
    /// 這一份最後寫的時間
    var updatedAt: Date

    /// 開始到結束（含暫停）的秒數；還在跑用 now
    func wallSeconds(now: Date) -> Double {
        max(0, (end ?? now).timeIntervalSince(start))
    }
}

// MARK: - 手錶自己的規則（sim_v4.py 同名函式）

/// 跑步中每次拿到距離的那一筆（HKLiveWorkoutBuilder 的累計距離；seconds＝那一刻的移動秒數）
struct WatchRunSample: Equatable {
    var seconds: Double
    var meters: Double
}

/// 路線小圖的一點（0～1；北在上）
struct WatchRunShapePoint: Equatable {
    var x: Double
    var y: Double
    var level: WatchPaceLevel
    var seg: Int
}

enum WatchRunMath {
    /// 一趟不到這麼多移動秒數：先問要不要存（HIG Workouts；iPhone 帶進來也丟掉不到 60 秒的，HealthSync.importWorkouts）
    static let shortSeconds: Double = 60
    /// 「這一公里」最近幾秒的距離樣本留多久
    static let sampleKeepSeconds: Double = 60
    /// 樣本最多留幾筆
    static let sampleMax = 200
    /// 路線小圖最多幾點
    static let shapeMaxPoints = 120
    /// 整條路線框起來不到這麼大（公尺）不畫小圖（原地繞圈、跑步機）
    static let shapeMinSpanMeters: Double = 50

    /// 走滿整公里那一刻：上一筆（prevMeters、prevSeconds）到這一筆（meters、seconds）之間跨過的每一個整公里，
    /// 照距離比例內插出那一刻的移動秒數（夾在兩筆之間）。done＝已經記了幾公里（kmTimes.count）。
    /// 例：上一筆 2,990 公尺 1,101 秒、這一筆 3,010 公尺 1,109 秒、done 2 → [1105]；一次跨兩公里回兩個
    static func kmCrossings(prevMeters: Double, prevSeconds: Double, meters: Double, seconds: Double,
                            done: Int) -> [Double] {
        guard prevMeters.isFinite, prevSeconds.isFinite, meters.isFinite, seconds.isFinite,
              meters > prevMeters, done >= 0 else { return [] }
        var out: [Double] = []
        var k = done + 1
        while Double(k) * 1000 <= meters && out.count < 100 {
            let target = Double(k) * 1000
            if target > prevMeters {
                let f = (target - prevMeters) / (meters - prevMeters)
                let t = prevSeconds + (seconds - prevSeconds) * f
                out.append(min(max(t, prevSeconds), max(seconds, prevSeconds)))
            } else {
                // 上一筆就已經過了（kmTimes 沒跟上，不該發生）：記上一筆的時間
                out.append(prevSeconds)
            }
            k += 1
        }
        return out
    }

    /// 只留最近 60 秒（移動秒數）、最多 200 筆
    static func pruned(_ samples: [WatchRunSample], nowSeconds: Double) -> [WatchRunSample] {
        var out = samples.filter { $0.seconds >= nowSeconds - sampleKeepSeconds }
        if out.count > sampleMax {
            out.removeFirst(out.count - sampleMax)
        }
        return out
    }

    /// 最近 window 秒（nowSeconds 往回）的距離與時間：最後一筆往回、還在窗內的最早那一筆到最後一筆。
    /// 最後一筆也太舊（站著、隧道）、不到兩筆、距離倒退回 nil
    static func recentWindow(_ samples: [WatchRunSample], nowSeconds: Double,
                             window: Double) -> (meters: Double, seconds: Double)? {
        guard let last = samples.last, nowSeconds.isFinite, last.seconds >= nowSeconds - window else { return nil }
        var first = last
        var i = samples.count - 1
        while i > 0 {
            let p = samples[i - 1]
            guard p.seconds >= nowSeconds - window else { break }
            first = p
            i -= 1
        }
        let dt = last.seconds - first.seconds
        let dm = last.meters - first.meters
        guard dt > 0, dm.isFinite, dm >= 0 else { return nil }
        return (meters: dm, seconds: dt)
    }

    /// 「這一公里」那一格（分鐘／公里）：最近 30 秒走不到 50 公尺回 nil（畫面寫「—」）；同 iPhone WorkoutFacts.recentPace 的規則
    static func recentPace(_ samples: [WatchRunSample], nowSeconds: Double) -> Double? {
        guard let w = recentWindow(samples, nowSeconds: nowSeconds, window: WatchRunFacts.recentPaceSeconds),
              w.meters >= WatchRunFacts.recentPaceMinMeters else { return nil }
        return (w.seconds / 60) / (w.meters / 1000)
    }

    /// 騎車「時速」（公里／時）：最近 10 秒；跨不到 3 秒回 nil（畫面寫「—」）
    static func recentSpeedKmh(_ samples: [WatchRunSample], nowSeconds: Double) -> Double? {
        guard let w = recentWindow(samples, nowSeconds: nowSeconds, window: WatchRunFacts.recentSpeedSeconds),
              w.seconds >= WatchRunFacts.recentSpeedMinSeconds else { return nil }
        return (w.meters / 1000) / (w.seconds / 3600)
    }

    /// 每公里的秒數（kmTimes 相鄰相減）：[365, 735, 1105] → [365, 370, 370]
    static func legSeconds(_ kmTimes: [Double]) -> [Double] {
        var out: [Double] = []
        var prev = 0.0
        for t in kmTimes {
            out.append(max(0, t - prev))
            prev = t
        }
        return out
    }

    /// 「暫停 2 次・1:10（都是自動）」：只算結束了的暫停（按住結束時還停著的那次不算，同 iPhone）；沒有回 nil。
    /// 後面的括號照 iPhone 成果頁（WorkoutCardData.autoPauseNote）：全部自動「（自動）」／「（都是自動）」、一部分「（自動 1 次）」
    static func pauseLine(_ pauses: [WatchRunPause]) -> String? {
        let done = pauses.filter { $0.end != nil }
        guard !done.isEmpty else { return nil }
        let total = done.reduce(0.0) { $0 + $1.seconds }
        let autoCount = done.filter { $0.auto }.count
        var note = ""
        if autoCount > 0 {
            if autoCount == done.count {
                note = done.count == 1 ? "（自動）" : "（都是自動）"
            } else {
                note = "（自動 \(autoCount) 次）"
            }
        }
        return "暫停 \(done.count) 次・" + WatchRunFormat.clock(seconds: total) + note
    }

    /// 路線小圖：等距投影（經度乘 cos 緯度）、框起來等比例縮進 0～1、置中、北在上；每一點照它那一刻的移動秒數分到第幾公里，
    /// 那一公里的配速（騎車用時速）跟整趟平均比上色（WatchPaceLevel）；最後不滿一公里那段 50 公尺以上才比，不然「差不多」。
    /// 超過 maxPoints 平均抽（最後一點一定留）。不到 2 點、整條框起來不到 50 公尺回空的（不畫）
    static func routeShape(_ points: [WatchRunPoint], kmTimes: [Double], sport: WatchSport,
                           movingSeconds: Double, meters: Double,
                           maxPoints: Int = shapeMaxPoints) -> [WatchRunShapePoint] {
        let pts = points.filter { $0.lat.isFinite && $0.lon.isFinite && abs($0.lat) <= 90 && abs($0.lon) <= 180 }
        guard pts.count >= 2, maxPoints >= 2 else { return [] }
        var minLat = pts[0].lat, maxLat = pts[0].lat, minLon = pts[0].lon, maxLon = pts[0].lon
        for p in pts {
            minLat = min(minLat, p.lat)
            maxLat = max(maxLat, p.lat)
            minLon = min(minLon, p.lon)
            maxLon = max(maxLon, p.lon)
        }
        let midLat = (minLat + maxLat) / 2
        let k = cos(midLat * .pi / 180)
        let w = (maxLon - minLon) * k
        let h = maxLat - minLat
        let span = max(w, h)
        // 1 度緯度約 111,195 公尺
        guard span * 111_195 >= shapeMinSpanMeters else { return [] }
        let offX = (1 - w / span) / 2
        let offY = (1 - h / span) / 2

        // 每一公里的等級
        let legs = legSeconds(kmTimes)
        let km = meters / 1000
        var levels: [WatchPaceLevel] = []
        let averagePace = km > 0 && movingSeconds > 0 ? movingSeconds / km : 0       // 秒／公里
        let averageSpeed = movingSeconds > 0 ? km / (movingSeconds / 3600) : 0       // 公里／時
        for leg in legs {
            levels.append(level(legMeters: 1000, legSeconds: leg, sport: sport,
                                averagePace: averagePace, averageSpeed: averageSpeed))
        }
        let tailMeters = meters - Double(kmTimes.count) * 1000
        let tailSeconds = movingSeconds - (kmTimes.last ?? 0)
        let tailLevel: WatchPaceLevel = tailMeters >= 50 && tailSeconds > 0
            ? level(legMeters: tailMeters, legSeconds: tailSeconds, sport: sport,
                    averagePace: averagePace, averageSpeed: averageSpeed)
            : .even

        // 平均抽點
        var picked: [WatchRunPoint] = []
        if pts.count <= maxPoints {
            picked = pts
        } else {
            let step = Double(pts.count - 1) / Double(maxPoints - 1)
            for i in 0..<maxPoints {
                let idx = min(pts.count - 1, Int((Double(i) * step).rounded()))
                picked.append(pts[idx])
            }
        }
        return picked.map { (p: WatchRunPoint) -> WatchRunShapePoint in
            let x = offX + (p.lon - minLon) * k / span
            let y = offY + (maxLat - p.lat) / span
            var i = 0
            while i < kmTimes.count && kmTimes[i] <= p.moving {
                i += 1
            }
            let lv = i < levels.count ? levels[i] : tailLevel
            return WatchRunShapePoint(x: x, y: y, level: lv, seg: p.seg)
        }
    }

    /// 一段（公尺、秒）跟整趟平均比的等級：跑走登山比配速（秒／公里），騎車比時速
    static func level(legMeters: Double, legSeconds: Double, sport: WatchSport,
                      averagePace: Double, averageSpeed: Double) -> WatchPaceLevel {
        guard legMeters > 0, legSeconds > 0 else { return .even }
        if sport == .bike {
            guard averageSpeed > 0 else { return .even }
            return WatchPaceLevel.forSpeed(kmh: (legMeters / 1000) / (legSeconds / 3600), average: averageSpeed)
        }
        guard averagePace > 0 else { return .even }
        return WatchPaceLevel.forPace(seconds: legSeconds / (legMeters / 1000), average: averagePace)
    }
}

// MARK: - 畫面上的字（sim_v4.py 同名函式；View 不自己拼）

/// 字的顏色（View 換成 WatchStyle 的色）
enum WatchRunTone: Equatable {
    case normal
    case green
    case amber
    /// 運動色（WatchSport.tint）
    case sport
}

/// 健康「存運動」的權限（只有寫的狀態查得到：HKHealthStore.authorizationStatus(for: .workoutType())）
enum WatchRunHealthAccess: Equatable {
    /// 還沒問過（第一次按開始先出說明卡）
    case unknown
    /// 沒給（.sharingDenied）：〔開始〕不能按
    case denied
    case allowed
}

/// 位置權限（CLLocationManager.authorizationStatus＋accuracyAuthorization）
enum WatchRunLocationAccess: Equatable {
    case unknown
    /// 沒給、被限制
    case denied
    /// 只給大約位置
    case reduced
    case full
}

/// ③ 跑步（judge §2.9）
struct WatchRunHome: Equatable {
    /// 「這週第 4 天・連續 6 週」（連續 0 週只寫前半）
    var header: String
    /// 「這週跑了」「這週騎了」
    var verbLine: String
    /// 「14.6」；從來沒收過 iPhone 的資料「—」
    var big: String
    /// 大字後面寫「公里」
    var showsUnit: Bool
    /// 「3 次・目標 20 公里」「這週還沒跑・目標 20 公里」「打開 iPhone 上的 LifeGood，就看得到這週的公里」
    var line3: String?
    /// 「還差 5.4 公里・剩 4 天」「已達標・多 0.6 公里」；沒設目標 nil
    var line4: String?
    var line4IsGreen: Bool
    /// 41mm：兩行併成一行「3 次・還差 5.4 公里」
    var compactLine: String?
    /// 週一到週日有沒有動（小風景條插旗；46mm 才畫）
    var flags: [Bool]
    /// 今天是第幾格（週一 0）
    var todayIndex: Int
    /// 這週主角（iPhone 算的；從來沒收過＝上一次用的、沒有就跑步）
    var sport: WatchSport
    /// 底部主鈕要開始的（上一次用的；沒有＝主角）
    var startSport: WatchSport
    /// 準備頁最下面「這週 9.4／20 公里」；從來沒收過 nil
    var prepWeekLine: String?

    // MARK: [v5] 數字（「這週」小柱、錶面小格用；home() 一起算好，View 不自己加減）

    /// 這週主角運動的公里（＝big 那個數）
    var km: Double = 0
    /// 每週目標（沒設 nil）
    var goalKm: Double? = nil
    /// 這週次數（主角運動）
    var runs: Int = 0
    /// 連續幾週（頁首那個數；0＝不寫）
    var streakWeeks: Int = 0
    /// 剩幾天（含今天）
    var daysLeft: Int = 0
    /// 收過 iPhone 的這週跑步（false＝大字「—」）
    var hasData: Bool = false
    /// 週一到週日每天的公里（7 個；主角運動；iPhone 的＋手錶自己加的）
    var dayKm: [Double] = []
    /// 手錶自己記、iPhone 還沒處理過、這週算進來的那幾趟（任何運動；「這週」清單補上去）
    var ownExtra: [WatchRunLogEntry] = []
}

/// 準備頁那一行（judge §2.10 五種狀態，一次只寫最要緊的一句）
struct WatchRunPrepLine: Equatable {
    var text: String
    var tone: WatchRunTone
    /// 〔開始〕能不能按（健康沒讓 LifeGood 存運動＝不能：跑完存不進去等於白跑）
    var canStart: Bool
    /// 按〔開始〕先出說明卡、再跳系統權限框（健康或位置還沒問過）
    var asksFirst: Bool
}

/// 跑步中頁首的狀態
enum WatchRunLiveState: Equatable {
    case running
    /// 手錶的自動暫停（HKWorkoutEventType.motionPaused）
    case autoPaused
    /// 你按的暫停（since＝按下去那一刻）
    case paused(since: Date)
    /// 當機重開、接回來的 3 秒
    case recovered
}

/// 跑步中數字頁（judge §2.11）
struct WatchRunLive: Equatable {
    /// 「晨跑」「晨跑・GPS 弱」「已自動暫停」「已暫停 0:42」「已接回」
    var header: String
    var headerTone: WatchRunTone
    /// 「21:05」
    var time: String
    /// 暫停中：時間停住變灰
    var timeIsDim: Bool
    /// 「3.42」
    var distance: String
    /// 「6'20"」（騎車「21.4」）；算不出來「—」
    var paceValue: String
    /// 「這一公里」（騎車「時速」）
    var paceLabel: String
    /// 「152」；量不到「—」
    var heart: String
}

/// 每跑滿一公里那 3 秒（judge §2.11「第 3 公里／6'10"／平均 6'08"」）
struct WatchRunKmFlash: Equatable {
    /// 「第 3 公里」
    var title: String
    /// 「6'10"」（騎車「22.0」）
    var big: String
    /// 大字下面那個字「這一公里」（騎車「這 5 公里時速」）
    var bigLabel: String
    /// 「平均 6'08"」（騎車「平均時速 21.5」）
    var line: String
    /// 要講的那一句（WatchRunFacts.voiceKm，跟 iPhone 一字不差）
    var voice: String
}

/// 跑完摘要（judge §2.12；亮點那兩行 v5）
struct WatchRunSummary: Equatable {
    /// 「已存好」／「還沒存進 Apple 健康」
    var head: String
    var saved: Bool
    /// 「晨跑」
    var title: String
    /// 「5.20」
    var big: String
    /// 「32:04・配速 6'10"」（騎車「1:02:10・時速 21.5」）
    var line: String
    /// 「平均 152・最高 171・340 大卡」（前面畫 ♥）；都沒有 nil
    var heartLine: String?
    /// 「每公里：6'05" 6'10" 6'10" 6'20" 6'06"」（騎車、不到一公里 nil）
    var splitsLine: String?
    /// 「暫停 2 次・1:10（都是自動）」；沒暫停 nil
    var pauseLine: String?
    /// 「已存進 Apple 健康・iPhone 健康頁會自己帶進來」／「這一趟先留在手錶上，存好才刪」
    var note: String
}

enum WatchRunText {
    // MARK: 固定的字

    static let permissionCard = "LifeGood 要用健康（存跑步、讀心率）和位置（畫路線）。位置請選「精確位置」，只給大約位置的話路線會差一兩公里、畫不出地圖"
    static let permissionOK = "好"
    static let healthDenied = "健康沒有讓 LifeGood 存運動：打開 iPhone「健康」App › 共享 › App › LifeGood，把「體能訓練」打開"
    static let noLocation = "沒有位置權限：這一趟只有距離、沒有地圖"
    static let reducedLocation = "只有大約位置：這一趟不會有地圖"
    static let lowPower = "低電量模式：路線可能比較粗"
    static let gpsFound = "● GPS 找到了"
    static let gpsSearching = "● 找 GPS 中…可以先開始"
    static let askFirst = "第一次開始會先問健康和位置的權限"
    static let startButton = "開始"
    static let countdownHint = "點一下跳過"
    static let noWeek = "打開 iPhone 上的 LifeGood，就看得到這週的公里"
    static let unsavedRow = "有 1 趟還沒存進 Apple 健康"
    static let pauseTitle = "暫停"
    static let resumeTitle = "繼續"
    static let endTitle = "按住結束"
    static let voiceTitle = "語音"
    static let hapticTitle = "震動"
    static let onText = "開"
    static let offText = "關"
    static let shortAsk = "不到 1 分鐘，要存嗎？"
    static let saveShortTitle = "存下來"
    static let discardShortTitle = "丟掉"
    static let savingText = "存進 Apple 健康中…"
    static let doneTitle = "完成"
    static let retryTitle = "再存一次"
    static let discardSavedTitle = "不存這一趟"
    static let discardSavedAsk = "不存這一趟？Apple 健康裡這一趟會刪掉"
    static let discardSavedYes = "刪掉"
    static let cancelTitle = "取消"
    static let routeHidden = "路線已存進 Apple 健康"
    static let savedHead = "已存好"
    static let unsavedHead = "還沒存進 Apple 健康"
    static let savedNote = "已存進 Apple 健康・iPhone 健康頁會自己帶進來"
    static let unsavedNote = "這一趟先留在手錶上，存好才刪"
    static let recoveredHeader = "已接回"
    static let autoPausedHeader = "已自動暫停"
    static let pausedHeader = "已暫停 "
    static let gpsWeakSuffix = "・GPS 弱"
    static let paceLabel = "這一公里"
    static let speedLabel = "時速"
    static let heartLabel = "心率"
    static let kmUnit = "公里"
    /// 手錶設定（judge §2.15）
    static let voiceRow = "每公里講一句（跑步）"
    static let hapticRow = "每公里震一下（跑步）"
    static let voiceReady = "語音：中文（台灣）✓"
    static let voiceMissing = "這支手錶沒有台灣中文語音，每公里只震動"

    /// 每公里那一頁、「已接回」留幾秒
    static let flashSeconds: Double = 3
    /// 按住結束要按多久
    static let holdSeconds: Double = 1
    /// 跑完 15 分鐘內打開 App 還是摘要（judge §2.0）
    static let summaryKeepSeconds: Double = 15 * 60

    // MARK: ③ 跑步

    /// 目標「20」「12.5」
    static func goalText(_ km: Double) -> String {
        km == km.rounded() ? String(format: "%.0f", km) : String(format: "%.1f", km)
    }

    /// ③ 這週：iPhone 的 runWeek（這週的；是上週的就從 0 算、連續週數接著算）＋手錶自己記、存好了、seen 裡沒有、
    /// 這週開始、至少 60 秒的那幾趟——跟主角同一種運動才加公里與次數；任何一種都算「這週動過了」（連續週數 +1）。
    /// 例：iPhone 9.4 公里 2 次、手錶 06:05 晨跑 5.20 公里（還沒帶進 iPhone）→ 14.6、3 次；帶進來後 seen 有它 → 照 iPhone 的 14.6
    static func home(package: WatchPackage?, own: [WatchRunLogEntry], now: Date,
                     lastSport: WatchSport?) -> WatchRunHome {
        let week = WatchRunFacts.week(of: now)
        let todayIndex = min(max(WatchRunFacts.weekdayIndex(now), 0), 6)
        let daysLeft = 7 - todayIndex
        let dayHead = "這週第 \(todayIndex + 1) 天"
        guard let w = package?.runWeek, let hero = WatchSport(rawValue: w.sport) else {
            let sport = lastSport ?? .run
            var empty = WatchRunHome(header: dayHead, verbLine: "這週" + WatchRunFacts.verb(sport) + "了",
                                     big: "—", showsUnit: false, line3: noWeek, line4: nil, line4IsGreen: false,
                                     compactLine: noWeek, flags: Array(repeating: false, count: 7), todayIndex: todayIndex,
                                     sport: sport, startSport: sport, prepWeekLine: nil)
            // [v5]
            empty.daysLeft = daysLeft
            empty.dayKm = Array(repeating: 0, count: 7)
            return empty
        }
        let sameWeek = abs(w.weekStart.timeIntervalSince(week.start)) < 1
        var km = sameWeek ? max(0, w.doneKm) : 0
        var runs = sameWeek ? max(0, w.runs) : 0
        var flags = Array(repeating: false, count: 7)
        if sameWeek && w.dayKm.count == 7 {
            flags = w.dayKm.map { $0 > 0 }
        }
        // [v5] 每天公里（iPhone 的這週那一份＋下面手錶自己加的）
        var dayKm = Array(repeating: 0.0, count: 7)
        if sameWeek && w.dayKm.count == 7 {
            dayKm = w.dayKm.map { $0.isFinite ? max(0, $0) : 0 }
        }
        var extra: [WatchRunLogEntry] = []
        let counted = sameWeek ? w.weekCounted : false
        var streak = 0
        if sameWeek {
            streak = max(0, w.streakWeeks)
        } else if let lastWeek = WatchRunFacts.calendar.date(byAdding: .day, value: -7, to: week.start),
                  abs(w.weekStart.timeIntervalSince(lastWeek)) < 1, w.weekCounted {
            streak = max(0, w.streakWeeks)
        }
        let seen = Set(w.seen)
        var used = Set<String>()
        var movedThisWeek = false
        for e in own {
            guard e.saved, let id = e.workoutId, !seen.contains(id), !used.contains(id) else { continue }
            guard e.start >= week.start, e.start < week.end else { continue }
            guard e.end.timeIntervalSince(e.start) >= WatchRunMath.shortSeconds else { continue }
            used.insert(id)
            movedThisWeek = true
            extra.append(e)
            guard e.sport == hero.rawValue else { continue }
            km += max(0, e.meters) / 1000
            runs += 1
            let i = WatchRunFacts.weekdayIndex(e.start)
            if i >= 0 && i < 7 {
                flags[i] = true
                dayKm[i] += max(0, e.meters) / 1000
            }
        }
        if movedThisWeek && !counted {
            streak += 1
        }
        let header = streak > 0 ? dayHead + "・連續 \(streak) 週" : dayHead
        let verb = WatchRunFacts.verb(hero)
        let goal: Double? = (w.goalKm ?? 0) > 0 ? w.goalKm : nil
        var line3: String
        var line4: String? = nil
        var green = false
        var compact: String
        if runs == 0 {
            line3 = "這週還沒" + verb
            compact = line3
        } else {
            line3 = "\(runs) 次"
            compact = line3
        }
        var prepWeek = "這週 " + WatchRunFormat.kmNumber(km) + " 公里"
        if let g = goal {
            line3 += "・目標 " + goalText(g) + " 公里"
            prepWeek = "這週 " + WatchRunFormat.kmNumber(km) + "／" + goalText(g) + " 公里"
            if km >= g - 0.05 {
                green = true
                line4 = km - g >= 0.05 ? "已達標・多 " + WatchRunFormat.kmNumber(km - g) + " 公里" : "已達標"
                if runs > 0 { compact += "・已達標" }
            } else {
                line4 = "還差 " + WatchRunFormat.kmNumber(g - km) + " 公里・剩 \(daysLeft) 天"
                if runs > 0 { compact += "・還差 " + WatchRunFormat.kmNumber(g - km) + " 公里" }
            }
        }
        var out = WatchRunHome(header: header, verbLine: "這週" + verb + "了", big: WatchRunFormat.kmNumber(km),
                               showsUnit: true, line3: line3, line4: line4, line4IsGreen: green, compactLine: compact,
                               flags: flags, todayIndex: todayIndex, sport: hero, startSport: lastSport ?? hero,
                               prepWeekLine: prepWeek)
        // [v5] 數字（「這週」小柱、錶面小格）
        out.km = km
        out.goalKm = goal
        out.runs = runs
        out.streakWeeks = streak
        out.daysLeft = daysLeft
        out.hasData = true
        out.dayKm = dayKm
        out.ownExtra = extra
        return out
    }

    // MARK: 準備頁

    /// 一次只寫最要緊的一句：健康沒給（擋〔開始〕）→ 還沒問過（按開始先出說明卡）→ 沒有位置 → 只有大約位置 →
    /// 低電量模式 → GPS 找到了／找 GPS 中
    static func prepLine(health: WatchRunHealthAccess, location: WatchRunLocationAccess, lowPower: Bool,
                         gpsFound: Bool) -> WatchRunPrepLine {
        if health == .denied {
            return WatchRunPrepLine(text: healthDenied, tone: .amber, canStart: false, asksFirst: false)
        }
        if health == .unknown || location == .unknown {
            return WatchRunPrepLine(text: askFirst, tone: .normal, canStart: true, asksFirst: true)
        }
        if location == .denied {
            return WatchRunPrepLine(text: noLocation, tone: .amber, canStart: true, asksFirst: false)
        }
        if location == .reduced {
            return WatchRunPrepLine(text: reducedLocation, tone: .amber, canStart: true, asksFirst: false)
        }
        if lowPower {
            return WatchRunPrepLine(text: Self.lowPower, tone: .amber, canStart: true, asksFirst: false)
        }
        if gpsFound {
            return WatchRunPrepLine(text: Self.gpsFound, tone: .green, canStart: true, asksFirst: false)
        }
        return WatchRunPrepLine(text: gpsSearching, tone: .amber, canStart: true, asksFirst: false)
    }

    // MARK: 跑步中

    /// 四個數字＋頁首。recentPace（分鐘／公里）、recentSpeed（公里／時）由 WatchRunMath 算好；暫停中「這一公里」寫「—」
    static func live(sport: WatchSport, start: Date, movingSeconds: Double, meters: Double,
                     recentPace: Double?, recentSpeed: Double?, heartRate: Double?,
                     state: WatchRunLiveState, gpsWeak: Bool, now: Date) -> WatchRunLive {
        let name = WatchRunFacts.timeOfDayName(sport, start: start)
        var header = name
        var tone = WatchRunTone.sport
        var dim = false
        var moving = true
        switch state {
        case .running:
            if gpsWeak { header = name + gpsWeakSuffix }
        case .autoPaused:
            header = autoPausedHeader
            tone = .amber
            dim = true
            moving = false
        case .paused(let since):
            header = pausedHeader + WatchRunFormat.clock(seconds: now.timeIntervalSince(since))
            tone = .amber
            dim = true
            moving = false
        case .recovered:
            header = recoveredHeader
            tone = .green
        }
        let paceValue: String
        let paceLabel: String
        if sport == .bike {
            paceLabel = speedLabel
            if moving, let v = recentSpeed, v.isFinite, v > 0 {
                paceValue = WatchRunFormat.speedNumber(v)
            } else {
                paceValue = "—"
            }
        } else {
            paceLabel = Self.paceLabel
            paceValue = moving ? WatchRunFormat.pace(recentPace) : "—"
        }
        var heart = "—"
        if let hr = heartRate, hr.isFinite, hr > 0, hr < 400 {
            heart = "\(WatchRunFormat.wholeSeconds(hr))"
        }
        return WatchRunLive(header: header, headerTone: tone,
                            time: WatchRunFormat.clock(seconds: movingSeconds), timeIsDim: dim,
                            distance: WatchRunFormat.preciseKmNumber(meters / 1000, sport: sport),
                            paceValue: paceValue, paceLabel: paceLabel, heart: heart)
    }

    /// 走滿第 kmTimes.count 公里那一刻的那一頁＋那一句。騎車只有 5 的倍數有（跟語音同一個條件），其他回 nil（不震、不講、不換頁）
    static func kmFlash(sport: WatchSport, kmTimes: [Double]) -> WatchRunKmFlash? {
        guard let voice = WatchRunFacts.voiceKm(sport: sport, kmTimes: kmTimes),
              let total = kmTimes.last else { return nil }
        let k = kmTimes.count
        if sport == .bike {
            let legStart = k >= 5 ? (k == 5 ? 0 : kmTimes[k - 6]) : 0
            let leg = total - legStart
            let legSpeed = leg > 0 ? 5 / (leg / 3600) : 0
            let avg = total > 0 ? Double(k) / (total / 3600) : 0
            return WatchRunKmFlash(title: "第 \(k) 公里", big: WatchRunFormat.speedNumber(legSpeed),
                                   bigLabel: "這 5 公里時速", line: "平均時速 " + WatchRunFormat.speedNumber(avg),
                                   voice: voice)
        }
        let leg = k >= 2 ? total - kmTimes[k - 2] : total
        return WatchRunKmFlash(title: "第 \(k) 公里", big: WatchRunFormat.pace(leg / 60), bigLabel: paceLabel,
                               line: "平均 " + WatchRunFormat.pace(total / Double(k) / 60), voice: voice)
    }

    // MARK: 跑完

    /// 摘要的字（saved＝已經存進 Apple 健康）
    static func summary(_ r: WatchRunRecord, saved: Bool) -> WatchRunSummary {
        let km = r.meters / 1000
        let minutes = r.movingSeconds / 60
        var line = WatchRunFormat.clock(seconds: r.movingSeconds)
        if r.sport == .bike {
            if let v = WatchRunFormat.speedKmh(km: km, minutes: minutes) {
                line += "・時速 " + WatchRunFormat.speedNumber(v)
            }
        } else if km > 0 && minutes > 0 {
            line += "・配速 " + WatchRunFormat.pace(km: km, minutes: minutes)
        }
        var heartParts: [String] = []
        if let a = r.heartAvg, a.isFinite, a > 0 {
            heartParts.append("平均 \(WatchRunFormat.wholeSeconds(a))")
        }
        if let m = r.heartMax, m.isFinite, m > 0 {
            heartParts.append("最高 \(WatchRunFormat.wholeSeconds(m))")
        }
        if r.kcal.isFinite && r.kcal >= 1 {
            heartParts.append(WatchRunFormat.kcal(r.kcal, estimated: false))
        }
        var splits: String? = nil
        let legs = WatchRunMath.legSeconds(r.kmTimes)
        if r.sport != .bike && !legs.isEmpty {
            let shown = legs.prefix(10).map { WatchRunFormat.pace($0 / 60) }.joined(separator: " ")
            splits = "每公里：" + shown + (legs.count > 10 ? " …" : "")
        }
        return WatchRunSummary(head: saved ? savedHead : unsavedHead, saved: saved,
                               title: WatchRunFacts.timeOfDayName(r.sport, start: r.start),
                               big: WatchRunFormat.preciseKmNumber(km, sport: r.sport), line: line,
                               heartLine: heartParts.isEmpty ? nil : heartParts.joined(separator: "・"),
                               splitsLine: splits, pauseLine: WatchRunMath.pauseLine(r.pauses),
                               note: saved ? savedNote : unsavedNote)
    }

    /// 這一趟夠不夠 1 分鐘（移動時間）：不夠先問要不要存
    static func isShort(_ r: WatchRunRecord) -> Bool {
        r.movingSeconds < WatchRunMath.shortSeconds
    }
}

// MARK: - 手錶記過的每一趟（手錶 App Group 的 UserDefaults；③ 這週、v5 錶面小格都讀）

/// 手錶記過的一趟（只有編號、運動、時間、公里；沒有路線、心率）
struct WatchRunLogEntry: Codable, Equatable, Identifiable {
    /// ＝WatchRunRecord.id
    var id: UUID
    /// Apple 健康編號（存好才有）
    var workoutId: String?
    /// WatchSport.rawValue
    var sport: String
    var start: Date
    var end: Date
    var movingSeconds: Double
    var meters: Double
    /// 存進 Apple 健康了（沒存成的不算進 ③：iPhone 永遠帶不進來）
    var saved: Bool
    /// [v5] 平均、最高心率（「那一趟」♥ 那一行；只在手錶上，不送 iPhone）
    var heartAvg: Double? = nil
    var heartMax: Double? = nil
    /// [v5] 路線形狀（0～1000、最多 40 點；「那一趟」小圖。WatchRunWeekText.compactShape 從摘要那份小圖抽）
    var shape: [WatchRunShapeXY]? = nil
}

enum WatchRunLog {
    static let key = "watch_run_log_v1"
    /// 留幾天、最多幾趟
    static let keepDays: Double = 14
    static let maxEntries = 30

    /// 全部（新到舊）；沒有、解不開回空的
    static func all() -> [WatchRunLogEntry] {
        guard let data = WidgetShared.defaults?.data(forKey: key),
              let list = try? JSONDecoder().decode([WatchRunLogEntry].self, from: data) else { return [] }
        return list
    }

    /// 加一趟、或換掉同一個 id 的那一趟；順手只留 14 天、30 趟
    static func upsert(_ entry: WatchRunLogEntry, now: Date) {
        var list = all().filter { $0.id != entry.id }
        list.append(entry)
        save(pruned(list, now: now))
    }

    /// 拿掉一趟（〔不存這一趟〕）
    static func remove(_ id: UUID) {
        save(all().filter { $0.id != id })
    }

    /// 新到舊、14 天內、最多 30 趟
    static func pruned(_ list: [WatchRunLogEntry], now: Date) -> [WatchRunLogEntry] {
        let cut = now.addingTimeInterval(-keepDays * 86_400)
        let kept = list.filter { $0.start >= cut }.sorted { $0.start > $1.start }
        return Array(kept.prefix(maxEntries))
    }

    private static func save(_ list: [WatchRunLogEntry]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        WidgetShared.defaults?.set(data, forKey: key)
    }
}

/// 跑步的設定（手錶 App Group；控制頁的兩顆小開關＝這一趟有效、也記成下次的預設；手錶設定頁同一組）
enum WatchRunPrefs {
    static let voiceKey = "watch_run_voice_on"
    static let hapticKey = "watch_run_haptic_on"
    static let lastSportKey = "watch_run_last_sport"

    /// 每公里講一句（沒設定過＝開）
    static var voiceOn: Bool {
        guard let d = WidgetShared.defaults, d.object(forKey: voiceKey) != nil else { return true }
        return d.bool(forKey: voiceKey)
    }

    static func setVoiceOn(_ on: Bool) {
        WidgetShared.defaults?.set(on, forKey: voiceKey)
    }

    /// 每公里震一下（沒設定過＝開）
    static var hapticOn: Bool {
        guard let d = WidgetShared.defaults, d.object(forKey: hapticKey) != nil else { return true }
        return d.bool(forKey: hapticKey)
    }

    static func setHapticOn(_ on: Bool) {
        WidgetShared.defaults?.set(on, forKey: hapticKey)
    }

    /// 上一次用的運動（③ 底部主鈕「開始騎車」）；沒用過 nil
    static var lastSport: WatchSport? {
        guard let raw = WidgetShared.defaults?.string(forKey: lastSportKey) else { return nil }
        return WatchSport(rawValue: raw)
    }

    static func setLastSport(_ sport: WatchSport) {
        WidgetShared.defaults?.set(sport.rawValue, forKey: lastSportKey)
    }
}
