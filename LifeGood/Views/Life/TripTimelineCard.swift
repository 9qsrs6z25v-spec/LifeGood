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
//   │ (🛒)        │ ‿‿樓群‿‿塔‿‿橋‿‿          ✈  [NT$1,014]
//   ╰─────────────┴──────────────────────────────────────────╯
//
// （v25.518 起「Have a nice trip!」寫在行程頁最上面的看板，第一站不再寫，
//  見 TripSummaryBoard.swift。）
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
///
/// [v25.519] 深色模式改成混 30% 白（原本用原色）。原本的註解寫「在 #2C2C2E 上 3.5～4.9，大字過」，
/// 但狀態面板的小標是 10pt、不是大字，要 4.5：紫 3.58、青 4.14、桃 3.79、藍 3.96 本來就不及格。
/// 夜晚的卡片（整張卡變深色，見 TripCardSky）面板是藏青，用原色更只剩 3.26～4.34。
/// 混 30% 白之後：深色面板 5.31～6.44、夜晚面板 4.83～7.21、查看地圖 6.09～9.14。
/// ⚠️ 數字是用 sRGB 近似算的；Color.mix 預設在 perceptual 色彩空間混，實機要再驗一次。
enum TripInk {
    /// 寫字用
    static func text(_ c: Color, _ scheme: ColorScheme) -> Color {
        scheme == .dark ? c.mix(with: .white, by: 0.3) : c.mix(with: .black, by: 0.4)
    }
    /// 白字壓上去的實心底（兩種模式都壓暗）。花費招牌原本白字壓原色只有
    /// 2.32～3.43:1，改用這個是 5.8～7.7:1。
    static func solid(_ c: Color) -> Color {
        c.mix(with: .black, by: 0.4)
    }
    /// 過夜的靛藍。系統靛藍在深色模式的 #2C2C2E 上只有 2.75:1。
    /// [v25.519] 混白從 30% 加到 45%：30% 在 #2C2C2E 上 4.45、在夜晚的藏青面板上 4.04～4.86，
    /// 差一點點；45% 是 5.74（#2C2C2E）、5.21～6.26（夜晚面板）。
    static func indigo(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.indigo.mix(with: .white, by: 0.45) : Color.indigo
    }
}

// MARK: - 天空（v25.519）

/// 卡片的天空跟著**那一站的抵達時間**走：早上淡藍、下午晴藍、傍晚橘粉、晚上深藍夜空加星星、
/// 深夜更暗。往下滑時間軸，像看著一天過去（使用者回報：「項目清單右邊有點白的單調」）。
///
/// 跟的是資料上的抵達時間，不是現在幾點，所以是靜態的，不需要 TimelineView。
enum TripSkyTime: Int, CaseIterable {
    case dawn, morning, afternoon, dusk, evening, lateNight

    /// 小時用 Calendar.current 取——時間軸算第幾天（TripPlan.timeline）用的是它，
    /// 卡上寫的 HH:mm（DateFormatter 預設）也是目前時區，天空才會跟卡上寫的時間對得上。
    ///
    ///   05:00–06:59 清晨　07:00–11:59 早上　12:00–16:59 下午
    ///   17:00–18:59 傍晚　19:00–22:59 晚上　23:00–04:59 深夜
    static func of(_ date: Date, calendar: Calendar = .current) -> TripSkyTime {
        switch calendar.component(.hour, from: date) {
        case 5..<7: return .dawn
        case 7..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<19: return .dusk
        case 19..<23: return .evening
        default: return .lateNight
        }
    }

    /// 晚上與深夜：整張卡變深色（淺色模式也是）
    var isNight: Bool { self == .evening || self == .lateNight }
}

/// 一張卡在某個時段的配色。淺色、深色模式各六組（規格「每個時段的配色表」）。
///
/// 設計：
/// • 白天四個時段：卡底照舊是白（深色模式 #1C1C1E），天空只是淡淡一層——從卡身頂端開始，
///   上方最濃、往下淡出，淡到「狀態面板上緣 −6pt」就沒了，不墊到面板後面。
/// • 晚上、深夜：**整張卡變深色**（卡底藏青、內容套深色模式），不做「只有上半是夜空」：
///   地址與面板之間只有 8pt，從藏青淡到白的那一段一定壓到字；而且整張套深色之後，
///   系統色（.primary／.secondary／分隔線／膠囊底）全部自動換成驗過的深色版。
/// • 當天色（TripDayPalette）不鋪大面積：天空講「幾點」，當天色講「哪一天」
///   （序號圈、面板、路段膠囊、查看地圖、…、花費招牌、天際線上的地標都還是當天色）。
///
/// 對比（sRGB 近似，scratchpad/v519/sky_contrast*.py）：標題 14.8～19.6；
/// 地址改用各時段的墨色，在天空最濃處 6.56～7.13、白底 8.09～9.52，夜晚 9.50～11.57。
struct TripCardSky: Equatable {
    let time: TripSkyTime
    /// 整頁是不是深色模式
    let pageDark: Bool
    /// 星星的種子（站序號）
    let seed: Int
    /// 天空最濃處（卡身頂端）
    let top: Color
    /// 天空中段（55% 處），再往下淡成同色相的透明
    let mid: Color
    /// 卡底。nil＝系統的 secondarySystemGroupedBackground（白天時段，淺色白、深色 #1C1C1E）
    let base: Color?
    /// 地址、備註的字色（取代原本的 .secondary／.tertiary：.secondary 在白底上只有 3.44，
    /// 疊上天空剩 2.99～3.24）
    let ink: Color
    /// 狀態面板的底。nil＝照舊 tertiarySystemGroupedBackground（白天時段不動）
    let panel: Color?
    /// 底帶的樓群色票
    let skyline: TripSkylineInk
    /// 底帶的地平線暖光（夜晚），0＝沒有
    let glow: Double
    /// 撒幾顆星，0＝不撒（只有夜晚）
    let stars: Int

    var isNight: Bool { time.isNight }

    /// 這張卡用哪一套配色：夜晚時段不管整頁是什麼模式都是深色
    var scheme: ColorScheme { (pageDark || time.isNight) ? .dark : .light }

    /// 狀態面板的框：面板跟夜晚卡底的對比只有 1.14～1.27，邊界靠這條框（看板格子同一條）
    var panelEdge: Color? { isNight ? TripBoardPalette(.dark).cellStroke : nil }

    /// 白天天空上的 ≡ 把手：灰底（tertiarySystemFill）疊在天空上只剩 2.86～3.00，
    /// 改成白 70% 的底＋看板標籤的藍（6.00～6.32）。夜晚與深色模式照舊。
    var handleFill: Color? { scheme == .light ? Color.white.opacity(0.7) : nil }
    var handleInk: Color? { scheme == .light ? TripBoardPalette(.light).label : nil }

    init(time: TripSkyTime, pageDark: Bool, seed: Int) {
        self.time = time
        self.pageDark = pageDark
        self.seed = seed
        // 夜晚的地址：看板夜裡日期的那個淡藍（深色模式所有時段也用它：.secondary 在深色「下午」只有 4.31）
        let nightInk = TripBoardPalette(.dark).inkDate
        var base: Color? = nil
        var panel: Color? = nil
        var glow = 0.0
        var stars = 0
        let top: Color, mid: Color, ink: Color, skyline: TripSkylineInk
        switch (pageDark, time) {
        // ── 淺色模式 ──
        case (false, .dawn):
            top = Color(tb: 0xFBE3D6); mid = Color(tb: 0xECE6F8); ink = Color(tb: 0x5A4A63)
            skyline = .dawnLight
        case (false, .morning):
            top = Color(tb: 0xDDF0FE); mid = Color(tb: 0xEEF7FF); ink = Color(tb: 0x33507F)
            skyline = .morningLight
        case (false, .afternoon):
            // 看板白天天空的中段與下段
            top = TripBoardSkyArt.dayHigh; mid = TripBoardSkyArt.dayLow; ink = Color(tb: 0x24476F)
            skyline = .boardDay
        case (false, .dusk):
            top = Color(tb: 0xFFCFB0); mid = Color(tb: 0xFBDDE6); ink = Color(tb: 0x6A3A2E)
            skyline = .duskLight
        case (false, .evening):
            top = Color(tb: 0x0B1636); mid = Color(tb: 0x111C40); ink = nightInk
            base = Color(tb: 0x16203F); panel = Color(tb: 0x24315C)
            skyline = .boardNight; glow = 0.18; stars = 8
        case (false, .lateNight):
            top = Color(tb: 0x050B22); mid = Color(tb: 0x080F2B); ink = nightInk
            base = Color(tb: 0x0C1229); panel = Color(tb: 0x1C2648)
            skyline = .lateNight; glow = 0.08; stars = 12
        // ── 深色模式 ──
        case (true, .dawn):
            top = Color(tb: 0x3B2C3F); mid = Color(tb: 0x2A2433); ink = nightInk
            skyline = .dayDark
        case (true, .morning):
            top = Color(tb: 0x1C3550); mid = Color(tb: 0x1C2735); ink = nightInk
            skyline = .dayDark
        case (true, .afternoon):
            top = Color(tb: 0x1B4166); mid = Color(tb: 0x1A2C44); ink = nightInk
            skyline = .dayDark
        case (true, .dusk):
            top = Color(tb: 0x4A2C2A); mid = Color(tb: 0x3A2433); ink = nightInk
            skyline = .duskDark
        case (true, .evening):
            // 看板夜空的天頂；卡底＝看板夜裡的卡頂色；面板＝看板夜裡格子的底
            top = TripBoardSkyArt.nightZenith; mid = Color(tb: 0x0F1A3D); ink = nightInk
            base = TripBoardPalette(.dark).boardTop; panel = Color(tb: 0x1C2646)
            skyline = .boardNight; glow = 0.16; stars = 8
        case (true, .lateNight):
            top = Color(tb: 0x050A1E); mid = Color(tb: 0x080E26); ink = nightInk
            base = Color(tb: 0x0A0F24); panel = Color(tb: 0x1A2444)
            skyline = .lateNight; glow = 0.08; stars = 12
        }
        self.top = top
        self.mid = mid
        self.base = base
        self.ink = ink
        self.panel = panel
        self.skyline = skyline
        self.glow = glow
        self.stars = stars
    }
}

/// 卡片底帶各時段的樓群色票（看板的 .boardDay／.boardNight 在 TripSummaryBoard.swift）。
/// 藝術元素只要看得到：近排對卡底的可見度白天 2.04～3.00、深色白天 1.64～1.81；
/// 夜晚的樓本身只有 1.05～1.37，靠地平線暖光和亮窗撐。
extension TripSkylineInk {
    static let dawnLight = TripSkylineInk(
        far: Color(tb: 0xD9CFE6, 0.8), farLight: nil, near: [Color(tb: 0xA7A3C9)],
        glint: Color.white.opacity(0.35), windowLine: Color.white.opacity(0.28), lit: nil)
    static let morningLight = TripSkylineInk(
        far: Color(tb: 0xC9DCEF, 0.8), farLight: nil, near: [Color(tb: 0x9DB8DA)],
        glint: Color.white.opacity(0.35), windowLine: Color.white.opacity(0.28), lit: nil)
    /// 傍晚：樓帶一點紫，亮邊與窗線是夕陽的暖色
    static let duskLight = TripSkylineInk(
        far: Color(tb: 0xE7C3C9, 0.8), farLight: nil, near: [Color(tb: 0xA98BB0)],
        glint: Color(tb: 0xFFD9B0, 0.45), windowLine: Color(tb: 0xFFE2B8, 0.55), lit: nil)
    /// 深夜（兩種模式共用）：比晚上更暗，窗只亮一成多
    static let lateNight = TripSkylineInk(
        far: Color(tb: 0x121A3A), farLight: nil, near: [Color(tb: 0x1E2A55), Color(tb: 0x182247)],
        glint: nil, windowLine: nil,
        lit: Lit(rate: 0.12, warm: Color(tb: 0xFFC56B), cool: Color(tb: 0x9ED8FF), warmShare: 0.72))
    /// 深色模式的清晨、早上、下午
    static let dayDark = TripSkylineInk(
        far: Color(tb: 0x2A3550, 0.8), farLight: nil, near: [Color(tb: 0x34466B)],
        glint: Color.white.opacity(0.10), windowLine: Color.white.opacity(0.12), lit: nil)
    /// 深色模式的傍晚
    static let duskDark = TripSkylineInk(
        far: Color(tb: 0x3A2E40, 0.8), farLight: nil, near: [Color(tb: 0x4A3A55)],
        glint: Color.white.opacity(0.10), windowLine: Color(tb: 0xFFC56B, 0.30), lit: nil)
}

/// cardColumn 裡要讓天空知道位置的幾段字（TripBoardAnchorKey 的 key，跟看板共用同一個 PreferenceKey）。
/// 天空淡到面板上緣就停；星星避開標題、地址、備註。
enum TripCardAnchor {
    static let title = "card.title"
    static let address = "card.address"
    static let note = "card.note"
    static let panel = "card.panel"
}

/// 夜晚卡片天空上的星星。用看板同一支 paintStars，只撒 8～12 顆，避開標題、地址、備註。
///
/// Equatable＋.equatable()：時間軸不是 lazy，四十張卡同時在；Canvas 的閉包比不出有沒有變，
/// 不擋的話整頁任何狀態一變就全部重畫。避開的範圍先取整數（.integral）：標題的跑馬燈
/// 每秒 30 格在動，小數點的版面抖動不能讓它重畫。
struct TripCardStars: View, Equatable {
    /// 天空的上緣（卡身頂）與星星撒到哪裡為止（卡片座標）
    let top: CGFloat
    let bottom: CGFloat
    /// 照片的右緣：再往左是照片，撒了也看不到
    let left: CGFloat
    let avoid: [CGRect]
    let seed: Int
    let count: Int

    var body: some View {
        Canvas { ctx, size in
            guard bottom - top > 14, size.width - left > 40 else { return }
            var g = ctx
            g.translateBy(x: left, y: top)
            let local = avoid.map { $0.offsetBy(dx: -left, dy: -top) }
            TripBoardSkyArt.paintStars(&g, width: size.width - left - 8, bottom: bottom - top,
                                       avoid: local, seed: seed, count: count)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
/// 圖層（後 → 前）：卡片底（含路段膠囊的底）→ 天空（v25.519）→ 天際線 → 照片 → 內容
/// → 照片上的標記與招牌。
///
/// ⚠️ 這一層**不准**掛 .clipShape／.clipped：花費招牌的 popover、拖曳時畫在卡與卡
///    之間的那條線都在卡片邊界上或外面。要裁的只有照片自己（照片自己 clipShape），
///    以及天空、天際線各自那一層（[v25.519] 實心的樓會凸出卡片右下的圓角）。
///
/// [v25.519] 夜晚時段的卡片整張是深色：呼叫端在這張卡外面套 .environment(\.colorScheme, sky.scheme)，
/// 骨架只負責換卡底、畫天空與星星。
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
    /// [v25.519] 這張卡的天空（跟著抵達時間）。nil＝照舊的白卡
    let sky: TripCardSky?
    /// [v25.519] 長按照片跳出的選單（更換封面）。掛在照片裁成波浪切線**之後**，
    /// 長按浮起來的預覽才是切好的形狀，不是整張沒裁的長方形。nil＝沒有選單
    let heroMenu: AnyView?

    @Environment(\.colorScheme) private var scheme
    /// 「增加對比」打開時天空淡一半
    @Environment(\.colorSchemeContrast) private var contrast
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
         footer: AnyView?, onTap: @escaping () -> Void,
         sky: TripCardSky? = nil, heroMenu: AnyView? = nil) {
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
        self.sky = sky
        self.heroMenu = heroMenu
    }

    var body: some View {
        Group {
            if metrics.stacked { stackedLayout } else { sideBySide }
        }
        // 整張卡可點＝打開景點卡。裡面的按鈕（路段、⊕、打卡、購物車、≡、…、
        // 天氣、電話、地圖、照片）自己吃掉點擊，其餘地方才傳到這裡。
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        // [v25.519] 標題、地址、面板的位置只給這張卡的天空用。讀完就清掉，
        // 不讓四十張卡的字典一路往上合併到整頁（看板的標頭也用同一個 key，但在別的子樹）。
        .transformPreference(TripBoardAnchorKey.self) { $0 = [:] }
    }

    private var shadowColor: Color {
        // 深色模式卡片是 #1C1C1E 放在 #000 上，本來就分得開；陰影在黑底上也看不到
        Color.black.opacity(scheme == .dark ? 0 : 0.07)
    }

    /// 卡底：白天時段照舊（淺色白、深色 #1C1C1E），夜晚時段是藏青
    private var cardFill: Color {
        sky?.base ?? Color(.secondarySystemGroupedBackground)
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
                .fill(cardFill)
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
            //
            // [v25.519] 樓改成實心有顏色（看板的畫法）之後，右下角會凸出卡片 18pt 的圓角
            // （約 10×8pt 的樓角壓在頁面底上），所以這一層自己裁成卡片右下角的形狀。
            // 有子地點 footer 時這裡不是卡片的底，不用裁。
            skyline
                .frame(width: max(0, m.cardWidth - m.photoBottom - 4),
                       height: bottomBand)
                .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: footer == nil ? 18 : 0,
                                                  style: .continuous))
        }
        // [v25.519] 天空：掛在天際線**之後**＝畫在它後面（background 越晚掛越在後面），
        // 所以疊起來是「卡底 → 天空 → 天際線 → 照片」，照片右緣的波浪缺口自然透出天空。
        // 位置要知道狀態面板在哪（天空淡到面板上緣 −6pt 就停，不墊到面板後面）。
        .backgroundPreferenceValue(TripBoardAnchorKey.self) { anchors in
            skyBackground(anchors)
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

    @ViewBuilder
    private func photoLayer(size: CGSize, rowTop: CGFloat?) -> some View {
        let m = metrics
        let shape = TripPhotoCutShape(topBand: band,
                                      topWidth: m.photoTop,
                                      midWidth: m.photo,
                                      bottomWidth: m.photoBottom,
                                      rowTop: rowTop,
                                      bottomLeftRadius: footer == nil ? 18 : 14)
        let clipped = hero
            .frame(width: m.photo + 2, height: size.height)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipShape(shape)
            // clipShape 不管點擊範圍；照片的點擊要跟著曲線，不能吃到右邊的內容
            .contentShape(shape)
        if let heroMenu {
            // [v25.519] 長按照片＝更換封面。點一下照舊是放大（Button 吃掉單點，長按才是選單）；
            // 拖曳只在右欄的 ≡ 把手上，不會跟這個搶。預覽形狀跟著波浪切線。
            clipped
                .contentShape(.contextMenuPreview, shape)
                .contextMenu { heroMenu }
        } else {
            clipped
        }
    }

    // MARK: 天空（v25.519）

    @ViewBuilder
    private func skyBackground(_ anchors: [String: Anchor<CGRect>]) -> some View {
        if let sky {
            GeometryReader { geo in
                skyLayer(sky, size: geo.size, anchors: anchors.mapValues { geo[$0] })
            }
        }
    }

    /// 天空：卡身頂端（路段膠囊底下）開始，上方最濃、往下淡成同色相的透明，
    /// 淡到「狀態面板上緣 −6pt」就沒了，不墊到面板後面。字落在最濃處到卡底之間，
    /// 對比是單調變化，驗頭尾兩端就夠（見 TripCardSky）。
    ///
    /// 只用 LinearGradient 填形狀（GPU 合成），不開點陣圖：不用 mask、blur、shadow、
    /// drawingGroup——四十張卡每一個都是一次離屏繪製。星星只有夜晚才有。
    private func skyLayer(_ sky: TripCardSky, size: CGSize, anchors: [String: CGRect]) -> some View {
        let top = band
        let panelTop = anchors[TripCardAnchor.panel]?.minY ?? size.height * 0.6
        let bottom = max(top + 12, panelTop - 6)
        let strength = contrast == .increased ? 0.5 : 1.0
        let avoid = [TripCardAnchor.title, TripCardAnchor.address, TripCardAnchor.note]
            .compactMap { anchors[$0] }
            .map { $0.integral.insetBy(dx: -4, dy: -3) }
        return ZStack(alignment: .topLeading) {
            UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18, style: .continuous)
                .fill(LinearGradient(stops: [.init(color: sky.top, location: 0),
                                             .init(color: sky.mid, location: 0.55),
                                             .init(color: sky.mid.opacity(0), location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .opacity(strength)
                .frame(width: size.width, height: bottom - top)
                .offset(y: top)
            if sky.stars > 0 {
                TripCardStars(top: top.rounded(), bottom: (bottom - 4).rounded(),
                              left: (metrics.photo + 2).rounded(),
                              avoid: avoid, seed: sky.seed, count: sky.stars)
                    .equatable()
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
                stackedHero
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
                // [v25.519] 實心的樓會凸出卡片下面兩個圓角：沒有 footer 時這一條就是卡片的底，裁成那個形狀
                skyline
                    .frame(maxWidth: .infinity)
                    .frame(height: bottomBand)
                    .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: footer == nil ? 18 : 0,
                                                      bottomTrailingRadius: footer == nil ? 18 : 0,
                                                      style: .continuous))
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
        // [v25.519] 上下排（字很大時）不畫天空漸層：上面是 112pt 的照片橫幅，天空只會剩一條帶子。
        // 卡底（夜晚是藏青）、夜晚的深色、底帶的彩色樓群照樣跟著時段。
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardFill)
                .shadow(color: shadowColor, radius: 6, x: 0, y: 2)
        }
    }

    /// 上下排的照片橫幅。長按選單（更換封面）掛在照片自己身上，不掛在整個 ZStack：
    /// 那樣購物車按鈕上長按也會跳出照片的選單。
    @ViewBuilder
    private var stackedHero: some View {
        if let heroMenu {
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            hero
                .contentShape(shape)
                .contentShape(.contextMenuPreview, shape)
                .contextMenu { heroMenu }
        } else {
            hero
        }
    }
}

// MARK: - 主圖

/// 左邊那張照片。來源：使用者的照片 → 衛星快照 → 當天色的街角線稿。
/// [v25.519] 「使用者的照片」是這一站的封面（TripStop.coverPhotoURL：指定的那張，或自動的第一張）；
/// 封面指定成衛星空照時呼叫端傳 photoURL＝nil。這裡不用改：taskKey 帶著檔名，換封面就重新載入。
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
    /// [v25.519] 面板的底。nil＝照舊 tertiarySystemGroupedBackground。夜晚的卡片傳藏青
    let surface: Color?
    /// [v25.519] 面板的框（0.5pt）。夜晚的卡片面板跟卡底只差 1.14～1.27，邊界靠它
    let edge: Color?

    @ScaledMetric(relativeTo: .callout) private var timeSize: CGFloat = 16
    @ScaledMetric(relativeTo: .caption2) private var labelSize: CGFloat = 10
    @ScaledMetric(relativeTo: .callout) private var glyph: CGFloat = 22

    init(left: Half, right: Half, rightDone: Bool, color: Color, checkIn: CheckIn?,
         surface: Color? = nil, edge: Color? = nil) {
        self.left = left
        self.right = right
        self.rightDone = rightDone
        self.color = color
        self.checkIn = checkIn
        self.surface = surface
        self.edge = edge
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
        .background(surface ?? Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            if let edge {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(edge, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
        }
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
                    // [v25.520] 子地點標題一行、放不下跑馬燈（跟 ItemRow 的子項目同一套）。
                    // 原本收合時截成「…」、展開時折三行；現在兩種狀態都是同一行。
                    MarqueeText(d.title.isEmpty ? "（未填標題）" : d.title)
                        .font(.system(size: 11, weight: .semibold))
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
    /// [v25.518] 以下四種**只給行程頁最上面的看板**（forBoard）：鳥居、台北 101、
    /// 高雄 85 大樓、廟宇的燕尾脊。時間軸那條 14pt 的底帶不畫它們（forCity 不會回傳）。
    case torii, tower101, tower85, templeRoof

    /// 只收畫得出、認得出的。台北 101 是一節一節的，不是這座塔，所以不收。
    /// （[v25.518] 101 後來有了自己的畫法 .tower101，但只在看板上出現）
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

    /// [v25.518] 看板（整趟的目的地）用的地標。
    ///
    /// 日本的城市前面多一座鳥居：日本才有、一眼認得出。台灣的縣市各給一個：
    /// 台北 101、高雄 85 大樓，其他縣市是廟宇的燕尾脊。
    /// forCity 不動——時間軸每進一座日本城市就多一座鳥居會變成壁紙。
    /// 「臺／台」先統一：同一座台北兩種寫法，不能一個有 101、一個沒有。
    static func forBoard(_ place: TripPlaceName.Place?) -> [TripLandmark] {
        guard let place else { return [] }
        let zh = place.zh.replacingOccurrences(of: "臺", with: "台")
        switch place.country {
        case "JP":
            return [.torii] + forCity(zh)
        case "TW":
            switch zh {
            case "台北": return [.tower101]
            case "高雄": return [.tower85]
            default: return [.templeRoof]
            }
        default:
            return []
        }
    }
}

// [v25.518] 地標的幾何從 TripCardSkyline 裡搬出來（原本是它的兩支 private 函式），
// 看板要用同一套畫法，不要再寫第二份。時間軸畫出來的樣子完全不變。
extension TripLandmark {
    /// 佔多寬（點）
    var span: CGFloat {
        switch self {
        case .tower: return 14
        case .bridge: return 62
        case .pagoda: return 18
        case .wheel: return 30
        case .torii: return 20
        case .tower101: return 12
        case .tower85: return 16
        case .templeRoof: return 26
        }
    }

    /// 封閉的形狀（看板可以填色）。其餘四種是線稿，填色會連成奇怪的面，只能描線。
    var isSolid: Bool {
        switch self {
        case .torii, .tower101, .tower85, .templeRoof: return true
        case .tower, .bridge, .pagoda, .wheel: return false
        }
    }

    /// 輪廓（純 Path）。height＝畫布高度，ground＝地面的 y，地標頂端在 ground − (height − 4)。
    /// 尺寸是照 14～40pt 高的底帶調的（橋塔、五重塔、摩天輪各有上限），
    /// 放到更高的畫布上不會等比例長大——要更大就整個 scaleBy。
    func outline(x: CGFloat, ground: CGFloat, height: CGFloat) -> Path {
        let top = max(2, ground - (height - 4))
        var p = Path()
        switch self {
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
        case .torii:
            // 鳥居：兩端上翹的笠木、島木、兩根柱、貫、中間的額束。全部是封閉的形狀
            let h = ground - top
            p.move(to: CGPoint(x: x - 1, y: top))
            p.addQuadCurve(to: CGPoint(x: x + 21, y: top),
                           control: CGPoint(x: x + 10, y: top + 3.2))
            p.addLine(to: CGPoint(x: x + 20.4, y: top + 2.4))
            p.addQuadCurve(to: CGPoint(x: x - 0.4, y: top + 2.4),
                           control: CGPoint(x: x + 10, y: top + 5.4))
            p.closeSubpath()
            p.addRect(CGRect(x: x + 0.8, y: top + 3.6, width: 18.4, height: 1.3))
            let pillarTop = top + 3.6
            p.addRect(CGRect(x: x + 3.6, y: pillarTop, width: 2.2, height: max(0, ground - pillarTop)))
            p.addRect(CGRect(x: x + 14.2, y: pillarTop, width: 2.2, height: max(0, ground - pillarTop)))
            p.addRect(CGRect(x: x + 1.6, y: top + h * 0.36, width: 16.8, height: 1.6))
            p.addRect(CGRect(x: x + 9.4, y: top + 4.9, width: 1.2, height: max(0, h * 0.36 - 4.9)))
        case .tower101:
            // 台北 101：基座＋八節（每一節上寬下窄）＋頂部平台與天線
            let cx = x + 6
            let h = ground - top
            let podiumTop = ground - h * 0.16
            let bodyTop = top + h * 0.2
            p.addRect(CGRect(x: cx - 5, y: podiumTop, width: 10, height: max(0, ground - podiumTop)))
            let seg = (podiumTop - bodyTop) / 8
            for i in 0..<8 {
                let y0 = bodyTop + CGFloat(i) * seg
                p.move(to: CGPoint(x: cx - 2.6, y: y0 + seg))
                p.addLine(to: CGPoint(x: cx - 3.6, y: y0 + 0.35))
                p.addLine(to: CGPoint(x: cx + 3.6, y: y0 + 0.35))
                p.addLine(to: CGPoint(x: cx + 2.6, y: y0 + seg))
                p.closeSubpath()
            }
            p.addRect(CGRect(x: cx - 1.8, y: bodyTop - 2.2, width: 3.6, height: 2.2))
            p.addRect(CGRect(x: cx - 0.45, y: top, width: 0.9, height: max(0, bodyTop - 2.2 - top)))
        case .tower85:
            // 高雄 85 大樓：兩支腳往上合成一棟，頂上收尖、一根天線
            let h = ground - top
            let split = ground - h * 0.42
            let shoulder = top + h * 0.22
            p.addRect(CGRect(x: x + 2, y: split, width: 4.2, height: max(0, ground - split)))
            p.addRect(CGRect(x: x + 9.8, y: split, width: 4.2, height: max(0, ground - split)))
            p.move(to: CGPoint(x: x + 2, y: split + 0.5))
            p.addLine(to: CGPoint(x: x + 2, y: shoulder))
            p.addLine(to: CGPoint(x: x + 8, y: top + h * 0.08))
            p.addLine(to: CGPoint(x: x + 14, y: shoulder))
            p.addLine(to: CGPoint(x: x + 14, y: split + 0.5))
            p.closeSubpath()
            p.addRect(CGRect(x: x + 7.6, y: top, width: 0.8, height: h * 0.08))
        case .templeRoof:
            // 廟宇：殿身、兩端下彎的屋頂、屋脊兩端往上翹的燕尾
            let h = ground - top
            let eave = ground - h * 0.42
            let ridge = ground - h * 0.62
            let tip = max(top, ridge - h * 0.28)
            p.addRect(CGRect(x: x + 5, y: eave, width: 16, height: max(0, ground - eave)))
            p.move(to: CGPoint(x: x + 1, y: eave + 0.5))
            p.addQuadCurve(to: CGPoint(x: x + 6, y: ridge), control: CGPoint(x: x + 5, y: eave))
            p.addLine(to: CGPoint(x: x + 20, y: ridge))
            p.addQuadCurve(to: CGPoint(x: x + 25, y: eave + 0.5), control: CGPoint(x: x + 21, y: eave))
            p.closeSubpath()
            // 左邊的燕尾（順時針，跟其他形狀同一個方向，重疊處才不會被挖空）
            p.move(to: CGPoint(x: x + 7, y: ridge + 0.6))
            p.addQuadCurve(to: CGPoint(x: x - 1, y: tip), control: CGPoint(x: x + 2.5, y: ridge + 0.4))
            p.addLine(to: CGPoint(x: x + 0.4, y: tip + 0.4))
            p.addQuadCurve(to: CGPoint(x: x + 7, y: ridge - 1), control: CGPoint(x: x + 3.5, y: ridge - 1.2))
            p.closeSubpath()
            // 右邊的燕尾（同樣順時針）
            p.move(to: CGPoint(x: x + 19, y: ridge - 1))
            p.addQuadCurve(to: CGPoint(x: x + 25.6, y: tip + 0.4), control: CGPoint(x: x + 22.5, y: ridge - 1.2))
            p.addLine(to: CGPoint(x: x + 27, y: tip))
            p.addQuadCurve(to: CGPoint(x: x + 19, y: ridge + 0.6), control: CGPoint(x: x + 23.5, y: ridge + 0.4))
            p.closeSubpath()
            p.addRect(CGRect(x: x + 6, y: ridge - 1, width: 14, height: 1.6))
        }
        return p
    }
}

/// 卡片底部那一條淡淡的城市線稿（設計稿右下的樓群、塔、斜張橋）。
///
/// 規矩沿用 v25.505～513：**可以被看見，不可以被讀**——要讀的東西（金額）是疊在
/// 上面的招牌，不畫進這裡。**每一站都不一樣**：樓群的種子取站序號。
/// 小飛機與虛線航線只出現在「下一段要搭飛機」的那一站。
/// （v25.517 第一站還有一句「Have a nice trip!」與航線；v25.518 起那句寫在
///  行程頁最上面的看板，第一站不再重複——上下連著兩次是雜訊。）
///
/// 畫布的高度就是卡片的底帶（沒花費 14、有花費 28），所有樓與地標都夾在
/// 畫布裡、**不往上探**：正上方就是膠囊排，膠囊的底是半透明的。
/// 地標擺在左邊 12～32% 的位置，右下角留給花費招牌（它「掛在建築物上」）。
///
/// [v25.519] 樓從淡淡的當天色線稿（0.05 填色、0.30 描邊，白底上幾乎看不見）改成看板那樣
/// **實心、有顏色**的兩排樓，色票跟著那一站的時段（TripCardSky.skyline）：白天藍灰、傍晚帶紫、
/// 夜裡深藍加亮窗與地平線暖光。畫法直接呼叫看板的 paintFarRow／paintNearRow，不寫第二份。
/// 地標與航線改用當天色的墨色（淺色壓暗 40%、深色混 30% 白）：天際線上仍看得出「哪一天」。
///
/// Equatable＋.equatable()（呼叫端在包 AnyView 之前掛）：時間軸不是 lazy、四十張卡同時在，
/// Canvas 的閉包比不出有沒有變，不擋的話整頁任何狀態一變（橫幅、拖曳目標、路線計算進度）
/// 就全部重畫。⚠️ 這個型別裡不能放 @Environment（合成的 == 比不了屬性包裝器），
/// 深淺色由呼叫端明確傳進來。
struct TripCardSkyline: View, Equatable {
    let color: Color
    let seed: Int
    let landmarks: [TripLandmark]
    let planeTrail: Bool
    /// [v25.519] 樓群的色票
    let ink: TripSkylineInk
    /// [v25.519] 地平線暖光的濃度（夜晚），0＝沒有。用漸層畫，不用模糊
    let glow: Double
    /// [v25.519] 這張卡是深色（深色模式或夜晚時段）：地標與航線的墨色用哪一套
    let dark: Bool

    init(color: Color, seed: Int, landmarks: [TripLandmark], planeTrail: Bool,
         ink: TripSkylineInk = .boardDay, glow: Double = 0, dark: Bool = false) {
        self.color = color
        self.seed = seed
        self.landmarks = landmarks
        self.planeTrail = planeTrail
        self.ink = ink
        self.glow = glow
        self.dark = dark
    }

    var body: some View {
        Canvas { ctx, size in
            Self.draw(&ctx, size: size, art: self)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func draw(_ ctx: inout GraphicsContext, size: CGSize, art a: TripCardSkyline) {
        guard size.width > 40, size.height > 12 else { return }
        var r = InkRandom(20117 + a.seed * 131)
        let ground = size.height
        // 地標與航線：當天色的墨色（深色混 30% 白，淺色壓暗 40%）
        let mark = a.dark ? a.color.mix(with: .white, by: 0.3).opacity(0.85)
                          : TripInk.solid(a.color).opacity(0.9)

        // 夜裡地平線一層暖光（看板夜空同一個色）。看板用的是模糊，四十張卡不能用——
        // 這裡是一條由透明到暖色的漸層，效果接近、成本是零
        if a.glow > 0 {
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [TripBoardSkyArt.horizonGlow.opacity(0),
                                  TripBoardSkyArt.horizonGlow.opacity(a.glow)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        }

        // 遠排（看板同一支）
        TripBoardSkyArt.paintFarRow(&ctx, width: size.width, ground: ground, band: size.height,
                                    ink: a.ink, seed: a.seed)

        // 地標先佔位置，近排的樓繞開它
        var reserved: [ClosedRange<CGFloat>] = []
        var lx = size.width * CGFloat(0.12 + r.next() * 0.2)
        for landmark in a.landmarks {
            let w = landmark.span
            if lx + w > size.width - 4 { break }
            ctx.stroke(landmark.outline(x: lx, ground: ground - 0.5, height: size.height),
                       with: .color(mark),
                       style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round))
            reserved.append((lx - 3)...(lx + w + 3))
            lx += w + CGFloat(18 + r.next() * 30)
        }

        // 近排（看板同一支）：白天亮邊＋窗線，夜裡亮窗
        TripBoardSkyArt.paintNearRow(&ctx, width: size.width, ground: ground, band: size.height,
                                     ink: a.ink, seed: a.seed, reserved: reserved)

        if a.planeTrail { drawPlane(&ctx, size: size, color: mark, random: &r) }
    }

    private static func drawPlane(_ ctx: inout GraphicsContext, size: CGSize,
                                  color: Color, random r: inout InkRandom) {
        let start = CGPoint(x: size.width * 0.18, y: size.height * 0.78)
        let end = CGPoint(x: size.width * CGFloat(0.62 + r.next() * 0.12),
                          y: size.height * 0.22)
        drawTrail(&ctx, from: start, to: end,
                  control: CGPoint(x: (start.x + end.x) / 2, y: size.height * 0.9),
                  color: color.opacity(0.6), lineWidth: 0.9,
                  icon: "airplane", iconColor: color,
                  iconSize: 12, iconAngle: -24)
    }

    /// 一條虛線航跡＋尾端一個小圖示（飛機、車、電車、行人）。
    /// [v25.518] 從 drawPlane 抽出來：看板的「Have a nice trip!」後面那條航線也用這一支。
    static func drawTrail(_ ctx: inout GraphicsContext, from start: CGPoint, to end: CGPoint,
                          control: CGPoint, color: Color, lineWidth: CGFloat,
                          icon: String, iconColor: Color, iconSize: CGFloat, iconAngle: Double) {
        var trail = Path()
        trail.move(to: start)
        trail.addQuadCurve(to: end, control: control)
        ctx.stroke(trail, with: .color(color),
                   style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [3, 3]))
        var mark = ctx.resolve(Image(systemName: icon))
        mark.shading = .color(iconColor)
        var g = ctx
        g.translateBy(x: end.x + iconSize / 2, y: end.y - 1)
        g.rotate(by: .degrees(iconAngle))
        g.draw(mark, in: CGRect(x: -iconSize / 2, y: -iconSize / 2, width: iconSize, height: iconSize))
    }
}

// [v25.520] 跑馬燈搬到 Views/MarqueeText.swift（MarqueeText），全 App 共用。
