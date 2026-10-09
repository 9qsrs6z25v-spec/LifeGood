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
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var financeStore: FinanceStore
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
    /// [v25.524] 最近交易（已經組好成卡片要寫的字）與本月各分類
    @State private var cachedRecent: [RecentEntry] = []
    @State private var categoryStats: [CategoryStat] = []
    /// 點最近交易的一筆：先看那一筆的卡片（跟各頁點一筆一樣）
    @State private var previewVariable: Expense?
    @State private var previewFixed: Expense?
    @State private var previewIncome: Income?
    /// 點分類明信片：切到變動支出並只看那一類（VariableExpenseView 讀到就清掉）
    @AppStorage(VariableExpenseView.filterRequestKey) private var variableFilterRequest = ""

    private static let badgeFormatter: DateFormatter = {
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
            .sheet(item: $previewVariable) { e in FinanceItemCard(target: .variableExpense(e.id)) }
            .sheet(item: $previewFixed) { e in FixedExpenseCard(expense: e) }
            .sheet(item: $previewIncome) { i in FinanceItemCard(target: .income(i.id)) }
            .task(id: store.modifyID) {
                cachedRecent = buildRecent()
                categoryStats = Self.buildCategoryStats(store)
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

    // MARK: - 本月花在哪裡（v25.524：分類明信片）
    //
    // 使用者：「項目的藝術感跟質感都差太多了」。原本是一張白卡上一列一列的圖示圓＋進度條；
    // 改成最上面一條分類比例的彩帶，下面兩欄「明信片」：每一類一張，上半是那一類的插畫
    // 與手寫英文字（MoneyArt.swift），下半是金額、占比、筆數、比上月同期。
    // 點一張 → 切到變動支出、只看那一類。

    /// 一個分類這個月的數字
    struct CategoryStat: Identifiable, Equatable {
        let category: VariableCategory
        let amount: Double
        let count: Int
        /// 上個月到同一天為止（月初跟上個月整個月比，每一類都會是「少很多」）
        let lastMonth: Double
        var id: String { category.rawValue }
    }

    static func buildCategoryStats(_ store: ExpenseStore, now: Date = Date()) -> [CategoryStat] {
        let cal = Calendar.current
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)),
              let lastStart = cal.date(byAdding: .month, value: -1, to: monthStart) else { return [] }
        let day = cal.component(.day, from: now)
        let lastDays = cal.range(of: .day, in: .month, for: lastStart)?.count ?? 30
        let lastCut = cal.date(byAdding: .day, value: min(day, lastDays), to: lastStart) ?? monthStart
        var amount: [VariableCategory: Double] = [:]
        var count: [VariableCategory: Int] = [:]
        var last: [VariableCategory: Double] = [:]
        for e in store.expenses where e.expenseType == .variable {
            let c = e.variableCategory ?? .other
            if cal.isDate(e.date, equalTo: now, toGranularity: .month) {
                amount[c, default: 0] += e.amount
                count[c, default: 0] += 1
            } else if e.date >= lastStart && e.date < lastCut {
                last[c, default: 0] += e.amount
            }
        }
        return amount
            .map { CategoryStat(category: $0.key, amount: $0.value, count: count[$0.key] ?? 0,
                                lastMonth: last[$0.key] ?? 0) }
            .filter { $0.amount > 0 }
            .sorted { a, b in a.amount != b.amount ? a.amount > b.amount : a.id < b.id }
    }

    private var categoryBreakdownSection: some View {
        let stats = categoryStats
        let total = stats.reduce(0) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 10) {
            MoneySectionHeader(title: "本月花在哪裡",
                               trailing: stats.isEmpty ? nil : "\(stats.count) 類・" + total.ntdWanString)
            if stats.isEmpty {
                emptyPlaceholder(
                    icon: "chart.bar.xaxis",
                    title: "尚無分類紀錄",
                    subtitle: "新增變動支出後顯示分類統計"
                )
            } else {
                MoneyShareRibbon(segments: stats.map {
                    MoneyShareRibbon.Segment(theme: MoneyArtTheme.of($0.category), value: $0.amount)
                })
                .padding(.bottom, 2)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                          spacing: 10) {
                    ForEach(Array(stats.enumerated()), id: \.element.id) { idx, s in
                        Button {
                            openCategory(s.category)
                        } label: {
                            MoneyCategoryPostcard(
                                theme: MoneyArtTheme.of(s.category),
                                name: s.category.rawValue,
                                amount: s.amount.ntdWanString,
                                share: total > 0 ? s.amount / total : 0,
                                count: s.count,
                                change: s.lastMonth > 0 ? MoneyFormat.change(s.amount, vs: s.lastMonth) : nil,
                                changeTone: MoneyTone.spendingChange(s.amount, vs: s.lastMonth))
                        }
                        .buttonStyle(MoneyPressStyle())
                        .accessibilityHint("切到變動支出，只看這一類")
                        .opacity(categoryListAppeared ? 1 : 0)
                        .offset(y: categoryListAppeared ? 0 : 14)
                        .animation(
                            .spring(response: 0.45, dampingFraction: 0.82)
                                .delay(0.05 * Double(min(idx, 8))),
                            value: categoryListAppeared
                        )
                    }
                }
            }
        }
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

    private func openCategory(_ category: VariableCategory) {
        variableFilterRequest = category.rawValue
        open(.variable)
    }

    // MARK: - 最近交易（v25.524：交易卡）

    private enum RecentTarget: Equatable {
        case variable(UUID), fixed(UUID), income(UUID)
    }

    private struct RecentEntry: Identifiable, Equatable {
        let item: MoneyItem
        let target: RecentTarget
        var id: UUID { item.id }
    }

    private func buildRecent() -> [RecentEntry] {
        // 「最近交易」只顯示已發生的紀錄；排除未來日期（如尚未開始的分階段貸款等固定支出投射），
        // 避免未來項目因日期最大而排到最前、擠掉真正的近期消費。
        let now = Date()
        let ctx = MoneyItemContext(lifeStore: lifeStore, store: store)
        var list: [(date: Date, entry: RecentEntry)] = []
        for e in store.expenses.filter({ $0.date <= now }).sorted(by: { $0.date > $1.date }).prefix(5) {
            let badge = Self.badgeFormatter.string(from: e.date)
            if e.expenseType == .fixed {
                var item = MoneyItem.fixed(e, ctx: ctx, financeStore: financeStore, now: now)
                item.badge = badge
                list.append((e.date, RecentEntry(item: item, target: .fixed(e.id))))
            } else {
                list.append((e.date, RecentEntry(item: MoneyItem.expense(e, ctx: ctx, badge: badge),
                                                 target: .variable(e.id))))
            }
        }
        for i in store.incomes.filter({ $0.date <= now }).sorted(by: { $0.date > $1.date }).prefix(5) {
            let item = MoneyItem.income(i, ctx: ctx, badge: Self.badgeFormatter.string(from: i.date), now: now)
            list.append((i.date, RecentEntry(item: item, target: .income(i.id))))
        }
        return Array(list.sorted { $0.date > $1.date }.prefix(5).map { $0.entry })
    }

    private func openRecent(_ target: RecentTarget) {
        switch target {
        case .variable(let id): previewVariable = store.expenses.first { $0.id == id }
        case .fixed(let id): previewFixed = store.expenses.first { $0.id == id }
        case .income(let id): previewIncome = store.incomes.first { $0.id == id }
        }
    }

    private var recentTransactionsSection: some View {
        let entries = cachedRecent
        return VStack(alignment: .leading, spacing: 10) {
            MoneySectionHeader(title: "最近交易", trailing: entries.isEmpty ? nil : "\(entries.count) 筆")
            if entries.isEmpty {
                emptyPlaceholder(
                    icon: "list.bullet.rectangle",
                    title: "尚無交易紀錄",
                    subtitle: "新增收入或支出後顯示於此"
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                        Button {
                            openRecent(entry.target)
                        } label: {
                            MoneyItemCard(item: entry.item)
                        }
                        .buttonStyle(MoneyPressStyle())
                        .accessibilityHint("點兩下打開這一筆")
                        .opacity(recentListAppeared ? 1 : 0)
                        .offset(y: recentListAppeared ? 0 : 14)
                        .animation(
                            .spring(response: 0.45, dampingFraction: 0.80)
                                .delay(0.06 * Double(idx)),
                            value: recentListAppeared
                        )
                    }
                }
            }
        }
        .padding(.horizontal)
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
}

#Preview {
    OverviewView()
        .environmentObject(ExpenseStore())
}
