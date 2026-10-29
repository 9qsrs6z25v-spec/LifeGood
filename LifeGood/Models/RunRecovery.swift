import Foundation
import Combine

// MARK: - 跑到一半被關掉，救得回來（v25.552，健康 v2）
//
// 以前記錄中的一切只在記憶體裡：跑到一半開相機、玩遊戲，系統把 LifeGood 收掉，或從多工畫面滑掉，整趟就不見了。
// 現在 RunTracker 跑步中每 30 秒或每 20 個新點（還有按暫停、繼續、App 退到背景時）把這一趟寫成一個小檔
// （RunCheckpoint → RunCheckpointStore：Application Support/RunCheckpoints/<編號>.json，不進 iCloud、不進手機備份），
// 按完成或放棄就刪掉。
// 下次打開 App（LifeGoodApp 的 .task → RunRecoveryCenter.scan()）找到還在的檔＝上次沒存完的那幾趟：
// 一打開問一次（LaunchGate 的提示框），健康頁最上面也有一張卡，〔存下來〕〔丟掉〕。
// 存下來跟按完成走同一條路（WorkoutFacts.makeSession）：每公里分段、簡化路線、運動種類、估的大卡都一樣。
//
// 取捨（health/build/v2/brief.md §1）：judge 寫「12 小時內有就問」，改成 7 天內都問（不是今天的，問句寫日期）、
// 超過 7 天才默默刪掉：跑完隔天晚上才打開 App 也救得回來。太短的（10 公尺內而且 30 秒內，跟按完成時「太短要不要存」同一條線）不問、直接刪。
//
// [v25.555] 健康 v5（build/v5/brief.md §G1-5）：
// • 存檔多帶 GPS 情形（RunCheckpoint.gps，選填：v25.554 以前寫的檔沒有這個鍵照樣讀得進來）→ 救回那一趟的成果頁也會提醒「GPS 訊號很弱」。
// • 〔存下來〕跟按住結束同一套取名：起點 150 公尺內、同一種運動、你改過名字的那幾趟沿用那個名字，不然照時段（晨跑、夜跑…）
//   （WorkoutFacts.makeSession(…sessions: store.workouts)）；存好之後用起點反查一次地點（WorkoutPlaceLookup.fill，查不到就不寫）。

/// 跑到一半的存檔（一個檔＝一趟）。欄位都是必填：同一版 App 自己寫自己讀；讀不出來的檔直接刪掉。
/// [v25.555] 只有最後的 gps 是選填（var＋預設 nil：舊檔沒有這個鍵照樣讀得進來，逐一列欄位的 init 也照舊）
struct RunCheckpoint: Codable, Identifiable {
    /// RunTracker.runId（也是檔名）
    let id: UUID
    /// RunSport.rawValue（「跑步」…）
    let sport: String
    /// 按開始那一刻
    let startedAt: Date
    /// 寫這個檔的時間
    let savedAt: Date
    /// 到寫檔為止的移動時間（秒，暫停不算）
    let movingSeconds: Double
    /// 寫檔時正在暫停：按暫停那一刻（＝救回來時的結束時間）；沒在暫停是 nil
    let pausedAt: Date?
    let distanceMeters: Double
    let elevationGainM: Double
    /// 完整的點（還沒簡化；救回來時才算分段、再簡化）
    let points: [RoutePoint]
    /// 已經結束的暫停（按暫停到按繼續）
    let pauses: [WorkoutPause]
    /// 每走滿一整公里那一刻的累計爬升（RunResult.kmClimb）
    let kmClimb: [Double]
    /// [v25.555] 到寫檔為止 GPS 好不好（RunTracker 每秒數的；RunResult.gps）。v25.554 以前寫的檔沒有，是 nil
    var gps: WorkoutGPSQuality? = nil

    var runSport: RunSport { RunSport(rawValue: sport) ?? .run }

    /// 太短（10 公尺內而且 30 秒內）：跟按完成時「這一趟只有 12 秒，要存嗎？」同一條線；救回時不問、直接刪
    var isTooShort: Bool { distanceMeters <= 10 && movingSeconds <= 30 }

    /// 救回來當成這一趟的成果：結束時間＝寫檔時在暫停就是按暫停那一刻，不然是最後一次寫檔。[v25.555] GPS 情形一起帶
    var result: RunResult {
        let end = max(pausedAt ?? savedAt, startedAt)
        var r = RunResult(sport: runSport,
                          distanceKm: distanceMeters / 1000,
                          movingMinutes: movingSeconds / 60,
                          route: points,
                          elevation: elevationGainM,
                          startedAt: startedAt,
                          endedAt: end,
                          pauses: pauses,
                          kmClimb: kmClimb)
        r.gps = gps
        return r
    }

    /// 問句：「上次的跑步 3.4 公里・21:05 還沒存，要存下來還是丟掉？」；不是今天的寫日期：
    /// 「10/14 週三那趟跑步 3.4 公里・21:05 還沒存，要存下來還是丟掉？」
    func prompt(now: Date = Date()) -> String {
        let what = runSport.rawValue + " " + WorkoutFormat.km(distanceMeters / 1000)
            + "・" + WorkoutFormat.clock(seconds: movingSeconds)
        let head: String
        if WorkoutFacts.calendar.isDate(startedAt, inSameDayAs: now) {
            head = "上次的" + what
        } else {
            head = WorkoutFormat.day(startedAt) + "那趟" + what
        }
        return head + " 還沒存，要存下來還是丟掉？"
    }
}

// MARK: - 檔案

/// 中途存檔的檔案：Application Support/RunCheckpoints/<編號>.json（不進 iCloud、不進手機備份）。
/// 寫、刪都排在同一條背景佇列，照呼叫的順序做：按完成時的刪除一定在最後一次寫之後。
enum RunCheckpointStore {
    private static let queue = DispatchQueue(label: "com.lifegood.run.checkpoint", qos: .utility)

    /// 資料夾（第一次用到時建好、設成不進手機備份）；拿不到回 nil（什麼都不寫，不會閃退）
    static func directory() -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        var dir = base.appendingPathComponent("RunCheckpoints", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                return nil
            }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? dir.setResourceValues(values)
        }
        return dir
    }

    static func fileURL(_ id: UUID) -> URL? {
        directory()?.appendingPathComponent(id.uuidString + ".json")
    }

    /// 寫一個存檔（背景；同一趟覆蓋同一個檔）
    static func save(_ checkpoint: RunCheckpoint) {
        queue.async {
            guard let url = RunCheckpointStore.fileURL(checkpoint.id),
                  let data = try? JSONEncoder().encode(checkpoint) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// 刪一個存檔（背景；排在之前的寫之後）
    static func delete(_ id: UUID) {
        queue.async {
            guard let url = RunCheckpointStore.fileURL(id) else { return }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// 讀出所有存檔（新的在前）。讀不出來的、超過 maxAge 的、太短的順手刪掉
    static func loadAll(maxAge: TimeInterval = 7 * 86_400) async -> [RunCheckpoint] {
        await withCheckedContinuation { cont in
            queue.async {
                cont.resume(returning: RunCheckpointStore.readAll(maxAge: maxAge))
            }
        }
    }

    private static func readAll(maxAge: TimeInterval) -> [RunCheckpoint] {
        let fm = FileManager.default
        guard let dir = directory(),
              let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        let now = Date()
        let decoder = JSONDecoder()
        var out: [RunCheckpoint] = []
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let cp = try? decoder.decode(RunCheckpoint.self, from: data) else {
                try? fm.removeItem(at: url)
                continue
            }
            if now.timeIntervalSince(cp.savedAt) > maxAge || cp.isTooShort {
                try? fm.removeItem(at: url)
                continue
            }
            out.append(cp)
        }
        return out.sorted { $0.savedAt > $1.savedAt }
    }
}

// MARK: - 救回

/// 上次沒存完的那幾趟。App 一打開 scan() 一次；LaunchGate 的提示框、健康頁最上面的卡都讀 pending
@MainActor
final class RunRecoveryCenter: ObservableObject {
    static let shared = RunRecoveryCenter()

    /// 還沒存、也還沒丟的那幾趟（新的在前）
    @Published private(set) var pending: [RunCheckpoint] = []
    /// scan() 跑完了（LaunchGate 等這個才決定要不要問）
    @Published private(set) var scanned = false

    private var scanning = false

    private init() {}

    /// App 一打開呼叫一次（LifeGoodApp 的 .task）：讀出上次沒存完的那幾趟。重複呼叫什麼都不做。
    /// 正在記錄的這一趟（理論上剛打開不會有）跳過
    func scan() async {
        guard !scanning, !scanned else { return }
        scanning = true
        let all = await RunCheckpointStore.loadAll()
        let active = RunTracker.shared.activeRunId
        pending = all.filter { $0.id != active }
        scanning = false
        scanned = true
    }

    /// 〔存下來〕：跟按完成同一條路（WorkoutFacts.makeSession）存進訓練紀錄；Apple 健康聯動打開的話也寫進去。
    /// 提示框、卡片按下去的那一次畫面更新先過，下一輪主執行緒才寫 store（Task @MainActor，同 RunTracker 回呼的寫法）
    /// [v25.555] 取名跟按住結束一樣看以前的紀錄（同一個起點沿用改過的名字、不然照時段）；寫好 store 之後反查地點
    ///（WorkoutPlaceLookup.fill：await 之後拿 store 最新那一筆、只寫空的；查不到不寫）
    func save(_ checkpoint: RunCheckpoint, store: LifeStore) {
        let id = checkpoint.id
        Task { @MainActor in
            guard self.pending.contains(where: { $0.id == id }) else { return }   // 連按兩下：只存一次
            self.pending.removeAll { $0.id == id }
            let session = WorkoutFacts.makeSession(from: checkpoint.result, bodyWeightKg: store.latestBodyWeightKg,
                                                   sessions: store.workouts)
            store.upsertWorkout(session)
            WorkoutPlaceLookup.shared.fill(session, store: store)
            RunCheckpointStore.delete(id)
            Task { await WorkoutHealthWriter.push(session, store: store) }
        }
    }

    /// 〔丟掉〕
    func discard(_ checkpoint: RunCheckpoint) {
        let id = checkpoint.id
        Task { @MainActor in
            self.pending.removeAll { $0.id == id }
            RunCheckpointStore.delete(id)
        }
    }
}

// MARK: - 寫進 Apple 健康（共用）

/// [v25.552] 把一趟寫進 Apple 健康：健康頁的聯動開關打開、裝置支援、而且還沒寫過的才寫；寫好把編號存回那一筆。
/// 以前只在 HealthView.pushToHealthKit；救回中途存檔也要用，搬到這裡（HealthView 改呼叫這支）。
/// 編號存回「最新的那一筆」（等待中被編輯過也不會蓋回舊的；找不到＝已經刪了，就不寫回）
/// [v25.554] 內容搬進 HealthSyncCenter.push（HealthSync.swift）：同一套流程多了簡化前的點（WorkoutRouteStash）、
/// 寫進去的時間與數字（WorkoutFacts.healthStamp，成果頁「已存進 Apple 健康・06:40」、改過才知道要〔更新〕）、
/// 寫入中（成果頁「存進 Apple 健康中…」）、失敗的一句話。這裡只轉呼叫，既有呼叫端（存檔、複製、救回）不用改
@MainActor
enum WorkoutHealthWriter {
    /// 健康頁 Apple 健康開關（HealthView 的 @AppStorage("health_hk_enabled") 同一個鍵）
    static let enabledKey = "health_hk_enabled"

    static func push(_ session: WorkoutSession, store: LifeStore) async {
        await HealthSyncCenter.shared.push(session, store: store)
    }
}
