import Foundation

// MARK: - 個股〔買進／賣出／配息／配股〕表單打開那一刻的字、數字的字（v25.612 stockinput）
//
// 只屬於「LifeGood」target。規格：scratchpad/radar/judge_stockinput.md §C；分工：scratchpad/radar/build/stockinput/brief.md。
//
// 使用者回報：「按下買進/賣出/股利時的買入介面跑出來會卡卡的，且有時候點到張數欄位無法打字，但切換多工再切回就可以打字」。
// 以前兩張表單（StockDetailView.swift 的 StockTransactionEditor／StockDividendEditor）一開始的字是在 onAppear 的
// loadInitial 才填：第一格畫面先是預設（買進／配息、空白），下一拍才換成你按的那一種、編輯那一筆的字（整張重排）。
// 現在 init 就用 State(initialValue:) 給好，字照這裡算。
//
// ⚠️ 這裡算出來的字要跟以前「loadInitial＋接著那一輪 onChange」最後留在欄位上的一模一樣（sim_stockinput.py 一條一條對照）：
//   • 交易：loadInitial 填好張數、單價（"%.2f"）、總金額之後，那一輪 onChange(of: priceText)（游標不在總金額）
//     會再叫一次 syncTotalFromQuantity，總金額最後是「欄位上的張數 × 每單位股數 × 欄位上的單價」（單價 > 0 才算）。
//   • 股利：loadInitial 之後那一輪 onChange(of: sharesAtEventText)（游標不在總配息）會再叫一次 syncTotalFromPerShare，
//     總配息最後是「欄位上的每股 × 欄位上的股數（取整數）」四捨五入（股數 > 0 才算）。
//   兩支 sync 的寫法照抄在下面，表單裡那兩支一個字都沒改。

/// 表單裡數字的字（輸入欄、換算結果）。寫法照搬兩張表單以前的 private static 函式，一個字都沒改；
/// 只有 NumberFormatter 改成 static 共用（以前每算一次、每重畫一次 body 就 new 一個）。設定一模一樣。
enum StockEditorText {
    /// 金額：最多兩位小數，不帶千分位（這是輸入欄，逗號會讓人以為要自己打）
    static func money(_ v: Double) -> String {
        let r = (v * 100).rounded() / 100
        return r == r.rounded() ? String(format: "%.0f", r) : String(format: "%g", r)
    }

    /// 數量：台股的張數可能到小數第 4 位（0.0001 張 = 0.1 股），美股本來就可能有零股
    static func quantity(_ v: Double) -> String {
        let r = (v * 10000).rounded() / 10000
        return r == r.rounded() ? String(format: "%.0f", r) : String(format: "%g", r)
    }

    /// 股數顯示：整數就不帶小數點
    static func shares(_ v: Double) -> String {
        let r = (v * 100).rounded() / 100
        return r == r.rounded() ? String(format: "%.0f", r) : String(format: "%g", r)
    }

    /// 編輯交易時張數欄的字（以前 StockTransactionEditor.formatLots）
    static func lots(_ v: Double) -> String {
        if v == v.rounded() { return String(format: "%.0f", v) }
        return String(format: "%g", v)
    }

    /// 每股配息顯示用：最多 6 位小數、去掉尾隨的 0，絕不吐科學記號。
    /// 不能用 "%g"——0.000008 會變成 "8e-06" 出現在輸入欄裡。（以前 StockDividendEditor.perShareDisplay）
    static func perShare(_ v: Double) -> String {
        if v == v.rounded() { return String(format: "%.0f", v) }
        var s = String(format: "%.6f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// 以前 StockTransactionEditor.decimalText：十進位、不帶千分位、最多 digits 位小數。
    /// 表單只用 2、4、6 位（美元金額、每股美元價、股數），這三種各留一個；其他位數照以前現做一個
    static func decimal(_ v: Double, max digits: Int) -> String {
        let f: NumberFormatter
        switch digits {
        case 2: f = decimal2
        case 4: f = decimal4
        case 6: f = decimal6
        default: f = makeDecimal(digits)
        }
        return f.string(from: NSNumber(value: v)) ?? "0"
    }

    /// 以前 StockTransactionEditor.amountSummary 的美股那一行：「US$」＋十進位（帶千分位）最多兩位小數
    static func usd(_ v: Double) -> String {
        "US$" + (usdSummary.string(from: NSNumber(value: v)) ?? "0")
    }

    private static func makeDecimal(_ digits: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.maximumFractionDigits = digits
        return f
    }

    private static let decimal2 = makeDecimal(2)
    private static let decimal4 = makeDecimal(4)
    private static let decimal6 = makeDecimal(6)

    private static let usdSummary: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal; f.maximumFractionDigits = 2
        return f
    }()
}

/// 兩張表單打開那一刻每一格的字（init 用 State(initialValue:) 給）
enum StockEditorSeed {
    struct TransactionSeed: Equatable {
        var date: Date
        var kind: StockTransactionKind
        var lotsText: String
        var priceText: String
        var totalText: String
    }

    struct DividendSeed: Equatable {
        var date: Date
        var kind: StockDividendKind
        var lotsText: String
        var perShareText: String
        var sharesAtEventText: String
        var totalText: String
        var note: String
        var photoFileNames: [String]
    }

    /// 交易表單：新增＝你按的那一種（買進／賣出）、欄位空白、日期今天；編輯＝那一筆的字。
    /// sharesPerUnit：這一檔一個單位幾股（台股 1000、美股 1；查不到股票時照以前當台股 1000）
    static func transaction(editing e: StockTransaction?, initialKind: StockTransactionKind,
                            sharesPerUnit: Double, now: Date) -> TransactionSeed {
        guard let e else {
            return TransactionSeed(date: now, kind: initialKind, lotsText: "", priceText: "", totalText: "")
        }
        // 以前 loadInitial：存檔的 lots 永遠是「股數 ÷ 1000」，畫面上要換成這支股票的單位
        let lotsText = StockEditorText.lots(e.lots * 1000 / sharesPerUnit)
        let priceText = String(format: "%.2f", e.price)
        var totalText = StockEditorText.money(e.shares * e.price)
        // 以前接著那一輪 onChange(of: priceText) → syncTotalFromQuantity（寫法照抄）
        let q = Double(lotsText) ?? 0
        let p = Double(priceText) ?? 0
        if p > 0 {
            totalText = q > 0 ? StockEditorText.money(q * sharesPerUnit * p) : ""
        }
        return TransactionSeed(date: e.date, kind: e.kind, lotsText: lotsText, priceText: priceText,
                           totalText: totalText)
    }

    /// 股利表單：新增＝你按的那一種（配息／配股）、日期今天，配息先帶入今天的持股股數；編輯＝那一筆的字、備註、文件照片。
    /// stock：表單打開那一刻的這一檔（查不到是 nil：單位照台股、持股 0）
    static func dividend(editing e: StockDividend?, initialKind: StockDividendKind,
                         stock: Stock?, now: Date) -> DividendSeed {
        let sharesPerUnit = stock?.sharesPerUnit ?? 1000
        var d = DividendSeed(date: now, kind: .cash, lotsText: "", perShareText: "", sharesAtEventText: "",
                         totalText: "", note: "", photoFileNames: [])
        if let e {
            d.date = e.date
            d.kind = e.kind
            d.lotsText = e.lots > 0 ? String(format: "%g", e.lots * 1000 / sharesPerUnit) : ""
            d.perShareText = e.perShare > 0 ? StockEditorText.perShare(e.perShare) : ""
            d.sharesAtEventText = e.sharesAtEvent > 0 ? "\(Int(e.sharesAtEvent))" : ""
            if e.perShare > 0, e.sharesAtEvent > 0 {
                d.totalText = String(format: "%g", (e.perShare * e.sharesAtEvent).rounded())
            }
            d.note = e.note
            d.photoFileNames = e.photoFileNames
        } else {
            d.kind = initialKind
            // 新增時，配息預設帶入當下持股股數
            if d.kind == .cash {
                d.sharesAtEventText = "\(Int(heldShares(stock, on: now, excludingDividend: nil)))"
            }
        }
        // 以前接著那一輪 onChange(of: sharesAtEventText)（欄位從空白變成有字才會叫）→ syncTotalFromPerShare（寫法照抄）
        if !d.sharesAtEventText.isEmpty {
            let p = Double(d.perShareText) ?? 0
            let s = Double(d.sharesAtEventText) ?? 0
            if s > 0 {
                d.totalText = p > 0 ? String(format: "%g", (p * s).rounded()) : ""
            }
        }
        return d
    }

    /// 以前 StockDividendEditor.currentHeldShares：這一檔在 date 當下的持股股數（用 transactions 累積；
    /// 沒有逐筆交易的舊資料用 shares）。加上 date 之前已發放的配股（編輯中的那一筆不算）
    static func heldShares(_ stock: Stock?, on date: Date, excludingDividend id: UUID?) -> Double {
        guard let stock else { return 0 }
        if stock.transactions.isEmpty {
            return stock.shares
        }
        var s: Double = 0
        for tx in stock.transactions where tx.date <= date {
            s += tx.kind == .buy ? tx.shares : -tx.shares
        }
        for div in stock.dividends where div.kind == .stock && div.date <= date && div.id != id {
            s += div.sharesEarned
        }
        return max(0, s)
    }

    /// 以前 StockTransactionEditor.sharesBeforeThisTx：這一筆**之前**的庫存股數（對帳單累計股數回推用）。
    /// 編輯既有交易時要把它自己扣掉，不然會拿自己減自己
    static func sharesBefore(_ stock: Stock?, excludingTransaction id: UUID?) -> Double {
        guard let s = stock else { return 0 }
        var total = s.dividends
            .filter { $0.kind == .stock }
            .reduce(0.0) { $0 + $1.sharesEarned }
        for tx in s.transactions where tx.id != id {
            total += tx.kind == .buy ? tx.shares : -tx.shares
        }
        return total
    }
}
