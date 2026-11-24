// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.640 mac1] 哪一筆、哪個欄位能在電腦改，鎖住時寫原因（judge_mac §O5 表）。
// 一支對一支照 scratchpad/radar/build/mac1/sim_mac1.py：expense_policy／expense_can_delete／income_policy／income_can_delete；
// 原因字＝sim 的 R 字典，一字不差（keycheck_mac1 逐字比）。
// [v25.641 mac2 G1] 收入照 judge_mac §P4：policy#1～#5、incomeDeleteReason、addBackReason（sim_mac2.py income_policy2／
// income_delete2／add_back_reason）；新 11 條原因字＝sim_mac2.R2。
// [v25.642 mac3 G1] 支出照 judge_mac §Q5、§Q6（sim_mac3.py expense3／delete3／cat_change3／dup3／addback3／live_kind_ids／
// link_data_parses／value_ok；sim3 編號 policy3#、del3#、catto3#、dup3#、addback3#、links3#、post3#）：連旅行那筆的金額、日期、刪除開；
// 外幣只鎖金額；有活細項整筆鎖；選過地點的名稱鎖；有分帳紀錄或殘留欄位的分類鎖；⌘D 複製、從備份加回的擋法。新原因字＝sim_mac3.R3。
import Foundation

/// 支出那筆連著的東西（快取版 cachedLinks()／剛抓到版 links(_:)）。只有 memberwise init：忘了傳＝編不過，不會變成少擋
struct MacLinkIDs {
    let liveSplitIDs: Set<UUID>
    let splitRecordIDs: Set<String>
    let kindRecordIDs: Set<String>
    let liveKindIDs: Set<String>
}

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

    // [v25.642 mac3] 新 16 條（sim_mac3.py R3，一字不差；Mac 1、Mac 2 的一條都不改，reasonForeign、reasonTrip 留著不用）
    static let reasonForeignAmount = "這筆是外幣，金額請在 iPhone 改"                 // R3['fx_amount']
    static let reasonTitlePlace = "這筆選過地點，名稱請在 iPhone 改（iPhone 改名稱會一起換地點）"   // R3['title_place']
    static let reasonSplitRecordEdit = "這筆有分帳紀錄，分類請在 iPhone 改"           // R3['split_rec_edit']
    static let reasonCategoryResidue = "這筆有舊版留下的欄位，分類請在 iPhone 改"     // R3['cat_residue']
    static let reasonKindLive = "這筆有細項，請在 iPhone 改"                          // R3['kind_live']
    static let reasonDuplicateKind = "這筆有細項，複製請在 iPhone 做"                 // R3['dup_kind']
    static let reasonDuplicatePay = "這筆有付款方式（信用卡或銀行），複製請在 iPhone 做"   // R3['dup_pay']
    static let reasonDuplicateResidue = "這筆有舊版留下的欄位，複製請在 iPhone 做"    // R3['dup_residue']
    static let reasonExpenseAddBackLinked = "這筆連著銀行、照片、分帳或細項，加回去那邊不會跟著回來，請在 iPhone 重記"   // R3['exp_addback_linked']
    static let reasonDetachLinked = "這筆在 iPhone 刪掉了，而且有分帳或細項，請在 iPhone 重記"   // R3['exp_detach_linked']
    static let reasonLinksUnknown = "確認不了這筆有沒有分帳或細項，這次先不存，請按 ⌘R 再試"     // R3['links_unknown']
    static let reasonPostShape = "這次要寫的內容跟你改的不一樣，這次先不存，請按 ⌘R 再試"       // R3['post_shape']
    static let reasonValueBad = "這一欄的值不對，這次先不存"                          // R3['value_bad']
    static let hintIPhoneOnly = "付款方式、同行、地點、照片請在 iPhone 改"            // R3['hint_iphone_only']
    static let duplicateButton = "複製"                                               // R3['dup_button']
    /// 確認框標題（R3['dup_confirm']）
    static func duplicateConfirm(_ label: String) -> String { "複製「\(label)」成新的一筆？日期會改成現在。" }

    // MARK: - 分類

    /// Mac 1 能記、能換的 8 類（sim EIGHT；照 VariableCategory.rawValue）
    static let eightCategoryNames: [String] = ["飲食", "交通", "娛樂", "購物", "日用品", "醫療", "教育", "其他"]
    static let eightCategories: [VariableCategory] = eightCategoryNames.compactMap { VariableCategory(rawValue: $0) }
    /// 收入能記、能換的 4 類（不給「投資」；sim INCOME_CATS）
    static let incomeCategories: [IncomeCategory] = [.salary, .bonus, .gift, .luck]
    /// [v25.641 mac2] 週期收入（沒連、沒設結束日或固定薪水）能互換的 3 類（sim2 RECURRING_CATS）
    static let recurringIncomeCategories: [IncomeCategory] = [.bonus, .gift, .luck]

    // MARK: - 支出（sim3 expense3／delete3／cat_change3／dup3／addback3；judge_mac §Q5 判定順序）

    // 照抄 ExpenseKinds.swift:374、:758、:1123（48c51a2）
    /// iPhone 存任何一次都會寫細項墓碑的那三種分類簽名（handledBasesV3；用 rawValue 拼）
    static let handledBasesV3: Set<String> = ["fixed." + FixedCategory.other.rawValue, "vehicle." + VehicleVariableCategory.other.rawValue, "re." + RealEstateExpenseCategory.tax.rawValue]

    /// 直接扣款：連著銀行、沒連信用卡
    static func isDirectDebit(_ e: Expense) -> Bool {
        e.linkedBankMilestoneId != nil && e.linkedCreditCardMilestoneId == nil
    }

    /// 選過地點（地址、座標任一；placeName 不算）
    static func hasPlace(_ e: Expense) -> Bool {
        e.placeAddress != nil || e.placeLatitude != nil || e.placeLongitude != nil
    }

    /// 舊版留下的欄位（換分類時 iPhone 會連帶清掉的那幾欄）
    static func hasResidue(_ e: Expense) -> Bool {
        if e.placeName != nil || e.vehicleExpenseCategory != nil || e.realEstateExpenseCategory != nil { return true }
        if e.taxSavingSubCategory != nil || e.evKwh != nil || e.evFromPct != nil { return true }
        return e.evToPct != nil || e.evOdometer != nil || e.fuelLiters != nil
    }

    /// 外幣（同 Mac 1：不是 NT$ 也不是空字串；TWD 也算）
    static func isForeign(_ e: Expense) -> Bool {
        e.currencyCode != "NT$" && !e.currencyCode.isEmpty
    }

    static func expense(_ e: Expense, rawEditable: Bool, links: MacLinkIDs) -> MacEditVerdict {
        // sim3: policy3#1 固定支出：整筆鎖
        if e.expenseType != .variable {
            return .locked(reasonFixed)
        }
        // sim3: policy3#2 不在 8 類：整筆鎖
        guard let cat = e.variableCategory, eightCategories.contains(cat) else {
            return .locked(reasonCategory)
        }
        // sim3: policy3#3 車子 → 房子 → 股票 → 保險
        if e.linkedVehicleId != nil { return .locked(reasonVehicle) }
        if e.linkedRealEstateId != nil { return .locked(reasonHouse) }
        if e.linkedStockId != nil { return .locked(reasonStock) }
        if e.linkedInsuranceId != nil { return .locked(reasonInsurance) }
        // sim3: policy3#4 看不懂的那筆
        if !rawEditable { return .locked(reasonNewer) }
        let upper = e.id.uuidString.uppercased()
        // sim3: policy3#5 有活細項：iPhone 存任何一次都寫細項墓碑 → 整筆鎖
        if links.liveKindIDs.contains(upper) { return .locked(reasonKindLive) }

        var reasons: [MacEditField: String] = [:]
        let live = links.liveSplitIDs.contains(e.id)
        let direct = isDirectDebit(e)
        // sim3: policy3#6 金額：直接扣款 ＞ 活分帳 ＞ 外幣（旅行不再鎖）
        if direct {
            reasons[.amount] = reasonBank
        } else if live {
            reasons[.amount] = reasonSplit
        } else if isForeign(e) {
            reasons[.amount] = reasonForeignAmount
        }
        // sim3: policy3#7 日期：直接扣款 ＞ 活分帳（外幣、旅行不再鎖）
        if direct {
            reasons[.date] = reasonBank
        } else if live {
            reasons[.date] = reasonSplit
        }
        // sim3: policy3#8 分類：活分帳 ＞ 分帳紀錄 ＞ 同行／地點／社交種類 ＞ 殘留欄位
        if live {
            reasons[.category] = reasonSplit
        } else if links.splitRecordIDs.contains(upper) {
            reasons[.category] = reasonSplitRecordEdit
        } else if e.diningMember != nil || e.placeAddress != nil || e.placeLatitude != nil
                    || e.placeLongitude != nil || e.socialSubCategory != nil {
            reasons[.category] = reasonCategoryLinked
        } else if hasResidue(e) {
            reasons[.category] = reasonCategoryResidue
        }
        // sim3: policy3#9 名稱：選過地點就鎖（iPhone 改名稱會一起換地點）
        if hasPlace(e) {
            reasons[.title] = reasonTitlePlace
        }
        // sim3: policy3#10 備註：開
        return MacEditVerdict(lock: nil, fieldReasons: reasons)
    }

    /// nil＝能刪。links.splitRecordIDs／kindRecordIDs＝分帳、細項裡有這個 id 的記錄（含墓碑）
    static func expenseDeleteReason(_ e: Expense, rawEditable: Bool, links: MacLinkIDs) -> String? {
        // sim3: del3#1 整筆鎖 → 日期那欄的原因（直接扣款、活分帳）→ 照片 → 信用卡 → 分帳紀錄 → 細項紀錄
        let v = expense(e, rawEditable: rawEditable, links: links)
        if let lock = v.lock { return lock }
        if let r = v.fieldReasons[.date] { return r }
        if !e.photoFileNames.isEmpty { return reasonPhoto }
        if e.linkedCreditCardMilestoneId != nil { return reasonCard }
        let id = e.id.uuidString.uppercased()
        if links.splitRecordIDs.contains(id) { return reasonSplitRecord }
        if links.kindRecordIDs.contains(id) { return reasonKindRecord }
        return nil
    }

    /// 換分類的新值：字串、解得成 VariableCategory、在 8 類（postCheck 也用這支）
    static func expenseCategoryValueOK(_ value: Any?) -> Bool {
        guard let raw = value as? String, let c = VariableCategory(rawValue: raw) else { return false }
        return eightCategories.contains(c)
    }

    /// 換分類的新值（policyBlock、gate 都看）：nil＝准；鎖不鎖由 verdict 管
    static func expenseCategoryChangeReason(_ e: Expense, to value: Any?) -> String? {
        // sim3: catto3#1 不是 8 類裡的字串一律擋
        expenseCategoryValueOK(value) ? nil : reasonFieldUnknown
    }

    /// ⌘D 複製：nil＝能複製（外幣可以）
    static func expenseDuplicateReason(_ e: Expense, rawEditable: Bool, links: MacLinkIDs) -> String? {
        // sim3: dup3#1 整筆鎖 → 細項紀錄 → 付款方式 → 殘留欄位
        let v = expense(e, rawEditable: rawEditable, links: links)
        if let lock = v.lock { return lock }
        if links.kindRecordIDs.contains(e.id.uuidString.uppercased()) { return reasonDuplicateKind }
        if e.linkedCreditCardMilestoneId != nil || e.linkedBankMilestoneId != nil { return reasonDuplicatePay }
        if hasResidue(e) { return reasonDuplicateResidue }
        return nil
    }

    /// 從備份加回、看門狗〔補回〕、⌘Z 復原刪除、⌘D 複製：一整筆支出加回去之前（policyBlock 用快取、postCheck 用剛抓到的）
    static func expenseAddBackReason(raw: [String: Any], links: MacLinkIDs) -> String? {
        // sim3: addback3#1 解不開或不 editable → newer；整筆鎖 → 那個字；連著銀行、照片、分帳、細項 → 不加回
        guard let schema = LedgerMerge.schema(for: LedgerMerge.expensesKey),
              JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw, options: []),
              let e = try? JSONDecoder().decode(Expense.self, from: data),
              LedgerMerge.editable(schema, raw: raw) else {
            return reasonNewer
        }
        let v = expense(e, rawEditable: true, links: links)
        if let lock = v.lock { return lock }
        let id = e.id.uuidString.uppercased()
        if isDirectDebit(e) || !e.photoFileNames.isEmpty { return reasonExpenseAddBackLinked }
        if links.splitRecordIDs.contains(id) || links.kindRecordIDs.contains(id) { return reasonExpenseAddBackLinked }
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

    /// 細項那包裡「活細項」的支出 id（大寫）：同 id 取 updatedAt 新的（沒有／Bool／不是數字＝最舊；一樣新留先出現的，
    /// 照 ExpenseKinds.swift:82-90），kind 是字串（含空字串：iPhone formSavingTagV3 只看 kind != nil）、base 在 handledBasesV3
    static func liveKindIDs(_ data: Data?) -> Set<String> {
        // sim3: links3#1 只用 JSONSerialization，不解別的欄位
        guard let data,
              let obj = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any],
              let list = obj["tags"] as? [Any] else { return [] }
        var best: [String: (t: Double?, tag: [String: Any])] = [:]
        for element in list {
            guard let d = element as? [String: Any], let rawID = d["id"] as? String,
                  let uuid = UUID(uuidString: rawID) else { continue }
            let k = uuid.uuidString
            // updatedAt：數字才算（Bool、沒有、不是數字＝最舊）
            var t: Double? = nil
            if let n = d["updatedAt"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite {
                t = n.doubleValue
            }
            if let old = best[k], (old.t ?? -Double.infinity) >= (t ?? -Double.infinity) { continue }
            best[k] = (t: t, tag: d)
        }
        var out = Set<String>()
        for (k, entry) in best {
            guard entry.tag["kind"] is String, let base = entry.tag["base"] as? String else { continue }
            if handledBasesV3.contains(base) { out.insert(k) }
        }
        return out
    }

    /// 分帳、細項那包解得開嗎：沒有那包＝true；JSON 物件而且 listKey 沒有或是陣列＝true；其餘 false（存的時候擋 links_unknown）
    static func linkDataParses(_ data: Data?, listKey: String) -> Bool {
        // sim3: links3#2 只有〔不是〕的細項包（沒有 tags）也算解得開
        guard let data else { return true }
        guard let obj = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else { return false }
        return obj[listKey] == nil || obj[listKey] is [Any]
    }

    /// JSONSerialization 的數字（不是 Bool、有限）；其餘 nil
    static func plainNumber(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let d = n.doubleValue
        return d.isFinite ? d : nil
    }

    // MARK: - postCheck（合併後真正要寫的那一筆；MacEditCenter.postReason 用）

    // sim3: post3#P3 每包准改的鍵、逐欄值範圍
    static let expensePostKeys: Set<String> = ["title", "note", "amount", "date", "variableCategory"]
    static let incomePostKeys: Set<String> = ["title", "note", "amount", "date", "category", "endDate", "endReason"]
    /// 日期：timeIntervalSinceReferenceDate 在 1970～2100（只擋明顯壞掉的）
    static let postDateRange: ClosedRange<Double> = -978307200...3124137600

    /// 合併後那一欄的值合不合法（value＝合併後那筆的值；沒有那個鍵＝nil、JSON null＝NSNull）
    static func postValueOK(key: String, field: String, value: Any?) -> Bool {
        switch field {
        case "title":
            guard let s = value as? String else { return false }
            return !s.trimmingCharacters(in: .whitespaces).isEmpty
        case "note":
            return value is String
        case "amount":
            guard let n = plainNumber(value) else { return false }
            return n > 0
        case "date":
            guard let n = plainNumber(value) else { return false }
            return postDateRange.contains(n)
        default:
            break
        }
        if key == LedgerMerge.expensesKey {
            return field == "variableCategory" && expenseCategoryValueOK(value)
        }
        guard key == LedgerMerge.incomesKey else { return false }
        let isNull = value == nil || value is NSNull
        switch field {
        case "category":
            guard let s = value as? String else { return false }
            return IncomeCategory(rawValue: s) != nil
        case "endDate":
            if isNull { return true }
            guard let n = plainNumber(value) else { return false }
            return postDateRange.contains(n)
        case "endReason":
            if isNull { return true }
            guard let s = value as? String else { return false }
            return SalaryEndReason(rawValue: s) != nil
        default:
            return false
        }
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
