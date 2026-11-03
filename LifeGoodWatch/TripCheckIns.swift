import Foundation
import WidgetKit

// MARK: - 旅途中的打卡（手錶 v6，v25.578；watch/judge.md §2.14、§4.1、§4.4、附錄 B；watch/build/v6/brief.md §2）
//
// 只屬於 LifeGoodWatch。〔到了〕〔離開〕按下去：
//   ① 先記在手錶上（WatchCheckInLog，手錶 App Group；④ 旅行、這一站、錶面「下一場」馬上換成「14:12 到了」）
//   ② 送 iPhone：transferUserInfo（排隊、保證送到、iPhone 不在旁邊也排著）＋ iPhone 在旁邊再 sendMessage（有回話）——
//      WatchSync.sendCheckIn（G2）。兩條都到也只寫一次：iPhone 只補還沒有的（WatchCheckInRule）
//   ③ iPhone 回話（done／queued／already／gone）→ 按鈕下面那一行換字；iPhone 寫回包裡之後（那一站有時間了）
//      WatchSync 收包時 WatchCheckInLog.reconcile 拿掉這一筆
// 時間一律是按下去那一刻（不是送到的時間）。沒有〔復原〕：按錯了到 iPhone 景點卡改（送的是「設成」，不會來回切換）。
// 規則跟 scratchpad/watch/build/v6/sim_v6.py 的 checkin_* 一模一樣（改了兩邊一起改、重跑 sim）。
//
// [v6 驗證修正] 那一行字的狀態機（scratchpad/watch/build/v6/verify/checkins_model.py 照這裡抄、四件事所有先後順序都驗過）：
//   • iPhone 寫進去之後先送新包、才回話：新包常常比回話先到，WatchCheckInLog.reconcile 先把這一筆拿掉了。
//     以前回話、逾時找不到那一筆就不改字，那一行卡在「正在送到 iPhone…」。現在記著這次按的（pressed），
//     新包帶回那一站的時間＝「已寫進 iPhone 的行程」（confirmWritten）；回話照樣找得到是哪一站
//   • 同一筆 transferUserInfo 比 sendMessage 先到 iPhone、已經照這一下寫進去：iPhone 回「本來就打過」的時間就是這一下
//     （isOwnTime，±1 秒）＝寫好了，不寫「已經在 14:12 打過卡」（那是家人先打、時間不一樣才寫）
//   • iPhone 不在旁邊、冷啟動排著：之後寫進去的新包一到，那一行也換「已寫進 iPhone 的行程」
//   • 那一站最新的一下才改那一行（先〔到了〕再〔離開〕，〔到了〕晚到的回話不蓋〔離開〕那一行）
//
// ⚠️ WatchSync 的回呼在背景執行緒：一律 Task { @MainActor in TripCheckIns.shared.… }。

@MainActor
final class TripCheckIns: ObservableObject {
    static let shared = TripCheckIns()

    /// sendMessage 送出後等 iPhone 回話多久，沒回就寫「還沒送到 iPhone，先存在手錶上」
    static let replyTimeout: TimeInterval = 5

    /// 手錶上按過、還沒被 iPhone 寫回包裡的（WatchCheckInLog）
    @Published private(set) var items: [WatchCheckInItem]
    /// 這次打開 App 按的：那一站（stopId）按鈕下面那一行。App 重開就沒有（看 items 的 state 推）
    @Published private(set) var lines: [UUID: String] = [:]

    /// 送出去、還在等回話的編號（5 秒沒回就換「先存在手錶上」）
    private var waiting: Set<UUID> = []
    /// 這次打開 App 按的（編號 → 那一筆）：iPhone 回話、逾時、新包到的時候，那一筆可能已經被新包收尾拿掉了
    /// （iPhone 寫回包裡：WatchCheckInLog.reconcile），照樣找得到是哪一站、是〔到了〕還是〔離開〕
    private var pressed: [UUID: WatchCheckIn] = [:]
    /// iPhone 回過最後的話（done／already／gone），或新包已經帶回那一站的時間：新包再到不再改那一行
    private var settled: Set<UUID> = []

    private init() {
        items = WatchCheckInLog.all()
    }

    func reload() {
        items = WatchCheckInLog.all()
    }

    /// 那一站按鈕下面那一行：這次按的看 lines；App 重開過的照檔裡最新那一筆的狀態推；沒有 nil
    func line(for stopId: UUID) -> String? {
        if let s = lines[stopId] { return s }
        let mine = items.filter { $0.checkIn.stopId == stopId }
        guard let item = mine.max(by: { $0.checkIn.createdAt < $1.checkIn.createdAt }) else { return nil }
        return WatchTripText.checkInLine(WatchTripText.checkInStatus(of: item), isDeparture: item.isDeparture)
    }

    // MARK: 按

    /// 〔到了〕：到達＝按下去那一刻
    func arrive(planId: UUID, stopId: UUID, now: Date = Date()) {
        let c = WatchCheckIn(id: UUID(), planId: planId, stopId: stopId, arrival: now, departure: nil, createdAt: now)
        record(c)
    }

    /// 〔離開〕：離開＝按下去那一刻；到達帶手錶上看到的（iPhone 那邊沒有到達時補上；有就不蓋）
    func depart(planId: UUID, stopId: UUID, arrivedAt: Date?, now: Date = Date()) {
        let c = WatchCheckIn(id: UUID(), planId: planId, stopId: stopId, arrival: arrivedAt, departure: now,
                             createdAt: now)
        record(c)
    }

    private func record(_ c: WatchCheckIn) {
        WatchCheckInLog.add(WatchCheckInItem(checkIn: c, state: .holding))
        reload()
        // 錶面「下一場」馬上換成「到了」／下一站（手錶小格讀同一份 WatchCheckInLog）
        WidgetCenter.shared.reloadTimelines(ofKind: WatchWidgetKind.nextUp)
        // [v7b] 按了〔到了〕：智慧型堆疊「旅途下一站」那一站不再浮（手錶小格讀同一份 WatchCheckInLog）
        WidgetCenter.shared.invalidateRelevance(ofKind: WatchWidgetKind.cardTrip)
        send(c)
    }

    /// 送一筆：還沒啟動好（sendCheckIn 回 false）留著 holding，啟動好、iPhone 回到身邊、回前景再送（sendDue）
    private func send(_ c: WatchCheckIn) {
        pressed[c.id] = c
        guard WatchSync.shared.sendCheckIn(c) else {
            setLine(.offline, for: c)
            return
        }
        WatchCheckInLog.update(c.id) { stored in
            if stored.state == .holding {
                stored.state = .sent
            }
        }
        reload()
        if WatchSync.shared.isPhoneReachable {
            setLine(.waiting, for: c)
            waiting.insert(c.id)
            scheduleTimeout(c.id)
        } else {
            setLine(.offline, for: c)
        }
    }

    /// 還沒送出去的（holding）現在送：WCSession 啟動好、iPhone 回到身邊、回前景（WatchSync、WatchModel 叫）
    func sendDue() {
        for item in items where item.state == .holding {
            send(item.checkIn)
        }
    }

    // MARK: WatchSync 回來（主執行緒）

    /// sendMessage 的回話：["ok": "done"|"queued"|"already"|"gone"|"failed", "at": 秒]。
    /// 那一筆已經被新包收尾拿掉（iPhone 寫回包裡了）也照樣改那一行（pressed 找得到是哪一站）
    func phoneReplied(_ id: UUID, ok: String?, at: Date?) {
        waiting.remove(id)
        let found: WatchCheckInItem? = items.first(where: { $0.id == id })
        guard let c = found?.checkIn ?? pressed[id] else { return }
        // 新包已經先到、那一站有時間了（WatchCheckInLog.reconcile 拿掉了）
        let written = found == nil
        if ok == WatchLink.okDone {
            settled.insert(id)
            WatchCheckInLog.update(id) { $0.state = .done }
            setLine(.done, for: c)
        } else if ok == WatchLink.okAlready {
            settled.insert(id)
            let shown = at ?? c.createdAt
            if Self.isOwnTime(shown, of: c) {
                // 同一筆從另一條路（transferUserInfo）先到、iPhone 已經照這一下的時間寫進去了：不是別人打的＝寫好了
                WatchCheckInLog.update(id) { $0.state = .done }
                setLine(.done, for: c)
            } else {
                WatchCheckInLog.update(id) { stored in
                    stored.state = .already
                    stored.phoneTime = shown
                }
                setLine(.already(shown), for: c)
            }
        } else if ok == WatchLink.okGone {
            // 那一站在 iPhone 上被刪了：手錶上這一筆拿掉（不再補到畫面上）
            settled.insert(id)
            WatchCheckInLog.remove(id)
            setLine(.gone, for: c)
        } else if written {
            // queued／解不開，但新包已經帶回那一站的時間：寫進去了（例：iPhone 剛好在這時候打開 LifeGood）
            settled.insert(id)
            setLine(.done, for: c)
        } else if ok == WatchLink.okQueued {
            WatchCheckInLog.update(id) { $0.state = .queued }
            setLine(.queued, for: c)
        } else {
            // 解不開、寫不進去：transferUserInfo 那一份照樣排著
            setLine(.offline, for: c)
        }
        reload()
        WidgetCenter.shared.reloadTimelines(ofKind: WatchWidgetKind.nextUp)
    }

    /// sendMessage 失敗（iPhone 不在旁邊了、LifeGood 被滑掉…）：transferUserInfo 那一份照樣排著
    func phoneUnreachable(_ id: UUID) {
        guard waiting.contains(id) else { return }
        waiting.remove(id)
        guard let item = items.first(where: { $0.id == id }) else {
            confirmWritten(id)
            return
        }
        setLine(.offline, for: item.checkIn)
    }

    /// transferUserInfo 送完、沒有錯：iPhone 收到了（還沒回話的，至少不再寫「先存在手錶上」）
    func markDelivered(_ id: UUID) {
        WatchCheckInLog.update(id) { stored in
            if stored.state == .sent || stored.state == .holding {
                stored.state = .delivered
            }
        }
        reload()
        guard let item = items.first(where: { $0.id == id }) else {
            confirmWritten(id)
            return
        }
        if item.state == .delivered && !waiting.contains(id) {
            setLine(.delivered, for: item.checkIn)
        }
    }

    /// WatchSync 收到新包、WatchCheckInLog.reconcile 做完之後：重讀；這次按的、被收尾拿掉的（iPhone 寫回包裡了）換
    /// 「已寫進 iPhone 的行程」；還沒送出去的補送
    func packageApplied() {
        reload()
        for id in Array(pressed.keys) where !items.contains(where: { $0.id == id }) {
            confirmWritten(id)
        }
        sendDue()
    }

    // MARK: 那一行

    /// 這次按的那一下已經不在手錶的打卡紀錄裡（新包帶回那一站的時間，WatchCheckInLog.reconcile 拿掉了）、
    /// iPhone 還沒回最後的話：當作寫進 iPhone 的行程了（之後 iPhone 的回話照樣可以改那一行）。
    /// 按下去超過 24 小時的（收尾因為太舊拿掉的）不算
    private func confirmWritten(_ id: UUID) {
        guard let c = pressed[id], !settled.contains(id) else { return }
        guard Date().timeIntervalSince(c.createdAt) < WatchCheckInLog.keep else { return }
        settled.insert(id)
        waiting.remove(id)
        setLine(.done, for: c)
    }

    /// 那一站按鈕下面那一行（只有那一站最新的一下才改）
    private func setLine(_ status: WatchCheckInStatus, for c: WatchCheckIn) {
        guard isLatest(c) else { return }
        lines[c.stopId] = WatchTripText.checkInLine(status, isDeparture: c.departure != nil)
    }

    /// 這次按過的裡面，同一站沒有比它更晚的一下
    private func isLatest(_ c: WatchCheckIn) -> Bool {
        !pressed.values.contains { $0.stopId == c.stopId && $0.createdAt > c.createdAt }
    }

    /// iPhone 回「本來就打過」的那個時間就是這一下（〔離開〕看離開、〔到了〕看到達；差不到 1 秒）：
    /// 同一筆從另一條路先到、已經寫進去了，不是別人打的
    static func isOwnTime(_ phoneTime: Date, of c: WatchCheckIn) -> Bool {
        guard let mine = c.departure ?? c.arrival else { return false }
        return abs(phoneTime.timeIntervalSince(mine)) < 1
    }

    // MARK: 計時

    private func scheduleTimeout(_ id: UUID) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(TripCheckIns.replyTimeout * 1_000_000_000))
            TripCheckIns.shared.replyTimedOut(id)
        }
    }

    private func replyTimedOut(_ id: UUID) {
        guard waiting.contains(id) else { return }
        waiting.remove(id)
        reload()
        guard let item = items.first(where: { $0.id == id }) else {
            // 新包已經帶回那一站的時間（收尾拿掉了）＝寫進 iPhone 的行程了
            confirmWritten(id)
            return
        }
        let status: WatchCheckInStatus = item.state == .delivered ? .delivered : .offline
        setLine(status, for: item.checkIn)
    }
}
