import SwiftUI

// MARK: - 房屋卡片看板的風景：這一間的剖面（v25.534）
//
// [v25.534] 使用者選了「剖面版」（看板直接畫這一間，不先用街景）：
//   透天   拿掉前牆，一層一層看得到房間：照 FloorInfo.functions 畫家具小圖（樣稿 hcard.js roomIcon），
//          一層有幾個用途就橫向平分，沒填用途的層只畫窗。B1 在地面線以下（把馬路剖開一塊），
//          RF 是屋頂裡那一間；有電梯就在右邊畫一條電梯井；每層右邊一塊小樓層牌。
//   大樓   灰藍色高樓，你那幾層塗紫色、右邊掛「12F」牌。樓太高就把別人的樓層壓扁，你那幾層至少 14pt 高。
//   斜線   還欠銀行的那一截：從地面（大樓是你那幾層的地板）往上，高度＝owedFraction；
//          頂端一條紅虛線、左邊掛「房貸 62%」；上面沒斜線的是你的。
//   狀態   房貸還沒開始＝虛線外框、沒有斜線；出租中＝左邊插綠色「出租中」牌；
//          已售＝整棟 45% 透明＋名牌「已售・<名字>」（賣掉時房貸結清，不畫斜線）；空房子＝一層的透天＋名牌。
// 規矩跟其他看板風景一樣：數字在頭部的 Text 裡（VoiceOver 唸那邊），這裡的牌子只是裝飾。
// 所有東西都畫在 band（rect）裡：band 上面緊接著那一句話，MoneyBoardSky 不會替風景讓字。

/// 剖面房子的一層（由下往上排好：地下室在最前面）
struct HouseSceneFloor: Equatable {
    var label: String            // FloorLabel 的短字：「B1」「1F」「2F」「M」「RF」
    var isBasement: Bool
    var isRoof: Bool
    var rooms: [FloorFunction]   // 這一層的用途（FloorInfo.functions），畫房間小圖
}

struct HouseSceneModel: Equatable {
    enum Shape: Equatable {
        /// 透天／別墅：每層一列；floors 空的時候畫一棟一層的透天
        case house(floors: [HouseSceneFloor], hasElevator: Bool)
        /// 大樓：你的那幾層（地上樓層，1 起算）；totalFloors＝整棟要畫幾層（至少比 ownedHigh 多 2）
        case tower(ownedLow: Int, ownedHigh: Int, totalFloors: Int, label: String)
    }
    var shape: Shape
    /// 白斜線高度比例（0…1）；0＝不畫斜線
    var owedFraction: Double
    /// 斜線頂端的牌子：「房貸 62%」「還要繳 94%」；nil＝不掛
    var owedLabel: String?
    var isRented: Bool           // 門邊插綠色「出租中」牌
    var isSold: Bool             // 整棟 45% 透明＋名牌「已售・<名字>」
    var notStarted: Bool         // 房貸還沒開始：虛線外框、沒有斜線
    var name: String             // 名牌上的房名（已截短）
}

struct FinHouseScene: Equatable {
    var model: HouseSceneModel
}

// MARK: - 畫的時候用的小東西（只在這個檔裡）

/// 剖面房子的顏色，淺／深各一組（照 hcard.js homeCut；深色的紫用 finHome 的亮紫 B79CFF）
private struct HouseCutInk {
    let back: Color          // 背牆
    let basementBack: Color  // 地下室的背牆（暗一點）
    let wall: Color          // 外牆、樓板
    let divider: Color       // 房間隔間
    let cord: Color          // 吊燈線
    let bulb: Color          // 燈泡
    let furniture: Color     // 家具（深）
    let cushion: Color       // 家具（淺：坐墊、床墊）
    let wood: Color
    let window: Color        // 窗（夜裡亮琥珀色）
    let soil: Color          // 地下室旁邊的土
    let roof: Color
    let floorInk: Color      // 樓層牌的字
    let basementInk: Color   // 地下室樓層牌的字（深灰）
    let pillFill: Color      // 樓層牌的底

    init(dark: Bool) {
        back = dark ? Color(tb: 0x2A2350) : Color(tb: 0xF1ECFF)
        basementBack = dark ? Color(tb: 0x221C40) : Color(tb: 0xE6E0F5)
        wall = dark ? Color(tb: 0xB79CFF) : Color(tb: 0x6B4BE0)
        divider = dark ? Color(tb: 0x4A3D86) : Color(tb: 0xD9CCFF)
        cord = dark ? Color(tb: 0xFFD98A) : Color(tb: 0x8A94AE)
        bulb = dark ? Color(tb: 0xFFE7A8) : Color(tb: 0xFFD98A)
        furniture = dark ? Color(tb: 0xC9B8FF) : Color(tb: 0x5A3FC4)
        cushion = dark ? Color(tb: 0x8E7CD8) : Color(tb: 0xB79CFF)
        wood = dark ? Color(tb: 0xB08A6A) : Color(tb: 0xC89B74)
        window = dark ? Color(tb: 0xFFC56B, 0.85) : Color(tb: 0xC4DCF6)
        soil = dark ? Color(tb: 0x241E33) : Color(tb: 0xE4D8C4)
        roof = Color(tb: 0x4B2FB0)
        floorInk = dark ? Color(tb: 0xC9B8FF) : Color(tb: 0x5A3FC4)
        basementInk = dark ? Color(tb: 0xA3B2D9) : Color(tb: 0x5B6478)
        pillFill = dark ? Color(tb: 0x1C2646, 0.88) : Color.white.opacity(0.92)
    }
}

/// 透天剖面的尺寸：一次算好，畫每一塊時都讀這裡
private struct HouseCutGeometry {
    var above: [HouseSceneFloor]     // 地上，由下往上（至少一層）
    var below: [HouseSceneFloor]     // 地下，B1 在最前面（最靠近地面）
    var attic: HouseSceneFloor?      // RF：畫在屋頂裡那一間
    var fh: CGFloat                  // 每層高
    var roofH: CGFloat
    var ground: CGFloat
    var left: CGFloat
    var bw: CGFloat
    var elevator: Bool

    var right: CGFloat { left + bw }
    var cx: CGFloat { left + bw / 2 }
    var bodyH: CGFloat { fh * CGFloat(above.count) }
    var depth: CGFloat { fh * CGFloat(below.count) }
    var bodyTop: CGFloat { ground - bodyH }
    var roofTop: CGFloat { bodyTop - roofH }
    /// 房子（含電梯井）的右緣：樓層牌從這裡往右掛
    var edge: CGFloat { right + (elevator ? 13 : 0) }

    /// 地上第 i 層（0＝最下面那層）的地板；i＝above.count 是天花板
    func floorY(_ i: Int) -> CGFloat { ground - CGFloat(i) * fh }
    /// 地下第 j 層（0＝B1）的天花板；j＝below.count 是最深那層的地板
    func basementTop(_ j: Int) -> CGFloat { ground + CGFloat(j) * fh }
}

/// 大樓的尺寸。樓太高時別人的樓層（fhOther）壓扁、你那幾層（fhMine）保持看得見
private struct HouseTowerGeometry {
    var ground: CGFloat
    var bodyTop: CGFloat
    var cx: CGFloat
    var bw: CGFloat
    var floors: Int
    var low: Int
    var high: Int
    var fhOther: CGFloat
    var fhMine: CGFloat

    var left: CGFloat { cx - bw / 2 }
    var right: CGFloat { cx + bw / 2 }

    /// 第 k 層（1 起算）的地板；k＝floors＋1 是樓頂
    func floorY(_ k: Int) -> CGFloat {
        let below = CGFloat(min(k - 1, low - 1)) * fhOther
        let mine = CGFloat(max(0, min(k - 1, high) - (low - 1))) * fhMine
        let above = CGFloat(max(0, k - 1 - high)) * fhOther
        return ground - below - mine - above
    }

    /// 你那幾層（左右各凸出 3，看起來是塗上去的一塊）
    var unit: CGRect {
        let top = floorY(high + 1)
        let bottom = floorY(low)
        return CGRect(x: left - 3, y: top, width: bw + 6, height: bottom - top)
    }
}

/// 一塊小牌子（先排好位置，最後才畫，才能互相讓開）
private struct HouseScenePill {
    let text: String
    var box: CGRect
    let fill: Color
    let ink: Color
    let size: CGFloat
    let weight: Font.Weight
}

/// 房子四周的牌子：右邊樓層牌、左邊房貸牌與出租牌、頂上名牌
private struct HouseSceneLabels {
    var right: [HouseScenePill] = []
    var left: [HouseScenePill] = []
    var top: HouseScenePill? = nil
    var pole: CGRect? = nil          // 出租牌的桿子
    var rightEdge: CGFloat = 0       // 右邊牌子的最右緣：行道樹從這裡往右種

    /// 左邊佔掉的地方（左邊那棵樹要讓開）
    var leftRects: [CGRect] {
        var out = left.map { $0.box }
        if let p = pole { out.append(p) }
        return out
    }
}

// MARK: - 畫法

extension MoneyBoardSky {
    /// [v25.534] 房屋卡片看板的風景（MoneyBoardSky.paint 分派到這裡；參數形狀跟其他風景一樣）
    static func paintHouse(_ ctx: inout GraphicsContext, rect r: CGRect, scene s: FinHouseScene,
                           dark: Bool, seed: Int) {
        guard r.width > 120, r.height > 60 else { return }
        let m = s.model
        switch m.shape {
        case let .house(floors, hasElevator):
            paintHouseCut(&ctx, rect: r, model: m, floors: floors, elevator: hasElevator, dark: dark, seed: seed)
        case let .tower(ownedLow, ownedHigh, totalFloors, label):
            paintHouseTower(&ctx, rect: r, model: m, low: ownedLow, high: ownedHigh, total: totalFloors,
                            label: label, dark: dark, seed: seed)
        }
    }

    // MARK: 透天剖面

    private static func paintHouseCut(_ ctx: inout GraphicsContext, rect r: CGRect, model m: HouseSceneModel,
                                      floors: [HouseSceneFloor], elevator: Bool, dark: Bool, seed: Int) {
        let w = r.width
        let plate = houseNamePlate(m, emptyHouse: floors.isEmpty)
        let g = houseCutGeometry(floors, elevator: elevator, rect: r, plate: plate != nil)
        let ink = HouseCutInk(dark: dark)
        let roadBottom = min(r.maxY, g.ground + 18)
        houseBackdrop(&ctx, width: w, ground: g.ground, dark: dark, seed: seed)
        houseRoad(&ctx, width: w, ground: g.ground, bottom: roadBottom, dark: dark)
        if roadBottom < r.maxY - 0.5 {
            // 地下室比馬路深：馬路下面露出一條土
            ctx.fill(Path(CGRect(x: 0, y: roadBottom, width: w, height: r.maxY - roadBottom)),
                     with: .color(ink.soil))
        }
        let owes = !m.isSold && !m.notStarted && m.owedFraction > 0
        let fraction = CGFloat(min(1, max(0, m.owedFraction)))
        let owedTop = g.ground - g.bodyH * fraction
        let labels = houseCutLabels(ctx, g: g, model: m, owedTop: owes ? owedTop : nil, plate: plate,
                                    ink: ink, dark: dark, rect: r)
        houseTrees(&ctx, from: labels.rightEdge, leftLimit: g.left - 10, ground: g.ground, width: w,
                   avoid: labels.leftRects, dark: dark)
        var body = ctx
        if m.isSold { body.opacity = 0.45 }
        houseCutBody(&body, g: g, dashed: m.notStarted, ink: ink, roadBottom: roadBottom, dark: dark)
        if owes {
            houseCutOwed(&ctx, g: g, top: owedTop, dark: dark)
        }
        houseDrawLabels(&ctx, labels, dark: dark)
    }

    /// 尺寸：band 固定（看板傳 132），層數多就把每層壓矮（最高 28）；地下室比馬路深時地面往上提
    private static func houseCutGeometry(_ floors: [HouseSceneFloor], elevator: Bool, rect r: CGRect,
                                         plate: Bool) -> HouseCutGeometry {
        var above = floors.filter { !$0.isBasement && !$0.isRoof }
        if above.isEmpty {
            // 空房子（或只填了 B1／RF）：畫一棟一層的透天，不掛樓層牌
            above = [HouseSceneFloor(label: "", isBasement: false, isRoof: false, rooms: [])]
        }
        let below = Array(floors.filter { $0.isBasement }.reversed())
        let roofs = floors.filter { $0.isRoof && !$0.isBasement }
        var attic: HouseSceneFloor? = nil
        if let first = roofs.first {
            let label = first.label.isEmpty ? "RF" : first.label
            attic = HouseSceneFloor(label: label, isBasement: false, isRoof: true, rooms: roofs.flatMap { $0.rooms })
        }
        let nA = CGFloat(above.count)
        let nB = CGFloat(below.count)
        let baseRoof: CGFloat = above.count <= 3 ? 24 : (above.count <= 5 ? 20 : 16)
        // 有 RF 時屋頂要高一點才放得下那一間；層數多時讓給樓層
        let roofH: CGFloat = attic == nil ? baseRoof : max(baseRoof, above.count <= 5 ? 22 : 18)
        let topPad: CGFloat = plate ? 20 : 6
        let roadH: CGFloat = 18
        let room = r.height - topPad - roofH
        var fh = (room - roadH) / nA
        if nB > 0 {
            fh = min(fh, (room - 2) / (nA + nB))
        }
        // 取到 0.5pt；層數多到每層不到 1pt（樓層打成一長串）時照算出來的高度，不夾回 1，
        // 不然整棟會長出 band、蓋到上面那一句話
        fh = fh >= 1 ? min(28, max(1, (fh * 2).rounded(.down) / 2)) : max(0.1, fh)
        let ground = r.maxY - max(roadH, nB > 0 ? nB * fh + 2 : 0)
        // 一兩層的房子窄一點，不然看起來是扁的
        var bw = min(150, max(96, r.width * 0.4))
        if above.count == 1 {
            bw *= 0.75
        } else if above.count == 2 {
            bw *= 0.9
        }
        bw = bw.rounded()
        // 左邊至少留 64：房貸牌、出租牌掛在那裡
        let left = max(64, r.width * 0.36 - bw / 2).rounded()
        return HouseCutGeometry(above: above, below: below, attic: attic, fh: fh, roofH: roofH, ground: ground,
                                left: left, bw: bw, elevator: elevator)
    }

    private static func houseCutBody(_ ctx: inout GraphicsContext, g: HouseCutGeometry, dashed: Bool,
                                     ink: HouseCutInk, roadBottom: CGFloat, dark: Bool) {
        houseBasement(&ctx, g: g, ink: ink, roadBottom: roadBottom, dark: dark, dashed: dashed)
        // 還沒交屋：房間淡淡的，外框是虛線
        var rooms = ctx
        if dashed { rooms.opacity *= 0.5 }
        for (i, level) in g.above.enumerated() {
            houseLevel(&rooms, level, floorY: g.floorY(i), g: g, ink: ink, underground: false, dark: dark)
        }
        let roof = houseRoofPaths(g)
        if dashed {
            houseCutOutline(&ctx, g: g, roof: roof.outer, ink: ink)
        } else {
            houseCutFrame(&ctx, g: g, ink: ink)
            ctx.fill(roof.outer, with: .color(ink.roof))
            ctx.fill(roof.inner, with: .color(ink.back))
        }
        if let attic = g.attic {
            houseAttic(&rooms, attic, g: g, ink: ink, dark: dark)
        }
        if g.elevator {
            houseElevator(&ctx, g: g, dark: dark, dashed: dashed)
        }
    }

    /// 一層：背牆（夜裡亮燈）＋房間（隔間、吊燈、家具），沒填用途就只畫窗
    private static func houseLevel(_ ctx: inout GraphicsContext, _ level: HouseSceneFloor, floorY fy: CGFloat,
                                   g: HouseCutGeometry, ink: HouseCutInk, underground: Bool, dark: Bool) {
        let top = fy - g.fh
        ctx.fill(Path(CGRect(x: g.left, y: top, width: g.bw, height: g.fh)),
                 with: .color(underground ? ink.basementBack : ink.back))
        if dark, g.fh > 6 {
            let glow = Gradient(colors: [Color(tb: 0xFFC56B, 0.35), Color(tb: 0xFFC56B, 0.08)])
            ctx.fill(Path(CGRect(x: g.left + 3, y: top + 3, width: g.bw - 6, height: g.fh - 3)),
                     with: .linearGradient(glow, startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: fy)))
        }
        if level.rooms.isEmpty {
            houseWindows(&ctx, top: top, g: g, ink: ink)
        } else {
            houseRooms(&ctx, level.rooms, top: top, floorY: fy, g: g, ink: ink, dark: dark)
        }
    }

    private static func houseWindows(_ ctx: inout GraphicsContext, top: CGFloat, g: HouseCutGeometry,
                                     ink: HouseCutInk) {
        guard g.fh >= 9 else { return }
        let ww = min(18, g.bw * 0.14).rounded()
        let wh = (g.fh * 0.42).rounded()
        let wy = (top + g.fh * 0.28).rounded()
        for dx: CGFloat in [0.3, 0.7] {
            let box = CGRect(x: (g.left + g.bw * dx - ww / 2).rounded(), y: wy, width: ww, height: wh)
            ctx.fill(Path(box), with: .color(ink.window))
            ctx.stroke(Path(box), with: .color(ink.wall.opacity(0.45)), lineWidth: 0.8)
            ctx.fill(Path(CGRect(x: box.minX, y: box.midY - 0.4, width: box.width, height: 0.8)),
                     with: .color(ink.wall.opacity(0.35)))
        }
    }

    /// 一層有幾個用途就橫向平分；家具站在這層的地板上（樓板最後才畫，會蓋住家具最下面 1.5pt，跟樣稿一樣）
    private static func houseRooms(_ ctx: inout GraphicsContext, _ rooms: [FloorFunction], top: CGFloat,
                                   floorY fy: CGFloat, g: HouseCutGeometry, ink: HouseCutInk, dark: Bool) {
        let cw = (g.bw - 6) / CGFloat(rooms.count)
        let lamp = g.fh >= 25
        let scale = houseIconScale(fh: g.fh, cellWidth: cw, lamp: lamp)
        for (k, room) in rooms.enumerated() {
            let rx = g.left + 3 + CGFloat(k) * cw
            let mid = rx + cw / 2
            if k > 0 {
                ctx.fill(Path(CGRect(x: rx - 0.6, y: top + 3, width: 1.2, height: g.fh - 3)),
                         with: .color(ink.divider))
            }
            if lamp {
                ctx.fill(Path(CGRect(x: mid - 0.4, y: top + 3, width: 0.8, height: 3)), with: .color(ink.cord))
                ctx.fill(Path(ellipseIn: CGRect(x: mid - 2, y: top + 5.5, width: 4, height: 2.4)),
                         with: .color(ink.bulb))
            }
            if let scale {
                var icon = ctx
                icon.translateBy(x: mid, y: fy)
                icon.scaleBy(x: scale.width, y: scale.height)
                houseRoomIcon(&icon, room, ink: ink, dark: dark)
            }
        }
    }

    /// 家具小圖的縮放（寬、高）：房間窄就整個縮，層矮就壓扁；層高不到 12（或縮到看不出來）就不畫，只留樓層牌。
    /// 小圖原尺寸大約寬 28、高 16（站在 y＝0）
    private static func houseIconScale(fh: CGFloat, cellWidth cw: CGFloat, lamp: Bool) -> CGSize? {
        guard fh >= 12 else { return nil }
        let roomH = fh - (lamp ? 9.5 : 3)
        let sx = min(1, (cw - 3) / 28)
        let sy = min(sx, roomH / 16)
        guard sx >= 0.4, sy >= 0.4 else { return nil }
        return CGSize(width: min(sx, sy * 1.6), height: sy)
    }

    private static func houseCutFrame(_ ctx: inout GraphicsContext, g: HouseCutGeometry, ink: HouseCutInk) {
        for i in 0...g.above.count {
            ctx.fill(Path(CGRect(x: g.left, y: g.floorY(i) - 1.5, width: g.bw, height: 3)), with: .color(ink.wall))
        }
        ctx.fill(Path(CGRect(x: g.left, y: g.bodyTop, width: 3, height: g.bodyH)), with: .color(ink.wall))
        ctx.fill(Path(CGRect(x: g.right - 3, y: g.bodyTop, width: 3, height: g.bodyH)), with: .color(ink.wall))
    }

    /// 房貸還沒開始（預售屋）：整棟只畫虛線外框，樓板也是虛線
    private static func houseCutOutline(_ ctx: inout GraphicsContext, g: HouseCutGeometry, roof: Path,
                                        ink: HouseCutInk) {
        let style = StrokeStyle(lineWidth: 1.2, dash: [3, 2])
        let color = ink.wall.opacity(0.85)
        ctx.fill(roof, with: .color(ink.back.opacity(0.35)))
        ctx.stroke(roof, with: .color(color), style: style)
        ctx.stroke(Path(CGRect(x: g.left, y: g.bodyTop, width: g.bw, height: g.bodyH)), with: .color(color),
                   style: style)
        var slabs = Path()
        for i in 1..<g.above.count {
            slabs.move(to: CGPoint(x: g.left, y: g.floorY(i)))
            slabs.addLine(to: CGPoint(x: g.right, y: g.floorY(i)))
        }
        ctx.stroke(slabs, with: .color(ink.wall.opacity(0.55)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
    }

    /// 剖開的屋頂：外層深紫三角，裡面用背牆色往內縮一圈
    private static func houseRoofPaths(_ g: HouseCutGeometry) -> (outer: Path, inner: Path) {
        var outer = Path()
        outer.move(to: CGPoint(x: g.left - 8, y: g.bodyTop))
        outer.addLine(to: CGPoint(x: g.cx, y: g.roofTop))
        outer.addLine(to: CGPoint(x: g.right + 8, y: g.bodyTop))
        outer.closeSubpath()
        var inner = Path()
        inner.move(to: CGPoint(x: g.left + 6, y: g.bodyTop - 2))
        inner.addLine(to: CGPoint(x: g.cx, y: g.roofTop + 7))
        inner.addLine(to: CGPoint(x: g.right - 6, y: g.bodyTop - 2))
        inner.closeSubpath()
        return (outer, inner)
    }

    /// RF：屋頂裡那一間。有用途就在正中間畫第一個（縮到塞得進三角形），沒有就畫一扇圓窗
    private static func houseAttic(_ ctx: inout GraphicsContext, _ attic: HouseSceneFloor, g: HouseCutGeometry,
                                   ink: HouseCutInk, dark: Bool) {
        let innerH = g.roofH - 9
        let base = g.bodyTop - 2
        guard innerH > 4 else { return }
        if let room = attic.rooms.first {
            let half = g.bw / 2 - 6
            let fit = half / (14 + 16 * half / innerH)
            let s = min(1, (innerH - 1) / 16, fit)
            guard s >= 0.35 else { return }
            var icon = ctx
            icon.translateBy(x: g.cx, y: base)
            icon.scaleBy(x: s, y: s)
            houseRoomIcon(&icon, room, ink: ink, dark: dark)
        } else {
            let d = min(7, innerH * 0.5)
            let dot = CGRect(x: g.cx - d / 2, y: base - innerH * 0.4 - d / 2, width: d, height: d)
            ctx.fill(Path(ellipseIn: dot), with: .color(ink.window))
            ctx.stroke(Path(ellipseIn: dot), with: .color(ink.wall.opacity(0.5)), lineWidth: 0.8)
        }
    }

    /// 電梯井：貼著右牆，從最深的地下室到屋頂下；井裡每層一條線，車廂停在 2F（只有一層就停 1F）
    private static func houseElevator(_ ctx: inout GraphicsContext, g: HouseCutGeometry, dark: Bool, dashed: Bool) {
        let top = g.bodyTop - 6
        let shaft = CGRect(x: g.right, y: top, width: 13, height: g.ground + g.depth - top)
        let color = dark ? Color(tb: 0x4A3A8F) : Color(tb: 0x8E74E6)
        if dashed {
            ctx.stroke(Path(shaft.insetBy(dx: 0.6, dy: 0.6)), with: .color(color),
                       style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
            return
        }
        ctx.fill(Path(shaft), with: .color(color))
        let line = dark ? Color(tb: 0x2A1F5A) : Color(tb: 0x6B4BE0, 0.6)
        var ys: [CGFloat] = []
        for i in 1..<g.above.count { ys.append(g.floorY(i)) }
        for j in 0..<g.below.count { ys.append(g.basementTop(j)) }
        for y in ys {
            ctx.fill(Path(CGRect(x: g.right + 2, y: y - 0.5, width: 9, height: 1)), with: .color(line))
        }
        let stop = min(1, g.above.count - 1)
        let car = CGRect(x: g.right + 2.5, y: g.floorY(stop) - g.fh * 0.85, width: 8, height: max(3, g.fh * 0.75))
        ctx.fill(Path(roundedRect: car, cornerRadius: 1.5),
                 with: .color(dark ? Color(tb: 0xFFE7A8) : Color.white.opacity(0.95)))
    }

    /// 地下室：把馬路剖開一塊（土色），裡面一層一層往下畫
    private static func houseBasement(_ ctx: inout GraphicsContext, g: HouseCutGeometry, ink: HouseCutInk,
                                      roadBottom: CGFloat, dark: Bool, dashed: Bool) {
        guard !g.below.isEmpty else { return }
        let pitH = max(g.depth + 2, roadBottom - g.ground)
        ctx.fill(Path(CGRect(x: g.left - 5, y: g.ground, width: g.edge - g.left + 10, height: pitH)),
                 with: .color(ink.soil))
        var rooms = ctx
        if dashed { rooms.opacity *= 0.5 }
        for (j, level) in g.below.enumerated() {
            houseLevel(&rooms, level, floorY: g.basementTop(j + 1), g: g, ink: ink, underground: true, dark: dark)
        }
        let box = CGRect(x: g.left, y: g.ground, width: g.bw, height: g.depth)
        if dashed {
            ctx.stroke(Path(box), with: .color(ink.wall.opacity(0.85)), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
            return
        }
        for j in 1...g.below.count {
            ctx.fill(Path(CGRect(x: g.left, y: g.basementTop(j) - 1.5, width: g.bw, height: 3)), with: .color(ink.wall))
        }
        ctx.fill(Path(CGRect(x: box.minX, y: box.minY, width: 3, height: box.height)), with: .color(ink.wall))
        ctx.fill(Path(CGRect(x: box.maxX - 3, y: box.minY, width: 3, height: box.height)), with: .color(ink.wall))
    }

    /// 還欠銀行的那一截：從地面往上。深色是白斜線；淺色的房間是很淡的紫、白線看不出來，
    /// 所以紫線（畫在房間上看得到）和白線（畫在牆、樓板、家具上看得到）錯開半格各畫一次
    private static func houseCutOwed(_ ctx: inout GraphicsContext, g: HouseCutGeometry, top: CGFloat, dark: Bool) {
        let zone = CGRect(x: g.left, y: top, width: g.bw, height: g.ground - top)
        guard zone.height > 0.5 else { return }
        if dark {
            houseHatch(&ctx, zone, color: Color.white.opacity(0.58), gap: 5, phase: 0)
        } else {
            ctx.fill(Path(zone), with: .color(Color(tb: 0x6B4BE0, 0.05)))
            houseHatch(&ctx, zone, color: Color(tb: 0x6B4BE0, 0.34), gap: 5, phase: 0)
            houseHatch(&ctx, zone, color: Color.white.opacity(0.7), gap: 5, phase: 2.5)
        }
        houseOwedLine(&ctx, y: top, from: g.left - 3, to: g.right + 3, dark: dark)
    }

    /// 斜線（跟 finHatch 同一個畫法，多一個 phase 讓兩組線錯開）
    private static func houseHatch(_ ctx: inout GraphicsContext, _ r: CGRect, color: Color, gap: CGFloat,
                                   phase: CGFloat) {
        guard r.width > 0.5, r.height > 0.5 else { return }
        var g = ctx
        g.clip(to: Path(r))
        var p = Path()
        var sx = r.minX - r.height + phase
        while sx < r.maxX {
            p.move(to: CGPoint(x: sx, y: r.maxY))
            p.addLine(to: CGPoint(x: sx + r.height, y: r.minY))
            sx += gap
        }
        g.stroke(p, with: .color(color), lineWidth: 1.1)
    }

    /// 斜線頂端那條紅虛線（還欠和你的分界）
    private static func houseOwedLine(_ ctx: inout GraphicsContext, y: CGFloat, from x0: CGFloat, to x1: CGFloat,
                                      dark: Bool) {
        var line = Path()
        line.move(to: CGPoint(x: x0, y: y))
        line.addLine(to: CGPoint(x: x1, y: y))
        ctx.stroke(line, with: .color(finOwedInk(dark: dark)), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
    }

    // MARK: 房間小圖（照 hcard.js roomIcon；原點＝房間中間的地板，往上是負的，寬約 28、高約 16）

    private static func houseRoomIcon(_ ctx: inout GraphicsContext, _ room: FloorFunction, ink: HouseCutInk,
                                      dark: Bool) {
        switch room {
        case .parking: houseIconCar(&ctx, dark: dark)
        case .livingRoom: houseIconLiving(&ctx, ink: ink, dark: dark)
        case .kitchen: houseIconKitchen(&ctx, ink: ink, dark: dark)
        case .masterBedroom: houseIconBed(&ctx, double: true, ink: ink)
        case .guestBedroom: houseIconBed(&ctx, double: false, ink: ink)
        case .musicRoom: houseIconPiano(&ctx, ink: ink, dark: dark)
        case .playroom: houseIconToys(&ctx)
        case .storage: houseIconBoxes(&ctx, dark: dark)
        }
    }

    /// 停車：一台小車
    private static func houseIconCar(_ ctx: inout GraphicsContext, dark: Bool) {
        let body = dark ? Color(tb: 0x5BA8E8) : Color(tb: 0x2F7FE8)
        let tire = dark ? Color(tb: 0x11162E) : Color(tb: 0x1D2B55)
        let glass = Color.white.opacity(0.75)
        hcBox(&ctx, -11, -8, 22, 5.5, body, r: 2.5)
        hcBox(&ctx, -6, -12, 11, 5, body, r: 2.5)
        hcBox(&ctx, -4.6, -11, 3.6, 2.6, glass, r: 0.8)
        hcBox(&ctx, 0, -11, 3.6, 2.6, glass, r: 0.8)
        hcDot(&ctx, -9, -4.5, 4.5, 4.5, tire)
        hcDot(&ctx, 4.5, -4.5, 4.5, 4.5, tire)
    }

    /// 客廳：沙發（左）＋電視（右）
    private static func houseIconLiving(_ ctx: inout GraphicsContext, ink: HouseCutInk, dark: Bool) {
        hcBox(&ctx, -12, -9, 14, 5, ink.cushion, r: 2)
        hcBox(&ctx, -13, -6, 16, 5, ink.furniture, r: 2)
        hcBox(&ctx, -14, -7, 2.2, 6, ink.furniture)
        hcBox(&ctx, 2.6, -7, 2.2, 6, ink.furniture)
        hcBox(&ctx, 6.5, -4, 7.5, 4, ink.wood, r: 0.8)
        hcBox(&ctx, 9.8, -6, 0.9, 2, ink.furniture)
        hcBox(&ctx, 6, -12.5, 8.5, 6.5, dark ? Color(tb: 0x4D7FD6) : Color(tb: 0x1D2B55), r: 1)
        hcBox(&ctx, 7, -11.5, 3, 2, Color.white.opacity(dark ? 0.35 : 0.45), r: 0.5)
    }

    /// 廚房：流理台＋吊櫃＋鍋子＋冰箱
    private static func houseIconKitchen(_ ctx: inout GraphicsContext, ink: HouseCutInk, dark: Bool) {
        let counterTop = dark ? Color(tb: 0xE6ECFF) : Color(tb: 0x8A94AE)
        let fridgeLine = dark ? Color(tb: 0x8A94AE) : Color(tb: 0xB9C2D6)
        hcBox(&ctx, -13, -8, 17, 8, ink.wood)
        hcBox(&ctx, -13, -9.2, 17, 1.6, counterTop)
        hcBox(&ctx, -4.9, -6.5, 0.8, 5, ink.furniture.opacity(0.45))
        hcBox(&ctx, -10, -11.8, 6, 2.8, Color(tb: 0xE07A2E), r: 1)
        hcBox(&ctx, -13, -16, 13, 3.4, ink.wood, r: 0.8)
        hcBox(&ctx, -7.3, -13.6, 1.6, 0.8, ink.furniture)
        let fridge = CGRect(x: 6, y: -15, width: 7, height: 15)
        ctx.fill(Path(roundedRect: fridge, cornerRadius: 1.5),
                 with: .color(dark ? Color(tb: 0xD7DEEE) : Color.white.opacity(0.98)))
        ctx.stroke(Path(roundedRect: fridge, cornerRadius: 1.5), with: .color(fridgeLine), lineWidth: 0.8)
        hcBox(&ctx, 6.5, -9.6, 6, 0.7, fridgeLine)
    }

    /// 主臥＝雙人床（床頭床尾板、兩顆枕頭）；客臥＝單人床＋床頭櫃小檯燈
    private static func houseIconBed(_ ctx: inout GraphicsContext, double: Bool, ink: HouseCutInk) {
        let pillow = Color.white.opacity(0.95)
        if double {
            hcBox(&ctx, -14, -13, 2.5, 13, ink.wood)
            hcBox(&ctx, 11.5, -7.5, 2, 7.5, ink.wood)
            hcBox(&ctx, -11.5, -6, 23, 5, ink.cushion, r: 1.5)
            hcBox(&ctx, -11, -9.8, 6, 3, pillow, r: 1.5)
            hcBox(&ctx, -9.5, -8.6, 6, 3, pillow, r: 1.5)
            hcBox(&ctx, -3, -8.2, 14, 3.2, ink.furniture, r: 1.5)
        } else {
            hcBox(&ctx, -10, -11, 2.5, 11, ink.wood)
            hcBox(&ctx, -7.5, -6, 15, 5, ink.cushion, r: 1.5)
            hcBox(&ctx, -6.5, -8.5, 5, 3, pillow, r: 1.5)
            hcBox(&ctx, -1, -8, 8.5, 3, ink.furniture, r: 1.5)
            hcBox(&ctx, 9.5, -5, 4.5, 5, ink.wood, r: 0.6)
            hcDot(&ctx, 10.4, -8.2, 2.8, 3, Color(tb: 0xFFD98A))
        }
    }

    /// 音樂室：直立鋼琴（琴鍵、譜架）＋琴椅
    private static func houseIconPiano(_ ctx: inout GraphicsContext, ink: HouseCutInk, dark: Bool) {
        let body = dark ? Color(tb: 0xC9B8FF) : Color(tb: 0x3B2A78)
        hcBox(&ctx, -12, -15, 17, 15, body, r: 1.5)
        hcBox(&ctx, -10, -13, 13, 2.5, ink.cushion, r: 0.8)
        hcBox(&ctx, -13, -8, 19, 2.4, Color.white.opacity(0.95), r: 0.6)
        for k in 0..<4 {
            hcBox(&ctx, -11.5 + CGFloat(k) * 4.2, -8, 1.4, 1.3, body)
        }
        hcBox(&ctx, 8, -5, 6, 1.6, ink.wood, r: 0.6)
        hcBox(&ctx, 8.6, -3.4, 1, 3.4, ink.wood)
        hcBox(&ctx, 12.4, -3.4, 1, 3.4, ink.wood)
    }

    /// 遊樂室：疊起來的積木＋一顆球
    private static func houseIconToys(_ ctx: inout GraphicsContext) {
        hcBox(&ctx, -12, -5.5, 5.5, 5.5, Color(tb: 0xE07A2E), r: 0.8)
        hcBox(&ctx, -6, -5.5, 5.5, 5.5, Color(tb: 0x2F9BD8), r: 0.8)
        hcBox(&ctx, -9, -11, 5.5, 5.5, Color(tb: 0x1F9D57), r: 0.8)
        var tri = Path()
        tri.move(to: CGPoint(x: -9, y: -11.4))
        tri.addLine(to: CGPoint(x: -6.25, y: -15.5))
        tri.addLine(to: CGPoint(x: -3.5, y: -11.4))
        tri.closeSubpath()
        ctx.fill(tri, with: .color(Color(tb: 0xF2B33D)))
        hcDot(&ctx, 3, -8, 8, 8, Color(tb: 0xE0457A))
        hcDot(&ctx, 4.6, -6.8, 2.6, 2.2, Color.white.opacity(0.8))
    }

    /// 倉庫：一疊紙箱
    private static func houseIconBoxes(_ ctx: inout GraphicsContext, dark: Bool) {
        let card = dark ? Color(tb: 0xB08A6A) : Color(tb: 0xC89B74)
        let card2 = dark ? Color(tb: 0x9A7658) : Color(tb: 0xB5875F)
        let tape = dark ? Color(tb: 0x6E5442) : Color(tb: 0xEAD9C0)
        hcBox(&ctx, -13, -9, 11, 9, card, r: 0.6)
        hcBox(&ctx, -8.1, -9, 1.2, 9, tape)
        hcBox(&ctx, -1, -7, 9, 7, card2, r: 0.6)
        hcBox(&ctx, 2.9, -7, 1.2, 7, tape)
        hcBox(&ctx, -11, -15.5, 8, 6.5, card2, r: 0.6)
        hcBox(&ctx, -7.6, -15.5, 1.2, 6.5, tape)
        hcBox(&ctx, 9, -4, 4.5, 4, card, r: 0.5)
    }

    private static func hcBox(_ ctx: inout GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat,
                              _ h: CGFloat, _ c: Color, r: CGFloat = 0) {
        let rect = CGRect(x: x, y: y, width: w, height: h)
        if r > 0 {
            ctx.fill(Path(roundedRect: rect, cornerRadius: r), with: .color(c))
        } else {
            ctx.fill(Path(rect), with: .color(c))
        }
    }

    private static func hcDot(_ ctx: inout GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat,
                              _ h: CGFloat, _ c: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h)), with: .color(c))
    }

    // MARK: 大樓

    private static func paintHouseTower(_ ctx: inout GraphicsContext, rect r: CGRect, model m: HouseSceneModel,
                                        low: Int, high: Int, total: Int, label: String, dark: Bool, seed: Int) {
        let w = r.width
        let plate = houseNamePlate(m, emptyHouse: false)
        let g = houseTowerGeometry(low: low, high: high, total: total, rect: r, plate: plate != nil)
        let ink = HouseCutInk(dark: dark)
        houseBackdrop(&ctx, width: w, ground: g.ground, dark: dark, seed: seed)
        houseRoad(&ctx, width: w, ground: g.ground, bottom: r.maxY, dark: dark)
        let u = g.unit
        let owes = !m.isSold && !m.notStarted && m.owedFraction > 0
        let fraction = CGFloat(min(1, max(0, m.owedFraction)))
        let owedTop = u.maxY - u.height * fraction
        let floorText = houseTowerFloorText(label, g: g)
        let labels = houseTowerLabels(ctx, g: g, model: m, floorText: floorText, owedTop: owes ? owedTop : nil,
                                      plate: plate, ink: ink, dark: dark, rect: r)
        houseTrees(&ctx, from: labels.rightEdge, leftLimit: u.minX - 4, ground: g.ground, width: w,
                   avoid: labels.leftRects, dark: dark)
        var body = ctx
        if m.isSold { body.opacity = 0.45 }
        houseTowerBody(&body, g: g, dark: dark, seed: seed)
        houseTowerUnit(&body, g: g, dark: dark, dashed: m.notStarted)
        if owes {
            houseTowerOwed(&ctx, unit: u, top: owedTop, dark: dark)
        }
        houseDrawLabels(&ctx, labels, dark: dark)
    }

    /// 大樓尺寸：整棟平均每層不到 12pt 時，你那幾層合起來至少 14pt（最多佔 4 成），其他樓層分剩下的
    private static func houseTowerGeometry(low: Int, high: Int, total: Int, rect r: CGRect,
                                           plate: Bool) -> HouseTowerGeometry {
        let ground = r.maxY - 18
        let bodyTop = r.minY + (plate ? 20 : 8) + 6
        let h = max(10, ground - bodyTop)
        let lo = max(1, low)
        let hi = max(lo, high)
        let n = max(total, hi + 1)
        let mine = hi - lo + 1
        let even = h / CGFloat(n)
        var fhMine = even
        var fhOther = even
        if even < 12 {
            let unitH = min(h * 0.4, max(14, CGFloat(mine) * even))
            fhMine = unitH / CGFloat(mine)
            fhOther = (h - unitH) / CGFloat(n - mine)
        }
        let bw = min(76, max(54, r.width * 0.18)).rounded()
        let cx = max(bw / 2 + 70, r.width * 0.36).rounded()
        return HouseTowerGeometry(ground: ground, bodyTop: bodyTop, cx: cx, bw: bw, floors: n, low: lo, high: hi,
                                  fhOther: fhOther, fhMine: fhMine)
    }

    private static func houseTowerFloorText(_ label: String, g: HouseTowerGeometry) -> String {
        let t = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        return g.high > g.low ? "\(g.low)–\(g.high)F" : "\(g.low)F"
    }

    /// 灰藍色高樓：樓頂機房、左邊一條亮面、每層一排窗（夜裡有些亮琥珀色）、一樓大門
    private static func houseTowerBody(_ ctx: inout GraphicsContext, g: HouseTowerGeometry, dark: Bool, seed: Int) {
        let h = g.ground - g.bodyTop
        ctx.fill(Path(CGRect(x: g.cx - g.bw * 0.22, y: g.bodyTop - 6, width: g.bw * 0.44, height: 6)),
                 with: .color(dark ? Color(tb: 0x22305E) : Color(tb: 0x8AA3C6)))
        ctx.fill(Path(CGRect(x: g.left, y: g.bodyTop, width: g.bw, height: h)),
                 with: .color(dark ? Color(tb: 0x2A3A70) : Color(tb: 0x9DB4D3)))
        ctx.fill(Path(CGRect(x: g.left, y: g.bodyTop, width: g.bw * 0.2, height: h)),
                 with: .color(Color.white.opacity(dark ? 0.06 : 0.25)))
        houseTowerWindows(&ctx, g: g, dark: dark, seed: seed)
        let lobby = g.floorY(1) - g.floorY(2)
        let doorH = min(12, lobby * 0.8)
        if doorH >= 4 {
            ctx.fill(Path(roundedRect: CGRect(x: g.cx - 5, y: g.ground - doorH, width: 10, height: doorH),
                          cornerRadius: 1.5),
                     with: .color(dark ? Color(tb: 0x141D3A) : Color(tb: 0x4A5B8C)))
        }
    }

    /// 別人的樓層：每層一排窗；壓得太扁（每層不到 2.5pt）就隔幾層才畫一排，當成紋路
    private static func houseTowerWindows(_ ctx: inout GraphicsContext, g: HouseTowerGeometry, dark: Bool, seed: Int) {
        var rng = InkRandom(seed &+ 41)
        let unlit = dark ? Color(tb: 0x3A4A80) : Color(tb: 0xC4D4E8)
        let lit = Color(tb: 0xFFC56B, 0.85)
        let cols = max(2, Int((g.bw - 8) / 11))
        let cw = (g.bw - 8) / CGFloat(cols)
        let step = g.fhOther >= 2.5 ? 1 : Int((2.5 / max(0.1, g.fhOther)).rounded(.up))
        for k in 1...g.floors where k < g.low || k > g.high {
            guard (k - 1) % step == 0 else { continue }
            let top = g.floorY(k + 1)
            let fh = g.floorY(k) - top
            let inset = min(1.4, fh * 0.22)
            let wh = max(0.8, fh - inset * 2)
            for c in 0..<cols {
                let x = g.left + 4 + CGFloat(c) * cw
                let on = dark && rng.next() > 0.6
                ctx.fill(Path(CGRect(x: x + 0.6, y: top + inset, width: cw - 1.2, height: wh)),
                         with: .color(on ? lit : unlit))
            }
        }
    }

    /// 你那幾層：finHome 紫色漸層＋樓板線＋窗；房貸還沒開始就只畫虛線框
    private static func houseTowerUnit(_ ctx: inout GraphicsContext, g: HouseTowerGeometry, dark: Bool, dashed: Bool) {
        let u = g.unit
        let th = MoneyArtTheme.finHome
        if dashed {
            ctx.fill(Path(u), with: .color(th.topColor.opacity(0.25)))
            ctx.stroke(Path(u.insetBy(dx: 0.6, dy: 0.6)), with: .color(dark ? th.topColor : th.bottomColor),
                       style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
            return
        }
        let grad = Gradient(colors: [th.topColor, th.bottomColor])
        ctx.fill(Path(u), with: .linearGradient(grad, startPoint: CGPoint(x: 0, y: u.minY),
                                                endPoint: CGPoint(x: 0, y: u.maxY)))
        let win = dark ? Color(tb: 0xFFC56B, 0.9) : Color.white.opacity(0.8)
        let sep = dark ? Color(tb: 0x2A1F5A) : Color(tb: 0x4B2FB0, 0.5)
        for k in g.low...g.high {
            let top = g.floorY(k + 1)
            let fh = g.floorY(k) - top
            if k > g.low {
                ctx.fill(Path(CGRect(x: u.minX, y: g.floorY(k) - 0.5, width: u.width, height: 1)), with: .color(sep))
            }
            guard fh >= 7 else { continue }
            for dx: CGFloat in [-0.27, 0, 0.27] {
                ctx.fill(Path(CGRect(x: g.cx + g.bw * dx - 5, y: top + fh * 0.25, width: 10, height: fh * 0.45)),
                         with: .color(win))
            }
        }
    }

    /// 大樓的斜線：畫在你那幾層，從那幾層的地板往上（跟透天從地面往上同一個意思）
    private static func houseTowerOwed(_ ctx: inout GraphicsContext, unit u: CGRect, top: CGFloat, dark: Bool) {
        let zone = CGRect(x: u.minX, y: top, width: u.width, height: u.maxY - top)
        houseHatch(&ctx, zone, color: Color.white.opacity(dark ? 0.58 : 0.8), gap: 4, phase: 0)
        houseOwedLine(&ctx, y: top, from: u.minX - 3, to: u.maxX + 3, dark: dark)
    }

    // MARK: 背景、馬路、行道樹

    /// 遠方一排矮房子＋草地條（房子後面）
    private static func houseBackdrop(_ ctx: inout GraphicsContext, width w: CGFloat, ground: CGFloat,
                                      dark: Bool, seed: Int) {
        TripBoardSkyArt.paintFarRow(&ctx, width: w, ground: ground, band: 34, ink: farInk(dark: dark), seed: seed)
        ctx.fill(Path(CGRect(x: 0, y: ground - 3, width: w, height: 3)),
                 with: .color(dark ? Color(tb: 0x1E3B33) : Color(tb: 0xBFE6CB)))
    }

    /// 前面的馬路：路肩、路面、白虛線（照樣稿；配色跟列表街景的 finStreet 不一樣）
    private static func houseRoad(_ ctx: inout GraphicsContext, width w: CGFloat, ground: CGFloat, bottom: CGFloat,
                                  dark: Bool) {
        let roadH = bottom - ground
        guard roadH > 4 else { return }
        ctx.fill(Path(CGRect(x: 0, y: ground, width: w, height: 3)),
                 with: .color(dark ? Color(tb: 0x3A4670) : Color(tb: 0xC9D6E8)))
        ctx.fill(Path(CGRect(x: 0, y: ground + 3, width: w, height: roadH - 3)),
                 with: .color(dark ? Color(tb: 0x141D3A) : Color(tb: 0x9AA9C2)))
        let dash = dark ? Color(tb: 0x6E7FB0, 0.7) : Color.white.opacity(0.85)
        let ly = ground + 3 + (roadH - 3) / 2 - 0.8
        var x: CGFloat = 6
        while x < w {
            ctx.fill(Path(CGRect(x: x, y: ly, width: 11, height: 1.6)), with: .color(dash))
            x += 22
        }
    }

    /// 行道樹：右邊從樓層牌外面種起（一大一小，畫面寬就一路種到底）；左邊一棵，壓到牌子就不種
    private static func houseTrees(_ ctx: inout GraphicsContext, from x0: CGFloat, leftLimit: CGFloat,
                                   ground: CGFloat, width w: CGFloat, avoid: [CGRect], dark: Bool) {
        let first = x0 + 22
        if first + 10 < w {
            paintTree(&ctx, at: CGPoint(x: first, y: ground), size: 22, dark: dark)
        }
        var x = first + 24
        var k = 0
        while x + 8 < w {
            let size: CGFloat = k == 0 ? 15 : (k % 2 == 1 ? 18 : 14)
            paintTree(&ctx, at: CGPoint(x: x, y: ground), size: size, dark: dark)
            x += k % 2 == 0 ? 40 : 26
            k += 1
        }
        let spot = CGRect(x: 8, y: ground - 26, width: 20, height: 26)
        let blocked = avoid.contains { $0.insetBy(dx: -3, dy: -2).intersects(spot) }
        if !blocked, spot.maxX + 6 < leftLimit {
            paintTree(&ctx, at: CGPoint(x: spot.midX, y: ground), size: 17, dark: dark)
        }
    }

    // MARK: 牌子

    /// 名牌：已售「已售・<名字>」；空房子（還沒填樓層）只寫名字；其他時候不掛
    private static func houseNamePlate(_ m: HouseSceneModel, emptyHouse: Bool) -> String? {
        let name = m.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if m.isSold { return name.isEmpty ? "已售" : "已售・" + name }
        if emptyHouse, !name.isEmpty { return name }
        return nil
    }

    private static func houseCutLabels(_ ctx: GraphicsContext, g: HouseCutGeometry, model m: HouseSceneModel,
                                       owedTop: CGFloat?, plate: String?, ink: HouseCutInk, dark: Bool,
                                       rect r: CGRect) -> HouseSceneLabels {
        var plan = HouseSceneLabels()
        plan.rightEdge = g.edge
        let ph = min(13, max(9, g.fh - 1))
        // 層太矮時隔幾層才掛一塊，免得牌子疊在一起
        let step = g.fh >= 9 ? 1 : Int((10 / max(0.1, g.fh)).rounded(.up))
        let x = g.edge + 5
        for (i, level) in g.above.enumerated() where !level.label.isEmpty && i % step == 0 {
            plan.right.append(houseFloorPill(ctx, level.label, x: x, y: g.floorY(i) - g.fh / 2, height: ph,
                                             basement: false, ink: ink, rect: r))
        }
        for (j, level) in g.below.enumerated() where !level.label.isEmpty && j % step == 0 {
            plan.right.append(houseFloorPill(ctx, level.label, x: x, y: g.basementTop(j) + g.fh / 2, height: ph,
                                             basement: true, ink: ink, rect: r))
        }
        if let attic = g.attic {
            plan.right.append(houseFloorPill(ctx, attic.label, x: x, y: g.bodyTop - g.roofH * 0.4,
                                             height: min(13, ph + 2), basement: false, ink: ink, rect: r))
        }
        for p in plan.right {
            plan.rightEdge = max(plan.rightEdge, p.box.maxX)
        }
        houseLeftLabels(ctx, plan: &plan, model: m, owedTop: owedTop, buildingLeft: g.left, ground: g.ground,
                        dark: dark, rect: r)
        if let s = plate {
            plan.top = housePlatePill(ctx, s, centerX: g.cx, bottom: g.roofTop - 3, dark: dark, rect: r)
        }
        return plan
    }

    private static func houseTowerLabels(_ ctx: GraphicsContext, g: HouseTowerGeometry, model m: HouseSceneModel,
                                         floorText: String, owedTop: CGFloat?, plate: String?, ink: HouseCutInk,
                                         dark: Bool, rect r: CGRect) -> HouseSceneLabels {
        var plan = HouseSceneLabels()
        let u = g.unit
        let ph = min(13, max(10, u.height - 1))
        let pill = houseFloorPill(ctx, floorText, x: u.maxX + 5, y: u.midY, height: ph, basement: false,
                                  ink: ink, rect: r)
        plan.right.append(pill)
        plan.rightEdge = max(u.maxX, pill.box.maxX)
        houseLeftLabels(ctx, plan: &plan, model: m, owedTop: owedTop, buildingLeft: u.minX, ground: g.ground,
                        dark: dark, rect: r)
        if let s = plate {
            plan.top = housePlatePill(ctx, s, centerX: g.cx, bottom: g.bodyTop - 9, dark: dark, rect: r)
        }
        return plan
    }

    /// 左邊的牌子：出租中（插在地上）＋房貸牌（對著斜線頂端）。兩塊疊到時把房貸牌往上推
    private static func houseLeftLabels(_ ctx: GraphicsContext, plan: inout HouseSceneLabels,
                                        model m: HouseSceneModel, owedTop: CGFloat?, buildingLeft: CGFloat,
                                        ground: CGFloat, dark: Bool, rect r: CGRect) {
        var rent: HouseScenePill? = nil
        if m.isRented, !m.isSold {
            let p = houseMakePill(ctx, "出租中", at: CGPoint(x: buildingLeft - 24, y: ground - 20), anchor: .center,
                                  fill: Color(tb: 0x1F9D57), ink: .white, size: 8, weight: .heavy, height: 14, rect: r)
            plan.pole = CGRect(x: p.box.midX - 0.8, y: ground - 16, width: 1.6, height: 16)
            rent = p
        }
        if let top = owedTop, let label = m.owedLabel, !label.isEmpty {
            var p = houseMakePill(ctx, label, at: CGPoint(x: buildingLeft - 8, y: top), anchor: .trailing,
                                  fill: finOwedInk(dark: dark), ink: .white, size: 8.5, weight: .heavy,
                                  height: 14, rect: r)
            if let sign = rent, p.box.intersects(sign.box.insetBy(dx: -2, dy: -2)) {
                p.box.origin.y = max(r.minY + 1, sign.box.minY - 3 - p.box.height)
            }
            plan.left.append(p)
        }
        if let sign = rent {
            plan.left.append(sign)
        }
    }

    private static func houseFloorPill(_ ctx: GraphicsContext, _ s: String, x: CGFloat, y: CGFloat, height: CGFloat,
                                       basement: Bool, ink: HouseCutInk, rect r: CGRect) -> HouseScenePill {
        houseMakePill(ctx, s, at: CGPoint(x: x, y: y), anchor: .leading, fill: ink.pillFill,
                      ink: basement ? ink.basementInk : ink.floorInk, size: 7.5, weight: .black,
                      height: height, rect: r)
    }

    private static func housePlatePill(_ ctx: GraphicsContext, _ s: String, centerX: CGFloat, bottom: CGFloat,
                                       dark: Bool, rect r: CGRect) -> HouseScenePill {
        houseMakePill(ctx, s, at: CGPoint(x: centerX, y: bottom), anchor: .bottom,
                      fill: dark ? Color(tb: 0x1C2646, 0.92) : Color.white.opacity(0.95),
                      ink: dark ? Color(tb: 0xE6ECFF) : Color(tb: 0x0B1B45),
                      size: 8, weight: .black, height: 14, rect: r)
    }

    /// 量好字寬、排好位置（anchor＝牌子的哪一點對齊 p），整塊夾在 band 裡面
    private static func houseMakePill(_ ctx: GraphicsContext, _ s: String, at p: CGPoint, anchor: UnitPoint,
                                      fill: Color, ink: Color, size: CGFloat, weight: Font.Weight,
                                      height: CGFloat, rect r: CGRect) -> HouseScenePill {
        let t = ctx.resolve(Text(s).font(.system(size: size, weight: weight)))
        let pw = (t.measure(in: CGSize(width: 300, height: 40)).width + 10).rounded(.up)
        let x = min(max(r.minX + 2, (p.x - pw * anchor.x).rounded()), r.maxX - pw - 2)
        let y = min(max(r.minY + 1, (p.y - height * anchor.y).rounded()), r.maxY - height - 1)
        return HouseScenePill(text: s, box: CGRect(x: x, y: y, width: pw, height: height),
                              fill: fill, ink: ink, size: size, weight: weight)
    }

    private static func houseDrawLabels(_ ctx: inout GraphicsContext, _ plan: HouseSceneLabels, dark: Bool) {
        if let pole = plan.pole {
            ctx.fill(Path(pole), with: .color(dark ? Color(tb: 0xA3B2D9) : Color(tb: 0x8A6142)))
        }
        for p in plan.right {
            houseDrawPill(&ctx, p)
        }
        for p in plan.left {
            houseDrawPill(&ctx, p)
        }
        if let p = plan.top {
            houseDrawPill(&ctx, p)
        }
    }

    private static func houseDrawPill(_ ctx: inout GraphicsContext, _ p: HouseScenePill) {
        let t = ctx.resolve(Text(p.text).font(.system(size: p.size, weight: p.weight)).foregroundStyle(p.ink))
        ctx.fill(Path(roundedRect: p.box, cornerRadius: p.box.height / 2), with: .color(p.fill))
        ctx.draw(t, at: CGPoint(x: p.box.midX, y: p.box.midY), anchor: .center)
    }
}
