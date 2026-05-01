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
            Text(label).font(.caption2).foregroundStyle(.secondary)
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

    // MARK: - 節稅建議

    private var deductionTipsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("節稅項目提醒", icon: "lightbulb.fill", color: .yellow)

            let tips: [(icon: String, title: String, detail: String)] = [
                ("heart.text.square", "保險費扣除額", "每人每年最高 2.4 萬（人身保險），全民健保無上限"),
                ("house.fill", "房貸利息扣除額", "自用住宅貸款利息，每年最高扣除 30 萬"),
                ("cross.case.fill", "醫藥費扣除額", "全家醫療及生育費用，核實認列無上限"),
                ("gift.fill", "捐贈扣除額", "對政府或教育機構捐贈，所得 20% 以內可扣"),
                ("graduationcap.fill", "教育學費扣除額", "大專以上子女學費，每人每年最高 2.5 萬"),
                ("figure.child", "幼兒學前扣除額", "5 歲以下子女，每人每年 12 萬"),
                ("building.2.fill", "房租支出扣除額", "無自有住宅者，每年最高扣除 18 萬"),
                ("banknote.fill", "薪資所得特別扣除額", "每人每年 20.7 萬"),
                ("person.fill", "身心障礙扣除額", "每人每年 20.7 萬"),
                ("dollarsign.circle", "長期照顧扣除額", "每人每年 12 萬"),
            ]

            ForEach(tips.indices, id: \.self) { i in
                let tip = tips[i]
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: tip.icon)
                        .font(.caption).foregroundStyle(.blue)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tip.title).font(.subheadline.weight(.medium))
                        Text(tip.detail).font(.caption).foregroundStyle(.secondary)
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
