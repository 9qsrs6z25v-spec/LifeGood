import SwiftUI
import MapKit
import UIKit
// .onReceive(NotificationCenter.default.publisher(for:)) 要用（MultiPhotoGallery 也是明著 import）
import Combine

// MARK: - 時間軸的一站：一站一張卡（v25.517，使用者畫的設計稿）
//
// 構圖照設計稿：
//
//   ╭───────────╮ ╭──────────────────────────────────────╮
//   │ ㊸        │ │ 🚗 2 分・313 m ›   ░░街道░░(🚗)    ⊕ │  ← 路段膠囊（原本兩站之間那一列）
//   │           ╰╮╰──────────────────────────────────────╯
//   │  照片       ╰╮ THE ROYAL PARK CANVAS          (≡)(…)
//   │  （波浪右緣） │ 📍 福岡縣福岡市博多區中洲 56-20
//   │              │ ┌✓ 已抵達 ──┬─ 🛏 過夜・隔天出發 ───›┐
//   │  Fukuoka    ╭╯ │  23:05    │   07:00              │
//   │   JAPAN    ╭╯  └──────────┴──────────────────────┘
//   │ [🛏實際入住] │ [☀ 25°/15° 福岡・晴時多雲][☎ 092…][地圖]
//   │ (🛒)        │ ‿‿樓群‿‿塔‿‿橋‿‿  Have a nice trip! ✈  [NT$1,014]
//   ╰─────────────┴──────────────────────────────────────────╯
//
// 但字級、比例都以手機讀得到為準：設計稿是平板比例，照縮到 393pt 寬的手機上
// 標題只剩 11pt、狀態小標不到 5pt。這裡的數字見規格「手機幾何」。
//
// 這個檔案只放**跟資料無關的骨架與零件**：卡片的形狀、照片的切線、各個小元件。
// 這一站要放什麼內容（打卡、選單、花費、sheet）由 TripPlanDetailView 組好，
// 用 AnyView 塞進來——一方面零件不必知道整個行程頁的狀態，另一方面在這個
// 邊界把型別抹掉（本專案踩過泛型型別太深、demangle 時 stack overflow 的閃退）。

// MARK: - 尺寸

/// 卡片的幾何。整條時間軸量一次卡寬，每張卡共用。
struct TripCardMetrics: Equatable {
    let cardWidth: CGFloat
    /// 字放很大時改成上下排（照片在上面變成橫幅，文字在下面）
    let stacked: Bool

    /// 標題右邊兩顆圓鈕（≡ 與 …，各 28）加三段 2pt 間距（標題｜≡｜…）＝ 28＋28＋2＋2 ＝ 60。
    /// ⚠️ 要跟 TripPlanDetailView.cardColumn 的標題列一致：這裡寫多了，切換上下排的
    ///    門檻就會提早一級（審查抓到：寫成 64 時 390／393 寬在 xxLarge 就切了）。
    static let titleAccessoryWidth: CGFloat = 60

    init(cardWidth: CGFloat, typeSize: DynamicTypeSize) {
        let w = max(280, cardWidth)
        self.cardWidth = w
        let photo = (w * 0.30).rounded()
        // 標題寬除以標題字級＝一行放得下幾個字高。小於 9 就改上下排：
        // 375 寬從 xxLarge（19）開始、390～402 從 xxxLarge（21）、430／440 從輔助第 1 級（25）。
        // 不切換的話，375 寬到輔助第 1 級時「THE ROYAL PARL…」每行只剩一個字。
        let titleWidth = w - photo - 20 - Self.titleAccessoryWidth
        self.stacked = titleWidth / Self.subheadlineSize(typeSize) < 9
    }

    /// 照片最寬處＝卡寬 30%（375 寬 103、440 寬 122）。
    /// 設計稿是 47%；照搬的話 440 寬的標題也要折三行。
    var photo: CGFloat { (cardWidth * 0.30).rounded() }
    /// 照片頂端讓給路段膠囊之後的寬度
    var photoTop: CGFloat { (photo * 0.80).rounded() }
    /// 照片底部讓給膠囊排之後的寬度
    var photoBottom: CGFloat { (photo * 0.82).rounded() }
    /// 卡寬 ≥ 395（430／440 寬的手機）：天氣膠囊寫兩行、狀態面板寫長的標籤
    var roomy: Bool { cardWidth >= 395 }

    /// .subheadline 在各級字級的點數（Apple HIG 的表）
    static func subheadlineSize(_ t: DynamicTypeSize) -> CGFloat {
        switch t {
        case .xSmall: return 12
        case .small: return 13
        case .medium: return 14
        case .large: return 15
        case .xLarge: return 17
        case .xxLarge: return 19
        case .xxxLarge: return 21
        case .accessibility1: return 25
        case .accessibility2: return 30
        case .accessibility3: return 36
        case .accessibility4: return 42
        case .accessibility5: return 49
        @unknown default: return 15
        }
    }
}

// MARK: - 顏色

/// 當天色要拿來寫字或當白字的底時，要先處理過才過得了對比。
///
/// 六個當天色是寫死的 sRGB 常數，不分深淺色模式。直接拿來寫在淺灰底上
/// 只有 2.1～3.1:1，連大字的 3:1 都過不了；混 40% 黑之後是 4.8～6.2。
/// 深色模式用原色就夠（在 #2C2C2E 上 3.5～4.9，大字過）。
/// ⚠️ 數字是用 sRGB 近似算的；Color.mix 預設在 perceptual 色彩空間混，實機要再驗一次。
enum TripInk {
    /// 寫字用
    static func text(_ c: Color, _ scheme: ColorScheme) -> Color {
        scheme == .dark ? c : c.mix(with: .black, by: 0.4)
    }
    /// 白字壓上去的實心底（兩種模式都壓暗）。花費招牌原本白字壓原色只有
    /// 2.32～3.43:1，改用這個是 5.8～7.7:1。
    static func solid(_ c: Color) -> Color {
        c.mix(with: .black, by: 0.4)
    }
    /// 過夜的靛藍。系統靛藍在深色模式的 #2C2C2E 上只有 2.75:1，混 30% 白後 4.77:1
    static func indigo(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.indigo.mix(with: .white, by: 0.3) : Color.indigo
    }
}

enum TripCardText {
    /// 地址那一行不寫開頭的「〒810-0801」：卡片右欄只有 220～266pt，
    /// 郵遞區號佔掉三分之一，而它是唯一不會在旅途中被讀的部分。
    ///
    /// 逐字吃掉〒、空白、郵遞區號（只認 ASCII／全形數字與連字號）、空白，不找「第一個空白」：
    /// 「〒810-0801福岡縣…中洲 56-20」這種〒後面沒空格的寫法，找第一個空白會把
    /// 整串地址吃到只剩「56-20」。至少 3 碼數字才當郵遞區號；吃完沒東西就原樣返回。
    static func addressWithoutPostal(_ s: String) -> String {
        let c = Array(s.trimmingCharacters(in: .whitespaces))
        guard c.first == "〒" else { return s }
        let ascii: ClosedRange<Character> = "0"..."9"
        let wide: ClosedRange<Character> = "０"..."９"
        func isSpace(_ ch: Character) -> Bool { ch == " " || ch == "　" }
        func isPostal(_ ch: Character) -> Bool {
            ascii.contains(ch) || wide.contains(ch) || ch == "-" || ch == "－"
        }
        var i = 1
        while i < c.count, isSpace(c[i]) { i += 1 }
        var digits = 0
        while i < c.count, isPostal(c[i]) {
            if c[i] != "-" && c[i] != "－" { digits += 1 }
            i += 1
        }
        while i < c.count, isSpace(c[i]) { i += 1 }
        guard digits >= 3, i < c.count else { return s }
        return String(c[i...])
    }
}

/// 手寫體。字型名稱找不到時會退回系統字，不會閃退；先問一次 UIFont 有沒有，
/// 沒有就明確退回有襯線的斜體，不讓它悄悄變成一般內文字。
///
/// 一律 fixedSize：壓在固定大小照片上的字不能跟著動態字級放大（會被切）。
/// 這些字型都沒有中日文字形——中文城市名不要用它們寫。
enum TripScriptFont {
    static let cityFontName = "SnellRoundhand-Black"
    static let greetingFontName = "BradleyHandITCTT-Bold"
    private static let hasCityFont = UIFont(name: cityFontName, size: 12) != nil
    private static let hasGreetingFont = UIFont(name: greetingFontName, size: 12) != nil

    static func city(_ size: CGFloat) -> Font {
        hasCityFont
            ? Font.custom(cityFontName, fixedSize: size)
            : Font.system(size: size, weight: .semibold, design: .serif).italic()
    }

    static func greeting(_ size: CGFloat) -> Font {
        hasGreetingFont
            ? Font.custom(greetingFontName, fixedSize: size)
            : Font.system(size: size, weight: .medium, design: .serif).italic()
    }
}

// MARK: - 形狀

/// 整張卡的底：右上一顆路段膠囊 ＋ 下面的卡身，中間留 4pt 透出頁面底。
/// 照片在卡身左邊、往上一路延伸到膠囊那一列（照片本身是不透明的，
/// 所以那一塊的輪廓由照片自己構成）。
struct TripCardSilhouette: Shape {
    var capsuleLeading: CGFloat
    /// 0＝沒有路段膠囊（上下排版面）
    var capsuleHeight: CGFloat
    var gap: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let bodyTop = capsuleHeight > 0 ? rect.minY + capsuleHeight + gap : rect.minY
        p.addRoundedRect(in: CGRect(x: rect.minX, y: bodyTop,
                                    width: rect.width, height: max(0, rect.maxY - bodyTop)),
                         cornerSize: CGSize(width: 18, height: 18), style: .continuous)
        if capsuleHeight > 0 {
            p.addRoundedRect(in: CGRect(x: rect.minX + capsuleLeading, y: rect.minY,
                                        width: max(0, rect.width - capsuleLeading),
                                        height: capsuleHeight),
                             cornerSize: CGSize(width: 12, height: 12), style: .continuous)
        }
        return p
    }
}

/// 照片的輪廓：左邊與上下貼齊卡片，右緣是一條會「繞開」內容的波浪線。
///
///   y=0 ┌──────────╮            ← 頂端：寬 topWidth（讓給右上的路段膠囊），微微外傾
///       │           \
///   topBand ─────────╲_          ← S 彎往外鼓
///       │              │         ← 中段：寬 midWidth，由上往下再外傾 4pt
///       │              │
///   rowTop−4−t ───────╱‾         ← S 彎往內收（底下那排膠囊從這裡伸進來）
///       │           │
///   H   ╰───────────╯            ← 底部：寬 bottomWidth
///
/// 座標都是相對於整張卡的 rect（寬＝卡寬），所以照片欄以外的地方本來就在形狀外。
/// 第一站沒有路段（換成「出發」膠囊）時形狀一樣；完全沒有膠囊（topBand＝0）時，
/// 頂端直接從 midWidth 開始，沒有上面那個缺口。
struct TripPhotoCutShape: Shape {
    var topBand: CGFloat
    var topWidth: CGFloat
    var midWidth: CGFloat
    var bottomWidth: CGFloat
    /// 底排膠囊的上緣（nil＝沒有那一排，下面不往內收）
    var rowTop: CGFloat?
    var bottomLeftRadius: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        let h = rect.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x, y: rect.minY + y)
        }
        let t: CGFloat = 16          // S 彎的高度
        let lean: CGFloat = 4        // 中段的外傾
        let rc: CGFloat = 10         // 照片右側兩個角
        let r = min(18, h / 2)       // 左上（卡片的角）
        let rb = min(bottomLeftRadius, h / 2)

        let hasTop = topBand > 0
        let yTopEnd = hasTop ? min(topBand, h * 0.35) : 0
        let yMidStart = hasTop ? yTopEnd + t : 0
        var yMidEnd = h
        var yBotStart = h
        if let rowTop, rowTop < h - rc {
            yBotStart = max(rowTop - 4, yMidStart + t)
            yMidEnd = yBotStart - t
        }
        let midTopX = midWidth - lean
        let topRightX = hasTop ? topWidth - 6 : midTopX

        func sCurve(_ p: inout Path, from a: CGPoint, to b: CGPoint) {
            let dy = b.y - a.y
            p.addCurve(to: b,
                       control1: CGPoint(x: a.x, y: a.y + dy * 0.55),
                       control2: CGPoint(x: b.x, y: b.y - dy * 0.55))
        }

        var p = Path()
        p.move(to: pt(0, r))
        p.addQuadCurve(to: pt(r, 0), control: pt(0, 0))
        p.addLine(to: pt(topRightX - rc, 0))
        p.addQuadCurve(to: pt(topRightX, rc), control: pt(topRightX, 0))
        if hasTop {
            p.addLine(to: pt(topWidth, yTopEnd))
            sCurve(&p, from: pt(topWidth, yTopEnd), to: pt(midTopX, yMidStart))
        }
        if yBotStart < h {
            p.addLine(to: pt(midWidth, yMidEnd))
            sCurve(&p, from: pt(midWidth, yMidEnd), to: pt(bottomWidth, yBotStart))
            p.addLine(to: pt(bottomWidth, h - rc))
            p.addQuadCurve(to: pt(bottomWidth - rc, h), control: pt(bottomWidth, h))
        } else {
            p.addLine(to: pt(midWidth, h - rc))
            p.addQuadCurve(to: pt(midWidth - rc, h), control: pt(midWidth, h))
        }
        p.addLine(to: pt(rb, h))
        p.addQuadCurve(to: pt(0, h - rb), control: pt(0, h))
        p.closeSubpath()
        return p
    }
}

/// 底排膠囊的位置，交給照片的切線用（照片在背景，量得到內容、內容不會被它影響）
private struct TripChipRowAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

// MARK: - 卡片骨架

/// 一張卡的骨架。內容全部由呼叫端組好傳進來。
///
/// 圖層（後 → 前）：卡片底（含路段膠囊的底）→ 天際線 → 照片 → 內容 → 照片上的標記與招牌。
///
/// ⚠️ 這一層**不准**掛 .clipShape／.clipped：花費招牌的 popover、拖曳時畫在卡與卡
///    之間的那條線都在卡片邊界上或外面。要裁的只有照片自己（照片自己 clipShape）。
struct TripStopCardFrame: View {
    let metrics: TripCardMetrics
    let topCapsule: AnyView?
    let hero: AnyView
    let heroOverlay: AnyView
    let column: AnyView
    let chipRow: AnyView?
    let skyline: AnyView
    let spendSign: AnyView?
    /// 底下留給天際線（與花費招牌）的高度
    let bottomBand: CGFloat
    let footer: AnyView?
    let onTap: () -> Void

    @Environment(\.colorScheme) private var scheme
    /// 路段膠囊的高度。字放大時跟著長，照片頂端的缺口跟著它走。
    @ScaledMetric(relativeTo: .caption2) private var scaledCapsuleHeight: CGFloat = 26
    private let capsuleGap: CGFloat = 4

    /// 膠囊裡的字被夾在輔助第 2 級（TripLegCapsule 外面掛了 .dynamicTypeSize(...AX2)），
    /// 這個高度卻是骨架自己量的、沒有被夾——AX3～AX5 會變成 68～97pt 高的膠囊
    /// 裡只有一行 22pt 的字。所以跟內容夾在同一級：caption2 在 AX2 是 24pt，
    /// 26 × 24 / 11 ≈ 57。（骨架本身不能整個夾：標題與地址不設上限。）
    private var capsuleHeight: CGFloat { min(scaledCapsuleHeight, 57) }

    init(metrics: TripCardMetrics, topCapsule: AnyView?, hero: AnyView,
         heroOverlay: AnyView, column: AnyView, chipRow: AnyView?,
         skyline: AnyView, spendSign: AnyView?, bottomBand: CGFloat,
         footer: AnyView?, onTap: @escaping () -> Void) {
        self.metrics = metrics
        self.topCapsule = topCapsule
        self.hero = hero
        self.heroOverlay = heroOverlay
        self.column = column
        self.chipRow = chipRow
        self.skyline = skyline
        self.spendSign = spendSign
        self.bottomBand = bottomBand
        self.footer = footer
        self.onTap = onTap
    }

    var body: some View {
        Group {
            if metrics.stacked { stackedLayout } else { sideBySide }
        }
        // 整張卡可點＝打開景點卡。裡面的按鈕（路段、⊕、打卡、購物車、≡、…、
        // 天氣、電話、地圖、照片）自己吃掉點擊，其餘地方才傳到這裡。
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var shadowColor: Color {
        // 深色模式卡片是 #1C1C1E 放在 #000 上，本來就分得開；陰影在黑底上也看不到
        Color.black.opacity(scheme == .dark ? 0 : 0.07)
    }

    // MARK: 照片在左（預設）

    private var band: CGFloat { topCapsule == nil ? 0 : capsuleHeight + capsuleGap }

    private var sideBySide: some View {
        VStack(alignment: .leading, spacing: 0) {
            sideBlock
            if let footer {
                footer
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
            }
        }
        .background {
            TripCardSilhouette(capsuleLeading: metrics.photoTop + 6,
                               capsuleHeight: topCapsule == nil ? 0 : capsuleHeight,
                               gap: capsuleGap)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: shadowColor, radius: 6, x: 0, y: 2)
        }
    }

    private var sideBlock: some View {
        let m = metrics
        return VStack(alignment: .leading, spacing: 0) {
            if let topCapsule {
                topCapsule
                    .frame(height: capsuleHeight)
                    .padding(.leading, m.photoTop + 6)
                    .padding(.bottom, capsuleGap)
            }
            // 照片欄只是一塊留白：照片畫在背景，這裡把位置讓出來
            HStack(alignment: .top, spacing: 0) {
                Color.clear.frame(width: m.photo, height: 1)
                column
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 96, alignment: .top)
            if let chipRow {
                // 底排從照片內收的地方開始，比右欄多拿 P−0.82P＋2 的寬度
                chipRow
                    .padding(.leading, m.photoBottom + 8)
                    .padding(.trailing, 10)
                    .anchorPreference(key: TripChipRowAnchorKey.self, value: .bounds) { $0 }
                    .padding(.top, 6)
            }
            Color.clear.frame(height: bottomBand)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // ⚠️ 照片要掛在天際線**之前**：background 越晚掛越在後面。反過來的話天際線壓在
        //    照片上——沒有膠囊排時照片一路是 midWidth 到底，比天際線的起點（photoBottom＋4）
        //    寬 15～20pt，樓的線稿會畫在照片右下角（審查抓到）。
        .backgroundPreferenceValue(TripChipRowAnchorKey.self) { anchor in
            GeometryReader { geo in
                photoLayer(size: geo.size, rowTop: anchor.map { geo[$0].minY })
            }
        }
        .background(alignment: .bottomTrailing) {
            // 天際線只畫在底帶裡，**不往上探**。
            //
            // 膠囊排就在底帶正上方，而三顆膠囊的底都是半透明的：天際線只要比底帶高，
            // 樓的輪廓和福岡塔就會從溫度與電話號碼後面透出來（設計審查時抓到，
            // 初稿給的是「底帶＋14」）。藝術疊到要讀的字後面，違反「可以被看見，
            // 不可以被讀」。樓高與地標在 Canvas 裡本來就夾在畫布高度內。
            skyline
                .frame(width: max(0, m.cardWidth - m.photoBottom - 4),
                       height: bottomBand)
        }
        .overlay(alignment: .topLeading) {
            heroOverlay
                .frame(width: m.photoBottom, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .overlay(alignment: .bottomTrailing) {
            if let spendSign { spendSign }
        }
    }

    private func photoLayer(size: CGSize, rowTop: CGFloat?) -> some View {
        let m = metrics
        let shape = TripPhotoCutShape(topBand: band,
                                      topWidth: m.photoTop,
                                      midWidth: m.photo,
                                      bottomWidth: m.photoBottom,
                                      rowTop: rowTop,
                                      bottomLeftRadius: footer == nil ? 18 : 14)
        return hero
            .frame(width: m.photo + 2, height: size.height)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipShape(shape)
            // clipShape 不管點擊範圍；照片的點擊要跟著曲線，不能吃到右邊的內容
            .contentShape(shape)
    }

    // MARK: 上下排（字放很大時）

    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let topCapsule {
                // 固定高度（跟左右排一樣），不是 minHeight：捲動視圖在縱向給的是 nil 提議，
                // minHeight 的框裡膠囊只會長到自己的理想高度——上下多出來的那幾 pt 點下去
                // 會落到整卡的「打開景點卡」，小街圖的 Canvas 也只拿到 10pt、一筆都不畫。
                // 膠囊的 .frame(maxHeight: .infinity) 要上層給固定高度才撐得滿。
                topCapsule
                    .frame(height: capsuleHeight)
                    .background(Color(.tertiarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
            }
            ZStack(alignment: .topLeading) {
                hero
                heroOverlay
            }
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 8)
            .padding(.top, 8)
            column
                .padding(.horizontal, 12)
                .padding(.top, 10)
            if let chipRow {
                chipRow
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }
            ZStack(alignment: .bottomTrailing) {
                // 同上：天際線不往上探，免得透到膠囊排的字後面
                skyline
                    .frame(maxWidth: .infinity)
                    .frame(height: bottomBand)
                if let spendSign { spendSign }
            }
            .frame(height: bottomBand, alignment: .bottom)
            if let footer {
                footer
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: shadowColor, radius: 6, x: 0, y: 2)
        }
    }
}

// MARK: - 主圖

/// 左邊那張照片。來源：使用者的第一張照片 → 衛星快照 → 當天色的街角線稿。
///
/// 只有卡片**捲進畫面**才載入；捲出去就把圖放掉（非 lazy 的列不會被銷毀，
/// 不放的話 40 站 × 1.4MB 一直留在記憶體）。放掉的圖還在 TripHeroStore 的
/// NSCache 裡，捲回來通常是瞬間拿回來。
struct TripHeroImage: View {
    let photoURL: URL?
    let coordinate: CLLocationCoordinate2D?
    let dayColor: Color
    /// 針的顏色編號（當天色 0～5），進快取的 key
    let pinKey: Int
    let seed: Int

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var isVisible = false
    /// 現在畫著的是不是**使用者自己的照片**（false＝衛星圖、或什麼都還沒有）。
    ///
    /// 只看 image == nil 不夠：照片檔還沒從 iCloud 下來時會退到衛星圖，image 就不是
    /// nil 了，之後照片到了也不會換上去（審查抓到）。要看「顯示的是哪一層」。
    @State private var showingUserPhoto = false
    /// iCloud 照片晚到時 +1，讓 .task 重跑
    @State private var reloadToken = 0

    init(photoURL: URL?, coordinate: CLLocationCoordinate2D?, dayColor: Color,
         pinKey: Int, seed: Int) {
        self.photoURL = photoURL
        self.coordinate = coordinate
        self.dayColor = dayColor
        self.pinKey = pinKey
        self.seed = seed
    }

    private var taskKey: String {
        let source = photoURL?.lastPathComponent
            ?? coordinate.map { String(format: "%.4f,%.4f", $0.latitude, $0.longitude) }
            ?? "-"
        return "\(isVisible)|\(source)|\(pinKey)|\(reloadToken)"
    }

    var body: some View {
        // 先用 Color.clear 佔住「給多大就多大」的框，照片疊在上面再裁掉。
        // 直接放 scaledToFill 的圖，它回報的尺寸會比框大，外面包的 Button
        // 點擊範圍就會跟著溢出到右欄的標題底下——點標題變成開照片。
        Color.clear
            .overlay {
                ZStack {
                    // 墊底的線稿一直在：載入中、載入失敗、沒有座標都是它
                    TripHeroFallbackArt(color: dayColor, seed: seed,
                                        showsPickHint: photoURL == nil && coordinate == nil)
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    }
                    // 上下各壓一層暗：左上的序號、左下的手寫城市名與膠囊都是白的
                    LinearGradient(colors: [Color.black.opacity(0.28), .clear],
                                   startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.28))
                    LinearGradient(colors: [.clear, Color.black.opacity(0.5)],
                                   startPoint: UnitPoint(x: 0.5, y: 0.45), endPoint: .bottom)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .onScrollVisibilityChange(threshold: 0.01) { isVisible = $0 }
            .task(id: taskKey) { await load() }
            .onReceive(NotificationCenter.default.publisher(for: .cloudSyncPhotosDidUpdate)) { _ in
                // 有照片、但現在畫的不是它（衛星圖墊著，或什麼都沒有）→ 再試一次。
                // 捲在畫面外的不用管：捲回來時 .task 本來就會重跑。
                if isVisible, photoURL != nil, !showingUserPhoto { reloadToken += 1 }
            }
    }

    @MainActor
    private func load() async {
        guard isVisible else {
            clear()
            return
        }
        let store = TripHeroStore.shared
        if let url = photoURL, let img = await store.photo(url) {
            show(img, userPhoto: true)
            return
        }
        guard !Task.isCancelled else { return }
        guard let c = coordinate else {
            // 沒有座標：墊底的線稿就是答案。照片被刪掉的時候，舊的那張也要拿掉
            clear()
            return
        }
        // 同一個座標再跑一次（iCloud 通知觸發、照片仍沒下來）會直接從記憶體快取拿到，不會再拍
        if let img = await store.satellite(c, pin: UIColor(dayColor), pinKey: pinKey,
                                           scale: displayScale) {
            show(img, userPhoto: false)
        } else if !Task.isCancelled {
            // 拍不到（沒網路、被節流）：露出墊底的線稿，不要留著上一個位置的圖
            clear()
        }
    }

    @MainActor
    private func clear() {
        image = nil
        showingUserPhoto = false
    }

    @MainActor
    private func show(_ img: UIImage, userPhoto: Bool) {
        guard !Task.isCancelled else { return }
        showingUserPhoto = userPhoto
        withAnimation(.easeOut(duration: 0.2)) { image = img }
    }
}

/// 沒有照片時墊在底下的街角線稿：當天色的深色漸層，疊白色、很淡的街道。
/// 種子取站序號，每一站的街都不一樣（同一張圖重複 40 次是壁紙）。
struct TripHeroFallbackArt: View {
    let color: Color
    let seed: Int
    /// 沒有座標：中間寫「選位置」，點照片就去選
    let showsPickHint: Bool

    init(color: Color, seed: Int, showsPickHint: Bool) {
        self.color = color
        self.seed = seed
        self.showsPickHint = showsPickHint
    }

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                Self.draw(&ctx, size: size, color: color, seed: seed)
            }
            if showsPickHint {
                VStack(spacing: 3) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 16, weight: .semibold))
                    Text("選位置")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(Color.white.opacity(0.9))
            }
        }
    }

    private static func draw(_ ctx: inout GraphicsContext, size: CGSize,
                             color: Color, seed: Int) {
        let rect = CGRect(origin: .zero, size: size)
        ctx.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [color.mix(with: .black, by: 0.30),
                              color.mix(with: .black, by: 0.62)]),
            startPoint: .zero,
            endPoint: CGPoint(x: size.width * 0.5, y: size.height)))
        var r = InkRandom(7177 + seed * 53)
        let street = GraphicsContext.Shading.color(Color.white.opacity(0.13))
        var y = CGFloat(10 + r.next() * 14)
        while y < size.height {
            var p = Path()
            let tilt = CGFloat(r.next() * 10 - 5)
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: size.width, y: y + tilt))
            let w: CGFloat = r.next() > 0.7 ? 2.4 : 1
            ctx.stroke(p, with: street, style: StrokeStyle(lineWidth: w))
            y += CGFloat(16 + r.next() * 20)
        }
        var x = CGFloat(8 + r.next() * 12)
        while x < size.width {
            var p = Path()
            let tilt = CGFloat(r.next() * 8 - 4)
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x + tilt, y: size.height))
            let w: CGFloat = r.next() > 0.75 ? 2.2 : 0.9
            ctx.stroke(p, with: street, style: StrokeStyle(lineWidth: w))
            x += CGFloat(14 + r.next() * 18)
        }
        var avenue = Path()
        avenue.move(to: CGPoint(x: -4, y: size.height * CGFloat(0.55 + r.next() * 0.3)))
        avenue.addLine(to: CGPoint(x: size.width + 4, y: size.height * CGFloat(0.1 + r.next() * 0.3)))
        ctx.stroke(avenue, with: .color(Color.white.opacity(0.2)),
                   style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
    }
}

// MARK: - 照片上的標記

/// 左上的序號圈（必去的話右上角一顆星）。壓在照片上，所以底色壓暗、加白環與陰影。
struct TripCardBadge: View {
    let number: Int
    let color: Color
    let isMustVisit: Bool
    @ScaledMetric(relativeTo: .caption) private var d: CGFloat = 22

    init(number: Int, color: Color, isMustVisit: Bool) {
        self.number = number
        self.color = color
        self.isMustVisit = isMustVisit
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Text("\(number)")
                .font(.system(size: d * 0.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: d, height: d)
                .background(Circle().fill(TripInk.solid(color)))
                .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
            if isMustVisit {
                Image(systemName: "star.fill")
                    .font(.system(size: d * 0.36))
                    .foregroundStyle(.orange)
                    .padding(1.5)
                    .background(Circle().fill(Color.white))
                    .offset(x: 5, y: -5)
            }
        }
        // 標題的輔助說明已經唸「第 N 站」（與必去）
        .accessibilityHidden(true)
        // 點到序號圈要落到底下的照片（使用者照片＝放大）。沒有這行的話它會吃掉
        // 點擊、往上找到整張卡的 onTapGesture，變成開景點卡（審查抓到）。
        .allowsHitTesting(false)
    }
}

/// 照片張數（兩張以上才出現：只有一張時，主圖就是那一張）
struct TripPhotoCountTag: View {
    let count: Int
    init(count: Int) { self.count = count }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 8, weight: .bold))
            Text("\(count)")
                .font(.system(size: 9, weight: .bold).monospacedDigit())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(Color.black.opacity(0.45), in: Capsule())
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// 「🛏 實際入住」：這一站的時間是現場打卡的，不是排出來的（原本時間欄的「實際」）
struct TripCheckInTag: View {
    let text: String
    let icon: String
    let color: Color
    @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = 10

    init(text: String, icon: String, color: Color) {
        self.text = text
        self.icon = icon
        self.color = color
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: size * 0.9, weight: .bold))
            Text(text).font(.system(size: size, weight: .bold))
        }
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(.white)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Capsule().fill(TripInk.solid(color)))
        .overlay(Capsule().stroke(Color.white.opacity(0.6), lineWidth: 0.75))
        // 時間已經不在它上面了（在右邊的狀態面板），所以不能寫「上面的時間」
        .accessibilityLabel(text + "：狀態面板上的時間是現場打卡的實際時間")
        // 標籤不是按鈕：點到它要落到底下的照片
        .allowsHitTesting(false)
    }
}

/// 照片左下手寫的城市名（「Fukuoka」＋「JAPAN」）。純裝飾：
/// 天氣膠囊已經寫了中文城市名，VoiceOver 不唸這一行。
struct TripCityScript: View {
    let place: TripPlaceName.Place?
    let coordinate: CLLocationCoordinate2D?
    let maxWidth: CGFloat
    @StateObject private var names = TripPlaceNameStore.shared
    @State private var isVisible = false

    init(place: TripPlaceName.Place?, coordinate: CLLocationCoordinate2D?, maxWidth: CGFloat) {
        self.place = place
        self.coordinate = coordinate
        self.maxWidth = maxWidth
    }

    var body: some View {
        Group {
            if let r = names.resolved(place: place, coordinate: coordinate), maxWidth >= 40 {
                VStack(alignment: .leading, spacing: -2) {
                    Text(r.romaji)
                        .font(TripScriptFont.city(22))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        // Snell 的收筆會超出字框，留一點不讓照片的切線把它切掉
                        .padding(.trailing, 4)
                    Text(r.country)
                        .font(.system(size: 8, weight: .semibold))
                        .tracking(3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.leading, 6)
                }
                .foregroundStyle(.white)
                .shadow(color: Color.black.opacity(0.45), radius: 2, x: 0, y: 1)
                .frame(maxWidth: maxWidth, alignment: .leading)
            } else {
                // 要有一點大小，onScrollVisibilityChange 才量得到它
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .onScrollVisibilityChange(threshold: 0.01) { isVisible = $0 }
        .task(id: isVisible) {
            guard isVisible else { return }
            await names.resolveIfNeeded(place: place, coordinate: coordinate)
        }
        .accessibilityHidden(true)
        // 純裝飾：點到手寫字要落到底下的照片（onScrollVisibilityChange 看的是幾何，不受影響）
        .allowsHitTesting(false)
    }
}

// MARK: - 路段膠囊（原本兩站之間那一列）

struct TripLegCapsule: View {
    let icon: String
    /// 這一段被單獨指定過方式才有（例「步行」）：v25.403 承諾過的記號
    let modeLabel: String?
    let text: String
    /// 第一站的「出發後 25 分抵達」
    let note: String?
    let isEstimated: Bool
    /// 指定抵達趕不上：整顆膠囊轉紅（細節寫在狀態面板底下）
    let isLate: Bool
    let color: Color
    let art: TripLegStreetArt.Style
    let seed: Int
    let a11yLabel: String
    let insertA11yLabel: String
    let onOpen: () -> Void
    let onInsert: () -> Void

    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .caption2) private var textSize: CGFloat = 10

    init(icon: String, modeLabel: String?, text: String, note: String?,
         isEstimated: Bool, isLate: Bool, color: Color,
         art: TripLegStreetArt.Style, seed: Int,
         a11yLabel: String, insertA11yLabel: String,
         onOpen: @escaping () -> Void, onInsert: @escaping () -> Void) {
        self.icon = icon
        self.modeLabel = modeLabel
        self.text = text
        self.note = note
        self.isEstimated = isEstimated
        self.isLate = isLate
        self.color = color
        self.art = art
        self.seed = seed
        self.a11yLabel = a11yLabel
        self.insertA11yLabel = insertA11yLabel
        self.onOpen = onOpen
        self.onInsert = onInsert
    }

    var body: some View {
        HStack(spacing: 0) {
            // 膠囊自己吃掉點擊：不然會被整張卡的「打開景點卡」吃走
            Button(action: onOpen) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: textSize, weight: .bold))
                    if let modeLabel {
                        Text(modeLabel)
                            .font(.system(size: textSize * 0.9, weight: .bold))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(color.opacity(0.14), in: Capsule())
                            .foregroundStyle(TripInk.text(color, scheme))
                    }
                    Text(text)
                        .font(.system(size: textSize, weight: .semibold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if let note {
                        Text(note)
                            .font(.system(size: textSize * 0.9, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    if isEstimated {
                        Text("估")
                            .font(.system(size: textSize * 0.8, weight: .bold))
                            .padding(.horizontal, 3).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.18), in: Capsule())
                            .foregroundStyle(TripInk.text(.orange, scheme))
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: textSize * 0.8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(isLate ? Color.red : Color.secondary)
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            .accessibilityLabel(a11yLabel)

            // 裝飾用的小街道圖：填滿文字與 ⊕ 之間（設計稿的地圖鋪在中間、⊕ 貼右緣），
            // 讓位的時候它先縮（左邊那顆按鈕是 layoutPriority(1)）
            TripLegStreetArt(color: color, seed: seed, style: art, icon: icon)
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 3)

            Button(action: onInsert) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 17))
                    .foregroundStyle(TripInk.text(color, scheme))
                    .frame(width: 34)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(insertA11yLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 整顆膠囊都是「這一段路」：點小地圖、車子圓章、空白處一樣打開路段詳情
        // （v25.407 起整列都能點；只讓左邊文字那段能點，等於把一半的面積
        // 改成「開景點卡」）。左邊那顆按鈕與 ⊕ 是子層，點擊仍然先給它們。
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .background {
            if isLate {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.red.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.red.opacity(0.35), lineWidth: 1))
            }
        }
    }
}

/// 路段膠囊裡那一小塊街道插畫。**不打任何地圖請求**：40 段各打一次快照會被節流。
/// 街廓是種子化的灰塊，路線是當天色——看得出「從這裡到那裡」，讀不出任何東西。
struct TripLegStreetArt: View {
    enum Style { case road, walk, flight, start }

    let color: Color
    let seed: Int
    let style: Style
    let icon: String

    init(color: Color, seed: Int, style: Style, icon: String) {
        self.color = color
        self.seed = seed
        self.style = style
        self.icon = icon
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Canvas { ctx, size in
                Self.draw(&ctx, size: size, color: color, seed: seed, style: style)
            }
            // 左邊淡入：插畫是從膠囊的文字後面「長出來」的，不是一塊貼上去的圖
            .mask {
                LinearGradient(colors: [.clear, .black, .black],
                               startPoint: .leading, endPoint: .trailing)
            }
            // 路線終點那顆交通方式的圓章（設計稿的車子）
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color(.systemBackground)))
                .shadow(color: Color.black.opacity(0.18), radius: 2, x: 0, y: 1)
                .padding(.trailing, 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func draw(_ ctx: inout GraphicsContext, size: CGSize,
                             color: Color, seed: Int, style: Style) {
        guard size.width > 30, size.height > 10 else { return }
        var r = InkRandom(5381 + seed * 97)
        let block = GraphicsContext.Shading.color(Color(.quaternarySystemFill))
        var x: CGFloat = 0
        while x < size.width {
            let w = CGFloat(9 + r.next() * 14)
            var y: CGFloat = 1
            while y < size.height - 1 {
                let h = CGFloat(5 + r.next() * 7)
                let rect = CGRect(x: x, y: y,
                                  width: min(w, size.width - x),
                                  height: min(h, size.height - 1 - y))
                if rect.width > 1, rect.height > 1 {
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: block)
                }
                y += h + 2.5
            }
            x += w + 2.5
        }

        let start = CGPoint(x: size.width * 0.22, y: size.height - 5)
        let end = CGPoint(x: size.width - 13, y: size.height * 0.5)
        var route = Path()
        route.move(to: start)
        switch style {
        case .flight:
            route.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2, y: 0))
        case .road, .walk, .start:
            let bend = start.x + (end.x - start.x) * CGFloat(0.3 + r.next() * 0.25)
            route.addLine(to: CGPoint(x: bend, y: start.y))
            route.addLine(to: CGPoint(x: bend + 6, y: end.y))
            route.addLine(to: end)
        }
        let dash: [CGFloat]
        switch style {
        case .flight: dash = [3, 2.5]
        case .walk: dash = [0.1, 3.2]
        case .road, .start: dash = []
        }
        ctx.stroke(route, with: .color(color.opacity(0.9)),
                   style: StrokeStyle(lineWidth: 2.2, lineCap: .round,
                                      lineJoin: .round, dash: dash))
        ctx.fill(Path(ellipseIn: CGRect(x: start.x - 3.2, y: start.y - 3.2,
                                        width: 6.4, height: 6.4)),
                 with: .color(Color.white))
        ctx.fill(Path(ellipseIn: CGRect(x: start.x - 2.2, y: start.y - 2.2,
                                        width: 4.4, height: 4.4)),
                 with: .color(color))
    }
}

// MARK: - 狀態面板

/// 「✓ 已抵達 23:05 ｜ 🛏 過夜・隔天出發 07:00 ›」
///
/// 左半＝抵達，右半＝離開。小標在上、大字時間在下（設計稿的樣子）。
/// 打卡的那顆圈就是左半的圖示：一顆按鈕走完 沒到 → 到了 → 玩完了 → 沒到
/// （v25.421 的設計，當天站在門口時按鈕愈少愈好）。
///   • 沒到：空心圈
///   • 到了：當天色實心圈＋✓（設計稿「✓ 已抵達」）
///   • 玩完了：左邊一樣是 ✓，**右半**換成 ✓「已離開」
/// 未來的日子左半是不能按的時鐘（整趟二十幾站都掛一顆圈只是雜訊）。
/// 面板其餘地方不是按鈕：點下去跟點卡片一樣打開景點卡，右邊的 › 是提示。
struct TripStatusPanel: View {
    struct Half {
        let glyph: String
        let label: String
        let time: String
        /// 這半邊的底色與圖示色
        let tint: Color
        /// 大字時間的顏色（已處理對比；趕不上時是紅）
        let ink: Color
        let showsLock: Bool
        let a11y: String
    }

    struct CheckIn {
        let state: TripStop.CheckInState
        let a11y: String
        let action: () -> Void
    }

    let left: Half
    let right: Half
    /// 已經打卡離開：右半的圖示換成實心 ✓
    let rightDone: Bool
    let color: Color
    let checkIn: CheckIn?

    @ScaledMetric(relativeTo: .callout) private var timeSize: CGFloat = 16
    @ScaledMetric(relativeTo: .caption2) private var labelSize: CGFloat = 10
    @ScaledMetric(relativeTo: .callout) private var glyph: CGFloat = 22

    init(left: Half, right: Half, rightDone: Bool, color: Color, checkIn: CheckIn?) {
        self.left = left
        self.right = right
        self.rightDone = rightDone
        self.color = color
        self.checkIn = checkIn
    }

    var body: some View {
        // 先試左右並排（設計稿）；並排的「理想寬度」放不下時，先把右半的字縮一號再試，
        // 還是放不下才改成上下兩列。
        //
        // 為什麼不是只靠 minimumScaleFactor：系統字放大時（AX2、375～393 寬的上下排版面），
        // 左半是 fixedSize、右半只剩 60～95pt，連縮到 0.8 都放不下，離開時間會被截成
        // 「0…」、「翌 01:10」被截（審查抓到）。截掉的是要讀的時間，不能接受。
        // 中間那個「縮一號」的候選是給預設字級的少數情況（指定抵達＋跨午夜離開、
        // 375 寬）：ViewThatFits 只看理想寬度，不知道 minimumScaleFactor 還縮得動，
        // 沒有這一層的話那幾張卡會直接變成上下兩列、多高 40pt。
        //
        // 這裡可以用 ViewThatFits：面板沒有 @StateObject、沒有 .task，三個候選各建一份
        // 只是多量一次，不會重複載入任何東西（天氣膠囊就不行，見 chipRow 的註解）。
        ViewThatFits(in: .horizontal) {
            pairedRow(rightScale: 1)
            pairedRow(rightScale: 0.85)
            VStack(spacing: 0) {
                leftHalf
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(left.tint.opacity(0.10))
                Rectangle()
                    .fill(Color(.separator).opacity(0.5))
                    .frame(height: 0.5)
                    .padding(.horizontal, 8)
                rightHalf(scale: 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(right.tint.opacity(0.08))
            }
        }
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// 左右並排（設計稿）。兩半一樣高：左半取理想寬度，右半吃剩下的。
    private func pairedRow(rightScale: CGFloat) -> some View {
        HStack(spacing: 0) {
            leftHalf
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxHeight: .infinity)
                .background(left.tint.opacity(0.10))
            Rectangle()
                .fill(Color(.separator).opacity(0.5))
                .frame(width: 0.5)
                .padding(.vertical, 8)
            rightHalf(scale: rightScale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(right.tint.opacity(0.08))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 左半：抵達（打卡鈕＋小標＋大字時間）
    private var leftHalf: some View {
        HStack(spacing: 6) {
            leftGlyph
            VStack(alignment: .leading, spacing: 0) {
                Text(left.label)
                    .font(.system(size: labelSize, weight: .semibold))
                    .foregroundStyle(left.ink)
                    .lineLimit(1)
                HStack(spacing: 2) {
                    if left.showsLock {
                        Image(systemName: "lock.fill")
                            .font(.system(size: labelSize * 0.8, weight: .bold))
                    }
                    Text(left.time)
                        .font(.system(size: timeSize, weight: .bold, design: .rounded)
                            .monospacedDigit())
                }
                .foregroundStyle(left.ink)
                .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(left.a11y)
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.vertical, 5)
    }

    /// 右半：離開（停留／過夜／已離開＋大字時間＋›）。scale＜1＝字縮一號的候選
    private func rightHalf(scale: CGFloat) -> some View {
        HStack(spacing: 6) {
            rightGlyph
            VStack(alignment: .leading, spacing: 0) {
                Text(right.label)
                    .font(.system(size: labelSize * scale, weight: .semibold))
                    .foregroundStyle(right.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(right.time)
                    .font(.system(size: timeSize * scale, weight: .bold, design: .rounded)
                        .monospacedDigit())
                    .foregroundStyle(right.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(right.a11y)
            Image(systemName: "chevron.right")
                .font(.system(size: labelSize * 0.9, weight: .bold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var leftGlyph: some View {
        if let checkIn {
            Button(action: checkIn.action) {
                checkInFace(checkIn.state)
                    .frame(width: glyph + 8, height: glyph + 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(checkIn.a11y)
        } else {
            disc(left.glyph, tint: left.tint, filled: false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var rightGlyph: some View {
        if rightDone {
            disc("checkmark", tint: right.tint, filled: true)
                .accessibilityHidden(true)
        } else {
            disc(right.glyph, tint: right.tint, filled: false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func checkInFace(_ state: TripStop.CheckInState) -> some View {
        switch state {
        case .notArrived:
            Circle()
                .stroke(Color.secondary.opacity(0.5), lineWidth: 1.6)
                .frame(width: glyph, height: glyph)
        case .arrived, .departed:
            ZStack {
                Circle().fill(TripInk.solid(color))
                Image(systemName: "checkmark")
                    .font(.system(size: glyph * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: glyph, height: glyph)
        }
    }

    private func disc(_ name: String, tint: Color, filled: Bool) -> some View {
        ZStack {
            Circle().fill(filled ? TripInk.solid(tint) : tint.opacity(0.16))
            Image(systemName: name)
                .font(.system(size: glyph * 0.45, weight: .bold))
                .foregroundStyle(filled ? Color.white : tint)
        }
        .frame(width: glyph, height: glyph)
    }
}

// MARK: - 提醒行（原本 stopChips 裡的警告與打卡結果）

struct TripCardFlag: Identifiable {
    enum Tone { case day, red, orange, green, neutral }
    let id: String
    let icon: String
    let text: String
    let tone: Tone
    var action: (() -> Void)? = nil
}

/// 狀態面板底下的幾行小字。用一行一行而不是膠囊：
/// 右欄只有 220～266pt，「實際停留 10 小時 34 分（多 9 小時 34 分）」放不進一顆膠囊。
struct TripCardFlagList: View {
    let flags: [TripCardFlag]
    let dayColor: Color
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = 10

    init(flags: [TripCardFlag], dayColor: Color) {
        self.flags = flags
        self.dayColor = dayColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(flags) { f in row(f) }
        }
    }

    @ViewBuilder
    private func row(_ f: TripCardFlag) -> some View {
        if let action = f.action {
            Button(action: action) {
                line(f).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            line(f)
        }
    }

    private func line(_ f: TripCardFlag) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: f.icon)
                .font(.system(size: size * 0.9, weight: .bold))
            Text(f.text)
                .font(.system(size: size, weight: .semibold))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tint(f.tone))
    }

    private func tint(_ tone: TripCardFlag.Tone) -> Color {
        switch tone {
        case .red: return .red
        case .orange: return TripInk.text(.orange, scheme)
        case .green: return TripInk.text(.green, scheme)
        case .day: return TripInk.text(dayColor, scheme)
        case .neutral: return .secondary
        }
    }
}

// MARK: - 底排：查看地圖

struct TripMapChip: View {
    enum Style { case full, short, icon }

    let style: Style
    let color: Color
    let minHeight: CGFloat?
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    init(style: Style, color: Color, minHeight: CGFloat?, action: @escaping () -> Void) {
        self.style = style
        self.color = color
        self.minHeight = minHeight
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "map")
                    .font(.system(size: 9, weight: .semibold))
                if style != .icon {
                    Text(style == .full ? "查看地圖" : "地圖")
                        .font(.system(size: 10, weight: .bold))
                }
                if style == .full {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                }
            }
            .fixedSize()
            .foregroundStyle(TripInk.text(color, scheme))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .frame(minHeight: minHeight)
            .background(color.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.55), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("用 Apple 地圖開啟")
    }
}

// MARK: - 子地點（從 ItemRow 搬出來，v25.399 起的功能）

/// 卡片最底下、照片下方的全寬一列。放在照片下面而不是右欄：
/// 展開時才不會把滿高的照片拉長、也不會被擠在 220pt 的右欄裡。
///
/// 從 ItemRow 的 disclosureSection／disclosureLine 原樣搬過來（那兩個是
/// ItemRow 的 private 成員，狀態也是它的 @State），兩層展開的行為不變。
struct TripSubSpotList: View {
    let items: [ItemDisclosure]
    let color: Color
    /// 子地點加總超過停留時間：膠囊改紅框（細節在面板底下那一行）
    let isOver: Bool

    @State private var listOpen = false
    @State private var openBodies: Set<String> = []

    init(items: [ItemDisclosure], color: Color, isOver: Bool) {
        self.items = items
        self.color = color
        self.isOver = isOver
    }

    private var tint: Color { isOver ? .red : color }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { listOpen.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 9, weight: .bold))
                    Text("子地點 \(items.count) 項")
                        .font(.system(size: 10, weight: .bold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(listOpen ? 90 : 0))
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(tint.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(tint.opacity(isOver ? 0.6 : 0.22), lineWidth: isOver ? 1 : 0.6))
                .foregroundStyle(tint)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("子地點 \(items.count) 項" + (isOver ? "，加起來超過停留時間" : ""))
            .accessibilityHint(listOpen ? "點兩下收起" : "點兩下展開")

            if listOpen {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items) { d in line(d) }
                }
                .padding(.leading, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func line(_ d: ItemDisclosure) -> some View {
        let open = openBodies.contains(d.id)
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    if open { openBodies.remove(d.id) } else { openBodies.insert(d.id) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(color.opacity(0.7))
                        .frame(width: 10)
                    if let badge = d.badge, !badge.isEmpty {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(color.opacity(0.12), in: Capsule())
                            .foregroundStyle(color)
                    }
                    Text(d.title.isEmpty ? "（未填標題）" : d.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(open ? 3 : 1)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                Text(d.body.isEmpty ? "（未填內容）" : d.body)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
        .padding(.leading, 2)
    }
}

// MARK: - 底部的線稿天際線

/// 天際線上會出現的地標。只畫在「進入這座城市的那一站」（前一站在別的城市，
/// 或是當天第一站）——二十站都在福岡的話，福岡塔只出現一次，不是二十次。
enum TripLandmark {
    case tower, bridge, pagoda, wheel

    /// 只收畫得出、認得出的。台北 101 是一節一節的，不是這座塔，所以不收。
    static func forCity(_ zh: String?) -> [TripLandmark] {
        guard let zh else { return [] }
        switch zh {
        case "福岡": return [.tower, .bridge]
        case "東京", "大阪", "名古屋", "札幌": return [.tower]
        case "神戶": return [.tower, .bridge]
        case "橫濱": return [.wheel, .bridge]
        case "京都", "奈良", "廿日市": return [.pagoda]
        case "北九州", "下關", "長崎": return [.bridge]
        default: return []
        }
    }
}

/// 卡片底部那一條淡淡的城市線稿（設計稿右下的樓群、塔、斜張橋）。
///
/// 規矩沿用 v25.505～513：**可以被看見，不可以被讀**——要讀的東西（金額）是疊在
/// 上面的招牌，不畫進這裡。**每一站都不一樣**：樓群的種子取站序號。
/// 「Have a nice trip!」只出現在整趟的第一站（送行的話，說一次）；
/// 小飛機與虛線航線出現在第一站，以及「下一段要搭飛機」的那一站。
///
/// 畫布的高度就是卡片的底帶（沒花費 14、有花費 28、第一站 26），所有樓與地標都夾在
/// 畫布裡、**不往上探**：正上方就是膠囊排，膠囊的底是半透明的。
/// 地標擺在左邊 12～32% 的位置，右下角留給花費招牌（它「掛在建築物上」）。
struct TripCardSkyline: View {
    let color: Color
    let seed: Int
    let landmarks: [TripLandmark]
    let planeTrail: Bool
    let greeting: Bool

    init(color: Color, seed: Int, landmarks: [TripLandmark], planeTrail: Bool, greeting: Bool) {
        self.color = color
        self.seed = seed
        self.landmarks = landmarks
        self.planeTrail = planeTrail
        self.greeting = greeting
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Canvas { ctx, size in
                Self.draw(&ctx, size: size, color: color, seed: seed,
                          landmarks: landmarks, planeTrail: planeTrail)
            }
            if greeting {
                Text("Have a nice trip!")
                    .font(TripScriptFont.greeting(12))
                    .foregroundStyle(color.opacity(0.75))
                    .rotationEffect(.degrees(-7))
                    .padding(.bottom, 5)
                    .offset(x: -12)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func draw(_ ctx: inout GraphicsContext, size: CGSize, color: Color,
                             seed: Int, landmarks: [TripLandmark], planeTrail: Bool) {
        guard size.width > 40, size.height > 12 else { return }
        var r = InkRandom(20117 + seed * 131)
        let ground = size.height - 1.5
        let line = color.opacity(0.30)
        let faint = color.opacity(0.16)
        let outline = StrokeStyle(lineWidth: 0.8, lineCap: .round, lineJoin: .round)

        // 地面：從左邊淡入，不切一條硬邊
        var base = Path()
        base.move(to: CGPoint(x: 0, y: ground))
        base.addLine(to: CGPoint(x: size.width, y: ground))
        ctx.stroke(base, with: .linearGradient(Gradient(colors: [.clear, line, faint]),
                                               startPoint: .zero,
                                               endPoint: CGPoint(x: size.width, y: 0)),
                   style: StrokeStyle(lineWidth: 0.8))

        // 地標先佔位置，樓群繞開它
        var reserved: [ClosedRange<CGFloat>] = []
        var lx = size.width * CGFloat(0.12 + r.next() * 0.2)
        for mark in landmarks {
            let w = width(of: mark)
            if lx + w > size.width - 4 { break }
            drawLandmark(mark, at: lx, ground: ground, height: size.height, ctx: &ctx, color: color)
            reserved.append((lx - 3)...(lx + w + 3))
            lx += w + CGFloat(18 + r.next() * 30)
        }

        // 樓群：只有輪廓，窗是幾條短虛線（整片亮著的點陣窗會像資料）
        var x: CGFloat = size.width * 0.02
        while x < size.width - 6 {
            let w = CGFloat(6 + r.next() * 12)
            if reserved.contains(where: { $0.overlaps(x...(x + w)) }) {
                x += w + 3
                continue
            }
            let roll = r.next()
            let tall: CGFloat = roll > 0.8 ? 1.0 : (roll > 0.45 ? 0.6 : 0.32)
            let h = min(size.height - 4, 5 + tall * CGFloat(6 + r.next() * 20))
            let rect = CGRect(x: x, y: ground - h, width: w, height: h)
            ctx.fill(Path(rect), with: .color(color.opacity(0.05)))
            ctx.stroke(Path(rect), with: .color(line), style: outline)
            var wy = rect.minY + 3
            while wy < ground - 3 {
                if r.next() > 0.45 {
                    var win = Path()
                    win.move(to: CGPoint(x: rect.minX + 2, y: wy))
                    win.addLine(to: CGPoint(x: rect.maxX - 2, y: wy))
                    ctx.stroke(win, with: .color(faint),
                               style: StrokeStyle(lineWidth: 0.6, dash: [1.4, 1.6]))
                }
                wy += 3.5
            }
            x += w + CGFloat(1.5 + r.next() * 6)
        }

        if planeTrail { drawPlane(&ctx, size: size, color: color, random: &r) }
    }

    private static func width(of m: TripLandmark) -> CGFloat {
        switch m {
        case .tower: return 14
        case .bridge: return 62
        case .pagoda: return 18
        case .wheel: return 30
        }
    }

    private static func drawLandmark(_ m: TripLandmark, at x: CGFloat, ground: CGFloat,
                                     height: CGFloat, ctx: inout GraphicsContext,
                                     color: Color) {
        let top = max(2, ground - (height - 4))
        var p = Path()
        switch m {
        case .tower:
            // 收斂的塔身＋展望台＋天線，加三道橫帶
            let cx = x + 7
            let h = ground - top
            let deckY = top + h * 0.32
            let neckY = top + h * 0.12
            p.move(to: CGPoint(x: x, y: ground))
            p.addLine(to: CGPoint(x: cx - 2, y: deckY))
            p.addLine(to: CGPoint(x: cx - 1, y: neckY))
            p.addLine(to: CGPoint(x: cx + 1, y: neckY))
            p.addLine(to: CGPoint(x: cx + 2, y: deckY))
            p.addLine(to: CGPoint(x: x + 14, y: ground))
            p.addRect(CGRect(x: cx - 4, y: deckY - 3, width: 8, height: 3))
            p.move(to: CGPoint(x: cx, y: neckY))
            p.addLine(to: CGPoint(x: cx, y: top))
            for i in 1...3 {
                let fy = deckY + (ground - deckY) * CGFloat(i) / 4
                let half = 2 + 5 * CGFloat(i) / 4
                p.move(to: CGPoint(x: cx - half, y: fy))
                p.addLine(to: CGPoint(x: cx + half, y: fy))
            }
        case .bridge:
            // 斜張橋：一座橋塔、兩邊各四條斜索
            let deckY = ground - 5
            let px = x + 31
            let pTop = max(top, ground - 24)
            p.move(to: CGPoint(x: x, y: deckY))
            p.addLine(to: CGPoint(x: x + 62, y: deckY))
            p.move(to: CGPoint(x: px, y: ground))
            p.addLine(to: CGPoint(x: px, y: pTop))
            for k: CGFloat in [6, 13, 20, 27] {
                p.move(to: CGPoint(x: px, y: pTop + 2))
                p.addLine(to: CGPoint(x: px - k, y: deckY))
                p.move(to: CGPoint(x: px, y: pTop + 2))
                p.addLine(to: CGPoint(x: px + k, y: deckY))
            }
            p.move(to: CGPoint(x: x + 6, y: deckY))
            p.addLine(to: CGPoint(x: x + 6, y: ground))
            p.move(to: CGPoint(x: x + 56, y: deckY))
            p.addLine(to: CGPoint(x: x + 56, y: ground))
        case .pagoda:
            // 五重塔：屋簷兩端上翹
            let cx = x + 9
            let tierH = max(3, min(5, (ground - top - 6) / 5))
            var y = ground
            for i in 0..<5 {
                let half = 8 - CGFloat(i) * 1.2
                p.move(to: CGPoint(x: cx - half - 1.5, y: y - tierH + 1))
                p.addQuadCurve(to: CGPoint(x: cx + half + 1.5, y: y - tierH + 1),
                               control: CGPoint(x: cx, y: y - tierH + 3))
                p.move(to: CGPoint(x: cx - half + 1.5, y: y))
                p.addLine(to: CGPoint(x: cx - half + 1.5, y: y - tierH + 2))
                p.move(to: CGPoint(x: cx + half - 1.5, y: y))
                p.addLine(to: CGPoint(x: cx + half - 1.5, y: y - tierH + 2))
                y -= tierH
            }
            p.move(to: CGPoint(x: cx, y: y + 1))
            p.addLine(to: CGPoint(x: cx, y: max(top, y - 6)))
        case .wheel:
            // 摩天輪
            let radius = max(4, min(13, (ground - top) / 2 - 1))
            let c = CGPoint(x: x + 15, y: ground - radius - 3)
            p.addEllipse(in: CGRect(x: c.x - radius, y: c.y - radius,
                                    width: radius * 2, height: radius * 2))
            for k in 0..<8 {
                let a = Double(k) * Double.pi / 4
                p.move(to: c)
                p.addLine(to: CGPoint(x: c.x + radius * CGFloat(cos(a)),
                                      y: c.y + radius * CGFloat(sin(a))))
            }
            p.move(to: c)
            p.addLine(to: CGPoint(x: c.x - 7, y: ground))
            p.move(to: c)
            p.addLine(to: CGPoint(x: c.x + 7, y: ground))
        }
        ctx.stroke(p, with: .color(color.opacity(0.36)),
                   style: StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round))
    }

    private static func drawPlane(_ ctx: inout GraphicsContext, size: CGSize,
                                  color: Color, random r: inout InkRandom) {
        let start = CGPoint(x: size.width * 0.18, y: size.height * 0.78)
        let end = CGPoint(x: size.width * CGFloat(0.62 + r.next() * 0.12),
                          y: size.height * 0.22)
        var trail = Path()
        trail.move(to: start)
        trail.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2,
                                                     y: size.height * 0.9))
        ctx.stroke(trail, with: .color(color.opacity(0.32)),
                   style: StrokeStyle(lineWidth: 0.9, lineCap: .round, dash: [3, 3]))
        var plane = ctx.resolve(Image(systemName: "airplane"))
        plane.shading = .color(color.opacity(0.55))
        var g = ctx
        g.translateBy(x: end.x + 6, y: end.y - 1)
        g.rotate(by: .degrees(-24))
        g.draw(plane, in: CGRect(x: -6, y: -6, width: 12, height: 12))
    }
}

// MARK: - 跑馬燈標題（v25.517）

/// 一行放不下的名字用跑馬燈，不折行（使用者指定：「不做折行，可以用跑馬燈方式」）。
///
/// 放得下就是一般的一行字，不會動。放不下才捲：停 2 秒讓人先讀開頭，
/// 再以每秒 32pt 往左捲，字尾後面隔一段空白接著第二份，捲到第二份的開頭
/// 剛好回到原位——那一格跟第一格長得一模一樣，所以接回去看不出跳動。
///
/// ⚠️ 用 TimelineView 從「現在幾點」算出位移，不用 withAnimation(.repeatForever)。
///    repeatForever 一旦開始就很難停、寬度一變（轉向、字級）就會從錯的位置繼續捲，
///    而時間軸上這種卡有幾十張。用時間算的話，暫停就是 paused: true，
///    寬度變了下一格自己就對。
///
/// ⚠️ 只在卡片捲進畫面時才捲：四十站同時在動是雜訊，也耗電。
///    「看不到」是要被明確回報才算——onScrollVisibilityChange 萬一沒回報初始狀態，
///    寧可多捲幾張看不到的，也不要讓眼前那張永遠不動。
///
/// ⚠️ 「減少動態效果」打開時不捲，退回一般的尾端省略（…）。VoiceOver 一律唸全名。
struct TripMarqueeText: View {
    let text: String
    var font: Font = .subheadline.weight(.semibold)
    /// VoiceOver 要唸的字（例如「第 43 站，THE ROYAL…，必去」）；nil＝唸 text
    var accessibilityText: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 這一行實際拿到的寬度
    @State private var boxWidth: CGFloat = 0
    /// 這串字一行排開的自然寬度
    @State private var textWidth: CGFloat = 0
    @State private var onScreen = true
    /// 這一輪從什麼時候開始算（捲回畫面、換字的時候重來，先停在開頭）
    @State private var cycleStart = Date()

    /// 兩份字之間的空白
    private static let gap: CGFloat = 36
    /// 每輪開頭停多久（秒）
    private static let hold: Double = 2.0
    /// 捲動速度（pt／秒）。再快就讀不到了
    private static let speed: Double = 32

    private var overflows: Bool { boxWidth > 0 && textWidth > boxWidth + 0.5 }

    var body: some View {
        // 佔位：決定這一行的高度與可用寬度。本身不畫（hidden 也會把它移出輔助使用的樹）。
        Text(text)
            .font(font)
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { w in
                boxWidth = w
            }
            // 量自然寬度：fixedSize 讓它照整串排開。掛在 background 裡不影響版面。
            .background(alignment: .leading) {
                Text(text)
                    .font(font)
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { w in
                        textWidth = w
                    }
            }
            .overlay(alignment: .leading) { visible }
            .onScrollVisibilityChange(threshold: 0.2) { shown in
                if shown && !onScreen { cycleStart = Date() }
                onScreen = shown
            }
            .onChange(of: text) { _, _ in cycleStart = Date() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText ?? text)
    }

    @ViewBuilder
    private var visible: some View {
        if !overflows || reduceMotion {
            Text(text)
                .font(font)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !onScreen)) { context in
                marquee(offset: Self.offset(at: context.date, since: cycleStart,
                                            distance: textWidth + Self.gap))
            }
        }
    }

    private func marquee(offset x: CGFloat) -> some View {
        HStack(spacing: Self.gap) {
            Text(text).font(font).fixedSize()
            Text(text).font(font).fixedSize()
        }
        .offset(x: x)
        .frame(width: boxWidth, alignment: .leading)
        .clipped()
        // 右緣一律淡出（告訴人後面還有字）；左緣只在捲動中才淡出——
        // 停在開頭的時候淡左緣會把第一個字吃掉一半。
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: x < 0 ? 10 : 0)
                Rectangle()
                LinearGradient(colors: [.black, .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 14)
            }
        }
    }

    /// 這一刻該往左移多少。一輪＝停 hold 秒＋捲 distance。
    /// 捲到 −distance 時第二份字剛好在原位，下一輪從 0 開始看起來是同一格。
    static func offset(at now: Date, since start: Date, distance: CGFloat) -> CGFloat {
        guard distance > 0 else { return 0 }
        let travel = Double(distance) / speed
        let t = max(0, now.timeIntervalSince(start))
        let phase = t.truncatingRemainder(dividingBy: hold + travel)
        return phase < hold ? 0 : -CGFloat((phase - hold) * speed)
    }
}
