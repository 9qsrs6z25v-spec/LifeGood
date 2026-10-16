import SwiftUI

// MARK: - 分享一趟運動（v25.555，健康 v5；health/judge.md §5.3、待決定 9；build/v5/brief.md §G3）
//
// G3 寫：分享前一張小表單（預覽、「加上路線形狀」預設關、「用我拍的照片當底」）＋算圖（一律淺色、最外層 .appStores()）＋系統分享面板。
// 預設：上半成果看板（天空＋側面的路，沒有路線形狀）、中間大字一行、每公里迷你條、右下「LifeGood」、日期只寫「10/15」。

/// 分享前那張小表單（成果頁「⋯ › 分享」用 .sheet(item:) 打開、最外層 .appStores()）
struct WorkoutShareSheet: View {
    let sessionId: UUID

    init(sessionId: UUID) {
        self.sessionId = sessionId
    }

    var body: some View {
        // G3：照 build/v5/brief.md §G3-5 實作
        Text("分享")
    }
}
