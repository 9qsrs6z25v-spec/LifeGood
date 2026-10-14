import Foundation

// MARK: - money 快照的 v2 欄位：分類、最常記的分類、車子卡、常記範本、下個月 1–7 號、隱藏版與鎖定畫面版的字（小工具 v2）
//
// 只屬於「LifeGood」target。由 G1 實作，規格見 scratchpad/widgets/v2/brief.md（G1-2）。
//
// WidgetSnapshotWriter.moneySnapshot 呼叫這裡把 v2 的欄位補進 money_v1.json：
//   • categories：14 個變動分類的名稱、圖示、顏色（記帳台的卡）
//   • topCategoryKeys：近 60 天記最多次的分類（記帳台第 1、2 張卡；沒車時第 3 張）
//   • vehicleCard：記帳台第 3 張「⚡ Taycan 電費」
//   • templates：一按就記的常記範本（同名稱＋同金額＋同分類〔＋同車〕近 60 天 ≥3 次，最多 4 個）
//   • nextMonthBoard：月底之後接的下個月 1–7 號，那一天打開 App 會算出來的 OverviewBoardData
//   • decorate：每一天補上 todayText、todayCount、incomeText、masked（隱藏金額版）、lock（鎖定畫面版）
//
// 規矩跟寫手一樣：只讀不寫任何 store；金額字只用 MoneyFormat.short／percent、ExpenseStore.displayAmountText。
// 輸出必須是「同樣的資料永遠排成同樣的順序」：快照內容沒變就不寫檔、不叫重畫（WidgetSnapshotStore.write），
// 所以字典的順序一律不拿來用，排序都有最後一層穩定的鍵。
//
// @MainActor：MoneyFormat 的 NumberFormatter 只在主執行緒用（跟寫手一樣）。

@MainActor
enum WidgetMoneyExtras {

    /// 「最常記」「常記範本」看近幾天（今天 00:00 往回算，到現在為止）
    static let lookbackDays = 60
    /// 常記範本至少要出現幾次
    static let templateMinCount = 3
    /// 常記範本最多幾個（小工具 2×2）
    static let templateMaxCount = 4
    /// 月底之後接下個月幾天（主控定案 4：每次都寫 1–7 號）
    static let nextMonthDays = 7
    /// 最常記的分類至少要有幾個（記帳台：前兩張＋沒車時的第三張）
    static let minTopCategories = 3

    /// 車子卡、車子範本的青綠（mock_spec ledger-desk-medium、judge §2.4）
    private static let carTop: UInt32 = 0x7FE3D0
    private static let carBottom: UInt32 = 0x1A9C8C
    private static let carTint: UInt32 = 0x138A7E

    /// 最常記的分類不夠時，依序補這幾個（跳過已經有的）
    private static let fallbackCategories: [VariableCategory] = [.food, .shopping, .transportation, .dailyNecessities]

    // MARK: - 分類

    /// 14 個變動分類，照 VariableCategory.allCases 的順序。key＝title＝rawValue（「飲食」），
    /// 顏色是 App 分類卡的那一組（MoneyArtTheme.of）。
    static func categories() -> [WidgetCategory] {
        VariableCategory.allCases.map { (c: VariableCategory) -> WidgetCategory in
            let theme = MoneyArtTheme.of(c)
            return WidgetCategory(key: c.rawValue, title: c.rawValue, icon: c.icon,
                                  top: theme.top, bottom: theme.bottom, tint: theme.tint)
        }
    }

    // MARK: - 車子卡

    /// 記帳台第三張卡。候選＝沒賣掉的車；挑近 60 天記帳（變動支出、連到那台車）筆數最多的那台，
    /// 同數取清單裡前面的。分類＝那台這 60 天最常記的車子分類（同數取 categories(for:) 裡前面的）；
    /// 沒紀錄：電車／電動機車用電費，其他用油錢；不在那台車可用的分類裡就取第一個。
    /// 沒有車回 nil（第三張改放第三多的分類）。
    static func vehicleCard(expense: ExpenseStore, finance: FinanceStore,
                            now: Date, calendar cal: Calendar) -> WidgetVehicleCard? {
        let candidates = finance.vehicles.filter { !$0.isSold(asOf: now) }
        guard let first = candidates.first else { return nil }
        let recent = recentVariable(expense, now: now, calendar: cal)

        var counts: [UUID: Int] = [:]
        for e in recent {
            if let vid = e.linkedVehicleId { counts[vid, default: 0] += 1 }
        }
        var pick = first
        var best = counts[first.id] ?? 0
        for v in candidates.dropFirst() {
            let n = counts[v.id] ?? 0
            if n > best {
                pick = v
                best = n
            }
        }

        let cat = vehicleCategory(for: pick, recent: recent)
        let name = pick.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = name.isEmpty ? cat.rawValue : name + " " + cat.rawValue
        return WidgetVehicleCard(vehicleId: pick.id, vehicleName: name, categoryKey: cat.rawValue,
                                 title: title, icon: cat.icon,
                                 top: carTop, bottom: carBottom, tint: carTint)
    }

    /// 那台車近 60 天最常記的車子分類（只數那台車可用的分類；同數取 categories(for:) 裡前面的）
    private static func vehicleCategory(for v: Vehicle, recent: [Expense]) -> VehicleVariableCategory {
        let allowed = VehicleVariableCategory.categories(for: v.powerType)
        var counts: [VehicleVariableCategory: Int] = [:]
        for e in recent where e.linkedVehicleId == v.id {
            if let c = e.vehicleExpenseCategory { counts[c, default: 0] += 1 }
        }
        var best: VehicleVariableCategory? = nil
        var bestCount = 0
        for c in allowed {
            let n = counts[c] ?? 0
            if n > bestCount {
                best = c
                bestCount = n
            }
        }
        if let best { return best }
        let electric = v.powerType == .electric || v.powerType == .electricMotorcycle
        let fallback: VehicleVariableCategory = electric ? .electricity : .fuel
        if allowed.contains(fallback) { return fallback }
        return allowed.first ?? .other
    }

    // MARK: - 最常記的分類

    /// 近 60 天變動支出依分類數次數，多到少；同數取最近一筆比較新的（再同就照 allCases 的順序）。
    /// hasVehicleCard 時跳過「汽車」（免得跟第三張車子卡重複）。不足 3 個依序補
    /// 飲食、購物、交通、日用品。回傳 rawValue，至少 3 個。
    static func topCategoryKeys(expense: ExpenseStore, hasVehicleCard: Bool,
                                now: Date, calendar cal: Calendar) -> [String] {
        let recent = recentVariable(expense, now: now, calendar: cal)
        var counts: [VariableCategory: Int] = [:]
        var latest: [VariableCategory: Date] = [:]
        for e in recent {
            guard let c = e.variableCategory else { continue }
            if hasVehicleCard && c == .vehicle { continue }
            counts[c, default: 0] += 1
            if let d = latest[c], d >= e.date { continue }
            latest[c] = e.date
        }
        var keys = counts.keys.sorted { a, b in
            categoryRanks(a, before: b, counts: counts, latest: latest)
        }
        for c in fallbackCategories where keys.count < minTopCategories && !keys.contains(c) {
            keys.append(c)
        }
        return keys.map(\.rawValue)
    }

    /// topCategoryKeys 的排序：次數多的在前 → 最近一筆新的在前 → allCases 的順序
    private static func categoryRanks(_ a: VariableCategory, before b: VariableCategory,
                                      counts: [VariableCategory: Int],
                                      latest: [VariableCategory: Date]) -> Bool {
        let ca = counts[a] ?? 0
        let cb = counts[b] ?? 0
        if ca != cb { return ca > cb }
        let da = latest[a] ?? .distantPast
        let db = latest[b] ?? .distantPast
        if da != db { return da > db }
        return categoryOrder(a) < categoryOrder(b)
    }

    private static func categoryOrder(_ c: VariableCategory) -> Int {
        VariableCategory.allCases.firstIndex(of: c) ?? Int.max
    }

    // MARK: - 常記範本（一按就記）

    /// 一組「同名稱＋同金額＋同分類＋同車＋同車子分類」的支出
    private struct TemplateGroup {
        let id: String
        let title: String
        let category: VariableCategory
        let vehicleId: UUID?
        let vehicleCategory: VehicleVariableCategory?
        var count: Int
        /// 最近的那一筆（金額字、排序用）
        var latest: Expense
    }

    /// 近 60 天、變動支出、金額 > 0、名稱去頭尾空白非空、台幣（NT$／TWD／空字串）、沒連股票／房子／保單的支出，
    /// 依「名稱＋金額（四捨五入到分）＋分類＋車＋車子分類」分組，≥3 次的才算；連車的那台必須還在而且沒賣，
    /// 否則整組丟掉。排序：次數多到少 → 最近一筆新的優先 → id。最多 4 個。
    /// 一按記的支出（Expense.fromQuickRecord）照樣算次數：那也是真的消費。
    static func templates(expense: ExpenseStore, finance: FinanceStore,
                          now: Date, calendar cal: Calendar) -> [WidgetQuickTemplate] {
        let liveCars = Set(finance.vehicles.filter { !$0.isSold(asOf: now) }.map(\.id))
        var groups: [String: TemplateGroup] = [:]
        for e in recentVariable(expense, now: now, calendar: cal) {
            guard let g = templateKey(e, liveCars: liveCars) else { continue }
            if var old = groups[g.id] {
                old.count += 1
                if e.date > old.latest.date { old.latest = e }
                groups[g.id] = old
            } else {
                groups[g.id] = g
            }
        }
        let picked = groups.values
            .filter { $0.count >= templateMinCount }
            .sorted { a, b in
                if a.count != b.count { return a.count > b.count }
                if a.latest.date != b.latest.date { return a.latest.date > b.latest.date }
                return a.id < b.id
            }
            .prefix(templateMaxCount)
        return picked.map { template(from: $0, expense: expense) }
    }

    /// 一筆支出算不算範本候選；算的話回它那一組（count 1）
    private static func templateKey(_ e: Expense, liveCars: Set<UUID>) -> TemplateGroup? {
        guard e.amount > 0, e.amount.isFinite,
              let cat = e.variableCategory,
              e.linkedStockId == nil, e.linkedRealEstateId == nil, e.linkedInsuranceId == nil else { return nil }
        let code = e.currencyCode
        guard code == "NT$" || code == "TWD" || code.isEmpty else { return nil }
        let title = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        // 連到的車已經刪掉或賣掉：整組不要（按下去也連不上那台車）
        if let vid = e.linkedVehicleId, !liveCars.contains(vid) { return nil }
        let vcat: VehicleVariableCategory? = e.linkedVehicleId == nil ? nil : e.vehicleExpenseCategory
        let id = WidgetQuickTemplate.makeId(title: title, amount: e.amount, categoryKey: cat.rawValue,
                                            vehicleId: e.linkedVehicleId,
                                            vehicleCategoryKey: vcat?.rawValue)
        return TemplateGroup(id: id, title: title, category: cat, vehicleId: e.linkedVehicleId,
                             vehicleCategory: vcat, count: 1, latest: e)
    }

    private static func template(from g: TemplateGroup, expense: ExpenseStore) -> WidgetQuickTemplate {
        let icon: String
        let top: UInt32
        let bottom: UInt32
        let tint: UInt32
        if g.vehicleId != nil {
            icon = (g.vehicleCategory ?? .other).icon
            top = carTop
            bottom = carBottom
            tint = carTint
        } else {
            let theme = MoneyArtTheme.of(g.category)
            icon = g.category.icon
            top = theme.top
            bottom = theme.bottom
            tint = theme.tint
        }
        return WidgetQuickTemplate(id: g.id, title: g.title, amount: g.latest.amount,
                                   amountText: expense.displayAmountText(g.latest),
                                   categoryKey: g.category.rawValue,
                                   vehicleId: g.vehicleId,
                                   vehicleCategoryKey: g.vehicleCategory?.rawValue,
                                   icon: icon, top: top, bottom: bottom, tint: tint,
                                   count: g.count)
    }

    // MARK: - 下個月 1–7 號

    /// 下個月 day 那一天打開 App 時，收支總覽頭部會算出來的 OverviewBoardData（只填小工具用得到的欄位）。
    ///
    /// 照 OverviewBoardData.build（OverviewBoard.swift）在 now = day 時的算法，但收入、固定支出用
    /// 指定日版本（ExpenseStore.monthIncomeTotal(asOf:)／estimatedMonthlyIncome(asOf:)／fixedMonthlyTotal(for:)）。
    /// **不能拿 build(store:now: 下個月) 硬算**：build 裡的收入、固定支出用的是「現在」。
    /// prev3DailyAvg、lastMonthSameDay、dues、upcoming 小工具不顯示，留預設。
    static func nextMonthBoard(expense: ExpenseStore, day: Date, calendar cal: Calendar) -> OverviewBoardData {
        var b = OverviewBoardData()
        b.month = cal.component(.month, from: day)
        b.day = cal.component(.day, from: day)
        b.daysInMonth = cal.range(of: .day, in: .month, for: day)?.count ?? 30
        b.income = expense.monthIncomeTotal(asOf: day)
        b.incomeMedian = expense.estimatedMonthlyIncome(asOf: day)
        b.base = max(b.income, b.incomeMedian)
        b.baseIsEstimate = b.incomeMedian > b.income
        b.fixed = expense.fixedMonthlyTotal(for: day)

        // 那個月每天的變動支出（通常是 0：已經先記在下個月的才有）。照 build 的迴圈，now 換成 day
        var daily = Array(repeating: 0.0, count: b.daysInMonth)
        for e in expense.expenses where e.expenseType == .variable
            && cal.isDate(e.date, equalTo: day, toGranularity: .month) {
            b.variable += e.amount
            if cal.isDate(e.date, inSameDayAs: day) { b.todayCount += 1 }
            let i = cal.component(.day, from: e.date) - 1
            if daily.indices.contains(i) { daily[i] += e.amount }
        }
        if daily.indices.contains(b.day - 1) { b.todayVariable = daily[b.day - 1] }
        b.daily = Array(daily.prefix(b.day))
        return b
    }

    // MARK: - 每一天補 v2 的字

    /// 每一天都要呼叫（今天、往後推的、下個月的）。字跟收支總覽同一套：
    /// 「今天花了」格（OverviewBoard.todayTile）、「這個月的錢」右上的收入（moneyCell）、頭部膠囊「已花 62%」。
    static func decorate(_ day: inout WidgetMoneyDay, board d: OverviewBoardData) {
        let ratio = spentRatio(d)
        let percent = MoneyFormat.percent(ratio)
        let countText = d.todayCount > 0 ? "今天 \(d.todayCount) 筆" : "今天 還沒花錢"

        day.todayCount = d.todayCount
        day.todayText = d.todayCount > 0
            ? "今天 " + MoneyFormat.short(d.todayVariable) + "・\(d.todayCount) 筆"
            : "今天 還沒花錢"
        // 拆成兩步：三元裡再套三元＋字串相加，型別檢查不用猜那麼多組合
        let estimateSuffix = d.baseIsEstimate ? "・預估" : ""
        let incomeLine = "收入 " + MoneyFormat.short(d.base) + estimateSuffix
        day.incomeText = d.hasBase ? incomeLine : nil

        guard d.hasBase else {
            day.masked = WidgetMoneyMasked(title: "本月支出", hero: WidgetHideAmounts.mask,
                                           line: "記一筆收入，才算得出還能花", footer: countText)
            day.lock = WidgetMoneyLock(ringValue: 0, ringText: "\(d.todayCount) 筆", ringCaption: "今天",
                                       inlineText: countText + "・還沒有收入紀錄")
            return
        }
        day.masked = WidgetMoneyMasked(title: "本月已花", hero: percent,
                                       line: "還有 \(d.remainingDays) 天", footer: countText)
        // 超支的判斷跟「還能花」同一個（WidgetSnapshotWriter.moneyDay：left < 0）
        let over = d.left < 0
        day.lock = WidgetMoneyLock(ringValue: over ? 1 : min(max(ratio, 0), 1),
                                   ringText: over ? "超支" : percent,
                                   ringCaption: "已花",
                                   inlineText: countText + "・已花 " + percent)
    }

    /// 本月支出 ÷ 收入基準；沒有收入基準、或算出來不是有限數是 0（MoneyFormat.percent 遇到 inf／nan 會當掉）
    private static func spentRatio(_ d: OverviewBoardData) -> Double {
        guard d.hasBase else { return 0 }
        let r = d.spending / d.base
        return r.isFinite ? r : 0
    }

    // MARK: - 共用

    /// 近 60 天（今天 00:00 往回 60 天起、到現在為止）的變動支出
    private static func recentVariable(_ expense: ExpenseStore, now: Date, calendar cal: Calendar) -> [Expense] {
        let today = cal.startOfDay(for: now)
        let start = cal.date(byAdding: .day, value: -lookbackDays, to: today) ?? today
        return expense.expenses.filter { $0.expenseType == .variable && $0.date >= start && $0.date <= now }
    }
}
