import SwiftUI
import WidgetKit

// MARK: - Widget Extension 進入點（v25.377）
//
// 目前只有一個成員：今日行程的 Live Activity（靈動島 + 鎖定畫面）。
// 之後要加桌面小工具，在這個 bundle 裡多列一個就好。
//
// [v25.545] 加入兩個桌面小工具：「還能花」（MoneyLeftWidget，小）、「今天」（TodayWidget，小、中）。
// 兩個都只讀 App Group 裡 App 寫好的快照（WidgetSnapshot.swift），小工具庫裡的名字是「LifeGood」。
//
// [v2] 加入：記帳台（中）、一按就記（小、中）、接下來要繳（中）；鎖定畫面「已花」「下一場」「下一筆要繳」；
// 控制項「記一筆」「隱藏金額」。@WidgetBundleBuilder 一次最多列 10 個，鎖定畫面三個＋控制項兩個
// 放在子 bundle（LifeGoodLockAndControlBundle），這裡列它的 body。

@main
struct LifeGoodWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DayTimelineLiveActivityWidget()
        // [v25.483] 照片匯入進度（跳出 App 時用靈動島顯示百分比）
        PhotoImportLiveActivityWidget()
        // [v25.545] 桌面小工具
        MoneyLeftWidget()
        TodayWidget()
        // [v2] 桌面小工具
        LedgerDeskWidget()
        QuickRecordWidget()
        BillsWidget()
        // [v2] 鎖定畫面三個＋控制項兩個
        LifeGoodLockAndControlBundle().body
    }
}

/// [v2] @WidgetBundleBuilder 一次最多 10 個，鎖定畫面三個＋控制項兩個放這裡
struct LifeGoodLockAndControlBundle: WidgetBundle {
    var body: some Widget {
        LockSpentWidget()
        LockNextStopWidget()
        LockNextBillWidget()
        AddExpenseControl()
        HideAmountsControl()
    }
}
