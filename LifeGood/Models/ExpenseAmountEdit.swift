import Foundation

// MARK: - 記帳編輯頁（AddExpenseView）的金額欄：帶回來怎麼寫、沒改要不要重算（v25.614 menus C2）
//
// 只屬於「LifeGood」target。規格：scratchpad/radar/judge_menus.md §C2；分工：scratchpad/radar/build/menus/brief.md。
//
// 以前（25.613 以前）編輯一筆支出，金額欄一律 String(format: "%.0f", …)：
//   • 外幣固定支出 USD 19.99 顯示「20」；Apple Pay 外幣換算的台幣 401.25、〔更新金額〕的 3,247.2 顯示「401」「3247」
//   • 按〔儲存〕就照欄位上的字重算：小數不見；外幣還照「現在」的匯率重算——匯率變了，什麼都沒改按儲存，台幣金額也跟著變
// 現在：
//   1. 金額欄最多 2 位小數、去掉尾巴的 0（19.99、401.25、3247.2、65）——fieldText
//   2. 沒改金額也沒改幣別（只改分類、備註、同行人員…）就存：amount 保留原本存的值（不重算、不捨小數）——amountToSave
//      改了金額或幣別（或股票連動的金額是股數 × 價格算的）才照以前的規則重算（儲蓄險原幣、其他 原幣 × 設定裡的匯率）
// AddExpenseView 只叫這裡（loadEditing 帶回金額欄、saveExpense 的 candidateAmount／amount 兩行）；sim_menus.py 一支一支對照。

enum ExpenseAmountEdit {
    /// 打開編輯那一刻的金額欄、幣別（loadEditing 最後記一份）
    struct Loaded: Equatable {
        /// 金額欄的字（fieldText 寫的）
        let text: String
        /// 金額欄左邊選的幣別（selectedCurrencyCode）
        let code: String
        /// 儲蓄險的幣別（insCurrencyCode）
        let insCode: String
        /// 那時候表單是不是儲蓄險（儲蓄險的 amount 是原幣、其他是台幣，兩種不能互相沿用）
        let isSavings: Bool
        /// 原本存的 amount（一個字都不動的那個數）
        let amount: Double
    }

    /// 金額欄的字：最多 2 位小數、去掉尾巴的 0（19.99 → "19.99"、401.25 → "401.25"、3247.2 → "3247.2"、65 → "65"）。
    /// 四捨五入到分（.toNearestOrAwayFromZero：剛好一半就進位；外幣除匯率的 19.990000000000002 寫 19.99）。
    /// 不帶千分位、小數點固定是「.」（輸入欄要能原樣讀回 Double）。不是有限數字、或大到 1e13 以上照以前 %.0f
    static func fieldText(_ value: Double) -> String {
        guard value.isFinite, Swift.abs(value) < 1e13 else { return String(format: "%.0f", value) }
        let cents: Double = (Swift.abs(value) * 100).rounded(.toNearestOrAwayFromZero)
        let c = Int64(cents)
        let whole: Int64 = c / 100
        let frac = Int(c % 100)
        let sign: String = (value < 0 && c != 0) ? "-" : ""
        if frac == 0 { return sign + String(whole) }
        if frac % 10 == 0 { return sign + String(whole) + "." + String(frac / 10) }
        let two: String = frac < 10 ? "0" + String(frac) : String(frac)
        return sign + String(whole) + "." + two
    }

    /// 金額欄的字 → 數字（只拿來比「有沒有改」）：去頭尾空白、拿掉千分位逗號；看不懂＝nil
    static func number(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
        guard let v = Double(t), v.isFinite else { return nil }
        return v
    }

    /// 沒改金額也沒改幣別：幣別、儲蓄險幣別、是不是儲蓄險都跟打開時一樣，金額欄的數值也一樣（"19.99" 跟 " 19.990 " 算一樣）
    static func isUnchanged(_ loaded: Loaded, text: String, code: String, insCode: String, isSavings: Bool) -> Bool {
        guard loaded.code == code, loaded.insCode == insCode, loaded.isSavings == isSavings else { return false }
        guard let before = number(loaded.text), let now = number(text) else { return false }
        return before == now
    }

    /// 要存的 amount。converted：照以前的規則算好的（儲蓄險＝欄位數字；其他＝欄位數字 × 匯率）。
    /// fromField：金額是從金額欄來的（false＝股票連動用股數 × 價格算的，照以前）。
    /// loaded 是 nil（新增）、或改了金額／幣別 → converted；沒改 → 原本存的 loaded.amount
    static func amountToSave(converted: Double, loaded: Loaded?, text: String, fromField: Bool,
                             code: String, insCode: String, isSavings: Bool) -> Double {
        guard fromField, let l = loaded else { return converted }
        guard isUnchanged(l, text: text, code: code, insCode: insCode, isSavings: isSavings) else { return converted }
        return l.amount
    }
}
