import SwiftUI

// MARK: - 美化紀錄（SubordinateRosterView）
// v1 美化方向：
//   filterBar  — 月份切換箭頭升級為 36pt 填充圓形按鈕（對齊 TaxOverviewView.yearPicker 規格）；
//                部門 Menu 膠囊加動態 tint（選取時藍底/邊框，預設次要背景）
//   legendChip — 色塊從 12pt 方形改 8pt Circle；加 color.opacity(0.10) 膠囊背景 + stroke 邊框
//   emptyHint  — 升級雙層脈衝光環 + 靛藍漸層底圓 + icon 尺寸 36pt（對齊 SubordinateView.emptyState）；
//                加細說明文字，兩種狀態（全空 vs 本部門空）分別顯示
// v2 美化方向（RosterCellDetailSheet）：
//   heroSection    — 頂部人員概覽列：44pt 靛藍漸層姓名縮寫圓（2字）+ 姓名 + 日期膠囊（假日紅/平日藍）
//                    + 班別彩色膠囊（依 rosterShiftColor）或「未排班」灰膠囊；
//                    進場 spring 動畫（heroAppeared，對齊 SubordinateDetailView.headerCard 規格）。
//   shiftSection   — Section 標題升級為 Capsule 色條 + 圖示 + .subheadline.semibold（sectionHeader 輔助）；
//                    「目前班別」列：班別名稱從純 bold 文字升級為彩色膠囊（含細邊框），
//                    對齊 legendChip + OverviewView.categoryRow 百分比膠囊規格；
//                    上班時間列：時間文字加 rosterShiftColor 著色，強化視覺關聯。
//   summarySection — Section 標題升級 sectionHeader；
//                    各事項（請假 / 會議 / 任務）從裸 Label 升級為
//                    32pt 漸層圖示圓 + 文字（對齊 SubordinateOverviewView.recordRow 規格）；
//                    全空時顯示 checkmark.circle.fill 微型圖示 + 說明文字，對齊 emptyHint 小型空狀態。
//   actionSection  — Section 標題升級 sectionHeader；
//                    動作列從裸 Label 升級為 32pt 漸層圖示圓 + 文字，
//                    對齊 SubordinateDetailView.sectionHeader 規格。
//   Form 背景      — 補 .scrollContentBackground(.hidden) + .background(systemGroupedBackground)，
//                    深色模式不再出現白色 List 背景，對齊 FixedExpenseView / ResumeView 規格。

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
    case .dayDuty:      return .mint
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
    @State private var emptyIconPulse = false

    private let nameColWidth: CGFloat = 88
    private let cellW: CGFloat = 40
    private let cellH: CGFloat = 42
    private let headerH: CGFloat = 38
    private let groupHeaderH: CGFloat = 26

    // MARK: 資料

    private var people: [Subordinate] {
        lifeStore.subordinates
            .filter { selectedDeptId == nil || $0.departmentId == selectedDeptId }
            .sorted { $0.name < $1.name }
    }

    /// 班表列：依廠區分組後的展開列（廠區標題 + 各部屬）
    private enum RosterRow: Identifiable {
        case header(String)
        case person(Subordinate)
        var id: String {
            switch self {
            case .header(let s):  return "h_\(s)"
            case .person(let p):  return "p_\(p.id.uuidString)"
            }
        }
    }

    /// 把 people 依廠區分組：有分廠區者各自成段（前面加標題），未分廠區者收在最後。
    /// 完全沒有人分廠區時，回傳純名單（不顯示任何標題）。
    private var rosterRows: [RosterRow] {
        let ppl = people
        let grouped = Dictionary(grouping: ppl) { $0.plantArea }
        let areas = grouped.keys.filter { !$0.isEmpty }.sorted()
        if areas.isEmpty { return ppl.map { .person($0) } }
        var rows: [RosterRow] = []
        for area in areas {
            rows.append(.header(area))
            rows.append(contentsOf: (grouped[area] ?? []).map { .person($0) })
        }
        if let unassigned = grouped[""], !unassigned.isEmpty {
            rows.append(.header("未分廠區"))
            rows.append(contentsOf: unassigned.map { .person($0) })
        }
        return rows
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
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                Button { shiftMonth(-1) } label: {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Text(monthTitle)
                    .font(.title3.weight(.semibold))
                Spacer()
                Button { shiftMonth(1) } label: {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                }
                .buttonStyle(.plain)
            }
            Menu {
                Button("全部部門") { selectedDeptId = nil }
                ForEach(lifeStore.departments) { d in
                    Button(d.name.isEmpty ? d.code : d.name) { selectedDeptId = d.id }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(selectedDeptId == nil ? Color.secondary : Color.blue)
                    Text(selectedDeptName).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(selectedDeptId == nil ? Color.primary : Color.blue)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(selectedDeptId == nil ? Color(.secondarySystemBackground) : Color.blue.opacity(0.10))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(selectedDeptId == nil ? Color.clear : Color.blue.opacity(0.22), lineWidth: 0.75))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.6))
    }

    private var emptyHint: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(Color.indigo.opacity(emptyIconPulse ? 0 : 0.28), lineWidth: 1.5)
                    .frame(width: 110, height: 110)
                    .scaleEffect(emptyIconPulse ? 1.35 : 1.0)
                    .animation(.easeOut(duration: 2.0).repeatForever(autoreverses: false), value: emptyIconPulse)
                Circle()
                    .stroke(Color.indigo.opacity(emptyIconPulse ? 0 : 0.14), lineWidth: 1)
                    .frame(width: 110, height: 110)
                    .scaleEffect(emptyIconPulse ? 1.62 : 1.0)
                    .animation(.easeOut(duration: 2.0).delay(0.3).repeatForever(autoreverses: false), value: emptyIconPulse)
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.indigo.opacity(0.14), Color.indigo.opacity(0.06)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 88, height: 88)
                    .overlay(Circle().stroke(Color.indigo.opacity(0.22), lineWidth: 1.2))
                Image(systemName: "person.2.slash")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Color.indigo.opacity(0.70))
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { emptyIconPulse = true }
            }
            .onDisappear { emptyIconPulse = false }
            VStack(spacing: 8) {
                Text(selectedDeptId == nil ? "尚無部屬資料" : "此部門沒有部屬")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.75))
                Text(selectedDeptId == nil
                     ? "在部屬頁新增成員，即可在此管理班表"
                     : "切換為「全部部門」或新增部屬後即可查看班表")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    // MARK: 棋盤格

    private var gridArea: some View {
        ScrollView(.vertical, showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {
                // 凍結姓名欄
                VStack(spacing: 0) {
                    Color.clear.frame(width: nameColWidth, height: headerH)
                    ForEach(rosterRows) { row in
                        switch row {
                        case .header(let area): nameHeaderCell(area)
                        case .person(let p):    nameCell(p)
                        }
                    }
                }
                // 可水平捲動的整月格
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) { ForEach(days, id: \.self) { d in dayHeader(d) } }
                        ForEach(rosterRows) { row in
                            switch row {
                            case .header:        gridHeaderRow()
                            case .person(let p): HStack(spacing: 0) { ForEach(days, id: \.self) { d in cell(p, d) } }
                            }
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

    /// 廠區分段：姓名欄上的標題格
    private func nameHeaderCell(_ area: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "building.2.fill").font(.system(size: 9))
            Text(area).font(.system(size: 11, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.blue)
        .padding(.leading, 8)
        .frame(width: nameColWidth, height: groupHeaderH, alignment: .leading)
        .background(Color.blue.opacity(0.10))
        .overlay(Rectangle().stroke(Color(.separator).opacity(0.2), lineWidth: 0.5))
    }

    /// 廠區分段：日格區對齊的整列底色橫條
    private func gridHeaderRow() -> some View {
        Rectangle()
            .fill(Color.blue.opacity(0.10))
            .frame(width: CGFloat(days.count) * cellW, height: groupHeaderH)
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
    @State private var heroAppeared = false

    private var sub: Subordinate? { lifeStore.subordinates.first { $0.id == cell.subId } }

    private var initials: String {
        let name = sub?.name ?? ""
        if name.isEmpty { return "?" }
        return String(name.prefix(2))
    }

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
                heroSection
                shiftSection
                summarySection
                actionSection
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
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

    // MARK: - 人員概覽列（美化 v2）

    private var heroSection: some View {
        Section {
            HStack(spacing: 14) {
                // 姓名縮寫圓：44pt 靛藍漸層，對齊 SubordinateDetailView.headerCard 規格
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.indigo.opacity(0.22), Color.indigo.opacity(0.09)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: Color.indigo.opacity(0.18), radius: 6, x: 0, y: 2)
                    Circle()
                        .stroke(Color.indigo.opacity(0.22), lineWidth: 1)
                        .frame(width: 44, height: 44)
                    Text(initials)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.indigo)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(sub?.name.isEmpty == false ? sub!.name : "未知部屬")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        // 日期膠囊：假日用紅色，平日用藍色
                        Text(Self.headerDateFormatter.string(from: cell.date))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isHoliday ? .red : .blue)
                            .padding(.horizontal, 7).padding(.vertical, 2.5)
                            .background((isHoliday ? Color.red : Color.blue).opacity(0.10))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(
                                (isHoliday ? Color.red : Color.blue).opacity(0.22),
                                lineWidth: 0.6
                            ))
                        // 班別膠囊：依 rosterShiftColor 著色，未排班用次要灰
                        if let shift = currentShift {
                            Text(shift.rawValue)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(rosterShiftColor(shift))
                                .padding(.horizontal, 7).padding(.vertical, 2.5)
                                .background(rosterShiftColor(shift).opacity(0.10))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(rosterShiftColor(shift).opacity(0.22), lineWidth: 0.6))
                        } else {
                            Text("未排班")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7).padding(.vertical, 2.5)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .opacity(heroAppeared ? 1 : 0)
            .offset(y: heroAppeared ? 0 : 12)
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    heroAppeared = true
                }
            }
        }
    }

    // MARK: - Section 標題輔助（Capsule 色條 + 圖示 + 標題，對齊全 App sectionHeader 規格）

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 3, height: 16)
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .textCase(nil)
    }

    // MARK: - 摘要事項列輔助（32pt 漸層圓 + 文字，對齊 SubordinateOverviewView.recordRow 規格）

    private func summaryRow(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.22), color.opacity(0.09)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                Circle()
                    .stroke(color.opacity(0.20), lineWidth: 0.75)
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
    }

    // MARK: - 班別設定 Section（美化 v2）

    private var shiftSection: some View {
        Section {
            // 目前班別：彩色膠囊（含細邊框），對齊 legendChip 設計規格
            HStack {
                Text("目前班別")
                    .foregroundStyle(.secondary)
                Spacer()
                if let shift = currentShift {
                    Text(shift.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(rosterShiftColor(shift))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(rosterShiftColor(shift).opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(rosterShiftColor(shift).opacity(0.28), lineWidth: 0.6))
                } else {
                    Text("未排班")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }
            }
            // 上班時間：時間文字以班別色著色，強化視覺關聯
            if let s = currentShift, s.hasWorkTime,
               let r = scheduleStore.schedule.range(for: s, isHoliday: isHoliday) {
                HStack {
                    Text(isHoliday ? "時間（假日）" : "時間（平日）")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(r.display)
                        .monospacedDigit()
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(rosterShiftColor(s))
                }
            }
            Menu {
                ForEach(ShiftType.allCases) { t in
                    Button(t.rawValue) { lifeStore.setShift(subordinateId: cell.subId, date: cell.date, type: t) }
                }
            } label: {
                Label("設定 / 變更班別", systemImage: "calendar.badge.clock")
            }
            Button {
                lifeStore.applyNightShiftRotation(subordinateId: cell.subId, startDate: cell.date)
                dismiss()
            } label: {
                Label("從這天套用大夜班輪班（8 天）", systemImage: "arrow.triangle.2.circlepath")
            }
            Button {
                lifeStore.applyEveningShiftWeekdays(subordinateId: cell.subId, startDate: cell.date)
                dismiss()
            } label: {
                Label("套用小夜班（整週一至五 5 天）", systemImage: "moon.stars")
            }
            Button {
                lifeStore.setShift(subordinateId: cell.subId, date: cell.date, type: .dayDuty)
                dismiss()
            } label: {
                Label("設為日值班（單日，平日 08:30–17:30）", systemImage: "sun.max")
            }
            Button(role: .destructive) {
                lifeStore.setShift(subordinateId: cell.subId, date: cell.date, type: nil)
                dismiss()
            } label: {
                Label("清除這天班別", systemImage: "xmark.circle")
            }
        } header: {
            sectionHeader("班別設定", icon: "calendar.badge.clock", color: .indigo)
        }
    }

    // MARK: - 當天摘要 Section（美化 v2）

    private var summarySection: some View {
        Section {
            let leave = leaveRecord
            let meets = meetingsToday
            let dueTasks = tasksToday
            if leave == nil && meets.isEmpty && dueTasks.isEmpty {
                // 全空小型空狀態：圖示 + 說明文字，對齊 SubordinateOverviewView.emptyHint 規格
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.secondary.opacity(0.55))
                    Text("當天無請假 / 會議 / 任務")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            if let leave = leave {
                summaryRow(
                    icon: "calendar.badge.minus",
                    title: "請假：\(leave.leaveType?.rawValue ?? "")",
                    color: .teal
                )
            }
            ForEach(meets) { m in
                summaryRow(
                    icon: "person.2.fill",
                    title: m.topic.isEmpty ? "會議" : m.topic,
                    color: .indigo
                )
            }
            ForEach(dueTasks) { t in
                summaryRow(
                    icon: "checklist",
                    title: "\(t.topic.isEmpty ? "任務" : t.topic)（截止）",
                    color: .cyan
                )
            }
        } header: {
            sectionHeader("當天摘要", icon: "calendar.day.timeline.left", color: .teal)
        }
    }

    // MARK: - 快速操作 Section（美化 v2）

    private var actionSection: some View {
        Section {
            Button { showAddLeave = true } label: {
                summaryRow(icon: "plus.circle.fill", title: "快速新增請假", color: .teal)
            }
            .tint(.teal)
            Button { goDetail = true } label: {
                summaryRow(icon: "person.text.rectangle.fill", title: "前往部屬詳情頁", color: .blue)
            }
            .tint(.blue)
        } header: {
            sectionHeader("快速操作", icon: "bolt.fill", color: .orange)
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

    private let editable: [ShiftType] = [.nightShift, .eveningShift, .holidayDuty, .dayDuty]

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
