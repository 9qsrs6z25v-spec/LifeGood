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

    /// [v25.498] 停格。
    ///
    /// TimelineView(.periodic) 只要還在畫面上就會一直叫 Canvas 重畫，
    /// **App 退到背景、或被系統畫面蓋住（截圖編輯器就是）都不會停**。
    /// 使用者回報截圖後編輯畫面會卡，原因就在這：底下兩個全螢幕 Canvas
    /// 還在每秒各算二十四次。
    ///
    /// 停格的時候換成一個不會滴答的 Canvas，畫同一個固定時刻——
    /// 畫面長得一樣，只是不再重算。
    var paused: Bool = false

    var body: some View {
        ZStack {
            InkPaperLayer(density: density)
            if paused {
                Canvas { context, size in
                    InkScene.draw(&context, size: size, time: 0, density: density)
                }
                .ignoresSafeArea()
            } else {
                TimelineView(.periodic(from: .now, by: 1.0 / 24.0)) { timeline in
                    Canvas { context, size in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        InkScene.draw(&context, size: size, time: t, density: density)
                    }
                }
                .ignoresSafeArea()
            }
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
            fibers(&context, size)
            grain(&context, size)
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
    ///
    /// [v25.494] 另外加 26 根纖維：宣紙是縱橫交錯的纖維壓出來的，
    /// 迎光看得到一根一根的筋。只有點沒有筋，看起來像噴砂的紙。
    private func fibers(_ context: inout GraphicsContext, _ size: CGSize) {
        var random = InkRandom(77131)
        for _ in 0..<26 {
            let x = random.next() * size.width
            let y = random.next() * size.height
            let length = 40 + random.next() * 160
            let angle = (random.next() - 0.5) * 0.5          // 幾乎是橫的
            var fiber = Path()
            fiber.move(to: CGPoint(x: x, y: y))
            fiber.addLine(to: CGPoint(x: x + CGFloat(cos(angle) * length),
                                      y: y + CGFloat(sin(angle) * length)))
            context.stroke(fiber,
                           with: .color(.black.opacity(0.018 + random.next() * 0.022)),
                           style: StrokeStyle(lineWidth: 0.6, lineCap: .round))
        }
    }

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
        // [v25.496] v25.494 讓整幅畫的墨色每兩分鐘濃淡一次（±7%），理由是
        // 「固定濃度看久了會平」。那個理由站不住：畫掛在牆上，墨不會自己變淡。
        // 而且那個係數是乘在**所有東西**上的，包括山——等於山也在呼吸。
        // 畫面要活，靠的是會動的東西真的在動，不是讓不動的東西微微發抖。
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

    /// [v25.492] 從右上角那枝梅飄下來的花瓣（**遠處那幾片**，前景另有一組）。
    ///
    /// 七片就夠——再多就變成櫻吹雪，那是另一個季節的畫。
    /// 每一片的下落速度、起始位置、搖擺相位都不同，而且快落地時會淡掉：
    /// 整片同時消失在同一條線上，一眼就看得出是程式畫的。
    ///
    /// [v25.493] 這一組改小、改淡、掉得慢——它們在照片後面，是遠景。
    private static func petals(_ context: inout GraphicsContext, _ size: CGSize, time: Double) {
        var random = InkRandom(48219)
        for i in 0..<5 {
            let startX = random.next()
            let phase = random.next()
            let speedSeed = random.next()
            let fallSeconds = 34.0 + speedSeed * 22.0
            let cycle = ((time / fallSeconds) + phase).truncatingRemainder(dividingBy: 1)
            let y = CGFloat(cycle) * size.height * 1.08 - size.height * 0.04
            let sway = CGFloat(sin(time * 0.55 + Double(i) * 1.37) * 18)
            let x = CGFloat(0.58 + startX * 0.40) * size.width + sway
            let r = 1.9 + CGFloat(speedSeed) * 1.3
            // 快到底的時候淡出
            let fade = cycle > 0.82 ? (1 - (cycle - 0.82) / 0.18) : 1
            let petal = InkBrush.petalPath(length: r * 2, width: r * 1.0)
                .applying(CGAffineTransform(rotationAngle: time * 0.7 + Double(i))
                    .concatenating(CGAffineTransform(translationX: x, y: y)))
            context.fill(petal,
                         with: .color(Color(red: 0.78, green: 0.26, blue: 0.32)
                            .opacity(0.34 * fade)))
        }
    }

    // MARK: 山

    /// 稜線高度。四個八度疊加，頻率用非整數倍——整數倍會讓波形週期性重複，
    /// 一眼就看出是公式畫的。
    /// [v25.496] 拿掉了 drift 參數。
    ///
    /// 原本每一層山的波形都隨時間推移（越近的推得越快，想做出視差），
    /// 結果是**山的形狀一直在變**——稜線會長出新的峰、舊的峰會縮回去。
    /// 使用者講得很準：會動的應該限制在小東西，樹、花草、落葉；山不會動。
    /// 山是一幅畫裡唯一的定點，它一動，前面所有「這是一幅畫」的功夫都白做了。
    private static func ridgeY(_ u: Double, layer: Int,
                               baseY: CGFloat, amp: CGFloat) -> CGFloat {
        var value = 0.0
        var weight = 1.0
        var freq = 1.5
        for octave in 0..<4 {
            let phase = Double(layer) * 5.7 + Double(octave) * 2.3
            value += weight * sin((u * freq + phase) * .pi)
            weight *= 0.5
            freq *= 2.13
        }
        value /= 1.9
        // 峰拉尖、谷壓平：山的輪廓不是對稱的波浪
        let shaped = value >= 0 ? pow(value, 1.45) : value * 0.42
        return baseY - amp * CGFloat(shaped)
    }

    private static func ridgePath(_ size: CGSize, layer: Int,
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
                           baseY: baseY, amp: amp)
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
        let bottom = layer == layers - 1 ? size.height : waterY + size.height * 0.06

        let (fill, crest) = ridgePath(size, layer: layer,
                                      baseY: baseY, amp: amp, bottom: bottom)

        // 山體：從稜線往下暈開
        let ink = (0.07 + 0.26 * depth) * density
        context.fill(fill, with: .linearGradient(
            Gradient(colors: [Color.black.opacity(ink),
                              Color.black.opacity(ink * 0.16)]),
            startPoint: CGPoint(x: 0, y: baseY - amp),
            endPoint: CGPoint(x: 0, y: bottom)))

        // [v25.494] 墨分五色：稜線底下再壓一道重墨，山才有體積。
        // 只有一層平塗的山是剪影，不是畫。
        if layer >= 2 {
            let bandHeight = amp * 0.5
            var band = Path()
            var x: CGFloat = 0
            let step: CGFloat = 6
            var points: [CGPoint] = []
            while x <= size.width {
                let u = Double(x / max(size.width, 1))
                let y = ridgeY(u, layer: layer, baseY: baseY, amp: amp)
                points.append(CGPoint(x: x, y: y))
                x += step
            }
            guard let head = points.first else { return }
            band.move(to: head)
            for pt in points.dropFirst() { band.addLine(to: pt) }
            for pt in points.reversed() {
                band.addLine(to: CGPoint(x: pt.x, y: pt.y + bandHeight))
            }
            band.closeSubpath()
            context.fill(band, with: .linearGradient(
                Gradient(colors: [Color.black.opacity(0.21 * depth * density), .clear]),
                startPoint: CGPoint(x: 0, y: baseY - amp),
                endPoint: CGPoint(x: 0, y: baseY - amp + bandHeight * 1.5)))

            // [v25.495] 緊貼稜線再壓一道更短更重的：山脊是整座山最暗的地方，
            // 只有一道慢慢淡下去的帶子，山還是看起來像一張剪紙。
            var crestBand = Path()
            crestBand.move(to: head)
            for pt in points.dropFirst() { crestBand.addLine(to: pt) }
            for pt in points.reversed() {
                crestBand.addLine(to: CGPoint(x: pt.x, y: pt.y + bandHeight * 0.24))
            }
            crestBand.closeSubpath()
            context.fill(crestBand, with: .linearGradient(
                Gradient(colors: [Color.black.opacity(0.17 * depth * density), .clear]),
                startPoint: CGPoint(x: 0, y: baseY - amp),
                endPoint: CGPoint(x: 0, y: baseY - amp + bandHeight * 0.3)))
        }

        // [v25.494] 濕邊改成「飛白」：一條連續等粗的線是向量圖，不是毛筆。
        // 真的筆鋒走過宣紙，墨會斷斷續續、粗細不均——那叫飛白，
        // 是「這是手畫的」最強的訊號。遠山維持細線（遠到看不見筆觸）。
        if layer >= 2 {
            var brush = InkRandom(layer * 613 + 7)
            let segments = 34
            var previous: CGPoint?
            for i in 0...segments {
                let u = Double(i) / Double(segments)
                let point = CGPoint(x: CGFloat(u) * size.width,
                                    y: ridgeY(u, layer: layer,
                                              baseY: baseY, amp: amp))
                defer { previous = point }
                guard let start = previous else { continue }
                let bite = brush.next()
                if bite < 0.14 { continue }      // 這一段紙面沒吃到墨
                var segment = Path()
                segment.move(to: start)
                segment.addLine(to: point)
                context.stroke(
                    segment,
                    with: .color(.black.opacity((0.10 + 0.32 * depth) * density
                                                * (0.45 + bite * 0.75))),
                    style: StrokeStyle(
                        lineWidth: (0.6 + 1.6 * CGFloat(depth)) * CGFloat(0.55 + bite * 0.9),
                        lineCap: .round))
            }
        } else {
            context.stroke(crest, with: .color(.black.opacity((0.10 + 0.34 * depth) * density)),
                           style: StrokeStyle(lineWidth: 0.6 + 1.5 * CGFloat(depth),
                                              lineCap: .round, lineJoin: .round))
        }

        // 皴筆：只有近的兩層畫得到筆觸
        if layer >= layers - 2 {
            var random = InkRandom(layer * 977 + 31)
            let count = 26
            for _ in 0..<count {
                let u = random.next()
                let x = CGFloat(u) * size.width
                let top = ridgeY(u, layer: layer, baseY: baseY, amp: amp)
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
            // [v25.496] 松樹長在稜線上，位置固定；會動的是枝葉。
            // 每棵的相位錯開——整排一起晃就像被按了同一個開關。
            if layer == layers - 1 {
                for (i, u) in [0.17, 0.235, 0.80, 0.86].enumerated() {
                    let x = CGFloat(u) * size.width
                    let y = ridgeY(u, layer: layer, baseY: baseY, amp: amp)
                    let sway = CGFloat(sin(time * 0.45 + Double(i) * 1.7) * 1.1
                                       + sin(time * 0.27 + Double(i) * 0.9) * 0.7)
                    pine(&context, at: CGPoint(x: x, y: y + 1),
                         scale: 0.85 + CGFloat(i % 2) * 0.35,
                         density: density, sway: sway)
                }
            }
        }
    }

    /// 一棵松：一條微彎的幹，三層往下垂的枝。
    /// `sway` 是這一瞬間風吹的幅度（點）——根不動，越往梢擺得越多。
    private static func pine(_ context: inout GraphicsContext, at base: CGPoint,
                             scale: CGFloat, density: Double, sway: CGFloat) {
        // [v25.495] 幹改成會收鋒的一筆。等粗的 1.5pt 直線在真機上像一根天線，
        // 樹幹本來就是下粗上細的。
        let h = 30 * scale
        let ink = Color.black.opacity(0.68 * density)
        InkBrush.taper(&context,
                       from: base,
                       control1: CGPoint(x: base.x - 2.4 * scale, y: base.y - h * 0.45),
                       control2: CGPoint(x: base.x + 1.2 * scale + sway * 0.5,
                                         y: base.y - h * 0.8),
                       to: CGPoint(x: base.x + 2 * scale + sway, y: base.y - h),
                       startWidth: 2.6 * scale, endWidth: 0.7 * scale, color: ink)

        for i in 0..<3 {
            let level = base.y - h * (0.5 + 0.18 * CGFloat(i))
            let span = (13 - CGFloat(i) * 2.6) * scale
            // 一層枝葉分左右兩筆，各自從幹上收出去
            // 高處的枝擺得比低處多（0.4→0.9），一棵樹才不是整塊在平移
            let reach = sway * (0.4 + 0.25 * CGFloat(i))
            for side in [CGFloat(-1), 1] {
                InkBrush.taper(&context,
                               from: CGPoint(x: base.x + reach * 0.2, y: level + 2 * scale),
                               control1: CGPoint(x: base.x + side * span * 0.4 + reach * 0.5,
                                                y: level - 2 * scale),
                               control2: CGPoint(x: base.x + side * span * 0.8 + reach * 0.8,
                                                y: level + 1 * scale),
                               to: CGPoint(x: base.x + side * span + reach,
                                           y: level + 4 * scale),
                               startWidth: 2.0 * scale, endWidth: 0.5 * scale,
                               color: ink.opacity(0.82))
            }
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

        // [v25.494] 霧改成「把墨擦掉」，不是「蓋一層白」。
        //
        // 水墨的雲霧是留白——紙本來就是白的，畫的時候那一塊根本不落墨。
        // 蓋白色是油畫的思路，蓋出來的霧永遠浮在山前面像一團棉花；
        // 擦掉之後，山是「溶進」霧裡的，而且露出來的是真正的紙色
        //（紙在另一層畫，擦掉這一層就會看見它）。
        var eraser = context
        eraser.blendMode = .destinationOut
        eraser.addFilter(.blur(radius: 40))
        eraser.fill(
            Path(ellipseIn: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)),
            with: .color(.black.opacity(min(1, breath * 1.55))))
        eraser.fill(
            Path(ellipseIn: CGRect(x: cx - w * 0.15, y: cy + h * 0.35,
                                   width: w * 0.8, height: h * 0.8)),
            with: .color(.black.opacity(min(1, breath * 1.1))))

        // 再補一點點白：霧本身會亮一些，純擦會顯得太空
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 44))
            layer.fill(
                Path(ellipseIn: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)),
                with: .color(.white.opacity(breath * 0.42)))
        }
    }

    // MARK: 水

    /// 水面：近山的倒影（翻過來、更淡、糊掉）＋幾道留白橫紋。
    private static func water(_ context: inout GraphicsContext, _ size: CGSize,
                              time: Double, density: Double, waterY: CGFloat) {
        let baseY = size.height * CGFloat(0.30 + 0.34 * 1.0)
        let amp = size.height * 0.075

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 6))
            // 把近山的稜線以水平線為軸翻下來
            var reflection = Path()
            reflection.move(to: CGPoint(x: 0, y: waterY))
            var x: CGFloat = 0
            while x <= size.width {
                let u = Double(x / max(size.width, 1))
                // 倒影照的是那座不動的山；會晃的是水面，不是山
                let y = ridgeY(u, layer: layers - 1, baseY: baseY, amp: amp)
                // [v25.494] 水面會晃：倒影不是鏡子，是一面在動的水。
                // 不加這個扭曲，倒影看起來就是把山貼過去而已。
                let ripple = CGFloat(sin(u * 11 + time * 1.3) * 2.2
                                     + sin(u * 23 - time * 0.9) * 1.1)
                reflection.addLine(to: CGPoint(x: x,
                                               y: waterY + (waterY - y) * 0.42 + ripple))
                x += 6
            }
            reflection.addLine(to: CGPoint(x: size.width, y: waterY))
            reflection.closeSubpath()
            layer.fill(reflection, with: .linearGradient(
                Gradient(colors: [Color.black.opacity(0.13 * density), .clear]),
                startPoint: CGPoint(x: 0, y: waterY),
                endPoint: CGPoint(x: 0, y: size.height)))
        }

        // [v25.495] 水面先鋪一層極淡的墨。
        //
        // 上一版沒有這一層：倒影只有 0.13 的墨，再往下就是空白的紙，
        // 然後我在那片白紙上又畫了四條不透明的白線——白壓白，看起來不是
        // 留白，是四條發亮的槓。留白要有墨才看得出來，所以先給水一點調子。
        var wash = Path()
        wash.addRect(CGRect(x: 0, y: waterY, width: size.width,
                            height: size.height - waterY))
        context.fill(wash, with: .linearGradient(
            Gradient(colors: [Color.black.opacity(0.085 * density),
                              Color.black.opacity(0.015 * density)]),
            startPoint: CGPoint(x: 0, y: waterY),
            endPoint: CGPoint(x: 0, y: size.height)))

        // 留白橫紋：水墨的水面是「不畫」畫出來的。
        // 兩頭要收掉——真的留白沒有邊界，有頭有尾的白線就是一條白線。
        for i in 0..<5 {
            let y = waterY + size.height * CGFloat(0.03 + 0.032 * Double(i))
            let phase = time * 0.12 + Double(i)
            let w = size.width * CGFloat(0.30 + 0.18 * Double(i % 2))
            let x = size.width * CGFloat(0.08 + 0.32 * (sin(phase) * 0.5 + 0.5))
            var line = Path()
            line.move(to: CGPoint(x: x, y: y))
            line.addLine(to: CGPoint(x: x + w, y: y))
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 2.6))
                layer.stroke(line, with: .linearGradient(
                    Gradient(stops: [
                        .init(color: .white.opacity(0), location: 0),
                        .init(color: .white.opacity(0.46), location: 0.28),
                        .init(color: .white.opacity(0.46), location: 0.70),
                        .init(color: .white.opacity(0), location: 1)]),
                    startPoint: CGPoint(x: x, y: y),
                    endPoint: CGPoint(x: x + w, y: y)),
                    style: StrokeStyle(lineWidth: 2.2 + CGFloat(i % 2) * 1.4,
                                       lineCap: .round))
            }
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
            // [v25.498] 半徑從 14 收到 9。牆上同時有八張卡片，每一張都在做
            // 永不停止的呼吸動畫，所以這層陰影每一幀都要重算八次模糊——
            // 半徑越大越貴，而紙照片本來也不會有那麼深的影子。
            .shadow(color: .black.opacity(0.30), radius: 9, x: 0, y: 6)
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
    /// 以畫面寬高的比例表示的落點。
    ///
    /// [v25.495] 兩件事跟上一版不同：
    ///
    /// 1. **左邊讓出來。** 題款與鈐印寫在畫面左緣（約到寬度的 0.13），
    ///    上一版的落點左到 0.24、卡片半寬 0.25，等於每一張都壓在字上，
    ///    真機上「勇闖福岡親子行」有一半是看不見的。中國畫把款題在留白處，
    ///    那塊留白就不該再放東西。
    /// 2. **先鋪開再補滿。** 上一版前四個落點是 0.27／0.22／0.44／0.60，
    ///    照片不多的時候全擠在上半，下面空一大片。現在前四張就把上下站滿。
    static let slots: [CGPoint] = [
        CGPoint(x: 0.52, y: 0.26),
        CGPoint(x: 0.60, y: 0.71),
        CGPoint(x: 0.43, y: 0.47),
        CGPoint(x: 0.67, y: 0.31),
        CGPoint(x: 0.47, y: 0.83),
        CGPoint(x: 0.70, y: 0.55),
        CGPoint(x: 0.41, y: 0.64),
        CGPoint(x: 0.58, y: 0.39)
    ]

    /// 同時最多留幾張。再多就看不清楚，而且記憶體要吃好幾張全解析度的圖。
    static let capacity = 8

    static func position(slot: Int, in size: CGSize) -> CGPoint {
        let base = slots[((slot % slots.count) + slots.count) % slots.count]
        // 每一輪偏一點點，第二圈疊上去才不會完全重合
        let round = Double(slot / slots.count)
        // 偏移幅度收小：再大就會把卡片推回題款那一欄
        let jitterX = CGFloat(sin(round * 2.3 + Double(slot)) * 0.018)
        let jitterY = CGFloat(cos(round * 1.7 + Double(slot) * 0.6) * 0.03)
        return CGPoint(x: (base.x + jitterX) * size.width,
                       y: (base.y + jitterY) * size.height)
    }

    /// 傾斜角度：照片隨手擺在桌上不會是正的
    static func rotation(slot: Int) -> Double {
        let pattern: [Double] = [-7, 5, -3, 8, -5, 3, -8, 6]
        return pattern[((slot % pattern.count) + pattern.count) % pattern.count]
    }

    /// 每一張佔畫面多大。
    /// [v25.495] 0.46 → 0.42：卡片要旋轉 ±8°，轉過之後的實際寬度比這個數字
    /// 大一成，不縮一點就擠不進「讓開題款」之後剩下的範圍。
    static func cardArea(_ size: CGSize) -> CGSize {
        CGSize(width: size.width * 0.42, height: size.height * 0.30)
    }
}

// MARK: - 筆（v25.495）

/// 毛筆的兩件事：**線條會收鋒**，**花不是圓點**。
///
/// 等粗的線是向量圖工具畫的，不是筆——筆鋒落紙重、提起來輕，一條枝子
/// 從根到梢一定越來越細。SwiftUI 的 `stroke` 只能給一個固定寬度，
/// 所以這裡沿著曲線取樣，自己把兩側的輪廓算出來，填成一塊實心的形狀。
enum InkBrush {
    /// 三次貝茲曲線上 t 處的點
    static func point(_ p0: CGPoint, _ c0: CGPoint, _ c1: CGPoint,
                      _ p1: CGPoint, _ t: CGFloat) -> CGPoint {
        // 權重先各自算好。四個項目寫成一條式子的話，光是推導那幾個
        // 整數字面量的型別就能讓編譯器卡到放棄（expression too complex）。
        let u: CGFloat = 1 - t
        let w0: CGFloat = u * u * u
        let w1: CGFloat = 3 * u * u * t
        let w2: CGFloat = 3 * u * t * t
        let w3: CGFloat = t * t * t
        let x: CGFloat = w0 * p0.x + w1 * c0.x + w2 * c1.x + w3 * p1.x
        let y: CGFloat = w0 * p0.y + w1 * c0.y + w2 * c1.y + w3 * p1.y
        return CGPoint(x: x, y: y)
    }

    /// 一筆有粗細變化的線：from 粗、to 細（或反過來）。
    static func taper(_ context: inout GraphicsContext,
                      from p0: CGPoint, control1 c0: CGPoint,
                      control2 c1: CGPoint, to p1: CGPoint,
                      startWidth: CGFloat, endWidth: CGFloat,
                      color: Color, steps: Int = 24) {
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let here = point(p0, c0, c1, p1, t)
            // 方向取前後各一小段，端點才不會退化成零向量
            let back = point(p0, c0, c1, p1, max(t - 0.02, 0))
            let ahead = point(p0, c0, c1, p1, min(t + 0.02, 1))
            var dx = ahead.x - back.x
            var dy = ahead.y - back.y
            let len = max(sqrt(dx * dx + dy * dy), 0.0001)
            dx /= len; dy /= len
            let half = (startWidth + (endWidth - startWidth) * t) / 2
            left.append(CGPoint(x: here.x - dy * half, y: here.y + dx * half))
            right.append(CGPoint(x: here.x + dy * half, y: here.y - dx * half))
        }
        guard let head = left.first else { return }
        var path = Path()
        path.move(to: head)
        for pt in left.dropFirst() { path.addLine(to: pt) }
        for pt in right.reversed() { path.addLine(to: pt) }
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }

    /// 一片花瓣：一頭尖、一頭圓（橢圓畫出來是藥丸，不是花）
    static func petalPath(length: CGFloat, width: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: -length * 0.5, y: 0))          // 尖端（連在枝上那頭）
        p.addQuadCurve(to: CGPoint(x: length * 0.5, y: 0),
                       control: CGPoint(x: 0, y: -width))
        p.addQuadCurve(to: CGPoint(x: -length * 0.5, y: 0),
                       control: CGPoint(x: 0, y: width))
        p.closeSubpath()
        return p
    }

    /// 一朵梅：五瓣、一點花心、幾根蕊。
    ///
    /// 上一版是「一個紅圓加一點深色花心」，理由是這個尺寸畫五瓣會糊成一團。
    /// 實際跑出來才知道判斷錯了——440pt 寬的螢幕上一朵花半徑 5pt，
    /// 在 3x 螢幕是 30 個像素，五瓣綽綽有餘。而完美的正圓一看就是程式畫的，
    /// 整枝梅因此像一張流程圖。
    static func plumBlossom(_ context: inout GraphicsContext, at center: CGPoint,
                            radius r: CGFloat, rotation: Double, tone: Double) {
        let red = Color(red: 0.72, green: 0.14, blue: 0.20)
        // 先一層很淡的暈：花要滲進紙裡，不是貼上去的
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: r * 0.55))
            layer.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r,
                                              width: r * 2, height: r * 2)),
                       with: .color(red.opacity(0.26 * tone)))
        }
        for k in 0..<5 {
            let angle = rotation + Double(k) * (.pi * 2 / 5)
            let cx = center.x + CGFloat(cos(angle)) * r * 0.46
            let cy = center.y + CGFloat(sin(angle)) * r * 0.46
            let petal = petalPath(length: r * 1.08, width: r * 0.72)
                .applying(CGAffineTransform(rotationAngle: angle)
                    .concatenating(CGAffineTransform(translationX: cx, y: cy)))
            context.fill(petal, with: .color(red.opacity(0.72 * tone)))
        }
        // 蕊：五根短線，長度不一
        for k in 0..<5 {
            let angle = rotation + 0.55 + Double(k) * (.pi * 2 / 5)
            let reach = r * CGFloat(0.5 + Double(k % 3) * 0.12)
            var stamen = Path()
            stamen.move(to: center)
            stamen.addLine(to: CGPoint(x: center.x + CGFloat(cos(angle)) * reach,
                                       y: center.y + CGFloat(sin(angle)) * reach))
            context.stroke(stamen,
                           with: .color(Color(red: 0.33, green: 0.06, blue: 0.09)
                            .opacity(0.52 * tone)),
                           style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
        }
        context.fill(Path(ellipseIn: CGRect(x: center.x - r * 0.17, y: center.y - r * 0.17,
                                            width: r * 0.34, height: r * 0.34)),
                     with: .color(Color(red: 0.36, green: 0.06, blue: 0.09)
                        .opacity(0.86 * tone)))
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
    /// [v25.497] 相框照主題換。版型（落點、角度、呼吸、老化）是共用的——
    /// 那一層講的是「照片怎麼擺在一個畫面裡」，跟畫的是山還是街無關。
    var theme: SlideshowTheme = .ink

    @State private var breathing = false

    @ViewBuilder
    private var framed: some View {
        switch theme {
        case .ink:
            InkFramedPhoto(image: item.image, size: cardSize)
        case .cyber:
            CyberFramedPhoto(image: item.image, size: cardSize,
                             tag: String(format: "%02d / %02d",
                                         item.slot % WallLayout.capacity + 1,
                                         WallLayout.capacity))
        }
    }

    var body: some View {
        framed
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

// MARK: - 前景（v25.493）
//
// 使用者說得對：東西全部在照片後面，看起來就是「照片貼在一張圖上」。
// 有東西從照片**前面**飄過去，才會有空間感——而空間感就是詩意的來源。
//
// 分前後的規則，照真實的距離走：
//   背後  紙、月、遠山、霧、水、雁、幾片遠處的落梅
//   前面  梅枝（它就長在鏡頭前）、近處的落梅、貼著地面流的霧、岸邊的蘆葦
//
// 前面的東西一律更大、更糊、更淡——離鏡頭近的東西本來就這樣。
// 這條規則比畫什麼更重要：同樣大小、同樣清晰的東西擺在前面只會像貼紙。

/// 掛在照片前面的那一層
struct InkForegroundView: View {
    var density: Double = 1.0
    /// 見 InkLandscapeView.paused
    var paused: Bool = false

    var body: some View {
        ZStack {
            // [v25.496] 梅枝從「只畫一次的靜態層」搬進會動的這一層。
            // 山不動了，但樹該動——一枝梅垂在鏡頭前紋風不動才是最假的。
            if paused {
                Canvas { context, size in
                    InkForeground.draw(&context, size: size, time: 0, density: density)
                }
                .ignoresSafeArea()
            } else {
                TimelineView(.periodic(from: .now, by: 1.0 / 24.0)) { timeline in
                    Canvas { context, size in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        InkForeground.draw(&context, size: size, time: t, density: density)
                    }
                }
                .ignoresSafeArea()
            }

            // 暗角壓在最上面：讓視線收回畫面中央
            InkVignette()
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

enum InkForeground {
    static func draw(_ context: inout GraphicsContext, size: CGSize,
                     time: Double, density: Double) {
        plumBranch(&context, size, time: time, density: density)
        reeds(&context, size, time: time, density: density)
        nearMist(&context, size, time: time)
        nearPetals(&context, size, time: time)
    }

    // MARK: 梅枝

    /// 右上角的梅枝。v25.492 之前它在背景層——那等於照片蓋在樹枝上，
    /// 樹明明比山近。搬到前面之後，花枝是垂在照片上的。
    static func plumBranch(_ context: inout GraphicsContext, _ size: CGSize,
                           time: Double, density: Double) {
        // [v25.495] 枝子改成會收鋒的筆畫。
        //
        // 上一版是三條等粗的 stroke 加七個正紅圓點——真機上看就是一張
        // 流程圖：直徑一樣、顏色一樣、邊緣硬的圓，沒有一樣是毛筆做得出來的。
        // 現在幹從根部 7pt 收到梢 1pt，花改成五瓣帶蕊、大小與角度各不相同。
        let ink = Color.black.opacity(0.70 * density)
        let w = size.width
        let h = size.height

        // [v25.496] 風。兩個週期疊起來（約 22 秒與 37 秒），不會數出節奏。
        // 幅度只有四個點上下——枝子是木頭，不是旗子。
        let sway = CGFloat(sin(time * 0.28) * 2.4 + sin(time * 0.17 + 1.3) * 1.3)

        /// 枝上某一點被風吹到哪。
        /// `flex` 是「離固定端多遠」：主幹跟畫面外的樹連著，那一頭不動（0），
        /// 越往梢越軟（1 以上）。木頭主要是上下擺，所以 y 給足、x 只給六成。
        func bend(_ ux: CGFloat, _ uy: CGFloat, _ flex: CGFloat) -> CGPoint {
            CGPoint(x: w * ux + sway * flex * 0.6, y: h * uy + sway * flex)
        }

        // 主幹：從畫面外伸進來，越往裡越細
        InkBrush.taper(&context,
                       from: bend(1.04, 0.008, 0),
                       control1: bend(0.93, 0.048, 0.25),
                       control2: bend(0.78, 0.072, 0.60),
                       to: bend(0.60, 0.195, 1.00),
                       startWidth: 7.0, endWidth: 1.1, color: ink, steps: 30)

        // 往下垂的側枝
        InkBrush.taper(&context,
                       from: bend(0.875, 0.060, 0.35),
                       control1: bend(0.885, 0.120, 0.60),
                       control2: bend(0.845, 0.180, 0.90),
                       to: bend(0.795, 0.238, 1.15),
                       startWidth: 3.2, endWidth: 0.6, color: ink.opacity(0.88))

        // 往上翹的側枝（梅的枝一定有往上衝的那一條，全部下垂就是柳）
        InkBrush.taper(&context,
                       from: bend(0.745, 0.126, 0.55),
                       control1: bend(0.688, 0.108, 0.80),
                       control2: bend(0.676, 0.078, 1.00),
                       to: bend(0.662, 0.044, 1.20),
                       startWidth: 2.8, endWidth: 0.5, color: ink.opacity(0.88))

        // 小枝：短、細、方向亂一點
        InkBrush.taper(&context,
                       from: bend(0.818, 0.088, 0.45),
                       control1: bend(0.845, 0.070, 0.58),
                       control2: bend(0.872, 0.056, 0.70),
                       to: bend(0.902, 0.040, 0.80),
                       startWidth: 1.9, endWidth: 0.4, color: ink.opacity(0.75))

        // 花：半徑、轉角、濃淡都不一樣，而且各自長在枝的哪一段（flex）
        // 要跟上面對得起來，不然風一吹花會從枝子上飛出去。
        // 花苞（小而濃）混在裡面，整枝才有「開到一半」的樣子——全部盛開是塑膠花。
        let blossoms: [(CGFloat, CGFloat, CGFloat, CGFloat, Double, Double)] = [
            (0.662, 0.044, 1.20, 6.2, 0.4, 1.00),
            (0.716, 0.124, 0.85, 5.0, 1.9, 0.92),
            (0.795, 0.238, 1.15, 5.6, 2.7, 0.96),
            (0.852, 0.112, 0.62, 4.3, 0.9, 0.85),
            (0.902, 0.040, 0.80, 5.4, 3.5, 0.90),
            (0.812, 0.068, 0.45, 3.6, 1.3, 0.78),
            (0.762, 0.170, 0.75, 4.0, 2.2, 0.88)
        ]
        for (ux, uy, flex, r, rotation, tone) in blossoms {
            InkBrush.plumBlossom(&context, at: bend(ux, uy, flex),
                                 radius: r, rotation: rotation, tone: tone * density)
        }

        // 花苞：兩個，小小一點紅，枝梢上
        for (ux, uy, flex, r) in [(CGFloat(0.638), CGFloat(0.168), CGFloat(1.10), CGFloat(2.4)),
                                  (CGFloat(0.868), CGFloat(0.168), CGFloat(0.95), CGFloat(2.0))] {
            let c = bend(ux, uy, flex)
            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r,
                                                width: r * 2, height: r * 2)),
                         with: .color(Color(red: 0.66, green: 0.12, blue: 0.18)
                            .opacity(0.80 * density)))
        }
    }

    // MARK: 近景的霧

    /// 貼著畫面下緣流過去的霧。它會從照片前面經過，照片因此「坐在」景裡，
    /// 而不是貼在上面。
    static func nearMist(_ context: inout GraphicsContext, _ size: CGSize, time: Double) {
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 55))
            for i in 0..<2 {
                let speed = 3.2 + Double(i) * 2.1
                let cycle = ((time * speed / 100).truncatingRemainder(dividingBy: 2.0)) - 0.5
                let cx = CGFloat(cycle) * size.width
                let cy = size.height * CGFloat(0.84 + 0.10 * Double(i))
                let w = size.width * 1.3
                let h = size.height * (0.10 + 0.03 * CGFloat(i))
                let breath = 0.26 + 0.10 * sin(time * 0.17 + Double(i) * 2.1)
                layer.fill(
                    Path(ellipseIn: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)),
                    with: .color(.white.opacity(breath)))
            }
        }
    }

    // MARK: 近處的落梅

    /// 離鏡頭近的花瓣：更大、更糊、掉得更快。
    /// 跟背景那幾片一起看，就有了前後。
    static func nearPetals(_ context: inout GraphicsContext, _ size: CGSize, time: Double) {
        var random = InkRandom(90210)
        context.drawLayer { layer in
            // [v25.495] 模糊從 1.2 降到 0.5。原本的糊度加上橢圓形狀，
            // 在真機上就是四團紅色污漬——近景要的是「快到看不清」，
            // 不是「髒」，所以形狀改成有尖端的花瓣，糊度拿掉大半。
            layer.addFilter(.blur(radius: 0.5))
            for i in 0..<4 {
                let startX = random.next()
                let phase = random.next()
                let speedSeed = random.next()
                let fallSeconds = 13.0 + speedSeed * 9.0
                let cycle = ((time / fallSeconds) + phase).truncatingRemainder(dividingBy: 1)
                let y = CGFloat(cycle) * size.height * 1.12 - size.height * 0.06
                let sway = CGFloat(sin(time * 0.8 + Double(i) * 1.9) * 26)
                let x = CGFloat(0.5 + startX * 0.48) * size.width + sway
                let r = 4.0 + CGFloat(speedSeed) * 2.6
                let fade = cycle > 0.86 ? (1 - (cycle - 0.86) / 0.14) : 1
                let petal = InkBrush.petalPath(length: r * 2, width: r * 0.95)
                    .applying(CGAffineTransform(rotationAngle: time * 1.1 + Double(i) * 0.8)
                        .concatenating(CGAffineTransform(translationX: x, y: y)))
                layer.fill(petal,
                           with: .color(Color(red: 0.74, green: 0.20, blue: 0.26)
                            .opacity(0.52 * fade)))
            }
        }
    }

    // MARK: 岸邊的蘆葦

    /// 畫面下緣的幾叢蘆葦，隨風輕擺。
    ///
    /// 前景放草不是裝飾：它給了「鏡頭站在這裡」的位置感——
    /// 看畫的人是蹲在岸邊看出去的。
    static func reeds(_ context: inout GraphicsContext, _ size: CGSize,
                      time: Double, density: Double) {
        // [v25.495] 每一根都改成收鋒的筆畫，高度與粗細用亂數拉開。
        //
        // 上一版是等粗 1.3pt 的線，一叢裡每根只差 0.045 的高度——真機上
        // 看起來是一排刮痕，不是草。草的重點就在「沒有兩根一樣高」。
        let clusters: [(CGFloat, CGFloat, Int)] = [
            (0.05, 1.05, 7), (0.17, 0.80, 5), (0.33, 0.58, 4),
            (0.90, 1.00, 7), (0.78, 0.76, 5), (0.64, 0.54, 3)
        ]
        for (ux, scale, count) in clusters {
            var random = InkRandom(Int(ux * 1000) + count)
            let baseX = size.width * ux
            for i in 0..<count {
                let spread = CGFloat(random.next() * 2 - 1) * 16 * scale
                // 高度拉到 0.10～0.24，差距夠大才像一叢草
                let height = size.height * CGFloat(0.10 + random.next() * 0.14) * scale
                let lean = CGFloat(random.next() * 2 - 1) * 18 * scale
                let sway = CGFloat(sin(time * 0.55 + random.next() * 6 + Double(ux) * 9)
                                   * (5 + 6 * random.next())) * scale
                let bottom = CGPoint(x: baseX + spread, y: size.height + 6)
                let top = CGPoint(x: bottom.x + lean + sway, y: size.height - height)
                let tone = 0.34 + random.next() * 0.26
                InkBrush.taper(&context,
                               from: bottom,
                               control1: CGPoint(x: bottom.x + lean * 0.15,
                                                y: size.height - height * 0.42),
                               control2: CGPoint(x: bottom.x + lean * 0.65 + sway * 0.5,
                                                y: size.height - height * 0.78),
                               to: top,
                               startWidth: (2.2 + CGFloat(random.next()) * 1.2) * scale,
                               endWidth: 0.35 * scale,
                               color: .black.opacity(tone * density))

                // 穗：兩三筆往同一邊散開，不是一根棒子
                let plume = 2 + Int(random.next() * 2)
                for k in 0..<plume {
                    let fan = CGFloat(k) - CGFloat(plume - 1) / 2
                    let tip = CGPoint(x: top.x + fan * 4 * scale + sway * 0.3,
                                      y: top.y - CGFloat(9 + random.next() * 7) * scale)
                    InkBrush.taper(&context,
                                   from: top,
                                   control1: CGPoint(x: top.x + fan * 1.5 * scale,
                                                    y: top.y - 4 * scale),
                                   control2: CGPoint(x: tip.x - fan * 0.8 * scale,
                                                    y: tip.y + 3 * scale),
                                   to: tip,
                                   startWidth: 2.0 * scale, endWidth: 0.3 * scale,
                                   color: .black.opacity(tone * 0.8 * density))
                }
            }
        }
    }
}

// MARK: - 照片進場（v25.494）

// 使用者指定：照片用 fade in、三秒。
//
// 原本是「墨漬長大」的遮罩：好看，但它是一個**動作**——三秒長的動作會變成
// 一段表演，照片反而被動畫搶走。淡入三秒是另一種時間感：照片像是從紙裡
// 慢慢浮出來，看的人有時間把目光移過去。
//
// 保留的是落下那一圈墨暈（照片壓在紙上的痕跡），跟著同一條曲線淡掉，
// 所以只在前段看得到。

private struct InkFadeInModifier: ViewModifier, Animatable {
    /// 0＝還沒出現，1＝完全出現
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            // 落定：從大 1.5% 收回原寸。幅度刻意極小——
            // 三秒的縮放只要看得出來就會變成「在動」，那就不是淡入了。
            .scaleEffect(1.015 - 0.015 * progress)
            .background(
                // 墨壓在紙上化開的那一圈：前段看得到，後段自己收掉
                Circle()
                    .stroke(Color.black.opacity((1 - progress) * 0.14),
                            lineWidth: 1 + 8 * (1 - progress))
                    .blur(radius: 10)
                    .scaleEffect(0.5 + progress * 1.1)
                    .allowsHitTesting(false)
            )
    }
}

extension AnyTransition {
    /// 淡入（實際秒數由呼叫端的 withAnimation 決定）
    static var inkFadeIn: AnyTransition {
        .modifier(active: InkFadeInModifier(progress: 0),
                  identity: InkFadeInModifier(progress: 1))
    }
}
