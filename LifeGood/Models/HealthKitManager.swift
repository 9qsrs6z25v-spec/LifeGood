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
//
// [v25.551] 寫訓練：結束時間改用記錄器的真正結束時間（WorkoutSession.workoutEnd，有驗證）；
// 路線另外包一層 do/catch、每一點的時間夾在開始～結束之間，路線寫不進去也不連累整筆（照樣回傳編號）。
//
// [v25.552] 一套數字（WorkoutFacts／WorkoutSport）：
// - 寫訓練的運動種類改看這一趟的主運動（WorkoutSession.primarySport）：健走寫成步行、登山寫成健行、
//   「其他有氧」寫成混合有氧（以前名字對不上一律當跑步）；地點只有重訓寫室內、有路線寫戶外、其他不知道。
// - 沒有量到的大卡改用 MET 表估（WorkoutFacts.estimatedKcal：依運動與時速；健走 60 分鐘 72.4 公斤約 181，以前一律 8 MET＝576）。
// - 匯入的名稱統一：手錶的「走路」叫「健走」、「健行」叫「登山」（跟 App 記的同一個名字，動作統計同一列）。
// - 手錶路線滿 3,000 點改成「隔一個丟一個、間距加倍」繼續抽，不再截斷（以前手錶騎 60 公里，地圖畫到 24 公里就斷）。

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
        /// [v25.552] 一套數字的運動種類（手錶的「走路」＝健走、「健行」＝登山）；瑜伽之類不是有氧也不是重訓的是 nil
        let sport: WorkoutSport?
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
                distanceKm: km, energyKcal: kcal, route: route,
                sport: Self.sport(for: w.workoutActivityType)))
        }
        return out
    }

    /// 取這筆訓練的 GPS 路徑（抽稀成至少 8 公尺一點，與 App 內自己錄的一致；
    /// [v25.552] 很長的路線滿 3,000 點就放寬間距、繼續抽到終點，不截斷，見 thin）
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
        // [v25.551] 結束時間：App 內即時紀錄用記錄器的真正結束時間（endedAt，對不上就退回「開始＋時間」，見 workoutEnd）。
        // v1 還沒寫暫停事件，所以「健身」App 顯示的時間會含暫停（v4 補 HKWorkoutEvent）。
        let end = session.workoutEnd(movingMinutes: minutes)
        // [v25.552] 運動種類看這一趟的主運動（一套數字 WorkoutSport）：健走＝步行、登山＝健行、其他有氧＝混合有氧
        // （游泳照名字），不再名字對不上就當跑步。地點：重訓室內、有路線戶外、其他不知道（跑步機、補記的不亂寫戶外）
        let sport = session.primarySport
        let activity = Self.activityType(for: sport, name: session.cardioExercises.first?.name ?? "")

        let config = HKWorkoutConfiguration()
        config.activityType = activity
        config.locationType = sport == .strength
            ? .indoor
            : (session.firstRouteExercise != nil ? .outdoor : .unknown)

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
            // [v25.552] 沒有量到（也沒存估好的）大卡：用 MET 表依運動與時速估（跟健康頁畫面同一支）；沒有體重就不寫大卡
            let kcal = session.activeEnergyKcal > 0
                ? session.activeEnergyKcal
                : (WorkoutFacts.estimatedKcal(session, bodyWeightKg: bodyWeightKg) ?? 0)
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

            // [v25.551] 路線自己 do/catch：運動已經寫進 Apple 健康了，路線失敗也一定要回傳編號，
            // 不然 App 沒記下編號，之後編輯再存（WorkoutHealthWriter.push 只看編號）會重複寫一筆
            if let ex = session.firstRouteExercise, ex.hasRoute {
                do {
                    try await saveRoute(ex.route, start: start, end: end, for: workout)
                } catch {
                    lastError = "路線沒寫進 Apple 健康：" + error.localizedDescription
                }
            }
            return workout.uuid.uuidString
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// [v25.551] 把 App 記的路線寫成 HKWorkoutRoute。每一點的時間夾在運動的開始～結束之間
    /// （超出運動時間的路線點 Apple 健康不收）。v25.352～v25.550 這段從沒真的跑過：App 記的路線永遠不到 2 點。
    private func saveRoute(_ route: [RoutePoint], start: Date, end: Date, for workout: HKWorkout) async throws {
        var locations: [CLLocation] = []
        locations.reserveCapacity(route.count)
        let last = max(start, end)
        for p in route {
            let t = min(max(start.addingTimeInterval(p.t), start), last)
            let coordinate = CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon)
            locations.append(CLLocation(coordinate: coordinate,
                                        altitude: p.alt, horizontalAccuracy: 5, verticalAccuracy: 5,
                                        timestamp: t))
        }
        guard locations.count >= 2 else { return }
        let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
        _ = try await routeBuilder.insertRouteData(locations)
        _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
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
        case .walking: return "健走"        // [v25.552] 以前「走路」：跟 App 記的「健走」分成兩列（U1 C10）
        case .cycling: return "騎車"
        case .swimming: return "游泳"
        case .hiking: return "登山"         // [v25.552] 以前「健行」：跟 App 的「登山」同一個名字
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

    /// [v25.552] Apple 健康的運動種類 → 一套數字的 WorkoutSport（匯入時存進 WorkoutExercise.sport）。
    /// 走路併進健走、健行併進登山；游泳、橢圓機、划船機、爬樓梯＝其他有氧；重訓三種＝重訓；其他（瑜伽、伸展…）nil
    static func sport(for t: HKWorkoutActivityType) -> WorkoutSport? {
        switch t {
        case .running: return .run
        case .walking: return .walk
        case .cycling: return .bike
        case .hiking: return .hike
        case .swimming, .elliptical, .rowing, .stairClimbing: return .other
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining: return .strength
        default: return nil
        }
    }

    /// [v25.552] 寫回 Apple 健康的運動種類：跟一套數字同一張表（WorkoutSport）。其他有氧不再一律當跑步（U1 C11）
    private static func activityType(for sport: WorkoutSport, name: String) -> HKWorkoutActivityType {
        switch sport {
        case .run: return .running
        case .walk: return .walking
        case .bike: return .cycling
        case .hike: return .hiking
        case .strength: return .traditionalStrengthTraining
        case .other: return name.contains("游") ? .swimming : .mixedCardio
        }
    }

    /// HealthKit 的路徑點很密（1 秒一點），抽稀成至少 8 公尺一點；[v25.552] 滿 3,000 點就隔一個丟一個、間距加倍
    /// （以前直接截斷：手錶騎 60 公里，地圖畫到 24 公里就斷）
    private static func thin(_ locations: [CLLocation], start: Date) -> [RoutePoint] {
        var out: [RoutePoint] = []
        var last: CLLocation?
        var step: Double = 8
        for loc in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            if let l = last, loc.distance(from: l) < step { continue }
            out.append(RoutePoint(lat: loc.coordinate.latitude,
                                  lon: loc.coordinate.longitude,
                                  t: loc.timestamp.timeIntervalSince(start),
                                  alt: loc.altitude))
            last = loc
            if out.count >= 3000, let lastPoint = out.last {
                // 留偶數位置的點（含起點）；最後一點落在奇數位置就補回來，線一定畫到現在這一點
                var kept: [RoutePoint] = []
                kept.reserveCapacity(out.count / 2 + 2)
                for (i, p) in out.enumerated() where i % 2 == 0 { kept.append(p) }
                if (out.count - 1) % 2 != 0 { kept.append(lastPoint) }
                out = kept
                step *= 2
            }
        }
        return out
    }
}
