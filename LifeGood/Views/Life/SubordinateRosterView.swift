import SwiftUI

// MARK: - 班別時間設定（可自訂，存於本機 UserDefaults）

final class ShiftScheduleStore: ObservableObject {
    static let shared = ShiftScheduleStore()
    private let key = "subordinate_shift_schedule"

    @Published var schedule: ShiftSchedule { didSet { persist() } }

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let s = try? JSONDecoder().decode(ShiftSchedule.self, from: data) {
            schedule = s
        } else {
            schedule = .default
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(schedule) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - 顏色語言

func rosterShiftColor(_ t: ShiftType) -> Color {
    switch t {
    case .nightShift:   return .indigo
    case .eveningShift: return .purple
    case .holidayDuty:  return .orange
    case .jetLagLeave:  return .teal
    case .restDay:      return .gray
    }
}

func rosterLeaveColor(_ t: LeaveType) -> Color {
    switch t {
    case .personal:   return .blue
    case .sick:       return .red
    case .annual:     return .green
    case .marriage:   return .pink
    case .funeral:    return Color(.darkGray)
    case .maternity:  return .purple
    case .paternity:  return .cyan
    case .official:   return .teal
    case .workInjury: return .brown
    }
}

// MARK: - 點擊格子的識別

private struct RosterCell: Identifiable {
    let id = UUID()
    let subId: UUID
    let date: Date
}

// MARK: - 部屬班表（棋盤式燈號）

struct SubordinateRosterView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @StateObject private var scheduleStore = ShiftScheduleStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var month: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var selectedDeptId: UUID? = nil
    @State private var detail: RosterCell?
    @State private var showSettings = false

    private let nameColWidth: CGFloat = 88
    private let cellW: CGFloat = 40
    private let cellH: CGFloat = 42
    private let headerH: CGFloat = 38

    // MARK: 資料

    private var people: [Subordinate] {
        lifeStore.subordinates
            .filter { selectedDeptId == nil || $0.departmentId == selectedDeptId }
            .sorted { $0.name < $1.name }
    }

    private var days: [Date] {
        let cal = Calendar.current
        guard let range = cal.range(of: .day, in: .month, for: month),
              let first = cal.date(from: cal.dateComponents([.year, .month], from: month)) else { return [] }
        return range.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: first) }
    }

    private static let monthTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "yyyy 年 M 月"
        return f
    }()

    private var monthTitle: String {
        Self.monthTitleFormatter.string(from: month)
    }

    private var selectedDeptName: String {
        guard let id = selectedDeptId,
              let d = lifeStore.departments.first(where: { $0.id == id }) else { return "全部部門" }
        return d.name.isEmpty ? (d.code.isEmpty ? "未命名部門" : d.code) : d.name
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                filterBar
                legend
                if people.isEmpty {
                    emptyHint
                } else {
                    gridArea
                }
            }
            .padding(.top, 6)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("部屬班表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(item: $detail) { cell in
                RosterCellDetailSheet(scheduleStore: scheduleStore, cell: cell)
            }
            .sheet(isPresented: $showSettings) {
                ShiftScheduleSettingsView(scheduleStore: scheduleStore)
            }
        }
    }

    // MARK: 篩選列

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left").font(.headline).foregroundStyle(.blue)
                }
                Spacer()
                Text(monthTitle).font(.headline)
                Spacer()
                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right").font(.headline).foregroundStyle(.blue)
                }
            }
            Menu {
                Button("全部部門") { selectedDeptId = nil }
                ForEach(lifeStore.departments) { d in
                    Button(d.name.isEmpty ? d.code : d.name) { selectedDeptId = d.id }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(selectedDeptName)
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .font(.subheadline)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal)
    }

    // MARK: 圖例

    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ShiftType.allCases) { t in
                    legendChip(t.shortLabel, rosterShiftColor(t))
                }
                legendChip("請假", .blue)
            }
            .padding(.horizontal)
        }
    }

    private func legendChip(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(text).font(.caption2)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color(.secondarySystemBackground))
        .clipShape(Capsule())
    }

    private var emptyHint: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "person.2.slash").font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
            Text(selectedDeptId == nil ? "尚無部屬資料" : "此部門沒有部屬").foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 棋盤格

    private var gridArea: some View {
        ScrollView(.vertical, showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {
                // 凍結姓名欄
                VStack(spacing: 0) {
                    Color.clear.frame(width: nameColWidth, height: headerH)
                    ForEach(people) { p in nameCell(p) }
                }
                // 可水平捲動的整月格
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) { ForEach(days, id: \.self) { d in dayHeader(d) } }
                        ForEach(people) { p in
                            HStack(spacing: 0) { ForEach(days, id: \.self) { d in cell(p, d) } }
                        }
                    }
                }
            }
            .background(Color(.systemBackground))
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.separator).opacity(0.15), lineWidth: 0.75))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func nameCell(_ sub: Subordinate) -> some View {
        HStack {
            Text(sub.name.isEmpty ? "未命名" : sub.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .padding(.leading, 8)
        .frame(width: nameColWidth, height: cellH)
        .overlay(Rectangle().stroke(Color(.separator).opacity(0.2), lineWidth: 0.5))
    }

    private func dayHeader(_ day: Date) -> some View {
        let weekend = isWeekend(day)
        return VStack(spacing: 1) {
            Text(weekdayShort(day)).font(.system(size: 9)).foregroundStyle(weekend ? .red : .secondary)
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(weekend ? .red : .primary)
        }
        .frame(width: cellW, height: headerH)
        .background(weekend ? Color(.tertiarySystemFill).opacity(0.5) : Color.clear)
        .overlay(Rectangle().stroke(Color(.separator).opacity(0.2), lineWidth: 0.5))
    }

    private func cell(_ sub: Subordinate, _ day: Date) -> some View {
        let leave = leaveFor(sub, day)
        let shift = shiftFor(sub, day)
        let weekend = isWeekend(day)
        return Button {
            detail = RosterCell(subId: sub.id, date: day)
        } label: {
            ZStack {
                Rectangle().fill(weekend ? Color(.tertiarySystemFill).opacity(0.4) : Color.clear)
                if let leave = leave {
                    cellChip(String(leave.rawValue.prefix(1)), rosterLeaveColor(leave))
                } else if let shift = shift {
                    cellChip(shift.shortLabel, rosterShiftColor(shift))
                }
            }
            .frame(width: cellW, height: cellH)
            .overlay(Rectangle().stroke(Color(.separator).opacity(0.2), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func cellChip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1).minimumScaleFactor(0.6)
            .frame(width: cellW - 8, height: cellH - 10)
            .background(color.gradient)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: 計算

    private func shiftFor(_ sub: Subordinate, _ day: Date) -> ShiftType? {
        let cal = Calendar.current
        return sub.shifts.first { cal.isDate($0.date, inSameDayAs: day) }?.type
    }

    private func leaveFor(_ sub: Subordinate, _ day: Date) -> LeaveType? {
        let cal = Calendar.current
        let d = cal.startOfDay(for: day)
        for r in sub.records where r.type == .leave {
            let s = cal.startOfDay(for: r.date)
            let e = cal.startOfDay(for: r.endDate ?? r.date)
            if d >= s && d <= e { return r.leaveType ?? .personal }
        }
        return nil
    }

    private func isWeekend(_ d: Date) -> Bool {
        let wd = Calendar.current.component(.weekday, from: d)
        return wd == 1 || wd == 7
    }

    private func weekdayShort(_ d: Date) -> String {
        let wd = Calendar.current.component(.weekday, from: d)  // 1 = 週日
        return ["日", "一", "二", "三", "四", "五", "六"][max(0, min(6, wd - 1))]
    }

    private func shiftMonth(_ delta: Int) {
        if let m = Calendar.current.date(byAdding: .month, value: delta, to: month) { month = m }
    }
}

// MARK: - 格子詳情（摘要 + 設定班別 + 快速請假 + 前往詳情）

private struct RosterCellDetailSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @ObservedObject var scheduleStore: ShiftScheduleStore
    @Environment(\.dismiss) private var dismiss

    let cell: RosterCell
    @State private var showAddLeave = false
    @State private var goDetail = false

    private var sub: Subordinate? { lifeStore.subordinates.first { $0.id == cell.subId } }

    private var isHoliday: Bool {
        let wd = Calendar.current.component(.weekday, from: cell.date)
        return wd == 1 || wd == 7
    }

    private var currentShift: ShiftType? {
        let cal = Calendar.current
        return sub?.shifts.first { cal.isDate($0.date, inSameDayAs: cell.date) }?.type
    }

    private static let headerDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d（EEE）"
        return f
    }()

    private var headerTitle: String {
        "\(sub?.name ?? "")　\(Self.headerDateFormatter.string(from: cell.date))"
    }

    var body: some View {
        NavigationStack {
            Form {
                shiftSection
                summarySection
                actionSection
            }
            .navigationTitle(headerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $showAddLeave) {
                RecordEditorSheet(subordinateId: cell.subId, type: .leave, editing: nil)
            }
            .sheet(isPresented: $goDetail) {
                if let sub = sub { SubordinateDetailView(subordinate: sub) }
            }
        }
    }

    private var shiftSection: some View {
        Section("班別") {
            HStack {
                Text("目前班別")
                Spacer()
                Text(currentShift?.rawValue ?? "未排班")
                    .foregroundStyle(currentShift.map { rosterShiftColor($0) } ?? .secondary)
                    .bold()
            }
            if let s = currentShift, s.hasWorkTime,
               let r = scheduleStore.schedule.range(for: s, isHoliday: isHoliday) {
                HStack {
                    Text(isHoliday ? "時間（假日）" : "時間（平日）").foregroundStyle(.secondary)
                    Spacer()
                    Text(r.display).monospacedDigit()
                }
            }
            Menu {
                ForEach(ShiftType.allCases) { t in
                    Button(t.rawValue) { lifeStore.setShift(subordinateId: cell.subId, date: cell.date, type: t) }
                }
                Divider()
                Button("清除班別", role: .destructive) {
                    lifeStore.setShift(subordinateId: cell.subId, date: cell.date, type: nil)
                }
            } label: {
                Label("設定 / 變更班別", systemImage: "calendar.badge.clock")
            }
            Button {
                lifeStore.applyNightShiftRotation(subordinateId: cell.subId, startDate: cell.date)
            } label: {
                Label("從今天套用大夜班輪班（8 天）", systemImage: "arrow.triangle.2.circlepath")
            }
        }
    }

    private var summarySection: some View {
        Section("當天摘要") {
            let leave = leaveRecord
            let meets = meetingsToday
            let dueTasks = tasksToday
            if leave == nil && meets.isEmpty && dueTasks.isEmpty {
                Text("當天無請假 / 會議 / 任務").foregroundStyle(.secondary)
            }
            if let leave = leave {
                Label("請假：\(leave.leaveType?.rawValue ?? "")", systemImage: "calendar.badge.minus")
                    .foregroundStyle(.teal)
            }
            ForEach(meets) { m in
                Label(m.topic.isEmpty ? "會議" : m.topic, systemImage: "person.2.fill")
                    .foregroundStyle(.indigo)
            }
            ForEach(dueTasks) { t in
                Label("\(t.topic.isEmpty ? "任務" : t.topic)（截止）", systemImage: "checklist")
                    .foregroundStyle(.cyan)
            }
        }
    }

    private var actionSection: some View {
        Section {
            Button { showAddLeave = true } label: {
                Label("快速新增請假", systemImage: "plus.circle").foregroundStyle(.teal)
            }
            Button { goDetail = true } label: {
                Label("前往部屬詳情頁", systemImage: "person.text.rectangle").foregroundStyle(.blue)
            }
        }
    }

    // 當天事項
    private var leaveRecord: SubordinateRecord? {
        guard let sub = sub else { return nil }
        let cal = Calendar.current
        let d = cal.startOfDay(for: cell.date)
        return sub.records.first { r in
            guard r.type == .leave else { return false }
            let s = cal.startOfDay(for: r.date)
            let e = cal.startOfDay(for: r.endDate ?? r.date)
            return d >= s && d <= e
        }
    }

    private var meetingsToday: [SubordinateMeeting] {
        guard let sub = sub else { return [] }
        let cal = Calendar.current
        return sub.meetings.filter { cal.isDate($0.date, inSameDayAs: cell.date) }
    }

    private var tasksToday: [SubordinateTask] {
        guard let sub = sub else { return [] }
        let cal = Calendar.current
        return sub.tasks.filter { t in
            if let due = t.dueDate, cal.isDate(due, inSameDayAs: cell.date) { return true }
            return cal.isDate(t.date, inSameDayAs: cell.date)
        }
    }
}

// MARK: - 班別時間設定

private struct ShiftScheduleSettingsView: View {
    @ObservedObject var scheduleStore: ShiftScheduleStore
    @Environment(\.dismiss) private var dismiss

    private let editable: [ShiftType] = [.nightShift, .eveningShift, .holidayDuty]

    var body: some View {
        NavigationStack {
            Form {
                ForEach(editable) { t in
                    Section(t.rawValue) {
                        timeRow("平日 開始", t, isHoliday: false, isStart: true)
                        timeRow("平日 結束", t, isHoliday: false, isStart: false)
                        timeRow("假日 開始", t, isHoliday: true, isStart: true)
                        timeRow("假日 結束", t, isHoliday: true, isStart: false)
                    }
                }
                Section {
                    Button("恢復預設時間", role: .destructive) { scheduleStore.schedule = .default }
                } footer: {
                    Text("時差假與休息沒有上下班時間。班別時間僅存於本機。")
                }
            }
            .navigationTitle("班別時間設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }

    private func timeRow(_ title: String, _ t: ShiftType, isHoliday: Bool, isStart: Bool) -> some View {
        DatePicker(title, selection: timeBinding(t, isHoliday: isHoliday, isStart: isStart),
                   displayedComponents: .hourAndMinute)
    }

    private func timeBinding(_ t: ShiftType, isHoliday: Bool, isStart: Bool) -> Binding<Date> {
        Binding(
            get: {
                let r = scheduleStore.schedule.range(for: t, isHoliday: isHoliday)
                    ?? ShiftTimeRange(startMinutes: 0, endMinutes: 0)
                let mins = isStart ? r.startMinutes : r.endMinutes
                return Calendar.current.date(bySettingHour: mins / 60, minute: mins % 60, second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                let cal = Calendar.current
                let mins = cal.component(.hour, from: newDate) * 60 + cal.component(.minute, from: newDate)
                var r = scheduleStore.schedule.range(for: t, isHoliday: isHoliday)
                    ?? ShiftTimeRange(startMinutes: 0, endMinutes: 0)
                if isStart { r.startMinutes = mins } else { r.endMinutes = mins }
                scheduleStore.schedule.set(r, for: t, isHoliday: isHoliday)
            }
        )
    }
}
