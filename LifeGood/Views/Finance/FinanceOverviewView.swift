import SwiftUI

struct FinanceOverviewView: View {
    @EnvironmentObject var store: FinanceStore

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
        }
    }

    // MARK: - 總資產

    private var totalAssetsCard: some View {
        VStack(spacing: 8) {
            Text("總資產").font(.subheadline).foregroundStyle(.white.opacity(0.8))
            Text(fmt(store.totalAssets))
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

    private var assetCards: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                assetCard(title: "儲蓄險", amount: store.totalInsuranceValue,
                          icon: "shield.fill", color: .blue, count: store.insurances.count)
                assetCard(title: "股票", amount: store.totalStockValue,
                          icon: "chart.line.uptrend.xyaxis", color: .orange, count: store.stocks.count)
            }
            HStack(spacing: 12) {
                assetCard(title: "汽車", amount: store.totalVehicleValue,
                          icon: "car.fill", color: .teal, count: store.vehicles.count)
                assetCard(title: "房地產", amount: store.totalRealEstateValue,
                          icon: "building.2.fill", color: .purple, count: store.realEstates.count)
            }
        }
        .padding(.horizontal)
    }

    private func assetCard(title: String, amount: Double, icon: String, color: Color, count: Int) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(fmtShort(amount)).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.6)
            Text("\(count) 筆").font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }

    // MARK: - 配置比例

    private var allocationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("資產配置").font(.headline).padding(.horizontal)

            let allocations = store.assetAllocations
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
                            Text(fmt(a.value)).font(.subheadline.bold())
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
                    Text(fmt(store.monthlyRentalIncome)).font(.subheadline.bold()).foregroundStyle(.green)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("房貸支出").font(.caption).foregroundStyle(.secondary)
                    Text(fmt(store.monthlyMortgagePayment)).font(.subheadline.bold()).foregroundStyle(.red)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("淨現金流").font(.caption).foregroundStyle(.secondary)
                    let flow = store.monthlyCashFlow
                    Text(fmt(flow)).font(.subheadline.bold()).foregroundStyle(flow >= 0 ? .green : .red)
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
