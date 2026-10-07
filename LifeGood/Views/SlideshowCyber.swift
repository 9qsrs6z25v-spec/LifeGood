import SwiftUI

// MARK: - 賽博龐克（v25.497）
//
// 第二套動態相簿主題。水墨那一套花了六個版本才站住，過程中學到的方法直接搬過來：
// **先問這個題材在物理上為什麼長那樣，再決定畫什麼。**「加霓虹」畫不出賽博龐克，
// 就像「加水墨筆刷」畫不出山水。
//
// 這套場景建立在五件事上：
//
// 1. **底是夜加雨，不是霓虹。** 霓虹之所以好看不是因為它亮，是因為**濕的地面把它
//    再放一次**。乾的夜晚街景只是晚上；地上有積水，同一盞招牌就有了兩倍的存在感。
//    所以這裡先有雨、先有濕地面，招牌才上場。
// 2. **光在空氣裡是有體積的。** 招牌射出來的光會照亮它附近的雨絲，離光遠的雨絲
//    根本看不見。一片亮度相同的雨是貼圖，不是雨。
// 3. **窗戶是尺度，不是裝飾。** 一棟樓有幾層、每層幾戶，決定你覺得它多高。而且
//    真的大樓**大部分窗是暗的**——暖黃的是家，冷白的是辦公室還沒下班，整片一樣亮
//    的窗格是點陣圖。
// 4. **壞掉的燈管是這個類型的簽名。** 但閃爍不能用 sin：sin 是心跳，壞燈管是隨機
//    的卡頓，大部分時間亮著，偶爾連著熄幾下，熄的長短還不一樣。
// 5. **掃描線與色差讓你覺得「這是透過某個東西看的」。** 沒有這一層，再多霓虹也只是
//    一張夜景照片。
//
// 會動與不會動，沿用水墨那一版定下的規則（使用者指出來的那條）：
//
// - **不動**：建築輪廓、窗的位置、招牌的位置與字、纜線的走向、地面倒影的形狀。
// - **動**：雨、蒸汽、飛行載具、窗戶明滅、招牌閃爍、水面波紋、掃描線滾動、纜線微擺。
//
// 效能上這條規則剛好也是最佳解：不動的東西畫在**只畫一次**的 Canvas，會動的才進
// 每秒 24 次的那一層。整座城的九百多扇窗因此一輩子只畫一次，每一幀真正重畫的
// 只有四十幾扇會閃的、一百五十條雨絲和幾台車。

// MARK: - 調色

enum CyberPalette {
    /// 夜空頂端：接近黑，但是藍紫的——純黑的天空看起來是沒畫完
    static let skyTop = Color(red: 0.035, green: 0.036, blue: 0.078)
    /// 地平線：被底下整座城的燈染紅的那一圈光害
    static let skyHorizon = Color(red: 0.165, green: 0.058, blue: 0.195)

    static let cyan = Color(red: 0.30, green: 0.94, blue: 1.00)
    static let magenta = Color(red: 1.00, green: 0.20, blue: 0.60)
    static let amber = Color(red: 1.00, green: 0.70, blue: 0.32)
    static let acid = Color(red: 0.60, green: 1.00, blue: 0.42)

    /// 窗的顏色與它出現的機率。暖黃佔絕大多數——那是住家。
    static let windowMix: [(Color, Double)] = [
        (Color(red: 1.00, green: 0.78, blue: 0.42), 0.70),   // 家
        (Color(red: 0.84, green: 0.93, blue: 1.00), 0.17),   // 辦公室的冷白光
        (magenta, 0.08),
        (cyan, 0.05)
    ]

    static func window(_ roll: Double) -> Color {
        var acc = 0.0
        for (color, weight) in windowMix {
            acc += weight
            if roll < acc { return color }
        }
        return windowMix[0].0
    }
}

// MARK: - 城市幾何（算一次，兩層共用）

/// 一扇窗。
struct CyberWindow {
    let rect: CGRect
    let color: Color
    let brightness: Double
    /// 有值＝這扇會閃（燈管壞了／有人在走動）。靜態層把它畫成暗的，
    /// 由動態層負責把它點亮，這樣「熄掉」就只是不畫，不必去擦已經畫好的墨。
    let flickerSeed: Int?
}

/// 一棟樓。
struct CyberBuilding {
    let rect: CGRect
    /// 0＝最遠
    let block: Int
    let windows: [CyberWindow]
    /// 樓頂有沒有東西（天線／水塔／警示燈）
    let crown: Int
}

/// 一面招牌。
struct CyberSign {
    let rect: CGRect
    let color: Color
    /// 直書還是橫書
    let vertical: Bool
    let text: String
    let flickerSeed: Int
    /// 招牌亮度（也決定它照亮多少雨）
    let power: Double
}

/// 整座城。
struct CyberCityPlan {
    let buildings: [CyberBuilding]
    let signs: [CyberSign]
    let cables: [CyberCable]
    let groundY: CGFloat
}

/// 一條橫過畫面的纜線。賽博龐克的天空一定是被電線切碎的——
/// 那是「這座城長得比它的基礎建設快」的視覺證據。
struct CyberCable {
    let start: CGPoint
    let end: CGPoint
    /// 下垂多少
    let sag: CGFloat
    let width: CGFloat
    let opacity: Double
    /// 掛在上面的小東西（燈籠／號誌盒）落在線上的哪個位置
    let charms: [CGFloat]
}

enum CyberCity {
    /// 幾排建築，遠到近
    static let blocks = 4

    /// 長出整座城。純函式、固定種子——靜態層與動態層各呼叫一次，
    /// 拿到的是完全一樣的城市。
    static func build(_ size: CGSize) -> CyberCityPlan {
        let groundY = size.height * 0.775
        var buildings: [CyberBuilding] = []

        for block in 0..<blocks {
            let depth = Double(block) / Double(blocks - 1)        // 0＝最遠
            var random = InkRandom(4700 + block * 131)
            // 越近的樓越高、底線越低（站在街上往上看）
            let baseline = size.height * CGFloat(0.40 + 0.20 * depth)
            let maxRise = size.height * CGFloat(0.16 + 0.20 * depth)
            let minWidth = size.width * CGFloat(0.045 + 0.035 * depth)
            let widthRange = size.width * CGFloat(0.045 + 0.075 * depth)

            var x: CGFloat = -size.width * 0.06
            while x < size.width * 1.06 {
                let w = minWidth + CGFloat(random.next()) * widthRange
                // 高度分佈刻意不是平均的：大部分是中等，偶爾一棟特別高。
                // 平均分佈畫出來是柵欄，不是天際線。
                let roll = random.next()
                let tall = roll > 0.86 ? 1.0 : (roll > 0.55 ? 0.62 : 0.34)
                let h = maxRise * CGFloat(0.28 + tall * random.next() * 0.95)
                let rect = CGRect(x: x, y: baseline - h, width: w, height: h + size.height)
                let crown = random.next() > 0.72 ? Int(random.next() * 3) + 1 : 0
                buildings.append(
                    CyberBuilding(rect: rect, block: block,
                                  windows: windows(in: CGRect(x: x, y: baseline - h,
                                                              width: w, height: h),
                                                   block: block, random: &random),
                                  crown: crown))
                // 樓跟樓之間留一點縫，但不要每次一樣寬
                x += w + CGFloat(random.next()) * size.width * 0.012 + 1.5
            }
        }

        return CyberCityPlan(buildings: buildings,
                             signs: signs(size),
                             cables: cables(size),
                             groundY: groundY)
    }

    /// 一棟樓的窗。
    ///
    /// 格子大小決定「這棟樓看起來幾層」，所以近的樓格子大、遠的樓小到剩一個點。
    /// 點亮的比例壓在四成上下——真的大樓晚上大部分窗是暗的。
    private static func windows(in rect: CGRect, block: Int,
                                random: inout InkRandom) -> [CyberWindow] {
        guard rect.height > 6, rect.width > 6 else { return [] }
        let depth = Double(block) / Double(blocks - 1)
        let cellW = CGFloat(2.6 + 3.4 * depth)
        let cellH = CGFloat(3.0 + 4.6 * depth)
        let gapW = CGFloat(1.6 + 1.8 * depth)
        let gapH = CGFloat(2.2 + 2.6 * depth)
        let inset = CGFloat(2.0 + 2.5 * depth)

        var out: [CyberWindow] = []
        var y = rect.minY + inset + 4
        while y + cellH < rect.maxY {
            var x = rect.minX + inset
            while x + cellW < rect.maxX - inset {
                let roll = random.next()
                if roll < 0.42 {
                    let seed = random.next() < 0.055 ? Int(random.next() * 9999) : nil
                    out.append(CyberWindow(
                        rect: CGRect(x: x, y: y, width: cellW, height: cellH),
                        color: CyberPalette.window(random.next()),
                        brightness: 0.35 + random.next() * 0.65,
                        flickerSeed: seed))
                }
                x += cellW + gapW
            }
            y += cellH + gapH
        }
        return out
    }

    /// 招牌。位置固定，字固定——會動的只有燈管。
    ///
    /// 直書的招牌是這個類型的骨架（香港、新宿、九龍城寨），橫的拿來打斷節奏。
    private static func signs(_ size: CGSize) -> [CyberSign] {
        let w = size.width
        let h = size.height
        return [
            CyberSign(rect: CGRect(x: w * 0.045, y: h * 0.300,
                                   width: w * 0.062, height: h * 0.185),
                      color: CyberPalette.magenta, vertical: true,
                      text: "美好人生", flickerSeed: 11, power: 1.0),
            CyberSign(rect: CGRect(x: w * 0.845, y: h * 0.255,
                                   width: w * 0.058, height: h * 0.150),
                      color: CyberPalette.cyan, vertical: true,
                      text: "記憶所", flickerSeed: 37, power: 0.9),
            CyberSign(rect: CGRect(x: w * 0.700, y: h * 0.470,
                                   width: w * 0.175, height: h * 0.038),
                      color: CyberPalette.amber, vertical: false,
                      text: "24H 営業", flickerSeed: 73, power: 0.7),
            CyberSign(rect: CGRect(x: w * 0.140, y: h * 0.545,
                                   width: w * 0.150, height: h * 0.032),
                      color: CyberPalette.acid, vertical: false,
                      text: "麵 · 酒 · 電", flickerSeed: 5, power: 0.6)
        ]
    }

    /// 只要纜線。前景層只畫纜線與掛在上面的燈籠，
    /// 為了四條線把整座城（九百多扇窗）重算一次太蠢了。
    static func cables(_ size: CGSize) -> [CyberCable] {
        let w = size.width
        let h = size.height
        return [
            CyberCable(start: CGPoint(x: -10, y: h * 0.118),
                       end: CGPoint(x: w + 10, y: h * 0.072),
                       sag: h * 0.055, width: 2.2, opacity: 0.92,
                       charms: [0.22, 0.58]),
            CyberCable(start: CGPoint(x: -10, y: h * 0.052),
                       end: CGPoint(x: w + 10, y: h * 0.145),
                       sag: h * 0.030, width: 1.3, opacity: 0.75, charms: []),
            CyberCable(start: CGPoint(x: -10, y: h * 0.205),
                       end: CGPoint(x: w + 10, y: h * 0.168),
                       sag: h * 0.038, width: 1.6, opacity: 0.60, charms: [0.79]),
            CyberCable(start: CGPoint(x: w * 0.62, y: -10),
                       end: CGPoint(x: w + 10, y: h * 0.235),
                       sag: w * 0.03, width: 1.1, opacity: 0.45, charms: [])
        ]
    }

    /// 壞掉的燈管。
    ///
    /// 不能用 sin：sin 是心跳，規律得一眼看穿。壞燈管是隨機的卡頓——大部分時間
    /// 亮著，偶爾連著熄幾下，而且熄的長短不一樣。三個頻率不成整數比的 sin 相乘，
    /// 乘積大部分時間很小、偶爾衝到接近 1，拿它當「這一刻熄掉」的門檻就對了。
    static func flicker(time: Double, seed: Int) -> Double {
        let t = time * (3.1 + Double(seed % 7) * 0.9) + Double(seed) * 1.37
        let a = sin(t) * sin(t * 1.618 + 0.7) * sin(t * 0.37 + 2.1)
        if a > 0.62 { return 0.06 }
        if a > 0.50 { return 0.52 }
        return 1.0
    }

    /// 這個 x 附近有多少光（0～1）。雨絲的亮度靠它決定——
    /// 離招牌遠的雨是看不見的。
    static func lightAt(_ x: CGFloat, _ y: CGFloat, signs: [CyberSign],
                        size: CGSize) -> Double {
        var total = 0.0
        for sign in signs {
            let cx = sign.rect.midX
            let cy = sign.rect.midY
            let dx = Double((x - cx) / max(size.width, 1))
            let dy = Double((y - cy) / max(size.height, 1))
            let d2 = dx * dx + dy * dy * 0.6
            total += sign.power * exp(-d2 * 26)
        }
        return min(total, 1.0)
    }
}

// MARK: - 背景

struct CyberCityView: View {
    var density: Double = 1.0

    @State private var plan: CyberCityPlan?
    @State private var builtFor: CGSize = .zero

    var body: some View {
        // ignoresSafeArea 只下在 GeometryReader 上，**裡面的 Canvas 一律不下**。
        // 兩邊都下的話 geo.size 是安全區內的尺寸、Canvas 拿到的是整個螢幕，
        // 整座城會照小的那個算座標、畫在大的那塊布上——樓會錯位，地平線會跑掉。
        GeometryReader { geo in
            ZStack {
                // 只畫一次：天空、整座城、九百多扇窗、地面倒影、掃描線
                CyberStaticLayer(plan: plan, density: density)

                // 每秒 24 次：會閃的窗、招牌的輝光、雨、蒸汽、飛車、水紋、滾動條
                TimelineView(.periodic(from: .now, by: 1.0 / 24.0)) { timeline in
                    Canvas { context, size in
                        guard let plan else { return }
                        CyberScene.draw(&context, size: size, plan: plan,
                                        time: timeline.date.timeIntervalSinceReferenceDate,
                                        density: density)
                    }
                }
            }
            .onAppear { rebuild(geo.size) }
            .onChange(of: geo.size) { _, new in rebuild(new) }
        }
        .ignoresSafeArea()
    }

    private func rebuild(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        guard abs(size.width - builtFor.width) > 0.5
                || abs(size.height - builtFor.height) > 0.5 else { return }
        builtFor = size
        plan = CyberCity.build(size)
    }
}

/// 不會動的那一半。
private struct CyberStaticLayer: View {
    let plan: CyberCityPlan?
    let density: Double

    var body: some View {
        Canvas { context, size in
            sky(&context, size)
            guard let plan else { return }
            city(&context, size, plan)
            ground(&context, size, plan)
            scanlines(&context, size)
        }
    }

    /// 夜空。往地平線被整座城的燈染開——那叫光害，而它正是夜景好看的原因。
    private func sky(_ context: inout GraphicsContext, _ size: CGSize) {
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(
                Gradient(colors: [CyberPalette.skyTop,
                                  CyberPalette.skyTop,
                                  CyberPalette.skyHorizon]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height * 0.62)))

        // 低空的雲：被底下的霓虹從下面打亮。雲本身是暗的，亮的是它的肚子。
        var random = InkRandom(90125)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 46))
            for i in 0..<5 {
                let cx = CGFloat(random.next()) * size.width
                let cy = size.height * CGFloat(0.06 + random.next() * 0.26)
                let w = size.width * CGFloat(0.45 + random.next() * 0.55)
                let h = size.height * CGFloat(0.045 + random.next() * 0.05)
                let tint = i % 2 == 0 ? CyberPalette.magenta : CyberPalette.cyan
                layer.fill(Path(ellipseIn: CGRect(x: cx - w / 2, y: cy - h / 2,
                                                  width: w, height: h)),
                           with: .color(tint.opacity(0.055 + random.next() * 0.05)))
            }
        }
    }

    private func city(_ context: inout GraphicsContext, _ size: CGSize,
                      _ plan: CyberCityPlan) {
        for building in plan.buildings {
            let depth = Double(building.block) / Double(CyberCity.blocks - 1)
            // 空氣透視：遠的樓偏藍、偏亮（空氣裡的光散進來），近的接近純黑
            let top = Color(red: 0.125 - 0.095 * depth,
                            green: 0.105 - 0.080 * depth,
                            blue: 0.215 - 0.160 * depth)
            let bottom = Color(red: 0.055 - 0.035 * depth,
                               green: 0.045 - 0.028 * depth,
                               blue: 0.105 - 0.070 * depth)
            context.fill(Path(building.rect), with: .linearGradient(
                Gradient(colors: [top, bottom]),
                startPoint: CGPoint(x: 0, y: building.rect.minY),
                endPoint: CGPoint(x: 0, y: building.rect.minY + building.rect.width * 3)))

            // 屋頂那一條邊：有光從後面打過來，天際線才咬得出來
            var edge = Path()
            edge.move(to: CGPoint(x: building.rect.minX, y: building.rect.minY))
            edge.addLine(to: CGPoint(x: building.rect.maxX, y: building.rect.minY))
            context.stroke(edge,
                           with: .color(CyberPalette.cyan.opacity(0.10 + 0.14 * (1 - depth))),
                           style: StrokeStyle(lineWidth: 0.8))

            crown(&context, building, depth: depth)

            for window in building.windows {
                // 會閃的這一批在這裡**不畫**：靜態層留著暗的窗口，
                // 由動態層把它點亮。這樣「熄掉」就只是不畫。
                guard window.flickerSeed == nil else { continue }
                context.fill(Path(window.rect),
                             with: .color(window.color
                                .opacity(window.brightness * (0.30 + 0.55 * depth) * density)))
            }
        }

        // 招牌板子（暗的底）。亮的燈管交給動態層。
        for sign in plan.signs {
            context.fill(Path(roundedRect: sign.rect, cornerRadius: 2),
                         with: .color(Color(red: 0.045, green: 0.04, blue: 0.065)))
            context.stroke(Path(roundedRect: sign.rect, cornerRadius: 2),
                           with: .color(sign.color.opacity(0.22)),
                           style: StrokeStyle(lineWidth: 0.8))
        }
    }

    /// 樓頂：天線、水塔、警示燈的桿子。天際線全部平頭就是一排積木。
    private func crown(_ context: inout GraphicsContext, _ building: CyberBuilding,
                       depth: Double) {
        guard building.crown > 0 else { return }
        let ink = Color(red: 0.02, green: 0.02, blue: 0.04)
        let cx = building.rect.midX
        let top = building.rect.minY
        let scale = CGFloat(0.6 + depth * 0.8)

        switch building.crown {
        case 1:     // 天線
            var mast = Path()
            mast.move(to: CGPoint(x: cx, y: top))
            mast.addLine(to: CGPoint(x: cx, y: top - 22 * scale))
            context.stroke(mast, with: .color(ink), style: StrokeStyle(lineWidth: 1.4 * scale))
            let r = 1.6 * scale
            context.fill(Path(ellipseIn: CGRect(x: cx - r, y: top - 22 * scale - r,
                                                width: r * 2, height: r * 2)),
                         with: .color(CyberPalette.magenta.opacity(0.9)))
        case 2:     // 水塔
            let w = building.rect.width * 0.34
            let h = 9 * scale
            context.fill(Path(CGRect(x: cx - w / 2, y: top - h, width: w, height: h)),
                         with: .color(ink))
            for leg in [CGFloat(-1), 1] {
                var l = Path()
                l.move(to: CGPoint(x: cx + leg * w * 0.35, y: top))
                l.addLine(to: CGPoint(x: cx + leg * w * 0.35, y: top - h))
                context.stroke(l, with: .color(ink), style: StrokeStyle(lineWidth: 1.1 * scale))
            }
        default:    // 兩根細桿
            for side in [CGFloat(-0.25), 0.25] {
                var mast = Path()
                let x = cx + building.rect.width * side
                mast.move(to: CGPoint(x: x, y: top))
                mast.addLine(to: CGPoint(x: x, y: top - (10 + 6 * scale)))
                context.stroke(mast, with: .color(ink),
                               style: StrokeStyle(lineWidth: 1.0 * scale))
            }
        }
    }

    /// 濕地面。
    ///
    /// 這是整套主題最重要的一塊——沒有它，上面那座城只是一張夜景。
    /// 倒影的形狀跟著那座不動的城，所以它也畫在靜態層；會晃的波紋在動態層。
    private func ground(_ context: inout GraphicsContext, _ size: CGSize,
                        _ plan: CyberCityPlan) {
        let groundY = plan.groundY
        context.fill(
            Path(CGRect(x: 0, y: groundY, width: size.width, height: size.height - groundY)),
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.055, green: 0.045, blue: 0.085),
                                  Color(red: 0.015, green: 0.014, blue: 0.028)]),
                startPoint: CGPoint(x: 0, y: groundY),
                endPoint: CGPoint(x: 0, y: size.height)))

        // 把招牌翻下來，往下拉長、糊掉。水面的倒影永遠比本體**長**，
        // 因為每一道波都把光再往你這邊帶一點。
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 9))
            for sign in plan.signs {
                let h = (groundY - sign.rect.maxY) * 0.9 + sign.rect.height * 2.6
                let rect = CGRect(x: sign.rect.minX - sign.rect.width * 0.25,
                                  y: groundY,
                                  width: sign.rect.width * 1.5,
                                  height: max(h, 40))
                layer.fill(Path(rect), with: .linearGradient(
                    Gradient(colors: [sign.color.opacity(0.30 * sign.power), .clear]),
                    startPoint: CGPoint(x: 0, y: groundY),
                    endPoint: CGPoint(x: 0, y: rect.maxY)))
            }
            // 整排樓的燈在地上糊成的一條亮帶
            layer.fill(Path(CGRect(x: 0, y: groundY, width: size.width,
                                   height: size.height * 0.07)),
                       with: .linearGradient(
                        Gradient(colors: [CyberPalette.amber.opacity(0.10), .clear]),
                        startPoint: CGPoint(x: 0, y: groundY),
                        endPoint: CGPoint(x: 0, y: groundY + size.height * 0.07)))
        }

        // 地平線那一條：地面與城市的交界要有一道亮線，不然城市像浮在空中
        var horizon = Path()
        horizon.move(to: CGPoint(x: 0, y: groundY))
        horizon.addLine(to: CGPoint(x: size.width, y: groundY))
        context.stroke(horizon, with: .color(CyberPalette.cyan.opacity(0.14)),
                       style: StrokeStyle(lineWidth: 1))
    }

    /// 掃描線。
    ///
    /// 它不動——動的是另一層那條滾動的亮帶。固定的掃描線每秒重畫三百多次
    /// 是純粹的浪費，而且肉眼根本看不出它有沒有在動。
    private func scanlines(_ context: inout GraphicsContext, _ size: CGSize) {
        var y: CGFloat = 0
        while y < size.height {
            context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                         with: .color(.black.opacity(0.14)))
            y += 3
        }
    }
}

// MARK: - 會動的那一半

enum CyberScene {
    static func draw(_ context: inout GraphicsContext, size: CGSize,
                     plan: CyberCityPlan, time: Double, density: Double) {
        flickeringWindows(&context, plan: plan, time: time, density: density)
        neon(&context, size, plan: plan, time: time, density: density)
        rain(&context, size, plan: plan, time: time, density: density)
        vehicles(&context, size, time: time, density: density)
        ripples(&context, size, plan: plan, time: time, density: density)
        rollBar(&context, size, time: time)
    }

    /// 會閃的窗。靜態層故意沒畫它們，所以這裡「熄掉」＝不畫。
    private static func flickeringWindows(_ context: inout GraphicsContext,
                                          plan: CyberCityPlan, time: Double,
                                          density: Double) {
        for building in plan.buildings {
            let depth = Double(building.block) / Double(CyberCity.blocks - 1)
            for window in building.windows {
                guard let seed = window.flickerSeed else { continue }
                let level = CyberCity.flicker(time: time, seed: seed)
                guard level > 0.1 else { continue }
                context.fill(Path(window.rect),
                             with: .color(window.color.opacity(
                                window.brightness * level
                                * (0.30 + 0.55 * depth) * density)))
            }
        }
    }

    /// 招牌的燈管與輝光。
    ///
    /// 輝光不是「把顏色調亮」——是同一個形狀畫三次：最外一圈糊得很開很淡，
    /// 中間一圈收一點，最裡面是幾乎純白的管芯。真的霓虹管中心是白的，
    /// 你看到的顏色是它周圍的氣體在發光。
    private static func neon(_ context: inout GraphicsContext, _ size: CGSize,
                             plan: CyberCityPlan, time: Double, density: Double) {
        for sign in plan.signs {
            let level = CyberCity.flicker(time: time, seed: sign.flickerSeed)
            guard level > 0.08 else { continue }
            let alpha = level * sign.power * density
            let shape = Path(roundedRect: sign.rect.insetBy(dx: 2.5, dy: 2.5),
                             cornerRadius: 2)

            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 18))
                layer.stroke(shape, with: .color(sign.color.opacity(0.55 * alpha)),
                             style: StrokeStyle(lineWidth: 7))
            }
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 5))
                layer.stroke(shape, with: .color(sign.color.opacity(0.85 * alpha)),
                             style: StrokeStyle(lineWidth: 3))
            }
            context.stroke(shape, with: .color(.white.opacity(0.80 * alpha)),
                           style: StrokeStyle(lineWidth: 1))

            // 招牌上的字：直書就一個字一個字往下排
            text(&context, sign, alpha: alpha)

            // 光打進雨裡的那道錐形
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 28))
                var cone = Path()
                cone.move(to: CGPoint(x: sign.rect.midX, y: sign.rect.midY))
                cone.addLine(to: CGPoint(x: sign.rect.midX - sign.rect.width * 1.9,
                                         y: plan.groundY))
                cone.addLine(to: CGPoint(x: sign.rect.midX + sign.rect.width * 1.9,
                                         y: plan.groundY))
                cone.closeSubpath()
                layer.fill(cone, with: .linearGradient(
                    Gradient(colors: [sign.color.opacity(0.17 * alpha), .clear]),
                    startPoint: CGPoint(x: 0, y: sign.rect.midY),
                    endPoint: CGPoint(x: 0, y: plan.groundY)))
            }
        }
    }

    private static func text(_ context: inout GraphicsContext, _ sign: CyberSign,
                             alpha: Double) {
        let characters = Array(sign.text)
        guard !characters.isEmpty else { return }
        if sign.vertical {
            let step = sign.rect.height / CGFloat(characters.count)
            let fontSize = min(step * 0.74, sign.rect.width * 0.72)
            for (i, ch) in characters.enumerated() {
                let point = CGPoint(x: sign.rect.midX,
                                    y: sign.rect.minY + step * (CGFloat(i) + 0.5))
                context.draw(
                    Text(String(ch))
                        .font(.system(size: fontSize, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92 * alpha)),
                    at: point, anchor: .center)
            }
        } else {
            let fontSize = min(sign.rect.height * 0.62,
                               sign.rect.width / CGFloat(characters.count) * 1.2)
            context.draw(
                Text(sign.text)
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92 * alpha)),
                at: CGPoint(x: sign.rect.midX, y: sign.rect.midY), anchor: .center)
        }
    }

    /// 雨。
    ///
    /// 關鍵不在雨絲本身，在**亮度**：雨滴自己不發光，它只是把旁邊的光折給你。
    /// 所以離招牌近的雨絲很明顯，遠的幾乎看不見。一片亮度相同的雨是貼圖。
    private static func rain(_ context: inout GraphicsContext, _ size: CGSize,
                             plan: CyberCityPlan, time: Double, density: Double) {
        var random = InkRandom(7731)
        for _ in 0..<150 {
            let lane = random.next()
            let depth = random.next()                    // 0＝遠，1＝近
            let phase = random.next()
            let fall = 1.45 - depth * 0.75               // 近的掉得快
            let cycle = ((time / fall) + phase).truncatingRemainder(dividingBy: 1)
            let y = CGFloat(cycle) * size.height * 1.25 - size.height * 0.12
            // 風把雨吹斜。斜的角度一致——同一場雨裡風向是同一個。
            let x = CGFloat(lane) * size.width * 1.3 - size.width * 0.15
                    + CGFloat(cycle) * size.width * 0.075
            let length = CGFloat(7 + depth * 26)
            let lit = CyberCity.lightAt(x, y, signs: plan.signs, size: size)
            let alpha = (0.045 + lit * 0.42) * (0.35 + depth * 0.65) * density
            guard alpha > 0.02 else { continue }

            var streak = Path()
            streak.move(to: CGPoint(x: x, y: y))
            streak.addLine(to: CGPoint(x: x - size.width * 0.022, y: y + length))
            context.stroke(streak, with: .color(.white.opacity(alpha)),
                           style: StrokeStyle(lineWidth: 0.6 + depth * 0.9,
                                              lineCap: .round))
        }
    }

    /// 飛行載具。水墨那一版的鳥在這裡的對應物——
    /// 一個會動的小點，用來說明「這個世界是活的，而且很大」。
    private static func vehicles(_ context: inout GraphicsContext, _ size: CGSize,
                                 time: Double, density: Double) {
        for i in 0..<3 {
            let speed = 0.016 + Double(i) * 0.009
            let cycle = ((time * speed) + Double(i) * 0.41)
                .truncatingRemainder(dividingBy: 1)
            let rightward = i % 2 == 0
            let travel = CGFloat(cycle) * size.width * 1.3 - size.width * 0.15
            let x = rightward ? travel : size.width - travel
            let y = size.height * CGFloat(0.13 + 0.085 * Double(i))
            let scale = CGFloat(0.7 + Double(i) * 0.35)
            let dir: CGFloat = rightward ? 1 : -1

            // 尾跡：往後拉的一道糊光
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 3))
                var trail = Path()
                trail.move(to: CGPoint(x: x, y: y))
                trail.addLine(to: CGPoint(x: x - dir * 30 * scale, y: y + 1.5 * scale))
                layer.stroke(trail,
                             with: .color(CyberPalette.magenta.opacity(0.42 * density)),
                             style: StrokeStyle(lineWidth: 1.6 * scale, lineCap: .round))
            }
            // 前白後紅，跟真的飛機一樣
            let r = 1.5 * scale
            context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r,
                                                width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(0.95 * density)))
            context.fill(Path(ellipseIn: CGRect(x: x - dir * 7 * scale - r * 0.7,
                                                y: y - r * 0.7,
                                                width: r * 1.4, height: r * 1.4)),
                         with: .color(CyberPalette.magenta.opacity(0.9 * density)))
        }
    }

    /// 水面的波紋。倒影的形狀是固定的（畫在靜態層），這裡只放會晃的那幾道亮線。
    private static func ripples(_ context: inout GraphicsContext, _ size: CGSize,
                                plan: CyberCityPlan, time: Double, density: Double) {
        var random = InkRandom(60221)
        for i in 0..<9 {
            let depth = random.next()
            let y = plan.groundY + (size.height - plan.groundY)
                * CGFloat(0.04 + depth * 0.92)
            let phase = time * (0.25 + depth * 0.5) + random.next() * 6
            let width = size.width * CGFloat(0.12 + random.next() * 0.3)
            let x = size.width * CGFloat(0.5 + sin(phase) * 0.42) - width / 2
            let tint = i % 3 == 0 ? CyberPalette.cyan
                : (i % 3 == 1 ? CyberPalette.magenta : CyberPalette.amber)
            var line = Path()
            line.move(to: CGPoint(x: x, y: y))
            line.addLine(to: CGPoint(x: x + width, y: y))
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 2.2))
                layer.stroke(line, with: .linearGradient(
                    Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: tint.opacity((0.16 + depth * 0.26) * density),
                              location: 0.35),
                        .init(color: .clear, location: 1)]),
                    startPoint: CGPoint(x: x, y: y),
                    endPoint: CGPoint(x: x + width, y: y)),
                    style: StrokeStyle(lineWidth: 1 + depth * 2.4, lineCap: .round))
            }
        }
    }

    /// 滾動條：CRT 的場同步沒鎖好，那條亮帶會慢慢往下爬。
    /// 週期刻意拉到快九秒——太頻繁就變成在閃，那是壞掉，不是老。
    private static func rollBar(_ context: inout GraphicsContext, _ size: CGSize,
                                time: Double) {
        let cycle = (time / 8.7).truncatingRemainder(dividingBy: 1)
        let y = CGFloat(cycle) * size.height * 1.3 - size.height * 0.15
        let h = size.height * 0.09
        context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: h)),
                     with: .linearGradient(
                        Gradient(colors: [.clear, .white.opacity(0.030), .clear]),
                        startPoint: CGPoint(x: 0, y: y),
                        endPoint: CGPoint(x: 0, y: y + h)))
    }
}

// MARK: - 前景

/// 照片**前面**的那一層。水墨那一版學到的：東西全部在照片後面，
/// 看起來就只是「照片貼在一張圖上」。
struct CyberForegroundView: View {
    var density: Double = 1.0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 24.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                CyberForeground.cables(&context, size, time: t, density: density)
                CyberForeground.steam(&context, size, time: t, density: density)
                CyberForeground.nearRain(&context, size, time: t, density: density)
            }
        }
        .overlay(CyberVignette())
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

enum CyberForeground {
    /// 纜線。走向固定，會動的是風吹的那一點點晃。
    ///
    /// 掛在線上的小燈籠才是重點——它給了「有人住在這裡」的證據。
    /// 一座只有大樓和招牌的城市是渲染圖，不是街。
    static func cables(_ context: inout GraphicsContext, _ size: CGSize,
                       time: Double, density: Double) {
        for (i, cable) in CyberCity.cables(size).enumerated() {
            let sway = CGFloat(sin(time * 0.31 + Double(i) * 1.9) * 2.0
                               + sin(time * 0.19 + Double(i)) * 1.1)
            let mid = CGPoint(x: (cable.start.x + cable.end.x) / 2,
                              y: (cable.start.y + cable.end.y) / 2
                                 + cable.sag * 2 + sway)
            var path = Path()
            path.move(to: cable.start)
            path.addQuadCurve(to: cable.end, control: mid)
            context.stroke(path,
                           with: .color(Color(red: 0.02, green: 0.02, blue: 0.035)
                            .opacity(cable.opacity)),
                           style: StrokeStyle(lineWidth: cable.width, lineCap: .round))

            // addQuadCurve 畫的是**二次**貝茲，InkBrush.point 算的是三次。
            // 換算：c1 = p0 + ⅔(ctrl − p0)，c2 = p1 + ⅔(ctrl − p1)。
            // 不換算的話燈籠會掛在離電線好幾個點遠的空中。
            let c1 = CGPoint(x: cable.start.x + (mid.x - cable.start.x) * 2 / 3,
                             y: cable.start.y + (mid.y - cable.start.y) * 2 / 3)
            let c2 = CGPoint(x: cable.end.x + (mid.x - cable.end.x) * 2 / 3,
                             y: cable.end.y + (mid.y - cable.end.y) * 2 / 3)
            for t in cable.charms {
                // 曲線上 t 處。線在晃，掛在上面的東西要跟著晃。
                let point = InkBrush.point(cable.start, c1, c2, cable.end, t)
                lantern(&context, at: point, time: time, seed: i * 17,
                        density: density)
            }
        }
    }

    /// 掛在電線上的小燈籠。
    private static func lantern(_ context: inout GraphicsContext, at top: CGPoint,
                                time: Double, seed: Int, density: Double) {
        let swing = CGFloat(sin(time * 0.74 + Double(seed)) * 3.2)
        let center = CGPoint(x: top.x + swing, y: top.y + 18)
        var cord = Path()
        cord.move(to: top)
        cord.addLine(to: CGPoint(x: center.x, y: center.y - 7))
        context.stroke(cord, with: .color(.black.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 0.9))

        let level = CyberCity.flicker(time: time, seed: seed + 3)
        let body = Path(ellipseIn: CGRect(x: center.x - 5.5, y: center.y - 7,
                                          width: 11, height: 14))
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 11))
            layer.fill(body, with: .color(CyberPalette.amber
                .opacity(0.70 * level * density)))
        }
        context.fill(body, with: .color(CyberPalette.amber
            .opacity(0.88 * level * density)))
        context.stroke(body, with: .color(.black.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 0.9))
    }

    /// 地面冒上來的蒸汽。
    ///
    /// 它不是白的——它被旁邊的霓虹染色。白色的蒸汽是在棚內拍的。
    static func steam(_ context: inout GraphicsContext, _ size: CGSize,
                      time: Double, density: Double) {
        var random = InkRandom(33112)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 42))
            for i in 0..<3 {
                let baseX = CGFloat(0.12 + random.next() * 0.76) * size.width
                let rise = 15.0 + random.next() * 11.0
                let phase = random.next()
                let cycle = ((time / rise) + phase).truncatingRemainder(dividingBy: 1)
                let y = size.height * (1.02 - CGFloat(cycle) * 0.42)
                let drift = CGFloat(sin(time * 0.28 + Double(i) * 2.2) * 28)
                let w = size.width * CGFloat(0.26 + cycle * 0.4)
                let h = size.height * CGFloat(0.10 + cycle * 0.12)
                // 升起來的過程裡越來越淡、越來越散
                let fade = (1 - cycle) * 0.5
                let tint = i == 0 ? CyberPalette.magenta
                    : (i == 1 ? CyberPalette.cyan : CyberPalette.amber)
                layer.fill(
                    Path(ellipseIn: CGRect(x: baseX + drift - w / 2, y: y - h / 2,
                                           width: w, height: h)),
                    with: .color(tint.opacity(0.30 * fade * density)))
            }
        }
    }

    /// 近處的雨：更大、更快、更糊——因為它離鏡頭近到對不到焦。
    /// 這一條規則跟水墨那一版的前景落梅是同一條。
    static func nearRain(_ context: inout GraphicsContext, _ size: CGSize,
                         time: Double, density: Double) {
        var random = InkRandom(51977)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 2.4))
            for _ in 0..<22 {
                let lane = random.next()
                let phase = random.next()
                let weight = random.next()
                let cycle = ((time / (0.52 + weight * 0.22)) + phase)
                    .truncatingRemainder(dividingBy: 1)
                let y = CGFloat(cycle) * size.height * 1.4 - size.height * 0.2
                let x = CGFloat(lane) * size.width * 1.3 - size.width * 0.15
                        + CGFloat(cycle) * size.width * 0.1
                let length = CGFloat(44 + weight * 70)
                var streak = Path()
                streak.move(to: CGPoint(x: x, y: y))
                streak.addLine(to: CGPoint(x: x - size.width * 0.05, y: y + length))
                layer.stroke(streak,
                             with: .color(.white.opacity((0.07 + weight * 0.09) * density)),
                             style: StrokeStyle(lineWidth: 1.4 + CGFloat(weight) * 1.6,
                                                lineCap: .round))
            }
        }
    }
}

/// 暗角。比水墨那一版重——夜景本來就只有中間看得見。
private struct CyberVignette: View {
    var body: some View {
        RadialGradient(colors: [.clear, .black.opacity(0.52)],
                       center: .center, startRadius: 100, endRadius: 560)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

// MARK: - 相框

/// 賽博龐克的「相框」不是框，是**面板**：全像投影懸在街上的那種。
///
/// 三件事讓它成立：
/// 1. **角標**（四個 L 形）。那是取景框的記號，一看就知道「這是某個系統在看」。
/// 2. **色差**。青與洋紅各偏一點點——那是鏡頭或訊號沒對準，是「透過設備看」的證據。
/// 3. **底下一行等寬字**。資料標籤。但標的必須是真的資訊，不能瞎編 EXIF。
struct CyberFramedPhoto: View {
    let image: UIImage
    let size: CGSize
    /// 右下角那行小字（例如 03/08）
    let tag: String

    var body: some View {
        VStack(spacing: 0) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size.width, height: size.height)
                .clipped()
                .overlay(chromaticEdge)
                .overlay(corners)
            dataStrip
        }
        .padding(7)
        .background(
            Rectangle()
                .fill(Color(red: 0.05, green: 0.05, blue: 0.075).opacity(0.88))
                .overlay(Rectangle().stroke(CyberPalette.cyan.opacity(0.40),
                                            lineWidth: 0.8))
        )
        .shadow(color: CyberPalette.cyan.opacity(0.30), radius: 16)
        .shadow(color: .black.opacity(0.65), radius: 10, x: 0, y: 7)
    }

    /// 色差：兩條錯開一點點的細邊，一青一洋紅。
    private var chromaticEdge: some View {
        ZStack {
            Rectangle()
                .stroke(CyberPalette.cyan.opacity(0.55), lineWidth: 1)
                .offset(x: -0.8, y: -0.8)
            Rectangle()
                .stroke(CyberPalette.magenta.opacity(0.55), lineWidth: 1)
                .offset(x: 0.8, y: 0.8)
        }
        .blendMode(.screen)
    }

    /// 四個角標。長度刻意只有短邊的六分之一——角標畫長了就變成框。
    private var corners: some View {
        GeometryReader { geo in
            let arm = min(geo.size.width, geo.size.height) / 6
            Path { path in
                let w = geo.size.width
                let h = geo.size.height
                path.move(to: CGPoint(x: 0, y: arm));    path.addLine(to: .zero)
                path.addLine(to: CGPoint(x: arm, y: 0))
                path.move(to: CGPoint(x: w - arm, y: 0)); path.addLine(to: CGPoint(x: w, y: 0))
                path.addLine(to: CGPoint(x: w, y: arm))
                path.move(to: CGPoint(x: w, y: h - arm)); path.addLine(to: CGPoint(x: w, y: h))
                path.addLine(to: CGPoint(x: w - arm, y: h))
                path.move(to: CGPoint(x: arm, y: h));    path.addLine(to: CGPoint(x: 0, y: h))
                path.addLine(to: CGPoint(x: 0, y: h - arm))
            }
            .stroke(CyberPalette.cyan.opacity(0.92), lineWidth: 1.6)
        }
    }

    private var dataStrip: some View {
        HStack(spacing: 5) {
            Rectangle()
                .fill(CyberPalette.magenta)
                .frame(width: 10, height: 2)
            Text(tag)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(CyberPalette.cyan.opacity(0.85))
            Spacer(minLength: 0)
        }
        .frame(width: size.width)
        .padding(.top, 5)
    }
}

// MARK: - HUD（賽博龐克版的題款）

/// 水墨那一版的題款是「畫、題款、印」的第二件。這裡的對應物是 HUD：
/// 一條帶刻度的側軌加上等寬字。
///
/// 位置跟題款一樣在畫面左緣——照片的落點已經為它讓開那一欄了，兩套主題共用。
struct CyberHUD: View {
    let title: String
    let dateText: String?
    /// 第幾張 / 共幾張
    let counter: String

    @State private var recOn = true

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            rail
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(CyberPalette.magenta)
                        .frame(width: 5, height: 5)
                        .opacity(recOn ? 1 : 0.15)
                    Text("REC")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(CyberPalette.magenta.opacity(0.9))
                }
                verticalMono(title, size: 14, weight: .bold,
                             color: .white.opacity(0.92))
                if let dateText {
                    verticalMono(dateText, size: 9, weight: .regular,
                                 color: CyberPalette.cyan.opacity(0.75))
                }
                Text(counter)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .shadow(color: CyberPalette.cyan.opacity(0.55), radius: 7)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                recOn = false
            }
        }
    }

    /// 帶刻度的側軌。五格一條長的——沒有長短之分的刻度只是一排點。
    private var rail: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<16, id: \.self) { i in
                Rectangle()
                    .fill(CyberPalette.cyan.opacity(i % 5 == 0 ? 0.75 : 0.28))
                    .frame(width: i % 5 == 0 ? 9 : 4, height: 1)
                    .padding(.bottom, 7)
            }
        }
    }

    /// 直書的等寬字。中文直書本來就通順，而且剛好佔住左邊那一欄。
    private func verticalMono(_ text: String, size: CGFloat,
                              weight: Font.Weight, color: Color) -> some View {
        VStack(alignment: .leading, spacing: size * 0.22) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                Text(String(ch))
                    .font(.system(size: size, weight: weight, design: .monospaced))
                    .foregroundStyle(color)
                    .fixedSize()
            }
        }
    }
}

// MARK: - 照片進場

/// 賽博龐克版的三秒淡入：**訊號對焦**。
///
/// 使用者指定了三秒淡入，那是這兩套主題共同的骨架；差別在於「淡入的時候
/// 還發生了什麼」。水墨是墨壓在紙上化開一圈，這裡是鏡頭在對焦——
/// 先是糊的、帶著青色的訊號暈，三秒之內收乾淨。
private struct CyberFocusModifier: ViewModifier, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            // 對焦：從糊到清楚。6pt 在手機上大約是「看得出來但還讀得到」。
            .blur(radius: (1 - progress) * 6)
            .scaleEffect(1.02 - 0.02 * progress)
            // 訊號還沒鎖上的時候整塊泛著青光，鎖上就收掉
            .shadow(color: CyberPalette.cyan.opacity((1 - progress) * 0.85),
                    radius: 10 + 26 * (1 - progress))
    }
}

extension AnyTransition {
    /// 訊號對焦（實際秒數由呼叫端的 withAnimation 決定）
    static var cyberFocusIn: AnyTransition {
        .modifier(active: CyberFocusModifier(progress: 0),
                  identity: CyberFocusModifier(progress: 1))
    }
}
