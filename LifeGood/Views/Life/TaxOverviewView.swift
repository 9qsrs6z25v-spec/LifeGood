import SwiftUI

// MARK: - 美化紀錄（TaxOverviewView）
// [2026-06] 本次美化方向：
//   1. annualSummaryCard → 升級為紅橘漸層英雄卡片（對齊 VariableExpenseView header 設計語言）：
//      頂部左置年度稅費大字、右置年收入 + 稅費率膠囊；底部 4 個 taxStat 改用 44pt 漸層圖示圓
//      搭配散景裝飾圓，整體對齊同系列 hero card 視覺語言。
//   2. yearPicker → 左右箭頭改為綠色填充圓形膠囊按鈕（提升觸碰目標；對齊 MacaronDatePicker 風格）
//      + 年份文字加大至 .title3，提升可讀性。
//   3. sectionHeader → 改為 Capsule 側條 + .semibold 標題（對齊 OverviewView categoryBreakdownSection
//      標題規格），支援可選計數膠囊參數，強化各 section 層級對比。
//   4. taxRecordsSection 各列 → 加入 38pt 漸層圖示圓 + 日期膠囊徽章，對齊 ExpenseRow 規格；
//      空狀態改用圖示 + 說明文字佔位塊（對齊 FixedExpenseView emptyStateView 風格）。
//   5. monthlyBreakdown 橫條 → 改用紅橘漸層 Capsule 填充；加入左展開進場動畫（對齊
//      allocationSection bar 規格），月份以膠囊徽章顯示，金額對齊右側。
//   6. taxSavingSection → taxSavingRow 圖示升級為 34pt 漸層圓（對齊 ExpenseRow icon 規格）；
//      進度條換用 Capsule 漸層（綠 → 橘）。
//   7. taxChecklistSection → 每列加入彩色圓形圖示 + 月份膠囊徽章 + 「應注意」改為 Capsule
//      （對齊統一列表 row 規格）；末項前加 Divider 視覺分隔。
//   8. deductionTipsSection → 圖示升級為 34pt 漸層圓，對齊 taxSavingRow 統一視覺。
//   9. 英雄卡片進場 spring 動畫（heroCardAppeared）+ 月份條進場動畫（monthBarAppeared）。

struct TaxOverviewView: View {
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())

    // 進場動畫旗標
    @State private var heroCardAppeared = false
    @State private var monthBarAppeared = false

    // MARK: - 商業邏輯（不動）

    private var taxExpenses: [Expense] {
        expenseStore.expenses.filter {
            $0.variableCategory == .tax &&
            Calendar.current.component(.year, from: $0.date) == selectedYear
        }
        .sorted { $0.date > $1.date }
    }

    private var totalTax: Double {
        taxExpenses.reduce(0) { $0 + $1.amount }
    }

    private var taxSavingExpenses: [Expense] {
        expenseStore.expenses.filter {
            $0.variableCategory == .taxSaving &&
            Calendar.current.component(.year, from: $0.date) == selectedYear
        }
        .sorted { $0.date > $1.date }
    }

    private var totalTaxSaving: Double {
        TaxSavingSubCategory.allCases.reduce(0) { $0 + taxSavingTotal(for: $1) }
    }

    private func taxSavingDirectTotal(for sub: TaxSavingSubCategory) -> Double {
        taxSavingExpenses
            .filter { $0.taxSavingSubCategory == sub }
            .reduce(0) { $0 + $1.amount }
    }

    private func taxSavingFromFixedTotal(for sub: TaxSavingSubCategory) -> Double {
        expenseStore.expenses
            .filter {
                $0.expenseType == .fixed &&
                $0.effectivelyTaxDeductible &&
                $0.inferredTaxSavingSubCategory == sub
            }
            .reduce(0) { $0 + yearEquivalentAmount($1, year: selectedYear) }
    }

    private func taxSavingTotal(for sub: TaxSavingSubCategory) -> Double {
        taxSavingDirectTotal(for: sub) + taxSavingFromFixedTotal(for: sub)
    }

    private func yearEquivalentAmount(_ exp: Expense, year: Int) -> Double {
        let cal = Calendar.current
        let createYear = cal.component(.year, from: exp.date)
        guard createYear <= year else { return 0 }
        let monthsActive: Int
        if createYear < year {
            monthsActive = 12
        } else {
            let createMonth = cal.component(.month, from: exp.date)
            monthsActive = max(0, 12 - createMonth + 1)
        }
        switch exp.recurrence {
        case .monthly:   return exp.amount * Double(monthsActive)
        case .quarterly: return exp.amount * (Double(monthsActive) / 3.0)
        case .yearly:    return exp.amount
        case .none:      return 0
        }
    }

    private var taxByMonth: [(month: Int, amount: Double)] {
        var result: [(Int, Double)] = []
        for m in 1...12 {
            let amount = taxExpenses.filter {
                Calendar.current.component(.month, from: $0.date) == m
            }.reduce(0) { $0 + $1.amount }
            if amount > 0 { result.append((m, amount)) }
        }
        return result
    }

    private var realEstateCount: Int { financeStore.realEstates.filter { !$0.isSold }.count }
    private var vehicleCount: Int { financeStore.vehicles.filter { !$0.isSold }.count }

    private var estimatedAnnualIncome: Double {
        expenseStore.incomes.reduce(0.0) { sum, inc in
            switch inc.period {
            case .monthly: return sum + inc.amount * 12
            case .yearly:  return sum + inc.amount
            case .once:
                if Calendar.current.component(.year, from: inc.date) == selectedYear {
                    return sum + inc.amount
                }
                return sum
            }
        }
    }

    // MARK: - 主體

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    yearPicker
                    annualSummaryCard
                        .opacity(heroCardAppeared ? 1 : 0)
                        .offset(y: heroCardAppeared ? 0 : 20)
                        .onAppear {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                                heroCardAppeared = true
                            }
                        }
                    taxRecordsSection
                    monthlyBreakdown
                    taxSavingSection
                    taxChecklistSection
                    deductionTipsSection
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("稅務")
        }
    }

    // MARK: - 年度選擇（升級：圓形膠囊按鈕 + 加大年份文字）

    private var yearPicker: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                    selectedYear -= 1
                    heroCardAppeared = false
                    monthBarAppeared = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                            heroCardAppeared = true
                            monthBarAppeared = true
                        }
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text("\(String(selectedYear)) 年度")
                    .font(.title3.weight(.bold))
                Text("年度稅務報告")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                    selectedYear += 1
                    heroCardAppeared = false
                    monthBarAppeared = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                            heroCardAppeared = true
                            monthBarAppeared = true
                        }
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        .padding(.horizontal)
    }

    // MARK: - 年度摘要英雄卡（升級：紅橘漸層 + 散景裝飾 + KPI 統計行）

    private var annualSummaryCard: some View {
        let taxRatio = estimatedAnnualIncome > 0 ? totalTax / estimatedAnnualIncome * 100 : 0

        return VStack(spacing: 0) {
            // 頂部：稅費 + 年收入
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("年度稅費支出")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                    Text(fmt(totalTax))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    if totalTax > 0 && estimatedAnnualIncome > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: taxRatio > 10 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .font(.system(size: 9))
                            Text("佔年收入 \(String(format: "%.1f", taxRatio))%")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.white.opacity(taxRatio > 10 ? 0.28 : 0.18))
                        .clipShape(Capsule())
                    }
                }
                Spacer()
                // 年收入 KPI 膠囊
                if estimatedAnnualIncome > 0 {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("預估年收入")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.62))
                        Text(fmtShort(estimatedAnnualIncome))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(.white.opacity(0.18))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.30), lineWidth: 0.75))
                }
            }

            // 分隔線
            Rectangle()
                .fill(.white.opacity(0.20))
                .frame(height: 0.5)
                .padding(.vertical, 14)

            // 4 個統計格
            HStack(spacing: 0) {
                taxStatCell(icon: "building.2.fill",      label: "持有房產", value: "\(realEstateCount) 筆", color: Color(red: 0.42, green: 0.62, blue: 1.00))
                taxStatDivider()
                taxStatCell(icon: "car.fill",             label: "持有車輛", value: "\(vehicleCount) 台",   color: Color(red: 1.00, green: 0.72, blue: 0.20))
                taxStatDivider()
                taxStatCell(icon: "doc.text.fill",        label: "稅費筆數", value: "\(taxExpenses.count) 筆", color: Color(red: 1.00, green: 0.78, blue: 0.75))
                taxStatDivider()
                taxStatCell(icon: "leaf.fill",            label: "節稅累積", value: fmtShort(totalTaxSaving), color: Color(red: 0.62, green: 1.00, blue: 0.75))
            }
        }
        .padding(20)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.90, green: 0.28, blue: 0.22),
                        Color(red: 0.70, green: 0.15, blue: 0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // 右上散景圓
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 140, height: 140)
                    .offset(x: 85, y: -55)
                    .blur(radius: 14)
                // 左下散景圓
                Circle()
                    .fill(.white.opacity(0.07))
                    .frame(width: 85, height: 85)
                    .offset(x: -65, y: 48)
                    .blur(radius: 10)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.70, green: 0.15, blue: 0.12).opacity(0.42), radius: 18, x: 0, y: 9)
        .padding(.horizontal)
    }

    private func taxStatCell(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.35), color.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.70))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func taxStatDivider() -> some View {
        Rectangle()
            .fill(.white.opacity(0.22))
            .frame(width: 0.5, height: 44)
    }

    // MARK: - 稅費紀錄（升級：漸層圖示圓 + 日期膠囊 + 空狀態佔位）

    private var taxRecordsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("稅費紀錄", icon: "list.bullet.rectangle", color: .red,
                          count: taxExpenses.isEmpty ? nil : taxExpenses.count)

            if taxExpenses.isEmpty {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.08))
                            .frame(width: 52, height: 52)
                        Image(systemName: "doc.text")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(Color.red.opacity(0.55))
                    }
                    Text("本年度尚無稅費紀錄")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
            } else {
                ForEach(Array(taxExpenses.enumerated()), id: \.element.id) { idx, exp in
                    HStack(spacing: 12) {
                        // 分類圖示圓
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.red.opacity(0.18), Color.red.opacity(0.07)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 38, height: 38)
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.red.opacity(0.85))
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(exp.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            // 日期膠囊
                            Text(fmtDate(exp.date))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(Capsule())
                        }

                        Spacer(minLength: 4)

                        Text(fmt(exp.amount))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.red.opacity(0.85))
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    if idx < taxExpenses.count - 1 {
                        Divider().padding(.leading, 64)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    // MARK: - 月份分佈（升級：漸層 Capsule + 進場動畫 + 月份膠囊徽章）

    @ViewBuilder
    private var monthlyBreakdown: some View {
        if !taxByMonth.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("月份分佈", icon: "calendar", color: .orange,
                              count: taxByMonth.count)

                let maxAmount = taxByMonth.map(\.amount).max() ?? 1
                ForEach(Array(taxByMonth.enumerated()), id: \.element.month) { idx, item in
                    HStack(spacing: 10) {
                        // 月份膠囊
                        Text("\(item.month)月")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(red: 0.90, green: 0.28, blue: 0.22))
                            .frame(width: 30, alignment: .trailing)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color(red: 0.90, green: 0.28, blue: 0.22).opacity(0.10))
                            .clipShape(Capsule())

                        // 漸層 Capsule 進度條（左側展開進場）
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color(.systemFill))
                                    .frame(height: 12)
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.90, green: 0.28, blue: 0.22),
                                                Color(red: 1.00, green: 0.55, blue: 0.20)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(
                                        width: max(8, geo.size.width * CGFloat(monthBarAppeared ? item.amount / maxAmount : 0)),
                                        height: 12
                                    )
                                    .animation(
                                        .spring(response: 0.65, dampingFraction: 0.80)
                                            .delay(0.06 * Double(idx)),
                                        value: monthBarAppeared
                                    )
                            }
                        }
                        .frame(height: 12)

                        Text(fmtShort(item.amount))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 66, alignment: .trailing)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                }
                .padding(.bottom, 6)
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
            .padding(.horizontal)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    monthBarAppeared = true
                }
            }
        }
    }

    // MARK: - 年度稅務檢核（升級：彩色圖示圓 + 月份膠囊 + 列間 Divider）

    private var taxChecklistSection: some View {
        let items: [(month: String, title: String, relevant: Bool, color: Color)] = [
            ("5月",  "綜合所得稅申報",     selectedYear < Calendar.current.component(.year, from: Date()), .indigo),
            ("5月",  "房屋稅繳納",         realEstateCount > 0,        .blue),
            ("7月",  "汽機車使用牌照稅",    vehicleCount > 0,            .orange),
            ("11月", "地價稅繳納",         realEstateCount > 0,        .purple),
            ("4月",  "汽機車燃料費",        vehicleCount > 0,            .teal),
            ("全年", "二代健保補充保費",    estimatedAnnualIncome > 0,  .green),
        ]

        let relevantCount = items.filter(\.relevant).count
        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader("年度稅務檢核", icon: "checkmark.square.fill", color: .green,
                          count: relevantCount > 0 ? relevantCount : nil)

            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                HStack(spacing: 12) {
                    // 狀態圖示圓
                    ZStack {
                        Circle()
                            .fill(
                                item.relevant
                                ? LinearGradient(colors: [item.color.opacity(0.20), item.color.opacity(0.08)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color(.systemFill), Color(.systemFill)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 36, height: 36)
                        Image(systemName: item.relevant ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(item.relevant ? item.color : Color(.tertiaryLabel))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.subheadline.weight(item.relevant ? .semibold : .regular))
                            .foregroundStyle(item.relevant ? .primary : .secondary)
                        // 月份膠囊
                        Text(item.month)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(item.relevant ? item.color : .secondary)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background((item.relevant ? item.color : Color.secondary).opacity(0.10))
                            .clipShape(Capsule())
                    }

                    Spacer(minLength: 4)

                    if item.relevant {
                        Text("應注意")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.orange.opacity(0.22), lineWidth: 0.6))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                if i < items.count - 1 {
                    Divider().padding(.leading, 62)
                }
            }
            .padding(.bottom, 4)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    // MARK: - 節稅累積（升級：漸層圖示圓 + 更精緻進度條）

    private var taxSavingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("節稅累積", icon: "leaf.fill", color: .green,
                          count: totalTaxSaving > 0 ? nil : nil)

            if totalTaxSaving == 0 {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.08))
                            .frame(width: 52, height: 52)
                        Image(systemName: "leaf")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(Color.green.opacity(0.55))
                    }
                    Text("本年度尚無節稅紀錄")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("可在「變動支出」分類選「節稅」新增；保險、房貸、房租固定支出也會自動納入")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
            } else {
                HStack {
                    Text("年度節稅總額")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(fmt(totalTaxSaving))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 14).padding(.vertical, 10)

                Divider().padding(.leading, 14)

                ForEach(TaxSavingSubCategory.allCases) { sub in
                    let total = taxSavingTotal(for: sub)
                    if total > 0 {
                        taxSavingRow(sub: sub, total: total)
                        Divider().padding(.leading, 58)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    private func taxSavingRow(sub: TaxSavingSubCategory, total: Double) -> some View {
        let limit = sub.annualLimit
        let progress: Double = {
            guard let limit = limit, limit > 0 else { return 0 }
            return min(1, total / limit)
        }()
        let reachedCap = limit != nil && total >= (limit ?? 0)
        let direct   = taxSavingDirectTotal(for: sub)
        let fromFixed = taxSavingFromFixedTotal(for: sub)
        let rowColor: Color = reachedCap ? .orange : .green

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // 34pt 漸層圖示圓
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [rowColor.opacity(0.20), rowColor.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 34, height: 34)
                    Image(systemName: sub.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(rowColor)
                }

                Text(sub.rawValue)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(fmt(total))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(rowColor)
                    .contentTransition(.numericText())

                if reachedCap {
                    Text("已達上限")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            if let limit = limit {
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(.systemFill))
                                .frame(height: 5)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: reachedCap
                                            ? [Color.orange, Color.orange.opacity(0.65)]
                                            : [Color.green, Color.green.opacity(0.65)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * CGFloat(progress), height: 5)
                        }
                    }
                    .frame(height: 5)
                    HStack {
                        Text("上限 \(fmt(limit))")
                            .font(.caption2).foregroundStyle(.tertiary)
                        Spacer()
                        Text(String(format: "%.0f%%", progress * 100))
                            .font(.caption2)
                            .foregroundStyle(reachedCap ? .orange : .secondary)
                    }
                }
            } else {
                Text(sub.limitNote).font(.caption2).foregroundStyle(.tertiary)
            }

            // 來源拆解
            if direct > 0 && fromFixed > 0 {
                HStack(spacing: 6) {
                    sourceTag("直接記錄", value: fmt(direct),    color: .green)
                    sourceTag("固定支出", value: fmt(fromFixed), color: .blue)
                    Spacer()
                }
            } else if fromFixed > 0 && direct == 0 {
                HStack {
                    sourceTag("來自固定支出", value: fmt(fromFixed), color: .blue)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func sourceTag(_ label: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.caption2.weight(.medium))
            Text(value).font(.caption2)
        }
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(color.opacity(0.12))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    // MARK: - 節稅項目提醒（升級：34pt 漸層圖示圓）

    private var deductionTipsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("節稅項目提醒", icon: "lightbulb.fill", color: Color(red: 1.00, green: 0.78, blue: 0.20))

            ForEach(Array(TaxSavingSubCategory.allCases.enumerated()), id: \.element) { idx, sub in
                let acc = taxSavingTotal(for: sub)
                let iconColor: Color = acc > 0 ? .green : .blue

                HStack(alignment: .top, spacing: 12) {
                    // 34pt 漸層圖示圓
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [iconColor.opacity(0.18), iconColor.opacity(0.07)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 34, height: 34)
                        Image(systemName: sub.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(iconColor)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("\(sub.rawValue)扣除額")
                                .font(.subheadline.weight(.semibold))
                            if acc > 0 {
                                Text("已累積 \(fmtShort(acc))")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Color.green.opacity(0.12))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Color.green.opacity(0.22), lineWidth: 0.6))
                            }
                        }
                        Text(sub.limitNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineSpacing(1)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)

                if idx < TaxSavingSubCategory.allCases.count - 1 {
                    Divider().padding(.leading, 62)
                }
            }
            .padding(.bottom, 4)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    // MARK: - 輔助：統一 section 標題（升級：Capsule 側條 + semibold + 可選計數膠囊）

    private func sectionHeader(_ title: String, icon: String, color: Color, count: Int? = nil) -> some View {
        HStack(spacing: 10) {
            // 左側 Capsule 側條（對齊 OverviewView categoryBreakdownSection）
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 18)

            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)

            Text(title)
                .font(.subheadline.weight(.semibold))

            Spacer()

            if let count = count {
                Text("\(count) 項")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(color.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.6))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - 格式化輔助

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f
    }()

    private func fmt(_ v: Double) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: v)) ?? "NT$0"
    }

    private func fmtShort(_ v: Double) -> String {
        if v >= 100_000_000 { return String(format: "%.1f億", v / 100_000_000) }
        if v >= 10_000 { return String(format: "%.0f萬", v / 10_000) }
        return fmt(v)
    }

    private static let fmtDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()

    private func fmtDate(_ d: Date) -> String {
        Self.fmtDateFormatter.string(from: d)
    }
}
