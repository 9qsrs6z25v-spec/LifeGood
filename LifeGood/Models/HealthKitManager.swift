import Foundation
import HealthKit
import CoreLocation

// MARK: - Apple 健康聯動（v25.352）
//
// 讀：體重、身高、血壓、心率、訓練（HKWorkout，含路徑）
// 寫：體重、訓練（HKWorkout + HKWorkoutRoute）
//
// 重要限制：HealthKit **沒有**「組數／次數／負荷」的標準欄位。重量訓練寫回去
// 只會是一段時間與消耗熱量，Apple 健康與其他 App 看不到「20 下 3 組」；
// 反過來從 Apple Watch 匯入的重訓也只有時間與熱量，動作明細要自己補。
// 這一點在健康頁與設定頁都有明講，不要讓使用者以為明細會同步。

@MainActor
final class HealthKitManager: ObservableObject {

    static let shared = HealthKitManager()

    @Published private(set) var isAvailable = HKHealthStore.isHealthDataAvailable()
    @Published private(set) var isAuthorized = false
    @Published private(set) var lastError: String?

    private let store = HKHealthStore()

    private init() {}

    // MARK: 型別

    private var bodyMassType: HKQuantityType? { HKQuantityType.quantityType(forIdentifier: .bodyMass) }
    private var heightType: HKQuantityType? { HKQuantityType.quantityType(forIdentifier: .height) }
    private var systolicType: HKQuantityType? { HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic) }
    private var diastolicType: HKQuantityType? { HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic) }
    private var heartRateType: HKQuantityType? { HKQuantityType.quantityType(forIdentifier: .heartRate) }
    private var energyType: HKQuantityType? { HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) }
    private var distanceType: HKQuantityType? { HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) }

    private var readTypes: Set<HKObjectType> {
        var set: Set<HKObjectType> = [HKObjectType.workoutType()]
        for t in [bodyMassType, heightType, systolicType, diastolicType, heartRateType, energyType, distanceType] {
            if let t { set.insert(t) }
        }
        set.insert(HKSeriesType.workoutRoute())
        return set
    }

    private var writeTypes: Set<HKSampleType> {
        var set: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let bodyMassType { set.insert(bodyMassType) }
        if let energyType { set.insert(energyType) }
        if let distanceType { set.insert(distanceType) }
        set.insert(HKSeriesType.workoutRoute())
        return set
    }

    // MARK: 授權

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            isAvailable = false
            lastError = "這台裝置不支援「健康」App。"
            return
        }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            isAuthorized = true
            lastError = nil
        } catch {
            isAuthorized = false
            lastError = error.localizedDescription
        }
    }

    /// 寫入權限查得到，讀取權限 Apple 刻意查不到（避免 App 反推使用者有沒有資料）。
    /// 所以這裡只用來顯示「有沒有給過寫入授權」。
    var canWriteWorkout: Bool {
        store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    // MARK: - 讀：體重與量測

    struct MeasurementSample {
        let date: Date
        let weightKg: Double?
        let heightCm: Double?
        let systolic: Int?
        let diastolic: Int?
        let heartRate: Int?
    }

    /// 抓 since 之後的體重（一天只留最後一筆，避免一天量三次就長出三列）
    func fetchBodyMass(since: Date) async -> [(date: Date, kg: Double)] {
        guard let type = bodyMassType else { return [] }
        let samples = await quantitySamples(type: type, since: since)
        var byDay: [Date: (Date, Double)] = [:]
        let cal = Calendar.current
        for s in samples {
            let kg = s.quantity.doubleValue(for: .gramUnit(with: .kilo))
            let day = cal.startOfDay(for: s.endDate)
            if let existing = byDay[day], existing.0 >= s.endDate { continue }
            byDay[day] = (s.endDate, kg)
        }
        return byDay.values.map { (date: $0.0, kg: $0.1) }.sorted { $0.date < $1.date }
    }

    func fetchLatestHeightCm() async -> Double? {
        guard let type = heightType else { return nil }
        let samples = await quantitySamples(type: type, since: Date.distantPast, limit: 1, newestFirst: true)
        guard let s = samples.first else { return nil }
        return s.quantity.doubleValue(for: .meterUnit(with: .centi))
    }

    /// 血壓（收縮／舒張配對）與心率，since 之後
    func fetchVitals(since: Date) async -> [MeasurementSample] {
        guard let sysType = systolicType, let diaType = diastolicType else { return [] }
        let sys = await quantitySamples(type: sysType, since: since)
        let dia = await quantitySamples(type: diaType, since: since)
        let hr = heartRateType == nil ? [] : await quantitySamples(type: heartRateType!, since: since)

        let unit = HKUnit.millimeterOfMercury()
        // 以「同一分鐘」把收縮壓與舒張壓配對——血壓計都是一次寫入兩筆
        var diaByMinute: [Date: Double] = [:]
        for d in dia { diaByMinute[Self.minuteKey(d.endDate)] = d.quantity.doubleValue(for: unit) }
        var hrByMinute: [Date: Double] = [:]
        let bpm = HKUnit.count().unitDivided(by: .minute())
        for h in hr { hrByMinute[Self.minuteKey(h.endDate)] = h.quantity.doubleValue(for: bpm) }

        return sys.compactMap { s in
            let key = Self.minuteKey(s.endDate)
            guard let d = diaByMinute[key] else { return nil }
            return MeasurementSample(
                date: s.endDate,
                weightKg: nil, heightCm: nil,
                systolic: Int(s.quantity.doubleValue(for: unit).rounded()),
                diastolic: Int(d.rounded()),
                heartRate: hrByMinute[key].map { Int($0.rounded()) })
        }.sorted { $0.date < $1.date }
    }

    // MARK: - 讀：訓練

    struct ImportedWorkout {
        let uuid: String
        let start: Date
        let end: Date
        let activityName: String
        let isCardio: Bool
        let distanceKm: Double
        let energyKcal: Double
        let route: [RoutePoint]
    }

    /// 匯入 since 之後的訓練。excluding 傳已經有的 HealthKit UUID，避免重複匯入。
    func fetchWorkouts(since: Date, excluding: Set<String>) async -> [ImportedWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let workouts: [HKWorkout] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate,
                                  limit: 200, sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }
        var out: [ImportedWorkout] = []
        for w in workouts {
            let id = w.uuid.uuidString
            if excluding.contains(id) { continue }
            let km = Self.distanceKm(of: w)
            let kcal = Self.energyKcal(of: w)
            let route = await fetchRoute(for: w)
            out.append(ImportedWorkout(
                uuid: id, start: w.startDate, end: w.endDate,
                activityName: Self.name(for: w.workoutActivityType),
                isCardio: Self.isCardio(w.workoutActivityType),
                distanceKm: km, energyKcal: kcal, route: route))
        }
        return out
    }

    /// 取這筆訓練的 GPS 路徑（抽稀成每 8 公尺一點，與 App 內自己錄的一致）
    private func fetchRoute(for workout: HKWorkout) async -> [RoutePoint] {
        let routes: [HKWorkoutRoute] = await withCheckedContinuation { cont in
            let p = HKQuery.predicateForObjects(from: workout)
            let q = HKSampleQuery(sampleType: HKSeriesType.workoutRoute(), predicate: p,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
            }
            store.execute(q)
        }
        guard let route = routes.first else { return [] }
        let locations: [CLLocation] = await withCheckedContinuation { cont in
            var acc: [CLLocation] = []
            let q = HKWorkoutRouteQuery(route: route) { _, batch, done, _ in
                if let batch { acc.append(contentsOf: batch) }
                if done { cont.resume(returning: acc) }
            }
            store.execute(q)
        }
        return Self.thin(locations, start: workout.startDate)
    }

    // MARK: - 寫

    func saveBodyMass(kg: Double, date: Date) async -> Bool {
        guard let type = bodyMassType, kg > 0 else { return false }
        let q = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg)
        let sample = HKQuantitySample(type: type, quantity: q, start: date, end: date)
        do { try await store.save(sample); return true }
        catch { lastError = error.localizedDescription; return false }
    }

    /// 把一次訓練寫進 Apple 健康。回傳 HKWorkout 的 UUID（存回 session 避免重複寫）。
    /// 只寫得進去時間、距離與熱量——組數次數負荷 HealthKit 沒有欄位可放。
    func saveWorkout(_ session: WorkoutSession, bodyWeightKg: Double?) async -> String? {
        let start = session.date
        let minutes = session.durationMinutes > 0
            ? session.durationMinutes
            : max(1, session.totalCardioMinutes)
        let end = start.addingTimeInterval(minutes * 60)
        let cardio = session.cardioExercises.first
        let activity: HKWorkoutActivityType = cardio == nil
            ? .traditionalStrengthTraining
            : Self.activityType(forName: cardio?.name ?? "")

        let config = HKWorkoutConfiguration()
        config.activityType = activity
        config.locationType = cardio == nil ? .indoor : .outdoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            _ = try await builder.beginCollection(at: start)

            var samples: [HKSample] = []
            let km = session.totalDistanceKm
            if km > 0, let distanceType {
                samples.append(HKQuantitySample(
                    type: distanceType,
                    quantity: HKQuantity(unit: .meterUnit(with: .kilo), doubleValue: km),
                    start: start, end: end))
            }
            let kcal = session.activeEnergyKcal > 0
                ? session.activeEnergyKcal
                : Self.estimateKcal(session: session, minutes: minutes, bodyWeightKg: bodyWeightKg)
            if kcal > 0, let energyType {
                samples.append(HKQuantitySample(
                    type: energyType,
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                    start: start, end: end))
            }
            if !samples.isEmpty { _ = try await builder.addSamples(samples) }

            // 明細塞不進 HealthKit 的欄位，至少用 metadata 留一行摘要
            let summary = session.exercises
                .map { "\($0.name) \($0.summary(bodyWeightKg: bodyWeightKg))" }
                .joined(separator: "；")
            if !summary.isEmpty {
                _ = try await builder.addMetadata([HKMetadataKeyWorkoutBrandName: "美好人生",
                                                   "LifeGoodSummary": summary])
            }

            _ = try await builder.endCollection(at: end)
            guard let workout = try await builder.finishWorkout() else { return nil }

            // 有路徑就一併寫成 HKWorkoutRoute
            if let ex = session.firstRouteExercise, ex.hasRoute {
                let locations = ex.route.map { p in
                    CLLocation(coordinate: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon),
                               altitude: p.alt, horizontalAccuracy: 5, verticalAccuracy: 5,
                               timestamp: start.addingTimeInterval(p.t))
                }
                if locations.count >= 2 {
                    let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
                    _ = try await routeBuilder.insertRouteData(locations)
                    _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
                }
            }
            return workout.uuid.uuidString
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - 共用查詢

    private func quantitySamples(type: HKQuantityType, since: Date,
                                 limit: Int = HKObjectQueryNoLimit,
                                 newestFirst: Bool = false) async -> [HKQuantitySample] {
        await withCheckedContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: .strictStartDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: !newestFirst)
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: limit, sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }
    }

    // MARK: - 工具

    private static func minuteKey(_ d: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month, .day, .hour, .minute], from: d)) ?? d
    }

    private static func distanceKm(of w: HKWorkout) -> Double {
        let types: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
        for id in types {
            guard let t = HKQuantityType.quantityType(forIdentifier: id),
                  let stat = w.statistics(for: t)?.sumQuantity() else { continue }
            let km = stat.doubleValue(for: .meterUnit(with: .kilo))
            if km > 0 { return km }
        }
        return 0
    }

    private static func energyKcal(of w: HKWorkout) -> Double {
        guard let t = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
              let stat = w.statistics(for: t)?.sumQuantity() else { return 0 }
        return stat.doubleValue(for: .kilocalorie())
    }

    /// 沒有熱量資料時的粗估：MET × 體重 × 小時。只是給個數字，不是醫療級估算。
    private static func estimateKcal(session: WorkoutSession, minutes: Double,
                                     bodyWeightKg: Double?) -> Double {
        guard let w = bodyWeightKg, w > 0, minutes > 0 else { return 0 }
        let met: Double = session.cardioExercises.isEmpty ? 5.0 : 8.0
        return met * w * (minutes / 60)
    }

    private static func isCardio(_ t: HKWorkoutActivityType) -> Bool {
        switch t {
        case .running, .walking, .cycling, .swimming, .hiking, .elliptical, .rowing, .stairClimbing:
            return true
        default:
            return false
        }
    }

    private static func name(for t: HKWorkoutActivityType) -> String {
        switch t {
        case .running: return "跑步"
        case .walking: return "走路"
        case .cycling: return "騎車"
        case .swimming: return "游泳"
        case .hiking: return "健行"
        case .elliptical: return "橢圓機"
        case .rowing: return "划船機"
        case .stairClimbing: return "爬樓梯"
        case .traditionalStrengthTraining: return "重量訓練"
        case .functionalStrengthTraining: return "功能性訓練"
        case .coreTraining: return "核心訓練"
        case .highIntensityIntervalTraining: return "高強度間歇"
        case .yoga: return "瑜伽"
        case .flexibility: return "伸展"
        default: return "訓練"
        }
    }

    private static func activityType(forName name: String) -> HKWorkoutActivityType {
        if name.contains("跑") { return .running }
        if name.contains("走") || name.contains("健走") { return .walking }
        if name.contains("騎") || name.contains("單車") || name.contains("自行車") { return .cycling }
        if name.contains("游") { return .swimming }
        if name.contains("登山") || name.contains("健行") { return .hiking }
        return .running
    }

    /// HealthKit 的路徑點很密（1 秒一點），抽稀成至少 8 公尺一點再存
    private static func thin(_ locations: [CLLocation], start: Date) -> [RoutePoint] {
        var out: [RoutePoint] = []
        var last: CLLocation?
        for loc in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            if let l = last, loc.distance(from: l) < 8 { continue }
            out.append(RoutePoint(lat: loc.coordinate.latitude,
                                  lon: loc.coordinate.longitude,
                                  t: loc.timestamp.timeIntervalSince(start),
                                  alt: loc.altitude))
            last = loc
            if out.count >= 3000 { break }
        }
        return out
    }
}
