import SwiftUI

// MARK: - 收支五頁共用的看板零件（v25.522，v25.523 重做）
//
// 使用者：「變動支出，固定支出，固定收入，總覽，圖表，這些幫我完整規劃，看板跟項目，
// 我想要跟旅遊項目一樣有設計感」。
//
// 視覺語言跟行程看板（Life/TripSummaryBoard.swift）同一套：淡色漸層的看板底、白色毛玻璃格子、
// 彩色圖示圓。配色、格子外框、圖示圓直接用行程看板的
// （TripBoardPalette／TripBoardCellChrome／TripBoardIconBadge），不另調一套。
//
// [v25.523] 第一版（v25.522）使用者說「質感差很多，這個好亂」。檢討：
// - 格子一列三個太窄，金額又長，右下角的迷你圖直接壓在數字上；
// - 每格塞五樣東西（圖示、標籤、箭頭、大字、補充、迷你圖），補充字又各有顏色；
// - 箭頭有的格子有、有的沒有。
// 這一版的規矩：
// - 格子一列兩個；一格只有「圖示＋標籤、大字、一行補充」，不放迷你圖、不放箭頭
//   （可以按的格子按下去會縮一下）。
// - 補充那一行是灰字，只有「變化」那幾個字上色（↑136% 橘、↓8% 綠）。
// - 圖只畫一張、畫大、畫在自己的格子裡（MoneySpendChart），不跟字疊在一起。
// - 要讀的數字一律是 Text；Canvas 只畫「看得到、不給讀」的圖。

enum MoneyFormat {
    /// 看板上的金額：一萬以上用「萬」、一億以上用「億」，一萬以下寫完整（NT$1,234）。
    /// 走全 App 共用的 ntdWanString，同一個數字在每一頁長得一樣。
    static func short(_ v: Double) -> String { v.ntdWanString }

    static func percent(_ r: Double) -> String {
        "\(Int((r * 100).rounded()))%"
    }

    /// 「↑12%」「↓8%」；差不到 1% 就說「持平」
    static func change(_ now: Double, vs before: Double) -> String? {
        guard before > 0 else { return nil }
        let r = now / before - 1
        if abs(r) < 0.01 { return "持平" }
        return (r > 0 ? "↑" : "↓") + percent(abs(r))
    }
}

/// 好、注意、超過——三種狀態的字色（淺色 4.5:1 以上；深色同色相調亮）
enum MoneyTone {
    case good, warn, bad, neutral

    func color(_ pal: TripBoardPalette) -> Color {
        switch self {
        case .good: return pal.dark ? Color(tb: 0x5BD99A) : Color(tb: 0x177A44)
        case .warn: return pal.dark ? Color(tb: 0xFFC14D) : Color(tb: 0xA65300)
        case .bad: return pal.dark ? Color(tb: 0xFF7A8A) : Color(tb: 0xC4243C)
        case .neutral: return pal.label
        }
    }

    /// 花得比較多是「注意」、比較少是「好」；差不到 5% 不上色
    static func spendingChange(_ now: Double, vs before: Double) -> MoneyTone {
        guard before > 0 else { return .neutral }
        if now > before * 1.05 { return .warn }
        if now < before * 0.95 { return .good }
        return .neutral
    }
}

/// 固定支出在收支看板上一律是紫色（圖例、圖上的底、「未來 7 天要扣」的圖示圓）
enum MoneyInk {
    static func fixed(_ pal: TripBoardPalette) -> Color {
        pal.dark ? Color(tb: 0xA98BFF) : Color(tb: 0x8B5CF6)
    }

    static func fixedBand(_ pal: TripBoardPalette) -> Color {
        Color(tb: 0x8B5CF6, pal.dark ? 0.22 : 0.10)
    }
}

/// 可以按的格子：按下去縮一下、淡一點（取代原本的小箭頭）
struct MoneyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - 格子

/// 看板上的一格：圖示圓＋標籤、大字、一行補充。
///
/// 補充那一行是灰字；accent 是要上色的那一小段（例如「↑136%」），接在補充後面。
struct MoneyTile: View {
    let icon: String
    let tint: TripBoardTint
    let label: String
    let value: String
    var valueTone: MoneyTone? = nil
    var detail: String? = nil
    var accent: String? = nil
    var accentTone: MoneyTone = .neutral
    var action: (() -> Void)? = nil
    var actionHint: String? = nil
    let pal: TripBoardPalette

    var body: some View {
        if let action {
            Button(action: action) {
                content
                    .contentShape(Rectangle())
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityHint(actionHint ?? "")
        } else {
            content
        }
    }

    private var a11y: String {
        var s = label + "，" + value
        if let detail { s += "，" + detail }
        if let accent { s += " " + accent }
        return s
    }

    private var detailText: Text {
        let base = detail ?? ""
        guard let accent else { return Text(base) }
        let colored = Text(accent).foregroundStyle(accentTone.color(pal))
        return base.isEmpty ? colored : Text("\(base) \(colored)")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                TripBoardIconBadge(icon: icon, colors: pal.badge(tint), diameter: 24, dark: pal.dark)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(pal.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(valueTone?.color(pal) ?? pal.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 7)
            if detail != nil || accent != nil {
                detailText
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(pal.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(TripBoardCellChrome(pal: pal))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
    }
}

/// 一列兩格，同一列一樣高；單數時最後一格旁邊留空。
struct MoneyTileGrid: View {
    let tiles: [AnyView]

    var body: some View {
        let rows = stride(from: 0, to: tiles.count, by: 2).map { i in
            Array(tiles[i..<min(i + 2, tiles.count)])
        }
        VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, t in
                        t
                    }
                    if row.count < 2 {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 圖例

struct MoneyLegendItem: View {
    enum Mark { case swatch, dash }

    let mark: Mark
    let color: Color
    let text: String
    let pal: TripBoardPalette

    var body: some View {
        HStack(spacing: 5) {
            switch mark {
            case .swatch:
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 8, height: 8)
            case .dash:
                Path { p in
                    p.move(to: CGPoint(x: 1, y: 1))
                    p.addLine(to: CGPoint(x: 11, y: 1))
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 3]))
                .frame(width: 12, height: 2)
            }
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(pal.label)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

// MARK: - 本月支出走勢圖

/// 這個月的支出一路累計上去的樣子：
/// - 底下一條淡紫色的帶子＝固定支出（月初就整筆算進來，所以線不是從 0 開始）；
/// - 實線＋淡淡的面積＝固定＋每天累計的變動支出，畫到今天，今天是一個點；
/// - 虛線＝照平常的花法，到月底會到哪裡；
/// - 一條橫線＝收入（花到這條線就是把這個月的收入花完了）。
/// 看得到、不給讀：金額一律寫在圖下面的 Text 裡（圖例、結論那一行）。
struct MoneySpendChart: View, Equatable {
    let month: Int
    let daysInMonth: Int
    /// 今天是幾號（1 起算）
    let day: Int
    let fixed: Double
    /// 1 號到今天，每天累計的變動支出
    let cumulative: [Double]
    let projected: Double?
    /// 收入（橫線）；沒有收入紀錄是 nil
    let ceiling: Double?
    let ceilingLabel: String?
    let line: Color
    let projection: Color
    let band: Color
    let rule: Color
    let label: Color
    /// 今天那個點的外圈（跟格子底色一樣，點才會「浮」在線上）
    let halo: Color

    var body: some View {
        Canvas { ctx, size in
            let days = max(daysInMonth, 2)
            let left: CGFloat = 4
            let right = size.width - 4
            let top: CGFloat = 16
            let bottom = size.height - 16
            let spent = fixed + (cumulative.last ?? 0)
            let maxV = max(ceiling ?? 0, projected ?? 0, spent, 1) * 1.08
            func x(_ d: Int) -> CGFloat {
                left + CGFloat(d - 1) / CGFloat(days - 1) * (right - left)
            }
            func y(_ v: Double) -> CGFloat {
                bottom - CGFloat(v / maxV) * (bottom - top)
            }

            // 固定支出的底
            if fixed > 0 {
                ctx.fill(Path(CGRect(x: left, y: y(fixed), width: right - left, height: bottom - y(fixed))),
                         with: .color(band))
            }

            // 底線
            var base = Path()
            base.move(to: CGPoint(x: left, y: bottom))
            base.addLine(to: CGPoint(x: right, y: bottom))
            ctx.stroke(base, with: .color(rule.opacity(0.6)), lineWidth: 0.5)

            // 收入那條線
            if let ceiling, ceiling > 0 {
                let cy = y(ceiling)
                var r = Path()
                r.move(to: CGPoint(x: left, y: cy))
                r.addLine(to: CGPoint(x: right, y: cy))
                ctx.stroke(r, with: .color(rule), lineWidth: 1)
                if let ceilingLabel {
                    let t = ctx.resolve(Text(ceilingLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(label))
                    // 上面放不下就放線下面
                    if cy - 14 >= 0 {
                        ctx.draw(t, at: CGPoint(x: left, y: cy - 3), anchor: .bottomLeading)
                    } else {
                        ctx.draw(t, at: CGPoint(x: left, y: cy + 3), anchor: .topLeading)
                    }
                }
            }

            let points: [CGPoint] = cumulative.enumerated().map { i, v in
                CGPoint(x: x(i + 1), y: y(fixed + v))
            }

            // 面積＋實線
            if points.count >= 2 {
                var area = Path()
                area.move(to: CGPoint(x: points[0].x, y: y(fixed)))
                for p in points { area.addLine(to: p) }
                area.addLine(to: CGPoint(x: points[points.count - 1].x, y: y(fixed)))
                area.closeSubpath()
                let highest = points.map(\.y).min() ?? top
                ctx.fill(area, with: .linearGradient(
                    Gradient(colors: [line.opacity(0.28), line.opacity(0.04)]),
                    startPoint: CGPoint(x: 0, y: highest), endPoint: CGPoint(x: 0, y: y(fixed))))

                var path = Path()
                path.move(to: points[0])
                for p in points.dropFirst() { path.addLine(to: p) }
                ctx.stroke(path, with: .color(line),
                           style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }

            // 月底預估（虛線）
            if let last = points.last, let projected, day < daysInMonth {
                let end = CGPoint(x: x(days), y: y(projected))
                var dash = Path()
                dash.move(to: last)
                dash.addLine(to: end)
                ctx.stroke(dash, with: .color(projection.opacity(0.6)),
                           style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [3, 4]))
                ctx.fill(Path(ellipseIn: CGRect(x: end.x - 2.5, y: end.y - 2.5, width: 5, height: 5)),
                         with: .color(projection.opacity(0.6)))
            }

            // 今天
            if let last = points.last {
                ctx.fill(Path(ellipseIn: CGRect(x: last.x - 6, y: last.y - 6, width: 12, height: 12)),
                         with: .color(line.opacity(0.18)))
                let dot = Path(ellipseIn: CGRect(x: last.x - 3.2, y: last.y - 3.2, width: 6.4, height: 6.4))
                ctx.fill(dot, with: .color(line))
                ctx.stroke(dot, with: .color(halo), lineWidth: 1.5)
            }

            // 日期
            let mid = (days + 1) / 2
            let marks: [(Int, UnitPoint)] = [(1, .bottomLeading), (mid, .bottom), (days, .bottomTrailing)]
            for (d, anchor) in marks {
                let t = ctx.resolve(Text("\(month)/\(d)")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(label))
                ctx.draw(t, at: CGPoint(x: x(d), y: size.height), anchor: anchor)
            }
        }
    }
}

// MARK: - 看板外框

/// 看板的底：跟行程看板同一個淡色漸層、同一個外框與陰影；圓角讀英雄卡設定的「圓角」。
struct MoneyBoardChrome: ViewModifier {
    let pal: TripBoardPalette
    let corner: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return content
            .background {
                shape.fill(LinearGradient(colors: [pal.boardTop, pal.boardBottom],
                                          startPoint: .top, endPoint: .bottom))
            }
            .clipShape(shape)
            .overlay { shape.stroke(pal.cardStroke, lineWidth: 0.75) }
            .shadow(color: pal.cardShadow, radius: 14, x: 0, y: 6)
    }
}
