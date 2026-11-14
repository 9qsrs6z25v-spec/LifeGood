import Foundation

// MARK: - 小工具自己上網抓價、選價、寫報價的字（小工具 v4）
//
// 這個檔案同時屬於「主 App」與「LifeGoodWidgets」兩個 target（主控契約，三組都不准改）。App 不呼叫這裡的任何東西。
// 規格：scratchpad/widgets/v4/brief.md §3.3、§3.5；judge §2.8、design_wealth W3／W5、§1.3、§3.7。
//
// 為什麼新寫一支、不把 App 的報價程式（StockView.swift 的 TWQuoteService）搬過來（主控定案 3）：
//   • TWQuoteService 綁著 App 的東西：Stock.usdTwdRateKey、StockDailyHistory（suffix 學習表）、
//     UserDefaults.standard 裡學到的上市／上櫃／興櫃表——小工具的行程讀不到 App 的 UserDefaults.standard，
//     搬過去等於兩份學習表各學各的；還要連 StockDailyHistory、StockDailyPoint 一起搬，動到股票頁的報價，風險高。
//   • 小工具一次只要 1～3 檔，Yahoo v8 chart 逐檔就夠（App 的報價也拿它當台股補網與美股主來源）；
//     App 把每一檔要試的 Yahoo 代號（App 自己學到的 .TW／.TWO）寫進快照，小工具照順序試，不用自己猜市場別。
//   • 2026/10/14 用 Python 實際打過（scratchpad/widgets/v4/fetch_check.py）：2330.TW、0050.TW、6488.TWO、AAPL、VOO、
//     GC=F、TWD=X、JPYTWD=X 都有 regularMarketPrice、chartPreviousClose、regularMarketTime、currentTradingPeriod；
//     2330.TWO 回 404（所以要照順序試）。
//
// 這裡有：
//   • WidgetYahooChart       抓一個 Yahoo 代號的 meta（股票、FXRateService.fetchDayQuotes 共用）
//   • WidgetQuoteService     抓一批股票、一批幣別（包成 quotes_v1.json 的形狀：WidgetQuote／WidgetRateQuote）
//   • WidgetQuoteSchedule    什麼時候再抓（台股盤中 15 分、美股盤中 60 分、其他 3 小時；金價 07:00–24:00 每 60 分）
//   • WidgetQuoteText        報價的字：時間（10:42／13:30 收盤／10/13 13:30 的價）、漲跌（▲13（+1.2%））
//   • WidgetFinanceStock.figures／WidgetRateChoice.figures：選價（小工具抓的比 App 新就用小工具的）＋組好全部的字。
//     **小工具畫面檔只准拿這兩支的結果畫，不准自己乘、不准自己拼「NT$」**（金額字一律 WidgetMoneyFormat）。

// MARK: - Yahoo v8 chart

/// Yahoo Finance v8 chart 的 meta（https://query1.finance.yahoo.com/v8/finance/chart/<代號>?range=1d&interval=1d）。
/// 跟 App 的 TWQuoteService.fetchYahoo、FXRateService.fetchQuote 同一個網址、同一個 User-Agent。
///
/// ⚠️ range 一定要 1d：range=1d 的 chartPreviousClose 才是「前一個交易日收盤」。2026/10/14 實測 2330.TW：
///    range=1d → 2490（10/13 收盤，對）；range=2d → 2490（巧合）；range=5d → 2585（10/7 收盤，錯）。
///    interval=1d 時 meta.previousClose 是 null，所以先看 previousClose、沒有再用 chartPreviousClose。
enum WidgetYahooChart {
    struct Meta: Equatable {
        /// 打的是哪個代號（「2330.TW」「GC=F」）
        var symbol: String
        /// regularMarketPrice（> 0 才算抓到）
        var price: Double
        /// 前一個交易日收盤：meta.previousClose，沒有就 chartPreviousClose；都沒有（或 ≤ 0）nil
        var previousClose: Double?
        /// 報價幣別（「TWD」「USD」）；貴金屬要是 USD 才換算
        var currency: String?
        /// regularMarketTime：這個價是幾點成交的
        var marketTime: Date?
        /// currentTradingPeriod.regular.start／end：這一個交易時段
        var sessionStart: Date?
        var sessionEnd: Date?
    }

    /// 小工具裡一次請求最多等幾秒（App 的報價用系統預設 60 秒；小工具的時間軸、↻ 按鈕不能等那麼久）
    static let timeout: TimeInterval = 10

    /// 代號直接插進路徑（跟 App 一樣：「=」「.」在路徑裡是合法字元，URL(string:) 原樣接受）
    static func url(symbol: String) -> URL? {
        URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?range=1d&interval=1d")
    }

    /// 抓一個代號；抓不到（網路、404、沒有價）回 nil
    static func meta(symbol: String) async -> Meta? {
        guard let url = url(symbol: symbol) else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = timeout
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return parse(data, symbol: symbol)
        } catch {
            return nil
        }
    }

    /// 解 JSON（fetch_check.py 照同一套規則驗證）
    static func parse(_ data: Data, symbol: String) -> Meta? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any],
              let chart = json["chart"] as? [String: Any],
              let results = chart["result"] as? [[String: Any]],
              let meta = results.first?["meta"] as? [String: Any],
              let price = number(meta["regularMarketPrice"]), price > 0 else { return nil }
        let rawPrevious: Double? = number(meta["previousClose"]) ?? number(meta["chartPreviousClose"])
        var previous: Double? = nil
        if let p = rawPrevious, p > 0 { previous = p }
        let periods = meta["currentTradingPeriod"] as? [String: Any]
        let regular = periods?["regular"] as? [String: Any]
        return Meta(symbol: symbol,
                    price: price,
                    previousClose: previous,
                    currency: meta["currency"] as? String,
                    marketTime: date(meta["regularMarketTime"]),
                    sessionStart: date(regular?["start"]),
                    sessionEnd: date(regular?["end"]))
    }

    /// JSONSerialization 的數字是 NSNumber（整數、小數都是）；null 是 NSNull → nil
    private static func number(_ any: Any?) -> Double? {
        guard let n = any as? NSNumber else { return nil }
        let v = n.doubleValue
        return v.isFinite ? v : nil
    }

    /// 秒數（epoch）→ Date
    private static func date(_ any: Any?) -> Date? {
        guard let t = number(any), t > 0 else { return nil }
        return Date(timeIntervalSince1970: t)
    }
}

// MARK: - 抓一批

enum WidgetQuoteService {
    /// 同時最多幾個請求（同 App 的報價補網、FXRateService：每輪 4 個，不要連發被限流）
    static let concurrency = 4

    /// 一檔股票：照順序試（preferred＝上次成功的那個排第一，其餘照 App 給的 candidates），第一個抓到的就用
    static func fetchStock(candidates: [String], preferred: String?, now: Date) async -> WidgetQuote? {
        var order: [String] = []
        if let p = preferred, candidates.contains(p) { order.append(p) }
        for c in candidates where !order.contains(c) { order.append(c) }
        for symbol in order {
            guard let m = await WidgetYahooChart.meta(symbol: symbol) else { continue }
            return WidgetQuote(yahooSymbol: symbol,
                               price: m.price,
                               previousClose: m.previousClose,
                               marketTime: m.marketTime,
                               sessionStart: m.sessionStart,
                               sessionEnd: m.sessionEnd,
                               fetchedAt: now)
        }
        return nil
    }

    /// 一批股票。回傳 App 的代號（WidgetFinanceStock.symbol）→ 抓到的價；抓不到的不在結果裡。
    /// cache：上次的快取（裡面記著每一檔上次成功的 Yahoo 代號，排第一個試）
    static func fetchStocks(_ stocks: [WidgetFinanceStock], cache: WidgetQuoteCache?,
                            now: Date) async -> [String: WidgetQuote] {
        var jobs: [(key: String, candidates: [String], preferred: String?)] = []
        var seen = Set<String>()
        for s in stocks where !s.yahooSymbols.isEmpty {
            guard seen.insert(s.symbol).inserted else { continue }
            jobs.append((key: s.symbol, candidates: s.yahooSymbols, preferred: cache?.stocks[s.symbol]?.yahooSymbol))
        }
        var result: [String: WidgetQuote] = [:]
        var idx = 0
        while idx < jobs.count {
            let slice = Array(jobs[idx..<min(idx + concurrency, jobs.count)])
            idx += concurrency
            await withTaskGroup(of: (String, WidgetQuote?).self) { group in
                for job in slice {
                    let key = job.key
                    let candidates = job.candidates
                    let preferred = job.preferred
                    group.addTask { (key, await fetchStock(candidates: candidates, preferred: preferred, now: now)) }
                }
                for await (key, quote) in group {
                    if let quote { result[key] = quote }
                }
            }
        }
        return result
    }

    /// 一批幣別、黃金（FXRateService 的代碼）：FXRateService.fetchDayQuotes（算法同 App 的自動更新）包成快取的形狀
    static func fetchRates(codes: [String], now: Date) async -> [String: WidgetRateQuote] {
        let quotes = await FXRateService.fetchDayQuotes(isoCodes: codes)
        var out: [String: WidgetRateQuote] = [:]
        for (code, q) in quotes {
            out[code] = WidgetRateQuote(rate: q.rate, previousRate: q.previousRate, asOf: q.asOf, fetchedAt: now)
        }
        return out
    }
}

// MARK: - 什麼時候再抓

/// 股票、金價匯率小工具的時間軸：一筆 entry（現在）＋ policy .after(下一次)。
/// 額度（judge §3.7、design_wealth §3.7）：股票一天大約 20–30 次、金價 17 次；↻ 是使用者按的，不算額度。
/// 國定假日不另外做表（抓到的價沒變，花不了多少額度）。
enum WidgetQuoteSchedule {
    /// 台股盤中每 15 分
    static let twSessionStep: TimeInterval = 15 * 60
    /// 美股盤中每 60 分
    static let usSessionStep: TimeInterval = 60 * 60
    /// 都沒開盤：每 3 小時（有更早的開盤就開盤那一刻）
    static let idleStep: TimeInterval = 3 * 3600
    /// 金價匯率 07:00–24:00 每 60 分
    static let ratesStep: TimeInterval = 60 * 60
    /// 快取比這個新就不再抓（↻ 剛抓完、好幾個小工具同一刻重畫、App 叫重畫）
    static let freshFor: TimeInterval = 5 * 60
    /// 下一次至少隔多久（避免算出來的時間太近、一直重畫）
    static let minStep: TimeInterval = 60

    private static let taipei: TimeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
    private static let newYork: TimeZone = TimeZone(identifier: "America/New_York") ?? .current

    /// 台股盤中（含 13:35 抓收盤那一次）：台北時間週一到週五 09:00–13:35
    static func isTWSession(_ date: Date) -> Bool {
        guard let m = weekdayMinute(date, in: taipei) else { return false }
        return m >= 9 * 60 && m < 13 * 60 + 35
    }

    /// 美股盤中：紐約時間週一到週五 09:30–16:05（台北時間夏令 21:30–04:05、冬令 22:30–05:05，日光節約自己跟著換）
    static func isUSSession(_ date: Date) -> Bool {
        guard let m = weekdayMinute(date, in: newYork) else { return false }
        return m >= 9 * 60 + 30 && m < 16 * 60 + 5
    }

    /// 股票小工具下一次重畫（重抓）的時間。hasTW／hasUS：畫面上有沒有台股、美股
    static func nextStockRefresh(after now: Date, hasTW: Bool, hasUS: Bool) -> Date {
        if hasTW && isTWSession(now) {
            var next = now.addingTimeInterval(twSessionStep)
            // 13:35 那一次一定要抓（收盤價）：下一個 15 分會跨過 13:35 就改成 13:35
            if let close = at(minute: 13 * 60 + 35, sameDayAs: now, in: taipei),
               close > now.addingTimeInterval(minStep), close < next {
                next = close
            }
            return next
        }
        if hasUS && isUSSession(now) { return now.addingTimeInterval(usSessionStep) }
        var next = now.addingTimeInterval(idleStep)
        if hasTW, let open = nextWeekdayTime(after: now, minute: 9 * 60, in: taipei), open < next { next = open }
        if hasUS, let open = nextWeekdayTime(after: now, minute: 9 * 60 + 30, in: newYork), open < next { next = open }
        return max(next, now.addingTimeInterval(minStep))
    }

    /// 金價匯率下一次重畫（重抓）：手機現在的時區 07:00–24:00 每 60 分；過了午夜跳到 07:00
    static func nextRatesRefresh(after now: Date) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard let sevenToday = cal.date(bySettingHour: 7, minute: 0, second: 0, of: today),
              let tomorrow = cal.date(byAdding: .day, value: 1, to: today),
              let sevenTomorrow = cal.date(bySettingHour: 7, minute: 0, second: 0, of: tomorrow) else {
            return now.addingTimeInterval(ratesStep)
        }
        if now < sevenToday { return sevenToday }
        let next = now.addingTimeInterval(ratesStep)
        return next < tomorrow ? next : sevenTomorrow
    }

    /// 那個時區、那一天的第幾分鐘；週六日回 nil
    private static func weekdayMinute(_ date: Date, in tz: TimeZone) -> Int? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.weekday, .hour, .minute], from: date)
        if let w = c.weekday, w == 1 || w == 7 { return nil }
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// 那個時區、date 那一天的某分鐘（bySettingHour：日光節約那天也對）
    private static func at(minute: Int, sameDayAs date: Date, in tz: TimeZone) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: date)
    }

    /// now 之後第一個平日的某分鐘（那個時區）
    private static func nextWeekdayTime(after now: Date, minute: Int, in tz: TimeZone) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let today = cal.startOfDay(for: now)
        for offset in 0..<8 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let w = cal.component(.weekday, from: day)
            if w == 1 || w == 7 { continue }
            guard let t = cal.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day) else { continue }
            if t > now { return t }
        }
        return nil
    }
}

// MARK: - 報價的字

/// 股票、金價匯率共用的字。金額、價錢一律走 WidgetMoneyFormat
enum WidgetQuoteText {
    /// 漲跌方向（只拿來上色：紅漲綠跌）。差不到 0.05% 算平盤（同 App MoneyTone.change）：1、-1、0
    static func direction(_ r: Double) -> Int {
        if r > 0.0005 { return 1 }
        if r < -0.0005 { return -1 }
        return 0
    }

    /// 「▲1.2%」「▼0.3%」「平盤」（股票卡片「今日 ▲1.2%」那一段，StockCardBoard.dayCapsule 同一個寫法）
    static func rate(_ r: Double) -> String {
        if abs(r) < 0.0005 { return "平盤" }
        return (r > 0 ? "▲" : "▼") + WidgetMoneyFormat.percent1(abs(r))
    }

    /// 「▲13（+1.2%）」「▼1.6（-0.3%）」「平盤」。diff＝差多少（已經照價錢的精度寫好、不帶正負號）
    static func change(diff: String, r: Double) -> String {
        if abs(r) < 0.0005 { return "平盤" }
        return (r > 0 ? "▲" : "▼") + diff + "（" + WidgetMoneyFormat.signedPercent(r) + "）"
    }

    /// 是幾點的價（design_wealth §1.3：舊的數字不能裝成新的，任何時候都寫）：
    ///   • 小工具抓的、盤中：今天「10:42」、不是今天「10/13 10:42」
    ///   • 小工具抓的、收盤：今天「13:30 收盤」、不是今天「10/13 收盤」
    ///   • App 的價（抓不到）：今天「13:30 的價」、不是今天「10/13 13:30 的價」；不知道幾點「App 的價」
    static func time(_ asOf: Date?, isClose: Bool, fromApp: Bool, now: Date) -> String {
        guard let at = asOf else { return fromApp ? "App 的價" : "" }
        let today = Calendar.current.isDate(at, inSameDayAs: now)
        let clock = DayTimelineFormat.time(at)
        if fromApp {
            return (today ? clock : WidgetDateText.shortDate(at) + " " + clock) + " 的價"
        }
        if isClose {
            return today ? clock + " 收盤" : WidgetDateText.shortDate(at) + " 收盤"
        }
        return today ? clock : WidgetDateText.shortDate(at) + " " + clock
    }

    /// 不是今天的價，漲跌前面要加的日期「10/13」（design_wealth §1.3：「今日」只用在今天的報價）；今天、不知道 nil
    static func datePrefix(_ asOf: Date?, now: Date) -> String? {
        guard let at = asOf, !Calendar.current.isDate(at, inSameDayAs: now) else { return nil }
        return WidgetDateText.shortDate(at)
    }
}

// MARK: - 股票：選價＋組字

/// 這一刻要畫的那個價
struct WidgetLivePrice: Equatable {
    var price: Double
    var previousClose: Double?
    /// 幾點的價（小工具抓的：成交時間；App 的：App 更新的時間；不知道 nil）
    var asOf: Date?
    /// 收盤價（寫「13:30 收盤」）
    var isClose: Bool
    /// 用的是 App 的價（小工具沒抓到，或 App 那一次比較新）
    var fromApp: Bool
}

/// 股票小工具要的全部字（WidgetFinanceStock.figures 組好；畫面只放 Text）
struct WidgetStockFigures: Equatable {
    /// 現價「1,085」「US$512.3」
    var priceText: String
    /// 小型第三行「▲13（+1.2%）」「平盤」；不知道昨收 nil（不寫這行）
    var changeText: String?
    /// 中型列、鎖定畫面「▲1.2%」「平盤」；不知道昨收 nil
    var rateText: String?
    /// 1 漲（紅）、-1 跌（綠）、0 平或不知道（只拿來上色；著色模式靠 ▲▼）
    var direction: Int
    /// 不是今天的價：漲跌前面加的日期「10/13」；今天 nil
    var datePrefix: String?
    /// 「比均價 +21.2%」；均價沒填 nil
    var vsAverageText: String?
    /// 「2 張・NT$217萬」：市值＝股數 × 價 × currencyFactor（同 Stock.marketValue 的式子）
    var holdingText: String
    /// 隱藏金額版「2 張・NT$ ••••」
    var holdingTextMasked: String
    /// 「10:42」「13:30 收盤」「10/13 收盤」「10/13 13:30 的價」「App 的價」
    var timeText: String
    var fromApp: Bool
}

extension WidgetFinanceStock {
    /// 選價：小工具抓的（而且比 App 那一次新）優先；不然用 App 的；都沒有 nil。
    /// 比的是「抓的時間」：小工具 fetchedAt 對 App 的 appQuoteAt（App 沒記時間就當小工具的比較新）
    func livePrice(quote: WidgetQuote?, now: Date) -> WidgetLivePrice? {
        if let q = quote, q.price > 0 {
            var newer = true
            if let appAt = appQuoteAt, appPrice > 0 { newer = q.fetchedAt >= appAt }
            if newer {
                return WidgetLivePrice(price: q.price, previousClose: q.previousClose,
                                       asOf: q.marketTime ?? q.fetchedAt,
                                       isClose: q.isClose(at: now), fromApp: false)
            }
        }
        guard appPrice > 0 else { return nil }
        return WidgetLivePrice(price: appPrice, previousClose: appPreviousClose,
                               asOf: appQuoteAt, isClose: false, fromApp: true)
    }

    /// 市值（台幣）＝股數 × 價 × currencyFactor（Stock.marketValue 同一個式子、同一個乘的順序）
    func marketValue(price: Double) -> Double {
        shares * price * currencyFactor
    }

    /// 全部的字。沒有任何價（App 也還沒報過價、小工具也沒抓到）nil：小工具寫「還沒有報價」
    func figures(quote: WidgetQuote?, now: Date) -> WidgetStockFigures? {
        guard let live = livePrice(quote: quote, now: now) else { return nil }
        let p = live.price
        var changeText: String? = nil
        var rateText: String? = nil
        var direction = 0
        if let prev = live.previousClose, prev > 0 {
            let r = p / prev - 1
            changeText = WidgetQuoteText.change(diff: WidgetMoneyFormat.price(abs(p - prev)), r: r)
            rateText = WidgetQuoteText.rate(r)
            direction = WidgetQuoteText.direction(r)
        }
        var vsAverage: String? = nil
        if avgPrice > 0 {
            vsAverage = "比均價 " + WidgetMoneyFormat.signedPercent(p / avgPrice - 1)
        }
        let priceText = (isUS ? "US$" : "") + WidgetMoneyFormat.price(p)
        let holding = qtyText + "・" + WidgetMoneyFormat.short(marketValue(price: p))
        return WidgetStockFigures(priceText: priceText,
                                  changeText: changeText,
                                  rateText: rateText,
                                  direction: direction,
                                  datePrefix: WidgetQuoteText.datePrefix(live.asOf, now: now),
                                  vsAverageText: vsAverage,
                                  holdingText: holding,
                                  holdingTextMasked: qtyText + "・" + WidgetHideAmounts.mask,
                                  timeText: WidgetQuoteText.time(live.asOf, isClose: live.isClose,
                                                                 fromApp: live.fromApp, now: now),
                                  fromApp: live.fromApp)
    }
}

// MARK: - 金價匯率：選價＋組字

/// 金價匯率小工具要的全部字（WidgetRateChoice.figures 組好）。公開牌價，不受「隱藏金額」影響（design_wealth §1.1 的例外）
struct WidgetRateFigures: Equatable {
    /// 「黃金 每克」「美金」
    var title: String
    /// 鎖定畫面圓形的小字「金/克」「美金」
    var shortTitle: String
    /// 大字：黃金「NT$4,350」、幣別「32.15」
    var valueText: String
    /// 鎖定畫面圓形、一行字：「4,350」「32.15」
    var shortValue: String
    /// 「▲38（+0.9%）比昨天」「跟昨天差不多」；用 App 的價時 nil（App 沒有前一天的價，不寫漲跌）
    var changeText: String?
    /// 鎖定畫面「▲0.9%」「平盤」；同上 nil
    var rateText: String?
    /// 1 漲、-1 跌、0 平或不知道（只拿來上色；著色模式靠 ▲▼）
    var direction: Int
    /// 「10:42」「10/13 10:42」「10/13 08:12 的價」「App 的價」
    var timeText: String
    /// 黃金、白銀「期貨換算」（寫在時間前面：「期貨換算・10:42」，放不下就只寫時間）；幣別 nil
    var sourceText: String?
    var fromApp: Bool
}

extension WidgetRateChoice {
    /// 選價：小工具抓的（比 App 自動更新那一次新）優先；不然 App 自訂幣別匯率裡的值；都沒有 nil
    ///（小工具寫「還沒抓到{title}」）。appUpdatedAt＝WidgetRatesBlock.appUpdatedAt
    func figures(quote: WidgetRateQuote?, appUpdatedAt: Date?, now: Date) -> WidgetRateFigures? {
        let source: String? = isMetal ? "期貨換算" : nil
        var useQuote = false
        if let q = quote, q.rate > 0 {
            useQuote = true
            if let app = appRate, app > 0, let appAt = appUpdatedAt { useQuote = q.fetchedAt >= appAt }
        }
        if useQuote, let q = quote {
            var changeText: String? = nil
            var rateText: String? = nil
            var direction = 0
            if let prev = q.previousRate, prev > 0 {
                let r = q.rate / prev - 1
                if abs(r) < 0.0005 {
                    changeText = "跟昨天差不多"
                } else {
                    let diff = WidgetMoneyFormat.rateDelta(abs(q.rate - prev), scale: q.rate)
                    changeText = WidgetQuoteText.change(diff: diff, r: r) + "比昨天"
                }
                rateText = WidgetQuoteText.rate(r)
                direction = WidgetQuoteText.direction(r)
            }
            return WidgetRateFigures(title: title, shortTitle: shortTitle,
                                     valueText: valueText(q.rate), shortValue: WidgetMoneyFormat.rate(q.rate),
                                     changeText: changeText, rateText: rateText, direction: direction,
                                     timeText: WidgetQuoteText.time(q.asOf ?? q.fetchedAt, isClose: false,
                                                                    fromApp: false, now: now),
                                     sourceText: source, fromApp: false)
        }
        guard let app = appRate, app > 0 else { return nil }
        return WidgetRateFigures(title: title, shortTitle: shortTitle,
                                 valueText: valueText(app), shortValue: WidgetMoneyFormat.rate(app),
                                 changeText: nil, rateText: nil, direction: 0,
                                 timeText: WidgetQuoteText.time(appUpdatedAt, isClose: false, fromApp: true, now: now),
                                 sourceText: source, fromApp: true)
    }

    /// 大字：黃金白銀前面加「NT$」（「NT$4,350」）；幣別只寫數字（「32.15」，前面已經有「美金」）
    private func valueText(_ v: Double) -> String {
        (isMetal ? "NT$" : "") + WidgetMoneyFormat.rate(v)
    }
}
