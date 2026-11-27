import SwiftUI
import WidgetKit

// MARK: - 手錶小格的時間軸（手錶 v1，v25.574；watch/judge.md §3.1「時間軸」「更新額度」；watch/build/v1/brief.md §2、G4）
//
// 只屬於 LifeGoodWatchWidgets。兩種小格都讀手錶 App Group 的 watch_v1.json（WidgetSnapshotStore.read(WatchPackage.self)），
// 在 provider 讀一次放進 entry，View 裡不讀檔、不讀設定。要排哪幾個時間點在 WatchTimelinePlan（Shared/WatchText.swift，
// 照 iPhone TodayWidgetTimeline 的規則；sim_v1.py 算過）。
// v1 **不寫智慧型堆疊的排序**（watchOS 的堆疊排序只看 provider 的相關性那一支／watchOS 26 的設定，一起放 v7b；judge §3.2）。
// 檔尾的 WatchWidgetStyle 是小格自己的顏色（手錶小格不能編手錶 App 資料夾裡那份樣子檔；色碼在 WatchPalette）。

/// 一筆 entry：那一刻、手上那一包、手錶自己的「遮住金額」
struct WatchPackageEntry: TimelineEntry {
    let date: Date
    let package: WatchPackage?
    let watchHides: Bool
}

enum WatchWidgetSource {
    /// provider 讀一次（View 裡不讀）
    static func read() -> (package: WatchPackage?, watchHides: Bool) {
        (WidgetSnapshotStore.read(WatchPackage.self), WatchHideAmounts.isOn)
    }

    static func timeline(_ plan: WatchTimelineDates, package: WatchPackage?, watchHides: Bool) -> Timeline<WatchPackageEntry> {
        let entries: [WatchPackageEntry] = plan.dates.map {
            WatchPackageEntry(date: $0, package: package, watchHides: watchHides)
        }
        let policy: TimelineReloadPolicy = plan.reloadAt.map { TimelineReloadPolicy.after($0) } ?? .never
        return Timeline(entries: entries, policy: policy)
    }
}

/// 下一場：倒數那幾分鐘每分鐘一筆、每場開始結束、換日、過期、「09:24 更新」出現；2 小時跟系統要一次新的
struct NextUpProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchPackageEntry {
        WatchPackageEntry(date: Date(), package: nil, watchHides: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchPackageEntry) -> Void) {
        let src = WatchWidgetSource.read()
        completion(WatchPackageEntry(date: Date(), package: src.package, watchHides: src.watchHides))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchPackageEntry>) -> Void) {
        let src = WatchWidgetSource.read()
        let plan = WatchTimelinePlan.nextUp(package: src.package, now: Date())
        completion(WatchWidgetSource.timeline(plan, package: src.package, watchHides: src.watchHides))
    }
}

/// 已花：現在＋往後每天 00:00＋「上次更新」出現＋最後一天結束；之後等下一包送來重畫（.never）
struct SpentProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchPackageEntry {
        WatchPackageEntry(date: Date(), package: nil, watchHides: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchPackageEntry) -> Void) {
        let src = WatchWidgetSource.read()
        completion(WatchPackageEntry(date: Date(), package: src.package, watchHides: src.watchHides))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchPackageEntry>) -> Void) {
        let src = WatchWidgetSource.read()
        let plan = WatchTimelinePlan.spent(package: src.package, now: Date())
        completion(WatchWidgetSource.timeline(plan, package: src.package, watchHides: src.watchHides))
    }
}

// MARK: - 小格自己的樣子（手錶 v1；色碼在 WatchPalette，Shared/WatchText.swift）
//
// 錶面上系統會拿掉底色、著色錶面會把顏色洗成單色（靠字和形狀分，不靠顏色）；智慧型堆疊看得到夜空。

enum WatchWidgetStyle {
    /// 0xRRGGBB → Color（sRGB）
    static func color(_ hex: UInt32) -> Color {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// 堆疊卡的夜空：121B38（頂）→ 0E1428（底）；跟手錶 App 看板頁、iPhone 深色看板同一片
    static var sky: LinearGradient {
        LinearGradient(colors: [WatchWidgetStyle.color(WatchPalette.skyTop),
                                WatchWidgetStyle.color(WatchPalette.skyMid)],
                       startPoint: .top, endPoint: .bottom)
    }

    /// 倒數、第三行（「5 分後・之後 3 件」）
    static var countdown: Color { WatchWidgetStyle.color(WatchPalette.countdown) }
    /// 超支的大字
    static var red: Color { WatchWidgetStyle.color(WatchPalette.red) }
    /// 「已花」的環（變動支出藍）
    static var spentRing: Color { WatchWidgetStyle.color(WatchPalette.variableBar) }

    /// 行程種類的顏色（會議橘、我的行事曆青、系統行事曆綠、旅遊紫）
    static func kindColor(_ kind: TimelineStopKind) -> Color {
        WatchWidgetStyle.color(WatchPalette.kind(kind))
    }
}
