import SwiftUI

// MARK: - 美化紀錄（SubordinateOverviewView）
// [2026-06 v1] 本次美化方向：
//   1. sectionHeader：升級為「漸層 Capsule 左側條 + 彩色圓形圖示圈 + 計數徽章膠囊」，
//      對齊 LifeOverviewView / FinanceChartView.sectionHeader 視覺規格
//   2. 各區塊列（請假 / 會議 / 任務）：改用 36pt 漸層圓形圖示 + 細邊框，
//      加入列間 Divider（.leading 對齊）；標籤膠囊改 Capsule（對齊全域規格）
//   3. emptyHint：從純文字升級為「小型空狀態：40pt 圖示圓 + 主色 + 說明文字」，
//      視覺重量對齊 OverviewView.emptyPlaceholder
//   4. 整體加入交錯淡入 + 向上進場動畫（sectionAppeared），
//      對齊 LifeOverviewView.timelineRowsAppeared 動畫規格
//   5. 三個主區塊（請假 / 會議 / 任務）最外層加 shadow + 極細 overlay 邊框，
//      提升深色模式下的邊界感與層次，對齊 OverviewView categoryBreakdownSection
// [2026-06 v2] 本次美化方向：
//   6. summaryHeroCard：日期選取器上方新增藍綠漸層英雄卡，顯示部屬總人數 +
//      今日請假 / 今日會議 / 待辦任務三格 KPI；三顆散景裝飾圓 + 頂部玻璃光澤
//      （white.opacity(0.18)），對齊 SubordinateView.summaryStatsCard /
//      VariableExpenseView.monthSummaryHeader 英雄卡規格；
//      heroAppeared spring 進場動畫（透明度 + Y 位移 16pt），段落進場延遲 0.10s
//   7. 時間標籤 Capsule 升級：leaveRow / meetingRow / taskRow 中裸 clock + 時間文字
//      升級為 tertiarySystemFill 底色 Capsule 徽章，
//      對齊 CareerView v2 / OverviewView.recentRow 日期 Capsule 設計語言
//   8. 彩色膠囊補細邊框：leaveType / 會議時長 / 截止日 / 部屬姓名膠囊補
//      Capsule().stroke(color.opacity(0.22), lineWidth:0.6)，
//      對齊全 App 膠囊描邊規格（BusinessCardView v2 / StockDetailView v2）
//   9. 雙層 shadow 升級：各卡片由單層 black.opacity(0.06) 升級為雙層
//      （色調主光暈 + 黑底基礎陰影），提升立體感，
//      對齊 SubordinateDetailView.headerCard / FamilyMembersResumeView v2 規格

struct SubordinateOverviewView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @State private var selectedDate = Date()
    @State private var heroAppeared = false
    @State private var sectionAppeared = false
    @State private var showCompleted = false
    @State private var editTarget: OverviewEditTarget?

    /// 點擊總覽項目要開啟的編輯目標
    private enum OverviewEditTarget: Identifiable {
        case leave(subId: UUID, rec: SubordinateRecord)
        case meeting(subId: UUID, meeting: SubordinateMeeting)
        case task(subId: UUID, task: SubordinateTask)
        case report(subId: UUID, report: WeeklyReport)
        var id: String {
            switch self {
            case .leave(_, let r):   return "l_\(r.id.uuidString)"
            case .meeting(_, let m): return "m_\(m.id.uuidString)"
            case .task(_, let t):    return "t_\(t.id.uuidString)"
            case .report(_, let r):  return "r_\(r.id.uuidString)"
            }
        }
    }

    private let calendar = Calendar.current

    private func isSameDay(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }

    // MARK: - 當日請假

    private var todayLeaves: [(sub: Subordinate, rec: SubordinateRecord)] {
        lifeStore.subordinates.flatMap { sub in
            sub.records
                .filter { $0.type == .leave }
                .filter { rec in
                    let start = rec.date
                    let end = rec.endDate ?? start
                    return selectedDate >= calendar.startOfDay(for: start)
                        && selectedDate < (calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? .distantFuture)
                }
                .map { (sub, $0) }
        }
        .sorted { $0.rec.date < $1.rec.date }
    }

    // MARK: - 當日會議

    private var todayMeetings: [(sub: Subordinate, meeting: SubordinateMeeting)] {
        lifeStore.subordinates.flatMap { sub in
            sub.meetings
                .filter { isSameDay($0.date, selectedDate) }
                .map { (sub, $0) }
        }
        .sorted { $0.meeting.date < $1.meeting.date }
    }

    // MARK: - 報告（本週全部 + 任何未完成 / 逾期）

    /// 報告呈現狀態
    enum ReportStatus { case overdue, thisWeek, pending, done }

    /// 選取日所在的自然週區間 [週起, 下週起)
    private var weekInterval: DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: selectedDate)
            ?? DateInterval(start: calendar.startOfDay(for: selectedDate), duration: 86_400)
    }

    /// 顯示規則：本週的報告（含已完成）+ 任何未完成的報告（含逾期、未來週）
    /// 排序：未完成優先（逾期最前 → 日期舊到新），其後已完成（日期新到舊）
    private var displayedReports: [(sub: Subordinate, report: WeeklyReport, status: ReportStatus)] {
        let wk = weekInterval
        return lifeStore.subordinates.flatMap { sub in
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

    // MARK: - 當日任務（進行中或當日到期）

    private var todayTasks: [(sub: Subordinate, task: SubordinateTask)] {
        lifeStore.subordinates.flatMap { sub in
            sub.tasks
                .filter { t in
                    !t.isCompleted && (
                        isSameDay(t.date, selectedDate)
                        || t.dueDate.map({ isSameDay($0, selectedDate) }) == true
                    )
                }
                .map { (sub, $0) }
        }
        .sorted { $0.task.date < $1.task.date }
    }

    /// 所有部屬、所有日期的「未完成」任務總清單（逾期排最前，再依截止日 / 日期）
    private var incompleteTasks: [(sub: Subordinate, task: SubordinateTask)] {
        lifeStore.subordinates.flatMap { sub in
            sub.tasks.filter { !$0.isCompleted }.map { (sub, $0) }
        }
        .sorted { a, b in
            let keyA = a.task.dueDate ?? a.task.date
            let keyB = b.task.dueDate ?? b.task.date
            return keyA < keyB
        }
    }

    /// 所有部屬、所有會議的「未完成」議程項目（依會議日期新到舊）
    private var incompleteMeetingItems: [(sub: Subordinate, meeting: SubordinateMeeting, item: MeetingItem)] {
        lifeStore.subordinates.flatMap { sub in
            sub.meetings.flatMap { m in
                m.items.filter { !$0.isCompleted }.map { (sub: sub, meeting: m, item: $0) }
            }
        }
        .sorted { $0.meeting.date > $1.meeting.date }
    }

    /// 所有「已完成」任務（依完成時間新到舊，無完成時間者退用日期）
    private var completedTasks: [(sub: Subordinate, task: SubordinateTask)] {
        lifeStore.subordinates.flatMap { sub in
            sub.tasks.filter { $0.isCompleted }.map { (sub, $0) }
        }
        .sorted { ($0.task.completedAt ?? $0.task.date) > ($1.task.completedAt ?? $1.task.date) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    summaryHeroCard
                        .opacity(heroAppeared ? 1 : 0)
                        .offset(y: heroAppeared ? 0 : 16)
                        .animation(.spring(response: 0.52, dampingFraction: 0.80), value: heroAppeared)

                    MacaronDatePicker(selectedDate: $selectedDate)

                    leaveSection
                        .opacity(sectionAppeared ? 1 : 0)
                        .offset(y: sectionAppeared ? 0 : 14)
                        .animation(.spring(response: 0.48, dampingFraction: 0.80).delay(0.05), value: sectionAppeared)

                    reportSection
                        .opacity(sectionAppeared ? 1 : 0)
                        .offset(y: sectionAppeared ? 0 : 14)
                        .animation(.spring(response: 0.48, dampingFraction: 0.80).delay(0.11), value: sectionAppeared)

                    meetingSection
                        .opacity(sectionAppeared ? 1 : 0)
                        .offset(y: sectionAppeared ? 0 : 14)
                        .animation(.spring(response: 0.48, dampingFraction: 0.80).delay(0.15), value: sectionAppeared)

                    taskSection
                        .opacity(sectionAppeared ? 1 : 0)
                        .offset(y: sectionAppeared ? 0 : 14)
                        .animation(.spring(response: 0.48, dampingFraction: 0.80).delay(0.19), value: sectionAppeared)
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("部屬總覽")
            .onAppear {
                withAnimation(.spring(response: 0.52, dampingFraction: 0.80)) {
                    heroAppeared = true
                }
                withAnimation(.spring(response: 0.50, dampingFraction: 0.82).delay(0.10)) {
                    sectionAppeared = true
                }
            }
            .onDisappear { heroAppeared = false; sectionAppeared = false }
            .sheet(item: $editTarget) { target in
                switch target {
                case .leave(let subId, let rec):
                    RecordEditorSheet(subordinateId: subId, type: rec.type, editing: rec)
                case .meeting(let subId, let meeting):
                    MeetingEditorSheet(subordinateId: subId, editing: meeting)
                case .task(let subId, let task):
                    TaskEditorSheet(subordinateId: subId, editing: task)
                case .report(let subId, let report):
                    WeeklyReportEditorSheet(subordinateId: subId, editing: report)
                }
            }
        }
    }

    // MARK: - 請假

    private var leaveSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("請假", icon: "calendar.badge.minus", color: .teal, count: todayLeaves.count)

            if todayLeaves.isEmpty {
                emptyHint("當日無人請假", icon: "calendar.badge.minus", color: .teal)
            } else {
                ForEach(Array(todayLeaves.enumerated()), id: \.element.rec.id) { idx, item in
                    leaveRow(item.sub, item.rec)

                    if idx < todayLeaves.count - 1 {
                        Divider().padding(.leading, 62)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75)
        )
        .shadow(color: Color.teal.opacity(0.12), radius: 10, x: 0, y: 4)
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        .padding(.horizontal)
    }

    // MARK: - 報告彙整

    private var reportSection: some View {
        let rows = displayedReports
        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader("報告（本週 / 待辦）", icon: "doc.text.fill", color: .purple, count: rows.count)

            if rows.isEmpty {
                emptyHint("本週無報告、無待辦報告", icon: "doc.text.fill", color: .purple)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.report.id) { idx, item in
                    reportRow(item.sub, item.report, status: item.status)

                    if idx < rows.count - 1 {
                        Divider().padding(.leading, 62)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75)
        )
        .shadow(color: Color.purple.opacity(0.12), radius: 10, x: 0, y: 4)
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        .padding(.horizontal)
    }

    /// 狀態標籤文案與顏色
    private func reportStatusBadge(_ status: ReportStatus) -> (text: String, color: Color)? {
        switch status {
        case .overdue:  return ("逾期", .red)
        case .thisWeek: return ("本週", .purple)
        case .pending:  return ("待辦", .orange)
        case .done:     return nil
        }
    }

    private func reportRow(_ sub: Subordinate, _ report: WeeklyReport, status: ReportStatus) -> some View {
        let badge = reportStatusBadge(status)
        return HStack(spacing: 12) {
            Button {
                lifeStore.toggleWeeklyReportCompletion(subordinateId: sub.id, reportId: report.id)
            } label: {
                Image(systemName: report.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(report.isCompleted ? Color.green : Color.purple)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(report.topic.isEmpty ? "未命名報告" : report.topic)
                        .font(.subheadline.weight(.semibold))
                        .strikethrough(report.isCompleted, color: .secondary)
                        .foregroundStyle(report.isCompleted ? .secondary : .primary)
                        .lineLimit(1)
                    if let badge {
                        Text(badge.text)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(badge.color.opacity(0.15))
                            .foregroundStyle(badge.color)
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 6) {
                    Text(sub.name.isEmpty ? "未命名" : sub.name)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.purple.opacity(0.12))
                        .foregroundStyle(.purple)
                        .clipShape(Capsule())
                    HStack(spacing: 3) {
                        Image(systemName: "calendar").font(.system(size: 8))
                        Text(reportDateText(report.date))
                    }
                    .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color(.tertiarySystemFill)).clipShape(Capsule())
                    if !report.note.isEmpty {
                        Text(report.note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .opacity(report.isCompleted ? 0.7 : 1)
        .contentShape(Rectangle())
        .onTapGesture { editTarget = .report(subId: sub.id, report: report) }
    }

    private func reportDateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d (E)"
        return f.string(from: date)
    }

    // MARK: - 會議

    private var meetingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("會議", icon: "person.3.fill", color: .indigo, count: todayMeetings.count)

            if todayMeetings.isEmpty {
                emptyHint("當日無會議", icon: "person.3.fill", color: .indigo)
            } else {
                ForEach(Array(todayMeetings.enumerated()), id: \.element.meeting.id) { idx, item in
                    meetingRow(item.sub, item.meeting)

                    if idx < todayMeetings.count - 1 {
                        Divider().padding(.leading, 62)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75)
        )
        .shadow(color: Color.indigo.opacity(0.12), radius: 10, x: 0, y: 4)
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        .padding(.horizontal)
    }

    // MARK: - 任務

    private var taskSection: some View {
        VStack(spacing: 16) {
            // 當日任務（選取日期、未完成）
            taskGroupCard(title: "當日任務", icon: "checklist", color: .cyan,
                          items: todayTasks, emptyText: "當日無任務")

            // 未完成會議條目（跨所有部屬 / 會議的未完成議程項目）
            meetingItemsCard

            // 未完成任務（跨所有日期 / 部屬的待辦總清單，逾期排最前）
            taskGroupCard(title: "未完成任務", icon: "tray.full.fill", color: .orange,
                          items: incompleteTasks, emptyText: "沒有未完成任務")

            // 已完成（可收合；無已完成時不顯示）
            if !completedTasks.isEmpty {
                completedCard
            }
        }
        .padding(.horizontal)
    }

    /// 未完成會議條目卡
    private var meetingItemsCard: some View {
        cardWrap {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("未完成會議條目", icon: "person.3.sequence.fill", color: .indigo,
                              count: incompleteMeetingItems.count)
                if incompleteMeetingItems.isEmpty {
                    emptyHint("沒有未完成的會議條目", icon: "person.3.sequence.fill", color: .indigo)
                } else {
                    ForEach(Array(incompleteMeetingItems.enumerated()), id: \.element.item.id) { idx, it in
                        meetingItemOverviewRow(it.sub, it.meeting, it.item)
                        if idx < incompleteMeetingItems.count - 1 { Divider().padding(.leading, 62) }
                    }
                }
            }
        }
    }

    private func meetingItemOverviewRow(_ sub: Subordinate, _ meeting: SubordinateMeeting, _ item: MeetingItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                lifeStore.toggleMeetingItemCompletion(subordinateId: sub.id, meetingId: meeting.id, itemId: item.id)
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(item.isCompleted ? Color.green : Color.indigo)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.content.isEmpty ? "未填內容" : item.content)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(meeting.topic.isEmpty ? "未命名會議" : meeting.topic)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.indigo)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.indigo.opacity(0.12))
                        .clipShape(Capsule())
                    if let due = item.dueDate {
                        HStack(spacing: 3) {
                            Image(systemName: "flag.fill").font(.system(size: 7, weight: .semibold))
                            Text("截止 \(fmtDateTime(due))")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(due < Date() ? .red : .indigo)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background((due < Date() ? Color.red : Color.indigo).opacity(0.12))
                        .clipShape(Capsule())
                    }
                    Text(sub.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture { editTarget = .meeting(subId: sub.id, meeting: meeting) }
    }

    private func taskGroupCard(title: String, icon: String, color: Color,
                               items: [(sub: Subordinate, task: SubordinateTask)],
                               emptyText: String) -> some View {
        cardWrap {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(title, icon: icon, color: color, count: items.count)
                if items.isEmpty {
                    emptyHint(emptyText, icon: icon, color: color)
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.task.id) { idx, item in
                        taskRow(item.sub, item.task)
                        if idx < items.count - 1 { Divider().padding(.leading, 62) }
                    }
                }
            }
        }
    }

    private var completedCard: some View {
        cardWrap {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showCompleted.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Capsule()
                            .fill(LinearGradient(colors: [.green, .green.opacity(0.55)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: 4, height: 18)
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [Color.green.opacity(0.20), Color.green.opacity(0.08)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 28, height: 28)
                            Circle().stroke(Color.green.opacity(0.22), lineWidth: 0.75).frame(width: 28, height: 28)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.green)
                        }
                        Text("已完成").font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                        Spacer()
                        Text("\(completedTasks.count) 筆")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.green)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.green.opacity(0.10)).clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.green.opacity(0.22), lineWidth: 0.75))
                        Image(systemName: showCompleted ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14).padding(.top, 13).padding(.bottom, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showCompleted {
                    ForEach(Array(completedTasks.enumerated()), id: \.element.task.id) { idx, item in
                        taskRow(item.sub, item.task)
                        if idx < completedTasks.count - 1 { Divider().padding(.leading, 62) }
                    }
                }
            }
        }
    }

    /// 任務卡片外框（三個任務分組共用：底色 + 圓角 + 細邊框 + 陰影）
    private func cardWrap<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
            .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    // MARK: - 列元件

    private func leaveRow(_ sub: Subordinate, _ rec: SubordinateRecord) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // 36pt 漸層圖示圓（對齊全域規格）
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.teal.opacity(0.22), Color.teal.opacity(0.08)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Circle()
                    .stroke(Color.teal.opacity(0.22), lineWidth: 1)
                    .frame(width: 36, height: 36)
                Image(systemName: "calendar.badge.minus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.teal)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(sub.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let lt = rec.leaveType {
                        Text(lt.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.teal)
                            .padding(.horizontal, 7).padding(.vertical, 2.5)
                            .background(Color.teal.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.teal.opacity(0.22), lineWidth: 0.6))
                    }
                    if let h = rec.leaveHours, h > 0 {
                        Text(h.truncatingRemainder(dividingBy: 1) == 0
                             ? "\(Int(h))h" : String(format: "%.1fh", h))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                    Text(fmtTime(rec.date))
                    if let end = rec.endDate {
                        Text("~")
                        Text(fmtTime(end))
                    }
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7).padding(.vertical, 2.5)
                .background(Color(.tertiarySystemFill))
                .clipShape(Capsule())
                if !rec.content.isEmpty {
                    Text(rec.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture { editTarget = .leave(subId: sub.id, rec: rec) }
    }

    private func meetingRow(_ sub: Subordinate, _ meeting: SubordinateMeeting) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.indigo.opacity(0.22), Color.indigo.opacity(0.08)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Circle()
                    .stroke(Color.indigo.opacity(0.22), lineWidth: 1)
                    .frame(width: 36, height: 36)
                Image(systemName: "person.3.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.indigo)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.topic.isEmpty ? "未命名會議" : meeting.topic)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                        Text(fmtTime(meeting.date))
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 2.5)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())

                    Text("\(meeting.durationMinutes) 分鐘")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.indigo)
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(Color.indigo.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.indigo.opacity(0.22), lineWidth: 0.6))

                    Text(sub.name)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color(.separator).opacity(0.18), lineWidth: 0.6))
                }
                if !meeting.items.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(meeting.items) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Button {
                                    lifeStore.toggleMeetingItemCompletion(subordinateId: sub.id, meetingId: meeting.id, itemId: item.id)
                                } label: {
                                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 13))
                                        .foregroundStyle(item.isCompleted ? Color.green : Color.indigo.opacity(0.55))
                                }
                                .buttonStyle(.plain)
                                Text(item.content.isEmpty ? "未填內容" : item.content)
                                    .font(.caption2)
                                    .strikethrough(item.isCompleted, color: .secondary)
                                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                                    .lineLimit(2)
                            }
                            .opacity(item.isCompleted ? 0.7 : 1)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture { editTarget = .meeting(subId: sub.id, meeting: meeting) }
    }

    private func taskRow(_ sub: Subordinate, _ task: SubordinateTask) -> some View {
        let isOverdue = !task.isCompleted && (task.dueDate.map { $0 < Date() } ?? false)
        let taskAccent: Color = task.isCompleted ? .green : (isOverdue ? .red : .cyan)

        return HStack(alignment: .center, spacing: 12) {
            // 可點打勾圓圈：直接切換完成狀態
            Button {
                lifeStore.toggleTaskCompletion(subordinateId: sub.id, taskId: task.id)
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [taskAccent.opacity(0.22), taskAccent.opacity(0.08)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    Circle()
                        .stroke(taskAccent.opacity(0.22), lineWidth: 1)
                        .frame(width: 36, height: 36)
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : (isOverdue ? "exclamationmark.circle.fill" : "circle"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(taskAccent)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(task.topic.isEmpty ? "未命名任務" : task.topic)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .strikethrough(task.isCompleted, color: .secondary)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    Text(sub.name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color(.separator).opacity(0.18), lineWidth: 0.6))
                }
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                        Text(fmtTime(task.date))
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 2.5)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())

                    if let due = task.dueDate {
                        HStack(spacing: 3) {
                            Image(systemName: isOverdue ? "exclamationmark.triangle.fill" : "clock.badge")
                                .font(.system(size: 9, weight: .semibold))
                            Text("截止 \(fmtDateTime(due))")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(isOverdue ? .red : .cyan)
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(taskAccent.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(taskAccent.opacity(0.22), lineWidth: 0.6))
                    }
                }
                if !task.content.isEmpty {
                    Text(task.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
        }
        .opacity(task.isCompleted ? 0.6 : 1)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture { editTarget = .task(subId: sub.id, task: task) }
    }

    // MARK: - 英雄摘要卡

    private var summaryHeroCard: some View {
        ZStack(alignment: .topLeading) {
            // 主漸層背景
            LinearGradient(
                colors: [Color(red: 0.17, green: 0.54, blue: 0.90),
                         Color(red: 0.05, green: 0.78, blue: 0.72)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))

            // 散景裝飾圓：右上
            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 90, height: 90)
                .blur(radius: 10)
                .offset(x: 250, y: -20)
            // 散景裝飾圓：左下
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 65, height: 65)
                .blur(radius: 8)
                .offset(x: -10, y: 62)
            // 散景裝飾圓：中右（第三顆）
            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 55, height: 55)
                .blur(radius: 8)
                .offset(x: 185, y: 52)

            VStack(alignment: .leading, spacing: 12) {
                // 標題列
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.22))
                            .frame(width: 36, height: 36)
                        Image(systemName: "person.3.sequence.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Text("部屬總覽")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("共 \(lifeStore.subordinates.count) 人")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.white.opacity(0.20))
                        .clipShape(Capsule())
                }

                Rectangle()
                    .fill(Color.white.opacity(0.22))
                    .frame(height: 0.5)

                // KPI 三格
                HStack(spacing: 0) {
                    heroKpiCell(value: "\(todayLeaves.count)", label: "今日請假",
                                icon: "calendar.badge.minus")
                    Rectangle().fill(Color.white.opacity(0.22)).frame(width: 0.5, height: 36)
                    heroKpiCell(value: "\(todayMeetings.count)", label: "今日會議",
                                icon: "person.3.fill")
                    Rectangle().fill(Color.white.opacity(0.22)).frame(width: 0.5, height: 36)
                    heroKpiCell(value: "\(incompleteTasks.count)", label: "待辦任務",
                                icon: "tray.full.fill")
                }
            }
            .padding(16)

            // 玻璃光澤覆層
            LinearGradient(
                colors: [.white.opacity(0.18), .clear],
                startPoint: .top, endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.17, green: 0.54, blue: 0.90).opacity(0.30), radius: 14, x: 0, y: 6)
        .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
        .padding(.horizontal)
    }

    private func heroKpiCell(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.80))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 輔助元件

    /// 區塊標題列：漸層 Capsule 左條 + 彩色圖示圓 + 計數徽章膠囊
    private func sectionHeader(_ title: String, icon: String, color: Color, count: Int) -> some View {
        HStack(spacing: 10) {
            // 漸層 Capsule 左側條（對齊 LifeOverviewView / OverviewView 規格）
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 18)

            // 彩色圖示圓
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.20), color.opacity(0.08)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                Circle()
                    .stroke(color.opacity(0.22), lineWidth: 0.75)
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
            }

            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)

            Spacer()

            // 計數徽章膠囊
            Text(count > 0 ? "\(count) 筆" : "無")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(count > 0 ? color : Color(.tertiaryLabel))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(count > 0 ? color.opacity(0.10) : Color(.tertiarySystemFill))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(count > 0 ? color.opacity(0.22) : Color.clear, lineWidth: 0.75)
                )
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 9)
    }

    /// 空狀態提示：小型圖示圓 + 說明文字（對齊 OverviewView.emptyPlaceholder 精簡版）
    private func emptyHint(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemFill))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(Color(.secondaryLabel))
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .padding(.bottom, 2)
    }

    private static let fmtTimeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let fmtDateTimeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d HH:mm"; return f
    }()

    private func fmtTime(_ date: Date) -> String {
        Self.fmtTimeFormatter.string(from: date)
    }

    private func fmtDateTime(_ date: Date) -> String {
        Self.fmtDateTimeFormatter.string(from: date)
    }
}
