// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.646 mac6 G3b] 記帳月曆 popover（judge_mac.md §T6-5）：一格一個記號、沒記的日子不打叉、能按的才包 Button、第 8 欄週打勾。
//
// • 遊戲列第二排〔徽章〕左邊那顆鈕開（MacGameViews，同 MGV:67 寫法），內容外面掛 .macStores(app)；寬 360；Grid／GridRow；
//   格子拆 MacGameCalCell（28×34）；popover 裡不放 ScrollView。
// • 主控骨架：`struct MacGameCalendarPopover: View` 無參數、回 EmptyView()；G3b 換內容。

import SwiftUI

struct MacGameCalendarPopover: View {
    var body: some View {
        EmptyView()
    }
}
