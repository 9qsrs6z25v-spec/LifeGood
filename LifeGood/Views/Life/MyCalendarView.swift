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
// [2026-08 v3] 補齊大字防截斷缺口：
// ⑫ calendarHeroCard 頂部 44pt 今日日期大字（Text("\(day)")）原本沒有 lineLimit／
//    minimumScaleFactor 防截斷保護，是同系列英雄卡 OverviewView／IncomeView／
//    FinanceOverviewView／FinanceChartView／ChartView／BusinessCardView／AddStockView
//    等皆已修過、本檔案仍缺的同型缺口——雖然日期數字固定 1～31（最多 2 位數），實務上不會被
//    裁切，但比照全 App 英雄卡大字一律加防護的規格補齊，維持視覺一致性。補上 .lineLimit(1) +
//    .minimumScaleFactor(0.6)，對齊卡片內「未來 30 天」KPI 膠囊已有的同型防護。純視覺層
//    調整，day／month／weekdayStr 等日期計算與行事曆資料邏輯完全未變動。
//    （下次美化本檔案時：英雄卡大字防截斷已補齊，可轉往其他仍留有待辦的畫面）

/// 我的行事曆：彙整當日家庭紀念日、工作會議與任務、本週快覽、未來里程碑、Apple 行事曆事件。
struct MyCalendarView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var financeStore: FinanceStore
    @StateObject private var appleCal = AppleCalendarBridge.shared

    @State private var selectedDate = Date()
    @State private var addPersonalKind: PersonalEventKind?   // 新增我的會議 / 事務
    @State private var subAddKind: SubAddKind?               // 新增部屬任務 / 會議 / 報告
    @State private var previewCalendarItem: CalendarEventCard.Item?
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var showSubCompleted = false
    @State private var openTarget: CalendarOpenTarget?

    /// 從搜尋結果 / 已完成卡片點擊要開啟的編輯目標
    enum CalendarOpenTarget: Identifiable {
        case report(subId: UUID, report: WeeklyReport)
        case task(subId: UUID, task: SubordinateTask)
        case meeting(subId: UUID, meeting: SubordinateMeeting)
        case leave(subId: UUID, rec: SubordinateRecord)
        case milestone(LifeMilestone)
        case event(PersonalEvent)
        var id: String {
            switch self {
            case .report(_, let r):  return "r_\(r.id.uuidString)"
            case .task(_, let t):    return "t_\(t.id.uuidString)"
            case .meeting(_, let m): return "m_\(m.id.uuidString)"
            case .leave(_, let rec): return "l_\(rec.id.uuidString)"
            case .milestone(let ms): return "ms_\(ms.id.uuidString)"
            case .event(let e):      return "e_\(e.id.uuidString)"
            }
        }
    }

    // 進場動畫旗標
    @State private var heroCardAppeared = false
    @State private var todayCardAppeared = false
    @State private var weekCardAppeared = false

    private let calendar = Calendar.current

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let calendarDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d (EEE)"
        f.locale = Locale(identifier: "zh_TW"); return f
    }()

    var body: some View {
        let trimmedQuery = debouncedSearchText.trimmingCharacters(in: .whitespaces)
        // Pre-compute once per render: avoids 16 redundant eventsOn() + 6 upcomingMilestones calls。
        // 搜尋模式下只會渲染 searchResultsView，calendarHeroCard/todayEventsSection/weekPreviewSection
        // 都不會顯示，因此這段非輕量運算（eventsOn 掃描家人+里程碑+行事曆全量）只在非搜尋狀態才需要，
        // 避免使用者在搜尋框每敲一個字元都白白重算一次。
        let resolvedWeekDates = trimmedQuery.isEmpty ? weekDates : []
        let startOfSelectedDay = calendar.startOfDay(for: selectedDate)
        let startOfToday = calendar.startOfDay(for: Date())
        let heroIsToday = startOfSelectedDay == startOfToday
        let heroWeekDates: [Date] = trimmedQuery.isEmpty
            ? (heroIsToday ? resolvedWeekDates
                : (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfToday) })
            : []
        // 非今日時 heroWeekDates 與 resolvedWeekDates 最多重疊 6 天，先算聯集只呼叫一次
        // eventsOn()（家人+里程碑+行事曆全量查詢，非輕量運算），weekEventsMap／heroEventsMap
        // 再各自從聯集結果取子集，避免重疊日期被 eventsOn() 重複掃描兩次。
        let allDates = trimmedQuery.isEmpty ? Array(Set(resolvedWeekDates).union(heroWeekDates)) : []
        let allEventsMap = Dictionary(uniqueKeysWithValues: allDates.map { ($0, eventsOn($0)) })
        let weekEventsMap = Dictionary(uniqueKeysWithValues: resolvedWeekDates.map { ($0, allEventsMap[$0] ?? []) })
        let heroEventsMap = heroIsToday ? weekEventsMap
            : Dictionary(uniqueKeysWithValues: heroWeekDates.map { ($0, allEventsMap[$0] ?? []) })
        let upcomingMS = trimmedQuery.isEmpty ? upcomingMilestones : []
        let heroTodayCount = heroEventsMap[startOfToday]?.count ?? 0
        let heroWeekTotal = heroWeekDates.reduce(0) { $0 + (heroEventsMap[$1]?.count ?? 0) }
        NavigationStack {
            ScrollView {
              if !trimmedQuery.isEmpty {
                searchResultsView(query: trimmedQuery)
                    .padding(.vertical)
              } else {
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
                    // 未來 30 天里程碑：區塊本體早已實作完成（含空狀態與「還有 N 個」溢出列），
                    // 但先前重整版面時漏了呼叫點，導致英雄卡「未來 30 天」計數旁始終看不到內容。
                    if !upcomingMS.isEmpty {
                        upcomingMilestonesSection(milestones: upcomingMS)
                    }
                    // 部屬事項（請假 / 會議 / 任務 / 未完成會議 / 未完成任務）
                    if !lifeStore.subordinates.isEmpty {
                        subordinateAgendaSection(date: startOfSelectedDay)
                    }
                }
                .padding(.vertical)
              }
            }
            .background(Color(.systemGroupedBackground))
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: "搜尋報告/會議/任務/里程碑/事件（標題或內容）")
            .navigationTitle("我的行事曆")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { addMenu }
            }
            .sheet(item: $addPersonalKind) { kind in
                PersonalEventEditor(initialDate: selectedDate, editing: nil, initialKind: kind)
            }
            .sheet(item: $subAddKind) { kind in
                AddSubItemSheet(kind: kind)
            }
            .sheet(item: $previewCalendarItem) { item in
                CalendarEventCard(item: item)
            }
            .sheet(item: $openTarget) { target in
                switch target {
                // 部屬報告/任務/會議/請假：先顯示預覽卡片，右上角「編輯」才進入編輯
                case .report(let subId, let report):
                    SubordinateItemCard(ref: .report(subId: subId, report: report))
                case .task(let subId, let task):
                    SubordinateItemCard(ref: .task(subId: subId, task: task))
                case .meeting(let subId, let meeting):
                    SubordinateItemCard(ref: .meeting(subId: subId, meeting: meeting))
                case .leave(let subId, let rec):
                    SubordinateItemCard(ref: .leave(subId: subId, rec: rec))
                case .milestone(let ms):
                    CalendarEventCard(item: .milestone(ms))
                case .event(let ev):
                    CalendarEventCard(item: .personalEvent(ev))
                }
            }
            .task {
                if appleCal.authorizationStatus == .notDetermined {
                    await appleCal.requestAccess()
                } else {
                    appleCal.refreshStatus()
                }
            }
            .task(id: searchText) {
                guard !searchText.isEmpty else { debouncedSearchText = ""; return }
                try? await Task.sleep(nanoseconds: 300_000_000)
                debouncedSearchText = searchText
            }
        }
    }

    /// 右上角「＋」選單：新增我的會議／事務，或部屬任務／會議／報告
    private var addMenu: some View {
        Menu {
            Section("我的行事曆") {
                Button { addPersonalKind = .meeting } label: { Label("新增會議", systemImage: "person.3.fill") }
                Button { addPersonalKind = .task } label: { Label("新增事務", systemImage: "checklist") }
            }
            Section("部屬") {
                Button { subAddKind = .task } label: { Label("新增部屬任務", systemImage: "checklist") }
                Button { subAddKind = .meeting } label: { Label("新增部屬會議", systemImage: "person.3.fill") }
                Button { subAddKind = .report } label: { Label("新增部屬報告", systemImage: "doc.text.fill") }
            }
        } label: {
            Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
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
        // [2026-07] 美化：取代先前塞進 detail 字串的「🔁」純文字表情符號，
        // 改用獨立布林旗標交由 eventRow 畫成與 clock／sun.max 同規格的 SF Symbol 徽章。
        var isRecurring: Bool = false
        var hasReminder: Bool = false

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
        // Calendar.date(from:) 對不存在的日期（如非閏年 2/29）不回傳 nil，
        // 而是自動溢位到下個月（2/29 → 3/1），導致生日顯示在錯誤的月份。
        // 提前把 day 截至該年該月實際天數，確保 2/29 在非閏年對應到 2/28。
        if let month = comp.month, let day = comp.day {
            let refDate = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? date
            let maxDay = calendar.range(of: .day, in: .month, for: refDate)?.count ?? day
            if day > maxDay { comp.day = maxDay }
        }
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

        // 部屬會議 / 部屬任務不再列入當日事件卡（下方已有獨立的部屬事項卡片）

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

        // 兼任職務的「重要日期」（尾牙的場勘日、彩排日等）。
        // 兼任里程碑的就任日本來就會被上面那段帶進行事曆，但卸任日與這些
        // 自訂日期不會——而它們才是使用者真正要被提醒的。
        for role in lifeStore.sideRoles {
            let roleName = SideRoleFormat.displayName(role)
            for kd in role.sideRoleKeyDates ?? []
            where calendar.isDate(kd.date, inSameDayAs: day) {
                events.append(CalendarEvent(
                    id: "srkd-\(kd.id.uuidString)",
                    type: .milestone,
                    title: kd.title.isEmpty ? roleName : "\(roleName)：\(kd.title)",
                    time: kd.date,
                    detail: "兼任職務"
                ))
            }
            if let end = role.sideRoleEndDate, calendar.isDate(end, inSameDayAs: day) {
                events.append(CalendarEvent(
                    id: "srend-\(role.id.uuidString)",
                    type: .milestone,
                    title: "\(roleName) 卸任",
                    time: end,
                    detail: "兼任職務"
                ))
            }
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
            let baseDetail: String = pe.durationMinutes > 0
                ? "\(pe.durationMinutes) 分鐘"
                : "全日"
            let withNote = pe.note.isEmpty ? baseDetail : "\(baseDetail) · \(pe.note)"
            events.append(CalendarEvent(
                id: "pe-\(pe.id.uuidString)-\(calendar.startOfDay(for: day).timeIntervalSince1970)",
                type: pe.kind == .meeting ? .meeting : .task,
                title: pe.title.isEmpty ? pe.kind.rawValue : pe.title,
                time: pe.durationMinutes > 0 ? occTime : nil,
                detail: withNote,
                personalEventId: pe.id,
                isRecurring: pe.recurrence != .none,
                hasReminder: pe.reminderMinutes >= 0
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

    /// 將當日事件解析為預覽卡片項目（個人事件/里程碑可編輯；系統行事曆可開啟；生日/紀念日唯讀）
    private func cardItem(for ev: CalendarEvent) -> CalendarEventCard.Item {
        if let pid = ev.personalEventId,
           let pe = lifeStore.personalEvents.first(where: { $0.id == pid }) {
            return .personalEvent(pe)
        }
        let fallbackDate = ev.time ?? calendar.startOfDay(for: selectedDate)
        switch ev.type {
        case .milestone:
            if ev.id.hasPrefix("ms-"),
               let uuid = UUID(uuidString: String(ev.id.dropFirst(3))),
               let ms = lifeStore.milestones.first(where: { $0.id == uuid }) {
                return .milestone(ms)
            }
            return .appleEvent(title: ev.title, time: ev.time, detail: ev.detail, date: fallbackDate)
        case .birthday:
            return .family(title: ev.title, detail: ev.detail, isBirthday: true)
        case .anniversary:
            return .family(title: ev.title, detail: ev.detail, isBirthday: false)
        case .appleCalendar, .meeting, .task:
            return .appleEvent(title: ev.title, time: ev.time, detail: ev.detail, date: fallbackDate)
        }
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
                    Button { previewCalendarItem = cardItem(for: ev) } label: { eventRow(ev) }
                        .buttonStyle(.plain)
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
                    // 重複／提醒次要徽章：與同排「clock／sun.max」尺寸節奏對齊（9pt 圖示 + tertiary），
                    // 取代先前塞進 detail 字串的「🔁」純文字表情符號寫法。
                    if ev.isRecurring {
                        Image(systemName: "repeat")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    if ev.hasReminder {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
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
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.white.opacity(0.35) : Color(.separator).opacity(0.12),
                            lineWidth: 0.75)
            )
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
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
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
                HeroKpiCell(label: "今日", value: "\(todayEvCount) 件", icon: "sun.max.fill")
                HeroKpiDivider()
                HeroKpiCell(label: "本週七天", value: "\(weekTotal) 件", icon: "calendar")
                HeroKpiDivider()
                HeroKpiCell(label: "未來 30 天", value: "\(upcomingCount) 個", icon: "flag.fill")
            }
        }
        .padding(20)
        .heroCardShell(card: .calendar)
        .padding(.horizontal)
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
    /// 報告呈現狀態（與部屬總覽一致）
    enum SubReportStatus { case overdue, thisWeek, pending, done }

    /// 顯示規則：所在週的未完成報告 + 任何未完成報告（含逾期、未來週）。
    /// 已完成一律不在此列出，改由底部「已完成」收合卡歸納。
    private func subReports(on date: Date) -> [(sub: Subordinate, report: WeeklyReport, status: SubReportStatus)] {
        let wk = calendar.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86_400)
        return lifeStore.subordinates.flatMap { sub in
            sub.weeklyReports.compactMap { r -> (sub: Subordinate, report: WeeklyReport, status: SubReportStatus)? in
                if r.isCompleted { return nil }                      // 已完成 → 移至「已完成」收合卡
                let inWeek = wk.contains(r.date)
                if r.date < wk.start { return (sub, r, .overdue) }
                if inWeek            { return (sub, r, .thisWeek) }
                return (sub, r, .pending)
            }
        }
        .sorted { $0.report.date < $1.report.date }
    }
    /// 報告狀態 → 標籤文字與強調色
    private func subReportMeta(_ status: SubReportStatus) -> (label: String?, color: Color) {
        switch status {
        case .overdue:  return ("逾期", .red)
        case .thisWeek: return ("本週", .purple)
        case .pending:  return ("待辦", .orange)
        case .done:     return (nil, .green)
        }
    }

    private static let subReportDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d (E)"
        return f
    }()

    private func subReportDateText(_ date: Date) -> String {
        Self.subReportDateFormatter.string(from: date)
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

    /// 當日事項（請假 / 報告 / 會議 / 任務）與下方「未完成待辦」之間的分隔線，讓兩組有明確空間區隔
    private var agendaGroupDivider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color(.separator).opacity(0.5)).frame(height: 0.75)
            Text("未完成待辦")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize()
            Rectangle().fill(Color(.separator).opacity(0.5)).frame(height: 0.75)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private func subordinateAgendaSection(date: Date) -> some View {
        let leaves = subLeaves(on: date)
        let reports = subReports(on: date)
        let meetings = subMeetings(on: date)
        let tasks = subTasks(on: date)
        let allIncompleteMeetings = subIncompleteMeetingItems
        let allIncompleteTasks = subIncompleteTasks
        return VStack(spacing: 16) {
            subAgendaCard("部屬請假", "calendar.badge.minus", .teal, count: leaves.count, empty: "當日無人請假") {
                ForEach(Array(leaves.enumerated()), id: \.offset) { _, it in
                    subAgendaRow(name: it.sub.name, lead: it.rec.leaveType?.rawValue ?? "請假",
                                 sub: it.rec.content, accent: .teal, icon: "calendar.badge.minus",
                                 onOpen: { openTarget = .leave(subId: it.sub.id, rec: it.rec) })
                }
            }
            subAgendaCard("部屬報告（本週/待辦）", "doc.text.fill", .purple, count: reports.count, empty: "本週無報告、無待辦報告") {
                ForEach(Array(reports.enumerated()), id: \.element.report.id) { _, it in
                    let meta = subReportMeta(it.status)
                    let dateStr = subReportDateText(it.report.date)
                    let detail = [meta.label.map { "\($0) · \(dateStr)" } ?? dateStr,
                                  it.report.note.isEmpty ? nil : it.report.note]
                        .compactMap { $0 }.joined(separator: " · ")
                    subAgendaCheckRow(name: it.sub.name,
                                      text: it.report.topic.isEmpty ? "未命名報告" : it.report.topic,
                                      detail: detail,
                                      done: it.report.isCompleted, accent: meta.color,
                                      completedAt: it.report.completedAt, due: it.report.date,
                                      onOpen: { openTarget = .report(subId: it.sub.id, report: it.report) }) {
                        lifeStore.toggleWeeklyReportCompletion(subordinateId: it.sub.id, reportId: it.report.id)
                    }
                }
            }
            subAgendaCard("部屬會議", "person.3.fill", .indigo, count: meetings.count, empty: "當日無會議") {
                ForEach(Array(meetings.enumerated()), id: \.offset) { _, it in
                    subAgendaRow(name: it.sub.name, lead: it.meeting.topic.isEmpty ? "未命名會議" : it.meeting.topic,
                                 sub: subAgendaTime(it.meeting.date), accent: .indigo, icon: "person.3.fill",
                                 onOpen: { openTarget = .meeting(subId: it.sub.id, meeting: it.meeting) })
                }
            }
            subAgendaCard("部屬任務", "checklist", .cyan, count: tasks.count, empty: "當日無任務") {
                ForEach(Array(tasks.enumerated()), id: \.offset) { _, it in
                    subAgendaCheckRow(name: it.sub.name,
                                      text: it.task.topic.isEmpty ? "未命名任務" : it.task.topic,
                                      detail: it.task.dueDate.map { "截止 " + subAgendaTime($0) },
                                      done: it.task.isCompleted, accent: .cyan,
                                      onOpen: { openTarget = .task(subId: it.sub.id, task: it.task) }) {
                        lifeStore.toggleTaskCompletion(subordinateId: it.sub.id, taskId: it.task.id)
                    }
                }
            }

            agendaGroupDivider

            subAgendaCard("未完成會議條目", "person.3.sequence.fill", .indigo,
                          count: allIncompleteMeetings.count, empty: "沒有未完成的會議條目") {
                ForEach(Array(allIncompleteMeetings.enumerated()), id: \.element.item.id) { _, it in
                    subAgendaCheckRow(name: it.sub.name,
                                      text: it.item.content.isEmpty ? "未填內容" : it.item.content,
                                      detail: (it.meeting.topic.isEmpty ? "會議" : it.meeting.topic)
                                            + (it.item.dueDate.map { "・截止 " + subAgendaTime($0) } ?? ""),
                                      done: it.item.isCompleted, accent: .indigo,
                                      onOpen: { openTarget = .meeting(subId: it.sub.id, meeting: it.meeting) }) {
                        lifeStore.toggleMeetingItemCompletion(subordinateId: it.sub.id, meetingId: it.meeting.id, itemId: it.item.id)
                    }
                }
            }
            subAgendaCard("未完成任務", "tray.full.fill", .orange,
                          count: allIncompleteTasks.count, empty: "沒有未完成任務") {
                ForEach(Array(allIncompleteTasks.enumerated()), id: \.element.task.id) { _, it in
                    subAgendaCheckRow(name: it.sub.name,
                                      text: it.task.topic.isEmpty ? "未命名任務" : it.task.topic,
                                      detail: it.task.dueDate.map { "截止 " + subAgendaTime($0) },
                                      done: it.task.isCompleted, accent: .orange,
                                      onOpen: { openTarget = .task(subId: it.sub.id, task: it.task) }) {
                        lifeStore.toggleTaskCompletion(subordinateId: it.sub.id, taskId: it.task.id)
                    }
                }
            }
            // 所有已勾選完成的項目（報告/會議項目/任務）收合於最下方
            CompletedCollapsibleCard(entries: subCompletedEntries,
                                     expanded: $showSubCompleted,
                                     title: "已完成")
        }
        .padding(.horizontal)
    }

    /// 全部已完成的部屬項目（不限日期），供底部收合卡使用；點一下開啟該項目
    private var subCompletedEntries: [CompletedEntry] {
        var out: [CompletedEntry] = []
        for sub in lifeStore.subordinates {
            let who = sub.name.isEmpty ? "未命名" : sub.name
            for r in sub.weeklyReports where r.isCompleted {
                out.append(CompletedEntry(id: r.id, kind: .report, title: r.topic,
                                          subtitle: who, completedAt: r.completedAt, due: r.date,
                                          onTap: { openTarget = .report(subId: sub.id, report: r) }))
            }
            for m in sub.meetings {
                for item in m.items where item.isCompleted {
                    out.append(CompletedEntry(id: item.id, kind: .meeting, title: item.content,
                                              subtitle: "\(who)・\(m.topic.isEmpty ? "會議" : m.topic)",
                                              completedAt: item.completedAt, due: item.dueDate,
                                              onTap: { openTarget = .meeting(subId: sub.id, meeting: m) }))
                }
            }
            for t in sub.tasks where t.isCompleted {
                out.append(CompletedEntry(id: t.id, kind: .task, title: t.topic,
                                          subtitle: who, completedAt: t.completedAt, due: t.dueDate,
                                          onTap: { openTarget = .task(subId: sub.id, task: t) }))
            }
        }
        return out
    }

    // MARK: - 搜尋（標題 + 內容）

    private struct SearchHit: Identifiable {
        let id: String
        let icon: String
        let color: Color
        let typeLabel: String
        let title: String
        let snippet: String?
        let date: Date
        let target: CalendarOpenTarget
    }

    private static let searchHitDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "yyyy/M/d"; return f
    }()

    /// 跨部屬報告/會議/任務/請假 + 里程碑 + 個人事件，比對標題與內容/備註
    private func searchHits(_ q: String) -> [SearchHit] {
        func hit(_ fields: [String]) -> Bool { fields.contains { $0.localizedCaseInsensitiveContains(q) } }
        var out: [SearchHit] = []
        for sub in lifeStore.subordinates {
            let who = sub.name.isEmpty ? "未命名" : sub.name
            for r in sub.weeklyReports where hit([r.topic, r.note]) {
                out.append(SearchHit(id: "r_\(r.id)", icon: "doc.text.fill", color: .purple,
                    typeLabel: "報告", title: r.topic.isEmpty ? "未命名報告" : r.topic,
                    snippet: r.note.isEmpty ? who : "\(who)・\(r.note)", date: r.date,
                    target: .report(subId: sub.id, report: r)))
            }
            for t in sub.tasks where hit([t.topic, t.content, t.note]) {
                out.append(SearchHit(id: "t_\(t.id)", icon: "checklist", color: .cyan,
                    typeLabel: "任務", title: t.topic.isEmpty ? "未命名任務" : t.topic,
                    snippet: t.content.isEmpty ? who : "\(who)・\(t.content)", date: t.date,
                    target: .task(subId: sub.id, task: t)))
            }
            for m in sub.meetings {
                if hit([m.topic, m.note]) {
                    out.append(SearchHit(id: "m_\(m.id)", icon: "person.3.fill", color: .indigo,
                        typeLabel: "會議", title: m.topic.isEmpty ? "未命名會議" : m.topic,
                        snippet: who, date: m.date,
                        target: .meeting(subId: sub.id, meeting: m)))
                }
                for item in m.items where hit([item.content, item.note]) {
                    out.append(SearchHit(id: "mi_\(item.id)", icon: "person.3.sequence.fill", color: .indigo,
                        typeLabel: "會議項目", title: item.content.isEmpty ? "未填內容" : item.content,
                        snippet: "\(who)・\(m.topic.isEmpty ? "會議" : m.topic)", date: m.date,
                        target: .meeting(subId: sub.id, meeting: m)))
                }
            }
            for rec in sub.records where hit([rec.content, rec.note]) {
                out.append(SearchHit(id: "rec_\(rec.id)", icon: "calendar.badge.clock", color: .teal,
                    typeLabel: rec.type.rawValue, title: rec.content.isEmpty ? rec.type.rawValue : rec.content,
                    snippet: who, date: rec.date,
                    target: .leave(subId: sub.id, rec: rec)))
            }
        }
        for ms in lifeStore.milestones where hit([ms.title, ms.note]) {
            out.append(SearchHit(id: "ms_\(ms.id)", icon: "flag.fill", color: .pink,
                typeLabel: "里程碑", title: ms.title.isEmpty ? "未命名里程碑" : ms.title,
                snippet: ms.note.isEmpty ? nil : ms.note, date: ms.date,
                target: .milestone(ms)))
        }
        // 兼任職務：職務名稱／主辦單位／負責範圍，以及底下的會議紀錄與待辦。
        // 里程碑那一輪只吃 title 與 note，這些欄位全都搜不到。
        for role in lifeStore.sideRoles {
            let roleName = SideRoleFormat.displayName(role)
            if hit([role.sideRoleName ?? "", role.sideRoleOrg ?? "", role.sideRoleScope ?? ""]) {
                out.append(SearchHit(id: "sr_\(role.id)", icon: "person.badge.plus", color: .indigo,
                    typeLabel: "兼任職務", title: roleName,
                    snippet: SideRoleFormat.subtitle(role), date: role.date,
                    target: .milestone(role)))
            }
            for mt in role.sideRoleMeetings ?? []
            where hit([mt.topic, mt.decisions, mt.note, mt.attendees.joined(separator: "、")]) {
                out.append(SearchHit(id: "srmt_\(mt.id)", icon: "text.bubble.fill", color: .indigo,
                    typeLabel: "兼任會議", title: mt.topic.isEmpty ? "未命名會議" : mt.topic,
                    snippet: "\(roleName)　" + (mt.decisions.isEmpty ? mt.note : mt.decisions),
                    date: mt.date, target: .milestone(role)))
            }
            for tk in role.sideRoleTasks ?? [] where hit([tk.content, tk.note]) {
                out.append(SearchHit(id: "srtk_\(tk.id)", icon: "checklist", color: .indigo,
                    typeLabel: "兼任待辦", title: tk.content.isEmpty ? "未填內容" : tk.content,
                    snippet: roleName, date: tk.dueDate ?? role.date,
                    target: .milestone(role)))
            }
            for kd in role.sideRoleKeyDates ?? [] where hit([kd.title, kd.note]) {
                out.append(SearchHit(id: "srkd_\(kd.id)", icon: "calendar", color: .indigo,
                    typeLabel: "兼任日期", title: kd.title.isEmpty ? "未命名日期" : kd.title,
                    snippet: roleName, date: kd.date, target: .milestone(role)))
            }
        }
        for pe in lifeStore.personalEvents where hit([pe.title, pe.note, pe.location]) {
            out.append(SearchHit(id: "pe_\(pe.id)", icon: "calendar", color: .green,
                typeLabel: pe.kind.rawValue, title: pe.title.isEmpty ? "未命名事件" : pe.title,
                snippet: pe.note.isEmpty ? (pe.location.isEmpty ? nil : pe.location) : pe.note, date: pe.date,
                target: .event(pe)))
        }
        return out.sorted { $0.date > $1.date }
    }

    @ViewBuilder
    private func searchResultsView(query: String) -> some View {
        let hits = searchHits(query)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("搜尋結果").font(.headline)
                Spacer()
                Text("\(hits.count) 筆").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            if hits.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 32)).foregroundStyle(.secondary)
                    Text("找不到「\(query)」相關項目").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 44)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(hits.enumerated()), id: \.element.id) { idx, h in
                        Button { openTarget = h.target } label: { searchHitRow(h) }
                        .buttonStyle(.plain)
                        if idx < hits.count - 1 { Divider().padding(.leading, 58) }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
                .padding(.horizontal)

                Text("點一下可開啟該項目編輯")
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func searchHitRow(_ h: SearchHit) -> some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(LinearGradient(colors: [h.color.opacity(0.20), h.color.opacity(0.08)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 34, height: 34)
                Image(systemName: h.icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(h.color)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(h.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                    Text(h.typeLabel).font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 1.5)
                        .background(h.color.opacity(0.14)).foregroundStyle(h.color).clipShape(Capsule())
                }
                if let s = h.snippet, !s.isEmpty {
                    Text(s).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(Self.searchHitDateFormatter.string(from: h.date)).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
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

    private func subAgendaRow(name: String, lead: String, sub: String, accent: Color, icon: String,
                              onOpen: (() -> Void)? = nil) -> some View {
        Button { onOpen?() } label: {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onOpen == nil)
    }

    private func subAgendaCheckRow(name: String, text: String, detail: String?, done: Bool,
                                   accent: Color, completedAt: Date? = nil, due: Date? = nil,
                                   onOpen: (() -> Void)? = nil,
                                   toggle: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: toggle) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16)).foregroundStyle(done ? Color.green : accent)
            }
            .buttonStyle(.plain)
            Button { onOpen?() } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(text).font(.subheadline.weight(.medium))
                            .strikethrough(done, color: .secondary)
                            .foregroundStyle(done ? .secondary : .primary).lineLimit(2)
                        if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                        if done { CompletionStamp(completedAt: completedAt, due: due) }
                    }
                    Spacer(minLength: 4)
                    Text(name).font(.caption2).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onOpen == nil)
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

// MARK: - 美化紀錄（PersonalEventEditor）2026-07
// 本檔案先前僅美化過 MyCalendarView 主畫面（英雄卡／sectionHeader／eventRow 等），
// 新增/編輯個人事件的 Form 表單一直維持系統預設純文字 Section("...") 標題，
// 與 RecordEditorSheet／MeetingEditorSheet／TaskEditorSheet／WeeklyReportEditorSheet
// 已套用的統一 Section header 規格不一致。本次補齊：
// ① 新增 editorSectionHeader(_:icon:tint:)，比照上述編輯 Sheet 規格
//    （4pt 漸層色條 + 圖示 + .subheadline.bold），取代「基本資訊／時間／重複／提醒／
//    Apple 行事曆／備註」六個 Section 的純文字標題。
// ② tint 預設依目前選取的事件類型動態切換（會議＝indigo／事務＝cyan），
//    對齊本檔案 eventRow／CalendarEventCard 既有的會議＝indigo、事務＝cyan 配色；
//    「基本資訊」標題圖示也隨 kind.icon 同步切換，備註區沿用全 App 一致的中性灰。
// ③ 純視覺層調整，未變動任何新增／編輯／刪除／Apple 行事曆同步／通知排程等既有商業邏輯。
//
// [2026-07 v2] 本次美化方向（承接上方待辦：CalendarEventCard 預覽卡片）：
// ④ titleBlock：從裸 icon 圓 + 標題文字，升級為依事件類型變色的漸層英雄卡
//    （會議＝indigo／事務＝cyan／里程碑＝橘／系統行事曆＝藍／生日＝粉金／紀念日＝玫瑰紅），
//    補齊雙散景圓 + 頂部玻璃光澤，對齊 StockDetailView／SubordinateDetailView 等其他
//    「閃卡」詳情頁英雄卡規格；卡內另加類型 Capsule 徽章（沿用 navTitle 文案）。
// ⑤ 新增 heroGradientColors：與純顯示用的淺色 accent（icon/欄位/按鈕沿用不變）分開，
//    改用手調深色調兩色，避免 family 粉色系等淺色 accent 直接當滿版背景時白字對比不足。
// ⑥ 新增 cardAppeared 進場動畫（spring 淡入 + Y 位移 14pt），對齊全 App detail sheet
//    開啟時的英雄卡進場規格。
// ⑦ 純顯示層調整，未變動事件／里程碑／Apple 行事曆／家人紀念日詳情欄位、編輯、
//    開啟系統行事曆等既有商業邏輯。
// [2026-07 v3] 本次美化方向（承接上方待辦）：
// ⑧ 新增 CalendarEventCard.cardSectionHeader(_:icon:tint:)，比照 PersonalEventEditor.
//    editorSectionHeader 規格（4pt 漸層色條 + 圖示 + .subheadline.bold），補上「詳細資訊」
//    （info.circle，沿用卡片 accent）與「備註」（note.text，中性灰，對齊 editorSectionHeader
//    備註區配色）兩個標頭，取代 infoCard 原本完全無標頭的裸欄位列，以及 noteBlock 原本
//    純 caption 字級「備註」二字標籤。
// ⑨ 純視覺層調整，未變動 fields／noteText 欄位資料來源、編輯、刪除等既有商業邏輯。
// [2026-07 v4] 本次美化方向（承接 v3 末尾待辦：eventRow「重複」「提醒」徽章）：
// ⑩ 主畫面 eventRow 先前把重複狀態塞進 detail 字串裡（"🔁 " 純文字表情符號前綴），
//    是全檔案唯一用 emoji 而非 SF Symbol 表達狀態的地方，與同排 clock／sun.max 兩個
//    9pt SF Symbol + tertiary 灰階圖示的既有節奏不一致。CalendarEvent 新增
//    isRecurring／hasReminder 兩個純顯示用布林欄位（預設 false，不影響既有呼叫端），
//    eventRow 改用 "repeat" 與 "bell.fill" 兩枚 9pt SF Symbol 徽章，套用與 clock／
//    sun.max 完全相同的尺寸／配色規格，達成「次要徽章統一尺寸節奏」。
// ⑪ 個人事件先前只顯示重複狀態、從未顯示是否有設提醒；hasReminder 依 pe.reminderMinutes
//    >= 0 判斷（-1 = 不提醒，沿用既有語意，未新增或變更任何提醒排程邏輯），純粹補齊
//    主畫面可視性，不影響 NotificationManager 既有的排程/取消/重新排程行為。
// ⑫ 純視覺層調整，未變動 eventsOn()／occurs()／reminderMinutes 讀寫、通知排程、
//    Apple 行事曆同步等既有商業邏輯。
// [2026-07 v5] 補齊 v4 留下的待辦（本檔案並無獨立 monthGrid 元件，僅 weekDayCard
// 一個月曆格狀元件，故改為直接檢視 weekDayCard 本身）：
// ⑬ weekDayCard 54×74pt 圓角卡片先前只有 background + shadow，缺少 overlay 細邊框，
//    與同檔案 appleCalendarBanner、三個 section 卡片（當日事件／本週快覽／未來里程碑）
//    既有的 RoundedRectangle stroke 規格不一致，深色模式下卡片邊界較模糊。補上
//    overlay(RoundedRectangle(cornerRadius: 14).stroke(...))：選中時 white.opacity(0.35)
//    （對齊 TravelMapView.statsCard 白色徽章邊框慣例），未選中時 separator.opacity(0.12)
//    （對齊本檔案 section 卡片既有邊框規格），純視覺層調整，不影響選取／事件點呈現邏輯。
// ⑭ 純視覺層調整，未變動 weekDates／selectedDate 綁定、weekEventsMap 等既有商業邏輯。
// [2026-08 v25.100] 本次美化方向（PersonalEventEditor 工具列儲存按鈕補齊載入狀態）：
//  ⑮ PersonalEventEditor.save() 自帶 isSaving 忙碌守衛（disabled(isSaving)）避免快速連點造成
//     重複事件／重複行事曆項目／重複通知，但按鈕本身在存檔期間毫無視覺提示。比照
//     SubordinateDetailView v25.99／OrganizationView v25.96 等全 App 儲存按鈕載入狀態規格，
//     於按鈕左側補上 HStack { if isSaving { ProgressView().scaleEffect(0.7).tint(.green) }；
//     Button(...) }。
//  ⑯ 純視覺層調整，performSave() 內部守衛判斷、Apple 行事曆同步與通知排程等既有商業邏輯
//     完全未變動。全 App 同型待辦清單（v25.96 OrganizationView 紀錄）已剩 LifeFinanceView／
//     ResumeView／ChildDetailView，下次可依序比照補齊。
//   （下次美化本檔案時，可轉往其他仍留有待辦的畫面）

struct PersonalEventEditor: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let initialDate: Date
    let editing: PersonalEvent?
    /// 新增時的預設類型（會議 / 事務）；編輯既有事件時忽略
    var initialKind: PersonalEventKind = .meeting

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
    // 防止連續點擊「新增/儲存」在 performSave() 的多個 await 中間隙並發觸發，
    // 各自用不同 UUID 建立事件而互相偵測不到對方，造成重複事件／重複行事曆項目／重複通知
    // （同型修復見 SubscriptionManager.purchaseInProgress）。
    @State private var isSaving = false
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
    @State private var locationDebouncedQuery: String = ""

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

    /// 統一 Section 標題：4pt 漸層色條 + 圖示 + 粗體文字，對齊 RecordEditorSheet／MeetingEditorSheet／
    /// TaskEditorSheet.editorSectionHeader 規格。tint 預設依目前選取的事件類型
    /// （會議＝indigo／事務＝cyan，沿用 CalendarEventCard.color 相同配色）。
    private func editorSectionHeader(_ title: String, icon: String, tint: Color? = nil) -> some View {
        let color = tint ?? (kind == .meeting ? .indigo : .cyan)
        return HStack(spacing: 8) {
            Capsule()
                .fill(LinearGradient(colors: [color, color.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 16)
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.weight(.bold))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("類型", selection: $kind) {
                        ForEach(PersonalEventKind.allCases) { k in
                            Label(k.rawValue, systemImage: k.icon).tag(k)
                        }
                    }
                    TextField("標題", text: $title)
                } header: {
                    editorSectionHeader("基本資訊", icon: kind.icon)
                }

                Section {
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
                } header: {
                    editorSectionHeader("時間", icon: "clock")
                }

                Section {
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
                } header: {
                    editorSectionHeader("重複", icon: "repeat")
                }

                Section {
                    Picker("提前提醒", selection: $reminder) {
                        ForEach(EventReminder.allCases) { r in
                            Text(r.displayName).tag(r)
                        }
                    }
                    if reminder != .none {
                        Text(reminderHint)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } header: {
                    editorSectionHeader("提醒", icon: "bell.badge")
                }

                appleCalendarSection

                Section {
                    TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
                } header: {
                    editorSectionHeader("備註", icon: "note.text", tint: Color(.systemGray2))
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
                    // [美化 v25.100] 存檔中顯示同色 ProgressView，對齊 SubordinateDetailView v25.99／
                    // OrganizationView v25.96 等 isSaving 忙碌守衛按鈕載入狀態規格。
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView().scaleEffect(0.7).tint(.green)
                        }
                        Button(editing == nil ? "新增" : "儲存") { save() }
                            .bold().foregroundStyle(.green)
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    }
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
                    // 新事件：套用預設類型（會議 / 事務），日期用使用者選的那天
                    kind = initialKind
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
            // 避免 300ms 防抖期間關閉表單後，Task 仍在背景驅動地點搜尋（對齊 AddExpenseView 的修復）
            .onDisappear { locationDebounceTask?.cancel() }
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
            editorSectionHeader("Apple 行事曆", icon: "calendar.badge.plus")
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
            locationDebouncedQuery = location
            if !location.isEmpty { locationCompleter.queryFragment = location }
        }
        .onChange(of: location) { _, newValue in
            if locationSuppressNextUpdate {
                locationSuppressNextUpdate = false
                // 選取建議項目屬於使用者明確動作，非逐字輸入，立即同步不必等防抖
                locationDebouncedQuery = newValue
                return
            }
            locationExpandedSuggestions = false
            locationDebounceTask?.cancel()
            locationDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                locationCompleter.queryFragment = newValue
                // [效能] allLocationSuggestions 原本直接讀取 location（每個按鍵字元都觸發一次
                // 對 lifeStore.personalEvents 的全量掃描），比照本檔案其餘搜尋欄位（電子發票／
                // 診所地點自動完成）既有的 300ms 防抖規格，本地歷史地點比對也改讀防抖後的值。
                locationDebouncedQuery = newValue
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
        let q = locationDebouncedQuery.trimmingCharacters(in: .whitespaces).lowercased()
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
        guard !trimmedTitle.isEmpty, !isSaving else { return }
        isSaving = true
        Task { await performSave(trimmedTitle: trimmedTitle) }
    }

    @MainActor
    private func performSave(trimmedTitle: String) async {
        defer { isSaving = false }
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

// MARK: - 行事曆事件預覽卡片（點事件先看卡片，右上角「編輯」才進入編輯）
// 個人事件 / 里程碑可編輯；系統行事曆事件提供「在行事曆開啟」；生日 / 紀念日為唯讀資訊。

struct CalendarEventCard: View {
    enum Item: Identifiable {
        case personalEvent(PersonalEvent)
        case milestone(LifeMilestone)
        case appleEvent(title: String, time: Date?, detail: String, date: Date)
        case family(title: String, detail: String, isBirthday: Bool)

        var id: String {
            switch self {
            case .personalEvent(let e): return "pe_\(e.id.uuidString)"
            case .milestone(let m):     return "ms_\(m.id.uuidString)"
            case .appleEvent(let t, let time, _, let d):
                return "ek_\(t)_\(time?.timeIntervalSince1970 ?? 0)_\(d.timeIntervalSince1970)"
            case .family(let t, _, let b): return "fam_\(b ? "b" : "a")_\(t)"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    let item: Item
    @State private var showEdit = false
    // [v2] titleBlock 英雄卡進場動畫旗標
    @State private var cardAppeared = false

    private static let dtFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "yyyy/M/d (E) HH:mm"; return f
    }()
    private static let dFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "yyyy/M/d (E)"; return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleBlock
                    if !fields.isEmpty { infoCard }
                    if !noteText.isEmpty { noteBlock }
                    if case .appleEvent(_, _, _, let date) = item { openInCalendarButton(date) }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { trailingButton }
            }
            .sheet(isPresented: $showEdit) { editor }
        }
    }

    @ViewBuilder private var trailingButton: some View {
        switch item {
        case .personalEvent, .milestone:
            Button("編輯") { showEdit = true }.bold()
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var editor: some View {
        switch item {
        case .personalEvent(let e): PersonalEventEditor(initialDate: e.date, editing: e)
        case .milestone(let m):     AddMilestoneView(editing: m)
        default: EmptyView()
        }
    }

    // MARK: - 標頭 / 樣式

    private var navTitle: String {
        switch item {
        case .personalEvent: return "個人事件"
        case .milestone:     return "里程碑"
        case .appleEvent:    return "系統行事曆"
        case .family(_, _, let b): return b ? "生日" : "紀念日"
        }
    }

    private var accent: Color {
        switch item {
        case .personalEvent(let e): return e.kind == .meeting ? .indigo : .cyan
        case .milestone:            return Color(red: 0.99, green: 0.65, blue: 0.30)
        case .appleEvent:           return Color(red: 0.45, green: 0.65, blue: 0.95)
        case .family(_, _, let b):  return b ? Color(red: 0.99, green: 0.74, blue: 0.80) : Color(red: 0.95, green: 0.55, blue: 0.65)
        }
    }

    private var icon: String {
        switch item {
        case .personalEvent(let e): return e.kind == .meeting ? "person.3.fill" : "checklist"
        case .milestone(let m):     return m.category.icon
        case .appleEvent:           return "calendar"
        case .family(_, _, let b):  return b ? "gift.fill" : "heart.fill"
        }
    }

    private var titleText: String {
        switch item {
        case .personalEvent(let e): return e.title.isEmpty ? e.kind.rawValue : e.title
        case .milestone(let m):     return m.title.isEmpty ? "里程碑" : m.title
        case .appleEvent(let t, _, _, _): return t
        case .family(let t, _, _):  return t
        }
    }

    private var noteText: String {
        switch item {
        case .personalEvent(let e): return e.note
        case .milestone(let m):     return m.note
        default: return ""
        }
    }

    /// 卡片欄位（標籤、值）
    private var fields: [(String, String)] {
        switch item {
        case .personalEvent(let e):
            var out: [(String, String)] = [("類型", e.kind.rawValue)]
            out.append(("時間", e.durationMinutes > 0 ? Self.dtFmt.string(from: e.date) : Self.dFmt.string(from: e.date) + " 全日"))
            if e.durationMinutes > 0 { out.append(("長度", "\(e.durationMinutes) 分鐘")) }
            if e.recurrence != .none { out.append(("重複", e.recurrence.rawValue)) }
            if !e.location.isEmpty { out.append(("地點", e.location)) }
            return out
        case .milestone(let m):
            return [("分類", m.category.rawValue), ("日期", Self.dFmt.string(from: m.date))]
        case .appleEvent(_, let time, let detail, let date):
            var out: [(String, String)] = [("時間", time.map { Self.dtFmt.string(from: $0) } ?? (Self.dFmt.string(from: date) + " 全日"))]
            if !detail.isEmpty { out.append(("詳情", detail)) }
            return out
        case .family(_, let detail, _):
            return detail.isEmpty ? [] : [("資訊", detail)]
        }
    }

    /// [v2] 依事件類型變色的深色調漸層（top→bottom），供 titleBlock 英雄卡背景使用；
    /// 與純顯示用的淺色 accent（icon/欄位/按鈕）分開，避免淺色系（如 family 粉色系）
    /// 直接當滿版背景時白色文字對比不足。
    private var heroGradientColors: (top: Color, bottom: Color) {
        switch item {
        case .personalEvent(let e):
            return e.kind == .meeting
                ? (Color(red: 0.36, green: 0.32, blue: 0.86), Color(red: 0.20, green: 0.42, blue: 0.90))
                : (Color(red: 0.10, green: 0.62, blue: 0.70), Color(red: 0.04, green: 0.46, blue: 0.56))
        case .milestone:
            return (Color(red: 1.00, green: 0.62, blue: 0.28), Color(red: 0.88, green: 0.38, blue: 0.05))
        case .appleEvent:
            return (Color(red: 0.32, green: 0.56, blue: 0.95), Color(red: 0.14, green: 0.38, blue: 0.85))
        case .family(_, _, let isBirthday):
            return isBirthday
                ? (Color(red: 0.98, green: 0.55, blue: 0.62), Color(red: 0.88, green: 0.30, blue: 0.42))
                : (Color(red: 0.92, green: 0.45, blue: 0.55), Color(red: 0.75, green: 0.22, blue: 0.35))
        }
    }

    /// [v2] 從裸 icon + 標題文字，升級為依類型變色的漸層英雄卡（雙散景圓 + 頂部玻璃光澤），
    /// 對齊 StockDetailView／SubordinateDetailView 等其他「閃卡」詳情頁英雄卡規格。
    private var titleBlock: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 52, height: 52)
                Circle()
                    .stroke(.white.opacity(0.40), lineWidth: 1.25)
                    .frame(width: 52, height: 52)
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(navTitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.white.opacity(0.18))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 0.6))
                Text(titleText)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        // 事件卡的漸層依事件類型換色（會議／個人／里程碑／系統行事曆／家人生日等），
        // 走 runtimeColors；使用者在進階設定指定的顏色仍然優先。
        .heroCardShell(card: .calendarEvent,
                       runtimeColors: [heroGradientColors.top, heroGradientColors.bottom])
        .opacity(cardAppeared ? 1 : 0)
        .offset(y: cardAppeared ? 0 : 14)
        .onAppear {
            withAnimation(.spring(response: 0.50, dampingFraction: 0.78)) { cardAppeared = true }
        }
    }

    /// [v3] infoCard／noteBlock 共用標頭，比照 PersonalEventEditor.editorSectionHeader 規格
    /// （4pt 漸層色條 + 圖示 + .subheadline.bold），補上 v2 只做完 titleBlock 英雄卡、
    /// 下方兩張卡片卻仍是無標頭裸內容區塊的落差。tint 預設沿用卡片既有 accent（依事件
    /// 類型變色），備註沿用 editorSectionHeader 同款中性灰，純視覺調整、欄位資料不變。
    private func cardSectionHeader(_ title: String, icon: String, tint: Color? = nil) -> some View {
        let color = tint ?? accent
        return HStack(spacing: 8) {
            Capsule()
                .fill(LinearGradient(colors: [color, color.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 16)
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.weight(.bold))
            Spacer(minLength: 0)
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardSectionHeader("詳細資訊", icon: "info.circle")
            VStack(spacing: 0) {
                ForEach(Array(fields.enumerated()), id: \.offset) { idx, f in
                    HStack {
                        Text(f.0).font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Text(f.1).font(.subheadline.weight(.medium)).multilineTextAlignment(.trailing)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    if idx < fields.count - 1 { Divider().padding(.leading, 14) }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var noteBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardSectionHeader("備註", icon: "note.text", tint: Color(.systemGray2))
            Text(noteText).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func openInCalendarButton(_ date: Date) -> some View {
        Button {
            AppleCalendarBridge.shared.openInAppleCalendar(at: date)
        } label: {
            Label("在「行事曆」App 開啟", systemImage: "arrow.up.forward.app")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(accent.opacity(0.12))
                .foregroundStyle(accent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MyCalendarView()
        .environmentObject(LifeStore())
        .environmentObject(FinanceStore())
}
