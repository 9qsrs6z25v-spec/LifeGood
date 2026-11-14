import Foundation
import CoreLocation
import HealthKit

// MARK: - 跑步的路線（手錶 v4，v25.580；watch/judge.md §2.10 權限五種狀態、§5.7 路線；watch/build/v4/brief.md §2、G2-2）
//
// 只屬於 LifeGoodWatch。**骨架（主控寫）：對外的名字、型別、參數不准改（WorkoutManager、準備頁 G3 照這些寫）；G2 填內容。**
// CLLocationManager（kCLLocationAccuracyBest、activityType .fitness）→ 誤差 50 公尺以上的點丟掉、暫停中不收 →
// 插進這一趟 builder 的 HKWorkoutRouteBuilder（seriesBuilder(for: .workoutRoute())，Apple「Creating a workout route」）；
// 存好運動之後 finishRoute(with:metadata:)；拿不到或收尾失敗、當機接回的那一趟，改用獨立的 HKWorkoutRouteBuilder 把收下來的點
// 一次插進去再收尾（同 iPhone HealthKitManager.saveRoute 的退路）。收下來的點另外留一份（points）：RunStash 每 30 秒存、
// 當機接回、〔再存一次〕、摘要小圖都用它。
//
// 精確位置（judge §2.10、§5.7）：只有大約位置時，進準備頁問一次「這一次給精確位置」
// （requestTemporaryFullAccuracyAuthorization(withPurposeKey: "RunRoute")）；打包出來的 Info.plist 真的有
// NSLocationTemporaryUsageDescriptionDictionary["RunRoute"] 才問（hasPreciseLocationPurpose，同 iPhone RunTracker），沒有就不問、不閃退。
// ⚠️ 絕對不准設 allowsBackgroundLocationUpdates（手錶 Info.plist 沒有 location 背景模式＝一開定位就閃退；運動 session 本來就讓
//    App 在背景活著）。位置權限只要「使用 App 時」（requestWhenInUseAuthorization），不要「永遠」。
// ⚠️ delegate 在 manager 建立的那條執行緒（這裡是主執行緒）叫；照 iPhone RunTracker 寫 nonisolated＋Task { @MainActor in }。
//
// [G2 填好]
// • 想要定位（wantsUpdates：準備頁暖機、跑步中）時權限剛給（locationManagerDidChangeAuthorization）就馬上 startUpdatingLocation；
//   準備頁中剛給「只有大約位置」也接著問一次精確位置（同一次準備頁只問一次，askedThisPrep）。
// • 收點：誤差 > 0 而且 ≤ 50 公尺、不早於開始、比上一點新、座標合法、跑步中而且沒暫停。每一批點排隊插進 seriesBuilder
//   （insertTask 一個接一個，收尾前先等插完）；插失敗一次就整條改用獨立的 builder（seriesFailed）。
// • GPS 弱：精確位置才算（沒有位置、只有大約位置時準備頁已經講過，跑步中頁首不再一直寫「GPS 弱」）；
//   最後一個 ≤ 20 公尺的定位、或開始／繼續那一刻（給 10 秒找回來）取晚的，離現在超過 10 秒＝弱；暫停中不算。
// • 獨立 builder 的點：時間夾在運動開始～結束之間（超出運動時間的點 Apple 健康不收；同 iPhone HealthKitManager.locations）。

@MainActor
final class RouteRecorder: NSObject, ObservableObject {
    static let shared = RouteRecorder()

    /// 位置權限（準備頁那一行，WatchRunText.prepLine）
    @Published private(set) var access: WatchRunLocationAccess = .unknown
    /// 準備頁「● GPS 找到了」：最近一筆誤差 20 公尺以內（WatchRunFacts 同 iPhone gpsWeakAccuracy 20）
    @Published private(set) var gpsFound = false
    /// 跑步中「晨跑・GPS 弱」：誤差超過 20 公尺連續 10 秒、或 10 秒收不到定位（暫停中不算）
    @Published private(set) var gpsWeak = false

    /// 這一趟收下來的點（WorkoutManager 存 RunStash、收尾、摘要小圖用；舊到新）
    private(set) var points: [WatchRunPoint] = []

    /// Info.plist 的 NSLocationTemporaryUsageDescriptionDictionary 裡的鍵（同 iPhone RunTracker.preciseLocationPurposeKey）
    static let purposeKey = "RunRoute"
    /// 誤差超過這個（公尺）的點不收（Apple「Creating a workout route」）
    static let maxAccuracy: Double = 50
    /// 誤差在這個以內算「GPS 找到了」（同 iPhone WorkoutFacts.gpsWeakAccuracy）
    static let goodAccuracy: Double = 20
    /// 超過這麼久（秒）收不到、或一直不準＝GPS 弱（同 iPhone WorkoutFacts.gpsWeakSeconds）
    static let weakSeconds: Double = 10

    /// 打包出來的 Info.plist 真的有「這一次給精確位置」那句說明才為 true（同 iPhone RunTracker.hasPreciseLocationPurpose）
    static let hasPreciseLocationPurpose: Bool = {
        let dict = Bundle.main.object(forInfoDictionaryKey: "NSLocationTemporaryUsageDescriptionDictionary") as? [String: Any]
        let text = dict?[RouteRecorder.purposeKey] as? String ?? ""
        return !text.isEmpty
    }()

    private let manager = CLLocationManager()

    // MARK: 內部（G2）

    /// 這一趟 builder 的路線 builder（nil＝收尾時用獨立的）
    private var routeBuilder: HKWorkoutRouteBuilder?
    /// 插點排隊（一批等上一批插完；收尾前先等最後一批）
    private var insertTask: Task<Void, Never>?
    /// seriesBuilder 插失敗過：之後不再插，收尾改用獨立的 builder 插全部的點
    private var seriesFailed = false
    /// 定位那一刻的移動秒數（WorkoutManager.movingSeconds(at:)）
    private var moving: ((Date) -> Double)?
    /// 想要定位（準備頁暖機、跑步中）：權限剛給時馬上開始
    private var wantsUpdates = false
    /// 跑步中（收點）
    private var recording = false
    /// 暫停中（你按的、自動的）：不收點
    private var paused = false
    /// 現在第幾段（每次暫停再繼續 +1）
    private var segment = 0
    /// 開始收點的時間（比它早的定位不收）
    private var beganAt: Date?
    /// 開始、繼續那一刻（GPS 弱給 10 秒找回來）
    private var graceFrom: Date?
    /// 最後一個誤差 20 公尺以內的定位時間
    private var lastGoodFix: Date?
    /// 這一次準備頁問過精確位置了
    private var askedThisPrep = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.distanceFilter = kCLDistanceFilterNone
        // 背景定位那個開關不設（見檔頭 ⚠️）
        refreshAccess()
    }

    /// 重讀位置權限（authorizationStatus＋accuracyAuthorization → access）
    func refreshAccess() {
        let next = Self.locationAccess(status: manager.authorizationStatus, accuracy: manager.accuracyAuthorization)
        if next != access { access = next }
    }

    /// 說明卡〔好〕之後：還沒問過才 requestWhenInUseAuthorization
    func requestAccess() {
        refreshAccess()
        guard access == .unknown else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// 進準備頁：只有大約位置、Info.plist 有說明字才問一次「這一次給精確位置」（同一次準備頁只問一次）
    func askPreciseOnce() {
        refreshAccess()
        guard access == .reduced, Self.hasPreciseLocationPurpose, !askedThisPrep else { return }
        askedThisPrep = true
        // 答案由 locationManagerDidChangeAuthorization 收（access 跟著改），這裡不用等
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: Self.purposeKey) { _ in }
    }

    /// 準備頁：有權限就開始定位（只更新 gpsFound，不收點）
    func warmUp() {
        wantsUpdates = true
        refreshAccess()
        guard access == .full || access == .reduced else { return }
        manager.startUpdatingLocation()
    }

    /// 準備頁 ✕、丟掉：停定位、清掉這一趟的狀態
    func cool() {
        manager.stopUpdatingLocation()
        wantsUpdates = false
        recording = false
        paused = false
        askedThisPrep = false
        routeBuilder = nil
        moving = nil
        if gpsFound { gpsFound = false }
        if gpsWeak { gpsWeak = false }
    }

    /// 開始收點。routeBuilder＝這一趟 builder 的 seriesBuilder（nil＝收尾時用獨立的）；
    /// moving＝定位那一刻的移動秒數（WorkoutManager.movingSeconds(at:)）；seg＝從第幾段開始（當機接回時接著上一段 +1）
    func begin(routeBuilder: HKWorkoutRouteBuilder?, moving: @escaping (Date) -> Double, seg: Int) {
        self.routeBuilder = routeBuilder
        self.moving = moving
        insertTask = nil
        seriesFailed = false
        recording = true
        paused = false
        segment = max(0, seg)
        let now = Date()
        beganAt = now
        graceFrom = now
        if gpsWeak { gpsWeak = false }
        wantsUpdates = true
        refreshAccess()
        manager.startUpdatingLocation()
    }

    /// 當機接回：先放回存檔裡的點（之後收的接在後面）
    func restore(points: [WatchRunPoint]) {
        self.points = points
    }

    /// 暫停（你按的、自動的）：不收點；繼續：換下一段（小圖、iPhone 那邊不連線）。一樣的狀態再叫一次不動
    func setPaused(_ paused: Bool) {
        guard paused != self.paused else { return }
        self.paused = paused
        if paused {
            if gpsWeak { gpsWeak = false }
        } else {
            segment += 1
            graceFrom = Date()
        }
    }

    /// 每秒一次（WorkoutManager 的 ticker）：GPS 弱的判斷
    func tick(now: Date) {
        var isWeak = false
        if recording && !paused && access == .full {
            let ref = max(lastGoodFix ?? .distantPast, graceFrom ?? .distantPast)
            isWeak = now.timeIntervalSince(ref) > Self.weakSeconds
        }
        if isWeak != gpsWeak { gpsWeak = isWeak }
    }

    /// 結束：停定位、不再收點（點留著，收尾要用）
    func stop() {
        recording = false
        wantsUpdates = false
        manager.stopUpdatingLocation()
        if gpsWeak { gpsWeak = false }
    }

    /// 存好運動之後：seriesBuilder 那一份收尾；沒有、失敗就看這筆運動是不是已經有路線，沒有再用獨立的 HKWorkoutRouteBuilder
    /// 把 points 一次插進去收尾。不到 2 點什麼都不做。成功回那條路線（〔不存這一趟〕要一起刪）
    func finishRoute(for workout: HKWorkout, healthStore: HKHealthStore) async -> HKWorkoutRoute? {
        let series = routeBuilder
        routeBuilder = nil
        let waiting = insertTask
        insertTask = nil
        if let waiting {
            await waiting.value
        }
        guard points.count >= 2 else { return nil }
        if let series, !seriesFailed {
            do {
                let route = try await series.finishRoute(with: workout, metadata: nil)
                return route
            } catch {
                // 沒收尾成功：下面先看有沒有路線，再用獨立的試一次
            }
        }
        if await hasRoute(workout, healthStore: healthStore) { return nil }
        return await saveRoute(points, for: workout, healthStore: healthStore)
    }

    /// 〔再存一次〕：用存檔裡的點寫一條獨立的路線（HKWorkoutRouteBuilder(healthStore:device:)）
    func saveRoute(_ points: [WatchRunPoint], for workout: HKWorkout, healthStore: HKHealthStore) async -> HKWorkoutRoute? {
        let locations = Self.locations(points, start: workout.startDate, end: workout.endDate)
        guard locations.count >= 2 else { return nil }
        let builder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
        do {
            try await builder.insertRouteData(locations)
            let route = try await builder.finishRoute(with: workout, metadata: nil)
            return route
        } catch {
            return nil
        }
    }

    /// 一趟結束（摘要收起來、丟掉）：點清掉
    func reset() {
        cool()
        points = []
        insertTask = nil
        seriesFailed = false
        beganAt = nil
        graceFrom = nil
        segment = 0
    }

    // MARK: 內部

    /// 權限 → 準備頁那一行要的四種
    private static func locationAccess(status: CLAuthorizationStatus,
                                       accuracy: CLAccuracyAuthorization) -> WatchRunLocationAccess {
        if status == .notDetermined { return .unknown }
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            return accuracy == .reducedAccuracy ? .reduced : .full
        }
        return .denied
    }

    /// 權限改了（剛按允許、精確位置開關、在設定裡關掉）
    private func authorizationChanged(status: CLAuthorizationStatus, accuracy: CLAccuracyAuthorization) {
        let next = Self.locationAccess(status: status, accuracy: accuracy)
        if next != access { access = next }
        guard wantsUpdates else { return }
        if next == .full || next == .reduced {
            manager.startUpdatingLocation()
        }
        if next == .reduced && !recording {
            askPreciseOnce()
        }
    }

    /// 收到一批定位（主執行緒）
    private func accept(_ locations: [CLLocation]) {
        var batch: [CLLocation] = []
        for loc in locations {
            let acc = loc.horizontalAccuracy
            if acc > 0, acc <= Self.goodAccuracy, loc.timestamp > (lastGoodFix ?? .distantPast) {
                lastGoodFix = loc.timestamp
            }
            guard recording, !paused, acc > 0, acc <= Self.maxAccuracy else { continue }
            if let began = beganAt, loc.timestamp < began { continue }
            if let last = points.last, loc.timestamp <= last.at { continue }
            let c = loc.coordinate
            guard CLLocationCoordinate2DIsValid(c) else { continue }
            let alt = loc.altitude.isFinite ? loc.altitude : 0
            let movingNow = moving?(loc.timestamp) ?? 0
            points.append(WatchRunPoint(lat: c.latitude, lon: c.longitude, alt: alt, at: loc.timestamp,
                                        moving: movingNow, acc: acc, seg: segment))
            batch.append(loc)
        }
        if let latest = locations.last {
            let found = latest.horizontalAccuracy > 0 && latest.horizontalAccuracy <= Self.goodAccuracy
            if found != gpsFound { gpsFound = found }
        }
        if !batch.isEmpty, !seriesFailed, let series = routeBuilder {
            insert(batch, into: series)
        }
    }

    /// 一批點插進 seriesBuilder（排在上一批後面）；插失敗：之後都不插，收尾用獨立的
    private func insert(_ batch: [CLLocation], into series: HKWorkoutRouteBuilder) {
        let previous = insertTask
        insertTask = Task { @MainActor in
            if let previous {
                await previous.value
            }
            guard !self.seriesFailed else { return }
            do {
                try await series.insertRouteData(batch)
            } catch {
                self.seriesFailed = true
            }
        }
    }

    /// 這筆運動是不是已經有路線（文件沒寫 finishWorkout 會不會順便收尾 seriesBuilder；有就不寫第二條；同 iPhone saveRoute）
    private func hasRoute(_ workout: HKWorkout, healthStore: HKHealthStore) async -> Bool {
        let count: Int = await withCheckedContinuation { cont in
            let p = HKQuery.predicateForObjects(from: workout)
            let q = HKSampleQuery(sampleType: HKSeriesType.workoutRoute(), predicate: p,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: samples?.count ?? 0)
            }
            healthStore.execute(q)
        }
        return count > 0
    }

    /// 路線點 → CLLocation：時間夾在開始～結束之間（超出運動時間的點 Apple 健康不收）；壞掉的座標不要
    private static func locations(_ points: [WatchRunPoint], start: Date, end: Date) -> [CLLocation] {
        var out: [CLLocation] = []
        out.reserveCapacity(points.count)
        let last = max(start, end)
        for p in points {
            let c = CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon)
            guard CLLocationCoordinate2DIsValid(c) else { continue }
            let t = min(max(p.at, start), last)
            let acc = p.acc.isFinite && p.acc > 0 ? p.acc : 5
            out.append(CLLocation(coordinate: c, altitude: p.alt.isFinite ? p.alt : 0,
                                  horizontalAccuracy: acc, verticalAccuracy: acc, timestamp: t))
        }
        return out
    }
}

extension RouteRecorder: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let received = locations
        Task { @MainActor in
            self.accept(received)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // 參數也叫 manager：在這裡先讀成值，閉包裡一律 self
        let status = manager.authorizationStatus
        let accuracy = manager.accuracyAuthorization
        Task { @MainActor in
            self.authorizationChanged(status: status, accuracy: accuracy)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 暫時收不到定位不算失敗（GPS 弱由 tick 判斷），不中斷這一趟
    }
}
