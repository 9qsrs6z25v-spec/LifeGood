// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.646 mac6 G2] 誰還欠我的唯讀精簡版（judge_mac.md §T3-2）：分帳包（lifegood_expense_splits_v1）解成畫面要的人、頓、還款。
//
// • 只給畫面：寫入層永遠不用這個檔的型別（macwrite 擋 Writer 收 MacOwed*；分帳寫入走 MacSplitPatch 的 raw JSON 局部改）。
// • 名字只在畫面（不進 .help、log、⌘C、日誌、備份檔名）；不存 accountId／depositId 的值，只存兩個 Bool。
// • 每支上一行「照抄 ES:行（258fea0）」；sim 編號 owed6#N（sim_mac6 owed_suite6／owed_text6）。
// • 主控骨架：型別、欄位、簽名定案（跨組名稱表 §T7-6）；`init(data:)`、owedMeals、settledMeals、people、summary、sidebarCount 回空，
//   G2 換內容。狀態那幾個 computed（ES:198-243）與 MacOwedText 的常數主控已照抄填好，G2 逐字核對。

import Foundation

// MARK: - 一筆還款、一個人、一頓

/// 照抄 ES:71-83、:168-194（258fea0）SplitRepayment：id 必填、date 讀不到＝distantPast（留著）、amount 讀不到 0
struct MacOwedRepay: Equatable {
    let id: UUID
    let date: Date
    let amount: Double
    /// 撤銷（〔改成還沒還〕）
    let removedAt: Date?
    /// accountId 解得出 UUID（照 iPhone：有帳戶名的那種還款）
    let account: Bool
    /// accountId 或 depositId 鍵在（值是什麼都算；頁面預先反灰用，比 iPhone 保守）
    let touchesBank: Bool

    /// 照抄 ES:198-200（258fea0）
    var isLive: Bool { removedAt == nil }
}

/// 照抄 ES:49-69、:133-164（258fea0）SplitShare（Mac 不解 isManual、updatedAt：畫面用不到）
struct MacOwedShare: Equatable {
    let id: UUID
    /// 名字快照（只在畫面）
    let name: String
    /// "treat"＝我請、"owe"＝要還我；看不懂的值一律照我請
    let role: String
    let amount: Double
    /// 逐筆解（壞一筆只丟那筆）；鍵不在＝[]
    let repayments: [MacOwedRepay]
    let removedAt: Date?

    // 照抄 ES:202-224（258fea0）
    var liveRepayments: [MacOwedRepay] { repayments.filter { r in r.isLive } }
    var hasRepayment: Bool { repayments.contains { r in r.isLive } }
    var repaidTotal: Double { liveRepayments.reduce(0) { $0 + $1.amount } }
    var isLive: Bool { removedAt == nil || hasRepayment }
    var owes: Bool { role == "owe" }
    var outstanding: Double { owes ? max(0, amount - repaidTotal) : 0 }
    var isSettled: Bool { owes && hasRepayment && outstanding < 0.5 }
    /// 最近一筆還沒撤銷的還款（日期新的；一樣新取後面那筆）
    var lastRepayment: MacOwedRepay? {
        var best: MacOwedRepay? = nil
        for r in liveRepayments {
            if let b = best, b.date > r.date { continue }
            best = r
        }
        return best
    }
}

/// 照抄 ES:34-46、:106-131（258fea0）ExpenseSplit（id＝Expense.id）
struct MacOwedSplit: Equatable {
    let id: UUID
    let baseAmount: Double
    let updatedAt: Date?
    let deletedAt: Date?
    let shares: [MacOwedShare]

    // 照抄 ES:229-236（258fea0）
    var liveShares: [MacOwedShare] {
        guard deletedAt == nil else { return [] }
        return shares.filter { s in s.isLive }
    }
    var owedTotal: Double { liveShares.filter { s in s.owes }.reduce(0) { $0 + $1.amount } }
    var treatTotal: Double { liveShares.filter { s in !s.owes }.reduce(0) { $0 + $1.amount } }
}

// MARK: - 誰還欠我：一人一頓、一個人、最上面那一列

/// 照抄 ES:700-716（258fea0）SplitOwedMeal；Mac 多帶給按鈕預判的四個欄位
struct MacOwedMeal: Identifiable, Equatable {
    let expenseID: UUID
    let shareID: UUID
    /// 只在畫面
    let name: String
    /// 吃飯那天（Expense.date）
    let date: Date
    /// 列上的字（店名；沒打名字用分類）
    let title: String
    /// 還沒還：還欠多少；還清了：還了多少
    let amount: Double
    /// 還沒還：等了幾天；還清了：隔了幾天才還
    let days: Int
    let repaidDate: Date?
    /// 最後一筆還款有帳戶（畫面寫「帳戶」，不讀存摺包）
    let account: Bool
    /// 那個人的 lastRepayment.id（〔改成還沒還〕的 ref）
    let lastRepaymentID: UUID?
    /// lastRepayment 有 accountId 或 depositId 鍵（預先反灰 deposit）
    let lastTouchesBank: Bool
    /// share.removedAt != nil（預先反灰 share_removed）
    let shareRemoved: Bool
    /// 有活的還款但 outstanding ≥ 0.5（預先反灰 partial）
    let partial: Bool

    /// 照抄 ES:715（258fea0）
    var id: String { expenseID.uuidString + "|" + shareID.uuidString }
}

/// 照抄 ES:719-726（258fea0）SplitOwedPerson（照名字原字串分組）
struct MacOwedPerson: Identifiable, Equatable {
    let name: String
    let total: Double
    let maxDays: Int
    let meals: [MacOwedMeal]

    var id: String { name }
}

/// 照抄 ES:728-738（258fea0）SplitOwedSummary
struct MacOwedSummary: Equatable {
    var people: Int = 0
    var total: Double = 0
    var meals: Int = 0
    /// 等了超過 30 天的筆數
    var lateCount: Int = 0
    var maxDays: Int = 0

    /// 入口要不要出現（還沒還的總額 ≥ 0.5）
    var showsEntry: Bool { total >= 0.5 }
}

// MARK: - 讀（畫面只問這個）

/// 照抄 ES:556-580（258fea0）ExpenseSplitIndex；寫入層永遠不用這個型別
struct MacOwedBook: Equatable {
    static let empty = MacOwedBook(data: nil)

    /// 只放 deletedAt == nil && !liveShares.isEmpty（同 id 留 updatedAt 新的、一樣新留先出現的）
    let byID: [UUID: MacOwedSplit]

    /// 頂層不是物件或 splits 不是陣列＝空（只給畫面）。主控骨架：一律空（G2 換內容，sim6: owed6#1～）
    init(data: Data?) {
        byID = [:]
    }

    var isEmpty: Bool { byID.isEmpty }

    /// 照抄 ES:577-580（258fea0）：變動支出才算分帳
    func split(for e: Expense) -> MacOwedSplit? {
        guard e.expenseType == .variable else { return nil }
        return byID[e.id]
    }

    /// 照抄 ES:620-633（258fea0）還沒還（一人一頓一列）。主控骨架：空
    func owedMeals(expenses: [Expense], now: Date, calendar: Calendar) -> [MacOwedMeal] {
        []
    }

    /// 照抄 ES:636-652（258fea0）最近 days 天內還清的。主控骨架：空
    func settledMeals(expenses: [Expense], now: Date, calendar: Calendar, days: Int = 90) -> [MacOwedMeal] {
        []
    }

    /// 照抄 ES:655-672（258fea0）依人分組。主控骨架：空
    static func people(_ meals: [MacOwedMeal]) -> [MacOwedPerson] {
        []
    }

    /// 照抄 ES:675-683（258fea0）最上面那一列。主控骨架：全 0
    func summary(expenses: [Expense], now: Date, calendar: Calendar) -> MacOwedSummary {
        MacOwedSummary()
    }

    /// 側欄用（Mac 自己的）：還沒還的人數（名字去重）、showsEntry；跟日子無關。主控骨架：(0, false)
    func sidebarCount(expenses: [Expense]) -> (people: Int, shows: Bool) {
        (0, false)
    }
}

// MARK: - 畫面上的字（照抄 ES:1171-1385（258fea0）ExpenseSplitText；只抄要用的）

enum MacOwedText {
    /// 照抄 ES:1173（258fea0）
    static let lateDays = 30
    /// 照抄 ES:1194（258fea0）
    static let undoCashTitle = "改成還沒還？"
    /// 照抄 ES:1202（258fea0）
    static let owedEmpty = "都還清了"
    /// 照抄 ES:1203（258fea0）
    static let owedSettledEmpty = "最近 90 天沒有還清的"
    /// 照抄 ES:1207（258fea0）
    static let repayCash = "現金（不記到存摺）"

    /// 照抄 ES:1217-1227（258fea0）「NT$1,500」：四捨五入到元（.5 進位）、千分位。主控骨架：空字（G2 照抄）
    static func ntd(_ v: Double) -> String { "" }

    /// 照抄 ES:1230-1233（258fea0）「11/20」。主控骨架：空字
    static func md(_ d: Date, _ cal: Calendar) -> String { "" }

    /// 照抄 ES:1236-1239（258fea0）「2026/11/22」。主控骨架：空字
    static func ymd(_ d: Date, _ cal: Calendar) -> String { "" }

    /// 照抄 ES:1242-1246（258fea0）兩天差幾天（各自的 startOfDay；負的算 0）。主控骨架：0
    static func daysBetween(_ from: Date, _ to: Date, calendar: Calendar) -> Int { 0 }

    /// 照抄 ES:1249-1252（258fea0）名稱（去空白），空的用分類（`.other` 這個 case，不寫字面值）。主控骨架：空字
    static func mealTitle(_ e: Expense) -> String { "" }

    /// 照抄 ES:1297-1299（258fea0）「已還 11/21・現金 ✓」；accountName 由呼叫端給 account ? "帳戶" : nil。主控骨架：空字
    static func paidLine(date: Date, accountName: String?, calendar: Calendar) -> String { "" }

    /// 照抄 ES:1302-1308（258fea0）詳情欄那一列右邊。主控骨架：空字
    static func detailShare(_ s: MacOwedShare, accountName: String?, calendar: Calendar) -> String { "" }

    /// 照抄 ES:1311-1322（258fea0）「這頓算你的 NT$750（自己 NT$375＋請客 NT$375）」。主控骨架：空字
    static func detailOwn(_ split: MacOwedSplit, amount: Double) -> String { "" }

    /// 照抄 ES:1325-1327（258fea0），Mac 字尾改「，請在 iPhone 重新分」。主控骨架：空字
    static func amountChanged(base: Double, now: Double) -> String { "" }

    /// 照抄 ES:1330（258fea0）「王小明 還了 NT$375」（只在畫面）。主控骨架：空字
    static func repayTitle(name: String, amount: Double) -> String { "" }

    /// 照抄 ES:1333-1335（258fea0）「2026/11/22（今天）」。主控骨架：空字
    static func repayDate(_ d: Date, now: Date, calendar: Calendar) -> String { "" }

    /// 照抄 ES:1343-1346（258fea0）「記好了：王小明 已還（現金）」（只在狀態膠囊）。主控骨架：空字
    static func repayDone(name: String, accountName: String?, amount: Double) -> String { "" }

    /// 照抄 ES:1364-1366（258fea0）「有 1 筆等了 35 天」（沒有超過 30 天的＝nil）。主控骨架：nil
    static func owedLate(_ s: MacOwedSummary) -> String? { nil }

    /// 照抄 ES:1369-1372（258fea0）「NT$375（1 頓・等了 35 天）」。主控骨架：空字
    static func owedPersonValue(_ p: MacOwedPerson) -> String { "" }
}
