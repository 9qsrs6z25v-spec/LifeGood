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
// [2026-07 v3] 補齊「部門篩選後零筆」次要空狀態缺口：
//   5. subordinateSections 篩選後 filtered.isEmpty 分支原本是裸 Text("此部門尚無部屬")，
//      未包圖示錨點，與同檔案 emptyStateView（頁面首次無部屬資料時的雙層脈衝光環大型空
//      狀態）及全 App 其餘「篩選後零筆」次要空狀態（ResumeView.categoryEmptyState／
//      FoodMapView.restaurantListEmptyState）不一致，兩種空狀態呈現落差明顯。新增
//      filteredEmptyState：56pt 藍色圖示圓（person.2.slash + emptyStateView 同款
//      accent 藍）+ 說明文字，對齊 ResumeView.categoryEmptyState 規格（次要篩選態僅用
//      輕量卡片，不做全頁大型脈衝動畫，該規格保留給頁面首次無資料的 emptyStateView）。
//      純視覺層調整，部門篩選邏輯、部屬資料來源等既有商業邏輯完全未變動。
// [2026-07 v4] 補齊「新增/編輯部屬」表單 Section header：
//   6. AddSubordinateView 是本檔案唯一仍在用系統預設純文字 Section 標頭
//      （Section("基本資訊")／Section("備註") 共 2 處）的地方，與同檔案列表
//      activeSubordinatesSectionHeader、全 App 其餘新增/編輯表單（OrganizationView.
//      orgPersonEditorSectionHeader／ChildDetailView.childEditorSectionHeader）早已升級
//      的「4pt 漸層 Capsule 側條 + 圖示 + 粗體標題」規格脫節。新增共用
//      subordinateEditorSectionHeader(_:icon:color:)，基本資訊＝indigo（沿用全 App
//      「基本資訊」慣例色）／備註＝secondary。純視覺層調整，欄位資料綁定、
//      canSave()／save() 等既有商業邏輯完全未變動。
// [2026-08 v5] 補齊 summaryStatsCard 英雄卡大字自適應收尾：
//   7. 頂部「部屬總覽」28pt「N 位部屬」大字原本沒有 lineLimit／minimumScaleFactor
//      防截斷保護，是本卡片唯一缺這道防護的數字——下方三格 summaryKpiCell（平均評分／
//      優秀／待提升）早已有 .lineLimit(1).minimumScaleFactor(0.7)。補上
//      .lineLimit(1) + .minimumScaleFactor(0.6)，對齊 VehicleView v25.49／
//      FinanceOverviewView v25.51／SavingsInsuranceView v25.54 等同系列「英雄卡大字
//      自適應收尾」規格，讓部屬人數字串在大團隊、超長排序膠囊擠壓卡片寬度時自動縮字
//      而不被系統裁切，同時維持在可辨識最小字級以上。純視覺層調整，total／avg／
//      excellent／needImprovement 等既有統計計算完全未變動。
//      （下次美化本檔案時：可留意 subordinateRow 是否仍有其他可與全 App 均值對齊之處，
//      或轉往其他仍留有待辦的畫面）
// [2026-08 v6] 補齊「新增/編輯部屬」工具列儲存按鈕載入狀態：
//   8. AddSubordinateView.save() 自帶 isSaving 忙碌守衛（disabled(isSaving)）避免快速連點
//      造成重複部屬紀錄，但按鈕本身在存檔期間毫無視覺提示。補上 ProgressView()
//      .scaleEffect(0.7).tint(.green)，isSaving 為 true 時顯示於按鈕左側，對齊
//      v25.81～v25.93 AddSavingsInsuranceView／AddExpenseView／AddIncomeView／
//      AddVehicleView／AddStockView／AddRealEstateView／SubordinateEquipmentView／
//      FamilyMembersResumeView 儲存按鈕載入狀態規格。純視覺層調整，save() 內部守衛
//      判斷與部屬資料寫入等既有商業邏輯完全未變動。
//      （下次美化時：同批清單仍剩 OrganizationView／SubordinateDetailView／
//      MyCalendarView／LifeFinanceView／ResumeView／ChildDetailView 待比照補齊
//      ——GradeTitleView 已於 v25.95 補齊，可挑剩餘其一接續）

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
    /// [v25.587 轉組織 v0a①] 往左滑〔刪除〕先問一次：要刪的那一位（nil＝沒有在問）
    @State private var pendingDelete: Subordinate?
    /// [v25.592 轉組織 v1b] 名單長按〔轉組織…〕開的精靈（judge §4.1；開始精靈要訂閱）。
    /// 要退回這一件：刪這一行、listRow 的 .contextMenu、personMenu／openOrgMove／openEdit、body 的 .sheet(item: $orgMoveWizard)
    @State private var orgMoveWizard: OrgMoveWizardRequest?
    /// [v25.593 轉組織 v2] 名單最下面「已轉出（N）」展開了沒（預設收起；judge §4.8）。要退回這一件：刪這一行與 archivedSection
    @State private var archivedOpen = false
    /// [v25.593 轉組織 v2] 往左滑〔刪除〕在職的人先問三選一「王小明是轉走了嗎？」（judge §3.6、③-C2）：問的是哪一位。
    /// 跟 pendingDelete 分開（兩個框不能掛同一個 state）。要退回這一件：刪這一行、滑出按鈕改回 pendingDelete = s、body 的第二個 .alert
    @State private var deleteChoiceFor: Subordinate?
    @AppStorage("subordinateSortOption") private var sortOptionRaw = SubordinateSortOption.dateAdded.rawValue
    @AppStorage("subordinateSortAscending") private var sortAscending = false
    @AppStorage("subordinateFilterDeptRaw") private var filterDeptRaw = ""   // 舊版單選（保留供遷移）
    /// [v25.298] 部門篩選改多選：逗號串接的部門 id；"" = 全部部門
    @AppStorage("subordinateFilterDeptsRaw") private var filterDeptsRaw = ""

    /// 目前勾選的部門集合（空＝全部部門）。新 key 沒值時沿用舊版單選設定。
    private var selectedDeptIds: Set<UUID> {
        let ids = filterDeptsRaw.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
        if !ids.isEmpty { return Set(ids) }
        if !filterDeptRaw.isEmpty, let legacy = UUID(uuidString: filterDeptRaw) { return [legacy] }
        return []
    }

    private func setSelectedDeptIds(_ ids: Set<UUID>) {
        filterDeptsRaw = ids.map(\.uuidString).sorted().joined(separator: ",")
        filterDeptRaw = ""   // 舊 key 清空，之後只認新 key
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
        // [v25.593 轉組織 v2] 名單上面只列在職的；已轉出的收在最下面「已轉出（N）」（archivedSection）。
        // 要退回這一件：改回 lifeStore.subordinates
        let list = lifeStore.activeSubordinates
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

    /// 套用部門篩選後的清單（保留排序；多選＝任一勾選部門即入列）
    private var filteredSubordinates: [Subordinate] {
        let ids = selectedDeptIds
        guard !ids.isEmpty else { return sortedSubordinates }
        return sortedSubordinates.filter { $0.departmentId.map(ids.contains) ?? false }
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
    private func subordinateSections(ctx: LifeStore.ScoreContext) -> some View {
        // filteredSubordinates／displayRows 各自是 filter/O(n log n) 排序，一次算好供本
        // section 的空狀態檢查、計數徽章、ForEach 共用，避免同一次 body 求值各自重跑三次。
        let filtered = filteredSubordinates
        let rows = displayRows(filtered)
        // [v25.593 轉組織 v2] 最下面「已轉出（N）」那幾列（交接單算的；新的在前；不套部門篩選）。一次算好給 archivedSection
        let archived = archivedListRows()
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
                filteredEmptyState
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        } else {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                listRow(row, idx: idx, ctx: ctx)
                    // 改用 allowsFullSwipe: false 的滑出按鈕取代 .onDelete：
                    // 避免整列滑到底直接刪除（與邊緣切頁手勢衝突，同型修正見 v25.154）
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if case .person(let s) = row {
                            // [v25.587 轉組織 v0a①] 先問，不直接刪（付費檢查照舊在前面）。
                            // 不用 role: .destructive：有確認框時，帶 destructive 的列一按就先被 List 滑掉，
                            // 按〔取消〕也回不來（坑 #12，同 ResumeView v25.562／RealEstateView v25.530）；改紅色 tint，按鈕看起來一樣。
                            // （要退回這一件：改回 Button(role: .destructive) { …; lifeStore.deleteSubordinate(s) }、拿掉 .tint。）
                            // [v25.593 轉組織 v2] 先問三選一「王小明是轉走了嗎？」〔轉組織…〕〔真的刪除〕〔取消〕（deleteChoiceFor）；
                            // 〔真的刪除〕才走原本的刪除確認框（pendingDelete）。要退回這一件：deleteChoiceFor 改回 pendingDelete
                            Button {
                                guard subscription.isPremium else { showPremiumAlert = true; return }
                                deleteChoiceFor = s
                            } label: {
                                Label("刪除", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
            }
            .onMove { from, to in
                guard subscription.isPremium else { showPremiumAlert = true; return }
                // 僅在「手動排序 + 全部部門」的平面清單下允許拖曳，offset 才與底層陣列一致
                guard sortOption == .manual, selectedDeptIds.isEmpty else { return }
                // [v25.593 轉組織 v2] 畫面上只有在職的：照 id 換算，已轉出的人留在陣列原本的位置（judge §4.8 ⚠️）。
                // filtered 在手動排序＋全部部門時就是在職的那份順序。要退回這一件：改回 lifeStore.subordinates.move(fromOffsets: from, toOffset: to)
                lifeStore.moveActiveSubordinates(visibleIds: filtered.map(\.id), fromOffsets: from, toOffset: to)
            }
        }

        // [v25.593 轉組織 v2] 名單最下面「已轉出（N）」（收起來；沒有就不出現）。要退回這一件：刪這一行與 archived 那一行
        archivedSection(archived)
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
    private func listRow(_ row: ListRow, idx: Int, ctx: LifeStore.ScoreContext) -> some View {
        switch row {
        case .header(let area):
            plantAreaHeader(area)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 2, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        case .person(let sub):
            subordinateRow(sub, ctx: ctx)
                .contentShape(Rectangle())
                .onTapGesture { viewingItem = sub }
                // [v25.592 轉組織 v1b] 長按：〔轉組織…〕〔編輯〕（judge §4.1）
                .contextMenu { personMenu(sub) }
                .opacity(rowsAppeared ? 1 : 0)
                .offset(y: rowsAppeared ? 0 : 14)
                .animation(
                    .spring(response: 0.45, dampingFraction: 0.82).delay(0.05 * Double(min(idx, 12))),
                    value: rowsAppeared
                )
        }
    }

    var body: some View {
        // 一次計算評分所需的整批資料（被標註計數 + 兼任待辦統計，皆為全量掃描），
        // 供頂部統計卡與每一列共用，避免各自重複觸發全量重算。
        let ctx = lifeStore.makeScoreContext()
        return NavigationStack {
            List {
                // 頂部統計摘要卡（有部屬才顯示）
                if !lifeStore.subordinates.isEmpty {
                    Section {
                        summaryStatsCard(ctx: ctx)
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
                    subordinateSections(ctx: ctx)
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
                // 勾選中的部門被刪除時，從篩選集合剔除（全刪光＝回復「全部部門」）
                let alive = selectedDeptIds.filter { ids.contains($0) }
                if alive != selectedDeptIds { setSelectedDeptIds(alive) }
            }
            .sheet(isPresented: $showAdd) { AddSubordinateView().appStores() }
            .sheet(item: $editingItem) { item in AddSubordinateView(editing: item).appStores() }
            // [v25.592 轉組織 v1b] 名單長按〔轉組織…〕（要退回這一件：刪這一行）
            .sheet(item: $orgMoveWizard) { r in OrgMoveWizard(personId: r.personId, presetDeptId: r.presetDeptId).appStores() }
            .sheet(item: $viewingItem) { item in SubordinateDetailView(subordinate: item).appStores() }
            .sheet(isPresented: $showRoster) { SubordinateRosterView().appStores() }
            .sheet(isPresented: $showTalentMatrix) { TalentMatrixView().appStores() }
            .premiumLockAlert(isPresented: $showPremiumAlert)
        }
        // [v25.587 轉組織 v0a①] 刪除確認框掛在 NavigationStack 外面（List 上已經有付費說明，同一個 view 不掛兩個 alert）
        .alert(deleteAskTitle, isPresented: deleteAskShown, presenting: pendingDelete) { s in
            Button("刪除", role: .destructive) { confirmDelete(s) }
            Button("取消", role: .cancel) { }
        } message: { s in
            // [v25.593 轉組織 v2] 前面多「王小明身上還有 3 件沒交出去。」（有才接；deleteConfirmMessage）。
            // 要退回這一件：改回 Text(lifeStore.subordinateDeleteConfirm(s).message)
            Text(deleteConfirmMessage(s))
        }
        // [v25.593 轉組織 v2] 往左滑〔刪除〕先問三選一「王小明是轉走了嗎？」（judge §3.6、③-C2；字在 OrgMovePlan.deleteChoice）。
        // 跟上面那一框分開兩個 state；〔真的刪除〕等這一框收完（0.35 秒）才跳上面那一框。要退回這一件：刪這一個 .alert
        .alert(deleteChoiceTitle, isPresented: deleteChoiceShown, presenting: deleteChoiceFor) { s in
            Button("轉組織…") { chooseOrgMove(s) }
            Button("真的刪除", role: .destructive) { chooseHardDelete(s) }
            Button("取消", role: .cancel) { }
        } message: { s in
            Text(deleteChoiceMessage(s))
        }
    }

    // MARK: - [v25.587 轉組織 v0a①] 刪除確認框（字在 LifeStore.subordinateDeleteConfirm）
    // （要退回這一件：滑出按鈕改回直接 lifeStore.deleteSubordinate(s)，刪掉 pendingDelete、這三支和 body 後面的 .alert。）

    private var deleteAskShown: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var deleteAskTitle: String {
        guard let s = pendingDelete else { return "" }
        return lifeStore.subordinateDeleteConfirm(s).title
    }

    /// 確認框收起之後（下一個 runloop）才刪；用 store 裡現在那一筆（問的期間又加了任務、提醒事項也刪得到）。
    /// 問的期間人已經被刪了（另一台、iCloud 拉下來）就什麼都不做。
    private func confirmDelete(_ s: Subordinate) {
        pendingDelete = nil
        let id = s.id
        DispatchQueue.main.async {
            guard let fresh = lifeStore.subordinates.first(where: { $0.id == id }) else { return }
            lifeStore.deleteSubordinate(fresh)
        }
    }

    /// [v25.593 轉組織 v2] 刪除確認框的內文：身上還有沒交出去的，前面多一句「王小明身上還有 3 件沒交出去。」
    ///（只提醒不擋；沒有就跟以前一字不差。在職的〔真的刪除〕、已轉出那一區的往左滑都走這一框）
    private func deleteConfirmMessage(_ s: Subordinate) -> String {
        let base = lifeStore.subordinateDeleteConfirm(s).message
        guard let note = OrgMovePlan.deleteOpenNote(personId: s.id, world: OrgMoveWorld(store: lifeStore)) else {
            return base
        }
        return note + "\n" + base
    }

    // MARK: - [v25.593 轉組織 v2] 往左滑〔刪除〕三選一（judge §3.6、③-C2；字在 OrgMovePlan.deleteChoice）
    // 〔轉組織…〕開精靈（照舊要訂閱）；〔真的刪除〕再跳原本的刪除確認框；〔取消〕不刪。
    // （要退回這一件：滑出按鈕改回 pendingDelete = s，刪 deleteChoiceFor、這四支與 body 的第二個 .alert。）

    private var deleteChoiceShown: Binding<Bool> {
        Binding(get: { deleteChoiceFor != nil }, set: { if !$0 { deleteChoiceFor = nil } })
    }

    private var deleteChoiceTitle: String {
        guard let s = deleteChoiceFor else { return "" }
        return OrgMovePlan.deleteChoice(personId: s.id, world: OrgMoveWorld(store: lifeStore)).title
    }

    private func deleteChoiceMessage(_ s: Subordinate) -> String {
        OrgMovePlan.deleteChoice(personId: s.id, world: OrgMoveWorld(store: lifeStore)).message
    }

    /// 〔轉組織…〕：框收起之後（下一個 runloop）才開精靈（訂閱在 openOrgMove 裡照舊看）
    private func chooseOrgMove(_ s: Subordinate) {
        deleteChoiceFor = nil
        let id = s.id
        DispatchQueue.main.async { openOrgMove(id) }
    }

    /// 〔真的刪除〕：框收起來之後才跳原本的刪除確認框（pendingDelete；兩個框不同時開）。
    /// 等 0.35 秒不是只等下一個 runloop：框還在收的那一刻疊第二個框，iOS 會把第二個吃掉（同 WealthEditors.confirmBankDelete）。
    /// 問的期間人已經被刪了（另一台、iCloud 拉下來）就不跳
    private func chooseHardDelete(_ s: Subordinate) {
        deleteChoiceFor = nil
        let id = s.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let fresh = lifeStore.subordinates.first(where: { $0.id == id }) else { return }
            pendingDelete = fresh
        }
    }

    // MARK: - [v25.593 轉組織 v2] 名單最下面「已轉出（N）」（judge §3.6、§4.8、③-B6）
    // 收起來的一區（預設收起）：點標題列展開／收起；每列灰字名字＋右邊「11/1 轉到品保課」；點了開卡片（同在職那列 viewingItem）；
    // 往左滑〔刪除〕直接走原本的刪除確認框（已經轉出了，不再問三選一）。不套部門篩選、不給拖曳、不給長按〔轉組織…〕。
    // （要退回這一件：刪 archivedOpen、這六支、subordinateSections 裡 archived 那兩行、檔尾兩個 SubArchivedList… struct。）

    /// 已轉出的那幾列（新的在前；OrgMovePlan.archivedRows）。沒有已轉出的人就不建 OrgMoveWorld
    private func archivedListRows() -> [OrgMoveArchivedRow] {
        guard !OrgMoveIndex.archived.isEmpty else { return [] }
        return OrgMovePlan.archivedRows(world: OrgMoveWorld(store: lifeStore))
    }

    @ViewBuilder
    private func archivedSection(_ rows: [OrgMoveArchivedRow]) -> some View {
        if !rows.isEmpty {
            Section {
                archivedHeader(count: rows.count)
                if archivedOpen {
                    ForEach(rows) { r in
                        archivedRow(r)
                    }
                }
            }
        }
    }

    /// 標題列「已轉出（1）▸」：整列點了展開／收起（用點擊手勢：手動排序時 List 在編輯模式，Button 點不到）
    private func archivedHeader(count: Int) -> some View {
        SubArchivedListHeader(count: count, open: archivedOpen)
            .contentShape(Rectangle())
            .onTapGesture { toggleArchived() }
    }

    /// 一列：點了開卡片；往左滑〔刪除〕（同在職那列：不用 role: .destructive，坑 #12，改紅色 tint）
    private func archivedRow(_ r: OrgMoveArchivedRow) -> some View {
        SubArchivedListRow(row: r)
            .contentShape(Rectangle())
            .onTapGesture { openArchived(r.personId) }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    deleteArchived(r.personId)
                } label: {
                    Label("刪除", systemImage: "trash")
                }
                .tint(.red)
            }
    }

    private func toggleArchived() {
        withAnimation(.easeInOut(duration: 0.2)) {
            archivedOpen.toggle()
        }
    }

    /// 打開已轉出那位的卡片（唯讀感在卡片裡；看卡片不用訂閱，同在職那列）
    private func openArchived(_ id: UUID) {
        guard let s = lifeStore.subordinates.first(where: { $0.id == id }) else { return }
        viewingItem = s
    }

    /// 已轉出那一區往左滑〔刪除〕：要訂閱；直接跳原本的刪除確認框（不再問三選一）
    private func deleteArchived(_ id: UUID) {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        guard let s = lifeStore.subordinates.first(where: { $0.id == id }) else { return }
        pendingDelete = s
    }

    // MARK: - [v25.592 轉組織 v1b] 名單長按：〔轉組織…〕〔編輯〕（judge §4.1、§4.8）
    // 兩顆都要訂閱（同部屬卡片「…」的〔編輯〕〔轉組織〕）；這位已經有一張排好的，精靈自己會先問〔打開那張〕〔取消那張、重排〕。
    // （要退回這一件：刪這三支、listRow 的 .contextMenu、orgMoveWizard 與 body 的 .sheet(item: $orgMoveWizard)。）

    @ViewBuilder
    private func personMenu(_ sub: Subordinate) -> some View {
        Button { openOrgMove(sub.id) } label: {
            Label("轉組織…", systemImage: "arrow.left.arrow.right.circle.fill")
        }
        Button { openEdit(sub) } label: {
            Label("編輯", systemImage: "square.and.pencil")
        }
    }

    private func openOrgMove(_ id: UUID) {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        orgMoveWizard = OrgMoveWizardRequest(personId: id)
    }

    private func openEdit(_ sub: Subordinate) {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        editingItem = sub
    }

    // MARK: - 統計摘要卡


    private func summaryStatsCard(ctx: LifeStore.ScoreContext) -> some View {
        // [v25.593 轉組織 v2] 人數、平均、優秀、待提升只算在職的（已轉出的不算進團隊）。要退回這一件：改回 lifeStore.subordinates
        let subordinates = lifeStore.activeSubordinates
        let scores = subordinates.map { subordinateScore($0, ctx: ctx) }
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
                        .heroBigValueFont()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
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
                HeroKpiCell(label: "平均評分", value: "\(avg)",
                               icon: "chart.bar.fill")
                HeroKpiDivider()
                HeroKpiCell(label: "優秀（90+）", value: "\(excellent) 位",
                               icon: "star.fill")
                HeroKpiDivider()
                HeroKpiCell(label: "待提升（<70）",
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
        .heroCardShell(card: .subordinateList)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    // MARK: - 部屬列表 sectionHeader [2026-06 v2]

    // MARK: - 部門篩選列 / 廠區分組標題

    /// [v25.298] 部門篩選改為下拉選單＋可多選：勾選期間選單不收合（一次勾好幾個），
    /// 「全部部門」一鍵清空。選擇摘要顯示在按鈕上。
    private var departmentFilterBar: some View {
        Menu {
            Button {
                setSelectedDeptIds([])
            } label: {
                if selectedDeptIds.isEmpty {
                    Label("全部部門", systemImage: "checkmark")
                } else {
                    Text("全部部門")
                }
            }
            Divider()
            ForEach(lifeStore.departments) { dept in
                Toggle(deptLabel(dept), isOn: deptToggleBinding(dept.id))
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selectedDeptIds.isEmpty ? Color.secondary : Color.blue)
                Text(deptFilterSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selectedDeptIds.isEmpty ? Color.primary : Color.blue)
                    .lineLimit(1)
                if !selectedDeptIds.isEmpty {
                    Text("\(selectedDeptIds.count)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 1.5)
                        .background(Color.blue.opacity(0.14))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(selectedDeptIds.isEmpty ? Color(.separator).opacity(0.3) : Color.blue.opacity(0.35),
                        lineWidth: 0.75))
            .contentShape(Rectangle())
        }
        .menuActionDismissBehavior(.disabled)
    }

    /// 單一部門的勾選 Binding（供 Menu 內 Toggle 使用）
    private func deptToggleBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedDeptIds.contains(id) },
            set: { on in
                var ids = selectedDeptIds
                if on { ids.insert(id) } else { ids.remove(id) }
                setSelectedDeptIds(ids)
            }
        )
    }

    /// 下拉按鈕上的選擇摘要：全部部門／部門名（最多列 2 個，其餘以「等 N 個部門」帶過）
    private var deptFilterSummary: String {
        let ids = selectedDeptIds
        guard !ids.isEmpty else { return "全部部門" }
        let names = lifeStore.departments
            .filter { ids.contains($0.id) }
            .map { deptLabel($0) }
        if names.count <= 2 { return names.joined(separator: "、") }
        return "\(names.prefix(2).joined(separator: "、")) 等 \(names.count) 個部門"
    }

    /// 廠區分組標題列（對齊部屬班表的廠區分段樣式）
    private func plantAreaHeader(_ area: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "building.2.fill").font(.system(size: 10, weight: .semibold))
            MarqueeText(area).font(.system(size: 12, weight: .bold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.blue)
    }

    private func activeSubordinatesSectionHeader(count: Int) -> some View {
        let accent = Color(red: 0.22, green: 0.53, blue: 0.98)
        let title = selectedDeptIds.isEmpty ? "部屬成員" : deptFilterSummary
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
            MarqueeText(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
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

    /// [v3] 部門篩選後零筆時的次要空狀態：輕量圖示＋文字卡片，對齊 ResumeView
    /// .categoryEmptyState 規格（篩選態不做全頁雙層脈衝光環，僅頁面首次無資料的
    /// emptyStateView 才用大型脈衝設計），取代原本裸露 Text 造成的視覺缺口。
    /// [v25.593 轉組織 v2] 篩選後零筆那一句（有篩部門照舊「此部門尚無部屬」）
    private var filteredEmptyText: String {
        selectedDeptIds.isEmpty ? "目前沒有在職的部屬" : "此部門尚無部屬"
    }

    private var filteredEmptyState: some View {
        let accent = Color(red: 0.22, green: 0.53, blue: 0.98)
        return VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 56, height: 56)
                    .overlay(Circle().stroke(accent.opacity(0.20), lineWidth: 1))
                Image(systemName: "person.2.slash")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(accent.opacity(0.75))
            }
            // [v25.593 轉組織 v2] 沒有篩部門、在職的都轉出了（只剩最下面「已轉出」）時寫「目前沒有在職的部屬」。
            // 要退回這一件：改回 Text("此部門尚無部屬")
            Text(filteredEmptyText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: - 部屬列

    private func subordinateRow(_ sub: Subordinate, ctx: LifeStore.ScoreContext) -> some View {
        let score = subordinateScore(sub, ctx: ctx)
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
                // [v25.549] 名字後面接年資（同部屬卡片看板）：「黃義超，3.2年資歷」
                MarqueeText(SubordinateDetailView.nameWithSeniority(sub.name, joinDate: sub.joinDate))
                    .font(.subheadline.weight(.semibold))

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

                    // [v25.592 轉組織 v1b] 排好、部門還沒改：「11/1 起 設備課」（judge §4.8）
                    plannedCapsule(sub.id)
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

    /// [v25.592 轉組織 v1b] 排好、部門還沒改的那位：部門膠囊後面一顆藍色小膠囊「11/1 起 設備課」
    ///（只換廠區「11/1 起 P2」、部門照舊「11/1 交接」；字在 OrgMovePlan.plannedCapsuleText 組好；judge §4.8）。
    /// 只在 App 內名單；小工具、通知、手錶一個字都沒有。要退回這一件：刪這一支與 subordinateRow 裡叫它的那一行。
    @ViewBuilder
    private func plannedCapsule(_ id: UUID) -> some View {
        if let text = OrgMovePlan.plannedCapsuleText(personId: id) {
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.blue)
                .padding(.horizontal, 6).padding(.vertical, 2.5)
                .background(Color.blue.opacity(0.12))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.blue.opacity(0.24), lineWidth: 0.6))
                .lineLimit(1)
                .layoutPriority(1)
        }
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
    /// ctx 由呼叫端（body）以 lifeStore.makeScoreContext() 算好一次傳入，
    /// 避免每一列各自重新全量掃描所有部屬的任務/會議/報告與兼任待辦。
    private func subordinateScore(_ sub: Subordinate, ctx: LifeStore.ScoreContext) -> Int {
        sub.overallScore(mentionedCount: ctx.mention(sub.id),
                         sideRoleDone: ctx.sideRoleDone(sub.id),
                         itemDone: ctx.itemDone(sub.id))
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

// MARK: - [v25.593 轉組織 v2] 名單最下面「已轉出（N）」的標題列與一列（judge §4.8、③-B6；字在 OrgMovePlan.archivedRows 組好）
// 只在 App 內名單；小工具、通知、手錶一個字都沒有。要退回這一件：刪這兩個 struct 與 SubordinateView 的 archivedSection 那幾支

/// 「已轉出（1）▸」：灰側條、灰字粗體、右邊箭頭（展開轉成朝下）
private struct SubArchivedListHeader: View {
    let count: Int
    let open: Bool

    private var hint: String { open ? "收起已轉出的部屬" : "展開已轉出的部屬" }

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(Color.gray.opacity(0.45))
                .frame(width: 4, height: 16)
            Text("已轉出（\(count)）")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.secondary)
                .rotationEffect(.degrees(open ? 90 : 0))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(hint))
    }
}

/// 一列：灰字「王小明」＋右邊灰字「11/1 轉到品保課」＋箭頭（點了開卡片）
private struct SubArchivedListRow: View {
    let row: OrgMoveArchivedRow

    var body: some View {
        HStack(spacing: 10) {
            Text(row.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(row.detail)
                .font(.caption)
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 新增/編輯部屬

// [2026-07 v4] Section header：對齊 OrganizationView.orgPersonEditorSectionHeader／
// ChildDetailView.childEditorSectionHeader 既有共用寫法（4pt 漸層 Capsule 側條 + 圖示 +
// .subheadline.semibold 標題）。
private func subordinateEditorSectionHeader(_ title: String, icon: String, color: Color) -> some View {
    HStack(spacing: 7) {
        Capsule()
            .fill(LinearGradient(colors: [color, color.opacity(0.70)], startPoint: .top, endPoint: .bottom))
            .frame(width: 4, height: 18)
        Image(systemName: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
    }
}

struct AddSubordinateView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    var editing: Subordinate?

    @State private var name = ""
    @State private var hasJoinDate = false
    @State private var joinDate = Date()
    @State private var hasBirthday = false
    @State private var birthday = Date()
    @State private var selectedGradeTitleId: UUID?
    @State private var selectedDepartmentId: UUID?
    @State private var department = ""
    @State private var note = ""
    @State private var hasPlantArea = false
    @State private var plantArea = ""
    @State private var isSaving = false
    /// [v25.587 轉組織 v0a⑥] 打開那一刻表單上的值（loadEditing 填好時記下）；存檔時跟它比，只寫真的改過的欄位
    @State private var opened: FormValues?

    /// [v25.587 轉組織 v0a⑥] 表單上的欄位（loadEditing 填的、save 讀的就是這幾個）
    private struct FormValues: Equatable {
        var name: String
        var hasJoinDate: Bool
        var joinDate: Date
        var hasBirthday: Bool
        var birthday: Date
        var gradeTitleId: UUID?
        var departmentId: UUID?
        var department: String
        var note: String
        var hasPlantArea: Bool
        var plantArea: String
    }

    private var formValues: FormValues {
        FormValues(name: name, hasJoinDate: hasJoinDate, joinDate: joinDate,
                   hasBirthday: hasBirthday, birthday: birthday,
                   gradeTitleId: selectedGradeTitleId, departmentId: selectedDepartmentId,
                   department: department, note: note,
                   hasPlantArea: hasPlantArea, plantArea: plantArea)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("姓名", text: $name)
                    Toggle("填入入職日期", isOn: $hasJoinDate)
                    if hasJoinDate {
                        DatePicker("入職日期", selection: $joinDate, displayedComponents: .date)
                    }
                    Toggle("填入生日", isOn: $hasBirthday)
                    if hasBirthday {
                        DatePicker("生日", selection: $birthday, displayedComponents: .date)
                        HStack {
                            Text("星座").foregroundStyle(.secondary)
                            Spacer()
                            Text(zodiacSign(for: birthday))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.purple)
                        }
                    }
                    gradeTitlePicker
                    departmentPicker
                    plantAreaField
                } header: {
                    subordinateEditorSectionHeader("基本資訊", icon: "person.fill", color: .indigo)
                }
                Section {
                    TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
                } header: {
                    subordinateEditorSectionHeader("備註", icon: "text.bubble.fill", color: .secondary)
                }
            }
            .navigationTitle(editing != nil ? "編輯部屬" : "新增部屬")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    // [美化] 存檔中顯示同色 ProgressView，對齊 FamilyMembersResumeView v25.93／
                    // SubordinateEquipmentView v25.92 等 isSaving 忙碌守衛按鈕載入狀態規格。
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView().scaleEffect(0.7).tint(.green)
                        }
                        Button(editing != nil ? "儲存" : "新增") { save() }
                            .bold().foregroundStyle(.green)
                            .disabled(!canSave || isSaving)
                    }
                }
            }
            .onAppear { loadEditing() }
        }
        // [v25.592 轉組織 v1b] 編輯頁開著時告訴 OrgMoveDueCenter（開著就不自動改部門，關了再看；brief §1-4 ③）。要退回這一件：刪這一行
        .orgMoveEditorPresence()
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
        guard !isSaving else { return }
        isSaving = true
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

        // [v25.587 轉組織 v0a⑥] 編輯既有部屬：只把改過的欄位寫到 store 裡現在那一筆（saveEdits）。新增照舊整筆建。
        // （要退回這一件：刪掉這個 if，回到整筆重建。）
        if let e = editing {
            saveEdits(id: e.id, linkedTitle: linkedTitle, deptText: deptText)
            dismiss()
            return
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
            equipments: editing?.equipments ?? [],
            // 升職歷程原本漏帶——編輯基本資料就會被空陣列洗掉（潛在 bug，本次補上）
            promotions: editing?.promotions ?? [],
            birthday: hasBirthday ? birthday : nil,
            // 生日提醒事件對應也要帶回，否則存個檔就會重複建立提醒
            birthdayEventId: editing?.birthdayEventId
        )
        if editing != nil { lifeStore.update(item) } else { lifeStore.add(item) }
        dismiss()
    }

    /// [v25.587 轉組織 v0a⑥] 跟打開那一刻（opened）比，只寫改過的欄位；任務、會議、班、週報、紀錄、升職歷程、
    /// 執掌設備、生日提醒事件一律用 store 現在的（不從表單帶回）——不然開著的編輯頁一存，就用打開那一刻的快照
    /// 把手錶剛打的勾、另一台剛搬走的任務、剛改好的部門整包蓋回去。什麼都沒改就不寫；開著的時候人被刪了不加回來。
    /// （要退回這一件：刪掉 save() 裡呼叫這支的 if；這支、opened、FormValues 可以留著不用。）
    private func saveEdits(id: UUID, linkedTitle: String, deptText: String) {
        guard let o = opened, var item = lifeStore.subordinates.first(where: { $0.id == id }) else { return }
        let cur = formValues
        var changed = false
        if cur.name != o.name {
            item.name = name.trimmingCharacters(in: .whitespaces)
            changed = true
        }
        if cur.hasJoinDate != o.hasJoinDate || (cur.hasJoinDate && cur.joinDate != o.joinDate) {
            item.joinDate = hasJoinDate ? joinDate : nil
            changed = true
        }
        if cur.hasBirthday != o.hasBirthday || (cur.hasBirthday && cur.birthday != o.birthday) {
            item.birthday = hasBirthday ? birthday : nil
            changed = true
        }
        // 職等那一欄有改才重寫 jobTitle 字樣（原本每存一次都照職等重組；畫面先查 gradeTitleId，看不出差別）
        if cur.gradeTitleId != o.gradeTitleId {
            item.gradeTitleId = selectedGradeTitleId
            item.jobTitle = linkedTitle
            changed = true
        }
        // [v25.589 轉組織 v0b④] 部門改走 lifeStore.setDepartment（同組織頁那條路：字樣統一「代碼 — 名稱」、組織人員跟著
        // 但「未選擇」不蓋成空的、自動產生的名片部門一起換）；這裡只記下有沒有改，其他欄位照舊 update。
        // （要退回這一件：換回原本這四行
        //   if cur.departmentId != o.departmentId || cur.department != o.department {
        //       item.departmentId = selectedDepartmentId; item.department = deptText; changed = true }
        //  ，拿掉下面 if deptEdited 那一行。）
        let deptEdited = cur.departmentId != o.departmentId || cur.department != o.department
        if cur.note != o.note {
            item.note = note.trimmingCharacters(in: .whitespaces)
            changed = true
        }
        if cur.hasPlantArea != o.hasPlantArea || (cur.hasPlantArea && cur.plantArea != o.plantArea) {
            item.plantArea = hasPlantArea ? plantArea.trimmingCharacters(in: .whitespaces) : ""
            changed = true
        }
        if changed { lifeStore.update(item) }
        // [v25.589 轉組織 v0b④] 順序：先 update（別的欄位；這時 item 的部門還是 store 現在的，組織人員不會被改）、
        // 再 setDepartment（倒過來的話 update 會用舊部門把剛換好的蓋回去）。兩次存檔，各自是完整的狀態。
        if deptEdited { lifeStore.setDepartment(id, to: selectedDepartmentId, freeText: deptText) }
    }

    private func loadEditing() {
        // [v25.587 轉組織 v0a⑥] 只填一次（onAppear 再跑時不把你剛改的欄位蓋回去）；
        // 用 store 裡現在那一筆填（找不到才用傳進來的），填進去的值記成 opened。
        // （要退回這一件：改回直接用 editing 填、不記 opened。）
        guard let e = editing, opened == nil else { return }
        let base = lifeStore.subordinates.first(where: { $0.id == e.id }) ?? e
        let values = FormValues(
            name: base.name,
            hasJoinDate: base.joinDate != nil, joinDate: base.joinDate ?? joinDate,
            hasBirthday: base.birthday != nil, birthday: base.birthday ?? birthday,
            gradeTitleId: base.gradeTitleId, departmentId: base.departmentId,
            department: base.department, note: base.note,
            hasPlantArea: !base.plantArea.isEmpty, plantArea: base.plantArea)
        name = values.name
        hasJoinDate = values.hasJoinDate
        joinDate = values.joinDate
        hasBirthday = values.hasBirthday
        birthday = values.birthday
        selectedGradeTitleId = values.gradeTitleId
        selectedDepartmentId = values.departmentId
        department = values.department
        note = values.note
        hasPlantArea = values.hasPlantArea
        plantArea = values.plantArea
        opened = values
    }
}

// MARK: - [v25.592 轉組織 v1b] 編輯頁開著（OrgMoveDueCenter 第 ③ 個條件）

/// 部屬編輯頁（AddSubordinateView）、組織人員編輯頁（OrgPersonEditor）最外層掛這個：打開時 `editorOpened()`、關掉時 `editorClosed()`
///（開著的時候到了生效日也不自動改部門，關掉之後再看一次；brief §1-4 ③）。
/// 一開一關只算一次：拍照、選照片的畫面回來 onAppear 又跑一次也不多算（counted 旗標），計數不會卡住。
/// 要退回這一件：刪這個 modifier 與兩個編輯頁最外層的 `.orgMoveEditorPresence()`。
struct OrgMoveEditorPresence: ViewModifier {
    @State private var counted = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !counted else { return }
                counted = true
                OrgMoveDueCenter.shared.editorOpened()
            }
            .onDisappear {
                guard counted else { return }
                counted = false
                OrgMoveDueCenter.shared.editorClosed()
            }
    }
}

extension View {
    /// [v25.592 轉組織 v1b] 部屬／組織人員編輯頁開著時告訴 OrgMoveDueCenter（見 OrgMoveEditorPresence）
    func orgMoveEditorPresence() -> some View {
        modifier(OrgMoveEditorPresence())
    }
}
