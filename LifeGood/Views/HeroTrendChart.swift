import SwiftUI
import Charts

// MARK: - 英雄卡背景趨勢曲線標準模板
// 從 StockView 英雄卡抽出（v25.173~25.181 逐版與使用者打磨定案的視覺規格），
// 供股票／收入／變動支出／固定支出等英雄卡共用。規格：
//  1. 平滑曲線（catmullRom）＋漸層面積；主線 2pt、半透明 30%
//  2. 垂直帶映射：數值範圍映射到卡片高度 20%~60% 帶，上方 40% 留白給大字
//  3. X 軸右延 25% 資料跨距：末點落在「右邊往回 20%」位置（類 3D 縱深構圖）
//  4. 回聲側線：主線左右各偏移 1% 卡片寬（1pt、13% 透明、無面積、尾端漸淡收細）
//  5. 景深：左高斯模糊→右漸清晰（同組線畫兩層、互補左右漸層遮罩交叉淡化）
//  6. 末端實心圓點＋大字數值標籤（皆半透明 30%；X/Y 軸各傾 5°、Z 軸 2° 立體微傾）
// 背景用法：放進英雄卡 .background 的 ZStack、緊接在底色 LinearGradient 之後。

/// 英雄卡背景趨勢資料點
struct HeroTrendPoint: Identifiable, Equatable {
    let date: Date
    let value: Double
    var id: Date { date }
}

enum HeroTrendSeries {
    /// 顯示用資料點：等距取樣至最多 maxCount 點（頭尾必留），
    /// 真實點不足 minCount 時在最前面補合成引導點湊滿——新使用者第一期只有
    /// 1 個點畫不出像樣的曲線，補點讓背景視覺舒服。合成點用「確定性偽隨機漫步」
    /// （種子＝首個真實點的時間＋數值）：同資料形狀固定，不會每次重繪亂跳；
    /// 每步 ±5% 波動、往回各推一個 stepBack 間隔（週資料傳一週、月資料傳一個月）。
    /// 合成點只在顯示時生成，不落地、不進同步。
    static func displayPoints(from raw: [HeroTrendPoint],
                              maxCount: Int = 40,
                              minCount: Int = 6,
                              stepBack: TimeInterval = 604_800) -> [HeroTrendPoint] {
        let real = sampled(raw.sorted { $0.date < $1.date }, maxCount: maxCount)
        guard let first = real.first, real.count < minCount else { return real }
        let padCount = minCount - real.count
        var seed = UInt64(abs(first.date.timeIntervalSince1970))
            &+ UInt64(abs(first.value) + 1)
        func nextUnit() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) % 1000) / 1000.0   // 0..<1
        }
        var value = first.value
        var synthetic: [HeroTrendPoint] = []
        for i in 1...padCount {
            let delta = (nextUnit() - 0.5) * 0.10   // 每步 ±5%
            value = max(value * (1 + delta), 1)
            synthetic.append(HeroTrendPoint(
                date: first.date.addingTimeInterval(Double(-i) * stepBack),
                value: value
            ))
        }
        return synthetic.reversed() + real
    }

    /// 等距取樣至最多 maxCount 點（頭尾必留；同 ChildDetailView 趨勢圖取樣規則）
    static func sampled(_ pts: [HeroTrendPoint], maxCount: Int = 40) -> [HeroTrendPoint] {
        guard pts.count > maxCount, maxCount >= 2 else { return pts }
        let step = Double(pts.count - 1) / Double(maxCount - 1)
        var out: [HeroTrendPoint] = []
        var lastIdx = -1
        for i in 0..<maxCount {
            let idx = Int((Double(i) * step).rounded())
            if idx != lastIdx {
                out.append(pts[idx])
                lastIdx = idx
            }
        }
        return out
    }
}

/// 英雄卡背景趨勢曲線（白色半透明，適用任何深色漸層底卡）。
/// 至少 2 點才畫、完全不吃觸控；不足 2 點時什麼都不畫（EmptyView）。
struct HeroTrendBackground: View {
    let points: [HeroTrendPoint]
    /// 末端大字數值格式（預設 NT$ 萬元格式）
    var valueText: (Double) -> String = { $0.ntdWanString }

    var body: some View {
        if points.count >= 2 {
            // 垂直帶映射：把數值範圍映射到卡片高度的 20%~60% 帶——
            // 最低點落在卡片下緣起 20% 高、最高點 60% 高，上方 40% 留白給大字。
            // 作法：把 Y 軸 domain 反推放大——實際值域佔 domain 的 0.4，下方預留 0.2。
            let values = points.map(\.value)
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 1
            let spread = max(maxV - minV, max(maxV * 0.05, 1))   // 平盤保底，避免除以零
            let span = spread / 0.4
            let domainLow = minV - 0.2 * span
            let domainHigh = domainLow + span
            let xFirst = points.first?.date ?? Date()
            let xLast = points.last?.date ?? Date()
            // X 軸右側延伸 25% 資料跨距：資料只佔左邊 80% 寬
            let xSpan = max(xLast.timeIntervalSince(xFirst), 1)
            let xHigh = xLast.addingTimeInterval(xSpan * 0.25)
            let xDomain = xFirst...xHigh
            let yDomain = domainLow...domainHigh
            // 回聲側線尾端收細：Charts 無法沿路徑變線寬，用尾端漸層遮罩淡出模擬
            let echoShift = xSpan * 1.25 * 0.01   // domain 全寬（含右延 25%）的 1%
            let echoTailTaper = LinearGradient(stops: [
                .init(color: .white, location: 0.00),
                .init(color: .white, location: 0.45),
                .init(color: .clear, location: 0.80)   // 資料終點約在 80% 寬，尾段漸淡收掉
            ], startPoint: .leading, endPoint: .trailing)
            let trendGroup = ZStack {
                trendLine(xDomain: xDomain, yDomain: yDomain,
                          xShift: -echoShift, lineWidth: 1,
                          lineOpacity: 0.13, showArea: false)
                    .mask(echoTailTaper)
                trendLine(xDomain: xDomain, yDomain: yDomain,
                          xShift: echoShift, lineWidth: 1,
                          lineOpacity: 0.13, showArea: false)
                    .mask(echoTailTaper)
                trendLine(xDomain: xDomain, yDomain: yDomain)
            }
            ZStack {
                // 景深（左模糊→右漸清晰）：整組三線畫兩層——底層整組高斯模糊、
                // 頂層清晰，各用互補的左右漸層遮罩交叉淡化，像相機失焦漸變到合焦。
                trendGroup
                    .blur(radius: 2.2)
                    .mask(LinearGradient(stops: [
                        .init(color: .white, location: 0.00),
                        .init(color: .white, location: 0.20),
                        .init(color: .clear, location: 0.75)
                    ], startPoint: .leading, endPoint: .trailing))
                trendGroup
                    .mask(LinearGradient(stops: [
                        .init(color: .clear, location: 0.20),
                        .init(color: .white, location: 0.75)
                    ], startPoint: .leading, endPoint: .trailing))
                // 上層：最後一個（真實）點——圓形實心、半透明 30%＋大字數值（同樣半透明）
                Chart(points) { p in
                    if p.id == points.last?.id {
                        PointMark(
                            x: .value("時間", p.date),
                            y: .value("數值", p.value)
                        )
                        .foregroundStyle(.white.opacity(0.30))
                        .symbol(.circle)
                        .symbolSize(90)
                        .annotation(position: .top,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            Text(valueText(p.value))
                                .font(.system(size: 19, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.30))
                                .shadow(color: .black.opacity(0.12), radius: 1.5, x: 0, y: 1)
                                // 立體微傾：X/Y 軸各轉 5 度、Z 軸轉 2 度，呼應景深構圖
                                .rotation3DEffect(.degrees(5), axis: (x: 1, y: 0, z: 0))
                                .rotation3DEffect(.degrees(5), axis: (x: 0, y: 1, z: 0))
                                .rotationEffect(.degrees(2))
                        }
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .chartXScale(domain: xDomain)
                .chartYScale(domain: yDomain)
                .allowsHitTesting(false)
            }
        }
    }

    /// 趨勢線單層（平滑曲線、預設帶漸層面積）。景深需要同一組線畫兩層
    /// （模糊層＋清晰層）疊加；回聲側線（xShift、細、更透明、無面積）也共用此畫法。
    private func trendLine(xDomain: ClosedRange<Date>, yDomain: ClosedRange<Double>,
                           xShift: TimeInterval = 0,
                           lineWidth: CGFloat = 2,
                           lineOpacity: Double = 0.30,
                           showArea: Bool = true) -> some View {
        Chart(points) { p in
            if showArea {
                AreaMark(
                    x: .value("時間", p.date.addingTimeInterval(xShift)),
                    y: .value("數值", p.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(LinearGradient(
                    colors: [.white.opacity(0.22), .white.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom
                ))
            }
            LineMark(
                x: .value("時間", p.date.addingTimeInterval(xShift)),
                y: .value("數值", p.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(.white.opacity(lineOpacity))
            .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .allowsHitTesting(false)
    }
}
