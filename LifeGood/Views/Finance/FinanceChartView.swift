import SwiftUI
import Charts

struct FinanceChartView: View {
    @EnvironmentObject var store: FinanceStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    allocationChart
                    stockPerformanceSection
                    realEstatePerformanceSection
                    insuranceSummarySection
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("理財圖表")
        }
    }

    // MARK: - 資產配置圖

    private var allocationChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("資產配置分布").font(.headline).padding(.horizontal)

            let allocations = store.assetAllocations
            if allocations.isEmpty {
                Text("尚無資產資料").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart(allocations) { a in
                    SectorMark(
                        angle: .value("金額", a.value),
                        innerRadius: .ratio(0.5),
                        angularInset: 2
                    )
                    .foregroundStyle(colorFor(a.type))
                    .annotation(position: .overlay) {
                        Text(String(format: "%.0f%%", a.percentage))
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                    }
                }
                .frame(height: 220)
                .padding(.horizontal)

                // 圖例
                HStack(spacing: 20) {
                    ForEach(allocations) { a in
                        HStack(spacing: 4) {
                            Circle().fill(colorFor(a.type)).frame(width: 8, height: 8)
                            Text(a.type.rawValue).font(.caption)
                            Text(fmtShort(a.value)).font(.caption.bold())
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

    // MARK: - 股票績效

    private var stockPerformanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("股票損益分析").font(.headline).padding(.horizontal)

            if store.stocks.isEmpty {
                Text("尚無股票資料").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                Chart(store.stocks) { stock in
                    BarMark(
                        x: .value("股票", stock.name),
                        y: .value("損益", stock.profitLoss)
                    )
                    .foregroundStyle(stock.profitLoss >= 0 ? Color.green : Color.red)
                    .cornerRadius(4)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(abbreviate(v)).font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 200)
                .padding(.horizontal)

                // 明細
                VStack(spacing: 0) {
                    ForEach(store.stocks.sorted(by: { $0.profitLoss > $1.profitLoss })) { stock in
                        HStack {
                            Text(stock.name).font(.caption)
                            if !stock.symbol.isEmpty {
                                Text(stock.symbol).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            let pl = stock.profitLoss
                            Text((pl >= 0 ? "+" : "") + fmt(pl))
                                .font(.caption.bold())
                                .foregroundStyle(pl >= 0 ? .green : .red)
                            Text(String(format: "(%@%.1f%%)", stock.returnRate >= 0 ? "+" : "", stock.returnRate))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal).padding(.vertical, 6)
                    }
                }
            }
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        .padding(.horizontal)
    }

    // MARK: - 房地產績效

    private var realEstatePerformanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("房地產績效").font(.headline).padding(.horizontal)

            if store.realEstates.isEmpty {
                Text("尚無房地產資料").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.realEstates) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.name).font(.subheadline.weight(.medium))
                                Spacer()
                                Text(fmt(item.currentValue)).font(.subheadline.bold())
                            }
                            HStack {
                                HStack(spacing: 4) {
                                    Text("增值")
                                    Text(String(format: "%@%.1f%%", item.appreciationRate >= 0 ? "+" : "", item.appreciationRate))
                                        .foregroundStyle(item.appreciationRate >= 0 ? .green : .red)
                                }
                                Spacer()
                                if item.monthlyRental > 0 {
                                    HStack(spacing: 4) {
                                        Text("租金報酬率")
                                        Text(String(format: "%.1f%%", item.rentalYield))
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal).padding(.vertical, 8)
                        if item.id != store.realEstates.last?.id {
                            Divider().padding(.leading)
                        }
                    }
                }
            }
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        .padding(.horizontal)
    }

    // MARK: - 儲蓄險摘要

    private var insuranceSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("儲蓄險摘要").font(.headline).padding(.horizontal)

            if store.insurances.isEmpty {
                Text("尚無儲蓄險資料").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.insurances) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.subheadline.weight(.medium))
                                Text("已繳 " + fmt(item.totalPaid)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(fmt(item.currentValue)).font(.subheadline.bold())
                                if item.returnRate != 0 {
                                    Text(String(format: "預估報酬 %.1f%%", item.returnRate))
                                        .font(.caption2)
                                        .foregroundStyle(item.returnRate >= 0 ? .green : .red)
                                }
                            }
                        }
                        .padding(.horizontal).padding(.vertical, 8)
                        if item.id != store.insurances.last?.id {
                            Divider().padding(.leading)
                        }
                    }
                }
            }
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

    private func abbreviate(_ v: Double) -> String {
        if abs(v) >= 10_000 { return String(format: "%.0f萬", v / 10_000) }
        if abs(v) >= 1000 { return String(format: "%.0fk", v / 1000) }
        return String(format: "%.0f", v)
    }
}
