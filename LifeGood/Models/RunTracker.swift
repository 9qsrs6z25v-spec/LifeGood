import Foundation
import CoreLocation
import Combine

// MARK: - 跑步／騎車即時路徑紀錄（v25.352）
//
// 用 CoreLocation 連續定位，邊跑邊累積距離、時間、配速與路徑點。
// 為了控制同步體積，路徑點在「記錄當下」就抽稀：至少移動 minDistance 公尺
// 或間隔 minInterval 秒才收一點，單次上限 maxPoints 點。以 5 公里、抽稀後
// 約 500 點計算，一次跑步大概只佔 15KB，放進 life_workouts 的 blob 沒問題。
//
// 背景定位：allowsBackgroundLocationUpdates 需要 Info.plist 的 UIBackgroundModes
// 含 location，否則會在執行期直接 crash——這個設定已寫進 pbxproj。

@MainActor
final class RunTracker: NSObject, ObservableObject {

    static let shared = RunTracker()

    // 抽稀參數
    private let minDistance: CLLocationDistance = 8      // 公尺
    private let minInterval: TimeInterval = 5            // 秒
    private let maxPoints = 3000
    /// 水平精度差過頭的點直接丟掉（隧道、室內常見）
    private let worstAccuracy: CLLocationAccuracy = 50

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

    private let manager = CLLocationManager()
    private var startedAt: Date?
    private var pausedAccumulated: TimeInterval = 0
    private var pauseStartedAt: Date?
    private var lastAccepted: CLLocation?
    private var lastAltitude: Double?
    private var ticker: AnyCancellable?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
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

    // MARK: - 控制

    func requestAuthorization() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func start() {
        guard phase == .idle else { return }
        requestAuthorization()
        distanceMeters = 0
        elapsed = 0
        points = []
        elevationGainM = 0
        currentSpeedMS = 0
        lastAccepted = nil
        lastAltitude = nil
        pausedAccumulated = 0
        pauseStartedAt = nil
        startedAt = Date()
        waitingForFix = true
        phase = .running
        beginUpdates()
        startTicker()
    }

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
        // 暫停期間移動過（例如坐車），不要把那一段連成直線灌進距離
        lastAccepted = nil
        phase = .running
        beginUpdates()
    }

    /// 結束並回傳這一趟的成果；phase 回到 idle
    @discardableResult
    func finish() -> (distanceKm: Double, minutes: Double, route: [RoutePoint], elevation: Double) {
        if phase == .paused, let p = pauseStartedAt {
            pausedAccumulated += Date().timeIntervalSince(p)
            pauseStartedAt = nil
        }
        updateElapsed()
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        ticker?.cancel(); ticker = nil
        let result = (distanceKm: distanceMeters / 1000,
                      minutes: elapsed / 60,
                      route: points,
                      elevation: elevationGainM)
        phase = .idle
        startedAt = nil
        waitingForFix = false
        return result
    }

    /// 丟棄這一趟
    func cancel() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        ticker?.cancel(); ticker = nil
        phase = .idle
        startedAt = nil
        distanceMeters = 0
        elapsed = 0
        points = []
        elevationGainM = 0
        waitingForFix = false
    }

    // MARK: - 內部

    private func beginUpdates() {
        let status = manager.authorizationStatus
        // 只有拿到定位授權才打開背景更新，否則系統會直接丟例外
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            manager.allowsBackgroundLocationUpdates = true
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

    private func accept(_ loc: CLLocation) {
        guard phase == .running else { return }
        // 精度太差或是舊的快取點就丟掉
        guard loc.horizontalAccuracy > 0, loc.horizontalAccuracy <= worstAccuracy else { return }
        guard abs(loc.timestamp.timeIntervalSinceNow) < 10 else { return }

        waitingForFix = false
        lastCoordinate = loc.coordinate
        currentSpeedMS = max(0, loc.speed)

        defer { lastAccepted = loc }
        guard let prev = lastAccepted else {
            appendPoint(loc)
            lastAltitude = loc.altitude
            return
        }
        let step = loc.distance(from: prev)
        let gap = loc.timestamp.timeIntervalSince(prev.timestamp)
        // 明顯是跳點（一秒飛超過 50 公尺＝時速 180）就不計距離
        guard gap > 0, step / gap < 50 else { return }
        distanceMeters += step

        if let la = lastAltitude {
            let up = loc.altitude - la
            if up > 1 { elevationGainM += up }        // 1 公尺以下當雜訊
        }
        lastAltitude = loc.altitude

        if step >= minDistance || gap >= minInterval { appendPoint(loc) }
    }

    private func appendPoint(_ loc: CLLocation) {
        guard points.count < maxPoints, let s = startedAt else { return }
        points.append(RoutePoint(lat: loc.coordinate.latitude,
                                 lon: loc.coordinate.longitude,
                                 t: loc.timestamp.timeIntervalSince(s),
                                 alt: loc.altitude))
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
            self.authorization = status
            if self.phase == .running,
               status == .authorizedAlways || status == .authorizedWhenInUse {
                self.beginUpdates()
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

    /// 每公里分段配速（分鐘／公里）
    static func splits(_ route: [RoutePoint]) -> [(km: Int, minutes: Double)] {
        guard route.count >= 2 else { return [] }
        var out: [(Int, Double)] = []
        var acc: Double = 0
        var kmIndex = 1
        var lastSplitTime: Double = route[0].t
        for i in 1..<route.count {
            let a = CLLocation(latitude: route[i - 1].lat, longitude: route[i - 1].lon)
            let b = CLLocation(latitude: route[i].lat, longitude: route[i].lon)
            acc += b.distance(from: a)
            while acc >= 1000 {
                let minutes = (route[i].t - lastSplitTime) / 60
                out.append((kmIndex, minutes))
                lastSplitTime = route[i].t
                kmIndex += 1
                acc -= 1000
            }
        }
        return out
    }
}
