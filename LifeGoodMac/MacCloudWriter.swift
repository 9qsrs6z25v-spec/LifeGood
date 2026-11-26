// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.640 mac1] 整個 Mac 唯一會寫 iCloud 的地方（judge_mac §O2-4；sim：ledger_sim.py Mac.save_fetch／save_write）。
// 每次存（最多 3 次嘗試）：
//   ① 寫入開關＋黃金案例全過、鍵在白名單 ② 重抓這個鍵（記錄或 zone 不存在 → 不建）
//   ③ 把動作套在 base（開表單那時的原字典陣列）上得到 local ④ LedgerMerge.threeWay ⑤ 那筆在另一台刪了 → 問
//   ⑥ 同一欄位兩邊都改 → 先問 ⑦ 跟雲端一樣 → 不寫 ⑧ LedgerMerge.selfCheck ⑨ 刪除：重抓分帳、細項確認沒有這筆的記錄
//   ⑩ 寫前備份雲端那份 ⑪ 拿剛抓到的那個 CKRecord，只設 payload／updatedAt／keyName，.ifServerRecordUnchanged
//   ⑫ 讀回 updatedAt ⑬ 記日誌
// 只收「動作」（新增一筆原字典、改幾個欄位、刪一筆），不收模型陣列、不收 Lite 型別。
// [v25.641 mac2 G1] S1：改一筆時 ② 重抓之後、③ 套動作之前，用剛抓到的那筆再判斷一次（gate；每一輪重試、〔用 iPhone 的〕重套之後都再跑）。
// S5：〔用 iPhone 的〕成組換（fieldGroups：結束日、結束原因）。sim_mac2.py save2／theirs_fields。
// [v25.642 mac3 G1] judge_mac §Q6 W-1～W-5（sim_mac3.py save3）：② 支出那包同一次多抓分帳、細項（MacFreshLinks，只放 bytes）；
// 有 bytes 卻解不開 → 不存；gate 多傳剛抓到的分帳細項；那筆不在了又有分帳或細項紀錄 → 不給另存；⑥ 之後、⑦ 之前 postCheck 看合併後那筆。
// [v25.644 mac4 G1] judge_mac §R6（sim_mac4.py save4；sim4 編號 write4#）：W4-13 刪除多一道 deleteGate（剛抓到那筆，每一輪都跑）；
// W4-8 改的那筆 base 裡還在卻套不上 → cannotMerge（不問〔另存〕）；W4-9 金額＋金額歷史成組（〔用 iPhone 的〕一起換）。
// [v25.646 mac6 G1] judge_mac §T4-2（sim_mac6.py split6#15～#18）：writeKeys 多分帳鍵；分帳只走檔尾 saveSplit（raw JSON 局部改：
// 只加一筆現金還款、或在一筆現金還款加 removedAt）；save 一字不改（schema 擋線照留＝分帳走 save 一定被擋）。
import CloudKit
import Foundation
import os

/// 一次存的動作（原字典層級；值是 JSONSerialization 的值）
enum MacLedgerAction {
    /// 新增一筆（id 已經在字典裡）
    case add(raw: [String: Any])
    /// 改幾個欄位；值 nil＝拿掉那欄
    case edit(id: String, changes: [String: Any?])
    case delete(id: String)

    var itemID: String {
        switch self {
        case .add(let raw): return (raw["id"] as? String) ?? ""
        case .edit(let id, _): return id
        case .delete(let id): return id
        }
    }
}

enum MacConflictResolution {
    /// 同一欄位 iPhone 也改了 → 先問
    case askFirst
    /// 用我填的
    case mine
    /// 用 iPhone 的（那幾欄改用雲端的值重算）
    case theirs
}

/// 同一筆、同一欄位兩邊都改了（id＝那筆的 id）
struct MacFieldConflict: Identifiable {
    let id: String
    let field: String
    let before: Any?
    let iphone: Any?
    let mine: Any?
}

enum MacWriteOutcome {
    case saved(MacKVRecord, merged: Bool)
    case nothingToWrite(MacKVRecord)
    /// 刪除：另一台改過這筆，留著沒刪
    case keptByOtherDevice
    case needsDecision([MacFieldConflict])
    /// 那筆在另一台刪掉了（或開表單之後就不在了）
    case goneElsewhere
    /// 連續 3 次 iPhone 剛好也在存
    case busy
    case offline
    case notSignedIn
    /// iCloud 上沒有這份資料（不建記錄、不建 zone）
    case noRecord
    case locked(String)
    case selfCheckFailed([String])
    case cannotMerge
    case failed(String)
}

/// ② 同一次抓到的分帳、細項 bytes（支出那包才抓；收入 fetched＝false）
struct MacFreshLinks {
    let fetched: Bool
    let splitData: Data?
    let kindData: Data?
}

/// 存的進度（表單按鈕字）
enum MacWritePhase {
    case fetching
    case saving
}

@MainActor
final class MacCloudWriter {
    static let writeKeys = ["lifegood_expenses", "lifegood_incomes", "lifegood_expense_splits_v1"]
    static let maxAttempts = 3

    let cloud: MacCloud
    /// 表單按鈕「取得 iCloud 最新資料…」→「存到 iCloud…」
    var onPhase: (@MainActor (MacWritePhase) -> Void)?
    /// 最近一次 .saved 記下的日誌（編輯器拿去登記復原）
    private(set) var lastEntry: MacJournalEntry?

    private let logger = Logger(subsystem: "com.lifegood.app.mac", category: "writer")

    init(cloud: MacCloud = .shared) {
        self.cloud = cloud
    }

    /// gate：改一筆時拿剛抓到的那筆原字典＋這次的改動＋剛抓到的分帳細項再判斷一次，回傳不是 nil＝擋（原因字）；新增、刪除不走 gate。
    /// postCheck：動作、剛抓到那筆、合併後那筆、剛抓到的分帳細項；回傳不是 nil＝擋（刪除不跑；nil＝不檢查，退路 R4）
    /// deleteGate：刪除時拿剛抓到的那筆原字典再判斷一次（不是 nil＝擋；雲端已經沒有那筆就不叫，照舊走 ⑦）
    func save(key: String, action: MacLedgerAction, base: Data, resolution: MacConflictResolution,
              journal: MacJournal, golden: LedgerMergeGolden.Report, writeEnabled: Bool,
              gate: (@MainActor ([String: Any], [String: Any?], MacFreshLinks) -> String?)? = nil,
              postCheck: (@MainActor (MacLedgerAction, [String: Any]?, [String: Any]?, MacFreshLinks) -> String?)? = nil,
              deleteGate: (@MainActor ([String: Any]) -> String?)? = nil) async -> MacWriteOutcome {
        lastEntry = nil
        // ① 開關、黃金案例、白名單
        guard writeEnabled else { return .locked("還沒打開「允許這台 Mac 修改」（在資料來源頁）") }
        guard golden.allPassed else {
            return .locked("自我檢查 \(golden.passed)/\(golden.total) 沒全過，這台 Mac 先不能改")
        }
        guard Self.writeKeys.contains(key), let schema = LedgerMerge.schema(for: key) else {
            return .locked("這一版電腦只能改收支")
        }
        var action = action
        for attempt in 1...Self.maxAttempts {
            onPhase?(.fetching)
            // ② 重抓（sim3: fresh3#1 支出那包同一次多抓分帳、細項；抓失敗照舊回錯，不當成「沒有」）
            let keys = key == MacCloud.expensesKey ? [key, MacCloud.splitsKey, MacCloud.kindsKey] : [key]
            let fetched: MacKVRecord
            let fresh: MacFreshLinks
            do {
                let map = try await cloud.fetch(keys, withPayload: true)
                guard let r = map[key], r.record != nil, r.data != nil else { return .noRecord }
                fetched = r
                if key == MacCloud.expensesKey {
                    fresh = MacFreshLinks(fetched: true, splitData: map[MacCloud.splitsKey]?.data,
                                          kindData: map[MacCloud.kindsKey]?.data)
                } else {
                    fresh = MacFreshLinks(fetched: false, splitData: nil, kindData: nil)
                }
            } catch {
                return Self.outcome(for: error)
            }
            guard let record = fetched.record, let remote = fetched.data else { return .noRecord }

            // sim3: fresh3#2 支出那包：分帳或細項有 bytes 卻解不開 → 這次不存（在 gate 之前）
            if key == MacCloud.expensesKey,
               !(MacEditPolicy.linkDataParses(fresh.splitData, listKey: "splits")
                 && MacEditPolicy.linkDataParses(fresh.kindData, listKey: "tags")) {
                return .locked(MacEditPolicy.reasonLinksUnknown)
            }

            // sim4: write4#1（W4-13）刪除：剛抓到那筆再判斷一次（每一輪重試都跑）
            if case .delete(let id) = action, let deleteGate, let item = Self.item(id, in: remote),
               let reason = deleteGate(item) {
                return .locked(reason)
            }

            // sim2: gate#1（S1）用剛抓到的那筆重新判斷；serverRecordChanged 重試的每一輪都會再跑
            // sim3: gate3#1 多傳剛抓到的分帳、細項
            if case .edit(let id, let changes) = action, let gate, let item = Self.item(id, in: remote),
               let reason = gate(item, changes, fresh) {
                return .locked(reason)
            }

            // ③ local＝動作套在 base 原字典陣列上
            guard let local = Self.apply(action, to: base) else {
                // 新增套不上去＝開表單那份看不懂（不是被別台刪掉）
                if case .add = action { return .cannotMerge }
                // sim4: write4#2（W4-8）改的那筆在 base 裡還在、卻套不上（值寫不成 JSON 之類）＝不是被別台刪掉 → 不問〔另存〕
                if case .edit(let id, _) = action, let arr = LedgerMerge.parseArray(base),
                   LedgerMerge.index(arr).pos[id] != nil {
                    return .cannotMerge
                }
                // sim3: detach3#1（③）改的那筆不在了：剛抓到的分帳或細項有這個 id → 不給〔另存〕
                if case .edit(let id, _) = action, key == MacCloud.expensesKey, Self.detachLinked(id, fresh) {
                    return .locked(MacEditPolicy.reasonDetachLinked)
                }
                return .goneElsewhere
            }
            // ④ 三方合併
            guard var result = LedgerMerge.threeWay(schema, base: base, local: local.data, remote: remote) else {
                return .cannotMerge
            }
            // ⑤ 這筆在另一台刪了（改過的贏會把它加回去）→ 不悄悄寫回，由編輯器問〔另存成新的一筆〕
            if !result.resurrected.isEmpty {
                // sim3: detach3#1（⑤）剛抓到的分帳或細項有這個 id → 不給〔另存〕
                if case .edit(let id, _) = action, key == MacCloud.expensesKey, Self.detachLinked(id, fresh) {
                    return .locked(MacEditPolicy.reasonDetachLinked)
                }
                return .goneElsewhere
            }
            // ⑥ 同一欄位兩邊都改
            let itemID = action.itemID
            let sameField = result.conflicts.filter { c in c.kind == .sameField && c.id == itemID }
            if !sameField.isEmpty {
                switch resolution {
                case .askFirst:
                    return .needsDecision(Self.describe(sameField, action: action, base: base, remote: remote))
                case .mine:
                    break
                case .theirs:
                    // [review mac3 writer-1] 新增的 id 雲端已經有、而且 iPhone 改過（存失敗重按、⌘D 重用同一筆）：
                    // 〔用 iPhone 的〕＝留雲端那筆，不寫電腦的值
                    guard case .edit(let id, var changes) = action else { return .nothingToWrite(fetched) }
                    let remoteItem = Self.item(id, in: remote)
                    let conflictFields = sameField.map { c in c.field }
                    // sim2: group#1（S5）衝突欄位＋同組裡這次也改到的欄位，一起換成雲端的值（雲端沒有那欄＝拿掉）
                    for field in Self.theirsFields(conflictFields, changes: changes) {
                        changes.updateValue(remoteItem?[field], forKey: field)
                    }
                    action = .edit(id: id, changes: changes)
                    // sim2: gate#2 重套之後再判斷一次（sim3: gate3#2 一樣傳剛抓到的分帳、細項）
                    if let gate, let item = remoteItem, let reason = gate(item, changes, fresh) {
                        return .locked(reason)
                    }
                    guard let again = Self.apply(action, to: base),
                          let merged = LedgerMerge.threeWay(schema, base: base, local: again.data, remote: remote) else {
                        return .cannotMerge
                    }
                    if !merged.resurrected.isEmpty {
                        // sim3: detach3#1（〔用 iPhone 的〕）剛抓到的分帳或細項有這個 id → 不給〔另存〕
                        if key == MacCloud.expensesKey, Self.detachLinked(id, fresh) {
                            return .locked(MacEditPolicy.reasonDetachLinked)
                        }
                        return .goneElsewhere
                    }
                    result = merged
                }
            }
            // sim3: post3 合併後真正要寫的那一筆整筆驗（⑥ 含〔用 iPhone 的〕重合併之後、⑦ 之前；刪除不跑）
            if case .delete = action {} else if let postCheck {
                if let reason = postCheck(action, Self.item(itemID, in: remote), Self.item(itemID, in: result.data), fresh) {
                    return .locked(reason)
                }
            }
            // ⑦ 跟雲端一樣：不寫
            if result.equalsRemote {
                if case .delete = action, !result.keptDeleted.isEmpty { return .keptByOtherDevice }
                return .nothingToWrite(fetched)
            }
            // ⑧ 自我檢查
            let expect = Self.expectation(for: action)
            let problems = LedgerMerge.selfCheck(schema, remote: remote, result: result, expect: expect)
            if !problems.isEmpty {
                logger.error("selfCheck 沒過 \(problems.count, privacy: .private)")
                return .selfCheckFailed(problems)
            }
            // ⑨ 刪除：重抓分帳、細項，任何一筆記錄（含墓碑）有這個 id 就不刪
            if case .delete(let id) = action, let reason = await deleteBlocker(id) {
                return .locked(reason)
            }
            // ⑩ 寫前備份雲端那份
            guard journal.backup(key: key, data: remote) else {
                return .failed("這台 Mac 的備份寫不進去，這次先不存")
            }
            // ⑪ 條件寫入（拿剛抓到的那個 CKRecord）
            onPhase?(.saving)
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mac_kv_\(key).json")
            do {
                try result.data.write(to: tmp, options: .atomic)
            } catch {
                return .failed("暫存檔寫不進去，這次先不存")
            }
            record["payload"] = CKAsset(fileURL: tmp)
            record["updatedAt"] = Date() as NSDate
            record["keyName"] = key as NSString
            let write = await Self.conditionalSave(record, database: cloud.database)
            try? FileManager.default.removeItem(at: tmp)
            let saved: CKRecord
            switch write {
            case .saved(let r):
                saved = r
            case .changed:
                // iPhone 剛好也在存 → 重抓、重合併、再寫
                if attempt < Self.maxAttempts {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                continue
            case .error(let e):
                return Self.outcome(for: e)
            }
            // ⑫ 讀回
            guard let back = await Self.readBack(saved.recordID, database: cloud.database) else {
                // iCloud 已經回報存好了：日誌照記（看門狗、「最近在電腦改的」看得到），只是不登記復原
                _ = Self.journalEntry(action: action, key: key, remote: remote, written: result.data, journal: journal)
                return .failed("寫進去了但讀不回來，請按 ⌘R")
            }
            let updatedAt = (back["updatedAt"] as? Date) ?? (saved["updatedAt"] as? Date) ?? Date()
            // changeTag 用這次寫入伺服器給的（跟 data 對得上）；讀回的 tag 不一樣＝寫完到讀回之間別台又存了，
            // 不能拿讀回的 tag 配這份 data（之後每一輪比 tag 都會以為沒變、不重抓）
            let newRecord = MacKVRecord(key: key, record: saved, data: result.data,
                                        changeTag: saved.recordChangeTag,
                                        updatedAt: updatedAt, fetchedAt: Date())
            // ⑬ 日誌
            lastEntry = Self.journalEntry(action: action, key: key, remote: remote, written: result.data,
                                          journal: journal)
            let merged = Self.otherFieldsChanged(action: action, base: base, remote: remote)
            return .saved(newRecord, merged: merged)
        }
        return .busy
    }

    // MARK: - ③ 動作套在 base 上

    /// base 原字典陣列＋動作 → local（edit／delete：base 沒有那個 id → nil）
    static func apply(_ action: MacLedgerAction, to base: Data) -> (data: Data, array: [Any])? {
        guard var arr = LedgerMerge.parseArray(base) else { return nil }
        let idx = LedgerMerge.index(arr)
        switch action {
        case .add(let raw):
            arr.append(raw)
        case .edit(let id, let changes):
            guard let pos = idx.pos[id], var d = arr[pos] as? [String: Any] else { return nil }
            for (k, v) in changes {
                if let v { d.updateValue(v, forKey: k) } else { d.removeValue(forKey: k) }
            }
            arr[pos] = d
        case .delete(let id):
            guard let pos = idx.pos[id] else { return nil }
            arr.remove(at: pos)
        }
        guard JSONSerialization.isValidJSONObject(arr),
              let data = try? JSONSerialization.data(withJSONObject: arr, options: []) else { return nil }
        return (data, arr)
    }

    // MARK: - 〔用 iPhone 的〕成組換（S5）

    /// 要一起換的欄位組：組裡任一欄衝突，這次改到的同組欄位全部換成雲端的值（日誌 supersede、看門狗也照組）
    // sim4: write4#3（W4-9）金額＋金額歷史成組
    static let fieldGroups: [[String]] = [["endDate", "endReason"], ["amount", "amountHistory"]]

    static func theirsFields(_ conflictFields: [String], changes: [String: Any?]) -> [String] {
        var out = Set(conflictFields)
        for group in fieldGroups where group.contains(where: { f in conflictFields.contains(f) }) {
            for f in group where changes.keys.contains(f) { out.insert(f) }
        }
        return out.sorted()
    }

    static func expectation(for action: MacLedgerAction) -> LedgerMerge.Expectation {
        switch action {
        case .add(let raw): return LedgerMerge.Expectation(added: [(raw["id"] as? String) ?? ""])
        case .edit(let id, _): return LedgerMerge.Expectation(edited: [id])
        case .delete(let id): return LedgerMerge.Expectation(removed: [id])
        }
    }

    static func item(_ id: String, in data: Data) -> [String: Any]? {
        guard let arr = LedgerMerge.parseArray(data), let pos = LedgerMerge.index(arr).pos[id] else { return nil }
        return arr[pos] as? [String: Any]
    }

    /// ⑥ 衝突：每欄「改之前、iPhone 的、你填的」
    private static func describe(_ conflicts: [LedgerMerge.Conflict], action: MacLedgerAction, base: Data,
                                 remote: Data) -> [MacFieldConflict] {
        let id = action.itemID
        let baseItem = item(id, in: base)
        let remoteItem = item(id, in: remote)
        var mineItem: [String: Any]?
        if let local = apply(action, to: base) {
            mineItem = item(id, in: local.data)
        }
        var seen = Set<String>()
        var out: [MacFieldConflict] = []
        for c in conflicts where !seen.contains(c.field) {
            seen.insert(c.field)
            out.append(MacFieldConflict(id: id, field: c.field, before: baseItem?[c.field],
                                        iphone: remoteItem?[c.field], mine: mineItem?[c.field]))
        }
        return out
    }

    /// merged：雲端那筆跟 base 比，有別的欄位（不是這次改的）被另一台改過
    private static func otherFieldsChanged(action: MacLedgerAction, base: Data, remote: Data) -> Bool {
        guard case .edit(let id, let changes) = action,
              let b = item(id, in: base), let r = item(id, in: remote) else { return false }
        let keys = Set(b.keys).union(r.keys).subtracting(changes.keys)
        return keys.contains { k in !LedgerMerge.same(b[k], r[k]) }
    }

    // MARK: - ⑤ 〔另存〕前：剛抓到的分帳、細項有沒有這個 id（含墓碑）

    private static func detachLinked(_ id: String, _ fresh: MacFreshLinks) -> Bool {
        let t = id.uppercased()
        return MacEditPolicy.splitRecordIDs(fresh.splitData).contains(t) || MacEditPolicy.kindRecordIDs(fresh.kindData).contains(t)
    }

    // MARK: - ⑨ 刪除前重抓分帳、細項

    private func deleteBlocker(_ id: String) async -> String? {
        let keys = [MacCloud.splitsKey, MacCloud.kindsKey]
        let map: [String: MacKVRecord]
        do {
            map = try await cloud.fetch(keys, withPayload: true)
        } catch {
            return "確認不了這筆有沒有分帳或細項（\(Self.message(for: error))），這次先不刪"
        }
        let target = id.uppercased()
        if MacEditPolicy.splitRecordIDs(map[MacCloud.splitsKey]?.data).contains(target) {
            return MacEditPolicy.reasonSplitRecord
        }
        if MacEditPolicy.kindRecordIDs(map[MacCloud.kindsKey]?.data).contains(target) {
            return MacEditPolicy.reasonKindRecord
        }
        return nil
    }

    // MARK: - ⑬ 日誌

    private static func journalEntry(action: MacLedgerAction, key: String, remote: Data, written: Data,
                                     journal: MacJournal) -> MacJournalEntry {
        let id = action.itemID
        let before = item(id, in: remote)
        let after = item(id, in: written)
        switch action {
        case .add:
            return journal.record(key: key, kind: .add, itemID: id, label: MacEntryRules.label(raw: after),
                                  fields: [:], rawBefore: nil, rawAfter: after)
        case .edit(_, let changes):
            var fields: [String: (before: Any?, after: Any?)] = [:]
            for (k, v) in changes {
                fields[k] = (before: before?[k], after: v)
            }
            return journal.record(key: key, kind: .edit, itemID: id, label: MacEntryRules.label(raw: after ?? before),
                                  fields: fields, rawBefore: before, rawAfter: after)
        case .delete:
            return journal.record(key: key, kind: .delete, itemID: id, label: MacEntryRules.label(raw: before),
                                  fields: [:], rawBefore: before, rawAfter: nil)
        }
    }

    // MARK: - ⑪ 條件寫入、⑫ 讀回（CloudKit 回呼在背景佇列，這兩支不綁主執行緒）

    enum SaveResult {
        case saved(CKRecord)
        case changed
        case error(Error)
    }

    enum MacWriterError: Error {
        /// iCloud 回報成功，卻沒有回傳存好的那筆
        case noSavedRecord
    }

    private final class OpBox: @unchecked Sendable {
        var record: CKRecord?
        var error: Error?
    }

    nonisolated private static func conditionalSave(_ record: CKRecord, database: CKDatabase) async -> SaveResult {
        await withCheckedContinuation { (cont: CheckedContinuation<SaveResult, Never>) in
            let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            op.savePolicy = .ifServerRecordUnchanged
            op.qualityOfService = .userInitiated
            let box = OpBox()
            op.perRecordSaveBlock = { _, res in
                switch res {
                case .success(let r): box.record = r
                case .failure(let e): box.error = e
                }
            }
            op.modifyRecordsResultBlock = { overall in
                if case .failure(let e) = overall, box.error == nil { box.error = e }
                if let e = box.error {
                    cont.resume(returning: MacCloudWriter.isServerRecordChanged(e) ? .changed : .error(e))
                } else if let r = box.record {
                    cont.resume(returning: .saved(r))
                } else {
                    cont.resume(returning: .error(MacWriterError.noSavedRecord))
                }
            }
            database.add(op)
        }
    }

    nonisolated private static func readBack(_ id: CKRecord.ID, database: CKDatabase) async -> CKRecord? {
        await withCheckedContinuation { (cont: CheckedContinuation<CKRecord?, Never>) in
            let op = CKFetchRecordsOperation(recordIDs: [id])
            op.desiredKeys = ["updatedAt"]
            op.qualityOfService = .userInitiated
            let box = OpBox()
            op.perRecordResultBlock = { _, res in
                if case .success(let r) = res { box.record = r }
            }
            op.fetchRecordsResultBlock = { _ in
                cont.resume(returning: box.record)
            }
            database.add(op)
        }
    }

    nonisolated static func isServerRecordChanged(_ error: Error) -> Bool {
        guard let ck = error as? CKError else { return false }
        if ck.code == .serverRecordChanged { return true }
        if ck.code == .partialFailure, let byID = ck.partialErrorsByItemID {
            return byID.values.contains { e in (e as? CKError)?.code == .serverRecordChanged }
        }
        return false
    }

    // MARK: - 錯誤 → 結果

    static func outcome(for error: Error) -> MacWriteOutcome {
        if let e = error as? MacCloudError {
            switch e {
            case .network: return .offline
            case .zoneNotFound: return .noRecord
            case .noAccount, .restricted, .couldNotDetermine: return .notSignedIn
            case .other(let s): return .failed(s)
            default: return .failed("iCloud 暫時不能用，等一下再試")
            }
        }
        if let ck = error as? CKError {
            switch ck.code {
            case .networkUnavailable, .networkFailure: return .offline
            case .notAuthenticated: return .notSignedIn
            case .zoneNotFound, .userDeletedZone, .unknownItem: return .noRecord
            case .quotaExceeded: return .failed("iCloud 空間不夠，這次沒有寫進去")
            case .requestRateLimited, .serviceUnavailable, .zoneBusy: return .failed("iCloud 現在很忙，等幾秒再按一次")
            default: return .failed("iCloud 沒有存成功（\(ck.code.rawValue)）")
            }
        }
        if error is MacWriterError { return .failed("iCloud 沒有回傳存好的那筆，請按 ⌘R 看看有沒有存進去") }
        return .failed("沒有存成功，請再試一次")
    }

    static func message(for error: Error) -> String {
        switch outcome(for: error) {
        case .offline: return "離線中"
        case .notSignedIn: return "這台 Mac 沒登入 iCloud"
        case .noRecord: return "iCloud 上沒有這份資料"
        case .failed(let s): return s
        default: return "iCloud 出錯"
        }
    }
}

// MARK: - [v25.646 mac6 G1] 分帳寫入（judge_mac §T4-2；同檔 extension 才拿得到 private 的 conditionalSave、lastEntry、logger）

// 每次存（最多 3 次嘗試）：① 開關、收支黃金、分帳黃金、白名單 ② 同一次重抓分帳＋支出（記錄不存在 → 不建）②b 形狀
// ③ gate（每一輪都在剛抓到的那份上重跑）④ resolved＋apply（＝local 只有這一個冪等動作的 threeWay）⑤ selfCheck ⑥ postCheck
// ⑦ 跟雲端一樣不寫 ⑧ 序列化 ⑨ 寫前備份 ⑩ 拿剛抓到的那個 CKRecord 只設 payload／updatedAt／keyName，.ifServerRecordUnchanged
// ⑪ 讀回 ⑫ 日誌（不帶名字；label 由 MacEditCenter 給「分帳還款・11/20 飲食」）。log 只記個數、.private。
extension MacCloudWriter {
    func saveSplit(_ action: MacSplitAction, journal: MacJournal, golden: LedgerMergeGolden.Report, splitGolden: MacSplitGolden.Report, writeEnabled: Bool, label: @MainActor ([String: Any]) -> String) async -> MacWriteOutcome {
        lastEntry = nil
        // sim6: split6#15 ① 開關、黃金案例（收支、分帳）、白名單
        guard writeEnabled else { return .locked(MacSplitPatch.reasonText("write_off")) }
        guard golden.allPassed else {
            return .locked("自我檢查 \(golden.passed)/\(golden.total) 沒全過，這台 Mac 先不能改")
        }
        guard splitGolden.allPassed else { return .locked(MacSplitPatch.reasonText("split_golden")) }
        let key = MacCloud.splitsKey
        guard Self.writeKeys.contains(key) else { return .locked(MacSplitPatch.reasonText("page_only")) }
        for attempt in 1...Self.maxAttempts {
            onPhase?(.fetching)
            // sim6: split6#16 ② 分帳＋支出同一次抓（抓失敗照舊回錯，不當成「沒有」）；任一個記錄不在 → 不建
            let fetched: MacKVRecord
            let expensesData: Data
            do {
                let map = try await cloud.fetch([MacCloud.splitsKey, MacCloud.expensesKey], withPayload: true)
                guard let s = map[MacCloud.splitsKey], s.record != nil, s.data != nil,
                      let e = map[MacCloud.expensesKey], e.record != nil, let ed = e.data else { return .noRecord }
                fetched = s
                expensesData = ed
            } catch {
                return Self.outcome(for: error)
            }
            guard let record = fetched.record, let remoteData = fetched.data else { return .noRecord }
            // ②b 分帳頂層是物件、splits 是陣列；支出是陣列（解不開不能當空包）
            guard let root = (try? JSONSerialization.jsonObject(with: remoteData, options: [])) as? [String: Any],
                  (root["splits"] as? [Any]) != nil, let expenses = LedgerMerge.parseArray(expensesData) else {
                return .locked(MacSplitPatch.reasonText("split_shape"))
            }
            // sim6: split6#17 ③ gate（剛抓到的；每一輪重試都重跑）
            switch MacSplitPatch.gate(root, expenses: expenses, action: action, now: Date()) {
            case .go:
                break
            case .done:
                return .nothingToWrite(fetched)
            case .locked(let k):
                return .locked(MacSplitPatch.lockText(k, root: root, action: action))
            }
            // ④ 金額換成剛抓到的 outstanding、nil 換成 lastRepayment；套在剛抓到的那份上
            guard let act = MacSplitPatch.resolved(action, in: root),
                  let result = MacSplitPatch.apply(act, to: root) else { return .cannotMerge }
            // ⑤ 自我檢查（結構）
            let problems = MacSplitPatch.selfCheck(remote: root, result: result, action: act)
            if !problems.isEmpty {
                logger.error("分帳 selfCheck 沒過 \(problems.count, privacy: .private)")
                return .selfCheckFailed(problems)
            }
            // ⑥ 存之前的檢查（語意：你的份不變、只現金、iPhone 解得開、那筆支出還在）
            if let k = MacSplitPatch.postCheck(remote: root, result: result, expenses: expenses, action: act) {
                return .locked(MacSplitPatch.reasonText(k))
            }
            // ⑦ 跟雲端一樣：不寫
            if LedgerMerge.same(result, root) { return .nothingToWrite(fetched) }
            // ⑧ 序列化
            guard JSONSerialization.isValidJSONObject(result),
                  let resultData = try? JSONSerialization.data(withJSONObject: result, options: []) else { return .cannotMerge }
            // sim6: split6#18 ⑨ 寫前備份雲端那份
            guard journal.backup(key: key, data: remoteData) else {
                return .failed("這台 Mac 的備份寫不進去，這次先不存")
            }
            // ⑩ 條件寫入（拿剛抓到的那個 CKRecord；撞到 → 回 ② 重抓、重 gate）
            onPhase?(.saving)
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mac_kv_\(key).json")
            do {
                try resultData.write(to: tmp, options: .atomic)
            } catch {
                return .failed("暫存檔寫不進去，這次先不存")
            }
            record["payload"] = CKAsset(fileURL: tmp)
            record["updatedAt"] = Date() as NSDate
            record["keyName"] = key as NSString
            let write = await Self.conditionalSave(record, database: cloud.database)
            try? FileManager.default.removeItem(at: tmp)
            let saved: CKRecord
            switch write {
            case .saved(let r):
                saved = r
            case .changed:
                if attempt < Self.maxAttempts {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                continue
            case .error(let e):
                return Self.outcome(for: e)
            }
            let entryLabel = label(MacSplitPatch.expenseItem(expenses, id: MacSplitPatch.ids(act).expense) ?? [:])
            // ⑪ 讀回：同一個 changeTag 要解出來跟 result 一樣（tag 不一樣＝寫完之後別台又存了，這次照樣算存好）
            var back: MacKVRecord? = nil
            do {
                let map = try await cloud.fetch([key], withPayload: true)
                back = map[key]
            } catch {
                back = nil
            }
            guard let b = back, b.record != nil, let backData = b.data, Self.splitReadBackOK(b, saved: saved, data: backData, written: result) else {
                // iCloud 已經回報存好了：日誌照記（看門狗、「最近在電腦改的」看得到），只是不登記復原
                _ = Self.splitJournalEntry(act, written: result, label: entryLabel, journal: journal)
                return .failed("寫進去了但讀不回來，請按 ⌘R")
            }
            let updatedAt = b.updatedAt ?? (saved["updatedAt"] as? Date) ?? Date()
            // changeTag 用這次寫入伺服器給的（跟 data 對得上；同 save 的理由）
            let newRecord = MacKVRecord(key: key, record: saved, data: resultData, changeTag: saved.recordChangeTag,
                                        updatedAt: updatedAt, fetchedAt: Date())
            // ⑫ 日誌
            lastEntry = Self.splitJournalEntry(act, written: result, label: entryLabel, journal: journal)
            return .saved(newRecord, merged: false)
        }
        return .busy
    }

    /// ⑪ 讀回那份：changeTag 跟這次寫入一樣 → 值要跟 result 一樣；不一樣（別台後來又存）→ 不比
    private static func splitReadBackOK(_ back: MacKVRecord, saved: CKRecord, data: Data, written: [String: Any]) -> Bool {
        guard back.changeTag == saved.recordChangeTag else { return true }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []) else { return false }
        return LedgerMerge.same(obj, written)
    }

    /// ⑫ 一筆分帳日誌（key＝分帳鍵、itemID＝"<支出UUID>|<那位UUID>"、rawAfter 只有 id／日期／金額；沒有名字）
    private static func splitJournalEntry(_ action: MacSplitAction, written: [String: Any], label: String,
                                          journal: MacJournal) -> MacJournalEntry {
        let info = MacSplitPatch.journalInfo(action, written: written)
        let kind: MacJournalEntry.Kind
        if case .repay = action {
            kind = .repay
        } else {
            kind = .unrepay
        }
        return journal.record(key: MacCloud.splitsKey, kind: kind, itemID: info.itemID, label: label,
                              fields: [:], rawBefore: nil, rawAfter: info.rawAfter)
    }
}
