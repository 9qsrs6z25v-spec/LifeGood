import SwiftUI
import WidgetKit

// MARK: - Widget Extension 進入點（v25.377）
//
// 目前只有一個成員：今日行程的 Live Activity（靈動島 + 鎖定畫面）。
// 之後要加桌面小工具，在這個 bundle 裡多列一個就好。

@main
struct LifeGoodWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DayTimelineLiveActivityWidget()
        // [v25.483] 照片匯入進度（跳出 App 時用靈動島顯示百分比）
        PhotoImportLiveActivityWidget()
    }
}
