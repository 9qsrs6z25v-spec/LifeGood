import Foundation

// MARK: - 記一筆、今天記的帳的字與規則（手錶 v2，v25.576；watch/judge.md §2.4、§2.6、§2.7、§2.17、§4.2；
//         watch/build/v2/brief.md §2）
//
// 只屬於 LifeGoodWatch（手錶小格不編）。只准用 Foundation 與 WatchPackage.swift／WidgetSnapshot.swift／
// DayTimelineAttributes.swift／RecordOutbox.swift 的純資料型別。View 只讀這裡組好的結果，不自己拼金額、不自己算步距。
// scratchpad/watch/build/v2/sim_v2.py 跟這個檔一模一樣（同名函式），改了兩邊一起改、重跑 sim。
//
// 手錶「只排版、不算錢」：還能花、今天幾筆都是 iPhone 寫好的字（WidgetMoneyDay）；手錶記的那幾筆
// **不自己減**，只寫「剛記的 N 筆還沒算進去」。
// 遮住（手腕放下、沒解鎖、手錶「遮住金額」、iPhone「隱藏金額」，WatchPrivacyRule.masksAmounts）：
//   記帳台格子的金額「•••」、今天記的帳「NT$ ••••」、記帳台頂上那一行換隱藏版（「已花 72%・今天 2 筆」）；名稱照顯示。
//
// [手錶 v6] v25.578（watch/judge.md §2.14「旅途中記一筆自動變外幣」；watch/build/v6/brief.md §2；sim_v6.py 同名函式）：
//   旅途中（WatchTripText.recordContext 有值）——
//   • 外幣（這趟有幣別與匯率）：記帳台換成這趟常用 4 個分類（範本是台幣固定金額，在國外沒意義）；金額頁是原幣
//     （「₩18,000」、錶冠一格 ₩1,000、膠囊是這趟最近記過的），送 iPhone 的台幣＝手錶上看到的「≈ NT$412」（入帳不重算）
//   • 國內旅行（沒有幣別）：記帳台照舊；每一筆都「記到」預設那一站（可以換成別站或整趟）
//   • 認得是哪一國、iPhone 沒有匯率：照台幣記，記帳台最下面寫「要記韓元：到 iPhone 設定加「韓元」匯率」

/// 記好的那一筆送到哪了（記好了那一頁的狀態行、記帳台的橫幅）
enum RecordSendState: Equatable {
    /// 10 秒內，還在手錶上（按〔復原〕就不記）
    case holding
    /// 送出去了，等 iPhone 回話（最多 5 秒）
    case waiting
    /// iPhone 回「已經入帳」；today＝入帳後今天記了幾筆（iPhone 帶回來的；沒有是 nil）
    case imported(today: Int?)
    /// iPhone 回「先放收件匣」（iPhone 被叫醒，但上面的 LifeGood 沒開）
    case queued
    /// 沒回話（iPhone 不在旁邊、關機、LifeGood 被滑掉——手錶分不出是哪一種）：先存在手錶上（count＝還沒送到的筆數，含這筆）
    case offline(count: Int)

    /// 已經是最後的字（之後 2.5 秒自己回 ② 錢）
    var isFinal: Bool {
        switch self {
        case .holding, .waiting: return false
        case .imported, .queued, .offline: return true
        }
    }

    /// iPhone 回過話（不要再被「沒回話」蓋掉）
    var hasPhoneReply: Bool {
        switch self {
        case .imported, .queued: return true
        case .holding, .waiting, .offline: return false
        }
    }
}

/// 記帳台的一格（2×2）
struct RecordDeskTile: Equatable, Identifiable {
    enum Kind: Equatable {
        /// 一按就記（點一下就記好）
        case template
        /// 分類（範本不到 4 個時補的；點了直接到金額頁）
        case category
    }

    var id: String
    var kind: Kind
    /// 「7-11 咖啡」「飲食」
    var title: String
    /// 右上角「55」（遮住「•••」）；分類格是 nil
    var amountText: String?
    var icon: String
    var tint: UInt32
    var categoryKey: String
    /// 範本那一格才有
    var template: WatchTemplate?
}

/// 記一筆第一步（記帳台）
struct RecordDesk: Equatable {
    enum Mode: Equatable {
        /// 手錶上還沒有 iPhone 的包
        case noPackage
        /// iPhone 設定把「送到手錶：錢」關掉了（手錶上不能記帳）
        case moneyOff
        /// 包裡沒有分類（iPhone 的 LifeGood 很久沒打開）
        case noDesk
        case normal
    }

    var mode: Mode
    /// 頂上那一行「還能花 NT$2.4萬・今天 0 筆」
    var header: String
    /// 最多 4 格：範本（次數多到少）→ 不夠用最常記的分類補
    var tiles: [RecordDeskTile]
    /// 範本不到 4 個：「同一筆記 3 次，就會出現在這裡」
    var hint: String?
    /// noPackage／moneyOff／noDesk 的說明
    var message: String?
}

/// 記一筆第二步之一（選分類）
struct RecordCategoryChoices: Equatable {
    /// 2×2：最常記的 4 個（11～14 點、17～20 點「飲食」排第一）
    var top: [WatchCategory]
    /// 「其他分類 ›」往下捲的那幾個（照 iPhone 分類的順序）
    var others: [WatchCategory]
    /// 加綠框的那一個（吃飯時間的「飲食」）；nil＝不加
    var highlightKey: String?
}

/// 記一筆第二步之二（金額頁一打開的樣子）
struct RecordAmountSetup: Equatable {
    var categoryKey: String
    /// 頁首「飲食・午餐」（沒有常寫的名稱：「飲食」）
    var title: String
    /// 送 iPhone 的名稱「午餐」；nil＝iPhone 用分類名
    var recordTitle: String?
    /// 一打開的金額（這個分類上次的金額；沒記過＝0，〔記下來〕先不能按）
    var initialAmount: Int
    /// 膠囊：這個分類最近 3 個不同金額（新到舊）；[v6] 外幣時是這趟最近記過的原幣金額
    var recent: [Int]
    /// [v6] 旅途中外幣（nil＝台幣）：金額、膠囊、錶冠都是原幣，下面一行「≈ NT$412（0.0229）」
    var currency: WatchCurrency? = nil
    /// [v6] 旅途中：記到哪裡（「📍 記到 弘大 ›」；nil＝不在旅途中，不畫那一行）
    var target: WatchTripRecordTarget? = nil
}

/// 今天記的帳的一列
struct RecordTodayRow: Equatable, Identifiable {
    var id: UUID
    /// 「午餐」
    var title: String
    /// 「12:10・NT$180」（遮住「12:10・NT$ ••••」）
    var detail: String
    var icon: String
    /// 手錶記的（後面畫 ⌚︎ applewatch）
    var fromWatch: Bool
    /// 還在手錶待送盒的：「等著送」「在 iPhone 等著入帳」「在 iPhone 上被刪掉了」（整列灰）；iPhone 帳本裡的是 nil
    var pendingNote: String?
}

/// 今天記的帳（第二層清單）
struct RecordTodayList: Equatable {
    /// 段頭「今天 NT$300・3 筆」（遮住「今天 3 筆」）；沒有錢的快照是 nil
    var header: String?
    var rows: [RecordTodayRow]
    /// 一列都沒有：「今天還沒記帳」
    var empty: String?
}

enum RecordText {
    // MARK: 常數與固定的字

    /// 數字鍵最多打到這麼大（6 位數）
    static let maxAmount = 999_999
    /// 同一格這麼多秒內再點不算（iPhone 收件匣也擋，QuickRecordInbox.doubleTapWindow）
    static let doubleTapSeconds: TimeInterval = 3
    /// 範本不到 4 個時最下面那一行
    static let deskHint = "同一筆記 3 次，就會出現在這裡"
    static let noPackageMessage = "還沒收到 iPhone 的資料・打開 iPhone 上的 LifeGood 一次"
    static let moneyOffMessage = "iPhone 設定把「送到手錶：錢」關掉了，手錶上不能記帳"
    static let noDeskMessage = "打開 iPhone 上的 LifeGood 一次，記帳台才有東西"
    static let crownHint = "轉錶冠調金額"
    static let todayFooter = "要改、要刪，請到 iPhone"
    static let todayEmpty = "今天還沒記帳"
    /// 格子裡遮住的金額
    static let tileMask = "•••"
    /// 「轉錶冠調金額」只在前幾次出現（手錶 App Group 的 UserDefaults 計次）
    static let crownHintKey = "watch_crown_hint_count"
    static let crownHintTimes = 3
    /// 範本、最常記的分類都不夠時，依序補這幾個（同 iPhone WidgetMoneyExtras.fallbackCategories 的前四個概念）
    static let fallbackCategoryKeys = ["飲食", "交通", "購物", "日用品"]
    /// 吃飯時間「飲食」排第一、加綠框
    static let mealCategoryKey = "飲食"

    // MARK: 金額（錶冠、數字鍵）

    /// 錶冠轉的是「金額清單的第幾格」，步距一定對（judge §2.6）：
    /// 0、5…200（每格 5）、210…2,000（10）、2,100…10,000（100）、10,500…100,000（500）
    static let amountSteps: [Int] = makeSteps()

    static func makeSteps() -> [Int] {
        var out: [Int] = []
        var v = 0
        while v <= 200 {
            out.append(v)
            v += 5
        }
        v = 210
        while v <= 2_000 {
            out.append(v)
            v += 10
        }
        v = 2_100
        while v <= 10_000 {
            out.append(v)
            v += 100
        }
        v = 10_500
        while v <= 100_000 {
            out.append(v)
            v += 500
        }
        return out
    }

    /// 這個金額在清單第幾格：清單上「≤ 它」的最後一格（187 → 185 那一格；超過 100,000 → 最後一格；負的 → 0）
    static func stepIndex(for amount: Int) -> Int {
        let steps = amountSteps
        var lo = 0
        var hi = steps.count - 1
        if amount <= steps[lo] { return 0 }
        if amount >= steps[hi] { return hi }
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if steps[mid] <= amount {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        return lo
    }

    /// 錶冠那一格的金額（超出範圍夾回來）
    static func stepAmount(at index: Int) -> Int {
        let steps = amountSteps
        return steps[min(max(index, 0), steps.count - 1)]
    }

    /// 「1,200」（每三位一個逗號；不靠語系）
    static func grouped(_ n: Int) -> String {
        let digits = String(abs(n))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 {
                out += ","
            }
            out.append(ch)
        }
        return n < 0 ? "-" + out : out
    }

    /// 「NT$1,200」（送 iPhone 的 amountText、記好了那一行）
    static func amountText(_ n: Int) -> String {
        "NT$" + grouped(n)
    }

    /// 數字鍵按一個數字：「18」按 0 →「180」；超過 6 位數不變
    static func padAppend(_ current: Int, digit: Int) -> Int {
        let next = current * 10 + digit
        return next > maxAmount ? current : next
    }

    /// 數字鍵按「00」
    static func padAppendDoubleZero(_ current: Int) -> Int {
        padAppend(padAppend(current, digit: 0), digit: 0)
    }

    /// 數字鍵按 ⌫
    static func padBackspace(_ current: Int) -> Int {
        current / 10
    }

    // MARK: 記帳台（第一步）

    /// 記帳台頂上那一行：抬手「還能花 NT$2.4萬・今天 0 筆」／超支「已超支 NT$3,200・今天 4 筆」／
    /// 沒收入「本月支出 NT$6.1萬・今天 3 筆」；遮住「已花 72%・今天 0 筆」（沒收入只寫「今天 3 筆」）
    static func deskHeader(day: WidgetMoneyDay?, masked: Bool) -> String {
        guard let d = day else { return "記一筆" }
        let countText = "今天 \(d.todayCount ?? 0) 筆"
        if masked {
            guard d.state != .noIncome, let m = d.masked else { return countText }
            return "已花 " + m.hero + "・" + countText
        }
        switch d.state {
        case .normal:
            return "還能花 " + d.hero + "・" + countText
        case .over:
            return "已超支 " + d.hero + "・" + countText
        case .noIncome:
            return "本月支出 " + d.hero + "・" + countText
        }
    }

    /// 範本格右上角的數字「55」（iPhone 組好的「NT$55」拿掉 NT$）；遮住「•••」
    static func tileAmount(_ t: WatchTemplate, masked: Bool) -> String {
        if masked { return tileMask }
        let text = t.amountText
        if text.hasPrefix("NT$") { return String(text.dropFirst(3)) }
        return text
    }

    static func desk(package: WatchPackage?, now: Date, masked: Bool) -> RecordDesk {
        guard let package else {
            return RecordDesk(mode: .noPackage, header: "記一筆", tiles: [], hint: nil, message: noPackageMessage)
        }
        guard let money = package.money else {
            return RecordDesk(mode: .moneyOff, header: "記一筆", tiles: [], hint: nil, message: moneyOffMessage)
        }
        let header = deskHeader(day: money.day(at: now), masked: masked)
        let categories = money.categories ?? []
        guard !categories.isEmpty else {
            return RecordDesk(mode: .noDesk, header: header, tiles: [], hint: nil, message: noDeskMessage)
        }
        var tiles: [RecordDeskTile] = []
        let templates = (money.templates ?? []).filter { WatchCategoryRule.isAllowed($0.categoryKey) }
        for t in templates.prefix(4) {
            tiles.append(RecordDeskTile(id: "t-" + t.id, kind: .template, title: t.title,
                                        amountText: tileAmount(t, masked: masked), icon: t.icon, tint: t.tint,
                                        categoryKey: t.categoryKey, template: t))
        }
        let keys = (money.topCategoryKeys ?? []) + fallbackCategoryKeys
        for key in keys where tiles.count < 4 {
            guard let c = categories.first(where: { $0.key == key }) else { continue }
            let id = "c-" + c.key
            if tiles.contains(where: { $0.id == id }) { continue }
            tiles.append(RecordDeskTile(id: id, kind: .category, title: c.title, amountText: nil, icon: c.icon,
                                        tint: c.tint, categoryKey: c.key, template: nil))
        }
        let hint: String? = templates.count < 4 ? deskHint : nil
        return RecordDesk(mode: .normal, header: header, tiles: tiles, hint: hint, message: nil)
    }

    // MARK: 選分類（第二步之一）

    static func categoryChoices(package: WatchPackage?, now: Date, calendar: Calendar) -> RecordCategoryChoices {
        let categories = package?.money?.categories ?? []
        var top: [WatchCategory] = []
        let keys = (package?.money?.topCategoryKeys ?? []) + fallbackCategoryKeys
        for key in keys where top.count < 4 {
            guard let c = categories.first(where: { $0.key == key }) else { continue }
            if top.contains(where: { $0.key == c.key }) { continue }
            top.append(c)
        }
        var highlight: String? = nil
        let hour = calendar.component(.hour, from: now)
        let mealTime = (hour >= 11 && hour <= 14) || (hour >= 17 && hour <= 20)
        if mealTime, let food = categories.first(where: { $0.key == mealCategoryKey }) {
            top.removeAll { $0.key == mealCategoryKey }
            top.insert(food, at: 0)
            if top.count > 4 {
                top.removeLast()
            }
            highlight = mealCategoryKey
        }
        let others = categories.filter { c in !top.contains(where: { $0.key == c.key }) }
        return RecordCategoryChoices(top: top, others: others, highlightKey: highlight)
    }

    // MARK: 金額頁（第二步之二）

    /// 這個分類最近 3 個不同金額：先用這個時段的（「飲食@11-14」），不夠再用整天的（「飲食」）補；
    /// 不是 1…999,999 的整數丟掉
    static func recentAmounts(categoryKey: String, package: WatchPackage?, now: Date, calendar: Calendar) -> [Int] {
        let slotKey = WatchTimeSlot.amountKey(category: categoryKey,
                                              slot: WatchTimeSlot.key(for: now, calendar: calendar))
        let slotList: [Double] = package?.recentAmounts?[slotKey] ?? []
        let dayList: [Double] = package?.recentAmounts?[categoryKey] ?? []
        var out: [Int] = []
        for v in slotList + dayList {
            // 先在 Double 上夾範圍再轉 Int：舊錶（S8／SE2／Ultra1，arm64_32）的 Int 只有 32 位，
            // iPhone 那邊沒有上限（一筆 30 億的帳）直接 Int(…) 會當掉（judge §7.8-4）
            guard v.isFinite else { continue }
            let whole = v.rounded()
            guard whole >= 1, whole <= Double(maxAmount) else { continue }
            let n = Int(whole)
            guard !out.contains(n) else { continue }
            out.append(n)
            if out.count == 3 { break }
        }
        return out
    }

    /// 這個分類在這個時段最常寫的名稱（iPhone 算好的；時段 WatchTimeSlot）
    static func hintTitle(categoryKey: String, package: WatchPackage?, now: Date, calendar: Calendar) -> String? {
        let slot = WatchTimeSlot.key(for: now, calendar: calendar)
        guard let t = package?.titleHints?[categoryKey]?[slot] else { return nil }
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func categoryTitle(_ key: String, package: WatchPackage?) -> String {
        package?.money?.categories?.first(where: { $0.key == key })?.title ?? key
    }

    static func amountSetup(categoryKey: String, package: WatchPackage?, now: Date,
                            calendar: Calendar) -> RecordAmountSetup {
        let catTitle = categoryTitle(categoryKey, package: package)
        let hint = hintTitle(categoryKey: categoryKey, package: package, now: now, calendar: calendar)
        let title = hint.map { catTitle + "・" + $0 } ?? catTitle
        let recent = recentAmounts(categoryKey: categoryKey, package: package, now: now, calendar: calendar)
        return RecordAmountSetup(categoryKey: categoryKey, title: title, recordTitle: hint,
                                 initialAmount: recent.first ?? 0, recent: recent)
    }

    // MARK: 做一筆

    /// 一按就記（範本）：範本編號照帶（iPhone 收件匣 3 秒內同一顆只記一筆）
    static func record(template t: WatchTemplate, now: Date) -> WatchRecord {
        WatchRecord(id: UUID(), createdAt: now, templateId: t.id, title: t.title, amountTWD: t.amount,
                    amountText: t.amountText, categoryKey: t.categoryKey, vehicleId: t.vehicleId,
                    vehicleCategoryKey: t.vehicleCategoryKey)
    }

    /// 選分類＋金額：沒有範本編號（iPhone 填「watch.<編號>」，每筆都不一樣）
    static func record(categoryKey: String, title: String?, amount: Int, now: Date) -> WatchRecord {
        WatchRecord(id: UUID(), createdAt: now, templateId: nil, title: title, amountTWD: Double(amount),
                    amountText: amountText(amount), categoryKey: categoryKey, vehicleId: nil, vehicleCategoryKey: nil)
    }

    // MARK: [v6] 旅途中

    /// 記帳台（旅途中）：外幣時換成這趟常用 4 個分類（範本不出現）、最下面「在國外：記帳台換成這趟常用的分類」；
    /// 沒有匯率時最下面寫「要記韓元：到 iPhone 設定加「韓元」匯率」；不在旅途中（trip nil）照 v2
    static func desk(package: WatchPackage?, now: Date, masked: Bool, trip: WatchTripRecordContext?) -> RecordDesk {
        var out = desk(package: package, now: now, masked: masked)
        guard out.mode == .normal, let trip else { return out }
        guard trip.currency != nil else {
            if let missing = trip.missingCurrencyLabel {
                out.hint = WatchTripText.missingRateHint(missing)
            }
            return out
        }
        let categories = package?.money?.categories ?? []
        var tiles: [RecordDeskTile] = []
        for key in trip.topCategoryKeys + fallbackCategoryKeys where tiles.count < 4 {
            guard let c = categories.first(where: { $0.key == key }) else { continue }
            let id = "c-" + c.key
            if tiles.contains(where: { $0.id == id }) { continue }
            tiles.append(RecordDeskTile(id: id, kind: .category, title: c.title, amountText: nil, icon: c.icon,
                                        tint: c.tint, categoryKey: c.key, template: nil))
        }
        out.tiles = tiles
        out.hint = WatchTripText.foreignDeskHint
        return out
    }

    /// 金額頁（旅途中）：記到哪裡；外幣時膠囊＝這趟最近記過的（手錶待送盒裡同幣別還沒入帳的排前面）、一打開是第一個
    static func tripAmountSetup(categoryKey: String, package: WatchPackage?, now: Date, calendar: Calendar,
                                trip: WatchTripRecordContext, target: WatchTripRecordTarget,
                                items: [WatchOutboxItem]) -> RecordAmountSetup {
        var setup = amountSetup(categoryKey: categoryKey, package: package, now: now, calendar: calendar)
        setup.target = target
        guard let c = trip.currency else { return setup }
        let recent = tripRecent(trip: trip, currency: c, items: items)
        setup.currency = c
        setup.recent = recent
        setup.initialAmount = recent.first ?? 0
        return setup
    }

    /// 這趟最近記過的原幣金額：手錶待送盒裡同幣別的（新到舊）＋包裡這趟的；不重複、最多 3 個
    static func tripRecent(trip: WatchTripRecordContext, currency c: WatchCurrency, items: [WatchOutboxItem]) -> [Int] {
        var out: [Int] = []
        let local = items.sorted { a, b in a.record.createdAt > b.record.createdAt }
        for item in local where item.record.currencyCode == c.code {
            guard let v = item.record.foreignAmount, v.isFinite, v >= 1,
                  v <= Double(WatchTripText.maxForeignAmount) else { continue }
            let n = Int(v.rounded())
            if !out.contains(n) { out.append(n) }
            if out.count == 3 { return out }
        }
        for n in trip.recentAmounts where !out.contains(n) {
            out.append(n)
            if out.count == 3 { break }
        }
        return out
    }

    /// 一按就記（旅途中）：照 v2＋記到哪一趟、哪一站（範本是台幣，國內旅行才會出現在記帳台）
    static func record(template t: WatchTemplate, now: Date, target: WatchTripRecordTarget?) -> WatchRecord {
        var r = record(template: t, now: now)
        r.tripPlanId = target?.planId
        r.tripStopId = target?.stopId
        return r
    }

    /// 選分類＋金額（旅途中）：外幣時 amount 是原幣（₩18,000）、台幣用手錶上看到的換算（WatchTripText.twdAmount，入帳不重算）；
    /// 沒有幣別照 v2 的台幣
    static func record(categoryKey: String, title: String?, amount: Int, now: Date, currency: WatchCurrency?,
                       target: WatchTripRecordTarget?) -> WatchRecord {
        var r: WatchRecord
        if let c = currency {
            let twd = WatchTripText.twdAmount(amount, c)
            r = WatchRecord(id: UUID(), createdAt: now, templateId: nil, title: title, amountTWD: Double(twd),
                            amountText: WatchTripText.foreignText(amount, c), categoryKey: categoryKey,
                            vehicleId: nil, vehicleCategoryKey: nil)
            r.currencyCode = c.code
            r.foreignAmount = Double(amount)
            r.rateShown = c.rateToTWD
        } else {
            r = record(categoryKey: categoryKey, title: title, amount: amount, now: now)
        }
        r.tripPlanId = target?.planId
        r.tripStopId = target?.stopId
        return r
    }

    /// 金額那一段：台幣「NT$180」；外幣「₩18,000 ≈ NT$412」；遮住「•••」
    static func tripAmountPart(_ r: WatchRecord, masked: Bool) -> String {
        if masked { return tileMask }
        guard r.currencyCode != nil else { return r.amountText }
        let twd = r.amountTWD.isFinite ? min(max(r.amountTWD, 0), Double(WatchTripText.maxTWD)) : 0
        return r.amountText + " ≈ NT$" + grouped(Int(twd.rounded()))
    }

    /// 記好了那一行（旅途中）：「韓國炸雞 ₩18,000 ≈ NT$412・記到 弘大」；遮住「韓國炸雞 •••・記到 弘大」
    static func tripDoneLine(_ r: WatchRecord, package: WatchPackage?, masked: Bool,
                             target: WatchTripRecordTarget?) -> String {
        let base = recordName(r, package: package) + " " + tripAmountPart(r, masked: masked)
        guard let target else { return base }
        return base + "・" + WatchTripText.targetLine(target)
    }

    /// 記帳台橫幅（旅途中、一按就記）：「已記 早餐 NT$65・記到 竹北老街」；遮住「已記 早餐 •••・記到 竹北老街」
    static func tripBannerText(_ r: WatchRecord, package: WatchPackage?, masked: Bool,
                               target: WatchTripRecordTarget?) -> String {
        "已記 " + tripDoneLine(r, package: package, masked: masked, target: target)
    }

    /// 這筆叫什麼（沒有名稱用分類名）
    static func recordName(_ r: WatchRecord, package: WatchPackage?) -> String {
        if let t = r.title, !t.isEmpty { return t }
        return categoryTitle(r.categoryKey, package: package)
    }

    /// 3 秒內同一格已經記過（待送盒裡同一個範本編號、按下去的時間差 < 3 秒）
    static func isDoubleTap(templateId: String, at now: Date, in items: [WatchOutboxItem]) -> Bool {
        items.contains { item in
            item.record.templateId == templateId
                && abs(now.timeIntervalSince(item.record.createdAt)) < doubleTapSeconds
        }
    }

    // MARK: 記好了（第三步、記帳台橫幅）

    /// 記帳台橫幅「已記 早餐 NT$65」（前面的 ✓ 是圖示）；遮住「已記 早餐 •••」
    static func bannerText(_ r: WatchRecord, package: WatchPackage?, masked: Bool) -> String {
        "已記 " + recordName(r, package: package) + " " + (masked ? tileMask : r.amountText)
    }

    /// 記好了那一頁第二行「午餐 NT$180・12:10」；遮住「午餐 NT$ ••••・12:10」
    static func doneLine(_ r: WatchRecord, package: WatchPackage?, masked: Bool) -> String {
        let amount = masked ? WidgetHideAmounts.mask : r.amountText
        return recordName(r, package: package) + " " + amount + "・" + DayTimelineFormat.time(r.createdAt)
    }

    /// 狀態行
    static func statusLine(_ s: RecordSendState) -> String {
        switch s {
        case .holding:
            return "10 秒內可以復原"
        case .waiting:
            return "正在送到 iPhone…"
        case .imported(let today):
            guard let n = today else { return "已送到 iPhone" }
            return "已送到 iPhone・今天 \(n) 筆"
        case .queued:
            return "已收到，打開 iPhone 上的 LifeGood 後入帳"
        case .offline(let count):
            return "還沒送到 iPhone，先存在手錶上（\(count) 筆）"
        }
    }

    /// 狀態行下面那一行小字
    static func statusNote(_ s: RecordSendState) -> String? {
        switch s {
        case .imported:
            return "錶面的「已花」幾分鐘內跟上"
        case .offline:
            return "iPhone 在旁邊時自己補送"
        case .holding, .waiting, .queued:
            return nil
        }
    }

    /// 記帳台橫幅過了 10 秒換成的短字（2.5 秒後收起來）
    static func bannerStatus(_ s: RecordSendState) -> String? {
        switch s {
        case .holding, .waiting:
            return nil
        case .imported(let today):
            guard let n = today else { return "已送到 iPhone" }
            return "已送到 iPhone・今天 \(n) 筆"
        case .queued:
            return "已收到，打開 iPhone 後入帳"
        case .offline(let count):
            return "先存在手錶上（\(count) 筆）"
        }
    }

    /// App 重開過、手上只有檔裡的狀態時推回去（記好了那一頁還開著的少數情況）
    static func sendState(for item: WatchOutboxItem, unsent: Int) -> RecordSendState {
        switch item.state {
        case .holding: return .holding
        case .sent: return .offline(count: unsent)
        case .delivered, .queued: return .queued
        case .imported: return .imported(today: nil)
        case .deleted: return .imported(today: nil)
        }
    }

    // MARK: 待送盒的數字

    /// 還沒送到 iPhone 的（設定「還沒送到 iPhone：N 筆」）
    static func unsentCount(_ items: [WatchOutboxItem]) -> Int {
        items.filter { $0.isUnsent }.count
    }

    /// ② 錢「剛記的 N 筆還沒算進去」：待送盒裡（不含在 iPhone 上被刪掉的）還不在新包 includedIds 的。0 筆＝nil
    static func notCountedLine(package: WatchPackage?, items: [WatchOutboxItem]) -> String? {
        let included = Set(package?.includedIds ?? [])
        let n = items.filter { $0.state != .deleted && !included.contains($0.id) }.count
        return n > 0 ? "剛記的 \(n) 筆還沒算進去" : nil
    }

    /// 設定第一行（0 筆＝nil，整行不出現）
    static func unsentLine(_ items: [WatchOutboxItem]) -> String? {
        let n = unsentCount(items)
        return n > 0 ? "還沒送到 iPhone：\(n) 筆" : nil
    }

    // MARK: 今天記的帳（第二層，judge §2.7）

    /// 待送盒那一筆的灰字
    static func pendingNote(_ state: WatchOutboxItem.State) -> String? {
        switch state {
        case .holding, .sent: return "等著送"
        case .delivered, .queued: return "在 iPhone 等著入帳"
        case .imported: return nil
        case .deleted: return "在 iPhone 上被刪掉了"
        }
    }

    /// 待送盒那一筆的圖示：範本的圖示 → 分類的圖示 → 「其他」
    static func icon(for r: WatchRecord, package: WatchPackage?) -> String {
        if let tid = r.templateId, let t = package?.money?.templates?.first(where: { $0.id == tid }) {
            return t.icon
        }
        if let c = package?.money?.categories?.first(where: { $0.key == r.categoryKey }) {
            return c.icon
        }
        return "ellipsis.circle.fill"
    }

    static func rowDetail(time: Date, amountText: String, masked: Bool) -> String {
        DayTimelineFormat.time(time) + "・" + (masked ? WidgetHideAmounts.mask : amountText)
    }

    /// iPhone 帳本裡今天的（包的 todayRecords）＋手錶待送盒裡今天記、還不在那一份裡的；新到舊（同一刻編號字串小的先）
    static func todayList(package: WatchPackage?, items: [WatchOutboxItem], now: Date, calendar: Calendar,
                          masked: Bool) -> RecordTodayList {
        var header: String? = nil
        if let d = package?.money?.day(at: now) {
            let t = d.lines(hidden: masked).todayText
            header = t.isEmpty ? nil : t
        }
        let phoneRows = package?.todayRecords ?? []
        let phoneIds = Set(phoneRows.map { $0.id })
        var rows: [(time: Date, row: RecordTodayRow)] = []
        // 包可能是昨天組的（iPhone 昨晚之後沒開 LifeGood）：只列跟現在同一天的——過了午夜不把昨天記的當成今天
        //（段頭跟著 money.day(at:) 換成「今天 還沒花錢」，這裡也要一致）
        for r in phoneRows where calendar.isDate(r.time, inSameDayAs: now) {
            let row = RecordTodayRow(id: r.id, title: r.title,
                                     detail: rowDetail(time: r.time, amountText: r.amountText, masked: masked),
                                     icon: r.icon, fromWatch: r.fromWatch, pendingNote: nil)
            rows.append((time: r.time, row: row))
        }
        for item in items where !phoneIds.contains(item.id) {
            let r = item.record
            guard calendar.isDate(r.createdAt, inSameDayAs: now) else { continue }
            let row = RecordTodayRow(id: r.id, title: recordName(r, package: package),
                                     detail: rowDetail(time: r.createdAt, amountText: r.amountText, masked: masked),
                                     icon: icon(for: r, package: package), fromWatch: true,
                                     pendingNote: pendingNote(item.state))
            rows.append((time: r.createdAt, row: row))
        }
        let sorted = rows.sorted { a, b in
            if a.time != b.time { return a.time > b.time }
            return a.row.id.uuidString < b.row.id.uuidString
        }
        let list = sorted.map { $0.row }
        return RecordTodayList(header: header, rows: list, empty: list.isEmpty ? todayEmpty : nil)
    }
}
