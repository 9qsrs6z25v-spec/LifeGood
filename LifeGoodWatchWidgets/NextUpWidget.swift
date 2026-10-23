import SwiftUI
import WidgetKit

// MARK: - 錶面「下一場」（手錶 v1，v25.574；watch/judge.md §3.1；watch/build/v1/brief.md G4-2；sim_v1 §5）
//
// 四個形狀，字全部在 WatchText.nextUp（Shared/WatchText.swift），這裡只排版、不拼字：
//   • 長方形（也能放進智慧型堆疊）：「○ 09:30 部門會議」／「12F 大會議室・30 分鐘」／「5 分後・之後 3 件」
//   • 圓形：外圈開始前 60 分鐘從空填到滿（進行中＝已經過了多少），中間記號＋「09:30」；沒有下一場只畫行事曆圖示
//   • 角落：中間記號，沿邊彎字「09:30 部門會議」
//   • 一行字：「09:30 部門會議」
// 錶面＝鎖定畫面：用 lockedSurfaceTitle（會議主題，不是人），**不寫部屬名字**；本來就沒有金額，所以手腕放下不用換字。
// 點了開那一件的細節（lifegood://today?stop=<id>&src=widget；WatchModel.open）；沒有那一件只開 ① 今天。
// 外圈用 Gauge＋時間軸的「每分鐘一筆」（WatchTimelinePlan.nextUp），不用 ProgressView(timerInterval:)（brief §1-14）。
// [手錶 v6] v25.578（watch/judge.md §3.1 表「旅途中（v6）」那一列；watch/build/v6/brief.md G3-4）：
//   旅途中那一種的字已經在 WatchText.nextUp 換好（「✈︎ 14:00 弘大／第 3／5 站・停留 90 分／25 分後・第 2 天」；過夜那一站一律
//   「住宿」；錶面放不下出處，所以不放天氣）。按了〔到了〕錶面馬上換：TripCheckIns 叫 reloadTimelines(ofKind: nextUp)，
//   這裡讀 WatchCheckInLog（經 WatchText.nextUp）。這裡只改點了開哪裡（linkURL）：包裡找得到那一場 → 那一場
//   （旅途中的站：WatchModel.open 開 ④ 旅行＋那一站）；找不到、但是旅途中那一種 → lifegood://life/trip（④ 旅行）；都沒有 → ① 今天。

struct NextUpWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchWidgetKind.nextUp, provider: NextUpProvider()) { entry in
            NextUpWidgetView(entry: entry)
        }
        .configurationDisplayName("下一場")
        .description("今天的下一件事；不寫部屬名字")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

/// 一筆 entry 的畫面：挑形狀、帶網址；最外層是 widget 用的夜空底（錶面上系統會拿掉，堆疊裡看得到）
struct NextUpWidgetView: View {
    let entry: WatchPackageEntry

    @Environment(\.widgetFamily) private var family

    private var model: WatchNextUp {
        WatchText.nextUp(package: entry.package, now: entry.date)
    }

    /// 點了開哪一件：包裡找得到那一場才帶 id（找不到＝只開 App 第一頁）
    private var linkedStop: TimelineStop? {
        guard let id = model.stopId else { return nil }
        return WatchText.findStop(id: id, in: entry.package)?.stop
    }

    /// [v6] 點了開哪裡：那一場（旅途中的站也是）→ 旅途中那一種、包裡找不到那一站 → 那一趟（④ 旅行）→ 只開 App 第一頁
    private var linkURL: URL {
        if let stop = linkedStop {
            return WidgetLink.today(stop)
        }
        if let planId = model.tripPlanId {
            return WidgetLink.trip(planId)
        }
        return WidgetLink.today(nil)
    }

    var body: some View {
        content
            .widgetURL(linkURL)
            .containerBackground(for: .widget) {
                WatchWidgetStyle.sky
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            NextUpCircular(model: model)
        case .accessoryCorner:
            NextUpCorner(model: model)
        case .accessoryInline:
            Text(model.inline)
        default:
            NextUpRectangular(model: model)
        }
    }
}

// MARK: - 長方形：三行

private struct NextUpRectangular: View {
    let model: WatchNextUp

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            NextUpFirstLine(model: model)
            Text(model.line2)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            NextUpThirdLine(text: model.line3, icon: model.line3Icon)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 第一行：種類記號（著色錶面靠形狀分：● 部屬會議、○ 我的行事曆、■ 系統行事曆、✈︎ 旅遊）＋「09:30 部門會議」
private struct NextUpFirstLine: View {
    let model: WatchNextUp

    var body: some View {
        HStack(spacing: 4) {
            markView
            Text(model.line1)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    @ViewBuilder
    private var markView: some View {
        if let mark = model.mark {
            Image(systemName: WatchText.markSymbol(mark))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WatchWidgetStyle.kindColor(mark))
                .widgetAccentable()
        }
    }
}

/// 第三行：「5 分後・之後 3 件」；前面可能有圖示（卡費今天截止 creditcard.fill、今天沒排時那件全天的事）；空的不畫
private struct NextUpThirdLine: View {
    let text: String
    let icon: String?

    var body: some View {
        if !text.isEmpty {
            HStack(spacing: 3) {
                iconView
                Text(text)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(WatchWidgetStyle.countdown)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WatchWidgetStyle.countdown)
        }
    }
}

// MARK: - 圓形：外圈＋記號＋時間

private struct NextUpCircular: View {
    let model: WatchNextUp

    private var ringTint: Color {
        guard let mark = model.mark else { return WatchWidgetStyle.countdown }
        return WatchWidgetStyle.kindColor(mark)
    }

    var body: some View {
        if let ring = model.ring {
            Gauge(value: ring, in: 0...1) {
                EmptyView()
            } currentValueLabel: {
                NextUpRingLabel(model: model)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(ringTint)
            .accessibilityLabel(Text(model.inline))
        } else {
            NextUpCircularIdle(text: model.inline)
        }
    }
}

/// 圓形中間：記號（小）＋「09:30」（下一場開始／進行中那場結束）
private struct NextUpRingLabel: View {
    let model: WatchNextUp

    var body: some View {
        VStack(spacing: 0) {
            markView
            Text(model.time ?? "")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    @ViewBuilder
    private var markView: some View {
        if let mark = model.mark {
            Image(systemName: WatchText.markSymbol(mark))
                .font(.system(size: 8, weight: .bold))
                .widgetAccentable()
        }
    }
}

/// 圓形沒有下一場（今天結束、今天沒排、沒有包、過期）：系統圓底＋行事曆圖示
private struct NextUpCircularIdle: View {
    let text: String

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "calendar")
                .font(.system(size: 18, weight: .semibold))
                .widgetAccentable()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text))
    }
}

// MARK: - 角落：中間記號，沿邊彎字

private struct NextUpCorner: View {
    let model: WatchNextUp

    private var symbol: String {
        guard let mark = model.mark else { return "calendar" }
        return WatchText.markSymbol(mark)
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .widgetAccentable()
            .widgetLabel {
                Text(model.inline)
            }
    }
}
