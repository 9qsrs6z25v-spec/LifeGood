import Foundation
import AppIntents
import ActivityKit

// MARK: - 鎖定畫面／靈動島的暫停、繼續鈕（健康 v6，v25.556）
//
// 這個檔案同時屬於「主 App」與「LifeGoodWidgets」兩個 target（照 DayTimelineToggleIntent.swift 的寫法；主控契約，各組都不改）。
// 規格：scratchpad/health/judge.md §4.4、health/build/v6/brief.md。
//
// • RunPauseIntent：即時動態上那一顆鈕（Button(intent:)）。LiveActivityIntent：系統在 **App 的行程裡**跑 perform
//   （App 被暫停了會先叫醒、被關掉了會在背景開起來），不開 App 畫面——鎖著手機、不用解鎖就能暫停／繼續。
//   pause：true＝暫停、false＝繼續（不用「切換」：連按兩下、或按到舊畫面，不會一按暫停一按又繼續）。
//   runId：這顆鈕是哪一趟的（RunActivityAttributes.runId）。不是正在記的那一趟（App 被關掉後留下來的殘留）就只收掉殘留。
// • perform 碰不到 App 的型別（RunTracker、RunActivityCenter），所以只呼叫 App 啟動時登記的處理者
//   （RunPauseBridge.register，在 LifeGoodApp.init；處理者＝RunActivityCenter.shared.handlePauseButton(pause:runId:)）。
// • 萬一系統在小工具的行程裡跑了 perform（沒有登記的處理者）：什麼都不做。不能像今日行程那樣先存起來等 App 套用——
//   幾分鐘後才套用一個「暫停」，會把使用者已經在跑的時間吃掉。
//
// ⚠️ 只准用 Foundation／AppIntents／ActivityKit 與共用檔的型別。不准引用 App 才有的型別。instance 參數不取名 title／description。

// MARK: - intent → App 的交接

/// RunPauseIntent → App。App 在 LifeGoodApp.init() 登記處理者
@MainActor
enum RunPauseBridge {
    private static var handler: (@MainActor (Bool, String) async -> Void)?

    /// App 啟動時登記（只有 App 會呼叫）。處理者的兩個參數：pause（true＝暫停）、runId（按的是哪一趟）
    static func register(_ newHandler: @escaping @MainActor (Bool, String) async -> Void) {
        handler = newHandler
    }

    /// intent 的 perform 呼叫：有處理者（在 App 的行程裡）就等它做完（暫停好、即時動態推上去了才回）；沒有就什麼都不做
    static func apply(pause: Bool, runId: String) async {
        guard let h = handler else { return }
        await h(pause, runId)
    }
}

// MARK: - 暫停／繼續鈕

struct RunPauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "暫停或繼續運動"
    static var description = IntentDescription("在鎖定畫面、靈動島暫停或繼續正在記錄的運動")
    /// 不開 App 畫面：LiveActivityIntent 在 App 的行程裡背景執行
    static var openAppWhenRun: Bool = false
    /// 不放進捷徑、Siri、聚焦搜尋（只給即時動態上那一顆鈕用；iOS 17 起）
    static var isDiscoverable: Bool = false

    /// true＝暫停、false＝繼續
    @Parameter(title: "暫停")
    var pause: Bool

    /// 這顆鈕是哪一趟的（RunActivityAttributes.runId）
    @Parameter(title: "哪一趟")
    var runId: String

    init() {}

    init(pause: Bool, runId: String) {
        self.pause = pause
        self.runId = runId
    }

    func perform() async throws -> some IntentResult {
        await RunPauseBridge.apply(pause: pause, runId: runId)
        return .result()
    }
}
