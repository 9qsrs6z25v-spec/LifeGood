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
// ⚠️ watchOS 沒有 iOS 那兩支「變成不活動／停用」的 delegate（session…DidBecomeInactive／session…DidDeactivate，iOS 才有），不准寫。
//
// [手錶 v2，v25.576] 記一筆送 iPhone（judge §4.3、§5.3、附錄 B「記一筆」那一列；watch/build/v2/brief.md G2-1）：
//   • sendRecord：RecordOutbox（主執行緒）過了 10 秒／〔完成〕／翻走／手腕放下才叫。每一筆都 transferUserInfo(["record": JSON])
//     （排隊、保證照順序送到、App 被暫停也繼續）；iPhone 在旁邊（isReachable）再 sendMessage 同一份（會把 iPhone 在背景叫醒、
//     有回話 ["ok": "imported"|"queued"|"failed", "today": 3]）→ RecordOutbox.phoneReplied；送不出去 → phoneUnreachable
//     （transferUserInfo 那一份照樣排著）。兩條都到也只記一次：iPhone 用編號擋（WatchImportedLog＋收件匣 id＝支出 id）。
//   • transferUserInfo 送完（session(_:didFinish:error:)、沒有錯）→ RecordOutbox.markDelivered（設定第一行不再算這一筆）。
//   • outstandingRecordIds：系統排隊裡還沒送完的記帳編號（設定〔現在送〕只補送排隊裡已經沒有的那幾筆）。
//   • applyData 寫好包之後（還在 applyLock 裡）RecordOutboxStore.reconcile：對 includedIds／queuedIds 收尾；
//     主執行緒那一份由 notifyModel → WatchModel.packageReceived → RecordOutbox.packageApplied 重讀、補送。
//   • activate 好、iPhone 變得在旁邊：RecordOutbox.sendDue（還沒 activate 好時按的、App 被暫停沒送成的，現在送）。
//   鎖的方向只有 applyLock → stateLock、applyLock → RecordOutboxStore 的鎖；RecordOutboxStore 不回頭拿這兩把，不會互鎖。
//   手錶不會收到 record（iPhone → 手錶只有包），didReceiveUserInfo 照 v1。
//
// [手錶 v6，v25.578] 旅途中打卡送 iPhone（judge §4.1、§4.4、附錄 B「打卡」那一列；watch/build/v6/brief.md G2-1）：
//   • sendCheckIn：TripCheckIns（主執行緒）〔到了〕〔離開〕按下去就叫。跟 sendRecord 同一個樣子——transferUserInfo(["checkIn": JSON])
//     （排隊、保證送到）＋ iPhone 在旁邊再 sendMessage 同一份（回 ["ok": "done"|"queued"|"already"|"gone"|"failed", "at": 秒]）
//     → TripCheckIns.phoneReplied；送不出去 → phoneUnreachable。兩條都到也只寫一次：iPhone 只補還沒有的（WatchCheckInRule）。
//   • transferUserInfo 送完（didFinish、沒有錯）：record 那一份照 v2；checkIn 那一份 → TripCheckIns.markDelivered。
//   • applyData（還在 applyLock 裡）：RecordOutboxStore.reconcile 多傳 outstandingRecordIds()——**v2 已知限制修正**：
//     系統排隊裡還沒送完的那幾筆（iPhone 根本還沒收到），那幾包沒有它不算「沒有它」，不會先被寫成「在 iPhone 上被刪掉了」；
//     接著 WatchCheckInLog.reconcile（iPhone 寫回包裡的打卡拿掉）。主執行緒那一份由 notifyModel → WatchModel.packageReceived
//     → TripCheckIns.packageApplied 重讀、補送。
//   • activate 好、iPhone 變得在旁邊：RecordOutbox.sendDue 之後 TripCheckIns.sendDue（還沒 activate 好時按的打卡現在送）。
//   鎖的方向多一條 applyLock → WatchCheckInLog 的鎖；WatchCheckInLog 不回頭拿這邊的鎖，不會互鎖。
//
// [手錶 v5，v25.582] 「我跑完了」「沒存成」送 iPhone（judge §5.7 最後一段、§2.12、附錄 B；watch/build/v5/brief.md §2）：
//   • sendRanWorkout：WorkoutManager 存好一趟（或〔再存一次〕存好）就叫。transferUserInfo(["ranWorkout": 編號, "ranAt": 結束秒])
//     （排隊、保證送到）＋ iPhone 在旁邊再 sendMessage 同一份（會在背景叫醒 iPhone、不等回話）。iPhone 記旗子 watch_run_pending，
//     健康頁回前景不等 15 分鐘馬上同步、先找那一筆（WatchRunFlags、HealthSyncCenter.syncForWatchRun）。兩條都到也只記一次（同一個編號）
//   • sendUnsavedRun：存不進 Apple 健康（true）、那一趟不在手錶上了（false）→ ["unsavedRun": 1／0]（同兩條路）
//   • 還沒 activate 好：先存在 UserDefaults（watch_run_report_pending_v1，只留最後一份「我跑完了」、最後一份「沒存成」），
//     activate 好再送
//   • reloadRunWeekWidget：錶面「這週跑步」馬上重畫（手錶自己記的那一趟算進去了；WatchRunLog 一改就叫）
//
// [手錶 v7a，v25.585] 說一句送 iPhone、收結果（judge §4.1「說一句」、§4.3、§5.3、§5.5、附錄 B「說一句」那一列；watch/build/v7a/brief.md G2-1）：
//   • sendVoice：VoiceOutbox（主執行緒）講完馬上叫、sendDue／〔現在送〕再叫。跟 sendRecord 同一個樣子——transferUserInfo(["voice": JSON])
//     （排隊、保證送到、iPhone 不在旁邊也排著）＋ iPhone 在旁邊再 sendMessage 同一份（回 ["ok": "working"|"queued"|"done"|"failed",
//     "said": Data（done 才有）]）。回話帶 said：先在這個背景執行緒 VoiceOutboxStore.applySaid 寫進檔（過 Store 自己的鎖），
//     再 Task { @MainActor } 交給 VoiceOutbox.phoneReplied；送不出去 → phoneUnreachable（transferUserInfo 那一份照樣排著）。
//     兩條都到、手錶重送，iPhone 只記一次（一句的編號＝支出編號＋iPhone 的 WatchVoiceLog）。
//   • outstandingVoiceIds：系統排隊裡還沒送完的說一句編號（設定〔現在送〕只補送排隊裡已經沒有的）。
//   • cancelVoiceTransfer：iPhone 回話確定收到了（working／queued，VoiceOutbox.phoneReplied 叫；結果來了——回話帶 said、
//     receiveSaid——這裡自己叫），系統排隊裡那一份（裡面有你講的原文）取消（judge §6.1「送到就刪」）。
//   • 收結果有兩條路，都走 receiveSaid（delegate return 之前寫好檔，背景被叫醒時 WatchAppDelegate 等 hasContentPending 變 false 就標完成）：
//     iPhone transferUserInfo(["said": …]) → didReceiveUserInfo（先看 "said"，不是才當包 apply）；
//     iPhone 在旁邊 sendMessage(["said": …], replyHandler: nil) → session(_:didReceiveMessage:)（v7a 新加；不是 said 的不管）。
//     同一句的結果到兩次不改（VoiceOutboxRule.withSaid）。
//   • transferUserInfo 送完（didFinish、沒有錯）：voice 那一份 → VoiceOutbox.markDelivered（原文清掉）；record、checkIn 照 v2、v6。
//   • activate 好、iPhone 變得在旁邊：TripCheckIns.sendDue 之後 VoiceOutbox.sendDue（還沒 activate 好時講的那幾句現在送）。
//   鎖的方向：VoiceOutboxStore 的鎖不回頭拿 applyLock／stateLock，applySaid 也不在 applyLock 裡叫，不會互鎖。

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

    // MARK: [v2] 記一筆送 iPhone（brief G2-1；名字、參數不准改，RecordOutbox 在叫）

    /// iPhone 在旁邊（activate 好、isReachable）：RecordOutbox 決定寫「正在送到 iPhone…」還是「先存在手錶上」
    var isPhoneReachable: Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        return session.activationState == .activated && session.isReachable
    }

    /// 送一筆（RecordOutbox 在主執行緒叫）：transferUserInfo（排隊、保證送到）＋ iPhone 在旁邊再 sendMessage（快、有回話）。
    /// 還沒 activate 好（或編不成 JSON）回 false（RecordOutbox 留著 holding，activate 好、回前景、收到包再送）。
    /// 回 true＝transferUserInfo 已經排進系統（不在旁邊時 RecordOutbox 自己寫「還沒送到 iPhone，先存在手錶上」）。
    /// 回話一律 Task { @MainActor in } 交給 RecordOutbox（replyHandler／errorHandler 在 WCSession 的背景執行緒）
    func sendRecord(_ record: WatchRecord) -> Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        guard session.activationState == .activated, let data = WatchRecordCodec.encode(record) else { return false }
        let message: [String: Any] = [WatchLink.recordKey: data]
        // 排隊、保證照順序送到、App 被暫停也繼續（送完 → session(_:didFinish:error:) → markDelivered）
        _ = session.transferUserInfo(message)
        // 不在旁邊：只排隊（RecordOutbox 寫「先存在手錶上」，回到身邊系統自己補送）
        guard session.isReachable else { return true }
        let id = record.id
        session.sendMessage(message, replyHandler: { reply in
            // iPhone 回 ["ok": "imported"|"queued"|"failed", "today": 3]（today 只有 imported 才可能有）
            let ok = reply[WatchLink.okKey] as? String
            let today = reply[WatchLink.todayCountKey] as? Int
            Task { @MainActor in
                RecordOutbox.shared.phoneReplied(id, ok: ok, today: today)
            }
        }, errorHandler: { _ in
            // iPhone 不在旁邊了、LifeGood 被滑掉、逾時…：transferUserInfo 那一份照樣排著
            Task { @MainActor in
                RecordOutbox.shared.phoneUnreachable(id)
            }
        })
        return true
    }

    /// 系統排隊裡還沒送完的手錶記帳編號（WCSession.outstandingUserInfoTransfers 裡帶 "record" 的）；〔現在送〕用：
    /// 還在排隊的不再送一次，排隊裡已經沒有、iPhone 也還沒確認的才補送。還沒 activate 好回空（那時 sendRecord 也送不出去）。
    /// [v6] applyData 也用：排隊裡的那幾筆，新包沒有它不數「沒有它」（RecordOutboxStore.reconcile 的 outstanding）
    func outstandingRecordIds() -> Set<UUID> {
        guard WCSession.isSupported() else { return [] }
        let session = WCSession.default
        guard session.activationState == .activated else { return [] }
        var ids = Set<UUID>()
        for transfer in session.outstandingUserInfoTransfers {
            guard let data = transfer.userInfo[WatchLink.recordKey] as? Data,
                  let record = WatchRecordCodec.decode(data) else { continue }
            ids.insert(record.id)
        }
        return ids
    }

    // MARK: [v6] 打卡送 iPhone（brief G2-1；名字、參數不准改，TripCheckIns 在叫）

    /// 送一筆打卡（TripCheckIns 在主執行緒叫）：transferUserInfo(["checkIn": JSON])＋ iPhone 在旁邊再 sendMessage（回話交給
    /// TripCheckIns.shared.phoneReplied／phoneUnreachable）。還沒 activate 好、編不成 JSON 回 false（TripCheckIns 留著 holding）。
    /// 回 true＝transferUserInfo 已經排進系統（不在旁邊時 TripCheckIns 自己寫「還沒送到 iPhone，先存在手錶上」）
    func sendCheckIn(_ checkIn: WatchCheckIn) -> Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        guard session.activationState == .activated, let data = WatchCheckInCodec.encode(checkIn) else { return false }
        let message: [String: Any] = [WatchLink.checkInKey: data]
        // 排隊、保證照順序送到、App 被暫停也繼續（送完 → session(_:didFinish:error:) → markDelivered）
        _ = session.transferUserInfo(message)
        // 不在旁邊：只排隊（回到身邊系統自己補送）
        guard session.isReachable else { return true }
        let id = checkIn.id
        session.sendMessage(message, replyHandler: { reply in
            // iPhone 回 ["ok": "done"|"queued"|"already"|"gone"|"failed", "at": 秒]（at 只有 already 才有）
            let ok = reply[WatchLink.okKey] as? String
            let seconds = reply[WatchLink.checkInAtKey] as? Double
            let at: Date? = seconds.map { Date(timeIntervalSince1970: $0) }
            Task { @MainActor in
                TripCheckIns.shared.phoneReplied(id, ok: ok, at: at)
            }
        }, errorHandler: { _ in
            // iPhone 不在旁邊了、LifeGood 被滑掉、逾時…：transferUserInfo 那一份照樣排著
            Task { @MainActor in
                TripCheckIns.shared.phoneUnreachable(id)
            }
        })
        return true
    }

    // MARK: [v7a] 說一句送 iPhone（骨架：主控定名字與參數，G2 填本體；VoiceOutbox 在叫，名字、參數不准改。watch/build/v7a/brief.md G2-1）

    /// 送一句（VoiceOutbox 在主執行緒叫）：transferUserInfo(["voice": JSON])＋ iPhone 在旁邊再 sendMessage（回話交給
    /// VoiceOutbox.shared.phoneReplied／phoneUnreachable）。還沒 activate 好、編不成 JSON 回 false（VoiceOutbox 留著 pending）
    /// 回 true＝transferUserInfo 已經排進系統（不在旁邊時 VoiceOutbox 自己寫「還沒送到 iPhone，先存在手錶上」）
    func sendVoice(_ voice: WatchVoice) -> Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        guard session.activationState == .activated, let data = WatchVoiceCodec.encode(voice) else { return false }
        let message: [String: Any] = [WatchLink.voiceKey: data]
        // 排隊、保證送到、App 被暫停也繼續（送完 → session(_:didFinish:error:) → markDelivered）
        _ = session.transferUserInfo(message)
        // 不在旁邊：只排隊（VoiceOutbox 寫「先存在手錶上」，回到身邊系統自己補送）
        guard session.isReachable else { return true }
        let id = voice.id
        session.sendMessage(message, replyHandler: { reply in
            // iPhone 回 ["ok": "working"|"queued"|"done"|"failed", "said": Data（done 才有）]
            let ok = reply[WatchLink.okKey] as? String
            let said: WatchVoiceSaid? = (reply[WatchLink.saidKey] as? Data).flatMap { WatchVoiceSaidCodec.decode($0) }
            if let said {
                // 先寫檔（這裡是 WCSession 的背景執行緒；VoiceOutboxStore 過自己的鎖）
                VoiceOutboxStore.applySaid(said, now: Date())
                // 有結果＝iPhone 早就收到這一句了：排隊裡那一份（裡面有原文）不用再送
                self.cancelVoiceTransfer(id)
            }
            Task { @MainActor in
                VoiceOutbox.shared.phoneReplied(id, ok: ok, said: said)
            }
        }, errorHandler: { _ in
            // iPhone 不在旁邊了、LifeGood 被滑掉、逾時…：transferUserInfo 那一份照樣排著
            Task { @MainActor in
                VoiceOutbox.shared.phoneUnreachable(id)
            }
        })
        return true
    }

    /// 系統排隊裡還沒送完的說一句編號（WCSession.outstandingUserInfoTransfers 裡帶 "voice" 的）；設定〔現在送〕用：
    /// 還在排隊的不再送一次。還沒 activate 好回空（那時 sendVoice 也送不出去）
    func outstandingVoiceIds() -> Set<UUID> {
        guard WCSession.isSupported() else { return [] }
        let session = WCSession.default
        guard session.activationState == .activated else { return [] }
        var ids = Set<UUID>()
        for transfer in session.outstandingUserInfoTransfers {
            guard let data = transfer.userInfo[WatchLink.voiceKey] as? Data,
                  let voice = WatchVoiceCodec.decode(data) else { continue }
            ids.insert(voice.id)
        }
        return ids
    }

    /// iPhone 回話確定收到了這一句：系統排隊裡那一份（裡面有原文）取消，不用再送（judge §6.1「送到就刪」）
    func cancelVoiceTransfer(_ id: UUID) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        for transfer in session.outstandingUserInfoTransfers {
            guard let data = transfer.userInfo[WatchLink.voiceKey] as? Data,
                  let voice = WatchVoiceCodec.decode(data),
                  voice.id == id else { continue }
            transfer.cancel()
        }
    }

    /// iPhone 送來的一句結果（transferUserInfo 或 sendMessage 的 ["said": Data]；WCSession 的背景執行緒）：
    /// delegate return 之前先寫進待送盒的檔（背景被叫醒時 App 隨時會被暫停），再交給主執行緒那一份重讀。
    /// 解不開不管；手錶上已經沒有這一句（早就刪了）applySaid 自己回 false、不新增
    private func receiveSaid(_ data: Data) {
        guard let said = WatchVoiceSaidCodec.decode(data) else { return }
        VoiceOutboxStore.applySaid(said, now: Date())
        // 有結果＝iPhone 早就收到這一句了：排隊裡如果還有那一份（裡面有原文）就取消
        cancelVoiceTransfer(said.id)
        Task { @MainActor in
            VoiceOutbox.shared.saidArrived(said)
        }
    }

    // MARK: [v5] 我跑完了、沒存成（brief §2；名字、參數不准改，WorkoutManager 在叫）

    /// 還沒 activate 好時先存起來的那幾份（["ranWorkout": …] 一份、["unsavedRun": …] 一份；activate 好再送）
    private static let reportPendingKey = "watch_run_report_pending_v1"

    /// 跑完存好了（或〔再存一次〕存好了）：告訴 iPhone 馬上去 Apple 健康找這一筆。workoutId nil／空＝存好了但讀不到編號
    func sendRanWorkout(workoutId: String?, endedAt: Date) {
        let message: [String: Any] = [WatchLink.ranWorkoutKey: workoutId ?? "",
                                      WatchLink.ranAtKey: endedAt.timeIntervalSince1970]
        deliverRunReport(message, slot: WatchLink.ranWorkoutKey)
        WatchSync.reloadRunWeekWidget()
    }

    /// 有一趟存不進 Apple 健康、留在手錶上（true）／那一趟不在手錶上了（false）
    func sendUnsavedRun(_ unsaved: Bool) {
        let message: [String: Any] = [WatchLink.unsavedRunKey: unsaved ? 1 : 0]
        deliverRunReport(message, slot: WatchLink.unsavedRunKey)
        // [v7b] 沒存成的那一趟也寫進了 WatchRunLog（RelevanceCardSource 照樣算「今天那個時段跑過了」）：
        // 請系統重新問「平常跑步的時間」「這週跑步」什麼時候浮（存好的那條走 sendRanWorkout → reloadRunWeekWidget）
        if unsaved {
            WidgetCenter.shared.invalidateRelevance(ofKind: WatchWidgetKind.runWeek)
            WidgetCenter.shared.invalidateRelevance(ofKind: WatchWidgetKind.cardRun)
        }
    }

    /// 錶面「這週跑步」重畫（WatchRunLog 加了、拿掉一趟）。
    /// [v7b] 順手請系統重新問「這週跑步」「平常跑步的時間」什麼時候浮（今天那個時段跑過了就不浮、週日差幾公里）
    static func reloadRunWeekWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: WatchWidgetKind.runWeek)
        WidgetCenter.shared.invalidateRelevance(ofKind: WatchWidgetKind.runWeek)
        WidgetCenter.shared.invalidateRelevance(ofKind: WatchWidgetKind.cardRun)
    }

    /// transferUserInfo（排隊、保證送到）＋ iPhone 在旁邊再 sendMessage（不等回話）。還沒 activate 好：存起來、activate 好再送
    private func deliverRunReport(_ message: [String: Any], slot: String) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            Self.keepRunReport(message, slot: slot)
            return
        }
        _ = session.transferUserInfo(message)
        guard session.isReachable else { return }
        session.sendMessage(message, replyHandler: nil, errorHandler: { _ in
            // iPhone 不在旁邊了、LifeGood 被滑掉…：transferUserInfo 那一份照樣排著
        })
    }

    /// 還沒 activate 好時存起來（同一種只留最後一份）
    private static func keepRunReport(_ message: [String: Any], slot: String) {
        let d = WidgetShared.defaults
        var all = (d?.dictionary(forKey: reportPendingKey) as? [String: [String: Any]]) ?? [:]
        all[slot] = message
        d?.set(all, forKey: reportPendingKey)
    }

    /// activate 好了：存起來的那幾份送出去、刪掉
    private func flushRunReports() {
        let d = WidgetShared.defaults
        guard let all = d?.dictionary(forKey: Self.reportPendingKey) as? [String: [String: Any]], !all.isEmpty else { return }
        d?.removeObject(forKey: Self.reportPendingKey)
        for (slot, message) in all {
            deliverRunReport(message, slot: slot)
        }
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
        // [v2] 待送盒對這一包的 includedIds／queuedIds 收尾（judge §4.3；還在 applyLock 裡，兩包同時到也照順序對）。
        // 舊包（上面 isOlder 那條）不對：名單是舊的。同一包（generatedAt 一樣）不會重算「沒有它」。
        // 主執行緒那一份由 notifyModel → WatchModel.packageReceived → RecordOutbox.packageApplied 重讀
        // [v6] v2 已知限制修正：系統排隊裡還沒送完的（iPhone 根本還沒收到）不數「沒有它」（outstanding）。
        //      接著打卡收尾：iPhone 寫回包裡的（那一站有時間了）、24 小時、那一站不在了的拿掉
        //      （主執行緒那一份由 WatchModel.packageReceived → TripCheckIns.packageApplied 重讀）
        let now = Date()
        RecordOutboxStore.reconcile(with: pkg, now: now, outstanding: outstandingRecordIds())
        WatchCheckInLog.reconcile(with: pkg, now: now)
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
        // [v7b] 智慧型堆疊：內容真的變了才請系統重新問「什麼時候浮上來」（invalidateRelevance，watchOS 11 起；
        // 下一場、已花、這週跑步＋5 種卡，WatchPackageDiff.relevanceKinds）。背景時卡那幾種也重畫（前景上面已經全部重畫）
        if wrote {
            let clues = WatchPackageDiff.relevanceKinds(old: old, new: pkg)
            for kind in clues {
                WidgetCenter.shared.invalidateRelevance(ofKind: kind)
            }
            if !appActive {
                for kind in clues where WatchWidgetKind.cards.contains(kind) {
                    WidgetCenter.shared.reloadTimelines(ofKind: kind)
                }
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
    /// 之前被叫要包的現在要；App 在前景、包太舊（或沒有）也要一份。
    /// [v2] activate 好時待送盒到期的現在送（還沒 activate 好時按的那幾筆，sendRecord 回 false 留在 holding）
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
        // [v5] 還沒 activate 好時跑完的那一趟（「我跑完了」「沒存成」）現在送
        flushRunReports()
        Task { @MainActor in
            // [v2] 先送記帳、再要包（下面 requestFromPhone 那一條）：iPhone 收完這幾筆組的包才帶得到它們。
            // 上面 wanted 那一條已經先要過了也沒關係：iPhone 入帳後 writeNow([.money]) 會再送一包新的
            RecordOutbox.shared.sendDue()
            // [v6] 還沒 activate 好時按的打卡（sendCheckIn 回 false 留在 holding）現在送
            TripCheckIns.shared.sendDue()
            // [v7a] 還沒 activate 好時講的那幾句（sendVoice 回 false 留在 pending）現在送
            VoiceOutbox.shared.sendDue()
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

    /// iPhone transferCurrentComplicationUserInfo 送來的（錶面推送也從這裡進來；內容跟 context 同一包）。
    /// [v7a] iPhone transferUserInfo 送來的說一句結果（["said": Data]）也從這裡進來：先看 "said"，不是才當包
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let data = userInfo[WatchLink.saidKey] as? Data {
            receiveSaid(data)
            return
        }
        apply(userInfo)
    }

    /// [v7a] iPhone 在旁邊 sendMessage 送來的（replyHandler 是 nil）：只有說一句的結果（["said": Data]），其他的不管
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message[WatchLink.saidKey] as? Data else { return }
        receiveSaid(data)
    }

    /// iPhone transferFile 送來的（壓完超過 48 KB）。這個方法 return 之後系統就把檔刪了：一定在這裡同步讀完
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let data = try? Data(contentsOf: file.fileURL) else { return }
        applyData(data)
    }

    /// iPhone 變得在旁邊：App 在前景、手上還沒有包、也沒在要 → 要一份。
    /// [v2] 待送盒到期還沒送的也現在送（已經排進 transferUserInfo 的，系統自己會補送，不用再送）
    /// [v6] 還沒送出去的打卡（holding）也現在送
    /// [v7a] 還沒交給系統的說一句（pending）也現在送
    func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in
            RecordOutbox.shared.sendDue()
            TripCheckIns.shared.sendDue()
            VoiceOutbox.shared.sendDue()
            let model = WatchModel.shared
            if model.isActive && model.package == nil && !model.asking {
                model.requestFromPhone()
            }
        }
    }

    /// [v2] 手錶送出的 transferUserInfo 送完了（iPhone 收到）：待送盒那一筆不再算「還沒送到 iPhone」。
    /// 有錯（例：iPhone 上還沒裝 LifeGood）就不動：留在「還沒送到」，設定〔現在送〕再送。
    /// [v6] 不是記帳的再看是不是打卡（"checkIn"）：TripCheckIns.markDelivered（按鈕下面寫「已送到 iPhone」）。都不是不管
    /// [v7a] 說一句（"voice"）：VoiceOutbox.markDelivered（「已送到 iPhone，記好會告訴你」、原文清掉）
    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        guard error == nil else { return }
        let info = userInfoTransfer.userInfo
        if let data = info[WatchLink.voiceKey] as? Data {
            guard let voice = WatchVoiceCodec.decode(data) else { return }
            let id = voice.id
            Task { @MainActor in
                VoiceOutbox.shared.markDelivered(id)
            }
            return
        }
        if let data = info[WatchLink.recordKey] as? Data {
            guard let record = WatchRecordCodec.decode(data) else { return }
            let id = record.id
            Task { @MainActor in
                RecordOutbox.shared.markDelivered(id)
            }
            return
        }
        guard let data = info[WatchLink.checkInKey] as? Data,
              let checkIn = WatchCheckInCodec.decode(data) else { return }
        let id = checkIn.id
        Task { @MainActor in
            TripCheckIns.shared.markDelivered(id)
        }
    }
}
