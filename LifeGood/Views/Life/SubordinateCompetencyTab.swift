import SwiftUI

// MARK: - [v25.599 職能雷達 v1a-1] 部屬卡片〔職能〕分頁（G1 負責；radar/judge.md §4.3、§5、§6、§3.6；radar/build/v1a-1/brief.md §4 G1）
//
// • 由上到下：摘要卡（不寫 0–100）→ 人格特質卡（0 項整張不出現）→ 每個系統一張 → 不用學的系統一行。
// • 看不擋；〔評分〕〔不用學的系統〕〔用範例開始〕〔自己設定〕要訂閱（isPremium／premiumLockAlert）。
// • 已轉出：〔評分〕藏起來、「已轉出，評分留著可以看」；這台的 App 比較舊：〔評分〕藏起來、頂上一行說明。
// • 整頁的數字、字只照 CompetencyMath.tabModel；sheet 一律 sheet(item:)＋.appStores()；dismiss 後寫 store 放下一個 runloop。
// 骨架（主控）：型別名與 init 參數是跨組契約，不准改；body 由 G1 換成真的。

struct SubordinateCompetencyTab: View {
    let subordinateId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("職能")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }
}
