import SwiftUI
import WidgetKit

// MARK: - 錶面「已花」（手錶 v1，v25.574；watch/judge.md §3.1、§13-9；watch/build/v1/brief.md G4-3；sim_v1 §6）
//
// 四個形狀，字全部在 WatchText.spent（Shared/WatchText.swift；金額是 iPhone 寫好的 lines(hidden:)／lock），這裡只排版：
//   • 長方形（也能放進智慧型堆疊）：抬手「本月還能花／NT$2.4萬／每天 NT$2,400・10 天」；
//     遮住「本月已花／72%／還有 10 天・今天 2 筆」
//   • 圓形：環 72%、中間「72%」、下面「已花」（沒有收入紀錄：購物車＋「2 筆」「今天」）——本來就只有百分比，不分遮不遮
//   • 角落：沿邊量表＋中間「72%」
//   • 一行字：「今天 2 筆・已花 72%」
// 遮不遮只看 WatchPrivacyRule.masksAmounts：手腕放下（isLuminanceReduced）、系統要求遮（redactionReasons 有 .privacy）、
// 手錶「遮住金額」（entry.watchHides）、iPhone「隱藏金額」（包裡的 phoneHidesAmounts）任一個成立就遮。不用系統的 privacySensitive。
// 點了開 ② 錢（lifegood://expense/overview?src=widget；WatchModel.open）。

struct SpentWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchWidgetKind.spent, provider: SpentProvider()) { entry in
            SpentWidgetView(entry: entry)
        }
        .configurationDisplayName("已花")
        .description("這個月花了多少；手腕放下只寫百分比")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

/// 一筆 entry 的畫面：決定遮不遮、挑形狀、帶網址；最外層是 widget 用的夜空底（錶面上系統會拿掉，堆疊裡看得到）
struct SpentWidgetView: View {
    let entry: WatchPackageEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.redactionReasons) private var reasons

    /// 遮住金額（judge §6.2-2）：手腕放下 ∨ 系統要求遮 ∨ 手錶「遮住金額」∨ iPhone「隱藏金額」
    private var masked: Bool {
        WatchPrivacyRule.masksAmounts(dimmed: dimmed,
                                      redacted: reasons.contains(.privacy),
                                      watchHides: entry.watchHides,
                                      phoneHides: entry.package?.phoneHidesAmounts ?? false)
    }

    private var model: WatchSpent {
        WatchText.spent(package: entry.package, now: entry.date, masked: masked)
    }

    var body: some View {
        content
            .widgetURL(WidgetLink.expenseOverview)
            .containerBackground(for: .widget) {
                WatchWidgetStyle.sky
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            SpentCircular(model: model)
        case .accessoryCorner:
            SpentCorner(model: model)
        case .accessoryInline:
            Text(model.inline)
        default:
            SpentRectangular(model: model)
        }
    }
}

// MARK: - 長方形：三行（抬手寫還能花金額；遮住寫百分比）

private struct SpentRectangular: View {
    let model: WatchSpent

    private var heroColor: Color {
        model.heroIsRed ? WatchWidgetStyle.red : Color.primary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(model.hero)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(heroColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
            Text(model.line3)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 圓形：環＋「72%」＋「已花」

private struct SpentCircular: View {
    let model: WatchSpent

    var body: some View {
        Gauge(value: model.ringValue, in: 0...1) {
            EmptyView()
        } currentValueLabel: {
            SpentRingLabel(model: model)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(WatchWidgetStyle.spentRing)
        .accessibilityLabel(Text(model.inline))
    }
}

/// 圓形中間：（購物車）「72%」「已花」；沒有收入紀錄「🛒 2 筆 今天」
private struct SpentRingLabel: View {
    let model: WatchSpent

    var body: some View {
        VStack(spacing: 0) {
            cartView
            Text(model.ringText)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(model.ringCaption)
                .font(.system(size: 9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    @ViewBuilder
    private var cartView: some View {
        if model.showsCart {
            Image(systemName: "cart.fill")
                .font(.system(size: 8, weight: .bold))
        }
    }
}

// MARK: - 角落：中間「72%」，沿邊量表

private struct SpentCorner: View {
    let model: WatchSpent

    var body: some View {
        Text(model.ringText)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .widgetAccentable()
            .widgetLabel {
                Gauge(value: model.ringValue, in: 0...1) {
                    EmptyView()
                }
                .tint(WatchWidgetStyle.spentRing)
            }
    }
}
