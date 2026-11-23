// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.640 mac1] 表單 → 寫入動作的規則（judge_mac §O5「名稱留空補分類名、金額 ≤ 0 不能存」）。
// 一支對一支照 scratchpad/radar/build/mac1/sim_mac1.py：parse_amount／new_expense_dict／new_income_dict。
// 新的一筆一律用 Expense／Income 自己的 init 再 JSONEncoder 編（跟 iPhone 存出來的長相一模一樣），再轉成字典交給 MacCloudWriter。
// 改一筆只交「改了哪幾欄」：date 寫 timeIntervalSinceReferenceDate（＝JSONEncoder 預設的日期編法）。
import Foundation

enum MacEntryRules {
    static let amountError = "請輸入大於 0 的金額"

    // MARK: - 金額（sim parse_amount）

    /// 只收數字和一個小數點、最多兩位小數、> 0；千分位逗號先拿掉。其餘（負號、科學記號、貨幣符號、全形數字）一律 nil
    static func parseAmount(_ text: String) -> Double? {
        let t = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t == "." { return nil }
        let allowed: Set<Character> = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "."]
        for c in t where !allowed.contains(c) { return nil }
        let parts = t.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count > 2 { return nil }
        if parts.count == 2 && parts[1].count > 2 { return nil }
        let intPart = parts[0].isEmpty ? "0" : String(parts[0])
        let fracPart = parts.count == 2 && !parts[1].isEmpty ? String(parts[1]) : "0"
        guard let v = Double(intPart + "." + fracPart), v.isFinite, v > 0 else { return nil }
        return v
    }

    // MARK: - 日期：DatePicker 只選日期，時間沿用

    /// day 的年月日＋timeSource 的時分秒（新的一筆＝現在的時間，跟 iPhone 一樣；改一筆＝原本的時間）
    static func combine(day: Date, timeOf timeSource: Date, calendar: Calendar = .current) -> Date {
        let d = calendar.dateComponents([.year, .month, .day], from: day)
        let t = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: timeSource)
        var c = DateComponents()
        c.year = d.year
        c.month = d.month
        c.day = d.day
        c.hour = t.hour
        c.minute = t.minute
        c.second = t.second
        c.nanosecond = t.nanosecond
        return calendar.date(from: c) ?? day
    }

    // MARK: - 新的一筆（sim new_expense_dict／new_income_dict）

    /// 回傳 (原字典, nil) 或 (nil, 原因)
    static func newExpense(title: String, amountText: String, day: Date, category: VariableCategory,
                           note: String, now: Date = Date()) -> (raw: [String: Any]?, error: String?) {
        guard MacEditPolicy.eightCategories.contains(category) else {
            return (nil, "分類只有 " + MacEditPolicy.eightCategoryNames.joined(separator: "、"))
        }
        guard let amount = parseAmount(amountText) else { return (nil, amountError) }
        var t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // 照抄 AddExpenseView.swift:4038-4041（25.639）：變動支出名稱留空時以分類名稱當預設
        if t.isEmpty {
            t = category.rawValue
        }
        let e = Expense(id: UUID(), title: t, amount: amount, date: combine(day: day, timeOf: now),
                        expenseType: .variable, variableCategory: category, note: note)
        guard let raw = dictionary(e) else { return (nil, "這筆編不出來，請再試一次") }
        return (raw, nil)
    }

    static func newIncome(title: String, amountText: String, day: Date, category: IncomeCategory,
                          note: String, now: Date = Date()) -> (raw: [String: Any]?, error: String?) {
        guard MacEditPolicy.incomeCategories.contains(category) else {
            let names = MacEditPolicy.incomeCategories.map { c in c.rawValue }
            return (nil, "分類只有 " + names.joined(separator: "、"))
        }
        guard let amount = parseAmount(amountText) else { return (nil, amountError) }
        var t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            t = category.rawValue
        }
        let i = Income(title: t, amount: amount, date: combine(day: day, timeOf: now), category: category,
                       period: .once, isFixedSalary: false, note: note)
        guard let raw = dictionary(i) else { return (nil, "這筆編不出來，請再試一次") }
        return (raw, nil)
    }

    /// 模型 → JSONEncoder（預設設定，跟 iPhone 的 save() 一樣）→ 字典
    static func dictionary<T: Encodable>(_ value: T) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any]
    }

    // MARK: - 改一筆：只交改了的欄位

    /// 表單上填的值（字串照原樣，金額是文字）
    struct Draft {
        var title: String
        var amountText: String
        var day: Date
        var expenseCategory: VariableCategory
        var incomeCategory: IncomeCategory
        var note: String
        /// 打開表單時金額那格的字；沒動過就不改金額（原本超過兩位小數的那幾筆，不動就不會被四捨五入）
        var originalAmountText: String? = nil
    }

    /// 表單金額那格的字：整數不寫小數點、最多兩位小數、不加千分位（「120」「12.5」）
    static func amountText(_ v: Double) -> String {
        guard v.isFinite else { return "" }
        if v == v.rounded(), Swift.abs(v) < 1e15 { return String(Int64(v)) }
        var s = String(format: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// 支出：跟原本那筆比，回傳要改的欄位（鎖住的欄位不收）；金額不對回傳 error
    static func expenseChanges(original e: Expense, draft: Draft,
                               verdict: MacEditVerdict) -> (changes: [String: Any?], error: String?) {
        var out: [String: Any?] = [:]
        let cat = verdict.canEdit(.category) ? draft.expenseCategory : (e.variableCategory ?? draft.expenseCategory)
        if verdict.canEdit(.title) {
            var t = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { t = cat.rawValue }                      // AddExpenseView.swift:4038-4041
            if t != e.title { out.updateValue(t, forKey: "title") }
        }
        if verdict.canEdit(.amount), draft.amountText != draft.originalAmountText {
            guard let amount = parseAmount(draft.amountText) else { return ([:], amountError) }
            if amount != e.amount { out.updateValue(amount, forKey: "amount") }
        }
        if verdict.canEdit(.date) {
            let newDate = sameDay(draft.day, e.date) ? e.date : combine(day: draft.day, timeOf: e.date)
            if newDate != e.date { out.updateValue(newDate.timeIntervalSinceReferenceDate, forKey: "date") }
        }
        if verdict.canEdit(.category), e.variableCategory != draft.expenseCategory {
            out.updateValue(draft.expenseCategory.rawValue, forKey: "variableCategory")
        }
        if verdict.canEdit(.note), draft.note != e.note {
            out.updateValue(draft.note, forKey: "note")
        }
        return (out, nil)
    }

    /// 收入：同上
    static func incomeChanges(original i: Income, draft: Draft,
                              verdict: MacEditVerdict) -> (changes: [String: Any?], error: String?) {
        var out: [String: Any?] = [:]
        let cat = verdict.canEdit(.category) ? draft.incomeCategory : i.category
        if verdict.canEdit(.title) {
            var t = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { t = cat.rawValue }
            if t != i.title { out.updateValue(t, forKey: "title") }
        }
        if verdict.canEdit(.amount), draft.amountText != draft.originalAmountText {
            guard let amount = parseAmount(draft.amountText) else { return ([:], amountError) }
            if amount != i.amount { out.updateValue(amount, forKey: "amount") }
        }
        if verdict.canEdit(.date) {
            let newDate = sameDay(draft.day, i.date) ? i.date : combine(day: draft.day, timeOf: i.date)
            if newDate != i.date { out.updateValue(newDate.timeIntervalSinceReferenceDate, forKey: "date") }
        }
        if verdict.canEdit(.category), i.category != draft.incomeCategory,
           MacEditPolicy.incomeCategories.contains(draft.incomeCategory) {
            out.updateValue(draft.incomeCategory.rawValue, forKey: "category")
        }
        if verdict.canEdit(.note), draft.note != i.note {
            out.updateValue(draft.note, forKey: "note")
        }
        return (out, nil)
    }

    static func sameDay(_ a: Date, _ b: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }

    // MARK: - 〔另存成新的一筆〕：那筆在另一台刪掉了（S11）

    /// base 那筆＋這次的改動，換一個新的 id（原字典其餘欄位原樣，不認得的也留著）
    static func detachedCopy(base: Data, id: String, changes: [String: Any?]) -> [String: Any]? {
        guard let arr = LedgerMerge.parseArray(base) else { return nil }
        let idx = LedgerMerge.index(arr)
        guard let pos = idx.pos[id], var d = arr[pos] as? [String: Any] else { return nil }
        for (k, v) in changes {
            if let v { d.updateValue(v, forKey: k) } else { d.removeValue(forKey: k) }
        }
        d.updateValue(UUID().uuidString, forKey: "id")
        return d
    }

    // MARK: - 顯示用的一句話（刪除確認、日誌、狀態列）

    /// 「午餐 NT$120（11/23）」
    static func label(raw: [String: Any]?, calendar: Calendar = .current) -> String {
        guard let raw else { return "這一筆" }
        let title = (raw["title"] as? String) ?? ""
        var parts: [String] = []
        if !title.isEmpty { parts.append(title) }
        if let n = raw["amount"] as? NSNumber {
            parts.append(money(n.doubleValue))
        }
        var text = parts.joined(separator: " ")
        if text.isEmpty { text = "這一筆" }
        if let t = raw["date"] as? NSNumber {
            let d = Date(timeIntervalSinceReferenceDate: t.doubleValue)
            let c = calendar.dateComponents([.month, .day], from: d)
            text += "（\(c.month ?? 0)/\(c.day ?? 0)）"
        }
        return text
    }

    /// 「NT$1,200」「NT$12.5」
    static func money(_ v: Double) -> String {
        "NT$" + WidgetMoneyFormat.number(v, digits: 2)
    }

    /// 衝突詢問、日誌用：把原字典的值寫成人看得懂的字
    static func display(field: String, value: Any?, calendar: Calendar = .current) -> String {
        guard let value else { return "（空白）" }
        if field == "amount", let n = value as? NSNumber { return money(n.doubleValue) }
        if field == "date", let n = value as? NSNumber {
            let d = Date(timeIntervalSinceReferenceDate: n.doubleValue)
            let c = calendar.dateComponents([.year, .month, .day], from: d)
            return "\(c.year ?? 0)/\(c.month ?? 0)/\(c.day ?? 0)"
        }
        if let s = value as? String { return s.isEmpty ? "（空白）" : s }
        if let n = value as? NSNumber { return n.stringValue }
        return "（看不懂的值）"
    }

    /// 欄位名 → 中文
    static func fieldName(_ field: String) -> String {
        switch field {
        case "title": return "名稱"
        case "amount": return "金額"
        case "date": return "日期"
        case "variableCategory", "category": return "分類"
        case "note": return "備註"
        default: return field
        }
    }
}
