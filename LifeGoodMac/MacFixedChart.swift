// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.644 mac4 G2] 金額走勢圖（實線＝實際、虛線＝預測；judge_mac §R8）。
//
// • 實際：LineMark(x:y:series:「實際」)＋catmullRom＋PointMark＋symbolSize(30.0)；預測：series「預測」＋虛線＋opacity 0.55。
// • ChartContent 是 MainActor：mark 函式寫在 View struct 裡；數字一律 Double。
// • 整張一個 VoiceOver 元素；不做點選（沒有 X 軸選取）。2 筆以上才畫（呼叫端判斷）。

import Charts
import SwiftUI

struct MacFixedTrendChart: View {
    let trend: MacFixedTrend

    var body: some View {
        Chart {
            ForEach(trend.actual) { p in
                actualLine(p)
            }
            ForEach(trend.actual) { p in
                actualPoint(p)
            }
            ForEach(trend.forecast) { p in
                forecastLine(p)
            }
        }
        .chartLegend(.hidden)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private func actualLine(_ p: MacFixedTrendPoint) -> some ChartContent {
        LineMark(x: .value("日期", p.date), y: .value("金額", p.amount), series: .value("線", "實際"))
            .interpolationMethod(.catmullRom)
            .foregroundStyle(Color.accentColor)
    }

    private func actualPoint(_ p: MacFixedTrendPoint) -> some ChartContent {
        PointMark(x: .value("日期", p.date), y: .value("金額", p.amount))
            .symbolSize(30.0)
            .foregroundStyle(Color.accentColor)
    }

    private func forecastLine(_ p: MacFixedTrendPoint) -> some ChartContent {
        LineMark(x: .value("日期", p.date), y: .value("金額", p.amount), series: .value("線", "預測"))
            .lineStyle(StrokeStyle(lineWidth: 1.6, dash: [5, 4]))
            .foregroundStyle(Color.accentColor)
            .opacity(0.55)
    }

    /// 「金額走勢：記了 3 筆，最近一筆 699」（幣別在詳情的金額那列）
    private var summary: String {
        guard let last = trend.actual.last else { return "金額走勢" }
        return "金額走勢：記了 \(trend.actual.count) 筆，最近一筆 " + WidgetMoneyFormat.number(last.amount, digits: 0)
    }
}
