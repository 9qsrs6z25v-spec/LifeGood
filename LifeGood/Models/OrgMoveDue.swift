import Foundation
import Combine
import UIKit

// MARK: - [v25.592 轉組織 v1b] 排在以後：規則、字（OrgMovePlan 的延伸）與到期那天自動改部門（OrgMoveDueCenter）
//（orgmove/judge.md §3.5、§3.8、§4.1、§4.4、§4.5、§4.7、§4.8、§5-1、§5-6、§5-15、§5-16、§5-18、§5-21、§5-36、§7 v1b、§13 第 6 題；
//  orgmove/build/v1b/brief.md §2；sim_v1b.py 一個函式一個函式對照）
//
// • 生效日可以排以後，預設下個月 1 號。確認時兩種（預設第一種）：
//   〔現在就交接，11/1 才改部門〕（timing "handoverNow"）＝事情確認那一刻就交（state "handed"），部門、廠區、名片、組織人員、管理人員 11/1 才改；
//   〔11/1 一起做〕（"together"）＝什麼都先不動（state "planned"），11/1 照那天的資料一起做（已經逾期的那天重算新截止）。
// • 會議、班的切點＝生效日與交接那天取晚的（cutKey；排在以後＝生效日；v1a 是交接那天）。
// • 生效那天打開 App 才改（沒開就下次打開補做，生效日照記）。**自動改只在三個條件都成立時**（judge §1.4-10、§3.5）：
//   ① 這支不是加入別人共享的那支（家人那支打開什麼都不動）② 這一輪 iCloud 拉取成功（或這台沒開 iCloud 同步）③ 沒有部屬／組織人員編輯頁開著。
//   不成立：不自動做，卡片與部屬總覽最上面「今天生效〔現在套用〕」你按才做。自動做的不碰行事曆、提醒事項（「今天生效」那張上你按）。
// • 字的規矩：不用「他／她」，寫名字或「這位同仁」。這裡的字只在 App 內頁；通知、小工具、手錶、鎖定畫面一個字都沒加（通知是 v3）。

/// 部屬總覽最上面「今天生效」卡的一列（judge §3.5「不然「今天生效〔現在套用〕」你按」）
struct OrgMoveDueRow: Identifiable, Equatable {
    let moveId: UUID
    let personId: UUID
    /// 「王小明 製造一課 → 設備課（P1 → P2）・11/1 生效」
    let title: String
    /// 「部門、廠區還沒改」／卡住的原因（「設備課已經刪掉了，要改去哪個部門？」）
    let detail: String
    let blocked: Bool
    let actions: [OrgMoveHintAction]
    var id: UUID { moveId }
}

/// 部門頁最下面「異動」那一區的一列（judge §4.8）
struct OrgMoveDeptRow: Identifiable, Equatable {
    let moveId: UUID
    /// 「11/1 王小明 調到 設備課（交出去 9 項）」「11/1 王小明 從 製造一課 調來」
    let title: String
    /// 調來的（true）／調走的（false）
    let incoming: Bool
    /// 排序用
    let effectiveKey: String
    var id: UUID { moveId }
}

/// 〔取消這張單〕的確認框（judge §3.8 生效前那一列）
struct OrgMoveCancelAsk: Equatable {
    let title: String
    let message: String
    /// 排好的（什麼都沒做）：只有一顆〔取消這張單〕
    let confirmLabel: String?
    /// 交出去了：〔拿回來（還沒做完的 7 項）〕（＝復原）
    let takeBackLabel: String?
    /// 交出去了：〔留給接手的人〕（交接照舊、部門不改了）
    let keepLabel: String?
}

/// 精靈一打開：這位已經有一張排好的（judge §5-21「王小明已經排了 11/1 轉組織〔打開那張〕〔取消那張、重排〕」）
struct OrgMovePlannedPrompt: Equatable {
    let moveId: UUID
    let title: String
    let message: String
}

/// 「今天生效」那張（LifeGoodApp 自動改完跳的、卡片／總覽〔現在套用〕之後跳的；judge §3.10 11/2 08:10）
struct OrgMoveDueNotice: Identifiable {
    let id = UUID()
    let results: [OrgMoveDueResult]
    /// 打開 App 時自動改的（false＝你按〔現在套用〕的）
    let auto: Bool
}

extension OrgMovePlan {

    // MARK: 生效日、什麼時候做

    /// 下個月 1 號（judge 第 6 題：10/28 打開就是 11/1；12/5 打開是 1/1）
    static func nextMonthFirstKey(_ todayKey: String) -> String {
        let parts = todayKey.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]) else { return todayKey }
        let ny = m == 12 ? y + 1 : y
        let nm = m == 12 ? 1 : m + 1
        return String(format: "%04d-%02d-01", ny, nm)
    }

    /// 精靈第 ① 步的預設生效日（下個月 1 號那天 00:00）
    static func defaultEffectiveDate(now: Date) -> Date {
        date(fromKey: nextMonthFirstKey(dayKey(now))) ?? now
    }

    /// 這一天在今天以後（＝要排；今天或以前＝確認就全部做）
    static func isFuture(_ effectiveKey: String, todayKey: String) -> Bool {
        effectiveKey > todayKey
    }

    /// 「什麼時候做」那兩顆（judge §4.4）
    static func timingOptions(effectiveKey: String, plantOnly: Bool = false, keepDept: Bool = false) -> [OrgMoveTimingOption] {
        let d = shortDay(effectiveKey)
        // [v25.592 轉組織 v1b 裁定] 〔照舊（只交接）〕部門不會改、只換廠區改的是廠區：兩顆的字不寫「才改部門」。
        // 要退回這一件：刪 plantOnly、keepDept 兩個參數與下面兩個 if（applyScheduleTexts 那一行改回只帶 effectiveKey）
        if keepDept {
            return [
                OrgMoveTimingOption(timing: .handoverNow, label: "現在就交接",
                                    note: "按下去就把事情交出去；部門照舊（\(d) 生效）"),
                OrgMoveTimingOption(timing: .together, label: "\(d) 再交接",
                                    note: "\(d) 以前什麼都不動；\(d) 照那天的資料交接、部門照舊（那天已經逾期的會重新給新的截止日）")
            ]
        }
        if plantOnly {
            return [
                OrgMoveTimingOption(timing: .handoverNow, label: "現在就交接，\(d) 才換廠區",
                                    note: "按下去就把事情交出去；廠區 \(d) 才換（\(d) 打開 App 時在你自己的手機上換）"),
                OrgMoveTimingOption(timing: .together, label: "\(d) 一起做",
                                    note: "\(d) 以前什麼都不動；\(d) 照那天的資料一起交接、換廠區（那天已經逾期的會重新給新的截止日）")
            ]
        }
        return [
            OrgMoveTimingOption(timing: .handoverNow, label: "現在就交接，\(d) 才改部門",
                                note: "按下去就把事情交出去；部門、廠區、名片、組織圖 \(d) 才改（\(d) 打開 App 時在你自己的手機上改）"),
            OrgMoveTimingOption(timing: .together, label: "\(d) 一起做",
                                note: "\(d) 以前什麼都不動；\(d) 照那天的資料一起交接、改部門（那天已經逾期的會重新給新的截止日）")
        ]
    }

    /// 第 ③ 步：生效日在以後時的那幾段（「什麼時候做」、生日提醒那行小字、接手的人比這張先調走的提醒）
    static func applyScheduleTexts(_ p: inout OrgMovePreview, draft: OrgMoveDraft, move: OrgMove,
                                   world: OrgMoveWorld, now: Date) {
        let today = dayKey(now)
        guard isFuture(move.effectiveKey, todayKey: today) else { return }
        // [v25.592 轉組織 v1b 裁定] 帶 kind、keepDept（字見 timingOptions）。要退回這一件：改回只帶 effectiveKey
        p.timingOptions = timingOptions(effectiveKey: move.effectiveKey,
                                        plantOnly: move.kind == OrgMoveKind.plant.rawValue,
                                        keepDept: move.keepDept == true)
        // [v25.593 轉組織 v2] 調出、離職、退休的兩顆（「現在就交接，11/1 才調出」…；OrgMoveOut.swift）。要退回這一件：刪這兩行
        let leaving = leavingTimingOptions(move)
        if !leaving.isEmpty { p.timingOptions = leaving }
        let chosen = p.timingOptions.first(where: { $0.timing == draft.timing }) ?? p.timingOptions[0]
        p.timingNote = chosen.note
        p.birthdayNote = "\(shortDay(move.effectiveKey)) 在「今天生效」那張上按一下才改"
        p.warnings = leavingWarnings(move)
    }

    /// 「陳怡君 11/1 前就調走了，確定交給這位？」：接手的人自己也排了轉組織、而且比這張早生效（judge §5-1）
    static func leavingWarnings(_ move: OrgMove) -> [String] {
        var seen = Set<UUID>()
        var out: [String] = []
        for l in move.allLines where !l.isOrgLine {
            guard let to = receiver(l, in: move).id, !seen.contains(to), to != move.personId else { continue }
            seen.insert(to)
            guard let p = OrgMoveIndex.plannedByPerson[to], p.moveId != move.id,
                  p.effectiveKey < move.effectiveKey, leavingNote(to) != nil else { continue }
            let n = receiver(l, in: move).name ?? "這位同仁"
            out.append("\(n) \(shortDay(move.effectiveKey)) 前就調走了（\(shortDay(p.effectiveKey))），確定交給這位？")
        }
        return out
    }

    /// 挑人頁副標「11/9 也要調走」（只換廠區＝「11/9 也要換廠區」；部門照舊的交接＝不寫）
    static func leavingNote(_ subId: UUID) -> String? {
        guard let p = OrgMoveIndex.plannedByPerson[subId] else { return nil }
        let d = shortDay(p.effectiveKey)
        if p.kind == OrgMoveKind.plant.rawValue { return "\(d) 也要換廠區" }
        // [v25.593 轉組織 v2] 排好要調出、離職、退休的：「11/9 也要調走」「11/9 離職」「11/9 退休」（部門照舊的調出也寫）。要退回這一件：刪這三行
        if p.kind == OrgMoveKind.resign.rawValue { return "\(d) 離職" }
        if p.kind == OrgMoveKind.retire.rawValue { return "\(d) 退休" }
        if p.kind == OrgMoveKind.out.rawValue { return "\(d) 也要調走" }
        if p.keepDept || p.toDeptId == p.fromDeptId { return nil }
        return "\(d) 也要調走"
    }

    // MARK: 你自己加的一項（kind "custom"：只記在單上、可以勾已交）

    /// 新的一列（第 ② 步〔＋ 自己加一項〕、交接單〔＋ 自己加一項〕）
    static func newCustomLine(title: String, memo: String, now: Date) -> OrgMoveLine {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        return OrgMoveLine(kind: OrgMoveLine.customKind, title: t.isEmpty ? "自己加的一項" : t,
                           memo: m.isEmpty ? nil : m, updatedAt: now)
    }

    static func customChoices(personName: String) -> [OrgMoveChoice] {
        [OrgMoveChoice(action: .give, label: "交給…", needsPerson: true),
         OrgMoveChoice(action: .follow, label: "跟著\(personName)", needsPerson: false)]
    }

    static func customReasons(_ line: OrgMoveLine) -> [String] {
        ["自己加的・只記在交接單上（不動任何資料）"]
    }

    /// 交接單那一列：✓「11/3 已交給 陳怡君」／○「交給 陳怡君・還沒交」／・「跟著王小明」
    static func customStatus(_ line: OrgMoveLine, move: OrgMove) -> OrgMoveLineStatus {
        // [v25.593 轉組織 v2] 自己加的一項〔交出去〕（鑰匙交給黃冠宇、我先收著）：同待辦那一種（OrgMoveOut.swift）。要退回這一件：刪這一行
        if line.lineAction == .handOut { return handOutStatus(line, move: move) }
        let person = move.personName.isEmpty ? "這位同仁" : move.personName
        let to = line.lineAction == .give ? line.toId : nil
        let toName = line.toName ?? ""
        if let at = line.checkedAt {
            let text = to == nil ? "\(shortDay(dayKey(at))) 已交" : "\(shortDay(dayKey(at))) 已交給 \(toName)"
            return OrgMoveLineStatus(kind: .custom, mark: "✓", text: text, holderId: to, fix: nil, fixLabel: nil)
        }
        if to != nil {
            return OrgMoveLineStatus(kind: .custom, mark: "○", text: "交給 \(toName)・還沒交", holderId: to, fix: nil, fixLabel: nil)
        }
        let undecided = line.action == nil ? "還沒決定（先跟著\(person)）" : "跟著\(person)"
        return OrgMoveLineStatus(kind: .custom, mark: "・", text: undecided, holderId: nil, fix: nil, fixLabel: nil)
    }

    /// 分享文字「自己加的」那一段（編號接著算；寫交接備註）
    static func customShareItems(_ lines: [OrgMoveLine], n: inout Int) -> [String] {
        guard !lines.isEmpty else { return [] }
        var out: [String] = ["自己加的"]
        for l in lines {
            n += 1
            out.append("\(n). \(l.title)")
            let memo = (l.memo ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !memo.isEmpty { out.append("   備註：\(memo)") }
        }
        return out
    }

    // MARK: 排好了、什麼都還沒做（〔11/1 一起做〕）的那一列

    static func plannedStatus(_ line: OrgMoveLine, move: OrgMove) -> OrgMoveLineStatus {
        let person = move.personName.isEmpty ? "這位同仁" : move.personName
        let d = shortDay(move.effectiveKey)
        let r = resolved(line, in: move.allLines)
        let rec = receiver(line, in: move)
        var text: String
        switch r.action {
        case .some(.give), .some(.newSeries):
            text = "排好了：\(d) 交給 \(rec.name ?? r.toName ?? "")"
            if line.lineAction == .withEquipment { text += "（跟著機台）" }
        case .some(.pending): text = "排好了：\(d) 待分派"
        case .some(.drop): text = "排好了：\(d) 不要了"
        case .some(.closeNow): text = "排好了：\(d) 結案"
        case .some(.end): text = "排好了：\(d) 前一場是最後一場"
        // [v25.593 轉組織 v2]「排好了：11/1 交出去給 黃冠宇」「排好了：11/1 我先接」
        case .some(.handOut):
            text = (line.toId == meId) ? "排好了：\(d) 我先接" : "排好了：\(d) 交出去給 \(line.toName ?? "")"
        case .some(.remove), .some(.replace), .some(.add), .some(.keep), .some(.skip): text = line.title
        case .some(.follow), .some(.withEquipment), .none: text = "排好了：跟著\(person)"
        }
        return OrgMoveLineStatus(kind: .planned, mark: "◌", text: text, holderId: move.personId, fix: nil, fixLabel: nil)
    }

    // MARK: 交接單單頭、「組織」那一列、歷程

    /// 單頭日子那一行多的那一段：交出去了、部門還沒改＝「・11/1 才改部門」；生效那天才改部門的＝「・11/2 08:10 改的部門」
    static func scheduleHeaderParts(_ move: OrgMove) -> String {
        if move.isHanded { return "・\(shortDay(move.effectiveKey)) 才改部門" }
        // [v25.592 轉組織 v1b 驗證]〔留給接手的人〕〔只做交接〕（cancelNote 寫了那一句）的部門沒改：不寫「…改的部門」
        //（不然單頭是「10/28 交接・10/30 14:00 改的部門」，可是部門照舊）。要退回這一件：拿掉 `move.cancelNote == nil,`
        guard move.timingValue == .handoverNow, move.cancelNote == nil, let a = move.appliedAt else { return "" }
        let c = calendar.dateComponents([.hour, .minute], from: a)
        let hm = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        return "・\(shortDay(dayKey(a))) \(hm) 改的部門"
    }

    /// 「11/1 起調設備課」「11/1 起換到 P2」「11/1 交接（部門照舊）」
    static func pendingHead(_ m: OrgMove, world: OrgMoveWorld) -> String {
        let d = shortDay(m.effectiveKey)
        if m.kind == OrgMoveKind.plant.rawValue { return "\(d) 起換到 \(m.to.plant ?? "")" }
        // [v25.593 轉組織 v2]「11/1 起調出到品保課」「11/1 起調出我的管轄」「11/1 起離職」「11/1 起退休」。要退回這一件：刪這一行
        if let h = leavingPendingHead(m, world: world) { return h }
        if m.keepDept == true || m.to.deptId == m.from.deptId { return "\(d) 交接（部門照舊）" }
        let dept = sideText(OrgMoveSide(deptId: m.to.deptId, deptLabel: m.to.deptLabel), world: world)
        return "\(d) 起調\(dept)"
    }

    /// 「組織」那一列（部門還沒改）：「11/1 才改：設備課・P2」；到了卻卡住＝⚠ 為什麼
    static func pendingOrgStatus(_ move: OrgMove, world: OrgMoveWorld, now: Date = Date()) -> (ok: Bool, text: String) {
        if isDue(move, todayKey: dayKey(now)), let b = dueBlock(move, world: world) {
            return (false, "⚠ " + b.text)
        }
        // [v25.593 轉組織 v2] 調出也改部門（changesDept）；調出、離職、退休多「收進已轉出」「標成已離職」。
        // 要退回這一件：改回 `move.kind == OrgMoveKind.move.rawValue && …`、刪 leavingWhat 那一行
        let deptChanged = move.changesDept
        let plantChanged = (move.to.plant ?? "") != (move.from.plant ?? "")
        let gradeChanged = move.to.gradeTitleId != move.from.gradeTitleId
        var what: [String] = []
        if deptChanged { what.append(sideText(OrgMoveSide(deptId: move.to.deptId, deptLabel: move.to.deptLabel), world: world)) }
        if plantChanged, let p = move.to.plant, !p.isEmpty { what.append(p) }
        if gradeChanged, let t = move.to.titleLabel, !t.isEmpty { what.append(t) }
        what.append(contentsOf: leavingWhat(move))
        if what.isEmpty { return (true, "部門照舊") }
        return (true, "\(shortDay(move.effectiveKey)) 才改：" + what.joined(separator: "・"))
    }

    /// 歷程那一列的標題（「2026/11/1 轉組織」「…（已取消）」「…（已復原）」）
    static func historyTitle(_ m: OrgMove) -> String {
        // [v25.593 轉組織 v2]「2026/11/1 調出我的管轄」「2026/11/1 離職」「2026/11/1 退休」「2026/12/15 回到我的部屬」。
        // 要退回這一件：word 改回 "轉組織"
        let word = historyWord(m)
        // [v25.592 轉組織 v1b 裁定] 用 undoneByCancel（〔留給接手的人〕之後再〔復原〕寫「已復原」）。要退回這一件：改回 `m.cancelledAt != nil`
        if m.isUndone { return "\(fullDay(m.effectiveKey)) \(word)" + (m.undoneByCancel ? "（已取消）" : "（已復原）") }
        return "\(fullDay(m.effectiveKey)) \(word)"
    }

    /// 歷程那一列的灰字（「交出去 10・跟著 5」「（已取消）」「交出去 9・跟著 5（11/1 才改部門）」）
    static func historySub(_ m: OrgMove, given: Int, follow: Int) -> String {
        // [v25.592 轉組織 v1b 裁定] 同 historyTitle。要退回這一件：改回 `m.cancelledAt != nil`
        if m.isUndone { return m.undoneByCancel ? "（已取消）" : "（已復原）" }
        // [v25.593 轉組織 v2] 回到我的部屬那一張什麼都沒交：不寫件數。要退回這一件：刪這一行
        if m.isBack { return "" }
        var s = "交出去 \(given)・跟著 \(follow)"
        if m.isHanded { s += "（\(shortDay(m.effectiveKey)) 才改部門）" }
        if m.keepDept == true, m.cancelledAt != nil { s += "（調動取消了）" }
        return s
    }

    // MARK: 提示列（看板下那一條）

    /// 卡片要不要建 OrgMoveWorld 的先擋（寬鬆：原人是這位、有一列交給這位、跟著機台還沒寫接手的人）。
    /// 比 OrgMoveCardData.hasOpenMove 多認得「部門還沒改的」（排好的、交出去了還沒到生效日的）
    static func hasHint(personId: UUID, book: OrgMoveBook, todayKey: String) -> Bool {
        book.live.contains { m in
            let open = isOpen(m, todayKey: todayKey)
            guard open || m.orgPending else { return false }
            if m.personId == personId { return true }
            return m.allLines.contains { l in
                l.toId == personId || (l.action == OrgMoveAction.withEquipment.rawValue && l.toId == nil)
            }
        }
    }

    /// 原人那一條（部門還沒改的那一張；沒有就 nil，照舊走套用之後的那一條）
    static func pendingPersonHint(personId: UUID, book: OrgMoveBook, world: OrgMoveWorld, now: Date) -> OrgMoveHint? {
        let today = dayKey(now)
        let list = book.live.filter { $0.personId == personId && $0.orgPending }
        guard let m = list.max(by: { ($0.createdAt ?? Date.distantPast) < ($1.createdAt ?? Date.distantPast) }) else { return nil }
        let person = m.personName.isEmpty ? "這位同仁" : m.personName
        let head = pendingHead(m, world: world)
        let late = lateLines(m, world: world, now: now)
        var actions: [OrgMoveHintAction] = []
        var warning: String?
        var text: String
        if isDue(m, todayKey: today) {
            text = "\(head)・今天生效"
            if let b = dueBlock(m, world: world) {
                warning = b.text
                actions = blockActions(b.kind)
            } else {
                warning = "部門、廠區還沒改"
                actions = [.applyNow]
            }
        } else if m.isPlanned {
            text = "\(head)・交接單排好了（\(lineCount(m.allLines) + m.allLines.filter(\.isLiveCustom).count) 項）"
        } else {
            text = "\(head)・已交出 \(handedCounts(m).given) 項"
            warning = handedWarning(m, world: world, now: now)
        }
        var badge: String?
        if m.isHanded {
            let map = OrgMoveHolderMap(world: world)
            let pend = tiles(m, map: map, world: world, now: now).first(where: { $0.id == "pending" })?.value ?? "0"
            badge = pend == "0" ? nil : "待分派 \(pend)"
        }
        var hint = OrgMoveHint(moveId: m.id, text: text, badge: badge, warning: warning, isReceiver: false)
        if !late.isEmpty {
            hint.note = lateNote(late.count, person: person)
            actions.append(.addLate)
        }
        hint.actions = actions
        return hint
    }

    /// 交出去了、部門還沒改的那張：⚠ 又回到原人身上／在兩個人身上（舊 iPad 存回來的；同套用之後那一條）
    private static func handedWarning(_ m: OrgMove, world: OrgMoveWorld, now: Date) -> String? {
        let map = OrgMoveHolderMap(world: world)
        var back = 0, both = 0
        for l in m.allLines where !l.isOrgLine {
            let s = status(l, in: m, map: map, now: now)
            if s.kind == .backOnPerson { back += 1 }
            if s.kind == .onBoth { both += 1 }
        }
        let person = m.personName.isEmpty ? "這位同仁" : m.personName
        if back > 0 { return "有 \(back) 項又回到\(person)身上" }
        if both > 0 { return "有 \(both) 項在兩個人身上" }
        return nil
    }

    /// 卡住時那一條上的按鈕
    static func blockActions(_ k: OrgMoveDueBlock) -> [OrgMoveHintAction] {
        switch k {
        case .deptMoved: return [.skipOrg, .cancel]
        case .deptGone: return [.pickDept, .skipOrg]
        case .personGone: return [.cancel]
        }
    }

    /// 接手的人那一條（〔11/1 一起做〕排好的）：「11/1 起會從王小明接手 6 項」（灰）
    static func plannedReceiverHints(personId: UUID, book: OrgMoveBook) -> [OrgMoveHint] {
        var out: [OrgMoveHint] = []
        for m in book.live where m.isPlanned && m.personId != personId {
            var n = 0
            for l in m.allLines where !l.isOrgLine && (l.lineKind != nil || l.isLiveCustom) {
                if receiver(l, in: m).id == personId { n += 1 }
            }
            guard n > 0 else { continue }
            let from = m.personName.isEmpty ? "這位同仁" : m.personName
            out.append(OrgMoveHint(moveId: m.id, text: "\(shortDay(m.effectiveKey)) 起會從\(from)接手 \(n) 項",
                                   badge: nil, warning: nil, isReceiver: true, muted: true))
        }
        return out
    }

    // MARK: 排好之後多了幾件（judge §5-15）

    /// 原人身上、單上沒有的待辦與週報（排好之後才多出來的）。部門還沒改的：照現在算；改好了的：只認改部門那一刻記下的（lateRefIds）。
    /// 不算：做完的、機台警報（跟著機台）、兼任的（跟著兼任）、缺失（只能跟著本人）、過了報告日的週報。
    /// 回傳〔加進交接單〕要加的那幾列（排好的＝還沒決定；交出去了的＝跟著，之後在交接單〔改交給…〕）
    static func lateLines(_ m: OrgMove, world: OrgMoveWorld, now: Date) -> [OrgMoveLine] {
        guard !m.isUndone, m.deletedAt == nil, let sub = world.sub(m.personId) else { return [] }
        // [v25.592 轉組織 v1b 驗證] 只換廠區的單（kind "plant"）本來就不列待辦、週報（buildLines 只有 .move 才列）：
        // 不然這位同仁手上所有待辦、週報都算成「排好之後多了 N 件」，生效那天還全記進 lateRefIds。要退回這一件：刪這一行
        guard m.kind == OrgMoveKind.move.rawValue else { return [] }
        let only: Set<UUID>? = m.orgPending ? nil : Set(m.lateRefIds ?? [])
        if let o = only, o.isEmpty { return [] }
        var known = Set<UUID>()
        for l in m.allLines {
            if let r = l.refId { known.insert(r) }
            if let i = l.itemId { known.insert(i) }
        }
        let action: String? = m.isPlanned ? nil : OrgMoveAction.follow.rawValue
        var out: [OrgMoveLine] = []
        let tasks = sub.tasks.filter { t in
            !t.isCompleted && t.equipmentLink == nil && !t.isDereliction && !known.contains(t.id)
                && !(t.sideRoleLink.map { world.sideRoleAlive($0) } ?? false)
                && (only?.contains(t.id) ?? true)
        }.sorted { a, b in (a.dueDate ?? a.date) < (b.dueDate ?? b.date) }
        for t in tasks {
            out.append(OrgMoveLine(kind: OrgMoveLineKind.task.rawValue, refId: t.id, holderId: m.personId,
                                   title: taskTitle(t), dueKey: t.dueDate.map { dayKey($0) }, action: action,
                                   addedLate: true))
        }
        let reps = sub.weeklyReports.filter { r in
            !r.isCompleted && r.date >= now && !known.contains(r.id) && (only?.contains(r.id) ?? true)
        }.sorted { $0.date < $1.date }
        for r in reps {
            out.append(OrgMoveLine(kind: OrgMoveLineKind.report.rawValue, refId: r.id, holderId: m.personId,
                                   title: reportTitle(r), dueKey: dayKey(r.date), action: action, addedLate: true))
        }
        return out
    }

    /// 「排好之後多了 2 件（先跟著王小明）」
    static func lateNote(_ count: Int, person: String) -> String {
        "排好之後多了 \(count) 件（先跟著\(person)）"
    }

    // MARK: 到期那天

    /// 到了（生效日今天或以前）、部門還沒改
    static func isDue(_ m: OrgMove, todayKey: String) -> Bool {
        m.orgPending && m.effectiveKey <= todayKey
    }

    /// 到了的那幾張（照生效日、建的時間排）
    static func dueMoves(book: OrgMoveBook, todayKey: String) -> [OrgMove] {
        book.live.filter { isDue($0, todayKey: todayKey) }.sorted { a, b in
            if a.effectiveKey != b.effectiveKey { return a.effectiveKey < b.effectiveKey }
            return (a.createdAt ?? Date.distantPast) < (b.createdAt ?? Date.distantPast)
        }
    }

    /// 到了卻不能改的原因（judge §3.5「生效前你又改了部門」、§5-6「新部門被刪了」）。nil＝可以改
    static func dueBlock(_ m: OrgMove, world: OrgMoveWorld) -> (kind: OrgMoveDueBlock, text: String)? {
        let person = m.personName.isEmpty ? "這位同仁" : m.personName
        guard let sub = world.sub(m.personId) else {
            return (.personGone, "找不到\(person)了（可能被刪了），這張單只能取消")
        }
        // [v25.593 轉組織 v2] 調出也改部門（m.changesDept）。要退回這一件：改回 `m.kind == OrgMoveKind.move.rawValue && …`
        let changesDept = m.changesDept
        guard changesDept else { return nil }
        let toText = sideText(OrgMoveSide(deptId: m.to.deptId, deptLabel: m.to.deptLabel), world: world)
        if world.dept(m.to.deptId) == nil {
            return (.deptGone, "\(toText)已經刪掉了，要改去哪個部門？")
        }
        if sub.departmentId != m.from.deptId {
            let cur = world.deptShort(sub.departmentId)
            let now0 = cur.isEmpty ? (sub.department.isEmpty ? "別的部門" : sub.department) : cur
            return (.deptMoved, "\(person)現在已經在\(now0)了，這張單還要做嗎？")
        }
        return nil
    }

    /// 「王小明 製造一課 → 設備課（P1 → P2）」
    static func dueTitle(_ m: OrgMove, world: OrgMoveWorld) -> String {
        let person = m.personName.isEmpty ? "這位同仁" : m.personName
        // [v25.593 轉組織 v2]「王小明 製造一課 → 品保課（調出）」「王小明 離職（製造一課）」。要退回這一件：刪這一行
        if let t = leavingDueTitle(m, world: world) { return t }
        let f = sideText(OrgMoveSide(deptId: m.from.deptId, deptLabel: m.from.deptLabel), world: world)
        let t = sideText(OrgMoveSide(deptId: m.to.deptId, deptLabel: m.to.deptLabel), world: world)
        let pf = m.from.plant ?? ""
        let pt = m.to.plant ?? ""
        let deptPart = (m.keepDept == true || f == t) ? "" : " \(f) → \(t)"
        let plantPart = pf == pt ? "" : (deptPart.isEmpty ? " \(pf) → \(pt)" : "（\(pf) → \(pt)）")
        let body = deptPart + plantPart
        return person + (body.isEmpty ? " 交接（部門照舊）" : body)
    }

    /// 改好（或卡住）之後「今天生效」那一列
    static func dueResult(_ m: OrgMove, applied: Bool, world: OrgMoveWorld, reminderCount: Int) -> OrgMoveDueResult {
        let title = dueTitle(m, world: world)
        if !applied, let b = dueBlock(m, world: world) {
            return OrgMoveDueResult(moveId: m.id, personId: m.personId, applied: false, title: title, detail: b.text,
                                    blockKind: b.kind.rawValue, birthdayOffer: false, reminderCount: 0)
        }
        let by = dayText(m.handoverByKey ?? handoverByKey(effectiveKey: m.effectiveKey))
        // [v25.593 轉組織 v2] 調出、離職、退休：「✓ 已收進「已轉出」」。要退回這一件：改回只有後面那一行
        let head = m.isLeaving ? "✓ 已收進「已轉出」"
            : (m.timingValue == .together ? "✓ 交接、部門都做好了" : "✓ 已換好")
        let detail = applied ? "\(head)・交接完成日 \(by)" : "部門、廠區還沒改"
        let offer = applied && m.retitleBirthday == true && birthdayOffer(m, world: world)
        return OrgMoveDueResult(moveId: m.id, personId: m.personId, applied: applied, title: title, detail: detail,
                                blockKind: nil, birthdayOffer: offer, reminderCount: applied ? reminderCount : 0)
    }

    /// 「今天生效」那一列的灰字：生效那天沒打開 App、晚幾天才改的（judge §7 v1b【待確認】：11/1 生效、11/3 才開）。當天改的＝nil
    static func dueLateText(_ m: OrgMove) -> String? {
        guard let a = m.appliedAt, dayKey(a) > m.effectiveKey else { return nil }
        let e = shortDay(m.effectiveKey)
        return "\(e) 生效・\(shortDay(dayKey(a))) 打開 App 才改（生效日照記 \(e)）"
    }

    /// 精靈完成畫面的大字與下面那一行（排好的、交出去了還沒改部門的；全部做好的＝「交接單做好了」、沒有那一行）
    static func doneTexts(_ m: OrgMove) -> (headline: String, sub: String?) {
        let d = shortDay(m.effectiveKey)
        // [v25.592 轉組織 v1b 裁定]〔照舊（只交接）〕寫「部門照舊」、只換廠區寫「換廠區」（同 timingOptions）。
        // 要退回這一件：刪 keep、plant 與兩個 if 裡的分支，改回原本的兩行 return
        let keep = m.keepDept == true
        let plant = m.kind == OrgMoveKind.plant.rawValue
        // [v25.593 轉組織 v2] 調出、離職、退休的完成畫面字（OrgMoveOut.swift）。要退回這一件：刪這一行
        if let t = leavingDoneTexts(m) { return t }
        if m.isPlanned {
            if keep { return ("交接單排好了", "\(d) 以前什麼都不動；\(d) 打開 App 時交接、部門照舊（在你自己的手機上）") }
            if plant { return ("交接單排好了", "\(d) 以前什麼都不動；\(d) 打開 App 時一起交接、換廠區（在你自己的手機上）") }
            return ("交接單排好了", "\(d) 以前什麼都不動；\(d) 打開 App 時一起交接、改部門（在你自己的手機上）")
        }
        if m.isHanded {
            if keep { return ("事情交出去了", "部門照舊（\(d) 生效）") }
            if plant { return ("事情交出去了", "廠區 \(d) 才換（\(d) 打開 App 時在你自己的手機上換）") }
            return ("事情交出去了", "部門、廠區、名片、組織圖 \(d) 才改（\(d) 打開 App 時在你自己的手機上改）")
        }
        return ("交接單做好了", nil)
    }

    /// 部屬總覽最上面「今天生效」卡（到了、部門還沒改的；自動改好的不在這裡）
    static func dueRows(book: OrgMoveBook, world: OrgMoveWorld, todayKey: String) -> [OrgMoveDueRow] {
        dueMoves(book: book, todayKey: todayKey).map { m -> OrgMoveDueRow in
            let title = dueTitle(m, world: world) + "・\(shortDay(m.effectiveKey)) 生效"
            if let b = dueBlock(m, world: world) {
                return OrgMoveDueRow(moveId: m.id, personId: m.personId, title: title, detail: b.text, blocked: true,
                                     actions: blockActions(b.kind))
            }
            return OrgMoveDueRow(moveId: m.id, personId: m.personId, title: title, detail: "部門、廠區還沒改",
                                 blocked: false, actions: [.applyNow])
        }
    }

    // MARK: 改、取消（生效前）

    /// 〔取消這張單〕可以按嗎（部門還沒改的）
    static func canCancel(_ m: OrgMove) -> Bool {
        m.orgPending && !m.isUndone
    }

    /// 〔取消這張單〕的確認框
    static func cancelAsk(_ m: OrgMove, map: OrgMoveHolderMap, now: Date) -> OrgMoveCancelAsk {
        let title = "取消 \(shortDay(m.effectiveKey)) 的轉組織？"
        if m.isPlanned {
            return OrgMoveCancelAsk(title: title, message: "這張單什麼都還沒動，取消了就不見了。",
                                    confirmLabel: "取消這張單", takeBackLabel: nil, keepLabel: nil)
        }
        // 「還沒做完的 7 項」＝交出去、要做的（待辦、警報、議程、週報、兼任）還沒做完的；機台、會議、班「交了就好」不算（同四格）
        var given = 0, open = 0
        for l in m.allLines where !l.isOrgLine && l.lineKind != nil && l.state != OrgMoveLineState.undone.rawValue {
            guard receiver(l, in: m).id != nil else { continue }
            given += 1
            let handOnly = l.kind == OrgMoveLineKind.equipment.rawValue || l.kind == OrgMoveLineKind.meeting.rawValue
                || l.kind == OrgMoveLineKind.shifts.rawValue
            if handOnly { continue }
            let k = status(l, in: m, map: map, now: now).kind
            if k == .open || k == .backOnPerson || k == .onBoth { open += 1 }
        }
        return OrgMoveCancelAsk(title: title, message: "已經交出去的 \(given) 項要怎麼辦？部門、廠區不會改（本來就還沒改）。",
                                confirmLabel: nil, takeBackLabel: "拿回來（還沒做完的 \(open) 項）",
                                keepLabel: "留給接手的人")
    }

    /// 取消、只做交接時寫進單上的那一句
    static func cancelNoteText(_ m: OrgMove, world: OrgMoveWorld, now: Date, skip: Bool) -> String {
        // [v25.593 轉組織 v2] 「11/1 起離職」「11/1 起退休」也換成「要」。要退回這一件：刪後面兩個 replacingOccurrences
        let head = pendingHead(m, world: world).replacingOccurrences(of: " 起調", with: " 要調")
            .replacingOccurrences(of: " 起換到", with: " 要換到")
            .replacingOccurrences(of: " 起離職", with: " 要離職")
            .replacingOccurrences(of: " 起退休", with: " 要退休")
        if skip { return "原本 \(head)；生效時部門已經不是單上寫的，部門那段沒做" }
        return "原本 \(head)，\(shortDay(dayKey(now))) 取消了調動；交出去的照舊"
    }

    /// 〔改生效日〕那一頁下面那一行
    static func rescheduleNote(_ m: OrgMove, newKey: String, todayKey: String) -> String {
        let d = shortDay(newKey)
        if newKey <= todayKey {
            return m.isPlanned ? "選了今天或以前：按〔改好了〕就馬上交接、改部門" : "選了今天或以前：按〔改好了〕就馬上改部門"
        }
        if m.isPlanned { return "\(d) 一起做；在那之前什麼都不動" }
        return "已經交出去的照舊；部門 \(d) 才改。已經交出去的會議、班照原本的 \(shortDay(m.effectiveKey)) 切"
    }

    /// 精靈一打開：這位已經有一張排好、部門還沒改的
    static func plannedPrompt(personId: UUID, book: OrgMoveBook) -> OrgMovePlannedPrompt? {
        let list = book.live.filter { $0.personId == personId && $0.orgPending }
        guard let m = list.max(by: { ($0.createdAt ?? Date.distantPast) < ($1.createdAt ?? Date.distantPast) }) else { return nil }
        let person = m.personName.isEmpty ? "這位同仁" : m.personName
        return OrgMovePlannedPrompt(moveId: m.id, title: "\(person)已經排了 \(shortDay(m.effectiveKey)) 轉組織",
                                    message: "一位同仁同時只能有一張排好的。要打開那張改，還是取消那張重排？")
    }

    // MARK: 名單、組織圖、部門頁

    /// 部屬名單那一列右邊的小膠囊「11/1 起 設備課」（只換廠區＝「11/1 起 P2」；部門照舊的交接＝「11/1 交接」）
    static func plannedCapsuleText(personId: UUID) -> String? {
        guard let p = OrgMoveIndex.plannedByPerson[personId] else { return nil }
        let d = shortDay(p.effectiveKey)
        if p.kind == OrgMoveKind.plant.rawValue { return "\(d) 起 \(p.toPlant)" }
        // [v25.593 轉組織 v2]「11/1 離職」「11/1 退休」「11/1 調出」（調出到別的部門寫部門：「11/1 起 品保課」）。要退回這一件：刪這三行
        if p.kind == OrgMoveKind.resign.rawValue { return "\(d) 離職" }
        if p.kind == OrgMoveKind.retire.rawValue { return "\(d) 退休" }
        if p.kind == OrgMoveKind.out.rawValue, p.keepDept || p.toDeptId == p.fromDeptId { return "\(d) 調出" }
        if p.keepDept || p.toDeptId == p.fromDeptId { return "\(d) 交接" }
        return "\(d) 起 \(labelShort(p.toDeptLabel))"
    }

    /// 組織圖、部門人員名字後面的小字「11/1 調設備課」（只換廠區＝「11/1 換到 P2」；部門照舊＝nil）
    static func plannedOrgNote(personId: UUID) -> String? {
        guard let p = OrgMoveIndex.plannedByPerson[personId] else { return nil }
        let d = shortDay(p.effectiveKey)
        if p.kind == OrgMoveKind.plant.rawValue { return "\(d) 換到 \(p.toPlant)" }
        // [v25.593 轉組織 v2]「11/1 離職」「11/1 退休」（組織圖名字後面的小字；調出照「11/1 調品保課」）。要退回這一件：刪這兩行
        if p.kind == OrgMoveKind.resign.rawValue { return "\(d) 離職" }
        if p.kind == OrgMoveKind.retire.rawValue { return "\(d) 退休" }
        if p.keepDept || p.toDeptId == p.fromDeptId { return nil }
        return "\(d) 調\(labelShort(p.toDeptLabel))"
    }

    /// 「EQ — 設備課」→「設備課」
    static func labelShort(_ label: String) -> String {
        if let r = label.range(of: " — ") { return String(label[r.upperBound...]) }
        return label
    }

    /// 部門頁最下面「異動」：這個部門進出的交接單（judge §4.8；排好的、交出去了、改好了；取消、復原的不列）
    static func deptMoveRows(deptId: UUID, book: OrgMoveBook, world: OrgMoveWorld) -> [OrgMoveDeptRow] {
        var out: [OrgMoveDeptRow] = []
        // [v25.593 轉組織 v2] 調出（改部門的、部門照舊的）、離職、退休也列在舊部門那頁（「11/1 王小明 調出到 品保課」「11/1 王小明 離職」）。
        // 要退回這一件：條件改回 `m.kind == OrgMoveKind.move.rawValue && m.keepDept != true && m.from.deptId != m.to.deptId`、刪 verb
        for m in book.live where !m.isUndone && (m.changesDept || m.isLeaving) {
            let person = m.personName.isEmpty ? "這位同仁" : m.personName
            let d = shortDay(m.effectiveKey)
            if m.from.deptId == deptId {
                let to = sideText(OrgMoveSide(deptId: m.to.deptId, deptLabel: m.to.deptLabel), world: world)
                let tail: String
                if m.isPlanned {
                    tail = "（排好了）"
                } else {
                    tail = "（交出去 \(handedCounts(m).given) 項）"
                }
                let verb = deptRowVerb(m, to: to)
                out.append(OrgMoveDeptRow(moveId: m.id, title: "\(d) \(person) \(verb)\(tail)", incoming: false,
                                          effectiveKey: m.effectiveKey))
            } else if m.to.deptId == deptId {
                let from = sideText(OrgMoveSide(deptId: m.from.deptId, deptLabel: m.from.deptLabel), world: world)
                let tail = m.orgPending ? "（排好了）" : ""
                out.append(OrgMoveDeptRow(moveId: m.id, title: "\(d) \(person) 從 \(from) 調來\(tail)", incoming: true,
                                          effectiveKey: m.effectiveKey))
            }
        }
        return out.sorted { a, b in a.effectiveKey != b.effectiveKey ? a.effectiveKey > b.effectiveKey : a.title < b.title }
    }

    /// 刪部門的確認框多一句（judge §5-6）：「有 1 張排好的交接單要調到這裡」（沒有＝nil）
    static func deptDeleteNote(deptId: UUID, book: OrgMoveBook) -> String? {
        let n = book.live.filter { $0.orgPending && $0.to.deptId == deptId && $0.from.deptId != deptId }.count
        return n > 0 ? "有 \(n) 張排好的交接單要調到這裡（刪掉後，那幾張到生效日會問你要改去哪個部門）" : nil
    }

    /// 組織頁直接改部門時先問（judge §4.1）：「王小明是你的部屬，手上還有 9 件沒做完。」（沒有還沒做完的也問：只寫前半句）
    static func directDeptChangeMessage(personId: UUID, world: OrgMoveWorld) -> String {
        let person = world.name(personId)
        guard let sub = world.sub(personId) else { return "\(person)是你的部屬。" }
        // 沒做完的待辦（機台警報跟著機台，不另外算）＋還沒交的週報＋負責的機台（judge §4.1：王小明 9 件）
        let ownedIds = Set(world.equipment.filter { $0.ownerId == personId }.map(\.id))
        let tasks = sub.tasks.filter { t in
            if t.isCompleted { return false }
            guard let link = t.equipmentLink else { return true }
            return !ownedIds.contains(link.equipmentId)
        }
        let open = tasks.count + sub.weeklyReports.filter { !$0.isCompleted }.count + ownedIds.count
        if open == 0 { return "\(person)是你的部屬。用轉組織可以排生效日、留一張交接單。" }
        return "\(person)是你的部屬，手上還有 \(open) 件沒做完。用轉組織可以排生效日、交接。"
    }

    // MARK: 〔11/1 一起做〕到期那天套用前重算（judge §3.5、§5-36）

    /// 照那天的資料重算：已經逾期的新截止日（套用那天與生效日取晚的＋7 天、遇六日挪週一；警報任務＝今天＋3 天）、
    /// 會議與班的切點（交接那天）、班那一列的標題。你選的照留
    static func refreshForApply(_ m: OrgMove, world: OrgMoveWorld, now: Date) -> OrgMove {
        guard let sub = world.sub(m.personId) else { return m }
        let today = dayKey(now)
        let cut = cutKey(effectiveKey: m.effectiveKey, todayKey: today)
        var out = m
        var lines = m.allLines
        for i in lines.indices {
            let l = lines[i]
            if l.kind == OrgMoveLineKind.task.rawValue || l.kind == OrgMoveLineKind.alarmTask.rawValue {
                guard l.lineLock != .dereliction, let t = sub.tasks.first(where: { $0.id == l.refId }) else { continue }
                let overdue = t.dueDate.map { $0 < now } ?? false
                if !overdue {
                    lines[i].newDueKey = nil
                } else if l.kind == OrgMoveLineKind.alarmTask.rawValue {
                    lines[i].newDueKey = newAlarmDueKey(todayKey: today)
                } else {
                    lines[i].newDueKey = newDueKey(effectiveKey: m.effectiveKey, todayKey: today)
                }
            } else if l.kind == OrgMoveLineKind.meeting.rawValue {
                lines[i].dueKey = cut
            } else if l.kind == OrgMoveLineKind.shifts.rawValue {
                let list = shiftsAfter(sub, cutKey: cut)
                if let first = list.first {
                    lines[i].title = shiftsTitle(list)
                    lines[i].dueKey = dayKey(first.date)
                }
            }
        }
        out.lines = lines
        return out
    }

    /// 交接單那一列：〔11/1 一起做〕套用那天才逾期、拿到新截止日的（「11/2 套用時已逾期，改成 11/9」judge §3.5）
    static func lateAtApplyText(_ line: OrgMoveLine, move: OrgMove) -> String? {
        guard move.timingValue == .together, line.wasOverdue == true, let nk = line.newDueKey,
              let a = move.appliedAt else { return nil }
        return "\(shortDay(dayKey(a))) 套用時已逾期，改成 \(shortDay(nk))"
    }
}

// MARK: - 到期那天打開 App：三個條件都成立才自動改部門

/// 生效那天打開 App（冷啟動、回前景、拉完 iCloud）時看一次到期的交接單（judge §7 v1b、§3.5）。
/// 只在主執行緒用（LifeGoodApp、編輯頁的 onAppear／onDisappear、通知都在主執行緒）。
/// 隱私：這裡什麼通知都不發（v3 才有），「今天生效」那張只在 App 裡。
final class OrgMoveDueCenter: ObservableObject {
    static let shared = OrgMoveDueCenter()

    /// 「今天生效」那張（LifeGoodApp 用 .sheet(item:) 跳）
    @Published var notice: OrgMoveDueNotice?

    private weak var life: LifeStore?
    private var started = false
    /// 這一輪 iCloud 拉取成功的時間（CloudSyncManager 拉完發 .cloudSyncDidFinishPull）
    private var lastPullOK: Date?
    /// 開著的部屬／組織人員編輯頁（AddSubordinateView、OrgPersonEditor 的 onAppear／onDisappear）
    private var editorsOpen = 0
    /// 等編輯頁關掉再看一次
    private var waitingEditors = false
    /// 還沒跳出來的那幾張（上面有別的畫面、開場還沒結束）
    private var pendingResults: [OrgMoveDueResult] = []
    private var showTries = 0
    private var earliestShow = Date.distantPast
    private var observer: NSObjectProtocol?

    private init() {}

    /// 冷啟動（LifeGoodApp .task 最前面，第一個 await 之前）：掛好「這一輪拉完了」的監聽；這台沒開 iCloud 同步就馬上看一次
    func start(life: LifeStore) {
        self.life = life
        guard !started else { return }
        started = true
        earliestShow = Date().addingTimeInterval(4)   // 開場謝幕、「本次更新」先跳完
        observer = NotificationCenter.default.addObserver(forName: .cloudSyncDidFinishPull, object: nil,
                                                          queue: .main) { [weak self] note in
            let ok = (note.userInfo?["ok"] as? Bool) ?? false
            guard ok else { return }
            self?.lastPullOK = Date()
            self?.check()
        }
        check()
    }

    /// 回前景（LifeGoodApp scenePhase .active）：剛拉過（2 分鐘內成功）或沒開同步就看一次；不然等這一輪拉完的通知
    func appBecameActive() {
        check()
        retryShow()
    }

    /// 部屬／組織人員編輯頁打開（onAppear）
    func editorOpened() {
        editorsOpen += 1
    }

    /// 部屬／組織人員編輯頁關掉（onDisappear）：都關了、剛才因為開著沒做的，再看一次
    func editorClosed() {
        editorsOpen = max(0, editorsOpen - 1)
        guard editorsOpen == 0, waitingEditors else { return }
        waitingEditors = false
        DispatchQueue.main.async { [weak self] in self?.check() }
    }

    /// 三個條件：不是加入別人共享的那支、這一輪 iCloud 拉成功（或這台沒開同步）、沒有編輯頁開著
    private var pullOK: Bool {
        guard CloudSyncManager.shared.isEnabled else { return true }
        guard let t = lastPullOK else { return false }
        return Date().timeIntervalSince(t) < 120
    }

    /// 看一次到期的（自動做；只做部門那幾格＋〔11/1 一起做〕的整張；行事曆、提醒事項不碰）
    func check(now: Date = Date()) {
        guard let store = life else { return }
        guard !CloudKitManager.shared.isShareParticipant else { return }
        let today = OrgMovePlan.dayKey(now)
        guard !OrgMovePlan.dueMoves(book: store.orgMoves, todayKey: today).isEmpty else { return }
        guard pullOK else { return }
        guard editorsOpen == 0 else {
            waitingEditors = true
            return
        }
        let results = store.applyDueOrgMoves(now: now, auto: true).filter { $0.applied }
        guard !results.isEmpty else { return }
        enqueue(results)
    }

    /// 你按〔現在套用〕〔只做交接〕之後要跳的那張（卡片、總覽、交接單頁自己用 .sheet(item:) 跳；這支只給 LifeGoodApp 自動那條用）
    private func enqueue(_ results: [OrgMoveDueResult]) {
        for r in results where !pendingResults.contains(where: { $0.moveId == r.moveId }) {
            pendingResults.append(r)
        }
        showTries = 0
        retryShow()
    }

    /// 上面沒有別的畫面（sheet、alert）、開場過了才跳；不然 1.5 秒後再試（最多 40 次；下次回前景再試）
    private func retryShow() {
        guard !pendingResults.isEmpty, notice == nil else { return }
        let wait = earliestShow.timeIntervalSinceNow
        if wait > 0 || somethingPresented() {
            guard showTries < 40 else { return }
            showTries += 1
            let delay = max(1.5, wait)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.retryShow() }
            return
        }
        notice = OrgMoveDueNotice(results: pendingResults, auto: true)
        pendingResults = []
    }

    /// 「今天生效」那張關掉
    func dismissNotice() {
        notice = nil
    }

    private func somethingPresented() -> Bool {
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene, ws.activationState == .foregroundActive else { continue }
            if ws.keyWindow?.rootViewController?.presentedViewController != nil { return true }
        }
        return false
    }
}
