import Foundation
import UserNotifications

// MARK: - 旅遊規劃的跨裝置通知（v25.454）
//
// 情境：在 A 手機新增了行程／景點／要帶的東西／伴手禮，B 手機要收到通知。
//
// 不需要自己的伺服器也不需要 APNs 憑證：CloudKit 的 zone 訂閱
//（CloudKitManager.ensureSubscriptionExists，shouldSendContentAvailable = true）
// 已經會在資料變動時把其他裝置叫起來拉變更。缺的只是「拉完之後跟使用者說一聲」。
//
// 所以這裡做的事很小：比對拉取前後的 tripPlans，把多出來的東西寫成本機通知。
// 真正的推播是 CloudKit 發的，這支只負責把它翻成人看得懂的一句話。
//
// 為什麼不會通知到自己：CloudKitManager 拉取時會比對內容，與本機已存的完全相同
// 就當成 echo 跳過，不會進 pulledKVKeys。自己推上去的變更不會變成自己的通知。

enum TripChangeNotifier {

    /// 使用者開關（設定頁）。預設開——這個功能的用處就是「不用自己問對方加了什麼」，
    /// 預設關掉等於沒做。
    static let enabledKey = "trip_sync_push_enabled"

    static var isEnabled: Bool {
        get {
            // 沒設定過的裝置回 true；UserDefaults.bool 對不存在的 key 回 false，
            // 直接用會讓預設變成「關」。
            UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// 一次拉取最多發幾則。再多就收斂成一則總結——
    /// 另一台裝置一口氣貼了 30 個景點時，30 則通知只會讓人把通知權限關掉。
    private static let maxNotifications = 6

    /// 通知 userInfo 裡放行程 id，點通知才知道要打開哪一份
    static let planIdKey = "trip_plan_id"

    // MARK: - 對外

    /// 由 LifeStore 在「從雲端拉取並重載完」之後呼叫。
    /// before／after 是重載前後的 tripPlans。
    ///
    /// 刻意不標 @MainActor：呼叫點是 LifeStore 的 @objc 通知處理函式（非 isolated），
    /// 標了就得在呼叫端包一層 Task，白白多一個 run-loop 空窗。這裡做的事
    /// （讀 UserDefaults、純比對）本來就與執行緒無關，需要 MainActor 的
    /// 權限檢查在 Task 裡 await。
    static func report(before: [TripPlan], after: [TripPlan]) {
        guard isEnabled else { return }
        // 本機原本一筆行程都沒有、卻一次拉進好幾份＝這台剛接上同步在補歷史資料，
        // 不是「別人剛剛新增了什麼」，整批報一遍只是洗版。
        //
        // 門檻刻意放在「好幾份」而不是「原本沒有」：對方建立**第一份**行程時，
        // 這台的 before 本來就是空的——那正是最該通知的時候，不能一起擋掉。
        if before.isEmpty, after.count > 2 { return }

        let items = diff(before: before, after: after)
        guard !items.isEmpty else { return }

        // NotificationManager 是 class 層級 @MainActor，連 .shared 都是隔離的，
        // 所以整個閉包標成 @MainActor，而不是在裡面逐個 await 屬性存取。
        Task { @MainActor in
            guard await NotificationManager.shared.requestAuthorization() else { return }
            await deliver(items)
        }
    }

    // MARK: - 差異

    /// 一則通知的內容
    struct Change {
        let planId: UUID
        let title: String
        let body: String
    }

    static func diff(before: [TripPlan], after: [TripPlan]) -> [Change] {
        let old = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [Change] = []

        for plan in after {
            guard let prev = old[plan.id] else {
                // 整份行程是新的
                out.append(Change(
                    planId: plan.id,
                    title: "其他裝置新增了旅遊行程",
                    body: planLine(plan)))
                continue
            }

            let newStops = added(plan.stops.map(\.id), prev.stops.map(\.id))
            if !newStops.isEmpty {
                let names = plan.stops.filter { newStops.contains($0.id) }.map(\.displayName)
                out.append(Change(
                    planId: plan.id,
                    title: "「\(plan.displayTitle)」新增景點",
                    body: listLine(names, unit: "個景點")))
            }

            let newPacking = added(plan.packingItems.map(\.id), prev.packingItems.map(\.id))
            if !newPacking.isEmpty {
                let names = plan.packingItems.filter { newPacking.contains($0.id) }
                    .map(\.titleWithQuantity)
                out.append(Change(
                    planId: plan.id,
                    title: "「\(plan.displayTitle)」要帶的東西",
                    body: listLine(names, unit: "項")))
            }

            let newSouvenir = added(plan.souvenirItems.map(\.id), prev.souvenirItems.map(\.id))
            if !newSouvenir.isEmpty {
                let names = plan.souvenirItems.filter { newSouvenir.contains($0.id) }
                    .map { item -> String in
                        let who = item.forWhom.trimmingCharacters(in: .whitespaces)
                        return who.isEmpty ? item.titleWithQuantity
                                           : item.titleWithQuantity + "（給\(who)）"
                    }
                out.append(Change(
                    planId: plan.id,
                    title: "「\(plan.displayTitle)」要帶回來的伴手禮",
                    body: listLine(names, unit: "項")))
            }
        }
        return out
    }

    /// after 有、before 沒有的 id。用 Set 比對，不靠順序——
    /// 另一台裝置重排過景點順序時，位置比對會把整串都當成新的。
    private static func added(_ after: [UUID], _ before: [UUID]) -> Set<UUID> {
        Set(after).subtracting(Set(before))
    }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d"
        return f
    }()

    private static func planLine(_ plan: TripPlan) -> String {
        var pieces = ["「\(plan.displayTitle)」"]
        let start = dayFmt.string(from: plan.startDate)
        let end = dayFmt.string(from: plan.endDate)
        pieces.append(start == end ? start : start + "–" + end)
        if !plan.stops.isEmpty { pieces.append("\(plan.stops.count) 個景點") }
        return pieces.joined(separator: " · ")
    }

    /// 「東京鐵塔、淺草寺、晴空塔 等 5 個景點」。
    /// 全部列出來會被系統截斷在不知道哪裡，前三個加總數才讀得完。
    private static func listLine(_ names: [String], unit: String) -> String {
        let shown = names.prefix(3).joined(separator: "、")
        if names.count <= 3 { return shown }
        return shown + " 等 \(names.count) \(unit)"
    }

    // MARK: - 送出

    private static func deliver(_ items: [Change]) async {
        let center = UNUserNotificationCenter.current()

        if items.count > maxNotifications {
            // 太多就收斂成一則。planId 取第一筆——點進去至少落在其中一份行程上，
            // 比落在清單頁好。
            let content = UNMutableNotificationContent()
            content.title = "旅遊規劃有新內容"
            content.body = "其他裝置新增了 \(items.count) 項（行程／景點／攜帶物品／伴手禮）"
            content.sound = .default
            content.threadIdentifier = "trip_sync"
            content.userInfo = [planIdKey: items[0].planId.uuidString]
            let req = UNNotificationRequest(
                identifier: "trip_sync_summary_\(Int(Date().timeIntervalSince1970))",
                content: content, trigger: nil)
            try? await center.add(req)
            return
        }

        for (i, change) in items.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = change.title
            content.body = change.body
            content.sound = .default
            // 同一份行程的通知在通知中心疊成一組，不是散成好幾條
            content.threadIdentifier = "trip_\(change.planId.uuidString)"
            content.userInfo = [planIdKey: change.planId.uuidString]
            let req = UNNotificationRequest(
                identifier: "trip_sync_\(change.planId.uuidString)_\(Int(Date().timeIntervalSince1970))_\(i)",
                content: content, trigger: nil)
            try? await center.add(req)
        }
    }
}
