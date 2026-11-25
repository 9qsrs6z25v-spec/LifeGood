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

    static let empty = MacGameSnapshot(started: false, level: 0, stageName: "空地", stageIcon: "leaf.fill",
                                       xp: 0, floor: 0, next: 100, streakWeeks: 0, streakSince: nil, lights: [],
                                       current: nil, settled: [], earned: [:], lit: [], backfillNote: nil)
}

/// 本機那一份（mac.game.state.<雜湊>）：v、seen、earned、maxXP；沒有金額、名稱、備註、帳的 id
private struct MacGameStored {
    var seen: [String] = []
    var earned: [String: Double] = [:]
    var maxXP: Int = 0

    init() {}

    init(_ d: [String: Any]) {
        seen = d["seen"] as? [String] ?? []
        earned = d["earned"] as? [String: Double] ?? [:]
        maxXP = d["maxXP"] as? Int ?? 0
    }

    var dictionary: [String: Any] {
        ["v": 1, "seen": seen, "earned": earned, "maxXP": maxXP]
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
}

@MainActor
final class MacGameModel: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var snapshot: MacGameSnapshot = .empty
    @Published private(set) var toast: MacGameToast? = nil
    /// 點亮時 +1（symbolEffect(.bounce, value:) 用）
    @Published private(set) var bounce: Int = 0

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

    // sim5: game#21（什麼時候算：money 七個 @Published＋回到前景 → debounce 300ms → recompute；60 秒計時器跨午夜才算；不在 body、.task 裡算或寫）
    init(money: MacMoneyStore) {
        self.enabled = UserDefaults.standard.object(forKey: "mac.game.enabled") as? Bool ?? true
        self.money = money
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
            return
        }
        if h != noteHash {
            backfillNote = nil
            noteHash = h
        }
        let key = "mac.game.state." + h
        let facts = compute(now: now, calendar: cal)
        let raw = UserDefaults.standard.dictionary(forKey: key)
        let fresh = raw == nil || (raw?["v"] as? Int) != 1
        var state = fresh ? MacGameStored() : MacGameStored(raw ?? [:])
        var lit = Set(state.earned.keys).union(facts.badges)
        let xp = MacGameRules.xp(weeks: facts.weekCount, stars: facts.stars, badges: lit.count)
        let shown = max(xp, state.maxXP)
        let lv = MacGameRules.level(xp: shown).level
        if isWritable(h) {
            removeOtherStates(keep: key)
            if fresh || justEnabled {
                backfill(&state, facts: facts, level: lv, fresh: fresh)
            } else {
                // ★4：earned 在可寫狀態第一次看到成立就寫（不管前景）
                for b in MacGameBadge.all where facts.badges.contains(b.id) && state.earned[b.id] == nil {
                    state.earned[b.id] = now.timeIntervalSinceReferenceDate
                }
                if NSApplication.shared.isActive {
                    celebrate(&state, level: lv, now: now, calendar: cal)
                }
            }
            state.maxXP = max(state.maxXP, xp)
            trim(&state)
            UserDefaults.standard.set(state.dictionary, forKey: key)
            lit = Set(state.earned.keys).union(facts.badges)
        }
        snapshot = makeSnapshot(facts, state: state, lit: lit, shown: shown)
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
}
