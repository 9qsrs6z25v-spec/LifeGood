import SwiftUI

struct FinanceOverviewView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @State private var showAddVariable = false
    @State private var showAddFixed = false
    @State private var showAddStock = false
    @State private var showAddRealEstate = false

    private func rateForCode(_ code: String) -> Double {
        if code == "NT$" { return 1 }
        return expenseStore.currencyRates.first(where: { $0.code == code })?.rate ?? 1
    }

    private var insuranceValueNTD: Double {
        store.insurances.reduce(0) { $0 + $1.currentValue * rateForCode($1.currencyCode) }
    }

    private var insurancePaidNTD: Double {
        store.insurances.reduce(0) { $0 + $1.totalPaid * rateForCode($1.currencyCode) }
    }

    private var insuranceProfitLoss: Double {
        insuranceValueNTD - insurancePaidNTD
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    totalAssetsCard
                    assetCards
                    allocationSection
                    cashFlowSection
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("理財總覽")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    quickAddMenu
                }
            }
            .sheet(isPresented: $showAddVariable) { AddExpenseView(expenseType: .variable) }
            .sheet(isPresented: $showAddFixed) { AddExpenseView(expenseType: .fixed) }
            .sheet(isPresented: $showAddStock) { AddStockView() }
            .sheet(isPresented: $showAddRealEstate) { AddRealEstateView() }
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

    private var totalAssetsNTD: Double {
        insuranceValueNTD + store.totalStockValue + store.totalVehicleValue + store.totalRealEstateValue
    }

    // MARK: - 總資產

    private var totalAssetsCard: some View {
        VStack(spacing: 8) {
            Text("總資產").font(.subheadline).foregroundStyle(.white.opacity(0.8))
            Text(fmt(totalAssetsNTD))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            LinearGradient(colors: [.green, .green.opacity(0.7)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 三大類

    private var stockProfitLoss: Double { store.totalStockProfitLoss }

    private var assetCards: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                assetCard(title: "儲蓄險", amount: insuranceValueNTD, profitLoss: insuranceProfitLoss,
                          icon: "shield.fill", color: .blue, count: store.insurances.count)
                assetCard(title: "股票", amount: store.totalStockValue, profitLoss: stockProfitLoss,
                          icon: "chart.line.uptrend.xyaxis", color: .orange, count: store.stocks.count)
            }
            HStack(spacing: 12) {
                assetCard(title: "汽車", amount: store.totalVehicleValue, profitLoss: nil,
                          icon: "car.fill", color: .teal, count: store.vehicles.count)
                assetCard(title: "房地產", amount: store.totalRealEstateValue, profitLoss: nil,
                          icon: "building.2.fill", color: .purple,
                          count: store.realEstates.filter { !$0.isSold }.count)
            }
        }
        .padding(.horizontal)
    }

    private func assetCard(title: String, amount: Double, profitLoss: Double?, icon: String, color: Color, count: Int) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(fmtShort(amount)).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.6)
            if let pl = profitLoss {
                Text((pl >= 0 ? "+" : "") + fmtShort(pl))
                    .font(.system(size: 10).bold())
                    .foregroundStyle(pl >= 0 ? .green : .red)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Text("\(count) 筆").font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }

    // MARK: - 配置比例

    private var ntdAllocations: [AssetAllocation] {
        let total = totalAssetsNTD
        guard total > 0 else { return [] }
        var result: [AssetAllocation] = []
        if insuranceValueNTD > 0 {
            result.append(AssetAllocation(type: .savingsInsurance, value: insuranceValueNTD, percentage: insuranceValueNTD / total * 100))
        }
        if store.totalStockValue > 0 {
            result.append(AssetAllocation(type: .stock, value: store.totalStockValue, percentage: store.totalStockValue / total * 100))
        }
        if store.totalVehicleValue > 0 {
            result.append(AssetAllocation(type: .vehicle, value: store.totalVehicleValue, percentage: store.totalVehicleValue / total * 100))
        }
        if store.totalRealEstateValue > 0 {
            result.append(AssetAllocation(type: .realEstate, value: store.totalRealEstateValue, percentage: store.totalRealEstateValue / total * 100))
        }
        return result.sorted { $0.value > $1.value }
    }

    private var allocationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("資產配置").font(.headline).padding(.horizontal)

            let allocations = ntdAllocations
            if allocations.isEmpty {
                Text("尚無資產資料").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                // 比例條
                HStack(spacing: 0) {
                    ForEach(allocations) { a in
                        Rectangle()
                            .fill(colorFor(a.type))
                            .frame(width: max(4, CGFloat(a.percentage / 100) * (UIScreen.main.bounds.width - 64)))
                    }
                }
                .frame(height: 12)
                .clipShape(Capsule())
                .padding(.horizontal)

                // 圖例
                VStack(spacing: 8) {
                    ForEach(allocations) { a in
                        HStack {
                            Circle().fill(colorFor(a.type)).frame(width: 10, height: 10)
                            Text(a.type.rawValue).font(.subheadline)
                            Spacer()
                            Text(fmtShort(a.value)).font(.subheadline.bold())
                            Text(String(format: "%.1f%%", a.percentage))
                                .font(.caption).foregroundStyle(.secondary).frame(width: 50, alignment: .trailing)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        .padding(.horizontal)
    }

    // MARK: - 現金流

    private var cashFlowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("每月現金流").font(.headline).padding(.horizontal)

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("租金收入").font(.caption).foregroundStyle(.secondary)
                    Text(fmtShort(store.monthlyRentalIncome)).font(.subheadline.bold()).foregroundStyle(.green)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("房貸支出").font(.caption).foregroundStyle(.secondary)
                    Text(fmtShort(store.monthlyMortgagePayment)).font(.subheadline.bold()).foregroundStyle(.red)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("淨現金流").font(.caption).foregroundStyle(.secondary)
                    let flow = store.monthlyCashFlow
                    Text(fmtShort(flow)).font(.subheadline.bold()).foregroundStyle(flow >= 0 ? .green : .red)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        .padding(.horizontal)
    }

    // MARK: - Helpers

    private func colorFor(_ type: AssetType) -> Color {
        switch type {
        case .savingsInsurance: return .blue
        case .stock: return .orange
        case .vehicle: return .teal
        case .realEstate: return .purple
        }
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "NT$0"
    }

    private func fmtShort(_ v: Double) -> String {
        if v >= 100_000_000 { return String(format: "%.1f億", v / 100_000_000) }
        if v >= 10_000 { return String(format: "%.0f萬", v / 10_000) }
        return fmt(v)
    }
}
