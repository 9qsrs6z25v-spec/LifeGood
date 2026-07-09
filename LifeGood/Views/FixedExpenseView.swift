import SwiftUI

// MARK: - 美化紀錄（FixedExpenseView）
// [2026-06 v1] 本次美化方向：
//   1. 補 .navigationBarTitleDisplayMode(.large) 與其他主要列表頁對齊
//   2. 空狀態：加入雙層脈衝光環動畫（對齊 VariableExpenseView emptyStateView 規格）
//   3. 分類 Section：加入交錯進場動畫（對齊 OverviewView categoryRow 規格）
//   4. categoryHeader：新增項目計數膠囊徽章，資訊密度與 daySectionHeader 對齊
//   5. FixedExpenseRow：季繳 / 年繳項目在金額下方顯示「月均 NT$X」輔助標籤，
//      幫助使用者快速換算月度負擔，對齊可讀性標準
// [2026-06 v2] 本次美化方向：
//   6. fixedSummaryHeader：新增 KPI 橫列（年度預估 / 日均負擔 / 月節稅），
//      對齊 VariableExpenseView / IncomeView summaryHeader 三格均值規格
//   7. KPI 橫列與進度條之間插入 0.5pt 白色分隔線（對齊 VariableExpenseView 規格）
//   8. 移除舊的內嵌「日均」文字標籤，改由 KPI 橫列統一呈現
//   9. 進度條右端文字改為「剩 X%」，與 VariableExpenseView 對齊
// [2026-06 v3] 本次美化方向（進度條升級）：
//  10. fixedSummaryHeader 進度條從單軌升級為雙軌，對齊
//      OverviewView / IncomeView / VariableExpenseView 標準雙軌規格：
//      ① 上軌（薄 3pt，white.opacity(0.44)）：月份進度；
//      ② 下軌（厚 6pt）：本月固定支出 vs 年均月支出（yearlyEstimate/12），
//         以「月均比率」直觀顯示本月是否因季繳/年繳而高於平均；
//         含月進度指示針（白色 2pt 豎棒），對齊 VariableExpenseView 規格。
//  11. 下軌配色三段：比率 ≤ 1.05 → 白色（正常）；> 1.05 → 暖黃警示（超月均）；
//      > 1.5 → 粉紅警示（本月固定支出顯著偏高，可能為季/年繳集中月）；
//      對齊 IncomeView / VariableExpenseView 警示配色規格。
//  12. 無年度估算（yearlyEstimate = 0）時降級回單軌，確保初次使用相容性。
// [2026-06 v4] 本次美化方向（英雄卡玻璃光澤補齊）：
//  13. fixedSummaryHeader 背景 ZStack 末層加入 LinearGradient [.white.opacity(0.18), .clear]
//      top→center 玻璃反光覆蓋層，對齊 OverviewView.monthlyBalanceCard v3 /
//      IncomeView.summaryHeader v4 / FinanceOverviewView.totalAssetsCard v3 英雄卡玻璃光澤規格；
//      補齊全 App 六張英雄卡中此張缺少的一層光澤（與 VariableExpenseView 同步補齊）。

struct FixedExpenseView: View {
    @EnvironmentObject var store: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var lifeStore: LifeStore
    @State private var showingAddSheet = false
    @State private var previewExpense: Expense?
    @State private var headerAppeared = false
    @State private var emptyIconPulse = false
    @State private var categoryListAppeared = false
    @State private var cachedGroupedByCategory: [(key: FixedCategory, value: [Expense])] = []

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "TWD"
        f.currencySymbol = "NT$"
        f.maximumFractionDigits = 0
        return f
    }()

    private func buildGroupedByCategory() -> [(key: FixedCategory, value: [Expense])] {
        let now = Date()
        let grouped = Dictionary(grouping: store.fixedExpenses) { expense in
            expense.fixedCategory ?? .other
        }
        let sums = grouped.mapValues { exps in
            exps.filter { $0.date <= now }.reduce(0) { $0 + $1.amount }
        }
        return grouped.sorted { sums[$0.key, default: 0] > sums[$1.key, default: 0] }
    }

    var body: some View {
        NavigationStack {
            List {
                // 月固定支出摘要（嵌入 List，與列表一起捲動）
                Section {
                    fixedSummaryHeader
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
                        .onDisappear {
                            headerAppeared = false
                        }
                }

                if store.fixedExpenses.isEmpty {
                    Section {
                        emptyStateView
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    fixedExpenseSections
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("固定支出")
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
            .task(id: store.modifyID) {
                cachedGroupedByCategory = buildGroupedByCategory()
            }
            .sheet(isPresented: $showingAddSheet) {
                AddExpenseView(expenseType: .fixed)
            }
            .sheet(item: $previewExpense) { expense in
                // 點項目先顯示預覽卡片（右上角「編輯」才進入編輯）
                FixedExpenseCard(expense: expense)
            }
        }
    }

    // MARK: - 摘要

    private var monthProgress: Double {
        let cal = Calendar.current
        let now = Date()
        let day = Double(cal.component(.day, from: now))
        let total = Double(cal.range(of: .day, in: .month, for: now)?.count ?? 30)
        return min(day / total, 1.0)
    }

    // KPI 橫列格（對齊 VariableExpenseView / IncomeView kpiCell 規格）
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

    private var fixedSummaryHeader: some View {
        // 先計算一次，避免 store.fixedExpenses（每次都 filter+sort 全部支出）被呼叫 3 次
        let fixed = store.fixedExpenses
        let yearlyEstimate = fixed.reduce(0.0) { total, expense in
            total + expense.amount * Double(occurrencesThisYear(for: expense))
        }
        let count = fixed.count
        let monthlyTotal = store.currentMonthFixedTotal
        let taxTotal = fixed
            .filter { $0.effectivelyTaxDeductible }
            .reduce(0.0) { $0 + monthlyEquivalent($1) }
        let dailyFixed = monthlyTotal / max(1, Double(Calendar.current.component(.day, from: Date())))

        // 雙軌進度條計算（v3 升級）
        let monthlyAvg = yearlyEstimate / 12           // 年均月支出
        let monthVsAvgRatio = monthlyAvg > 0 ? monthlyTotal / monthlyAvg : 0.0
        let barRatio = min(monthVsAvgRatio, 1.0)       // 條寬上限 1.0
        let monthVsAvgBarColor: Color = {
            if monthVsAvgRatio > 1.5 { return Color(red: 1.0, green: 0.78, blue: 0.75).opacity(0.90) }
            if monthVsAvgRatio > 1.05 { return Color(red: 1.0, green: 0.65, blue: 0.22).opacity(0.90) }
            return .white.opacity(0.82)
        }()

        return VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("本月固定支出")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.80))
                    Text(formatCurrency(monthlyTotal))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
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
                    if taxTotal > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "leaf.fill")
                                .font(.system(size: 9))
                            Text("節稅 " + formatCurrency(taxTotal))
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.white.opacity(0.18))
                        .clipShape(Capsule())
                        .foregroundStyle(.white.opacity(0.90))
                    }
                }
            }

            // KPI 橫列：年度預估 / 日均負擔 / 月節稅（對齊 VariableExpenseView / IncomeView 三格規格）
            HStack(spacing: 0) {
                kpiCell(label: "年度預估", value: formatCurrency(yearlyEstimate))
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 0.5, height: 28)
                kpiCell(label: "日均負擔", value: formatCurrency(dailyFixed))
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 0.5, height: 28)
                kpiCell(label: "月節稅", value: taxTotal > 0 ? formatCurrency(taxTotal) : "NT$0")
            }
            .padding(.vertical, 10)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.top, 12)

            // 分隔線（對齊 VariableExpenseView 規格）
            Rectangle()
                .fill(.white.opacity(0.20))
                .frame(height: 0.5)
                .padding(.vertical, 12)

            // 雙軌進度條（有年度估算時）：月進度（上薄軌）+ 本月vs月均（下厚軌 + 月進度針）
            if monthlyAvg > 0 {
                VStack(spacing: 5) {
                    // ① 月進度軌（薄軌 3pt，半透明白）
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.12)).frame(height: 3)
                            Capsule().fill(.white.opacity(0.44))
                                .frame(width: geo.size.width * monthProgress, height: 3)
                                .animation(.spring(response: 0.7, dampingFraction: 0.8), value: monthProgress)
                        }
                    }
                    .frame(height: 3)

                    // ② 本月 vs 月均比率軌（厚軌 6pt + 月進度指示針）
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.18)).frame(height: 6)
                            Capsule()
                                .fill(monthVsAvgBarColor)
                                .frame(width: geo.size.width * barRatio, height: 6)
                                .animation(.spring(response: 0.7, dampingFraction: 0.8), value: barRatio)
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
                        HStack(spacing: 3) {
                            // 季/年繳集中月警示圖示
                            if monthVsAvgRatio > 1.05 {
                                Image(systemName: monthVsAvgRatio > 1.5
                                      ? "flame.fill"
                                      : "exclamationmark.triangle.fill")
                                    .font(.system(size: 8))
                            }
                            Text("本月 \(Int(monthVsAvgRatio * 100))% 月均")
                        }
                        .font(.caption2)
                        .foregroundStyle({
                            if monthVsAvgRatio > 1.5 { return Color(red: 1.0, green: 0.78, blue: 0.75) }
                            if monthVsAvgRatio > 1.05 { return Color(red: 1.0, green: 0.90, blue: 0.55) }
                            return .white.opacity(0.62) as Color
                        }())
                        Spacer()
                        Text("月進度 \(Int(monthProgress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.60))
                    }
                }
            } else {
                // 降級：無年度估算時顯示單軌月進度
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
                        HStack(spacing: 4) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 10))
                            Text("月進度 \(Int(monthProgress * 100))%")
                        }
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
                    .frame(width: 75, height: 75)
                    .offset(x: -65, y: 45)
                    .blur(radius: 9)
                // 右下微光（提升色彩層次）
                Circle()
                    .fill(.white.opacity(0.05))
                    .frame(width: 55, height: 55)
                    .offset(x: 95, y: 40)
                    .blur(radius: 10)
                // [v4] 頂部玻璃光澤：LinearGradient white→clear top→center，
                // 對齊 OverviewView.monthlyBalanceCard v3 / IncomeView.summaryHeader v4 /
                // FinanceOverviewView.totalAssetsCard v3 英雄卡玻璃反光規格
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

    // MARK: - 空狀態

    private var emptyStateView: some View {
        let accent = Color(red: 0.22, green: 0.53, blue: 0.98)
        return VStack(spacing: 24) {
            Spacer()

            ZStack {
                // 外層脈衝光環（對齊 VariableExpenseView emptyStateView 雙層環規格）
                Circle()
                    .stroke(accent.opacity(emptyIconPulse ? 0 : 0.28), lineWidth: 1.5)
                    .frame(width: 110, height: 110)
                    .scaleEffect(emptyIconPulse ? 1.35 : 1.0)
                    .animation(
                        .easeOut(duration: 2.0).repeatForever(autoreverses: false),
                        value: emptyIconPulse
                    )
                // 內層脈衝光環（延遲 0.3s，製造波紋層次）
                Circle()
                    .stroke(accent.opacity(emptyIconPulse ? 0 : 0.14), lineWidth: 1)
                    .frame(width: 110, height: 110)
                    .scaleEffect(emptyIconPulse ? 1.60 : 1.0)
                    .animation(
                        .easeOut(duration: 2.0).delay(0.3).repeatForever(autoreverses: false),
                        value: emptyIconPulse
                    )
                // 主圓底（漸層填色）
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.14), accent.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .overlay(
                        Circle()
                            .stroke(accent.opacity(0.22), lineWidth: 1.2)
                    )
                Image(systemName: "pin.slash")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(accent.opacity(0.70))
            }
            .onAppear {
                emptyIconPulse = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    emptyIconPulse = true
                }
            }

            VStack(spacing: 10) {
                Text("尚無固定支出紀錄")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.75))
                Text("固定支出包含房租、水電、保險、\n貸款等每月重複發生的費用")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Button {
                showingAddSheet = true
            } label: {
                Label("新增固定支出", systemImage: "plus.circle.fill")
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

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 分類群組 Sections（嵌入外層 List）

    @ViewBuilder
    private var fixedExpenseSections: some View {
        ForEach(Array(cachedGroupedByCategory.enumerated()), id: \.element.key) { groupIdx, pair in
            let (category, expenses) = pair
            Section(header: categoryHeader(category: category, expenses: expenses)) {
                ForEach(Array(expenses.enumerated()), id: \.element.id) { rowIdx, expense in
                    FixedExpenseRow(expense: expense)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            previewExpense = expense
                        }
                        // 交錯進場：群組序 × 4 + 列序，確保每列入場稍有延遲
                        .opacity(categoryListAppeared ? 1 : 0)
                        .offset(y: categoryListAppeared ? 0 : 14)
                        .animation(
                            .spring(response: 0.45, dampingFraction: 0.82)
                                .delay(0.05 * Double(groupIdx * 4 + rowIdx)),
                            value: categoryListAppeared
                        )
                }
                .onDelete { offsets in
                    deleteWithSync(offsets: offsets, from: expenses)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05)) {
                categoryListAppeared = true
            }
        }
        .onDisappear {
            categoryListAppeared = false
        }
    }

    private func categoryAccentColor(_ category: FixedCategory) -> Color {
        switch category {
        case .rent:         return .blue
        case .utilities:    return Color(red: 1.0, green: 0.75, blue: 0.10)
        case .insurance:    return .green
        case .subscription: return .purple
        case .loan:         return Color(red: 0.90, green: 0.25, blue: 0.30)
        case .telecom:      return .cyan
        case .management:   return Color(red: 0.55, green: 0.45, blue: 0.35)
        case .other:        return .secondary
        }
    }

    private func categoryHeader(category: FixedCategory, expenses: [Expense]) -> some View {
        let now = Date()
        let activeExpenses = expenses.filter { $0.date <= now }
        let accent = categoryAccentColor(category)

        return HStack(spacing: 9) {
            // 分類圖示（圓角方形，帶漸層 + 外框 + 陰影）
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.20), accent.opacity(0.09)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(accent.opacity(0.22), lineWidth: 0.75)
                    )
                    .shadow(color: accent.opacity(0.18), radius: 5, x: 0, y: 2)
                Image(systemName: category.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
            }
            Text(category.rawValue)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(accent)

            // 項目計數膠囊徽章（對齊 recentTransactionsSection 的計數規格）
            Text("\(expenses.count) 項")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(accent.opacity(0.80))
                .padding(.horizontal, 7).padding(.vertical, 2.5)
                .background(accent.opacity(0.10))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(accent.opacity(0.20), lineWidth: 0.6))

            Spacer()

            // 月費用小計膠囊（加強邊框）
            Group {
                if category == .insurance {
                    insuranceHeaderAmount(activeExpenses)
                        .font(.caption.weight(.bold))
                } else {
                    Text(formatCurrency(activeExpenses.reduce(0) { $0 + monthlyEquivalent($1) }))
                        .font(.caption.weight(.bold))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 4.5)
            .background(accent.opacity(0.10))
            .foregroundStyle(accent)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(accent.opacity(0.25), lineWidth: 0.7))
        }
        .textCase(nil)
    }

    @ViewBuilder
    private func insuranceHeaderAmount(_ expenses: [Expense]) -> some View {
        let byCurrency = Dictionary(grouping: expenses) { $0.currencyCode }
        let parts = byCurrency.sorted(by: { $0.key < $1.key }).map { (code, exps) -> String in
            let total = exps.reduce(0.0) { $0 + monthlyEquivalent($1) }
            return formatCurrencyWithCode(total, code: code)
        }
        Text(parts.joined(separator: " + "))
            .font(.caption.bold())
    }

    private func monthlyEquivalent(_ expense: Expense) -> Double {
        switch expense.recurrence {
        case .monthly: return expense.amount
        case .quarterly: return expense.amount / 3
        case .yearly: return expense.amount / 12
        case .none: return expense.amount
        }
    }

    private static let currencyFormatterCache = NSCache<NSString, NumberFormatter>()
    private func formatCurrencyWithCode(_ value: Double, code: String) -> String {
        if let f = Self.currencyFormatterCache.object(forKey: code as NSString) {
            return f.string(from: NSNumber(value: value)) ?? "\(code) 0"
        }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        f.currencySymbol = (code == "NT$" || code == "TWD") ? "NT$" : "\(code) "
        Self.currencyFormatterCache.setObject(f, forKey: code as NSString)
        return f.string(from: NSNumber(value: value)) ?? "\(code) 0"
    }

    /// 刪除固定支出時同步刪除理財連結項目
    private func deleteWithSync(offsets: IndexSet, from list: [Expense]) {
        for index in offsets {
            let expense = list[index]
            // 解除連結的儲蓄險（僅清除連結，不刪除整筆儲蓄險）
            if let linkedId = expense.linkedInsuranceId,
               var ins = financeStore.insurances.first(where: { $0.id == linkedId }) {
                if ins.linkedExpenseId == expense.id {
                    ins.linkedExpenseId = nil
                    financeStore.update(ins)
                }
            }
            // 刪除房地產中對應的貸款/已支出/變動支出項目（不刪除整筆房地產）
            if let linkedId = expense.linkedRealEstateId,
               var re = financeStore.realEstates.first(where: { $0.id == linkedId }) {
                re.mortgageItems.removeAll { $0.linkedExpenseId == expense.id }
                re.paidItems.removeAll { $0.linkedExpenseId == expense.id }
                re.variableExpenses.removeAll { $0.linkedExpenseId == expense.id }
                re.insuranceItems.removeAll { $0.linkedExpenseId == expense.id }
                re.propertyAssets.removeAll { $0.linkedExpenseId == expense.id }
                financeStore.update(re)
            }
            // 刪除連結的汽車定期支出項目
            if let linkedId = expense.linkedVehicleId,
               var vehicle = financeStore.vehicles.first(where: { $0.id == linkedId }) {
                vehicle.fixedExpenses.removeAll { $0.linkedExpenseId == expense.id }
                financeStore.update(vehicle)
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

    private func formatCurrency(_ value: Double) -> String {
        value.ntdWanString
    }

    /// 依開始日期與週期，估算該筆固定支出在當年度內發生的次數
    private func occurrencesThisYear(for expense: Expense) -> Int {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        guard let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let yearEndDay = calendar.date(from: DateComponents(year: year, month: 12, day: 31)),
              let yearEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: yearEndDay) else {
            return 0
        }
        let effectiveStart = max(expense.date, yearStart)
        if effectiveStart > yearEnd { return 0 }

        switch expense.recurrence {
        case .monthly:
            let months = calendar.dateComponents([.month], from: effectiveStart, to: yearEnd).month ?? 0
            return max(0, months + 1)
        case .quarterly:
            let months = calendar.dateComponents([.month], from: effectiveStart, to: yearEnd).month ?? 0
            return max(0, months / 3 + 1)
        case .yearly:
            return expense.date <= yearEnd ? 1 : 0
        case .none:
            return expense.date <= yearEnd ? 1 : 0
        }
    }
}

// MARK: - 固定支出列

struct FixedExpenseRow: View {
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
        switch expense.fixedCategory {
        case .rent:         return .blue
        case .utilities:    return Color(red: 1.0, green: 0.75, blue: 0.10)
        case .insurance:    return .green
        case .subscription: return .purple
        case .loan:         return Color(red: 0.90, green: 0.25, blue: 0.30)
        case .telecom:      return .cyan
        case .management:   return Color(red: 0.55, green: 0.45, blue: 0.35)
        case .other, .none: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // 左側分類色彩強調條（加粗至 4pt，圓角加大增加視覺重量）
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [categoryAccent, categoryAccent.opacity(0.40)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4)
                .padding(.vertical, 8)
                .padding(.trailing, 14)

            HStack(spacing: 12) {
                // 分類圖示圓（與 ExpenseRow 對齊：44pt、陰影、18pt 圖示）
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [categoryAccent.opacity(0.22), categoryAccent.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: categoryAccent.opacity(0.22), radius: 6, x: 0, y: 3)
                    Image(systemName: expense.fixedCategory?.icon ?? "pin.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(categoryAccent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(expense.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if let recurrence = expense.recurrence {
                            Text(recurrence.rawValue)
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(categoryAccent.opacity(0.12))
                                .foregroundStyle(categoryAccent)
                                .clipShape(Capsule())
                        }
                        if expense.effectivelyTaxDeductible {
                            HStack(spacing: 2) {
                                Image(systemName: "leaf.fill")
                                    .font(.system(size: 8))
                                Text("節稅")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .foregroundStyle(Color.green)
                            .clipShape(Capsule())
                        }
                        if !expense.note.isEmpty {
                            Text(expense.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(formattedAmount)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.92, green: 0.28, blue: 0.28))
                        .contentTransition(.numericText())

                    // 季繳 / 年繳：顯示月均換算，幫助使用者快速理解月度負擔
                    monthlyAverageBadge

                    deductionLabelBadge
                }
            }
            .padding(.vertical, 7)
        }
    }

    /// 季繳 / 年繳的「月均」膠囊（抽出以降低主 body 型別檢查複雜度）
    @ViewBuilder
    private var monthlyAverageBadge: some View {
        let monthly = monthlyEquivalentAmount(expense)
        if let recurrence = expense.recurrence, recurrence != .monthly, monthly > 0 {
            HStack(spacing: 2) {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 8, weight: .medium))
                Text("月均 \(formatCurrencyCompact(monthly))")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Color(red: 0.92, green: 0.28, blue: 0.28).opacity(0.65))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color(red: 0.92, green: 0.28, blue: 0.28).opacity(0.08))
            .clipShape(Capsule())
        }
    }

    /// 扣款對象（信用卡 / 銀行）標籤膠囊
    @ViewBuilder
    private var deductionLabelBadge: some View {
        if let label = deductionTargetLabel {
            HStack(spacing: 3) {
                Image(systemName: deductionIcon)
                    .font(.system(size: 9))
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

    private var formattedAmount: String {
        let code = expense.currencyCode
        // 儲蓄險的 amount 已是原幣別存值（沒乘匯率），其他類型存的是換算後的 NT$。
        let isSavingsIns = expense.fixedCategory == .insurance
            && expense.insuranceSubCategory == .savings
        if code != "NT$" && code != "TWD" && !code.isEmpty {
            let displayAmount: Double
            if isSavingsIns {
                displayAmount = expense.amount
            } else if let rate = store.currencyRates.first(where: { $0.code == code }), rate.rate > 0 {
                displayAmount = expense.amount / rate.rate
            } else {
                displayAmount = expense.amount
            }
            let str = Self.decimalFormatter.string(from: NSNumber(value: displayAmount)) ?? "0"
            return "\(code) \(str)"
        }
        return formatCurrency(expense.amount)
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

    /// 依週期換算月均金額（與 FixedExpenseView.monthlyEquivalent 邏輯一致）
    private func monthlyEquivalentAmount(_ expense: Expense) -> Double {
        switch expense.recurrence {
        case .monthly:   return expense.amount
        case .quarterly: return expense.amount / 3
        case .yearly:    return expense.amount / 12
        case .none:      return 0
        }
    }

    /// 金額緊湊格式：≥1萬顯示「N萬 / N.N萬」，否則顯示「NT$X」
    private func formatCurrencyCompact(_ value: Double) -> String {
        if abs(value) >= 10_000 {
            let wan = value / 10_000
            let str = (wan == wan.rounded()) ? String(format: "%.0f", wan) : String(format: "%.1f", wan)
            return "\(str)萬"
        }
        return Self.currencyFormatter.string(from: NSNumber(value: value)) ?? "NT$0"
    }
}

// MARK: - 固定支出預覽卡片（點項目先看卡片，右上角「編輯」才進入編輯）

private struct FixedExpenseCard: View {
    @EnvironmentObject var store: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var financeStore: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let expense: Expense
    @State private var showEdit = false

    /// 讀取 store 最新版本，編輯儲存後即時反映（找不到才退回快照）
    private var current: Expense { store.expenses.first { $0.id == expense.id } ?? expense }

    /// 若此筆為儲蓄險固定支出，取其連結的理財儲蓄險（利率等資料存於此）。
    /// 先用正向連結（linkedInsuranceId），找不到再用反向連結（儲蓄險記得連到本支出），
    /// 以相容早期連結遺失／子分類未存到的舊資料——只要有連結儲蓄險就視為儲蓄險。
    private var linkedSavings: SavingsInsurance? {
        guard current.fixedCategory == .insurance else { return nil }
        if let id = current.linkedInsuranceId,
           let ins = financeStore.insurances.first(where: { $0.id == id }) {
            return ins
        }
        return financeStore.insurances.first { $0.linkedExpenseId == current.id }
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "yyyy/M/d"; return f
    }()
    private static let decimalFmt: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0; return f
    }()

    private var accent: Color {
        switch current.fixedCategory {
        case .rent:         return .blue
        case .utilities:    return Color(red: 1.0, green: 0.75, blue: 0.10)
        case .insurance:    return .green
        case .subscription: return .purple
        case .loan:         return Color(red: 0.90, green: 0.25, blue: 0.30)
        case .telecom:      return .cyan
        case .management:   return Color(red: 0.55, green: 0.45, blue: 0.35)
        case .other, .none: return .secondary
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleBlock
                    infoCard
                    if linkedSavings != nil { savingsSection }
                    if !current.note.isEmpty { noteBlock }
                    photoSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(current.fixedCategory?.rawValue ?? "固定支出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("編輯") { showEdit = true }.bold()
                }
            }
            .sheet(isPresented: $showEdit) {
                AddExpenseView(expenseType: .fixed, editingExpense: current)
            }
        }
    }

    private var titleBlock: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.10)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48)
                Image(systemName: current.fixedCategory?.icon ?? "pin.circle.fill")
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(current.title.isEmpty ? "未命名項目" : current.title)
                    .font(.title3.weight(.bold))
                Text(formattedAmount)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.92, green: 0.28, blue: 0.28))
            }
            Spacer(minLength: 0)
        }
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            if let recurrence = current.recurrence {
                field("週期", recurrence.rawValue)
                let monthly = monthlyEquivalent
                if recurrence != .monthly, monthly > 0 {
                    Divider().padding(.leading, 14)
                    field("月均換算", "NT$ " + fmtShort(monthly))
                }
            }
            Divider().padding(.leading, 14)
            field("起始日期", Self.dateFmt.string(from: current.date))
            if current.effectivelyTaxDeductible {
                Divider().padding(.leading, 14)
                field("節稅", "列入節稅追蹤")
            }
            if let target = deductionTargetLabel {
                Divider().padding(.leading, 14)
                field("扣款目標", target)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var noteBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("備註").font(.caption).foregroundStyle(.secondary)
            Text(current.note).font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// 儲蓄險明細：顯示連結理財儲蓄險的複利年利率、繳費週期、起訖日與期滿預估
    @ViewBuilder
    private var savingsSection: some View {
        if let ins = linkedSavings {
            let rate = current.insuranceRate ?? ins.annualRate
            let elapsed = ins.elapsedPeriods
            let total = ins.totalPeriods
            let paid = ins.premiumAmount * Double(elapsed)
            let projected = ins.premiumAmount * Double(total)
            let progress = total > 0 ? min(1, Double(elapsed) / Double(total)) : 0
            VStack(alignment: .leading, spacing: 8) {
                Text("儲蓄險").font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.top, 10)

                // 甘特圖：起始日 → 到期日，填色代表已繳進度，圓點為目前位置
                ganttBar(progress: progress, start: ins.startDate, end: ins.maturityDate)

                VStack(spacing: 0) {
                    field("複利年利率", rate > 0 ? String(format: "%.2f%%", rate) : "—")
                    Divider().padding(.leading, 14)
                    field("繳費週期", ins.paymentPeriod.rawValue)
                    Divider().padding(.leading, 14)
                    field("已繳 / 總期數", "\(elapsed) / \(total) 期")
                    Divider().padding(.leading, 14)
                    field("已繳總支出", "\(ins.currencyCode) " + fmtShort(paid))
                    Divider().padding(.leading, 14)
                    field("預計總支出", "\(ins.currencyCode) " + fmtShort(projected))
                    Divider().padding(.leading, 14)
                    field("起始日", Self.dateFmt.string(from: ins.startDate))
                    Divider().padding(.leading, 14)
                    field("預計結束（到期）", Self.dateFmt.string(from: ins.maturityDate))
                    if ins.expectedReturn > 0 {
                        Divider().padding(.leading, 14)
                        field("期滿預估領回", "\(ins.currencyCode) " + fmtShort(ins.expectedReturn))
                    }
                }
            }
            .padding(.bottom, 6)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    /// 甘特圖風格的繳費進度條：整條代表起始日→到期日，填色為已繳進度，白圓點標示目前位置
    private func ganttBar(progress: Double, start: Date, end: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let fill = max(6, w * progress)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill)).frame(height: 10)
                    Capsule()
                        .fill(LinearGradient(colors: [.green, .green.opacity(0.55)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: fill, height: 10)
                    Circle().fill(.white).frame(width: 15, height: 15)
                        .overlay(Circle().stroke(Color.green, lineWidth: 3))
                        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                        .offset(x: min(w - 15, max(0, w * progress - 7.5)))
                }
                .frame(height: 15)
            }
            .frame(height: 16)
            HStack {
                Text(Self.dateFmt.string(from: start)).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.caption2.weight(.bold)).foregroundStyle(.green)
                Spacer()
                Text(Self.dateFmt.string(from: end)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
    }

    /// 帳單照片：可拍照 / 從相簿新增，直接寫回此筆固定支出並持久化（含 iCloud 同步）
    private var photoSection: some View {
        MultiPhotoGallery(
            fileNames: photoBinding,
            urlFor: { Expense.photoURL(for: $0) },
            onSaveImage: { Expense.savePhoto($0, expenseId: expense.id) },
            onDeleteFile: { Expense.deletePhoto($0) },
            title: "帳單照片"
        )
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// 綁定到此筆支出的照片檔名陣列：新增 / 刪除即透過 store.update 寫回並存檔
    private var photoBinding: Binding<[String]> {
        Binding(
            get: { current.photoFileNames },
            set: { newNames in
                var e = current
                e.photoFileNames = newNames
                store.update(e)
            }
        )
    }

    private func field(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    // MARK: - 計算（與 FixedExpenseRow 邏輯一致）

    private var formattedAmount: String {
        let code = current.currencyCode
        let isSavingsIns = current.fixedCategory == .insurance && current.insuranceSubCategory == .savings
        if code != "NT$" && code != "TWD" && !code.isEmpty {
            let displayAmount: Double
            if isSavingsIns {
                displayAmount = current.amount
            } else if let rate = store.currencyRates.first(where: { $0.code == code }), rate.rate > 0 {
                displayAmount = current.amount / rate.rate
            } else {
                displayAmount = current.amount
            }
            let str = Self.decimalFmt.string(from: NSNumber(value: displayAmount)) ?? "0"
            return "\(code) \(str)"
        }
        return current.amount.ntdWanString
    }

    private var monthlyEquivalent: Double {
        switch current.recurrence {
        case .monthly:   return current.amount
        case .quarterly: return current.amount / 3
        case .yearly:    return current.amount / 12
        case .none:      return 0
        }
    }

    private var deductionTargetLabel: String? {
        if let cardId = current.linkedCreditCardMilestoneId,
           let card = lifeStore.milestones.first(where: { $0.id == cardId }) {
            return card.cardName ?? card.title
        }
        if let bankId = current.linkedBankMilestoneId,
           let ms = lifeStore.milestones.first(where: { $0.id == bankId }) {
            let name = ms.bankName ?? ms.title
            let currency = current.linkedBankCurrency ?? "NT$"
            return currency == "NT$" ? name : "\(name) · \(currency)"
        }
        return nil
    }

    private func fmtShort(_ v: Double) -> String {
        if abs(v) >= 10_000 {
            let s = Self.decimalFmt.string(from: NSNumber(value: v / 10_000)) ?? "0"
            return "\(s)萬"
        }
        return Self.decimalFmt.string(from: NSNumber(value: v)) ?? "0"
    }
}

#Preview {
    FixedExpenseView()
        .environmentObject(ExpenseStore())
}
