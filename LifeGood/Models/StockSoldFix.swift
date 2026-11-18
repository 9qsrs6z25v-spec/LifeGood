import Foundation

// MARK: - [v25.630 stocksold] 有帳本的股票用〔已賣出〕開關賣出（judge_stocksold.md §C；build/stocksold/brief.md）
//
// 使用者：「那你看我11/17賣出這個宜特 怎麼戶頭沒有入帳資料」。原因：有帳本交易的股票，交割只照帳本寫
// （LifeStore.rewriteStockSettlements 的 `if !stock.transactions.isEmpty`），編輯股票打開〔已賣出〕只改了
// isSold／soldPrice／soldDate、另外記一筆「賣出 X（虧損）／（獲利）」，帳本沒有賣出 → 戶頭不入帳、卡片已實現 0、
// 之後加股利 recompute 又變回沒賣。
//
// 這一版（不加 Stock／StockTransaction 欄位、不加同步鍵、不自動改資料）：
// • 有帳本的股票，開關＝在帳本補一筆「賣出剩下全部」，寫法同帳本〔賣出〕表單（upserting：補種舊資料 → 同 id 換掉／加在後面
//   → 照日期排 → 重算）；呼叫端接著 store.update＋rewriteStockSettlements（同帳本表單），開關以前記的那筆收入／支出刪掉
//   （帳本會算已實現損益，留著會重複算）。帳本〔賣出〕本來就不記收入／支出，所以結果跟帳本賣出一樣。
// • 開關補的那一筆 id 固定（toggleSellId：WealthIDs.stable，SHA256，每檔一個）。關掉〔已賣出〕只刪「帳本最後一筆賣出、而且是這個 id」；
//   帳本自己記的賣出不動（擋下來，請到帳本改）。
// • 已經壞掉的（標了已賣出、帳本沒賣光）：股票卡提示卡〔補記賣出〕按了才補（mismatch → fixed），按之前什麼都不改。
// • 沒有帳本交易的舊式股票：formPlan 回 .legacy，AddStockView 照 22bab81 一字不改（開關＋T+2 入帳＋虧損支出）。
// 規則照 build/stocksold/sim_stocksold.py 一個函式一個函式對照（台北、洛杉磯兩個時區）。

enum StockSoldFix {

    /// 帳本持有「還有」的門檻（同 recomputeFromTransactions 的 netShares <= 0.0001 算賣光）
    static let heldEpsilon: Double = 0.0001

    // MARK: 開關補的那一筆

    /// 開關（編輯股票〔已賣出〕、股票卡〔補記賣出〕）在帳本補的那一筆賣出的 id：每檔固定一個。
    /// ⚠️ 種子字串一個字都不能改：改了就認不得以前補的那一筆（關掉〔已賣出〕刪不到）
    static func toggleSellId(for stockId: UUID) -> UUID {
        WealthIDs.stable("stock-toggle-sell-" + stockId.uuidString)
    }

    /// 照帳本算現在還持有幾股（不改傳進來的；同 recomputeFromTransactions）。沒有帳本交易＝nil
    static func ledgerShares(_ stock: Stock) -> Double? {
        guard !stock.transactions.isEmpty else { return nil }
        var s = stock
        s.recomputeFromTransactions()
        return s.shares
    }

    /// 帳本照算是不是已經賣光（recompute 的 isSold）。沒有帳本交易＝false
    static func ledgerSoldOut(_ stock: Stock) -> Bool {
        guard !stock.transactions.isEmpty else { return false }
        var s = stock
        s.recomputeFromTransactions()
        return s.isSold
    }

    /// 帳本最後一筆賣出（照日期；同一刻的取陣列後面那筆）
    static func lastSell(_ stock: Stock) -> StockTransaction? {
        var best: StockTransaction?
        for tx in stock.transactions where tx.kind == .sell {
            if let b = best, tx.date < b.date { continue }
            best = tx
        }
        return best
    }

    /// 帳本〔買進／賣出〕表單存一筆交易的寫法（StockTransactionEditor.save 抽出來；開關、提示卡同一支）：
    /// 舊式資料先補種、同 id 換掉否則加在後面、照日期排、照帳本重算。呼叫端接著 store.update＋rewriteStockSettlements
    static func upserting(_ tx: StockTransaction, into stock: Stock) -> Stock {
        var s = stock
        s.seedTransactionsFromLegacyIfNeeded()
        if let idx = s.transactions.firstIndex(where: { $0.id == tx.id }) {
            s.transactions[idx] = tx
        } else {
            s.transactions.append(tx)
        }
        s.transactions.sort { $0.date < $1.date }
        s.recomputeFromTransactions()
        return s
    }

    /// 在帳本補一筆「賣出剩下全部」：張數＝帳本現在的持有（補之前照帳本算）、價格與日子照傳進來的。
    /// id 用 toggleSellId；這一檔已經有那個 id（賣光後又買進、再用開關賣）就用新的 id（那一筆關開關刪不到，要到帳本刪）。
    /// 只給有帳本交易的股票用；價格 ≤ 0、帳本已經沒有持股＝nil
    static func closeOut(_ stock: Stock, price: Double, date: Date) -> (stock: Stock, tx: StockTransaction)? {
        guard price > 0, let held = ledgerShares(stock), held > heldEpsilon else { return nil }
        let fixedId = toggleSellId(for: stock.id)
        let taken = stock.transactions.contains { $0.id == fixedId }
        let tx = StockTransaction(id: taken ? UUID() : fixedId, date: date, kind: .sell,
                                  lots: held / 1000, price: price)
        return (upserting(tx, into: stock), tx)
    }

    /// 同 closeOut，只要改好的那一檔
    static func appendingCloseOutSell(_ stock: Stock, price: Double, date: Date) -> Stock? {
        closeOut(stock, price: price, date: date)?.stock
    }

    /// 關掉〔已賣出〕：帳本最後一筆賣出是開關補的那一筆（toggleSellId）才刪，刪完照帳本重算（同帳本表單的刪除：不補種）。不是＝nil
    static func removingToggleSell(_ stock: Stock) -> Stock? {
        let fixedId = toggleSellId(for: stock.id)
        guard let last = lastSell(stock), last.id == fixedId else { return nil }
        var s = stock
        s.transactions.removeAll { $0.id == fixedId }
        s.recomputeFromTransactions()
        return s
    }

    // MARK: 已經壞掉的（股票卡提示卡）

    /// 標了已賣出、帳本沒賣光：要補記的那一筆（張數＝帳本還持有的、價格與日子＝標的）
    struct Mismatch: Equatable {
        let stockId: UUID
        let heldShares: Double
        let price: Double
        let date: Date
        /// 帳本裡本來有沒有賣出（沒有＝已實現損益是 0）
        let ledgerHasSell: Bool
        /// 開關以前記的「賣出 X（虧損）」「（獲利）」
        let switchExpenseId: UUID?
        let switchIncomeId: UUID?

        var settleDate: Date { StockTransaction.taiwanSettlementDate(from: date) }
    }

    /// 有帳本交易、isSold、soldPrice > 0、有賣出日、帳本照算還持有 > 0.0001。其他一律 nil（沒有帳本的舊式股票也是 nil）
    static func mismatch(_ stock: Stock) -> Mismatch? {
        guard stock.isSold, stock.soldPrice > 0, let d = stock.soldDate,
              let held = ledgerShares(stock), held > heldEpsilon else { return nil }
        return Mismatch(stockId: stock.id, heldShares: held, price: stock.soldPrice, date: d,
                        ledgerHasSell: stock.transactions.contains { $0.kind == .sell },
                        switchExpenseId: stock.linkedExpenseId, switchIncomeId: stock.linkedIncomeId)
    }

    /// 〔補記賣出〕：照 mismatch 補那一筆（closeOut）、兩個連結清掉。記帳那兩筆由呼叫端 removeSwitchRecords 刪，
    /// 接著 store.update＋rewriteStockSettlements。沒有 mismatch＝nil
    static func fixed(_ stock: Stock) -> Stock? {
        guard let m = mismatch(stock), var s = appendingCloseOutSell(stock, price: m.price, date: m.date) else { return nil }
        s.linkedExpenseId = nil
        s.linkedIncomeId = nil
        return s
    }

    /// 刪掉開關記的「賣出 X（虧損）／（獲利）」：同 AddStockView 關掉〔已賣出〕的刪法（支出走 delete，連照片一起刪；收入 removeAll）
    static func removeSwitchRecords(expenseId: UUID?, incomeId: UUID?, in expense: ExpenseStore) {
        if let eid = expenseId, let exp = expense.expenses.first(where: { $0.id == eid }) {
            expense.delete(exp)
        }
        if let iid = incomeId { expense.incomes.removeAll { $0.id == iid } }
    }

    // MARK: 編輯股票存檔（AddStockView.save）

    enum FormPlan {
        /// 沒有帳本交易（含新增股票）：照 22bab81（開關＋T+2 入帳＋虧損支出／獲利收入）
        case legacy
        /// 有帳本、賣出那幾格跟打開時一樣：賣出的事一樣都不碰（isSold／價／日／兩個連結照舊，不記收入／支出）
        case keep
        /// 有帳本、帳本沒賣光、開關關著：照 22bab81 關掉的寫法（清三欄、刪開關記的收入／支出）
        case clear
        /// 有帳本、開關打開：帳本補一筆賣出剩下全部（tx＝補的那一筆）
        case closeOut(Stock, StockTransaction)
        /// 有帳本、開關關掉：刪掉開關補的那一筆（tx＝刪掉的那一筆）
        case reopen(Stock, StockTransaction)
        /// 有帳本、開關補的那一筆改價／改日（tx＝改好的那一筆）
        case resell(Stock, StockTransaction)
        /// 擋下來（errorBanner 的字）
        case blocked(String)

        /// 交易改好、已照帳本重算的那一檔（closeOut／reopen／resell）
        var ledgerStock: Stock? {
            switch self {
            case .closeOut(let s, _), .reopen(let s, _), .resell(let s, _): return s
            default: return nil
            }
        }

        /// 照 22bab81 記／刪「賣出 X（虧損）／（獲利）」那一段（.legacy、.clear）
        var usesSwitchRecords: Bool {
            switch self {
            case .legacy, .clear: return true
            default: return false
            }
        }
    }

    static let blockedPriceText = "已標記為賣出，請輸入賣出價格"
    static let blockedReopenText = "這檔是照帳本賣光的。要改成沒賣，請到股票卡的帳本刪掉那筆賣出。"
    static let blockedResellText = "這檔是照帳本賣光的。賣出價、日期請到股票卡的帳本改那筆賣出。"
    static let blockedNothingText = "帳本裡這檔已經沒有持股，沒有可以賣的。"

    /// 編輯股票的張數檢查：照舊要 > 0；帳本已經賣光的（持有 0 張，表單帶出來就是「0」）也可以存
    /// （22bab81 這種一按儲存就擋「請輸入股票名稱、張數和買入價格」：開關關不掉、備註也改不了）。沒有帳本的舊式股票照舊
    static func lotsAllowed(_ lots: Double, editing: Stock?) -> Bool {
        if lots > 0 { return true }
        guard lots == 0, let e = editing else { return false }
        return ledgerSoldOut(e)
    }

    /// 賣出價一樣沒：照表單打開時的寫法比（AddStockView.loadEditing 用 %.2f）
    static func samePrice(_ a: Double, _ b: Double) -> Bool {
        String(format: "%.2f", a) == String(format: "%.2f", b)
    }

    /// 編輯股票存檔怎麼處理賣出（editing＝打開表單時的那一檔；isSold／price／date＝表單上的）
    static func formPlan(editing: Stock?, isSold: Bool, price: Double, date: Date,
                         calendar: Calendar = Calendar(identifier: .gregorian)) -> FormPlan {
        guard let e = editing, !e.transactions.isEmpty else { return .legacy }
        if e.isSold, isSold, samePrice(e.soldPrice, price),
           let d = e.soldDate, calendar.isDate(d, inSameDayAs: date) {
            return .keep
        }
        let soldOut = ledgerSoldOut(e)
        if !isSold {
            guard soldOut else { return .clear }
            guard let gone = lastSell(e), let s = removingToggleSell(e) else { return .blocked(blockedReopenText) }
            return .reopen(s, gone)
        }
        guard price > 0 else { return .blocked(blockedPriceText) }
        if !soldOut {
            guard let r = closeOut(e, price: price, date: date) else { return .blocked(blockedNothingText) }
            return .closeOut(r.stock, r.tx)
        }
        // 價格欄沒改（照 %.2f 字比）＝開關補的那一筆照原價，只改日子：表單帶出的是帳本加權均價，部分賣過時不是那一筆的價
        // （[驗] 帳本賣 3 張×100、開關補 1 張×100.5 → 表單帶「100.12」；只改日子，以前那一筆會被改成 100.12、已實現 +500 變 +120）
        guard let gone = lastSell(e), let removed = removingToggleSell(e),
              let r = closeOut(removed, price: samePrice(e.soldPrice, price) ? gone.price : price, date: date) else {
            return .blocked(blockedResellText)
        }
        return .resell(r.stock, r.tx)
    }

    /// 把 plan 套到表單組好的那一檔（item：名稱、代號、備註、帳戶、股數…照表單；transactions／dividends＝editing 的）
    static func applying(_ plan: FormPlan, to item: Stock, editing: Stock?) -> Stock {
        var s = item
        switch plan {
        case .keep:
            guard let e = editing else { return item }
            s.isSold = e.isSold
            s.soldPrice = e.soldPrice
            s.soldDate = e.soldDate
            s.linkedExpenseId = e.linkedExpenseId
            s.linkedIncomeId = e.linkedIncomeId
        case .closeOut(let fixed, _), .reopen(let fixed, _), .resell(let fixed, _):
            s.transactions = fixed.transactions
            s.linkedExpenseId = nil
            s.linkedIncomeId = nil
            s.recomputeFromTransactions()
        case .legacy, .clear, .blocked:
            break
        }
        return s
    }

    // MARK: 字（不用 NumberFormatter：同 WealthFormat）

    /// 「2」「2.5」「1,234.5678」：最多 digits 位小數（4 或 2），尾巴的 0 不寫
    static func trimmed(_ v: Double, digits: Int = 4) -> String {
        let scale: Double = digits >= 4 ? 10_000 : 100
        let width = digits >= 4 ? 4 : 2
        let r = (Swift.abs(v) * scale).rounded()
        guard r.isFinite, r < 9e15 else { return String(format: "%.0f", v) }
        let n = Int64(r)
        let unit = Int64(scale)
        let whole = WealthFormat.grouped(Double(n / unit), decimals: 0)
        var frac = String(n % unit)
        while frac.count < width { frac = "0" + frac }
        while frac.hasSuffix("0") { frac.removeLast() }
        let body = frac.isEmpty ? whole : whole + "." + frac
        return (v < 0 && n != 0) ? "-" + body : body
    }

    /// 台股「2 張」「0.5 張」；美股「15 股」（同帳本那一列 StockCardText.quantity 的單位）
    static func quantityText(_ shares: Double, isUS: Bool) -> String {
        isUS ? trimmed(shares) + " 股" : trimmed(shares / 1000) + " 張"
    }

    /// 每股價「103.5」「1,085」（最多兩位小數）
    static func priceText(_ v: Double) -> String { trimmed(v, digits: 2) }

    /// 這筆賣出的錢（原幣）：台股「NT$207,000」、美股「US$1,234.50」
    static func moneyText(_ v: Double, isUS: Bool) -> String {
        isUS ? "US$" + WealthFormat.grouped(v, decimals: 2) : WealthFormat.ntd(v)
    }

    /// 已實現損益（台幣）：「-NT$136,000」「+NT$12,000」
    static func realizedText(_ v: Double) -> String {
        v < 0 ? WealthFormat.ntd(v) : "+" + WealthFormat.ntd(v)
    }

    /// 「11/17」；不是今年寫「2025/11/17」（固定西曆：手機設民國曆也不寫 115 年）
    static func dayText(_ d: Date, now: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        let md = "\(c.month ?? 0)/\(c.day ?? 0)"
        return c.year == calendar.component(.year, from: now) ? md : "\(c.year ?? 0)/" + md
    }

    static let cardTitle = "帳本沒有這次賣出"
    static let doneTitle = "補記好了"

    /// 提示卡那一段：「這檔標了已賣出（11/17・103.5），但帳本沒有賣出紀錄，所以戶頭沒有入帳、已實現損益是 0。」
    static func cardMessage(_ m: Mismatch, isUS: Bool, now: Date,
                            calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let when = dayText(m.date, now: now, calendar: calendar) + "・" + priceText(m.price)
        if !m.ledgerHasSell {
            return "這檔標了已賣出（\(when)），但帳本沒有賣出紀錄，所以戶頭沒有入帳、已實現損益是 0。"
        }
        let q = quantityText(m.heldShares, isUS: isUS)
        return "這檔標了已賣出（\(when)），但帳本還有 \(q)沒有賣出紀錄，所以這 \(q)賣的錢沒有入帳。"
    }

    /// 〔補記賣出 2 張 × 103.5〕
    static func buttonTitle(_ m: Mismatch, isUS: Bool) -> String {
        "補記賣出 " + quantityText(m.heldShares, isUS: isUS) + " × " + priceText(m.price)
    }

    /// 開關以前記的那一筆：「也會刪掉當初開關記的「賣出 宜特（虧損）」NT$136,000（帳本會算已實現損益，留著會重複算）。」
    static func switchRecordLine(title: String, amount: Double) -> String {
        "也會刪掉當初開關記的「\(title)」\(WealthFormat.ntd(amount))（帳本會算已實現損益，留著會重複算）。"
    }

    /// 按下去之前問一次的那幾行（confirmationDialog 的 message）
    static func confirmMessage(_ m: Mismatch, isUS: Bool, switchRecord: String?, now: Date,
                               calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let trade = dayText(m.date, now: now, calendar: calendar)
        let settle = dayText(m.settleDate, now: now, calendar: calendar)
        let q = quantityText(m.heldShares, isUS: isUS)
        let p = priceText(m.price)
        let money = moneyText(m.heldShares * m.price, isUS: isUS)
        var s = "帳本加一筆 \(trade) 賣出 \(q) × \(p)，\(settle) 交割，\(money) 入帳到交割銀行。"
        if let r = switchRecord { s += "\n" + r }
        return s
    }

    /// 補好之後提示卡換成這一張（換一檔、按〔知道了〕就收起來；不存檔）
    struct Done: Equatable {
        let stockId: UUID
        let shares: Double
        let price: Double
        let tradeDate: Date
        let settleDate: Date
        /// 補好之後的已實現損益（台幣；moneyRealizedProfit）
        let realized: Double
        let isUS: Bool
    }

    static func done(from m: Mismatch, fixed: Stock) -> Done {
        Done(stockId: fixed.id, shares: m.heldShares, price: m.price, tradeDate: m.date,
             settleDate: m.settleDate, realized: fixed.moneyRealizedProfit, isUS: fixed.isUSStock)
    }

    /// 「已補記賣出 2 張 × 103.5，已實現損益 -NT$136,000。」＋交割那一句（交割日還沒到：先在銀行頁「接下來 30 天」，
    /// 那天起在存摺明細；同 WealthFacts 存摺明細只列到今天、以後的在「接下來」）
    static func doneMessage(_ d: Done, now: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let q = quantityText(d.shares, isUS: d.isUS)
        let p = priceText(d.price)
        let r = realizedText(d.realized)
        let head = "已補記賣出 \(q) × \(p)，已實現損益 \(r)。"
        let day = dayText(d.settleDate, now: now, calendar: calendar)
        if calendar.startOfDay(for: d.settleDate) > calendar.startOfDay(for: now) {
            return head + "\n\(day) 交割入帳：今天還沒到，先在銀行頁「接下來 30 天」看得到，\(day) 起在存摺明細。"
        }
        return head + "\n\(day) 已交割入帳，銀行頁的存摺明細看得到。"
    }

    /// 編輯股票〔已賣出〕底下那一行灰字（有帳本的股票才有；沒有要說的＝nil）
    static func formHint(_ plan: FormPlan, editing: Stock?, now: Date,
                         calendar: Calendar = Calendar(identifier: .gregorian)) -> String? {
        let isUS = editing?.isUSStock ?? false
        func line(_ tx: StockTransaction) -> String {
            let day = dayText(tx.date, now: now, calendar: calendar)
            let q = quantityText(tx.shares, isUS: isUS)
            let p = priceText(tx.price)
            return "\(day) 賣出 \(q) × \(p)"
        }
        switch plan {
        case .closeOut(_, let tx):
            let settle = dayText(tx.settlementDate, now: now, calendar: calendar)
            return "這檔有帳本：存檔會在帳本補一筆 \(line(tx))（剩下的全部），\(settle) 交割入帳；不會另外記「賣出（虧損／獲利）」。"
        case .reopen(_, let tx):
            return "存檔會刪掉帳本裡開關補的那筆賣出（\(line(tx))）。"
        case .resell(_, let tx):
            return "存檔會把帳本裡開關補的那筆賣出改成 \(line(tx))。"
        case .blocked(let why):
            return why
        case .keep:
            guard let e = editing, mismatch(e) != nil else { return nil }
            return "這檔標了已賣出，但帳本沒有賣光；到股票卡按〔補記賣出〕補上，戶頭才會入帳。"
        case .legacy, .clear:
            return nil
        }
    }
}
