import SwiftUI

// MARK: - 美化紀錄（SubordinateView）
// [2026-06] 本次美化方向：
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
    @AppStorage("subordinateSortOption") private var sortOptionRaw = SubordinateSortOption.dateAdded.rawValue
    @AppStorage("subordinateSortAscending") private var sortAscending = false

    // 進場動畫旗標
    @State private var summaryAppeared = false
    @State private var rowsAppeared = false
    @State private var emptyIconPulse = false

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

    private func deptLabel(_ sub: Subordinate) -> String {
        if let dept = lifeStore.departments.first(where: { $0.id == sub.departmentId }) {
            return dept.code.isEmpty ? dept.name : "\(dept.code) \(dept.name)"
        }
        return sub.department
    }

    private var sortedSubordinates: [Subordinate] {
        let list = lifeStore.subordinates
        if sortOption == .manual { return list }
        let sorted = list.sorted { a, b in
            let result: Bool
            switch sortOption {
            case .name: result = a.name < b.name
            case .department: result = deptLabel(a) < deptLabel(b)
            case .jobTitle: result = a.jobTitle < b.jobTitle
            case .joinDate:
                let ad = a.joinDate ?? Date.distantFuture
                let bd = b.joinDate ?? Date.distantFuture
                result = ad < bd
            case .dateAdded:
                let ai = list.firstIndex(where: { $0.id == a.id }) ?? 0
                let bi = list.firstIndex(where: { $0.id == b.id }) ?? 0
                result = ai < bi
            case .manual:
                result = false
            }
            return sortAscending ? result : !result
        }
        return sorted
    }

    var body: some View {
        NavigationStack {
            List {
                // 頂部統計摘要卡（有部屬才顯示）
                if !lifeStore.subordinates.isEmpty {
                    Section {
                        summaryStatsCard
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
                    ForEach(Array(sortedSubordinates.enumerated()), id: \.element.id) { idx, sub in
                        subordinateRow(sub)
                            .contentShape(Rectangle())
                            .onTapGesture { viewingItem = sub }
                            .opacity(rowsAppeared ? 1 : 0)
                            .offset(y: rowsAppeared ? 0 : 14)
                            .animation(
                                .spring(response: 0.45, dampingFraction: 0.82)
                                    .delay(0.05 * Double(min(idx, 12))),
                                value: rowsAppeared
                            )
                    }
                    .onDelete { offsets in
                        guard subscription.isPremium else { showPremiumAlert = true; return }
                        let items = offsets.map { sortedSubordinates[$0] }
                        items.forEach { lifeStore.deleteSubordinate($0) }
                    }
                    .onMove { from, to in
                        guard subscription.isPremium else { showPremiumAlert = true; return }
                        guard sortOption == .manual else { return }
                        lifeStore.subordinates.move(fromOffsets: from, toOffset: to)
                    }
                }
            }
            .environment(\.editMode, sortOption == .manual ? .constant(.active) : .constant(.inactive))
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("部屬")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            showRoster = true
                        } label: {
                            Image(systemName: "calendar.day.timeline.left")
                                .font(.title3).foregroundStyle(.blue)
                        }

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
                                        if sortOption == option {
                                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                        } else {
                                            Image(systemName: option.icon)
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down.circle")
                                .font(.title3).foregroundStyle(.green)
                        }

                        Button {
                            if subscription.isPremium { showAdd = true }
                            else { showPremiumAlert = true }
                        } label: {
                            Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                        }
                    }
                }
            }
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.08)) {
                    rowsAppeared = true
                }
            }
            .sheet(isPresented: $showAdd) { AddSubordinateView() }
            .sheet(item: $editingItem) { item in AddSubordinateView(editing: item) }
            .sheet(item: $viewingItem) { item in SubordinateDetailView(subordinate: item) }
            .sheet(isPresented: $showRoster) { SubordinateRosterView() }
            .premiumLockAlert(isPresented: $showPremiumAlert)
        }
    }

    // MARK: - 統計摘要卡

    private var averageScore: Int {
        let list = lifeStore.subordinates
        guard !list.isEmpty else { return 0 }
        let total = list.map { subordinateScore($0) }.reduce(0, +)
        return total / list.count
    }

    private var excellentCount: Int {
        lifeStore.subordinates.filter { subordinateScore($0) >= 90 }.count
    }

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

    private var summaryStatsCard: some View {
        let total = lifeStore.subordinates.count
        let avg = averageScore
        let excellent = excellentCount
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
                               value: "\(lifeStore.subordinates.filter { subordinateScore($0) < 70 }.count) 位",
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
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.10, green: 0.35, blue: 0.82).opacity(0.42), radius: 16, x: 0, y: 8)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    emptyIconPulse = true
                }
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

    private func subordinateRow(_ sub: Subordinate) -> some View {
        let score = subordinateScore(sub)
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
                    } else if !sub.jobTitle.isEmpty {
                        Text(sub.jobTitle)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 7).padding(.vertical, 2.5)
                            .background(accent.opacity(0.12))
                            .clipShape(Capsule())
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
                            .lineLimit(1)
                    }
                }

                // 到職日 / 年資
                if let jd = sub.joinDate {
                    HStack(spacing: 3) {
                        Image(systemName: "calendar")
                            .font(.system(size: 9, weight: .medium))
                        Text("到職 \(formatDate(jd))")
                            .font(.caption2)
                    }
                    .foregroundStyle(.tertiary)
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

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: date)
    }

    /// 自動評分：基礎 80，依記錄加減，範圍 0~100
    private func subordinateScore(_ sub: Subordinate) -> Int {
        var score: Double = 80
        for rec in sub.records {
            switch rec.type {
            case .pro:           score += 2
            case .con:           score -= 2
            case .achievement:   score += 3
            case .improvement:   score += 1
            case .fault:         score -= 3
            case .missOperation:
                switch rec.severity {
                case .minor:  score -= 1
                case .normal: score -= 2
                case .severe: score -= 4
                case .none:   score -= 2
                }
            case .leave:
                let hours = rec.leaveHours ?? 8
                score -= hours / 16
            }
        }
        return max(0, min(100, Int(score.rounded())))
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
            tasks: editing?.tasks ?? []
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
        if let jd = e.joinDate {
            hasJoinDate = true
            joinDate = jd
        }
    }
}
