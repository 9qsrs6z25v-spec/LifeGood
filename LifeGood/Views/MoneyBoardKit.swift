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
// - 圖只畫一張、畫大、畫在自己的格子裡，不跟字疊在一起。
// - 要讀的數字一律是 Text；Canvas 只畫「看得到、不給讀」的圖。
//
// [v25.526] 看板頭部換成天空＋風景（MoneyBoardScenes.swift／MoneyBoards.swift）；
// 原本總覽的「本月支出走勢圖」由城市取代，拿掉。格子右下角加一個淡淡的圖案（watermark）。

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
///
/// [v25.527] 加 up／down：股價的漲跌照台股習慣「紅漲綠跌」（使用者選的）。
/// 跟 good／bad 分開，因為意思不一樣：花得少是好（綠），股票漲是紅。
enum MoneyTone {
    case good, warn, bad, neutral, up, down

    func color(_ pal: TripBoardPalette) -> Color {
        switch self {
        case .good: return pal.dark ? Color(tb: 0x5BD99A) : Color(tb: 0x177A44)
        case .warn: return pal.dark ? Color(tb: 0xFFC14D) : Color(tb: 0xA65300)
        case .bad: return pal.dark ? Color(tb: 0xFF7A8A) : Color(tb: 0xC4243C)
        case .neutral: return pal.label
        case .up: return pal.dark ? Color(tb: 0xFF6B6B) : Color(tb: 0xD62F3A)
        case .down: return pal.dark ? Color(tb: 0x5BD99A) : Color(tb: 0x1F8A50)
        }
    }

    /// 漲跌（紅漲綠跌）；差不到 0.05% 算平盤
    static func change(_ v: Double, base: Double = 1) -> MoneyTone {
        guard base != 0 else { return .neutral }
        let r = v / abs(base)
        if r > 0.0005 { return .up }
        if r < -0.0005 { return .down }
        return .neutral
    }

    /// 花得比較多是「注意」、比較少是「好」；差不到 5% 不上色
    static func spendingChange(_ now: Double, vs before: Double) -> MoneyTone {
        guard before > 0 else { return .neutral }
        if now > before * 1.05 { return .warn }
        if now < before * 0.95 { return .good }
        return .neutral
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
    /// 右下角淡淡的大圖案（SF Symbol）：只是裝飾，不給讀
    var watermark: String? = nil
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
        // 圖案超出格子的那一截由格子的外框裁掉（TripBoardCellChrome 會 clipShape）
        .background(alignment: .bottomTrailing) {
            if let watermark {
                Image(systemName: watermark)
                    .font(.system(size: 50, weight: .bold))
                    .foregroundStyle(pal.ink.opacity(pal.dark ? 0.08 : 0.06))
                    .rotationEffect(.degrees(-14))
                    .offset(x: 10, y: 12)
                    .accessibilityHidden(true)
            }
        }
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
