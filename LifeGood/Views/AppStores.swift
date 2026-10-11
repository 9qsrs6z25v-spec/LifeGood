import SwiftUI

// MARK: - 全 App 共用的那一份資料（v25.535）
//
// 使用者在 Mac 上（Mac 跑的 iPad 版）從「我的行事曆」右上角「＋」選「新增部屬任務」就閃退：
// 跳出來的「選擇部屬」畫面拿不到 LifeStore（SwiftUI 的 EnvironmentObject 找不到，直接中止）。
// 平常 sheet 會繼承打開它那一頁的環境，但這條路在 Mac 上沒有繼承到；找不到是執行期閃退，
// 編譯器擋不住，所以不再賭系統一定會轉交。
//
// 記帳、理財、人生三份資料本來就是全 App 唯一的一份（LifeGoodApp 建一次、往下傳），
// 這裡把它們收成固定的一份：LifeGoodApp 用的就是這三個，
// 每一個 sheet／fullScreenCover／popover 的內容再掛 .appStores()，直接拿同一份，不靠繼承。

enum AppStores {
    static let expense = ExpenseStore()
    static let finance = FinanceStore()
    static let life = LifeStore()
}

extension View {
    /// 掛在每一個 sheet／fullScreenCover／popover 內容的最外層：
    /// 把 App 最外層注入的六個共用物件再放一次（都是同一份，不會多一份資料）。
    func appStores() -> some View {
        modifier(AppStoresModifier())
    }
}

private struct AppStoresModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environmentObject(AppStores.expense)
            .environmentObject(AppStores.finance)
            .environmentObject(AppStores.life)
            .environmentObject(CloudSyncManager.shared)
            .environmentObject(SubscriptionManager.shared)
            .environmentObject(EInvoiceSyncManager.shared)
    }
}
