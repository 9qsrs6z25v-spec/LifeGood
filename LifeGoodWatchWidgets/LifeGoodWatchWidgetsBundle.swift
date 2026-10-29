import SwiftUI
import WidgetKit

// MARK: - 手錶小格進入點（手錶 v1，v25.574；watch/judge.md §3.1；watch/build/v1/brief.md G4-1）
//
// 只屬於「LifeGoodWatchWidgets」target（com.lifegood.app.watchkitapp.widgets，watchOS 11.0），
// 嵌在手錶 App 的 Embed Foundation Extensions（不是 iPhone App）。
// v1 兩種小格，各四個形狀（圓形、角落、一行字、長方形；長方形也能放進智慧型堆疊）：
//   • 下一場（NextUpWidget.swift）：今天的下一件事；錶面不寫部屬名字（WidgetStop.lockedSurfaceTitle）
//   • 已花（SpentWidget.swift）：這個月花了多少；長方形抬手寫還能花，手腕放下／遮住只寫百分比（§13-9）
// 兩種都讀手錶 App Group 的 watch_v1.json（WatchPackageProvider.swift）；字全部在 WatchText（Shared/WatchText.swift）。
// v0 的「LG」圓形佔位拿掉了：錶面上放了那一格的要重新選（Changelog 寫）。
// 小格是另一個 bundle、沒有素材目錄，讀不到手錶 App 的圖示，所以只用 SF Symbol 與字（critic 🟠8）。
// 每一種小格最外層都要 widget 用的 container background（寫法見 NextUpWidgetView、SpentWidgetView），
// 少了整格會變成系統的英文提示（critic 🔴5、judge §7.8-10）。
// 智慧型堆疊自己往上排、watchOS 26 才有的卡與控制項：v7b（下面）。
// [手錶 v2] v25.576：多「＋ 記一筆」（AddWidget.swift；圓形、角落；點了開記帳台）。
// [手錶 v5] v25.582：多「這週跑步」（RunWeekWidget.swift；四個形狀；角落跑者點了直接到準備頁）。
// [手錶 v7b] v25.584（watch/judge.md §3.2、§3.4；watch/build/v7b/brief.md §2）：watchOS 26 才有的五張堆疊卡（RelevanceCards.swift）
//   與三個控制項（WatchControls.swift）放在 LifeGoodWatch26Bundle，外面用 if #available(watchOS 26, *) 包一次
//   （WidgetBundleBuilder.buildLimitedAvailability(_: some Widget) watchOS 9.1 起、buildOptional watchOS 9 起；build/v7b/doc/）。
//   watchOS 11 的錶只看得到上面四種，其他照常。「下一場」「已花」「這週跑步」自己往上排（relevance()）在 RelevanceCards.swift。

@main
struct LifeGoodWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextUpWidget()
        SpentWidget()
        AddWidget()
        RunWeekWidget()
        if #available(watchOS 26, *) {
            LifeGoodWatch26Bundle().body
        }
    }
}

/// [v7b] watchOS 26 才有的：五張智慧型堆疊卡（只在堆疊出現、不能手動加）＋三個控制項（控制中心、智慧型堆疊）
@available(watchOS 26, *)
struct LifeGoodWatch26Bundle: WidgetBundle {
    var body: some Widget {
        MorningCardWidget()
        MeetingCardWidget()
        CardBillCardWidget()
        UsualRunCardWidget()
        TripStopCardWidget()
        WatchAddRecordControl()
        WatchStartRunControl()
        WatchHideAmountsControl()
    }
}
