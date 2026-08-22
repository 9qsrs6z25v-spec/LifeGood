import SwiftUI

// MARK: - 美化紀錄（VariableExpenseView）
// [2026-06 v1] 本次美化方向：
//   1. monthSummaryHeader：移除頂部內嵌「日均」文字，改以 KPI 橫列統一展示，
//      三格：今日花費 / 日均支出 / 近3月均值，對齊 IncomeView.kpiCell 規格
//   2. monthSummaryHeader：KPI 橫列與月進度條之間加入分隔線，提升視覺層次
//   3. emptyStateView：單層脈衝光環升級為雙層（外環延遲 0.3s 製造波紋），
//      並加入橘色 CTA 按鈕，對齊 FixedExpenseView.emptyStateView 設計規格
//   4. expenseListSections：加入交錯淡入 + 向上進場動畫，
//      對齊 FixedExpenseView.fixedExpenseSections 規格
// [2026-06 v2] 本次美化方向（ExpenseRow）：
//   5. 分類標籤 HStack 加入地點指示圖示（mappin.circle.fill，11pt 綠色）：
//      當 expense.placeLatitude != nil 時顯示，標示此筆消費已標注至美食地圖，
//      對齊 VariableExpenseView.searchable 可搜尋 placeAddress 的資訊揭露規格。
//   6. 右側 VStack 加入社交禮金收受人膠囊（gift.fill 圖示 + 粉紅色）：
//      當 expense.variableCategory == .social && socialRecipient 不為空時顯示，
//      補齊 diningMember 已顯示但 socialRecipient 未顯示的資訊不均衡問題，
//      對齊 AddExpenseView 社交禮金收受人 .pink 配色規格。
// [2026-06 v3] 本次美化方向（monthSummaryHeader 雙軌進度條）：
//   10. 月進度條從單軌升級為雙軌，對齊 IncomeView.summaryHeader / OverviewView.monthlyBalanceCard 規格：
//       ① 上軌（薄 3pt，white.opacity(0.44)）：月份進度；
//       ② 下軌（厚 6pt）：本月支出 vs 近3月均值比率，含月進度指示針（白色 2pt 豎棒）。
//   11. 下軌配色三段：比率 ≤ 月進度+8% → 白色；比率 > 月進度+8% → 暖黃警示；
//       比率 > 100%（超過月均）→ 粉紅警示色（超支）。
//   12. 近3月均值為零時降級回原有單軌，確保初次使用兼容，不破壞既有邏輯。
// [2026-06 v4] 本次美化方向（英雄卡玻璃光澤補齊）：
//   13. monthSummaryHeader 背景 ZStack 末層加入 LinearGradient [.white.opacity(0.18), .clear]
//       top→center 玻璃反光覆蓋層，對齊 OverviewView.monthlyBalanceCard v3 /
//       IncomeView.summaryHeader v4 / FinanceOverviewView.totalAssetsCard v3 英雄卡玻璃光澤規格；
//       補齊全 App 六張英雄卡中此張缺少的一層光澤（與 FixedExpenseView 同步補齊）。
//   14. 補入第三顆散景裝飾圓（中右 55pt，white.opacity(0.05)），
//       對齊 IncomeView.summaryHeader 三圓規格（右上主圓 + 左下次圓 + 中右微光），
//       讓色彩層次與其他英雄卡對齊。
// [2026-07 v5] 本次美化方向（monthSummaryHeader 大字金額防截斷）：
//   15. 「本月變動支出」32pt 大字金額補上 .lineLimit(1) + .minimumScaleFactor(0.5)，
//       對齊 IncomeView.summaryHeader / Finance/AddStockView / Finance/RealEstateView
//       等姊妹英雄卡既有的大字防截斷規格；金額位數很多（例如萬元以上）時自動縮小字級，
//       避免在小螢幕裝置上被裁切，且縮放下限仍維持可辨識大小（同步補齊 FixedExpenseView）。

struct VariableExpenseView: View {
    @EnvironmentObject var store: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var lifeStore: LifeStore
    @State private var showingAddSheet = false
    @State private var selectedCategory: VariableCategory?
    @State private var expenseToEdit: Expense?
    /// 點列先開詳情卡片（FinanceItemCard 模組）；編輯是卡片右上的動作
    @State private var previewExpense: Expense?
    @State private var visibleWeeks = 1
    @State private var searchText: String = ""
    @State private var listRowsAppeared = false
    @State private var cachedTrailingMonthlyAvg: Double = 0
    /// 英雄卡背景趨勢（單月變動支出逐月序列；HeroTrendBackground 標準模板）
    @State private var heroSeries: [HeroTrendPoint] = []
    @State private var cachedTodayVariableTotal: Double = 0
    @State private var debouncedSearchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var cachedFilteredExpenses: [Expense] = []

    private static let groupDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M月d日 EEEE"
        f.locale = Locale(identifier: "zh_TW")
        return f
    }()

    /// 分組 key 專用（含年份，"yyyy-MM-dd"），對齊 IncomeView 同型修復：groupDateFormatter 沒有
    /// 年份，跨年資料若同月同日同星期幾會被 Dictionary 分組誤合併成同一個 Section。
    private static let groupKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "zh_TW")
        return f
    }()

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "TWD"
        f.currencySymbol = "NT$"
        f.maximumFractionDigits = 0
        return f
    }()

    var filteredExpenses: [Expense] { cachedFilteredExpenses }

    private func buildFilteredExpenses() -> [Expense] {
        var list = store.variableExpenses
        if let category = selectedCategory {
            list = list.filter { $0.variableCategory == category }
        }
        let q = debouncedSearchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter { exp in
                exp.title.lowercased().contains(q)
                    || exp.note.lowercased().contains(q)
                    || exp.categoryName.lowercased().contains(q)
                    || (exp.placeAddress?.lowercased().contains(q) ?? false)
                    || (exp.diningMember?.lowercased().contains(q) ?? false)
                    || (exp.socialRecipient?.lowercased().contains(q) ?? false)
                    || (exp.taxSavingSubCategory?.rawValue.lowercased().contains(q) ?? false)
                    || (exp.socialSubCategory?.rawValue.lowercased().contains(q) ?? false)
            }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 0) {
                        monthSummaryHeader
                        // 超支警示：emoji 小字提示掛在卡片下方（正常時不顯示）
                        HeroOverspendHint(ratio: overspendRatio,
                                          monthProgress: monthProgress,
                                          noun: "變動支出")
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                Section {
                    categoryFilter
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                let expenses = filteredExpenses
                if expenses.isEmpty {
                    Section {
                        emptyStateView
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    expenseListSectionsFor(expenses)
                }
            }
            .listStyle(.insetGrouped)
            // onAppear/onDisappear 掛在 List 本身（而非 expenseListSectionsFor 內每個日期分組的
            // ForEach）：List 延遲載入各 Section，掛在 ForEach 上等同掛在每組各自的子視圖上，
            // 捲動使某組進出可視範圍就各自觸發一次，所有列共用的 listRowsAppeared 旗標會被
            // 反覆重置，導致可視列表捲動時無謂淡出又重播進場動畫。改掛在 List 本身，
            // 比照 FamilyView 既有寫法，確保只在畫面進出時各觸發一次。
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05)) {
                    listRowsAppeared = true
                }
            }
            .onDisappear {
                listRowsAppeared = false
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("變動支出")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddExpenseView(expenseType: .variable)
            }
            .sheet(item: $expenseToEdit) { expense in
                AddExpenseView(expenseType: .variable, editingExpense: expense)
            }
            .sheet(item: $previewExpense) { expense in
                FinanceItemCard(target: .variableExpense(expense.id))
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜尋名稱 / 備註 / 分類 / 地點"
            )
            .onChange(of: searchText) { _, newValue in
                searchDebounceTask?.cancel()
                searchDebounceTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    debouncedSearchText = newValue
                }
            }
            .onDisappear { searchDebounceTask?.cancel() }
            .task(id: store.modifyID) {
                cachedTrailingMonthlyAvg = computeTrailingMonthlyAvg()
                cachedTodayVariableTotal = store.variableExpenses
                    .filter { Calendar.current.isDateInToday($0.date) }
                    .reduce(0) { $0 + $1.amount }
                heroSeries = store.heroVariableSeries()   // 壓縮/補點交給模板依進階設定即時處理
            }
            .task(id: "\(store.modifyID)-\(selectedCategory?.rawValue ?? "")-\(debouncedSearchText)") {
                cachedFilteredExpenses = buildFilteredExpenses()
            }
        }
    }

    // MARK: - KPI 計算輔助

    private func computeTrailingMonthlyAvg() -> Double {
        let calendar = Calendar.current
        let now = Date()
        var totals: [Double] = []
        for i in 1...3 {
            guard let base = calendar.date(byAdding: .month, value: -i, to: now),
                  let interval = calendar.dateInterval(of: .month, for: base) else { continue }
            let total = store.expenses
                .filter { $0.expenseType == .variable && $0.date >= interval.start && $0.date < interval.end }
                .reduce(0) { $0 + $1.amount }
            totals.append(total)
        }
        guard !totals.isEmpty else { return 0 }
        return totals.reduce(0, +) / Double(totals.count)
    }

    private var todayVariableTotal: Double { cachedTodayVariableTotal }

    private var trailingMonthlyAverageVariable: Double { cachedTrailingMonthlyAvg }



    // MARK: - 月摘要

    private var monthProgress: Double {
        let cal = Calendar.current
        let now = Date()
        let day = Double(cal.component(.day, from: now))
        let total = Double(cal.range(of: .day, in: .month, for: now)?.count ?? 30)
        return min(day / total, 1.0)
    }

    /// 卡片下方超支提示用的比例（本月變動支出 ÷ 近 3 月均值；與卡內進度條同口徑、不夾住）
    private var overspendRatio: Double {
        let avg = trailingMonthlyAverageVariable
        return avg > 0 ? store.currentMonthVariableTotal / avg : 0
    }

    private var monthSummaryHeader: some View {
        // 一次 filter 同時算筆數與總額，避免 currentMonthExpenses（掃全部支出）被呼叫兩次
        let monthlyVariable = store.currentMonthExpenses.filter { $0.expenseType == .variable }
        let count = monthlyVariable.count
        let total = monthlyVariable.reduce(0) { $0 + $1.amount }
        let dayOfMonth = Calendar.current.component(.day, from: Date())
        let dailyAvg = total / Double(max(dayOfMonth, 1))

        return VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("本月變動支出")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.80))
                    Text(formatCurrency(total))
                        .heroBigValueFont()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(count) 筆")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.22))
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                }
            }

            // KPI 橫列：今日花費 / 日均支出 / 近3月均值
            HStack(spacing: 0) {
                HeroKpiCell(label: "今日花費", value: formatCurrency(todayVariableTotal))
                HeroKpiDivider()
                HeroKpiCell(label: "日均支出", value: formatCurrency(dailyAvg))
                HeroKpiDivider()
                HeroKpiCell(label: "近3月均值", value: formatCurrency(trailingMonthlyAverageVariable))
            }
            .padding(.vertical, 10)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.top, 12)

            // 分隔線
            Rectangle()
                .fill(.white.opacity(0.20))
                .frame(height: 0.5)
                .padding(.vertical, 12)

            // 雙軌進度條（有近3月均值時）：月進度（上薄軌）+ 支出進度（下厚軌 + 指示針）
            if trailingMonthlyAverageVariable > 0 {
                // rawRatio 計算一次，供進度條寬度、配色、標籤文字共用，
                // 避免在各 closure 內重複呼叫 store.currentMonthVariableTotal
                let avg = trailingMonthlyAverageVariable
                let rawRatio = total / avg
                let barRatio = min(rawRatio, 1.0)
                let barColor: Color = {
                    if rawRatio > 1.0 { return Color(red: 1.0, green: 0.78, blue: 0.75).opacity(0.90) }
                    if rawRatio > monthProgress + HeroOverspendHint.warnLead {
                        return Color(red: 1.0, green: 0.65, blue: 0.22).opacity(0.90)
                    }
                    return .white.opacity(0.82)
                }()
                VStack(spacing: 5) {
                    // ① 月進度軌（薄軌，半透明白）
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.12)).frame(height: 3)
                            Capsule().fill(.white.opacity(0.44))
                                .frame(width: geo.size.width * monthProgress, height: 3)
                                .animation(.spring(response: 0.7, dampingFraction: 0.8), value: monthProgress)
                        }
                    }
                    .frame(height: 3)
                    // ② 支出進度軌（厚軌 + 月進度指示針）
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.18)).frame(height: 6)
                            Capsule()
                                .fill(barColor)
                                .frame(width: geo.size.width * barRatio, height: 6)
                                .animation(.spring(response: 0.7, dampingFraction: 0.8), value: barRatio)
                            // 月進度指示針（細白豎棒）
                            Capsule()
                                .fill(.white.opacity(0.92))
                                .frame(width: 2, height: 6)
                                .shadow(color: .black.opacity(0.25), radius: 1.5, x: 0, y: 0)
                                .offset(x: max(0, geo.size.width * monthProgress - 1))
                                .animation(.spring(response: 0.7, dampingFraction: 0.8), value: monthProgress)
                        }
                    }
                    .frame(height: 6)
                    HStack {
                        // 警示圖示已移至卡片下方的 HeroOverspendHint（emoji 小字提示）
                        Text("支出 \(Int(rawRatio * 100))%（均）")
                        .font(.caption2)
                        .foregroundStyle({
                            if rawRatio > 1.0 { return Color(red: 1.0, green: 0.78, blue: 0.75) }
                            if rawRatio > monthProgress + HeroOverspendHint.warnLead {
                                return Color(red: 1.0, green: 0.90, blue: 0.55)
                            }
                            return .white.opacity(0.60) as Color
                        }())
                        Spacer()
                        Text("月進度 \(Int(monthProgress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.60))
                    }
                }
            } else {
                // 無近3月均值時降級為單軌（初次使用兼容）
                VStack(spacing: 5) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.18)).frame(height: 5)
                            Capsule().fill(.white.opacity(0.80))
                                .frame(width: geo.size.width * monthProgress, height: 5)
                                .animation(.spring(response: 0.7, dampingFraction: 0.8), value: monthProgress)
                        }
                    }
                    .frame(height: 5)
                    HStack {
                        Text("本月進度 \(Int(monthProgress * 100))%")
                            .font(.caption2).foregroundStyle(.white.opacity(0.60))
                        Spacer()
                        Text("剩 \(Int((1 - monthProgress) * 100))%")
                            .font(.caption2).foregroundStyle(.white.opacity(0.60))
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .heroCardShell(card: .variableExpense) {
            // 單月變動支出趨勢曲線背景（HeroTrendBackground 標準模板）
            HeroTrendBackground(points: heroSeries, stepBack: 2_592_000)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    // MARK: - 分類篩選

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "全部", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }

                ForEach(VariableCategory.allCases) { category in
                    FilterChip(
                        title: category.rawValue,
                        icon: category.icon,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color(.separator).opacity(0.22), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 1)
        }
    }

    // MARK: - 日期 Section Header（含日計合計）

    private func daySectionHeader(dateString: String, expenses: [Expense]) -> some View {
        let dayTotal = expenses.reduce(0.0) { $0 + $1.amount }
        let accent = Color(red: 1.00, green: 0.62, blue: 0.22)
        return HStack(spacing: 8) {
            // 小方形日期標記，與左側列表色系呼應
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.60)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 3, height: 14)

            Text(dateString)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.75))

            Spacer(minLength: 6)

            // 當日合計膠囊：帶淡橘背景 + 細邊框
            HStack(spacing: 4) {
                Text(formatCurrency(dayTotal))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(accent)
                Text("· \(expenses.count) 筆")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(accent.opacity(0.10))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(accent.opacity(0.22), lineWidth: 0.6)
            )
        }
        .textCase(nil)
    }

    // MARK: - 空狀態

    @State private var emptyIconPulse = false
    @State private var emptyPulseTask: Task<Void, Never>?

    private var emptyStateView: some View {
        let isSearching = !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        let accent = Color(red: 1.00, green: 0.62, blue: 0.22)
        return VStack(spacing: 24) {
            ZStack {
                if !isSearching {
                    // 外層脈衝光環
                    Circle()
                        .stroke(accent.opacity(emptyIconPulse ? 0 : 0.25), lineWidth: 1.5)
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
                }
                // 主圓圈（漸層底 + 細邊框）
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isSearching
                                ? [Color(.systemFill), Color(.secondarySystemFill)]
                                : [accent.opacity(0.15), accent.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .overlay(
                        Circle()
                            .stroke(
                                isSearching ? Color.clear : accent.opacity(0.22),
                                lineWidth: 1.2
                            )
                    )
                Image(systemName: isSearching ? "magnifyingglass" : "bag")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(isSearching ? .secondary : accent.opacity(0.72))
            }
            .onAppear {
                emptyIconPulse = false
                emptyPulseTask?.cancel()
                if !isSearching {
                    emptyPulseTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard !Task.isCancelled else { return }
                        emptyIconPulse = true
                    }
                }
            }
            // [除錯] isSearching 只是本地計算值，不會改變外層 ZStack 的身分，
            // 單靠 onAppear/onDisappear 不會在搜尋文字變化時重觸發；空清單時
            // 搜尋一次再清空會讓脈衝動畫永久停止（對齊 FoodMapView.emptyOverlay 的既有修法）。
            .onChange(of: isSearching) { _, searching in
                emptyPulseTask?.cancel()
                emptyIconPulse = false
                if !searching {
                    emptyPulseTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard !Task.isCancelled else { return }
                        emptyIconPulse = true
                    }
                }
            }
            .onDisappear {
                emptyPulseTask?.cancel()
            }

            VStack(spacing: 10) {
                Text(isSearching ? "找不到符合的支出" : "尚無變動支出紀錄")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.75))
                Text(isSearching ? "換個關鍵字試試" : "變動支出包含日常消費、飲食、\n娛樂、購物等非固定費用")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            if !isSearching {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("新增第一筆支出", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [accent, Color(red: 0.86, green: 0.36, blue: 0.06)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: Color(red: 0.86, green: 0.36, blue: 0.06).opacity(0.35), radius: 10, y: 5)
                }
                .buttonStyle(.plain)
            }

        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    // MARK: - 支出列表（List sections，包在外層的 List 內）

    @ViewBuilder
    private func expenseListSectionsFor(_ expenses: [Expense]) -> some View {
        let allGroups = groupedByDate(expenses)
        let isSearching = !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        let cutoff = Calendar.current.date(byAdding: .day, value: -7 * visibleWeeks, to: Date()) ?? Date()
        // 搜尋時不限制週數，顯示所有符合的結果
        let visibleGroups = isSearching ? allGroups : allGroups.filter { group in
            guard let d = group.value.first?.date else { return false }
            return d >= cutoff
        }
        let hiddenGroups: [(key: String, value: [Expense])] = isSearching ? [] : allGroups.filter { group in
            guard let d = group.value.first?.date else { return true }
            return d < cutoff
        }
        let hiddenCount = hiddenGroups.reduce(0) { $0 + $1.value.count }

        ForEach(Array(visibleGroups.enumerated()), id: \.element.key) { groupIdx, group in
            let expenses = group.value
            let dateString = expenses.first.map { Self.groupDateFormatter.string(from: $0.date) } ?? group.key
            Section(header: daySectionHeader(dateString: dateString, expenses: expenses)) {
                ForEach(Array(expenses.enumerated()), id: \.element.id) { rowIdx, expense in
                    ExpenseRow(expense: expense)
                        .contentShape(Rectangle())
                        .onTapGesture { previewExpense = expense }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                if let idx = expenses.firstIndex(where: { $0.id == expense.id }) {
                                    deleteWithSync(offsets: IndexSet(integer: idx), from: expenses)
                                }
                            } label: { Label("刪除", systemImage: "trash") }

                            Button {
                                duplicateExpense(expense)
                            } label: { Label("複製", systemImage: "doc.on.doc") }
                            .tint(.blue)
                        }
                        .opacity(listRowsAppeared ? 1 : 0)
                        .offset(y: listRowsAppeared ? 0 : 12)
                        .animation(
                            .spring(response: 0.44, dampingFraction: 0.82)
                                .delay(0.04 * Double(min(groupIdx * 3 + rowIdx, 14))),
                            value: listRowsAppeared
                        )
                }
            }
        }

        if hiddenCount > 0 {
            Section {
                Button {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                        visibleWeeks += 1
                    }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.12))
                                .frame(width: 36, height: 36)
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.green)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("展開更早一週")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("還有 \(hiddenCount) 筆隱藏中")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(hiddenCount)")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.12))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 刪除變動支出時同步刪除理財連結項目
    private func deleteWithSync(offsets: IndexSet, from list: [Expense]) {
        for index in offsets {
            let expense = list[index]
            // 同步刪除汽車變動支出
            if let vehicleId = expense.linkedVehicleId,
               var vehicle = financeStore.vehicles.first(where: { $0.id == vehicleId }) {
                vehicle.variableExpenses.removeAll { $0.linkedExpenseId == expense.id }
                financeStore.update(vehicle)
            }
            // 同步刪除房地產變動支出與水電瓦斯繳費紀錄
            if let reId = expense.linkedRealEstateId,
               var re = financeStore.realEstates.first(where: { $0.id == reId }) {
                re.variableExpenses.removeAll { $0.linkedExpenseId == expense.id }
                re.utilityPayments.removeAll { $0.linkedExpenseId == expense.id }
                financeStore.update(re)
            }
            // 同步解除股票連結（僅在該股票確實連結的是這筆被刪除的支出時才解除，
            // 避免複製支出產生的重複 linkedStockId 誤刪原始支出的連結）
            if let stockId = expense.linkedStockId,
               var stock = financeStore.stocks.first(where: { $0.id == stockId }),
               stock.linkedExpenseId == expense.id {
                stock.linkedExpenseId = nil
                financeStore.update(stock)
            }
            // 同步刪除銀行扣款記錄
            if let bankId = expense.linkedBankMilestoneId,
               var ms = lifeStore.milestones.first(where: { $0.id == bankId }) {
                ms.bankDeposits?.removeAll { $0.linkedExpenseId == expense.id }
                lifeStore.update(ms)
            }
        }
        store.delete(at: offsets, from: list)
    }

    /// 複製支出：全部欄位複製，日期改為現在
    private func duplicateExpense(_ expense: Expense) {
        let copy = Expense(
            id: UUID(),
            title: expense.title,
            amount: expense.amount,
            date: Date(),
            expenseType: expense.expenseType,
            variableCategory: expense.variableCategory,
            fixedCategory: expense.fixedCategory,
            recurrence: expense.recurrence,
            insuranceSubCategory: expense.insuranceSubCategory,
            loanSubCategory: expense.loanSubCategory,
            linkedInsuranceId: expense.linkedInsuranceId,
            linkedStockId: expense.linkedStockId,
            linkedRealEstateId: expense.linkedRealEstateId,
            linkedVehicleId: expense.linkedVehicleId,
            vehicleExpenseCategory: expense.vehicleExpenseCategory,
            realEstateExpenseCategory: expense.realEstateExpenseCategory,
            taxSavingSubCategory: expense.taxSavingSubCategory,
            socialSubCategory: expense.socialSubCategory,
            socialRecipient: expense.socialRecipient,
            taxDeductibleOverride: expense.taxDeductibleOverride,
            note: expense.note,
            currencyCode: expense.currencyCode,
            diningMember: expense.diningMember,
            linkedBankMilestoneId: expense.linkedBankMilestoneId,
            linkedBankCurrency: expense.linkedBankCurrency,
            linkedCreditCardMilestoneId: expense.linkedCreditCardMilestoneId,
            placeAddress: expense.placeAddress,
            placeLatitude: expense.placeLatitude,
            placeLongitude: expense.placeLongitude
        )
        store.add(copy)
    }

    // MARK: - 依日期分組

    private func groupedByDate(_ expenses: [Expense]) -> [(key: String, value: [Expense])] {
        let grouped = Dictionary(grouping: expenses) { expense in
            Self.groupKeyFormatter.string(from: expense.date)
        }

        return grouped.sorted { pair1, pair2 in
            guard let date1 = pair1.value.first?.date,
                  let date2 = pair2.value.first?.date else { return false }
            return date1 > date2
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        value.ntdWanString
    }
}

// MARK: - 篩選標籤

struct FilterChip: View {
    let title: String
    var icon: String?
    let isSelected: Bool
    /// 選中狀態的背景色；預設 .green，可傳入分類特有色彩（如 CareerView 的子分類色）
    var tint: Color = .green
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(isSelected ? tint : Color(.secondarySystemFill))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
            .shadow(
                color: isSelected ? tint.opacity(0.30) : .clear,
                radius: 6, x: 0, y: 3
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.04 : 1.0)
        .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isSelected)
    }
}

// MARK: - 支出列

struct ExpenseRow: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var store: ExpenseStore
    let expense: Expense

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "TWD"
        f.currencySymbol = "NT$"
        f.maximumFractionDigits = 0
        return f
    }()

    private static let decimalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    private var categoryAccent: Color {
        expense.variableCategory?.accentColor ?? .secondary
    }

    var body: some View {
        HStack(spacing: 12) {
            // 分類圖示圓（加大 + 陰影）
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [categoryAccent.opacity(0.22), categoryAccent.opacity(0.09)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .shadow(color: categoryAccent.opacity(0.22), radius: 6, x: 0, y: 3)
                Image(systemName: expense.categoryIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(categoryAccent)
            }

            // 標題 + 副資訊
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                // 分類膠囊標籤 + 地點指示 + 備註
                HStack(spacing: 5) {
                    Text(expense.categoryName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(categoryAccent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(categoryAccent.opacity(0.12))
                        .clipShape(Capsule())
                    // 地點指示（有 GPS 座標時顯示，對應美食地圖功能入口）
                    if expense.placeLatitude != nil {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.green.opacity(0.72))
                    }
                    if !expense.note.isEmpty {
                        Text(expense.note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                // 扣款帳戶標籤（信用卡 / 銀行）
                if let label = deductionTargetLabel {
                    HStack(spacing: 3) {
                        Image(systemName: deductionIcon)
                            .font(.system(size: 9, weight: .medium))
                        Text(label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(categoryAccent.opacity(0.85))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(categoryAccent.opacity(0.08))
                    .clipShape(Capsule())
                    .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            // 金額 + 同行者
            VStack(alignment: .trailing, spacing: 4) {
                Text(formattedAmount)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.25))
                    .contentTransition(.numericText())

                if let member = expense.diningMember, !member.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 9))
                        Text(member)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.10))
                    .clipShape(Capsule())
                    .lineLimit(1)
                }
                // 社交禮金收受人（社交分類才顯示）
                if expense.variableCategory == .social,
                   let recipient = expense.socialRecipient,
                   !recipient.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 9))
                        Text(recipient)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.pink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.pink.opacity(0.10))
                    .clipShape(Capsule())
                    .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 5)
    }

    private var deductionIcon: String {
        expense.linkedCreditCardMilestoneId != nil ? "creditcard.fill" : "building.columns.fill"
    }

    private var deductionTargetLabel: String? {
        if let cardId = expense.linkedCreditCardMilestoneId,
           let card = lifeStore.milestones.first(where: { $0.id == cardId }) {
            return card.cardName ?? card.title
        }
        if let bankId = expense.linkedBankMilestoneId,
           let ms = lifeStore.milestones.first(where: { $0.id == bankId }) {
            let name = ms.bankName ?? ms.title
            let currency = expense.linkedBankCurrency ?? "NT$"
            return currency == "NT$" ? name : "\(name) · \(currency)"
        }
        return nil
    }

    private func formatCurrency(_ value: Double) -> String {
        value.ntdWanString
    }

    /// 顯示用金額：外幣時將儲存的台幣等值除以匯率還原原幣金額
    private var formattedAmount: String {
        let code = expense.currencyCode
        if code != "NT$" && code != "TWD" && !code.isEmpty {
            let displayAmount: Double
            if let rate = store.currencyRates.first(where: { $0.code == code }), rate.rate > 0 {
                displayAmount = expense.amount / rate.rate
            } else {
                displayAmount = expense.amount
            }
            let str = Self.decimalFormatter.string(from: NSNumber(value: displayAmount)) ?? "0"
            return "\(code) \(str)"
        }
        return formatCurrency(expense.amount)
    }
}

#Preview {
    VariableExpenseView()
        .environmentObject(ExpenseStore())
}
