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
//
// [v3] 加入：旅行（小、中、鎖定畫面長方形，TravelWidget）；控制項「說一句」「記到…」（放子 bundle，共 7 個）。
// 還能花、今天、記帳台、接下來要繳、鎖定畫面「下一場」「下一筆要繳」改成長按可設定（kind 不變，各自的檔案）。
// 這一層現在 9 個、子 bundle 7 個，都在 10 個以內。
//
// [v4] 加入理財四個（五個 kind）：股票今天（小＋鎖定畫面三型 StockWidget、中 StocksWidget）、金價匯率（RatesWidget）、
// 我的車（VehicleWidget）、淨資產（NetWorthWidget），放子 bundle（LifeGoodFinanceBundle），這裡列它的 body。
// 這一層現在 10 個、LifeGoodLockAndControlBundle 7 個、LifeGoodFinanceBundle 5 個，都在 10 個以內。
//
// [v5] 加入：部屬今天（小、中、鎖定畫面長方形與一行字，TeamWidget）、控制項「今日行程」（DayTimelineControl，
// 靈動島開關）；「今天」多了大型（TodayWidget，kind 不變）。這一層已經 10 個，所以旅行搬進新的子 bundle
// LifeGoodLifeBundle（跟部屬今天放一起；kind 不變，已經放好的旅行小工具不受影響），今日行程放進
// LifeGoodLockAndControlBundle。這一層 10 個、LifeGoodLockAndControlBundle 8 個、LifeGoodFinanceBundle 5 個、
// LifeGoodLifeBundle 2 個，都在 10 個以內。
// 型別由 G2（TeamWidget，TeamWidget.swift）、G3（DayTimelineControl，LifeGoodControls.swift）實作，
// 名字是 scratchpad/widgets/v5/brief.md 定死的。
//
// [健康 v6，v25.556] 加入跑步的即時動態（RunLiveActivityWidget，RunLiveActivity.swift：鎖定畫面、靈動島、手錶智慧型堆疊），
// 放 LifeGoodLifeBundle（這一層已經 10 個）。LifeGoodLifeBundle 現在 3 個，都在 10 個以內。
//
// [健康 v7b，v25.558] 加入控制項「開始跑步」（StartRunControl，LifeGoodControls.swift：figure.run →
// LifeGoodOpenIntent(url: WidgetLink.healthRun)），放 LifeGoodLockAndControlBundle（8 → 9）。
// 這一層 10 個、LifeGoodLockAndControlBundle 9 個、LifeGoodFinanceBundle 5 個、LifeGoodLifeBundle 3 個，都在 10 個以內。
// 名字是 build/v7b/brief.md §5 定死的。

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
        // [v2] 鎖定畫面三個＋控制項（[v3] 四個；[v5] 五個；[健康 v7b] 六個）
        LifeGoodLockAndControlBundle().body
        // [v4] 理財四個（五個 kind）
        LifeGoodFinanceBundle().body
        // [v5] 旅行（[v3]，從這一層搬下去）＋部屬今天
        LifeGoodLifeBundle().body
    }
}

/// [v2] @WidgetBundleBuilder 一次最多 10 個，鎖定畫面三個＋控制項放這裡（[v3] 加說一句、記到…，共 7 個；
/// [v5] 加今日行程，共 8 個；[健康 v7b] 加開始跑步，共 9 個）
struct LifeGoodLockAndControlBundle: WidgetBundle {
    var body: some Widget {
        LockSpentWidget()
        LockNextStopWidget()
        LockNextBillWidget()
        AddExpenseControl()
        HideAmountsControl()
        // [v3]
        VoiceRecordControl()
        RecordToControl()
        // [v5] 靈動島今日行程開關
        DayTimelineControl()
        // [健康 v7b] 控制中心「開始跑步」
        StartRunControl()
    }
}

/// [v4] 股票今天（小＋鎖定畫面、中）、金價匯率、我的車、淨資產（@WidgetBundleBuilder 一次最多 10 個，共 5 個）
struct LifeGoodFinanceBundle: WidgetBundle {
    var body: some Widget {
        StockWidget()
        StocksWidget()
        RatesWidget()
        VehicleWidget()
        NetWorthWidget()
    }
}

/// [v5] 人生：旅行（[v3]）、部屬今天；[健康 v6] 跑步的即時動態（@WidgetBundleBuilder 一次最多 10 個，共 3 個）
struct LifeGoodLifeBundle: WidgetBundle {
    var body: some Widget {
        TravelWidget()
        TeamWidget()
        // [健康 v6] 跑步：鎖定畫面「晨跑・跑步中　3.42 公里｜21:05｜6'20"」＋暫停鈕、靈動島「跑者 3.42 ── 21:05」
        RunLiveActivityWidget()
    }
}
