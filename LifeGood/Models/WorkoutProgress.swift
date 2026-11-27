import Foundation
import CoreLocation

// MARK: - 教練與進步（v25.557，健康 v7 前半；health/judge.md §3.10、§4.1 第 11 列、§4.3、§5.1、§6 v7；build/v7/brief.md §2）
//
// 主控檔（只屬於 App target）：v7 各組共用的純函式與值型別都在這裡，畫面、記錄器只讀、不另寫第二套。
// 每一支都在 health/build/v7/sim_v7.py 逐行寫過一份、驗過（59/59）；改常數或順序要先改模擬再改這裡。
//
// • 自動暫停 RunAutoPause：GPS 速度＋誤差為主——低於門檻（跑 0.5、走／登山 0.4、騎 1.5 公尺/秒）的好定位連續 8 秒（至少 6 筆）
//   就暫停；超過門檻兩倍連續 3 筆、而且離停下來的地方 10 公尺以上（或連續 6 筆）就繼續，繼續的時間從開始動的那一筆算。
//   手機的動作偵測（RunMotion）只輔助：說你還在走、跑時要等 16 秒（慢走不誤停）；系統給不出速度時（speed < 0）才看它。
//   誤差超過 20 公尺、收不到定位（隧道）都不暫停：看不準就不停，不會把在跑的時間停掉。
// • 每公里語音 voiceKm：「3 公里，這一公里 6 分 15 秒，總時間 18 分 25 秒，平均配速 6 分 08 秒。」騎車每 5 公里講時速。
// • 個人紀錄：bestEfforts（移動時間軸上找最快的 1／5／10 公里、半馬：暫停的空隙不算距離也不算時間，同 RouteMath.kmSplits）、
//   personalRecords（健康頁「個人紀錄」）、recordMarks（存檔時跟以前比一次：破紀錄的記號存在 WorkoutSession.highlights）。
// • 同一條路 sameRoute／routeMatch：起點、終點都在 150 公尺內、距離差 10% 內、走到 25%／50%／75% 那幾點也都靠得近（方向相同）。
//   「河濱老路線・第 12 次・比上次快 42 秒」：名字從你取的名字來（去掉「晨跑」這種字尾＋「老路線」），比上次照這一趟的距離換算。
// • 請假週、連續週數 streak（WorkoutFacts.swift）與月曆 monthGrid：有運動的週 +1；沒運動但請假：不加、不斷；都沒有：停。

// MARK: - 自動暫停

/// [v25.557] 手機的動作偵測（CMMotionActivity）最近說你在做什麼。RunTracker 把 CMMotionActivity 換成這個：
/// 信心低、在車上、看不出來＝unknown；靜止＝still；走路或跑步＝onFoot；騎車＝cycling
enum RunMotion: Equatable {
    case unknown
    case still
    case onFoot
    case cycling
}

/// [v25.557] 自動暫停的判斷（judge §4.1 第 11 列；build/v7/sim_v7.py RunAutoPause 逐行）。
/// RunTracker 每收到一筆（過了 50 公尺、30 秒、亂序那三道關的）定位叫一次 observe；跑步中、自動暫停中才叫（手動暫停中不叫）。
/// 開始、手動暫停、手動繼續、自動繼續、完成、放棄都 reset（自動繼續時 observe 自己 reset 該清的）。
struct RunAutoPause: Equatable {
    /// 這一筆之後要做什麼
    enum Event: Equatable {
        case none
        /// 自動暫停：從這一筆定位的時間起算（成批送來時是那一筆的時間，不是收到的時間）
        case pause(Date)
        /// 自動繼續：從開始動的那一筆定位的時間起算（那幾秒算移動時間）
        case resume(Date)
    }

    /// 低於門檻連續這麼久（定位上的時間）就暫停（judge 8 秒；GPS 速度降下來要 1～2 秒，實際約 9～10 秒）
    static let stillSeconds: TimeInterval = 8
    /// 動作偵測說你還在走、跑（onFoot）：等久一點（慢走時 GPS 速度偶爾掉到門檻下，不誤停）
    static let stillSecondsOnFoot: TimeInterval = 16
    /// 而且這段時間至少收到這麼多筆（定位斷斷續續不算）
    static let stillMinFixes = 6
    /// 兩筆定位隔超過這麼久：重新數
    static let gapSeconds: TimeInterval = 3
    /// 超過門檻兩倍連續幾筆、而且離停下來的地方 resumeMeters 以上就繼續
    static let resumeFixes = 3
    /// 或連續這麼多筆（誤差大、看不出離多遠時）
    static let resumeFixesAnyway = 6
    static let resumeMeters: Double = 10
    /// 這一趟走滿這麼遠之後才會自動暫停（剛按開始站著等紅燈不算）
    static let minDistanceMeters: Double = 20
    /// 誤差在這個以內的定位才拿來判斷停下來（同 RunTracker.goodAccuracy）
    static let goodAccuracy: Double = 20

    /// 停下來的門檻（公尺／秒）：RunSport.autoPauseSpeed
    let stopSpeed: Double
    /// 跑、走、登山（看動作偵測的「走路、跑步」）；騎車是 false（看「騎車」）
    let onFoot: Bool
    /// 現在是不是自動暫停中（RunTracker.autoPaused 跟著它）
    private(set) var paused = false
    private var stillSince: Date?
    private var stillCount = 0
    private var moveSince: Date?
    private var moveCount = 0
    private var lastAt: Date?
    private var anchorLat: Double?
    private var anchorLon: Double?

    init(stopSpeed: Double, onFoot: Bool) {
        self.stopSpeed = stopSpeed
        self.onFoot = onFoot
    }

    /// 動起來的門檻：停下來門檻的兩倍
    var resumeSpeed: Double { stopSpeed * 2 }

    /// 全部清掉（開始、手動暫停、手動繼續、完成、放棄）
    mutating func reset() {
        paused = false
        stillSince = nil
        stillCount = 0
        moveSince = nil
        moveCount = 0
        lastAt = nil
        anchorLat = nil
        anchorLon = nil
    }

    /// 一筆定位。speed：nil＝這一筆沒有速度（CLLocation.speed < 0）；accuracy：水平誤差（公尺）；
    /// eligible：跑步中、這一趟走滿 20 公尺（暫停中不看）；motion：動作偵測最近說的（沒有動作偵測就 unknown）
    mutating func observe(t: Date, speed: Double?, accuracy: Double, lat: Double, lon: Double,
                          eligible: Bool, motion: RunMotion) -> Event {
        let gap = lastAt.map { t.timeIntervalSince($0) > Self.gapSeconds } ?? false
        lastAt = t
        if gap {
            stillSince = nil
            stillCount = 0
            moveSince = nil
            moveCount = 0
        }
        if paused {
            return observePaused(t: t, speed: speed, accuracy: accuracy, lat: lat, lon: lon, motion: motion)
        }
        let slow: Bool
        if let v = speed {
            slow = v < stopSpeed
        } else {
            slow = motion == .still
        }
        guard eligible, accuracy <= Self.goodAccuracy, slow else {
            stillSince = nil
            stillCount = 0
            return .none
        }
        if stillSince == nil {
            stillSince = t
            stillCount = 0
        }
        stillCount += 1
        let need = (onFoot && motion == .onFoot) ? Self.stillSecondsOnFoot : Self.stillSeconds
        guard let since = stillSince, t.timeIntervalSince(since) >= need, stillCount >= Self.stillMinFixes else {
            return .none
        }
        paused = true
        anchorLat = lat
        anchorLon = lon
        stillSince = nil
        stillCount = 0
        moveSince = nil
        moveCount = 0
        return .pause(t)
    }

    /// 自動暫停中：動起來了沒
    private mutating func observePaused(t: Date, speed: Double?, accuracy: Double, lat: Double, lon: Double,
                                        motion: RunMotion) -> Event {
        let going: RunMotion = onFoot ? .onFoot : .cycling
        let moving: Bool
        if let v = speed {
            moving = v >= resumeSpeed
        } else {
            moving = motion == going
        }
        guard moving else {
            moveSince = nil
            moveCount = 0
            return .none
        }
        if moveSince == nil {
            moveSince = t
            moveCount = 0
        }
        moveCount += 1
        var far = false
        if let la = anchorLat, let lo = anchorLon, accuracy <= Self.goodAccuracy {
            far = WorkoutFacts.haversineMeters(lat, lon, la, lo) >= Self.resumeMeters
        }
        guard (moveCount >= Self.resumeFixes && far) || moveCount >= Self.resumeFixesAnyway,
              let from = moveSince else { return .none }
        paused = false
        stillSince = nil
        stillCount = 0
        moveSince = nil
        moveCount = 0
        anchorLat = nil
        anchorLon = nil
        return .resume(from)
    }
}

// MARK: - 距離（球面；個人紀錄、同一條路、自動暫停共用，sim 的 dist 同一個公式）

extension WorkoutFacts {

    /// 兩點的距離（公尺；haversine、地球半徑 6,371,008.8 公尺）。不建 CLLocation（掃全部路線時快很多）
    static func haversineMeters(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6_371_008.8
        let la1 = lat1 * .pi / 180
        let la2 = lat2 * .pi / 180
        let dLa = la2 - la1
        let dLo = (lon2 - lon1) * .pi / 180
        let h = sin(dLa / 2) * sin(dLa / 2) + cos(la1) * cos(la2) * sin(dLo / 2) * sin(dLo / 2)
        let d = 2 * r * asin(min(1, max(0, h).squareRoot()))
        return d.isFinite ? d : 0
    }
}

// MARK: - 每公里語音（judge §6 v7）

extension WorkoutFacts {

    /// 語音唸的時間：「6 分 02 秒」「18 分 25 秒」「1 小時 05 分 12 秒」「45 秒」
    static func voiceDuration(_ seconds: Double) -> String {
        let s = WorkoutFormat.wholeSeconds(seconds)
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

    /// 走滿第 k 公里（k＝kmTimes.count；kmTimes＝RunTracker.kmTimes，每走滿一整公里那一刻的移動時間，暫停不算）那一刻要講的一句。
    /// 跑、走、登山每公里：「1 公里，用時 6 分 02 秒。」「3 公里，這一公里 6 分 15 秒，總時間 18 分 25 秒，平均配速 6 分 08 秒。」
    /// 騎車只有 5 的倍數：「5 公里，總時間 13 分 38 秒，平均時速 22.0 公里。」
    /// 「10 公里，這 5 公里時速 22.0 公里，總時間 27 分 16 秒，平均時速 22.0 公里。」；其他公里回 nil（不講）
    static func voiceKm(sport: WorkoutSport, kmTimes: [Double]) -> String? {
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

// MARK: - 個人紀錄（judge §3.10：最快 1 公里、最快 5 公里、最長…；從整趟裡找最快的那一段、暫停不算）

/// [v25.557] 健康頁「個人紀錄」的一列是哪一種。rawValue 存在 WorkoutRecordMark.kind（上線後不能改名）
enum WorkoutRecordKind: String, CaseIterable {
    case fastest1k
    case fastest5k
    case fastest10k
    case fastestHalf
    case longestRun
    case longestBike
    case longestWalk
    case longestHike

    /// 「最快 1 公里」「最快 5 公里」「最快 10 公里」「最快半馬」「最長」「騎車最長」「健走最長」「登山最長」
    var title: String {
        switch self {
        case .fastest1k: return "最快 1 公里"
        case .fastest5k: return "最快 5 公里"
        case .fastest10k: return "最快 10 公里"
        case .fastestHalf: return "最快半馬"
        case .longestRun: return "最長"
        case .longestBike: return "騎車最長"
        case .longestWalk: return "健走最長"
        case .longestHike: return "登山最長"
        }
    }

    /// 最快幾公里的那段距離（公尺）；最長是 nil
    var effortMeters: Double? {
        switch self {
        case .fastest1k: return 1000
        case .fastest5k: return 5000
        case .fastest10k: return 10_000
        case .fastestHalf: return 21_097.5
        case .longestRun, .longestBike, .longestWalk, .longestHike: return nil
        }
    }

    /// 哪一種運動的紀錄
    var sport: WorkoutSport {
        switch self {
        case .fastest1k, .fastest5k, .fastest10k, .fastestHalf, .longestRun: return .run
        case .longestBike: return .bike
        case .longestWalk: return .walk
        case .longestHike: return .hike
        }
    }

    /// 最快幾公里：值越小越好；最長：越大越好
    var smallerIsBetter: Bool { effortMeters != nil }
}

/// [v25.557] 健康頁「個人紀錄」的一列：「最快 1 公里　5'41"　9/28 ›」（點了打開那一趟）
struct WorkoutRecord: Identifiable, Equatable {
    let kind: WorkoutRecordKind
    /// 最快幾公里：秒；最長：公里
    let value: Double
    let sessionId: UUID
    let date: Date

    var id: String { kind.rawValue }
    /// 「最快 1 公里」
    var label: String { kind.title }
    /// 「5'41"」「29:58」「10.2 公里」
    var valueText: String { WorkoutFacts.recordValueText(kind, value: value) }
    /// 「9/28」
    var dateText: String { WorkoutFormat.monthDay(date) }
}

extension WorkoutFacts {

    /// 最快幾公里找哪幾段（公尺）：1、5、10 公里、半馬
    static let effortMeters: [Double] = [1000, 5000, 10_000, 21_097.5]
    /// 兩點之間快過這個（公尺／秒）當成 GPS 跳點：那一小段不算距離也不算時間
    static let effortMaxPairSpeed: Double = 12
    /// 一段平均快過這個（公尺／秒；1 公里 2'23"）不收（資料壞掉的假紀錄）
    static let effortMaxAverageSpeed: Double = 7
    /// 個人紀錄卡最下面那一行灰字
    static let recordFootnote = "最快幾公里是從整趟裡找最快的那一段，不算暫停的時間。"

    /// 一條路線裡最快的 1／5／10 公里、半馬（不夠長的那幾段沒有）。只看同一段（seg）裡相鄰兩點：暫停的空隙不算距離也不算時間
    /// （同 RouteMath.kmSplits），所以跨過暫停也找得到、暫停那幾分鐘不算進去。累計距離、累計移動時間兩條軸，
    /// 雙指標找「走完 D 公尺最少要幾秒」（終點照距離比例內插）。存檔時用簡化前的完整點算（WorkoutFacts.makeSession）。
    /// sim_v7.py best_efforts
    static func bestEfforts(_ route: [RoutePoint]) -> [WorkoutEffort] {
        let n = route.count
        guard n >= 2 else { return [] }
        var cd = [Double](repeating: 0, count: n)
        var ct = [Double](repeating: 0, count: n)
        for i in 1..<n {
            let p = route[i - 1]
            let q = route[i]
            var d = 0.0
            var dt = 0.0
            if (p.seg ?? 0) == (q.seg ?? 0) {
                let dd = haversineMeters(p.lat, p.lon, q.lat, q.lon)
                let tt = q.t - p.t
                if tt > 0, dd / tt <= effortMaxPairSpeed {
                    d = dd
                    dt = tt
                }
            }
            cd[i] = cd[i - 1] + d
            ct[i] = ct[i - 1] + dt
        }
        let total = cd[n - 1]
        var out: [WorkoutEffort] = []
        for target in effortMeters {
            guard total >= target else { break }
            var best: Double? = nil
            var j = 0
            var i = 0
            while i < n {
                let want = cd[i] + target
                if want > total + 1e-9 { break }
                if j < i { j = i }
                while j < n - 1 && cd[j + 1] < want { j += 1 }
                if j >= n - 1 { break }
                let segD = cd[j + 1] - cd[j]
                let k = segD > 0 ? (want - cd[j]) / segD : 0
                let tEnd = ct[j] + (ct[j + 1] - ct[j]) * k
                let sec = tEnd - ct[i]
                if sec > 0 {
                    if let b = best {
                        if sec < b { best = sec }
                    } else {
                        best = sec
                    }
                }
                i += 1
            }
            if let b = best, target / b <= effortMaxAverageSpeed {
                out.append(WorkoutEffort(meters: target, seconds: b))
            }
        }
        return out
    }

    /// 這個動作的最快幾公里：只有跑步、有路線（App 記的、手錶帶進來的）。存檔時算好的（WorkoutExercise.efforts）照用；
    /// v25.556 以前存的、手錶帶進來的沒有，就用存下來的（簡化過的）路線現算（sim §8：跟完整的點差 3 秒內）
    static func efforts(_ e: WorkoutExercise, in s: WorkoutSession) -> [WorkoutEffort] {
        guard e.kind == .cardio, e.resolvedSport == .run, e.hasRoute else { return [] }
        if let stored = e.efforts { return stored }
        guard let src = source(of: s), src == .app || src == .watch else { return [] }
        return bestEfforts(e.route)
    }

    /// 這種有氧算哪一種「最長」
    private static func longestKind(_ sport: WorkoutSport) -> WorkoutRecordKind? {
        switch sport {
        case .run: return .longestRun
        case .bike: return .longestBike
        case .walk: return .longestWalk
        case .hike: return .longestHike
        case .strength, .other: return nil
        }
    }

    /// 最快幾公里那段距離算哪一種
    private static func fastestKind(_ meters: Double) -> WorkoutRecordKind? {
        WorkoutRecordKind.allCases.first { k in
            guard let m = k.effortMeters else { return false }
            return abs(m - meters) < 0.5
        }
    }

    /// 新的比舊的好（一樣好留先跑出來的那一趟）
    private static func better(_ kind: WorkoutRecordKind, _ value: Double, than old: WorkoutRecord?) -> Bool {
        guard let o = old else { return true }
        return kind.smallerIsBetter ? value < o.value : value > o.value
    }

    /// 健康頁「個人紀錄」（照 WorkoutRecordKind 的順序；沒跑過的那一種不出現）。
    /// 最長：每個有氧動作的距離（手動補記、舊版記的、手錶的都算）；最快幾公里：efforts（只有跑步、有路線）
    static func personalRecords(_ sessions: [WorkoutSession]) -> [WorkoutRecord] {
        var best: [WorkoutRecordKind: WorkoutRecord] = [:]
        let ordered = sessions.sorted { $0.date < $1.date }
        for s in ordered {
            for e in s.exercises where e.kind == .cardio {
                if let kind = longestKind(e.resolvedSport), e.distanceKm.isFinite, e.distanceKm >= 0.05,
                   better(kind, e.distanceKm, than: best[kind]) {
                    best[kind] = WorkoutRecord(kind: kind, value: e.distanceKm, sessionId: s.id, date: s.date)
                }
                for eff in efforts(e, in: s) {
                    guard let kind = fastestKind(eff.meters), eff.seconds.isFinite, eff.seconds > 0,
                          better(kind, eff.seconds, than: best[kind]) else { continue }
                    best[kind] = WorkoutRecord(kind: kind, value: eff.seconds, sessionId: s.id, date: s.date)
                }
            }
        }
        return WorkoutRecordKind.allCases.compactMap { best[$0] }
    }

    /// 存檔時：這一趟破了哪幾個紀錄（跟比它早的每一趟比；以前沒有比得上的——第一次跑——不算）。
    /// 最快幾公里快 1 秒以上、最長多 0.05 公里以上才算。sim_v7.py record_marks
    static func recordMarks(for s: WorkoutSession, among sessions: [WorkoutSession]) -> [WorkoutRecordMark] {
        let before = sessions.filter { $0.id != s.id && $0.date < s.date }
        let old = personalRecords(before)
        var out: [WorkoutRecordMark] = []
        for r in personalRecords([s]) {
            guard let o = old.first(where: { $0.kind == r.kind }) else { continue }
            let broke = r.kind.smallerIsBetter ? r.value < o.value - 0.5 : r.value > o.value + 0.05
            if broke {
                out.append(WorkoutRecordMark(kind: r.kind.rawValue, value: r.value, previous: o.value))
            }
        }
        return out
    }

    /// 紀錄的值：最快 1 公里寫配速的樣子「5'41"」；5、10 公里、半馬寫時間「29:58」「1:02:10」；最長「10.2 公里」
    static func recordValueText(_ kind: WorkoutRecordKind, value: Double) -> String {
        switch kind {
        case .fastest1k:
            return WorkoutFormat.pace(value / 60)
        case .fastest5k, .fastest10k, .fastestHalf:
            return WorkoutFormat.clock(seconds: value)
        case .longestRun, .longestBike, .longestWalk, .longestHike:
            return WorkoutFormat.km(value)
        }
    }

    /// 成果頁「這趟的收穫」那一條：「新紀錄：最快 5 公里 29:40（快 18 秒）」「新紀錄：最長 10.5 公里（多 0.3 公里）」；
    /// 新版才有的 kind（舊版讀不懂）回 nil
    static func recordGainText(_ m: WorkoutRecordMark) -> String? {
        guard let kind = WorkoutRecordKind(rawValue: m.kind) else { return nil }
        let value = recordValueText(kind, value: m.value)
        if kind.smallerIsBetter {
            let faster = WorkoutFormat.wholeSeconds(m.previous - m.value)
            let gap = faster >= 60 ? "\(faster / 60) 分 " + String(format: "%02d 秒", faster % 60) : "\(faster) 秒"
            return "新紀錄：" + kind.title + " " + value + "（快 " + gap + "）"
        }
        return "新紀錄：" + kind.title + " " + value + "（多 " + WorkoutFormat.kmNumber(m.value - m.previous) + " 公里）"
    }

    /// 這一趟破的第一個紀錄的名字（項目卡第一顆膠囊、成果看板右上膠囊：「最快 1 公里」）；沒有 nil
    static func firstRecordTitle(_ s: WorkoutSession) -> String? {
        for m in s.highlights?.records ?? [] {
            if let k = WorkoutRecordKind(rawValue: m.kind) { return k.title }
        }
        return nil
    }
}

// MARK: - 同一條路自動比上次（judge §6 v7：起終點 150 公尺內、距離差 10% 內、方向相同）

extension WorkoutFacts {

    /// 起點、終點各自離多近才算同一條（公尺）
    static let sameRouteEndsMeters: Double = 150
    /// 距離差多少以內（比例）
    static let sameRouteDistanceRatio: Double = 0.10
    /// 這麼短的不比（公里）
    static let sameRouteMinKm: Double = 0.5
    /// 走到 25%、50%、75% 那幾點各自離多近（公尺；至少 150、或路線長的 6%）：方向相同、中間走同一條
    static let sameRouteMidMeters: Double = 150
    static let sameRouteMidRatio: Double = 0.06

    /// 沿著路線（不分段，暫停的空隙也當直線）走到每一個 fraction（0…1）的那幾點，和路線全長（公尺）。sim point_at
    static func routeSamples(_ route: [RoutePoint], fractions: [Double]) -> (points: [(lat: Double, lon: Double)], length: Double)? {
        let n = route.count
        guard n >= 2 else { return nil }
        var cum = [Double](repeating: 0, count: n)
        for i in 1..<n {
            cum[i] = cum[i - 1] + haversineMeters(route[i - 1].lat, route[i - 1].lon, route[i].lat, route[i].lon)
        }
        let total = cum[n - 1]
        var out: [(lat: Double, lon: Double)] = []
        for f in fractions {
            let target = total * f
            var found: (lat: Double, lon: Double)? = nil
            for i in 1..<n where cum[i] >= target {
                let d = cum[i] - cum[i - 1]
                let k = d > 0 ? (target - cum[i - 1]) / d : 0
                let p = route[i - 1]
                let q = route[i]
                found = (lat: p.lat + (q.lat - p.lat) * k, lon: p.lon + (q.lon - p.lon) * k)
                break
            }
            out.append(found ?? (lat: route[n - 1].lat, lon: route[n - 1].lon))
        }
        return (points: out, length: total)
    }

    /// 兩條路是不是同一條（距離用畫面上的公里數 aKm、bKm）。sim same_route
    static func sameRoute(_ a: [RoutePoint], km aKm: Double, _ b: [RoutePoint], km bKm: Double) -> Bool {
        guard a.count >= 2, b.count >= 2, aKm >= sameRouteMinKm, bKm >= sameRouteMinKm else { return false }
        guard abs(aKm - bKm) <= sameRouteDistanceRatio * max(aKm, bKm) else { return false }
        guard let a0 = a.first, let a1 = a.last, let b0 = b.first, let b1 = b.last else { return false }
        guard haversineMeters(a0.lat, a0.lon, b0.lat, b0.lon) <= sameRouteEndsMeters,
              haversineMeters(a1.lat, a1.lon, b1.lat, b1.lon) <= sameRouteEndsMeters else { return false }
        let fractions = [0.25, 0.5, 0.75]
        guard let sa = routeSamples(a, fractions: fractions), let sb = routeSamples(b, fractions: fractions),
              sa.points.count == sb.points.count else { return false }
        let tolerance = max(sameRouteMidMeters, sameRouteMidRatio * max(sa.length, sb.length))
        for i in 0..<sa.points.count {
            let p = sa.points[i]
            let q = sb.points[i]
            if haversineMeters(p.lat, p.lon, q.lat, q.lon) > tolerance { return false }
        }
        return true
    }

    /// 比上次快幾秒（正＝快、負＝慢）：照這一趟的距離換算（距離差一點也公平；一樣長就是時間差）。sim route_delta
    static func routeDelta(previousKm: Double, previousMinutes: Double, km: Double, minutes: Double) -> Double? {
        guard previousKm > 0, km > 0, previousMinutes > 0, minutes > 0 else { return nil }
        let d = (previousMinutes / previousKm - minutes / km) * km * 60
        return d.isFinite ? d : nil
    }

    /// 「比上次快 42 秒」「比上次慢 1 分 05 秒」；差不到 3 秒「跟上次差不多」；算不出來 nil。sim route_delta_text
    static func routeDeltaText(_ seconds: Double?) -> String? {
        guard let sec = seconds, sec.isFinite else { return nil }
        let s = WorkoutFormat.wholeSeconds(abs(sec))
        if s < 3 { return "跟上次差不多" }
        let t = s >= 60 ? "\(s / 60) 分 " + String(format: "%02d 秒", s % 60) : "\(s) 秒"
        return (sec > 0 ? "比上次快 " : "比上次慢 ") + t
    }

    /// 名字最後的時段名、運動名（長的先比）
    private static let routeSuffixes: [String] = [
        "深夜跑步", "午後跑步", "深夜健走", "午後健走", "午間健走", "深夜騎車", "午後騎車",
        // [v25.557 裁定] 兩、三個字的運動詞要排在單字「跑」「走」「單車」前面：不然「週末長跑」會變「週末長老路線」、
        // 「河濱騎單車」會變「河濱騎老路線」（sim_v7 SUFFIXES 同步）
        "騎單車", "長跑", "路跑", "練跑", "快走", "爬山",
        "晨跑", "午跑", "夜跑", "晨走", "晚走", "晨騎", "午騎", "夜騎", "跑步", "健走", "騎車", "登山",
        "慢跑", "散步", "走路", "健行", "單車", "騎", "跑", "走"
    ]

    /// 路線的名字：「河濱晨跑」→「河濱老路線」（去掉最後的時段名／運動名，加「老路線」）；
    /// 只有時段名、運動名（「晨跑」「跑步」）→ nil；沒有那種字尾的自己取的名字照用（「河濱自行車道」）。sim route_nickname
    static func routeNickname(_ title: String) -> String? {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        for suf in routeSuffixes {
            if t == suf { return nil }
            if t.hasSuffix(suf) {
                let base = String(t.dropLast(suf.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                return base.isEmpty ? nil : base + "老路線"
            }
        }
        return t
    }

    /// 存檔時取的路線名字：這一趟的名字 → 同一條路以前那幾趟（新到舊）的名字 → 以前那幾趟的地點 → 「老路線」
    static func routeName(_ s: WorkoutSession, matched: [WorkoutSession]) -> String {
        if let n = routeNickname(s.title) { return n }
        let recent = matched.sorted { $0.date > $1.date }
        for o in recent {
            if let n = routeNickname(o.title) { return n }
        }
        for o in recent {
            let p = o.place.trimmingCharacters(in: .whitespacesAndNewlines)
            if !p.isEmpty { return p }
        }
        return "老路線"
    }

    /// 存檔時：同一條路以前跑過幾次、比上次快多少（跑過才有；這一趟是第一次 nil）。只跟比它早的、同一類運動、有路線的比
    static func routeMatch(for s: WorkoutSession, among sessions: [WorkoutSession]) -> WorkoutRouteMatch? {
        guard let e = s.firstRouteExercise else { return nil }
        let sport = e.resolvedSport
        guard sport.runSport != nil else { return nil }
        var matched: [WorkoutSession] = []
        for o in sessions where o.id != s.id && o.date < s.date {
            guard let oe = o.firstRouteExercise, sportsMatch(oe.resolvedSport, sport) else { continue }
            if sameRoute(e.route, km: e.distanceKm, oe.route, km: oe.distanceKm) {
                matched.append(o)
            }
        }
        guard let prev = matched.max(by: { $0.date < $1.date }), let pe = prev.firstRouteExercise else { return nil }
        let prevMinutes = pe.durationMinutes > 0 ? pe.durationMinutes : movingMinutes(prev)
        let minutes = e.durationMinutes > 0 ? e.durationMinutes : movingMinutes(s)
        let delta = routeDelta(previousKm: pe.distanceKm, previousMinutes: prevMinutes, km: e.distanceKm, minutes: minutes)
        return WorkoutRouteMatch(name: routeName(s, matched: matched), count: matched.count + 1,
                                 deltaSeconds: delta, previousId: prev.id)
    }

    /// 這一趟現在的名字是你自己取的就用它算（存檔後改過名字也跟著變），不然用存檔時取的
    static func routeDisplayName(_ s: WorkoutSession, _ m: WorkoutRouteMatch) -> String {
        if isCustomTitle(s.title), let n = routeNickname(s.title) { return n }
        return m.name ?? "老路線"
    }

    /// 成果看板右上膠囊：「河濱老路線・第 12 次」（第 2 次起才有）
    static func routeCapsule(_ s: WorkoutSession) -> String? {
        guard let m = s.highlights?.route, let n = m.count, n >= 2 else { return nil }
        return routeDisplayName(s, m) + "・第 \(n) 次"
    }

    /// 這趟的收穫那一條：「河濱老路線・第 12 次・比上次快 42 秒」
    static func routeLine(_ s: WorkoutSession) -> String? {
        guard let head = routeCapsule(s) else { return nil }
        if let d = routeDeltaText(s.highlights?.route?.deltaSeconds) { return head + "・" + d }
        return head
    }

    /// 項目卡的膠囊：「第 12 次・快 42 秒」「第 12 次・慢 15 秒」「第 12 次・差不多」
    static func routeChip(_ s: WorkoutSession) -> String? {
        guard let m = s.highlights?.route, let n = m.count, n >= 2 else { return nil }
        var t = "第 \(n) 次"
        if let d = routeDeltaText(m.deltaSeconds) {
            if d == "跟上次差不多" {
                t += "・差不多"
            } else {
                t += "・" + d.replacingOccurrences(of: "比上次", with: "")
            }
        }
        return t
    }

    /// 存檔時算一次（WorkoutFacts.makeSession）：破紀錄＋同一條路；都沒有 nil
    static func highlights(for s: WorkoutSession, among sessions: [WorkoutSession]) -> WorkoutHighlights? {
        let marks = recordMarks(for: s, among: sessions)
        let route = routeMatch(for: s, among: sessions)
        guard !marks.isEmpty || route != nil else { return nil }
        return WorkoutHighlights(records: marks.isEmpty ? nil : marks, route: route)
    }
}

// MARK: - 請假週（judge §6 v7「月曆＋請假週」）

extension WorkoutFacts {

    /// 請假的那一週存的字：那一週週一的日期「2026-08-31」（西曆、手機時區）
    static func leaveKey(weekOf date: Date) -> String {
        let s = weekStart(of: date)
        let c = calendar.dateComponents([.year, .month, .day], from: s)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 「2026-08-31」→ 那一週週一 00:00；看不懂 nil
    static func leaveWeekStart(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]
        c.month = parts[1]
        c.day = parts[2]
        guard let d = calendar.date(from: c) else { return nil }
        return weekStart(of: d)
    }

    /// 請假的那幾週（週一 00:00）：連續週數、月曆用
    static func leaveWeeks(_ book: WorkoutLeaveBook) -> Set<Date> {
        Set((book.weeks ?? []).compactMap { leaveWeekStart($0) })
    }

    /// 這一天所在的那一週請假了沒
    static func isLeave(_ book: WorkoutLeaveBook, weekOf date: Date) -> Bool {
        book.contains(leaveKey(weekOf: date))
    }
}

// MARK: - 月曆（每天一格，深淺＝那天動了多久；最右邊一欄＝那一週有沒有算進連續週數）

/// [v25.557] 月曆的一天
struct WorkoutMonthDay: Identifiable, Equatable {
    let date: Date
    /// 幾號
    let day: Int
    /// 是這個月的（上個月、下個月的日子畫淡一點、不能點）
    let inMonth: Bool
    let isToday: Bool
    /// 今天之後（不上色）
    let isFuture: Bool
    /// 那天每一趟的移動時間加總（分鐘）
    let minutes: Double
    /// 深淺 0…4（WorkoutFacts.heatLevel）
    let level: Int
    /// 那天做了哪幾種（最多兩種，照 跑、走、騎、登山、重訓、其他）
    let sports: [WorkoutSport]
    /// 第三種起還有幾種（格子寫「+1」）
    let more: Int
    /// 那天的每一趟（舊到新）：一趟直接打開、兩趟以上讓你選
    let sessionIds: [UUID]
    /// VoiceOver：「10 月 15 日，跑步 32 分鐘」「10 月 16 日，沒有運動」
    let spoken: String

    var id: Date { date }
}

/// [v25.557] 月曆一週最右邊那一欄
enum WorkoutWeekMark: Equatable {
    /// 沒有運動、沒請假（過去的週不打叉、不染紅；這週、以後的週也是這個）
    case none
    /// 有運動（算進連續週數）：打勾
    case active
    /// 沒運動但請假：葉子（不斷、也不加）
    case leave
}

/// [v25.557] 月曆的一週（一列）
struct WorkoutMonthWeek: Identifiable, Equatable {
    /// 週一 00:00
    let start: Date
    /// 請假存的字「2026-10-12」（WorkoutFacts.leaveKey）
    let key: String
    /// 週一到週日
    let days: [WorkoutMonthDay]
    let mark: WorkoutWeekMark
    /// 這一週標了請假（有運動時 mark 是 active，但這個照樣是 true：長按選單寫「取消請假」）
    let isLeave: Bool
    let isCurrent: Bool
    /// 下週以後
    let isFuture: Bool

    var id: Date { start }
}

/// [v25.557] 一個月的月曆
struct WorkoutMonthGrid: Equatable {
    /// 那個月 1 號 00:00
    let month: Date
    /// 「2026 年 10 月」
    let title: String
    /// 這個月碰到的每一週（9/28 那週到 10/26 那週，4～6 列）
    let weeks: [WorkoutMonthWeek]
    /// 這個月幾趟
    let tripCount: Int
    /// 標頭右邊：「10 月・9 趟」
    let trailing: String
    /// 月曆下面那一行：「連續 6 週（9/7 那週起）」「連續 11 週（7/27 那週起）・中間請假 1 週」；0 週「這週動一下，就開始算連續週數」
    let footer: String
}

extension WorkoutFacts {

    /// 這一天所在那個月的 1 號 00:00
    static func monthStart(_ date: Date) -> Date {
        let c = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: c) ?? calendar.startOfDay(for: date)
    }

    /// 月曆格子的深淺：沒動 0；1–19 分 1（重訓沒填時間也算 1）；20–39 分 2；40–59 分 3；60 分以上 4。sim heat_level
    static func heatLevel(minutes: Double, counted: Bool) -> Int {
        if minutes >= 60 { return 4 }
        if minutes >= 40 { return 3 }
        if minutes >= 20 { return 2 }
        if minutes >= 1 || counted { return 1 }
        return 0
    }

    /// 月曆能翻到哪幾個月（舊到新）：第一筆運動那個月到下個月（下週請假剛好跨月時翻得到）；一筆都沒有：這個月、下個月
    static func calendarMonths(_ sessions: [WorkoutSession], now: Date = Date()) -> [Date] {
        let thisMonth = monthStart(now)
        let first = sessions.map(\.date).min().map { monthStart($0) } ?? thisMonth
        let last = calendar.date(byAdding: .month, value: 1, to: thisMonth) ?? thisMonth
        var out: [Date] = []
        var cur = min(first, thisMonth)
        while cur <= last && out.count < 600 {
            out.append(cur)
            guard let next = calendar.date(byAdding: .month, value: 1, to: cur) else { break }
            cur = next
        }
        return out
    }

    /// 一天的運動種類順序（格子上的小圖示）
    private static let monthSportOrder: [WorkoutSport] = [.run, .walk, .bike, .hike, .strength, .other]

    /// 一個月的月曆（在 .task 裡算，body 只畫）。leave：LifeStore.workoutLeave
    static func monthGrid(_ sessions: [WorkoutSession], month: Date, leave: WorkoutLeaveBook,
                          now: Date = Date()) -> WorkoutMonthGrid {
        let first = monthStart(month)
        let next = calendar.date(byAdding: .month, value: 1, to: first) ?? first.addingTimeInterval(31 * 86_400)
        let today = calendar.startOfDay(for: now)
        let thisWeek = weekStart(of: now)
        let leaveSet = leaveWeeks(leave)
        // 每天的運動（同一天依時間排）
        var byDay: [Date: [WorkoutSession]] = [:]
        for s in sessions {
            byDay[calendar.startOfDay(for: s.date), default: []].append(s)
        }
        var weeks: [WorkoutMonthWeek] = []
        var cursor = weekStart(of: first)
        while cursor < next && weeks.count < 7 {
            var days: [WorkoutMonthDay] = []
            var active = false
            for i in 0..<7 {
                let d = calendar.date(byAdding: .day, value: i, to: cursor) ?? cursor.addingTimeInterval(Double(i) * 86_400)
                let list = (byDay[d] ?? []).sorted { $0.date < $1.date }
                let counted = list.contains { counts($0) }
                if counted { active = true }
                let minutes = list.reduce(0) { $0 + max(0, movingMinutes($1)) }
                var kinds: [WorkoutSport] = []
                for sp in monthSportOrder where list.contains(where: { $0.primarySport == sp }) {
                    kinds.append(sp)
                }
                let comps = calendar.dateComponents([.month, .day], from: d)
                let dayNumber = comps.day ?? 0
                let monthNumber = comps.month ?? 0
                var spoken = "\(monthNumber) 月 \(dayNumber) 日，"
                if list.isEmpty {
                    spoken += "沒有運動"
                } else {
                    let names = kinds.map(\.displayName).joined(separator: "、")
                    spoken += names + (minutes >= 1 ? " " + WorkoutFormat.total(minutes: minutes) : "")
                    if list.count > 1 { spoken += "，\(list.count) 趟" }
                }
                days.append(WorkoutMonthDay(date: d, day: dayNumber, inMonth: d >= first && d < next,
                                            isToday: d == today, isFuture: d > today,
                                            minutes: minutes, level: heatLevel(minutes: minutes, counted: counted),
                                            sports: Array(kinds.prefix(2)), more: max(0, kinds.count - 2),
                                            sessionIds: list.map(\.id), spoken: spoken))
            }
            let isLeave = leaveSet.contains(cursor)
            let mark: WorkoutWeekMark = active ? .active : (isLeave ? .leave : .none)
            weeks.append(WorkoutMonthWeek(start: cursor, key: leaveKey(weekOf: cursor), days: days, mark: mark,
                                          isLeave: isLeave, isCurrent: cursor == thisWeek, isFuture: cursor > thisWeek))
            guard let nextWeek = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = nextWeek
        }
        let inMonth = sessions.filter { $0.date >= first && $0.date < next }
        let mc = calendar.dateComponents([.year, .month], from: first)
        let monthNumber = mc.month ?? 0
        let st = streak(sessions, leave: leaveSet, now: now)
        var footer: String
        if st.weeks >= 1, let since = st.since {
            footer = "連續 \(st.weeks) 週（" + WorkoutFormat.monthDay(since) + " 那週起）"
            if st.leaveWeeks > 0 { footer += "・中間請假 \(st.leaveWeeks) 週" }
        } else {
            footer = "這週動一下，就開始算連續週數"
        }
        return WorkoutMonthGrid(month: first, title: "\(mc.year ?? 0) 年 \(monthNumber) 月", weeks: weeks,
                                tripCount: inMonth.count, trailing: "\(monthNumber) 月・\(inMonth.count) 趟",
                                footer: footer)
    }
}
