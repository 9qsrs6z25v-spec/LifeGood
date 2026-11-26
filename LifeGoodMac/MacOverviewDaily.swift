// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.648 mac7 G2] 總覽中間的每天花多少（judge_mac.md §U3-4）：每日長條＋日預算虛線＋今天虛線＋扣款日站牌點。
//
// • 這版唯一新的 import Charts 檔；BarMark 一律 yStart:／yEnd:（不寫 BarMark(x:… y:)）；mark 都拆成 private func 回 some ChartContent。
// • 色在卡片 body 先算好（讀 colorScheme 一次）、一律 Color：不用漸層、AnyShapeStyle、foregroundStyle(by:)、chartForegroundStyleScale(。
// • 不做點選（沒有 chartXSelection、chartOverlay）；整張一個 VoiceOver 元素。
// • 主控骨架（C0）：MacOverviewDailyCard(data:)、MacOverviewBar、MacOverviewStop 定案（§U7-6）。G2 填內容（圖拆成 fileprivate MacOverviewDailyChart）。

import SwiftUI
import Charts

/// 長條的一根（under＝日預算以內那截、over＝超過的那截；色先算好）
struct MacOverviewBar: Identifiable {
    let label: String
    let under: Double
    let over: Double
    let underFill: Color
    let overFill: Color

    var id: String { label }
}

/// 扣款日站牌點（past 淡、next／later 實）
struct MacOverviewStop: Identifiable {
    let label: String
    let fill: Color

    var id: String { label }
}

/// §U3-4 每天花多少（.macBoard(.orange)）— sim7: ov7#14 ov7#15
/// 色在這裡先算好（讀 colorScheme 一次）：under＝MacChartTheme.mixVariable（iPhone 變動藍）、over＝MacTone.warn、今天以後不上色；
/// 站牌 past＝MacRailTint.station 淡 0.4、next／later＝station。沒資料（d.daily 全 0 而且沒有日預算）＝空的提示。
struct MacOverviewDailyCard: View {
    let data: MacOverviewBoardData
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = MacPalette(scheme)
        let days = MacOverviewBoardText.daily(data)
        let empty = data.daily.allSatisfy { $0 == 0 } && data.dailyBudget == nil
        VStack(alignment: .leading, spacing: 10) {
            MacSectionHeader(title: "每天花多少", icon: "chart.bar.fill", tint: MacPageTheme.orange.top,
                             count: MacOverviewBoardText.budgetText(data))
            if empty {
                MacEmptyHint(icon: "chart.bar", tint: MacPageTheme.orange.top, title: "這個月還沒有變動支出", detail: nil)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                MacOverviewDailyChart(bars: Self.bars(days, dark: p.dark), stops: Self.stops(days, scheme: scheme),
                                      budget: data.dailyBudget, budgetLabel: MacOverviewBoardText.budgetText(data),
                                      today: "\(data.day)", axis: MacOverviewBoardText.axisDays(data))
                    .frame(height: 150)
                if let next = MacOverviewBoardText.nextLabel(data) {
                    Label(next, systemImage: "tram.fill")
                        .font(.caption)
                        .foregroundStyle(p.label)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .macBoard(.orange)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MacOverviewBoardText.dailySummary(data))
    }

    /// 長條：日預算以內那截藍、超過那截 warn；今天以後（0 高）不上色
    private static func bars(_ days: [MacOverviewDay], dark: Bool) -> [MacOverviewBar] {
        let p = MacPalette(dark ? .dark : .light)
        let warn: Color = MacTone.warn.color(p)
        var out: [MacOverviewBar] = []
        for d in days {
            let under: Color = d.amount > 0 ? MacChartTheme.mixVariable : Color.clear
            let over: Color = d.over > 0 ? warn : Color.clear
            out.append(MacOverviewBar(label: d.label, under: d.under, over: d.over, underFill: under, overFill: over))
        }
        return out
    }

    /// 站牌：扣款日一天一顆（past 淡、next／later 實；沒有扣款的那天不畫）
    private static func stops(_ days: [MacOverviewDay], scheme: ColorScheme) -> [MacOverviewStop] {
        let station: Color = MacRailTint(scheme).station
        var out: [MacOverviewStop] = []
        for d in days {
            switch d.station {
            case .none: continue
            case .past: out.append(MacOverviewStop(label: d.label, fill: station.opacity(0.4)))
            case .next, .later: out.append(MacOverviewStop(label: d.label, fill: station))
            }
        }
        return out
    }
}

/// 圖本身（不做點選：沒有 chartXSelection、chartOverlay）；mark 都拆 private func 回 some ChartContent
fileprivate struct MacOverviewDailyChart: View {
    let bars: [MacOverviewBar]
    let stops: [MacOverviewStop]
    let budget: Double?
    let budgetLabel: String?
    let today: String
    let axis: [String]

    var body: some View {
        Chart {
            ForEach(bars) { b in
                under(b)
                over(b)
            }
            if let v = budget {
                budgetRule(v)
            }
            todayRule(today)
            ForEach(stops) { s in
                stop(s)
            }
        }
        .chartXAxis {
            AxisMarks(values: axis) { _ in
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { v in
                AxisGridLine()
                AxisValueLabel {
                    Text(MacChartText.axis(v.as(Double.self) ?? 0))
                }
            }
        }
    }

    private func under(_ b: MacOverviewBar) -> some ChartContent {
        BarMark(x: .value("日", b.label), yStart: .value("金額", 0.0), yEnd: .value("金額", b.under), width: .ratio(0.62))
            .foregroundStyle(b.underFill)
            .cornerRadius(2)
    }

    private func over(_ b: MacOverviewBar) -> some ChartContent {
        BarMark(x: .value("日", b.label), yStart: .value("金額", b.under), yEnd: .value("金額", b.under + b.over), width: .ratio(0.62))
            .foregroundStyle(b.overFill)
            .cornerRadius(2)
    }

    /// 日預算虛線＋「日預算 NT$1,087」（照 MacIncomeChart.expectedRule 寫法）
    private func budgetRule(_ v: Double) -> some ChartContent {
        RuleMark(y: .value("日預算", v))
            .foregroundStyle(Color.secondary)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .annotation(position: .top, alignment: .trailing, spacing: 2) {
                MacOverviewChartNote(text: budgetLabel ?? "")
            }
    }

    /// 今天一條虛線＋「今天」
    private func todayRule(_ label: String) -> some ChartContent {
        RuleMark(x: .value("日", label))
            .foregroundStyle(Color.secondary.opacity(0.6))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            .annotation(position: .top, alignment: .center, spacing: 2) {
                MacOverviewChartNote(text: "今天")
            }
    }

    /// 扣款日站牌（照 MacFixedChart.actualPoint 寫法）
    private func stop(_ s: MacOverviewStop) -> some ChartContent {
        PointMark(x: .value("日", s.label), y: .value("金額", 0.0))
            .symbolSize(30.0)
            .foregroundStyle(s.fill)
    }
}

/// 虛線上的小字（「日預算 NT$1,087」「今天」）
fileprivate struct MacOverviewChartNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
