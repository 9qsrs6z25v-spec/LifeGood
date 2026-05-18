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
                }
                .onAppear {
                    BackupManager.shared.createSnapshotIfNeeded(
                        expense: expenseStore, finance: financeStore, life: lifeStore
                    )
                    cloudSync.syncNow()
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
