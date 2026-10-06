import SwiftUI

// MARK: - 動態相簿的背景與版面（v25.489）
//
// 使用者要的兩件事：
//   1. 會動的水墨背景（山、霧、飛鳥），不是把照片糊掉當底
//   2. 一個畫面上慢慢跑出很多張照片的拼貼版型
//
// 水墨這一支完全用 Canvas 畫出來，沒有任何圖檔：
//   • 不必打包素材（那些圖庫的圖有授權問題，而且一張就好幾 MB）
//   • 任何螢幕尺寸都剛好，不會拉伸
//   • 山形是幾條正弦波疊出來的，每一層速度不同＝視差，所以它會「活著」

/// 背景樣式
enum SlideBackdrop: String, CaseIterable, Identifiable {
    /// 照片自己放大糊掉（v25.488 的做法）
    case photo
    /// 會動的水墨山水
    case ink
    /// 素的宣紙
    case paper
    /// 純黑
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .photo: return "照片暈染"
        case .ink:   return "水墨山水"
        case .paper: return "宣紙"
        case .dark:  return "純黑"
        }
    }

    /// 背景是亮的嗎——文字與按鈕要跟著換顏色，不然白字壓在宣紙上看不見
    var isLight: Bool {
        switch self {
        case .ink, .paper: return true
        case .photo, .dark: return false
        }
    }
}

/// 會動的水墨山水。
///
/// 每秒重畫 24 次就夠了（水墨本來就該慢），用 .periodic 而不是 .animation：
/// 後者會跟著螢幕更新率跑到 120fps，畫一樣的東西卻多燒四倍的電。
struct InkLandscapeView: View {
    /// 0...1，整體濃淡
    var density: Double = 1.0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 24.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                paper(&context, size)
                // 由遠到近四層山：越近越濃、跑得越快（視差）
                for layer in 0..<4 {
                    ridge(&context, size, layer: layer, time: t)
                }
                mist(&context, size, time: t)
                birds(&context, size, time: t)
            }
        }
        .ignoresSafeArea()
    }

    private func paper(_ context: inout GraphicsContext, _ size: CGSize) {
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.985, green: 0.980, blue: 0.970),
                    Color(red: 0.930, green: 0.930, blue: 0.925),
                    Color(red: 0.890, green: 0.893, blue: 0.895)
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)))
    }

    /// 一層山脊。兩個不同週期的正弦疊起來，才不會像心電圖。
    private func ridge(_ context: inout GraphicsContext, _ size: CGSize,
                       layer: Int, time: Double) {
        let depth = Double(layer) / 3.0                 // 0＝最遠
        let baseY = size.height * (0.40 + 0.15 * depth)
        let amp = size.height * (0.055 + 0.055 * (1 - depth))
        let drift = time * (1.6 + Double(layer) * 2.4) / 120.0

        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        var x: CGFloat = 0
        let step: CGFloat = 5
        while x <= size.width {
            let u = Double(x / max(size.width, 1))
            let y = baseY
                - amp * sin((u * 3.1 + drift + Double(layer) * 0.7) * .pi)
                - amp * 0.45 * sin((u * 7.7 - drift * 1.6 + Double(layer) * 1.9) * .pi)
            path.addLine(to: CGPoint(x: x, y: CGFloat(y)))
            x += step
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()

        let ink = (0.08 + 0.20 * depth) * density
        context.fill(path, with: .linearGradient(
            Gradient(colors: [Color.black.opacity(ink),
                              Color.black.opacity(ink * 0.18)]),
            startPoint: CGPoint(x: 0, y: baseY - amp),
            endPoint: CGPoint(x: 0, y: size.height)))
    }

    /// 橫向飄的霧帶。模糊半徑開很大，邊界才不會像一條白色香腸。
    private func mist(_ context: inout GraphicsContext, _ size: CGSize, time: Double) {
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 42))
            for i in 0..<3 {
                let speed = 5.0 + Double(i) * 3.5
                let cycle = ((time * speed / 100).truncatingRemainder(dividingBy: 1.6)) - 0.3
                let cx = CGFloat(cycle) * size.width
                let cy = size.height * CGFloat(0.47 + 0.11 * Double(i))
                let w = size.width * 1.05
                let h = size.height * (0.055 + 0.02 * CGFloat(i))
                layer.fill(
                    Path(ellipseIn: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)),
                    with: .color(.white.opacity(0.55)))
            }
        }
    }

    /// 幾隻飛鳥。兩段二次曲線就是一隻鳥，多了反而假。
    private func birds(_ context: inout GraphicsContext, _ size: CGSize, time: Double) {
        for i in 0..<5 {
            let cycle = ((time / 34 + Double(i) * 0.21).truncatingRemainder(dividingBy: 1))
            let x = CGFloat(cycle) * size.width * 1.25 - size.width * 0.12
            let y = size.height * CGFloat(0.22 + 0.055 * Double(i % 3))
                + CGFloat(sin(time * 0.7 + Double(i)) * 5)
            let s: CGFloat = 5 + CGFloat(i % 3) * 1.6
            var path = Path()
            path.move(to: CGPoint(x: x - s, y: y))
            path.addQuadCurve(to: CGPoint(x: x, y: y - s * 0.12),
                              control: CGPoint(x: x - s * 0.5, y: y - s * 0.6))
            path.addQuadCurve(to: CGPoint(x: x + s, y: y),
                              control: CGPoint(x: x + s * 0.5, y: y - s * 0.6))
            context.stroke(path, with: .color(.black.opacity(0.42 * density)),
                           lineWidth: 1.1)
        }
    }
}

/// 素宣紙（不會動，給想安靜一點的人）
struct RicePaperView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [
                Color(red: 0.98, green: 0.97, blue: 0.95),
                Color(red: 0.93, green: 0.92, blue: 0.90)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
            // 很淡的墨暈，不然只是一塊米色
            RadialGradient(colors: [.black.opacity(0.05), .clear],
                           center: .topTrailing, startRadius: 10, endRadius: 420)
            RadialGradient(colors: [.black.opacity(0.04), .clear],
                           center: .bottomLeading, startRadius: 10, endRadius: 380)
        }
        .ignoresSafeArea()
    }
}

// MARK: - 拼貼牆

/// 版面：一次一張，還是一張一張疊上同一個畫面
enum SlideLayout: String, CaseIterable, Identifiable {
    case single, collage

    var id: String { rawValue }

    var label: String {
        switch self {
        case .single:  return "單張"
        case .collage: return "拼貼牆"
        }
    }
}

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
