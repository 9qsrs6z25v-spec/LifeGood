// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.644 mac4 G3] 貸款的期數（照抄 HouseFacts.swift:19-141、MoneyItemCard.swift:1040-1063（f2c8892）；judge_mac §R7 ⑭、§R17-3）。
// 總設計先放骨架（名字、外部標籤照 judge_mac §R9 名稱表，三組都不准改；內部參數名 now／cal 照 iOS，照抄 token 才比得過）；
// G3 填內容。只 import Foundation。
// • 只抄期數用得到的五支（periodMonths、contractPeriods、firstDue、dueDate、duesOnOrBefore）；monthlyRate、balances 這一版用不到，不抄。
// • 規則一律照 iOS：第一期＝起始日＋1 個週期、第 k 期＝第一期＋(k−1) 個週期（一次加）、扣款日 ≤ 今天才算繳了（startOfDay 比）、
//   季繳先四捨五入月數再 ÷3 截斷、年限最多 100 年、有結束日截到結束日。
// • iOS 的 Recurrence.periodMonths 在 Mac 改名 macPeriodMonths（Mac 不編 HouseFacts.swift，日後一起編也不撞名）。
// • 數字例（假資料）：2023/11/5 起、20 年月繳 NT$28,000、今天 2026/11/25 → 已繳 36／240、還要繳 204 × 28,000。
import Foundation

enum MacLoanMath {
    // 照抄 HouseFacts.swift:20-27（f2c8892）HouseLoanMath.periodMonths
    /// 一個週期幾個月（季繳 3、年繳 12）：月付換算用
    static func periodMonths(_ r: Recurrence) -> Int {
        switch r {
        case .monthly: return 1
        case .quarterly: return 3
        case .yearly: return 12
        }
    }

    // 照抄 HouseFacts.swift:29-38（f2c8892）HouseLoanMath.contractPeriods — sim4: loan4#1
    /// 合約期數：取整跟 Expense.suggestedEndDate 一樣，期數 × 週期才會剛好落在記帳補上的結束日
    static func contractPeriods(years: Double, recurrence r: Recurrence) -> Int {
        // 年限最多算 100 年：輸入框打了一長串數字時 Int(...) 會直接閃退，期數迴圈也會跑不完
        let y: Double = years.isFinite ? min(max(years, 0), 100) : 0
        switch r {
        case .monthly:   return max(1, Int((y * 12).rounded()))
        case .quarterly: return max(1, Int((y * 12).rounded() / 3))
        case .yearly:    return max(1, Int(y.rounded()))
        }
    }

    // 照抄 HouseFacts.swift:40-43（f2c8892）HouseLoanMath.firstDue
    /// 第一期扣款日＝起始日＋1 個週期（貸款規則，同 nextFixedDueDate）
    static func firstDue(start: Date, component: Calendar.Component, step: Int, calendar cal: Calendar) -> Date {
        cal.date(byAdding: component, value: step, to: start) ?? start
    }

    // 照抄 HouseFacts.swift:45-49（f2c8892）HouseLoanMath.dueDate（骨架簽名回 Date?；本體一樣，一定有值）
    /// 第 k 期（從 1 起算）扣款日＝第一期＋(k−1) 個週期，一次加 — sim4: loan4#2
    static func dueDate(_ k: Int, start: Date, component: Calendar.Component, step: Int, calendar cal: Calendar) -> Date? {
        let first = firstDue(start: start, component: component, step: step, calendar: cal)
        return cal.date(byAdding: component, value: step * max(0, k - 1), to: first) ?? first
    }

    // 照抄 HouseFacts.swift:51-69（f2c8892）HouseLoanMath.duesOnOrBefore — sim4: loan4#3
    /// 扣款日 ≤ day 的期數（最多 limit 期）。先用月份差估，再前後微調，不用一期一期數。
    static func duesOnOrBefore(_ day: Date, start: Date, component: Calendar.Component, step: Int,
                               limit: Int, calendar cal: Calendar) -> Int {
        guard limit > 0, step > 0 else { return 0 }
        let target = cal.startOfDay(for: day)
        let first = cal.startOfDay(for: firstDue(start: start, component: component, step: step, calendar: cal))
        guard first <= target else { return 0 }
        func due(_ j: Int) -> Date {   // j 從 0 起算
            cal.startOfDay(for: cal.date(byAdding: component, value: step * j, to: first) ?? first)
        }
        let diff = cal.dateComponents([component], from: first, to: target).value(for: component) ?? 0
        var j = max(0, diff / step)
        var guardSteps = 0
        while j > 0 && due(j) > target && guardSteps < 8 { j -= 1; guardSteps += 1 }
        guardSteps = 0
        while due(j + 1) <= target && guardSteps < 8 { j += 1; guardSteps += 1 }
        return min(limit, j + 1)
    }
}

// 照抄 HouseFacts.swift:108-111（f2c8892）Recurrence.periodMonths（改名 macPeriodMonths，不准用 iOS 的名字）
extension Recurrence {
    /// 一個週期幾個月（季繳 3、年繳 12）
    var macPeriodMonths: Int { MacLoanMath.periodMonths(self) }
}

// 照抄 MoneyItemCard.swift:1040-1053（f2c8892）MoneyLoanSchedule（欄位、isDone、left 逐字；Mac 不需要 Equatable）
/// 貸款繳到第幾期（照抄 MoneyLoanSchedule）
struct MacLoanSchedule {
    /// 已經繳了幾期（真正的期數：季繳一季算一期）
    let elapsed: Int
    let total: Int
    /// 每期金額（季繳就是一季的錢）
    let perPeriod: Double
    /// 每月要繳多少（季繳 ÷ 3、年繳 ÷ 12）
    let monthly: Double

    var isDone: Bool { elapsed >= total }
    /// 還要繳：剩下的期數 × 每期金額（含利息）
    var left: Double { Double(max(0, total - elapsed)) * perPeriod }
}

extension Expense {
    // 照抄 HouseFacts.swift:120-141（f2c8892）Expense.loanPeriods（預設參數拿掉：一律由呼叫端傳 now、calendar）
    /// 貸款扣到第幾期、一共幾期（照抄 Expense.loanPeriods）— sim4: loan4#4
    /// 第一期＝起始日＋1 個週期、扣款日 ≤ 今天才算繳了；一共幾期照年限，有結束日就截到結束日。沒填年限也沒結束日回 nil。
    func macLoanPeriods(asOf now: Date, calendar cal: Calendar) -> (paid: Int, total: Int)? {
        guard isRecurringFixed, fixedCategory == .loan, let rec = recurrence else { return nil }
        let (component, step) = rec.componentValue
        var total: Int
        if let years = loanYears, years > 0 {
            total = MacLoanMath.contractPeriods(years: years, recurrence: rec)
            if let end = endDate {
                total = min(total, MacLoanMath.duesOnOrBefore(end, start: date, component: component, step: step,
                                                              limit: total, calendar: cal))
            }
        } else if let end = endDate {
            total = MacLoanMath.duesOnOrBefore(end, start: date, component: component, step: step,
                                               limit: 1200, calendar: cal)
        } else {
            return nil
        }
        guard total > 0 else { return nil }
        let paid = MacLoanMath.duesOnOrBefore(now, start: date, component: component, step: step,
                                              limit: total, calendar: cal)
        return (paid, total)
    }

    // 照抄 MoneyItemCard.swift:1058-1062（f2c8892）Expense.moneyLoanSchedule（預設參數拿掉）
    /// 貸款繳到第幾期。不是貸款、或沒填年限也沒結束日是 nil — sim4: loan4#4
    func macLoanSchedule(now: Date, calendar cal: Calendar) -> MacLoanSchedule? {
        guard let rec = recurrence, let p = macLoanPeriods(asOf: now, calendar: cal) else { return nil }
        let months = Double(max(1, rec.macPeriodMonths))
        return MacLoanSchedule(elapsed: p.paid, total: p.total, perPeriod: amount, monthly: amount / months)
    }
}
