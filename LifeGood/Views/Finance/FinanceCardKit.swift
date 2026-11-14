//
//  FinanceCardKit.swift
//  LifeGood
//
//  [v25.540] 理財卡片的通用零件（第三張卡：股票、房屋之後的車子）。
//  - 這些本來是房屋卡（HouseCardViews.swift）裡的 private 零件，車子要第二次用，不抽就要第三次複製。
//  - 搬過來的是同一份程式碼、只改名字；房屋那邊用 private typealias 接回舊名、或改成一行轉呼叫，
//    所以房屋上百個呼叫點一個字都不用改，畫面一像素都不變。
//  - 值型別（FinanceLine、FinanceRun、FinanceFormat、FinanceRound、FinanceProgressData）的別名放在
//    VehicleCardData.swift 最上面，這裡不再宣告一次。
//  - 這裡的 View 都不讀 EnvironmentObject（分享圖片用 ImageRenderer 畫），只讀 colorScheme。
//

import SwiftUI

// MARK: - 外框、顏色

/// 白卡外框、格子底色：股票卡片那一套本來就是通用的，換個名字給房子、車子用（不動 StockCardViews.swift）
typealias FinanceCardChrome = StockCardChrome      // 白卡外框（StockCardViews.swift，不改原檔）
typealias FinanceCardTile = StockCardTile          // 格子底色等

/// 卡片上通用的幾個顏色（房屋 HCColors 的 pick／tick／ink／payingBlue 搬過來；分類色各卡自己留）
enum FinanceCardColors {
    static func pick(_ light: UInt32, _ dark: UInt32, _ pal: TripBoardPalette) -> Color {
        Color(tb: pal.dark ? dark : light)
    }

    /// 進度格的段交界細刻度
    static func tick(_ pal: TripBoardPalette) -> Color {
        pal.dark ? Color.white.opacity(0.32) : Color(tb: 0xA9B6D3)
    }

    /// 繳款中那一段的藍（白字在上面深淺色都讀得到）
    static let payingBlue = Color(tb: 0x2F7FE8)

    /// 格子大數字、小字的顏色：nil 或 neutral 用呼叫端給的一般字色
    static func ink(_ tone: MoneyTone?, pal: TripBoardPalette, fallback: Color) -> Color {
        guard let tone, tone != .neutral else { return fallback }
        return tone.color(pal)
    }
}

// MARK: - 換房／換車列

/// 換房（換車）列的一顆膠囊
struct FinanceSwitcherItem: Identifiable, Equatable {
    let id: UUID
    let title: String          // 已截短（MoneyBoardText.short(_, max: 6)）
    let trailing: String       // 「▲30%」「賣 ▲18%」；可空字串
    let tone: MoneyTone
}

/// 釘在最上面的一排：同一組（持有中／已售出）的每一間，點了就換。樣子照 StockSwitcherStrip，選中的自動捲到中間。
struct FinanceSwitcherStrip: View {
    let items: [FinanceSwitcherItem]
    let selected: UUID
    let onSelect: (UUID) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items, id: \.id) { item in
                        Button {
                            onSelect(item.id)
                        } label: {
                            pill(item, on: item.id == selected, pal: pal)
                        }
                        .buttonStyle(MoneyPressStyle())
                        .id(item.id)
                        .accessibilityAddTraits(item.id == selected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
            .onChange(of: selected) { _, id in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func pill(_ item: FinanceSwitcherItem, on: Bool, pal: TripBoardPalette) -> some View {
        let fill = on ? FinanceCardColors.pick(0x1D2B55, 0x3B4F8F, pal) : pal.cellFill
        let ink = on ? Color.white : pal.ink
        return HStack(spacing: 6) {
            Text(item.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ink)
            if !item.trailing.isEmpty {
                Text(item.trailing)
                    .font(.caption.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(trailingColor(item.tone, on: on, pal: pal))
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .background(fill, in: Capsule())
        .overlay(Capsule().stroke(on ? Color.clear : pal.cellStroke, lineWidth: 0.75))
        .shadow(color: on ? Color.clear : pal.cellShadow, radius: 3, x: 0, y: 1)
    }

    /// 選中的膠囊是深藍底：漲跌字改用調亮的 FF8A8A／6EE7A8，不然紅綠壓在深藍上看不清楚
    private func trailingColor(_ tone: MoneyTone, on: Bool, pal: TripBoardPalette) -> Color {
        guard on else { return tone.color(pal) }
        switch tone {
        case .up: return Color(tb: 0xFF8A8A)
        case .down, .good: return Color(tb: 0x6EE7A8)
        default: return Color.white.opacity(0.85)
        }
    }
}

// MARK: - 資料卡的列

/// 資料卡的一列：左邊標籤（寬 84）、右邊值靠右（樣子照 StockInfoCard）；accessory 是右邊的小圖示（›、展開）
struct FinanceInfoRow: View {
    let label: String
    let value: Text
    var accessory: String? = nil
    var labelWidth: CGFloat = 84

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .leading)
            value
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
            if let accessory {
                Image(systemName: accessory)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// 一串資料列，列和列之間細線（同 StockInfoCard）；外框由呼叫端決定。
/// 每列自己決定能不能點（地址是選單、權狀可展開、保險可點），所以收的是已經包好的畫面。
struct FinanceInfoRows: View {
    struct Row: Identifiable {
        let id: String
        let content: AnyView
    }

    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                if i > 0 {
                    Divider().padding(.leading, 14)
                }
                row.content
            }
        }
    }
}

// MARK: - 區塊標題、小按鈕、小標

/// 區塊標題（MoneySectionHeader）＋需要時右邊一顆綠色「＋」（MoneySectionHeader 本身沒有按鈕槽）
struct FinanceCardHeader: View {
    let title: String
    var trailing: String? = nil
    var addLabel: String? = nil
    var onAdd: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            MoneySectionHeader(title: title, trailing: trailing)
                .accessibilityAddTraits(.isHeader)
            if let onAdd {
                FinanceAddButton(label: addLabel ?? "新增", action: onAdd)
            }
        }
    }
}

/// 區塊標題右邊的綠色小「＋」
struct FinanceAddButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Color.white)
                .frame(width: 24, height: 24)
                .background(Color(tb: 0x1F9D57), in: Circle())
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(MoneyPressStyle())
        .accessibilityLabel(label)
    }
}

/// 綠色膠囊「＋ 記一筆」「＋ 加一段」（同股票帳本的 177A44 膠囊）
struct FinanceGreenPill: View {
    let title: String

    var body: some View {
        Label(title, systemImage: "plus")
            .font(.caption.weight(.heavy))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .background(Color(tb: 0x177A44), in: Capsule())
    }
}

/// 灰色／注意色小標（「沒連到記帳」「期數沒填」）
struct FinanceMiniTag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}

/// 列旁邊的照片小圖示＋張數（點了看全部照片）
struct FinancePhotoBadge: View {
    let count: Int
    let pal: TripBoardPalette

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "photo.on.rectangle")
            Text("\(count)")
        }
        .font(.caption.weight(.bold))
        .monospacedDigit()
        .foregroundStyle(pal.hint)
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .background(pal.hint.opacity(0.12), in: Capsule())
    }
}

// MARK: - 一句話

/// FinanceLine 轉成 Text（不能叫 FinanceText：FinanceBoards.swift 已經有 enum FinanceText）
enum FinanceLineText {
    /// 一段一段接成一個 Text（粗體用 heavy、tone 上色）；用插值接，不串一長串 +
    static func text(_ line: FinanceLine, pal: TripBoardPalette) -> Text {
        var out: Text? = nil
        for run in line.runs {
            let next = piece(run, pal: pal)
            if let prev = out {
                out = Text("\(prev)\(next)")
            } else {
                out = next
            }
        }
        return out ?? Text(verbatim: "")
    }

    private static func piece(_ run: FinanceRun, pal: TripBoardPalette) -> Text {
        var t = Text(verbatim: run.text)
        if run.bold {
            t = t.fontWeight(.heavy)
        }
        if let tone = run.tone {
            t = t.foregroundStyle(tone.color(pal))
        }
        return t
    }
}

/// 白卡裡的一句話（FinanceLine：金額粗體、上色）
struct FinanceSentence: View {
    let line: FinanceLine
    let pal: TripBoardPalette

    var body: some View {
        FinanceLineText.text(line, pal: pal)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 3×2 格

/// 一格要畫的東西。點了做什麼由各卡自己的 tap 型別決定，這裡只問「能不能點」「VoiceOver 提示」
protocol FinanceTileContent: Identifiable {
    var label: String { get }
    var value: String { get }
    var valueTone: MoneyTone? { get }
    var sub: String { get }
    var subTone: MoneyTone? { get }
    var isTappable: Bool { get }
    /// VoiceOver 的提示（點了會去哪裡）；不能點的格子 ""
    var tapHint: String { get }
}

/// 3×2 格（樣子照股票帳本的六格）；可以點的格子小字後面多一個 ›。點了把那一格交回給呼叫端
struct FinanceTileGrid<Tile: FinanceTileContent>: View {
    let tiles: [Tile]
    let pal: TripBoardPalette
    var onTap: ((Tile) -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // 超大字時三欄擠不下「還有 39 年 5 個月」，改兩欄
        let count = typeSize.isAccessibilitySize ? 2 : 3
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(tiles, id: \.id) { t in
                cell(t)
            }
        }
    }

    @ViewBuilder
    private func cell(_ t: Tile) -> some View {
        if let onTap, t.isTappable {
            Button {
                onTap(t)
            } label: {
                FinanceTileView(tile: t, pal: pal, tappable: true)
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityHint(t.tapHint)
        } else {
            FinanceTileView(tile: t, pal: pal, tappable: false)
        }
    }
}

struct FinanceTileView<Tile: FinanceTileContent>: View {
    let tile: Tile
    let pal: TripBoardPalette
    let tappable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tile.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(tile.value)
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(FinanceCardColors.ink(tile.valueTone, pal: pal, fallback: Color.primary))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            subLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(FinanceCardTile.fill(pal), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var subLine: some View {
        HStack(spacing: 2) {
            Text(tile.sub.isEmpty ? " " : tile.sub)
                .font(.caption2)
                .foregroundStyle(FinanceCardColors.ink(tile.subTone, pal: pal, fallback: Color.secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if tappable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 長條

/// 分段長條的一段
struct FinanceBarPart: Identifiable {
    let id: String
    let value: Double
    let color: Color
}

/// 分段長條（同股票「含息總報酬」那條：2pt 間隔、每段最少 2pt、外面裁成膠囊）；數字靠圖例的字唸，條本身不給讀
struct FinanceStackBar: View {
    let parts: [FinanceBarPart]
    let height: CGFloat
    let pal: TripBoardPalette

    var body: some View {
        let positive = parts.filter { $0.value > 0 }
        let sum = positive.reduce(0.0) { $0 + $1.value }
        return GeometryReader { geo in
            bar(positive, sum: sum, width: geo.size.width)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func bar(_ list: [FinanceBarPart], sum: Double, width: CGFloat) -> some View {
        let gaps = CGFloat(max(0, list.count - 1)) * 2
        let usable = max(0, width - gaps)
        return ZStack(alignment: .leading) {
            Capsule().fill(pal.progressTrack)
            if sum > 0 {
                HStack(spacing: 2) {
                    ForEach(list, id: \.id) { p in
                        Rectangle()
                            .fill(p.color)
                            .frame(width: max(2, usable * CGFloat(p.value / sum)))
                    }
                }
                .clipShape(Capsule())
            }
        }
    }
}

/// 段落列「第 7／60 期」旁邊的細進度條
struct FinanceThinBar: View {
    let fraction: Double
    let color: Color
    let track: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(color)
                    .frame(width: max(4, geo.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(minWidth: 40, maxWidth: .infinity)
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

// MARK: - 貸款進度格

/// 貸款進度：左端第一期、右端繳完；過去的那段紫色、未來灰；段和段的交界細刻度；今天一顆圓點。
/// 骨架照 StockPricePosition（12pt 留白＋TripBoardCellChrome、44pt 高的軌道、18pt 小牌子），牌子太近時推開。
struct FinanceProgressCell: View {
    let p: FinanceProgressData
    let pal: TripBoardPalette
    var tappable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            titleRow
            GeometryReader { geo in
                track(width: geo.size.width)
            }
            .frame(height: 44)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(p.left)
                Spacer(minLength: 4)
                Text(p.right)
                    .multilineTextAlignment(.trailing)
            }
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(pal.label)
            if !p.note.isEmpty {
                Text(p.note)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(pal.inkDate)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .modifier(TripBoardCellChrome(pal: pal))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(p.title)
        .accessibilityValue(p.accessibilityText)
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(p.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(pal.ink)
            Spacer(minLength: 8)
            Text(p.range)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(pal.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if tappable {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(pal.label)
            }
        }
    }

    private func track(width w: CGFloat) -> some View {
        let inset: CGFloat = 9
        let usable = max(1, w - inset * 2)
        let f = CGFloat(min(1, max(0, p.fraction)))
        let xDot = inset + usable * f
        let xEnd = inset + usable
        let trackY: CGFloat = 33
        let deep = MoneyBoardSky.ridgeCost(dark: pal.dark)
        let dotColor = p.notStarted ? pal.label : deep
        let centers = pillCenters(width: w, dot: xDot, dotText: p.dotPill, end: xEnd, endText: p.endPill)
        let fillStart = inset - 4
        return ZStack {
            Capsule()
                .fill(pal.progressTrack)
                .frame(width: usable + 8, height: 6)
                .position(x: w / 2, y: trackY)
            if f > 0 {
                Capsule()
                    .fill(LinearGradient(colors: [deep.opacity(0.4), deep], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, xDot - fillStart), height: 6)
                    .position(x: (fillStart + xDot) / 2, y: trackY)
            }
            ForEach(p.ticks, id: \.id) { t in
                Capsule()
                    .fill(FinanceCardColors.tick(pal))
                    .frame(width: 1.5, height: 12)
                    .position(x: inset + usable * CGFloat(t.fraction), y: trackY)
            }
            Circle()
                .fill(dotColor)
                .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                .frame(width: 15, height: 15)
                .shadow(color: dotColor.opacity(0.35), radius: 3, x: 0, y: 1)
                .position(x: xDot, y: trackY)
            pill(p.dotPill, fill: p.notStarted ? FinanceCardColors.pick(0x7A86A8, 0x5A6585, pal) : FinanceCardColors.pick(0x1D2B55, 0x3B4F8F, pal))
                .position(x: centers.dot, y: 9)
            pill(p.endPill, fill: FinanceCardColors.pick(0x177A44, 0x2E9E66, pal))
                .position(x: centers.end, y: 9)
        }
    }

    private func pill(_ s: String, fill: Color) -> some View {
        Text(s)
            .font(.system(size: 10, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(fill, in: Capsule())
    }

    /// 牌子的寬度（估的：中文一個字約 10.5pt、數字約 6pt，加左右留白；同 StockPricePosition）
    private func pillWidth(_ s: String) -> CGFloat {
        s.unicodeScalars.reduce(CGFloat(14)) { $0 + ($1.isASCII ? 6.2 : 10.5) }
    }

    /// 「今天」和「繳完」各自先夾在格子裡（「繳完」掛在最右端，一定會被往左推）；
    /// 兩塊靠太近才往兩邊推開，推出邊緣就整組挪回來。不能一開始就整組挪：兩塊離很遠時，
    /// 「繳完」貼右邊被推回來，會連「今天」一起推出左邊。
    private func pillCenters(width w: CGFloat, dot: CGFloat, dotText: String, end: CGFloat,
                             endText: String) -> (dot: CGFloat, end: CGFloat) {
        let wa = pillWidth(dotText)
        let wb = pillWidth(endText)
        var a = min(max(dot, wa / 2), w - wa / 2)
        var b = min(max(end, wb / 2), w - wb / 2)
        let need = (wa + wb) / 2 + 6
        if b - a < need {
            let mid = (a + b) / 2
            a = mid - need / 2
            b = mid + need / 2
            if b + wb / 2 > w {
                let shift = b + wb / 2 - w
                a -= shift
                b -= shift
            }
            if a - wa / 2 < 0 {
                let shift = wa / 2 - a
                a += shift
                b += shift
            }
        }
        return (dot: a, end: b)
    }
}

// MARK: - 帳本的一列

/// 金額下面的小標（「沒連到記帳」灰色、「自備款不知道」注意色）
struct FinanceRowTag: Identifiable {
    let text: String
    let color: Color
    var id: String { text }
}

/// 帳本的一列（匯出逐筆也用它，所以只吃字串和顏色、不讀任何 EnvironmentObject）：
/// 52pt 日期塊、32pt 分類色圓裡一個字、標題與細字、右邊金額；金額下可以掛小標
struct FinanceLedgerRow: View {
    let dayText: String
    let monthText: String
    let glyph: String
    let markColor: Color
    let title: String
    let detail: String
    let amountText: String
    var tags: [FinanceRowTag] = []
    let accessibilityText: String
    /// 左右留白；列旁邊另外放收據按鈕時傳 0，由外層補
    var hPadding: CGFloat = 14

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            dateBlock
            Text(glyph)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Color.white)
                .frame(width: 32, height: 32)
                .background(markColor, in: Circle())
                .accessibilityHidden(true)
            texts
            Spacer(minLength: 6)
            amount
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, hPadding)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var dateBlock: some View {
        VStack(spacing: 0) {
            Text(dayText)
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .monospacedDigit()
            Text(monthText)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(width: 52)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    private var amount: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(amountText)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .lineLimit(1)
            ForEach(tags, id: \.id) { tag in
                FinanceMiniTag(text: tag.text, color: tag.color)
            }
        }
    }
}

// MARK: - 帳本的篩選、年份、再看 N 筆、記一筆

/// 篩選膠囊（「全部 NT$371.2萬」）；選中的深藍底白字。切換的動畫留在呼叫端的 action 裡
struct FinanceFilterChip: View {
    let text: String
    let on: Bool
    let pal: TripBoardPalette
    let action: () -> Void

    var body: some View {
        let fill = on ? FinanceCardColors.pick(0x0B1B45, 0x3B4F8F, pal) : FinanceCardTile.fill(pal)
        return Button(action: action) {
            Text(text)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(on ? Color.white : pal.label)
                .padding(.horizontal, 11)
                .frame(minHeight: 28)
                .background(fill, in: Capsule())
        }
        .buttonStyle(MoneyPressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// 年份組頭「2026 年・79 筆」＋右邊小計；點一下展開／收起（動畫留在呼叫端的 action 裡）
struct FinanceYearHeader: View {
    let title: String
    let expanded: Bool
    let pal: TripBoardPalette
    let action: () -> Void

    var body: some View {
        let parts = Self.splitTitle(title)
        let state: String = expanded ? "已展開" : "已收起"
        let hint: String = expanded ? "點兩下收起" : "點兩下展開"
        return Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.heavy))
                    .frame(width: 12)
                Text(parts.left)
                Spacer(minLength: 8)
                Text(parts.right)
                    .monospacedDigit()
            }
            .font(.footnote.weight(.heavy))
            .foregroundStyle(pal.label)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(state)
        .accessibilityHint(hint)
    }

    /// 「2026 年・79 筆・NT$862.6萬」→ 左「2026 年・79 筆」、右「NT$862.6萬」（最後一個「・」後面是小計）
    private static func splitTitle(_ t: String) -> (left: String, right: String) {
        guard let r = t.range(of: "・", options: .backwards) else { return (left: t, right: "") }
        return (left: String(t[..<r.lowerBound]), right: String(t[r.upperBound...]))
    }
}

/// 「再看 N 筆」（上面一條細線）
struct FinanceMoreButton: View {
    let hidden: Int
    let pal: TripBoardPalette
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider().padding(.leading, 14)
            Button(action: action) {
                Text("再看 \(hidden) 筆")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(pal.hint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// [v25.534] 綠色「＋ 記一筆」選單：付費在選單打開前就擋——沒付費時不是選單，是一顆按了只跳付費說明的按鈕
struct FinanceAddMenuPill<Items: View>: View {
    var title: String = "記一筆"
    let canEdit: Bool
    let askPremium: () -> Void
    // init 已經自己寫了 @ViewBuilder 參數，屬性本身就不用再掛（掛了也只影響 memberwise init）
    let items: () -> Items

    init(title: String = "記一筆", canEdit: Bool, askPremium: @escaping () -> Void,
         @ViewBuilder items: @escaping () -> Items) {
        self.title = title
        self.canEdit = canEdit
        self.askPremium = askPremium
        self.items = items
    }

    var body: some View {
        if canEdit {
            Menu {
                items()
            } label: {
                FinanceGreenPill(title: title)
            }
            .accessibilityLabel(title)
        } else {
            Button {
                askPremium()
            } label: {
                FinanceGreenPill(title: title)
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityLabel(title)
        }
    }
}

// MARK: - 圖例、要確認、完成列

/// 可以點的圖例：8×8 色塊＋名稱＋金額（action nil＝不能點，例如分享圖）
struct FinanceLegendButton: View {
    let color: Color
    let label: String
    let valueText: String
    let accessibilityLabel: String
    let hint: String
    let pal: TripBoardPalette
    let action: (() -> Void)?

    var body: some View {
        if let action {
            Button {
                action()
            } label: {
                content
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(hint)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
        }
    }

    private var content: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(pal.label)
            Text(valueText)
                .fontWeight(.heavy)
                .monospacedDigit()
                .foregroundStyle(pal.ink)
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .fixedSize()
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

/// 「要確認」一列右邊的一顆按鈕
struct FinanceCheckButton: Identifiable {
    let title: String
    let action: () -> Void
    var id: String { title }
}

/// 「要確認」的一列：注意色圖示、一句話、右邊膠囊按鈕（付費、確認都在外殼）。
/// 一顆按鈕時排在同一行（房屋原樣）；兩顆時排到句子下面，免得句子被擠成一欄
struct FinanceCheckRow: View {
    let icon: String
    let message: String
    let buttons: [FinanceCheckButton]
    /// 第一顆按鈕的 VoiceOver 名稱（「去填：車貸沒填年限…」）；其他顆用「按鈕字：句子」
    let accessibilityLabel: String
    let pal: TripBoardPalette

    var body: some View {
        if buttons.count > 1 {
            stacked
        } else {
            HStack(alignment: .center, spacing: 10) {
                iconView
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // 一顆時直接排在同一行（不再多包一層 HStack），跟房屋原本的排法一模一樣
                ForEach(Array(buttons.enumerated()), id: \.element.id) { i, b in
                    button(b, index: i)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }

    private var stacked: some View {
        HStack(alignment: .top, spacing: 10) {
            iconView
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    ForEach(Array(buttons.enumerated()), id: \.element.id) { i, b in
                        button(b, index: i)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var iconView: some View {
        Image(systemName: icon)
            .font(.body.weight(.semibold))
            .foregroundStyle(MoneyTone.warn.color(pal))
            .frame(width: 20)
            .accessibilityHidden(true)
    }

    private func button(_ b: FinanceCheckButton, index: Int) -> some View {
        let spoken = index == 0 ? accessibilityLabel : "\(b.title)：\(message)"
        return Button {
            b.action()
        } label: {
            Text(b.title)
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(pal.hint)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 11)
                .frame(minHeight: 30)
                .background(pal.hint.opacity(0.12), in: Capsule())
        }
        .buttonStyle(MoneyPressStyle())
        .accessibilityLabel(spoken)
    }
}

/// 看板下取代進度格的一行（「車貸 2029/9 全部繳完」）：圖示＋粗體一行，看板格子的外框
struct FinanceDoneRow: View {
    let icon: String
    let text: String
    let tone: MoneyTone
    let pal: TripBoardPalette

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tone.color(pal))
            Text(text)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(pal.ink)
            Spacer(minLength: 0)
        }
        .padding(12)
        .modifier(TripBoardCellChrome(pal: pal))
        .accessibilityElement(children: .combine)
    }
}
