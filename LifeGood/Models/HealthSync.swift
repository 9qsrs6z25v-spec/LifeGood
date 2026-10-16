import Foundation
import Combine

// MARK: - Apple 健康同步與要確認的動作（v25.554，健康 v4；health/judge.md §6 v4、build/v4/brief.md）
//
// 以前同步整段寫在健康頁的 Apple 健康設定小頁裡（只有按「立即同步」才跑、起點是上次同步那一刻、用開始時間篩：
// 手錶 07:00 開始跑、07:30 打開 App 同步過、08:00 跑完，那一趟永遠帶不進來）。v4 搬到這裡，健康頁、設定小頁、成果頁共用：
// • 同步（sync）：上次同步往回 1 天、用結束時間篩、編號去重（已經在 LifeGood 的、帳上「不再帶進來」的、LifeGood 自己寫的都不帶）；
//   手錶的爬升、移動時間（扣掉手錶的暫停）、騎車距離一起讀；v4 以前帶進來的手錶紀錄補讀一次；路線晚到的 24 小時內再找；
//   舊版記的（路線沒存到）去 Apple 健康找同一時間、有路線的手錶紀錄（routeFinds，先問、一筆一筆接回）。
// • 打開健康頁 15 分鐘沒同步就自動同步（syncIfDue；WorkoutFacts.healthSyncDue）。
// • 寫進去（push）：真正開始結束、每次暫停一組暫停／繼續、跑走登山寫步行＋跑步距離、騎車寫騎車距離、爬升寫進附註、
//   用簡化前的點寫路線（WorkoutRouteStash）；寫好記下寫進去的時間與數字（WorkoutFacts.healthStamp）。
// • 改過〔更新〕＝刪掉 Apple 健康裡舊的那筆、寫一筆新的；刪除時可以連 Apple 健康那筆一起刪（只有 LifeGood 寫的刪得掉）；
//   手錶記的只從 LifeGood 刪、以後不再帶進來（LifeStore.workoutHealthLedger）。
// • 手錶和 App 同一趟〔合成一筆〕〔兩筆都留〕（WorkoutFacts.duplicates／merged）；舊紀錄〔接回來〕〔先不要〕。
// 判斷、合成、字都在 WorkoutFacts（純函式，build/v4/sim_v4.py 驗算）；Apple 健康的讀寫在 HealthKitManager。

/// [v25.554] 存檔前完整的點（還沒簡化）：只放記憶體一下，寫進 Apple 健康時拿走（judge §6 v4「用簡化前的點」）。
/// WorkoutFacts.makeSession 放進來（按完成、救回中途存檔都走它），HealthSyncCenter.push 拿走；最多留 4 趟。
/// 沒有 actor 隔離（makeSession 不在主執行緒也能叫），用鎖保護
enum WorkoutRouteStash {
    private static let lock = NSLock()
    private static var routes: [(id: UUID, route: [RoutePoint])] = []
    private static let maxRoutes = 4

    /// 放一趟（同一趟再放就換掉）；不到 2 點不放
    static func keep(_ route: [RoutePoint], for id: UUID) {
        guard route.count >= 2 else { return }
        lock.lock()
        defer { lock.unlock() }
        routes.removeAll { $0.id == id }
        routes.append((id: id, route: route))
        if routes.count > maxRoutes { routes.removeFirst(routes.count - maxRoutes) }
    }

    /// 拿走一趟（拿過就沒了）；沒有回 nil（App 重開過、編輯後再寫：用存下來的簡化路線）
    static func take(_ id: UUID) -> [RoutePoint]? {
        lock.lock()
        defer { lock.unlock() }
        guard let i = routes.firstIndex(where: { $0.id == id }) else { return nil }
        let r = routes[i].route
        routes.remove(at: i)
        return r
    }
}

/// [v25.554] 舊版記的那一趟（路線沒存到），在 Apple 健康找到同一時間、有路線的手錶紀錄（還沒帶進 LifeGood 的那種）。
/// 健康頁要確認「9/20 的跑步是舊版記的，路線沒存到；Apple Watch 同一時間有路線。」〔接回來〕〔先不要〕
struct WorkoutRouteFind: Identifiable {
    /// LifeGood 裡舊版記的那一趟
    let sessionId: UUID
    /// 那一趟的開始（問句的日期）
    let sessionDate: Date
    /// 那一趟的運動（問句「的跑步」）
    let sport: WorkoutSport
    /// 手錶那一筆的 Apple 健康編號
    let watchUUID: String
    /// 手錶那一筆照「帶進來」的樣子組好的一趟（有路線；接回時當成 WorkoutFacts.merged 的 watch）
    let watch: WorkoutSession

    var id: UUID { sessionId }

    /// 健康頁那一句（跟 legacy 的 WorkoutDuplicate 同一句）
    var prompt: String { WorkoutFacts.legacyRoutePrompt(date: sessionDate, sport: sport) }
}

/// [v25.554] Apple 健康同步、寫入、更新、刪除、合成、接回路線（健康頁、設定小頁、成果頁、刪除確認框共用一個）。
/// 全部在主執行緒；寫 store 都在 await 之後（不跟按鈕、提示框收起同一輪）。
/// 每一個 await 回來之後都重新拿 store 裡最新的那一筆再改（中間可能被編輯、刪掉、別台裝置同步過來）；
/// 一次動很多筆時組好新陣列 store.workouts = all 一次寫（不一筆一筆 upsert，免得存檔＋重算 N 次）。
/// 判斷一律叫 WorkoutFacts（同一趟、要不要再讀、改過沒、合成），這裡只管「什麼時候讀、讀了怎麼併、寫了記什麼」。
/// **對外的名字、參數、回傳型別不准改**（build/v4/brief.md §5 名稱表）
@MainActor
final class HealthSyncCenter: ObservableObject {
    static let shared = HealthSyncCenter()

    /// 正在同步（設定小頁「同步中…」、健康頁 Apple 健康那一列）
    @Published private(set) var syncing = false
    /// 上一次同步的結果：「已帶入 訓練 2 筆、體重 1 筆」「已是最新，沒有新資料」；nil＝這次打開 App 還沒同步過
    @Published private(set) var lastMessage: String?
    /// 上一次動作失敗的一句話（「沒刪成功：…」「路線沒寫進 Apple 健康：…」）；成功的動作會清掉
    @Published private(set) var lastProblem: String?
    /// 舊紀錄在 Apple 健康找得到手錶路線的（只放記憶體；每次同步重找）
    @Published private(set) var routeFinds: [WorkoutRouteFind] = []
    /// Apple 健康多了要同意的項目（v4 新加的騎車距離還沒同意過）：健康頁要確認〔去同意〕
    @Published private(set) var needsMoreAccess = false
    /// 正在寫進 Apple 健康（含〔更新〕）的那幾趟：成果頁「存進 Apple 健康中…」
    @Published private(set) var writing: Set<UUID> = []

    /// 正在合成、接回路線的那幾趟（先刪 Apple 健康裡 LifeGood 寫的那筆，要等一下）：連按兩下只做一次
    private var busy: Set<UUID> = []
    /// 這次 App 開著已經去 Apple 健康找過路線的舊紀錄（找不到的不再每次同步都找；App 重開再找）
    private var searchedLegacy: Set<UUID> = []
    /// 成果頁〔去 Apple 健康找〕找到的（使用者自己按的：按過「先不要」的也留著給他看）
    private var askedFinds: Set<UUID> = []

    /// v4 以前的紀錄補讀一次：一次最多讀幾趟（新到舊）
    private static let maxRefresh = 300
    /// 舊紀錄找回路線：一次同步最多找幾趟（新到舊；找過的這次 App 開著不再找）
    private static let maxLegacySearch = 50
    /// 舊紀錄找回路線：在那一趟前後多抓多久的 Apple 健康紀錄
    private static let legacySearchSlack: TimeInterval = 2 * 3_600
    /// 有路線的運動（手錶路線晚到、v4 以前帶進來沒有路線的，再去找路線）
    private static let routeSports: Set<WorkoutSport> = [.run, .walk, .bike, .hike]

    private init() {}

    /// 健康頁的 Apple 健康開關（@AppStorage("health_hk_enabled")，同 WorkoutHealthWriter.enabledKey）
    var isEnabled: Bool { UserDefaults.standard.bool(forKey: WorkoutHealthWriter.enabledKey) }

    /// 上次同步的時間（@AppStorage("health_hk_last_sync")，秒；0＝沒同步過）
    static let lastSyncKey = "health_hk_last_sync"

    private var hk: HealthKitManager { HealthKitManager.shared }

    /// 上次同步的時間；沒同步過是 nil
    private var lastSyncDate: Date? {
        let t = UserDefaults.standard.double(forKey: Self.lastSyncKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    // MARK: 同步

    /// 打開健康頁、回到前景：開著、裝置支援、離上次同步 15 分鐘以上才同步（WorkoutFacts.healthSyncDue）；正在同步就什麼都不做
    func syncIfDue(store: LifeStore) async {
        guard isEnabled, hk.isAvailable, !syncing else { return }
        guard WorkoutFacts.healthSyncDue(lastSync: lastSyncDate, now: Date()) else { return }
        await sync(store: store)
    }

    /// 立即同步（設定小頁「立即同步」、打開開關之後）：不跳任何權限框（新的權限走 requestAccess）
    func sync(store: LifeStore) async {
        guard isEnabled, hk.isAvailable, !syncing else { return }
        syncing = true
        defer { syncing = false }
        lastProblem = nil

        // 只查、不跳同意畫面（statusForAuthorizationRequest）
        needsMoreAccess = await hk.needsAuthorizationRequest()

        let now = Date()
        // 上次同步往回 1 天（第一次 90 天）；HealthKit 那邊用結束時間篩（重疊就算）
        let since = WorkoutFacts.healthSyncStart(lastSync: lastSyncDate, now: now)

        let measured = await syncProfile(since: since, store: store)
        let added = await importWorkouts(since: since, now: now, store: store)
        let routes = await refreshOld(now: now, skip: Set(added), store: store)
        await findLegacyRoutes(now: now, store: store)

        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.lastSyncKey)
        lastMessage = Self.summary(workouts: added.count, weights: measured.weights,
                                   vitals: measured.vitals, routes: routes)
    }

    /// 打開開關、要確認〔去同意〕：跳系統的同意畫面（只問還沒問過的種類），問完更新 needsMoreAccess、再同步一次
    func requestAccess(store: LifeStore) async {
        await hk.requestAuthorization()
        needsMoreAccess = await hk.needsAuthorizationRequest()
        await sync(store: store)
    }

    /// 同步完那一句：「已帶入 訓練 2 筆、體重 1 筆、血壓 1 筆、補上 1 趟路線」；都沒有「已是最新，沒有新資料」
    private static func summary(workouts: Int, weights: Int, vitals: Int, routes: Int) -> String {
        var parts: [String] = []
        if workouts > 0 { parts.append("訓練 \(workouts) 筆") }
        if weights > 0 { parts.append("體重 \(weights) 筆") }
        if vitals > 0 { parts.append("血壓 \(vitals) 筆") }
        var text = parts.isEmpty ? "" : "已帶入 " + parts.joined(separator: "、")
        if routes > 0 {
            text += text.isEmpty ? "已補上 \(routes) 趟路線" : "、補上 \(routes) 趟路線"
        }
        return text.isEmpty ? "已是最新，沒有新資料" : text
    }

    /// 已經在 LifeGood 的編號（含合成用掉的手錶編號）＋帳上「不再帶進來」的：同步、找路線都不再帶這些
    private func knownUUIDs(_ store: LifeStore) -> Set<String> {
        var set = store.workoutHealthLedger.ignoredSet
        for s in store.workouts {
            if let id = s.healthKitUUID { set.insert(id) }
            if let m = s.health?.mergedWatchUUID { set.insert(m) }
        }
        return set
    }

    /// 體重、血壓心率、身高（v3 設定小頁的規則照舊：同一天已經有體重就不加、同一分鐘已經有血壓就不加、身高沒填才補）。
    /// 全部讀完（await）才拿 store 裡最新的健康檔案來加，不會蓋掉讀的時候剛改的
    private func syncProfile(since: Date, store: LifeStore) async -> (weights: Int, vitals: Int) {
        let weights = await hk.fetchBodyMass(since: since)
        let vitals = await hk.fetchVitals(since: since)
        var height: Double?
        if store.healthProfile.heightCm == 0 {
            height = await hk.fetchLatestHeightCm()
        }

        var profile = store.healthProfile
        let cal = Calendar.current
        var addedWeights = 0
        var addedVitals = 0
        for w in weights {
            let hasSameDay = profile.measurements.contains {
                $0.weightKg != nil && cal.isDate($0.date, inSameDayAs: w.date)
            }
            guard !hasSameDay else { continue }
            profile.measurements.append(HealthMeasurement(date: w.date, weightKg: w.kg,
                                                          note: "來自 Apple 健康"))
            addedWeights += 1
        }
        for v in vitals {
            let exists = profile.measurements.contains {
                abs($0.date.timeIntervalSince(v.date)) < 60 && $0.hasBloodPressure
            }
            guard !exists else { continue }
            profile.measurements.append(HealthMeasurement(date: v.date, weightKg: nil,
                                                          systolic: v.systolic, diastolic: v.diastolic,
                                                          heartRate: v.heartRate, note: "來自 Apple 健康"))
            addedVitals += 1
        }
        var heightChanged = false
        if profile.heightCm == 0, let h = height, h > 0 {
            profile.heightCm = h
            heightChanged = true
        }
        if addedWeights > 0 || addedVitals > 0 || heightChanged {
            profile.measurements.sort { $0.date > $1.date }
            store.updateHealthProfile(profile)
        }
        return (addedWeights, addedVitals)
    }

    /// 手錶的運動帶進來（不到 1 分鐘的不要）；回傳這次帶進來的編號。
    /// HealthKitManager 已經跳過 LifeGood 自己寫的、excluding 裡的；寫之前用最新的 store 再擋一次重複編號，一次 append
    private func importWorkouts(since: Date, now: Date, store: LifeStore) async -> [String] {
        let imported = await hk.fetchWorkouts(since: since, excluding: knownUUIDs(store))
        let fresh = imported
            .filter { $0.end.timeIntervalSince($0.start) >= 60 }
            .map { importedSession(from: $0, now: now) }
        guard !fresh.isEmpty else { return [] }

        var known = knownUUIDs(store)
        var all = store.workouts
        var added: [String] = []
        for s in fresh {
            guard let id = s.healthKitUUID, !known.contains(id) else { continue }
            known.insert(id)
            all.append(s)
            added.append(id)
        }
        if !added.isEmpty { store.workouts = all }
        return added
    }

    /// Apple 健康的一筆 → LifeGood 的一趟（帶進來的樣子；舊紀錄找回路線的 WorkoutRouteFind.watch 也用這個組）。
    /// 移動時間用 HKWorkout.duration（扣掉手錶的暫停）、結束是手錶那筆的結束；爬升手錶有量才知道（0＝平路），沒量是不知道
    private func importedSession(from i: HealthKitManager.ImportedWorkout, now: Date) -> WorkoutSession {
        let ex = WorkoutExercise(
            name: i.activityName,
            kind: i.isCardio ? .cardio : .strength,
            reps: 0, sets: 0, loadType: .none, loadKg: 0,
            distanceKm: i.distanceKm, durationMinutes: i.movingMinutes,
            route: i.route, elevationGainM: i.climbM ?? 0,
            note: i.isCardio ? "" : "來自 Apple 健康，組數次數請自行補上",
            sport: i.sport)
        let climbKnown: Bool? = i.isCardio ? (i.climbM != nil) : nil
        let link = WorkoutHealthLink(importedAt: now, refreshedAt: now, climbKnown: climbKnown)
        return WorkoutSession(
            date: i.start, title: i.activityName, exercises: [ex],
            durationMinutes: i.movingMinutes,
            healthKitUUID: i.uuid, activeEnergyKcal: i.energyKcal,
            endedAt: i.end, source: .watch, health: link)
    }

    // MARK: 補讀（v4 以前的紀錄、路線晚到）

    /// WorkoutFacts.needsHealthRefresh 的那幾趟（新到舊、最多 300）讀一次 Apple 健康那一筆：
    /// • 手錶的：第一次補讀補爬升、騎車距離（以前是 0 的）、移動時間（差 30 秒以上才改）；沒有路線的跑走騎登山再找路線（晚到的）。
    /// • 其他（LifeGood 寫的、舊資料看不出來的）：是 LifeGood 寫的記 written＝true＋寫進去的距離、開始；不是記 false。
    /// • 沒讀到的：這一批有讀到任何一筆才記 refreshedAt（那筆在健康 App 被刪了）；一筆都沒讀到（可能沒讀取權限）都不記，下次再讀。
    ///   不清 healthKitUUID（沒讀取權限時讀起來也是沒有）。
    /// skip：這次剛帶進來的（剛讀過）。回傳補上路線的趟數
    private func refreshOld(now: Date, skip: Set<String>, store: LifeStore) async -> Int {
        let candidates = store.workouts.filter { s in
            guard let id = s.healthKitUUID, !skip.contains(id) else { return false }
            return WorkoutFacts.needsHealthRefresh(s, now: now)
        }
        let targets = Array(candidates.sorted { $0.date > $1.date }.prefix(Self.maxRefresh))
        guard !targets.isEmpty else { return 0 }

        let infos = await hk.fetchWorkouts(uuids: targets.compactMap { $0.healthKitUUID })
        var byUUID: [String: HealthKitManager.ImportedWorkout] = [:]
        for i in infos { byUUID[i.uuid.uppercased()] = i }

        // 路線：全部 await 完才寫 store
        var routes: [UUID: [RoutePoint]] = [:]
        for s in targets {
            guard let id = s.healthKitUUID, let info = byUUID[id.uppercased()] else { continue }
            guard isWatch(s, info: info), s.firstRouteExercise == nil,
                  Self.routeSports.contains(s.primarySport) else { continue }
            let r = await hk.fetchRoute(uuid: info.uuid)
            if r.count >= 2 { routes[s.id] = r }
        }

        // 一次寫回（await 之後最新的 store；編號換過的那一趟不動）
        let anyRead = !infos.isEmpty
        var targetUUID: [UUID: String] = [:]
        for s in targets {
            if let id = s.healthKitUUID { targetUUID[s.id] = id }
        }
        var all = store.workouts
        var changed = false
        var routesAdded = 0
        for k in all.indices {
            guard let wanted = targetUUID[all[k].id], all[k].healthKitUUID == wanted else { continue }
            var s = all[k]
            let lateRoute = routes[s.id]
            if let info = byUUID[wanted.uppercased()] {
                if isWatch(s, info: info) {
                    if applyWatchRefresh(&s, info: info, route: lateRoute, now: now) { routesAdded += 1 }
                } else {
                    applyOwnRefresh(&s, info: info, now: now)
                }
            } else if anyRead {
                var h = s.health ?? WorkoutHealthLink()
                h.refreshedAt = now
                s.health = h
            } else {
                continue
            }
            all[k] = s
            changed = true
        }
        if changed { store.workouts = all }
        return routesAdded
    }

    /// 這一趟是不是手錶那一筆：看得出來的照 WorkoutFacts.source(of:)；看不出來的（v25.552 以前、沒有路線）照 Apple 健康：
    /// 不是 LifeGood 寫的就是手錶的
    private func isWatch(_ s: WorkoutSession, info: HealthKitManager.ImportedWorkout) -> Bool {
        if let src = WorkoutFacts.source(of: s) { return src == .watch }
        return !info.isOwn
    }

    /// 手錶那一趟補讀。爬升、距離、移動時間只在第一次補讀時改（之後的再讀只為了晚到的路線，不蓋掉使用者自己改過的數字）；
    /// 回傳有沒有補上路線
    private func applyWatchRefresh(_ s: inout WorkoutSession, info: HealthKitManager.ImportedWorkout,
                                   route: [RoutePoint]?, now: Date) -> Bool {
        var h = s.health ?? WorkoutHealthLink()
        let firstTime = h.refreshedAt == nil
        // 先記來源：下面補 endedAt 之後，沒記來源的會被 source(of:) 當成 App 記的
        if s.source == nil { s.source = .watch }
        var gotRoute = false
        if let i = WorkoutFacts.mainCardioIndex(s), s.exercises[i].kind == .cardio {
            if firstTime {
                s.exercises[i].elevationGainM = info.climbM ?? 0
                h.climbKnown = info.climbM != nil
                if s.totalDistanceKm <= 0 && info.distanceKm > 0 {
                    s.exercises[i].distanceKm = info.distanceKm
                }
            }
            if let r = route, r.count >= 2, s.firstRouteExercise == nil {
                s.exercises[i].route = r
                gotRoute = true
            }
        }
        if firstTime, info.movingMinutes > 0,
           abs(info.movingMinutes - WorkoutFacts.movingMinutes(s)) >= 0.5 {
            s.durationMinutes = info.movingMinutes
            if let i = WorkoutFacts.mainCardioIndex(s) ?? (s.exercises.count == 1 ? 0 : nil) {
                s.exercises[i].durationMinutes = info.movingMinutes
            }
            s.endedAt = info.end
        }
        h.refreshedAt = now
        s.health = h
        return gotRoute
    }

    /// LifeGood 寫的（或舊資料看不出來、Apple 健康說是 LifeGood 寫的）那一趟補讀：
    /// 寫進去的距離、開始補上（時間和運動不補：v4 以前寫的時間含暫停、不認得的名字一律當跑步，拿來比會誤報「改過了」）
    private func applyOwnRefresh(_ s: inout WorkoutSession, info: HealthKitManager.ImportedWorkout, now: Date) {
        var h = s.health ?? WorkoutHealthLink()
        if info.isOwn {
            h.written = true
            h.writtenKm = info.distanceKm
            h.writtenStart = info.start
            // 看不出來怎麼記的（沒有 endedAt、不是舊版只存到起點的）→ 手動補記
            if WorkoutFacts.source(of: s) == nil { s.source = .manual }
        } else {
            h.written = false
        }
        h.refreshedAt = now
        s.health = h
    }

    // MARK: 舊紀錄找回路線

    /// 舊版記的（路線沒存到）那幾趟，去 Apple 健康找同一時間、有路線、還沒帶進 LifeGood 的手錶紀錄（一趟一趟問）。
    /// 手錶那筆已經在 LifeGood 的走合成（WorkoutFacts.duplicates 的 legacy），按過「先不要」的不找；這次 App 開著找過的不再找
    private func findLegacyRoutes(now: Date, store: LifeStore) async {
        let ledger = store.workoutHealthLedger
        let dups = WorkoutFacts.duplicates(store.workouts, ledger: ledger)
        let legacy = WorkoutFacts.legacyNeedingRoute(store.workouts, ledger: ledger, duplicates: dups)
        let todo = Array(legacy.filter { !searchedLegacy.contains($0.id) }.prefix(Self.maxLegacySearch))

        var found: [WorkoutRouteFind] = []
        var taken = Set(routeFinds.map { $0.watchUUID })
        for s in todo {
            searchedLegacy.insert(s.id)
            if let f = await watchMatch(for: s, now: now, taken: taken, store: store) {
                taken.insert(f.watchUUID)
                found.append(f)
            }
        }
        // 這次找到的＋之前找到、還沒處理、還對得上的（await 之後的 routeFinds、store）
        let merged = validFinds(found + routeFinds, store: store)
        if merged.map({ $0.sessionId }) != routeFinds.map({ $0.sessionId })
            || merged.map({ $0.watchUUID }) != routeFinds.map({ $0.watchUUID }) {
            routeFinds = merged
        }
    }

    /// 一趟舊紀錄在 Apple 健康的手錶紀錄：前後各 2 小時、不是 LifeGood 寫的、編號還沒在 LifeGood（也不在帳上、不在 taken）、
    /// 同一趟（WorkoutFacts.matchesOuting）；重疊最多的先試，有 2 點以上路線才算（最多試 3 筆）
    private func watchMatch(for s: WorkoutSession, now: Date, taken: Set<String>,
                            store: LifeStore) async -> WorkoutRouteFind? {
        let end = WorkoutFacts.endDate(s)
        let nearby = await hk.fetchWorkouts(from: s.date.addingTimeInterval(-Self.legacySearchSlack),
                                            to: end.addingTimeInterval(Self.legacySearchSlack))
        let known = knownUUIDs(store).union(taken)
        var ranked: [(overlap: Double, workout: HealthKitManager.ImportedWorkout)] = []
        for w in nearby where !w.isOwn && !known.contains(w.uuid) {
            guard WorkoutFacts.matchesOuting(s, start: w.start, end: w.end, sport: w.sport) else { continue }
            let ov = WorkoutFacts.overlapSeconds(aStart: s.date, aEnd: end, bStart: w.start, bEnd: w.end)
            ranked.append((overlap: ov, workout: w))
        }
        ranked.sort { $0.overlap > $1.overlap }
        for candidate in ranked.prefix(3) {
            var w = candidate.workout
            let route = await hk.fetchRoute(uuid: w.uuid)
            guard route.count >= 2 else { continue }
            w.route = route
            return WorkoutRouteFind(sessionId: s.id, sessionDate: s.date, sport: s.primarySport,
                                    watchUUID: w.uuid, watch: importedSession(from: w, now: now))
        }
        return nil
    }

    /// 還對得上的找回路線（去重、新到舊）：那一趟還在、還是舊版沒路線；手錶那筆還沒帶進 LifeGood、沒在帳上；
    /// 「先不要」的拿掉（成果頁自己按〔去 Apple 健康找〕的留著）
    private func validFinds(_ finds: [WorkoutRouteFind], store: LifeStore) -> [WorkoutRouteFind] {
        let ledger = store.workoutHealthLedger
        let known = knownUUIDs(store)
        var legacyIds = Set<UUID>()
        for s in store.workouts where s.isLegacyRouteMissing { legacyIds.insert(s.id) }
        var seen = Set<UUID>()
        var out: [WorkoutRouteFind] = []
        for f in finds {
            guard !seen.contains(f.sessionId), legacyIds.contains(f.sessionId),
                  !known.contains(f.watchUUID) else { continue }
            guard !ledger.skipped(f.sessionId) || askedFinds.contains(f.sessionId) else { continue }
            seen.insert(f.sessionId)
            out.append(f)
        }
        return out.sorted { $0.sessionDate > $1.sessionDate }
    }

    /// 從 routeFinds 拿掉一趟（接回了、先不要、刪掉了）
    private func dropFind(_ sessionId: UUID) {
        askedFinds.remove(sessionId)
        if routeFinds.contains(where: { $0.sessionId == sessionId }) {
            routeFinds.removeAll { $0.sessionId == sessionId }
        }
    }

    // MARK: 寫

    /// 寫進 Apple 健康（新的一趟、救回、補記、複製、成果頁〔存進去〕）：開著、支援、還沒有編號才寫；
    /// 寫好把編號和寫進去的數字（WorkoutFacts.healthStamp）存回 store 裡最新的那一筆
    func push(_ session: WorkoutSession, store: LifeStore) async {
        guard isEnabled, hk.isAvailable, session.healthKitUUID == nil,
              !writing.contains(session.id), !busy.contains(session.id) else { return }
        writing.insert(session.id)
        defer { writing.remove(session.id) }

        // 簡化前的點（按完成、救回的那一次才有；App 重開過、〔更新〕用存下來的簡化路線）
        let full = WorkoutRouteStash.take(session.id)
        guard let uuid = await hk.saveWorkout(session, bodyWeightKg: store.latestBodyWeightKg,
                                              fullRoute: full) else {
            // 沒寫進去：完整的點放回去（成果頁〔存進去〕再試還用得到）
            if let full { WorkoutRouteStash.keep(full, for: session.id) }
            lastProblem = hk.lastError ?? "沒存進 Apple 健康"
            return
        }
        // await 之後：拿最新的那一筆（沒了＝刪掉了，就不寫回；已經有編號＝別的路徑寫過了）
        guard var latest = store.workouts.first(where: { $0.id == session.id }),
              latest.healthKitUUID == nil else { return }
        // 記的是「寫進去的那一份」的數字（之後編輯改了，跟它比才知道要〔更新〕）；
        // 帶進來、補讀、爬升、合成的欄位照最新那一筆的
        var stamp = WorkoutFacts.healthStamp(session, at: Date())
        stamp.importedAt = latest.health?.importedAt
        stamp.refreshedAt = latest.health?.refreshedAt
        stamp.climbKnown = latest.health?.climbKnown
        stamp.mergedWatchUUID = latest.health?.mergedWatchUUID
        latest.healthKitUUID = uuid
        latest.health = stamp
        store.upsertWorkout(latest)
        lastProblem = nil
    }

    /// 〔更新〕：刪掉 Apple 健康裡舊的那筆（LifeGood 寫的），照現在的寫一筆新的
    func update(_ sessionId: UUID, store: LifeStore) async {
        guard hk.isAvailable, !writing.contains(sessionId), !busy.contains(sessionId) else { return }
        guard let s = store.workouts.first(where: { $0.id == sessionId }),
              let uuid = s.healthKitUUID,
              s.health?.mergedWatchUUID == nil,
              s.health?.written == true || WorkoutActions.deleteKind(s) == .withHealth else { return }
        guard isEnabled else {
            // 刪了舊的卻寫不回新的（開關關著 push 不寫）：先不動
            lastProblem = "健康頁的 Apple 健康沒打開，打開後再按〔更新〕。"
            return
        }
        writing.insert(sessionId)
        let result = await hk.deleteWorkout(uuid: uuid)
        writing.remove(sessionId)

        switch result {
        case .deleted, .notFound:
            // 舊的不在了（找不到也算刪掉了）：清掉編號和寫進去的數字，照最新的寫一筆新的
            guard var latest = store.workouts.first(where: { $0.id == sessionId }),
                  latest.healthKitUUID == uuid else { return }
            latest.healthKitUUID = nil
            latest.health?.clearWritten()
            store.upsertWorkout(latest)
            lastProblem = nil
            await push(latest, store: store)
        case .notOurs:
            if var latest = store.workouts.first(where: { $0.id == sessionId }), latest.healthKitUUID == uuid {
                var h = latest.health ?? WorkoutHealthLink()
                h.clearWritten()
                h.written = false
                latest.health = h
                store.upsertWorkout(latest)
            }
            lastProblem = "Apple 健康裡那一筆不是 LifeGood 寫的，沒辦法更新。"
        case .failed(let message):
            lastProblem = "沒更新成功：" + message
        }
    }

    /// 刪除那一趟（WorkoutActions.delete 已經排到下一輪才叫）：先從 LifeGood 刪；
    /// alsoFromHealth 而且是 LifeGood 寫的 → 也刪 Apple 健康那筆；其他（手錶的、只刪 LifeGood 的）→ 編號記進「不再帶進來」
    func deleteSession(_ sessionId: UUID, alsoFromHealth: Bool, store: LifeStore) {
        guard let s = store.workouts.first(where: { $0.id == sessionId }) else { return }
        let kind = WorkoutActions.deleteKind(s)
        store.deleteWorkout(id: sessionId)
        dropFind(sessionId)
        // 合成過的：手錶那筆的編號本來就在帳上；再記一次（舊版 iPad 同步過來的帳可能沒有）
        if let merged = s.health?.mergedWatchUUID { store.ignoreHealthWorkout(merged) }
        guard let uuid = s.healthKitUUID else { return }
        if alsoFromHealth && kind == .withHealth {
            // 再問 Apple 健康一次是不是 LifeGood 寫的（舊資料看不出來的那種）：不是、刪不掉 → 留著、記進「不再帶進來」
            Task { await self.deleteFromHealth(uuid, store: store) }
        } else {
            store.ignoreHealthWorkout(uuid)
        }
    }

    /// 刪 Apple 健康那筆（LifeGood 這筆已經刪了）：刪掉、本來就不在 → 什麼都不用；不是 LifeGood 寫的、刪不掉 → 記進「不再帶進來」
    private func deleteFromHealth(_ uuid: String, store: LifeStore) async {
        let result = await hk.deleteWorkout(uuid: uuid)
        switch result {
        case .deleted, .notFound:
            break
        case .notOurs:
            store.ignoreHealthWorkout(uuid)
        case .failed(let message):
            store.ignoreHealthWorkout(uuid)
            lastProblem = "LifeGood 這筆刪了；Apple 健康那筆沒刪成功：" + message
        }
    }

    // MARK: 同一趟、舊紀錄

    /// 合成、接回之前：App 那一趟原本的 Apple 健康編號怎麼處理
    private struct HealthRelinkPlan {
        /// 合成後的編號（nil＝LifeGood 寫的那筆刪不掉，留原本的編號）
        var uuid: String?
        /// 清掉寫進去的數字（LifeGood 寫的那筆已經不在 Apple 健康了）
        var clearWritten = false
        /// 原本那個編號記進「不再帶進來」（留在 Apple 健康、不是 LifeGood 寫的）
        var ignoreOld: String?
        /// 給使用者看的一句（刪不掉的時候）
        var problem: String?
    }

    /// LifeGood 自己寫進 Apple 健康的那筆先刪掉（不然 LifeGood 是一筆、健身 App 還是兩筆）：
    /// 刪掉、本來就不在、不是 LifeGood 寫的 → 改指向手錶那筆；刪不掉 → 留著原本的編號、說一聲
    private func relinkPlan(_ s: WorkoutSession, to watchUUID: String, done: String) async -> HealthRelinkPlan {
        guard let old = s.healthKitUUID, old != watchUUID else {
            return HealthRelinkPlan(uuid: watchUUID)
        }
        guard WorkoutActions.deleteKind(s) == .withHealth else {
            // 原本指的那筆已經知道不是 LifeGood 寫的：留在 Apple 健康、以後不再帶進來
            return HealthRelinkPlan(uuid: watchUUID, ignoreOld: old)
        }
        let result = await hk.deleteWorkout(uuid: old)
        switch result {
        case .deleted, .notFound:
            return HealthRelinkPlan(uuid: watchUUID, clearWritten: true)
        case .notOurs:
            return HealthRelinkPlan(uuid: watchUUID, clearWritten: true, ignoreOld: old)
        case .failed(let message):
            return HealthRelinkPlan(uuid: nil,
                                    problem: done + "；Apple 健康裡 LifeGood 寫的那筆沒刪掉（" + message + "），健身 App 會看到兩筆。")
        }
    }

    /// 合成好的那一趟套上新的編號
    private func applyPlan(_ plan: HealthRelinkPlan, to m: inout WorkoutSession) {
        guard let uuid = plan.uuid else { return }
        m.healthKitUUID = uuid
        if plan.clearWritten { m.health?.clearWritten() }
    }

    /// 〔合成一筆〕〔接回來〕（手錶那筆已經在 LifeGood）：WorkoutFacts.merged，手錶那一趟從 LifeGood 拿掉、編號記進「不再帶進來」；
    /// LifeGood 自己寫進 Apple 健康的那筆刪掉（刪成功才把 healthKitUUID 改指向手錶那筆）
    func merge(_ duplicate: WorkoutDuplicate, store: LifeStore) async {
        let d = duplicate
        guard !busy.contains(d.appId), !writing.contains(d.appId) else { return }
        guard let app = store.workouts.first(where: { $0.id == d.appId }),
              app.health?.mergedWatchUUID == nil,
              let watch = store.workouts.first(where: { $0.id == d.watchId }),
              watch.healthKitUUID == d.watchUUID else { return }

        busy.insert(d.appId)
        let plan = await relinkPlan(app, to: d.watchUUID, done: "已合成一筆")
        busy.remove(d.appId)

        // await 之後拿最新的兩趟再合（中間可能被編輯過）；手錶那趟這時被刪了就用剛剛那一份
        guard let latestApp = store.workouts.first(where: { $0.id == d.appId }),
              latestApp.health?.mergedWatchUUID == nil else { return }
        let latestWatch = store.workouts.first(where: { $0.id == d.watchId }) ?? watch
        var m = WorkoutFacts.merged(app: latestApp, watch: latestWatch)
        WorkoutFacts.applyKcalEstimate(&m, bodyWeightKg: store.latestBodyWeightKg)
        applyPlan(plan, to: &m)

        var all = store.workouts
        guard let i = all.firstIndex(where: { $0.id == d.appId }) else { return }
        all[i] = m
        all.removeAll { $0.id == d.watchId }
        store.workouts = all
        store.ignoreHealthWorkout(d.watchUUID)
        if let old = plan.ignoreOld { store.ignoreHealthWorkout(old) }
        dropFind(d.appId)
        lastProblem = plan.problem
    }

    /// 〔兩筆都留〕：記進帳（以後不再問這一對）
    func keepBoth(_ duplicate: WorkoutDuplicate, store: LifeStore) {
        store.keepWorkoutPair(appId: duplicate.appId, watchUUID: duplicate.watchUUID)
    }

    /// 成果頁〔去 Apple 健康找〕：只找這一趟（按過「先不要」的也找）；找到放進 routeFinds 並回傳，找不到回 nil
    func findRoute(for sessionId: UUID, store: LifeStore) async -> WorkoutRouteFind? {
        guard hk.isAvailable,
              let s = store.workouts.first(where: { $0.id == sessionId }),
              s.isLegacyRouteMissing else { return nil }
        if let had = routeFinds.first(where: { $0.sessionId == sessionId }) { return had }

        let taken = Set(routeFinds.map { $0.watchUUID })
        let found = await watchMatch(for: s, now: Date(), taken: taken, store: store)
        searchedLegacy.insert(sessionId)
        guard let f = found else { return nil }
        // await 之後：那一趟還在、還是舊版沒路線才放進去
        guard let latest = store.workouts.first(where: { $0.id == sessionId }),
              latest.isLegacyRouteMissing else { return nil }
        askedFinds.insert(sessionId)
        var list = routeFinds.filter { $0.sessionId != sessionId }
        list.append(f)
        routeFinds = list.sorted { $0.sessionDate > $1.sessionDate }
        return f
    }

    /// 〔接回來〕（手錶那筆還沒帶進 LifeGood）：WorkoutFacts.merged，手錶那筆的編號記進「不再帶進來」
    func attachRoute(_ find: WorkoutRouteFind, store: LifeStore) async {
        let id = find.sessionId
        guard !busy.contains(id), !writing.contains(id) else { return }
        // 手錶那筆這時已經帶進 LifeGood（剛同步過）：改走要確認的〔接回來〕（合成），這一列拿掉
        let alreadyIn = store.workouts.contains {
            $0.healthKitUUID == find.watchUUID || $0.health?.mergedWatchUUID == find.watchUUID
        }
        guard !alreadyIn,
              let s = store.workouts.first(where: { $0.id == id }),
              s.isLegacyRouteMissing else {
            dropFind(id)
            return
        }

        busy.insert(id)
        let plan = await relinkPlan(s, to: find.watchUUID, done: "已接回路線")
        busy.remove(id)

        // await 之後拿最新的那一趟（中間被刪掉、被改成有路線就不接）
        guard let latest = store.workouts.first(where: { $0.id == id }),
              latest.isLegacyRouteMissing else {
            dropFind(id)
            return
        }
        var m = WorkoutFacts.merged(app: latest, watch: find.watch)
        WorkoutFacts.applyKcalEstimate(&m, bodyWeightKg: store.latestBodyWeightKg)
        applyPlan(plan, to: &m)
        store.upsertWorkout(m)
        store.ignoreHealthWorkout(find.watchUUID)
        if let old = plan.ignoreOld { store.ignoreHealthWorkout(old) }
        dropFind(id)
        lastProblem = plan.problem
    }

    /// 〔先不要〕：記進帳（以後不再找這一趟）、從 routeFinds 拿掉
    func skipRoute(_ find: WorkoutRouteFind, store: LifeStore) {
        store.skipRouteRecovery(find.sessionId)
        dropFind(find.sessionId)
    }
}
