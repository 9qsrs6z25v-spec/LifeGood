import SwiftUI
import UIKit

// MARK: - 跑步畫面的零件（v25.555，健康 v5；health/judge.md §4.0–4.2、樣稿②-2／②-3、③-B1～B9；build/v5/brief.md §G2）
//
// G2 寫：天空面板（開始前／跑步中／暫停）、GPS 燈膠囊、四顆運動膠囊、直徑 88 的開始圓鈕、大字＋三格（點了換）、
// 「這一公里」小步道、暫停／按住結束、GPS 弱提示條、倒數 3-2-1、位置說明卡、浮在地圖上的膠囊鈕。
// RunTrackingView.swift 只管狀態、地圖、流程；這裡的 view 只畫，按了就呼叫傳進來的閉包，不寫任何 store。
//
// • 字都由 RunTrackingView 的 computed var 組好再傳進來（坑 #7：body 不寫長運算式）；這裡只排版、上色。
// • 每個要給別的檔用的零件都寫明確的 init（有 private 的 @Environment／@State 時，自動合成的 init 會變 private）。
// • 天空底是 Canvas：RunSkyArt 是 Equatable＋.equatable()（坑 #5），每秒重畫面板時不重畫天空。
// • 天空用看板同一支 TripBoardSkyArt.paintSky（樣稿的 skyfill：上面晴藍、下面淡；深色自動是夜空＋星星），右上的雲同一支 cloud；
//   暫停整片灰藍（淺 C9D3E0 → E3E8EF、深 2A3142 → 1E2433，樣稿③-B5）。
// • 字色一律 TripBoardPalette（ink／label／inkDate），深色模式跟著換。

// MARK: - 尺寸

/// 跑步畫面幾個要跟 RunTrackingView 對齊的數字
enum RunScreenMetrics {
    /// 天空面板的內容離面板上緣（GPS 弱提示條下面）多遠。RunTrackingView 量內容的位置後減掉它，
    /// 算地圖下緣要讓多少（提示條出現、消失時地圖不跟著跳）
    static let panelTopPadding: CGFloat = 14
    /// GPS 弱提示條的高
    static let weakStripHeight: CGFloat = 28
}

// MARK: - 數字加粗的一句話

/// 一句話裡的數字加粗（「420／1000 m・2'40"」「第 4 公里」「這週跑了 9.4 公里・目標 20」「已暫停・1:12」）。
/// 一段一段接成一個 Text（同 FinanceLineText：用插值接，不串 +）；數字以外的字照外面給的字型、顏色
enum RunNumberText {
    static func text(_ s: String, numberColor: Color) -> Text {
        var out: Text? = nil
        for run in runs(s) {
            let next = piece(run.text, isNumber: run.isNumber, numberColor: numberColor)
            if let prev = out {
                out = Text("\(prev)\(next)")
            } else {
                out = next
            }
        }
        return out ?? Text(verbatim: s)
    }

    private static func piece(_ s: String, isNumber: Bool, numberColor: Color) -> Text {
        let t = Text(verbatim: s)
        guard isNumber else { return t }
        return t.fontWeight(.heavy).foregroundStyle(numberColor)
    }

    /// 切成「數字」「不是數字」一段一段：0～9 算數字，數字後面接著的 . : ' " 也算（「6'20"」「2.6」「21:05」）。
    /// 只認半形數字：國字「一」也是 Unicode 數字，「這一公里」不能被加粗
    static func runs(_ s: String) -> [(text: String, isNumber: Bool)] {
        var out: [(text: String, isNumber: Bool)] = []
        var cur = ""
        var curIsNumber = false
        for ch in s {
            let digit = ch >= "0" && ch <= "9"
            let joins = curIsNumber && !cur.isEmpty && (ch == "." || ch == ":" || ch == "'" || ch == "\"")
            let isNumber = digit || joins
            if !cur.isEmpty && isNumber != curIsNumber {
                out.append((text: cur, isNumber: curIsNumber))
                cur = ""
            }
            curIsNumber = isNumber
            cur.append(ch)
        }
        if !cur.isEmpty {
            out.append((text: cur, isNumber: curIsNumber))
        }
        return out
    }
}

// MARK: - 天空面板

/// 天空面板的底（Canvas）：白天看板的天空漸層＋雲；深色是夜空＋星星；暫停是整片灰藍。
/// Equatable＋.equatable()（坑 #5）：面板每秒重畫時，輸入沒變就不重畫天空
struct RunSkyArt: View, Equatable {
    let dark: Bool
    let paused: Bool
    /// 畫幾朵雲：開始前 2 朵（右上、開始鈕右邊）、跑步中 1 朵（右邊那朵會擋到數字）
    let clouds: Int

    init(dark: Bool, paused: Bool, clouds: Int) {
        self.dark = dark
        self.paused = paused
        self.clouds = clouds
    }

    var body: some View {
        Canvas { ctx, size in
            Self.paint(&ctx, size: size, art: self)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 雲的位置（寬、高的比例）與寬度（面板寬的比例）：樣稿 skyfill 的前兩個位置
    private static let cloudSpots: [(x: CGFloat, y: CGFloat, w: CGFloat)] = [
        (x: 0.62, y: 0.05, w: 0.15),
        (x: 0.88, y: 0.42, w: 0.16)
    ]

    static func paint(_ ctx: inout GraphicsContext, size: CGSize, art a: RunSkyArt) {
        guard size.width > 20, size.height > 20 else { return }
        let rect = Path(CGRect(origin: .zero, size: size))
        if a.paused {
            let colors = a.dark ? [Color(tb: 0x2A3142), Color(tb: 0x1E2433)] : [Color(tb: 0xC9D3E0), Color(tb: 0xE3E8EF)]
            ctx.fill(rect, with: .linearGradient(Gradient(colors: colors), startPoint: .zero,
                                                 endPoint: CGPoint(x: 0, y: size.height)))
        } else {
            TripBoardSkyArt.paintSky(&ctx, size: size, dark: a.dark)
            if a.dark {
                TripBoardSkyArt.paintStars(&ctx, width: size.width, bottom: size.height * 0.6,
                                           avoid: [], seed: 5, count: 22)
            }
        }
        let fill = cloudFill(dark: a.dark, paused: a.paused)
        for (i, s) in cloudSpots.enumerated() where i < a.clouds {
            let w = size.width * s.w
            let c = CGPoint(x: size.width * s.x, y: size.height * s.y + w * 0.2)
            ctx.fill(TripBoardSkyArt.cloud(center: c, width: w), with: .color(fill))
        }
    }

    private static func cloudFill(dark: Bool, paused: Bool) -> Color {
        if paused { return dark ? Color.white.opacity(0.06) : Color.white.opacity(0.55) }
        return dark ? Color(tb: 0x2A3A66, 0.5) : Color.white.opacity(0.92)
    }
}

/// 面板外殼：全寬、上面兩角圓（圓角讀英雄卡設定的「圓角」，同健康看板）、底延伸到安全區外（到螢幕最下面）。
/// strip：GPS 弱提示條（放在面板最上面、跟面板同一個圓角）；nil 不畫
struct RunSkyPanel<Content: View>: View {
    let paused: Bool
    let clouds: Int
    let strip: String?
    let content: Content

    @Environment(\.colorScheme) private var scheme
    /// 只讀「圓角」（同 HealthBoard）
    @ObservedObject private var heroStyle = HeroStyleStore.shared

    init(paused: Bool, clouds: Int, strip: String?, @ViewBuilder content: () -> Content) {
        self.paused = paused
        self.clouds = clouds
        self.strip = strip
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            if let strip {
                RunWeakStrip(text: strip, corner: corner)
            }
            content
                .padding(.horizontal, 18)
                .padding(.top, RunScreenMetrics.panelTopPadding)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background { sky }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var corner: CGFloat { CGFloat(heroStyle.value(.corner, .health)) }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: corner, topTrailingRadius: corner, style: .continuous)
    }

    private var shadowColor: Color {
        scheme == .dark ? Color.black.opacity(0.4) : Color(tb: 0x1E3A6E, 0.16)
    }

    /// 天空＋外框＋往上的淡陰影；延伸到底部安全區外（Home 指示條那一塊也是天空）。
    /// 天空墊一層實心的同形狀（.background）：天空是 Canvas、不接手指（allowsHitTesting(false)），
    /// 沒有這層的話，在面板空白的地方（開始鈕兩旁、格子之間）拖、捏會穿過去動到後面的地圖（v4 的面板是 .regularMaterial，擋得住）
    private var sky: some View {
        RunSkyArt(dark: scheme == .dark, paused: paused, clouds: clouds)
            .equatable()
            .background { shape.fill(TripBoardPalette(scheme).boardBottom) }
            .clipShape(shape)
            .overlay { shape.stroke(TripBoardPalette(scheme).cardStroke, lineWidth: 0.75) }
            .shadow(color: shadowColor, radius: 14, x: 0, y: -4)
            .ignoresSafeArea(edges: .bottom)
    }
}

/// 面板正上方那一條「GPS 訊號弱，距離可能少算」（樣稿③-B6；淡黃底＝看板「晚了」那一種提示）
struct RunWeakStrip: View {
    let text: String
    let corner: CGFloat

    @Environment(\.colorScheme) private var scheme

    init(text: String, corner: CGFloat) {
        self.text = text
        self.corner = corner
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(notice.text)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: RunScreenMetrics.weakStripHeight)
            .background(notice.fill, in: shape)
            .accessibilityAddTraits(.isStaticText)
    }

    private var notice: TripBoardPalette.Notice { TripBoardPalette(scheme).notice(.late) }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: corner, topTrailingRadius: corner, style: .continuous)
    }
}

// MARK: - 浮在地圖上的膠囊

/// 膠囊的樣子：bar＝上面那排左邊（15pt）、title＝中間標題（16pt 粗）、map＝地圖按鈕（13pt）、
/// mapSelected＝「看整條路」開著（深藍底白字）、mapLink＝「回到我身邊」（藍字）
enum RunCapsuleStyle {
    case bar, title, map, mapSelected, mapLink
}

/// 白底膠囊＋淡陰影（深色用 .regularMaterial）；當 Button 的 label 用，自己不接按鈕
struct RunFloatingCapsule: View {
    let title: String
    let icon: String?
    let style: RunCapsuleStyle

    @Environment(\.colorScheme) private var scheme

    init(title: String, icon: String? = nil, style: RunCapsuleStyle) {
        self.title = title
        self.icon = icon
        self.style = style
    }

    var body: some View {
        label
            .font(font)
            .foregroundStyle(textColor)
            .lineLimit(1)
            .padding(.horizontal, 13)
            .frame(minHeight: 34)
            .background { chrome }
            .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 2)
    }

    @ViewBuilder
    private var label: some View {
        if let icon {
            Label(title, systemImage: icon)
                .labelStyle(RunTightLabelStyle())
        } else {
            Text(title)
        }
    }

    private var font: Font {
        switch style {
        case .bar: return .subheadline.weight(.bold)
        case .title: return .headline.weight(.heavy)
        case .map, .mapSelected, .mapLink: return .footnote.weight(.bold)
        }
    }

    private var textColor: Color {
        let pal = TripBoardPalette(scheme)
        switch style {
        case .mapSelected: return .white
        case .mapLink: return scheme == .dark ? pal.hint : Color(tb: 0x0A6FE0)
        case .bar, .title, .map: return pal.ink
        }
    }

    @ViewBuilder
    private var chrome: some View {
        if style == .mapSelected {
            Capsule().fill(scheme == .dark ? Color(tb: 0x2F5BB7) : Color(tb: 0x1D2B55))
        } else if scheme == .dark {
            Capsule().fill(.regularMaterial)
        } else {
            Capsule().fill(Color.white.opacity(0.9))
        }
    }
}

/// 圖示和字靠近一點（系統 Label 的間距在 15pt 字旁邊太開）
struct RunTightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
                .imageScale(.small)
            configuration.title
        }
    }
}

/// 右上「⋯」那顆圓鈕（Menu 的 label）
struct RunFloatingCircle: View {
    let icon: String

    @Environment(\.colorScheme) private var scheme

    init(icon: String) {
        self.icon = icon
    }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(TripBoardPalette(scheme).ink)
            .frame(width: 34, height: 34)
            .background { chrome }
            .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 2)
            .contentShape(Circle())
    }

    @ViewBuilder
    private var chrome: some View {
        if scheme == .dark {
            Circle().fill(.regularMaterial)
        } else {
            Circle().fill(Color.white.opacity(0.9))
        }
    }
}

/// 「回到我身邊」下面那行小字「10 秒後自己回來」
struct RunHintTag: View {
    let text: String

    @Environment(\.colorScheme) private var scheme

    init(text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(scheme == .dark ? TripBoardPalette(scheme).label : Color(tb: 0x3E4A6E))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var fill: Color {
        scheme == .dark ? Color(tb: 0x1C2646, 0.86) : Color.white.opacity(0.85)
    }
}

/// 上面那排膠囊下面的「正在找你的位置…」（樣稿③-B1：轉圈＋字）
struct RunFindingCapsule: View {
    @Environment(\.colorScheme) private var scheme

    init() {}

    var body: some View {
        HStack(spacing: 7) {
            ProgressView()
                .controlSize(.small)
            Text("正在找你的位置…")
                .font(.footnote.weight(.bold))
                .foregroundStyle(TripBoardPalette(scheme).ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 32)
        .background { chrome }
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 2)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var chrome: some View {
        if scheme == .dark {
            Capsule().fill(.regularMaterial)
        } else {
            Capsule().fill(Color.white.opacity(0.94))
        }
    }
}

// MARK: - 地圖上的小東西

/// 每整公里一塊白底小牌（樣子同成果頁的 WorkoutDetailKmPill：10pt 粗圓體、深藍字）
struct RunKmPill: View {
    let km: Int

    init(km: Int) {
        self.km = km
    }

    var body: some View {
        Text(verbatim: "\(km)")
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color(tb: 0x0B1B45))
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Color.white, in: Capsule())
            .overlay(Capsule().stroke(Color(tb: 0x0B1B45, 0.25), lineWidth: 0.75))
            .shadow(color: Color.black.opacity(0.18), radius: 1.5, x: 0, y: 1)
            .accessibilityLabel("第 \(km) 公里")
    }
}

/// 起點：白圈、運動色邊
struct RunStartDot: View {
    let tint: Color

    init(tint: Color) {
        self.tint = tint
    }

    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(tint, lineWidth: 4))
            .accessibilityLabel("起點")
    }
}

// MARK: - GPS 燈

/// 面板左上的 GPS 燈膠囊：燈（顏色由呼叫端決定）＋字＋藍字連結（「去設定打開」「打開精確位置」）
struct RunGPSCapsule: View {
    let color: Color
    let text: String
    let link: String?
    let onLink: () -> Void

    @Environment(\.colorScheme) private var scheme

    init(color: Color, text: String, link: String?, onLink: @escaping () -> Void) {
        self.color = color
        self.text = text
        self.link = link
        self.onLink = onLink
    }

    var body: some View {
        HStack(spacing: 6) {
            lamp
            RunNumberText.text(text, numberColor: pal.capsuleText)
                .font(.caption.weight(.bold))
                .foregroundStyle(pal.capsuleText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let link {
                Button(link, action: onLink)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(linkColor)
                    .buttonStyle(.plain)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 26)
        .background(pal.capsuleFill, in: Capsule())
        .overlay(Capsule().stroke(pal.capsuleStroke, lineWidth: 0.75))
    }

    private var pal: TripBoardPalette { TripBoardPalette(scheme) }

    private var linkColor: Color {
        scheme == .dark ? pal.hint : Color(tb: 0x2F7FE8)
    }

    /// 燈＋一圈同色的淡光暈
    private var lamp: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .background(Circle().fill(color.opacity(0.22)).frame(width: 13, height: 13))
            .accessibilityHidden(true)
    }
}

// MARK: - 開始前

/// 四顆運動膠囊（樣稿②-2）：選中的深藍底白字，其他白底深藍字
struct RunSportPicker: View {
    let selected: RunSport
    let onPick: (RunSport) -> Void

    @Environment(\.colorScheme) private var scheme

    init(selected: RunSport, onPick: @escaping (RunSport) -> Void) {
        self.selected = selected
        self.onPick = onPick
    }

    var body: some View {
        HStack(spacing: 7) {
            ForEach(RunSport.allCases) { s in
                chip(s)
            }
        }
    }

    private var pal: TripBoardPalette { TripBoardPalette(scheme) }

    private var selectedFill: Color {
        scheme == .dark ? Color(tb: 0x2F5BB7) : pal.ink
    }

    private var chipFill: Color {
        scheme == .dark ? pal.capsuleFill : Color.white.opacity(0.78)
    }

    private func chip(_ s: RunSport) -> some View {
        let on = s == selected
        return Button {
            onPick(s)
        } label: {
            Label(s.rawValue, systemImage: WorkoutSport(s).icon)
                .labelStyle(RunTightLabelStyle())
                .font(.footnote.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(on ? Color.white : pal.ink)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(on ? selectedFill : chipFill, in: Capsule())
        }
        .buttonStyle(MoneyPressStyle())
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// 直徑 88 的綠色圓鈕「開始」＋外圈 10pt 淡綠光環；不能按（沒有位置權限）時灰色、沒有光環
struct RunStartCircle: View {
    let enabled: Bool
    let action: () -> Void

    init(enabled: Bool, action: @escaping () -> Void) {
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text("開始")
                .font(.title2.weight(.heavy))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 88, height: 88)
                .background(Circle().fill(fill))
        }
        .buttonStyle(MoneyPressStyle())
        .background { halo }
        .shadow(color: enabled ? WorkoutPalette.go.opacity(0.35) : Color.clear, radius: 7, x: 0, y: 4)
        .disabled(!enabled)
        .accessibilityLabel("開始")
        .accessibilityHint(enabled ? "開始記錄這一趟" : "沒有位置權限，記不了路線")
    }

    private var fill: Color {
        enabled ? WorkoutPalette.go : Color(.systemGray3)
    }

    @ViewBuilder
    private var halo: some View {
        if enabled {
            Circle()
                .fill(WorkoutPalette.go.opacity(0.18))
                .padding(-10)
        }
    }
}

/// 開始鈕下面兩行：「這週跑了 9.4 公里・目標 20」（粗、數字更粗）＋「上一趟：昨天 06:10・晨跑 5.1 公里」（灰）
struct RunIntroLines: View {
    let week: String
    let second: String?

    @Environment(\.colorScheme) private var scheme

    init(week: String, second: String?) {
        self.week = week
        self.second = second
    }

    var body: some View {
        VStack(spacing: 4) {
            RunNumberText.text(week, numberColor: pal.ink)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(pal.ink)
            if let second {
                Text(second)
                    .font(.footnote)
                    .foregroundStyle(pal.label)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var pal: TripBoardPalette { TripBoardPalette(scheme) }
}

/// 第一次打開、位置還沒問過：先出我們的說明卡，按〔好〕才跳系統的位置框（judge §4.1 第 1 列）
struct RunPermissionCard: View {
    let tint: Color
    let onOK: () -> Void

    @Environment(\.colorScheme) private var scheme

    static let title = "需要你的位置"
    static let message = "要畫出你跑過的路，需要用你的位置。下一步選「使用 App 時允許」就好；鎖著螢幕也會繼續記，狀態列左上會出現藍色標示。"

    init(tint: Color, onOK: @escaping () -> Void) {
        self.tint = tint
        self.onOK = onOK
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Text(Self.message)
                .font(.subheadline)
                .foregroundStyle(pal.label)
                .fixedSize(horizontal: false, vertical: true)
            okButton
        }
        .padding(16)
        .background(pal.cellFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(pal.cellStroke, lineWidth: 0.75))
    }

    private var pal: TripBoardPalette { TripBoardPalette(scheme) }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill")
                .font(.headline)
                .foregroundStyle(tint)
            Text(Self.title)
                .font(.headline)
                .foregroundStyle(pal.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var okButton: some View {
        Button(action: onOK) {
            Text("好")
                .font(.headline)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(WorkoutPalette.go, in: Capsule())
        }
        .buttonStyle(MoneyPressStyle())
    }
}

// MARK: - 跑步中

/// 大字「3.42 公里」（56pt 圓體粗字、等寬）
struct RunLiveReadout: View {
    let number: String
    let unit: String

    @Environment(\.colorScheme) private var scheme

    init(number: String, unit: String) {
        self.number = number
        self.unit = unit
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(number)
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(pal.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(pal.inkDate)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(number + " " + unit)
    }

    private var pal: TripBoardPalette { TripBoardPalette(scheme) }
}

/// 三格裡的一格（字由 RunTrackingView 組好）
struct RunStatCellData: Equatable {
    /// 「21:05」「6'20"」「約 220」「—」
    let value: String
    /// 「時間」「這一公里」「大卡」
    let label: String
    /// VoiceOver 唸的（「這一公里 6 分 20 秒」）
    let spoken: String
    /// 「點兩下換成爬升」；nil＝固定的那一格（右格），不能點
    let hint: String?

    init(value: String, label: String, spoken: String, hint: String?) {
        self.value = value
        self.label = label
        self.spoken = spoken
        self.hint = hint
    }
}

/// 三格（中間兩條直線分隔；值 28pt 圓體粗字等寬、標籤 caption）；能換的格子點了呼叫 onTap(第幾格)
struct RunStatRow: View {
    let cells: [RunStatCellData]
    let onTap: (Int) -> Void

    @Environment(\.colorScheme) private var scheme

    init(cells: [RunStatCellData], onTap: @escaping (Int) -> Void) {
        self.cells = cells
        self.onTap = onTap
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(Array(cells.indices), id: \.self) { i in
                if i > 0 {
                    divider
                }
                cell(i)
                    .padding(.leading, i > 0 ? 12 : 0)
            }
        }
    }

    private var pal: TripBoardPalette { TripBoardPalette(scheme) }

    private var divider: some View {
        Rectangle()
            .fill(pal.label.opacity(0.3))
            .frame(width: 0.75, height: 36)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func cell(_ i: Int) -> some View {
        let c = cells[i]
        if let hint = c.hint {
            Button {
                onTap(i)
            } label: {
                cellBody(c)
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityLabel(c.spoken)
            .accessibilityHint(hint)
        } else {
            cellBody(c)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(c.spoken)
        }
    }

    private func cellBody(_ c: RunStatCellData) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(c.value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(pal.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(c.label)
                .font(.caption.weight(.bold))
                .foregroundStyle(pal.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// 「這一公里」小步道（樣稿②-3、③-B7）：8pt 軌道，已走的運動色漸層、沒走的點狀虛線；條頭一顆 22pt 白圓（運動色邊＋運動圖示）；
/// 右邊「420／1000 m・2'40"」（騎車「這 5 公里 2.6／5 公里」）
struct RunLegTrail: View {
    let fraction: Double
    let colors: [Color]
    let tint: Color
    let icon: String
    let text: String
    let spoken: String

    @Environment(\.colorScheme) private var scheme

    init(fraction: Double, colors: [Color], tint: Color, icon: String, text: String, spoken: String) {
        self.fraction = fraction
        self.colors = colors
        self.tint = tint
        self.icon = icon
        self.text = text
        self.spoken = spoken
    }

    var body: some View {
        HStack(spacing: 10) {
            RunLegTrack(fraction: fraction, colors: colors, tint: tint, icon: icon, dash: dashColor)
                .frame(height: 22)
            RunNumberText.text(text, numberColor: pal.ink)
                .font(.caption.weight(.semibold))
                .foregroundStyle(pal.label)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var pal: TripBoardPalette { TripBoardPalette(scheme) }

    private var dashColor: Color {
        scheme == .dark ? Color.white.opacity(0.18) : Color(tb: 0xC9D6EA)
    }
}

/// 小步道的軌道本身（寬度跟著外面給的空間）
private struct RunLegTrack: View {
    let fraction: Double
    let colors: [Color]
    let tint: Color
    let icon: String
    let dash: Color

    var body: some View {
        GeometryReader { geo in
            track(width: geo.size.width, height: geo.size.height)
        }
    }

    private func track(width w: CGFloat, height h: CGFloat) -> some View {
        let f = CGFloat(fraction.isFinite ? min(1, max(0, fraction)) : 0)
        let headX = min(max(w * f, 11), max(11, w - 11))
        return ZStack(alignment: .leading) {
            Path { p in
                p.move(to: CGPoint(x: 0, y: h / 2))
                p.addLine(to: CGPoint(x: w, y: h / 2))
            }
            .stroke(dash, style: StrokeStyle(lineWidth: 8, dash: [4, 4]))
            Capsule()
                .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                .frame(width: max(8, headX), height: 8)
            head
                .position(x: headX, y: h / 2)
        }
    }

    private var head: some View {
        Image(systemName: icon)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 22, height: 22)
            .background(Circle().fill(Color.white))
            .overlay(Circle().stroke(tint, lineWidth: 1.5))
            .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
    }
}

// MARK: - 按鈕

/// white＝白膠囊深藍字（暫停、暫停中的結束）；green＝綠膠囊白字＋外圈淡綠光環（繼續、按住結束）
enum RunPanelButtonStyle {
    case white, green
}

/// 面板下面的大按鈕（高 54、膠囊）的樣子；按住結束也用它
struct RunPanelButtonFace: View {
    let title: String
    let icon: String
    let style: RunPanelButtonStyle

    @Environment(\.colorScheme) private var scheme

    init(title: String, icon: String, style: RunPanelButtonStyle) {
        self.title = title
        self.icon = icon
        self.style = style
    }

    var body: some View {
        Label(title, systemImage: icon)
            .labelStyle(RunTightLabelStyle())
            .font(.headline.weight(.heavy))
            .foregroundStyle(textColor)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(fill, in: Capsule())
            .background { halo }
            .shadow(color: shadowColor, radius: 4, x: 0, y: 2)
    }

    private var pal: TripBoardPalette { TripBoardPalette(scheme) }

    private var textColor: Color {
        style == .green ? Color.white : pal.ink
    }

    private var fill: Color {
        switch style {
        case .green: return WorkoutPalette.go
        case .white: return scheme == .dark ? Color(tb: 0x1C2646) : Color.white
        }
    }

    private var shadowColor: Color {
        style == .green ? WorkoutPalette.go.opacity(0.3) : Color(tb: 0x1E3A6E, 0.12)
    }

    @ViewBuilder
    private var halo: some View {
        if style == .green {
            Capsule()
                .fill(WorkoutPalette.go.opacity(0.18))
                .padding(-4)
        }
    }
}

/// 一般的大按鈕（暫停、繼續、暫停中的結束）
struct RunPanelButton: View {
    let title: String
    let icon: String
    let style: RunPanelButtonStyle
    let action: () -> Void

    init(title: String, icon: String, style: RunPanelButtonStyle, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            RunPanelButtonFace(title: title, icon: icon, style: style)
        }
        .buttonStyle(MoneyPressStyle())
    }
}

/// 跑步中「■ 按住結束」：按住 1 秒（RunSport.holdToFinishSeconds）外圈線性填滿才結束，放開就退回；只點一下不會結束。
/// 開著 VoiceOver 改成一般按鈕，點了呼叫 onAsk（呼叫端跳「結束這一趟？」）
struct RunHoldToFinishButton: View {
    let onFinish: () -> Void
    let onAsk: () -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    /// 外圈填多滿（0…1）
    @State private var progress: CGFloat = 0

    init(onFinish: @escaping () -> Void, onAsk: @escaping () -> Void) {
        self.onFinish = onFinish
        self.onAsk = onAsk
    }

    var body: some View {
        if voiceOver {
            askButton
        } else {
            holdFace
        }
    }

    private var face: some View {
        RunPanelButtonFace(title: "按住結束", icon: "stop.fill", style: .green)
    }

    private var askButton: some View {
        Button(action: onAsk) {
            face
        }
        .buttonStyle(MoneyPressStyle())
        .accessibilityLabel("結束")
        .accessibilityHint("點兩下會先問要不要結束這一趟")
    }

    private var holdFace: some View {
        face
            .overlay { ring }
            .contentShape(Capsule())
            .onLongPressGesture(minimumDuration: RunSport.holdToFinishSeconds, maximumDistance: 40,
                                perform: { onFinish() },
                                onPressingChanged: { pressing in pressingChanged(pressing) })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("按住結束")
            .accessibilityHint("按住一秒結束這一趟")
            .accessibilityAddTraits(.isButton)
    }

    /// 外圈 4pt（跟淡綠光環同一圈）：按住時從 0 填到滿
    private var ring: some View {
        Capsule()
            .trim(from: 0, to: progress)
            .stroke(WorkoutPalette.go, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .padding(-2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func pressingChanged(_ pressing: Bool) {
        if pressing {
            withAnimation(.linear(duration: RunSport.holdToFinishSeconds)) { progress = 1 }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
        }
    }
}

// MARK: - 倒數

/// 倒數 3-2-1（樣稿③-B8）：半透明天空蓋整個畫面、手寫「Ready?」斜 −8°、大字 3 → 2 → 1 →「開始！」、「點一下跳過」；
/// 點任何地方＝馬上開始（onSkip）、左上 ✕＝取消（onCancel，不開始）。VoiceOver 整層一個元素
struct RunCountdownOverlay: View {
    /// 3、2、1；0＝「開始！」（已經開始了，✕ 不畫）
    let value: Int
    let onSkip: () -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var scheme

    init(value: Int, onSkip: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.value = value
        self.onSkip = onSkip
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                backdrop
                center
            }
            .contentShape(Rectangle())
            .onTapGesture { onSkip() }
            if value > 0 {
                cancelButton
                    .padding(.leading, 16)
                    .padding(.top, 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits([.isButton, .isModal])     // 倒數時 VoiceOver 不會跑到後面的運動膠囊、開始鈕
        .accessibilityAction { onSkip() }
        .accessibilityAction(.escape) { onCancel() }
    }

    private var pal: TripBoardPalette { TripBoardPalette(scheme) }

    private var bigText: String { value > 0 ? "\(value)" : "開始！" }

    private var spoken: String { value > 0 ? "倒數 \(value) 秒，點兩下馬上開始" : "開始！" }

    private var backdropColors: [Color] {
        scheme == .dark
            ? [Color(tb: 0x0A1433, 0.9), Color(tb: 0x121B38, 0.92)]
            : [Color(tb: 0x8FD3FF, 0.86), pal.boardTop.opacity(0.92)]
    }

    private var backdrop: some View {
        LinearGradient(colors: backdropColors, startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    private var center: some View {
        VStack(spacing: 0) {
            Text("Ready?")
                .font(TripScriptFont.greeting(34))
                .foregroundStyle(pal.hint)
                .rotationEffect(.degrees(-8))
                .padding(.bottom, -6)
            Text(bigText)
                .font(.system(size: 120, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(pal.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            Text("點一下跳過")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(pal.label)
                .padding(.top, 18)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(pal.ink)
                .frame(width: 36, height: 36)
                .background(Circle().fill(scheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.8)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("取消")
    }
}
