import Foundation
import AppIntents
import ActivityKit
import WidgetKit

// MARK: - 靈動島今日行程的開關（小工具 v5）
//
// 這個檔案同時屬於「主 App」與「LifeGoodWidgets」兩個 target（主控契約，三組都不准改）。
// 規格：scratchpad/widgets/v5/brief.md §3.5；design_life.md L7（:492-510）、L1 中型「上靈動島」（:208-212）、§3.7。
//
// • DayTimelineToggleIntent：控制中心「今日行程」開關（ControlWidgetToggle 的 action）。
//   SetValueIntent（系統把開關的新值放進 value）＋LiveActivityIntent（跟現有 SelectTimelineStopIntent 同一類：
//   兩個 target 都有這個型別，系統在 **App 的行程裡**跑 perform——不開 App 畫面，但能 Activity.request）。
//   WWDC24「Extend your app's controls across the system」計時器開關就是這個寫法（SetValueIntent, LiveActivityIntent）。
// • StartDayTimelineIntent：中型「今天」的「上靈動島」小按鈕（Button(intent:)）。只會開、不會關，
//   所以另做一個沒有參數的 LiveActivityIntent，不靠 Button 帶 SetValueIntent 的 value（這一點沒把握）。
//   兩個都叫同一個 DayTimelineToggleBridge.apply(_:)。
//
// perform 碰不到 App 的型別（DayTimelineController、LifeStore），所以只呼叫 App 啟動時登記的處理者
// （DayTimelineToggleBridge.register，在 LifeGoodApp.init）。處理者：開＝isEnabled = true 並 refresh；
// 關＝isEnabled = false 並 stop（DayTimelineController.setEnabled(_:store:)）。
// 保險：萬一系統在小工具的行程裡跑了 perform（沒有登記的處理者），想要的值先存進 App Group，
// App 啟動、每次回前景時 DayTimelineToggleState.takePending() 撿起來套用（只認今天按的）。
//
// 控制項的狀態（開／關）不是 isEnabled，而是「靈動島現在有沒有在跑」：App 在靈動島開始、續期、收掉時
// 把「跑到幾點」寫進 App Group（DayTimelineToggleState.setRunningUntil），過了那個時間就算沒在跑
// （一個即時動態最長活 8 小時，App 被暫停時系統會自己收掉，App 來不及寫）。
//
// ⚠️ 只准用 Foundation／AppIntents／ActivityKit／WidgetKit 與共用檔的型別（WidgetShared、WidgetKind、WidgetRefresh）。
//    不准引用 App 才有的型別。instance 參數不取名 title／description。

// MARK: - App Group 裡的狀態

/// 靈動島「跑到幾點」與「待套用」的值（App Group 的 UserDefaults，不同步、iPhone 各自一份）
enum DayTimelineToggleState {
    /// 「跑到幾點」（epoch 秒；沒有這個鍵＝沒在跑）
    static let runningUntilKey = "day_timeline_running_until"
    /// 控制項在小工具的行程裡被按了、還沒交給 App 的值與按的時間
    static let pendingValueKey = "day_timeline_pending_value"
    static let pendingAtKey = "day_timeline_pending_at"
    /// 一個即時動態最長活多久（系統上限；DayTimelineController 在 7 小時 50 分時自己續期）
    static let maxRun: TimeInterval = 8 * 3600

    /// 靈動島跑到幾點；沒在跑、App Group 沒生效是 nil
    static var runningUntil: Date? {
        guard let d = WidgetShared.defaults, d.object(forKey: runningUntilKey) != nil else { return nil }
        return Date(timeIntervalSince1970: d.double(forKey: runningUntilKey))
    }

    /// 這個時間點靈動島有沒有在跑（跑到幾點 > now）
    static func isRunning(at now: Date) -> Bool {
        guard let until = runningUntil else { return false }
        return until > now
    }

    /// App 用：寫「跑到幾點」（nil＝沒在跑）。值真的變了（差 1 秒以上、或有／沒有換了）才回 true，
    /// 回 true 時 App 才叫控制項與「今天」重畫（App 在背景叫重畫會吃小工具每天的額度）
    @discardableResult
    static func setRunningUntil(_ date: Date?) -> Bool {
        guard let d = WidgetShared.defaults else { return false }
        let old = runningUntil
        let same: Bool
        switch (old, date) {
        case (nil, nil):
            same = true
        case let (a?, b?):
            same = abs(a.timeIntervalSince(b)) < 1
        default:
            same = false
        }
        if same { return false }
        if let date {
            d.set(date.timeIntervalSince1970, forKey: runningUntilKey)
        } else {
            d.removeObject(forKey: runningUntilKey)
        }
        return true
    }

    /// intent 沒交到 App 時：先存想要的值
    static func setPending(_ on: Bool, at now: Date = Date()) {
        guard let d = WidgetShared.defaults else { return }
        d.set(on, forKey: pendingValueKey)
        d.set(now.timeIntervalSince1970, forKey: pendingAtKey)
    }

    /// App 啟動、回前景時：取走並清掉；只認今天按的（昨天按了沒交到的不要突然開起來）
    static func takePending(now: Date = Date()) -> Bool? {
        guard let d = WidgetShared.defaults, d.object(forKey: pendingValueKey) != nil else { return nil }
        let value = d.bool(forKey: pendingValueKey)
        let at = Date(timeIntervalSince1970: d.double(forKey: pendingAtKey))
        d.removeObject(forKey: pendingValueKey)
        d.removeObject(forKey: pendingAtKey)
        guard Calendar.current.isDate(at, inSameDayAs: now) else { return nil }
        return value
    }
}

// MARK: - intent → App 的交接

/// DayTimelineToggleIntent／StartDayTimelineIntent → App。App 在 LifeGoodApp.init() 登記處理者
///（處理者：DayTimelineController.shared.setEnabled(on, store: AppStores.life)）
@MainActor
enum DayTimelineToggleBridge {
    private static var handler: (@MainActor (Bool) async -> Void)?

    /// App 啟動時登記（只有 App 會呼叫）
    static func register(_ newHandler: @escaping @MainActor (Bool) async -> Void) {
        handler = newHandler
    }

    /// intent 的 perform 呼叫：有處理者（在 App 的行程裡）就等它做完（靈動島開好或收掉才回）；
    /// 沒有（在小工具的行程裡跑）就把想要的值存進 App Group，並叫控制項、「今天」重畫（不要卡在系統先畫的「開」）
    static func apply(_ on: Bool) async {
        if let h = handler {
            await h(on)
            return
        }
        DayTimelineToggleState.setPending(on)
        WidgetRefresh.reloadControls(WidgetKind.dayTimelineControlKinds)
        WidgetRefresh.reload([WidgetKind.today])
    }
}

// MARK: - 控制中心「今日行程」開關

struct DayTimelineToggleIntent: SetValueIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "今日行程"
    static var description = IntentDescription("把今天的行程放上靈動島，或收掉")
    /// 不開 App 畫面：LiveActivityIntent 在 App 的行程裡背景執行
    static var openAppWhenRun: Bool = false

    /// 系統按開關時把新的值放進來（true＝放上靈動島）
    @Parameter(title: "顯示")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        await DayTimelineToggleBridge.apply(value)
        return .result()
    }
}

// MARK: - 中型「今天」的「上靈動島」按鈕

struct StartDayTimelineIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "上靈動島"
    static var description = IntentDescription("把今天的行程放上靈動島")
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        await DayTimelineToggleBridge.apply(true)
        return .result()
    }
}
