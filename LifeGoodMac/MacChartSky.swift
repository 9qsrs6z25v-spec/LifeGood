// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.645 mac5 G2] 圖表看板右邊的星座（judge_mac.md §S5-1 ⑮）：照抄 MoneyBoardScenes.swift:1015-1050（9f25bf5）paintConstellation 的星，
//   不抄畫字（:1051-1063）；全 LifeGoodMac 唯一的 Canvas。
//
// • 只畫不收滑鼠：外面 .accessibilityHidden(true)、.allowsHitTesting(false)；不准 ctx.resolve(、ctx.draw(（不畫字）。
// • MacChartSkyView 是 View＋Equatable，看板用 .equatable()（values 一樣不重畫）。
// • 主控骨架：MacChartSkyView(values:)、MacChartSky.paint(_:rect:values:) 簽名定案；G2 換內容。
// [v25.648 mac7 G4] 夜空滑過（judge_mac.md §U6-1）：星座本身不動，上面疊一層只收滑鼠的透明層 MacChartSkyHover（onContinuousHover、
//   GeometryReader 全 LifeGoodMac 只在這裡）；停在星上寫那一期・金額（沒有名字），點一下＝選那一期（外面 focus = .period，不寫任何 store）。

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

// MARK: - 夜空滑過（§U6-1；Mac 7）

/// 滑過層的一顆星：label＝那一期（長條的 label，點一下就選它）、text＝提示字（那一期・金額；沒有名字）
struct MacChartSkyPoint: Equatable {
    let label: String
    let text: String
}

extension MacChartSky {
    // sim7: sky7#2
    /// 跟 paint 同一條：x＝16＋(w−32)·i／(n−1)（paint 的 rect 是 origin .zero，minX＝0）；n < 2 沒有星座 → 正中間
    static func pointX(_ i: Int, width: CGFloat, count n: Int) -> CGFloat {
        guard n >= 2 else { return width / 2 }
        return 16 + (width - 32) * CGFloat(i) / CGFloat(n - 1)
    }

    // sim7: sky7#3
    /// 滑鼠 x → 最近那顆星；n < 2、太窄、超出最近那顆半格（max(6, 格寬／2)）→ nil
    static func hoverIndex(x: CGFloat, width: CGFloat, count n: Int) -> Int? {
        guard n >= 2, width > 32, x.isFinite else { return nil }
        let step: CGFloat = (width - 32) / CGFloat(n - 1)
        let raw: CGFloat = ((x - 16) / step).rounded()
        let i: Int = Int(min(max(raw, 0), CGFloat(n - 1)))
        let half: CGFloat = max(6, step / 2)
        return abs(x - pointX(i, width: width, count: n)) <= half ? i : nil
    }

    // sim7: sky7#1
    /// 星座有畫（values.count ≥ 2）而且跟 bars 一樣多才有點；不然空（總計 0 時 skyValues 是空的 → 滑過、點都沒反應）
    static func hoverPoints(values: [Double], bars: [MacChartBar]) -> [MacChartSkyPoint] {
        guard values.count >= 2, values.count == bars.count else { return [] }
        return bars.map { b in MacChartSkyPoint(label: b.label, text: b.label + "・" + b.valueText) }
    }

    // sim7: sky7#4
    /// 提示框（寬 140）左緣：那顆星置中，夾在 [0, w − 140]（太窄就靠左）
    static func tipX(_ i: Int, width: CGFloat, count n: Int) -> CGFloat {
        let x: CGFloat = pointX(i, width: width, count: n) - 70
        return min(max(0, x), max(0, width - 140))
    }
}

// sim7: sky7#5
/// 只收滑鼠的透明層：滑過寫那一期・金額，點一下 onPick(label)；鍵盤用〔換一期 ▾〕（L7-8），不進輔助使用（星座本身也 hidden）
struct MacChartSkyHover: View {
    let points: [MacChartSkyPoint]
    let onPick: (String) -> Void
    @State private var hovered: Int? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p):
                            hovered = MacChartSky.hoverIndex(x: p.x, width: geo.size.width, count: points.count)
                        case .ended:
                            hovered = nil
                        }
                    }
                    .onTapGesture {
                        if let i = hovered, i < points.count { onPick(points[i].label) }
                    }
                if let i = hovered, i < points.count {
                    MacChartSkyTip(text: points[i].text)
                        .offset(x: MacChartSky.tipX(i, width: geo.size.width, count: points.count), y: 2)
                        .allowsHitTesting(false)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// 提示框：寬 140、白 12% 膠囊底＋白 18% 框、caption semibold、夜空上一律淺字（不加動畫）
struct MacChartSkyTip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(MacSky.ink.ink)
            .lineLimit(1)
            .frame(width: 140, height: 22)
            .background(Color.white.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }
}
