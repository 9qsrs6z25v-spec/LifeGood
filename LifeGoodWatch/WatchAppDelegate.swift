import Foundation
import WatchKit
import WatchConnectivity

// MARK: - 手錶 App 的 delegate（手錶 v1，v25.574；watch/judge.md §5.3-4、§7.8-7；watch/build/v1/brief.md G2-2）
//
// 照 Apple 範例 samples/wc/SimpleWatchConnectivity Watch App/AppDelegate.swift 逐段抄，只改三處：
//   • init 的 assert(WCSession.isSupported()) 改成 guard（我們不 crash；手錶上其實一定是 true）
//   • delegate 換成 WatchSync.shared（範例是 SessionDelegator），另外裝通知〔看議程〕的 delegate
//   • 拿掉範例的 Logger（範例自己的除錯工具）；scheduleSnapshotRefresh 照留
//
// 為什麼要這樣收尾（judge §5.3-4、U3 坑 7）：iPhone 送包時手錶 App 沒在跑，系統會在背景叫醒 App、
// 交來 WKWatchConnectivityRefreshBackgroundTask。包要等 WCSession activate 好、交給 delegate
// （WatchSync 在 delegate 裡同步寫檔、重畫小格）之後才算收完——所以先把工作存起來，
// 等 activationState == .activated 而且 hasContentPending == false 才一起標完成。
// 太早標＝包還沒交到 delegate 就被暫停，錶面停在舊資料；忘了標＝背景額度被吃光、被系統殺掉。
//
// [手錶 v4，v25.580] 跑到一半 App 當掉、被系統關掉：系統重開 App 時叫 handleActiveWorkoutRecovery（Apple「Running workout
// sessions」）→ WorkoutManager.recoverActiveWorkout 用 recoverActiveWorkoutSession 接回運動 session，從 RunStash 補每公里、
// 暫停、路線點，頁首「已接回」（judge §2.11「當機重開後」；watch/build/v4/brief.md G2-4）。其他一行沒動。

final class WatchAppDelegate: NSObject, WKApplicationDelegate {

    // Hold the KVO observers to keep observing the change in the extension's lifetime.
    // （範例原話：KVO 要一直留著，App 活多久就看多久）
    private var activationStateObservation: NSKeyValueObservation?
    private var hasContentPendingObservation: NSKeyValueObservation?

    // An array to keep the background tasks.（先存起來的 WatchConnectivity 背景工作）
    private var wcBackgroundTasks = [WKWatchConnectivityRefreshBackgroundTask]()

    override init() {
        super.init()
        startWatchConnectivity()
        // 通知〔看議程〕：手錶上按前景按鈕／點通知本身 → 開手錶 App 那一場的細節（judge §3.5 工程 v1）。
        // 要在 App 啟動完成前就設好 delegate，才接得到「按了通知把 App 叫起來」的那一次
        WatchNotificationDelegate.install()
    }

    /// 範例 init 的那一段（KVO → delegate → activate）
    private func startWatchConnectivity() {
        // 範例是 assert(WCSession.isSupported(), …)；我們不 crash
        guard WCSession.isSupported() else { return }

        // Apps must complete WKWatchConnectivityRefreshBackgroundTask. Otherwise, tasks keep consuming
        // the background executing time and eventually cause a crash.
        // The timing to complete the tasks is when the current WCSession turns to a state other than .activated
        // or hasContentPending flips false (see completeBackgroundTasks), so use KVO to observe
        // the changes of the two properties.
        activationStateObservation = WCSession.default.observe(\.activationState) { _, _ in
            DispatchQueue.main.async {
                self.completeBackgroundTasks()
            }
        }
        hasContentPendingObservation = WCSession.default.observe(\.hasContentPending) { _, _ in
            DispatchQueue.main.async {
                self.completeBackgroundTasks()
            }
        }

        // Activate the session asynchronously as early as possible.
        // When the system needs to launch the app to run a background task, this saves some background runtime budget.
        WCSession.default.delegate = WatchSync.shared
        WCSession.default.activate()
    }

    // Complete the background tasks, and schedule a snapshot refresh.
    func completeBackgroundTasks() {
        guard !wcBackgroundTasks.isEmpty else { return }

        guard WCSession.default.activationState == .activated,
              WCSession.default.hasContentPending == false else { return }

        wcBackgroundTasks.forEach { $0.setTaskCompletedWithSnapshot(false) }

        // Schedule a snapshot refresh if the UI is updated by background tasks.
        let date = Date(timeIntervalSinceNow: 1)
        WKApplication.shared().scheduleSnapshotRefresh(withPreferredDate: date, userInfo: nil) { _ in
            // 排不進去也沒關係：下次打開 App 照樣重讀包（範例只印出錯誤）
        }
        wcBackgroundTasks.removeAll()
    }

    // Apps must complete WKWatchConnectivityRefreshBackgroundTask after the pending data is received.
    // This sample retains the tasks first, and complete them in the following cases:
    // 1. hasContentPending flips false, meaning no pending data waiting for processing. Pending data means
    //    the data the device receives prior to when the WCSession gets activated.
    //    More data might arrive, but it isn't pending when the session gets activated.
    // 2. The end of the handle method.
    //    This happens when hasContentPending flips to false before the app retains the tasks.
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let wcTask = task as? WKWatchConnectivityRefreshBackgroundTask {
                wcBackgroundTasks.append(wcTask)
            } else {
                // 其他背景工作（快照等）v1 沒有要做的，馬上標完成（judge §7.8-7）
                task.setTaskCompletedWithSnapshot(false)
            }
        }
        completeBackgroundTasks()
    }

    /// [手錶 v4] 跑到一半 App 當掉、系統重開 App：接回運動 session（Apple「Running workout sessions」；judge §2.11「當機重開後」）
    func handleActiveWorkoutRecovery() {
        Task { @MainActor in
            WorkoutManager.shared.recoverActiveWorkout()
        }
    }
}
