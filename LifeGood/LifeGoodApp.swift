import SwiftUI
import UIKit
import CloudKit

/// 處理 CloudKit silent remote notification 與 APNs 註冊。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 註冊靜默推播以接收 CKRecordZoneSubscription 變更
        application.registerForRemoteNotifications()
        return true
    }

    /// SwiftUI 生命週期下，CKShare 邀請連結的接受回呼走 UIWindowSceneDelegate 而非
    /// UIApplicationDelegate；指定自訂 SceneDelegate 承接（不實作視窗建立，SwiftUI 照常管理視窗）。
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = ShareSceneDelegate.self
        return config
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // 只有使用者啟用同步時才處理推播，避免覆蓋本地資料
        guard CloudSyncManager.shared.isEnabled else {
            completionHandler(.noData); return
        }
        CloudKitManager.shared.handleRemoteNotification(userInfo: userInfo, completion: completionHandler)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // CloudKit 仍可使用 foreground polling，這裡僅靜默忽略
    }
}

/// 承接 CKShare 邀請連結：使用者點擊「加入共享」後系統喚起 App 並呼叫這裡。
/// App 未執行時的冷啟動接受走 willConnectTo 的 connectionOptions。
final class ShareSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        CloudKitManager.shared.acceptShare(cloudKitShareMetadata)
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        if let meta = connectionOptions.cloudKitShareMetadata {
            CloudKitManager.shared.acceptShare(meta)
        }
    }
}

@main
struct LifeGoodApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var expenseStore = ExpenseStore()
    @StateObject private var financeStore = FinanceStore()
    @StateObject private var lifeStore = LifeStore()
    @StateObject private var cloudSync = CloudSyncManager.shared
    @StateObject private var subscription = SubscriptionManager.shared
    @StateObject private var einvoiceSync = EInvoiceSyncManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            // 開場謝幕動畫的狀態與 withAnimation **必須住在一個真正的 View 裡**
            //（LaunchGate）。先前兩版失敗的修法（v25.234 的 .transition、
            // v25.240 的 modifier 動畫）狀態都掛在 App 結構上、由 Scene body 重算驅動
            // ——App 不是 View，Scene 根層的重算會丟棄動畫交易，withAnimation 形同
            // 直接賦值，使用者永遠看到硬切。搬進 View 之後才是一般的、可靠的動畫路徑。
            LaunchGate {
            MainTabView()
                .environmentObject(expenseStore)
                .environmentObject(financeStore)
                .environmentObject(lifeStore)
                .environmentObject(cloudSync)
                .environmentObject(subscription)
                .environmentObject(einvoiceSync)
                .task {
                    await subscription.refreshStatus()
                    await subscription.loadProducts()
                    await einvoiceSync.syncIfDue(expenseStore: expenseStore)
                    // 啟動時重排所有事件提醒，讓舊事件升級到新版 body / 截止日邏輯
                    await NotificationManager.shared.rescheduleAll(events: lifeStore.personalEvents)
                    // 冷啟動順帶刷新自訂幣別匯率（與設定頁那顆按鈕同一套邏輯，
                    // 認不得的幣別維持手動值）。放最後、結果不看：開場動畫期間
                    // 網路慢也不擋任何啟動流程，失敗就沿用上次的值。
                    _ = await expenseStore.autoUpdateCurrencyRates()
                }
                .onAppear {
                    BackupManager.shared.createSnapshotIfNeeded(
                        expense: expenseStore, finance: financeStore, life: lifeStore
                    )
                    cloudSync.syncNow()
                    // 拉取遠端訂閱總開關 + 人數，並（必要時）註冊本使用者
                    RemoteAdminManager.shared.bootstrap()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        BackupManager.shared.createSnapshotIfNeeded(
                            expense: expenseStore, finance: financeStore, life: lifeStore
                        )
                    } else if phase == .active {
                        // 節流：30 秒內已同步過會自動跳過，避免快速切換 App
                        // 造成的反覆 CloudKit pull 觸發畫面閃爍
                        cloudSync.syncNowIfDue()
                        Task {
                            await subscription.refreshStatus()
                            await einvoiceSync.syncIfDue(expenseStore: expenseStore)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 開場閘門（真正的 View，動畫在這裡才會播）

/// 包住主畫面的開場層。冷啟動時蓋著品牌開場 1.4 秒，然後「往觀者方向放大 + 淡出」
/// 謝幕，主畫面同時從 97% 回正；動畫播完才卸載開場層（卸載瞬間已全透明）。
/// @State 屬於這個 View，只在程序重建（冷啟動）時重置——從背景喚醒不重播，
/// 「看到開場＝App 曾被系統終止」的目視判斷維持不變。
///
/// 動畫用 .animation(value:) 綁定驅動（不靠 withAnimation 的交易傳遞）：
/// 值一變就在本視圖層級播動畫，這是整個 App 其他動畫走的同一條路徑。
private struct LaunchGate<Content: View>: View {
    @ViewBuilder let content: Content

    @State private var showSplash = true
    @State private var splashDismissed = false

    var body: some View {
        ZStack {
            content
                .scaleEffect(showSplash && !splashDismissed ? 0.97 : 1)
                .animation(.easeInOut(duration: 0.6), value: splashDismissed)

            if showSplash {
                LaunchSplashView()
                    .opacity(splashDismissed ? 0 : 1)
                    .scaleEffect(splashDismissed ? 1.1 : 1)
                    .animation(.easeInOut(duration: 0.6), value: splashDismissed)
                    .allowsHitTesting(!splashDismissed)
                    .zIndex(10)
                    .task {
                        // 開場停留 1.4 秒後謝幕；只擋視覺不擋啟動流程
                        //（content 的 task/onAppear 同步照常執行）
                        try? await Task.sleep(nanoseconds: 1_400_000_000)
                        splashDismissed = true
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        showSplash = false
                    }
            }
        }
    }
}

// MARK: - 美化紀錄（LaunchSplashView）
// [2026-08 v1] 本次美化方向（聚焦這一個元件）：
//   1. 品牌圖示圓原本只有 fill + stroke，是全 App 唯一一個「圖示圓」規格完全沒有陰影的
//      地方（TravelMapView／ExpenseRow 等圖示圓皆搭配 accent.opacity 光暈陰影，見
//      TravelMapView.spotRow shadow(color: accent.opacity(0.22), radius: 6) 慣例）。
//      補上白色光暈陰影 shadow(color: .white.opacity(0.30), radius: 22)，在漸層底色上
//      呈現向外擴散的品牌光暈，強化開場第一眼的質感與立體感，對齊全 App 圖示圓陰影規格。
//      純視覺調整，開場動畫時序（1.4 秒後淡出）與冷啟動判斷邏輯完全未變動。
//   （下次美化本檔案時，可轉往其他仍留有待辦的畫面）
//
// 品牌開場：漸層底 + 圖示圓 spring 進場 + 標題淡入上移，底部顯示目前版本/建置號。
// 只在冷啟動出現（見 LifeGoodApp.showSplash 註解），可作為「App 曾被殺」的目視指標。

private struct LaunchSplashView: View {
    @State private var iconAppeared = false
    @State private var textAppeared = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.45, blue: 0.94),
                         Color(red: 0.10, green: 0.68, blue: 0.62)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            // 散景裝飾圓（對齊全 App 英雄卡視覺語言）
            Circle().fill(.white.opacity(0.10)).frame(width: 220, height: 220)
                .offset(x: 130, y: -260).blur(radius: 18)
            Circle().fill(.white.opacity(0.07)).frame(width: 160, height: 160)
                .offset(x: -120, y: 240).blur(radius: 14)

            VStack(spacing: 18) {
                ZStack {
                    Circle().fill(.white.opacity(0.16)).frame(width: 110, height: 110)
                    Circle().stroke(.white.opacity(0.35), lineWidth: 1).frame(width: 110, height: 110)
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(.white)
                }
                // v1 美化：白色光暈陰影，對齊全 App 圖示圓陰影規格
                .shadow(color: .white.opacity(0.30), radius: 22)
                .scaleEffect(iconAppeared ? 1.0 : 0.72)
                .opacity(iconAppeared ? 1 : 0)

                VStack(spacing: 6) {
                    Text("美好人生")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                    Text("LifeGood")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .opacity(textAppeared ? 1 : 0)
                .offset(y: textAppeared ? 0 : 12)
            }

            // 版本號：目視確認目前跑的 build（冷啟動指標的附加價值）
            VStack {
                Spacer()
                if let entry = Changelog.entries.first {
                    Text("v\(entry.version)（\(entry.build)）")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.bottom, 18)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { iconAppeared = true }
            withAnimation(.easeOut(duration: 0.4).delay(0.25)) { textAppeared = true }
        }
    }
}
