// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.640 mac1] 哪一筆、哪個欄位能在電腦改，鎖住時寫原因（judge_mac §O5 表）。
// 一支對一支照 scratchpad/radar/build/mac1/sim_mac1.py：expense_policy／expense_can_delete／income_policy／income_can_delete；
// 原因字＝sim 的 R 字典，一字不差（keycheck_mac1 逐字比）。
// [v25.641 mac2 G1] 收入照 judge_mac §P4：policy#1～#5、incomeDeleteReason、addBackReason（sim_mac2.py income_policy2／
// income_delete2／add_back_reason）；新 11 條原因字＝sim_mac2.R2。
// [v25.642 mac3 G1] 支出照 judge_mac §Q5、§Q6（sim_mac3.py expense3／delete3／cat_change3／dup3／addback3／live_kind_ids／
// link_data_parses／value_ok；sim3 編號 policy3#、del3#、catto3#、dup3#、addback3#、links3#、post3#）：連旅行那筆的金額、日期、刪除開；
// 外幣只鎖金額；有活細項整筆鎖；選過地點的名稱鎖；有分帳紀錄或殘留欄位的分類鎖；⌘D 複製、從備份加回的擋法。新原因字＝sim_mac3.R3。
// [v25.644 mac4 G1] 固定支出照 judge_mac §R4、§R5（sim_mac4.py fixed_verdict／policy4／delete4／dup4／addback4／cat_change4／
// recurrence_value_reason／fixed_end_reason_value_reason／amount_history_value_reason（8-B）／value_ok4／post_same；sim4 編號
// policy4#、residue4#、del4#、dup4#、addback4#、catto4#、rec4#、endr4#、hist4#）：一般固定（六類、有週期、沒連車房股保、沒活細項、
// 沒分帳紀錄）開名稱、備註、停止；台幣金額（已開始只給〔從今天起〕）；第一期還沒到的扣款日、週期；六類之間換分類。新原因字＝sim_mac4.NEW4。
// 照抄的那幾支在 MacFixedCal.swift（WealthFacts.swift、AddExpenseView.swift（f2c8892））。
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
    /// [v25.644 mac4] 固定支出的週期（只有固定支出那筆用；收入、變動支出的鎖頭清單不列）
    case recurrence

    var label: String {
        switch self {
        case .title: return "名稱"
        case .note: return "備註"
        case .amount: return "金額"
        case .date: return "日期"
        case .category: return "分類"
        case .endDate: return "結束日"
        case .recurrence: return "週期"
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
    // [v25.644 mac4] 總設計先放（judge_mac §R9 名稱表；簽名不准改）
    static let hintFixedIPhoneOnly = "付款方式、細項、節稅、照片、連著的資產請在 iPhone 改"   // R4['hint_fixed_iphone_only']
    // [v25.644 mac4 G1] 新原因字（sim_mac4.py NEW4，一字不差；Mac 1～3 的一條都不改，reasonFixed 留著不用）
    static let reasonFixedLegacy = "這筆是舊資料（沒有週期或分類），請先在 iPhone 打開存一次"          // R4['fixed_legacy']
    static let reasonFixedPolicy = "保險會連著財富頁的保單，這一版請在 iPhone 改"                    // R4['fixed_policy']
    static let reasonFixedLoan = "貸款會連著房子、車子和利率一起算，這一版請在 iPhone 改"            // R4['fixed_loan']
    static let reasonFixedSplit = "這筆有分帳紀錄，請在 iPhone 改"                                   // R4['fixed_split']
    static let reasonFixedStarted = "第一期已經扣過了，改扣款日或週期會連以前的期數一起移，請在 iPhone 改"   // R4['fixed_started']
    static let reasonFixedHistFuture = "這筆的金額紀錄有之後才生效的金額，金額請在 iPhone 改"         // R4['fixed_hist_future']
    static let reasonFixedHistFull = "這筆的金額紀錄太多了，金額請在 iPhone 改"                       // R4['fixed_hist_full']
    static let reasonFixedCatTax = "這筆設過節稅，分類請在 iPhone 改"                                 // R4['fixed_cat_tax']
    static let reasonFixedCatKind = "這筆有細項紀錄，分類請在 iPhone 改"                              // R4['fixed_cat_kind']
    static let reasonFixedDelete = "固定支出請在 iPhone 刪（iPhone 會一起清車子、存摺上掛著這筆的紀錄）；不再扣款的話，請用〔停止扣款…〕"   // R4['fixed_delete']
    static let reasonFixedDetach = "這筆固定支出在 iPhone 刪掉了，請在 iPhone 重記"                   // R4['fixed_detach']
    static let reasonFixedAmountMoved = "這筆的金額或扣款日剛在 iPhone 改過，請關掉表單重新打開再改"   // R4['fixed_amount_moved']
    static let reasonFixedPast = "這樣改會動到今天以前已經扣過的期數，這次先不存，請在 iPhone 改"     // R4['fixed_past']
    static let reasonFixedEndCut = "停止日不能早於最近已經扣過的那一期"                               // R4['fixed_end_cut']
    static let reasonFixedEndReopen = "停止的日子已經過了，改晚或取消停止會多出以前的期數，請在 iPhone 改"   // R4['fixed_end_reopen']
    static let reasonDuplicateFixed = "固定支出不能複製，請按 ⌘N 記一筆"                              // R4['dup_fixed']
    static let fixedAllIPhone = "要連以前扣過的那幾期一起改，請在 iPhone 改"                          // R4['fixed_all_iphone']
    static let fixedDateHint = "第一期還沒到，改扣款日只會影響之後的期數"                             // R4['fixed_date_hint']
    static let fixedStartedHint = "第一期已經扣過了，存的時候會問以前的要不要跟著改"                   // R4['fixed_started_hint']
    static let errorFixedTitleEmpty = "固定支出要填名稱"                                              // R4['fixed_title_empty']
    static let errorFixedDatePast = "扣款日不能改到今天以前（會多出以前的期數），請在 iPhone 改"       // R4['fixed_date_past']
    static let fixedDeleteOwn = "這筆是剛在電腦記的，iPhone 還沒改過它。"                             // R4['fixed_delete_own']
    static let stopButton = "停止扣款…"                                                               // R4['stop_button']
    static let askFromToday = "從今天起（以前的照舊）"                                                // R4['ask_from']
    /// 固定支出那筆詳情鎖頭清單列的 7 欄（.endDate 對固定支出畫面字寫「停止」）
    static let fixedFields: [MacEditField] = [.title, .note, .amount, .date, .recurrence, .category, .endDate]
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
    /// [v25.644 mac4] 電腦能改、能換、能記的固定支出 6 類（sim4 SIX；用 case，不寫字面值）
    static let plainFixedCategories: [FixedCategory] = [.rent, .utilities, .subscription, .telecom, .management, .other]

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

    static func expense(_ e: Expense, rawEditable: Bool, links: MacLinkIDs, now: Date = Date()) -> MacEditVerdict {
        // [v25.644 mac4] 固定支出走 fixedVerdict（policy4#1～#9）；sim3: policy3#1 之後的變動支出一行不動
        if e.expenseType == .fixed {
            return fixedVerdict(e, rawEditable: rawEditable, links: links, now: now)
        }
        // sim3: policy3#1 不是變動支出（這一版的模型只有兩種；看不懂的類型解不開，到不了這裡）：整筆鎖
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

    // MARK: - 固定支出（sim4 fixed_verdict；judge_mac §R5 判定順序）

    /// 固定支出那筆：連車房股保 → 看不懂 → 舊資料 → 保險 → 貸款 → 活細項 → 分帳紀錄 → 不在六類 → 逐欄
    private static func fixedVerdict(_ e: Expense, rawEditable: Bool, links: MacLinkIDs, now: Date) -> MacEditVerdict {
        // sim4: policy4#1 車子 → 房子 → 股票 → 保險（連著的那幾類 iPhone 存的時候會一起寫別包）
        if e.linkedVehicleId != nil { return .locked(reasonVehicle) }
        if e.linkedRealEstateId != nil { return .locked(reasonHouse) }
        if e.linkedStockId != nil { return .locked(reasonStock) }
        if e.linkedInsuranceId != nil { return .locked(reasonInsurance) }
        // sim4: policy4#2 看不懂的那筆
        if !rawEditable { return .locked(reasonNewer) }
        // sim4: policy4#3 舊資料：沒分類或沒週期（iPhone 打開表單就補，存一次就變了）
        guard let cat = e.fixedCategory, e.recurrence != nil else { return .locked(reasonFixedLegacy) }
        // sim4: policy4#4 保險（iPhone 每存一次都動帳本的保單）
        if cat == .insurance { return .locked(reasonFixedPolicy) }
        // sim4: policy4#5 貸款
        if cat == .loan { return .locked(reasonFixedLoan) }
        let upper = e.id.uuidString.uppercased()
        // sim4: policy4#6 有活細項（稅費組）
        if links.liveKindIDs.contains(upper) { return .locked(reasonKindLive) }
        // sim4: policy4#7 分帳紀錄（含墓碑）或活分帳
        if links.splitRecordIDs.contains(upper) || links.liveSplitIDs.contains(e.id) { return .locked(reasonFixedSplit) }
        // sim4: policy4#8 不在六類（看不懂的新分類）
        guard plainFixedCategories.contains(cat) else { return .locked(reasonNewer) }
        // sim4: policy4#9 逐欄：名稱、備註、停止開；金額、扣款日、週期、分類看下面
        return MacEditVerdict(lock: nil, fieldReasons: fixedFieldReasons(e, links: links, now: now))
    }

    /// policy4#9 的欄位原因（沒列的欄位能改）
    private static func fixedFieldReasons(_ e: Expense, links: MacLinkIDs, now: Date) -> [MacEditField: String] {
        var reasons: [MacEditField: String] = [:]
        let started = MacFixedCal.isStarted(e, now: now)
        // 金額：外幣 ＞ 金額紀錄有明天以後的點 ＞ 紀錄 ≥ 1199 筆 ＞（★1）〔從今天起〕也會動到以前的期數
        if isForeign(e) {
            reasons[.amount] = reasonForeignAmount
        } else if started && MacFixedCal.historyHasFuture(e, now: now) {
            reasons[.amount] = reasonFixedHistFuture
        } else if started && e.amountHistory.count >= 1199 {
            reasons[.amount] = reasonFixedHistFull
        } else if started && !MacFixedCal.fromTodayKeepsPast(e, now: now) {
            reasons[.amount] = reasonFixedPast
        }
        // 扣款日、週期：第一期已經扣過了就鎖
        if started {
            reasons[.date] = reasonFixedStarted
            reasons[.recurrence] = reasonFixedStarted
        }
        // 分類：節稅覆寫 ＞ 細項紀錄（含墓碑）＞ 舊版殘留
        if e.taxDeductibleOverride != nil {
            reasons[.category] = reasonFixedCatTax
        } else if links.kindRecordIDs.contains(e.id.uuidString.uppercased()) {
            reasons[.category] = reasonFixedCatKind
        } else if hasFixedResidue(e) {
            reasons[.category] = reasonCategoryResidue
        }
        return reasons
    }

    /// 固定支出不該有的舊欄位（iPhone 換分類整筆重建時會連帶清掉）— sim4: residue4#1
    static func hasFixedResidue(_ e: Expense) -> Bool {
        // sim4: residue4#1 RESIDUE4 那 24 欄任一非 nil
        if e.variableCategory != nil || e.vehicleExpenseCategory != nil || e.realEstateExpenseCategory != nil { return true }
        if e.taxSavingSubCategory != nil || e.socialSubCategory != nil || e.socialRecipient != nil { return true }
        if e.diningMember != nil || e.placeName != nil || e.placeAddress != nil { return true }
        if e.placeLatitude != nil || e.placeLongitude != nil || e.evKwh != nil { return true }
        if e.evFromPct != nil || e.evToPct != nil || e.evOdometer != nil || e.fuelLiters != nil { return true }
        if e.linkedTripPlanId != nil || e.linkedTripStopId != nil { return true }
        if e.insuranceSubCategory != nil || e.loanSubCategory != nil || e.loanTotalAmount != nil { return true }
        if e.loanYears != nil || e.loanRate != nil || e.insuranceRate != nil { return true }
        // 孤兒銀行幣別（銀行在 iPhone 刪掉時只清 id）
        if !(e.linkedBankCurrency ?? "").isEmpty && e.linkedBankMilestoneId == nil { return true }
        // 有停止原因、沒有停止日
        return e.endReason != nil && e.endDate == nil
    }

    /// nil＝能刪。links.splitRecordIDs／kindRecordIDs＝分帳、細項裡有這個 id 的記錄（含墓碑）
    static func expenseDeleteReason(_ e: Expense, rawEditable: Bool, links: MacLinkIDs) -> String? {
        // sim4: del4#1 固定支出：整筆鎖 → 那個字；其餘一律 fixed_delete（電腦剛記的那筆由 MacEditCenter.deleteReason 先判）
        if e.expenseType == .fixed {
            return fixedVerdict(e, rawEditable: rawEditable, links: links, now: Date()).lock ?? reasonFixedDelete
        }
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
        if e.expenseType != .variable { return reasonDuplicateFixed }       // sim4: dup4#1 固定支出一律不給複製
        // sim3: dup3#1 整筆鎖 → 細項紀錄 → 付款方式 → 殘留欄位
        let v = expense(e, rawEditable: rawEditable, links: links)
        if let lock = v.lock { return lock }
        if links.kindRecordIDs.contains(e.id.uuidString.uppercased()) { return reasonDuplicateKind }
        if e.linkedCreditCardMilestoneId != nil || e.linkedBankMilestoneId != nil { return reasonDuplicatePay }
        // 銀行在 iPhone 刪掉時只清 linkedBankMilestoneId、幣別留著（LifeStore.swift:1799（48c51a2））；
        // 複製會照抄那個幣別 → postCheck A3 一定擋，所以這裡先當成舊欄位擋（選單、詳情鈕反灰，不會按了才失敗）
        if hasResidue(e) || !(e.linkedBankCurrency ?? "").isEmpty { return reasonDuplicateResidue }
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
        // sim4: addback4#1 固定支出：連著銀行（不只直接扣款；iPhone 刪的時候會清存摺）、照片、分帳、細項 → 不加回；只有信用卡放行
        if e.expenseType == .fixed {
            if e.linkedBankMilestoneId != nil || !e.photoFileNames.isEmpty { return reasonExpenseAddBackLinked }
            if links.splitRecordIDs.contains(id) || links.kindRecordIDs.contains(id) { return reasonExpenseAddBackLinked }
            return nil
        }
        if isDirectDebit(e) || !e.photoFileNames.isEmpty { return reasonExpenseAddBackLinked }
        if links.splitRecordIDs.contains(id) || links.kindRecordIDs.contains(id) { return reasonExpenseAddBackLinked }
        return nil
    }

    // MARK: - 固定支出新開放欄位的值檢查（gate、policyBlock 驗電腦交出去的原值；postCheck P3 驗合併後的值）

    /// 換分類的新值：那筆是固定支出、字串、六類 → nil；其餘 field_unknown — sim4: catto4#1
    static func fixedCategoryChangeReason(_ e: Expense, to value: Any?) -> String? {
        // sim4: catto4#1
        guard e.expenseType == .fixed, let s = value as? String, let c = FixedCategory(rawValue: s),
              plainFixedCategories.contains(c) else { return reasonFieldUnknown }
        return nil
    }

    /// 週期的新值：字串而且解得成 Recurrence → nil；nil、NSNull、亂字 → field_unknown — sim4: rec4#1
    static func recurrenceValueReason(_ value: Any?) -> String? {
        // sim4: rec4#1（不准拿掉週期）
        guard let s = value as? String, Recurrence(rawValue: s) != nil else { return reasonFieldUnknown }
        return nil
    }

    /// 停止原因的新值：nil（拿掉）、NSNull、解得成 FixedEndReason → nil；其餘 field_unknown — sim4: endr4#1
    static func fixedEndReasonValueReason(_ value: Any?) -> String? {
        // sim4: endr4#1
        guard let value, !(value is NSNull) else { return nil }
        guard let s = value as? String, FixedEndReason(rawValue: s) != nil else { return reasonFieldUnknown }
        return nil
    }

    /// 金額歷史上限（照 WealthSchedule.fixedPeriods 的 1200 期）；policy4#9 在 1199 筆就先鎖金額
    static let amountHistoryMax = 1200

    /// 金額歷史的值（8-B）：陣列、≤ 1200 筆；每個元素字典、鍵剛好 id／date／amount；id 大寫標準形 UUID、整份不重複；
    /// 跟剛抓到那筆同 id 同內容的舊元素不驗值；新冒出來的：date 數字在 postDateRange、amount 有限 > 0 — sim4: hist4#1
    static func amountHistoryValueReason(_ value: Any?, fetched: Any?) -> String? {
        // sim4: hist4#1（不要求排序、不要求最後一筆＝amount；fetched＝剛抓到那筆的 amountHistory 原值）
        guard let list = value as? [Any], list.count <= amountHistoryMax else { return reasonValueBad }
        var old: [String: [String: Any]] = [:]
        if let prior = fetched as? [Any] {
            for element in prior {
                if let d = element as? [String: Any], let id = d["id"] as? String { old[id] = d }
            }
        }
        let shape: Set<String> = ["id", "date", "amount"]
        var seen = Set<String>()
        for element in list {
            guard let d = element as? [String: Any], Set(d.keys) == shape else { return reasonValueBad }
            guard let id = d["id"] as? String, let u = UUID(uuidString: id), u.uuidString == id else { return reasonValueBad }
            guard !seen.contains(id) else { return reasonValueBad }
            seen.insert(id)
            if let o = old[id], LedgerMerge.same(o, d) { continue }
            guard let day = plainNumber(d["date"]), postDateRange.contains(day) else { return reasonValueBad }
            guard let amount = plainNumber(d["amount"]), amount > 0 else { return reasonValueBad }
        }
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
    /// [v25.644 mac4] 固定支出那筆准改的鍵（P2 依剛抓到那筆的類型挑；跟 expensePostKeys 分兩份）
    static let fixedPostKeys: Set<String> = ["title", "note", "amount", "amountHistory", "date", "recurrence", "fixedCategory", "endDate", "endReason"]
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

    /// [v25.644 mac4] 固定支出那筆合併後那一欄的值（P3；sim4 value_ok4）。fetchedHistory＝剛抓到那筆的 amountHistory 原值
    static func fixedPostValueOK(field: String, value: Any?, fetchedHistory: Any?) -> Bool {
        let isNull = value == nil || value is NSNull
        switch field {
        case "title", "note", "amount", "date":
            return postValueOK(key: LedgerMerge.expensesKey, field: field, value: value)
        case "amountHistory":
            return amountHistoryValueReason(value, fetched: fetchedHistory) == nil
        case "recurrence":
            return recurrenceValueReason(value) == nil
        case "fixedCategory":
            guard let s = value as? String, let c = FixedCategory(rawValue: s) else { return false }
            return plainFixedCategories.contains(c)
        case "endDate":
            if isNull { return true }
            guard let n = plainNumber(value) else { return false }
            return postDateRange.contains(n)
        case "endReason":
            if isNull { return true }
            guard let s = value as? String else { return false }
            return FixedEndReason(rawValue: s) != nil
        default:
            return false
        }
    }

    /// [v25.644 mac4] P5、P6 比值：nil（沒有那個鍵）只等於 nil；Bool 只等於 Bool；數字差 ≤ 1e-6；字串逐字；
    /// NSNull 只等於 NSNull；陣列、字典逐層（sim4 post_same）
    static func postSame(_ a: Any?, _ b: Any?) -> Bool {
        guard let x = a, let y = b else { return a == nil && b == nil }
        let xb = isBoolValue(x)
        let yb = isBoolValue(y)
        if xb || yb {
            guard xb && yb, let p = x as? Bool, let q = y as? Bool else { return false }
            return p == q
        }
        if let p = numberValue(x), let q = numberValue(y) {
            return Swift.abs(p - q) <= 1e-6
        }
        if let p = x as? [Any], let q = y as? [Any] {
            guard p.count == q.count else { return false }
            for i in p.indices where !postSame(p[i], q[i]) { return false }
            return true
        }
        if let p = x as? [String: Any], let q = y as? [String: Any] {
            guard Set(p.keys) == Set(q.keys) else { return false }
            for (k, v) in p where !postSame(v, q[k]) { return false }
            return true
        }
        if let p = x as? String, let q = y as? String { return p == q }
        return x is NSNull && y is NSNull
    }

    /// JSONSerialization 的 Bool（CFBoolean）
    private static func isBoolValue(_ v: Any) -> Bool {
        guard let n = v as? NSNumber else { return false }
        return CFGetTypeID(n) == CFBooleanGetTypeID()
    }

    /// 數字（不是 Bool；NaN、無限大也算數字，相減不會 ≤ 1e-6）
    private static func numberValue(_ v: Any) -> Double? {
        guard !(v is String), let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
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
