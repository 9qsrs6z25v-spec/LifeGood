// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.645 mac5 G3] 記帳小鎮的狀態（judge_mac.md §S4-7、§S4-8）：從 MacMoneyStore 現有收支即時算；只存這台 Mac 的兩個本機鍵。
//
// • 本機鍵只准 "mac.game.enabled"（Bool，沒有＝開）與 "mac.game.state." ＋ 16 碼帳號雜湊（拼鍵前 isAccountHash 檢查）；
//   UserDefaults.standard、不用 @AppStorage、不上 iCloud、不進通知／小工具／App Group、不寫 log。只在 Combine sink、計時器、按鈕動作裡寫。
// • 不收 MacJournal、MacEditCenter；不碰任何同步鍵、mac.writeEnabled.*。
// • 算：money 的 $expenses、$incomes、$rates、$splitIndex、$accountHash、$hasFetchedThisLaunch、$showingCache＋回到前景
//   → .debounce(300ms, DispatchQueue.main) → recompute(now: Date())（@Published 在 willSet 發送，一定 debounce 之後才讀）。
// • 主控骨架：enabled（骨架永遠 false）、snapshot、toast、bounce、init(money:)、setEnabled(_:)、dismissToast() 簽名定案；G3 換內容。
// • recompute 逐行照 sim_mac5 Game.recompute（★3～★5）。
// • [v25.646 mac6 C0] init 多收 MacJournal（骨架不用；G3b 只讀 entries 的 kind == .add、key、at 與 accountHash）；
//   第二批的 @Published（calendarGrid、checkBounce）與動作（toggleNoSpend、dismissReview、openCalendar、stepCalendar）先放空殼（§T7-6）。
// • [v25.646 mac6 G3b] 第二批（§T6）：本機那份升 v2（noSpend 打卡字、lastReview 這週一的字；同一個鍵、不新增鍵）；
//   先讀本機那份再算（打卡要算進記帳日）；版本三分（沒有／壞＝第一次、v1＝就地遷移、v ≥ 3＝只看不寫）。
//   讀日誌只准 kind == .add、key、at 與 accountHash（第一次在電腦記帳那枚）；不碰分帳、不寫 log、沒有金額與名字。
//   打卡、回顧〔好〕只在按鈕動作裡寫；月曆只算不寫（翻到哪個月只在記憶體）。Mac 5 的 compute 留著對照（noSpend 空時 compute2 逐位一樣）。
// • [v25.648 mac7 C0] 第三批年度星路的 @Published（yearRoad）、記憶體（yearShown、yearInput）與動作（openYear、stepYear、refreshYear）
//   先放空殼（judge_mac.md §U5-4、§U7-2；只加）。G3 換內容並在 recompute 加三行；state、version()、dictionary 一字不動。

import SwiftUI
import Combine
import AppKit

/// 點亮時那一則（4 秒或點一下收掉）
struct MacGameToast: Equatable {
    let text: String
    /// 手寫英文：Level up!／Goal reached!
    let script: String
    /// 同一天第二次同樣的字也算新的一則（4 秒計時只收自己那一則）
    let id = UUID()
}

/// 遊戲列與 popover 要畫的東西（一個金額、一個名字都沒有；欄位 G3 可增減，名字與 static let empty 不准改）
struct MacGameSnapshot: Equatable {
    /// 有沒有開始記帳（S 存在）
    let started: Bool
    let level: Int
    let stageName: String
    let stageIcon: String
    /// 顯示的經驗值＝max(xp, maxXP)
    let xp: Int
    let floor: Int
    let next: Int
    let streakWeeks: Int
    let streakSince: Date?
    let lights: [MacGameLight]
    let current: MacGameMonth?
    /// 結算月（新到舊，最多 12 個給 popover）
    let settled: [MacGameMonth]
    /// 點亮的徽章 id → 點亮時間（timeIntervalSinceReferenceDate；0＝第一次打開補上的）
    let earned: [String: Double]
    /// [G3] 畫成點亮的徽章＝earned ∪ 現在成立的（快照、還沒抓完時只顯示、不寫）
    let lit: Set<String>
    /// 第一次打開那一行「以前記的帳也算進來了：已點亮 N 枚」（只在記憶體）
    let backfillNote: String?
    // [v25.646 mac6] 第二批（empty 用預設值）
    /// 〔今天沒花錢〕出不出現（可寫、今天能打卡）
    var canCheckToday: Bool = false
    /// 每週回顧卡（沒有＝不畫）
    var review: MacGameReview? = nil
    /// 自己的紀錄（徽章 popover）
    var records: MacGameRecords = .empty
    /// 比較新的版本存的：「這一版只看不改」
    var readOnlyNote: String? = nil

    static let empty = MacGameSnapshot(started: false, level: 0, stageName: "空地", stageIcon: "leaf.fill",
                                       xp: 0, floor: 0, next: 100, streakWeeks: 0, streakSince: nil, lights: [],
                                       current: nil, settled: [], earned: [:], lit: [], backfillNote: nil)
}

/// 本機那一份（mac.game.state.<雜湊>）：v、seen、earned、maxXP；沒有金額、名稱、備註、帳的 id
private struct MacGameStored {
    var seen: [String] = []
    var earned: [String: Double] = [:]
    var maxXP: Int = 0
    /// [v25.646 mac6] 打卡的日子字（"2026-11-26"；最多 1,000，舊的先丟）
    var noSpend: [String] = []
    /// [v25.646 mac6] 回顧〔好〕過的那週週一的字（沒有＝不放這個鍵）
    var lastReview: String? = nil

    init() {}

    // sim6: game#43（v2：noSpend 逐筆驗字、去重、排序；lastReview 看不懂＝沒有）
    init(_ d: [String: Any]) {
        seen = d["seen"] as? [String] ?? []
        earned = d["earned"] as? [String: Double] ?? [:]
        maxXP = d["maxXP"] as? Int ?? 0
        let days: [String] = (d["noSpend"] as? [Any] ?? []).compactMap { x in x as? String }
        noSpend = MacGameDays.cleanNoSpend(days, calendar: MacGameRules.calendar)
        if let r = d["lastReview"] as? String, MacGameDays.day(r, calendar: MacGameRules.calendar) != nil {
            lastReview = r
        }
    }

    // sim6: game#43（寫回一律 v＝2；lastReview 沒有就不放（plist 不收 nil））
    var dictionary: [String: Any] {
        var out: [String: Any] = ["v": 2, "seen": seen, "earned": earned, "maxXP": maxXP, "noSpend": noSpend]
        if let r = lastReview {
            out["lastReview"] = r
        }
        return out
    }

    /// 版本三分：沒有／v 讀不到／v < 1＝第一次；v＝1＝Mac 5 寫的（就地遷移）；v ≥ 3＝比這版新（只看不寫）
    // sim6: game#43
    static func version(_ raw: [String: Any]?) -> (fresh: Bool, legacy: Bool, newer: Bool) {
        let v = raw?["v"] as? Int
        let fresh = raw == nil || v == nil || (v ?? 0) < 1
        return (fresh, v == 1, (v ?? 0) > 2)
    }
}

/// 一次算好的量（只在記憶體）
private struct MacGameFacts {
    let first: Date?
    let weekCount: Int
    let streak: (weeks: Int, since: Date?)
    let lights: [MacGameLight]
    /// 結算月（舊到新）
    let months: [MacGameMonth]
    let current: MacGameMonth?
    let stars: Int
    let badges: Set<String>
    // [v25.646 mac6] 第二批（compute2 填；Mac 5 的 compute 用預設值）
    var days: MacGameDayFacts = .empty
    var firstAdd: Date? = nil
    var records: MacGameRecords = .empty
    var recordHits: [MacGameRecordHit] = []
}

@MainActor
final class MacGameModel: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var snapshot: MacGameSnapshot = .empty
    @Published private(set) var toast: MacGameToast? = nil
    /// 點亮時 +1（symbolEffect(.bounce, value:) 用）
    @Published private(set) var bounce: Int = 0
    /// [v25.646 mac6] 記帳月曆（開著才有值；openCalendar／stepCalendar 只算不寫）
    @Published private(set) var calendarGrid: MacGameCalendarGrid? = nil
    /// [v25.646 mac6] 按了〔今天沒花錢〕+1（那盞燈 symbolEffect(.bounce, value:) 用）
    @Published private(set) var checkBounce: Int = 0
    /// [v25.648 mac7] 年度星路（開著才有值；openYear／stepYear 只算不寫）
    @Published private(set) var yearRoad: MacGameYearRoad? = nil

    private let money: MacMoneyStore
    private var bag: Set<AnyCancellable> = []
    /// 從關掉打開：下一次可寫狀態靜默補上（不慶祝）
    private var justEnabled = false
    /// 第一次打開那行字（記憶體，這次開 App 才顯示）
    private var backfillNote: String? = nil
    /// 那行字是哪個帳號的（換帳號就清掉，不把上一個帳號的徽章數帶過去）
    private var noteHash: String? = nil
    /// 一天最多跳一次（記憶體，不存；★5）
    private var lastBounceDay: Date? = nil
    /// 上次算的那天 00:00（計時器跨午夜才重算）
    private var lastDay: Date? = nil
    /// [v25.646 mac6] 只讀：kind == .add、key、at、accountHash（第一次在電腦記帳）
    private let journal: MacJournal
    /// 月曆翻到哪個月（記憶體，不存；nil＝月曆沒開）
    private var calendarMonth: Date? = nil
    /// 上一次算的日子、打卡、可不可寫、連續週數（月曆與打卡用；記憶體）
    private var dayFacts: MacGameDayFacts = .empty
    private var dayNoSpend: Set<String> = []
    private var dayWritable = false
    private var dayStreakWeeks = 0
    private var dayStreakSince: Date? = nil
    /// 這次可以慶祝的紀錄（celebrate 用完清空）
    private var pendingRecords: [MacGameRecordHit] = []
    /// [v25.648 mac7] 星路翻到哪一年（記憶體，不存；nil＝星路沒開）
    private var yearShown: Int? = nil
    /// [v25.648 mac7] 上一次算的星路輸入（recompute 填；記憶體，不存）
    private var yearInput: MacGameYearInput = .empty

    // sim5: game#21（什麼時候算：money 七個 @Published＋回到前景 → debounce 300ms → recompute；60 秒計時器跨午夜才算；不在 body、.task 裡算或寫）
    init(money: MacMoneyStore, journal: MacJournal) {
        self.enabled = UserDefaults.standard.object(forKey: "mac.game.enabled") as? Bool ?? true
        self.money = money
        self.journal = journal
        // 七個 @Published＋回到前景都戳同一個 poke（訂閱當下各送一次現值 → debounce 後只算一次）；
        // 不用 AnyPublisher／Publishers.MergeMany（macsymbols 白名單只有 PassthroughSubject），意思一樣
        let poke = PassthroughSubject<Void, Never>()
        money.$expenses.sink { _ in poke.send(()) }.store(in: &bag)
        money.$incomes.sink { _ in poke.send(()) }.store(in: &bag)
        money.$rates.sink { _ in poke.send(()) }.store(in: &bag)
        money.$splitIndex.sink { _ in poke.send(()) }.store(in: &bag)
        money.$accountHash.sink { _ in poke.send(()) }.store(in: &bag)
        money.$hasFetchedThisLaunch.sink { _ in poke.send(()) }.store(in: &bag)
        money.$showingCache.sink { _ in poke.send(()) }.store(in: &bag)
        // sim6: game#39（日誌換了、換帳號了也重算；@Published 在 willSet 發送 → debounce 之後才讀）
        journal.$entries.sink { _ in poke.send(()) }.store(in: &bag)
        journal.$accountHash.sink { _ in poke.send(()) }.store(in: &bag)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { _ in poke.send(()) }
            .store(in: &bag)
        poke
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.recompute(now: Date()) }
            .store(in: &bag)
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
            .store(in: &bag)
    }

    /// 選單「顯示 › 遊戲元素」、popover〔關掉遊戲元素〕
    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "mac.game.enabled")
        let was = enabled
        enabled = on
        if !on {
            toast = nil
            calendarMonth = nil
            calendarGrid = nil
            return
        }
        if !was {
            justEnabled = true
            recompute(now: Date())
        }
    }

    /// 點一下點亮膠囊
    func dismissToast() {
        toast = nil
    }

    // MARK: [v25.646 mac6] 第二批的動作（主控骨架：什麼都不做；G3b 換內容，第一行 guard）

    /// 〔今天沒花錢〕、月曆格子補按／取消（day＝那天 00:00）
    func toggleNoSpend(_ day: Date) {
        guard enabled, let h = money.accountHash, Self.isAccountHash(h) else { return }
        // sim6: game#27（按鈕動作：先算一次（狀態升 v2、日子最新）→ 重讀 → 能取消就取消、能打卡就加 → 寫 → 再算；
        //               不寫 log、金額、帳的 id；快照、還沒抓完、比較新的版本都不寫）
        recompute(now: Date())
        guard dayWritable else { return }
        let cal = MacGameRules.calendar
        let key = "mac.game.state." + h
        guard let raw = UserDefaults.standard.dictionary(forKey: key), !MacGameStored.version(raw).newer else { return }
        var state = MacGameStored(raw)
        let d = cal.startOfDay(for: day)
        let k = MacGameDays.dayKey(d, calendar: cal)
        let stored = Set(state.noSpend)
        if MacGameDays.canUncheck(d, facts: dayFacts, noSpend: stored, writable: true, calendar: cal) {
            state.noSpend.removeAll { x in x == k }
        } else if MacGameDays.canCheck(d, facts: dayFacts, noSpend: stored, writable: true, calendar: cal) {
            state.noSpend = MacGameDays.cleanNoSpend(state.noSpend + [k], calendar: cal)
            if d == dayFacts.today {
                checkBounce += 1
            }
        } else {
            return
        }
        UserDefaults.standard.set(state.dictionary, forKey: key)
        recompute(now: Date())
    }

    /// 每週回顧〔好〕
    func dismissReview() {
        guard enabled, let h = money.accountHash, Self.isAccountHash(h) else { return }
        // sim6: game#35（〔好〕：可寫才寫 lastReview＝這週一的字；同一週不再出現，下週一又有新的）
        recompute(now: Date())
        guard dayWritable else { return }
        let cal = MacGameRules.calendar
        let key = "mac.game.state." + h
        guard let raw = UserDefaults.standard.dictionary(forKey: key), !MacGameStored.version(raw).newer else { return }
        var state = MacGameStored(raw)
        state.lastReview = MacGameDays.dayKey(MacGameRules.weekStart(of: Date(), calendar: cal), calendar: cal)
        UserDefaults.standard.set(state.dictionary, forKey: key)
        recompute(now: Date())
    }

    /// 打開記帳月曆（只算不寫）
    // sim6: game#31（打開＝這個月；翻月夾在開始記帳那個月～這個月，最多往回 120 個月；只算不寫）
    func openCalendar() {
        calendarMonth = MacGameDays.monthStart(Date(), calendar: MacGameRules.calendar)
        refreshCalendar(now: Date())
    }

    /// 月曆翻月（n＝-1 上個月、1 下個月；只算不寫）
    func stepCalendar(_ n: Int) {
        guard let m = calendarMonth else { return }
        calendarMonth = MacGameDays.stepMonth(m, by: n, start: dayFacts.start, now: Date(), calendar: MacGameRules.calendar)
        refreshCalendar(now: Date())
    }

    /// 月曆開著才算（recompute 結尾、打開、翻月）
    private func refreshCalendar(now: Date) {
        guard let m = calendarMonth else { return }
        calendarGrid = MacGameDays.monthGrid(month: m, facts: dayFacts, noSpend: dayNoSpend, writable: dayWritable,
                                             streakWeeks: dayStreakWeeks, streakSince: dayStreakSince, now: now,
                                             calendar: MacGameRules.calendar)
    }

    // MARK: [v25.648 mac7] 年度星路（主控骨架：什麼都不做；G3 換內容，只算不寫）

    /// 打開年度星路（只算不寫）
    // sim7: game#61
    func openYear() {
    }

    /// 星路翻年（n＝-1 前一年、1 後一年；只算不寫）
    func stepYear(_ n: Int) {
    }

    /// 星路開著才算（recompute 結尾、打開、翻年）
    private func refreshYear(now: Date) {
    }

    /// 16 碼小寫十六進位（MacMoneyStore.hashAccount 的樣子）；不是這個樣子不拼鍵、不刪
    static func isAccountHash(_ s: String) -> Bool {
        s.count == 16 && s.allSatisfy { c in "0123456789abcdef".contains(c) }
    }

    // MARK: - 算

    private func tick() {
        let day = MacGameRules.calendar.startOfDay(for: Date())
        guard day != lastDay else { return }
        recompute(now: Date())
    }

    private func recompute(now: Date) {
        guard enabled else { return }
        let cal = MacGameRules.calendar
        lastDay = cal.startOfDay(for: now)
        guard let h = money.accountHash, Self.isAccountHash(h) else {
            snapshot = .empty
            dayWritable = false
            return
        }
        if h != noteHash {
            backfillNote = nil
            noteHash = h
        }
        let key = "mac.game.state." + h
        // sim6: game#43（先讀本機那份再算：打卡要算進記帳日；版本三分 fresh／legacy／newer）
        let raw = UserDefaults.standard.dictionary(forKey: key)
        let ver = MacGameStored.version(raw)
        let fresh = ver.fresh
        var state = fresh ? MacGameStored() : MacGameStored(raw ?? [:])
        let facts = compute2(now: now, calendar: cal, noSpend: state.noSpend)
        var lit = Set(state.earned.keys).union(facts.badges)
        let xp = MacGameRules.xp(weeks: facts.weekCount, stars: facts.stars, badges: lit.count)
        let shown = max(xp, state.maxXP)
        let lv = MacGameRules.level(xp: shown).level
        // sim6: game#45（比較新的版本存的：照算照畫、一個欄位都不寫、不刪別的帳號那份、打卡鈕與〔好〕不出現）
        let writable = isWritable(h) && !ver.newer
        if writable {
            removeOtherStates(keep: key)
            if fresh || justEnabled {
                backfill(&state, facts: facts, level: lv, fresh: fresh)
                // sim6: game#46（第一次：lastReview＝這週一，這週不出回顧卡）
                if fresh {
                    state.lastReview = MacGameDays.dayKey(MacGameRules.weekStart(of: now, calendar: cal), calendar: cal)
                }
            } else {
                if ver.legacy {
                    migrate(&state, facts: facts, level: lv)
                }
                // ★4：earned 在可寫狀態第一次看到成立就寫（不管前景）
                for b in MacGameBadge.all where facts.badges.contains(b.id) && state.earned[b.id] == nil {
                    state.earned[b.id] = earnedTime(b.id, facts: facts, now: now)
                }
                if NSApplication.shared.isActive {
                    pendingRecords = facts.recordHits
                    celebrate(&state, level: lv, now: now, calendar: cal)
                }
            }
            state.maxXP = max(state.maxXP, xp)
            trim(&state)
            // sim6: game#49（只寫 mac.game.state.<合法雜湊>：沒有金額、名稱、帳的 id；不碰同步鍵、mac.writeEnabled.*、日誌）
            UserDefaults.standard.set(state.dictionary, forKey: key)
            lit = Set(state.earned.keys).union(facts.badges)
        }
        snapshot = makeSnapshot2(facts, state: state, lit: lit, shown: shown, writable: writable, newer: ver.newer, now: now)
        dayFacts = facts.days
        dayNoSpend = Set(state.noSpend)
        dayWritable = writable
        dayStreakWeeks = facts.streak.weeks
        dayStreakSince = facts.streak.since
        refreshCalendar(now: now)
    }

    // sim5: game#22（可寫狀態＝enabled && account == .available && 這次開 App 抓過 && 不是快照 && 帳號雜湊合法）
    private func isWritable(_ h: String) -> Bool {
        enabled && money.account == .available && money.hasFetchedThisLaunch && !money.showingCache && Self.isAccountHash(h)
    }

    /// 換帳號：別的合法雜湊那份刪掉；後綴不合法的不動（不是我們寫的不刪）；mac.game.enabled 不動（★3）
    private func removeOtherStates(keep key: String) {
        let prefix = "mac.game.state."
        for k in UserDefaults.standard.dictionaryRepresentation().keys where k.hasPrefix(prefix) && k != key {
            let suffix = String(k.dropFirst(prefix.count))
            if Self.isAccountHash(suffix) {
                UserDefaults.standard.removeObject(forKey: k)
            }
        }
    }

    // sim5: game#23（第一次／v ≠ 1／從關掉打開：現在成立的徽章 earned＝0、seen 放等級＋徽章、不慶祝；第一次才寫那行字）
    private func backfill(_ state: inout MacGameStored, facts: MacGameFacts, level lv: Int, fresh: Bool) {
        for id in facts.badges.sorted() where state.earned[id] == nil {
            state.earned[id] = 0
        }
        let seen = Set(state.seen)
        var add: [String] = ["level.\(lv)"]
        for b in MacGameBadge.all where state.earned[b.id] != nil {
            add.append(b.id)
        }
        // sim6: game#46（[v25.646 mac6] 現在成立的紀錄也算看過，不慶祝）
        add += facts.recordHits.map { r in r.id }
        state.seen += add.filter { !seen.contains($0) }
        let n = state.earned.count
        if fresh && n > 0 {
            backfillNote = MacGameText.backfill(n)
        }
        justEnabled = false
    }

    // sim5: game#24（慶祝：前景才做；新等級 > seen 最大的 level.N，或 earned 有、seen 沒有的徽章 → 一則；一天最多跳一次）
    private func celebrate(_ state: inout MacGameStored, level lv: Int, now: Date, calendar cal: Calendar) {
        let seen = Set(state.seen)
        let seenLevel = seen.compactMap { s -> Int? in s.hasPrefix("level.") ? Int(s.dropFirst(6)) : nil }.max() ?? -1
        let newLevel: Int? = lv > seenLevel ? lv : nil
        let newBadges: [String] = MacGameBadge.all.map { $0.id }.filter { id in
            state.earned[id] != nil && !seen.contains(id)
        }
        // sim6: game#37（[v25.646 mac6] 還沒看過的破紀錄併進同一則；一段只跳一次）
        let newRecords = pendingRecords.filter { r in !seen.contains(r.id) }
        pendingRecords = []
        if !newRecords.isEmpty {
            celebrateRecords(&state, newLevel: newLevel, newBadges: newBadges, records: newRecords, now: now, calendar: cal)
            return
        }
        guard let t = MacGameText.toast(newLevel: newLevel, newBadges: newBadges) else { return }
        if let n = newLevel {
            state.seen.append("level.\(n)")
        }
        state.seen += newBadges
        show(MacGameToast(text: t.text, script: t.script))
        let today = cal.startOfDay(for: now)
        if lastBounceDay != today {
            bounce += 1
            lastBounceDay = today
        }
    }

    /// seen 最多 200（舊的先丟）、earned 最多 50（留最新的）
    private func trim(_ state: inout MacGameStored) {
        if state.seen.count > 200 {
            state.seen = Array(state.seen.suffix(200))
        }
        if state.earned.count > 50 {
            let keep = state.earned.sorted { a, b in a.value < b.value }.suffix(50)
            var out: [String: Double] = [:]
            for kv in keep { out[kv.key] = kv.value }
            state.earned = out
        }
        // sim6: game#28（[v25.646 mac6] 打卡最多 1,000 個，舊的先丟）
        if state.noSpend.count > MacGameDays.noSpendLimit {
            state.noSpend = Array(state.noSpend.suffix(MacGameDays.noSpendLimit))
        }
    }

    /// 膠囊直接出現；4 秒後收（還是同一則才收；MacEditor.swift:1440-1444 寫法）
    private func show(_ t: MacGameToast) {
        toast = t
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, self.toast == t else { return }
            self.toast = nil
        }
    }

    private func compute(now: Date, calendar cal: Calendar) -> MacGameFacts {
        let variableDates: [Date] = money.expenses.filter { $0.expenseType == .variable }.map { $0.date }
        let onceDates: [Date] = money.incomes.filter { $0.period == .once }.map { $0.date }
        let days = MacGameRules.recordDays(variableDates: variableDates, onceIncomeDates: onceDates, now: now, calendar: cal)
        // sim5: game#2（開始記帳那天 S＝記帳日最早那天；沒有＝還沒開始）
        let first: Date? = days.min()
        var weeks = Set<Date>()
        for d in days {
            weeks.insert(MacGameRules.weekStart(of: d, calendar: cal))
        }
        var variableDays = Set<Date>()
        for d in variableDates {
            variableDays.insert(cal.startOfDay(for: d))
        }
        let lights = MacGameRules.weekLights(recordDays: days, variableDays: variableDays, start: first, now: now, calendar: cal)
        var months: [MacGameMonth] = []
        for m in MacGameRules.settledMonthStarts(firstDay: first, now: now, calendar: cal) {
            months.append(monthStars(m, days: days, first: first, now: now, calendar: cal))
        }
        var current: MacGameMonth? = nil
        if first != nil, let cur = cal.date(from: cal.dateComponents([.year, .month], from: now)) {
            current = monthStars(cur, days: days, first: first, now: now, calendar: cal)
        }
        let stars = months.reduce(0) { $0 + $1.settledStars }
        let longest = MacGameRules.longestStreak(weeks, calendar: cal)
        return MacGameFacts(first: first, weekCount: weeks.count, streak: MacGameRules.streak(weeks, now: now, calendar: cal),
                            lights: lights, months: months, current: current, stars: stars,
                            badges: MacGameRules.badges(longest: longest, months: months))
    }

    private func monthStars(_ start: Date, days: Set<Date>, first: Date?, now: Date, calendar cal: Calendar) -> MacGameMonth {
        let end = cal.date(byAdding: .month, value: 1, to: start) ?? start
        let ledger = MacGameRules.monthLedger(money: money, start: start, end: end, now: now, calendar: cal)
        return MacGameRules.month(ledger, days: days, firstDay: first, now: now, calendar: cal)
    }

    private func makeSnapshot(_ f: MacGameFacts, state: MacGameStored, lit: Set<String>, shown: Int) -> MacGameSnapshot {
        let lv = MacGameRules.level(xp: shown)
        let st = MacGameRules.stage(lv.level)
        return MacGameSnapshot(started: f.first != nil, level: lv.level, stageName: st.name, stageIcon: st.icon,
                               xp: shown, floor: lv.floor, next: lv.next, streakWeeks: f.streak.weeks,
                               streakSince: f.streak.since, lights: f.lights, current: f.current,
                               settled: Array(f.months.reversed().prefix(12)), earned: state.earned, lit: lit,
                               backfillNote: backfillNote)
    }

    // MARK: - [v25.646 mac6] 第二批

    // sim6: game#25（記帳日 R＝資料 ∪ 有效打卡；W、★1、經驗值都吃 R；S 只看資料；公式不改）
    private func compute2(now: Date, calendar cal: Calendar, noSpend: [String]) -> MacGameFacts {
        let variableDates: [Date] = money.expenses.filter { $0.expenseType == .variable }.map { $0.date }
        let onceDates: [Date] = money.incomes.filter { $0.period == .once }.map { $0.date }
        let d = MacGameDays.facts(variableDates: variableDates, onceIncomeDates: onceDates, noSpend: noSpend, now: now,
                                  calendar: cal)
        let first = d.start
        var months: [MacGameMonth] = []
        for m in MacGameRules.settledMonthStarts(firstDay: first, now: now, calendar: cal) {
            months.append(monthStars(m, days: d.recordDays, first: first, now: now, calendar: cal))
        }
        var current: MacGameMonth? = nil
        if first != nil, let cur = cal.date(from: cal.dateComponents([.year, .month], from: now)) {
            current = monthStars(cur, days: d.recordDays, first: first, now: now, calendar: cal)
        }
        let stars = months.reduce(0) { $0 + $1.settledStars }
        let longest = MacGameRules.longestStreak(d.weeks, calendar: cal)
        let add = firstMacAdd()
        let tidy = MacGameDays.fixedTidy(money.expenses, now: now, calendar: cal)
        var badges = MacGameRules.badges(longest: longest, months: months)
        badges.formUnion(MacGameDays.badges2(longest: longest, dayCount: d.recordDays.count, macAdd: add != nil, fixedTidy: tidy))
        let streak = MacGameRules.streak(d.weeks, now: now, calendar: cal)
        let lights = MacGameDays.weekLights(d, now: now, calendar: cal)
        let records = MacGameDays.records(weeks: d.weeks, months: months, calendar: cal)
        let hits = MacGameDays.recordHits(weeks: d.weeks, months: months, now: now, calendar: cal)
        return MacGameFacts(first: first, weekCount: d.weeks.count, streak: streak, lights: lights, months: months,
                            current: current, stars: stars, badges: badges, days: d, firstAdd: add, records: records,
                            recordHits: hits)
    }

    // sim6: game#39（同一個帳號的日誌裡最早那筆收支 add 的時間；只讀 kind、key、at；用 ==，不 switch）
    private func firstMacAdd() -> Date? {
        guard let h = money.accountHash, journal.accountHash == h else { return nil }
        var first: Date? = nil
        for e in journal.entries where e.kind == .add && LedgerMerge.keys.contains(e.key) {
            if let f = first, f <= e.at { continue }
            first = e.at
        }
        return first
    }

    /// 一般路徑點亮時間：第一次在電腦記帳＝那筆的 at；其餘＝現在
    private func earnedTime(_ id: String, facts: MacGameFacts, now: Date) -> Double {
        if id == MacGameDays.firstMacID, let at = facts.firstAdd {
            return at.timeIntervalSinceReferenceDate
        }
        return now.timeIntervalSinceReferenceDate
    }

    // sim6: game#44（v1 → v2：新 4 枚現在成立的 earned＝0（靜默）；seen 加這幾枚＋現在等級＋現在成立的紀錄；
    //               noSpend 空、lastReview 不放（升級後第一張回顧照出現）；有補上才寫那行字）
    private func migrate(_ state: inout MacGameStored, facts: MacGameFacts, level lv: Int) {
        var added = 0
        for b in MacGameBadge.all where MacGameDays.addedInV2.contains(b.id) && facts.badges.contains(b.id) {
            guard state.earned[b.id] == nil else { continue }
            state.earned[b.id] = 0
            added += 1
        }
        let seen = Set(state.seen)
        var add: [String] = ["level.\(lv)"]
        for b in MacGameBadge.all where MacGameDays.addedInV2.contains(b.id) && state.earned[b.id] != nil {
            add.append(b.id)
        }
        add += facts.recordHits.map { r in r.id }
        state.seen += add.filter { x in !seen.contains(x) }
        if added > 0 {
            backfillNote = MacGameText.backfill(state.earned.count)
        }
    }

    // sim6: game#37（有破紀錄的那一則：Level up! ＞ New record! ＞ Goal reached!；一天最多跳一次照 ★5）
    private func celebrateRecords(_ state: inout MacGameStored, newLevel: Int?, newBadges: [String], records: [MacGameRecordHit],
                                  now: Date, calendar cal: Calendar) {
        let texts: [String] = records.map { r in r.text }
        guard let t = MacGameText.toast(newLevel: newLevel, newBadges: newBadges, newRecords: texts) else { return }
        if let n = newLevel {
            state.seen.append("level.\(n)")
        }
        state.seen += newBadges
        state.seen += records.map { r in r.id }
        show(MacGameToast(text: t.text, script: t.script))
        let today = cal.startOfDay(for: now)
        if lastBounceDay != today {
            bounce += 1
            lastBounceDay = today
        }
    }

    // sim6: game#34（快照加第二批：今天能不能打卡、回顧卡、自己的紀錄、只看不改；「最近幾個月」只放 6 個）
    private func makeSnapshot2(_ f: MacGameFacts, state: MacGameStored, lit: Set<String>, shown: Int, writable: Bool,
                               newer: Bool, now: Date) -> MacGameSnapshot {
        let base = makeSnapshot(f, state: state, lit: lit, shown: shown)
        let cal = MacGameRules.calendar
        var out = MacGameSnapshot(started: base.started, level: base.level, stageName: base.stageName, stageIcon: base.stageIcon,
                                  xp: base.xp, floor: base.floor, next: base.next, streakWeeks: base.streakWeeks,
                                  streakSince: base.streakSince, lights: base.lights, current: base.current,
                                  settled: Array(base.settled.prefix(6)), earned: base.earned, lit: base.lit,
                                  backfillNote: base.backfillNote)
        let noSpend = Set(state.noSpend)
        out.canCheckToday = MacGameDays.canCheck(f.days.today, facts: f.days, noSpend: noSpend, writable: writable, calendar: cal)
        out.review = MacGameDays.review(facts: f.days, months: f.months, earned: state.earned, lastReview: state.lastReview,
                                        streakWeeks: f.streak.weeks, writable: writable, now: now, calendar: cal)
        out.records = f.records
        out.readOnlyNote = newer ? MacGameText.readOnly : nil
        return out
    }
}
