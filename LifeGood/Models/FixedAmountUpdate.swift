import Foundation

// MARK: - 固定支出〔更新金額〕要打哪個幣別（v25.611 learn C4）
//
// 只屬於「LifeGood」target。規格：scratchpad/radar/judge_learn.md §C4；分工：scratchpad/radar/build/learn/brief.md。
//
// 固定支出的 amount 怎麼存（AddExpenseView 存檔：amount = isSavingsInsurance ? rawAmount : rawAmount * currencyMultiplier）：
//   • 台幣：amount 是台幣
//   • 外幣（不是儲蓄險）：amount 是**換好的台幣**（原幣 × 設定裡的匯率），currencyCode 是原幣別；
//     畫面（FixedExpenseCard.formattedAmount）用 amount ÷ 匯率 顯示成「USD 99」
//   • 儲蓄險：amount 本來就是原幣
// 以前〔更新金額〕框寫「目前 3,246」（台幣）、打的數字直接當台幣存：打 99 變成 NT$99（畫面變成約 USD 3）。
// 這裡決定框要打哪個幣別、怎麼換回 amount；FixedExpenseView 只叫這裡（sim_learn.py 一支一支對照）。
// 匯率的找法跟 AddExpenseView.currencyMultiplier、FixedExpenseCard.formattedAmount 一模一樣
// （設定裡寫法一樣的第一個、> 0）；沒有匯率不猜（不當 1），請你打台幣。

/// 〔更新金額〕框打的是哪個幣別
enum FixedAmountInputUnit: Equatable {
    /// 台幣固定支出：打台幣
    case twd
    /// 外幣、設定裡有匯率：打原幣，存 原幣 × 匯率（台幣）
    case foreign(code: String, rate: Double)
    /// 外幣、設定裡沒有那個幣別的匯率：打台幣（不猜匯率）
    case foreignNoRate(code: String)
    /// 儲蓄險：amount 本來就是原幣（code 是台幣時寫「NT$」）
    case savings(code: String)
}

enum FixedAmountUpdate {
    /// 原本的說明字（一字不改）
    static let baseMessage = "記錄新一期的金額（例：今年續保的乙式險保費）。舊金額會保留成走勢曲線的歷史點。"

    /// 儲蓄險（同 FixedExpenseCard.formattedAmount、ExpenseStore.displayAmountText 的判斷）
    static func isSavings(_ e: Expense) -> Bool {
        e.fixedCategory == .insurance && e.insuranceSubCategory == .savings
    }

    /// 設定裡那個幣別的匯率：寫法一樣的第一個，> 0 才算（同 AddExpenseView.currencyMultiplier）。沒有＝nil
    static func rate(for code: String, rates: [CurrencyRate]) -> Double? {
        guard let r = rates.first(where: { $0.code == code }), r.rate > 0 else { return nil }
        return r.rate
    }

    /// 這一筆的框要打哪個幣別
    static func unit(for e: Expense, rates: [CurrencyRate]) -> FixedAmountInputUnit {
        let code = e.currencyCode
        if isSavings(e) { return .savings(code: FinanceRates.isNTD(code) ? "NT$" : code) }
        if FinanceRates.isNTD(code) { return .twd }
        if let r = rate(for: code, rates: rates) { return .foreign(code: code, rate: r) }
        return .foreignNoRate(code: code)
    }

    /// 框上寫的幣別
    static func unitLabel(_ unit: FixedAmountInputUnit) -> String {
        switch unit {
        case .twd, .foreignNoRate:
            return "NT$"
        case .foreign(let code, _):
            return code
        case .savings(let code):
            return code
        }
    }

    /// 框裡「目前」那個數字（用框上的幣別）：外幣有匯率＝amount ÷ 匯率（同畫面上的「USD 99」）；其他＝amount
    static func shownCurrent(_ e: Expense, unit: FixedAmountInputUnit) -> Double {
        if case .foreign(_, let r) = unit { return e.amount / r }
        return e.amount
    }

    /// 打的數字 → 要存的 amount：外幣有匯率＝原幣 × 匯率（同 AddExpenseView 存檔 rawAmount * currencyMultiplier，不四捨五入）；其他照打的
    static func storedAmount(typed: Double, unit: FixedAmountInputUnit) -> Double {
        if case .foreign(_, let r) = unit { return typed * r }
        return typed
    }

    /// 打的字 → 數字（去頭尾空白、拿掉千分位逗號；要是 > 0 的有限數字）。看不懂＝nil（〔更新〕按不下去）
    static func parseTyped(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
        guard let v = Double(t), v.isFinite, v > 0 else { return nil }
        return v
    }

    /// 框的提示字：「新一期金額（USD，目前 99）」「新一期金額（NT$，目前 3,246）」。
    /// 取整數，跟卡片上的「USD 99」同一個數（formattedAmount 的 decimalFmt 也是 0 位小數）
    static func placeholder(_ e: Expense, unit: FixedAmountInputUnit) -> String {
        let label = unitLabel(unit)
        let current = numberText(shownCurrent(e, unit: unit), maxFraction: 0)
        return "新一期金額（\(label)，目前 \(current)）"
    }

    /// 多的那一句：外幣有匯率「照目前匯率 1 USD = 32.8 換成台幣存。」、沒有匯率「設定裡沒有 USD 的匯率，請打台幣。」；其他沒有
    static func note(_ unit: FixedAmountInputUnit) -> String? {
        switch unit {
        case .foreign(let code, let r):
            return "照目前匯率 1 \(code) = \(numberText(r, maxFraction: 4)) 換成台幣存。"
        case .foreignNoRate(let code):
            return "設定裡沒有 \(code) 的匯率，請打台幣。"
        case .twd, .savings:
            return nil
        }
    }

    /// 對話框的說明：原本那句＋（有的話）多的那一句
    static func message(_ unit: FixedAmountInputUnit) -> String {
        guard let n = note(unit) else { return baseMessage }
        return baseMessage + "\n" + n
    }

    // MARK: 走勢圖、金額紀錄的幣別（不改存法，只改標示）

    /// 歷史點的幣別：外幣儲蓄險是原幣（AddSavingsInsuranceView、〔更新金額〕都照原幣存），其他一律台幣（外幣固定支出存的是換好的台幣）
    static func historyLabel(_ e: Expense) -> String {
        if isSavings(e), !FinanceRates.isNTD(e.currencyCode) { return e.currencyCode }
        return "NT$"
    }

    /// 「NT$3,246」「USD 5,000」（整數；台幣照走勢圖原本的寫法不空格）
    static func historyAmountText(_ v: Double, label: String) -> String {
        let n = numberText(v, maxFraction: 0)
        return label == "NT$" ? "NT$" + n : label + " " + n
    }

    /// 金額紀錄編輯頁多的一句：外幣（不是儲蓄險）的固定支出，說清楚這裡是台幣；其他沒有
    static func historyNote(_ e: Expense) -> String? {
        guard !isSavings(e), !FinanceRates.isNTD(e.currencyCode) else { return nil }
        return "這筆是 \(e.currencyCode) 的固定支出，金額紀錄存的是每一期換成台幣的金額（NT$）。"
    }

    // MARK: 數字字

    /// 四捨五入（.plain＝ROUND_HALF_UP）到 maxFraction 位、去掉小數尾巴的 0、整數部分每三位一個逗號。
    /// 不用 NumberFormatter（它預設是銀行家捨入，sim 對不上）
    static func numberText(_ v: Double, maxFraction: Int) -> String {
        guard v.isFinite else { return "0" }
        var d = Decimal(v)
        var r = Decimal()
        NSDecimalRound(&r, &d, maxFraction, .plain)
        let raw = NSDecimalNumber(decimal: r).stringValue
        let negative = raw.hasPrefix("-")
        let body = negative ? String(raw.dropFirst()) : raw
        let parts = body.components(separatedBy: ".")
        let intPart = parts[0]
        let n = intPart.count
        var grouped = ""
        for (i, ch) in intPart.enumerated() {
            if i > 0 && (n - i) % 3 == 0 { grouped.append(",") }
            grouped.append(ch)
        }
        var out = (negative ? "-" : "") + grouped
        if parts.count > 1 {
            // 自己去掉小數尾巴的 0（不靠 NSDecimalRound／stringValue 會不會壓縮：32.8000 → 32.8）
            var frac = parts[1]
            while frac.hasSuffix("0") { frac.removeLast() }
            if !frac.isEmpty { out += "." + frac }
        }
        return out
    }
}
