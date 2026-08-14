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
    @State private var appearedCards: Set<String> = []
    @State private var ringPulse = false
    @State private var ringPulseTask: Task<Void, Never>?
    @State private var recentListAppeared = false
    @State private var categoryListAppeared = false
    @State private var todayCardAppeared = false
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

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月"
        return f
    }()

    private var displayedIncome: Double {
        store.hasCurrentMonthIncome ? store.currentMonthIncomeTotal : store.estimatedMonthlyIncome
    }

    private var isEstimated: Bool {
        !store.hasCurrentMonthIncome && store.estimatedMonthlyIncome > 0
    }

    // 本月過了幾天 / 共幾天
    private var monthProgress: Double {
        let cal = Calendar.current
        let now = Date()
        let day = Double(cal.component(.day, from: now))
        let range = cal.range(of: .day, in: .month, for: now)
        let total = Double(range?.count ?? 30)
        return min(day / total, 1.0)
    }

    var body: some View {
        // [效能] displayedIncome／isEstimated 各自都會掃描 incomes 陣列（isEstimated 內部
        // 還會呼叫 estimatedMonthlyIncome 逐月重算），原本 monthlyBalanceCard 與下方
        // summaryCard 各自獨立存取，同一次 body render 會重複觸發 4~6 次相同掃描；
        // 在此一次性計算後以參數傳入，兩處共用同一份結果。
        let income = displayedIncome
        let estimated = isEstimated
        return NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 0) {
                        monthlyBalanceCard(income: income, isEstimated: estimated)
                            .padding(.horizontal)
                        // 超支警示：emoji 小字提示掛在卡片下方（正常時不顯示）
                        HeroOverspendHint(
                            ratio: income > 0 ? store.currentMonthTotal / income : 0,
                            monthProgress: monthProgress)
                    }
                        .opacity(appearedCards.contains("header") ? 1 : 0)
                        .offset(y: appearedCards.contains("header") ? 0 : 20)
                        .onAppear {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                                _ = appearedCards.insert("header")
                            }
                        }
                        .onDisappear {
                            appearedCards.remove("header")
                        }

                    HStack(alignment: .top, spacing: 12) {
                        summaryCard(
                            title: estimated ? "收入 (預估)" : "收入",
                            amount: income,
                            icon: "banknote.fill",
                            color: .green,
                            key: "income"
                        )
                        summaryCard(
                            title: "變動支出",
                            amount: store.currentMonthVariableTotal,
                            icon: "arrow.up.arrow.down.circle.fill",
                            color: .orange,
                            key: "variable"
                        )
                        summaryCard(
                            title: "固定支出",
                            amount: store.currentMonthFixedTotal,
                            icon: "pin.circle.fill",
                            color: .blue,
                            key: "fixed"
                        )
                    }
                    .padding(.horizontal)

                    todayCard
                        .padding(.horizontal)
                        .opacity(todayCardAppeared ? 1 : 0)
                        .offset(y: todayCardAppeared ? 0 : 16)
                        .onAppear {
                            withAnimation(.spring(response: 0.52, dampingFraction: 0.80).delay(0.10)) {
                                todayCardAppeared = true
                            }
                            // 先重置為 false，確保即使殘留 Task 搶先將 ringPulse 設為 true，
                            // 下方的 Task 仍能產生 false→true 的變化讓 animation(value:) 重新作用
                            ringPulse = false
                            ringPulseTask?.cancel()
                            ringPulseTask = Task {
                                try? await Task.sleep(nanoseconds: 600_000_000)
                                guard !Task.isCancelled else { return }
                                ringPulse = true
                            }
                        }
                        .onDisappear {
                            // 重置旗標，讓下次 onAppear 時脈衝動畫與進場動畫都能重新觸發
                            ringPulseTask?.cancel()
                            ringPulse = false
                            todayCardAppeared = false
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
            .task(id: store.modifyID) {
                cachedRecentItems = buildRecentItems()
                cachedCategoryTotals = store.variableCategoryTotals()
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

    // MARK: - KPI 格（對齊 IncomeView / VariableExpenseView / FixedExpenseView kpiCell 規格）


    // MARK: - 本月收支摘要卡片

    private func monthlyBalanceCard(income: Double, isEstimated: Bool) -> some View {
        // 一次計算 currentMonthTotal（含兩次 O(n) 掃描），避免透過原先 spendingRatio /
        // spendingBarColor 兩個 struct-level computed property 在 body 內重複呼叫 10+ 次
        let total = store.currentMonthTotal
        let balance = income - total
        let isPositive = balance >= 0
        let spendingRatio = income > 0 ? min(total / income, 1.0) : 0.0
        let barColor: Color = {
            if spendingRatio > HeroOverspendHint.dangerRatio { return Color.red.opacity(0.85) }
            if spendingRatio > monthProgress + HeroOverspendHint.warnLead {
                return Color(red: 1.0, green: 0.65, blue: 0.22).opacity(0.90)
            }
            return .white.opacity(0.85)
        }()
        // [v4] KPI 橫列計算：一次讀取，避免 closure 內重複呼叫 store
        let day = Calendar.current.component(.day, from: Date())
        let todayTotalKPI = store.todayTotal
        let fixedTotalKPI = store.currentMonthFixedTotal

        return VStack(spacing: 0) {
            // 頂部：收入 vs 支出
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(isEstimated ? "本月收入（預估）" : "本月收入")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                        if isEstimated {
                            Text("預估")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.white.opacity(0.22))
                                .clipShape(Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    // [v4] 補入 minimumScaleFactor + lineLimit + contentTransition，防大數字截斷
                    Text(smartCurrency(income))
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .contentTransition(.numericText())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("本月支出")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                    // [v4] 補入 minimumScaleFactor + lineLimit + contentTransition
                    Text(smartCurrency(total))
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .contentTransition(.numericText())
                }
            }

            // [v4] KPI 橫列：今日花費 / 日均支出 / 本月固定，
            // 對齊 IncomeView / VariableExpenseView / FixedExpenseView summaryHeader KPI 三格規格
            HStack(spacing: 0) {
                HeroKpiCell(label: "今日花費", value: smartCurrency(todayTotalKPI))
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 0.5, height: 28)
                HeroKpiCell(label: "日均支出", value: smartCurrency(total / Double(max(day, 1))))
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 0.5, height: 28)
                HeroKpiCell(label: "本月固定", value: smartCurrency(fixedTotalKPI))
            }
            .padding(.vertical, 10)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.top, 12)

            // 分隔線
            Rectangle()
                .fill(.white.opacity(0.2))
                .frame(height: 0.5)
                .padding(.vertical, 14)

            // 收支餘額
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("收支餘額")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                        if isEstimated {
                            Text("預估")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.white.opacity(0.22))
                                .clipShape(Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    Text(currentMonthString())
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                // [v5] 補入 minimumScaleFactor + lineLimit，收支餘額是本卡三個數字中最寬的一個
                // （"+"／"-" 符號 + 金額），v4 只補了收入／支出兩個子欄位，漏了這裡，
                // 大額結餘（含負數）在小螢幕上原本沒有防截斷保護。
                Text((isPositive ? "+" : "") + smartCurrency(balance))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(isPositive ? .white : Color(red: 1.0, green: 0.78, blue: 0.75))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .shadow(
                        color: isPositive ? .clear : Color.red.opacity(0.45),
                        radius: 8, x: 0, y: 2
                    )
            }

            // 雙軌進度條：月進度（上）+ 支出比例（下，附月進度指示針）
            if income > 0 {
                VStack(spacing: 5) {
                    // ① 月進度軌（薄軌，半透明白）
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.12))
                                .frame(height: 3)
                            Capsule()
                                .fill(.white.opacity(0.44))
                                .frame(width: geo.size.width * monthProgress, height: 3)
                                .animation(.spring(response: 0.7, dampingFraction: 0.8), value: monthProgress)
                        }
                    }
                    .frame(height: 3)

                    // ② 支出比例軌（厚軌 + 月進度指示針）
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.18))
                                .frame(height: 6)
                            Capsule()
                                .fill(barColor)
                                .frame(width: geo.size.width * spendingRatio, height: 6)
                                .animation(.spring(response: 0.7, dampingFraction: 0.8), value: spendingRatio)
                            // 月進度指示針（細白豎棒，指示月份走到哪）
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
                        Text("支出 \(Int(spendingRatio * 100))%")
                        .font(.caption2)
                        .foregroundStyle(spendingRatio > monthProgress + HeroOverspendHint.warnLead
                                         ? (spendingRatio > HeroOverspendHint.dangerRatio
                                            ? Color(red: 1.0, green: 0.78, blue: 0.75)
                                            : Color(red: 1.0, green: 0.90, blue: 0.55))
                                         : .white.opacity(0.60))
                        Spacer()
                        Text("月進度 \(Int(monthProgress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.60))
                    }
                }
                .padding(.top, 12)
            }
        }
        .padding(20)
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
                // 裝飾性散景圓，增加卡片層次感
                Circle()
                    .fill(.white.opacity(0.13))
                    .frame(width: 140, height: 140)
                    .offset(x: 90, y: -55)
                    .blur(radius: 14)
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 90, height: 90)
                    .offset(x: -70, y: 55)
                    .blur(radius: 10)
                // [v4] 第三顆散景圓（中右微光），對齊 IncomeView / VariableExpenseView 三顆散景設計規格
                Circle()
                    .fill(.white.opacity(0.06))
                    .frame(width: 55, height: 55)
                    .offset(x: 30, y: 42)
                    .blur(radius: 8)
                // [v3] 頂部玻璃光澤：LinearGradient white→clear，對齊 FinanceOverviewView totalAssetsCard 規格
                LinearGradient(
                    colors: [.white.opacity(0.18), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.07, green: 0.50, blue: 0.38).opacity(0.42), radius: 18, x: 0, y: 9)
    }

    // MARK: - 摘要小卡

    private func cardDelay(_ key: String) -> Double {
        switch key {
        case "income":   return 0.08
        case "variable": return 0.16
        case "fixed":    return 0.24
        default:         return 0.0
        }
    }

    private func summaryCard(title: String, amount: Double, icon: String, color: Color, key: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 彩色頂端條
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.55)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(height: 4)
                .padding(.bottom, 10)

            HStack(spacing: 6) {
                // [v3] 圖示圓：純色 opacity.0.16 → LinearGradient (0.20→0.08) + stroke border，對齊 categoryRow 規格
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.20), color.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                    Circle()
                        .stroke(color.opacity(0.18), lineWidth: 0.75)
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            Text(smartCurrency(amount))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(
            ZStack {
                Color(.systemBackground)
                color.opacity(0.04)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(0.12), lineWidth: 0.75)
        )
        .shadow(color: color.opacity(0.13), radius: 10, x: 0, y: 4)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
        .opacity(appearedCards.contains(key) ? 1 : 0)
        .offset(y: appearedCards.contains(key) ? 0 : 18)
        .onAppear {
            withAnimation(.spring(response: 0.50, dampingFraction: 0.78).delay(cardDelay(key))) {
                _ = appearedCards.insert(key)
            }
        }
    }

    // MARK: - 今日花費

    private var todayCard: some View {
        let cal = Calendar.current
        let day = cal.component(.day, from: Date())
        let weekday = cal.component(.weekday, from: Date())
        let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
        let weekdayIdx = weekday - 1
        let weekdayStr = weekdays.indices.contains(weekdayIdx) ? weekdays[weekdayIdx] : ""
        let todayTotal = store.todayTotal
        let hasSpending = todayTotal > 0
        // [v3] 今日交易筆數，用於右側計數膠囊
        let todayCount = store.expenses.filter { cal.isDateInToday($0.date) }.count

        return HStack(spacing: 0) {
            // 左側綠色強調條
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [.green, .green.opacity(0.40)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4)
                .padding(.vertical, 10)
                .padding(.trailing, 14)

            // 日期圓形徽章
            ZStack {
                // 向外擴散的脈衝光環
                Circle()
                    .stroke(Color.green.opacity(ringPulse ? 0 : 0.42), lineWidth: 1.5)
                    .frame(width: 52, height: 52)
                    .scaleEffect(ringPulse ? 1.55 : 1.0)
                    .animation(
                        .easeOut(duration: 1.6).repeatForever(autoreverses: false),
                        value: ringPulse
                    )
                Circle()
                    .stroke(Color.green.opacity(ringPulse ? 0 : 0.20), lineWidth: 1)
                    .frame(width: 52, height: 52)
                    .scaleEffect(ringPulse ? 1.85 : 1.0)
                    .animation(
                        .easeOut(duration: 1.6).delay(0.25).repeatForever(autoreverses: false),
                        value: ringPulse
                    )
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.green.opacity(0.22), .green.opacity(0.07)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                VStack(spacing: 0) {
                    Text("\(day)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                    Text("週\(weekdayStr)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.green.opacity(0.7))
                }
            }
            .padding(.trailing, 14)

            VStack(alignment: .leading, spacing: 4) {
                Text("今日花費")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(smartCurrency(todayTotal))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(hasSpending ? .primary : Color.green.opacity(0.5))
                    .contentTransition(.numericText())
            }

            Spacer()

            // [v3] 右側情境膠囊：有支出→ N 筆計數膠囊；零支出→成就徽章
            if hasSpending {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 11, weight: .semibold))
                    Text("今日 \(todayCount) 筆")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill))
                .clipShape(Capsule())
            } else {
                // 零支出成就徽章：綠色膠囊 + 圖示
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("今日零支出")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.10))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.green.opacity(0.20), lineWidth: 0.75)
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(
            ZStack {
                Color(.systemBackground)
                // 左上角淡綠色散景光暈，增加卡片層次感
                Circle()
                    .fill(Color.green.opacity(0.06))
                    .frame(width: 110, height: 110)
                    .offset(x: -10, y: -35)
                    .blur(radius: 18)
                // 右下補光
                Circle()
                    .fill(Color.green.opacity(0.04))
                    .frame(width: 70, height: 70)
                    .offset(x: 80, y: 32)
                    .blur(radius: 12)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.green.opacity(0.10), lineWidth: 0.75)
        )
        .shadow(color: Color.green.opacity(0.12), radius: 14, x: 0, y: 6)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
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
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
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

    private func currentMonthString() -> String {
        Self.monthFormatter.string(from: Date())
    }
}

#Preview {
    OverviewView()
        .environmentObject(ExpenseStore())
}
