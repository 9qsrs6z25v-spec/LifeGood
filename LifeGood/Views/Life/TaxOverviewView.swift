import SwiftUI

struct TaxOverviewView: View {
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())

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

    // MARK: - 節稅紀錄

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

    /// 直接以「節稅」變動支出記錄的金額
    private func taxSavingDirectTotal(for sub: TaxSavingSubCategory) -> Double {
        taxSavingExpenses
            .filter { $0.taxSavingSubCategory == sub }
            .reduce(0) { $0 + $1.amount }
    }

    /// 從固定支出（保險 / 房貸 / 房租）依年度推斷出的累積金額
    private func taxSavingFromFixedTotal(for sub: TaxSavingSubCategory) -> Double {
        expenseStore.expenses
            .filter {
                $0.expenseType == .fixed &&
                $0.effectivelyTaxDeductible &&
                $0.inferredTaxSavingSubCategory == sub
            }
            .reduce(0) { $0 + yearEquivalentAmount($1, year: selectedYear) }
    }

    /// 該子分類年度合計（直接記錄 + 固定支出推斷）
    private func taxSavingTotal(for sub: TaxSavingSubCategory) -> Double {
        taxSavingDirectTotal(for: sub) + taxSavingFromFixedTotal(for: sub)
    }

    /// 將固定支出依 recurrence 換算成「在 selectedYear 內」的累積金額。
    /// 規則：
    /// - 起始日 > selectedYear 12/31：0（還沒開始）
    /// - 起始日 < selectedYear 1/1：整年（每月 *12 / 每季 *4 / 每年 *1）
    /// - 起始日同年：從起始月起算
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
        case .yearly:    return exp.amount  // 整年算一次
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

    // 房屋稅 / 地價稅相關
    private var realEstateCount: Int { financeStore.realEstates.filter { !$0.isSold }.count }

    // 車輛相關
    private var vehicleCount: Int { financeStore.vehicles.filter { !$0.isSold }.count }

    // 年收入估算
    private var estimatedAnnualIncome: Double {
        expenseStore.incomes.reduce(0.0) { sum, inc in
            switch inc.period {
            case .monthly: return sum + inc.amount * 12
            case .yearly: return sum + inc.amount
            case .once:
                if Calendar.current.component(.year, from: inc.date) == selectedYear {
                    return sum + inc.amount
                }
                return sum
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    yearPicker
                    annualSummaryCard
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

    // MARK: - 年度選擇

    private var yearPicker: some View {
        HStack {
            Button { selectedYear -= 1 } label: {
                Image(systemName: "chevron.left").foregroundStyle(.green)
            }
            Spacer()
            Text("\(String(selectedYear)) 年度")
                .font(.headline)
            Spacer()
            Button { selectedYear += 1 } label: {
                Image(systemName: "chevron.right").foregroundStyle(.green)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 年度摘要

    private var annualSummaryCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("年度稅費支出").font(.subheadline).foregroundStyle(.secondary)
                    Text(fmt(totalTax)).font(.title2.bold()).foregroundStyle(.red)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("預估年收入").font(.subheadline).foregroundStyle(.secondary)
                    Text(fmt(estimatedAnnualIncome)).font(.title3.bold()).foregroundStyle(.green)
                }
            }

            Divider()

            HStack(spacing: 20) {
                taxStat(icon: "building.2.fill", label: "持有房產", value: "\(realEstateCount) 筆", color: .blue)
                taxStat(icon: "car.fill", label: "持有車輛", value: "\(vehicleCount) 台", color: .orange)
                taxStat(icon: "doc.text.fill", label: "稅費筆數", value: "\(taxExpenses.count) 筆", color: .red)
                taxStat(icon: "lightbulb.fill", label: "節稅累積", value: fmt(totalTaxSaving), color: .green)
            }

            if estimatedAnnualIncome > 0 {
                HStack {
                    Text("稅費佔收入比").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    let ratio = totalTax / estimatedAnnualIncome * 100
                    Text(String(format: "%.1f%%", ratio))
                        .font(.caption.bold())
                        .foregroundStyle(ratio > 10 ? .red : .green)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func taxStat(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(value).font(.caption.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 稅費紀錄

    private var taxRecordsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("稅費紀錄", icon: "list.bullet.rectangle", color: .red)

            if taxExpenses.isEmpty {
                Text("本年度尚無稅費紀錄").font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal).padding(.bottom, 12)
            } else {
                ForEach(taxExpenses) { exp in
                    HStack {
                        Text(fmtDate(exp.date)).font(.caption2).foregroundStyle(.tertiary)
                        Text(exp.title).font(.subheadline).lineLimit(1)
                        Spacer()
                        Text(fmt(exp.amount)).font(.subheadline.bold()).foregroundStyle(.red)
                    }
                    .padding(.horizontal).padding(.vertical, 6)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 月份分佈

    @ViewBuilder
    private var monthlyBreakdown: some View {
        if !taxByMonth.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("月份分佈", icon: "calendar", color: .blue)

                let maxAmount = taxByMonth.map(\.amount).max() ?? 1
                ForEach(taxByMonth, id: \.month) { item in
                    HStack(spacing: 8) {
                        Text("\(item.month)月").font(.caption).frame(width: 30, alignment: .trailing)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.red.opacity(0.6))
                                .frame(width: max(4, geo.size.width * CGFloat(item.amount / maxAmount)))
                        }
                        .frame(height: 16)
                        Text(fmt(item.amount)).font(.caption2).foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .trailing)
                    }
                    .padding(.horizontal).padding(.vertical, 3)
                }
                .padding(.bottom, 8)
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
        }
    }

    // MARK: - 年度稅務檢核

    private var taxChecklistSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("年度稅務檢核", icon: "checkmark.square", color: .green)

            let items: [(String, String, Bool)] = [
                ("5月", "綜合所得稅申報", selectedYear < Calendar.current.component(.year, from: Date())),
                ("5月", "房屋稅繳納", realEstateCount > 0),
                ("7月", "汽機車使用牌照稅", vehicleCount > 0),
                ("11月", "地價稅繳納", realEstateCount > 0),
                ("4月", "汽機車燃料費", vehicleCount > 0),
                ("全年", "二代健保補充保費", estimatedAnnualIncome > 0),
            ]

            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                HStack(spacing: 10) {
                    Image(systemName: item.2 ? "checkmark.circle.fill" : "circle")
                        .font(.subheadline)
                        .foregroundStyle(item.2 ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.1).font(.subheadline)
                        Text(item.0).font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if item.2 {
                        Text("應注意").font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12))
                            .foregroundStyle(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                .padding(.horizontal).padding(.vertical, 8)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 節稅累積（與變動支出 .taxSaving 連動）

    private var taxSavingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("節稅累積", icon: "lightbulb.fill", color: .green)

            if totalTaxSaving == 0 {
                Text("本年度尚無節稅紀錄。可在「變動支出」分類選「節稅」新增；既有的保險、房貸、房租固定支出也會自動納入。")
                    .font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal).padding(.bottom, 12)
            } else {
                HStack {
                    Text("年度節稅總額")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(fmt(totalTaxSaving))
                        .font(.title3.bold())
                        .foregroundStyle(.green)
                }
                .padding(.horizontal).padding(.vertical, 6)
                Divider()
                ForEach(TaxSavingSubCategory.allCases) { sub in
                    let total = taxSavingTotal(for: sub)
                    if total > 0 {
                        taxSavingRow(sub: sub, total: total)
                        Divider().padding(.leading, 44)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func taxSavingRow(sub: TaxSavingSubCategory, total: Double) -> some View {
        let limit = sub.annualLimit
        let progress: Double = {
            guard let limit = limit, limit > 0 else { return 0 }
            return min(1, total / limit)
        }()
        let reachedCap = limit != nil && total >= (limit ?? 0)
        let direct = taxSavingDirectTotal(for: sub)
        let fromFixed = taxSavingFromFixedTotal(for: sub)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: sub.icon)
                    .font(.subheadline).foregroundStyle(.green)
                    .frame(width: 22)
                Text(sub.rawValue).font(.subheadline.weight(.medium))
                Spacer()
                Text(fmt(total))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(reachedCap ? .orange : .green)
            }
            if let limit = limit {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(.tertiarySystemFill))
                            .frame(height: 5)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(reachedCap ? Color.orange : Color.green)
                            .frame(width: geo.size.width * CGFloat(progress), height: 5)
                    }
                }
                .frame(height: 5)
                HStack {
                    Text("上限 \(fmt(limit))")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    Text(reachedCap ? "已達上限" : String(format: "%.0f%%", progress * 100))
                        .font(.caption2)
                        .foregroundStyle(reachedCap ? .orange : .secondary)
                }
            } else {
                Text(sub.limitNote).font(.caption2).foregroundStyle(.tertiary)
            }
            // 來源拆解：直接記錄 / 來自固定支出
            if direct > 0 && fromFixed > 0 {
                HStack(spacing: 6) {
                    sourceTag("直接記錄", value: fmt(direct), color: .green)
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
        .padding(.horizontal).padding(.vertical, 8)
    }

    private func sourceTag(_ label: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.caption2.weight(.medium))
            Text(value).font(.caption2)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.12))
        .foregroundStyle(color)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - 節稅建議（含已累積金額）

    private var deductionTipsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("節稅項目提醒", icon: "lightbulb.fill", color: .yellow)

            ForEach(TaxSavingSubCategory.allCases) { sub in
                let acc = taxSavingTotal(for: sub)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: sub.icon)
                        .font(.caption).foregroundStyle(acc > 0 ? .green : .blue)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("\(sub.rawValue)扣除額").font(.subheadline.weight(.medium))
                            if acc > 0 {
                                Text("已累積 \(fmt(acc))")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Color.green.opacity(0.15))
                                    .foregroundStyle(.green)
                                    .clipShape(Capsule())
                            }
                        }
                        Text(sub.limitNote).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal).padding(.vertical, 8)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 輔助

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(color)
            Text(title).font(.headline)
            Spacer()
        }
        .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "NT$0"
    }

    private func fmtDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f.string(from: d)
    }
}
