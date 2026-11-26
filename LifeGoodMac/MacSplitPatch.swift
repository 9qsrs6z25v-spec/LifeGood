// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.646 mac6 G1] 分帳寫入的動作、守門、局部改、自我檢查、黃金（judge_mac.md §T4-1、§T4-3、§T4-4、§T4-6、§T4-7）。
//
// • 只放字串、數字、字典（JSONSerialization 解開的那種）；不准任何 MacOwed*（MacOwedMealRef 除外，定義在這裡）、MacSplitLite 型別、
//   JSONEncoder、purged(、對 "updatedAt" 的寫入、linkedExpenseId、BankDeposit、存摺包、名字欄位。
// • Mac 寫的還款只有三個鍵 {id, date, amount}；撤銷只加 removedAt；不動任何 updatedAt、不清墓碑（30 天前的留給 iPhone 清）。
// • 原因字（§T4-6）主控已填好：不寫第三人稱代名詞、不寫那兩個禁字，用「這位」「這頓」「這筆」。
// • 主控骨架：型別、原因字、`MacSplitGolden.Report(passed: 0, total: 0)`（allPassed＝false → C0 時兩個動作一律鎖）；G1 換內容。

import Foundation

// MARK: - 頁面給寫入層的那一頓（只有 id 與數字；名字不進來）

/// 頁面打開表單、按〔改成還沒還〕那一刻的那一頓、那一位
struct MacOwedMealRef: Hashable {
    let expenseID: UUID
    let shareID: UUID
    /// 〔改成還沒還〕要撤的那筆（頁面看到的 lastRepayment）；〔已還〕＝nil
    let repaymentID: UUID?
    /// 頁面看到的金額（〔已還〕＝outstanding；〔改成還沒還〕＝那筆的 amount）
    let expected: Double
}

// MARK: - 動作、結果、來源

enum MacSplitAction {
    /// 〔記下來〕：repayment＝["id": 大寫 UUID 字串, "date": 整數秒 Double, "amount": Double]
    case repay(expenseID: String, shareID: String, repayment: [String: Any], expected: Double)
    /// 〔改成還沒還〕：repaymentID nil＝那個人的 lastRepayment（ES:1071-1079）；at＝整數秒 Double；fromPage＝要求是 lastRepayment
    case unrepay(expenseID: String, shareID: String, repaymentID: String?, at: Double, fromPage: Bool)
}

enum MacSplitGateResult {
    case go
    /// 不用寫（原因字 key）
    case done(String)
    /// 鎖住（原因字 key）
    case locked(String)
}

/// 誰叫的（MacWritePurpose 不加 case）
enum MacSplitPurpose {
    case page, undo, redo, restore(String), revert(String)
}

// MARK: - 純函式（gate／apply／selfCheck／postCheck：G1）

enum MacSplitPatch {
    /// §T4-6 原因字（key → 字）
    static let reasons: [String: String] = [
        "page_only": "這一版電腦只能看",
        "split_shape": "分帳那包看不懂（可能是較新的 iPhone 版記的），請先更新電腦版",
        "split_dup": "這頓的分帳資料有重複，請在 iPhone 處理",
        "split_gone": "這頓的分帳在 iPhone 改過了，請按 ⌘R 再看一次",
        "expense_gone": "這筆支出在另一台刪掉了",
        "not_variable": "這筆已經不是變動支出，請在 iPhone 處理",
        "share_gone": "這位已經不在這頓的名單裡（iPhone 剛改過）",
        "not_owe": "這位是我請，不用還",
        "already_settled": "iPhone 剛標過已還，這次不用再標",
        "partial": "這位已經還過一部分，請在 iPhone 處理",
        "amount_moved": "iPhone 剛改過這位的份，請再看一次",
        "date_future": "日期不能選今天以後",
        "already_undone": "iPhone 剛改成還沒還了",
        "rep_gone": "這筆還款在 iPhone 改過了，請按 ⌘R 再看一次",
        "not_last": "只能把最近一筆還款改成還沒還（跟 iPhone 一樣）",
        "deposit": "這筆還款有記到存摺，請在 iPhone 改成還沒還（iPhone 會問存摺那筆要不要一起刪）",
        "share_removed": "這位已經從這頓拿掉了，改成還沒還請在 iPhone 做",
        "split_golden": "分帳自我檢查沒全過，這台 Mac 先不能標已還",
        "post_check": "存之前的檢查沒過（分帳那包），這次沒有寫",
        "write_off": "要在電腦標已還，先到資料來源頁打開允許這台 Mac 修改",
        "snapshot": "iCloud 讀完才能標已還",
        "offline": "離線中",
    ]

    /// 原因字；不認得的 key 寫一句通用的（不帶名字、金額）
    static func reasonText(_ key: String) -> String {
        reasons[key] ?? "這次先不寫，請按 ⌘R 再看一次"
    }

    /// amount_moved 帶兩個金額（不帶名字）：「iPhone 剛把這位的份從 NT$300 改成 NT$375，請再看一次」
    static func amountMovedText(from before: Double, to after: Double) -> String {
        "iPhone 剛把這位的份從 \(ntd(before)) 改成 \(ntd(after))，請再看一次"
    }

    /// 「NT$1,500」（同 ES:1217-1227 的進位；這檔不准用 MacOwedText，自己一份）
    private static func ntd(_ v: Double) -> String {
        guard v.isFinite, abs(v) < 1e15 else { return "NT$0" }
        let r = Int(abs(v).rounded(.toNearestOrAwayFromZero))
        let digits = String(r)
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return (v < 0 && r > 0 ? "-" : "") + "NT$" + out
    }
}

// MARK: - 分帳黃金（§T4-7；MacJournal init 跑一次；沒全過只鎖分帳兩個動作）

enum MacSplitGolden {
    struct Report {
        let passed: Int
        let total: Int
        var allPassed: Bool { passed == total && total > 0 }
    }

    /// 一案（G1 照 sim_mac6 golden_gen6 產生；欄位 G1 可加）
    struct Case {
        /// 案名（例 "repay_basic"；不准叫 name：這檔不准出現名字欄位）
        let id: String
    }

    /// 主控骨架：0 案（allPassed＝false）
    static let cases: [Case] = []

    /// 主控骨架：Report(passed: 0, total: 0)
    static func run() -> Report {
        Report(passed: 0, total: 0)
    }
}
