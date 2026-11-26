// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.648 mac7 G2] 總覽中間的每天花多少（judge_mac.md §U3-4）：每日長條＋日預算虛線＋今天虛線＋扣款日站牌點。
//
// • 這版唯一新的 import Charts 檔；BarMark 一律 yStart:／yEnd:（不寫 BarMark(x:… y:)）；mark 都拆成 private func 回 some ChartContent。
// • 色在卡片 body 先算好（讀 colorScheme 一次）、一律 Color：不用漸層、AnyShapeStyle、foregroundStyle(by:)、chartForegroundStyleScale(。
// • 不做點選（沒有 chartXSelection、chartOverlay）；整張一個 VoiceOver 元素。
// • 主控骨架（C0）：MacOverviewDailyCard(data:)、MacOverviewBar、MacOverviewStop 定案（§U7-6）；卡片 body 最簡。G2 換內容。

import SwiftUI
import Charts

/// 長條的一根（under＝日預算以內那截、over＝超過的那截；色先算好）
struct MacOverviewBar: Identifiable {
    let label: String
    let under: Double
    let over: Double
    let underFill: Color
    let overFill: Color

    var id: String { label }
}

/// 扣款日站牌點（past 淡、next／later 實）
struct MacOverviewStop: Identifiable {
    let label: String
    let fill: Color

    var id: String { label }
}

/// §U3-4 每天花多少（.macBoard(.orange)）
struct MacOverviewDailyCard: View {
    let data: MacOverviewBoardData

    var body: some View {
        EmptyView()
    }
}
