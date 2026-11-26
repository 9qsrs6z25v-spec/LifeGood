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

    // MARK: 讀值（JSONSerialization 解開的值；照 iPhone JSONDecoder 的 try? 讀法）

    // sim6: split6#1 有限數字（Bool 不算：NSNumber 裡的 CFBoolean 擋掉）
    static func number(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let d = n.doubleValue
        return d.isFinite ? d : nil
    }

    /// UUID 字串 → 大寫正規化（不是 UUID＝nil；iPhone 解不開 id 的那筆會被 lossyArray 丟掉）
    static func canonicalID(_ v: Any?) -> String? {
        guard let s = v as? String, let u = UUID(uuidString: s) else { return nil }
        return u.uuidString
    }

    /// 陣列裡 iPhone 解得開的那幾個（字典、id 是 UUID）
    static func withID(_ list: [Any]) -> [[String: Any]] {
        list.compactMap { x in x as? [String: Any] }.filter { d in canonicalID(d["id"]) != nil }
    }

    /// 那位的還款（repayments 不是陣列＝沒有）
    static func reps(_ share: [String: Any]) -> [[String: Any]] {
        guard let arr = share["repayments"] as? [Any] else { return [] }
        return withID(arr)
    }

    /// 還款活著（removedAt 不是數字＝活的：iPhone try? 讀不到當 nil）
    static func repLive(_ r: [String: Any]) -> Bool {
        number(r["removedAt"]) == nil
    }

    static func liveReps(_ share: [String: Any]) -> [[String: Any]] {
        reps(share).filter { r in repLive(r) }
    }

    static func repaid(_ share: [String: Any]) -> Double {
        var t: Double = 0
        for r in liveReps(share) {
            t += number(r["amount"]) ?? 0
        }
        return t
    }

    /// 看不懂的 role 一律當我請（ES SplitShare.role）
    static func role(_ share: [String: Any]) -> String {
        (share["role"] as? String) ?? "treat"
    }

    static func shareAmount(_ share: [String: Any]) -> Double {
        number(share["amount"]) ?? 0
    }

    static func owes(_ share: [String: Any]) -> Bool {
        role(share) == "owe"
    }

    /// 還欠多少（ES:213）
    static func outstanding(_ share: [String: Any]) -> Double {
        owes(share) ? max(0, shareAmount(share) - repaid(share)) : 0
    }

    static func shareRemoved(_ share: [String: Any]) -> Bool {
        number(share["removedAt"]) != nil
    }

    /// 還在這頓裡（ES:209：沒拿掉，或拿掉了但還有活的還款）
    static func shareLive(_ share: [String: Any]) -> Bool {
        !shareRemoved(share) || !liveReps(share).isEmpty
    }

    /// ES:215
    static func isSettled(_ share: [String: Any]) -> Bool {
        owes(share) && !liveReps(share).isEmpty && outstanding(share) < 0.5
    }

    /// 日期讀不到＝distantPast（比任何日子都早）
    static func repDate(_ r: [String: Any]) -> Double {
        number(r["date"]) ?? -Double.greatestFiniteMagnitude
    }

    /// 最近一筆活的還款（ES:216-224：日期新的；一樣新取後面那筆）
    static func lastRep(_ share: [String: Any]) -> [String: Any]? {
        var best: [String: Any]? = nil
        for r in liveReps(share) {
            if let b = best, repDate(b) > repDate(r) { continue }
            best = r
        }
        return best
    }

    static func shares(_ split: [String: Any]) -> [[String: Any]] {
        guard let arr = split["shares"] as? [Any] else { return [] }
        return withID(arr)
    }

    /// 還在的人（整頓墓碑＝沒有人；ES:228-232）
    static func liveShares(_ split: [String: Any]) -> [[String: Any]] {
        guard number(split["deletedAt"]) == nil else { return [] }
        return shares(split).filter { s in shareLive(s) }
    }

    /// 要還我的加總（已還、沒還都算；ES:234）
    static func owedTotal(_ split: [String: Any]) -> Double {
        var t: Double = 0
        for s in liveShares(split) where owes(s) {
            t += shareAmount(s)
        }
        return t
    }

    /// 陣列裡 id 對上的位置（大寫正規化後比）
    static func indexes(_ list: [Any], id: String) -> [Int] {
        var out: [Int] = []
        for (i, x) in list.enumerated() {
            if let d = x as? [String: Any], canonicalID(d["id"]) == id { out.append(i) }
        }
        return out
    }

    static func uniqueIndex(_ list: [Any], id: String) -> Int? {
        let h = indexes(list, id: id)
        return h.count == 1 ? h[0] : nil
    }

    /// 剛抓到的支出包裡的那筆（第一筆對上的）
    static func expenseItem(_ expenses: [Any], id: String) -> [String: Any]? {
        for x in expenses {
            if let d = x as? [String: Any], canonicalID(d["id"]) == id { return d }
        }
        return nil
    }

    /// 鍵在（null 也算）、卻不是數字
    static func badNumber(_ d: [String: Any], _ key: String) -> Bool {
        d[key] != nil && number(d[key]) == nil
    }

    /// 動作的那一頓、那一位（大寫）
    static func ids(_ action: MacSplitAction) -> (expense: String, share: String) {
        switch action {
        case .repay(let e, let s, _, _):
            return (canonicalID(e) ?? "", canonicalID(s) ?? "")
        case .unrepay(let e, let s, _, _, _):
            return (canonicalID(e) ?? "", canonicalID(s) ?? "")
        }
    }

    // MARK: 找那一頓、那一位

    /// 原陣列裡的那一頓、那一位（位置都是原陣列的 index）
    struct Target {
        let list: [Any]
        let splitAt: Int
        let split: [String: Any]
        let shareList: [Any]
        let shareAt: Int
        let share: [String: Any]
    }

    enum Located {
        case found(Target)
        case locked(String)
    }

    /// 不驗型別、只找唯一的那一頓、那一位（apply、selfCheck、postCheck 用；gate 已經先驗過）
    static func find(_ root: [String: Any], _ action: MacSplitAction) -> Target? {
        let id = ids(action)
        guard let list = root["splits"] as? [Any], let si = uniqueIndex(list, id: id.expense),
              let split = list[si] as? [String: Any], let shareList = split["shares"] as? [Any],
              let hi = uniqueIndex(shareList, id: id.share), let share = shareList[hi] as? [String: Any] else { return nil }
        return Target(list: list, splitAt: si, split: split, shareList: shareList, shareAt: hi, share: share)
    }

    // sim6: split6#2 §T4-3：那頓（重複 split_dup；沒有、墓碑、沒有活的人 split_gone）→ 那筆支出（不在 expense_gone、不是變動
    // not_variable）→ 那位（重複 split_dup；沒有、不 isLive share_gone）；路徑上任一層型別不對 split_shape
    static func locate(_ root: [String: Any], expenseID eid: String, shareID sid: String, expenses: [Any]) -> Located {
        guard let list = root["splits"] as? [Any] else { return .locked("split_shape") }
        let h = indexes(list, id: eid)
        if h.count >= 2 { return .locked("split_dup") }
        guard let si = h.first, let split = list[si] as? [String: Any] else { return .locked("split_gone") }
        if badNumber(split, "deletedAt") { return .locked("split_shape") }
        if number(split["deletedAt"]) != nil { return .locked("split_gone") }
        let rawShares = split["shares"] as? [Any]
        if split["shares"] != nil && rawShares == nil { return .locked("split_shape") }
        let shareList: [Any] = rawShares ?? []
        if shareList.contains(where: { x in !(x is [String: Any]) }) { return .locked("split_shape") }
        if liveShares(split).isEmpty { return .locked("split_gone") }
        guard let e = expenseItem(expenses, id: eid) else { return .locked("expense_gone") }
        guard (e["expenseType"] as? String) == ExpenseType.variable.rawValue else { return .locked("not_variable") }
        let hh = indexes(shareList, id: sid)
        if hh.count >= 2 { return .locked("split_dup") }
        guard let hi = hh.first, let share = shareList[hi] as? [String: Any] else { return .locked("share_gone") }
        if let v = share["repayments"] {
            guard let arr = v as? [Any] else { return .locked("split_shape") }
            for x in arr {
                guard let r = x as? [String: Any], canonicalID(r["id"]) != nil else { return .locked("split_shape") }
                if badNumber(r, "removedAt") || badNumber(r, "date") || badNumber(r, "amount") {
                    return .locked("split_shape")
                }
            }
        }
        if badNumber(share, "amount") || badNumber(share, "removedAt") { return .locked("split_shape") }
        if share["role"] != nil && (share["role"] as? String) == nil { return .locked("split_shape") }
        if !shareLive(share) { return .locked("share_gone") }
        return .found(Target(list: list, splitAt: si, split: split, shareList: shareList, shareAt: hi, share: share))
    }

    // MARK: gate（純函式；在剛重抓的分帳＋支出上算；回原因字 key）

    static func gate(_ root: [String: Any], expenses: [Any], action: MacSplitAction, now: Date,
                     calendar: Calendar = .current) -> MacSplitGateResult {
        let id = ids(action)
        switch locate(root, expenseID: id.expense, shareID: id.share, expenses: expenses) {
        case .locked(let k):
            return .locked(k)
        case .found(let t):
            switch action {
            case .repay(_, _, let rep, let expected):
                return repayGate(t.share, repayment: rep, expected: expected, now: now, calendar: calendar)
            case .unrepay(_, _, let rid, _, let fromPage):
                return unrepayGate(t.share, repaymentID: rid, fromPage: fromPage)
            }
        }
    }

    // sim6: split6#3 〔已還〕r1～r7
    static func repayGate(_ share: [String: Any], repayment rep: [String: Any], expected: Double, now: Date,
                          calendar: Calendar) -> MacSplitGateResult {
        let out = outstanding(share)
        let hasLive = !liveReps(share).isEmpty
        if role(share) != "owe" { return .locked("not_owe") }                    // r1
        if hasLive && out < 0.5 { return .done("already_settled") }              // r2
        if hasLive { return .locked("partial") }                                 // r3
        if abs(out - expected) >= 0.005 { return .locked("amount_moved") }       // r4
        if out < 0.5 { return .locked("not_owe") }                               // r5
        if let rid = canonicalID(rep["id"]), reps(share).contains(where: { r in canonicalID(r["id"]) == rid }) {
            return .done("already_settled")                                      // r6 補回、重按
        }
        guard let d = number(rep["date"]), d <= endOfToday(now, calendar: calendar) else {
            return .locked("date_future")                                        // r7
        }
        return .go
    }

    /// 今天 23:59:59（2001 起算秒數）
    static func endOfToday(_ now: Date, calendar: Calendar) -> Double {
        let start = calendar.startOfDay(for: now)
        let next = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return next.timeIntervalSinceReferenceDate - 1
    }

    // sim6: split6#4 〔改成還沒還〕u1～u5
    static func unrepayGate(_ share: [String: Any], repaymentID rid: String?, fromPage: Bool) -> MacSplitGateResult {
        let picked: [String: Any]
        if let rid {
            let c = canonicalID(rid)
            let found = reps(share).filter { r in c != nil && canonicalID(r["id"]) == c }
            if found.count >= 2 { return .locked("split_dup") }
            guard let f = found.first else { return .locked("rep_gone") }               // u2
            if !repLive(f) { return .done("already_undone") }
            picked = f
        } else {
            guard let last = lastRep(share) else { return .done("already_undone") }     // u1
            picked = last
        }
        if fromPage {
            let lastID = lastRep(share).flatMap { l in canonicalID(l["id"]) }
            if lastID == nil || lastID != canonicalID(picked["id"]) { return .locked("not_last") }   // u3
        }
        if picked["accountId"] != nil || picked["depositId"] != nil { return .locked("deposit") }   // u4（鍵在就算）
        if shareRemoved(share) { return .locked("share_removed") }                                // u5
        return .go
    }

    // MARK: 動作 → 寫什麼

    // sim6: split6#5 Mac 寫的還款只有這 3 個鍵（沒有 accountId、depositId、removedAt）
    static func repayment(id: String, date: Double, amount: Double) -> [String: Any] {
        ["id": id, "date": date, "amount": amount]
    }

    /// 2001 起算的整數秒（iPhone JSONEncoder 預設的 Date；整數 Double 經 JSONSerialization 原值來回）
    static func seconds(_ d: Date) -> Double {
        d.timeIntervalSinceReferenceDate.rounded(.down)
    }

    // sim6: split6#6 gate 放行之後：〔已還〕金額換成剛抓到那位的 outstanding；〔改成還沒還〕nil 換成 lastRepayment 的 id
    static func resolved(_ action: MacSplitAction, in root: [String: Any]) -> MacSplitAction? {
        guard let t = find(root, action) else { return nil }
        switch action {
        case .repay(let e, let s, let rep, let expected):
            let r = repayment(id: (rep["id"] as? String) ?? "", date: number(rep["date"]) ?? 0, amount: outstanding(t.share))
            return .repay(expenseID: e, shareID: s, repayment: r, expected: expected)
        case .unrepay(let e, let s, let rid, let at, let fromPage):
            let pickedID: String?
            if let rid {
                pickedID = canonicalID(rid)
            } else {
                pickedID = lastRep(t.share).flatMap { l in canonicalID(l["id"]) }
            }
            guard let picked = pickedID else { return nil }
            return .unrepay(expenseID: e, shareID: s, repaymentID: picked, at: at, fromPage: fromPage)
        }
    }

    // sim6: split6#7 raw JSON 局部改：只動那一頓、那一位的 repayments 一個元素（不 decode 再 encode、不清墓碑、不動 updatedAt）
    static func apply(_ action: MacSplitAction, to root: [String: Any]) -> [String: Any]? {
        guard let t = find(root, action) else { return nil }
        var list: [Any] = []
        if let v = t.share["repayments"] {
            guard let arr = v as? [Any] else { return nil }
            list = arr
        }
        switch action {
        case .repay(_, _, let rep, _):
            guard let rid = canonicalID(rep["id"]), indexes(list, id: rid).isEmpty else { return nil }
            list.append(rep)
        case .unrepay(_, _, let ridOpt, let at, _):
            guard let rid = ridOpt, let c = canonicalID(rid) else { return nil }
            let h = indexes(list, id: c)
            guard h.count == 1, var r = list[h[0]] as? [String: Any], r["removedAt"] == nil else { return nil }
            r["removedAt"] = at
            list[h[0]] = r
        }
        var share = t.share
        share["repayments"] = list
        var shareList = t.shareList
        shareList[t.shareAt] = share
        var split = t.split
        split["shares"] = shareList
        var splits = t.list
        splits[t.splitAt] = split
        var out = root
        out["splits"] = splits
        guard JSONSerialization.isValidJSONObject(out) else { return nil }
        return out
    }

    // MARK: 自我檢查（結構）、存之前的檢查（語意）

    static func sameExcept(_ a: [String: Any], _ b: [String: Any], _ skip: String) -> Bool {
        let ka = Set(a.keys).subtracting([skip])
        let kb = Set(b.keys).subtracting([skip])
        guard ka == kb else { return false }
        for k in ka where !LedgerMerge.same(a[k], b[k]) { return false }
        return true
    }

    // sim6: split6#8 S1～S7（回不過的代碼；空＝全過）
    static func selfCheck(remote: [String: Any], result: [String: Any], action: MacSplitAction) -> [String] {
        guard sameExcept(remote, result, "splits") else { return ["S1"] }
        guard let t = find(remote, action), let b = result["splits"] as? [Any], b.count == t.list.count else { return ["S2"] }
        for i in t.list.indices where i != t.splitAt {
            if !LedgerMerge.same(t.list[i], b[i]) { return ["S2"] }
        }
        guard let sb = b[t.splitAt] as? [String: Any], sameExcept(t.split, sb, "shares") else { return ["S3"] }
        guard let hb = sb["shares"] as? [Any], hb.count == t.shareList.count else { return ["S4"] }
        for i in t.shareList.indices where i != t.shareAt {
            if !LedgerMerge.same(t.shareList[i], hb[i]) { return ["S4"] }
        }
        guard let pb = hb[t.shareAt] as? [String: Any], sameExcept(t.share, pb, "repayments") else { return ["S5"] }
        let ra: [Any] = (t.share["repayments"] as? [Any]) ?? []
        guard let rb = pb["repayments"] as? [Any], repaymentsOK(action, before: ra, after: rb) else { return ["S6"] }
        guard JSONSerialization.isValidJSONObject(result),
              let data = try? JSONSerialization.data(withJSONObject: result, options: []),
              let back = try? JSONSerialization.jsonObject(with: data, options: []),
              LedgerMerge.same(back, result) else { return ["S7"] }
        return []
    }

    /// S6：〔已還〕多剛好一筆 {id, date, amount}（id 大寫 UUID、以前沒有；date 整數秒；amount 數字）；
    /// 〔改成還沒還〕筆數一樣、只有那一筆多一個 removedAt（以前沒有）
    static func repaymentsOK(_ action: MacSplitAction, before ra: [Any], after rb: [Any]) -> Bool {
        switch action {
        case .repay:
            guard rb.count == ra.count + 1 else { return false }
            for i in ra.indices where !LedgerMerge.same(ra[i], rb[i]) { return false }
            guard let n = rb.last as? [String: Any], Set(n.keys) == Set(["id", "date", "amount"]),
                  let rid = n["id"] as? String, canonicalID(rid) == rid, indexes(ra, id: rid).isEmpty,
                  let d = number(n["date"]), number(n["amount"]) != nil, d == d.rounded(.down) else { return false }
            return true
        case .unrepay(_, _, let ridOpt, _, _):
            guard let rid = ridOpt, let c = canonicalID(rid), rb.count == ra.count else { return false }
            let h = indexes(ra, id: c)
            guard h.count == 1 else { return false }
            let j = h[0]
            for i in ra.indices where i != j && !LedgerMerge.same(ra[i], rb[i]) { return false }
            guard let x = ra[j] as? [String: Any], let y = rb[j] as? [String: Any], x["removedAt"] == nil,
                  Set(y.keys) == Set(x.keys).union(["removedAt"]), sameExcept(x, y, "removedAt"),
                  number(y["removedAt"]) != nil else { return false }
            return true
        }
    }

    // sim6: split6#9 P1～P6（在 result 上用 iPhone 規則重算；nil＝放行，否則 "post_check"）
    static func postCheck(remote: [String: Any], result: [String: Any], expenses: [Any], action: MacSplitAction) -> String? {
        let bad = "post_check"
        guard let t0 = find(remote, action), let t1 = find(result, action) else { return bad }
        let sh0 = t0.share
        let sh1 = t1.share
        // P1 那位的份、這頓的 baseAmount 不變
        if !LedgerMerge.same(sh0["amount"], sh1["amount"]) || !LedgerMerge.same(t0.split["baseAmount"], t1.split["baseAmount"]) {
            return bad
        }
        let reps0 = reps(sh0)
        let reps1 = reps(sh1)
        var plus = 0
        switch action {
        case .repay(_, _, let rep, let expected):
            plus = 1
            let rid = canonicalID(rep["id"])
            let added = reps1.filter { r in rid != nil && canonicalID(r["id"]) == rid }
            guard added.count == 1, let m = number(added[0]["amount"]) else { return bad }
            // P1 金額＝剛抓到的 outstanding＝畫面看到的（±0.005）、≥ 0.5
            if abs(m - outstanding(sh0)) >= 0.000001 || abs(m - expected) >= 0.005 || m < 0.5 { return bad }
            // P2 標完那位還清了
            if !isSettled(sh1) { return bad }
            // P5 不建存摺
            if added[0]["accountId"] != nil || added[0]["depositId"] != nil { return bad }
        case .unrepay(_, _, let rid, _, _):
            let c = rid.flatMap { x in canonicalID(x) }
            let tgt0 = reps0.filter { r in c != nil && canonicalID(r["id"]) == c }
            let tgt1 = reps1.filter { r in c != nil && canonicalID(r["id"]) == c }
            guard tgt0.count == 1, tgt1.count == 1, !repLive(tgt1[0]) else { return bad }
            // P5 被撤那筆本來就沒碰存摺
            if tgt0[0]["accountId"] != nil || tgt0[0]["depositId"] != nil { return bad }
            // P2 別的活還款原樣；一筆都不剩時要還欠 ≥ 0.5
            let live0 = liveReps(sh0).compactMap { r in canonicalID(r["id"]) }.filter { x in x != c }
            let live1 = liveReps(sh1).compactMap { r in canonicalID(r["id"]) }
            if live0 != live1 { return bad }
            if live1.isEmpty && (!owes(sh1) || outstanding(sh1) < 0.5) { return bad }
        }
        // P3 你的份不變：這頓 owedTotal、活的人數前後一樣
        if abs(owedTotal(t0.split) - owedTotal(t1.split)) >= 0.000001 { return bad }
        if liveShares(t0.split).count != liveShares(t1.split).count { return bad }
        // P4 iPhone 解得開：每層解得開的筆數不變（〔已還〕那位多 1 筆）
        guard let l0 = remote["splits"] as? [Any], let l1 = result["splits"] as? [Any] else { return bad }
        if withID(l0).count != withID(l1).count || shares(t0.split).count != shares(t1.split).count { return bad }
        if reps1.count != reps0.count + plus { return bad }
        // P6 那筆支出還在、還是變動（同一次抓到的）
        guard let e = expenseItem(expenses, id: ids(action).expense),
              (e["expenseType"] as? String) == ExpenseType.variable.rawValue else { return bad }
        return nil
    }

    // sim6: split6#10 鎖住時給畫面的字（amount_moved 帶兩個金額、不帶名字）
    static func lockText(_ key: String, root: [String: Any], action: MacSplitAction) -> String {
        if key == "amount_moved", case .repay(_, _, _, let expected) = action, let t = find(root, action) {
            return amountMovedText(from: expected, to: outstanding(t.share))
        }
        return reasonText(key)
    }

    // MARK: 日誌、看門狗

    // sim6: split6#11 itemID＝"<支出UUID>|<那位UUID>"；rawAfter 只有 id、日期、金額（〔改成還沒還〕多 undoneAt）；不帶名字、店名
    static func journalInfo(_ action: MacSplitAction, written: [String: Any]) -> (itemID: String, rawAfter: [String: Any]) {
        let id = ids(action)
        var rid = ""
        var undoneAt: Double? = nil
        switch action {
        case .repay(_, _, let rep, _):
            rid = canonicalID(rep["id"]) ?? ""
        case .unrepay(_, _, let r, let at, _):
            rid = r.flatMap { x in canonicalID(x) } ?? ""
            undoneAt = at
        }
        var date: Double = 0
        var amount: Double = 0
        if let t = find(written, action), let r = reps(t.share).first(where: { x in canonicalID(x["id"]) == rid }) {
            date = number(r["date"]) ?? 0
            amount = number(r["amount"]) ?? 0
        }
        var raw: [String: Any] = ["expenseId": id.expense, "shareId": id.share, "repaymentId": rid, "date": date,
                                  "amount": amount]
        if let undoneAt { raw["undoneAt"] = undoneAt }
        return (id.expense + "|" + id.share, raw)
    }

    /// 一筆分帳日誌的 id、日期、金額
    struct EntryInfo {
        let expenseID: String
        let shareID: String
        let repaymentID: String
        let date: Double
        let amount: Double
    }

    // sim6: split6#13 日誌 rawAfter → id／日期／金額（讀不懂＝nil：不復原、不補回）
    static func entryInfo(_ raw: [String: Any]?) -> EntryInfo? {
        guard let raw, let e = canonicalID(raw["expenseId"]), let s = canonicalID(raw["shareId"]),
              let r = canonicalID(raw["repaymentId"]), let d = number(raw["date"]), let m = number(raw["amount"]) else {
            return nil
        }
        return EntryInfo(expenseID: e, shareID: s, repaymentID: r, date: d, amount: m)
    }

    // sim6: split6#12 看門狗（§T4-5）：現在雲端那份 → "repayMissing"／"unrepayBack"／"repayTwice"／nil。
    // 不提示：那頓刪了、支出刪了或不是變動、那位拿掉了、iPhone 自己撤了電腦那筆、看不懂
    static func watchKey(kind: String, rawAfter: [String: Any]?, splits: Data?, expenses: Data?) -> String? {
        guard let info = entryInfo(rawAfter), let sd = splits, let ed = expenses,
              let root = (try? JSONSerialization.jsonObject(with: sd, options: [])) as? [String: Any],
              let list = root["splits"] as? [Any], let exps = LedgerMerge.parseArray(ed) else { return nil }
        guard let si = uniqueIndex(list, id: info.expenseID), let split = list[si] as? [String: Any],
              number(split["deletedAt"]) == nil else { return nil }
        guard let e = expenseItem(exps, id: info.expenseID),
              (e["expenseType"] as? String) == ExpenseType.variable.rawValue else { return nil }
        let shareList: [Any] = (split["shares"] as? [Any]) ?? []
        guard let hi = uniqueIndex(shareList, id: info.shareID), let share = shareList[hi] as? [String: Any],
              !shareRemoved(share) else { return nil }
        let mine = reps(share).filter { r in canonicalID(r["id"]) == info.repaymentID }
        if kind == "repay" {
            guard let r = mine.first else { return "repayMissing" }
            guard repLive(r) else { return nil }
            let others = liveReps(share).filter { x in canonicalID(x["id"]) != info.repaymentID }
            return others.isEmpty ? nil : "repayTwice"
        }
        if kind == "unrepay", let r = mine.first, repLive(r) { return "unrepayBack" }
        return nil
    }
}

// MARK: - 分帳黃金（§T4-7；MacJournal init 跑一次；沒全過只鎖分帳兩個動作）

enum MacSplitGolden {
    struct Report {
        let passed: Int
        let total: Int
        var allPassed: Bool { passed == total && total > 0 }
    }

    /// 一案（sim_mac6 golden_gen6 產生）。JSON 用單引號寫（跑的時候換成雙引號；資料裡沒有單引號、反斜線）；不放名字
    struct Case {
        /// 案名（例 "repay_basic"；不准叫 name：這檔不准出現名字欄位）
        let id: String
        /// "repay"／"unrepay"
        let kind: String
        /// 〔已還〕新那筆的 id；〔改成還沒還〕要撤的那筆（""＝nil＝lastRepayment）
        let repaymentID: String
        /// 〔已還〕日期；〔改成還沒還〕撤銷時間（2001 起整數秒）
        let at: Double
        let expected: Double
        let fromPage: Bool
        /// "go"／"done:<key>"／"locked:<key>"／"post:<key>"
        let want: String
        /// 雲端分帳那包
        let remote: String
        /// 雲端支出那包
        let expenses: String
        /// want＝go 時寫完那包
        let result: String
    }

    /// 每案都是這一頓、這一位
    static let expenseID = "00000000-0000-0000-0000-000000000001"
    static let shareID = "00000000-0000-0000-0000-00000000000B"

    // sim6: split6#14
    // ---- golden_gen6 begin ----
    // golden_gen6 產生（python3 -I sim_split6.py --gen）：不要手改；sim_mac6 golden_gen6 逐字比
    static let goldenNow: Double = 817366800
    static let cases: [Case] = [
        Case(id: "repay_basic", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817366800, expected: 375, fromPage: false,
             want: "go",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000063','date':817366800.0,'amount':375.0}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}"),
        Case(id: "repay_empty_list", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817366800, expected: 375, fromPage: false,
             want: "go",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':[]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000063','date':817366800.0,'amount':375.0}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}"),
        Case(id: "repay_after_undone", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817366800, expected: 375, fromPage: false,
             want: "go",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000033','date':816915600.0,'amount':375,'removedAt':816915660.0}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000033','date':816915600.0,'amount':375,'removedAt':816915660.0},{'id':'00000000-0000-0000-0000-000000000063','date':817366800.0,'amount':375.0}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}"),
        Case(id: "repay_lowercase_ids", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817366800, expected: 375, fromPage: false,
             want: "go",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'shares':[{'id':'00000000-0000-0000-0000-00000000000b','role':'owe','amount':375,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: "{'splits':[{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'shares':[{'id':'00000000-0000-0000-0000-00000000000b','role':'owe','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000063','date':817366800.0,'amount':375.0}]}]}]}"),
        Case(id: "repay_unknown_keys", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817366800, expected: 375, fromPage: false,
             want: "go",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'zz':[1,2]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}],'yy':{'a':1}}],'xx':'keep'}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'zz':[1,2],'repayments':[{'id':'00000000-0000-0000-0000-000000000063','date':817366800.0,'amount':375.0}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}],'yy':{'a':1}}],'xx':'keep'}"),
        Case(id: "repay_half_amount", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817366800, expected: 375.5, fromPage: false,
             want: "go",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375.5,'updatedAt':100},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375.5,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000063','date':817366800.0,'amount':375.5}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}"),
        Case(id: "repay_today_end", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817401599, expected: 375, fromPage: false,
             want: "go",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000063','date':817401599.0,'amount':375.0}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}"),
        Case(id: "repay_past", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 816915600, expected: 375, fromPage: false,
             want: "go",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000063','date':816915600.0,'amount':375.0}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}"),
        Case(id: "repay_future", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817401600, expected: 375, fromPage: false,
             want: "locked:date_future",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "repay_amount_moved", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817366800, expected: 375, fromPage: false,
             want: "locked:amount_moved",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':400,'updatedAt':100},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "repay_treat", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817366800, expected: 375, fromPage: false,
             want: "locked:not_owe",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'treat','amount':375,'updatedAt':100},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "repay_odd_role", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817366800, expected: 375, fromPage: false,
             want: "locked:not_owe",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'xx','amount':375,'updatedAt':100},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "repay_settled", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817366800, expected: 375, fromPage: false,
             want: "done:already_settled",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000033','date':816915600.0,'amount':375}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "repay_partial", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817366800, expected: 275, fromPage: false,
             want: "locked:partial",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000033','date':816915600.0,'amount':100}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "repay_tiny", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817366800, expected: 0.3, fromPage: false,
             want: "locked:not_owe",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':0.3,'updatedAt':100},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "repay_same_id", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817366800, expected: 375, fromPage: false,
             want: "done:already_settled",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000063','date':816915600.0,'amount':375,'removedAt':816915660.0}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "repay_split_dup", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817366800, expected: 375, fromPage: false,
             want: "locked:split_dup",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "repay_share_dup", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817366800, expected: 375, fromPage: false,
             want: "locked:split_dup",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100},{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "repay_split_missing", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817366800, expected: 375, fromPage: false,
             want: "locked:split_gone",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000004','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "repay_split_deleted", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817366800, expected: 375, fromPage: false,
             want: "locked:split_gone",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}],'deletedAt':200}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "repay_nobody_left", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817366800, expected: 375, fromPage: false,
             want: "locked:split_gone",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'removedAt':200},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100,'removedAt':200}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "repay_expense_gone", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817366800, expected: 375, fromPage: false,
             want: "locked:expense_gone",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "repay_not_variable", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817366800, expected: 375, fromPage: false,
             want: "locked:not_variable",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'固定支出'}]",
             result: ""),
        Case(id: "repay_share_gone", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817366800, expected: 375, fromPage: false,
             want: "locked:share_gone",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000D','role':'owe','amount':375,'updatedAt':100},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "repay_share_removed", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817366800, expected: 375, fromPage: false,
             want: "locked:share_gone",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'removedAt':200},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "repay_reps_not_list", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817366800, expected: 375, fromPage: false,
             want: "locked:split_shape",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':{'id':'00000000-0000-0000-0000-000000000033'}},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "repay_reps_null", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817366800, expected: 375, fromPage: false,
             want: "locked:split_shape",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':null},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "repay_amount_text", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817366800, expected: 375, fromPage: false,
             want: "locked:split_shape",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':'375','updatedAt':100},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "repay_amount_bool", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817366800, expected: 375, fromPage: false,
             want: "locked:split_shape",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':true,'updatedAt':100},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "repay_splits_not_list", kind: "repay", repaymentID: "00000000-0000-0000-0000-000000000063", at: 817366800, expected: 375, fromPage: false,
             want: "locked:split_shape",
             remote: "{'splits':{'id':'00000000-0000-0000-0000-000000000001'}}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "unrepay_last", kind: "unrepay", repaymentID: "", at: 817366800, expected: 0, fromPage: true,
             want: "go",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000033','date':816915600.0,'amount':375}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000033','date':816915600.0,'amount':375,'removedAt':817366800.0}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}"),
        Case(id: "unrepay_given", kind: "unrepay", repaymentID: "00000000-0000-0000-0000-000000000033", at: 817366800, expected: 0, fromPage: true,
             want: "go",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000033','date':816915600.0,'amount':375}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000033','date':816915600.0,'amount':375,'removedAt':817366800.0}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}"),
        Case(id: "unrepay_tie_takes_later", kind: "unrepay", repaymentID: "", at: 817366800, expected: 0, fromPage: true,
             want: "go",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000033','date':816915600.0,'amount':100},{'id':'00000000-0000-0000-0000-000000000034','date':816915600.0,'amount':275}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000033','date':816915600.0,'amount':100},{'id':'00000000-0000-0000-0000-000000000034','date':816915600.0,'amount':275,'removedAt':817366800.0}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}"),
        Case(id: "unrepay_not_last", kind: "unrepay", repaymentID: "00000000-0000-0000-0000-000000000033", at: 817366800, expected: 0, fromPage: true,
             want: "locked:not_last",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000033','date':816915600.0,'amount':100},{'id':'00000000-0000-0000-0000-000000000034','date':816915600.0,'amount':275}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "unrepay_undo_keeps_other", kind: "unrepay", repaymentID: "00000000-0000-0000-0000-000000000033", at: 817366800, expected: 0, fromPage: false,
             want: "go",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000033','date':816915600.0,'amount':100},{'id':'00000000-0000-0000-0000-000000000034','date':816915600.0,'amount':275}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000033','date':816915600.0,'amount':100,'removedAt':817366800.0},{'id':'00000000-0000-0000-0000-000000000034','date':816915600.0,'amount':275}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}"),
        Case(id: "unrepay_already", kind: "unrepay", repaymentID: "00000000-0000-0000-0000-000000000033", at: 817366800, expected: 0, fromPage: true,
             want: "done:already_undone",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000033','date':816915600.0,'amount':375,'removedAt':816915660.0}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "unrepay_none_live", kind: "unrepay", repaymentID: "", at: 817366800, expected: 0, fromPage: true,
             want: "done:already_undone",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000033','date':816915600.0,'amount':375,'removedAt':816915660.0}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "unrepay_rep_gone", kind: "unrepay", repaymentID: "00000000-0000-0000-0000-000000000034", at: 817366800, expected: 0, fromPage: true,
             want: "locked:rep_gone",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000033','date':816915600.0,'amount':375}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "unrepay_account", kind: "unrepay", repaymentID: "00000000-0000-0000-0000-000000000033", at: 817366800, expected: 0, fromPage: true,
             want: "locked:deposit",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000033','date':816915600.0,'amount':375,'accountId':'00000000-0000-0000-0000-000000000050'}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "unrepay_deposit", kind: "unrepay", repaymentID: "00000000-0000-0000-0000-000000000033", at: 817366800, expected: 0, fromPage: true,
             want: "locked:deposit",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000033','date':816915600.0,'amount':375,'depositId':'00000000-0000-0000-0000-00000000005A'}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "unrepay_account_null", kind: "unrepay", repaymentID: "00000000-0000-0000-0000-000000000033", at: 817366800, expected: 0, fromPage: true,
             want: "locked:deposit",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000033','date':816915600.0,'amount':375,'accountId':null}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "unrepay_share_removed", kind: "unrepay", repaymentID: "00000000-0000-0000-0000-000000000033", at: 817366800, expected: 0, fromPage: true,
             want: "locked:share_removed",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000033','date':816915600.0,'amount':375}],'removedAt':200},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "unrepay_treat", kind: "unrepay", repaymentID: "00000000-0000-0000-0000-000000000033", at: 817366800, expected: 0, fromPage: true,
             want: "post:post_check",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'treat','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000033','date':816915600.0,'amount':375}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
        Case(id: "unrepay_removed_null", kind: "unrepay", repaymentID: "00000000-0000-0000-0000-000000000033", at: 817366800, expected: 0, fromPage: true,
             want: "locked:split_shape",
             remote: "{'splits':[{'id':'00000000-0000-0000-0000-000000000003','baseAmount':220,'updatedAt':50,'shares':[{'id':'00000000-0000-0000-0000-00000000001F','role':'owe','amount':110,'updatedAt':100}]},{'id':'00000000-0000-0000-0000-000000000001','baseAmount':1500,'updatedAt':100,'shares':[{'id':'00000000-0000-0000-0000-00000000000B','role':'owe','amount':375,'updatedAt':100,'repayments':[{'id':'00000000-0000-0000-0000-000000000033','date':816915600.0,'amount':375,'removedAt':null}]},{'id':'00000000-0000-0000-0000-00000000000C','role':'treat','amount':300,'updatedAt':100}]}]}",
             expenses: "[{'id':'00000000-0000-0000-0000-000000000001','expenseType':'變動支出'},{'id':'00000000-0000-0000-0000-000000000002','expenseType':'固定支出'},{'id':'00000000-0000-0000-0000-000000000003','expenseType':'變動支出'}]",
             result: ""),
    ]
    // ---- golden_gen6 end ----
    static func run() -> Report {
        var passed = 0
        for c in cases where check(c) {
            passed += 1
        }
        return Report(passed: passed, total: cases.count)
    }

    static func check(_ c: Case) -> Bool {
        guard let root = json(c.remote) as? [String: Any], let expenses = json(c.expenses) as? [Any] else { return false }
        let action: MacSplitAction
        if c.kind == "repay" {
            action = .repay(expenseID: expenseID, shareID: shareID,
                            repayment: MacSplitPatch.repayment(id: c.repaymentID, date: c.at, amount: c.expected),
                            expected: c.expected)
        } else {
            action = .unrepay(expenseID: expenseID, shareID: shareID, repaymentID: c.repaymentID.isEmpty ? nil : c.repaymentID,
                              at: c.at, fromPage: c.fromPage)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? TimeZone(secondsFromGMT: 8 * 3600) ?? TimeZone.current
        let now = Date(timeIntervalSinceReferenceDate: goldenNow)
        let got = pipeline(root, expenses: expenses, action: action, now: now, calendar: calendar)
        guard got.key == c.want else { return false }
        guard c.want == "go" else { return true }
        guard let want = json(c.result), let result = got.result else { return false }
        return LedgerMerge.same(result, want)
    }

    /// 單引號 JSON → 值
    static func json(_ text: String) -> Any? {
        guard !text.isEmpty, let data = text.replacingOccurrences(of: "'", with: "\"").data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [])
    }

    /// saveSplit ③～⑥ 不碰 iCloud 的那一段（gate → resolved → apply → selfCheck → postCheck）
    static func pipeline(_ root: [String: Any], expenses: [Any], action: MacSplitAction, now: Date,
                         calendar: Calendar) -> (key: String, result: [String: Any]?) {
        switch MacSplitPatch.gate(root, expenses: expenses, action: action, now: now, calendar: calendar) {
        case .go:
            break
        case .done(let k):
            return ("done:" + k, nil)
        case .locked(let k):
            return ("locked:" + k, nil)
        }
        guard let act = MacSplitPatch.resolved(action, in: root),
              let result = MacSplitPatch.apply(act, to: root) else { return ("cannot", nil) }
        if !MacSplitPatch.selfCheck(remote: root, result: result, action: act).isEmpty { return ("self", nil) }
        if let k = MacSplitPatch.postCheck(remote: root, result: result, expenses: expenses, action: act) {
            return ("post:" + k, nil)
        }
        return ("go", result)
    }
}
