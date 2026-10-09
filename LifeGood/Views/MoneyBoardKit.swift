import SwiftUI

// MARK: - 收支五頁共用的看板零件（v25.522）
//
// 使用者：「變動支出，固定支出，固定收入，總覽，圖表，這些幫我完整規劃，看板跟項目，
// 我想要跟旅遊項目一樣有設計感」、「你幫我規劃完整的 KPI 對於使用者會想看的」。
//
// 視覺語言跟行程看板（Life/TripSummaryBoard.swift）同一套：淡色漸層的看板底、上面一小片
// 跟資料有關的插畫、白色毛玻璃格子（彩色圖示圓＋大數字＋小標籤＋右下角淡淡的迷你圖）、
// 進度比較卡、膠囊、提醒列。配色、格子外框、圖示圓直接用行程看板的
// （TripBoardPalette／TripBoardCellChrome／TripBoardIconBadge）——同一個 App 裡的兩塊看板
// 不該各調一套顏色，也不該有兩份一樣的程式。
//
// 規矩（跟行程看板一樣）：
// - 要讀的數字一律是 Text；Canvas 只畫「看得到、不給讀」的迷你圖。
// - 迷你圖畫的是使用者自己的資料（這個月每天的花費、近 7 天、近幾個月），不畫裝飾用的假圖。

enum MoneyFormat {
    /// 看板上的金額：一萬以上用「萬」、一億以上用「億」，一萬以下寫完整（NT$1,234）。
    /// 走全 App 共用的 ntdWanString，同一個數字在每一頁長得一樣。
    static func short(_ v: Double) -> String { v.ntdWanString }

    /// 帶正負號（結餘）。負號用全形減號，不會跟數字黏成一團
    static func signed(_ v: Double) -> String {
        if v > 0.5 { return "+" + v.ntdWanString }
        if v < -0.5 { return "−" + abs(v).ntdWanString }
        return v.ntdWanString
    }

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
}

// MARK: - 格子

/// 看板上的一格：上面一顆彩色圖示圓＋標籤，中間大數字，下面一行補充（變化、占比…），
/// 右下角淡淡一小塊迷你圖。有 action 就整格可以按（右上角一個小箭頭）。
///
/// 圖示與數字上下排，不像行程看板左右排：金額比「47 站」長得多（NT$12.3萬），
/// 375 寬的手機一格只有一百出頭 pt，左右排會把金額縮到讀不出來。
struct MoneyTile: View {
    let icon: String
    let tint: TripBoardTint
    let label: String
    let value: String
    var valueTone: MoneyTone? = nil
    var detail: String? = nil
    var detailTone: MoneyTone = .neutral
    var art: AnyView? = nil
    var action: (() -> Void)? = nil
    let pal: TripBoardPalette

    var body: some View {
        if let action {
            Button(action: action) {
                content
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var a11y: String {
        label + "，" + value + (detail.map { "，" + $0 } ?? "")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                TripBoardIconBadge(icon: icon, colors: pal.badge(tint), diameter: 24, dark: pal.dark)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(pal.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if action != nil {
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(pal.label.opacity(0.7))
                }
            }
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(valueTone?.color(pal) ?? pal.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(detail)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(detailTone.color(pal))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(alignment: .bottomTrailing) {
            if let art {
                art
                    // 圓環是正方形：貼右下，不要置中在這塊長方形裡
                    .frame(width: 52, height: 26, alignment: .bottomTrailing)
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .modifier(TripBoardCellChrome(pal: pal))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
    }
}

/// 一列三格；不足三格時用空白補齊，跟上一列切齊。
struct MoneyTileRow: View {
    let tiles: [AnyView]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, t in
                t
            }
            if tiles.count < 3 {
                ForEach(0..<(3 - tiles.count), id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 迷你圖（看得到、不給讀）

/// 折線＋淡淡的面積（這個月每天累計、近幾個月…）
struct MoneySparkline: View, Equatable {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            guard values.count >= 2, let maxV = values.max(), maxV > 0 else { return }
            let step = size.width / CGFloat(values.count - 1)
            var line = Path()
            for (i, v) in values.enumerated() {
                let y = size.height - CGFloat(max(0, v) / maxV) * (size.height - 2) - 1
                let p = CGPoint(x: CGFloat(i) * step, y: y)
                if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(
                Gradient(colors: [color.opacity(0.30), color.opacity(0.02)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(line, with: .color(color.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

/// 長條（近 7 天、近 6 個月）。最後一條（今天／本月）比較濃
struct MoneyBars: View, Equatable {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            guard !values.isEmpty else { return }
            let maxV = max(values.max() ?? 0, 1)
            let n = CGFloat(values.count)
            let gap: CGFloat = 2
            let w = max(1, (size.width - gap * (n - 1)) / n)
            for (i, v) in values.enumerated() {
                let h = max(1.5, CGFloat(max(0, v) / maxV) * size.height)
                let rect = CGRect(x: CGFloat(i) * (w + gap), y: size.height - h, width: w, height: h)
                let isLast = i == values.count - 1
                ctx.fill(Path(roundedRect: rect, cornerRadius: min(2, w / 2)),
                         with: .color(color.opacity(isLast ? 0.9 : 0.38)))
            }
        }
    }
}

/// 圓環（還剩幾成、占了幾成）
struct MoneyRing: View, Equatable {
    let fraction: Double
    let color: Color
    let track: Color

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(1, fraction))))
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(2)
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - 燒錢進度

/// 兩條並排比：月過了幾成 vs 可以自由花的錢用了幾成，底下一句白話結論。
struct MoneyPaceCard: View {
    let title: String
    let icon: String
    let monthProgress: Double
    let spentLabel: String
    let spentRatio: Double
    let tone: MoneyTone
    let status: String
    var tag: String? = nil
    let pal: TripBoardPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(tone.color(pal))
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(pal.ink)
                if let tag {
                    Text(tag)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(pal.label)
                        .padding(.horizontal, 6).padding(.vertical, 1.5)
                        .background(pal.progressTrack, in: Capsule())
                }
                Spacer(minLength: 0)
            }
            bar(title: "月過了", fraction: monthProgress, color: pal.label.opacity(0.45))
            bar(title: spentLabel, fraction: spentRatio, color: tone.color(pal))
            Text(status)
                .font(.caption)
                .foregroundStyle(pal.label)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .modifier(TripBoardCellChrome(pal: pal))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title + "，月過了 " + MoneyFormat.percent(monthProgress) + "，"
                            + spentLabel + " " + MoneyFormat.percent(spentRatio) + "。" + status)
    }

    private func bar(title: String, fraction: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(pal.label)
                .lineLimit(1)
                .fixedSize()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(pal.progressTrack)
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(max(0, min(1, fraction))))
                }
            }
            .frame(height: 8)
            Text(MoneyFormat.percent(fraction))
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(pal.ink)
                .frame(minWidth: 38, alignment: .trailing)
        }
    }
}

// MARK: - 膠囊

struct MoneyChip: Identifiable {
    let id: String
    let icon: String
    let text: String
}

struct MoneyChipView: View {
    let chip: MoneyChip
    let pal: TripBoardPalette

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: chip.icon).font(.caption2.weight(.bold))
            Text(chip.text).font(.caption.weight(.semibold)).lineLimit(1)
        }
        .fixedSize()
        .foregroundStyle(pal.capsuleText)
        .padding(.horizontal, 10)
        .frame(minHeight: 24)
        .background(pal.capsuleFill, in: Capsule())
        .overlay(Capsule().stroke(pal.capsuleStroke, lineWidth: 0.75))
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
