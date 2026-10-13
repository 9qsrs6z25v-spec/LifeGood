import SwiftUI
import WidgetKit

// MARK: - 小工具的配色與天空（v25.545，只屬於 LifeGoodWidgets）
//
// 色碼照 App 看板抄過來（scratchpad/widgets/mock_spec.json 的 commonPalette），
// 不搬 App 的型別（TripBoardPalette、MoneyTone、Color(tb:) 都只在 App target）。
//
// 規格見 scratchpad/widgets/v1/brief.md 的 G2。
//
// 這個檔案提供：
//   • Color(widgetHex:opacity:)        16 進位轉色（刻意不叫 tb：App 的 Color(tb:) 不在這個 target）
//   • WidgetPalette                    淺色／深色兩組色碼；mono＝著色或 StandBy（白字＋透明度）
//   • WidgetPalette.Surface            現在被放在哪：著色？StandBy？要不要畫天空？
//   • WidgetSky / WidgetSkyMoon        天空底（淺色漸層＋雲；深色星空＋月牙）
//   • WidgetStopMark                   行程點：會議實心圓、我的行事曆空心圓、系統行事曆小方塊、旅遊小飛機
//                                      （著色模式顏色會被洗掉，四種靠形狀分辨）

// MARK: - 16 進位轉色

extension Color {
    /// 0xRRGGBB → sRGB 顏色
    init(widgetHex: UInt32, opacity: Double = 1) {
        let red = Double((widgetHex >> 16) & 0xFF) / 255
        let green = Double((widgetHex >> 8) & 0xFF) / 255
        let blue = Double(widgetHex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

// MARK: - 配色

/// 小工具的一組顏色。每個屬性都是 Color（三元運算子兩邊同型別，型別檢查快）。
///
/// mono＝著色模式或 StandBy：天空不畫，字改成白字＋透明度
///（著色模式系統只看透明度上色；StandBy 是黑底）。橫條、行程點沿用深色那一組。
struct WidgetPalette {
    /// 深色（mono 也算深色：黑底白字）
    let isDark: Bool
    /// 著色模式或 StandBy
    let isMono: Bool

    init(_ scheme: ColorScheme, mono: Bool = false) {
        isMono = mono
        isDark = mono || scheme == .dark
    }

    // 天空

    var skyTop: Color { isDark ? Color(widgetHex: 0x121B38) : Color(widgetHex: 0xEAF4FD) }
    var skyBottom: Color { isDark ? Color(widgetHex: 0x0E1428) : Color(widgetHex: 0xF4F8FD) }
    var cloud: Color { Color(widgetHex: 0xFFFFFF, opacity: 0.94) }
    var moon: Color { Color(widgetHex: 0xF4EBC8) }
    var stars: Color { Color(widgetHex: 0xCFE0FF, opacity: 0.85) }

    // 字

    /// 大字、內文
    var ink: Color {
        if isMono { return Color.white }
        return isDark ? Color(widgetHex: 0xF3F6FF) : Color(widgetHex: 0x0B1B45)
    }

    /// 次要內文（StandBy 樣稿「白 0.85」；其他時候同 ink）
    var inkSoft: Color {
        if isMono { return Color.white.opacity(0.85) }
        return ink
    }

    /// 左上角日期
    var inkDate: Color {
        if isMono { return Color.white.opacity(0.75) }
        return isDark ? Color(widgetHex: 0xB9C7EE) : Color(widgetHex: 0x1D3A7A)
    }

    /// 小標、最下面一行、灰字
    var label: Color {
        if isMono { return Color.white.opacity(0.7) }
        return isDark ? Color(widgetHex: 0xA3B2D9) : Color(widgetHex: 0x4A5B8C)
    }

    // 好壞

    var good: Color { isDark ? Color(widgetHex: 0x5BD99A) : Color(widgetHex: 0x177A44) }
    var warn: Color { isDark ? Color(widgetHex: 0xFFC14D) : Color(widgetHex: 0xA65300) }
    var bad: Color { isDark ? Color(widgetHex: 0xFF7A8A) : Color(widgetHex: 0xC4243C) }

    // 這個月的錢（橫條）

    var fixedTop: Color { isDark ? Color(widgetHex: 0x8B5CF6) : Color(widgetHex: 0xB38BFF) }
    var fixedBottom: Color { isDark ? Color(widgetHex: 0xA98BFF) : Color(widgetHex: 0x8B5CF6) }
    var variableTop: Color { isDark ? Color(widgetHex: 0x3D86FF) : Color(widgetHex: 0x5B9BFF) }
    var variableBottom: Color { isDark ? Color(widgetHex: 0x5B9BFF) : Color(widgetHex: 0x2459D6) }
    var barTrack: Color { isDark ? Color(widgetHex: 0xFFFFFF, opacity: 0.10) : Color(widgetHex: 0xE3ECF8) }
    var incomeTick: Color { isDark ? Color(widgetHex: 0xF3F6FF) : Color(widgetHex: 0x0B1B45) }

    // 今天

    /// 「25 分後」（StandBy 樣稿是橘色）
    var countdown: Color {
        if isMono { return Color(widgetHex: 0xFF9500) }
        return isDark ? Color(widgetHex: 0x8DB7FF) : Color(widgetHex: 0x2F5BB7)
    }

    /// 全天的事膠囊
    var capsuleFill: Color {
        if isMono { return Color.white.opacity(0.14) }
        return isDark ? Color(widgetHex: 0xFFFFFF, opacity: 0.12) : Color(widgetHex: 0xFFFFFF, opacity: 0.65)
    }

    var capsuleText: Color {
        if isMono { return Color.white.opacity(0.9) }
        return isDark ? Color(widgetHex: 0xE6ECFF) : Color(widgetHex: 0x163A87)
    }

    /// 時間軸的線（淺 #4A5B8C 30%；深 白 20%）
    var axisTrack: Color {
        isDark ? Color(widgetHex: 0xFFFFFF, opacity: 0.20) : Color(widgetHex: 0x4A5B8C, opacity: 0.30)
    }

    /// 行程四色（跟靈動島同一套色相：會議橘、我的行事曆青、系統行事曆綠、旅遊紫）
    func dot(_ kind: TimelineStopKind) -> Color {
        switch kind {
        case .meeting:
            return isDark ? Color(widgetHex: 0xFF9F0A) : Color(widgetHex: 0xFF9500)
        case .personal:
            return isDark ? Color(widgetHex: 0x64D2FF) : Color(widgetHex: 0x32ADE6)
        case .appleCalendar:
            return isDark ? Color(widgetHex: 0x30D158) : Color(widgetHex: 0x34C759)
        case .trip:
            return isDark ? Color(widgetHex: 0xBF5AF2) : Color(widgetHex: 0xAF52DE)
        }
    }
}

// MARK: - 現在被放在哪

extension WidgetPalette {
    /// 小工具現在的環境。系統沒有直接說「你在 StandBy」，只能看背景被拿掉了沒。
    ///
    /// • 著色（iOS 18「著色」／iOS 26「透明」）：renderingMode 不是 fullColor → 不畫天空、重點色。
    /// • StandBy：背景被拿掉、而且不是 accented。iOS 18 著色主畫面也可能把背景拿掉，
    ///   多看一個 accented 才不會把著色主畫面誤當成 StandBy（那樣「今天」會換成大字版、名字換成類別）。
    ///   StandBy 夜間（全紅）若是 vibrant，也算 StandBy。
    struct Surface {
        let isTinted: Bool
        let isStandBy: Bool

        init(renderingMode: WidgetRenderingMode, showsBackground: Bool) {
            isTinted = renderingMode != .fullColor
            isStandBy = !showsBackground && renderingMode != .accented
        }

        /// 只有全彩、有背景時才畫天空
        var drawsSky: Bool { !isTinted && !isStandBy }

        /// 字改用白字＋透明度那一組
        var isMono: Bool { isTinted || isStandBy }
    }
}

// MARK: - 天空

/// 月牙（深色）／雲（淺色）放哪。
/// 中型「今天」右上角有手寫問候，不准用 topTrailing（會壓到字，J:56）。
enum WidgetSkyMoon {
    /// 右上（還能花）
    case topTrailing
    /// 左上日期旁（中型今天）
    case topLeading
    /// 右邊、大字那一列旁（小型今天：右上角有「4 場」）
    case middleTrailing
    /// 不放
    case none
}

/// App 看板那片天：淺色淡藍漸層＋一朵雲；深色星空＋月牙。只用簡單形狀，不用 Canvas。
struct WidgetSky: View {
    let palette: WidgetPalette
    var moon: WidgetSkyMoon = .topTrailing

    var body: some View {
        ZStack {
            LinearGradient(colors: [palette.skyTop, palette.skyBottom],
                           startPoint: .top, endPoint: .bottom)
            if palette.isDark {
                WidgetSkyStars(color: palette.stars)
                WidgetSkyOrnament(placement: moon) {
                    WidgetSkyCrescent(color: palette.moon, cutout: palette.skyTop)
                }
            } else {
                WidgetSkyOrnament(placement: moon) {
                    WidgetSkyCloud(color: palette.cloud)
                }
            }
        }
    }
}

/// 把月牙／雲放到指定位置（位置數字集中在這裡）
private struct WidgetSkyOrnament<Content: View>: View {
    let placement: WidgetSkyMoon
    @ViewBuilder let content: () -> Content

    var body: some View {
        switch placement {
        case .topTrailing:
            placed(alignment: .topTrailing, insets: EdgeInsets(top: 11, leading: 0, bottom: 0, trailing: 12))
        case .topLeading:
            // 日期「10/13 週二」右邊、第二列「今天 4 場・還剩 3 場」上面
            placed(alignment: .topLeading, insets: EdgeInsets(top: 6, leading: 104, bottom: 0, trailing: 0))
        case .middleTrailing:
            placed(alignment: .trailing, insets: EdgeInsets(top: 0, leading: 0, bottom: 24, trailing: 12))
        case .none:
            EmptyView()
        }
    }

    private func placed(alignment: Alignment, insets: EdgeInsets) -> some View {
        content()
            .padding(insets)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

/// 一彎月牙：一個月亮色的圓，蓋一個天空色的圓
private struct WidgetSkyCrescent: View {
    let color: Color
    let cutout: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 15, height: 15)
            Circle()
                .fill(cutout)
                .frame(width: 13, height: 13)
                .offset(x: 4.5, y: -3.5)
        }
        .frame(width: 18, height: 18)
    }
}

/// 一朵雲：一條膠囊＋兩個圓
private struct WidgetSkyCloud: View {
    let color: Color

    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule()
                .fill(color)
                .frame(width: 40, height: 12)
            Circle()
                .fill(color)
                .frame(width: 18, height: 18)
                .offset(x: -6, y: -4)
            Circle()
                .fill(color)
                .frame(width: 13, height: 13)
                .offset(x: 8, y: -4)
        }
        .frame(width: 44, height: 26, alignment: .bottom)
    }
}

/// 一顆星（位置是整塊的比例，0…1）
private struct WidgetSkyStarPoint {
    let id: Int
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let alpha: Double
}

/// 十來顆固定位置的小星點（每次畫都一樣，不會閃）
private struct WidgetSkyStars: View {
    let color: Color

    private static let points: [WidgetSkyStarPoint] = [
        WidgetSkyStarPoint(id: 0, x: 0.08, y: 0.10, size: 1.6, alpha: 0.8),
        WidgetSkyStarPoint(id: 1, x: 0.36, y: 0.06, size: 1.2, alpha: 0.6),
        WidgetSkyStarPoint(id: 2, x: 0.62, y: 0.14, size: 1.8, alpha: 0.9),
        WidgetSkyStarPoint(id: 3, x: 0.93, y: 0.30, size: 1.3, alpha: 0.6),
        WidgetSkyStarPoint(id: 4, x: 0.52, y: 0.33, size: 1.1, alpha: 0.5),
        WidgetSkyStarPoint(id: 5, x: 0.04, y: 0.46, size: 1.3, alpha: 0.6),
        WidgetSkyStarPoint(id: 6, x: 0.80, y: 0.52, size: 1.6, alpha: 0.7),
        WidgetSkyStarPoint(id: 7, x: 0.27, y: 0.64, size: 1.2, alpha: 0.5),
        WidgetSkyStarPoint(id: 8, x: 0.96, y: 0.72, size: 1.2, alpha: 0.6),
        WidgetSkyStarPoint(id: 9, x: 0.58, y: 0.82, size: 1.5, alpha: 0.6),
        WidgetSkyStarPoint(id: 10, x: 0.13, y: 0.90, size: 1.4, alpha: 0.7),
        WidgetSkyStarPoint(id: 11, x: 0.74, y: 0.95, size: 1.1, alpha: 0.5)
    ]

    var body: some View {
        GeometryReader { geo in
            ForEach(Self.points, id: \.id) { point in
                star(point, in: geo.size)
            }
        }
    }

    private func star(_ point: WidgetSkyStarPoint, in size: CGSize) -> some View {
        Circle()
            .fill(color.opacity(point.alpha))
            .frame(width: point.size, height: point.size)
            .position(x: size.width * point.x, y: size.height * point.y)
    }
}

// MARK: - 行程點

/// 行程點：會議實心圓、我的行事曆空心圓、系統行事曆小方塊、旅遊小飛機。
/// 著色模式把顏色洗成同一色，靠形狀分辨四種（J:59、179）。
struct WidgetStopMark: View {
    let kind: TimelineStopKind
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        switch kind {
        case .meeting:
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        case .personal:
            Circle()
                .strokeBorder(color, lineWidth: ringWidth)
                .frame(width: size, height: size)
        case .appleCalendar:
            RoundedRectangle(cornerRadius: size * 0.18)
                .fill(color)
                .frame(width: squareSide, height: squareSide)
        case .trip:
            Image(systemName: "airplane")
                .font(.system(size: size * 1.15, weight: .bold))
                .foregroundStyle(color)
        }
    }

    private var ringWidth: CGFloat { max(1.5, size * 0.22) }

    /// 方塊看起來比圓大，縮一點
    private var squareSide: CGFloat { size * 0.88 }
}
