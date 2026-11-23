// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.640 mac1] 哪一筆、哪個欄位能在電腦改，鎖住時寫原因（judge_mac §O5 表）。
// 一支對一支照 scratchpad/radar/build/mac1/sim_mac1.py：expense_policy／expense_can_delete／income_policy／income_can_delete；
// 原因字＝sim 的 R 字典，一字不差（keycheck_mac1 逐字比）。
import Foundation

/// 表單上能改的五個欄位
enum MacEditField: String, CaseIterable, Hashable {
    case title, note, amount, date, category

    var label: String {
        switch self {
        case .title: return "名稱"
        case .note: return "備註"
        case .amount: return "金額"
        case .date: return "日期"
        case .category: return "分類"
        }
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
    static let reasonIncomeBank = "這筆連著銀行帳戶，請在 iPhone 改"                // R['inc_bank']
    static let reasonIncomeRecurring = "每月、每年的收入金額要連財富頁一起改，請在 iPhone 改"   // R['inc_recurring']
    static let reasonIncomeInvest = "投資收入請在 iPhone 改"                        // R['inc_invest']

    // MARK: - 分類

    /// Mac 1 能記、能換的 8 類（sim EIGHT；照 VariableCategory.rawValue）
    static let eightCategoryNames: [String] = ["飲食", "交通", "娛樂", "購物", "日用品", "醫療", "教育", "其他"]
    static let eightCategories: [VariableCategory] = eightCategoryNames.compactMap { VariableCategory(rawValue: $0) }
    /// 收入能記、能換的 4 類（不給「投資」；sim INCOME_CATS）
    static let incomeCategories: [IncomeCategory] = [.salary, .bonus, .gift, .luck]

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

    // MARK: - 收入（sim income_policy／income_can_delete）

    static func income(_ i: Income, rawEditable: Bool) -> MacEditVerdict {
        if i.linkedStockId != nil { return .locked(reasonIncomeStock) }
        if i.linkedBankMilestoneId != nil { return .locked(reasonIncomeBank) }
        if !rawEditable { return .locked(reasonNewer) }
        var reasons: [MacEditField: String] = [:]
        if i.period != .once {
            reasons[.amount] = reasonIncomeRecurring
            reasons[.date] = reasonIncomeRecurring
            reasons[.category] = reasonIncomeRecurring
        } else if i.category == .investment {
            reasons[.category] = reasonIncomeInvest
        }
        return MacEditVerdict(lock: nil, fieldReasons: reasons)
    }

    static func incomeDeleteReason(_ i: Income, rawEditable: Bool) -> String? {
        let v = income(i, rawEditable: rawEditable)
        if let lock = v.lock { return lock }
        if i.period != .once { return reasonIncomeRecurring }
        if i.category == .investment { return reasonIncomeInvest }
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
