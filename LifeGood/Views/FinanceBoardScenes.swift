import SwiftUI

// MARK: - 理財六頁的風景（v25.527）
//
// 跟收支看板同一個頭部（MoneyBoardHeader／MoneyBoardSky：天空、雲、月牙、手寫問候），
// 最下面那一條換成理財自己的資料：
//   總覽     資產小鎮：房子＝房地產、銀行＝儲蓄險、玻璃大樓＝股票、車＝載具，越高值越多；
//            斜線那一截是還欠銀行的（房貸、車貸），實心的才是你的
//   股票     熱氣球：一檔一顆，越大市值越大、飛越高賺越多；虛線是成本線，掉到線下就是賠（紅漲綠跌）
//   儲蓄險   果園：一張保單一棵樹，繳越多樹越大，快滿期的結果子，牌子寫滿期年
//   載具     今年這條路：1 月到 12 月，車停在今天；路邊一個月一個圓標（大小＝那個月花多少），
//            前面的路牌是接下來要繳的
//   房地產   街景：透天畫出樓層、大樓標出你那幾層，斜線＝還欠的，出租的掛牌子
//   圖表     極光：簾幕的上緣是每個月的淨資產
// 規矩跟收支看板一樣：要讀的數字在頭部與膠囊的 Text 裡，這裡畫的是「看得到、不給讀」的。

// MARK: - 風景的資料

/// 總覽：資產小鎮
struct FinTownScene: Equatable {
    struct Building: Equatable {
        let kind: FinanceAssetKind
        let value: Double
        /// 還欠的（房貸、車貸）；沒有是 0
        var owed: Double = 0
        var count: Int = 1
        /// 建築上方的牌子（「1,880萬」）
        let label: String
        /// 斜線上面的小牌子（「房貸 756萬」）
        var owedLabel: String? = nil
        /// 股票大樓牆上那條線往上還是往下
        var rising: Bool = true
    }
    var buildings: [Building]
}

/// 股票：熱氣球
struct FinBalloonScene: Equatable {
    struct Balloon: Equatable {
        let label: String
        let value: Double
        /// 報酬率（%）
        let returnRate: Double
        /// 旁邊的小牌子（最會漲的那一顆：「2330 +48%」）
        var callout: String? = nil
    }
    var balloons: [Balloon]
}

/// 儲蓄險：果園
struct FinOrchardScene: Equatable {
    struct Tree: Equatable {
        /// 繳了幾成（0…1）
        let progress: Double
        /// 樹下的牌子（滿期年）
        let label: String
        /// 到期比已繳多幾 %（果子的數量）
        let gain: Double
        let foreign: Bool
    }
    var trees: [Tree]
}

/// 載具：今年這條路
struct FinRoadScene: Equatable {
    enum Kind: Equatable { case fuel, charge, care, park, other }
    struct Mark: Equatable {
        /// 在一年裡的位置（0＝1/1、1＝12/31）
        let t: Double
        let kind: Kind
        let amount: Double
    }
    struct Sign: Equatable {
        let t: Double
        let label: String
    }
    var today: Double
    var marks: [Mark]
    var signs: [Sign]
}

/// 房地產：街景
struct FinStreetScene: Equatable {
    struct Home: Equatable {
        let tower: Bool
        /// 透天：幾層樓；大樓：整棟畫幾層
        let floors: Int
        /// 大樓：你是哪幾層
        var fromFloor: Int = 0
        var toFloor: Int = 0
        /// 還欠的比例（0…1）
        var owedFraction: Double = 0
        var owedLabel: String? = nil
        var rented: Bool = false
        var sold: Bool = false
        let label: String
    }
    var homes: [Home]
}

/// 圖表：極光
struct FinAuroraScene: Equatable {
    struct Tick: Equatable {
        let index: Int
        let label: String
    }
    /// 每個月的淨資產（最後一個是現在）
    var values: [Double]
    var startLabel: String? = nil
    var endLabel: String? = nil
    var ticks: [Tick] = []
}

// MARK: - 畫法

extension MoneyBoardSky {
    // MARK: 共用小東西

    /// 白底小牌子（建築上方的名字、房貸幾成…）
    @discardableResult
    static func finPill(_ ctx: inout GraphicsContext, _ s: String, centerX cx: CGFloat, y: CGFloat,
                        below: Bool = false, dark: Bool, color: Color, bounds: CGFloat) -> CGRect {
        let t = ctx.resolve(Text(s).font(.system(size: 8, weight: .heavy)).foregroundStyle(color))
        let m = t.measure(in: CGSize(width: 300, height: 40))
        let w = m.width + 10
        let h = m.height + 3
        let x = min(max(2, (cx - w / 2).rounded()), bounds - w - 2)
        let box = CGRect(x: x, y: below ? y : y - h, width: w, height: h)
        ctx.fill(Path(roundedRect: box, cornerRadius: h / 2),
                 with: .color(dark ? Color(tb: 0x1C2646, 0.9) : Color.white.opacity(0.9)))
        ctx.draw(t, at: CGPoint(x: box.midX, y: box.midY), anchor: .center)
        return box
    }

    /// 斜線（還欠銀行的那一截）
    static func finHatch(_ ctx: inout GraphicsContext, _ r: CGRect, color: Color, gap: CGFloat = 4) {
        guard r.width > 0.5, r.height > 0.5 else { return }
        var g = ctx
        g.clip(to: Path(r))
        var p = Path()
        var sx = r.minX - r.height
        while sx < r.maxX {
            p.move(to: CGPoint(x: sx, y: r.maxY))
            p.addLine(to: CGPoint(x: sx + r.height, y: r.minY))
            sx += gap
        }
        g.stroke(p, with: .color(color), lineWidth: 1.1)
    }

    static func finStreet(_ ctx: inout GraphicsContext, width w: CGFloat, ground: CGFloat, bottom: CGFloat,
                          dark: Bool) {
        ctx.fill(Path(CGRect(x: 0, y: ground, width: w, height: bottom - ground)), with: .color(groundFill(dark: dark)))
        let ly = ground + (bottom - ground) / 2
        var lx: CGFloat = 0
        while lx < w {
            ctx.fill(Path(CGRect(x: lx, y: ly - 0.8, width: 7, height: 1.6)),
                     with: .color(Color.white.opacity(dark ? 0.25 : 0.8)))
            lx += 14
        }
    }

    static func finLamp(_ ctx: inout GraphicsContext, x: CGFloat, ground: CGFloat, dark: Bool) {
        let pole = dark ? Color(tb: 0x8A96B8) : Color(tb: 0x5A6478)
        ctx.fill(Path(CGRect(x: x - 0.7, y: ground - 26, width: 1.4, height: 26)), with: .color(pole))
        ctx.fill(Path(CGRect(x: x - 4, y: ground - 27, width: 8, height: 2)), with: .color(pole))
        if dark {
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 4))
                layer.fill(Path(ellipseIn: CGRect(x: x - 7, y: ground - 30, width: 14, height: 10)),
                           with: .color(Color(tb: 0xFFC56B, 0.35)))
            }
        }
        ctx.fill(Path(ellipseIn: CGRect(x: x - 2.4, y: ground - 26, width: 4.8, height: 3)),
                 with: .color(dark ? Color(tb: 0xFFD98A) : Color(tb: 0xFFF4D6)))
    }

    static func finInk(_ theme: MoneyArtTheme, dark: Bool) -> Color {
        dark ? Color(tb: 0xE6ECFF) : theme.ink(.light)
    }

    static func finOwedInk(dark: Bool) -> Color {
        dark ? Color(tb: 0xFF7A8A) : Color(tb: 0xC4243C)
    }

    // MARK: 總覽：資產小鎮

    static func paintTown(_ ctx: inout GraphicsContext, rect r: CGRect, scene s: FinTownScene, dark: Bool, seed: Int) {
        let w = r.width
        let ground = r.maxY - 22
        TripBoardSkyArt.paintFarRow(&ctx, width: w, ground: ground, band: 34, ink: farInk(dark: dark), seed: seed)
        finStreet(&ctx, width: w, ground: ground, bottom: r.maxY, dark: dark)
        finLamp(&ctx, x: 6, ground: ground, dark: dark)
        finLamp(&ctx, x: w - 6, ground: ground, dark: dark)
        let items = s.buildings
        guard !items.isEmpty else {
            // 還沒有任何資產：三塊虛線框的空地
            for k in 0..<3 {
                let x = w * (0.22 + 0.28 * CGFloat(k)) - 26
                ctx.stroke(Path(roundedRect: CGRect(x: x, y: ground - 10, width: 52, height: 10), cornerRadius: 2),
                           with: .color(dark ? Color(tb: 0x7A8FC8, 0.6) : Color.white.opacity(0.95)),
                           style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
            return
        }
        let slot = (w - 16) / CGFloat(items.count)
        let maxV = max(items.map(\.value).max() ?? 1, 1)
        let top = r.minY + 24
        let maxH = max(40, ground - top)
        if items.count > 1 {
            for k in 1..<items.count {
                paintTree(&ctx, at: CGPoint(x: 8 + slot * CGFloat(k) - 4, y: ground), size: 15, dark: dark)
            }
        }
        let owedInk = Color.white.opacity(dark ? 0.55 : 0.8)
        let roof = Color(tb: 0x4B2FB0)
        for (i, b) in items.enumerated() {
            let cx = 8 + slot * (CGFloat(i) + 0.5)
            let th = b.kind.theme
            let h = 36 + (maxH - 36) * CGFloat((max(0, b.value) / maxV).squareRoot())
            let grad = Gradient(colors: [th.topColor, th.bottomColor])
            var labelY = ground - h - 5
            switch b.kind {
            case .realEstate:
                let bw = min(slot * 0.66, 72)
                let bodyH = h * 0.64
                if b.count > 1 {
                    let bx = cx + bw * 0.34
                    let bh = bodyH * 0.7
                    let bw2 = bw * 0.62
                    ctx.fill(Path(CGRect(x: bx - bw2 / 2, y: ground - bh, width: bw2, height: bh)),
                             with: .color(th.bottomColor.opacity(0.5)))
                    var back = Path()
                    back.move(to: CGPoint(x: bx - bw2 / 2 - 3, y: ground - bh))
                    back.addLine(to: CGPoint(x: bx, y: ground - bh - bw2 * 0.4))
                    back.addLine(to: CGPoint(x: bx + bw2 / 2 + 3, y: ground - bh))
                    back.closeSubpath()
                    ctx.fill(back, with: .color(roof.opacity(0.6)))
                }
                ctx.fill(Path(CGRect(x: cx - bw / 2, y: ground - bodyH, width: bw, height: bodyH)),
                         with: .linearGradient(grad, startPoint: CGPoint(x: 0, y: ground - h),
                                               endPoint: CGPoint(x: 0, y: ground)))
                var rf = Path()
                rf.move(to: CGPoint(x: cx - bw / 2 - 6, y: ground - bodyH))
                rf.addLine(to: CGPoint(x: cx, y: ground - h))
                rf.addLine(to: CGPoint(x: cx + bw / 2 + 6, y: ground - bodyH))
                rf.closeSubpath()
                ctx.fill(rf, with: .color(roof))
                ctx.fill(Path(CGRect(x: cx + bw * 0.18, y: ground - h * 0.86, width: 6, height: h * 0.16)),
                         with: .color(roof))
                let windowFill = dark ? Color(tb: 0xFFC56B, 0.85) : Color.white.opacity(0.78)
                let windowSpots: [(CGFloat, CGFloat)] = [(-0.24, 0.22), (0.24, 0.22), (-0.24, 0.52)]
                for (dx, dy) in windowSpots {
                    ctx.fill(Path(CGRect(x: cx + bw * dx - 6, y: ground - bodyH + bodyH * dy, width: 12, height: 10)),
                             with: .color(windowFill))
                }
                ctx.fill(Path(roundedRect: CGRect(x: cx + bw * 0.24 - 6, y: ground - 20, width: 12, height: 20),
                              cornerRadius: 2), with: .color(Color(tb: 0x3A2390, 0.9)))
                if b.owed > 0, b.value > 0 {
                    let oh = bodyH * CGFloat(min(1, b.owed / b.value))
                    finHatch(&ctx, CGRect(x: cx - bw / 2, y: ground - oh, width: bw, height: oh), color: owedInk)
                    if let ol = b.owedLabel {
                        finPill(&ctx, ol, centerX: cx - bw * 0.12, y: ground - oh - 1, dark: dark,
                                color: finOwedInk(dark: dark), bounds: w)
                    }
                }
            case .stock:
                let bw = min(slot * 0.46, 44)
                let body = CGRect(x: cx - bw / 2, y: ground - h, width: bw, height: h)
                ctx.fill(Path(body), with: .linearGradient(grad, startPoint: CGPoint(x: 0, y: body.minY),
                                                           endPoint: CGPoint(x: 0, y: ground)))
                ctx.fill(Path(CGRect(x: body.minX, y: body.minY, width: bw * 0.22, height: h)),
                         with: .color(Color.white.opacity(0.25)))
                var floors = Path()
                var yy = body.minY + 6
                while yy < ground - 3 {
                    floors.move(to: CGPoint(x: body.minX + 3, y: yy))
                    floors.addLine(to: CGPoint(x: body.maxX - 3, y: yy))
                    yy += 6
                }
                ctx.stroke(floors, with: .color(Color.white.opacity(0.35)), lineWidth: 0.7)
                let shape: [CGFloat] = b.rising ? [0.15, 0.32, 0.26, 0.48, 0.44, 0.66, 0.78]
                                                : [0.78, 0.6, 0.66, 0.44, 0.48, 0.3, 0.18]
                var line = Path()
                for (k, f) in shape.enumerated() {
                    let p = CGPoint(x: body.minX + 4 + (bw - 8) * CGFloat(k) / CGFloat(shape.count - 1),
                                    y: ground - h * 0.12 - h * 0.62 * f)
                    if k == 0 { line.move(to: p) } else { line.addLine(to: p) }
                }
                ctx.stroke(line, with: .color(Color.white.opacity(0.95)),
                           style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                ctx.fill(Path(CGRect(x: cx - 0.7, y: body.minY - 9, width: 1.4, height: 9)), with: .color(th.bottomColor))
                labelY = body.minY - 11
            case .savings:
                let bw = min(slot * 0.7, 70)
                let base: CGFloat = 5
                let colH = h * 0.6
                let pedH = h - colH - base * 2
                ctx.fill(Path(CGRect(x: cx - bw / 2 - 4, y: ground - base, width: bw + 8, height: base)),
                         with: .color(th.bottomColor))
                ctx.fill(Path(CGRect(x: cx - bw / 2, y: ground - base - colH, width: bw, height: colH)),
                         with: .color(dark ? Color(tb: 0x22305E) : Color(tb: 0xEAF2FF)))
                for k in 0..<4 {
                    let x = cx - bw / 2 + 4 + CGFloat(k) * (bw - 15) / 3
                    ctx.fill(Path(CGRect(x: x, y: ground - base - colH, width: 7, height: colH)),
                             with: .linearGradient(grad, startPoint: CGPoint(x: 0, y: ground - h),
                                                   endPoint: CGPoint(x: 0, y: ground)))
                }
                ctx.fill(Path(CGRect(x: cx - bw / 2 - 2, y: ground - base - colH - base, width: bw + 4, height: base)),
                         with: .color(th.bottomColor))
                var ped = Path()
                ped.move(to: CGPoint(x: cx - bw / 2 - 5, y: ground - colH - base * 2))
                ped.addLine(to: CGPoint(x: cx, y: ground - h))
                ped.addLine(to: CGPoint(x: cx + bw / 2 + 5, y: ground - colH - base * 2))
                ped.closeSubpath()
                ctx.fill(ped, with: .linearGradient(grad, startPoint: CGPoint(x: 0, y: ground - h),
                                                    endPoint: CGPoint(x: 0, y: ground - colH)))
                let sc = CGPoint(x: cx, y: ground - colH - base * 2 - pedH * 0.42)
                let ss = min(8, pedH * 0.42)
                var shield = Path()
                shield.move(to: CGPoint(x: sc.x, y: sc.y - ss))
                shield.addLine(to: CGPoint(x: sc.x + ss * 0.8, y: sc.y - ss * 0.6))
                shield.addLine(to: CGPoint(x: sc.x + ss * 0.7, y: sc.y + ss * 0.3))
                shield.addLine(to: CGPoint(x: sc.x, y: sc.y + ss))
                shield.addLine(to: CGPoint(x: sc.x - ss * 0.7, y: sc.y + ss * 0.3))
                shield.addLine(to: CGPoint(x: sc.x - ss * 0.8, y: sc.y - ss * 0.6))
                shield.closeSubpath()
                ctx.fill(shield, with: .color(Color.white.opacity(0.95)))
            case .vehicle:
                let cw = min(slot * 0.86, 74)
                let ch: CGFloat = 22
                let cy = ground - 3
                var car = Path()
                car.move(to: CGPoint(x: cx - cw / 2, y: cy))
                car.addLine(to: CGPoint(x: cx - cw / 2, y: cy - ch * 0.55))
                car.addQuadCurve(to: CGPoint(x: cx - cw * 0.3, y: cy - ch * 0.66),
                                 control: CGPoint(x: cx - cw / 2 + 2, y: cy - ch * 0.62))
                car.addLine(to: CGPoint(x: cx - cw * 0.16, y: cy - ch))
                car.addLine(to: CGPoint(x: cx + cw * 0.2, y: cy - ch))
                car.addLine(to: CGPoint(x: cx + cw * 0.36, y: cy - ch * 0.62))
                car.addQuadCurve(to: CGPoint(x: cx + cw / 2, y: cy - ch * 0.3),
                                 control: CGPoint(x: cx + cw / 2, y: cy - ch * 0.55))
                car.addLine(to: CGPoint(x: cx + cw / 2, y: cy))
                car.closeSubpath()
                ctx.fill(car, with: .linearGradient(grad, startPoint: CGPoint(x: 0, y: cy - ch),
                                                    endPoint: CGPoint(x: 0, y: cy)))
                ctx.fill(Path(CGRect(x: cx - cw * 0.12, y: cy - ch * 0.9, width: cw * 0.28, height: ch * 0.28)),
                         with: .color(Color.white.opacity(0.8)))
                if b.owed > 0 {
                    finHatch(&ctx, CGRect(x: cx - cw / 2, y: cy - ch * 0.55, width: cw * 0.4, height: ch * 0.55),
                             color: owedInk, gap: 3)
                }
                for wx in [cx - cw * 0.28, cx + cw * 0.3] {
                    ctx.fill(Path(ellipseIn: CGRect(x: wx - 6, y: cy - 6, width: 12, height: 12)),
                             with: .color(Color(tb: 0x1D2433)))
                    ctx.fill(Path(ellipseIn: CGRect(x: wx - 2.6, y: cy - 2.6, width: 5.2, height: 5.2)),
                             with: .color(Color(tb: 0xC9D3E6)))
                }
                labelY = cy - ch - 5
            }
            finPill(&ctx, b.kind.name + " " + b.label, centerX: cx, y: labelY, dark: dark,
                    color: finInk(th, dark: dark), bounds: w)
        }
    }

    // MARK: 股票：熱氣球

    static func paintBalloons(_ ctx: inout GraphicsContext, rect r: CGRect, scene s: FinBalloonScene,
                              dark: Bool, seed: Int) {
        let w = r.width
        let ground = r.maxY - 14
        ctx.fill(Path(CGRect(x: 0, y: ground, width: w, height: r.maxY - ground)),
                 with: .color(dark ? Color(tb: 0x13301F) : Color(tb: 0xBFE6C8)))
        var rnd = InkRandom(seed &+ 3)
        for _ in 0..<9 {
            let tx = CGFloat(rnd.next()) * w
            paintTree(&ctx, at: CGPoint(x: tx, y: ground + 2), size: CGFloat(8 + rnd.next() * 5), dark: dark)
        }
        let baseY = r.minY + r.height * 0.5
        var costLine = Path()
        costLine.move(to: CGPoint(x: 8, y: baseY))
        costLine.addLine(to: CGPoint(x: w - 8, y: baseY))
        let lineInk = dark ? Color.white.opacity(0.45) : Color(tb: 0x1D3A7A, 0.45)
        ctx.stroke(costLine, with: .color(lineInk), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        let costLabel = ctx.resolve(Text("成本線").font(.system(size: 8, weight: .bold))
            .foregroundStyle(dark ? Color.white.opacity(0.6) : Color(tb: 0x1D3A7A, 0.6)))
        ctx.draw(costLabel, at: CGPoint(x: 10, y: baseY - 2), anchor: .bottomLeading)

        let items = s.balloons
        guard !items.isEmpty else { return }
        let n = items.count
        let maxV = max(items.map(\.value).max() ?? 1, 1)
        let maxAbs = max(10, items.map { abs($0.returnRate) }.max() ?? 10)
        let upRange = baseY - (r.minY + 26)
        let downRange = (ground - 30) - baseY
        for (i, b) in items.enumerated() {
            let x = 62 + (w - 94) * (n == 1 ? 0.5 : CGFloat(i) / CGFloat(n - 1))
            let ratio = CGFloat(min(1, abs(b.returnRate) / maxAbs))
            let y = b.returnRate >= 0 ? baseY - upRange * ratio : baseY + downRange * ratio
            let rr = 8 + 12 * CGFloat((max(0, b.value) / maxV).squareRoot())
            let up = b.returnRate >= 0
            let colors = up ? [Color(tb: 0xFF8A80), Color(tb: 0xD62F3A)] : [Color(tb: 0x7FD8A4), Color(tb: 0x1F8A50)]
            // 籃子與繩子
            let by = y + rr * 1.05 + 7
            var ropes = Path()
            ropes.move(to: CGPoint(x: x - rr * 0.55, y: y + rr * 0.7))
            ropes.addLine(to: CGPoint(x: x - 3, y: by))
            ropes.move(to: CGPoint(x: x + rr * 0.55, y: y + rr * 0.7))
            ropes.addLine(to: CGPoint(x: x + 3, y: by))
            ctx.stroke(ropes, with: .color(dark ? Color.white.opacity(0.5) : Color(tb: 0x5A4636, 0.7)), lineWidth: 0.7)
            ctx.fill(Path(roundedRect: CGRect(x: x - 4, y: by, width: 8, height: 6), cornerRadius: 1.5),
                     with: .color(Color(tb: 0x8A5A34)))
            // 氣球
            var env = Path()
            env.move(to: CGPoint(x: x, y: y + rr * 1.05))
            env.addCurve(to: CGPoint(x: x, y: y - rr * 1.15),
                         control1: CGPoint(x: x - rr * 1.25, y: y + rr * 0.35),
                         control2: CGPoint(x: x - rr * 1.1, y: y - rr * 1.15))
            env.addCurve(to: CGPoint(x: x, y: y + rr * 1.05),
                         control1: CGPoint(x: x + rr * 1.1, y: y - rr * 1.15),
                         control2: CGPoint(x: x + rr * 1.25, y: y + rr * 0.35))
            env.closeSubpath()
            ctx.fill(env, with: .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: x - rr, y: 0),
                                                endPoint: CGPoint(x: x + rr, y: 0)))
            var g = ctx
            g.clip(to: env)
            var gores = Path()
            for k: CGFloat in [-0.45, 0, 0.45] {
                gores.move(to: CGPoint(x: x + rr * k * 0.4, y: y + rr * 1.05))
                gores.addQuadCurve(to: CGPoint(x: x + rr * k * 0.5, y: y - rr * 1.15),
                                   control: CGPoint(x: x + rr * k * 1.6, y: y))
            }
            g.stroke(gores, with: .color(Color.white.opacity(0.55)), lineWidth: 1)
            g.fill(Path(ellipseIn: CGRect(x: x - rr * 0.65, y: y - rr * 0.85, width: rr * 0.55, height: rr * 0.75)),
                   with: .color(Color.white.opacity(0.28)))
            let t = ctx.resolve(Text(b.label).font(.system(size: 8, weight: .heavy))
                .foregroundStyle(dark ? Color.white.opacity(0.85) : Color(tb: 0x0B1B45, 0.85)))
            ctx.draw(t, at: CGPoint(x: x, y: by + 7), anchor: .top)
            if let c = b.callout {
                let m = ctx.resolve(Text(c).font(.system(size: 8, weight: .heavy))).measure(in: CGSize(width: 300, height: 40))
                let tone: MoneyTone = up ? .up : .down
                finPill(&ctx, c, centerX: x + rr + 9 + m.width / 2, y: y - rr * 0.5, below: true, dark: dark,
                        color: tone.color(TripBoardPalette(dark ? .dark : .light)), bounds: w)
            }
        }
    }

    // MARK: 儲蓄險：果園

    static func paintOrchard(_ ctx: inout GraphicsContext, rect r: CGRect, scene s: FinOrchardScene,
                             dark: Bool, seed: Int) {
        let w = r.width
        let ground = r.maxY - 18
        ctx.fill(Path(CGRect(x: 0, y: ground, width: w, height: r.maxY - ground)),
                 with: .color(dark ? Color(tb: 0x14301F) : Color(tb: 0xC6E9CF)))
        let wood = dark ? Color(tb: 0x6B5A48) : Color(tb: 0xC9A57A)
        var fence = Path()
        fence.move(to: CGPoint(x: 0, y: ground - 9))
        fence.addLine(to: CGPoint(x: w, y: ground - 9))
        fence.move(to: CGPoint(x: 0, y: ground - 4))
        fence.addLine(to: CGPoint(x: w, y: ground - 4))
        ctx.stroke(fence, with: .color(wood), lineWidth: 1.5)
        var fx: CGFloat = 4
        while fx < w {
            ctx.fill(Path(CGRect(x: fx, y: ground - 13, width: 2, height: 13)), with: .color(wood))
            fx += 12
        }
        let trees = s.trees
        guard !trees.isEmpty else {
            // 還沒有保單：幾棵剛種下的小苗
            for k in 0..<3 {
                paintTree(&ctx, at: CGPoint(x: w * (0.25 + 0.25 * CGFloat(k)), y: ground), size: 10, dark: dark)
            }
            return
        }
        let n = trees.count
        let maxH = ground - (r.minY + 22)
        for (i, t) in trees.enumerated() {
            let x = 30 + (w - 60) * (n == 1 ? 0.5 : CGFloat(i) / CGFloat(n - 1))
            let size = 0.28 + 0.72 * CGFloat(min(1, max(0, t.progress)))
            let H = maxH * size
            ctx.fill(Path(CGRect(x: x - 2, y: ground - H * 0.42, width: 4, height: H * 0.42)),
                     with: .color(dark ? Color(tb: 0x5B4330) : Color(tb: 0x8A6142)))
            let cr = H * 0.34
            let cy = ground - H * 0.42 - cr * 0.7
            ctx.fill(Path(ellipseIn: CGRect(x: x - cr, y: cy - cr, width: cr * 2, height: cr * 2)),
                     with: .color(dark ? Color(tb: 0x2F7A55) : Color(tb: 0x4DB878)))
            ctx.fill(Path(ellipseIn: CGRect(x: x - cr * 0.95, y: cy - cr * 0.9, width: cr * 1.2, height: cr * 1.1)),
                     with: .color(dark ? Color(tb: 0x3C9467) : Color(tb: 0x6FCE96)))
            ctx.fill(Path(ellipseIn: CGRect(x: x + cr * 0.1, y: cy - cr * 0.6, width: cr * 0.9, height: cr * 0.9)),
                     with: .color(dark ? Color(tb: 0x358A60) : Color(tb: 0x5CC487)))
            if t.progress >= 0.5 {
                let fruits = min(6, Int((t.gain / 6).rounded()) + 1)
                var rnd = InkRandom(seed &+ i &* 13)
                for _ in 0..<fruits {
                    let a = rnd.next() * Double.pi * 2
                    let d = Double(cr) * (0.35 + rnd.next() * 0.45)
                    let fxp = x + CGFloat(cos(a) * d)
                    let fyp = cy + CGFloat(sin(a) * d)
                    ctx.fill(Path(ellipseIn: CGRect(x: fxp - 2.6, y: fyp - 2.6, width: 5.2, height: 5.2)),
                             with: .color(t.foreign ? Color(tb: 0xFFC94D) : Color(tb: 0xFF7A59)))
                }
            }
            // 牌子
            let label = ctx.resolve(Text(t.label).font(.system(size: 8, weight: .heavy))
                .foregroundStyle(dark ? Color(tb: 0xF3E2C4) : Color(tb: 0x6B4A2A)))
            let m = label.measure(in: CGSize(width: 200, height: 40))
            let sw = m.width + 8
            ctx.fill(Path(CGRect(x: x - 0.8, y: ground - 2, width: 1.6, height: 6)), with: .color(Color(tb: 0x8A6142)))
            ctx.fill(Path(roundedRect: CGRect(x: x - sw / 2, y: ground + 2, width: sw, height: 11), cornerRadius: 2),
                     with: .color(dark ? Color(tb: 0x3A2E22) : Color(tb: 0xF3E2C4)))
            ctx.draw(label, at: CGPoint(x: x, y: ground + 7.5), anchor: .center)
        }
    }

    // MARK: 載具：今年這條路

    static func paintYearRoad(_ ctx: inout GraphicsContext, rect r: CGRect, scene s: FinRoadScene,
                              dark: Bool, seed: Int) {
        let w = r.width
        let roadTop = r.maxY - 32
        let roadBot = r.maxY - 12
        var hill = Path()
        hill.move(to: CGPoint(x: 0, y: roadTop))
        hill.addLine(to: CGPoint(x: 0, y: roadTop - 18))
        hill.addQuadCurve(to: CGPoint(x: w * 0.5, y: roadTop - 22), control: CGPoint(x: w * 0.25, y: roadTop - 44))
        hill.addQuadCurve(to: CGPoint(x: w, y: roadTop - 26), control: CGPoint(x: w * 0.75, y: roadTop - 4))
        hill.addLine(to: CGPoint(x: w, y: roadTop))
        hill.closeSubpath()
        ctx.fill(hill, with: .color(dark ? Color(tb: 0x1A2550) : Color(tb: 0xCFE0F2)))
        ctx.fill(Path(CGRect(x: 0, y: roadTop, width: w, height: roadBot - roadTop)),
                 with: .color(dark ? Color(tb: 0x2A3150) : Color(tb: 0x8A93A6)))
        var lx: CGFloat = 0
        while lx < w {
            ctx.fill(Path(CGRect(x: lx, y: (roadTop + roadBot) / 2 - 0.8, width: 8, height: 1.6)),
                     with: .color(Color.white.opacity(0.85)))
            lx += 16
        }
        ctx.fill(Path(CGRect(x: 0, y: roadBot, width: w, height: r.maxY - roadBot)), with: .color(groundFill(dark: dark)))
        let x0: CGFloat = 14
        let x1 = w - 14
        func X(_ t: Double) -> CGFloat { x0 + (x1 - x0) * CGFloat(min(1, max(0, t))) }
        let carX = X(s.today)
        let tickInk = dark ? Color.white.opacity(0.4) : Color(tb: 0x4A5B8C, 0.5)
        let monthInk = dark ? Color(tb: 0xA3B2D9) : Color(tb: 0x4A5B8C)
        for m in 1...12 {
            let xx = X(Double(m - 1) / 12)
            ctx.fill(Path(CGRect(x: xx, y: roadBot, width: 1, height: 3)), with: .color(tickInk))
            if (m % 3 == 1 || m == 12), abs(xx - carX) > 20 {
                let t = ctx.resolve(Text("\(m)月").font(.system(size: 7.5, weight: .bold)).foregroundStyle(monthInk))
                ctx.draw(t, at: CGPoint(x: xx + 2, y: roadBot + 2), anchor: .topLeading)
            }
        }
        // 每個月一個圓標：顏色＝那個月花最多的那一類，大小＝那個月花多少
        let maxAmount = max(s.marks.map(\.amount).max() ?? 1, 1)
        for mk in s.marks {
            let xx = X(mk.t)
            let rr = 5 + 4.5 * CGFloat((mk.amount / maxAmount).squareRoot())
            let cy = roadTop - 8 - rr
            var stem = Path()
            stem.move(to: CGPoint(x: xx, y: roadTop))
            stem.addLine(to: CGPoint(x: xx, y: cy + rr))
            ctx.stroke(stem, with: .color(dark ? Color.white.opacity(0.35) : Color(tb: 0x4A5B8C, 0.35)), lineWidth: 0.8)
            let (fill, glyph): (Color, String) = {
                switch mk.kind {
                case .fuel: return (Color(tb: 0xFF9F38), "油")
                case .charge: return (Color(tb: 0x2FBF71), "電")
                case .care: return (Color(tb: 0x5B7CFA), "修")
                case .park: return (Color(tb: 0x9AA3B5), "停")
                case .other: return (Color(tb: 0x9AA3B5), "其")
                }
            }()
            let dot = Path(ellipseIn: CGRect(x: xx - rr, y: cy - rr, width: rr * 2, height: rr * 2))
            ctx.fill(dot, with: .color(fill))
            ctx.stroke(dot, with: .color(Color.white.opacity(0.9)), lineWidth: 1)
            let gt = ctx.resolve(Text(glyph).font(.system(size: max(6.5, rr * 1.05), weight: .black))
                .foregroundStyle(Color.white))
            ctx.draw(gt, at: CGPoint(x: xx, y: cy), anchor: .center)
        }
        // 接下來要繳：路牌（太近就往上錯開，不超出邊）
        var placed: [CGRect] = []
        for sg in s.signs {
            let t = ctx.resolve(Text(sg.label).font(.system(size: 8, weight: .heavy)).foregroundStyle(Color.white))
            let m = t.measure(in: CGSize(width: 300, height: 40))
            let bw = m.width + 10
            let px = X(sg.t)
            let xx = min(max(px, bw / 2 + 4), w - bw / 2 - 4)
            var box = CGRect(x: xx - bw / 2, y: roadTop - 46, width: bw, height: 14)
            var guardCount = 0
            while placed.contains(where: { $0.insetBy(dx: -2, dy: -1).intersects(box) }), guardCount < 4 {
                box.origin.y -= 17
                guardCount += 1
            }
            placed.append(box)
            ctx.fill(Path(CGRect(x: px - 0.8, y: box.maxY, width: 1.6, height: roadTop - box.maxY)),
                     with: .color(dark ? Color(tb: 0xA3B2D9) : Color(tb: 0x5A6478)))
            ctx.fill(Path(roundedRect: box, cornerRadius: 3), with: .color(Color(tb: 0x1F9D57)))
            ctx.draw(t, at: CGPoint(x: box.midX, y: box.midY), anchor: .center)
        }
        // 車：今天
        let cy = roadTop + 11
        var car = Path()
        car.move(to: CGPoint(x: carX - 18, y: cy))
        car.addLine(to: CGPoint(x: carX - 18, y: cy - 8))
        car.addQuadCurve(to: CGPoint(x: carX - 10, y: cy - 10.5), control: CGPoint(x: carX - 16, y: cy - 10))
        car.addLine(to: CGPoint(x: carX - 6, y: cy - 16))
        car.addLine(to: CGPoint(x: carX + 7, y: cy - 16))
        car.addLine(to: CGPoint(x: carX + 12, y: cy - 10))
        car.addQuadCurve(to: CGPoint(x: carX + 18, y: cy - 4), control: CGPoint(x: carX + 18, y: cy - 9))
        car.addLine(to: CGPoint(x: carX + 18, y: cy))
        car.closeSubpath()
        ctx.fill(car, with: .color(Color(tb: 0x2F6FE0)))
        ctx.stroke(car, with: .color(.white), lineWidth: 1)
        ctx.fill(Path(CGRect(x: carX - 4, y: cy - 14.5, width: 8, height: 4)), with: .color(Color(tb: 0xDCEBFF)))
        for wx in [carX - 10, carX + 10] {
            ctx.fill(Path(ellipseIn: CGRect(x: wx - 3.8, y: cy - 3.8, width: 7.6, height: 7.6)),
                     with: .color(Color(tb: 0x1D2433)))
        }
        let todayT = ctx.resolve(Text("今天").font(.system(size: 8, weight: .heavy)).foregroundStyle(Color(tb: 0x2F6FE0)))
        ctx.draw(todayT, at: CGPoint(x: carX, y: roadBot + 2), anchor: .top)
    }

    // MARK: 房地產：街景

    static func paintStreet(_ ctx: inout GraphicsContext, rect r: CGRect, scene s: FinStreetScene,
                            dark: Bool, seed: Int) {
        let w = r.width
        let ground = r.maxY - 18
        TripBoardSkyArt.paintFarRow(&ctx, width: w, ground: ground, band: 34, ink: farInk(dark: dark), seed: seed)
        finStreet(&ctx, width: w, ground: ground, bottom: r.maxY, dark: dark)
        let homes = s.homes
        guard !homes.isEmpty else {
            for k in 0..<2 {
                let x = w * (0.33 + 0.34 * CGFloat(k)) - 28
                ctx.stroke(Path(roundedRect: CGRect(x: x, y: ground - 10, width: 56, height: 10), cornerRadius: 2),
                           with: .color(dark ? Color(tb: 0x7A8FC8, 0.6) : Color.white.opacity(0.95)),
                           style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
            return
        }
        let th = MoneyArtTheme.finHome
        let grad = Gradient(colors: [th.topColor, th.bottomColor])
        let slot = (w - 16) / CGFloat(homes.count)
        let maxH = ground - (r.minY + 22)
        for k in 0...homes.count {
            let x = 8 + slot * CGFloat(k) + (k == 0 ? 10 : (k == homes.count ? -10 : 0))
            paintTree(&ctx, at: CGPoint(x: x, y: ground), size: 16, dark: dark)
        }
        let owedInk = Color.white.opacity(0.8)
        let windowFill = dark ? Color(tb: 0xFFC56B, 0.85) : Color.white.opacity(0.78)
        for (i, hm) in homes.enumerated() {
            let cx = 8 + slot * (CGFloat(i) + 0.5)
            var g = ctx
            if hm.sold { g.opacity = 0.45 }
            let topY: CGFloat
            let leftX: CGFloat
            if hm.tower {
                let bw = min(slot * 0.42, 56)
                let H = maxH
                let floors = max(hm.floors, max(hm.toFloor + 2, 6))
                let fh = (H - 6) / CGFloat(floors)
                g.fill(Path(CGRect(x: cx - bw / 2, y: ground - H, width: bw, height: H)),
                       with: .color(dark ? Color(tb: 0x2A3A70) : Color(tb: 0x9DB4D3)))
                g.fill(Path(CGRect(x: cx - bw / 2, y: ground - H, width: bw * 0.2, height: H)),
                       with: .color(Color.white.opacity(dark ? 0.06 : 0.25)))
                for f in 0..<floors {
                    let fy = ground - CGFloat(f + 1) * fh
                    g.fill(Path(CGRect(x: cx - bw / 2 + 4, y: fy + 1.4, width: bw - 8, height: max(0.5, fh - 2.8))),
                           with: .color(dark ? Color(tb: 0x3A4A80) : Color(tb: 0xC4D4E8)))
                }
                let from = max(1, hm.fromFloor)
                let to = max(from, hm.toFloor)
                let yTop = ground - CGFloat(to) * fh
                let yBot = ground - CGFloat(from - 1) * fh
                let unit = CGRect(x: cx - bw / 2 - 3, y: yTop, width: bw + 6, height: yBot - yTop)
                g.fill(Path(unit), with: .linearGradient(grad, startPoint: CGPoint(x: 0, y: yTop),
                                                         endPoint: CGPoint(x: 0, y: yBot)))
                if hm.owedFraction > 0 {
                    finHatch(&g, CGRect(x: unit.minX, y: unit.minY, width: unit.width * CGFloat(min(1, hm.owedFraction)),
                                        height: unit.height), color: owedInk, gap: 3)
                }
                let floorLabel = to > from ? "\(from)–\(to)F" : "\(from)F"
                finPill(&g, floorLabel, centerX: cx + bw / 2 + 16, y: yTop - 2, below: true, dark: dark,
                        color: finInk(th, dark: dark), bounds: w)
                topY = ground - H
                leftX = cx - bw / 2
            } else {
                let bw = min(slot * 0.5, 62)
                let floors = min(6, max(1, hm.floors))
                let fh = min(18, (maxH - 22) / CGFloat(floors))
                let bodyH = fh * CGFloat(floors)
                let H = bodyH + 20
                g.fill(Path(CGRect(x: cx - bw / 2, y: ground - bodyH, width: bw, height: bodyH)),
                       with: .linearGradient(grad, startPoint: CGPoint(x: 0, y: ground - bodyH),
                                             endPoint: CGPoint(x: 0, y: ground)))
                for f in 0..<floors {
                    let fy = ground - CGFloat(f + 1) * fh
                    for dx: CGFloat in [-0.24, 0.24] {
                        g.fill(Path(CGRect(x: cx + bw * dx - 5, y: fy + fh * 0.26, width: 10, height: fh * 0.46)),
                               with: .color(windowFill))
                    }
                }
                var rf = Path()
                rf.move(to: CGPoint(x: cx - bw / 2 - 5, y: ground - bodyH))
                rf.addLine(to: CGPoint(x: cx, y: ground - H))
                rf.addLine(to: CGPoint(x: cx + bw / 2 + 5, y: ground - bodyH))
                rf.closeSubpath()
                g.fill(rf, with: .color(Color(tb: 0x4B2FB0)))
                if hm.owedFraction > 0 {
                    let oh = bodyH * CGFloat(min(1, hm.owedFraction))
                    finHatch(&g, CGRect(x: cx - bw / 2, y: ground - oh, width: bw, height: oh), color: owedInk)
                    if let ol = hm.owedLabel {
                        finPill(&g, ol, centerX: cx, y: ground - oh - 1, dark: dark, color: finOwedInk(dark: dark), bounds: w)
                    }
                }
                topY = ground - H
                leftX = cx - bw / 2
            }
            if hm.rented, !hm.sold {
                let px = max(10, leftX - 12)
                g.fill(Path(CGRect(x: px - 0.8, y: ground - 34, width: 1.6, height: 34)),
                       with: .color(dark ? Color(tb: 0xA3B2D9) : Color(tb: 0x8A6142)))
                let t = g.resolve(Text("出租中").font(.system(size: 8, weight: .heavy)).foregroundStyle(Color.white))
                let m = t.measure(in: CGSize(width: 200, height: 40))
                let sign = CGRect(x: px - (m.width + 10) / 2, y: ground - 46, width: m.width + 10, height: 14)
                g.fill(Path(roundedRect: sign, cornerRadius: 3), with: .color(Color(tb: 0x1F9D57)))
                g.draw(t, at: CGPoint(x: sign.midX, y: sign.midY), anchor: .center)
            }
            finPill(&ctx, hm.sold ? "已售・" + hm.label : hm.label, centerX: cx, y: topY - 4, dark: dark,
                    color: hm.sold ? Color(tb: 0x9AA3B5) : finInk(th, dark: dark), bounds: w)
        }
    }

    // MARK: 圖表：極光

    static func paintAurora(_ ctx: inout GraphicsContext, rect r: CGRect, scene s: FinAuroraScene, seed: Int) {
        let w = r.width
        let bot = r.maxY - 14
        let top = r.minY + 22
        // 山影（先畫在後面，極光的下緣淡進山裡）
        var hill = Path()
        hill.move(to: CGPoint(x: 0, y: r.maxY))
        hill.addLine(to: CGPoint(x: 0, y: r.maxY - 12))
        hill.addQuadCurve(to: CGPoint(x: w * 0.55, y: r.maxY - 12), control: CGPoint(x: w * 0.3, y: r.maxY - 26))
        hill.addQuadCurve(to: CGPoint(x: w, y: r.maxY - 16), control: CGPoint(x: w * 0.8, y: r.maxY - 2))
        hill.addLine(to: CGPoint(x: w, y: r.maxY))
        hill.closeSubpath()
        let v = s.values
        guard v.count >= 2 else {
            ctx.fill(hill, with: .color(Color(tb: 0x0B1230)))
            return
        }
        // 上下各留一點：淨資產是負的（貸款比資產多）也畫得出來
        let vmin = v.min() ?? 0
        let vmax = v.max() ?? 1
        let pad = max((vmax - vmin) * 0.12, abs(vmax) * 0.02, 1)
        let lo = vmin - pad
        let hi = vmax + pad * 0.25
        let n = v.count
        func X(_ i: Int) -> CGFloat { 14 + (w - 28) * CGFloat(i) / CGFloat(n - 1) }
        func Y(_ x: Double) -> CGFloat { bot - (bot - top) * CGFloat((x - lo) / (hi - lo)) }
        let pts = v.enumerated().map { CGPoint(x: X($0.offset), y: Y($0.element)) }
        var curve = Path()
        curve.move(to: pts[0])
        for i in 1..<n {
            let p0 = pts[i - 1]
            let p1 = pts[i]
            let mx = (p0.x + p1.x) / 2
            curve.addCurve(to: p1, control1: CGPoint(x: mx, y: p0.y), control2: CGPoint(x: mx, y: p1.y))
        }
        var curtain = curve
        curtain.addLine(to: CGPoint(x: pts[n - 1].x, y: bot))
        curtain.addLine(to: CGPoint(x: pts[0].x, y: bot))
        curtain.closeSubpath()
        // 簾幕
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 2))
            layer.fill(curtain, with: .linearGradient(
                Gradient(stops: [Gradient.Stop(color: Color(tb: 0x7CFFCB, 0.85), location: 0),
                                 Gradient.Stop(color: Color(tb: 0x5EC8FF, 0.45), location: 0.35),
                                 Gradient.Stop(color: Color(tb: 0x7C5CFF, 0.22), location: 0.75),
                                 Gradient.Stop(color: Color(tb: 0x7C5CFF, 0), location: 1)]),
                startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bot)))
        }
        // 一道道光束
        var g = ctx
        g.clip(to: curtain)
        var rnd = InkRandom(seed &+ 17)
        var x: CGFloat = 14
        while x < w - 14 {
            let len = CGFloat(18 + rnd.next() * 40)
            let a = 0.05 + rnd.next() * 0.14
            g.fill(Path(CGRect(x: x, y: top - 10, width: 1.2, height: len + 50)),
                   with: .linearGradient(Gradient(colors: [Color(tb: 0xDCFFF0, a), Color(tb: 0xDCFFF0, 0)]),
                                         startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: top + len + 40)))
            x += 2.5
        }
        // 上緣的光暈＋亮線
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 4))
            layer.stroke(curve, with: .color(Color(tb: 0x7CFFCB, 0.7)), lineWidth: 5)
        }
        ctx.stroke(curve, with: .color(Color(tb: 0xDCFFF0, 0.95)), lineWidth: 1.3)
        ctx.fill(hill, with: .color(Color(tb: 0x0B1230)))
        // 頭尾的標記
        let last = pts[n - 1]
        ctx.fill(MoneyArtPatternLayer.star(center: last, radius: 8), with: .color(Color(tb: 0xFFE29A)))
        if let el = s.endLabel {
            let t = ctx.resolve(Text(el).font(.system(size: 8.5, weight: .heavy)).foregroundStyle(Color(tb: 0xFFE29A)))
            ctx.draw(t, at: CGPoint(x: last.x - 11, y: last.y - 5), anchor: .bottomTrailing)
        }
        let first = pts[0]
        ctx.fill(Path(ellipseIn: CGRect(x: first.x - 2.5, y: first.y - 2.5, width: 5, height: 5)),
                 with: .color(Color(tb: 0xDCFFF0, 0.9)))
        if let sl = s.startLabel {
            let t = ctx.resolve(Text(sl).font(.system(size: 8, weight: .heavy)).foregroundStyle(Color(tb: 0xDCFFF0, 0.85)))
            ctx.draw(t, at: CGPoint(x: first.x + 2, y: first.y - 6), anchor: .bottomLeading)
        }
        for tick in s.ticks where tick.index >= 0 && tick.index < n {
            let t = ctx.resolve(Text(tick.label).font(.system(size: 7.5, weight: .bold)).foregroundStyle(Color(tb: 0xA3B2D9)))
            ctx.draw(t, at: CGPoint(x: X(tick.index), y: r.maxY - 2), anchor: .bottom)
        }
    }
}
