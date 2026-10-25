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
// 智慧型堆疊自己往上排、watchOS 26 才有的卡與控制項都是 v7b，這版不寫。
// [手錶 v2] v25.576：多「＋ 記一筆」（AddWidget.swift；圓形、角落；點了開記帳台）。
// [手錶 v5] v25.582：多「這週跑步」（RunWeekWidget.swift；四個形狀；角落跑者點了直接到準備頁）。

@main
struct LifeGoodWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextUpWidget()
        SpentWidget()
        AddWidget()
        RunWeekWidget()
    }
}
