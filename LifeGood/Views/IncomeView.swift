import SwiftUI

// MARK: - 美化紀錄（IncomeView）
// [2026-06 v1] 本次美化方向：
//   1. emptyState：單層脈衝光環升級為雙層（外環延遲 0.3s 製造波紋），
//      主圓尺寸從 82pt 對齊至 88pt，脈衝環從 100pt 對齊至 108pt，
//      加入綠色 CTA 按鈕「新增第一筆收入」，對齊 VariableExpenseView.emptyStateView 設計規格
//   2. incomeListSections：加入交錯淡入 + 向上進場動畫，
//      對齊 VariableExpenseView.expenseListSections 規格
//   3. summaryHeader：本月收入下方加入「日均收入」輔助文字，
//      對齊 FixedExpenseView.fixedSummaryHeader 的日均顯示規格
// [2026-06 v2] 本次美化方向（summaryHeader 升級）：
//   4. 支出進度條：從 2 段（白/紅）升級為 3 段配色（白→暖黃警示→粉紅超支），
//      與 OverviewView.monthlyBalanceCard / VariableExpenseView.monthSummaryHeader 雙軌規格對齊；
//      判斷條件：spendingRatio ≤ monthProgress+8% → 白；> monthProgress+8% → 暖黃；> 90% → 粉紅。
//   5. 進度條下方說明列加入條件式警告圖示（exclamationmark.triangle.fill 暖黃 / flame.fill 粉紅），
//      對齊 OverviewView / VariableExpenseView 警示標示規格。
//   6. 英雄卡底部加入「收入分類彩條」（mini allocation bar）：
//      當有 ≥2 個收入分類時，顯示薪資/獎金/投資/禮金/幸運金比例的漸層彩條 + glow overlay，
//      底下附各分類色圓點 + 名稱的橫排圖例，
//      對齊 FinanceOverviewView.totalAssetsCard mini 資產配置彩條設計語言。

struct IncomeView: View {
    @EnvironmentObject var store: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var lifeStore: LifeStore
    @State private var showAdd = false
    @State private var editingItem: Income?
    @State private var selectedCategory: IncomeCategory?
    @State private var searchText: String = ""
    @State private var headerAppeared = false
    @State private var listRowsAppeared = false

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f
    }()

    private static let groupDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M月d日 EEEE"
        f.locale = Locale(identifier: "zh_TW")
        return f
    }()

    var filteredIncomes: [Income] {
        var list = store.incomes.sorted { $0.date > $1.date }
        if let cat = selectedCategory {
            list = list.filter { $0.category == cat }
        }
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter { inc in
                inc.title.lowercased().contains(q)
                    || inc.note.lowercased().contains(q)
                    || inc.category.rawValue.lowercased().contains(q)
            }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summaryHeader
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .opacity(headerAppeared ? 1 : 0)
                        .offset(y: headerAppeared ? 0 : 22)
                        .onAppear {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                                headerAppeared = true
                            }
                        }
                }
                Section {
                    categoryFilter
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if filteredIncomes.isEmpty {
                    Section {
                        emptyState
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    incomeListSections
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("收入")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddIncomeView() }
            .sheet(item: $editingItem) { item in AddIncomeView(editing: item) }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜尋名稱 / 備註 / 分類"
            )
        }
    }

    /// 所有收入加總（含已繳的固定薪水展開到每一個已發生月份）
    private var totalIncomeAll: Double {
        let calendar = Calendar.current
        let now = Date()
        return store.incomes.reduce(0.0) { sum, income in
            switch income.period {
            case .once:
                return sum + income.amount
            case .monthly:
                let months = calendar.dateComponents([.month], from: income.date, to: now).month ?? 0
                return sum + income.amount * Double(max(1, months + 1))
            case .yearly:
                let years = calendar.dateComponents([.year], from: income.date, to: now).year ?? 0
                return sum + income.amount * Double(max(1, years + 1))
            }
        }
    }

    // MARK: - 摘要

    private var headerMonthProgress: Double {
        let cal = Calendar.current
        let now = Date()
        let day = Double(cal.component(.day, from: now))
        let total = Double(cal.range(of: .day, in: .month, for: now)?.count ?? 30)
        return min(day / total, 1.0)
    }

    /// 累計收入 + 歷史月均收入（從最早一筆到現在）
    private var monthlyStats: (cumulative: Double, average: Double) {
        let total = totalIncomeAll
        guard !store.incomes.isEmpty,
              let earliest = store.incomes.min(by: { $0.date < $1.date })?.date else {
            return (total, total)
        }
        let monthCount = max(1, (Calendar.current.dateComponents([.month], from: earliest, to: Date()).month ?? 0) + 1)
        return (total, total / Double(monthCount))
    }

    private func kpiCell(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    private var summaryHeader: some View {
        let useEstimate = !store.hasCurrentMonthIncome && store.estimatedMonthlyIncome > 0
        let displayedIncome = useEstimate ? store.estimatedMonthlyIncome : store.currentMonthIncomeTotal
        let displayedBalance = displayedIncome - store.currentMonthTotal
        let isPositive = displayedBalance >= 0
        let recurringMonthly = store.incomes
            .filter { $0.period != .once }
            .reduce(0.0) { $0 + $1.monthlyAmount }
        let spendingRatio = displayedIncome > 0
            ? min(store.currentMonthTotal / displayedIncome, 1.0)
            : 0.0
        let stats = monthlyStats
        // mini 分類彩條資料（≥2 種分類才顯示）
        let catAmounts = incomeCategoryAmounts
        let totalCatIncome = catAmounts.reduce(0.0) { $0 + $1.amount }

        return VStack(spacing: 0) {
            // 頂部：本月收入 + 收支餘額
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(useEstimate ? "本月收入（預估）" : "本月收入")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.78))
                        if useEstimate {
                            HStack(spacing: 3) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.system(size: 8))
                                Text("預估")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.white.opacity(0.22))
                            .clipShape(Capsule())
                            .foregroundStyle(.white)
                        }
                    }
                    Text(fmt(displayedIncome))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                    // 日均收入：對齊 FixedExpenseView.fixedSummaryHeader 輔助文字規格
                    if displayedIncome > 0 {
                        let day = Calendar.current.component(.day, from: Date())
                        Text("日均 " + fmt(displayedIncome / Double(max(day, 1))))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.top, 1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("收支餘額")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                    Text((isPositive ? "+" : "") + fmt(displayedBalance))
                        .font(.title3.bold())
                        .foregroundStyle(isPositive ? .white : Color(red: 1.0, green: 0.78, blue: 0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                        .shadow(
                            color: isPositive ? .clear : Color.red.opacity(0.40),
                            radius: 6, x: 0, y: 2
                        )
                }
            }

            if useEstimate {
                HStack(spacing: 5) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                    Text("顯示近 6 個月收入中位數預估值")
                        .font(.caption2)
                    Spacer()
                }
                .foregroundStyle(.white.opacity(0.70))
                .padding(.top, 10)
            }

            // KPI 橫列：累計收入 / 月均收入 / 固定月收
            HStack(spacing: 0) {
                kpiCell(label: "累計收入", value: fmt(stats.cumulative))
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 0.5, height: 28)
                kpiCell(label: "月均收入", value: fmt(stats.average))
                if recurringMonthly > 0 {
                    Rectangle()
                        .fill(.white.opacity(0.25))
                        .frame(width: 0.5, height: 28)
                    kpiCell(label: "固定月收", value: fmt(recurringMonthly))
                }
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

            // 雙軌進度條：月進度（上，薄軌）+ 支出比例（下，厚軌 + 針）
            if displayedIncome > 0 {
                VStack(spacing: 5) {
                    // ① 月進度軌（薄軌，半透明白）
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.12))
                                .frame(height: 3)
                            Capsule()
                                .fill(.white.opacity(0.44))
                                .frame(width: geo.size.width * headerMonthProgress, height: 3)
                                .animation(.spring(response: 0.7, dampingFraction: 0.8), value: headerMonthProgress)
                        }
                    }
                    .frame(height: 3)

                    // ② 支出比例軌（厚軌 + 月進度指示針；3 段配色對齊 OverviewView）
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.18))
                                .frame(height: 6)
                            Capsule()
                                // 3 段：正常白 → 超速暖黃 → 超支粉紅
                                .fill(spendingRatio > 0.9
                                      ? Color(red: 1.0, green: 0.78, blue: 0.75).opacity(0.90)
                                      : spendingRatio > headerMonthProgress + 0.08
                                        ? Color(red: 1.0, green: 0.65, blue: 0.22).opacity(0.90)
                                        : .white.opacity(0.82))
                                .frame(width: geo.size.width * spendingRatio, height: 6)
                                .animation(.spring(response: 0.7, dampingFraction: 0.8), value: spendingRatio)
                            // 月進度指示針（細白豎棒，指示月份走到哪）
                            Capsule()
                                .fill(.white.opacity(0.92))
                                .frame(width: 2, height: 6)
                                .shadow(color: .black.opacity(0.25), radius: 1.5, x: 0, y: 0)
                                .offset(x: max(0, geo.size.width * headerMonthProgress - 1))
                                .animation(.spring(response: 0.7, dampingFraction: 0.8), value: headerMonthProgress)
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        HStack(spacing: 3) {
                            // 條件式警告圖示：正常時不顯示，對齊 OverviewView 規格
                            if spendingRatio > headerMonthProgress + 0.08 {
                                Image(systemName: spendingRatio > 0.9
                                      ? "flame.fill"
                                      : "exclamationmark.triangle.fill")
                                    .font(.system(size: 8))
                            }
                            Text("支出 \(Int(spendingRatio * 100))%")
                        }
                        .font(.caption2)
                        .foregroundStyle(spendingRatio > 0.9
                                         ? Color(red: 1.0, green: 0.78, blue: 0.75)
                                         : spendingRatio > headerMonthProgress + 0.08
                                           ? Color(red: 1.0, green: 0.90, blue: 0.55)
                                           : .white.opacity(0.62))
                        Spacer()
                        Text("月進度 \(Int(headerMonthProgress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.60))
                    }
                }
            }

            // 收入分類彩條（≥2 個分類才顯示；設計語言對齊 FinanceOverviewView totalAssetsCard）
            if catAmounts.count > 1 && totalCatIncome > 0 {
                Rectangle()
                    .fill(.white.opacity(0.20))
                    .frame(height: 0.5)
                    .padding(.vertical, 12)

                VStack(spacing: 6) {
                    // 比例彩條（glow overlay 增加立體感）
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(Array(catAmounts.enumerated()), id: \.offset) { _, item in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(incomeCategoryColor(item.category).opacity(0.90))
                                    .frame(
                                        width: max(3, CGFloat(item.amount / totalCatIncome) *
                                                   (geo.size.width - CGFloat(max(0, catAmounts.count - 1)) * 2))
                                    )
                            }
                        }
                    }
                    .frame(height: 6)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(
                        // 頂部白色高亮 + 底部柔化，增加彩條立體感
                        LinearGradient(
                            colors: [.white.opacity(0.28), .clear, .black.opacity(0.08)],
                            startPoint: .top, endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    )

                    // 圖例：色圓點 + 分類名稱橫排
                    HStack(spacing: 8) {
                        ForEach(Array(catAmounts.enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(incomeCategoryColor(item.category))
                                    .frame(width: 5, height: 5)
                                Text(item.category.rawValue)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.80))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.74, blue: 0.50),
                        Color(red: 0.07, green: 0.50, blue: 0.38)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // 右上主散景圓
                Circle()
                    .fill(.white.opacity(0.13))
                    .frame(width: 140, height: 140)
                    .offset(x: 90, y: -55)
                    .blur(radius: 14)
                // 左下補光
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 90, height: 90)
                    .offset(x: -70, y: 55)
                    .blur(radius: 10)
                // 中右小散景（增加層次）
                Circle()
                    .fill(.white.opacity(0.05))
                    .frame(width: 55, height: 55)
                    .offset(x: 60, y: 40)
                    .blur(radius: 8)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.07, green: 0.50, blue: 0.38).opacity(0.42), radius: 16, x: 0, y: 8)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    // MARK: - 篩選

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "全部", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(IncomeCategory.allCases) { cat in
                    FilterChip(title: cat.rawValue, icon: cat.icon, isSelected: selectedCategory == cat) {
                        selectedCategory = cat
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

    private func daySectionHeader(dateString: String, incomes: [Income]) -> some View {
        let dayTotal = incomes.reduce(0.0) { $0 + $1.amount }
        let accent = Color(red: 0.16, green: 0.74, blue: 0.50)
        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 3, height: 14)

            Text(dateString)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.75))

            Spacer(minLength: 6)

            HStack(spacing: 4) {
                Text("+\(fmt(dayTotal))")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(accent)
                Text("· \(incomes.count) 筆")
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

    private var emptyState: some View {
        let isSearching = !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        let accent = Color(red: 0.16, green: 0.74, blue: 0.50)
        return VStack(spacing: 24) {
            ZStack {
                if !isSearching {
                    // 外層脈衝光環（對齊 VariableExpenseView emptyStateView 雙層環規格）
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
                // 主圓底（漸層填色 + 細邊框，尺寸對齊至 88pt）
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
                Image(systemName: isSearching ? "magnifyingglass" : "banknote")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(isSearching ? .secondary : accent.opacity(0.72))
            }
            .onAppear {
                if !isSearching {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        emptyIconPulse = true
                    }
                }
            }

            VStack(spacing: 10) {
                Text(isSearching ? "找不到符合的收入" : "尚無收入紀錄")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.75))
                Text(isSearching ? "換個關鍵字試試" : "薪資、獎金、投資收益等\n各類收入都可以記錄在這裡")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            // 非搜尋狀態下顯示 CTA 按鈕，對齊 VariableExpenseView 空狀態設計規格
            if !isSearching {
                Button {
                    showAdd = true
                } label: {
                    Label("新增第一筆收入", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [accent, Color(red: 0.07, green: 0.50, blue: 0.38)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: Color(red: 0.07, green: 0.50, blue: 0.38).opacity(0.35), radius: 10, y: 5)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    // MARK: - 列表（List sections，包在外層的 List 內）

    @ViewBuilder
    private var incomeListSections: some View {
        let groups = groupedByDate()
        ForEach(Array(groups.enumerated()), id: \.element.key) { groupIdx, pair in
            let (dateString, incomes) = pair
            Section(header: daySectionHeader(dateString: dateString, incomes: incomes)) {
                ForEach(Array(incomes.enumerated()), id: \.element.id) { rowIdx, income in
                    incomeRow(income)
                        .contentShape(Rectangle())
                        .onTapGesture { editingItem = income }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                if let idx = incomes.firstIndex(where: { $0.id == income.id }) {
                                    deleteIncomes(at: IndexSet(integer: idx), from: incomes)
                                }
                            } label: { Label("刪除", systemImage: "trash") }

                            Button {
                                duplicateIncome(income)
                            } label: { Label("複製", systemImage: "doc.on.doc") }
                            .tint(.blue)
                        }
                        // 交錯淡入 + 向上進場，對齊 VariableExpenseView 規格
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
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05)) {
                listRowsAppeared = true
            }
        }
    }

    /// 刪除收入時同步清掉股票連結與銀行存款紀錄
    private func deleteIncomes(at offsets: IndexSet, from incomes: [Income]) {
        for index in offsets {
            let income = incomes[index]
            if let stockId = income.linkedStockId,
               var stock = financeStore.stocks.first(where: { $0.id == stockId }) {
                stock.linkedIncomeId = nil
                financeStore.update(stock)
            }
            if let bankId = income.linkedBankMilestoneId,
               var ms = lifeStore.milestones.first(where: { $0.id == bankId }) {
                ms.bankDeposits?.removeAll { $0.linkedExpenseId == income.id }
                lifeStore.update(ms)
            }
        }
        store.deleteIncome(at: offsets, from: incomes)
    }

    /// 複製收入：欄位沿用、日期改為現在、不沿用股票配息連結（避免 1:1 配息重複連結）。
    /// 若是一次性且連結銀行帳戶，補一筆對應的入帳紀錄維持餘額正確。
    private func duplicateIncome(_ income: Income) {
        let copy = Income(
            id: UUID(),
            title: income.title,
            amount: income.amount,
            date: Date(),
            category: income.category,
            period: income.period,
            isFixedSalary: income.isFixedSalary,
            note: income.note,
            linkedStockId: nil,
            linkedBankMilestoneId: income.linkedBankMilestoneId,
            linkedBankCurrency: income.linkedBankCurrency
        )
        store.add(copy)
        // 一次性收入 + 有連結銀行 → 補一筆入帳，週期性收入靠展開不需單筆
        if copy.period == .once,
           let bankId = copy.linkedBankMilestoneId,
           var ms = lifeStore.milestones.first(where: { $0.id == bankId }) {
            var list = ms.bankDeposits ?? []
            list.append(BankDeposit(
                id: UUID(), date: copy.date, amount: copy.amount,
                currencyCode: copy.linkedBankCurrency ?? "NT$",
                isWithdrawal: false, linkedExpenseId: copy.id
            ))
            ms.bankDeposits = list
            lifeStore.update(ms)
        }
    }

    private func incomeCategoryColor(_ category: IncomeCategory) -> Color {
        switch category {
        case .salary:     return Color(red: 0.16, green: 0.74, blue: 0.50)
        case .bonus:      return Color(red: 1.00, green: 0.72, blue: 0.18)
        case .gift:       return Color(red: 1.00, green: 0.35, blue: 0.55)
        case .luck:       return Color(red: 0.68, green: 0.40, blue: 1.00)
        case .investment: return Color(red: 0.27, green: 0.67, blue: 0.99)
        }
    }

    // mini 收入分類彩條用：依收入金額加總，取排名前 N 大的分類比例
    private var incomeCategoryAmounts: [(category: IncomeCategory, amount: Double)] {
        var amounts: [IncomeCategory: Double] = [:]
        for income in store.incomes {
            amounts[income.category, default: 0] += income.amount
        }
        return IncomeCategory.allCases
            .compactMap { cat -> (category: IncomeCategory, amount: Double)? in
                let v = amounts[cat, default: 0]
                return v > 0 ? (cat, v) : nil
            }
            .sorted { $0.amount > $1.amount }
    }

    private func incomeRow(_ income: Income) -> some View {
        let accent = incomeCategoryColor(income.category)
        return HStack(spacing: 12) {
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
                Image(systemName: income.category.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(income.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(income.category.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(accent.opacity(0.12))
                        .clipShape(Capsule())
                    if income.period != .once {
                        Text(income.period.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(accent.opacity(0.10))
                            .foregroundStyle(accent.opacity(0.85))
                            .clipShape(Capsule())
                    }
                    if !income.note.isEmpty {
                        Text(income.note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                Text(fmt(income.amount))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .contentTransition(.numericText())
                if let label = depositBankLabel(for: income) {
                    HStack(spacing: 3) {
                        Image(systemName: "building.columns.fill")
                            .font(.system(size: 9))
                        Text(label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())
                    .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func depositBankLabel(for income: Income) -> String? {
        guard let bankId = income.linkedBankMilestoneId,
              let ms = lifeStore.milestones.first(where: { $0.id == bankId }) else { return nil }
        let name = ms.bankName ?? ms.title
        let currency = income.linkedBankCurrency ?? "NT$"
        return currency == "NT$" ? name : "\(name) · \(currency)"
    }

    // MARK: - 分組

    private func groupedByDate() -> [(key: String, value: [Income])] {
        let grouped = Dictionary(grouping: filteredIncomes) { income in
            Self.groupDateFormatter.string(from: income.date)
        }

        return grouped.sorted { pair1, pair2 in
            guard let d1 = pair1.value.first?.date, let d2 = pair2.value.first?.date else { return false }
            return d1 > d2
        }
    }

    /// 金額格式化：未滿一萬照常顯示 NT$ 金額；達到一萬(含)以上改以「萬」為單位，
    /// 例如 12,345 → NT$1.2萬、1,234,567 → NT$123.5萬，避免位數過多造成換行/難讀。
    private func fmt(_ v: Double) -> String {
        v.ntdWanString
    }
}
