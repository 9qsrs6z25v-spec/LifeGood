import Foundation

// MARK: - life 快照的 v5 欄位：部屬今天、廠區、家庭待辦、倒數（小工具 v5，只屬於主 App）
//
// 由 G1 實作，規格見 scratchpad/widgets/v5/brief.md 的 G1-4（主控定案 1–5、19）。
// WidgetSnapshotWriter.lifeSnapshot 呼叫這裡組 WidgetLifeSnapshot 的 hasTeam／team／plantAreas／
// familyTasks／countdowns（型別在共用檔 LifeGood/Shared/WidgetSnapshot.swift）。判斷一律走 TeamDay（部屬總覽同一套）
// 與 CalendarDayItems（我的行事曆同一套）；只讀不寫。
//
// • team（今天、明天各一份）：請假一人一筆（假別用「、」接）、班別（ShiftType.shortLabel，不含「休」、沒人的不放；
//   那一天請假的人不算進班別，同班表格子）、
//   逾期／這一天到期的任務（逾期在前；全部前 20 件＋每廠區前 2 件）、每廠區件數（用全部任務算）、
//   逾期報告數、這一天與隔天生日的部屬。
//   基準時間：今天那一份＝寫快照的當下（跟部屬總覽的紅字同一刻），明天那一份＝明天 00:00。
// • countdowns：60 天內（多帶 1 天）的家人生日、結婚紀念日、兼任職務重要日期，App 算好「下一次那一天 00:00」；
//   2/29 在平年算 2/28（CalendarDayItems.annualOccurrence，我的行事曆的規則）。
//
// @MainActor：CalendarDayItems 是 @MainActor（annualOccurrence、displayName 在那裡）。

@MainActor
enum WidgetLifeExtras {

    /// 一天最多帶幾件任務（再補每個廠區的前 perPlantTasks 件）
    static let maxTasks = 20
    /// 每個廠區至少帶幾件（篩廠區時中型那兩條才不會空掉）
    static let perPlantTasks = 2
    /// 倒數最多帶幾件
    static let maxCountdowns = 12
    /// 比 WidgetCountdown.horizonDays 多 1 天：快照用到明天時也還有完整 60 天
    static let countdownLookaheadDays = WidgetCountdown.horizonDays + 1

    // MARK: - 部屬今天

    /// dayStarts＝[今天 00:00, 明天 00:00]；沒有部屬時每一天都是空的那一份
    static func team(life: LifeStore, dayStarts: [Date], now: Date,
                     calendar cal: Calendar = .current) -> [WidgetTeamDay] {
        let subs: [Subordinate] = life.subordinates
        let areas: [String] = plantAreas(life: life)
        let hasUnassigned: Bool = subs.contains { trim($0.plantArea).isEmpty }
        let areaKeys: [String] = hasUnassigned ? areas + [""] : areas
        // 未完成任務跟哪一天無關：算一次，兩天共用（順序＝部屬總覽「未完成任務」）
        let incomplete: [(sub: Subordinate, task: SubordinateTask)] = TeamDay.incompleteTasks(in: subs)
        var out: [WidgetTeamDay] = []
        for start in dayStarts {
            out.append(teamDay(subs: subs, incomplete: incomplete, areaKeys: areaKeys,
                               day: cal.startOfDay(for: start), now: now, calendar: cal))
        }
        return out
    }

    /// 一個廠區的件數（數的時候用）
    private struct PlantTally {
        var overdue = 0
        var dueToday = 0
        var unfinished = 0
        var reports = 0
    }

    private static func teamDay(subs: [Subordinate],
                                incomplete: [(sub: Subordinate, task: SubordinateTask)],
                                areaKeys: [String],
                                day: Date, now: Date,
                                calendar cal: Calendar) -> WidgetTeamDay {
        let dayEnd: Date = cal.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        // 基準時間（主控定案 2）：今天那一份＝寫的當下，明天那一份＝明天 00:00
        let ref: Date = cal.isDate(day, inSameDayAs: now) ? now : day

        var tallies: [String: PlantTally] = [:]
        var overdueRows: [WidgetTeamTask] = []
        var dueRows: [WidgetTeamTask] = []
        for item in incomplete {
            let area = trim(item.sub.plantArea)
            let isOver = TeamDay.isOverdue(item.task, at: ref)
            let due = TeamDay.dueDay(item.task, calendar: cal)
            let isDue = !isOver && cal.isDate(due, inSameDayAs: day)
            var t = tallies[area] ?? PlantTally()
            t.unfinished += 1
            if isOver { t.overdue += 1 }
            if isDue { t.dueToday += 1 }
            tallies[area] = t
            guard isOver || isDue else { continue }
            let row = taskRow(item.sub, item.task, area: area, due: due, isOverdue: isOver,
                              isDueToday: isDue, day: day, calendar: cal)
            if isOver {
                overdueRows.append(row)
            } else {
                dueRows.append(row)
            }
        }

        // 報告區標「逾期」的（這一週以前、未完成，所有報告類型）
        for r in TeamDay.reports(on: day, in: subs, calendar: cal) where r.status == .overdue {
            let area = trim(r.sub.plantArea)
            var t = tallies[area] ?? PlantTally()
            t.reports += 1
            tallies[area] = t
        }

        var counts: [WidgetTeamCounts] = []
        for area in areaKeys {
            let t = tallies[area] ?? PlantTally()
            counts.append(WidgetTeamCounts(plantArea: area, overdueTasks: t.overdue, dueTodayTasks: t.dueToday,
                                           openTasks: t.unfinished, overdueReports: t.reports))
        }

        let leaveList: [WidgetTeamPerson] = leavePeople(subs: subs, day: day, calendar: cal)
        // 班表格子有請假就只顯示請假（SubordinateRosterView.cell）：請假的人不算進班別人數
        let onLeave: Set<UUID> = Set(leaveList.map { $0.subId })

        return WidgetTeamDay(dayKey: WidgetDateText.dayKey(day),
                             dayStart: day,
                             dayEnd: dayEnd,
                             dateText: WidgetDateText.dayLabel(day),
                             shortDateText: WidgetDateText.shortDate(day),
                             leaves: leaveList,
                             shifts: shiftLists(subs: subs, day: day, onLeave: onLeave, calendar: cal),
                             tasks: keptTasks(overdueRows + dueRows),
                             counts: counts,
                             birthdays: birthdays(subs: subs, day: day, calendar: cal))
    }

    /// 這一天請假的人：一人一筆（照第一筆請假的開始時間），detail＝那個人每一筆的假別時數用「、」接
    private static func leavePeople(subs: [Subordinate], day: Date,
                                    calendar cal: Calendar) -> [WidgetTeamPerson] {
        var order: [UUID] = []
        var whoById: [UUID: Subordinate] = [:]
        var textsById: [UUID: [String]] = [:]
        for item in TeamDay.leaves(on: day, in: subs, calendar: cal) {
            let id = item.sub.id
            if whoById[id] == nil {
                order.append(id)
                whoById[id] = item.sub
            }
            textsById[id, default: []].append(TeamDay.leaveText(item.rec))
        }
        var out: [WidgetTeamPerson] = []
        for id in order {
            guard let sub = whoById[id] else { continue }
            out.append(person(sub, detail: joinedLeaveTexts(textsById[id] ?? [])))
        }
        return out
    }

    /// 「特休、病假 4 小時」。兩筆以上時，沒填假別也沒填時數的那幾筆（「請假」）不重複寫；
    /// 一模一樣的字只寫一次（兩筆重疊的特休不寫成「特休、特休」）；全部都沒填就是一個「請假」
    private static func joinedLeaveTexts(_ texts: [String]) -> String {
        var filled: [String] = []
        for text in texts where text != "請假" && !filled.contains(text) {
            filled.append(text)
        }
        if filled.isEmpty { return "請假" }
        return filled.joined(separator: "、")
    }

    /// 這一天班表上有人的班別（不含「休」），照 ShiftType 順序；每一班的人照部屬清單順序。
    /// onLeave＝這一天請假的部屬：班表格子有請假時只顯示假別、不顯示班別，所以不算進班別（「大夜 3」跟班表那一格對得起來）
    private static func shiftLists(subs: [Subordinate], day: Date, onLeave: Set<UUID>,
                                   calendar cal: Calendar) -> [WidgetTeamShift] {
        var byType: [ShiftType: [WidgetTeamPerson]] = [:]
        for sub in subs where !onLeave.contains(sub.id) {
            guard let type = TeamDay.shift(of: sub, on: day, calendar: cal), type != .restDay else { continue }
            byType[type, default: []].append(person(sub, detail: ""))
        }
        var out: [WidgetTeamShift] = []
        for (order, type) in ShiftType.allCases.enumerated() where type != .restDay {
            guard let people = byType[type], !people.isEmpty else { continue }
            out.append(WidgetTeamShift(label: type.shortLabel, order: order, people: people))
        }
        return out
    }

    /// 一件逾期／這一天到期的任務。逾期天數＝到期那天到這一天差幾個日曆天；差 0 天（今天截止、時間已過）寫「已逾期」
    private static func taskRow(_ sub: Subordinate, _ task: SubordinateTask, area: String, due: Date,
                                isOverdue: Bool, isDueToday: Bool, day: Date,
                                calendar cal: Calendar) -> WidgetTeamTask {
        let days: Int = isOverdue ? max(0, cal.dateComponents([.day], from: due, to: day).day ?? 0) : 0
        let dueText: String
        if isOverdue {
            dueText = days >= 1 ? "逾期 \(days) 天" : "已逾期"
        } else {
            dueText = "今天"
        }
        return WidgetTeamTask(subId: sub.id,
                              taskId: task.id,
                              name: displayName(sub),
                              topic: task.topic.isEmpty ? "未命名任務" : task.topic,
                              dueDay: due,
                              plantArea: area,
                              isOverdue: isOverdue,
                              isDueToday: isDueToday,
                              overdueDays: days,
                              dueText: dueText,
                              link: WidgetLink.teamTask(subId: sub.id, taskId: task.id).absoluteString)
    }

    /// ordered（逾期在前、再這一天到期）照順序走一遍：前 maxTasks 件留下；之後的，那個廠區留下的還不到
    /// perPlantTasks 件也留下。留下的維持 ordered 順序
    private static func keptTasks(_ ordered: [WidgetTeamTask]) -> [WidgetTeamTask] {
        var perPlant: [String: Int] = [:]
        var out: [WidgetTeamTask] = []
        for (index, row) in ordered.enumerated() {
            let kept = perPlant[row.plantArea] ?? 0
            guard index < maxTasks || kept < perPlantTasks else { continue }
            perPlant[row.plantArea] = kept + 1
            out.append(row)
        }
        return out
    }

    /// 這一天（dayOffset 0）與隔天（1）生日的部屬（只算部屬；2/29 在平年算 2/28）
    private static func birthdays(subs: [Subordinate], day: Date,
                                  calendar cal: Calendar) -> [WidgetTeamBirthday] {
        var out: [WidgetTeamBirthday] = []
        for offset in 0...1 {
            guard let d = cal.date(byAdding: .day, value: offset, to: day) else { continue }
            let year = cal.component(.year, from: d)
            for sub in subs {
                guard let bd = sub.birthday else { continue }
                let occ = CalendarDayItems.annualOccurrence(of: bd, year: year, calendar: cal)
                guard cal.isDate(occ, inSameDayAs: d) else { continue }
                out.append(WidgetTeamBirthday(subId: sub.id, name: displayName(sub),
                                              plantArea: trim(sub.plantArea), dayOffset: offset))
            }
        }
        return out
    }

    private static func person(_ sub: Subordinate, detail: String) -> WidgetTeamPerson {
        WidgetTeamPerson(subId: sub.id, name: displayName(sub), plantArea: trim(sub.plantArea), detail: detail)
    }

    /// 名字去頭尾空白；空的寫「未命名」（同部屬總覽）
    private static func displayName(_ sub: Subordinate) -> String {
        let n = trim(sub.name)
        return n.isEmpty ? "未命名" : n
    }

    private static func trim(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 廠區清單

    /// Subordinate.plantArea 去頭尾空白、非空、去重，localizedStandardCompare 排（「P2」排在「P10」前面）
    static func plantAreas(life: LifeStore) -> [String] {
        let set = Set(life.subordinates.map { trim($0.plantArea) }.filter { !$0.isEmpty })
        return set.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // MARK: - 家庭待辦

    /// 每一天：未完成、截止日在這一天的件數，與未完成的總數
    static func familyTasks(life: LifeStore, dayStarts: [Date],
                            calendar cal: Calendar = .current) -> [WidgetFamilyTasksDay] {
        let unfinished: [FamilyTask] = life.familyTasks.filter { !$0.isCompleted }
        var out: [WidgetFamilyTasksDay] = []
        for start in dayStarts {
            let day = cal.startOfDay(for: start)
            let dayEnd: Date = cal.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            let dueCount: Int = unfinished.filter { t in
                t.dueDate.map { cal.isDate($0, inSameDayAs: day) } ?? false
            }.count
            out.append(WidgetFamilyTasksDay(dayKey: WidgetDateText.dayKey(day),
                                            dayStart: day,
                                            dayEnd: dayEnd,
                                            dueTodayCount: dueCount,
                                            openCount: unfinished.count))
        }
        return out
    }

    // MARK: - 倒數

    /// 今天到 countdownLookaheadDays 天後（含）的家人生日、結婚紀念日、兼任職務重要日期。
    /// 依（日期、種類優先序、id）排，取前 maxCountdowns 件。點了一律開我的行事曆
    static func countdowns(life: LifeStore, now: Date, calendar cal: Calendar = .current) -> [WidgetCountdown] {
        let today = cal.startOfDay(for: now)
        let last: Date = cal.date(byAdding: .day, value: countdownLookaheadDays, to: today) ?? today
        let link = WidgetLink.today(nil).absoluteString
        var out: [WidgetCountdown] = []

        for m in life.familyMembers {
            if let bd = m.birthday {
                let next = nextOccurrence(of: bd, from: today, calendar: cal)
                if next <= last {
                    let name = CalendarDayItems.displayName(m)
                    let age = cal.component(.year, from: next) - cal.component(.year, from: bd)
                    let title = age > 0 ? "\(name) \(age) 歲生日" : "\(name) 生日"
                    out.append(WidgetCountdown(id: "bd-\(m.id.uuidString)", kind: .birthday, title: title,
                                               date: next, icon: "birthday.cake.fill", link: link))
                }
            }
            if m.role == .spouse, let md = m.marriageDate {
                let next = nextOccurrence(of: md, from: today, calendar: cal)
                if next <= last {
                    out.append(WidgetCountdown(id: "anniv-\(m.id.uuidString)", kind: .anniversary,
                                               title: "結婚紀念日", date: next, icon: "heart.fill", link: link))
                }
            }
        }

        // 兼任職務的重要日期（同 CalendarDayItems.sideRoleItems 的標題）；卸任日不放
        for role in life.sideRoles {
            let roleName = SideRoleFormat.displayName(role)
            for kd in role.sideRoleKeyDates ?? [] {
                let d = cal.startOfDay(for: kd.date)
                guard d >= today, d <= last else { continue }
                let title = kd.title.isEmpty ? roleName : "\(roleName)：\(kd.title)"
                out.append(WidgetCountdown(id: "srkd-\(kd.id.uuidString)", kind: .sideRole, title: title,
                                           date: d, icon: "flag.fill", link: link))
            }
        }

        out.sort { a, b in
            if a.date != b.date { return a.date < b.date }
            if a.kind.priority != b.kind.priority { return a.kind.priority < b.kind.priority }
            return a.id < b.id
        }
        return Array(out.prefix(maxCountdowns))
    }

    /// 生日、紀念日下一次是哪一天（00:00）：今年的還沒過（含今天）用今年的，否則明年的
    private static func nextOccurrence(of date: Date, from today: Date, calendar cal: Calendar) -> Date {
        let year = cal.component(.year, from: today)
        let thisYear = cal.startOfDay(for: CalendarDayItems.annualOccurrence(of: date, year: year, calendar: cal))
        if thisYear >= today { return thisYear }
        return cal.startOfDay(for: CalendarDayItems.annualOccurrence(of: date, year: year + 1, calendar: cal))
    }
}
