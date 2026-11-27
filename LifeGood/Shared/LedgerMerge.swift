import Foundation

// [v25.640 mac1] 收支一筆一筆合併（iPhone、iPad、Mac 同一份程式）。
//
// 這個檔同時編進 LifeGood（iOS）和 LifeGoodMac；只用 Foundation，加上同模組的 Expense、Income（Codable）。
// 規格：scratchpad/radar/judge_mac.md §O2-3。Python 參考實作：scratchpad/radar/build/mac1/ledger_sim.py，
// 每個分支有編號，這裡用「sim: threeWay#N」對照；黃金案例在 LedgerMergeGolden.swift（golden_gen.py 產生）。
//
// 只管兩個同步鍵：lifegood_expenses、lifegood_incomes（不新增同步鍵、不改資料格式）。
// 規則重點：
//   - 以 id 為單位、欄位層級合併；只比 knownKeys（＝Expense／Income 的 CodingKeys），不認得的欄位照雲端那份留著。
//   - 改過的贏過刪除；沒有 base（第一次、各種重置之後）一律直接回傳雲端那份＝跟以前一樣。
//   - 這台看不懂的那筆（base 裡解不開、id 重複、沒有 id）：不改、不刪。
// 這個檔不碰 UserDefaults、CloudKit、檔案；純函式，任何執行緒都能叫。

/// 收支兩個鍵的「形狀」：認得哪些欄位、怎麼用這一版的模型正規化（字典 → 模型 → 字典）
enum LedgerSchema: String, CaseIterable {
    case expenses = "lifegood_expenses"
    case incomes = "lifegood_incomes"

    var key: String { rawValue }

    /// 跟 Expense.swift、Income.swift 的 private CodingKeys 逐字相同（ledgerkeys.py 每版檢查）
    var knownKeys: [String] {
        switch self {
        case .expenses: return LedgerMerge.expenseKeys
        case .incomes: return LedgerMerge.incomeKeys
        }
    }

    /// 每一筆用這一版的模型解一次再編一次（補預設值、拿掉不認得的欄位與 enum 值）；解不開的那筆＝nil。
    /// 回傳跟 items 一樣長。
    func normalize(_ items: [Any]) -> [[String: Any]?] {
        switch self {
        case .expenses: return LedgerMerge.normalize(items, as: Expense.self)
        case .incomes: return LedgerMerge.normalize(items, as: Income.self)
        }
    }
}

/// 逐筆容錯解碼用（壞一筆只丟那筆；照 ExpenseStore.FailableDecodable）
private struct LedgerFailable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

enum LedgerMerge {
    // MARK: - 管哪些鍵

    static let expensesKey = "lifegood_expenses"
    static let incomesKey = "lifegood_incomes"
    static let keys: [String] = [expensesKey, incomesKey]

    static func handles(_ key: String) -> Bool {
        LedgerSchema(rawValue: key) != nil
    }

    static func schema(for key: String) -> LedgerSchema? {
        LedgerSchema(rawValue: key)
    }

    /// Expense.swift CodingKeys（照原檔順序）
    static let expenseKeys: [String] = [
        "id", "title", "amount", "date", "expenseType", "variableCategory", "fixedCategory", "recurrence",
        "insuranceSubCategory", "loanSubCategory",
        "linkedInsuranceId", "linkedStockId", "linkedRealEstateId", "linkedVehicleId",
        "vehicleExpenseCategory", "realEstateExpenseCategory", "taxSavingSubCategory",
        "socialSubCategory", "socialRecipient", "taxDeductibleOverride", "note", "currencyCode", "diningMember",
        "loanTotalAmount", "loanYears", "loanRate", "insuranceRate",
        "linkedBankMilestoneId", "linkedBankCurrency", "linkedCreditCardMilestoneId",
        "placeName", "placeAddress", "placeLatitude", "placeLongitude", "photoFileNames", "amountHistory",
        "evKwh", "evFromPct", "evToPct", "evOdometer", "fuelLiters",
        "linkedTripPlanId", "linkedTripStopId",
        "fromQuickRecord",
        "endDate", "endReason",
    ]

    /// Income.swift CodingKeys（照原檔順序）
    static let incomeKeys: [String] = [
        "id", "title", "amount", "date", "category", "period", "isFixedSalary", "note", "linkedStockId",
        "linkedBankMilestoneId", "linkedBankCurrency", "endDate", "endReason",
        "amountHistory",
    ]

    // MARK: - 結果

    struct Conflict: Equatable {
        enum Kind: String {
            /// 同一欄位兩邊都改成不同的值：用這台的（Mac 存之前先問；iPhone 不問）
            case sameField
            /// 這台刪了、另一台改過：留著（改過的贏）
            case deleteVsEdit
            /// 這台改了、另一台刪了：用 base 那筆＋這台的改動加回去（改過的贏）
            case editVsDelete
        }
        let id: String
        /// sameField 才有欄位名；另外兩種是空字串
        let field: String
        let kind: Kind
    }

    struct Result {
        /// 合併後的陣列（JSONSerialization 的值）
        let array: [Any]
        /// equalsRemote 時＝雲端原 bytes；否則＝array 用 JSONSerialization 編出來的
        let data: Data
        /// 合併結果跟雲端那份值相等（這台沒有要加上去的改動）
        let equalsRemote: Bool
        /// 沒有 base（或 base 讀不懂）→ 直接回傳雲端那份
        let usedBase: Bool
        /// 這台新增、加在尾巴的 id
        let added: [String]
        /// 這台改了欄位、套到雲端那筆上的 id
        let changed: [String]
        /// 這台刪掉、雲端那筆也沒被改過而刪掉的 id
        let removed: [String]
        /// 這台改了、雲端已經刪掉 → 加回去的 id
        let resurrected: [String]
        /// 這台刪了、雲端改過 → 留著的 id
        let keptDeleted: [String]
        /// base 裡這一版看不懂的 id（不改、不刪）
        let unreadable: [String]
        let conflicts: [Conflict]
    }

    /// selfCheck 的預期：這次寫入打算新增、改、刪哪些 id
    struct Expectation {
        var added: Set<String> = []
        var edited: Set<String> = []
        var removed: Set<String> = []

        init(added: Set<String> = [], edited: Set<String> = [], removed: Set<String> = []) {
            self.added = added
            self.edited = edited
            self.removed = removed
        }
    }

    // MARK: - 三方合併

    /// base＝這台上次跟雲端對齊的那一份；local＝這台現在的那一份；remote＝雲端現在的那一份。
    /// local 或 remote 不是 JSON 陣列 → nil（呼叫端退回以前的行為，Mac 一律不寫）。
    static func threeWay(_ schema: LedgerSchema, base: Data?, local: Data, remote: Data) -> Result? {
        guard let remoteArr = parseArray(remote) else { return nil }        // sim: threeWay#0
        guard let localArr = parseArray(local) else { return nil }          // sim: threeWay#0
        guard let baseData = base, let baseArr = parseArray(baseData) else {
            // sim: threeWay#1 沒有 base → 雲端那份原樣（＝以前的行為）
            return Result(array: remoteArr, data: remote, equalsRemote: true, usedBase: false,
                          added: [], changed: [], removed: [], resurrected: [], keptDeleted: [],
                          unreadable: [], conflicts: [])
        }

        let known = schema.knownKeys
        let baseIdx = index(baseArr)
        let localIdx = index(localArr)
        let remoteIdx = index(remoteArr)
        let baseNorm = schema.normalize(baseArr)
        let localNorm = schema.normalize(localArr)
        let remoteNorm = schema.normalize(remoteArr)

        var out: [Any] = remoteArr
        var removeAt = Set<Int>()
        var appended: [Any] = []
        var added: [String] = []
        var changed: [String] = []
        var removed: [String] = []
        var resurrected: [String] = []
        var keptDeleted: [String] = []
        var unreadable: [String] = []
        var conflicts: [Conflict] = []

        // A. 走 local（照順序）：新增、改
        for (li, element) in localArr.enumerated() {
            guard let lRaw = element as? [String: Any], let id = lRaw["id"] as? String else {
                continue                                                     // sim: threeWay#2 沒有 id：不管
            }
            if localIdx.dup.contains(id) {
                // sim: threeWay#3 local 裡 id 重複：base、雲端都沒有＝這台新加的，每一份都加；否則不碰
                if baseIdx.pos[id] == nil && !baseIdx.dup.contains(id)
                    && remoteIdx.pos[id] == nil && !remoteIdx.dup.contains(id) {
                    appended.append(lRaw)
                    if !added.contains(id) { added.append(id) }
                }
                continue
            }
            let lN = localNorm[li] ?? lRaw
            if baseIdx.dup.contains(id) {
                if !unreadable.contains(id) { unreadable.append(id) }      // sim: threeWay#4 base 裡 id 重複
                continue
            }
            if let bi = baseIdx.pos[id] {
                guard let bN = baseNorm[bi] else {
                    if !unreadable.contains(id) { unreadable.append(id) }  // sim: threeWay#5 base 那筆看不懂
                    continue
                }
                let fields = known.filter { k in !same(bN[k], lN[k]) }
                if fields.isEmpty { continue }                               // sim: threeWay#6 這台沒改
                if remoteIdx.dup.contains(id) { continue }                   // sim: threeWay#9 雲端 id 重複：不碰
                if let ri = remoteIdx.pos[id], var rD = remoteArr[ri] as? [String: Any] {
                    let rN = remoteNorm[ri]
                    var touched = false
                    for k in fields {
                        let current: Any?
                        if let rn = rN { current = rn[k] } else { current = rD[k] }
                        if !same(current, bN[k]) && !same(current, lN[k]) {
                            conflicts.append(Conflict(id: id, field: k, kind: .sameField))   // sim: threeWay#7
                        }
                        if !same(rD[k], lN[k]) { touched = true }
                        if let v = lN[k] { rD[k] = v } else { rD.removeValue(forKey: k) }   // sim: threeWay#8
                    }
                    if touched {
                        out[ri] = rD
                        changed.append(id)
                    }
                } else {
                    // sim: threeWay#10 雲端刪了、這台改了 → base 那筆（含不認得的欄位）＋改動加回尾巴
                    var d = (baseArr[bi] as? [String: Any]) ?? bN
                    for k in fields {
                        if let v = lN[k] { d[k] = v } else { d.removeValue(forKey: k) }
                    }
                    appended.append(d)
                    resurrected.append(id)
                    conflicts.append(Conflict(id: id, field: "", kind: .editVsDelete))
                }
            } else if remoteIdx.dup.contains(id) {
                continue                                                     // sim: threeWay#9
            } else if let ri = remoteIdx.pos[id], var rD = remoteArr[ri] as? [String: Any] {
                // sim: threeWay#11 兩邊都新增同一個 id：當成改，不一樣的欄位用這台的、記衝突
                let rN = remoteNorm[ri]
                var touched = false
                for k in known {
                    let current: Any?
                    if let rn = rN { current = rn[k] } else { current = rD[k] }
                    if same(current, lN[k]) { continue }
                    conflicts.append(Conflict(id: id, field: k, kind: .sameField))
                    if !same(rD[k], lN[k]) { touched = true }
                    if let v = lN[k] { rD[k] = v } else { rD.removeValue(forKey: k) }
                }
                if touched {
                    out[ri] = rD
                    changed.append(id)
                }
            } else {
                appended.append(lRaw)                                        // sim: threeWay#12 新增
                added.append(id)
            }
        }

        // B. 走 base：這台刪掉的
        for (bi, element) in baseArr.enumerated() {
            guard let bRaw = element as? [String: Any], let id = bRaw["id"] as? String else { continue }
            if baseIdx.dup.contains(id) { continue }
            if localIdx.pos[id] != nil || localIdx.dup.contains(id) { continue }
            guard let bN = baseNorm[bi] else {
                if !unreadable.contains(id) { unreadable.append(id) }      // sim: threeWay#13 看不懂的不刪
                continue
            }
            if remoteIdx.dup.contains(id) { continue }                       // sim: threeWay#15 雲端 id 重複：不碰
            guard let ri = remoteIdx.pos[id] else { continue }               // sim: threeWay#14 雲端也沒了
            if let rN = remoteNorm[ri], known.allSatisfy({ k in same(bN[k], rN[k]) }) {
                removeAt.insert(ri)                                          // sim: threeWay#16 刪
                removed.append(id)
            } else {
                keptDeleted.append(id)                                       // sim: threeWay#17 雲端改過 → 留著
                conflicts.append(Conflict(id: id, field: "", kind: .deleteVsEdit))
            }
        }

        // C. 組合：雲端的順序（拿掉刪的）＋尾巴新增的
        var result: [Any] = []
        result.reserveCapacity(out.count + appended.count)
        for (i, element) in out.enumerated() where !removeAt.contains(i) {
            result.append(element)
        }
        result.append(contentsOf: appended)

        let equal = removeAt.isEmpty && appended.isEmpty && changed.isEmpty
            && NSArray(array: result).isEqual(to: remoteArr)
        let data: Data
        if equal {
            data = remote                                                    // sim: threeWay#18 值一樣＝原 bytes
        } else {
            guard JSONSerialization.isValidJSONObject(result),
                  let encoded = try? JSONSerialization.data(withJSONObject: result, options: []) else { return nil }
            data = encoded
        }
        return Result(array: result, data: data, equalsRemote: equal, usedBase: true,
                      added: added, changed: changed, removed: removed, resurrected: resurrected,
                      keptDeleted: keptDeleted, unreadable: unreadable, conflicts: conflicts)
    }

    // MARK: - 這筆能不能在這一版改

    /// 原字典每個鍵都在正規化後的結果裡、值相等。失敗＝那筆有這一版不認得的欄位或 enum 值（Mac 鎖成只能看）
    static func editable(_ schema: LedgerSchema, raw: [String: Any]) -> Bool {
        let normalized = schema.normalize([raw])
        guard let first = normalized.first, let n = first else { return false }
        for (k, v) in raw {
            guard let nv = n[k], same(v, nv) else { return false }
        }
        return true
    }

    // MARK: - 寫之前的自我檢查（Mac 一定要過才寫）

    /// 回傳問題清單；空的＝通過。
    /// ① 寫出去的解得開 ② 筆數＝雲端 − 刪 ＋ 加 ＋ 加回 ③ 雲端每個 id（這次刪的除外）都在
    /// ④ 這次動到的 id 都在預期裡 ⑤ 沒動到的那幾筆原字典跟雲端一樣 ⑥ 動到的那幾筆用這一版解得開
    static func selfCheck(_ schema: LedgerSchema, remote: Data, result: Result, expect: Expectation) -> [String] {
        var problems: [String] = []
        guard let remoteArr = parseArray(remote) else { return ["雲端那份不是陣列"] }
        guard let outArr = parseArray(result.data) else { return ["寫出去的那份解不開"] }      // ①
        let expectedCount = remoteArr.count - result.removed.count + result.added.count + result.resurrected.count
        if outArr.count != expectedCount {                                                       // ②
            problems.append("筆數不對：雲端 \(remoteArr.count)、結果 \(outArr.count)、應該 \(expectedCount)")
        }
        let remoteIdx = index(remoteArr)
        let outIdx = index(outArr)
        let removedSet = Set(result.removed)
        for id in remoteIdx.pos.keys where !removedSet.contains(id) && outIdx.pos[id] == nil {   // ③
            problems.append("雲端那筆不見了：\(id)")
        }
        for id in result.removed where !expect.removed.contains(id) {                           // ④
            problems.append("刪了沒打算刪的：\(id)")
        }
        for id in result.added where !expect.added.contains(id) {
            problems.append("加了沒打算加的：\(id)")
        }
        for id in result.resurrected where !expect.edited.contains(id) {
            problems.append("加回了沒打算改的：\(id)")
        }
        for id in result.changed where !expect.edited.contains(id) && !expect.added.contains(id) {
            problems.append("改了沒打算改的：\(id)")
        }
        // ⑤ 結果的前段＝雲端（拿掉刪的那幾格）照順序；沒動到的要一模一樣
        let changedSet = Set(result.changed)
        var kept: [Any] = []
        for element in remoteArr {
            if let d = element as? [String: Any], let id = d["id"] as? String,
               remoteIdx.dup.contains(id) == false, removedSet.contains(id) {
                continue
            }
            kept.append(element)
        }
        if outArr.count >= kept.count {
            for (i, element) in kept.enumerated() {
                if let d = element as? [String: Any], let id = d["id"] as? String, changedSet.contains(id) {
                    continue
                }
                if !same(element, outArr[i]) {
                    problems.append("沒動到的第 \(i + 1) 筆變了")
                }
            }
        } else {
            problems.append("結果比雲端留下來的還少")
        }
        // ⑥ 動到的那幾筆解得開
        let touched = Set(result.added).union(result.changed).union(result.resurrected)
        if !touched.isEmpty {
            let outNorm = schema.normalize(outArr)
            for (i, element) in outArr.enumerated() {
                guard let d = element as? [String: Any], let id = d["id"] as? String, touched.contains(id) else { continue }
                if outNorm[i] == nil { problems.append("動到的那筆解不開：\(id)") }
            }
        }
        return problems
    }

    // MARK: - 指紋（日誌、備份檔名用；判斷相等一律直接比 Data）

    /// FNV-1a 64 位元＋長度，跨啟動穩定（不用 hashValue）
    static func fingerprint(_ data: Data) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in data {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        let hex = String(h, radix: 16)
        let pad = String(repeating: "0", count: max(0, 16 - hex.count))
        return pad + hex + "-" + String(data.count)
    }

    // MARK: - 小工具（internal：Mac 的寫入層、黃金案例也用）

    /// JSON 陣列 → [Any]；不是陣列＝nil
    static func parseArray(_ data: Data) -> [Any]? {
        (try? JSONSerialization.jsonObject(with: data, options: [])) as? [Any]
    }

    /// id → 第幾格（只放唯一的）；dup＝出現兩次以上的 id
    static func index(_ arr: [Any]) -> (pos: [String: Int], dup: Set<String>) {
        var pos: [String: Int] = [:]
        var dup = Set<String>()
        for (i, element) in arr.enumerated() {
            guard let d = element as? [String: Any], let id = d["id"] as? String else { continue }
            if pos[id] != nil || dup.contains(id) {
                dup.insert(id)
            } else {
                pos[id] = i
            }
        }
        for id in dup { pos.removeValue(forKey: id) }
        return (pos, dup)
    }

    /// 兩個 JSON 值相等（都沒有＝相等；NSNumber 比數值、NSArray／NSDictionary 逐層比）
    static func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil):
            return true
        case let (x?, y?):
            guard let xo = x as? NSObject, let yo = y as? NSObject else { return false }
            return xo.isEqual(yo)
        default:
            return false
        }
    }

    /// 每一筆用模型 T 解一次再編一次；整批一次做（幾千筆幾十毫秒）
    static func normalize<T: Codable>(_ items: [Any], as type: T.Type) -> [[String: Any]?] {
        let none = [[String: Any]?](repeating: nil, count: items.count)
        guard !items.isEmpty, JSONSerialization.isValidJSONObject(items),
              let data = try? JSONSerialization.data(withJSONObject: items, options: []),
              let decoded = try? JSONDecoder().decode([LedgerFailable<T>].self, from: data),
              decoded.count == items.count else { return none }
        let ok: [T] = decoded.compactMap { f in f.value }
        guard let encoded = try? JSONEncoder().encode(ok),
              let back = (try? JSONSerialization.jsonObject(with: encoded, options: [])) as? [Any],
              back.count == ok.count else { return none }
        var out: [[String: Any]?] = []
        out.reserveCapacity(items.count)
        var j = 0
        for f in decoded {
            if f.value != nil {
                out.append(back[j] as? [String: Any])
                j += 1
            } else {
                out.append(nil)
            }
        }
        return out
    }
}
