import SwiftUI

struct SubordinateOverviewView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @State private var selectedDate = Date()

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
                        && selectedDate < calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end))!
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
                    isSameDay(t.date, selectedDate)
                    || (t.dueDate != nil && isSameDay(t.dueDate!, selectedDate))
                }
                .map { (sub, $0) }
        }
        .sorted { $0.task.date < $1.task.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    MacaronDatePicker(selectedDate: $selectedDate)
                    leaveSection
                    meetingSection
                    taskSection
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("部屬總覽")
        }
    }

    // MARK: - 請假

    private var leaveSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("請假", icon: "calendar.badge.minus", color: .teal, count: todayLeaves.count)

            if todayLeaves.isEmpty {
                emptyHint("當日無人請假")
            } else {
                ForEach(todayLeaves, id: \.rec.id) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "calendar.badge.minus")
                            .font(.caption).foregroundStyle(.teal).frame(width: 20)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(item.sub.name).font(.subheadline.weight(.medium))
                                if let lt = item.rec.leaveType {
                                    Text(lt.rawValue).font(.caption2.weight(.medium))
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color.teal.opacity(0.15)).foregroundStyle(.teal)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                if let h = item.rec.leaveHours, h > 0 {
                                    Text(h.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(h))h" : String(format: "%.1fh", h))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            HStack(spacing: 4) {
                                Text(fmtTime(item.rec.date))
                                if let end = item.rec.endDate {
                                    Text("~ \(fmtTime(end))")
                                }
                            }
                            .font(.caption2).foregroundStyle(.tertiary)
                            if !item.rec.content.isEmpty {
                                Text(item.rec.content).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 會議

    private var meetingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("會議", icon: "person.3.fill", color: .indigo, count: todayMeetings.count)

            if todayMeetings.isEmpty {
                emptyHint("當日無會議")
            } else {
                ForEach(todayMeetings, id: \.meeting.id) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "person.3.fill")
                            .font(.caption).foregroundStyle(.indigo).frame(width: 20)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.meeting.topic.isEmpty ? "未命名會議" : item.meeting.topic)
                                .font(.subheadline.weight(.medium))
                            HStack(spacing: 6) {
                                Text(fmtTime(item.meeting.date)).font(.caption2).foregroundStyle(.tertiary)
                                Text("\(item.meeting.durationMinutes) 分鐘").font(.caption2)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Color.indigo.opacity(0.12)).foregroundStyle(.indigo)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                Text(item.sub.name).font(.caption2).foregroundStyle(.secondary)
                            }
                            if !item.meeting.items.isEmpty {
                                Text("\(item.meeting.items.count) 個項目").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 任務

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("任務", icon: "checklist", color: .cyan, count: todayTasks.count)

            if todayTasks.isEmpty {
                emptyHint("當日無任務")
            } else {
                ForEach(todayTasks, id: \.task.id) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "checklist")
                            .font(.caption).foregroundStyle(.cyan).frame(width: 20)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(item.task.topic.isEmpty ? "未命名任務" : item.task.topic)
                                    .font(.subheadline.weight(.medium))
                                Text(item.sub.name).font(.caption2).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 6) {
                                Text(fmtTime(item.task.date)).font(.caption2).foregroundStyle(.tertiary)
                                if let due = item.task.dueDate {
                                    Text("截止 \(fmtDateTime(due))").font(.caption2)
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(due < Date() ? Color.red.opacity(0.12) : Color.cyan.opacity(0.12))
                                        .foregroundStyle(due < Date() ? .red : .cyan)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }
                            if !item.task.content.isEmpty {
                                Text(item.task.content).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 輔助

    private func sectionHeader(_ title: String, icon: String, color: Color, count: Int) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(color)
            Text(title).font(.headline)
            Spacer()
            Text("\(count) 筆").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal).padding(.bottom, 12)
    }

    private func fmtTime(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
    }

    private func fmtDateTime(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M/d HH:mm"; return f.string(from: date)
    }
}
