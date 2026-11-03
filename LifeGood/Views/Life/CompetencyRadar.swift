import SwiftUI

// MARK: - [v25.599 職能雷達 v1a-1] 雷達元件（G2 負責；radar/judge.md §3.2、§4.3②③、§4.10、§13；radar/build/v1a-1/brief.md §4 G2）
//
// • 只照 CompetencyChartModel 畫（座標、字、狀態都在 CompetencyMath 算好）；body 裡不寫長運算式。
// • Path 畫的 Shape（好 .fill／.stroke(StrokeStyle(dash:))、ImageRenderer 畫得出來）；不用 Swift Charts、不用 Canvas 畫字。
// • 沒評、不適用的軸不畫頂點；有分數的軸少於 3 個只畫點；跳過的那一段畫虛線。v1a 不做形變動畫（新線淡入）。
// • 級數 > 11 只畫 4 圈（model.rings 已經是 4 圈）。
// 骨架（主控）：型別名與 init 參數是跨組契約，不准改；body 由 G2 換成真的。
// 座標一律在 CompetencyRadarLayout（private struct）裡用 Double 算好、明寫 CGFloat(...) 換過去；各個子 View 只排版。
// [v25.600 職能雷達 v1a-2]（radar/build/v1a-2/brief.md §4 G2 8–11）下面橫條那一列在分數後面多寫那一分的名字
// axis.levelText（「能教人」；名字跟現在不一樣寫「當時：能教人」；§13 沒名字不寫）；↑↓ 顏色照 CompetencyMath.deltaDirection。
// 檔尾 CompetencyRadarThumb 是設定預覽的小圖（主控寫的）。要退回這一版：CompetencyRadarAxisRowTitle 的 levelText 那兩行拿掉。
// [v25.601 職能雷達 v1b]（radar/build/v1b/brief.md §1-6、§4 G2 1–6；judge §3.2、§3.8）目標＝第三條線：
// • 雷達：model.hasTarget 才畫；axis.targetT 的頂點連成 .primary.opacity(0.6) 1.5pt 點線（dash [1, 3]、lineCap .round、不填色），
//   有目標的軸 < 3 只畫空心小點。ZStack 順序：格線 → 上一次 → 目標 → 這次 → 圈旁小字 → 軸名。不看 showPrevious（模型沒有目標就是不疊）。
// • 圖例多「┄ 目標 E2」（model.legendTarget）；新人沒評過、只有目標時圖例也出現（只畫目標那一段）。
// • 橫條：比例條在目標的位置一條 2pt 刻線（overlay 裡的 GeometryReader，高度固定 10）、下面一行 axis.targetText
//  「目標 3 ✓」（綠）「目標 3・差 1」「目標 3・未評」（灰）；整列 .combine 念得到。
// • 不做形變動畫、不用 accessibilityChartDescriptor（目標差已經組進 model.accessibilityText）。
// 要退回這一件：刪 CompetencyRadarTargetLayer、CompetencyRadarBarTick、layout.target、圖例 target、橫條 targetT／targetText 那幾行。

/// 人格特質紫、系統藍綠（跟執掌 (0.18,0.62,0.60) 分開）
enum CompetencyPalette {
    static let trait = Color(red: 0.55, green: 0.36, blue: 0.96)
    static let system = Color(red: 0.16, green: 0.55, blue: 0.78)

    static func tint(isTrait: Bool) -> Color { isTrait ? trait : system }
}

// MARK: - 一張卡

/// 一張雷達卡：標題「Gas System・10/30 比 4/30」＋右邊「平均 4.3」、雷達（或橫條）、圖例、下面一排橫條
/// 整張白卡（內距 16、圓角 16、細框）都在這裡畫；外距由呼叫的人加。
struct CompetencyChartCard: View {
    let model: CompetencyChartModel
    /// 疊上一次（摘要卡「疊：上一次」的開關）
    var showPrevious: Bool = true
    /// 點頂點、軸名、橫條那一列（v1a-2 才接 sheet；v1a-1 傳 nil）
    var onTapAxis: ((UUID) -> Void)? = nil

    private var isRadar: Bool { model.style == .radar || model.style == .radarShort }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CompetencyRadarCardHeader(model: model)
            if model.style == .empty {
                CompetencyRadarEmptyNote()
            } else {
                CompetencyRadarCardContent(model: model, showPrevious: showPrevious,
                                           isRadar: isRadar, onTapAxis: onTapAxis)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 1))
    }
}

/// 標題列：「人格特質・10/30 比 4/30」＋右邊「平均 4.3」（主題色）
private struct CompetencyRadarCardHeader: View {
    let model: CompetencyChartModel

    private var tint: Color { CompetencyPalette.tint(isTrait: model.isTrait) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(model.headline)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let avg = model.averageText {
                Text(avg)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }
        }
    }
}

/// 卡片中段：雷達（3～12 項）、圖例、角落小字、下面一排橫條（1～2 項、13 項以上時橫條就是圖）
private struct CompetencyRadarCardContent: View {
    let model: CompetencyChartModel
    let showPrevious: Bool
    let isRadar: Bool
    let onTapAxis: ((UUID) -> Void)?

    private var tint: Color { CompetencyPalette.tint(isTrait: model.isTrait) }
    /// 第一次評分只有「━ 4/30」；還沒評過不寫圖例
    private var legendPrevious: String? {
        (showPrevious && model.hasPrevious) ? model.legendPrevious : nil
    }
    /// [v25.601 v1b] 有這次或有目標才寫圖例
    private var showsLegend: Bool { model.legendCurrent != nil || model.legendTarget != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isRadar {
                CompetencyRadarView(model: model, showPrevious: showPrevious)
            }
            // [v25.601 v1b] 只有目標（新人沒評過）時圖例也出現。要退回這一件：條件改回 if let current = model.legendCurrent
            if showsLegend {
                CompetencyRadarLegend(current: model.legendCurrent, previous: legendPrevious,
                                      target: model.legendTarget, tint: tint)
                    .frame(maxWidth: .infinity, alignment: isRadar ? .center : .leading)
            }
            CompetencyRadarNotes(note: model.note, carriedNote: model.carriedNote)
            CompetencyRadarBars(model: model, showPrevious: showPrevious, onTapAxis: onTapAxis, showsNote: false)
        }
    }
}

/// 0 項的系統
private struct CompetencyRadarEmptyNote: View {
    var body: some View {
        Text("這一組還沒有項目，到 設定 → 職能項目 加")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 「項目少於 3 個，改用橫條」「評了 2 項，還畫不成雷達」「值班技能沿用 4/30」
private struct CompetencyRadarNotes: View {
    let note: String?
    let carriedNote: String?

    var body: some View {
        if note != nil || carriedNote != nil {
            VStack(alignment: .leading, spacing: 2) {
                if let n = note {
                    Text(n).font(.caption2).foregroundStyle(.secondary)
                }
                if let c = carriedNote {
                    Text(c).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// 圖例一行：「━ 10/30　┅ 4/30　┄ 目標 E2」（線型用 Path 畫，色弱一樣分得出）
/// [v25.601 v1b] current 可以是 nil（新人沒評過、只有目標）；target＝model.legendTarget
private struct CompetencyRadarLegend: View {
    let current: String?
    let previous: String?
    let target: String?
    let tint: Color

    private var spokenText: String {
        var s: String = ""
        if let c = current {
            s = "實線是 " + c
            if let p = previous { s += "，灰色虛線是 " + p }
        }
        if let t = target {
            s += (s.isEmpty ? "" : "，") + "點線是 " + t
        }
        return s
    }

    var body: some View {
        HStack(spacing: 6) {
            if let c = current {
                Capsule()
                    .fill(tint)
                    .frame(width: 16, height: 2)
                Text(c)
            }
            if current != nil, let p = previous {
                CompetencyRadarPolygon(points: [CGPoint(x: 0, y: 1), CGPoint(x: 16, y: 1)], closed: false)
                    .stroke(Color.gray, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    .frame(width: 16, height: 2)
                    .padding(.leading, 8)
                Text(p)
            }
            if let t = target {
                CompetencyRadarLegendTargetLine()
                    .padding(.leading, current == nil ? 0 : 8)
                Text(t)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
    }
}

/// [v25.601 v1b] 圖例裡目標那一小段點線（跟雷達的目標點線同一個 StrokeStyle）
private struct CompetencyRadarLegendTargetLine: View {
    var body: some View {
        CompetencyRadarPolygon(points: [CGPoint(x: 1, y: 1), CGPoint(x: 15, y: 1)], closed: false)
            .stroke(CompetencyRadarTargetStyle.color, style: CompetencyRadarTargetStyle.stroke)
            .frame(width: 16, height: 2)
    }
}

/// [v25.601 v1b] 目標線的顏色與線型（雷達、圖例、橫條刻線共用；brief §1-16 寫死 .primary.opacity(0.6)）
private enum CompetencyRadarTargetStyle {
    static let color: Color = Color.primary.opacity(0.6)
    static let stroke: StrokeStyle = StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [1, 3])
}

// MARK: - 雷達本體

/// 雷達本體（或 1～2 項、13 項以上的橫條）；空殼（還沒評過）也畫軸和名字
struct CompetencyRadarView: View {
    let model: CompetencyChartModel
    var showPrevious: Bool = true

    var body: some View {
        switch model.style {
        case .empty:
            CompetencyRadarEmptyNote()
        case .bars:
            CompetencyRadarBars(model: model, showPrevious: showPrevious, onTapAxis: nil, showsNote: true)
        case .radar, .radarShort:
            CompetencyRadarChart(model: model, showPrevious: showPrevious)
        }
    }
}

/// 3～12 軸的雷達：格線、上一次（灰虛線）、這次（主題色）、軸名
private struct CompetencyRadarChart: View {
    let model: CompetencyChartModel
    let showPrevious: Bool

    @State private var width: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var lineHeight: CGFloat = 16

    private var tint: Color { CompetencyPalette.tint(isTrait: model.isTrait) }
    private var fillOpacity: Double { colorScheme == .dark ? 0.35 : 0.25 }
    private var numbered: Bool { typeSize >= .accessibility1 }
    private var layout: CompetencyRadarLayout {
        CompetencyRadarLayout(model: model, width: width, lineHeight: lineHeight,
                              numbered: numbered, showPrevious: showPrevious)
    }
    private var layerId: String { model.latestDay ?? "-" }

    var body: some View {
        let lay = layout
        ZStack {
            CompetencyRadarGridLayer(layout: lay)
            CompetencyRadarPreviousLayer(points: lay.previous)
            // [v25.601 v1b] 目標點線（上一次之上、這次之下）。要退回這一件：刪這一行
            CompetencyRadarTargetLayer(points: lay.target)
            CompetencyRadarCurrentLayer(layout: lay, tint: tint, fillOpacity: fillOpacity,
                                        drawsPolygon: model.drawsPolygon)
                .id(layerId)
                .transition(.opacity)
            CompetencyRadarRingLabelLayer(labels: lay.ringLabels)
            CompetencyRadarLabelLayer(labels: lay.labels)
        }
        .frame(maxWidth: .infinity)
        .frame(height: lay.height)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { w in
            if abs(w - width) > 0.5 { width = w }
        }
        .animation(.easeInOut(duration: 0.25), value: model.latestDay)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityText)
    }
}

/// 格線：同心多邊形（faint 的淡一點）＋放射線（小洞邊到外圈）
private struct CompetencyRadarGridLayer: View {
    let layout: CompetencyRadarLayout

    var body: some View {
        ZStack {
            CompetencyRadarSegments(segments: layout.spokes)
                .stroke(Color(.separator), lineWidth: 0.5)
            CompetencyRadarGrid(rings: layout.faintRings)
                .stroke(Color(.separator).opacity(0.4), lineWidth: 0.75)
            CompetencyRadarGrid(rings: layout.strongRings)
                .stroke(Color(.separator), lineWidth: 1)
        }
    }
}

/// 圈旁小字（寫在第一軸右邊一點）；疊在這次的填色上面，才不會被蓋住
private struct CompetencyRadarRingLabelLayer: View {
    let labels: [CompetencyRadarRingLabel]

    var body: some View {
        ZStack {
            ForEach(labels) { lb in
                Text(lb.text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: CompetencyRadarLayout.ringLabelWidth, alignment: .leading)
                    .position(lb.center)
            }
        }
    }
}

/// 上一次：灰 1.5pt 虛線、不填色；頂點 < 3 只畫小灰點
private struct CompetencyRadarPreviousLayer: View {
    let points: [CGPoint]

    var body: some View {
        if points.count >= 3 {
            CompetencyRadarPolygon(points: points, closed: true)
                .stroke(Color.gray, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        } else if !points.isEmpty {
            CompetencyRadarDots(points: points, diameter: 4)
                .fill(Color.gray)
        }
    }
}

/// [v25.601 v1b] 目標：.primary 0.6、1.5pt 點線（dash [1, 3]、圓頭）、不填色；有目標的軸 < 3 只畫空心小點
private struct CompetencyRadarTargetLayer: View {
    let points: [CGPoint]

    var body: some View {
        if points.count >= 3 {
            CompetencyRadarPolygon(points: points, closed: true)
                .stroke(CompetencyRadarTargetStyle.color, style: CompetencyRadarTargetStyle.stroke)
        } else if !points.isEmpty {
            CompetencyRadarDots(points: points, diameter: 5)
                .stroke(CompetencyRadarTargetStyle.color, lineWidth: 1)
        }
    }
}

/// 這次：填色＋實線邊（跳過沒評的那段畫虛線）＋頂點實心圓點；有分數的軸少於 3 個只畫點
private struct CompetencyRadarCurrentLayer: View {
    let layout: CompetencyRadarLayout
    let tint: Color
    let fillOpacity: Double
    let drawsPolygon: Bool

    var body: some View {
        ZStack {
            if drawsPolygon {
                CompetencyRadarPolygon(points: layout.current, closed: true)
                    .fill(tint.opacity(fillOpacity))
                CompetencyRadarSegments(segments: layout.solidEdges)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                CompetencyRadarSegments(segments: layout.dashedEdges)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            }
            CompetencyRadarDots(points: layout.current, diameter: 6)
                .fill(tint)
        }
    }
}

/// 軸名（一般 Text，吃得到動態字級）；位置、寬、對齊都在 layout 算好
private struct CompetencyRadarLabelLayer: View {
    let labels: [CompetencyRadarLabelSpot]

    var body: some View {
        ZStack {
            ForEach(labels) { spot in
                CompetencyRadarAxisLabel(spot: spot)
                    .frame(width: spot.width, height: spot.height, alignment: spot.frameAlignment)
                    .position(spot.center)
            }
        }
    }
}

/// 一根軸的名字＋（沒評、不適用時）灰字「未評」／「不適用」
private struct CompetencyRadarAxisLabel: View {
    let spot: CompetencyRadarLabelSpot

    var body: some View {
        VStack(alignment: spot.stackAlignment, spacing: 0) {
            Text(spot.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(spot.textAlignment)
            if let s = spot.status {
                Text(s)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - 下面一排橫條（每一軸一列；1～2 項、13 項以上時這就是圖）

/// 每項一列：名字、分數、↑↓、沿用日子、換算前的分數；一條比例條＋上一次淡色短條
struct CompetencyRadarBars: View {
    let model: CompetencyChartModel
    var showPrevious: Bool = true
    var onTapAxis: ((UUID) -> Void)? = nil
    /// 獨立用（CompetencyRadarView 的 .bars）時把 model.note 寫在上面；卡片裡由卡片寫
    var showsNote: Bool = true

    @Environment(\.dynamicTypeSize) private var typeSize

    private var tint: Color { CompetencyPalette.tint(isTrait: model.isTrait) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsNote, let note = model.note {
                Text(note).font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(model.axes.indices, id: \.self) { i in
                rowView(i)
            }
        }
    }

    /// 9～12 項（軸上寫短名或 ①）、字放大（軸上寫 ①）時，列前面多寫軸上那個字當對照
    private func prefix(_ i: Int) -> String? {
        let isRadar: Bool = model.style == .radar || model.style == .radarShort
        guard isRadar else { return nil }
        if typeSize >= .accessibility1 {
            return i < CompetencyMath.circledNumbers.count ? CompetencyMath.circledNumbers[i] : "\(i + 1)"
        }
        let axis: CompetencyAxisModel = model.axes[i]
        return axis.label != axis.name ? axis.label : nil
    }

    @ViewBuilder
    private func rowView(_ i: Int) -> some View {
        let axis: CompetencyAxisModel = model.axes[i]
        if let tap = onTapAxis {
            Button {
                tap(axis.id)
            } label: {
                CompetencyRadarAxisRow(axis: axis, tint: tint, showPrevious: showPrevious, prefix: prefix(i))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            CompetencyRadarAxisRow(axis: axis, tint: tint, showPrevious: showPrevious, prefix: prefix(i))
        }
    }
}

/// 一軸一列（VoiceOver 一列念一次）
struct CompetencyRadarAxisRow: View {
    let axis: CompetencyAxisModel
    let tint: Color
    var showPrevious: Bool = true
    /// 軸上寫的短名或 ①（對照用；沒有 nil）
    var prefix: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CompetencyRadarAxisRowTitle(axis: axis, prefix: prefix)
            CompetencyRadarAxisRowBar(t: axis.t, previousT: showPrevious ? axis.previousT : nil,
                                      targetT: axis.targetT, tint: tint)
            if let o = axis.originalText {
                Text(o).font(.caption2).foregroundStyle(.secondary)
            }
            // [v25.601 v1b]「目標 3 ✓」「目標 3・差 1」「目標 3・未評」（不適用、沒有目標 nil）。要退回這一件：刪這三行
            if let tx = axis.targetText {
                Text(tx).font(.caption2).foregroundStyle(targetColor)
                    .accessibilityLabel(targetSpoken)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// [v25.601 v1b] 達標綠、其他灰
    private var targetColor: Color { axis.targetMet == true ? Color.green : Color.secondary }
    /// [v25.601 v1b 審查修] VoiceOver 不念「✓」的符號名稱：「目標 3，達標」（跟雷達那一句一樣）
    private var targetSpoken: String { (axis.targetText ?? "").replacingOccurrences(of: " ✓", with: "，達標") }
}

/// 「緊急應變　4　能教人　↑2（4/30）」；沒評「未評」、不適用「不適用」（灰）
private struct CompetencyRadarAxisRowTitle: View {
    let axis: CompetencyAxisModel
    let prefix: String?

    private var isRated: Bool { axis.state == .rated }
    private var valueText: String {
        switch axis.state {
        case .rated: return axis.valueText ?? ""
        case .unrated: return "未評"
        case .na: return "不適用"
        }
    }
    private var valueFont: Font {
        isRated ? Font.footnote.weight(.semibold).monospacedDigit() : Font.caption
    }
    /// [v25.600 v1a-2] 方向照 CompetencyMath.deltaDirection（1 綠、−1 橘、0 灰；跟〔職能〕分頁同一支）
    private var deltaColor: Color {
        switch CompetencyMath.deltaDirection(axis.deltaText) {
        case 1: return Color.green
        case -1: return Color.orange
        default: return Color.secondary
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let p = prefix {
                Text(p).font(.footnote).foregroundStyle(.secondary)
            }
            Text(axis.name)
                .font(.footnote)
                .foregroundStyle(isRated ? Color.primary : Color.secondary)
                .lineLimit(2)
            if axis.archived {
                Text("已停用").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(valueText)
                .font(valueFont)
                .foregroundStyle(isRated ? Color.primary : Color.secondary)
            // [v25.600 v1a-2] 那一分的名字「能教人」「當時：能教人」（§13：有名字才寫）
            if let lt = axis.levelText {
                Text(lt).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            if let d = axis.deltaText {
                Text(d).font(.caption.weight(.semibold)).foregroundStyle(deltaColor)
            }
            if let c = axis.carriedFrom {
                Text("（" + c + "）").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// 細比例條（這次，主題色）＋上一次淡色短條（灰）。長度＝比例 t（brief §4 G2：橫條看準確數字）
/// [v25.601 v1b] targetT 有就在比例條上畫一條目標刻線（高 10，比例條在中間）
private struct CompetencyRadarAxisRowBar: View {
    let t: Double?
    let previousT: Double?
    var targetT: Double? = nil
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                if let t = t {
                    CompetencyRadarBarFill(fraction: t)
                        .fill(tint)
                }
            }
            .frame(height: 6)
            .frame(height: targetT == nil ? 6 : 10)
            .overlay(alignment: .leading) {
                CompetencyRadarBarTick(fraction: targetT)
            }
            if let p = previousT {
                CompetencyRadarBarFill(fraction: p)
                    .fill(Color.gray.opacity(0.45))
                    .frame(height: 3)
            }
        }
        .accessibilityHidden(true)
    }
}

/// [v25.601 v1b] 目標刻線：2pt 寬、10pt 高，中心在比例 fraction（夾在條內）；nil 不畫。
/// GeometryReader 只在 overlay 裡（大小＝比例條那一塊），不會撐開版面
private struct CompetencyRadarBarTick: View {
    let fraction: Double?

    var body: some View {
        if let f = fraction {
            GeometryReader { g in
                Rectangle()
                    .fill(CompetencyRadarTargetStyle.color)
                    .frame(width: 2, height: 10)
                    .offset(x: Self.offsetX(width: g.size.width, fraction: f))
            }
        }
    }

    /// 刻線左緣的 x：中心對準 width×fraction，夾在 0…width−2
    static func offsetX(width: CGFloat, fraction: Double) -> CGFloat {
        let f: CGFloat = CGFloat(min(max(fraction, 0), 1))
        let x: CGFloat = width * f - 1
        return min(max(x, 0), max(width - 2, 0))
    }
}

// MARK: - Shape（Path 畫；座標是整塊圖的絕對座標，path(in:) 不看 rect）

/// 一條線段（放射線、多邊形的邊）
struct CompetencyRadarSegment: Equatable {
    let from: CGPoint
    let to: CGPoint
}

/// 多邊形（closed＝true 收口；填色、上一次虛線、圖例線型都用這個）
struct CompetencyRadarPolygon: Shape {
    let points: [CGPoint]
    var closed: Bool = true

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for pt in points.dropFirst() {
            p.addLine(to: pt)
        }
        if closed && points.count > 2 {
            p.closeSubpath()
        }
        return p
    }
}

/// 一組同心多邊形（格線）
struct CompetencyRadarGrid: Shape {
    let rings: [[CGPoint]]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for ring in rings {
            guard let first = ring.first else { continue }
            p.move(to: first)
            for pt in ring.dropFirst() {
                p.addLine(to: pt)
            }
            p.closeSubpath()
        }
        return p
    }
}

/// 一組各自獨立的線段（放射線、多邊形的邊；實線虛線分兩組畫）
struct CompetencyRadarSegments: Shape {
    let segments: [CompetencyRadarSegment]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for s in segments {
            p.move(to: s.from)
            p.addLine(to: s.to)
        }
        return p
    }
}

/// 一組實心圓點（頂點）
struct CompetencyRadarDots: Shape {
    let points: [CGPoint]
    let diameter: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let half: CGFloat = diameter / 2
        for pt in points {
            p.addEllipse(in: CGRect(x: pt.x - half, y: pt.y - half, width: diameter, height: diameter))
        }
        return p
    }
}

/// 橫條：從左邊畫到 fraction（0…1）。最低分（t＝0）至少畫成一個圓點（寬＝條高），
/// 才不會跟「未評」一樣空著（judge §3.2：最低分不會縮成沒有）；圓角夾在寬高一半以內，寬 0 不畫。
struct CompetencyRadarBarFill: Shape {
    let fraction: Double

    func path(in rect: CGRect) -> Path {
        let f: CGFloat = CGFloat(min(max(fraction, 0), 1))
        let w: CGFloat = min(max(rect.width * f, rect.height), rect.width)
        guard w > 0, rect.height > 0 else { return Path() }
        let bar = CGRect(x: rect.minX, y: rect.minY, width: w, height: rect.height)
        let corner: CGFloat = min(w, rect.height) / 2
        return Path(roundedRect: bar, cornerRadius: corner)
    }
}

// MARK: - 座標（只在這個檔；純計算，數字全部來自 CompetencyMath）

/// 圈旁小字
private struct CompetencyRadarRingLabel: Identifiable {
    let id: Int
    let text: String
    let center: CGPoint
}

/// 一根軸的標籤放哪裡：框的中心、寬高、框內對齊
private struct CompetencyRadarLabelSpot: Identifiable {
    let id: Int
    let text: String
    /// 「未評」「不適用」；有分數或空殼 nil
    let status: String?
    /// 1 靠左（往右長）／−1 靠右／0 置中（CompetencyMath.labelAlignment）
    let align: Int
    /// 正上方那根：框底貼著 R＋8
    let isTop: Bool
    /// 正下方那根：框頂貼著 R＋8
    let isBottom: Bool
    let width: CGFloat
    let height: CGFloat
    let center: CGPoint

    var frameAlignment: Alignment {
        if isTop { return .bottom }
        if isBottom { return .top }
        if align > 0 { return .leading }
        if align < 0 { return .trailing }
        return .center
    }
    var stackAlignment: HorizontalAlignment {
        if align > 0 { return .leading }
        if align < 0 { return .trailing }
        return .center
    }
    var textAlignment: TextAlignment {
        if align > 0 { return .leading }
        if align < 0 { return .trailing }
        return .center
    }
}

/// 整張雷達的座標（圓心不在正中：奇數軸照頂點上下範圍置中，框高＝多邊形上下範圍＋上下標籤）
private struct CompetencyRadarLayout {
    static let ringLabelWidth: CGFloat = 40
    /// 寬度還沒量到時先用 300
    static let fallbackWidth: Double = 300

    var height: CGFloat = 0
    var strongRings: [[CGPoint]] = []
    var faintRings: [[CGPoint]] = []
    var spokes: [CompetencyRadarSegment] = []
    var ringLabels: [CompetencyRadarRingLabel] = []
    /// 這次有分數的頂點（沒評、不適用跳過）
    var current: [CGPoint] = []
    var solidEdges: [CompetencyRadarSegment] = []
    var dashedEdges: [CompetencyRadarSegment] = []
    /// 上一次有分數的頂點（不疊時空）
    var previous: [CGPoint] = []
    /// [v25.601 v1b] 有目標的軸的頂點（模型沒有目標時空）
    var target: [CGPoint] = []
    var labels: [CompetencyRadarLabelSpot] = []

    init(model: CompetencyChartModel, width: CGFloat, lineHeight: CGFloat, numbered: Bool, showPrevious: Bool) {
        let w: Double = width > 1 ? Double(width) : Self.fallbackWidth
        let r: Double = max(CompetencyMath.radarRadius(cardWidth: w), 40)
        let n: Int = model.axes.count
        let lh: Double = Double(lineHeight)
        let ext: (up: Double, down: Double) = CompetencyMath.verticalExtent(count: n)
        let widths: [Double] = CompetencyMath.labelWidths(cardWidth: w, radius: r, count: n)

        // 1. 標籤框（相對圓心），順便量出整張圖的上下範圍
        var minY: Double = -r * ext.up
        var maxY: Double = r * ext.down
        var boxes: [CompetencyRadarLabelBox] = []
        for i in 0..<n {
            let lw: Double = i < widths.count ? max(widths[i], 24) : 24
            let box = Self.labelBox(model: model, index: i, count: n, radius: r, labelWidth: lw,
                                    lineHeight: lh, numbered: numbered)
            minY = min(minY, box.top)
            maxY = max(maxY, box.top + box.height)
            boxes.append(box)
        }
        minY -= 2
        maxY += 2
        let cx: Double = w / 2
        let cy: Double = -minY
        height = CGFloat(maxY - minY)

        func cg(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: CGFloat(cx + x), y: CGFloat(cy + y))
        }

        // 2. 格線、放射線、圈旁小字（寫在第一軸＝正上方右邊一點）
        for (k, ring) in model.rings.enumerated() {
            var pts: [CGPoint] = []
            for i in 0..<n {
                let p: RadarPoint = CompetencyMath.ringPoint(t: ring.t, index: i, count: n, radius: r)
                pts.append(cg(p.x, p.y))
            }
            if ring.faint { faintRings.append(pts) } else { strongRings.append(pts) }
            if let text = ring.label {
                let top: RadarPoint = CompetencyMath.ringPoint(t: ring.t, index: 0, count: n, radius: r)
                let x: Double = 4 + Double(Self.ringLabelWidth) / 2
                ringLabels.append(CompetencyRadarRingLabel(id: k, text: text, center: cg(x, top.y)))
            }
        }
        for i in 0..<n {
            let inner: RadarPoint = CompetencyMath.ringPoint(t: 0, index: i, count: n, radius: r)
            let outer: RadarPoint = CompetencyMath.ringPoint(t: 1, index: i, count: n, radius: r)
            spokes.append(CompetencyRadarSegment(from: cg(inner.x, inner.y), to: cg(outer.x, outer.y)))
        }

        // 3. 這次：只有有分數的軸有頂點；邊照 CompetencyMath.edges（skipped → 虛線）
        let ts: [Double?] = model.axes.map { $0.t }
        let verts: [RadarVertex] = CompetencyMath.vertices(ts, radius: r)
        current = verts.map { cg($0.x, $0.y) }
        if model.drawsPolygon {
            for e in CompetencyMath.edges(verts, count: n) {
                guard e.from < current.count, e.to < current.count else { continue }
                let seg = CompetencyRadarSegment(from: current[e.from], to: current[e.to])
                if e.skipped { dashedEdges.append(seg) } else { solidEdges.append(seg) }
            }
        }

        // 4. 上一次
        if showPrevious && model.hasPrevious {
            let pts: [Double?] = model.axes.map { $0.previousT }
            previous = CompetencyMath.vertices(pts, radius: r).map { cg($0.x, $0.y) }
        }

        // 4b. [v25.601 v1b] 目標（不看 showPrevious：模型裡沒有目標就是不疊）
        if model.hasTarget {
            let tts: [Double?] = model.axes.map { $0.targetT }
            target = CompetencyMath.vertices(tts, radius: r).map { cg($0.x, $0.y) }
        }

        // 5. 標籤換成絕對座標
        labels = boxes.map { b in
            CompetencyRadarLabelSpot(id: b.index, text: b.text, status: b.status, align: b.align,
                                     isTop: b.isTop, isBottom: b.isBottom,
                                     width: CGFloat(b.width), height: CGFloat(b.height),
                                     center: cg(b.centerX, b.top + b.height / 2))
        }
    }

    /// 一根軸的標籤框（相對圓心）：放在 R＋8；靠左的框左緣貼著那一點、靠右的右緣貼著、正上正下的框底／框頂貼著
    private static func labelBox(model: CompetencyChartModel, index i: Int, count n: Int, radius r: Double,
                                 labelWidth lw: Double, lineHeight lh: Double, numbered: Bool) -> CompetencyRadarLabelBox {
        let axis: CompetencyAxisModel = model.axes[i]
        let anchor: RadarPoint = CompetencyMath.point(t: 1, index: i, count: n, radius: r + 8)
        let align: Int = CompetencyMath.labelAlignment(i, n)
        let status: String? = statusText(axis.state, neverRated: model.neverRated)
        let lines: Double = status == nil ? 2 : 3
        let h: Double = lh * lines
        let isTop: Bool = align == 0 && anchor.y < 0
        let isBottom: Bool = align == 0 && anchor.y > 0
        let top: Double
        if isTop {
            top = anchor.y - h
        } else if isBottom {
            top = anchor.y
        } else {
            top = anchor.y - h / 2
        }
        let centerX: Double
        if align > 0 {
            centerX = anchor.x + lw / 2
        } else if align < 0 {
            centerX = anchor.x - lw / 2
        } else {
            centerX = anchor.x
        }
        let text: String = labelText(axis, index: i, numbered: numbered)
        return CompetencyRadarLabelBox(index: i, text: text, status: status, align: align, isTop: isTop,
                                       isBottom: isBottom, width: lw, height: h, top: top, centerX: centerX)
    }

    /// 字放大（≥ accessibility1）軸上只寫 ①②③（下面橫條照常寫全名）
    private static func labelText(_ axis: CompetencyAxisModel, index i: Int, numbered: Bool) -> String {
        guard numbered else { return axis.label }
        let nums: [String] = CompetencyMath.circledNumbers
        return i < nums.count ? nums[i] : "\(i + 1)"
    }

    /// 空殼（一格都沒評過）只寫軸名，不寫「未評」
    private static func statusText(_ state: CompetencyAxisState, neverRated: Bool) -> String? {
        guard !neverRated else { return nil }
        switch state {
        case .rated: return nil
        case .unrated: return "未評"
        case .na: return "不適用"
        }
    }
}

/// 標籤框（相對圓心，Double）
private struct CompetencyRadarLabelBox {
    let index: Int
    let text: String
    let status: String?
    let align: Int
    let isTop: Bool
    let isBottom: Bool
    let width: Double
    let height: Double
    let top: Double
    let centerX: Double
}

// MARK: - [v25.600 職能雷達 v1a-2] 設定預覽的空殼小雷達（主控先寫好能用的；G2 可以調樣子，型別名與 init 參數不准改）

/// 設定「預覽」一格的小圖：3～12 項畫空殼多邊形（12 點鐘起順時針）、1～2 項與 13 項以上畫三條橫條、0 項畫虛線圓
struct CompetencyRadarThumb: View {
    let axisCount: Int
    let tint: Color

    private var style: CompetencyChartStyle { CompetencyMath.chartStyle(axisCount: axisCount) }

    var body: some View {
        ZStack {
            switch style {
            case .empty:
                Circle()
                    .stroke(Color(.separator), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            case .bars:
                CompetencyRadarThumbBars()
                    .fill(tint.opacity(0.55))
            case .radar, .radarShort:
                CompetencyRadarThumbShape(sides: axisCount)
                    .fill(tint.opacity(0.12))
                CompetencyRadarThumbShape(sides: axisCount)
                    .stroke(tint, lineWidth: 1.2)
            }
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }
}

/// 正 n 邊形（頂點在 12 點鐘、順時針；角度照 CompetencyMath.angle）
struct CompetencyRadarThumbShape: Shape {
    let sides: Int

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let n: Int = max(sides, 3)
        let r: Double = Double(min(rect.width, rect.height)) / 2
        let cx: Double = Double(rect.midX)
        let cy: Double = Double(rect.midY)
        for i in 0..<n {
            let a: Double = CompetencyMath.angle(i, n)
            let pt = CGPoint(x: CGFloat(cx + r * cos(a)), y: CGFloat(cy + r * sin(a)))
            if i == 0 {
                p.move(to: pt)
            } else {
                p.addLine(to: pt)
            }
        }
        p.closeSubpath()
        return p
    }
}

/// 三條長短不一的橫條（1～2 項、13 項以上「改用橫條」）
struct CompetencyRadarThumbBars: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let h: CGFloat = rect.height / 7
        let widths: [CGFloat] = [0.9, 0.65, 0.8]
        for (i, w) in widths.enumerated() {
            let y: CGFloat = rect.minY + h * CGFloat(1 + i * 2)
            let r = CGRect(x: rect.minX, y: y, width: rect.width * w, height: h)
            p.addRoundedRect(in: r, cornerSize: CGSize(width: h / 2, height: h / 2))
        }
        return p
    }
}
