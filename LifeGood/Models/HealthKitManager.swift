import Foundation
import HealthKit
import CoreLocation

// MARK: - Apple 健康聯動（v25.352）
//
// 讀：體重、身高、血壓、心率、訓練（HKWorkout，含路徑、爬升、騎車距離）
// 寫：訓練（含路線、暫停、爬升）
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
//
// [v25.554] 健康 v4：Apple 健康讀寫都對（health/build/v4/brief.md §6 G1）
// - 寫：開始、結束是真正按開始和完成的時間，每次暫停寫一組「暫停／繼續」事件（WorkoutFacts.healthPauses），
//   「健身」App 的運動時間就扣掉暫停（06:00 開始、06:20–06:30 暫停、06:52 結束 → 42 分鐘）；暫停加起來跟
//   「結束−開始−移動時間」對不上（編輯改過時間）的不寫，免得健身 App 的時間比 LifeGood 短。
//   距離照每個有氧動作的運動分種類寫（WorkoutFacts.healthDistance）：跑步、健走、登山＝步行＋跑步，騎車＝騎車距離，
//   重訓、其他有氧不寫（以前一律寫成步行＋跑步，騎車的公里灌進「健康」的步行距離）。
//   爬升知道才寫（WorkoutFacts.climb，0＝平路也寫）：運動的附註 HKMetadataKeyElevationAscended。
//   路線用簡化前的點（fullRoute，WorkoutRouteStash 拿來的），先用這筆運動 builder 的 seriesBuilder(for:)
//   （Apple「Creating a workout route」的寫法），拿不到或寫失敗再用獨立的 HKWorkoutRouteBuilder 試一次；路線失敗照樣回傳編號。
// - 讀：用結束時間篩（跟［since, 現在］重疊；以前要開始時間在 since 之後，07:00 開始、07:30 同步過、08:00 跑完的那趟永遠帶不進來）；
//   移動時間用 HKWorkout.duration（扣掉手錶的暫停）、手錶量的爬升（沒量是 nil，不是 0）、騎車距離（多要一項讀取權限）；
//   LifeGood 自己寫進去的不帶進來（isOwn：來源是自己這個 App）。
// - 新 API：依編號讀、依時間讀、讀一筆路線、刪一筆（連 LifeGood 寫的距離、大卡、路線一起刪）、還有沒同意過的權限。
// - 寫的權限拿掉體重（寫體重那一支全 App 沒人叫，刪掉）；讀寫都多「騎車距離」。
// - 打包出來的 Info.plist 沒有兩句健康說明字（hasUsageDescriptions）就整個不碰 HealthKit：isAvailable 是 false、
//   不叫 requestAuthorization（少了說明字會閃退）、讀寫都直接回空的。

@MainActor
final class HealthKitManager: ObservableObject {

    static let shared = HealthKitManager()

    /// [v25.554] 裝置支援「健康」而且打包出來的 Info.plist 有兩句健康說明字才是 true
    @Published private(set) var isAvailable = HKHealthStore.isHealthDataAvailable() && HealthKitManager.hasUsageDescriptions
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
    /// [v25.554] 騎車距離：讀（手錶騎車的公里；以前沒要這項，帶進來可能是 0）、寫（LifeGood 騎車寫這種，不再灌進步行＋跑步）
    private var cyclingType: HKQuantityType? { HKQuantityType.quantityType(forIdentifier: .distanceCycling) }

    private var readTypes: Set<HKObjectType> {
        var set: Set<HKObjectType> = [HKObjectType.workoutType()]
        for t in [bodyMassType, heightType, systolicType, diastolicType, heartRateType, energyType, distanceType, cyclingType] {
            if let t { set.insert(t) }
        }
        set.insert(HKSeriesType.workoutRoute())
        return set
    }

    /// [v25.554] 拿掉體重（全 App 沒有寫體重的地方）、多騎車距離
    private var writeTypes: Set<HKSampleType> {
        var set: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let energyType { set.insert(energyType) }
        if let distanceType { set.insert(distanceType) }
        if let cyclingType { set.insert(cyclingType) }
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
        // [v25.554] 打包出來的 Info.plist 少了健康說明字：叫 requestAuthorization 會閃退，整個不碰
        guard Self.hasUsageDescriptions else {
            isAvailable = false
            lastError = "這個版本少了「健康」的說明字，Apple 健康先關著。"
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
        guard isAvailable else { return false }
        return store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
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
        guard isAvailable, let type = bodyMassType else { return [] }
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
        guard isAvailable, let type = heightType else { return nil }
        let samples = await quantitySamples(type: type, since: Date.distantPast, limit: 1, newestFirst: true)
        guard let s = samples.first else { return nil }
        return s.quantity.doubleValue(for: .meterUnit(with: .centi))
    }

    /// 血壓（收縮／舒張配對）與心率，since 之後
    func fetchVitals(since: Date) async -> [MeasurementSample] {
        guard isAvailable, let sysType = systolicType, let diaType = diastolicType else { return [] }
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
        /// [v25.554] var：依編號、依時間讀回時先不帶路線（空的），要的時候再 fetchRoute(uuid:)
        var route: [RoutePoint]
        /// [v25.552] 一套數字的運動種類（手錶的「走路」＝健走、「健行」＝登山）；瑜伽之類不是有氧也不是重訓的是 nil
        let sport: WorkoutSport?
        /// [v25.554] 移動時間（分鐘）：HKWorkout.duration（扣掉手錶的暫停）；以前用結束減開始（含暫停，配速會變慢）
        let movingMinutes: Double
        /// [v25.554] 手錶量的爬升（公尺，HKMetadataKeyElevationAscended）；沒量是 nil（不是 0）
        let climbM: Double?
        /// [v25.554] LifeGood 自己寫進去的（同步不帶進來；刪除、〔更新〕才刪得掉）
        let isOwn: Bool
    }

    /// 匯入 since 之後的訓練（帶路線）。excluding 傳已經有的 HealthKit UUID，避免重複匯入。
    /// [v25.554] 用結束時間篩：跟［since, 現在］重疊的都算（options 是空的；以前要開始時間在 since 之後，
    /// 手錶 07:00 開始、07:30 同步過、08:00 跑完的那一趟永遠帶不進來）；LifeGood 自己寫的跳過
    /// （「只刪 LifeGood 這筆」留在 Apple 健康的那筆，不會被當成手錶紀錄帶回來）
    func fetchWorkouts(since: Date, excluding: Set<String>) async -> [ImportedWorkout] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: [])
        let found = await workouts(matching: predicate, limit: 200)
        var out: [ImportedWorkout] = []
        for w in found {
            if excluding.contains(w.uuid.uuidString) { continue }
            if Self.isOwn(w) { continue }
            let route = await fetchRoute(for: w)
            out.append(makeImported(w, route: route))
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
            var finished = false
            let q = HKWorkoutRouteQuery(route: route) { _, batch, done, error in
                if finished { return }
                if let batch { acc.append(contentsOf: batch) }
                // [v25.554] 出錯時 done 不一定是 true：也要結束（不然一直等、同步卡在「同步中…」）；
                // 讀到一半出錯的不要（只有半條線，當成沒有，路線晚到那段下次再找）
                if done || error != nil {
                    finished = true
                    cont.resume(returning: error == nil ? acc : [])
                }
            }
            store.execute(q)
        }
        return Self.thin(locations, start: workout.startDate)
    }

    // MARK: - 寫

    /// 把一次訓練寫進 Apple 健康。回傳 HKWorkout 的 UUID（存回 session 避免重複寫）。
    /// 只寫得進去時間、距離與熱量——組數次數負荷 HealthKit 沒有欄位可放。
    /// [v25.554] fullRoute：簡化前的點（WorkoutRouteStash；nil 或不到 2 點就用存下來的路線）；
    /// 暫停寫成事件、距離分步行＋跑步／騎車、爬升寫進附註、路線用 seriesBuilder(for:)（見檔頭）
    func saveWorkout(_ session: WorkoutSession, bodyWeightKg: Double?, fullRoute: [RoutePoint]? = nil) async -> String? {
        guard isAvailable else {
            lastError = "Apple 健康現在不能用（這台裝置不支援，或這個版本少了「健康」的說明字）。"
            return nil
        }
        // 上一次寫的問題（暫停、路線沒寫進去）不要一直掛在設定小頁：這一次有問題下面會再記
        lastError = nil
        let start = session.date
        let minutes = session.durationMinutes > 0
            ? session.durationMinutes
            : max(1, session.totalCardioMinutes)
        // [v25.551] 結束時間：App 內即時紀錄用記錄器的真正結束時間（endedAt，對不上就退回「開始＋時間」，見 workoutEnd）。
        // [v25.554] 中間的暫停寫成事件（pausesToWrite），「健身」App 的運動時間＝結束−開始−暫停＝移動時間
        let end = session.workoutEnd(movingMinutes: minutes)
        // [v25.552] 運動種類看這一趟的主運動（一套數字 WorkoutSport）：健走＝步行、登山＝健行、其他有氧＝混合有氧
        // （游泳照名字），不再名字對不上就當跑步。地點：重訓室內、有路線戶外、其他不知道（跑步機、補記的不亂寫戶外）
        let sport = session.primarySport
        let activity = Self.activityType(for: sport, name: session.cardioExercises.first?.name ?? "")
        // [v25.554] 路線用簡化前的點（比較密，「健身」App 的線比較順）；沒有（App 重開過、〔更新〕）用存下來的簡化路線
        let full = fullRoute ?? []
        let routePoints = full.count >= 2 ? full : (session.firstRouteExercise?.route ?? [])
        let routeLocations = Self.locations(routePoints, start: start, end: end)

        let config = HKWorkoutConfiguration()
        config.activityType = activity
        config.locationType = sport == .strength
            ? .indoor
            : (routeLocations.count >= 2 ? .outdoor : .unknown)

        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            _ = try await builder.beginCollection(at: start)

            // [v25.554] 路線 builder 跟著這筆運動拿（Apple「Creating a workout route」：seriesBuilder(for:) 轉 HKWorkoutRouteBuilder，
            // 運動進行中插點、存好運動之後 finishRoute）。點在這裡就插好（自己 do/catch，不連累整筆）；
            // 轉型失敗（nil）或插不進去，存好運動之後改用獨立的 HKWorkoutRouteBuilder（saveRoute）
            var seriesRoute: HKWorkoutRouteBuilder?
            if routeLocations.count >= 2,
               let routeBuilder = builder.seriesBuilder(for: HKSeriesType.workoutRoute()) as? HKWorkoutRouteBuilder {
                do {
                    _ = try await routeBuilder.insertRouteData(routeLocations)
                    seriesRoute = routeBuilder
                } catch {
                    seriesRoute = nil
                }
            }

            var samples: [HKSample] = []
            // [v25.554] 距離分種類：跑走登山＝步行＋跑步、騎車＝騎車距離、重訓與其他有氧不寫（distanceToWrite）
            let km = Self.distanceToWrite(session)
            if km.walkingRunning > 0, let distanceType {
                samples.append(HKQuantitySample(
                    type: distanceType,
                    quantity: HKQuantity(unit: .meterUnit(with: .kilo), doubleValue: km.walkingRunning),
                    start: start, end: end))
            }
            if km.cycling > 0, let cyclingType {
                samples.append(HKQuantitySample(
                    type: cyclingType,
                    quantity: HKQuantity(unit: .meterUnit(with: .kilo), doubleValue: km.cycling),
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

            // [v25.554] 每次暫停一個「暫停」＋一個「繼續」事件（零長度的時間點）。事件自己 do/catch：
            // 寫不進去頂多「健身」App 的時間含暫停，不能連累整筆（沒存進去比時間不準更糟）
            let pauses = Self.pausesToWrite(session, start: start, end: end, movingMinutes: minutes)
            if !pauses.isEmpty {
                var events: [HKWorkoutEvent] = []
                for p in pauses {
                    events.append(HKWorkoutEvent(type: .pause,
                                                 dateInterval: DateInterval(start: p.start, duration: 0),
                                                 metadata: nil))
                    events.append(HKWorkoutEvent(type: .resume,
                                                 dateInterval: DateInterval(start: p.end, duration: 0),
                                                 metadata: nil))
                }
                do {
                    _ = try await builder.addWorkoutEvents(events)
                } catch {
                    lastError = "暫停沒寫進 Apple 健康（運動時間會含暫停）：" + error.localizedDescription
                }
            }

            // 明細塞不進 HealthKit 的欄位，至少用 metadata 留一行摘要；[v25.554] 爬升知道就寫（0＝平路也寫）
            var meta: [String: Any] = [HKMetadataKeyWorkoutBrandName: "美好人生"]
            let summary = session.exercises
                .map { "\($0.name) \($0.summary(bodyWeightKg: bodyWeightKg))" }
                .joined(separator: "；")
            if !summary.isEmpty { meta["LifeGoodSummary"] = summary }
            if let climb = Self.climbToWrite(session) {
                meta[HKMetadataKeyElevationAscended] = HKQuantity(unit: .meter(), doubleValue: climb)
            }
            _ = try await builder.addMetadata(meta)

            _ = try await builder.endCollection(at: end)
            guard let workout = try await builder.finishWorkout() else {
                // 文件：沒有錯誤卻是 nil＝存好了，但手機鎖著讀不到那一筆
                lastError = "存進 Apple 健康時手機鎖著，讀不到那一筆的編號；打開「健身」App 看看有沒有這一趟。"
                return nil
            }

            // [v25.551] 路線自己 do/catch（saveRoute 不丟錯）：運動已經寫進 Apple 健康了，路線失敗也一定要回傳編號，
            // 不然 App 沒記下編號，之後再存會重複寫一筆
            if routeLocations.count >= 2 {
                await saveRoute(routeLocations, for: workout, seriesBuilder: seriesRoute)
            }
            // 路線寫完之前，運動的 builder 一定要還在（seriesBuilder 拿來的路線 builder 是它的）：這裡再碰它一下
            _ = builder.workoutConfiguration
            return workout.uuid.uuidString
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// [v25.551] 把 App 記的路線寫成 HKWorkoutRoute。每一點的時間夾在運動的開始～結束之間
    /// （超出運動時間的路線點 Apple 健康不收）。v25.352～v25.550 這段從沒真的跑過：App 記的路線永遠不到 2 點。
    /// [v25.554] 先收尾運動 builder 給的路線 builder（seriesBuilder(for:)，點在運動存好之前已經插好）；
    /// 沒有或失敗再用獨立的 HKWorkoutRouteBuilder 試一次（v1～v3 的寫法，實機有路線）——試之前先看這筆運動是不是
    /// 已經有路線（文件沒寫 finishWorkout 會不會順便收尾 series builder；有就不要再寫第二條）。錯誤自己吃掉、記在 lastError
    private func saveRoute(_ locations: [CLLocation], for workout: HKWorkout,
                           seriesBuilder: HKWorkoutRouteBuilder?) async {
        guard locations.count >= 2 else { return }
        if let routeBuilder = seriesBuilder {
            do {
                _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
                return
            } catch {
                // 沒收尾成功：下面先看有沒有路線，再用獨立的試一次
            }
        }
        let attached = await samples(of: HKSeriesType.workoutRoute(),
                                     matching: HKQuery.predicateForObjects(from: workout))
        if !attached.isEmpty { return }
        do {
            let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
            _ = try await routeBuilder.insertRouteData(locations)
            _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
        } catch {
            lastError = "路線沒寫進 Apple 健康：" + error.localizedDescription
        }
    }

    // MARK: - v25.554 健康 v4 的新 API
    // 名字、參數、回傳型別照 build/v4/brief.md §5 名稱表，不准改（G2 的 HealthSyncCenter 照這幾支寫）

    /// 刪 Apple 健康裡一筆運動的結果
    enum DeleteResult: Equatable {
        /// 刪掉了（連它的距離、大卡、路線）
        case deleted
        /// Apple 健康裡已經沒有這一筆（使用者在「健康」App 刪過）；沒有讀取權限時也是這樣
        case notFound
        /// 不是 LifeGood 寫的（手錶記的）：Apple 只讓 App 刪自己寫的
        case notOurs
        /// 沒刪成功（沒有寫入權限、其他錯誤）：一句給使用者看的話
        case failed(String)
    }

    /// 打包出來的 Info.plist 有沒有兩句健康說明字。沒有就整個不碰 HealthKit（少了說明字 requestAuthorization 會閃退，
    /// 同 RunTracker.hasLocationBackgroundMode、v25.533 的教訓）。nonisolated：只讀 Bundle，哪裡都能叫（屬性初值也能用）
    nonisolated static var hasUsageDescriptions: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSHealthShareUsageDescription") != nil
            && Bundle.main.object(forInfoDictionaryKey: "NSHealthUpdateUsageDescription") != nil
    }

    /// 還有沒同意過的種類（v4 新加的騎車距離）：true＝再呼叫 requestAuthorization 會跳同意畫面（健康頁要確認〔去同意〕）。
    /// 只是查，不跳任何畫面；查不到（出錯）當作不用
    func needsAuthorizationRequest() async -> Bool {
        guard isAvailable else { return false }
        do {
            let status = try await store.statusForAuthorizationRequest(toShare: writeTypes, read: readTypes)
            return status == .shouldRequest
        } catch {
            return false
        }
    }

    /// 依編號讀回（不帶路線，route 是空的；LifeGood 自己寫的也讀，isOwn 標出來）。讀不到的（刪了、沒權限）就不在結果裡
    func fetchWorkouts(uuids: [String]) async -> [ImportedWorkout] {
        guard isAvailable else { return [] }
        var seen = Set<UUID>()
        var ids: [UUID] = []
        for s in uuids {
            guard let id = UUID(uuidString: s), !seen.contains(id) else { continue }
            seen.insert(id)
            ids.append(id)
        }
        var out: [ImportedWorkout] = []
        var i = 0
        while i < ids.count {
            let batch = Set(ids[i..<min(i + 200, ids.count)])
            i += 200
            let predicate = HKQuery.predicateForObjects(with: batch)
            let found = await workouts(matching: predicate, limit: HKObjectQueryNoLimit)
            for w in found { out.append(makeImported(w, route: [])) }
        }
        return out
    }

    /// 一段時間裡（跟［from, to］重疊）的運動，不帶路線；跳過 LifeGood 自己寫的（舊紀錄找回路線用）
    func fetchWorkouts(from start: Date, to end: Date) async -> [ImportedWorkout] {
        guard isAvailable, end > start else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let found = await workouts(matching: predicate, limit: 500)
        var out: [ImportedWorkout] = []
        for w in found where !Self.isOwn(w) {
            out.append(makeImported(w, route: []))
        }
        return out
    }

    /// 一筆運動的路線（抽稀規則同匯入：8 公尺一點、滿 3,000 點放寬）；沒有路線、找不到回空的
    func fetchRoute(uuid: String) async -> [RoutePoint] {
        guard isAvailable, let id = UUID(uuidString: uuid) else { return [] }
        let found = await workouts(matching: HKQuery.predicateForObject(with: id), limit: 1)
        guard let w = found.first else { return [] }
        return await fetchRoute(for: w)
    }

    /// 刪一筆運動（只有 LifeGood 寫的刪得掉；連它的距離、大卡、路線一起刪）。
    /// 文件沒寫刪運動會不會順便刪掉關聯的樣本，自己找出來一起刪（「健康」的步行距離、活動圓圈才不會留著那一趟的數字）。
    /// 先整包一起刪（Apple：多筆只要一筆不行就全部不刪＝不會只刪一半）；整包不行再只刪運動那一筆，樣本一筆一筆試
    func deleteWorkout(uuid: String) async -> DeleteResult {
        guard isAvailable else { return .failed("這台裝置現在不能用 Apple 健康") }
        guard let id = UUID(uuidString: uuid) else { return .notFound }
        let found = await workouts(matching: HKQuery.predicateForObject(with: id), limit: 1)
        guard let w = found.first else { return .notFound }
        guard Self.isOwn(w) else { return .notOurs }

        let mine = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: w),
            HKQuery.predicateForObjects(from: HKSource.default())
        ])
        var linkedTypes: [HKSampleType] = []
        if let distanceType { linkedTypes.append(distanceType) }
        if let cyclingType { linkedTypes.append(cyclingType) }
        if let energyType { linkedTypes.append(energyType) }
        linkedTypes.append(HKSeriesType.workoutRoute())
        var linked: [HKSample] = []
        for t in linkedTypes {
            let more = await samples(of: t, matching: mine)
            linked.append(contentsOf: more)
        }

        var objects: [HKObject] = [w]
        for s in linked { objects.append(s) }
        do {
            try await store.delete(objects)
            return .deleted
        } catch {
            // 整包刪不成：下面只刪運動那一筆再說
        }
        do {
            try await store.delete(w)
        } catch {
            return .failed(Self.deleteProblem(error))
        }
        for s in linked {
            _ = try? await store.delete(s)
        }
        return .deleted
    }

    // MARK: - 共用查詢

    /// [v25.554] 符合條件的運動，按結束時間新到舊
    private func workouts(matching predicate: NSPredicate, limit: Int) async -> [HKWorkout] {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let result: [HKWorkout] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate,
                                  limit: limit, sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }
        return result
    }

    /// [v25.554] 某一種樣本裡符合條件的（刪一筆運動時找它底下的距離、大卡、路線）
    private func samples(of type: HKSampleType, matching predicate: NSPredicate) async -> [HKSample] {
        let result: [HKSample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: samples ?? [])
            }
            store.execute(q)
        }
        return result
    }

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

    /// [v25.554] 一筆 HKWorkout 組成帶進來的樣子（每一種讀法都走這裡：移動時間、爬升、是不是自己寫的只算一處）
    private func makeImported(_ w: HKWorkout, route: [RoutePoint]) -> ImportedWorkout {
        let span = max(0, w.endDate.timeIntervalSince(w.startDate))
        // 移動時間：HKWorkout.duration 扣掉手錶的暫停；不合理（0、負的、不是有限數）就用結束減開始
        let duration = w.duration
        let moving = (duration.isFinite && duration > 0) ? duration : span
        return ImportedWorkout(
            uuid: w.uuid.uuidString, start: w.startDate, end: w.endDate,
            activityName: Self.name(for: w.workoutActivityType),
            isCardio: Self.isCardio(w.workoutActivityType),
            distanceKm: Self.distanceKm(of: w), energyKcal: Self.energyKcal(of: w), route: route,
            sport: Self.sport(for: w.workoutActivityType),
            movingMinutes: moving / 60,
            climbM: Self.climbM(of: w),
            isOwn: Self.isOwn(w))
    }

    // MARK: - 工具

    private static func minuteKey(_ d: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month, .day, .hour, .minute], from: d)) ?? d
    }

    /// [v25.554] 是不是 LifeGood 自己寫進去的（來源是這個 App）
    private static func isOwn(_ object: HKObject) -> Bool {
        object.sourceRevision.source.bundleIdentifier == HKSource.default().bundleIdentifier
    }

    /// [v25.554] 手錶量的爬升（公尺）：運動附註的 HKMetadataKeyElevationAscended；沒有、單位不是長度、不合理的都是 nil（不知道，不是 0）
    private static func climbM(of w: HKWorkout) -> Double? {
        guard let q = w.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity,
              q.is(compatibleWith: .meter()) else { return nil }
        let m = q.doubleValue(for: .meter())
        guard m.isFinite, m >= 0 else { return nil }
        return m
    }

    /// [v25.554] 先找這種運動該有的距離（騎車先找騎車距離、游泳先找游泳距離），沒有再找其他種
    private static func distanceKm(of w: HKWorkout) -> Double {
        let types: [HKQuantityTypeIdentifier]
        switch w.workoutActivityType {
        case .cycling: types = [.distanceCycling, .distanceWalkingRunning, .distanceSwimming]
        case .swimming: types = [.distanceSwimming, .distanceWalkingRunning, .distanceCycling]
        default: types = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
        }
        for id in types {
            guard let t = HKQuantityType.quantityType(forIdentifier: id),
                  let stat = w.statistics(for: t)?.sumQuantity() else { continue }
            let km = stat.doubleValue(for: .meterUnit(with: .kilo))
            if km.isFinite, km > 0 { return km }
        }
        return 0
    }

    private static func energyKcal(of w: HKWorkout) -> Double {
        guard let t = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
              let stat = w.statistics(for: t)?.sumQuantity() else { return 0 }
        return stat.doubleValue(for: .kilocalorie())
    }

    /// [v25.554] 要寫的距離（公里）：每個有氧動作照它的運動分種類（WorkoutFacts.healthDistance）加起來；
    /// 重訓、其他有氧（橢圓機、划船、游泳…）不寫。例：騎 23.4 公里 → 騎車 23.4、步行＋跑步 0
    private static func distanceToWrite(_ s: WorkoutSession) -> (walkingRunning: Double, cycling: Double) {
        var walk = 0.0
        var bike = 0.0
        for e in s.cardioExercises where e.distanceKm.isFinite && e.distanceKm > 0 {
            switch WorkoutFacts.healthDistance(for: e.resolvedSport) {
            case .walkingRunning: walk += e.distanceKm
            case .cycling: bike += e.distanceKm
            case .none: break
            }
        }
        return (walkingRunning: walk, cycling: bike)
    }

    /// [v25.554] 寫進附註的爬升（公尺）：主要那個有氧動作（有路線的優先）知道爬升才寫（WorkoutFacts.climb），0＝平路也寫；
    /// 不知道（舊版灌水的、手動補記沒填）不寫
    private static func climbToWrite(_ s: WorkoutSession) -> Double? {
        guard let main = s.firstRouteExercise ?? s.cardioExercises.first,
              let c = WorkoutFacts.climb(main, in: s), c.isFinite, c >= 0 else { return nil }
        return c
    }

    /// [v25.554] 要寫的暫停：WorkoutFacts.healthPauses（排好、夾在開始～結束、併好），而且加起來要跟
    /// 「結束−開始−移動時間」對得上（差 1 分鐘內）。編輯改過時間長度、結束時間退回「開始＋移動時間」的就對不上——
    /// 這時再寫暫停，「健身」App 的時間會比 LifeGood 的短，乾脆不寫
    private static func pausesToWrite(_ s: WorkoutSession, start: Date, end: Date, movingMinutes: Double) -> [WorkoutPause] {
        let pauses = WorkoutFacts.healthPauses(s, start: start, end: end)
        guard !pauses.isEmpty else { return [] }
        let paused = pauses.reduce(0.0) { $0 + $1.seconds }
        let room = end.timeIntervalSince(start) - movingMinutes * 60
        guard abs(room - paused) <= 60 else { return [] }
        return pauses
    }

    /// [v25.554] 路線點 → CLLocation：時間夾在開始～結束之間（超出運動時間的點 Apple 健康不收）；壞掉的座標不要
    private static func locations(_ route: [RoutePoint], start: Date, end: Date) -> [CLLocation] {
        var out: [CLLocation] = []
        out.reserveCapacity(route.count)
        let last = max(start, end)
        for p in route where p.t.isFinite {
            let coordinate = CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon)
            guard CLLocationCoordinate2DIsValid(coordinate) else { continue }
            let t = min(max(start.addingTimeInterval(p.t), start), last)
            out.append(CLLocation(coordinate: coordinate,
                                  altitude: p.alt.isFinite ? p.alt : 0,
                                  horizontalAccuracy: 5, verticalAccuracy: 5,
                                  timestamp: t))
        }
        return out
    }

    /// [v25.554] 刪不掉時給使用者看的一句話
    private static func deleteProblem(_ error: Error) -> String {
        if let hk = error as? HKError {
            switch hk.code {
            case .errorAuthorizationDenied, .errorAuthorizationNotDetermined:
                return "Apple 健康沒給 LifeGood 寫入（刪除）權限"
            default:
                break
            }
        }
        return error.localizedDescription
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
