import SwiftUI

// MARK: - 載具卡片看板的風景：這台車的路（v25.540）
//
// [v25.540] 載具卡片看板最下面那一條（judge「看板」的第二步，本版直接做，不先給 FinRoadScene 加 window）：
//   路     asOf 那個月往前 11 個月～往後 4 個月月初，車停在今天（大約 75% 的位置）。
//          交車以前的路畫淡、沒有圓標；已售出的路只畫到賣出日的下一個月，後面是草地。
//   圓標   車身後每個日曆月一顆，大小＝那個月花多少（半徑 5＋4.5×√(該月÷最大月)），字＝花最多的種類：
//          油／充／修／停／其，跟列表看板同一組字與色；深色另訂一組亮一點的。
//   路牌   車前最多 3 塊：「接下來」最早的幾件（綠）、該保養了（橘）、車貸繳完。撞到就往上錯開。
//   車     轎車或機車；顏色＝VehicleScriptName.theme(v) 的漸層（跟列表項目卡同色）；電車車門小閃電、油電小插頭。
//          有車貸：車身後段白斜線＋「車貸 43%」牌；已售出：整台 45% 透明＋名牌「已售・<名字>」，沒有路牌和斜線。
//          深色：車燈往前照一道琥珀色光、車窗亮琥珀色、白斜線 0.58。
// 規矩跟其他看板風景一樣：數字在頭部的 Text 裡（VoiceOver 唸那邊），這裡的字只是裝飾。
// 所有東西都畫在 band（rect）裡；牌子先排好位置、最後才畫，互相讓開（照 FinHouseScene 的切法）。

/// [v25.540] 載具卡片看板：這台車的路（asOf 那個月往前 11 個月～往後 4 個月月初）。
/// 位置一律是 0…1（VehicleCardData 算好），這裡不碰日期；數字在頭部 Text，場景上的字只是裝飾。
struct FinDriveScene: Equatable {
    enum Shape: Equatable { case car, scooter }          // 機車、電動機車畫機車
    enum Badge: Equatable { case none, bolt, plug }      // 電車車門小閃電、油電小插頭
    struct Mark: Equatable {
        let t: Double                 // 那個日曆月的中點
        let kind: FinRoadScene.Kind   // 油／充／修／停／其（FinRoadScene.Kind.of，洗車算其）
        let amount: Double            // 那個月的金額（台幣）；半徑＝5＋4.5×√(amount÷最大月)
    }
    struct Sign: Equatable {
        let t: Double
        let label: String             // 「2/12 保險」「約 1/15 保養」「該保養了」「車貸繳完」
        var isWarn = false            // 橘牌（該保養了）
    }
    struct Tick: Equatable {
        let t: Double                 // 每個月月初
        let label: String             // 1 月寫「2027」、4／7／10 月寫「M月」、其他空字串（只畫刻度）
    }
    var today: Double = 0.75          // 車停的位置（已售出＝賣出日）
    var todayLabel: String = "今天"   // 車下的字；已售出 ""（不寫）
    var roadEnd: Double = 1           // 路畫到哪（已售出＝賣出日下一個月月初的 t；其他 1）
    var purchaseT: Double? = nil      // 「交車」小旗；購入日不在範圍內 nil；這之前的路畫淡、沒有圓標
    var marks: [Mark] = []
    var signs: [Sign] = []            // 最多 3 塊（已售出空的）
    var ticks: [Tick] = []
    var shape: Shape = .car
    var badge: Badge = .none
    var bodyTop: UInt32 = 0x7FE3D0    // 車身漸層＝VehicleScriptName.theme(v).top／bottom
    var bodyBottom: UInt32 = 0x1A9C8C
    var owedFraction: Double = 0      // 車身後段白斜線比例（0…1）；0＝不畫
    var owedLabel: String? = nil      // 「車貸 43%」「還要繳 47%」；nil＝不掛
    var isSold = false                // 車 45% 透明、名牌「已售・<name>」、沒有路牌和斜線
    var name: String = ""             // 名牌用（已截短 8 字；車牌樣用 shareName）
}

// MARK: - 畫的時候用的小東西（只在這個檔裡）

/// 風景的顏色，淺／深各一組（照樣稿 vcard.js paintDriveScene／paintCar）
private struct DriveInk {
    let dark: Bool
    let hillFar: Color       // 遠山
    let hillNear: Color      // 近一點的山丘
    let grass: Color         // 遠排房子前面那一條草地
    let field: Color         // 已售出：路畫完以後的草地
    let road: Color
    let tick: Color          // 月份刻度
    let month: Color         // 月份字
    let stem: Color          // 圓標的細桿
    let markRing: Color      // 圓標外圈
    let markText: Color      // 圓標裡的字
    let signPole: Color
    let flagPole: Color
    let carStroke: Color     // 車身描邊
    let window: Color        // 車窗（夜裡亮琥珀色）
    let shadow: Color        // 車底的影子
    let headlight: Color
    let handle: Color        // 機車的座墊、把手
    let hatch: Color         // 車貸白斜線
    let plateFill: Color     // 名牌底
    let plateInk: Color      // 名牌字

    static let tire = Color(tb: 0x1D2433)
    static let hub = Color(tb: 0xC9D3E3)
    static let tail = Color(tb: 0xE5383B, 0.9)
    static let seam = Color(tb: 0x0B3A36, 0.25)
    static let beam = Color(tb: 0xFFC56B)
    static let flag = Color(tb: 0xE8A317)
    static let signGreen = Color(tb: 0x1F9D57)
    /// 該保養了：白字要讀得到（B85A00 對白 4.7:1；圓標橘 FF9F38 只有 2.1:1，深色的 MoneyTone.warn 更淡）
    static let signWarn = Color(tb: 0xB85A00)

    init(dark: Bool) {
        self.dark = dark
        hillFar = dark ? Color(tb: 0x1A2550, 0.9) : Color(tb: 0xC9DCF0)
        hillNear = dark ? Color(tb: 0x1E2B5C, 0.95) : Color(tb: 0xB5CEE8)
        grass = dark ? Color(tb: 0x1E3B33) : Color(tb: 0xBFE6CB)
        field = dark ? Color(tb: 0x173329) : Color(tb: 0xCFEBD8)
        road = dark ? Color(tb: 0x2A3150) : Color(tb: 0x8A93A6)
        tick = dark ? Color.white.opacity(0.4) : Color(tb: 0x4A5B8C, 0.5)
        month = dark ? Color(tb: 0xA3B2D9) : Color(tb: 0x4A5B8C)
        stem = dark ? Color.white.opacity(0.35) : Color(tb: 0x4A5B8C, 0.35)
        markRing = dark ? Color(tb: 0x0E1428, 0.9) : Color.white.opacity(0.9)
        markText = dark ? Color(tb: 0x0E1428) : Color.white
        signPole = dark ? Color(tb: 0xA3B2D9) : Color(tb: 0x5A6478)
        flagPole = dark ? Color(tb: 0xC9D3E3) : Color(tb: 0x5A6478)
        carStroke = dark ? Color(tb: 0xE6ECFF, 0.85) : Color.white.opacity(0.95)
        window = dark ? Color(tb: 0xFFC56B, 0.95) : Color(tb: 0xDCF4FF)
        shadow = dark ? Color.black.opacity(0.35) : Color(tb: 0x2A3A66, 0.18)
        headlight = dark ? Color(tb: 0xFFE7A8) : Color(tb: 0xFFF4C2)
        handle = dark ? Color(tb: 0xA3B2D9) : Color(tb: 0x1D2433)
        hatch = Color.white.opacity(dark ? 0.58 : 0.85)
        plateFill = dark ? Color(tb: 0x1C2646, 0.92) : Color.white.opacity(0.95)
        plateInk = dark ? Color(tb: 0xE6ECFF) : Color(tb: 0x0B1B45)
    }

    /// 圓標的底色與字：字跟列表看板 paintYearRoad 同一組（「電」已改「充」）；深色另訂亮一點的色
    func mark(_ kind: FinRoadScene.Kind) -> (fill: Color, glyph: String) {
        switch kind {
        case .fuel: return (Color(tb: dark ? 0xFFB866 : 0xFF9F38), "油")
        case .charge: return (Color(tb: dark ? 0x5BD99A : 0x2FBF71), "充")
        case .care: return (Color(tb: dark ? 0x8FA6FF : 0x5B7CFA), "修")
        case .park: return (Color(tb: dark ? 0xA3B2D9 : 0x9AA3B5), "停")
        case .other: return (Color(tb: dark ? 0xA3B2D9 : 0x9AA3B5), "其")
        }
    }
}

/// 路與車的尺寸：一次算好，畫每一塊時都讀這裡
private struct DriveGeometry {
    let rect: CGRect
    let roadTop: CGFloat
    let roadBot: CGFloat
    let x0: CGFloat
    let x1: CGFloat
    let carX: CGFloat
    let endX: CGFloat        // 路畫到哪（roadEnd 1＝畫到底）
    let fadeX: CGFloat       // 交車以前的路畫淡（沒有交車旗＝左緣：整條實心）
    let base: CGFloat        // 車輪著地的那一條線
    let halfWidth: CGFloat   // 車身一半寬（轎車 22.5、機車 16）

    init(rect r: CGRect, scene s: FinDriveScene) {
        let lo = r.minX + 14
        let hi = r.maxX - 14
        func pos(_ t: Double) -> CGFloat { lo + (hi - lo) * CGFloat(min(1, max(0, t))) }
        rect = r
        roadBot = r.maxY - 14
        roadTop = r.maxY - 34
        x0 = lo
        x1 = hi
        carX = pos(s.today)
        endX = s.roadEnd >= 1 ? r.maxX : pos(s.roadEnd)
        if let p = s.purchaseT, p > 0 {
            fadeX = pos(p)
        } else {
            fadeX = r.minX
        }
        base = r.maxY - 18
        halfWidth = s.shape == .car ? 22.5 : 16
    }

    func x(_ t: Double) -> CGFloat {
        x0 + (x1 - x0) * CGFloat(min(1, max(0, t)))
    }

    /// 車（含把手）佔的地方：旁邊的圓標要抬高讓開
    var vehicleBox: CGRect {
        CGRect(x: carX - halfWidth - 1, y: base - 26, width: halfWidth * 2 + 2, height: 26)
    }
}

/// 一塊小牌子（先排好位置，最後才畫，才能互相讓開）；fill nil＝只寫字（車下的「今天」）
private struct DrivePill {
    let text: String
    var box: CGRect
    let fill: Color?
    let ink: Color
    let size: CGFloat
    let weight: Font.Weight
    let radius: CGFloat
}

/// 一顆圓標排好的位置
private struct DriveMarkSpot {
    let x: CGFloat
    let cy: CGFloat
    let rr: CGFloat
    let kind: FinRoadScene.Kind

    var box: CGRect { CGRect(x: x - rr, y: cy - rr, width: rr * 2, height: rr * 2) }
}

/// 一塊路牌：桿子插在那一天，牌子可能被推到旁邊或上面
private struct DriveSignSpot {
    let poleX: CGFloat
    let pill: DrivePill
}

/// 「交車」小旗（旗面右邊剪一個燕尾）
private struct DriveFlag {
    let poleX: CGFloat
    let top: CGFloat
    let cloth: CGRect
    let box: CGRect          // 旗桿＋旗面：圓標、路牌要讓開
}

/// 整幅畫的牌子與圓標位置
private struct DriveLayout {
    var today: DrivePill? = nil
    var flag: DriveFlag? = nil
    var marks: [DriveMarkSpot] = []
    var signs: [DriveSignSpot] = []
    var owed: DrivePill? = nil
    var plate: DrivePill? = nil
}

// MARK: - 畫法

extension MoneyBoardSky {
    /// [v25.540] 載具卡片看板的風景（MoneyBoardSky.paint 分派到這裡；參數形狀跟其他風景一樣）
    static func paintDrive(_ ctx: inout GraphicsContext, rect r: CGRect, scene s: FinDriveScene, dark: Bool, seed: Int) {
        guard r.width > 120, r.height > 60 else { return }
        let g = DriveGeometry(rect: r, scene: s)
        let ink = DriveInk(dark: dark)
        let plan = driveLayout(ctx, g: g, scene: s, ink: ink)
        driveBackdrop(&ctx, g: g, ink: ink, seed: seed)
        driveRoad(&ctx, g: g, ink: ink)
        driveTicks(&ctx, g: g, ticks: s.ticks, today: plan.today?.box, ink: ink)
        driveSignPoles(&ctx, plan.signs, g: g, ink: ink)
        driveMarks(&ctx, plan.marks, g: g, ink: ink)
        if let f = plan.flag {
            driveFlag(&ctx, f, g: g, ink: ink)
        }
        for sp in plan.signs {
            driveDrawPill(&ctx, sp.pill)
        }
        var body = ctx
        if s.isSold { body.opacity = 0.45 }
        driveVehicle(&body, g: g, scene: s, ink: ink)
        driveDrawLabels(&ctx, plan)
    }

    // MARK: 排版（先排好位置，畫的時候照著畫）

    private static func driveLayout(_ ctx: GraphicsContext, g: DriveGeometry, scene s: FinDriveScene,
                                    ink: DriveInk) -> DriveLayout {
        var plan = DriveLayout()
        plan.today = driveTodayPill(ctx, g: g, scene: s, ink: ink)
        plan.flag = driveFlagSpot(ctx, g: g, scene: s)
        plan.marks = driveMarkSpots(s.marks, g: g, flag: plan.flag?.box)
        var avoid = plan.marks.map { $0.box }
        if let f = plan.flag { avoid.append(f.box) }
        if !s.isSold {
            plan.signs = driveSignSpots(ctx, s.signs, g: g, avoid: avoid)
        }
        plan.owed = driveOwedPill(ctx, g: g, scene: s, ink: ink)
        plan.plate = drivePlatePill(ctx, g: g, scene: s, ink: ink, avoid: avoid)
        return plan
    }

    /// 車下的字（「今天」）：淺色用車身深色那一端再壓暗，深色用車身亮的那一端
    private static func driveTodayPill(_ ctx: GraphicsContext, g: DriveGeometry, scene s: FinDriveScene,
                                       ink: DriveInk) -> DrivePill? {
        guard !s.todayLabel.isEmpty else { return nil }
        let color = ink.dark ? Color(tb: s.bodyTop) : TripInk.text(Color(tb: s.bodyBottom), .light)
        return driveMakePill(ctx, s.todayLabel, at: CGPoint(x: g.carX, y: g.roadBot + 1), anchor: .top,
                             fill: nil, ink: color, size: 8, weight: .heavy, height: 12, radius: 0, rect: g.rect)
    }

    /// 交車小旗：插在購入那天；剛好插在車身上（剛買的車）就移到車尾後面，旗面在車頂上方
    private static func driveFlagSpot(_ ctx: GraphicsContext, g: DriveGeometry, scene s: FinDriveScene) -> DriveFlag? {
        guard let p = s.purchaseT, p >= 0, p <= 1 else { return nil }
        let label = ctx.resolve(Text("交車").font(.system(size: 7.5, weight: .black)))
        let tw = label.measure(in: CGSize(width: 200, height: 40)).width
        let cw = (tw + 13).rounded(.up)
        var x = g.x(p)
        let car = g.vehicleBox
        if x > car.minX - 3, x < car.maxX + 2 {
            x = car.minX - 3
        }
        x = min(max(g.rect.minX + 2, x), g.rect.maxX - cw - 3)
        let top = g.roadTop - 26
        let cloth = CGRect(x: x + 0.7, y: top, width: cw, height: 11)
        let box = CGRect(x: x - 1, y: top, width: cw + 2, height: g.roadTop - top)
        return DriveFlag(poleX: x, top: top, cloth: cloth, box: box)
    }

    /// 圓標：靠近車的抬高讓開車頂；擋到交車旗的移到旗子上面
    private static func driveMarkSpots(_ marks: [FinDriveScene.Mark], g: DriveGeometry,
                                       flag: CGRect?) -> [DriveMarkSpot] {
        let spent = marks.filter { $0.amount > 0 }
        let maxAmount = max(spent.map { $0.amount }.max() ?? 1, 1)
        var out: [DriveMarkSpot] = []
        for mk in spent {
            let x = g.x(mk.t)
            let rr = 5 + 4.5 * CGFloat((mk.amount / maxAmount).squareRoot())
            var cy = g.roadTop - 7 - rr
            if abs(x - g.carX) < g.halfWidth + 1.5 + rr {
                cy = g.roadTop - 15 - rr
            }
            if let f = flag {
                let box = CGRect(x: x - rr, y: cy - rr, width: rr * 2, height: rr * 2)
                if f.insetBy(dx: -2, dy: -2).intersects(box) {
                    cy = min(cy, f.minY - 3 - rr)
                }
            }
            out.append(DriveMarkSpot(x: x, cy: cy, rr: rr, kind: mk.kind))
        }
        return out
    }

    /// 路牌：預設在路上方 30～44pt；撞到別的牌子、圓標、旗子就移到它上面（最多 4 次），不超出 band
    private static func driveSignSpots(_ ctx: GraphicsContext, _ signs: [FinDriveScene.Sign], g: DriveGeometry,
                                       avoid: [CGRect]) -> [DriveSignSpot] {
        var placed: [CGRect] = []
        var out: [DriveSignSpot] = []
        for sg in signs.prefix(3) {
            let px = g.x(sg.t)
            let fill = sg.isWarn ? DriveInk.signWarn : DriveInk.signGreen
            var pill = driveMakePill(ctx, sg.label, at: CGPoint(x: px, y: g.roadTop - 37), anchor: .center,
                                     fill: fill, ink: .white, size: 8, weight: .heavy, height: 14, radius: 3,
                                     rect: g.rect)
            let blockers = placed + avoid
            var tries = 0
            while tries < 4, let hit = blockers.first(where: { $0.insetBy(dx: -2, dy: -1).intersects(pill.box) }) {
                pill.box.origin.y = max(g.rect.minY + 1, hit.minY - 3 - pill.box.height)
                tries += 1
            }
            placed.append(pill.box)
            out.append(DriveSignSpot(poleX: px, pill: pill))
        }
        return out
    }

    /// 「車貸 43%」：車尾左邊、壓在路面上（照房屋 houseLeftLabels：finOwedInk 底白字 8.5pt）
    private static func driveOwedPill(_ ctx: GraphicsContext, g: DriveGeometry, scene s: FinDriveScene,
                                      ink: DriveInk) -> DrivePill? {
        guard !s.isSold, s.owedFraction > 0, let label = s.owedLabel, !label.isEmpty else { return nil }
        let at = CGPoint(x: g.carX - g.halfWidth - 3.5, y: g.base - 12)
        return driveMakePill(ctx, label, at: at, anchor: .trailing, fill: finOwedInk(dark: ink.dark), ink: .white,
                             size: 8.5, weight: .heavy, height: 14, radius: 7, rect: g.rect)
    }

    /// 已售出的名牌：車頂上方；擋到圓標、旗子就再往上
    private static func drivePlatePill(_ ctx: GraphicsContext, g: DriveGeometry, scene s: FinDriveScene,
                                       ink: DriveInk, avoid: [CGRect]) -> DrivePill? {
        guard s.isSold else { return nil }
        let name = s.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = name.isEmpty ? "已售" : "已售・\(name)"
        var p = driveMakePill(ctx, text, at: CGPoint(x: g.carX, y: g.base - 52), anchor: .bottom,
                              fill: ink.plateFill, ink: ink.plateInk, size: 8, weight: .black, height: 14,
                              radius: 7, rect: g.rect)
        let hits = avoid.filter { $0.insetBy(dx: -2, dy: -2).intersects(p.box) }
        if let top = hits.map({ $0.minY }).min() {
            p.box.origin.y = max(g.rect.minY + 1, top - 3 - p.box.height)
        }
        return p
    }

    /// 量好字寬、排好位置（anchor＝牌子的哪一點對齊 p），整塊夾在 band 裡面（照 houseMakePill）
    private static func driveMakePill(_ ctx: GraphicsContext, _ s: String, at p: CGPoint, anchor: UnitPoint,
                                      fill: Color?, ink: Color, size: CGFloat, weight: Font.Weight,
                                      height: CGFloat, radius: CGFloat, rect r: CGRect) -> DrivePill {
        let t = ctx.resolve(Text(s).font(.system(size: size, weight: weight)))
        let pw = (t.measure(in: CGSize(width: 300, height: 40)).width + 10).rounded(.up)
        let x = min(max(r.minX + 2, (p.x - pw * anchor.x).rounded()), r.maxX - pw - 2)
        let y = min(max(r.minY + 1, (p.y - height * anchor.y).rounded()), r.maxY - height - 1)
        return DrivePill(text: s, box: CGRect(x: x, y: y, width: pw, height: height), fill: fill, ink: ink,
                         size: size, weight: weight, radius: radius)
    }

    // MARK: 背景、路、刻度

    /// 遠山、近丘、遠排房子、草地條、右邊兩棵樹（照樣稿；山丘的形狀照列表看板 paintYearRoad）
    private static func driveBackdrop(_ ctx: inout GraphicsContext, g: DriveGeometry, ink: DriveInk, seed: Int) {
        let w = g.rect.width
        let top = g.roadTop
        var far = Path()
        far.move(to: CGPoint(x: 0, y: top))
        far.addLine(to: CGPoint(x: 0, y: top - 30))
        far.addQuadCurve(to: CGPoint(x: w * 0.42, y: top - 38), control: CGPoint(x: w * 0.2, y: top - 64))
        far.addQuadCurve(to: CGPoint(x: w * 0.78, y: top - 46), control: CGPoint(x: w * 0.6, y: top - 18))
        far.addQuadCurve(to: CGPoint(x: w, y: top - 48), control: CGPoint(x: w * 0.9, y: top - 64))
        far.addLine(to: CGPoint(x: w, y: top))
        far.closeSubpath()
        ctx.fill(far, with: .color(ink.hillFar))
        var near = Path()
        near.move(to: CGPoint(x: 0, y: top))
        near.addLine(to: CGPoint(x: 0, y: top - 16))
        near.addQuadCurve(to: CGPoint(x: w * 0.55, y: top - 20), control: CGPoint(x: w * 0.3, y: top - 34))
        near.addQuadCurve(to: CGPoint(x: w, y: top - 26), control: CGPoint(x: w * 0.8, y: top - 8))
        near.addLine(to: CGPoint(x: w, y: top))
        near.closeSubpath()
        ctx.fill(near, with: .color(ink.hillNear))
        TripBoardSkyArt.paintFarRow(&ctx, width: w, ground: top, band: 30, ink: farInk(dark: ink.dark), seed: seed)
        ctx.fill(Path(CGRect(x: 0, y: top - 3, width: w, height: 3)), with: .color(ink.grass))
        paintTree(&ctx, at: CGPoint(x: w * 0.86, y: top - 1), size: 18, dark: ink.dark)
        paintTree(&ctx, at: CGPoint(x: w * 0.895, y: top - 1), size: 13, dark: ink.dark)
    }

    /// 路面：交車以前畫淡；已售出畫到賣出日的下一個月，後面換草地
    private static func driveRoad(_ ctx: inout GraphicsContext, g: DriveGeometry, ink: DriveInk) {
        let r = g.rect
        let h = g.roadBot - g.roadTop
        ctx.fill(Path(CGRect(x: r.minX, y: g.roadBot, width: r.width, height: r.maxY - g.roadBot)),
                 with: .color(groundFill(dark: ink.dark)))
        if g.endX < r.maxX {
            ctx.fill(Path(CGRect(x: g.endX, y: g.roadTop, width: r.maxX - g.endX, height: h)), with: .color(ink.field))
        }
        let fadeEnd = min(g.fadeX, g.endX)
        if fadeEnd > r.minX {
            ctx.fill(Path(CGRect(x: r.minX, y: g.roadTop, width: fadeEnd - r.minX, height: h)),
                     with: .color(ink.road.opacity(0.35)))
        }
        if g.endX > g.fadeX {
            ctx.fill(Path(CGRect(x: g.fadeX, y: g.roadTop, width: g.endX - g.fadeX, height: h)), with: .color(ink.road))
        }
        let mid = g.roadTop + h / 2
        var lx = r.minX + 4
        while lx < g.endX - 4 {
            let dw = min(8, g.endX - lx)
            let alpha = lx < g.fadeX ? 0.35 : 0.85
            ctx.fill(Path(CGRect(x: lx, y: mid - 0.8, width: dw, height: 1.6)), with: .color(Color.white.opacity(alpha)))
            lx += 16
        }
    }

    /// 月份刻度（路下面）：有字的才寫；離車 20pt 內、壓到「今天」、超出路尾的不寫
    private static func driveTicks(_ ctx: inout GraphicsContext, g: DriveGeometry, ticks: [FinDriveScene.Tick],
                                   today: CGRect?, ink: DriveInk) {
        for tk in ticks {
            let x = g.x(tk.t)
            if x > g.endX + 1 { continue }
            ctx.fill(Path(CGRect(x: x, y: g.roadBot, width: 1, height: 3)), with: .color(ink.tick))
            guard !tk.label.isEmpty, abs(x - g.carX) > 20 else { continue }
            let t = ctx.resolve(Text(tk.label).font(.system(size: 7.5, weight: .bold)).foregroundStyle(ink.month))
            let m = t.measure(in: CGSize(width: 200, height: 40))
            // 最後一根（例如 9 月看時的「2027」）往左收，不要被看板的圓角切掉
            let lx = min(x + 2, g.rect.maxX - 14 - m.width)
            let box = CGRect(x: lx, y: g.roadBot + 2, width: m.width, height: m.height)
            if let tb = today, tb.insetBy(dx: -2, dy: 0).intersects(box) { continue }
            ctx.draw(t, at: CGPoint(x: lx, y: g.roadBot + 2), anchor: .topLeading)
        }
    }

    // MARK: 圓標、旗子、路牌

    private static func driveSignPoles(_ ctx: inout GraphicsContext, _ signs: [DriveSignSpot], g: DriveGeometry,
                                       ink: DriveInk) {
        for sp in signs {
            let top = sp.pill.box.maxY
            guard g.roadTop > top else { continue }
            ctx.fill(Path(CGRect(x: sp.poleX - 0.8, y: top, width: 1.6, height: g.roadTop - top)),
                     with: .color(ink.signPole))
        }
    }

    private static func driveMarks(_ ctx: inout GraphicsContext, _ spots: [DriveMarkSpot], g: DriveGeometry,
                                   ink: DriveInk) {
        for m in spots {
            var stem = Path()
            stem.move(to: CGPoint(x: m.x, y: g.roadTop))
            stem.addLine(to: CGPoint(x: m.x, y: m.cy + m.rr))
            ctx.stroke(stem, with: .color(ink.stem), lineWidth: 0.8)
            let look = ink.mark(m.kind)
            let dot = Path(ellipseIn: m.box)
            ctx.fill(dot, with: .color(look.fill))
            ctx.stroke(dot, with: .color(ink.markRing), lineWidth: 1)
            let size = max(6.5, m.rr * 1.05)
            let t = ctx.resolve(Text(look.glyph).font(.system(size: size, weight: .black)).foregroundStyle(ink.markText))
            ctx.draw(t, at: CGPoint(x: m.x, y: m.cy), anchor: .center)
        }
    }

    private static func driveFlag(_ ctx: inout GraphicsContext, _ f: DriveFlag, g: DriveGeometry, ink: DriveInk) {
        ctx.fill(Path(CGRect(x: f.poleX - 0.7, y: f.top, width: 1.4, height: g.roadTop - f.top)),
                 with: .color(ink.flagPole))
        let c = f.cloth
        var cloth = Path()
        cloth.move(to: CGPoint(x: c.minX, y: c.minY))
        cloth.addLine(to: CGPoint(x: c.maxX, y: c.minY))
        cloth.addLine(to: CGPoint(x: c.maxX - 4, y: c.midY))
        cloth.addLine(to: CGPoint(x: c.maxX, y: c.maxY))
        cloth.addLine(to: CGPoint(x: c.minX, y: c.maxY))
        cloth.closeSubpath()
        ctx.fill(cloth, with: .color(DriveInk.flag))
        let t = ctx.resolve(Text("交車").font(.system(size: 7.5, weight: .black)).foregroundStyle(Color.white))
        ctx.draw(t, at: CGPoint(x: c.minX + (c.width - 4) / 2, y: c.midY), anchor: .center)
    }

    private static func driveDrawLabels(_ ctx: inout GraphicsContext, _ plan: DriveLayout) {
        if let p = plan.owed {
            driveDrawPill(&ctx, p)
        }
        if let p = plan.plate {
            driveDrawPill(&ctx, p)
        }
        if let p = plan.today {
            driveDrawPill(&ctx, p)
        }
    }

    private static func driveDrawPill(_ ctx: inout GraphicsContext, _ p: DrivePill) {
        if let fill = p.fill {
            ctx.fill(Path(roundedRect: p.box, cornerRadius: p.radius), with: .color(fill))
        }
        let t = ctx.resolve(Text(p.text).font(.system(size: p.size, weight: p.weight)).foregroundStyle(p.ink))
        ctx.draw(t, at: CGPoint(x: p.box.midX, y: p.box.midY), anchor: .center)
    }

    // MARK: 車

    /// 車（已售出時呼叫端傳進來的 ctx 已經 45% 透明）：影子 → 深色車燈的光 → 車身
    private static func driveVehicle(_ ctx: inout GraphicsContext, g: DriveGeometry, scene s: FinDriveScene,
                                     ink: DriveInk) {
        let cx = g.carX
        let base = g.base
        let half = g.halfWidth
        ctx.fill(Path(ellipseIn: CGRect(x: cx - half - 1.5, y: base - 2.5, width: half * 2 + 3, height: 4)),
                 with: .color(ink.shadow))
        switch s.shape {
        case .car:
            if ink.dark, !s.isSold {
                driveBeam(&ctx, x: cx + 21, y: base - 11)
            }
            driveCar(&ctx, cx: cx, base: base, scene: s, ink: ink)
        case .scooter:
            if ink.dark, !s.isSold {
                driveBeam(&ctx, x: cx + 13.5, y: base - 17.5)
            }
            driveScooter(&ctx, cx: cx, base: base, scene: s, ink: ink)
        }
    }

    /// 深色：車燈往前照一道琥珀色的光（FFC56B 35% → 0）
    private static func driveBeam(_ ctx: inout GraphicsContext, x: CGFloat, y: CGFloat) {
        var beam = Path()
        beam.move(to: CGPoint(x: x, y: y - 1.5))
        beam.addLine(to: CGPoint(x: x + 59, y: y - 8))
        beam.addLine(to: CGPoint(x: x + 59, y: y + 10))
        beam.addLine(to: CGPoint(x: x, y: y + 1.5))
        beam.closeSubpath()
        let fade = Gradient(colors: [DriveInk.beam.opacity(0.35), DriveInk.beam.opacity(0)])
        ctx.fill(beam, with: .linearGradient(fade, startPoint: CGPoint(x: x + 1, y: y),
                                             endPoint: CGPoint(x: x + 57, y: y)))
    }

    /// 車身漸層：bodyTop（上）→ bodyBottom（下）
    private static func driveBodyShading(_ s: FinDriveScene, top: CGFloat, bottom: CGFloat) -> GraphicsContext.Shading {
        let grad = Gradient(colors: [Color(tb: s.bodyTop), Color(tb: s.bodyBottom)])
        return .linearGradient(grad, startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom))
    }

    /// 車貸：車身後段（左邊）白斜線，先 clip 到車身，交界一條紅虛線
    private static func driveOwedHatch(_ ctx: inout GraphicsContext, body: Path, zone: CGRect, scene s: FinDriveScene,
                                       ink: DriveInk) {
        guard !s.isSold, s.owedFraction > 0 else { return }
        let len = zone.width * CGFloat(min(1, s.owedFraction))
        var g = ctx
        g.clip(to: body)
        finHatch(&g, CGRect(x: zone.minX, y: zone.minY, width: len, height: zone.height), color: ink.hatch, gap: 3.6)
        var edge = Path()
        edge.move(to: CGPoint(x: zone.minX + len, y: zone.minY))
        edge.addLine(to: CGPoint(x: zone.minX + len, y: zone.maxY))
        g.stroke(edge, with: .color(finOwedInk(dark: ink.dark)), style: StrokeStyle(lineWidth: 1, dash: [2, 1.6]))
    }

    /// 側面轎車（照樣稿 carPath：寬 45、高 20，輪子半徑 5，車頭朝右）
    private static func driveCarPath(cx: CGFloat, base: CGFloat) -> Path {
        func p(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: cx + dx, y: base + dy) }
        var path = Path()
        path.move(to: p(-22, -6))
        path.addLine(to: p(-22, -12.5))
        path.addQuadCurve(to: p(-17, -16), control: p(-21.5, -15.5))
        path.addLine(to: p(-11.5, -16.5))
        path.addLine(to: p(-6.5, -23))
        path.addQuadCurve(to: p(-0.5, -24.5), control: p(-4.5, -24.5))
        path.addLine(to: p(3.5, -24.5))
        path.addQuadCurve(to: p(10.5, -17.5), control: p(6.5, -24))
        path.addLine(to: p(17.5, -16))
        path.addQuadCurve(to: p(22.5, -10.5), control: p(22, -15))
        path.addLine(to: p(22.5, -6))
        path.addQuadCurve(to: p(20, -4.5), control: p(22, -4.5))
        path.addLine(to: p(-20, -4.5))
        path.addQuadCurve(to: p(-22, -6), control: p(-22, -4.5))
        path.closeSubpath()
        return path
    }

    private static func driveCar(_ ctx: inout GraphicsContext, cx: CGFloat, base: CGFloat, scene s: FinDriveScene,
                                 ink: DriveInk) {
        let body = driveCarPath(cx: cx, base: base)
        ctx.fill(body, with: driveBodyShading(s, top: base - 25, bottom: base - 4))
        let zone = CGRect(x: cx - 22.5, y: base - 26, width: 45, height: 22)
        driveOwedHatch(&ctx, body: body, zone: zone, scene: s, ink: ink)
        ctx.stroke(body, with: .color(ink.carStroke), lineWidth: 1)
        var glass = Path()
        glass.move(to: CGPoint(x: cx - 10.3, y: base - 17.2))
        glass.addLine(to: CGPoint(x: cx - 6, y: base - 22.6))
        glass.addLine(to: CGPoint(x: cx + 2.8, y: base - 22.6))
        glass.addLine(to: CGPoint(x: cx + 7.8, y: base - 17.6))
        glass.closeSubpath()
        ctx.fill(glass, with: .color(ink.window))
        ctx.fill(Path(CGRect(x: cx - 1.4, y: base - 23, width: 1.6, height: 6)), with: .color(Color(tb: s.bodyBottom)))
        ctx.fill(Path(CGRect(x: cx - 1.2, y: base - 16.5, width: 0.8, height: 10)), with: .color(DriveInk.seam))
        ctx.fill(Path(CGRect(x: cx + 19.5, y: base - 13.5, width: 3, height: 2.2)), with: .color(ink.headlight))
        ctx.fill(Path(CGRect(x: cx - 22, y: base - 13, width: 2.2, height: 2)), with: .color(DriveInk.tail))
        driveWheel(&ctx, x: cx - 13, base: base, radius: 5)
        driveWheel(&ctx, x: cx + 13, base: base, radius: 5)
        driveBadge(&ctx, s.badge, x: cx - 7.5, y: base - 10.8, size: 7.5)
    }

    /// 側面速克達（車頭朝右）：後面一塊車殼蓋住後輪上緣、中間低的踏板、前面擋泥的龍頭
    private static func driveScooterPath(cx: CGFloat, base: CGFloat) -> Path {
        func p(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: cx + dx, y: base + dy) }
        var path = Path()
        path.move(to: p(-15.5, -8))
        path.addQuadCurve(to: p(-13.5, -14.5), control: p(-16.5, -12.5))
        path.addLine(to: p(-3, -15))
        path.addQuadCurve(to: p(-0.5, -11), control: p(-1, -14.5))
        path.addLine(to: p(4.5, -10.5))
        path.addLine(to: p(7, -19.5))
        path.addQuadCurve(to: p(10.5, -21.5), control: p(8, -21.8))
        path.addQuadCurve(to: p(14.5, -10.5), control: p(14, -17.5))
        path.addLine(to: p(14, -8.5))
        path.addQuadCurve(to: p(12, -9.2), control: p(13, -9.5))
        path.addLine(to: p(5.5, -7))
        path.addLine(to: p(-5, -7))
        path.addQuadCurve(to: p(-15.5, -8), control: p(-12, -8.8))
        path.closeSubpath()
        return path
    }

    private static func driveScooter(_ ctx: inout GraphicsContext, cx: CGFloat, base: CGFloat, scene s: FinDriveScene,
                                     ink: DriveInk) {
        var bar = Path()
        bar.move(to: CGPoint(x: cx + 9.5, y: base - 20.5))
        bar.addLine(to: CGPoint(x: cx + 8, y: base - 24.5))
        bar.move(to: CGPoint(x: cx + 5.5, y: base - 24.8))
        bar.addLine(to: CGPoint(x: cx + 10.5, y: base - 24.8))
        ctx.stroke(bar, with: .color(ink.handle), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        let body = driveScooterPath(cx: cx, base: base)
        ctx.fill(body, with: driveBodyShading(s, top: base - 22, bottom: base - 7))
        let zone = CGRect(x: cx - 16.5, y: base - 22.5, width: 32, height: 16)
        driveOwedHatch(&ctx, body: body, zone: zone, scene: s, ink: ink)
        ctx.stroke(body, with: .color(ink.carStroke), lineWidth: 1)
        ctx.fill(Path(roundedRect: CGRect(x: cx - 13.5, y: base - 17.6, width: 11, height: 3), cornerRadius: 1.5),
                 with: .color(ink.handle))
        ctx.fill(Path(ellipseIn: CGRect(x: cx + 11.3, y: base - 18.6, width: 2.6, height: 2.2)), with: .color(ink.headlight))
        ctx.fill(Path(CGRect(x: cx - 16, y: base - 12.2, width: 1.8, height: 2)), with: .color(DriveInk.tail))
        driveWheel(&ctx, x: cx - 10, base: base, radius: 4.5)
        driveWheel(&ctx, x: cx + 11, base: base, radius: 4.5)
        driveBadge(&ctx, s.badge, x: cx - 8, y: base - 11.2, size: 6)
    }

    /// 輪子：深色胎＋淺色輪轂
    private static func driveWheel(_ ctx: inout GraphicsContext, x: CGFloat, base: CGFloat, radius r: CGFloat) {
        ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: base - r * 2, width: r * 2, height: r * 2)), with: .color(DriveInk.tire))
        let h = r * 0.44
        ctx.fill(Path(ellipseIn: CGRect(x: x - h, y: base - r - h, width: h * 2, height: h * 2)), with: .color(DriveInk.hub))
    }

    /// 車門上的小徽章：電車、電動機車小閃電；油電小插頭（中心 (x, y)，高 size）
    private static func driveBadge(_ ctx: inout GraphicsContext, _ badge: FinDriveScene.Badge, x: CGFloat, y: CGFloat,
                                   size: CGFloat) {
        let white = Color.white.opacity(0.95)
        let k = size / 10
        switch badge {
        case .none:
            return
        case .bolt:
            var bolt = Path()
            bolt.move(to: CGPoint(x: x + 1 * k, y: y - 5 * k))
            bolt.addLine(to: CGPoint(x: x - 3 * k, y: y + 0.8 * k))
            bolt.addLine(to: CGPoint(x: x - 0.2 * k, y: y + 0.8 * k))
            bolt.addLine(to: CGPoint(x: x - 1 * k, y: y + 5 * k))
            bolt.addLine(to: CGPoint(x: x + 3 * k, y: y - 0.8 * k))
            bolt.addLine(to: CGPoint(x: x + 0.2 * k, y: y - 0.8 * k))
            bolt.closeSubpath()
            ctx.fill(bolt, with: .color(white))
        case .plug:
            let plug = CGRect(x: x - 3.3 * k, y: y - 2.9 * k, width: 6.7 * k, height: 6 * k)
            ctx.fill(Path(roundedRect: plug, cornerRadius: 1.3 * k), with: .color(white))
            ctx.fill(Path(CGRect(x: x - 2.3 * k, y: y - 5.6 * k, width: 1.2 * k, height: 2.7 * k)), with: .color(white))
            ctx.fill(Path(CGRect(x: x + 1.1 * k, y: y - 5.6 * k, width: 1.2 * k, height: 2.7 * k)), with: .color(white))
        }
    }
}
