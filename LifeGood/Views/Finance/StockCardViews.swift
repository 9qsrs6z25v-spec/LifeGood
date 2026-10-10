import SwiftUI
import Charts

// MARK: - 股票卡片（v25.528）
//
// 使用者：「不錯 接下来換股票卡片介面，幫我深入規劃」，看過規劃與樣稿：「好 先照你的建議做」。
//
// 原本的卡片是一張閃卡（稀有度外框＋市值大字＋三欄），下面一路排了八段：K 線、法人、籌碼、
// 交易資訊、交易紀錄、股利紀錄、帳戶、備註。問題是：
//   - 大字是市值，賺多少、今天漲跌、均價在哪裡都要往下找；
//   - 買賣跟股利分成兩本，看不出「什麼時候買、什麼時候領息、賣在哪裡」的先後；
//   - 賣掉的股票只剩「賣出市值」，看不出賣得好不好。
// 這一版跟理財頁同一套看板：
//   換股列 → 看板（股價山稜＋價格位置＋膠囊）→ 走勢（K 線標出買賣點、配息、均價線）
//   → 籌碼（法人、融資融券合成一張，分頁）→ 我的帳本（六格＋含息總報酬＋一條時間軸）
//   → 股利（每次配息、殖利率、拿回成本幾成）→ 資料
// 閃卡（FlashCardView）還留給載具與房地產；股票不再用。
//
// 均價照 App 原本的算法（全部買進的平均，配股攤進去；賣出不改均價），不改成券商的「移動平均」：
// AddStockView 可以手動改均價，重算會蓋掉使用者自己填的數字，兩種算法混在一起總數也對不起來。
// 所以帳本裡每一筆賣出的已實現＝賣出股數 ×（賣價 − 均價），加起來剛好是 moneyRealizedProfit。

// MARK: - 字

enum StockCardText {
    /// 數量：台股寫「張」（存檔就是張，跟編輯畫面輸入的一樣；零股是「0.5 張」），美股寫「股」
    static func quantity(_ s: Stock, shares: Double) -> String {
        s.isUSStock
            ? FinanceItemText.number(shares, digits: 4) + " 股"
            : FinanceItemText.number(shares / 1000, digits: 4) + " 張"
    }

    /// 牌子上的價錢：千元以上不寫小數、百元以上一位、其他兩位（1,085／895.2／23.45）
    static func price(_ v: Double) -> String {
        let a = abs(v)
        if a >= 1000 { return FinanceItemText.number(v.rounded()) }
        if a >= 100 { return FinanceItemText.number((v * 10).rounded() / 10) }
        return FinanceItemText.number(v)
    }

    /// 格子、牌子裡的金額：不寫 NT$（「179萬」「+38萬」）
    static func compact(_ v: Double, signed: Bool = false) -> String {
        (signed && v > 0 ? "+" : "") + MoneyFormat.compact(v)
    }

    /// 單筆交易／配息是原幣別：台股「NT$51.8萬」，美股「US$1,234.5」（美金不講萬）
    static func trade(_ s: Stock, _ v: Double) -> String {
        s.isUSStock ? "US$" + FinanceItemText.number(v) : v.ntdWanString
    }

    /// 持有多久：「1 年 2 個月」「5 個月」「12 天」
    static func span(from a: Date, to b: Date) -> String? {
        guard b > a else { return nil }
        let c = Calendar.current.dateComponents([.year, .month, .day], from: a, to: b)
        let y = c.year ?? 0
        let m = c.month ?? 0
        if y > 0 { return m > 0 ? "\(y) 年 \(m) 個月" : "\(y) 年" }
        if m > 0 { return "\(m) 個月" }
        return "\(max(1, c.day ?? 0)) 天"
    }

    /// 帳本左邊的日期方塊：「10」＋「2026/9」
    static func day(_ d: Date) -> String {
        String(format: "%02d", Calendar.current.component(.day, from: d))
    }

    static func yearMonth(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: d)
        return "\(c.year ?? 0)/\(c.month ?? 0)"
    }
}

// MARK: - 帳本

/// 帳本裡的一筆：買進、賣出、配息、配股照日期排在一起
struct StockLedgerEvent: Identifiable, Equatable {
    enum Kind: Equatable { case buy, sell, cash, stock }
    enum Source: Equatable {
        case transaction(StockTransaction)
        case dividend(StockDividend)
        /// 沒有交易紀錄的舊資料：用買入日／賣出日補上的那一筆（按了開「編輯股票」）
        case legacy
    }
    let id: String
    let date: Date
    let kind: Kind
    let source: Source
    /// 股數：買、賣、配股是這一筆的股數；配息是當時的持股
    let shares: Double
    /// 每股價錢（買賣）或每股配息（原幣別）
    let price: Double
    /// 金額（原幣別）：買賣＝股數 × 價錢；配息＝配到的現金；配股是 0
    let amount: Double
    /// 這一筆之後還有幾股
    let sharesAfter: Double
    /// 賣出：這一筆的已實現（台幣）＝賣出股數 ×（賣價 − 均價）
    var realized: Double? = nil
    /// 買進：現價比買價（0.047＝現在 +4.7%）
    var nowRate: Double? = nil
}

enum StockLedger {
    private enum Item {
        case tx(StockTransaction)
        case div(StockDividend)
        case legacyBuy
        case legacySell
    }

    private struct Entry {
        let day: Date
        let order: Int
        let date: Date
        let item: Item
    }

    /// 全部的紀錄，新的在前。nowPrice：算買進那幾筆「現在 +x%」用（持有中才傳）
    static func events(_ s: Stock, nowPrice: Double?) -> [StockLedgerEvent] {
        let cal = Calendar.current
        let fx = s.currencyFactor
        var entries: [Entry] = []
        if s.transactions.isEmpty {
            if s.shares > 0 {
                entries.append(Entry(day: cal.startOfDay(for: s.purchaseDate), order: 0, date: s.purchaseDate, item: .legacyBuy))
                if s.isSold, let d = s.soldDate, s.soldPrice > 0 {
                    entries.append(Entry(day: cal.startOfDay(for: d), order: 3, date: d, item: .legacySell))
                }
            }
        } else {
            for t in s.transactions {
                entries.append(Entry(day: cal.startOfDay(for: t.date), order: t.kind == .buy ? 0 : 3, date: t.date, item: .tx(t)))
            }
        }
        for d in s.dividends {
            entries.append(Entry(day: cal.startOfDay(for: d.date), order: d.kind == .stock ? 1 : 2, date: d.date, item: .div(d)))
        }
        // 同一天先買、再配股配息、最後才賣（日期只選到「天」，時間是記帳那一刻，不能拿來排）
        entries.sort { a, b in
            if a.day != b.day { return a.day < b.day }
            if a.order != b.order { return a.order < b.order }
            return a.date < b.date
        }
        var held: Double = 0
        var out: [StockLedgerEvent] = []
        for entry in entries {
            switch entry.item {
            case .tx(let t):
                held = max(0, held + (t.kind == .buy ? t.shares : -t.shares))
                var e = StockLedgerEvent(id: t.id.uuidString, date: t.date, kind: t.kind == .buy ? .buy : .sell,
                                         source: .transaction(t), shares: t.shares, price: t.price,
                                         amount: t.amount, sharesAfter: held)
                if t.kind == .sell {
                    e.realized = t.shares * (t.price - s.purchasePrice) * fx
                } else if let now = nowPrice, now > 0, t.price > 0 {
                    e.nowRate = now / t.price - 1
                }
                out.append(e)
            case .div(let d):
                let cash = d.kind == .cash
                if !cash { held += d.sharesEarned }
                out.append(StockLedgerEvent(id: d.id.uuidString, date: d.date, kind: cash ? .cash : .stock,
                                            source: .dividend(d), shares: cash ? d.sharesAtEvent : d.sharesEarned,
                                            price: cash ? d.perShare : 0, amount: cash ? d.cashTotal : 0,
                                            sharesAfter: held))
            case .legacyBuy:
                held += s.shares
                var e = StockLedgerEvent(id: "legacy-buy", date: s.purchaseDate, kind: .buy, source: .legacy,
                                         shares: s.shares, price: s.purchasePrice,
                                         amount: s.shares * s.purchasePrice, sharesAfter: held)
                if let now = nowPrice, now > 0, s.purchasePrice > 0 {
                    e.nowRate = now / s.purchasePrice - 1
                }
                out.append(e)
            case .legacySell:
                held = 0
                var e = StockLedgerEvent(id: "legacy-sell", date: entry.date, kind: .sell, source: .legacy,
                                         shares: s.shares, price: s.soldPrice,
                                         amount: s.shares * s.soldPrice, sharesAfter: 0)
                e.realized = s.shares * (s.soldPrice - s.purchasePrice) * fx
                out.append(e)
            }
        }
        return out.reversed()
    }
}

// MARK: - 卡片的數字

/// 股票卡片要顯示的數字。StockDetailView 的 body 裡算一次，往下傳給看板、帳本、股利、資料。
struct StockCardData {
    let stock: Stock
    var title = ""
    /// 「台股・上市」「台股・ETF」「美股」
    var market = ""
    /// 看板右邊的手寫字（TSMC）
    var script = MoneyArtTheme.finStock.word
    var seed = 0
    // 報價（原幣別）
    var price: Double = 0
    var dayRate: Double? = nil
    // 下面是台幣
    var dayChange: Double? = nil
    var value: Double = 0
    var cost: Double = 0
    var realized: Double = 0
    var cashDividends: Double = 0
    var cashDividendCount = 0
    var stockDividendShares: Double = 0
    var stockDividendCount = 0
    var dividends12m: Double = 0
    var totalBought: Double = 0
    /// 占持股（持有中不只一檔才有）
    var weight: Double? = nil
    var firstBuy: Date? = nil
    var holding: String? = nil
    // 價格位置（原幣別）
    var rangeLow: Double? = nil
    var rangeHigh: Double? = nil
    var rangeLabel = "52 週"
    // 賣掉的
    var soldShares: Double = 0
    var soldBasis: Double = 0
    /// 賣掉之後的現價（打開時抓一次；抓不到用日線快取最近一根）
    var nowPrice: Double? = nil
    /// 賣出後漲跌（0.075＝漲 7.5%）
    var afterSale: Double? = nil
    var events: [StockLedgerEvent] = []
    var ridge = FinRidgeScene(values: [])

    var isSold: Bool { stock.isSold }
    var unrealized: Double { value - cost }
    var unrealizedRate: Double? { cost > 0 ? unrealized / cost : nil }
    /// 未實現＋已實現＋配息
    var totalGain: Double { unrealized + realized + cashDividends }
    /// 含息總報酬：賺的 ÷ 總共買進的
    var totalReturn: Double? { totalBought > 0 ? totalGain / totalBought : nil }
    /// 已賣出：含息報酬（已實現＋配息）÷ 賣掉的那些的成本
    var soldReturn: Double? { soldBasis > 0 ? (realized + cashDividends) / soldBasis : nil }
    /// 用自己的成本算的殖利率（近 12 個月的配息 ÷ 還持有的成本）
    var yieldOnCost: Double? { cost > 0 && dividends12m > 0 ? dividends12m / cost : nil }
    /// 配息已經拿回成本幾成
    var recovered: Double? { cost > 0 && cashDividends > 0 ? cashDividends / cost : nil }

    /// 看板第一行：「2330・台股・上市」「2603・已賣出」
    var headline: String {
        [stock.symbol, isSold ? "已賣出" : market].filter { !$0.isEmpty }.joined(separator: "・")
    }

    static func build(_ s: Stock, all: [Stock], points: [StockDailyPoint], soldNowPrice: Double?,
                      now: Date = Date()) -> StockCardData {
        let cal = Calendar.current
        let fx = s.currencyFactor
        var d = StockCardData(stock: s)
        d.title = s.name.isEmpty ? (s.symbol.isEmpty ? "股票" : s.symbol) : s.name
        if s.isUSStock {
            d.market = "美股"
        } else {
            var parts = ["台股"]
            if StockScriptName.isETF(s) {
                parts.append("ETF")
            } else if let tier = TWQuoteService.tierLabel(symbol: s.symbol) {
                parts.append(tier)
            }
            d.market = parts.joined(separator: "・")
        }
        d.script = StockScriptName.word(s) ?? MoneyArtTheme.finStock.word
        d.seed = MoneyItem.seed(s.id)
        let year = points.filter { $0.close > 0 && now.timeIntervalSince($0.date) <= 366 * 86_400 }
        // 日線快取最近一根（一週內的才算「現在」）
        let recent: Double? = year.last.flatMap { now.timeIntervalSince($0.date) < 7 * 86_400 ? $0.close : nil }

        var bought: Double = 0
        var sold: Double = 0
        if s.transactions.isEmpty {
            bought = s.shares * s.purchasePrice
            sold = s.isSold ? s.shares : 0
        } else {
            for t in s.transactions {
                if t.kind == .buy { bought += t.amount } else { sold += t.shares }
            }
        }
        d.totalBought = bought * fx
        d.soldShares = sold
        d.soldBasis = sold * s.purchasePrice * fx
        d.realized = s.moneyRealizedProfit
        for v in s.dividends {
            if v.kind == .cash {
                d.cashDividends += v.cashTotal * fx
                d.cashDividendCount += 1
            } else {
                d.stockDividendShares += v.sharesEarned
                d.stockDividendCount += 1
            }
        }
        if let yearAgo = cal.date(byAdding: .year, value: -1, to: now) {
            d.dividends12m = s.moneyCashDividends(from: yearAgo, to: now)
        }
        let firstBuy = s.transactions.filter { $0.kind == .buy }.map(\.date).min() ?? s.purchaseDate
        d.firstBuy = firstBuy
        d.holding = StockCardText.span(from: firstBuy, to: s.isSold ? (s.soldDate ?? now) : now)

        if s.isSold {
            d.nowPrice = soldNowPrice ?? recent
            if let p = d.nowPrice, p > 0, s.soldPrice > 0 { d.afterSale = p / s.soldPrice - 1 }
            d.price = d.nowPrice ?? 0
        } else {
            d.price = s.currentPrice
            d.value = s.marketValue
            d.cost = s.totalCost
            if s.currentPrice > 0, let prev = previousClose(s, points: points, now: now), prev > 0 {
                d.dayRate = s.currentPrice / prev - 1
                d.dayChange = s.shares * (s.currentPrice - prev) * fx
            }
            let active = all.filter { !$0.isSold && $0.shares > 0 }
            let total = active.reduce(0) { $0 + $1.marketValue }
            if active.count > 1, total > 0, d.value > 0 { d.weight = d.value / total }
        }

        // 價格位置：近一年的最低、最高（快取不到一年就寫「近 N 個月」）
        if year.count >= 2 {
            var lo = year.map { $0.low ?? $0.close }.min() ?? 0
            var hi = year.map { $0.high ?? $0.close }.max() ?? 0
            if d.price > 0 {
                lo = min(lo, d.price)
                hi = max(hi, d.price)
            }
            if lo > 0, hi > lo {
                d.rangeLow = lo
                d.rangeHigh = hi
                let days = now.timeIntervalSince(year[0].date) / 86_400
                if days < 330 { d.rangeLabel = "近 \(max(1, Int((days / 30.4).rounded()))) 個月" }
            }
        }

        d.events = StockLedger.events(s, nowPrice: !s.isSold && s.currentPrice > 0 ? s.currentPrice : nil)
        let up: Bool
        if s.isSold {
            up = (d.afterSale ?? 0) >= 0
        } else {
            up = (d.dayRate ?? (s.currentPrice - s.purchasePrice)) >= 0
        }
        d.ridge = ridgeScene(s, year: year, price: d.price, up: up)
        return d
    }

    /// 前一個交易日的收盤（今日漲跌用）：報價時記下的優先，沒有就看手上這份日線
    /// （跟 Stock.moneyPreviousClose 同一套判斷，只是不再讀一次快取）
    static func previousClose(_ s: Stock, points: [StockDailyPoint], now: Date) -> Double? {
        guard !s.symbol.isEmpty else { return nil }
        if let p = StockPreviousClose.value(s.symbol, now: now) { return p }
        guard points.count >= 2, let last = points.last, now.timeIntervalSince(last.date) < 5 * 86_400 else { return nil }
        let sameSession = Calendar.current.isDate(last.date, inSameDayAs: now)
            || abs(s.currentPrice - last.close) <= last.close * 0.0001
        return sameSession ? points[points.count - 2].close : last.close
    }

    /// 已賣出的那一檔：含息報酬（換股列用；不用整份 build）
    static func realizedReturn(_ s: Stock) -> Double? {
        let sold = s.transactions.isEmpty
            ? s.shares
            : s.transactions.filter { $0.kind == .sell }.reduce(0) { $0 + $1.shares }
        let basis = sold * s.purchasePrice * s.currencyFactor
        guard basis > 0 else { return nil }
        let divs = s.dividends.filter { $0.kind == .cash }.reduce(0) { $0 + $1.cashTotal } * s.currencyFactor
        return (s.moneyRealizedProfit + divs) / basis
    }

    /// 看板的風景：近一年一週一點的收盤價，均價是水平面，買賣插旗、配息是金幣
    static func ridgeScene(_ s: Stock, year pts: [StockDailyPoint], price: Double, up: Bool) -> FinRidgeScene {
        guard pts.count >= 2 else { return FinRidgeScene(values: []) }
        let cal = Calendar.current
        // 從最後一天往回每隔一週取一點（最後一點一定是最近那一天）
        let step = max(1, Int((Double(pts.count) / 52).rounded()))
        var idx: [Int] = []
        var i = pts.count - 1
        while i >= 0 {
            idx.append(i)
            i -= step
        }
        idx.reverse()
        var values = idx.map { pts[$0].close }
        if price > 0 { values[values.count - 1] = price }
        let dates = idx.map { cal.startOfDay(for: pts[$0].date) }
        var scene = FinRidgeScene(values: values)
        if s.purchasePrice > 0 {
            scene.cost = s.purchasePrice
            scene.costLabel = "均價 " + StockCardText.price(s.purchasePrice)
        }
        scene.priceLabel = StockCardText.price(values[values.count - 1])
        scene.up = up
        // 插在那一週的點上；一年以前的不畫
        func index(of date: Date) -> Int? {
            let day = cal.startOfDay(for: date)
            guard let first = dates.first,
                  day >= (cal.date(byAdding: .day, value: -6, to: first) ?? first) else { return nil }
            return dates.firstIndex { $0 >= day } ?? dates.count - 1
        }
        var seen = Set<String>()
        func add(_ date: Date, _ kind: FinRidgeScene.MarkKind) {
            guard let k = index(of: date) else { return }
            let key = "\(k)-\(kind)"
            guard !seen.contains(key) else { return }
            seen.insert(key)
            scene.marks.append(FinRidgeScene.Mark(index: k, kind: kind))
        }
        if s.transactions.isEmpty {
            if s.shares > 0 {
                add(s.purchaseDate, .buy)
                if s.isSold, let sd = s.soldDate { add(sd, .sell) }
            }
        } else {
            for t in s.transactions { add(t.date, t.kind == .buy ? .buy : .sell) }
        }
        for v in s.dividends where v.kind == .cash { add(v.date, .dividend) }
        // 月份：1、4、7、10 月（太靠兩邊的不寫）
        if dates.count >= 5 {
            for k in 2..<(dates.count - 2) {
                let m = cal.component(.month, from: dates[k])
                guard m != cal.component(.month, from: dates[k - 1]), m % 3 == 1 else { continue }
                scene.ticks.append(FinRidgeScene.Tick(index: k, label: "\(m)月"))
            }
        }
        return scene
    }
}

/// K 線上的買賣點、配息
struct StockChartMark: Equatable {
    enum Kind: Equatable { case buy, sell, dividend }
    let date: Date
    let kind: Kind
    let shares: Double
    let price: Double

    static func marks(_ s: Stock) -> [StockChartMark] {
        var out: [StockChartMark] = []
        if s.transactions.isEmpty {
            if s.shares > 0 {
                out.append(StockChartMark(date: s.purchaseDate, kind: .buy, shares: s.shares, price: s.purchasePrice))
                if s.isSold, let d = s.soldDate, s.soldPrice > 0 {
                    out.append(StockChartMark(date: d, kind: .sell, shares: s.shares, price: s.soldPrice))
                }
            }
        } else {
            for t in s.transactions {
                out.append(StockChartMark(date: t.date, kind: t.kind == .buy ? .buy : .sell, shares: t.shares, price: t.price))
            }
        }
        for v in s.dividends where v.kind == .cash {
            out.append(StockChartMark(date: v.date, kind: .dividend, shares: v.sharesAtEvent, price: v.perShare))
        }
        return out
    }
}

// MARK: - 外框

/// 看板下面那幾張卡的外框（跟理財頁的圖表卡同一套：白底、圓角 18、淡淡的影子）
struct StockCardChrome: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: shape)
            .overlay {
                shape.stroke(scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04), lineWidth: 0.75)
            }
            .shadow(color: scheme == .dark ? Color.black.opacity(0.3) : Color(tb: 0x1E3A6E, 0.07), radius: 8, x: 0, y: 3)
    }
}

/// 卡片裡的小方格底色（帳本六格、籌碼三格）
enum StockCardTile {
    static func fill(_ pal: TripBoardPalette) -> Color {
        pal.dark ? Color.white.opacity(0.06) : Color(tb: 0xF2F5FA)
    }
}

// MARK: - 看板

/// 股票卡片最上面的看板。持有中：大字是市值；賣掉的：大字是已實現損益，膠囊是「賣出後」漲跌。
struct StockCardBoard: View {
    let data: StockCardData

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        return data.isSold ? soldBoard(pal) : activeBoard(pal)
    }

    // MARK: 持有中

    private func activeBoard(_ pal: TripBoardPalette) -> MoneyBoardCard {
        let d = data
        let tone = d.dayRate.map { MoneyTone.change($0) } ?? .neutral
        let chips = activeChips(pal)
        let showPosition = d.rangeLow != nil && d.rangeHigh != nil && d.price > 0
        return MoneyBoardCard(
            card: .stock,
            header: MoneyBoardHeader(
                date: d.headline,
                dateIcon: "building.columns.fill",
                capsule: dayCapsule,
                capsuleIcon: tone == .down ? "chart.line.downtrend.xyaxis" : "chart.line.uptrend.xyaxis",
                capsuleTint: tone == .neutral ? nil : tone.color(pal),
                label: "我的市值",
                big: MoneyFormat.short(d.value),
                line: activeLine(pal),
                greeting: [d.script],
                scene: .ridge(d.ridge),
                band: 132,
                seed: d.seed),
            content: (chips.isEmpty && !showPosition) ? nil : AnyView(
                VStack(alignment: .leading, spacing: 10) {
                    if showPosition, let lo = d.rangeLow, let hi = d.rangeHigh {
                        StockPricePosition(low: lo, high: hi,
                                           cost: d.stock.purchasePrice > 0 ? d.stock.purchasePrice : nil,
                                           price: d.price, label: d.rangeLabel, pal: pal)
                    }
                    if !chips.isEmpty {
                        MoneyBoardChips(chips: chips, pal: pal)
                    }
                }
            ))
    }

    /// 「今日 ▲1.8%」
    private var dayCapsule: String? {
        guard let r = data.dayRate else { return nil }
        if abs(r) < 0.0005 { return "今日 平盤" }
        return "今日 " + (r > 0 ? "▲" : "▼") + FinanceText.percent1(abs(r))
    }

    private func activeLine(_ pal: TripBoardPalette) -> Text {
        let d = data
        let s = d.stock
        guard s.shares > 0 else { return Text("還沒有持股：在下面「我的帳本」記一筆買進") }
        let qty = StockCardText.quantity(s, shares: s.shares)
        guard s.currentPrice > 0 else { return Text("還沒有報價・持有 \(qty)") }
        guard d.cost > 0 else { return Text("成本沒有填，算不出賺賠・持有 \(qty)") }
        let tone = MoneyTone.change(d.unrealized, base: d.cost)
        let amount = FinanceText.signed(d.unrealized) + "（" + FinanceText.signedPercent(d.unrealized / d.cost) + "）"
        return Text("未實現 \(Text(amount).fontWeight(.heavy).foregroundStyle(tone.color(pal)))・持有 \(qty)")
    }

    private func activeChips(_ pal: TripBoardPalette) -> [MoneyBoardChip] {
        let d = data
        var out: [MoneyBoardChip] = []
        if let c = d.dayChange {
            out.append(MoneyBoardChip(icon: "sun.max.fill", label: "今日", value: FinanceText.signed(c),
                                      tone: MoneyTone.change(c, base: max(d.value, 1))))
        }
        if abs(d.realized) >= 1 {
            out.append(MoneyBoardChip(icon: "checkmark.seal.fill", label: "已實現", value: FinanceText.signed(d.realized),
                                      tone: MoneyTone.change(d.realized, base: max(d.totalBought, 1))))
        }
        if d.cashDividends > 0 {
            out.append(MoneyBoardChip(icon: "gift.fill", label: "累計股利", value: MoneyFormat.short(d.cashDividends)))
        }
        if let w = d.weight {
            out.append(MoneyBoardChip(icon: "chart.pie.fill", label: "占持股", value: MoneyFormat.percent(w)))
        }
        if let h = d.holding {
            out.append(MoneyBoardChip(icon: "clock.fill", label: "持有", value: h))
        }
        return out
    }

    // MARK: 已賣出

    private func soldBoard(_ pal: TripBoardPalette) -> MoneyBoardCard {
        let d = data
        let tone = MoneyTone.change(d.realized, base: max(d.soldBasis, 1))
        let after = d.afterSale.map { MoneyTone.change($0) } ?? .neutral
        let chips = soldChips(pal)
        return MoneyBoardCard(
            card: .stock,
            header: MoneyBoardHeader(
                date: d.headline,
                dateIcon: "checkmark.seal.fill",
                capsule: afterCapsule,
                capsuleIcon: after == .down ? "chart.line.downtrend.xyaxis" : "chart.line.uptrend.xyaxis",
                capsuleTint: after == .neutral ? nil : after.color(pal),
                label: "已實現損益",
                big: FinanceText.signed(d.realized),
                bigTone: tone == .neutral ? nil : tone,
                line: soldLine(pal),
                greeting: [d.script],
                scene: .ridge(d.ridge),
                band: 132,
                seed: d.seed),
            content: chips.isEmpty ? nil : AnyView(MoneyBoardChips(chips: chips, pal: pal)))
    }

    /// 「賣出後 ▼7.5%」：賣掉之後股價又漲了還是跌了
    private var afterCapsule: String? {
        guard let a = data.afterSale else { return nil }
        if abs(a) < 0.0005 { return "賣出後 平盤" }
        return "賣出後 " + (a > 0 ? "▲" : "▼") + FinanceText.percent1(abs(a))
    }

    /// 「2026/3/3 賣在 186・現在 172（賣出後 -7.5%）」
    private func soldLine(_ pal: TripBoardPalette) -> Text? {
        let d = data
        let s = d.stock
        guard s.soldPrice > 0 else { return nil }
        let when = s.soldDate.map { FinanceItemText.date($0) + " " } ?? ""
        let sell = when + "賣在 " + StockCardText.price(s.soldPrice)
        guard let now = d.nowPrice, let a = d.afterSale else { return Text(sell) }
        let tone = MoneyTone.change(a)
        let after = Text("賣出後 " + FinanceText.signedPercent(a)).fontWeight(.heavy).foregroundStyle(tone.color(pal))
        return Text("\(sell)・現在 \(StockCardText.price(now))（\(after)）")
    }

    private func soldChips(_ pal: TripBoardPalette) -> [MoneyBoardChip] {
        let d = data
        var out: [MoneyBoardChip] = []
        if d.stock.purchasePrice > 0 {
            out.append(MoneyBoardChip(icon: "cart.fill", label: "均價", value: StockCardText.price(d.stock.purchasePrice)))
        }
        if d.cashDividends > 0 {
            out.append(MoneyBoardChip(icon: "gift.fill", label: "股利", value: MoneyFormat.short(d.cashDividends)))
        }
        if let r = d.soldReturn {
            out.append(MoneyBoardChip(icon: "percent", label: "含息報酬", value: FinanceText.signedPercent(r),
                                      tone: MoneyTone.change(r)))
        }
        if let h = d.holding {
            out.append(MoneyBoardChip(icon: "clock.fill", label: "持有", value: h))
        }
        return out
    }
}

// MARK: - 價格位置

/// 近一年最低到最高的一條軌道：紫色菱形是均價、圓點是現價（現價比均價高是紅、低是綠）
struct StockPricePosition: View {
    let low: Double
    let high: Double
    let cost: Double?
    let price: Double
    /// 「52 週」或「近 6 個月」
    let label: String
    let pal: TripBoardPalette

    var body: some View {
        let up = cost.map { price >= $0 } ?? true
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("價格位置")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(pal.ink)
                Spacer(minLength: 8)
                Text(label + " " + StockCardText.price(low) + " – " + StockCardText.price(high))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(pal.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            GeometryReader { geo in
                track(width: geo.size.width, up: up)
            }
            .frame(height: 44)
            HStack {
                Text("低 " + StockCardText.price(low))
                Spacer()
                Text("高 " + StockCardText.price(high))
            }
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(pal.label)
            note
                .font(.footnote.weight(.semibold))
                .foregroundStyle(pal.inkDate)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .modifier(TripBoardCellChrome(pal: pal))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("價格位置")
        .accessibilityValue(accessibilityText)
    }

    private var highName: String { (label.hasPrefix("近") ? "離" : "離 ") + label + "高點" }

    /// 「比均價 +21.2%・離 52 週高點 -3.5%」
    private var note: Text {
        var first: Text? = nil
        if let c = cost, c > 0 {
            let r = price / c - 1
            first = Text("比均價 \(Text(FinanceText.signedPercent(r)).foregroundStyle(MoneyTone.change(r).color(pal)))")
        }
        var second: Text? = nil
        if high > 0 {
            let r = price / high - 1
            second = abs(r) < 0.0005
                ? Text("在" + label + "高點")
                : Text(highName + " " + FinanceText.signedPercent(r))
        }
        if let first, let second { return Text("\(first)・\(second)") }
        return first ?? second ?? Text("")
    }

    private var accessibilityText: String {
        var parts = [label + "最低 " + StockCardText.price(low) + "、最高 " + StockCardText.price(high)]
        if let c = cost { parts.append("均價 " + StockCardText.price(c)) }
        parts.append("現價 " + StockCardText.price(price))
        return parts.joined(separator: "，")
    }

    private func track(width w: CGFloat, up: Bool) -> some View {
        let inset: CGFloat = 9
        let span = max(high - low, 0.0001)
        func x(_ v: Double) -> CGFloat { inset + (w - inset * 2) * CGFloat(min(1, max(0, (v - low) / span))) }
        let xp = x(price)
        let xc = cost.map { x($0) }
        let costColor = MoneyBoardSky.ridgeCost(dark: pal.dark)
        let priceColor = up ? MoneyBoardSky.ridgeUp(dark: pal.dark) : MoneyBoardSky.ridgeDown(dark: pal.dark)
        // 均價在這一年的範圍外面：菱形貼在邊上，牌子寫箭頭（「均價 600 ←」）
        let costText: String? = cost.map { c -> String in
            let arrow = c < low ? " ←" : (c > high ? " →" : "")
            return "均價 " + StockCardText.price(c) + arrow
        }
        let priceText = "現價 " + StockCardText.price(price)
        let centers = pillCenters(width: w, cost: xc, costText: costText, price: xp, priceText: priceText)
        let trackY: CGFloat = 33
        let segStart = min(xc ?? xp, xp)
        let segEnd = max(xc ?? xp, xp)
        let towardRight = (xc ?? xp) <= xp
        return ZStack {
            Capsule()
                .fill(pal.progressTrack)
                .frame(width: max(0, w - inset * 2 + 8), height: 6)
                .position(x: w / 2, y: trackY)
            if xc != nil {
                Capsule()
                    .fill(LinearGradient(colors: [priceColor.opacity(0.3), priceColor],
                                         startPoint: towardRight ? .leading : .trailing,
                                         endPoint: towardRight ? .trailing : .leading))
                    .frame(width: max(6, segEnd - segStart), height: 6)
                    .position(x: (segStart + segEnd) / 2, y: trackY)
            }
            if let xc {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(costColor)
                    .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).stroke(Color.white, lineWidth: 1.5))
                    .frame(width: 11, height: 11)
                    .rotationEffect(.degrees(45))
                    .position(x: xc, y: trackY)
            }
            Circle()
                .fill(priceColor)
                .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                .frame(width: 15, height: 15)
                .shadow(color: priceColor.opacity(0.35), radius: 3, x: 0, y: 1)
                .position(x: xp, y: trackY)
            if let costText, let cx = centers.cost {
                pill(costText, fill: costColor)
                    .position(x: cx, y: 9)
            }
            pill(priceText, fill: priceColor)
                .position(x: centers.price, y: 9)
        }
    }

    private func pill(_ s: String, fill: Color) -> some View {
        Text(s)
            .font(.system(size: 10, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(fill, in: Capsule())
    }

    /// 牌子的寬度（估的：中文一個字約 10.5pt、數字約 6pt，加左右留白）
    private func pillWidth(_ s: String) -> CGFloat {
        s.unicodeScalars.reduce(CGFloat(14)) { $0 + ($1.isASCII ? 6.2 : 10.5) }
    }

    /// 兩個牌子靠太近就往兩邊推開，推到邊緣就整組挪回來
    private func pillCenters(width w: CGFloat, cost: CGFloat?, costText: String?, price: CGFloat,
                             priceText: String) -> (cost: CGFloat?, price: CGFloat) {
        let wp = pillWidth(priceText)
        guard let cost, let costText else { return (cost: nil, price: min(max(price, wp / 2), w - wp / 2)) }
        let wc = pillWidth(costText)
        let costLeft = cost <= price
        var a = costLeft ? cost : price
        var b = costLeft ? price : cost
        let wa = costLeft ? wc : wp
        let wb = costLeft ? wp : wc
        let need = (wa + wb) / 2 + 6
        if b - a < need {
            let mid = (a + b) / 2
            a = mid - need / 2
            b = mid + need / 2
        }
        if a - wa / 2 < 0 {
            let shift = wa / 2 - a
            a += shift
            b += shift
        }
        if b + wb / 2 > w {
            let shift = b + wb / 2 - w
            a -= shift
            b -= shift
        }
        if costLeft { return (cost: a, price: b) }
        return (cost: b, price: a)
    }
}

// MARK: - 換股列

/// 最上面一排：同一組（持有中／已賣出）的每一檔，點了就換；左右滑也可以換
struct StockSwitcherStrip: View {
    struct Item: Identifiable, Equatable {
        let id: UUID
        let symbol: String
        let name: String
        /// 持有中：今日漲跌；已賣出：含息報酬
        let rate: Double?
        let isDay: Bool
    }

    let items: [Item]
    let selected: UUID
    let onSelect: (UUID) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        Button {
                            onSelect(item.id)
                        } label: {
                            pill(item, on: item.id == selected, pal: pal)
                        }
                        .buttonStyle(MoneyPressStyle())
                        .id(item.id)
                        .accessibilityAddTraits(item.id == selected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
            .onChange(of: selected) { _, id in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func pill(_ item: Item, on: Bool, pal: TripBoardPalette) -> some View {
        let fill = on ? (pal.dark ? Color(tb: 0x3B4F8F) : Color(tb: 0x1D2B55)) : pal.cellFill
        let ink = on ? Color.white : pal.ink
        return HStack(spacing: 6) {
            if !item.symbol.isEmpty {
                Text(item.symbol)
                    .font(.caption.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(ink)
            }
            Text(MoneyBoardText.short(item.name.isEmpty ? "股票" : item.name, max: 6))
                .font(.caption.weight(.semibold))
                .foregroundStyle(on ? Color.white.opacity(0.9) : pal.label)
            if let r = item.rate {
                Text(rateText(r, isDay: item.isDay))
                    .font(.caption.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(rateColor(r, on: on, pal: pal))
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .background(fill, in: Capsule())
        .overlay(Capsule().stroke(on ? Color.clear : pal.cellStroke, lineWidth: 0.75))
        .shadow(color: on ? Color.clear : pal.cellShadow, radius: 3, x: 0, y: 1)
    }

    private func rateText(_ r: Double, isDay: Bool) -> String {
        guard isDay else { return FinanceText.signedPercent(r) }
        if abs(r) < 0.0005 { return "平盤" }
        return (r > 0 ? "▲" : "▼") + FinanceText.percent1(abs(r))
    }

    private func rateColor(_ r: Double, on: Bool, pal: TripBoardPalette) -> Color {
        let tone = MoneyTone.change(r)
        guard on else { return tone.color(pal) }
        switch tone {
        case .up: return Color(tb: 0xFF8A8A)
        case .down: return Color(tb: 0x6EE7A8)
        default: return Color.white.opacity(0.85)
        }
    }
}

// MARK: - 籌碼

/// 一檔股票某一天的籌碼（每日收集的快照；法人是股數、融資融券是張數，照官方原始單位）
struct StockChipDay: Identifiable, Equatable {
    let date: Date
    /// 三大法人合計（股）
    let net: Double?
    let foreign: Double?
    let trust: Double?
    let dealer: Double?
    /// 融資、融券餘額（張）
    let margin: Double?
    let short: Double?
    /// 外資持股（%）
    let foreignPct: Double?

    var id: Date { date }
    var hasBreakdown: Bool { foreign != nil || trust != nil || dealer != nil }
}

struct StockChipData: Equatable {
    var days: [StockChipDay] = []
    /// 整個快照庫一筆都沒有（收集還沒跑完或一直失敗）
    var storeIsEmpty = false

    /// 法人：最近 20 個交易日
    var inst: [StockChipDay] { Array(days.filter { $0.net != nil }.suffix(20)) }
    var margin: [StockChipDay] { days.filter { $0.margin != nil || $0.short != nil || $0.foreignPct != nil } }
    var isEmpty: Bool { inst.isEmpty && margin.isEmpty }

    /// 讀快照（檔案 IO：在背景跑）
    static func load(symbol: String) -> StockChipData {
        let records = InstitutionalHistory.tradingRecords()
        var out = StockChipData()
        out.storeIsEmpty = records.isEmpty
        for rec in records {
            guard let d = InstitutionalHistory.dayFmt.date(from: rec.date) else { continue }
            let day = StockChipDay(date: d, net: rec.net[symbol], foreign: rec.foreign?[symbol],
                                   trust: rec.trust?[symbol], dealer: rec.dealer?[symbol],
                                   margin: rec.marginBalance?[symbol], short: rec.shortBalance?[symbol],
                                   foreignPct: rec.foreignPct?[symbol])
            if day.net != nil || day.margin != nil || day.short != nil || day.foreignPct != nil {
                out.days.append(day)
            }
        }
        return out
    }
}

enum StockChipText {
    static let md: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d"
        return f
    }()

    static let detail: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "yyyy/M/d（E）"
        return f
    }()

    /// 「10,161」
    static func lots(_ v: Double) -> String { FinanceItemText.number(abs(v).rounded()) }

    /// 「+10,161」「-706」
    static func signedLots(_ v: Double) -> String {
        let r = v.rounded()
        return (r > 0 ? "+" : (r < 0 ? "-" : "")) + lots(r)
    }

    /// 從最後一天往回數：連續幾天同一個方向（正＝連買、負＝連賣）
    static func streak(_ v: [Double]) -> Int {
        guard let last = v.last, last != 0 else { return 0 }
        var n = 0
        for x in v.reversed() {
            guard x != 0, (x > 0) == (last > 0) else { break }
            n += 1
        }
        return last > 0 ? n : -n
    }
}

/// 籌碼卡：三大法人／融資融券兩頁。只有台股上市櫃有這份官方資料（美股、興櫃整張不出現）
struct StockChipsCard: View {
    let data: StockChipData
    var tier: String? = nil

    enum Tab: String, CaseIterable, Identifiable {
        case inst = "三大法人"
        case margin = "融資融券"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .inst
    @State private var selectedDate: Date?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let inst = data.inst
        let margin = data.margin
        let shown: Tab = inst.isEmpty ? .margin : (margin.isEmpty ? .inst : tab)
        VStack(alignment: .leading, spacing: 10) {
            MoneySectionHeader(title: "籌碼", trailing: (tier.map { $0 + "・" } ?? "") + "收盤後更新")
            VStack(alignment: .leading, spacing: 12) {
                if !inst.isEmpty && !margin.isEmpty {
                    Picker("籌碼", selection: $tab) {
                        ForEach(Tab.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: tab) { selectedDate = nil }
                }
                if shown == .inst {
                    StockInstPane(days: inst, selectedDate: $selectedDate, pal: pal)
                } else {
                    StockMarginPane(days: margin, selectedDate: $selectedDate, pal: pal)
                }
            }
            .padding(14)
            .modifier(StockCardChrome())
        }
    }
}

/// 快照庫還是空的：說清楚為什麼沒有資料、什麼時候會有
struct StockChipsCollectingHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MoneySectionHeader(title: "籌碼")
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "tray.and.arrow.down")
                    .foregroundStyle(.secondary)
                Text("法人買賣超、融資融券的資料收集中。官方收盤後公布（法人約 16:30、融資融券約 21:00），開 App 時會自動收集近幾個交易日，收到後這裡就會出現圖表。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .modifier(StockCardChrome())
        }
    }
}

/// 三大法人：一句話（近 20 個交易日外資買超多少、連買幾天）＋三格＋每天的堆疊柱＋外資累計虛線
private struct StockInstPane: View {
    let days: [StockChipDay]
    @Binding var selectedDate: Date?
    let pal: TripBoardPalette

    static let foreignColor = Color(tb: 0x2F7FE8)
    static let trustColor = Color(tb: 0xF39A1E)
    static let dealerColor = Color(tb: 0x8B5CF6)

    private struct Cum: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    private var selected: StockChipDay? {
        guard let selectedDate else { return nil }
        return days.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        let hasBreakdown = days.contains { $0.hasBreakdown }
        // 三格的合計（股 → 張）
        let foreignSum = days.reduce(0.0) { $0 + ($1.foreign ?? 0) } / 1000
        let trustSum = days.reduce(0.0) { $0 + ($1.trust ?? 0) } / 1000
        let dealerSum = days.reduce(0.0) { $0 + ($1.dealer ?? 0) } / 1000
        VStack(alignment: .leading, spacing: 12) {
            if let sel = selected {
                dayDetail(sel)
            } else {
                summary(hasBreakdown: hasBreakdown)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if hasBreakdown {
                HStack(spacing: 8) {
                    cell("外資", foreignSum, Self.foreignColor)
                    cell("投信", trustSum, Self.trustColor)
                    cell("自營商", dealerSum, Self.dealerColor)
                }
            }
            chart(hasBreakdown: hasBreakdown)
            Text(hasBreakdown
                 ? "每天一根，往上是買超、往下是賣超；虛線是外資累計。點一下看那一天。"
                 : "每天一根，往上是買超、往下是賣超（舊資料只有三大法人合計）。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 「近 20 個交易日：外資 買超 10,161 張・連買 5 天」
    private func summary(hasBreakdown: Bool) -> Text {
        let n = days.count
        let who = hasBreakdown ? "外資" : "三大法人"
        let values = days.map { hasBreakdown ? ($0.foreign ?? 0) : ($0.net ?? 0) }
        let total = values.reduce(0, +) / 1000
        let tone = MoneyTone.change(total)
        let word = total >= 0 ? "買超 " : "賣超 "
        let amount = Text(word + StockChipText.lots(total) + " 張").foregroundStyle(tone.color(pal))
        let streak = StockChipText.streak(values)
        if abs(streak) >= 2 {
            return Text("近 \(n) 個交易日：\(who) \(amount)・連\(streak > 0 ? "買" : "賣") \(abs(streak)) 天")
        }
        return Text("近 \(n) 個交易日：\(who) \(amount)")
    }

    private func cell(_ label: String, _ v: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(StockChipText.signedLots(v))
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(MoneyTone.change(v).color(pal))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(StockCardTile.fill(pal), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func dayDetail(_ d: StockChipDay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(StockChipText.detail.string(from: d.date))
                    .font(.subheadline.weight(.bold))
                Spacer()
                Button {
                    selectedDate = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("回到近 \(days.count) 個交易日")
            }
            HStack(spacing: 12) {
                if d.hasBreakdown {
                    pair("外資", d.foreign, Self.foreignColor)
                    pair("投信", d.trust, Self.trustColor)
                    pair("自營", d.dealer, Self.dealerColor)
                }
                Spacer(minLength: 0)
                Text("合計 " + StockChipText.signedLots((d.net ?? 0) / 1000) + " 張")
                    .font(.caption.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(MoneyTone.change(d.net ?? 0).color(pal))
            }
        }
    }

    private func pair(_ label: String, _ shares: Double?, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(shares.map { StockChipText.signedLots($0 / 1000) } ?? "—")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
        }
    }

    private func chart(hasBreakdown: Bool) -> some View {
        // 外資累計線縮到柱子的範圍裡（看形狀：一路往上＝一直在買）
        let maxBar = days.map { d -> Double in
            guard d.hasBreakdown else { return abs(d.net ?? 0) }
            let parts = [d.foreign ?? 0, d.trust ?? 0, d.dealer ?? 0]
            return max(parts.filter { $0 > 0 }.reduce(0, +), -parts.filter { $0 < 0 }.reduce(0, +))
        }.max() ?? 0
        var running = 0.0
        let cum = days.map { d -> Cum in
            running += d.foreign ?? 0
            return Cum(date: d.date, value: running)
        }
        let maxCum = cum.map { abs($0.value) }.max() ?? 0
        let scale = maxCum > 0 ? maxBar / maxCum * 0.92 : 0
        let barWidth: CGFloat = days.count > 25 ? 5 : 8
        let sel = selected
        return Chart {
            if let sel {
                RuleMark(x: .value("選取", sel.date))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            ForEach(days) { d in
                if d.hasBreakdown {
                    BarMark(x: .value("日", d.date), y: .value("張", (d.foreign ?? 0) / 1000), width: .fixed(barWidth))
                        .foregroundStyle(Self.foreignColor)
                    BarMark(x: .value("日", d.date), y: .value("張", (d.trust ?? 0) / 1000), width: .fixed(barWidth))
                        .foregroundStyle(Self.trustColor)
                    BarMark(x: .value("日", d.date), y: .value("張", (d.dealer ?? 0) / 1000), width: .fixed(barWidth))
                        .foregroundStyle(Self.dealerColor)
                } else {
                    BarMark(x: .value("日", d.date), y: .value("張", (d.net ?? 0) / 1000), width: .fixed(barWidth))
                        .foregroundStyle(Color.gray.opacity(0.55))
                }
            }
            if hasBreakdown, scale > 0 {
                ForEach(cum) { c in
                    LineMark(x: .value("日", c.date), y: .value("張", c.value * scale / 1000),
                             series: .value("線", "外資累計"))
                        .foregroundStyle(Self.foreignColor.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1.3, dash: [3, 2]))
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(StockChipText.md.string(from: d))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(StockChipText.signedLots(v)).font(.system(size: 9))
                    }
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .frame(height: 140)
        .accessibilityLabel("三大法人每日買賣超")
    }
}

/// 融資融券：四格（融資、融券＋比前一天多少，券資比、外資持股）＋融資餘額走勢
private struct StockMarginPane: View {
    let days: [StockChipDay]
    @Binding var selectedDate: Date?
    let pal: TripBoardPalette

    private let marginColor = Color.orange

    private var selected: StockChipDay? {
        guard let selectedDate else { return nil }
        return days.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        let shown = selected ?? days.last
        let line = days.filter { $0.margin != nil }
        VStack(alignment: .leading, spacing: 12) {
            if let shown {
                HStack {
                    Text(selected == nil ? "最新一天・" + StockChipText.md.string(from: shown.date)
                                         : StockChipText.detail.string(from: shown.date))
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    if selected != nil {
                        Button {
                            selectedDate = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("回到最新一天")
                    }
                }
                metrics(shown)
            }
            if line.count >= 2 {
                chart(line)
                Text("融資餘額走勢（張）。點一下看那一天。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metrics(_ d: StockChipDay) -> some View {
        let prev = days.filter { $0.date < d.date }.last { $0.margin != nil || $0.short != nil }
        let mDelta: Double? = d.margin.flatMap { m in prev?.margin.map { m - $0 } }
        let sDelta: Double? = d.short.flatMap { s in prev?.short.map { s - $0 } }
        let ratio: Double? = d.short.flatMap { s in d.margin.flatMap { m in m > 0 ? s / m : nil } }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            if let m = d.margin {
                cell("融資", StockChipText.lots(m) + " 張", delta: mDelta)
            }
            if let s = d.short {
                cell("融券", StockChipText.lots(s) + " 張", delta: sDelta)
            }
            if let ratio {
                cell("券資比", FinanceText.percent1(ratio), delta: nil)
            }
            if let f = d.foreignPct {
                cell("外資持股", String(format: "%.1f%%", f), delta: nil)
            }
        }
    }

    private func cell(_ label: String, _ value: String, delta: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let delta, delta.rounded() != 0 {
                    Text(StockChipText.signedLots(delta))
                        .font(.caption2.weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(MoneyTone.change(delta).color(pal))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(StockCardTile.fill(pal), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func chart(_ line: [StockChipDay]) -> some View {
        // 融資餘額是「量」：軸從資料的範圍起跳（從 0 起跳多半是一條貼底的平線）
        let vals = line.compactMap(\.margin)
        let lo = vals.min() ?? 0
        let hi = vals.max() ?? 1
        let pad = hi > lo ? (hi - lo) * 0.15 : max(hi * 0.05, 1)
        let domain = max(0, lo - pad)...(hi + pad)
        let sel = selected
        return Chart {
            if let sel, let m = sel.margin {
                RuleMark(x: .value("選取", sel.date))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(x: .value("選取", sel.date), y: .value("融資（張）", m))
                    .foregroundStyle(marginColor)
                    .symbolSize(60)
            }
            ForEach(line) { p in
                AreaMark(x: .value("日", p.date), yStart: .value("底", domain.lowerBound),
                         yEnd: .value("融資（張）", p.margin ?? 0))
                    .foregroundStyle(LinearGradient(colors: [marginColor.opacity(0.2), marginColor.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("日", p.date), y: .value("融資（張）", p.margin ?? 0))
                    .foregroundStyle(marginColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.8))
            }
        }
        .chartYScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(StockChipText.md.string(from: d))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(StockChipText.lots(v)).font(.system(size: 9))
                    }
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .frame(height: 110)
        .accessibilityLabel("融資餘額走勢")
    }
}

// MARK: - 我的帳本

/// 帳本「＋」選單的四種
enum StockLedgerAdd { case buy, sell, cash, stock }

/// 我的帳本：上面六格數字＋含息總報酬，下面一條時間軸（買進、賣出、配息、配股照日期排）
struct StockLedgerCard: View {
    let data: StockCardData
    let onAdd: (StockLedgerAdd) -> Void
    let onOpen: (StockLedgerEvent) -> Void

    @State private var showAll = false
    @Environment(\.colorScheme) private var scheme

    /// 先列幾筆（其他的按「再看 N 筆更早的」）
    private static let preview = 6

    var body: some View {
        let pal = TripBoardPalette(scheme)
        VStack(alignment: .leading, spacing: 10) {
            MoneySectionHeader(title: "我的帳本",
                               trailing: data.firstBuy.map { "從 " + FinanceItemText.date($0) + " 第一次買" })
            StockLedgerNumbers(data: data, pal: pal)
            timeline(pal)
        }
    }

    private func timeline(_ pal: TripBoardPalette) -> some View {
        let events = data.events
        let shown = showAll ? events : Array(events.prefix(Self.preview))
        let hidden = events.count - shown.count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Text(events.isEmpty ? "紀錄" : "紀錄・" + String(events.count) + " 筆")
                    .font(.subheadline.weight(.bold))
                Spacer(minLength: 8)
                Menu {
                    Button { onAdd(.buy) } label: { Label("買進", systemImage: "arrow.down.circle") }
                    Button { onAdd(.sell) } label: { Label("賣出", systemImage: "arrow.up.circle") }
                    Button { onAdd(.cash) } label: { Label("配息", systemImage: "dollarsign.circle") }
                    Button { onAdd(.stock) } label: { Label("配股", systemImage: "leaf") }
                } label: {
                    Label("買進／賣出／股利", systemImage: "plus")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 30)
                        .background(Color(tb: 0x177A44), in: Capsule())
                }
                .accessibilityLabel("新增買進、賣出或股利")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 6)
            if events.isEmpty {
                Text("還沒有紀錄。按右上角記一筆買進，之後的賣出、配息、配股都會照日期排在這裡。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, e in
                if i > 0 {
                    Divider().padding(.leading, 76)
                }
                Button {
                    onOpen(e)
                } label: {
                    StockLedgerRow(event: e, stock: data.stock, pal: pal)
                }
                .buttonStyle(MoneyPressStyle())
            }
            if hidden > 0 {
                Divider().padding(.leading, 14)
                Button {
                    withAnimation(.easeOut(duration: 0.25)) { showAll = true }
                } label: {
                    Text("再看 \(hidden) 筆更早的")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            } else if !events.isEmpty {
                Color.clear.frame(height: 6)
            }
        }
        .modifier(StockCardChrome())
    }
}

/// 帳本上半：六格＋含息總報酬
private struct StockLedgerNumbers: View {
    let data: StockCardData
    let pal: TripBoardPalette

    private struct Tile: Identifiable {
        let label: String
        let value: String
        var tone: MoneyTone? = nil
        var sub: String = ""
        var id: String { label }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(tiles) { t in
                    tile(t)
                }
            }
            if data.totalBought > 0 {
                StockTotalReturn(data: data, pal: pal)
            }
            if data.stock.isUSStock {
                Text("美股的金額都換成台幣算（1 美元 ≈ NT$" + FinanceItemText.number(Stock.usdTwdRate) + "，報價時更新）")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .modifier(StockCardChrome())
    }

    private var tiles: [Tile] {
        let d = data
        let s = d.stock
        let cur = s.priceCurrencySymbol
        var out: [Tile] = []
        let dividendSub = d.cashDividendCount > 0 ? "\(d.cashDividendCount) 次配息" : "還沒有配息"
        if s.isSold {
            out.append(Tile(label: "賣出", value: StockCardText.quantity(s, shares: d.soldShares),
                            sub: s.isUSStock ? "" : FinanceItemText.number(d.soldShares, digits: 4) + " 股"))
            out.append(Tile(label: "賣價", value: FinanceItemText.number(s.soldPrice), sub: "平均・" + cur))
            out.append(Tile(label: "均價", value: FinanceItemText.number(s.purchasePrice), sub: "買進・" + cur))
            out.append(Tile(label: "已實現", value: StockCardText.compact(d.realized, signed: true),
                            tone: MoneyTone.change(d.realized, base: max(d.soldBasis, 1)),
                            sub: d.soldBasis > 0 ? FinanceText.signedPercent(d.realized / d.soldBasis) : ""))
            out.append(Tile(label: "股利", value: StockCardText.compact(d.cashDividends),
                            tone: d.cashDividends > 0 ? .warn : nil, sub: dividendSub))
            var range = ""
            if let a = d.firstBuy, let b = s.soldDate {
                range = StockCardText.yearMonth(a) + "–" + StockCardText.yearMonth(b)
            }
            out.append(Tile(label: "持有", value: d.holding ?? "—", sub: range))
            return out
        }
        out.append(Tile(label: "持有", value: StockCardText.quantity(s, shares: s.shares),
                        sub: s.isUSStock ? "" : FinanceItemText.number(s.shares, digits: 4) + " 股"))
        out.append(Tile(label: "均價", value: FinanceItemText.number(s.purchasePrice), sub: cur))
        out.append(Tile(label: "成本", value: StockCardText.compact(d.cost), sub: "還持有的這些"))
        out.append(Tile(label: "未實現",
                        value: s.currentPrice > 0 ? StockCardText.compact(d.unrealized, signed: true) : "—",
                        tone: s.currentPrice > 0 ? MoneyTone.change(d.unrealized, base: max(d.cost, 1)) : nil,
                        sub: s.currentPrice > 0 ? (d.unrealizedRate.map { FinanceText.signedPercent($0) } ?? "") : "還沒有報價"))
        out.append(Tile(label: "已實現", value: StockCardText.compact(d.realized, signed: true),
                        tone: MoneyTone.change(d.realized, base: max(d.totalBought, 1)), sub: "賣掉的那些"))
        out.append(Tile(label: "股利", value: StockCardText.compact(d.cashDividends),
                        tone: d.cashDividends > 0 ? .warn : nil, sub: dividendSub))
        return out
    }

    private func tile(_ t: Tile) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(t.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(t.value)
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(t.tone.map { $0 == .neutral ? Color.primary : $0.color(pal) } ?? Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(t.sub.isEmpty ? " " : t.sub)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(StockCardTile.fill(pal), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// 含息總報酬：未實現＋已實現＋配息 ÷ 總共買進，下面一條三段的條
private struct StockTotalReturn: View {
    let data: StockCardData
    let pal: TripBoardPalette

    private struct Part: Identifiable {
        let label: String
        let value: Double
        let color: Color
        var id: String { label }
    }

    var body: some View {
        let d = data
        let tone = MoneyTone.change(d.totalGain, base: max(d.totalBought, 1))
        let up = MoneyBoardSky.ridgeUp(dark: pal.dark)
        var parts: [Part] = []
        if !d.isSold {
            parts.append(Part(label: "未實現", value: d.unrealized, color: up))
        }
        parts.append(Part(label: "已實現", value: d.realized, color: up.opacity(0.5)))
        parts.append(Part(label: "股利", value: d.cashDividends, color: Color(tb: 0xE8A317)))
        let positive = parts.filter { $0.value > 0 }
        let sum = positive.reduce(0) { $0 + $1.value }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(d.isSold ? "含息報酬" : "含息總報酬")
                    .font(.subheadline.weight(.bold))
                Spacer(minLength: 8)
                Text(FinanceText.signedPercent(d.totalReturn ?? 0))
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(tone == .neutral ? Color.primary : tone.color(pal))
            }
            GeometryReader { geo in
                let gaps = CGFloat(max(0, positive.count - 1)) * 2
                ZStack(alignment: .leading) {
                    Capsule().fill(pal.progressTrack)
                    if sum > 0 {
                        HStack(spacing: 2) {
                            ForEach(positive) { p in
                                Rectangle()
                                    .fill(p.color)
                                    .frame(width: max(2, (geo.size.width - gaps) * CGFloat(p.value / sum)))
                            }
                        }
                        .clipShape(Capsule())
                    }
                }
            }
            .frame(height: 10)
            .accessibilityHidden(true)
            ChipFlowLayout(spacing: 12) {
                ForEach(parts) { p in
                    MoneyLegendItem(mark: .swatch, color: p.color,
                                    text: p.label + " " + StockCardText.compact(p.value), pal: pal)
                }
            }
            Text("總共買進 \(MoneyFormat.short(d.totalBought))，到今天\(d.totalGain >= 0 ? "賺了" : "賠了") \(MoneyFormat.short(abs(d.totalGain)))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 帳本的一行：日期方塊、買／賣／息／股的圓、標題與補充、右邊金額與小膠囊
struct StockLedgerRow: View {
    let event: StockLedgerEvent
    let stock: Stock
    let pal: TripBoardPalette

    var body: some View {
        let e = event
        let look = Self.look(e.kind)
        return HStack(alignment: .center, spacing: 10) {
            VStack(spacing: 0) {
                Text(StockCardText.day(e.date))
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                Text(StockCardText.yearMonth(e.date))
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(width: 52)
            Text(look.glyph)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Color.white)
                .frame(width: 32, height: 32)
                .background(look.color, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                Text(amount)
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(amountColor)
                    .lineLimit(1)
                if let chip {
                    Text(chip.text)
                        .font(.caption2.weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(chip.tone.color(pal))
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(chip.tone.color(pal).opacity(0.12), in: Capsule())
                }
            }
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// 圓裡的字與顏色（白字壓得上去的那一組，深淺色一樣）
    static func look(_ k: StockLedgerEvent.Kind) -> (glyph: String, color: Color) {
        switch k {
        case .buy: return ("買", Color(tb: 0xE5383B))
        case .sell: return ("賣", Color(tb: 0x1F9D57))
        case .cash: return ("息", Color(tb: 0xE09A10))
        case .stock: return ("股", Color(tb: 0x14A3A3))
        }
    }

    private var title: String {
        let e = event
        switch e.kind {
        case .buy: return "買進 " + StockCardText.quantity(stock, shares: e.shares) + " × " + FinanceItemText.number(e.price)
        case .sell: return "賣出 " + StockCardText.quantity(stock, shares: e.shares) + " × " + FinanceItemText.number(e.price)
        case .cash: return "配息"
        case .stock: return "配股 " + StockCardText.quantity(stock, shares: e.shares)
        }
    }

    private var detail: String {
        let e = event
        let after = StockCardText.quantity(stock, shares: e.sharesAfter)
        switch e.kind {
        case .buy: return "買完持有 " + after
        case .sell: return e.sharesAfter > 0.0001 ? "賣完還有 " + after : "全部賣掉"
        case .cash:
            return "每股 " + FinanceItemText.number(e.price, digits: 4) + " × " + FinanceItemText.number(e.shares, digits: 4) + " 股"
        case .stock: return "配完持有 " + after
        }
    }

    private var amount: String {
        let e = event
        switch e.kind {
        case .buy, .sell: return StockCardText.trade(stock, e.amount)
        case .cash: return "+" + StockCardText.trade(stock, e.amount)
        case .stock: return "+" + FinanceItemText.number(e.shares, digits: 4) + " 股"
        }
    }

    private var amountColor: Color {
        switch event.kind {
        case .buy, .sell: return Color.primary
        case .cash: return MoneyTone.warn.color(pal)
        case .stock: return pal.dark ? Color(tb: 0x5FD3D3) : Color(tb: 0x0F7C7C)
        }
    }

    /// 賣出：「已實現 +NT$9.0萬」；買進：「現在 +4.7%」
    private var chip: (text: String, tone: MoneyTone)? {
        let e = event
        if let r = e.realized, abs(r) >= 1 {
            return ("已實現 " + FinanceText.signed(r), MoneyTone.change(r))
        }
        if let n = e.nowRate {
            return ("現在 " + FinanceText.signedPercent(n), MoneyTone.change(n))
        }
        return nil
    }
}

// MARK: - 股利

/// 股利：每次配息一根金色的柱、近 12 個月與殖利率、配息拿回成本幾成（拿回 100% 就是零成本股）
struct StockDividendCard: View {
    let data: StockCardData

    @Environment(\.colorScheme) private var scheme

    private struct Bar: Identifiable {
        let id: String
        let label: String
        let value: Double
    }

    private static let ym: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yy/M"
        return f
    }()

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let d = data
        let s = d.stock
        let fx = s.currencyFactor
        let bars: [Bar] = s.dividends
            .filter { $0.kind == .cash && $0.cashTotal > 0 }
            .sorted { $0.date < $1.date }
            .suffix(8)
            .map { Bar(id: $0.id.uuidString, label: Self.ym.string(from: $0.date), value: $0.cashTotal * fx) }
        return VStack(alignment: .leading, spacing: 10) {
            MoneySectionHeader(title: "股利", trailing: trailing)
            VStack(alignment: .leading, spacing: 12) {
                if !bars.isEmpty {
                    barRow(bars, pal: pal)
                }
                if d.cashDividendCount > 0 {
                    twelveMonths
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let r = d.recovered, !d.isSold {
                    recovery(r, pal: pal)
                }
                if d.stockDividendCount > 0 {
                    Text("配股 \(d.stockDividendCount) 次・共 " + FinanceItemText.number(d.stockDividendShares, digits: 4)
                         + " 股（股數變多，均價跟著攤低）")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .modifier(StockCardChrome())
        }
    }

    private var trailing: String? {
        let d = data
        if d.cashDividendCount > 0 {
            return "累計 " + MoneyFormat.short(d.cashDividends) + "・\(d.cashDividendCount) 次"
        }
        return d.stockDividendCount > 0 ? "配股 \(d.stockDividendCount) 次" : nil
    }

    /// 「近 12 個月 NT$3.7萬・用你的成本算殖利率 2.1%」
    private var twelveMonths: Text {
        let d = data
        guard d.dividends12m > 0 else { return Text("近 12 個月還沒有配息") }
        let amount = Text(MoneyFormat.short(d.dividends12m)).fontWeight(.heavy)
        if let y = d.yieldOnCost {
            return Text("近 12 個月 \(amount)・用你的成本算殖利率 \(Text(FinanceText.percent1(y)).fontWeight(.heavy))")
        }
        return Text("近 12 個月 \(amount)")
    }

    private func barRow(_ bars: [Bar], pal: TripBoardPalette) -> some View {
        let maxV = max(bars.map(\.value).max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(bars) { b in
                VStack(spacing: 4) {
                    Text(StockCardText.compact(b.value))
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(pal.dark ? Color(tb: 0xFFE29A) : Color(tb: 0x9A5B00))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LinearGradient(colors: [Color(tb: 0xFFD36B), Color(tb: 0xE89A12)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 28, height: max(6, 84 * CGFloat(b.value / maxV)))
                    Text(b.label)
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("每次配息")
        .accessibilityValue(bars.map { $0.label + " " + MoneyFormat.short($0.value) }.joined(separator: "，"))
    }

    private func recovery(_ r: Double, pal: TripBoardPalette) -> some View {
        let gold = pal.dark ? Color(tb: 0xFFC14D) : Color(tb: 0xA65300)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("股利已經拿回成本")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(FinanceText.percent1(r))
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(gold)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(tb: 0xE8A317, 0.16))
                    Capsule()
                        .fill(LinearGradient(colors: [Color(tb: 0xFFD36B), Color(tb: 0xE89A12)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * CGFloat(min(1, r))))
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
            Text(r >= 1 ? "已經是「零成本股」：配息拿回來的比成本還多" : "拿回 100% 就是「零成本股」：之後漲跌都是賺的")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 資料

/// 資料：市場、第一次買進、扣款入帳的銀行、證券帳戶、匯率、備註
struct StockInfoCard: View {
    let data: StockCardData
    var bank: String? = nil
    var securities: String? = nil

    var body: some View {
        let d = data
        let s = d.stock
        var rows: [(String, String)] = []
        var market = d.market + "・" + d.title
        if let en = StockScriptName.word(s), en != d.title { market += " " + en }
        rows.append(("市場", market))
        if let first = d.firstBuy {
            rows.append(("第一次買進", FinanceItemText.date(first)))
        }
        if s.isSold, let sold = s.soldDate {
            rows.append(("賣出", FinanceItemText.date(sold)))
        }
        if let bank {
            rows.append(("扣款／入帳", bank))
        }
        if let securities {
            rows.append(("證券帳戶", securities))
        }
        if s.isUSStock {
            rows.append(("匯率", "1 美元 ≈ NT$" + FinanceItemText.number(Stock.usdTwdRate) + "（報價時更新）"))
        }
        let note = s.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 10) {
            MoneySectionHeader(title: "資料")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    if i > 0 {
                        Divider().padding(.leading, 14)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.0)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 84, alignment: .leading)
                        Text(row.1)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .accessibilityElement(children: .combine)
                }
                if !note.isEmpty {
                    Divider().padding(.leading, 14)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("備註")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(note)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                }
            }
            .modifier(StockCardChrome())
        }
    }
}
