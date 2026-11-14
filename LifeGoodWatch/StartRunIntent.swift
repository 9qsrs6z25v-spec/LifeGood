import Foundation
import AppIntents

// MARK: - Ultra 動作按鈕：一按開始跑步、動作＋側邊一起按暫停／繼續（手錶 v5，v25.582；watch/judge.md §3.6、§13-1；
//         watch/build/v5/brief.md §2）
//
// 只屬於 LifeGoodWatch（手錶 App）。Apple〈Responding to the Action button on Apple Watch Ultra〉：動作按鈕的 intent 一定寫在
// 手錶 App 裡、**不能放在 App Intents extension**；手錶小格 target 不編這個檔（pbxwatch_check R 段擋：AppIntents 只准這個檔）。
//
// • StartRunIntent（StartWorkoutIntent，watchOS 9 起）：在 Ultra「設定 › 動作按鈕」選「體能訓練」→ App 選 LifeGood 之後，
//   動作按鈕一按＝WorkoutManager.startFromActionButton：準備頁 → 權限都好就直接 3、2、1（GPS 還沒找到也開始）；
//   健康沒給、還沒問過就停在準備頁講清楚。suggestedWorkouts＝跑步、健走、騎車、登山（設定裡「第一下」底下那幾個）。
//   Apple 規定 30 秒內要開始運動 session：perform 等到真的開始（最多 8 秒）才回。
// • PauseRunIntent／ResumeRunIntent（PauseWorkoutIntent／ResumeWorkoutIntent，watchOS 9 起）：跑步中動作＋側邊一起按＝暫停；
//   暫停中＝繼續（自動暫停中按＝你按的暫停）。
// • 不是 Ultra（S8、SE2）：動作按鈕不存在，這三個 intent 不會被叫，其他功能照常（§13-1「不是 Ultra 也無害」）。
// 寫法照這個專案 iPhone 那邊編過的 AppIntents（RunPauseIntent、WidgetConfigTypes 的 AppEnum）：static var＋字面值。

/// 動作按鈕「第一下」底下可以選的四種運動（rawValue＝WatchSport.rawValue）
enum LifeGoodRunStyle: String, AppEnum {
    case run
    case walk
    case bike
    case hike

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "運動"
    static var caseDisplayRepresentations: [LifeGoodRunStyle: DisplayRepresentation] = [
        .run: DisplayRepresentation(title: "跑步", subtitle: "戶外"),
        .walk: DisplayRepresentation(title: "健走", subtitle: "戶外"),
        .bike: DisplayRepresentation(title: "騎車", subtitle: "戶外"),
        .hike: DisplayRepresentation(title: "登山", subtitle: "戶外")
    ]

    /// 手錶的運動
    var sport: WatchSport {
        WatchSport(rawValue: rawValue) ?? .run
    }
}

/// intent → WorkoutManager（主執行緒）
@MainActor
enum RunIntentBridge {
    static func start(_ sport: WatchSport) async {
        await WorkoutManager.shared.startFromActionButton(sport: sport)
    }

    static func pause() {
        WorkoutManager.shared.pauseFromActionButton()
    }

    static func resume() {
        WorkoutManager.shared.resumeFromActionButton()
    }
}

/// Ultra 動作按鈕一按：開始運動
struct StartRunIntent: StartWorkoutIntent {
    static var title: LocalizedStringResource = "LifeGood 開始運動"
    static var openAppWhenRun: Bool = true
    static var suggestedWorkouts: [StartRunIntent] = [
        StartRunIntent(choice: .run),
        StartRunIntent(choice: .walk),
        StartRunIntent(choice: .bike),
        StartRunIntent(choice: .hike)
    ]

    @Parameter(title: "運動")
    var workoutStyle: LifeGoodRunStyle

    init() {
        workoutStyle = .run
    }

    init(choice: LifeGoodRunStyle) {
        workoutStyle = choice
    }

    var displayRepresentation: DisplayRepresentation {
        LifeGoodRunStyle.caseDisplayRepresentations[workoutStyle] ?? DisplayRepresentation(title: "跑步")
    }

    func perform() async throws -> some IntentResult {
        let sport = workoutStyle.sport
        await RunIntentBridge.start(sport)
        return .result()
    }
}

/// 跑步中動作＋側邊一起按：暫停
struct PauseRunIntent: PauseWorkoutIntent {
    static var title: LocalizedStringResource = "LifeGood 暫停運動"

    func perform() async throws -> some IntentResult {
        await RunIntentBridge.pause()
        return .result()
    }
}

/// 暫停中動作＋側邊一起按：繼續
struct ResumeRunIntent: ResumeWorkoutIntent {
    static var title: LocalizedStringResource = "LifeGood 繼續運動"

    func perform() async throws -> some IntentResult {
        await RunIntentBridge.resume()
        return .result()
    }
}
