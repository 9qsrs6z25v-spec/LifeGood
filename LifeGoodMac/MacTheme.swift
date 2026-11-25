// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.645 mac5 G1a] 電腦版設計系統 MacTheme（judge_mac.md §S3）：色票淺深兩套、頁主題色、圖表色、遊戲色、尺寸、共用元件。
//
// • 只 import SwiftUI；不用 Assets、不用 NSColor 動態色；顏色一律具名 static let／let（值照抄 iOS，Mac 另寫、不共用 iOS 檔）。
// • 名字不准 Color(tb:)、MoneyTone、TripBoardPalette、MoneyPressStyle、accentColor（Mac 新名字 macTint）。
// • 主控骨架：型別、token 的值、元件簽名都已定案（三組都不准改簽名）；G1a 只換元件 body（修飾器 ≤ 8、不收 @ViewBuilder 閉包）。
// • MacPalette 只在外框、卡片 body 讀 @Environment(\.colorScheme)；Table 的 Cell 不讀。

import SwiftUI

// MARK: - 工具與尺寸（§S3-7）

enum MacTheme {
    /// 0xRRGGBB → Color（用共用 Expense.swift 已編過的 Color(red:green:blue:opacity:)）
    static func hex(_ v: Int, _ a: Double = 1) -> Color {
        let r: Double = Double((v >> 16) & 0xFF) / 255
        let g: Double = Double((v >> 8) & 0xFF) / 255
        let b: Double = Double(v & 0xFF) / 255
        return Color(red: r, green: g, blue: b, opacity: a)
    }

    static let boardCorner: CGFloat = 14
    static let cardCorner: CGFloat = 12
    static let boardPadding: CGFloat = 12
    static let cardPadding: CGFloat = 12
    static let pillHeight: CGFloat = 26
}

// MARK: - 色票（§S3-1；照抄 TripSummaryBoard.swift:443-470（9f25bf5）TripBoardPalette 的值）

struct MacPalette {
    let dark: Bool

    init(_ scheme: ColorScheme) { dark = scheme == .dark }

    var ink: Color { dark ? MacTheme.hex(0xF3F6FF) : MacTheme.hex(0x0B1B45) }
    var inkDate: Color { dark ? MacTheme.hex(0xB9C7EE) : MacTheme.hex(0x1D3A7A) }
    var label: Color { dark ? MacTheme.hex(0xA3B2D9) : MacTheme.hex(0x4A5B8C) }
    var hint: Color { dark ? MacTheme.hex(0x8DB7FF) : MacTheme.hex(0x2F5BB7) }
    var boardTop: Color { dark ? MacTheme.hex(0x121B38) : MacTheme.hex(0xEAF4FD) }
    var boardBottom: Color { dark ? MacTheme.hex(0x0E1428) : MacTheme.hex(0xF4F8FD) }
    var cardStroke: Color { dark ? Color.white.opacity(0.08) : Color.white.opacity(0.80) }
    var cardShadow: Color { dark ? Color.black.opacity(0.40) : MacTheme.hex(0x3B6FB6, 0.12) }
    var cellFill: Color { dark ? MacTheme.hex(0x1C2646, 0.86) : Color.white.opacity(0.78) }
    var cellStroke: Color { dark ? Color.white.opacity(0.10) : Color.white.opacity(0.75) }
    var cellShadow: Color { dark ? Color.black.opacity(0.25) : MacTheme.hex(0x1E3A6E, 0.08) }
    var capsuleText: Color { dark ? MacTheme.hex(0xE6ECFF) : MacTheme.hex(0x163A87) }
    var track: Color { dark ? Color.white.opacity(0.10) : MacTheme.hex(0xE3ECF8) }
}

// MARK: - 語氣色（§S3-2；照抄 MoneyBoardKit.swift:51-56（9f25bf5）MoneyTone；neutral＝label，F7）

enum MacTone {
    case good, warn, bad, neutral

    func color(_ p: MacPalette) -> Color {
        switch self {
        case .good: return p.dark ? MacTheme.hex(0x5BD99A) : MacTheme.hex(0x177A44)
        case .warn: return p.dark ? MacTheme.hex(0xFFC14D) : MacTheme.hex(0xA65300)
        case .bad: return p.dark ? MacTheme.hex(0xFF7A8A) : MacTheme.hex(0xC4243C)
        case .neutral: return p.label
        }
    }
}

// MARK: - 頁主題色（§S3-3；淺深同一組）

struct MacPageTheme {
    let top: Color
    let bottom: Color
    let tint: Color

    /// 實心漸層（圖示圓、色條）：左上 → 右下
    var fill: LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 看板染色底：主題色淡淡一層（淺 0.10／深 0.16）→ boardBottom，上 → 下
    func boardFill(_ p: MacPalette) -> LinearGradient {
        let wash: Color = top.opacity(p.dark ? 0.16 : 0.10)
        return LinearGradient(colors: [wash, p.boardBottom], startPoint: .top, endPoint: .bottom)
    }

    // 照抄 HeroStyleKit.swift:310-311（9f25bf5）.income／.overview／.chart
    static let green = MacPageTheme(top: Color(red: 0.16, green: 0.74, blue: 0.50),
                                    bottom: Color(red: 0.07, green: 0.50, blue: 0.38),
                                    tint: Color(red: 0.16, green: 0.74, blue: 0.50))
    // 照抄 HeroStyleKit.swift:345-346（9f25bf5）
    static let orange = MacPageTheme(top: Color(red: 1.00, green: 0.62, blue: 0.22),
                                     bottom: Color(red: 0.86, green: 0.36, blue: 0.06),
                                     tint: Color(red: 1.00, green: 0.62, blue: 0.22))
    // 照抄 HeroStyleKit.swift:351-352（9f25bf5）
    static let blue = MacPageTheme(top: Color(red: 0.22, green: 0.53, blue: 0.98),
                                   bottom: Color(red: 0.10, green: 0.35, blue: 0.82),
                                   tint: Color(red: 0.22, green: 0.53, blue: 0.98))
    // 照抄 MoneyArt.swift:151（9f25bf5）chartTrend
    static let night = MacPageTheme(top: MacTheme.hex(0x7FB8FF), bottom: MacTheme.hex(0x3550D8), tint: MacTheme.hex(0x2F5BD8))
    // top 照抄 FixedExpenseView.swift:494（9f25bf5）稅費 5E6478；bottom Mac 自訂
    static let slate = MacPageTheme(top: Color(red: 0.37, green: 0.39, blue: 0.47),
                                    bottom: Color(red: 0.26, green: 0.28, blue: 0.35),
                                    tint: Color(red: 0.37, green: 0.39, blue: 0.47))
}

extension MacPage {
    /// 側欄圖示、看板染色用（總覽、收入綠；變動支出橘；固定支出藍；圖表夜空藍；資料來源灰藍）
    var theme: MacPageTheme {
        switch self {
        case .overview, .income: return .green
        case .variable: return .orange
        case .fixed: return .blue
        case .chart: return .night
        case .source: return .slate
        }
    }
}

// MARK: - 圖表色（§S3-4；照抄 MoneyArt.swift:151-162、ChartView.swift:1091-1092、MoneyBoardScenes.swift:1015-1064、
//          TripSummaryBoard.swift:1536-1546（9f25bf5））

enum MacChartTheme {
    static let trend = MacPageTheme.night
    static let variable = MacPageTheme(top: MacTheme.hex(0xFFB45E), bottom: MacTheme.hex(0xE0457A), tint: MacTheme.hex(0xE0573A))
    static let fixed = MacPageTheme(top: MacTheme.hex(0xA88BFF), bottom: MacTheme.hex(0x3A63D8), tint: MacTheme.hex(0x5B4BE0))
    static let mixVariable = MacTheme.hex(0x2F6FE0)
    static let mixFixed = MacTheme.hex(0x7547E0)
}

/// 圖表看板的夜空（淺色、深色都用夜空：白星在白天天空上看不清，Mac 自己的取捨 L5）
enum MacSky {
    static let stops: [Gradient.Stop] = [
        Gradient.Stop(color: MacTheme.hex(0x0A1433), location: 0),
        Gradient.Stop(color: MacTheme.hex(0x13224A), location: 0.5),
        Gradient.Stop(color: MacTheme.hex(0x18264E), location: 0.82),
        Gradient.Stop(color: MacTheme.hex(0x121B38), location: 1),
    ]
    static let hill = MacTheme.hex(0x0B1230)
    static let line = MacTheme.hex(0x9ED8FF, 0.45)
    static let halo = MacTheme.hex(0x9ED8FF, 0.12)
    static let star = Color.white
    static let gold = MacTheme.hex(0xFFE29A)

    static var fill: LinearGradient {
        LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    /// 夜空上的字永遠用深色調色盤（淺字）
    static let ink = MacPalette(.dark)
}

// MARK: - 分類色（§S3-5；新名字 macTint，變動共用 VariableCategory.accentColor、Mac 不另寫）

extension FixedCategory {
    // 照抄 FixedExpenseView.swift:497-505（9f25bf5）accent
    var macTint: Color {
        switch self {
        case .rent: return .blue
        case .utilities: return Color(red: 1.0, green: 0.75, blue: 0.10)
        case .insurance: return .green
        case .subscription: return .purple
        case .loan: return Color(red: 0.90, green: 0.25, blue: 0.30)
        case .telecom: return .cyan
        case .management: return Color(red: 0.55, green: 0.45, blue: 0.35)
        // 最後一類
        case .other: return .secondary
        }
    }
}

extension MacFixedGroupKey {
    var macTint: Color {
        switch self {
        case .category(let c): return c.macTint
        // 照抄 FixedExpenseView.swift:494（9f25bf5）稅費 5E6478
        case .tax: return MacTheme.hex(0x5E6478)
        }
    }

    var macIcon: String {
        switch self {
        case .category(let c): return c.icon
        case .tax: return "doc.text.fill"
        }
    }
}

extension IncomeCategory {
    // 照抄 AddIncomeView.swift:112-120（9f25bf5）categoryAccent（這版先定好給 Mac 6）
    var macTint: Color {
        switch self {
        case .salary: return Color(red: 0.16, green: 0.74, blue: 0.50)
        case .bonus: return Color(red: 1.00, green: 0.72, blue: 0.18)
        case .gift: return Color(red: 1.00, green: 0.35, blue: 0.55)
        case .luck: return Color(red: 0.68, green: 0.40, blue: 1.00)
        case .investment: return Color(red: 0.27, green: 0.67, blue: 0.99)
        }
    }
}

// MARK: - 遊戲色（§S3-6；Mac 自訂；遊戲層不准用分類色、MacTone.bad）

struct MacGameTint {
    let dark: Bool

    init(_ scheme: ColorScheme) { dark = scheme == .dark }

    /// 實心星、金燈
    var star: Color { dark ? MacTheme.hex(0xFFD45E) : MacTheme.hex(0xC98A00) }
    /// 葉子（＝MacTone.good）
    var leaf: Color { dark ? MacTheme.hex(0x5BD99A) : MacTheme.hex(0x177A44) }

    // 週數徽章：照抄 HeroStyleKit.swift:333-334（9f25bf5）
    static let medal = MacPageTheme(top: Color(red: 0.10, green: 0.62, blue: 0.58),
                                    bottom: Color(red: 0.04, green: 0.44, blue: 0.52),
                                    tint: Color(red: 0.10, green: 0.62, blue: 0.58))
    /// 存下、守住徽章
    static let save = MacPageTheme.green
    // 三顆星徽章：top 照抄 AddIncomeView.swift:116（9f25bf5）
    static let gold = MacPageTheme(top: Color(red: 1.00, green: 0.72, blue: 0.18),
                                   bottom: Color(red: 0.86, green: 0.55, blue: 0.05),
                                   tint: Color(red: 1.00, green: 0.72, blue: 0.18))
    /// 還沒點亮、空心燈、本月空心星：灰（不是紅、不打叉）
    static let dimStroke = Color.secondary.opacity(0.35)
    static let dimIcon = Color.secondary
}

// MARK: - 外框（§S3-8；G1a：染色漸層、圓角、細框、陰影）

/// 看板：染色漸層底、圓角 14、cardStroke 0.75、陰影 r12 y5、內距 12（照抄 MoneyBoardKit.swift:244-259）
struct MacBoardChrome: ViewModifier {
    let theme: MacPageTheme
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let p = MacPalette(scheme)
        let shape = RoundedRectangle(cornerRadius: MacTheme.boardCorner, style: .continuous)
        let fill: LinearGradient = theme.boardFill(p)
        return content
            .padding(MacTheme.boardPadding)
            .background(fill, in: shape)
            .overlay(shape.stroke(p.cardStroke, lineWidth: 0.75))
            .shadow(color: p.cardShadow, radius: 12, x: 0, y: 5)
    }
}

/// 白卡：cellFill、cellStroke 0.75、陰影 r8 y3、圓角 12、內距 12（照抄 TripSummaryBoard.swift:1102-1115）
struct MacCardChrome: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let p = MacPalette(scheme)
        let shape = RoundedRectangle(cornerRadius: MacTheme.cardCorner, style: .continuous)
        return content
            .padding(MacTheme.cardPadding)
            .background(p.cellFill, in: shape)
            .overlay(shape.stroke(p.cellStroke, lineWidth: 0.75))
            .shadow(color: p.cellShadow, radius: 8, x: 0, y: 3)
    }
}

/// 入場：opacity 0→1、y 10→0、spring(0.45, 0.82)，第 i 個延遲 0.04×min(i, 8)；減少動態效果直接顯示（照抄 OverviewView.swift:248-253）
struct MacAppear: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var anim: Animation {
        .spring(response: 0.45, dampingFraction: 0.82).delay(0.04 * Double(min(index, 8)))
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .onAppear {
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(anim) { shown = true }
                }
            }
    }
}

extension View {
    func macBoard(_ t: MacPageTheme) -> some View { modifier(MacBoardChrome(theme: t)) }
    func macCard() -> some View { modifier(MacCardChrome()) }
    func macAppear(_ index: Int) -> some View { modifier(MacAppear(index: index)) }
}

// MARK: - 元件（§S3-8；簽名定案；G1a 換 body）

/// 圖示圓：solid＝兩色漸層實心圓＋白符號；不 solid＝淡色圓＋細框＋主題色符號（照抄 TripSummaryBoard.swift:2726-2745、AddIncomeView.swift:600-611）
struct MacIconBadge: View {
    let icon: String
    let top: Color
    let bottom: Color
    let size: CGFloat
    let solid: Bool

    var body: some View {
        if solid {
            MacIconBadgeSolid(icon: icon, top: top, bottom: bottom, size: size)
        } else {
            MacIconBadgeSoft(icon: icon, top: top, size: size)
        }
    }
}

/// 實心：top→bottom 漸層圓＋白符號（size×0.45 semibold）＋陰影 bottom@0.30 r3 y2
private struct MacIconBadgeSolid: View {
    let icon: String
    let top: Color
    let bottom: Color
    let size: CGFloat

    var body: some View {
        let fill = LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        ZStack {
            Circle().fill(fill)
            Image(systemName: icon)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(Color.white)
        }
        .frame(width: size, height: size)
        .shadow(color: bottom.opacity(0.30), radius: 3, x: 0, y: 2)
    }
}

/// 淡色：top@0.20→@0.08 漸層圓＋top@0.20 細框 0.75＋top 色符號
private struct MacIconBadgeSoft: View {
    let icon: String
    let top: Color
    let size: CGFloat

    var body: some View {
        let fill = LinearGradient(colors: [top.opacity(0.20), top.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
        ZStack {
            Circle().fill(fill)
            Circle().stroke(top.opacity(0.20), lineWidth: 0.75)
            Image(systemName: icon)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(top)
        }
        .frame(width: size, height: size)
    }
}

/// 區塊標頭：4×16 色條（tint→tint@0.55）＋13pt 圖示＋標題＋右邊計數膠囊（照抄 TaxOverviewView.swift:982-1012）
struct MacSectionHeader: View {
    let title: String
    let icon: String
    let tint: Color
    let count: String?

    var body: some View {
        let bar = LinearGradient(colors: [tint, tint.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        HStack(spacing: 6) {
            Capsule()
                .fill(bar)
                .frame(width: 4, height: 16)
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let count {
                MacSectionCount(text: count, tint: tint)
            }
        }
    }
}

/// 標頭右邊的計數膠囊：tint@0.10 底、tint@0.22 框 0.6、caption2 semibold
private struct MacSectionCount: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.22), lineWidth: 0.6))
    }
}

/// 看板 36pt 大字（value 給 contentTransition 用；numericText() 不帶 value）；減少動態效果時數字直接換、不滾
struct MacHeroNumber: View {
    let text: String
    let value: Double
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(text)
            .font(.system(size: 36, weight: .heavy, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(MacPalette(scheme).ink)
            .contentTransition(.numericText())
            .transaction { t in
                if reduceMotion { t.animation = nil }
            }
            .animation(.snappy, value: value)
    }
}

/// 看板小標
struct MacHeroLabel: View {
    let text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(MacPalette(scheme).label)
    }
}

/// 卡片 22pt 數字（顏色由呼叫端 .foregroundStyle 給：MacStatCard 傳 ink，結餘負數傳 MacTone.bad；
/// 這裡不自己上色，不然外面的顏色蓋不過來）
struct MacStatNumber: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// 白膠囊：圖示（tone 色）＋標籤＋值；高 26、cellFill／cellStroke／陰影 r4 y1（照抄 MoneyBoards.swift:56-80）
struct MacPill: View {
    let icon: String
    let label: String
    let value: String
    let tone: MacTone
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = MacPalette(scheme)
        MacPillContent(icon: icon, label: label, value: value, iconColor: tone.color(p), p: p)
            .padding(.horizontal, 9)
            .frame(height: MacTheme.pillHeight)
            .background(p.cellFill, in: Capsule())
            .overlay(Capsule().stroke(p.cellStroke, lineWidth: 0.75))
            .shadow(color: p.cellShadow, radius: 4, x: 0, y: 1)
    }
}

/// 膠囊裡面那一行（拆出來，MacPill.body 修飾器不超過 8 個）
private struct MacPillContent: View {
    let icon: String
    let label: String
    let value: String
    let iconColor: Color
    let p: MacPalette

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(iconColor)
            Text(label)
                .font(.caption)
                .foregroundStyle(p.label)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(p.capsuleText)
        }
        .lineLimit(1)
    }
}

/// 6pt 比例條：底 tint@0.14、前景 tint→tint@0.7（不用 GeometryReader：前景用 scaleEffect 從左邊縮；呼叫端先把 fraction 夾在 0…1，這裡再夾一次）
struct MacMeterBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        let f: Double = min(max(fraction, 0), 1)
        let fill = LinearGradient(colors: [tint, tint.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
        ZStack(alignment: .leading) {
            Capsule().fill(tint.opacity(0.14))
            if f > 0 {
                Capsule()
                    .fill(fill)
                    .scaleEffect(x: CGFloat(f), y: 1, anchor: .leading)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// 空白狀態：72pt 淡色圖示圓＋標題＋說明（靜態，不脈衝；照 VariableExpenseView.swift:298-345 縮小）
struct MacEmptyHint: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String?

    var body: some View {
        VStack(spacing: 10) {
            MacIconBadge(icon: icon, top: tint, bottom: tint, size: 72, solid: false)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

/// 徽章外框：點亮＝實心圖示圓＋外圈 top@0.35 1.5pt；沒點亮＝灰色空心圓＋灰圖示（不是紅、不打叉）
struct MacMedalFrame: View {
    let icon: String
    let top: Color
    let bottom: Color
    let earned: Bool
    let size: CGFloat

    var body: some View {
        if earned {
            MacIconBadge(icon: icon, top: top, bottom: bottom, size: size, solid: true)
                .overlay(Circle().stroke(top.opacity(0.35), lineWidth: 1.5).padding(-3))
        } else {
            MacMedalDim(icon: icon, size: size)
        }
    }
}

/// 還沒點亮：MacGameTint.dimStroke 空心圓＋dimIcon 圖示
private struct MacMedalDim: View {
    let icon: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(MacGameTint.dimStroke, lineWidth: 1.5)
            Image(systemName: icon)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(MacGameTint.dimIcon)
        }
        .frame(width: size, height: size)
    }
}

/// 手寫招呼（Bradley Hand；字型不存在時自動退回系統字）；色＝hint（圖表看板掛 .dark，夜空上是淺色）
struct MacGreeting: View {
    let text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .font(Font.custom("BradleyHandITCTT-Bold", size: 16))
            .foregroundStyle(MacPalette(scheme).hint)
            .lineLimit(1)
    }
}
