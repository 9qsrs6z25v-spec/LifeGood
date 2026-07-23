import SwiftUI

// MARK: - 美化紀錄（SubordinateView）
// [2026-06 v1] 本次美化方向：
//   1. summaryStatsBar：頂部加入三格統計膠囊橫列（總人數 / 平均評分 / 優秀人數），
//      藍色漸層 hero card，散景裝飾圓 + spring 進場動畫（summaryAppeared）；
//      對齊 VariableExpenseView.monthSummaryHeader 設計語言。
//   2. subordinateRow：圓圈從 36pt 升至 44pt；改用 LinearGradient 填色 + 陰影；
//      左側加入 4pt 評分色彩強調條；評分數值移入右側 Capsule 膠囊；
//      部門名稱 + 職等以彩色 Capsule 呈現，對齊 ExpenseRow / FixedExpenseRow 規格。
//   3. emptyState：從純文字升級為雙層脈衝光環 + 漸層底圓 + 說明文字 + 藍色 CTA 按鈕，
//      對齊 VariableExpenseView.emptyStateView 設計規格。
//   4. 列表進場：加入交錯淡入 + 向上進場動畫（rowsAppeared），
//      對齊 FixedExpenseView.fixedExpenseSections 規格。
// [2026-06 v2] 本次美化方向：
//   1. summaryStatsCard 背景：補第三顆散景圓（中右 55pt、blur 8）+ 玻璃光澤
//      LinearGradient([white.opacity(0.18), clear] top→center)，對齊 v3+ hero card 標準。
//   2. subordinateRow 到職日：從純 icon+text 升級為 Capsule 日期徽章
//      （tertiarySystemFill 底色 + calendar icon），對齊 CareerView / OverviewView.recentRow v2。
//   3. subordinateRow 膠囊補細邊框：
//      - 職等/職稱膠囊：.overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
//      - 部門膠囊：.overlay(Capsule().stroke(Color(.separator).opacity(0.18), lineWidth: 0.6))
//   4. 列表新增 activeSubordinatesSectionHeader（4pt Capsule 漸層側條 + 人數計數徽章），
//      對齊 StockView.activeStocksSectionHeader 設計語言。

enum SubordinateSortOption: String, CaseIterable, Identifiable {
    case name = "姓名"
    case department = "部門"
    case jobTitle = "職位"
    case joinDate = "到職日期"
    case dateAdded = "新增順序"
    case manual = "手動排序"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .name: return "person"
        case .department: return "building.2"
        case .jobTitle: return "briefcase"
        case .joinDate: return "calendar.badge.clock"
        case .dateAdded: return "calendar"
        case .manual: return "hand.draw"
        }
    }
}

struct SubordinateView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showAdd = false
    @State private var editingItem: Subordinate?
    @State private var viewingItem: Subordinate?
    @State private var showPremiumAlert = false
    @State private var showRoster = false
    @State private var showTalentMatrix = false
    @AppStorage("subordinateSortOption") private var sortOptionRaw = SubordinateSortOption.dateAdded.rawValue
    @AppStorage("subordinateSortAscending") private var sortAscending = false
    @AppStorage("subordinateFilterDeptRaw") private var filterDeptRaw = ""   // "" = 全部部門

    private var selectedDeptId: UUID? {
        filterDeptRaw.isEmpty ? nil : UUID(uuidString: filterDeptRaw)
    }

    // 進場動畫旗標
    @State private var summaryAppeared = false
    @State private var rowsAppeared = false
    @State private var emptyIconPulse = false
    @State private var emptyIconPulseTask: Task<Void, Never>?
    // [2026-06 v2] sectionHeader 進場旗標
    @State private var headerAppeared = false

    private var sortOption: SubordinateSortOption {
        get { SubordinateSortOption(rawValue: sortOptionRaw) ?? .dateAdded }
        set { sortOptionRaw = newValue.rawValue }
    }

    private var sortOptionBinding: Binding<SubordinateSortOption> {
        Binding(
            get: { sortOption },
            set: { sortOptionRaw = $0.rawValue }
        )
    }

    private var sortedSubordinates: [Subordinate] {
        let list = lifeStore.subordinates
        if sortOption == .manual { return list }
        // 預先建立 id→index 對照，避免 sort closure 內部重複呼叫 firstIndex 造成 O(n² log n)
        let indexMap: [UUID: Int] = sortOption == .dateAdded
            ? Dictionary(list.indices.map { (list[$0].id, $0) }, uniquingKeysWith: { first, _ in first })
            : [:]
        // 預先建立部門標籤快取；deptLabel() 內部做 departments.first(where:) O(n)，
        // 若放在 sort closure 內每次比較都執行，整體排序退化為 O(n² log n)。
        let deptCache: [UUID: String] = sortOption == .department
            ? Dictionary(lifeStore.departments.map {
                ($0.id, $0.code.isEmpty ? $0.name : "\($0.code) \($0.name)")
            }, uniquingKeysWith: { first, _ in first })
            : [:]
        let sorted = list.sorted { a, b in
            let result: Bool
            switch sortOption {
            case .name: result = a.name < b.name
            case .department:
                let aLabel = a.departmentId.flatMap { deptCache[$0] } ?? a.department
                let bLabel = b.departmentId.flatMap { deptCache[$0] } ?? b.department
                result = aLabel < bLabel
            case .jobTitle: result = a.jobTitle < b.jobTitle
            case .joinDate:
                let ad = a.joinDate ?? Date.distantFuture
                let bd = b.joinDate ?? Date.distantFuture
                result = ad < bd
            case .dateAdded:
                result = (indexMap[a.id] ?? 0) < (indexMap[b.id] ?? 0)
            case .manual:
                result = false
            }
            return sortAscending ? result : !result
        }
        return sorted
    }

    /// 部門標籤（代號 + 名稱）
    private func deptLabel(_ dept: Department) -> String {
        if dept.code.isEmpty { return dept.name.isEmpty ? "未命名部門" : dept.name }
        return dept.name.isEmpty ? dept.code : "\(dept.code) \(dept.name)"
    }

    /// 套用部門篩選後的清單（保留排序）
    private var filteredSubordinates: [Subordinate] {
        guard let id = selectedDeptId else { return sortedSubordinates }
        return sortedSubordinates.filter { $0.departmentId == id }
    }

    /// 列表顯示列：依廠區分組（標題 + 人員）；手動排序時維持平面以便拖曳。
    private enum ListRow: Identifiable {
        case header(String)
        case person(Subordinate)
        var id: String {
            switch self {
            case .header(let s): return "h_\(s)"
            case .person(let p): return "p_\(p.id.uuidString)"
            }
        }
    }

    private func displayRows(_ filtered: [Subordinate]) -> [ListRow] {
        let list = filtered
        if sortOption == .manual { return list.map { .person($0) } }
        let grouped = Dictionary(grouping: list) { $0.plantArea }
        let areas = grouped.keys.filter { !$0.isEmpty }.sorted()
        if areas.isEmpty { return list.map { .person($0) } }   // 無人分廠區 → 平面顯示
        var rows: [ListRow] = []
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

    // MARK: - 列表內容（拆分以降低型別檢查負擔）

    @ViewBuilder
    private func subordinateSections(mentionCounts: [UUID: Int]) -> some View {
        // filteredSubordinates／displayRows 各自是 filter/O(n log n) 排序，一次算好供本
        // section 的空狀態檢查、計數徽章、ForEach 共用，避免同一次 body 求值各自重跑三次。
        let filtered = filteredSubordinates
        let rows = displayRows(filtered)
        // 部門篩選列（有定義部門才顯示）
        if !lifeStore.departments.isEmpty {
            Section {
                departmentFilterBar
                    .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }

        // 部屬列表 sectionHeader（4pt Capsule 側條 + 計數徽章）
        Section {
            activeSubordinatesSectionHeader(count: filtered.count)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 2, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .opacity(headerAppeared ? 1 : 0)
                .offset(y: headerAppeared ? 0 : 8)
                .onAppear {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.80).delay(0.12)) {
                        headerAppeared = true
                    }
                }
        }

        if filtered.isEmpty {
            Section {
                Text("此部門尚無部屬")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        } else {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                listRow(row, idx: idx, mentionCounts: mentionCounts)
            }
            .onDelete { offsets in
                guard subscription.isPremium else { showPremiumAlert = true; return }
                let items = offsets.compactMap { off -> Subordinate? in
                    guard off < rows.count, case .person(let s) = rows[off] else { return nil }
                    return s
                }
                items.forEach { lifeStore.deleteSubordinate($0) }
            }
            .onMove { from, to in
                guard subscription.isPremium else { showPremiumAlert = true; return }
                // 僅在「手動排序 + 全部部門」的平面清單下允許拖曳，offset 才與底層陣列一致
                guard sortOption == .manual, selectedDeptId == nil else { return }
                lifeStore.subordinates.move(fromOffsets: from, toOffset: to)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                Button { showTalentMatrix = true } label: {
                    Image(systemName: "chart.dots.scatter").font(.title3).foregroundStyle(.blue)
                }
                Button { showRoster = true } label: {
                    Image(systemName: "calendar.day.timeline.left").font(.title3).foregroundStyle(.blue)
                }
                sortMenu
                Button {
                    if subscription.isPremium { showAdd = true } else { showPremiumAlert = true }
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                }
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SubordinateSortOption.allCases) { option in
                Button {
                    if sortOption == option {
                        sortAscending.toggle()
                    } else {
                        sortOptionRaw = option.rawValue
                        sortAscending = true
                    }
                } label: {
                    Label {
                        Text(option.rawValue)
                    } icon: {
                        Image(systemName: sortOption == option
                              ? (sortAscending ? "chevron.up" : "chevron.down")
                              : option.icon)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle").font(.title3).foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private func listRow(_ row: ListRow, idx: Int, mentionCounts: [UUID: Int]) -> some View {
        switch row {
        case .header(let area):
            plantAreaHeader(area)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 2, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        case .person(let sub):
            subordinateRow(sub, mentionCounts: mentionCounts)
                .contentShape(Rectangle())
                .onTapGesture { viewingItem = sub }
                .opacity(rowsAppeared ? 1 : 0)
                .offset(y: rowsAppeared ? 0 : 14)
                .animation(
                    .spring(response: 0.45, dampingFraction: 0.82).delay(0.05 * Double(min(idx, 12))),
                    value: rowsAppeared
                )
        }
    }

    var body: some View {
        // 一次計算被標註計數（O(N×M) 全量掃描），供頂部統計卡與每一列共用，
        // 避免 summaryStatsCard 的 subordinates.map 與每一列 subordinateRow 各自重複觸發全量重算。
        let mentionCounts = lifeStore.mentionedCounts()
        return NavigationStack {
            List {
                // 頂部統計摘要卡（有部屬才顯示）
                if !lifeStore.subordinates.isEmpty {
                    Section {
                        summaryStatsCard(mentionCounts: mentionCounts)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .opacity(summaryAppeared ? 1 : 0)
                            .offset(y: summaryAppeared ? 0 : 20)
                            .onAppear {
                                withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                                    summaryAppeared = true
                                }
                            }
                    }
                }

                if lifeStore.subordinates.isEmpty {
                    Section {
                        emptyStateView
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    subordinateSections(mentionCounts: mentionCounts)
                }
            }
            .environment(\.editMode, sortOption == .manual ? .constant(.active) : .constant(.inactive))
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("部屬")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.08)) {
                    rowsAppeared = true
                }
            }
            // 部屬全部刪除後 summaryStatsCard 與 sectionHeader 從畫面移除，
            // 旗標需歸零讓下次新增部屬時進場動畫能重新播放（對齊 FamilyView v22.11 修復規格）。
            .onChange(of: lifeStore.subordinates.isEmpty) { _, isEmpty in
                if isEmpty {
                    summaryAppeared = false
                    headerAppeared = false
                }
            }
            .onChange(of: lifeStore.departments.map(\.id)) { _, ids in
                // 所選部門被刪除時，篩選回復為「全部部門」（用 id 陣列觀察，避免 Department 需 Equatable）
                if let id = selectedDeptId, !ids.contains(id) {
                    filterDeptRaw = ""
                }
            }
            .sheet(isPresented: $showAdd) { AddSubordinateView() }
            .sheet(item: $editingItem) { item in AddSubordinateView(editing: item) }
            .sheet(item: $viewingItem) { item in SubordinateDetailView(subordinate: item) }
            .sheet(isPresented: $showRoster) { SubordinateRosterView() }
            .sheet(isPresented: $showTalentMatrix) { TalentMatrixView() }
            .premiumLockAlert(isPresented: $showPremiumAlert)
        }
    }

    // MARK: - 統計摘要卡

    private func summaryKpiCell(label: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func summaryStatsCard(mentionCounts: [UUID: Int]) -> some View {
        let subordinates = lifeStore.subordinates
        let scores = subordinates.map { subordinateScore($0, mentionCounts: mentionCounts) }
        let total = subordinates.count
        let avg: Int = scores.isEmpty ? 0 : scores.reduce(0, +) / scores.count
        let excellent = scores.filter { $0 >= 90 }.count
        let needImprovement = scores.filter { $0 < 70 }.count
        let avgColor: Color = avg >= 90 ? .green : avg >= 80 ? .blue : avg >= 70 ? .orange : .red

        return VStack(spacing: 0) {
            // 頂部：部屬人數 + 當前排序方式
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("部屬總覽")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.80))
                    Text("\(total) 位部屬")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                Spacer()
                // 當前排序膠囊
                HStack(spacing: 4) {
                    Image(systemName: sortOption.icon)
                        .font(.system(size: 9))
                    Text(sortOption.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.white.opacity(0.20))
                .clipShape(Capsule())
                .foregroundStyle(.white)
            }

            // KPI 橫列：平均評分 / 優秀人數 / 整體分布
            HStack(spacing: 0) {
                summaryKpiCell(label: "平均評分", value: "\(avg)",
                               icon: "chart.bar.fill")
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 0.5, height: 28)
                summaryKpiCell(label: "優秀（90+）", value: "\(excellent) 位",
                               icon: "star.fill")
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 0.5, height: 28)
                summaryKpiCell(label: "待提升（<70）",
                               value: "\(needImprovement) 位",
                               icon: "exclamationmark.triangle.fill")
            }
            .padding(.vertical, 10)
            .background(.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.top, 12)

            // 評分進度條（視覺化當前平均評分）
            VStack(spacing: 5) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.18))
                            .frame(height: 5)
                        Capsule()
                            .fill(.white.opacity(0.80))
                            .frame(width: geo.size.width * CGFloat(avg) / 100.0, height: 5)
                            .animation(.spring(response: 0.7, dampingFraction: 0.8),
                                       value: avg)
                    }
                }
                .frame(height: 5)
                HStack {
                    Text("團隊平均 \(avg) 分")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.60))
                    Spacer()
                    Text(avg >= 90 ? "表現優秀" : avg >= 80 ? "表現良好" : avg >= 70 ? "尚可改善" : "需要關注")
                        .font(.caption2)
                        .foregroundStyle(avgColor.opacity(0.90))
                }
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.22, green: 0.53, blue: 0.98),
                        Color(red: 0.10, green: 0.35, blue: 0.82)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // 右上主散景圓
                Circle()
                    .fill(.white.opacity(0.13))
                    .frame(width: 130, height: 130)
                    .offset(x: 85, y: -50)
                    .blur(radius: 14)
                // 左下次散景圓
                Circle()
                    .fill(.white.opacity(0.07))
                    .frame(width: 80, height: 80)
                    .offset(x: -65, y: 50)
                    .blur(radius: 10)
                // [2026-06 v2] 第三顆中右散景圓（對齊 v3+ hero card 標準）
                Circle()
                    .fill(.white.opacity(0.055))
                    .frame(width: 55, height: 55)
                    .offset(x: 30, y: 40)
                    .blur(radius: 8)
                // [2026-06 v2] 玻璃光澤（對齊 v3+ hero card 標準）
                LinearGradient(
                    colors: [.white.opacity(0.18), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.10, green: 0.35, blue: 0.82).opacity(0.42), radius: 16, x: 0, y: 8)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    // MARK: - 部屬列表 sectionHeader [2026-06 v2]

    // MARK: - 部門篩選列 / 廠區分組標題

    private var departmentFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "全部部門", active: selectedDeptId == nil) { filterDeptRaw = "" }
                ForEach(lifeStore.departments) { dept in
                    filterChip(title: deptLabel(dept), active: selectedDeptId == dept.id) {
                        filterDeptRaw = dept.id.uuidString
                    }
                }
            }
            .padding(.horizontal, 4).padding(.vertical, 2)
        }
    }

    private func filterChip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(active ? Color.blue : Color(.secondarySystemBackground))
                .foregroundStyle(active ? .white : .primary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(active ? Color.blue : Color(.separator).opacity(0.3), lineWidth: 0.75))
        }
        .buttonStyle(.plain)
    }

    /// 廠區分組標題列（對齊部屬班表的廠區分段樣式）
    private func plantAreaHeader(_ area: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "building.2.fill").font(.system(size: 10, weight: .semibold))
            Text(area).font(.system(size: 12, weight: .bold)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.blue)
    }

    private func activeSubordinatesSectionHeader(count: Int) -> some View {
        let accent = Color(red: 0.22, green: 0.53, blue: 0.98)
        let title = selectedDeptId.flatMap { id in lifeStore.departments.first { $0.id == id } }
            .map { deptLabel($0) } ?? "部屬成員"
        return HStack(spacing: 8) {
            // 4pt Capsule 漸層側條（對齊 StockView.activeStocksSectionHeader 規格）
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.45)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 16)
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
            // 計數徽章
            Text("\(count) 位")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(accent.opacity(0.10))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
        }
        .padding(.vertical, 2)
    }

    // MARK: - 空狀態

    private var emptyStateView: some View {
        let accent = Color(red: 0.22, green: 0.53, blue: 0.98)
        return VStack(spacing: 24) {
            ZStack {
                // 外層脈衝光環
                Circle()
                    .stroke(accent.opacity(emptyIconPulse ? 0 : 0.28), lineWidth: 1.5)
                    .frame(width: 108, height: 108)
                    .scaleEffect(emptyIconPulse ? 1.35 : 1.0)
                    .animation(
                        .easeOut(duration: 2.0).repeatForever(autoreverses: false),
                        value: emptyIconPulse
                    )
                // 內層脈衝光環（延遲 0.3s，製造波紋層次）
                Circle()
                    .stroke(accent.opacity(emptyIconPulse ? 0 : 0.13), lineWidth: 1)
                    .frame(width: 108, height: 108)
                    .scaleEffect(emptyIconPulse ? 1.62 : 1.0)
                    .animation(
                        .easeOut(duration: 2.0).delay(0.3).repeatForever(autoreverses: false),
                        value: emptyIconPulse
                    )
                // 主圓底（漸層填色 + 細邊框）
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.15), accent.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .overlay(
                        Circle()
                            .stroke(accent.opacity(0.22), lineWidth: 1.2)
                    )
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(accent.opacity(0.72))
            }
            .onAppear {
                emptyIconPulse = false
                emptyIconPulseTask?.cancel()
                emptyIconPulseTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    emptyIconPulse = true
                }
            }
            .onDisappear {
                emptyIconPulseTask?.cancel()
                emptyIconPulse = false
            }

            VStack(spacing: 10) {
                Text("尚無部屬紀錄")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.75))
                Text("新增部屬後，可追蹤每位成員的\n評分、職等、到職日期與部門資訊")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Button {
                if subscription.isPremium { showAdd = true }
                else { showPremiumAlert = true }
            } label: {
                Label("新增第一位部屬", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [accent, Color(red: 0.10, green: 0.35, blue: 0.82)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color(red: 0.10, green: 0.35, blue: 0.82).opacity(0.35), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    // MARK: - 部屬列

    private func subordinateRow(_ sub: Subordinate, mentionCounts: [UUID: Int]) -> some View {
        let score = subordinateScore(sub, mentionCounts: mentionCounts)
        let accent = scoreColor(score)

        return HStack(spacing: 0) {
            // 左側評分色彩強調條（4pt，對齊 ExpenseRow / FixedExpenseRow 規格）
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.40)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4)
                .padding(.vertical, 8)
                .padding(.trailing, 14)

            // 頭像圓（44pt 漸層填色 + 評分數字，對齊 ExpenseRow 規格）
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.22), accent.opacity(0.09)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .shadow(color: accent.opacity(0.22), radius: 6, x: 0, y: 3)
                Circle()
                    .stroke(accent.opacity(0.30), lineWidth: 1.5)
                    .frame(width: 44, height: 44)
                Text("\(score)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
            }
            .padding(.trailing, 12)

            // 姓名 + 職等 + 到職年數
            VStack(alignment: .leading, spacing: 4) {
                Text(sub.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                // 職等 + 部門膠囊橫列
                HStack(spacing: 5) {
                    if let gt = lifeStore.gradeTitles.first(where: { $0.id == sub.gradeTitleId }) {
                        Text("\(gt.grade) \(gt.title)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 7).padding(.vertical, 2.5)
                            .background(accent.opacity(0.12))
                            .clipShape(Capsule())
                            // [2026-06 v2] 職等膠囊補細邊框
                            .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
                    } else if !sub.jobTitle.isEmpty {
                        Text(sub.jobTitle)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 7).padding(.vertical, 2.5)
                            .background(accent.opacity(0.12))
                            .clipShape(Capsule())
                            // [2026-06 v2] 職稱膠囊補細邊框
                            .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
                            .lineLimit(1)
                    }

                    // 部門名稱膠囊
                    let deptName = resolvedDeptName(sub)
                    if !deptName.isEmpty {
                        Text(deptName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2.5)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                            // [2026-06 v2] 部門膠囊補細邊框
                            .overlay(Capsule().stroke(Color(.separator).opacity(0.18), lineWidth: 0.6))
                            .lineLimit(1)
                    }
                }

                // [2026-06 v2] 到職日：升級為 Capsule 日期徽章（對齊 CareerView / OverviewView.recentRow v2）
                if let jd = sub.joinDate {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 9, weight: .medium))
                        Text("到職 \(formatDate(jd))")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color(.separator).opacity(0.15), lineWidth: 0.5))
                }
            }

            Spacer(minLength: 8)

            // 右側：評分等級膠囊
            VStack(alignment: .trailing, spacing: 4) {
                Text(scoreLevelLabel(score))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(accent.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .padding(.vertical, 6)
    }

    private func resolvedDeptName(_ sub: Subordinate) -> String {
        if let dept = lifeStore.departments.first(where: { $0.id == sub.departmentId }) {
            return dept.code.isEmpty ? dept.name : "\(dept.code) \(dept.name)"
        }
        return sub.department
    }

    private func scoreLevelLabel(_ score: Int) -> String {
        switch score {
        case 90...: return "優秀"
        case 80...: return "良好"
        case 70...: return "尚可"
        default:    return "需關注"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()

    private func formatDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }

    /// 列表顯示分數：潛力與主動性的平均（含被標註加分）。
    /// mentionCounts 由呼叫端（body）以 lifeStore.mentionedCounts() 算好一次傳入，
    /// 避免每一列各自重新全量掃描所有部屬的任務/會議/報告。
    private func subordinateScore(_ sub: Subordinate, mentionCounts: [UUID: Int]) -> Int {
        sub.overallScore(mentionedCount: mentionCounts[sub.id] ?? 0)
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 90...:  return .green
        case 80...:  return .blue
        case 70...:  return .orange
        default:     return .red
        }
    }
}

// MARK: - 新增/編輯部屬

struct AddSubordinateView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    var editing: Subordinate?

    @State private var name = ""
    @State private var hasJoinDate = false
    @State private var joinDate = Date()
    @State private var selectedGradeTitleId: UUID?
    @State private var selectedDepartmentId: UUID?
    @State private var department = ""
    @State private var note = ""
    @State private var hasPlantArea = false
    @State private var plantArea = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    TextField("姓名", text: $name)
                    Toggle("填入入職日期", isOn: $hasJoinDate)
                    if hasJoinDate {
                        DatePicker("入職日期", selection: $joinDate, displayedComponents: .date)
                    }
                    gradeTitlePicker
                    departmentPicker
                    plantAreaField
                }
                Section("備註") {
                    TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
                }
            }
            .navigationTitle(editing != nil ? "編輯部屬" : "新增部屬")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing != nil ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(!canSave)
                }
            }
            .onAppear { loadEditing() }
        }
    }

    @ViewBuilder
    private var gradeTitlePicker: some View {
        if lifeStore.gradeTitles.isEmpty {
            HStack {
                Text("職位")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("請先至「部門職等」設定")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        } else {
            Picker("職位", selection: $selectedGradeTitleId) {
                Text("未選擇").tag(UUID?.none)
                ForEach(lifeStore.gradeTitles) { gt in
                    Text("\(gt.grade) — \(gt.title)").tag(UUID?.some(gt.id))
                }
            }
        }
    }

    /// 既有部屬已用過的廠區名稱（給快速選取，避免打錯字導致分組不一致）
    private var existingPlantAreas: [String] {
        Array(Set(lifeStore.subordinates.map { $0.plantArea }.filter { !$0.isEmpty })).sorted()
    }

    @ViewBuilder
    private var plantAreaField: some View {
        Toggle("分廠區", isOn: $hasPlantArea.animation())
        if hasPlantArea {
            TextField("廠區名稱（例如 A、B、P1、P2）", text: $plantArea)
            if !existingPlantAreas.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(existingPlantAreas, id: \.self) { area in
                            Button { plantArea = area } label: {
                                Text(area)
                                    .font(.caption)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(plantArea == area ? Color.blue.opacity(0.15) : Color(.secondarySystemBackground))
                                    .foregroundStyle(plantArea == area ? Color.blue : Color.primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var departmentPicker: some View {
        if lifeStore.departments.isEmpty {
            TextField("部門", text: $department)
        } else {
            Picker("部門", selection: $selectedDepartmentId) {
                Text("未選擇").tag(UUID?.none)
                ForEach(lifeStore.departments) { dept in
                    Text(dept.code.isEmpty ? dept.name : "\(dept.code) — \(dept.name)")
                        .tag(UUID?.some(dept.id))
                }
            }
        }
    }

    private func save() {
        let linkedTitle: String
        if let gtId = selectedGradeTitleId,
           let gt = lifeStore.gradeTitles.first(where: { $0.id == gtId }) {
            linkedTitle = "\(gt.grade) — \(gt.title)"
        } else {
            linkedTitle = ""
        }

        let deptText: String
        if let dId = selectedDepartmentId,
           let dept = lifeStore.departments.first(where: { $0.id == dId }) {
            deptText = dept.code.isEmpty ? dept.name : "\(dept.code) — \(dept.name)"
        } else {
            deptText = department.trimmingCharacters(in: .whitespaces)
        }

        let existingRecords = editing?.records ?? []
        let item = Subordinate(
            id: editing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            jobTitle: linkedTitle,
            department: deptText,
            note: note.trimmingCharacters(in: .whitespaces),
            gradeTitleId: selectedGradeTitleId,
            departmentId: selectedDepartmentId,
            records: existingRecords,
            joinDate: hasJoinDate ? joinDate : nil,
            // 編輯時務必帶回既有的會議與任務，否則 update() 會以空陣列覆蓋而導致消失
            meetings: editing?.meetings ?? [],
            tasks: editing?.tasks ?? [],
            // 帶回既有班別，避免編輯部屬後排好的班被清掉
            shifts: editing?.shifts ?? [],
            plantArea: hasPlantArea ? plantArea.trimmingCharacters(in: .whitespaces) : "",
            weeklyReports: editing?.weeklyReports ?? [],
            // 帶回既有執掌設備（PM/警報記錄），避免編輯基本資料時被空陣列覆蓋
            equipments: editing?.equipments ?? []
        )
        if editing != nil { lifeStore.update(item) } else { lifeStore.add(item) }
        dismiss()
    }

    private func loadEditing() {
        guard let e = editing else { return }
        name = e.name
        selectedGradeTitleId = e.gradeTitleId
        selectedDepartmentId = e.departmentId
        department = e.department
        note = e.note
        plantArea = e.plantArea
        hasPlantArea = !e.plantArea.isEmpty
        if let jd = e.joinDate {
            hasJoinDate = true
            joinDate = jd
        }
    }
}
