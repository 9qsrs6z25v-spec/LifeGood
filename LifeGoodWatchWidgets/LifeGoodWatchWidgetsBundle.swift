import SwiftUI
import WidgetKit

// MARK: - 手錶小格進入點（手錶 v0，v25.573）
//
// 只屬於「LifeGoodWatchWidgets」target（com.lifegood.app.watchkitapp.widgets，watchOS 11.0），
// 嵌在手錶 App 的 Embed Foundation Extensions（不是 iPhone App）。
// v0 只有一個圓形佔位（錶面「編輯 › 複雜功能」找得到 LifeGood、寫「LG」，點了打開手錶 App）。
// 小格是另一個 bundle、沒有素材目錄，讀不到手錶 App 的圖示，所以只寫字（critic 🟠8）。
// **每一個小格都要 widget 用的 containerBackground**（寫法見 WatchPlaceholderView），少了整格會變成系統的英文提示（critic 🔴5、judge §7.8-10）。
// v1 換成正式的「下一場」「已花」（WatchPackageProvider、NextUpWidget、SpentWidget）；這個佔位的 kind 會拿掉。

@main
struct LifeGoodWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WatchPlaceholderWidget()
    }
}

struct WatchPlaceholderWidget: Widget {
    /// v0 佔位的 kind；v1 拿掉（錶面上放了這格的話要重新選）
    static let kind = "LifeGoodWatchPlaceholder"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchPlaceholderProvider()) { entry in
            WatchPlaceholderView(entry: entry)
        }
        .configurationDisplayName("LifeGood")
        .description("手錶版準備中")
        .supportedFamilies([.accessoryCircular])
    }
}

struct WatchPlaceholderEntry: TimelineEntry {
    let date: Date
}

/// 一筆、不更新（.never）：v0 沒有資料
struct WatchPlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchPlaceholderEntry {
        WatchPlaceholderEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchPlaceholderEntry) -> Void) {
        completion(WatchPlaceholderEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchPlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [WatchPlaceholderEntry(date: Date())], policy: .never))
    }
}

/// 圓形佔位：系統圓底＋「LG」。染色錶面靠 widgetAccentable 上色；點了打開手錶 App（小格預設行為）。
/// 最後那段 widget 用的 containerBackground 不准拿掉：少了整格變成「請採用 containerBackground」的英文提示。
struct WatchPlaceholderView: View {
    let entry: WatchPlaceholderEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Text("LG")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("LifeGood"))
        .containerBackground(for: .widget) {
            Color.clear
        }
    }
}
