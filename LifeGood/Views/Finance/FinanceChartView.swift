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
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("資產配置分布", icon: "chart.pie.fill", color: .purple)

            let allocations = store.assetAllocations
            if allocations.isEmpty {
                emptyPlaceholder(icon: "chart.pie", title: "尚無資產資料", subtitle: "新增資產後顯示配置分布")
            } else {
                ZStack {
                    Chart(allocations) { a in
                        SectorMark(
                            angle: .value("金額", a.value),
                            innerRadius: .ratio(0.52),
                            angularInset: 1.8
                        )
                        .foregroundStyle(colorFor(a.type))
                        .cornerRadius(4)
                    }
                    .frame(height: 200)
                    .padding(.horizontal)

                    // 甜甜圈中心：總資產
                    VStack(spacing: 2) {
                        Text("總資產")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(fmtShort(allocations.reduce(0) { $0 + $1.value }))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .minimumScaleFactor(0.65)
                            .lineLimit(1)
                            .frame(maxWidth: 80)
                    }
                }

                // 圖例：彩色圓形圖示 + 類別名 + 金額
                VStack(spacing: 8) {
                    let grandTotal = allocations.reduce(0) { $0 + $1.value }
                    ForEach(allocations) { a in
                        let color = colorFor(a.type)
                        let pct = grandTotal > 0 ? a.value / grandTotal * 100 : 0
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [color.opacity(0.22), color.opacity(0.09)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 30, height: 30)
                                Image(systemName: iconFor(a.type))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(color)
                            }
                            Text(a.type.rawValue)
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text(fmtShort(a.value))
                                .font(.caption.bold())
                            Text(String(format: "%.1f%%", pct))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(color)
                                .padding(.horizontal, 6).padding(.vertical, 2.5)
                                .background(color.opacity(0.10))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 18)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    // MARK: - 股票績效

    private var stockPerformanceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("股票損益分析", icon: "chart.line.uptrend.xyaxis", color: .orange)

            if store.stocks.isEmpty {
                emptyPlaceholder(icon: "chart.bar.xaxis", title: "尚無股票資料", subtitle: "新增股票後顯示損益分析")
            } else {
                // 加總損益摘要卡
                let totalPL = store.stocks.reduce(0.0) { $0 + $1.profitLoss }
                let plColor: Color = totalPL >= 0 ? .green : .red
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(plColor.opacity(0.14))
                            .frame(width: 40, height: 40)
                        Image(systemName: totalPL >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(plColor)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("加總損益")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text((totalPL >= 0 ? "+" : "") + fmt(totalPL))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(plColor)
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    Text("\(store.stocks.count) 檔")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(plColor)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(plColor.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(plColor.opacity(0.22), lineWidth: 0.75))
                }
                .padding(.horizontal)

                // 橫軸可滑動長條圖
                let visibleCount = min(store.stocks.count, 5)
                Chart(store.stocks) { stock in
                    BarMark(
                        x: .value("股票", stock.name),
                        y: .value("損益", stock.profitLoss)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: stock.profitLoss >= 0
                                ? [Color.green, Color.green.opacity(0.65)]
                                : [Color.red, Color.red.opacity(0.65)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .cornerRadius(5)
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
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: visibleCount)
                .frame(height: 200)
                .padding(.horizontal)

                // 明細列
                let sortedStocks = store.stocks.sorted { $0.profitLoss > $1.profitLoss }
                VStack(spacing: 0) {
                    ForEach(Array(sortedStocks.enumerated()), id: \.element.id) { i, stock in
                        let pl = stock.profitLoss
                        let plC: Color = pl >= 0 ? .green : .red

                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(plC.opacity(0.12))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(plC)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stock.name)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(stock.symbol)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text((pl >= 0 ? "+" : "") + fmt(pl))
                                    .font(.subheadline.bold())
                                    .foregroundStyle(plC)
                                    .contentTransition(.numericText())
                                Text(String(format: "%@%.1f%%", stock.returnRate >= 0 ? "+" : "", stock.returnRate))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(plC.opacity(0.80))
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)

                        if i < sortedStocks.count - 1 {
                            Divider().padding(.leading, 60)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 18)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    // MARK: - 房地產績效

    private var realEstatePerformanceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("房地產績效", icon: "building.2.fill", color: .indigo)

            if store.realEstates.isEmpty {
                emptyPlaceholder(icon: "building.2", title: "尚無房地產資料", subtitle: "新增房地產後顯示績效")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.realEstates.enumerated()), id: \.element.id) { i, item in
                        let appColor: Color = item.appreciationRate >= 0 ? .green : .red

                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.indigo.opacity(0.18), Color.indigo.opacity(0.07)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 40, height: 40)
                                Image(systemName: "building.2.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.indigo)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    HStack(spacing: 3) {
                                        Image(systemName: item.appreciationRate >= 0 ? "arrow.up.right" : "arrow.down.right")
                                            .font(.system(size: 8, weight: .bold))
                                        Text(String(format: "%@%.1f%%", item.appreciationRate >= 0 ? "+" : "", item.appreciationRate))
                                            .font(.system(size: 10, weight: .semibold))
                                    }
                                    .foregroundStyle(appColor)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(appColor.opacity(0.10))
                                    .clipShape(Capsule())

                                    if item.monthlyRental > 0 {
                                        HStack(spacing: 3) {
                                            Image(systemName: "house.fill")
                                                .font(.system(size: 8))
                                            Text(String(format: "%.1f%% 租報", item.rentalYield))
                                                .font(.system(size: 10, weight: .medium))
                                        }
                                        .foregroundStyle(.blue)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.08))
                                        .clipShape(Capsule())
                                    }
                                }
                            }

                            Spacer()

                            Text(fmtShort(item.currentValue))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText())
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 11)

                        if i < store.realEstates.count - 1 {
                            Divider().padding(.leading, 64)
                        }

                    }
                }
            }
        }
        .padding(.vertical, 18)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    // MARK: - 儲蓄險摘要

    private var insuranceSummarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("儲蓄險摘要", icon: "shield.fill", color: .blue)

            if store.insurances.isEmpty {
                emptyPlaceholder(icon: "shield", title: "尚無儲蓄險資料", subtitle: "新增儲蓄險後顯示摘要")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.insurances.enumerated()), id: \.element.id) { i, item in
                        let rateColor: Color = item.returnRate >= 0 ? .green : .red

                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue.opacity(0.20), Color.blue.opacity(0.08)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 40, height: 40)
                                Image(systemName: "shield.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.blue)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                HStack(spacing: 5) {
                                    Text("已繳 \(fmtShort(item.totalPaid))")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color(.tertiarySystemFill))
                                        .clipShape(Capsule())
                                    if item.returnRate != 0 {
                                        Text(String(format: "預估 %@%.1f%%", item.returnRate >= 0 ? "+" : "", item.returnRate))
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(rateColor)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(rateColor.opacity(0.10))
                                            .clipShape(Capsule())
                                    }
                                }
                            }

                            Spacer()

                            Text(fmtShort(item.currentValue))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText())
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 11)

                        if i < store.insurances.count - 1 {
                            Divider().padding(.leading, 64)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 18)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    // MARK: - 共用元件

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 20)
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.weight(.bold))
            Spacer()
        }
        .padding(.horizontal)
    }

    private func emptyPlaceholder(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(.secondarySystemFill), Color(.systemFill)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                Circle()
                    .stroke(Color(.separator).opacity(0.30), lineWidth: 1)
                    .frame(width: 64, height: 64)
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Color(.secondaryLabel))
            }
            VStack(spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
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

    private func iconFor(_ type: AssetType) -> String {
        switch type {
        case .savingsInsurance: return "shield.fill"
        case .stock: return "chart.line.uptrend.xyaxis"
        case .vehicle: return "car.fill"
        case .realEstate: return "building.2.fill"
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
