import SwiftUI

// MARK: - 收支看板的頭部：天空＋一幅用資料畫的風景（v25.526）
//
// 使用者：「項目達標了，上方看板差強人意，你再好好規劃」，看過樣稿後「五個一次做完」。
//
// 差強人意在哪：行程看板的頭部是一整幅畫（天空、雲、天際線、客機、手寫的 Have a nice trip!），
// 收支看板只有字和角落一個小太陽，畫面上看不到自己這個月的錢。
//
// 這一版五頁的看板都換成同一套頭部：
//   日期列（左）＋膠囊（右）／小字／大字／一句話
//   ＋右邊手寫的兩行問候（Have a nice／October!）
//   ＋最下面一條「風景」，每一頁畫自己的資料：
//     總覽     城市：每天一棟樓（高度＝那天花多少）、沒花錢的日子種一棵樹、還沒到的日子是空地、
//              日預算虛線（超過的那一截樓頂變橘）、地上一條鐵道（固定支出的扣款日是車站，電車停在今天）
//     變動支出 市集：一家店是一個分類，店面寬度＝這個月那一類花多少，雨棚是分類色
//     收入     山：近 6 個月一個月一座山，這個月的山用虛線畫出預期的高度、插旗
//     固定支出 列車：這個月的鐵道，一筆固定支出一個車站，扣過的打勾，電車停在今天，下一站有小牌子
//     圖表     星空：這一段期間每一期花多少連成星座，最多的那一期是最亮的星
//
// 天空、雲、星星、遠處的樓直接用行程看板那幾支（TripBoardSkyArt），兩塊看板是同一個天空。
// 規矩一樣：要讀的數字一律是 Text；插畫看得到、不給讀（整塊 accessibilityHidden），
// 風景只畫在最下面那一條（band）裡，不長到字的後面；手寫問候用 anchor 量出大字在哪，寫在它右邊。

// MARK: - 風景的資料

/// 鐵道上的一站（固定支出的扣款日）
struct MoneyRailStation: Equatable {
    let day: Int
    let past: Bool
    var isNext: Bool = false
}

/// 總覽：這個月的城市
struct MoneyCityScene: Equatable {
    var daysInMonth: Int
    var today: Int
    /// 1 號到今天，每天的變動支出
    var daily: [Double]
    /// 這個月從哪一天開始有記帳（之前的日子不種樹：那不是沒花錢，是還沒記）
    var firstDay: Int = 1
    /// 日預算（扣掉固定支出之後平均每天可以花多少）；沒有收入紀錄是 nil
    var dailyBudget: Double? = nil
    var budgetLabel: String? = nil
    var stations: [MoneyRailStation] = []
    /// 下一站的字（「明天扣 Netflix」）
    var nextLabel: String? = nil
}

/// 變動支出：市集
struct MoneyMarketScene: Equatable {
    struct Shop: Equatable {
        let theme: MoneyArtTheme
        let amount: Double
        let share: Double
    }
    var shops: [Shop]
}

/// 收入：山
struct MoneyMountainScene: Equatable {
    struct Peak: Equatable {
        let label: String
        let value: Double
    }
    /// 最後一座是這個月
    var peaks: [Peak]
    /// 這個月預期的高度（虛線＋旗子）；已經超過就是 nil
    var expected: Double? = nil
    var expectedLabel: String? = nil
}

/// 固定支出：列車
struct MoneyRailScene: Equatable {
    var month: Int
    var daysInMonth: Int
    var today: Int
    var stations: [MoneyRailStation]
    var nextTitle: String? = nil
    var nextDetail: String? = nil
}

/// 圖表：星空
struct MoneyStarScene: Equatable {
    var values: [Double]
    var maxLabel: String? = nil
}

enum MoneyBoardScene: Equatable {
    case city(MoneyCityScene)
    case market(MoneyMarketScene)
    case mountains(MoneyMountainScene)
    case railway(MoneyRailScene)
    case stars(MoneyStarScene)
    // [v25.527] 理財六頁（資料與畫法在 FinanceBoardScenes.swift）
    case town(FinTownScene)
    case balloons(FinBalloonScene)
    case orchard(FinOrchardScene)
    case road(FinRoadScene)
    case street(FinStreetScene)
    case aurora(FinAuroraScene)
    // [v25.528] 股票卡片：這一檔近一年的股價山稜
    case ridge(FinRidgeScene)
}

// MARK: - 頭部的字

/// 頭部那幾段字的位置（插畫要讓開）
struct MoneyBoardTextRects: Equatable {
    var date: CGRect = .zero
    var capsule: CGRect = .zero
    var label: CGRect = .zero
    var big: CGRect = .zero
    var line: CGRect = .zero

    var all: [CGRect] { [date, capsule, label, big, line].filter { !$0.isEmpty } }
}

struct MoneyBoardAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// 收支看板的頭部。
///
/// 字是一般的 SwiftUI Text（跟著動態字級、VoiceOver 唸得到）；天空與風景是後面的一張 Canvas，
/// 用 anchorPreference 量出每一段字的位置：星星、雲讓開字，手寫問候寫在大字的右邊，
/// 風景只畫在最下面那一條（band，字的下面）。
struct MoneyBoardHeader: View {
    let date: String
    var dateIcon: String = "calendar"
    var capsule: String? = nil
    var capsuleIcon: String? = nil
    /// 膠囊的字色（股票的今日漲跌：紅漲綠跌）；nil＝一般的膠囊字色
    var capsuleTint: Color? = nil
    let label: String
    let big: String
    var bigTone: MoneyTone? = nil
    var line: Text? = nil
    /// 手寫問候（一到兩行，英文；手寫字型沒有中文字形）
    var greeting: [String] = []
    let scene: MoneyBoardScene
    /// 風景那一條的高度
    var band: CGFloat = 112
    var seed: Int = 0

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        VStack(alignment: .leading, spacing: 0) {
            // 字放很大時日期與膠囊排不下一列，膠囊改到日期下面（同行程看板）
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 0) {
                    dateLabel(pal)
                    Spacer(minLength: 8)
                    capsuleView(pal)
                }
                VStack(alignment: .leading, spacing: 4) {
                    dateLabel(pal)
                    capsuleView(pal)
                }
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(pal.label)
                .lineLimit(1)
                .padding(.top, 6)
                .anchorPreference(key: MoneyBoardAnchorKey.self, value: .bounds) { ["label": $0] }
            Text(big)
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(bigTone?.color(pal) ?? pal.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .anchorPreference(key: MoneyBoardAnchorKey.self, value: .bounds) { ["big": $0] }
            if let line {
                line
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(pal.inkDate)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .anchorPreference(key: MoneyBoardAnchorKey.self, value: .bounds) { ["line": $0] }
            }
            Color.clear
                .frame(height: band)
        }
        .padding(.top, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .backgroundPreferenceValue(MoneyBoardAnchorKey.self) { anchors in
            GeometryReader { geo in
                MoneyBoardSky(dark: pal.dark, scene: scene, greeting: greeting, seed: seed,
                              rects: Self.rects(geo, anchors), band: band)
                    .equatable()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func dateLabel(_ pal: TripBoardPalette) -> some View {
        HStack(spacing: 6) {
            Image(systemName: dateIcon)
                .font(.footnote.weight(.bold))
            Text(date)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(pal.inkDate)
        .fixedSize()
        .anchorPreference(key: MoneyBoardAnchorKey.self, value: .bounds) { ["date": $0] }
    }

    @ViewBuilder
    private func capsuleView(_ pal: TripBoardPalette) -> some View {
        if let capsule {
            HStack(spacing: 5) {
                if let capsuleIcon {
                    Image(systemName: capsuleIcon)
                        .font(.caption.weight(.bold))
                }
                Text(capsule)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .fixedSize()
            .foregroundStyle(capsuleTint ?? pal.capsuleText)
            .padding(.horizontal, 11)
            .frame(minHeight: 26)
            .background(pal.capsuleFill, in: Capsule())
            .overlay(Capsule().stroke(pal.capsuleStroke, lineWidth: 0.75))
            .anchorPreference(key: MoneyBoardAnchorKey.self, value: .bounds) { ["capsule": $0] }
        }
    }

    /// 字的位置取整數：小數點的版面抖動不要讓整幅畫重畫
    private static func rects(_ geo: GeometryProxy, _ a: [String: Anchor<CGRect>]) -> MoneyBoardTextRects {
        var r = MoneyBoardTextRects()
        if let x = a["date"] { r.date = geo[x].integral }
        if let x = a["capsule"] { r.capsule = geo[x].integral }
        if let x = a["label"] { r.label = geo[x].integral }
        if let x = a["big"] { r.big = geo[x].integral }
        if let x = a["line"] { r.line = geo[x].integral }
        return r
    }
}

// MARK: - 天空＋風景

/// Equatable＋.equatable()：Canvas 的閉包比不出有沒有變，輸入都是值，相同就不重畫。
struct MoneyBoardSky: View, Equatable {
    let dark: Bool
    let scene: MoneyBoardScene
    let greeting: [String]
    let seed: Int
    let rects: MoneyBoardTextRects
    let band: CGFloat

    var body: some View {
        Canvas { ctx, size in
            Self.paint(&ctx, size: size, art: self)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 手寫問候量好的樣子（先量、再讓星星和雲讓開它、最後才寫上去）
struct MoneyGreetingLayout {
    let texts: [GraphicsContext.ResolvedText]
    let size: CGFloat
    let lineGap: CGFloat
    let indent: CGFloat
    /// 轉之前的寬高
    let width: CGFloat
    let height: CGFloat
    let lastHeight: CGFloat
    let center: CGPoint
    /// 轉了之後佔的範圍
    let rect: CGRect
}

extension MoneyBoardSky {
    static let greetingAngle = -8.0

    static func paint(_ ctx: inout GraphicsContext, size: CGSize, art a: MoneyBoardSky) {
        let w = size.width
        let h = size.height
        guard w > 160, h > 80 else { return }
        let bandTop = h - a.band
        let region = scriptRegion(rects: a.rects, width: w, bandTop: bandTop)
        let greeting = greetingLayout(ctx, lines: a.greeting, region: region, dark: a.dark)
        var avoid = a.rects.all.map { $0.insetBy(dx: -4, dy: -3) }
        if let greeting { avoid.append(greeting.rect.insetBy(dx: -6, dy: -4)) }
        // 月牙（夜裡）：先找好位置，星星和雲也讓開它
        let moon = a.dark
            ? moonSpot(width: w, bandTop: bandTop, rects: a.rects, greeting: greeting?.rect, avoid: avoid)
            : nil
        if let moon { avoid.append(CGRect(x: moon.x - 12, y: moon.y - 12, width: 24, height: 24)) }

        TripBoardSkyArt.paintSky(&ctx, size: size, dark: a.dark)
        if a.dark {
            TripBoardSkyArt.paintStars(&ctx, width: w, bottom: bandTop - 4, avoid: avoid, seed: a.seed)
        }
        paintClouds(&ctx, width: w, bandTop: bandTop, dark: a.dark, avoid: avoid)
        if let moon {
            paintMoon(&ctx, at: moon)
        }

        let bandRect = CGRect(x: 0, y: bandTop, width: w, height: a.band)
        switch a.scene {
        case .city(let s): paintCity(&ctx, rect: bandRect, scene: s, dark: a.dark, seed: a.seed)
        case .market(let s): paintMarket(&ctx, rect: bandRect, scene: s, dark: a.dark, seed: a.seed)
        case .mountains(let s): paintMountains(&ctx, rect: bandRect, scene: s, dark: a.dark, seed: a.seed)
        case .railway(let s): paintRailway(&ctx, rect: bandRect, scene: s, dark: a.dark, seed: a.seed)
        case .stars(let s): paintConstellation(&ctx, rect: bandRect, scene: s, seed: a.seed)
        case .town(let s): paintTown(&ctx, rect: bandRect, scene: s, dark: a.dark, seed: a.seed)
        case .balloons(let s): paintBalloons(&ctx, rect: bandRect, scene: s, dark: a.dark, seed: a.seed)
        case .orchard(let s): paintOrchard(&ctx, rect: bandRect, scene: s, dark: a.dark, seed: a.seed)
        case .road(let s): paintYearRoad(&ctx, rect: bandRect, scene: s, dark: a.dark, seed: a.seed)
        case .street(let s): paintStreet(&ctx, rect: bandRect, scene: s, dark: a.dark, seed: a.seed)
        case .aurora(let s): paintAurora(&ctx, rect: bandRect, scene: s, seed: a.seed)
        case .ridge(let s): paintRidge(&ctx, rect: bandRect, scene: s, dark: a.dark, seed: a.seed)
        }

        if let greeting {
            drawGreeting(&ctx, greeting, dark: a.dark)
        }
    }

    /// 手寫問候可以寫的範圍：大字（和它上面那行小字）的右邊、日期列的下面
    static func scriptRegion(rects r: MoneyBoardTextRects, width w: CGFloat, bandTop: CGFloat) -> CGRect {
        guard !r.big.isEmpty else { return .zero }
        let top = max(r.date.maxY, r.capsule.maxY) + 2
        let left = max(r.big.maxX, r.label.maxX) + 12
        let bottom = min(max(r.big.maxY + 2, top + 30), bandTop - 4)
        return CGRect(x: left, y: top, width: max(0, w - 10 - left), height: max(0, bottom - top))
    }

    // MARK: 雲、月亮、手寫字

    static func paintClouds(_ ctx: inout GraphicsContext, width w: CGFloat, bandTop: CGFloat,
                            dark: Bool, avoid: [CGRect]) {
        let fill = dark ? Color(tb: 0x2A3A66, 0.5) : Color.white.opacity(0.92)
        // 遠的兩朵：貼在風景上緣、糊開、淡（風景畫在它前面）
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 5))
            layer.opacity = 0.6
            layer.fill(TripBoardSkyArt.cloud(center: CGPoint(x: w * 0.24, y: bandTop + 4), width: w * 0.34),
                       with: .color(fill))
            layer.fill(TripBoardSkyArt.cloud(center: CGPoint(x: w * 0.68, y: bandTop - 2), width: w * 0.26),
                       with: .color(fill))
        }
        // 近的：依序試幾個位置，壓到字或手寫問候就換下一個，最多兩朵
        let near: [(CGPoint, CGFloat)] = [(CGPoint(x: w * 0.9, y: bandTop - 8), w * 0.14),
                                          (CGPoint(x: w * 0.6, y: bandTop - 2), w * 0.2),
                                          (CGPoint(x: w * 0.52, y: 18), w * 0.13),
                                          (CGPoint(x: w * 0.8, y: bandTop - 34), w * 0.12)]
        var drawn = 0
        for (c, cw) in near where drawn < 2 {
            let path = TripBoardSkyArt.cloud(center: c, width: cw)
            let bb = path.boundingRect.insetBy(dx: -2, dy: -2)
            if avoid.contains(where: { $0.intersects(bb) }) { continue }
            drawn += 1
            ctx.fill(path, with: .color(fill))
            if !dark {
                ctx.fill(path, with: .linearGradient(
                    Gradient(colors: [Color(tb: 0xC9DDF0, 0), Color(tb: 0xC9DDF0, 0.55)]),
                    startPoint: CGPoint(x: 0, y: c.y - cw * 0.1),
                    endPoint: CGPoint(x: 0, y: c.y + cw * 0.12)))
            }
        }
    }

    /// 月牙放哪：依序試手寫問候的右邊、膠囊下面、風景上緣的右邊、日期與膠囊之間；
    /// 壓到字或手寫問候就換下一個，都不行就不畫（nil）
    static func moonSpot(width w: CGFloat, bandTop: CGFloat, rects r: MoneyBoardTextRects,
                         greeting: CGRect?, avoid: [CGRect]) -> CGPoint? {
        var spots: [CGPoint] = []
        if let g = greeting {
            spots.append(CGPoint(x: g.maxX + 16, y: g.minY + 8))
        }
        spots.append(CGPoint(x: w - 28, y: max(r.capsule.maxY, r.date.maxY) + 18))
        spots.append(CGPoint(x: w - 24, y: bandTop - 18))
        if !r.date.isEmpty, !r.capsule.isEmpty, r.capsule.minY < r.date.maxY {
            spots.append(CGPoint(x: (r.date.maxX + r.capsule.minX) / 2, y: r.date.midY))
        }
        for c in spots where c.x > 14 && c.x < w - 12 && c.y > 10 && c.y < bandTop - 14 {
            let box = CGRect(x: c.x - 12, y: c.y - 12, width: 24, height: 24)
            if avoid.contains(where: { $0.intersects(box) }) { continue }
            return c
        }
        return nil
    }

    static func paintMoon(_ ctx: inout GraphicsContext, at c: CGPoint) {
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 5))
            layer.fill(Path(ellipseIn: CGRect(x: c.x - 10, y: c.y - 10, width: 20, height: 20)),
                       with: .color(Color(tb: 0xF4EBC8, 0.35)))
        }
        var moon = ctx.resolve(Image(systemName: "moon.fill"))
        moon.shading = .color(Color(tb: 0xF4EBC8))
        ctx.draw(moon, in: CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14))
    }

    static func greetingColor(dark: Bool) -> Color {
        dark ? Color(tb: 0xCFE0FF, 0.85) : Color.white.opacity(0.94)
    }

    /// 手寫兩行（第二行縮排），往左上斜 8°。放不下就縮字，最小 14 還放不下就不寫（回 nil）。
    static func greetingLayout(_ ctx: GraphicsContext, lines: [String], region: CGRect,
                               dark: Bool) -> MoneyGreetingLayout? {
        guard !lines.isEmpty, region.width >= 60, region.height >= 24 else { return nil }
        let color = greetingColor(dark: dark)
        let rad = greetingAngle * Double.pi / 180
        let cosA = CGFloat(abs(cos(rad)))
        let sinA = CGFloat(abs(sin(rad)))
        let box = CGSize(width: 600, height: 200)
        for size: CGFloat in [22, 20, 18, 16, 15, 14] {
            var texts: [GraphicsContext.ResolvedText] = []
            var sizes: [CGSize] = []
            for line in lines {
                let t = ctx.resolve(Text(line).font(TripScriptFont.greeting(size)).foregroundStyle(color))
                texts.append(t)
                sizes.append(t.measure(in: box))
            }
            let indent = size * 0.6
            // 行距 0.92：再擠，第二行的大寫字頭會碰到第一行
            let lineGap = size * 0.92
            var bw: CGFloat = 0
            for (i, m) in sizes.enumerated() {
                bw = max(bw, (i > 0 ? indent : 0) + m.width)
            }
            let lastHeight = sizes.last?.height ?? size
            let bh = lineGap * CGFloat(lines.count - 1) + lastHeight + size * 0.25
            let outerW = bw * cosA + bh * sinA
            let outerH = bw * sinA + bh * cosA
            guard outerW <= region.width, outerH <= region.height else { continue }
            let center = CGPoint(x: region.minX + outerW / 2 + 2, y: region.midY)
            let rect = CGRect(x: center.x - outerW / 2, y: center.y - outerH / 2, width: outerW, height: outerH)
            return MoneyGreetingLayout(texts: texts, size: size, lineGap: lineGap, indent: indent,
                                       width: bw, height: bh, lastHeight: lastHeight,
                                       center: center, rect: rect)
        }
        return nil
    }

    /// 寫上去：一層淡淡的影子讓白字在淺色天空上讀得出來，最後一行底下一道收筆
    static func drawGreeting(_ ctx: inout GraphicsContext, _ l: MoneyGreetingLayout, dark: Bool) {
        let color = greetingColor(dark: dark)
        let x0 = -l.width / 2
        let y0 = -l.height / 2
        var g = ctx
        g.translateBy(x: l.center.x, y: l.center.y)
        g.rotate(by: .degrees(greetingAngle))
        g.drawLayer { layer in
            layer.addFilter(.shadow(color: Color(tb: 0x0B1B45, dark ? 0.6 : 0.35), radius: 1.5, x: 0, y: 0.5))
            for (i, t) in l.texts.enumerated() {
                layer.draw(t, at: CGPoint(x: x0 + (i > 0 ? l.indent : 0), y: y0 + l.lineGap * CGFloat(i)),
                           anchor: .topLeading)
            }
            var swash = Path()
            let sy = y0 + l.lineGap * CGFloat(l.texts.count - 1) + l.lastHeight * 0.92
            swash.move(to: CGPoint(x: x0 + l.indent * 0.6, y: sy + 1))
            swash.addQuadCurve(to: CGPoint(x: x0 + l.width, y: sy - l.size * 0.2),
                               control: CGPoint(x: x0 + l.width * 0.5, y: sy + l.size * 0.35))
            layer.stroke(swash, with: .color(color),
                         style: StrokeStyle(lineWidth: max(1, l.size * 0.06), lineCap: .round))
        }
    }

    // MARK: 共用小東西

    /// 遠處淡淡的一排樓（行程看板的遠排，顏色更淡：前面的樓才是資料）
    static func farInk(dark: Bool) -> TripSkylineInk {
        TripSkylineInk(far: dark ? Color(tb: 0x22305E) : Color(tb: 0xCFE0F2, 0.85),
                       farLight: dark ? Color(tb: 0xFFCF7A, 0.4) : nil,
                       near: [], glint: nil, windowLine: nil, lit: nil)
    }

    static func groundFill(dark: Bool) -> Color {
        dark ? Color(tb: 0x0E1530) : Color(tb: 0xD5E4F4)
    }

    static func purple(dark: Bool) -> Color {
        dark ? Color(tb: 0xA98BFF) : Color(tb: 0x8B5CF6)
    }

    static func paintTree(_ ctx: inout GraphicsContext, at p: CGPoint, size s: CGFloat, dark: Bool) {
        let trunk = dark ? Color(tb: 0x3B2E28) : Color(tb: 0x7A5A3E)
        let leaf = dark ? Color(tb: 0x2F7A55) : Color(tb: 0x58BE84)
        let leaf2 = dark ? Color(tb: 0x3C9467) : Color(tb: 0x7AD3A0)
        ctx.fill(Path(CGRect(x: p.x - 0.8, y: p.y - s * 0.55, width: 1.6, height: s * 0.55)), with: .color(trunk))
        let r1 = s * 0.42
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r1, y: p.y - s * 0.85 - r1, width: r1 * 2, height: r1 * 2)),
                 with: .color(leaf))
        let r2 = s * 0.22
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.18 - r2, y: p.y - s * 0.95 - r2, width: r2 * 2, height: r2 * 2)),
                 with: .color(leaf2))
    }

    /// 鐵軌（枕木＋兩條軌）
    static func paintTrack(_ ctx: inout GraphicsContext, width w: CGFloat, y ry: CGFloat, dark: Bool) {
        let rail = dark ? Color(tb: 0x5A6FA8) : Color(tb: 0x9DB4D3)
        var sx: CGFloat = 4
        while sx < w {
            ctx.fill(Path(CGRect(x: sx, y: ry - 3, width: 2, height: 6)), with: .color(rail.opacity(0.55)))
            sx += 7
        }
        for dy: CGFloat in [-2, 2] {
            var l = Path()
            l.move(to: CGPoint(x: 0, y: ry + dy))
            l.addLine(to: CGPoint(x: w, y: ry + dy))
            ctx.stroke(l, with: .color(rail), lineWidth: 1)
        }
    }

    /// 小電車（車頭朝右）
    static func paintTrain(_ ctx: inout GraphicsContext, center tx: CGFloat, rail ry: CGFloat, long: Bool) {
        let blue = Color(tb: 0x2F6FE0)
        let windows = Color(tb: 0xDCEBFF)
        if long {
            let body = CGRect(x: tx - 30, y: ry - 19, width: 40, height: 16)
            ctx.fill(Path(roundedRect: body, cornerRadius: 5), with: .color(blue))
            ctx.stroke(Path(roundedRect: body, cornerRadius: 5), with: .color(.white), lineWidth: 1.2)
            for k in 0..<4 {
                ctx.fill(Path(roundedRect: CGRect(x: tx - 26 + CGFloat(k) * 9, y: ry - 15, width: 6, height: 5),
                              cornerRadius: 1), with: .color(windows))
            }
            var nose = Path()
            nose.move(to: CGPoint(x: tx + 10, y: ry - 17))
            nose.addQuadCurve(to: CGPoint(x: tx + 19, y: ry - 5), control: CGPoint(x: tx + 18, y: ry - 17))
            nose.addLine(to: CGPoint(x: tx + 10, y: ry - 5))
            nose.closeSubpath()
            ctx.fill(nose, with: .color(blue))
        } else {
            let body = CGRect(x: tx - 10, y: ry - 8.5, width: 20, height: 11)
            ctx.fill(Path(roundedRect: body, cornerRadius: 3), with: .color(blue))
            ctx.stroke(Path(roundedRect: body, cornerRadius: 3), with: .color(.white), lineWidth: 1)
            for k in 0..<3 {
                ctx.fill(Path(roundedRect: CGRect(x: tx - 7.5 + CGFloat(k) * 5.5, y: ry - 6, width: 4, height: 3.5),
                              cornerRadius: 0.8), with: .color(windows))
            }
        }
    }

    // MARK: 城市（總覽）

    static func paintCity(_ ctx: inout GraphicsContext, rect r: CGRect, scene s: MoneyCityScene,
                          dark: Bool, seed: Int) {
        let w = r.width
        let railH: CGFloat = 34
        let ground = r.maxY - railH
        let days = max(1, s.daysInMonth)
        let x0 = r.minX + 14
        let x1 = r.maxX - 14
        let slot = (x1 - x0) / CGFloat(days)
        let bw = max(2, slot * 0.8)
        let buildTop = r.minY + 18
        let maxH = max(12, ground - buildTop)

        TripBoardSkyArt.paintFarRow(&ctx, width: w, ground: ground, band: 32, ink: farInk(dark: dark), seed: seed)

        let budget = s.dailyBudget ?? 0
        let maxV = max(s.daily.max() ?? 0, budget * 1.6, 1)
        func height(_ v: Double) -> CGFloat {
            6 + (maxH - 10) * CGFloat((max(0, v) / maxV).squareRoot())
        }
        let budgetY: CGFloat? = budget > 0 ? ground - height(budget) : nil
        let near: [Color] = dark ? [Color(tb: 0x2A3A70), Color(tb: 0x33447D)]
                                 : [Color(tb: 0x5F86BF), Color(tb: 0x6B90C6)]
        let warm = Gradient(colors: [Color(tb: 0xFFC56B), Color(tb: 0xF08A3A)])
        let todayFill = Gradient(colors: [Color(tb: 0x5B9BFF), Color(tb: 0x2459D6)])
        let lotStroke = dark ? Color(tb: 0x7A8FC8, 0.6) : Color.white.opacity(0.95)
        var flagTop: CGFloat? = nil
        var flagX: CGFloat = 0

        for d in 1...days {
            let cx = x0 + slot * (CGFloat(d) - 0.5)
            let bx = cx - bw / 2
            let isToday = d == s.today
            if d > s.today {
                // 還沒到：地上一塊虛線框的空地
                ctx.stroke(Path(CGRect(x: bx, y: ground - 4, width: bw, height: 4)), with: .color(lotStroke),
                           style: StrokeStyle(lineWidth: 0.8, dash: [1.5, 1.5]))
                continue
            }
            let v = d - 1 < s.daily.count ? s.daily[d - 1] : 0
            if v <= 0 {
                if d >= s.firstDay {
                    // 沒花錢的日子種一棵樹
                    let ts = min(14, slot * 1.4)
                    paintTree(&ctx, at: CGPoint(x: cx, y: ground), size: ts, dark: dark)
                    if isToday {
                        flagTop = ground - ts * 1.3
                        flagX = cx
                    }
                } else {
                    ctx.stroke(Path(CGRect(x: bx, y: ground - 4, width: bw, height: 4)), with: .color(lotStroke),
                               style: StrokeStyle(lineWidth: 0.8, dash: [1.5, 1.5]))
                }
                continue
            }
            let hgt = height(v)
            let top = ground - hgt
            let rect = CGRect(x: bx, y: top, width: bw, height: hgt)
            if isToday {
                ctx.fill(Path(rect), with: .linearGradient(todayFill, startPoint: CGPoint(x: 0, y: top),
                                                           endPoint: CGPoint(x: 0, y: ground)))
                flagTop = top
                flagX = cx
            } else {
                ctx.fill(Path(rect), with: .color(near[d % 2]))
            }
            // 超過日預算的那一截
            if let by = budgetY, top < by {
                ctx.fill(Path(CGRect(x: bx, y: top, width: bw, height: by - top)),
                         with: .linearGradient(warm, startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: by)))
            }
            // 窗：白天亮邊＋窗線，夜裡亮燈（今天那棟燈多）
            if dark {
                var rnd = InkRandom(seed &+ d &* 977)
                var wy = top + 3
                while wy < ground - 3 {
                    for wx in [bx + 1.4, bx + bw - 2.9] where bw > 5 {
                        if rnd.next() < (isToday ? 0.8 : 0.32) {
                            ctx.fill(Path(CGRect(x: wx, y: wy, width: 1.5, height: 1.8)),
                                     with: .color(Color(tb: 0xFFC56B, 0.55 + rnd.next() * 0.4)))
                        }
                    }
                    wy += 3.8
                }
            } else {
                ctx.fill(Path(CGRect(x: bx, y: top, width: bw * 0.25, height: hgt)), with: .color(Color.white.opacity(0.35)))
                var wy = top + 3
                while wy < ground - 3 {
                    var l = Path()
                    l.move(to: CGPoint(x: bx + 1.4, y: wy))
                    l.addLine(to: CGPoint(x: bx + bw - 1.4, y: wy))
                    ctx.stroke(l, with: .color(Color.white.opacity(0.4)),
                               style: StrokeStyle(lineWidth: 0.6, dash: [1.4, 1.6]))
                    wy += 4
                }
            }
        }

        // 日預算線＋標籤
        if let by = budgetY {
            let lc = dark ? Color(tb: 0xFFC56B) : Color(tb: 0xE07800)
            var l = Path()
            l.move(to: CGPoint(x: x0, y: by))
            l.addLine(to: CGPoint(x: x1, y: by))
            ctx.stroke(l, with: .color(lc.opacity(0.9)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            if let label = s.budgetLabel {
                let t = ctx.resolve(Text(label).font(.system(size: 8, weight: .bold)).foregroundStyle(lc))
                let m = t.measure(in: CGSize(width: 300, height: 40))
                let box = CGRect(x: x1 - m.width - 12, y: by - m.height - 6, width: m.width + 12, height: m.height + 4)
                ctx.fill(Path(roundedRect: box, cornerRadius: box.height / 2),
                         with: .color(dark ? Color(tb: 0x1C2646, 0.88) : Color.white.opacity(0.88)))
                ctx.draw(t, at: CGPoint(x: box.midX, y: box.midY), anchor: .center)
            }
        }

        // 今天：一根旗竿＋小旗
        if let ft = flagTop {
            var pole = Path()
            pole.move(to: CGPoint(x: flagX, y: ft - 2))
            pole.addLine(to: CGPoint(x: flagX, y: ft - 15))
            ctx.stroke(pole, with: .color(dark ? Color(tb: 0xCFE0FF) : Color(tb: 0x1D3A7A)), lineWidth: 1)
            let t = ctx.resolve(Text("今天").font(.system(size: 7, weight: .heavy)).foregroundStyle(Color.white))
            let m = t.measure(in: CGSize(width: 100, height: 20))
            var flag = CGRect(x: flagX, y: ft - 17, width: m.width + 8, height: m.height + 2)
            if flag.maxX > r.maxX - 4 { flag.origin.x = flagX - flag.width }
            ctx.fill(Path(roundedRect: flag, cornerRadius: 2), with: .color(Color(tb: 0x2F6FE0)))
            ctx.draw(t, at: CGPoint(x: flag.midX, y: flag.midY), anchor: .center)
        }

        // 地面與鐵道：固定支出的扣款日是車站，電車停在今天
        ctx.fill(Path(CGRect(x: 0, y: ground, width: w, height: r.maxY - ground)), with: .color(groundFill(dark: dark)))
        let ry = ground + 11
        paintTrack(&ctx, width: w, y: ry, dark: dark)
        let stationInk = purple(dark: dark)
        for st in s.stations where st.day >= 1 && st.day <= days {
            let cx = x0 + slot * (CGFloat(st.day) - 0.5)
            let dot = Path(ellipseIn: CGRect(x: cx - 4, y: ry - 4, width: 8, height: 8))
            ctx.fill(dot, with: .color(stationInk.opacity(st.past ? 0.45 : 1)))
            ctx.stroke(dot, with: .color(dark ? Color(tb: 0x121B38) : Color.white), lineWidth: 1.4)
        }
        let tx = x0 + slot * (CGFloat(min(max(s.today, 1), days)) - 0.5)
        paintTrain(&ctx, center: tx - 2, rail: ry, long: false)
        if let label = s.nextLabel, let next = s.stations.first(where: { $0.isNext }) {
            let cx = x0 + slot * (CGFloat(next.day) - 0.5)
            var tick = Path()
            tick.move(to: CGPoint(x: cx, y: ry + 5))
            tick.addLine(to: CGPoint(x: cx, y: ry + 10))
            ctx.stroke(tick, with: .color(stationInk), lineWidth: 1)
            let t = ctx.resolve(Text(label).font(.system(size: 8, weight: .heavy)).foregroundStyle(stationInk))
            let m = t.measure(in: CGSize(width: 300, height: 30))
            var lx = cx - 4
            if lx + m.width > w - 6 { lx = max(6, cx + 4 - m.width) }
            ctx.draw(t, at: CGPoint(x: lx, y: ry + 11), anchor: .topLeading)
        }
    }

    // MARK: 市集（變動支出）

    static func paintMarket(_ ctx: inout GraphicsContext, rect r: CGRect, scene s: MoneyMarketScene,
                            dark: Bool, seed: Int) {
        let w = r.width
        let streetH: CGFloat = 22
        let ground = r.maxY - streetH
        TripBoardSkyArt.paintFarRow(&ctx, width: w, ground: ground, band: 30, ink: farInk(dark: dark), seed: seed)

        // 街道
        ctx.fill(Path(CGRect(x: 0, y: ground, width: w, height: streetH)), with: .color(groundFill(dark: dark)))
        var lx: CGFloat = 0
        while lx < w {
            ctx.fill(Path(CGRect(x: lx, y: ground + 10, width: 7, height: 2)),
                     with: .color(Color.white.opacity(dark ? 0.25 : 0.8)))
            lx += 14
        }

        // 還沒有消費：三家還沒開的店（灰、沒有招牌）
        let placeholder = s.shops.isEmpty
        let shops: [MoneyMarketScene.Shop] = placeholder
            ? [0.4, 0.34, 0.26].map { MoneyMarketScene.Shop(theme: .misc, amount: 1, share: $0) }
            : s.shops
        let gap: CGFloat = 4
        let usable = w - 20 - gap * CGFloat(max(0, shops.count - 1))
        var widths = shops.map { max(14, usable * CGFloat($0.share)) }
        let sum = widths.reduce(0, +)
        if sum > usable, sum > 0 { widths = widths.map { $0 * usable / sum } }
        let maxA = max(shops.map(\.amount).max() ?? 1, 1)
        let hMax = max(34, ground - (r.minY + 28))
        let ink = dark ? Color(tb: 0xE6ECFF) : Color(tb: 0x0B1B45, 0.88)
        let lightStripe = dark ? Color(tb: 0xE8ECF8) : Color.white
        var x = r.minX + 10
        for (i, shop) in shops.enumerated() {
            let sw = widths[i]
            let h = min(hMax, 30 + (hMax - 30) * CGFloat((shop.amount / maxA).squareRoot()))
            let top = ground - h
            // 牆
            let wall = CGRect(x: x, y: top + 10, width: sw, height: h - 10)
            ctx.fill(Path(wall), with: .color(dark ? Color(tb: 0x2A3358) : Color(tb: 0xF6EFE6)))
            ctx.stroke(Path(wall), with: .color(dark ? Color(tb: 0x3A4570) : Color(tb: 0xD9CBB8)), lineWidth: 0.8)
            // 雨棚：分類色與白的條紋，下緣一道道波浪
            let n = max(2, Int(sw / 9))
            let stw = sw / CGFloat(n)
            for j in 0..<n {
                let col = j % 2 == 0 ? shop.theme.bottomColor : lightStripe
                let sx = x + CGFloat(j) * stw
                var stripe = Path(CGRect(x: sx, y: top, width: stw, height: 14))
                stripe.move(to: CGPoint(x: sx, y: top + 14))
                stripe.addQuadCurve(to: CGPoint(x: sx + stw, y: top + 14), control: CGPoint(x: sx + stw / 2, y: top + 20))
                stripe.closeSubpath()
                ctx.fill(stripe, with: .color(placeholder ? col.opacity(0.5) : col))
            }
            ctx.fill(Path(roundedRect: CGRect(x: x, y: top - 3, width: sw, height: 4), cornerRadius: 2),
                     with: .color(shop.theme.bottomColor.opacity(placeholder ? 0.5 : 1)))
            if !placeholder {
                // 招牌：分類的手寫英文字
                if sw > 48 {
                    let t = ctx.resolve(Text(shop.theme.word).font(TripScriptFont.city(min(17, sw / 4)))
                        .foregroundStyle(ink))
                    ctx.draw(t, at: CGPoint(x: x + sw / 2, y: top - 4), anchor: .bottom)
                }
                // 櫥窗（寫占幾成）與門
                if sw > 28 {
                    let win = CGRect(x: x + sw * 0.12, y: top + 20, width: sw * 0.42, height: max(6, h - 26))
                    // 夜裡櫥窗亮燈（暖色），白天是分類色的淡玻璃
                    ctx.fill(Path(roundedRect: win, cornerRadius: 2),
                             with: .color(dark ? Color(tb: 0xFFC56B, 0.5) : shop.theme.topColor.opacity(0.35)))
                    let doorH = min(24, max(8, h - 14))
                    ctx.fill(Path(roundedRect: CGRect(x: x + sw * 0.62, y: ground - doorH, width: sw * 0.24, height: doorH),
                                  cornerRadius: 2), with: .color(shop.theme.bottomColor.opacity(0.75)))
                    let pct = ctx.resolve(Text("\(Int((shop.share * 100).rounded()))%")
                        .font(.system(size: 9, weight: .heavy, design: .rounded)).foregroundStyle(ink))
                    ctx.draw(pct, at: CGPoint(x: win.midX, y: win.minY + 9), anchor: .center)
                }
            }
            x += sw + gap
        }
    }

    // MARK: 山（收入）

    static func paintMountains(_ ctx: inout GraphicsContext, rect r: CGRect, scene s: MoneyMountainScene,
                               dark: Bool, seed: Int) {
        let w = r.width
        let labelH: CGFloat = 16
        let ground = r.maxY - labelH
        let top = r.minY + 30
        let maxH = max(20, ground - top)

        // 白天：太陽從山後升起（夜裡的月亮在頭部右上角，山後面的月亮太小、會整個被山擋住）
        let sc = CGPoint(x: w * 0.62, y: ground - maxH * 0.6)
        if !dark {
            ctx.fill(Path(ellipseIn: CGRect(x: sc.x - 40, y: sc.y - 40, width: 80, height: 80)),
                     with: .radialGradient(Gradient(colors: [Color(tb: 0xFFE29A), Color(tb: 0xFFC94D, 0.5),
                                                             Color(tb: 0xFFC94D, 0)]),
                                           center: sc, startRadius: 0, endRadius: 40))
            ctx.fill(Path(ellipseIn: CGRect(x: sc.x - 13, y: sc.y - 13, width: 26, height: 26)),
                     with: .color(Color(tb: 0xFFB020)))
        }
        // 遠山
        var ridge = Path()
        ridge.move(to: CGPoint(x: 0, y: ground))
        ridge.addLine(to: CGPoint(x: 0, y: ground - 26))
        ridge.addQuadCurve(to: CGPoint(x: w * 0.4, y: ground - 30), control: CGPoint(x: w * 0.2, y: ground - 46))
        ridge.addQuadCurve(to: CGPoint(x: w * 0.8, y: ground - 38), control: CGPoint(x: w * 0.6, y: ground - 14))
        ridge.addQuadCurve(to: CGPoint(x: w, y: ground - 24), control: CGPoint(x: w * 0.92, y: ground - 52))
        ridge.addLine(to: CGPoint(x: w, y: ground))
        ridge.closeSubpath()
        ctx.fill(ridge, with: .color(dark ? Color(tb: 0x1F4A3E) : Color(tb: 0xA9E9C6, 0.8)))

        let n = max(1, s.peaks.count)
        let seg = (w - 20) / CGFloat(n)
        let maxV = max(s.peaks.map(\.value).max() ?? 0, s.expected ?? 0, 1)
        func height(_ v: Double) -> CGFloat {
            14 + (maxH - 14) * CGFloat((max(0, v) / maxV).squareRoot())
        }
        let grad = dark ? Gradient(colors: [Color(tb: 0x2F8A5E), Color(tb: 0x14503A)])
                        : Gradient(colors: [Color(tb: 0x5FD69A), Color(tb: 0x167A55)])
        let labelInk = dark ? Color(tb: 0xA3B2D9) : Color(tb: 0x4A5B8C)
        let good = dark ? Color(tb: 0x5BD99A) : Color(tb: 0x177A44)
        for (i, p) in s.peaks.enumerated() {
            let cx = r.minX + 10 + seg * (CGFloat(i) + 0.5)
            let base = seg * 0.95
            let hh = height(p.value)
            let isCurrent = i == s.peaks.count - 1
            var m = Path()
            m.move(to: CGPoint(x: cx - base, y: ground))
            m.addQuadCurve(to: CGPoint(x: cx, y: ground - hh), control: CGPoint(x: cx - base * 0.35, y: ground - hh * 0.55))
            m.addQuadCurve(to: CGPoint(x: cx + base, y: ground), control: CGPoint(x: cx + base * 0.35, y: ground - hh * 0.55))
            m.closeSubpath()
            var g = ctx
            g.opacity = isCurrent ? 0.78 : 0.94
            g.fill(m, with: .linearGradient(grad, startPoint: CGPoint(x: 0, y: ground - hh),
                                            endPoint: CGPoint(x: 0, y: ground)))
            // 高的山頂一點雪
            if hh > maxH * 0.62 {
                var snow = Path()
                snow.move(to: CGPoint(x: cx - 9, y: ground - hh + 14))
                snow.addLine(to: CGPoint(x: cx, y: ground - hh))
                snow.addLine(to: CGPoint(x: cx + 9, y: ground - hh + 14))
                snow.addLine(to: CGPoint(x: cx + 4, y: ground - hh + 10))
                snow.addLine(to: CGPoint(x: cx, y: ground - hh + 15))
                snow.addLine(to: CGPoint(x: cx - 4, y: ground - hh + 10))
                snow.closeSubpath()
                ctx.fill(snow, with: .color(Color.white.opacity(dark ? 0.6 : 0.9)))
            }
            // 這個月：虛線畫出預期的高度，山頂插旗
            if isCurrent, let exp = s.expected, exp > p.value {
                let he = height(exp)
                var outline = Path()
                outline.move(to: CGPoint(x: cx - base * 0.6, y: ground))
                outline.addQuadCurve(to: CGPoint(x: cx, y: ground - he), control: CGPoint(x: cx - base * 0.2, y: ground - he * 0.55))
                outline.addQuadCurve(to: CGPoint(x: cx + base * 0.6, y: ground), control: CGPoint(x: cx + base * 0.2, y: ground - he * 0.55))
                ctx.stroke(outline, with: .color(good), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                var pole = Path()
                pole.move(to: CGPoint(x: cx, y: ground - he))
                pole.addLine(to: CGPoint(x: cx, y: ground - he - 18))
                ctx.stroke(pole, with: .color(dark ? Color(tb: 0xCFE0FF) : Color(tb: 0x0B1B45)), lineWidth: 1)
                var flag = Path()
                flag.move(to: CGPoint(x: cx, y: ground - he - 18))
                flag.addLine(to: CGPoint(x: cx + 13, y: ground - he - 14))
                flag.addLine(to: CGPoint(x: cx, y: ground - he - 10))
                flag.closeSubpath()
                ctx.fill(flag, with: .color(Color(tb: 0xE0457A)))
                if let label = s.expectedLabel {
                    let lt = ctx.resolve(Text(label).font(.system(size: 8, weight: .heavy)).foregroundStyle(good))
                    ctx.draw(lt, at: CGPoint(x: cx - 4, y: ground - he - 12), anchor: .trailing)
                }
            }
        }
        ctx.fill(Path(CGRect(x: 0, y: ground, width: w, height: labelH)),
                 with: .color(dark ? Color(tb: 0x0F2A22) : Color(tb: 0xCFE8D8, 0.6)))
        // 月份字寫在地面那一條上
        for (i, p) in s.peaks.enumerated() {
            let cx = r.minX + 10 + seg * (CGFloat(i) + 0.5)
            let t = ctx.resolve(Text(p.label).font(.system(size: 8.5, weight: .bold)).foregroundStyle(labelInk))
            ctx.draw(t, at: CGPoint(x: cx, y: ground + 2), anchor: .top)
        }
    }

    // MARK: 列車（固定支出）

    static func paintRailway(_ ctx: inout GraphicsContext, rect r: CGRect, scene s: MoneyRailScene,
                             dark: Bool, seed: Int) {
        let w = r.width
        let stripH: CGFloat = 30
        let ground = r.maxY - stripH

        // 遠山與樹
        var hill = Path()
        hill.move(to: CGPoint(x: 0, y: ground))
        hill.addLine(to: CGPoint(x: 0, y: ground - 24))
        hill.addQuadCurve(to: CGPoint(x: w * 0.5, y: ground - 28), control: CGPoint(x: w * 0.25, y: ground - 46))
        hill.addQuadCurve(to: CGPoint(x: w, y: ground - 22), control: CGPoint(x: w * 0.75, y: ground - 10))
        hill.addLine(to: CGPoint(x: w, y: ground))
        hill.closeSubpath()
        ctx.fill(hill, with: .color(dark ? Color(tb: 0x1A2550) : Color(tb: 0xCFE0F2)))
        var rnd = InkRandom(seed &* 5 &+ 11)
        for _ in 0..<14 {
            let tx = CGFloat(rnd.next()) * w
            let rr = CGFloat(4 + rnd.next() * 3)
            ctx.fill(Path(ellipseIn: CGRect(x: tx - rr, y: ground - 6 - rr, width: rr * 2, height: rr * 2)),
                     with: .color(dark ? Color(tb: 0x2F6A55) : Color(tb: 0x9FD3B4, 0.8)))
        }

        ctx.fill(Path(CGRect(x: 0, y: ground, width: w, height: stripH)), with: .color(groundFill(dark: dark)))
        let ry = ground + 10
        paintTrack(&ctx, width: w, y: ry, dark: dark)

        let days = max(1, s.daysInMonth)
        let x0 = r.minX + 16
        let x1 = r.maxX - 16
        let slot = (x1 - x0) / CGFloat(days)
        let stationInk = purple(dark: dark)
        for st in s.stations where st.day >= 1 && st.day <= days {
            let cx = x0 + slot * (CGFloat(st.day) - 0.5)
            let alpha = st.past ? 0.4 : 0.95
            var pole = Path()
            pole.move(to: CGPoint(x: cx, y: ry - 6))
            pole.addLine(to: CGPoint(x: cx, y: ry - 22))
            ctx.stroke(pole, with: .color(stationInk.opacity(alpha)), lineWidth: 1.2)
            let rad: CGFloat = st.isNext ? 7 : 5.5
            let head = Path(ellipseIn: CGRect(x: cx - rad, y: ry - 22 - rad * 2, width: rad * 2, height: rad * 2))
            ctx.fill(head, with: .color(stationInk.opacity(st.past ? 0.4 : 1)))
            ctx.stroke(head, with: .color(dark ? Color(tb: 0x121B38) : Color.white), lineWidth: 1.5)
            if st.past {
                var check = Path()
                let cy = ry - 22 - rad
                check.move(to: CGPoint(x: cx - 2.5, y: cy))
                check.addLine(to: CGPoint(x: cx - 0.7, y: cy + 1.8))
                check.addLine(to: CGPoint(x: cx + 2.7, y: cy - 1.8))
                ctx.stroke(check, with: .color(.white), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            }
        }

        // 電車停在今天
        let tx = x0 + slot * (CGFloat(min(max(s.today, 1), days)) - 0.5)
        paintTrain(&ctx, center: tx, rail: ry, long: true)

        // 下一站的小牌子
        if let title = s.nextTitle, let next = s.stations.first(where: { $0.isNext }) {
            let cx = x0 + slot * (CGFloat(next.day) - 0.5)
            let ink = dark ? Color(tb: 0xF3F6FF) : Color(tb: 0x0B1B45)
            let t1 = ctx.resolve(Text(title).font(.system(size: 8.5, weight: .heavy)).foregroundStyle(stationInk))
            let t2 = ctx.resolve(Text(s.nextDetail ?? "").font(.system(size: 9.5, weight: .heavy)).foregroundStyle(ink))
            let m1 = t1.measure(in: CGSize(width: 300, height: 40))
            let m2 = t2.measure(in: CGSize(width: 300, height: 40))
            let bw = max(m1.width, m2.width) + 14
            let bh = m1.height + m2.height + 8
            let headTop = ry - 22 - 14
            var bx = cx - 18
            bx = min(max(8, bx), w - bw - 8)
            let by = max(r.minY + 2, headTop - 6 - bh)
            let bubble = CGRect(x: bx, y: by, width: bw, height: bh)
            ctx.fill(Path(roundedRect: bubble, cornerRadius: 8),
                     with: .color(dark ? Color(tb: 0x1C2646) : Color.white))
            ctx.stroke(Path(roundedRect: bubble, cornerRadius: 8), with: .color(stationInk.opacity(0.35)), lineWidth: 0.8)
            var pointer = Path()
            let px = min(max(bubble.minX + 10, cx), bubble.maxX - 10)
            pointer.move(to: CGPoint(x: px - 4, y: bubble.maxY))
            pointer.addLine(to: CGPoint(x: px, y: bubble.maxY + 5))
            pointer.addLine(to: CGPoint(x: px + 4, y: bubble.maxY))
            pointer.closeSubpath()
            ctx.fill(pointer, with: .color(dark ? Color(tb: 0x1C2646) : Color.white))
            ctx.draw(t1, at: CGPoint(x: bx + 7, y: by + 4), anchor: .topLeading)
            ctx.draw(t2, at: CGPoint(x: bx + 7, y: by + 5 + m1.height), anchor: .topLeading)
        }

        // 鐵道下面：月初、今天、月底
        let labelInk = dark ? Color(tb: 0xA3B2D9) : Color(tb: 0x4A5B8C)
        let first = ctx.resolve(Text("\(s.month)/1").font(.system(size: 8, weight: .bold)).foregroundStyle(labelInk))
        let last = ctx.resolve(Text("\(s.month)/\(days)").font(.system(size: 8, weight: .bold)).foregroundStyle(labelInk))
        let todayT = ctx.resolve(Text("今天").font(.system(size: 8, weight: .heavy)).foregroundStyle(Color(tb: 0x2F6FE0)))
        let ly = ry + 8
        ctx.draw(todayT, at: CGPoint(x: tx - 10, y: ly), anchor: .top)
        if tx - 10 - 24 > x0 + 18 {
            ctx.draw(first, at: CGPoint(x: x0, y: ly), anchor: .topLeading)
        }
        if tx - 10 + 24 < x1 - 22 {
            ctx.draw(last, at: CGPoint(x: x1, y: ly), anchor: .topTrailing)
        }
    }

    // MARK: 星空（圖表）

    static func paintConstellation(_ ctx: inout GraphicsContext, rect r: CGRect, scene s: MoneyStarScene, seed: Int) {
        let w = r.width
        let top = r.minY + 20
        let bot = r.maxY - 22
        // 地平線的山影
        var hill = Path()
        hill.move(to: CGPoint(x: 0, y: r.maxY))
        hill.addLine(to: CGPoint(x: 0, y: r.maxY - 10))
        hill.addQuadCurve(to: CGPoint(x: w * 0.6, y: r.maxY - 12), control: CGPoint(x: w * 0.3, y: r.maxY - 22))
        hill.addQuadCurve(to: CGPoint(x: w, y: r.maxY - 14), control: CGPoint(x: w * 0.8, y: r.maxY - 2))
        hill.addLine(to: CGPoint(x: w, y: r.maxY))
        hill.closeSubpath()
        ctx.fill(hill, with: .color(Color(tb: 0x0B1230)))

        let values = s.values
        guard values.count >= 2 else { return }
        let maxV = max(values.max() ?? 0, 1)
        let n = values.count
        var pts: [CGPoint] = []
        for (i, v) in values.enumerated() {
            let x = r.minX + 16 + (w - 32) * CGFloat(i) / CGFloat(n - 1)
            let y = bot - (bot - top) * CGFloat((max(0, v) / maxV).squareRoot())
            pts.append(CGPoint(x: x, y: y))
        }
        var line = Path()
        line.addLines(pts)
        ctx.stroke(line, with: .color(Color(tb: 0x9ED8FF, 0.45)), lineWidth: 0.9)
        for (i, p) in pts.enumerated() {
            let rr = 1.2 + 3.2 * CGFloat((max(0, values[i]) / maxV).squareRoot())
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - rr * 2.4, y: p.y - rr * 2.4, width: rr * 4.8, height: rr * 4.8)),
                     with: .color(Color(tb: 0x9ED8FF, 0.12)))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2)),
                     with: .color(.white))
        }
        // 最多的那一期：最亮的星
        if let iMax = values.indices.max(by: { values[$0] < values[$1] }), values[iMax] > 0 {
            let p = pts[iMax]
            ctx.fill(MoneyArtPatternLayer.star(center: p, radius: 10), with: .color(Color(tb: 0xFFE29A)))
            if let label = s.maxLabel {
                let t = ctx.resolve(Text(label).font(.system(size: 8.5, weight: .heavy))
                    .foregroundStyle(Color(tb: 0xFFE29A)))
                let m = t.measure(in: CGSize(width: 300, height: 40))
                if p.x - 12 - m.width > 8 {
                    ctx.draw(t, at: CGPoint(x: p.x - 12, y: p.y - 6), anchor: .bottomTrailing)
                } else {
                    ctx.draw(t, at: CGPoint(x: p.x + 12, y: p.y - 6), anchor: .bottomLeading)
                }
            }
        }
    }
}
