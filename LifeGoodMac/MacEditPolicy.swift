// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.640 mac1] 哪一筆、哪個欄位能在電腦改，鎖住時寫原因（judge_mac §O5 表）。
// 一支對一支照 scratchpad/radar/build/mac1/sim_mac1.py：expense_policy／expense_can_delete／income_policy／income_can_delete；
// 原因字＝sim 的 R 字典，一字不差（keycheck_mac1 逐字比）。
// [v25.641 mac2 G1] 收入照 judge_mac §P4：policy#1～#5、incomeDeleteReason、addBackReason（sim_mac2.py income_policy2／
// income_delete2／add_back_reason）；新 11 條原因字＝sim_mac2.R2。
import Foundation

/// 表單上能改的欄位（endDate＝結束日，結束原因跟它同一欄）
enum MacEditField: String, CaseIterable, Hashable {
    case title, note, amount, date, category, endDate

    var label: String {
        switch self {
        case .title: return "名稱"
        case .note: return "備註"
        case .amount: return "金額"
        case .date: return "日期"
        case .category: return "分類"
        case .endDate: return "結束日"
        }
    }

    /// 詳情欄鎖頭清單列哪幾欄（sim2 fields_for）：支出 5 欄；單次收入 5 欄；週期收入 6 欄（多結束日）
    static func fields(for ref: MacEntryRef, income: Income?) -> [MacEditField] {
        let five: [MacEditField] = [.title, .note, .amount, .date, .category]
        guard case .income = ref, let income, income.period != .once else { return five }
        return five + [.endDate]
    }
}

/// 一筆的判定：lock 不是 nil＝整筆只能看；否則 fieldReasons 裡有的欄位鎖住（值＝原因），沒有的欄位能改
struct MacEditVerdict {
    let lock: String?
    let fieldReasons: [MacEditField: String]

    static func locked(_ reason: String) -> MacEditVerdict {
        MacEditVerdict(lock: reason, fieldReasons: [:])
    }

    /// nil＝能改
    func reason(_ field: MacEditField) -> String? {
        if let lock { return lock }
        return fieldReasons[field]
    }

    func canEdit(_ field: MacEditField) -> Bool {
        reason(field) == nil
    }

    /// 至少有一欄能改（名稱、備註沒鎖整筆時一律能改）
    var canEditAny: Bool {
        lock == nil
    }
}

enum MacEditPolicy {
    // MARK: - 原因字（sim_mac1.py 的 R，一字不差）

    static let reasonFixed = "固定支出這一版先只能看，請在 iPhone 改"              // R['fixed']
    static let reasonCategory = "這個分類請在 iPhone 改"                            // R['cat']
    static let reasonVehicle = "這筆連著車子，請在 iPhone 改"                       // R['vehicle']
    static let reasonHouse = "這筆連著房子，請在 iPhone 改"                         // R['house']
    static let reasonStock = "這筆連著股票，請在 iPhone 改"                         // R['stock']、R['inc_stock']
    static let reasonInsurance = "這筆連著保險，請在 iPhone 改"                     // R['insurance']
    static let reasonNewer = "這筆是較新的 iPhone 版記的，請先更新電腦版"           // R['newer']
    static let reasonForeign = "這筆是外幣，金額、日期請在 iPhone 改"               // R['fx']
    static let reasonBank = "這筆連著銀行帳戶，金額、日期請在 iPhone 改"            // R['bank']
    static let reasonSplit = "這筆有分帳，請在 iPhone 改"                           // R['split']
    static let reasonTrip = "這筆連著旅行，金額、日期請在 iPhone 改"                // R['trip']
    static let reasonCategoryLinked = "這筆有同行或地點，分類請在 iPhone 改"        // R['catlinked']
    static let reasonPhoto = "這筆有照片，請在 iPhone 刪"                           // R['photo']
    static let reasonCard = "信用卡那幾筆這一版請在 iPhone 刪"                      // R['card']
    static let reasonSplitRecord = "這筆有分帳紀錄，請在 iPhone 刪"                 // R['splitrec']
    static let reasonKindRecord = "這筆有細項，請在 iPhone 刪"                      // R['kindrec']
    static let reasonIncomeStock = "這筆連著股票，請在 iPhone 改"                   // R['inc_stock']
    /// 只給刪除用（Mac 2 起連銀行的收入能改名稱、備註，不再整筆鎖）
    static let reasonIncomeBank = "這筆連著銀行帳戶，請在 iPhone 改"                // R['inc_bank']
    static let reasonIncomeRecurring = "每月、每年的收入金額要連財富頁一起改，請在 iPhone 改"   // R['inc_recurring']
    static let reasonIncomeInvest = "投資收入請在 iPhone 改"                        // R['inc_invest']

    // [v25.641 mac2] 新 11 條（sim_mac2.py R2，一字不差）
    static let reasonIncomeBankMore = "這筆連著銀行帳戶，分類、結束日請在 iPhone 改"   // R2['inc_bank_more']
    static let reasonIncomeRecurringDate = "每月、每年收入的開始日請在 iPhone 改"      // R2['inc_rec_date']
    static let reasonIncomeRecurringSalary = "每月收入要換成薪水或從薪水換掉，請在 iPhone 改"   // R2['inc_rec_salary']
    static let reasonIncomeRecurringCatEnd = "這筆設過結束日或固定薪水，分類請在 iPhone 改"    // R2['inc_rec_cat_end']
    static let reasonIncomeEndSalary = "只有固定薪水能設結束日"                     // R2['inc_end_salary']
    static let reasonIncomePeriod = "週期、固定薪水開關請在 iPhone 改"               // R2['inc_period']
    static let reasonIncomeAddBackLinked = "這筆連著銀行帳戶或股票，加回去存摺和股票不會跟著回來，請在 iPhone 重記"   // R2['inc_addback_linked']
    static let reasonGatePrefix = "這筆剛在 iPhone 改過，現在"                       // R2['gate_prefix']
    static let reasonFieldUnknown = "這一欄請在 iPhone 改"                           // R2['field_unknown']
    static let errorEndBefore = "結束日不能早於開始日"                               // R2['end_before']
    static let errorSalaryYearly = "薪水只有每月或單次"                              // R2['salary_yearly']

    // MARK: - 分類

    /// Mac 1 能記、能換的 8 類（sim EIGHT；照 VariableCategory.rawValue）
    static let eightCategoryNames: [String] = ["飲食", "交通", "娛樂", "購物", "日用品", "醫療", "教育", "其他"]
    static let eightCategories: [VariableCategory] = eightCategoryNames.compactMap { VariableCategory(rawValue: $0) }
    /// 收入能記、能換的 4 類（不給「投資」；sim INCOME_CATS）
    static let incomeCategories: [IncomeCategory] = [.salary, .bonus, .gift, .luck]
    /// [v25.641 mac2] 週期收入（沒連、沒設結束日或固定薪水）能互換的 3 類（sim2 RECURRING_CATS）
    static let recurringIncomeCategories: [IncomeCategory] = [.bonus, .gift, .luck]

    // MARK: - 支出（sim expense_policy）

    static func expense(_ e: Expense, rawEditable: Bool, liveSplitIDs: Set<UUID>) -> MacEditVerdict {
        if e.expenseType != .variable {
            return .locked(reasonFixed)
        }
        guard let cat = e.variableCategory, eightCategories.contains(cat) else {
            return .locked(reasonCategory)
        }
        if e.linkedVehicleId != nil { return .locked(reasonVehicle) }
        if e.linkedRealEstateId != nil { return .locked(reasonHouse) }
        if e.linkedStockId != nil { return .locked(reasonStock) }
        if e.linkedInsuranceId != nil { return .locked(reasonInsurance) }
        if !rawEditable { return .locked(reasonNewer) }

        var reasons: [MacEditField: String] = [:]
        let hasSplit = liveSplitIDs.contains(e.id)
        var amountReason: String?
        if e.currencyCode != "NT$" && !e.currencyCode.isEmpty {
            amountReason = reasonForeign
        } else if e.linkedBankMilestoneId != nil && e.linkedCreditCardMilestoneId == nil {
            amountReason = reasonBank
        } else if hasSplit {
            amountReason = reasonSplit
        } else if e.linkedTripPlanId != nil {
            amountReason = reasonTrip
        }
        if let amountReason {
            reasons[.amount] = amountReason
            reasons[.date] = amountReason
        }
        if hasSplit {
            reasons[.category] = reasonSplit
        } else if e.diningMember != nil || e.placeAddress != nil || e.placeLatitude != nil
                    || e.placeLongitude != nil || e.socialSubCategory != nil {
            reasons[.category] = reasonCategoryLinked
        }
        return MacEditVerdict(lock: nil, fieldReasons: reasons)
    }

    /// sim expense_can_delete：nil＝能刪。splitRecordIDs／kindRecordIDs＝分帳、細項裡有這個 id 的記錄（含墓碑）
    static func expenseDeleteReason(_ e: Expense, rawEditable: Bool, liveSplitIDs: Set<UUID>,
                                    splitRecordIDs: Set<String>, kindRecordIDs: Set<String>) -> String? {
        let v = expense(e, rawEditable: rawEditable, liveSplitIDs: liveSplitIDs)
        if let lock = v.lock { return lock }
        if let r = v.fieldReasons[.amount] { return r }
        if !e.photoFileNames.isEmpty { return reasonPhoto }
        if e.linkedCreditCardMilestoneId != nil { return reasonCard }
        let id = e.id.uuidString.uppercased()
        if splitRecordIDs.contains(id) { return reasonSplitRecord }
        if kindRecordIDs.contains(id) { return reasonKindRecord }
        return nil
    }

    // MARK: - 收入（sim2 income_policy2／income_delete2／add_back_reason；judge_mac §P4 判定順序）

    static func income(_ i: Income, rawEditable: Bool) -> MacEditVerdict {
        // sim2: policy#1 連股票：整筆鎖
        if i.linkedStockId != nil { return .locked(reasonIncomeStock) }
        // sim2: policy#2 看不懂的那筆：整筆鎖（移到銀行前面）
        if !rawEditable { return .locked(reasonNewer) }
        var reasons: [MacEditField: String] = [:]
        // sim2: policy#3 連銀行：只開名稱、備註
        if i.linkedBankMilestoneId != nil {
            reasons[.amount] = reasonBank
            reasons[.date] = reasonBank
            reasons[.category] = reasonIncomeBankMore
            reasons[.endDate] = reasonIncomeBankMore
            return MacEditVerdict(lock: nil, fieldReasons: reasons)
        }
        // sim2: policy#4 單次：同 Mac 1（投資那筆不換分類）；沒有結束日
        if i.period == .once {
            if i.category == .investment { reasons[.category] = reasonIncomeInvest }
            reasons[.endDate] = reasonIncomeEndSalary
            return MacEditVerdict(lock: nil, fieldReasons: reasons)
        }
        // sim2: policy#5 週期：金額、開始日鎖；分類只在獎金、禮金、確幸之間換；結束日只給每月固定薪水
        reasons[.amount] = reasonIncomeRecurring
        reasons[.date] = reasonIncomeRecurringDate
        if i.category == .investment {
            reasons[.category] = reasonIncomeInvest
        } else if i.category == .salary {
            reasons[.category] = reasonIncomeRecurringSalary
        } else if recurringIncomeCategories.contains(i.category)
                    && (i.isFixedSalary || i.endDate != nil || i.endReason != nil) {
            reasons[.category] = reasonIncomeRecurringCatEnd
        }
        let endOpen = i.category == .salary && i.isFixedSalary && i.period == .monthly
        if !endOpen { reasons[.endDate] = reasonIncomeEndSalary }
        return MacEditVerdict(lock: nil, fieldReasons: reasons)
    }

    /// [review writer-1] 換分類的新值（存的時候、復原時用那筆最新的樣子再查）：nil＝准。
    /// 單次只能換成 4 類；週期的新舊都要在獎金、禮金、確幸（換成或換掉薪水、投資一律擋）
    static func incomeCategoryChangeReason(_ i: Income, to value: Any?) -> String? {
        // sim2: catto#1 看不懂的值擋；跟那筆一樣＝沒換
        guard let raw = value as? String, let c = IncomeCategory(rawValue: raw) else { return reasonFieldUnknown }
        if c == i.category { return nil }
        if i.period == .once {
            if incomeCategories.contains(c) { return nil }
            return c == .investment ? reasonIncomeInvest : reasonFieldUnknown
        }
        if recurringIncomeCategories.contains(i.category) && recurringIncomeCategories.contains(c) { return nil }
        if i.category == .investment || c == .investment { return reasonIncomeInvest }
        return reasonIncomeRecurringSalary
    }

    /// sim2 income_delete2：nil＝能刪（單次、週期都可以）
    static func incomeDeleteReason(_ i: Income, rawEditable: Bool) -> String? {
        let v = income(i, rawEditable: rawEditable)
        if let lock = v.lock { return lock }
        if i.linkedBankMilestoneId != nil { return reasonIncomeBank }
        if i.category == .investment { return reasonIncomeInvest }
        return nil
    }

    /// 從備份加回、看門狗〔補回〕一整筆收入：原字典連著銀行或股票就不加回（存摺、股票不會跟著回來）
    static func addBackReason(raw: [String: Any]) -> String? {
        // sim2: addback（非空字串才算連著）
        for k in ["linkedBankMilestoneId", "linkedStockId"] {
            if let s = raw[k] as? String, !s.isEmpty { return reasonIncomeAddBackLinked }
        }
        return nil
    }

    // MARK: - 刪除前重抓：分帳、細項裡有這個 id 的記錄（含墓碑；只用 JSONSerialization 數 id，不解別的欄位）

    /// 分帳那包 {"splits":[{"id":…}]} 裡的 id（大寫）
    static func splitRecordIDs(_ data: Data?) -> Set<String> {
        recordIDs(data, listKey: "splits")
    }

    /// 細項那包 {"tags":[{"id":…}]} 裡的 id（大寫）
    static func kindRecordIDs(_ data: Data?) -> Set<String> {
        recordIDs(data, listKey: "tags")
    }

    private static func recordIDs(_ data: Data?, listKey: String) -> Set<String> {
        guard let data,
              let obj = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any],
              let list = obj[listKey] as? [Any] else { return [] }
        var out = Set<String>()
        for element in list {
            if let d = element as? [String: Any], let id = d["id"] as? String {
                out.insert(id.uppercased())
            }
        }
        return out
    }
}
