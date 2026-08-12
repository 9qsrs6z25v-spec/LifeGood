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
    /// 顯示用資料點：超過 maxCount（預設 10）點時「分桶移動平均」壓縮至 maxCount 點，
    /// 真實點不足 minCount 時在最前面補合成引導點湊滿——新使用者第一期只有
    /// 1 個點畫不出像樣的曲線，補點讓背景視覺舒服。合成點用「確定性偽隨機漫步」
    /// （種子＝首個真實點的時間＋數值）：同資料形狀固定，不會每次重繪亂跳；
    /// 每步 ±5% 波動、往回各推一個 stepBack 間隔（週資料傳一週、月資料傳一個月）。
    /// 合成點只在顯示時生成，不落地、不進同步。
    static func displayPoints(from raw: [HeroTrendPoint],
                              maxCount: Int = 10,
                              minCount: Int = 6,
                              stepBack: TimeInterval = 604_800) -> [HeroTrendPoint] {
        let real = averaged(raw.sorted { $0.date < $1.date }, maxCount: maxCount)
        // 補點目標不能超過壓縮上限（進階設定把點數調到 6 以下時，以點數上限為準）
        let padTarget = min(minCount, maxCount)
        guard let first = real.first, real.count < padTarget else { return real }
        let padCount = padTarget - real.count
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

    /// 分桶移動平均壓縮至最多 maxCount 點（使用者指定，取代原本的等距丟點取樣）：
    /// 超過 maxCount 點時，最後一點保留「真實最新值」（末端大字要對應目前數字，
    /// 不能被平均稀釋），其餘歷史點均分成 maxCount-1 桶、各取桶內平均值——
    /// 每一筆歷史都貢獻到曲線而不是被丟掉；點的時間取桶內平均時間。
    /// 傳入需已依時間排序。
    static func averaged(_ pts: [HeroTrendPoint], maxCount: Int = 10) -> [HeroTrendPoint] {
        guard pts.count > maxCount, maxCount >= 2 else { return pts }
        let last = pts[pts.count - 1]
        let rest = Array(pts[0..<(pts.count - 1)])
        let bucketCount = maxCount - 1
        var out: [HeroTrendPoint] = []
        let n = rest.count
        for b in 0..<bucketCount {
            let lo = n * b / bucketCount
            let hi = n * (b + 1) / bucketCount
            guard hi > lo else { continue }
            let slice = rest[lo..<hi]
            let avgValue = slice.reduce(0.0) { $0 + $1.value } / Double(slice.count)
            let avgTime = slice.reduce(0.0) { $0 + $1.date.timeIntervalSince1970 } / Double(slice.count)
            out.append(HeroTrendPoint(date: Date(timeIntervalSince1970: avgTime), value: avgValue))
        }
        out.append(last)
        return out
    }
}

/// 英雄卡背景趨勢曲線（白色半透明，適用任何深色漸層底卡）。
/// 至少 2 點才畫、完全不吃觸控；不足 2 點時什麼都不畫（EmptyView）。
/// 傳入「原始序列」即可：壓縮（分桶移動平均）與補點在顯示時依進階設定即時處理，
/// 使用者在「設定 > 進階設定」拉滑桿時（@AppStorage）四張英雄卡立即生效。
struct HeroTrendBackground: View {
    /// 原始序列（未壓縮）
    let points: [HeroTrendPoint]
    /// 合成引導點的回推間隔（週資料傳一週、月資料傳一個月）
    var stepBack: TimeInterval = 604_800
    /// 末端大字數值格式（預設 NT$ 萬元格式）
    var valueText: (Double) -> String = { $0.ntdWanString }
    /// 線條/圓點/數字主色（預設白，適用深色漸層卡；淺色卡傳強調色）
    var tint: Color = .white
    /// 覆寫壓縮點數（nil＝依進階設定；股票項目卡「每日一點」傳原始點數不壓縮）
    var pointLimitOverride: Int? = nil
    /// 是否顯示末端大字數值（項目卡上現價已另有顯示時可關閉、只留實心圓點）
    var showEndLabel: Bool = true

    // 進階設定可調參數（設定 > 進階設定；預設值＝與使用者逐版打磨定案的規格）
    @AppStorage("hero_trend_point_count") private var pointCount: Int = 10
    @AppStorage("hero_trend_opacity") private var mainOpacity: Double = 0.30
    @AppStorage("hero_trend_line_width") private var mainLineWidth: Double = 2.0
    @AppStorage("hero_trend_blur") private var blurRadius: Double = 2.2

    var body: some View {
        let pts = HeroTrendSeries.displayPoints(from: points,
                                                maxCount: max(pointLimitOverride ?? pointCount, 2),
                                                stepBack: stepBack)
        if pts.count >= 2 {
            // 垂直帶映射：把數值範圍映射到卡片高度的 20%~60% 帶——
            // 最低點落在卡片下緣起 20% 高、最高點 60% 高，上方 40% 留白給大字。
            // 作法：把 Y 軸 domain 反推放大——實際值域佔 domain 的 0.4，下方預留 0.2。
            let values = pts.map(\.value)
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 1
            let spread = max(maxV - minV, max(maxV * 0.05, 1))   // 平盤保底，避免除以零
            let span = spread / 0.4
            let domainLow = minV - 0.2 * span
            let domainHigh = domainLow + span
            let xFirst = pts.first?.date ?? Date()
            let xLast = pts.last?.date ?? Date()
            // X 軸右側延伸 25% 資料跨距：資料只佔左邊 80% 寬
            let xSpan = max(xLast.timeIntervalSince(xFirst), 1)
            let xHigh = xLast.addingTimeInterval(xSpan * 0.25)
            let xDomain = xFirst...xHigh
            let yDomain = domainLow...domainHigh
            // 回聲側線：透明度／線寬與主線連動（維持既定比例 0.44 / 0.5）
            let echoOpacity = mainOpacity * 0.44
            let echoWidth = max(mainLineWidth * 0.5, 0.5)
            // 回聲側線尾端收細：Charts 無法沿路徑變線寬，用尾端漸層遮罩淡出模擬
            let echoShift = xSpan * 1.25 * 0.01   // domain 全寬（含右延 25%）的 1%
            let echoTailTaper = LinearGradient(stops: [
                .init(color: .white, location: 0.00),
                .init(color: .white, location: 0.45),
                .init(color: .clear, location: 0.80)   // 資料終點約在 80% 寬，尾段漸淡收掉
            ], startPoint: .leading, endPoint: .trailing)
            let trendGroup = ZStack {
                trendLine(pts, xDomain: xDomain, yDomain: yDomain,
                          xShift: -echoShift, lineWidth: echoWidth,
                          lineOpacity: echoOpacity, showArea: false)
                    .mask(echoTailTaper)
                trendLine(pts, xDomain: xDomain, yDomain: yDomain,
                          xShift: echoShift, lineWidth: echoWidth,
                          lineOpacity: echoOpacity, showArea: false)
                    .mask(echoTailTaper)
                trendLine(pts, xDomain: xDomain, yDomain: yDomain,
                          lineWidth: mainLineWidth, lineOpacity: mainOpacity)
            }
            ZStack {
                // 景深（左模糊→右漸清晰）：整組三線畫兩層——底層整組高斯模糊、
                // 頂層清晰，各用互補的左右漸層遮罩交叉淡化，像相機失焦漸變到合焦。
                trendGroup
                    .blur(radius: blurRadius)
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
                // 上層：最後一個（真實）點——圓形實心＋大字數值（透明度隨進階設定）
                Chart(pts) { p in
                    if p.id == pts.last?.id {
                        PointMark(
                            x: .value("時間", p.date),
                            y: .value("數值", p.value)
                        )
                        .foregroundStyle(tint.opacity(mainOpacity))
                        .symbol(.circle)
                        .symbolSize(90)
                        .annotation(position: .top,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            if showEndLabel {
                                Text(valueText(p.value))
                                    .font(.system(size: 19, weight: .bold, design: .rounded))
                                    .foregroundStyle(tint.opacity(mainOpacity))
                                    .shadow(color: .black.opacity(0.12), radius: 1.5, x: 0, y: 1)
                                    // 立體微傾：X/Y 軸各轉 5 度、Z 軸轉 2 度，呼應景深構圖
                                    .rotation3DEffect(.degrees(5), axis: (x: 1, y: 0, z: 0))
                                    .rotation3DEffect(.degrees(5), axis: (x: 0, y: 1, z: 0))
                                    .rotationEffect(.degrees(2))
                            }
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
    private func trendLine(_ data: [HeroTrendPoint],
                           xDomain: ClosedRange<Date>, yDomain: ClosedRange<Double>,
                           xShift: TimeInterval = 0,
                           lineWidth: CGFloat = 2,
                           lineOpacity: Double = 0.30,
                           showArea: Bool = true) -> some View {
        Chart(data) { p in
            if showArea {
                AreaMark(
                    x: .value("時間", p.date.addingTimeInterval(xShift)),
                    y: .value("數值", p.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(LinearGradient(
                    colors: [tint.opacity(0.22), tint.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom
                ))
            }
            LineMark(
                x: .value("時間", p.date.addingTimeInterval(xShift)),
                y: .value("數值", p.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(tint.opacity(lineOpacity))
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

// MARK: - 股價＋成交量複合背景（股票項目卡用）

/// 股票項目卡背景：上方每日收盤價曲線（沿用 HeroTrendBackground 完整模板、
/// 每日一點不壓縮、不顯示末端大字——卡片右側已有現價），下方每日成交量
/// 柱狀圖（最高量柱只到卡片約 20% 高，當作曲線的底座）。
/// 白卡上用強調色 tint 繪製；量柱透明度獨立於曲線透明度，
/// 由「進階設定 > 圖表設定 > 股票」單獨調整（使用者反映量柱不明顯）。
struct HeroPriceVolumeBackground: View {
    /// 每日收盤價（原始序列）
    let prices: [HeroTrendPoint]
    /// 每日成交量（原始序列，與 prices 同日期範圍）
    let volumes: [HeroTrendPoint]
    var tint: Color = .white

    @AppStorage("hero_volume_bar_opacity") private var volumeBarOpacity: Double = 0.45

    var body: some View {
        ZStack {
            // 底層：成交量柱狀圖（X domain 與價格曲線同樣右延 25%，柱與曲線點對齊）
            if volumes.count >= 2, let maxVol = volumes.map(\.value).max(), maxVol > 0 {
                let xFirst = volumes.first?.date ?? Date()
                let xLast = volumes.last?.date ?? Date()
                let xSpan = max(xLast.timeIntervalSince(xFirst), 1)
                let xHigh = xLast.addingTimeInterval(xSpan * 0.25)
                Chart(volumes) { v in
                    BarMark(
                        x: .value("日", v.date),
                        y: .value("量", v.value),
                        width: .fixed(1.5)
                    )
                    .foregroundStyle(tint.opacity(volumeBarOpacity))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .chartXScale(domain: xFirst...xHigh)
                .chartYScale(domain: 0...(maxVol / 0.20))   // 最高量柱佔卡片 20% 高
                .allowsHitTesting(false)
            }
            // 上層：收盤價曲線（每日一點、關閉末端大字）
            HeroTrendBackground(
                points: prices,
                stepBack: 86_400,
                tint: tint,
                pointLimitOverride: max(prices.count, 2),
                showEndLabel: false
            )
        }
    }
}
