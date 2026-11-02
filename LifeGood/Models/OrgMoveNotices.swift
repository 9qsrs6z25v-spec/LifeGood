import Foundation
import Combine
import SwiftUI
import UserNotifications

// MARK: - [v25.596 轉組織 v3] 交接提醒（本機通知；orgmove/judge.md §4.11、§4.12、§7 v3；orgmove/build/v3/brief.md §2；
// sim_v3.py 照這裡一行一行寫過、跑過）
//
// 1. OrgMoveNotices：要排哪幾則（純計算，不碰通知中心）。identifier 前綴 "orgmove."：
//    • 生效前一天 20:00「明天有 1 份交接單生效」（orgmove.eve.<生效日>）——部門還沒改的（排好的、交出去了還沒到生效日的：orgPending）
//    • 生效日 08:15「今天有 1 份交接單生效，打開 App 就會一次改好」（orgmove.day.<生效日>）——同上；那天 08:15 以前打開 App
//      自動改好了＝不是 orgPending，重排時拿掉
//    • 交接完成日 09:00「有 1 份交接還有 1 件待分派」（orgmove.by.<交接完成日>）——還有待分派（機台現在還是原人負責）或還沒決定
//      （自己加的一項還沒選交給誰；排好了到那天都還沒套用的那幾列）才排
//    • 〔交出去〕給「我」的事原訂那天 09:00「你接的交接事項有 1 件今天到期」（orgmove.mine.<日子>）——還沒打勾收掉才排
//    同一天好幾張併成一則、寫件數。標題一律「交接提醒」。**字不寫名字、部門、是調走還是離職、事情內容**（只有件數和明天／今天）。
//    點了：只有一張＝打開那張交接單；好幾張、我接的＝部屬總覽（userInfo[OrgMoveNotices.userInfoKey]＝交接單 UUID 字串或 ""）。
//    開關：設定「交接提醒（只這台）」（OrgMoveNotices.enabledKey，UserDefaults.standard、不同步、不進備份）；
//    沒設過＝加入別人共享的那支（家人的）關、其他開（同 WealthReminders.transfersEnabled、v1b「今天生效」只在你的手機做的那套）。
//    關了＝把 orgmove. 開頭的待發、已送達的通知全部拿掉。
// 2. OrgMoveNoticeCenter：排進系統。LifeGoodApp 啟動 start 一次；交接單、機台負責人、部屬一改（防抖 2 秒）、
//    ReminderCenter.rebuildAll（啟動、回前景、會議改了）、設定開關一動都重排；要排的跟上次一樣就不動系統。
//    改生效日、取消、復原、套用完成、交接完成、刪除、〔回到我的部屬〕都是改 orgMoves → 自動重排。
// 3. OrgMoveNoticeRouter：點通知 → 人生 › 職涯 › 部屬總覽，總覽取走後打開那張交接單（找不到就停在總覽）。
// 4. OrgMoveReminderLater：〔11/1 一起做〕到期自動套用時沒動的 Apple 提醒事項（收回的分身、不要了的那幾則 id、件數），
//    存在這台（UserDefaults.standard，不同步：自動套用只在你的手機做，Apple 提醒事項也是這台的帳號）。
//    以前只記在記憶體（App 關掉就刪不掉了，v1b brief §11、v2 brief §11-8）；現在關掉重開，交接單頁照樣有〔更新提醒事項〕。
//
// 鎖定畫面、小工具、手錶錶面、手腕放下、靈動島一個字都沒加（judge §4.12）；手錶包不加欄位。

/// 一則要排的交接提醒（字已經組好；不含名字、部門、調動種類、事情內容）
struct OrgMoveNoticeJob: Equatable {
    /// UNNotificationRequest.identifier：「orgmove.eve.2026-11-01」「orgmove.day.2026-11-01」「orgmove.by.2026-11-11」「orgmove.mine.2026-11-05」
    let key: String
    /// 「交接提醒」
    let title: String
    /// 「明天有 1 份交接單生效」
    let body: String
    let fireDate: Date
    /// 點了開哪一張（只有一張才有；好幾張、我接的＝nil → 部屬總覽）
    let moveId: UUID?
}

enum OrgMoveNotices {
    /// 重排時認得「哪些是交接提醒排的」
    static let prefix = "orgmove."
    /// 設定的「交接提醒（只這台）」（UserDefaults.standard；不同步、不進備份）
    static let enabledKey = "orgmove_notices_enabled"
    /// 點通知要開哪一張（userInfo；交接單 UUID 字串，"" ＝部屬總覽）
    static let userInfoKey = "orgmove_move_id"
    /// 通知中心疊成一組
    static let threadId = "orgmove"
    /// 標題
    static let title = "交接提醒"
    /// 最多幾則（iOS 64 則待發：部屬會議 20、財富 10，這裡很克制）
    static let limit = 8

    /// 這台要不要排：設過照設的；沒設過＝加入別人共享的那支（家人的）關、其他開（judge §4.11）
    static var isEnabled: Bool {
        if let v = UserDefaults.standard.object(forKey: enabledKey) as? Bool { return v }
        return !CloudKitManager.shared.isShareParticipant
    }

    // MARK: 算件數

    /// 交接完成日那則的件數：待分派（單上待分派、機台現在還是原人負責）＋還沒決定（自己加的一項還沒選交給誰；
    /// 部門還沒改、還沒套用的那幾列）。owners＝機台 id → 現在的負責人（OrgMoveIndex.equipmentOwners）
    static func openCounts(_ m: OrgMove, owners: [UUID: UUID]) -> (pending: Int, undecided: Int) {
        var pending = 0
        for lid in OrgMovePlan.pendingLineIds(m) {
            guard let eid = m.line(lid)?.refId else { continue }
            if owners[eid] == m.personId { pending += 1 }
        }
        var undecided = 0
        for l in m.allLines where !l.isOrgLine && l.state != OrgMoveLineState.undone.rawValue {
            if l.isCustom {
                if l.action == nil && l.toId == nil && l.checkedAt == nil { undecided += 1 }
            } else if m.isPlanned && l.action == nil && l.state == nil {
                undecided += 1
            }
        }
        return (pending, undecided)
    }

    // MARK: 字（只有件數、明天／今天；sim 斷言不含任何部屬、組織人員名字、部門名）

    static func eveBody(_ n: Int) -> String { "明天有 \(n) 份交接單生效" }
    static func dayBody(_ n: Int) -> String { "今天有 \(n) 份交接單生效，打開 App 就會一次改好" }
    static func byBody(moves: Int, pending: Int, undecided: Int) -> String {
        if pending > 0 && undecided > 0 { return "有 \(moves) 份交接還有 \(pending) 件待分派、\(undecided) 件還沒決定" }
        if undecided > 0 { return "有 \(moves) 份交接還有 \(undecided) 件還沒決定" }
        return "有 \(moves) 份交接還有 \(pending) 件待分派"
    }
    static func mineBody(_ n: Int) -> String { "你接的交接事項有 \(n) 件今天到期" }
    /// [v25.597 轉組織 v4] 回來前 3 天：「有一位同仁 1/29 回來，有 3 件要還」（好幾位「有 2 位同仁 1/29 回來，有 5 件要還」；
    /// 沒有要還的「有一位同仁 1/29 回來」）。不寫名字、部門、借調還是留停
    static func backBody(people: Int, dayKey: String, items: Int) -> String {
        let who = people == 1 ? "有一位同仁" : "有 \(people) 位同仁"
        let d = OrgMovePlan.shortDay(dayKey)
        return items > 0 ? "\(who) \(d) 回來，有 \(items) 件要還" : "\(who) \(d) 回來"
    }

    // MARK: 候選

    /// 所有交接提醒：不看時間、不限則數、照日子排（sim_v3.py notice_candidates）。純計算：不碰通知中心。
    /// personIds＝現在還在的部屬 id（人被刪了的那張不提醒：到期也套不了）
    /// [v25.597 轉組織 v4] backCounts＝暫時離開那張 id → 要還的件數（OrgMovePlan.returnItemCount；OrgMoveNoticeCenter 照現在的資料算好給）
    static func candidates(book: OrgMoveBook, owners: [UUID: UUID], personIds: Set<UUID>,
                           backCounts: [UUID: Int] = [:]) -> [OrgMoveNoticeJob] {
        let moves: [OrgMove] = book.live.filter { !$0.isBack && personIds.contains($0.personId) }
        var out: [OrgMoveNoticeJob] = []

        // 生效前一天、生效日：部門還沒改的（排好的、交出去了還沒到生效日的）
        var effGroups: [String: [UUID]] = [:]
        for m in moves where m.orgPending && !m.effectiveKey.isEmpty {
            effGroups[m.effectiveKey, default: []].append(m.id)
        }
        for k in effGroups.keys.sorted() {
            let ids = effGroups[k] ?? []
            let one: UUID? = ids.count == 1 ? ids.first : nil
            if let f = at(OrgMovePlan.addDays(k, -1), hour: 20, minute: 0) {
                out.append(OrgMoveNoticeJob(key: prefix + "eve." + k, title: title, body: eveBody(ids.count),
                                            fireDate: f, moveId: one))
            }
            if let f = at(k, hour: 8, minute: 15) {
                out.append(OrgMoveNoticeJob(key: prefix + "day." + k, title: title, body: dayBody(ids.count),
                                            fireDate: f, moveId: one))
            }
        }

        // 交接完成日：還有待分派或還沒決定的（按了〔交接完成〕、復原了、取消了的不算）
        var byGroups: [String: [(id: UUID, pending: Int, undecided: Int)]] = [:]
        for m in moves where !m.isUndone && !m.isClosed && !m.isCancelled && (m.wasApplied || m.isPlanned) {
            let c = openCounts(m, owners: owners)
            guard c.pending + c.undecided > 0 else { continue }
            let k = m.handoverByKey ?? OrgMovePlan.handoverByKey(effectiveKey: m.effectiveKey)
            byGroups[k, default: []].append((id: m.id, pending: c.pending, undecided: c.undecided))
        }
        for k in byGroups.keys.sorted() {
            let rows = byGroups[k] ?? []
            guard let f = at(k, hour: 9, minute: 0) else { continue }
            let p = rows.reduce(0) { $0 + $1.pending }
            let u = rows.reduce(0) { $0 + $1.undecided }
            let one: UUID? = rows.count == 1 ? rows.first?.id : nil
            out.append(OrgMoveNoticeJob(key: prefix + "by." + k, title: title,
                                        body: byBody(moves: rows.count, pending: p, undecided: u),
                                        fireDate: f, moveId: one))
        }

        // 〔交出去〕給「我」、還沒收掉的：原訂那天 09:00（打開部屬總覽「我接的」）
        var mine: [String: Int] = [:]
        for m in moves where m.wasApplied && !m.isUndone {
            for l in m.allLines where l.lineAction == .handOut && l.toId == OrgMovePlan.meId
                && l.state == OrgMoveLineState.done.rawValue && l.checkedAt == nil {
                guard let k = l.newDueKey ?? l.dueKey else { continue }
                mine[k, default: 0] += 1
            }
        }
        for k in mine.keys.sorted() {
            guard let f = at(k, hour: 9, minute: 0) else { continue }
            out.append(OrgMoveNoticeJob(key: prefix + "mine." + k, title: title, body: mineBody(mine[k] ?? 0),
                                        fireDate: f, moveId: nil))
        }

        // [v25.597 轉組織 v4] 暫時離開回來前 3 天 09:00（orgmove.back.<回來那天>；同一天回來的併一則；按過〔還給本人〕〔留給代理人〕的不排）。
        // 要退回這一件：刪這一段與 backCounts 參數
        var back: [String: [UUID]] = [:]
        for m in moves where m.isTemp && m.wasApplied && !m.isUndone && !m.isCancelled && m.returnedAt == nil {
            guard let k = m.returnKey, OrgMovePlan.date(fromKey: k) != nil else { continue }
            back[k, default: []].append(m.id)
        }
        for k in back.keys.sorted() {
            let ids = back[k] ?? []
            guard let f = at(OrgMovePlan.addDays(k, -3), hour: 9, minute: 0) else { continue }
            let items = ids.reduce(0) { $0 + (backCounts[$1] ?? 0) }
            out.append(OrgMoveNoticeJob(key: prefix + "back." + k, title: title,
                                        body: backBody(people: ids.count, dayKey: k, items: items),
                                        fireDate: f, moveId: ids.count == 1 ? ids.first : nil))
        }
        return out
    }

    /// 候選裡時間還沒到的（fireDate > now），近的先排、最多 limit 則（sim_v3.py notice_jobs）。純計算
    static func jobs(from candidates: [OrgMoveNoticeJob], now: Date) -> [OrgMoveNoticeJob] {
        let upcoming: [OrgMoveNoticeJob] = candidates.filter { $0.fireDate > now }
        let ordered: [OrgMoveNoticeJob] = upcoming.enumerated().sorted { x, y in
            if x.element.fireDate != y.element.fireDate { return x.element.fireDate < y.element.fireDate }
            return x.offset < y.offset
        }.map { $0.element }
        return Array(ordered.prefix(limit))
    }

    /// 「2026-11-01」那天幾點幾分（西曆、手機時區；讀不懂回 nil）
    static func at(_ dayKey: String, hour: Int, minute: Int) -> Date? {
        guard let d = OrgMovePlan.date(fromKey: dayKey) else { return nil }
        return OrgMovePlan.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: d)
    }
}

// MARK: - 排程（主 App）

/// 把 OrgMoveNotices.jobs 排成本機通知。LifeGoodApp 啟動時 start 一次；ReminderCenter.rebuildAll、設定開關一動叫 rebuildSoon
@MainActor
final class OrgMoveNoticeCenter {
    static let shared = OrgMoveNoticeCenter()

    private init() {}

    private weak var lifeStore: LifeStore?
    private var cancellables = Set<AnyCancellable>()
    private var started = false
    /// 上一次真的排進系統的（key＋時間＋字＋開關）；這次一樣就不動系統
    private var lastSignature: String?
    /// 正在排的那一輪（下一輪等它跑完再排）
    private var running: Task<Void, Never>?

    /// 啟動時呼叫一次（重複呼叫無害）：交接單、機台負責人、部屬一改（防抖 2 秒）重排，然後馬上排一次
    func start(life: LifeStore) {
        guard !started else { return }
        started = true
        lifeStore = life
        let moves = life.$orgMoves.map { _ in () }
        let pool = life.$equipmentPool.map { _ in () }
        let subs = life.$subordinates.map { _ in () }
        moves.merge(with: pool)
            .merge(with: subs)
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildSoon() }
            .store(in: &cancellables)
        rebuildSoon()
    }

    /// 回到前景、會議提醒重排、設定的「交接提醒（只這台）」一動：重排（還沒 start 就什麼都不做）
    func rebuildSoon() {
        guard started else { return }
        let previous = running
        running = Task { @MainActor [weak self] in
            await previous?.value
            await self?.rebuild()
        }
    }

    private func rebuild() async {
        guard let life = lifeStore else { return }
        let enabled = OrgMoveNotices.isEnabled
        var jobs: [OrgMoveNoticeJob] = []
        if enabled {
            let ids = Set(life.subordinates.map(\.id))
            // [v25.597 轉組織 v4] 暫時離開還沒回來的：要還的件數照現在的資料算（有這種單才建查表）。要退回這一件：刪 temps／back 兩段、
            // candidates 拿掉 backCounts
            let temps = life.orgMoves.live.filter { $0.isTemp && $0.wasApplied && !$0.isUndone && $0.returnedAt == nil }
            var back: [UUID: Int] = [:]
            if !temps.isEmpty {
                let map = OrgMoveHolderMap(world: OrgMoveWorld(store: life))
                for m in temps { back[m.id] = OrgMovePlan.returnItemCount(m, map: map) }
            }
            let all = OrgMoveNotices.candidates(book: life.orgMoves, owners: OrgMoveIndex.equipmentOwners, personIds: ids,
                                                backCounts: back)
            jobs = OrgMoveNotices.jobs(from: all, now: Date())
        }
        let body = jobs.map { j -> String in
            j.key + "@" + String(Int(j.fireDate.timeIntervalSince1970)) + "|" + j.body + "|" + (j.moveId?.uuidString ?? "")
        }.joined(separator: "\n")
        let signature = (enabled ? "on\n" : "off\n") + body
        if signature == lastSignature { return }

        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        // 先清掉上一輪排的全部交接提醒：改了生效日、取消、套用好了、分好了的，殘留的舊通知會在不對的時間響
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(OrgMoveNotices.prefix) }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }
        if !enabled {
            // 關了：通知中心裡已經送達的也拿掉（家人那支、借人看的手機上不留）
            let delivered = await center.deliveredNotifications()
            let shown = delivered.map { $0.request.identifier }.filter { $0.hasPrefix(OrgMoveNotices.prefix) }
            if !shown.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: shown)
            }
        }
        guard !jobs.isEmpty else {
            lastSignature = signature
            return
        }
        // 授權照 MeetingReminders 的慣例：有要排的才問（沒問過才會跳）
        guard await NotificationManager.shared.requestAuthorization() else { return }

        let cal = OrgMovePlan.calendar
        for job in jobs where job.fireDate > Date() {
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: job.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let content = UNMutableNotificationContent()
            content.title = job.title
            content.body = job.body
            content.sound = .default
            content.threadIdentifier = OrgMoveNotices.threadId
            content.userInfo = [OrgMoveNotices.userInfoKey: job.moveId?.uuidString ?? ""]
            let req = UNNotificationRequest(identifier: job.key, content: content, trigger: trigger)
            try? await center.add(req)
        }
        lastSignature = signature
    }
}

// MARK: - 點通知（AppDelegate → 部屬總覽 → 那張交接單）

/// 點交接提醒：切到人生 › 職涯 › 部屬總覽，總覽取走後打開那張交接單。
/// 存 UUID token 不存 Bool：停在部屬總覽再點一次也會換值、onChange 收得到（同 DeepLinkRouter.pendingBirthdays）。
/// 不在 class 層級加 @MainActor（同 DeepLinkRouter 的理由：View 裡 @ObservedObject 拿 shared 才編得過）；呼叫點都在主執行緒
final class OrgMoveNoticeRouter: ObservableObject {
    static let shared = OrgMoveNoticeRouter()
    private init() {}

    /// 每點一次換一個（部屬總覽 onChange 收）
    @Published private(set) var token: UUID?
    /// 要開的那一張（nil＝停在部屬總覽）
    private var moveId: UUID?

    /// AppDelegate 叫（Task { @MainActor in … } 裡）：raw＝userInfo[OrgMoveNotices.userInfoKey]
    func open(_ raw: String) {
        AppNavigation.goToSubordinateOverview()
        DeepLinkRouter.shared.markRoute()
        moveId = UUID(uuidString: raw)
        token = UUID()
    }

    /// 部屬總覽取走：回傳要開的那一張（沒有請求、或只要停在總覽＝nil）；取走就清掉
    func take() -> UUID? {
        guard token != nil else { return nil }
        let id = moveId
        moveId = nil
        token = nil
        return id
    }
}

/// 部屬總覽收「打開這張交接單」的兩個時機：冷啟動時通知比這一頁先到（onAppear）、已經停在部屬總覽時再點一次（onChange）
private struct OrgMoveNoticeReceiver: ViewModifier {
    @ObservedObject private var router = OrgMoveNoticeRouter.shared
    let action: (UUID) -> Void

    init(action: @escaping (UUID) -> Void) {
        self.action = action
    }

    func body(content: Content) -> some View {
        content
            .onAppear { fire() }
            .onChange(of: router.token) { _, _ in fire() }
    }

    private func fire() {
        guard router.token != nil else { return }
        if let id = router.take() { action(id) }
    }
}

extension View {
    /// [v25.596 轉組織 v3] 部屬總覽：點了交接提醒、而且只有一張時呼叫 action（那張交接單的 id；呼叫端自己確認還在）
    func onOrgMoveNotice(_ action: @escaping (UUID) -> Void) -> some View {
        modifier(OrgMoveNoticeReceiver(action: action))
    }
}

// MARK: - 自動套用時沒動的 Apple 提醒事項（只這台）

/// 一張交接單自動套用時沒動的 Apple 提醒事項（OrgMoveReminderLater 存的一筆）
struct OrgMoveReminderLaterEntry: Codable, Equatable {
    /// 要刪的提醒事項 id（收回的分身、不要了的那幾則）
    var deletes: [String]
    /// 「今天生效」上〔更新提醒事項（4 件）〕的件數（交出去、不要了、結案的那幾件有提醒事項的）
    var count: Int
    var at: Date?

    init(deletes: [String] = [], count: Int = 0, at: Date? = nil) {
        self.deletes = deletes
        self.count = count
        self.at = at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deletes = (try? c.decodeIfPresent([String].self, forKey: .deletes)) ?? []
        count = (try? c.decodeIfPresent(Int.self, forKey: .count)) ?? 0
        at = try? c.decodeIfPresent(Date.self, forKey: .at)
    }

    private enum CodingKeys: String, CodingKey {
        case deletes, count, at
    }
}

/// 〔11/1 一起做〕到期自動套用時沒動的 Apple 提醒事項：照交接單 id 存在這台（UserDefaults.standard；不同步、不進備份、
/// 「清除全部資料」一起清）。LifeStore.applyDueOrgMoves(auto: true) 記、syncOrgMoveReminders 取走
enum OrgMoveReminderLater {
    static let key = "orgmove_reminders_later_v1"

    static func all() -> [String: OrgMoveReminderLaterEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let d = try? JSONDecoder().decode([String: OrgMoveReminderLaterEntry].self, from: data) else { return [:] }
        return d
    }

    static func entry(_ moveId: UUID) -> OrgMoveReminderLaterEntry? {
        all()[moveId.uuidString]
    }

    /// 記下（同一張已經有的：刪的併起來、件數取大的）
    static func add(_ moveId: UUID, deletes: [String], count: Int, now: Date) {
        var d = all()
        var e = d[moveId.uuidString] ?? OrgMoveReminderLaterEntry()
        for rid in deletes where !e.deletes.contains(rid) { e.deletes.append(rid) }
        e.count = max(e.count, count)
        e.at = now
        d[moveId.uuidString] = e
        write(d)
    }

    static func remove(_ moveId: UUID) {
        var d = all()
        guard d[moveId.uuidString] != nil else { return }
        d[moveId.uuidString] = nil
        write(d)
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func write(_ d: [String: OrgMoveReminderLaterEntry]) {
        if d.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(d) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
