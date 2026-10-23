import Foundation
import UIKit
import CoreLocation

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
//
// [手錶 v6] v25.578（watch/judge.md §2.14、§5.2、§6.1；watch/build/v6/brief.md §2；sim_v6.py 同名函式）：旅行——
//   • 快取多 timeZoneId（App 寫這一份那一刻的時區：快照每一天的起訖用它算）、tripToday、tripTomorrow
//     （旅途中今天、明天的站：站名、時間、第幾站、地址、座標、電話、打卡時間、天氣字；這趟的幣別與匯率、
//     最近記過的金額（只有數字）、常用分類）。**不放**：站的備註、照片、子地點、伴手禮、同行者、花費明細
//   • write（寫 money／bills 時）順手算旅行；只寫 life 時（打卡、改行程、天氣抓到了）走 writeTrip：讀現有快取只換旅行那幾欄
//   • 天氣只讀 TripWeatherStore 的快取（手錶不自己抓）；App 在前景、今天明天的站預報還沒抓過或超過一天，
//     叫一次 TripWeatherStore.preload（已經有新的就不打網路、失敗過的不自動重試、10 分鐘最多一次），抓完重寫 life
//   • 幣別（tripCurrency）：這趟已經記過的外幣 → 站的電話國碼 → 座標（台韓日三個框）；到 iPhone 設定的匯率找那一筆

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

    // MARK: [v6] 旅行（一律選填；v1、v2 寫的舊檔沒有）

    /// App 寫這一份那一刻的時區（Calendar.current.timeZone.identifier）：快照每一天的起訖是用它算的
    var timeZoneId: String? = nil
    /// 旅途中今天的站（今天不在任何一趟的期間裡是 nil）
    var tripToday: WatchTripDay? = nil
    /// 旅途中明天的站
    var tripTomorrow: WatchTripDay? = nil
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
        // [v6] 旅行
        fillTrip(&cache, expense: expense, life: life, now: now)
        WidgetSnapshotStore.write(cache)
        preloadWeatherIfNeeded(plans: life.tripPlans, now: now)
    }

    /// [v6] 只有 life 變了（打卡、改行程、天氣抓到了；WidgetSnapshotWriter.writeNow 只寫 life 的時候）：
    /// 讀現有的快取、只換旅行那幾欄（不重算卡費、最近金額）。還沒寫過快取（write 還沒跑過）就不寫，等 write
    static func writeTrip(expense: ExpenseStore, life: LifeStore, now: Date) {
        guard var cache = WidgetSnapshotStore.read(WatchExtrasCache.self) else { return }
        fillTrip(&cache, expense: expense, life: life, now: now)
        cache.generatedAt = now
        WidgetSnapshotStore.write(cache)
        preloadWeatherIfNeeded(plans: life.tripPlans, now: now)
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

// MARK: - [v6] 旅行（tripToday、tripTomorrow；judge §2.14、§5.2；sim_v6.py 同名函式）

@MainActor
extension WatchExtrasWriter {
    /// 「這趟最近記過的金額」最多幾個
    static let tripRecentCount = 3
    /// 「這趟最常記的分類」最多幾個
    static let tripTopCategoryCount = 4
    /// 天氣提醒送幾句
    static let weatherTipCount = 2
    /// App 在前景時，多久最多叫一次 TripWeatherStore.preload
    static let weatherPreloadInterval: TimeInterval = 10 * 60

    /// 幣別 ISO → 給人看的名字（iPhone 設定那一筆的寫法認不得時用；「韓元」）
    static let currencyNames: [String: String] = [
        "KRW": "韓元", "JPY": "日圓", "CNY": "人民幣", "HKD": "港幣", "MOP": "澳門幣", "SGD": "新加坡幣",
        "THB": "泰銖", "VND": "越南盾", "MYR": "馬來幣", "IDR": "印尼盾", "PHP": "菲律賓披索",
        "USD": "美金", "EUR": "歐元", "GBP": "英鎊", "AUD": "澳幣", "NZD": "紐幣", "CHF": "瑞士法郎", "CAD": "加幣"
    ]

    /// 錶冠一格多少（judge §2.14「錶冠一格 ₩1,000」）；不在表上＝1
    static let crownSteps: [String: Double] = [
        "KRW": 1000, "JPY": 100, "VND": 10000, "IDR": 1000, "THB": 10, "PHP": 10, "HKD": 10, "MOP": 10, "CNY": 10
    ]

    /// 電話國碼 → 那一國的幣別 ISO（Apple 地圖給的電話是國際格式「+82 2-…」）。先比 3 碼再比 2 碼
    static let phoneCodes: [String: String] = [
        "886": "TWD", "852": "HKD", "853": "MOP", "351": "EUR", "353": "EUR", "358": "EUR",
        "81": "JPY", "82": "KRW", "86": "CNY", "65": "SGD", "66": "THB", "84": "VND", "60": "MYR",
        "62": "IDR", "63": "PHP", "44": "GBP", "61": "AUD", "64": "NZD", "41": "CHF",
        "33": "EUR", "34": "EUR", "39": "EUR", "49": "EUR", "31": "EUR", "32": "EUR", "43": "EUR", "30": "EUR"
    ]

    /// 快取的旅行那幾欄（write、writeTrip 共用）：時區、今天、明天
    static func fillTrip(_ cache: inout WatchExtrasCache, expense: ExpenseStore, life: LifeStore, now: Date) {
        let cal = Calendar.current
        cache.timeZoneId = cal.timeZone.identifier
        let plans: [TripPlan] = life.tripPlans
        let all: [Expense] = expense.expenses
        let rates: [CurrencyRate] = expense.currencyRates
        let weather: (TripStop, Date) -> TripDayWeather? = { stop, day in
            guard let c = stop.coordinate else { return nil }
            return TripWeatherStore.shared.forecast(at: c, on: day)
        }
        cache.tripToday = tripDay(on: now, plans: plans, expenses: all, rates: rates, calendar: cal, weather: weather)
        let todayStart = cal.startOfDay(for: now)
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: todayStart) {
            cache.tripTomorrow = tripDay(on: tomorrow, plans: plans, expenses: all, rates: rates, calendar: cal,
                                         weather: weather)
        } else {
            cache.tripTomorrow = nil
        }
    }

    /// 那一天落在哪一趟的期間裡（同 LifeStore.tripPlan(covering:)：以「天」比對出發那天到最後一站離開那天；照順序第一個）
    static func coveringPlan(_ plans: [TripPlan], on date: Date, calendar cal: Calendar) -> TripPlan? {
        let day = cal.startOfDay(for: date)
        return plans.first { plan in
            let from = cal.startOfDay(for: plan.startDate)
            let to = cal.startOfDay(for: plan.endDate)
            return day >= from && day <= to
        }
    }

    /// 旅途中的那一天（不在任何一趟的期間裡回 nil）。站＝時間軸上抵達時間落在這一天的（含已經離開的）
    static func tripDay(on date: Date, plans: [TripPlan], expenses: [Expense], rates: [CurrencyRate],
                        calendar cal: Calendar, weather: (TripStop, Date) -> TripDayWeather?) -> WatchTripDay? {
        guard let plan = coveringPlan(plans, on: date, calendar: cal) else { return nil }
        let dayStart = cal.startOfDay(for: date)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        let firstDay = cal.startOfDay(for: plan.startDate)
        let count = max(plan.dayCount, 1)
        let offset = cal.dateComponents([.day], from: firstDay, to: dayStart).day ?? 0
        let index = min(max(offset + 1, 1), count)
        var stops: [WatchTripStop] = []
        for slot in plan.timeline where slot.arrival >= dayStart && slot.arrival < dayEnd {
            stops.append(tripStop(slot: slot, planId: plan.id, weather: weather(slot.stop, slot.arrival)))
        }
        let trimmed = plan.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        var day = WatchTripDay(planId: plan.id, title: trimmed.isEmpty ? "旅行" : trimmed,
                               dayKey: WidgetDateText.dayKey(dayStart), dayStart: dayStart, dayEnd: dayEnd,
                               dayIndex: index, dayCount: count, stops: stops)
        let money = tripCurrency(plan: plan, expenses: expenses, rates: rates)
        day.currency = money.currency
        day.missingCurrencyLabel = money.missingLabel
        // 天氣一定跟出處一起（WeatherKit 規定；judge §2.14）：有任何一站有天氣字才帶網址
        if stops.contains(where: { $0.weatherText != nil }) {
            day.weatherSource = TripWeatherStore.attributionURL.absoluteString
        }
        let linked = tripExpenses(expenses, planId: plan.id)
        if let c = money.currency {
            let recent = tripRecentAmounts(linked, currency: c)
            day.recentAmounts = recent.isEmpty ? nil : recent
        }
        let top = tripTopCategories(linked)
        day.topCategoryKeys = top.isEmpty ? nil : top
        return day
    }

    /// 時間軸的一格 → 手錶的一站（只抄白名單那幾欄：不帶備註、照片、子地點、封面、路段）
    static func tripStop(slot: TripPlan.Slot, planId: UUID, weather w: TripDayWeather?) -> WatchTripStop {
        let s = slot.stop
        let phone = (s.phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // 場次 id 跟 TodayAgenda 同一個寫法（「t」＋行程編號前 8 碼＋抵達時間的秒）：錶面「下一場」點進來對得上
        let timelineId = "t" + String(planId.uuidString.prefix(8)) + String(Int(slot.arrival.timeIntervalSince1970))
        var out = WatchTripStop(id: s.id, timelineStopId: timelineId, name: s.displayName,
                                isOvernight: s.isOvernight, arrival: slot.arrival, departure: slot.departure,
                                dwellMinutes: max(0, s.dwellMinutes),
                                address: s.displayAddress.trimmingCharacters(in: .whitespacesAndNewlines))
        out.latitude = s.latitude
        out.longitude = s.longitude
        out.phone = phone.isEmpty ? nil : phone
        out.arrivedAt = s.actualArrival
        out.departedAt = s.actualDeparture
        if let w {
            out.weatherText = weatherText(w)
            out.weatherSymbol = w.symbolName
            let tips: [String] = w.tips.prefix(weatherTipCount).map { $0.text }
            out.weatherTips = tips.isEmpty ? nil : tips
        }
        return out
    }

    /// 「18°／11° 短暫陣雨 40%」（降雨機率 30% 以上才寫，同 iPhone 天氣膠囊 TripDayWeather.showsRain）
    static func weatherText(_ w: TripDayWeather) -> String {
        var parts: [String] = [w.temperatureText]
        let condition = w.conditionText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !condition.isEmpty { parts.append(condition) }
        if w.showsRain { parts.append(w.rainText) }
        return parts.joined(separator: " ")
    }

    /// 這趟記帳用什麼幣別（judge §2.14；sim_v6.py trip_currency）：
    /// ① 這趟已經記過的外幣支出（linkedTripPlanId＝這趟）最常用的那個寫法——你在 iPhone 記過一筆韓元，就照你的寫法
    /// ② 站的電話國碼多數決；沒有電話的站看座標（只認台灣、韓國、日本三個框）。多數是台灣＝國內，不用外幣
    /// 找到那一國之後到 iPhone 設定的匯率找同一個 ISO 代碼（FXRateService.isoCode）、匯率 > 0 的第一筆；
    /// 沒有＝currency nil、missingLabel「韓元」（手錶照台幣記，記帳台寫要到 iPhone 設定加匯率）
    static func tripCurrency(plan: TripPlan, expenses: [Expense],
                             rates: [CurrencyRate]) -> (currency: WatchCurrency?, missingLabel: String?) {
        let linked = tripExpenses(expenses, planId: plan.id)
        var codeCount: [String: Int] = [:]
        var codeOrder: [String] = []
        for e in linked {
            let code = e.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !isTWD(code) else { continue }
            if codeCount[code] == nil { codeOrder.append(code) }
            codeCount[code, default: 0] += 1
        }
        if let best = mostCommon(codeOrder, counts: codeCount),
           let rate = rates.first(where: { validRate($0) && $0.code.trimmingCharacters(in: .whitespacesAndNewlines) == best }) {
            return (currency: watchCurrency(rate), missingLabel: nil)
        }
        var isoCount: [String: Int] = [:]
        var isoOrder: [String] = []
        for stop in plan.stops {
            guard let iso = stopCountryISO(stop) else { continue }
            if isoCount[iso] == nil { isoOrder.append(iso) }
            isoCount[iso, default: 0] += 1
        }
        guard let iso = mostCommon(isoOrder, counts: isoCount), iso != "TWD" else {
            return (currency: nil, missingLabel: nil)
        }
        if let rate = rates.first(where: { validRate($0) && FXRateService.isoCode(for: $0.code) == iso }) {
            return (currency: watchCurrency(rate), missingLabel: nil)
        }
        return (currency: nil, missingLabel: currencyNames[iso] ?? iso)
    }

    static func isTWD(_ code: String) -> Bool {
        code == "NT$" || code == "TWD" || code.isEmpty
    }

    static func validRate(_ r: CurrencyRate) -> Bool {
        r.rate.isFinite && r.rate > 0
    }

    /// 次數最多的；同數取先出現的
    static func mostCommon(_ order: [String], counts: [String: Int]) -> String? {
        var best: String? = nil
        var bestCount = 0
        for key in order {
            let n = counts[key] ?? 0
            if n > bestCount {
                best = key
                bestCount = n
            }
        }
        return best
    }

    /// iPhone 設定那一筆匯率 → 手錶的幣別：code 照原樣（＝支出存的 currencyCode）、名字與錶冠一格照 ISO 查
    static func watchCurrency(_ rate: CurrencyRate) -> WatchCurrency {
        let iso = FXRateService.isoCode(for: rate.code)
        let trimmed = rate.code.trimmingCharacters(in: .whitespacesAndNewlines)
        let label: String = iso.flatMap { currencyNames[$0] } ?? trimmed
        let symbol: String = WealthFormat.currencySymbol(rate.code) ?? ""
        let step: Double = iso.flatMap { crownSteps[$0] } ?? 1
        return WatchCurrency(code: rate.code, label: label, symbol: symbol, rateToTWD: rate.rate, crownStep: step)
    }

    /// 一站在哪一國：電話國碼優先，沒有電話看座標
    static func stopCountryISO(_ stop: TripStop) -> String? {
        if let iso = phoneCountryISO(stop.phone) { return iso }
        guard let lat = stop.latitude, let lon = stop.longitude else { return nil }
        return coordinateISO(latitude: lat, longitude: lon)
    }

    /// 「+82 2-3142-0000」→ KRW；「+886 …」→ TWD；不是「+」開頭、不認得 nil
    static func phoneCountryISO(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("+") else { return nil }
        let digits = String(trimmed.dropFirst().filter { $0.isNumber })
        for n in [3, 2] where digits.count > n {
            if let iso = phoneCodes[String(digits.prefix(n))] { return iso }
        }
        return nil
    }

    /// 座標框（邊界故意保守，認不得回 nil）：台灣 21.8–25.4N／119.3–122.1E；韓國 33.0–38.7N／124.5–129.6E；
    /// 日本 30.9–45.6N／129.6–146E，或 24.0–30.9N／122.9–132E（沖繩）
    static func coordinateISO(latitude lat: Double, longitude lon: Double) -> String? {
        if lat >= 21.8 && lat <= 25.4 && lon >= 119.3 && lon <= 122.1 { return "TWD" }
        if lat >= 33.0 && lat <= 38.7 && lon >= 124.5 && lon < 129.6 { return "KRW" }
        if lat >= 30.9 && lat <= 45.6 && lon >= 129.6 && lon <= 146.0 { return "JPY" }
        if lat >= 24.0 && lat < 30.9 && lon >= 122.9 && lon <= 132.0 { return "JPY" }
        return nil
    }

    /// 記在這一趟上的變動支出（新到舊）
    static func tripExpenses(_ expenses: [Expense], planId: UUID) -> [Expense] {
        let list = expenses.filter { e in
            e.expenseType == .variable && e.linkedTripPlanId == planId && e.amount.isFinite && e.amount > 0
        }
        return newestFirst(list)
    }

    /// 這趟最近記過的外幣金額（新到舊）：同一個幣別、台幣除回原幣（用現在的匯率）、對齊到錶冠一格、
    /// ≥ 一格、不重複、最多 3 個
    static func tripRecentAmounts(_ linked: [Expense], currency c: WatchCurrency) -> [Double] {
        guard c.rateToTWD.isFinite, c.rateToTWD > 0 else { return [] }
        let step: Double = c.crownStep > 0 ? c.crownStep : 1
        var out: [Double] = []
        for e in linked where e.currencyCode == c.code {
            let foreign = e.amount / c.rateToTWD
            let snapped = (foreign / step).rounded() * step
            guard snapped.isFinite, snapped >= step, !out.contains(snapped) else { continue }
            out.append(snapped)
            if out.count == tripRecentCount { break }
        }
        return out
    }

    /// 這趟最常記的分類（次數多到少，同數看最近一筆新的，再同看 key 字串；手錶上不給的拿掉），最多 4 個
    static func tripTopCategories(_ linked: [Expense]) -> [String] {
        var count: [String: Int] = [:]
        var latest: [String: Date] = [:]
        for e in linked {
            guard let key = e.variableCategory?.rawValue, WatchCategoryRule.isAllowed(key) else { continue }
            count[key, default: 0] += 1
            latest[key] = max(latest[key] ?? Date.distantPast, e.date)
        }
        let sorted: [String] = count.keys.sorted { a, b in
            let ca = count[a] ?? 0
            let cb = count[b] ?? 0
            if ca != cb { return ca > cb }
            let la = latest[a] ?? Date.distantPast
            let lb = latest[b] ?? Date.distantPast
            if la != lb { return la > lb }
            return a < b
        }
        return Array(sorted.prefix(tripTopCategoryCount))
    }

    // MARK: 天氣（只在前景、只抓今天明天的站）

    /// 上一次叫 TripWeatherStore.preload 的時間（只活在這次啟動）
    private static var lastWeatherPreload: Date? = nil

    /// App 在前景時：旅途中今天、明天的站，預報還沒抓過或超過一天的叫 TripWeatherStore.preload 抓一次
    /// （已經有新的就不打網路、失敗過的不自動重試）；抓完 writeNow([.life]) 重組，天氣字跟著上手錶。10 分鐘最多一次
    static func preloadWeatherIfNeeded(plans: [TripPlan], now: Date) {
        guard UIApplication.shared.applicationState == .active else { return }
        if let last = lastWeatherPreload, now.timeIntervalSince(last) < weatherPreloadInterval { return }
        let coords = weatherCoordinatesToLoad(plans: plans, now: now)
        guard !coords.isEmpty else { return }
        lastWeatherPreload = now
        Task { @MainActor in
            await TripWeatherStore.shared.preload(coords)
            WidgetSnapshotWriter.shared.writeNow([.life])
        }
    }

    /// 今天、明天在旅途中的站：有座標、在預報範圍內、沒失敗過、沒在抓、還沒抓過或已經超過一天的
    static func weatherCoordinatesToLoad(plans: [TripPlan], now: Date) -> [CLLocationCoordinate2D] {
        let cal = Calendar.current
        let store = TripWeatherStore.shared
        let today = cal.startOfDay(for: now)
        var out: [CLLocationCoordinate2D] = []
        for offset in 0..<2 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today),
                  let end = cal.date(byAdding: .day, value: 1, to: day),
                  let plan = coveringPlan(plans, on: day, calendar: cal) else { continue }
            for slot in plan.timeline where slot.arrival >= day && slot.arrival < end {
                guard let c = slot.stop.coordinate, TripWeatherStore.isWithinForecastRange(slot.arrival) else { continue }
                guard !store.hasFailed(at: c), !store.isLoading(at: c) else { continue }
                guard store.source(at: c) == nil || store.isStale(at: c) else { continue }
                out.append(c)
            }
        }
        return out
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
        // [v6] 旅途中：幣別、原幣、匯率、記到哪一趟哪一站（金額照舊是手錶上換好的台幣）
        e.currencyCode = r.currencyCode
        e.foreignAmount = r.foreignAmount
        e.rateShown = r.rateShown
        e.tripPlanId = r.tripPlanId
        e.tripStopId = r.tripStopId
        return e
    }
}
