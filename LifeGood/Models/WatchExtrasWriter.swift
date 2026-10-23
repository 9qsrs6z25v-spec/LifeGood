import Foundation

// MARK: - 手錶附加資料快取（手錶 v1，v25.574；只屬於主 App；watch/judge.md §5.2、§8 v1；watch/build/v1/brief.md §2）
//
// 手錶包裡有幾樣東西要碰帳本才算得出來（v1 只有「哪幾期卡費是自己繳」）。被手錶叫醒的冷啟動不准碰帳本，
// 所以 App 開著時（WidgetSnapshotWriter.writeNow 寫 bills 的時候）先把它們寫成 App Group 的一個小檔，
// WatchPackageBuilder 組包時只讀這個檔。v2 起再加最近金額、今天記的帳…（一律選填）。
//
// ⚠️ 這個檔只放「手錶包要的、已經消毒過的」東西：卡費只放帳單的來源 key（「c-<卡 UUID>-<期>」），
//    沒有卡名、金額、號碼。
//
// [手錶 v2] v25.576（watch/judge.md §2.6、§2.7、§4.3、§5.2；watch/build/v2/brief.md §2）：
//   • 快取多四樣（WidgetSnapshotWriter.writeNow 寫 money 或 bills 時都重寫）：
//     recentAmounts（每個分類最近 3 個不同金額）、titleHints（每個分類每個時段最常寫的名稱）、
//     todayRecords（今天的變動支出，最多 10 筆；只有名稱、金額字、時間、圖示、是不是手錶記的——
//     不帶備註、照片、同行者、付款卡）、includedIds（帳本裡已經有的手錶編號，近 3 天入帳、最多 100）
//   • WatchImportedLog：已經入帳的手錶編號（App Group UserDefaults「watch_imported_ids」）。QuickRecordImporter 入帳後寫、
//     WatchBridge 收到手錶的帳先查（在裡面就不再放進收件匣）、這裡算 includedIds 與「⌚︎ 手錶記的」
//   • WatchRecordInbox：手錶的 WatchRecord → 收件匣的 QuickRecordEntry（WatchBridge 用；範本編號規則 judge §1.4-1）
//   規則跟 scratchpad/watch/build/v2/sim_v2.py 的同名函式一模一樣（改了兩邊一起改、重跑 sim）。

/// watch_extras_v1.json（只在 iPhone；不會送到手錶）
struct WatchExtrasCache: Codable, Equatable, WidgetSnapshotPayload {
    static let file = WidgetSnapshotFile.watchExtras
    static let schemaVersion = 1

    var schema: Int = WatchExtrasCache.schemaVersion
    var generatedAt: Date
    /// 自己繳（WealthCardDue.isManual）的那幾期卡費：「c-<卡 UUID>-<帳單 key>」（＝FinanceUpcoming 卡費那一列的 id，
    /// 也是 WidgetBill.id「@」前面那一段），排好
    var manualCardBillKeys: [String]
    /// 這支 iPhone 是加入別人的共享（CloudKitManager.isShareParticipant）：「會議細節裡的部屬名字」預設關（judge §6.6）
    var isShareParticipant: Bool

    // MARK: [v2] 一律選填（v1 寫的舊檔沒有）

    /// 最近 3 個不同金額（台幣、四捨五入到元，新到舊）：「飲食」整天、「飲食@11-14」只看那個時段
    var recentAmounts: [String: [Double]]? = nil
    /// 分類 key → 時段 key（WatchTimeSlot.keys）→ 最常寫的名稱
    var titleHints: [String: [String: String]]? = nil
    /// 今天的變動支出（新到舊，最多 10 筆）
    var todayRecords: [WatchRecordRow]? = nil
    /// 帳本裡已經有的手錶編號（近 3 天入帳、還在帳本裡，新到舊，最多 100）
    var includedIds: [UUID]? = nil
}

@MainActor
enum WatchExtrasWriter {
    /// 「最近金額」「這個時段最常寫的名稱」看近幾天（同 iPhone 小工具常記範本，WidgetMoneyExtras.lookbackDays）
    static let lookbackDays = 60
    /// 每個分類給幾個最近金額
    static let recentAmountCount = 3
    /// 一個名稱在那個時段至少寫過幾次才算「最常寫的」
    static let titleHintMinCount = 2
    /// 今天記的帳最多送幾筆
    static let todayRecordMax = 10
    /// includedIds：入帳後幾天內的才放
    static let includedDays: Double = 3
    /// includedIds 最多幾個
    static let includedMax = 100

    /// WidgetSnapshotWriter.writeNow 寫 money 或 bills 時叫（App 開著、三份資料都在）。內容沒變不寫
    static func write(expense: ExpenseStore, finance: FinanceStore, life: LifeStore, now: Date) {
        let facts = life.wealthFacts(expense: expense, finance: finance, now: now)
        var keys: [String] = []
        for card in facts.cards {
            for due in card.dues where due.isManual {
                keys.append("c-" + card.id.uuidString + "-" + due.key)
            }
        }
        keys.sort()
        var cache = WatchExtrasCache(generatedAt: now,
                                     manualCardBillKeys: keys,
                                     isShareParticipant: CloudKitManager.shared.isShareParticipant)
        // [v2] 記一筆、今天記的帳
        let cal = Calendar.current
        let all: [Expense] = expense.expenses
        let recent = candidates(all, now: now, calendar: cal)
        cache.recentAmounts = recentAmounts(recent, calendar: cal)
        cache.titleHints = titleHints(recent, calendar: cal)
        let log = WatchImportedLog.all()
        let watchIds = Set(log.keys)
        cache.todayRecords = todayRecords(all, watchIds: watchIds, now: now, calendar: cal) { e in
            expense.displayAmountText(e)
        }
        cache.includedIds = includedIds(log: log, ledger: Set(all.map(\.id)), now: now)
        WidgetSnapshotStore.write(cache)
    }

    // MARK: - [v2] 規則（sim_v2.py 同名函式）

    /// 近 60 天（今天 00:00 往回 60 天起、到現在為止）、變動支出、台幣（NT$／TWD／空字串）、金額 > 0、
    /// 沒連股票／房子／保單、有分類（同 WidgetMoneyExtras 常記範本的候選條件，不要求名稱）
    static func candidates(_ expenses: [Expense], now: Date, calendar cal: Calendar) -> [Expense] {
        let today = cal.startOfDay(for: now)
        let start = cal.date(byAdding: .day, value: -lookbackDays, to: today) ?? today
        return expenses.filter { e in
            guard e.expenseType == .variable, e.date >= start, e.date <= now else { return false }
            guard e.amount.isFinite, e.amount > 0, e.variableCategory != nil else { return false }
            guard e.linkedStockId == nil, e.linkedRealEstateId == nil, e.linkedInsuranceId == nil else { return false }
            let code = e.currencyCode
            return code == "NT$" || code == "TWD" || code.isEmpty
        }
    }

    /// 新到舊（同一刻 id 字串小的先）
    static func newestFirst(_ list: [Expense]) -> [Expense] {
        list.sorted { a, b in
            if a.date != b.date { return a.date > b.date }
            return a.id.uuidString < b.id.uuidString
        }
    }

    /// 每個分類兩份：整天（鍵「飲食」）、這一筆的時段（鍵「飲食@11-14」，WatchTimeSlot.amountKey）。
    /// 都是新到舊，金額四捨五入到元（≥ 1），不重複，取前 3 個。
    /// 為什麼要分時段：中午打開「飲食」要是 180（昨天的午餐），不是早上那杯 55 的咖啡
    static func recentAmounts(_ recent: [Expense], calendar cal: Calendar) -> [String: [Double]] {
        var out: [String: [Double]] = [:]
        for e in newestFirst(recent) {
            guard let category = e.variableCategory?.rawValue else { continue }
            let whole = e.amount.rounded()
            guard whole >= 1 else { continue }
            let slotKey = WatchTimeSlot.amountKey(category: category,
                                                  slot: WatchTimeSlot.key(for: e.date, calendar: cal))
            for key in [category, slotKey] {
                var list = out[key] ?? []
                guard list.count < recentAmountCount, !list.contains(whole) else { continue }
                list.append(whole)
                out[key] = list
            }
        }
        return out
    }

    /// 每個分類 × 每個時段：名稱去頭尾空白、不是空的、不等於分類名；寫過 ≥ 2 次的取最多次的，
    /// 同數取最近一筆比較新的，再同取名稱字串小的
    static func titleHints(_ recent: [Expense], calendar cal: Calendar) -> [String: [String: String]] {
        // 分類 → 時段 → 名稱 → (次數, 最近一次)
        var tally: [String: [String: [String: (count: Int, latest: Date)]]] = [:]
        for e in recent {
            guard let category = e.variableCategory else { continue }
            let key = category.rawValue
            let title = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title != key else { continue }
            let slot = WatchTimeSlot.key(for: e.date, calendar: cal)
            var bySlot = tally[key] ?? [:]
            var byTitle = bySlot[slot] ?? [:]
            let old = byTitle[title] ?? (count: 0, latest: Date.distantPast)
            byTitle[title] = (count: old.count + 1, latest: max(old.latest, e.date))
            bySlot[slot] = byTitle
            tally[key] = bySlot
        }
        var out: [String: [String: String]] = [:]
        for (key, bySlot) in tally {
            var hints: [String: String] = [:]
            for (slot, byTitle) in bySlot {
                if let best = bestTitle(byTitle) {
                    hints[slot] = best
                }
            }
            if !hints.isEmpty {
                out[key] = hints
            }
        }
        return out
    }

    /// 次數 ≥ 2 的裡面挑：次數多 → 最近一次新 → 名稱字串小
    static func bestTitle(_ byTitle: [String: (count: Int, latest: Date)]) -> String? {
        let ranked = byTitle.filter { $0.value.count >= titleHintMinCount }.sorted { a, b in
            if a.value.count != b.value.count { return a.value.count > b.value.count }
            if a.value.latest != b.value.latest { return a.value.latest > b.value.latest }
            return a.key < b.key
        }
        return ranked.first?.key
    }

    /// 今天（Calendar.current 的同一天）的變動支出，新到舊、最多 10 筆。
    /// 名稱去頭尾空白（空的用分類名）；金額字用 ExpenseStore.displayAmountText（amountText 閉包）；
    /// 圖示：連車的用車子分類的圖示，否則用變動分類的圖示；是不是手錶記的看 WatchImportedLog
    static func todayRecords(_ expenses: [Expense], watchIds: Set<UUID>, now: Date, calendar cal: Calendar,
                             amountText: (Expense) -> String) -> [WatchRecordRow] {
        let today = expenses.filter { $0.expenseType == .variable && cal.isDate($0.date, inSameDayAs: now) }
        return newestFirst(today).prefix(todayRecordMax).map { e in
            WatchRecordRow(id: e.id, title: rowTitle(e), amountText: amountText(e), time: e.date,
                           icon: rowIcon(e), fromWatch: watchIds.contains(e.id))
        }
    }

    static func rowTitle(_ e: Expense) -> String {
        let t = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        return e.variableCategory?.rawValue ?? VariableCategory.other.rawValue
    }

    static func rowIcon(_ e: Expense) -> String {
        if e.linkedVehicleId != nil, let v = e.vehicleExpenseCategory {
            return v.icon
        }
        return (e.variableCategory ?? .other).icon
    }

    /// 入帳 3 天內、帳本裡還有的手錶編號：入帳時間新到舊（同一刻編號字串小的先），最多 100
    static func includedIds(log: [UUID: Date], ledger: Set<UUID>, now: Date) -> [UUID] {
        let limit = includedDays * 24 * 3600
        let kept = log.filter { ledger.contains($0.key) && now.timeIntervalSince($0.value) <= limit }
        let sorted = kept.sorted { a, b in
            if a.value != b.value { return a.value > b.value }
            return a.key.uuidString < b.key.uuidString
        }
        return sorted.prefix(includedMax).map { $0.key }
    }
}

// MARK: - [v2] 已經入帳的手錶編號

/// App Group UserDefaults「watch_imported_ids」：編號字串 → 入帳時間（1970 起的秒）。最多 200 筆，舊的先丟。
/// QuickRecordImporter 入帳後寫（主執行緒）；WatchBridge（被手錶叫醒的冷啟動也會叫）、WatchExtrasWriter 讀。
/// 只碰 UserDefaults，不碰三份大資料。
enum WatchImportedLog {
    static let key = "watch_imported_ids"
    static let maxCount = 200

    static func all() -> [UUID: Date] {
        guard let raw = WidgetShared.defaults?.dictionary(forKey: key) else { return [:] }
        var out: [UUID: Date] = [:]
        for (k, v) in raw {
            guard let id = UUID(uuidString: k), let t = v as? Double else { continue }
            out[id] = Date(timeIntervalSince1970: t)
        }
        return out
    }

    static func contains(_ id: UUID) -> Bool {
        all()[id] != nil
    }

    /// 記下這幾個編號（已經有的更新時間）；超過 200 筆把入帳時間最舊的丟掉
    static func note(_ ids: [UUID], at date: Date) {
        guard !ids.isEmpty, let d = WidgetShared.defaults else { return }
        var log = all()
        for id in ids {
            log[id] = date
        }
        let kept = log.sorted { a, b in
            if a.value != b.value { return a.value > b.value }
            return a.key.uuidString < b.key.uuidString
        }.prefix(maxCount)
        var raw: [String: Double] = [:]
        for (id, t) in kept {
            raw[id.uuidString] = t.timeIntervalSince1970
        }
        d.set(raw, forKey: key)
    }
}

// MARK: - [v2] 手錶的一筆 → 收件匣的一筆

enum WatchRecordInbox {
    /// 金額上限（防壞資料；手錶數字鍵最多 6 位數）
    static let maxAmount: Double = 10_000_000
    /// 按下去的時間比現在晚這麼多（手錶時鐘不準）就用現在
    static let futureSlack: TimeInterval = 5 * 60

    /// 手錶的 WatchRecord → QuickRecordEntry：id 同一個、templateId＝templateId ?? "watch.<id>"（judge §1.4-1）、
    /// title nil＝空字串（入帳時用分類名）、source＝"watch"、時間＝按下去那一刻。金額不對回 nil（不收）
    static func entry(from r: WatchRecord, now: Date) -> QuickRecordEntry? {
        guard r.amountTWD.isFinite, r.amountTWD > 0, r.amountTWD <= maxAmount else { return nil }
        let pressed = r.createdAt.timeIntervalSince(now) > futureSlack ? now : r.createdAt
        var e = QuickRecordEntry(templateId: r.templateId ?? ("watch." + r.id.uuidString),
                                 title: r.title ?? "",
                                 amount: r.amountTWD,
                                 amountText: r.amountText,
                                 categoryKey: r.categoryKey,
                                 vehicleId: r.vehicleId,
                                 vehicleCategoryKey: r.vehicleCategoryKey,
                                 now: pressed)
        e.id = r.id
        e.source = QuickRecordInbox.watchSource
        return e
    }
}
