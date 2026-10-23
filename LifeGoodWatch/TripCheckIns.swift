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
        send(c)
    }

    /// 送一筆：還沒啟動好（sendCheckIn 回 false）留著 holding，啟動好、iPhone 回到身邊、回前景再送（sendDue）
    private func send(_ c: WatchCheckIn) {
        let isDeparture = c.departure != nil
        guard WatchSync.shared.sendCheckIn(c) else {
            lines[c.stopId] = WatchTripText.checkInLine(.offline, isDeparture: isDeparture)
            return
        }
        WatchCheckInLog.update(c.id) { stored in
            if stored.state == .holding {
                stored.state = .sent
            }
        }
        reload()
        if WatchSync.shared.isPhoneReachable {
            lines[c.stopId] = WatchTripText.checkInLine(.waiting, isDeparture: isDeparture)
            waiting.insert(c.id)
            scheduleTimeout(c.id)
        } else {
            lines[c.stopId] = WatchTripText.checkInLine(.offline, isDeparture: isDeparture)
        }
    }

    /// 還沒送出去的（holding）現在送：WCSession 啟動好、iPhone 回到身邊、回前景（WatchSync、WatchModel 叫）
    func sendDue() {
        for item in items where item.state == .holding {
            send(item.checkIn)
        }
    }

    // MARK: WatchSync 回來（主執行緒）

    /// sendMessage 的回話：["ok": "done"|"queued"|"already"|"gone"|"failed", "at": 秒]
    func phoneReplied(_ id: UUID, ok: String?, at: Date?) {
        waiting.remove(id)
        guard let item = items.first(where: { $0.id == id }) else { return }
        let stopId = item.checkIn.stopId
        let isDeparture = item.isDeparture
        if ok == WatchLink.okDone {
            WatchCheckInLog.update(id) { $0.state = .done }
            lines[stopId] = WatchTripText.checkInLine(.done, isDeparture: isDeparture)
        } else if ok == WatchLink.okQueued {
            WatchCheckInLog.update(id) { $0.state = .queued }
            lines[stopId] = WatchTripText.checkInLine(.queued, isDeparture: isDeparture)
        } else if ok == WatchLink.okAlready {
            let shown = at ?? item.checkIn.createdAt
            WatchCheckInLog.update(id) { stored in
                stored.state = .already
                stored.phoneTime = shown
            }
            lines[stopId] = WatchTripText.checkInLine(.already(shown), isDeparture: isDeparture)
        } else if ok == WatchLink.okGone {
            // 那一站在 iPhone 上被刪了：手錶上這一筆拿掉（不再補到畫面上）
            WatchCheckInLog.remove(id)
            lines[stopId] = WatchTripText.checkInLine(.gone, isDeparture: isDeparture)
        } else {
            // 解不開、寫不進去：transferUserInfo 那一份照樣排著
            lines[stopId] = WatchTripText.checkInLine(.offline, isDeparture: isDeparture)
        }
        reload()
        WidgetCenter.shared.reloadTimelines(ofKind: WatchWidgetKind.nextUp)
    }

    /// sendMessage 失敗（iPhone 不在旁邊了、LifeGood 被滑掉…）：transferUserInfo 那一份照樣排著
    func phoneUnreachable(_ id: UUID) {
        guard waiting.contains(id) else { return }
        waiting.remove(id)
        guard let item = items.first(where: { $0.id == id }) else { return }
        lines[item.checkIn.stopId] = WatchTripText.checkInLine(.offline, isDeparture: item.isDeparture)
    }

    /// transferUserInfo 送完、沒有錯：iPhone 收到了（還沒回話的，至少不再寫「先存在手錶上」）
    func markDelivered(_ id: UUID) {
        WatchCheckInLog.update(id) { stored in
            if stored.state == .sent || stored.state == .holding {
                stored.state = .delivered
            }
        }
        reload()
        guard let item = items.first(where: { $0.id == id }) else { return }
        if item.state == .delivered && !waiting.contains(id) {
            lines[item.checkIn.stopId] = WatchTripText.checkInLine(.delivered, isDeparture: item.isDeparture)
        }
    }

    /// WatchSync 收到新包、WatchCheckInLog.reconcile 做完之後：重讀；還沒送出去的補送
    func packageApplied() {
        reload()
        sendDue()
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
        guard let item = items.first(where: { $0.id == id }) else { return }
        if item.state == .delivered {
            lines[item.checkIn.stopId] = WatchTripText.checkInLine(.delivered, isDeparture: item.isDeparture)
        } else {
            lines[item.checkIn.stopId] = WatchTripText.checkInLine(.offline, isDeparture: item.isDeparture)
        }
    }
}
