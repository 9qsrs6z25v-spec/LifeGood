// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.640 mac1] 表單 → 寫入動作的規則（judge_mac §O5「名稱留空補分類名、金額 ≤ 0 不能存」）。
// 一支對一支照 scratchpad/radar/build/mac1/sim_mac1.py：parse_amount／new_expense_dict／new_income_dict。
// 新的一筆一律用 Expense／Income 自己的 init 再 JSONEncoder 編（跟 iPhone 存出來的長相一模一樣），再轉成字典交給 MacCloudWriter。
// 改一筆只交「改了哪幾欄」：date 寫 timeIntervalSinceReferenceDate（＝JSONEncoder 預設的日期編法）。
// [v25.641 mac2 G1] 收入照 judge_mac §P5（sim_mac2.py new_income2／income_changes2／display／field_name；sim2 編號 entry#）：
// 新記可選週期／固定薪水／結束日；改週期收入能在獎金、禮金、確幸之間換分類、固定薪水設／改／拿掉結束日（endDate、endReason 兩欄一起寫）。
// [v25.642 mac3 G1] 支出照 judge_mac §Q5 表單規則（sim_mac3.py expense_changes3／new_expense3／duplicate3；sim3 編號 entry3#）：
// 名稱、備註照 iPhone 用 .whitespaces 去頭尾（換行不去）；⌘D 複製照抄 VariableExpenseView.swift:560-591 的參數表。收入不動。
// [v25.644 mac4 G1] 固定支出照 judge_mac §R5 表單規則（sim_mac4.py fixed_changes／new_fixed／end_changed／snapshot_dicts；
// sim4 編號 entry4#）：已開始的改金額只給〔從今天起〕（MacFixedCal.historyFrom 逐筆轉字典）、第一期還沒到才改扣款日週期、
// 停止日不早於最近已扣過那期、停在以前的不准改晚或拿掉、名稱必填（不補分類名）。變動支出、收入不動。
import Foundation

/// 表單結束日那一區（開關、哪一天、原因）
struct MacIncomeEndDraft: Equatable {
    var enabled = false
    var day = Date()
    var reason: SalaryEndReason = .jobChange
}

/// [v25.644 mac4] 固定支出停止那一區（開關、最後一次扣款日、原因）
struct MacFixedEndDraft: Equatable {
    var enabled = false
    var day = Date()
    var reason: FixedEndReason = .cancelled
}

/// [v25.644 mac4] 詢問框選了〔從今天起〕：cutoff、firstID、newID 在按下那一刻定（存失敗重按、跳衝突再按都用同一份）
enum MacAmountPick: Equatable {
    case fromToday(cutoff: Date, firstID: UUID, newID: UUID)
}

/// [v25.644 mac4] 已開始那筆改金額：存之前先問（字照 iPhone，只拿掉〔全部都改〕）
struct MacAmountAsk: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

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

    /// 回傳 (原字典, nil) 或 (nil, 原因)。id、now 由表單開著的期間固定（存失敗再按一次＝同一筆，不會多一筆）
    static func newExpense(title: String, amountText: String, day: Date, category: VariableCategory,
                           note: String, id: UUID = UUID(), now: Date = Date()) -> (raw: [String: Any]?, error: String?) {
        guard MacEditPolicy.eightCategories.contains(category) else {
            return (nil, "分類只有 " + MacEditPolicy.eightCategoryNames.joined(separator: "、"))
        }
        guard let amount = parseAmount(amountText) else { return (nil, amountError) }
        // sim3: entry3#2 名稱、備註照 iPhone 只去頭尾空白（AddExpenseView.swift:4028、:4271；換行不去）
        var t = title.trimmingCharacters(in: .whitespaces)
        // 照抄 AddExpenseView.swift:4038-4041（25.639）：變動支出名稱留空時以分類名稱當預設
        if t.isEmpty {
            t = category.rawValue
        }
        let e = Expense(id: id, title: t, amount: amount, date: combine(day: day, timeOf: now),
                        expenseType: .variable, variableCategory: category, note: note.trimmingCharacters(in: .whitespaces))
        guard let raw = dictionary(e) else { return (nil, "這筆編不出來，請再試一次") }
        return (raw, nil)
    }

    // 照抄 VariableExpenseView.swift:560-591（48c51a2）duplicateExpense 的 Expense(...) 參數表 — sim3: entry3#3
    // （UUID()→id、Date()→now、title→e.title、expense.→e.；evKwh、fuelLiters 那兩行用不到：有殘留欄位的那筆不給複製）
    /// ⌘D 複製成新的一筆：呼叫前先過 MacEditPolicy.expenseDuplicateReason；id、now 在確認框打開那一刻定下來
    static func duplicate(_ e: Expense, id: UUID, now: Date) -> [String: Any]? {
        let copy = Expense(
            id: id,
            title: e.title,
            amount: e.amount,
            date: now,
            expenseType: e.expenseType,
            variableCategory: e.variableCategory,
            fixedCategory: e.fixedCategory,
            recurrence: e.recurrence,
            insuranceSubCategory: e.insuranceSubCategory,
            loanSubCategory: e.loanSubCategory,
            linkedInsuranceId: e.linkedInsuranceId,
            linkedStockId: e.linkedStockId,
            linkedRealEstateId: e.linkedRealEstateId,
            linkedVehicleId: e.linkedVehicleId,
            vehicleExpenseCategory: e.vehicleExpenseCategory,
            realEstateExpenseCategory: e.realEstateExpenseCategory,
            taxSavingSubCategory: e.taxSavingSubCategory,
            socialSubCategory: e.socialSubCategory,
            socialRecipient: e.socialRecipient,
            taxDeductibleOverride: e.taxDeductibleOverride,
            note: e.note,
            currencyCode: e.currencyCode,
            diningMember: e.diningMember,
            linkedBankMilestoneId: e.linkedBankMilestoneId,
            linkedBankCurrency: e.linkedBankCurrency,
            linkedCreditCardMilestoneId: e.linkedCreditCardMilestoneId,
            placeName: e.placeName,
            placeAddress: e.placeAddress,
            placeLatitude: e.placeLatitude,
            placeLongitude: e.placeLongitude
        )
        return dictionary(copy)
    }

    /// 收入：薪水＝固定薪水開著就每月、關著就單次（不給每年）；獎金、禮金、確幸照選的週期、isFixedSalary＝false；
    /// 結束日只在薪水＋固定薪水時收。驗證順序：分類 → 金額 → 薪水選每年 → 結束日早於日期
    static func newIncome(title: String, amountText: String, day: Date, category: IncomeCategory, note: String,
                          period: IncomePeriod = .once, isFixedSalary: Bool = false,
                          end: (day: Date, reason: SalaryEndReason)? = nil,
                          id: UUID = UUID(), now: Date = Date()) -> (raw: [String: Any]?, error: String?) {
        guard MacEditPolicy.incomeCategories.contains(category) else {
            let names = MacEditPolicy.incomeCategories.map { c in c.rawValue }
            return (nil, "分類只有 " + names.joined(separator: "、"))
        }
        guard let amount = parseAmount(amountText) else { return (nil, amountError) }
        let finalPeriod: IncomePeriod
        let fixed: Bool
        if category == .salary {
            // sim2: entry#4 薪水：固定＝每月，不固定＝單次；選了每年擋
            if period == .yearly { return (nil, MacEditPolicy.errorSalaryYearly) }
            finalPeriod = isFixedSalary ? .monthly : .once
            fixed = isFixedSalary
        } else {
            // sim2: entry#5 獎金、禮金、確幸：照選的週期，不是固定薪水
            finalPeriod = period
            fixed = false
        }
        var t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            t = category.rawValue
        }
        let date = combine(day: day, timeOf: now)
        var endDate: Date? = nil
        var endReason: SalaryEndReason? = nil
        if let end, category == .salary, fixed {
            // sim2: entry#6 結束日時間＝現在的時間（跟日期同一套）；結束那天不能早於開始那天
            let e = combine(day: end.day, timeOf: now)
            let calendar = Calendar.current
            if calendar.startOfDay(for: e) < calendar.startOfDay(for: date) { return (nil, MacEditPolicy.errorEndBefore) }
            endDate = e
            endReason = end.reason
        }
        // endDate、endReason 是 nil 時 JSONEncoder 不寫那兩個鍵（跟 iPhone 新增一樣）；amountHistory、linkedBank*、linkedStockId 不出現
        let i = Income(id: id, title: t, amount: amount, date: date, category: category,
                       period: finalPeriod, isFixedSalary: fixed, note: note, endDate: endDate, endReason: endReason)
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
        /// [v25.641 mac2] 收入：週期（新記非薪水用）、固定薪水（新記薪水用，預設開）、結束日那一區與打開表單時的值
        var period: IncomePeriod = .once
        var isFixedSalary: Bool = true
        var end = MacIncomeEndDraft()
        var originalEnd = MacIncomeEndDraft()
        /// [v25.644 mac4] 固定支出：新記切〔固定〕／改固定支出那筆；分類（預設房租）、週期（預設每月）、停止那一區與打開表單時的值
        var fixedMode: Bool = false
        var fixedCategory: FixedCategory = .rent
        var recurrence: Recurrence = .monthly
        var fixedEnd = MacFixedEndDraft()
        var originalFixedEnd = MacFixedEndDraft()
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
        // sim3: entry3#1 名稱、備註照 iPhone 只去頭尾空白（換行不去）；其餘照 Mac 1
        var out: [String: Any?] = [:]
        let cat = verdict.canEdit(.category) ? draft.expenseCategory : (e.variableCategory ?? draft.expenseCategory)
        if verdict.canEdit(.title) {
            var t = draft.title.trimmingCharacters(in: .whitespaces)
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
        if verdict.canEdit(.note) {
            let n = draft.note.trimmingCharacters(in: .whitespaces)
            if n != e.note { out.updateValue(n, forKey: "note") }
        }
        return (out, nil)
    }

    /// 收入：同上（sim2 income_changes2）。週期收入的金額、開始日被 verdict 擋，不會進 changes
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
        if i.period == .once {
            if verdict.canEdit(.category), i.category != draft.incomeCategory,
               MacEditPolicy.incomeCategories.contains(draft.incomeCategory) {
                out.updateValue(draft.incomeCategory.rawValue, forKey: "category")
            }
        } else if verdict.canEdit(.category), draft.incomeCategory != i.category,
                  MacEditPolicy.recurringIncomeCategories.contains(i.category),
                  MacEditPolicy.recurringIncomeCategories.contains(draft.incomeCategory) {
            // sim2: entry#1 週期：新舊都在獎金、禮金、確幸才換
            out.updateValue(draft.incomeCategory.rawValue, forKey: "category")
        }
        if verdict.canEdit(.endDate), endChanged(draft.end, draft.originalEnd) {
            let end = draft.end
            if end.enabled {
                // sim2: entry#2 開著：不能早於開始那天；同一天保留原值，否則那天＋開始日的時間；兩欄一起寫
                if Calendar.current.startOfDay(for: end.day) < Calendar.current.startOfDay(for: i.date) {
                    return ([:], MacEditPolicy.errorEndBefore)
                }
                let newEnd: Date
                if let old = i.endDate, sameDay(end.day, old) {
                    newEnd = old
                } else {
                    newEnd = combine(day: end.day, timeOf: i.date)
                }
                out.updateValue(newEnd.timeIntervalSinceReferenceDate, forKey: "endDate")
                out.updateValue(end.reason.rawValue, forKey: "endReason")
            } else if i.endDate != nil || i.endReason != nil {
                // sim2: entry#3 關掉：兩欄都拿掉（鍵留在 changes、值 nil；MacCloudWriter.apply 會 removeValue）
                out.updateValue(nil, forKey: "endDate")
                out.updateValue(nil, forKey: "endReason")
            }
        }
        if verdict.canEdit(.note), draft.note != i.note {
            out.updateValue(draft.note, forKey: "note")
        }
        return (out, nil)
    }

    // MARK: - [v25.644 mac4] 固定支出（sim4 fixed_changes／new_fixed）

    // 照 AddExpenseView.swift:3985-4005（amountChangeAsk 問不問的條件與字）、:4028（名稱 .whitespaces）、:4052-4060（名稱必填）、
    // :4271（備註 .whitespaces）、:4287-4288（停止兩欄一起寫）（f2c8892）；只給〔從今天起〕
    /// 固定支出：跟打開表單那份比，回傳要改的欄位（鎖住的欄位不收）。已開始那筆改金額而 pick 是 nil → 回 ask（不存，先問）；
    /// 有 pick → amount＋amountHistory 一起寫（〔從今天起〕：今天以前每一期照舊）。順序照 sim：名稱 → 備註 → 金額 → 扣款日 → 週期 → 分類 → 停止 → 問
    static func fixedChanges(original e: Expense, draft: Draft, verdict: MacEditVerdict, now: Date,
                             pick: MacAmountPick?) -> (changes: [String: Any?], error: String?, ask: MacAmountAsk?) {
        // sim4: entry4#1
        var out: [String: Any?] = [:]
        // 名稱：.whitespaces 去頭尾；固定支出名稱空的擋（不補分類名，AddExpenseView.swift:4052-4060）
        let title = draft.title.trimmingCharacters(in: .whitespaces)
        if verdict.canEdit(.title) {
            if title.isEmpty { return ([:], MacEditPolicy.errorFixedTitleEmpty, nil) }
            if title != e.title { out.updateValue(title, forKey: "title") }
        }
        if verdict.canEdit(.note) {
            let n = draft.note.trimmingCharacters(in: .whitespaces)
            if n != e.note { out.updateValue(n, forKey: "note") }
        }
        // 金額：欄位動過才看；差 ≤ 0.004 當沒改；沒開始只寫 amount；已開始要〔從今天起〕
        var askAmount: Double?
        if verdict.canEdit(.amount), draft.amountText != draft.originalAmountText {
            guard let amount = parseAmount(draft.amountText) else { return ([:], amountError, nil) }
            if Swift.abs(amount - e.amount) > 0.004 {
                if !MacFixedCal.isStarted(e, now: now) {
                    out.updateValue(amount, forKey: "amount")
                } else if case .fromToday(let cutoff, let firstID, let newID)? = pick {
                    // F3：[AmountSnapshot] 整份 cast 成字典會失敗 → 逐筆轉；筆數對不上就不存
                    let snaps = MacFixedCal.historyFrom(cutoff, history: e.amountHistory, current: e.amount, firstDate: e.date,
                                                        newAmount: amount, firstID: firstID, newID: newID)
                    let dicts = snaps.compactMap { MacEntryRules.dictionary($0) }
                    if dicts.count != snaps.count { return ([:], MacEditPolicy.reasonValueBad, nil) }
                    out.updateValue(amount, forKey: "amount")
                    out.updateValue(dicts, forKey: "amountHistory")
                } else {
                    askAmount = amount
                }
            }
        }
        // 扣款日：同一天不寫；換天＝那天＋原本的時間；不准改到今天以前
        var newStart = e.date
        if verdict.canEdit(.date), !sameDay(draft.day, e.date) {
            let d = combine(day: draft.day, timeOf: e.date)
            if MacFixedCal.day(d) < MacFixedCal.day(now) { return ([:], MacEditPolicy.errorFixedDatePast, nil) }
            out.updateValue(d.timeIntervalSinceReferenceDate, forKey: "date")
            newStart = d
        }
        if verdict.canEdit(.recurrence), draft.recurrence != e.recurrence {
            out.updateValue(draft.recurrence.rawValue, forKey: "recurrence")
        }
        if verdict.canEdit(.category), draft.fixedCategory != e.fixedCategory {
            guard MacEditPolicy.plainFixedCategories.contains(draft.fixedCategory) else {
                return ([:], MacEditPolicy.reasonFieldUnknown, nil)
            }
            out.updateValue(draft.fixedCategory.rawValue, forKey: "fixedCategory")
        }
        // 停止：兩欄一起寫或一起拿掉
        if verdict.canEdit(.endDate), fixedEndChanged(draft.fixedEnd, draft.originalFixedEnd) {
            if let error = fixedEndChanges(e, end: draft.fixedEnd, start: newStart, now: now, into: &out) {
                return ([:], error, nil)
            }
        }
        if let askAmount {
            let name = verdict.canEdit(.title) ? title : e.title
            let hasPayment = e.linkedBankMilestoneId != nil || e.linkedCreditCardMilestoneId != nil
            let ask = MacAmountAsk(title: MacFixedCal.amountAskTitle(name: name, old: e.amount, new: askAmount),
                                   message: MacFixedCal.amountAskMessage(hasPayment: hasPayment,
                                                                        iPhoneLine: MacEditPolicy.fixedAllIPhone))
            return ([:], nil, ask)
        }
        return (out, nil, nil)
    }

    /// 原本就停在今天以前（改晚、拿掉都會多出以前的期數）
    static func fixedEndClosedPast(_ e: Expense, now: Date) -> Bool {
        guard let old = e.endDate else { return false }
        return MacFixedCal.day(old) < MacFixedCal.day(now)
    }

    // 照 AddExpenseView.swift:2720-2721（打開停止開關的預設原因）（f2c8892）；日子改成 max(今天, 第一期, 最近已扣過那期)（§R5）
    /// 停止區預設（〔停止扣款…〕開表單、打開開關）：日子＝max(今天, 第一期, 最近已扣過那期)、時分照 e.date；
    /// 原因＝這個分類最可能的那個（共用 FixedEndReason.suggested(for:)）— sim4: entry4#3
    static func fixedStopDefault(_ e: Expense, now: Date) -> MacFixedEndDraft {
        // sim4: entry4#3
        let day = combine(day: MacFixedCal.stopLowerBound(e, now: now), timeOf: e.date)
        let reason = FixedEndReason.suggested(for: e.fixedCategory).first ?? .cancelled
        return MacFixedEndDraft(enabled: true, day: day, reason: reason)
    }

    /// 停止那一區寫進 out；回傳錯誤字（nil＝照寫）。start＝這次存完的第一期（扣款日改了用新的）
    private static func fixedEndChanges(_ e: Expense, end: MacFixedEndDraft, start: Date, now: Date,
                                        into out: inout [String: Any?]) -> String? {
        let closedPast = fixedEndClosedPast(e, now: now)
        guard end.enabled else {
            // 關掉：原本有停止日才拿掉；原本停在以前 → 會多出以前的期數
            guard e.endDate != nil else { return nil }
            if closedPast { return MacEditPolicy.reasonFixedEndReopen }
            out.updateValue(nil, forKey: "endDate")
            out.updateValue(nil, forKey: "endReason")
            return nil
        }
        let d = MacFixedCal.day(end.day)
        if d < MacFixedCal.day(start) { return MacEditPolicy.errorEndBefore }
        if let last = MacFixedCal.lastPastDue(e, now: now), d < last { return MacEditPolicy.reasonFixedEndCut }
        if closedPast, let old = e.endDate, d > MacFixedCal.day(old) { return MacEditPolicy.reasonFixedEndReopen }
        let newEnd: Date
        if let old = e.endDate, sameDay(end.day, old) {
            newEnd = old
        } else {
            newEnd = combine(day: end.day, timeOf: e.date)
        }
        out.updateValue(newEnd.timeIntervalSinceReferenceDate, forKey: "endDate")
        out.updateValue(end.reason.rawValue, forKey: "endReason")
        return nil
    }

    /// 停止那一區有沒有動：開關不同＝改；都關＝沒改；都開＝不同天或原因不同（sim4 end_changed）
    static func fixedEndChanged(_ a: MacFixedEndDraft, _ b: MacFixedEndDraft, calendar: Calendar = .current) -> Bool {
        if a.enabled != b.enabled { return true }
        if !a.enabled { return false }
        return !calendar.isDate(a.day, inSameDayAs: b.day) || a.reason != b.reason
    }

    /// 新記一筆固定支出：分類六類 → 金額 → 名稱必填 → 停止不早於第一期；Expense(...) → JSONEncoder → 字典。
    /// 台幣、付款不指定、amountHistory＝[]（照 iPhone 新增）；id、now 由表單開著的期間固定
    static func newFixed(title: String, amountText: String, day: Date, category: FixedCategory, recurrence: Recurrence,
                         note: String, end: (day: Date, reason: FixedEndReason)?, id: UUID = UUID(), now: Date = Date()) -> (raw: [String: Any]?, error: String?) {
        // sim4: entry4#2
        guard MacEditPolicy.plainFixedCategories.contains(category) else { return (nil, MacEditPolicy.reasonFieldUnknown) }
        guard let amount = parseAmount(amountText) else { return (nil, amountError) }
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return (nil, MacEditPolicy.errorFixedTitleEmpty) }
        let date = combine(day: day, timeOf: now)
        var endDate: Date? = nil
        var endReason: FixedEndReason? = nil
        if let end {
            let calendar = Calendar.current
            if calendar.startOfDay(for: end.day) < calendar.startOfDay(for: date) { return (nil, MacEditPolicy.errorEndBefore) }
            endDate = combine(day: end.day, timeOf: date)
            endReason = end.reason
        }
        let e = Expense(id: id, title: t, amount: amount, date: date, expenseType: .fixed, fixedCategory: category,
                        recurrence: recurrence, note: note.trimmingCharacters(in: .whitespaces), currencyCode: "NT$",
                        endDate: endDate, endReason: endReason)
        guard let raw = dictionary(e) else { return (nil, "這筆編不出來，請再試一次") }
        return (raw, nil)
    }

    /// 結束那一區有沒有動：開關不同＝改；都關＝沒改；都開＝不同天或原因不同
    static func endChanged(_ a: MacIncomeEndDraft, _ b: MacIncomeEndDraft, calendar: Calendar = .current) -> Bool {
        if a.enabled != b.enabled { return true }
        if !a.enabled { return false }
        return !calendar.isDate(a.day, inSameDayAs: b.day) || a.reason != b.reason
    }

    static func sameDay(_ a: Date, _ b: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }

    // MARK: - 〔另存成新的一筆〕：那筆在另一台刪掉了（S11）

    private static let detachedLinkKeys = [
        "linkedBankMilestoneId", "linkedBankCurrency", "linkedCreditCardMilestoneId",
        "linkedStockId", "linkedRealEstateId", "linkedVehicleId", "linkedInsuranceId",
        "linkedTripPlanId", "linkedTripStopId",
    ]

    /// base 那筆＋這次的改動，換一個新的 id（原字典其餘欄位原樣，不認得的也留著）
    static func detachedCopy(base: Data, id: String, changes: [String: Any?]) -> [String: Any]? {
        guard let arr = LedgerMerge.parseArray(base) else { return nil }
        let idx = LedgerMerge.index(arr)
        guard let pos = idx.pos[id], var d = arr[pos] as? [String: Any] else { return nil }
        // 連著銀行、卡、股票、房子、車子、保險、旅行或有照片的，換新 id 會讓那邊的連結對不上 → 不給另存，請在 iPhone 處理
        if detachedLinkKeys.contains(where: { d[$0] != nil && !(d[$0] is NSNull) }) { return nil }
        if let photos = d["photoFileNames"] as? [Any], !photos.isEmpty { return nil }
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

    /// 衝突詢問、日誌用：把原字典的值寫成人看得懂的字（sim2 display）
    static func display(field: String, value: Any?, calendar: Calendar = .current) -> String {
        guard let value, !(value is NSNull) else { return "（空白）" }
        if field == "amount", let n = value as? NSNumber { return money(n.doubleValue) }
        if field == "date" || field == "endDate", let n = value as? NSNumber {
            let d = Date(timeIntervalSinceReferenceDate: n.doubleValue)
            let c = calendar.dateComponents([.year, .month, .day], from: d)
            return "\(c.year ?? 0)/\(c.month ?? 0)/\(c.day ?? 0)"
        }
        if field == "amountHistory", let list = value as? [Any] { return "\(list.count) 段" }
        if field == "isFixedSalary", let b = value as? Bool { return b ? "是" : "不是" }
        // [v25.644 mac4] fixedCategory、recurrence、endReason 是 rawValue 字串，照原字寫（下一行）
        if let s = value as? String { return s.isEmpty ? "（空白）" : s }
        if let n = value as? NSNumber { return n.stringValue }
        return "（看不懂的值）"
    }

    /// 欄位名 → 中文（sim2 field_name）
    static func fieldName(_ field: String) -> String {
        switch field {
        case "title": return "名稱"
        case "amount": return "金額"
        case "date": return "日期"
        case "variableCategory", "category", "fixedCategory": return "分類"
        case "note": return "備註"
        case "endDate": return "結束日"
        case "endReason": return "結束原因"
        case "period", "recurrence": return "週期"
        case "isFixedSalary": return "固定薪水"
        case "amountHistory": return "金額歷史"
        default: return field
        }
    }
}
