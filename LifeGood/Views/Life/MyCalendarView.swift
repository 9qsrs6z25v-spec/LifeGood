import SwiftUI

/// 我的行事曆：彙整當日家庭紀念日、工作會議與任務、本週快覽、未來里程碑。
struct MyCalendarView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var financeStore: FinanceStore

    @State private var selectedDate = Date()

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    MacaronDatePicker(selectedDate: $selectedDate)
                    todayEventsSection
                    weekPreviewSection
                    upcomingMilestonesSection
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("我的行事曆")
        }
    }

    // MARK: - 今日事件

    /// 統一的事件項目（含類型、標題、時間、副標）
    private struct CalendarEvent: Identifiable {
        let id: String
        let type: EventType
        let title: String
        let time: Date?
        let detail: String

        enum EventType {
            case birthday, anniversary, meeting, task, milestone
            var icon: String {
                switch self {
                case .birthday:    return "gift.fill"
                case .anniversary: return "heart.fill"
                case .meeting:     return "person.3.fill"
                case .task:        return "checklist"
                case .milestone:   return "flag.fill"
                }
            }
            var color: Color {
                switch self {
                case .birthday:    return Color(red: 0.99, green: 0.74, blue: 0.80)
                case .anniversary: return Color(red: 0.95, green: 0.55, blue: 0.65)
                case .meeting:     return Color(red: 0.78, green: 0.71, blue: 0.89)
                case .task:        return Color(red: 0.66, green: 0.86, blue: 0.74)
                case .milestone:   return Color(red: 0.99, green: 0.80, blue: 0.65)
                }
            }
            var name: String {
                switch self {
                case .birthday: return "生日"
                case .anniversary: return "紀念日"
                case .meeting: return "會議"
                case .task: return "任務"
                case .milestone: return "里程碑"
                }
            }
        }
    }

    /// 將生日 / 紀念日的「年份」對齊到當年（用於跨年比對）
    private func annualOccurrence(of date: Date, year: Int) -> Date {
        var comp = calendar.dateComponents([.month, .day], from: date)
        comp.year = year
        return calendar.date(from: comp) ?? date
    }

    private func eventsOn(_ day: Date) -> [CalendarEvent] {
        var events: [CalendarEvent] = []
        let year = calendar.component(.year, from: day)

        // 家庭生日（每年同一天）
        for member in lifeStore.familyMembers {
            if let bd = member.birthday {
                let occ = annualOccurrence(of: bd, year: year)
                if calendar.isDate(occ, inSameDayAs: day) {
                    let age = year - calendar.component(.year, from: bd)
                    events.append(CalendarEvent(
                        id: "bd-\(member.id.uuidString)",
                        type: .birthday,
                        title: "\(member.chineseName) 生日",
                        time: nil,
                        detail: age > 0 ? "\(age) 歲" : member.role.rawValue
                    ))
                }
            }
            if member.role == .spouse, let md = member.marriageDate {
                let occ = annualOccurrence(of: md, year: year)
                if calendar.isDate(occ, inSameDayAs: day) {
                    let years = year - calendar.component(.year, from: md)
                    events.append(CalendarEvent(
                        id: "anniv-\(member.id.uuidString)",
                        type: .anniversary,
                        title: "結婚紀念日",
                        time: nil,
                        detail: years > 0 ? "\(years) 週年" : "結婚紀念"
                    ))
                }
            }
        }

        // 部屬會議
        for sub in lifeStore.subordinates {
            for m in sub.meetings where calendar.isDate(m.date, inSameDayAs: day) {
                events.append(CalendarEvent(
                    id: "mtg-\(m.id.uuidString)",
                    type: .meeting,
                    title: m.topic.isEmpty ? "未命名會議" : m.topic,
                    time: m.date,
                    detail: "\(sub.name) · \(m.durationMinutes) 分鐘"
                ))
            }
        }

        // 部屬任務（建立日或截止日落於當天）
        for sub in lifeStore.subordinates {
            for t in sub.tasks {
                let onCreate = calendar.isDate(t.date, inSameDayAs: day)
                let onDue = t.dueDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false
                if onCreate || onDue {
                    events.append(CalendarEvent(
                        id: "task-\(t.id.uuidString)\(onDue ? "-due" : "")",
                        type: .task,
                        title: t.topic.isEmpty ? "未命名任務" : t.topic,
                        time: onCreate ? t.date : t.dueDate,
                        detail: "\(sub.name)\(onDue ? " · 今日截止" : "")"
                    ))
                }
            }
        }

        // 人生里程碑（精準日期）
        for ms in lifeStore.milestones where calendar.isDate(ms.date, inSameDayAs: day) {
            events.append(CalendarEvent(
                id: "ms-\(ms.id.uuidString)",
                type: .milestone,
                title: ms.title,
                time: ms.date,
                detail: ms.category.rawValue
            ))
        }

        return events.sorted { (a, b) in
            switch (a.time, b.time) {
            case let (la?, lb?): return la < lb
            case (nil, _?): return true   // 全日事件排前
            case (_?, nil): return false
            default: return a.title < b.title
            }
        }
    }

    private var todayEvents: [CalendarEvent] { eventsOn(selectedDate) }

    private var todayEventsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("當日事件",
                          icon: "calendar.badge.clock",
                          color: Color(red: 0.95, green: 0.55, blue: 0.65),
                          count: todayEvents.count)

            if todayEvents.isEmpty {
                emptyHint("這天沒有特別事件")
            } else {
                ForEach(todayEvents) { ev in
                    eventRow(ev)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func eventRow(_ ev: CalendarEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ev.type.icon)
                .font(.caption)
                .foregroundStyle(ev.type.color)
                .frame(width: 22, height: 22)
                .background(ev.type.color.opacity(0.18))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(ev.title).font(.subheadline.weight(.medium))
                    Text(ev.type.name).font(.caption2.weight(.medium))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(ev.type.color.opacity(0.18))
                        .foregroundStyle(ev.type.color)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                HStack(spacing: 6) {
                    if let t = ev.time {
                        Text(fmtTime(t)).font(.caption2).foregroundStyle(.tertiary)
                    } else {
                        Text("全日").font(.caption2).foregroundStyle(.tertiary)
                    }
                    if !ev.detail.isEmpty {
                        Text(ev.detail).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    // MARK: - 本週快覽（以選取日為中心向後 7 天）

    private var weekPreviewSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("接下來 7 天",
                          icon: "calendar",
                          color: Color(red: 0.78, green: 0.71, blue: 0.89),
                          count: weekDates.reduce(0) { $0 + eventsOn($1).count })

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(weekDates, id: \.self) { date in
                        weekDayCard(date: date, events: eventsOn(date))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var weekDates: [Date] {
        (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset,
                          to: calendar.startOfDay(for: selectedDate))
        }
    }

    private func weekDayCard(date: Date, events: [CalendarEvent]) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let weekday = ["日", "一", "二", "三", "四", "五", "六"][calendar.component(.weekday, from: date) - 1]
        let day = calendar.component(.day, from: date)
        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 4) {
                Text(weekday).font(.caption2).foregroundStyle(isSelected ? .white : .secondary)
                Text("\(day)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : (isToday ? .green : .primary))
                if events.isEmpty {
                    Circle().fill(Color.clear).frame(width: 6, height: 6)
                } else {
                    HStack(spacing: 2) {
                        ForEach(0..<min(events.count, 3), id: \.self) { i in
                            Circle()
                                .fill(events[i].type.color)
                                .frame(width: 6, height: 6)
                        }
                    }
                }
            }
            .frame(width: 50, height: 70)
            .background(isSelected ? Color.green : Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 未來 30 天里程碑

    private var upcomingMilestones: [LifeMilestone] {
        let now = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 30, to: now) ?? now
        return lifeStore.milestones
            .filter { $0.date >= now && $0.date <= end }
            .sorted { $0.date < $1.date }
    }

    private var upcomingMilestonesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("未來 30 天里程碑",
                          icon: "flag.fill",
                          color: Color(red: 0.99, green: 0.80, blue: 0.65),
                          count: upcomingMilestones.count)

            if upcomingMilestones.isEmpty {
                emptyHint("尚無排程的里程碑")
            } else {
                ForEach(upcomingMilestones.prefix(8)) { ms in
                    HStack(spacing: 10) {
                        Image(systemName: ms.category.icon)
                            .font(.caption).foregroundStyle(.orange).frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ms.title).font(.subheadline.weight(.medium))
                            HStack(spacing: 6) {
                                Text(fmtDate(ms.date)).font(.caption2).foregroundStyle(.tertiary)
                                Text(ms.category.rawValue).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(daysUntil(ms.date))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                }
                if upcomingMilestones.count > 8 {
                    Text("還有 \(upcomingMilestones.count - 8) 個...")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .padding(.horizontal).padding(.bottom, 12)
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
            Text("\(count)").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal).padding(.bottom, 12)
    }

    private func fmtTime(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }

    private func fmtDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M/d (EEE)"
        f.locale = Locale(identifier: "zh_TW")
        return f.string(from: d)
    }

    private func daysUntil(_ d: Date) -> String {
        let now = calendar.startOfDay(for: Date())
        let then = calendar.startOfDay(for: d)
        let days = calendar.dateComponents([.day], from: now, to: then).day ?? 0
        if days == 0 { return "今天" }
        if days == 1 { return "明天" }
        return "\(days) 天後"
    }
}

#Preview {
    MyCalendarView()
        .environmentObject(LifeStore())
        .environmentObject(FinanceStore())
}
