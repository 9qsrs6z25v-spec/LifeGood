import SwiftUI

// MARK: - [v25.599 職能雷達 v1a-1] 雷達元件（G2 負責；radar/judge.md §3.2、§4.3②③、§4.10、§13；radar/build/v1a-1/brief.md §4 G2）
//
// • 只照 CompetencyChartModel 畫（座標、字、狀態都在 CompetencyMath 算好）；body 裡不寫長運算式。
// • Path 畫的 Shape（好 .fill／.stroke(StrokeStyle(dash:))、ImageRenderer 畫得出來）；不用 Swift Charts、不用 Canvas 畫字。
// • 沒評、不適用的軸不畫頂點；有分數的軸少於 3 個只畫點；跳過的那一段畫虛線。v1a 不做形變動畫（新線淡入）。
// • 級數 > 11 只畫 4 圈（model.rings 已經是 4 圈）。
// 骨架（主控）：型別名與 init 參數是跨組契約，不准改；body 由 G2 換成真的。

/// 人格特質紫、系統藍綠（跟執掌 (0.18,0.62,0.60) 分開）
enum CompetencyPalette {
    static let trait = Color(red: 0.55, green: 0.36, blue: 0.96)
    static let system = Color(red: 0.16, green: 0.55, blue: 0.78)

    static func tint(isTrait: Bool) -> Color { isTrait ? trait : system }
}

/// 一張雷達卡：標題「Gas System・10/30 比 4/30」＋右邊「平均 4.3」、雷達（或橫條）、圖例、下面一排橫條
struct CompetencyChartCard: View {
    let model: CompetencyChartModel
    /// 疊上一次（摘要卡「疊：上一次」的開關）
    var showPrevious: Bool = true
    /// 點頂點、軸名、橫條那一列（v1a-2 才接 sheet；v1a-1 傳 nil）
    var onTapAxis: ((UUID) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.headline)
                .font(.subheadline.weight(.semibold))
            CompetencyRadarView(model: model, showPrevious: showPrevious)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 雷達本體（或 1～2 項、13 項以上的橫條）；空殼（還沒評過）也畫軸和名字
struct CompetencyRadarView: View {
    let model: CompetencyChartModel
    var showPrevious: Bool = true

    var body: some View {
        Text(model.accessibilityText)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
