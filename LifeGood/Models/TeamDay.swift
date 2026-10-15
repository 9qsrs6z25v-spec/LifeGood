import Foundation

// MARK: - 部屬的「某一天」：請假、班別、任務、報告、生日（小工具 v5，只屬於主 App）
//
// 由 G1 實作，規格見 scratchpad/widgets/v5/brief.md 的 G1-1。
// 從部屬總覽（SubordinateOverviewView）的 todayLeaves／todayTasks／incompleteTasks／displayedReports／
// taskRow 的逾期判斷原樣抽出來；部屬總覽改呼叫這裡、行為不變；life 快照的 team（WidgetLifeExtras）也呼叫這裡，
// 所以小工具的「請假 2」「逾期 2」跟部屬總覽一定是同一個判斷。
// 不是 @MainActor：純函式，只吃 [Subordinate] 與日期。
//
// 四支原本的函式逐字照搬 body，只換名字：visibleSubordinates→subs、selectedDate→day、calendar→cal、
// isSameDay(a, b)→cal.isDate(a, inSameDayAs: b)、weekInterval→weekInterval(for: day, calendar: cal)。
// 回傳的標籤 tuple 型別不變（總覽的呼叫端一個字不用改）。
// 生日不放這裡：要用 CalendarDayItems.annualOccurrence（@MainActor），放 WidgetLifeExtras。

enum TeamDay {

    /// 報告呈現狀態（原 SubordinateOverviewView.ReportStatus，總覽改成 typealias 指過來）
    enum ReportStatus { case overdue, thisWeek, pending, done }

    // MARK: - 當日請假（原 SubordinateOverviewView.todayLeaves）

    /// 這一天請假的紀錄（一筆紀錄一列；同一人同一天兩筆就兩列），依請假開始時間排
    static func leaves(on day: Date, in subs: [Subordinate],
                       calendar cal: Calendar = .current) -> [(sub: Subordinate, rec: SubordinateRecord)] {
        subs.flatMap { sub in
            sub.records
                .filter { $0.type == .leave }
                .filter { rec in
                    let start = rec.date
                    let end = rec.endDate ?? start
                    return day >= cal.startOfDay(for: start)
                        && day < (cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: end)) ?? .distantFuture)
                }
                .map { (sub, $0) }
        }
        .sorted { $0.rec.date < $1.rec.date }
    }

    // MARK: - 報告（原 weekInterval／displayedReports）

    /// 這一天所在的自然週區間 [週起, 下週起)
    static func weekInterval(for day: Date, calendar cal: Calendar = .current) -> DateInterval {
        cal.dateInterval(of: .weekOfYear, for: day)
            ?? DateInterval(start: cal.startOfDay(for: day), duration: 86_400)
    }

    /// 顯示規則：這一週的報告（含已完成）+ 任何未完成的報告（含逾期、未來週）
    /// 排序：未完成優先（逾期最前 → 日期舊到新），其後已完成（日期新到舊）
    static func reports(on day: Date, in subs: [Subordinate],
                        calendar cal: Calendar = .current)
        -> [(sub: Subordinate, report: WeeklyReport, status: ReportStatus)] {
        let wk = weekInterval(for: day, calendar: cal)
        return subs.flatMap { sub in
            sub.weeklyReports.compactMap { r -> (sub: Subordinate, report: WeeklyReport, status: ReportStatus)? in
                let inWeek = wk.contains(r.date)
                if r.isCompleted {
                    return inWeek ? (sub, r, .done) : nil       // 已完成只顯示本週
                }
                if r.date < wk.start { return (sub, r, .overdue) }   // 逾期未完成
                if inWeek            { return (sub, r, .thisWeek) }   // 本週未完成
                return (sub, r, .pending)                            // 未來週、未完成
            }
        }
        .sorted { a, b in
            if a.report.isCompleted != b.report.isCompleted { return !a.report.isCompleted }
            return a.report.isCompleted ? a.report.date > b.report.date
                                        : a.report.date < b.report.date
        }
    }

    // MARK: - 當日任務（原 todayTasks：開始日或截止日是這一天、未完成）

    static func dayTasks(on day: Date, in subs: [Subordinate],
                         calendar cal: Calendar = .current) -> [(sub: Subordinate, task: SubordinateTask)] {
        subs.flatMap { sub in
            sub.tasks
                .filter { t in
                    !t.isCompleted && (
                        cal.isDate(t.date, inSameDayAs: day)
                        || t.dueDate.map({ cal.isDate($0, inSameDayAs: day) }) == true
                    )
                }
                .map { (sub, $0) }
        }
        .sorted { $0.task.date < $1.task.date }
    }

    // MARK: - 未完成任務（原 incompleteTasks：所有部屬、所有日期，依 dueDate ?? date）

    static func incompleteTasks(in subs: [Subordinate]) -> [(sub: Subordinate, task: SubordinateTask)] {
        subs.flatMap { sub in
            sub.tasks.filter { !$0.isCompleted }.map { (sub, $0) }
        }
        .sorted { a, b in
            let keyA = a.task.dueDate ?? a.task.date
            let keyB = b.task.dueDate ?? b.task.date
            return keyA < keyB
        }
    }

    // MARK: - 逾期（原 taskRow 的 isOverdue：部屬總覽的紅字）

    /// 未完成、有截止時間、而且截止時間已經過了 now
    static func isOverdue(_ task: SubordinateTask, at now: Date) -> Bool {
        !task.isCompleted && (task.dueDate.map { $0 < now } ?? false)
    }

    // MARK: - [v5] 小工具多要的（純函式）

    /// 到期那天 00:00（dueDate ?? date，同總覽「未完成任務」的排序鍵）
    static func dueDay(_ task: SubordinateTask, calendar cal: Calendar = .current) -> Date {
        cal.startOfDay(for: task.dueDate ?? task.date)
    }

    /// 那一天的班別（同 SubordinateDetailView.effectiveShiftType、SubordinateRosterView.currentShift 的取法：
    /// 同一天的第一筆；LifeStore 設班別時會先刪掉同一天的，所以一天最多一筆）。沒排班回 nil
    static func shift(of sub: Subordinate, on day: Date, calendar cal: Calendar = .current) -> ShiftType? {
        sub.shifts.first { cal.isDate($0.date, inSameDayAs: day) }?.type
    }

    /// 一筆請假的假別與時數：「病假 4 小時」「特休」「4 小時」；都沒填寫「請假」。
    /// 寫法同部屬總覽的文字匯出（假別 rawValue、時數 String(format: "%g", h) + " 小時"），用空格接
    static func leaveText(_ rec: SubordinateRecord) -> String {
        var parts: [String] = []
        if let lt = rec.leaveType { parts.append(lt.rawValue) }
        if let h = rec.leaveHours, h > 0 { parts.append(String(format: "%g", h) + " 小時") }
        return parts.isEmpty ? "請假" : parts.joined(separator: " ")
    }
}
