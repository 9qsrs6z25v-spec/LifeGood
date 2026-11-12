import Foundation
import UserNotifications

// MARK: - [v25.625] 水電 v6（util6）：「水電用得比較多時通知我」排進通知中心、拿掉（radar/build/util6/brief.md）
//
// 要不要排、字、identifier 全在 UtilityHighNotice.swift（純函式，sim_util6.py 照那裡寫過、跑過）；這裡只做三件事：
//   1. 問通知中心（授權狀態、待發清單）、問三份資料（AppStores；HouseCardData.build 算這間房子的水電列）
//   2. 照 UtilityHighNotice.plan 拿掉、排進去
//   3. 存本機紀錄（UserDefaults.standard「utility_high_notice_log_v1」；不同步、不進備份）
//
// 什麼時候跑（都由 App 裡的程式叫；沒有背景抓取、沒有伺服器）：
//   • afterSave：繳費表單按〔儲存〕成功、dismiss 之後的那個 DispatchQueue.main.async 裡、store 寫完之後（RealEstateEditors.swift）
//   • afterDelete：繳費表單刪掉那一期之後（同上）
//   • enabledChanged／hideNameChanged：設定頁那兩顆開關一動（UtilityNoticeSettingsRows.swift）
//   • appBecameActive：App 回前景（LifeGoodApp.swift）：那一期在別台刪了、換了種類、房子刪了或賣了 → 拿掉
// **沒有通知權限就不排、不算、不跳權限要求**（權限照既有的入口問：行事曆、財富提醒第一次排的時候）。拿掉不需要權限：
// 沒權限時存檔，這一期自己的、這間這一種還在等的那則拿掉（當作不偏高）。
// 關掉「水電用得比較多時通知我」：通知中心裡已經送到的也拿掉；打開「不要出現房子名稱」：送到的、寫了名字的那幾則拿掉。
// 打開「不要出現房子名稱」時沒權限（改不了字）：待發、寫了名字的那幾則直接拿掉。
// 一件一件排隊做（running）：連按兩次儲存不會拿到同一份待發清單。不在 body／.task 裡叫。
//
// 不在 class 層級加 @MainActor（同 OrgMoveNoticeRouter）：入口在主執行緒叫，真正做事的 handle 是 @MainActor。

/// 排隊的一件事
enum UtilityHighNoticeEvent: Equatable {
    case saved(estateId: UUID, paymentId: UUID, type: UtilityType)
    case deleted(estateId: UUID, paymentId: UUID)
    case enabledChanged
    case hideNameChanged
    case sweep
}

final class UtilityHighNoticeCenter {
    static let shared = UtilityHighNoticeCenter()

    private init() {}

    /// 正在做的那一件（下一件等它做完；只在主執行緒讀寫）
    private var running: Task<Void, Never>? = nil

    // MARK: 入口（都在主執行緒叫）

    /// 繳費表單按〔儲存〕成功之後（dismiss 之後的 DispatchQueue.main.async 裡，度數、房子都寫完之後叫）
    func afterSave(estateId: UUID, paymentId: UUID, type: UtilityType) {
        enqueue(.saved(estateId: estateId, paymentId: paymentId, type: type))
    }

    /// 繳費表單刪掉那一期之後
    func afterDelete(estateId: UUID, paymentId: UUID) {
        enqueue(.deleted(estateId: estateId, paymentId: paymentId))
    }

    /// 設定「水電用得比較多時通知我」一動（關掉＝待發的全部拿掉；打開不補排）
    func enabledChanged() {
        enqueue(.enabledChanged)
    }

    /// 設定「通知裡不要出現房子名稱」一動：待發的那幾則照新的設定重寫內文
    func hideNameChanged() {
        enqueue(.hideNameChanged)
    }

    /// App 回前景：那一期已經不在的待發通知拿掉
    func appBecameActive() {
        enqueue(.sweep)
    }

    private func enqueue(_ event: UtilityHighNoticeEvent) {
        let previous = running
        running = Task { @MainActor [weak self] in
            await previous?.value
            await self?.handle(event)
        }
    }

    // MARK: 做事

    @MainActor
    private func handle(_ event: UtilityHighNoticeEvent) async {
        let center = UNUserNotificationCenter.current()
        switch event {
        case .saved(let estateId, let paymentId, let type):
            await saved(estateId: estateId, paymentId: paymentId, type: type, center: center)
        case .deleted(let estateId, let paymentId):
            let pending: [String] = await Self.pendingIds(center)
            let plan: UtilityHighNoticePlan = UtilityHighNotice.plan(.gone, estateId: estateId, paymentId: paymentId,
                                                                     type: nil, shownName: nil, enabled: false,
                                                                     now: Date(), cal: Calendar.current,
                                                                     pending: pending, log: Self.loadLog())
            await apply(plan, center: center)
        case .enabledChanged:
            guard !UtilityHighNotice.isEnabled else { return }
            let pending: [String] = await Self.pendingIds(center)
            removeAndForget(UtilityHighNotice.ours(pending), center: center)
            // [G1 補] 關掉：通知中心裡已經送到、還留著的水電通知也拿掉（同交接提醒關掉時）
            await removeDelivered(onlyNamed: false, center: center)
        case .hideNameChanged:
            // [G1 補] 打開「不要出現房子名稱」：已經送到、還留在通知中心、寫了房子名稱的那幾則拿掉（送到的改不了字）
            if UtilityHighNotice.hidesName {
                await removeDelivered(onlyNamed: true, center: center)
            }
            await rewritePending(center: center)
        case .sweep:
            let pending: [String] = await Self.pendingIds(center)
            let ours: [String] = UtilityHighNotice.ours(pending)
            guard !ours.isEmpty else { return }
            let gone: [String] = UtilityHighNotice.isEnabled
                ? UtilityHighNotice.stale(pending: ours, estates: AppStores.finance.realEstates)
                : ours
            removeAndForget(gone, center: center)
        }
    }

    /// 存了一期：開著、有權限才算；算這間房子的水電列（跟房子詳情同一支 HouseCardData.build），照 plan 排
    @MainActor
    private func saved(estateId: UUID, paymentId: UUID, type: UtilityType, center: UNUserNotificationCenter) async {
        guard UtilityHighNotice.isEnabled else { return }
        let settings = await center.notificationSettings()
        guard Self.authorized(settings.authorizationStatus) else {
            // [裁定補] 沒權限：不算、不排、不問權限；只把這一期自己的、這間這一種還在等的拿掉（拿掉不需要權限）。
            // 不然「有權限時排好 → 關掉通知 → 改回不偏高存檔 → 20:00 前又打開通知」那則還是會響
            let waiting: [String] = await Self.pendingIds(center)
            let quiet: UtilityHighNoticePlan = UtilityHighNotice.plan(.notHigh, estateId: estateId, paymentId: paymentId,
                                                                      type: type, shownName: nil, enabled: false,
                                                                      now: Date(), cal: Calendar.current,
                                                                      pending: waiting, log: Self.loadLog())
            await apply(quiet, center: center)
            return
        }
        var verdict: UtilityHighVerdict = .gone
        var rawName: String? = nil
        if let re = AppStores.finance.realEstates.first(where: { $0.id == estateId }) {
            rawName = re.name
            let card: HouseCardData = HouseCardData.build(re, expense: AppStores.expense,
                                                          vehicles: AppStores.finance.vehicles)
            if let src = card.utilities.trendSource {
                verdict = UtilityHighNotice.verdict(rows: src.rows.rows, paymentId: paymentId, asOf: src.asOf,
                                                    isSold: src.isSold, cal: Calendar.current)
            }
        }
        let shown: String? = UtilityHighNotice.shownName(rawName, hide: UtilityHighNotice.hidesName)
        let pending: [String] = await Self.pendingIds(center)
        let plan: UtilityHighNoticePlan = UtilityHighNotice.plan(verdict, estateId: estateId, paymentId: paymentId,
                                                                 type: type, shownName: shown, enabled: true,
                                                                 now: Date(), cal: Calendar.current,
                                                                 pending: pending, log: Self.loadLog())
        await apply(plan, center: center)
    }

    /// 先拿掉、再排；排不進去的那則紀錄裡不算在等
    @MainActor
    private func apply(_ plan: UtilityHighNoticePlan, center: UNUserNotificationCenter) async {
        if !plan.remove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: plan.remove)
        }
        guard let job = plan.add else {
            Self.saveLog(plan.log)
            return
        }
        let request: UNNotificationRequest = Self.request(job)
        do {
            try await center.add(request)
            Self.saveLog(plan.log)
        } catch {
            // [G1 補] 排不進去：同一個 identifier 原本在等的那則（同一期重存）也拿掉，紀錄跟通知中心才對得上
            center.removePendingNotificationRequests(withIdentifiers: [job.identifier])
            Self.saveLog(UtilityHighNotice.forgetting([job.identifier], in: plan.log))
        }
    }

    /// 拿掉這幾則、紀錄裡不算送了
    @MainActor
    private func removeAndForget(_ ids: [String], center: UNUserNotificationCenter) {
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        Self.saveLog(UtilityHighNotice.forgetting(ids, in: Self.loadLog()))
    }

    /// 通知中心裡已經送到的水電通知拿掉（拿掉不需要權限）。onlyNamed＝只拿內文寫了房子名稱的（開頭不是「有一間房子」）
    @MainActor
    private func removeDelivered(onlyNamed: Bool, center: UNUserNotificationCenter) async {
        let delivered: [UNNotification] = await center.deliveredNotifications()
        var ids: [String] = []
        for n in delivered where n.request.identifier.hasPrefix(UtilityHighNotice.prefix) {
            if onlyNamed && n.request.content.body.hasPrefix(UtilityHighNotice.someHouse) { continue }
            ids.append(n.request.identifier)
        }
        guard !ids.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// 換了「不要出現房子名稱」：待發的那幾則換內文（同一個 identifier、同一個時間）。
    /// [G1 補] 沒權限（改不了字）或換不進去、而且這次是要藏名字：寫了名字的那則直接拿掉（之後打開權限也不會響出名字；拿掉不需要權限）
    @MainActor
    private func rewritePending(center: UNUserNotificationCenter) async {
        let settings = await center.notificationSettings()
        let canAdd: Bool = Self.authorized(settings.authorizationStatus)
        let requests: [UNNotificationRequest] = await center.pendingNotificationRequests()
        let hide: Bool = UtilityHighNotice.hidesName
        let estates: [RealEstate] = AppStores.finance.realEstates
        var drop: [String] = []
        for r in requests where r.identifier.hasPrefix(UtilityHighNotice.prefix) {
            guard let parsed = UtilityHighNotice.parse(r.identifier) else { continue }
            let name: String? = estates.first(where: { $0.id == parsed.estateId })?.name
            let partner: String? = r.content.userInfo[UtilityHighNotice.partnerInfoKey] as? String
            guard let text = UtilityHighNotice.rewrittenBody(identifier: r.identifier, partner: partner,
                                                             estateName: name, hide: hide),
                  text != r.content.body else { continue }
            guard canAdd, let content = r.content.mutableCopy() as? UNMutableNotificationContent else {
                if hide { drop.append(r.identifier) }
                continue
            }
            content.body = text
            let next = UNNotificationRequest(identifier: r.identifier, content: content, trigger: r.trigger)
            do {
                try await center.add(next)
            } catch {
                if hide { drop.append(r.identifier) }
            }
        }
        removeAndForget(drop, center: center)
    }

    // MARK: 小工具

    static func authorized(_ s: UNAuthorizationStatus) -> Bool {
        switch s {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    static func pendingIds(_ center: UNUserNotificationCenter) async -> [String] {
        let requests: [UNNotificationRequest] = await center.pendingNotificationRequests()
        return requests.map { $0.identifier }
    }

    /// 通知內容：標題「水電瓦斯」、內文沒有數字；不掛按鈕（categoryIdentifier 不設）、不改 App 圖示上的數字
    static func request(_ job: UtilityHighNoticeJob) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = job.title
        content.body = job.body
        content.sound = .default
        content.threadIdentifier = UtilityHighNotice.threadId
        let partner: String = job.vsLastYear ? UtilityHighNotice.partnerLastYear : UtilityHighNotice.partnerRecent
        content.userInfo = [UtilityHighNotice.estateInfoKey: job.estateId.uuidString,
                            UtilityHighNotice.kindInfoKey: job.typeCode,
                            UtilityHighNotice.partnerInfoKey: partner]
        let comps: DateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute],
                                                                    from: job.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return UNNotificationRequest(identifier: job.identifier, content: content, trigger: trigger)
    }

    static func loadLog() -> UtilityHighNoticeLog {
        guard let d = UserDefaults.standard.data(forKey: UtilityHighNotice.logKey),
              let log = try? JSONDecoder().decode(UtilityHighNoticeLog.self, from: d) else { return UtilityHighNoticeLog.empty }
        return log
    }

    static func saveLog(_ log: UtilityHighNoticeLog) {
        guard let d = try? JSONEncoder().encode(log) else { return }
        UserDefaults.standard.set(d, forKey: UtilityHighNotice.logKey)
    }
}
