import SwiftUI
import EventKit

/// 我的行事曆：彙整當日家庭紀念日、工作會議與任務、本週快覽、未來里程碑、Apple 行事曆事件。
struct MyCalendarView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var financeStore: FinanceStore
    @ObservedObject private var appleCal = AppleCalendarBridge.shared

    @State private var selectedDate = Date()
    @State private var showAdd = false
    @State private var editingEvent: PersonalEvent?

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    MacaronDatePicker(selectedDate: $selectedDate)
                    appleCalendarBanner
                    todayEventsSection
                    weekPreviewSection
                    upcomingMilestonesSection
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("我的行事曆")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3).foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                PersonalEventEditor(initialDate: selectedDate, editing: nil)
            }
            .sheet(item: $editingEvent) { ev in
                PersonalEventEditor(initialDate: ev.date, editing: ev)
            }
            .task {
                if appleCal.authorizationStatus == .notDetermined {
                    await appleCal.requestAccess()
                } else {
                    appleCal.refreshStatus()
                }
            }
        }
    }

    /// 顯示 Apple 行事曆狀態 banner：未授權／拒絕時顯示，已授權則隱藏
    @ViewBuilder
    private var appleCalendarBanner: some View {
        if appleCal.authorizationStatus == .notDetermined {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.plus").foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("連動 Apple 行事曆")
                        .font(.subheadline.weight(.semibold))
                    Text("授權後可在這裡看到 iOS 行事曆事件")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button("開啟") {
                    Task { await appleCal.requestAccess() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        } else if appleCal.isDenied {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple 行事曆權限被拒")
                        .font(.subheadline.weight(.semibold))
                    Text("請到「設定 → LifeGood」開啟「行事曆」權限")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button("設定") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
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
        var personalEventId: UUID? = nil

        enum EventType {
            case birthday, anniversary, meeting, task, milestone, appleCalendar
            var icon: String {
                switch self {
                case .birthday:      return "gift.fill"
                case .anniversary:   return "heart.fill"
                case .meeting:       return "person.3.fill"
                case .task:          return "checklist"
                case .milestone:     return "flag.fill"
                case .appleCalendar: return "calendar"
                }
            }
            var color: Color {
                switch self {
                case .birthday:      return Color(red: 0.99, green: 0.74, blue: 0.80)
                case .anniversary:   return Color(red: 0.95, green: 0.55, blue: 0.65)
                case .meeting:       return Color(red: 0.78, green: 0.71, blue: 0.89)
                case .task:          return Color(red: 0.66, green: 0.86, blue: 0.74)
                case .milestone:     return Color(red: 0.99, green: 0.80, blue: 0.65)
                case .appleCalendar: return Color(red: 0.45, green: 0.65, blue: 0.95)
                }
            }
            var name: String {
                switch self {
                case .birthday: return "生日"
                case .anniversary: return "紀念日"
                case .meeting: return "會議"
                case .task: return "任務"
                case .milestone: return "里程碑"
                case .appleCalendar: return "系統行事曆"
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

        // Apple 系統行事曆（讀取自 EventKit）— 排除已從 LifeGood 同步出去的事件，避免重複
        if appleCal.hasAccess {
            let syncedIds = Set(lifeStore.personalEvents.compactMap { $0.ekEventIdentifier })
            for ev in appleCal.events(forDay: day, calendar: calendar) where !syncedIds.contains(ev.eventIdentifier) {
                let calName = ev.calendar?.title ?? "行事曆"
                let location = (ev.location?.trimmingCharacters(in: .whitespaces)) ?? ""
                var detailParts: [String] = [calName]
                if ev.isAllDay { detailParts.append("全日") }
                if !location.isEmpty { detailParts.append(location) }
                events.append(CalendarEvent(
                    id: "ek-\(ev.calendarItemIdentifier)-\(ev.startDate.timeIntervalSince1970)",
                    type: .appleCalendar,
                    title: ev.title.isEmpty ? "(無標題)" : ev.title,
                    time: ev.isAllDay ? nil : ev.startDate,
                    detail: detailParts.joined(separator: " · ")
                ))
            }
        }

        // 個人行事曆事件（事務 / 會議，含重複展開）
        for pe in lifeStore.personalEvents where pe.occurs(on: day, calendar: calendar) {
            let occTime = pe.occurrenceDate(on: day, calendar: calendar)
            let recurrenceLabel = pe.recurrence == .none ? "" : "🔁 "
            let baseDetail: String = pe.durationMinutes > 0
                ? "\(recurrenceLabel)\(pe.durationMinutes) 分鐘"
                : "\(recurrenceLabel)全日"
            let withNote = pe.note.isEmpty ? baseDetail : "\(baseDetail) · \(pe.note)"
            events.append(CalendarEvent(
                id: "pe-\(pe.id.uuidString)-\(calendar.startOfDay(for: day).timeIntervalSince1970)",
                type: pe.kind == .meeting ? .meeting : .task,
                title: pe.title.isEmpty ? pe.kind.rawValue : pe.title,
                time: pe.durationMinutes > 0 ? occTime : nil,
                detail: withNote,
                personalEventId: pe.id
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

    /// 當前選定日期顯示用（今天 → 「當日事件」、其他日 → 「2025/5/15 (Wed) 事件」）
    private var selectedDayHeaderTitle: String {
        if calendar.isDateInToday(selectedDate) { return "當日事件" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d (EEE)"
        return "\(f.string(from: selectedDate)) 事件"
    }

    private var todayEventsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(selectedDayHeaderTitle,
                          icon: "calendar.badge.clock",
                          color: Color(red: 0.95, green: 0.55, blue: 0.65),
                          count: todayEvents.count)

            if todayEvents.isEmpty {
                emptyHint("這天沒有特別事件")
            } else {
                ForEach(todayEvents) { ev in
                    if let pid = ev.personalEventId,
                       let pe = lifeStore.personalEvents.first(where: { $0.id == pid }) {
                        Button { editingEvent = pe } label: { eventRow(ev) }
                            .buttonStyle(.plain)
                    } else {
                        eventRow(ev)
                    }
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

// MARK: - 個人行事曆事件編輯器

struct PersonalEventEditor: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let initialDate: Date
    let editing: PersonalEvent?

    @State private var title: String = ""
    @State private var kind: PersonalEventKind = .meeting
    @State private var date: Date = Date()
    @State private var durationMinutes: Int = 30
    @State private var note: String = ""
    @State private var recurrence: EventRecurrence = .none
    @State private var hasRecurrenceEnd: Bool = false
    @State private var recurrenceEndDate: Date = Date().addingTimeInterval(60 * 60 * 24 * 90)
    @State private var reminder: EventReminder = .none
    @State private var showDeleteConfirm = false
    @State private var permissionDeniedAlert = false
    // Apple 行事曆連動
    @State private var location: String = ""
    @State private var syncToAppleCalendar: Bool = false
    @State private var selectedAppleCalendarId: String?
    @ObservedObject private var appleCal = AppleCalendarBridge.shared

    /// 常用長度選項（分鐘），0 = 全日
    private let durationOptions: [(label: String, minutes: Int)] = [
        ("全日", 0),
        ("15 分鐘", 15),
        ("30 分鐘", 30),
        ("1 小時", 60),
        ("90 分鐘", 90),
        ("2 小時", 120),
        ("半天 (4h)", 240),
        ("一天 (8h)", 480)
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    Picker("類型", selection: $kind) {
                        ForEach(PersonalEventKind.allCases) { k in
                            Label(k.rawValue, systemImage: k.icon).tag(k)
                        }
                    }
                    TextField("標題", text: $title)
                }

                Section("時間") {
                    DatePicker("開始", selection: $date,
                               displayedComponents: durationMinutes == 0 ? [.date] : [.date, .hourAndMinute])
                    Picker("長度", selection: $durationMinutes) {
                        ForEach(durationOptions, id: \.minutes) { opt in
                            Text(opt.label).tag(opt.minutes)
                        }
                    }
                    if durationMinutes > 0 {
                        HStack {
                            Text("結束").foregroundStyle(.secondary)
                            Spacer()
                            Text(formatEnd(date: date, minutes: durationMinutes))
                                .font(.subheadline)
                                .foregroundStyle(.green)
                        }
                    }
                }

                Section("重複") {
                    Picker("頻率", selection: $recurrence) {
                        ForEach(EventRecurrence.allCases) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                    if recurrence != .none {
                        Toggle("設定結束日", isOn: $hasRecurrenceEnd)
                        if hasRecurrenceEnd {
                            DatePicker("結束於", selection: $recurrenceEndDate, in: date..., displayedComponents: .date)
                        }
                    }
                }

                Section("提醒") {
                    Picker("提前提醒", selection: $reminder) {
                        ForEach(EventReminder.allCases) { r in
                            Text(r.displayName).tag(r)
                        }
                    }
                    if reminder != .none {
                        Text(reminderHint)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                appleCalendarSection

                Section("備註") {
                    TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
                }

                if editing != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("刪除事件", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "新增事件" : "編輯事件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing == nil ? "新增" : "儲存") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("確定刪除？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) { delete() }
                Button("取消", role: .cancel) {}
            }
            .alert("通知權限被拒", isPresented: $permissionDeniedAlert) {
                Button("好") {}
            } message: {
                Text("請至 iOS 設定 → LifeGood → 通知 開啟，否則無法收到提醒。")
            }
            .onAppear {
                if let e = editing {
                    title = e.title
                    kind = e.kind
                    date = e.date
                    durationMinutes = e.durationMinutes
                    note = e.note
                    recurrence = e.recurrence
                    if let endDate = e.recurrenceEndDate {
                        hasRecurrenceEnd = true
                        recurrenceEndDate = endDate
                    }
                    reminder = EventReminder(rawValue: e.reminderMinutes) ?? .none
                    location = e.location
                    syncToAppleCalendar = e.syncToAppleCalendar
                    selectedAppleCalendarId = e.appleCalendarId
                } else {
                    // 預設將時間設為使用者選的日期 + 當下時間
                    let now = Date()
                    let cal = Calendar.current
                    let timeComp = cal.dateComponents([.hour, .minute], from: now)
                    var dayComp = cal.dateComponents([.year, .month, .day], from: initialDate)
                    dayComp.hour = timeComp.hour
                    dayComp.minute = timeComp.minute
                    date = cal.date(from: dayComp) ?? initialDate
                }
                // 預設行事曆 ID（若使用者尚未選擇）
                if selectedAppleCalendarId == nil {
                    selectedAppleCalendarId = appleCal.defaultCalendarId
                }
            }
        }
    }

    @ViewBuilder
    private var appleCalendarSection: some View {
        Section {
            Toggle(isOn: $syncToAppleCalendar) {
                Label("同步到 Apple 行事曆", systemImage: "calendar.badge.plus")
            }
            .tint(.blue)
            .disabled(appleCal.isDenied)

            if syncToAppleCalendar {
                if appleCal.hasAccess {
                    if !appleCal.writableCalendars.isEmpty {
                        Picker("寫入行事曆", selection: $selectedAppleCalendarId) {
                            ForEach(appleCal.writableCalendars, id: \.calendarIdentifier) { c in
                                HStack {
                                    Circle().fill(Color(cgColor: c.cgColor)).frame(width: 10, height: 10)
                                    Text(c.title)
                                }
                                .tag(c.calendarIdentifier as String?)
                            }
                        }
                    }
                    TextField("地點（選填）", text: $location)
                } else if appleCal.authorizationStatus == .notDetermined {
                    Text("儲存時將跳出 Apple 行事曆授權")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Apple 行事曆")
        } footer: {
            if appleCal.isDenied {
                Text("Apple 行事曆權限被拒，無法寫入。請至「設定 → LifeGood」開啟。")
                    .foregroundStyle(.orange)
            } else if syncToAppleCalendar && editing?.ekEventIdentifier != nil {
                Text("關閉開關並儲存，會把 Apple 行事曆中對應的事件一起移除。")
            } else {
                Text("打開後，事件會寫入並同步到 Apple 行事曆。地點 / 提醒 / 重複都會帶過去。")
            }
        }
    }

    /// 提醒提示文字
    private var reminderHint: String {
        guard reminder != .none else { return "" }
        let cal = Calendar.current
        let fire = cal.date(byAdding: .minute, value: -reminder.rawValue, to: date) ?? date
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        if recurrence == .none {
            return "首次提醒：\(f.string(from: fire))"
        } else {
            return "首次提醒：\(f.string(from: fire))，之後依「\(recurrence.rawValue)」重複"
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }
        Task { await performSave(trimmedTitle: trimmedTitle) }
    }

    @MainActor
    private func performSave(trimmedTitle: String) async {
        // 先按目前 form 內容組事件
        var event = PersonalEvent(
            id: editing?.id ?? UUID(),
            title: trimmedTitle,
            kind: kind,
            date: date,
            durationMinutes: durationMinutes,
            note: note.trimmingCharacters(in: .whitespaces),
            recurrence: recurrence,
            recurrenceEndDate: (recurrence != .none && hasRecurrenceEnd) ? recurrenceEndDate : nil,
            reminderMinutes: reminder.rawValue,
            location: location.trimmingCharacters(in: .whitespaces),
            syncToAppleCalendar: syncToAppleCalendar,
            appleCalendarId: selectedAppleCalendarId,
            ekEventIdentifier: editing?.ekEventIdentifier
        )

        // Apple 行事曆同步
        if syncToAppleCalendar {
            // 還沒拿權限就先請求
            if appleCal.authorizationStatus == .notDetermined {
                await appleCal.requestAccess()
            }
            if appleCal.hasAccess {
                if let newId = appleCal.writeOrUpdate(from: event, calendarId: selectedAppleCalendarId ?? appleCal.defaultCalendarId) {
                    event.ekEventIdentifier = newId
                }
            }
        } else if let oldId = editing?.ekEventIdentifier {
            // 從同步切回不同步 → 刪掉 EKEvent
            appleCal.delete(eventIdentifier: oldId)
            event.ekEventIdentifier = nil
        }

        if let idx = lifeStore.personalEvents.firstIndex(where: { $0.id == event.id }) {
            lifeStore.personalEvents[idx] = event
        } else {
            lifeStore.personalEvents.append(event)
        }

        // 排程通知（會自動覆蓋舊的）
        if reminder != .none {
            let granted = await NotificationManager.shared.requestAuthorization()
            if !granted {
                permissionDeniedAlert = true
            }
        }
        await NotificationManager.shared.schedule(event)
        dismiss()
    }

    private func delete() {
        guard let e = editing else { return }
        NotificationManager.shared.cancel(eventId: e.id)
        if let ekId = e.ekEventIdentifier {
            appleCal.delete(eventIdentifier: ekId)
        }
        lifeStore.personalEvents.removeAll { $0.id == e.id }
        dismiss()
    }

    private func formatEnd(date: Date, minutes: Int) -> String {
        let end = Calendar.current.date(byAdding: .minute, value: minutes, to: date) ?? date
        let f = DateFormatter()
        let cal = Calendar.current
        if cal.isDate(end, inSameDayAs: date) {
            f.dateFormat = "HH:mm"
        } else {
            f.dateFormat = "M/d HH:mm"
        }
        return f.string(from: end)
    }
}

#Preview {
    MyCalendarView()
        .environmentObject(LifeStore())
        .environmentObject(FinanceStore())
}
