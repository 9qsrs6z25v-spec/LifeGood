import Foundation

// MARK: - 理財四個小工具的快照（finance_v1.json）＋App 記股價、匯率的更新時間（小工具 v4）
//
// 只屬於「LifeGood」target。由 G1 實作，規格見 scratchpad/widgets/v4/brief.md 的 G1-1、G1-2。
// （主控建好的空檔，已登記 pbxproj：A01A000001001547／A01B000001001547）
//
// 股票今天、金價匯率、我的車、淨資產要顯示的字與數字，全部用理財頁同一套算好、組好：
//   • 開頭只建一次 FinanceLoanIndex（同 FinanceOverviewData.build，FinanceBoards.swift:71），
//     淨資產、上個月、每台車都讀它，數字才會跟理財總覽、車子卡片一模一樣
//   • 淨資產＝FinanceSnapshot.current；「比上月」＝FinanceHistory.series(months: 2) 的第一點
//     （理財總覽 FinanceBoards.swift:74-76 同一段），寫法照 changeCapsule（:134-138）
//   • 每台車讀 VehicleFacts；「接下來」跟「接下來要繳」同一套：今天、15 天後各算一次合併（WidgetBillsBuilder）
//   • 股票：持有中依市值大到小；今年股利、最近一次配息同股票頁看板（StockBoardData.build）
//   • 金價匯率：設定「自訂幣別匯率」裡 FXRateService 認得的幣別
//
// 規矩：**只讀不寫**——不呼叫 FinanceOverviewData.build（它會寫每月淨資產紀錄）、不呼叫 FinanceHistory.record、
// 不改任何 store。金額的字只用 MoneyFormat.short／MoneyFormat.percent／FinanceText.about100／
// FinanceItemText.number／ntdWanString；寫進快照的 Double 一律有限。
//
// @MainActor：MoneyFormat 的 NumberFormatter 只在主執行緒用（跟寫手一樣）。

@MainActor
enum WidgetFinanceBuilder {

    /// 我的車「接下來」最多放幾筆
    private static let maxVehicleDues = 8
    /// 車貸接下來的扣款日最多放幾期（App 兩週沒開，已繳期數也會自己往前走）
    private static let maxLoanDues = 6

    /// 其他貸款的顏色（灰）：App 的理財總覽沒有這一類的主題色，小工具兩條裡用灰
    private static let otherLoanTop: UInt32 = 0xC5CCDA
    private static let otherLoanBottom: UInt32 = 0x7A869E

    /// 理財四個小工具的快照。只讀不寫：不呼叫 FinanceOverviewData.build、不呼叫 FinanceHistory.record
    static func snapshot(expense: ExpenseStore, finance: FinanceStore, now: Date,
                         calendar cal: Calendar = .current) -> WidgetFinanceSnapshot {
        let index = FinanceLoanIndex(finance: finance, expense: expense, now: now)
        let rates = FinanceRates(expense)
        let stocks = stocksBlock(finance: finance, now: now, calendar: cal)
        let rateBlock = ratesBlock(expense: expense)
        let cars = vehicles(expense: expense, finance: finance, index: index, now: now, calendar: cal)
        let worth = netWorth(expense: expense, finance: finance, rates: rates, index: index,
                             now: now, calendar: cal)
        return WidgetFinanceSnapshot(generatedAt: now,
                                     dataDay: WidgetDateText.dayKey(now),
                                     stocks: stocks,
                                     rates: rateBlock,
                                     vehicles: cars,
                                     netWorth: worth)
    }

    // MARK: - 股票

    private static func stocksBlock(finance: FinanceStore, now: Date,
                                    calendar cal: Calendar) -> WidgetStocksBlock {
        // 今年 1/1 00:00（同 StockBoardData.build，FinanceBoards.swift:483）
        let yearStart = cal.date(from: cal.dateComponents([.year], from: now)) ?? now

        // 持有中（沒賣掉、股數 > 0、有代號），市值大到小；同值依代號（再依 id，結果固定）
        let held = finance.stocks.filter { !$0.isSold && $0.shares > 0 && !trimmedSymbol($0).isEmpty }
        let ranked: [(stock: Stock, value: Double)] = held.map { (stock: $0, value: finite($0.marketValue)) }
        let ordered = ranked.sorted { a, b in
            if a.value != b.value { return a.value > b.value }
            let sa = trimmedSymbol(a.stock)
            let sb = trimmedSymbol(b.stock)
            if sa != sb { return sa < sb }
            return a.stock.id.uuidString < b.stock.id.uuidString
        }
        let items: [WidgetFinanceStock] = ordered.prefix(WidgetStocksBlock.maxItems).map {
            stockItem($0.stock, yearStart: yearStart, now: now)
        }

        // 中型最下面那一行：全部股票（含已賣出，同 StockBoardData.build:484）
        let thisYear = finance.stocks.reduce(0.0) { $0 + $1.moneyCashDividends(from: yearStart, to: now) }
        let latest = latestCashDividend(in: finance.stocks, now: now)
        var parts: [String] = []
        var masked: [String] = []
        if thisYear >= 1 {
            parts.append("今年股利 " + MoneyFormat.short(thisYear))
            masked.append("今年股利 " + WidgetHideAmounts.mask)
        }
        if let latest {
            let day = dividendDay(latest.dividend.date, now: now)
            parts.append("最近 " + day + " 配息 " + MoneyFormat.short(finite(latest.amount)))
            masked.append("最近 " + day + " 配息 " + WidgetHideAmounts.mask)
        }
        return WidgetStocksBlock(items: items,
                                 dividendLine: parts.isEmpty ? nil : parts.joined(separator: "・"),
                                 dividendLineMasked: masked.isEmpty ? nil : masked.joined(separator: "・"))
    }

    private static func stockItem(_ s: Stock, yearStart: Date, now: Date) -> WidgetFinanceStock {
        let symbol = trimmedSymbol(s)
        let rawName = s.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let thisYear = s.moneyCashDividends(from: yearStart, to: now)
        var lastText: String? = nil
        if let d = lastCashDividend(of: s, now: now) {
            lastText = dividendDay(d.date, now: now) + " 配息 "
                + MoneyFormat.short(finite(d.cashTotal * s.currencyFactor))
        }
        return WidgetFinanceStock(id: s.id,
                                  symbol: symbol,
                                  name: rawName.isEmpty ? symbol : rawName,
                                  script: StockScriptName.word(s) ?? MoneyArtTheme.finStock.word,
                                  yahooSymbols: yahooSymbols(symbol),
                                  isUS: s.isUSStock,
                                  shares: finite(s.shares),
                                  qtyText: StockCardText.quantity(s, shares: s.shares),
                                  avgPrice: finite(s.purchasePrice),
                                  currencyFactor: finite(s.currencyFactor),
                                  appPrice: finite(s.currentPrice),
                                  appPreviousClose: positive(s.moneyPreviousClose(now: now)),
                                  appQuoteAt: AppQuoteClock.stockTime(symbol),
                                  dividendsThisYearText: thisYear >= 1 ? MoneyFormat.short(thisYear) : nil,
                                  lastDividendText: lastText,
                                  link: WidgetLink.financeStock(s.id).absoluteString)
    }

    /// 小工具上網抓價要試的 Yahoo 代號：跟 App 抓日線、報價補網同一套（StockDailyHistory.suffixCandidates）。
    /// 美股「VOO」；台股學過的「2330.TW」，沒學過的「6488.TW」「6488.TWO」兩個都放
    private static func yahooSymbols(_ symbol: String) -> [String] {
        StockDailyHistory.suffixCandidates(for: symbol).map { symbol + $0 }
    }

    /// 這一檔日期最晚的那一筆現金股利（今天以前領到的；App 只記已經領到的，不猜下一次）。
    /// 金額是 0 的（每股配息或當時股數沒填）不算，同股票卡片的股利長條（StockDividendCard 濾 cashTotal > 0），
    /// 免得寫出「最近 10/5 配息 NT$0」
    private static func lastCashDividend(of s: Stock, now: Date) -> StockDividend? {
        s.dividends
            .filter { $0.kind == .cash && $0.cashTotal > 0 && $0.date <= now }
            .max { $0.date < $1.date }
    }

    /// 配息日：今年的寫「10/5」，不是今年的寫「2025/8/15」（HouseCardFormat.shortDate，卡片同一套）。
    /// 台股多半一年配一次，上半年只寫「最近 8/15 配息」會被看成今年、還沒到的日子
    private static func dividendDay(_ d: Date, now: Date) -> String {
        HouseCardFormat.shortDate(d, now: now)
    }

    /// 全部股票（含已賣出）日期最晚的那一筆現金股利，金額換成台幣（cashTotal × 那一檔的 currencyFactor）
    private static func latestCashDividend(in stocks: [Stock], now: Date)
        -> (dividend: StockDividend, amount: Double)? {
        var best: (dividend: StockDividend, amount: Double)? = nil
        for s in stocks {
            guard let d = lastCashDividend(of: s, now: now) else { continue }
            if let b = best, b.dividend.date >= d.date { continue }
            best = (dividend: d, amount: d.cashTotal * s.currencyFactor)
        }
        return best
    }

    private static func trimmedSymbol(_ s: Stock) -> String {
        s.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 金價匯率

    /// 設定「自訂幣別匯率」照順序：幣別字去空白、空的跳過；匯率 > 0；FXRateService 認得；同一個代碼只留第一個
    private static func ratesBlock(expense: ExpenseStore) -> WidgetRatesBlock {
        var seen = Set<String>()
        var items: [WidgetFinanceRate] = []
        for r in expense.currencyRates {
            let label = r.code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, r.rate > 0, r.rate.isFinite,
                  let code = FXRateService.isoCode(for: label) else { continue }
            guard seen.insert(code).inserted else { continue }
            items.append(WidgetFinanceRate(code: code, label: label, rate: r.rate))
        }
        return WidgetRatesBlock(items: items, appUpdatedAt: AppQuoteClock.ratesUpdatedAt)
    }

    // MARK: - 我的車

    /// 照 FinanceStore.vehicles 的順序：沒賣掉的全放；賣掉的只有 45 天內還有要扣的才放，接在後面
    private static func vehicles(expense: ExpenseStore, finance: FinanceStore, index: FinanceLoanIndex,
                                 now: Date, calendar cal: Calendar) -> [WidgetFinanceVehicle] {
        guard !finance.vehicles.isEmpty else { return [] }
        let today = cal.startOfDay(for: now)
        let horizonEnd = cal.date(byAdding: .day, value: WidgetBillsBuilder.horizonDays, to: today) ?? today
        // 15 天後再算一次（同 WidgetBillsBuilder.financeBills 的 index2）：VehicleFacts.upcoming 每筆只給下一次，
        // 往後推才拿得到 45 天內的第二期。只要車子的 VehicleFacts（FinanceLoanIndex.init 也是這一支），不建房子的
        let shifted = cal.date(byAdding: .day, value: WidgetBillsBuilder.financeShiftDays, to: today) ?? today
        let later = FinanceLoanIndex.vehicleFacts(finance, expense: expense, now: shifted)

        var held: [WidgetFinanceVehicle] = []
        var sold: [WidgetFinanceVehicle] = []
        for v in finance.vehicles {
            guard let facts = index.vehicles[v.id] else { continue }
            let isSold = v.isSold(asOf: now)
            let dues = upcoming(facts, later: later[v.id], today: today, horizonEnd: horizonEnd, calendar: cal)
            if isSold && dues.isEmpty { continue }
            let item = vehicleItem(v, facts: facts, sold: isSold, upcoming: dues, now: now, calendar: cal)
            if isSold {
                sold.append(item)
            } else {
                held.append(item)
            }
        }
        return held + sold
    }

    private static func vehicleItem(_ v: Vehicle, facts: VehicleFacts, sold: Bool, upcoming: [WidgetVehicleDue],
                                    now: Date, calendar cal: Calendar) -> WidgetFinanceVehicle {
        // 主題色、插畫跟車子卡片同一個（油車油電藍 finGas、電車綠 finElectric、機車 finMoto／finScooter）
        let theme = VehicleScriptName.theme(v)
        let power = widgetPower(v.powerType)
        return WidgetFinanceVehicle(id: v.id,
                                    name: VehicleScriptName.shareName(v),
                                    power: power,
                                    powerText: v.powerType.shortName,
                                    isSold: sold,
                                    top: theme.top,
                                    bottom: theme.bottom,
                                    tint: theme.tint,
                                    symbol: theme.hero,
                                    monthlyText: sold ? nil : FinanceText.about100(facts.monthly),
                                    energyText: sold ? nil : energyText(facts),
                                    valueText: valueText(facts, sold: sold),
                                    loan: sold ? nil : loan(facts, now: now, calendar: cal),
                                    upcoming: upcoming,
                                    buttons: sold ? [] : buttons(v.id, power: power),
                                    link: WidgetLink.financeVehicle(v.id).absoluteString)
    }

    private static func widgetPower(_ p: VehiclePowerType) -> WidgetVehiclePower {
        switch p {
        case .electric: return .electric
        case .gasoline: return .gasoline
        case .hybrid: return .hybrid
        case .motorcycle: return .motorcycle
        case .electricMotorcycle: return .electricMotorcycle
        }
    }

    /// 「每度電 NT$7.9」「每公升 NT$30.5」「每公里 NT$2.1」（同載具頁看板與車子項目卡；決定 13 一律一位小數）
    private static func energyText(_ f: VehicleFacts) -> String? {
        if let p = f.perKwh, p.isFinite {
            return "每度電 NT$" + FinanceItemText.number(p, digits: 1)
        }
        if let p = f.fuel?.perLiter, p.isFinite {
            return "每公升 NT$" + FinanceItemText.number(p, digits: 1)
        }
        if let p = f.perKm, p.isFinite {
            return "每公里 NT$" + FinanceItemText.number(p, digits: 1)
        }
        return nil
    }

    /// 「估值 NT$260萬」；已售出「成交 NT$200萬」（沒填成交價、用估值當賣價的還是寫「估值」）；
    /// 估值還沒填、借用購入價的寫「購入價」（車子卡片寫「車輛估值（還沒填，先用購入價）」，不冒充估值）
    private static func valueText(_ f: VehicleFacts, sold: Bool) -> String? {
        let value = finite(f.value)
        guard value > 0 else { return nil }
        let word: String
        if sold && !f.saleUsesEstimate {
            word = "成交 "
        } else if !sold && f.valueIsFallback {
            word = "購入價 "
        } else {
            word = "估值 "
        }
        return word + MoneyFormat.short(value)
    }

    /// 車貸（有填年限的那幾筆合起來，同車子卡片 FinanceItems.swift:815-860 的判斷）。
    /// 已售出的車不放（車子卡片也只有持有中才畫車貸進度：賣掉的車 VehicleFacts 算到賣出那天為止）
    private static func loan(_ f: VehicleFacts, now: Date, calendar cal: Calendar) -> WidgetVehicleLoan? {
        guard let s = f.loan else { return nil }
        // [v4 驗證] 同車子卡片（FinanceItems.vehicleLoan）：有年限的都繳完了、另一筆沒填年限的這個月還在扣，
        // 卡片不寫「車貸繳清」（改寫「車貸每月 …・沒填年限」）；小工具也不放，免得寫「車貸繳清」其實還在扣
        let guessMonthly = f.loans
            .filter { $0.termIsGuess && $0.isPaying(inMonth: f.asOf, calendar: Calendar(identifier: .gregorian)) }
            .reduce(0.0) { $0 + $1.monthly }
        if s.isDone && guessMonthly >= 1 { return nil }
        let known = f.loans.filter { !$0.termIsGuess && $0.countedPeriods > 0 }
        let today = cal.startOfDay(for: now)
        // 接下來會扣的期：每筆從「已繳＋1」期起，扣款日在今天 00:00 之後的（已繳的期數算到今天，同 App）
        var dues: [WidgetLoanDue] = []
        for l in known where l.paidPeriods < l.countedPeriods {
            var k = l.paidPeriods + 1
            var taken = 0
            while k <= l.countedPeriods && taken < maxLoanDues {
                let day = cal.startOfDay(for: l.due(k))
                if day > today {
                    dues.append(WidgetLoanDue(date: day, index: k))
                    taken += 1
                }
                k += 1
            }
        }
        dues.sort { a, b in
            if a.date != b.date { return a.date < b.date }
            return a.index < b.index
        }
        let payoff = known.compactMap(\.payoffDate).max().map { HouseCardFormat.ym($0) + " 繳完" }
        var start: String? = nil
        if s.elapsed == 0 {
            start = known.map(\.firstDue).min().map { HouseCardFormat.ym($0) + " 開始" }
        }
        return WidgetVehicleLoan(paid: s.elapsed,
                                 total: s.total,
                                 dues: Array(dues.prefix(maxLoanDues)),
                                 payoffText: payoff,
                                 startText: start)
    }

    /// 今天起 45 天內每一次要扣的：今天、15 天後兩份 VehicleFacts.upcoming 合在一起，id＋日子去重，
    /// 依（日子、名稱）排，最多 8 筆（同 WidgetBillsBuilder.financeBills）。保養超過預計日期的不列（同 FinanceUpcoming）
    private static func upcoming(_ facts: VehicleFacts, later: VehicleFacts?, today: Date, horizonEnd: Date,
                                 calendar cal: Calendar) -> [WidgetVehicleDue] {
        var sources: [VehicleFacts] = [facts]
        if let later { sources.append(later) }
        var seen = Set<String>()
        var out: [WidgetVehicleDue] = []
        for f in sources {
            for u in f.upcoming {
                let day = cal.startOfDay(for: u.date)
                guard day >= today, day < horizonEnd else { continue }
                let key = u.id + "@" + WidgetDateText.dayKey(day)
                guard seen.insert(key).inserted else { continue }
                out.append(vehicleDue(u, id: key, day: day, loans: f.loans))
            }
        }
        out.sort { a, b in
            if a.date != b.date { return a.date < b.date }
            if a.title != b.title { return a.title < b.title }
            return a.id < b.id
        }
        return Array(out.prefix(maxVehicleDues))
    }

    /// 名稱、金額照 FinanceUpcoming.vehicleItem（FinanceInsights.swift:597-621），去掉車名前綴：
    /// 同一台兩筆都沒取名時「車貸（第 1 筆）」；保養是估計的寫「約」
    private static func vehicleDue(_ u: VehicleUpcoming, id: String, day: Date,
                                   loans: [VehicleLoan]) -> WidgetVehicleDue {
        var title = u.title
        var period: String? = nil
        let amount: String
        switch u.kind {
        case .loan(let loanId):
            let l = loans.first { $0.id == loanId }
            if let l, l.displayTitle != l.title {
                title = l.title + "（" + l.displayTitle + "）"
            }
            if let next = l?.next(onOrAfter: u.date) {
                period = "第 \(next.index) 期"
            }
            amount = u.amount.ntdWanString
        case .fixed:
            amount = u.amount.ntdWanString
        case .maintenance:
            amount = u.amount > 0 ? "約 " + u.amount.ntdWanString : "—"
        }
        return WidgetVehicleDue(id: id, date: day, title: title, periodText: period, amountText: amount)
    }

    /// 中型的兩顆按鈕：電車、電動機車［記電費、記停車］；油車、油電、機車［記加油、記停車］（主控定案 14）
    private static func buttons(_ vehicleId: UUID, power: WidgetVehiclePower) -> [WidgetVehicleButton] {
        let energy: VehicleVariableCategory = power.chargesElectric ? .electricity : .fuel
        return [button(vehicleId, category: energy), button(vehicleId, category: .parking)]
    }

    private static func button(_ vehicleId: UUID, category: VehicleVariableCategory) -> WidgetVehicleButton {
        let title: String
        let icon: String
        switch category {
        case .electricity:
            title = "記電費"
            icon = "bolt.fill"
        case .fuel:
            title = "記加油"
            icon = "fuelpump.fill"
        default:
            title = "記停車"
            icon = "parkingsign.circle"
        }
        let url = WidgetLink.addExpense(vehicleId: vehicleId, vehicleCategoryKey: category.rawValue)
        return WidgetVehicleButton(categoryKey: category.rawValue, title: title, icon: icon,
                                   link: url.absoluteString)
    }

    // MARK: - 淨資產

    /// 「比上月」那幾個字（changeCapsule 同一個算法與寫法）
    private struct ChangeWords {
        var text: String?
        var short: String?
        var direction: Int
    }

    /// 理財總覽頭部同一套：FinanceSnapshot.current＋FinanceHistory.series(months: 2)（只讀，不 record）。
    /// 沒有任何資產、也沒有貸款 nil
    private static func netWorth(expense: ExpenseStore, finance: FinanceStore, rates: FinanceRates,
                                 index: FinanceLoanIndex, now: Date, calendar cal: Calendar) -> WidgetNetWorth? {
        let s = FinanceSnapshot.current(finance: finance, expense: expense, rates: rates, now: now, index: index)
        guard s.assets > 0 || s.debt > 0 else { return nil }
        // 上個月：有存下來的用存的、沒有的 App 自己回推（同 FinanceOverviewData.build 的 :74-76）
        let two = FinanceHistory.series(months: 2, finance: finance, expense: expense, rates: rates,
                                        now: now, index: index)
        var last: Double? = nil
        if two.count == 2, two[0].assets > 0 { last = two[0].netWorth }
        let change = changeWords(netWorth: s.netWorth, last: last)

        let month = cal.component(.month, from: now)
        let assets = assetParts(s)
        let debts = debtParts(s)
        let scale = max(s.assets, s.debt, 1)
        return WidgetNetWorth(monthKey: WidgetDateText.monthKey(now),
                              monthText: "\(month) 月",
                              netWorthText: MoneyFormat.short(finite(s.netWorth)),
                              isNegative: s.netWorth < 0,
                              changeText: change.text,
                              changeShort: change.short,
                              changeDirection: change.direction,
                              line: overviewLine(s, masked: false),
                              lineMasked: overviewLine(s, masked: true),
                              assets: assets,
                              debts: debts,
                              assetsBar: clamp01(s.assets / scale),
                              debtsBar: clamp01(s.debt / scale),
                              summaryText: assets.isEmpty ? "\(month) 月" : "資產 \(assets.count) 類・\(month) 月",
                              stockPriceAt: stockPriceAt(finance))
    }

    /// 「比上月 ↑1.8%」「比上月 ↓0.6%」「比上月 持平」：照 FinanceOverviewBoard.changeCapsule 逐字
    ///（上個月是負的也照「變了多少」算：−100 萬 → −50 萬是 ↑50%）
    private static func changeWords(netWorth: Double, last: Double?) -> ChangeWords {
        guard let last, last.isFinite, netWorth.isFinite, abs(last) >= 1 else {
            return ChangeWords(text: nil, short: nil, direction: 0)
        }
        let r = (netWorth - last) / abs(last)
        guard r.isFinite else { return ChangeWords(text: nil, short: nil, direction: 0) }
        if abs(r) < 0.01 { return ChangeWords(text: "比上月 持平", short: "持平", direction: 0) }
        let short = (r > 0 ? "↑" : "↓") + MoneyFormat.percent(abs(r))
        return ChangeWords(text: "比上月 " + short, short: short, direction: r > 0 ? 1 : -1)
    }

    /// 理財總覽頭部那一句（FinanceOverviewBoard.line，FinanceBoards.swift:141-153）：
    /// 「總資產 NT$3795萬・貸款還欠 約 NT$2075萬」「總資產 NT$3795萬・沒有貸款」；masked 金額換 NT$ ••••
    private static func overviewLine(_ s: FinanceSnapshot, masked: Bool) -> String {
        let assets = "總資產 " + (masked ? WidgetHideAmounts.mask : MoneyFormat.short(finite(s.assets)))
        if s.debt <= 0 { return assets + "・沒有貸款" }
        let word = (s.mortgageEstimated || s.carLoanEstimated) ? "貸款還欠 約 " : "貸款還欠 "
        let debt = masked ? WidgetHideAmounts.mask : MoneyFormat.short(finite(s.debt))
        return assets + "・" + word + debt
    }

    /// 資產各類（> 0 的，金額大到小：同理財總覽「錢放在哪裡」FinanceBoards.swift:183-185 同一個排序）
    private static func assetParts(_ s: FinanceSnapshot) -> [WidgetNetWorthPart] {
        let kinds = FinanceAssetKind.allCases.filter { s.value($0) > 0 }.sorted { s.value($0) > s.value($1) }
        return kinds.map { kind -> WidgetNetWorthPart in
            let v = finite(s.value(kind))
            let theme = kind.theme
            let share = clamp01(s.assets > 0 ? v / s.assets : 0)
            return WidgetNetWorthPart(key: kind.rawValue,
                                      title: kind.name,
                                      icon: theme.hero,
                                      amountText: MoneyFormat.short(v),
                                      shareText: MoneyFormat.percent(share),
                                      share: share,
                                      top: theme.top,
                                      bottom: theme.bottom)
        }
    }

    /// 貸款各類（> 0 的，金額大到小）：房貸、車貸照理財總覽的字——算不出本金、退回含利息的寫「還要繳」，
    /// 本金是推算的寫「約」（mortgageWord，FinanceBoards.swift:215-219）；其他貸款本來就是含利息的還要繳
    private static func debtParts(_ s: FinanceSnapshot) -> [WidgetNetWorthPart] {
        var list: [(part: WidgetNetWorthPart, value: Double)] = []
        if s.mortgage > 0 {
            let word = s.mortgageScheduled ? "還要繳 " : (s.mortgageEstimated ? "約 " : "")
            let theme = MoneyArtTheme.finHome
            list.append(debtPart(key: "mortgage", title: "房貸", icon: "house", word: word, value: s.mortgage,
                                 total: s.debt, top: theme.top, bottom: theme.bottom))
        }
        if s.carLoan > 0 {
            let word = s.carLoanScheduled ? "還要繳 " : (s.carLoanEstimated ? "約 " : "")
            let theme = MoneyArtTheme.finDrive
            list.append(debtPart(key: "carLoan", title: "車貸", icon: "car", word: word, value: s.carLoan,
                                 total: s.debt, top: theme.top, bottom: theme.bottom))
        }
        if s.otherLoan > 0 {
            list.append(debtPart(key: "otherLoan", title: "其他貸款", icon: "banknote", word: "還要繳 ",
                                 value: s.otherLoan, total: s.debt, top: otherLoanTop, bottom: otherLoanBottom))
        }
        return list.sorted { $0.value > $1.value }.map { $0.part }
    }

    private static func debtPart(key: String, title: String, icon: String, word: String, value: Double,
                                 total: Double, top: UInt32, bottom: UInt32)
        -> (part: WidgetNetWorthPart, value: Double) {
        let v = finite(value)
        let share = clamp01(total > 0 ? v / total : 0)
        let part = WidgetNetWorthPart(key: key,
                                      title: title,
                                      icon: icon,
                                      amountText: word + MoneyFormat.short(v),
                                      shareText: MoneyFormat.percent(share),
                                      share: share,
                                      top: top,
                                      bottom: bottom)
        return (part: part, value: v)
    }

    /// 淨資產裡股票用的是幾點的價：持有中股票 AppQuoteClock 記的最新那一筆；沒有股票或不知道 nil
    private static func stockPriceAt(_ finance: FinanceStore) -> Date? {
        finance.stocks
            .filter { !$0.isSold && $0.shares > 0 }
            .compactMap { AppQuoteClock.stockTime($0.symbol) }
            .max()
    }

    // MARK: - 數字的保險

    /// 寫進快照的數字一律有限（MoneyFormat.percent 遇到 inf／nan 會在 Int(...) 當掉）
    private static func finite(_ v: Double) -> Double {
        v.isFinite ? v : 0
    }

    /// > 0 的有限值；其他 nil（App 的前一日收盤不知道就不寫，不猜）
    private static func positive(_ v: Double?) -> Double? {
        guard let v, v.isFinite, v > 0 else { return nil }
        return v
    }

    private static func clamp01(_ v: Double) -> Double {
        guard v.isFinite else { return 0 }
        return min(max(v, 0), 1)
    }
}

// MARK: - App 記股價、匯率最後一次更新成功的時間（小工具 v4，主控 F）

/// 小工具抓不到價時，用 App 的價並寫「10/13 13:30 的價」——那個「13:30」就是這裡記的。
/// 本機 UserDefaults.standard，**不同步**（不進 CloudSyncManager.syncKeys：是這台裝置什麼時候抓的，
/// 別台的時間沒有意義），清掉也沒關係（小工具改寫「App 的價」）。
///
/// 記的是「App 抓到報價的那一刻」，不是成交時間（MIS、TPEx、Yahoo 給的時間格式各不相同，App 也沒存）。
/// 股票頁 refreshAllPrices、ExpenseStore.autoUpdateCurrencyRates 成功時各記一次；
/// 新增／編輯股票的單檔查價、已賣出的查價不記（不在小工具上）。
///
/// 不標 @MainActor：只讀寫 UserDefaults（執行緒安全），寫手（@MainActor）與報價那兩支都叫得到。
enum AppQuoteClock {
    /// [App 的股票代號（去空白）: epoch 秒]
    private static let stocksKey = "widget_stock_quote_times_v1"
    /// epoch 秒
    private static let ratesKey = "widget_rates_updated_at_v1"

    /// 這幾檔剛報價成功（代號是 App 的 Stock.symbol；去頭尾空白後存）
    static func rememberStocks(_ symbols: [String], at now: Date = Date()) {
        let clean = symbols
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !clean.isEmpty else { return }
        let defaults = UserDefaults.standard
        var map = (defaults.dictionary(forKey: stocksKey) as? [String: Double]) ?? [:]
        let t = now.timeIntervalSince1970
        for symbol in clean { map[symbol] = t }
        defaults.set(map, forKey: stocksKey)
    }

    /// 這一檔 App 最後一次報價成功的時間；沒記過 nil
    static func stockTime(_ symbol: String) -> Date? {
        let key = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty,
              let map = UserDefaults.standard.dictionary(forKey: stocksKey) as? [String: Double],
              let t = map[key], t.isFinite, t > 0 else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    /// 自訂幣別匯率剛自動更新成功（至少帶入一個）
    static func rememberRates(at now: Date = Date()) {
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: ratesKey)
    }

    /// App 最後一次自動更新匯率成功的時間；沒記過 nil
    static var ratesUpdatedAt: Date? {
        let t = UserDefaults.standard.double(forKey: ratesKey)
        guard t.isFinite, t > 0 else { return nil }
        return Date(timeIntervalSince1970: t)
    }
}
