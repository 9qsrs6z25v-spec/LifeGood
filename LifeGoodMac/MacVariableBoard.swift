// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.642 mac3 G2] 變動支出頁的統計、表格的列、拷貝的字（只 import Foundation；judge_mac §Q7 ①～⑬、§Q8；brief §2 G2 第 1～8 條）。
//
// • ①⑤⑥⑦⑧⑨ 照抄 iOS（48c51a2）：從 proto/MacVariableBoard_proto.swift 拿來，一個 token 都不改（keycheck 照抄比對）；
//   只准 Date()→now、Calendar.current→calendar、store.→money.、店同額／同時間 Mac 補（shopOrder、newerFirst）。
// • ②③④ 看板的字、⑪ 一天一組、⑫ 金額字、⑬ 付款字：iOS 回的是 Text／View，照字面值＋sim_mac3.py 行為寫（board#2～#4、table#11～#13）。
// • 列（MacVariableRow）全 let，顯示字建列時算好；排序自己寫（不用 Foundation 的排序 API），同值照 id。
// • 拷貝（⌘C）白名單組字：日期時間、項目、分類、金額、付款、地點、備註；不帶同行、收受人、分帳、我的份。
// • 這個檔不寫 store、不碰 records、不讀存摺；不叫總覽那兩支統計（含固定日均、沒併五家）。
import Foundation

/// 「花在哪裡」一列（照 iPhone 市集的店：一個分類一家）
struct MacVariableShop: Identifiable {
    let category: VariableCategory
    let amount: Double
    let share: Double

    var id: String { category.rawValue }
}

// 照抄 MoneyBoards.swift:185-207（48c51a2）VariableBoardData（shops 換成 MacVariableShop）
struct MacVariableBoardData {
    var month = 1
    var day = 1
    var total: Double = 0
    var count = 0
    var today: Double = 0
    var todayCount = 0
    var samePeriodAvg: Double? = nil
    var shops: [MacVariableShop] = []
    var largestTitle: String? = nil
    var largestAmount: Double = 0
    var topPlace: String? = nil
    var topPlaceCount = 0
    var noSpendDays = 0
    var splitNote: String? = nil

    var dailyAvg: Double { total / Double(max(day, 1)) }
}

enum MacVariableBoard {
    // 照抄 MoneyBoards.swift:210-287（48c51a2）VariableBoardData.build — sim3: board#1
    // （store → money、Calendar.current → calendar、店同額 Mac 補照 VariableCategory.allCases：shopOrder）
    @MainActor
    static func build(money: MacMoneyStore, now: Date, calendar: Calendar) -> MacVariableBoardData {
        let cal = calendar
        var d = MacVariableBoardData()
        d.month = cal.component(.month, from: now)
        d.day = cal.component(.day, from: now)
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) else { return d }
        let variables = money.expenses.filter { $0.expenseType == .variable }
        let firstEver = variables.map(\.date).min().map { cal.startOfDay(for: $0) }

        var spentDays = Set<Int>()
        var byCategory: [VariableCategory: Double] = [:]
        var places: [String: Int] = [:]
        var largest: Expense? = nil
        for e in variables where cal.isDate(e.date, equalTo: now, toGranularity: .month) {
            d.total += money.ownAmount(e)
            d.count += 1
            if cal.isDate(e.date, inSameDayAs: now) {
                d.today += money.ownAmount(e)
                d.todayCount += 1
            }
            spentDays.insert(cal.component(.day, from: e.date))
            byCategory[e.variableCategory ?? .other, default: 0] += money.ownAmount(e)
            if let p = e.placeName?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
                places[p, default: 0] += 1
            }
            if e.amount > (largest?.amount ?? 0) { largest = e }
        }
        if let largest {
            d.largestTitle = MacVariableText.short(MacVariableText.title(largest), max: 10)
            d.largestAmount = largest.amount
        }
        if let top = places.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }),
           top.value >= 2 {
            d.topPlace = MacVariableText.short(top.key)
            d.topPlaceCount = top.value
        }

        // 店：「其他」固定排最後；有名字的分類超過四類（有「其他」時）或五類，後面的併進「其他」
        if d.total > 0 {
            let named = byCategory.filter { $0.key != .other }.sorted { MacVariableBoard.shopOrder($0, $1) }
            var otherSum = byCategory[.other] ?? 0
            let room = otherSum > 0 ? 4 : 5
            var kept = named
            if named.count > room {
                kept = Array(named.prefix(4))
                otherSum += named.dropFirst(4).reduce(0) { $0 + $1.value }
            }
            var shops = kept.map {
                MacVariableShop(category: $0.key, amount: $0.value, share: $0.value / d.total)
            }
            if otherSum > 0 {
                shops.append(MacVariableShop(category: .other, amount: otherSum, share: otherSum / d.total))
            }
            d.shops = shops
        }

        // 無消費：從這個月開始記帳的那一天起，到昨天
        if let firstEver {
            let firstDay = firstEver < monthStart ? 1 : cal.component(.day, from: firstEver)
            if firstDay < d.day {
                d.noSpendDays = (firstDay..<d.day).filter { !spentDays.contains($0) }.count
            }
        }

        // 近 3 個月同期
        var sums: [Double] = []
        for back in 1...3 {
            guard let m = cal.date(byAdding: .month, value: -back, to: monthStart),
                  let firstEver, firstEver <= m else { continue }
            let mDays = cal.range(of: .day, in: .month, for: m)?.count ?? 30
            guard let cut = cal.date(byAdding: .day, value: min(d.day, mDays), to: m) else { continue }
            sums.append(variables.filter { $0.date >= m && $0.date < cut }.reduce(0) { $0 + money.ownAmount($1) })
        }
        d.samePeriodAvg = sums.isEmpty ? nil : sums.reduce(0, +) / Double(sums.count)
        // [v25.634] C8：這個月因為分帳扣掉的（要還我，已還、沒還都算）；沒用分帳＝0 → nil
        d.splitNote = MacVariableText.statsNote(money.splitIndex.deducted(expenses: variables, month: now, calendar: cal))
        return d
    }

    /// 店的順序：金額大到小；同額照 VariableCategory.allCases（iOS 是字典順序、沒定；Mac 補）
    static func shopOrder(_ a: (key: VariableCategory, value: Double), _ b: (key: VariableCategory, value: Double)) -> Bool {
        if a.value != b.value { return a.value > b.value }
        let order = VariableCategory.allCases
        return (order.firstIndex(of: a.key) ?? order.count) < (order.firstIndex(of: b.key) ?? order.count)
    }
}

enum MacVariableText {
    // 照抄 MoneyBoards.swift:108-111（48c51a2）MoneyBoardText.short — sim3: text#5
    /// 膠囊、牌子上的名字：太長就截掉
    static func short(_ s: String, max n: Int = 8) -> String {
        s.count > n ? String(s.prefix(n - 1)) + "…" : s
    }

    // 照抄 MoneyItemCard.swift:843-846（48c51a2）MoneyItem.title — sim3: text#6（moneyTrimmed＝.whitespacesAndNewlines）
    /// 名稱：使用者打的名字照用；沒打名字才退到地點名、備註或分類名
    static func title(_ e: Expense) -> String {
        let t = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? e.stopRowLabel(suppressing: []).primary : t
    }

    // 照抄 ExpenseSplits.swift:1217-1230（48c51a2）ExpenseSplitText.ntd
    /// 「NT$1,500」：四捨五入到元（.5 進位）、千分位
    static func ntd(_ v: Double) -> String {
        guard v.isFinite, abs(v) < 1e15 else { return "NT$0" }
        let r = Int(abs(v).rounded(.toNearestOrAwayFromZero))
        let digits = String(r)
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return (v < 0 && r > 0 ? "-" : "") + "NT$" + out
    }

    // 照抄 ExpenseSplits.swift:1385-1387（48c51a2）ExpenseSplitText.statsNote — sim3: text#7
    /// 統計說明小字（這個月有扣才出現）
    static func statsNote(_ deducted: Double) -> String? {
        deducted >= 0.5 ? "有分帳的飯只算你自己那份：這個月扣掉要還你的 \(ntd(deducted))。" : nil
    }
}

enum MacVariableTable {
    // 照抄 ExpenseStore.swift:417-421（48c51a2）variableExpenses — sim3: table#8（同時間 Mac 補照 id 字串：newerFirst）
    static func variableExpenses(_ expenses: [Expense]) -> [Expense] {
        expenses
            .filter { $0.expenseType == .variable }
            .sorted { MacVariableTable.newerFirst($0, $1) }
    }

    /// 新到舊；同時間照 id 字串（iOS 沒定，Mac 補，同 Mac 2）
    static func newerFirst(_ a: Expense, _ b: Expense) -> Bool {
        if a.date != b.date { return a.date > b.date }
        return a.id.uuidString < b.id.uuidString
    }

    // 照抄 VariableExpenseView.swift:113-122（48c51a2）搜尋 10 欄 — sim3: table#9（q 已經 .whitespaces＋lowercased()）
    static func matches(_ exp: Expense, query q: String, kinds: MacKindIndex) -> Bool {
        exp.title.lowercased().contains(q)
            || exp.note.lowercased().contains(q)
            || exp.categoryName.lowercased().contains(q)
            || exp.macDisplayCategoryName(kinds: kinds).lowercased().contains(q)
            || (exp.placeAddress?.lowercased().contains(q) ?? false)
            || (exp.placeName?.lowercased().contains(q) ?? false)
            || (exp.diningMember?.lowercased().contains(q) ?? false)
            || (exp.socialRecipient?.lowercased().contains(q) ?? false)
            || (exp.taxSavingSubCategory?.rawValue.lowercased().contains(q) ?? false)
            || (exp.socialSubCategory?.rawValue.lowercased().contains(q) ?? false)
    }
}

// MARK: - ②③④ 看板的字（MacVariableHeadline）

/// 看板一顆膠囊（good＝綠字：「還沒花錢」「無消費」）
struct MacVariableChip: Identifiable {
    let label: String
    let value: String
    let good: Bool

    var id: String { label }
}

/// 看板頭：日期行、膠囊、標題、大字、不是本月時那行小字
struct MacVariableHeader {
    let date: String
    let capsule: String
    let label: String
    let big: String
    let note: String?
}

enum MacVariableHeadline {
    // 照抄 MoneyBoards.swift:312-325（48c51a2）VariableBoard.line（iOS 回 Text，這裡回字；X＝WidgetMoneyFormat.percent）— sim3: board#2
    static func line(_ d: MacVariableBoardData) -> String {
        guard let avg = d.samePeriodAvg else {
            return d.total > 0 ? "前幾個月還沒有完整的紀錄可以比" : "這個月還沒有變動支出"
        }
        guard avg > 0 else { return "近 3 個月的同一段時間都沒有花費" }
        let r = d.total / avg - 1
        if abs(r) < 0.01 { return "跟近 3 個月同期差不多" }
        let pct = WidgetMoneyFormat.percent(abs(r))
        if r > 0 {
            return "比近 3 個月同期多 " + pct
        }
        return "比近 3 個月同期少 " + pct
    }

    // 照抄 MoneyBoards.swift:327-350（48c51a2）VariableBoard.chips（順序、出現條件照 iOS）— sim3: board#3
    // Mac 補：current == false（以前／之後的月份）只留〈最大一筆〉〈最常去〉（只看「哪個月」的那幾格；judge_mac §Q8-2）
    static func chips(_ d: MacVariableBoardData, current: Bool) -> [MacVariableChip] {
        var out: [MacVariableChip] = []
        if d.todayCount > 0 {
            out.append(MacVariableChip(label: "今天", value: WidgetMoneyFormat.short(d.today), good: false))
        } else {
            out.append(MacVariableChip(label: "今天", value: "還沒花錢", good: true))
        }
        if d.total > 0 {
            out.append(MacVariableChip(label: "日均", value: WidgetMoneyFormat.short(d.dailyAvg), good: false))
        }
        if let t = d.largestTitle {
            out.append(MacVariableChip(label: "最大一筆", value: t + " " + WidgetMoneyFormat.short(d.largestAmount), good: false))
        }
        if let p = d.topPlace {
            out.append(MacVariableChip(label: "最常去", value: "\(p) ×\(d.topPlaceCount)", good: false))
        }
        if d.noSpendDays > 0 {
            out.append(MacVariableChip(label: "無消費", value: "\(d.noSpendDays) 天", good: true))
        }
        if !current {
            out = out.filter { c in c.label == "最大一筆" || c.label == "最常去" }
        }
        return out
    }

    // 照抄 MoneyBoards.swift:301-304（48c51a2）看板頭（英文招呼 :306 不抄）— sim3: board#4
    // Mac 補：不是本月 → 日期行空、「86 筆」、「10 月變動支出」（不同年「2025 年 10 月變動支出」）＋一行小字
    static func header(_ d: MacVariableBoardData, month: Date, now: Date, calendar: Calendar) -> MacVariableHeader {
        let shown = MacVariableMonth.start(of: month, calendar: calendar)
        let current = MacVariableMonth.start(of: now, calendar: calendar)
        let big = WidgetMoneyFormat.short(d.total)
        if shown == current {
            return MacVariableHeader(date: "\(d.month) 月・第 \(d.day) 天", capsule: "本月 \(d.count) 筆",
                                     label: "本月變動支出", big: big, note: nil)
        }
        let y = calendar.component(.year, from: shown)
        let m = calendar.component(.month, from: shown)
        let label = y == calendar.component(.year, from: now) ? "\(m) 月變動支出" : "\(y) 年 \(m) 月變動支出"
        let note = shown < current ? "以前的月份只顯示合計（iPhone 沒有這一頁）" : "之後的月份只顯示合計（iPhone 沒有這一頁）"
        return MacVariableHeader(date: "", capsule: "\(d.count) 筆", label: label, big: big, note: note)
    }
}

// MARK: - 月份（Mac 補；iPhone 變動頁沒有月份切換）

enum MacVariableMonth {
    /// 那個月 1 號 00:00
    static func start(of d: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: d)) ?? d
    }

    /// sim3: month#3　看板的 now：本月＝now；別的月＝那個月最後一天 23:59:59（只顯示只看「哪個月」的 6 格）
    static func boardNow(month: Date, now: Date, calendar: Calendar) -> Date {
        let m = start(of: month, calendar: calendar)
        guard m != start(of: now, calendar: calendar),
              let next = calendar.date(byAdding: .month, value: 1, to: m) else { return now }
        return next.addingTimeInterval(-1)
    }

    /// 「2026 年 11 月」（副標、空白狀態）
    static func title(_ month: Date, calendar: Calendar) -> String {
        "\(calendar.component(.year, from: month)) 年 \(calendar.component(.month, from: month)) 月"
    }
}

// MARK: - 表格的列

/// 表格一列（全 let；顯示字建列時算好，Cell 裡不再 format）
struct MacVariableRow: Identifiable {
    let id: MacEntryRef
    let date: Date
    /// 分組「12:30」；平表或搜全部月份「11/23 12:30」（不同年「2025/11/23 12:30」）
    let timeText: String
    /// ⌘C 用「2026/11/23 12:30」
    let copyDate: String
    /// ⑥ 名稱（空的退到地點名、備註或分類名）
    let title: String
    /// 細項說法（「汽車 - 罰款」）
    let category: String
    /// 刷卡金額（排序用）
    let amount: Double
    /// ⑫「NT$480」「USD 4（≈ NT$128）」
    let amountText: String
    /// 你自己那份（排序、組頭、小計用；沒分帳＝amount）
    let mine: Double
    /// 只有活分帳那筆有字
    let mineText: String
    /// ⑬「信用卡」「銀行」「銀行・USD」「—」
    let payText: String
    /// 同行（只顯示；⌘C 不帶）
    let with: String
    /// 地點名（空的用地址）
    let place: String
    /// 備註（跟名稱一樣就空的）
    let note: String
}

typealias MacVariableSort = KeyPathComparator<MacVariableRow>

/// 一天一組（整串一組時 id＝.distantPast）
struct MacVariableDay: Identifiable {
    let id: Date
    let title: String
    let badge: String?
    let summary: String
    let rows: [MacVariableRow]
}

extension MacVariableTable {
    /// 「11/23 週日」的星期（同 MacText 的 DateFormatter：zh_Hant_TW、時區跟著這台 Mac）
    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "EEE"
        return f
    }()

    // 照抄 MoneyItemCard.swift:787-798（48c51a2）付款（先卡後銀行；iPhone 查存摺拿名字，Mac 只寫哪一種）— sim3: table#13
    /// 表格 empty「—」、詳情 empty「不指定」；外幣銀行加「・USD」（同 MacIncomeTable.bankText 的判斷）
    static func payText(_ e: Expense, empty: String) -> String {
        if e.linkedCreditCardMilestoneId != nil { return "信用卡" }
        if e.linkedBankMilestoneId != nil {
            if let code = e.linkedBankCurrency, !code.isEmpty, code != "NT$", code != "TWD" {
                return "銀行・" + code
            }
            return "銀行"
        }
        return empty
    }

    // 照抄 MoneyItemCard.swift:825-838（48c51a2）amountText（外幣＝code＋amount÷今天匯率，0 位小數 halfEven）— sim3: table#12
    /// Mac：台幣完整位數；外幣後面加「（≈ NT$128）」（存的台幣等值）
    static func amountText(_ e: Expense, rates: [CurrencyRate]) -> String {
        let code = e.currencyCode
        guard code != "NT$", code != "TWD", !code.isEmpty else { return MacText.exactMoney(e.amount) }
        let value: Double
        if let rate = rates.first(where: { r in r.code == code })?.rate, rate > 0 {
            value = e.amount / rate
        } else {
            value = e.amount
        }
        return code + " " + WidgetMoneyFormat.number(value, digits: 0) + "（≈ " + MacText.money(e.amount) + "）"
    }

    /// 第一個比較器是時間（或沒有比較器）→ 一天一組
    static func isByTime(_ order: [MacVariableSort]) -> Bool {
        guard let first = order.first else { return true }
        return first.keyPath == \MacVariableRow.date
    }

    /// 照 sortOrder 一個一個比（compare 已照正反），同值照 id 字串（同 Mac 2 MacIncomeTable.sort）
    static func sort(_ rows: [MacVariableRow], by order: [MacVariableSort]) -> [MacVariableRow] {
        rows.sorted { a, b in
            for c in order {
                let r = c.compare(a, b)
                if r == .orderedAscending { return true }
                if r == .orderedDescending { return false }
            }
            return a.id.id < b.id.id
        }
    }

    /// 整串一組的標題「依金額排序」
    static func columnName(_ c: MacVariableSort) -> String {
        if c.keyPath == \MacVariableRow.date { return "時間" }
        if c.keyPath == \MacVariableRow.title { return "項目" }
        if c.keyPath == \MacVariableRow.category { return "分類" }
        if c.keyPath == \MacVariableRow.amount { return "金額" }
        if c.keyPath == \MacVariableRow.mine { return "我的份" }
        if c.keyPath == \MacVariableRow.payText { return "付款" }
        if c.keyPath == \MacVariableRow.with { return "同行" }
        if c.keyPath == \MacVariableRow.place { return "地點" }
        if c.keyPath == \MacVariableRow.note { return "備註" }
        return "點的欄"
    }

    // 照抄 VariableExpenseView.swift:643-653（48c51a2）日分組＋:436-438 組頭（MoneyItemCard.swift:414-470）— sim3: table#11
    // Mac：分組鍵用 calendar.startOfDay(for:)（iOS 用「yyyy-MM-dd」字串，同時區等價）；組頭合計照 iPhone 用刷卡金額，
    // 有分帳扣掉的那天多寫「（你的份 NT$…）」；第一個比較器不是時間 → 整串一組「依金額排序」
    @MainActor
    static func days(money: MacMoneyStore, month: Date, query: String, category: VariableCategory?, searchAll: Bool,
                     order: [MacVariableSort], now: Date, calendar: Calendar) -> [MacVariableDay] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let everyMonth = searchAll && !q.isEmpty
        let kinds = money.kindIndex
        var picked: [Expense] = []
        // table#10 先分類篩 → 月份（搜全部月份＋有字時不看）→ table#9 搜尋
        for e in variableExpenses(money.expenses) {
            if let category, e.variableCategory != category { continue }
            if !everyMonth && !calendar.isDate(e.date, equalTo: month, toGranularity: .month) { continue }
            if !q.isEmpty && !matches(e, query: q, kinds: kinds) { continue }
            picked.append(e)
        }
        let byTime = isByTime(order)
        let grouped = byTime && !everyMonth
        let rows: [MacVariableRow] = picked.map { e in
            row(e, money: money, kinds: kinds, grouped: grouped, now: now, calendar: calendar)
        }
        guard !rows.isEmpty else { return [] }
        if !byTime {
            let sorted = sort(rows, by: order)
            let name = order.first.map { c in columnName(c) } ?? "時間"
            return [MacVariableDay(id: .distantPast, title: "依" + name + "排序", badge: nil, summary: summary(sorted),
                                   rows: sorted)]
        }
        // 天的先後跟著第一個比較器的正反（沒有比較器＝新到舊）
        let newestFirst = order.first.map { c in c.order == .reverse } ?? true
        let dayOrder = order.isEmpty ? [MacVariableSort(\MacVariableRow.date, order: .reverse)] : order
        return group(rows, newestFirst: newestFirst, order: dayOrder, now: now, calendar: calendar)
    }

    /// 一天一組：天的先後照第一個比較器正反、天裡面照 sort(_:by:)
    static func group(_ rows: [MacVariableRow], newestFirst: Bool, order: [MacVariableSort], now: Date,
                      calendar: Calendar) -> [MacVariableDay] {
        var buckets: [Date: [MacVariableRow]] = [:]
        for r in rows {
            buckets[calendar.startOfDay(for: r.date), default: []].append(r)
        }
        let keys: [Date] = buckets.keys.sorted { a, b in newestFirst ? a > b : a < b }
        return keys.map { (k: Date) -> MacVariableDay in
            let rs = sort(buckets[k] ?? [], by: order)
            return MacVariableDay(id: k, title: dayTitle(k, now: now, calendar: calendar),
                                  badge: dayBadge(k, now: now, calendar: calendar), summary: summary(rs), rows: rs)
        }
    }

    /// 一列（建列時把字都算好）
    @MainActor
    static func row(_ e: Expense, money: MacMoneyStore, kinds: MacKindIndex, grouped: Bool, now: Date,
                    calendar: Calendar) -> MacVariableRow {
        let sameYear = calendar.component(.year, from: e.date) == calendar.component(.year, from: now)
        let timeText: String
        if grouped {
            timeText = MacText.time(e.date)
        } else {
            timeText = sameYear ? MacText.dayTime(e.date) : MacText.fullDayTime(e.date)
        }
        let title = MacVariableText.title(e)
        let memo = e.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeName = e.placeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let own = money.ownAmount(e)
        let live = money.splitIndex.liveShares(for: e) != nil
        return MacVariableRow(id: .expense(e.id), date: e.date, timeText: timeText, copyDate: MacText.fullDayTime(e.date),
                              title: title, category: e.macDisplayCategoryName(kinds: kinds), amount: e.amount,
                              amountText: amountText(e, rates: money.rates), mine: own,
                              mineText: live ? MacText.exactMoney(own) : "", payText: payText(e, empty: "—"),
                              with: e.diningMember ?? "", place: placeName.isEmpty ? (e.placeAddress ?? "") : placeName,
                              note: memo == title ? "" : memo)
    }

    /// 組頭「11/23 週日」（不同年「2025/11/23 週日」）
    static func dayTitle(_ day: Date, now: Date, calendar: Calendar) -> String {
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
        return (sameYear ? MacText.day(day) : MacText.fullDay(day)) + " " + weekday.string(from: day)
    }

    /// 組頭膠囊「今天」「昨天」
    static func dayBadge(_ day: Date, now: Date, calendar: Calendar) -> String? {
        if calendar.isDate(day, inSameDayAs: now) { return "今天" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: y) { return "昨天" }
        return nil
    }

    /// 組頭右邊「3 筆・NT$1,340」＋（刷卡合計 − 你的份 ≥ 0.5）「（你的份 NT$1,100）」
    static func summary(_ rows: [MacVariableRow]) -> String {
        let amount = rows.reduce(0.0) { s, r in s + r.amount }
        let own = rows.reduce(0.0) { s, r in s + r.mine }
        var text = "\(rows.count) 筆・" + MacText.exactMoney(amount)
        if amount - own >= 0.5 {
            text += "（你的份 " + MacText.exactMoney(own) + "）"
        }
        return text
    }

    /// 篩選列右邊小計：「86 筆・你的份合計 NT$2.3萬」／有篩選或搜尋「符合 12 筆・你的份合計 NT$240」
    static func subtotal(_ rows: [MacVariableRow], filtering: Bool) -> String {
        let own = rows.reduce(0.0) { s, r in s + r.mine }
        let head = filtering ? "符合 \(rows.count) 筆" : "\(rows.count) 筆"
        return head + "・你的份合計 " + WidgetMoneyFormat.short(own)
    }
}

// MARK: - ⌘C（白名單組字）

/// sim3: copy3#1　一列一行、Tab 分欄、沒有表頭；只讀日期時間、項目、分類、金額、付款、地點、備註
enum MacVariableCopy {
    static func line(_ row: MacVariableRow) -> String {
        [row.copyDate, row.title, row.category, row.amountText, row.payText, row.place, row.note].joined(separator: "\t")
    }

    /// 沒選或選到的不在列裡＝空陣列
    static func lines(selection: MacEntryRef?, days: [MacVariableDay]) -> [String] {
        guard let selection else { return [] }
        for day in days {
            for row in day.rows where row.id == selection {
                return [line(row)]
            }
        }
        return []
    }
}
