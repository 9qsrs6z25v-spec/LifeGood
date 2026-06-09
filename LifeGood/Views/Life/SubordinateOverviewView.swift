import SwiftUI

// MARK: - 美化紀錄（SubordinateOverviewView）
// [2026-06] 本次美化方向：
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

struct SubordinateOverviewView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @State private var selectedDate = Date()
    @State private var sectionAppeared = false
    @State private var showCompleted = false
    @State private var editTarget: OverviewEditTarget?

    /// 點擊總覽項目要開啟的編輯目標
    private enum OverviewEditTarget: Identifiable {
        case leave(subId: UUID, rec: SubordinateRecord)
        case meeting(subId: UUID, meeting: SubordinateMeeting)
        case task(subId: UUID, task: SubordinateTask)
        var id: String {
            switch self {
            case .leave(_, let r):   return "l_\(r.id.uuidString)"
            case .meeting(_, let m): return "m_\(m.id.uuidString)"
            case .task(_, let t):    return "t_\(t.id.uuidString)"
            }
        }
    }

    private var calendar: Calendar { Calendar.current }

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
                    MacaronDatePicker(selectedDate: $selectedDate)

                    leaveSection
                        .opacity(sectionAppeared ? 1 : 0)
                        .offset(y: sectionAppeared ? 0 : 14)
                        .animation(.spring(response: 0.48, dampingFraction: 0.80).delay(0.05), value: sectionAppeared)

                    meetingSection
                        .opacity(sectionAppeared ? 1 : 0)
                        .offset(y: sectionAppeared ? 0 : 14)
                        .animation(.spring(response: 0.48, dampingFraction: 0.80).delay(0.12), value: sectionAppeared)

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
                withAnimation(.spring(response: 0.50, dampingFraction: 0.82)) {
                    sectionAppeared = true
                }
            }
            .sheet(item: $editTarget) { target in
                switch target {
                case .leave(let subId, let rec):
                    RecordEditorSheet(subordinateId: subId, type: rec.type, editing: rec)
                case .meeting(let subId, let meeting):
                    MeetingEditorSheet(subordinateId: subId, editing: meeting)
                case .task(let subId, let task):
                    TaskEditorSheet(subordinateId: subId, editing: task)
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
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
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
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    // MARK: - 任務

    private var taskSection: some View {
        VStack(spacing: 16) {
            // 當日任務（選取日期、未完成）
            taskGroupCard(title: "當日任務", icon: "checklist", color: .cyan,
                          items: todayTasks, emptyText: "當日無任務")

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
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
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
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(fmtTime(rec.date))
                    if let end = rec.endDate {
                        Text("~")
                        Text(fmtTime(end))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
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
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                    Text("\(meeting.durationMinutes) 分鐘")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.indigo)
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(Color.indigo.opacity(0.12))
                        .clipShape(Capsule())

                    Text(sub.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !meeting.items.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 9))
                        Text("\(meeting.items.count) 個議程項目")
                    }
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
                }
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                        Text(fmtTime(task.date))
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

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

    private func fmtTime(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
    }

    private func fmtDateTime(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M/d HH:mm"; return f.string(from: date)
    }
}
