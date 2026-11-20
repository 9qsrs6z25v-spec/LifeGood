//
//  UtilityTrendChart.swift
//  LifeGood
//
//  [v25.620] 水電瓦斯趨勢的圖（房子水電區小圖、v2 全頁共用）。
//  - 資料全部在 UtilityTrendData.swift 算好（UtilityTrendChartData：點、線段、平均、domain、VoiceOver 那句）；
//    這裡只畫，不算、不寫 store。UserDefaults 只在 UtilityTrendMemory（膠囊按鈕的動作裡才叫 save）。
//  - 閃退規則（critic_crash §9）：外殼 UtilityTrendChart 只管手指位置／高度／VoiceOver；Chart 單獨一個
//    UtilityTrendPlot；每個 mark 一個 @ChartContentBuilder func；點形用 UTDot 的 switch，不用三元。
//  - 顏色由 type 對照（Data 不放 Color：切深色模式不用重算資料）。
//  - [v25.623] 電費度數圖的夏月淡灰底：chart.bands 一律 ForEach（沒有就空陣列，不用 if），畫在最底下；
//    帳單標記的期空心點（UTDot 本來就有 hollow）；圖例多「灰底是夏月（6–9 月）」。
//

import SwiftUI
import Charts

// MARK: - 顏色

/// 水電顏色（從 HouseCardViews.swift 的 HCColors.utility 搬過來；舊的改成一行轉呼叫）
enum UtilityPalette {
    /// 水藍、電琥珀（字也用這個：A65300／FFC14D）、瓦斯橘
    static func line(_ t: UtilityType, pal: TripBoardPalette) -> Color {
        switch t {
        case .water: return FinanceCardColors.pick(0x2F7FE8, 0x7DB2FF, pal)
        case .electricity: return FinanceCardColors.pick(0xA65300, 0xFFC14D, pal)
        case .gas: return FinanceCardColors.pick(0xE07A2E, 0xFFA366, pal)
        }
    }

    /// 沒指定是哪個表的灰點
    static func neutral(_ pal: TripBoardPalette) -> Color {
        FinanceCardColors.pick(0x9AA3B5, 0x8A93A6, pal)
    }

    /// [v25.623] 夏月（6–9 月）淡灰底（不是黃：電費線是琥珀色）
    static func summer(_ pal: TripBoardPalette) -> Color {
        FinanceCardColors.pick(0xEEF0F4, 0x262A33, pal)
    }
}

// MARK: - 上次看的種類

/// 上次看的種類（只是個人方便：讀不到就退回預設）。存 UtilityType.rawValue，不同步、不進匯出
enum UtilityTrendMemory {
    static func key(_ estateId: UUID) -> String {
        "utilityTrendKind-" + estateId.uuidString
    }

    static func load(_ estateId: UUID) -> UtilityType? {
        guard let raw = UserDefaults.standard.string(forKey: key(estateId)) else { return nil }
        return UtilityType(rawValue: raw)
    }

    /// 只准在按鈕動作裡叫（不准在 body、build、.task）
    static func save(_ t: UtilityType, estateId: UUID) {
        UserDefaults.standard.set(t.rawValue, forKey: key(estateId))
    }
}

// MARK: - 圖外殼

/// 小圖、全頁共用。外殼只管：手指位置、找最近一點、高度、VoiceOver
struct UtilityTrendChart: View {
    let chart: UtilityTrendChartData
    let pal: TripBoardPalette
    /// 小圖 150、全頁 200
    let height: CGFloat
    @Binding var pickedKey: String?
    /// 手指正在按的日期（chartXSelection；放開就變回 nil，選取留著）
    @State private var raw: Date?

    var body: some View {
        UtilityTrendPlot(chart: chart, pal: pal, pickedKey: pickedKey, raw: $raw)
            .onChange(of: raw) { _, d in pick(d) }
            .onChange(of: chart.identity) { _, _ in raw = nil }
            .frame(height: height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(chart.accessibilityText)
    }

    /// 放開後 raw 變 nil 不清選取；nearestKey 在 Data（二分搜尋）
    private func pick(_ d: Date?) {
        guard let d, let k = chart.nearestKey(to: d), k != pickedKey else { return }
        pickedKey = k
    }
}

// MARK: - 只有 Chart

/// 只放 Chart（strict 16）。lines 只有 2 點以上的段、points 全部的點（含灰點），都在 Data 攤平好
fileprivate struct UtilityTrendPlot: View {
    let chart: UtilityTrendChartData
    let pal: TripBoardPalette
    let pickedKey: String?
    @Binding var raw: Date?

    var body: some View {
        Chart {
            ForEach(chart.bands) { b in band(b) }
            ForEach(chart.lines) { p in line(p) }
            ForEach(chart.points) { p in point(p) }
            if let avg = chart.average { averageRule(avg) }
            if let x = chart.x(of: pickedKey) { pickedRule(x) }
        }
        .chartXScale(domain: chart.xDomain)
        .chartYScale(domain: chart.yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(FinanceFormat.ym(d))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel()
            }
        }
        .chartXSelection(value: $raw)
    }

    /// [v25.623] 夏月淡灰底（最底下一層；x、y 都是 Data 截好的範圍）
    @ChartContentBuilder
    private func band(_ b: UtilityTrendBand) -> some ChartContent {
        RectangleMark(xStart: .value("夏月起", b.start), xEnd: .value("夏月迄", b.end),
                      yStart: .value("下", b.yLow), yEnd: .value("上", b.yHigh))
            .foregroundStyle(UtilityPalette.summer(pal))
    }

    @ChartContentBuilder
    private func line(_ p: UtilityTrendPoint) -> some ChartContent {
        LineMark(x: .value("期", p.x), y: .value("金額", p.y), series: .value("表", p.seriesId))
            .foregroundStyle(UtilityPalette.line(p.type, pal: pal))
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.linear)
    }

    @ChartContentBuilder
    private func point(_ p: UtilityTrendPoint) -> some ChartContent {
        PointMark(x: .value("期", p.x), y: .value("金額", p.y))
            .symbol {
                UTDot(shape: p.shape, hollow: p.hollow, assigned: p.assigned,
                      tint: UtilityPalette.line(p.type, pal: pal), gray: UtilityPalette.neutral(pal),
                      lit: p.key == pickedKey, visible: p.visible)
            }
    }

    @ChartContentBuilder
    private func averageRule(_ v: Double) -> some ChartContent {
        RuleMark(y: .value("平均", v))
            .foregroundStyle(pal.label)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }

    @ChartContentBuilder
    private func pickedRule(_ x: Date) -> some ChartContent {
        RuleMark(x: .value("選", x))
            .foregroundStyle(pal.label.opacity(0.45))
            .lineStyle(StrokeStyle(lineWidth: 1))
    }
}

// MARK: - 點

/// 點：圓／三角／方 × 實心／空心；沒指定表的灰色小點；visible=false 畫 0 大小（型別不變）
fileprivate struct UTDot: View {
    let shape: UtilityTrendShape
    let hollow: Bool
    let assigned: Bool
    let tint: Color
    let gray: Color
    let lit: Bool
    let visible: Bool

    var body: some View {
        switch shape {
        case .circle: dot(Circle())
        case .triangle: dot(UTTriangle())
        case .square: dot(Rectangle())
        }
    }

    private var size: CGFloat {
        if !visible { return 0 }
        if !assigned { return 6 }
        if lit { return 11 }
        return 8
    }

    private var color: Color {
        assigned ? tint : gray
    }

    @ViewBuilder
    private func dot<S: InsettableShape>(_ s: S) -> some View {
        if hollow {
            s.strokeBorder(color, lineWidth: 1.6)
                .frame(width: size, height: size)
        } else {
            s.fill(color)
                .frame(width: size, height: size)
        }
    }
}

/// 三角形（上中、右下、左下）；strokeBorder 要 InsettableShape
fileprivate struct UTTriangle: InsettableShape {
    /// 不要叫 inset：跟 inset(by:) 同名
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> UTTriangle {
        var t = self
        t.insetAmount += amount
        return t
    }
}

// MARK: - 圖例

/// 圖例（小圖、v2 全頁共用）。一排最多 2 項，Data 先分好；VoiceOver 不唸（整張圖那句已經講了）
struct UtilityTrendLegend: View {
    let rows: [UtilityLegendRow]
    let type: UtilityType
    let pal: TripBoardPalette

    var body: some View {
        VStack(spacing: 4) {
            ForEach(rows) { r in
                HStack(spacing: 12) {
                    ForEach(r.entries) { e in
                        UTLegendItem(entry: e, type: type, pal: pal)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

/// 圖例一項：表＝同色不同點形、沒指定＝灰點、每期平均＝虛線
fileprivate struct UTLegendItem: View {
    let entry: UtilityLegendEntry
    let type: UtilityType
    let pal: TripBoardPalette

    var body: some View {
        switch entry.mark {
        case .average:
            MoneyLegendItem(mark: .dash, color: pal.label, text: entry.text, pal: pal)
        case .dot(let s):
            HStack(spacing: 5) {
                UTDot(shape: s, hollow: false, assigned: true, tint: tint, gray: gray, lit: false, visible: true)
                label
            }
        case .unassigned:
            HStack(spacing: 5) {
                UTDot(shape: .circle, hollow: false, assigned: false, tint: tint, gray: gray, lit: false, visible: true)
                label
            }
        case .summer:
            HStack(spacing: 5) {
                swatch
                label
            }
        }
    }

    /// [v25.623] 夏月那一項的小方塊（跟圖上的淡灰底同色）
    private var swatch: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(UtilityPalette.summer(pal))
            .frame(width: 12, height: 8)
    }

    private var tint: Color { UtilityPalette.line(type, pal: pal) }
    private var gray: Color { UtilityPalette.neutral(pal) }

    private var label: some View {
        Text(entry.text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(pal.label)
            .lineLimit(1)
    }
}
