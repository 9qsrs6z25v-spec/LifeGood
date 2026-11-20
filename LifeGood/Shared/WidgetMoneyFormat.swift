import Foundation

// MARK: - 小工具 v4：跟 App 一模一樣的金額寫法
//
// 這個檔案同時屬於「主 App」與「LifeGoodWidgets」兩個 target（主控契約，三組都不准改）。
// 規格：scratchpad/widgets/v4/brief.md §3.4。
//
// 為什麼有這個檔：股票、金價匯率小工具會自己上網抓新價，市值（股數 × 價 × 美金匯率）、比均價、漲跌
// 要用新價重算——這是小工具裡**唯一允許算錢、寫金額的地方**（judge §2.1「金額寫法跟 App 共用同一段程式」）。
// 其他小工具（還能花、接下來要繳、我的車、淨資產）照舊只放 App 組好的字。
//
// 為什麼是「照抄」不是「搬」：App 那幾支散在 FinanceModels.swift（Double.ntdWanString）、MoneyBoardKit.swift
// （MoneyFormat）、FinanceBoards.swift（FinanceText）、FinanceItems.swift（FinanceItemText）、StockCardViews.swift
// （StockCardText），全 App 幾百個呼叫點；整段搬進共用檔要動一大片 App 程式（v4 範圍外、風險高）。
// 所以這裡**逐字照抄**它們的函式本體（只換名字：self → value、私有 formatter 換成這個檔自己的），
// 由 scratchpad/widgets/v4/fmt_check.py 每次核對：
//   1. 兩邊的函式本體去掉註解、空白、換名之後一個 token 都不差；
//   2. 把兩邊的本體各自轉成 Python、跑 300 個值，結果一模一樣，再對幾個 App 畫面上的字（NT$4.6萬、NT$1720萬…）。
// **App 那幾支以後改了，這裡要跟著改，fmt_check.py 會抓到。**
//
// 例外（標 [widget-guard] 的那幾行）：App 的 MoneyFormat.percent／FinanceText.percent1 遇到 inf／nan 會在 Int(...) 當掉；
// 小工具當掉就是一片空白，所以先擋掉、回「—」。有限的數字結果跟 App 一模一樣。
//
// 只用 Foundation。NumberFormatter 的設定也照抄（沒設 locale＝跟著手機，跟 App 同一台手機同一個樣子）；
// iOS 7 起 NumberFormatter 格式化是執行緒安全的，小工具的時間軸在背景執行緒用沒問題。

/// ＝ FinanceModels.swift 的 _ntdCurrencyFormatter
private let widgetNtdCurrencyFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencySymbol = "NT$"
    f.maximumFractionDigits = 0
    return f
}()

/// ＝ FinanceItems.swift 的 financeNumberFormatter(_:)
private func widgetFinanceNumberFormatter(_ digits: Int) -> NumberFormatter {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.minimumFractionDigits = 0
    f.maximumFractionDigits = digits
    return f
}

private let widgetFinanceNumber0 = widgetFinanceNumberFormatter(0)
private let widgetFinanceNumber1 = widgetFinanceNumberFormatter(1)
private let widgetFinanceNumber2 = widgetFinanceNumberFormatter(2)
private let widgetFinanceNumber4 = widgetFinanceNumberFormatter(4)

enum WidgetMoneyFormat {

    // MARK: 照抄 App

    /// ＝ Double.ntdWanString（FinanceModels.swift）＝ MoneyFormat.short（MoneyBoardKit.swift）。
    /// 一億以上「NT$1.5億」、一萬以上「NT$4.6萬」「NT$1720萬」、一萬以下「NT$2,402」
    static func short(_ value: Double) -> String {
        // [v25.530] 先四捨五入到一位小數再判斷是不是整數：以前先判斷再格式化，
        // 3,480,000.4 這種會被 %.1f 進位成「348.0萬」，三個這樣的數加起來就寫成「860.0萬」。
        func trimmed(_ x: Double) -> String {
            let r = (x * 10).rounded() / 10
            return (r == r.rounded()) ? String(format: "%.0f", r) : String(format: "%.1f", r)
        }
        let a = Swift.abs(value)
        let sign = value < 0 ? "-" : ""
        if a >= 100_000_000 {           // ≥ 1億 → 億
            return "\(sign)NT$\(trimmed(a / 100_000_000))億"
        }
        if a >= 10_000 {                // ≥ 1 萬 → 萬
            let wan = a / 10_000
            // %.1f 格式化後若捨入到 10000，改以億顯示，避免「10000.0萬」
            if wan >= 9_999.95 { return "\(sign)NT$\(trimmed(a / 100_000_000))億" }
            return "\(sign)NT$\(trimmed(wan))萬"
        }
        return widgetNtdCurrencyFormatter.string(from: NSNumber(value: value)) ?? "NT$0"
    }

    /// ＝ MoneyFormat.percent（MoneyBoardKit.swift）：「62%」
    static func percent(_ r: Double) -> String {
        guard r.isFinite, Swift.abs(r) < 1e12 else { return "—" }   // [widget-guard]
        return "\(Int((r * 100).rounded()))%"
    }

    /// ＝ FinanceText.signed（FinanceBoards.swift）：「+NT$41.2萬」「-NT$3,200」
    static func signed(_ v: Double) -> String {
        (v > 0 ? "+" : "") + short(v)
    }

    /// ＝ FinanceText.percent1（FinanceBoards.swift）：「1.2%」（一位小數；10% 以上不寫小數）
    static func percent1(_ r: Double) -> String {
        guard r.isFinite, Swift.abs(r) < 1e12 else { return "—" }   // [widget-guard]
        let p = r * 100
        return abs(p) >= 10 ? "\(Int(p.rounded()))%" : String(format: "%.1f%%", p)
    }

    /// ＝ FinanceText.signedPercent（FinanceBoards.swift）：「+21.2%」「-3.5%」
    static func signedPercent(_ r: Double) -> String {
        (r > 0 ? "+" : (r < 0 ? "-" : "")) + percent1(abs(r))
    }

    /// ＝ FinanceItemText.number（FinanceItems.swift）：「612」「61.25」「1,234.5」（小數最多 digits 位）
    static func number(_ v: Double, digits: Int = 2) -> String {
        // [v25.538] 以前只分「兩位」「四位」：digits: 1 也印兩位，車卡寫成「持有 2.07 年」「每度 NT$7.94」
        let f: NumberFormatter
        switch digits {
        case ...0: f = widgetFinanceNumber0
        case 1: f = widgetFinanceNumber1
        case 2: f = widgetFinanceNumber2
        default: f = widgetFinanceNumber4
        }
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.0f", v)
    }

    /// ＝ StockCardText.price（StockCardViews.swift）：牌子上的價錢，千元以上不寫小數、百元以上一位、其他兩位（1,085／895.2／23.45）
    static func price(_ v: Double) -> String {
        let a = abs(v)
        if a >= 1000 { return number(v.rounded()) }
        if a >= 100 { return number((v * 10).rounded() / 10) }
        return number(v)
    }

    // MARK: v4 新定的（App 沒有對應的畫面）

    /// 匯率、金價的數字（設定頁只顯示輸入框的原數字，App 沒有現成的寫法，v4 定）：
    /// 千元以上不寫小數「4,350」「16,313」、1 元以上兩位「32.15」、1 元以下四位「0.2001」
    static func rate(_ v: Double) -> String {
        let a = abs(v)
        if a >= 1000 { return number(v.rounded(), digits: 0) }
        if a >= 1 { return number(v, digits: 2) }
        return number(v, digits: 4)
    }

    /// 匯率、金價的漲跌差（跟 rate 同一個精度，看的是現價 scale 的大小）：金價 4,350 漲 37.6 寫「38」、美金 32.15 漲 0.021 寫「0.02」
    static func rateDelta(_ d: Double, scale: Double) -> String {
        let a = abs(scale)
        if a >= 1000 { return number(d.rounded(), digits: 0) }
        if a >= 1 { return number(d, digits: 2) }
        return number(d, digits: 4)
    }
}
