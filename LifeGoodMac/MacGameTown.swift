// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.648 mac7 G3] 記帳小鎮第三批：小鎮畫面（judge_mac.md §U5-1、§U5-2）。只畫、不算新規則、不存任何東西。
//
// • MacGameTownPlan.make 是純函式（level＝snapshot.level、lights＝snapshot.lights）；sim 編號 game#50～#54。
// • 全 LifeGoodMac 第三個 Canvas：只 fill／stroke 形狀；不准 ctx.resolve(、ctx.draw(（不畫字）、TimelineView、動畫。
// • 沒有金額、名字；沒有紅、粉；外層 .accessibilityElement(children: .ignore)、.allowsHitTesting(false)。
// • 主控骨架（C0）：型別與簽名定案（§U7-6）；make 回空 pieces、畫面 Color.clear、兩個放置處 EmptyView()。G3 換內容。
// • [G3] 位置表（MacGameTownLayout）是固定的字面值：sim_mac7 town7 逐個數字讀這張表跟 python 那份比（改一個數字兩邊都要改）。
//   座標 0…1（x 從左、y 從上）；地面從 y＝0.80 開始；建築底一律站在 0.80；窗戶的位置避開前排的樹（樹頂 0.76）與前面的房子。

import SwiftUI

/// 小鎮的一塊（座標、大小都是 0…1 的比例）
struct MacGameTownPiece: Equatable {
    let kind: MacGameTownKind
    let x: Double
    let y: Double
    let w: Double
    let h: Double
    let lit: Bool
}

enum MacGameTownKind: Equatable {
    case lot, sapling, house, garden, tree, shop, alley, stall, hall, river, boat, tower, sparkle, window
}

/// 照等級蓋的小鎮（只升不降；這週的燈 → 亮窗、樹）
struct MacGameTownPlan: Equatable {
    let level: Int
    let pieces: [MacGameTownPiece]
    /// 本週 .lamp＋.checked 的數量（≤ 7）
    let lamps: Int
    /// 本週 .leaf＋.checked 的數量（≤ 7）
    let trees: Int

    // sim7: game#50～#54（G3 換內容）
    static func make(level: Int, lights: [MacGameLight]) -> MacGameTownPlan {
        let lv = max(0, level)
        // sim7: game#50（亮窗＝記帳日＝金燈＋打勾的葉子；樹＝沒花錢的日子＝葉子＋打勾的葉子；都 ≤ 7）
        let lamps = min(7, lights.filter { l in l == .lamp || l == .checked }.count)
        let trees = min(7, lights.filter { l in l == .leaf || l == .checked }.count)
        // sim7: game#51（照等級累加：Lv0 三塊空地＋小苗；Lv1 起拿掉第一塊空地（蓋成小屋）；Lv.n 一定包含 Lv.n−1 的全部（n ≥ 2））
        var spots: [MacGameTownSpot] = lv >= 1 ? Array(MacGameTownLayout.lots.dropFirst()) : MacGameTownLayout.lots
        spots.append(MacGameTownLayout.sapling)
        for (i, tier) in MacGameTownLayout.tiers.enumerated() where lv >= i + 1 {
            spots += tier
        }
        // sim7: game#53（樹：地面前排固定 7 個位置，前 trees 個種樹）
        spots += MacGameTownLayout.trees.prefix(trees)
        // Lv.9 起一顆小星星、每多一級多一顆（最多 12 顆）
        spots += MacGameTownLayout.sparkles.prefix(max(0, lv - 8))
        // sim7: game#52（窗戶照表上的順序編號；前 min(lamps, 窗戶總數) 扇亮，其餘暗）
        var pieces: [MacGameTownPiece] = []
        var n = 0
        for s in spots {
            var lit = false
            if s.kind == .window {
                lit = n < lamps
                n += 1
            }
            pieces.append(MacGameTownPiece(kind: s.kind, x: s.x, y: s.y, w: s.w, h: s.h, lit: lit))
        }
        // sim7: game#54（座標都在 0…1、w、h > 0；同一個 level＋lights 結果逐位一樣 → 畫面 .equatable() 不重畫）
        return MacGameTownPlan(level: lv, pieces: pieces, lamps: lamps, trees: trees)
    }
}

/// 位置表的一格（lit 由 make 算）
private struct MacGameTownSpot {
    let kind: MacGameTownKind
    let x: Double
    let y: Double
    let w: Double
    let h: Double

    init(_ kind: MacGameTownKind, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        self.kind = kind
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

/// 固定位置（sim_mac7 town7 逐個讀；順序就是窗戶的編號順序）
private enum MacGameTownLayout {
    /// Lv0：三塊空地（站在地平線上；之後被小屋、小店、小巷蓋住）
    static let lots: [MacGameTownSpot] = [
        MacGameTownSpot(.lot, 0.035, 0.72, 0.09, 0.08),
        MacGameTownSpot(.lot, 0.30, 0.72, 0.09, 0.08),
        MacGameTownSpot(.lot, 0.42, 0.72, 0.115, 0.08),
    ]
    static let sapling = MacGameTownSpot(.sapling, 0.165, 0.70, 0.03, 0.10)
    /// Lv1 小屋（2 窗）
    static let house: [MacGameTownSpot] = [
        MacGameTownSpot(.house, 0.03, 0.44, 0.10, 0.36),
        MacGameTownSpot(.window, 0.045, 0.62, 0.022, 0.07),
        MacGameTownSpot(.window, 0.093, 0.62, 0.022, 0.07),
    ]
    /// Lv2 菜園三排＋一棵樹
    static let garden: [MacGameTownSpot] = [
        MacGameTownSpot(.garden, 0.14, 0.82, 0.10, 0.022),
        MacGameTownSpot(.garden, 0.14, 0.86, 0.10, 0.022),
        MacGameTownSpot(.garden, 0.14, 0.90, 0.10, 0.022),
        MacGameTownSpot(.tree, 0.245, 0.56, 0.035, 0.24),
    ]
    /// Lv3 街角小店（2 窗、遮雨棚）
    static let shop: [MacGameTownSpot] = [
        MacGameTownSpot(.shop, 0.29, 0.48, 0.11, 0.32),
        MacGameTownSpot(.window, 0.303, 0.65, 0.022, 0.07),
        MacGameTownSpot(.window, 0.365, 0.65, 0.022, 0.07),
    ]
    /// Lv4 小巷兩棟（4 窗）
    static let alley: [MacGameTownSpot] = [
        MacGameTownSpot(.alley, 0.41, 0.40, 0.07, 0.40),
        MacGameTownSpot(.alley, 0.48, 0.46, 0.07, 0.34),
        MacGameTownSpot(.window, 0.434, 0.50, 0.022, 0.07),
        MacGameTownSpot(.window, 0.434, 0.63, 0.022, 0.07),
        MacGameTownSpot(.window, 0.504, 0.56, 0.022, 0.07),
        MacGameTownSpot(.window, 0.504, 0.67, 0.022, 0.07),
    ]
    /// Lv5 市集兩攤
    static let stalls: [MacGameTownSpot] = [
        MacGameTownSpot(.stall, 0.56, 0.64, 0.06, 0.16),
        MacGameTownSpot(.stall, 0.625, 0.64, 0.06, 0.16),
    ]
    /// Lv6 鎮公所（2 窗＋旗）
    static let hall: [MacGameTownSpot] = [
        MacGameTownSpot(.hall, 0.69, 0.30, 0.13, 0.50),
        MacGameTownSpot(.window, 0.712, 0.60, 0.022, 0.07),
        MacGameTownSpot(.window, 0.776, 0.60, 0.022, 0.07),
    ]
    /// Lv7 河道＋一艘小船
    static let river: [MacGameTownSpot] = [
        MacGameTownSpot(.river, 0.83, 0.80, 0.17, 0.20),
        MacGameTownSpot(.boat, 0.88, 0.86, 0.07, 0.06),
    ]
    /// Lv8 後排兩棟高樓（6 窗；窗戶都在市集棚子上面）
    static let towers: [MacGameTownSpot] = [
        MacGameTownSpot(.tower, 0.56, 0.14, 0.055, 0.66),
        MacGameTownSpot(.tower, 0.625, 0.20, 0.055, 0.60),
        MacGameTownSpot(.window, 0.577, 0.22, 0.022, 0.07),
        MacGameTownSpot(.window, 0.577, 0.34, 0.022, 0.07),
        MacGameTownSpot(.window, 0.577, 0.46, 0.022, 0.07),
        MacGameTownSpot(.window, 0.642, 0.28, 0.022, 0.07),
        MacGameTownSpot(.window, 0.642, 0.40, 0.022, 0.07),
        MacGameTownSpot(.window, 0.642, 0.52, 0.022, 0.07),
    ]
    /// Lv9 天際線三棟（6 窗；窗戶都在前面房子的屋頂上面）
    static let skyline: [MacGameTownSpot] = [
        MacGameTownSpot(.tower, 0.05, 0.10, 0.06, 0.70),
        MacGameTownSpot(.tower, 0.15, 0.18, 0.05, 0.62),
        MacGameTownSpot(.tower, 0.86, 0.12, 0.06, 0.68),
        MacGameTownSpot(.window, 0.069, 0.16, 0.022, 0.07),
        MacGameTownSpot(.window, 0.069, 0.28, 0.022, 0.07),
        MacGameTownSpot(.window, 0.164, 0.24, 0.022, 0.07),
        MacGameTownSpot(.window, 0.164, 0.34, 0.022, 0.07),
        MacGameTownSpot(.window, 0.879, 0.20, 0.022, 0.07),
        MacGameTownSpot(.window, 0.879, 0.32, 0.022, 0.07),
    ]
    /// Lv1～Lv9 依序（第 i 個＝Lv.(i＋1) 起有）
    static let tiers: [[MacGameTownSpot]] = [house, garden, shop, alley, stalls, hall, river, towers, skyline]
    /// 地面前排 7 個種樹的位置（種的順序）
    static let trees: [MacGameTownSpot] = [
        MacGameTownSpot(.tree, 0.005, 0.76, 0.035, 0.18),
        MacGameTownSpot(.tree, 0.135, 0.76, 0.035, 0.18),
        MacGameTownSpot(.tree, 0.255, 0.76, 0.035, 0.18),
        MacGameTownSpot(.tree, 0.40, 0.76, 0.035, 0.18),
        MacGameTownSpot(.tree, 0.545, 0.76, 0.035, 0.18),
        MacGameTownSpot(.tree, 0.685, 0.76, 0.035, 0.18),
        MacGameTownSpot(.tree, 0.79, 0.76, 0.035, 0.18),
    ]
    /// 天上 12 顆小星星的位置（避開高樓的頂）
    static let sparkles: [MacGameTownSpot] = [
        MacGameTownSpot(.sparkle, 0.23, 0.10, 0.02, 0.07),
        MacGameTownSpot(.sparkle, 0.31, 0.20, 0.02, 0.07),
        MacGameTownSpot(.sparkle, 0.38, 0.08, 0.02, 0.07),
        MacGameTownSpot(.sparkle, 0.45, 0.18, 0.02, 0.07),
        MacGameTownSpot(.sparkle, 0.51, 0.06, 0.02, 0.07),
        MacGameTownSpot(.sparkle, 0.73, 0.12, 0.02, 0.07),
        MacGameTownSpot(.sparkle, 0.79, 0.22, 0.02, 0.07),
        MacGameTownSpot(.sparkle, 0.95, 0.06, 0.02, 0.07),
        MacGameTownSpot(.sparkle, 0.27, 0.30, 0.02, 0.07),
        MacGameTownSpot(.sparkle, 0.48, 0.28, 0.02, 0.07),
        MacGameTownSpot(.sparkle, 0.75, 0.03, 0.02, 0.07),
        MacGameTownSpot(.sparkle, 0.83, 0.30, 0.02, 0.07),
    ]
}

/// 小鎮圖（View＋Equatable：plan 一樣不重畫）
struct MacGameTownView: View, Equatable {
    let plan: MacGameTownPlan
    let dark: Bool

    /// VoiceOver 唸的一句（景名；沒有數字）
    private var label: String {
        "記帳小鎮：" + MacGameRules.stage(plan.level).name
    }

    var body: some View {
        Canvas { ctx, size in
            MacGameTownArt.paint(&ctx, rect: CGRect(origin: .zero, size: size), plan: plan, dark: dark)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .allowsHitTesting(false)
    }
}

/// 小鎮的色票（淺、深兩套；沒有紅、粉）
private struct MacGameTownInk {
    let dark: Bool

    var skyTop: Color { dark ? MacTheme.hex(0x0A1433) : MacTheme.hex(0xDDF0FF) }
    var skyBottom: Color { dark ? MacTheme.hex(0x18264E) : MacTheme.hex(0xF4F8FD) }
    var ground: Color { dark ? MacTheme.hex(0x1E3A33) : MacTheme.hex(0xCFE8D6) }
    var wall: Color { dark ? MacTheme.hex(0x2A3A66) : Color.white }
    var wallShade: Color { dark ? MacTheme.hex(0x22305A) : MacTheme.hex(0xE3ECF8) }
    /// 後排高樓（比牆淡一點）
    var tower: Color { dark ? MacTheme.hex(0x22305A) : MacTheme.hex(0xC9D6EE) }
    var roofTeal: Color { MacTheme.hex(0x1A9E94) }
    var roofBlue: Color { MacTheme.hex(0x3887FA) }
    var roofGold: Color { MacTheme.hex(0xC98A00) }
    var roofGray: Color { MacTheme.hex(0x5E6478) }
    /// 樹＝MacTone.good 的值
    var tree: Color { dark ? MacTheme.hex(0x5BD99A) : MacTheme.hex(0x177A44) }
    var garden: Color { tree.opacity(0.55) }
    /// 亮窗＝MacGameTint.star 的值
    var windowLit: Color { dark ? MacTheme.hex(0xFFD45E) : MacTheme.hex(0xC98A00) }
    var windowDark: Color { dark ? MacTheme.hex(0x3A4A7A) : MacTheme.hex(0xB9C7EE, 0.6) }
    var river: Color { MacTheme.hex(0x7FB8FF, 0.6) }
    var sparkle: Color { MacTheme.hex(0xFFE29A) }
    var lot: Color { roofGray.opacity(0.6) }
}

enum MacGameTownArt {
    /// 畫的順序：後排 → 前排（窗戶、小星星最後）
    private static let layers: [[MacGameTownKind]] = [[.tower], [.river], [.lot], [.garden], [.house, .shop, .alley, .stall, .hall],
                                                      [.tree, .sapling], [.boat], [.window], [.sparkle]]
    /// 地面從這裡開始（0…1）
    private static let groundTop: CGFloat = 0.80

    /// 只 fill／stroke 形狀，不畫字
    static func paint(_ ctx: inout GraphicsContext, rect: CGRect, plan: MacGameTownPlan, dark: Bool) {
        let r = rect
        guard r.width > 0, r.height > 0 else { return }
        let ink = MacGameTownInk(dark: dark)
        ctx.fill(Path(r), with: .linearGradient(Gradient(colors: [ink.skyTop, ink.skyBottom]), startPoint: CGPoint(x: r.minX, y: r.minY),
                                              endPoint: CGPoint(x: r.minX, y: r.maxY)))
        let g = r.height * groundTop
        ctx.fill(Path(CGRect(x: r.minX, y: r.minY + g, width: r.width, height: r.height - g)), with: .color(ink.ground))
        for layer in layers {
            for p in plan.pieces where layer.contains(p.kind) {
                drawPiece(&ctx, p, in: frame(p, in: r), ink: ink)
            }
        }
    }

    private static func frame(_ p: MacGameTownPiece, in r: CGRect) -> CGRect {
        CGRect(x: r.minX + r.width * CGFloat(p.x), y: r.minY + r.height * CGFloat(p.y),
               width: r.width * CGFloat(p.w), height: r.height * CGFloat(p.h))
    }

    private static func drawPiece(_ ctx: inout GraphicsContext, _ p: MacGameTownPiece, in f: CGRect, ink: MacGameTownInk) {
        switch p.kind {
        case .lot:
            ctx.stroke(Path(roundedRect: f, cornerRadius: 2), with: .color(ink.lot), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        case .sapling:
            drawPlant(&ctx, f, crown: 0.55, ink: ink)
        case .tree:
            drawPlant(&ctx, f, crown: 0.7, ink: ink)
        case .garden:
            ctx.fill(Path(roundedRect: f, cornerRadius: f.height / 2), with: .color(ink.garden))
        case .house:
            drawHouse(&ctx, f, ink: ink)
        case .shop:
            drawShop(&ctx, f, ink: ink)
        case .alley:
            drawWall(&ctx, f, ink: ink)
            drawBand(&ctx, f, color: ink.roofBlue)
        case .tower:
            ctx.fill(Path(f), with: .color(ink.tower))
            drawBand(&ctx, f, color: ink.roofGray)
        case .stall:
            drawStall(&ctx, f, canopy: p.x < 0.6 ? ink.roofTeal : ink.roofGold, ink: ink)
        case .hall:
            drawHall(&ctx, f, ink: ink)
        case .river:
            ctx.fill(Path(roundedRect: f, cornerRadius: min(f.width, f.height) * 0.3), with: .color(ink.river))
        case .boat:
            drawBoat(&ctx, f, ink: ink)
        case .window:
            ctx.fill(Path(roundedRect: f, cornerRadius: 1), with: .color(p.lit ? ink.windowLit : ink.windowDark))
        case .sparkle:
            ctx.fill(sparklePath(center: CGPoint(x: f.midX, y: f.midY), radius: min(f.width, f.height) / 2), with: .color(ink.sparkle))
        }
    }

    /// 樹、小苗：上面圓的樹冠、下面樹幹
    private static func drawPlant(_ ctx: inout GraphicsContext, _ f: CGRect, crown: CGFloat, ink: MacGameTownInk) {
        let trunkW: CGFloat = max(1, f.width * 0.18)
        let trunkTop: CGFloat = f.minY + f.height * crown * 0.8
        ctx.fill(Path(CGRect(x: f.midX - trunkW / 2, y: trunkTop, width: trunkW, height: f.maxY - trunkTop)), with: .color(ink.roofGray))
        ctx.fill(Path(ellipseIn: CGRect(x: f.minX, y: f.minY, width: f.width, height: f.height * crown)), with: .color(ink.tree))
    }

    /// 牆＋右邊一條影子
    private static func drawWall(_ ctx: inout GraphicsContext, _ r: CGRect, ink: MacGameTownInk) {
        ctx.fill(Path(r), with: .color(ink.wall))
        ctx.fill(Path(CGRect(x: r.maxX - r.width * 0.25, y: r.minY, width: r.width * 0.25, height: r.height)), with: .color(ink.wallShade))
    }

    /// 平屋頂一條
    private static func drawBand(_ ctx: inout GraphicsContext, _ f: CGRect, color: Color) {
        ctx.fill(Path(CGRect(x: f.minX, y: f.minY, width: f.width, height: max(1.5, f.height * 0.06))), with: .color(color))
    }

    /// 門（牆的下緣正中間）
    private static func drawDoor(_ ctx: inout GraphicsContext, _ body: CGRect, ink: MacGameTownInk) {
        let w: CGFloat = body.width * 0.22
        let h: CGFloat = body.height * 0.4
        ctx.fill(Path(roundedRect: CGRect(x: body.midX - w / 2, y: body.maxY - h, width: w, height: h), cornerRadius: 1),
                 with: .color(ink.roofGray))
    }

    /// 小屋：斜屋頂（青）＋牆＋門
    private static func drawHouse(_ ctx: inout GraphicsContext, _ f: CGRect, ink: MacGameTownInk) {
        let roofH: CGFloat = f.height * 0.35
        let body = CGRect(x: f.minX, y: f.minY + roofH, width: f.width, height: f.height - roofH)
        drawWall(&ctx, body, ink: ink)
        var roof = Path()
        roof.move(to: CGPoint(x: f.minX - f.width * 0.06, y: body.minY))
        roof.addLine(to: CGPoint(x: f.midX, y: f.minY))
        roof.addLine(to: CGPoint(x: f.maxX + f.width * 0.06, y: body.minY))
        roof.closeSubpath()
        ctx.fill(roof, with: .color(ink.roofTeal))
        drawDoor(&ctx, body, ink: ink)
    }

    /// 街角小店：平屋頂（金）＋藍色遮雨棚＋門
    private static func drawShop(_ ctx: inout GraphicsContext, _ f: CGRect, ink: MacGameTownInk) {
        let body = CGRect(x: f.minX, y: f.minY + f.height * 0.14, width: f.width, height: f.height * 0.86)
        drawWall(&ctx, body, ink: ink)
        ctx.fill(Path(CGRect(x: f.minX - f.width * 0.04, y: f.minY, width: f.width * 1.08, height: f.height * 0.14)),
                 with: .color(ink.roofGold))
        let aw: CGFloat = f.width * 1.04 / 5
        for i in 0..<5 {
            let stripe = CGRect(x: f.minX - f.width * 0.02 + aw * CGFloat(i), y: f.minY + f.height * 0.36, width: aw, height: f.height * 0.12)
            ctx.fill(Path(stripe), with: .color(i % 2 == 0 ? ink.roofBlue : ink.wallShade))
        }
        drawDoor(&ctx, body, ink: ink)
    }

    /// 市集一攤：兩根柱子、棚子、檯子
    private static func drawStall(_ ctx: inout GraphicsContext, _ f: CGRect, canopy: Color, ink: MacGameTownInk) {
        let pole: CGFloat = max(1, f.width * 0.06)
        ctx.fill(Path(CGRect(x: f.minX + f.width * 0.08, y: f.minY, width: pole, height: f.height)), with: .color(ink.roofGray))
        ctx.fill(Path(CGRect(x: f.maxX - f.width * 0.08 - pole, y: f.minY, width: pole, height: f.height)), with: .color(ink.roofGray))
        ctx.fill(Path(CGRect(x: f.minX, y: f.minY + f.height * 0.55, width: f.width, height: f.height * 0.45)), with: .color(ink.wall))
        var top = Path()
        top.move(to: CGPoint(x: f.minX - f.width * 0.05, y: f.minY + f.height * 0.38))
        top.addLine(to: CGPoint(x: f.minX + f.width * 0.15, y: f.minY))
        top.addLine(to: CGPoint(x: f.maxX - f.width * 0.15, y: f.minY))
        top.addLine(to: CGPoint(x: f.maxX + f.width * 0.05, y: f.minY + f.height * 0.38))
        top.closeSubpath()
        ctx.fill(top, with: .color(canopy))
    }

    /// 鎮公所：旗桿＋旗（青）、山牆（灰藍）、牆、門
    private static func drawHall(_ ctx: inout GraphicsContext, _ f: CGRect, ink: MacGameTownInk) {
        let body = CGRect(x: f.minX, y: f.minY + f.height * 0.44, width: f.width, height: f.height * 0.56)
        drawWall(&ctx, body, ink: ink)
        var roof = Path()
        roof.move(to: CGPoint(x: f.minX - f.width * 0.04, y: body.minY))
        roof.addLine(to: CGPoint(x: f.midX, y: f.minY + f.height * 0.30))
        roof.addLine(to: CGPoint(x: f.maxX + f.width * 0.04, y: body.minY))
        roof.closeSubpath()
        ctx.fill(roof, with: .color(ink.roofGray))
        let pole: CGFloat = max(1, f.width * 0.02)
        ctx.fill(Path(CGRect(x: f.midX - pole / 2, y: f.minY, width: pole, height: f.height * 0.30)), with: .color(ink.roofGray))
        ctx.fill(Path(CGRect(x: f.midX + pole / 2, y: f.minY, width: f.width * 0.22, height: f.height * 0.11)), with: .color(ink.roofTeal))
        drawDoor(&ctx, body, ink: ink)
    }

    /// 小船：船身（金）＋帆（牆色）
    private static func drawBoat(_ ctx: inout GraphicsContext, _ f: CGRect, ink: MacGameTownInk) {
        var hull = Path()
        hull.move(to: CGPoint(x: f.minX, y: f.midY))
        hull.addLine(to: CGPoint(x: f.maxX, y: f.midY))
        hull.addLine(to: CGPoint(x: f.maxX - f.width * 0.2, y: f.maxY))
        hull.addLine(to: CGPoint(x: f.minX + f.width * 0.2, y: f.maxY))
        hull.closeSubpath()
        ctx.fill(hull, with: .color(ink.roofGold))
        var sail = Path()
        sail.move(to: CGPoint(x: f.midX, y: f.minY - f.height * 0.6))
        sail.addLine(to: CGPoint(x: f.midX, y: f.midY))
        sail.addLine(to: CGPoint(x: f.maxX - f.width * 0.12, y: f.midY))
        sail.closeSubpath()
        ctx.fill(sail, with: .color(ink.wall))
    }

    /// 四個尖的小星星（8 點：外徑 radius、內徑 0.32 × radius，尖朝上）
    private static func sparklePath(center c: CGPoint, radius: CGFloat) -> Path {
        var p = Path()
        for k in 0..<8 {
            let rr: CGFloat = k % 2 == 0 ? radius : radius * 0.32
            let angle: Double = -Double.pi / 2 + Double(k) * Double.pi / 4
            let pt = CGPoint(x: c.x + rr * CGFloat(cos(angle)), y: c.y + rr * CGFloat(sin(angle)))
            if k == 0 {
                p.move(to: pt)
            } else {
                p.addLine(to: pt)
            }
        }
        p.closeSubpath()
        return p
    }
}

/// 徽章 popover 最上面那張（高 120）
struct MacGameTownBanner: View {
    let snap: MacGameSnapshot
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        MacGameTownView(plan: MacGameTownPlan.make(level: snap.level, lights: snap.lights), dark: scheme == .dark)
            .equatable()
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .help(MacGameText.townHelp)
    }
}

/// 遊戲列第一行那張小的（理想寬 150、高 32；窄視窗自己縮）
struct MacGameTownStrip: View {
    let snap: MacGameSnapshot
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        MacGameTownView(plan: MacGameTownPlan.make(level: snap.level, lights: snap.lights), dark: scheme == .dark)
            .equatable()
            .frame(minWidth: 0, idealWidth: 150, maxWidth: 150)
            .frame(height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
