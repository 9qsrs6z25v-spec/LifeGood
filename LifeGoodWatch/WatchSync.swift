import Foundation
import WatchConnectivity
import WidgetKit

// MARK: - 手錶這一頭的傳話（手錶 v1，v25.574；watch/judge.md §5.3、附錄 B；watch/build/v1/brief.md G2-3）
//
// 只屬於 LifeGoodWatch。WCSession 的 delegate（WatchAppDelegate 的 init 就設好、activate）。
// iPhone 送來的包有四條路，全部走 applyData：
//   • updateApplicationContext → session(_:didReceiveApplicationContext:)；activate 好時也把 receivedApplicationContext 套一次
//   • transferCurrentComplicationUserInfo（錶面字變了才走）→ session(_:didReceiveUserInfo:)
//   • transferFile（壓完 > 48 KB）→ session(_:didReceive:)
//   • 手錶自己要（sendMessage(["want": "pkg"])）的回覆 → requestPackage 的 replyHandler
// applyData：LZFSE 解開（WatchPackageCodec，schema 不對當沒收到）→ 比新舊（舊的不收）→ 寫進**手錶自己的**
// App Group（WidgetSnapshotStore.write，同一支）→ 記收到的時間（WatchReceiveLog）→ **同步**重畫小格
// （前景＝全部；背景只重畫 WatchPackageDiff.widgetKinds 有變的那幾種）→ 才 Task { @MainActor } 叫 WatchModel。
//
// ⚠️ 不加 actor：delegate 方法在 WCSession 的背景執行緒。要動 WatchModel 一律 Task { @MainActor in … }
//    （judge §7.8-8）。寫檔、重畫小格要在 delegate 方法 return 之前做完——背景被叫醒時，
//    WatchAppDelegate 等 hasContentPending 變 false 就標完成，App 隨時會被暫停（judge §5.3-4）。
// ⚠️ watchOS 沒有 sessionDidBecomeInactive／sessionDidDeactivate（iOS 才有），不准寫。

final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()

    /// 手錶 App 在前景（含手腕放下的永遠顯示）。WatchModel.scenePhaseChanged 在主執行緒設，
    /// 這裡在 WCSession 的背景執行緒讀（決定小格重畫全部還是只重畫有變的）
    var appActive: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return storedAppActive
        }
        set {
            stateLock.lock()
            storedAppActive = newValue
            stateLock.unlock()
        }
    }

    /// appActive、wantAfterActivation、activationFinished 三個在不同執行緒讀寫，一律過這把鎖
    private let stateLock = NSLock()
    /// 收包（讀舊包 → 比 → 寫）一次只走一條：context、錶面推送、回覆可能同時到
    private let applyLock = NSLock()
    private var storedAppActive = false
    /// 還沒 activate 好就被叫要包：等 activationDidComplete 再要（WatchModel.asking 保持 true，不先顯示「沒要到」）
    private var wantAfterActivation = false
    /// activationDidComplete 來過了（activate 失敗之後再被叫要包，就自己再 activate 一次）
    private var activationFinished = false

    private override init() {
        super.init()
    }

    // MARK: 跟 iPhone 要

    /// 跟 iPhone 要最新的包（sendMessage(["want": "pkg"])，會把 iPhone 的 LifeGood 在背景叫醒，judge §5.4）；
    /// 結果在主執行緒交給 WatchModel.askFinished(ok:)。WatchModel（主執行緒）與 activationDidComplete（背景）都會叫
    func requestPackage() {
        guard WCSession.isSupported() else {
            finishAsk(false)
            return
        }
        let session = WCSession.default
        stateLock.lock()
        let activated = session.activationState == .activated
        if !activated {
            wantAfterActivation = true
        }
        let retryActivation = !activated && activationFinished
        stateLock.unlock()

        guard activated else {
            // 還在 activate：等 activationDidComplete 再要。上一次 activate 失敗了：再 activate 一次
            if retryActivation {
                session.activate()
            }
            return
        }
        guard session.isReachable else {
            finishAsk(false)
            return
        }
        session.sendMessage([WatchLink.wantKey: WatchLink.wantPackage], replyHandler: { reply in
            // iPhone 回 ["pkg": Data, "v": 1, "t": 秒]；iPhone 上還沒有包回 ["none": 1]（＝沒要到）
            let ok = self.apply(reply)
            Task { @MainActor in
                WatchModel.shared.askFinished(ok: ok)
            }
        }, errorHandler: { _ in
            Task { @MainActor in
                WatchModel.shared.askFinished(ok: false)
            }
        })
    }

    // MARK: 收包

    /// application context／complication user info／回覆那一份字典：取出 "pkg"（LZFSE）交給 applyData。
    /// 沒有 "pkg"（例：回覆 ["none": 1]）回 false
    @discardableResult
    func apply(_ dict: [String: Any], fresh: Bool = true) -> Bool {
        guard let data = dict[WatchLink.packageKey] as? Data else { return false }
        return applyData(data, fresh: fresh)
    }

    /// 解開 → 比新舊 → 寫檔 → 記時間 → 重畫小格 → 叫 WatchModel。解不開、schema 不對回 false（當作沒收到）。
    /// fresh＝false：activate 時重套手上那一份 receivedApplicationContext（多半是早就套過的同一包）——
    /// 內容真的換了才算「收到」，不然設定頁會寫成剛剛才更新、打開 App 也不會再跟 iPhone 要新的
    @discardableResult
    func applyData(_ data: Data, fresh: Bool = true) -> Bool {
        guard let pkg = WatchPackageCodec.decode(data) else { return false }
        applyLock.lock()
        let old = WidgetSnapshotStore.read(WatchPackage.self)
        if WatchPackageDiff.isOlder(pkg, than: old) {
            // 兩條路一起到、順序顛倒：舊的不收（不寫、不重畫），只記收到
            if fresh {
                WatchReceiveLog.note(Date())
            }
            applyLock.unlock()
            if fresh {
                notifyModel()
            }
            return true
        }
        let kinds = WatchPackageDiff.widgetKinds(old: old, new: pkg)
        let wrote = WidgetSnapshotStore.write(pkg)
        if fresh || wrote {
            WatchReceiveLog.note(Date())
        }
        // 同步重畫（delegate 方法 return 之前做完）：前景＝4 種都重畫（不算額度，只放堆疊的卡靠這條，judge §5.3-5）；
        // 背景只重畫內容真的變了的那幾種（write 回 false＝內容沒變，不重畫）
        if appActive {
            WidgetCenter.shared.reloadAllTimelines()
        } else if wrote {
            for kind in kinds {
                WidgetCenter.shared.reloadTimelines(ofKind: kind)
            }
        }
        applyLock.unlock()
        if fresh || wrote {
            notifyModel()
        }
        return true
    }

    /// 寫好檔之後（主執行緒）：WatchModel 重讀包、收到的時間、要包的狀態
    private func notifyModel() {
        Task { @MainActor in
            WatchModel.shared.packageReceived()
        }
    }

    private func finishAsk(_ ok: Bool) {
        Task { @MainActor in
            WatchModel.shared.askFinished(ok: ok)
        }
    }

    // MARK: WCSessionDelegate（watchOS）

    /// watchOS 必寫。activate 好：先套手上那一份 context（只放智慧型堆疊時打開 App 馬上看到，做好標準 7）；
    /// 之前被叫要包的現在要；App 在前景、包太舊（或沒有）也要一份
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        let activated = activationState == .activated
        if activated {
            let context = session.receivedApplicationContext
            if !context.isEmpty {
                apply(context, fresh: false)
            }
        }
        stateLock.lock()
        activationFinished = true
        let wanted = wantAfterActivation
        wantAfterActivation = false
        stateLock.unlock()

        if wanted {
            if activated {
                requestPackage()
            } else {
                finishAsk(false)
            }
        }
        guard activated else { return }
        Task { @MainActor in
            let model = WatchModel.shared
            if model.isActive && model.shouldAsk(now: Date()) && !model.asking {
                model.requestFromPhone()
            }
        }
    }

    /// iPhone updateApplicationContext 送來的（App 沒在跑時系統在背景叫醒 App 再交到這裡）
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    /// iPhone transferCurrentComplicationUserInfo 送來的（錶面推送也從這裡進來；內容跟 context 同一包）
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        apply(userInfo)
    }

    /// iPhone transferFile 送來的（壓完超過 48 KB）。這個方法 return 之後系統就把檔刪了：一定在這裡同步讀完
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let data = try? Data(contentsOf: file.fileURL) else { return }
        applyData(data)
    }

    /// iPhone 變得在旁邊：App 在前景、手上還沒有包、也沒在要 → 要一份
    func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in
            let model = WatchModel.shared
            if model.isActive && model.package == nil && !model.asking {
                model.requestFromPhone()
            }
        }
    }
}
