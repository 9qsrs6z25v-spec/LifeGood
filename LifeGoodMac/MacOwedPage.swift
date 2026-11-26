// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.646 mac6 G2] 誰還欠我頁（judge_mac.md §T3-1、§T3-4、§T3-6、§T3-7）：看板、人卡片、〔還沒還｜還清了〕、每一頓表、工具列、表單。
//
// • 主控骨架：`struct MacOwedPage: View` 無參數（MacShell 的 case .owed 用）；G2 換內容。
// • 不准：refresh(、adopt(、MacCloudWriter、journal.、UserDefaults、Logger、print(、NSPasteboard、.copyable(、onCopyCommand、
//   .textSelection、.onDeleteCommand、accessibilityIdentifier、ShareLink、.badge(、GeometryReader、AnyView（§T3-10）。

import SwiftUI

struct MacOwedPage: View {
    var body: some View {
        Text("")
    }
}
