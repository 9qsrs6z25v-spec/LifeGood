import SwiftUI
import WidgetKit

// MARK: - 錶面「＋ 記一筆」（手錶 v2，v25.576；watch/judge.md §3.1「＋ 記一筆」、§2.6；watch/build/v2/brief.md §2）
//
// 只屬於 LifeGoodWatchWidgets。圓形、角落兩種形狀，只畫「＋」，不讀包、不寫金額（手腕放下也一樣）；
// 點了開手錶 App 的記帳台（lifegood://add/expense，WatchModel.open → WatchSheet.record）：從錶面記一筆＝點「＋」、點一格，兩下。
// 時間軸只有一筆、.never（不吃重畫額度）。跟其他小格一樣最外層要 widget 的 container background（judge §7.8-10）。

struct AddWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchWidgetKind.add, provider: AddProvider()) { entry in
            AddWidgetView(entry: entry)
        }
        .configurationDisplayName("記一筆")
        .description("點一下打開記帳台，再點一格就記好")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

struct AddEntry: TimelineEntry {
    let date: Date
}

struct AddProvider: TimelineProvider {
    func placeholder(in context: Context) -> AddEntry {
        AddEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (AddEntry) -> Void) {
        completion(AddEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AddEntry>) -> Void) {
        completion(Timeline(entries: [AddEntry(date: Date())], policy: .never))
    }
}

struct AddWidgetView: View {
    let entry: AddEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(WidgetLink.addExpense())
            .containerBackground(for: .widget) {
                WatchWidgetStyle.sky
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCorner:
            cornerView
        default:
            circularView
        }
    }

    /// 圓形：系統的小圓底＋粗「＋」
    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .widgetAccentable()
        }
    }

    /// 角落：「＋」＋沿邊彎字「記一筆」
    private var cornerView: some View {
        Image(systemName: "plus")
            .font(.system(size: 20, weight: .bold))
            .widgetAccentable()
            .widgetLabel {
                Text("記一筆")
            }
    }
}
