import Foundation
import WidgetKit
import AppIntents

// MARK: - 小工具自己抓的價：quotes_v1.json 的讀寫、↻ 重抓（小工具 v4）
//
// 只屬於「LifeGoodWidgets」target。由 G2 實作，規格見 scratchpad/widgets/v4/brief.md 的 G2-1。
// （主控建好的空檔，已登記 pbxproj：A01A000002000088／A01B000002000088）
//
// • WidgetQuoteStore：quotes_v1.json（WidgetQuoteCache，契約在 WidgetSnapshot.swift）的讀、合併寫、
//   「夠不夠新」，以及 provider 用的「該抓就抓、合併、回最新的快取」。**只有小工具讀寫**，App 不讀不寫
//   （App 的股價照它自己的報價程式；這裡抓到的價只給小工具看）。
//   上網一律經契約的 WidgetQuoteService（Yahoo v8 chart／FXRateService.fetchDayQuotes），這裡不另寫網路程式。
//   股票的下一次重畫（stockReloadAt）＝契約的 WidgetQuoteSchedule.nextStockRefresh，[審查] 外加收盤後等收盤價的 15 分重抓。
// • RefreshQuotesIntent：小工具右下角的 ↻。在小工具的行程裡跑（openAppWhenRun = false、型別只在小工具 target），
//   強制重抓那幾檔股票／那幾個幣別，寫快取，叫股票或金價匯率小工具重畫。不改 LifeGood 的任何資料。
//
// 同一個行程裡好幾個小工具可能同一刻重抓（股票小、中、金價匯率、↻）：合併寫檔在 NSLock 裡排隊
// （讀 → 疊上新的 → 寫），網路在鎖外；merge 是同步函式，鎖不會跨 await 拿著。
//
// 型別（internal 的都帶 WidgetQuoteStore 前綴或是 brief 指定的名字）：WidgetQuoteStore、RefreshQuotesIntent

// MARK: - 快取

enum WidgetQuoteStore {
    /// 合併寫檔排隊用（同一個行程裡的好幾個 timeline／↻）
    private static let lock = NSLock()

    /// 沒快照、沒持股時，多久再跟系統要一次（App 寫快照時本來就會叫重畫，這只是保險）
    static let idleRetry: TimeInterval = 3 * 3600

    /// [審查] 收盤後還沒拿到收盤那一筆時，多久再抓一次、收盤後最多等多久（見 stockReloadAt）
    static let closeRetryStep: TimeInterval = 15 * 60
    static let closeRetryWindow: TimeInterval = 3600

    /// quotes_v1.json；沒有、解不開、schema 對不上回 nil
    static func read() -> WidgetQuoteCache? {
        WidgetSnapshotStore.read(WidgetQuoteCache.self)
    }

    /// 只換有抓到的那幾個（沒抓到的留舊值），寫檔，回合併後的。
    /// 寫不進去（App Group 沒生效）也照樣回合併後的，這一次的畫面還是用得到新價
    @discardableResult
    static func merge(stocks: [String: WidgetQuote], rates: [String: WidgetRateQuote],
                      now: Date) -> WidgetQuoteCache {
        lock.lock()
        defer { lock.unlock() }
        var cache: WidgetQuoteCache = read() ?? WidgetQuoteCache.empty(at: now)
        for (symbol, quote) in stocks {
            cache.stocks[symbol] = quote
        }
        for (code, quote) in rates {
            cache.rates[code] = quote
        }
        cache.generatedAt = now
        WidgetSnapshotStore.write(cache)
        return cache
    }

    /// 這幾檔（App 的代號 WidgetFinanceStock.symbol）在快取裡都比 maxAge 新。空清單＝不用抓＝true
    static func isFresh(stocks symbols: [String], in cache: WidgetQuoteCache?, now: Date,
                        maxAge: TimeInterval) -> Bool {
        for symbol in symbols {
            guard let quote = cache?.stocks[symbol] else { return false }
            if !isRecent(quote.fetchedAt, now: now, maxAge: maxAge) { return false }
        }
        return true
    }

    /// 這幾個代碼（FXRateService 的「XAU」「USD」）在快取裡都比 maxAge 新。空清單＝true
    static func isFresh(rates codes: [String], in cache: WidgetQuoteCache?, now: Date,
                        maxAge: TimeInterval) -> Bool {
        for code in codes {
            guard let quote = cache?.rates[code] else { return false }
            if !isRecent(quote.fetchedAt, now: now, maxAge: maxAge) { return false }
        }
        return true
    }

    /// provider、↻ 用：force 或快取不夠新（WidgetQuoteSchedule.freshFor）的那幾檔才上網抓，合併，回最新的快取。
    /// 不夠新的才抓（抓不到的那一檔不會害其他檔每次都重抓）；一個都沒抓到就回現在檔裡的
    static func refreshStocks(_ stocks: [WidgetFinanceStock], now: Date, force: Bool) async -> WidgetQuoteCache? {
        let cache = read()
        let need: [WidgetFinanceStock] = stocksToFetch(stocks, cache: cache, now: now, force: force)
        guard !need.isEmpty else { return cache }
        let fetched: [String: WidgetQuote] = await WidgetQuoteService.fetchStocks(need, cache: cache, now: now)
        guard !fetched.isEmpty else { return read() ?? cache }
        return merge(stocks: fetched, rates: [:], now: now)
    }

    /// 同上，金價匯率（codes＝FXRateService 的代碼；空字串、重複的先拿掉）
    static func refreshRates(codes: [String], now: Date, force: Bool) async -> WidgetQuoteCache? {
        let cache = read()
        let need: [String] = codesToFetch(codes, cache: cache, now: now, force: force)
        guard !need.isEmpty else { return cache }
        let fetched: [String: WidgetRateQuote] = await WidgetQuoteService.fetchRates(codes: need, now: now)
        guard !fetched.isEmpty else { return read() ?? cache }
        return merge(stocks: [:], rates: fetched, now: now)
    }

    /// 股票、金價匯率小工具的 entry 時間：now，再加下一個 00:00（比 reloadAt 早才放）——
    /// 「13:30 收盤」「10:42」過了午夜要變「10/13 收盤」「10/13 10:42」、漲跌前面加「10/13」，
    /// 每一筆 entry 的字都用那一筆自己的時間組
    static func entryDates(now: Date, reloadAt: Date) -> [Date] {
        var dates: [Date] = [now]
        if let midnight = WidgetDateText.midnights(after: now, count: 1).first, midnight < reloadAt {
            dates.append(midnight)
        }
        return dates
    }

    /// 股票小工具（小、中）下一次重畫的時間：照 WidgetQuoteSchedule.nextStockRefresh（畫面上有沒有台股、美股）。
    /// [審查] 再加一條保險：收盤已經過了（1 小時內），快取裡卻還是盤中那一筆（Yahoo 台股可能慢一點、
    /// 13:35 那次可能抓失敗）→ 15 分後再抓一次，不等下一個 3 小時。正常情況（13:35 抓到 13:30 的收盤）不會多抓
    static func stockReloadAt(_ stocks: [WidgetFinanceStock], cache: WidgetQuoteCache?, now: Date) -> Date {
        let hasTW: Bool = stocks.contains { !$0.isUS }
        let hasUS: Bool = stocks.contains { $0.isUS }
        let base: Date = WidgetQuoteSchedule.nextStockRefresh(after: now, hasTW: hasTW, hasUS: hasUS)
        let waiting: Bool = stocks.contains { stock in
            guard let quote = cache?.stocks[stock.symbol] else { return false }
            return awaitsClose(quote, now: now)
        }
        guard waiting else { return base }
        return min(base, now.addingTimeInterval(closeRetryStep))
    }

    // MARK: 小零件

    /// 這一筆是這個交易時段的盤中價（成交時間在開盤之後、收盤前 1 分鐘之前），可是收盤已經過了、還在 1 小時內
    private static func awaitsClose(_ quote: WidgetQuote, now: Date) -> Bool {
        guard let traded = quote.marketTime, let start = quote.sessionStart, let end = quote.sessionEnd else {
            return false
        }
        if traded < start || traded >= end.addingTimeInterval(-60) { return false }
        return now >= end && now < end.addingTimeInterval(closeRetryWindow)
    }

    /// 抓的時間在 maxAge 以內（手機時間被往回調、抓的時間比現在晚，一律當不新）
    private static func isRecent(_ fetchedAt: Date, now: Date, maxAge: TimeInterval) -> Bool {
        let age: TimeInterval = now.timeIntervalSince(fetchedAt)
        return age >= 0 && age <= maxAge
    }

    /// 要上網抓的那幾檔：force 全部；否則快取不夠新的，加上 [v4 驗證] 收盤後 1 小時內快取還是盤中那一筆的
    ///（13:30 剛抓過、還沒拿到收盤集合競價那一筆時，13:35 那一次快取才 5 分鐘以內、會被當成夠新而跳過——
    /// 「13:35 一定要抓」就落空，要等 15 分後的重試）
    private static func stocksToFetch(_ stocks: [WidgetFinanceStock], cache: WidgetQuoteCache?,
                                      now: Date, force: Bool) -> [WidgetFinanceStock] {
        if force { return stocks }
        let maxAge: TimeInterval = WidgetQuoteSchedule.freshFor
        return stocks.filter { stock in
            if !isFresh(stocks: [stock.symbol], in: cache, now: now, maxAge: maxAge) { return true }
            guard let quote = cache?.stocks[stock.symbol] else { return true }
            return awaitsClose(quote, now: now)
        }
    }

    /// 要上網抓的那幾個代碼：去空字串、去重複（照原本順序）；force 全部，否則只有快取不夠新的
    private static func codesToFetch(_ codes: [String], cache: WidgetQuoteCache?,
                                     now: Date, force: Bool) -> [String] {
        var unique: [String] = []
        for code in codes where !code.isEmpty && !unique.contains(code) {
            unique.append(code)
        }
        if force { return unique }
        let maxAge: TimeInterval = WidgetQuoteSchedule.freshFor
        return unique.filter { !isFresh(rates: [$0], in: cache, now: now, maxAge: maxAge) }
    }
}

// MARK: - ↻ 重抓

/// ↻ 重抓：在小工具裡跑（不開 App），強制抓、寫快取、叫那一種小工具重畫。
/// 參數只用 String（v2 規則：參數型別越單純越不會出事）：股票是逗號分隔的 UUID 字串、幣別是逗號分隔的 FX 代碼。
/// 股票只給 id，代號、要試哪些 Yahoo 代號從 finance 快照讀（快照改了也不會抓錯檔）
struct RefreshQuotesIntent: AppIntent {
    static var title: LocalizedStringResource = "重抓報價"
    static var description = IntentDescription("重新抓股價或金價匯率（只給小工具看，不改 LifeGood 的資料）")
    /// 不開 App：在小工具的行程裡抓完、寫完 quotes_v1.json 就結束
    static var openAppWhenRun: Bool = false

    /// 逗號分隔的股票 UUID；"" 不抓股票
    @Parameter(title: "股票")
    var stockIds: String

    /// 逗號分隔的 FX 代碼（「XAU,USD」）；"" 不抓幣別
    @Parameter(title: "幣別")
    var rateCodes: String

    init() {}

    init(stockIds: [UUID], rateCodes: [String]) {
        self.stockIds = stockIds.map { $0.uuidString }.joined(separator: ",")
        self.rateCodes = rateCodes.joined(separator: ",")
    }

    func perform() async throws -> some IntentResult {
        let now = Date()
        let ids: [String] = Self.split(stockIds)
        let codes: [String] = Self.split(rateCodes)
        var kinds: [String] = []
        if !ids.isEmpty {
            let stocks: [WidgetFinanceStock] = Self.stocks(ids: ids)
            if !stocks.isEmpty {
                _ = await WidgetQuoteStore.refreshStocks(stocks, now: now, force: true)
            }
            kinds.append(contentsOf: WidgetKind.stockKinds)
        }
        if !codes.isEmpty {
            _ = await WidgetQuoteStore.refreshRates(codes: codes, now: now, force: true)
            kinds.append(contentsOf: WidgetKind.ratesKinds)
        }
        // 系統按完也會重畫按的那一個；這裡多叫一次，讓放在別處的同一種（股票小、中）一起換新價
        WidgetRefresh.reload(kinds)
        return .result()
    }

    /// 「a,b,,c」→ ["a", "b", "c"]（去頭尾空白、去空的）
    private static func split(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// finance 快照裡 id 對得上的那幾檔（賣掉、刪掉的就不抓）
    private static func stocks(ids: [String]) -> [WidgetFinanceStock] {
        let items: [WidgetFinanceStock] = WidgetSnapshotStore.read(WidgetFinanceSnapshot.self)?.stocks.items ?? []
        return items.filter { ids.contains($0.id.uuidString) }
    }
}
