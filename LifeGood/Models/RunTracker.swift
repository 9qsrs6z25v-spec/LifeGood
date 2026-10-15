import Foundation
import CoreLocation
import CoreMotion
import Combine

// MARK: - 跑步／騎車即時路徑紀錄（v25.352；v25.551 存點重寫）
//
// 用 CoreLocation 連續定位，邊跑邊累積距離、時間、配速與路徑點。
//
// [v25.551] 存點規則（模擬：health/build/v1/sim_v1.py，常數一個都不能跟模擬不一樣）：
// • 跟「上一個存下來的點」比（以前跟上一筆定位比，1 秒只走 3 公尺永遠到不了 8 公尺，
//   一整趟只存得到起點那 1 點，所以跑完沒有地圖）。
// • 每種運動自己的間距（RunSport.minStep：跑 5、走／登山 4、騎 10 公尺）。
// • 精度 20 公尺內才起點、才算距離；50 公尺以外完全不收；超過 30 秒的舊定位不收
//   （鎖屏時系統會攢一批才送）。
// • 最近 5 筆、而且跟最新那筆相差 6 秒內的好定位，經緯度平均後才拿來比（線不會抖）。
// • 跳點（跟上一個存下來的點相比超過 RunSport.maxSpeed）不算；定位回報的速度低於
//   RunSport.stillSpeed、離上一點又不到兩倍間距，當成站著（紅燈）不加距離。
// • 距離＝存下來的點之間相加。存滿 3,000 點就隔一個丟一個、間距加倍（騎 100 公里也留得住）。
// • 暫停再繼續是新的一段（RoutePoint.seg）：暫停中走的路不連線、不算距離、不算爬升。
// • 爬升用氣壓計（CMAltimeter，比錨點高 1 公尺才算）；沒有「動作與健身」說明字、
//   或使用者不允許，就用 GPS 高度備案（平滑 0.1、門檻 5 公尺）。
// • 暖機：開始運動畫面一打開就 prepare() 先定位（藍點、GPS 燈，起點不會歪），
//   也先問「動作與健身」；畫面關掉 stopPreparing()。
// • 精度用 kCLLocationAccuracyBest（Apple 運動路線範例的設定；導航級是給接著電源用的）。
//
// 背景定位：allowsBackgroundLocationUpdates 需要 Info.plist 的 UIBackgroundModes
// 含 location，否則 CoreLocation 會斷言、App 直接閃退。這個鍵要寫在
// LifeGood/Info.plist（v25.533）；寫在 pbxproj 的 INFOPLIST_KEY_UIBackgroundModes
// 不會進到打包出來的 Info.plist。beginUpdates 另外先檢查一次，設定再壞也只是
// 鎖屏後不記錄，不會閃退。

// MARK: - 運動種類（v25.551）

/// 開始運動畫面選的運動。rawValue 就是畫面上的字，也是存檔時的訓練名稱；
/// HealthKitManager.activityType(forName:) 靠這幾個字對到 Apple 健康的運動種類。
/// 運動種類放在 RunTracker（不是畫面）：選騎車、按「隱藏」再從健康頁回來，還是騎車。
enum RunSport: String, CaseIterable, Identifiable {
    case run = "跑步"
    case walk = "健走"
    case bike = "騎車"
    case hike = "登山"

    var id: String { rawValue }

    /// 離「上一個存下來的點」至少幾公尺才再存一點。
    /// 健走 4 公尺＝大約每 3 秒一點（Apple 寫運動路線的建議）。
    var minStep: Double {
        switch self {
        case .run: return 5
        case .walk: return 4
        case .hike: return 4
        case .bike: return 10
        }
    }

    /// 跟上一個存下來的點相比，平均速度超過這個（公尺／秒）就當成跳點
    var maxSpeed: Double {
        switch self {
        case .run: return 12
        case .walk: return 12
        case .hike: return 12
        case .bike: return 25
        }
    }

    /// 定位回報的速度低於這個（公尺／秒），而且離上一點不到兩倍間距，就當成站著（紅燈），不加距離
    var stillSpeed: Double {
        switch self {
        case .run: return 0.5
        case .walk: return 0.4
        case .hike: return 0.4
        case .bike: return 1.0
        }
    }

    /// 地圖預設拉多近（鏡頭離地公尺）：大約看得到前後兩三個路口
    var followDistance: Double {
        switch self {
        case .run: return 600
        case .walk: return 400
        case .hike: return 800
        case .bike: return 1_200
        }
    }

    // MARK: 記住的選擇（開始運動畫面用）

    /// 上次選的運動（@AppStorage 也用這個鍵，存的是 rawValue）
    static let lastSportKey = "run_last_sport"

    /// 上次選的運動；沒選過就是跑步
    static var remembered: RunSport {
        RunSport(rawValue: UserDefaults.standard.string(forKey: lastSportKey) ?? "") ?? .run
    }

    /// 這種運動記住的地圖遠近的鍵，例：run_follow_distance_跑步
    var followDistanceKey: String { "run_follow_distance_" + rawValue }

    /// 這種運動記住的地圖遠近；沒記過就用預設值。夾在 150～5,000 公尺
    var rememberedFollowDistance: Double {
        let v = UserDefaults.standard.double(forKey: followDistanceKey)
        guard v > 0 else { return followDistance }
        return min(max(v, 150), 5_000)
    }

    /// 記住兩指縮放後的遠近。拉到 5 公里以外看大範圍可以，但下次打開最多從 5 公里開始
    func rememberFollowDistance(_ meters: Double) {
        guard meters.isFinite, meters > 0 else { return }
        UserDefaults.standard.set(min(max(meters, 150), 5_000), forKey: followDistanceKey)
    }
}

/// 結束一趟的成果（RunTracker.finish() 回傳；呼叫端只有 RunTrackingView.finish()）
struct RunResult {
    let sport: RunSport
    let distanceKm: Double
    /// 扣掉暫停的移動時間（分鐘）
    let movingMinutes: Double
    let route: [RoutePoint]
    /// 累計爬升（公尺）
    let elevation: Double
    /// 按「開始」那一刻
    let startedAt: Date
    /// 真正結束的時間：最後一次按暫停那一刻（「完成」鈕只在暫停時出現，暫停到按完成之間不算運動）；
    /// 沒在暫停就是按完成那一刻
    let endedAt: Date
}

/// 地圖上的一段線（暫停再繼續就是新的一段），給 Map 裡的 ForEach 用
struct RouteSegment: Identifiable {
    let id: Int
    let coordinates: [CLLocationCoordinate2D]
}

@MainActor
final class RunTracker: NSObject, ObservableObject {

    static let shared = RunTracker()

    // 存點參數（[v25.551] 跟 health/build/v1/sim_v1.py 一模一樣）
    /// 存滿這麼多點就隔一個丟一個、間距加倍
    private let maxPoints = 3000
    /// 水平精度差過頭的點直接丟掉（隧道、室內常見）；20～50 公尺的只更新藍點和燈
    private let worstAccuracy: CLLocationAccuracy = 50
    /// [v25.551] 定位時間離現在超過這個（秒）就不收：鎖屏時系統會攢一批才送，原本 10 秒會丟掉一大段
    private let freshSeconds: TimeInterval = 30
    /// [v25.551] 平均最近幾筆好定位
    private let windowCount = 5
    /// [v25.551] 而且跟最新那筆相差幾秒內才一起平均（橋下斷訊後不拿 10 秒前的點來平均，線頭不會往回縮）
    private let windowSeconds: TimeInterval = 6
    /// [v25.551] GPS 備案：平滑後的高度比錨點高這麼多（公尺）才算爬升
    private let gpsClimbStep: Double = 5
    /// [v25.551] 氣壓計：比錨點高這麼多（公尺）才算爬升
    private let baroClimbStep: Double = 1
    /// [v25.551] GPS 備案：垂直精度在這個以內（公尺）的高度才拿來算
    private let gpsMaxVerticalAccuracy: CLLocationAccuracy = 15

    enum Phase { case idle, running, paused }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var points: [RoutePoint] = []
    @Published private(set) var currentSpeedMS: Double = 0
    @Published private(set) var elevationGainM: Double = 0
    @Published private(set) var lastCoordinate: CLLocationCoordinate2D?
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    /// 已經開始跑但一直收不到有效定位（收不到 GPS）時給畫面提示
    @Published private(set) var waitingForFix = false
    /// [v25.551] 這一趟的運動（start(sport:) 決定）；畫面標題、健康頁橫幅、存檔都讀這個
    @Published private(set) var sport: RunSport = .run
    /// [v25.551] 最新一筆定位的水平誤差（公尺），給 GPS 燈；還沒收到過就是 nil
    @Published private(set) var gpsAccuracy: Double?
    /// [v25.551] 每收到一筆定位就加一。座標不是 Equatable，畫面用這個當 onChange 的觸發
    @Published private(set) var fixSerial = 0

    /// [v25.551] 精度在這個以內（公尺）才起點、才算距離、線頭才接到藍點
    private let goodAccuracy: CLLocationAccuracy = 20
    /// [v25.551] 第幾段：暫停再繼續就加一，存點時寫進 RoutePoint.seg（0 寫 nil）
    private var seg = 0
    /// [v25.551] 最新一筆定位的時間：擋亂序、重複，也給 secondsSinceFix
    private var lastFixTime: Date?

    private let manager = CLLocationManager()
    private var startedAt: Date?
    private var pausedAccumulated: TimeInterval = 0
    private var pauseStartedAt: Date?
    private var ticker: AnyCancellable?

    /// [v25.551] 上一個存下來的點（平均過的）：距離、間距、跳點、站著都跟它比
    private var lastStored: CLLocation?
    /// [v25.551] 最近幾筆好定位（精度 20 公尺內），拿來平均
    private var window: [CLLocation] = []
    /// [v25.551] 這一趟的存點間距；存滿 3,000 點時加倍
    private var minStep: Double = RunSport.run.minStep
    /// [v25.551] 開始運動畫面開著（prepare 之後、stopPreparing 之前）
    private var preparing = false

    /// [v25.551] 氣壓計（爬升）；startAltimeter 是唯一打開它的地方。
    /// lazy：第一次用到是在 startAltimeter 過了 hasMotionUsage 之後，打包出來的 Info.plist
    /// 沒有「動作與健身」說明字時，整個 App 從頭到尾都不會建立 CMAltimeter
    private lazy var altimeter = CMAltimeter()
    /// [v25.551] 氣壓計開著：開著就不用 GPS 高度算爬升
    private var usingBarometer = false
    /// [v25.551] 氣壓計的錨點（相對高度，公尺）
    private var baroAnchor: Double?
    /// [v25.551] GPS 備案：平滑過的高度
    private var gpsAltSmooth: Double?
    /// [v25.551] GPS 備案：錨點
    private var gpsAltAnchor: Double?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
    }

    var isActive: Bool { phase != .idle }

    /// 目前平均配速（分鐘／公里）；距離太短時回 nil，避免一開跑就跳出誇張數字
    var paceMinPerKm: Double? {
        guard distanceMeters > 50, elapsed > 0 else { return nil }
        return (elapsed / 60) / (distanceMeters / 1000)
    }

    /// 即時配速（由最近一次定位的速度換算）
    var livePaceMinPerKm: Double? {
        guard currentSpeedMS > 0.5 else { return nil }
        return (1000 / currentSpeedMS) / 60
    }

    /// [v25.551] 手機記得的上一個位置：還沒收到新定位前，地圖開場先放在這裡（不會拉到整個台灣）
    var lastKnownCoordinate: CLLocationCoordinate2D? {
        lastCoordinate ?? manager.location?.coordinate
    }

    /// [v25.551] 離最新一筆定位幾秒；還沒收到過是 nil。GPS 燈用：太久沒收到就當成還在找
    var secondsSinceFix: TimeInterval? {
        guard let t = lastFixTime else { return nil }
        return Date().timeIntervalSince(t)
    }

    /// [v25.551] 地圖上要畫的線：依 seg 切段（暫停那段不連線）；記錄中、精度夠好時，
    /// 最後一段再接到藍點，線頭每秒跟著人走，不會落後 5 筆平均的那 2 秒。
    /// 畫面只讀這個，不在 body 裡切段。
    var segments: [RouteSegment] {
        var runs = RouteMath.segmentRuns(points)
        if phase == .running, let tail = lastCoordinate, let last = points.last,
           (last.seg ?? 0) == seg, let acc = gpsAccuracy, acc <= goodAccuracy, !runs.isEmpty {
            runs[runs.count - 1].append(tail)
        }
        return RouteMath.drawableSegments(runs)
    }

    // MARK: - 控制

    func requestAuthorization() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// [v25.551] 開始運動畫面一打開就呼叫：先定位（藍點、GPS 燈，起點不會歪），也先問「動作與健身」。
    /// 只在 App 開著時定位、不開背景更新；畫面關掉要呼叫 stopPreparing()。
    func prepare() {
        preparing = true
        requestAuthorization()
        let status = manager.authorizationStatus
        if phase == .idle, status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
        }
        startAltimeter()
    }

    /// [v25.551] 開始運動畫面關掉時呼叫；正在記錄（含暫停）就什麼都不關
    func stopPreparing() {
        preparing = false
        guard phase == .idle else { return }
        manager.stopUpdatingLocation()
        stopAltimeter()
    }

    /// [v25.551] 開始記錄（原本的 start() 拿掉了：一定要說是哪種運動）。
    /// 暖機時收到的 lastFixTime、lastCoordinate、gpsAccuracy 不清：線頭和燈馬上就有。
    func start(sport: RunSport) {
        guard phase == .idle else { return }
        requestAuthorization()
        self.sport = sport
        minStep = sport.minStep
        seg = 0
        lastStored = nil
        window = []
        baroAnchor = nil
        gpsAltSmooth = nil
        gpsAltAnchor = nil
        distanceMeters = 0
        elapsed = 0
        points = []
        elevationGainM = 0
        currentSpeedMS = 0
        pausedAccumulated = 0
        pauseStartedAt = nil
        startedAt = Date()
        waitingForFix = true
        phase = .running
        beginUpdates()
        startTicker()
        startAltimeter()                                   // 暖機時已經開了就略過
    }

    /// 暫停：關定位省電（鎖定畫面的「繼續」v6 再改）。氣壓計不關，onBarometer 在暫停時不算
    func pause() {
        guard phase == .running else { return }
        phase = .paused
        pauseStartedAt = Date()
        manager.stopUpdatingLocation()
    }

    func resume() {
        guard phase == .paused else { return }
        if let p = pauseStartedAt { pausedAccumulated += Date().timeIntervalSince(p) }
        pauseStartedAt = nil
        // 暫停期間移動過（走去便利商店、坐電梯）：那一段不連線、不算距離、不算爬升，另起一段
        lastStored = nil
        window = []
        seg += 1
        baroAnchor = nil
        gpsAltAnchor = nil
        // GPS 備案的平滑值也從頭算：留著舊的，坐電梯上 30 公尺後平滑值會慢慢追上去，
        // 被當成爬了 30 公尺（build/v1/g1/elevator_check.py：留著 31～37 m、清掉 6～13 m＝跟平路一樣）
        gpsAltSmooth = nil
        phase = .running
        beginUpdates()
    }

    /// 結束並回傳這一趟的成果；phase 回到 idle。
    /// endedAt＝最後一次按暫停那一刻（「完成」只在暫停時出現，暫停到按完成之間不是運動）
    @discardableResult
    func finish() -> RunResult {
        let now = Date()
        let end = pauseStartedAt ?? now
        if phase == .paused, let p = pauseStartedAt {
            pausedAccumulated += now.timeIntervalSince(p)
            pauseStartedAt = nil
        }
        updateElapsed()
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        ticker?.cancel(); ticker = nil
        stopAltimeter()
        let begin = startedAt ?? end.addingTimeInterval(-elapsed)
        let result = RunResult(sport: sport,
                               distanceKm: distanceMeters / 1000,
                               movingMinutes: elapsed / 60,
                               route: points,
                               elevation: elevationGainM,
                               startedAt: begin,
                               endedAt: max(end, begin))
        phase = .idle
        startedAt = nil
        waitingForFix = false
        lastStored = nil
        window = []
        return result
    }

    /// 丟棄這一趟
    func cancel() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        ticker?.cancel(); ticker = nil
        stopAltimeter()
        phase = .idle
        startedAt = nil
        pauseStartedAt = nil
        pausedAccumulated = 0
        distanceMeters = 0
        elapsed = 0
        points = []
        elevationGainM = 0
        waitingForFix = false
        lastStored = nil
        window = []
        seg = 0
    }

    // MARK: - 內部

    /// 打包出來的 Info.plist 真的有宣告 location 背景模式才為 true
    private static let hasLocationBackgroundMode: Bool = {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        return modes.contains("location")
    }()

    private func beginUpdates() {
        let status = manager.authorizationStatus
        // 只有拿到定位授權、而且 App 有宣告 location 背景模式才打開背景更新，
        // 兩個少一個 CoreLocation 都會直接斷言閃退（v25.533 就是少了背景模式）
        if (status == .authorizedAlways || status == .authorizedWhenInUse),
           Self.hasLocationBackgroundMode {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
        }
        manager.startUpdatingLocation()
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                if self.phase == .running { self.updateElapsed() }
            }
    }

    private func updateElapsed() {
        guard let s = startedAt else { return }
        elapsed = max(0, Date().timeIntervalSince(s) - pausedAccumulated)
    }

    // MARK: 存點（[v25.551] 跟 sim_v1.py 的 Tracker.accept／store／thin_out 一模一樣）

    /// 每一筆定位都進來：暖機、暫停時只更新藍點和燈；跑步中才平均、比對、存點
    private func accept(_ raw: CLLocation) {
        guard raw.horizontalAccuracy > 0, raw.horizontalAccuracy <= worstAccuracy else { return }
        guard abs(raw.timestamp.timeIntervalSinceNow) < freshSeconds else { return }   // 原本 10 秒；鎖屏時系統會攢一批才送
        if let t = lastFixTime, raw.timestamp <= t { return }                          // 亂序、重複
        lastFixTime = raw.timestamp
        lastCoordinate = raw.coordinate                                                // 鏡頭與線的尾巴
        gpsAccuracy = raw.horizontalAccuracy
        currentSpeedMS = max(0, raw.speed)
        fixSerial &+= 1
        guard phase == .running else { return }                                        // 暖機、暫停：只更新藍點和燈
        guard raw.horizontalAccuracy <= goodAccuracy else { return }                   // 還沒收斂：不起點、不算距離
        waitingForFix = false
        window.append(raw)
        window.removeAll { raw.timestamp.timeIntervalSince($0.timestamp) > windowSeconds }
        if window.count > windowCount { window.removeFirst() }
        let loc = Self.averaged(window, latest: raw)
        guard let prev = lastStored else { store(loc); return }
        let d = loc.distance(from: prev)
        let dt = loc.timestamp.timeIntervalSince(prev.timestamp)
        guard dt > 0, d / dt < sport.maxSpeed else { return }                          // 跳點：lastStored 不動
        if raw.speed >= 0, raw.speed < sport.stillSpeed, d < 2 * minStep { return }    // 紅燈站著的飄移
        guard d >= minStep else { return }
        distanceMeters += d                                                            // 距離＝存下來的點之間相加
        store(loc)
    }

    /// 經緯度取平均；時間、高度、精度、速度取最新那筆
    private static func averaged(_ window: [CLLocation], latest: CLLocation) -> CLLocation {
        guard !window.isEmpty else { return latest }
        var lat = 0.0
        var lon = 0.0
        for l in window {
            lat += l.coordinate.latitude
            lon += l.coordinate.longitude
        }
        let n = Double(window.count)
        return CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat / n, longitude: lon / n),
                          altitude: latest.altitude,
                          horizontalAccuracy: latest.horizontalAccuracy,
                          verticalAccuracy: latest.verticalAccuracy,
                          course: latest.course,
                          speed: latest.speed,
                          timestamp: latest.timestamp)
    }

    /// 存一點：RoutePoint 帶段號（0 寫 nil 省空間）；存滿 3,000 點就放寬；沒有氣壓計時順便算 GPS 爬升
    private func store(_ loc: CLLocation) {
        lastStored = loc
        if let s = startedAt {
            points.append(RoutePoint(lat: loc.coordinate.latitude,
                                     lon: loc.coordinate.longitude,
                                     t: max(0, loc.timestamp.timeIntervalSince(s)),
                                     alt: loc.altitude,
                                     seg: seg == 0 ? nil : seg))
            if points.count >= maxPoints { thinOut() }
        }
        gpsElevation(loc)
    }

    /// 存滿了：隔一個丟一個（第一點、最後一點留著），之後間距加倍（騎 100 公里最後約每 40 公尺一點）
    private func thinOut() {
        guard let last = points.last else { return }
        var kept: [RoutePoint] = []
        kept.reserveCapacity(points.count / 2 + 2)
        for (i, p) in points.enumerated() where i % 2 == 0 { kept.append(p) }
        if (points.count - 1) % 2 != 0 { kept.append(last) }
        points = kept
        minStep *= 2
    }

    // MARK: 爬升（[v25.551] 氣壓計；沒有就用 GPS 備案）

    /// 打包出來的 Info.plist 真的有「動作與健身」說明字才為 true；沒有就不碰 CMAltimeter（不然一呼叫就閃退），走 GPS 備案。
    /// 這個鍵寫在 pbxproj 的 INFOPLIST_KEY_NSMotionUsageDescription（Debug、Release 兩處），寫法同 hasLocationBackgroundMode
    private static let hasMotionUsage: Bool = {
        let text = Bundle.main.object(forInfoDictionaryKey: "NSMotionUsageDescription") as? String ?? ""
        return !text.isEmpty
    }()

    /// 唯一打開氣壓計的地方（每個 CMAltimeter 呼叫前都先過 hasMotionUsage）；已經開著就略過。
    /// prepare() 和 start(sport:) 都會呼叫：暖機時問「動作與健身」被按了「不允許」、系統卻沒回錯誤時，
    /// 按開始的這一刻也會發現，改用 GPS 備案（不然整趟爬升都是 0）
    private func startAltimeter() {
        guard Self.hasMotionUsage, CMAltimeter.isRelativeAltitudeAvailable() else { return }
        let status = CMAltimeter.authorizationStatus()
        guard status != .denied, status != .restricted else {
            if usingBarometer { stopAltimeter() }
            return
        }
        guard !usingBarometer else { return }
        usingBarometer = true
        baroAnchor = nil                                                   // 重新打開時相對高度從 0 算起，舊錨點對不上
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
            let h = data?.relativeAltitude.doubleValue                     // 先把數字取出來
            let failed = error != nil
            guard let tracker = self else { return }
            Task { @MainActor in tracker.onBarometer(h, failed: failed) }  // 照 locationManager(_:didUpdateLocations:) 的寫法
        }
    }

    /// 關氣壓計（沒開過也可以呼叫：沒開過就什麼都不碰）；之後 store() 改用 GPS 高度。
    /// usingBarometer 只在 startAltimeter 真的打開時設 true，所以 CMAltimeter 只會在開過之後才被呼叫
    private func stopAltimeter() {
        guard usingBarometer else { return }
        altimeter.stopRelativeAltitudeUpdates()
        usingBarometer = false
    }

    /// 氣壓計：比錨點高 1 m 才算，往下超過 1 m 就把錨點移下來；暫停中不算
    private func onBarometer(_ h: Double?, failed: Bool) {
        if failed { stopAltimeter(); return }                   // 使用者不給「動作與健身」：之後改用 GPS
        guard phase == .running, let h else { return }
        guard let a = baroAnchor else { baroAnchor = h; return }
        if h - a >= baroClimbStep {
            elevationGainM += h - a
            baroAnchor = h
        } else if h < a - baroClimbStep {
            baroAnchor = h
        }
    }

    /// GPS 備案（只在 store() 裡、而且沒有氣壓計時）：高度先平滑 0.1，再用 5 m 門檻
    private func gpsElevation(_ loc: CLLocation) {
        guard !usingBarometer, loc.verticalAccuracy > 0, loc.verticalAccuracy <= gpsMaxVerticalAccuracy else { return }
        let s = (gpsAltSmooth ?? loc.altitude) * 0.9 + loc.altitude * 0.1
        gpsAltSmooth = s
        guard let a = gpsAltAnchor else { gpsAltAnchor = s; return }
        if s - a >= gpsClimbStep {
            elevationGainM += s - a
            gpsAltAnchor = s
        } else if s < a - gpsClimbStep {
            gpsAltAnchor = s
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension RunTracker: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        let received = locations
        Task { @MainActor in
            for loc in received { self.accept(loc) }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            // 參數也叫 manager：閉包裡一律寫 self.manager
            self.authorization = status
            let granted = status == .authorizedAlways || status == .authorizedWhenInUse
            if self.phase == .running, granted {
                self.beginUpdates()
            } else if self.preparing, self.phase == .idle, granted {
                self.manager.startUpdatingLocation()            // [v25.551] 暖機中剛按允許：馬上開始定位
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 暫時收不到定位不算失敗，畫面上已用 waitingForFix 提示，這裡不中斷紀錄
    }
}

// MARK: - 路徑工具

enum RouteMath {
    /// 路徑的中心與涵蓋範圍，用來決定地圖要拉多遠
    static func bounds(_ route: [RoutePoint]) -> (center: CLLocationCoordinate2D, spanMeters: Double)? {
        guard !route.isEmpty else { return nil }
        let lats = route.map(\.lat), lons = route.map(\.lon)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let a = CLLocation(latitude: minLat, longitude: minLon)
        let b = CLLocation(latitude: maxLat, longitude: maxLon)
        return (center, max(300, a.distance(from: b) * 1.35))
    }

    static func coordinates(_ route: [RoutePoint]) -> [CLLocationCoordinate2D] {
        route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    /// [v25.551] 手機完全不知道你在哪、也沒有上一趟紀錄時，地圖先放這裡（台北車站）
    static let fallbackCenter = CLLocationCoordinate2D(latitude: 25.0478, longitude: 121.5170)

    /// [v25.551] 依 RoutePoint.seg 把路線切成一段一段（暫停再繼續是新的一段）。
    /// 只有一點的段也留著（記錄中線頭會接到藍點），畫之前再用 drawableSegments 濾掉。
    static func segmentRuns(_ route: [RoutePoint]) -> [[CLLocationCoordinate2D]] {
        var runs: [[CLLocationCoordinate2D]] = []
        var current: [CLLocationCoordinate2D] = []
        var currentSeg: Int? = nil
        for p in route {
            let s = p.seg ?? 0
            if let cs = currentSeg, cs != s {
                runs.append(current)
                current = []
            }
            currentSeg = s
            current.append(CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon))
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    /// [v25.551] 畫得出來的段（兩點以上）；id 是畫面上的第幾段
    static func drawableSegments(_ runs: [[CLLocationCoordinate2D]]) -> [RouteSegment] {
        var out: [RouteSegment] = []
        for run in runs where run.count >= 2 {
            out.append(RouteSegment(id: out.count, coordinates: run))
        }
        return out
    }

    /// [v25.551] 已存路線的線段（RouteMapView 用）
    static func segments(_ route: [RoutePoint]) -> [RouteSegment] {
        drawableSegments(segmentRuns(route))
    }

    /// 每公里分段配速（分鐘／公里）。
    /// [v25.551] 段與段之間（暫停）跳過：那段空隙不算距離，那段時間也不算進那一公里
    static func splits(_ route: [RoutePoint]) -> [(km: Int, minutes: Double)] {
        guard route.count >= 2 else { return [] }
        var out: [(Int, Double)] = []
        var acc: Double = 0
        var kmIndex = 1
        var lastSplitTime: Double = route[0].t
        var pausedInSplit: Double = 0
        for i in 1..<route.count {
            if (route[i].seg ?? 0) != (route[i - 1].seg ?? 0) {
                pausedInSplit += max(0, route[i].t - route[i - 1].t)
                continue
            }
            let a = CLLocation(latitude: route[i - 1].lat, longitude: route[i - 1].lon)
            let b = CLLocation(latitude: route[i].lat, longitude: route[i].lon)
            acc += b.distance(from: a)
            while acc >= 1000 {
                let minutes = max(0, route[i].t - lastSplitTime - pausedInSplit) / 60
                out.append((kmIndex, minutes))
                lastSplitTime = route[i].t
                pausedInSplit = 0
                kmIndex += 1
                acc -= 1000
            }
        }
        return out
    }
}
