import SwiftUI

// MARK: - 動態相簿的水墨場景與拼貼版型（v25.490）
//
// 使用者定案：只留「水墨山水背景 ＋ 水墨相框 ＋ 拼貼牆」，其餘選項全部移除。
// 這一版把山水的真實度再推一階。
//
// ── 這一版做了什麼讓它更像畫 ──
// 1. 山的輪廓改用四個八度的疊加（fBm），而且頻率不是整數倍——
//    原本兩條正弦疊出來的稜線有明顯週期感，看久了會發現它在重複。
//    峰與谷再分開塑形：峰拉尖、谷壓平，山才不是一排對稱的波浪。
// 2. 霧**夾在山之間**，不是全部蓋在最上面。這是空氣透視的本質：
//    遠山之所以淡，是因為中間隔著空氣。順序一錯，再淡的遠山也像貼紙。
// 3. 每一道稜線加「濕邊」：水墨的山脊是筆鋒壓下去那一下，最濃；
//    山體往下才暈開。只有填色沒有濕邊，看起來像色塊不像筆。
// 4. 近山加短皴筆（山的質感紋理），遠山不加——遠的地方本來就看不到筆觸。
// 5. 水面：近山在水裡的倒影（上下翻轉、更淡、糊掉）＋幾道留白橫紋。
// 6. 松樹長在近山的稜線上（位置跟著稜線一起飄），梅枝掛在右上角。
// 7. 紙紋、月暈、暗角是靜態的，另外一層畫，不跟著每一幀重算。

/// 會動的水墨山水。
///
/// 靜態的東西（紙、月、梅枝、暗角）跟會動的東西（山、霧、水、鳥）分兩層：
/// 靜態那層只畫一次，省掉每秒 24 次的重複勞動。
struct InkLandscapeView: View {
    /// 0...1，整體墨色濃淡
    var density: Double = 1.0

    var body: some View {
        ZStack {
            InkPaperLayer(density: density)
            TimelineView(.periodic(from: .now, by: 1.0 / 24.0)) { timeline in
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    InkScene.draw(&context, size: size, time: t, density: density)
                }
            }
            .ignoresSafeArea()
            // 暗角壓在最上面：讓視線收回畫面中央
            InkVignette()
        }
        .ignoresSafeArea()
    }
}

// MARK: 靜態層（紙、月、梅枝）

private struct InkPaperLayer: View {
    let density: Double

    var body: some View {
        Canvas { context, size in
            // 宣紙：不是純白，暖一點、右下角再沉一點
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.980, green: 0.974, blue: 0.962),
                        Color(red: 0.946, green: 0.940, blue: 0.928),
                        Color(red: 0.902, green: 0.898, blue: 0.890)
                    ]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width * 0.3, y: size.height)))

            moon(&context, size)
            grain(&context, size)
            plumBranch(&context, size)
        }
        .ignoresSafeArea()
    }

    /// 淡淡的月輪。水墨畫裡的月亮是「留白＋一圈淡墨」，不是一顆發光的球。
    private func moon(_ context: inout GraphicsContext, _ size: CGSize) {
        let c = CGPoint(x: size.width * 0.74, y: size.height * 0.17)
        let r = min(size.width, size.height) * 0.085
        context.fill(
            Path(ellipseIn: CGRect(x: c.x - r * 2.6, y: c.y - r * 2.6,
                                   width: r * 5.2, height: r * 5.2)),
            with: .radialGradient(
                Gradient(colors: [Color.white.opacity(0.75), Color.white.opacity(0)]),
                center: c, startRadius: r * 0.6, endRadius: r * 2.6))
        context.stroke(
            Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
            with: .color(.black.opacity(0.07)), lineWidth: 1)
    }

    /// 紙紋。固定種子的細點，數量壓在 140 顆——靜態層只畫一次，不心疼。
    private func grain(_ context: inout GraphicsContext, _ size: CGSize) {
        var random = InkRandom(20260819)
        for _ in 0..<140 {
            let x = random.next() * size.width
            let y = random.next() * size.height
            let r = 0.4 + random.next() * 0.9
            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                with: .color(.black.opacity(0.025 + random.next() * 0.03)))
        }
    }

    /// 右上角的梅枝：一條主幹、兩條分枝、幾朵紅梅。
    /// 這是整張畫的「落款位置」——有它才有中國畫的樣子。
    private func plumBranch(_ context: inout GraphicsContext, _ size: CGSize) {
        let ink = Color.black.opacity(0.62 * density)
        var trunk = Path()
        let start = CGPoint(x: size.width * 1.02, y: size.height * 0.02)
        trunk.move(to: start)
        trunk.addCurve(to: CGPoint(x: size.width * 0.66, y: size.height * 0.165),
                       control1: CGPoint(x: size.width * 0.92, y: size.height * 0.05),
                       control2: CGPoint(x: size.width * 0.80, y: size.height * 0.08))
        context.stroke(trunk, with: .color(ink),
                       style: StrokeStyle(lineWidth: 3.4, lineCap: .round))

        var branch1 = Path()
        branch1.move(to: CGPoint(x: size.width * 0.86, y: size.height * 0.072))
        branch1.addQuadCurve(to: CGPoint(x: size.width * 0.80, y: size.height * 0.195),
                             control: CGPoint(x: size.width * 0.86, y: size.height * 0.14))
        context.stroke(branch1, with: .color(ink.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 1.7, lineCap: .round))

        var branch2 = Path()
        branch2.move(to: CGPoint(x: size.width * 0.75, y: size.height * 0.123))
        branch2.addQuadCurve(to: CGPoint(x: size.width * 0.70, y: size.height * 0.062),
                             control: CGPoint(x: size.width * 0.70, y: size.height * 0.10))
        context.stroke(branch2, with: .color(ink.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

        // 梅花：五個點一朵太細了，用一個紅圓加一點深色花心就夠
        let blossoms: [(CGFloat, CGFloat, CGFloat)] = [
            (0.69, 0.060, 5.0), (0.73, 0.118, 4.2), (0.795, 0.192, 4.6),
            (0.845, 0.118, 3.6), (0.885, 0.063, 4.4), (0.805, 0.072, 3.2)
        ]
        for (ux, uy, r) in blossoms {
            let c = CGPoint(x: size.width * ux, y: size.height * uy)
            context.fill(
                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                with: .color(Color(red: 0.78, green: 0.16, blue: 0.22).opacity(0.85)))
            context.fill(
                Path(ellipseIn: CGRect(x: c.x - r * 0.28, y: c.y - r * 0.28,
                                       width: r * 0.56, height: r * 0.56)),
                with: .color(.black.opacity(0.45)))
        }
    }
}

private struct InkVignette: View {
    var body: some View {
        RadialGradient(colors: [.clear, .black.opacity(0.16)],
                       center: .center, startRadius: 120, endRadius: 520)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .blendMode(.multiply)
    }
}

// MARK: 動態層

enum InkScene {
    /// 幾層山。遠到近，最後一層是前景。
    private static let layers = 5

    static func draw(_ context: inout GraphicsContext, size: CGSize,
                     time: Double, density: Double) {
        // 水面在這個高度，近山要在它上面
        let waterY = size.height * 0.80

        for layer in 0..<layers {
            ridge(&context, size, layer: layer, time: time, density: density, waterY: waterY)
            // 霧夾在山之間（空氣透視）：第 1、2 層之後各鋪一道
            if layer == 1 { mist(&context, size, time: time, band: 0) }
            if layer == 2 { mist(&context, size, time: time, band: 1) }
        }

        water(&context, size, time: time, density: density, waterY: waterY)
        mist(&context, size, time: time, band: 2)
        birds(&context, size, time: time, density: density)
        petals(&context, size, time: time)
    }

    // MARK: 落梅

    /// [v25.492] 從右上角那枝梅飄下來的花瓣。
    ///
    /// 七片就夠——再多就變成櫻吹雪，那是另一個季節的畫。
    /// 每一片的下落速度、起始位置、搖擺相位都不同，而且快落地時會淡掉：
    /// 整片同時消失在同一條線上，一眼就看得出是程式畫的。
    private static func petals(_ context: inout GraphicsContext, _ size: CGSize, time: Double) {
        var random = InkRandom(48219)
        for i in 0..<7 {
            let startX = random.next()
            let phase = random.next()
            let speedSeed = random.next()
            let fallSeconds = 26.0 + speedSeed * 20.0
            let cycle = ((time / fallSeconds) + phase).truncatingRemainder(dividingBy: 1)
            let y = CGFloat(cycle) * size.height * 1.08 - size.height * 0.04
            let sway = CGFloat(sin(time * 0.55 + Double(i) * 1.37) * 18)
            let x = CGFloat(0.58 + startX * 0.40) * size.width + sway
            let r = 2.4 + CGFloat(speedSeed) * 1.9
            // 快到底的時候淡出
            let fade = cycle > 0.82 ? (1 - (cycle - 0.82) / 0.18) : 1
            let petal = Path(ellipseIn: CGRect(x: -r, y: -r * 0.6,
                                               width: r * 2, height: r * 1.2))
                .applying(CGAffineTransform(rotationAngle: time * 0.7 + Double(i))
                    .concatenating(CGAffineTransform(translationX: x, y: y)))
            context.fill(petal,
                         with: .color(Color(red: 0.78, green: 0.26, blue: 0.32)
                            .opacity(0.52 * fade)))
        }
    }

    // MARK: 山

    /// 稜線高度。四個八度疊加，頻率用非整數倍——整數倍會讓波形週期性重複，
    /// 一眼就看出是公式畫的。
    private static func ridgeY(_ u: Double, layer: Int, drift: Double,
                               baseY: CGFloat, amp: CGFloat) -> CGFloat {
        var value = 0.0
        var weight = 1.0
        var freq = 1.5
        for octave in 0..<4 {
            let phase = drift * (1 + Double(octave) * 0.22) + Double(layer) * 5.7 + Double(octave) * 2.3
            value += weight * sin((u * freq + phase) * .pi)
            weight *= 0.5
            freq *= 2.13
        }
        value /= 1.9
        // 峰拉尖、谷壓平：山的輪廓不是對稱的波浪
        let shaped = value >= 0 ? pow(value, 1.45) : value * 0.42
        return baseY - amp * CGFloat(shaped)
    }

    private static func ridgePath(_ size: CGSize, layer: Int, drift: Double,
                                  baseY: CGFloat, amp: CGFloat,
                                  bottom: CGFloat) -> (Path, Path) {
        var fill = Path()
        var crest = Path()
        fill.move(to: CGPoint(x: 0, y: bottom))
        var x: CGFloat = 0
        let step: CGFloat = 4
        var first = true
        while x <= size.width {
            let y = ridgeY(Double(x / max(size.width, 1)), layer: layer,
                           drift: drift, baseY: baseY, amp: amp)
            fill.addLine(to: CGPoint(x: x, y: y))
            if first {
                crest.move(to: CGPoint(x: x, y: y))
                first = false
            } else {
                crest.addLine(to: CGPoint(x: x, y: y))
            }
            x += step
        }
        fill.addLine(to: CGPoint(x: size.width, y: bottom))
        fill.closeSubpath()
        return (fill, crest)
    }

    private static func ridge(_ context: inout GraphicsContext, _ size: CGSize,
                              layer: Int, time: Double, density: Double, waterY: CGFloat) {
        let depth = Double(layer) / Double(layers - 1)       // 0＝最遠
        let baseY = size.height * CGFloat(0.30 + 0.34 * depth)
        let amp = size.height * CGFloat(0.075 + 0.055 * (1 - depth))
        let drift = time * (1.1 + Double(layer) * 2.0) / 140.0
        let bottom = layer == layers - 1 ? size.height : waterY + size.height * 0.06

        let (fill, crest) = ridgePath(size, layer: layer, drift: drift,
                                      baseY: baseY, amp: amp, bottom: bottom)

        // 山體：從稜線往下暈開
        let ink = (0.07 + 0.26 * depth) * density
        context.fill(fill, with: .linearGradient(
            Gradient(colors: [Color.black.opacity(ink),
                              Color.black.opacity(ink * 0.16)]),
            startPoint: CGPoint(x: 0, y: baseY - amp),
            endPoint: CGPoint(x: 0, y: bottom)))

        // 濕邊：筆鋒壓在稜線上那一下，比山體濃
        context.stroke(crest, with: .color(.black.opacity((0.10 + 0.34 * depth) * density)),
                       style: StrokeStyle(lineWidth: 0.6 + 1.5 * CGFloat(depth),
                                          lineCap: .round, lineJoin: .round))

        // 皴筆：只有近的兩層畫得到筆觸
        if layer >= layers - 2 {
            var random = InkRandom(layer * 977 + 31)
            let count = 26
            for _ in 0..<count {
                let u = random.next()
                let x = CGFloat(u) * size.width
                let top = ridgeY(u, layer: layer, drift: drift, baseY: baseY, amp: amp)
                let length = CGFloat(10 + random.next() * 26) * CGFloat(0.6 + depth)
                guard top + length < bottom else { continue }
                var stroke = Path()
                stroke.move(to: CGPoint(x: x, y: top + 3))
                stroke.addQuadCurve(
                    to: CGPoint(x: x + CGFloat(random.next() * 8 - 4), y: top + 3 + length),
                    control: CGPoint(x: x + CGFloat(random.next() * 10 - 5), y: top + length * 0.5))
                context.stroke(stroke,
                               with: .color(.black.opacity((0.05 + random.next() * 0.10) * density)),
                               style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
            }
            // 松樹長在稜線上，跟著山一起飄
            if layer == layers - 1 {
                for (i, u) in [0.17, 0.235, 0.80, 0.86].enumerated() {
                    let x = CGFloat(u) * size.width
                    let y = ridgeY(u, layer: layer, drift: drift, baseY: baseY, amp: amp)
                    pine(&context, at: CGPoint(x: x, y: y + 1),
                         scale: 0.85 + CGFloat(i % 2) * 0.35, density: density)
                }
            }
        }
    }

    /// 一棵松：一條微彎的幹，三層往下垂的枝。
    private static func pine(_ context: inout GraphicsContext, at base: CGPoint,
                             scale: CGFloat, density: Double) {
        let h = 26 * scale
        let ink = Color.black.opacity(0.62 * density)
        var trunk = Path()
        trunk.move(to: base)
        trunk.addQuadCurve(to: CGPoint(x: base.x + 2 * scale, y: base.y - h),
                           control: CGPoint(x: base.x - 2 * scale, y: base.y - h * 0.55))
        context.stroke(trunk, with: .color(ink),
                       style: StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round))

        for i in 0..<3 {
            let level = base.y - h * (0.55 + 0.17 * CGFloat(i))
            let span = (11 - CGFloat(i) * 2.4) * scale
            var bough = Path()
            bough.move(to: CGPoint(x: base.x - span, y: level + 3 * scale))
            bough.addQuadCurve(to: CGPoint(x: base.x + span, y: level + 3 * scale),
                               control: CGPoint(x: base.x, y: level - 4 * scale))
            context.stroke(bough, with: .color(ink.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 1.2 * scale, lineCap: .round))
        }
    }

    // MARK: 霧

    /// 一道橫向飄的霧。三道各自速度不同，而且濃度會慢慢起伏——
    /// 固定濃度的霧看久了會發現它只是在平移。
    private static func mist(_ context: inout GraphicsContext, _ size: CGSize,
                             time: Double, band: Int) {
        let speed = 4.5 + Double(band) * 3.2
        let cycle = ((time * speed / 100).truncatingRemainder(dividingBy: 1.8)) - 0.4
        let cx = CGFloat(cycle) * size.width
        let cy = size.height * CGFloat(0.44 + 0.13 * Double(band))
        let w = size.width * 1.15
        let h = size.height * (0.05 + 0.022 * CGFloat(band))
        let breath = 0.42 + 0.18 * sin(time * 0.21 + Double(band) * 1.7)

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 38))
            layer.fill(
                Path(ellipseIn: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)),
                with: .color(.white.opacity(breath)))
            // 第二團錯開一點，霧才不是一條
            layer.fill(
                Path(ellipseIn: CGRect(x: cx - w * 0.15, y: cy + h * 0.35,
                                       width: w * 0.8, height: h * 0.8)),
                with: .color(.white.opacity(breath * 0.75)))
        }
    }

    // MARK: 水

    /// 水面：近山的倒影（翻過來、更淡、糊掉）＋幾道留白橫紋。
    private static func water(_ context: inout GraphicsContext, _ size: CGSize,
                              time: Double, density: Double, waterY: CGFloat) {
        let drift = time * (1.1 + Double(layers - 1) * 2.0) / 140.0
        let baseY = size.height * CGFloat(0.30 + 0.34 * 1.0)
        let amp = size.height * 0.075

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 6))
            // 把近山的稜線以水平線為軸翻下來
            var reflection = Path()
            reflection.move(to: CGPoint(x: 0, y: waterY))
            var x: CGFloat = 0
            while x <= size.width {
                let y = ridgeY(Double(x / max(size.width, 1)), layer: layers - 1,
                               drift: drift, baseY: baseY, amp: amp)
                reflection.addLine(to: CGPoint(x: x, y: waterY + (waterY - y) * 0.42))
                x += 6
            }
            reflection.addLine(to: CGPoint(x: size.width, y: waterY))
            reflection.closeSubpath()
            layer.fill(reflection, with: .linearGradient(
                Gradient(colors: [Color.black.opacity(0.13 * density), .clear]),
                startPoint: CGPoint(x: 0, y: waterY),
                endPoint: CGPoint(x: 0, y: size.height)))
        }

        // 留白橫紋：水墨的水面是「不畫」畫出來的
        for i in 0..<4 {
            let y = waterY + size.height * CGFloat(0.035 + 0.035 * Double(i))
            let phase = time * 0.12 + Double(i)
            let w = size.width * CGFloat(0.26 + 0.16 * Double(i % 2))
            let x = size.width * CGFloat(0.12 + 0.3 * (sin(phase) * 0.5 + 0.5))
            var line = Path()
            line.move(to: CGPoint(x: x, y: y))
            line.addLine(to: CGPoint(x: x + w, y: y))
            context.stroke(line, with: .color(.white.opacity(0.55)),
                           style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
    }

    // MARK: 鳥

    private static func birds(_ context: inout GraphicsContext, _ size: CGSize,
                              time: Double, density: Double) {
        // 鬆散的人字隊形：三前兩後
        let formation: [(CGFloat, CGFloat, CGFloat)] = [
            (0, 0, 1.0), (-0.055, 0.022, 0.85), (0.052, 0.026, 0.85),
            (-0.105, 0.046, 0.7), (0.100, 0.052, 0.7)
        ]
        let cycle = ((time / 48).truncatingRemainder(dividingBy: 1))
        let headX = CGFloat(cycle) * size.width * 1.3 - size.width * 0.15
        let headY = size.height * 0.20 + CGFloat(sin(time * 0.33) * 10)

        for (dx, dy, scale) in formation {
            let x = headX + dx * size.width
            let y = headY + dy * size.height
            let s: CGFloat = 5.2 * scale
            var path = Path()
            path.move(to: CGPoint(x: x - s, y: y))
            path.addQuadCurve(to: CGPoint(x: x, y: y - s * 0.14),
                              control: CGPoint(x: x - s * 0.52, y: y - s * 0.62))
            path.addQuadCurve(to: CGPoint(x: x + s, y: y),
                              control: CGPoint(x: x + s * 0.52, y: y - s * 0.62))
            context.stroke(path, with: .color(.black.opacity(0.40 * density * Double(scale))),
                           style: StrokeStyle(lineWidth: 1.0 * scale, lineCap: .round))
        }
    }
}

/// 固定種子的亂數（LCG）。要的是「每次都一樣」而不是「夠亂」——
/// 每一幀重骰的話，紙紋與皴筆會閃成雜訊。
struct InkRandom {
    private var state: UInt64

    init(_ seed: Int) {
        state = UInt64(truncatingIfNeeded: seed) &* 6364136223846793005 &+ 1442695040888963407
    }

    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) & 0xFF_FFFF) / Double(0xFF_FFFF)
    }
}

// MARK: - 水墨相框

/// 裱在宣紙上的照片。動態相簿唯一的相框樣式（v25.490 使用者定案）。
struct InkFramedPhoto: View {
    let image: UIImage
    let size: CGSize

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size.width, height: size.height)
            .clipped()
            // 照片邊緣壓一道糊開的墨線，像是拓在紙上的
            .overlay(
                Rectangle()
                    .stroke(Color.black.opacity(0.55), lineWidth: 1.1)
                    .blur(radius: 1.5)
            )
            .padding(13)
            .background(
                Color(red: 0.965, green: 0.952, blue: 0.930)
                    .overlay(
                        RadialGradient(colors: [.black.opacity(0.06), .clear],
                                       center: .topLeading, startRadius: 2, endRadius: 300)
                    )
            )
            .overlay(
                Rectangle()
                    .stroke(Color.black.opacity(0.28), lineWidth: 2.2)
                    .blur(radius: 2.2)
            )
            .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 8)
    }
}

// MARK: - 拼貼牆

/// 拼貼牆上的一張照片
struct WallPhoto: Identifiable, Equatable {
    /// 用照片在相簿裡的序號當 id：同一張不會同時出現兩次
    let id: Int
    let image: UIImage
    /// 落在第幾個位置
    let slot: Int

    static func == (a: WallPhoto, b: WallPhoto) -> Bool { a.id == b.id }
}

/// 拼貼牆的擺放規則。
///
/// 位置不用亂數決定：亂數會讓照片疊成一坨，或整片空著。
/// 用一組排好的落點依序輪流，再加上固定的小偏移，看起來像隨手擺、
/// 其實每一張都有自己的位子。
enum WallLayout {
    /// 以畫面寬高的比例表示的落點
    static let slots: [CGPoint] = [
        CGPoint(x: 0.30, y: 0.27),
        CGPoint(x: 0.71, y: 0.22),
        CGPoint(x: 0.50, y: 0.44),
        CGPoint(x: 0.24, y: 0.60),
        CGPoint(x: 0.76, y: 0.55),
        CGPoint(x: 0.42, y: 0.71),
        CGPoint(x: 0.70, y: 0.78),
        CGPoint(x: 0.27, y: 0.83)
    ]

    /// 同時最多留幾張。再多就看不清楚，而且記憶體要吃好幾張全解析度的圖。
    static let capacity = 8

    static func position(slot: Int, in size: CGSize) -> CGPoint {
        let base = slots[((slot % slots.count) + slots.count) % slots.count]
        // 每一輪偏一點點，第二圈疊上去才不會完全重合
        let round = Double(slot / slots.count)
        let jitterX = CGFloat(sin(round * 2.3 + Double(slot)) * 0.035)
        let jitterY = CGFloat(cos(round * 1.7 + Double(slot) * 0.6) * 0.03)
        return CGPoint(x: (base.x + jitterX) * size.width,
                       y: (base.y + jitterY) * size.height)
    }

    /// 傾斜角度：照片隨手擺在桌上不會是正的
    static func rotation(slot: Int) -> Double {
        let pattern: [Double] = [-7, 5, -3, 8, -5, 3, -8, 6]
        return pattern[((slot % pattern.count) + pattern.count) % pattern.count]
    }

    /// 每一張佔畫面多大
    static func cardArea(_ size: CGSize) -> CGSize {
        CGSize(width: size.width * 0.46, height: size.height * 0.30)
    }
}

// MARK: - 水墨轉場

// 照片落到牆上時用的進場效果：一塊**會長大的墨漬**當遮罩。
// 十幾個位置固定的墨點各自在不同時間開始擴散，邊緣糊開，
// 看起來就像墨在宣紙上洇開。
//
// 兩個關鍵（兩個都踩過）：
//   • 墨點位置必須固定（InkRandom 是固定種子的）。每一幀重骰會閃成雜訊。
//   • ViewModifier 要遵從 Animatable，SwiftUI 才會替 progress 補間；
//     不然它只會在 0 與 1 之間直接跳過去，根本看不到暈開的過程。

private struct InkBlobs: View {
    let progress: Double
    let seed: Int

    var body: some View {
        Canvas { context, size in
            // 邊緣糊掉才像墨，銳利的圓只會像貼紙
            context.addFilter(.blur(radius: 22))
            var random = InkRandom(seed &* 131 &+ 7)
            let longest = max(size.width, size.height)
            let count = 14
            for i in 0..<count {
                let cx = random.next() * size.width
                let cy = random.next() * size.height
                let scale = 0.35 + random.next() * 0.55
                // 每一點開始暈開的時間錯開，才有「一點一點滲出來」的感覺
                let delay = Double(i) / Double(count) * 0.45
                let local = max(0, min(1, (progress - delay) / max(0.0001, 1 - delay)))
                let radius = longest * 0.9 * scale * local
                guard radius > 0.5 else { continue }
                context.fill(
                    Path(ellipseIn: CGRect(x: cx - radius, y: cy - radius,
                                           width: radius * 2, height: radius * 2)),
                    with: .color(.black))
            }
        }
    }
}

private struct InkRevealModifier: ViewModifier, Animatable {
    var progress: Double
    var seed: Int

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .mask(InkBlobs(progress: progress, seed: seed))
            // [v25.492] 照片落在紙上的那一下，墨會往外化開一圈。
            // 只在進場的過程中看得到——progress 到 1 就完全透明。
            .background(
                Circle()
                    .stroke(Color.black.opacity((1 - progress) * 0.16),
                            lineWidth: 1 + 9 * (1 - progress))
                    .blur(radius: 9)
                    .scaleEffect(0.45 + progress * 1.15)
                    .allowsHitTesting(false)
            )
    }
}

extension AnyTransition {
    /// 水墨暈開。離場用淡出——兩張同時做遮罩會互相穿幫。
    static func inkWash(seed: Int) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(active: InkRevealModifier(progress: 0, seed: seed),
                                 identity: InkRevealModifier(progress: 1, seed: seed)),
            removal: .opacity)
    }
}

// MARK: - 落款與鈐印（v25.492）
//
// 中國畫的三件套是「畫、題款、印」。前面兩版把畫做出來了，題款與印一直缺著——
// 那正是「看起來像水墨」與「看起來是一幅畫」之間的差別。
//
// 題款直書（由上往下、字與字之間收緊），印是紅底白文的方章，略微歪一點：
// 蓋章本來就不會蓋得完全正。

/// 直書的墨字
struct VerticalInkText: View {
    let text: String
    var size: CGFloat = 16
    var weight: Font.Weight = .regular
    var opacity: Double = 0.78

    var body: some View {
        VStack(spacing: size * 0.12) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                Text(String(ch))
                    .font(.system(size: size, weight: weight, design: .serif))
                    .foregroundStyle(Color.black.opacity(opacity))
                    .fixedSize()
            }
        }
    }
}

/// 鈐印：紅底白文的方章
struct InkSeal: View {
    var text: String = "美好"
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.1)
                .fill(Color(red: 0.72, green: 0.14, blue: 0.16).opacity(0.88))
            VStack(spacing: -size * 0.06) {
                ForEach(Array(text.prefix(2).enumerated()), id: \.offset) { _, ch in
                    Text(String(ch))
                        .font(.system(size: size * 0.38, weight: .bold, design: .serif))
                        .foregroundStyle(Color(red: 0.98, green: 0.96, blue: 0.94))
                }
            }
        }
        .frame(width: size, height: size)
        // 蓋章不會正，歪一點才像手蓋的
        .rotationEffect(.degrees(-3))
        .shadow(color: .black.opacity(0.12), radius: 1.5, x: 0.5, y: 1)
    }
}

/// 畫面左側的落款：相簿名、日期、印。
struct InkColophon: View {
    let title: String
    let dateText: String?

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            VerticalInkText(text: title, size: 17, weight: .semibold, opacity: 0.80)
            if let dateText {
                VerticalInkText(text: dateText, size: 10.5, opacity: 0.55)
            }
            InkSeal()
        }
    }
}

// MARK: - 拼貼牆上的一張（v25.492）

/// 牆上的照片。
///
/// 兩件事讓它不只是「貼上去」：
///   • 每一張都在很慢地呼吸（五、六秒一個來回，各自錯開），幅度小到說不出
///     哪裡在動，但畫面不會死。
///   • 舊的照片退後一點、淡一點——視線自然會落在最新落下的那一張。
struct WallCard: View {
    let item: WallPhoto
    let cardSize: CGSize
    let container: CGSize
    /// 0＝最新落下的那一張
    let age: Int

    @State private var breathing = false

    var body: some View {
        InkFramedPhoto(image: item.image, size: cardSize)
            .rotationEffect(.degrees(WallLayout.rotation(slot: item.slot)
                                     + (breathing ? 0.9 : -0.9)))
            .scaleEffect((breathing ? 1.005 : 0.995) * (age == 0 ? 1.0 : 0.97))
            .opacity(age == 0 ? 1 : max(0.5, 1 - Double(age) * 0.075))
            .position(WallLayout.position(slot: item.slot, in: container))
            .onAppear {
                // 每張的週期都不一樣，不然整面牆會一起起伏，像在呼吸的是牆不是照片
                withAnimation(.easeInOut(duration: 5.4 + Double(item.slot % 5) * 0.8)
                    .repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
    }
}
