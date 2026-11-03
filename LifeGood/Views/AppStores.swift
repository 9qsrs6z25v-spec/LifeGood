import SwiftUI
import UIKit

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
//
// [手錶 v1] v25.574（watch/judge.md §5.4、watch/build/v1/brief.md G1-4）：三份第一次被建立時叫 AppStoresDiagnostics.noteCreated()，
// App 那時在背景（iCloud 靜默推播、手錶叫醒 iPhone）就在 App Group 記一次；設定頁「Apple Watch」段寫「背景建立資料：N 次」。
// 用一週是 0，才證明「被手錶叫醒不碰帳本」真的成立。建立的東西、時機一點都沒變。

enum AppStores {
    static let expense: ExpenseStore = {
        AppStoresDiagnostics.noteCreated()
        return ExpenseStore()
    }()
    static let finance: FinanceStore = {
        AppStoresDiagnostics.noteCreated()
        return FinanceStore()
    }()
    static let life: LifeStore = {
        AppStoresDiagnostics.noteCreated()
        return LifeStore()
    }()
}

/// [手錶 v1] 三份資料在 App 背景時被建立的次數（給查問題用，judge §5.4）。
/// 一次啟動只記第一次（三份一起建也只算一次）。static 初始化不一定在主執行緒，
/// 所以不在那裡讀 UIApplication：先排到主執行緒再看。
/// 前景啟動時，畫面（場景）還沒接上的那一下 applicationState 也可能是 .background：
/// 看到背景先等 3 秒再看一次，還在背景才算（前景啟動那時早就是 .inactive／.active 了）。
/// 這 3 秒中間 App 被系統暫停過（背景叫醒做完就被暫停，下次回來可能已經是前景；實際過了遠超過 3 秒）也算背景，
/// 免得正好漏掉要查的那一種（被手錶、iCloud 推播叫醒）。
enum AppStoresDiagnostics {
    /// App Group：背景建立了幾次（Int）
    static let countKey = "watch_diag_bg_store_inits"
    /// App Group：最近一次是什麼時候（1970 起的秒，Double）
    static let lastKey = "watch_diag_bg_store_last"
    /// 這次啟動已經看過了（只在主執行緒讀寫）
    @MainActor private static var noted = false
    /// 等 3 秒、實際過了超過這麼久＝中間被系統暫停過（App 那時在背景）
    private static let suspendedAfterSeconds: TimeInterval = 10

    /// AppStores 三份的初始化叫（任何執行緒）
    static func noteCreated() {
        Task { @MainActor in
            await AppStoresDiagnostics.recordIfBackground()
        }
    }

    @MainActor
    static func recordIfBackground() async {
        guard !noted else { return }
        noted = true
        guard UIApplication.shared.applicationState == .background else { return }
        let seenAt = Date()
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        let wasSuspended = Date().timeIntervalSince(seenAt) > suspendedAfterSeconds
        guard wasSuspended || UIApplication.shared.applicationState == .background else { return }
        let d = WidgetShared.defaults
        d?.set(count + 1, forKey: countKey)
        d?.set(seenAt.timeIntervalSince1970, forKey: lastKey)
    }

    /// 設定頁「背景建立資料：N 次」
    static var count: Int {
        WidgetShared.defaults?.integer(forKey: countKey) ?? 0
    }

    /// 最近一次（沒有過是 nil）
    static var last: Date? {
        let t = WidgetShared.defaults?.double(forKey: lastKey) ?? 0
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }
}

extension View {
    /// 掛在每一個 sheet／fullScreenCover／popover 內容的最外層：
    /// 把 App 最外層注入的六個共用物件再放一次（都是同一份，不會多一份資料）。
    ///
    /// 回傳 AnyView：sheet 內容的型別會變成主畫面型別的一部分，有些頁面（行程詳情）
    /// 掛了二十幾個 sheet，型別太深在執行時 demangle 爆過棧。在這裡抹掉，
    /// 每個 sheet 的內容型別反而比以前短。只在 sheet 最外層用一次，不影響效能。
    func appStores() -> AnyView {
        AnyView(modifier(AppStoresModifier()))
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
