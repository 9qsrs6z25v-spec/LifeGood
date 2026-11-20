import Foundation

// MARK: - 自訂幣別匯率的自動取值（小工具 v4 從 FinanceModels.swift 搬來）
//
// 這個檔案同時屬於「主 App」與「LifeGoodWidgets」兩個 target（主控契約，三組都不准改）。
// 規格：scratchpad/widgets/v4/brief.md §3.3。
//
// [小工具 v4] 整段 FXRateService 原封不動從 LifeGood/Models/FinanceModels.swift 搬過來（名字、行為、註解一個字都沒改），
// 原檔那一段刪掉（App 照舊叫 FXRateService.isoCode／fetchRates／UpdateOutcome，ExpenseStore.autoUpdateCurrencyRates 不用改）。
// 搬的理由：金價匯率小工具要用同一張別名表、同一個黃金換算（GC=F × TWD=X ÷ 31.1034768 × 克數）自己上網抓價。
// 它本來就只用 Foundation（URLSession、JSONSerialization、TaskGroup），沒有任何 App 型別。
//
// 檔尾的 extension（fetchDayQuotes）是 v4 新加的：小工具要「比昨天」，所以多帶前一日收盤與報價時間；
// App 不呼叫它。抓 Yahoo 的那一段在 WidgetQuoteService.swift 的 WidgetYahooChart（同一個網址、同一個 User-Agent）。
// 原本的 fetchRates／fetchMetalRates／fetchQuote 一行都沒動。

// MARK: - 自訂匯率

/// 設定頁「自訂幣別匯率」的自動取值。
/// 資料源與美股市值換算同一個（Yahoo v8 chart 的 {幣別}TWD=X），
/// 實測 JPY 0.1982／EUR 36.96／CNY 4.74 等皆與台銀牌價同量級。
///
/// 使用者的幣別欄是自由文字（「美金」「日圓」……），所以先過一張別名表
/// 對成 ISO 代碼再查；對不上的（例如自創代號）不動它，維持手動值。
///
/// [v25.542] 加上黃金、白銀。Yahoo 的 XAUTWD=X、XAUUSD=X 都已下市（回 Not Found），
/// 台銀黃金牌價網頁又有防機器人驗證 App 抓不到，只剩紐約期貨 GC=F／SI=F
/// （美元／金衡盎司）抓得到，所以貴金屬是拿期貨價乘美元匯率自己換算成台幣。
enum FXRateService {
    /// 常見寫法 → 代碼。鍵一律存「正規化後」的樣子（大寫、半形括號、沒有空白，見 normalizedKey），
    /// 不然永遠對不到。
    private static let aliases: [String: String] = [
        "美金": "USD", "美元": "USD", "USD": "USD",
        "日圓": "JPY", "日幣": "JPY", "日元": "JPY", "JPY": "JPY",
        "歐元": "EUR", "EUR": "EUR",
        "人民幣": "CNY", "RMB": "CNY", "CNY": "CNY",
        "港幣": "HKD", "港元": "HKD", "HKD": "HKD",
        "英鎊": "GBP", "GBP": "GBP",
        "澳幣": "AUD", "澳元": "AUD", "AUD": "AUD",
        "加幣": "CAD", "加元": "CAD", "CAD": "CAD",
        "韓元": "KRW", "韓圜": "KRW", "KRW": "KRW",
        "新加坡幣": "SGD", "新幣": "SGD", "星幣": "SGD", "SGD": "SGD",
        "瑞士法郎": "CHF", "CHF": "CHF",
        "泰銖": "THB", "THB": "THB",
        "越南盾": "VND", "VND": "VND",
        "馬來幣": "MYR", "令吉": "MYR", "MYR": "MYR",
        "菲律賓披索": "PHP", "披索": "PHP", "PHP": "PHP",
        "印尼盾": "IDR", "IDR": "IDR",
        "紐幣": "NZD", "紐元": "NZD", "NZD": "NZD",
        // [v25.569] 使用者回報「ZAR 辨識不到南非幣」：補南非幣，順便補幾種台灣常見的幣別。
        // 一樣查 Yahoo 的 {代碼}TWD=X（ZARTWD=X 等都有報價）。
        "南非幣": "ZAR", "南非蘭特": "ZAR", "蘭特": "ZAR", "ZAR": "ZAR",
        "瑞典克朗": "SEK", "SEK": "SEK",
        "挪威克朗": "NOK", "NOK": "NOK",
        "丹麥克朗": "DKK", "DKK": "DKK",
        "印度盧比": "INR", "盧比": "INR", "INR": "INR",
        "土耳其里拉": "TRY", "里拉": "TRY", "TRY": "TRY",
        "墨西哥披索": "MXN", "MXN": "MXN",
        "澳門幣": "MOP", "澳門元": "MOP", "MOP": "MOP",
        "阿聯迪拉姆": "AED", "迪拉姆": "AED", "AED": "AED",
        // [v25.542] 貴金屬用內部代碼（不是 ISO）。ISO 的 XAU 本來指一盎司，但這裡的「1 單位」
        // 是記帳時輸入的數量，買金飾、黃金存摺都以克計，使用者也明說要每克，所以 XAU＝每克；
        // 要每台錢、每盎司另外填「黃金(錢)」「黃金(盎司)」。內部代碼會直接出現在
        // 「查詢失敗：…」訊息裡，所以取成看得懂的樣子。
        "XAU": "XAU", "黃金": "XAU", "金": "XAU", "GOLD": "XAU", "金價": "XAU",
        "黃金(克)": "XAU", "金(克)": "XAU", "黃金/克": "XAU", "黃金每克": "XAU",
        "XAU(克)": "XAU", "XAU/G": "XAU",
        "黃金(錢)": "XAU(錢)", "金(錢)": "XAU(錢)", "黃金一錢": "XAU(錢)", "台錢": "XAU(錢)",
        "黃金/錢": "XAU(錢)", "XAU(錢)": "XAU(錢)",
        "黃金(盎司)": "XAU(盎司)", "金(盎司)": "XAU(盎司)", "XAU/OZ": "XAU(盎司)",
        "XAU(OZ)": "XAU(盎司)", "金衡盎司": "XAU(盎司)", "XAU(盎司)": "XAU(盎司)",
        "XAG": "XAG", "白銀": "XAG", "銀": "XAG", "SILVER": "XAG",
        "白銀(克)": "XAG", "銀(克)": "XAG", "XAG/G": "XAG"
    ]

    /// [v25.542] 貴金屬內部代碼 → Yahoo 期貨代號＋一單位幾克（nil＝就是一金衡盎司，不經過克）。
    /// 不在這張表裡的代碼照舊走 {代碼}TWD=X。
    private static let metals: [String: (symbol: String, gramsPerUnit: Double?)] = [
        "XAU": (symbol: "GC=F", gramsPerUnit: 1),
        "XAU(錢)": (symbol: "GC=F", gramsPerUnit: 3.75),   // 台錢＝3.75 克
        "XAU(盎司)": (symbol: "GC=F", gramsPerUnit: nil),
        "XAG": (symbol: "SI=F", gramsPerUnit: 1)
    ]

    /// [v25.542] 一金衡盎司幾克：期貨報價以金衡盎司計，換成每克要除這個數
    private static let gramsPerTroyOunce = 31.1034768

    /// [v25.542] 查表前把同一個意思的不同打法收成一種：iPhone 中文鍵盤打出來的是全形括號，
    /// 也常有人在中間留空白（「黃金 (克)」「黃金 / 克」），不收的話別名表得把每種組合都列一遍。
    /// 舊幣別的鍵本來就沒有括號、斜線、空白，對得到的結果不變。
    private static func normalizedKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespaces)
            .uppercased()
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: "／", with: "/")
            .components(separatedBy: .whitespaces)
            .joined()
    }

    /// 把使用者輸入的幣別文字對成代碼（ISO，或貴金屬的內部代碼）；對不上回 nil（該列維持手動）
    static func isoCode(for raw: String) -> String? {
        let key = normalizedKey(raw)
        guard !key.isEmpty else { return nil }
        return aliases[key]
    }

    /// 抓一批幣別的對台幣匯率。回傳代碼 → 匯率；抓不到的不出現在結果裡。
    /// 併發上限 4，比照股票報價補網的既有節流。
    static func fetchRates(isoCodes: [String]) async -> [String: Double] {
        let all = Set(isoCodes)
        // [v25.542] 貴金屬沒有 {代碼}TWD=X 可查，分出來另外算；其餘照舊
        let metalCodes = all.filter { metals[$0] != nil }.sorted()
        let wanted = all.filter { metals[$0] == nil }.sorted()
        guard !all.isEmpty else { return [:] }
        var result: [String: Double] = [:]
        var idx = 0
        while idx < wanted.count {
            let slice = Array(wanted[idx..<min(idx + 4, wanted.count)])
            idx += 4
            await withTaskGroup(of: (String, Double?).self) { group in
                for code in slice {
                    group.addTask { (code, await fetchRate(isoCode: code)) }
                }
                for await (code, r) in group {
                    if let r { result[code] = r }
                }
            }
        }
        if !metalCodes.isEmpty {
            // 這一批有美金的話 TWD=X 剛抓過，直接沿用（失敗就算失敗，不重抓）
            let metalRates = await fetchMetalRates(codes: metalCodes,
                                                   usdTwdFetched: wanted.contains("USD"),
                                                   usdTwd: result["USD"])
            for (code, rate) in metalRates { result[code] = rate }
        }
        return result
    }

    /// [v25.542] 就是 fetchQuote 的回傳型別（現價＋報價幣別）；取個名字，
    /// TaskGroup 的型別參數才不會是一長串巢狀具名 tuple
    private typealias YahooQuote = (price: Double, currency: String?)

    /// [v25.542] 貴金屬每單位台幣。GC=F／SI=F／TWD=X 一次更新各只抓一次——同時有
    /// XAU、XAU(錢)、XAU(盎司) 也只打一次 GC=F。最多 3 個代號，不超過併發上限 4。
    /// - usdTwdFetched: 一般幣別那段已經抓過 TWD=X（此時 usdTwd 就是它的結果，nil＝抓失敗）
    private static func fetchMetalRates(codes: [String], usdTwdFetched: Bool, usdTwd: Double?) async -> [String: Double] {
        var symbols = Set(codes.compactMap { metals[$0]?.symbol })
        if !usdTwdFetched { symbols.insert("TWD=X") }
        var quotes: [String: YahooQuote] = [:]
        await withTaskGroup(of: (String, YahooQuote?).self) { group in
            for symbol in symbols {
                group.addTask { (symbol, await fetchQuote(symbol: symbol)) }
            }
            for await (symbol, quote) in group {
                if let quote { quotes[symbol] = quote }
            }
        }
        guard let fx = usdTwdFetched ? usdTwd : quotes["TWD=X"]?.price else { return [:] }
        var result: [String: Double] = [:]
        for code in codes {
            // 期貨報價應該是美元；萬一 Yahoo 改成別的幣別，寧可算查詢失敗，也不要帶入差一個量級的金價
            guard let spec = metals[code], let quote = quotes[spec.symbol], quote.currency == "USD" else { continue }
            let twdPerOunce = quote.price * fx
            let rate: Double
            if let grams = spec.gramsPerUnit {
                rate = twdPerOunce / gramsPerTroyOunce * grams
            } else {
                rate = twdPerOunce
            }
            // 金價到「元」以下兩位就夠，多的小數只會讓設定頁的比值欄擠不下
            result[code] = (rate * 100).rounded() / 100
        }
        return result
    }

    /// 一次自動更新的結果（設定頁組訊息用；App 啟動時的靜默更新忽略它）
    struct UpdateOutcome {
        var updated = 0
        /// 認得但查價失敗的代碼（ISO，或貴金屬內部代碼如 XAU(錢)，訊息裡直接列出也看得懂）
        var failedIso: [String] = []
        /// 別名表認不得的幣別原文
        var unknown: [String] = []
        var recognizedAny: Bool { updated > 0 || !failedIso.isEmpty }
    }

    /// 單一幣別對台幣。USD 的 Yahoo 代號是特例「TWD=X」，其餘為「{代碼}TWD=X」。
    private static func fetchRate(isoCode: String) async -> Double? {
        let pair = isoCode == "USD" ? "TWD=X" : "\(isoCode)TWD=X"
        return await fetchQuote(symbol: pair)?.price
    }

    /// [v25.542] 抓 Yahoo 單一代號的現價。貴金屬要確認報價幣別是美元，所以把 meta.currency 一起帶回；
    /// 一般幣別只用 price，行為跟以前一樣。
    private static func fetchQuote(symbol: String) async -> (price: Double, currency: String?)? {
        // 代號直接插進路徑：「=」在網址路徑裡是合法字元，URL(string:) 原樣接受（TWD=X 一直這樣用）
        let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?range=1d&interval=1d"
        guard let url = URL(string: urlString) else { return nil }
        do {
            var req = URLRequest(url: url)
            req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let chart = json["chart"] as? [String: Any],
                  let meta = (chart["result"] as? [[String: Any]])?.first?["meta"] as? [String: Any],
                  let price = meta["regularMarketPrice"] as? Double, price > 0 else { return nil }
            return (price: price, currency: meta["currency"] as? String)
        } catch { return nil }
    }
}

// MARK: - [小工具 v4] 金價匯率小工具：現價＋前一日收盤＋報價時間

extension FXRateService {
    /// 一個代碼（isoCode(for:) 的結果）的「現在」與「前一日收盤」，都是 1 單位幾台幣
    struct DayQuote: Equatable {
        /// 跟 fetchRates 同一個數（同一個網址、同一個換算；貴金屬一樣四捨五入到兩位小數）
        var rate: Double
        /// 前一日收盤換成同一個單位（貴金屬＝期貨前一日收盤 × 美金前一日收盤）；Yahoo 沒給 nil
        var previousRate: Double?
        /// 這個價是幾點的（Yahoo regularMarketTime；貴金屬看期貨那一筆）
        var asOf: Date?
    }

    /// 抓一批代碼（「USD」「JPY」「XAU」「XAU(錢)」…）的現價與前一日收盤。抓不到的不在結果裡。
    /// 一般幣別打 {代碼}TWD=X（美金 TWD=X）；貴金屬打期貨（GC=F／SI=F）＋TWD=X，同一個代號一次只打一次。
    /// 併發上限 4（同 fetchRates）。**App 不呼叫**（App 照舊用 fetchRates）；小工具用（WidgetQuoteService.fetchRates）。
    static func fetchDayQuotes(isoCodes: [String]) async -> [String: DayQuote] {
        let all = Set(isoCodes.filter { !$0.isEmpty })
        guard !all.isEmpty else { return [:] }
        var symbols = Set<String>()
        for code in all {
            if let spec = metals[code] {
                symbols.insert(spec.symbol)
                symbols.insert("TWD=X")
            } else {
                symbols.insert(code == "USD" ? "TWD=X" : "\(code)TWD=X")
            }
        }
        let list = symbols.sorted()
        var metas: [String: WidgetYahooChart.Meta] = [:]
        var idx = 0
        while idx < list.count {
            let slice = Array(list[idx..<min(idx + 4, list.count)])
            idx += 4
            await withTaskGroup(of: (String, WidgetYahooChart.Meta?).self) { group in
                for symbol in slice {
                    group.addTask { (symbol, await WidgetYahooChart.meta(symbol: symbol)) }
                }
                for await (symbol, meta) in group {
                    if let meta { metas[symbol] = meta }
                }
            }
        }
        var result: [String: DayQuote] = [:]
        for code in all {
            if let quote = dayQuote(code: code, metas: metas) { result[code] = quote }
        }
        return result
    }

    /// 一個代碼的 DayQuote（metas 是這一輪抓到的 Yahoo meta，key＝Yahoo 代號）
    private static func dayQuote(code: String, metas: [String: WidgetYahooChart.Meta]) -> DayQuote? {
        guard let spec = metals[code] else {
            let pair = code == "USD" ? "TWD=X" : "\(code)TWD=X"
            guard let m = metas[pair] else { return nil }
            return DayQuote(rate: m.price, previousRate: m.previousClose, asOf: m.marketTime)
        }
        // 跟 fetchMetalRates 同一條：期貨要是美元報價（不是就算抓不到），× 美元匯率，換成每單位
        guard let future = metas[spec.symbol], future.currency == "USD",
              let fx = metas["TWD=X"] else { return nil }
        let rate = metalRate(ouncePrice: future.price, usdTwd: fx.price, gramsPerUnit: spec.gramsPerUnit)
        var previous: Double? = nil
        if let p = future.previousClose, let q = fx.previousClose {
            previous = metalRate(ouncePrice: p, usdTwd: q, gramsPerUnit: spec.gramsPerUnit)
        }
        return DayQuote(rate: rate, previousRate: previous, asOf: future.marketTime)
    }

    /// 每金衡盎司的美元價 → 每單位台幣，四捨五入到兩位小數。算式逐字照 fetchMetalRates（原函式不動）
    private static func metalRate(ouncePrice: Double, usdTwd fx: Double, gramsPerUnit: Double?) -> Double {
        let twdPerOunce = ouncePrice * fx
        let rate: Double
        if let grams = gramsPerUnit {
            rate = twdPerOunce / gramsPerTroyOunce * grams
        } else {
            rate = twdPerOunce
        }
        return (rate * 100).rounded() / 100
    }
}
