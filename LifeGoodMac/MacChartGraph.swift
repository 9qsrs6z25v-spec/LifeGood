// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.645 mac5 G2] 圖表頁的兩張圖（judge_mac.md §S5-2）：趨勢長條（BarMark yStart/yEnd＋chartXSelection）、變動／固定甜甜圈（SectorMark）。
//
// • 這版唯一新的 import Charts 檔（另外只有 MacIncomeChart、MacFixedChart）。
// • 每個 mark 拆成 private func … -> some ChartContent；顏色先算好放進 MacChartBar.fill／MacChartSlice.color（一律 Color，
//   不用 AnyShapeStyle、不用漸層、不用 foregroundStyle(by:)、chartForegroundStyleScale）。
// • ForEach、選取一律用 label（ChartDataPoint.id 每次重算都新）。
// • 主控骨架：MacChartBar、MacChartSlice、MacChartTrend、MacChartPie 簽名定案（不准改）；G2 換 body。

import SwiftUI
import Charts

/// 趨勢長條一根（fill 先算好：沒選取＝trend.top、選到那根＝trend.bottom、其餘＝trend.top.opacity(0.45)）
struct MacChartBar: Identifiable {
    let label: String
    let amount: Double
    let fill: Color
    let valueText: String
    var id: String { label }
}

/// 甜甜圈一片（id＝分類名稱或組名，逐筆給色）
struct MacChartSlice: Identifiable {
    let id: String
    let amount: Double
    let color: Color
}

/// 趨勢卡的圖（picked＝chartXSelection 選到的 label）
struct MacChartTrend: View {
    let bars: [MacChartBar]
    let visible: Set<String>
    @Binding var picked: String?
    let title: String
    let count: String

    var body: some View {
        plot
            .chartXSelection(value: $picked)
            .accessibilityLabel(Text(title + "，" + count))
    }

    /// 選到的那一根（虛線＋金額）：picked 對得到 label 才有
    private var selected: MacChartBar? {
        guard let p = picked else { return nil }
        return bars.first(where: { b in b.label == p })
    }

    /// X 軸只標 visible 那幾個（照長條的順序）
    private var axisLabels: [String] {
        bars.map { b in b.label }.filter { l in visible.contains(l) }
    }

    private var plot: some View {
        Chart {
            ForEach(bars) { b in
                bar(b)
            }
            if let s = selected {
                rule(s)
            }
        }
        .chartXAxis {
            AxisMarks(values: axisLabels) { _ in
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

    private func bar(_ b: MacChartBar) -> some ChartContent {
        BarMark(x: .value("期", b.label), yStart: .value("金額", 0.0), yEnd: .value("金額", b.amount), width: .ratio(0.6))
            .foregroundStyle(b.fill)
            .cornerRadius(3)
    }

    private func rule(_ b: MacChartBar) -> some ChartContent {
        RuleMark(x: .value("期", b.label))
            .foregroundStyle(Color.secondary)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .annotation(position: .top, alignment: .center, spacing: 2) {
                MacChartPickLabel(text: b.valueText)
            }
    }
}

/// 虛線上的金額「NT$2,130」
struct MacChartPickLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }
}

/// 甜甜圈（中心字 center、detail 用 ZStack 疊，不用 chartBackground）
struct MacChartPie: View {
    let slices: [MacChartSlice]
    let center: String
    let detail: String

    var body: some View {
        ZStack {
            plot
            MacChartPieCenter(center: center, detail: detail)
        }
        .frame(width: 132, height: 132)
    }

    // 照抄 ChartView.swift:787-793（9f25bf5）SectorMark；逐筆給色
    private var plot: some View {
        Chart(slices) { s in
            slice(s)
        }
        .chartLegend(.hidden)
    }

    private func slice(_ s: MacChartSlice) -> some ChartContent {
        SectorMark(angle: .value("金額", s.amount), innerRadius: .ratio(0.58), angularInset: 2.0)
            .foregroundStyle(s.color)
            .cornerRadius(5)
    }
}

/// 甜甜圈中心：合計＋幾類（照 ChartView.swift:798-816 的兩行）
struct MacChartPieCenter: View {
    let center: String
    let detail: String

    var body: some View {
        VStack(spacing: 2) {
            Text(center)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: 70)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
