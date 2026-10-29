import Foundation

// MARK: - [v25.591 轉組織 v1a-2] 會議、議程、班、兼任：清單、預設、字、狀態（OrgMovePlan 的延伸）
//（orgmove/judge.md §3.2 會議／議程／班／兼任那幾列、§3.8、§3.9、§4.3、§4.4、§4.5、§4.10、§5-20、§8 風險 6～8、§11.6；
//  orgmove/build/v1a-2/brief.md §2-2；sim_v1a-2.py 一個函式一個函式對照）
//
// 畫面、套用、sim 吃同一支：字都在這裡組好，畫面只排版（body 裡不寫長運算式、不自己再篩一次資料）。
// • 「交接那天」＝生效日與今天取晚的那天（v1a 生效日只能今天或以前：今天以前已經開過的會、上過的班照原本記的）。
// • 固定會議不整場搬（以前的掛名分、議程分留原人）：〔照舊〕〔最後一場〕〔交給…〕＝舊的到交接那天前一天結束、新的在對方名下接著開，
//   新會議名稱拿掉人名（「王小明 週會」→「週會」：會議名稱就是通知標題、今天時間軸、手錶時間軸的字，App 不自己把名字寫上鎖定畫面）。
// • 議程留在原本那場會議，只換負責人；沒指派的寫上接手的人（沒指派的做完算會議主人）；別人會議裡的那項預設交回會議主人。
// • 班：同一天同一班搬給接手的人；撞班逐天問（預設〔改成…〕；這位同仁那天是休、時差＝〔這天清掉〕）；被蓋掉的那格存起來。
// • 兼任：有連結的（自動建的分身、拉進來的任務或議程）一律到兼任換人（連兼任負責人一起換），預設〔照舊〕，〔全部交給〕不動它。
// 字的規矩：不用「他／她」，寫名字或「這位同仁」。

/// 一場固定會議在「交接那天」前後的樣子（清單灰字、確認頁、套用、交接單都用這一份）
struct OrgMoveMeetingFacts {
    /// 有週期
    var isRecurring = false
    /// 名稱像一對一（1on1、面談…）：分享文字不寫
    var isOneOnOne = false
    /// 「每週二 14:00」
    var schedule = ""
    /// 交接那天以前最後一場（沒取消的；實際開會的時間）
    var last: Date?
    /// 那一場的原定時間（議程搬進去的那一場的鍵）
    var lastScheduled: Date?
    /// 交接那天（含）以後第一場（沒取消的；實際開會的時間）
    var next: Date?
    /// 交接那天（含）以後第一個規則日（新會議從這一場開始；那一場被取消了也從它算，覆寫才對得上）
    var firstRuleDate: Date?
    /// 交接那天（含）以後、有議程的覆寫場次（原定時間、幾項）
    var futureWithItems: [OrgMoveSessionCount] = []
    /// 交接那天（含）以後、沒有議程的覆寫場次（加開、改期、取消、只改了提醒）
    var futureEmpty: [OrgMoveSessionCount] = []
    /// 交接那天（含）以後還有沒有場次（沒有就不列成一列）
    var runsAfterCut = false
}

/// 一場覆寫場次（原定時間、議程幾項、是不是加開的）
struct OrgMoveSessionCount: Equatable {
    let scheduled: Date
    let count: Int
    let isAdHoc: Bool
}

/// 撞班的一天（第 ② 步只展開這幾天；確認頁一天一行）
struct OrgMoveShiftConflict: Identifiable, Equatable {
    /// 「2026-11-04」
    let day: String
    /// 「11/4（三）」
    let dayText: String
    /// 這位同仁那天的班（「大夜」）
    let mineLabel: String
    /// 接手的人那天原本的班（「日值班」）
    let theirsLabel: String
    /// "overwrite"／"drop"／"<部屬 id>"（沒選過＝預設）
    let choice: String
    /// 「⚠ 11/4（三）林志豪已經排了日值班」
    let warning: String
    /// 選了之後的那一行（「改成大夜：林志豪那天的日值班要另外找人」）
    let note: String
    /// 三顆的字：〔改成大夜〕〔這天清掉〕〔這天交給別人…〕
    let overwriteLabel: String
    let dropLabel: String
    let otherLabel: String
    var id: String { day }
}

extension OrgMovePlan {

    // MARK: 交接那天

    /// 交接那天＝生效日與今天取晚的（v1a 生效日只能今天或以前：今天以前已經開過的會、上過的班照原本記的）
    static func cutKey(effectiveKey: String, todayKey: String) -> String {
        max(effectiveKey, todayKey)
    }

    /// 草稿的交接那天（第 ② 步、第 ③ 步）
    static func draftCutKey(_ draft: OrgMoveDraft, now: Date) -> String {
        cutKey(effectiveKey: dayKey(draft.effective), todayKey: dayKey(now))
    }

    /// 套用過的單：生效日與按確認那天取晚的（還沒套用＝今天）
    static func cutKey(_ move: OrgMove, now: Date) -> String {
        let at: String = (move.handedAt ?? move.appliedAt).map { dayKey($0) } ?? dayKey(now)
        return max(move.effectiveKey, at)
    }

    // MARK: 會議

    private static let meetingWeekdayChars = ["日", "一", "二", "三", "四", "五", "六"]

    /// 「每週二 14:00」「隔週一、四 08:30」「每天 08:30」「每月 6 日 14:00」；不重複的「11/6（五）14:00」
    static func meetingSchedule(_ m: SubordinateMeeting) -> String {
        let c = calendar.dateComponents([.hour, .minute, .weekday, .day], from: m.date)
        let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        guard let r = m.rule else { return dayText(dayKey(m.date)) + " " + time }
        switch r.frequency {
        case .daily:
            return "每天 " + time
        case .weekly, .biweekly:
            let wds: [Int] = r.weekdays.isEmpty ? [c.weekday ?? 1] : r.weekdays.sorted()
            let names = wds.map { meetingWeekdayChars[min(max($0 - 1, 0), 6)] }.joined(separator: "、")
            return (r.frequency == .weekly ? "每週" : "隔週") + names + " " + time
        case .monthly:
            return "每月 \(c.day ?? 1) 日 " + time
        }
    }

    /// 這場會議在交接那天前後的樣子
    static func meetingFacts(_ m: SubordinateMeeting, cutKey: String) -> OrgMoveMeetingFacts {
        var f = OrgMoveMeetingFacts()
        f.isRecurring = m.rule != nil
        f.isOneOnOne = SubExportComposer.isOneOnOneName(m.topic)
        f.schedule = meetingSchedule(m)
        guard let cut = date(fromKey: cutKey) else { return f }
        let from = calendar.date(byAdding: .day, value: -100, to: cut) ?? cut
        let horizon = calendar.date(byAdding: .day, value: 120, to: cut) ?? cut
        let occ = m.expandedOccurrences(from: from, horizon: horizon)
        var lastOcc: ResolvedMeetingOccurrence?
        for o in occ where !o.isCancelled && o.date < cut {
            if let l = lastOcc, l.date >= o.date { continue }
            lastOcc = o
        }
        f.last = lastOcc?.date
        f.lastScheduled = lastOcc?.scheduledDate
        f.next = occ.filter { !$0.isCancelled && $0.date >= cut }.map(\.date).min()
        f.firstRuleDate = occ.filter { !$0.isAdHoc && $0.scheduledDate >= cut }.map(\.scheduledDate).min()
        let future = m.occurrences.filter { $0.scheduledDate >= cut }.sorted { $0.scheduledDate < $1.scheduledDate }
        for o in future {
            let s = OrgMoveSessionCount(scheduled: o.scheduledDate, count: o.items.count, isAdHoc: o.isAdHoc)
            if o.items.isEmpty { f.futureEmpty.append(s) } else { f.futureWithItems.append(s) }
        }
        if let r = m.rule {
            let open = r.endDate.map { $0 >= cut } ?? true
            f.runsAfterCut = open && (f.firstRuleDate != nil || !future.isEmpty)
        } else {
            f.runsAfterCut = m.date >= cut || m.occurrences.contains { $0.effectiveDate >= cut }
        }
        return f
    }

    /// 新會議的名稱：拿掉任何部屬、組織人員、名片的名字，不換成任何人（judge §1.4-5、第 4 題）。
    /// 「王小明 週會」→「週會」、「王小明的週會」→「週會」、「王小明 1on1」→「1on1」；拿光了＝「部屬會議」（同會議通知沒名稱時的字）
    static func topicWithoutNames(_ topic: String, world: OrgMoveWorld) -> String {
        var raw: [String] = world.subordinates.map(\.name)
        raw.append(contentsOf: world.orgPeople.map(\.name))
        raw.append(contentsOf: world.businessCards.map(\.name))
        var set = Set<String>()
        for n in raw {
            let t = n.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count >= 2 { set.insert(t) }
        }
        let names = set.sorted { a, b in a.count != b.count ? a.count > b.count : a < b }
        var t = topic
        for n in names {
            t = t.replacingOccurrences(of: n + "的", with: " ")
            t = t.replacingOccurrences(of: n, with: " ")
        }
        let parts = t.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        // 名字拿掉之後頭尾剩下的頓號、逗號一起拿掉（「陳怡君、王小明 對焦」→「對焦」）
        let edge = CharacterSet(charactersIn: "、，,・/／&＆+＋").union(.whitespacesAndNewlines)
        let out = parts.joined(separator: " ").trimmingCharacters(in: edge)
        return out.isEmpty ? "部屬會議" : out
    }

    /// 這一列新會議要叫什麼（你改過的照你的；沒改過＝原本的名稱拿掉人名）
    static func newSeriesTopic(_ line: OrgMoveLine, world: OrgMoveWorld) -> String {
        let mine = (line.newTopic ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return mine.isEmpty ? topicWithoutNames(line.title, world: world) : mine
    }

    /// 這位同仁名下、交接那天（含）以後還會開的會議（照 sub.meetings 的順序）＋每場的議程（含別人會議裡交給這位同仁的）。
    /// withAgenda＝false（只換廠區）只列會議
    static func meetingAndAgendaLines(personId: UUID, sub: Subordinate, owned: [ManagedEquipment], cutKey: String,
                                      withAgenda: Bool, world: OrgMoveWorld) -> [OrgMoveLine] {
        let ownedIds = Set(owned.map(\.id))
        var out: [OrgMoveLine] = []
        for m in sub.meetings {
            let f = meetingFacts(m, cutKey: cutKey)
            if f.runsAfterCut {
                let topic = m.topic.trimmingCharacters(in: .whitespacesAndNewlines)
                let linked: UUID? = m.linkedEquipmentIds.first(where: { ownedIds.contains($0) })
                out.append(OrgMoveLine(kind: OrgMoveLineKind.meeting.rawValue, refId: m.id, parentId: linked,
                                       holderId: personId, title: topic.isEmpty ? "未命名會議" : topic,
                                       dueKey: cutKey, action: OrgMoveAction.follow.rawValue))
            }
            guard withAgenda else { continue }
            let ctxs = m.itemContexts.filter { !$0.item.isCompleted }.sorted { a, b in
                a.sessionDate != b.sessionDate ? a.sessionDate < b.sessionDate : a.item.id.uuidString < b.item.id.uuidString
            }
            for ctx in ctxs {
                if let back = ctx.item.sideRoleLink, world.sideRoleAlive(back) { continue }   // 兼任那種另外一列
                let content = ctx.item.content.trimmingCharacters(in: .whitespacesAndNewlines)
                let mentions = mentionedEquipment(content, owned: owned) != nil
                out.append(OrgMoveLine(kind: OrgMoveLineKind.agenda.rawValue, refId: ctx.item.id, parentId: m.id,
                                       holderId: personId, title: content.isEmpty ? "未命名議程" : content,
                                       dueKey: dayKey(ctx.sessionDate),
                                       action: mentions ? nil : OrgMoveAction.follow.rawValue))
            }
        }
        guard withAgenda else { return out }
        // 別人會議裡、負責人是這位同仁的（三種 id：部屬、組織人員、名片）：預設交回會議主人
        let mine = personIds(personId, world: world)
        for other in world.subordinates where other.id != personId {
            for m in other.meetings {
                let ctxs = m.itemContexts.filter { c in
                    !c.item.isCompleted && c.item.assigneeIds.contains(where: { mine.contains($0) })
                }.sorted { a, b in
                    a.sessionDate != b.sessionDate ? a.sessionDate < b.sessionDate : a.item.id.uuidString < b.item.id.uuidString
                }
                for ctx in ctxs {
                    if let back = ctx.item.sideRoleLink, world.sideRoleAlive(back) { continue }
                    let content = ctx.item.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    out.append(OrgMoveLine(kind: OrgMoveLineKind.agenda.rawValue, refId: ctx.item.id, parentId: m.id,
                                           holderId: other.id, title: content.isEmpty ? "未命名議程" : content,
                                           dueKey: dayKey(ctx.sessionDate), action: OrgMoveAction.give.rawValue,
                                           toId: other.id, toName: world.name(other.id)))
                }
            }
        }
        return out
    }

    /// 這位同仁的三種 id（部屬、連到的組織人員、那位組織人員的名片）：議程負責人用
    static func personIds(_ personId: UUID, world: OrgMoveWorld) -> Set<UUID> {
        var out: Set<UUID> = [personId]
        if let op = world.orgPerson(linkedTo: personId) {
            out.insert(op.id)
            if let cid = op.linkedBusinessCardId { out.insert(cid) }
        }
        return out
    }

    /// 議程內容提到這位同仁要交的機台（機台名稱裡有數字的那一段，例「蝕刻機 E-03」的「E-03」）：預設〔還沒決定〕，其他議程預設〔照舊〕。
    /// 跟「連到要交的機台的待辦預設跟著機台」同一個想法：機台的事多半跟著機台交出去（brief §1-4 取捨）
    static func mentionedEquipment(_ content: String, owned: [ManagedEquipment]) -> ManagedEquipment? {
        let text = content.lowercased()
        guard !text.isEmpty else { return nil }
        for e in owned {
            let tokens = e.name.components(separatedBy: CharacterSet(charactersIn: " 　・、/"))
            for tk in tokens {
                let t = tk.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard t.count >= 2, t.rangeOfCharacter(from: .decimalDigits) != nil else { continue }
                if text.contains(t) { return e }
            }
        }
        return nil
    }

    /// 兼任的議程（拉進兼任的那幾項）：自己會議裡的全部、別人會議裡這位同仁是兼任負責人的。兼任待辦重複的只列一次（seen）
    static func sideRoleAgendaLines(personId: UUID, sub: Subordinate, world: OrgMoveWorld,
                                    seen: inout Set<UUID>) -> [OrgMoveLine] {
        var out: [OrgMoveLine] = []
        var taken = seen
        func add(_ ctx: SubordinateMeeting.ItemContext, meeting m: SubordinateMeeting, holder: UUID) {
            guard let back = ctx.item.sideRoleLink, world.sideRoleAlive(back), !taken.contains(back.taskId) else { return }
            taken.insert(back.taskId)
            let content = ctx.item.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let due: String? = sideRoleTask(back, world: world)?.dueDate.map { dayKey($0) }
            out.append(OrgMoveLine(kind: OrgMoveLineKind.sideRole.rawValue, refId: back.taskId, itemId: ctx.item.id,
                                   parentId: back.roleId, holderId: holder,
                                   title: content.isEmpty ? "未命名議程" : content, dueKey: due,
                                   action: OrgMoveAction.follow.rawValue, meetingId: m.id))
        }
        for m in sub.meetings {
            for ctx in m.itemContexts where !ctx.item.isCompleted { add(ctx, meeting: m, holder: personId) }
        }
        for other in world.subordinates where other.id != personId {
            for m in other.meetings {
                for ctx in m.itemContexts where !ctx.item.isCompleted {
                    guard let back = ctx.item.sideRoleLink, sideRoleAssigns(back, person: personId, world: world) else { continue }
                    add(ctx, meeting: m, holder: other.id)
                }
            }
        }
        seen = taken
        return out
    }

    /// 兼任待辦本身
    static func sideRoleTask(_ back: SideRoleBackLink, world: OrgMoveWorld) -> SideRoleTask? {
        world.sideRoles.first(where: { $0.id == back.roleId })?.sideRoleTasks?.first(where: { $0.id == back.taskId })
    }

    /// [v25.591 轉組織 v1a-2 驗證] 兼任那一列（任務那種）的標題。App 自動建的分身（兼任那邊 isAutoCreated 的連結）topic 一律是
    /// 兼任名稱（syncSideRoleTaskLinksBody 寫的「尾牙籌備」），標題寫那件事（分身的 content＝兼任待辦的內容「尾牙場控彩排」），
    /// 不然清單、交接單、分享、接手那一區都只看得到「尾牙籌備（兼任「尾牙籌備」）」。你從部屬這邊拉進兼任的任務照任務自己的標題。
    /// 要退回這一件：刪這支，buildLines 的兼任那一列 title 改回 taskTitle(t)
    static func sideRoleLineTitle(_ t: SubordinateTask, back: SideRoleBackLink, world: OrgMoveWorld) -> String {
        let links: [SideRoleTaskLink] = sideRoleTask(back, world: world)?.links ?? []
        let isClone = links.contains { $0.kind == .task && $0.isAutoCreated && $0.itemId == t.id }
        guard isClone else { return taskTitle(t) }
        let c = t.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return c.isEmpty ? taskTitle(t) : c
    }

    /// 這則兼任待辦的負責人裡有沒有連到這位部屬的成員（同 LifeStore.sideRoleAssigns）
    static func sideRoleAssigns(_ back: SideRoleBackLink, person: UUID, world: OrgMoveWorld) -> Bool {
        guard let role = world.sideRoles.first(where: { $0.id == back.roleId }),
              let task = role.sideRoleTasks?.first(where: { $0.id == back.taskId }) else { return false }
        let mids = Set((role.sideRoleMembers ?? []).filter { $0.linkedPersonId == person }.map(\.id))
        return (task.assigneeIds ?? []).contains(where: { mids.contains($0) })
    }

    // MARK: 班

    /// 交接那天（含）以後的班（照日子排）
    static func shiftsAfter(_ sub: Subordinate, cutKey: String) -> [SubordinateShift] {
        sub.shifts.filter { dayKey($0.date) >= cutKey }.sorted { $0.date < $1.date }
    }

    /// 「11/2～11/8 的班 7 格（大夜 6）」（有上下班時間的班別才寫在括號裡，照第一次出現的順序）
    static func shiftsTitle(_ list: [SubordinateShift]) -> String {
        guard let first = list.first, let last = list.last else { return "以後的班" }
        let a = shortDay(dayKey(first.date))
        let b = shortDay(dayKey(last.date))
        let range = a == b ? a : "\(a)～\(b)"
        var order: [ShiftType] = []
        var counts: [ShiftType: Int] = [:]
        for s in list where s.type.hasWorkTime {
            if counts[s.type] == nil { order.append(s.type) }
            counts[s.type, default: 0] += 1
        }
        let detail = order.map { "\($0.shortLabel) \(counts[$0] ?? 0)" }.joined(separator: "、")
        return "\(range) 的班 \(list.count) 格" + (detail.isEmpty ? "" : "（\(detail)）")
    }

    /// 班那一列（沒有交接那天以後的班＝nil）。預設：換了部門或廠區＝還沒決定；同部門同廠區（〔照舊（只交接）〕）＝跟著
    static func shiftsLine(personId: UUID, sub: Subordinate, cutKey: String, defaultFollow: Bool) -> OrgMoveLine? {
        let list = shiftsAfter(sub, cutKey: cutKey)
        guard let first = list.first else { return nil }
        return OrgMoveLine(kind: OrgMoveLineKind.shifts.rawValue, refId: nil, holderId: personId,
                           title: shiftsTitle(list), dueKey: dayKey(first.date),
                           action: defaultFollow ? OrgMoveAction.follow.rawValue : nil)
    }

    /// 撞班那天沒選過時的預設：這位同仁那天有上班＝〔改成…〕（"overwrite"）；那天是休、時差＝〔這天清掉〕（"drop"）
    static func defaultShiftChoice(_ mine: ShiftType) -> String {
        mine.hasWorkTime ? "overwrite" : "drop"
    }

    /// 交給接手的人時撞到的那幾天（接手的人那天已經有班）；只有〔交給…〕才有
    static func shiftConflicts(_ line: OrgMoveLine, personName: String, world: OrgMoveWorld,
                               cutKey: String) -> [OrgMoveShiftConflict] {
        guard line.kind == OrgMoveLineKind.shifts.rawValue, line.action == OrgMoveAction.give.rawValue,
              let to = line.toId, let me = world.sub(line.holderId), let them = world.sub(to) else { return [] }
        var theirs: [String: ShiftType] = [:]
        for s in them.shifts { theirs[dayKey(s.date)] = s.type }
        let toName = line.toName ?? world.name(to)
        var out: [OrgMoveShiftConflict] = []
        for s in shiftsAfter(me, cutKey: cutKey) {
            let d = dayKey(s.date)
            guard let t = theirs[d] else { continue }
            let choice = line.days?[d] ?? defaultShiftChoice(s.type)
            let note: String
            switch choice {
            case "overwrite":
                note = "改成\(s.type.shortLabel)：\(toName)那天的\(t.rawValue)要另外找人"
            case "drop":
                note = "這天清掉：\(toName)照原本的\(t.rawValue)，\(personName)那天的\(s.type.rawValue)不交出去"
            default:
                let other = UUID(uuidString: choice)
                let n = world.name(other)
                let busy = other.flatMap { o in world.sub(o)?.shifts.first(where: { dayKey($0.date) == d }) }
                note = busy.map { "這天交給 \(n)（\(n)那天的\($0.type.rawValue)要另外找人）" } ?? "這天交給 \(n)"
            }
            out.append(OrgMoveShiftConflict(day: d, dayText: dayText(d), mineLabel: s.type.shortLabel,
                                            theirsLabel: t.rawValue, choice: choice,
                                            warning: "⚠ \(dayText(d))\(toName)已經排了\(t.rawValue)",
                                            note: note, overwriteLabel: "改成\(s.type.shortLabel)",
                                            dropLabel: "這天清掉", otherLabel: "這天交給別人…"))
        }
        return out
    }

    /// 撞班那一天選了什麼（"overwrite"／"drop"／部屬 id 字串）
    static func setShiftDay(_ lines: inout [OrgMoveLine], lineId: UUID, day: String, choice: String, now: Date) {
        guard let i = lines.firstIndex(where: { $0.id == lineId }) else { return }
        var d = lines[i].days ?? [:]
        d[day] = choice
        lines[i].days = d
        lines[i].updatedAt = now
    }

    /// 確認頁的那幾行（只有〔改成…〕會蓋掉別人的班）：「11/4 林志豪原本的日值班換成大夜：那天日值班要另外找人」
    static func shiftOverwriteLines(_ line: OrgMoveLine, personName: String, world: OrgMoveWorld,
                                    cutKey: String) -> [String] {
        let toName = line.toName ?? world.name(line.toId)
        return shiftConflicts(line, personName: personName, world: world, cutKey: cutKey)
            .filter { $0.choice == "overwrite" }
            .map { "\(shortDay($0.day)) \(toName)原本的\($0.theirsLabel)換成\($0.mineLabel)：那天\($0.theirsLabel)要另外找人" }
    }

    // MARK: 一列的選項、膠囊、灰字（OrgMovePlan.choices／capsuleText／reasonLines 交過來）

    /// 會議那一列的會議（還在原人身上的那一份）
    static func meeting(_ line: OrgMoveLine, world: OrgMoveWorld) -> SubordinateMeeting? {
        guard let mid = line.refId else { return nil }
        if let m = world.sub(line.holderId)?.meetings.first(where: { $0.id == mid }) { return m }
        for s in world.subordinates {
            if let m = s.meetings.first(where: { $0.id == mid }) { return m }
        }
        return nil
    }

    /// 〔最後一場〕的字：「10/27 是最後一場」（交接那天以前一場都沒有＝「11/1 起不再開」）
    static func meetingEndLabel(_ f: OrgMoveMeetingFacts, cutKey: String) -> String {
        if let l = f.last { return "\(shortDay(dayKey(l))) 是最後一場" }
        return "\(shortDay(cutKey)) 起不再開"
    }

    /// 會議那一列連到要交的機台、那台交給誰（「E-03 交給陳怡君」）
    static func meetingEquipmentReceiver(_ line: OrgMoveLine, in lines: [OrgMoveLine]) -> (id: UUID, name: String)? {
        guard let eid = line.parentId,
              let eq = lines.first(where: { $0.kind == OrgMoveLineKind.equipment.rawValue && $0.refId == eid }),
              eq.lineAction == .give, let to = eq.toId else { return nil }
        return (to, eq.toName ?? "")
    }

    static func meetingChoices(_ line: OrgMoveLine, in lines: [OrgMoveLine], world: OrgMoveWorld) -> [OrgMoveChoice] {
        var out = [OrgMoveChoice(action: .follow, label: "照舊", needsPerson: false)]
        guard let m = meeting(line, world: world) else { return out }
        let cut = line.dueKey ?? dayKey(Date())
        let f = meetingFacts(m, cutKey: cut)
        let preset = meetingEquipmentReceiver(line, in: lines)
        if f.isRecurring {
            out.append(OrgMoveChoice(action: .end, label: meetingEndLabel(f, cutKey: cut), needsPerson: false))
            if let p = preset {
                out.append(OrgMoveChoice(action: .newSeries, label: "交給 \(p.name)（新會議接著開）",
                                         needsPerson: false, toId: p.id, toName: p.name))
            }
            out.append(OrgMoveChoice(action: .newSeries, label: "交給…（舊的結束、新的接著開）", needsPerson: true))
        } else {
            if let p = preset {
                out.append(OrgMoveChoice(action: .give, label: "交給 \(p.name)", needsPerson: false, toId: p.id, toName: p.name))
            }
            out.append(OrgMoveChoice(action: .give, label: "交給…（整場交出去）", needsPerson: true))
        }
        return out
    }

    static func agendaChoices(_ line: OrgMoveLine, personId: UUID, world: OrgMoveWorld) -> [OrgMoveChoice] {
        let follow = OrgMoveChoice(action: .follow, label: "照舊", needsPerson: false)
        let pick = OrgMoveChoice(action: .give, label: "改由…", needsPerson: true)
        guard let h = line.holderId, h != personId else {
            return [follow, pick, OrgMoveChoice(action: .drop, label: "不要了", needsPerson: false)]
        }
        // 別人會議裡的：第一顆交回會議主人（〔不要了〕不給：那是別人的會議）
        let n = world.name(h)
        return [OrgMoveChoice(action: .give, label: "改由 \(n)（會議主人）", needsPerson: false, toId: h, toName: n),
                pick, follow]
    }

    static func shiftsChoices(personName: String) -> [OrgMoveChoice] {
        [OrgMoveChoice(action: .give, label: "交給…", needsPerson: true),
         OrgMoveChoice(action: .follow, label: "跟著\(personName)", needsPerson: false),
         OrgMoveChoice(action: .drop, label: "這幾天清掉", needsPerson: false)]
    }

    static func sideRoleChoices() -> [OrgMoveChoice] {
        [OrgMoveChoice(action: .follow, label: "照舊", needsPerson: false),
         OrgMoveChoice(action: .give, label: "到兼任換人…", needsPerson: true)]
    }

    /// 四種的膠囊字（OrgMovePlan.capsuleText 交過來；nil＝不是這四種）
    static func moreCapsuleText(_ line: OrgMoveLine, personName: String, world: OrgMoveWorld) -> String? {
        guard let k = line.lineKind else { return nil }
        let a = line.lineAction
        switch k {
        case .meeting:
            switch a {
            case .some(.end):
                guard let m = meeting(line, world: world) else { return "最後一場" }
                let cut = line.dueKey ?? dayKey(Date())
                return meetingEndLabel(meetingFacts(m, cutKey: cut), cutKey: cut)
            case .some(.newSeries):
                let cut = line.dueKey ?? dayKey(Date())
                let start = meeting(line, world: world).flatMap { meetingFacts($0, cutKey: cut).firstRuleDate }
                let from = start.map { "（\(shortDay(dayKey($0))) 起）" } ?? ""
                return "交給 \(line.toName ?? "")" + from
            case .some(.give):
                return "交給 \(line.toName ?? "")"
            case .none:
                return "還沒決定"
            default:
                return "照舊"
            }
        case .agenda:
            switch a {
            case .some(.give): return "改由 \(line.toName ?? "")"
            case .some(.drop): return "不要了"
            case .none: return "還沒決定"
            default: return "照舊"
            }
        case .shifts:
            switch a {
            case .some(.give): return "交給 \(line.toName ?? "")"
            case .some(.drop): return "這幾天清掉"
            case .none: return "還沒決定"
            default: return "跟著\(personName)"
            }
        case .sideRole:
            switch a {
            case .some(.give): return "到兼任換人 → \(line.toName ?? "")"
            case .none: return "還沒決定"
            default: return "照舊"
            }
        default:
            return nil
        }
    }

    /// 第 ② 步一列的標題（議程寫哪一場：「10/27：E-03 備品清單更新」「林志豪的製造一課晨會：P1 夜班人力表」；其他照 title）
    static func rowTitle(_ line: OrgMoveLine, personId: UUID, world: OrgMoveWorld) -> String {
        guard line.kind == OrgMoveLineKind.agenda.rawValue else { return line.title }
        if let h = line.holderId, h != personId {
            let topic = world.sub(h)?.meetings.first(where: { $0.id == line.parentId })?.topic
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let where0 = topic.isEmpty ? "\(world.name(h))的會議" : "\(world.name(h))的\(topic)"
            return "\(where0)：\(line.title)"
        }
        return "\(shortDay(line.dueKey))：\(line.title)"
    }

    /// 四種的灰字（OrgMovePlan.reasonLines 交過來；nil＝不是這四種）
    static func moreReasonLines(_ line: OrgMoveLine, in lines: [OrgMoveLine], personId: UUID?, personName: String,
                                world: OrgMoveWorld, now: Date) -> [String]? {
        guard let k = line.lineKind else { return nil }
        switch k {
        case .meeting:
            return meetingReasons(line, in: lines, world: world)
        case .agenda:
            return agendaReasons(line, personId: personId ?? line.holderId, personName: personName, world: world)
        case .shifts:
            switch line.lineAction {
            case .some(.give):
                let n = shiftConflicts(line, personName: personName, world: world,
                                       cutKey: line.dueKey ?? dayKey(now)).count
                let head = "同一天同一班換到\(line.toName ?? "")名下；時差、休照搬"
                return n > 0 ? [head, "撞到 \(n) 天：\(line.toName ?? "")那天已經有班（下面選）"] : [head]
            case .some(.drop):
                return ["這幾天的班清掉（班表上空著，要另外排）"]
            case .some(.follow):
                return ["照舊排在\(personName)名下"]
            default:
                return ["選了接手的人：同一天同一班換過去"]
            }
        case .sideRole:
            return sideRoleReasons(line, personName: personName, world: world, now: now)
        default:
            return nil
        }
    }

    private static func meetingReasons(_ line: OrgMoveLine, in lines: [OrgMoveLine], world: OrgMoveWorld) -> [String] {
        guard let m = meeting(line, world: world) else { return ["找不到這場會議了"] }
        let cut = line.dueKey ?? dayKey(Date())
        let f = meetingFacts(m, cutKey: cut)
        var first = f.schedule
        if let l = f.last { first += "・上一場 \(shortDay(dayKey(l)))" }
        if let n = f.next { first += "・下一場 \(shortDay(dayKey(n)))" }
        var out = [first]
        if let eid = line.parentId {
            let eq = world.equipmentName(eid)
            if let r = meetingEquipmentReceiver(line, in: lines) {
                out.append("連到\(eq)（\(eq) 交給\(r.name)）")
            } else {
                out.append("連到\(eq)")
            }
        }
        switch line.lineAction {
        case .some(.end):
            out.append(contentsOf: meetingEndNotes(f, cutKey: cut))
        case .some(.newSeries), .some(.give):
            out.append("新會議名稱：\(newSeriesTopic(line, world: world))（這個名稱會出現在通知與手錶上，建議不要放人名）")
            if line.lineAction == .newSeries, let start = f.firstRuleDate,
               !(f.futureWithItems.isEmpty && f.futureEmpty.isEmpty) {
                out.append("\(shortDay(dayKey(start))) 以後排好的場次與議程一起搬到新會議")
            }
        default:
            break
        }
        return out
    }

    /// 〔最後一場〕多講的那幾行：「11/10 加開的那一場也會取消（那場沒有議程）」「11/3 那場的 2 項議程會搬到 10/27 最後一場」
    static func meetingEndNotes(_ f: OrgMoveMeetingFacts, cutKey: String) -> [String] {
        var out: [String] = []
        if f.futureEmpty.count == 1, let e = f.futureEmpty.first {
            let what = e.isAdHoc ? "加開的那一場" : "那一場"
            out.append("\(shortDay(dayKey(e.scheduled))) \(what)也會取消（那場沒有議程）")
        } else if f.futureEmpty.count > 1 {
            let days = f.futureEmpty.map { shortDay(dayKey($0.scheduled)) }.joined(separator: "、")
            out.append("\(days) 那 \(f.futureEmpty.count) 場也會取消（沒有議程）")
        }
        for s in f.futureWithItems {
            if let l = f.last {
                out.append("\(shortDay(dayKey(s.scheduled))) 那場的 \(s.count) 項議程會搬到 \(shortDay(dayKey(l))) 最後一場")
            } else {
                out.append("\(shortDay(dayKey(s.scheduled))) 那場有 \(s.count) 項議程：交接那天以前沒有場次可以搬，那一場照樣留著")
            }
        }
        return out
    }

    private static func agendaReasons(_ line: OrgMoveLine, personId: UUID?, personName: String,
                                      world: OrgMoveWorld) -> [String] {
        guard let h = line.holderId,
              let m = world.sub(h)?.meetings.first(where: { $0.id == line.parentId }),
              let item = m.allItems.first(where: { $0.id == line.refId }) else { return ["找不到這項議程了"] }
        let topic = m.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let isMine = personId == nil || h == personId
        let owned = world.equipment.filter { $0.ownerId == h }
        var out: [String] = []
        let unassigned = item.assigneeIds.isEmpty
        if !isMine {
            out.append("在\(world.name(h))的「\(topic.isEmpty ? "會議" : topic)」裡・\(shortDay(line.dueKey)) 那場")
        } else {
            let who = unassigned ? "沒指派負責人" : "負責人 \(personName)"
            out.append((topic.isEmpty ? "會議" : topic) + "・" + who)
        }
        if isMine, let e = mentionedEquipment(line.title, owned: owned) {
            out.append("提到\(world.equipmentName(e.id))")
        }
        if line.lineAction == .give, unassigned, let n = line.toName {
            out.append("沒指派負責人：會寫上\(n)")
        }
        return out
    }

    private static func sideRoleReasons(_ line: OrgMoveLine, personName: String, world: OrgMoveWorld, now: Date) -> [String] {
        let role = world.sideRoleName(line.parentId)
        var first = "兼任「\(role)」"
        if let d = line.dueKey { first += "・\(shortDay(d)) 到期" }
        if line.meetingId != nil { first += "・會議議程" }
        switch line.lineAction {
        case .some(.give):
            return [first, "這件也是兼任「\(role)」的待辦：會一起把兼任負責人換成 \(line.toName ?? "")"]
        default:
            return [first, "照舊：兼任跨部門，\(personName)還是「\(role)」的人"]
        }
    }

    // MARK: 交接單頁：四種的狀態（照現在的資料算；OrgMovePlan.status 交過來）

    static func moreStatus(_ line: OrgMoveLine, in move: OrgMove, map: OrgMoveHolderMap, now: Date) -> OrgMoveLineStatus? {
        guard let k = line.lineKind else { return nil }
        let person = move.personName.isEmpty ? "這位同仁" : move.personName
        switch k {
        case .meeting: return meetingStatus(line, move: move, map: map, person: person, now: now)
        case .agenda: return agendaStatus(line, move: move, map: map, person: person)
        case .shifts: return shiftsStatus(line, move: move, map: map, person: person, now: now)
        case .sideRole: return sideRoleStatus(line, move: move, map: map, person: person)
        default: return nil
        }
    }

    private static func st(_ kind: OrgMoveLineStatus.Kind, _ mark: String, _ text: String, holder: UUID? = nil,
                           fix: OrgMoveLineStatus.Fix? = nil, fixLabel: String? = nil) -> OrgMoveLineStatus {
        OrgMoveLineStatus(kind: kind, mark: mark, text: text, holderId: holder, fix: fix, fixLabel: fixLabel)
    }

    private static func meetingStatus(_ line: OrgMoveLine, move: OrgMove, map: OrgMoveHolderMap,
                                      person: String, now: Date) -> OrgMoveLineStatus {
        guard let mid = line.refId else { return st(.missing, "・", "找不到這場會議了") }
        let old = map.meetings[mid]
        switch line.lineAction {
        case .some(.end):
            guard let m = old else { return st(.missing, "・", "找不到這場會議了（可能被刪了）") }
            let undo = OrgMoveMeetingUndo.decode(line.removedJSON)
            let set = undo?.setEndDate
            if let e = m.rule?.endDate, let s = set, e <= s {
                let lastText = undo?.lastScheduled.map { "\(shortDay(dayKey($0))) 是最後一場" } ?? "之後不再開"
                return st(.ended, "✓", lastText, holder: move.personId)
            }
            return st(.backOnPerson, "⚠", "這場會議又沒有結束日了（可能是還沒更新的 iPad 存回來的）",
                      holder: move.personId, fix: .redo, fixLabel: "再結束一次")
        case .some(.newSeries):
            guard let nid = line.newId, let to = line.toId else { return st(.follow, "・", "跟著\(person)") }
            let topic = line.newTopic ?? line.title
            guard let h = map.meetingHolders[nid] else {
                return st(.backOnPerson, "⚠", "新會議「\(topic)」不見了（可能是還沒更新的 iPad 存回來的）",
                          holder: move.personId, fix: .redo, fixLabel: "再交一次")
            }
            if h != to { return st(.elsewhere, "・", "新會議現在在 \(map.name(h)) 名下", holder: h) }
            if let m = old, m.rule?.endDate == nil {
                return st(.backOnPerson, "⚠", "\(line.title)又沒有結束日了（可能是還沒更新的 iPad 存回來的）",
                          holder: move.personId, fix: .redo, fixLabel: "再交一次")
            }
            let sched = map.meetings[nid].map { meetingSchedule($0) } ?? ""
            let start = map.meetings[nid].map { "（\(shortDay(dayKey($0.date))) 起）" } ?? ""
            return st(.handed, "●", "新會議「\(topic)」・\(sched)\(start)", holder: to)
        case .some(.give):
            guard let to = line.toId else { return st(.follow, "・", "跟著\(person)") }
            guard let h = map.meetingHolders[mid] else { return st(.missing, "・", "找不到這場會議了（可能被刪了）") }
            if h == to { return st(.handed, "●", "在\(map.name(to))名下", holder: to) }
            if h == move.personId {
                return st(.backOnPerson, "⚠", "這場會議又回到\(person)名下（可能是還沒更新的 iPad 存回來的）",
                          holder: h, fix: .redo, fixLabel: "再交一次")
            }
            return st(.elsewhere, "・", "現在在 \(map.name(h)) 名下", holder: h)
        default:
            return st(.follow, "・", "跟著\(person)（照開）", holder: move.personId)
        }
    }

    private static func agendaStatus(_ line: OrgMoveLine, move: OrgMove, map: OrgMoveHolderMap,
                                     person: String) -> OrgMoveLineStatus {
        switch line.lineAction {
        case .some(.drop):
            let fix: OrgMoveLineStatus.Fix? = line.removedJSON != nil ? .putBack : nil
            return st(.dropped, "・", "不要了", fix: fix, fixLabel: fix == nil ? nil : "放回\(person)")
        case .some(.give):
            break
        default:
            return st(.follow, "・", "跟著\(person)", holder: line.holderId)
        }
        guard let iid = line.refId, let c = map.items[iid]?.first else {
            return st(.missing, "・", "找不到這項議程了（可能被刪了）")
        }
        guard let to = line.toId else { return st(.follow, "・", "跟著\(person)") }
        let credit = map.creditedPeople(c)
        if c.item.isCompleted {
            let at = c.item.completedAt.map { shortDay(dayKey($0)) + " 做完" } ?? "做完了"
            let who = credit.first ?? to
            return st(.done, "✓", who == to ? at : "\(map.name(who))\(at)", holder: c.holder)
        }
        let session = "\(c.topic.isEmpty ? "會議" : c.topic)（\(shortDay(dayKey(c.session)))）"
        if credit.contains(to) {
            return st(.open, "○", "在\(session)", holder: c.holder)
        }
        if credit.contains(move.personId) {
            return st(.backOnPerson, "⚠", "這項又回到\(person)身上（可能是還沒更新的 iPad 存回來的）",
                      holder: c.holder, fix: .redo, fixLabel: "再交一次")
        }
        let now0 = credit.first.map { map.name($0) } ?? map.name(c.holder)
        return st(.elsewhere, "・", "現在是 \(now0) 負責", holder: c.holder)
    }

    private static func shiftsStatus(_ line: OrgMoveLine, move: OrgMove, map: OrgMoveHolderMap,
                                     person: String, now: Date) -> OrgMoveLineStatus {
        let today = dayKey(now)
        let cells = line.removedShifts ?? []
        switch line.lineAction {
        case .some(.drop):
            let back = cells.contains { $0.who == move.personId && $0.day >= today }
            let fix: OrgMoveLineStatus.Fix? = back ? .putBack : nil
            return st(.dropped, "・", "這幾天的班清掉了", fix: fix, fixLabel: fix == nil ? nil : "放回\(person)")
        case .some(.give):
            break
        default:
            return st(.follow, "・", "跟著\(person)", holder: move.personId)
        }
        guard let to = line.toId else { return st(.follow, "・", "跟著\(person)") }
        var back = 0
        for c in cells where c.who == move.personId && c.overwritten != true && c.day >= today {
            guard let t = c.to else { continue }
            let theirs = map.shiftDays[t]?[c.day]
            let onPerson = map.shiftDays[move.personId]?[c.day] != nil
            // [v25.591 轉組織 v1a-2 驗證] 接手的人那天又是交接時被蓋掉的那一格（舊 iPad 把整包部屬存回來：11/4 林志豪的日值班回來、
            // 王小明的大夜也回來）也算沒交到，不然照樣寫「● …（11/4 改成大夜）」。要退回這一件：改回 `onPerson && theirs == nil`
            let overwrittenBack = theirs.map { s in
                cells.contains { $0.overwritten == true && $0.who == t && $0.day == c.day && $0.id == s.id }
            } ?? false
            if onPerson && (theirs == nil || overwrittenBack) { back += 1 }
        }
        if back > 0 {
            return st(.backOnPerson, "⚠", "有 \(back) 天的班又回到\(person)身上（可能是還沒更新的 iPad 存回來的）",
                      holder: move.personId, fix: .redo, fixLabel: "再交一次")
        }
        var text = line.title
        let over = cells.filter { $0.overwritten == true }.map { "\(shortDay($0.day)) 改成\(shiftShort(cells, day: $0.day))" }
        if !over.isEmpty { text += "（" + over.joined(separator: "、") + "）" }
        return st(.handed, "●", text, holder: to)
    }

    /// 那一天搬過去的班的短字（「大夜」）
    private static func shiftShort(_ cells: [OrgMoveShiftCell], day: String) -> String {
        guard let c = cells.first(where: { $0.day == day && $0.overwritten != true }),
              let t = ShiftType(rawValue: c.type) else { return "" }
        return t.shortLabel
    }

    private static func sideRoleStatus(_ line: OrgMoveLine, move: OrgMove, map: OrgMoveHolderMap,
                                       person: String) -> OrgMoveLineStatus {
        guard line.lineAction == .give, let to = line.toId else {
            return st(.follow, "・", "照舊（\(person)還是兼任負責人）", holder: move.personId)
        }
        guard let tid = line.refId, let t = map.sideRoleTasks[tid] else {
            return st(.missing, "・", "兼任的這件找不到了（可能被刪了）")
        }
        let holder = map.sideRoleCopies[tid]?.first(where: { $0.holder == to })?.holder
        if t.isCompleted {
            let at = t.completedAt.map { shortDay(dayKey($0)) + " 做完" } ?? "做完了"
            return st(.done, "✓", at, holder: holder ?? to)
        }
        let who = map.sideRoleAssignees[tid] ?? []
        if who.contains(to) && !who.contains(move.personId) {
            let due = t.dueDate.map { "截止 " + shortDay(dayKey($0)) } ?? "沒有截止日"
            return st(.open, "○", "兼任負責人 \(map.name(to))・\(due)", holder: holder ?? to)
        }
        if who.contains(move.personId) && !who.contains(to) {
            return st(.backOnPerson, "⚠", "兼任負責人又是\(person)了（可能是還沒更新的 iPad 存回來的）",
                      holder: move.personId, fix: .redo, fixLabel: "再交一次")
        }
        let names = who.map { map.name($0) }.sorted().joined(separator: "、")
        return st(.elsewhere, "・", names.isEmpty ? "兼任那邊現在沒有負責人" : "兼任負責人現在是 \(names)", holder: holder)
    }

    // MARK: 分享（四種；OrgMovePlan.shareItems 交過來）

    /// 給某一位的會議、議程、班、兼任那幾段（編號接著 n 算）。不寫議程備註、你的備註；一對一的會議與議程只有交出去的那項會出現
    static func moreShareItems(_ mine: [OrgMoveLine], move: OrgMove, map: OrgMoveHolderMap, world: OrgMoveWorld,
                               n: inout Int) -> [String] {
        var out: [String] = []
        let meetings = mine.filter { $0.kind == OrgMoveLineKind.meeting.rawValue }
        let agenda = mine.filter { $0.kind == OrgMoveLineKind.agenda.rawValue }
        let shifts = mine.filter { $0.kind == OrgMoveLineKind.shifts.rawValue }
        let sides = mine.filter { $0.kind == OrgMoveLineKind.sideRole.rawValue }
        if !meetings.isEmpty {
            out.append("會議")
            for l in meetings {
                n += 1
                let nid = l.lineAction == .newSeries ? l.newId : l.refId
                let m = nid.flatMap { map.meetings[$0] }
                let topic = l.lineAction == .newSeries ? (l.newTopic ?? l.title) : (m?.topic ?? l.title)
                var s = "\(n). \(topic)"
                if let m {
                    s += "・" + meetingSchedule(m)
                    if l.lineAction == .newSeries { s += "（\(shortDay(dayKey(m.date))) 起）" }
                }
                out.append(s)
                appendMemo(l, &out)
            }
        }
        if !agenda.isEmpty {
            out.append("會議議程")
            for l in agenda {
                n += 1
                let c = l.refId.flatMap { map.items[$0]?.first }
                let topic = c.map { $0.topic.isEmpty ? "會議" : $0.topic } ?? "會議"
                let day = c.map { shortDay(dayKey($0.session)) } ?? shortDay(l.dueKey)
                out.append("\(n). \(topic)（\(day)）：\(l.title)")
                appendMemo(l, &out)
            }
        }
        if !shifts.isEmpty {
            out.append("班")
            for l in shifts {
                n += 1
                var s = "\(n). \(l.title)"
                let over = (l.removedShifts ?? []).filter { $0.overwritten == true }
                    .map { "\(shortDay($0.day)) 原本的\($0.type)換成\(shiftShort(l.removedShifts ?? [], day: $0.day))" }
                if !over.isEmpty { s += "（" + over.joined(separator: "、") + "）" }
                out.append(s)
                appendMemo(l, &out)
            }
        }
        if !sides.isEmpty {
            out.append("兼任")
            for l in sides {
                n += 1
                var s = "\(n). \(l.title)（兼任「\(world.sideRoleName(l.parentId))」）"
                if let t = l.refId.flatMap({ map.sideRoleTasks[$0] }), let d = t.dueDate { s += "｜截止 \(shortDay(dayKey(d)))" }
                out.append(s)
                appendMemo(l, &out)
            }
        }
        return out
    }

    private static func appendMemo(_ l: OrgMoveLine, _ out: inout [String]) {
        let memo = (l.memo ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !memo.isEmpty { out.append("   備註：\(memo)") }
    }

    /// 整張（給新主管）「跟著王小明的：」那一段要不要寫這一列：一對一的會議、一對一裡的議程不寫（judge §4.10）
    static func shareFollowAllowed(_ l: OrgMoveLine, map: OrgMoveHolderMap) -> Bool {
        switch l.lineKind {
        case .some(.meeting):
            return !SubExportComposer.isOneOnOneName(l.title)
        case .some(.agenda):
            let topic = l.refId.flatMap { map.items[$0]?.first?.topic } ?? ""
            return !SubExportComposer.isOneOnOneName(topic)
        default:
            return true
        }
    }

    // MARK: 復原的確認字（四種；OrgMovePlan.undoPreview 交過來）

    static func moreUndoParts(_ move: OrgMove, map: OrgMoveHolderMap, now: Date) -> [String] {
        let person = move.personName.isEmpty ? "這位同仁" : move.personName
        let today = dayKey(now)
        var out: [String] = []
        for l in move.allLines where l.state != OrgMoveLineState.undone.rawValue {
            switch l.lineKind {
            case .some(.meeting):
                guard let s = moreStatus(l, in: move, map: map, now: now) else { continue }
                if l.lineAction == .end, s.kind == .ended {
                    let back = (OrgMoveMeetingUndo.decode(l.removedJSON)?.removedOccurrences.count ?? 0)
                    out.append("\(l.title)接著開" + (back > 0 ? "（取消的 \(back) 場放回）" : ""))
                } else if l.lineAction == .newSeries, s.kind == .handed, let nid = l.newId, let nm = map.meetings[nid] {
                    let topic = l.newTopic ?? nm.topic
                    if nm.date >= now {
                        out.append("新會議「\(topic)」還沒開過：拿掉，以後的場次搬回\(l.title)")
                    } else {
                        // [v25.591 轉組織 v1a-2 裁定] 復原從「現在」切（驗證修的）：字跟著改「現在起停開、還沒開的場次」。
                        // 要退回這一件：改回「今天起停開，以後的場次搬回」
                        out.append("新會議「\(topic)」已經開過：現在起停開，還沒開的場次搬回\(l.title)")
                    }
                } else if l.lineAction == .give, s.kind == .handed {
                    out.append("\(l.title)搬回\(person)名下")
                }
            case .some(.shifts):
                guard l.lineAction == .give || l.lineAction == .drop else { continue }
                let cells = l.removedShifts ?? []
                let mine = cells.filter { $0.who == move.personId && $0.overwritten != true && $0.day >= today }
                if !mine.isEmpty {
                    let days = mine.map(\.day).sorted()
                    let range = days.count == 1 ? shortDay(days[0]) : "\(shortDay(days[0]))～\(shortDay(days[days.count - 1]))"
                    out.append("\(range) 的班 \(mine.count) 格搬回\(person)")
                }
                for c in cells where c.overwritten == true && c.day >= today {
                    out.append("\(shortDay(c.day)) \(map.name(c.who))原本的\(c.type)放回")
                }
            case .some(.sideRole):
                guard l.lineAction == .give, let s = moreStatus(l, in: move, map: map, now: now), s.kind == .open else { continue }
                out.append("兼任「\(sideRoleNameFromMap(l, map: map))」負責人換回\(person)")
            default:
                continue
            }
        }
        return out
    }

    private static func sideRoleNameFromMap(_ l: OrgMoveLine, map: OrgMoveHolderMap) -> String {
        let n = l.parentId.flatMap { map.sideRoleNames[$0] } ?? ""
        return n.isEmpty ? "兼任職務" : n
    }
}
