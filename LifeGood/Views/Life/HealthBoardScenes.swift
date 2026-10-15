import SwiftUI

// MARK: - 健康頁看板的兩幅風景（v25.553，健康 v3；health/judge.md §3.12）
//
// A.「這週的河堤」.riverside(HealthWeekScene)：健康頁看板（band 118）。
//    一條米白色河堤步道由左（6%）到右（94%）等分七段＝週一到週日；每段下方一塊白底小牌「一」…「日」（finPill 的畫法），
//    今天那塊深藍底白字。有運動的那天在步道上插小旗：旗竿高＝max(10, 34 × height) pt（height 是那天那種運動的公里
//    ÷ 這週單日單種最多的公里；重訓的旗固定 14pt）；旗面是運動色（WorkoutPalette.sport）；同一天兩種運動兩面並排，
//    第三種起只畫一顆小點（extraDots）。小跑者站在今天那段（圖示跟著 runnerSport：figure.run／walk／outdoor.cycle／hiking）；
//    今天之後的步道畫成點狀虛線。白天：遠方一排淡淡的樓、幾棵行道樹、步道下方一條河（淡藍水面＋兩三道白色波紋）。
//    夜裡：星空（天空那層已經畫了）、河面一道月光、每段交界一盞路燈亮暖黃光暈（finLamp）。
// B.「這一趟的路」.runTrail(WorkoutTrailScene)：成果頁看板（band 132），從側面看。
//    左邊（6%）一面白色起點旗、右邊（94%）一座小拱門＝終點，中間一條路，橫軸是距離。每整公里一根小柱子掛白底小牌
//    「1」…「5」（騎車每 5 公里），star 那一根頂上一顆小星星。路面照 bands 上色（WorkoutPalette.pace）。
//    hilly：地面線就是 profile（壓扁到 band 裡，照 FinRidgeScene 的山稜畫法）；不 hilly：平的河濱、路下一條河。
//    小跑者站在終點拱門旁。重訓（kind .strength）：一排槓片，一個動作一片，大小＝plates。
//    沒有路線（kind .noRoute）：平的河堤、虛線步道、一塊小牌 note（「這趟沒有路線」）。
//    為什麼用側面：看得出哪一段快、哪裡在爬坡，又不會露出路線的形狀（住家附近；看板之後會上分享圖）。
//
// 規矩跟其他看板風景一樣（U3 §5、坑 #4／#5／#27）：數字一律在頭部的 Text 裡，風景上的字只是裝飾、旗子不寫公里；
// 只畫在 rect（band）裡；開頭 guard r.width > 120, r.height > 60；小牌先排好位置、互相讓開、最後才畫
// （FinDriveScene／FinHouseScene 的切法）；淺深各一組顏色（DriveInk 的寫法）。資料端已經把位置換成 0…1，這裡不碰日期。
//
// 分工：資料（這兩個 struct）主控寫好、HealthPageData.build／WorkoutFacts.trailScene 產生；畫法 G1 實作。

/// [v25.553] 健康頁看板：這週的河堤（週一到週日七段）
struct HealthWeekScene: Equatable {
    struct Flag: Equatable {
        var sport: WorkoutSport
        /// 0…1：那天這種運動的公里 ÷ 這週「單日單種」最多的公里（旗竿 max(10, 34 × height) pt）；
        /// 重訓（sport .strength）固定 0，畫 14pt
        var height: Double
    }
    struct Day: Equatable {
        /// 「一」「二」…「日」
        var label: String
        /// 最多兩面：有氧照公里多到少，重訓排最後
        var flags: [Flag]
        /// 第三種起，一種一顆小點
        var extraDots: Int
        /// 今天之後（那一段步道畫點狀虛線）
        var isFuture: Bool
    }
    /// 7 天，週一到週日
    var days: [Day] = []
    /// 今天是第幾段：0＝週一 … 6＝週日
    var todayIndex: Int = 0
    /// 小跑者的樣子：最近一趟有氧的運動；沒有就是看板主角
    var runnerSport: WorkoutSport = .run
}

/// [v25.553] 成果頁看板：這一趟的路（從側面看）。位置都是 0…1（距離的比例）
struct WorkoutTrailScene: Equatable {
    enum Kind: Equatable {
        /// 有路線：路、柱子、快慢上色、高度
        case route
        /// 重訓：一排槓片
        case strength
        /// 沒有路線：平的河堤＋小牌 note
        case noRoute
    }
    struct Band: Equatable {
        var from: Double
        var to: Double
        var level: WorkoutPaceLevel
    }
    var kind: Kind = .noRoute
    var sport: WorkoutSport = .run
    /// 每整公里（騎車每 5 公里）的位置 0…1
    var marks: [Double] = []
    /// 柱子上的小牌「1」「2」…（騎車「5」「10」…）；跟 marks 一樣長。柱子太密（間距不到 14pt）時隔幾根才掛一塊
    var markLabels: [String] = []
    /// 哪一根柱子頂上有星星（marks 的索引）；不到兩根柱子是 nil
    var star: Int? = nil
    /// 路面快慢上色；空的＝整條路一個顏色（運動色淡一點）
    var bands: [Band] = []
    /// 地面高度 0…1（最多 120 點，照距離等分）；空的＝平的
    var profile: [Double] = []
    /// 畫山稜（true）還是平的河濱（false）
    var hilly: Bool = false
    /// 重訓：每個動作一片槓片的大小 0.35…1（最多 8 片）
    var plates: [Double] = []
    /// 沒有路線時那塊小牌的字
    var note: String? = nil
}

// MARK: - 畫的時候用的小東西（只在這個檔裡）
//
// [v25.553] G1：版面照樣稿①-1／①-3／③-A1～A4（河堤）與②-5（側面的路）；畫法照 FinDriveScene 的切法——
// 顏色收一組（HealthRiverInk）、尺寸一次算好（HealthRiverLayout／HealthTrailLayout）、小牌先排好位置最後才畫（HealthTrailPlan）。

/// 兩幅風景共用的顏色，淺／深各一組（照樣稿 health/mock/health.js 的 paintRiverside／paintTrail；DriveInk 的寫法）
private struct HealthRiverInk {
    let dark: Bool
    let grassTop: Color      // 河堤草地（上→下）
    let grassBottom: Color
    let waterTop: Color      // 河（上→下）
    let waterBottom: Color
    let ripple: Color        // 水面波紋
    let shore: Color         // 岸邊一道亮線
    let path: Color          // 步道（今天以前）
    let pathEdge: Color
    let pathDot: Color       // 步道（今天之後：點狀虛線）
    let tick: Color          // 七段交界的小刻度
    let pole: Color          // 旗竿、每公里的柱子
    let flagEdge: Color      // 旗面細邊（健走綠旗在草地上才分得出來）
    let dot: Color           // 第三種運動起的小點
    let figure: Color        // 小跑者（= pal.ink）
    let pillFill: Color      // 「一」…「日」白底小牌
    let pillInk: Color
    let todayFill: Color     // 今天那塊深藍底白字
    let markFill: Color      // 柱子上的小牌（「1」「2」…）
    let markInk: Color
    let moon: Color          // 河面月光
    let hillFar: Color       // 側面的路（山稜）：遠山
    let ridgeTop: Color      // 山稜（上→下）
    let ridgeBottom: Color
    let ridgeLine: Color
    let startPole: Color     // 起點旗竿、拱門下的方格
    let flagLine: Color      // 起點白旗的細灰邊
    let bar: Color           // 槓鈴的槓
    let mat: Color           // 重訓的地墊
    let shadow: Color

    static let star = Color(tb: 0xFFC93C)

    init(dark: Bool) {
        self.dark = dark
        grassTop = dark ? Color(tb: 0x1D3B39) : Color(tb: 0xC9E9C2)
        grassBottom = dark ? Color(tb: 0x16302F) : Color(tb: 0xB5DFB0)
        waterTop = dark ? Color(tb: 0x15244A) : Color(tb: 0xBFE3F7)
        waterBottom = dark ? Color(tb: 0x0F1C3D) : Color(tb: 0x9CCFEF)
        ripple = dark ? Color(tb: 0x9ED8FF, 0.25) : Color.white.opacity(0.75)
        shore = dark ? Color.white.opacity(0.10) : Color.white.opacity(0.7)
        // 深色的步道用樣稿的 6E7894（2A3150 壓在深綠草地上幾乎看不見）
        path = dark ? Color(tb: 0x6E7894) : Color(tb: 0xF3EAD7)
        pathEdge = dark ? Color(tb: 0x8F99B8, 0.6) : Color(tb: 0xDCCDAE)
        pathDot = dark ? Color(tb: 0x8F99B8, 0.8) : Color(tb: 0xD9C9A6)
        tick = dark ? Color(tb: 0x4A5578) : Color(tb: 0xC9B78F)
        pole = dark ? Color(tb: 0xA3B2D9) : Color(tb: 0x5A6478)
        flagEdge = dark ? Color.white.opacity(0.35) : Color.white.opacity(0.85)
        dot = dark ? Color(tb: 0xA3B2D9) : Color(tb: 0x5A6478)
        figure = dark ? Color(tb: 0xF3F6FF) : Color(tb: 0x0B1B45)
        pillFill = dark ? Color(tb: 0x1C2646, 0.92) : Color.white.opacity(0.92)
        pillInk = dark ? Color(tb: 0xC9D4F2) : Color(tb: 0x4A5B8C)
        todayFill = dark ? Color(tb: 0x3B4F8F) : Color(tb: 0x1D2B55)
        markFill = dark ? Color(tb: 0x1C2646) : Color.white
        markInk = dark ? Color(tb: 0xE6ECFF) : Color(tb: 0x0B1B45)
        moon = Color(tb: 0xF4EBC8)
        hillFar = dark ? Color(tb: 0x1A2550) : Color(tb: 0xCFE0F2)
        ridgeTop = dark ? Color(tb: 0x24524A) : Color(tb: 0xA6D9A0)
        ridgeBottom = dark ? Color(tb: 0x15302D) : Color(tb: 0xCDEBC6)
        ridgeLine = dark ? Color.white.opacity(0.35) : Color.white.opacity(0.9)
        startPole = dark ? Color(tb: 0xCFE0FF) : Color(tb: 0x1D2B55)
        flagLine = dark ? Color(tb: 0xA3B2D9) : Color(tb: 0x8A93A6)
        bar = dark ? Color(tb: 0xA3B2D9) : Color(tb: 0x8A93A6)
        mat = dark ? Color(tb: 0x1E2848) : Color(tb: 0xDCE3EF)
        shadow = dark ? Color.black.opacity(0.35) : Color(tb: 0x2A3A66, 0.16)
    }
}

/// 河堤（band 118）的尺寸：都從 band 的下緣往上量（band 不是 118 也排得開）
private struct HealthRiverLayout {
    let rect: CGRect
    let x0: CGFloat          // 步道左端（6%）
    let x1: CGFloat          // 步道右端（94%）
    let seg: CGFloat         // 一天一段
    let waterTop: CGFloat    // 河：waterTop … rect.maxY（24pt）
    let pillTop: CGFloat     // 「一」…「日」小牌（13pt 高）
    let pathY: CGFloat       // 步道中線
    let pathH: CGFloat
    let grassTop: CGFloat    // 草地上緣（遠樓、行道樹站在這裡）
    let today: Int

    init(rect r: CGRect, today t: Int) {
        let left = r.minX + r.width * 0.06
        let right = r.minX + r.width * 0.94
        let water = r.maxY - 24
        let pill = water - 19
        let path = pill - 7
        rect = r
        x0 = left
        x1 = right
        seg = (right - left) / 7
        waterTop = water
        pillTop = pill
        pathH = 6
        pathY = path
        grassTop = path - 10
        today = min(6, max(0, t))
    }

    var pathTop: CGFloat { pathY - pathH / 2 }
    var pathBottom: CGFloat { pathY + pathH / 2 }
    /// 第 i 段（0＝週一）的左端
    func left(_ i: Int) -> CGFloat { x0 + seg * CGFloat(i) }
    /// 第 i 段裡 f（0…1）的位置
    func at(_ i: Int, _ f: CGFloat) -> CGFloat { left(i) + seg * f }
    /// 實線畫到今天那段的右端
    var solidEnd: CGFloat { left(today + 1) }
}

/// 插在步道上的一面旗（先排好，樹要讓開它）
private struct HealthFlagSpot {
    let x: CGFloat           // 旗竿
    let height: CGFloat      // 旗竿高（10～34；重訓 14）
    let cloth: CGFloat       // 旗面寬（同一天兩面時窄一點，不碰到第二面的竿）
    let color: Color
}

/// 側面的路（band 132）的尺寸
private struct HealthTrailLayout {
    let rect: CGRect
    let x0: CGFloat          // 起點（6%）
    let x1: CGFloat          // 終點（94%）
    let hilly: Bool
    let profile: [Double]
    let base: CGFloat        // 平的：路的基線（maxY − 34）
    let top: CGFloat         // 山稜：profile 1 在這裡（minY + 40）
    let bottom: CGFloat      // 山稜：profile 0 在這裡（maxY − 18）
    let waterTop: CGFloat    // 平的：河 waterTop … maxY

    init(rect r: CGRect, scene s: WorkoutTrailScene) {
        rect = r
        x0 = r.minX + r.width * 0.06
        x1 = r.minX + r.width * 0.94
        let prof = s.profile.map { $0.isFinite ? min(1, max(0, $0)) : 0 }
        profile = prof
        hilly = s.kind == .route && s.hilly && prof.count >= 2
        base = r.maxY - 34
        top = r.minY + 40
        bottom = r.maxY - 18
        waterTop = r.maxY - 22
    }

    func x(_ f: Double) -> CGFloat {
        x0 + (x1 - x0) * CGFloat(min(1, max(0, f.isFinite ? f : 0)))
    }

    /// profile 在 f（0…1）的值（照距離等分的點之間直線內插）；沒有 profile 是 0.5
    func level(_ f: Double) -> Double {
        let n = profile.count
        guard n >= 2 else { return 0.5 }
        let pos = min(1, max(0, f.isFinite ? f : 0)) * Double(n - 1)
        let i = min(n - 2, max(0, Int(pos)))
        let t = pos - Double(i)
        return profile[i] + (profile[i + 1] - profile[i]) * t
    }

    /// 地面在 f 的高度：山稜照 profile 壓進 top…bottom；平的河濱只留 ±2pt 的起伏（看得出有坡，但是平路）
    func groundY(_ f: Double) -> CGFloat {
        let p = CGFloat(min(1, max(0, level(f))))
        if hilly { return bottom - (bottom - top) * p }
        return base + 2 - 4 * p
    }

    func groundY(atX x: CGFloat) -> CGFloat {
        guard x1 > x0 else { return groundY(0) }
        return groundY(Double((x - x0) / (x1 - x0)))
    }
}

/// 側面的路：先排好的位置（起點旗、拱門、柱子、小牌、星星），樹與小牌照它讓開
private struct HealthTrailPlan {
    struct Post {
        let x: CGFloat
        let ground: CGFloat
        let tall: Bool       // 有掛牌的 16pt；沒掛牌的 10pt
    }
    struct Sign {
        let text: String
        let box: CGRect
    }
    var flagPole: CGPoint = .zero
    var flagBox: CGRect = .zero
    var arch: CGRect = .zero         // 兩根柱子＋半圓頂（寬 17）
    var archGround: CGFloat = 0
    var posts: [Post] = []
    var signs: [Sign] = []
    var star: CGPoint? = nil
    /// 樹不要種在這些 x 範圍（起點旗、拱門、每根柱子）
    var reserved: [ClosedRange<CGFloat>] = []
}

// MARK: - 畫法

extension MoneyBoardSky {

    /// 這週的河堤（健康頁看板，band 118）
    static func paintRiverside(_ ctx: inout GraphicsContext, rect r: CGRect, scene s: HealthWeekScene,
                               dark: Bool, seed: Int) {
        guard r.width > 120, r.height > 60, s.days.count == 7 else { return }
        let g = HealthRiverLayout(rect: r, today: s.todayIndex)
        let ink = HealthRiverInk(dark: dark)
        // 先排好旗子、跑者的位置：樹、路燈照它讓開（坑 #27）
        let flags = riverFlagSpots(s, g: g, dark: dark)
        let runner = riverRunnerImage(ctx, s, ink: ink)
        let runnerBox = riverRunnerBox(runner.size, s, g: g)
        var avoid: [ClosedRange<CGFloat>] = flags.map { ($0.x - 2)...($0.x + $0.cloth + 2) }
        avoid.append((runnerBox.minX - 2)...(runnerBox.maxX + 2))
        for (i, d) in s.days.enumerated() where d.extraDots > 0 {
            avoid.append((g.at(i, riverDotSpot) - 3)...(g.at(i, riverDotSpot) + 3))
        }
        if dark {
            for i in 1..<7 { avoid.append((g.left(i) - 6)...(g.left(i) + 6)) }
        }

        riverBackdrop(&ctx, g: g, ink: ink, seed: seed)
        riverTrees(&ctx, g: g, dark: dark, seed: seed, avoid: avoid)
        healthWater(&ctx, rect: CGRect(x: r.minX, y: g.waterTop, width: r.width, height: r.maxY - g.waterTop),
                    ink: ink, seed: seed)
        riverPath(&ctx, g: g, ink: ink)
        if dark {
            // 夜裡每段交界一盞路燈（6 盞；旗在段內 30%／48%、跑者 66%～86%，交界 ±4pt 碰不到）
            for i in 1..<7 {
                finLamp(&ctx, x: g.left(i), ground: g.pathTop, dark: true)
            }
        }
        riverFlags(&ctx, flags, g: g, ink: ink)
        riverDots(&ctx, s, g: g, ink: ink)
        ctx.draw(runner, in: runnerBox)
        riverDayPills(&ctx, s, g: g, ink: ink)
    }

    /// 這一趟的路（成果頁看板，band 132）
    static func paintRunTrail(_ ctx: inout GraphicsContext, rect r: CGRect, scene s: WorkoutTrailScene,
                              dark: Bool, seed: Int) {
        guard r.width > 120, r.height > 60 else { return }
        let ink = HealthRiverInk(dark: dark)
        let g = HealthTrailLayout(rect: r, scene: s)
        switch s.kind {
        case .route:
            trailRoute(&ctx, g: g, scene: s, ink: ink, seed: seed)
        case .strength:
            trailStrength(&ctx, rect: r, scene: s, ink: ink, seed: seed)
        case .noRoute:
            trailNoRoute(&ctx, g: g, scene: s, ink: ink, seed: seed)
        }
    }

    // MARK: 河堤：排版

    /// 旗子：段內 30%（第二面 48%）；旗竿 max(10, 34 × height)，重訓固定 14
    private static func riverFlagSpots(_ s: HealthWeekScene, g: HealthRiverLayout, dark: Bool) -> [HealthFlagSpot] {
        let pairCloth = max(5, min(9, g.seg * 0.18 - 0.8))
        let soloCloth = max(5, min(10, g.seg * 0.3))
        var out: [HealthFlagSpot] = []
        for (i, d) in s.days.enumerated() {
            let pair = Array(d.flags.prefix(2))
            for (j, f) in pair.enumerated() {
                let x = g.at(i, j == 0 ? 0.30 : 0.48).rounded()
                let v = f.height.isFinite ? min(1, max(0, f.height)) : 0
                let h: CGFloat = f.sport == .strength ? 14 : max(10, 34 * CGFloat(v))
                out.append(HealthFlagSpot(x: x, height: h, cloth: pair.count > 1 ? pairCloth : soloCloth,
                                          color: WorkoutPalette.sport(f.sport, dark: dark)))
            }
        }
        return out
    }

    private static func riverRunnerImage(_ ctx: GraphicsContext, _ s: HealthWeekScene,
                                         ink: HealthRiverInk) -> GraphicsContext.ResolvedImage {
        var img = ctx.resolve(Image(systemName: s.runnerSport.icon))
        img.shading = .color(ink.figure)
        return img
    }

    /// 小跑者站在今天那段 75%（13pt 高、照圖示原本的寬高比）；左邊讓開那天的旗面、右邊不壓到下一段的交界（夜裡的路燈）。
    /// 騎車的圖示比較寬，放不下就整個等比例縮小（最小 10pt 高，不壓扁）
    private static func riverRunnerBox(_ size: CGSize, _ s: HealthWeekScene, g: HealthRiverLayout) -> CGRect {
        let aspect = size.height > 0.5 ? min(1.6, max(0.5, size.width / size.height)) : 0.85
        let day = s.days[g.today]
        let pairCloth = max(5, min(9, g.seg * 0.18 - 0.8))
        let soloCloth = max(5, min(10, g.seg * 0.3))
        var lo = g.left(g.today) + 2
        if day.flags.count >= 2 {
            lo = g.at(g.today, 0.48) + pairCloth + 1.5
        } else if day.flags.count == 1 {
            lo = g.at(g.today, 0.30) + soloCloth + 1.5
        }
        let hi = g.left(g.today + 1) - 1.5
        var h: CGFloat = 13
        var w = h * aspect
        let room = max(6, hi - lo)
        if w > room {
            h = max(10, room / aspect)
            w = h * aspect
        }
        let cx = min(max(g.at(g.today, 0.75), lo + w / 2), hi - w / 2)
        return CGRect(x: cx - w / 2, y: g.pathTop + 0.5 - h, width: w, height: h)
    }

    // MARK: 河堤：畫

    /// 遠方一排淡淡的樓＋河堤草地
    private static func riverBackdrop(_ ctx: inout GraphicsContext, g: HealthRiverLayout, ink: HealthRiverInk, seed: Int) {
        let r = g.rect
        TripBoardSkyArt.paintFarRow(&ctx, width: r.width, ground: g.grassTop + 1, band: 40,
                                    ink: farInk(dark: ink.dark), seed: seed)
        let grass = CGRect(x: r.minX, y: g.grassTop, width: r.width, height: max(0, g.waterTop - g.grassTop))
        ctx.fill(Path(grass), with: .linearGradient(Gradient(colors: [ink.grassTop, ink.grassBottom]),
                                                    startPoint: CGPoint(x: 0, y: grass.minY),
                                                    endPoint: CGPoint(x: 0, y: grass.maxY)))
    }

    /// 行道樹 3～5 棵：站在草地上緣（步道後面），讓開旗子、跑者、路燈，彼此至少隔 18pt
    private static func riverTrees(_ ctx: inout GraphicsContext, g: HealthRiverLayout, dark: Bool, seed: Int,
                                   avoid: [ClosedRange<CGFloat>]) {
        var rnd = InkRandom(seed &* 11 &+ 3)
        var placed: [CGFloat] = []
        var tries = 0
        while placed.count < 5 && tries < 28 {
            tries += 1
            let x = g.rect.minX + 6 + CGFloat(rnd.next()) * max(1, g.rect.width - 12)
            let size = 10 + CGFloat(rnd.next()) * 3.5
            let half = size * 0.45
            let span = (x - half)...(x + half)
            if avoid.contains(where: { $0.overlaps(span) }) { continue }
            if placed.contains(where: { abs($0 - x) < 18 }) { continue }
            placed.append(x)
            paintTree(&ctx, at: CGPoint(x: x, y: g.grassTop + 1), size: size, dark: dark)
        }
    }

    /// 步道：今天以前實線（米白、圓頭），交界一個小刻度；今天之後點狀虛線
    private static func riverPath(_ ctx: inout GraphicsContext, g: HealthRiverLayout, ink: HealthRiverInk) {
        let solid = CGRect(x: g.x0, y: g.pathTop, width: max(g.pathH, g.solidEnd - g.x0), height: g.pathH)
        let shape = Path(roundedRect: solid, cornerRadius: g.pathH / 2)
        ctx.fill(shape, with: .color(ink.path))
        ctx.stroke(shape, with: .color(ink.pathEdge), lineWidth: 0.8)
        for i in 1..<7 {
            let x = g.left(i)
            if i <= g.today {
                ctx.fill(Path(CGRect(x: x - 0.5, y: g.pathTop + 1, width: 1, height: g.pathH - 2)),
                         with: .color(ink.tick))
            } else {
                ctx.fill(Path(CGRect(x: x - 0.5, y: g.pathY - 3, width: 1, height: 6)), with: .color(ink.pathDot))
            }
        }
        var x = g.solidEnd + 4
        while x < g.x1 - 1 {
            ctx.fill(Path(ellipseIn: CGRect(x: x - 1.4, y: g.pathY - 1.4, width: 2.8, height: 2.8)),
                     with: .color(ink.pathDot))
            x += 5
        }
    }

    /// 小旗：竿插在步道上緣，三角旗面運動色＋細白邊，竿頭一顆小圓
    private static func riverFlags(_ ctx: inout GraphicsContext, _ flags: [HealthFlagSpot], g: HealthRiverLayout,
                                   ink: HealthRiverInk) {
        let base = g.pathTop + 0.5
        for f in flags {
            let top = base - f.height
            ctx.fill(Path(CGRect(x: f.x - 0.55, y: top, width: 1.1, height: f.height)), with: .color(ink.pole))
            var cloth = Path()
            cloth.move(to: CGPoint(x: f.x + 0.5, y: top + 0.5))
            cloth.addLine(to: CGPoint(x: f.x + 0.5 + f.cloth, y: top + 3.6))
            cloth.addLine(to: CGPoint(x: f.x + 0.5, y: top + 6.7))
            cloth.closeSubpath()
            ctx.fill(cloth, with: .color(f.color))
            ctx.stroke(cloth, with: .color(ink.flagEdge), lineWidth: 0.6)
            ctx.fill(Path(ellipseIn: CGRect(x: f.x - 1.1, y: top - 1.6, width: 2.2, height: 2.2)), with: .color(ink.pole))
        }
    }

    /// 第三種運動起的小點放在段內哪裡：17%（第一面旗的左邊）。
    /// brief 寫 60%，但兩面旗時第二面的旗面從 48% 伸到約 64%（343pt 寬一段 43pt、旗面 7pt），點會疊在旗面上；
    /// 17% 左邊是交界（夜裡的路燈竿 ±0.7pt）、右邊是第一面旗竿（30%），都碰不到
    private static let riverDotSpot: CGFloat = 0.17

    /// 同一天第三種運動起：步道上方 4pt 一顆小點（最多往上疊 3 顆）
    private static func riverDots(_ ctx: inout GraphicsContext, _ s: HealthWeekScene, g: HealthRiverLayout,
                                  ink: HealthRiverInk) {
        for (i, d) in s.days.enumerated() where d.extraDots > 0 {
            let x = g.at(i, riverDotSpot)
            for k in 0..<min(d.extraDots, 3) {
                let y = g.pathTop - 4 - CGFloat(k) * 3.6
                ctx.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)), with: .color(ink.dot))
            }
        }
    }

    /// 步道下方「一」…「日」小牌；今天那塊深藍底白字
    private static func riverDayPills(_ ctx: inout GraphicsContext, _ s: HealthWeekScene, g: HealthRiverLayout,
                                      ink: HealthRiverInk) {
        for (i, d) in s.days.enumerated() {
            let isToday = i == g.today
            let box = healthPillBox(ctx, d.label, center: CGPoint(x: g.at(i, 0.5), y: g.pillTop + 6.5),
                                    size: 8.5, height: 13, bounds: g.rect)
            healthDrawPill(&ctx, d.label, box: box, fill: isToday ? ink.todayFill : ink.pillFill,
                           ink: isToday ? Color.white : ink.pillInk, size: 8.5, shadow: false)
        }
    }

    // MARK: 共用：河、小牌、小人

    /// 河：淡藍水面＋岸邊一道亮線＋幾道白色波紋；夜裡右邊一道月光（白 0.25 的直條漸層＋一層一層變短的亮線）
    private static func healthWater(_ ctx: inout GraphicsContext, rect w: CGRect, ink: HealthRiverInk, seed: Int) {
        guard w.height > 2, w.width > 2 else { return }
        ctx.fill(Path(w), with: .linearGradient(Gradient(colors: [ink.waterTop, ink.waterBottom]),
                                                startPoint: CGPoint(x: 0, y: w.minY),
                                                endPoint: CGPoint(x: 0, y: w.maxY)))
        ctx.fill(Path(CGRect(x: w.minX, y: w.minY, width: w.width, height: 1.2)), with: .color(ink.shore))
        var rnd = InkRandom(seed &* 3 &+ 1)
        for _ in 0..<6 {
            let x = w.minX + CGFloat(rnd.next()) * w.width
            let y = w.minY + 5 + CGFloat(rnd.next()) * max(1, w.height - 9)
            let l = 8 + CGFloat(rnd.next()) * 12
            var p = Path()
            p.move(to: CGPoint(x: x, y: y))
            p.addQuadCurve(to: CGPoint(x: x + l, y: y), control: CGPoint(x: x + l / 2, y: y - 1.6))
            ctx.stroke(p, with: .color(ink.ripple), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }
        guard ink.dark else { return }
        let mx = w.minX + w.width * 0.88
        ctx.fill(Path(CGRect(x: mx - 7, y: w.minY + 1, width: 14, height: w.height - 1)),
                 with: .linearGradient(Gradient(colors: [Color.white.opacity(0.25), Color.white.opacity(0)]),
                                       startPoint: CGPoint(x: 0, y: w.minY),
                                       endPoint: CGPoint(x: 0, y: w.maxY)))
        for i in 0..<5 {
            let y = w.minY + 3 + CGFloat(i) * (w.height - 5) / 5
            let lw = 14 - CGFloat(i) * 2
            ctx.fill(Path(roundedRect: CGRect(x: mx - lw / 2, y: y, width: lw, height: 1.6), cornerRadius: 0.8),
                     with: .color(ink.moon.opacity(0.55 - Double(i) * 0.08)))
        }
    }

    /// 小牌的位置：量好字寬、置中在 center、整塊夾在 band 裡（照 driveMakePill）
    private static func healthPillBox(_ ctx: GraphicsContext, _ s: String, center c: CGPoint, size: CGFloat,
                                      height h: CGFloat, bounds r: CGRect) -> CGRect {
        let t = ctx.resolve(Text(s).font(.system(size: size, weight: .heavy)))
        let w = max(h, (t.measure(in: CGSize(width: 300, height: 40)).width + 8).rounded(.up))
        let x = min(max(r.minX + 2, (c.x - w / 2).rounded()), r.maxX - w - 2)
        let y = min(max(r.minY + 1, (c.y - h / 2).rounded()), r.maxY - h - 1)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private static func healthDrawPill(_ ctx: inout GraphicsContext, _ s: String, box: CGRect, fill: Color, ink: Color,
                                       size: CGFloat, shadow: Bool) {
        let shape = Path(roundedRect: box, cornerRadius: box.height / 2)
        if shadow {
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: Color.black.opacity(0.2), radius: 1.5, x: 0, y: 0.5))
                layer.fill(shape, with: .color(fill))
            }
        } else {
            ctx.fill(shape, with: .color(fill))
        }
        let t = ctx.resolve(Text(s).font(.system(size: size, weight: .heavy)).foregroundStyle(ink))
        ctx.draw(t, at: CGPoint(x: box.midX, y: box.midY), anchor: .center)
    }

    /// 小人（運動圖示）：照圖示原本的寬高比，最寬 maxWidth（放不下就整個縮小）
    private static func healthFigure(_ ctx: inout GraphicsContext, sport: WorkoutSport, centerX cx: CGFloat,
                                     bottom: CGFloat, height: CGFloat, maxWidth: CGFloat, ink: HealthRiverInk) {
        var img = ctx.resolve(Image(systemName: sport.icon))
        img.shading = .color(ink.figure)
        let size = img.size
        let aspect = size.height > 0.5 ? min(1.6, max(0.5, size.width / size.height)) : 0.85
        var h = height
        var w = h * aspect
        if w > maxWidth {
            w = maxWidth
            h = w / aspect
        }
        ctx.draw(img, in: CGRect(x: cx - w / 2, y: bottom - h, width: w, height: h))
    }

    // MARK: 這一趟的路：有路線

    private static func trailRoute(_ ctx: inout GraphicsContext, g: HealthTrailLayout, scene s: WorkoutTrailScene,
                                   ink: HealthRiverInk, seed: Int) {
        let plan = trailLayout(ctx, g: g, scene: s)
        if g.hilly {
            trailHills(&ctx, g: g, ink: ink, seed: seed)
        } else {
            trailRiverbank(&ctx, g: g, ink: ink, seed: seed)
        }
        trailTrees(&ctx, g: g, dark: ink.dark, seed: seed, count: g.hilly ? 5 : 6, avoid: plan.reserved)
        trailRoad(&ctx, g: g, scene: s, ink: ink)
        trailStartFlag(&ctx, plan, ink: ink)
        for p in plan.posts {
            let h: CGFloat = p.tall ? 16 : 10
            ctx.fill(Path(CGRect(x: p.x - 0.7, y: p.ground - h, width: 1.4, height: h)), with: .color(ink.pole))
        }
        trailArch(&ctx, plan, sport: s.sport, ink: ink)
        // 小跑者站在終點拱門下（兩根柱子中間）
        let a = plan.arch
        healthFigure(&ctx, sport: s.sport, centerX: a.midX, bottom: plan.archGround + 0.5, height: 13,
                     maxWidth: a.width - 5, ink: ink)
        for sg in plan.signs {
            healthDrawPill(&ctx, sg.text, box: sg.box, fill: ink.markFill, ink: ink.markInk, size: 9, shadow: true)
        }
        if let c = plan.star {
            var star = ctx.resolve(Image(systemName: "star.fill"))
            star.shading = .color(HealthRiverInk.star)
            ctx.draw(star, in: CGRect(x: c.x - 4.5, y: c.y - 4.5, width: 9, height: 9))
        }
    }

    /// 排版：起點旗、拱門、每根柱子的小牌（太密就隔 k 根才掛；最快那一根一定掛、上面一顆星）
    private static func trailLayout(_ ctx: GraphicsContext, g: HealthTrailLayout, scene s: WorkoutTrailScene) -> HealthTrailPlan {
        var plan = HealthTrailPlan()
        let r = g.rect
        let fg = g.groundY(0) - 2
        plan.flagPole = CGPoint(x: g.x0, y: fg)
        plan.flagBox = CGRect(x: g.x0 - 1, y: fg - 24, width: 14, height: 24)
        let ax = min(g.x1 - 1, r.maxX - 21)
        let ag = g.groundY(1) - 2
        plan.archGround = ag
        plan.arch = CGRect(x: ax, y: ag - 31, width: 17, height: 31)
        plan.reserved = [(plan.flagBox.minX - 3)...(plan.flagBox.maxX + 3),
                         (plan.arch.minX - 4)...(plan.arch.maxX + 4)]

        let n = min(s.marks.count, s.markLabels.count)
        guard n > 0 else { return plan }
        var xs: [CGFloat] = []
        var widths: [CGFloat] = []
        for i in 0..<n {
            xs.append(g.x(s.marks[i]))
            widths.append(trailSignWidth(ctx, s.markLabels[i]))
        }
        // 相鄰兩根的最小間距；小牌放不下（不到 14pt、或比最寬的牌子＋3 還窄）就隔 k 根才掛
        var minGap = CGFloat.greatestFiniteMagnitude
        if n >= 2 {
            for i in 1..<n { minGap = min(minGap, abs(xs[i] - xs[i - 1])) }
        }
        let need = max(14, (widths.max() ?? 14) + 3)
        var k = 1
        if minGap < need, minGap > 0.5 {
            k = max(1, Int((need / minGap).rounded(.up)))
        }
        let starIndex: Int? = s.star.flatMap { ($0 >= 0 && $0 < n) ? $0 : nil }
        var order: [Int] = []
        if let st = starIndex { order.append(st) }
        for i in 0..<n where (i + 1) % k == 0 && i != starIndex {
            order.append(i)
        }
        var placed: [CGRect] = [plan.flagBox.insetBy(dx: -2, dy: -2), plan.arch.insetBy(dx: -2, dy: -2)]
        var labeled = Set<Int>()
        for i in order {
            let ground = g.groundY(s.marks[i]) - 2
            let isStar = i == starIndex
            let minY = r.minY + (isStar ? 10 : 1)
            var box = CGRect(x: (xs[i] - widths[i] / 2).rounded(), y: max(minY, ground - 16 - 13),
                             width: widths[i], height: 13)
            box.origin.x = min(max(r.minX + 2, box.origin.x), r.maxX - box.width - 2)
            if isStar {
                box = trailNudge(box, away: placed, bounds: r)
            } else if placed.contains(where: { $0.intersects(box) }) {
                continue
            }
            placed.append(box.insetBy(dx: -1.5, dy: 0))
            labeled.insert(i)
            plan.signs.append(HealthTrailPlan.Sign(text: s.markLabels[i], box: box))
            if isStar {
                plan.star = CGPoint(x: box.midX, y: max(r.minY + 5, box.minY - 5.5))
            }
        }
        for i in 0..<n {
            plan.posts.append(HealthTrailPlan.Post(x: xs[i], ground: g.groundY(s.marks[i]) - 2,
                                                   tall: labeled.contains(i)))
            plan.reserved.append((xs[i] - 4)...(xs[i] + 4))
        }
        return plan
    }

    private static func trailSignWidth(_ ctx: GraphicsContext, _ s: String) -> CGFloat {
        let t = ctx.resolve(Text(s).font(.system(size: 9, weight: .heavy)))
        return max(13, (t.measure(in: CGSize(width: 300, height: 40)).width + 8).rounded(.up))
    }

    /// 最快那一根的牌子壓到起點旗或拱門：往旁邊推開（推不出 band 就夾在裡面）
    private static func trailNudge(_ box: CGRect, away blockers: [CGRect], bounds r: CGRect) -> CGRect {
        var b = box
        for blk in blockers where blk.intersects(b) {
            if b.midX >= blk.midX {
                b.origin.x = blk.maxX + 1
            } else {
                b.origin.x = blk.minX - 1 - b.width
            }
        }
        b.origin.x = min(max(r.minX + 2, b.origin.x), r.maxX - b.width - 2)
        return b
    }

    /// 平的河濱：遠樓、草地（上緣就是地面線）、路下一條河
    private static func trailRiverbank(_ ctx: inout GraphicsContext, g: HealthTrailLayout, ink: HealthRiverInk, seed: Int) {
        let r = g.rect
        TripBoardSkyArt.paintFarRow(&ctx, width: r.width, ground: g.base - 4, band: 42,
                                    ink: farInk(dark: ink.dark), seed: seed)
        let grass = trailGroundShape(g, down: g.waterTop)
        ctx.fill(grass, with: .linearGradient(Gradient(colors: [ink.grassTop, ink.grassBottom]),
                                              startPoint: CGPoint(x: 0, y: g.base - 4),
                                              endPoint: CGPoint(x: 0, y: g.waterTop)))
        healthWater(&ctx, rect: CGRect(x: r.minX, y: g.waterTop, width: r.width, height: r.maxY - g.waterTop),
                    ink: ink, seed: seed)
    }

    /// 山稜（爬升夠多）：後面一排遠山（照 paintRidge 的起伏），前面這一趟的高度剖面，稜線一道白邊
    private static func trailHills(_ ctx: inout GraphicsContext, g: HealthTrailLayout, ink: HealthRiverInk, seed: Int) {
        let r = g.rect
        let phase = Double(seed % 628) / 100
        func farY(_ x: CGFloat) -> CGFloat {
            let t = Double(x)
            let wave = 8 * sin(t / 41 + phase) + 5 * sin(t / 17 + phase * 2)
            return r.minY + 50 - CGFloat(wave)
        }
        var far = Path()
        far.move(to: CGPoint(x: r.minX, y: r.maxY))
        var x = r.minX
        while x <= r.maxX {
            far.addLine(to: CGPoint(x: x, y: farY(x)))
            x += 4
        }
        far.addLine(to: CGPoint(x: r.maxX, y: farY(r.maxX)))
        far.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        far.closeSubpath()
        ctx.fill(far, with: .color(ink.hillFar))
        let hill = trailGroundShape(g, down: r.maxY)
        ctx.fill(hill, with: .linearGradient(Gradient(colors: [ink.ridgeTop, ink.ridgeBottom]),
                                             startPoint: CGPoint(x: 0, y: g.top),
                                             endPoint: CGPoint(x: 0, y: r.maxY)))
        ctx.stroke(trailGroundLine(g), with: .color(ink.ridgeLine), lineWidth: 1.4)
    }

    /// 地面線（整個 band 寬；起點、終點外面照兩端的高度接平）
    private static func trailGroundLine(_ g: HealthTrailLayout) -> Path {
        let r = g.rect
        var p = Path()
        var x = r.minX
        p.move(to: CGPoint(x: x, y: g.groundY(atX: x)))
        while x < r.maxX {
            x = min(r.maxX, x + 2)
            p.addLine(to: CGPoint(x: x, y: g.groundY(atX: x)))
        }
        return p
    }

    /// 地面線往下收到 down 的一塊（草地、山）
    private static func trailGroundShape(_ g: HealthTrailLayout, down: CGFloat) -> Path {
        let r = g.rect
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: down))
        var x = r.minX
        p.addLine(to: CGPoint(x: x, y: g.groundY(atX: x)))
        while x < r.maxX {
            x = min(r.maxX, x + 2)
            p.addLine(to: CGPoint(x: x, y: g.groundY(atX: x)))
        }
        p.addLine(to: CGPoint(x: r.maxX, y: down))
        p.closeSubpath()
        return p
    }

    /// 行道樹：站在路的後面（樹幹底在路面白邊上緣，看得到樹幹），讓開起點旗、拱門、柱子、小牌
    private static func trailTrees(_ ctx: inout GraphicsContext, g: HealthTrailLayout, dark: Bool, seed: Int,
                                   count: Int, avoid: [ClosedRange<CGFloat>]) {
        var rnd = InkRandom(seed &* 5 &+ 9)
        var placed: [CGFloat] = []
        var tries = 0
        while placed.count < count && tries < count * 5 {
            tries += 1
            let x = g.rect.minX + 8 + CGFloat(rnd.next()) * max(1, g.rect.width - 16)
            let size = 9 + CGFloat(rnd.next()) * 3
            let half = size * 0.45
            let span = (x - half)...(x + half)
            if avoid.contains(where: { $0.overlaps(span) }) { continue }
            if placed.contains(where: { abs($0 - x) < 16 }) { continue }
            placed.append(x)
            paintTree(&ctx, at: CGPoint(x: x, y: g.groundY(atX: x) - 6), size: size, dark: dark)
        }
    }

    /// 路面：先一條白邊（深色深藍邊）7pt，再照 bands 一段一段上配速色 5pt；bands 空的整條運動色淡一點
    private static func trailRoad(_ ctx: inout GraphicsContext, g: HealthTrailLayout, scene s: WorkoutTrailScene,
                                  ink: HealthRiverInk) {
        let whole = trailRoadPath(g, from: 0, to: 1)
        ctx.stroke(whole, with: .color(WorkoutPalette.casing(dark: ink.dark)),
                   style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
        guard !s.bands.isEmpty else {
            ctx.stroke(whole, with: .color(WorkoutPalette.sport(s.sport, dark: ink.dark).opacity(0.6)),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            return
        }
        for b in s.bands {
            let a = b.from.isFinite ? min(1, max(0, b.from)) : 0
            let z = b.to.isFinite ? min(1, max(0, b.to)) : 0
            guard z > a else { continue }
            ctx.stroke(trailRoadPath(g, from: a, to: z), with: .color(WorkoutPalette.pace(b.level, dark: ink.dark)),
                       style: StrokeStyle(lineWidth: 5, lineCap: .butt, lineJoin: .round))
        }
    }

    /// 路的中線（貼著地面線、高 2.5pt），每 2pt 一點
    private static func trailRoadPath(_ g: HealthTrailLayout, from a: Double, to z: Double) -> Path {
        let xa = g.x(a)
        let xz = g.x(z)
        let steps = max(1, Int(((xz - xa) / 2).rounded(.up)))
        var p = Path()
        for k in 0...steps {
            let x = xa + (xz - xa) * CGFloat(k) / CGFloat(steps)
            let pt = CGPoint(x: x, y: g.groundY(atX: x) - 2.5)
            if k == 0 {
                p.move(to: pt)
            } else {
                p.addLine(to: pt)
            }
        }
        return p
    }

    /// 起點：一根竿＋白色三角旗（細灰邊）
    private static func trailStartFlag(_ ctx: inout GraphicsContext, _ plan: HealthTrailPlan, ink: HealthRiverInk) {
        let p = plan.flagPole
        ctx.fill(Path(CGRect(x: p.x - 0.65, y: p.y - 24, width: 1.3, height: 24)), with: .color(ink.startPole))
        var cloth = Path()
        cloth.move(to: CGPoint(x: p.x + 0.6, y: p.y - 24))
        cloth.addLine(to: CGPoint(x: p.x + 12, y: p.y - 20))
        cloth.addLine(to: CGPoint(x: p.x + 0.6, y: p.y - 16))
        cloth.closeSubpath()
        ctx.fill(cloth, with: .color(Color.white))
        ctx.stroke(cloth, with: .color(ink.flagLine), lineWidth: 0.8)
    }

    /// 終點：兩根柱子＋半圓頂（運動色），柱子之間掛一條小方格布
    private static func trailArch(_ ctx: inout GraphicsContext, _ plan: HealthTrailPlan, sport: WorkoutSport,
                                  ink: HealthRiverInk) {
        let a = plan.arch
        let ground = plan.archGround
        let color = WorkoutPalette.sport(sport, dark: ink.dark)
        let pillar: CGFloat = 2.2
        let pillarTop = ground - 22
        for px in [a.minX, a.maxX - pillar] {
            ctx.fill(Path(roundedRect: CGRect(x: px, y: pillarTop, width: pillar, height: ground - pillarTop + 0.5),
                          cornerRadius: 0.8), with: .color(color))
        }
        let left = a.minX + pillar / 2
        let right = a.maxX - pillar / 2
        let cx = (left + right) / 2
        let rad = (right - left) / 2
        let k: CGFloat = 0.552
        var arc = Path()
        arc.move(to: CGPoint(x: left, y: pillarTop + 0.5))
        arc.addCurve(to: CGPoint(x: cx, y: pillarTop + 0.5 - rad),
                     control1: CGPoint(x: left, y: pillarTop + 0.5 - rad * k),
                     control2: CGPoint(x: cx - rad * k, y: pillarTop + 0.5 - rad))
        arc.addCurve(to: CGPoint(x: right, y: pillarTop + 0.5),
                     control1: CGPoint(x: cx + rad * k, y: pillarTop + 0.5 - rad),
                     control2: CGPoint(x: right, y: pillarTop + 0.5 - rad * k))
        ctx.stroke(arc, with: .color(color), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        // 方格布（終點線）
        let bx = a.minX + pillar
        let bw = a.width - pillar * 2
        let cols = 5
        let cw = bw / CGFloat(cols)
        ctx.fill(Path(CGRect(x: bx, y: pillarTop + 1, width: bw, height: 4)), with: .color(Color.white))
        for c in 0..<cols {
            for row in 0..<2 where (c + row) % 2 == 0 {
                ctx.fill(Path(CGRect(x: bx + CGFloat(c) * cw, y: pillarTop + 1 + CGFloat(row) * 2, width: cw, height: 2)),
                         with: .color(ink.startPole))
            }
        }
    }

    // MARK: 這一趟的路：重訓、沒有路線

    /// 重訓：一支槓鈴，兩邊對稱一片一片槓片（一個動作一片，高＝24 + 44 × plates，最大的靠內、放在地墊上）
    private static func trailStrength(_ ctx: inout GraphicsContext, rect r: CGRect, scene s: WorkoutTrailScene,
                                      ink: HealthRiverInk, seed: Int) {
        let floor = r.maxY - 18
        TripBoardSkyArt.paintFarRow(&ctx, width: r.width, ground: floor, band: 46, ink: farInk(dark: ink.dark), seed: seed)
        ctx.fill(Path(CGRect(x: r.minX, y: floor, width: r.width, height: r.maxY - floor)),
                 with: .color(groundFill(dark: ink.dark)))
        let raw = s.plates.isEmpty ? [0.6] : Array(s.plates.prefix(8))
        let plates = raw.map { $0.isFinite ? min(1, max(0.2, $0)) : 0.6 }.sorted(by: >)
        let cx = r.midX
        let barY = floor - 34
        let pw: CGFloat = plates.count <= 4 ? 10 : 7      // 動作少的時候槓片厚一點，不會只剩幾根細條
        let gap: CGFloat = 1.6
        let sleeve = CGFloat(plates.count) * (pw + gap) + 10
        let half = min(r.width * 0.38, max(sleeve + 46, r.width * 0.3))
        let collar = half - sleeve
        // 地墊、影子
        ctx.fill(Path(roundedRect: CGRect(x: cx - half - 10, y: floor - 2, width: half * 2 + 20, height: 6), cornerRadius: 3),
                 with: .color(ink.mat))
        ctx.fill(Path(ellipseIn: CGRect(x: cx - half, y: floor - 3, width: half * 2, height: 5)), with: .color(ink.shadow))
        // 槓（中間細、兩端套筒粗一點）
        ctx.fill(Path(roundedRect: CGRect(x: cx - collar, y: barY - 1.8, width: collar * 2, height: 3.6), cornerRadius: 1.8),
                 with: .color(ink.bar))
        for side in [CGFloat(-1), CGFloat(1)] {
            let sx = side > 0 ? cx + collar : cx - half
            ctx.fill(Path(roundedRect: CGRect(x: sx, y: barY - 2.6, width: sleeve, height: 5.2), cornerRadius: 2.6),
                     with: .color(ink.bar))
            let cxr = side > 0 ? cx + collar : cx - collar - 3
            ctx.fill(Path(roundedRect: CGRect(x: cxr, y: barY - 6, width: 3, height: 12), cornerRadius: 1),
                     with: .color(ink.pole))
        }
        // 槓片
        let top = Color(tb: 0xB3A8F0)
        let bottom = WorkoutPalette.sport(.strength, dark: ink.dark)
        for (k, v) in plates.enumerated() {
            let h = 24 + 44 * CGFloat(v)
            let off = collar + 4 + CGFloat(k) * (pw + gap)
            for side in [CGFloat(-1), CGFloat(1)] {
                let x = side > 0 ? cx + off : cx - off - pw
                let rect = CGRect(x: x, y: barY - h / 2, width: pw, height: h)
                let shape = Path(roundedRect: rect, cornerRadius: 2)
                ctx.fill(shape, with: .linearGradient(Gradient(colors: [top, bottom]),
                                                      startPoint: CGPoint(x: 0, y: rect.minY),
                                                      endPoint: CGPoint(x: 0, y: rect.maxY)))
                ctx.stroke(shape, with: .color(Color.white.opacity(ink.dark ? 0.25 : 0.6)), lineWidth: 0.6)
            }
        }
    }

    /// 沒有路線：平的河堤、點狀虛線步道、中間一塊小牌（「這趟沒有路線」），步道右端站著小人
    private static func trailNoRoute(_ ctx: inout GraphicsContext, g: HealthTrailLayout, scene s: WorkoutTrailScene,
                                     ink: HealthRiverInk, seed: Int) {
        let r = g.rect
        var noteBox: CGRect? = nil
        if let note = s.note, !note.isEmpty {
            noteBox = healthPillBox(ctx, note, center: CGPoint(x: r.midX, y: g.base - 22), size: 9.5, height: 18,
                                    bounds: r)
        }
        var avoid: [ClosedRange<CGFloat>] = [(g.x1 - 14)...(g.x1 + 6)]
        if let b = noteBox { avoid.append((b.minX - 4)...(b.maxX + 4)) }
        trailRiverbank(&ctx, g: g, ink: ink, seed: seed)
        trailTrees(&ctx, g: g, dark: ink.dark, seed: seed, count: 5, avoid: avoid)
        var x = g.x0
        while x <= g.x1 {
            ctx.fill(Path(ellipseIn: CGRect(x: x - 1.6, y: g.groundY(atX: x) - 4.1, width: 3.2, height: 3.2)),
                     with: .color(ink.pathDot))
            x += 5
        }
        healthFigure(&ctx, sport: s.sport, centerX: g.x1 - 4, bottom: g.groundY(1) - 2, height: 13, maxWidth: 16,
                     ink: ink)
        if let b = noteBox, let note = s.note {
            healthDrawPill(&ctx, note, box: b, fill: ink.pillFill, ink: ink.pillInk, size: 9.5, shadow: true)
        }
    }
}
