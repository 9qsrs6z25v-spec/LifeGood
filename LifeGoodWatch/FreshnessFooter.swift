import SwiftUI

// MARK: - 資料多舊的那一行（judge §5.6；brief G3-6）（手錶 v1，v25.574）
//
// 只屬於 LifeGoodWatch。① 今天、今天全部、② 錢、接下來要繳的最下面一行。
// 字一律是 WatchText.lifeFreshness／moneyFreshness 組好的（WidgetDateText 那一套，門檻同 WidgetFreshness）：
//   今天的行程：3 小時內不寫；3 小時～2 天「09:24 更新」（灰）；超過 2 天琥珀；過期「打開 iPhone 上的 LifeGood，更新今天的行程」（琥珀）
//   錢、要繳：2 天內不寫；超過「上次更新 10/20」（灰）；過了下個月 7 號「打開 iPhone 上的 LifeGood 一次」（琥珀）
// nil＝不畫（連空白都不佔）。這一行沒有金額、人名，手腕放下不用換字。

struct FreshnessFooter: View {
    /// WatchText.lifeFreshness／moneyFreshness 的結果；nil＝不畫
    let freshness: WatchFreshness?

    var body: some View {
        if let f = freshness {
            Text(f.text)
                .font(.footnote)
                .foregroundStyle(f.isAmber ? WatchStyle.amber : WatchStyle.small)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
