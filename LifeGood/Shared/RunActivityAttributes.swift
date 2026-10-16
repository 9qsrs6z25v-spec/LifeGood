import Foundation
import ActivityKit

// MARK: - 跑步即時動態 · 資料（健康 v6，v25.556）
//
// 這個檔案同時屬於「主 App」與「LifeGoodWidgets」兩個 target（照 PhotoImportAttributes.swift）：
// 主 App（RunActivityCenter）負責開始、更新、結束；小工具（LifeGoodWidgets/RunLiveActivity.swift）負責在
// 鎖定畫面、靈動島、手錶的智慧型堆疊畫出來。規格：scratchpad/health/judge.md §4.4、health/build/v6/brief.md。
//
// • 不放路線形狀、不放地點：鎖著時旁人看得到，從家門口出發的路線形狀就是住家附近（judge 待決定 9）。
//   名字只用時段名「晨跑」，不用沿用來的「河濱晨跑」（自己取的名字常常就是地名）。
// • 時間不每秒推：小工具用 Text(timerInterval:pauseTime:countsDown:showsHours:) 從 clockStart 往上數，系統自己走；
//   暫停時 pausedAt 有值，時間停在那一刻。距離、第三格由 App 節流推（RunActivityCenter：10 秒、或走了 50 公尺、
//   過整公里、暫停、繼續；站著不動也每 60 秒推一次，staleDate 才不會誤報）。
// • 數字都是 App 組好的字（WorkoutFormat，跟跑步畫面同一套寫法）；小工具不算任何東西。
// • ContentState 上限 4KB（ActivityKit 硬限制）：這裡最長約 200 bytes。
//
// ⚠️ 只准用 Foundation／ActivityKit。不准引用 App 才有的型別（RunSport、WorkoutSport、WorkoutFormat、WorkoutPalette
//    都只在 App target）。這個檔是主控契約，各組都不改；要加東西先問主控。

/// 這一趟在哪個狀態
enum RunActivityPhase: String, Codable, Hashable {
    /// 記錄中（時間在走）
    case running
    /// 暫停中（時間停在 pausedAt）
    case paused
    /// 按完成了（鎖定畫面留 15 分鐘「完成　5.20 公里・32:10・6'11"」，靈動島馬上收）
    case finished
}

/// 運動種類。App 的 RunSport 只在 App target（rawValue 是中文），這裡另做一份小的；
/// rawValue 用英文，之後改畫面上的字也不會讀不回來
enum RunActivitySport: String, Codable, Hashable {
    case run
    case walk
    case bike
    case hike

    /// 「跑步」「健走」「騎車」「登山」（跟 WorkoutSport.displayName 一樣）
    var name: String {
        switch self {
        case .run: return "跑步"
        case .walk: return "健走"
        case .bike: return "騎車"
        case .hike: return "登山"
        }
    }

    /// SF Symbols（跟 WorkoutSport.icon 一樣）
    var icon: String {
        switch self {
        case .run: return "figure.run"
        case .walk: return "figure.walk"
        case .bike: return "figure.outdoor.cycle"
        case .hike: return "figure.hiking"
        }
    }

    /// 運動色・淺色（跟 WorkoutPalette.sport(_:dark: false) 一樣；跑步橘 EB6834）
    var tintHex: UInt32 {
        switch self {
        case .run: return 0xEB6834
        case .walk: return 0x1BAF7A
        case .bike: return 0x2A78D6
        case .hike: return 0xEDA100
        }
    }

    /// 運動色・深色（跟 WorkoutPalette.sport(_:dark: true) 一樣）
    var tintHexDark: UInt32 {
        switch self {
        case .run: return 0xD95926
        case .walk: return 0x199E70
        case .bike: return 0x3987E5
        case .hike: return 0xC98500
        }
    }
}

struct RunActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// 記錄中／暫停中／完成
        var phase: RunActivityPhase
        /// 大字距離「3.42」（App 用 WorkoutFormat.preciseKmNumber 組好；騎車 10 公里以上「12.6」）。單位「公里」小工具自己寫
        var distanceText: String
        /// 計時起點＝按開始那一刻＋到現在暫停過的總秒數（RunTracker.movingClockStart）。
        /// 小工具從這裡往上數，數出來就是移動時間（暫停不算），不用每秒推
        var clockStart: Date
        /// 暫停中、完成：時間停在這一刻（暫停＝按暫停那一刻；完成＝結束那一刻）。記錄中是 nil
        var pausedAt: Date?
        /// 第三格的數字：跑走登山「6'20"」（最近 30 秒；算不出來「—」）；騎車時速「21.4」。暫停中改成平均
        var thirdText: String
        /// 第三格下面的小字：記錄中 跑走登山「這一公里」、騎車「時速」；暫停中「平均配速」「平均時速」
        var thirdLabel: String
        /// 完成那一行：「5.20 公里・32:10・6'11"」（騎車「23.4 公里・1:05:12・時速 21.5」）；沒完成是 nil
        var finishedLine: String?

        init(phase: RunActivityPhase, distanceText: String, clockStart: Date, pausedAt: Date? = nil,
             thirdText: String, thirdLabel: String, finishedLine: String? = nil) {
            self.phase = phase
            self.distanceText = distanceText
            self.clockStart = clockStart
            self.pausedAt = pausedAt
            self.thirdText = thirdText
            self.thirdLabel = thirdLabel
            self.finishedLine = finishedLine
        }
    }

    /// 這一趟的編號（RunTracker.runId 的 uuidString）。暫停鈕帶著它：按到殘留的舊一趟不會動到正在記的這一趟
    var runId: String
    /// 哪一種運動（圖示、運動色、「跑步中」的「跑步」）
    var sport: RunActivitySport
    /// 時段名「晨跑」「晚走」「夜騎」「登山」（WorkoutFacts.timeOfDayName，按開始那一刻取，之後不變；不放地點）
    var title: String
    /// 按開始那一刻
    var startedAt: Date

    init(runId: String, sport: RunActivitySport, title: String, startedAt: Date) {
        self.runId = runId
        self.sport = sport
        self.title = title
        self.startedAt = startedAt
    }
}

// MARK: - 字與時間（App、小工具共用；全部純函式，build/v6/sim_v6.py §8 逐字驗過）

extension RunActivityAttributes {
    /// 暫停多久提醒一次要不要結束（鎖定畫面那一行字靠 staleDate；App 另外排一則本機通知）
    static let pauseRemindSeconds: TimeInterval = 30 * 60
    /// 記錄中多久沒更新就寫「好一陣子沒更新了」（App 至少每 60 秒推一次；App 被系統收掉時才會到）
    static let runningStaleSeconds: TimeInterval = 5 * 60
    /// 計時字最多數到幾小時（即時動態最長 8 小時，給寬一點）
    static let timerSpanSeconds: TimeInterval = 24 * 3600

    /// 標題：「晨跑・跑步中」「晚走・健走中」「晨騎・騎車中」「登山中」；暫停「晨跑・已暫停」「登山・已暫停」；完成「完成」
    /// （跟健康頁記錄中條 HealthLiveStrip.titleText 一樣）
    func headline(_ s: ContentState) -> String {
        switch s.phase {
        case .finished:
            return "完成"
        case .paused:
            return title + "・已暫停"
        case .running:
            if sport == .hike { return "登山中" }
            return title + "・" + sport.name + "中"
        }
    }

    /// 計時字的區間（往上數）：clockStart 起 24 小時
    static func timerRange(_ s: ContentState) -> ClosedRange<Date> {
        s.clockStart...s.clockStart.addingTimeInterval(timerSpanSeconds)
    }

    /// 內容多久之後算過期（ActivityContent 的 staleDate）：記錄中 5 分鐘後（App 每次推都往後延）；
    /// 暫停中＝按暫停 30 分鐘後（鎖定畫面改寫提醒）；完成不過期
    static func staleDate(_ s: ContentState, now: Date) -> Date? {
        switch s.phase {
        case .running:
            return now.addingTimeInterval(runningStaleSeconds)
        case .paused:
            return (s.pausedAt ?? now).addingTimeInterval(pauseRemindSeconds)
        case .finished:
            return nil
        }
    }

    /// 過期時（context.isStale）多寫的一行
    static func staleNote(_ s: ContentState) -> String? {
        switch s.phase {
        case .paused:
            return "已暫停 30 分鐘・不跑了就打開 LifeGood 按結束"
        case .running:
            return "好一陣子沒更新了・打開 LifeGood 看看"
        case .finished:
            return nil
        }
    }

    /// 暫停鈕的圖示：記錄中 pause.fill、暫停中 play.fill
    static func buttonIcon(_ s: ContentState) -> String {
        s.phase == .paused ? "play.fill" : "pause.fill"
    }

    /// 暫停鈕給 VoiceOver 的字：「暫停」「繼續」
    static func buttonLabel(_ s: ContentState) -> String {
        s.phase == .paused ? "繼續" : "暫停"
    }

    /// 按了暫停鈕要做什麼：true＝暫停（記錄中按）、false＝繼續（暫停中按）。RunPauseIntent(pause:runId:) 的 pause
    static func buttonPauses(_ s: ContentState) -> Bool {
        s.phase != .paused
    }
}
