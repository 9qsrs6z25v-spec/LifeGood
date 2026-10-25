import SwiftUI
import UIKit
import CloudKit
import UserNotifications

/// 處理 CloudKit silent remote notification 與 APNs 註冊。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 註冊靜默推播以接收 CKRecordZoneSubscription 變更
        application.registerForRemoteNotifications()
        // [v25.454] 接手通知的前景顯示與點擊：
        //   • 前景顯示：沒有 delegate 時，App 開著收到的通知會被系統靜靜丟掉。
        //     行事曆提醒一直是這樣——人正在用 App，提醒就不會出現。
        //   • 點擊：旅遊的跨裝置通知要能點進那一份行程。
        // [手錶 v3] 通知的按鈕（〔5 分鐘後再提醒〕〔明天 9 點再提醒〕〔晚上再提醒〕）：每次啟動都要登記（背景冷啟動也是）
        NotificationActions.registerCategories()
        UNUserNotificationCenter.current().delegate = self
        // [手錶 v1] 手錶傳話（WCSession）一啟動就接上：手錶在背景叫醒 iPhone 時（「給我最新的」）要有人接（judge §5.4）。
        // 只讀 App Group 的檔、不碰三份資料；iPad、Mac 上 WCSession.isSupported() 是 false，什麼都不做
        WatchBridge.shared.activate()
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

// MARK: - 本機通知的前景顯示與點擊（v25.454）

extension AppDelegate: UNUserNotificationCenterDelegate {

    /// App 在前景時也要顯示。沒有這個方法，開著 App 收到的通知會被系統丟掉。
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    /// 點通知：旅遊的跨裝置通知帶了行程 id，切到旅遊地圖並打開那一份行程。
    /// 其他通知（行事曆提醒）沒帶 id，就只是開 App，維持原本行為。
    /// [手錶 v3] 按鈕（再提醒）見 NotificationActions.handle：第一件事就交給它，是按鈕就不往下走。
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // [手錶 v3] 第一件事看按了哪一顆：再提醒是背景動作（手錶上按也在這裡跑，可能是 iPhone 背景冷啟動）。
        // 只碰通知中心、自己叫 completionHandler；一定 return，不准往下走到底下的 AppStores.life
        if NotificationActions.handle(response, completion: completionHandler) { return }
        let info = response.notification.request.content.userInfo
        if let raw = info[TripChangeNotifier.planIdKey] as? String,
           let id = UUID(uuidString: raw) {
            Task { @MainActor in
                AppNavigation.goToTravelMap()
                DeepLinkRouter.shared.requestTripPlan(id)
            }
        } else if let raw = info[DeepLinkRouter.meetingNotificationKey] as? String {
            // [v25.455] 部屬會議提醒 → 切到「我的行事曆」並打開那場會議的卡片
            Task { @MainActor in
                AppNavigation.goToMyCalendar()
                DeepLinkRouter.shared.requestTimelineStop(
                    DayTimelineLink.stopIdForMeeting(uuidString: raw))
            }
        } else if let raw = info[DeepLinkRouter.wealthNotificationKey] as? String,
                  let id = UUID(uuidString: raw) {
            // [財富 v4] 財富提醒（WealthReminders）→ 切到人生 › 財富並打開那張卡／那個帳戶。
            // 跟小工具卡費列同一個總入口（WidgetLink.apply 的 .wealth：goToWealth＋requestItem）；不是從小工具來的，不帶 src=widget
            Task { @MainActor in
                _ = WidgetLink.apply(WidgetLink.url(for: .wealth(id: id), fromWidget: false), store: AppStores.life)
            }
        }
        completionHandler()
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
    // [v25.535] 三份資料改用 AppStores 那一份：sheet 的內容用 .appStores() 拿的是同一份
    @StateObject private var expenseStore = AppStores.expense
    @StateObject private var financeStore = AppStores.finance
    @StateObject private var lifeStore = AppStores.life
    @StateObject private var cloudSync = CloudSyncManager.shared
    @StateObject private var subscription = SubscriptionManager.shared
    @StateObject private var einvoiceSync = EInvoiceSyncManager.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // [v2 小工具] 控制項「記一筆」（LifeGoodOpenIntent，openAppWhenRun）把網址交到這裡：
        // 跟 onOpenURL 同一個總入口（WidgetLink.apply），快速通道、預填、自動聚焦全部共用。
        // 登記完 register 會馬上撿 App Group 裡 20 秒內存著的網址（intent 萬一在小工具的行程裡跑）
        WidgetOpenAppHandoff.register { url in
            _ = WidgetLink.apply(url, store: AppStores.life)
        }
        // [v5] 控制中心「今日行程」、中型「今天」的「上靈動島」（LiveActivityIntent，在 App 的行程裡背景跑）交到這裡：
        // 跟設定頁的開關同一個 isEnabled（DayTimelineController.setEnabled）
        DayTimelineToggleBridge.register { on in
            await DayTimelineController.shared.setEnabled(on, store: AppStores.life)
            // 今天沒有行程時不能卡在系統先畫的「開」：不管有沒有上島都叫控制項重讀一次
            WidgetRefresh.reloadControls(WidgetKind.dayTimelineControlKinds)
        }
        // [健康 v6] 鎖定畫面／靈動島的暫停鈕（RunPauseIntent，LiveActivityIntent，在 App 的行程裡背景跑）交到這裡：
        // 是正在記錄的那一趟就暫停／繼續，不是（App 被關掉後留下的）就收掉
        RunPauseBridge.register { pause, runId in
            await RunActivityCenter.shared.handlePauseButton(pause: pause, runId: runId)
        }
    }

    var body: some Scene {
        WindowGroup {
            // 開場謝幕動畫的狀態與 withAnimation **必須住在一個真正的 View 裡**
            //（LaunchGate）。先前兩版失敗的修法（v25.234 的 .transition、
            // v25.240 的 modifier 動畫）狀態都掛在 App 結構上、由 Scene body 重算驅動
            // ——App 不是 View，Scene 根層的重算會丟棄動畫交易，withAnimation 形同
            // 直接賦值，使用者永遠看到硬切。搬進 View 之後才是一般的、可靠的動畫路徑。
            LaunchGate {
            MainTabView()
                // [v25.521] 量主畫面大小（iPad／Mac 的視窗可以拉伸了），一整頁的 sheet 照它撐開
                .measuresAppWindow()
                .environmentObject(expenseStore)
                .environmentObject(financeStore)
                .environmentObject(lifeStore)
                .environmentObject(cloudSync)
                .environmentObject(subscription)
                .environmentObject(einvoiceSync)
                .task {
                    // [v2 小工具] 一按就記的收件匣先收進帳本（第一份快照才含剛記的）；
                    // 放在電子發票同步（einvoiceSync.syncIfDue）之前，防重複才找得到一按記的那筆
                    // [手錶 v6] 多收 life：旅途中在手錶記的帳入帳時要看那一趟、那一站還在不在（連旅遊）
                    QuickRecordImporter.shared.start(expense: expenseStore, finance: financeStore, life: lifeStore)
                    // [v25.545] 桌面小工具的快照：掛好監聽、馬上寫一次（放在任何 await 之前，
                    // 開場動畫期間就寫好；第二次呼叫什麼都不做）。[v2] 多收 finance（車子卡、接下來要繳）
                    WidgetSnapshotWriter.shared.start(expense: expenseStore, finance: financeStore, life: lifeStore)
                    // [手錶 v6] 手錶的打卡：記住 LifeStore（之後手錶打卡馬上寫進行程）、把 iPhone 沒開時排著的
                    // 照按下去的時間套進行程。要在寫手 start 之後：套完才寫得出新的手錶包
                    WatchActionApplier.shared.start(life: lifeStore)
                    WatchActionApplier.shared.applyPending()
                    // [手錶 v7a] 手錶的說一句：記住三份資料（之後手錶說一句、App 活著就馬上記）。排著的等下面讀完訂閱才記
                    WatchVoiceApplier.shared.start(expense: expenseStore, finance: financeStore, life: lifeStore)
                    // [財富 v4] 財富提醒（卡費截止、可能不夠扣的扣款與交割、卡片快到期；通知不寫卡名、金額、號碼）：
                    // 掛好監聽（記帳／理財／人生一改，防抖 3 秒重排）、馬上排一次；第二次呼叫什麼都不做。
                    // 同步呼叫、不 await：授權照 MeetingReminders 的慣例，有要排的才問（WealthReminderCenter 裡）
                    WealthReminderCenter.shared.start(expense: expenseStore, finance: financeStore, life: lifeStore)
                    // [財富 v7] 給網頁版的財富數字（life_wealth_facts_v1：合計、暱稱、後 4 碼、存摺上、要繳、交割、定存到期日；
                    // 沒有完整號碼、有效期限）：掛好監聽（防抖 5 秒）、馬上寫一次；跟上次一樣就不寫。第二次呼叫什麼都不做
                    WealthWebFactsWriter.shared.start(expense: expenseStore, finance: financeStore, life: lifeStore)
                    // [v25.552] 找上次跑到一半被關掉、還沒存的那幾趟（讀檔在背景，很快）。
                    // 放在其他 await 前面：開場謝幕（約 2 秒）之前就找好，LaunchGate 謝幕後問一次
                    await RunRecoveryCenter.shared.scan()
                    // [健康 v6] 上次 App 被關掉時留在鎖定畫面的跑步即時動態（時間還在走、按了沒用）：收掉；
                    // 正在記錄的那一趟、已經結束的「完成」那張不動。沒在記錄時一起取消暫停 30 分鐘提醒
                    await RunActivityCenter.shared.endLeftovers(keeping: RunTracker.shared.activeRunId)
                    await subscription.refreshStatus()
                    // [手錶 v7a] 訂閱讀進來了：手錶包的「說一句能不能用」跟著對（剛打開時可能寫成 false）；iPhone 沒開時手錶說的那幾句現在記
                    WatchExtrasWriter.refreshVoiceReady()
                    WatchVoiceApplier.shared.applyPending()
                    await subscription.loadProducts()
                    await einvoiceSync.syncIfDue(expenseStore: expenseStore)
                    // 啟動時重排所有提醒，讓舊事件升級到新版 body / 截止日邏輯。
                    // [v25.455] 改走 ReminderCenter：它會把「通知 or 鬧鐘」分流，
                    // 並且一併排部屬會議的提醒（部屬會議在此之前完全沒有提醒）。
                    await ReminderCenter.rebuildAll(events: lifeStore.personalEvents,
                                                    subordinates: lifeStore.subordinates,
                                                    tripPlans: lifeStore.tripPlans)
                    // 冷啟動順帶刷新自訂幣別匯率（與設定頁那顆按鈕同一套邏輯，
                    // 認不得的幣別維持手動值）。放最後、結果不看：開場動畫期間
                    // 網路慢也不擋任何啟動流程，失敗就沿用上次的值。
                    _ = await expenseStore.autoUpdateCurrencyRates()
                    // [v5] 控制項在小工具的行程裡被按了、沒交到 App（保險）：照使用者按的開／關
                    if let want = DayTimelineToggleState.takePending() {
                        await DayTimelineController.shared.setEnabled(want, store: lifeStore)
                    }
                    // [v25.377] 靈動島的今日行程：沒開啟就直接返回，不會做任何事
                    await DayTimelineController.shared.refresh(store: lifeStore)
                }
                // [v25.381] 從靈動島／鎖定畫面點進來：切到「我的行事曆」
                // [v25.545] 改走總入口：lifegood://today… 照舊交給 DayTimelineLink.apply，
                // 另外認得小工具的 lifegood://expense/overview（收支總覽）
                .onOpenURL { url in
                    _ = WidgetLink.apply(url, store: lifeStore)
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
                        // [v25.545] 保底：離開 App 那一刻小工具的快照一定是最新的
                        WidgetSnapshotWriter.shared.writeNow()
                        // [財富 v7] 網頁版那一包也寫一次（force：平常 App 在背景時寫手不寫，這裡是你剛離開，以這台為準）
                        WealthWebFactsWriter.shared.writeNow(force: true)
                    } else if phase == .active {
                        // [健康 v6] 正在記錄、跑步的即時動態不見了（系統 8 小時收掉、一開始系統關著）就重開；快 8 小時了收舊開新
                        RunActivityCenter.shared.appBecameActive()
                        // 節流：30 秒內已同步過會自動跳過，避免快速切換 App
                        // 造成的反覆 CloudKit pull 觸發畫面閃爍
                        cloudSync.syncNowIfDue()
                        // [v2 小工具] 先把一按就記的待入帳收進帳本，再接控制項存著的網址（萬一沒直接交到），
                        // 最後才重寫快照（「今天 N 筆」含剛收進來的）
                        _ = QuickRecordImporter.shared.importPending()
                        // [手錶 v6] iPhone 沒開時手錶打的卡（watch_actions_v1 排著的）照按下去的時間寫進行程
                        WatchActionApplier.shared.applyPending()
                        WidgetOpenAppHandoff.consumeStored()
                        // [v25.545] 今天往前走了（過了午夜、過了一場）：重寫小工具快照，內容沒變就不寫
                        WidgetSnapshotWriter.shared.writeNow()
                        // [財富 v4] 財富提醒跟著今天往前走（過了截止日、標成已繳、換了月）重排；要排的跟上次一樣就不動通知中心
                        WealthReminderCenter.shared.rebuildSoon()
                        Task {
                            await subscription.refreshStatus()
                            // [手錶 v7a] 回前景：訂閱、AI 設定可能改了，手錶包的「說一句能不能用」跟著對；
                            // iPhone 沒開時手錶說的那幾句（watch_voice_v1 排著的）照講完的時間記
                            WatchExtrasWriter.refreshVoiceReady()
                            WatchVoiceApplier.shared.applyPending()
                            await einvoiceSync.syncIfDue(expenseStore: expenseStore)
                            // [v5] 控制項在小工具的行程裡被按了、沒交到 App（保險）：照使用者按的開／關
                            if let want = DayTimelineToggleState.takePending() {
                                await DayTimelineController.shared.setEnabled(want, store: lifeStore)
                            }
                            // [v25.377] 回到前景就重算時間軸：8 小時到期被系統收掉的
                            // Live Activity 也會在這裡重新掛上
                            // [v5] 控制中心在背景開不了島（Activity.request 被擋）時：isEnabled 已經是開，這裡會開
                            await DayTimelineController.shared.refresh(store: lifeStore)
                            // [v25.455] 提醒也一併續上。鬧鐘一次只掛最近 8 個
                            //（AlarmKit 有數量上限），靠每次回到前景往後補。
                            await ReminderCenter.rebuildAll(events: lifeStore.personalEvents,
                                                            subordinates: lifeStore.subordinates,
                                                            tripPlans: lifeStore.tripPlans)
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
    /// [v2 小工具] 從小工具／控制項點進來（網址帶 src=widget）：不播開場、這次不跳「本次更新」
    @ObservedObject private var deepLink = DeepLinkRouter.shared
    /// [v2 小工具] 這次啟動不跳「本次更新」（不寫已讀，下次正常冷啟動再跳）
    @State private var skipWhatsNewThisLaunch = false

    // MARK: [v25.392] 更新後的「本次更新」視窗
    //
    // 記的是「已經看過哪一版的更新說明」，不是「上次開啟的版本」——使用者若在
    // 視窗還開著時把 App 殺掉，下次會再跳一次，不會有一版的內容就這樣錯過。
    @AppStorage("last_seen_changelog_version") private var lastSeenVersion = ""
    /// [v25.532] 要跳的更新說明跟「打開」綁在一起（sheet(item:)）：以前先填 whatsNew 再打開，
    /// sheet 有時拿到改之前的空陣列，跳出一張空白的更新說明
    @State private var whatsNewPayload: WhatsNewPayload?

    // MARK: [v25.552] 上次跑到一半被關掉、還沒存的那一趟
    //
    // 開場謝幕、「本次更新」都過了才問一次（提示框不跟它們疊在一起）；從小工具點進來那次不問。
    // 按「稍後再說」、或不只一趟的，健康頁最上面有一張卡（HealthView 讀同一個 RunRecoveryCenter）。

    /// [v25.552] 上次跑到一半被關掉、還沒存的那幾趟（.task 一打開就 scan）
    @ObservedObject private var recovery = RunRecoveryCenter.shared
    /// [v25.552] 開場謝幕、「本次更新」都過了（這之後才問，不跟它們疊在一起）
    @State private var launchSettled = false
    /// [v25.552] 這次啟動問過了（只問一次；按「稍後再說」或還有第二趟的，健康頁最上面有卡）
    @State private var recoveryAsked = false
    @State private var recoveryPrompt: RunCheckpoint?

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
                        // [v2 小工具] 從小工具進來時開場已經直接拿掉（這個 task 被取消、sleep 提早回來）：什麼都不做
                        guard showSplash, !Task.isCancelled else { return }
                        splashDismissed = true
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        showSplash = false
                        // [v2 小工具] 謝幕途中從小工具點進來：這次不跳（下次正常冷啟動再跳）
                        guard !skipWhatsNewThisLaunch else { return }
                        // 謝幕之後才跳，不要跟開場動畫疊在一起
                        presentWhatsNewIfNeeded()
                        // [v25.552] 沒有更新說明要看：開場到這裡就結束了，可以問沒存完的那一趟；
                        // 有更新說明就等它關掉（sheet 的 onDismiss）再問
                        if whatsNewPayload == nil { settleLaunch() }
                    }
            }
        }
        .sheet(item: $whatsNewPayload, onDismiss: { settleLaunch() }) { payload in
            WhatsNewView(entries: payload.entries) { markWhatsNewSeen() }
                .appStores()
        }
        .onChange(of: deepLink.widgetLaunch, initial: true) { _, fromWidget in
            skipSplashForWidget(fromWidget)
        }
        // [v25.552] 找沒存完的那一趟比謝幕還慢做完時：做完再看要不要問
        .onChange(of: recovery.scanned) { _, _ in
            askRecoveryIfNeeded()
        }
        .alert("有一趟運動還沒存", isPresented: recoveryShown, presenting: recoveryPrompt) { cp in
            Button("存下來") { RunRecoveryCenter.shared.save(cp, store: AppStores.life) }
            Button("丟掉", role: .destructive) { RunRecoveryCenter.shared.discard(cp) }
            Button("稍後再說", role: .cancel) { }
        } message: { cp in
            Text(cp.prompt())
        }
    }

    // MARK: [v25.552] 問沒存完的那一趟

    private var recoveryShown: Binding<Bool> {
        Binding(get: { recoveryPrompt != nil }, set: { if !$0 { recoveryPrompt = nil } })
    }

    /// 開場謝幕（沒有更新說明時）或更新說明關掉之後呼叫：開場結束了，可以問
    private func settleLaunch() {
        launchSettled = true
        askRecoveryIfNeeded()
    }

    /// 謝幕、更新說明都過了、從小工具點進來那次不問、這次還沒問過，才問最新那一趟。
    /// 〔存下來〕〔丟掉〕交給 RunRecoveryCenter（它在下一輪主執行緒才寫 store、刪檔）；〔稍後再說〕什麼都不動，健康頁有卡
    private func askRecoveryIfNeeded() {
        guard launchSettled, !recoveryAsked, !skipWhatsNewThisLaunch, whatsNewPayload == nil,
              let first = recovery.pending.first else { return }
        recoveryAsked = true
        recoveryPrompt = first
    }

    /// [v2 小工具] 從小工具／控制項點進來（judge §2.4：冷啟動 1 秒內能打數字）：開場還在就直接拿掉
    /// （不播謝幕動畫），這次不跳「本次更新」——不寫已讀，下次正常打開再跳。開場已經結束就什麼都不做
    private func skipSplashForWidget(_ fromWidget: Bool) {
        guard fromWidget, showSplash else { return }
        skipWhatsNewThisLaunch = true
        showSplash = false
        // 全新安裝第一次就從小工具點進來：照 presentWhatsNewIfNeeded 的「全新安裝」那一支記下目前版本
        //（那一支本來就不跳）。不記的話，這次記了帳、下次正常打開會被當成舊使用者，跳出整頁更新說明。
        // 舊使用者（有資料）不動：下次正常冷啟動照樣跳
        if lastSeenVersion.isEmpty, !hasExistingData, !Changelog.currentVersion.isEmpty {
            lastSeenVersion = Changelog.currentVersion
        }
    }

    /// 這次啟動要不要跳更新說明。
    private func presentWhatsNewIfNeeded() {
        let current = Changelog.currentVersion
        guard !current.isEmpty else { return }
        if lastSeenVersion.isEmpty {
            // 沒有已讀紀錄有兩種可能，處理方式不一樣：
            // ① 全新安裝 → 一打開就被一整面更新紀錄糊臉並不合理。記下目前版本、
            //    什麼都不跳，從下一次更新開始才會有。
            // ② 這個功能上線前就在用的舊使用者 → 他確實剛更新完，只是我們不知道
            //    他上一版是哪一版，所以只跳「目前這一版」的內容，不要憑空往回補。
            guard hasExistingData else {
                lastSeenVersion = current
                return
            }
            let entries = Changelog.entries.filter {
                Changelog.compareVersions($0.version, current) == .orderedSame
            }
            if entries.isEmpty { lastSeenVersion = current } else { whatsNewPayload = WhatsNewPayload(entries: entries) }
            return
        }
        let pending = Changelog.entries(after: lastSeenVersion, upTo: current)
        guard !pending.isEmpty else {
            // 沒有新內容（含 TestFlight 降版的情況）也要把已讀推到目前版本，
            // 否則降版再升回來會重跳一次
            lastSeenVersion = current
            return
        }
        whatsNewPayload = WhatsNewPayload(entries: pending)
    }

    /// 這台裝置上已經有資料＝是既有使用者，不是全新安裝。
    ///
    /// 直接讀 UserDefaults 而不是注入 Store：LaunchGate 是開場的外殼，
    /// 為了一個判斷把三個 Store 拉進來並不值得。這裡只看 key 在不在，不解碼內容。
    private var hasExistingData: Bool {
        let ud = UserDefaults.standard
        let probes = ["lifegood_expenses", "lifegood_incomes",
                      "life_milestones", "life_subordinates", "life_family"]
        return probes.contains { ud.object(forKey: $0) != nil }
    }

    /// 看完（按「開始使用」、「完成」或下拉關閉）就記下已讀。冪等。
    private func markWhatsNewSeen() {
        lastSeenVersion = Changelog.currentVersion
        whatsNewPayload = nil
    }

    private struct WhatsNewPayload: Identifiable {
        let id = UUID()
        let entries: [ChangelogEntry]
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
