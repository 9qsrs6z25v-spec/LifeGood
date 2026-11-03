import Foundation

// MARK: - 手錶的打卡（手錶 v6，v25.578；只屬於主 App；watch/judge.md §4.1、§4.4、§5.4、附錄 B；watch/build/v6/brief.md §2）
//
// 手錶按〔到了〕〔離開〕送來一筆 WatchCheckIn（Shared/WatchPackage.swift）。iPhone 這邊兩種情況：
//   • LifeGood 開著、或剛用過還活著（WatchActionApplier.isReady：LifeGoodApp 的 .task 叫過 start）：
//     WatchBridge 直接 WatchActionApplier.apply → LifeStore.setTripStopCheckIn，回「done／already／gone」
//   • 被手錶叫醒的冷啟動（畫面沒建立、.task 沒跑）：**不碰三份大資料**（judge §5.4、§7.8-6），
//     WatchBridge 只把它寫成 App Group 的一個小檔（WatchActionInbox.add），回「queued」；
//     下次打開 LifeGood（.task、回前景）WatchActionApplier.applyPending 照按下去的時間順序套用、套完刪檔
//
// 檔：<App Group>/Widgets/watch_actions_v1/<編號>.json，一筆一個檔（照 QuickRecordInbox：不用檔案鎖）。
// 同一筆從兩條路（transferUserInfo＋sendMessage）都到：同一個編號＝同一個檔名，覆寫，不會變兩筆。
//
// 寫進行程的規則（WatchCheckInRule；sim_v6.py checkin_resolve，改了兩邊一起改）：送的是「設成幾點」不是「切換」——
//   • 那一趟、那一站不在了 → gone（「這一站在 iPhone 上改過了」）
//   • 只補 iPhone 上還沒有的：到達＝iPhone 已經有的 ?? 手錶送的；離開＝iPhone 已經有的 ?? 手錶送的
//     （你在 iPhone 也按了、家人在她手機打了：不蓋）
//   • 什麼都沒補到 → already，帶 iPhone 上那個時間（〔到了〕看到達、〔離開〕看離開；「已經在 14:05 打過卡」）
//   • 時間一律是手錶按下去那一刻（WatchCheckIn.arrival／departure），不是送到的時間
//   離開不能早於到達：LifeStore.setTripStopCheckIn 自己會取 max。
//
// ⚠️ WatchActionInbox（檔案那一半）會在被手錶叫醒的冷啟動跑：只准碰 App Group 的檔，不准碰 AppStores／三份大資料
//    （pkg_keys_check.py D3 段擋）。WatchActionApplier 只在 LifeGoodApp 的 .task 把 LifeStore 交給它之後才會寫。

/// 排著的打卡（只有檔案；被手錶叫醒的冷啟動也能叫）
enum WatchActionInbox {
    /// <App Group>/Widgets/ 底下的資料夾
    static let folderName = "watch_actions_v1"

    /// <App Group>/Widgets/watch_actions_v1/。create 為 true 時順手建（保護等級跟收件匣一樣）
    static func folderURL(create: Bool) -> URL? {
        guard let base = WidgetSnapshotStore.folderURL(create: create) else { return nil }
        let folder = base.appendingPathComponent(folderName, isDirectory: true)
        if create {
            let attributes: [FileAttributeKey: Any] = [
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ]
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                        attributes: attributes)
            } catch {
                return nil
            }
        }
        return folder
    }

    private static func fileURL(_ id: UUID, in folder: URL) -> URL {
        folder.appendingPathComponent(id.uuidString + ".json", isDirectory: false)
    }

    /// 排一筆（原子寫入；同一個編號覆寫同一個檔）。寫不進去回 false
    @discardableResult
    static func add(_ checkIn: WatchCheckIn) -> Bool {
        guard let folder = folderURL(create: true), let data = WatchCheckInCodec.encode(checkIn) else { return false }
        do {
            try data.write(to: fileURL(checkIn.id, in: folder),
                           options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }

    /// 排著的全部，依按下去的時間由舊到新（同一刻編號字串小的先）。解不開的壞檔刪掉（不然每次都卡在那裡）
    static func pending() -> [WatchCheckIn] {
        guard let folder = folderURL(create: false) else { return [] }
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles]) else { return [] }
        var out: [WatchCheckIn] = []
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let checkIn = WatchCheckInCodec.decode(data) {
                out.append(checkIn)
            } else {
                try? fm.removeItem(at: url)
            }
        }
        return out.sorted { a, b in
            if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
            return a.id.uuidString < b.id.uuidString
        }
    }

    static func remove(_ id: UUID) {
        guard let folder = folderURL(create: false) else { return }
        try? FileManager.default.removeItem(at: fileURL(id, in: folder))
    }
}

/// 打卡寫進行程的規則（純函式；sim_v6.py checkin_resolve）
enum WatchCheckInRule {
    enum Outcome: Equatable {
        /// 寫進去：到達、離開設成這兩個（nil＝那一欄維持沒有）
        case applied(arrival: Date?, departure: Date?)
        /// 什麼都沒補到：iPhone 上那個時間（〔到了〕＝到達、〔離開〕＝離開；iPhone 上也沒有＝按下去那一刻）
        case already(Date)
        /// 那一趟或那一站不在了
        case gone
    }

    /// current＝iPhone 上那一站現在的到達、離開（找不到那一站傳 nil）
    static func resolve(current: (arrival: Date?, departure: Date?)?, checkIn c: WatchCheckIn) -> Outcome {
        guard let current else { return .gone }
        let arrival: Date? = current.arrival ?? c.arrival
        let departure: Date? = current.departure ?? c.departure
        if arrival == current.arrival && departure == current.departure {
            let isDeparture = c.departure != nil
            let shown: Date? = isDeparture ? current.departure : current.arrival
            return .already(shown ?? c.createdAt)
        }
        return .applied(arrival: arrival, departure: departure)
    }
}

/// 把打卡寫進 LifeStore（主執行緒；LifeGoodApp 的 .task 叫過 start 才會寫）
@MainActor
final class WatchActionApplier {
    static let shared = WatchActionApplier()

    private weak var lifeStore: LifeStore?

    private init() {}

    /// start 叫過、LifeStore 還在（App 開著、或剛用過還活著）。WatchBridge 看這個決定「馬上寫」還是「只排檔」
    var isReady: Bool { lifeStore != nil }

    /// LifeGoodApp 的 .task 叫一次（重複呼叫無害）：記住 LifeStore。排著的由呼叫的人接著叫 applyPending
    func start(life: LifeStore) {
        lifeStore = life
    }

    /// 套一筆（WatchBridge 活著時、applyPending）。寫進去了就馬上重寫 life 快照（手錶包跟著送）
    @discardableResult
    func apply(_ checkIn: WatchCheckIn) -> WatchCheckInRule.Outcome {
        guard let life = lifeStore else { return .gone }
        let outcome = Self.outcome(of: checkIn, plans: life.tripPlans)
        if case .applied(let arrival, let departure) = outcome {
            life.setTripStopCheckIn(planId: checkIn.planId, stopId: checkIn.stopId,
                                    arrival: arrival, departure: departure)
            WidgetSnapshotWriter.shared.writeNow([.life])
        }
        return outcome
    }

    /// 套 watch_actions_v1 排著的（照按下去的時間由舊到新）；每一筆不管結果都刪檔。還沒 start 什麼都不做
    func applyPending() {
        guard isReady else { return }
        for checkIn in WatchActionInbox.pending() {
            apply(checkIn)
            WatchActionInbox.remove(checkIn.id)
        }
    }

    /// 這一筆在這份行程上會怎樣（不寫）
    static func outcome(of checkIn: WatchCheckIn, plans: [TripPlan]) -> WatchCheckInRule.Outcome {
        guard let plan = plans.first(where: { $0.id == checkIn.planId }),
              let stop = plan.stops.first(where: { $0.id == checkIn.stopId }) else {
            return WatchCheckInRule.resolve(current: nil, checkIn: checkIn)
        }
        return WatchCheckInRule.resolve(current: (arrival: stop.actualArrival, departure: stop.actualDeparture),
                                        checkIn: checkIn)
    }
}
