import SwiftUI
import CoreLocation

// MARK: - 一趟運動成果頁的資料（v25.553，健康 v3；health/judge.md §5.2）
//
// G3 檔案：成果頁（WorkoutDetailView）要的字與數字在這裡一次算好（照 VehicleCardData.build 的寫法：
// 在 .task(id:) 裡、主執行緒算一次存 @State，body 只畫）。一套數字讀 WorkoutFacts／WorkoutFormat，
// 每公里分段讀 WorkoutFacts.validSplits、高度讀 WorkoutFacts.elevation、側面的路讀 WorkoutFacts.trailScene、
// 快慢讀 WorkoutPaceLevel／WorkoutPalette（主控寫好，不要再寫第二套）。
//
// 各區（例：10/15 河濱晨跑，judge §8.0）：
// ⓪ 換一趟：同一週不只一趟才有（「10/12 晨跑 4.3」「10/13 下班健… 3.1」…）。
// ① 看板：「10/15 週四 06:05–06:39」（沒有 endedAt 只寫開始）、膠囊「跑步」、小字「河濱晨跑」、大字「5.20 公里」、
//    一句「**32:10**・配速 **6'11"**」（騎車「平均時速」；重訓「3 個動作・共 9 組」）、手寫 Nice / run!（這一趟讓這週達標 Goal / reached!）；
//    六格：距離｜時間（總共 34:40）｜平均配速｜最快一公里 6'02"（第 1 公里 ›）｜爬升 18 m（最高比起點高 9 m ›）｜大卡 約 340（估的）。
// ② 這趟的收穫：只在這一趟在「這週」時（打開三週前那趟說「這週跑步 14.6 公里」會誤會）。
// ③ 要確認：舊版沒路線；編輯過距離或時間、每公里分段對不上（WorkoutFacts.validSplits 是 nil）。
// ④ 路線：沿路線每 100 公尺一小段（同一段 seg 裡；路線超過 12 公里時放寬到 總長÷120，地圖上最多約 120 條線），
//    配速＝那一小段的時間÷距離，跟**這條路線自己的平均**（路線總移動時間÷路線總距離）比——編輯過距離也照樣上色；
//    一小段的快慢連前後各一小段一起算（約 300 公尺；單看 100 公尺會被 GPS 幾公尺的誤差弄花，見 build/v3/g3/sim_g3.py）；
//    相鄰同一級併成一條；每整公里（騎車每 5 公里）一塊小牌、每次暫停一塊「暫停 2:30」。
//    圖例那句的平均：分段對得上（沒編輯過）寫存下來的平均（跟看板同一個數字）；對不上寫路線自己的平均。
// ⑤ 每公里：validSplits 有值、而且至少一整公里；騎車滿 5 公里就每 5 公里一行（時速）。
// ⑥ 高度：WorkoutFacts.elevation 的 gainM ≥ 10。
// ⑧ Apple 健康：裝置不支援「健康」不出現。⑨ 資料：永遠出現。
// 另外：重訓、或一趟裡不只一個動作時多一區「動作」（每個動作一行，WorkoutExercise.summary）。

/// 成果頁全部的字與數字。型別都收在裡面（不佔全域名字：v3 四組同時開工）
struct WorkoutCardData {

    // MARK: 型別

    /// 六格點了做什麼
    enum TileTap: Equatable {
        case none
        /// 捲到「每公里」
        case splits
        /// 捲到「高度」
        case elevation
    }

    /// 看板下的一格（FinanceTileGrid）
    struct Tile: FinanceTileContent {
        let id: String
        let label: String
        let value: String
        var valueTone: MoneyTone? = nil
        var sub: String = ""
        var subTone: MoneyTone? = nil
        var tap: TileTap = .none

        var isTappable: Bool { tap != .none }
        var tapHint: String {
            switch tap {
            case .none: return ""
            case .splits: return "點兩下捲到每公里"
            case .elevation: return "點兩下捲到高度"
            }
        }
    }

    /// 成果看板的頭部（照 VehicleCardBoardData 的資料合約）
    struct Board: Equatable {
        /// 「10/15 週四 06:05–06:39」
        var date = ""
        var dateIcon = "figure.run"
        /// 右上膠囊：運動名「跑步」（中性）
        var capsule: String? = nil
        var capsuleIcon: String? = nil
        /// 小字：這一趟的名字「河濱晨跑」
        var label = ""
        /// 大字：「5.20 公里」；重訓「2,160 kg」或「45 分鐘」
        var big = ""
        /// 一句話：「**32:10**・配速 **6'11"**」（粗體不上色）
        var line = FinanceLine()
        /// 手寫：Nice / run!、Goal / reached!
        var greeting: [String] = []
        var accessibilityText = ""
        var seed = 0
    }

    /// 這趟的收穫一列
    struct Gain: Identifiable {
        let id: String
        let icon: String
        /// 圖示圓的顏色：這種運動的主題色；nil＝綠（連續週數）
        let sport: WorkoutSport?
        let line: FinanceLine
        var accessibilityText: String { line.plain }
    }

    /// 要確認一列（只提醒，沒有按鈕）
    struct Check: Identifiable {
        let id: String
        let icon: String
        let message: String
    }

    /// 路線地圖（整頁唯一一張真地圖；全螢幕那張用同一份）
    struct RouteMap {
        struct Piece: Identifiable {
            let id: Int
            let coordinates: [CLLocationCoordinate2D]
            /// nil＝這條路線算不出快慢（點上沒有時間）：整條運動色
            let level: WorkoutPaceLevel?
        }
        struct Mark: Identifiable {
            let id: Int
            let text: String
            let coordinate: CLLocationCoordinate2D
        }
        var sport: WorkoutSport
        var pieces: [Piece]
        /// 每整公里（騎車每 5 公里）的小牌「1」「2」…
        var marks: [Mark]
        /// 每次暫停的地方「暫停 2:30」（段數跟暫停次數對得上才放）
        var pauses: [Mark]
        var start: CLLocationCoordinate2D
        var end: CLLocationCoordinate2D
        /// 鏡頭：中心照 RouteMath.bounds；範圍（度）照路線自己的南北、東西各放大 1.4 倍（見 cameraSpan）
        var center: CLLocationCoordinate2D
        var latitudeDelta: Double
        var longitudeDelta: Double
        /// 有快慢上色（圖例才出現）
        var paced: Bool
        /// 「（跟這趟平均 6'11" 比）」「（跟這趟平均時速 21.5 比）」
        var legendNote: String
        /// 放大按鈕的 VoiceOver 提示
        var accessibilityText: String
    }

    /// 每公里一行（騎車每 5 公里一行）
    struct SplitRow: Identifiable {
        let id: Int
        /// 「1」…「5」；最後不滿一段「0.2」；騎車「5」「10」
        let label: String
        /// 配速「6'02"」；最後不滿一公里是那一段的時間「1'14"」；騎車時速「21.5」
        let value: String
        /// 長條長度 0…1（越快越長：最快那段÷這段）；0＝不畫長條
        let fraction: Double
        let level: WorkoutPaceLevel
        /// 「快」「慢」「快很多」「慢很多」；差不多不寫
        let levelWord: String
        /// 「+4 m」；不知道是空字串
        let climb: String
        /// 最快那一段（兩段以上才有）
        let star: Bool
        /// 最後不滿一段：「（換算每公里 6'10"，跟平均差不多）」；有值時這一行不畫長條
        let note: String?
        let accessibilityText: String
    }

    struct Splits {
        /// 「每公里」「每 5 公里」
        var title: String
        /// 「5.20 公里」
        var trailing: String
        /// 騎車：「數字是平均時速（公里/時）」
        var caption: String?
        var rows: [SplitRow]
    }

    /// 高度小圖
    struct Elevation {
        struct Point: Identifiable {
            let id: Int
            let km: Double
            let meters: Double
        }
        /// 「爬升 **18 m**・下降 **17 m**・最高比起點高 **9 m**」（數字粗體、不上色；樣稿②-5）
        var summary: FinanceLine
        var points: [Point]
        /// 圖的上下範圍（公尺，比起點高多少）
        var floor: Double
        var ceiling: Double
        var totalKm: Double
        /// 最高那一點＋小字「+9 m」（比起點高不到 1 公尺不標）
        var peak: Point?
        var peakLabel: String
        var accessibilityText: String
    }

    /// Apple 健康那一列
    struct HealthLine {
        let text: String
        /// 已存進：綠字
        let good: Bool
    }

    /// 資料一列；note 是值下面的灰字（大卡「估的，依體重 72.4 kg」）
    struct InfoItem: Identifiable {
        let id: String
        let label: String
        let value: String
        var note: String? = nil
    }

    /// 動作一行（重訓、或一趟裡不只一個動作）
    struct Move: Identifiable {
        let id: UUID
        let name: String
        let detail: String
    }

    // MARK: 欄位

    var sessionId: UUID
    var sport: WorkoutSport
    /// 工具列中間、刪除確認框用的名字（WorkoutFacts.title）
    var title: String
    var board: Board
    var scene: WorkoutTrailScene
    var tiles: [Tile]
    /// 0 件整區不出現
    var gains: [Gain]
    /// 0 件整區不出現
    var checks: [Check]
    /// nil＝沒有路線（換 routeNote 一行灰字；重訓兩個都 nil、整區不出現）
    var route: RouteMap?
    var routeNote: String?
    var splits: Splits?
    var elevation: Elevation?
    /// 空的整區不出現
    var moves: [Move]
    /// nil＝裝置不支援「健康」
    var health: HealthLine?
    var info: [InfoItem]
    /// 換一趟列（同一週，舊到新）；不到兩顆不出現
    var switcher: [FinanceSwitcherItem]
}

// MARK: - 算

extension WorkoutCardData {

    /// 一次算完。在 .task(id:) 裡、主執行緒呼叫（WorkoutFormat 的 DateFormatter、MoneyBoardText 共用）。
    /// sessions：全部運動（收穫、換一趟列用）；hkEnabled：健康頁的 Apple 健康開關；hkAvailable：這台裝置有沒有「健康」
    @MainActor
    static func build(session s: WorkoutSession, sessions: [WorkoutSession], prefs: WorkoutPrefs,
                      bodyWeightKg: Double?, hkEnabled: Bool, hkAvailable: Bool,
                      now: Date = Date()) -> WorkoutCardData {
        let sport = s.primarySport
        let title = WorkoutFacts.title(s)
        // 每公里、高度、路線看「有路線的那個動作」；沒有路線看第一個有氧動作（手動補記也可能有分段？沒有，但不怕）
        let main = s.firstRouteExercise ?? s.cardioExercises.first
        let validSplits = main.flatMap { WorkoutFacts.validSplits($0) }
        let plan = validSplits.flatMap { splitPlan($0, sport: main?.resolvedSport ?? sport) }
        let elevation = s.firstRouteExercise.flatMap { WorkoutFacts.elevation($0, in: s) }
        let elevationShown = elevation.flatMap { makeElevation($0) }
        let goal = goalFacts(s, sessions: sessions, prefs: prefs, sport: sport, now: now)

        var card = WorkoutCardData(
            sessionId: s.id, sport: sport, title: title,
            board: Board(), scene: WorkoutFacts.trailScene(s, bodyWeightKg: bodyWeightKg),
            tiles: [], gains: [], checks: [],
            route: nil, routeNote: nil, splits: nil, elevation: elevationShown,
            moves: makeMoves(s, bodyWeightKg: bodyWeightKg),
            health: makeHealth(s, hkEnabled: hkEnabled, hkAvailable: hkAvailable),
            info: makeInfo(s, bodyWeightKg: bodyWeightKg),
            switcher: makeSwitcher(s, sessions: sessions))

        card.board = makeBoard(s, title: title, sport: sport, bodyWeightKg: bodyWeightKg, madeGoal: goal.madeGoal)
        if sport == .strength {
            card.tiles = strengthTiles(s, bodyWeightKg: bodyWeightKg)
        } else {
            card.tiles = cardioTiles(s, main: main, sport: sport, plan: plan, elevation: elevation,
                                     elevationShown: elevationShown != nil, bodyWeightKg: bodyWeightKg)
        }
        card.gains = goal.gains
        card.checks = makeChecks(s, main: main, splitsValid: validSplits != nil)
        if let e = s.firstRouteExercise {
            card.route = makeRoute(e, sport: e.resolvedSport, pauses: s.pauses,
                                   storedAverage: validSplits != nil ? storedAverage(e) : nil)
        }
        if card.route == nil {
            card.routeNote = makeRouteNote(s, sport: sport)
        }
        if let e = main, let plan {
            card.splits = makeSplits(plan, exercise: e)
        }
        return card
    }

    // MARK: 字的小工具

    /// 大卡格、資料列的數字：「約 340」「402」（WorkoutFormat.kcal 去掉「大卡」兩個字，同一套進位）
    private static func kcalNumber(_ kcal: Double, estimated: Bool) -> String {
        WorkoutFormat.kcal(kcal, estimated: estimated).replacingOccurrences(of: " 大卡", with: "")
    }

    /// 「6 分 02 秒」（VoiceOver 唸的配速、時間）
    private static func spokenClock(seconds: Double) -> String {
        let t = WorkoutFormat.wholeSeconds(seconds)
        let h = t / 3600
        let m = (t % 3600) / 60
        let sec = t % 60
        if h > 0 { return "\(h) 小時 \(m) 分 \(sec) 秒" }
        return String(format: "%d 分 %02d 秒", m, sec)
    }

    /// 「4」（公尺取整數，同 WorkoutFormat.climb 的進位）
    private static func meters(_ v: Double) -> String {
        "\(WorkoutFormat.wholeSeconds(v))"
    }

    /// 開始到結束：有 endedAt（App 記的）才算；跟移動時間對不上就退回「開始＋移動時間」（workoutEnd）
    private static func endDate(_ s: WorkoutSession) -> Date? {
        guard s.endedAt != nil else { return nil }
        return s.workoutEnd(movingMinutes: WorkoutFacts.movingMinutes(s))
    }

    // MARK: ① 看板

    private static func makeBoard(_ s: WorkoutSession, title: String, sport: WorkoutSport,
                                  bodyWeightKg: Double?, madeGoal: Bool) -> Board {
        var b = Board()
        var date = WorkoutFormat.day(s.date) + " " + WorkoutFormat.time(s.date)
        if let end = endDate(s) {
            date += "–" + WorkoutFormat.time(end)
        }
        b.date = date
        b.dateIcon = sport.icon
        b.capsule = sport.displayName
        b.capsuleIcon = sport.icon
        b.label = title
        b.seed = MoneyItem.seed(s.id)

        let km = s.totalDistanceKm
        let moving = WorkoutFacts.movingMinutes(s)
        if sport == .strength {
            b.big = strengthBig(s, moving: moving, bodyWeightKg: bodyWeightKg)
            b.line = strengthLine(s)
        } else if km > 0 {
            b.big = WorkoutFormat.preciseKmNumber(km, sport: sport) + " 公里"
            b.line = cardioLine(km: km, moving: moving, sport: sport)
        } else if moving > 0 {
            // 有氧沒填距離（飛輪、補記只填時間）
            b.big = WorkoutFormat.total(minutes: moving)
            b.line = FinanceLine(runs: [FinanceRun(text: "移動 "),
                                        FinanceRun(text: WorkoutFormat.clock(minutes: moving), bold: true)])
        } else {
            b.big = sport.displayName
        }
        b.greeting = madeGoal ? ["Goal", "reached!"] : greeting(sport)

        var parts: [String] = [b.date, title, sport.displayName + " " + b.big]
        let plain = b.line.plain.replacingOccurrences(of: "・", with: "，")
        if !plain.isEmpty { parts.append(plain) }
        if madeGoal { parts.append("這一趟讓這週達標") }
        b.accessibilityText = parts.joined(separator: "，") + "。"
        return b
    }

    /// 「**32:10**・配速 **6'11"**」；騎車「**1:05:12**・平均時速 **21.5**」（粗體不上色）
    private static func cardioLine(km: Double, moving: Double, sport: WorkoutSport) -> FinanceLine {
        guard moving > 0 else { return FinanceLine() }
        var runs = [FinanceRun(text: WorkoutFormat.clock(minutes: moving), bold: true)]
        if sport == .bike {
            if let v = WorkoutFormat.speedKmh(km: km, minutes: moving) {
                runs.append(FinanceRun(text: "・平均時速 "))
                runs.append(FinanceRun(text: WorkoutFormat.speedNumber(v), bold: true))
            }
        } else {
            runs.append(FinanceRun(text: "・配速 "))
            runs.append(FinanceRun(text: WorkoutFormat.pace(km: km, minutes: moving), bold: true))
        }
        return FinanceLine(runs: runs)
    }

    /// 重訓大字：有訓練量「2,160 kg」，不然「45 分鐘」，都沒有「3 個動作」
    private static func strengthBig(_ s: WorkoutSession, moving: Double, bodyWeightKg: Double?) -> String {
        if let v = s.totalVolume(bodyWeightKg: bodyWeightKg), v.isFinite, v >= 1, v < 1e12 {
            return Int(v.rounded()).formatted() + " kg"
        }
        if moving > 0 { return WorkoutFormat.total(minutes: moving) }
        let n = s.strengthExercises.count
        return n > 0 ? "\(n) 個動作" : "重訓"
    }

    /// 重訓一句：「3 個動作・共 9 組」；手錶帶進來沒有動作：「Apple Watch 記的」
    private static func strengthLine(_ s: WorkoutSession) -> FinanceLine {
        let n = s.strengthExercises.count
        guard n > 0 else {
            return WorkoutFacts.source(of: s) == .watch ? FinanceLine.text("Apple Watch 記的") : FinanceLine()
        }
        let sets = s.totalSets
        return FinanceLine.text(sets > 0 ? "\(n) 個動作・共 \(sets) 組" : "\(n) 個動作")
    }

    /// 手寫（judge §4.3）：跑步 Nice / run!、健走 Good / walk!、騎車 Nice / ride!、登山 Great / hike!、重訓 Well / done!、其他 Nice / work!
    private static func greeting(_ sport: WorkoutSport) -> [String] {
        switch sport {
        case .run: return ["Nice", "run!"]
        case .walk: return ["Good", "walk!"]
        case .bike: return ["Nice", "ride!"]
        case .hike: return ["Great", "hike!"]
        case .strength: return ["Well", "done!"]
        case .other: return ["Nice", "work!"]
        }
    }

    // MARK: ① 六格

    private static func cardioTiles(_ s: WorkoutSession, main: WorkoutExercise?, sport: WorkoutSport,
                                    plan: SplitPlan?, elevation: WorkoutElevation?, elevationShown: Bool,
                                    bodyWeightKg: Double?) -> [Tile] {
        let km = s.totalDistanceKm
        let moving = WorkoutFacts.movingMinutes(s)
        var tiles: [Tile] = []

        // 距離
        tiles.append(Tile(id: "distance", label: "距離",
                          value: km > 0 ? WorkoutFormat.preciseKmNumber(km, sport: sport) + " 公里" : "—"))

        // 時間（小字「總共 34:40」：開始到結束，含暫停；差不到 5 秒不寫）
        var totalText = ""
        if let end = endDate(s) {
            let span = end.timeIntervalSince(s.date)
            if span - moving * 60 >= 5 { totalText = "總共 " + WorkoutFormat.clock(seconds: span) }
        }
        tiles.append(Tile(id: "time", label: "時間",
                          value: moving > 0 ? WorkoutFormat.clock(minutes: moving) : "—",
                          sub: totalText))

        // 平均配速／平均時速
        if sport == .bike {
            let v = WorkoutFormat.speedKmh(km: km, minutes: moving)
            tiles.append(Tile(id: "speed", label: "平均時速",
                              value: v.map { WorkoutFormat.speedNumber($0) } ?? "—",
                              sub: v == nil ? "" : "公里/時"))
        } else {
            tiles.append(Tile(id: "pace", label: "平均配速", value: WorkoutFormat.pace(km: km, minutes: moving)))
        }

        // 最快一公里（騎車滿 5 公里：最快 5 公里，寫時速）
        tiles.append(fastestTile(plan))

        // 爬升
        tiles.append(climbTile(s, main: main, elevation: elevation, shown: elevationShown))

        // 大卡
        tiles.append(kcalTile(s, bodyWeightKg: bodyWeightKg))
        return tiles
    }

    private static func fastestTile(_ plan: SplitPlan?) -> Tile {
        guard let plan, let i = plan.best, i < plan.groups.count else {
            return Tile(id: "fastest", label: "最快一公里", value: "—")
        }
        let g = plan.groups[i]
        let label = plan.step == 5 ? "最快 5 公里" : "最快一公里"
        let sub = plan.step == 5 ? "第 \(g.firstKm)–\(g.lastKm) 公里" : "第 \(g.lastKm) 公里"
        let value = plan.isBike
            ? WorkoutFormat.speedNumber(g.speedKmh)
            : WorkoutFormat.pace(g.paceSeconds / 60)
        return Tile(id: "fastest", label: label, value: value, sub: sub, tap: .splits)
    }

    private static func climbTile(_ s: WorkoutSession, main: WorkoutExercise?, elevation: WorkoutElevation?,
                                  shown: Bool) -> Tile {
        guard let e = main, let gain = WorkoutFacts.climb(e, in: s) else {
            return Tile(id: "climb", label: "爬升", value: "—")
        }
        guard gain >= 10 else {
            return Tile(id: "climb", label: "爬升", value: "平路")
        }
        if shown, let el = elevation {
            return Tile(id: "climb", label: "爬升", value: WorkoutFormat.climb(gain),
                        sub: "最高比起點高 " + meters(el.maxAboveStartM) + " m", tap: .elevation)
        }
        return Tile(id: "climb", label: "爬升", value: WorkoutFormat.climb(gain))
    }

    private static func kcalTile(_ s: WorkoutSession, bodyWeightKg: Double?) -> Tile {
        guard let k = WorkoutFacts.kcal(s, bodyWeightKg: bodyWeightKg) else {
            return Tile(id: "kcal", label: "大卡", value: "—", sub: bodyWeightKg == nil ? "沒有體重" : "")
        }
        let sub: String
        if k.estimated {
            sub = "估的"
        } else if WorkoutFacts.source(of: s) == .watch {
            sub = "Apple Watch 量的"
        } else {
            sub = ""
        }
        return Tile(id: "kcal", label: "大卡", value: kcalNumber(k.kcal, estimated: k.estimated), sub: sub)
    }

    /// 重訓：訓練量、動作數、總組數、總下數、時間、大卡
    private static func strengthTiles(_ s: WorkoutSession, bodyWeightKg: Double?) -> [Tile] {
        let moves = s.strengthExercises.count
        let moving = WorkoutFacts.movingMinutes(s)
        var volume = "—"
        if let v = s.totalVolume(bodyWeightKg: bodyWeightKg), v.isFinite, v >= 1, v < 1e12 {
            volume = Int(v.rounded()).formatted() + " kg"
        }
        return [
            Tile(id: "volume", label: "訓練量", value: volume),
            Tile(id: "moves", label: "動作", value: moves > 0 ? "\(moves) 個" : "—"),
            Tile(id: "sets", label: "總組數", value: s.totalSets > 0 ? "\(s.totalSets) 組" : "—"),
            Tile(id: "reps", label: "總下數", value: s.totalReps > 0 ? "\(s.totalReps) 下" : "—"),
            Tile(id: "time", label: "時間", value: moving > 0 ? WorkoutFormat.clock(minutes: moving) : "—"),
            kcalTile(s, bodyWeightKg: bodyWeightKg)
        ]
    }

    // MARK: ② 這趟的收穫

    private struct GoalFacts {
        var gains: [Gain] = []
        /// 這一趟讓這週達標（扣掉這趟還不到、加上到了）：看板手寫 Goal / reached!
        var madeGoal = false
    }

    /// 只在這一趟在「這週」時；運動是這一趟的運動（騎車那趟講騎車）
    private static func goalFacts(_ s: WorkoutSession, sessions: [WorkoutSession], prefs: WorkoutPrefs,
                                  sport: WorkoutSport, now: Date) -> GoalFacts {
        var out = GoalFacts()
        guard WorkoutFacts.isInWeek(s.date, of: now) else { return out }

        if [WorkoutSport.run, .walk, .bike, .hike].contains(sport) {
            let p = WorkoutFacts.weekProgress(sessions, prefs: prefs, sport: sport, now: now)
            let trip = s.exercises
                .filter { $0.kind == .cardio && $0.resolvedSport == sport }
                .reduce(0) { $0 + max(0, $1.distanceKm) }
            let weekStart = WorkoutFacts.weekStart(of: now)
            let others = sessions.filter { $0.id != s.id }
            let before = WorkoutFacts.distanceKm(others, sport: sport, from: weekStart, to: s.date)
            let after = before + trip
            // 「這週跑步 14.6 公里」：數字粗體、不上色（樣稿②-5；同房屋、車子卡的一句話）
            let head = [FinanceRun(text: "這週\(sport.displayName) "),
                        FinanceRun(text: WorkoutFormat.kmNumber(p.doneKm), bold: true),
                        FinanceRun(text: " 公里")]
            var line: FinanceLine? = nil
            if let g = p.goalKm {
                if before < g - 0.05 && after >= g - 0.05 {
                    out.madeGoal = true
                    let text = "這一趟讓這週達標（\(WorkoutFormat.kmNumber(after))／\(HealthPageData.goalKmText(g))）"
                    line = FinanceLine(runs: [FinanceRun(text: text, bold: true, tone: .good)])
                } else if p.reached {
                    line = FinanceLine(runs: head + [FinanceRun(text: "，"),
                                                     FinanceRun(text: "已達標", bold: true, tone: .good)])
                } else if p.doneKm >= 0.05 {
                    // 「，目標 20 公里還差 5.4 公里」（數字照目標格的寫法：整數不寫小數）
                    let rest = [FinanceRun(text: "，目標 "),
                                FinanceRun(text: goalNumber(g), bold: true),
                                FinanceRun(text: " 公里還差 "),
                                FinanceRun(text: goalNumber(p.remainingKm), bold: true),
                                FinanceRun(text: " 公里")]
                    line = FinanceLine(runs: head + rest)
                }
            } else if p.doneKm >= 0.05 {
                line = FinanceLine(runs: head)
            }
            if let line {
                out.gains.append(Gain(id: "goal", icon: "target", sport: sport, line: line))
            }
        } else if sport == .strength {
            let n = WorkoutFacts.week(of: now)
            let count = sessions.filter { $0.date >= n.start && $0.date < n.end && !$0.strengthExercises.isEmpty }.count
            if count > 0 {
                out.gains.append(Gain(id: "goal", icon: "dumbbell.fill", sport: .strength,
                                      line: FinanceLine(runs: [FinanceRun(text: "這週重訓 "),
                                                               FinanceRun(text: "\(count)", bold: true),
                                                               FinanceRun(text: " 次")])))
            }
        }

        let streak = WorkoutFacts.streakWeeks(sessions, now: now)
        if streak >= 2 {
            out.gains.append(Gain(id: "streak", icon: "flame.fill", sport: nil,
                                  line: FinanceLine(runs: [FinanceRun(text: "連續 "),
                                                           FinanceRun(text: "\(streak)", bold: true),
                                                           FinanceRun(text: " 週有運動")])))
        }
        return out
    }

    /// 目標格同一套寫法的數字：HealthPageData.goalKmText 去掉「 公里」（整數「20」、其他「5.4」）
    private static func goalNumber(_ km: Double) -> String {
        HealthPageData.goalKmText(km).replacingOccurrences(of: " 公里", with: "")
    }

    // MARK: ③ 要確認

    private static func makeChecks(_ s: WorkoutSession, main: WorkoutExercise?, splitsValid: Bool) -> [Check] {
        var out: [Check] = []
        if s.isLegacyRouteMissing {
            out.append(Check(id: "legacy", icon: "map",
                             message: "這一趟是舊版記錄的，路線當時沒存到；距離和時間大致是對的。"))
        }
        if let e = main, let sp = e.splits, !sp.isEmpty, !splitsValid {
            out.append(Check(id: "splits", icon: "pencil.circle",
                             message: "這一趟的距離或時間改過，每公里分段對不上了，先不顯示。"))
        }
        return out
    }

    // MARK: ④ 路線

    /// 沒有路線時那一行灰字（重訓不出現）
    private static func makeRouteNote(_ s: WorkoutSession, sport: WorkoutSport) -> String? {
        guard sport != .strength else { return nil }
        if s.isLegacyRouteMissing { return "這一趟是舊版記錄的，路線沒有存到" }
        let src = WorkoutFacts.source(of: s)
        if src == .manual { return "手動補記，沒有路線" }
        if src == .watch { return "Apple Watch 這一趟沒有路線" }
        return "這一趟沒有路線"
    }

    /// 存下來的平均（秒/公里、公里/時）：分段對得上（沒編輯過）時，圖例寫這個數字，跟看板一樣
    private static func storedAverage(_ e: WorkoutExercise) -> (pace: Double, speed: Double)? {
        guard e.distanceKm > 0, e.durationMinutes > 0 else { return nil }
        return (e.durationMinutes * 60 / e.distanceKm, e.distanceKm / (e.durationMinutes / 60))
    }

    private static func coordinate(_ p: RoutePoint) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon)
    }

    /// 路線地圖：快慢上色的線段、每公里小牌、暫停小牌、鏡頭
    private static func makeRoute(_ e: WorkoutExercise, sport: WorkoutSport, pauses: [WorkoutPause]?,
                                  storedAverage stored: (pace: Double, speed: Double)?) -> RouteMap? {
        let r = e.route.filter { $0.lat.isFinite && $0.lon.isFinite && abs($0.lat) <= 90 && abs($0.lon) <= 180 }
        guard r.count >= 2, let b = RouteMath.bounds(r), let first = r.first, let last = r.last else { return nil }
        let n = r.count

        // 1. 每一步的距離與時間（換段＝暫停的空隙，不算距離也不算時間）
        var stepD = [Double](repeating: 0, count: n)
        var stepT = [Double](repeating: 0, count: n)
        var totalD = 0.0
        var totalT = 0.0
        for i in 1..<n {
            guard (r[i - 1].seg ?? 0) == (r[i].seg ?? 0) else { continue }
            var d = CLLocation(latitude: r[i - 1].lat, longitude: r[i - 1].lon)
                .distance(from: CLLocation(latitude: r[i].lat, longitude: r[i].lon))
            if !d.isFinite || d < 0 { d = 0 }
            let t = r[i].t - r[i - 1].t
            let dt = (t.isFinite && t > 0) ? t : 0
            stepD[i] = d
            stepT[i] = dt
            totalD += d
            totalT += dt
        }

        // 2. 這條路線自己的平均（編輯過距離也不受影響）
        let isBike = sport == .bike
        let paced = totalD >= 200 && totalT > 0
        let avgPace = paced ? totalT / (totalD / 1000) : 0
        let avgSpeed = paced ? (totalD / 1000) / (totalT / 3600) : 0
        // 每 100 公尺一小段；長的路線放寬（地圖上最多約 120 條線，不卡）
        let chunkM = max(100, totalD / 120)

        func level(_ d: Double, _ t: Double) -> WorkoutPaceLevel {
            guard d > 0, t > 0 else { return .even }
            if isBike {
                return WorkoutPaceLevel.forSpeed(kmh: (d / 1000) / (t / 3600), average: avgSpeed)
            }
            return WorkoutPaceLevel.forPace(seconds: t / (d / 1000), average: avgPace)
        }

        // 3. 一段一段（同一個 seg）切小段、相鄰同一級併成一條
        var pieces: [RouteMap.Piece] = []
        var a = 0
        while a < n {
            let seg = r[a].seg ?? 0
            var bEnd = a
            while bEnd + 1 < n, (r[bEnd + 1].seg ?? 0) == seg { bEnd += 1 }
            if bEnd > a {
                // 3a. 切小段（from、to 是點的索引；d、t 是這一小段的距離與時間）
                var raw: [(from: Int, to: Int, d: Double, t: Double)] = []
                var from = a
                var cd = 0.0
                var ct = 0.0
                for i in (a + 1)...bEnd {
                    cd += stepD[i]
                    ct += stepT[i]
                    if cd >= chunkM {
                        raw.append((from: from, to: i, d: cd, t: ct))
                        from = i
                        cd = 0
                        ct = 0
                    }
                }
                if from < bEnd {
                    if let tail = raw.last, cd < chunkM / 2 {
                        // 段尾剩下不到半小段：併進前一小段（太短算出來的快慢不準）
                        raw[raw.count - 1] = (from: tail.from, to: bEnd, d: tail.d + cd, t: tail.t + ct)
                    } else {
                        raw.append((from: from, to: bEnd, d: cd, t: ct))
                    }
                }
                // 3b. 每一小段的快慢連前後各一小段一起算（約 300 公尺）：GPS 每點幾公尺的誤差，
                //     在 100 公尺裡就是好幾秒，單看一小段顏色會花掉（build/v3/g3/sim_g3.py：雜訊 2 公尺 30 次，平均 11.5 條線）
                var levels: [WorkoutPaceLevel?] = []
                for j in raw.indices {
                    guard paced else {
                        levels.append(nil)
                        continue
                    }
                    let lo = max(0, j - 1)
                    let hi = min(raw.count - 1, j + 1)
                    var d = 0.0
                    var t = 0.0
                    for q in lo...hi {
                        d += raw[q].d
                        t += raw[q].t
                    }
                    let lv: WorkoutPaceLevel = d >= 50 ? level(d, t) : WorkoutPaceLevel.even
                    levels.append(lv)
                }
                // 3c. 相鄰同一級併成一條（頭尾共用一點，線接得起來）
                var k = 0
                while k < raw.count {
                    var m = k
                    while m + 1 < raw.count, levels[m + 1] == levels[k] { m += 1 }
                    let coords = (raw[k].from...raw[m].to).map { coordinate(r[$0]) }
                    pieces.append(RouteMap.Piece(id: pieces.count, coordinates: coords, level: levels[k]))
                    k = m + 1
                }
            }
            a = bEnd + 1
        }
        guard !pieces.isEmpty else { return nil }

        // 4. 每整公里（騎車每 5 公里）一塊小牌：沿路線量（暫停的空隙不算），在那一步裡照比例內插
        var marks: [RouteMap.Mark] = []
        let every = isBike ? 5000.0 : 1000.0
        var cum = 0.0
        var next = every
        for i in 1..<n where stepD[i] > 0 {
            let d = stepD[i]
            while cum + d >= next, marks.count < 200 {
                let k = (next - cum) / d
                let lat = r[i - 1].lat + (r[i].lat - r[i - 1].lat) * k
                let lon = r[i - 1].lon + (r[i].lon - r[i - 1].lon) * k
                marks.append(RouteMap.Mark(id: marks.count, text: "\(Int((next / 1000).rounded()))",
                                           coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
                next += every
            }
            cum += d
        }

        // 5. 暫停的地方（上一段最後一點）：段數跟暫停次數對得上才放，對不上寧可不放
        var boundaries: [Int] = []
        for i in 1..<n where (r[i - 1].seg ?? 0) != (r[i].seg ?? 0) {
            boundaries.append(i - 1)
        }
        var pauseMarks: [RouteMap.Mark] = []
        let ps = pauses ?? []
        if !ps.isEmpty, ps.count == boundaries.count {
            for (j, idx) in boundaries.enumerated() {
                pauseMarks.append(RouteMap.Mark(id: j, text: "暫停 " + WorkoutFormat.clock(seconds: ps[j].seconds),
                                                coordinate: coordinate(r[idx])))
            }
        }

        // 6. 圖例那句：沒編輯過寫存下來的平均（跟看板同一個數字）；編輯過寫路線自己的平均
        var note = ""
        if paced {
            if isBike {
                let v = stored?.speed ?? avgSpeed
                note = "（跟這趟平均時速 " + WorkoutFormat.speedNumber(v) + " 比）"
            } else {
                let p = stored?.pace ?? avgPace
                note = "（跟這趟平均 " + WorkoutFormat.pace(p / 60) + " 比）"
            }
        }
        let spoken = paced
            ? "路線依快慢上色：藍色比較快、灰色差不多、琥珀色比較慢" + note
            : "這一趟的路線"

        let span = cameraSpan(r, centerLatitude: b.center.latitude)
        return RouteMap(sport: sport, pieces: pieces, marks: marks, pauses: pauseMarks,
                        start: coordinate(first), end: coordinate(last),
                        center: b.center, latitudeDelta: span.lat, longitudeDelta: span.lon,
                        paced: paced, legendNote: note, accessibilityText: spoken)
    }

    /// 鏡頭範圍（度）：路線自己的南北、東西各放大 1.4 倍（起點圈、終點旗、小牌不貼邊），兩邊至少 300 公尺。
    /// 卡片裡的地圖是 200pt 高的長條：照 RouteMapView 用對角線畫一個正方形範圍，沿河 2.5 公里寬、0.5 公里高的 U 形
    /// 只佔畫面寬度不到一半；分開算南北、東西，地圖會把整條路放滿長條（MapKit 會再照畫面長寬比放寬到全部看得到）。
    /// 夾在合法範圍內（範圍不合法地圖會閃退）
    private static func cameraSpan(_ r: [RoutePoint], centerLatitude: Double) -> (lat: Double, lon: Double) {
        let lats = r.map(\.lat)
        let lons = r.map(\.lon)
        let latExtent = (lats.max() ?? 0) - (lats.min() ?? 0)
        let lonExtent = (lons.max() ?? 0) - (lons.min() ?? 0)
        let minLat = 300.0 / 111_320.0
        let minLon = minLat / max(0.2, cos(centerLatitude * Double.pi / 180))
        let lat = min(170, max(latExtent.isFinite ? latExtent * 1.4 : 0, minLat))
        let lon = min(350, max(lonExtent.isFinite ? lonExtent * 1.4 : 0, minLon))
        return (lat, lon)
    }

    // MARK: ⑤ 每公里

    /// 分好組的分段：跑走登山每公里一組；騎車滿 5 公里就 5 公里一組（不滿的併進最後一行）
    private struct SplitPlan {
        struct Group {
            var meters: Double
            var seconds: Double
            /// 這一組的爬升；有一段不知道就整組不知道
            var climb: Double?
            /// 第幾公里起訖（1 起）
            var firstKm: Int
            var lastKm: Int
            /// 秒/公里
            var paceSeconds: Double { meters > 0 ? seconds / (meters / 1000) : 0 }
            /// 公里/時
            var speedKmh: Double { seconds > 0 ? (meters / 1000) / (seconds / 3600) : 0 }
        }
        var groups: [Group]
        /// 最後不滿一組（跑步：不滿一公里那段；騎車：剩下的公里＋不滿一公里那段）
        var tail: Group?
        var step: Int
        var isBike: Bool
        var avgPace: Double
        var avgSpeed: Double
        /// 最快那一組（groups 的索引）
        var best: Int?
    }

    private static func splitPlan(_ sp: [WorkoutSplit], sport: WorkoutSport) -> SplitPlan? {
        let full = sp.filter { $0.meters >= 999 }
        guard !full.isEmpty else { return nil }
        let totalM = sp.reduce(0) { $0 + $1.meters }
        let totalS = sp.reduce(0) { $0 + $1.seconds }
        guard totalM > 0, totalS > 0 else { return nil }
        let isBike = sport == .bike
        let step = (isBike && full.count >= 5) ? 5 : 1

        func merge(_ part: [WorkoutSplit], firstKm: Int, lastKm: Int) -> SplitPlan.Group {
            var climb: Double? = 0
            for x in part {
                if let c = x.climbM, let acc = climb { climb = acc + c } else { climb = nil }
            }
            return SplitPlan.Group(meters: part.reduce(0) { $0 + $1.meters },
                                   seconds: part.reduce(0) { $0 + $1.seconds },
                                   climb: climb, firstKm: firstKm, lastKm: lastKm)
        }

        var groups: [SplitPlan.Group] = []
        let groupCount = full.count / step
        for g in 0..<groupCount {
            let part = Array(full[(g * step)..<((g + 1) * step)])
            groups.append(merge(part, firstKm: g * step + 1, lastKm: (g + 1) * step))
        }
        // 剩下的：沒湊滿一組的整公里＋不滿一公里那段
        var rest = Array(full[(groupCount * step)...])
        rest.append(contentsOf: sp.filter { $0.meters < 999 })
        let restM = rest.reduce(0) { $0 + $1.meters }
        let tail: SplitPlan.Group? = restM >= 50
            ? merge(rest, firstKm: groupCount * step + 1, lastKm: groupCount * step + rest.count)
            : nil

        var best: Int? = nil
        for (i, g) in groups.enumerated() where g.seconds > 0 {
            if let b = best {
                if g.paceSeconds < groups[b].paceSeconds { best = i }
            } else {
                best = i
            }
        }
        return SplitPlan(groups: groups, tail: tail, step: step, isBike: isBike,
                         avgPace: totalS / (totalM / 1000), avgSpeed: (totalM / 1000) / (totalS / 3600),
                         best: best)
    }

    private static func levelWord(_ l: WorkoutPaceLevel) -> String {
        l == .even ? "" : l.label
    }

    private static func makeSplits(_ plan: SplitPlan, exercise e: WorkoutExercise) -> Splits? {
        guard !plan.groups.isEmpty else { return nil }
        let bestPace = plan.best.map { plan.groups[$0].paceSeconds } ?? 0
        let bestSpeed = plan.best.map { plan.groups[$0].speedKmh } ?? 0
        let starOK = plan.groups.count >= 2
        var rows: [SplitRow] = []

        for (i, g) in plan.groups.enumerated() {
            let lv: WorkoutPaceLevel
            let value: String
            let fraction: Double
            var spoken: String
            if plan.isBike {
                lv = WorkoutPaceLevel.forSpeed(kmh: g.speedKmh, average: plan.avgSpeed)
                value = WorkoutFormat.speedNumber(g.speedKmh)
                fraction = bestSpeed > 0 ? g.speedKmh / bestSpeed : 0
                spoken = (plan.step == 5 ? "第 \(g.firstKm) 到 \(g.lastKm) 公里" : "第 \(g.lastKm) 公里")
                    + "，時速 " + value
            } else {
                lv = WorkoutPaceLevel.forPace(seconds: g.paceSeconds, average: plan.avgPace)
                value = WorkoutFormat.pace(g.paceSeconds / 60)
                fraction = g.paceSeconds > 0 ? bestPace / g.paceSeconds : 0
                spoken = "第 \(g.lastKm) 公里，" + spokenClock(seconds: g.paceSeconds)
            }
            let word = levelWord(lv)
            let climb = g.climb.map { "+" + meters($0) + " m" } ?? ""
            let star = starOK && plan.best == i
            if !word.isEmpty { spoken += "，" + word }
            if let c = g.climb { spoken += "，爬升 " + meters(c) + " 公尺" }
            if star { spoken += "，最快" }
            rows.append(SplitRow(id: i, label: "\(g.lastKm)", value: value,
                                 fraction: min(1, max(0, fraction)), level: lv, levelWord: word,
                                 climb: climb, star: star, note: nil, accessibilityText: spoken))
        }

        if let t = plan.tail {
            let label = String(format: "%.1f", t.meters / 1000)
            if plan.isBike {
                let value = WorkoutFormat.speedNumber(t.speedKmh)
                rows.append(SplitRow(id: rows.count, label: label, value: value, fraction: 0, level: .even,
                                     levelWord: "", climb: "", star: false, note: "（最後這 \(label) 公里的時速）",
                                     accessibilityText: "最後 \(label) 公里，時速 " + value))
            } else {
                // 「0.2　1'14"（換算每公里 6'10"，跟平均差不多）」：200 公尺以上才比快慢（太短不準）
                let perKm = t.paceSeconds
                var tailNote = "（換算每公里 " + WorkoutFormat.pace(perKm / 60)
                if t.meters >= 200, perKm > 0 {
                    switch WorkoutPaceLevel.forPace(seconds: perKm, average: plan.avgPace) {
                    case .even: tailNote += "，跟平均差不多"
                    case .faster, .muchFaster: tailNote += "，比平均快"
                    case .slower, .muchSlower: tailNote += "，比平均慢"
                    }
                }
                tailNote += "）"
                rows.append(SplitRow(id: rows.count, label: label, value: WorkoutFormat.pace(t.seconds / 60),
                                     fraction: 0, level: .even, levelWord: "", climb: "", star: false,
                                     note: tailNote,
                                     accessibilityText: "最後 \(label) 公里，" + spokenClock(seconds: t.seconds)
                                        + "，換算每公里 " + spokenClock(seconds: perKm)))
            }
        }

        return Splits(title: plan.step == 5 ? "每 5 公里" : "每公里",
                      trailing: WorkoutFormat.preciseKmNumber(e.distanceKm, sport: e.resolvedSport) + " 公里",
                      caption: plan.isBike ? "數字是平均時速（公里/時）" : nil,
                      rows: rows)
    }

    // MARK: ⑥ 高度

    /// 爬升 10 公尺以上（存下來的、知道的）才出現
    private static func makeElevation(_ el: WorkoutElevation) -> Elevation? {
        guard let gain = el.gainM, gain >= 10, el.samples.count >= 2 else { return nil }
        let points = el.samples.enumerated().map { i, p in Elevation.Point(id: i, km: p.km, meters: p.meters) }
        let ms = points.map(\.meters)
        let lo = ms.min() ?? 0
        let hi = ms.max() ?? 0
        // 圖的上下範圍要是有限的數（ClosedRange 下界大於上界、或碰到 NaN 會閃退）
        guard lo.isFinite, hi.isFinite, ms.allSatisfy({ $0.isFinite }) else { return nil }
        let pad = max(2, (hi - lo) * 0.15)
        let total = points.last?.km ?? 0
        guard total.isFinite, total > 0 else { return nil }
        // 最高點的小字跟上面那一行、六格「最高比起點高 9 m」同一個數字（maxAboveStartM）；
        // 取樣點的最高值是內插出來的，可能比它少一點，四捨五入後會差 1 公尺
        let peak = (hi >= 1 && el.maxAboveStartM >= 1) ? points.first(where: { $0.meters == hi }) : nil
        let up = WorkoutFormat.climb(gain)
        let down = meters(el.lossM)
        let top = meters(el.maxAboveStartM)
        let summary = FinanceLine(runs: [FinanceRun(text: "爬升 "), FinanceRun(text: up, bold: true),
                                         FinanceRun(text: "・下降 "), FinanceRun(text: "\(down) m", bold: true),
                                         FinanceRun(text: "・最高比起點高 "), FinanceRun(text: "\(top) m", bold: true)])
        let spoken = "高度：爬升 \(meters(gain)) 公尺，下降 \(down) 公尺，最高比起點高 \(top) 公尺"
        return Elevation(summary: summary, points: points,
                         floor: min(lo, 0) - pad * 0.5, ceiling: hi + pad,
                         totalKm: total, peak: peak, peakLabel: "+\(top) m",
                         accessibilityText: spoken)
    }

    // MARK: 動作

    /// 重訓、或一趟裡不只一個動作：每個動作一行（「臥推」「10 下 × 3 組・60 kg」）
    private static func makeMoves(_ s: WorkoutSession, bodyWeightKg: Double?) -> [Move] {
        guard !s.strengthExercises.isEmpty || s.exercises.count > 1 else { return [] }
        return s.exercises.map { e in
            let name = e.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return Move(id: e.id, name: name.isEmpty ? e.resolvedSport.displayName : name,
                        detail: e.summary(bodyWeightKg: bodyWeightKg))
        }
    }

    // MARK: ⑧ Apple 健康

    private static func makeHealth(_ s: WorkoutSession, hkEnabled: Bool, hkAvailable: Bool) -> HealthLine? {
        guard hkAvailable else { return nil }
        let src = WorkoutFacts.source(of: s)
        if src == .watch { return HealthLine(text: "來自 Apple Watch", good: false) }
        if s.healthKitUUID != nil {
            // 舊資料看不出是 App 寫進去的還是從 Apple 健康帶進來的
            return src == nil
                ? HealthLine(text: "Apple 健康裡也有這一筆", good: false)
                : HealthLine(text: "已存進 Apple 健康", good: true)
        }
        if !hkEnabled { return HealthLine(text: "沒有存進 Apple 健康（健康頁的 Apple 健康沒打開）", good: false) }
        return HealthLine(text: "沒有存進 Apple 健康（可能沒給寫入權限）", good: false)
    }

    // MARK: ⑨ 資料

    private static func makeInfo(_ s: WorkoutSession, bodyWeightKg: Double?) -> [InfoItem] {
        var out: [InfoItem] = []
        out.append(InfoItem(id: "start", label: "開始",
                            value: WorkoutFormat.date(s.date) + " " + WorkoutFormat.time(s.date)))
        if let end = endDate(s) {
            let sameDay = WorkoutFacts.calendar.isDate(end, inSameDayAs: s.date)
            out.append(InfoItem(id: "end", label: "結束",
                                value: sameDay ? WorkoutFormat.time(end)
                                    : WorkoutFormat.date(end) + " " + WorkoutFormat.time(end)))
        }
        let moving = WorkoutFacts.movingMinutes(s)
        if moving > 0 {
            out.append(InfoItem(id: "moving", label: "移動時間", value: WorkoutFormat.clock(minutes: moving)))
        }
        if let ps = s.pauses, !ps.isEmpty {
            let total = ps.reduce(0) { $0 + $1.seconds }
            out.append(InfoItem(id: "pauses", label: "暫停",
                                value: "\(ps.count) 次・" + WorkoutFormat.clock(seconds: total)))
        }
        let place = s.place.trimmingCharacters(in: .whitespacesAndNewlines)
        if !place.isEmpty {
            out.append(InfoItem(id: "place", label: "地點", value: place))
        }
        if let src = WorkoutFacts.source(of: s) {
            // 舊版只存到起點的那幾趟（judge §2.5 v3）：距離照記，但當時 GPS 飄的也算進去了
            // （模擬：跑步約多 2%、健走約多 15%），值下面一行灰字講清楚
            let legacyNote: String? = s.isLegacyRouteMissing ? "舊版記錄，距離可能多算一點" : nil
            out.append(InfoItem(id: "source", label: "記錄方式", value: src.label, note: legacyNote))
        }
        if let k = WorkoutFacts.kcal(s, bodyWeightKg: bodyWeightKg) {
            var note: String? = nil
            if k.estimated {
                if let w = bodyWeightKg, w > 0 {
                    note = "估的，依體重 " + String(format: "%.1f", w) + " kg"
                } else {
                    note = "估的"
                }
            } else if WorkoutFacts.source(of: s) == .watch {
                note = "Apple Watch 量的"
            }
            out.append(InfoItem(id: "kcal", label: "大卡", value: kcalNumber(k.kcal, estimated: k.estimated),
                                note: note))
        }
        let memo = s.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !memo.isEmpty {
            out.append(InfoItem(id: "note", label: "備註", value: memo))
        }
        return out
    }

    // MARK: ⓪ 換一趟

    /// 同一週（週一開始）的每一趟，舊到新：「10/12 晨跑」＋「4.3」（重訓、沒距離不寫）
    private static func makeSwitcher(_ s: WorkoutSession, sessions: [WorkoutSession]) -> [FinanceSwitcherItem] {
        let w = WorkoutFacts.week(of: s.date)
        let list = sessions
            .filter { $0.date >= w.start && $0.date < w.end }
            .sorted { $0.date < $1.date }
        guard list.count > 1 else { return [] }
        return list.map { x in
            let km = x.totalDistanceKm
            let trailing = (x.primarySport != .strength && km >= 0.05) ? WorkoutFormat.kmNumber(km) : ""
            let title = WorkoutFormat.monthDay(x.date) + " " + MoneyBoardText.short(WorkoutFacts.title(x), max: 4)
            return FinanceSwitcherItem(id: x.id, title: title, trailing: trailing, tone: .neutral)
        }
    }
}
