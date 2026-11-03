import SwiftUI

// MARK: - [v25.599 職能雷達 v1a-1] 評分畫面（G3 負責；radar/judge.md §3.7、§4.5、§13；radar/build/v1a-1/brief.md §4 G3）
//
// • sheet .large；日期（不能晚於今天；同一天或已有那天就打開那一張）、這次評、〔全部照上次〕／〔這組照上次〕（範圍不同不帶）、
//   灰點上次、high ≤ 10 一排／兩排圓按鈕、high > 10 滑桿＋數字欄＋〔－〕〔＋〕（§13）、淡框點一下＝確認、〔⋯〕清掉、
//   只在下一格空的才捲、底部那一行＋〔儲存〕、VoiceOver 可調整。
// • 規則全部在 CompetencyMath（ratingPlan、carriedCells、draft(from:)、footerCounts、footerText、buildSession、savedToast）。
// • 存檔：先 dismiss，下一個 runloop 再 lifeStore.saveCompetencySession。
// 骨架（主控）：型別名與 init 參數是跨組契約，不准改；body 由 G3 換成真的。

/// 打開評分畫面的請求（sheet(item:) 用）
struct CompetencyRatingRequest: Identifiable {
    let id = UUID()
    let subordinateId: UUID
    /// 要評哪一天（nil＝今天）
    var dayKey: String? = nil
}

struct CompetencyRatingSheet: View {
    let request: CompetencyRatingRequest
    /// 存好之後（已經 dismiss）給〔職能〕分頁顯示底部小提示「已儲存 10/30 的評分（12 格）」
    var onSaved: ((String) -> Void)? = nil

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Text("評分")
                .navigationTitle("評分")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                }
        }
    }
}
