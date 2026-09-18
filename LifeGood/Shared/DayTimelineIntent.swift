import Foundation
import AppIntents
import ActivityKit

// MARK: - 點小點點切換場次（v25.377）
//
// 這個檔案同時屬於「主 App」與「LifeGoodWidgets」兩個 target。
// Widget Extension 需要它來建出 Button(intent:)，實際執行則發生在主 App 的行程裡
//（LiveActivityIntent 的語意），所以更新 Activity 的程式碼放這裡兩邊都編得過。
//
// ⚠️ 展開的靈動島只接受 Button／Toggle，沒有自由點擊區也沒有手勢。
//    「點軸上的點看該場會議」就是靠這個 intent 換掉 ContentState.selectedIndex。

@available(iOS 17.0, *)
struct SelectTimelineStopIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "選擇行程"
    static var description = IntentDescription("切換今日行程時間軸上顯示的場次")
    /// 不要打開 App：使用者只是想在靈動島裡換一站來看
    static var openAppWhenRun: Bool = false

    @Parameter(title: "場次索引")
    var index: Int

    init() {}
    init(index: Int) { self.index = index }

    func perform() async throws -> some IntentResult {
        await DayTimelineLiveActivity.select(index: index)
        return .result()
    }
}

// MARK: - 更新執行中的 Live Activity

enum DayTimelineLiveActivity {

    /// 目前執行中的那一個（同時間只會有一個）
    @available(iOS 16.2, *)
    static var running: Activity<DayTimelineAttributes>? {
        Activity<DayTimelineAttributes>.activities.first
    }

    /// 切換展開區要顯示哪一站。索引越界時夾回範圍內，不做任何事也不報錯——
    /// 使用者按下按鈕到 intent 執行之間，快照有可能已經被重新整理過。
    @available(iOS 16.2, *)
    static func select(index: Int) async {
        guard let activity = running else { return }
        var state = activity.content.state
        guard !state.stops.isEmpty else { return }
        state.selectedIndex = min(max(index, 0), state.stops.count - 1)
        await activity.update(ActivityContent(state: state,
                                              staleDate: activity.content.staleDate))
    }
}
