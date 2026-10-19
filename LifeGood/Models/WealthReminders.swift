import Foundation
import Combine
import UserNotifications

// MARK: - 財富的日子與提醒（v25.565，財富 v4；wealth/judge.md §6.5、§6.6、§7.1；build/v4/brief.md §2）
//
// 兩件事，都只讀財富的一套數字（WealthFacts：Card.dues、settlements、Card.expiryMonth；sim_v4.py 照這裡寫過、跑過）：
//
// 1. WealthDates：我的行事曆、「今天」小工具的財富日子——
//    • 繳款截止日（自己繳的卡橘色、自動扣的灰色；每張卡只放接下來 2 期，金額是 0 的那期不放）
//    • 交割日（買＝從交割銀行扣、賣＝入帳）
//    • 卡片到期（有效期限那個月的 1 號）
//    結帳日不放。開戶日不在這裡（行事曆那筆財富里程碑照舊列，分類寫「財富」：WealthDates.isWealthAccount）。
//    **不送 Apple 行事曆**：AppleCalendarBridge 只寫你的個人行事曆事件與生日，財富的日子不是 PersonalEvent，寫不過去
//    （judge §6.6：跟著 Apple ID 到處出現）。
//    字：我的行事曆在 App 裡，可以有金額（「自己繳・NT$18,600」）；「今天」小工具主畫面寫卡名不寫金額（「CUBE 卡費截止」）；
//    鎖定畫面／StandBy 只寫類別字（「卡費」「交割」「卡片到期」，judge §7.1）。
//
// 2. WealthReminders：本機通知（identifier 前綴 "wealth."；最多 10 則、近的先排；iOS 一個 App 最多 64 則待發，
//    部屬會議用 20，judge §9-11）：
//    • 自己繳／每次問我的卡：截止前 3 天、當天 09:00；標成已繳那一期就不在 dues 裡，重排時移掉（當天那則不會來）
//    • 自動扣的卡：只在扣款帳戶 30 天內可能不夠扣（Account.shortage 在截止日或更早）時，扣款前 3 天 09:00
//    • 交割：只在交割帳戶那天可能不夠扣時，前一天 20:00
//    • 卡片效期：那個月 1 號往前 30 天 09:00
//    字一律**不寫卡名、金額、末四碼、帳號**（鎖定畫面、通知中心看得到；使用者的規則＋judge §7.1）：「卡費 10/27 截止（3 天後）」。
//    點了開那張卡／那個帳戶（userInfo[DeepLinkRouter.wealthNotificationKey]＝UUID 字串，LifeGoodApp 的 AppDelegate 接）。
//    開關：設定 › 會議提醒那一塊「財富提醒」（WealthReminders.enabledKey，沒設定過＝開）；每張卡 WealthCardPrefs.remind == false 不提醒。
//    授權照 MeetingReminders 的慣例：有要排的才叫 NotificationManager.requestAuthorization()（沒問過才會跳）。
//
// 什麼時候重排（WealthReminderCenter）：start 之後，記帳／理財／人生一改（防抖 3 秒）、回到前景、設定開關一動；
// 這次要排的跟上次一模一樣就不動系統（不打擾、不耗電）。

// MARK: - 1. 財富的日子

/// 我的行事曆、今天小工具的一件財富的事
struct WealthDateItem: Identifiable, Equatable {
    enum Kind: String {
        case cardDue, settlement, cardExpiry
    }

    /// 「wd-due-<卡>-<2026-10>」「wd-settle-<帳戶>-<2026-10-21>-NT$」「wd-expiry-<卡>-<2027-03>」
    let id: String
    /// 那天 00:00
    let day: Date
    let kind: Kind
    /// 我的行事曆標題：「CUBE 卡費」「元大證券 交割」「CUBE 卡片到期」
    let title: String
    /// 我的行事曆那一行灰字（App 裡，可以有金額）：「自己繳・NT$18,600」「從薪轉扣・NT$52,340」「換新卡後記得改綁定的扣款」
    let detail: String
    /// 「今天」小工具主畫面（不寫金額）：「CUBE 卡費截止」「@GoGo 卡費扣款」「元大證券 交割」
    let widgetTitle: String
    /// 鎖定畫面／StandBy 的類別字（不寫卡名）：「卡費」「交割」「卡片到期」
    let lockTitle: String
    /// SF Symbol（iOS 18 都有）
    let icon: String
    /// 點了開哪一張卡／哪一個帳戶（WealthCardPage）
    let accountId: UUID
    /// 自己繳的卡（行事曆畫橘色；其他灰）
    let isManual: Bool
}

enum WealthDates {
    /// 每張卡放接下來幾期
    static let duesPerCard = 2

    /// 今天起的財富日子（照日子、同一天照標題；sim_v4.py wealth_dates）
    static func all(facts: WealthFacts) -> [WealthDateItem] {
        let today = facts.today
        var out: [WealthDateItem] = []
        // 繳款截止日：每張卡接下來 2 期（已結帳還沒繳的、這一期、下一期；金額 0 的不在 dues 裡）
        for c in facts.cards {
            var shown = 0
            for d in c.dues where d.status == .due || d.status == .unbilled {
                let day = WealthCal.day(d.due)
                guard day >= today else { continue }
                if shown >= duesPerCard { break }
                shown += 1
                let widgetTitle: String = c.name + (d.isManual ? " 卡費截止" : " 卡費扣款")
                out.append(WealthDateItem(id: "wd-due-\(c.id.uuidString)-\(d.key)", day: day, kind: .cardDue,
                                          title: c.name + " 卡費", detail: d.modeText + "・" + d.amountText,
                                          widgetTitle: widgetTitle, lockTitle: "卡費", icon: "creditcard.fill",
                                          accountId: c.id, isManual: d.isManual))
            }
        }
        // 交割日
        for s in facts.settlements {
            let day = WealthCal.day(s.day)
            guard day >= today else { continue }
            out.append(WealthDateItem(id: "wd-settle-" + s.id, day: day, kind: .settlement,
                                      title: s.title, detail: s.directionText + "・" + s.amountText,
                                      widgetTitle: s.title, lockTitle: "交割", icon: "arrow.left.arrow.right",
                                      accountId: s.accountId, isManual: false))
        }
        // 卡片到期（那個月 1 號；這個月以前的不放）
        let thisMonth = WealthCal.startOfMonth(today)
        for c in facts.cards where !c.isDisabled {
            guard let em = c.expiryMonth, em >= thisMonth else { continue }
            out.append(WealthDateItem(id: "wd-expiry-\(c.id.uuidString)-\(WealthCal.monthKey(em))", day: em,
                                      kind: .cardExpiry, title: c.name + " 卡片到期", detail: "換新卡後記得改綁定的扣款",
                                      widgetTitle: c.name + " 卡片到期", lockTitle: "卡片到期",
                                      icon: "calendar.badge.exclamationmark", accountId: c.id, isManual: false))
        }
        // 照日子；同一天照標題（sort 不保證穩定，帶著原本的位置比）
        return out.enumerated().sorted { x, y in
            if x.element.day != y.element.day { return x.element.day < y.element.day }
            if x.element.title != y.element.title { return x.element.title < y.element.title }
            return x.offset < y.offset
        }.map { $0.element }
    }

    /// 那一天的財富日子（我的行事曆 eventsOn、今天小工具 CalendarDayItems.allDay 用）
    static func items(on day: Date, facts: WealthFacts) -> [WealthDateItem] {
        let d = WealthCal.day(day)
        return all(facts: facts).filter { $0.day == d }
    }

    /// 財富帳戶的里程碑（銀行、信用卡、證券、保險；開戶日、核卡日）：行事曆分類寫「財富」不寫「成就」、點了開卡片頁
    static func isWealthAccount(_ m: LifeMilestone) -> Bool {
        m.category == .achievement && m.financeSubCategory != nil
    }
}

// MARK: - 2. 提醒

/// 一則要排的財富提醒（字已經組好；不含卡名、金額、號碼）
struct WealthReminderJob: Equatable {
    /// UNNotificationRequest.identifier：「wealth.due.<卡>.<2026-10>.3」「wealth.auto.<卡>.<2026-11>」
    /// 「wealth.settle.<帳戶>.<2026-10-21>」「wealth.expiry.<卡>.<2027-03>」
    let key: String
    let title: String
    let body: String
    let fireDate: Date
    /// 點了開哪一張卡／哪一個帳戶
    let accountId: UUID
}

enum WealthReminders {
    /// 重排時認得「哪些是財富排的」
    static let prefix = "wealth."
    /// 設定的「財富提醒」開關（UserDefaults；沒設定過＝開）
    static let enabledKey = "wealth_reminders_enabled"
    /// 最多幾則（judge §6.6：iOS 64 則待發，部屬會議已經用 20）
    static let limit = 10
    /// 通知中心疊成一組
    static let threadId = "wealth"

    static var isEnabled: Bool {
        // UserDefaults.bool 對不存在的 key 回 false；沒設定過要當開
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// 要排的提醒（近的先排、最多 10 則；sim_v4.py reminder_jobs 照這裡寫）。純計算：不碰通知中心
    static func jobs(facts: WealthFacts, book: WealthBook, now: Date) -> [WealthReminderJob] {
        var out: [WealthReminderJob] = []
        let accounts = Dictionary(facts.accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let paidHint = "繳完到財富頁按「標成已繳」，提醒就會取消。"

        // 卡費：自己繳的截止前 3 天、當天；自動扣的只在可能不夠扣時、扣款前 3 天
        for c in facts.cards where !c.isDisabled && book.card(c.id).remind != false {
            for d in c.dues where d.status == .due || d.status == .unbilled {
                let dueDay = WealthCal.day(d.due)
                let md = WealthFormat.monthDay(dueDay)
                if d.isManual {
                    let f3 = at(WealthCal.addDays(-3, to: dueDay), hour: 9)
                    let f0 = at(dueDay, hour: 9)
                    if f3 > now {
                        out.append(WealthReminderJob(key: prefix + "due.\(c.id.uuidString).\(d.key).3",
                                                     title: "卡費 \(md) 截止（3 天後）", body: paidHint,
                                                     fireDate: f3, accountId: c.id))
                    }
                    if f0 > now {
                        out.append(WealthReminderJob(key: prefix + "due.\(c.id.uuidString).\(d.key).0",
                                                     title: "卡費今天截止（\(md)）", body: paidHint,
                                                     fireDate: f0, accountId: c.id))
                    }
                } else {
                    guard let pid = d.payerId, let a = accounts[pid], let sh = a.shortage,
                          WealthCal.day(sh.date) <= dueDay else { continue }
                    let f = at(WealthCal.addDays(-3, to: dueDay), hour: 9)
                    if f > now {
                        out.append(WealthReminderJob(key: prefix + "auto.\(c.id.uuidString).\(d.key)",
                                                     title: "卡費 \(md) 自動扣款（3 天後）",
                                                     body: "扣款的帳戶可能不夠扣，打開看看。",
                                                     fireDate: f, accountId: c.id))
                    }
                }
            }
        }

        // 交割：只在那天可能不夠扣時，前一天 20:00
        for s in facts.settlements where s.isOutflow {
            guard let a = accounts[s.accountId], let sh = a.shortage,
                  WealthCal.day(sh.date) == WealthCal.day(s.day) else { continue }
            let f = at(WealthCal.addDays(-1, to: s.day), hour: 20)
            if f > now {
                out.append(WealthReminderJob(key: prefix + "settle.\(s.accountId.uuidString).\(WealthCal.dayKey(s.day))",
                                             title: "明天 \(WealthFormat.monthDay(s.day)) 交割",
                                             body: "交割的帳戶可能不夠扣，打開看看。",
                                             fireDate: f, accountId: s.accountId))
            }
        }

        // 卡片效期：那個月 1 號往前 30 天
        for c in facts.cards where !c.isDisabled && book.card(c.id).remind != false {
            guard let em = c.expiryMonth else { continue }
            let f = at(WealthCal.addDays(-30, to: em), hour: 9)
            if f > now {
                out.append(WealthReminderJob(key: prefix + "expiry.\(c.id.uuidString).\(WealthCal.monthKey(em))",
                                             title: "有一張卡快到期",
                                             body: "\(WealthCal.month(em)) 月到期，換新卡後記得改綁定的扣款與卡片資料。",
                                             fireDate: f, accountId: c.id))
            }
        }

        // 近的先排（同一個時間照產生的先後；sort 不保證穩定，帶著位置比）
        let ordered: [WealthReminderJob] = out.enumerated().sorted { x, y in
            if x.element.fireDate != y.element.fireDate { return x.element.fireDate < y.element.fireDate }
            return x.offset < y.offset
        }.map { $0.element }
        return Array(ordered.prefix(limit))
    }

    /// 那天幾點整（西曆、手機時區）
    private static func at(_ day: Date, hour: Int) -> Date {
        WealthCal.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: WealthCal.day(day)) ?? day
    }
}

// MARK: - 排程（主 App）

/// 把 WealthReminders.jobs 排成本機通知。LifeGoodApp 啟動時 start 一次；回到前景、設定開關一動叫 rebuildSoon。
@MainActor
final class WealthReminderCenter {
    static let shared = WealthReminderCenter()

    private init() {}

    private var expenseStore: ExpenseStore?
    private var financeStore: FinanceStore?
    private var lifeStore: LifeStore?
    private var cancellables = Set<AnyCancellable>()
    private var started = false
    /// 上一次真的排進系統的（key＋時間＋字）；這次一樣就不動
    private var lastSignature: String?
    /// 正在排的那一輪（下一輪等它跑完再排，不會兩輪交錯）
    private var running: Task<Void, Never>?

    /// 啟動時呼叫一次（重複呼叫無害）：掛監聽（記帳、理財、人生一改，防抖 3 秒重排），然後馬上排一次
    func start(expense: ExpenseStore, finance: FinanceStore, life: LifeStore) {
        guard !started else { return }
        started = true
        expenseStore = expense
        financeStore = finance
        lifeStore = life
        expense.objectWillChange
            .merge(with: finance.objectWillChange)
            .merge(with: life.objectWillChange)
            .debounce(for: .seconds(3), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildSoon() }
            .store(in: &cancellables)
        rebuildSoon()
    }

    /// 回到前景、設定的「財富提醒」開關一動：重排（還沒 start 就什麼都不做）
    func rebuildSoon() {
        guard started else { return }
        let previous = running
        running = Task { @MainActor [weak self] in
            await previous?.value
            await self?.rebuild()
        }
    }

    private func rebuild() async {
        guard let expense = expenseStore, let finance = financeStore, let life = lifeStore else { return }
        var jobs: [WealthReminderJob] = []
        if WealthReminders.isEnabled {
            let facts = life.wealthFacts(expense: expense, finance: finance)
            jobs = WealthReminders.jobs(facts: facts, book: life.wealthBook, now: Date())
        }
        let signature = jobs.map { j -> String in
            j.key + "@" + String(Int(j.fireDate.timeIntervalSince1970)) + "|" + j.title + "|" + j.body
        }.joined(separator: "\n")
        if signature == lastSignature { return }

        let center = UNUserNotificationCenter.current()
        // 先清掉上一輪排的全部財富提醒：標成已繳、改了截止日、關掉提醒的，殘留的舊通知會在不對的時間響
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(WealthReminders.prefix) }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }
        guard !jobs.isEmpty else {
            lastSignature = signature
            return
        }
        guard await NotificationManager.shared.requestAuthorization() else { return }

        let cal = Calendar.current
        for job in jobs where job.fireDate > Date() {
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: job.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let content = UNMutableNotificationContent()
            content.title = job.title
            content.body = job.body
            content.sound = .default
            content.threadIdentifier = WealthReminders.threadId
            content.userInfo = [DeepLinkRouter.wealthNotificationKey: job.accountId.uuidString]
            let req = UNNotificationRequest(identifier: job.key, content: content, trigger: trigger)
            try? await center.add(req)
        }
        lastSignature = signature
    }
}
