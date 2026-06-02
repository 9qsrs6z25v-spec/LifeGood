import SwiftUI

// MARK: - 美化紀錄（FixedExpenseView）
// [2026-06] 本次美化方向：
//   1. 補 .navigationBarTitleDisplayMode(.large) 與其他主要列表頁對齊
//   2. 空狀態：加入雙層脈衝光環動畫（對齊 VariableExpenseView emptyStateView 規格）
//   3. 分類 Section：加入交錯進場動畫（對齊 OverviewView categoryRow 規格）
//   4. categoryHeader：新增項目計數膠囊徽章，資訊密度與 daySectionHeader 對齊
//   5. FixedExpenseRow：季繳 / 年繳項目在金額下方顯示「月均 NT$X」輔助標籤，
//      幫助使用者快速換算月度負擔，對齊可讀性標準

struct FixedExpenseView: View {
    @EnvironmentObject var store: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var lifeStore: LifeStore
    @State private var showingAddSheet = false
    @State private var expenseToEdit: Expense?
    @State private var headerAppeared = false
    @State private var emptyIconPulse = false
    @State private var categoryListAppeared = false

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "TWD"
        f.currencySymbol = "NT$"
        f.maximumFractionDigits = 0
        return f
    }()

    var groupedByCategory: [(key: FixedCategory, value: [Expense])] {
        let now = Date()
        let grouped = Dictionary(grouping: store.fixedExpenses) { expense in
            expense.fixedCategory ?? .other
        }
        // 先把每組總額算好一次，避免排序比較函式內重複執行 filter+reduce
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
            .sheet(isPresented: $showingAddSheet) {
                AddExpenseView(expenseType: .fixed)
            }
            .sheet(item: $expenseToEdit) { expense in
                AddExpenseView(expenseType: .fixed, editingExpense: expense)
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

    private var fixedSummaryHeader: some View {
        let yearlyEstimate = store.fixedExpenses.reduce(0.0) { total, expense in
            total + expense.amount * Double(occurrencesThisYear(for: expense))
        }
        let count = store.fixedExpenses.count
        let monthlyTotal = store.currentMonthFixedTotal
        let taxTotal = store.fixedExpenses
            .filter { $0.effectivelyTaxDeductible }
            .reduce(0.0) { $0 + monthlyEquivalent($1) }

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
                    if monthlyTotal > 0 {
                        Text("日均 " + formatCurrency(monthlyTotal / max(1, Double(Calendar.current.component(.day, from: Date())))))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.top, 1)
                    }
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

            // 月進度條
            VStack(spacing: 5) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.18))
                            .frame(height: 5)
                        Capsule()
                            .fill(.white.opacity(0.80))
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
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.60))
                    Spacer()
                    Text("年度預估 " + formatCurrency(yearlyEstimate))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.60))
                }
            }
            .padding(.top, 12)
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
        ForEach(Array(groupedByCategory.enumerated()), id: \.element.key) { groupIdx, pair in
            let (category, expenses) = pair
            Section(header: categoryHeader(category: category, expenses: expenses)) {
                ForEach(Array(expenses.enumerated()), id: \.element.id) { rowIdx, expense in
                    FixedExpenseRow(expense: expense)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            expenseToEdit = expense
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

    private static var currencyFormatterCache: [String: NumberFormatter] = [:]
    private func formatCurrencyWithCode(_ value: Double, code: String) -> String {
        if let f = Self.currencyFormatterCache[code] {
            return f.string(from: NSNumber(value: value)) ?? "\(code) 0"
        }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        f.currencySymbol = (code == "NT$" || code == "TWD") ? "NT$" : "\(code) "
        Self.currencyFormatterCache[code] = f
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
                    if let recurrence = expense.recurrence,
                       recurrence != .monthly {
                        let monthly = monthlyEquivalentAmount(expense)
                        if monthly > 0 {
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
            }
            .padding(.vertical, 7)
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

#Preview {
    FixedExpenseView()
        .environmentObject(ExpenseStore())
}
