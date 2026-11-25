// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.645 mac5 G2] 圖表看板右邊的星座（judge_mac.md §S5-1 ⑮）：照抄 MoneyBoardScenes.swift:1015-1050（9f25bf5）paintConstellation 的星，
//   不抄畫字（:1051-1063）；全 LifeGoodMac 唯一的 Canvas。
//
// • 只畫不收滑鼠：外面 .accessibilityHidden(true)、.allowsHitTesting(false)；不准 ctx.resolve(、ctx.draw(（不畫字）。
// • MacChartSkyView 是 View＋Equatable，看板用 .equatable()（values 一樣不重畫）。
// • 主控骨架：MacChartSkyView(values:)、MacChartSky.paint(_:rect:values:) 簽名定案；G2 換內容。

import SwiftUI

struct MacChartSkyView: View, Equatable {
    let values: [Double]

    var body: some View {
        Canvas { ctx, size in
            MacChartSky.paint(&ctx, rect: CGRect(origin: .zero, size: size), values: values)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

enum MacChartSky {
    // 照抄 MoneyBoardScenes.swift:1015-1050（9f25bf5）paintConstellation（Color(tb:) → MacSky；MoneyArtPatternLayer.star → starPath；
    // 不抄 :1051-1063 畫字）— sim5: sky5#1
    /// 星座：山影、連線、光暈、星，最多那期金色五角星；values.count < 2 只畫山影
    static func paint(_ ctx: inout GraphicsContext, rect: CGRect, values: [Double]) {
        let r = rect
        let w = r.width
        let top = r.minY + 20
        let bot = r.maxY - 22
        // 地平線的山影
        var hill = Path()
        hill.move(to: CGPoint(x: 0, y: r.maxY))
        hill.addLine(to: CGPoint(x: 0, y: r.maxY - 10))
        hill.addQuadCurve(to: CGPoint(x: w * 0.6, y: r.maxY - 12), control: CGPoint(x: w * 0.3, y: r.maxY - 22))
        hill.addQuadCurve(to: CGPoint(x: w, y: r.maxY - 14), control: CGPoint(x: w * 0.8, y: r.maxY - 2))
        hill.addLine(to: CGPoint(x: w, y: r.maxY))
        hill.closeSubpath()
        ctx.fill(hill, with: .color(MacSky.hill))

        guard values.count >= 2 else { return }
        let maxV = max(values.max() ?? 0, 1)
        let n = values.count
        var pts: [CGPoint] = []
        for (i, v) in values.enumerated() {
            let x = r.minX + 16 + (w - 32) * CGFloat(i) / CGFloat(n - 1)
            let y = bot - (bot - top) * CGFloat((max(0, v) / maxV).squareRoot())
            pts.append(CGPoint(x: x, y: y))
        }
        var line = Path()
        line.addLines(pts)
        ctx.stroke(line, with: .color(MacSky.line), lineWidth: 0.9)
        for (i, p) in pts.enumerated() {
            let rr = 1.2 + 3.2 * CGFloat((max(0, values[i]) / maxV).squareRoot())
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - rr * 2.4, y: p.y - rr * 2.4, width: rr * 4.8, height: rr * 4.8)),
                     with: .color(MacSky.halo))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2)),
                     with: .color(MacSky.star))
        }
        // 最多的那一期：最亮的星（同額留第一個）
        if let iMax = values.indices.max(by: { values[$0] < values[$1] }), values[iMax] > 0 {
            ctx.fill(starPath(center: pts[iMax], radius: 10), with: .color(MacSky.gold))
        }
    }

    /// 五角星（10 點：外徑 radius、內徑 0.42 × radius，尖朝上）
    private static func starPath(center: CGPoint, radius: CGFloat) -> Path {
        var p = Path()
        let inner: CGFloat = radius * 0.42
        for k in 0..<10 {
            let rr: CGFloat = k % 2 == 0 ? radius : inner
            let angle: Double = -Double.pi / 2 + Double(k) * Double.pi / 5
            let pt = CGPoint(x: center.x + rr * CGFloat(cos(angle)), y: center.y + rr * CGFloat(sin(angle)))
            if k == 0 {
                p.move(to: pt)
            } else {
                p.addLine(to: pt)
            }
        }
        p.closeSubpath()
        return p
    }
}
