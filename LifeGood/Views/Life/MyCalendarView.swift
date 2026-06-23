import SwiftUI
import EventKit
import MapKit

// MARK: - 美化紀錄（MyCalendarView）2026-06
// ① sectionHeader：漸層膠囊色條 + 計數膠囊，與 OverviewView / IncomeView 設計語言保持均值。
// ② eventRow：36pt 圓圈改用 LinearGradient（0.22→0.09 opacity, topLeading→bottomTrailing）填色
//    + shadow(color: .opacity(0.18), radius: 5, x: 0, y: 2)，與其他頁面卡片立體感一致。
// ③ weekDayCard：選中日加 shadow、寬度 54pt；今日小綠點標記；事件圓點 5pt + shadow。
// ④ 空狀態：emptyPlaceholder 卡片（雙環脈衝 + CTA），與 IncomeView / VariableExpenseView 一致。
// ⑤ appleCalendarBanner：overlay 邊框 + icon 背景圓 + 陰影。
// ⑥ 進場動畫：.opacity + .offset 彈跳進場（錯落延遲）。
// ⑦ upcomingMilestonesSection：新增 milestoneAccent() 輔助函式，各類別採獨立色彩，
//    圖示圓改 LinearGradient + shadow；類別標籤改圓角膠囊 badge，與 LifeOverviewView 一致。
// [2026-06 v2] 本次美化方向：
// ⑧ calendarHeroCard：新增藍色漸層英雄摘要卡（今日大字日期 + 月份/星期副標 +
//    今日事件計數白色膠囊 + 未來里程碑 KPI 膠囊 + 三欄 KPI 橫列：今日/本週七天/未來30天）
//    三顆散景裝飾圓 + 頂部玻璃光澤（white.opacity(0.18)），
//    對齊 FinanceOverviewView.totalAssetsCard / IncomeView.summaryHeader 英雄卡片規格；
//    heroCardAppeared spring 進場動畫（透明度 + Y 位移 20pt），位於 MacaronDatePicker 上方。
// ⑨ 三個 section 卡片（當日事件 / 本週快覽 / 未來里程碑）加入 overlay RoundedRectangle
//    stroke（separator.opacity(0.12), 0.75pt），提升深色模式邊界感，
//    對齊 OverviewView / IncomeView 全 App 卡片精緻規格。
// ⑩ eventRow 事件類型膠囊：補入 Capsule().stroke(ev.type.color.opacity(0.22), 0.6pt)，
//    對齊 OverviewView.categoryRow / LifeOverviewView.categoryBreakdownSection 膠囊邊框規格。
// ⑪ upcomingMilestonesSection 里程碑日期：從純 .caption2 tertiary 文字升級為
//    calendar 圖示 + tertiarySystemFill Capsule 徽章，
//    對齊 OverviewView.recentRow / CareerView v2 日期膠囊設計語言。

/// 我的行事曆：彙整當日家庭紀念日、工作會議與任務、本週快覽、未來里程碑、Apple 行事曆事件。
struct MyCalendarView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var financeStore: FinanceStore
    @StateObject private var appleCal = AppleCalendarBridge.shared

    @State private var selectedDate = Date()
    @State private var showAdd = false
    @State private var editingEvent: PersonalEvent?

    // 進場動畫旗標
    @State private var heroCardAppeared = false
    @State private var todayCardAppeared = false
    @State private var weekCardAppeared = false
    @State private var milestonesCardAppeared = false

    private let calendar = Calendar.current

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let calendarDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d (EEE)"
        f.locale = Locale(identifier: "zh_TW"); return f
    }()

    var body: some View {
        // Pre-compute once per render: avoids 16 redundant eventsOn() + 6 upcomingMilestones calls
        let resolvedWeekDates = weekDates
        let startOfSelectedDay = calendar.startOfDay(for: selectedDate)
        let startOfToday = calendar.startOfDay(for: Date())
        let weekEventsMap = Dictionary(uniqueKeysWithValues: resolvedWeekDates.map { ($0, eventsOn($0)) })
        let upcomingMS = upcomingMilestones
        let heroIsToday = startOfSelectedDay == startOfToday
        let heroWeekDates = heroIsToday ? resolvedWeekDates
            : (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfToday) }
        let heroEventsMap = heroIsToday ? weekEventsMap
            : Dictionary(uniqueKeysWithValues: heroWeekDates.map { ($0, eventsOn($0)) })
        let heroTodayCount = heroEventsMap[startOfToday]?.count ?? 0
        let heroWeekTotal = heroWeekDates.reduce(0) { $0 + (heroEventsMap[$1]?.count ?? 0) }
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    calendarHeroCard(todayEvCount: heroTodayCount, weekTotal: heroWeekTotal, upcomingCount: upcomingMS.count)
                        .opacity(heroCardAppeared ? 1 : 0)
                        .offset(y: heroCardAppeared ? 0 : 20)
                        .onAppear {
                            withAnimation(.spring(response: 0.52, dampingFraction: 0.80).delay(0.04)) {
                                heroCardAppeared = true
                            }
                        }
                        .onDisappear { heroCardAppeared = false }
                    MacaronDatePicker(selectedDate: $selectedDate)
                    appleCalendarBanner
                    todayEventsSection(events: weekEventsMap[startOfSelectedDay] ?? [])
                        .opacity(todayCardAppeared ? 1 : 0)
                        .offset(y: todayCardAppeared ? 0 : 18)
                        .onAppear {
                            withAnimation(.spring(response: 0.52, dampingFraction: 0.80).delay(0.08)) {
                                todayCardAppeared = true
                            }
                        }
                        .onDisappear { todayCardAppeared = false }
                    weekPreviewSection(weekDates: resolvedWeekDates, weekEventsMap: weekEventsMap)
                        .opacity(weekCardAppeared ? 1 : 0)
                        .offset(y: weekCardAppeared ? 0 : 18)
                        .onAppear {
                            withAnimation(.spring(response: 0.52, dampingFraction: 0.80).delay(0.16)) {
                                weekCardAppeared = true
                            }
                        }
                        .onDisappear { weekCardAppeared = false }
                    upcomingMilestonesSection(milestones: upcomingMS)
                        .opacity(milestonesCardAppeared ? 1 : 0)
                        .offset(y: milestonesCardAppeared ? 0 : 18)
                        .onAppear {
                            withAnimation(.spring(response: 0.52, dampingFraction: 0.80).delay(0.24)) {
                                milestonesCardAppeared = true
                            }
                        }
                        .onDisappear { milestonesCardAppeared = false }

                    // 部屬事項（請假 / 會議 / 任務 / 未完成會議 / 未完成任務）
                    if !lifeStore.subordinates.isEmpty {
                        subordinateAgendaSection(date: startOfSelectedDay)
                    }
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
            HStack(spacing: 12) {
                // 圖示背景圓
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.blue)
                }
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
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.blue)
                .clipShape(Capsule())
            }
            .padding(14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.blue.opacity(0.12), lineWidth: 0.75)
            )
            .shadow(color: Color.blue.opacity(0.08), radius: 8, x: 0, y: 3)
            .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
            .padding(.horizontal)
        } else if appleCal.isDenied {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.orange)
                }
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
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.orange)
                .clipShape(Capsule())
            }
            .padding(14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.orange.opacity(0.15), lineWidth: 0.75)
            )
            .shadow(color: Color.orange.opacity(0.10), radius: 8, x: 0, y: 3)
            .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
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
        if let result = calendar.date(from: comp) { return result }
        // 2/29 在非閏年不存在時，改用 2/28，避免回傳原始日期造成跨年錯誤
        comp.day = (comp.day ?? 1) - 1
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
                    title: (ev.title ?? "").isEmpty ? "(無標題)" : (ev.title ?? "(無標題)"),
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

    /// 當前選定日期顯示用（今天 → 「當日事件」、其他日 → 「2025/5/15 (Wed) 事件」）
    private var selectedDayHeaderTitle: String {
        if calendar.isDateInToday(selectedDate) { return "當日事件" }
        return "\(Self.calendarDateFormatter.string(from: selectedDate)) 事件"
    }

    private func todayEventsSection(events: [CalendarEvent]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(selectedDayHeaderTitle,
                          icon: "calendar.badge.clock",
                          color: Color(red: 0.95, green: 0.55, blue: 0.65),
                          count: events.count)

            if events.isEmpty {
                emptyPlaceholder(
                    icon: "calendar",
                    title: "這天沒有特別事件",
                    subtitle: "新增事件或等待紀念日、里程碑到來"
                )
            } else {
                ForEach(Array(events.enumerated()), id: \.element.id) { idx, ev in
                    if let pid = ev.personalEventId,
                       let pe = lifeStore.personalEvents.first(where: { $0.id == pid }) {
                        Button { editingEvent = pe } label: { eventRow(ev) }
                            .buttonStyle(.plain)
                    } else {
                        eventRow(ev)
                    }
                    if idx < events.count - 1 {
                        Divider().padding(.leading, 60)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    private func eventRow(_ ev: CalendarEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 圖示圓：36pt LinearGradient + shadow，與 IncomeView / VariableExpenseView 均值
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [ev.type.color.opacity(0.22), ev.type.color.opacity(0.09)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                    .shadow(color: ev.type.color.opacity(0.18), radius: 5, x: 0, y: 2)
                Circle()
                    .stroke(ev.type.color.opacity(0.28), lineWidth: 0.75)
                    .frame(width: 36, height: 36)
                Image(systemName: ev.type.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ev.type.color)
            }
            VStack(alignment: .leading, spacing: 4) {
                // 標題 + 類型膠囊
                HStack(spacing: 6) {
                    Text(ev.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(ev.type.name)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(ev.type.color.opacity(0.15))
                        .foregroundStyle(ev.type.color)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(ev.type.color.opacity(0.22), lineWidth: 0.6))
                }
                // 時間 + 詳情
                HStack(spacing: 6) {
                    if let t = ev.time {
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            Text(fmtTime(t))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        HStack(spacing: 3) {
                            Image(systemName: "sun.max")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            Text("全日")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    if !ev.detail.isEmpty {
                        Text("·").font(.caption2).foregroundStyle(.quaternary)
                        Text(ev.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - 本週快覽（以選取日為中心向後 7 天）

    private func weekPreviewSection(weekDates: [Date], weekEventsMap: [Date: [CalendarEvent]]) -> some View {
        let totalCount = weekEventsMap.values.reduce(0) { $0 + $1.count }
        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader("接下來 7 天",
                          icon: "calendar",
                          color: Color(red: 0.78, green: 0.71, blue: 0.89),
                          count: totalCount)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(weekDates, id: \.self) { date in
                        weekDayCard(date: date, events: weekEventsMap[date] ?? [])
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 14)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
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
        let weekdayNames = ["日", "一", "二", "三", "四", "五", "六"]
        let weekdayIdx = calendar.component(.weekday, from: date) - 1
        let weekday = weekdayNames.indices.contains(weekdayIdx) ? weekdayNames[weekdayIdx] : ""
        let day = calendar.component(.day, from: date)

        return Button {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.70)) {
                selectedDate = date
            }
        } label: {
            VStack(spacing: 5) {
                Text(weekday)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : .secondary)
                Text("\(day)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : (isToday ? .green : .primary))

                // 今日標記：選中時不顯示（已有白色背景），未選中時顯示小綠點
                if isToday && !isSelected {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 4, height: 4)
                        .shadow(color: .green.opacity(0.5), radius: 2)
                } else if events.isEmpty {
                    Circle().fill(Color.clear).frame(width: 4, height: 4)
                } else {
                    // 事件彩點（最多 3 個）
                    HStack(spacing: 2) {
                        ForEach(0..<min(events.count, 3), id: \.self) { i in
                            Circle()
                                .fill(isSelected ? .white.opacity(0.90) : events[i].type.color)
                                .frame(width: 5, height: 5)
                                .shadow(
                                    color: isSelected ? .clear : events[i].type.color.opacity(0.45),
                                    radius: 1.5
                                )
                        }
                    }
                }
            }
            .frame(width: 54, height: 74)
            .background(
                ZStack {
                    if isSelected {
                        // 選中：綠色漸層底 + 輕微散景高光
                        LinearGradient(
                            colors: [Color.green, Color(red: 0.07, green: 0.52, blue: 0.38)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Circle()
                            .fill(.white.opacity(0.14))
                            .frame(width: 38, height: 38)
                            .offset(x: 14, y: -20)
                            .blur(radius: 8)
                    } else {
                        Color(.tertiarySystemFill)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(
                color: isSelected ? Color.green.opacity(0.42) : .clear,
                radius: 8, x: 0, y: 4
            )
            .scaleEffect(isSelected ? 1.04 : 1.0)
            .animation(.spring(response: 0.30, dampingFraction: 0.72), value: isSelected)
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

    private func upcomingMilestonesSection(milestones: [LifeMilestone]) -> some View {
        // 區塊標題用固定橙色，各里程碑列使用 milestoneAccent() 獨立色彩（與 LifeOverviewView 一致）
        let headerColor = Color(red: 0.99, green: 0.65, blue: 0.30)
        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader("未來 30 天里程碑",
                          icon: "flag.fill",
                          color: headerColor,
                          count: milestones.count)

            if milestones.isEmpty {
                emptyPlaceholder(
                    icon: "flag",
                    title: "尚無排程的里程碑",
                    subtitle: "在人生頁新增里程碑後顯示於此"
                )
            } else {
                ForEach(Array(milestones.prefix(8).enumerated()), id: \.element.id) { idx, ms in
                    // 每列採各自類別色彩，統一色彩語言與 LifeOverviewView milestoneTimelineSection
                    let msColor = milestoneAccent(ms.category)
                    HStack(spacing: 12) {
                        // 圖示圓：36pt LinearGradient + shadow，與 eventRow 及其他頁面卡片均值
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [msColor.opacity(0.22), msColor.opacity(0.09)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 36, height: 36)
                                .shadow(color: msColor.opacity(0.18), radius: 5, x: 0, y: 2)
                            Circle()
                                .stroke(msColor.opacity(0.28), lineWidth: 0.75)
                                .frame(width: 36, height: 36)
                            Image(systemName: ms.category.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(msColor)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ms.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            HStack(spacing: 5) {
                                HStack(spacing: 3) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    Text(fmtDate(ms.date))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(Capsule())
                                // 類別標籤：圓角膠囊 badge，與 IncomeView / VariableExpenseView 均值
                                Text(ms.category.rawValue)
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(msColor.opacity(0.14))
                                    .foregroundStyle(msColor)
                                    .clipShape(Capsule())
                            }
                        }
                        Spacer()
                        // 倒數天數膠囊：跟隨類別色彩
                        Text(daysUntil(ms.date))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(msColor)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(msColor.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(msColor.opacity(0.25), lineWidth: 0.6)
                            )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)

                    if idx < min(milestones.count, 8) - 1 {
                        Divider().padding(.leading, 62)
                    }
                }
                if milestones.count > 8 {
                    HStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle()
                                .fill(Color(.tertiaryLabel))
                                .frame(width: 3, height: 3)
                        }
                        Text("還有 \(milestones.count - 8) 個里程碑")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    // MARK: - [v2] 英雄摘要卡

    private func calendarHeroCard(todayEvCount: Int, weekTotal: Int, upcomingCount: Int) -> some View {
        let day = calendar.component(.day, from: Date())
        let month = calendar.component(.month, from: Date())
        let weekdayNames = ["日", "一", "二", "三", "四", "五", "六"]
        let weekdayIdx = calendar.component(.weekday, from: Date()) - 1
        let weekdayStr = weekdayNames.indices.contains(weekdayIdx) ? weekdayNames[weekdayIdx] : ""

        return VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("我的行事曆")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text("\(day)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(month) 月")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.80))
                            Text("週\(weekdayStr)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.60))
                        }
                    }
                    Text("今日 \(todayEvCount) 件事件")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.white.opacity(0.20))
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                        .padding(.top, 1)
                }
                Spacer()
                if upcomingCount > 0 {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("未來 30 天")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.62))
                        HStack(spacing: 3) {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("\(upcomingCount) 個里程碑")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(Color(red: 0.72, green: 0.95, blue: 0.82))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.white.opacity(0.18))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.30), lineWidth: 0.75))
                    }
                }
            }

            Rectangle()
                .fill(.white.opacity(0.20))
                .frame(height: 0.5)
                .padding(.vertical, 14)

            HStack(spacing: 0) {
                heroKpiCell(label: "今日", value: "\(todayEvCount) 件")
                Rectangle().fill(.white.opacity(0.22)).frame(width: 0.5, height: 28)
                heroKpiCell(label: "本週七天", value: "\(weekTotal) 件")
                Rectangle().fill(.white.opacity(0.22)).frame(width: 0.5, height: 28)
                heroKpiCell(label: "未來 30 天", value: "\(upcomingCount) 個")
            }
        }
        .padding(20)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.28, green: 0.48, blue: 0.90),
                        Color(red: 0.16, green: 0.30, blue: 0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(.white.opacity(0.13))
                    .frame(width: 130, height: 130)
                    .offset(x: 90, y: -50)
                    .blur(radius: 14)
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 85, height: 85)
                    .offset(x: -65, y: 52)
                    .blur(radius: 10)
                Circle()
                    .fill(.white.opacity(0.06))
                    .frame(width: 55, height: 55)
                    .offset(x: 28, y: 28)
                    .blur(radius: 8)
                LinearGradient(
                    colors: [.white.opacity(0.18), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.16, green: 0.30, blue: 0.72).opacity(0.42), radius: 18, x: 0, y: 9)
        .padding(.horizontal)
    }

    private func heroKpiCell(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 部屬事項卡片（彙整自部屬總覽）

    private static let subAgendaFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "M/d HH:mm"; return f
    }()
    private func subAgendaTime(_ d: Date) -> String { Self.subAgendaFmt.string(from: d) }

    private func subLeaves(on date: Date) -> [(sub: Subordinate, rec: SubordinateRecord)] {
        let d = calendar.startOfDay(for: date)
        return lifeStore.subordinates.flatMap { sub in
            sub.records.filter { r in
                guard r.type == .leave else { return false }
                let s = calendar.startOfDay(for: r.date)
                let e = calendar.startOfDay(for: r.endDate ?? r.date)
                return d >= s && d <= e
            }.map { (sub: sub, rec: $0) }
        }
    }
    private func subMeetings(on date: Date) -> [(sub: Subordinate, meeting: SubordinateMeeting)] {
        lifeStore.subordinates.flatMap { sub in
            sub.meetings.filter { calendar.isDate($0.date, inSameDayAs: date) }.map { (sub: sub, meeting: $0) }
        }
    }
    private func subReports(on date: Date) -> [(sub: Subordinate, report: WeeklyReport)] {
        lifeStore.subordinates.flatMap { sub in
            sub.weeklyReports.filter { calendar.isDate($0.date, inSameDayAs: date) }.map { (sub: sub, report: $0) }
        }
    }
    private func subTasks(on date: Date) -> [(sub: Subordinate, task: SubordinateTask)] {
        lifeStore.subordinates.flatMap { sub in
            sub.tasks.filter { t in
                guard !t.isCompleted else { return false }
                if let due = t.dueDate, calendar.isDate(due, inSameDayAs: date) { return true }
                return calendar.isDate(t.date, inSameDayAs: date)
            }.map { (sub: sub, task: $0) }
        }
    }
    private var subIncompleteMeetingItems: [(sub: Subordinate, meeting: SubordinateMeeting, item: MeetingItem)] {
        lifeStore.subordinates.flatMap { sub in
            sub.meetings.flatMap { m in
                m.items.filter { !$0.isCompleted }.map { (sub: sub, meeting: m, item: $0) }
            }
        }.sorted { $0.meeting.date > $1.meeting.date }
    }
    private var subIncompleteTasks: [(sub: Subordinate, task: SubordinateTask)] {
        lifeStore.subordinates.flatMap { sub in
            sub.tasks.filter { !$0.isCompleted }.map { (sub: sub, task: $0) }
        }.sorted { ($0.task.dueDate ?? $0.task.date) < ($1.task.dueDate ?? $1.task.date) }
    }

    private func subordinateAgendaSection(date: Date) -> some View {
        let leaves = subLeaves(on: date)
        let reports = subReports(on: date)
        let meetings = subMeetings(on: date)
        let tasks = subTasks(on: date)
        return VStack(spacing: 16) {
            subAgendaCard("部屬請假", "calendar.badge.minus", .teal, count: leaves.count, empty: "當日無人請假") {
                ForEach(Array(leaves.enumerated()), id: \.offset) { _, it in
                    subAgendaRow(name: it.sub.name, lead: it.rec.leaveType?.rawValue ?? "請假",
                                 sub: it.rec.content, accent: .teal, icon: "calendar.badge.minus")
                }
            }
            subAgendaCard("部屬報告", "doc.text.fill", .purple, count: reports.count, empty: "當日無報告") {
                ForEach(Array(reports.enumerated()), id: \.element.report.id) { _, it in
                    subAgendaCheckRow(name: it.sub.name,
                                      text: it.report.topic.isEmpty ? "未命名報告" : it.report.topic,
                                      detail: it.report.note.isEmpty ? nil : it.report.note,
                                      done: it.report.isCompleted, accent: .purple) {
                        lifeStore.toggleWeeklyReportCompletion(subordinateId: it.sub.id, reportId: it.report.id)
                    }
                }
            }
            subAgendaCard("部屬會議", "person.3.fill", .indigo, count: meetings.count, empty: "當日無會議") {
                ForEach(Array(meetings.enumerated()), id: \.offset) { _, it in
                    subAgendaRow(name: it.sub.name, lead: it.meeting.topic.isEmpty ? "未命名會議" : it.meeting.topic,
                                 sub: subAgendaTime(it.meeting.date), accent: .indigo, icon: "person.3.fill")
                }
            }
            subAgendaCard("部屬任務", "checklist", .cyan, count: tasks.count, empty: "當日無任務") {
                ForEach(Array(tasks.enumerated()), id: \.offset) { _, it in
                    subAgendaCheckRow(name: it.sub.name,
                                      text: it.task.topic.isEmpty ? "未命名任務" : it.task.topic,
                                      detail: it.task.dueDate.map { "截止 " + subAgendaTime($0) },
                                      done: it.task.isCompleted, accent: .cyan) {
                        lifeStore.toggleTaskCompletion(subordinateId: it.sub.id, taskId: it.task.id)
                    }
                }
            }
            subAgendaCard("未完成會議條目", "person.3.sequence.fill", .indigo,
                          count: subIncompleteMeetingItems.count, empty: "沒有未完成的會議條目") {
                ForEach(Array(subIncompleteMeetingItems.enumerated()), id: \.element.item.id) { _, it in
                    subAgendaCheckRow(name: it.sub.name,
                                      text: it.item.content.isEmpty ? "未填內容" : it.item.content,
                                      detail: (it.meeting.topic.isEmpty ? "會議" : it.meeting.topic)
                                            + (it.item.dueDate.map { "・截止 " + subAgendaTime($0) } ?? ""),
                                      done: it.item.isCompleted, accent: .indigo) {
                        lifeStore.toggleMeetingItemCompletion(subordinateId: it.sub.id, meetingId: it.meeting.id, itemId: it.item.id)
                    }
                }
            }
            subAgendaCard("未完成任務", "tray.full.fill", .orange,
                          count: subIncompleteTasks.count, empty: "沒有未完成任務") {
                ForEach(Array(subIncompleteTasks.enumerated()), id: \.element.task.id) { _, it in
                    subAgendaCheckRow(name: it.sub.name,
                                      text: it.task.topic.isEmpty ? "未命名任務" : it.task.topic,
                                      detail: it.task.dueDate.map { "截止 " + subAgendaTime($0) },
                                      done: it.task.isCompleted, accent: .orange) {
                        lifeStore.toggleTaskCompletion(subordinateId: it.sub.id, taskId: it.task.id)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private func subAgendaCard<Content: View>(_ title: String, _ icon: String, _ color: Color,
                                              count: Int, empty: String,
                                              @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title, icon: icon, color: color, count: count)
            if count == 0 {
                Text(empty).font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.vertical, 10)
            } else {
                content()
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
    }

    private func subAgendaRow(name: String, lead: String, sub: String, accent: Color, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(lead).font(.subheadline.weight(.medium)).lineLimit(1)
                if !sub.isEmpty { Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 4)
            Text(name).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private func subAgendaCheckRow(name: String, text: String, detail: String?, done: Bool,
                                   accent: Color, toggle: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: toggle) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16)).foregroundStyle(done ? Color.green : accent)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(.subheadline.weight(.medium))
                    .strikethrough(done, color: .secondary)
                    .foregroundStyle(done ? .secondary : .primary).lineLimit(2)
                if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 4)
            Text(name).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .opacity(done ? 0.7 : 1)
    }

    // MARK: - 輔助元件

    // sectionHeader：漸層膠囊色條 + 計數膠囊，與 OverviewView 設計語言一致
    private func sectionHeader(_ title: String, icon: String, color: Color, count: Int) -> some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.50)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 20)
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.weight(.bold))
            Spacer()
            if count > 0 {
                Text("\(count) 筆")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(color.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.75))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // emptyPlaceholder：帶圓形圖示的完整空狀態卡片，與 OverviewView emptyPlaceholder 一致
    private func emptyPlaceholder(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(.secondarySystemFill), Color(.systemFill)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                Circle()
                    .stroke(Color(.separator).opacity(0.30), lineWidth: 0.75)
                    .frame(width: 60, height: 60)
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Color(.secondaryLabel))
            }
            VStack(spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal)
    }

    private func fmtTime(_ d: Date) -> String { Self.timeFormatter.string(from: d) }
    private func fmtDate(_ d: Date) -> String { Self.calendarDateFormatter.string(from: d) }

    private func daysUntil(_ d: Date) -> String {
        let now = calendar.startOfDay(for: Date())
        let then = calendar.startOfDay(for: d)
        let days = calendar.dateComponents([.day], from: now, to: then).day ?? 0
        if days == 0 { return "今天" }
        if days == 1 { return "明天" }
        return "\(days) 天後"
    }

    // 里程碑類別色彩：與 LifeOverviewView.milestoneColor() 保持完全一致的色彩語言
    private func milestoneAccent(_ cat: MilestoneCategory) -> Color {
        switch cat {
        case .marriage:    return Color(red: 1.00, green: 0.40, blue: 0.60)
        case .family:      return Color(red: 1.00, green: 0.60, blue: 0.20)
        case .realEstate:  return Color(red: 0.42, green: 0.58, blue: 0.80)
        case .career:      return Color(red: 0.25, green: 0.60, blue: 0.95)
        case .education:   return Color(red: 0.45, green: 0.75, blue: 0.40)
        case .achievement: return Color(red: 0.20, green: 0.78, blue: 0.55)
        case .travel:      return Color(red: 0.55, green: 0.35, blue: 0.95)
        case .pet:         return Color(red: 0.90, green: 0.50, blue: 0.20)
        case .health:      return Color(red: 0.95, green: 0.28, blue: 0.32)
        case .other:       return Color.secondary
        }
    }
}

// MARK: - 個人行事曆事件編輯器

struct PersonalEventEditor: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let initialDate: Date
    let editing: PersonalEvent?

    private static let mdhmFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d HH:mm"; return f
    }()
    private static let hmFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

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
    // 上一次新增事件用的設定，新事件預填用
    @AppStorage("calendar.lastSyncToAppleCalendar") private var lastSyncToAppleCalendar: Bool = false
    @AppStorage("calendar.lastAppleCalendarId") private var lastAppleCalendarIdRaw: String = ""
    @StateObject private var appleCal = AppleCalendarBridge.shared

    // 地點自動完成（Apple Maps POI + 過去用過的地點）
    @StateObject private var locationCompleter = RestaurantSearchCompleter()
    @StateObject private var locationProvider = LocationProvider.shared
    @FocusState private var locationFieldFocused: Bool
    @State private var locationSuppressNextUpdate: Bool = false
    @State private var locationExpandedSuggestions: Bool = false
    @State private var locationDebounceTask: Task<Void, Never>?

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
                    if durationMinutes == 0 {
                        // 全天事件：只選日期
                        DatePicker("開始", selection: $date, displayedComponents: .date)
                    } else {
                        // 有長度：日期 + 時間（分鐘 5 倍數、24 小時制）
                        HStack {
                            Text("開始")
                            Spacer()
                            FiveMinuteDateTimePicker(selection: $date).fixedSize()
                        }
                    }
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
                    // 新事件：日期用使用者選的那天，時間用排程時段（整點/半點，過 18:00 則 09:30）
                    let cal = Calendar.current
                    let sched = FiveMinuteDateTimePicker.defaultSchedulingTime()
                    let timeComp = cal.dateComponents([.hour, .minute], from: sched)
                    var dayComp = cal.dateComponents([.year, .month, .day], from: initialDate)
                    dayComp.hour = timeComp.hour
                    dayComp.minute = timeComp.minute
                    date = cal.date(from: dayComp) ?? initialDate
                    // Apple 行事曆：用上次新增時的設定預填
                    syncToAppleCalendar = lastSyncToAppleCalendar
                    if !lastAppleCalendarIdRaw.isEmpty {
                        // 若上次選的行事曆仍存在且可寫入，沿用；否則 fallback 預設
                        let writableIds = appleCal.writableCalendars.map { $0.calendarIdentifier }
                        if writableIds.contains(lastAppleCalendarIdRaw) {
                            selectedAppleCalendarId = lastAppleCalendarIdRaw
                        }
                    }
                }
                // 預設行事曆 ID（若使用者尚未選擇）
                if selectedAppleCalendarId == nil {
                    selectedAppleCalendarId = appleCal.defaultCalendarId
                }
            }
            // 使用者改動時即時記下，方便下次新事件預填
            .onChange(of: syncToAppleCalendar) { _, newValue in
                if editing == nil { lastSyncToAppleCalendar = newValue }
            }
            .onChange(of: selectedAppleCalendarId) { _, newValue in
                if editing == nil, let id = newValue { lastAppleCalendarIdRaw = id }
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
                    locationAutocompleteField
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

    // MARK: - 地點自動完成

    @ViewBuilder
    private var locationAutocompleteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(.blue)
                    .frame(width: 20)
                TextField("地點（選填）", text: $location)
                    .focused($locationFieldFocused)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                if !location.isEmpty {
                    Button {
                        location = ""
                        locationExpandedSuggestions = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            if locationFieldFocused {
                locationSuggestionsList
            }
        }
        .onAppear {
            LocationProvider.shared.requestIfNeeded()
            locationCompleter.setRegion(LocationProvider.shared.searchRegion)
            if !location.isEmpty { locationCompleter.queryFragment = location }
        }
        .onChange(of: location) { _, newValue in
            if locationSuppressNextUpdate {
                locationSuppressNextUpdate = false
                return
            }
            locationExpandedSuggestions = false
            locationDebounceTask?.cancel()
            locationDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                locationCompleter.queryFragment = newValue
            }
        }
        .onChange(of: locationProvider.lastLocation) { _, _ in
            locationCompleter.setRegion(LocationProvider.shared.searchRegion)
            if !location.isEmpty { locationCompleter.queryFragment = location }
        }
    }

    @ViewBuilder
    private var locationSuggestionsList: some View {
        let all = allLocationSuggestions
        if !all.isEmpty {
            let limit = 20
            let visible = locationExpandedSuggestions ? all : Array(all.prefix(limit))
            let hiddenCount = max(0, all.count - limit)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visible) { item in
                        Button { applyLocationSuggestion(item) } label: {
                            locationSuggestionRow(item)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 44)
                    }
                    if !locationExpandedSuggestions && hiddenCount > 0 {
                        Button {
                            locationExpandedSuggestions = true
                        } label: {
                            HStack {
                                Image(systemName: "chevron.down.circle.fill").foregroundStyle(.blue)
                                Text("顯示更多 (\(hiddenCount))")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.blue)
                                Spacer()
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else if locationExpandedSuggestions && all.count > limit {
                        Button {
                            locationExpandedSuggestions = false
                        } label: {
                            HStack {
                                Image(systemName: "chevron.up.circle.fill").foregroundStyle(.secondary)
                                Text("收合")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 240)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
            )
        }
    }

    private func locationSuggestionRow(_ item: CalendarLocationSuggestion) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(item.iconColor.opacity(0.15)).frame(width: 28, height: 28)
                Image(systemName: item.iconName)
                    .foregroundStyle(item.iconColor)
                    .font(.caption)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "arrow.up.left").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    /// 合併過去 PersonalEvent 用過的地點 + Apple Maps 結果
    private var allLocationSuggestions: [CalendarLocationSuggestion] {
        let q = location.trimmingCharacters(in: .whitespaces).lowercased()
        var seen: Set<String> = []
        var output: [CalendarLocationSuggestion] = []

        for ev in lifeStore.personalEvents
            where !ev.location.trimmingCharacters(in: .whitespaces).isEmpty {
            if !q.isEmpty && !ev.location.lowercased().contains(q) { continue }
            let key = "past|\(ev.location.lowercased())"
            if seen.contains(key) { continue }
            seen.insert(key)
            output.append(CalendarLocationSuggestion(
                id: key, source: .past, title: ev.location,
                subtitle: "", completion: nil
            ))
        }

        for c in locationCompleter.results {
            let key = "apple|\(c.title.lowercased())|\(c.subtitle.lowercased())"
            if seen.contains(key) { continue }
            seen.insert(key)
            output.append(CalendarLocationSuggestion(
                id: key, source: .apple, title: c.title,
                subtitle: c.subtitle, completion: c
            ))
        }

        return output
    }

    private func applyLocationSuggestion(_ item: CalendarLocationSuggestion) {
        locationSuppressNextUpdate = true
        switch item.source {
        case .past:
            location = item.title
        case .apple:
            // 地點欄位帶「名稱 - 地址」較完整；若無 subtitle 則只帶名稱
            if item.subtitle.isEmpty {
                location = item.title
            } else {
                location = "\(item.title) - \(item.subtitle)"
            }
        }
        locationExpandedSuggestions = false
        locationFieldFocused = false
    }

    /// 提醒提示文字
    private var reminderHint: String {
        guard reminder != .none else { return "" }
        let cal = Calendar.current
        let fire = cal.date(byAdding: .minute, value: -reminder.rawValue, to: date) ?? date
        let timeStr = Self.mdhmFormatter.string(from: fire)
        if recurrence == .none {
            return "首次提醒：\(timeStr)"
        } else {
            return "首次提醒：\(timeStr)，之後依「\(recurrence.rawValue)」重複"
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
        let f = Calendar.current.isDate(end, inSameDayAs: date) ? Self.hmFormatter : Self.mdhmFormatter
        return f.string(from: end)
    }
}

// MARK: - 行事曆地點候選資料型別

fileprivate struct CalendarLocationSuggestion: Identifiable {
    enum Source { case past, apple }
    let id: String
    let source: Source
    let title: String
    let subtitle: String
    let completion: MKLocalSearchCompletion?

    var iconName: String {
        source == .past ? "clock.arrow.circlepath" : "mappin"
    }
    var iconColor: Color {
        source == .past ? .green : .blue
    }
}

#Preview {
    MyCalendarView()
        .environmentObject(LifeStore())
        .environmentObject(FinanceStore())
}
