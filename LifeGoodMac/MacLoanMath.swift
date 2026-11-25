// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.644 mac4 G3] 貸款的期數（照抄 HouseFacts.swift:19-141、MoneyItemCard.swift:1040-1063（f2c8892）；judge_mac §R7 ⑭、§R17-3）。
// 總設計先放骨架（名字、外部標籤照 judge_mac §R9 名稱表，三組都不准改；內部參數名 now／cal 照 iOS，照抄 token 才比得過）；
// G3 填內容。只 import Foundation。
import Foundation

enum MacLoanMath {
    /// 第 k 期（從 1 起算）扣款日＝第一期＋(k−1) 個週期，一次加 — sim4: loan4#2
    static func dueDate(_ k: Int, start: Date, component: Calendar.Component, step: Int, calendar cal: Calendar) -> Date? { nil }
}

/// 貸款繳到第幾期（照抄 MoneyLoanSchedule）
struct MacLoanSchedule {
    let elapsed: Int
    let total: Int
    let perPeriod: Double
    let monthly: Double

    var isDone: Bool { elapsed >= total }
    var left: Double { Double(max(0, total - elapsed)) * perPeriod }
}

extension Expense {
    /// 貸款扣到第幾期、一共幾期（照抄 Expense.loanPeriods）— sim4: loan4#4
    func macLoanPeriods(asOf now: Date, calendar cal: Calendar) -> (paid: Int, total: Int)? { nil }

    /// 照抄 Expense.moneyLoanSchedule — sim4: loan4#4
    func macLoanSchedule(now: Date, calendar cal: Calendar) -> MacLoanSchedule? { nil }
}
