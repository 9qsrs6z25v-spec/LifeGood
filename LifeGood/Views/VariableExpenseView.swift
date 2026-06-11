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

struct VariableExpenseView: View {
    @EnvironmentObject var store: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var lifeStore: LifeStore
    @State private var showingAddSheet = false
    @State private var selectedCategory: VariableCategory?
    @State private var expenseToEdit: Expense?
    @State private var visibleWeeks = 1
    @State private var searchText: String = ""
    @State private var listRowsAppeared = false
    @State private var cachedTrailingMonthlyAvg: Double = 0

    private static let groupDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M月d日 EEEE"
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

    var filteredExpenses: [Expense] {
        var list = store.variableExpenses
        if let category = selectedCategory {
            list = list.filter { $0.variableCategory == category }
        }
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
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
                    monthSummaryHeader
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
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜尋名稱 / 備註 / 分類 / 地點"
            )
            .task(id: store.modifyID) {
                cachedTrailingMonthlyAvg = computeTrailingMonthlyAvg()
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

    private var todayVariableTotal: Double {
        store.variableExpenses
            .filter { Calendar.current.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.amount }
    }

    private var trailingMonthlyAverageVariable: Double { cachedTrailingMonthlyAvg }

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

    // MARK: - 月摘要

    private var monthProgress: Double {
        let cal = Calendar.current
        let now = Date()
        let day = Double(cal.component(.day, from: now))
        let total = Double(cal.range(of: .day, in: .month, for: now)?.count ?? 30)
        return min(day / total, 1.0)
    }

    private var monthSummaryHeader: some View {
        let count = store.currentMonthExpenses.filter { $0.expenseType == .variable }.count
        let total = store.currentMonthVariableTotal
        let dayOfMonth = Calendar.current.component(.day, from: Date())
        let dailyAvg = total / Double(max(dayOfMonth, 1))

        return VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("本月變動支出")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.80))
                    Text(formatCurrency(total))
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
                }
            }

            // KPI 橫列：今日花費 / 日均支出 / 近3月均值
            HStack(spacing: 0) {
                kpiCell(label: "今日花費", value: formatCurrency(todayVariableTotal))
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 0.5, height: 28)
                kpiCell(label: "日均支出", value: formatCurrency(dailyAvg))
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 0.5, height: 28)
                kpiCell(label: "近3月均值", value: formatCurrency(trailingMonthlyAverageVariable))
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
                    Text("本月進度 \(Int(monthProgress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.60))
                    Spacer()
                    Text("剩 \(Int((1 - monthProgress) * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.60))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.62, blue: 0.22),
                        Color(red: 0.86, green: 0.36, blue: 0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // 裝飾性散景圓
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 120, height: 120)
                    .offset(x: 80, y: -45)
                    .blur(radius: 12)
                Circle()
                    .fill(.white.opacity(0.07))
                    .frame(width: 70, height: 70)
                    .offset(x: -60, y: 40)
                    .blur(radius: 8)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.86, green: 0.36, blue: 0.06).opacity(0.38), radius: 14, x: 0, y: 7)
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
                if !isSearching {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        emptyIconPulse = true
                    }
                }
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
            let (dateString, expenses) = group
            Section(header: daySectionHeader(dateString: dateString, expenses: expenses)) {
                ForEach(Array(expenses.enumerated()), id: \.element.id) { rowIdx, expense in
                    ExpenseRow(expense: expense)
                        .contentShape(Rectangle())
                        .onTapGesture { expenseToEdit = expense }
                        .swipeActions(edge: .trailing) {
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
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05)) {
                listRowsAppeared = true
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
            // 同步解除股票連結
            if let stockId = expense.linkedStockId,
               var stock = financeStore.stocks.first(where: { $0.id == stockId }) {
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
            Self.groupDateFormatter.string(from: expense.date)
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
