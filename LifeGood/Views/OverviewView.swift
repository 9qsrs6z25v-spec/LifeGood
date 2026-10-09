import SwiftUI

// MARK: - 美化紀錄（OverviewView）
// [2026-06 v1] smartCurrency：新增億量級支援（≥1億 → "X.X 億"），對齊 ntdWanString 與
//   FinanceOverviewView.fmtShort 的「萬、億」顯示規格，避免「10000.0 萬」截斷大字。
//   閾值：<1萬→NT$X，≥1萬<1億→"X.X 萬"，≥1億→"X.X 億"。
// [2026-06 v2] recentRow + categoryRow 對齊標準設計語言：
//   1. recentRow：圖示圓 40pt → 44pt + LinearGradient 漸層填充 + 陰影（對齊 incomeRow / ExpenseRow 規格）；
//      分類標籤從純文字升級為彩色 Capsule 膠囊（對齊 incomeRow.category Capsule 規格）；
//      金額字型升為 .system(size:15, design:.rounded) + contentTransition；
//      日期改為小型 Capsule 膠囊（tertiarySystemFill 底），提升視覺層次。
//   2. categoryRow：圖示圓 32pt → 40pt + LinearGradient 漸層填充 + 細邊框（對齊
//      LifeOverviewView.categoryBreakdownSection 40pt 標準統計圖示規格）；
//      百分比從純 caption2 文字升為彩色 Capsule 膠囊（含細邊框），對齊 LifeOverviewView 規格；
//      金額字型升為 .system(size:14, design:.rounded)，與列表行整體加重一致。
// [2026-06 v3] 五處細節補齊，對齊全 App 最高視覺均值：
//   1. summaryCard 圖示圓：30pt 純色 opacity.0.16 → 32pt LinearGradient (0.20→0.08) + stroke border (0.18)，
//      對齊 categoryRow / breakdownLegendItem 漸層圓規格。
//   2. monthlyBalanceCard 頂部玻璃光澤：ZStack 背景最上層加 LinearGradient [white.opacity(0.18), clear]
//      top→center，讓英雄卡頂部呈現玻璃反光感，對齊 FinanceOverviewView totalAssetsCard 規格。
//   3. categoryRow 比例條 glow overlay：彩色 Capsule 條上疊加 LinearGradient
//      [white.opacity(0.28), clear, black.opacity(0.08)] top→bottom，增加立體感，
//      對齊 ChartView.expenseTypeBreakdown 彩條及 VariableExpenseView.monthSummaryHeader 雙軌進度條規格。
//   4. recentRow 圖示圓 stroke border：補 Circle().stroke(accentColor.opacity(0.18), lineWidth:0.75)，
//      對齊 categoryRow 的 stroke 規格，兩個 Section 圖示圓視覺一致。
//   5. todayCard 右側計數膠囊：有支出時顯示「今日 N 筆」灰底膠囊（取代空白 Spacer），
//      對齊 recentTransactionsSection / categoryBreakdownSection 計數膠囊設計語言。
// [2026-06 v4] 本次美化方向（KPI 橫列補齊 + 設計細節對齊）：
//   6. monthlyBalanceCard KPI 橫列：在頂部收入/支出行與分隔線之間補入三格 KPI
//      （今日花費 / 日均支出 / 本月固定），對齊 IncomeView / VariableExpenseView /
//      FixedExpenseView summaryHeader KPI 三格設計規格；
//      OverviewView 原是全 App 唯一缺少 KPI 橫列的英雄卡，此次補齊均值。
//   7. monthlyBalanceCard 頂部「本月收入」/「本月支出」金額：補入 minimumScaleFactor(0.72) +
//      lineLimit(1) + contentTransition(.numericText())，防止大數字截斷並加平滑數字動畫，
//      對齊 IncomeView.summaryHeader 大字已有的規格（title3 系列原本缺失）。
//   8. monthlyBalanceCard 背景：補入第三顆散景圓（55pt white.opacity(0.06) 中右 blur 8），
//      對齊 IncomeView / VariableExpenseView summaryHeader 三顆散景圓設計規格，
//      讓 OverviewView 英雄卡散景層次與其他頁面完全一致。
//   9. recentRow 分類 Capsule 膠囊：補入 overlay Capsule stroke 細邊框（accent.opacity(0.22) 0.6pt），
//      對齊 ExpenseRow / incomeRow category Capsule 膠囊設計規格，
//      消除最近交易行分類標籤無邊框、其他列表行有邊框的視覺不均衡。
// [2026-07 v5] 承接 v4 留下的漏網之魚：monthlyBalanceCard「收支餘額」大字補入
//   lineLimit(1) + minimumScaleFactor(0.6)。v4 已補齊同卡「本月收入」/「本月支出」兩個子
//   欄位的防截斷規格，但這裡是三個數字中最寬的一個（多了 "+"／"-" 符號，且金額本身也最大），
//   當時被漏掉；比照 LifeOverviewView／LifeRealEstateView／ChildrenResumeView 近期同一輪
//   「英雄卡大字自適應收尾」規格補上，避免大額（含負數）結餘在小螢幕上被截斷。
//   純視覺層調整，balance／isPositive 等既有商業邏輯完全未變動。
//   （下次美化本檔案時，可轉往其他仍留有待辦的畫面）

struct OverviewView: View {
    @EnvironmentObject var store: ExpenseStore
    @State private var showAddVariable = false
    @State private var showAddFixed = false
    @State private var showAddStock = false
    @State private var showAddRealEstate = false
    @State private var boardAppeared = false
    @State private var recentListAppeared = false
    @State private var categoryListAppeared = false
    /// 看板的數字一次算好（.task(id: store.modifyID)），不要在 body 裡掃支出
    @State private var board = OverviewBoardData()
    /// 從「未來 7 天要扣」點進來編輯的那筆固定支出
    @State private var editingFixed: Expense?
    /// 看板格子點下去切到收入／變動／固定那一頁（跟頂部子功能列同一個值）
    @AppStorage("expense_feature") private var expenseFeatureRaw: String = ExpenseFeature.overview.rawValue
    @State private var cachedRecentItems: [RecentItem] = []
    @State private var cachedCategoryTotals: [(category: VariableCategory, amount: Double)] = []

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "TWD"
        f.currencySymbol = "NT$"
        f.maximumFractionDigits = 0
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // [v25.522] 原本的「收支結餘英雄卡＋三格摘要＋今日卡」換成一塊看板
                    // （OverviewBoard.swift）；v25.523 重做：還能花多少、本月支出走勢圖、四格，
                    // 「未來 7 天要扣」另外一塊放在看板下面。
                    VStack(spacing: 14) {
                        OverviewBoard(
                            data: board,
                            openIncome: { open(.income) },
                            openVariable: { open(.variable) })
                        if !board.upcoming.isEmpty {
                            OverviewUpcomingCard(bills: board.upcoming) { id in
                                editingFixed = store.expenses.first { $0.id == id }
                            }
                        }
                    }
                        .padding(.horizontal)
                        .opacity(boardAppeared ? 1 : 0)
                        .offset(y: boardAppeared ? 0 : 20)
                        .onAppear {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                                boardAppeared = true
                            }
                        }
                        .onDisappear {
                            boardAppeared = false
                        }

                    categoryBreakdownSection

                    recentTransactionsSection
                        .onAppear {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.15)) {
                                recentListAppeared = true
                            }
                        }
                        .onDisappear {
                            recentListAppeared = false
                        }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("總覽")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    quickAddMenu
                }
            }
            .sheet(isPresented: $showAddVariable) { AddExpenseView(expenseType: .variable) }
            .sheet(isPresented: $showAddFixed) { AddExpenseView(expenseType: .fixed) }
            .sheet(isPresented: $showAddStock) { AddStockView() }
            .sheet(isPresented: $showAddRealEstate) { AddRealEstateView() }
            .sheet(item: $editingFixed) { e in AddExpenseView(expenseType: .fixed, editingExpense: e) }
            .task(id: store.modifyID) {
                cachedRecentItems = buildRecentItems()
                cachedCategoryTotals = store.variableCategoryTotals()
                // .task 每次出現都會重跑（切回這頁、跨過午夜再打開），日期相關的數字跟著更新
                board = OverviewBoardData.build(store: store)
            }
        }
    }

    private var quickAddMenu: some View {
        Menu {
            Button { showAddVariable = true } label: { Label("變動支出", systemImage: "arrow.up.arrow.down.circle.fill") }
            Button { showAddFixed = true } label: { Label("固定支出", systemImage: "pin.circle.fill") }
            Button { showAddStock = true } label: { Label("股票", systemImage: "chart.line.uptrend.xyaxis") }
            Button { showAddRealEstate = true } label: { Label("房地產", systemImage: "building.2.fill") }
        } label: {
            Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
        }
    }

    /// 看板格子 → 切到那一頁（同頂部子功能列、同左右滑的動畫）
    private func open(_ feature: ExpenseFeature) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.70)) {
            expenseFeatureRaw = feature.rawValue
        }
    }

    // MARK: - 分類配色（委派給 VariableCategory.accentColor）
    private func categoryColor(_ category: VariableCategory) -> Color {
        category.accentColor
    }

    // MARK: - 分類支出（帶比例條）

    private var categoryBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            let categoryTotals = cachedCategoryTotals
            let maxAmount = categoryTotals.map(\.amount).max() ?? 1
            // variableCategoryTotals() 已過濾本月變動支出，直接加總即可，
            // 避免在每個 categoryRow 內重複呼叫 currentMonthVariableTotal（O(n)×列數）
            let totalVar = categoryTotals.reduce(0) { $0 + $1.amount }

            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 20)
                Text("本月變動支出分類")
                    .font(.subheadline.weight(.bold))
                Spacer()
                if !categoryTotals.isEmpty {
                    Text("\(categoryTotals.count) 項")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.green.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.green.opacity(0.22), lineWidth: 0.75))
                }
            }
            .padding(.horizontal)

            if categoryTotals.isEmpty {
                emptyPlaceholder(
                    icon: "chart.bar.xaxis",
                    title: "尚無分類紀錄",
                    subtitle: "新增變動支出後顯示分類統計"
                )
                .padding(.horizontal)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(categoryTotals.enumerated()), id: \.element.category.rawValue) { idx, item in
                        categoryRow(item: item, maxAmount: maxAmount, totalVar: totalVar)
                            .opacity(categoryListAppeared ? 1 : 0)
                            .offset(y: categoryListAppeared ? 0 : 14)
                            .animation(
                                .spring(response: 0.45, dampingFraction: 0.82)
                                    .delay(0.06 * Double(idx)),
                                value: categoryListAppeared
                            )

                        if idx < categoryTotals.count - 1 {
                            Divider().padding(.leading, 46)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
                .padding(.horizontal)
                .onAppear {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05)) {
                        categoryListAppeared = true
                    }
                }
                .onDisappear {
                    categoryListAppeared = false
                }
            }
        }
    }

    private func categoryRow(item: (category: VariableCategory, amount: Double), maxAmount: Double, totalVar: Double) -> some View {
        let ratio = maxAmount > 0 ? item.amount / maxAmount : 0
        let pct = totalVar > 0 ? Int(item.amount / totalVar * 100) : 0
        let accent = categoryColor(item.category)

        return VStack(spacing: 8) {
            HStack(spacing: 12) {
                // 40pt 漸層圖示圓 + 細邊框（對齊 LifeOverviewView.categoryBreakdownSection 統計情境規格）
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.20), accent.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    Circle()
                        .stroke(accent.opacity(0.22), lineWidth: 1.2)
                        .frame(width: 40, height: 40)
                    Image(systemName: item.category.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                }
                Text(item.category.rawValue)
                    .font(.subheadline)
                Spacer()
                // 金額 + 百分比彩色膠囊（對齊 LifeOverviewView categoryBreakdownSection 規格）
                HStack(spacing: 8) {
                    Text(smartCurrency(item.amount))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("\(pct)%")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(accent.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
                }
            }

            // 漸層比例進度條（高度 6pt，圓角 3pt，對齊 FinanceOverviewView.allocationSection 規格）
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemFill))
                        .frame(height: 6)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.55)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * ratio, height: 6)
                        .animation(.spring(response: 0.6, dampingFraction: 0.78), value: ratio)
                    // [v3] glow overlay：彩條頂部白色光澤 + 底部柔化，對齊 ChartView.expenseTypeBreakdown 規格
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.28), .clear, .black.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: geo.size.width * ratio, height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - 最近交易

    private struct RecentItem: Identifiable {
        let id: UUID
        let title: String
        let icon: String
        let category: String
        let amount: Double
        let date: Date
        let isIncome: Bool
    }

    private var recentItems: [RecentItem] { cachedRecentItems }

    private func buildRecentItems() -> [RecentItem] {
        // 「最近交易」只顯示已發生的紀錄；排除未來日期（如尚未開始的分階段貸款等固定支出投射），
        // 避免未來項目因日期最大而排到最前、擠掉真正的近期消費。
        let now = Date()
        let recentExp = store.expenses.filter { $0.date <= now }.sorted { $0.date > $1.date }.prefix(5).map { e in
            RecentItem(id: e.id, title: e.title, icon: e.categoryIcon,
                       category: e.categoryName, amount: e.amount, date: e.date, isIncome: false)
        }
        let recentInc = store.incomes.filter { $0.date <= now }.sorted { $0.date > $1.date }.prefix(5).map { i in
            RecentItem(id: i.id, title: i.title, icon: i.category.icon,
                       category: i.category.rawValue, amount: i.amount, date: i.date, isIncome: true)
        }
        return Array((recentExp + recentInc).sorted { $0.date > $1.date }.prefix(5))
    }

    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            let items = recentItems
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 20)
                Text("最近交易")
                    .font(.subheadline.weight(.bold))
                Spacer()
                if !items.isEmpty {
                    Text("\(items.count) 筆")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.green.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.green.opacity(0.22), lineWidth: 0.75))
                }
            }
            .padding(.horizontal)

            if items.isEmpty {
                emptyPlaceholder(
                    icon: "list.bullet.rectangle",
                    title: "尚無交易紀錄",
                    subtitle: "新增收入或支出後顯示於此"
                )
                .padding(.horizontal)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        recentRow(item)
                            .opacity(recentListAppeared ? 1 : 0)
                            .offset(y: recentListAppeared ? 0 : 14)
                            .animation(
                                .spring(response: 0.45, dampingFraction: 0.80)
                                    .delay(0.06 * Double(idx)),
                                value: recentListAppeared
                            )

                        if idx < items.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
                .padding(.horizontal)
            }
        }
    }

    private func recentRow(_ item: RecentItem) -> some View {
        // 收入用綠色，支出用紅色（與其他列表頁配色一致）
        let accentColor: Color = item.isIncome ? .green : Color(red: 0.90, green: 0.25, blue: 0.25)

        return HStack(spacing: 12) {
            // 44pt 漸層圖示圓 + 陰影（對齊 incomeRow / ExpenseRow 圖示圓規格）
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accentColor.opacity(0.22), accentColor.opacity(0.09)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .shadow(color: accentColor.opacity(0.22), radius: 6, x: 0, y: 3)
                // [v3] stroke border：補齊 categoryRow 的邊框規格，兩 Section 圖示圓視覺一致
                Circle()
                    .stroke(accentColor.opacity(0.18), lineWidth: 0.75)
                    .frame(width: 44, height: 44)
                Image(systemName: item.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accentColor)
            }

            // 標題 + 彩色分類膠囊（對齊 incomeRow.category Capsule 規格）
            VStack(alignment: .leading, spacing: 4) {
                // [v25.520] 交易名稱過長改跑馬燈（原本切成「…」）
                MarqueeText(item.title)
                    .font(.subheadline.weight(.semibold))
                // [v4] 補入 overlay stroke 細邊框，對齊 ExpenseRow / incomeRow category Capsule 規格
                Text(item.category)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(accentColor.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(accentColor.opacity(0.22), lineWidth: 0.6))
            }

            Spacer(minLength: 4)

            // 金額 + 日期小膠囊
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(item.isIncome ? "+" : "-")\(smartCurrency(item.amount))")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(accentColor)
                    .contentTransition(.numericText())
                Text(formatDate(item.date))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - 空狀態元件

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
                    .frame(width: 70, height: 70)
                Circle()
                    .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
                    .frame(width: 70, height: 70)
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color(.secondaryLabel))
            }
            VStack(spacing: 6) {
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
        .padding(.vertical, 32)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Double) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: value)) ?? "NT$0"
    }

    // 【美化 2026-06】加入億量級：≥1億 → "X.X 億"；≥1萬 → "X.X 萬"；<1萬 → NT$X
    private func smartCurrency(_ value: Double) -> String {
        let absVal = abs(value)
        if absVal >= 100_000_000 {                               // ≥ 1億
            return String(format: "%.1f 億", value / 100_000_000)
        }
        if absVal >= 10_000 {                                    // ≥ 1萬
            let wan = value / 10_000
            // %.1f 格式化後若捨入到 10000，改以億顯示，避免「10000.0萬」
            if abs(wan) >= 9_999.95 { return String(format: "%.1f 億", value / 100_000_000) }
            return String(format: abs(wan) >= 10 ? "%.1f 萬" : "%.2f 萬", wan)
        }
        return formatCurrency(value)
    }

    private func formatDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return Self.timeFormatter.string(from: date) }
        if cal.isDateInYesterday(date) { return "昨天" }
        return Self.shortDateFormatter.string(from: date)
    }
}

#Preview {
    OverviewView()
        .environmentObject(ExpenseStore())
}
