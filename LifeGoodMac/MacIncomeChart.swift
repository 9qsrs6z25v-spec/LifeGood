// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.641 mac2 G2] 近 6 個月長條（import Charts；brief.md §2 G2 第 9 條、scout_macui §6、judge_mac.md §P8）。
//
// • 每根 BarMark(x:yStart:yEnd:width:)（不用 x:y:，預設會疊）；ahead 時本月多一根半透明＋RuleMark 虛線＋「預期 NT$x」。
// • ChartContent 是 MainActor：mark 函式寫在 View struct 裡；數字一律 Double（0.0）。
// • 整張一個 VoiceOver 元素。

import SwiftUI
import Charts

struct MacIncomeChart: View {
    let bars: [MacIncomeBar]
    /// 本月預期（中位數 > 本月已入帳 才有）
    let expected: Double?
    let summary: String

    var body: some View {
        Chart {
            ForEach(bars) { b in
                bar(b)
            }
            if let e = expected, let cur = bars.last {
                expectedBar(cur, e)
                expectedRule(e)
            }
        }
        .frame(height: 140)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private func bar(_ b: MacIncomeBar) -> some ChartContent {
        BarMark(x: .value("月", b.label), yStart: .value("收入", 0.0), yEnd: .value("收入", b.amount), width: .ratio(0.6))
            .foregroundStyle(Color.green.opacity(b.isCurrent ? 1.0 : 0.55))
            .cornerRadius(3)
    }

    private func expectedBar(_ cur: MacIncomeBar, _ e: Double) -> some ChartContent {
        BarMark(x: .value("月", cur.label), yStart: .value("收入", cur.amount), yEnd: .value("收入", e), width: .ratio(0.6))
            .foregroundStyle(Color.green.opacity(0.18))
    }

    private func expectedRule(_ e: Double) -> some ChartContent {
        RuleMark(y: .value("預期", e))
            .foregroundStyle(Color.secondary)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .annotation(position: .top, alignment: .trailing, spacing: 2) {
                MacIncomeExpectedLabel(value: e)
            }
    }
}

/// 虛線上的「預期 NT$8.8萬」
struct MacIncomeExpectedLabel: View {
    let value: Double

    var body: some View {
        Text("預期 " + MacText.short(value))
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
