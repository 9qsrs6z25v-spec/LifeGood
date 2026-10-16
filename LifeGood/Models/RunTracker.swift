import Foundation
import CoreLocation
import CoreMotion
import Combine
import UIKit

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
//
// [v25.552] 記錄完整（模擬：health/build/v2/sim_v2.py 的 Tracker，常數一個都不能跟模擬不一樣）：
// • 中途存檔：按開始那一刻先寫一次（檔一直都在，剛出門就被關掉也救得回來）；跑步中每 30 秒或每 20 個新點
//   （checkpointSeconds／checkpointPoints，哪個先到算哪個）；按暫停、按繼續、App 退到背景（開相機、切去別的 App）
//   都馬上寫。寫到 Application Support/RunCheckpoints/<runId>.json（RunCheckpointStore，背景佇列寫，
//   不進 iCloud、不進手機備份）。按完成或放棄就刪（刪排在最後一次寫之後）。
//   下次打開 App 還在的檔＝上次被系統收掉、從多工畫面滑掉、沒存完的那一趟：RunRecoveryCenter 問〔存下來〕〔丟掉〕，
//   存下來跟按完成走同一條路（WorkoutFacts.makeSession）。
// • 暫停清單：每一次按暫停到按繼續記成一筆 WorkoutPause（RunResult.pauses）；最後按完成前那次不算
//  （它是 finish() 的結束時間）。
// • 每公里爬升記號：每走滿一整公里，記下那一刻的累計爬升（RunResult.kmClimb），每公里分段的爬升用相鄰兩個相減。
// • 氣壓計 30 秒沒資料（baroStaleSeconds；鎖屏、跑到一半關掉「動作與健身」系統又沒回錯誤）爬升改用 GPS 估：
//   從那一點重新起算、不補算停之前那段；氣壓計資料回來時先把錨點設成那一筆、不加（停掉那段 GPS 已經算過），之後換回氣壓計。
// • 精確位置：按開始時「精確位置」關著（只給大約位置，誤差 1～3 公里，每一筆都被丟掉、畫不出線），
//   就請系統「這一次給精確位置」（requestPreciseLocation：打包出來的 Info.plist 有說明字才呼叫，沒有就不碰，不會閃退）。

// MARK: - 運動種類（v25.551）

/// 開始運動畫面選的運動。rawValue 就是畫面上的字，也是存檔時的訓練名稱；
/// [v25.552] 存檔時另外記 WorkoutExercise.sport（WorkoutSport(_:)），Apple 健康的運動種類改看它（HealthKitManager.activityType(for:name:)）。
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

    // MARK: [v25.555] 跑步畫面的開關（build/v5/brief.md §2；主控寫好，G2 照用）

    /// 螢幕保持亮著（每種運動各記一個）的鍵，例：run_keep_awake_騎車
    var keepAwakeKey: String { "run_keep_awake_" + rawValue }

    /// 螢幕保持亮著：騎車預設開（手機架在龍頭），跑步、健走、登山預設關（在臂套裡，看鎖定畫面）。judge §4.0
    var keepAwake: Bool {
        (UserDefaults.standard.object(forKey: keepAwakeKey) as? Bool) ?? (self == .bike)
    }

    func setKeepAwake(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: keepAwakeKey)
    }

    /// 按開始先倒數 3、2、1（全部運動共用一個開關；預設開）的鍵
    static let countdownKey = "run_countdown"

    /// 倒數開關；沒設過＝開
    static var countdownOn: Bool {
        (UserDefaults.standard.object(forKey: countdownKey) as? Bool) ?? true
    }

    static func setCountdown(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: countdownKey)
    }

    /// 跑步中「結束」要按住幾秒（外圈填滿才算；只點一下不會結束）
    static let holdToFinishSeconds: Double = 1.0

    /// 面板上可以點來換的小格（slot 0＝左邊那格、1＝中間那格），這種運動記住的選擇（0、1、2 輪流）；沒選過是 0
    func cellChoice(_ slot: Int) -> Int {
        let v = UserDefaults.standard.integer(forKey: "run_cell_\(slot)_" + rawValue)
        return min(max(v, 0), 2)
    }

    func setCellChoice(_ slot: Int, _ value: Int) {
        UserDefaults.standard.set(min(max(value, 0), 2), forKey: "run_cell_\(slot)_" + rawValue)
    }
}

/// 結束一趟的成果（RunTracker.finish() 回傳，呼叫端是 RunTrackingView.finish()；
/// [v25.552] 救回中途存檔時 RunCheckpoint.result 也建一個。兩條路都交給 WorkoutFacts.makeSession 組成存檔）
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
    /// [v25.552] 中間每一次暫停（按暫停到按繼續）；最後按「完成」前那次不算
    var pauses: [WorkoutPause] = []
    /// [v25.552] 每走滿一整公里那一刻的累計爬升（kmClimb[0]＝第 1 公里走完時）；每公里爬升用相鄰兩個相減
    var kmClimb: [Double] = []
    /// [v25.555] 記錄時 GPS 好不好（跑步中每秒數：GPS 弱的秒數、平均誤差）；WorkoutFacts.makeSession 存進 WorkoutSession.gps
    var gps: WorkoutGPSQuality? = nil
}

/// [v25.555] 跑步中地圖上每整公里一塊白底小牌（記錄器走滿一整公里那一刻存下來的那一點；騎車畫面只畫 5 的倍數）
struct RunKmMarker: Identifiable, Equatable {
    /// 第幾公里（1 起）
    let km: Int
    let lat: Double
    let lon: Double

    var id: Int { km }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
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
    /// [v25.552] 中途存檔：最久每 30 秒寫一次
    private let checkpointSeconds: TimeInterval = 30
    /// [v25.552] 中途存檔：或每 20 個新點（GPS 很密的時候先到）
    private let checkpointPoints = 20
    /// [v25.552] 氣壓計超過這麼久（秒）沒資料，爬升改用 GPS 估（鎖屏、跑到一半關掉「動作與健身」系統又沒回錯誤）
    private let baroStaleSeconds: TimeInterval = 30

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
    /// [v25.552] 使用者把「精確位置」關掉了（有給位置權限、但只給大約位置）：誤差 1～3 公里，
    /// 每一筆都超過 50 公尺被丟掉，一直「定位中…」、畫不出線。GPS 燈改寫「精確位置關著」＋「打開精確位置」
    @Published private(set) var reducedAccuracy = false
    /// [v25.555] 地圖上每整公里一塊小牌（store() 走滿一整公里時加；start 清空）。// G1：在 store() 的 kmClimb 迴圈裡一起加
    @Published private(set) var kmMarkers: [RunKmMarker] = []

    /// [v25.555] 每走滿一整公里那一刻的移動時間（秒）：kmTimes[0]＝第 1 公里走完時。「這一公里」小步道用（WorkoutFacts.legProgress）。
    /// 不發布（elapsed 每秒都在變，畫面本來就每秒重畫）。// G1：在 store() 的 kmClimb 迴圈裡一起加、start 清空
    private(set) var kmTimes: [Double] = []

    /// [v25.552] 這一趟的編號：中途存檔的檔名（RunCheckpointStore），start(sport:) 換新的
    private(set) var runId = UUID()
    /// [v25.552] 正在記錄（含暫停）的那一趟的編號；沒在記錄是 nil。App 一打開找沒存的那幾趟時，跳過這一趟
    var activeRunId: UUID? { isActive ? runId : nil }
    /// [v25.553] 正在記錄（含暫停）的那一趟按「開始」的時間；沒在記錄是 nil。
    /// 健康頁的記錄中條照它取名（06:05 開始＝「晨跑」，WorkoutFacts.timeOfDayName）；只讀，不改記錄
    var activeStartedAt: Date? { isActive ? startedAt : nil }

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
    /// [v25.551] 氣壓計開著：開著就不用 GPS 高度算爬升（[v25.552] 除非 30 秒沒資料：baroAlive／baroFallback）
    private var usingBarometer = false
    /// [v25.551] 氣壓計的錨點（相對高度，公尺）
    private var baroAnchor: Double?
    /// [v25.551] GPS 備案：平滑過的高度
    private var gpsAltSmooth: Double?
    /// [v25.551] GPS 備案：錨點
    private var gpsAltAnchor: Double?

    /// [v25.552] 這一趟已經結束的暫停（按暫停到按繼續）；按完成前最後那次不算
    private var pauses: [WorkoutPause] = []
    /// [v25.552] 每走滿一整公里那一刻的累計爬升（RunResult.kmClimb）
    private var kmClimb: [Double] = []
    /// [v25.552] 上次中途存檔之後新存了幾點
    private var newPointsSinceCheckpoint = 0
    /// [v25.552] 上次中途存檔的時間
    private var lastCheckpointAt: Date?
    /// [v25.552] 最近一次收到氣壓計資料的時間（startAltimeter 打開時先記一次，給 30 秒寬限）
    private var lastBaroAt: Date?
    /// [v25.552] 氣壓計停了、爬升暫時用 GPS 估
    private var baroFallback = false
    /// [v25.552] App 退到背景時馬上寫一次中途存檔
    private var backgroundSink: AnyCancellable?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
        reducedAccuracy = Self.isReduced(manager)
        // [v25.552] 退到背景（開相機、切去別的 App）先寫一次：系統之後把 App 收掉也救得回來。
        // 閉包在 @MainActor 的 init 裡寫、不是 @Sendable，跟 startTicker 的 Timer.publish 一樣會被當成主執行緒
        //（這個通知系統在主執行緒送，不加 receive(on:)：晚一輪才寫，App 可能已經被暫停了）
        backgroundSink = NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                guard let self, self.isActive else { return }
                self.checkpointNow()
            }
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

    // MARK: [v25.555] 跑步畫面的數字（judge §4.2；算法在 WorkoutFacts，build/v5/sim_v5.py 驗算過）

    /// 現在離按開始幾秒（含暫停，跟 RoutePoint.t 同一把尺）；沒在記錄是 nil
    private var nowSinceStart: Double? {
        guard isActive, let s = startedAt else { return nil }
        return Date().timeIntervalSince(s)
    }

    /// 「這一公里」那一格（分鐘／公里）：最近 30 秒存下來的點；不到 50 公尺、暫停中是 nil（畫面寫「—」）
    var recentPaceMinPerKm: Double? {
        guard phase == .running, let t = nowSinceStart else { return nil }
        return WorkoutFacts.recentPace(points, nowT: t)
    }

    /// 騎車「時速」（公里／時）：最近 10 秒；暫停中、站著是 nil（畫面寫「—」）
    var recentSpeedKmh: Double? {
        guard phase == .running, let t = nowSinceStart else { return nil }
        return WorkoutFacts.recentSpeedKmh(points, nowT: t)
    }

    /// 「這一公里」小步道（騎車「這 5 公里」）
    var legProgress: RunLegProgress {
        WorkoutFacts.legProgress(distanceMeters: distanceMeters, elapsed: elapsed,
                                 kmTimes: kmTimes, sport: WorkoutSport(sport))
    }

    /// 正在暫停：按暫停那一刻（「已暫停・1:12」從這裡算）；沒在暫停是 nil
    var pausedAt: Date? {
        phase == .paused ? pauseStartedAt : nil
    }

    /// [v25.555] GPS 弱：跑步中（暫停不算），誤差超過 20 公尺連續 10 秒、或 10 秒收不到定位（隧道、橋下、還沒定到位）。
    /// 畫面上那條「GPS 訊號弱，距離可能少算」（還在等第一個好定位 waitingForFix、精確位置關著時畫面改寫自己的那一句、不畫這條）、
    /// GPS 燈「GPS 弱・誤差 35 公尺」、存檔的 WorkoutGPSQuality（弱的秒數）都讀這個。
    /// 用 Date() 算：畫面每秒（elapsed 一變）重畫時重新判斷，收不到定位也會變。build/v5/sim_v5.py 的 TrackerV5.gps_weak。
    /// // G1：照 build/v5/brief.md §G1-3 填（weakSince、lastFixArrival；開始、繼續時重設）
    var gpsWeak: Bool {
        false
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

    // MARK: 精確位置（v25.552）

    /// 暫時打開精確位置時，系統框上那句說明在 LifeGood/Info.plist 的
    /// NSLocationTemporaryUsageDescriptionDictionary 裡的鍵（字典型的鍵寫在 pbxproj 的 INFOPLIST_KEY_ 不會進到打包出來的 Info.plist，
    /// 跟 v25.533 的 UIBackgroundModes 一樣，所以寫在 Info.plist 檔案裡）
    static let preciseLocationPurposeKey = "RunRoute"

    /// 打包出來的 Info.plist 真的有那句說明才為 true（照 hasLocationBackgroundMode 的寫法）：沒有就不呼叫系統，畫面改帶去設定
    private static let hasPreciseLocationPurpose: Bool = {
        let dict = Bundle.main.object(forInfoDictionaryKey: "NSLocationTemporaryUsageDescriptionDictionary") as? [String: Any]
        let text = dict?["RunRoute"] as? String ?? ""
        return !text.isEmpty
    }()

    /// 有給位置權限、但「精確位置」關著（只給大約位置）。delegate 回呼裡也會呼叫，所以是 nonisolated
    nonisolated static func isReduced(_ m: CLLocationManager) -> Bool {
        let s = m.authorizationStatus
        guard s == .authorizedWhenInUse || s == .authorizedAlways else { return false }
        return m.accuracyAuthorization == .reducedAccuracy
    }

    /// 畫面上「打開精確位置」能不能直接跳系統框（不能就帶去設定）
    var canAskPreciseLocation: Bool { reducedAccuracy && Self.hasPreciseLocationPurpose }

    /// 跳系統框問「這一次給精確位置」（App 開著、精確位置關著、Info.plist 有說明字才會跳）。
    /// 答案由 locationManagerDidChangeAuthorization 收（reducedAccuracy 跟著改），這裡不用等
    func requestPreciseLocation() {
        guard canAskPreciseLocation else { return }
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: Self.preciseLocationPurposeKey) { _ in }
    }

    /// [v25.551] 開始運動畫面一打開就呼叫：先定位（藍點、GPS 燈，起點不會歪），也先問「動作與健身」。
    /// 只在 App 開著時定位、不開背景更新；畫面關掉要呼叫 stopPreparing()。
    /// [v25.555] asking：false＝不跳任何系統權限框（第一次打開、位置還沒問過：畫面先出我們的說明卡，按〔好〕才 prepare(asking: true)）。
    /// // G1：照 build/v5/brief.md §G1-1 改內容（現在 asking 還沒用到）
    func prepare(asking: Bool = true) {
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
    /// [v25.552] 換新的 runId（中途存檔的檔名）；lastBaroAt 不清：暖機時氣壓計已經在送就照用，
    /// 還沒送過的話 30 秒後自動走 GPS 備案，送了就換回來。精確位置關著就請系統暫時給；最後先寫一次中途存檔
    func start(sport: RunSport) {
        guard phase == .idle else { return }
        requestAuthorization()
        self.sport = sport
        runId = UUID()
        pauses = []
        kmClimb = []
        newPointsSinceCheckpoint = 0
        baroFallback = false
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
        if reducedAccuracy { requestPreciseLocation() }    // [v25.552] 精確位置關著：按開始這一刻請系統「這一次給精確位置」
        checkpointNow()                                    // [v25.552] 一開始就寫一次：檔一直都在，剛出門就被關掉也救得回來
    }

    /// 暫停：關定位省電（鎖定畫面的「繼續」v6 再改）。氣壓計不關，onBarometer 在暫停時不算
    /// [v25.552] 存檔的移動時間算到按暫停那一刻，馬上寫一次中途存檔（暫停中被關掉，救回來的結束時間＝按暫停那一刻）
    func pause() {
        guard phase == .running else { return }
        updateElapsed()                                    // 存檔的移動時間算到按暫停那一刻
        phase = .paused
        pauseStartedAt = Date()
        manager.stopUpdatingLocation()
        checkpointNow()
    }

    /// [v25.552] 這次暫停記進暫停清單（按暫停到按繼續），最後馬上寫一次中途存檔
    func resume() {
        guard phase == .paused else { return }
        let now = Date()
        if let p = pauseStartedAt {
            pausedAccumulated += now.timeIntervalSince(p)
            pauses.append(WorkoutPause(start: p, end: now))
        }
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
        checkpointNow()
    }

    /// 結束並回傳這一趟的成果；phase 回到 idle。
    /// endedAt＝最後一次按暫停那一刻（「完成」只在暫停時出現，暫停到按完成之間不是運動）
    /// [v25.552] 暫停清單、每公里爬升記號一起交出去（最後那次暫停不進 pauses：它在 pauseStartedAt，是結束時間）；
    /// 中途存檔刪掉（背景佇列，排在最後一次寫之後）
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
                               endedAt: max(end, begin),
                               pauses: pauses,
                               kmClimb: kmClimb)
        RunCheckpointStore.delete(runId)
        pauses = []
        kmClimb = []
        phase = .idle
        startedAt = nil
        waitingForFix = false
        lastStored = nil
        window = []
        return result
    }

    /// 丟棄這一趟（[v25.552] 中途存檔一起刪）
    func cancel() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        ticker?.cancel(); ticker = nil
        stopAltimeter()
        RunCheckpointStore.delete(runId)
        pauses = []
        kmClimb = []
        newPointsSinceCheckpoint = 0
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
                if self.phase == .running {
                    self.updateElapsed()
                    self.checkpointIfDue()                 // [v25.552] 沒有新點（站著、隧道）也每 30 秒寫一次
                }
            }
    }

    private func updateElapsed() {
        guard let s = startedAt else { return }
        elapsed = max(0, Date().timeIntervalSince(s) - pausedAccumulated)
    }

    // MARK: 中途存檔（[v25.552] 跟 sim_v2.py 的 Tracker.checkpoint_if_due／checkpoint_now 一樣）

    /// 每 30 秒或每 20 個新點寫一次（store() 和每秒的 ticker 都會叫）
    private func checkpointIfDue() {
        guard phase != .idle else { return }
        let now = Date()
        let since = lastCheckpointAt.map { now.timeIntervalSince($0) } ?? .infinity
        if newPointsSinceCheckpoint >= checkpointPoints || since >= checkpointSeconds {
            checkpointNow()
        }
    }

    /// 馬上寫一次（開始、暫停、繼續、退到背景）。寫檔在背景（RunCheckpointStore），這裡只抄一份資料
    private func checkpointNow() {
        guard phase != .idle, let s = startedAt else { return }
        if phase == .running { updateElapsed() }
        let cp = RunCheckpoint(id: runId,
                               sport: sport.rawValue,
                               startedAt: s,
                               savedAt: Date(),
                               movingSeconds: elapsed,
                               pausedAt: pauseStartedAt,
                               distanceMeters: distanceMeters,
                               elevationGainM: elevationGainM,
                               points: points,
                               pauses: pauses,
                               kmClimb: kmClimb)
        RunCheckpointStore.save(cp)
        lastCheckpointAt = Date()
        newPointsSinceCheckpoint = 0
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

    /// 存一點：RoutePoint 帶段號（0 寫 nil 省空間）；存滿 3,000 點就放寬；沒有氣壓計時順便算 GPS 爬升。
    /// [v25.552] 最後再記每公里爬升記號、數新點、到了就中途存檔（這段跟 sim_v2.py 的 Tracker.store 一樣）
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
        // [v25.552] 每走滿一整公里記一次累計爬升（每公里分段的爬升用相鄰兩個相減）
        while distanceMeters >= Double(kmClimb.count + 1) * 1000 {
            kmClimb.append(elevationGainM)
        }
        newPointsSinceCheckpoint += 1
        checkpointIfDue()
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
        lastBaroAt = Date()                                                // [v25.552] 給 30 秒寬限：這段時間還沒資料不算停
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
        baroFallback = false                                               // [v25.552] 關掉了就是一般的 GPS 備案
    }

    /// [v25.552] 氣壓計開著、而且 30 秒內有資料（t 用定位的時間：鎖屏一批送來的舊定位不會被誤判）
    private func baroAlive(at t: Date) -> Bool {
        guard usingBarometer, let last = lastBaroAt else { return false }
        return t.timeIntervalSince(last) <= baroStaleSeconds
    }

    /// 氣壓計：比錨點高 1 m 才算，往下超過 1 m 就把錨點移下來；暫停中不算。
    /// [v25.552] 有資料就記 lastBaroAt（暫停中也記：氣壓計還活著）；剛從 GPS 備案回來，先把錨點設成這一筆、不加
    private func onBarometer(_ h: Double?, failed: Bool) {
        if failed { stopAltimeter(); return }                   // 使用者不給「動作與健身」：之後改用 GPS
        guard let h else { return }
        lastBaroAt = Date()                                     // 暫停中也記：氣壓計還活著
        if baroFallback {                                       // 剛從 GPS 備案回來：從這一筆重新起算，停掉那段 GPS 已經算過
            baroFallback = false
            baroAnchor = h
            // GPS 的平滑值、錨點到這裡就舊了：清掉，之後氣壓計又停、或報錯關掉改回 GPS 時從新的那一點算，
            // 不會拿備案那時的舊高度追上來被當成爬升（下次進備案本來也會清，模擬結果不變）
            gpsAltSmooth = nil
            gpsAltAnchor = nil
            return
        }
        guard phase == .running else { return }
        guard let a = baroAnchor else { baroAnchor = h; return }
        if h - a >= baroClimbStep {
            elevationGainM += h - a
            baroAnchor = h
        } else if h < a - baroClimbStep {
            baroAnchor = h
        }
    }

    /// GPS 備案（只在 store() 裡、而且沒有氣壓計時）：高度先平滑 0.1，再用 5 m 門檻。
    /// [v25.552] 氣壓計開著但 30 秒沒資料也走這裡（剛停那一點重新起算，不補算停之前那段）
    private func gpsElevation(_ loc: CLLocation) {
        if baroAlive(at: loc.timestamp) { return }                 // 氣壓計活著：爬升歸它
        if usingBarometer, !baroFallback {                          // 氣壓計剛停：GPS 從這一點重新起算（不補算停之前那段）
            baroFallback = true
            gpsAltSmooth = nil
            gpsAltAnchor = nil
        }
        guard loc.verticalAccuracy > 0, loc.verticalAccuracy <= gpsMaxVerticalAccuracy else { return }
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
        let reduced = RunTracker.isReduced(manager)          // [v25.552] 精確位置開關改了也會來這裡
        Task { @MainActor in
            // 參數也叫 manager：閉包裡一律寫 self.manager
            self.authorization = status
            self.reducedAccuracy = reduced
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
